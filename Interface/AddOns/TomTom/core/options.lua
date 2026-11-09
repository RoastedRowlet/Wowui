--[[--------------------------------------------------------------------------
--  TomTom by Cladhaire <cladhaire@gmail.com>
--
--  All Rights Reserved
----------------------------------------------------------------------------]]

-- The settings builder. Files describe their settings as data with
-- AddSettingsSection; this file builds the Blizzard settings pages from it.
-- See docs/archive/settings-proposal.md. The TOC loads this file before the files
-- that add sections.
--
-- A section:
--   page        page id; "main" is the TomTom page
--   pageName    name of the page (one section of the page gives it)
--   pageOrder   order of the page among the TomTom pages
--   order       order of the section on its page
--   settingsKey options namespace of the rows
--   available   optional function; false leaves the section out
--   header      optional name of a section header. It comes before all rows
--               of the section, also before the feature row.
--   feature     optional {name, tooltip, path}: the enable setting. It is
--               the first row of the section and a row in the Features list
--               on the TomTom page. The other rows grey out while it is off.
--               path defaults to settingsKey .. ".enable".
--   suppress    optional feature name (core/suppress.lua). While another
--               addon suppresses it, the setting rows grey out and a line
--               "Controlled by <owner>" shows after the feature row.
--   rows        list of rows, in order
--
-- A row has a type: header, text, preview, toggle, range, select, color or
-- execute. Setting rows use key (in settingsKey) or path ("ns.key"), name,
-- tooltip, and optional enabledWhen(profile) and suppress (as for a section,
-- with the line after the row). A row can give get, set, default and
-- variable instead of a path. See the builders below.

local _, addon = ...
local TomTom = addon
local L = addon.L
addon.private = addon.private or {}
local private = addon.private

local sections = {}
local settingsByVariable = {}
local mainCategory

-- The settings names must be unique in the whole game.
local function VariableName(namespace, key)
    -- One return value only: gsub also returns the count.
    local variable = ("TOMTOM_%s_%s"):format(namespace, key):upper():gsub("[^%w_]", "_")
    return variable
end

local function SplitPath(section, row)
    if row.path then
        return row.path:match("^([^.]+)%.(.+)$")
    end
    return section.settingsKey, row.key
end

