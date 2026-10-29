-- 单位锚点：显示要贴在某个单位的姓名板、或队伍 / 团队框里这个单位那一格上时，由这里找框体。
-- 只取框体引用、看框体能不能用（被禁止访问、没显示的跳过），不读单位状态、不碰秘密值。
-- 姓名板认暴雪原生（ExwindBlizzardNameplateAnchor）和 Plater / Platynator / Ellesmere / PlateColor；
-- 队伍 / 团队框用 ExwindTools.UnitFrame.FindUnitFrame（认 Cell、ElvUI 等第三方和暴雪框）。
-- 另给编辑画面用的假姓名板、假队伍框：屏幕上没有真的时拿来摆位置，样子跟着玩家用的姓名板插件走。

local ExwindTools = _G.ExwindTools
if type(ExwindTools) ~= "table" or type(ExwindTools.UI) ~= "table" then
    error("ExwindUnitAnchor requires initialized EXUI", 0)
end
local EXUI = ExwindTools.UI

local function IsUsableAnchorCandidate(obj, plate)
    if not obj or type(obj.GetObjectType) ~= "function" then return false end
    if obj.IsForbidden and obj:IsForbidden() then return false end
    if obj.IsVisible and not obj:IsVisible() then return false end
    local current = obj
    for _ = 1, 8 do
        if not current or type(current.GetParent) ~= "function" then break end
        current = current:GetParent()
        if not current then break end
        if current == plate or current == UIParent or current == WorldFrame then return true end
        if current.IsForbidden and current:IsForbidden() then return false end
        if current.IsShown and not current:IsShown() then return false end
    end
    return true
end

local function GetNameplate(unit)
    local api = _G.C_NamePlate
    if type(api) == "table" and type(api.GetNamePlateForUnit) == "function" then
        local plate = api.GetNamePlateForUnit(unit)
        if plate then return plate end
    end
    local driver = _G.NamePlateDriverFrame
    if driver and type(driver.GetNamePlateForUnit) == "function" then
        return driver:GetNamePlateForUnit(unit)
    end
    return nil
end

-- 单位姓名板上血条那一块（侧边图标、装饰贴它）；单位没有姓名板或姓名板插件还没装好显示时返回 nil。
function EXUI:ResolveNameplateAnchor(unit)
    if type(unit) ~= "string" or unit == "" then return nil end
    local plate = GetNameplate(unit)
    if type(plate) ~= "table" or (plate.IsForbidden and plate:IsForbidden()) then return nil end

    local native = self:GetBlizzardNameplateAnchor(unit)
    if native and native.plate == plate and native.container then return native.container end

    local backend = self:GetNameplateBackend()
    if backend == "platynator" then
        if type(plate.GetChildren) == "function" then
            local children = { plate:GetChildren() }
            for i = 1, #children do
                local child = children[i]
                if IsUsableAnchorCandidate(child, plate) and child.widgets and child.AurasManager then
                    if type(child.GetChildren) == "function" then
                        local widgets = { child:GetChildren() }
                        for j = 1, #widgets do
                            local widget = widgets[j]
                            local details = widget and widget.details
                            if IsUsableAnchorCandidate(widget, plate) and type(details) == "table"
                                and details.kind == "health" and widget.statusBar then
                                return widget
                            end
                        end
                    end
                    return child
                end
            end
        end
        -- Platynator 装好自己的显示后会藏起暴雪的 UnitFrame，退回去会跟着一个隐藏的框。
        return nil
    elseif backend == "plater" then
        -- Plater 每次排姓名板后都把这个框贴齐当前血条。
        local anchor = plate.PlaterAnchorFrame
        if IsUsableAnchorCandidate(anchor, plate) then return anchor end
    elseif backend == "ellesmere" then
        if type(plate.GetChildren) == "function" then
            local children = { plate:GetChildren() }
            for i = 1, #children do
                local child = children[i]
                if child.health and child.unit and IsUsableAnchorCandidate(child.health, plate) then
                    return child.health
                end
            end
        end
    else
        local unitFrame = plate.UnitFrame or plate.unitFrame
        if unitFrame and unitFrame.HealthBarsContainer and IsUsableAnchorCandidate(unitFrame, plate) then
            return unitFrame
        end
    end

    local candidates = {
        plate.unitFrame and plate.unitFrame.healthBar,
        plate.UnitFrame and plate.UnitFrame.healthBar,
        plate.unitFrame and plate.unitFrame.HealthBar,
        plate.UnitFrame and plate.UnitFrame.HealthBar,
        plate.unitFrame,
        plate.UnitFrame,
    }
    for i = 1, #candidates do
        if IsUsableAnchorCandidate(candidates[i], plate) then return candidates[i] end
    end
    return plate
