---@diagnostic disable: undefined-global, undefined-field
-- One transfer page, two columns.  Export choice is intentionally small;
-- imports expose only the included appearance and role assignments.

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI

ExBoss.UI.Panel.ImportExportPage = ExBoss.UI.Panel.ImportExportPage or {}
local Page = ExBoss.UI.Panel.ImportExportPage
local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, key) return key end })

local BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14, insets = { left = 4, right = 4, top = 4, bottom = 4 },
}
local BACKDROP_SIMPLE = { bgFile = "Interface\\Buttons\\WHITE8X8" }
local THEME = {
    Background = { 0.04, 0.04, 0.05, 0.98 }, Border = { 0.25, 0.25, 0.28, 1 },
    Primary = { 0.64, 0.19, 0.79 }, Success = { 0.13, 0.77, 0.37 },
    TextMain = { 0.9, 0.9, 0.9, 1 }, TextSub = { 0.6, 0.6, 0.65, 1 },
}
local ROLE_LABELS = {
    mplus_tank = L["大秘境坦克"], mplus_heal = L["大秘境治疗"], mplus_dps = L["大秘境 DPS"],
    raid_tank = L["团本坦克"], raid_heal = L["团本治疗"], raid_dps = L["团本 DPS"],
}
local ROLE_ORDER = { "mplus_tank", "mplus_heal", "mplus_dps", "raid_tank", "raid_heal", "raid_dps" }

local scrollFrame, scrollChild, exportPopup, uiBuilt
local exportNameInput, exportAppearanceCheck, exportAppearanceDropdown, exportMplusCheck, exportRaidCheck, exportStatus
local importInputBox, importSummary, importStatus, importAppearanceCheck, importLegacyCheck, importSection, importButton, apiImportButton
local importRoleChecks, parsedTransfer
local importNameRows = {}

local function Trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function CreateSmallButton(parent, text, onClick)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(120, 28); button:SetBackdrop(BACKDROP_SIMPLE); button:SetBackdropColor(0.2, 0.2, 0.25, 0.9)
    local label = EXUI:CreateVisualFontString(button, EXFONTFRAME, "GameFontNormal")
    label:SetPoint("CENTER"); label:SetText(text); label:SetTextColor(unpack(THEME.TextMain))
    button:SetScript("OnClick", onClick)
    button:SetScript("OnEnter", function(self) self:SetBackdropColor(0.3, 0.3, 0.35, 0.95) end)
    button:SetScript("OnLeave", function(self) self:SetBackdropColor(0.2, 0.2, 0.25, 0.9) end)
    return button
end

local function CreateActionButton(parent, text, onClick, color)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    local base = color or THEME.Primary
    button:SetSize(180, 40); button:SetBackdrop(BACKDROP); button:SetBackdropColor(unpack(base)); button:SetBackdropBorderColor(0.5, 0.5, 0.55, 0.8)
    local label = EXUI:CreateVisualFontString(button, EXFONTFRAME, "GameFontNormal")
    label:SetPoint("CENTER"); label:SetText(text); label:SetTextColor(1, 1, 1, 1)
    button:SetScript("OnClick", onClick)
    button:SetScript("OnEnter", function(self)
        self:SetBackdropColor(math.min(1, base[1] * 1.3), math.min(1, base[2] * 1.3), math.min(1, base[3] * 1.3), 1)
    end)
    button:SetScript("OnLeave", function(self) self:SetBackdropColor(unpack(base)) end)
    return button
end

-- Import/export fields must use the shared EXUI factory.  Apart from visual
-- consistency, that factory also owns focus, placeholder, scroll, and pool
-- lifecycle behaviour.  This page used to create bare black EditBoxes.
local function GetNativeEditBox(control)
    return control and (control.editBox or control.EditBox or control) or nil
end

local function StyleInput(control)
    if control and control.SetBackdropColor then
        control:SetBackdropColor(0.10, 0.11, 0.16, 0.96)
        control:SetBackdropBorderColor(0.48, 0.52, 0.66, 0.95)
    end
    local edit = GetNativeEditBox(control)
    if edit and edit.SetTextColor then
        edit:SetTextColor(0.92, 0.94, 0.99, 1)
    end
    return control
end

local function CreateMultiLineEditBox(parent, width, height)
    return StyleInput(EXUI:CreateEditBox(parent, "", width, height, nil, {}))
end

