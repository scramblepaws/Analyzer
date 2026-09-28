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

function Input.setup()
    local UIS = game:GetService("UserInputService")
    
    -- Mouse move
    local moveConn = UIS.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            -- ponytail: InputObject.Position shares Drawing's coordinate space;
            -- GetMouseLocation inset math misaligned clicks, so don't use it
            Input._mousePos = Vector2.new(input.Position.X, input.Position.Y)
            
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
            local pos = Vector2.new(input.Position.X, input.Position.Y)
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
            
            local pos = Vector2.new(input.Position.X, input.Position.Y)
            
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
    self:redrawSubtree()
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
    child:redrawSubtree()
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

-- ponytail: the whole point of v2 — one call repositions an entire subtree
function Widget:redrawSubtree()
    self:redraw()
    for _, child in ipairs(self._children) do
        child:redrawSubtree()
    end
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
    self._borderThickness = props.borderThickness or 0
    -- ponytail: explicit nil check — transparency 0 (invisible) is falsy but valid
    self._transparency = props.transparency
    if self._transparency == nil then self._transparency = 1 end
    
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
    self._expandIcon.Text = self._hasChildren and "+" or "  "
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
    self._expandIcon.Text = "-"
    
    if self._onExpand then
        self._onExpand(self)
    end
end

function TreeNode:collapse()
    if not self._expanded then return end
    self._expanded = false
    self._expandIcon.Text = "+"
    
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

function TextBlock:redraw()
    if self._bg then
        self._bg:_updateAbsolutePosition()
        self._bg:redraw()
    end
    if self._gutterBg then
        self._gutterBg.Position = Vector2.new(self._absX, self._absY)
        self._gutterBg.Size = Vector2.new(self._gutterWidth, self._height)
    end
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

function TextInput:redraw()
    if self._bgRect then
        self._bgRect:_updateAbsolutePosition()
        self._bgRect:redraw()
    end
    if self._textObj then
        self._textObj.Position = Vector2.new(self._absX + UI.Theme.Padding, self._absY + 3)
    end
    self:_updateDisplay()
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

local _mainWindow = nil -- v2: window ROOT; drag = one setPosition, cascaded
local _sections = nil -- Sections shim (registerContent/switchTab API the modules use)
local _treePane = nil -- v2: modules parent content here and read boxes, never pixels
local _contentPane = nil

-- ponytail: v2 chrome primitives — parented, relative coords, cascade for free
local function chromeRect(parent, x, y, w, h, color, z, opts)
    opts = opts or {}
    local r = Rect.new({
        x = x, y = y, width = w, height = h,
        fillColor = color, borderColor = opts.border or color,
        borderThickness = opts.border and 1 or 0,
        transparency = opts.transparency or 1, zIndex = z,
        interactive = false,
    })
    parent:addChild(r)
    return r
end

local function chromeLabel(parent, text, x, y, color, size, z)
    local l = Label.new({
        x = x, y = y, text = text, textColor = color, fontSize = size,
        zIndex = z, interactive = false,
    })
    parent:addChild(l)
    return l
end

function MainWindow.layoutAreas()
    local pad = 8
    local menuH = UI.Theme.MenuHeight
    local headH = UI.Theme.PaneHeadHeight
    local treeW = math.max(200, math.floor(UI._windowW * 0.34))
    local paneTop = UI._windowY + UI.Theme.TitleBarHeight + 1 + menuH + 1
    local paneH = UI._windowY + UI._windowH - paneTop
    UI._treeW, UI._paneTop, UI._paneH = treeW, paneTop, paneH
    UI._treeArea = {x = UI._windowX + pad, y = paneTop + headH, width = treeW - pad * 2, height = paneH - headH}
    UI._contentArea = {x = UI._windowX + treeW + pad, y = paneTop + headH, width = UI._windowW - treeW - pad * 2, height = paneH - headH}
end

