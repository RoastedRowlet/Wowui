-- UI.lua


local api = WorldMarkerCyclerAPI
local targetApi = WorldMarkerCyclerTargetAPI
local mouseoverApi = WorldMarkerCyclerMouseoverAPI
local f -- forward declare frame

-- Locale table for UI strings
local L = setmetatable({}, { __index = function(t, k) return k end })
local locale = GetLocale()
if locale == "frFR" then
    L["World Marker Key Editor"] = "Editeur de raccourcis de marqueurs"
    L["ALL KEYBIND CAN BE SET IN THIS PAGE"] = "TOUS LES RACCOURCIS PEUVENT ETRE DEFINIS ICI"
    L["Use the input boxes below to set keybindings for world, target, and mouseover markers."] = "Utilisez les champs ci-dessous pour definir les raccourcis pour les marqueurs mondiaux, de cible et de survol."
    L["Marker Cycle Order (comma separated):\ne.g. 1SQUARE,2TRIANGLE,3DIAMOND,4CROSS,\n5STAR,6CIRCLE,7MOON,8SKULL"] = "Ordre de cycle des marqueurs (separe par des virgules):\nex. 1CARRE,2TRIANGLE,3DIAMANT,4CROIX,\n5ETOILE,6CERCLE,7LUNE,8CRANE"
    L["Note: Keybinds set here will override any keybinds set via slash commands or other UIs."] = "Remarque : Les raccourcis definis ici remplaceront ceux definis via les commandes ou autres interfaces."
    L["All Markers and Numbers above them represent the orderList that will be once you press the keybinds first time so when you clear all markers it will start from that first number you put into the input box for example if you put 8 it will mean skull marker will always show first and when you clear all markers skull will be placed first again this order is now shared by the ground, target and mouseover cyclers."] = "Tous les marqueurs et les numeros ci-dessus representent l'ordre qui sera utilise lorsque vous appuierez sur les raccourcis pour la premiere fois. Par exemple, si vous mettez 8, le marqueur crane sera toujours place en premier apres avoir tout efface. Cet ordre est desormais partage par les marqueurs au sol, de cible et de survol."
    L["World Cycle Key:"] = "Raccourci cycle mondial :"
    L["World Clear Key:"] = "Raccourci effacer mondial :"
    L["Target Cycle Key:"] = "Raccourci cycle cible :"
    L["Target Clear Key:"] = "Raccourci effacer cible :"
    L["Mouseover Cycle Key:"] = "Raccourci cycle survol :"
    L["Mouseover Clear Key:"] = "Raccourci effacer survol :"
    L["Raid Picker Open Key:"] = "Raccourci ouverture selecteur raid :"
end
local L = setmetatable({}, { __index = function(t, k) return k end })
local locale = GetLocale()

if locale == "frFR" then
    -- your existing French translations

elseif locale == "zhCN" then
    -- Simplified Chinese
    L["World Marker Key Editor"] = "世界标记按键编辑器"
    L["ALL KEYBIND CAN BE SET IN THIS PAGE"] = "所有快捷键都可以在此页面设置"
    L["Use the input boxes below to set keybindings for world, target, and mouseover markers."] = "使用下面的输入框设置世界标记、目标标记和鼠标悬停标记的快捷键。"
    L["Marker Cycle Order (comma separated):\ne.g. 1SQUARE,2TRIANGLE,3DIAMOND,4CROSS,\n5STAR,6CIRCLE,7MOON,8SKULL"] = "标记循环顺序（用逗号分隔）：\n例如：1方块,2三角,3菱形,4十字,\n5星星,6圆形,7月亮,8骷髅"
    L["Note: Keybinds set here will override any keybinds set via slash commands or other UIs."] = "注意：这里设置的快捷键将覆盖通过命令或其他界面设置的快捷键。"
    L["All Markers and Numbers above them represent the orderList that will be once you press the keybinds first time so when you clear all markers it will start from that first number you put into the input box for example if you put 8 it will mean skull marker will always show first and when you clear all markers skull will be placed first again this order is now shared by the ground, target and mouseover cyclers."] = "上方的所有标记及其数字表示第一次按下快捷键时的循环顺序。例如，如果你输入8，则骷髅标记会始终首先出现，并且在清除所有标记后也会再次优先放置。此顺序现在由地面、目标和鼠标悬停标记共用。"
    L["World Cycle Key:"] = "世界循环键："
    L["World Clear Key:"] = "清除世界标记键："
    L["Target Cycle Key:"] = "目标循环键："
    L["Target Clear Key:"] = "清除目标标记键："
    L["Mouseover Cycle Key:"] = "鼠标悬停循环键："
    L["Mouseover Clear Key:"] = "清除鼠标悬停标记键："
    L["Raid Picker Open Key:"] = "打开团队标记选择器键："

elseif locale == "zhTW" then
    -- Traditional Chinese
    L["World Marker Key Editor"] = "世界標記按鍵編輯器"
    L["ALL KEYBIND CAN BE SET IN THIS PAGE"] = "所有快捷鍵都可以在此頁面設定"
    L["Use the input boxes below to set keybindings for world, target, and mouseover markers."] = "使用下面的輸入框設定世界標記、目標標記與滑鼠懸停標記的快捷鍵。"
    L["Marker Cycle Order (comma separated):\ne.g. 1SQUARE,2TRIANGLE,3DIAMOND,4CROSS,\n5STAR,6CIRCLE,7MOON,8SKULL"] = "標記循環順序（以逗號分隔）：\n例如：1方塊,2三角,3菱形,4十字,\n5星星,6圓形,7月亮,8骷髏"
    L["Note: Keybinds set here will override any keybinds set via slash commands or other UIs."] = "注意：此處設定的快捷鍵將覆蓋透過指令或其他介面設定的快捷鍵。"
    L["All Markers and Numbers above them represent the orderList that will be once you press the keybinds first time so when you clear all markers it will start from that first number you put into the input box for example if you put 8 it will mean skull marker will always show first and when you clear all markers skull will be placed first again this order is now shared by the ground, target and mouseover cyclers."] = "上方的標記與數字表示第一次按下快捷鍵時的循環順序。例如輸入8，則骷髏標記會優先顯示，並在清除後再次優先放置。此順序現在由地面、目標和滑鼠懸停標記共用。"
    L["World Cycle Key:"] = "世界循環鍵："
    L["World Clear Key:"] = "清除世界標記鍵："
    L["Target Cycle Key:"] = "目標循環鍵："
    L["Target Clear Key:"] = "清除目標標記鍵："
    L["Mouseover Cycle Key:"] = "滑鼠懸停循環鍵："
    L["Mouseover Clear Key:"] = "清除滑鼠懸停標記鍵："
    L["Raid Picker Open Key:"] = "開啟團隊標記選擇器鍵："

