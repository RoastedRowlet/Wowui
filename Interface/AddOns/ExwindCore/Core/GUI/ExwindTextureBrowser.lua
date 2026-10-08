-- Session-only browser/picker for ExwindCore/Textures.
-- Selection is submitted only by the caller's guarded owner callback.

local ExwindTools = _G.ExwindTools
local VirtualList = _G.ExwindVirtualList
if not ExwindTools or not ExwindTools.UI or not VirtualList then return end

local EXUI = ExwindTools.UI
local Catalog = ExwindTools.TextureCatalog
if type(Catalog) ~= "table" or type(Catalog.assets) ~= "table" then return end

local WINDOW_WIDTH, WINDOW_HEIGHT = 1120, 760
local GRID_COLUMNS = 10
local GRID_ROW_HEIGHT = 82
local CELL_WIDTH, CELL_HEIGHT, CELL_GAP = 100, 74, 4
local THUMBNAIL_SIZE = 44
local ALL_CATEGORIES = "__all"

local window
local gridList
local pathInput
local selectedName
local selectedMeta
local countText
local selectedAsset
local picker, selectPathButton
local selectedCategory = ALL_CATEGORIES
local searchText = ""
local filteredAssets = {}
local gridRows = {}

local SelectAsset

local function NormalizeSearch(value)
    value = tostring(value or "")
    value = string.match(value, "^%s*(.-)%s*$") or value
    return string.lower(value)
end

local function AssetMatches(asset)
    if selectedCategory ~= ALL_CATEGORIES and asset.category ~= selectedCategory then
        return false
    end
    if searchText == "" then return true end
    local haystack = strlower(table.concat({
        tostring(asset.name or ""),
        tostring(asset.relativePath or ""),
        tostring(asset.category or ""),
        tostring(asset.path or ""),
    }, "\n"))
    return string.find(haystack, searchText, 1, true) ~= nil
end

local function UpdateSelection(asset)
    selectedAsset = asset
    if selectPathButton then selectPathButton:SetEnabled(asset ~= nil) end
    if not selectedName then return end

    if not asset then
        selectedName:SetText("没有匹配的材质")
        selectedMeta:SetText("请切换上方分类或修改搜索条件。")
        pathInput:SetText("")
        return
    end

    selectedName:SetText(asset.name or "")
    selectedMeta:SetText(string.format("%s  ·  %s",
        tostring(asset.category or ""), tostring(asset.extension or "")))
    pathInput:SetText(asset.path or "")
    pathInput:SetCursorPosition(0)
end