function MainWindow.create()
    local vw, vh = UI.getViewport()
    -- ponytail: compact floating window, centered; tiny screens fall back to margins
    local winW, winH = 880, 560
    if vw < 920 then winW = vw - 20 end
    if vh < 600 then winH = vh - 20 end
    local winX, winY = math.floor((vw - winW) / 2), math.floor((vh - winH) / 2)
    
    -- Store dimensions globally
    UI._windowX = winX
    UI._windowY = winY
    UI._windowW = winW
    UI._windowH = winH
    MainWindow.layoutAreas()
    local menuH, headH, pad = UI.Theme.MenuHeight, UI.Theme.PaneHeadHeight, 8
    local treeW, paneTop, paneH = UI._treeW, UI._paneTop, UI._paneH
    _mainWindow = Widget.new({x = winX, y = winY, width = winW, height = winH, zIndex = 99, interactive = false})
    UI._titleText, UI._statsText = nil, nil
    UI._menuBar, UI._sectionLabel, UI._titlePulse, UI._flashBg, UI._dragHandle = nil, nil, nil, nil, nil
    UI._treePane, UI._contentPane = nil, nil
    
    -- Drop shadow (single offset layer, no rounded edges anywhere)
    chromeRect(_mainWindow, 5, 6, winW, winH, Color3.fromRGB(0, 0, 0), 98, {transparency = 0.7})

    -- Window background (root child; border via opts)
    chromeRect(_mainWindow, 0, 0, winW, winH, UI.Theme.Background, 100, {border = UI.Theme.Border})
    
    -- Title strip (node; children relative)
    local titleBar = Widget.new({x = 0, y = 0, width = winW, height = UI.Theme.TitleBarHeight, interactive = false})
    _mainWindow:addChild(titleBar)
    chromeRect(titleBar, 0, 0, winW, UI.Theme.TitleBarHeight, UI.Theme.Surface, 101)
    
    UI._titleText = chromeLabel(titleBar, "// " .. string.upper(Analyzer._name) .. " v" .. Analyzer._version, UI.Theme.Padding, 6, UI.Theme.Accent, UI.Theme.FontSize, 102)
    
    UI._statsText = chromeLabel(titleBar, "", winW - 200, 6, UI.Theme.TextDark, UI.Theme.SmallFontSize, 102)
    
    local titleAccent = chromeRect(titleBar, 0, UI.Theme.TitleBarHeight, winW, 1, UI.Theme.Accent, 101)
    UI._titlePulse = titleAccent._bg
    
    -- Title drag handle (invisible child; drag = root.setPosition, cascaded)
    local dragHandle = Rect.new({
        x = 0, y = 0, width = winW, height = UI.Theme.TitleBarHeight,
        fillColor = UI.Theme.Background, borderThickness = 0, transparency = 0,
        zIndex = 115, interactive = true,
    })
    titleBar:addChild(dragHandle)
    dragHandle._draggable = true
    dragHandle.onDrag = function(_, p)
        UI.moveWindowTo(math.floor(p.X), math.floor(p.Y))
    end
    Input.register(dragHandle)
    UI._dragHandle = dragHandle

    -- Section menu (node; tabs relative, one shared sliding magenta bar)
    local menuNode = Widget.new({x = 0, y = UI.Theme.TitleBarHeight + 1, width = winW, height = menuH, interactive = false})
    _mainWindow:addChild(menuNode)
    local sectionNames = {"Properties", "Scripts", "Remote Spy", "Export"}
    local tabW = math.floor(winW / #sectionNames)
    _sections = { _tabs = {}, _contentPanels = {}, _activeTab = nil }
    for i, sname in ipairs(sectionNames) do
        local tab = Tab.new({
            x = (i - 1) * tabW,
            y = 0,
            width = tabW,
            height = menuH,
            text = string.upper(sname),
            tabName = sname,
            noUnderline = true,
            zIndex = 110,
            onClick = function() _sections:switchTab(sname) end,
        })
        menuNode:addChild(tab)
        _sections._tabs[sname] = tab
    end
    chromeRect(menuNode, 0, menuH - 1, winW, 1, UI.Theme.Border, 109)
    UI._menuBar = chromeRect(menuNode, 0, menuH - 2, tabW, 2, UI.Theme.Magenta, 111)

    -- Panes (nodes; P2 parents module content here, modules read boxes not pixels)
    local treePane = Widget.new({x = 0, y = paneTop - winY, width = treeW, height = paneH, interactive = false})
    _mainWindow:addChild(treePane)
    _treePane = treePane
    local contentPane = Widget.new({x = treeW + 1, y = paneTop - winY, width = winW - treeW - 1, height = paneH, interactive = false})
    _mainWindow:addChild(contentPane)
    _contentPane = contentPane
    chromeRect(treePane, 0, 0, treeW, headH, UI.Theme.Surface, 105)
    chromeRect(treePane, 0, 0, 3, headH, UI.Theme.Accent, 106)
    chromeLabel(treePane, "// EXPLORER", 10, 4, UI.Theme.TextDim, UI.Theme.SmallFontSize, 106)
    chromeRect(_mainWindow, treeW, paneTop - winY, 1, paneH, UI.Theme.BorderLight, 105)
    chromeRect(contentPane, 0, 0, winW - treeW - 1, headH, UI.Theme.Surface, 105)
    chromeRect(contentPane, 0, 0, 3, headH, UI.Theme.Magenta, 106)
    UI._sectionLabel = chromeLabel(contentPane, "// PROPERTIES", 10, 4, UI.Theme.Magenta, UI.Theme.SmallFontSize, 106)

    -- Content-switch flash (tinted child; fades out, hides at rest)
    local flash = Rect.new({
        x = UI._contentArea.x - winX, y = UI._contentArea.y - winY,
        width = UI._contentArea.width, height = UI._contentArea.height,
        fillColor = UI.Theme.Magenta, borderThickness = 0, transparency = 0,
        zIndex = 130, interactive = false,
    })
    _mainWindow:addChild(flash)
    flash:setVisible(false)
    UI._flashBg = flash._bg

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
            local seq, bar, fromX, toX = UI._menuBarSeq, UI._menuBar, UI._menuBar._x, tab._x
            UI.tween(0.14, function(t)
                if seq ~= UI._menuBarSeq then return end
                bar._x = fromX + (toX - fromX) * t
                bar:_updateAbsolutePosition()
                bar:redraw()
            end)
        end
        if UI._sectionLabel then
            UI._sectionLabel:setText("// " .. string.upper(tabName))
        end
        if UI._flashBg and Analyzer._visible then
            UI._flashBg.Visible = true
            UI.tween(0.25, function(t)
                UI._flashBg.Transparency = 0.3 * (1 - t)
                if t >= 1 then UI._flashBg.Visible = false end
            end)
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
    local accentLine = UI._titlePulse
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
    -- ponytail: v2 — one cascade covers chrome, tabs, drag handle, P2 module tops
    if _mainWindow then
        _mainWindow:setVisible(visible)
    end
    if UI._statsText and visible then
        local stats = Pool.getStats()
        UI._statsText:setText(string.format("Drawing: %d active / %d pooled", stats.active, stats.pooled))
    end
    if _sections and _sections._activeTab then
        -- ponytail: re-fire so modules refresh their pooled rows on toggle
        pcall(function() Analyzer.Signals.TabChanged:Fire(_sections._activeTab, nil) end)
    end
end

-- ponytail: v2 drag = one root setPosition (cascade) + module row relayouts; no state loss
function UI.moveWindowTo(nx, ny)
    if not _mainWindow then return end
    local vw, vh = UI.getViewport()
    nx = math.max(-UI._windowW + 120, math.min(nx, vw - 120))
    ny = math.max(0, math.min(ny, vh - 40))
    local dx, dy = nx - UI._windowX, ny - UI._windowY
    if dx == 0 and dy == 0 then return end
    UI._windowX, UI._windowY = nx, ny
    MainWindow.layoutAreas()
    _mainWindow:setPosition(nx, ny)
    for _, m in ipairs({"Explorer", "Properties", "ScriptViewer", "RemoteSpy", "Export"}) do
        local mod = Analyzer[m]
        if mod and mod.move then pcall(mod.move, mod) end
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

-- ponytail: v2 P2 — modules parent content widgets here, position relative
function MainWindow.getTreePane()
    return _treePane
end

function MainWindow.getContentPane()
    return _contentPane
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
    _treePane, _contentPane = nil, nil
    UI._dragHandle = nil
end

return UI