elseif locale == "deDE" then
    -- German
    L["World Marker Key Editor"] = "Weltenmarkierungs-Tasteneditor"
    L["ALL KEYBIND CAN BE SET IN THIS PAGE"] = "ALLE TASTENBELEGUNGEN KÖNNEN AUF DIESER SEITE FESTGELEGT WERDEN"
    L["Use the input boxes below to set keybindings for world, target, and mouseover markers."] = "Verwenden Sie die untenstehenden Eingabefelder, um Tastenbelegungen für Welt-, Ziel- und Mouseover-Markierungen festzulegen."
    L["Marker Cycle Order (comma separated):\ne.g. 1SQUARE,2TRIANGLE,3DIAMOND,4CROSS,\n5STAR,6CIRCLE,7MOON,8SKULL"] = "Markierungsreihenfolge (durch Kommas getrennt):\nz. B. 1QUADRAT,2DREIECK,3RAUTE,4KREUZ,\n5STERN,6KREIS,7MOND,8SCHÄDEL"
    L["Note: Keybinds set here will override any keybinds set via slash commands or other UIs."] = "Hinweis: Hier gesetzte Tastenbelegungen überschreiben alle, die über Befehle oder andere Oberflächen gesetzt wurden."
    L["All Markers and Numbers above them represent the orderList that will be once you press the keybinds first time so when you clear all markers it will start from that first number you put into the input box for example if you put 8 it will mean skull marker will always show first and when you clear all markers skull will be placed first again this order is now shared by the ground, target and mouseover cyclers."] = "Alle Markierungen und Zahlen darüber stellen die Reihenfolge dar, die beim ersten Drücken der Taste verwendet wird. Wenn Sie z. B. 8 eingeben, wird der Schädel immer zuerst angezeigt und nach dem Löschen aller Markierungen erneut zuerst gesetzt. Diese Reihenfolge gilt jetzt für Boden-, Ziel- und Mouseover-Markierungen."
    L["World Cycle Key:"] = "Welt-Zyklus-Taste:"
    L["World Clear Key:"] = "Welt-Markierungen löschen:"
    L["Target Cycle Key:"] = "Ziel-Zyklus-Taste:"
    L["Target Clear Key:"] = "Ziel-Markierungen löschen:"
    L["Mouseover Cycle Key:"] = "Mouseover-Zyklus-Taste:"
    L["Mouseover Clear Key:"] = "Mouseover-Markierungen löschen:"
    L["Raid Picker Open Key:"] = "Raid-Markierungsmenü öffnen:"

elseif locale == "esES" or locale == "esMX" then
    -- Spanish (Spain + Latin America)
    L["World Marker Key Editor"] = "Editor de teclas de marcadores del mundo"
    L["ALL KEYBIND CAN BE SET IN THIS PAGE"] = "TODAS LAS TECLAS SE PUEDEN CONFIGURAR EN ESTA PÁGINA"
    L["Use the input boxes below to set keybindings for world, target, and mouseover markers."] = "Usa los campos de abajo para configurar teclas para marcadores de mundo, objetivo y mouseover."
    L["Marker Cycle Order (comma separated):\ne.g. 1SQUARE,2TRIANGLE,3DIAMOND,4CROSS,\n5STAR,6CIRCLE,7MOON,8SKULL"] = "Orden del ciclo de marcadores (separado por comas):\nej. 1CUADRADO,2TRIÁNGULO,3ROMBO,4CRUZ,\n5ESTRELLA,6CÍRCULO,7LUNA,8CALAVERA"
    L["Note: Keybinds set here will override any keybinds set via slash commands or other UIs."] = "Nota: Las teclas configuradas aquí sobrescribirán las establecidas mediante comandos u otras interfaces."
    L["All Markers and Numbers above them represent the orderList that will be once you press the keybinds first time so when you clear all markers it will start from that first number you put into the input box for example if you put 8 it will mean skull marker will always show first and when you clear all markers skull will be placed first again this order is now shared by the ground, target and mouseover cyclers."] = "Todos los marcadores y números representan el orden que se usará al presionar la tecla por primera vez. Por ejemplo, si pones 8, la calavera aparecerá primero y seguirá siendo la primera al limpiar todos los marcadores. Este orden ahora se comparte entre los marcadores de suelo, objetivo y mouseover."
    L["World Cycle Key:"] = "Tecla ciclo mundo:"
    L["World Clear Key:"] = "Tecla limpiar mundo:"
    L["Target Cycle Key:"] = "Tecla ciclo objetivo:"
    L["Target Clear Key:"] = "Tecla limpiar objetivo:"
    L["Mouseover Cycle Key:"] = "Tecla ciclo mouseover:"
    L["Mouseover Clear Key:"] = "Tecla limpiar mouseover:"
    L["Raid Picker Open Key:"] = "Tecla abrir selector de banda:"

elseif locale == "itIT" then
    -- Italian
    L["World Marker Key Editor"] = "Editor tasti marcatori del mondo"
    L["ALL KEYBIND CAN BE SET IN THIS PAGE"] = "TUTTI I TASTI POSSONO ESSERE IMPOSTATI IN QUESTA PAGINA"
    L["Use the input boxes below to set keybindings for world, target, and mouseover markers."] = "Usa i campi qui sotto per impostare i tasti per marcatori del mondo, bersaglio e mouseover."
    L["Marker Cycle Order (comma separated):\ne.g. 1SQUARE,2TRIANGLE,3DIAMOND,4CROSS,\n5STAR,6CIRCLE,7MOON,8SKULL"] = "Ordine ciclo marcatori (separato da virgole):\nes. 1QUADRATO,2TRIANGOLO,3ROMBO,4CROCE,\n5STELLA,6CERCHIO,7LUNA,8TESCHIO"
    L["Note: Keybinds set here will override any keybinds set via slash commands or other UIs."] = "Nota: I tasti impostati qui sovrascriveranno quelli impostati tramite comandi o altre interfacce."
    L["All Markers and Numbers above them represent the orderList that will be once you press the keybinds first time so when you clear all markers it will start from that first number you put into the input box for example if you put 8 it will mean skull marker will always show first and when you clear all markers skull will be placed first again this order is now shared by the ground, target and mouseover cyclers."] = "Tutti i marcatori e i numeri rappresentano l'ordine usato alla prima pressione. Se inserisci 8, il teschio sarà sempre il primo anche dopo aver pulito tutto. Questo ordine e ora condiviso da marcatori a terra, bersaglio e mouseover."
    L["World Cycle Key:"] = "Tasto ciclo mondo:"
    L["World Clear Key:"] = "Tasto pulizia mondo:"
    L["Target Cycle Key:"] = "Tasto ciclo bersaglio:"
    L["Target Clear Key:"] = "Tasto pulizia bersaglio:"
    L["Mouseover Cycle Key:"] = "Tasto ciclo mouseover:"
    L["Mouseover Clear Key:"] = "Tasto pulizia mouseover:"
    L["Raid Picker Open Key:"] = "Tasto apertura selettore raid:"

