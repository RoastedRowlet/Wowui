---@diagnostic disable: undefined-global, undefined-field
-- One transfer page, two columns.  Export choice is intentionally small;
-- imports expose only the included appearance and role assignments.

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI

ExBoss.UI.Panel.ImportExportPage = ExBoss.UI.Panel.ImportExportPage or {}
local Page = ExBoss.UI.Panel.ImportExportPage
local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, key) return key end })

local MODULE_KEY = "ExBoss.ImportExport"
local ROLE_LABELS = {
    mplus_tank = L["大秘境坦克"], mplus_heal = L["大秘境治疗"], mplus_dps = L["大秘境 DPS"],
    raid_tank = L["团本坦克"], raid_heal = L["团本治疗"], raid_dps = L["团本 DPS"],
}
local ROLE_ORDER = { "mplus_tank", "mplus_heal", "mplus_dps", "raid_tank", "raid_heal", "raid_dps" }

local scrollFrame, scrollChild, pageSession
local exportNameInput, exportAppearanceCheck, exportAppearanceDropdown, exportMplusCheck, exportRaidCheck, exportResultInput
local importInputBox, importAppearanceCheck, importLegacyCheck
local importRoleChecks, parsedTransfer
local importNameRows = {}
local transferState = { exportName = "", exportAppearance = true, exportAppearanceProfile = "", exportResult = "", importText = "" }
local importAvailable = {}
local RefreshPage

local function Trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

-- Import/export fields must use the shared EXUI factory.  Apart from visual
-- consistency, that factory also owns focus, placeholder, scroll, and pool
-- lifecycle behaviour.  This page used to create bare black EditBoxes.
local function GetNativeEditBox(control)
    return control and (control.editBox or control.EditBox or control) or nil
end

local function FocusAndHighlight(control)
    local edit = GetNativeEditBox(control)
    if edit and edit.SetFocus then
        edit:SetFocus()
        if edit.HighlightText then edit:HighlightText() end
    end
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

local function ClearImportNameRows()
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
    local row = {
        kind = kind,
        title = title,
        data = data or {},
    }
    row.name = Trim(row.data.suggestedName)
    importNameRows[#importNameRows + 1] = row
end

local function IsImportNameRowSelected(row)
    if row.kind == "appearance" then return transferState.importAppearance == true end
    if row.kind == "legacy" then return transferState.importLegacy == true end
    if row.kind ~= "pair" then return false end
    local assignments = row.data.assignments or {}
    for _, slot in ipairs(ROLE_ORDER) do
        if tostring(assignments[slot] or "") == tostring(row.data.pairID)
            and transferState[slot] == true then
            return true
        end
    end
    return false
end

local function RefreshImportNameRows()
    if RefreshPage then RefreshPage() end
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
    transferState.exportAppearanceProfile = selected
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
    transferState.exportResult = encoded
    exportResultInput:SetText(encoded)
    FocusAndHighlight(exportResultInput)
end

local function ClearImportChoices()
    parsedTransfer = nil
    ClearImportNameRows()
    importAvailable = {}
    RefreshImportNameRows()
end

local function ShowParsedTransfer(decoded)
    ClearImportChoices()
    parsedTransfer = decoded
    if decoded.kind == "appearance" then
        transferState.importAppearance, importAvailable.importAppearance = true, true
    elseif decoded.kind == "legacyBoss" then
        transferState.importLegacy, importAvailable.importLegacy = true, true
    elseif decoded.kind == "bundle" then
        local bundle = decoded.bundle
        if bundle.appearance then
            transferState.importAppearance, importAvailable.importAppearance = true, true
        end
        for _, category in ipairs({ "mplus", "raid" }) do
            local scene = bundle.scenes[category]
            if scene then
                for _, slot in ipairs(ROLE_ORDER) do
                    if scene.assignments[slot] then
                        transferState[slot], importAvailable[slot] = true, true
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

local importChildren = {
    { id = "importText", kind = "control", controlType = "multiline", ref = "importText" },
    { id = "parse", kind = "setting", label = L["解析"], children = {
        { id = "parseButton", kind = "button", text = L["解析"], action = "parse" },
    } },
    { id = "importNames", kind = "repeat", source = "importNames", template = {
        id = "importName", kind = "control", controlType = "input", ref = "importName", visible = "nameSelected",
    } },
    { id = "importAppearance", kind = "control", controlType = "switch", ref = "importAppearance", visible = "importAppearance" },
    { id = "importLegacy", kind = "control", controlType = "switch", ref = "importLegacy", visible = "importLegacy" },
}
for _, slot in ipairs(ROLE_ORDER) do
    importChildren[#importChildren + 1] = {
        id = slot, kind = "control", controlType = "switch", ref = slot, visible = slot,
    }
end
importChildren[#importChildren + 1] = { id = "importActions", kind = "setting", label = L["导入"], children = {
    { id = "importButton", kind = "button", text = L["执行导入"], action = "import" },
    { id = "apiImportButton", kind = "button", text = L["测试：通过 Wago API 导入"], action = "apiImport" },
} }

