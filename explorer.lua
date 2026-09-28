--[[ Analyzer — Explorer: lazy-load instance tree ]]
local Analyzer = getgenv().Analyzer
if not Analyzer then error("[Analyzer] Explorer loaded before loader.") return end
local UI = Analyzer.UI
if not UI then error("[Analyzer] Explorer needs UI first.") return end

local Explorer = {}
Analyzer.Explorer = Explorer
Explorer._nodes = {} -- flat visible rows {node=TreeNode, depth}
Explorer._selected = nil
Explorer._conns = {}

local function getRoots()
    local roots = {}
    local names = {"Workspace","Players","Lighting","ReplicatedStorage","ReplicatedFirst",
        "ServerStorage","StarterGui","StarterPack","SoundService","TweenService","HttpService"}
    for _, n in ipairs(names) do
        local ok, svc = pcall(game.GetService, game, n)
        if ok and svc then table.insert(roots, svc) end
    end
    if #roots == 0 then -- ponytail: fallback, full svc list when GetService fails
        for _, c in ipairs(game:GetChildren()) do table.insert(roots, c) end
    end
    return roots
end

local function hasKids(inst)
    local ok, kids = pcall(function() return inst:GetChildren() end)
    return ok and kids and #kids > 0
end

function Explorer:_layout()
    -- ponytail: v2 — box read live from layout authority every pass, never stored
    local box = UI._treeArea
    if not box or not self._scroll then return end
    local area = {x = box.x, y = box.y + 28, width = box.width, height = box.height - 28}
    local show = Analyzer._visible and self._tabActive
    local f = self._filter or ""
    local y = area.y - self._scroll._scrollOffset
    local shown = 0
    for _, row in ipairs(self._nodes) do
        local match = f == "" or row.node._instance.Name:lower():find(f, 1, true)
        if match then
            row.node:updatePosition(area.x, y)
            row.node:setVisible(show and y >= area.y - 20 and y < area.y + area.height)
            y = y + UI.Theme.LineHeight
            shown = shown + 1
        else
            row.node:setVisible(false)
        end
    end
    self._scroll:setContentHeight(shown * UI.Theme.LineHeight)
    if self._search then self._search:setVisible(show) end
    if self._refreshBtn then self._refreshBtn:setVisible(show) end
end

function Explorer:_insertChildren(parentRow, parentNode)
    local inst = parentNode._instance
    local ok, kids = pcall(function() return inst:GetChildren() end)
    if not ok then return end
    table.sort(kids, function(a, b) return a.Name < b.Name end)
    local idx = 0
    for i, row in ipairs(self._nodes) do if row.node == parentNode then idx = i break end end
    for j = #kids, 1, -1 do -- insert in order after parent
        local child = kids[j]
        local w = (UI._treeArea and UI._treeArea.width or 300) - 8
        local node = UI.TreeNode.new({
            x = 0, y = 0, width = w, height = UI.Theme.LineHeight,
            instance = child, text = child.Name, depth = parentRow.depth + 1,
            className = child.ClassName, hasChildren = hasKids(child),
            zIndex = 120,
            onSelect = function(n) self:select(n._instance, n) end,
            onExpand = function(n) self:_onExpand(n) end,
            onCollapse = function(n) self:_onCollapse(n) end,
        })
        table.insert(self._nodes, idx + 1, {node = node, depth = parentRow.depth + 1})
        table.insert(parentNode._childNodes, node)
    end
    self:_layout()
end

function Explorer:_onExpand(node)
    local row
    for _, r in ipairs(self._nodes) do if r.node == node then row = r break end end
    if row then self:_insertChildren(row, node) end
    -- ponytail: no auto-refresh on ChildAdded (full refresh collapses the tree
    -- and thrashes on spammy games); Refresh button re-syncs on demand
    node._hasChildren = true
end

function Explorer:_onCollapse(_node) self:_layout() end

function Explorer:select(inst, node)
    if self._selected and self._selected.setSelected then
        pcall(function() self._selected:setSelected(false) end)
    end
    self._selected = node
    if node then pcall(function() node:setSelected(true) end) end
    Analyzer.Signals.InstanceSelected:Fire(inst)
    Analyzer.Signals.ScriptRequested:Fire(inst)
end

function Explorer:refresh()
    for _, row in ipairs(self._nodes) do pcall(function() row.node:destroy() end) end
    self._nodes = {}
    self._selected = nil
    local box = UI._treeArea
    if not box then return end
    for _, root in ipairs(getRoots()) do
        local node = UI.TreeNode.new({
            x = 0, y = 0, width = box.width - 8, height = UI.Theme.LineHeight,
            instance = root, text = root.Name, depth = 0,
            className = root.ClassName, hasChildren = hasKids(root), zIndex = 120,
            onSelect = function(n) self:select(n._instance, n) end,
            onExpand = function(n) self:_onExpand(n) end,
            onCollapse = function(n) self:_onCollapse(n) end,
        })
        table.insert(self._nodes, {node = node, depth = 0})
    end
    self:_layout()
end

function Explorer.init()
    -- ponytail: v2 — tops parented to tree pane with RELATIVE coords; cascade moves them
    local pane = UI.MainWindow.getTreePane()
    local box = UI._treeArea
    local tabs = UI.MainWindow.getTabContainer()
    local holder = UI.Widget.new({x = 0, y = 0, width = box.width, height = box.height, zIndex = 115})
    holder.redraw = function() end
    if pane then pane:addChild(holder) end
    Explorer._holder = holder
    Explorer._search = UI.TextInput.new({x = 0, y = 0, width = box.width - 90, height = 24,
        placeholder = "Filter by name...", zIndex = 121,
        onChange = function(t) Explorer._filter = t:lower() Explorer:_layout() end})
    Explorer._refreshBtn = UI.Button.new({x = box.width - 80, y = 0, width = 80, height = 24,
        text = "Refresh", zIndex = 121, onClick = function() Explorer:refresh() end})
    Explorer._scroll = UI.ScrollContainer.new({x = 0, y = 28, width = box.width,
        height = box.height - 28, zIndex = 120, itemHeight = UI.Theme.LineHeight,
        onScroll = function() Explorer:_layout() end})
    if pane then
        pane:addChild(Explorer._search)
        pane:addChild(Explorer._refreshBtn)
        pane:addChild(Explorer._scroll)
    end
    tabs:registerContent("Explorer", holder)
    -- show/hide with tab: hook visibility via TabChanged
    table.insert(Explorer._conns, Analyzer.Signals.TabChanged:Connect(function(name)
        Explorer._tabActive = true -- tree pane is always visible in single-menu layout
        Explorer:_layout()
    end))
    Explorer._tabActive = true -- default tab
    Explorer:refresh()
    Explorer._search:setVisible(false) Explorer._refreshBtn:setVisible(false)
    print("[Analyzer] Explorer initialized")
end

function Explorer.move()
    -- ponytail: v2 — tops ride the pane cascade; only flat rows need relayout
    Explorer:_layout()
end

function Explorer.cleanup()
    for _, c in ipairs(Explorer._conns) do pcall(function() c.Disconnect(c) end) end
    Explorer._conns = {}
    for _, row in ipairs(Explorer._nodes) do pcall(function() row.node:destroy() end) end
    Explorer._nodes = {}
    Explorer._selected = nil
end

return Explorer