elseif locale == "ptBR" then
    -- Portuguese (Brazil)
    L["World Marker Key Editor"] = "Editor de teclas de marcadores do mundo"
    L["ALL KEYBIND CAN BE SET IN THIS PAGE"] = "TODAS AS TECLAS PODEM SER CONFIGURADAS NESTA PÁGINA"
    L["Use the input boxes below to set keybindings for world, target, and mouseover markers."] = "Use os campos abaixo para configurar teclas para marcadores de mundo, alvo e mouseover."
    L["Marker Cycle Order (comma separated):\ne.g. 1SQUARE,2TRIANGLE,3DIAMOND,4CROSS,\n5STAR,6CIRCLE,7MOON,8SKULL"] = "Ordem do ciclo de marcadores (separado por vírgulas):\nex. 1QUADRADO,2TRIÂNGULO,3LOSANGO,4CRUZ,\n5ESTRELA,6CÍRCULO,7LUA,8CAVEIRA"
    L["Note: Keybinds set here will override any keybinds set via slash commands or other UIs."] = "Nota: As teclas configuradas aqui substituirão quaisquer outras definidas por comandos ou outras interfaces."
    L["All Markers and Numbers above them represent the orderList that will be once you press the keybinds first time so when you clear all markers it will start from that first number you put into the input box for example if you put 8 it will mean skull marker will always show first and when you clear all markers skull will be placed first again this order is now shared by the ground, target and mouseover cyclers."] = "Todos os marcadores e números representam a ordem usada ao pressionar a tecla pela primeira vez. Se colocar 8, a caveira aparecerá primeiro e continuará sendo a primeira após limpar tudo. Esta ordem agora e compartilhada pelos marcadores no chão, de alvo e de mouseover."
    L["World Cycle Key:"] = "Tecla ciclo mundo:"
    L["World Clear Key:"] = "Tecla limpar mundo:"
    L["Target Cycle Key:"] = "Tecla ciclo alvo:"
    L["Target Clear Key:"] = "Tecla limpar alvo:"
    L["Mouseover Cycle Key:"] = "Tecla ciclo mouseover:"
    L["Mouseover Clear Key:"] = "Tecla limpar mouseover:"
    L["Raid Picker Open Key:"] = "Tecla abrir seletor de raide:"

elseif locale == "ruRU" then
    -- Russian
    L["World Marker Key Editor"] = "Редактор клавиш меток мира"
    L["ALL KEYBIND CAN BE SET IN THIS PAGE"] = "ВСЕ КЛАВИШИ МОЖНО НАСТРОИТЬ НА ЭТОЙ СТРАНИЦЕ"
    L["Use the input boxes below to set keybindings for world, target, and mouseover markers."] = "Используйте поля ниже, чтобы назначить клавиши для мировых, целевых и mouseover-меток."
    L["Marker Cycle Order (comma separated):\ne.g. 1SQUARE,2TRIANGLE,3DIAMOND,4CROSS,\n5STAR,6CIRCLE,7MOON,8SKULL"] = "Порядок цикла меток (через запятую):\nнапр. 1КВАДРАТ,2ТРЕУГОЛЬНИК,3РОМБ,4КРЕСТ,\n5ЗВЕЗДА,6КРУГ,7ЛУНА,8ЧЕРЕП"
    L["Note: Keybinds set here will override any keybinds set via slash commands or other UIs."] = "Примечание: назначенные здесь клавиши заменят те, что заданы через команды или другие интерфейсы."
    L["All Markers and Numbers above them represent the orderList that will be once you press the keybinds first time so when you clear all markers it will start from that first number you put into the input box for example if you put 8 it will mean skull marker will always show first and when you clear all markers skull will be placed first again this order is now shared by the ground, target and mouseover cyclers."] = "Все метки и числа обозначают порядок при первом нажатии. Если указать 8, череп всегда будет первым и после очистки снова станет первым. Этот порядок теперь общий для наземных меток, цели и наведения мыши."
    L["World Cycle Key:"] = "Клавиша цикла мира:"
    L["World Clear Key:"] = "Клавиша очистки мира:"
    L["Target Cycle Key:"] = "Клавиша цикла цели:"
    L["Target Clear Key:"] = "Клавиша очистки цели:"
    L["Mouseover Cycle Key:"] = "Клавиша цикла mouseover:"
    L["Mouseover Clear Key:"] = "Клавиша очистки mouseover:"
    L["Raid Picker Open Key:"] = "Клавиша открытия выбора рейда:"
end
-- Marker icon textures for 1-8
local markerIcons = {
    [1] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6", -- Square
    [2] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_4", -- Triangle (green)
    [3] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3", -- Diamond (purple)
    [4] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7", -- Cross (red X)
    [5] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1", -- Star (yellow)
    [6] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_2", -- Circle (orange)
    [7] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_5", -- Moon (blue)
    [8] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8", -- Skull
}

local markerNames = {
    [1] = "SQUARE",  [2] = "TRIANGLE", [3] = "DIAMOND", [4] = "CROSS",
    [5] = "STAR",    [6] = "CIRCLE",   [7] = "MOON",    [8] = "SKULL",
}

local markerColors = {
    [1] = {1, 1, 0},
    [2] = {0, 1, 0},
    [3] = {0.8, 0, 1},
    [4] = {1, 0, 0},
    [5] = {1, 0.8, 0},
    [6] = {1, 0.5, 0},
    [7] = {0.4, 0.6, 1},
    [8] = {0.9, 0.9, 0.9},
}

local editBoxes = {}
local scrollChild