local LAYOUT = {
    version = 2, layout = "grid",
    columns = { { weight = 1 }, { weight = 1 } },
    cards = {
        { id = "export", kind = "card", title = L["导出"], row = 1, column = 1,
            children = {
                { id = "exportName", kind = "control", controlType = "input", ref = "exportName" },
                { id = "exportAppearance", kind = "control", controlType = "switch", ref = "exportAppearance" },
                { id = "exportAppearanceProfile", kind = "control", controlType = "select", ref = "exportAppearanceProfile" },
                { id = "exportMplus", kind = "control", controlType = "switch", ref = "exportMplus" },
                { id = "exportRaid", kind = "control", controlType = "switch", ref = "exportRaid" },
                { id = "exportAction", kind = "setting", label = L["导出"], children = {
                    { id = "exportButton", kind = "button", text = L["生成导出字符串"], action = "export" },
                } },
                { id = "exportResult", kind = "control", controlType = "multiline", ref = "exportResult" },
            } },
        { id = "import", kind = "card", title = L["导入"], row = 1, column = 2,
            children = importChildren },
    },
}

-- These controls edit transfer choices, not saved module configuration. Reuse
-- the standard binding/control presentation with silent, page-local writes.
local function TransferBinding(root, key)
    local binding = EXUI:CreateSettingsV2Binding(MODULE_KEY, root, key)
    local write = binding.Write
    function binding:Write(value)
        return write(self, value, "silent")
    end
    return binding
end

local function RememberInput(widget, context, binding)
    local edit = GetNativeEditBox(widget)
    edit:HookScript("OnTextChanged", function(self, userInput)
        if userInput and context:IsCurrent() then binding:Write(self:GetText()) end
    end)
end

local function TransferControl(key, controlType, label)
    local binding = TransferBinding(transferState, key)
    local adapter = EXUI:CreateSettingsV2Control({
        controlType = controlType, label = label, options = controlType == "select" and {} or nil,
        size = controlType == "multiline" and "tall" or nil,
    }, function() return binding end)
    local mount, update, release = adapter.mount, adapter.update, adapter.release
    function adapter.mount(host, context)
        local widget = mount(host, context)
        if controlType == "input" then
            RememberInput(widget, context, binding)
        end
        if key == "exportAppearanceProfile" then
            exportAppearanceDropdown = widget
            RefreshAppearanceDropdown(binding:Read())
        end
        return widget
    end
    function adapter.update(widget, context)
        if key == "exportAppearanceProfile" then
            RefreshAppearanceDropdown(binding:Read())
            return
        end
        update(widget, context)
    end
    function adapter.release(widget, context)
        if key == "exportAppearanceProfile" then exportAppearanceDropdown = nil end
        release(widget, context)
    end
    return adapter
end

local function ImportNameControl()
    local adapters = {}
    local standard = EXUI:CreateSettingsV2Control({ controlType = "input" }, function(context)
        return TransferBinding(context.scope.item, "name")
    end)
    local methods = {
        mount = function(host, context)
            local row = context.scope.item
            local binding = TransferBinding(row, "name")
            local adapter = EXUI:CreateSettingsV2Control({
                controlType = "input", label = row.title .. " " .. L["名称（必填）"],
            }, function() return binding end)
            local widget = adapter.mount(host, context)
            RememberInput(widget, context, binding)
            row.input = widget
            adapters[widget] = adapter
            return widget
        end,
        update = function(widget, context) adapters[widget].update(widget, context) end,
        measure = function(widget, context, width) return adapters[widget].measure(widget, context, width) end,
        layout = function(widget, context, width, height) adapters[widget].layout(widget, context, width, height) end,
        setEnabled = function(widget, context, enabled) adapters[widget].setEnabled(widget, context, enabled) end,
        setVisible = function(widget, context, visible) adapters[widget].setVisible(widget, context, visible) end,
        release = function(widget, context)
            context.scope.item.input = nil
            adapters[widget].release(widget, context)
            adapters[widget] = nil
        end,
    }
    for key, method in pairs(methods) do standard[key] = method end
    return standard
end