local function CopyValue(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for k, v in pairs(value) do
        copy[k] = CopyValue(v)
    end
    return copy
end

local function DefaultValue(namespace, key)
    local defaults = TomTom.defaults and TomTom.defaults.profile[namespace]
    return defaults and defaults[key]
end

function private.AddSettingsSection(section)
    assert(type(section.page) == "string" and type(section.rows) == "table", "AddSettingsSection: page and rows")
    table.insert(sections, section)
end

--[[--------------------------------------------------------------------------
--  Settings objects
----------------------------------------------------------------------------]]

local VAR_TYPES = {
    toggle = "Boolean",
    range = "Number",
    color = "String",
}

-- Returns the setting object for a setting row.
local function CreateRowSetting(category, section, row)
    local namespace, key = SplitPath(section, row)
    local variable = row.variable or VariableName(namespace, key)
    assert(not settingsByVariable[variable], "Two settings rows for " .. variable)

    local get, set, default
    if row.get then
        get, set, default = row.get, row.set, row.default
    elseif row.type == "color" then
        get = function()
            return private.ColorToHex(TomTom.db.profile[namespace][key])
        end
        set = function(value)
            local color = private.HexToColor(value)
            -- A color without opacity keeps its saved shape {r, g, b}.
            if not row.opacity then
                color[4] = nil
            end
            private.SetSetting(namespace, key, color)
        end
        default = private.ColorToHex(DefaultValue(namespace, key))
    else
        get = function()
            return TomTom.db.profile[namespace][key]
        end
        set = function(value)
            private.SetSetting(namespace, key, value)
        end
        default = DefaultValue(namespace, key)
    end

    local varType = VAR_TYPES[row.type]
    if row.type == "select" then
        varType = type(default) == "number" and "Number" or "String"
    end

    local setting = private.CreateUnregisteredSetting(category, variable, Settings.VarType[varType],
        row.name, default, get, set)
    settingsByVariable[variable] = setting
    return setting, namespace, key
end

function private.RefreshSettingsRow(namespace, key)
    local setting = settingsByVariable[VariableName(namespace, key)]
    if setting then
        setting:NotifyUpdate()
    end
end

local function RefreshAllRows()
    for _, setting in pairs(settingsByVariable) do
        setting:NotifyUpdate()
    end
end

TomTom:RegisterMessage("TOMTOM_PROFILE_CHANGED", RefreshAllRows)

-- NotifyUpdate sets the row values only. The enabled state of a row with no
-- parent row, the shown predicates and the "Controlled by" text change only
-- when the page shows again, so an open TomTom page shows again. In combat
-- it waits until the combat ends, to keep the settings panel free of taint.
local redisplayQueued

local function RedisplayOpenPage()
    redisplayQueued = false
    local panel = SettingsPanel
    if not (mainCategory and panel and panel:IsShown() and panel.GetCurrentCategory) then
        return
    end
    local category = panel:GetCurrentCategory()
    if category and (category == mainCategory or category:GetParentCategory() == mainCategory) then
        panel:SelectCategory(category, true)
    end
end

TomTom:RegisterMessage("TOMTOM_FEATURE_SUPPRESSION_CHANGED", function()
    RefreshAllRows()
    if not redisplayQueued then
        redisplayQueued = true
        TomTom:Defer(RedisplayOpenPage)
    end
end)

--[[--------------------------------------------------------------------------
--  Rows
----------------------------------------------------------------------------]]

local function AddInitializer(category, initializer)
    Settings.RegisterInitializer(category, initializer)
    return initializer
end

local function CreateSliderFormatter(row)
    if type(row.format) == "function" then
        return row.format
    end
    local fmt = row.format or (row.step and row.step < 1 and "%.2f" or "%d")
    return function(value)
        return fmt:format(value)
    end
end

local function SelectOptions(row)
    return function()
        local values = type(row.values) == "function" and row.values() or row.values
        local container = Settings.CreateControlTextContainer()
        local order = row.sorting
        if not order then
            order = {}
            for value in pairs(values) do
                table.insert(order, value)
            end
            table.sort(order, function(a, b) return tostring(values[a]) < tostring(values[b]) end)
        end
        for _, value in ipairs(order) do
            if values[value] then
                container:Add(value, values[value])
            end
        end
        return container:GetData()
    end
end

local rowBuilders = {}

function rowBuilders.header(category, _, row)
    return AddInitializer(category, CreateSettingsListSectionHeaderInitializer(row.name, row.tooltip))
end

function rowBuilders.text(category, _, row)
    return AddInitializer(category, private.CreateTextInitializer({
        text = row.text, textFunc = row.textFunc, image = row.image, imageFunc = row.imageFunc,
    }))
end

-- A text row that refreshes when other settings change, for example a theme
-- preview. watch is a list of keys in settingsKey, or "ns.key" paths.
function rowBuilders.preview(category, section, row)
    local variables = {}
    for _, watched in ipairs(row.watch or {}) do
        local namespace, key = watched:match("^([^.]+)%.(.+)$")
        table.insert(variables, VariableName(namespace or section.settingsKey, key or watched))
    end
    return AddInitializer(category, private.CreateTextInitializer({
        textFunc = row.textFunc, imageFunc = row.imageFunc, watchVariables = variables,
    }))
end

function rowBuilders.toggle(category, section, row)
    local setting = CreateRowSetting(category, section, row)
    return AddInitializer(category, Settings.CreateCheckboxInitializer(setting, nil, row.tooltip)), setting
end

function rowBuilders.range(category, section, row)
    local setting = CreateRowSetting(category, section, row)
    local options = Settings.CreateSliderOptions(row.min, row.max, row.step)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, CreateSliderFormatter(row))
    return AddInitializer(category, Settings.CreateSliderInitializer(setting, options, row.tooltip)), setting
end

function rowBuilders.select(category, section, row)
    local setting = CreateRowSetting(category, section, row)
    return AddInitializer(category, Settings.CreateDropdownInitializer(setting, SelectOptions(row), row.tooltip)), setting
end

function rowBuilders.color(category, section, row)
    local setting = CreateRowSetting(category, section, row)
    return AddInitializer(category, private.CreateColorInitializer(setting, row.tooltip, row.opacity)), setting
end

