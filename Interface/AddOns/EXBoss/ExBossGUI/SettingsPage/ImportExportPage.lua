---@diagnostic disable: undefined-global, undefined-field
-- One transfer page, two columns.  Export choice is intentionally small;
-- imports expose only the included appearance and role assignments.

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI
local GC = ExwindTools.GUIColors

ExBoss.UI.Panel.ImportExportPage = ExBoss.UI.Panel.ImportExportPage or {}
local Page = ExBoss.UI.Panel.ImportExportPage
local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, key) return key end })

local THEME = {
    Background = GC.popup, Border = GC.popupBorder,
    Primary = GC.accent, Success = { 0.13, 0.77, 0.37 },
    TextMain = GC.text, TextSub = GC.textDim,
}
local ROLE_LABELS = {
    mplus_tank = L["大秘境坦克"], mplus_heal = L["大秘境治疗"], mplus_dps = L["大秘境 DPS"],
    raid_tank = L["团本坦克"], raid_heal = L["团本治疗"], raid_dps = L["团本 DPS"],
}
local ROLE_ORDER = { "mplus_tank", "mplus_heal", "mplus_dps", "raid_tank", "raid_heal", "raid_dps" }

local scrollFrame, scrollChild, uiBuilt
local exportFormSession, RelayoutExportPresentation
local importFormSession, importParseButton, RelayoutImportPresentation
local exportNameInput, exportAppearanceCheck, exportAppearanceDropdown, exportMplusCheck, exportRaidCheck, exportResultInput
local importInputBox, importAppearanceCheck, importLegacyCheck, exportSection, importSection, importButton, apiImportButton
local importRoleChecks, parsedTransfer
local importNameRows = {}
local LayoutTransferColumns

local function Trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function CreateActionButton(parent, text, onClick)
    return EXUI:CreateButton(parent, 180, 28, text, onClick,
        { variant = "primary", compact = true })
end

-- Import/export fields must use the shared EXUI factory.  Apart from visual
-- consistency, that factory also owns focus, placeholder, scroll, and pool
-- lifecycle behaviour.  This page used to create bare black EditBoxes.
local function GetNativeEditBox(control)
    return control and (control.editBox or control.EditBox or control) or nil
end

local function StyleInput(control)
    if control and control.SetBackdropColor then
        control:SetBackdropColor(unpack(GC.input))
        control:SetBackdropBorderColor(unpack(GC.panelBorder))
    end
    local edit = GetNativeEditBox(control)
    if edit and edit.SetTextColor then
        edit:SetTextColor(unpack(GC.text))
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

local function SectionBg(parent, title, color)
    local card = EXUI:CreateSettingsCard(parent, { title = "", collapsible = false })
    card._sectionHeading = EXUI:CreateSettingsSection(parent, { kind = "section", title = title })
    local body = card:GetBody()
    body._settingsCard = card
    return body
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

local function SetStatus(text, ok)
    local color = ok == true and "|cff33ee77" or ok == false and "|cffff6666" or "|cffbfc8d6"
    local message = color .. tostring(text or "") .. "|r"
    if ExBoss.Print and type(ExBoss.Print.Say) == "function" then
        ExBoss.Print.Say(message)
    else
        print(message)
    end
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
    if importFormSession then
        importFormSession:Release()
        importFormSession = nil
    end
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

RelayoutImportPresentation = function()
    if not importFormSession or not importSection then return end
    local height = importFormSession:Relayout(math.max(1, importSection:GetWidth() or 1))
    importSection._settingsCard:SetContentHeight(height)
    if scrollChild then
        local exportHeight = exportSection and exportSection._settingsCard and exportSection._settingsCard:GetHeight() or 0
        scrollChild:SetHeight(math.max(1, math.max(exportHeight, importSection._settingsCard:GetHeight()) + 80))
    end
end