-- =========================
-- Key Capture Overlay (IME-proof, press-to-bind)
-- =========================
local keyCaptureFrame = CreateFrame("Button", "WMC_KeyCaptureOverlay", UIParent)
keyCaptureFrame:SetAllPoints(UIParent)
keyCaptureFrame:SetFrameStrata("FULLSCREEN_DIALOG")
keyCaptureFrame:EnableKeyboard(true)
keyCaptureFrame:EnableMouseWheel(true)
keyCaptureFrame:RegisterForClicks("AnyDown")
keyCaptureFrame:SetPropagateKeyboardInput(false)
keyCaptureFrame:Hide()
keyCaptureFrame._activeBox = nil
keyCaptureFrame._activeHandler = nil
keyCaptureFrame._activeGetBind = nil

local function GetModifierString()
    local mod = ""
    if IsControlKeyDown() then mod = mod .. "CTRL-" end
    if IsAltKeyDown()     then mod = mod .. "ALT-" end
    if IsShiftKeyDown()   then mod = mod .. "SHIFT-" end
    return mod
end

local function FinishKeyCapture(mod, key)
    local box     = keyCaptureFrame._activeBox
    local handler = keyCaptureFrame._activeHandler
    if not box then keyCaptureFrame:Hide(); return end

    local fullBind = mod .. key
    box:SetText(fullBind)
    keyCaptureFrame:Hide()

    if handler then handler(mod, key, fullBind) end
    local tApi = WorldMarkerCyclerTargetAPI
    local mApi = WorldMarkerCyclerMouseoverAPI
    if tApi and tApi.UpdateBindings then tApi.UpdateBindings() end
    if api  and api.UpdateBindings  then api.UpdateBindings()  end
    if mApi and mApi.UpdateBindings then mApi.UpdateBindings() end
end

local function CancelKeyCapture()
    local box = keyCaptureFrame._activeBox
    local get = keyCaptureFrame._activeGetBind
    if box and get then
        box:SetText(get())
    end
    keyCaptureFrame:Hide()
end

keyCaptureFrame:SetScript("OnKeyDown", function(_, key)
    if key == "ESCAPE" then CancelKeyCapture(); return end
    if key == "LSHIFT" or key == "RSHIFT"
    or key == "LCTRL"  or key == "RCTRL"
    or key == "LALT"   or key == "RALT" then
        return
    end
    FinishKeyCapture(GetModifierString(), key)
end)

keyCaptureFrame:SetScript("OnMouseWheel", function(_, delta)
    local key = delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"
    FinishKeyCapture(GetModifierString(), key)
end)

keyCaptureFrame:SetScript("OnClick", function(_, button)
    if button == "LeftButton" then CancelKeyCapture(); return end
    local map = { RightButton="BUTTON2", MiddleButton="BUTTON3",
                  Button4="BUTTON4", Button5="BUTTON5",
                  Button6="BUTTON6", Button7="BUTTON7" }
    FinishKeyCapture(GetModifierString(), map[button] or button:upper())
end)

keyCaptureFrame:SetScript("OnHide", function()
    keyCaptureFrame._activeBox = nil
    keyCaptureFrame._activeHandler = nil
    keyCaptureFrame._activeGetBind = nil
end)

local function CreateKeyEditBoxes(label, x, y, getBind, handler)
    local lbl = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", x, y)
    lbl:SetText(label)

    local bindBox = CreateFrame("EditBox", nil, scrollChild, "InputBoxTemplate")
    bindBox:SetSize(160, 22)
    bindBox:SetPoint("LEFT", lbl, "RIGHT", 10, 0)
    bindBox:SetAutoFocus(false)
    bindBox:SetText(getBind())

    local function apply()
        local bind = bindBox:GetText():upper()
        local mod, key = "", bind
        if bind:find("CTRL%-") then mod = mod .. "CTRL-"; key = key:gsub("CTRL%-", "") end
        if bind:find("ALT%-") then mod = mod .. "ALT-"; key = key:gsub("ALT%-", "") end
        if bind:find("SHIFT%-") then mod = mod .. "SHIFT-"; key = key:gsub("SHIFT%-", "") end
        key = key:gsub("^%s+", "")
        local fullBind = mod .. key
        if handler then handler(mod, key, fullBind) end
        bindBox:SetText(fullBind)
        if targetApi and targetApi.UpdateBindings then targetApi.UpdateBindings() end
        if api and api.UpdateBindings then api.UpdateBindings() end
        if mouseoverApi and mouseoverApi.UpdateBindings then mouseoverApi.UpdateBindings() end
    end

    bindBox:SetScript("OnEnterPressed", apply)
    bindBox:SetScript("OnEditFocusLost", apply)

    -- "Bind" button: click it, then press a key combo to capture
    local bindBtn = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
    bindBtn:SetSize(50, 22)
    bindBtn:SetPoint("LEFT", bindBox, "RIGHT", 4, 0)
    bindBtn:SetText("Bind")
    bindBtn:SetScript("OnClick", function()
        bindBox:ClearFocus()
        keyCaptureFrame._activeBox = bindBox
        keyCaptureFrame._activeHandler = handler
        keyCaptureFrame._activeGetBind = getBind
        bindBox:SetText("Press a key...")
        keyCaptureFrame:Show()
    end)

    table.insert(editBoxes, {bindBox = bindBox, getBind = getBind})
end

