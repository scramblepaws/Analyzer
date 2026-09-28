--[[
    Analyzer — Roblox Game Analyzer
    Loader / Entry Point
    
    This is the script you execute in your UNC/SUNC-compatible executor.
    It bootstraps the entire tool by:
      1. Cleaning up any previous instance (re-execution safe)
      2. Detecting available UNC/SUNC capabilities
      3. Loading all modules from GitHub
      4. Setting up the keybind (Right Shift) and tray icon
]]

----------------------------------------------------------------------
-- Configuration
----------------------------------------------------------------------
local CONFIG = {
    -- Set this to your GitHub raw URL base, e.g.:
    -- "https://raw.githubusercontent.com/YourUser/YourRepo/main"
    BASE_URL = "https://raw.githubusercontent.com/scramblepaws/Analyzer/main",
    
    TOGGLE_KEY = Enum.KeyCode.RightShift,
    TRAY_ICON_RADIUS = 8,
    TRAY_ICON_MARGIN = 20,
    TRAY_ICON_COLOR = Color3.fromRGB(0, 162, 255),
    
    VERSION = "1.0.0",
    NAME = "Analyzer",
}

----------------------------------------------------------------------
-- Re-execution Guard & Cleanup
----------------------------------------------------------------------
if getgenv().Analyzer then
    if getgenv().Analyzer._cleanup then
        pcall(getgenv().Analyzer._cleanup)
    end
    getgenv().Analyzer = nil
    task.wait(0.1)
end

----------------------------------------------------------------------
-- Initialize Root Table
----------------------------------------------------------------------
local Analyzer = {
    _version = CONFIG.VERSION,
    _name = CONFIG.NAME,
    _config = CONFIG,
    _connections = {},   -- all RBXScriptConnections for cleanup
    _drawingObjects = {}, -- all Drawing objects for cleanup
    _loaded = false,
    _visible = false,
    _capabilities = {},
}
getgenv().Analyzer = Analyzer

----------------------------------------------------------------------
-- Capability Detection
----------------------------------------------------------------------
local function checkCapability(name, func)
    local available = type(func) == "function"
    Analyzer._capabilities[name] = available
    return available
end

local function detectCapabilities()
    local caps = {}
    
    -- Required
    caps.Drawing = typeof(Drawing) == "table" and Drawing.new ~= nil
    caps.getgenv = type(getgenv) == "function"
    caps.game = typeof(game) == "Instance"
    
    -- Optional UNC/SUNC functions
    local optionalFuncs = {
        "decompile", "getscriptbytecode", "hookmetamethod",
        "getconnections", "gethiddenproperty", "getproperties",
        "saveinstance", "writefile", "readfile", "setclipboard",
        "getinstances", "getnilinstances", "getcallingscript",
        "getnamecallmethod", "newcclosure", "hookfunction",
        "iscclosure", "checkcaller", "getinfo",
    }
    
    for _, name in ipairs(optionalFuncs) do
        local fn = getfenv()[name] or getgenv()[name]
        if fn == nil then
            -- Try raw global lookup
            pcall(function()
                fn = _G[name] or rawget(_G, name)
            end)
        end
        caps[name] = type(fn) == "function"
    end
    
    Analyzer._capabilities = caps
    return caps
end

local function printBanner(caps)
    local lines = {
        "",
        "╔══════════════════════════════════════════╗",
        "║       " .. CONFIG.NAME .. " v" .. CONFIG.VERSION .. "                    ║",
        "║       Roblox Game Analyzer              ║",
        "╚══════════════════════════════════════════╝",
        "",
        "  Toggle: Right Shift | Tray: Bottom-Right",
        "",
        "  ── Capabilities ──",
    }
    
    -- Required
    local requiredList = {"Drawing", "getgenv", "game"}
    for _, name in ipairs(requiredList) do
        local icon = caps[name] and "  ✅ " or "  ❌ "
        table.insert(lines, icon .. name .. (caps[name] and "" or " (REQUIRED - MISSING!)"))
    end
    
    table.insert(lines, "")
    table.insert(lines, "  ── Optional Features ──")
    
    local optionalDisplay = {
        {"decompile",          "Script Decompilation"},
        {"getscriptbytecode",  "Bytecode Extraction"},
        {"hookmetamethod",     "Remote Spy (outgoing)"},
        {"getconnections",     "Remote Spy (incoming)"},
        {"gethiddenproperty",  "Hidden Properties"},
        {"getproperties",      "Property Enumeration"},
        {"saveinstance",       "Game Export"},
        {"writefile",          "File Saving"},
        {"setclipboard",       "Clipboard Copy"},
        {"getnilinstances",    "Nil Instances"},
        {"newcclosure",        "Closure Wrapping"},
        {"getcallingscript",   "Caller Detection"},
    }
    
    for _, pair in ipairs(optionalDisplay) do
        local name, desc = pair[1], pair[2]
        local icon = caps[name] and "  ✅ " or "  ⚠️ "
        table.insert(lines, icon .. desc .. " (" .. name .. ")")
    end
    
    table.insert(lines, "")
    
    -- Check for critical missing capabilities
    local missing = {}
    for _, name in ipairs(requiredList) do
        if not caps[name] then
            table.insert(missing, name)
        end
    end
    
    if #missing > 0 then
        table.insert(lines, "  ❌ CRITICAL: Missing required capabilities: " .. table.concat(missing, ", "))
        table.insert(lines, "  ❌ Analyzer cannot start. Please use a UNC-compatible executor.")
    else
        table.insert(lines, "  ✅ All required capabilities available. Starting...")
    end
    
    table.insert(lines, "")
    
    for _, line in ipairs(lines) do
        print(line)
    end
    
    return #missing == 0
end