local function CreateSingleLineEditBox(parent, width)
    return StyleInput(EXUI:CreateEditBox(parent, "", width, 28, nil, {}))
end

local function FocusAndHighlight(control)
    local edit = GetNativeEditBox(control)
    if edit and edit.SetFocus then
        edit:SetFocus()
        if edit.HighlightText then edit:HighlightText() end
    end
end

local function ShowExportPopup(encoded, name)
    if not exportPopup then
        local popup = CreateFrame("Frame", "ExBoss_ExportPopup", UIParent, "BackdropTemplate")
        popup:SetSize(600, 350); popup:SetPoint("CENTER"); popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:SetBackdrop(BACKDROP); popup:SetBackdropColor(0.06, 0.06, 0.08, 0.98); popup:SetBackdropBorderColor(unpack(THEME.Border))
        popup:EnableMouse(true); popup:SetMovable(true); popup:RegisterForDrag("LeftButton")
        popup:SetScript("OnDragStart", popup.StartMoving); popup:SetScript("OnDragStop", popup.StopMovingOrSizing)
        if not tContains(UISpecialFrames, "ExBoss_ExportPopup") then table.insert(UISpecialFrames, "ExBoss_ExportPopup") end
        local title = EXUI:CreateVisualFontString(popup, EXFONTFRAME)
        title:SetFont(ExwindTools.MAIN_FONT or "Fonts\\FRIZQT__.TTF", 22, "OUTLINE"); title:SetPoint("TOP", 0, -15); popup.Title = title
        local close = CreateFrame("Button", nil, popup, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -5, -5); close:SetScript("OnClick", function() popup:Hide() end)
        local hint = EXUI:CreateVisualFontString(popup, EXFONTFRAME, "GameFontHighlight")
        hint:SetPoint("TOP", title, "BOTTOM", 0, -8); hint:SetTextColor(0.8, 0.8, 0.8); hint:SetText("|cffffd100Ctrl+C|r " .. L["复制，或点击"] .. " |cffffd100" .. L["全选复制"] .. "|r")
        popup.ExportTextInput = CreateMultiLineEditBox(popup, 560, 200)
        popup.ExportTextInput:SetPoint("TOP", hint, "BOTTOM", 0, -10)
        local selectButton = CreateSmallButton(popup, L["全选复制"], function() FocusAndHighlight(popup.ExportTextInput) end)
        selectButton:SetSize(100, 28); selectButton:SetPoint("BOTTOM", popup, "BOTTOM", -60, 15)
        local closeButton = CreateSmallButton(popup, L["关闭"], function() popup:Hide() end)
        closeButton:SetSize(80, 28); closeButton:SetPoint("BOTTOM", popup, "BOTTOM", 60, 15)
        exportPopup = popup
    end
    exportPopup.ExportTextInput:SetText(encoded or "")
    exportPopup.Title:SetText("|cff00ff80" .. L["导出成功"] .. "|r - " .. tostring(name or ""))
    exportPopup:Show(); FocusAndHighlight(exportPopup.ExportTextInput)
end

local function SectionBg(parent, title, color)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetBackdrop(BACKDROP); frame:SetBackdropColor(unpack(THEME.Background)); frame:SetBackdropBorderColor(unpack(THEME.Border))
    local bar = EXUI:CreateVisualTexture(frame, EXBORDERFRAME)
    bar:SetColorTexture(color[1], color[2], color[3], 0.90); bar:SetHeight(2); bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -6); bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)
    local heading = EXUI:CreateVisualFontString(frame, EXFONTFRAME)
    heading:SetFont(ExwindTools.MAIN_FONT or "Fonts\\FRIZQT__.TTF", 16, "OUTLINE"); heading:SetPoint("TOPLEFT", 14, -14); heading:SetText(title); heading:SetTextColor(unpack(color))
    return frame
end

local function MakeLabel(parent, text)
    local label = EXUI:CreateVisualFontString(parent, EXFONTFRAME, "GameFontHighlightSmall")
    label:SetText(text or ""); label:SetTextColor(unpack(THEME.TextSub)); label:SetJustifyH("LEFT")
    return label
end

local function Profiles()
    return ExBoss and ExBoss.AppearanceProfiles
end

local function IE()
    return ExBoss and ExBoss.Voice and ExBoss.Voice.ImportExport
end

