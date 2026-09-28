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

-- ponytail: executor workspace folder per game, e.g. Analyzer/My_Cool_Game
local function gameFolder()
    local name = "Place_" .. tostring(game.PlaceId)
    pcall(function()
        local info = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId)
        if info and info.Name and info.Name ~= "" then name = info.Name end
    end)
    name = name:gsub("[^%w%s%-%_]", ""):gsub("%s+", "_"):sub(1, 48)
    if name == "" then name = "Place_" .. tostring(game.PlaceId) end
    return "Analyzer/" .. name
end

local function ensureFolder(path)
    local mf, isf = getgenv().makefolder, getgenv().isfolder
    if type(mf) ~= "function" then return false end
    local cur = ""
    for part in (path .. "/"):gmatch("(.-)/") do
        cur = (cur == "") and part or (cur .. "/" .. part)
        local exists = false
        if type(isf) == "function" then exists = isf(cur) end
        if not exists then pcall(mf, cur) end
    end
    return true
end

-- ponytail: caps at 400 scripts + yields; full-game decompile of everything would hang
function Export.dumpGame()
    local wf = getgenv().writefile
    local dec = getgenv().decompile
    if type(wf) ~= "function" then status("writefile() missing", UI.Theme.Warning) return end
    if type(dec) ~= "function" then status("decompile() missing", UI.Theme.Warning) return end
    local folder = gameFolder()
    if not ensureFolder(folder .. "/scripts") then
        status("makefolder() missing", UI.Theme.Warning)
        return
    end
    status("Dumping to " .. folder .. "...", UI.Theme.Accent)
    task.spawn(function()
        local descs = {}
        pcall(function() descs = game:GetDescendants() end)
        local count, fail, capped = 0, 0, false
        for i, inst in ipairs(descs) do
            if inst:IsA("LuaSourceContainer") then
                if count >= 400 then capped = true break end
                local rel = inst:GetFullName():gsub("%.", "/"):gsub("[^%w%/_%-%(%)]", "_"):sub(1, 120)
                local dir = folder .. "/scripts/" .. (rel:match("(.+)/[^/]+$") or "")
                if dir ~= "" then ensureFolder(dir) end
                local ok, src = pcall(dec, inst)
                if ok and type(src) == "string" then
                    if pcall(wf, folder .. "/scripts/" .. rel .. ".lua",
                            "-- " .. inst:GetFullName() .. "\n" .. src) then
                        count = count + 1
                    else
                        fail = fail + 1
                    end
                else
                    fail = fail + 1
                end
            end
            if i % 200 == 0 then task.wait() end
        end
        -- manifests: tree + captured remotes
        local tree = {}
        for i, inst in ipairs(descs) do
            if i > 5000 then break end
            table.insert(tree, inst:GetFullName() .. " : " .. inst.ClassName)
        end
        pcall(wf, folder .. "/tree.txt", table.concat(tree, "\n"))
        if Analyzer.RemoteSpy and #Analyzer.RemoteSpy._log > 0 then
            local lines = {}
            for _, e in ipairs(Analyzer.RemoteSpy._log) do
                table.insert(lines, e.time .. " " .. e.path .. " " .. e.args)
            end
            pcall(wf, folder .. "/remotes.txt", table.concat(lines, "\n"))
        end
        local msg = string.format("Dumped %d scripts (%d failed)%s -> %s",
            count, fail, capped and " [capped]" or "", folder)
        status(msg, UI.Theme.Success)
        UI.Notification.show("Dumped " .. count .. " scripts", 2)
    end)
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
    btn("AUTO-DUMP game -> Analyzer/ folder", function()
        Export.dumpGame()
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

return Export