function rowBuilders.execute(category, _, row)
    return AddInitializer(category, CreateSettingsButtonInitializer(row.name, row.buttonText or row.name,
        row.func, row.tooltip, true))
end

local function NotSuppressed(feature)
    return function()
        return not private.IsFeatureSuppressed(feature)
    end
end

-- Shown only while another addon suppresses the feature.
local function AddControlledRow(category, feature)
    local initializer = AddInitializer(category, private.CreateTextInitializer({
        textFunc = function()
            return L["Controlled by %s"]:format(private.FeatureOwnersText(feature))
        end,
    }))
    initializer:AddShownPredicate(function()
        return private.IsFeatureSuppressed(feature)
    end)
end

local function BuildRow(category, section, row, parentInitializer, parentSetting)
    local builder = rowBuilders[row.type]
    assert(builder, "Unknown settings row type: " .. tostring(row.type))
    local initializer, setting = builder(category, section, row)

    local suppress = row.suppress or section.suppress
    if suppress and setting then
        initializer:AddModifyPredicate(NotSuppressed(suppress))
    end
    if row.suppress then
        AddControlledRow(category, row.suppress)
    end

    if parentInitializer then
        initializer:SetParentInitializer(parentInitializer, function()
            return parentSetting:GetValue()
        end)
    end
    if row.enabledWhen then
        initializer:AddModifyPredicate(function()
            return row.enabledWhen(TomTom.db.profile)
        end)
    end
    return initializer, setting
end

--[[--------------------------------------------------------------------------
--  Pages
----------------------------------------------------------------------------]]

local function IsAvailable(section)
    return not section.available or section.available()
end

local function SortedSections()
    local list = {}
    for _, section in ipairs(sections) do
        if IsAvailable(section) then
            table.insert(list, section)
        end
    end
    table.sort(list, function(a, b) return (a.order or 0) < (b.order or 0) end)
    return list
end

-- Groups the sections by page, in page order. The main page comes first.
local function CollectPages()
    local pages, byId = {}, {}
    for _, section in ipairs(SortedSections()) do
        local page = byId[section.page]
        if not page then
            page = {id = section.page, sections = {}, order = section.pageOrder or 100}
            byId[section.page] = page
            table.insert(pages, page)
        end
        page.name = page.name or section.pageName
        page.order = section.pageOrder or page.order
        table.insert(page.sections, section)
    end
    table.sort(pages, function(a, b) return a.order < b.order end)
    return pages, byId
end

StaticPopupDialogs["TOMTOM_RESET_SETTINGS_PAGE"] = {
    preferredIndex = STATICPOPUPS_NUMDIALOGS,
    text = L["Reset all settings on this page to their defaults?"],
    button1 = L["Yes"],
    button2 = L["No"],
    OnAccept = function(_, data)
        data()
    end,
    timeout = 30,
    whileDead = 1,
    hideOnEscape = 1,
}

local function ResetPage(page)
    local done = {}
    for _, section in ipairs(page.sections) do
        local namespace = section.settingsKey
        if namespace and not done[namespace] then
            done[namespace] = true
            for key, value in pairs(TomTom.defaults.profile[namespace] or {}) do
                private.SetSetting(namespace, key, CopyValue(value))
            end
        end
    end
    RefreshAllRows()
end

local function AddResetButton(category, page)
    AddInitializer(category, CreateSettingsButtonInitializer(L["Reset to defaults"], L["Reset to defaults"],
        function()
            StaticPopup_Show("TOMTOM_RESET_SETTINGS_PAGE", nil, nil, function() ResetPage(page) end)
        end, page.id == "main"
            and L["Reset the general options on this page. The Features list and the other pages do not change."]
            or L["Reset the settings on this page. Other pages and the waypoints do not change."], true))
end

local function FeatureRow(section)
    local feature = section.feature
    return {type = "toggle", name = feature.name, tooltip = feature.tooltip,
        path = feature.path or (section.settingsKey .. ".enable")}
end