local function CreateTransferOwner()
    local owner = {
        binding = { moduleKey = MODULE_KEY, config = transferState },
        controls = {
            exportName = TransferControl("exportName", "input", L["导出包名称（可选，供接收方识别）"]),
            exportAppearance = TransferControl("exportAppearance", "switch", L["是否导出外观配置"]),
            exportAppearanceProfile = TransferControl("exportAppearanceProfile", "select", L["选择外观配置"]),
            exportMplus = TransferControl("exportMplus", "switch", L["是否导出大秘境配置"]),
            exportRaid = TransferControl("exportRaid", "switch", L["是否导出团本配置"]),
            exportResult = TransferControl("exportResult", "multiline", L["生成导出字符串"]),
            importText = TransferControl("importText", "multiline", L["请先粘贴导出字符串"]),
            importName = ImportNameControl(),
            importAppearance = TransferControl("importAppearance", "switch", L["导入并启用外观配置"]),
            importLegacy = TransferControl("importLegacy", "switch", L["导入旧版 Author + User（不自动启用）"]),
        },
        predicates = { nameSelected = function(scope) return IsImportNameRowSelected(scope.item) end },
        sources = { importNames = function() return importNameRows end },
        actions = { export = ExportBundle, parse = ParseImport, import = DoImport, apiImport = DoPublicAPIImport },
        onHeightChanged = function(height) scrollChild:SetHeight(math.max(1, height)) end,
    }
    for _, key in ipairs({ "importAppearance", "importLegacy" }) do
        owner.predicates[key] = function() return importAvailable[key] == true end
    end
    for _, slot in ipairs(ROLE_ORDER) do
        owner.controls[slot] = TransferControl(slot, "switch", L["导入并切换："] .. ROLE_LABELS[slot])
        owner.predicates[slot] = function() return importAvailable[slot] == true end
    end
    return owner
end

local function FindControl(id)
    local modulePage = EXUI:GetModulePage(MODULE_KEY, scrollChild)
    return modulePage and modulePage:Find(id)
end

local function CaptureControls()
    exportNameInput = FindControl("exportName")
    exportAppearanceCheck = FindControl("exportAppearance")
    exportAppearanceDropdown = FindControl("exportAppearanceProfile")
    exportMplusCheck, exportRaidCheck = FindControl("exportMplus"), FindControl("exportRaid")
    exportResultInput, importInputBox = FindControl("exportResult"), FindControl("importText")
    importAppearanceCheck, importLegacyCheck = FindControl("importAppearance"), FindControl("importLegacy")
    importRoleChecks = {}
    for _, slot in ipairs(ROLE_ORDER) do importRoleChecks[slot] = FindControl(slot) end
end

RefreshPage = function()
    if pageSession and pageSession.alive then pageSession:Refresh() end
end

local function ReleasePage()
    if pageSession then
        pageSession:Release()
        pageSession = nil
    end
    if scrollChild then
        scrollChild._exV2Session, scrollChild._exV2Owner = nil, nil
        if EXUI.ActivePageFrame == scrollChild then
            EXUI.ActivePageFrame = nil
            if EXUI.CurrentModule == MODULE_KEY then EXUI.CurrentModule = nil end
        end
    end
    if EXUI.ActivePageScrollFrame == scrollFrame then EXUI.ActivePageScrollFrame = nil end
    exportNameInput, exportAppearanceCheck, exportAppearanceDropdown, exportMplusCheck, exportRaidCheck, exportResultInput = nil, nil, nil, nil, nil, nil
    importInputBox, importAppearanceCheck, importLegacyCheck, importRoleChecks = nil, nil, nil, nil
end

local function SyncWidth()
    if not scrollFrame or not scrollChild then return end
    scrollChild:SetWidth(scrollFrame:GetWidth())
    if pageSession then pageSession:Invalidate() end
end

function Page:Render(contentFrame)
    if not contentFrame then return end
    if not scrollFrame then
        scrollFrame = EXUI:CreateScrollFrame(contentFrame)
        scrollFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT")
        scrollFrame:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT")
        scrollChild = CreateFrame("Frame", nil, scrollFrame)
        scrollChild:SetPoint("TOPLEFT")
        scrollChild:SetHeight(1)
        scrollFrame:SetScrollChild(scrollChild)
        scrollFrame:HookScript("OnHide", ReleasePage)
        scrollFrame:HookScript("OnSizeChanged", SyncWidth)
    end
    scrollFrame:SetParent(contentFrame)
    scrollFrame:ClearAllPoints()
    scrollFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT")
    scrollFrame:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT")
    SyncWidth()
    scrollFrame:Show()
    scrollChild:Show()
    if not pageSession then
        if transferState.exportMplus == nil then
            transferState.exportMplus, transferState.exportRaid = DefaultExportChecks()
        end
        local owner = CreateTransferOwner()
        pageSession = EXUI:MountSettingsDeclarationV2(scrollChild, LAYOUT, owner)
        scrollChild._exV2Session, scrollChild._exV2Owner = pageSession, owner
        CaptureControls()
    end
    EXUI.ActivePageFrame, EXUI.ActivePageScrollFrame, EXUI.CurrentModule = scrollChild, scrollFrame, MODULE_KEY
    RefreshAppearanceDropdown()
    RefreshPage()
end

function Page:Hide()
    ReleasePage()
    if scrollFrame then scrollFrame:Hide() end
end
