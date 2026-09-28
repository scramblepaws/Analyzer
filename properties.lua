--[[ Analyzer — Properties: live snapshot + GetPropertyChangedSignal ]]
local Analyzer = getgenv().Analyzer
if not Analyzer then error("[Analyzer] Properties loaded before loader.") return end
local UI = Analyzer.UI
if not UI then error("[Analyzer] Properties needs UI first.") return end

local Properties = {}
Analyzer.Properties = Properties
Properties._items = {}
Properties._propConns = {}
Properties._current = nil

-- ponytail: curated fallback, extend when a ClassName is missing
local FALLBACK = {
    Part = {"Name","ClassName","Position","Size","Anchored","CanCollide","Transparency","Color","Material","Parent"},
    Model = {"Name","ClassName","PrimaryPart","Parent"},
    Script = {"Name","ClassName","Enabled","RunContext","Parent"},
    LocalScript = {"Name","ClassName","Enabled","Parent"},
    ModuleScript = {"Name","ClassName","Parent"},
    RemoteEvent = {"Name","ClassName","Parent"},
    RemoteFunction = {"Name","ClassName","Parent"},
    TextLabel = {"Name","ClassName","Text","TextColor3","BackgroundColor3","Visible","Parent"},
    Frame = {"Name","ClassName","BackgroundColor3","Visible","Size","Position","Parent"},
}
local GENERIC = {"Name","ClassName","Parent"}

local function serialize(v)
    local t = typeof(v)
    if t == "Vector3" then return string.format("%.1f, %.1f, %.1f", v.X, v.Y, v.Z)
    elseif t == "Color3" then return string.format("#%02X%02X%02X", v.R*255, v.G*255, v.B*255)
    elseif t == "Instance" then return v and v:GetFullName() or "nil"
    elseif t == "EnumItem" then return tostring(v) end
    local ok, s = pcall(tostring, v)
    return ok and (s:sub(1, 80)) or "?"
end

local function propNames(inst)
    local gp = getgenv().getproperties or getgenv().getprops
    if type(gp) == "function" then
        local ok, list = pcall(gp, inst)
        if ok and type(list) == "table" then
            local out = {}
            for k in pairs(list) do table.insert(out, tostring(k)) end
            table.sort(out)
            return out
        end
    end
    return FALLBACK[inst.ClassName] or GENERIC
end

function Properties:clear()
    for _, c in ipairs(self._propConns) do pcall(function() c:Disconnect() end) end
    self._propConns = {}
    for _, it in ipairs(self._items) do pcall(function() it:destroy() end) end
    self._items = {}
end

function Properties:show(inst)
    self:clear()
    self._current = inst
    self._tabActive = true -- ponytail: show() implies tab switch (signal is async)
    if not inst or not self._area then return end
    local names = propNames(inst)
    local y0 = self._area.y - self._scroll._scrollOffset
    for i, pname in ipairs(names) do
        local ok, val = pcall(function() return inst[pname] end)
        local item = UI.ListItem.new({x = self._area.x, y = y0 + (i-1) * UI.Theme.LineHeight,
            width = self._area.width, height = UI.Theme.LineHeight,
            key = pname, value = ok and serialize(val) or "—", index = i, zIndex = 120})
        item:setVisible(Analyzer._visible)
        table.insert(self._items, item)
        -- live update; disconnect all on next show() (prevents leaks)
        pcall(function()
            local conn = inst:GetPropertyChangedSignal(pname):Connect(function()
                local ok2, v2 = pcall(function() return inst[pname] end)
                if ok2 then item:setKeyValue(pname, serialize(v2)) end
            end)
            table.insert(self._propConns, conn)
            table.insert(Analyzer._connections, conn)
        end)
    end
    self._scroll:setContentHeight(#names * UI.Theme.LineHeight)
    self:_layout()
end

function Properties:_layout()
    if not self._area then return end
    local show = Analyzer._visible and self._tabActive
    local y = self._area.y - self._scroll._scrollOffset
    for _, it in ipairs(self._items) do
        it:updatePosition(self._area.x, y)
        it:setVisible(show and y >= self._area.y - 20 and y < self._area.y + self._area.height)
        y = y + UI.Theme.LineHeight
    end
end

function Properties.init()
    local area = UI.MainWindow.getContentArea()
    Properties._area = area
    local tabs = UI.MainWindow.getTabContainer()
    local holder = UI.Widget.new({x = area.x, y = area.y, width = area.width, height = area.height, zIndex = 115})
    holder.redraw = function() end
    Properties._scroll = UI.ScrollContainer.new({x = area.x, y = area.y, width = area.width,
        height = area.height, zIndex = 120, itemHeight = UI.Theme.LineHeight,
        onScroll = function() Properties:_layout() end})
    tabs:registerContent("Properties", holder)
    table.insert(Analyzer._connections, Analyzer.Signals.InstanceSelected:Connect(function(inst)
        tabs:switchTab("Properties")
        Properties:show(inst)
    end))
    table.insert(Analyzer._connections, Analyzer.Signals.TabChanged:Connect(function(name)
        Properties._tabActive = (name == "Properties")
        Properties:_layout()
    end))
    Properties._tabActive = false
    print("[Analyzer] Properties initialized")
end

function Properties.cleanup() Properties:clear() end

return Properties
