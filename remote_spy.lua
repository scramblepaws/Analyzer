--[[ Analyzer — Remote Spy: __namecall hook, capped FIFO 500, one-line log ]]
local Analyzer = getgenv().Analyzer
if not Analyzer then error("[Analyzer] RemoteSpy loaded before loader.") return end
local UI = Analyzer.UI
if not UI then error("[Analyzer] RemoteSpy needs UI first.") return end

local Spy = {}
Analyzer.RemoteSpy = Spy
Spy._log = {}
Spy._paused = false
Spy._hooked = false
Spy.MAX = 500

local function serializeArgs(...)
    local out = {}
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        local t = typeof(v)
        local s
        if t == "Instance" then s = v:GetFullName()
        elseif t == "Vector3" then s = string.format("V3(%.1f,%.1f,%.1f)", v.X, v.Y, v.Z)
        elseif t == "string" then s = '"' .. v:sub(1, 60) .. '"'
        else local ok, r = pcall(tostring, v) s = ok and r:sub(1, 60) or "?" end
        table.insert(out, s)
    end
    return table.concat(out, ", ")
end

function Spy:_render()
    if not self._block then return end
    local lines = {}
    local f = (self._filter or ""):lower()
    for _, e in ipairs(self._log) do -- ponytail: newest at bottom, no expandable rows in v1
        local line = string.format("[%s] %s :: %s(%s)", e.dir, e.time, e.path, e.args)
        if f == "" or line:lower():find(f, 1, true) then table.insert(lines, line:sub(1, 160)) end
    end
    self._block:setContent(#lines > 0 and table.concat(lines, "\n") or "-- no remote calls captured yet")
end

function Spy:push(dir, remote, method, ...)
    if self._paused then return end
    table.insert(self._log, {dir = dir, time = os.date("%X"), path = remote:GetFullName(),
        args = (method ~= "" and method .. "; " or "") .. serializeArgs(...)})
    while #self._log > self.MAX do table.remove(self._log, 1) end -- FIFO cap
    Analyzer.Signals.RemoteLogged:Fire(self._log[#self._log])
    -- ponytail: throttle render to 3/sec; spammy games fire dozens/sec
    if Analyzer._visible and self._block then
        local now = os.clock()
        if now - (self._lastRender or 0) > 0.33 and not self._renderQueued then
            self._lastRender = now
            self:_render()
        elseif not self._renderQueued then
            self._renderQueued = true
            task.delay(0.33, function()
                self._renderQueued = false
                self._lastRender = os.clock()
                if Analyzer._visible then self:_render() end
            end)
        end
    end
end

function Spy:start()
    if self._hooked then return end
    local hmm = getgenv().hookmetamethod
    local ncm = getgenv().getnamecallmethod
    if type(hmm) ~= "function" then return end -- executor without hook: spy stays idle
    local old
    old = hmm(game, "__namecall", getgenv().newcclosure and getgenv().newcclosure(function(selfObj, ...)
        local method = ""
        if type(ncm) == "function" then local ok, m = pcall(ncm) if ok then method = m end end
        if (method == "FireServer" or method == "InvokeServer")
            and (selfObj:IsA("RemoteEvent") or selfObj:IsA("RemoteFunction")) then
            pcall(function() Spy:push("OUT", selfObj, method, ...) end)
        end
        return old(selfObj, ...)
    end) or function(selfObj, ...) return old(selfObj, ...) end)
    Analyzer._originalNamecall = old
    self._hooked = true
end

function Spy.init()
    local area = UI.MainWindow.getContentArea()
    local tabs = UI.MainWindow.getTabContainer()
    local holder = UI.Widget.new({x = area.x, y = area.y, width = area.width, height = area.height, zIndex = 115})
    holder.redraw = function() end
    Spy._filterBox = UI.TextInput.new({x = area.x + 8, y = area.y + 4, width = area.width - 260,
        height = 24, placeholder = "Filter...", zIndex = 121,
        onChange = function(t) Spy._filter = t Spy:_render() end})
    Spy._pauseBtn = UI.Button.new({x = area.x + area.width - 244, y = area.y + 4, width = 70, height = 24,
        text = "Pause", zIndex = 121, onClick = function(selfBtn)
            Spy._paused = not Spy._paused selfBtn:setText(Spy._paused and "Resume" or "Pause") end})
    Spy._clearBtn = UI.Button.new({x = area.x + area.width - 166, y = area.y + 4, width = 70, height = 24,
        text = "Clear", zIndex = 121, onClick = function() Spy._log = {} Spy:_render() end})
    Spy._copyBtn = UI.Button.new({x = area.x + area.width - 88, y = area.y + 4, width = 80, height = 24,
        text = "Copy", zIndex = 121, onClick = function()
            local sc = getgenv().setclipboard
            if type(sc) == "function" then pcall(sc, table.concat((function()
                local l = {} for _, e in ipairs(Spy._log) do table.insert(l, e.path) end return l end)(), "\n")) end
        end})
    Spy._block = UI.TextBlock.new({x = area.x, y = area.y + 34, width = area.width,
        height = area.height - 34, zIndex = 120, showLineNumbers = false})
    tabs:registerContent("Remote Spy", holder)
    table.insert(Analyzer._connections, Analyzer.Signals.TabChanged:Connect(function(name)
        local show = Analyzer._visible and name == "Remote Spy"
        Spy._filterBox:setVisible(show)
        Spy._pauseBtn:setVisible(show)
        Spy._clearBtn:setVisible(show)
        Spy._copyBtn:setVisible(show)
        Spy._block:setVisible(show)
    end))
    Spy:start()
    Spy:_render()
    print("[Analyzer] RemoteSpy initialized")
end

function Spy.cleanup()
    if Analyzer._originalNamecall and type(getgenv().hookmetamethod) == "function" then
        pcall(function() getgenv().hookmetamethod(game, "__namecall", Analyzer._originalNamecall) end)
        Analyzer._originalNamecall = nil
    end
    Spy._hooked = false
end

return Spy
