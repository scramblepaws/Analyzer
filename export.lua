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

return Export