local function BuildGridRows()
    wipe(gridRows)
    local row
    for index, asset in ipairs(filteredAssets) do
        local column = ((index - 1) % GRID_COLUMNS) + 1
        if column == 1 then
            row = {}
            gridRows[#gridRows + 1] = row
        end
        row[column] = asset
    end
end

local function RefreshGrid()
    if not gridList then return end
    wipe(filteredAssets)
    for _, asset in ipairs(Catalog.assets) do
        if AssetMatches(asset) then
            filteredAssets[#filteredAssets + 1] = asset
        end
    end
    BuildGridRows()
    countText:SetText(string.format("显示 %d / %d · 每行 %d 个",
        #filteredAssets, tonumber(Catalog.count) or #Catalog.assets, GRID_COLUMNS))
    gridList:SetData(gridRows)

    local keepSelection = false
    if selectedAsset then
        for _, asset in ipairs(filteredAssets) do
            if asset == selectedAsset then
                keepSelection = true
                break
            end
        end
    end
    if not keepSelection then
        SelectAsset(filteredAssets[1])
    else
        gridList:Refresh()
        UpdateSelection(selectedAsset)
    end
end

SelectAsset = function(asset)
    UpdateSelection(asset)
    if gridList then gridList:Refresh() end
end

local function CreateGridRow(owner)
    local row = CreateFrame("Frame", nil, owner)
    row.cells = {}

    for column = 1, GRID_COLUMNS do
        local cell = EXUI:CreateButton(row, CELL_WIDTH, CELL_HEIGHT, "", function(self)
            if self._textureAsset then SelectAsset(self._textureAsset) end
        end, { compact = true, variant = "soft" })
        cell:SetPoint("TOPLEFT", row, "TOPLEFT", (column - 1) * (CELL_WIDTH + CELL_GAP), -4)
        cell:SetSize(CELL_WIDTH, CELL_HEIGHT)

        cell.thumbnail = EXUI:CreateVisualTexture(cell, EXBASEFRAME)
        cell.thumbnail:SetPoint("TOP", cell, "TOP", 0, -6)
        cell.thumbnail:SetSize(THUMBNAIL_SIZE, THUMBNAIL_SIZE)

        cell.selectionLine = EXUI:CreateVisualTexture(cell, EXBORDERFRAME)
        cell.selectionLine:SetPoint("TOPLEFT", cell, "TOPLEFT", 4, -3)
        cell.selectionLine:SetPoint("TOPRIGHT", cell, "TOPRIGHT", -4, -3)
        cell.selectionLine:SetHeight(2)
        cell.selectionLine:SetColorTexture(0.26, 0.72, 1, 1)

        cell.assetName = EXUI:CreateVisualFontString(cell, EXFONTFRAME, "GameFontHighlightSmall")
        cell.assetName:SetPoint("BOTTOMLEFT", cell, "BOTTOMLEFT", 5, 5)
        cell.assetName:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -5, 5)
        cell.assetName:SetJustifyH("CENTER")
        cell.assetName:SetWordWrap(false)
        row.cells[column] = cell
    end
    return row
end

local function BindGridRow(row, assets)
    for column, cell in ipairs(row.cells) do
        local asset = assets and assets[column] or nil
        cell._textureAsset = asset
        cell:SetShown(asset ~= nil)
        if asset then
            local loaded = cell.thumbnail:SetTexture(asset.path)
            if loaded ~= true then
                cell.thumbnail:SetColorTexture(0.16, 0.17, 0.20, 1)
            else
                cell.thumbnail:SetTexCoord(0, 1, 0, 1)
                cell.thumbnail:SetVertexColor(1, 1, 1, 1)
            end
            cell.assetName:SetText(asset.name or "")
            cell.selectionLine:SetShown(asset == selectedAsset)
        else
            cell.thumbnail:SetTexture(nil)
            cell.assetName:SetText("")
            cell.selectionLine:Hide()
        end
    end
end

local function CreateCategoryItems()
    local categoryIcons = {
        Borders = "square", GUI = "settings", ["Icons/EXBoss"] = "image",
        ["Images/EXBoss"] = "image", ["Images/ExwindTools/EJ-UI"] = "castle",
        LOGO = "image", ["LOGO/ExwindTools"] = "image",
        ["Materials/EXBoss/Rings"] = "crosshair",
        ["Materials/ExwindTools/PlayerPosition"] = "map-pin",
    }
    local items = {
        {
            id = ALL_CATEGORIES,
            label = string.format("全部 (%d)", tonumber(Catalog.count) or #Catalog.assets),
            icon = EXUI:GetIcon("layout-grid"),
        },
    }
    for _, category in ipairs(Catalog.categories or {}) do
        local icon = categoryIcons[category.id]
            or (category.id:find("Icons/ExwindTools/font_options", 1, true) == 1 and "type" or nil)
        items[#items + 1] = {
            id = category.id,
            icon = icon and EXUI:GetIcon(icon) or nil,
            label = string.format("%s (%d)", tostring(category.label or category.id),
                tonumber(category.count) or 0),
        }
    end
    return items
end

local function EnsureWindow()
    if window then return window end

    window = CreateFrame("Frame", "ExwindTextureBrowserWindow", UIParent, "BackdropTemplate")
    window:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetFrameLevel(520)
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:SetScript("OnHide", function()
        if picker then picker.alive = false; picker = nil end
        if selectPathButton then selectPathButton:SetText("选中路径") end
    end)
    EXUI:ApplyDialogStyle(window)

    local title = EXUI:CreateVisualFontString(window, EXFONTFRAME, "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", 22, -18)
    title:SetText("EXWIND 材质浏览器")

    local subtitle = EXUI:CreateVisualFontString(window, EXFONTFRAME, "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
    subtitle:SetText("分类分页 · 小图网格预览 · 只读会话选择")

    local close = EXUI:CreateButton(window, 32, 30, "×", function() window:Hide() end,
        { variant = "soft", compact = true })
    close:SetPoint("TOPRIGHT", -16, -15)

    local divider = EXUI:CreateSettingsSeparator(window, WINDOW_WIDTH - 44)
    divider:SetPoint("TOPLEFT", 22, -64)

    local categoryTabs = EXUI:CreateTabGroup(window, {
        items = CreateCategoryItems(),
        value = selectedCategory,
        sizing = "content",
        minItemWidth = 72,
        itemHeight = 32,
        width = WINDOW_WIDTH - 44,
        onChange = function(value)
            selectedCategory = value or ALL_CATEGORIES
            RefreshGrid()
        end,
    })
    categoryTabs:SetPoint("TOPLEFT", 22, -78)
    categoryTabs:SetPoint("TOPRIGHT", -22, -78)

    local searchInput = EXUI:CreateEditBox(window, "", 470, 30, "搜索文件名 / 路径", {
        placeholder = "输入关键字即时过滤当前分类",
        onChanged = function(text)
            searchText = NormalizeSearch(text)
            RefreshGrid()
        end,
    })
    searchInput:SetPoint("TOPLEFT", 22, -130)

    countText = EXUI:CreateVisualFontString(window, EXFONTFRAME, "GameFontHighlightSmall")
    countText:SetPoint("RIGHT", window, "TOPRIGHT", -24, -145)
    countText:SetJustifyH("RIGHT")
    countText:SetText("")

    local gridCard = EXUI:CreateCard(window, WINDOW_WIDTH - 44, 490)
    gridCard:SetPoint("TOPLEFT", 22, -176)
    gridCard:SetPoint("BOTTOMRIGHT", -22, 92)
    gridList = VirtualList:Create(gridCard, {
        rowHeight = GRID_ROW_HEIGHT,
        overscan = 1,
        createRow = CreateGridRow,
        bindRow = BindGridRow,
    })
    gridList:SetPoint("TOPLEFT", gridCard, "TOPLEFT", 8, -8)
    gridList:SetPoint("BOTTOMRIGHT", gridCard, "BOTTOMRIGHT", -8, 8)

    local selectionCard = EXUI:CreateCard(window, WINDOW_WIDTH - 44, 58)
    selectionCard:SetPoint("BOTTOMLEFT", 22, 18)
    selectionCard:SetPoint("BOTTOMRIGHT", -22, 18)

    selectedName = EXUI:CreateVisualFontString(selectionCard, EXFONTFRAME, "GameFontNormal")
    selectedName:SetPoint("TOPLEFT", 14, -10)
    selectedName:SetWidth(280)
    selectedName:SetJustifyH("LEFT")
    selectedName:SetWordWrap(false)

    selectedMeta = EXUI:CreateVisualFontString(selectionCard, EXFONTFRAME, "GameFontDisableSmall")
    selectedMeta:SetPoint("TOPLEFT", selectedName, "BOTTOMLEFT", 0, -4)
    selectedMeta:SetWidth(280)
    selectedMeta:SetJustifyH("LEFT")
    selectedMeta:SetWordWrap(false)

    pathInput = EXUI:CreateEditBox(selectionCard, "", 610, 30, "材质路径", {
        placeholder = "点击小图后显示完整 WoW 路径",
    })
    pathInput:SetPoint("LEFT", selectionCard, "LEFT", 320, 0)

    local selectPath = EXUI:CreateButton(selectionCard, 108, 30, "选中路径", function()
        if not selectedAsset then return end
        if picker and picker.alive then
            local lease, asset = picker, selectedAsset
            local ok, failure = pcall(lease.onSelect, asset.path, asset)
            lease:Release()
            if not ok then error(failure, 0) end
            return
        end
        pathInput:SetFocus()
        pathInput:HighlightText()
    end, { compact = true })
    selectPathButton = selectPath
    selectPath:SetPoint("LEFT", pathInput, "RIGHT", 10, 0)

    window:Hide()
    _G.UISpecialFrames = _G.UISpecialFrames or {}
    table.insert(_G.UISpecialFrames, "ExwindTextureBrowserWindow")
    RefreshGrid()
    return window
end

local function ToggleBrowser()
    if picker then picker:Release() end
    local browser = EnsureWindow()
    browser:SetShown(not browser:IsShown())
end

-- value retains the existing path representation; this API never writes config.
-- Owners wrap onSelect with their Context.Guard and Release the lease on departure.
function EXUI:OpenTexturePicker(options)
    assert(type(options) == "table" and type(options.onSelect) == "function", "texture picker requires onSelect")
    if picker then picker:Release() end
    local browser = EnsureWindow()
    local lease = { alive=true, onSelect=options.onSelect }
    function lease:IsOpen()
        return self.alive == true and picker == self and browser:IsShown()
    end
    function lease:OwnsFrame(frame)
        if not self:IsOpen() then return false end
        while frame do
            if frame == browser then return true end
            frame = frame.GetParent and frame:GetParent() or nil
        end
        return false
    end
    function lease:Release()
        if not self.alive then return end
        self.alive = false
        if picker == self then picker = nil; browser:Hide() end
    end
    picker = lease
    local matched
    for _, asset in ipairs(Catalog.assets) do
        if asset.path == options.value then matched = asset; break end
    end
    SelectAsset(matched)
    pathInput:ClearFocus()
    selectPathButton:SetText("使用材质")
    browser:Show()
    return lease
end

_G.SLASH_EXWINDTEXTURES1 = "/extextures"
_G.SLASH_EXWINDTEXTURES2 = "/extex"
SlashCmdList.EXWINDTEXTURES = ToggleBrowser