local function SetStatus(target, text, ok)
    if not target then return end
    local color = ok == true and "|cff33ee77" or ok == false and "|cffff6666" or "|cffbfc8d6"
    target:SetText(color .. tostring(text or "") .. "|r")
end

local function IsChecked(check)
    return check and check.GetChecked and check:GetChecked() == true
end

local function SetVisible(frame, visible)
    if frame then
        if visible then frame:Show() else frame:Hide() end
    end
end

local function IsVisible(frame)
    return frame and frame.IsShown and frame:IsShown() == true
end

local function ClearImportNameRows()
    for _, row in ipairs(importNameRows or {}) do
        row.label:Hide()
        row.input:Hide()
    end
    importNameRows = {}
end

local function PairRoleLabel(category, assignments, pairID)
    local roles = {}
    for _, slot in ipairs(ROLE_ORDER) do
        if tostring(assignments[slot] or "") == tostring(pairID) then
            roles[#roles + 1] = ROLE_LABELS[slot]
        end
    end
    local scene = category == "raid" and L["团本"] or L["大秘境"]
    return scene .. " Author（" .. table.concat(roles, " + ") .. "）"
end

local function PairRoleSuffix(assignments, pairID)
    local roles = {}
    for _, slot in ipairs(ROLE_ORDER) do
        if tostring(assignments[slot] or "") == tostring(pairID) then
            roles[#roles + 1] = ROLE_LABELS[slot]
        end
    end
    return #roles > 0 and table.concat(roles, " + ") or tostring(pairID)
end

-- The package name is the sender's intended receiver-facing default.  It
-- wins over the source Author name.  More than one unique Author in a scene
-- cannot all be imported under the exact same name, so make those defaults
-- distinct before the receiver presses Import.
local function SuggestedPairImportName(bundleName, scene, pair)
    local name = Trim(bundleName)
    if name == "" then
        return pair and pair.author and pair.author.name or ""
    end
    if type(scene) == "table" and #(scene.pairs or {}) > 1 then
        return name .. " - " .. PairRoleSuffix(scene.assignments or {}, pair and pair.id)
    end
    return name
end

local function AddImportNameRow(kind, title, data)
    if not importSection then return end
    local width = math.max(200, (importSection:GetWidth() or 500) - 28)
    local row = {
        kind = kind,
        title = title,
        data = data or {},
        label = MakeLabel(importSection, title .. " " .. L["名称（必填）"]),
        input = CreateSingleLineEditBox(importSection, width),
    }
    row.input:SetText(Trim(row.data.suggestedName))
    row.label:Hide()
    row.input:Hide()
    importNameRows[#importNameRows + 1] = row
end

local function IsImportNameRowSelected(row)
    if row.kind == "appearance" then return IsChecked(importAppearanceCheck) end
    if row.kind == "legacy" then return IsChecked(importLegacyCheck) end
    if row.kind ~= "pair" then return false end
    local assignments = row.data.assignments or {}
    for _, slot in ipairs(ROLE_ORDER) do
        if tostring(assignments[slot] or "") == tostring(row.data.pairID)
            and IsChecked(importRoleChecks and importRoleChecks[slot]) then
            return true
        end
    end
    return false
end

local function LayoutImportControls()
    if not importSection then return end
    local y = -230
    for _, row in ipairs(importNameRows) do
        local visible = IsImportNameRowSelected(row)
        SetVisible(row.label, visible)
        SetVisible(row.input, visible)
        if visible then
            row.label:ClearAllPoints(); row.label:SetPoint("TOPLEFT", 14, y)
            row.input:ClearAllPoints(); row.input:SetPoint("TOPLEFT", 14, y - 18)
            y = y - 52
        end
    end

    if importSummary then
        importSummary:ClearAllPoints(); importSummary:SetPoint("TOPLEFT", 14, y); importSummary:SetPoint("TOPRIGHT", -14, y)
        y = y - math.max(60, (tonumber(importSummary._lineCount) or 0) * 14 + 10)
    end

    for _, check in ipairs({ importAppearanceCheck, importLegacyCheck }) do
        if IsVisible(check) then
            check:ClearAllPoints(); check:SetPoint("TOPLEFT", 14, y)
            y = y - 28
        end
    end
    for _, slot in ipairs(ROLE_ORDER) do
        local check = importRoleChecks and importRoleChecks[slot]
        if IsVisible(check) then
            check:ClearAllPoints(); check:SetPoint("TOPLEFT", 14, y)
            y = y - 25
        end
    end
    if importButton then
        importButton:ClearAllPoints(); importButton:SetPoint("TOPLEFT", 14, y)
        y = y - 44
    end
    if apiImportButton then
        apiImportButton:ClearAllPoints(); apiImportButton:SetPoint("TOPLEFT", 14, y)
        y = y - 44
    end
    if importStatus then
        importStatus:ClearAllPoints(); importStatus:SetPoint("TOPLEFT", 14, y); importStatus:SetPoint("TOPRIGHT", -14, y)
        y = y - 34
    end
    importSection:SetHeight(math.max(700, -y + 18))
    if scrollChild then scrollChild:SetHeight(math.max(740, importSection:GetHeight() + 36)) end
end

local function RefreshImportNameRows()
    LayoutImportControls()
end

local function BuildImportNameRows(decoded)
    ClearImportNameRows()
    if decoded.kind == "appearance" then
        AddImportNameRow("appearance", L["外观配置"], { suggestedName = decoded.profile and decoded.profile.name })
    elseif decoded.kind == "legacyBoss" then
        local category = decoded.profile.category == "raid" and L["团本"] or L["大秘境"]
        AddImportNameRow("legacy", category .. " " .. L["Author 配置"], {
            category = decoded.profile.category,
            suggestedName = decoded.profile.author and decoded.profile.author.name,
        })
    elseif decoded.kind == "bundle" then
        local bundle = decoded.bundle
        local bundleName = Trim(bundle.name)
        if bundle.appearance then
            AddImportNameRow("appearance", L["外观配置"], {
                suggestedName = bundleName ~= "" and bundleName or bundle.appearance.name,
            })
        end
        for _, category in ipairs({ "mplus", "raid" }) do
            local scene = bundle.scenes[category]
            if scene then
                for _, pair in ipairs(scene.pairs) do
                    AddImportNameRow("pair", PairRoleLabel(category, scene.assignments, pair.id), {
                        category = category,
                        pairID = pair.id,
                        assignments = scene.assignments,
                        suggestedName = SuggestedPairImportName(bundleName, scene, pair),
                    })
                end
            end
        end
    end
    RefreshImportNameRows()
end

local function CollectImportNames()
    local names, used = { pairs = {} }, { appearance = {}, mplus = {}, raid = {} }
    for _, row in ipairs(importNameRows) do
        if IsImportNameRowSelected(row) then
            local name = Trim(row.input:GetText())
            if name == "" then return nil, L["请填写："] .. row.title end
            if row.kind == "appearance" then
                if used.appearance[name] then return nil, L["导入名称不能重复："] .. name end
                used.appearance[name] = true
                names.appearance = name
            elseif row.kind == "legacy" then
                local category = row.data.category == "raid" and "raid" or "mplus"
                if used[category][name] then return nil, L["导入名称不能重复："] .. name end
                used[category][name] = true
                names.legacy = name
            elseif row.kind == "pair" then
                local category = row.data.category
                if used[category][name] then return nil, L["导入名称不能重复："] .. name end
                used[category][name] = true
                names.pairs[category] = names.pairs[category] or {}
                names.pairs[category][row.data.pairID] = name
            end
        end
    end
    if names.appearance then
        local profiles = Profiles()
        if not profiles or type(profiles.IsProfileNameAvailable) ~= "function" then
            return nil, L["外观配置系统不可用"]
        end
        if profiles:IsProfileNameAvailable(names.appearance) ~= true then
            return nil, L["外观配置名称已存在："] .. names.appearance
        end
    end
    for category, pairNames in pairs(names.pairs) do
        local boss = ExBoss and ExBoss.BossConfig
        if not boss or type(boss.IsAuthorConfigurationNameAvailable) ~= "function" then
            return nil, L["Boss 配置系统不可用"]
        end
        for _, name in pairs(pairNames) do
            if boss:IsAuthorConfigurationNameAvailable(category, name) ~= true then
                return nil, L["Author 配置名称已存在："] .. name
            end
        end
    end
    return names
end

local function RefreshAppearanceDropdown(preferredID)
    local profiles = Profiles()
    if not (profiles and exportAppearanceDropdown and profiles.GetProfileItems) then return end
    local items = profiles:GetProfileItems()
    exportAppearanceDropdown._items = items
    local active = profiles.GetActiveProfileID and profiles:GetActiveProfileID() or ""
    local selected = tostring(preferredID or exportAppearanceDropdown._value or active or "")
    local found = false
    for _, item in ipairs(items) do if tostring(item[2]) == selected then found = true break end end
    if not found then selected = tostring(active or (items[1] and items[1][2]) or "") end
    exportAppearanceDropdown._value, exportAppearanceDropdown._currentValue = selected, selected
    for _, item in ipairs(items) do
        if tostring(item[2]) == selected then exportAppearanceDropdown:SetText(item[1]); return end
    end
    exportAppearanceDropdown:SetText(L["没有可用外观配置"])
end

local function ExportBundle()
    local ie = IE()
    if not ie or type(ie.ExportBundle) ~= "function" then
        SetStatus(exportStatus, L["导出系统不可用"], false); return
    end
    local options = {
        name = Trim(exportNameInput and exportNameInput:GetText() or ""),
        appearanceProfileID = IsChecked(exportAppearanceCheck) and exportAppearanceDropdown and exportAppearanceDropdown._value or nil,
        mplus = IsChecked(exportMplusCheck),
        raid = IsChecked(exportRaidCheck),
    }
    local encoded, reason = ie:ExportBundle(options)
    if not encoded then SetStatus(exportStatus, L["导出失败："] .. tostring(reason), false); return end
    SetStatus(exportStatus, L["已导出所选配置"], true)
    ShowExportPopup(encoded, options.name ~= "" and options.name or L["外观 / Boss 配置"])
end

local function ClearImportChoices()
    parsedTransfer = nil
    ClearImportNameRows()
    SetVisible(importAppearanceCheck, false)
    SetVisible(importLegacyCheck, false)
    for _, check in pairs(importRoleChecks or {}) do SetVisible(check, false) end
    if importSummary then importSummary:SetText(""); importSummary._lineCount = 0 end
    LayoutImportControls()
end

local function ShowParsedTransfer(decoded)
    ClearImportChoices()
    parsedTransfer = decoded
    local lines = {}
    if decoded.kind == "appearance" then
        importAppearanceCheck:SetChecked(true); SetVisible(importAppearanceCheck, true)
        lines[#lines + 1] = L["内容：外观与模块配置"]
        lines[#lines + 1] = L["导入后会直接启用，并重载界面。"]
    elseif decoded.kind == "legacyBoss" then
        importLegacyCheck:SetChecked(true); SetVisible(importLegacyCheck, true)
        local scene = decoded.profile.category == "raid" and L["团本"] or L["大秘境"]
        lines[#lines + 1] = L["旧版内容："] .. scene .. " Author + User"
        lines[#lines + 1] = L["旧字符串没有职责映射：可导入，但不会自动启用。"]
    elseif decoded.kind == "bundle" then
        local bundle = decoded.bundle
        if Trim(bundle.name) ~= "" then
            lines[#lines + 1] = L["导出包名称："] .. tostring(bundle.name)
        end
        if bundle.appearance then
            importAppearanceCheck:SetChecked(true); SetVisible(importAppearanceCheck, true)
            lines[#lines + 1] = L["外观："] .. tostring(bundle.appearance.name or L["外观配置"])
        end
        for _, category in ipairs({ "mplus", "raid" }) do
            local scene = bundle.scenes[category]
            if scene then
                lines[#lines + 1] = (category == "raid" and L["团本"] or L["大秘境"]) .. "：" .. tostring(#scene.pairs) .. L[" 个 Author + User 配置对"]
                for _, slot in ipairs(ROLE_ORDER) do
                    if scene.assignments[slot] then
                        local check = importRoleChecks[slot]
                        check:SetChecked(true); SetVisible(check, true)
                    end
                end
            end
        end
        lines[#lines + 1] = L["勾选的职责会导入并切换；未勾选的职责不会导入对应配置。"]
    end
    importSummary:SetText(table.concat(lines, "\n"))
    importSummary._lineCount = #lines
    BuildImportNameRows(decoded)
end

local function ParseImport()
    ClearImportChoices()
    local raw = Trim(importInputBox and importInputBox:GetText() or "")
    if raw == "" then SetStatus(importStatus, L["请先粘贴导出字符串"], false); return end

    local profiles = Profiles()
    if raw:sub(1, 11) == "!EXBOSSAP1!" then
        local profile, reason = profiles and profiles.DecodeImportString and profiles:DecodeImportString(raw)
        if not profile then SetStatus(importStatus, L["解析失败："] .. tostring(reason), false); return end
        ShowParsedTransfer({ kind = "appearance", profile = profile })
        SetStatus(importStatus, L["解析成功：选择后执行导入"], true)
        return
    end

    local ie = IE()
    local decoded, reason = ie and ie.DecodeTransfer and ie:DecodeTransfer(raw)
    if not decoded then SetStatus(importStatus, L["解析失败："] .. tostring(reason or L["导入系统不可用"]), false); return end
    ShowParsedTransfer(decoded)
    SetStatus(importStatus, L["解析成功：勾选要导入并启用的内容"], true)
end

local function ImportAppearance(profile, importedName)
    local profiles = Profiles()
    if not profiles or type(profiles.ImportProfilePayload) ~= "function" or type(profiles.ActivateProfile) ~= "function" then
        return false, L["外观配置系统不可用"]
    end
    local payload = {
        name = Trim(importedName) ~= "" and Trim(importedName) or profile.name,
        appearance = profile.appearance,
    }
    local ok, idOrReason = profiles:ImportProfilePayload(payload)
    if not ok then return false, idOrReason end
    local activated, changedOrReason = profiles:ActivateProfile(idOrReason)
    if not activated then return false, changedOrReason end
    return true, changedOrReason == true
end

local function SelectedRoles(category, assignments)
    local selected = {}
    for _, slot in ipairs(ROLE_ORDER) do
        if assignments[slot] and IsChecked(importRoleChecks[slot]) then selected[slot] = true end
    end
    return selected
end

local function HasSelectedRole(selected)
    return next(selected) ~= nil
end

local function DoImport()
    if not parsedTransfer then SetStatus(importStatus, L["请先点击解析"], false); return end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        SetStatus(importStatus, L["战斗中不能导入或切换配置"], false); return
    end
    local importNames, nameReason = CollectImportNames()
    if not importNames then SetStatus(importStatus, nameReason, false); return end

    local changed, imported = false, 0
    if parsedTransfer.kind == "appearance" then
        if IsChecked(importAppearanceCheck) then
            local ok, result = ImportAppearance(parsedTransfer.profile, importNames.appearance)
            if not ok then SetStatus(importStatus, L["导入失败："] .. tostring(result), false); return end
            changed, imported = result == true, imported + 1
        end
    elseif parsedTransfer.kind == "legacyBoss" then
        if IsChecked(importLegacyCheck) then
            local ie = IE()
            if not ie or type(ie.ImportUserConfigurationPayload) ~= "function" then
                SetStatus(importStatus, L["导入失败："] .. L["导入系统不可用"], false)
                return
            end
            local ok, result = ie:ImportUserConfigurationPayload({ version = 6, payloadType = "exboss_author_user_values", profile = parsedTransfer.profile }, importNames.legacy)
            if not ok then SetStatus(importStatus, L["导入失败："] .. tostring(result), false); return end
            imported = imported + 1
        end
    elseif parsedTransfer.kind == "bundle" then
        local bundle = parsedTransfer.bundle
        if bundle.appearance and IsChecked(importAppearanceCheck) then
            local ok, result = ImportAppearance(bundle.appearance, importNames.appearance)
            if not ok then SetStatus(importStatus, L["导入失败："] .. tostring(result), false); return end
            changed, imported = result == true, imported + 1
        end
        local boss = ExBoss and ExBoss.BossConfig
        for _, category in ipairs({ "mplus", "raid" }) do
            local scene = bundle.scenes[category]
            if scene then
                local selected = SelectedRoles(category, scene.assignments)
                if HasSelectedRole(selected) then
                    if not boss or type(boss.ImportSelectedScene) ~= "function" then
                        SetStatus(importStatus, L["导入失败："] .. L["Boss 配置系统不可用"], false)
                        return
                    end
                    -- Do not combine this call with `and`: Lua collapses the
                    -- second return value of a call used inside an expression.
                    -- We need the result table to count imported pairs and
                    -- switched role assignments after a successful import.
                    local ok, result = boss:ImportSelectedScene(category, scene.pairs, scene.assignments, selected, importNames.pairs[category])
                    if not ok then SetStatus(importStatus, L["导入失败："] .. tostring(result), false); return end
                    imported = imported + (tonumber(result.imported) or 0)
                    changed = changed or (tonumber(result.assignments) or 0) > 0
                end
            end
        end
    end

    if imported == 0 then SetStatus(importStatus, L["没有勾选需要导入的内容"], nil); return end
    if changed then
        if type(ReloadUI) ~= "function" then SetStatus(importStatus, L["无法重载界面，未完成切换"], false); return end
        ReloadUI()
        return
    end
    SetStatus(importStatus, L["已导入。旧版字符串不会自动切换配置。"], true)
end

-- This is deliberately separate from the normal import workflow: it calls
-- the public Wago API with the exact string in the box, so it exposes the
-- returned failure reason that a third-party wrapper may otherwise swallow.
local function DoPublicAPIImport()
    local raw = Trim(importInputBox and importInputBox:GetText() or "")
    if raw == "" then SetStatus(importStatus, L["请先粘贴导出字符串"], false); return end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        SetStatus(importStatus, L["战斗中不能导入或切换配置"], false); return
    end
    local api = _G.EXBossWagoAPI
    if type(api) ~= "table" or type(api.ImportProfile) ~= "function" then
        SetStatus(importStatus, L["Wago API 不可用"], false); return
    end
    local ok, result = api:ImportProfile(raw)
    if not ok then
        SetStatus(importStatus, L["Wago API 导入失败："] .. tostring(result), false)
        return
    end
    if type(result) == "table" and result.reloadRequired == true then
        SetStatus(importStatus, L["Wago API 导入成功，正在重载界面"], true)
        if type(ReloadUI) == "function" then ReloadUI(); return end
    end
    SetStatus(importStatus, L["Wago API 导入成功"], true)
end

local function DefaultExportChecks()
    local _, instanceType = GetInstanceInfo()
    if instanceType == "raid" then return false, true end
    return true, false
end

local function EnsureUI(contentFrame)
    if uiBuilt and scrollFrame and scrollFrame:GetParent() == contentFrame then return end
    if scrollFrame then scrollFrame:Hide(); scrollFrame:SetParent(UIParent) end
    scrollFrame = CreateFrame("ScrollFrame", nil, contentFrame, "ScrollFrameTemplate")
    if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then ExBoss.UI.ApplyModernScrollBarSkin(scrollFrame) end
    scrollFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 4, -4); scrollFrame:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -26, 4)
    scrollChild = CreateFrame("Frame", nil, scrollFrame); scrollFrame:SetScrollChild(scrollChild)
    local width = math.max(600, (contentFrame:GetWidth() or 1100) - 50)
    local columnWidth = math.floor((width - 20) / 2) - 6
    local defaultMplus, defaultRaid = DefaultExportChecks()

    local exportSection = SectionBg(scrollChild, L["导出"], THEME.Primary)
    exportSection:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, -16); exportSection:SetWidth(columnWidth); exportSection:SetHeight(700)
    local y = -42
    MakeLabel(exportSection, L["导出包名称（可选，供接收方识别）"]):SetPoint("TOPLEFT", 14, y); y = y - 20
    exportNameInput = CreateSingleLineEditBox(exportSection, columnWidth - 28)
    exportNameInput:SetPoint("TOPLEFT", 14, y); y = y - 44
    exportAppearanceCheck = EXUI:CreateCheckbox(exportSection, L["是否导出外观配置"], true, function() end)
    exportAppearanceCheck:SetPoint("TOPLEFT", 14, y); y = y - 32
    exportAppearanceDropdown = EXUI:CreateDropdown(exportSection, columnWidth - 42, L["选择外观配置"], {}, "", function(value)
        exportAppearanceDropdown._value, exportAppearanceDropdown._currentValue = value, value
    end)
    exportAppearanceDropdown:SetPoint("TOPLEFT", 28, y); y = y - 48
    exportMplusCheck = EXUI:CreateCheckbox(exportSection, L["是否导出大秘境配置"], defaultMplus, function() end)
    exportMplusCheck:SetPoint("TOPLEFT", 14, y); y = y - 34
    exportRaidCheck = EXUI:CreateCheckbox(exportSection, L["是否导出团本配置"], defaultRaid, function() end)
    exportRaidCheck:SetPoint("TOPLEFT", 14, y); y = y - 52
    local exportButton = CreateActionButton(exportSection, L["生成导出字符串"], ExportBundle)
    exportButton:SetSize(170, 38); exportButton:SetPoint("TOPLEFT", 14, y); y = y - 52
    exportStatus = EXUI:CreateVisualFontString(exportSection, EXFONTFRAME, "GameFontHighlightSmall")
    exportStatus:SetPoint("TOPLEFT", 14, y); exportStatus:SetPoint("TOPRIGHT", -14, y); exportStatus:SetJustifyH("LEFT"); exportStatus:SetJustifyV("TOP"); exportStatus:SetTextColor(unpack(THEME.TextSub))
    exportStatus:SetText(L["Boss 配置始终按「Author + 对应 User 覆盖」成对导出。相同 Author 只会导出一次，并附带职责启用映射。"])

    importSection = SectionBg(scrollChild, L["导入"], THEME.Success)
    importSection:SetPoint("TOPLEFT", exportSection, "TOPRIGHT", 20, 0); importSection:SetWidth(columnWidth); importSection:SetHeight(700)
    local iy = -42
    MakeLabel(importSection, L["粘贴导出字符串"]):SetPoint("TOPLEFT", 14, iy); iy = iy - 20
    importInputBox = CreateMultiLineEditBox(importSection, columnWidth - 28, 110)
    importInputBox:SetPoint("TOPLEFT", 14, iy); iy = iy - 122
    local parse = CreateActionButton(importSection, L["解析"], ParseImport, THEME.Success)
    parse:SetSize(100, 32); parse:SetPoint("TOPLEFT", 14, iy); iy = iy - 46
    importSummary = EXUI:CreateVisualFontString(importSection, EXFONTFRAME, "GameFontHighlightSmall")
    importSummary:SetPoint("TOPLEFT", 14, iy); importSummary:SetPoint("TOPRIGHT", -14, iy); importSummary:SetJustifyH("LEFT"); importSummary:SetJustifyV("TOP"); importSummary:SetTextColor(unpack(THEME.TextMain)); importSummary:SetText("")
    importSummary._lineCount = 0
    iy = iy - 70
    importAppearanceCheck = EXUI:CreateCheckbox(importSection, L["导入并启用外观配置"], true, RefreshImportNameRows)
    importAppearanceCheck:SetPoint("TOPLEFT", 14, iy); iy = iy - 28
    importLegacyCheck = EXUI:CreateCheckbox(importSection, L["导入旧版 Author + User（不自动启用）"], true, RefreshImportNameRows)
    importLegacyCheck:SetPoint("TOPLEFT", 14, iy); iy = iy - 28
    importRoleChecks = {}
    for _, slot in ipairs(ROLE_ORDER) do
        local check = EXUI:CreateCheckbox(importSection, L["导入并切换："] .. ROLE_LABELS[slot], true, RefreshImportNameRows)
        check:SetPoint("TOPLEFT", 14, iy); iy = iy - 25
        importRoleChecks[slot] = check
    end
    importButton = CreateActionButton(importSection, L["执行导入"], DoImport, THEME.Success)
    importButton:SetSize(140, 36); importButton:SetPoint("BOTTOMLEFT", 14, 46)
    apiImportButton = CreateActionButton(importSection, L["测试：通过 Wago API 导入"], DoPublicAPIImport, THEME.Primary)
    apiImportButton:SetSize(200, 36); apiImportButton:SetPoint("BOTTOMLEFT", 164, 46)
    importStatus = EXUI:CreateVisualFontString(importSection, EXFONTFRAME, "GameFontHighlightSmall")
    importStatus:SetPoint("BOTTOMLEFT", 14, 16); importStatus:SetPoint("BOTTOMRIGHT", -14, 16); importStatus:SetJustifyH("LEFT"); importStatus:SetTextColor(unpack(THEME.TextSub)); importStatus:SetText("")

    scrollChild:SetSize(width, 740)
    uiBuilt = true
    RefreshAppearanceDropdown()
    ClearImportChoices()
end

function Page:Render(contentFrame)
    EnsureUI(contentFrame)
    scrollFrame:SetParent(contentFrame); scrollFrame:ClearAllPoints(); scrollFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 4, -4); scrollFrame:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -26, 4)
    scrollChild:SetWidth(math.max(600, (contentFrame:GetWidth() or 1100) - 50))
    scrollFrame:Show()
    RefreshAppearanceDropdown()
end

function Page:Hide()
    if scrollFrame then scrollFrame:Hide() end
end