----------------------------------------------------------------------
-- Module Loading
----------------------------------------------------------------------
local EMBEDDED = {
["ui_framework.lua"] = [===[
--[[
    Analyzer — UI Framework
    Drawing API Widget System
    
    Provides all visual components built entirely on Drawing.new().
    Includes: Signal, Pool, Theme, Input System, and all widgets.
    
    Registers into getgenv().Analyzer.UI
]]

local Analyzer = getgenv().Analyzer
if not Analyzer then
    error("[Analyzer] UI Framework loaded before loader. Run loader.lua first.")
    return
end

----------------------------------------------------------------------
-- Module Registration
----------------------------------------------------------------------
local UI = {}
Analyzer.UI = UI

----------------------------------------------------------------------
-- Signal Class
----------------------------------------------------------------------
local Signal = {}
Signal.__index = Signal

function Signal.new()
    return setmetatable({
        _listeners = {},
        _nextId = 1,
    }, Signal)
end

function Signal:Connect(callback)
    local id = self._nextId
    self._nextId = id + 1
    self._listeners[id] = callback
    
    return {
        Disconnect = function()
            self._listeners[id] = nil
        end,
        Connected = true,
    }
end

function Signal:Fire(...)
    for _, callback in pairs(self._listeners) do
        task.spawn(callback, ...)
    end
end

function Signal:DisconnectAll()
    self._listeners = {}
end

function Signal:Wait()
    local thread = coroutine.running()
    local conn
    conn = self:Connect(function(...)
        conn:Disconnect()
        task.spawn(thread, ...)
    end)
    return coroutine.yield()
end

UI.Signal = Signal

-- Global signals for inter-module communication
Analyzer.Signals = {
    InstanceSelected = Signal.new(),
    TabChanged = Signal.new(),
    RemoteLogged = Signal.new(),
    ScriptRequested = Signal.new(),
    Notification = Signal.new(),
    ThemeChanged = Signal.new(),
}

----------------------------------------------------------------------
-- Theme
----------------------------------------------------------------------
----------------------------------------------------------------------
-- Motion (tween helper) + Drop Shadow
-- ponytail: one tiny tween runner; per-widget seq tokens kill stale tweens
----------------------------------------------------------------------
function UI.tween(dur, step)
    task.spawn(function()
        local t0 = os.clock()
        while true do
            local t = math.clamp((os.clock() - t0) / dur, 0, 1)
            local ok = pcall(step, t)
            if not ok or t >= 1 then break end
            task.wait()
        end
    end)
end

function UI.lerpColor(a, b, t)
    return Color3.new(
        a.R + (b.R - a.R) * t,
        a.G + (b.G - a.G) * t,
        a.B + (b.B - a.B) * t)
end

function UI.shadow(x, y, w, h, zIndex)
    local s = Pool.get("Square")
    s.Size = Vector2.new(w, h)
    s.Position = Vector2.new(x + 5, y + 6)
    s.Color = Color3.fromRGB(0, 0, 0)
    s.Filled = true
    s.Thickness = 0
    s.Transparency = 0.7
    s.ZIndex = zIndex
    s.Visible = false
    table.insert(Analyzer._drawingObjects, s)
    return s
end

UI.Theme = {
    Background    = Color3.fromRGB(11, 14, 23),
    Surface       = Color3.fromRGB(18, 24, 39),
    SurfaceLight  = Color3.fromRGB(28, 37, 62),
    SurfaceHover  = Color3.fromRGB(38, 50, 82),
    Border        = Color3.fromRGB(42, 58, 96),
    BorderLight   = Color3.fromRGB(74, 96, 148),
    Text          = Color3.fromRGB(205, 220, 255),
    TextDim       = Color3.fromRGB(110, 130, 175),
    TextDark      = Color3.fromRGB(66, 80, 116),
    Accent        = Color3.fromRGB(0, 240, 255),
    AccentHover   = Color3.fromRGB(130, 250, 255),
    AccentDim     = Color3.fromRGB(8, 62, 82),
    Magenta       = Color3.fromRGB(255, 42, 109),
    Error         = Color3.fromRGB(255, 42, 109),
    Warning       = Color3.fromRGB(249, 240, 2),
    Success       = Color3.fromRGB(57, 255, 20),
    
    -- Class colors for Explorer
    ClassColors = {
        Script        = Color3.fromRGB(255, 158, 0),
        LocalScript   = Color3.fromRGB(255, 158, 0),
        ModuleScript  = Color3.fromRGB(255, 110, 200),
        Part          = Color3.fromRGB(0, 240, 255),
        MeshPart      = Color3.fromRGB(0, 240, 255),
        UnionOperation = Color3.fromRGB(0, 240, 255),
        WedgePart     = Color3.fromRGB(0, 240, 255),
        TrussPart     = Color3.fromRGB(0, 240, 255),
        Model         = Color3.fromRGB(249, 240, 2),
        Folder        = Color3.fromRGB(249, 240, 2),
        RemoteEvent   = Color3.fromRGB(255, 42, 109),
        RemoteFunction = Color3.fromRGB(255, 42, 109),
        BindableEvent = Color3.fromRGB(255, 120, 190),
        BindableFunction = Color3.fromRGB(255, 120, 190),
        Frame         = Color3.fromRGB(57, 255, 20),
        TextLabel     = Color3.fromRGB(57, 255, 20),
        TextButton    = Color3.fromRGB(57, 255, 20),
        TextBox       = Color3.fromRGB(57, 255, 20),
        ImageLabel    = Color3.fromRGB(57, 255, 20),
        ImageButton   = Color3.fromRGB(57, 255, 20),
        ScrollingFrame = Color3.fromRGB(57, 255, 20),
        ScreenGui     = Color3.fromRGB(57, 255, 20),
        BillboardGui  = Color3.fromRGB(57, 255, 20),
        SurfaceGui    = Color3.fromRGB(57, 255, 20),
    },
    
    -- Syntax highlighting colors
    Syntax = {
        Keyword  = Color3.fromRGB(0, 240, 255),
        String   = Color3.fromRGB(126, 255, 170),
        Comment  = Color3.fromRGB(92, 102, 150),
        Number   = Color3.fromRGB(255, 42, 109),
        BuiltIn  = Color3.fromRGB(255, 158, 0),
        Default  = Color3.fromRGB(205, 220, 255),
    },
    
    -- Layout
    FontSize       = 14,
    MenuHeight     = 26,
    PaneHeadHeight = 22,
    SmallFontSize  = 12,
    LineHeight     = 20,
    TabHeight      = 30,
    TitleBarHeight = 28,
    Padding        = 8,
    IndentWidth    = 20,
    ScrollbarWidth = 6,
    WindowMargin   = 40,
}

function UI.getClassColor(className)
    return UI.Theme.ClassColors[className] or Color3.fromRGB(180, 180, 180)
end

----------------------------------------------------------------------
-- Drawing Object Pool
----------------------------------------------------------------------
local Pool = {
    _pools = {},
    _active = {},
    _totalCreated = 0,
}
UI.Pool = Pool

function Pool.get(drawingType)
    local pool = Pool._pools[drawingType]
    if pool and #pool > 0 then
        local obj = table.remove(pool)
        obj.Visible = false -- will be made visible by the caller
        Pool._active[obj] = true
        return obj
    end
    
    -- Create new
    local obj = Drawing.new(drawingType)
    obj.Visible = false
    Pool._active[obj] = true
    Pool._totalCreated = Pool._totalCreated + 1
    table.insert(Analyzer._drawingObjects, obj)
    return obj
end

function Pool.release(obj)
    if not obj then return end
    
    local drawingType = nil
    -- Determine type by checking properties
    if pcall(function() local _ = obj.Radius end) then
        drawingType = "Circle"
    elseif pcall(function() local _ = obj.TextBounds end) then
        drawingType = "Text"
    elseif pcall(function() local _ = obj.From end) then
        drawingType = "Line"
    else
        drawingType = "Square"
    end
    
    obj.Visible = false
    Pool._active[obj] = nil
    
    if not Pool._pools[drawingType] then
        Pool._pools[drawingType] = {}
    end
    table.insert(Pool._pools[drawingType], obj)
end

function Pool.releaseAll()
    -- ponytail: recycle (not just hide) so stats stay honest; copy keys first
    local objs = {}
    for obj, _ in pairs(Pool._active) do table.insert(objs, obj) end
    for _, obj in ipairs(objs) do
        pcall(function() Pool.release(obj) end)
    end
    Pool._active = {}
end

function Pool.getStats()
    local pooled = 0
    for _, p in pairs(Pool._pools) do
        pooled = pooled + #p
    end
    local active = 0
    for _ in pairs(Pool._active) do
        active = active + 1
    end
    return {
        total = Pool._totalCreated,
        active = active,
        pooled = pooled,
    }
end

----------------------------------------------------------------------
-- Safe Viewport (validates real screensize, falls back when unreadable)
----------------------------------------------------------------------
function UI.getViewport()
    local w, h = 1280, 720 -- ponytail: fallback, real size when readable
    pcall(function()
        local cam = workspace.CurrentCamera
        if cam and cam.ViewportSize then
            local vs = cam.ViewportSize
            if vs.X > 100 and vs.Y > 100 then
                w, h = math.floor(vs.X), math.floor(vs.Y)
            end
        end
    end)
    return w, h
end

----------------------------------------------------------------------
-- Input System
----------------------------------------------------------------------
local Input = {
    _mousePos = Vector2.new(0, 0),
    _mouseDown = false,
    _widgets = {},      -- ordered by z-index for hit testing
    _focused = nil,     -- currently focused widget (for text input)
    _dragging = nil,    -- currently dragged widget
    _dragOffset = Vector2.new(0, 0),
    _connections = {},
}
UI.Input = Input

function Input.register(widget)
    table.insert(Input._widgets, widget)
    -- Sort by z-index descending (highest first for hit testing)
    table.sort(Input._widgets, function(a, b)
        return (a._zIndex or 0) > (b._zIndex or 0)
    end)
end

function Input.unregister(widget)
    for i, w in ipairs(Input._widgets) do
        if w == widget then
            table.remove(Input._widgets, i)
            break
        end
    end
end

function Input.hitTest(pos)
    for _, widget in ipairs(Input._widgets) do
        if widget._visible and widget._interactive then
            local wx, wy = widget._absX or 0, widget._absY or 0
            local ww, wh = widget._width or 0, widget._height or 0
            
            if pos.X >= wx and pos.X <= wx + ww and
               pos.Y >= wy and pos.Y <= wy + wh then
                return widget
            end
        end
    end
    return nil
end

-- ponytail: single mouse source; GetMouseLocation includes topbar inset, Drawing coords don't
function Input.mousePos()
    local p = game:GetService("UserInputService"):GetMouseLocation()
    pcall(function() p = p - game:GetService("GuiService"):GetGuiInset() end)
    return p
end

function Input.setup()
    local UIS = game:GetService("UserInputService")
    
    -- Mouse move
    local moveConn = UIS.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            Input._mousePos = Input.mousePos()
            
            -- Handle drag
            if Input._dragging and Input._dragging.onDrag then
                Input._dragging:onDrag(Input._mousePos - Input._dragOffset)
            end
            
            -- Handle hover
            local hit = Input.hitTest(Input._mousePos)
            for _, widget in ipairs(Input._widgets) do
                if widget._hovered and widget ~= hit then
                    widget._hovered = false
                    if widget.onHoverEnd then widget:onHoverEnd() end
                end
            end
            if hit and not hit._hovered then
                hit._hovered = true
                if hit.onHoverStart then hit:onHoverStart() end
            end
        end
        
        -- Mouse scroll
        if input.UserInputType == Enum.UserInputType.MouseWheel then
            local hit = Input.hitTest(Input._mousePos)
            if hit and hit.onScroll then
                hit:onScroll(input.Position.Z)
            end
        end
    end)
    table.insert(Input._connections, moveConn)
    table.insert(Analyzer._connections, moveConn)
    
    -- Mouse click
    local clickConn = UIS.InputBegan:Connect(function(input, gameProcessed)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            Input._mouseDown = true
            local pos = Input.mousePos()
            local hit = Input.hitTest(pos)
            
            -- Focus management
            if Input._focused and Input._focused ~= hit then
                if Input._focused.onBlur then Input._focused:onBlur() end
                Input._focused = nil
            end
            
            if hit then
                if hit.onMouseDown then hit:onMouseDown(pos) end
                if hit._focusable then
                    Input._focused = hit
                    if hit.onFocus then hit:onFocus() end
                end
                if hit._draggable then
                    Input._dragging = hit
                    Input._dragOffset = pos - Vector2.new(hit._absX or 0, hit._absY or 0)
                end
            end
        end
        
        -- Keyboard input for focused widget
        if input.UserInputType == Enum.UserInputType.Keyboard then
            if Input._focused and Input._focused.onKeyPress then
                Input._focused:onKeyPress(input.KeyCode)
            end
        end
    end)
    table.insert(Input._connections, clickConn)
    table.insert(Analyzer._connections, clickConn)
    
    -- Mouse release
    local releaseConn = UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            Input._mouseDown = false
            
            local pos = Input.mousePos()
            
            if Input._dragging then
                Input._dragging = nil
            end
            
            local hit = Input.hitTest(pos)
            if hit and hit.onClick then
                hit:onClick(pos)
            end
        end
    end)
    table.insert(Input._connections, releaseConn)
    table.insert(Analyzer._connections, releaseConn)
    
    -- Text input (for TextInput widget)
    local textConn = UIS.TextBoxFocusReleased:Connect(function() end) -- placeholder
    -- We handle text via keyboard events on focused widgets instead
end

----------------------------------------------------------------------
-- Widget Base Class
----------------------------------------------------------------------
local Widget = {}
Widget.__index = Widget

function Widget.new(props)
    local self = setmetatable({
        _x = props.x or 0,
        _y = props.y or 0,
        _absX = props.x or 0,
        _absY = props.y or 0,
        _width = props.width or 100,
        _height = props.height or 20,
        _visible = false,
        _interactive = props.interactive ~= false,
        _focusable = props.focusable or false,
        _draggable = props.draggable or false,
        _zIndex = props.zIndex or 1,
        _hovered = false,
        _parent = nil,
        _children = {},
        _drawingObjects = {},
    }, Widget)
    return self
end

function Widget:setPosition(x, y)
    self._x = x
    self._y = y
    self:_updateAbsolutePosition()
    self:redraw()
end

function Widget:_updateAbsolutePosition()
    if self._parent then
        self._absX = self._parent._absX + self._x
        self._absY = self._parent._absY + self._y
    else
        self._absX = self._x
        self._absY = self._y
    end
    for _, child in ipairs(self._children) do
        child:_updateAbsolutePosition()
    end
end

function Widget:setSize(w, h)
    self._width = w
    self._height = h
    self:redraw()
end

function Widget:setVisible(visible)
    self._visible = visible
    for _, obj in ipairs(self._drawingObjects) do
        pcall(function() obj.Visible = visible end)
    end
    for _, child in ipairs(self._children) do
        child:setVisible(visible)
    end
end

function Widget:addChild(child)
    child._parent = self
    table.insert(self._children, child)
    child:_updateAbsolutePosition()
end

function Widget:removeChild(child)
    for i, c in ipairs(self._children) do
        if c == child then
            table.remove(self._children, i)
            child._parent = nil
            break
        end
    end
end

function Widget:destroy()
    Input.unregister(self)
    for _, obj in ipairs(self._drawingObjects) do
        Pool.release(obj)
    end
    self._drawingObjects = {}
    for _, child in ipairs(self._children) do
        child:destroy()
    end
    self._children = {}
    self._visible = false
end

function Widget:redraw()
    -- Override in subclasses
end

UI.Widget = Widget

----------------------------------------------------------------------
-- Rect Widget
----------------------------------------------------------------------
local Rect = setmetatable({}, {__index = Widget})
Rect.__index = Rect

function Rect.new(props)
    local self = Widget.new(props)
    setmetatable(self, Rect)
    
    self._fillColor = props.fillColor or UI.Theme.Surface
    self._borderColor = props.borderColor or UI.Theme.Border
    self._borderThickness = props.borderThickness or 1
    self._transparency = props.transparency or 1
    
    -- Create drawing objects
    self._bg = Pool.get("Square")
    self._bg.Size = Vector2.new(self._width, self._height)
    self._bg.Position = Vector2.new(self._absX, self._absY)
    self._bg.Color = self._fillColor
    self._bg.Filled = true
    self._bg.Thickness = 0
    self._bg.Transparency = self._transparency
    self._bg.ZIndex = self._zIndex
    self._bg.Visible = false
    table.insert(self._drawingObjects, self._bg)
    
    if self._borderThickness > 0 then
        self._border = Pool.get("Square")
        self._border.Size = Vector2.new(self._width, self._height)
        self._border.Position = Vector2.new(self._absX, self._absY)
        self._border.Color = self._borderColor
        self._border.Filled = false
        self._border.Thickness = self._borderThickness
        self._border.Transparency = self._transparency
        self._border.ZIndex = self._zIndex + 1
        self._border.Visible = false
        table.insert(self._drawingObjects, self._border)
    end
    
    return self
end

function Rect:setFillColor(color)
    self._fillColor = color
    if self._bg then self._bg.Color = color end
end

function Rect:redraw()
    if self._bg then
        self._bg.Position = Vector2.new(self._absX, self._absY)
        self._bg.Size = Vector2.new(self._width, self._height)
        self._bg.Color = self._fillColor
        self._bg.Visible = self._visible
    end
    if self._border then
        self._border.Position = Vector2.new(self._absX, self._absY)
        self._border.Size = Vector2.new(self._width, self._height)
        self._border.Visible = self._visible
    end
end

UI.Rect = Rect

----------------------------------------------------------------------
-- Label Widget
----------------------------------------------------------------------
local Label = setmetatable({}, {__index = Widget})
Label.__index = Label

function Label.new(props)
    local self = Widget.new(props)
    setmetatable(self, Label)
    
    self._text = props.text or ""
    self._textColor = props.textColor or UI.Theme.Text
    self._fontSize = props.fontSize or UI.Theme.FontSize
    self._font = props.font or 2 -- Drawing.Fonts.Plex (or system default)
    self._center = props.center or false
    self._maxWidth = props.maxWidth or nil
    
    self._textObj = Pool.get("Text")
    self._textObj.Text = self:_getTruncatedText()
    self._textObj.Position = Vector2.new(self._absX, self._absY)
    self._textObj.Color = self._textColor
    self._textObj.Size = self._fontSize
    self._textObj.Font = self._font
    self._textObj.Center = self._center
    self._textObj.Outline = false
    self._textObj.OutlineColor = Color3.fromRGB(0, 0, 0)
    self._textObj.ZIndex = self._zIndex + 2
    self._textObj.Visible = false
    table.insert(self._drawingObjects, self._textObj)
    
    -- Update width/height based on text bounds
    if self._textObj.TextBounds then
        self._width = self._textObj.TextBounds.X
        self._height = self._textObj.TextBounds.Y
    end
    
    return self
end

function Label:_getTruncatedText()
    if not self._maxWidth or self._maxWidth <= 0 then
        return self._text
    end
    
    -- Approximate truncation: estimate ~7px per char at font size 14
    local charWidth = self._fontSize * 0.5
    local maxChars = math.floor(self._maxWidth / charWidth)
    
    if #self._text <= maxChars then
        return self._text
    end
    
    return string.sub(self._text, 1, maxChars - 3) .. "..."
end

function Label:setText(text)
    self._text = text
    if self._textObj then
        self._textObj.Text = self:_getTruncatedText()
    end
end

function Label:setColor(color)
    self._textColor = color
    if self._textObj then
        self._textObj.Color = color
    end
end

function Label:redraw()
    if self._textObj then
        self._textObj.Position = Vector2.new(self._absX, self._absY)
        self._textObj.Text = self:_getTruncatedText()
        self._textObj.Color = self._textColor
        self._textObj.Visible = self._visible
    end
end

UI.Label = Label

----------------------------------------------------------------------
-- Button Widget
----------------------------------------------------------------------
local Button = setmetatable({}, {__index = Widget})
Button.__index = Button

function Button.new(props)
    local self = Widget.new(props)
    setmetatable(self, Button)
    self._interactive = true
    
    self._text = props.text or "Button"
    self._normalColor = props.normalColor or UI.Theme.Surface
    self._hoverColor = props.hoverColor or UI.Theme.SurfaceHover
    self._activeColor = props.activeColor or UI.Theme.Accent
    self._textColor = props.textColor or UI.Theme.Text
    self._onClick = props.onClick or nil
    self._isActive = props.isActive or false
    
    -- Background rect
    self._bgRect = Rect.new({
        x = 0, y = 0,
        width = self._width,
        height = self._height,
        fillColor = self._isActive and self._activeColor or self._normalColor,
        borderColor = UI.Theme.Border,
        borderThickness = 0,
        zIndex = self._zIndex,
    })
    self:addChild(self._bgRect)
    
    -- Text label
    self._label = Label.new({
        x = UI.Theme.Padding,
        y = math.floor((self._height - UI.Theme.FontSize) / 2),
        text = self._text,
        textColor = self._textColor,
        fontSize = props.fontSize or UI.Theme.FontSize,
        zIndex = self._zIndex + 3,
    })
    self:addChild(self._label)
    
    Input.register(self)
    
    return self
end

function Button:setActive(active)
    self._hoverSeq = (self._hoverSeq or 0) + 1
    self._isActive = active
    self._bgRect:setFillColor(active and self._activeColor or self._normalColor)
    self._bgRect:redraw()
end

function Button:_tweenFill(target)
    local from = self._bgRect._fillColor
    self._hoverSeq = (self._hoverSeq or 0) + 1
    local seq = self._hoverSeq
    UI.tween(0.09, function(t)
        if seq ~= self._hoverSeq then return end
        self._bgRect:setFillColor(UI.lerpColor(from, target, t))
    end)
end

function Button:onHoverStart()
    if not self._isActive then
        self:_tweenFill(self._hoverColor)
    end
end

function Button:onHoverEnd()
    if not self._isActive then
        self:_tweenFill(self._normalColor)
    end
end

function Button:onClick(pos)
    if self._onClick then
        self._onClick(self)
    end
end

function Button:setText(text)
    self._text = text
    if self._label then
        self._label:setText(text)
        self._label:redraw()
    end
end

function Button:redraw()
    self._bgRect:setSize(self._width, self._height)
    self._bgRect:_updateAbsolutePosition()
    self._bgRect:redraw()
    self._label:_updateAbsolutePosition()
    self._label:redraw()
end

function Button:setVisible(visible)
    self._visible = visible
    self._bgRect:setVisible(visible)
    self._label:setVisible(visible)
end

UI.Button = Button

----------------------------------------------------------------------
-- Tab Widget
----------------------------------------------------------------------
local Tab = setmetatable({}, {__index = Button})
Tab.__index = Tab

function Tab.new(props)
    props.normalColor = props.normalColor or UI.Theme.Background
    props.hoverColor = props.hoverColor or UI.Theme.SurfaceLight
    props.activeColor = props.activeColor or UI.Theme.Surface
    props.borderThickness = 0
    
    local self = Button.new(props)
    setmetatable(self, Tab)
    
    self._tabName = props.tabName or props.text
    
    -- Accent underline (visible when active; menu uses one shared sliding bar instead)
    if not props.noUnderline then
        self._underline = Pool.get("Square")
    self._underline.Size = Vector2.new(self._width, 2)
    self._underline.Position = Vector2.new(self._absX, self._absY + self._height - 2)
    self._underline.Color = UI.Theme.Accent
    self._underline.Filled = true
    self._underline.Thickness = 0
    self._underline.ZIndex = self._zIndex + 5
    self._underline.Visible = false
    table.insert(self._drawingObjects, self._underline)
    end
    
    return self
end

function Tab:setActive(active)
    self._hoverSeq = (self._hoverSeq or 0) + 1
    self._isActive = active
    self._bgRect:setFillColor(active and self._activeColor or self._normalColor)
    self._bgRect:redraw()
    if self._label then
        self._label:setColor(active and UI.Theme.Accent or UI.Theme.TextDim)
        self._label:redraw()
    end
    if self._underline then
        self._underline.Visible = active and self._visible
    end
end

function Tab:redraw()
    Button.redraw(self)
    if self._underline then
        self._underline.Position = Vector2.new(self._absX, self._absY + self._height - 2)
        self._underline.Size = Vector2.new(self._width, 2)
        self._underline.Visible = self._isActive and self._visible
    end
end

function Tab:setVisible(visible)
    Button.setVisible(self, visible)
    if self._underline then
        self._underline.Visible = self._isActive and visible
    end
end

UI.Tab = Tab

----------------------------------------------------------------------
-- ScrollContainer Widget
----------------------------------------------------------------------
local ScrollContainer = setmetatable({}, {__index = Widget})
ScrollContainer.__index = ScrollContainer

function ScrollContainer.new(props)
    local self = Widget.new(props)
    setmetatable(self, ScrollContainer)
    self._interactive = true
    
    self._scrollOffset = 0
    self._maxScroll = 0
    self._contentHeight = props.contentHeight or 0
    self._scrollSpeed = props.scrollSpeed or 30
    self._onScroll = props.onScroll or nil
    self._items = {}
    self._itemHeight = props.itemHeight or UI.Theme.LineHeight
    
    -- Background
    self._bg = Rect.new({
        x = 0, y = 0,
        width = self._width,
        height = self._height,
        fillColor = props.bgColor or UI.Theme.Background,
        borderColor = UI.Theme.Border,
        borderThickness = 0,
        zIndex = self._zIndex,
    })
    self:addChild(self._bg)
    
    -- Scrollbar track
    self._scrollTrack = Pool.get("Square")
    self._scrollTrack.Size = Vector2.new(UI.Theme.ScrollbarWidth, self._height)
    self._scrollTrack.Position = Vector2.new(
        self._absX + self._width - UI.Theme.ScrollbarWidth,
        self._absY
    )
    self._scrollTrack.Color = UI.Theme.Background
    self._scrollTrack.Filled = true
    self._scrollTrack.Thickness = 0
    self._scrollTrack.ZIndex = self._zIndex + 8
    self._scrollTrack.Visible = false
    table.insert(self._drawingObjects, self._scrollTrack)
    
    -- Scrollbar thumb
    self._scrollThumb = Pool.get("Square")
    self._scrollThumb.Size = Vector2.new(UI.Theme.ScrollbarWidth, 30)
    self._scrollThumb.Position = Vector2.new(
        self._absX + self._width - UI.Theme.ScrollbarWidth,
        self._absY
    )
    self._scrollThumb.Color = UI.Theme.BorderLight
    self._scrollThumb.Filled = true
    self._scrollThumb.Thickness = 0
    self._scrollThumb.ZIndex = self._zIndex + 9
    self._scrollThumb.Visible = false
    table.insert(self._drawingObjects, self._scrollThumb)
    
    Input.register(self)
    
    return self
end

function ScrollContainer:setContentHeight(height)
    self._contentHeight = height
    self._maxScroll = math.max(0, height - self._height)
    self:_updateScrollbar()
end

function ScrollContainer:scrollTo(offset)
    self._scrollOffset = math.clamp(offset, 0, self._maxScroll)
    self:_updateScrollbar()
    if self._onScroll then
        self._onScroll(self._scrollOffset)
    end
end

function ScrollContainer:onScroll(delta)
    local newOffset = self._scrollOffset - delta * self._scrollSpeed
    self:scrollTo(newOffset)
end

function ScrollContainer:_updateScrollbar()
    if self._contentHeight <= self._height then
        -- No scrollbar needed
        if self._scrollTrack then self._scrollTrack.Visible = false end
        if self._scrollThumb then self._scrollThumb.Visible = false end
        return
    end
    
    local trackHeight = self._height
    local thumbHeight = math.max(20, (self._height / self._contentHeight) * trackHeight)
    local scrollRatio = self._scrollOffset / self._maxScroll
    local thumbY = self._absY + scrollRatio * (trackHeight - thumbHeight)
    
    if self._scrollTrack then
        self._scrollTrack.Position = Vector2.new(
            self._absX + self._width - UI.Theme.ScrollbarWidth,
            self._absY
        )
        self._scrollTrack.Size = Vector2.new(UI.Theme.ScrollbarWidth, self._height)
        self._scrollTrack.Visible = self._visible
    end
    
    if self._scrollThumb then
        self._scrollThumb.Position = Vector2.new(
            self._absX + self._width - UI.Theme.ScrollbarWidth,
            thumbY
        )
        self._scrollThumb.Size = Vector2.new(UI.Theme.ScrollbarWidth, thumbHeight)
        self._scrollThumb.Visible = self._visible
    end
end

function ScrollContainer:getVisibleRange()
    local startIndex = math.floor(self._scrollOffset / self._itemHeight) + 1
    local visibleCount = math.ceil(self._height / self._itemHeight) + 1
    local endIndex = startIndex + visibleCount - 1
    return startIndex, endIndex
end

function ScrollContainer:redraw()
    self._bg:setSize(self._width, self._height)
    self._bg:_updateAbsolutePosition()
    self._bg:redraw()
    self:_updateScrollbar()
end

function ScrollContainer:setVisible(visible)
    self._visible = visible
    self._bg:setVisible(visible)
    self:_updateScrollbar()
end

UI.ScrollContainer = ScrollContainer

----------------------------------------------------------------------
-- TreeNode Widget
----------------------------------------------------------------------
local TreeNode = setmetatable({}, {__index = Widget})
TreeNode.__index = TreeNode

function TreeNode.new(props)
    local self = Widget.new(props)
    setmetatable(self, TreeNode)
    self._interactive = true
    
    self._instance = props.instance       -- Roblox instance
    self._text = props.text or (props.instance and props.instance.Name) or "Node"
    self._depth = props.depth or 0
    self._expanded = false
    self._selected = false
    self._childNodes = {}
    self._hasChildren = props.hasChildren or false
    self._onSelect = props.onSelect or nil
    self._onExpand = props.onExpand or nil
    self._onCollapse = props.onCollapse or nil
    self._className = props.className or (props.instance and props.instance.ClassName) or ""
    self._parentContainer = props.parentContainer or nil
    self._nodeIndex = props.nodeIndex or 0  -- position in flat render list
    self._childAddedConn = nil
    self._childRemovedConn = nil
    
    local indent = self._depth * UI.Theme.IndentWidth
    local rowHeight = UI.Theme.LineHeight
    
    -- Row background (for selection/hover)
    self._rowBg = Pool.get("Square")
    self._rowBg.Size = Vector2.new(self._width - indent, rowHeight)
    self._rowBg.Position = Vector2.new(self._absX + indent, self._absY)
    self._rowBg.Color = UI.Theme.Background
    self._rowBg.Filled = true
    self._rowBg.Thickness = 0
    self._rowBg.ZIndex = self._zIndex
    self._rowBg.Visible = false
    table.insert(self._drawingObjects, self._rowBg)
    
    -- Expand/collapse icon
    self._expandIcon = Pool.get("Text")
    self._expandIcon.Text = self._hasChildren and "▶" or "  "
    self._expandIcon.Position = Vector2.new(self._absX + indent + 2, self._absY + 2)
    self._expandIcon.Color = UI.Theme.TextDim
    self._expandIcon.Size = UI.Theme.SmallFontSize
    self._expandIcon.Font = 2
    self._expandIcon.ZIndex = self._zIndex + 3
    self._expandIcon.Visible = false
    table.insert(self._drawingObjects, self._expandIcon)
    
    -- Class color chip (square: no rounded edges in this UI)
    self._classDot = Pool.get("Square")
    self._classDot.Size = Vector2.new(8, 8)
    self._classDot.Position = Vector2.new(self._absX + indent + 16, self._absY + rowHeight / 2 - 4)
    self._classDot.Color = UI.getClassColor(self._className)
    self._classDot.Filled = true
    self._classDot.Thickness = 0
    self._classDot.ZIndex = self._zIndex + 3
    self._classDot.Visible = false
    table.insert(self._drawingObjects, self._classDot)
    
    -- Name label
    self._nameLabel = Pool.get("Text")
    self._nameLabel.Text = self._text
    self._nameLabel.Position = Vector2.new(self._absX + indent + 28, self._absY + 2)
    self._nameLabel.Color = UI.Theme.Text
    self._nameLabel.Size = UI.Theme.FontSize
    self._nameLabel.Font = 2
    self._nameLabel.ZIndex = self._zIndex + 3
    self._nameLabel.Visible = false
    table.insert(self._drawingObjects, self._nameLabel)
    
    -- Class name label (dim)
    self._classLabel = Pool.get("Text")
    self._classLabel.Text = " : " .. self._className
    self._classLabel.Position = Vector2.new(self._absX + indent + 28 + (#self._text * 7), self._absY + 2)
    self._classLabel.Color = UI.Theme.TextDark
    self._classLabel.Size = UI.Theme.SmallFontSize
    self._classLabel.Font = 2
    self._classLabel.ZIndex = self._zIndex + 3
    self._classLabel.Visible = false
    table.insert(self._drawingObjects, self._classLabel)
    
    Input.register(self)
    
    return self
end

function TreeNode:expand()
    if self._expanded or not self._hasChildren then return end
    self._expanded = true
    self._expandIcon.Text = "▼"
    
    if self._onExpand then
        self._onExpand(self)
    end
end

function TreeNode:collapse()
    if not self._expanded then return end
    self._expanded = false
    self._expandIcon.Text = "▶"
    
    -- Destroy child nodes
    for _, child in ipairs(self._childNodes) do
        child:destroy()
    end
    self._childNodes = {}
    
    -- Disconnect child listeners
    if self._childAddedConn then
        self._childAddedConn:Disconnect()
        self._childAddedConn = nil
    end
    if self._childRemovedConn then
        self._childRemovedConn:Disconnect()
        self._childRemovedConn = nil
    end
    
    if self._onCollapse then
        self._onCollapse(self)
    end
end

function TreeNode:setSelected(selected)
    self._selected = selected
    if not self._rowBg then return end
    if selected then
        -- ponytail: neon flash decaying to selection bg, token kills stale tweens
        self._rowBg.Color = UI.Theme.Accent
        self._flashSeq = (self._flashSeq or 0) + 1
        local seq, bg = self._flashSeq, self._rowBg
        UI.tween(0.22, function(t)
            if seq ~= self._flashSeq then return end
            bg.Color = UI.lerpColor(UI.Theme.Accent, UI.Theme.AccentDim, t)
        end)
    else
        self._flashSeq = (self._flashSeq or 0) + 1
        self._rowBg.Color = UI.Theme.Background
    end
end

function TreeNode:onClick(pos)
    local indent = self._depth * UI.Theme.IndentWidth
    local iconEndX = self._absX + indent + 16
    
    -- Check if click was on the expand icon
    if pos.X < iconEndX and self._hasChildren then
        if self._expanded then
            self:collapse()
        else
            self:expand()
        end
    else
        -- Click on the name = select
        if self._onSelect then
            self._onSelect(self)
        end
    end
end

function TreeNode:onHoverStart()
    if not self._selected then
        self._rowBg.Color = UI.Theme.SurfaceHover
    end
end

function TreeNode:onHoverEnd()
    if not self._selected then
        self._rowBg.Color = UI.Theme.Background
    end
end

function TreeNode:updatePosition(x, y)
    self._absX = x
    self._absY = y
    
    local indent = self._depth * UI.Theme.IndentWidth
    local rowHeight = UI.Theme.LineHeight
    
    if self._rowBg then
        self._rowBg.Position = Vector2.new(x + indent, y)
        self._rowBg.Size = Vector2.new(self._width - indent, rowHeight)
    end
    if self._expandIcon then
        self._expandIcon.Position = Vector2.new(x + indent + 2, y + 2)
    end
    if self._classDot then
        self._classDot.Position = Vector2.new(x + indent + 16, y + rowHeight / 2 - 4)
    end
    if self._nameLabel then
        self._nameLabel.Position = Vector2.new(x + indent + 28, y + 2)
    end
    if self._classLabel then
        self._classLabel.Position = Vector2.new(
            x + indent + 28 + (#self._text * 7), y + 2
        )
    end
end

function TreeNode:setVisible(visible)
    self._visible = visible
    for _, obj in ipairs(self._drawingObjects) do
        pcall(function() obj.Visible = visible end)
    end
end

function TreeNode:destroy()
    Input.unregister(self)
    
    -- Disconnect instance listeners
    if self._childAddedConn then
        self._childAddedConn:Disconnect()
        self._childAddedConn = nil
    end
    if self._childRemovedConn then
        self._childRemovedConn:Disconnect()
        self._childRemovedConn = nil
    end
    
    -- Destroy children recursively
    for _, child in ipairs(self._childNodes) do
        child:destroy()
    end
    self._childNodes = {}
    
    -- Release drawing objects
    for _, obj in ipairs(self._drawingObjects) do
        Pool.release(obj)
    end
    self._drawingObjects = {}
    self._visible = false
end

UI.TreeNode = TreeNode

----------------------------------------------------------------------
-- TextBlock Widget (virtual-scroll, syntax-highlighted)
----------------------------------------------------------------------
local TextBlock = setmetatable({}, {__index = Widget})
TextBlock.__index = TextBlock

function TextBlock.new(props)
    local self = Widget.new(props)
    setmetatable(self, TextBlock)
    self._interactive = true
    
    self._lines = {}            -- array of raw text lines
    self._tokenizedLines = {}   -- array of {{text, color}, ...} per line
    self._scrollOffset = 0
    self._lineHeight = props.lineHeight or UI.Theme.LineHeight
    self._gutterWidth = props.gutterWidth or 40
    self._showLineNumbers = props.showLineNumbers ~= false
    self._tokenizer = props.tokenizer or nil  -- function(line) -> {{text, color}, ...}
    
    -- Pools for visible lines
    self._visibleLineCount = math.ceil(self._height / self._lineHeight) + 1
    self._maxSegments = props.maxSegments or 8 -- max color segments per line
    
    -- Background
    self._bg = Rect.new({
        x = 0, y = 0,
        width = self._width,
        height = self._height,
        fillColor = UI.Theme.Background,
        borderColor = UI.Theme.Border,
        borderThickness = 1,
        zIndex = self._zIndex,
    })
    self:addChild(self._bg)
    
    -- Gutter background
    if self._showLineNumbers then
        self._gutterBg = Pool.get("Square")
        self._gutterBg.Size = Vector2.new(self._gutterWidth, self._height)
        self._gutterBg.Position = Vector2.new(self._absX, self._absY)
        self._gutterBg.Color = UI.Theme.Surface
        self._gutterBg.Filled = true
        self._gutterBg.Thickness = 0
        self._gutterBg.ZIndex = self._zIndex + 1
        self._gutterBg.Visible = false
        table.insert(self._drawingObjects, self._gutterBg)
    end
    
    -- Pre-allocate text objects for visible lines
    self._lineNumberPool = {}
    self._segmentPool = {}  -- [lineSlot][segmentSlot] = Drawing Text
    
    for i = 1, self._visibleLineCount do
        -- Line number
        if self._showLineNumbers then
            local lnObj = Pool.get("Text")
            lnObj.Text = ""
            lnObj.Size = UI.Theme.SmallFontSize
            lnObj.Font = 2
            lnObj.Color = UI.Theme.TextDark
            lnObj.ZIndex = self._zIndex + 4
            lnObj.Visible = false
            table.insert(self._drawingObjects, lnObj)
            self._lineNumberPool[i] = lnObj
        end
        
        -- Segments
        self._segmentPool[i] = {}
        for j = 1, self._maxSegments do
            local segObj = Pool.get("Text")
            segObj.Text = ""
            segObj.Size = UI.Theme.FontSize
            segObj.Font = 2
            segObj.Color = UI.Theme.Text
            segObj.ZIndex = self._zIndex + 4
            segObj.Visible = false
            table.insert(self._drawingObjects, segObj)
            self._segmentPool[i][j] = segObj
        end
    end
    
    -- Scrollbar
    self._scrollContainer = ScrollContainer.new({
        x = self._width - UI.Theme.ScrollbarWidth,
        y = 0,
        width = UI.Theme.ScrollbarWidth,
        height = self._height,
        zIndex = self._zIndex + 6,
        onScroll = function(offset)
            self._scrollOffset = offset
            self:_renderVisibleLines()
        end,
    })
    
    Input.register(self)
    
    return self
end

function TextBlock:setContent(text)
    if type(text) == "string" then
        self._lines = {}
        for line in (text .. "\n"):gmatch("(.-)\n") do
            table.insert(self._lines, line)
        end
    elseif type(text) == "table" then
        self._lines = text
    end
    
    -- Tokenize all lines
    self._tokenizedLines = {}
    if self._tokenizer then
        for i, line in ipairs(self._lines) do
            self._tokenizedLines[i] = self._tokenizer(line)
        end
    else
        for i, line in ipairs(self._lines) do
            self._tokenizedLines[i] = {{line, UI.Theme.Text}}
        end
    end
    
    -- Update scroll
    local totalHeight = #self._lines * self._lineHeight
    self._scrollOffset = 0
    
    self:_renderVisibleLines()
end

function TextBlock:_renderVisibleLines()
    local startLine = math.floor(self._scrollOffset / self._lineHeight) + 1
    local offsetY = -(self._scrollOffset % self._lineHeight)
    
    for slot = 1, self._visibleLineCount do
        local lineIdx = startLine + slot - 1
        local y = self._absY + offsetY + (slot - 1) * self._lineHeight
        
        -- Line number
        if self._showLineNumbers and self._lineNumberPool[slot] then
            local lnObj = self._lineNumberPool[slot]
            if lineIdx <= #self._lines then
                lnObj.Text = tostring(lineIdx)
                lnObj.Position = Vector2.new(
                    self._absX + self._gutterWidth - (#tostring(lineIdx) * 7) - 4,
                    y + 2
                )
                lnObj.Visible = self._visible and y >= self._absY and y < self._absY + self._height
            else
                lnObj.Visible = false
            end
        end
        
        -- Segments
        local segments = self._segmentPool[slot]
        if segments then
            local tokens = lineIdx <= #self._tokenizedLines and self._tokenizedLines[lineIdx] or {}
            local xPos = self._absX + (self._showLineNumbers and self._gutterWidth + 8 or 8)
            
            for j = 1, self._maxSegments do
                local segObj = segments[j]
                if j <= #tokens then
                    local token = tokens[j]
                    segObj.Text = token[1]
                    segObj.Color = token[2]
                    segObj.Position = Vector2.new(xPos, y + 2)
                    segObj.Visible = self._visible and y >= self._absY and y < self._absY + self._height
                    
                    -- Advance X position (approximate character width)
                    xPos = xPos + #token[1] * (UI.Theme.FontSize * 0.5)
                else
                    segObj.Visible = false
                end
            end
        end
    end
end

function TextBlock:onScroll(delta)
    local maxScroll = math.max(0, #self._lines * self._lineHeight - self._height)
    self._scrollOffset = math.clamp(self._scrollOffset - delta * 30, 0, maxScroll)
    self:_renderVisibleLines()
end

function TextBlock:setVisible(visible)
    self._visible = visible
    self._bg:setVisible(visible)
    if self._gutterBg then
        self._gutterBg.Visible = visible
    end
    if visible then
        self:_renderVisibleLines()
    else
        -- Hide all pool objects
        for _, lnObj in pairs(self._lineNumberPool) do
            lnObj.Visible = false
        end
        for _, segs in pairs(self._segmentPool) do
            for _, segObj in pairs(segs) do
                segObj.Visible = false
            end
        end
    end
end

function TextBlock:destroy()
    Input.unregister(self)
    Widget.destroy(self)
end

UI.TextBlock = TextBlock

----------------------------------------------------------------------
-- ListItem Widget
----------------------------------------------------------------------
local ListItem = setmetatable({}, {__index = Widget})
ListItem.__index = ListItem

function ListItem.new(props)
    local self = Widget.new(props)
    setmetatable(self, ListItem)
    self._interactive = true
    
    self._key = props.key or ""
    self._value = props.value or ""
    self._keyColor = props.keyColor or UI.Theme.Text
    self._valueColor = props.valueColor or UI.Theme.TextDim
    self._index = props.index or 0
    self._expanded = false
    self._expandedContent = props.expandedContent or nil
    self._onClick = props.onClick or nil
    
    -- Row background (alternating colors)
    local bgColor = self._index % 2 == 0 and UI.Theme.Surface or UI.Theme.Background
    self._rowBg = Pool.get("Square")
    self._rowBg.Size = Vector2.new(self._width, self._height)
    self._rowBg.Position = Vector2.new(self._absX, self._absY)
    self._rowBg.Color = bgColor
    self._rowBg.Filled = true
    self._rowBg.Thickness = 0
    self._rowBg.ZIndex = self._zIndex
    self._rowBg.Visible = false
    table.insert(self._drawingObjects, self._rowBg)
    
    -- Key label
    self._keyLabel = Pool.get("Text")
    self._keyLabel.Text = self._key
    self._keyLabel.Position = Vector2.new(self._absX + UI.Theme.Padding, self._absY + 2)
    self._keyLabel.Color = self._keyColor
    self._keyLabel.Size = UI.Theme.FontSize
    self._keyLabel.Font = 2
    self._keyLabel.ZIndex = self._zIndex + 2
    self._keyLabel.Visible = false
    table.insert(self._drawingObjects, self._keyLabel)
    
    -- Value label
    local valueX = self._absX + math.max(self._width * 0.4, 150)
    self._valueLabel = Pool.get("Text")
    self._valueLabel.Text = self._value
    self._valueLabel.Position = Vector2.new(valueX, self._absY + 2)
    self._valueLabel.Color = self._valueColor
    self._valueLabel.Size = UI.Theme.FontSize
    self._valueLabel.Font = 2
    self._valueLabel.ZIndex = self._zIndex + 2
    self._valueLabel.Visible = false
    table.insert(self._drawingObjects, self._valueLabel)
    
    Input.register(self)
    
    return self
end

function ListItem:setKeyValue(key, value, valueColor)
    self._key = key
    self._value = value
    if valueColor then self._valueColor = valueColor end
    
    if self._keyLabel then self._keyLabel.Text = key end
    if self._valueLabel then
        self._valueLabel.Text = value
        if valueColor then self._valueLabel.Color = valueColor end
    end
end

function ListItem:updatePosition(x, y)
    self._absX = x
    self._absY = y
    
    if self._rowBg then
        self._rowBg.Position = Vector2.new(x, y)
    end
    if self._keyLabel then
        self._keyLabel.Position = Vector2.new(x + UI.Theme.Padding, y + 2)
    end
    if self._valueLabel then
        local valueX = x + math.max(self._width * 0.4, 150)
        self._valueLabel.Position = Vector2.new(valueX, y + 2)
    end
end

function ListItem:setVisible(visible)
    self._visible = visible
    for _, obj in ipairs(self._drawingObjects) do
        pcall(function() obj.Visible = visible end)
    end
end

function ListItem:onClick(pos)
    if self._onClick then
        self._onClick(self)
    end
end

function ListItem:onHoverStart()
    if self._rowBg then
        self._rowBg.Color = UI.Theme.SurfaceHover
    end
end

function ListItem:onHoverEnd()
    local bgColor = self._index % 2 == 0 and UI.Theme.Surface or UI.Theme.Background
    if self._rowBg then
        self._rowBg.Color = bgColor
    end
end

function ListItem:destroy()
    Input.unregister(self)
    for _, obj in ipairs(self._drawingObjects) do
        Pool.release(obj)
    end
    self._drawingObjects = {}
    self._visible = false
end

UI.ListItem = ListItem

----------------------------------------------------------------------
-- TextInput Widget (simple keyboard-driven)
----------------------------------------------------------------------
local TextInput = setmetatable({}, {__index = Widget})
TextInput.__index = TextInput

function TextInput.new(props)
    local self = Widget.new(props)
    setmetatable(self, TextInput)
    self._interactive = true
    self._focusable = true
    
    self._text = props.text or ""
    self._placeholder = props.placeholder or "Type here..."
    self._onSubmit = props.onSubmit or nil
    self._onChange = props.onChange or nil
    self._isFocused = false
    
    -- Background
    self._bgRect = Rect.new({
        x = 0, y = 0,
        width = self._width,
        height = self._height,
        fillColor = UI.Theme.Surface,
        borderColor = UI.Theme.Border,
        borderThickness = 1,
        zIndex = self._zIndex,
    })
    self:addChild(self._bgRect)
    
    -- Text display
    self._textObj = Pool.get("Text")
    self._textObj.Text = self._placeholder
    self._textObj.Position = Vector2.new(self._absX + UI.Theme.Padding, self._absY + 3)
    self._textObj.Color = UI.Theme.TextDim
    self._textObj.Size = UI.Theme.FontSize
    self._textObj.Font = 2
    self._textObj.ZIndex = self._zIndex + 3
    self._textObj.Visible = false
    table.insert(self._drawingObjects, self._textObj)
    
    -- Cursor (blinking line)
    self._cursor = Pool.get("Square")
    self._cursor.Size = Vector2.new(1, UI.Theme.FontSize)
    self._cursor.Position = Vector2.new(self._absX + UI.Theme.Padding, self._absY + 3)
    self._cursor.Color = UI.Theme.Text
    self._cursor.Filled = true
    self._cursor.Thickness = 0
    self._cursor.ZIndex = self._zIndex + 4
    self._cursor.Visible = false
    table.insert(self._drawingObjects, self._cursor)
    
    Input.register(self)
    
    return self
end

function TextInput:onFocus()
    self._isFocused = true
    self._bgRect:setFillColor(UI.Theme.SurfaceLight)
    self._bgRect:redraw()
    self:_updateDisplay()
end

function TextInput:onBlur()
    self._isFocused = false
    self._bgRect:setFillColor(UI.Theme.Surface)
    self._bgRect:redraw()
    self._cursor.Visible = false
    self:_updateDisplay()
end

function TextInput:onKeyPress(keyCode)
    if not self._isFocused then return end
    
    local keyName = keyCode.Name
    
    if keyCode == Enum.KeyCode.Backspace then
        if #self._text > 0 then
            self._text = string.sub(self._text, 1, -2)
            self:_updateDisplay()
            if self._onChange then self._onChange(self._text) end
        end
    elseif keyCode == Enum.KeyCode.Return then
        if self._onSubmit then self._onSubmit(self._text) end
    elseif keyCode == Enum.KeyCode.Escape then
        if Input._focused == self then
            Input._focused = nil
            self:onBlur()
        end
    else
        -- Try to get the character
        local char = nil
        if #keyName == 1 then
            -- Check shift
            local UIS = game:GetService("UserInputService")
            local shifted = UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift)
            char = shifted and keyName:upper() or keyName:lower()
        elseif keyCode == Enum.KeyCode.Space then
            char = " "
        elseif keyCode == Enum.KeyCode.Period then
            char = "."
        elseif keyCode == Enum.KeyCode.Minus then
            char = "-"
        elseif keyCode == Enum.KeyCode.Underscore or keyName == "Underscore" then
            char = "_"
        end
        
        if char then
            self._text = self._text .. char
            self:_updateDisplay()
            if self._onChange then self._onChange(self._text) end
        end
    end
end

function TextInput:_updateDisplay()
    if self._textObj then
        if #self._text > 0 then
            self._textObj.Text = self._text
            self._textObj.Color = UI.Theme.Text
        else
            self._textObj.Text = self._placeholder
            self._textObj.Color = UI.Theme.TextDim
        end
    end
    
    if self._cursor and self._isFocused then
        local textWidth = #self._text * (UI.Theme.FontSize * 0.5)
        self._cursor.Position = Vector2.new(
            self._absX + UI.Theme.Padding + textWidth + 1,
            self._absY + 3
        )
        self._cursor.Visible = true
    end
end

function TextInput:getText()
    return self._text
end

function TextInput:setText(text)
    self._text = text
    self:_updateDisplay()
end

function TextInput:clear()
    self._text = ""
    self:_updateDisplay()
    if self._onChange then self._onChange("") end
end

function TextInput:setVisible(visible)
    self._visible = visible
    self._bgRect:setVisible(visible)
    if self._textObj then self._textObj.Visible = visible end
    if self._cursor then self._cursor.Visible = visible and self._isFocused end
end

function TextInput:destroy()
    Input.unregister(self)
    Widget.destroy(self)
end

UI.TextInput = TextInput

----------------------------------------------------------------------
-- Notification Widget
----------------------------------------------------------------------
local Notification = {}
UI.Notification = Notification

local _notifQueue = {}

function Notification.show(text, duration, color)
    duration = duration or 1.5
    color = color or UI.Theme.Success
    
    local vw, vh = UI.getViewport()
    local viewportSize = Vector2.new(vw, vh)
    
    -- Background
    local bg = Drawing.new("Square")
    local bgShadow = Drawing.new("Square")
    bg.Size = Vector2.new(#text * 8 + 20, 28)
    bg.Position = Vector2.new(
        viewportSize.X / 2 - (#text * 8 + 20) / 2,
        viewportSize.Y - 80
    )
    bg.Color = UI.Theme.Surface
    bg.Filled = true
    bg.Thickness = 0
    bg.Transparency = 0.9
    bg.ZIndex = 10000
    bg.Visible = true
    bgShadow.Size = bg.Size
    bgShadow.Position = Vector2.new(bg.Position.X + 4, bg.Position.Y + 5)
    bgShadow.Color = Color3.fromRGB(0, 0, 0)
    bgShadow.Filled = true
    bgShadow.Thickness = 0
    bgShadow.Transparency = 0.7
    bgShadow.ZIndex = 9999
    bgShadow.Visible = true
    
    -- Border
    local border = Drawing.new("Square")
    border.Size = bg.Size
    border.Position = bg.Position
    border.Color = color
    border.Filled = false
    border.Thickness = 1
    border.Transparency = 0.9
    border.ZIndex = 10001
    border.Visible = true
    
    -- Text
    local textObj = Drawing.new("Text")
    textObj.Text = text
    textObj.Position = Vector2.new(
        viewportSize.X / 2,
        bg.Position.Y + 5
    )
    textObj.Color = color
    textObj.Size = UI.Theme.FontSize
    textObj.Font = 2
    textObj.Center = true
    textObj.ZIndex = 10002
    textObj.Visible = true

    -- Slide-up entrance (square edges, magenta border stays sharp)
    local finalY = bg.Position.Y
    for _, o in ipairs({bg, border}) do
        o.Position = Vector2.new(o.Position.X, finalY + 18)
    end
    textObj.Position = Vector2.new(textObj.Position.X, finalY + 23)
    UI.tween(0.16, function(t)
        local y = finalY + 18 * (1 - t)
        bg.Position = Vector2.new(bg.Position.X, y)
        bgShadow.Position = Vector2.new(bg.Position.X + 4, y + 5)
        border.Position = Vector2.new(border.Position.X, y)
        textObj.Position = Vector2.new(textObj.Position.X, y + 5)
    end)
    
    -- Auto-hide after duration
    task.delay(duration, function()
        pcall(function()
            bg:Remove()
            bgShadow:Remove()
            border:Remove()
            textObj:Remove()
        end)
    end)
end

----------------------------------------------------------------------
-- Main Window Assembly
----------------------------------------------------------------------
local MainWindow = {}
UI.MainWindow = MainWindow

-- ponytail: one-liner chrome squares/text (bars, ticks, dividers, headers)
local function chromeSquare(x, y, w, h, color, z)
    local o = Pool.get("Square")
    o.Size = Vector2.new(w, h)
    o.Position = Vector2.new(x, y)
    o.Color = color
    o.Filled = true
    o.Thickness = 0
    o.Transparency = 1
    o.ZIndex = z
    o.Visible = false
    table.insert(Analyzer._drawingObjects, o)
    table.insert(UI._chrome, o)
    return o
end

local function chromeText(text, x, y, color, size, z)
    local o = Pool.get("Text")
    o.Text = text
    o.Position = Vector2.new(x, y)
    o.Color = color
    o.Size = size
    o.Font = 2
    o.ZIndex = z
    o.Visible = false
    table.insert(Analyzer._drawingObjects, o)
    table.insert(UI._chrome, o)
    return o
end

local _mainWindow = nil
local _sections = nil -- Sections shim (registerContent/switchTab API the modules use)
UI._chrome = {} -- window furniture toggled together

function MainWindow.create()
    local vw, vh = UI.getViewport()
    -- ponytail: shrink margin on small screens so content stays usable
    local margin = vw < 900 and 10 or UI.Theme.WindowMargin
    
    local winX = margin
    local winY = margin
    local winW = vw - margin * 2
    local winH = vh - margin * 2
    local menuH = UI.Theme.MenuHeight
    local headH = UI.Theme.PaneHeadHeight
    local pad = 8
    local treeW = math.max(200, math.floor(winW * 0.34))
    local paneTop = winY + UI.Theme.TitleBarHeight + 1 + menuH + 1
    local paneH = winY + winH - paneTop
    
    -- Store dimensions globally
    UI._windowX = winX
    UI._windowY = winY
    UI._windowW = winW
    UI._windowH = winH
    UI._treeArea = {x = winX + pad, y = paneTop + headH, width = treeW - pad * 2, height = paneH - headH}
    UI._contentArea = {x = winX + treeW + pad, y = paneTop + headH, width = winW - treeW - pad * 2, height = paneH - headH}
    UI._chrome = {}
    UI._titleBarBg, UI._titleText, UI._statsText, UI._titleBorder = nil, nil, nil, nil
    UI._menuBar, UI._sectionLabel, UI._contentFlash = nil, nil, nil
    
    -- Drop shadow (single offset layer, no rounded edges anywhere)
    table.insert(UI._chrome, UI.shadow(winX, winY, winW, winH, 99))

    -- Window background
    _mainWindow = Rect.new({
        x = winX,
        y = winY,
        width = winW,
        height = winH,
        fillColor = UI.Theme.Background,
        borderColor = UI.Theme.Border,
        borderThickness = 1,
        zIndex = 100,
    })
    
    -- Title bar
    local titleBarBg = Pool.get("Square")
    titleBarBg.Size = Vector2.new(winW, UI.Theme.TitleBarHeight)
    titleBarBg.Position = Vector2.new(winX, winY)
    titleBarBg.Color = UI.Theme.Surface
    titleBarBg.Filled = true
    titleBarBg.Thickness = 0
    titleBarBg.ZIndex = 101
    titleBarBg.Visible = false
    table.insert(Analyzer._drawingObjects, titleBarBg)
    UI._titleBarBg = titleBarBg
    table.insert(UI._chrome, titleBarBg)
    
    -- Title text
    local titleText = Pool.get("Text")
    titleText.Text = "// " .. string.upper(Analyzer._name) .. " v" .. Analyzer._version
    titleText.Position = Vector2.new(winX + UI.Theme.Padding, winY + 6)
    titleText.Color = UI.Theme.Accent
    titleText.Size = UI.Theme.FontSize
    titleText.Font = 2
    titleText.ZIndex = 102
    titleText.Visible = false
    table.insert(Analyzer._drawingObjects, titleText)
    UI._titleText = titleText
    table.insert(UI._chrome, titleText)
    
    -- Pool stats text (top right)
    local statsText = Pool.get("Text")
    statsText.Text = ""
    statsText.Position = Vector2.new(winX + winW - 200, winY + 6)
    statsText.Color = UI.Theme.TextDark
    statsText.Size = UI.Theme.SmallFontSize
    statsText.Font = 2
    statsText.ZIndex = 102
    statsText.Visible = false
    table.insert(Analyzer._drawingObjects, statsText)
    UI._statsText = statsText
    table.insert(UI._chrome, statsText)
    
    -- Title bar border bottom
    local titleBorder = Pool.get("Square")
    titleBorder.Size = Vector2.new(winW, 1)
    titleBorder.Position = Vector2.new(winX, winY + UI.Theme.TitleBarHeight)
    titleBorder.Color = UI.Theme.Accent
    titleBorder.Filled = true
    titleBorder.Thickness = 0
    titleBorder.ZIndex = 101
    titleBorder.Visible = false
    table.insert(Analyzer._drawingObjects, titleBorder)
    UI._titleBorder = titleBorder
    table.insert(UI._chrome, titleBorder)
    
    -- Section menu (flat tabs + one shared sliding magenta bar)
    local menuY = winY + UI.Theme.TitleBarHeight + 1
    local sectionNames = {"Properties", "Scripts", "Remote Spy", "Export"}
    local tabW = math.floor(winW / #sectionNames)
    _sections = { _tabs = {}, _contentPanels = {}, _activeTab = nil }
    for i, sname in ipairs(sectionNames) do
        local tab = Tab.new({
            x = winX + (i - 1) * tabW,
            y = menuY,
            width = tabW,
            height = menuH,
            text = string.upper(sname),
            tabName = sname,
            noUnderline = true,
            zIndex = 110,
            onClick = function() _sections:switchTab(sname) end,
        })
        _sections._tabs[sname] = tab
    end
    chromeSquare(winX, menuY + menuH - 1, winW, 1, UI.Theme.Border, 109)
    UI._menuBar = chromeSquare(winX, menuY + menuH - 2, tabW, 2, UI.Theme.Magenta, 111)

    -- Left pane header (explorer) + divider + right pane header
    chromeSquare(winX, paneTop, treeW, headH, UI.Theme.Surface, 105)
    chromeSquare(winX, paneTop, 3, headH, UI.Theme.Accent, 106)
    chromeText("// EXPLORER", winX + 10, paneTop + 4, UI.Theme.TextDim, UI.Theme.SmallFontSize, 106)
    chromeSquare(winX + treeW, paneTop, 1, paneH, UI.Theme.BorderLight, 105)
    chromeSquare(winX + treeW + 1, paneTop, winW - treeW - 1, headH, UI.Theme.Surface, 105)
    chromeSquare(winX + treeW + 1, paneTop, 3, headH, UI.Theme.Magenta, 106)
    UI._sectionLabel = chromeText("// PROPERTIES", winX + treeW + 11, paneTop + 4, UI.Theme.Magenta, UI.Theme.SmallFontSize, 106)

    -- Content-switch flash frame (border-only, rests invisible)
    local flash = Pool.get("Square")
    flash.Size = Vector2.new(UI._contentArea.width, UI._contentArea.height)
    flash.Position = Vector2.new(UI._contentArea.x, UI._contentArea.y)
    flash.Color = UI.Theme.Magenta
    flash.Filled = false
    flash.Thickness = 1
    flash.Transparency = 1
    flash.ZIndex = 130
    flash.Visible = false
    table.insert(Analyzer._drawingObjects, flash)
    table.insert(UI._chrome, flash)
    UI._contentFlash = flash

    function _sections:switchTab(tabName)
        if self._activeTab == tabName then return end
        local oldTab = self._activeTab
        self._activeTab = tabName
        for name, tab in pairs(self._tabs) do tab:setActive(name == tabName) end
        for name, panel in pairs(self._contentPanels) do
            if panel.setVisible then panel:setVisible(name == tabName and Analyzer._visible) end
        end
        local tab = self._tabs[tabName]
        if tab and UI._menuBar then
            UI._menuBarSeq = (UI._menuBarSeq or 0) + 1
            local seq, bar, fromX, toX = UI._menuBarSeq, UI._menuBar, UI._menuBar.Position.X, tab._absX
            UI.tween(0.14, function(t)
                if seq ~= UI._menuBarSeq then return end
                bar.Position = Vector2.new(fromX + (toX - fromX) * t, bar.Position.Y)
            end)
        end
        if UI._sectionLabel then
            UI._sectionLabel.Text = "// " .. string.upper(tabName)
        end
        if UI._contentFlash and Analyzer._visible then
            local fl = UI._contentFlash
            fl.Visible = true
            UI.tween(0.3, function(t) fl.Transparency = 0.2 + 0.8 * t end)
        end
        Analyzer.Signals.TabChanged:Fire(tabName, oldTab)
    end
    function _sections:registerContent(tabName, panel)
        self._contentPanels[tabName] = panel
        panel:setVisible(tabName == self._activeTab and Analyzer._visible)
    end
    function _sections:getActiveTab() return self._activeTab end

    -- Accent pulse on the title line (one object, cheap heartbeat)
    UI._pulseOn = true
    local accentLine = titleBorder
    task.spawn(function()
        local t = 0
        while UI._pulseOn and getgenv().Analyzer ~= nil do
            task.wait(0.06)
            t = t + 0.06
            pcall(function()
                accentLine.Transparency = 0.55 + 0.45 * math.abs(math.sin(t * 2.2))
            end)
        end
    end)
    
    -- Default section (tree is always visible on the left)
    _sections:switchTab("Properties")
    
    -- Start hidden
    MainWindow.setVisible(false)
    
    return _mainWindow
end

function MainWindow.setVisible(visible)
    if _mainWindow then
        _mainWindow:setVisible(visible)
    end
    for _, obj in ipairs(UI._chrome or {}) do
        pcall(function() obj.Visible = visible end)
    end
    if _sections then
        for _, tab in pairs(_sections._tabs) do tab:setVisible(visible) end
    end
    if UI._statsText and visible then
        local stats = Pool.getStats()
        UI._statsText.Text = string.format("Drawing: %d active / %d pooled", stats.active, stats.pooled)
    end
    if _sections and _sections._activeTab then
        -- ponytail: re-fire so modules refresh their pooled rows on toggle
        pcall(function() Analyzer.Signals.TabChanged:Fire(_sections._activeTab, nil) end)
    end
end

function MainWindow.getTabContainer()
    return _sections
end

function MainWindow.getContentArea()
    return UI._contentArea
end

function MainWindow.getTreeArea()
    return UI._treeArea
end

----------------------------------------------------------------------
-- Module Init / Cleanup
----------------------------------------------------------------------
function UI.init()
    -- ponytail: loud env check — Pool is assigned at chunk load; if it's gone,
    -- the executor mangled chunk state (not our logic), and we say so plainly
    assert(type(Pool) == "table" and type(Pool.get) == "function",
        "[Analyzer] UI chunk state corrupt: Pool missing at init (executor chunk bug?)")
    Input.setup()
    MainWindow.create()
    UI._watchResize()
    print("[Analyzer] UI Framework initialized")
end

-- ponytail: rebuild (not reposition) on resize — reuses tested init paths.
-- Polls 2x/sec; skips sub-2px jitter; debounces 0.5s through drag-resizes.
function UI._watchResize()
    if UI._watching then return end
    UI._watching = true
    task.spawn(function()
        local lastW, lastH = UI.getViewport()
        local pending = false
        while UI._watching do
            task.wait(0.5)
            if getgenv().Analyzer == nil then break end
            local w, h = UI.getViewport()
            if math.abs(w - lastW) > 2 or math.abs(h - lastH) > 2 then
                lastW, lastH = w, h
                if not pending then
                    pending = true
                    task.delay(0.5, function()
                        pending = false
                        if pcall(UI.rebuild) then
                            lastW, lastH = UI.getViewport()
                        end
                    end)
                end
            end
        end
    end)
end

function UI.rebuild()
    if not Analyzer._loaded then return end
    local wasVisible = Analyzer._visible
    local mods = {"Explorer", "Properties", "ScriptViewer", "RemoteSpy", "Export"}
    for _, m in ipairs(mods) do
        if Analyzer[m] and Analyzer[m].cleanup then pcall(Analyzer[m].cleanup) end
    end
    UI.cleanup()
    Input.setup()
    MainWindow.create()
    UI._watchResize()
    Analyzer._initModules()
    if wasVisible then MainWindow.setVisible(true) end
end

function UI.setVisible(visible)
    MainWindow.setVisible(visible)
end

function UI.cleanup()
    UI._watching = false
    UI._pulseOn = false
    Pool.releaseAll()
    
    for _, conn in ipairs(Input._connections) do
        pcall(function() conn:Disconnect() end)
    end
    Input._connections = {}
    Input._widgets = {}
    
    _mainWindow = nil
    _sections = nil
end


]===],
["export.lua"] = [===[
--[[ Analyzer — Export: saveinstance / writefile / clipboard, status line ]]
local Analyzer = getgenv().Analyzer
if not Analyzer then error("[Analyzer] Export loaded before loader.") return end
local UI = Analyzer.UI
if not UI then error("[Analyzer] Export needs UI first.") return end

local Export = {}
Analyzer.Export = Export

local function status(msg, color)
    if Export._label then
        Export._label:setText(msg:sub(1, 100))
        Export._label:setColor(color or UI.Theme.Text)
        Export._label:redraw()
    end
    print("[Analyzer] " .. msg)
end

function Export.init()
    local area = UI.MainWindow.getContentArea()
    local tabs = UI.MainWindow.getTabContainer()
    local holder = UI.Widget.new({x = area.x, y = area.y, width = area.width, height = area.height, zIndex = 115})
    holder.redraw = function() end
    Export._label = UI.Label.new({x = area.x + 8, y = area.y + 8, text = "Export tools",
        textColor = UI.Theme.Text, zIndex = 121})
    local y = area.y + 36
    Export._btns = {}
    local function btn(text, fn)
        local b = UI.Button.new({x = area.x + 8, y = y, width = 220, height = 28,
            text = text, zIndex = 121, onClick = fn})
        y = y + 34
        table.insert(Export._btns, b)
        return b
    end
    btn("Save Full Game (saveinstance)", function()
        local si = getgenv().saveinstance
        if type(si) ~= "function" then status("saveinstance() missing", UI.Theme.Warning) return end
        local ok, err = pcall(si) status(ok and "Saved via saveinstance" or "Fail: "..tostring(err):sub(1,60),
            ok and UI.Theme.Success or UI.Theme.Error)
    end)
    btn("Copy Selected Path", function()
        local sc = getgenv().setclipboard
        if type(sc) ~= "function" then status("setclipboard() missing", UI.Theme.Warning) return end
        local sel = Analyzer.Explorer and Analyzer.Explorer._selected
        local inst = sel and sel._instance
        if inst then pcall(sc, inst:GetFullName()) status("Copied: "..inst.Name, UI.Theme.Success)
        else status("Nothing selected", UI.Theme.Warning) end
    end)
    btn("Dump Remote Log", function()
        local wf = getgenv().writefile
        local lines = {}
        if Analyzer.RemoteSpy then for _, e in ipairs(Analyzer.RemoteSpy._log) do
            table.insert(lines, e.time.." "..e.path.." "..e.args) end end
        if type(wf) == "function" then
            local ok = pcall(wf, "analyzer_remotes.txt", table.concat(lines, "\n"))
            status(ok and "Wrote analyzer_remotes.txt" or "writefile failed",
                ok and UI.Theme.Success or UI.Theme.Error)
        elseif type(getgenv().setclipboard) == "function" then
            pcall(getgenv().setclipboard, table.concat(lines, "\n")) status("Copied log", UI.Theme.Success)
        else status("No writefile/clipboard", UI.Theme.Warning) end
    end)
    tabs:registerContent("Export", holder)
    Export._conns = Export._conns or {}
    table.insert(Export._conns, Analyzer.Signals.TabChanged:Connect(function(name)
        local show = Analyzer._visible and name == "Export"
        if Export._label then Export._label:setVisible(show) end
        for _, b in ipairs(Export._btns or {}) do b:setVisible(show) end
    end))
    print("[Analyzer] Export initialized")
end

function Export.cleanup()
    for _, c in ipairs(Export._conns or {}) do pcall(function() c.Disconnect(c) end) end
    Export._conns = {}
end


]===],
["explorer.lua"] = [===[
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

function Explorer.cleanup()
    for _, c in ipairs(Explorer._conns) do pcall(function() c.Disconnect(c) end) end
    Explorer._conns = {}
    for _, row in ipairs(Explorer._nodes) do pcall(function() row.node:destroy() end) end
    Explorer._nodes = {}
    Explorer._selected = nil
end


]===],
["properties.lua"] = [===[
--[[ Analyzer — Properties: live snapshot + GetPropertyChangedSignal ]]
local Analyzer = getgenv().Analyzer
if not Analyzer then error("[Analyzer] Properties loaded before loader.") return end
local UI = Analyzer.UI
if not UI then error("[Analyzer] Properties needs UI first.") return end

local Properties = {}
Analyzer.Properties = Properties
Properties._items = {}
Properties._propConns = {}
Properties._conns = {}
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
    table.insert(Properties._conns, Analyzer.Signals.InstanceSelected:Connect(function(inst)
        tabs:switchTab("Properties")
        Properties:show(inst)
    end))
    table.insert(Properties._conns, Analyzer.Signals.TabChanged:Connect(function(name)
        Properties._tabActive = (name == "Properties")
        Properties:_layout()
    end))
    Properties._tabActive = false
    print("[Analyzer] Properties initialized")
end

function Properties.cleanup()
    for _, c in ipairs(Properties._conns) do pcall(function() c.Disconnect(c) end) end
    Properties._conns = {}
    Properties:clear()
end


]===],
["script_viewer.lua"] = [===[
--[[ Analyzer — Script Viewer: decompile + inline highlight + virtual scroll ]]
local Analyzer = getgenv().Analyzer
if not Analyzer then error("[Analyzer] ScriptViewer loaded before loader.") return end
local UI = Analyzer.UI
if not UI then error("[Analyzer] ScriptViewer needs UI first.") return end

local SV = {}
Analyzer.ScriptViewer = SV
SV._conns = {}

local KW = {["local"]=1,["function"]=1,["end"]=1,["if"]=1,["then"]=1,["else"]=1,
    ["elseif"]=1,["for"]=1,["while"]=1,["do"]=1,["return"]=1,["nil"]=1,["true"]=1,
    ["false"]=1,["and"]=1,["or"]=1,["not"]=1,["in"]=1,["repeat"]=1,["until"]=1,["break"]=1}
local BUILTIN = {game=1, workspace=1, script=1, print=1, pairs=1, ipairs=1, tostring=1,
    tonumber=1, task=1, require=1, table=1, string=1, math=1, Instance=1}

local function tokenize(line)
    local segs, i, n = {}, 1, #line
    local function push(t, c) -- ponytail: merge runs, cap 8 segs/line in TextBlock
        if #segs > 0 and segs[#segs][2] == c then segs[#segs][1] = segs[#segs][1] .. t
        else table.insert(segs, {t, c}) end
    end
    while i <= n do
        local c = line:sub(i, i)
        if c == "-" and line:sub(i, i+1) == "--" then push(line:sub(i), UI.Theme.Syntax.Comment) break
        elseif c == '"' or c == "'" then
            local j = line:find(c, i+1) or n
            push(line:sub(i, j), UI.Theme.Syntax.String) i = j + 1
        elseif c:match("%d") then
            local num = line:match("^%d+%.?%d*", i) push(num, UI.Theme.Syntax.Number) i = i + #num
        elseif c:match("[%a_]") then
            local w = line:match("^[%a_][%w_]*", i)
            push(w, KW[w] and UI.Theme.Syntax.Keyword or BUILTIN[w] and UI.Theme.Syntax.BuiltIn or UI.Theme.Syntax.Default)
            i = i + #w
        else push(c, UI.Theme.Syntax.Default) i = i + 1 end
    end
    if #segs == 0 then segs = {{"", UI.Theme.Syntax.Default}} end
    while #segs > 8 do table.remove(segs) end -- ponytail: truncate exotic lines
    return segs
end

function SV:view(inst)
    if not inst then return end
    local label = inst:GetFullName()
    local src = "-- select a Script / LocalScript / ModuleScript"
    if inst:IsA("LuaSourceContainer") then
        local dec = getgenv().decompile
        if type(dec) == "function" then
            local ok, out = pcall(dec, inst)
            src = (ok and type(out) == "string") and out or ("-- decompile failed: " .. tostring(out):sub(1,120))
        else
            local g = getgenv().getscriptbytecode
            if type(g) == "function" then
                local ok = pcall(g, inst)
                src = ok and "-- bytecode only (no decompiler); showing disassembly unsupported in v1" or src
            else src = "-- no decompile() in this executor (needs UNC decompile)" end
        end
    end
    self._path:setText(label:sub(1, 90))
    self._path:redraw()
    self._block:setContent(src)
end

function SV.init()
    local area = UI.MainWindow.getContentArea()
    local tabs = UI.MainWindow.getTabContainer()
    local holder = UI.Widget.new({x = area.x, y = area.y, width = area.width, height = area.height, zIndex = 115})
    holder.redraw = function() end
    SV._path = UI.Label.new({x = area.x + 8, y = area.y + 4, text = "No script selected",
        textColor = UI.Theme.Accent, zIndex = 121})
    SV._copy = UI.Button.new({x = area.x + area.width - 88, y = area.y + 2, width = 80, height = 24,
        text = "Copy", zIndex = 121, onClick = function()
            local sc = getgenv().setclipboard
            if type(sc) == "function" and SV._block._lines then
                pcall(sc, table.concat(SV._block._lines, "\n"))
                UI.Notification.show("Copied", 1)
            end
        end})
    SV._block = UI.TextBlock.new({x = area.x, y = area.y + 30, width = area.width,
        height = area.height - 30, zIndex = 120, tokenizer = tokenize, maxSegments = 8})
    tabs:registerContent("Scripts", holder)
    table.insert(SV._conns, Analyzer.Signals.ScriptRequested:Connect(function(inst)
        if inst and inst:IsA("LuaSourceContainer") then
            tabs:switchTab("Scripts")
            SV:view(inst)
        end
    end))
    table.insert(SV._conns, Analyzer.Signals.TabChanged:Connect(function(name)
        local show = Analyzer._visible and name == "Scripts"
        SV._path:setVisible(show)
        SV._copy:setVisible(show)
        SV._block:setVisible(show)
    end))
    SV._block:setContent("-- click a Script in Explorer to decompile")
    print("[Analyzer] ScriptViewer initialized")
end

function SV.cleanup()
    for _, c in ipairs(SV._conns) do pcall(function() c.Disconnect(c) end) end
    SV._conns = {}
end


]===],
["remote_spy.lua"] = [===[
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
        if (method == "FireServer" or method == "InvokeServer")
            and (selfObj:IsA("RemoteEvent") or selfObj:IsA("RemoteFunction")) then
            pcall(function() Spy:push("OUT", selfObj, method, ...) end)
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


]===],
}

local function compileModule(filename, src)
    -- ponytail: capture loadstring's REAL error (2nd return), never swallow it
    local fn, cerr = loadstring(src, "@" .. filename)
    if not fn then error("compile failed: " .. tostring(cerr)) end
    return fn()
end

local function fetchModule(url)
    local src = game:HttpGet(url, true)
    -- ponytail: every module starts with "--[["; anything else is proxy/stale junk -> retry once
    if type(src) ~= "string" or src:sub(1, 4) ~= "--[[" then
        warn("[" .. CONFIG.NAME .. "] ⚠️ bad payload for " .. url .. " (got: " .. tostring(src):sub(1, 80) .. "), retrying...")
        src = game:HttpGet(url, true)
    end
    return src
end

local function loadModule(name, filename)
    local success, result
    local src = nil

    if EMBEDDED and EMBEDDED[filename] then
        -- single-file release build: no network, no cache skew between files
        src = EMBEDDED[filename]
        success, result = pcall(compileModule, filename, src)
    else    if CONFIG.BASE_URL then
        -- Load from remote URL
        local url = CONFIG.BASE_URL .. "/" .. filename
        success, result = pcall(function()
            src = fetchModule(url)
            return src
        end)
        if success then
            success, result = pcall(compileModule, filename, src)
        end
    else
        -- Load from local workspace (development mode)
        -- Try readfile first, fall back to requiring from workspace
        if Analyzer._capabilities.readfile or (type(readfile) == "function") then
            success, result = pcall(function()
                local source = readfile(filename)
                return loadstring(source)()
            end)
        end
        
        if not success then
            -- Try direct loadstring from workspace path
            success, result = pcall(function()
                return loadstring(game:HttpGet("file://" .. filename, true))()
            end)
        end
    end
    
    if success then
        print("[" .. CONFIG.NAME .. "] ✅ Loaded: " .. name)
        return result
    else
        local err = tostring(result)
        warn("[" .. CONFIG.NAME .. "] ❌ Failed to load " .. name .. ": " .. err)
        -- ponytail: dump the offending source line so executor chunk-wrappers can't hide it
        local lnum = err:match(":(%d+):")
        if lnum and src then
            local lines = {}
            for line in (src .. "\n"):gmatch("(.-)\n") do table.insert(lines, line) end
            lnum = tonumber(lnum)
            for i = math.max(1, lnum - 2), math.min(#lines, lnum + 2) do
                warn(string.format("[%s] %s %d: %s", CONFIG.NAME, i == lnum and ">>>" or "   ", i, lines[i]:sub(1, 160)))
            end
            warn(string.format("[%s] (chunk has %d lines; if %d is beyond that, the executor wraps chunks)", CONFIG.NAME, #lines, lnum))
        end
        return nil
    end
end

----------------------------------------------------------------------
-- Safe Viewport (validates real screensize, falls back when unreadable)
----------------------------------------------------------------------
local function getSafeViewport()
    local w, h = 1280, 720 -- ponytail: fallback, real size when readable
    pcall(function()
        local cam = workspace.CurrentCamera
        if cam and cam.ViewportSize then
            local vs = cam.ViewportSize
            if vs.X > 100 and vs.Y > 100 then
                w, h = math.floor(vs.X), math.floor(vs.Y)
            end
        end
    end)
    return w, h
end

----------------------------------------------------------------------
-- Tray Icon
----------------------------------------------------------------------
local trayIcon = nil
local trayClickRegion = nil

local function createTrayIcon()
    local vw, vh = getSafeViewport()
    local viewportSize = Vector2.new(vw, vh)
    
    local x = viewportSize.X - CONFIG.TRAY_ICON_MARGIN - CONFIG.TRAY_ICON_RADIUS
    local y = viewportSize.Y - CONFIG.TRAY_ICON_MARGIN - CONFIG.TRAY_ICON_RADIUS
    
    trayIcon = Drawing.new("Square")
    trayIcon.Position = Vector2.new(x, y)
    trayIcon.Size = Vector2.new(CONFIG.TRAY_ICON_RADIUS * 2, CONFIG.TRAY_ICON_RADIUS * 2)
    trayIcon.Color = CONFIG.TRAY_ICON_COLOR
    trayIcon.Filled = true
    trayIcon.Thickness = 0
    trayIcon.Transparency = 0.8
    trayIcon.Visible = true
    trayIcon.ZIndex = 9999
    
    table.insert(Analyzer._drawingObjects, trayIcon)
    
    -- Outline frame (square: no rounded edges in this UI)
    local trayOutline = Drawing.new("Square")
    trayOutline.Position = Vector2.new(x - 2, y - 2)
    trayOutline.Size = Vector2.new(CONFIG.TRAY_ICON_RADIUS * 2 + 4, CONFIG.TRAY_ICON_RADIUS * 2 + 4)
    trayOutline.Color = Color3.fromRGB(60, 60, 60)
    trayOutline.Filled = false
    trayOutline.Thickness = 1
    trayOutline.Transparency = 0.6
    trayOutline.Visible = true
    trayOutline.ZIndex = 9998
    
    table.insert(Analyzer._drawingObjects, trayOutline)
    
    return x, y
end

----------------------------------------------------------------------
-- Input Handling (Keybind + Tray Click)
----------------------------------------------------------------------
local function setupInput(trayX, trayY)
    local UserInputService = game:GetService("UserInputService")
    -- ponytail: GetMouseLocation includes topbar inset; Drawing coords are absolute
    local function mousePos()
        local p = UserInputService:GetMouseLocation()
        pcall(function()
            p = p - game:GetService("GuiService"):GetGuiInset()
        end)
        return p
    end
    
    -- Toggle keybind
    local toggleConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        
        if input.KeyCode == CONFIG.TOGGLE_KEY then
            Analyzer._visible = not Analyzer._visible
            if Analyzer.UI and Analyzer.UI.setVisible then
                Analyzer.UI.setVisible(Analyzer._visible)
            end
            
            -- Update tray icon color
            if trayIcon then
                trayIcon.Color = Analyzer._visible 
                    and Color3.fromRGB(80, 200, 80) 
                    or CONFIG.TRAY_ICON_COLOR
            end
        end
    end)
    table.insert(Analyzer._connections, toggleConn)
    
    -- Tray icon click detection
    local clickConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end

        local dist = (mousePos() - Vector2.new(trayX + CONFIG.TRAY_ICON_RADIUS, trayY + CONFIG.TRAY_ICON_RADIUS)).Magnitude
        
        if dist <= CONFIG.TRAY_ICON_RADIUS + 5 then
            Analyzer._visible = not Analyzer._visible
            if Analyzer.UI and Analyzer.UI.setVisible then
                Analyzer.UI.setVisible(Analyzer._visible)
            end
            
            if trayIcon then
                trayIcon.Color = Analyzer._visible 
                    and Color3.fromRGB(80, 200, 80) 
                    or CONFIG.TRAY_ICON_COLOR
            end
        end
    end)
    table.insert(Analyzer._connections, clickConn)
end

----------------------------------------------------------------------
-- Master Cleanup Function
----------------------------------------------------------------------
function Analyzer._cleanup()
    print("[" .. CONFIG.NAME .. "] Cleaning up...")
    
    -- Disconnect all signals
    for _, conn in ipairs(Analyzer._connections) do
        pcall(function() conn:Disconnect() end)
    end
    Analyzer._connections = {}
    
    -- Destroy all Drawing objects
    for _, obj in ipairs(Analyzer._drawingObjects) do
        pcall(function() obj:Remove() end)
    end
    Analyzer._drawingObjects = {}
    
    -- Call module-specific cleanup
    local modules = {"UI", "Explorer", "Properties", "ScriptViewer", "RemoteSpy", "Export"}
    for _, modName in ipairs(modules) do
        if Analyzer[modName] and Analyzer[modName].cleanup then
            pcall(Analyzer[modName].cleanup)
        end
    end
    
    -- Restore hooked metamethods
    if Analyzer._originalNamecall then
        pcall(function()
            hookmetamethod(game, "__namecall", Analyzer._originalNamecall)
        end)
        Analyzer._originalNamecall = nil
    end
    
    -- Clear the global
    getgenv().Analyzer = nil
    
    print("[" .. CONFIG.NAME .. "] Cleanup complete.")
end

-- Re-initializes all feature modules (used by UI.rebuild() on resize)
function Analyzer._initModules()
    local modules = {"UI", "Explorer", "Properties", "ScriptViewer", "RemoteSpy", "Export"}
    for _, modName in ipairs(modules) do
        if Analyzer[modName] and Analyzer[modName].init then
            local ok, err = pcall(Analyzer[modName].init)
            if not ok then
                warn("[" .. CONFIG.NAME .. "] ⚠️ Failed to init " .. modName .. ": " .. tostring(err))
            end
        end
    end
end
local function main()
    -- Step 1: Detect capabilities
    local caps = detectCapabilities()
    
    -- Step 2: Print banner and check requirements
    local canStart = printBanner(caps)
    if not canStart then
        Analyzer._cleanup()
        return
    end
    
    -- Step 3: Load modules in dependency order
    print("[" .. CONFIG.NAME .. "] Loading modules...")
    
    local moduleOrder = {
        {"UI Framework",   "ui_framework.lua"},
        {"Export",         "export.lua"},
        {"Explorer",       "explorer.lua"},
        {"Properties",     "properties.lua"},
        {"Script Viewer",  "script_viewer.lua"},
        {"Remote Spy",     "remote_spy.lua"},
    }
    
    for _, mod in ipairs(moduleOrder) do
        loadModule(mod[1], mod[2])
        task.wait() -- yield between modules to prevent timeout
    end
    
    -- Step 4: Create tray icon
    local trayX, trayY = createTrayIcon()
    
    -- Step 5: Setup input
    setupInput(trayX, trayY)
    
    -- Step 6: Initialize all modules
    Analyzer._initModules()
    
    -- Step 7: Mark as loaded
    Analyzer._loaded = true
    print("[" .. CONFIG.NAME .. "] ✅ Ready! Press Right Shift or click the tray icon to toggle.")
    print("")
end

-- Run
main()