-- Sample Keybind popup (independent of scroll)
local samplePage
local function ShowSampleKeybindPage()
    if not samplePage then
        samplePage = CreateFrame("Frame", "WorldMarkerCyclerSampleKeybindPage", UIParent, "BackdropTemplate")
        samplePage:SetSize(420, 340)
        samplePage:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        samplePage:SetBackdrop({bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 }})
        samplePage:SetBackdropColor(0, 0, 0, 0.92)
        samplePage:SetFrameStrata("DIALOG")
        samplePage:Hide()
        samplePage:SetMovable(true)
        samplePage:EnableMouse(true)
        samplePage:RegisterForDrag("LeftButton")
        samplePage:SetScript("OnDragStart", function(self) self:StartMoving() end)
        samplePage:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

        local stitle = samplePage:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        stitle:SetPoint("TOP", 0, -16)
        stitle:SetText("Sample Mouse Keybinds")

        local sScrollFrame = CreateFrame("ScrollFrame", nil, samplePage, "UIPanelScrollFrameTemplate")
        sScrollFrame:SetPoint("TOPLEFT", 16, -48)
        sScrollFrame:SetPoint("BOTTOMRIGHT", -16, 48)
        local content = CreateFrame("Frame", nil, sScrollFrame)
        content:SetSize(380, 260)
        sScrollFrame:SetScrollChild(content)

        local mouseKeys = {
            { key = "MOUSEWHEELUP", desc = "Mouse Wheel Up" },
            { key = "MOUSEWHEELDOWN", desc = "Mouse Wheel Down" },
            { key = "BUTTON1", desc = "Left Click" },
            { key = "BUTTON2", desc = "Right Click" },
            { key = "BUTTON3", desc = "Middle Button" },
            { key = "BUTTON4", desc = "Extra Mouse Button 4" },
            { key = "BUTTON5", desc = "Extra Mouse Button 5" },
            { key = "BUTTON6", desc = "Extra Mouse Button 6 (if available)" },
            { key = "BUTTON7", desc = "Extra Mouse Button 7 (if available)" },
        }
        local sy = -8
        for i, info in ipairs(mouseKeys) do
            local line = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            line:SetPoint("TOPLEFT", 0, sy)
            line:SetWidth(360)
            line:SetText("|cffffff00"..info.key.."|r - "..info.desc)
            sy = sy - 22
        end
        local modLine = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        modLine:SetPoint("TOPLEFT", 0, sy)
        modLine:SetWidth(360)
        modLine:SetText("\nYou can combine with modifiers: |cffffff00CTRL-|r, |cffffff00ALT-|r, |cffffff00SHIFT-|r")
        sy = sy - 32
        local exampleLine = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        exampleLine:SetPoint("TOPLEFT", 0, sy)
        exampleLine:SetWidth(360)
        exampleLine:SetText("Example: |cffffff00CTRL-MOUSEWHEELDOWN|r")
        sy = sy - 22
        local noteLine = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        noteLine:SetPoint("TOPLEFT", 0, sy)
        noteLine:SetWidth(360)
        noteLine:SetText("\nNote: Key names must be uppercase and match WoW's internal names.")
        local closeBtn = CreateFrame("Button", nil, samplePage, "UIPanelButtonTemplate")
        closeBtn:SetSize(80, 24)
        closeBtn:SetPoint("BOTTOM", 0, 16)
        closeBtn:SetText("Close")
        closeBtn:SetScript("OnClick", function() samplePage:Hide() end)
    end
    samplePage:Show()
end