local function LayoutImportControls()
    -- 只重排原同parent控件；原选择、显隐、职责顺序及输入对象保持。
    if not importSection then return end
    if importFormSession then
        importFormSession:Release()
        importFormSession = nil
    end
    local rows = {}
    rows[#rows + 1] = { controls = { { widget = importInputBox } } }
    rows[#rows + 1] = { controls = { { widget = importParseButton, width = 100 } } }
    for _, row in ipairs(importNameRows) do
        local visible = IsImportNameRowSelected(row)
        SetVisible(row.label, visible)
        SetVisible(row.input, visible)
        if visible then
            rows[#rows + 1] = { widget = row.input, label = row.label:GetText() }
            row.label:Hide()
        end
    end

    for _, entry in ipairs({
        { importAppearanceCheck, L["导入并启用外观配置"] },
        { importLegacyCheck, L["导入旧版 Author + User（不自动启用）"] },
    }) do
        if IsVisible(entry[1]) then
            rows[#rows + 1] = { widget = entry[1], label = entry[2], presentation = "switch" }
        end
    end
    for _, slot in ipairs(ROLE_ORDER) do
        local check = importRoleChecks and importRoleChecks[slot]
        if IsVisible(check) then
            rows[#rows + 1] = { widget = check, label = L["导入并切换："] .. ROLE_LABELS[slot], presentation = "switch" }
        end
    end
    local actions = { controls = {} }
    if importButton then actions.controls[#actions.controls + 1] = { widget = importButton, width = 116 } end
    if apiImportButton then actions.controls[#actions.controls + 1] = { widget = apiImportButton, width = 220 } end
    rows[#rows + 1] = actions
    EXUI:PrepareSettingsListCard(importSection._settingsCard, { preserveHeader = false })
    importFormSession = _G.ExwindGrid:MountSettingsList(importSection, { sections = { { rows = rows } } })
    importFormSession.card = importSection._settingsCard
    RelayoutImportPresentation()
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
        SetStatus(L["导出系统不可用"], false); return
    end
    local options = {
        name = Trim(exportNameInput and exportNameInput:GetText() or ""),
        appearanceProfileID = IsChecked(exportAppearanceCheck) and exportAppearanceDropdown and exportAppearanceDropdown._value or nil,
        mplus = IsChecked(exportMplusCheck),
        raid = IsChecked(exportRaidCheck),
    }
    local encoded, reason = ie:ExportBundle(options)
    if not encoded then SetStatus(L["导出失败："] .. tostring(reason), false); return end
    SetStatus(L["已导出所选配置"], true)
    exportResultInput:SetText(encoded)
    FocusAndHighlight(exportResultInput)
end

local function ClearImportChoices()
    parsedTransfer = nil
    ClearImportNameRows()
    SetVisible(importAppearanceCheck, false)
    SetVisible(importLegacyCheck, false)
    for _, check in pairs(importRoleChecks or {}) do SetVisible(check, false) end
    LayoutImportControls()
end

local function ShowParsedTransfer(decoded)
    ClearImportChoices()
    parsedTransfer = decoded
    if decoded.kind == "appearance" then
        importAppearanceCheck:SetChecked(true); SetVisible(importAppearanceCheck, true)
    elseif decoded.kind == "legacyBoss" then
        importLegacyCheck:SetChecked(true); SetVisible(importLegacyCheck, true)
    elseif decoded.kind == "bundle" then
        local bundle = decoded.bundle
        if bundle.appearance then
            importAppearanceCheck:SetChecked(true); SetVisible(importAppearanceCheck, true)
        end
        for _, category in ipairs({ "mplus", "raid" }) do
            local scene = bundle.scenes[category]
            if scene then
                for _, slot in ipairs(ROLE_ORDER) do
                    if scene.assignments[slot] then
                        local check = importRoleChecks[slot]
                        check:SetChecked(true); SetVisible(check, true)
                    end
                end
            end
        end
    end
    BuildImportNameRows(decoded)
end

local function ParseImport()
    ClearImportChoices()
    local raw = Trim(importInputBox and importInputBox:GetText() or "")
    if raw == "" then SetStatus(L["请先粘贴导出字符串"], false); return end

    local profiles = Profiles()
    if raw:sub(1, 11) == "!EXBOSSAP1!" then
        local profile, reason = profiles and profiles.DecodeImportString and profiles:DecodeImportString(raw)
        if not profile then SetStatus(L["解析失败："] .. tostring(reason), false); return end
        ShowParsedTransfer({ kind = "appearance", profile = profile })
        SetStatus(L["解析成功：选择后执行导入"], true)
        return
    end

    local ie = IE()
    local decoded, reason = ie and ie.DecodeTransfer and ie:DecodeTransfer(raw)
    if not decoded then SetStatus(L["解析失败："] .. tostring(reason or L["导入系统不可用"]), false); return end
    ShowParsedTransfer(decoded)
    SetStatus(L["解析成功：勾选要导入并启用的内容"], true)
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
    if not parsedTransfer then SetStatus(L["请先点击解析"], false); return end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        SetStatus(L["战斗中不能导入或切换配置"], false); return
    end
    local importNames, nameReason = CollectImportNames()
    if not importNames then SetStatus(nameReason, false); return end

    local changed, imported = false, 0
    if parsedTransfer.kind == "appearance" then
        if IsChecked(importAppearanceCheck) then
            local ok, result = ImportAppearance(parsedTransfer.profile, importNames.appearance)
            if not ok then SetStatus(L["导入失败："] .. tostring(result), false); return end
            changed, imported = result == true, imported + 1
        end
    elseif parsedTransfer.kind == "legacyBoss" then
        if IsChecked(importLegacyCheck) then
            local ie = IE()
            if not ie or type(ie.ImportUserConfigurationPayload) ~= "function" then
                SetStatus(L["导入失败："] .. L["导入系统不可用"], false)
                return
            end
            local ok, result = ie:ImportUserConfigurationPayload({ version = 6, payloadType = "exboss_author_user_values", profile = parsedTransfer.profile }, importNames.legacy)
            if not ok then SetStatus(L["导入失败："] .. tostring(result), false); return end
            imported = imported + 1
        end
    elseif parsedTransfer.kind == "bundle" then
        local bundle = parsedTransfer.bundle
        if bundle.appearance and IsChecked(importAppearanceCheck) then
            local ok, result = ImportAppearance(bundle.appearance, importNames.appearance)
            if not ok then SetStatus(L["导入失败："] .. tostring(result), false); return end
            changed, imported = result == true, imported + 1
        end
        local boss = ExBoss and ExBoss.BossConfig
        for _, category in ipairs({ "mplus", "raid" }) do
            local scene = bundle.scenes[category]
            if scene then
                local selected = SelectedRoles(category, scene.assignments)
                if HasSelectedRole(selected) then
                    if not boss or type(boss.ImportSelectedScene) ~= "function" then
                        SetStatus(L["导入失败："] .. L["Boss 配置系统不可用"], false)
                        return
                    end
                    -- Do not combine this call with `and`: Lua collapses the
                    -- second return value of a call used inside an expression.
                    -- We need the result table to count imported pairs and
                    -- switched role assignments after a successful import.
                    local ok, result = boss:ImportSelectedScene(category, scene.pairs, scene.assignments, selected, importNames.pairs[category])
                    if not ok then SetStatus(L["导入失败："] .. tostring(result), false); return end
                    imported = imported + (tonumber(result.imported) or 0)
                    changed = changed or (tonumber(result.assignments) or 0) > 0
                end
            end
        end
    end

    if imported == 0 then SetStatus(L["没有勾选需要导入的内容"], nil); return end
    if changed then
        if type(ReloadUI) ~= "function" then SetStatus(L["无法重载界面，未完成切换"], false); return end
        ReloadUI()
        return
    end
    SetStatus(L["已导入。旧版字符串不会自动切换配置。"], true)
end

-- This is deliberately separate from the normal import workflow: it calls
-- the public Wago API with the exact string in the box, so it exposes the
-- returned failure reason that a third-party wrapper may otherwise swallow.
local function DoPublicAPIImport()
    local raw = Trim(importInputBox and importInputBox:GetText() or "")
    if raw == "" then SetStatus(L["请先粘贴导出字符串"], false); return end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        SetStatus(L["战斗中不能导入或切换配置"], false); return
    end
    local api = _G.EXBossWagoAPI
    if type(api) ~= "table" or type(api.ImportProfile) ~= "function" then
        SetStatus(L["Wago API 不可用"], false); return
    end
    local ok, result = api:ImportProfile(raw)
    if not ok then
        SetStatus(L["Wago API 导入失败："] .. tostring(result), false)
        return
    end
    if type(result) == "table" and result.reloadRequired == true then
        SetStatus(L["Wago API 导入成功，正在重载界面"], true)
        if type(ReloadUI) == "function" then ReloadUI(); return end
    end
    SetStatus(L["Wago API 导入成功"], true)
end

local function DefaultExportChecks()
    local _, instanceType = GetInstanceInfo()
    if instanceType == "raid" then return false, true end
    return true, false
end

-- [卡片/Grid 迁移边界：导入导出页]
-- 允许：只按共享规范替换导出/导入两块的外观、锚点、宽高与动态高度报告。
-- 导出结果只写本页展示框；格式、生成、解析、导入与职责选择保持原处理链。
-- SectionBg 当前是真实 parent；若换共享卡必须整体承接其 children，不能只把背景当容器声明后遗留子控件。
RelayoutExportPresentation = function()
    if not exportFormSession or not exportSection then return end
    local height = exportFormSession:Relayout(math.max(1, exportSection:GetWidth() or 1))
    exportSection._settingsCard:SetContentHeight(height)
    if scrollChild and importSection and importSection._settingsCard then
        scrollChild:SetHeight(math.max(1, math.max(exportSection._settingsCard:GetHeight(), importSection._settingsCard:GetHeight()) + 80))
    end
end

-- Borrow the ordinary settings-row presentation; original controls keep their
-- parents, values and callbacks. Only the two outer columns own coordinates.
LayoutTransferColumns = function()
    if not (scrollChild and exportSection and importSection) then return end
    local width = math.max(600, scrollChild:GetWidth() or 600)
    local columnWidth = (width - 36) * 0.5
    for index, section in ipairs({ exportSection, importSection }) do
        local card = section._settingsCard
        local heading = card._sectionHeading
        heading:ClearAllPoints()
        heading:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10 + (index - 1) * (columnWidth + 16), -16)
        EXUI:UpdateSettingsSectionLayout(heading, columnWidth)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, 0)
        card:SetWidth(columnWidth)
    end
end

local function EnsureUI(contentFrame)
    if uiBuilt and scrollFrame and scrollFrame:GetParent() == contentFrame then return end
    if exportFormSession then
        exportFormSession:Release()
        exportFormSession = nil
    end
    if importFormSession then
        importFormSession:Release()
        importFormSession = nil
    end
    if scrollFrame then scrollFrame:Hide(); scrollFrame:SetParent(UIParent) end
    scrollFrame = CreateFrame("ScrollFrame", nil, contentFrame, "ScrollFrameTemplate")
    if ExBoss.UI and ExBoss.UI.ApplyModernScrollBarSkin then ExBoss.UI.ApplyModernScrollBarSkin(scrollFrame) end
    scrollFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 4, -4); scrollFrame:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -18, 4)
    scrollChild = CreateFrame("Frame", nil, scrollFrame); scrollFrame:SetScrollChild(scrollChild)
    local width = math.max(600, (contentFrame:GetWidth() or 1100) - 50)
    local columnWidth = (width - 36) * 0.5
    local defaultMplus, defaultRaid = DefaultExportChecks()

    exportSection = SectionBg(scrollChild, L["导出"], THEME.Primary)
    exportSection._settingsCard:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, -16)
    exportSection._settingsCard:SetWidth(columnWidth)
    exportSection:SetHeight(300); exportSection._settingsCard:SetContentHeight(300)
    local y = -42
    local exportNameLabel = MakeLabel(exportSection, L["导出包名称（可选，供接收方识别）"])
    exportNameLabel:SetPoint("TOPLEFT", 14, y); y = y - 20
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
    exportButton:SetSize(170, 28); exportButton:SetPoint("TOPLEFT", 14, y); y = y - 52
    exportResultInput = CreateMultiLineEditBox(exportSection, columnWidth - 48, 240)

    importSection = SectionBg(scrollChild, L["导入"], THEME.Success)
    importSection._settingsCard:SetPoint("TOPLEFT", exportSection._settingsCard, "TOPRIGHT", 16, 0)
    importSection._settingsCard:SetWidth(columnWidth)
    importSection:SetHeight(700); importSection._settingsCard:SetContentHeight(700)
    local iy = -42
    importInputBox = CreateMultiLineEditBox(importSection, columnWidth - 48, 240)
    importInputBox:SetPoint("TOPLEFT", 14, iy); iy = iy - 252
    importParseButton = CreateActionButton(importSection, L["解析"], ParseImport)
    importParseButton:SetSize(100, 28); importParseButton:SetPoint("TOPLEFT", 14, iy); iy = iy - 46
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
    importButton = CreateActionButton(importSection, L["执行导入"], DoImport)
    importButton:SetSize(140, 28); importButton:SetPoint("BOTTOMLEFT", 14, 46)
    apiImportButton = CreateActionButton(importSection, L["测试：通过 Wago API 导入"], DoPublicAPIImport)
    apiImportButton:SetSize(220, 28); apiImportButton:SetPoint("BOTTOMLEFT", 164, 46)

    scrollChild:SetSize(width, math.max(exportSection._settingsCard:GetHeight(), importSection._settingsCard:GetHeight()) + 80)
    LayoutTransferColumns()
    EXUI:PrepareSettingsListCard(exportSection._settingsCard, { preserveHeader = false })
    exportNameLabel:Hide()
    exportFormSession = _G.ExwindGrid:MountSettingsList(exportSection, {
        sections = { { rows = {
            { widget = exportNameInput, label = exportNameLabel:GetText() },
            { widget = exportAppearanceCheck, label = L["是否导出外观配置"], presentation = "switch" },
            { widget = exportAppearanceDropdown, label = L["选择外观配置"] },
            { widget = exportMplusCheck, label = L["是否导出大秘境配置"], presentation = "switch" },
            { widget = exportRaidCheck, label = L["是否导出团本配置"], presentation = "switch" },
            { controls = { { widget = exportButton, width = 170 } } },
            -- The shared action row supplies the single divider above this result.
            { controls = { { widget = exportResultInput } } },
        } } },
    })
    exportFormSession.card = exportSection._settingsCard
    RelayoutExportPresentation()
    uiBuilt = true
    RefreshAppearanceDropdown()
    ClearImportChoices()
end

function Page:Render(contentFrame)
    EnsureUI(contentFrame)
    scrollFrame:SetParent(contentFrame); scrollFrame:ClearAllPoints(); scrollFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 4, -4); scrollFrame:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -18, 4)
    scrollChild:SetWidth(math.max(600, (contentFrame:GetWidth() or 1100) - 50))
    LayoutTransferColumns()
    RelayoutExportPresentation()
    RelayoutImportPresentation()
    scrollFrame:Show()
    RefreshAppearanceDropdown()
end

function Page:Hide()
    if scrollFrame then scrollFrame:Hide() end
end
