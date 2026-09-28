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
    local area = self._area
    if not area then return end
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
        local node = UI.TreeNode.new({
            x = 0, y = 0, width = self._area.width - 8, height = UI.Theme.LineHeight,
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
    if not self._area then return end
    for _, root in ipairs(getRoots()) do
        local node = UI.TreeNode.new({
            x = 0, y = 0, width = self._area.width - 8, height = UI.Theme.LineHeight,
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
    local area = UI.MainWindow.getTreeArea()
    Explorer._area = area
    local tabs = UI.MainWindow.getTabContainer()
    local holder = UI.Widget.new({x = area.x, y = area.y, width = area.width, height = area.height, zIndex = 115})
    holder.redraw = function() end
    Explorer._holder = holder
    Explorer._search = UI.TextInput.new({x = area.x, y = area.y, width = area.width - 90, height = 24,
        placeholder = "Filter by name...", zIndex = 121,
        onChange = function(t) Explorer._filter = t:lower() Explorer:_layout() end})
    Explorer._refreshBtn = UI.Button.new({x = area.x + area.width - 80, y = area.y, width = 80, height = 24,
        text = "Refresh", zIndex = 121, onClick = function() Explorer:refresh() end})
    Explorer._scroll = UI.ScrollContainer.new({x = area.x, y = area.y + 28, width = area.width,
        height = area.height - 28, zIndex = 120, itemHeight = UI.Theme.LineHeight,
        onScroll = function() Explorer:_layout() end})
    Explorer._area = {x = area.x, y = area.y + 28, width = area.width, height = area.height - 28}
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
    local area = UI.MainWindow.getTreeArea()
    if not area or not Explorer._scroll then return end
    Explorer._search:setPosition(area.x, area.y)
    Explorer._refreshBtn:setPosition(area.x + area.width - 80, area.y)
    Explorer._scroll:setPosition(area.x, area.y + 28)
    Explorer._area = {x = area.x, y = area.y + 28, width = area.width, height = area.height - 28}
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