end

-- kind = "nameplate"：单位的姓名板血条；"group"：队伍 / 团队框里这个单位那一格。找不到返回 nil。
function EXUI:ResolveUnitAnchor(kind, unit)
    if type(unit) ~= "string" or unit == "" then return nil end
    if kind == "nameplate" then return self:ResolveNameplateAnchor(unit) end
    if kind == "group" then
        local finder = ExwindTools.UnitFrame
        if type(finder) ~= "table" or type(finder.FindUnitFrame) ~= "function" then return nil end
        return finder.FindUnitFrame(unit, { preferGroupedPlayerFrame = true })
    end
    return nil
end

-- ===== 编辑画面用的假框 =====
local WHITE = "Interface\\Buttons\\WHITE8X8"
-- 暴雪原生敌对姓名板的样子（没装姓名板插件时用）。
local BLIZZARD_NAMEPLATE = { width = 128, height = 12,
    color = { r = .78, g = .08, b = .08, a = 1 }, backgroundColor = { r = .08, g = .08, b = .08, a = 1 } }
-- 暴雪紧凑队伍框一格的大小与血条色。
local GROUP_CELL = { width = 72, height = 36, gap = 2,
    color = { r = .15, g = .62, b = .25, a = 1 }, backgroundColor = { r = .08, g = .08, b = .08, a = 1 } }
local HEALTH_FILL = .7

local function Paint(texture, path, color)
    texture:SetTexture(path or WHITE)
    texture:SetVertexColor(color.r or 1, color.g or 1, color.b or 1, color.a or 1)
end

local function Bar(frame, width, height, fill, color, background, texture, backgroundTexture)
    local border = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    Paint(border, WHITE, { r = 0, g = 0, b = 0, a = 1 })
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    Paint(bg, backgroundTexture, background)
    local bar = frame:CreateTexture(nil, "ARTWORK")
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("BOTTOMLEFT")
    bar:SetWidth(math.max(1, width * fill))
    Paint(bar, texture, color)
    frame:SetSize(width, height)
end

-- 假姓名板：一条血条 + 上方名字，大小、材质、颜色跟着玩家用的姓名板插件（拿不到就用暴雪原生样子）。
-- 返回的框就是“血条那一块”，跟 ResolveNameplateAnchor 找到的真框同一个意思。
function EXUI:CreateNameplatePreview(parent, label)
    local style = self:GetThirdPartyNameplatePreviewStyle() or BLIZZARD_NAMEPLATE
    local frame = CreateFrame("Frame", nil, parent)
    frame:EnableMouse(false)
    local width = math.max(1, tonumber(style.width) or BLIZZARD_NAMEPLATE.width)
    local height = math.max(1, tonumber(style.height) or BLIZZARD_NAMEPLATE.height)
    Bar(frame, width, height, HEALTH_FILL, style.color or BLIZZARD_NAMEPLATE.color,
        style.backgroundColor or BLIZZARD_NAMEPLATE.backgroundColor, style.texture, style.backgroundTexture)
    local name = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local anchor = type(style.name) == "table" and type(style.name.anchor) == "table" and style.name.anchor or {}
    name:SetPoint(anchor.point or "BOTTOM", frame, anchor.relativePoint or "TOP", tonumber(anchor.x) or 0, tonumber(anchor.y) or 2)
    name:SetText(label or "")
    frame.name = name
    return frame
end

-- 假队伍框：竖排 #labels 格（暴雪紧凑队伍框的大小），每格一条血条 + 中间名字。frame.cells[i] 是第 i 格，
-- 跟 ResolveUnitAnchor("group", 单位) 找到的真格同一个意思。
function EXUI:CreateGroupFramePreview(parent, labels)
    local frame = CreateFrame("Frame", nil, parent)
    frame:EnableMouse(false)
    frame.cells = {}
    local count = math.max(1, #(labels or {}))
    for index = 1, count do
        local cell = CreateFrame("Frame", nil, frame)
        cell:EnableMouse(false)
        Bar(cell, GROUP_CELL.width, GROUP_CELL.height, 1, GROUP_CELL.color, GROUP_CELL.backgroundColor)
        cell:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1 - (index - 1) * (GROUP_CELL.height + GROUP_CELL.gap))
        local name = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        name:SetPoint("CENTER")
        name:SetText(labels and labels[index] or "")
        frame.cells[index] = cell
    end
    frame:SetSize(GROUP_CELL.width + 2, count * GROUP_CELL.height + (count - 1) * GROUP_CELL.gap + 2)
    return frame
end
