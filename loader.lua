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
local EMBEDDED = nil --[[BUNDLE_ANCHOR]]

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
