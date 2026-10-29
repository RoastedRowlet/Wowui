-- ExwindStackBarCollection.lua
-- 层数条唯一 Item/Collection 渲染入口：按 最小～最大 层数填充一条进度条，可带刻度。
--
-- 条体、文字、排列、群组几何、点击与视觉效果全部沿用 TimerBarCollection；这里只把
-- 层数条 presentation 换算成计时条 presentation（层数 → 进度、刻度 → 计时条刻度）。
-- 秘密层数只原样交给原生 StatusBar（TimerBarWidget:SetSecretProgress），不读取、不比较、不运算。
--
-- presentation：
--   style        计时条样式 { timerBar = {...}, text = {...} }，与 TimerBarCollection 相同
--   stacks       普通层数（数字或 nil）；秘密层数写 stacksMode = "SECRET" 与 secretStacks，
--                或沿用 { mode = "SECRET", value = ... } 包装
--   minimum      普通数字，填充起点层数，默认 0
--   maximum      普通数字，填满时的层数，默认 minimum + 1
--   markers      可选 { mode = "auto"|"manual"|"hidden", positions = { 0～1 }, thickness, color = {r,g,b,a} }；
--                auto 在 minimum 与 maximum 之间的每个整数层画一条刻度
--   time         可选，只接受普通文字 { text, shown }；层数条没有计时通道，原生 Duration 文字由调用方
--                声明的 regionElements 承载
--   其余字段（icon、label、localOffset、regionElements、elementContent、regionConfigContextID、
--   interaction、fillColor、hasFillColorComponents、fillColorComponents、shown 等）原样交给计时条。

local ExwindTools = _G.ExwindTools
local EXUI = ExwindTools and ExwindTools.UI
if not EXUI then return end

local function NumberOr(value, fallback)
    local number = tonumber(value)
    if number == nil then return fallback end
    return number
end

local function Shallow(source)
    local copy = {}
    for key, value in pairs(type(source) == "table" and source or {}) do copy[key] = value end
    return copy
end

-- 刻度只由普通声明数字计算，与层数值无关。
local function MarkerList(markers, minimum, maximum)
    if type(markers) ~= "table" then return {} end
    local positions = {}
    if markers.mode == "auto" then
        for index = math.floor(minimum) + 1, math.ceil(maximum) - 1 do
            positions[#positions + 1] = (index - minimum) / (maximum - minimum)
        end
    elseif markers.mode == "manual" then
        for _, position in ipairs(type(markers.positions) == "table" and markers.positions or {}) do
            local value = tonumber(position)
            if value and value > 0 and value < 1 then positions[#positions + 1] = value end
        end
    end
    local color = type(markers.color) == "table" and markers.color or {}
    local result = {}
    for _, position in ipairs(positions) do
        result[#result + 1] = {
            value = position, width = math.max(1, NumberOr(markers.thickness, 1)),
            r = NumberOr(color.r, 1), g = NumberOr(color.g, 1),
            b = NumberOr(color.b, 1), a = NumberOr(color.a, .65),
        }
    end
    return result
end

local function ToTimerBarPresentation(source)
    if type(source) ~= "table" then error("StackBarCollection presentation must be table", 3) end
    local result = Shallow(source)
    local minimum = NumberOr(source.minimum, 0)
    local maximum = NumberOr(source.maximum, minimum + 1)
    if maximum <= minimum then maximum = minimum + 1 end
    local stacks = source.stacks
    if source.stacksMode == "SECRET" then
        result.progress = { mode = "SECRET", value = source.secretStacks, minimum = minimum, maximum = maximum }
    elseif type(stacks) == "table" and stacks.mode == "SECRET" then
        result.progress = { mode = "SECRET", value = stacks.value, minimum = minimum, maximum = maximum }
    else
        local value = type(stacks) == "table" and stacks.value or stacks
        result.progress = { value = value == nil and minimum or value, minimum = minimum, maximum = maximum }
    end
    -- 层数条没有计时通道：进度只来自层数，时间位置只放普通文字。
    local time = source.time
    result.time = type(time) == "table" and { text = time.text, shown = time.shown } or nil
    local style = Shallow(source.style)
    style.timerBar = Shallow(style.timerBar)
    local markers = MarkerList(source.markers, minimum, maximum)
    style.timerBar.showMarkers = #markers > 0
    style.markers = markers
    result.style = style
    result.fillVisible = true
    result.stackBarSource = source
    return result
end

function EXUI:CreateStackBarCollection(parent, interactionMode, moduleKey, callbacks)
    EXUI:RequireModuleKey(moduleKey, "CreateStackBarCollection")
    local collection = EXUI:CreateTimerBarCollection(parent, interactionMode, moduleKey, callbacks)
    local applyTimerBar, reapplyTimerBar = collection.ApplyItem, collection.ReapplyCurrentItems

    -- 已换算过的 presentation（ReapplyCurrentItems 传回的 item.presentation）按原层数条声明重算。
    function collection:ApplyItem(item, presentation)
        if type(presentation) ~= "table" then error("StackBarCollection presentation must be table", 2) end
        return applyTimerBar(self, item, ToTimerBarPresentation(presentation.stackBarSource or presentation))
    end

    -- 调用方只改层数条声明；计时条换算结果不对外暴露。
    function collection:ReapplyCurrentItems(mutatePresentation, options)
        return reapplyTimerBar(self, function(converted, item)
            if type(mutatePresentation) == "function" then mutatePresentation(converted.stackBarSource, item) end
        end, options)
    end

    collection.UpdateItemTime = nil
    return collection
end
