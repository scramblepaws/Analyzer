--[[ Analyzer — Script Viewer: decompile + inline highlight + virtual scroll ]]
local Analyzer = getgenv().Analyzer
if not Analyzer then error("[Analyzer] ScriptViewer loaded before loader.") return end
local UI = Analyzer.UI
if not UI then error("[Analyzer] ScriptViewer needs UI first.") return end

local SV = {}
Analyzer.ScriptViewer = SV

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
    table.insert(Analyzer._connections, Analyzer.Signals.ScriptRequested:Connect(function(inst)
        if inst and inst:IsA("LuaSourceContainer") then
            tabs:switchTab("Scripts")
            SV:view(inst)
        end
    end))
    table.insert(Analyzer._connections, Analyzer.Signals.TabChanged:Connect(function(name)
        local show = Analyzer._visible and name == "Scripts"
        SV._path:setVisible(show)
        SV._copy:setVisible(show)
        SV._block:setVisible(show)
    end))
    SV._block:setContent("-- click a Script in Explorer to decompile")
    print("[Analyzer] ScriptViewer initialized")
end

function SV.cleanup() end

return SV