-- Builds the rows of a page. Returns the feature rows for the Features list.
-- On the TomTom page the enable row is the Features list row, so
-- listRows[section] gives it.
local function BuildPage(category, page, listRows)
    local features = {}
    -- One "Controlled by" row for each feature on a page.
    local controlled = {}
    for _, section in ipairs(page.sections) do
        if section.header then
            BuildRow(category, section, {type = "header", name = section.header})
        end
        local enableInitializer, enableSetting
        if listRows and listRows[section] then
            enableInitializer = listRows[section]
            enableSetting = enableInitializer:GetSetting()
        elseif section.feature then
            enableInitializer, enableSetting = BuildRow(category, section, FeatureRow(section))
            table.insert(features, {tooltip = section.feature.tooltip, setting = enableSetting, section = section})
        end
        if section.suppress and not controlled[section.suppress] then
            controlled[section.suppress] = true
            AddControlledRow(category, section.suppress)
        end
        for _, row in ipairs(section.rows) do
            BuildRow(category, section, row, enableInitializer, enableSetting)
        end
    end
    return features
end

local function AddAbout(category)
    AddInitializer(category, CreateSettingsListSectionHeaderInitializer(L["About"]))
    AddInitializer(category, private.CreateTextInitializer({
        image = {texture = "Interface\\AddOns\\TomTom\\Images\\Modern\\TomTom-Logo.tga", width = 64, height = 64},
        textFunc = function()
            return table.concat({
                "|cffffd200" .. L["Version:"] .. "|r TomTom-" .. tostring(TomTom.version),
                "|cffffd200" .. L["Author:"] .. "|r Cladhaire",
                "|cffffd200" .. L["Co-maintainer:"] .. "|r Ludovicus",
                "|cffffd200" .. L["Contributors:"] .. "|r Carl Thomas, Chris Braithwaite (modern artwork)",
                L["Localization by many helpers"],
            }, "\n")
        end,
    }))
end

-- Builds all TomTom settings pages. Call it once, at login.
function private.BuildSettings()
    assert(not mainCategory, "BuildSettings runs only once")
    local pages, byId = CollectPages()

    local category, layout = Settings.RegisterVerticalLayoutCategory("TomTom")
    mainCategory = category

    local allFeatures = {}
    local subcategories = {}
    for _, page in ipairs(pages) do
        if page.id ~= "main" then
            local subcategory = Settings.RegisterVerticalLayoutSubcategory(category, page.name)
            for _, feature in ipairs(BuildPage(subcategory, page)) do
                table.insert(allFeatures, feature)
            end
            AddResetButton(subcategory, page)
            subcategories[page.id] = subcategory
        end
    end

    if private.BuildProfilesPage then
        subcategories.profiles = private.BuildProfilesPage(category)
    end

    -- A feature with no page of its own (for example the corpse waypoint)
    -- has its only enable row in the Features list.
    local listRows = {}
    local mainFeatures = {}
    for _, section in ipairs(byId.main and byId.main.sections or {}) do
        if section.feature then
            local setting = CreateRowSetting(category, section, FeatureRow(section))
            table.insert(mainFeatures, {tooltip = section.feature.tooltip, setting = setting, section = section})
        end
    end

    if #allFeatures + #mainFeatures > 0 then
        AddInitializer(category, CreateSettingsListSectionHeaderInitializer(L["Features"]))
        for _, feature in ipairs(allFeatures) do
            -- The same setting object as the row on the feature's own page
            -- (SD1). Search lists the feature on its own page only (SD11).
            local initializer = Settings.CreateCheckboxInitializer(feature.setting, nil, feature.tooltip)
            initializer:SetSearchIgnoredInLayout(layout)
            if feature.section.suppress then
                initializer:AddModifyPredicate(NotSuppressed(feature.section.suppress))
            end
            AddInitializer(category, initializer)
        end
        for _, feature in ipairs(mainFeatures) do
            local initializer = Settings.CreateCheckboxInitializer(feature.setting, nil, feature.tooltip)
            if feature.section.suppress then
                initializer:AddModifyPredicate(NotSuppressed(feature.section.suppress))
            end
            AddInitializer(category, initializer)
            listRows[feature.section] = initializer
        end
    end

    if byId.main then
        BuildPage(category, byId.main, listRows)
        AddResetButton(category, byId.main)
    end
    AddAbout(category)

    Settings.RegisterAddOnCategory(category)
    return category, subcategories
end

function private.OpenSettings()
    if mainCategory then
        Settings.OpenToCategory(mainCategory:GetID())
    end
end