local function BuildUI()
    f = CreateFrame("Frame", "WorldMarkerCyclerUI", InterfaceOptionsFramePanelContainer)
    f.name = "World Marker Cycler"
    if SettingsPanel and SettingsPanel.AddCategory then
        SettingsPanel.AddCategory(f)
    elseif Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category, layout = Settings.RegisterCanvasLayoutCategory(f, f.name)
        Settings.RegisterAddOnCategory(category)
    else
        InterfaceOptions_AddCategory(f)
    end

    -- Scroll frame wrapping all content
    local scrollFrame = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -26, 0)

    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(scrollFrame:GetWidth() or 580)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)
    scrollFrame:SetScript("OnSizeChanged", function(self, w, h)
        scrollChild:SetWidth(w)
    end)

    local curY = -12

    -- Title
    local title = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", scrollChild, "TOP", 0, curY)
    title:SetText(L["World Marker Key Editor"])
    curY = curY - 20

    local title2 = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title2:SetPoint("TOP", scrollChild, "TOP", 0, curY)
    title2:SetText(L["ALL KEYBIND CAN BE SET IN THIS PAGE"])
    title2:SetTextColor(0, 1, 0)
    curY = curY - 16

    local subtitle = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetTextColor(1, 1, 1, 0.8)
    subtitle:SetPoint("TOP", scrollChild, "TOP", 0, curY)
    subtitle:SetText(L["Use the input boxes below to set keybindings for world, target, and mouseover markers."])
    curY = curY - 24

    -- Keybind rows
    CreateKeyEditBoxes(L["World Cycle Key:"], 16, curY,
        function() return ((WMC_Saved and WMC_Saved.placeModifier) or "") .. ((WMC_Saved and WMC_Saved.placeKey) or "") end,
        function(mod, key)
            if api and api.SetPlaceKey then api.SetPlaceKey(mod, key) end
            if api and api.UpdateBindings then api.UpdateBindings() end
        end
    )
    curY = curY - 26

    -- Click edge selector row
    local clickEdgeLbl = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    clickEdgeLbl:SetPoint("TOPLEFT", 16, curY)
    clickEdgeLbl:SetText("|cffffff00Click edge:|r")

    local function makeEdgeBtn(label, xOff, clickFn)
        local btn = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
        btn:SetSize(64, 22)
        btn:SetPoint("TOPLEFT", clickEdgeLbl, "TOPRIGHT", xOff, 2)
        btn:SetText(label)
        btn:SetScript("OnClick", clickFn)
        return btn
    end

    local edgeBtnAuto = makeEdgeBtn("Auto",  8,  function()
        if SlashCmdList and SlashCmdList["WMCCLICKEDGE"] then
            SlashCmdList["WMCCLICKEDGE"]("auto")
        end
    end)
    local edgeBtnUp   = makeEdgeBtn("Up",    76, function()
        if WorldMarkerCyclerAPI and WorldMarkerCyclerAPI.SetUseClickDown then
            WorldMarkerCyclerAPI.SetUseClickDown(false)
            print("WorldMarkerCycler: click edge set to UP (keyboard).")
        end
    end)
    local edgeBtnDown = makeEdgeBtn("Down",  144, function()
        if WorldMarkerCyclerAPI and WorldMarkerCyclerAPI.SetUseClickDown then
            WorldMarkerCyclerAPI.SetUseClickDown(true)
            print("WorldMarkerCycler: click edge set to DOWN (mouse button).")
        end
    end)

    -- Description sits below the button row
    local clickEdgeDesc = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    clickEdgeDesc:SetPoint("TOPLEFT", 16, curY - 28)
    clickEdgeDesc:SetWidth(520)
    clickEdgeDesc:SetText("|cffaaaaaa Auto = detects keyboard vs mouse button.  Up = keyboard.  Down = MMO mouse / extra buttons.|r")

    curY = curY - 52

    CreateKeyEditBoxes(L["World Clear Key:"], 16, curY,
        function() return ((WMC_Saved and WMC_Saved.clearModifier) or "") .. ((WMC_Saved and WMC_Saved.clearKey) or "") end,
        function(mod, key)
            if api and api.SetClearKey then api.SetClearKey(mod, key) end
            if api and api.UpdateBindings then api.UpdateBindings() end
        end
    )
    curY = curY - 30

    CreateKeyEditBoxes(L["Target Cycle Key:"], 16, curY,
        function() return ((WMC_TargetSaved and WMC_TargetSaved.placeModifier) or "") .. ((WMC_TargetSaved and WMC_TargetSaved.placeKey) or "") end,
        function(mod, key, fullBind)
            if SlashCmdList and SlashCmdList["WMCTARGETADD"] then
                SlashCmdList["WMCTARGETADD"]("cycle " .. (mod or "") .. (mod ~= "" and " " or "") .. (key or ""))
            end
            if targetApi and targetApi.UpdateBindings then targetApi.UpdateBindings() end
        end
    )
    curY = curY - 30

    CreateKeyEditBoxes(L["Target Clear Key:"], 16, curY,
        function() return ((WMC_TargetSaved and WMC_TargetSaved.clearModifier) or "") .. ((WMC_TargetSaved and WMC_TargetSaved.clearKey) or "") end,
        function(mod, key, fullBind)
            if SlashCmdList and SlashCmdList["WMCTARGETADD"] then
                SlashCmdList["WMCTARGETADD"]("clear " .. (mod or "") .. (mod ~= "" and " " or "") .. (key or ""))
            end
            if targetApi and targetApi.UpdateBindings then targetApi.UpdateBindings() end
        end
    )
    curY = curY - 30

    CreateKeyEditBoxes(L["Mouseover Cycle Key:"], 16, curY,
        function() return ((WMC_MouseoverSaved and WMC_MouseoverSaved.placeModifier) or "") .. ((WMC_MouseoverSaved and WMC_MouseoverSaved.placeKey) or "") end,
        function(mod, key)
            local mApi = WorldMarkerCyclerMouseoverAPI
            if mApi and mApi.SetPlaceKey then
                mApi.SetPlaceKey(mod, key)
            end
            if mApi and mApi.UpdateBindings then mApi.UpdateBindings() end
        end
    )
    curY = curY - 30

    CreateKeyEditBoxes(L["Mouseover Clear Key:"], 16, curY,
        function() return ((WMC_MouseoverSaved and WMC_MouseoverSaved.clearModifier) or "") .. ((WMC_MouseoverSaved and WMC_MouseoverSaved.clearKey) or "") end,
        function(mod, key)
            local mApi = WorldMarkerCyclerMouseoverAPI
            if mApi and mApi.SetClearKey then
                mApi.SetClearKey(mod, key)
            end
            if mApi and mApi.UpdateBindings then mApi.UpdateBindings() end
        end
    )
    curY = curY - 30

    CreateKeyEditBoxes(L["Raid Picker Open Key:"], 16, curY,
        function() return ((WMC_RaidPickerSaved and WMC_RaidPickerSaved.openModifier) or "") .. ((WMC_RaidPickerSaved and WMC_RaidPickerSaved.openKey) or "") end,
        function(mod, key)
            local raidPickerApi = WorldMarkerCyclerRaidPickerAPI
            if raidPickerApi and raidPickerApi.SetOpenKey then
                raidPickerApi.SetOpenKey(mod, key)
            else
                if not WMC_RaidPickerSaved then WMC_RaidPickerSaved = {} end
                WMC_RaidPickerSaved.openModifier = mod or ""
                WMC_RaidPickerSaved.openKey = key or ""
            end
            if raidPickerApi and raidPickerApi.UpdateBindings then raidPickerApi.UpdateBindings() end
        end
    )
    curY = curY - 30

    -- Marker bar layout: one row, or markers stacked above the buttons
    local rowsCheck = CreateFrame("CheckButton", nil, scrollChild, "UICheckButtonTemplate")
    rowsCheck:SetSize(24, 24)
    rowsCheck:SetPoint("TOPLEFT", 16, curY)
    local rowsLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    rowsLabel:SetPoint("LEFT", rowsCheck, "RIGHT", 2, 0)
    rowsLabel:SetText(L["Marker bar: two rows"])

    local function RefreshRowsCheck()
        local api = WorldMarkerCyclerRaidPickerAPI
        local rows = (api and api.GetRows and api.GetRows())
            or (WMC_RaidPickerSaved and WMC_RaidPickerSaved.rows) or 1
        rowsCheck:SetChecked(rows == 2)
    end
    RefreshRowsCheck()
    -- keep it honest if the layout was changed with /wmcrrows
    rowsCheck:SetScript("OnShow", RefreshRowsCheck)

    rowsCheck:SetScript("OnClick", function(self)
        local want = self:GetChecked() and 2 or 1
        local api = WorldMarkerCyclerRaidPickerAPI
        if api and api.SetRows then
            -- SetRows returns false when it had to defer past combat lockdown
            if not api.SetRows(want) then
                print(L["Marker bar layout will change when you leave combat."])
            end
        else
            if not WMC_RaidPickerSaved then WMC_RaidPickerSaved = {} end
            WMC_RaidPickerSaved.rows = want
        end
    end)

    local rowsDesc = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rowsDesc:SetPoint("TOPLEFT", rowsCheck, "BOTTOMLEFT", 2, 2)
    rowsDesc:SetWidth(420)
    rowsDesc:SetJustifyH("LEFT")
    rowsDesc:SetText(L["Splits the bar so the markers sit above the action buttons."])
    rowsDesc:SetTextColor(0.7, 0.7, 0.7)
    curY = curY - 46

    -- Note
    local noteLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    noteLabel:SetPoint("TOPLEFT", 16, curY)
    noteLabel:SetText(L["Note: Keybinds set here will override any keybinds set via slash commands or other UIs."])
    noteLabel:SetWidth(400)
    noteLabel:SetWordWrap(true)
    noteLabel:SetTextColor(1, 1, 1, 1)
    noteLabel:SetFontObject("SystemFont_Outline")
    curY = curY - 30

    -- Sample keybinds button
    local sampleBtn = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
    sampleBtn:SetSize(200, 28)
    sampleBtn:SetPoint("TOPLEFT", 16, curY)
    sampleBtn:SetText("Show Sample Mouse Keybinds")
    sampleBtn:SetScript("OnClick", function() ShowSampleKeybindPage() end)
    curY = curY - 40

    -- Blizzard API warning box
    local warnBox = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
    warnBox:SetSize(540, 72)
    warnBox:SetPoint("TOPLEFT", 16, curY)
    warnBox:SetBackdrop({bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 }})
    warnBox:SetBackdropColor(0.1, 0.05, 0.05, 0.95)
    warnBox:SetBackdropBorderColor(1, 0.2, 0.2, 1)
    local warn = warnBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    warn:SetPoint("TOPLEFT", warnBox, "TOPLEFT", 10, -8)
    warn:SetPoint("BOTTOMRIGHT", warnBox, "BOTTOMRIGHT", -10, 8)
    warn:SetTextColor(1, 0.3, 0.3, 1)
    warn:SetJustifyH("LEFT")
    warn:SetJustifyV("TOP")
    warn:SetWordWrap(true)
    warn:SetMaxLines(5)
    warn:SetText("|cffff4444Blizzard limits world marker placement/clearing to 3 per second. Excess commands will be ignored or delayed. This addon throttles to avoid hitting this limit.|r")
    curY = curY - 82

    -- Marker Cycle Order section
    local orderLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    orderLabel:SetPoint("TOPLEFT", 16, curY)
    orderLabel:SetWidth(380)
    orderLabel:SetWordWrap(true)
    orderLabel:SetText(L["Marker Cycle Order (comma separated):\ne.g. 1SQUARE,2TRIANGLE,3DIAMOND,4CROSS,\n5STAR,6CIRCLE,7MOON,8SKULL"])
    orderLabel:SetTextColor(1, 1, 1, 1)
    orderLabel:SetFontObject("SystemFont_Outline")

    local orderBox = CreateFrame("EditBox", nil, scrollChild, "InputBoxTemplate")
    orderBox:SetSize(140, 22)
    orderBox:SetPoint("LEFT", orderLabel, "RIGHT", 10, 0)
    orderBox:SetAutoFocus(false)
    orderBox:SetText(table.concat((WMC_Saved and WMC_Saved.orderList) or {1,2,3,4,5,6,7,8}, ","))
    curY = curY - 54

    -- Number labels 1-8
    local numberLabels = {}
    for i = 1, 8 do
        local lbl = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalOutline")
        lbl:SetFontObject("GameFontNormalOutline")
        lbl:SetFont(lbl:GetFont(), 18, "OUTLINE")
        lbl:SetPoint("TOPLEFT", 16 + (i-1)*28 + 6, curY)
        lbl:SetText(tostring(i))
        numberLabels[i] = lbl
    end
    curY = curY - 22

    -- Marker icon row
    local function ShowOrderIcons()
        if f._orderIcons then
            for _, t in ipairs(f._orderIcons) do t:Hide() end
        end
        f._orderIcons = f._orderIcons or {}
        local order = (WMC_Saved and WMC_Saved.orderList) or {1,2,3,4,5,6,7,8}
        for i = 1, 8 do
            local marker = order[i]
            local icon = f._orderIcons[i]
            if not icon then
                icon = scrollChild:CreateTexture(nil, "ARTWORK")
                f._orderIcons[i] = icon
            end
            icon:SetTexture(markerIcons[marker] or markerIcons[1])
            icon:SetSize(24, 24)
            icon:SetPoint("TOPLEFT", numberLabels[i], "BOTTOMLEFT", -4, -2)
            icon:Show()
        end
    end
    ShowOrderIcons()
    curY = curY - 32

    local function applyOrder()
        local text = orderBox:GetText()
        local t = {}
        for num in string.gmatch(text, "%d") do
            table.insert(t, tonumber(num))
        end
        if #t == 8 then
            WMC_Saved.orderList = t
            if api and api.SetOrder then api.SetOrder(t) end
            -- Push the same order to the target and mouseover cyclers.
            -- They used to keep their own hardcoded order, which is why
            -- editing this box only ever affected the ground markers.
            -- Looked up at call time: those files load after UI.lua.
            local tApi = _G.WorldMarkerCyclerTargetAPI
            if tApi and tApi.SyncOrderFromWorld then tApi.SyncOrderFromWorld()
            elseif tApi and tApi.SetOrder then tApi.SetOrder(t) end
            local mApi = _G.WorldMarkerCyclerMouseoverAPI
            if mApi and mApi.SyncOrderFromWorld then mApi.SyncOrderFromWorld()
            elseif mApi and mApi.SetOrder then mApi.SetOrder(t) end
        end
        orderBox:SetText(table.concat(WMC_Saved.orderList, ","))
        ShowOrderIcons()
    end
    orderBox:SetScript("OnEnterPressed", applyOrder)
    orderBox:SetScript("OnEditFocusLost", applyOrder)

    -- Explanation text
    local label2 = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label2:SetPoint("TOPLEFT", 16, curY)
    label2:SetText(L["All Markers and Numbers above them represent the orderList that will be once you press the keybinds first time so when you clear all markers it will start from that first number you put into the input box for example if you put 8 it will mean skull marker will always show first and when you clear all markers skull will be placed first again this order is now shared by the ground, target and mouseover cyclers."])
    label2:SetWidth(540)
    label2:SetWordWrap(true)
    label2:SetTextColor(1, 1, 1, 1)
    label2:SetFontObject("SystemFont_Outline")
    curY = curY - 80

    -- =========================
    -- Custom Cycle Mode Section
    -- =========================
    local ccBox = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
    ccBox:SetSize(540, 200)
    ccBox:SetPoint("TOPLEFT", 16, curY)
    ccBox:SetBackdrop({bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 }})
    ccBox:SetBackdropColor(0.05, 0.05, 0.15, 0.95)
    ccBox:SetBackdropBorderColor(0.4, 0.6, 1, 1)

    local ccTitle = ccBox:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    ccTitle:SetPoint("TOPLEFT", ccBox, "TOPLEFT", 12, -10)
    ccTitle:SetText("Custom Cycle Mode")
    ccTitle:SetTextColor(0.4, 0.8, 1)

    local ccToggle = CreateFrame("CheckButton", nil, ccBox, "UICheckButtonTemplate")
    ccToggle:SetSize(24, 24)
    ccToggle:SetPoint("LEFT", ccTitle, "RIGHT", 8, 0)
    ccToggle:SetChecked(WMC_Saved and WMC_Saved.customCycleEnabled or false)
    local ccToggleLabel = ccBox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ccToggleLabel:SetPoint("LEFT", ccToggle, "RIGHT", 2, 0)
    ccToggleLabel:SetText("Enable")

    local ccStatus = ccBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ccStatus:SetPoint("TOPLEFT", ccTitle, "BOTTOMLEFT", 0, -4)
    ccStatus:SetTextColor(0.7, 0.7, 0.7)

    local function UpdateCustomCycleStatus()
        local markers = (WMC_Saved and WMC_Saved.customCycleMarkers) or {}
        local enabled = WMC_Saved and WMC_Saved.customCycleEnabled
        if enabled and #markers > 0 then
            local names = {}
            for _, m in ipairs(markers) do
                table.insert(names, markerNames[m] or tostring(m))
            end
            ccStatus:SetText("Active: " .. #markers .. " markers  --  " .. table.concat(names, " > "))
            ccStatus:SetTextColor(0, 1, 0.5)
        elseif enabled then
            ccStatus:SetText("Enabled but no markers selected!")
            ccStatus:SetTextColor(1, 0.3, 0.3)
        else
            ccStatus:SetText("Disabled  --  using full 8-marker order list")
            ccStatus:SetTextColor(0.5, 0.5, 0.5)
        end
    end

    local ccDesc = ccBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ccDesc:SetPoint("TOPLEFT", ccStatus, "BOTTOMLEFT", 0, -4)
    ccDesc:SetTextColor(0.8, 0.8, 0.8)
    ccDesc:SetWidth(520)
    ccDesc:SetWordWrap(true)
    ccDesc:SetText("Select which markers to include. The first selected marker is always placed first after clearing.")

    local ccMarkerBtns = {}

    local function RebuildCustomCycleFromButtons()
        local list = {}
        for i = 1, 8 do
            if ccMarkerBtns[i] and ccMarkerBtns[i]:GetChecked() then
                table.insert(list, i)
            end
        end
        if #list == 0 then
            print("|cffff4444Custom Cycle: Select at least one marker!|r")
            return
        end
        if WMC_Saved then WMC_Saved.customCycleMarkers = list end
        if api and api.SetCustomCycleMarkers then api.SetCustomCycleMarkers(list) end
        UpdateCustomCycleStatus()
        if f._ccOrderIcons then
            for _, ic in ipairs(f._ccOrderIcons) do ic:Hide() end
        end
        f._ccOrderIcons = f._ccOrderIcons or {}
        for idx, m in ipairs(list) do
            local ic = f._ccOrderIcons[idx]
            if not ic then
                ic = ccBox:CreateTexture(nil, "ARTWORK")
                f._ccOrderIcons[idx] = ic
            end
            ic:SetTexture(markerIcons[m] or markerIcons[1])
            ic:SetSize(22, 22)
            ic:SetPoint("TOPLEFT", ccBox, "BOTTOMLEFT", 12 + (idx-1) * 28, 28)
            ic:Show()
        end
        for idx = #list + 1, 8 do
            if f._ccOrderIcons[idx] then f._ccOrderIcons[idx]:Hide() end
        end
    end

    for i = 1, 8 do
        local col = (i - 1) % 4
        local row = math.floor((i - 1) / 4)
        local cb = CreateFrame("CheckButton", nil, ccBox, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        cb:SetPoint("TOPLEFT", ccDesc, "BOTTOMLEFT", col * 130, -(row * 28 + 6))
        ccMarkerBtns[i] = cb

        local ico = ccBox:CreateTexture(nil, "ARTWORK")
        ico:SetTexture(markerIcons[i] or markerIcons[1])
        ico:SetSize(18, 18)
        ico:SetPoint("LEFT", cb, "RIGHT", 0, 0)

        local lbl = ccBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", ico, "RIGHT", 3, 0)
        local c = markerColors[i]
        lbl:SetText("|cff" .. string.format("%02x%02x%02x", c[1]*255, c[2]*255, c[3]*255) .. markerNames[i] .. "|r")

        local savedCustom = (WMC_Saved and WMC_Saved.customCycleMarkers) or {8, 4, 3, 2}
        for _, m in ipairs(savedCustom) do
            if m == i then cb:SetChecked(true); break end
        end
        cb:SetScript("OnClick", function() RebuildCustomCycleFromButtons() end)
    end

    local ccOrderLabel = ccBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ccOrderLabel:SetPoint("BOTTOMLEFT", ccBox, "BOTTOMLEFT", 12, 52)
    ccOrderLabel:SetText("Cycle order (e.g. 8,4,3,2):")
    ccOrderLabel:SetTextColor(0.8, 0.8, 0.6)

    local ccOrderBox = CreateFrame("EditBox", nil, ccBox, "InputBoxTemplate")
    ccOrderBox:SetSize(120, 20)
    ccOrderBox:SetPoint("LEFT", ccOrderLabel, "RIGHT", 6, 0)
    ccOrderBox:SetAutoFocus(false)
    ccOrderBox:SetText(table.concat((WMC_Saved and WMC_Saved.customCycleMarkers) or {8,4,3,2}, ","))

    local function applyCustomOrder()
        local text = ccOrderBox:GetText()
        local t = {}
        local seen = {}
        for num in string.gmatch(text, "%d") do
            local n = tonumber(num)
            if n and n >= 1 and n <= 8 and not seen[n] then
                table.insert(t, n)
                seen[n] = true
            end
        end
        if #t > 0 then
            if WMC_Saved then WMC_Saved.customCycleMarkers = t end
            if api and api.SetCustomCycleMarkers then api.SetCustomCycleMarkers(t) end
            for i = 1, 8 do
                ccMarkerBtns[i]:SetChecked(seen[i] or false)
            end
        end
        ccOrderBox:SetText(table.concat((WMC_Saved and WMC_Saved.customCycleMarkers) or {}, ","))
        UpdateCustomCycleStatus()
        RebuildCustomCycleFromButtons()
    end
    ccOrderBox:SetScript("OnEnterPressed", applyCustomOrder)
    ccOrderBox:SetScript("OnEditFocusLost", applyCustomOrder)

    ccToggle:SetScript("OnClick", function(self)
        local enabled = self:GetChecked()
        if WMC_Saved then WMC_Saved.customCycleEnabled = enabled end
        if api and api.SetCustomCycleEnabled then api.SetCustomCycleEnabled(enabled) end
        UpdateCustomCycleStatus()
    end)

    UpdateCustomCycleStatus()
    RebuildCustomCycleFromButtons()
    curY = curY - 210

    -- Set total scroll content height
    scrollChild:SetHeight(math.abs(curY) + 20)

    -- Slash command
    SLASH_WMCEDITOR1 = "/wmckey"
    SlashCmdList["WMCEDITOR"] = function()
        if f:IsShown() then f:Hide() else f:Show() end
    end

    f:HookScript("OnShow", function() end)
    f:Hide()
end

function WorldMarkerCyclerUI_OnReady()
    if not f then
        BuildUI()
    end
end
