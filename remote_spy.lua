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
Spy._conns = {}
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
    local wrap = getgenv().newcclosure
    local function handler(selfObj, ...)
        local method = ""
        if type(ncm) == "function" then local ok, m = pcall(ncm) if ok then method = m end end
        -- ponytail: Luau rejects '...' inside a nested non-vararg closure, so
        -- capture varargs once and unpack the table instead
        local args, n = {...}, select("#", ...)
        if (method == "FireServer" or method == "InvokeServer")
            and (selfObj:IsA("RemoteEvent") or selfObj:IsA("RemoteFunction")) then
            pcall(function() Spy:push("OUT", selfObj, method, table.unpack(args, 1, n)) end)
        end
        return Spy._hookedFn(selfObj, ...)
    end
    -- ponytail: pcall everything; a throwing newcclosure/hook must idle the spy, not kill init
    local wrapped = handler
    if type(wrap) == "function" then
        local wok, w = pcall(wrap, handler)
        if wok and type(w) == "function" then wrapped = w end
    end
    local ok, old = pcall(hmm, game, "__namecall", wrapped)
    if not ok or type(old) ~= "function" then return end
    -- ponytail: keep the TRUE original across rebuild re-hooks
    if not Analyzer._originalNamecall then Analyzer._originalNamecall = old end
    Spy._hookedFn = old
    self._hooked = true
end

function Spy.init()
    -- ponytail: v2 — tops parented to content pane (relative); cascade moves them
    local pane = UI.MainWindow.getContentPane()
    local box = UI._contentArea
    local w, h = box.width, box.height
    local tabs = UI.MainWindow.getTabContainer()
    local holder = UI.Widget.new({x = 0, y = 0, width = w, height = h, zIndex = 115})
    holder.redraw = function() end
    if pane then pane:addChild(holder) end
    Spy._filterBox = UI.TextInput.new({x = 8, y = 4, width = w - 260,
        height = 24, placeholder = "Filter...", zIndex = 121,
        onChange = function(t) Spy._filter = t Spy:_render() end})
    Spy._pauseBtn = UI.Button.new({x = w - 244, y = 4, width = 70, height = 24,
        text = "Pause", zIndex = 121, onClick = function(selfBtn)
            Spy._paused = not Spy._paused selfBtn:setText(Spy._paused and "Resume" or "Pause") end})
    Spy._clearBtn = UI.Button.new({x = w - 166, y = 4, width = 70, height = 24,
        text = "Clear", zIndex = 121, onClick = function() Spy._log = {} Spy:_render() end})
    Spy._copyBtn = UI.Button.new({x = w - 88, y = 4, width = 80, height = 24,
        text = "Copy", zIndex = 121, onClick = function()
            local sc = getgenv().setclipboard
            if type(sc) == "function" then pcall(sc, table.concat((function()
                local l = {} for _, e in ipairs(Spy._log) do table.insert(l, e.path) end return l end)(), "\n")) end
        end})
    Spy._block = UI.TextBlock.new({x = 0, y = 34, width = w,
        height = h - 34, zIndex = 120, showLineNumbers = false})
    if pane then
        pane:addChild(Spy._filterBox)
        pane:addChild(Spy._pauseBtn)
        pane:addChild(Spy._clearBtn)
        pane:addChild(Spy._copyBtn)
        pane:addChild(Spy._block)
    end
    tabs:registerContent("Remote Spy", holder)
    table.insert(Spy._conns, Analyzer.Signals.TabChanged:Connect(function(name)
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
    for _, c in ipairs(Spy._conns) do pcall(function() c.Disconnect(c) end) end
    Spy._conns = {}
    if Analyzer._originalNamecall and type(getgenv().hookmetamethod) == "function" then
        pcall(function() getgenv().hookmetamethod(game, "__namecall", Analyzer._originalNamecall) end)
        Analyzer._originalNamecall = nil
    end
    Spy._hooked = false
end

return Spy
