-- =========================================================
-- ExwindGUIComposite.lua: 组合设置组、固定复合宿主及对应测量/释放。
-- 复用 ExwindGUI 的同一 UI/外观表；不创建新的配置或对象池系统。
-- 定位: 私有组合支撑 -> Font/Sound -> Preview -> Glow/Icon/TimerBar ->
-- WidgetLayout/ModuleCommon -> Aura/Anchor/Texture -> Grid 测量登记。
-- =========================================================
local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI
local L = ExwindTools.L
local MODERN = EXUI.ControlAppearance
local MC = MODERN.colors
local GM = ExwindTools.GUIMetrics
local Internal = EXUI._GUIInternal
local StyleModernTitle = Internal.StyleModernTitle
local SetDropdownDisplayText = Internal.SetDropdownDisplayText
local AcquireCompositeGroup = Internal.AcquireCompositeGroup
local IsModuleCommonOrdinaryField = Internal.IsModuleCommonOrdinaryField

-- 组合组只用列间竖线区分字段；线锚定原有容器，重排时不移动控件。
local function CreateCompositeColumnDivider(parent, topFrame, bottomFrame, side, offset)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(unpack(ExwindTools.GUIColors.sectionDivider))
    line:SetWidth(1)
    line:SetPoint("TOP", topFrame, side == "LEFT" and "TOPLEFT" or "TOPRIGHT", offset, 0)
    line:SetPoint("BOTTOM", bottomFrame, side == "LEFT" and "BOTTOMLEFT" or "BOTTOMRIGHT", offset, 0)
    return line
end

-- =========================================================
-- 组合组内部支撑：原路径访问、绑定、弹层、刷新与释放。
-- =========================================================
-- 组合控件的子控件会常驻在宿主下面。代理把读写转发到“本次借用”的数据表，
-- 这样复用后的 Slider / Dropdown / ColorButton 不会继续引用上一条规则。
local function CompositePathValue(db, path)
    if path == nil or path == "" then return db end
    local value = db
    for part in string.gmatch(path, "[^%.]+") do
        value = type(value) == "table" and value[part] or nil
    end
    return value
end

local function CompositePathSet(db, path, value)
    if type(db) ~= "table" or type(path) ~= "string" or path == "" then return false end
    local target, last = db, nil
    for part in string.gmatch(path, "[^%.]+") do
        if last then
            target[last] = type(target[last]) == "table" and target[last] or {}
            target = target[last]
        end
        last = part
    end
    if not last then return false end
    target[last] = value
    return true
end

local function CreateCompositeProxy(host, path)
    return setmetatable({}, {
        __index = function(_, field)
            local target = CompositePathValue(host._exCompositeDb, path)
            return type(target) == "table" and target[field] or nil
        end,
        __newindex = function(_, field, value)
            local target = CompositePathValue(host._exCompositeDb, path)
            if type(target) == "table" then target[field] = value end
        end,
    })
end

-- 右侧弹出面板不能作为 ScrollChild 的子对象：即使设为高层也会被滚动区域裁切。
-- 统一挂在 UIParent 的 DIALOG 层。内部 Dropdown 的列表由 Blizzard_Menu 自动创建在
-- FULLSCREEN_DIALOG，层级天然高于弹窗本身，避免同 TOOLTIP 层互相遮挡。
-- CompositeFontGroup / IconGroup / TimerBarGroup 都从这里取得弹层；层级恢复
-- 必须是这一处的统一职责，不能由各组的右侧按钮各自补丁。
local function RaiseCompositePopupHost(popup)
    if not popup then return end
    popup:SetFrameStrata("DIALOG")
    popup:SetFrameLevel(math.max(1000, (UIParent:GetFrameLevel() or 1) + 1000))
    if popup.SetToplevel then popup:SetToplevel(true) end
    -- 同 strata 的浮层会随着点击顺序而重叠；空白区点击也必须把当前 popup
    -- 放回最前，不能让它落到设置主框或另一张已存在 popup 后面。
    if popup.Raise then popup:Raise() end
end

local function CreateCompositePopupHost(owner, width, height)
    local popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    popup:SetClampedToScreen(true)
    if EXUI.SetControlAppearance then
        EXUI:SetControlAppearance(popup, EXUI:GetControlAppearance(owner))
    end
    popup:SetSize(width, height)
    -- 主面板和它的 ModalLayer 同样在 DIALOG；弹窗必须明显高于二者，
    -- 而其下拉列表再由 FULLSCREEN_DIALOG 覆盖。
    RaiseCompositePopupHost(popup)
    popup:HookScript("OnShow", function(self)
        RaiseCompositePopupHost(self)
        EXUI:ApplyDialogStyle(self)
    end)
    popup:HookScript("OnMouseDown", RaiseCompositePopupHost)
    popup._exPopupOwner = owner
    return popup
end

-- Composite 控件除自身字段外，允许以纯数据声明“同一 DB、同一次 commit”必须
-- 一并写入的字段。它不是回调、也不保存模块函数；标准 Slider binder 只消费
-- 这份公开元数据，因而接管生命周期后不会丢失控件固有语义。
local function ValidateCompositeCommitWritesMetadata(metadata)
    if metadata == nil then return nil end
    if type(metadata) ~= "table" then
        error("composite control metadata must be table", 3)
    end
    for key in pairs(metadata) do
        if key ~= "commitWrites" then
            error("composite control metadata only supports commitWrites", 3)
        end
    end
    if type(metadata.commitWrites) ~= "table" or #metadata.commitWrites == 0 then
        error("composite control commitWrites must be a non-empty array", 3)
    end
    for index, write in ipairs(metadata.commitWrites) do
        if type(write) ~= "table" or type(write.path) ~= "string" or write.path == "" then
            error("composite control commitWrites entry requires path", 3)
        end
        for key in pairs(write) do
            if key ~= "path" and key ~= "value" then
                error("composite control commitWrites entry only supports path/value", 3)
            end
        end
        local valueType = type(write.value)
        if valueType ~= "boolean" and valueType ~= "number" and valueType ~= "string" then
            error("composite control commitWrites value must be scalar: " .. tostring(index), 3)
        end
    end
    return metadata.commitWrites
end

local function RegisterCompositeControl(host, control, path, kind, metadata, displayDefault)
    if not control then return control end
    local commitWrites = ValidateCompositeCommitWritesMetadata(metadata)
    host._exCompositeControls = host._exCompositeControls or {}
    host._exCompositeControls[#host._exCompositeControls + 1] = {
        control = control, path = path, kind = kind, displayDefault = displayDefault,
        -- 仅允许声明式 commitWrites；禁止把私有 callback 塞进控件 metadata。
        commitWrites = commitWrites,
    }
    return control
end

local function CompositeDropdownText(value, items)
    for _, item in ipairs(items or {}) do
        if type(item) == "table" then
            if item.isMenu then
                local text = CompositeDropdownText(value, item.menu)
                if text then return text end
            elseif item[2] == value or tostring(item[2]) == tostring(value) then
                return item[1]
            end
        elseif item == value or tostring(item) == tostring(value) then
            return item
        end
    end
    return nil
end

local function RefreshCompositeControl(entry, db)
    local control, value = entry.control, CompositePathValue(db, entry.path)
    if not control then return end
    -- Construction defaults are presentation only; re-reading an absent field
    -- must retain that same display without adding a field to the saved DB.
    if value == nil then value = entry.displayDefault end
    if entry.kind == "color" then
        -- 颜色按钮保存的是嵌套目标表引用。组合组从对象池复用时，必须像其它
        -- 控件一样重绑到本轮 DB；仅 UpdateColor 会继续写入上一次页面的表。
        local colorDB, colorKey = db, entry.path
        local parentPath, directKey = tostring(entry.path or ""):match("^(.*)%.([^%.]+)$")
        if parentPath and directKey then
            for part in string.gmatch(parentPath, "[^%.]+") do
                colorDB = type(colorDB) == "table" and colorDB[part] or nil
            end
            colorKey = directKey
        end
        if type(colorDB) == "table" then
            control._currentDb = colorDB
            control._currentKey = colorKey
        end
        if control.UpdateColor then control:UpdateColor() end
    elseif entry.kind == "check" then
        if control.SetChecked then control:SetChecked(value == true) end
    elseif entry.kind == "slider" then
        local callback = control._onValueChanged
        control._onValueChanged = nil
        if control.Init and control._exCompositeMin ~= nil then
            -- 存档缺字段时与构造时一致按 0 显示（夹到滑条范围内），不是显示最小值。
            local minValue, maxValue = control._exCompositeMin, control._exCompositeMax
            local fallback = math.max(minValue, maxValue and math.min(maxValue, 0) or 0)
            control:Init(tonumber(value) or fallback, minValue, maxValue, control._exCompositeSteps)
        elseif control.SetValue then
            control:SetValue(tonumber(value) or 0)
        end
        control._onValueChanged = callback
        if control.ValueText and control._formatter then
            control.ValueText:SetText(control._formatter(tonumber(value) or 0))
        end
    elseif entry.kind == "dropdown" then
        if control._mediaType then
            control._selectedValue = value
            SetDropdownDisplayText(control, value == "默认" and L["默认"] or value or L["请选择..."])
        else
            control._currentValue = value
            SetDropdownDisplayText(control, CompositeDropdownText(value, control._items) or L["请选择..."])
        end
    elseif entry.kind == "choice" then
        control:SetValue(value)
    elseif entry.kind == "edit" then
        if control.SetText then control:SetText(tostring(value or "")) end
    end
end

local function BindCompositeGroup(host, db, onUpdate, opts)
    host._exCompositeDb = db
    host._exCompositeOnUpdate = onUpdate
    host._exCompositeOpts = opts or {}
    for _, entry in ipairs(host._exCompositeControls or {}) do
        RefreshCompositeControl(entry, db)
    end
    if host._exCompositeTitle and host._exCompositeLabel then
        host._exCompositeTitle:SetText(host._exCompositeLabel)
    end
    if type(host._exCompositeHeaderRefresh) == "function" then
        host:_exCompositeHeaderRefresh()
    end
    if type(host._exCompositeConfigure) == "function" then
        host:_exCompositeConfigure()
    end
end

-- Composite Host 会被 FramePool 交给不同宽度的 Grid 项目复用。仅 SetSize 会让
-- 内部卡片保留上一次借用时的绝对坐标/宽度，因此把“宿主尺寸 + 内部重排”收口。
-- 这里不保存视觉状态，也不触发配置回调；每一种 Composite 在创建时登记自己的
-- 窄布局函数，复用时只按当前实际宽高重新锚定已有控件。
-- Layout cached skins even when SetSize does not fire OnSizeChanged (same-size
-- pool reuse, or a different parent scale). Keep colors, alpha and active state;
-- this pass must not create a new panel or revive an explicitly cleared skin.
function EXUI:RefreshCompositeSurfaces(host)
    local visited = {}
    local function Refresh(frame)
        if not frame or visited[frame] then return end
        visited[frame] = true
        for _, skin in pairs(frame._exModernSurfaces or {}) do
            if type(skin.Layout) == "function" then skin.Layout() end
        end
        if frame.GetChildren then
            for _, child in ipairs({ frame:GetChildren() }) do Refresh(child) end
        end
        for _, popup in ipairs(frame._exCompositePopups or {}) do Refresh(popup) end
    end
    Refresh(host)
end

function EXUI:LayoutCompositeGroup(host, width, height)
    host:SetSize(width, height)
    if type(host._exCompositeReflow) == "function" then
        host:_exCompositeReflow(width, height)
    end
    self:RefreshCompositeSurfaces(host)
end

-- Older preview/item shells explicitly use a panel. Settings groups call the
-- public geometry-only entry above so reuse cannot add a different background.
local function ReflowCompositeGroup(host, width, height)
    EXUI:LayoutCompositeGroup(host, width, height)
    if EXUI.ApplyModernPanel then EXUI:ApplyModernPanel(host) end
end

-- 预览拖动会由模块直接写回同一份 ModuleDB；当前可见 Grid 不能等到重开页面
-- 才重新绑定。组合控件统一从自己已绑定的 DB 回读，避免每个模块分别触碰
-- Slider / Dropdown / Checkbox 私有实现，也不引入第二张预览配置表。
function EXUI:RefreshCompositeGroupFromDB(host)
    if type(host) ~= "table" or type(host._exCompositeDb) ~= "table" then return false end
    BindCompositeGroup(host, host._exCompositeDb, host._exCompositeOnUpdate, host._exCompositeOpts)
    return true
end

local function AttachCompositeRelease(host)
    local factory = _G.ExwindFactory
    -- FramePool 在每次 Release 后都会清空 frame._exPoolRelease；因此组合宿主
    -- 每次 Acquire/重绑都必须重新登记本轮清理，不能用永久 attached 标记跳过。
    if not factory or not factory.AttachPoolRelease then return end
    factory:AttachPoolRelease(host, function(frame)
        for _, popup in ipairs(frame._exCompositePopups or {}) do popup:Hide() end
        -- modulecommonsettings 的字段由模块动态声明；宿主归池时必须先归还
        -- 本轮借用的标准子控件，不能把上一模块的字段树带进下一模块。
        if frame._exClearModuleCommonEntries then
            frame:_exClearModuleCommonEntries()
        end
        frame._exCompositeDb = nil
        frame._exCompositeOnUpdate = nil
        frame._exCompositeOpts = nil
        frame._moduleCommonDb = nil
        frame._soundGroupKey = nil
        frame._soundState = nil
        frame._previewCallbacks = nil
        frame._previewData = nil
    end)
end

local function CompositeEmitUpdate(host, changedField)
    if host._exCompositeOnUpdate then host._exCompositeOnUpdate(host._exCompositeDb, changedField) end
end

-- =========================================================
-- 字体设置组：CreateFontGroup。
-- =========================================================
local COMPOSITE_PAD_X, COMPOSITE_PAD_Y, COMPOSITE_GAP =
    GM.space.compositePadX, GM.space.compositePadY, GM.space.compositeGap
local COMPOSITE_MIN_SLOT_GAP = GM.space.compositeMinSlotGap
local COMPOSITE_ACTION_PAD, COMPOSITE_ACTION_INNER_GAP =
    GM.space.compositeActionPad, GM.space.compositeActionInnerGap
-- 列内控件两侧内缩：控件宽 = 列宽 - inset，x = inset / 2。
local COMPOSITE_CONTROL_INSET = GM.space.compositeControlInset
local COMPOSITE_CONTROL_X = math.floor(COMPOSITE_CONTROL_INSET / 2)

-- Four equal visual columns; narrow cards retain those four areas in two rows.
local function CompositeColumnWidth(width)
    local columns = width < 720 and 2 or 4
    return math.max(1, math.floor((width - COMPOSITE_PAD_X * 2 - (columns - 1) * COMPOSITE_GAP) / columns))
end

-- 字体 / 图标 / 计时条三组共用的“三分隔四区”纵向布局。
-- 四区 = 左右两列指标 + 右侧功能区的左右两列；窄宽度时功能区整体落到指标区下方。
-- 一个区段按“行”排版：行高取该行左右两列声明的较大值，首行顶与末行底贴齐区段
-- 边缘、行间距统一（单行居中），左右两列共用同一组行顶，所以同一视觉行的控件
-- 一定在同一条基线上，不会因两列槽数不同而一高一低。
-- 区段高度由较高的那一列在最小行距下推算；卡片高度、Grid 测量和控件摆放
-- 全部读 BuildCompositeColumnsLayout 的结果，不再各写一份常量。
-- 每行按实际内容声明高度：带标题的滑条/下拉占标题加控件体，无标题控件只占单行；
-- 控件被整组隐藏时必须把对应行也去掉，不保留空行。
-- 槽位声明：数字 = 该行的高度；{ h = 高度, span = true } = 跨整行的底部行
-- （只允许声明在左列末尾，右列同一索引留空）。span 行排在指标区与功能区下方，
-- 宽度占满卡片整行，列间竖线不会穿过它。
local function CompositeSlotHeight(slot)
    if type(slot) == "table" then return tonumber(slot.h) or 0 end
    return tonumber(slot) or 0
end

local function CompositeSlotIsSpan(slot)
    return type(slot) == "table" and slot.span == true
end

-- 同一区段的左右两列按“行”对齐：行高取该行左右两列的较大值，行间距统一，
-- 左右两列共用同一组行顶，所以同一视觉行的控件不会因两列槽数不同而错开。
local function CompositeRowPlan(leftSlots, rightSlots)
    local rows, spans = {}, {}
    local count = math.max(#leftSlots, #rightSlots)
    for index = 1, count do
        local leftSlot, rightSlot = leftSlots[index], rightSlots[index]
        if CompositeSlotIsSpan(leftSlot) then
            spans[#spans + 1] = CompositeSlotHeight(leftSlot)
        else
            rows[#rows + 1] = math.max(CompositeSlotHeight(leftSlot), CompositeSlotHeight(rightSlot))
        end
    end
    return rows, spans
end

local function CompositeStackMinHeight(heights)
    local total = 0
    for _, height in ipairs(heights) do total = total + height end
    if #heights <= 1 then return total end
    return total + (#heights - 1) * COMPOSITE_MIN_SLOT_GAP
end

local function CompositeStackTops(heights, rangeHeight)
    local count, total = #heights, 0
    for _, height in ipairs(heights) do total = total + height end
    if count == 0 then return {} end
    if count == 1 then return { math.floor((rangeHeight - heights[1]) / 2) } end
    local gap, tops, y = (rangeHeight - total) / (count - 1), {}, 0
    for index, height in ipairs(heights) do
        tops[index] = math.floor(y + 0.5)
        y = y + height + gap
    end
    return tops
end

-- actionTexts：功能区左右两列的控件文字。宽布局下列宽放不下其中任何一条时整体改用窄布局
-- （功能区落到指标区下方、列宽加倍），文字不被截断。
local function BuildCompositeColumnsLayout(width, metricLeftSlots, metricRightSlots, leftSlots, rightSlots, actionTexts)
    width = tonumber(width) or 750
    local narrow = width < 720
    if not narrow and actionTexts then
        local wideColumn = math.floor((CompositeColumnWidth(width) * 2 + COMPOSITE_GAP) / 2)
            - COMPOSITE_ACTION_PAD - COMPOSITE_ACTION_INNER_GAP
        for _, text in ipairs(actionTexts) do
            if EXUI:MeasureButtonWidth(text) > wideColumn then narrow = true; break end
        end
    end
    local controlWidth = narrow and (width - COMPOSITE_PAD_X * 2)
        or (CompositeColumnWidth(width) * 2 + COMPOSITE_GAP)
    local metricsWidth = narrow and (width - COMPOSITE_PAD_X * 2)
        or (width - COMPOSITE_PAD_X * 2 - COMPOSITE_GAP - controlWidth)
    local itemWidth = math.floor((metricsWidth - COMPOSITE_GAP) / 2)
    local metricRows, spanRows = CompositeRowPlan(metricLeftSlots, metricRightSlots)
    local actionRows = CompositeRowPlan(leftSlots, rightSlots)
    local metricsHeight = CompositeStackMinHeight(metricRows)
    local actionHeight = CompositeStackMinHeight(actionRows)
    if not narrow then
        metricsHeight = math.max(metricsHeight, actionHeight)
        actionHeight = metricsHeight
    end
    local actionTop = narrow and (COMPOSITE_PAD_Y + metricsHeight + COMPOSITE_GAP) or COMPOSITE_PAD_Y
    local rowsBottom = narrow and (actionTop + actionHeight)
        or (COMPOSITE_PAD_Y + math.max(metricsHeight, actionHeight))
    local spanTop = rowsBottom + (#spanRows > 0 and COMPOSITE_GAP or 0)
    local spanTops, spanY = {}, spanTop
    for index, height in ipairs(spanRows) do
        spanTops[index] = spanY
        spanY = spanY + height + COMPOSITE_MIN_SLOT_GAP
    end
    local half = math.floor(controlWidth / 2)
    local metricTops = CompositeStackTops(metricRows, metricsHeight)
    local actionTops = CompositeStackTops(actionRows, actionHeight)
    return {
        narrow = narrow,
        itemWidth = itemWidth,
        col1 = COMPOSITE_PAD_X,
        col2 = COMPOSITE_PAD_X + itemWidth + COMPOSITE_GAP,
        metricsTop = COMPOSITE_PAD_Y,
        metricsHeight = metricsHeight,
        metricRows = metricRows,
        -- 左右两列共用同一组行顶。
        metricLeftTops = metricTops,
        metricRightTops = metricTops,
        controlX = narrow and COMPOSITE_PAD_X or (COMPOSITE_PAD_X + metricsWidth + COMPOSITE_GAP),
        controlWidth = controlWidth,
        actionTop = actionTop,
        actionHeight = actionHeight,
        actionRows = actionRows,
        leftTops = actionTops,
        rightTops = actionTops,
        -- 功能区左右两列对中线镜像：到卡片边与到中线的留白相同。
        actionLeftX = COMPOSITE_ACTION_PAD,
        actionRightX = half + COMPOSITE_ACTION_INNER_GAP,
        actionColumnWidth = math.max(1, half - COMPOSITE_ACTION_PAD - COMPOSITE_ACTION_INNER_GAP),
        -- 底部跨整行：y 是相对 content 的绝对值，宽度占满卡片整行。
        spanRows = spanRows,
        spanTops = spanTops,
        spanX = COMPOSITE_PAD_X + COMPOSITE_CONTROL_X,
        spanWidth = math.max(1, width - (COMPOSITE_PAD_X + COMPOSITE_CONTROL_X) * 2),
        height = spanTop + CompositeStackMinHeight(spanRows) + COMPOSITE_PAD_Y,
    }
end

-- 下拉的标签在控件外侧；按正式标签字号和间距计入实际占用高度。
local function CompositeDropdownHeight()
    return GM.font.title + 3 + GM.size.controlHeight
end

-- 行内统一基线：带标题控件（滑条 / 下拉）标题贴行顶，本体下移一个标题高度；
-- 同一行里的无标题控件（颜色按钮 / 复选框 / 按钮）也按这条基线，本体顶因此对齐。
-- 整行都是无标题控件时（行高与控件高一致）回到行顶，不再凭空下移。
local function CompositeTitleOffset()
    return CompositeDropdownHeight() - GM.size.controlHeight
end

local function CompositeAlignedY(rowTop, rowHeight, controlHeight)
    rowHeight = rowHeight or controlHeight
    local titleOffset = CompositeTitleOffset()
    if rowHeight - controlHeight >= titleOffset then
        return rowTop + titleOffset
    end
    return rowTop + math.floor((rowHeight - controlHeight) / 2)
end

local function PlaceCompositeControl(control, parent, x, y, width, height)
    control:ClearAllPoints()
    control:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    if width and height then control:SetSize(width, height)
    elseif width then control:SetWidth(width) end
    if control._gridType == "GridDropdown" or control._gridType == "GridLSMDropdown" then
        EXUI:UpdateLabelStyle(control, nil, "top")
    end
end

-- 功能区左右两列之间的竖线，位置随功能区宽度重算。
local function LayoutCompositeActionDivider(divider, card, cardWidth)
    local x = math.floor(cardWidth / 2)
    divider:ClearAllPoints()
    divider:SetPoint("TOPLEFT", card, "TOPLEFT", x, 0)
    divider:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", x, 0)
end

-- 三组的槽位声明（Grid 测量与各 Create*Group 共用）：
-- row 槽 = 带标题行的一行；line 槽 = 单行控件（复选框 / 按钮）。
local function FontGroupLayout(width)
    local row, line = GM.size.sliderHeight, GM.size.controlHeight
    local dropdown = CompositeDropdownHeight()
    return BuildCompositeColumnsLayout(width, { line, dropdown, dropdown }, { row, row, row },
        { line, line, dropdown, dropdown }, { line, line, line },
        { L["显示文字"], L["启用阴影"], L["阴影设置"], L["布局设置"], L["高级设置"] })
end

local function IconGroupLayout(width, opts)
    local row, line = GM.size.sliderHeight, GM.size.controlHeight
    local metricSlots = opts and opts.hidePositionControls == true and { row } or { row, row }
    return BuildCompositeColumnsLayout(width, metricSlots, metricSlots,
        { line, line, line, line }, { line, line, line, line },
        { L["显示图标"], L["显示边框"], L["裁切图标"], L["图标倒数"],
            L["外观设置"], L["边框设置"], L["裁切设置"], L["倒数设置"] })
end

-- 计时条组功能区：applicationBar 的图标与填充控件对原生条无效、整组隐藏，
-- 因此槽位也必须跟着收，不保留空行（与图标组 hidePositionControls 同一规则）。
local function TimerBarActionSlots(opts)
    local line = GM.size.controlHeight
    if opts and opts.applicationBar == true then return { line }, { line } end
    return { line, line, line }, { line, line, line }
end

local function TimerBarGroupLayout(width, opts)
    local row, line = GM.size.sliderHeight, GM.size.controlHeight
    local actionLeft, actionRight = TimerBarActionSlots(opts)
    -- 第三行是两个整列宽的颜色按钮；条体材质下拉落到底部的跨整行槽。
    return BuildCompositeColumnsLayout(width,
        { row, row, line, { h = CompositeDropdownHeight(), span = true } }, { row, row, line },
        actionLeft, actionRight,
        { L["显示图标"], L["显示边框"], L["图标设置"], L["边框设置"], L["填充设置"] })
end

function EXUI:CreateFontGroup(parent, width, label, db, onUpdate, opts)
    db = type(db) == "table" and db or {}
    opts = type(opts) == "table" and opts or {}
    local offsetMin = tonumber(opts.offsetMin) or -200
    local offsetMax = tonumber(opts.offsetMax) or 200
    local shadowOffsetMin = tonumber(opts.shadowOffsetMin) or -20
    local shadowOffsetMax = tonumber(opts.shadowOffsetMax) or 20

    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local defaultFont = (LSM and LSM.GetDefault and LSM:GetDefault("font")) or "Friz Quadrata TT"
    local defaults = {
        enabled = true,
        font = defaultFont,
        size = 14,
        r = 1, g = 1, b = 1, a = 1,
        outline = "OUTLINE",
        x = 0, y = 0,
        shadow = false,
        shadowX = 1, shadowY = -1,
        shadowColorR = 0, shadowColorG = 0, shadowColorB = 0, shadowColorA = 1,
        autoWidth = false,
        maxWidth = 0,
        fixedWidth = 200,
        justifyH = "LEFT", justifyV = "MIDDLE",
        gradientEnabled = false,
        gradientStart = 0, gradientLength = 0,
        -- drawLayer / drawSubLevel 是旧存档导入兼容字段：不再补默认值、
        -- 不再暴露设置控件，所有 FontString 统一由 EXFONTFRAME 接管。
        rotation = 0,
    }
    for field, value in pairs(defaults) do
        if db[field] == nil then db[field] = value end
    end
    local groupWidth = width or 750
    -- 窄卡把右侧功能区移到字段下方，避免半宽 SettingsCard 产生负 Slider 宽度。
    -- 高度与控件坐标都来自 FontGroupLayout，Grid 测量读同一个函数。
    local groupHeight = FontGroupLayout(groupWidth).height
    -- 与 IconGroup 共用同一组层级；两种复合控件只保留内容差异。
    local palette = {
        panel = MC.panel,
        card = MC.raised,
        utility = MC.raised,
        border = MC.border,
        borderSoft = MC.border,
        text = MC.text,
        value = MC.blue,
        accent = MC.blue,
    }
    local group, isNew = AcquireCompositeGroup("CompositeFontGroup", parent)
    group._exCompositeLabel = label or L["文字设置"]
    BindCompositeGroup(group, db, onUpdate, opts)
    if not isNew then
        if group._exSetUnboundedWidthControls then group:_exSetUnboundedWidthControls(opts) end
        AttachCompositeRelease(group)
        -- FontGroup owns its internal surfaces; the generic reuse helper adds
        -- an outer panel that a freshly constructed FontGroup does not have.
        EXUI:LayoutCompositeGroup(group, groupWidth, groupHeight)
        return group
    end
    local proxy = CreateCompositeProxy(group)
    db = proxy

    local function EmitUpdate() CompositeEmitUpdate(group) end

    -- FontGroup 控件写入同一份 ModuleDB 后仅经统一通知重套既有表面。
    local function GetFontInputMetadata()
        local activeOpts = group._exCompositeOpts or {}
        local metadata = activeOpts._exWriteContext
        if metadata == nil then return nil end
        if type(metadata) ~= "table" or type(metadata.moduleKey) ~= "string" or metadata.moduleKey == "" then
            error("CreateFontGroup requires Grid write context", 2)
        end
        local prefix = metadata.pathPrefix or metadata.path
        if type(prefix) ~= "string" or prefix == "" then
            error("CreateFontGroup Grid write context requires pathPrefix", 2)
        end
        local commitAPI = EXUI.CommitModuleValue
        if type(commitAPI) ~= "function" then
            error("CreateFontGroup requires its Core commit API", 2)
        end
        return metadata.moduleKey, prefix
    end
    local function CommitFontValue(field, value, onWrite)
        local moduleKey, prefix = GetFontInputMetadata()
        local function Write(nextValue)
            db[field] = nextValue
            if onWrite then onWrite(nextValue) end
        end
        if moduleKey then
            local payload = {
                moduleKey = moduleKey, path = prefix .. "." .. field,
                readValue = function() return db[field] end, writeValue = Write,
            }
            return EXUI:CommitModuleValue(payload, value)
        end
        Write(value)
        EmitUpdate()
        return true
    end
    local function CreateFontColorTransaction(colorKey)
        local fields = colorKey == "shadowColor"
            and { "shadowColorR", "shadowColorG", "shadowColorB", "shadowColorA" }
            or { "r", "g", "b", "a" }
        return function()
            -- ColorButton 是池化对象；必须在每次打开色盘时读取本次页面的合同，
            -- 不能把首次创建它的模块 key / path 闭包带到后续页面。
            local moduleKey, prefix = GetFontInputMetadata()
            if not moduleKey then return nil end
            local payload = {
                moduleKey = moduleKey, path = prefix .. "." .. colorKey,
                readValue = function()
                    return { r = db[fields[1]], g = db[fields[2]], b = db[fields[3]], a = db[fields[4]] }
                end,
                writeValue = function(value)
                    db[fields[1]], db[fields[2]], db[fields[3]], db[fields[4]] = value.r, value.g, value.b, value.a
                end,
            }
            return EXUI:CreateModuleNotifyFlow(payload)
        end
    end
    local function SetFontValue(field, value, phase, onWrite)
        db[field] = value
        if onWrite then onWrite(value) end
        if phase ~= "live" then EmitUpdate() end
    end

    -- FontGroup 的设置绑定声明输入事务生命周期。每次按下
    -- 都从当前 pooled group 的 opts 取合同，避免把上一个模块的 moduleKey/path
    -- 闭包带到本页面；拖动只写真实 DB 并 patch 已挂载 Panel，commit 才正式刷新。
    local function CreateFontPreviewLifecycle(field, onWrite)
        local activeOpts = group._exCompositeOpts or {}
        local transaction = activeOpts._exWriteContext
        if transaction ~= nil then
            if type(transaction) ~= "table" or type(transaction.moduleKey) ~= "string" or transaction.moduleKey == "" then
                error("CreateFontGroup requires Grid write context", 2)
            end
            local prefix = transaction.pathPrefix or transaction.path
            if type(prefix) ~= "string" or prefix == "" then
                error("CreateFontGroup Grid write context requires pathPrefix", 2)
            end
            local createAPI = EXUI.CreateModuleNotifyFlow
            if type(createAPI) ~= "function" then
                error("CreateFontGroup requires its Core transaction API", 2)
            end
            local function Write(value)
                db[field] = value
                if onWrite then onWrite(value) end
            end
            local payload = {
                moduleKey = transaction.moduleKey,
                path = prefix .. "." .. field,
                readValue = function() return db[field] end,
                writeValue = Write,
            }
            return createAPI(EXUI, payload)
        end
        local metadata = activeOpts._exWriteContext
        if metadata == nil then return nil end
        if type(metadata) ~= "table" or type(metadata.moduleKey) ~= "string" or metadata.moduleKey == "" then
            error("CreateFontGroup requires Grid write context", 2)
        end
        local prefix = metadata.pathPrefix or metadata.path
        if type(prefix) ~= "string" or prefix == "" then
            error("CreateFontGroup Grid write context requires pathPrefix", 2)
        end
        if type(EXUI.CreateModuleNotifyFlow) ~= "function" then
            error("CreateFontGroup requires CreateModuleNotifyFlow", 2)
        end
        local function Write(value)
            db[field] = value
            if onWrite then onWrite(value) end
        end
        return EXUI:CreateModuleNotifyFlow({
            moduleKey = metadata.moduleKey,
            path = prefix .. "." .. field,
            readValue = function() return db[field] end,
            writeValue = Write,
            commit = function(value)
                Write(value)
                EmitUpdate()
            end,
        })
    end

    local function CreateFontSlider(host, sliderWidth, titleText, field, minValue, maxValue, value, stepValue, onWrite)
        local lifecycle
        local slider = self:CreateSlider(host, sliderWidth, titleText, minValue, maxValue, value, stepValue, nil, {
            numberInputPosition = "title",
            showFill = field ~= "x" and field ~= "y" and field ~= "shadowX" and field ~= "shadowY",
            onBegin = function()
                lifecycle = CreateFontPreviewLifecycle(field, onWrite)
                if lifecycle and lifecycle.onBegin then lifecycle.onBegin() end
            end,
            onLive = function(v)
                if lifecycle and lifecycle.onLive then lifecycle.onLive(v) else SetFontValue(field, v, "live", onWrite) end
            end,
            onCommit = function(v)
                -- 输入框不会触发原生轨道的 OnMouseDown；标准模块仍必须在这里
                -- 输入框同样读取当前 Grid 写入上下文。
                local inputOpts = group._exCompositeOpts or {}
                if not lifecycle and inputOpts._exWriteContext ~= nil then
                    lifecycle = CreateFontPreviewLifecycle(field, onWrite)
                end
                if lifecycle and lifecycle.onCommit then
                    lifecycle.onCommit(v)
                    lifecycle = nil
                else
                    SetFontValue(field, v, "commit", onWrite)
                end
            end,
        })
        return slider
    end
    group:SetSize(groupWidth, groupHeight)
    EXUI:ClearControlSurface(group)

    local content = CreateFrame("Frame", nil, group)
    content:SetSize(groupWidth, groupHeight)
    content:SetPoint("TOPLEFT", 0, 0)

    local gap = COMPOSITE_GAP
    local fontLayout = FontGroupLayout(groupWidth)
    local sliderWidth = fontLayout.itemWidth - COMPOSITE_CONTROL_INSET

    -- 四区：左列（颜色/字体/描边）、右列（大小/X/Y）、功能区左列（开关+对齐）、功能区右列（三个设置按钮）。
    -- 槽位与坐标全部来自 FontGroupLayout，由下面的 _exCompositeReflow 统一摆放。
    local metricsLeft = CreateFrame("Frame", nil, content)
    local metricsRight = CreateFrame("Frame", nil, content)
    group._exFontGroupMetricCards = { metricsLeft, metricsRight }

    -- 字体、颜色和描边属于日常选项，直接展示在主面板，不再藏进弹窗。
    local colorBtn = self:CreateColorButton(metricsLeft, L["文字颜色"], db, "", true, EmitUpdate,
        { _changeFlow = CreateFontColorTransaction("color") })
    colorBtn:SetHeight(GM.size.colorButtonHeight)

    -- 下拉框的标签绘制在本体上方；带标题行的槽把本体对齐到槽底。
    local fontDrop = self:CreateLSMDropdown(metricsLeft, "font", sliderWidth, L["字体样式"], db.font, function(key)
        CommitFontValue("font", key)
    end)

    local outlineItems = { { L["无"], "" }, { L["细"], "OUTLINE" }, { L["粗"], "THICKOUTLINE" }, { L["无锯齿"], "MONOCHROME" } }
    local outlineDrop = self:CreateDropdown(metricsLeft, sliderWidth, L["文字描边"], outlineItems, db.outline, function(v)
        CommitFontValue("outline", v)
    end)

    local sizeSlider = CreateFontSlider(metricsRight, sliderWidth, L["文字大小"], "size", 4, 100, db.size, 1)
    local xSlider = CreateFontSlider(metricsRight, sliderWidth, L["X 轴偏移"], "x", offsetMin, offsetMax, db.x, 1)
    local ySlider = CreateFontSlider(metricsRight, sliderWidth, L["Y 轴偏移"], "y", offsetMin, offsetMax, db.y, 1)

    -- 右侧功能区沿用 IconGroup 的 utility 卡片。
    local controlCard = CreateFrame("Frame", nil, content)
    group._exFontGroupActionCard = controlCard
    CreateCompositeColumnDivider(content, metricsLeft, metricsLeft, "RIGHT", gap / 2)
    local actionDivider = CreateCompositeColumnDivider(content, controlCard, controlCard, "LEFT", -gap / 2)
    local utilityDivider = controlCard:CreateTexture(nil, "ARTWORK")
    utilityDivider:SetColorTexture(unpack(ExwindTools.GUIColors.sectionDivider))
    utilityDivider:SetWidth(1)

    local showText = self:CreateCheckbox(controlCard, L["显示文字"], db.enabled, function(v)
        CommitFontValue("enabled", v)
    end)

    local shadowCheck = self:CreateCheckbox(controlCard, L["启用阴影"], db.shadow, function(v)
        CommitFontValue("shadow", v)
    end)
    -- 开关量统一用开关：标签在左、开关贴右（设置行规格）。
    EXUI:PrepareSettingsListControl(showText, { presentation = "switch", labelLeft = true })
    EXUI:PrepareSettingsListControl(shadowCheck, { presentation = "switch", labelLeft = true })

    local alignmentWidth = fontLayout.actionColumnWidth
    local justifyHItems = { { L["左对齐"], "LEFT" }, { L["居中"], "CENTER" }, { L["右对齐"], "RIGHT" } }
    local justifyH = self:CreateDropdown(controlCard, alignmentWidth, L["水平对齐"], justifyHItems, db.justifyH, function(v)
        CommitFontValue("justifyH", v)
    end)

    local justifyVItems = { { L["顶部"], "TOP" }, { L["居中"], "MIDDLE" }, { L["底部"], "BOTTOM" } }
    local justifyV = self:CreateDropdown(controlCard, alignmentWidth, L["垂直对齐"], justifyVItems, db.justifyV, function(v)
        CommitFontValue("justifyV", v)
    end)

    local gradientCheck = self:CreateCheckbox(controlCard, L["启用文字渐隐"], db.gradientEnabled, function(v)
        CommitFontValue("gradientEnabled", v)
    end)
    -- 当前文字 Region 没有可靠的跨版本渐隐/旋转实现；不把未消费字段暴露给用户。
    -- 保持 CreateCheckbox 的默认尺寸，不写死宽度，也不参与功能区槽位摆放。
    gradientCheck:Hide()

    local function CreatePopup(titleText, popupWidth, popupHeight)
        local popup = CreateCompositePopupHost(group, popupWidth, popupHeight)
        EXUI:SetControlSurface(popup, GM.radius.card, palette.panel, palette.border)
        popup:Hide()
        local popupTitle = EXUI:CreateVisualFontString(popup, EXFONTFRAME, "GameFontHighlight")
        popupTitle:SetPoint("TOPLEFT", 13, -9)
        popupTitle:SetText(titleText)
        StyleModernTitle(popupTitle)
        local close = self:CreateButton(popup, 28, 24, "×", function() popup:Hide() end, { compact = true })
        close:SetPoint("TOPRIGHT", -7, -4)
        return popup
    end

    local popupScale = 1.3
    local popupWidth = math.floor(400 * popupScale)
    local shadowPopup = CreatePopup(L["阴影设置"], popupWidth, 140)
    local layoutPopup = CreatePopup(L["布局设置"], popupWidth, 156)
    local advancedPopup = CreatePopup(L["高级文字设置"], popupWidth, 210)
    local popupPad, popupGap = 14, 18
    local popupItemW = math.floor((popupWidth - popupPad * 2 - popupGap) / 2)
    local popupCol2 = popupPad + popupItemW + popupGap

    local shadowColor = self:CreateColorButton(shadowPopup, L["阴影颜色"], db, "shadowColor", true, EmitUpdate,
        { _changeFlow = CreateFontColorTransaction("shadowColor") })
    shadowColor:SetPoint("TOPLEFT", popupPad, -46)
    local shadowX = CreateFontSlider(shadowPopup, popupItemW, L["阴影 X 偏移"], "shadowX", shadowOffsetMin, shadowOffsetMax, db.shadowX, 0.1)
    shadowX:SetPoint("TOPLEFT", popupCol2, -42)
    local shadowY = CreateFontSlider(shadowPopup, popupItemW, L["阴影 Y 偏移"], "shadowY", shadowOffsetMin, shadowOffsetMax, db.shadowY, 0.1)
    shadowY:SetPoint("TOPLEFT", popupCol2, -95)

    local autoWidthCheck
    local fixedWidth = CreateFontSlider(layoutPopup, popupItemW, L["固定宽度"], "fixedWidth", 0, 1000, db.fixedWidth, 1, function()
        -- 用户调整固定宽度即明确选择固定宽度模式；数值 0 的语义是“按文字自身宽度”。
        -- 不自动关掉该模式会让滑条看似没有作用。
        db.autoWidth = false
        if autoWidthCheck.SetChecked then autoWidthCheck:SetChecked(false) end
    end)
    fixedWidth:SetPoint("TOPLEFT", popupPad, -42)
    local maxWidth = CreateFontSlider(layoutPopup, popupItemW, L["最大宽度 (0=不限)"], "maxWidth", 0, 1000, db.maxWidth, 1)
    maxWidth:SetPoint("TOPLEFT", popupCol2, -42)
    autoWidthCheck = self:CreateCheckbox(layoutPopup, L["自动宽度"], db.autoWidth, function(v)
        CommitFontValue("autoWidth", v)
    end)
    autoWidthCheck:SetPoint("TOPLEFT", popupPad, -96)
    autoWidthCheck:SetSize(156, GM.size.checkboxRowHeight)

    local gradientStart = CreateFontSlider(advancedPopup, popupItemW, L["渐隐起点"], "gradientStart", 0, 1000, db.gradientStart, 1)
    gradientStart:SetPoint("TOPLEFT", popupPad, -42)
    local gradientLength = CreateFontSlider(advancedPopup, popupItemW, L["渐隐长度"], "gradientLength", 0, 1000, db.gradientLength, 1)
    gradientLength:SetPoint("TOPLEFT", popupCol2, -42)
    local rotation = CreateFontSlider(advancedPopup, popupItemW, L["文字旋转"], "rotation", -180, 180, db.rotation, 1)
    rotation:SetPoint("TOPLEFT", popupPad, -150)

    local function TogglePopup(popup, anchor)
        local shouldShow = not popup:IsShown()
        shadowPopup:Hide()
        layoutPopup:Hide()
        advancedPopup:Hide()
        if shouldShow then
            popup:ClearAllPoints()
            popup:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -6)
            popup:Show()
        end
    end
    local function CreateUtilityButton(text, buttonWidth, onClick)
        return EXUI:CreateButton(controlCard, buttonWidth, GM.size.buttonHeight, text, onClick, { variant = "soft" })
    end

    local buttonWidth = fontLayout.actionColumnWidth
    local shadowButton = CreateUtilityButton(L["阴影设置"], buttonWidth, function(self) TogglePopup(shadowPopup, self) end)
    local layoutButton = CreateUtilityButton(L["布局设置"], buttonWidth, function(self) TogglePopup(layoutPopup, self) end)
    local advancedButton = CreateUtilityButton(L["高级设置"], buttonWidth, function(self) TogglePopup(advancedPopup, self) end)

    -- 单行公告等明确声明为无界文本的模块不能暴露会制造宽度限制的控件。
    -- 该组会被对象池复用，因而每次绑定都必须显式恢复/隐藏，不能把上一个
    -- 无界模块的可见性残留给普通文字模块。
    group._exFontAutoWidthCheck = autoWidthCheck
    group._exFontLayoutButton = layoutButton
    group._exSetUnboundedWidthControls = function(self, activeOpts)
        local unbounded = type(activeOpts) == "table" and activeOpts.unboundedWidth == true
        if self._exFontAutoWidthCheck then self._exFontAutoWidthCheck:SetShown(not unbounded) end
        if self._exFontLayoutButton then self._exFontLayoutButton:SetShown(not unbounded) end
    end
    group:_exSetUnboundedWidthControls(opts)

    group:HookScript("OnHide", function()
        shadowPopup:Hide()
        layoutPopup:Hide()
        advancedPopup:Hide()
    end)
    RegisterCompositeControl(group, colorBtn, "", "color")
    RegisterCompositeControl(group, fontDrop, "font", "dropdown")
    RegisterCompositeControl(group, outlineDrop, "outline", "dropdown")
    RegisterCompositeControl(group, sizeSlider, "size", "slider")
    RegisterCompositeControl(group, xSlider, "x", "slider")
    RegisterCompositeControl(group, ySlider, "y", "slider")
    RegisterCompositeControl(group, showText, "enabled", "check")
    RegisterCompositeControl(group, shadowCheck, "shadow", "check")
    RegisterCompositeControl(group, autoWidthCheck, "autoWidth", "check")
    RegisterCompositeControl(group, gradientCheck, "gradientEnabled", "check")
    RegisterCompositeControl(group, shadowColor, "shadowColor", "color")
    RegisterCompositeControl(group, shadowX, "shadowX", "slider")
    RegisterCompositeControl(group, shadowY, "shadowY", "slider")
    -- 固定宽度是 FontGroup 的公开控件语义：调整它必定切出自动宽度模式。
    -- 旧页面仍由上面的 Slider callback 保持此行为；标准生命周期接管时则
    -- 读取这份声明式 metadata，在同一 DB、同一次 commit 写入 autoWidth=false。
    RegisterCompositeControl(group, fixedWidth, "fixedWidth", "slider", {
        commitWrites = {
            { path = "autoWidth", value = false },
        },
    })
    RegisterCompositeControl(group, maxWidth, "maxWidth", "slider")
    RegisterCompositeControl(group, justifyH, "justifyH", "dropdown")
    RegisterCompositeControl(group, justifyV, "justifyV", "dropdown")
    RegisterCompositeControl(group, gradientStart, "gradientStart", "slider")
    RegisterCompositeControl(group, gradientLength, "gradientLength", "slider")
    RegisterCompositeControl(group, rotation, "rotation", "slider")
    group._exCompositePopups = { shadowPopup, layoutPopup, advancedPopup }

    group._fontGroupDb = proxy
    -- 宽窄两种布局都由同一次 FontGroupLayout 决定：每列控件按槽位摆放，
    -- 卡片高度 = layout.height，Grid 测量读同一个函数。
    group._exCompositeReflow = function(self, nextWidth)
        local layout = FontGroupLayout(nextWidth)
        local nextSliderWidth = layout.itemWidth - COMPOSITE_CONTROL_INSET
        local columnWidth, leftX, rightX = layout.actionColumnWidth, layout.actionLeftX, layout.actionRightX

        self:SetSize(nextWidth, layout.height)
        content:ClearAllPoints()
        content:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
        content:SetSize(nextWidth, layout.height)
        EXUI:ClearControlSurface(self)

        metricsLeft:ClearAllPoints(); metricsLeft:SetPoint("TOPLEFT", content, "TOPLEFT", layout.col1, -layout.metricsTop)
        metricsLeft:SetSize(layout.itemWidth, layout.metricsHeight)
        metricsRight:ClearAllPoints(); metricsRight:SetPoint("TOPLEFT", content, "TOPLEFT", layout.col2, -layout.metricsTop)
        metricsRight:SetSize(layout.itemWidth, layout.metricsHeight)
        local leftTops, rightTops = layout.metricLeftTops, layout.metricRightTops
        local metricRows = layout.metricRows
        PlaceCompositeControl(colorBtn, metricsLeft, COMPOSITE_CONTROL_X,
            CompositeAlignedY(leftTops[1], metricRows[1], GM.size.colorButtonHeight),
            nextSliderWidth, GM.size.colorButtonHeight)
        PlaceCompositeControl(fontDrop, metricsLeft, COMPOSITE_CONTROL_X,
            CompositeAlignedY(leftTops[2], metricRows[2], GM.size.dropdownHeight), nextSliderWidth)
        PlaceCompositeControl(outlineDrop, metricsLeft, COMPOSITE_CONTROL_X,
            CompositeAlignedY(leftTops[3], metricRows[3], GM.size.dropdownHeight), nextSliderWidth)
        PlaceCompositeControl(sizeSlider, metricsRight, COMPOSITE_CONTROL_X, rightTops[1], nextSliderWidth)
        PlaceCompositeControl(xSlider, metricsRight, COMPOSITE_CONTROL_X, rightTops[2], nextSliderWidth)
        PlaceCompositeControl(ySlider, metricsRight, COMPOSITE_CONTROL_X, rightTops[3], nextSliderWidth)

        controlCard:ClearAllPoints()
        controlCard:SetPoint("TOPLEFT", content, "TOPLEFT", layout.controlX, -layout.actionTop)
        controlCard:SetSize(layout.controlWidth, layout.actionHeight)
        actionDivider:SetShown(not layout.narrow)
        LayoutCompositeActionDivider(utilityDivider, controlCard, layout.controlWidth)
        local left, right = layout.leftTops, layout.rightTops
        local actionRows = layout.actionRows
        local checkHeight = GM.size.checkboxRowHeight
        PlaceCompositeControl(showText, controlCard, leftX,
            CompositeAlignedY(left[1], actionRows[1], checkHeight), columnWidth, checkHeight)
        PlaceCompositeControl(shadowCheck, controlCard, leftX,
            CompositeAlignedY(left[2], actionRows[2], checkHeight), columnWidth, checkHeight)
        PlaceCompositeControl(justifyH, controlCard, leftX,
            CompositeAlignedY(left[3], actionRows[3], GM.size.dropdownHeight), columnWidth)
        PlaceCompositeControl(justifyV, controlCard, leftX,
            CompositeAlignedY(left[4], actionRows[4], GM.size.dropdownHeight), columnWidth)
        for index, button in ipairs({ shadowButton, layoutButton, advancedButton }) do
            PlaceCompositeControl(button, controlCard, rightX,
                CompositeAlignedY(right[index], actionRows[index], GM.size.buttonHeight),
                columnWidth, GM.size.buttonHeight)
        end

        for _, card in ipairs(self._exFontGroupMetricCards) do
            EXUI:ClearControlSurface(card)
        end
        EXUI:ClearControlSurface(controlCard)
        for _, popup in ipairs(self._exCompositePopups or {}) do
            EXUI:SetControlSurface(popup, GM.radius.card, palette.panel, palette.border)
        end
    end
    EXUI:LayoutCompositeGroup(group, groupWidth, groupHeight)
    -- 预览画布拖动会直接写入 db；提供统一回刷入口，让下方 X/Y 滑杆
    -- 立即同步，而不是下一次手动调整时从旧值跳回去。
    group.RefreshFromDB = function(self)
        BindCompositeGroup(self, self._exCompositeDb, self._exCompositeOnUpdate, self._exCompositeOpts)
    end
    AttachCompositeRelease(group)
    return group
end

-- =========================================================
-- 12. 音效设置复合组件 (Sound Settings Group)
-- 扁平前缀字段：<key>Enabled/Source/Label/LSM/Path/TtsText/Channel。
-- 来源集合由调用方 opts.sources 声明；未声明时绝不开放语音包。
-- =========================================================
local function ResolveSoundGroupSecondaryCheckbox(opts)
    local spec = type(opts) == "table" and opts.secondaryCheckbox or nil
    if spec == nil then return nil end
    if type(spec) ~= "table" then
        error("soundgroup secondaryCheckbox must be table", 3)
    end
    for field in pairs(spec) do
        if field ~= "key" and field ~= "label" then
            error("soundgroup secondaryCheckbox only supports key/label", 3)
        end
    end
    if type(spec.key) ~= "string" or spec.key == "" then
        error("soundgroup secondaryCheckbox requires non-empty key", 3)
    end
    if type(spec.label) ~= "string" or spec.label == "" then
        error("soundgroup secondaryCheckbox requires non-empty label", 3)
    end
    return spec
end

-- SoundGroup 的测量和重排共用同一份布局；通道单选在组内独占一行。
function EXUI:BuildSoundGroupLayout(width, opts)
    local groupWidth = math.max(1, tonumber(width) or 750)
    local secondaryCheckbox = ResolveSoundGroupSecondaryCheckbox(opts)
    local extraHeight = secondaryCheckbox and 56 or 0
    local channelLabelHeight = GM.font.label + GM.space.descriptionGap
    if groupWidth >= 760 then
        return {
            height = 64 + extraHeight + channelLabelHeight + GM.size.segmentedItemHeight + GM.space.descriptionGap,
            isWide = true,
            secondaryCheckbox = secondaryCheckbox,
            enabledY = -4,
            secondaryY = -60,
            sourceY = -4,
            channelY = -64 - extraHeight - channelLabelHeight,
            testY = -4,
        }
    end
    return {
        height = 101 + extraHeight + GM.size.segmentedItemHeight + 8,
        isWide = false,
        secondaryCheckbox = secondaryCheckbox,
        enabledY = -8,
        secondaryY = -45,
        sourceY = -45 - extraHeight,
        channelY = -101 - extraHeight,
        testY = -104 - extraHeight,
    }
end

-- Presentation-only sound selector. The declaration supplies existing controls;
-- their owner retains callbacks, values, pooling and configuration writes.
local function SetSoundSelectorJoinedEdge(control, edge)
    if not control then return end
    if not control._exJoinedEdge then
        local release = control._exPoolRelease
        _G.ExwindFactory:AttachPoolRelease(control, function(self)
            self._exJoinedEdge = nil
            if release then release(self) end
        end)
    end
    control._exJoinedEdge = edge
    EXUI:ApplyControlAppearance(control)
    for _, skin in pairs(control._exModernSurfaces or {}) do skin.Layout() end
end

function EXUI:LayoutSoundSelector(parent, spec)
    local source, preview = spec.source, spec.preview
    if not (source and preview) then return end
    local top, height = spec.top or 0, spec.height or GM.size.controlHeight
    source._exGridFixedHeight = height
    SetSoundSelectorJoinedEdge(source, "first")
    SetSoundSelectorJoinedEdge(preview, "last")
    source:ClearAllPoints()
    source:SetPoint("TOPLEFT", parent, "TOPLEFT", spec.left or 0, -top)
    source:SetSize(spec.sourceWidth or 100, height)
    source:Show()
    preview:ClearAllPoints()
    preview:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(spec.right or 0), -top)
    preview:SetSize(spec.previewWidth or 28, height)
    preview:Show()
    if spec.paintPreview then spec.paintPreview(preview) end
    for _, control in pairs(spec.contents) do
        if control._gridType == "GridDropdown" or control._gridType == "GridLSMDropdown"
            or control._gridType == "GridMultiselect" then control._exGridFixedHeight = height end
        SetSoundSelectorJoinedEdge(control, "middle")
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", source, "TOPRIGHT", spec.gap or 0, 0)
        control:SetPoint("TOPRIGHT", preview, "TOPLEFT", -(spec.gap or 0), 0)
        control:SetHeight(height)
    end
end

function EXUI:RefreshSoundSelector(spec)
    -- Never normalize or write a source value here. Unsupported sources simply
    -- have no visible editor; the caller owns its existing source policy.
    for source, control in pairs(spec.contents) do
        local selected = source == spec.value
        control:SetShown(selected)
        if spec.setUsable and (selected or spec.updateInactive) then
            spec.setUsable(control, selected and spec.enabled == true)
        end
    end
    if spec.preview then
        spec.preview:Show()
        if spec.setUsable then spec.setUsable(spec.preview, spec.enabled == true) end
    end
end

function EXUI:CreateSoundGroup(parent, width, label, db, key, onUpdate, opts)
    db = type(db) == "table" and db or {}
    opts = type(opts) == "table" and opts or {}
    key = tostring(key or "sound")

    local function HasUsablePackItems(items)
        if type(items) ~= "table" then return false end
        for _, item in ipairs(items) do
            if type(item) == "string" and item ~= "" then return true end
            if type(item) == "table" and item[1] ~= nil and item[2] ~= nil then return true end
        end
        return false
    end
    local function ResolveInitialPackItems()
        local packItems = opts.packItems
        if type(packItems) == "function" then
            local ok, result = pcall(packItems, db, key)
            packItems = ok and result or nil
        end
        return packItems
    end

    local allowed = {}
    local sources = {}
    local requestedSources = type(opts.sources) == "table" and opts.sources or { "lsm", "file", "tts" }
    local packAvailable = HasUsablePackItems(ResolveInitialPackItems())
    for _, source in ipairs(requestedSources) do
        if source == "pack" and not packAvailable then
            -- pack 没有本轮可用条目时不能成为可选来源，更不能被选为默认值。
        elseif (source == "pack" or source == "lsm" or source == "file" or source == "tts") and not allowed[source] then
            allowed[source] = true
            sources[#sources + 1] = source
        end
    end
    if #sources == 0 then
        sources = { "lsm", "file", "tts" }
        allowed = { lsm = true, file = true, tts = true }
    end

    local sourceItems = {
        pack = { L["语音包"], "pack" },
        lsm = { L["LSM音效"], "lsm" },
        file = { L["自定义路径"], "file" },
        tts = { L["TTS语音"], "tts" },
    }
    local dropdownSources = {}
    local defaultSource
    for _, source in ipairs(sources) do
        dropdownSources[#dropdownSources + 1] = sourceItems[source]
        if not defaultSource and source ~= "pack" then defaultSource = source end
    end
    defaultSource = defaultSource or sources[1]

    local group
    local suffix = {
        enabled = "Enabled", source = "Source", label = "Label", lsm = "LSM",
        path = "Path", tts = "TtsText", channel = "Channel",
    }
    local function Field(name) return ((group and group._soundGroupKey) or key) .. suffix[name] end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local defaultLSM = (LSM and LSM.GetDefault and LSM:GetDefault("sound")) or "None"
    local defaults = {
        enabled = false, source = defaultSource, label = "", lsm = defaultLSM,
        path = "", tts = "", channel = "Master",
    }
    for name, value in pairs(defaults) do
        local field = Field(name)
        if db[field] == nil then db[field] = value end
    end
    if not allowed[db[Field("source")]] then db[Field("source")] = defaultSource end

    -- 宽版首行：启用 / 来源 / 当前音效 / 试听；通道单选独占下一行。
    -- 窄宿主的启用、声音选择和通道分别占行，避免相互覆盖。
    local groupWidth = width or 750
    local soundLayout = self:BuildSoundGroupLayout(groupWidth, opts)
    local groupHeight = soundLayout.height
    local isNew
    group, isNew = AcquireCompositeGroup("CompositeSoundGroup", parent)
    group._exCompositeLabel = label or L["音效设置"]
    group._soundGroupKey = key
    group._soundState = {
        allowed = allowed, defaultSource = defaultSource, dropdownSources = dropdownSources,
        requestedSources = requestedSources,
    }
    BindCompositeGroup(group, db, onUpdate, opts)
    if not isNew then
        group:_exCompositeConfigure()
        AttachCompositeRelease(group)
        EXUI:LayoutCompositeGroup(group, groupWidth, groupHeight)
        EXUI:ClearControlSurface(group)
        return group
    end

    group:SetSize(groupWidth, groupHeight)
    EXUI:ClearControlSurface(group)

    local content = CreateFrame("Frame", nil, group)
    content:SetPoint("TOPLEFT", 0, 0)
    local settingsCard = CreateFrame("Frame", nil, content)

    local function ActiveDB() return type(group._exCompositeDb) == "table" and group._exCompositeDb or nil end
    local function SetValue(name, value)
        local active = ActiveDB()
        if active then active[Field(name)] = value end
    end
    local function GetValue(name)
        local active = ActiveDB()
        return active and active[Field(name)] or defaults[name]
    end
    local function EmitUpdate() CompositeEmitUpdate(group) end

    local enabled = self:CreateCheckbox(settingsCard, L["启用"], GetValue("enabled"), function(value)
        SetValue("enabled", value); EmitUpdate()
    end)
    local secondaryCheckbox = self:CreateCheckbox(settingsCard, "", false, function(value)
        local activeOpts = group._exCompositeOpts or {}
        local spec = ResolveSoundGroupSecondaryCheckbox(activeOpts)
        local active = ActiveDB()
        if spec and active and CompositePathSet(active, spec.key, value) then
            EmitUpdate()
        end
    end)
    local sourceDrop = self:CreateDropdown(settingsCard, 200, L["音效来源"], dropdownSources, GetValue("source"), function(value)
        SetValue("source", value)
        group:_exCompositeConfigure()
        EmitUpdate()
    end)
    local packDrop = self:CreateDropdown(settingsCard, 200, L["语音包标签"], {}, GetValue("label"), function(value)
        SetValue("label", value); EmitUpdate()
    end)
    local lsmDrop = self:CreateLSMSoundDropdown(settingsCard, 200, L["选择音效 (LSM)"], GetValue("lsm"), function(value)
        SetValue("lsm", value); EmitUpdate()
    end)
    lsmDrop._mediaType = "sound"
    local pathInput = self:CreateEditBox(settingsCard, GetValue("path"), 200, GM.size.inputHeight, L["自定义路径"], {
        placeholder = L["示例: Interface\\AddOns\\MySound\\test.ogg"],
        onEnter = function(value) SetValue("path", value); EmitUpdate() end,
        onEditFocusLost = function(value) SetValue("path", value); EmitUpdate() end,
    })
    local ttsInput = self:CreateEditBox(settingsCard, GetValue("tts"), 200, GM.size.inputHeight, L["TTS文本"], {
        placeholder = L["输入要朗读的文字"],
        onEnter = function(value) SetValue("tts", value); EmitUpdate() end,
        onEditFocusLost = function(value) SetValue("tts", value); EmitUpdate() end,
    })
    local channels = {
        { L["主音量 (Master)"], "Master" }, { L["音效 (SFX)"], "SFX" },
        { L["环境 (Ambience)"], "Ambience" }, { L["音乐 (Music)"], "Music" },
        { L["对话 (Dialog)"], "Dialog" },
    }
    local channelGroup = self:CreateSegmentedControl(settingsCard, groupWidth - COMPOSITE_PAD_X * 2, channels, GetValue("channel"), function(value)
        SetValue("channel", value); EmitUpdate()
    end)
    local channelLabel = self:CreateVisualFontString(settingsCard, EXFONTFRAME, "GameFontHighlightSmall")
    MODERN.ApplyTextRole(channelLabel, "control", MC.muted)
    channelLabel:SetText(L["音频通道"])
    channelLabel:SetPoint("BOTTOMLEFT", channelGroup, "TOPLEFT", 0, GM.space.descriptionGap)
    local testButton = self:CreateButton(settingsCard, 110, GM.size.buttonHeight, "", function(button)
        local activeOpts = group._exCompositeOpts or {}
        if type(activeOpts.onTest) == "function" then
            activeOpts.onTest(group._exCompositeDb, group._soundGroupKey, button)
            return
        end
        -- Module declarations are pure data, so Grid soundgroup cannot carry a
        -- callback.  An explicit testButtonKey reuses the established module
        -- click-state contract; the module still owns the actual playback.
        local clickKey = activeOpts.testButtonKey
        local writeContext = activeOpts._exWriteContext
        if type(clickKey) == "string" and clickKey ~= ""
            and type(writeContext) == "table" and type(writeContext.moduleKey) == "string"
            and writeContext.moduleKey ~= "" then
            ExwindTools:UpdateState(writeContext.moduleKey .. ".ButtonClicked", {
                key = clickKey,
                fullPath = writeContext.pathPrefix,
                ts = GetTime(),
            })
        end
    end)
    EXUI:ApplySoundPreviewAppearance(testButton)

    enabled._soundField = "enabled"
    sourceDrop._soundField = "source"
    packDrop._soundField = "label"
    lsmDrop._soundField = "lsm"
    pathInput._soundField = "path"
    ttsInput._soundField = "tts"
    channelGroup._soundField = "channel"
    RegisterCompositeControl(group, enabled, Field("enabled"), "check")
    RegisterCompositeControl(group, sourceDrop, Field("source"), "dropdown")
    RegisterCompositeControl(group, packDrop, Field("label"), "dropdown")
    RegisterCompositeControl(group, lsmDrop, Field("lsm"), "dropdown")
    RegisterCompositeControl(group, pathInput, Field("path"), "edit")
    RegisterCompositeControl(group, ttsInput, Field("tts"), "edit")
    RegisterCompositeControl(group, channelGroup, Field("channel"), "choice")

    local function ResolvePackItems()
        local activeOpts = group._exCompositeOpts or {}
        local packItems = activeOpts.packItems
        if type(packItems) == "function" then
            local ok, result = pcall(packItems, group._exCompositeDb, group._soundGroupKey)
            packItems = ok and result or nil
        end
        return type(packItems) == "table" and packItems or {}
    end
    local function RebuildSourceState(state, packItems)
        local nextAllowed, nextItems, nextDefault = {}, {}, nil
        for _, candidate in ipairs(state.requestedSources or {}) do
            if candidate == "pack" and not HasUsablePackItems(packItems) then
                -- 动态 provider 本轮为空时，pack 必须从来源菜单消失。
            elseif (candidate == "pack" or candidate == "lsm" or candidate == "file" or candidate == "tts") and not nextAllowed[candidate] then
                nextAllowed[candidate] = true
                nextItems[#nextItems + 1] = sourceItems[candidate]
                if not nextDefault and candidate ~= "pack" then nextDefault = candidate end
            end
        end
        if #nextItems == 0 then
            nextAllowed = { lsm = true, file = true, tts = true }
            nextItems = { sourceItems.lsm, sourceItems.file, sourceItems.tts }
            nextDefault = "lsm"
        end
        state.allowed, state.dropdownSources, state.defaultSource = nextAllowed, nextItems, nextDefault or nextItems[1][2]
    end
    group._exCompositeConfigure = function(self)
        local state = self._soundState or {}
        local activeOpts = self._exCompositeOpts or {}
        local secondarySpec = ResolveSoundGroupSecondaryCheckbox(activeOpts)
        if testButton.SetText then testButton:SetText("") end
        secondaryCheckbox:SetShown(secondarySpec ~= nil)
        if secondarySpec then
            secondaryCheckbox.label:SetText(secondarySpec.label)
            secondaryCheckbox:SetChecked(CompositePathValue(self._exCompositeDb, secondarySpec.key) == true)
        end
        -- 同一 CompositeHost 可被不同 key/来源集合的页面复用；先将每个已建立
        -- 控件的扁平字段映射重绑到本轮 key，再刷新显示，不能沿用上一页路径。
        for _, entry in ipairs(self._exCompositeControls or {}) do
            local fieldName = entry.control and entry.control._soundField
            if fieldName then
                entry.path = Field(fieldName)
                RefreshCompositeControl(entry, self._exCompositeDb)
            end
        end
        local packItems = ResolvePackItems()
        RebuildSourceState(state, packItems)
        local source = GetValue("source")
        if not state.allowed or not state.allowed[source] then
            source = state.defaultSource
            SetValue("source", source)
        end
        sourceDrop._items = state.dropdownSources or {}
        sourceDrop._currentValue = source
        SetDropdownDisplayText(sourceDrop, CompositeDropdownText(source, sourceDrop._items) or L["请选择..."])
        packDrop._items = packItems
        packDrop._currentValue = GetValue("label")
        SetDropdownDisplayText(packDrop, CompositeDropdownText(packDrop._currentValue, packItems) or L["请选择..."])
        if #packItems > 0 then
            if packDrop.Enable then packDrop:Enable() end
        elseif packDrop.Disable then
            packDrop:Disable()
        end
        if packDrop.EnableMouse then packDrop:EnableMouse(#packItems > 0) end
        EXUI:RefreshSoundSelector({
            contents = { pack = packDrop, lsm = lsmDrop, file = pathInput, tts = ttsInput },
            preview = testButton, value = source,
        })
    end
    group._exCompositeReflow = function(self, nextWidth, nextHeight)
        local layout = EXUI:BuildSoundGroupLayout(nextWidth, self._exCompositeOpts)
        content:ClearAllPoints()
        content:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
        content:SetSize(nextWidth, math.max(1, nextHeight))
        EXUI:ClearControlSurface(self)
        local padding = COMPOSITE_PAD_X
        settingsCard:ClearAllPoints(); settingsCard:SetPoint("TOPLEFT", content, "TOPLEFT")
        settingsCard:SetSize(nextWidth, math.max(1, nextHeight))
        local sourceTop = layout.isWide and 26 or -layout.sourceY
        local selectorLeft = layout.isWide and 132 or padding
        local selectorRight = padding
        -- 复选框行比普通控件矮，垂直居中到同一行的 controlHeight 控件上。
        local checkInset = math.floor((GM.size.controlHeight - GM.size.checkboxRowHeight) / 2)
        enabled:ClearAllPoints(); enabled:SetPoint("TOPLEFT", settingsCard, "TOPLEFT", padding, (layout.isWide and -26 or layout.enabledY) - checkInset)
        enabled:SetSize(105, GM.size.checkboxRowHeight)
        secondaryCheckbox:ClearAllPoints(); secondaryCheckbox:SetPoint("TOPLEFT", settingsCard, "TOPLEFT", padding, layout.secondaryY)
        secondaryCheckbox:SetWidth(math.max(105, nextWidth - padding * 2))
        for _, control in ipairs({ sourceDrop, packDrop, lsmDrop, pathInput, ttsInput }) do
            if control.label then control.label:Hide() end
            if control.labelText then control.labelText:Hide() end
        end
        EXUI:LayoutSoundSelector(settingsCard, {
            source = sourceDrop, preview = testButton,
            contents = { pack = packDrop, lsm = lsmDrop, file = pathInput, tts = ttsInput },
            left = selectorLeft, right = selectorRight, top = sourceTop, height = GM.size.controlHeight,
            sourceWidth = math.min(130, math.max(90, (nextWidth - selectorLeft - selectorRight) * .25)),
            previewWidth = 30, paintPreview = function(button) EXUI:ApplySoundPreviewAppearance(button) end,
        })
        channelGroup:ClearAllPoints()
        channelGroup:SetPoint("TOPLEFT", settingsCard, "TOPLEFT", padding, layout.channelY)
        channelGroup:SetWidth(math.max(1, nextWidth - padding * 2))
    end
    group:_exCompositeConfigure()
    EXUI:LayoutCompositeGroup(group, groupWidth, groupHeight)
    AttachCompositeRelease(group)
    return group
end

-- =========================================================
-- 14. 交互式预览画板 (Interactive Preview Canvas)
-- =========================================================
function EXUI:CreatePreviewCanvas(parent, width, height, elementsData, callbacks)
    local canvas, isNew = AcquireCompositeGroup("CompositePreviewCanvas", parent)
    canvas._previewCallbacks = callbacks or {}
    canvas._previewData = elementsData or {}
    canvas:SetSize(width, height)
    if not isNew then
        canvas.selectedKey = nil
        canvas:UpdateElements(canvas._previewData)
        ReflowCompositeGroup(canvas, width, height)
        AttachCompositeRelease(canvas)
        return canvas
    end

    -- 画板背景 (网格或深色背景)
    canvas:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tileSize = 16,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    EXUI:ApplyModernPanel(canvas, true)

    -- 网格参考线 (辅助对齐)
    local gridLine = EXUI:CreateVisualTexture(canvas, EXBACKGROUNDFRAME)
    gridLine:SetAllPoints()
    gridLine:SetColorTexture(1, 1, 1, 0.05)

    local centerLineH = EXUI:CreateVisualTexture(canvas, EXBASEFRAME)
    centerLineH:SetHeight(1)
    centerLineH:SetPoint("LEFT"); centerLineH:SetPoint("RIGHT")
    centerLineH:SetPoint("CENTER")
    centerLineH:SetColorTexture(1, 1, 1, 0.2)

    local centerLineV = EXUI:CreateVisualTexture(canvas, EXBASEFRAME)
    centerLineV:SetWidth(1)
    centerLineV:SetPoint("TOP"); centerLineV:SetPoint("BOTTOM")
    centerLineV:SetPoint("CENTER")
    centerLineV:SetColorTexture(1, 1, 1, 0.2)

    canvas.elements = {}
    canvas.selectedKey = nil

    -- 内部方法：创建/更新子元素
    function canvas:UpdateElements(dataMap)
        -- 1. 隐藏所有旧元素
        for _, el in pairs(self.elements) do el:Hide() end

        -- 2. 遍历数据创建/显示元素
        for key, data in pairs(dataMap) do
            if data.enabled then
                local el = self.elements[key]
                if not el then
                    local elementKey = key
                    el = CreateFrame("Button", nil, self, "BackdropTemplate")
                    el:SetSize(100, 24) -- 默认基准大小
                    el:SetBackdrop(nil)

                    el.text = EXUI:CreateVisualFontString(el, EXFONTFRAME, "GameFontHighlightSmall")
                    el.text:SetPoint("CENTER")

                    -- 拖拽逻辑
                    el:SetMovable(true)
                    el:RegisterForDrag("LeftButton")
                    el:SetScript("OnDragStart", function(s)
                        if self.selectedKey ~= elementKey then self:Select(elementKey) end
                        s:StartMoving()
                    end)
                    el:SetScript("OnDragStop", function(s)
                        s:StopMovingOrSizing()
                        local cx, cy = self:GetCenter()
                        local ex, ey = s:GetCenter()

                        if not cx or not ex then return end

                        -- 计算相对坐标 (相对于 Canvas 中心)
                        local relX = ex - cx
                        local relY = ey - cy

                        -- 吸附逻辑 (简单取整)
                        relX = math.floor(relX + 0.5)
                        relY = math.floor(relY + 0.5)

                        s:ClearAllPoints()
                        s:SetPoint("CENTER", self, "CENTER", relX, relY)

                        local activeCallbacks = self._previewCallbacks
                        if activeCallbacks and activeCallbacks.onMove then
                            activeCallbacks.onMove(elementKey, relX, relY)
                        end
                    end)

                    -- 点击选择
                    el:SetScript("OnClick", function() self:Select(elementKey) end)

                    self.elements[key] = el
                end

                -- 更新样式与位置
                el:Show()
                el.text:SetText(data.label or key)
                el:ClearAllPoints()
                el:SetPoint("CENTER", self, "CENTER", data.x or 0, data.y or 0)

                -- 根据是否选中设置外观
                if self.selectedKey == key then
                    EXUI:SetControlSurface(el, GM.radius.control, MC.blueSoft, MC.focus)
                    el.text:SetTextColor(unpack(MC.lightBlue))
                else
                    EXUI:SetControlSurface(el, GM.radius.control, MC.input, MC.border)
                    el.text:SetTextColor(unpack(MC.text))
                end
            end
        end
    end

    function canvas:Select(key)
        self.selectedKey = key
        -- 刷新外观
        for k, el in pairs(self.elements) do
            if k == key then
                EXUI:SetControlSurface(el, GM.radius.control, MC.blueSoft, MC.focus)
                el.text:SetTextColor(unpack(MC.lightBlue))
            else
                EXUI:SetControlSurface(el, GM.radius.control, MC.input, MC.border)
                el.text:SetTextColor(unpack(MC.text))
            end
        end
        local activeCallbacks = self._previewCallbacks
        if activeCallbacks and activeCallbacks.onSelect then activeCallbacks.onSelect(key) end
    end

    function canvas:ClearSelection()
        self:Select(nil)
    end

    canvas:UpdateElements(canvas._previewData)
    canvas._exCompositeReflow = function(self, nextWidth, nextHeight) self:SetSize(nextWidth, nextHeight) end
    ReflowCompositeGroup(canvas, width, height)
    AttachCompositeRelease(canvas)
    return canvas
end

-- =========================================================
-- 17. 图标设置组 (Icon Settings Group)
-- =========================================================
function EXUI:CreateIconGroup(parent, width, label, db, key, onUpdate, opts)
    opts = type(opts) == "table" and opts or {}
    local groupWidth = width or 750
    -- 窄卡把功能区移到 2x2 字段下方；宽卡继续保持原来的左右结构。
    -- 高度与控件坐标都来自 IconGroupLayout，Grid 测量读同一个函数。
    local groupHeight = IconGroupLayout(groupWidth, opts).height

    -- [关键修复] 获取嵌套子表，如果不存在则初始化
    db = type(db) == "table" and db or {}
    if key and not db[key] then db[key] = {} end
    local iconDb = key and db[key] or db

    -- 图标四项开关的默认状态。nil 视为开启，既兼容旧配置，也让首次打开
    -- 设置页时与当前默认视觉保持一致。
    if iconDb.showIcon == nil then iconDb.showIcon = true end
    if iconDb.showBorder == nil then iconDb.showBorder = true end
    if iconDb.enableCrop == nil then iconDb.enableCrop = true end
    if iconDb.showCooldown == nil then iconDb.showCooldown = true end
    if iconDb.reverse == nil then iconDb.reverse = false end
    if type(iconDb.cooldown) ~= "table" then iconDb.cooldown = {} end
    local cooldownDb = iconDb.cooldown
    if cooldownDb.showSwipe == nil then cooldownDb.showSwipe = true end
    if cooldownDb.swipeAlpha == nil then cooldownDb.swipeAlpha = 0.65 end
    if cooldownDb.showEdge == nil then cooldownDb.showEdge = true end
    if cooldownDb.edgeAlpha == nil then cooldownDb.edgeAlpha = 1 end
    if cooldownDb.showBling == nil then cooldownDb.showBling = false end

    local palette = {
        panel = MC.panel,
        card = MC.raised,
        utility = MC.raised,
        border = MC.border,
        borderSoft = MC.border,
        text = MC.text,
        value = MC.blue,
        accent = MC.blue,
    }

    local container, isNew = AcquireCompositeGroup("CompositeIconGroup", parent)
    container._exCompositeLabel = label or L["图标设置"]
    BindCompositeGroup(container, iconDb, onUpdate, opts)
    if not isNew then
        AttachCompositeRelease(container)
        EXUI:LayoutCompositeGroup(container, groupWidth, groupHeight)
        EXUI:ClearControlSurface(container)
        for _, card in ipairs(container._exIconMetricCards or {}) do
            EXUI:ClearControlSurface(card)
        end
        if container._exIconActionCard then
            EXUI:ClearControlSurface(container._exIconActionCard)
        end
        for _, popup in ipairs(container._exCompositePopups or {}) do
            EXUI:SetControlSurface(popup, GM.radius.card, palette.panel, palette.border)
        end
        for _, line in ipairs(container.crispOutline or {}) do line:Hide() end
        container.crispOutline = nil
        return container
    end
    iconDb = CreateCompositeProxy(container)
    cooldownDb = CreateCompositeProxy(container, "cooldown")
    opts = setmetatable({}, { __index = function(_, field)
        return (container._exCompositeOpts or {})[field]
    end })
    onUpdate = function() CompositeEmitUpdate(container) end

    local function GetIconInputMetadata()
        local activeOpts = container._exCompositeOpts or {}
        local metadata = activeOpts._exWriteContext
        if metadata == nil then return nil end
        if type(metadata) ~= "table" or type(metadata.moduleKey) ~= "string" or metadata.moduleKey == "" then
            error("CreateIconGroup requires Grid write context", 2)
        end
        local prefix = metadata.pathPrefix or metadata.path
        if type(prefix) ~= "string" or prefix == "" then
            error("CreateIconGroup Grid write context requires pathPrefix", 2)
        end
        local commitAPI = EXUI.CommitModuleValue
        if type(commitAPI) ~= "function" then
            error("CreateIconGroup requires its Core commit API", 2)
        end
        return metadata.moduleKey, prefix
    end

    -- IconGroup 的写入上下文只由 Grid 注入；每次值变化都经统一 ModuleDB
    -- 通知重套已存在表面。
    local function WriteIconSliderValue(field, value)
        local target, key = iconDb, field
        local parentPath, childKey = tostring(field):match("^(.*)%.([^%.]+)$")
        if parentPath == "cooldown" then
            target, key = cooldownDb, childKey
        end
        target[key] = value
    end

    local function ReadIconValue(field)
        local parentPath, childKey = tostring(field):match("^(.*)%.([^%.]+)$")
        if parentPath == "cooldown" then return cooldownDb[childKey] end
        return iconDb[field]
    end

    local function CommitIconValue(field, value)
        local moduleKey, prefix = GetIconInputMetadata()
        if moduleKey then
            local payload = {
                moduleKey = moduleKey, path = prefix .. "." .. field,
                readValue = function() return ReadIconValue(field) end,
                writeValue = function(nextValue) WriteIconSliderValue(field, nextValue) end,
            }
            return EXUI:CommitModuleValue(payload, value)
        end
        WriteIconSliderValue(field, value)
        if onUpdate then onUpdate() end
        return true
    end

    local function CreateIconColorTransaction(colorKey)
        local fields = colorKey == "borderColor"
            and { "borderColorR", "borderColorG", "borderColorB", "borderColorA" }
            or { "colorR", "colorG", "colorB", "colorA" }
        return function()
            -- 同 FontGroup：池化色盘必须在点击当下解析当前模块声明。
            local moduleKey, prefix = GetIconInputMetadata()
            if not moduleKey then return nil end
            local payload = {
                moduleKey = moduleKey, path = prefix .. "." .. colorKey,
                readValue = function()
                    return { r = iconDb[fields[1]], g = iconDb[fields[2]], b = iconDb[fields[3]], a = iconDb[fields[4]] }
                end,
                writeValue = function(value)
                    iconDb[fields[1]], iconDb[fields[2]], iconDb[fields[3]], iconDb[fields[4]] = value.r, value.g, value.b, value.a
                end,
            }
            return EXUI:CreateModuleNotifyFlow(payload)
        end
    end

    local function SetIconSliderValue(field, value, phase)
        WriteIconSliderValue(field, value)
        if phase ~= "live" and onUpdate then onUpdate() end
    end

    -- IconGroup 的设置绑定声明输入事务生命周期。每次
    -- 按下均从当前 pooled group 的 opts 解析，绝不复用上一模块的 moduleKey/path；
    local function CreateIconNotifyFlow(field)
        local activeOpts = container._exCompositeOpts or {}
        local transaction = activeOpts._exWriteContext
        if transaction ~= nil then
            if type(transaction) ~= "table" or type(transaction.moduleKey) ~= "string" or transaction.moduleKey == "" then
                error("CreateIconGroup requires Grid write context", 2)
            end
            local prefix = transaction.pathPrefix or transaction.path
            if type(prefix) ~= "string" or prefix == "" then
                error("CreateIconGroup Grid write context requires pathPrefix", 2)
            end
            local createAPI = EXUI.CreateModuleNotifyFlow
            if type(createAPI) ~= "function" then
                error("CreateIconGroup requires its Core transaction API", 2)
            end
            local payload = {
                moduleKey = transaction.moduleKey,
                path = prefix .. "." .. field,
                readValue = function()
                    local target, fieldKey = iconDb, field
                    local parentPath, childKey = tostring(field):match("^(.*)%.([^%.]+)$")
                    if parentPath == "cooldown" then target, fieldKey = cooldownDb, childKey end
                    return target[fieldKey]
                end,
                writeValue = function(value) WriteIconSliderValue(field, value) end,
            }
            return createAPI(EXUI, payload)
        end
        local metadata = activeOpts._exWriteContext
        if metadata == nil then return nil end
        if type(metadata) ~= "table" or type(metadata.moduleKey) ~= "string" or metadata.moduleKey == "" then
            error("CreateIconGroup requires Grid write context", 2)
        end
        local prefix = metadata.pathPrefix or metadata.path
        if type(prefix) ~= "string" or prefix == "" then
            error("CreateIconGroup Grid write context requires pathPrefix", 2)
        end
        if type(EXUI.CreateModuleNotifyFlow) ~= "function" then
            error("CreateIconGroup requires CreateModuleNotifyFlow", 2)
        end
        return EXUI:CreateModuleNotifyFlow({
            moduleKey = metadata.moduleKey,
            path = prefix .. "." .. field,
            readValue = function()
                local target, fieldKey = iconDb, field
                local parentPath, childKey = tostring(field):match("^(.*)%.([^%.]+)$")
                if parentPath == "cooldown" then target, fieldKey = cooldownDb, childKey end
                return target[fieldKey]
            end,
            writeValue = function(value)
                WriteIconSliderValue(field, value)
            end,
            commit = function(value)
                WriteIconSliderValue(field, value)
                if onUpdate then onUpdate() end
            end,
        })
    end

    local function CreateIconSlider(parentFrame, sliderWidth, titleText, field, minValue, maxValue, value, stepValue)
        local lifecycle
        return EXUI:CreateSlider(parentFrame, sliderWidth, titleText, minValue, maxValue, value, stepValue, nil, {
            numberInputPosition = "title",
            showFill = field ~= "x" and field ~= "y" and field ~= "shadowX" and field ~= "shadowY",
            onBegin = function()
                lifecycle = CreateIconNotifyFlow(field)
                if lifecycle and lifecycle.onBegin then lifecycle.onBegin() end
            end,
            onLive = function(v)
                if lifecycle and lifecycle.onLive then lifecycle.onLive(v) else SetIconSliderValue(field, v, "live") end
            end,
            onCommit = function(v)
                -- 同 FontGroup：数字输入是一次性提交，没有拖动期的 onBegin。
                local inputOpts = container._exCompositeOpts or {}
                if not lifecycle and inputOpts._exWriteContext ~= nil then
                    lifecycle = CreateIconNotifyFlow(field)
                end
                if lifecycle and lifecycle.onCommit then
                    lifecycle.onCommit(v)
                    lifecycle = nil
                else
                    SetIconSliderValue(field, v, "commit")
                end
            end,
        })
    end

    container:SetSize(groupWidth, groupHeight)
    EXUI:ClearControlSurface(container)

    local content = CreateFrame("Frame", nil, container)
    content:SetSize(groupWidth, groupHeight)
    content:SetPoint("TOPLEFT", 0, 0)

    -- 左侧默认是 2x2 几何滑条；不需要模块局部图标偏移时可显式隐藏
    -- Position 控件，根锚点仍是该模块唯一的位置来源。
    local gap = COMPOSITE_GAP
    local iconLayout = IconGroupLayout(groupWidth, opts)
    local sliderWidth = iconLayout.itemWidth - COMPOSITE_CONTROL_INSET

    -- 四区：左列（宽度/水平偏移）、右列（高度/垂直偏移）、功能区左列（四个开关）、
    -- 功能区右列（四个设置按钮，与左列开关逐行成对）。坐标由 IconGroupLayout 统一给出。
    local metricsLeft = CreateFrame("Frame", nil, content)
    local metricsRight = CreateFrame("Frame", nil, content)

    local sWidth = CreateIconSlider(metricsLeft, sliderWidth, L["宽度 (Width)"], "width", 10, 300, iconDb.width or 64, 1)
    local sHeight = CreateIconSlider(metricsRight, sliderWidth, L["高度 (Height)"], "height", 10, 300, iconDb.height or 64, 1)

    local sPosX, sPosY
    if opts.hidePositionControls ~= true then
        -- Aura 图标可用较细的偏移范围；排序和间距属于另一张“排序”卡片，绝不由这里重算。
        local offsetMin = tonumber(opts.offsetMin) or -1000
        local offsetMax = tonumber(opts.offsetMax) or 1000
        local offsetStep = tonumber(opts.offsetStep) or 1
        sPosX = CreateIconSlider(metricsLeft, sliderWidth, L["水平偏移 (X)"], "x", offsetMin, offsetMax, iconDb.x or 0, offsetStep)
        sPosY = CreateIconSlider(metricsRight, sliderWidth, L["垂直偏移 (Y)"], "y", offsetMin, offsetMax, iconDb.y or 0, offsetStep)
    end
    container._exIconMetricCards = { metricsLeft, metricsRight }

    -- 四项功能控制区：每一行左侧开关、右侧对应设置按钮。
    local actionCard = CreateFrame("Frame", nil, content)
    container._exIconActionCard = actionCard
    CreateCompositeColumnDivider(content, metricsLeft, metricsLeft, "RIGHT", gap / 2)
    local actionDivider = CreateCompositeColumnDivider(content, actionCard, actionCard, "LEFT", -gap / 2)
    local utilityDivider = actionCard:CreateTexture(nil, "ARTWORK")
    utilityDivider:SetColorTexture(unpack(ExwindTools.GUIColors.sectionDivider))
    utilityDivider:SetWidth(1)

    local cbShow = EXUI:CreateCheckbox(actionCard, L["显示图标"], iconDb.showIcon, function(v)
        CommitIconValue("showIcon", v)
    end)
    local cbShowBorder = EXUI:CreateCheckbox(actionCard, L["显示边框"], iconDb.showBorder, function(v)
        CommitIconValue("showBorder", v)
    end)
    local cbCrop = EXUI:CreateCheckbox(actionCard, L["裁切图标"], iconDb.enableCrop, function(v)
        CommitIconValue("enableCrop", v)
    end)
    local cbCooldown = EXUI:CreateCheckbox(actionCard, L["图标倒数"], iconDb.showCooldown, function(v)
        CommitIconValue("showCooldown", v)
    end)
    -- 开关量统一用开关：标签在左、开关贴右（设置行规格）。
    EXUI:PrepareSettingsListControl(cbShow, { presentation = "switch", labelLeft = true })
    EXUI:PrepareSettingsListControl(cbShowBorder, { presentation = "switch", labelLeft = true })
    EXUI:PrepareSettingsListControl(cbCrop, { presentation = "switch", labelLeft = true })
    EXUI:PrepareSettingsListControl(cbCooldown, { presentation = "switch", labelLeft = true })
    local function CreatePopup(titleText, width, height)
        local popup = CreateCompositePopupHost(container, width, height)
        EXUI:SetControlSurface(popup, GM.radius.card, palette.panel, palette.border)
        popup:Hide()

        local popupTitle = EXUI:CreateVisualFontString(popup, EXFONTFRAME, "GameFontHighlight")
        popupTitle:SetPoint("TOPLEFT", 13, -9)
        popupTitle:SetText(titleText)
        StyleModernTitle(popupTitle)

        local close = EXUI:CreateButton(popup, 28, 24, "×", function()
            popup:Hide()
        end, { compact = true })
        close:SetPoint("TOPRIGHT", -7, -4)
        return popup
    end

    local popupScale = 1.3
    local appearancePopupW = math.floor(400 * popupScale)
    local appearancePopup = CreatePopup(L["外观设置"], appearancePopupW, 254)
    local countdownPopupW, countdownPopupH = math.floor(400 * popupScale), 212
    local countdownPopup = CreatePopup(L["倒数设置"], countdownPopupW, countdownPopupH)
    local appearancePad, appearanceGap = 14, 18
    local appearanceItemW = math.floor((appearancePopupW - appearancePad * 2 - appearanceGap) / 2)

    -- central basicIcon 的图标来源属于业务 item，不是外观 DB；该中央分支不许
    -- CreateIconGroup 偷建/编辑 legacy iconID。旧页面保持原来的可选输入框。
    if opts.hideIconID ~= true then
        local inputIcon = EXUI:CreateEditBox(
            appearancePopup,
            tostring(iconDb.iconID or ""),
            appearanceItemW,
            GM.size.inputHeight,
            L["图标ID (可选)"],
            {
                onEnter = function(v)
                    CommitIconValue("iconID", tonumber(v) or nil)
                end,
                onEditFocusLost = function(v)
                    CommitIconValue("iconID", tonumber(v) or nil)
                end,
                labelPos = "top"
            }
        )
        inputIcon:SetPoint("TOPLEFT", appearancePad, -44)
    end

    local alpha = CreateIconSlider(appearancePopup, appearanceItemW, L["图标透明度"], "alpha", 0, 1,
        tonumber(iconDb.alpha) or 1, 0.05)
    alpha:SetPoint("TOPLEFT", appearancePad + appearanceItemW + appearanceGap, -40)

    local cbDesaturated = EXUI:CreateCheckbox(appearancePopup, L["图标变灰"], iconDb.desaturated, function(v)
        CommitIconValue("desaturated", v)
    end)
    cbDesaturated:SetPoint("TOPLEFT", appearancePad, -92)
    local iconColor = EXUI:CreateColorButton(appearancePopup, L["图标染色"], iconDb, "color", true, onUpdate,
        { _changeFlow = CreateIconColorTransaction("color") })
    iconColor:SetPoint("TOPLEFT", appearancePad, -128)

    local blendDrop = EXUI:CreateDropdown(appearancePopup, appearanceItemW, L["混合模式"], {
        { "BLEND", "BLEND" },
        { "ADD", "ADD" },
        { "MOD", "MOD" },
        { "ALPHAKEY", "ALPHAKEY" },
        { "DISABLE", "DISABLE" },
    }, iconDb.blendMode or "BLEND", function(v)
        CommitIconValue("blendMode", v)
    end)
    blendDrop:SetPoint("TOPLEFT", appearancePad + appearanceItemW + appearanceGap, -132)

    local rotation = CreateIconSlider(appearancePopup, appearanceItemW, L["旋转角度"], "rotation", -180, 180,
        tonumber(iconDb.rotation) or 0, 1)
    rotation:SetPoint("TOPLEFT", appearancePad, -202)

    local popupW, popupH = math.floor(580 * popupScale), 154
    local cropPopup = CreatePopup(L["裁切设置"], popupW, popupH)
    local borderPopup = CreatePopup(L["边框设置"], popupW, popupH)
    local popupPad, popupGap = 14, 18
    local popupItemW = math.floor((popupW - popupPad * 2 - popupGap) / 2)
    local popupCol1 = popupPad
    local popupCol2 = popupCol1 + popupItemW + popupGap

    local cropLeft = CreateIconSlider(cropPopup, popupItemW, L["裁切左 (Crop Left)"], "cropLeft", 0, 1,
        tonumber(iconDb.cropLeft) or 0.08, 0.01)
    cropLeft:SetPoint("TOPLEFT", popupCol1, -48)

    local cropRight = CreateIconSlider(cropPopup, popupItemW, L["裁切右 (Crop Right)"], "cropRight", 0, 1,
        tonumber(iconDb.cropRight) or 0.92, 0.01)
    cropRight:SetPoint("TOPLEFT", popupCol2, -48)

    local cropTop = CreateIconSlider(cropPopup, popupItemW, L["裁切上 (Crop Top)"], "cropTop", 0, 1,
        tonumber(iconDb.cropTop) or 0.08, 0.01)
    cropTop:SetPoint("TOPLEFT", popupCol1, -101)

    local cropBottom = CreateIconSlider(cropPopup, popupItemW, L["裁切下 (Crop Bottom)"], "cropBottom", 0, 1,
        tonumber(iconDb.cropBottom) or 0.92, 0.01)
    cropBottom:SetPoint("TOPLEFT", popupCol2, -101)

    local borderBtn = EXUI:CreateColorButton(borderPopup, L["边框颜色"], iconDb, "borderColor", true, onUpdate,
        { _changeFlow = CreateIconColorTransaction("borderColor") })
    borderBtn:SetPoint("TOPLEFT", popupCol1, -48)

    local borderDrop = EXUI:CreateLSMTextureDropdown(borderPopup, "border", popupItemW, L["边框材质"],
        iconDb.borderTexture or "None",
        function(k)
            CommitIconValue("borderTexture", k)
        end)
    borderDrop:SetPoint("TOPLEFT", popupCol2, -48)

    local sBorderSize = CreateIconSlider(borderPopup, popupItemW, L["边框粗细"], "borderSize", -10, 10,
        iconDb.borderSize or 1, 0.1)
    sBorderSize:SetPoint("TOPLEFT", popupCol1, -101)

    local sBorderPad = CreateIconSlider(borderPopup, popupItemW, L["边框间距 (Padding)"], "borderPadding", -10, 10,
        iconDb.borderPadding or 0, 0.1)
    sBorderPad:SetPoint("TOPLEFT", popupCol2, -101)

    -- 图标倒数的原生扇形视觉全部收口于此；数字文本由统一文本控件接管。
    local cbReverse = EXUI:CreateCheckbox(countdownPopup, L["倒数反转"], iconDb.reverse, function(v)
        CommitIconValue("reverse", v)
    end)
    cbReverse:SetPoint("TOPLEFT", 14, -42)
    cbReverse:SetSize(156, GM.size.checkboxRowHeight)
    local countdownPad, countdownGap = 14, 18
    local countdownItemW = math.floor((countdownPopupW - countdownPad * 2 - countdownGap) / 2)
    local countdownCol2 = countdownPad + countdownItemW + countdownGap

    local cbSwipe = EXUI:CreateCheckbox(countdownPopup, L["启用扇形倒数"], cooldownDb.showSwipe, function(v)
        CommitIconValue("cooldown.showSwipe", v)
    end)
    cbSwipe:SetPoint("TOPLEFT", countdownCol2, -42)
    cbSwipe:SetSize(156, GM.size.checkboxRowHeight)
    local cbEdge = EXUI:CreateCheckbox(countdownPopup, L["显示边缘光"], cooldownDb.showEdge, function(v)
        CommitIconValue("cooldown.showEdge", v)
    end)
    cbEdge:SetPoint("TOPLEFT", countdownPad, -76)
    cbEdge:SetSize(156, GM.size.checkboxRowHeight)
    local cbBling = EXUI:CreateCheckbox(countdownPopup, L["倒数结束闪光"], cooldownDb.showBling, function(v)
        CommitIconValue("cooldown.showBling", v)
    end)
    cbBling:SetPoint("TOPLEFT", countdownCol2, -76)
    cbBling:SetSize(176, GM.size.checkboxRowHeight)
    local swipeAlpha = CreateIconSlider(countdownPopup, countdownItemW, L["扇形透明度"], "cooldown.swipeAlpha", 0, 1,
        cooldownDb.swipeAlpha, 0.05)
    swipeAlpha:SetPoint("TOPLEFT", countdownPad, -128)

    local edgeAlpha = CreateIconSlider(countdownPopup, countdownItemW, L["边缘光透明度"], "cooldown.edgeAlpha", 0, 1,
        cooldownDb.edgeAlpha, 0.05)
    edgeAlpha:SetPoint("TOPLEFT", countdownCol2, -128)

    local function TogglePopup(popup, anchor, point, relativePoint)
        local shouldShow = not popup:IsShown()
        appearancePopup:Hide()
        cropPopup:Hide()
        borderPopup:Hide()
        countdownPopup:Hide()
        if shouldShow then
            popup:ClearAllPoints()
            popup:SetPoint(point, anchor, relativePoint, 0, -6)
            popup:Show()
        end
    end

    -- 功能按钮与普通页面按钮共享同一构造器和状态 painter。
    local function CreateUtilityButton(text, width, onClick)
        return EXUI:CreateButton(actionCard, width, GM.size.buttonHeight, text, onClick, { variant = "secondary" })
    end

    local buttonWidth = iconLayout.actionColumnWidth
    local appearanceButton = CreateUtilityButton(L["外观设置"], buttonWidth, function(self)
        TogglePopup(appearancePopup, self, "TOPRIGHT", "BOTTOMRIGHT")
    end)

    local borderButton = CreateUtilityButton(L["边框设置"], buttonWidth, function(self)
        TogglePopup(borderPopup, self, "TOPRIGHT", "BOTTOMRIGHT")
    end)

    local cropButton = CreateUtilityButton(L["裁切设置"], buttonWidth, function(self)
        TogglePopup(cropPopup, self, "TOPRIGHT", "BOTTOMRIGHT")
    end)

    local countdownButton = CreateUtilityButton(L["倒数设置"], buttonWidth, function(self)
        TogglePopup(countdownPopup, self, "TOPRIGHT", "BOTTOMRIGHT")
    end)

    container:HookScript("OnHide", function()
        appearancePopup:Hide()
        cropPopup:Hide()
        borderPopup:Hide()
        countdownPopup:Hide()
    end)

    RegisterCompositeControl(container, sWidth, "width", "slider")
    RegisterCompositeControl(container, sHeight, "height", "slider")
    if sPosX then RegisterCompositeControl(container, sPosX, "x", "slider") end
    if sPosY then RegisterCompositeControl(container, sPosY, "y", "slider") end
    RegisterCompositeControl(container, cbShow, "showIcon", "check")
    RegisterCompositeControl(container, cbShowBorder, "showBorder", "check")
    RegisterCompositeControl(container, cbCrop, "enableCrop", "check")
    RegisterCompositeControl(container, cbCooldown, "showCooldown", "check")
    RegisterCompositeControl(container, inputIcon, "iconID", "edit")
    RegisterCompositeControl(container, alpha, "alpha", "slider", nil, 1)
    RegisterCompositeControl(container, cbDesaturated, "desaturated", "check")
    RegisterCompositeControl(container, iconColor, "color", "color")
    RegisterCompositeControl(container, blendDrop, "blendMode", "dropdown", nil, "BLEND")
    RegisterCompositeControl(container, rotation, "rotation", "slider")
    RegisterCompositeControl(container, cropLeft, "cropLeft", "slider", nil, 0.08)
    RegisterCompositeControl(container, cropRight, "cropRight", "slider", nil, 0.92)
    RegisterCompositeControl(container, cropTop, "cropTop", "slider", nil, 0.08)
    RegisterCompositeControl(container, cropBottom, "cropBottom", "slider", nil, 0.92)
    RegisterCompositeControl(container, borderBtn, "borderColor", "color")
    RegisterCompositeControl(container, borderDrop, "borderTexture", "dropdown", nil, "None")
    RegisterCompositeControl(container, sBorderSize, "borderSize", "slider", nil, 1)
    RegisterCompositeControl(container, sBorderPad, "borderPadding", "slider")
    RegisterCompositeControl(container, cbReverse, "reverse", "check")
    RegisterCompositeControl(container, cbSwipe, "cooldown.showSwipe", "check")
    RegisterCompositeControl(container, cbEdge, "cooldown.showEdge", "check")
    RegisterCompositeControl(container, cbBling, "cooldown.showBling", "check")
    RegisterCompositeControl(container, swipeAlpha, "cooldown.swipeAlpha", "slider")
    RegisterCompositeControl(container, edgeAlpha, "cooldown.edgeAlpha", "slider")
    container._exCompositePopups = { appearancePopup, cropPopup, borderPopup, countdownPopup }
    container._iconGroupDb = iconDb
    -- 宽窄两种布局都由同一次 IconGroupLayout 决定；Grid 测量读同一个函数。
    container._exCompositeReflow = function(self, nextWidth)
        local layout = IconGroupLayout(nextWidth, opts)
        local nextSliderWidth = layout.itemWidth - COMPOSITE_CONTROL_INSET
        local columnWidth, leftX, rightX = layout.actionColumnWidth, layout.actionLeftX, layout.actionRightX

        self:SetSize(nextWidth, layout.height)
        content:ClearAllPoints()
        content:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
        content:SetSize(nextWidth, layout.height)
        EXUI:ClearControlSurface(self)

        metricsLeft:ClearAllPoints(); metricsLeft:SetPoint("TOPLEFT", content, "TOPLEFT", layout.col1, -layout.metricsTop)
        metricsLeft:SetSize(layout.itemWidth, layout.metricsHeight)
        metricsRight:ClearAllPoints(); metricsRight:SetPoint("TOPLEFT", content, "TOPLEFT", layout.col2, -layout.metricsTop)
        metricsRight:SetSize(layout.itemWidth, layout.metricsHeight)
        local leftTops, rightTops = layout.metricLeftTops, layout.metricRightTops
        PlaceCompositeControl(sWidth, metricsLeft, COMPOSITE_CONTROL_X, leftTops[1], nextSliderWidth)
        PlaceCompositeControl(sHeight, metricsRight, COMPOSITE_CONTROL_X, rightTops[1], nextSliderWidth)
        if sPosX then PlaceCompositeControl(sPosX, metricsLeft, COMPOSITE_CONTROL_X, leftTops[2], nextSliderWidth) end
        if sPosY then PlaceCompositeControl(sPosY, metricsRight, COMPOSITE_CONTROL_X, rightTops[2], nextSliderWidth) end

        actionCard:ClearAllPoints()
        actionCard:SetPoint("TOPLEFT", content, "TOPLEFT", layout.controlX, -layout.actionTop)
        actionCard:SetSize(layout.controlWidth, layout.actionHeight)
        actionDivider:SetShown(not layout.narrow)
        LayoutCompositeActionDivider(utilityDivider, actionCard, layout.controlWidth)
        local checkHeight = GM.size.checkboxRowHeight
        local actionRows = layout.actionRows
        for index, checkbox in ipairs({ cbShow, cbShowBorder, cbCrop, cbCooldown }) do
            PlaceCompositeControl(checkbox, actionCard, leftX,
                CompositeAlignedY(layout.leftTops[index], actionRows[index], checkHeight),
                columnWidth, checkHeight)
        end
        for index, button in ipairs({ appearanceButton, borderButton, cropButton, countdownButton }) do
            PlaceCompositeControl(button, actionCard, rightX,
                CompositeAlignedY(layout.rightTops[index], actionRows[index], GM.size.buttonHeight),
                columnWidth, GM.size.buttonHeight)
        end
    end
    EXUI:LayoutCompositeGroup(container, groupWidth, groupHeight)
    AttachCompositeRelease(container)

    return container
end

-- =========================================================
-- 18. 计时条设置组（TimerBarWidget 对应的配置 GUI）
-- =========================================================
function EXUI:CreateTimerBarGroup(parent, width, label, db, key, onUpdate, opts)
    if key and type(db) == "table" then
        db[key] = type(db[key]) == "table" and db[key] or {}
        db = db[key]
    end
    db = type(db) == "table" and db or {}
    opts = type(opts) == "table" and opts or {}
    local iconOffsetMin = tonumber(opts.iconOffsetMin) or -200
    local iconOffsetMax = tonumber(opts.iconOffsetMax) or 200
    local defaults = {
        width = 240, height = 24, x = 0, y = 0,
        texture = "Clean",
        barColorR = 1, barColorG = 0.7, barColorB = 0, barColorA = 1,
        barBgColorR = 0, barBgColorG = 0, barBgColorB = 0, barBgColorA = 0.5,
        showBorder = true, borderTexture = "None", borderSize = 1, borderPadding = 0,
        borderColorR = 1, borderColorG = 1, borderColorB = 1, borderColorA = 1,
        showIcon = true, iconWidth = 24, iconHeight = 24, iconSide = "LEFT",
        iconOffsetX = -5, iconOffsetY = 0,
        showIconBorder = true, iconBorderTexture = "None", iconBorderSize = 1, iconBorderPadding = 0,
        iconBorderColorR = 1, iconBorderColorG = 1, iconBorderColorB = 1, iconBorderColorA = 1,
        fillMode = opts.fillModeOnly == true and "LTR_FILL" or "RTL_DRAIN", fillDirection = "LEFT_TO_RIGHT", progressMode = "REMAINING",
    }
    if opts.fillModeOnly == true then
        defaults.fillDirection, defaults.progressMode = nil, nil
    end
    for field, value in pairs(defaults) do
        if db[field] == nil then db[field] = value end
    end
    local groupWidth = width or 975
    local groupHeight = TimerBarGroupLayout(groupWidth, opts).height
    -- 层数条复用计时条的尺寸／材质／颜色／边框控件，但没有 duration、图标或填充模式语义。
    -- 使用独立对象池，避免普通计时条和层数条之间残留可见控件。
    local poolType = opts.applicationBar == true and "CompositeTimerBarApplicationGroup" or "CompositeTimerBarGroup"
    local group, isNew = AcquireCompositeGroup(poolType, parent)
    group._exCompositeLabel = label or L["计时条设置"]
    BindCompositeGroup(group, db, onUpdate, opts)
    -- TimerBar 的真实 DB 路径只由 Grid 的私有写入上下文提供。
    local function CreateTimerBarNotifyFlow(field)
        local metadata = group._exCompositeOpts and group._exCompositeOpts._exWriteContext
        if metadata == nil then return nil end
        if type(metadata) ~= "table" or type(metadata.moduleKey) ~= "string" or metadata.moduleKey == ""
            or type(metadata.pathPrefix) ~= "string" then
            error("CreateTimerBarGroup requires Grid write context", 2)
        end
        if type(EXUI.CreateModuleNotifyFlow) ~= "function" then
            error("CreateTimerBarGroup requires CreateModuleNotifyFlow", 2)
        end
        return EXUI:CreateModuleNotifyFlow({
            moduleKey = metadata.moduleKey,
            path = metadata.pathPrefix .. "." .. field,
            readValue = function() return db[field] end,
            writeValue = function(value) db[field] = value end,
            commit = function(value)
                db[field] = value
                CompositeEmitUpdate(group)
            end,
        })
    end
    -- 已声明的 TimerBarGroup 全部控件均走统一通知流。
    local function CreateTimerBarNotifyFlowForValue(field, readValue, writeValue)
        local activeOpts = group._exCompositeOpts or {}
        local metadata = activeOpts._exWriteContext
        if metadata == nil then return nil end
        if type(metadata) ~= "table" or type(metadata.moduleKey) ~= "string" or metadata.moduleKey == ""
            or type(metadata.pathPrefix) ~= "string" or metadata.pathPrefix == "" then
            error("CreateTimerBarGroup requires Grid write context", 2)
        end
        local createAPI = EXUI.CreateModuleNotifyFlow
        if type(createAPI) ~= "function" then
            error("CreateTimerBarGroup requires CreateModuleNotifyFlow", 2)
        end
        return createAPI(EXUI, {
            moduleKey = metadata.moduleKey,
            path = metadata.pathPrefix .. "." .. field,
            readValue = readValue or function() return db[field] end,
            writeValue = writeValue or function(value) db[field] = value end,
        })
    end
    group._timerBarFillModeOnly = opts.fillModeOnly == true
    if not isNew then
        -- 下拉菜单由对象池复用，但严格 TimerBar 与旧模块的 fill 值集合不同。
        -- 每次借用都必须覆盖菜单与当前值，不能保留上一次页面的项目或闭包语义。
        local fillMode = group._timerBarFillModeDropdown
        if not fillMode then
            error("CreateTimerBarGroup: pooled group is missing fillMode dropdown", 2)
        end
        fillMode._items = group._timerBarFillModeOnly and {
            { L["左到右填满"], "LTR_FILL" }, { L["左到右消退"], "LTR_FADE" },
            { L["右到左填满"], "RTL_FILL" }, { L["右到左消退"], "RTL_FADE" },
        } or {
            { L["左到右填满"], "LTR_FILL" }, { L["左到右消退"], "LTR_DRAIN" },
            { L["右到左填满"], "RTL_FILL" }, { L["右到左消退"], "RTL_DRAIN" },
        }
        fillMode._currentValue = db.fillMode
        SetDropdownDisplayText(fillMode, CompositeDropdownText(db.fillMode, fillMode._items) or L["请选择..."])
        AttachCompositeRelease(group)
        EXUI:LayoutCompositeGroup(group, groupWidth, groupHeight)
        EXUI:ClearControlSurface(group)
        return group
    end
    local proxy = CreateCompositeProxy(group)
    db = proxy

    local function EmitUpdate() CompositeEmitUpdate(group) end
    local function GetTimerBarInputMetadata()
        local activeOpts = group._exCompositeOpts or {}
        local metadata = activeOpts._exWriteContext
        if metadata == nil then return nil end
        if type(metadata) ~= "table" or type(metadata.moduleKey) ~= "string" or metadata.moduleKey == ""
            or type(metadata.pathPrefix) ~= "string" or metadata.pathPrefix == "" then
            error("CreateTimerBarGroup requires Grid write context", 2)
        end
        local commitAPI = EXUI.CommitModuleValue
        if type(commitAPI) ~= "function" then
            error("CreateTimerBarGroup requires CommitModuleValue", 2)
        end
        return metadata.moduleKey, metadata.pathPrefix
    end
    local function CommitTimerBarValue(field, value, writeValue)
        local moduleKey, prefix = GetTimerBarInputMetadata()
        local Write = writeValue or function(nextValue) db[field] = nextValue end
        if moduleKey then
            return EXUI:CommitModuleValue({
                moduleKey = moduleKey, path = prefix .. "." .. field,
                readValue = function() return db[field] end, writeValue = Write,
            }, value)
        end
        Write(value)
        EmitUpdate()
        return true
    end
    local palette = {
        panel = MC.panel, card = MC.raised,
        utility = MC.input, border = MC.border,
        text = MC.text, value = MC.blue,
    }
    local flatBackdrop = {
        bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    }
    group:SetSize(groupWidth, groupHeight)
    EXUI:ClearControlSurface(group)

    local content = CreateFrame("Frame", nil, group)
    content:SetSize(groupWidth, groupHeight); content:SetPoint("TOPLEFT", 0, 0)
    local gap = COMPOSITE_GAP
    local timerLayout = TimerBarGroupLayout(groupWidth, opts)
    local sliderWidth = timerLayout.itemWidth - COMPOSITE_CONTROL_INSET

    -- 四区：左列（宽度/X/颜色）、右列（高度/Y/材质）、功能区左列（开关+标签）、
    -- 功能区右列（三个设置按钮，与左列逐行成对）。三行共用同一组行基线，
    -- 坐标由 TimerBarGroupLayout 统一给出。
    local metricsLeft = CreateFrame("Frame", nil, content)
    local metricsRight = CreateFrame("Frame", nil, content)
    local function AddSlider(card, titleText, field, min, max, step)
        local lifecycle, transaction
        local slider = EXUI:CreateSlider(card, sliderWidth, titleText, min, max, db[field], step, nil, {
            numberInputPosition = "title",
            showFill = field ~= "x" and field ~= "y" and field ~= "shadowX" and field ~= "shadowY",
            onBegin = function()
                transaction = CreateTimerBarNotifyFlowForValue(field)
                if transaction then transaction.onBegin(); return end
                lifecycle = CreateTimerBarNotifyFlow(field)
                if lifecycle and lifecycle.onBegin then lifecycle.onBegin() end
            end,
            onLive = function(value)
                if transaction then return transaction.onLive(value) end
                if lifecycle and lifecycle.onLive then return lifecycle.onLive(value) end
                db[field] = value
            end,
            onCommit = function(value)
                -- 输入框路径没有 onBegin；按提交当下的声明建立同一事务。
                if not transaction then transaction = CreateTimerBarNotifyFlowForValue(field) end
                if transaction then
                    local result = transaction.onCommit(value)
                    transaction = nil
                    return result
                end
                if lifecycle and lifecycle.onCommit then
                    local result = lifecycle.onCommit(value)
                    lifecycle = nil
                    return result
                end
                db[field] = value
                EmitUpdate()
            end,
        })
        return RegisterCompositeControl(group, slider, field, "slider")
    end
    -- 边框/图标弹窗里的数值控件也必须遵守与主面板同一 live 合同：
    -- 拖动仅重套已物化视觉，松手才统一广播 DatabaseChanged。
    local function AddPopupSlider(parent, sliderWidth, titleText, field, min, max, step)
        local lifecycle, transaction
        local slider = EXUI:CreateSlider(parent, sliderWidth, titleText, min, max, db[field], step, nil, {
            numberInputPosition = "title",
            showFill = field ~= "x" and field ~= "y" and field ~= "shadowX" and field ~= "shadowY",
            onBegin = function()
                transaction = CreateTimerBarNotifyFlowForValue(field)
                if transaction then transaction.onBegin(); return end
                lifecycle = CreateTimerBarNotifyFlow(field)
                if lifecycle and lifecycle.onBegin then lifecycle.onBegin() end
            end,
            onLive = function(value)
                if transaction then return transaction.onLive(value) end
                if lifecycle and lifecycle.onLive then return lifecycle.onLive(value) end
                db[field] = value
            end,
            onCommit = function(value)
                -- 弹窗 Slider 的数字输入也必须走同一条事务。
                if not transaction then transaction = CreateTimerBarNotifyFlowForValue(field) end
                if transaction then
                    local result = transaction.onCommit(value)
                    transaction = nil
                    return result
                end
                if lifecycle and lifecycle.onCommit then
                    local result = lifecycle.onCommit(value)
                    lifecycle = nil
                    return result
                end
                db[field] = value
                EmitUpdate()
            end,
        })
        return slider
    end
    local widthSlider = AddSlider(metricsLeft, L["宽度 (Width)"], "width", 50, 800, 1)
    local heightSlider = AddSlider(metricsRight, L["高度 (Height)"], "height", 8, 120, 1)
    local xSlider = AddSlider(metricsLeft, L["X 轴偏移"], "x", -1000, 1000, 1)
    local ySlider = AddSlider(metricsRight, L["Y 轴偏移"], "y", -1000, 1000, 1)

    -- 第三行：两个半宽颜色按钮 + 一项 LSM 条体材质。
    local function CreateColorTransaction(field)
        return function()
            return CreateTimerBarNotifyFlowForValue(field,
                function()
                    return { r = db[field .. "R"], g = db[field .. "G"], b = db[field .. "B"], a = db[field .. "A"] }
                end,
                function(value)
                    db[field .. "R"], db[field .. "G"], db[field .. "B"], db[field .. "A"] = value.r, value.g, value.b, value.a
                end)
        end
    end
    -- 前景在左列、背景在右列，各占整列宽：半宽时色块加内边距会把标签挤掉。
    local fgButton = EXUI:CreateColorButton(metricsLeft, L["前景"], db, "barColor", true, EmitUpdate,
        { _changeFlow = CreateColorTransaction("barColor") })
    local bgButton = EXUI:CreateColorButton(metricsRight, L["背景"], db, "barBgColor", true, EmitUpdate,
        { _changeFlow = CreateColorTransaction("barBgColor") })
    -- 条体材质下拉落在底部跨整行槽，宽度占满卡片整行。
    local textureDrop = EXUI:CreateLSMTextureDropdown(content, "statusbar", sliderWidth, L["LSM皮肤"], db.texture, function(value)
        CommitTimerBarValue("texture", value)
    end)

    local actionCard = CreateFrame("Frame", nil, content)
    CreateCompositeColumnDivider(content, metricsLeft, metricsLeft, "RIGHT", gap / 2)
    local columnsDivider = CreateCompositeColumnDivider(content, actionCard, actionCard, "LEFT", -gap / 2)
    local function ActionButton(text, callback)
        return EXUI:CreateButton(actionCard, timerLayout.actionColumnWidth, GM.size.buttonHeight,
            text, callback, { variant = "secondary" })
    end

    local popupList = {}
    local function CreatePopup(titleText, popupWidth, popupHeight)
        local popup = CreateCompositePopupHost(group, popupWidth, popupHeight)
        popup:SetBackdrop(flatBackdrop); popup:SetBackdropColor(unpack(palette.panel)); popup:SetBackdropBorderColor(unpack(palette.border)); popup:Hide()
        local popupTitle = EXUI:CreateVisualFontString(popup, EXFONTFRAME, "GameFontHighlight")
        popupTitle:SetPoint("TOPLEFT", 13, -9); popupTitle:SetText(titleText)
        StyleModernTitle(popupTitle)
        local close = EXUI:CreateButton(popup, 28, 24, "×", function() popup:Hide() end, { compact = true })
        close:SetPoint("TOPRIGHT", -7, -4)
        popupList[#popupList + 1] = popup
        return popup
    end
    local function TogglePopup(popup, anchor)
        local show = not popup:IsShown()
        for _, other in ipairs(popupList) do other:Hide() end
        if show then popup:ClearAllPoints(); popup:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -6); popup:Show() end
    end

    local borderPopup = CreatePopup(L["边框设置"], 540, 166)
    local borderTexture = EXUI:CreateLSMTextureDropdown(borderPopup, "border", 245, L["边框材质"], db.borderTexture, function(value)
        CommitTimerBarValue("borderTexture", value)
    end)
    borderTexture:SetPoint("TOPLEFT", 14, -46)
    local borderColor = EXUI:CreateColorButton(borderPopup, L["边框颜色"], db, "borderColor", true, EmitUpdate,
        { _changeFlow = CreateColorTransaction("borderColor") })
    borderColor:SetPoint("TOPLEFT", 280, -42)
    local borderSize = AddPopupSlider(borderPopup, 245, L["边框粗细"], "borderSize", 0, 20, 0.1)
    borderSize:SetPoint("TOPLEFT", 14, -112)
    local borderPad = AddPopupSlider(borderPopup, 245, L["边框间距 (Padding)"], "borderPadding", -10, 10, 0.1)
    borderPad:SetPoint("TOPLEFT", 280, -112)

    local iconPopup = CreatePopup(L["图标设置"], 700, 286 + GM.size.sliderHeight + 14)
    local iconColumnWidth, iconColumn2 = 320, 362
    local iconSides = { { L["左侧"], "LEFT" }, { L["中间"], "CENTER" }, { L["右侧"], "RIGHT" } }
    local iconSide = EXUI:CreateDropdown(iconPopup, iconColumnWidth, L["图标位置"], iconSides, db.iconSide, function(value)
        CommitTimerBarValue("iconSide", value)
    end)
    iconSide:SetPoint("TOPLEFT", 14, -46)
    -- 坐标最终由 Widget 按物理像素对齐；和条/文字/材质的其它位置控件一致，
    -- 必须使用整数步进。0.1 会把 -200..200 扩成 4,000 个原生 Slider 档位，
    -- 但不会产生额外可见位置，反而只让这两个拖动控件异常迟滞。
    local iconOffsetX = AddPopupSlider(iconPopup, iconColumnWidth, L["图标 X 轴偏移"], "iconOffsetX", iconOffsetMin, iconOffsetMax, 1)
    iconOffsetX:SetPoint("TOPLEFT", iconColumn2, -46)
    local iconWidth = AddPopupSlider(iconPopup, iconColumnWidth, L["图标宽度"], "iconWidth", 8, 160, 1)
    iconWidth:SetPoint("TOPLEFT", 14, -100)
    local iconHeight = AddPopupSlider(iconPopup, iconColumnWidth, L["图标高度"], "iconHeight", 8, 160, 1)
    iconHeight:SetPoint("TOPLEFT", iconColumn2, -100)
    local iconOffsetY = AddPopupSlider(iconPopup, iconColumnWidth, L["图标 Y 轴偏移"], "iconOffsetY", iconOffsetMin, iconOffsetMax, 1)
    iconOffsetY:SetPoint("TOPLEFT", 14, -154)
    local showIconBorder = EXUI:CreateCheckbox(iconPopup, L["显示图标边框"], db.showIconBorder, function(value)
        CommitTimerBarValue("showIconBorder", value)
    end)
    showIconBorder:SetPoint("TOPLEFT", iconColumn2, -154)
    local iconBorderTexture = EXUI:CreateLSMTextureDropdown(iconPopup, "border", iconColumnWidth, L["图标边框材质"], db.iconBorderTexture, function(value)
        CommitTimerBarValue("iconBorderTexture", value)
    end)
    iconBorderTexture:SetPoint("TOPLEFT", 14, -232)
    local iconBorderColor = EXUI:CreateColorButton(iconPopup, L["图标边框颜色"], db, "iconBorderColor", true, EmitUpdate,
        { _changeFlow = CreateColorTransaction("iconBorderColor") })
    iconBorderColor:SetPoint("TOPLEFT", iconColumn2, -228)
    local iconBorderSize = AddPopupSlider(iconPopup, iconColumnWidth, L["图标边框粗细"], "iconBorderSize", 0, 20, 0.1)
    iconBorderSize:SetPoint("TOPLEFT", 14, -286)
    local iconBorderPad = AddPopupSlider(iconPopup, iconColumnWidth, L["图标边框间距"], "iconBorderPadding", -10, 10, 0.1)
    iconBorderPad:SetPoint("TOPLEFT", iconColumn2, -286)

    local fillPopup = CreatePopup(L["填充设置"], 540, 126)
    local fillOptions = opts.fillModeOnly == true and {
        { L["左到右填满"], "LTR_FILL" }, { L["左到右消退"], "LTR_FADE" },
        { L["右到左填满"], "RTL_FILL" }, { L["右到左消退"], "RTL_FADE" },
    } or {
        { L["左到右填满"], "LTR_FILL" }, { L["左到右消退"], "LTR_DRAIN" },
        { L["右到左填满"], "RTL_FILL" }, { L["右到左消退"], "RTL_DRAIN" },
    }
    local fillMode = EXUI:CreateDropdown(fillPopup, 510, L["填充方式"], fillOptions, db.fillMode, function(value)
        local function WriteFillMode(nextValue)
            db.fillMode = nextValue
            if group._timerBarFillModeOnly == true then return end
            if nextValue == "LTR_FILL" then db.fillDirection, db.progressMode = "LEFT_TO_RIGHT", "ELAPSED"
            elseif nextValue == "LTR_DRAIN" then db.fillDirection, db.progressMode = "RIGHT_TO_LEFT", "REMAINING"
            elseif nextValue == "RTL_FILL" then db.fillDirection, db.progressMode = "RIGHT_TO_LEFT", "ELAPSED"
            else db.fillDirection, db.progressMode = "LEFT_TO_RIGHT", "REMAINING" end
        end
        if group._timerBarFillModeOnly == true then
            CommitTimerBarValue("fillMode", value, WriteFillMode)
            return
        end
        CommitTimerBarValue("fillMode", value, WriteFillMode)
    end)
    fillMode:SetPoint("TOPLEFT", 14, -46)
    group._timerBarFillModeDropdown = fillMode

    local showIcon = EXUI:CreateCheckbox(actionCard, L["显示图标"], db.showIcon, function(value)
        CommitTimerBarValue("showIcon", value)
    end)
    local iconButton = ActionButton(L["图标设置"], function(self) TogglePopup(iconPopup, self) end)

    local showBorder = EXUI:CreateCheckbox(actionCard, L["显示边框"], db.showBorder, function(value)
        CommitTimerBarValue("showBorder", value)
    end)
    -- 开关量统一用开关：标签在左、开关贴右（设置行规格）。
    EXUI:PrepareSettingsListControl(showIcon, { presentation = "switch", labelLeft = true })
    EXUI:PrepareSettingsListControl(showBorder, { presentation = "switch", labelLeft = true })
    local borderButton = ActionButton(L["边框设置"], function(self) TogglePopup(borderPopup, self) end)

    local fillLabel = EXUI:CreateVisualFontString(actionCard, EXFONTFRAME, "GameFontHighlight")
    -- LEFT 锚点的 Y 偏移从垂直中线计算，会把文字推到卡片外；必须以 TOPLEFT 定位（见 _exCompositeReflow）。
    fillLabel:SetText(L["填充方式"])
    fillLabel:SetJustifyV("MIDDLE")
    StyleModernTitle(fillLabel)
    local fillButton = ActionButton(L["填充设置"], function(self) TogglePopup(fillPopup, self) end)

    local actionDivider = actionCard:CreateTexture(nil, "ARTWORK")
    actionDivider:SetColorTexture(unpack(ExwindTools.GUIColors.sectionDivider))
    actionDivider:SetWidth(1)

    if opts.applicationBar == true then
        -- ApplicationBar 的进度和法术图标由原生 Aura 绑定决定；这些控制项写入数据却
        -- 不会影响原生条，故不向用户显示。
        showIcon:Hide()
        iconButton:Hide()
        fillLabel:Hide()
        fillButton:Hide()
        iconPopup:Hide()
        fillPopup:Hide()
    end

    RegisterCompositeControl(group, fgButton, "barColor", "color")
    RegisterCompositeControl(group, bgButton, "barBgColor", "color")
    RegisterCompositeControl(group, textureDrop, "texture", "dropdown")
    RegisterCompositeControl(group, borderTexture, "borderTexture", "dropdown")
    RegisterCompositeControl(group, borderColor, "borderColor", "color")
    RegisterCompositeControl(group, borderSize, "borderSize", "slider")
    RegisterCompositeControl(group, borderPad, "borderPadding", "slider")
    RegisterCompositeControl(group, iconSide, "iconSide", "dropdown")
    RegisterCompositeControl(group, iconOffsetX, "iconOffsetX", "slider")
    RegisterCompositeControl(group, iconWidth, "iconWidth", "slider")
    RegisterCompositeControl(group, iconHeight, "iconHeight", "slider")
    RegisterCompositeControl(group, iconOffsetY, "iconOffsetY", "slider")
    RegisterCompositeControl(group, showIconBorder, "showIconBorder", "check")
    RegisterCompositeControl(group, iconBorderTexture, "iconBorderTexture", "dropdown")
    RegisterCompositeControl(group, iconBorderColor, "iconBorderColor", "color")
    RegisterCompositeControl(group, iconBorderSize, "iconBorderSize", "slider")
    RegisterCompositeControl(group, iconBorderPad, "iconBorderPadding", "slider")
    RegisterCompositeControl(group, fillMode, "fillMode", "dropdown")
    RegisterCompositeControl(group, showIcon, "showIcon", "check")
    RegisterCompositeControl(group, showBorder, "showBorder", "check")
    group._exCompositePopups = popupList
    group._timerBarDb = proxy
    -- 宽窄两种布局都由同一次 TimerBarGroupLayout 决定；Grid 测量读同一个函数。
    -- 四列按实际内容占用同一纵向范围，首尾留白对称。
    group._exCompositeReflow = function(self, nextWidth)
        local layout = TimerBarGroupLayout(nextWidth, opts)
        local nextSliderWidth = layout.itemWidth - COMPOSITE_CONTROL_INSET
        local columnWidth, leftX, rightX = layout.actionColumnWidth, layout.actionLeftX, layout.actionRightX
        local line = GM.size.controlHeight

        self:SetSize(nextWidth, layout.height)
        content:ClearAllPoints()
        content:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
        content:SetSize(nextWidth, layout.height)
        EXUI:ClearControlSurface(self)

        metricsLeft:ClearAllPoints(); metricsLeft:SetPoint("TOPLEFT", content, "TOPLEFT", layout.col1, -layout.metricsTop)
        metricsLeft:SetSize(layout.itemWidth, layout.metricsHeight)
        metricsRight:ClearAllPoints(); metricsRight:SetPoint("TOPLEFT", content, "TOPLEFT", layout.col2, -layout.metricsTop)
        metricsRight:SetSize(layout.itemWidth, layout.metricsHeight)
        local leftTops, rightTops = layout.metricLeftTops, layout.metricRightTops
        local metricRows = layout.metricRows
        PlaceCompositeControl(widthSlider, metricsLeft, COMPOSITE_CONTROL_X, leftTops[1], nextSliderWidth)
        PlaceCompositeControl(heightSlider, metricsRight, COMPOSITE_CONTROL_X, rightTops[1], nextSliderWidth)
        PlaceCompositeControl(xSlider, metricsLeft, COMPOSITE_CONTROL_X, leftTops[2], nextSliderWidth)
        PlaceCompositeControl(ySlider, metricsRight, COMPOSITE_CONTROL_X, rightTops[2], nextSliderWidth)
        -- 第三行：前景与背景各占整列宽，左右同一条基线。
        local colorY = CompositeAlignedY(leftTops[3], metricRows[3], GM.size.colorButtonHeight)
        PlaceCompositeControl(fgButton, metricsLeft, COMPOSITE_CONTROL_X, colorY,
            nextSliderWidth, GM.size.colorButtonHeight)
        PlaceCompositeControl(bgButton, metricsRight, COMPOSITE_CONTROL_X, colorY,
            nextSliderWidth, GM.size.colorButtonHeight)
        -- 底部跨整行：材质下拉锚在 content 上，占满卡片整行宽度。
        PlaceCompositeControl(textureDrop, content, layout.spanX,
            CompositeAlignedY(layout.spanTops[1], layout.spanRows[1], GM.size.dropdownHeight), layout.spanWidth)

        actionCard:ClearAllPoints()
        actionCard:SetPoint("TOPLEFT", content, "TOPLEFT", layout.controlX, -layout.actionTop)
        actionCard:SetSize(layout.controlWidth, layout.actionHeight)
        columnsDivider:SetShown(not layout.narrow)
        LayoutCompositeActionDivider(actionDivider, actionCard, layout.controlWidth)
        local left, right = layout.leftTops, layout.rightTops
        local actionRows = layout.actionRows
        local checkHeight = GM.size.checkboxRowHeight
        -- applicationBar 的图标与填充控件对原生条无效、整组隐藏，槽位已由
        -- TimerBarActionSlots 收掉；这里按同一条件只摆放可见条目，不会落到空槽。
        local leftItems, rightItems
        if opts.applicationBar == true then
            leftItems = { { showBorder, checkHeight } }
            rightItems = { { borderButton, GM.size.buttonHeight } }
        else
            leftItems = { { showIcon, checkHeight }, { showBorder, checkHeight }, { fillLabel, line } }
            rightItems = { { iconButton, GM.size.buttonHeight }, { borderButton, GM.size.buttonHeight },
                { fillButton, GM.size.buttonHeight } }
        end
        for index, item in ipairs(leftItems) do
            PlaceCompositeControl(item[1], actionCard, leftX,
                CompositeAlignedY(left[index], actionRows[index], item[2]), columnWidth, item[2])
        end
        for index, item in ipairs(rightItems) do
            PlaceCompositeControl(item[1], actionCard, rightX,
                CompositeAlignedY(right[index], actionRows[index], item[2]), columnWidth, item[2])
        end
    end
    EXUI:LayoutCompositeGroup(group, groupWidth, groupHeight)
    AttachCompositeRelease(group)
    return group
end

-- =========================================================
-- 19. Glow 设置组（Core 原生动画引擎 ExwindGlow）
-- 一列设置行：顶行“发光”开关；开了露出一排四张预设格（蚂蚁线 / 流光 / 脉冲 / 翻书），每格一枚常亮的
-- 样本按该预设（叠上当前颜色、速度等）真实发光，选中的高亮，选了预设又改过参数的格下标“已改”；
-- 下面是颜色（色板 + 自定义色块）、透明度，以及当前样式真支持的参数：三种都有速度、间距，
-- 沿边流光多出线条数量 / 长度 / 粗细 / 方向，呼吸、触发光环多出大小。
-- 存法：db 里以 key 为前缀的扁平字段（<key>Enabled / Style / Frequency / Lines / Length / Thickness /
-- Direction / Scale / Offset / ColorR / G / B / A），与 BuildGlowStyle 读的一致；V2 声明里 path 就是前缀
-- （如 path = "s.glow" → s.glowEnabled …），字段存到哪由调用方的 path 决定。
-- 一次操作（拖完滑杆、选预设、点色板、选颜色）写完所有字段后只调一次 onUpdate(db)。
-- opts.style = V2 页面样式（设置行外观跟着页面）；opts.sampleIcon = 样本图标（贴图 ID / 路径，或返回它的函数）。
-- opts.desaturate = true：翻书样本去色后再着色（同 ExwindGlow 的 desaturate）。
-- opts.params = { <后缀> = { min, max, step, decimals } }：按调用方改某个滑杆的范围、步进和显示小数位，没写的照 GLOW_PARAMS。
-- 样本发光只在组可见时播放：组隐藏时全部停掉，归还时释放。
-- =========================================================
local GLOW_DEFAULTS = { Enabled = true, Style = "EDGE_FLOW", Frequency = 1, Lines = 1, Length = 32, Thickness = 2,
    Direction = "CLOCKWISE", Scale = 1, Offset = 3, ColorR = 1, ColorG = 0.82, ColorB = 0.20, ColorA = 1 }
local GLOW_LEGACY_STYLES = {
    ["Action Button Glow"] = "PULSE",
    ["Pixel Glow"] = "EDGE_FLOW",
    ["Autocast Shine"] = "EDGE_FLOW",
    ["Proc Glow"] = "PROC_FLIPBOOK",
    ["Proc Alt Glow"] = "PROC_FLIPBOOK",
}
-- 预设只是参数的快捷组合：蚂蚁线 = 沿边流光多条短线，流光 = 沿边流光一条长线，脉冲 = 呼吸，翻书 = 触发光环。
local GLOW_PRESETS = {
    { text = "蚂蚁线", values = { Style = "EDGE_FLOW", Lines = 8, Length = 10, Thickness = 2 } },
    { text = "流光", values = { Style = "EDGE_FLOW", Lines = 1, Length = 32, Thickness = 2 } },
    { text = "脉冲", values = { Style = "PULSE", Scale = 1 } },
    { text = "翻书", values = { Style = "PROC_FLIPBOOK", Scale = 1 } },
}
-- 参数行（颜色行之后）：flow = true 只给沿边流光，flow = false 只给另两种，不写三种都有。
local GLOW_PARAMS = {
    { suffix = "ColorA", label = "透明度", min = 0, max = 1, step = 0.05, percent = true },
    { suffix = "Frequency", label = "速度", min = 0.1, max = 5, step = 0.1 },
    { suffix = "Offset", label = "间距", min = -20, max = 50, step = 1 },
    { suffix = "Lines", label = "线条数量", min = 1, max = 36, step = 1, flow = true },
    { suffix = "Length", label = "线条长度", min = 8, max = 120, step = 1, flow = true },
    { suffix = "Thickness", label = "线条粗细", min = 1, max = 20, step = 0.5, flow = true },
    { suffix = "Direction", label = "方向", flow = true, segment = true },
    { suffix = "Scale", label = "大小", min = 0.25, max = 3, step = 0.05, flow = false },
}
local GLOW_POOL = "CompositeGlowSettings"

local function GlowPart(name) return GM.settings.parts[name] end

-- 预设格的固定高：内距 + 预览区 + 名字 + “已改”。
local function GlowTileHeight()
    return GlowPart("glowTilePadY") * 2 + GlowPart("glowTilePreviewHeight") + GlowPart("glowTileLabelFont")
        + GlowPart("glowTileMarkFont") + GlowPart("glowTileLineGap") * 2
end

local function GlowTileColumns(width, padX)
    local room = math.max(1, width - padX * 2)
    local gap = GlowPart("glowTileGap")
    local columns = #GLOW_PRESETS
    while columns > 1 and (room - gap * (columns - 1)) / columns < GlowPart("glowTileMinWidth") do
        columns = columns / 2
    end
    return math.max(1, math.floor(columns))
end

local function GlowTilesBlockHeight(width, padX)
    local columns = GlowTileColumns(width, padX)
    local rows = math.ceil(#GLOW_PRESETS / columns)
    return GlowPart("glowTileBlockPadY") * 2 + rows * GlowTileHeight() + (rows - 1) * GlowPart("glowTileGap")
end

-- 预设格照方格卡画法（Core 公共的卡片勾选框底、悬停、右上角斜角 + 白勾）。
local function PaintGlowTile(tile)
    EXUI:PaintCheckCardSurface(tile, tile._exSelected == true, tile:IsMouseOver(), true, GM.radius.popup)
end

-- 一次性建在池化宿主上的固定件：四张预设格、色板条。每次借出只改文字、颜色和回调。
local function BuildGlowHost(group)
    group.content = CreateFrame("Frame", nil, group)
    group.tiles = {}
    for index = 1, #GLOW_PRESETS do
        local tile = CreateFrame("Button", nil, group.content)
        tile:RegisterForClicks("LeftButtonUp")
        tile.sample = CreateFrame("Frame", nil, tile)
        tile.sample:EnableMouse(false)
        tile.icon = tile.sample:CreateTexture(nil, "ARTWORK")
        tile.icon:SetAllPoints(tile.sample)
        tile.label = EXUI:CreateVisualFontString(tile, EXFONTFRAME, "GameFontHighlight")
        tile.label:SetJustifyH("CENTER")
        tile.label:SetWordWrap(false)
        tile.mark = EXUI:CreateVisualFontString(tile, EXFONTFRAME, "GameFontHighlightSmall")
        tile.mark:SetJustifyH("CENTER")
        tile:SetScript("OnEnter", PaintGlowTile)
        tile:SetScript("OnLeave", PaintGlowTile)
        tile:SetScript("OnClick", function(self) if self._exOnPick then self._exOnPick() end end)
        group.tiles[index] = tile
    end
    group.swatchBar = CreateFrame("Frame", nil, group.content)
    group.swatches = {}
    for index = 1, #ExwindTools.GUIColors.glowPalette do
        local swatch = CreateFrame("Button", nil, group.swatchBar)
        swatch:RegisterForClicks("LeftButtonUp")
        swatch:SetScript("OnClick", function(self) if self._exOnPick then self._exOnPick() end end)
        group.swatches[index] = swatch
    end
end

-- 归还：样本发光释放、本次借的控件和设置行还池、回调清掉。
local function ReleaseGlowSettings(host)
    for _, tile in ipairs(host.tiles) do
        EXUI:ReleaseGlow(tile.sample)
        tile._exOnPick, tile._exSelected = nil, nil
        tile:Hide()
    end
    for _, swatch in ipairs(host.swatches) do swatch._exOnPick = nil end
    for _, control in ipairs(host._exGlowControls or {}) do
        EXUI:RestoreSettingsListControl(control)
        _G.ExwindFactory:ReleaseGridWidget(control)
    end
    for _, row in ipairs(host._exGlowRows or {}) do row:Release() end
    host:SetScript("OnShow", nil)
    host:SetScript("OnHide", nil)
    host._exGlowControls, host._exGlowRows, host._exStandardSliderControls = nil, nil, nil
    host._exStandardSliderDB, host._glowDb, host._exMeasureHeight = nil, nil, nil
    host._exCompositeReflow, host._exCompositeConfigure = nil, nil
    host._exCompositeDb, host._exCompositeOnUpdate, host._exCompositeOpts = nil, nil, nil
end

function EXUI:CreateGlowSettings(parent, width, label, db, key, onUpdate, opts)
    db = type(db) == "table" and db or {}
    opts = type(opts) == "table" and opts or {}
    key = key or "glow"
    for suffix, value in pairs(GLOW_DEFAULTS) do
        if db[key .. suffix] == nil then db[key .. suffix] = value end
    end
    db[key .. "Style"] = GLOW_LEGACY_STYLES[db[key .. "Style"]] or db[key .. "Style"]

    local group, isNew = AcquireCompositeGroup(GLOW_POOL, parent)
    if isNew then BuildGlowHost(group) end
    EXUI:ClearControlSurface(group)
    local content = group.content
    content:ClearAllPoints()
    content:SetPoint("TOPLEFT", group, "TOPLEFT", 0, 0)
    content:Show()
    local style = opts.style
    local styledHeight = style and style.controlHeight
    local padX = style and style.rowPaddingX or GM.settings.rowPaddingX
    local GC = ExwindTools.GUIColors
    local function Get(suffix) return db[key .. suffix] end
    local function IsFlow() return Get("Style") == "EDGE_FLOW" end

    -- 标准 Slider 合同元数据：只暴露既有控件与其真实 DB 路径。
    group._exStandardSliderControls = {}
    group._exStandardSliderDB = db
    group._glowDb = db
    local controls, rows = {}, {}
    group._exGlowControls, group._exGlowRows = controls, rows
    local entries = {}
    local refresh -- 下面定义：按 db 回填控件、预设格与色板
    local function Emit()
        refresh()
        if onUpdate then onUpdate(db) end
    end
    local function Entry(rowLabel, control, kind)
        local entry = { control = control, kind = kind }
        if kind ~= "fixed" then controls[#controls + 1] = control end -- 色板条是宿主的固定件，不归还
        local fixed
        if kind == "segment" then
            fixed = style and style.segmentEqualWidth and style.controlWidth
                or (control.NaturalWidth and control:NaturalWidth()) or control:GetWidth()
        elseif kind == "fixed" then
            fixed = control:GetWidth()
        end
        entry.row = EXUI:CreateSettingsRow(content, {
            label = rowLabel,
            controlKind = kind == "slider" and "ordinary" or nil,
            controlWidth = fixed,
            controlMinWidth = kind == "slider" and GM.size.settingsRowSliderMinWidth or fixed,
            style = style,
        })
        rows[#rows + 1] = entry.row
        entries[#entries + 1] = entry
        return entry
    end

    -- 顶行开关。
    local enabled = EXUI:CreateCheckbox(content, L["发光"], Get("Enabled") == true, function(checked)
        db[key .. "Enabled"] = checked == true
        Emit()
    end)
    EXUI:PrepareSettingsListControl(enabled, { hideLabel = true, presentation = "switch" })
    local switchEntry = Entry(L["发光"], enabled, "switch")

    -- 颜色行：色板 + 自定义色块（色块的取色器带透明度，与透明度滑杆写同一字段）。
    local swatchSize, swatchGap = GlowPart("glowSwatchSize"), GlowPart("glowSwatchGap")
    local custom = EXUI:CreateColorButton(group.swatchBar, "", db, key .. "Color", true, Emit, { swatchOnly = true })
    custom:SetSize(styledHeight or GM.size.controlHeight, styledHeight or GM.size.controlHeight)
    local barHeight = custom:GetHeight()
    for index, swatch in ipairs(group.swatches) do
        local color = GC.glowPalette[index]
        swatch:ClearAllPoints()
        swatch:SetPoint("LEFT", group.swatchBar, "LEFT", (index - 1) * (swatchSize + swatchGap), 0)
        swatch:SetSize(swatchSize, swatchSize)
        swatch:EnableMouse(true)
        swatch._exOnPick = function()
            db[key .. "ColorR"], db[key .. "ColorG"], db[key .. "ColorB"] = color[1], color[2], color[3]
            Emit()
        end
        swatch:Show()
    end
    custom:ClearAllPoints()
    custom:SetPoint("LEFT", group.swatchBar, "LEFT", #group.swatches * (swatchSize + swatchGap), 0)
    group.swatchBar:SetSize(#group.swatches * (swatchSize + swatchGap) + custom:GetWidth(), barHeight)
    local colorEntry = Entry(L["颜色"], group.swatchBar, "fixed")
    controls[#controls + 1] = custom

    -- 参数行。
    local params = {}
    local paramOverrides = type(opts.params) == "table" and opts.params or {}
    for _, base in ipairs(GLOW_PARAMS) do
        local spec = base
        local override = paramOverrides[base.suffix]
        if type(override) == "table" then
            spec = {}
            for name, value in pairs(base) do spec[name] = value end
            for name, value in pairs(override) do spec[name] = value end
        end
        local field = key .. spec.suffix
        local control
        if spec.segment then
            local items = { { L["顺时针"], "CLOCKWISE" }, { L["逆时针"], "COUNTERCLOCKWISE" } }
            control = EXUI:CreateSegmentedControl(content, GM.size.controlDefaultWidth, items, db[field], function(value)
                db[field] = value
                Emit()
            end, styledHeight and { height = styledHeight } or nil)
        else
            local decimalFormat = spec.decimals and ("%." .. spec.decimals .. "f") or nil
            local formatter = spec.percent and function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end
                or (decimalFormat and function(v) return string.format(decimalFormat, v) end) or nil
            local parse = spec.percent and function(text)
                local number = tonumber((text:gsub("%%$", "")))
                return number and number / 100 or nil
            end or nil
            control = EXUI:CreateSlider(content, GM.size.controlDefaultWidth, L[spec.label], spec.min, spec.max,
                db[field], spec.step, formatter, {
                    -- 拖动中只更新预设格样本，放开或输入提交时才算一次改动。
                    onLive = function(value) db[field] = value; refresh() end,
                    onCommit = function(value) db[field] = value; Emit() end,
                    parse = parse,
                })
            EXUI:PrepareSettingsListControl(control, { ordinaryControl = true, hideLabel = true, valuePosition = "right" })
            table.insert(group._exStandardSliderControls, { control = control, path = field })
        end
        local entry = Entry(L[spec.label], control, spec.segment and "segment" or "slider")
        entry.spec = spec
        params[#params + 1] = entry
    end

    -- 预设格：选中 = 同样式里与当前值最接近的那张，字段没全对上标“已改”。
    local function PickedPreset()
        local best, bestScore, bestCount
        for index, preset in ipairs(GLOW_PRESETS) do
            if preset.values.Style == Get("Style") then
                local score, count = 0, 0
                for suffix, value in pairs(preset.values) do
                    count = count + 1
                    if Get(suffix) == value then score = score + 1 end
                end
                if not best or score > bestScore then best, bestScore, bestCount = index, score, count end
            end
        end
        return best, best and bestScore < bestCount
    end
    local function SampleIcon()
        local icon = opts.sampleIcon
        if type(icon) == "function" then icon = icon() end
        return icon or 134400
    end
    local function StopSamples()
        for _, tile in ipairs(group.tiles) do EXUI:HideGlow(tile.sample) end
    end
    local function PlaySamples()
        if not group:IsVisible() or Get("Enabled") ~= true then StopSamples(); return end
        local size = GlowPart("glowTileSampleSize")
        for index, tile in ipairs(group.tiles) do
            local values = {}
            for suffix in pairs(GLOW_DEFAULTS) do values[key .. suffix] = Get(suffix) end
            for suffix, value in pairs(GLOW_PRESETS[index].values) do values[key .. suffix] = value end
            values[key .. "Offset"] = math.min(values[key .. "Offset"], GlowPart("glowSampleOffsetMax"))
            local glowStyle = EXUI:BuildGlowStyle(values, key, size, size)
            glowStyle.enabled = true
            glowStyle.desaturate = opts.desaturate == true
            EXUI:ShowGlow(tile.sample, glowStyle)
        end
    end
    local labelFont, markFont = GlowPart("glowTileLabelFont"), GlowPart("glowTileMarkFont")
    for index, tile in ipairs(group.tiles) do
        local preset = GLOW_PRESETS[index]
        MODERN.Font(tile.label, labelFont, GC.text, "", "GameFontHighlight")
        MODERN.Font(tile.mark, markFont, GC.textDim, "", "GameFontHighlightSmall")
        tile.label:SetText(L[preset.text])
        tile.mark:SetText(L["已改"])
        tile.icon:SetTexture(SampleIcon())
        tile:EnableMouse(true)
        tile._exOnPick = function()
            for suffix, value in pairs(preset.values) do db[key .. suffix] = value end
            Emit()
        end
    end

    local width = width or 750
    -- 按宽从上往下排：开关行；开着时预设格一排、颜色行、当前样式的参数行。返回总高。
    local function Layout(nextWidth)
        width = nextWidth or width
        content:SetWidth(width)
        local on = Get("Enabled") == true
        local flow = IsFlow()
        local shown = { switchEntry }
        if on then
            shown[#shown + 1] = colorEntry
            for _, entry in ipairs(params) do
                if entry.spec.flow == nil or entry.spec.flow == flow then shown[#shown + 1] = entry end
            end
        end
        local visible = {}
        for _, entry in ipairs(shown) do visible[entry] = true end
        for _, entry in ipairs(entries) do
            if not visible[entry] then
                entry.row:Hide()
                entry.control:Hide()
            end
        end
        local y = 0
        for index, entry in ipairs(shown) do
            local row, control = entry.row, entry.control
            EXUI:SetSettingsRowLast(row, index == #shown)
            local height, x, cy, controlWidth = EXUI:UpdateSettingsRowLayout(row, width, math.max(1, control:GetHeight()))
            if entry.kind ~= "fixed" then control:SetWidth(controlWidth) end
            if entry.kind == "slider" then
                EXUI:UpdateSettingsListControlLayout(control, controlWidth, styledHeight)
            end
            height, x, cy = EXUI:UpdateSettingsRowLayout(row, width, math.max(1, control:GetHeight()))
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            row:Show()
            control:ClearAllPoints()
            control:SetPoint("TOPLEFT", row, "TOPLEFT", x, -cy)
            control:Show()
            y = y + height
            -- 预设格一排紧跟开关行。
            if entry == switchEntry and on then
                local columns = GlowTileColumns(width, padX)
                local gap, tileHeight = GlowPart("glowTileGap"), GlowTileHeight()
                local tileWidth = math.floor((width - padX * 2 - gap * (columns - 1)) / columns)
                local top = y + GlowPart("glowTileBlockPadY")
                local preview = GlowPart("glowTilePreviewHeight")
                local sampleSize = GlowPart("glowTileSampleSize")
                local lineGap, tilePadY = GlowPart("glowTileLineGap"), GlowPart("glowTilePadY")
                for tileIndex, tile in ipairs(group.tiles) do
                    local column, line = (tileIndex - 1) % columns, math.floor((tileIndex - 1) / columns)
                    tile:ClearAllPoints()
                    tile:SetPoint("TOPLEFT", content, "TOPLEFT", padX + column * (tileWidth + gap), -(top + line * (tileHeight + gap)))
                    tile:SetSize(tileWidth, tileHeight)
                    tile.sample:ClearAllPoints()
                    tile.sample:SetPoint("CENTER", tile, "TOP", 0, -(tilePadY + preview / 2))
                    tile.sample:SetSize(sampleSize, sampleSize)
                    tile.label:ClearAllPoints()
                    tile.label:SetPoint("TOPLEFT", tile, "TOPLEFT", 2, -(tilePadY + preview + lineGap))
                    tile.label:SetPoint("TOPRIGHT", tile, "TOPRIGHT", -2, -(tilePadY + preview + lineGap))
                    tile.mark:ClearAllPoints()
                    tile.mark:SetPoint("TOP", tile.label, "BOTTOM", 0, -lineGap)
                    tile:Show()
                end
                y = y + GlowTilesBlockHeight(width, padX)
            end
        end
        for _, tile in ipairs(group.tiles) do tile:SetShown(on) end
        content:SetHeight(math.max(1, y))
        return math.max(1, y)
    end

    refresh = function()
        enabled:SetChecked(Get("Enabled") == true)
        EXUI:ApplyControlAppearance(enabled)
        for _, entry in ipairs(params) do
            local value = Get(entry.spec.suffix)
            if entry.spec.segment then entry.control:SetValue(value)
            elseif tonumber(value) then entry.control:SetEXUIValue(tonumber(value), "silent") end
        end
        custom:UpdateColor()
        local r, g, b = Get("ColorR"), Get("ColorG"), Get("ColorB")
        for index, swatch in ipairs(group.swatches) do
            local color = GC.glowPalette[index]
            local same = math.abs(color[1] - r) < 0.005 and math.abs(color[2] - g) < 0.005 and math.abs(color[3] - b) < 0.005
            EXUI:SetControlSurface(swatch, GM.radius.thumb, { color[1], color[2], color[3], 1 },
                same and GC.text or GC.subcardBorder)
        end
        local picked, modified = PickedPreset()
        for index, tile in ipairs(group.tiles) do
            tile._exSelected = index == picked
            tile.mark:SetShown(index == picked and modified == true)
            PaintGlowTile(tile)
        end
        PlaySamples()
    end

    group:SetScript("OnShow", PlaySamples)
    group:SetScript("OnHide", StopSamples)
    -- V2 页面先量高再排：量的时候就按这个宽排一次。
    group._exMeasureHeight = function(_, measureWidth) return Layout(measureWidth) end
    group._exCompositeReflow = function(self, nextWidth)
        Layout(nextWidth)
        EXUI:ClearControlSurface(self)
    end
    -- 外部改了存档（预览拖动、撤销）后 RefreshCompositeGroupFromDB 走这里回填。
    group._exCompositeDb, group._exCompositeOnUpdate, group._exCompositeOpts = db, onUpdate, opts
    group._exCompositeConfigure = function() refresh(); Layout(width) end
    _G.ExwindFactory:AttachPoolRelease(group, ReleaseGlowSettings)

    refresh()
    local height = Layout(width)
    EXUI:LayoutCompositeGroup(group, width, height)
    return group
end

-- =========================================================
-- 20. Widget 排列设置组
-- 只管理同一规则内多个 Widget 的增长方向、间距、最大显示数量与可选换行方向。
-- 整体 X/Y 属于模块 AnchorController，不能放在这里。
-- =========================================================
-- 只描述排列组的视觉字段；不参与配置构造、绑定或提交。
local function BuildWidgetLayoutSettingsFlow(width, opts)
    opts = type(opts) == "table" and opts or {}
    local fields = {
        { path = "direction", type = "dropdown", label = L["增长方向"] },
        { path = "spacing", type = "slider", label = L["间距"] },
        { path = "maxVisible", type = "slider", label = L["最大显示"] },
    }
    if opts.includeMaxPerRow ~= false then
        fields[#fields + 1] = { path = "maxPerRow", type = "slider", label = L["每行最多"] }
    end
    if opts.includeWrapDirection == true then
        fields[#fields + 1] = { path = "wrapDirection", type = "dropdown", label = L["换行方向"] }
    end
    return EXUI:BuildModuleCommonSettingsFlow(width, { presentation = "settings-list", fields = fields })
end

function EXUI:CreateWidgetLayoutGroup(parent, width, label, db, key, onUpdate, opts)
    opts = type(opts) == "table" and opts or {}
    if key and type(db) == "table" then
        db[key] = type(db[key]) == "table" and db[key] or {}
        db = db[key]
    end
    db = type(db) == "table" and db or {}
    local allowedDirections = type(opts.allowedDirections) == "table" and opts.allowedDirections or {
        "RIGHT", "LEFT", "DOWN", "UP", "CENTER_HORIZONTAL", "CENTER_VERTICAL",
    }
    local defaultDirection = allowedDirections[1] or "RIGHT"
    local wrapDirections = type(opts.wrapDirections) == "table" and opts.wrapDirections or {
        "DOWN", "UP",
    }
    local defaultWrapDirection = tostring(opts.defaultWrapDirection or wrapDirections[1] or "DOWN")
    local maxVisibleMin = math.max(1, tonumber(opts.maxVisibleMin) or 1)
    local maxVisibleMax = math.max(maxVisibleMin, tonumber(opts.maxVisibleMax) or 40)
    local defaultMaxVisible = tonumber(opts.defaultMaxVisible) or 8
    defaultMaxVisible = math.max(maxVisibleMin, math.min(defaultMaxVisible, maxVisibleMax))
    if db.direction == nil then db.direction = defaultDirection end
    if db.spacing == nil then db.spacing = 4 end
    if db.maxVisible == nil then db.maxVisible = defaultMaxVisible end
    if db.maxPerRow == nil then db.maxPerRow = 8 end
    if db.wrapDirection == nil then db.wrapDirection = defaultWrapDirection end

    local includeMaxPerRow = opts.includeMaxPerRow ~= false
    local includeWrapDirection = opts.includeWrapDirection == true
    local groupWidth = width or 760
    local groupHeight = BuildWidgetLayoutSettingsFlow(groupWidth, opts).height
    -- 二维换行卡有额外的下拉控件，必须使用已注册的独立宿主池；
    -- 不能让它和普通单轴卡复用，也不能接受任意外部池名。
    local poolType = includeWrapDirection and "CompositeWidgetLayoutGroupWithWrap" or "CompositeWidgetLayoutGroup"
    local group, isNew = AcquireCompositeGroup(poolType, parent)
    group._exCompositeLabel = label or L["排序"]
    BindCompositeGroup(group, db, onUpdate, opts)
    if not isNew then
        AttachCompositeRelease(group)
        local maxVisible = group._exWidgetLayoutMaxVisible
        if maxVisible then
            maxVisible:SetMinMaxValues(maxVisibleMin, maxVisibleMax)
            local value = tonumber(db.maxVisible) or defaultMaxVisible
            value = math.max(maxVisibleMin, math.min(value, maxVisibleMax))
            db.maxVisible = value
            maxVisible:SetValue(value)
        end
        EXUI:LayoutCompositeGroup(group, groupWidth, groupHeight)
        EXUI:ClearControlSurface(group)
        if group._exWidgetLayoutHint then group._exWidgetLayoutHint:Hide() end
        return group
    end
    local proxy = CreateCompositeProxy(group)
    db = proxy
    group:SetSize(groupWidth, groupHeight)
    EXUI:ClearControlSurface(group)

    local function EmitUpdate() CompositeEmitUpdate(group) end

    -- Layout 卡片本身会从对象池复用；每次输入都必须从当前宿主读取
    -- Grid 写入上下文，不能捕获第一次（通常是 TimerBar）创建时的 moduleKey。
    local function CreateLayoutInputTransaction(field)
        local activeOpts = group._exCompositeOpts or {}
        local metadata = activeOpts._exWriteContext
        if metadata == nil then return nil end
        if type(metadata) ~= "table" or type(metadata.moduleKey) ~= "string" or metadata.moduleKey == "" then
            error("CreateWidgetLayoutGroup requires Grid write context", 2)
        end
        if type(EXUI.CreateModuleNotifyFlow) ~= "function" then
            error("CreateWidgetLayoutGroup requires CreateModuleNotifyFlow", 2)
        end
        local prefix = metadata.pathPrefix
        if prefix ~= nil and type(prefix) ~= "string" then
            error("CreateWidgetLayoutGroup Grid write context pathPrefix must be string or nil", 2)
        end
        local path = type(prefix) == "string" and prefix ~= "" and (prefix .. "." .. field) or field
        return EXUI:CreateModuleNotifyFlow({
            moduleKey = metadata.moduleKey,
            path = path,
            readValue = function() return group._widgetLayoutDb[field] end,
            writeValue = function(value) group._widgetLayoutDb[field] = value end,
        })
    end

    local function CommitLayoutValue(field, value)
        local transaction = CreateLayoutInputTransaction(field)
        if transaction and transaction.onCommit then return transaction.onCommit(value) end
        group._widgetLayoutDb[field] = value
        EmitUpdate()
        return true
    end

    -- 排列组的滑条是设置行呈现：下方 reflow 用 PrepareSettingsListControl 的
    -- valuePosition="right" 把数值框放在行右侧、轨道占满控件列，数值框已经和行标题
    -- 同一行。因此这里不声明 numberInputPosition（它只对带自有标题的滑条有意义，
    -- 且设置行布局随后会重锚数值框与轨道）。

    local directionLabels = {
        RIGHT = L["向右"], LEFT = L["向左"], DOWN = L["向下"], UP = L["向上"],
        CENTER_HORIZONTAL = L["左右居中"], CENTER_VERTICAL = L["上下居中"],
    }
    local directionItems = {}
    for _, directionKey in ipairs(allowedDirections) do
        directionItems[#directionItems + 1] = { directionLabels[directionKey] or tostring(directionKey), directionKey }
    end
    local direction = EXUI:CreateDropdown(group, math.min(220, groupWidth - 40), L["增长方向"], directionItems, db.direction, function(value)
        CommitLayoutValue("direction", value)
    end)
    direction:SetPoint("TOPLEFT", 16, -42)
    RegisterCompositeControl(group, direction, "direction", "dropdown")

    local spacing = EXUI:CreateSlider(group, math.min(180, math.max(120, groupWidth * 0.24)), L["间距"], -10, 20,
        tonumber(db.spacing) or 4, 0.1, nil, CreateLayoutInputTransaction("spacing") or function(value)
            db.spacing = value
            EmitUpdate()
        end)
    spacing:SetPoint("TOPLEFT", math.min(255, groupWidth * 0.36), -46)
    RegisterCompositeControl(group, spacing, "spacing", "slider")

    local maxVisible = EXUI:CreateSlider(group, math.min(180, math.max(120, groupWidth * 0.24)), L["最大显示"], maxVisibleMin, maxVisibleMax,
        tonumber(db.maxVisible) or defaultMaxVisible, 1, nil, CreateLayoutInputTransaction("maxVisible") or function(value)
            db.maxVisible = value
            EmitUpdate()
        end)
    maxVisible:SetPoint("TOPLEFT", math.min(470, groupWidth * 0.64), -46)
    RegisterCompositeControl(group, maxVisible, "maxVisible", "slider")
    group._exWidgetLayoutMaxVisible = maxVisible

    local maxPerRow
    if includeMaxPerRow then
        maxPerRow = EXUI:CreateSlider(group, math.min(180, math.max(120, groupWidth * 0.24)), L["每行最多"], 1, 40,
            tonumber(db.maxPerRow) or 8, 1, nil, CreateLayoutInputTransaction("maxPerRow") or function(value)
                db.maxPerRow = value
                EmitUpdate()
            end)
        maxPerRow:SetPoint("TOPLEFT", 16, -92)
        RegisterCompositeControl(group, maxPerRow, "maxPerRow", "slider")
    end

    local wrapDirection
    if includeWrapDirection then
        local wrapItems = {}
        for _, directionKey in ipairs(wrapDirections) do
            wrapItems[#wrapItems + 1] = { directionLabels[directionKey] or tostring(directionKey), directionKey }
        end
        wrapDirection = EXUI:CreateDropdown(group, math.min(180, math.max(120, groupWidth * 0.24)), L["换行方向"], wrapItems,
            db.wrapDirection, function(value)
                db.wrapDirection = value
                EmitUpdate()
            end)
        wrapDirection:SetPoint("TOPLEFT", math.min(255, groupWidth * 0.36), -88)
        RegisterCompositeControl(group, wrapDirection, "wrapDirection", "dropdown")
    end

    group._widgetLayoutDb = proxy
    group._exCompositeConfigure = function(self)
        local activeOpts = self._exCompositeOpts or {}
        local activeDirections = type(activeOpts.allowedDirections) == "table" and activeOpts.allowedDirections or {
            "RIGHT", "LEFT", "DOWN", "UP", "CENTER_HORIZONTAL", "CENTER_VERTICAL",
        }
        local activeItems = {}
        for _, directionKey in ipairs(activeDirections) do
            activeItems[#activeItems + 1] = { directionLabels[directionKey] or tostring(directionKey), directionKey }
        end
        direction._items = activeItems
        direction._currentValue = self._widgetLayoutDb.direction
        direction._onSelect = function(value) CommitLayoutValue("direction", value) end
        SetDropdownDisplayText(direction, CompositeDropdownText(direction._currentValue, activeItems) or L["请选择..."])

        local function RebindSlider(control, field)
            -- SetLifecycleCallbacks only replaces onValueChanged when given a
            -- function, so explicitly clear the fallback callback from a
            -- possible no-context first creation.
            control._onValueChanged = nil
            control:SetLifecycleCallbacks(CreateLayoutInputTransaction(field) or {})
        end
        RebindSlider(spacing, "spacing")
        RebindSlider(maxVisible, "maxVisible")
        if maxPerRow then RebindSlider(maxPerRow, "maxPerRow") end
    end
    group:_exCompositeConfigure()
    local settingsControls = {
        direction = direction, spacing = spacing, maxVisible = maxVisible,
        maxPerRow = maxPerRow, wrapDirection = wrapDirection,
    }
    local settingsRows = {}
    group._exCompositeReflow = function(self, nextWidth, nextHeight)
        local flow = BuildWidgetLayoutSettingsFlow(nextWidth, self._exCompositeOpts)
        self._exGridFixedHeight = flow.height
        self:SetHeight(flow.height)
        EXUI:ClearControlSurface(self)
        for _, row in pairs(settingsRows) do row:Hide() end
        for _, control in pairs(settingsControls) do control:Hide() end
        for index, entry in ipairs(flow.entries) do
            local field = entry.field
            local control = settingsControls[field.path]
            if control then
                local row = settingsRows[field.path]
                if not row then
                    row = EXUI:CreateSettingsRow(self, { label = field.label, controlKind = "ordinary",
                        controlMinWidth = EXUI:GetModuleCommonControlMinWidth(field) })
                    settingsRows[field.path] = row
                end
                row._exSettingsRowIsLast = index == #flow.entries
                row:Show()
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", self, "TOPLEFT", 0, entry.y)
                EXUI:PrepareSettingsListControl(control, {
                    hideLabel = true, ordinaryControl = true,
                    valuePosition = field.type == "slider" and "right" or nil,
                })
                local _, x, y, controlWidth = EXUI:UpdateSettingsRowLayout(row, entry.width, entry.controlHeight)
                control:SetWidth(controlWidth)
                EXUI:UpdateSettingsListControlLayout(control, controlWidth)
                control:ClearAllPoints()
                control:SetPoint("TOPLEFT", self, "TOPLEFT", x,
                    entry.y - y - math.max(0, (entry.controlHeight - control:GetHeight()) * 0.5))
                control:Show()
            end
        end
    end
    EXUI:LayoutCompositeGroup(group, groupWidth, groupHeight)
    AttachCompositeRelease(group)
    return group
end

-- =========================================================
-- 模块通用设置组；纯布局 BuildModuleCommonSettingsFlow 位于 SettingsList 文件。
-- =========================================================
function EXUI:CreateModuleCommonSettingsGroup(parent, width, label, db, key, onUpdate, opts)
    opts = type(opts) == "table" and opts or {}
    if key and opts.bindRoot ~= true and type(db) == "table" then
        db[key] = type(db[key]) == "table" and db[key] or {}
        db = db[key]
    end
    db = type(db) == "table" and db or {}
    local groupWidth = width or 760
    local flow = self:BuildModuleCommonSettingsFlow(groupWidth, opts)
    local groupHeight = flow.height
    local group, isNew = AcquireCompositeGroup(opts.poolType or "CompositeModuleCommonSettingsGroup", parent)
    EXUI:ClearControlSurface(group)
    group._exCompositeLabel = label or L["模块通用设置"]
    -- modulecommonsettings 的 fields 是模块声明的动态结构，不能像字体/计时条/图标
    -- 等固定结构组那样整树复用。先归还上一轮的子控件，再按本轮 fields 建立；外壳
    -- 仍是 CompositeHost 池，标准 checkbox/dropdown/slider/input/color 仍各自回到既有池。
    if not isNew and group._exClearModuleCommonEntries then
        group:_exClearModuleCommonEntries()
    end
    BindCompositeGroup(group, db, onUpdate, opts)
    group._moduleCommonDb = db
    -- Grid 容器可能在同一帧被其他页面激活；页面需要能把实际显示的宿主
    -- 明确重绑回本次渲染的模块 DB，不能依赖对象池残留引用。
    group.RebindDB = function(self, nextDB)
        if type(nextDB) ~= "table" then return false end
        BindCompositeGroup(self, nextDB, self._exCompositeOnUpdate, self._exCompositeOpts)
        self._moduleCommonDb = nextDB
        return true
    end
    if not isNew then
        group:_exBuildModuleCommonEntries(flow)
        AttachCompositeRelease(group)
        EXUI:LayoutCompositeGroup(group, groupWidth, groupHeight)
        return group
    end

    group:SetSize(groupWidth, groupHeight)

    local content = CreateFrame("Frame", nil, group)
    content:SetPoint("TOPLEFT", 0, 0)
    local settingsCard = CreateFrame("Frame", nil, content)

    local function EmitUpdate() CompositeEmitUpdate(group) end
    -- Root-bound ModuleCommon cards have no group prefix.  Their Checkbox /
    -- Dropdown / Input controls still need a real leaf path; forwarding the
    -- empty group path makes NotifyModuleValueChanged reject the change.
    local function NotifyModuleCommonField(path)
        local metadata = group._exCompositeOpts and group._exCompositeOpts._exWriteContext
        if metadata == nil then return false end
        if type(metadata) ~= "table" or type(metadata.moduleKey) ~= "string" or metadata.moduleKey == "" then
            error("CreateModuleCommonSettingsGroup requires Grid write context", 2)
        end
        local prefix = metadata.pathPrefix
        if prefix ~= nil and type(prefix) ~= "string" then
            error("CreateModuleCommonSettingsGroup Grid write context pathPrefix must be string or nil", 2)
        end
        local fullPath = type(prefix) == "string" and prefix ~= "" and (prefix .. "." .. path) or path
        EXUI:NotifyModuleValueChanged(metadata.moduleKey, fullPath, "committed")
        return true
    end
    local function SetValue(path, value, phase)
        CompositePathSet(group._exCompositeDb, path, value)
        -- 外部 DatabaseChanged 监听负责运行时同步；页面自己的预览则不应依赖那条
        -- 异步链。允许宿主在“字段已写入同一份 DB”的瞬间直接重套预览样式。
        if phase ~= "live" and type(group._exCompositeOpts.onFieldChanged) == "function" then
            group._exCompositeOpts.onFieldChanged(group._exCompositeDb, path, value)
        end
        if phase ~= "live" and not NotifyModuleCommonField(path) then EmitUpdate() end
    end

    -- ModuleCommonSettings 的连续 Slider 通过唯一 ModuleDB 通知流重套表面。
    local function CreateModuleCommonNotifyFlow(path)
        local metadata = group._exCompositeOpts and group._exCompositeOpts._exWriteContext
        if metadata == nil then return nil end
        if type(metadata) ~= "table" or type(metadata.moduleKey) ~= "string" or metadata.moduleKey == "" then
            error("CreateModuleCommonSettingsGroup requires Grid write context", 2)
        end
        if type(EXUI.CreateModuleNotifyFlow) ~= "function" then
            error("CreateModuleCommonSettingsGroup requires CreateModuleNotifyFlow", 2)
        end
        local prefix = metadata.pathPrefix
        if prefix ~= nil and type(prefix) ~= "string" then
            error("CreateModuleCommonSettingsGroup Grid write context pathPrefix must be string or nil", 2)
        end
        local fullPath = type(prefix) == "string" and prefix ~= "" and (prefix .. "." .. path) or path
        return EXUI:CreateModuleNotifyFlow({
            moduleKey = metadata.moduleKey,
            path = fullPath,
            readValue = function() return CompositePathValue(group._exCompositeDb, path) end,
            -- Core controller owns the only commit refresh.  live writes must
            -- not broadcast DatabaseChanged or rebuild this page.
            writeValue = function(value) SetValue(path, value, "live") end,
        })
    end

    group._exClearModuleCommonEntries = function(self)
        local factory = _G.ExwindFactory
        for _, mounted in ipairs(self._exModuleCommonEntries or {}) do
            local control = mounted.control
            if control then EXUI:RestoreSettingsListControl(control) end
            if mounted.row and mounted.row.Release then mounted.row:Release() end
            if control and control._fromPool and factory then
                factory:Release(control._fromPool, control)
            elseif control then
                control:Hide()
                control:ClearAllPoints()
            end
            if mounted.card then
                mounted.card:Hide()
                mounted.card:ClearAllPoints()
            end
        end
        self._exModuleCommonEntries = {}
        self._exCompositeControls = {}
    end

    group._exBuildModuleCommonEntries = function(self, nextFlow)
        local activeFields = nextFlow.fields or {}
        local activeDb = self._exCompositeDb or {}
        self._exModuleCommonEntries = {}
        self._exModuleCommonCards = self._exModuleCommonCards or {}
        for index, field in ipairs(activeFields) do
            local path = tostring(field.path or field.key or "")
            if path ~= "" or field.type == "button" then
                local disabled = field.disabled == true
                local flowEntry = nextFlow.entries[index]
                local value = CompositePathValue(activeDb, path)
            local control, kind = nil, nil
            -- 保留每个控件的独立承载 Frame（下拉/对象池会依赖它的局部父级），
            -- 但取消背景与边框：视觉上只保留模块通用设置的外层卡片，不再出现小方格。
            local card = self._exModuleCommonCards[index]
            if not card then
                card = CreateFrame("Frame", nil, settingsCard, "BackdropTemplate")
                self._exModuleCommonCards[index] = card
                card:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
                card:SetBackdropColor(0, 0, 0, 0)
                card:SetBackdropBorderColor(0, 0, 0, 0)
            end
            card:SetParent(settingsCard)
            card:Show()
            card:SetSize(flowEntry.width, flowEntry.height)
            card:SetPoint("TOPLEFT", flowEntry.x, flowEntry.y)
            local row
            if nextFlow.settingsList then
                row = EXUI:CreateSettingsRow(card, {
                    label = field.label or field.path or field.key,
                    description = field.description,
                    controlWidth = field.controlWidth,
                    controlKind = IsModuleCommonOrdinaryField(field) and "ordinary" or nil,
                    controlMinWidth = EXUI:GetModuleCommonControlMinWidth(field),
                    inputWidthPercent = field.inputWidthPercent,
                    isLast = index == #activeFields,
                })
            end
            if field.type == "button" then
                control = EXUI:CreateButton(card, flowEntry.width - 20, GM.size.buttonHeight, field.label or path, function()
                    if disabled then return end
                    local structureResult
                    if type(field.onClick) == "function" then
                        structureResult = field.onClick(self._exCompositeDb)
                    end
                    CompositeEmitUpdate(self)
                    if type(self._exCompositeOpts.onStructureChanged) == "function" then
                        self._exCompositeOpts.onStructureChanged(structureResult)
                    end
                end, { variant = field.variant })
                control:SetPoint("TOPLEFT", 10, -16)
                kind = "button"
            elseif field.type == "checkbox" then
                control = EXUI:CreateCheckbox(card, field.label or path, value == true, function(v)
                    if not disabled then self._exModuleCommonSetValue(path, v == true) end
                end)
                control:SetPoint("TOPLEFT", 10, -11)
                kind = "check"
            elseif field.type == "dropdown" then
                control = EXUI:CreateDropdown(card, flowEntry.width - 20, field.label or path, field.items or {}, value, function(v)
                    if not disabled then self._exModuleCommonSetValue(path, v) end
                end)
                control:SetPoint("TOPLEFT", 10, -25)
                kind = "dropdown"
            elseif field.type == "lsm_background" or field.type == "lsm_border" or field.type == "lsm_texture" then
                local mediaType = field.type == "lsm_background" and "background"
                    or (field.type == "lsm_border" and "border" or "statusbar")
                control = EXUI:CreateLSMTextureDropdown(card, mediaType, flowEntry.width - 20, field.label or path, value, function(v)
                    if not disabled then self._exModuleCommonSetValue(path, v) end
                end)
                control:SetPoint("TOPLEFT", 10, -25)
                kind = "dropdown"
            elseif field.type == "input" then
                control = EXUI:CreateEditBox(card, tostring(value or ""), flowEntry.width - 20, GM.size.inputHeight, field.label or path, {
                    labelPos = "top",
                    onEnter = function(v) if not disabled then SetValue(path, v or "") end end,
                    onEditFocusLost = function(v) if not disabled then SetValue(path, v or "") end end,
                })
                control:SetPoint("TOPLEFT", 10, -16)
                kind = "edit"
            elseif field.type == "color" then
                -- 颜色值仍按现有 R/G/B/A 字段保存；仅由通用封装组承载，
                -- 不让模块退回为四个散装滑动条。
                -- A disabled field is presentation only. In particular, do not
                -- create a missing parent table in the module's real config.
                local colorDB, colorKey = disabled and {} or self._exCompositeDb, path
                local colorParentPath, directColorKey = path:match("^(.*)%.([^%.]+)$")
                if not disabled and colorParentPath and directColorKey then
                    local target = self._exCompositeDb
                    for part in string.gmatch(colorParentPath, "[^%.]+") do
                        target[part] = type(target[part]) == "table" and target[part] or {}
                        target = target[part]
                    end
                    colorDB, colorKey = target, directColorKey
                end
                control = EXUI:CreateColorButton(card, field.label or path, colorDB, colorKey, true, function()
                    if disabled then return end
                    if type(self._exCompositeOpts.onFieldChanged) == "function" then
                        self._exCompositeOpts.onFieldChanged(self._exCompositeDb, path)
                    end
                    if not NotifyModuleCommonField(path) then CompositeEmitUpdate(self) end
                end)
                control:SetPoint("TOPLEFT", 10, -14)
                kind = "color"
            else
                local lifecycle = not disabled and CreateModuleCommonNotifyFlow(path) or nil
                if lifecycle then
                    control = EXUI:CreateSlider(card, flowEntry.width - 20, field.label or path,
                        tonumber(field.min) or 0, tonumber(field.max) or 100, tonumber(value) or tonumber(field.min) or 0,
                        tonumber(field.step) or 1, nil, lifecycle)
                else
                    control = EXUI:CreateSlider(card, flowEntry.width - 20, field.label or path,
                        tonumber(field.min) or 0, tonumber(field.max) or 100, tonumber(value) or tonumber(field.min) or 0,
                        tonumber(field.step) or 1, nil, function(v)
                            if not disabled then self._exModuleCommonSetValue(path, v) end
                        end)
                end
                control:SetPoint("TOPLEFT", 10, -8)
                kind = "slider"
            end
            if not disabled and field.type ~= "button" then
                RegisterCompositeControl(self, control, path, kind)
            end
                if row and control then
                    EXUI:PrepareSettingsListControl(control, {
                        hideLabel = true,
                        presentation = field.presentation or ((self._exCompositeOpts
                            and self._exCompositeOpts._exTypedSettings == true
                            and field.type == "checkbox") and "switch" or nil),
                        ordinaryControl = IsModuleCommonOrdinaryField(field),
                        valuePosition = field.type == "slider" and (field.valuePosition or "right") or nil,
                    })
                end
                if control then
                    -- A pooled control may have served a disabled field on the
                    -- previous mount. Restore the original enabled state too.
                    local enabled = not disabled
                    if control.SetEnabled then control:SetEnabled(enabled) end
                    for _, key in ipairs({"checkbox", "numberInput", "Slider", "Back", "Forward"}) do
                        local part = control[key]
                        if part and part.SetEnabled then part:SetEnabled(enabled) end
                    end
                end
                self._exModuleCommonEntries[index] = {
                    card = card, control = control, kind = kind, field = field, row = row,
                }
            end
        end
    end
    group._exModuleCommonSetValue = SetValue
    group:_exBuildModuleCommonEntries(flow)

    group._exApplyModuleCommonFlow = function(self, nextFlow)
        self._exModuleCommonFlow = nextFlow
        -- 只有在线编辑器新增的空背景卡片允许其 layout.h 控制高度。其余
        -- ModuleCommon 仍由真实 fields Flow 固定高度，避免正式页面产生空白或裁切。
        if self._exCompositeOpts and self._exCompositeOpts.gridEditableHeight == true then
            self._exGridFixedHeight = nil
        else
            self._exGridFixedHeight = nextFlow.height
        end
        self:SetSize(nextFlow.width, nextFlow.height)
        EXUI:ClearControlSurface(self)
        local cardInsetX = tonumber(nextFlow.cardInsetX)
        if cardInsetX == nil then cardInsetX = nextFlow.padding or 0 end
        local cardInsetY = tonumber(nextFlow.cardInsetY) or 8
        local cardBottomInset = tonumber(nextFlow.cardBottomInset) or cardInsetY
        content:ClearAllPoints()
        content:SetPoint("TOPLEFT", 0, 0)
        content:SetSize(nextFlow.width, math.max(1, nextFlow.height))
        settingsCard:ClearAllPoints()
        settingsCard:SetPoint("TOPLEFT", content, "TOPLEFT", cardInsetX, -cardInsetY)
        local cardHeight = tonumber(nextFlow.cardHeight)
            or math.max(1, nextFlow.height - cardInsetY - cardBottomInset)
        settingsCard:SetSize(nextFlow.width - cardInsetX * 2, cardHeight)
        if nextFlow.settingsList then
            settingsCard:SetSize(nextFlow.width, nextFlow.height)
            for index, entry in ipairs(nextFlow.entries) do
                local mounted = self._exModuleCommonEntries[index]
                if mounted then
                    local rowHeight, controlX, controlY, controlWidth = EXUI:UpdateSettingsRowLayout(
                        mounted.row, entry.width, entry.controlHeight)
                    mounted.card:ClearAllPoints()
                    mounted.card:SetPoint("TOPLEFT", settingsCard, "TOPLEFT", 0, entry.y)
                    mounted.card:SetSize(entry.width, rowHeight)
                    mounted.row:ClearAllPoints()
                    mounted.row:SetPoint("TOPLEFT", mounted.card, "TOPLEFT", 0, 0)
                    local control = mounted.control
                    if control then
                        if control.SetWidth then control:SetWidth(controlWidth) end
                        EXUI:UpdateSettingsListControlLayout(control, controlWidth)
                        control:ClearAllPoints()
                        local actualHeight = control.GetHeight and control:GetHeight() or entry.controlHeight
                        local visualInset = math.max(0, (entry.controlHeight - actualHeight) * 0.5)
                        control:SetPoint("TOPLEFT", mounted.card, "TOPLEFT", controlX, -(controlY + visualInset))
                    end
                end
            end
            return
        end
        for index, entry in ipairs(nextFlow.entries) do
            local mounted = self._exModuleCommonEntries[index]
            if mounted then
                mounted.card:ClearAllPoints()
                mounted.card:SetPoint("TOPLEFT", settingsCard, "TOPLEFT",
                    entry.x - (nextFlow.entryOriginX or nextFlow.padding or 0), entry.y + nextFlow.contentTopInset)
                mounted.card:SetSize(entry.width, entry.height)
                local control = mounted.control
                if control then
                    if control.SetWidth then control:SetWidth(math.max(1, entry.width - 20)) end
                    control:ClearAllPoints()
                    if mounted.kind == "button" or mounted.kind == "edit" then
                        control:SetPoint("TOPLEFT", 10, -16)
                    elseif mounted.kind == "check" then
                        control:SetPoint("TOPLEFT", 10, -11)
                    elseif mounted.kind == "color" then
                        control:SetPoint("TOPLEFT", 10, -14)
                    else
                        control:SetPoint("TOPLEFT", 10, -25)
                    end
                end
            end
        end
    end
    group._exCompositeReflow = function(self, nextWidth)
        self:_exApplyModuleCommonFlow(EXUI:BuildModuleCommonSettingsFlow(nextWidth, self._exCompositeOpts))
    end
    EXUI:LayoutCompositeGroup(group, groupWidth, groupHeight)

    group.RefreshFromDB = function(self)
        BindCompositeGroup(self, self._exCompositeDb, self._exCompositeOnUpdate, self._exCompositeOpts)
    end
    AttachCompositeRelease(group)
    return group
end

-- =========================================================
-- 20.1 通用锚点设置组
-- 只管理 DB 字段与页面操作；实际 Frame 创建、拖动与依附仍由 AnchorController 负责。
-- =========================================================
function EXUI:CreateAnchorGroup(parent, width, label, db, key, onUpdate, opts)
    opts = type(opts) == "table" and opts or {}
    if key and type(db) == "table" then
        db[key] = type(db[key]) == "table" and db[key] or {}
        db = db[key]
    end
    db = type(db) == "table" and db or {}

    local xKey = opts.offsetXKey or "x"
    local yKey = opts.offsetYKey or "y"
    local attachKey = opts.attachEnabledKey or "attachToCustom"
    local targetKey = opts.attachTargetKey or "customAttachTarget"
    local supportsCustomAttach = opts.allowCustomAttach ~= false
    local defaultX = tonumber(opts.defaultOffsetX) or 0
    local defaultY = tonumber(opts.defaultOffsetY) or 0
    local groupWidth = width or 760
    -- 锚点组就是一行标准设置行：左边标签，右边依次是目标框架输入框、选择框架按钮、启用开关。
    local groupHeight = GM.settings.rowMinHeight

    if db[xKey] == nil then db[xKey] = defaultX end
    if db[yKey] == nil then db[yKey] = defaultY end
    if supportsCustomAttach and db[attachKey] == nil then db[attachKey] = false end
    if supportsCustomAttach and db[targetKey] == nil then db[targetKey] = "" end

    local group, isNew = AcquireCompositeGroup("CompositeAnchorGroup", parent)
    group._exCompositeLabel = label or L["锚点设置"]
    BindCompositeGroup(group, db, onUpdate, opts)
    if not isNew then
        AttachCompositeRelease(group)
        EXUI:LayoutCompositeGroup(group, groupWidth, groupHeight)
        EXUI:ClearControlSurface(group)
        if group._exAnchorRefresh then group:_exAnchorRefresh() end
        return group
    end

    local proxy = CreateCompositeProxy(group)
    db = proxy
    group:SetSize(groupWidth, groupHeight)
    EXUI:ClearControlSurface(group)

    local function EmitUpdate(field) CompositeEmitUpdate(group, field) end
    -- 锚点是否启用只控制是否跟随目标；X/Y 仍是模块自身的控件配置，不能在此覆盖。
    -- 输入框与选择器常驻，方便先填路径再启用，不因开关状态造成控件跳动。
    local attach, target, picker, row
    if supportsCustomAttach then
        row = EXUI:CreateSettingsRow(group, { label = L["启用自由依附"], isLast = true })
        group._exAnchorRow = row
        attach = EXUI:CreateCheckbox(group, L["启用"], db[attachKey] == true, function(value)
            db[attachKey] = value == true
            EmitUpdate(attachKey)
        end)
        EXUI:PrepareSettingsListControl(attach, { presentation = "switch", hideLabel = true })
        RegisterCompositeControl(group, attach, attachKey, "check")

        target = EXUI:CreateEditBox(group, tostring(db[targetKey] or ""), 180, GM.settings.controlHeight, nil, {
            onEnter = function(value) db[targetKey] = value or ""; EmitUpdate(targetKey) end,
            onEditFocusLost = function(value) db[targetKey] = value or ""; EmitUpdate(targetKey) end,
        })
        RegisterCompositeControl(group, target, targetKey, "edit")

        picker = EXUI:CreateButton(group, 108, GM.settings.controlHeight, L["选择框架"], function()
            if type(group._exCompositeOpts.onPickFrame) == "function" then
                group._exCompositeOpts.onPickFrame(group._exCompositeDb)
            end
        end)
        picker:SetShown(type(opts.onPickFrame) == "function")
    end

    group._anchorDb = proxy
    group._exCompositeReflow = function(self, nextWidth)
        EXUI:ClearControlSurface(self)
        if not supportsCustomAttach then return end
        local gap = GM.space.dialogButtonGap
        local controlHeight = GM.settings.controlHeight
        local switchWidth = GM.size.switchTrackWidth
        local pickerWidth = picker:IsShown() and picker:GetWidth() or 0
        local fixed = switchWidth + gap + (pickerWidth > 0 and (pickerWidth + gap) or 0)
        -- 控件列：输入框按剩余宽度伸缩，但不窄于设置行控件最小宽，也不超过 260。
        local available = math.max(1, nextWidth - GM.settings.rowPaddingX * 2)
        local inputWidth = math.max(GM.settings.controlMinWidth,
            math.min(260, available - fixed - GM.settings.controlMinWidth - GM.settings.labelControlGap))
        row._exSettingsRowControlWidth = fixed + inputWidth
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
        local height, controlX, controlY = EXUI:UpdateSettingsRowLayout(row, nextWidth, controlHeight, nil)
        self:SetHeight(height)
        local x = controlX
        target:ClearAllPoints(); target:SetSize(inputWidth, controlHeight)
        target:SetPoint("TOPLEFT", row, "TOPLEFT", x, -controlY)
        x = x + inputWidth + gap
        picker:ClearAllPoints()
        if pickerWidth > 0 then
            picker:SetHeight(controlHeight)
            picker:SetPoint("TOPLEFT", row, "TOPLEFT", x, -controlY)
            x = x + pickerWidth + gap
        end
        attach:ClearAllPoints(); attach:SetSize(switchWidth, controlHeight)
        attach:SetPoint("TOPLEFT", row, "TOPLEFT", x, -controlY)
    end
    EXUI:LayoutCompositeGroup(group, groupWidth, groupHeight)
    AttachCompositeRelease(group)
    return group
end

-- =========================================================
-- 21. 通用材质设置组
-- 用于普通 / Aura 显示的静态材质外观；宿主决定数据来源与生命周期。
-- =========================================================
function EXUI:CreateTextureGroup(parent, width, label, db, key, onUpdate, opts)
    opts = type(opts) == "table" and opts or {}
    if key and type(db) == "table" then
        db[key] = type(db[key]) == "table" and db[key] or {}
        db = db[key]
    end
    db = type(db) == "table" and db or {}
    local defaults = {
        fileID = "", width = 128, height = 128, x = 0, y = 0,
        alpha = 1, scale = 1, rotation = 0, flipH = false, flipV = false,
        colorR = 1, colorG = 1, colorB = 1, colorA = 1, blendMode = "BLEND",
    }
    for field, value in pairs(defaults) do
        if db[field] == nil then db[field] = value end
    end

    local groupWidth = width or 760
    local group, isNew = AcquireCompositeGroup("CompositeTextureGroup", parent)
    group._exCompositeLabel = label or L["材质"]
    BindCompositeGroup(group, db, onUpdate, opts)
    if not isNew then
        AttachCompositeRelease(group)
        EXUI:LayoutCompositeGroup(group, groupWidth, 250)
        if group._exTextureConfigure then group:_exTextureConfigure() end
        return group
    end
    local proxy = CreateCompositeProxy(group)
    db = proxy
    group:SetSize(groupWidth, 250)
    group:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    group:SetBackdropColor(unpack(MC.panel))
    group:SetBackdropBorderColor(unpack(MC.border))

    local title = EXUI:CreateVisualFontString(group, EXFONTFRAME, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -8)
    title:SetText(group._exCompositeLabel)
    StyleModernTitle(title)
    group._exCompositeTitle = title

    local function EmitUpdate() CompositeEmitUpdate(group) end
    local function AddSlider(field, titleText, minValue, maxValue, step, x, y, controlWidth)
        local slider = EXUI:CreateSlider(group, controlWidth or 170, titleText, minValue, maxValue, db[field], step, nil,
            function(value)
                db[field] = value
                EmitUpdate()
            end, { numberInputPosition = "title", showFill = field ~= "x" and field ~= "y" })
        slider:SetPoint("TOPLEFT", x, y)
        return RegisterCompositeControl(group, slider, field, "slider")
    end

    local fileInput = EXUI:CreateEditBox(group, tostring(db.fileID or ""), math.min(310, groupWidth - 48), GM.size.inputHeight,
        L["FileDataID / 路径"], {
            onEnter = function(value)
                db.fileID = tostring(value or "")
                EmitUpdate()
            end,
            onEditFocusLost = function(value)
                db.fileID = tostring(value or "")
                EmitUpdate()
            end,
            labelPos = "top",
        })
    fileInput:SetPoint("TOPLEFT", 16, -54)
    RegisterCompositeControl(group, fileInput, "fileID", "edit")

    -- 选择器是材质组件本身的可选能力。模块只能提供“如何挑选”的
    -- 回调，不能在自己的 Editor 里再创建/定位一枚私有按钮；这样池化
    -- 后也始终读取本次绑定的 DB 与回调。
    local texturePicker = EXUI:CreateButton(group, 108, GM.size.buttonHeight, opts.pickerLabel or L["选择材质"], function()
        local activeOpts = group._exCompositeOpts or {}
        if type(activeOpts.onPickTexture) ~= "function" then return end
        activeOpts.onPickTexture(group._exCompositeDb and group._exCompositeDb.fileID, function(textureID)
            if type(group._exCompositeDb) ~= "table" then return end
            group._exCompositeDb.fileID = tostring(textureID or "")
            EXUI:RefreshCompositeGroupFromDB(group)
            CompositeEmitUpdate(group)
        end)
    end)
    texturePicker:SetPoint("TOPRIGHT", -16, -54)
    group._exTexturePickerButton = texturePicker
    group._exTextureConfigure = function(self)
        local activeOpts = self._exCompositeOpts or {}
        local picker = self._exTexturePickerButton
        if not picker then return end
        if picker.SetText then picker:SetText(activeOpts.pickerLabel or L["选择材质"]) end
        picker:SetShown(type(activeOpts.onPickTexture) == "function")
    end
    group:_exTextureConfigure()

    local widthSlider = AddSlider("width", L["宽度"], 1, 1024, 1, 16, -116)
    local heightSlider = AddSlider("height", L["高度"], 1, 1024, 1, 204, -116)
    local xSlider = AddSlider("x", L["X 偏移"], -1000, 1000, 1, 392, -116)
    local ySlider = AddSlider("y", L["Y 偏移"], -1000, 1000, 1, 580, -116)
    local alphaSlider = AddSlider("alpha", L["透明度"], 0, 1, 0.05, 16, -176)
    local scaleSlider = AddSlider("scale", L["缩放"], 0.05, 5, 0.05, 204, -176)
    local rotationSlider = AddSlider("rotation", L["旋转"], -180, 180, 1, 392, -176)

    local color = EXUI:CreateColorButton(group, L["材质颜色"], db, "color", true, EmitUpdate)
    color:SetPoint("TOPLEFT", 580, -164)
    RegisterCompositeControl(group, color, "color", "color")
    local blend = EXUI:CreateDropdown(group, math.min(220, groupWidth - 48), L["混合模式"], {
        { "BLEND", "BLEND" }, { "ADD", "ADD" }, { "MOD", "MOD" },
        { "ALPHAKEY", "ALPHAKEY" }, { "DISABLE", "DISABLE" },
    }, db.blendMode, function(value)
        db.blendMode = value
        EmitUpdate()
    end)
    blend:SetPoint("TOPLEFT", 16, -226)
    RegisterCompositeControl(group, blend, "blendMode", "dropdown")

    local flipH = EXUI:CreateCheckbox(group, L["水平翻转"], db.flipH, function(value)
        db.flipH = value
        EmitUpdate()
    end)
    flipH:SetPoint("TOPLEFT", 254, -222)
    RegisterCompositeControl(group, flipH, "flipH", "check")
    local flipV = EXUI:CreateCheckbox(group, L["垂直翻转"], db.flipV, function(value)
        db.flipV = value
        EmitUpdate()
    end)
    flipV:SetPoint("TOPLEFT", 394, -222)
    RegisterCompositeControl(group, flipV, "flipV", "check")
    group._textureDb = proxy
    group._exCompositeReflow = function(self, nextWidth, nextHeight)
        local columnWidth = math.max(120, math.floor((nextWidth - 68) / 4))
        local col1 = 16
        local col2 = col1 + columnWidth + 18
        local col3 = col2 + columnWidth + 18
        local col4 = col3 + columnWidth + 18
        local fileWidth = math.min(310, math.max(160, nextWidth - 48))
        fileInput:SetWidth(fileWidth)
        texturePicker:ClearAllPoints(); texturePicker:SetPoint("TOPRIGHT", self, "TOPRIGHT", -16, -54)
        local top = { widthSlider, heightSlider, xSlider, ySlider }
        local topX = { col1, col2, col3, col4 }
        for index, slider in ipairs(top) do
            slider:SetWidth(columnWidth)
            slider:ClearAllPoints(); slider:SetPoint("TOPLEFT", self, "TOPLEFT", topX[index], -116)
        end
        for index, slider in ipairs({ alphaSlider, scaleSlider, rotationSlider }) do
            slider:SetWidth(columnWidth)
            slider:ClearAllPoints(); slider:SetPoint("TOPLEFT", self, "TOPLEFT", topX[index], -176)
        end
        color:ClearAllPoints(); color:SetPoint("TOPLEFT", self, "TOPLEFT", col4, -164)
        blend:SetWidth(math.min(220, math.max(120, nextWidth - 48)))
        flipH:ClearAllPoints(); flipH:SetPoint("TOPLEFT", self, "TOPLEFT", col2 + 50, -222)
        flipV:ClearAllPoints(); flipV:SetPoint("TOPLEFT", self, "TOPLEFT", col3 + 2, -222)
    end
    EXUI:LayoutCompositeGroup(group, groupWidth, 250)
    AttachCompositeRelease(group)
    return group
end

-- 标准组合控件的无副作用 Grid 测量。数值与各 Create*Group 的实际 SetSize
-- 完全一致；将来修改控件高度时，必须同时改这里或改成共享常量，不能让 schema
-- 猜测内部控件树的高度。
local function FixedGridMeasure(height)
    return function()
        return { minHeight = height, preferredHeight = height }
    end
end

EXUI:RegisterGridComponentMeasure("slider", FixedGridMeasure(EXUI.GridSliderHeight))
-- 字体/图标/计时条的高度与 Create*Group 的实际摆放读同一个 *GroupLayout 函数。
local function ColumnsGroupMeasure(buildLayout)
    return function(width, opts)
        local height = buildLayout(width, opts).height
        return { minHeight = height, preferredHeight = height }
    end
end
EXUI:RegisterGridComponentMeasure("fontgroup", ColumnsGroupMeasure(FontGroupLayout))
EXUI:RegisterGridComponentMeasure("icongroup", ColumnsGroupMeasure(IconGroupLayout))
EXUI:RegisterGridComponentMeasure("timerbargroup", ColumnsGroupMeasure(TimerBarGroupLayout))
EXUI:RegisterGridComponentMeasure("texturegroup", FixedGridMeasure(250))
EXUI:RegisterGridComponentMeasure("anchorgroup", FixedGridMeasure(GM.settings.rowMinHeight))
-- 发光设置组在 V2 里由已挂载的组自己量（_exMeasureHeight）；这里只给没挂载时的估算：每行按最小行高。
EXUI:RegisterGridComponentMeasure("glow_settings", function(width, opts, db, item)
    local key = type(item) == "table" and item.key or "glow"
    db = type(db) == "table" and db or {}
    local rowHeight = (type(opts.style) == "table" and opts.style.rowMinHeight) or GM.settings.rowMinHeight
    local height = rowHeight
    if db[key .. "Enabled"] ~= false then
        local flow = (db[key .. "Style"] or GLOW_DEFAULTS.Style) == "EDGE_FLOW"
        local count = 1
        for _, spec in ipairs(GLOW_PARAMS) do
            if spec.flow == nil or spec.flow == flow then count = count + 1 end
        end
        height = height + count * rowHeight + GlowTilesBlockHeight(width, GM.settings.rowPaddingX)
    end
    return { minHeight = height, preferredHeight = height }
end)
EXUI:RegisterGridComponentMeasure("soundgroup", function(width, opts)
    local height = EXUI:BuildSoundGroupLayout(width, opts).height
    return { minHeight = height, preferredHeight = height }
end)
EXUI:RegisterGridComponentMeasure("widgetlayout", function(width, opts)
    local height = BuildWidgetLayoutSettingsFlow(width, opts).height
    return { minHeight = height, preferredHeight = height }
end)
EXUI:RegisterGridComponentMeasure("modulecommonsettings", function(width, opts)
    local flow = EXUI:BuildModuleCommonSettingsFlow(width, opts)
    return { minHeight = flow.height, preferredHeight = flow.height }
end)

-- Shared presentation for modal decisions, status feedback, and context actions.
-- These factories own only frames; callers retain their existing data and callbacks.
local function FeedbackColors()
    return ExwindTools.GUIColors
end

local function FeedbackText(parent, size, color, text)
    local font = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    local path = (GameFontHighlight:GetFont())
    font:SetFont(path, size, "")
    font:SetTextColor(unpack(color))
    font:SetJustifyH("LEFT")
    font:SetText(text or "")
    return font
end

local function PlaceClamped(frame, x, y)
    local width, height = frame:GetSize()
    local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
    local left = math.max(4, math.min(x or 0, screenWidth - width - 4))
    local top = math.max(height + 4, math.min(y or screenHeight, screenHeight - 4))
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

-- Buttons are declared left-to-right, anchored as a group to the right.
-- Only presentation values live here; actions and data remain owned by callers.
local function DialogPlainText(text)
    return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function DialogResult(dialog, id)
    return { button = id, text = dialog.activeInput and dialog.activeInput:GetText() or nil,
        checked = dialog.checkbox:IsShown() and dialog.checkbox:GetChecked() or false }
end

function EXUI:CloseDialog(reason)
    local overlay = self._dialogOverlay
    if not overlay or not overlay.options then return end
    local options, dialog = overlay.options, overlay.dialog
    local result = DialogResult(dialog, reason or "cancel")
    overlay.options = nil
    overlay.fade:Stop()
    if dialog.activeInput then
        dialog.activeInput:ClearFocus()
        dialog.activeInput:SetScript("OnKeyUp", nil)
    end
    dialog.activeInput = nil
    overlay:Hide()
    for _, button in ipairs(dialog.buttons) do button._dialogAction = nil end
    if options.content and options.content.unmount then options.content.unmount(dialog.content, dialog) end
    if options.onClose then options.onClose(result, reason or "cancel") end
    return result
end

local function ActivateDialogButton(dialog, index)
    local overlay = EXUI._dialogOverlay
    if not overlay or not overlay.options then return end
    local action = overlay.options.buttons[index]
    if not action or action.disabled then return end
    local result = DialogResult(dialog, action.id)
    local callback = action.onClick
    if action.close ~= false then EXUI:CloseDialog(action.id) end
    if callback then callback(result, dialog) end
end

local function CancelDialog()
    local overlay = EXUI._dialogOverlay
    if not overlay or not overlay.options then return end
    local options, dialog = overlay.options, overlay.dialog
    for index, action in ipairs(options.buttons) do
        if action.id == options.cancelButton then ActivateDialogButton(dialog, index); return end
    end
    local result = EXUI:CloseDialog("cancel")
    if options.onCancel then options.onCancel(result) end
end

local function FocusDialogButton(dialog, index)
    dialog.focusIndex = index
    for i, button in ipairs(dialog.buttons) do EXUI:SetButtonKeyboardFocus(button, i == index) end
end

local function HandleDialogKey(key, fromInput)
    local overlay = EXUI._dialogOverlay
    if not overlay or not overlay.options then return end
    local options, dialog = overlay.options, overlay.dialog
    if key == "ESCAPE" then
        if options.cancelOnEscape ~= false then CancelDialog() end
    elseif key == "TAB" then
        if dialog.activeInput then dialog.activeInput:ClearFocus() end
        local count, step = #options.buttons, IsShiftKeyDown() and -1 or 1
        local index = dialog.focusIndex or (step == 1 and 0 or 1)
        for _ = 1, count do
            index = (index - 1 + step) % count + 1
            if not options.buttons[index].disabled then FocusDialogButton(dialog, index); break end
        end
    elseif key == "ENTER" then
        if options.danger or options.enterConfirms == false then return end
        if fromInput and options.input and options.input.multiline then return end
        ActivateDialogButton(dialog, dialog.focusIndex or dialog.defaultIndex or 1)

    end
end

function EXUI:ShowDialog(options)
    assert(type(options) == "table" and type(options.buttons) == "table" and #options.buttons > 0,
        "ShowDialog requires a non-empty buttons array")
    local ids, hasDanger = {}, options.danger == true
    for _, action in ipairs(options.buttons) do
        assert(type(action.id) == "string" and not ids[action.id], "dialog buttons require unique ids")
        assert(type(action.text) == "string", "dialog buttons require text")
        ids[action.id] = true
        hasDanger = hasDanger or action.variant == "dangerSolid" or action.variant == "danger"
    end
    if hasDanger then options.danger = true end
    if self.HideContextMenu then self:HideContextMenu() end
    self:CloseDialog("replaced")
    local c, overlay = FeedbackColors(), self._dialogOverlay
    if not overlay then
        overlay = CreateFrame("Button", nil, UIParent)
        overlay:Hide()
        overlay:SetAllPoints(UIParent)
        overlay:SetFrameStrata("FULLSCREEN_DIALOG")
        overlay:SetFrameLevel(9600)
        overlay:EnableMouse(false)
        -- 弹窗不拦任何按键（移动、技能照常），关闭只靠按钮和右上角叉。
        overlay:EnableKeyboard(false)
        local dialog = CreateFrame("Frame", nil, overlay)
        dialog:SetPoint("CENTER", UIParent, "CENTER")
        dialog:SetFrameLevel(9602)
        dialog:EnableMouse(true)
        dialog:SetMovable(true)
        dialog:SetClampedToScreen(true)
        dialog:RegisterForDrag("LeftButton")
        dialog:SetScript("OnDragStart", function(frame) frame:StartMoving() end)
        dialog:SetScript("OnDragStop", function(frame) frame:StopMovingOrSizing() end)
        dialog.buttons = {}
        dialog.title = FeedbackText(dialog, GM.font.dialogTitle, c.dialogTitle, "")
        dialog.title:SetPoint("TOPLEFT", GM.space.dialogPaddingX, -GM.space.dialogPaddingY)
        -- 标题右界避开关闭按钮。
        dialog.title:SetPoint("TOPRIGHT",
            -(GM.space.dialogPaddingX + GM.size.dialogCloseSize + GM.space.descriptionGap),
            -GM.space.dialogPaddingY)
        -- 来源行紧随标题，与标题同宽；正文起点由标题区实际高度推算（见下方 bodyTop）。
        dialog.source = FeedbackText(dialog, GM.font.small, c.textDim, "")
        dialog.source:SetPoint("TOPLEFT", dialog.title, "BOTTOMLEFT", 0, -GM.space.descriptionGap)
        dialog.source:SetPoint("TOPRIGHT", dialog.title, "BOTTOMRIGHT", 0, -GM.space.descriptionGap)
        dialog.source:SetWordWrap(false)
        local close = CreateFrame("Button", nil, dialog)
        close:SetSize(GM.size.dialogCloseSize, GM.size.dialogCloseSize)
        -- 关闭按钮比正文内边距略紧：按钮自身已有视觉留白。
        close:SetPoint("TOPRIGHT", -GM.space.dialogSectionGap, -GM.space.dialogSectionGap)
        close:SetScript("OnClick", CancelDialog)
        local closeIcon = self:CreateVisualTexture(close, EXBORDERFRAME)
        closeIcon:SetTexture(self:GetIcon("x"))
        closeIcon:SetSize(GM.size.dialogCloseGlyphSize, GM.size.dialogCloseGlyphSize)
        closeIcon:SetPoint("CENTER")
        closeIcon:SetVertexColor(unpack(c.textDim))
        close:SetScript("OnEnter", function() closeIcon:SetVertexColor(unpack(c.text)) end)
        close:SetScript("OnLeave", function() closeIcon:SetVertexColor(unpack(c.textDim)) end)
        dialog.closeButton = close
        dialog.body = FeedbackText(dialog, GM.font.label, c.text, "")
        dialog.body:SetJustifyV("TOP")
        -- 勾选框沿用公共 checkboxBoxSize：不在调用点改子 Frame 尺寸，否则
        -- painter 画的勾选面与命中框脱节（全项目只有这里曾改成 16）。
        dialog.checkbox = self:CreateCheckbox(dialog, "", false, nil)
        dialog.content = CreateFrame("Frame", nil, dialog)
        dialog.Close = function(_, reason) if overlay:IsShown() then return EXUI:CloseDialog(reason) end end
        dialog.GetResult = function() return DialogResult(dialog) end
        overlay.dialog = dialog
        overlay.fade = overlay:CreateAnimationGroup()
        local fade = overlay.fade:CreateAnimation("Alpha")
        fade:SetFromAlpha(0); fade:SetToAlpha(1); fade:SetDuration(.12)
        overlay.fade:SetScript("OnFinished", function() overlay:SetAlpha(1) end)
        self._dialogOverlay = overlay
    end
    overlay.options = options
    local dialog = overlay.dialog
    dialog._dialogToken = (dialog._dialogToken or 0) + 1
    dialog.focusIndex, dialog.defaultIndex = nil, nil
    local padX, gap = GM.space.dialogPaddingX, GM.space.dialogSectionGap
    local width = math.max(320, math.min(options.width or 380, UIParent:GetWidth() - padX * 2))
    dialog:ClearAllPoints(); dialog:SetPoint("CENTER", UIParent, "CENTER")
    dialog:SetWidth(width)
    local source = DialogPlainText(options.sourceAddon or "ExwindCore")
    if options.sourceModule and options.sourceModule ~= "" then
        source = source .. " · " .. DialogPlainText(options.sourceModule)
    end
    dialog.source:SetText(source)
    dialog.title:SetText(DialogPlainText(options.title or L["提示"]))
    dialog.title:SetTextColor(unpack(c.dialogTitle))
    dialog.source:SetTextColor(unpack(c.textDim))
    dialog.body:SetTextColor(unpack(c.text))
    dialog.body:ClearAllPoints()
    -- 正文起点 = 标题区实际高度（标题 + 来源两行）后再留一个区段间距；
    -- 文本高度取不到时退回字号，不让布局整体上移。
    local titleHeight = math.max(dialog.title:GetStringHeight() or 0, GM.font.dialogTitle)
    local sourceHeight = math.max(dialog.source:GetStringHeight() or 0, GM.font.small)
    local bodyTop = GM.space.dialogPaddingY + titleHeight + GM.space.descriptionGap + sourceHeight + gap
    dialog.body:SetPoint("TOPLEFT", padX, -bodyTop)
    dialog.body:SetWidth(width - padX * 2)
    dialog.body:SetText(DialogPlainText(options.text))
    local y = bodyTop + (dialog.body:GetStringHeight() or 0)
    if dialog.singleInput then dialog.singleInput:Hide() end
    if dialog.multiInput then dialog.multiInput:Hide() end
    if options.input then
        local input = options.input
        local key = input.multiline and "multiInput" or "singleInput"
        local inputHeight = input.multiline and (input.height or 180) or GM.size.inputHeight
        if not dialog[key] then dialog[key] = self:CreateEditBox(dialog, "", width - padX * 2, inputHeight) end
        local holder = dialog[key]
        local edit = holder.editBox or holder
        dialog.activeInput = edit
        edit:SetScript("OnKeyUp", nil)
        holder:ClearAllPoints(); holder:SetPoint("TOPLEFT", padX, -y - gap)
        holder:SetSize(width - padX * 2, inputHeight); holder:Show()
        -- 多行输入自带滚动条与内边距，文字宽度再内收 26。
        if input.multiline then edit:SetWidth(width - padX * 2 - 26) end
        edit:SetMaxLetters(input.maxLetters or 0)
        if not edit._dialogTextHandlerSaved then
            edit._dialogBaseTextChanged = edit:GetScript("OnTextChanged")
            edit._dialogTextHandlerSaved = true
        end
        edit:SetScript("OnTextChanged", nil)
        edit:SetText(input.text or "")
        edit:SetScript("OnTextChanged", function(box, userInput)
            if box._dialogBaseTextChanged then box._dialogBaseTextChanged(box, userInput) end
            if not userInput then return end
            if input.readOnly then box:SetText(input.text or ""); box:HighlightText(); return end
            if input.onChanged then input.onChanged(box:GetText(), dialog) end
        end)
        edit:SetScript("OnEnterPressed", function() HandleDialogKey("ENTER", true) end)
        edit:SetScript("OnEscapePressed", function() HandleDialogKey("ESCAPE", true) end)
        edit:SetScript("OnTabPressed", function() HandleDialogKey("TAB", true) end)
        if edit._dialogBaseTextChanged then edit._dialogBaseTextChanged(edit, false) end
        y = y + gap + inputHeight
    end
    dialog.checkbox:Hide()
    if options.checkbox then
        dialog.checkbox:Show(); dialog.checkbox:ClearAllPoints()
        -- 勾选框容器左侧自带 1px 视觉留白，比正文内边距少 2。
        dialog.checkbox:SetPoint("TOPLEFT", padX - 2, -y - gap)
        dialog.checkbox.label:SetText(DialogPlainText(options.checkbox.text))
        dialog.checkbox.label:SetTextColor(unpack(c.text))
        dialog.checkbox:SetChecked(options.checkbox.checked == true)
        y = y + gap + GM.size.checkboxRowHeight
    end
    dialog.content:Hide()
    if options.content then
        dialog.content:SetSize(width - padX * 2, options.content.height or 120)
        dialog.content:ClearAllPoints(); dialog.content:SetPoint("TOPLEFT", padX, -y - gap)
        dialog.content:Show()
        y = y + gap + dialog.content:GetHeight()
    end
    -- 按钮用公共工厂的默认高度与最小宽；变体只经 SetButtonVariant 归一化，
    -- 调用点不写 _exButtonVariant，也不自己算内边距。
    local buttonGap = GM.space.dialogButtonGap
    local buttonHeight = GM.size.controlHeight
    local buttonRowHeight = buttonHeight + buttonGap
    local total, buttonWidths = 0, {}
    for i, action in ipairs(options.buttons) do
        local b = dialog.buttons[i]
        if not b then
            b = self:CreateButton(dialog, GM.size.buttonMinWidth, buttonHeight, "",
                function() ActivateDialogButton(dialog, i) end, { variant = action.variant })
            dialog.buttons[i] = b
        end
        b:SetText(action.text)
        b:SetEnabled(not action.disabled)
        self:SetButtonVariant(b, action.variant)
        buttonWidths[i] = math.max(GM.size.buttonMinWidth,
            b:GetFontString():GetStringWidth() + GM.space.buttonPaddingX * 2)
        total = total + buttonWidths[i] + (i > 1 and buttonGap or 0)
        if action.id == options.defaultButton then dialog.defaultIndex = i end
    end
    -- Wrap long translated labels instead of extending past the dialog edges.
    local available = width - padX * 2
    local x, buttonY, rows = 0, padX, 1
    for i = #options.buttons, 1, -1 do
        local b, bw = dialog.buttons[i], math.min(available, buttonWidths[i])
        if x > 0 and x + bw > available then x, buttonY, rows = 0, buttonY + buttonRowHeight, rows + 1 end
        b:ClearAllPoints(); b:SetSize(bw, buttonHeight)
        b:SetPoint("BOTTOMRIGHT", -padX - x, buttonY); b:Show()
        x = x + bw + buttonGap
    end
    for i = #options.buttons + 1, #dialog.buttons do dialog.buttons[i]:Hide() end
    dialog:SetHeight(y + gap + rows * buttonRowHeight + padX)
    self:SetControlSurface(dialog, GM.radius.dialog, c.dialog, c.dialogBorder)
    local focus = dialog.defaultIndex or 1
    if options.danger then
        for i, action in ipairs(options.buttons) do if action.id == options.cancelButton then focus = i; break end end
    end
    FocusDialogButton(dialog, focus)
    overlay:SetAlpha(1); overlay:Show(); overlay.fade:Play()
    if options.content and options.content.mount then options.content.mount(dialog.content, dialog) end
    if options.input and options.input.focus ~= false then
        dialog.activeInput:SetFocus()
        if options.input.highlight then dialog.activeInput:HighlightText() end
    end
    if options.onShow then options.onShow(dialog) end
    return dialog
end

-- Nonmodal pickers/viewers keep their owner and content, sharing only the shell.
function EXUI:ApplyDialogStyle(frame, titleRegion)
    local c = FeedbackColors()
    self:SetControlSurface(frame, GM.radius.dialog, c.dialog, c.dialogBorder)
    if titleRegion then titleRegion:SetTextColor(unpack(c.text)) end
end

function EXUI:HideDialog(id)
    local overlay = self._dialogOverlay
    if overlay and overlay.options and (id == nil or overlay.options.id == id) then
        return self:CloseDialog("owner-hidden")
    end
end

function EXUI:IsDialogShown(id)
    local overlay = self._dialogOverlay
    return overlay and overlay:IsShown() and overlay.options
        and (id == nil or overlay.options.id == id) or false
end

-- Existing callers retain their original confirm/cancel callback signatures.
function EXUI:ShowConfirmDialog(options)
    return self:ShowDialog({
        sourceAddon = options.sourceAddon, sourceModule = options.sourceModule,
        id = options.id, title = options.title, text = options.text, width = options.width, danger = options.danger,
        onClose = options.onClose, enterConfirms = options.enterConfirms,
        cancelOnEscape = options.cancelOnEscape, cancelOnBackdrop = options.cancelOnBackdrop,
        checkbox = options.checkboxText and { text = options.checkboxText, checked = options.checkboxChecked },
        defaultButton = "confirm", cancelButton = "cancel",
        buttons = {
            { id = "cancel", text = options.cancelText or L["取消"], onClick = function(r)
                if options.onCancel then options.onCancel(r.checked) end
            end },
            { id = "confirm", text = options.confirmText or L["确定"],
                variant = options.danger and "dangerSolid" or "primary", onClick = function(r)
                    if options.onConfirm then options.onConfirm(r.checked) end
                end },
        },
    })
end

-- 输入一行文字：EXUI:ShowInputDialog({ title, text, value, maxLetters, onConfirm = function(text), onCancel })
-- 回车确定、ESC 取消；外壳、拖动、按键与 ShowDialog 相同。
function EXUI:ShowInputDialog(options)
    return self:ShowDialog({
        sourceAddon = options.sourceAddon, sourceModule = options.sourceModule,
        id = options.id, title = options.title, text = options.text, width = options.width,
        onClose = options.onClose,
        input = { text = options.value, maxLetters = options.maxLetters, highlight = true,
            onChanged = options.onChanged },
        defaultButton = "confirm", cancelButton = "cancel",
        buttons = {
            { id = "cancel", text = options.cancelText or L["取消"], onClick = function(r)
                if options.onCancel then options.onCancel(r.text) end
            end },
            { id = "confirm", text = options.confirmText or L["确定"], variant = "primary", onClick = function(r)
                if options.onConfirm then options.onConfirm(r.text) end
            end },
        },
    })
end

-- 纯提示：EXUI:ShowAlertDialog({ title, text, onClose = function() })，只有一个确定，ESC 等同确定。
function EXUI:ShowAlertDialog(options)
    return self:ShowDialog({
        sourceAddon = options.sourceAddon, sourceModule = options.sourceModule,
        id = options.id, title = options.title, text = options.text, width = options.width,
        defaultButton = "ok", cancelButton = "ok",
        buttons = {
            { id = "ok", text = options.confirmText or L["确定"], variant = "primary", onClick = function()
                if options.onClose then options.onClose() end
            end },
        },
    })
end

function EXUI:HideConfirmDialog(accepted)
    local overlay = self._dialogOverlay
    if not overlay or not overlay.options then return end
    for i, button in ipairs(overlay.options.buttons) do
        if button.id == (accepted and "confirm" or "cancel") then ActivateDialogButton(overlay.dialog, i); return end
    end
end

-- =========================================================
-- EXAura 编辑器需要而此前 Core 没有的公共封装：
--   CreateFloatingWindow        非模态浮动窗口（可拖动，不是 ShowDialog 的模态单例）
--   CreateToggleDropdownButton  开关加下拉合一按钮
--   CreateFlowDirectionThumb / CreateFlowDirectionPicker  群组方向缩略图与 8 种方向选择
--   CreatePerLineSelector       每行个数选择
--   CreateButtonStrip           胶囊按钮组（顶部全局按钮：一条圆角胶囊分成几段）
-- 全部是纯数据选项；外观只取 GUIColors / GUIStates / GUIMetrics；组合宿主走 Factory 的
-- 组合池，借用时重绑、归还时清掉本租约的回调与子控件。不读写任何配置。
-- =========================================================
local GC = ExwindTools.GUIColors
local GS = ExwindTools.GUIStates
local Factory = _G.ExwindFactory
local MODERN_MEDIA = Internal.MODERN_MEDIA

-- ---------------------------------------------------------
-- 任何空白处拖动（EXAura 浮出物用）：EXUI:SetDragAnywhere(frame, opts) / EXUI:SetDragAnywhere(frame, nil) 关掉
--   opts = { onDragStart = function(frame)（可选，开始移动前调）, onDragStop = function(frame, x, y)（可选）,
--            fromButtons = true（可选：按在 frame 里的按钮上也能拖——移动超过阈值就改拖整个框并取消这次按钮点击，没动照常点击）}
-- 按下左键时鼠标下是 frame 本身，或 frame 里的普通 Frame / ScrollFrame（自己没有 OnMouseDown / OnMouseUp / OnDragStart，
-- 一路到 frame 都不经过按钮、输入框、滑条这类控件），拖过 GM.space.dragThreshold 像素才开始移动（单击不动）。
-- 已有原生拖动（写了 OnDragStart）的框不经这里，由它自己的脚本拖。
-- 松开后 frame 改成 TOPLEFT 贴 UIParent 左下角，x, y 就是这个偏移（frame 自己的坐标单位）：
-- 调用方恢复位置 = ClearAllPoints(); SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)。改高时顶边不动。
-- 夹不夹在屏幕内由 frame:SetClampedToScreen 决定，这里不管。
-- ---------------------------------------------------------
local SettleDraggedFrame
do
    SettleDraggedFrame = function(frame)
        local x, y = frame:GetLeft(), frame:GetTop()
        if not x then return nil, nil end
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
        return x, y
    end

    local function DragAnywhereBlank(focus, target)
        if type(focus) ~= "table" or not focus.GetObjectType then return false end
        if focus:GetScript("OnDragStart") then return false end
        if focus == target then return true end
        local kind = focus:GetObjectType()
        if kind ~= "Frame" and kind ~= "ScrollFrame" then return false end
        if focus:GetScript("OnMouseDown") or focus:GetScript("OnMouseUp") then return false end
        local parent = focus:GetParent()
        while parent and parent ~= target do
            local parentKind = parent:GetObjectType()
            if parentKind ~= "Frame" and parentKind ~= "ScrollFrame" then return false end
            parent = parent:GetParent()
        end
        return parent == target
    end

    -- fromButtons：按下时鼠标下是 target 里的按钮（一路到 target 只经过普通框、滚动框、按钮）就返回它。
    local function DragAnywhereButton(focus, target)
        if type(focus) ~= "table" or not focus.GetObjectType or focus:GetObjectType() ~= "Button" then return nil end
        if focus:GetScript("OnDragStart") then return nil end
        local parent = focus:GetParent()
        while parent and parent ~= target do
            local kind = parent:GetObjectType()
            if kind ~= "Frame" and kind ~= "ScrollFrame" and kind ~= "Button" then return nil end
            parent = parent:GetParent()
        end
        return parent == target and focus or nil
    end

    -- 拖动开始时把按下的那个按钮的 OnClick 换成一次性空函数（松手那次点击被吃掉），松手后的下一帧之前换回原脚本。
    local function DragAnywhereRestoreClick(driver)
        local swallowed = driver._exSwallowed
        if not swallowed then return end
        driver._exSwallowed = nil
        swallowed.button:SetScript("OnClick", swallowed.script)
    end

    local function DragAnywhereSwallowClick(driver, button)
        driver._exSwallowed = { button = button, script = button:GetScript("OnClick") }
        button:SetScript("OnClick", function() DragAnywhereRestoreClick(driver) end)
        button:SetButtonState("NORMAL")
    end

    local function DragAnywhereFinish(driver)
        local target, moving = driver._exTarget, driver._exMoving
        driver._exPending, driver._exMoving, driver._exButton = nil, nil, nil
        driver:SetScript("OnUpdate", nil)
        if driver._exSwallowed then C_Timer.After(0, function() DragAnywhereRestoreClick(driver) end) end
        if not moving then return end
        target:StopMovingOrSizing()
        local x, y = SettleDraggedFrame(target)
        local opts = driver._exOpts
        if opts and opts.onDragStop then opts.onDragStop(target, x, y) end
    end

    local function DragAnywhereUpdate(driver)
        if not IsMouseButtonDown("LeftButton") then DragAnywhereFinish(driver) return end
        if not driver._exPending then return end
        local x, y = GetCursorPosition()
        local threshold = GM.space.dragThreshold
        if math.abs(x - driver._exPressX) < threshold and math.abs(y - driver._exPressY) < threshold then return end
        driver._exPending, driver._exMoving = nil, true
        local target, opts = driver._exTarget, driver._exOpts
        if driver._exButton then DragAnywhereSwallowClick(driver, driver._exButton) end
        if opts.onDragStart then opts.onDragStart(target) end
        -- 开始移动前先把锚点换成 TOPLEFT 贴 UIParent（按当前屏幕位置只算一次）：
        -- 框原来贴在别的框上（贴靠目标、选中框）或用别的锚点时，StartMoving 不会再换算出跳一下的位置。
        SettleDraggedFrame(target)
        target:StartMoving()
    end

    local function DragAnywhereEvent(driver, event, button)
        if button ~= "LeftButton" or not driver._exOpts then return end
        if event == "GLOBAL_MOUSE_UP" then
            if driver._exPending or driver._exMoving then DragAnywhereFinish(driver) end
            return
        end
        local target = driver._exTarget
        local focus = GetMouseFoci()[1]
        local button = driver._exOpts.fromButtons and DragAnywhereButton(focus, target) or nil
        if not target:IsVisible() or not (button or DragAnywhereBlank(focus, target)) then return end
        driver._exButton = button
        driver._exPressX, driver._exPressY = GetCursorPosition()
        driver._exPending = true
        driver:SetScript("OnUpdate", DragAnywhereUpdate)
    end

    function EXUI:SetDragAnywhere(frame, opts)
        if type(frame) ~= "table" or type(frame.StartMoving) ~= "function" then error("SetDragAnywhere: frame must be a frame", 2) end
        if opts ~= nil then
            if type(opts) ~= "table" then error("SetDragAnywhere: opts must be a table or nil", 2) end
            for key in pairs(opts) do
                if key ~= "onDragStart" and key ~= "onDragStop" and key ~= "fromButtons" then error("SetDragAnywhere: unknown option " .. tostring(key), 2) end
            end
            if opts.fromButtons ~= nil and opts.fromButtons ~= true then error("SetDragAnywhere: fromButtons must be true or nil", 2) end
            if opts.onDragStart ~= nil and type(opts.onDragStart) ~= "function" then error("SetDragAnywhere: onDragStart must be a function", 2) end
            if opts.onDragStop ~= nil and type(opts.onDragStop) ~= "function" then error("SetDragAnywhere: onDragStop must be a function", 2) end
        end
        local driver = frame._exDragAnywhere
        if not driver then
            if opts == nil then return end
            driver = CreateFrame("Frame", nil, frame)
            driver:SetSize(1, 1)
            driver:EnableMouse(false)
            driver._exTarget = frame
            driver:SetScript("OnEvent", DragAnywhereEvent)
            frame._exDragAnywhere = driver
        end
        if driver._exMoving then frame:StopMovingOrSizing() end
        DragAnywhereRestoreClick(driver)
        driver._exPending, driver._exMoving, driver._exButton = nil, nil, nil
        driver:SetScript("OnUpdate", nil)
        driver._exOpts = opts
        if opts then
            frame:SetMovable(true)
            driver:RegisterEvent("GLOBAL_MOUSE_DOWN")
            driver:RegisterEvent("GLOBAL_MOUSE_UP")
            driver:Show()
        else
            driver:UnregisterAllEvents()
        end
    end
end

-- ---------------------------------------------------------
-- 非模态浮动窗口
-- ---------------------------------------------------------
local FLOATING_POOL = "EXUI.FloatingWindow"
Factory:InitCompositePool(FLOATING_POOL)

local FLOATING_STRATA = { DIALOG = true, FULLSCREEN_DIALOG = true }

-- 叠放规则（所有浮窗共用，只此一处）：同一层（strata）里鼠标和绘制都按 frameLevel 判谁在上，
-- 而且是按每个子框自己的 frameLevel 比，不按所属窗口比。所以每只浮窗占一段级别（FLOATING_LEVEL_STEP），
-- 提到最前 = 拿到比所有浮窗都高的一段，整棵子树（含吃鼠标的透明滚动框、卡片）一起压住下面的窗口。
-- 不用 SetToplevel / Raise：它们只动窗口本身的级别，几只窗口会挤在同一级，下面窗口更深的子框反而挡住上面窗口的按钮。
-- 子框级别随父框整体平移（窗口建好后再改级别，内容照常显示），段宽只要大过窗口内嵌套深度。
local FLOATING_LEVEL_BASE, FLOATING_LEVEL_STEP, FLOATING_LEVEL_CEILING = 1000, 200, 9000
local floatingTopLevel = FLOATING_LEVEL_BASE - FLOATING_LEVEL_STEP
local floatingWindows = setmetatable({}, { __mode = "k" })
local function RaiseFloatingWindow(window)
    window:SetFrameStrata(window._exFloatStrata)
    floatingWindows[window] = true
    local others = window:GetFrameLevel() < floatingTopLevel
    if not others then
        for other in pairs(floatingWindows) do
            if other ~= window and other:IsShown() and other:GetFrameLevel() >= window:GetFrameLevel() then others = true; break end
        end
    end
    if not others and window:GetFrameLevel() >= FLOATING_LEVEL_BASE then return end
    if floatingTopLevel + FLOATING_LEVEL_STEP > FLOATING_LEVEL_CEILING then
        -- 段号用完：按现有上下次序把显示中的浮窗重新从底排起，次序不变。
        local order = {}
        for other in pairs(floatingWindows) do
            if other ~= window and other:IsShown() then order[#order + 1] = other end
        end
        table.sort(order, function(a, b) return a:GetFrameLevel() < b:GetFrameLevel() end)
        floatingTopLevel = FLOATING_LEVEL_BASE - FLOATING_LEVEL_STEP
        for _, other in ipairs(order) do
            floatingTopLevel = floatingTopLevel + FLOATING_LEVEL_STEP
            other:SetFrameLevel(floatingTopLevel)
        end
    end
    floatingTopLevel = floatingTopLevel + FLOATING_LEVEL_STEP
    window:SetFrameLevel(floatingTopLevel)
end
-- 在浮窗里任何地方按下（按钮、输入框、子面板也算）都把它提到最前：看按下时鼠标落在哪只浮窗里。
local floatingRaiser = CreateFrame("Frame")
floatingRaiser:RegisterEvent("GLOBAL_MOUSE_DOWN")
floatingRaiser:SetScript("OnEvent", function()
    local focus = GetMouseFoci()[1]
    while focus do
        if floatingWindows[focus] and focus._exFloatStrata and focus:IsShown() then RaiseFloatingWindow(focus); return end
        focus = focus:GetParent()
    end
end)

local function LayoutFloatingTitle(window, closable)
    local title, pad = window._exFloatTitle, window.contentPadding
    title:ClearAllPoints()
    title:SetPoint("LEFT", window._exFloatHeader, "LEFT", pad, 0)
    if closable then
        title:SetPoint("RIGHT", window._exFloatClose, "LEFT", -GM.space.descriptionGap, 0)
    else
        title:SetPoint("RIGHT", window._exFloatHeader, "RIGHT", -pad, 0)
    end
end

-- 内容区：标题行下面，左右下各留 window.contentPadding。
local function PlaceFloatingContent(window)
    local pad, content = window.contentPadding, window.content
    content:ClearAllPoints()
    content:SetPoint("TOPLEFT", window, "TOPLEFT", pad, -window._exFloatHeader:GetHeight())
    content:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -pad, pad)
end

-- 贴靠函数在下文定义，这里先声明，window.SetAnchor 才能取到同一个 local。
local SetFloatingWindowAnchor

-- 每个池化宿主只建一次：标题栏（拖动条）、标题文字、关闭按钮、内容区。
-- 这些子对象和下面的脚本都不捕获任何租约数据；租约数据只放在宿主字段里。
-- 拖动中（按下拖起到松手）：window._exFloatDragging = true，位置只归鼠标——SetAnchor 不生效、贴靠跟随停掉，
-- 调用方的重新贴靠 / 重排先看 window:IsDragging()。松手才把位置交回（onDragStop）。
local FloatingWindowDragStart, FloatingWindowDragStop
do
    -- 标题栏、背景框原生拖动的松手兜底：拖起的那个框中途被收走时收不到 OnDragStop，左键一松也照样结束。
    local function Watch(window)
        if not IsMouseButtonDown("LeftButton") then FloatingWindowDragStop(window) end
    end
    FloatingWindowDragStart = function(window)
        if window._exFloatDragging then return end
        -- 用户手动拖走：不再跟随贴靠目标，只留在拖到的位置。
        if window._exFloatAnchor then window:SetAnchor(nil) end
        -- 先按当前屏幕位置换成 TOPLEFT 贴 UIParent（只算一次），再开始移动。
        SettleDraggedFrame(window)
        window._exFloatDragging = true
        window:SetScript("OnUpdate", Watch)
        window:StartMoving()
    end
    FloatingWindowDragStop = function(window)
        if not window._exFloatDragging then return end
        window._exFloatDragging = nil
        window:SetScript("OnUpdate", nil)
        window:StopMovingOrSizing()
        -- dragAnywhere 窗口：拖完改成 TOPLEFT 贴 UIParent（之后改高顶边不动），告诉调用方位置。
        if not window._exFloatDragAnywhere then return end
        local x, y = SettleDraggedFrame(window)
        local callback = window._exFloatOnDragStop
        if callback and x then callback(window, x, y) end
    end
end
-- 空白处拖动（EXUI:SetDragAnywhere）走的两头：开始时取消贴靠、记拖动中，结束时同上告诉调用方。
local FLOATING_DRAG_ANYWHERE = {
    onDragStart = function(window)
        if window._exFloatAnchor then window:SetAnchor(nil) end
        window._exFloatDragging = true
    end,
    onDragStop = function(window, x, y)
        window._exFloatDragging = nil
        local callback = window._exFloatOnDragStop
        if callback and x then callback(window, x, y) end
    end,
}

-- 空白处也能拖：吃鼠标但没有任何鼠标手势的纯背景 Frame（卡片、分组底等）把拖动转给所在浮窗。
-- 按钮、输入框、滑条等交互控件及已有鼠标脚本的框保持原样；内容是动态建的，所以显示时和调用方要求时各扫一遍。
local function FloatingDragForwardStart(surface)
    local window = surface._exFloatDragWindow
    if not window or not window:IsShown() then return end
    -- 池化子框可能已被挪到别处：只有仍在这只窗口里才转发。
    local parent = surface:GetParent()
    while parent and parent ~= window do parent = parent:GetParent() end
    if parent == window then FloatingWindowDragStart(window) end
end
local function FloatingDragForwardStop(surface)
    local window = surface._exFloatDragWindow
    if window then FloatingWindowDragStop(window) end
end
local function BindFloatingDragSurface(window, surface)
    if surface._exFloatDragWindow == nil then
        if surface:GetScript("OnMouseDown") or surface:GetScript("OnMouseUp")
            or surface:GetScript("OnDragStart") or surface:GetScript("OnDragStop") then return false end
        surface:SetScript("OnDragStart", FloatingDragForwardStart)
        surface:SetScript("OnDragStop", FloatingDragForwardStop)
        surface:RegisterForDrag("LeftButton")
    elseif surface:GetScript("OnDragStart") ~= FloatingDragForwardStart then
        return false
    end
    surface._exFloatDragWindow = window
    return true
end
local function RefreshFloatingDragSurfaces(window)
    local function Visit(surface)
        local kind = surface:GetObjectType()
        if (kind ~= "Frame" and kind ~= "ScrollFrame") or surface._gridType then return end
        -- 空白处可拖的窗口：只开了滚轮的滚动框（内容区整块）也是背景，它挡在窗口上面，按下去拖不动窗口；
        -- 给它开鼠标、同样转发拖动（滚轮照旧）。
        if window._exFloatDragAnywhere and kind == "ScrollFrame" and not surface:IsMouseEnabled()
            and surface:IsMouseWheelEnabled() and BindFloatingDragSurface(window, surface) then
            surface:EnableMouse(true)
        end
        if surface:IsMouseEnabled() and not BindFloatingDragSurface(window, surface) then return end
        for _, child in ipairs({ surface:GetChildren() }) do Visit(child) end
    end
    for _, child in ipairs({ window.content:GetChildren() }) do Visit(child) end
end

local function BuildFloatingWindow(window)
    window:SetMovable(true)
    window:SetClampedToScreen(true)
    window:HookScript("OnMouseDown", RaiseFloatingWindow)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", FloatingWindowDragStart)
    window:SetScript("OnDragStop", FloatingWindowDragStop)
    -- 打开时和点击时一样提到最前：后打开的面板压住先开的面板和跟随元素的工具条。
    window:HookScript("OnShow", function(self)
        if self._exFloatStrata then RaiseFloatingWindow(self) end
        if not self._exFloatManualDragScan then
            C_Timer.After(0, function() if self:IsShown() then RefreshFloatingDragSurfaces(self) end end)
        end
    end)

    local header = CreateFrame("Frame", nil, window)
    header:SetPoint("TOPLEFT", window, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", window, "TOPRIGHT", 0, 0)
    header:SetHeight(GM.size.floatingHeaderHeight)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() FloatingWindowDragStart(window) end)
    header:SetScript("OnDragStop", function() FloatingWindowDragStop(window) end)
    header:HookScript("OnMouseDown", function() RaiseFloatingWindow(window) end)
    window._exFloatHeader = header

    local title = EXUI:CreateVisualFontString(header, EXFONTFRAME, "GameFontHighlight")
    title:SetJustifyH("LEFT")
    title:SetJustifyV("MIDDLE")
    title:SetWordWrap(false)
    MODERN.ApplyTextRole(title, "title", GC.text)
    window._exFloatTitle = title

    local close = CreateFrame("Button", nil, header)
    close:SetSize(GM.size.floatingCloseSize, GM.size.floatingCloseSize)
    close:SetPoint("RIGHT", header, "RIGHT", -(GM.size.floatingHeaderHeight - GM.size.floatingCloseSize) / 2, 0)
    close:RegisterForClicks("LeftButtonUp")
    local closeIcon = EXUI:CreateVisualTexture(close, EXBORDERFRAME)
    closeIcon:SetTexture(EXUI:GetIcon("x"))
    closeIcon:SetSize(GM.size.dialogCloseGlyphSize, GM.size.dialogCloseGlyphSize)
    closeIcon:SetPoint("CENTER")
    closeIcon:SetVertexColor(unpack(GC.textDim))
    close:SetScript("OnEnter", function() closeIcon:SetVertexColor(unpack(GC.text)) end)
    close:SetScript("OnLeave", function() closeIcon:SetVertexColor(unpack(GC.textDim)) end)
    close:SetScript("OnClick", function()
        local request = window._exFloatOnCloseRequested
        if request then request(window, "close-button")
        else window:Hide() end
    end)
    window._exFloatClose = close

    window.content = CreateFrame("Frame", nil, window)
    window.contentPadding = GM.space.cardBodyPadding
    PlaceFloatingContent(window)

    window.SetTitle = function(self, text) self._exFloatTitle:SetText(text or "") end
    window.Release = function(self) Factory:ReleaseCompositeHost(self) end
    window.SetAnchor = function(self, spec) SetFloatingWindowAnchor(self, spec) end
    -- 用户正按着拖这只窗口（标题栏或空白处）：调用方的贴靠、重新摆放要等松手。
    window.IsDragging = function(self) return self._exFloatDragging == true end
    -- 内容重建后由调用方调用，让新建的背景框也能拖窗口。
    window.RefreshDragSurfaces = RefreshFloatingDragSurfaces
end

-- 贴靠：全部换算成窗口自己的坐标单位，相对 UIParent 左下角摆放。
-- 先放目标右边（顶对齐），放不下换左边，再不行上方、下方（左对齐）；都放不下仍用右边。最后夹在屏幕内。
-- anchor.align = "center"：左右两侧时竖直中心线对齐目标中心，上下两侧时水平中心线对齐；anchor.margin = 离屏幕四边至少多少。
-- anchor.side = "below"：先放目标下方（下方放不下再按上面的顺序），用于贴在顶部按钮条下面的面板。
local function PlaceFloatingWindowBeside(window)
    local anchor = window._exFloatAnchor
    local target = anchor.frame
    local left, bottom, width, height = target:GetRect()
    if not left then return end
    local ws = window:GetEffectiveScale()
    local ratio = target:GetEffectiveScale() / ws
    local L, B = left * ratio, bottom * ratio
    local R, T = L + width * ratio, B + height * ratio
    local us = UIParent:GetEffectiveScale() / ws
    local sw, sh = UIParent:GetWidth() * us, UIParent:GetHeight() * us
    local ww, wh = window:GetWidth(), window:GetHeight()
    local gap = anchor.gap
    local centered = anchor.align == "center"
    local sideY = centered and ((T + B) / 2 - wh / 2) or (T - wh)
    local sideX = centered and ((L + R) / 2 - ww / 2) or L
    local margin = anchor.margin or 0
    local x, y
    if anchor.side == "below" and B - gap - wh >= 0 then
        x, y = sideX, B - gap - wh
    elseif R + gap + ww <= sw then
        x, y = R + gap, sideY
        -- anchor.trail：同组跟在本窗右边的浮窗（如二级）。整组右边放不下时整组往左移到刚好放得下，
        -- 本窗左边不越过目标左边；移了也放不下才不管（同组浮窗自己翻边）。
        local companion = anchor.trail and anchor.trail()
        if companion and companion:IsShown() then
            local cr = companion:GetEffectiveScale() / ws
            local cAnchor = companion._exFloatAnchor
            local over = x + ww + (companion:GetWidth() + (cAnchor and cAnchor.gap or 0)) * cr - (sw - margin)
            if over > 0 and x - over >= L then x = x - over end
        end
    elseif L - gap - ww >= 0 then
        x, y = L - gap - ww, sideY
    elseif T + gap + wh <= sh then
        x, y = sideX, T + gap
    elseif B - gap - wh >= 0 then
        x, y = sideX, B - gap - wh
    else
        x, y = R + gap, sideY
    end
    x = math.max(margin, math.min(x, sw - ww - margin))
    y = math.max(margin, math.min(y, sh - wh - margin))
    window:ClearAllPoints()
    window:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
end

local function FloatingWindowFollow(window)
    if window._exFloatAnchor then PlaceFloatingWindowBeside(window) end
end

-- window:SetAnchor(spec)：spec = { frame = 目标框, gap = 间距（可选，默认 GM.space.descriptionGap）,
-- follow = true 时每帧跟随目标移动, align = "top"（默认，顶对齐）| "center"（中心线对齐目标中心）,
-- margin = 离屏幕边至少多少（可选，默认 0）, trail = function() 返回同组跟在右边的浮窗或 nil（可选）,
-- side = "below"（可选：先放目标下方）}；传 nil 取消贴靠（窗口停在当前位置）。
-- 当前贴靠在 window._exFloatAnchor（同样的字段），窗口改了尺寸后可以 window:SetAnchor(window._exFloatAnchor) 重摆。
SetFloatingWindowAnchor = function(window, spec)
    -- 拖动中位置归鼠标：贴靠（含重摆、取消）一律不动它，松手后用户拖到哪就停哪。
    if window._exFloatDragging then return end
    if spec == nil then
        window._exFloatAnchor = nil
        window:SetScript("OnUpdate", nil)
        return
    end
    if type(spec) ~= "table" or type(spec.frame) ~= "table" or type(spec.frame.GetRect) ~= "function" then
        error("CreateFloatingWindow: anchor.frame must be a frame", 3)
    end
    if spec.gap ~= nil and type(spec.gap) ~= "number" then
        error("CreateFloatingWindow: anchor.gap must be a number", 3)
    end
    if spec.follow ~= nil and type(spec.follow) ~= "boolean" then
        error("CreateFloatingWindow: anchor.follow must be boolean", 3)
    end
    if spec.align ~= nil and spec.align ~= "top" and spec.align ~= "center" then
        error("CreateFloatingWindow: anchor.align must be top or center", 3)
    end
    if spec.margin ~= nil and (type(spec.margin) ~= "number" or spec.margin < 0) then
        error("CreateFloatingWindow: anchor.margin must be a non-negative number", 3)
    end
    if spec.trail ~= nil and type(spec.trail) ~= "function" then
        error("CreateFloatingWindow: anchor.trail must be a function", 3)
    end
    if spec.side ~= nil and spec.side ~= "below" then
        error("CreateFloatingWindow: anchor.side must be below", 3)
    end
    window._exFloatAnchor = { frame = spec.frame, gap = spec.gap or GM.space.descriptionGap, follow = spec.follow,
        align = spec.align, margin = spec.margin, trail = spec.trail, side = spec.side }
    window:SetScript("OnUpdate", spec.follow == true and FloatingWindowFollow or nil)
    PlaceFloatingWindowBeside(window)
end

local function FloatingWindowOnHide(window)
    if window._exFloatDragging then
        window._exFloatDragging = nil
        window:SetScript("OnUpdate", nil)
    end
    window:StopMovingOrSizing()
    local callback = window._exFloatOnHide
    if callback then callback(window) end
end

-- options（纯数据）:
--   width, height   必填，窗口外框尺寸
--   parent          可选，默认 UIParent
--   title           可选，标题栏文字；不填则标题栏只作拖动条
--   closable        true 时标题栏右侧显示 × 关闭按钮（点击 = window:Hide()）
--   strata          可选 "DIALOG"（默认）或 "FULLSCREEN_DIALOG"
--   padding         可选，内容区（和标题 / 页签）离窗口左右、内容离底边的内距，默认 GM.space.cardBodyPadding；
--                   实际值放在 window.contentPadding
--   dragAnywhere    可选 true：窗口里任何空白处（不是按钮、输入框等控件的地方）都能拖（EXUI:SetDragAnywhere）；
--                   拖完窗口改成 TOPLEFT 贴 UIParent 左下角，之后内容刷新、改高都不挪位置
--   manualDragScan  可选 true：显示时不自动扫可拖背景，由调用方在内容的框换了时自己调 window:RefreshDragSurfaces()
--                   （内容复用、框没变时重开窗口不用再扫一遍）
--   clampToScreen   可选 false：不夹在屏幕内（可以拖出屏幕）；不写照旧夹住
--   onDragStop(window, x, y) 可选，只在 dragAnywhere 时调：用户拖完（标题栏、空白处都算）后的位置，
--                   恢复用 window:ClearAllPoints(); window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
--   background      可选 "panel"：窗口底色与外框用设置主窗口那一套（GUIColors.panel / panelBorder）；不写照旧用对话框底
--   onHide(window)  可选；窗口因关闭按钮、Hide()、父级隐藏等原因隐藏时调用（Release 引发的隐藏不调用；
--   onCloseRequested(window, "close-button") 可选；×只请求关闭，owner先收尾再Hide/Release。
--                   可以在 onHide 里调 window:Release()）
--   anchor          可选 { frame, gap, follow }：贴在 frame 旁边（右→左→上→下，夹在屏幕内），follow=true 每帧跟随；
--                   之后可用 window:SetAnchor(spec) 换目标、SetAnchor(nil) 取消；用户拖动窗口会自动取消。
--                   不传时位置照旧为屏幕中心。
--   headerTabs      可选 { items, value, onChange, height, fontSize }：页签放在标题行（不再有单独的标题文字），
--                   × 在页签行最右；items / value / onChange 同 CreateTabGroup，height = 标题行高（默认 GM.size.tabHeight），
--                   fontSize = 页签字号（可选）。返回的 window.tabs 就是这个页签组（SetValue / GetValue 照常）。
-- 返回已隐藏的窗口：window.content 是内容区 Frame，window:SetTitle(text)，window:Release()，
-- window:RefreshDragSurfaces()（内容重建后让新背景框也能拖窗口；显示时自动扫一次），
-- window:IsDragging()（用户正按着拖：拖动中 SetAnchor 不生效，调用方自己摆位置前也要先看它）；位置默认屏幕中心，
-- 调用方自行 ClearAllPoints/SetPoint 与 Show()。不吞 Esc、不遮罩、不抢键盘。
function EXUI:CreateFloatingWindow(options)
    if type(options) ~= "table" then error("CreateFloatingWindow: options must be a table", 2) end
    if type(options.width) ~= "number" or options.width <= 0
        or type(options.height) ~= "number" or options.height <= 0 then
        error("CreateFloatingWindow: options.width and options.height must be positive numbers", 2)
    end
    if options.title ~= nil and type(options.title) ~= "string" then
        error("CreateFloatingWindow: options.title must be a string", 2)
    end
    if options.onHide ~= nil and type(options.onHide) ~= "function" then
        error("CreateFloatingWindow: options.onHide must be a function", 2)
    end
    if options.onCloseRequested ~= nil and type(options.onCloseRequested) ~= "function" then
        error("CreateFloatingWindow: options.onCloseRequested must be a function", 2)
    end
    local headerTabs = options.headerTabs
    if headerTabs ~= nil then
        if type(headerTabs) ~= "table" or type(headerTabs.items) ~= "table" then
            error("CreateFloatingWindow: options.headerTabs must be { items, value, onChange, height, fontSize }", 2)
        end
        for key in pairs(headerTabs) do
            if key ~= "items" and key ~= "value" and key ~= "onChange" and key ~= "height" and key ~= "fontSize" then
                error("CreateFloatingWindow: options.headerTabs unknown field " .. tostring(key), 2)
            end
        end
        if headerTabs.height ~= nil and (type(headerTabs.height) ~= "number" or headerTabs.height <= 0) then
            error("CreateFloatingWindow: options.headerTabs.height must be a positive number", 2)
        end
        if options.title ~= nil then error("CreateFloatingWindow: headerTabs replaces the title; omit options.title", 2) end
    end
    if options.dragAnywhere ~= nil and type(options.dragAnywhere) ~= "boolean" then
        error("CreateFloatingWindow: options.dragAnywhere must be boolean", 2)
    end
    if options.manualDragScan ~= nil and type(options.manualDragScan) ~= "boolean" then
        error("CreateFloatingWindow: options.manualDragScan must be boolean", 2)
    end
    if options.clampToScreen ~= nil and type(options.clampToScreen) ~= "boolean" then
        error("CreateFloatingWindow: options.clampToScreen must be boolean", 2)
    end
    if options.onDragStop ~= nil and type(options.onDragStop) ~= "function" then
        error("CreateFloatingWindow: options.onDragStop must be a function", 2)
    end
    if options.padding ~= nil and (type(options.padding) ~= "number" or options.padding < 0) then
        error("CreateFloatingWindow: options.padding must be a non-negative number", 2)
    end
    if options.background ~= nil and options.background ~= "panel" then
        error("CreateFloatingWindow: options.background must be panel or nil", 2)
    end
    local strata = options.strata == nil and "DIALOG" or options.strata
    if not FLOATING_STRATA[strata] then
        error("CreateFloatingWindow: options.strata must be DIALOG or FULLSCREEN_DIALOG", 2)
    end
    local window, isNew = Factory:AcquireCompositeHost(FLOATING_POOL, options.parent or UIParent)
    if isNew then BuildFloatingWindow(window) end
    window._exFloatStrata = strata
    window:SetSize(options.width, options.height)
    window:ClearAllPoints()
    window:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    window:EnableMouse(true)
    window._exFloatTitle:SetText(options.title or "")
    window._exFloatClose:SetShown(options.closable == true)
    window.contentPadding = options.padding or GM.space.cardBodyPadding
    window:SetClampedToScreen(options.clampToScreen ~= false)
    window._exFloatDragAnywhere = options.dragAnywhere == true
    window._exFloatOnDragStop = options.onDragStop
    window._exFloatManualDragScan = options.manualDragScan == true
    EXUI:SetDragAnywhere(window, options.dragAnywhere == true and FLOATING_DRAG_ANYWHERE or nil)
    LayoutFloatingTitle(window, options.closable == true)
    if headerTabs then
        -- 页签进标题行：标题行加高到页签高，页签占满标题行（× 左边为止），内容区跟着下移。
        local header, height = window._exFloatHeader, headerTabs.height or GM.size.tabHeight
        header:SetHeight(height)
        window._exFloatTitle:Hide()
        local tabs = EXUI:CreateTabGroup(header, { items = headerTabs.items, value = headerTabs.value, fit = true,
            onChange = headerTabs.onChange, itemHeight = height, fontSize = headerTabs.fontSize })
        tabs:ClearAllPoints()
        tabs:SetPoint("TOPLEFT", header, "TOPLEFT", window.contentPadding, 0)
        if options.closable == true then
            tabs:SetPoint("BOTTOMRIGHT", window._exFloatClose, "BOTTOMLEFT", -GM.space.descriptionGap, -(height - GM.size.floatingCloseSize) / 2)
        else
            tabs:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -window.contentPadding, 0)
        end
        tabs:Show()
        window.tabs = tabs
    end
    PlaceFloatingContent(window)
    EXUI:ApplyDialogStyle(window, window._exFloatTitle)
    if options.background == "panel" then
        -- 和 EXBoss / Tools 设置主窗口同一底色与外框（GUIColors.panel / panelBorder）。
        EXUI:SetControlSurface(window, GM.radius.dialog, GC.panel, GC.panelBorder)
    end
    RaiseFloatingWindow(window)
    window:Hide()
    window._exFloatOnHide = options.onHide
    window._exFloatOnCloseRequested = options.onCloseRequested
    window:SetScript("OnHide", FloatingWindowOnHide)
    if options.anchor ~= nil then SetFloatingWindowAnchor(window, options.anchor) end
    Factory:AttachPoolRelease(window, function(self)
        -- 先清回调再隐藏：归还引发的隐藏不再调用 onHide，
        -- 使用方在 onHide 里调 window:Release() 时同一窗口不会被归还两次。
        self._exFloatOnHide = nil
        self._exFloatOnCloseRequested = nil
        self._exFloatAnchor, self._exFloatDragging = nil, nil
        self._exFloatOnDragStop, self._exFloatDragAnywhere, self._exFloatManualDragScan = nil, nil, nil
        EXUI:SetDragAnywhere(self, nil)
        self:SetClampedToScreen(true)
        if self.tabs then
            -- 标题行页签：归还页签组，标题行与内容区回到默认高度。
            Factory:ReleaseCompositeHost(self.tabs)
            self.tabs = nil
            self._exFloatHeader:SetHeight(GM.size.floatingHeaderHeight)
            self._exFloatTitle:Show()
        end
        self.contentPadding = GM.space.cardBodyPadding
        PlaceFloatingContent(self)
        self:SetScript("OnUpdate", nil)
        self:StopMovingOrSizing()
        if self:IsShown() then self:Hide() end
        self:SetScript("OnHide", nil)
        self._exFloatStrata = nil
        -- 内容由调用方负责归还；没有归还的子对象脱离并隐藏，避免下一次借用时露出旧内容。
        local content = self.content
        for _, child in ipairs({ content:GetChildren() }) do
            child:Hide()
            child:ClearAllPoints()
            child:SetParent(nil)
        end
        for _, region in ipairs({ content:GetRegions() }) do region:Hide() end
    end)
    return window
end

-- ---------------------------------------------------------
-- 开关加下拉合一按钮
-- ---------------------------------------------------------
local TOGGLE_DROPDOWN_POOL = "EXUI.ToggleDropdownButton"
Factory:InitCompositePool(TOGGLE_DROPDOWN_POOL)

local function PaintToggleDropdown(button)
    local checked = button._exTdChecked
    local hasToggle = checked ~= nil
    local on = checked == true
    local enabled = button._exTdEnabled ~= false
    local toggleEnabled = hasToggle and enabled and button._exTdToggleEnabled == true
    local hover = enabled and ((button._exTdHoverLeft and (not hasToggle or toggleEnabled)) or button._exTdHoverRight)
    local pressed = enabled and button._exTdPressed == true
    -- 开启 = 主要按钮配色；关闭或没有开关 = 次要按钮配色；整体禁用 = 禁用配色。
    local state = not enabled and GS.button.disabled
        or (on and GS.primary or GS.button)[pressed and "pressed" or hover and "hover" or "normal"]
    EXUI:SetControlSurface(button, GM.radius.control, state.fill, state.border)
    button._exTdLabel:SetTextColor(unpack(state.text))
    button._exTdArrow:SetVertexColor(unpack((on or not enabled) and state.text or (hover and MC.white or MC.muted)))
    local divider = button._exTdDivider
    divider:SetShown(hasToggle)
    divider:SetColorTexture(unpack(state.border))
    local box, mark = button._exTdBox, button._exTdMark
    box:SetShown(hasToggle)
    if hasToggle then
        local fill, edge, markColor = MC.input, MC.checkboxBorder, MC.primaryFill
        if not toggleEnabled then
            fill, edge, markColor = MC.disabledFill, MC.disabledBorder, MC.disabledText
        elseif on then
            fill, edge = MC.white, MC.white
        end
        EXUI:SetControlSurface(box, GM.radius.thumb, fill, edge)
        mark:SetVertexColor(unpack(markColor))
        mark:SetShown(on)
    end
end

local function LayoutToggleDropdown(button)
    local hasToggle = button._exTdChecked ~= nil
    local left, right, label = button._exTdLeft, button._exTdRight, button._exTdLabel
    local divider = button._exTdDivider
    right:ClearAllPoints()
    left:ClearAllPoints()
    divider:ClearAllPoints()
    right:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    right:SetWidth(GM.size.toggleDropdownArrowWidth)
    left:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT", 0, 0)
    divider:SetPoint("TOPLEFT", right, "TOPLEFT", 0, -GM.radius.control)
    divider:SetPoint("BOTTOMLEFT", right, "BOTTOMLEFT", 0, GM.radius.control)
    divider:SetWidth(1)
    label:ClearAllPoints()
    if hasToggle then
        local box = button._exTdBox
        box:ClearAllPoints()
        box:SetPoint("LEFT", left, "LEFT", GM.space.buttonPaddingX, 0)
        label:SetPoint("LEFT", box, "RIGHT", GM.space.toggleDropdownGap, 0)
        label:SetPoint("RIGHT", left, "RIGHT", -GM.space.toggleDropdownGap, 0)
        label:SetJustifyH("LEFT")
    else
        label:SetPoint("LEFT", left, "LEFT", GM.space.toggleDropdownGap, 0)
        label:SetPoint("RIGHT", left, "RIGHT", -GM.space.toggleDropdownGap, 0)
        label:SetJustifyH("CENTER")
    end
end

-- 整体可用 × 开关可用 → 左右两半的可点状态。
local function ApplyToggleDropdownEnabled(button)
    local enabled = button._exTdEnabled ~= false
    button._exTdLeft:SetEnabled(enabled and (button._exTdChecked == nil or button._exTdToggleEnabled == true))
    button._exTdRight:SetEnabled(enabled)
end

local function ToggleDropdownOpen(button)
    local callback = button._exTdOnDropdown
    if callback then callback(button) end
end

local function BuildToggleDropdown(button)
    local right = CreateFrame("Button", nil, button)
    right:RegisterForClicks("LeftButtonUp")
    local left = CreateFrame("Button", nil, button)
    left:RegisterForClicks("LeftButtonUp")
    button._exTdLeft, button._exTdRight = left, right

    local box = CreateFrame("Frame", nil, left)
    box:SetSize(GM.size.toggleDropdownBoxSize, GM.size.toggleDropdownBoxSize)
    box:EnableMouse(false)
    local mark = box:CreateTexture(nil, "OVERLAY")
    mark:SetTexture(MODERN_MEDIA .. "GlyphCheck.tga", "CLAMP", "CLAMP", "LINEAR")
    mark:SetAllPoints(box)
    button._exTdBox, button._exTdMark = box, mark

    local label = EXUI:CreateVisualFontString(left, EXFONTFRAME)
    label:SetFontObject(MODERN.buttonFont)
    label:SetJustifyV("MIDDLE")
    label:SetWordWrap(false)
    button._exTdLabel = label

    local divider = right:CreateTexture(nil, "ARTWORK")
    button._exTdDivider = divider
    local arrow = right:CreateTexture(nil, "ARTWORK")
    arrow:SetTexture(MODERN_MEDIA .. "GlyphChevron.tga", "CLAMP", "CLAMP", "LINEAR")
    arrow:SetSize(16, 16)
    arrow:SetPoint("CENTER", right, "CENTER", 0, 0)
    button._exTdArrow = arrow

    local function Track(half, hoverKey)
        half:SetScript("OnEnter", function() button[hoverKey] = true; PaintToggleDropdown(button) end)
        half:SetScript("OnLeave", function()
            button[hoverKey] = false
            button._exTdPressed = false
            PaintToggleDropdown(button)
        end)
        half:SetScript("OnMouseDown", function(self, mouseButton)
            if mouseButton == "LeftButton" and self:IsEnabled() then
                button._exTdPressed = true
                PaintToggleDropdown(button)
            end
        end)
        half:SetScript("OnMouseUp", function()
            button._exTdPressed = false
            PaintToggleDropdown(button)
        end)
    end
    Track(left, "_exTdHoverLeft")
    Track(right, "_exTdHoverRight")

    right:SetScript("OnClick", function() ToggleDropdownOpen(button) end)
    left:SetScript("OnClick", function()
        local checked = button._exTdChecked
        if checked == nil then ToggleDropdownOpen(button); return end
        local nextChecked = not checked
        button._exTdChecked = nextChecked
        PaintToggleDropdown(button)
        local callback = button._exTdOnToggle
        if callback then callback(nextChecked, button) end
    end)

    function button:SetChecked(checked)
        if self._exTdChecked == nil then
            error("ToggleDropdownButton:SetChecked requires a toggle (options.checked was nil)", 2)
        end
        if type(checked) ~= "boolean" then error("ToggleDropdownButton:SetChecked expects a boolean", 2) end
        self._exTdChecked = checked
        PaintToggleDropdown(self)
    end
    function button:GetChecked() return self._exTdChecked end
    function button:SetLabel(text)
        self._exTdLabel:SetText(text or "")
    end
    function button:SetToggleEnabled(enabled)
        self._exTdToggleEnabled = enabled == true
        ApplyToggleDropdownEnabled(self)
        PaintToggleDropdown(self)
    end
    function button:SetEnabled(enabled)
        self._exTdEnabled = enabled == true
        if not self._exTdEnabled then self._exTdPressed = false end
        ApplyToggleDropdownEnabled(self)
        PaintToggleDropdown(self)
    end
    function button:Release() Factory:ReleaseCompositeHost(self) end
end

-- options（纯数据）:
--   text          按钮文字
--   checked       boolean：有开关（点左半切换，点右半展开）；nil：没有开关，整块按钮点哪里都展开
--   toggleEnabled 可选，默认 true；false 时开关半边不可点（展开仍可用）
--   onToggle(checked, button)  开关点击后调用（控件已切到新状态；业务拒绝时调用 button:SetChecked 改回）
--   onDropdown(button)         展开动作；弹窗内容与位置由调用方负责，锚点用 button 本身
-- 返回池化宿主：SetChecked(bool)（静默）、GetChecked()、SetLabel(text)、
-- SetToggleEnabled(bool)、SetEnabled(bool)（整体可用）、Release()。悬停提示挂在 _exTdLeft / _exTdRight。
function EXUI:CreateToggleDropdownButton(parent, width, height, options)
    options = options or {}
    if type(options) ~= "table" then error("CreateToggleDropdownButton: options must be a table", 2) end
    if type(width) ~= "number" or width <= 0 then error("CreateToggleDropdownButton: width must be a positive number", 2) end
    if options.checked ~= nil and type(options.checked) ~= "boolean" then
        error("CreateToggleDropdownButton: options.checked must be boolean or nil", 2)
    end
    if options.onToggle ~= nil and type(options.onToggle) ~= "function" then
        error("CreateToggleDropdownButton: options.onToggle must be a function", 2)
    end
    if options.onDropdown ~= nil and type(options.onDropdown) ~= "function" then
        error("CreateToggleDropdownButton: options.onDropdown must be a function", 2)
    end
    local button, isNew = Factory:AcquireCompositeHost(TOGGLE_DROPDOWN_POOL, parent)
    if isNew then BuildToggleDropdown(button) end
    button:SetSize(width, height or GM.size.controlHeight)
    button._exTdChecked = options.checked
    button._exTdToggleEnabled = options.toggleEnabled ~= false
    button._exTdEnabled = true
    button._exTdOnToggle, button._exTdOnDropdown = options.onToggle, options.onDropdown
    button._exTdHoverLeft, button._exTdHoverRight, button._exTdPressed = false, false, false
    ApplyToggleDropdownEnabled(button)
    button._exTdLabel:SetText(options.text or "")
    LayoutToggleDropdown(button)
    PaintToggleDropdown(button)
    Factory:AttachPoolRelease(button, function(self)
        self._exTdChecked, self._exTdToggleEnabled, self._exTdEnabled = nil, nil, nil
        self._exTdOnToggle, self._exTdOnDropdown = nil, nil
        self._exTdHoverLeft, self._exTdHoverRight, self._exTdPressed = nil, nil, nil
        self._exTdLabel:SetText("")
        self._exTdLeft:Enable()
        self._exTdRight:Enable()
    end)
    return button
end

-- ---------------------------------------------------------
-- 图标按钮（可选开关状态）
-- ---------------------------------------------------------
local ICON_BUTTON_POOL = "EXUI.IconButton"
Factory:InitCompositePool(ICON_BUTTON_POOL)
local ICON_BUTTON_APPEARANCE = { field = true, ghost = true, input = true, dark = true }
-- 能当开关（options.checked）的外观。
local ICON_BUTTON_CHECKABLE = { field = true, input = true, dark = true }

local function PaintIconButton(host)
    local enabled = host._exIbEnabled ~= false
    local hover = enabled and host._exIbHover == true
    local pressed = enabled and host._exIbPressed == true
    local appearance = host._exIbAppearance
    local fill, border, iconColor
    if appearance == "ghost" then
        -- 无底：只有图标，悬停与按下时提亮；写了 iconColor 时平常图标用它。
        iconColor = not enabled and MC.disabledText
            or ((hover or pressed) and MC.white or (host._exIbIconColor or MC.muted))
    elseif appearance == "input" then
        -- 输入框同款底和边：悬停、按下换输入框悬停边，按下或开启（checked）底换输入框悬停底；
        -- 图标默认正文色，开启时白色。
        local checked = host._exIbChecked == true
        fill = not enabled and GC.inputDisabled or ((pressed or checked) and GC.inputHover or GC.input)
        border = not enabled and GC.inputDisabledBorder or ((hover or pressed or checked) and GC.inputHoverBorder or GC.inputBorder)
        iconColor = not enabled and GC.textDisabled or (checked and GC.white or (host._exIbIconColor or GC.text))
    elseif appearance == "dark" then
        -- 黑色轨道：叠在彩色底上的黑 0.20 小钮，不画边；悬停、按下出白 0.35 边、图标变白；
        -- 开启（checked）白 0.24 底、白图标；停用整体淡到 35%。
        local checked = host._exIbChecked == true
        fill = not enabled and GC.iconDarkDisabledFill or (checked and GC.iconDarkChecked or GC.iconDarkFill)
        border = (enabled and (hover or pressed)) and GC.iconDarkHoverBorder or GC.transparent
        iconColor = not enabled and GC.iconDarkDisabledIcon
            or ((checked or hover or pressed) and GC.white or (host._exIbIconColor or GC.iconDarkIcon))
    else
        local state = not enabled and GS.button.disabled
            or (host._exIbChecked == true and GS.primary or GS.button)[pressed and "pressed" or hover and "hover" or "normal"]
        fill, border, iconColor = state.fill, state.border, state.text
        -- 浮层外观（EXUI:SetControlOverlayAppearance）：没开、可用时底与平常边换浮层色；开启、禁用照旧。
        if host._exOverlay and enabled and host._exIbChecked ~= true then
            fill = GC.floatControlFill
            if not hover and not pressed then border = GC.floatControlBorder end
        end
    end
    -- 悬停换色（hoverBorderColor / hoverIconColor）：可用且悬停或按下时，边、图标改用指定色；没写照外观规则。
    if hover or pressed then
        if host._exIbHoverBorder and border then border = host._exIbHoverBorder end
        if host._exIbHoverIcon then iconColor = host._exIbHoverIcon end
    end
    if appearance == "ghost" then EXUI:ClearControlSurface(host)
    else EXUI:SetControlSurface(host, GM.radius.control, fill, border) end
    host._exIbIcon:SetVertexColor(unpack(iconColor))
end

local function BuildIconButton(host)
    local hit = CreateFrame("Button", nil, host)
    hit:SetAllPoints(host)
    hit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local icon = EXUI:CreateVisualTexture(hit, EXBORDERFRAME)
    icon:SetPoint("CENTER", hit, "CENTER", 0, 0)
    host.button, host._exIbIcon = hit, icon
    host._exOverlayRefresh = PaintIconButton
    hit:SetScript("OnEnter", function(self)
        host._exIbHover = true; PaintIconButton(host)
        if host._exIbTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(host._exIbTooltip, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    hit:SetScript("OnLeave", function(self)
        host._exIbHover, host._exIbPressed = false, false
        PaintIconButton(host)
        if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
    end)
    hit:SetScript("OnMouseDown", function(self, mouseButton)
        -- 按下就收起悬停提示（同 V2 句子词、芯片）。
        if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
        if mouseButton == "LeftButton" and self:IsEnabled() then
            host._exIbPressed = true
            PaintIconButton(host)
        end
    end)
    hit:SetScript("OnMouseUp", function()
        host._exIbPressed = false
        PaintIconButton(host)
    end)
    hit:SetScript("OnClick", function(_, mouseButton)
        local checked = host._exIbChecked
        if checked == nil then
            local callback = host._exIbOnClick
            if callback then callback(host, mouseButton) end
            return
        end
        if mouseButton ~= "LeftButton" then return end
        host._exIbChecked = not checked
        PaintIconButton(host)
        local callback = host._exIbOnToggle
        if callback then callback(host._exIbChecked, host) end
    end)
    function host:SetChecked(checked)
        if self._exIbChecked == nil then error("IconButton:SetChecked requires options.checked", 2) end
        if type(checked) ~= "boolean" then error("IconButton:SetChecked expects a boolean", 2) end
        self._exIbChecked = checked
        PaintIconButton(self)
    end
    function host:GetChecked() return self._exIbChecked end
    function host:SetIcon(id)
        self._exIbIcon:SetTexture(EXUI:GetIcon(id))
    end
    -- 平常状态的图标颜色（ghost / input / dark 外观）；nil 回到外观默认色。
    function host:SetIconColor(color)
        if color ~= nil and type(color) ~= "table" then error("IconButton:SetIconColor expects a color table or nil", 2) end
        self._exIbIconColor = color
        PaintIconButton(self)
    end
    -- 悬停换色：悬停、按下时的边色与图标色（ghost 没有边，只换图标）；nil 回到外观默认。
    function host:SetHoverColors(borderColor, iconColor)
        if (borderColor ~= nil and type(borderColor) ~= "table") or (iconColor ~= nil and type(iconColor) ~= "table") then
            error("IconButton:SetHoverColors expects color tables or nil", 2)
        end
        self._exIbHoverBorder, self._exIbHoverIcon = borderColor, iconColor
        PaintIconButton(self)
    end
    -- 换外观（"field" / "ghost" / "input" / "dark"）；开关按钮不能换到 ghost。
    function host:SetAppearance(appearance)
        if not ICON_BUTTON_APPEARANCE[appearance] then error("IconButton:SetAppearance expects field, ghost, input or dark", 2) end
        if self._exIbChecked ~= nil and not ICON_BUTTON_CHECKABLE[appearance] then
            error("IconButton:SetAppearance: a checked button needs field, input or dark appearance", 2)
        end
        self._exIbAppearance = appearance
        PaintIconButton(self)
    end
    function host:SetEnabled(enabled)
        self._exIbEnabled = enabled == true
        if not self._exIbEnabled then self._exIbPressed = false end
        self.button:SetEnabled(self._exIbEnabled)
        PaintIconButton(self)
    end
    function host:Release() Factory:ReleaseCompositeHost(self) end
end

-- options（纯数据）:
--   icon        必填，GUIIcons 图标 ID
--   iconSize    可选，图标边长，默认 GM.size.iconGlyphSize
--   appearance  可选，"field"（默认：次要按钮底，开启时主色底）、"ghost"（无底，只有图标；不支持开关）、
--               "input"（输入框同款底和边，图标正文色；开启时输入框悬停底 + 白图标）、
--               "dark"（黑色轨道：黑 0.20 底无边，悬停白 0.35 边，开启白 0.24 底；叠在彩色底上用）
--   iconColor   可选，ghost / input / dark 平常状态的图标颜色（悬停、开启、停用照外观规则）；之后可 SetIconColor
--   hoverBorderColor / hoverIconColor  可选，可用时悬停、按下的边色 / 图标色（ghost 只换图标）；不写照外观规则；
--               之后可 SetHoverColors(border, icon)
--   checked     boolean：开关按钮（左键切换后调用 onToggle；field、input、dark 外观）；nil：普通按钮（点击调用 onClick）
--   onToggle(checked, button)   开关切换后调用（控件已切到新状态；业务拒绝时调用 SetChecked 改回）
--   onClick(button, mouseButton) 普通按钮点击
--   tooltip     可选，悬停提示文字（GameTooltip，按钮上方）；按下即收起
-- 返回池化宿主：SetChecked(bool)（静默）、GetChecked()、SetIcon(id)、SetIconColor(color)、SetHoverColors(border, icon)、
-- SetAppearance(name)、
-- SetEnabled(bool)、Release()；
-- 悬停提示挂在 button.button（实际接收鼠标的 Button）。
function EXUI:CreateIconButton(parent, width, height, options)
    if type(options) ~= "table" then error("CreateIconButton: options must be a table", 2) end
    if type(width) ~= "number" or width <= 0 or type(height) ~= "number" or height <= 0 then
        error("CreateIconButton: width and height must be positive numbers", 2)
    end
    if not ExwindTools.GUIIcons.ids[options.icon] then error("CreateIconButton: options.icon must be a registered icon id", 2) end
    local appearance = options.appearance or "field"
    if not ICON_BUTTON_APPEARANCE[appearance] then error("CreateIconButton: options.appearance must be field, ghost, input or dark", 2) end
    if options.checked ~= nil and (type(options.checked) ~= "boolean" or not ICON_BUTTON_CHECKABLE[appearance]) then
        error("CreateIconButton: options.checked must be boolean and requires field, input or dark appearance", 2)
    end
    for _, key in ipairs({ "iconColor", "hoverBorderColor", "hoverIconColor" }) do
        if options[key] ~= nil and type(options[key]) ~= "table" then
            error("CreateIconButton: options." .. key .. " must be a color table", 2)
        end
    end
    if options.iconSize ~= nil and (type(options.iconSize) ~= "number" or options.iconSize <= 0) then
        error("CreateIconButton: options.iconSize must be a positive number", 2)
    end
    if options.tooltip ~= nil and type(options.tooltip) ~= "string" then
        error("CreateIconButton: options.tooltip must be a string", 2)
    end
    for _, key in ipairs({ "onToggle", "onClick" }) do
        if options[key] ~= nil and type(options[key]) ~= "function" then
            error("CreateIconButton: options." .. key .. " must be a function", 2)
        end
    end
    local host, isNew = Factory:AcquireCompositeHost(ICON_BUTTON_POOL, parent)
    if isNew then BuildIconButton(host) end
    host:SetSize(width, height)
    host._exIbAppearance = appearance
    host._exIbIconColor = options.iconColor
    host._exIbHoverBorder, host._exIbHoverIcon = options.hoverBorderColor, options.hoverIconColor
    host._exIbChecked = options.checked
    host._exIbEnabled = true
    host._exIbOnToggle, host._exIbOnClick = options.onToggle, options.onClick
    host._exIbTooltip = options.tooltip
    host._exIbHover, host._exIbPressed = false, false
    local size = options.iconSize or GM.size.iconGlyphSize
    host._exIbIcon:SetSize(size, size)
    host._exIbIcon:SetTexture(EXUI:GetIcon(options.icon))
    host.button:Enable()
    PaintIconButton(host)
    Factory:AttachPoolRelease(host, function(self)
        self._exIbAppearance, self._exIbChecked, self._exIbEnabled = nil, nil, nil
        self._exIbIconColor, self._exIbHoverBorder, self._exIbHoverIcon = nil, nil, nil
        self._exIbOnToggle, self._exIbOnClick, self._exIbTooltip = nil, nil, nil
        if GameTooltip:GetOwner() == self.button then GameTooltip:Hide() end
        self._exIbHover, self._exIbPressed = nil, nil
        self._exIbIcon:SetTexture(nil)
        self.button:Enable()
        EXUI:ClearControlSurface(self)
    end)
    return host
end

-- ---------------------------------------------------------
-- 胶囊按钮组
-- 一条圆角胶囊（host 底 + 1px bDef 边）分成几段，每段图标 + 文字；段间 1px 竖线上下各缩一截。
-- 悬停白 0.07 底；按下（pressed）白 0.14 底 + 1px 白 0.55 内描边，它两边的竖线隐藏。
-- 选中（selected，几段里当前用的那一段）：底色和字色同分段控件选中（segmentSelected / segmentSelectedText），两边竖线隐藏。
-- 首尾段的底色跟着胶囊圆角裁（_exJoinedEdge = "first" / "last"），中间段是直角。
-- 段是胶囊宿主自己的子 Button，跟宿主一起进出对象池。
-- ---------------------------------------------------------
local BUTTON_STRIP_POOL = "EXUI.ButtonStrip"
Factory:InitCompositePool(BUTTON_STRIP_POOL)
local BUTTON_STRIP_TONES = { ok = true, danger = true }
local BUTTON_STRIP_FIELDS = { icon = true, text = true, tooltip = true, pressed = true, selected = true }

-- 一段的文字与图标颜色：ok 绿、danger 红；没有 tone 时按下白、平常正文色。
local function StripSegmentColor(item)
    if item.tone == "ok" then return GC.capsuleAddText end
    if item.tone == "danger" then return GC.capsuleDangerText end
    if item.selected then return GC.segmentSelectedText end
    return item.pressed and GC.white or GC.text
end

local function PaintStripSegment(segment)
    local strip, item = segment._exStripOwner, segment._exStripItem
    if not strip or not item then return end
    if item.pressed then
        MODERN.PaintControlSurface(segment, segment._exStripRadius, GC.capsulePressedFill, GC.capsulePressedBorder)
    elseif item.selected then
        MODERN.PaintControlSurface(segment, segment._exStripRadius, GC.segmentSelected, GC.transparent)
    elseif segment._exStripHover then
        MODERN.PaintControlSurface(segment, segment._exStripRadius, GC.capsuleHoverFill, GC.transparent)
    else
        EXUI:ClearControlSurface(segment)
    end
    local color = StripSegmentColor(item)
    segment._exStripText:SetTextColor(unpack(color))
    segment._exStripIcon:SetVertexColor(unpack(color))
    -- 拼接边规则下末段左缘的描边由前一段提供；末段按下时自己补这一条。
    segment._exStripSeam:SetShown(item.pressed == true and segment._exJoinedEdge == "last")
    -- 段间竖线挂在后一段的左缘：按下段左右两条都隐藏。
    local previous = strip._exStripSegments[segment._exStripIndex - 1]
    segment._exStripDivider:SetShown(previous ~= nil and not (item.pressed or item.selected)
        and not (previous._exStripItem.pressed or previous._exStripItem.selected))
end

local function ShowStripTooltip(segment)
    local item = segment._exStripItem
    if not item or not item.tooltip then return end
    local strip = segment._exStripOwner
    if strip and strip._exStripTooltipAnchor == "below" then
        -- 提示框水平居中贴在这一段正下方，不压住左右两段。
        GameTooltip:SetOwner(segment, "ANCHOR_NONE")
        GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint("TOP", segment, "BOTTOM", 0, -GM.size.capsuleTooltipGap)
    else
        GameTooltip:SetOwner(segment, "ANCHOR_BOTTOM")
    end
    GameTooltip:AddLine(item.tooltip, 1, 1, 1, true)
    GameTooltip:Show()
    if strip and strip._exStripTooltipAnchor == "below" then
        -- 提示比这一段宽时，居中会伸出胶囊（首尾段尤其明显）：伸出哪边就改为跟胶囊那一边对齐，
        -- 仍在这一段下方、离段下沿 capsuleTooltipGap。宽度换算到段的坐标再比。
        local ratio = GameTooltip:GetEffectiveScale() / segment:GetEffectiveScale()
        local half = GameTooltip:GetWidth() * ratio / 2
        local center = (segment:GetLeft() + segment:GetRight()) / 2
        local gap = -GM.size.capsuleTooltipGap
        if center - half < strip:GetLeft() then
            GameTooltip:ClearAllPoints()
            GameTooltip:SetPoint("TOPLEFT", segment, "BOTTOMLEFT", (strip:GetLeft() - segment:GetLeft()) / ratio, gap)
        elseif center + half > strip:GetRight() then
            GameTooltip:ClearAllPoints()
            GameTooltip:SetPoint("TOPRIGHT", segment, "BOTTOMRIGHT", (strip:GetRight() - segment:GetRight()) / ratio, gap)
        end
    end
end

local function CreateStripSegment(strip, index)
    local segment = CreateFrame("Button", nil, strip)
    segment:RegisterForClicks("LeftButtonUp")
    segment._exSurfaceLargeRadius = true -- 首尾段圆角跟胶囊一样，高分屏上超过 32 物理像素
    segment._exStripIndex = index
    segment._exStripIcon = EXUI:CreateVisualTexture(segment, EXBORDERFRAME)
    segment._exStripText = EXUI:CreateVisualFontString(segment, EXFONTFRAME, "GameFontHighlight")
    segment._exStripText:SetWordWrap(false)
    local divider = segment:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(unpack(GC.panelBorder))
    segment._exStripDivider = divider
    local seam = segment:CreateTexture(nil, "OVERLAY")
    seam:SetColorTexture(unpack(GC.capsulePressedBorder))
    seam:SetPoint("TOPLEFT", segment, "TOPLEFT", 0, 0)
    seam:SetPoint("BOTTOMLEFT", segment, "BOTTOMLEFT", 0, 0)
    seam:Hide()
    segment._exStripSeam = seam
    segment:SetScript("OnEnter", function(self)
        self._exStripHover = true
        PaintStripSegment(self)
        ShowStripTooltip(self)
        local owner, item = self._exStripOwner, self._exStripItem
        if owner and owner._exStripOnHover and item then owner._exStripOnHover(item.id, self, true, owner) end
    end)
    segment:SetScript("OnLeave", function(self)
        self._exStripHover = false
        PaintStripSegment(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        local owner, item = self._exStripOwner, self._exStripItem
        if owner and owner._exStripOnHover and item then owner._exStripOnHover(item.id, self, false, owner) end
    end)
    -- 选项 hideTooltipOnPress：按下就收起悬停提示（点了会开面板，提示不能还盖着）。
    segment:SetScript("OnMouseDown", function(self)
        local owner = self._exStripOwner
        if owner and owner._exStripHideTipOnPress and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    segment:SetScript("OnClick", function(self)
        local owner, item = self._exStripOwner, self._exStripItem
        local callback = owner and owner._exStripOnClick
        if callback and item then callback(item.id, self, owner) end
    end)
    return segment
end

-- 按每段内容排宽：段内左右内距 14，首段左、尾段右 18；图标与文字间距、最小段宽都在 GM.size。
-- 段在胶囊边框里面（上下左右各让 1 物理像素），宽按物理像素取整，竖线落在整像素上。
local function LayoutButtonStrip(strip)
    local size = GM.size
    local pixel = MODERN.surfaceAtlas:GetPixel(strip)
    local items, segments = strip._exStripItems, strip._exStripSegments
    local count = #items
    local innerHeight = size.capsuleHeight - pixel * 2
    local x = pixel
    for index, item in ipairs(items) do
        local segment = segments[index]
        if not segment then
            segment = CreateStripSegment(strip, index)
            segments[index] = segment
        end
        segment._exStripOwner, segment._exStripItem = strip, item
        local iconSize = item.emphasize and size.capsuleAddIconSize or size.capsuleIconSize
        local text, icon = segment._exStripText, segment._exStripIcon
        MODERN.Font(text, item.emphasize and size.capsuleAddFont or size.capsuleFont,
            StripSegmentColor(item), "", "GameFontHighlight")
        text:SetText(item.text or "")
        local textWidth = item.text and math.ceil(text:GetUnboundedStringWidth()) or 0
        local iconWidth = item.icon and iconSize or 0
        local gap = (iconWidth > 0 and textWidth > 0) and size.capsuleIconTextGap or 0
        local content = iconWidth + gap + textWidth
        local padLeft = index == 1 and size.capsuleEdgePadX or size.capsuleSegmentPadX
        local padRight = index == count and size.capsuleEdgePadX or size.capsuleSegmentPadX
        local width = math.max(size.capsuleSegmentMinWidth, padLeft + content + padRight)
        width = math.ceil(width / pixel - 0.001) * pixel
        segment:ClearAllPoints()
        segment:SetPoint("TOPLEFT", strip, "TOPLEFT", x, -pixel)
        segment:SetSize(width, innerHeight)
        local startX = padLeft + math.floor((width - padLeft - padRight - content) / 2 + .5)
        icon:ClearAllPoints()
        icon:SetSize(iconSize, iconSize)
        icon:SetTexture(item.icon and EXUI:GetIcon(item.icon) or nil)
        icon:SetShown(item.icon ~= nil)
        icon:SetPoint("LEFT", segment, "LEFT", startX, 0)
        text:ClearAllPoints()
        text:SetPoint("LEFT", segment, "LEFT", startX + iconWidth + gap, 0)
        text:SetShown(textWidth > 0)
        local divider = segment._exStripDivider
        divider:ClearAllPoints()
        divider:SetPoint("TOPLEFT", segment, "TOPLEFT", 0, -(size.capsuleDividerInset - pixel))
        divider:SetPoint("BOTTOMLEFT", segment, "BOTTOMLEFT", 0, size.capsuleDividerInset - pixel)
        divider:SetWidth(pixel)
        segment._exStripSeam:SetWidth(pixel)
        -- 首尾段跟着胶囊圆角，中间段直角；只有一段时两头都圆。半径写整数 capsuleRadius（比段高一半略大），
        -- 由 GetMetrics 截到段高一半，画出来就是整半圆；固定值也让表面缓存只有一套，不随缩放新建。
        segment._exJoinedEdge = count > 1 and (index == 1 and "first" or (index == count and "last" or nil)) or nil
        segment._exStripRadius = (index == 1 or index == count) and size.capsuleRadius or 0
        segment:Show()
        x = x + width
    end
    for index = count + 1, #segments do
        local segment = segments[index]
        segment._exStripOwner, segment._exStripItem, segment._exStripHover = nil, nil, nil
        EXUI:ClearControlSurface(segment)
        segment:Hide()
    end
    strip:SetSize(x + pixel, size.capsuleHeight)
    EXUI:SetControlSurface(strip, size.capsuleRadius, GC.panel, GC.panelBorder)
    for index = 1, count do PaintStripSegment(segments[index]) end
end

local function CopyStripItem(item, index, seen)
    local where = "CreateButtonStrip: items[" .. index .. "]"
    if type(item) ~= "table" then error(where .. " must be a table", 3) end
    if type(item.id) ~= "string" and type(item.id) ~= "number" then error(where .. ".id must be a string or number", 3) end
    if seen[item.id] then error("CreateButtonStrip: duplicate item id " .. tostring(item.id), 3) end
    seen[item.id] = true
    if item.icon ~= nil and not ExwindTools.GUIIcons.ids[item.icon] then error(where .. ".icon must be a registered icon id", 3) end
    if item.text ~= nil and type(item.text) ~= "string" then error(where .. ".text must be a string", 3) end
    if item.icon == nil and (item.text == nil or item.text == "") then error(where .. " needs an icon or text", 3) end
    if item.tone ~= nil and not BUTTON_STRIP_TONES[item.tone] then error(where .. ".tone must be ok or danger", 3) end
    if item.tooltip ~= nil and type(item.tooltip) ~= "string" then error(where .. ".tooltip must be a string", 3) end
    if item.emphasize ~= nil and type(item.emphasize) ~= "boolean" then error(where .. ".emphasize must be a boolean", 3) end
    if item.pressed ~= nil and type(item.pressed) ~= "boolean" then error(where .. ".pressed must be a boolean", 3) end
    if item.selected ~= nil and type(item.selected) ~= "boolean" then error(where .. ".selected must be a boolean", 3) end
    return { id = item.id, icon = item.icon, text = item.text, tone = item.tone, tooltip = item.tooltip,
        emphasize = item.emphasize == true, pressed = item.pressed == true, selected = item.selected == true }
end

-- 用着的胶囊（弱表）：UI 缩放、窗口尺寸变化后按新的物理像素重排段宽和竖线。
local buttonStripFrames = setmetatable({}, { __mode = "k" })
local buttonStripScaleWatcher

local function WatchButtonStripScale(strip)
    buttonStripFrames[strip] = true
    if buttonStripScaleWatcher then return end
    buttonStripScaleWatcher = CreateFrame("Frame")
    buttonStripScaleWatcher:RegisterEvent("UI_SCALE_CHANGED")
    buttonStripScaleWatcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
    buttonStripScaleWatcher:SetScript("OnEvent", function()
        for owner in pairs(buttonStripFrames) do
            if owner._exStripItems then LayoutButtonStrip(owner) end
        end
    end)
end

local function BuildButtonStrip(strip)
    strip._exStripSegments = {}
    strip._exSurfaceLargeRadius = true -- 胶囊圆角 21：高分屏上超过 32 物理像素，走大半径图集
    WatchButtonStripScale(strip)
    -- 改一段的图标、文字、提示或按下状态；宽度跟着内容重排，胶囊总宽随之变化。
    function strip:SetItem(id, fields)
        if type(fields) ~= "table" then error("ButtonStrip:SetItem expects a table", 2) end
        local item, segment
        for index, current in ipairs(self._exStripItems or {}) do
            if current.id == id then item, segment = current, self._exStripSegments[index] end
        end
        if not item then error("ButtonStrip:SetItem unknown id " .. tostring(id), 2) end
        for key in pairs(fields) do
            if not BUTTON_STRIP_FIELDS[key] then error("ButtonStrip:SetItem unknown field " .. tostring(key), 2) end
        end
        if fields.icon ~= nil and not ExwindTools.GUIIcons.ids[fields.icon] then
            error("ButtonStrip:SetItem icon must be a registered icon id", 2)
        end
        if fields.text ~= nil and type(fields.text) ~= "string" then error("ButtonStrip:SetItem text must be a string", 2) end
        if fields.tooltip ~= nil and type(fields.tooltip) ~= "string" then error("ButtonStrip:SetItem tooltip must be a string", 2) end
        if fields.pressed ~= nil and type(fields.pressed) ~= "boolean" then error("ButtonStrip:SetItem pressed must be a boolean", 2) end
        if fields.selected ~= nil and type(fields.selected) ~= "boolean" then error("ButtonStrip:SetItem selected must be a boolean", 2) end
        if fields.icon ~= nil then item.icon = fields.icon end
        if fields.text ~= nil then item.text = fields.text end
        if fields.tooltip ~= nil then item.tooltip = fields.tooltip end
        if fields.pressed ~= nil then item.pressed = fields.pressed end
        if fields.selected ~= nil then item.selected = fields.selected end
        LayoutButtonStrip(self)
        if GameTooltip:IsOwned(segment) then ShowStripTooltip(segment) end
    end
    -- 某一段的 Frame（给菜单、弹窗当锚点）。
    function strip:GetItemFrame(id)
        for index, item in ipairs(self._exStripItems or {}) do
            if item.id == id then return self._exStripSegments[index] end
        end
    end
    function strip:Release() Factory:ReleaseCompositeHost(self) end
end

-- options（纯数据 + 回调）:
--   items = { { id, icon?, text?, tone? = "ok" | "danger", tooltip?, emphasize?, pressed?, selected? }, ... }（至少一项）
--     icon 是 GUIIcons ID；icon 与 text 至少一个。tone = "ok" 图标和文字染绿（capsuleAddText），
--     "danger" 染红（capsuleDangerText），段底不变色。emphasize = true：字 capsuleAddFont、图标 capsuleAddIconSize。
--     pressed = true：按下状态（白 0.14 底 + 白 0.55 内描边、白字，两边竖线隐藏）。
--     selected = true：选中（几段里当前用的那一段）：同分段控件选中的底色和字色，两边竖线隐藏。
--   onClick(id, segmentFrame, strip)   点某一段；segmentFrame 可当菜单锚点
--   onHover(id, segmentFrame, entering, strip)  可选：鼠标进 / 出某一段时调用（entering = true 进、false 出），
--                            给调用方在段旁边画自己的悬停预览；不写时照旧只有 tooltip。
--   tooltipAnchor = "below"  可选：悬停提示水平居中放在该段正下方（间距 GM.size.capsuleTooltipGap）；
--                            不写时照旧 GameTooltip 的 ANCHOR_BOTTOM。
--   hideTooltipOnPress = true  可选：在某一段上按下鼠标就收起它的悬停提示（移开再移回才重新显示）；不写时照旧。
-- 返回池化宿主（自己按内容定宽，高 GM.size.capsuleHeight）：SetItem(id, { icon?, text?, tooltip?, pressed?, selected? })、
-- GetItemFrame(id)、Release()。悬停有 tooltip 的段显示 GameTooltip。
function EXUI:CreateButtonStrip(parent, options)
    if type(options) ~= "table" then error("CreateButtonStrip: options must be a table", 2) end
    if type(options.items) ~= "table" or #options.items == 0 then error("CreateButtonStrip: options.items must be a non-empty array", 2) end
    if options.onClick ~= nil and type(options.onClick) ~= "function" then
        error("CreateButtonStrip: options.onClick must be a function", 2)
    end
    if options.onHover ~= nil and type(options.onHover) ~= "function" then
        error("CreateButtonStrip: options.onHover must be a function", 2)
    end
    if options.tooltipAnchor ~= nil and options.tooltipAnchor ~= "below" then
        error("CreateButtonStrip: options.tooltipAnchor must be \"below\"", 2)
    end
    if options.hideTooltipOnPress ~= nil and options.hideTooltipOnPress ~= true then
        error("CreateButtonStrip: options.hideTooltipOnPress must be true or nil", 2)
    end
    local items, seen = {}, {}
    for index, item in ipairs(options.items) do items[index] = CopyStripItem(item, index, seen) end
    local strip, isNew = Factory:AcquireCompositeHost(BUTTON_STRIP_POOL, parent)
    if isNew then BuildButtonStrip(strip) end
    strip._exStripItems = items
    strip._exStripOnClick = options.onClick
    strip._exStripOnHover = options.onHover
    strip._exStripTooltipAnchor = options.tooltipAnchor
    strip._exStripHideTipOnPress = options.hideTooltipOnPress
    for _, segment in ipairs(strip._exStripSegments) do segment._exStripHover = false end
    LayoutButtonStrip(strip)
    -- 自定义字体首帧可能还没载入，量出来的字宽偏小；下一帧同一租约再排一次。
    C_Timer.After(0, function()
        if strip._exStripItems == items then LayoutButtonStrip(strip) end
    end)
    Factory:AttachPoolRelease(strip, function(self)
        for _, segment in ipairs(self._exStripSegments) do
            if GameTooltip:IsOwned(segment) then GameTooltip:Hide() end
            segment._exStripOwner, segment._exStripItem, segment._exStripHover = nil, nil, nil
            segment._exJoinedEdge = nil
            segment._exStripSeam:Hide()
            EXUI:ClearControlSurface(segment)
            segment:Hide()
        end
        self._exStripItems, self._exStripOnClick, self._exStripTooltipAnchor = nil, nil, nil
        self._exStripOnHover = nil
        self._exStripHideTipOnPress = nil
        EXUI:ClearControlSurface(self)
    end)
    return strip
end

-- ---------------------------------------------------------
-- 群组方向缩略图与方向选择
-- ---------------------------------------------------------
local FLOW_VECTOR = { RIGHT = { 1, 0 }, LEFT = { -1, 0 }, UP = { 0, 1 }, DOWN = { 0, -1 } }
-- 主方向 × 换行方向，共 8 种；顺序就是选择格的排列顺序（4 列 × 2 行）。
local FLOW_PRESETS = { { "RIGHT", "DOWN" }, { "RIGHT", "UP" }, { "LEFT", "DOWN" }, { "LEFT", "UP" },
    { "DOWN", "RIGHT" }, { "DOWN", "LEFT" }, { "UP", "RIGHT" }, { "UP", "LEFT" } }
local FLOW_CELLS = 6
local FLOW_LINE_SIZE = 3

local FLOW_THUMB_POOL = "EXUI.FlowDirectionThumb"
Factory:InitCompositePool(FLOW_THUMB_POOL)

local function BuildFlowThumb(thumb)
    thumb._exFlowCells = {}
    for index = 1, FLOW_CELLS do
        local square = EXUI:CreateVisualTexture(thumb, EXBASEFRAME)
        square:SetTexture("Interface\\Buttons\\WHITE8X8")
        local number = EXUI:CreateVisualFontString(thumb, EXFONTFRAME, "GameFontHighlightSmall")
        number:SetJustifyH("CENTER")
        number:SetJustifyV("MIDDLE")
        MODERN.ApplyTextRole(number, "hint", GC.white)
        number:SetText(tostring(index))
        thumb._exFlowCells[index] = { square = square, number = number }
    end
    function thumb:SetFlow(direction, wrap, selected)
        local main, cross = FLOW_VECTOR[direction], FLOW_VECTOR[wrap]
        if not main or not cross then
            error("FlowDirectionThumb:SetFlow expects direction/wrap of RIGHT, LEFT, UP or DOWN", 2)
        end
        local width, height = self:GetWidth(), self:GetHeight()
        -- 最多三行三列小方块，四周留 flowCellInset，竖排的三行不贴格边。
        local inset, cellGap = GM.space.flowCellInset, GM.space.flowCellGap
        local size = math.max(1, math.floor(math.min((width - inset * 2 - cellGap * 2) / 3,
            (height - inset * 2 - cellGap * 2) / 3)))
        local step = size + cellGap
        local firstColor = self._exFlowFirstColor or GC.accent
        for index, cell in ipairs(self._exFlowCells) do
            local line, position = math.floor((index - 1) / FLOW_LINE_SIZE), (index - 1) % FLOW_LINE_SIZE
            -- 第 1 个在主方向的反侧、第 1 行在换行方向的反侧，所以序号沿主方向增长、第 2 行落在换行一侧。
            local x = (position - 1) * main[1] * step + (line - 0.5) * cross[1] * step
            local y = (position - 1) * main[2] * step + (line - 0.5) * cross[2] * step
            cell.square:ClearAllPoints()
            cell.square:SetPoint("CENTER", self, "CENTER", x, y)
            cell.square:SetSize(size, size)
            cell.square:SetVertexColor(unpack(index == 1 and firstColor
                or (selected and GC.primaryFill or GC.sliderTrack)))
            cell.number:ClearAllPoints()
            cell.number:SetPoint("CENTER", cell.square, "CENTER", 0, 0)
            cell.number:SetTextColor(unpack(index == 1 and GC.page or GC.white))
        end
    end
    function thumb:Release() Factory:ReleaseCompositeHost(self) end
end

-- options（可选）: firstColor = {r,g,b,a} 第 1 个方块的颜色（业务色，默认 GC.accent）。
-- 返回池化宿主：SetFlow(direction, wrap, selected)、Release()。direction/wrap 取 "RIGHT"/"LEFT"/"UP"/"DOWN"。
function EXUI:CreateFlowDirectionThumb(parent, width, height, options)
    options = options or {}
    if type(options) ~= "table" then error("CreateFlowDirectionThumb: options must be a table", 2) end
    if type(width) ~= "number" or width <= 0 or type(height) ~= "number" or height <= 0 then
        error("CreateFlowDirectionThumb: width and height must be positive numbers", 2)
    end
    if options.firstColor ~= nil and type(options.firstColor) ~= "table" then
        error("CreateFlowDirectionThumb: options.firstColor must be a color table", 2)
    end
    local thumb, isNew = Factory:AcquireCompositeHost(FLOW_THUMB_POOL, parent)
    if isNew then BuildFlowThumb(thumb) end
    thumb:SetSize(width, height)
    thumb._exFlowFirstColor = options.firstColor
    Factory:AttachPoolRelease(thumb, function(self) self._exFlowFirstColor = nil end)
    return thumb
end

local FLOW_PICKER_POOL = "EXUI.FlowDirectionPicker"
Factory:InitCompositePool(FLOW_PICKER_POOL)

local function PaintFlowChoice(choice)
    local picker = choice._exFlowPicker
    local preset = FLOW_PRESETS[choice._exFlowIndex]
    local selected = picker._exFlowDirection == preset[1] and picker._exFlowWrap == preset[2]
    if selected then
        EXUI:SetControlSurface(choice, GM.radius.control, GC.optionRowSelected, GC.optionRowSelectedBorder)
    else
        EXUI:SetControlSurface(choice, GM.radius.control, GC.optionRow,
            choice._exFlowHover and GC.optionRowHoverBorder or GC.optionRowBorder)
    end
    if choice._exFlowThumb then choice._exFlowThumb:SetFlow(preset[1], preset[2], selected) end
end

local function RefreshFlowPicker(picker)
    for _, choice in ipairs(picker._exFlowChoices) do PaintFlowChoice(choice) end
end

local function BuildFlowPicker(picker)
    picker._exFlowChoices = {}
    for index = 1, #FLOW_PRESETS do
        local choice = CreateFrame("Button", nil, picker, "BackdropTemplate")
        choice:RegisterForClicks("LeftButtonUp")
        choice._exFlowPicker, choice._exFlowIndex = picker, index
        choice:SetScript("OnEnter", function(self) self._exFlowHover = true; PaintFlowChoice(self) end)
        choice:SetScript("OnLeave", function(self) self._exFlowHover = false; PaintFlowChoice(self) end)
        choice:SetScript("OnClick", function(self)
            local preset = FLOW_PRESETS[self._exFlowIndex]
            picker._exFlowDirection, picker._exFlowWrap = preset[1], preset[2]
            RefreshFlowPicker(picker)
            local callback = picker._exFlowOnChange
            if callback then callback(preset[1], preset[2], picker) end
        end)
        picker._exFlowChoices[index] = choice
    end
    function picker:SetFlow(direction, wrap)
        if (direction ~= nil and not FLOW_VECTOR[direction]) or (wrap ~= nil and not FLOW_VECTOR[wrap]) then
            error("FlowDirectionPicker:SetFlow expects direction/wrap of RIGHT, LEFT, UP or DOWN", 2)
        end
        self._exFlowDirection, self._exFlowWrap = direction, wrap
        RefreshFlowPicker(self)
    end
    function picker:GetFlow() return self._exFlowDirection, self._exFlowWrap end
    function picker:Release() Factory:ReleaseCompositeHost(self) end
end

-- options（纯数据）:
--   direction, wrap  当前选中的主方向与换行方向（"RIGHT"/"LEFT"/"UP"/"DOWN"）；都不填 = 无选中
--   firstColor       可选，缩略图第 1 个方块的颜色（业务色，默认 GC.accent）
--   onChange(direction, wrap, picker)  用户点选后调用（控件已切到新选择）
--   stretch          可选，true = 选择格随宿主宽变宽（4 列平分整宽，不窄于默认格宽）；改宽后调 Relayout()
-- 返回池化宿主（4 列 × 2 行共 8 个缩略图选择格）：SetFlow(direction, wrap)（静默）、GetFlow()、Relayout()、Release()。
function EXUI:CreateFlowDirectionPicker(parent, options)
    options = options or {}
    if type(options) ~= "table" then error("CreateFlowDirectionPicker: options must be a table", 2) end
    if (options.direction ~= nil and not FLOW_VECTOR[options.direction])
        or (options.wrap ~= nil and not FLOW_VECTOR[options.wrap]) then
        error("CreateFlowDirectionPicker: options.direction/wrap must be RIGHT, LEFT, UP or DOWN", 2)
    end
    if options.onChange ~= nil and type(options.onChange) ~= "function" then
        error("CreateFlowDirectionPicker: options.onChange must be a function", 2)
    end
    if options.stretch ~= nil and options.stretch ~= true then
        error("CreateFlowDirectionPicker: options.stretch must be true or nil", 2)
    end
    local picker, isNew = Factory:AcquireCompositeHost(FLOW_PICKER_POOL, parent)
    if isNew then BuildFlowPicker(picker) end
    local cellWidth, cellHeight, gap = GM.size.flowThumbWidth, GM.size.flowThumbHeight, GM.space.flowThumbGap
    picker._exFlowDirection, picker._exFlowWrap = options.direction, options.wrap
    picker._exFlowOnChange = options.onChange
    picker._exFlowStretch = options.stretch
    picker:SetSize(4 * cellWidth + 3 * gap, 2 * cellHeight + gap)
    for _, choice in ipairs(picker._exFlowChoices) do
        choice._exFlowHover = false
        local thumb = EXUI:CreateFlowDirectionThumb(choice, cellWidth, cellHeight, { firstColor = options.firstColor })
        thumb:ClearAllPoints()
        thumb:SetPoint("CENTER", choice, "CENTER", 0, 0)
        thumb:SetFrameLevel(choice:GetFrameLevel() + 1)
        choice._exFlowThumb = thumb
    end
    -- 摆选择格：stretch 时 4 列平分当前宽（不窄于默认格宽），否则用默认格宽。
    function picker:Relayout()
        local width = cellWidth
        if self._exFlowStretch then width = math.max(cellWidth, (self:GetWidth() - 3 * gap) / 4) end
        for index, choice in ipairs(self._exFlowChoices) do
            choice:SetSize(width, cellHeight)
            choice:ClearAllPoints()
            choice:SetPoint("TOPLEFT", self, "TOPLEFT",
                ((index - 1) % 4) * (width + gap), -math.floor((index - 1) / 4) * (cellHeight + gap))
            if choice._exFlowThumb then choice._exFlowThumb:SetSize(width, cellHeight) end
        end
        RefreshFlowPicker(self)
    end
    picker:Relayout()
    Factory:AttachPoolRelease(picker, function(self)
        for _, choice in ipairs(self._exFlowChoices) do
            if choice._exFlowThumb then choice._exFlowThumb:Release() end
            choice._exFlowThumb, choice._exFlowHover = nil, nil
        end
        self._exFlowDirection, self._exFlowWrap, self._exFlowOnChange, self._exFlowStretch = nil, nil, nil, nil
    end)
    return picker
end

-- ---------------------------------------------------------
-- 每行个数选择
-- ---------------------------------------------------------
local PER_LINE_POOL = "EXUI.PerLineSelector"
Factory:InitCompositePool(PER_LINE_POOL)

local function RefreshPerLine(selector)
    local value = selector._exPerLineValue
    -- single：单选，只亮选中的那一个；否则 1..value 全亮（表示“到第几个换行”）。
    local single = selector._exPerLineSingle
    for index, square in ipairs(selector._exPerLineSquares) do
        local lit = value ~= nil and (single and index == value or (not single and index <= value))
        square._exButtonVariant = lit and "primary" or "secondary"
        Internal.PaintModernButton(square)
    end
    local none = selector._exPerLineNone
    if none then
        none._exButtonVariant = value == nil and "primary" or "secondary"
        Internal.PaintModernButton(none)
    end
    if selector._exPerLineInput then selector._exPerLineInput:SetNumber(value) end
end

local function CommitPerLine(selector, value)
    selector._exPerLineValue = value
    RefreshPerLine(selector)
    local callback = selector._exPerLineOnChange
    if callback then callback(value, selector) end
end

local function ReleasePooledChild(child)
    Factory:Release(child._fromPool, child)
end

-- options（纯数据）:
--   max          可选，方块个数，默认 10（1..max 的整数方块）
--   value        当前每行个数（正整数）；nil = 没有个数（不换行）
--   inputLabel   可选，数字输入框左侧的说明文字；不填则不显示
--   validation   可选，"clamp"（默认）或"reject"；透传数字输入的原始值校验策略
--   noneText     可选，“清除个数”按钮的文字；不填则不显示该按钮（点击 = onChange(nil)）
--   onChange(value, selector)  用户点方块、输入数字、点清除按钮后调用（value 为正整数或 nil）
--   single       可选，true = 只用一种控件：max 不超过 10 只给一排方块（随宿主宽收窄，最窄 perLineMinSquare，
--                改宽后调 Relayout()；_exMinWidth = 能收窄到的宽），超过 10 只给数字框；不显示 inputLabel / noneText
-- 返回池化宿主：SetValue(value)（静默）、GetValue()、Relayout()、Release()。
function EXUI:CreatePerLineSelector(parent, options)
    options = options or {}
    if type(options) ~= "table" then error("CreatePerLineSelector: options must be a table", 2) end
    if options.validation ~= nil and options.validation ~= "clamp" and options.validation ~= "reject" then
        error("CreatePerLineSelector: validation must be clamp or reject", 2)
    end
    local maximum = options.max == nil and 10 or options.max
    if type(maximum) ~= "number" or maximum < 1 or maximum ~= math.floor(maximum) then
        error("CreatePerLineSelector: options.max must be a positive integer", 2)
    end
    local value = options.value
    if value ~= nil and (type(value) ~= "number" or value < 1 or value ~= math.floor(value)) then
        error("CreatePerLineSelector: options.value must be a positive integer or nil", 2)
    end
    if options.inputLabel ~= nil and type(options.inputLabel) ~= "string" then
        error("CreatePerLineSelector: options.inputLabel must be a string", 2)
    end
    if options.noneText ~= nil and type(options.noneText) ~= "string" then
        error("CreatePerLineSelector: options.noneText must be a string", 2)
    end
    if options.onChange ~= nil and type(options.onChange) ~= "function" then
        error("CreatePerLineSelector: options.onChange must be a function", 2)
    end
    if options.single ~= nil and options.single ~= true then
        error("CreatePerLineSelector: options.single must be true or nil", 2)
    end
    local selector, isNew = Factory:AcquireCompositeHost(PER_LINE_POOL, parent)
    if isNew then
        local label = EXUI:CreateVisualFontString(selector, EXFONTFRAME, "GameFontHighlightSmall")
        label:SetJustifyH("LEFT")
        label:SetJustifyV("MIDDLE")
        label:SetWordWrap(false)
        MODERN.ApplyTextRole(label, "control", MC.muted)
        selector._exPerLineLabel = label
        function selector:SetValue(count)
            if count ~= nil and (type(count) ~= "number" or count < 1 or count ~= math.floor(count)) then
                error("PerLineSelector:SetValue expects a positive integer or nil", 2)
            end
            self._exPerLineValue = count
            RefreshPerLine(self)
        end
        function selector:GetValue() return self._exPerLineValue end
        function selector:Release() Factory:ReleaseCompositeHost(self) end
    end
    selector._exPerLineValue = value
    selector._exPerLineOnChange = options.onChange
    selector._exPerLineSingle = options.single == true

    local size, gap = GM.size.controlHeight, GM.space.perLineGap
    selector._exPerLineSquares = {}
    selector._exMinWidth = nil
    function selector:Relayout() end
    if options.single then
        local squares = maximum <= 10
        for index = 1, squares and maximum or 0 do
            selector._exPerLineSquares[index] = EXUI:CreateButton(selector, size, size, tostring(index),
                function(_, mouseButton, down)
                    if (mouseButton ~= nil and mouseButton ~= "LeftButton") or down then return end
                    CommitPerLine(selector, index)
                end, { compact = true })
        end
        selector._exPerLineNone, selector._exPerLineInput = nil, nil
        if squares then
            -- 一排方块：按当前宽平分，边长在 perLineMinSquare 和控件高之间，竖直居中。
            function selector:Relayout()
                local edge = math.floor((self:GetWidth() - (maximum - 1) * gap) / maximum)
                edge = math.max(GM.size.perLineMinSquare, math.min(size, edge))
                for index, square in ipairs(self._exPerLineSquares) do
                    square:SetSize(edge, edge)
                    square:ClearAllPoints()
                    square:SetPoint("TOPLEFT", self, "TOPLEFT", (index - 1) * (edge + gap), -(size - edge) / 2)
                end
            end
            selector._exMinWidth = maximum * GM.size.perLineMinSquare + (maximum - 1) * gap
            selector:SetSize(maximum * size + (maximum - 1) * gap, size)
            selector:Relayout()
        else
            local input = EXUI:CreateNumberInput(selector, GM.size.perLineInputWidth, {
                min = 1, max = maximum, step = 1, integer = true, value = value,
                validation = options.validation,
                onChanged = function(number) CommitPerLine(selector, number) end,
            })
            input:ClearAllPoints()
            input:SetPoint("TOPLEFT", selector, "TOPLEFT", 0, 0)
            selector._exPerLineInput = input
            selector:SetSize(GM.size.perLineInputWidth, size)
        end
        selector._exPerLineLabel:SetText("")
        selector._exPerLineLabel:Hide()
        RefreshPerLine(selector)
        Factory:AttachPoolRelease(selector, function(self)
            for _, square in ipairs(self._exPerLineSquares) do ReleasePooledChild(square) end
            if self._exPerLineInput then ReleasePooledChild(self._exPerLineInput) end
            self._exPerLineSquares, self._exPerLineNone, self._exPerLineInput = nil, nil, nil
            self._exPerLineValue, self._exPerLineOnChange, self._exMinWidth, self._exPerLineSingle = nil, nil, nil, nil
        end)
        return selector
    end
    for index = 1, maximum do
        local square = EXUI:CreateButton(selector, size, size, tostring(index), function(_, mouseButton, down)
            if (mouseButton ~= nil and mouseButton ~= "LeftButton") or down then return end
            CommitPerLine(selector, index)
        end, { compact = true })
        square:ClearAllPoints()
        square:SetPoint("TOPLEFT", selector, "TOPLEFT", (index - 1) * (size + gap), 0)
        selector._exPerLineSquares[index] = square
    end

    local rowTop = -(size + GM.space.settingsV2Gap)
    local rowWidth = 0
    local label = selector._exPerLineLabel
    label:ClearAllPoints()
    if options.inputLabel then
        label:SetText(options.inputLabel)
        label:SetPoint("LEFT", selector, "TOPLEFT", 0, rowTop - size / 2)
        label:Show()
        rowWidth = math.ceil(label:GetUnboundedStringWidth()) + 2 * gap
    else
        label:SetText("")
        label:Hide()
    end
    local input = EXUI:CreateNumberInput(selector, GM.size.perLineInputWidth, {
        min = 1, step = 1, integer = true, value = value,
        validation = options.validation,
        onChanged = function(number) CommitPerLine(selector, number) end,
    })
    input:ClearAllPoints()
    input:SetPoint("TOPLEFT", selector, "TOPLEFT", rowWidth, rowTop)
    selector._exPerLineInput = input
    rowWidth = rowWidth + GM.size.perLineInputWidth

    selector._exPerLineNone = nil
    if options.noneText then
        local none = EXUI:CreateButton(selector, GM.size.buttonMinWidth, size, options.noneText,
            function(_, mouseButton, down)
                if (mouseButton ~= nil and mouseButton ~= "LeftButton") or down then return end
                CommitPerLine(selector, nil)
            end)
        none:ClearAllPoints()
        none:SetPoint("LEFT", input, "RIGHT", 2 * gap, 0)
        selector._exPerLineNone = none
        rowWidth = rowWidth + 2 * gap + none:GetWidth()
    end

    selector:SetSize(math.max(maximum * size + (maximum - 1) * gap, rowWidth), size + GM.space.settingsV2Gap + size)
    RefreshPerLine(selector)
    Factory:AttachPoolRelease(selector, function(self)
        for _, square in ipairs(self._exPerLineSquares) do ReleasePooledChild(square) end
        if self._exPerLineNone then ReleasePooledChild(self._exPerLineNone) end
        ReleasePooledChild(self._exPerLineInput)
        self._exPerLineSquares, self._exPerLineNone, self._exPerLineInput = nil, nil, nil
        self._exPerLineValue, self._exPerLineOnChange = nil, nil
        self._exPerLineLabel:SetText("")
        self._exPerLineLabel:Hide()
    end)
    return selector
end

-- A small rectangular preview and two strict number inputs. Data owns occupancy.
local GRID_SIZE_POOL = "EXUI.GridSizePicker"
Factory:InitCompositePool(GRID_SIZE_POOL)

local function CheckGridSize(rows, cols)
    return type(rows) == "number" and rows >= 1 and rows <= 8 and rows == math.floor(rows)
        and type(cols) == "number" and cols >= 1 and cols <= 15 and cols == math.floor(cols)
end

local function PaintGridSize(picker, rows, cols)
    local state = picker._exGridSize
    if not state then return end
    rows, cols = rows or state.rows, cols or state.cols
    for index, cell in ipairs(state.cells) do
        local row, col = math.floor((index - 1) / 6) + 1, (index - 1) % 6 + 1
        cell._exButtonVariant = row <= rows and col <= cols and "primary" or "secondary"
        Internal.PaintModernButton(cell)
    end
end

local function RestoreGridSize(picker)
    local state = picker._exGridSize
    if not state then return end
    state.rowInput:SetNumber(state.rows)
    state.colInput:SetNumber(state.cols)
    PaintGridSize(picker)
end

local function CommitGridSize(picker, state, rows, cols)
    if picker._exGridSize ~= state or not state.enabled then return end
    local changed = state.rows ~= rows or state.cols ~= cols
    state.rows, state.cols = rows, cols
    RestoreGridSize(picker)
    if changed then state.onChange(rows, cols) end -- May release/rebuild this lease.
end

-- options: rows/cols, rowLabel/colLabel, onChange(rows,cols), disabled=false.
-- SetValue/GetValue are silent. Release retires the lease before clearing focus.
function EXUI:CreateGridSizePicker(parent, options)
    if type(options) ~= "table" or not CheckGridSize(options.rows, options.cols) then
        error("CreateGridSizePicker: rows 1..8 and cols 1..15 must be integers", 2)
    end
    if type(options.rowLabel) ~= "string" or type(options.colLabel) ~= "string"
        or type(options.onChange) ~= "function" then
        error("CreateGridSizePicker: rowLabel/colLabel and onChange are required", 2)
    end
    local picker = Factory:AcquireCompositeHost(GRID_SIZE_POOL, parent)
    local state = { rows=options.rows, cols=options.cols, cells={}, enabled=options.disabled ~= true,
        onChange=options.onChange }
    picker._exGridSize = state
    local size, gap = 34, 4
    local width, previewHeight = 6 * size + 5 * gap, 4 * size + 3 * gap
    for row = 1, 4 do
        for col = 1, 6 do
            local cell = EXUI:CreateButton(picker, size, size, "", function(_, button, down)
                if down or (button and button ~= "LeftButton") then return end
                CommitGridSize(picker, state, row, col)
            end, { compact=true })
            cell:SetPoint("TOPLEFT", picker, "TOPLEFT", (col - 1) * (size + gap), -(row - 1) * (size + gap))
            cell._exGridSizeOwner, cell._exGridRow, cell._exGridCol = picker, row, col
            -- Permanent hooks read the current lease; never capture a pooled owner.
            if not cell._exGridSizeHoverHook then
                cell._exGridSizeHoverHook = true
                cell:HookScript("OnEnter", function(self)
                    local owner = self._exGridSizeOwner
                    local current = owner and owner._exGridSize
                    if current and current.enabled then PaintGridSize(owner, self._exGridRow, self._exGridCol) end
                end)
                cell:HookScript("OnLeave", function(self)
                    local owner = self._exGridSizeOwner
                    if owner and owner._exGridSize then PaintGridSize(owner) end
                end)
            end
            state.cells[#state.cells + 1] = cell
        end
    end
    local function ConfirmNumbers()
        if picker._exGridSize ~= state or not state.enabled then return end
        -- Use the same raw parser/validator as NumberInput, including the other draft.
        local rowsOK, rows = Internal.ReadNumberInputDraft(state.rowInput)
        local colsOK, cols = Internal.ReadNumberInputDraft(state.colInput)
        if not rowsOK or not colsOK then RestoreGridSize(picker); return end
        CommitGridSize(picker, state, rows, cols)
    end
    local function Rejected()
        if picker._exGridSize == state then RestoreGridSize(picker) end
    end
    local inputWidth = (width - gap) / 2
    state.rowInput = EXUI:CreateNumberInput(picker, inputWidth, {
        min=1, max=8, integer=true, value=state.rows, label=options.rowLabel,
        validation="reject", onChanged=ConfirmNumbers, onRejected=Rejected,
    })
    state.colInput = EXUI:CreateNumberInput(picker, inputWidth, {
        min=1, max=15, integer=true, value=state.cols, label=options.colLabel,
        validation="reject", onChanged=ConfirmNumbers, onRejected=Rejected,
    })
    local inputTop = previewHeight + GM.space.settingsV2Gap + GM.size.inputHeight
    state.rowInput:SetPoint("TOPLEFT", picker, "TOPLEFT", 0, -inputTop)
    state.colInput:SetPoint("TOPLEFT", picker, "TOPLEFT", inputWidth + gap, -inputTop)
    picker:SetSize(width, inputTop + GM.size.inputHeight)
    function picker:GetValue()
        local current = self._exGridSize
        if current then return current.rows, current.cols end
    end
    function picker:SetValue(rows, cols)
        if not CheckGridSize(rows, cols) then error("GridSizePicker:SetValue expects rows 1..8 and cols 1..15", 2) end
        local current = self._exGridSize
        if not current then return end
        current.rows, current.cols = rows, cols
        RestoreGridSize(self)
    end
    function picker:SetEnabled(enabled)
        local current = self._exGridSize
        if not current then return end
        current.enabled = enabled == true
        current.rowInput:SetEnabled(current.enabled)
        current.colInput:SetEnabled(current.enabled)
        for _, cell in ipairs(current.cells) do cell:SetEnabled(current.enabled) end
        RestoreGridSize(self)
    end
    function picker:Release() Factory:ReleaseCompositeHost(self) end
    Factory:AttachPoolRelease(picker, function(self)
        local current = self._exGridSize
        self._exGridSize = nil
        if not current then return end
        current.onChange = nil
        for _, cell in ipairs(current.cells) do
            cell._exGridSizeOwner, cell._exGridRow, cell._exGridCol = nil, nil, nil
            ReleasePooledChild(cell)
        end
        ReleasePooledChild(current.rowInput)
        ReleasePooledChild(current.colInput)
    end)
    picker:SetEnabled(state.enabled)
    return picker
end

local SetContextGlyph
local function StatusPalette(kind)
    local c = FeedbackColors()
    if kind == "ok" or kind == "success" then return c.statusOkFg, c.statusOkBorder, c.statusOkTint, "ok" end
    if kind == "error" or kind == "err" then return c.statusErrFg, c.statusErrBorder, c.statusErrTint, "error" end
    return c.statusInfoFg, c.statusInfoBorder, c.statusInfoTint, "info"
end

-- options.surface 选择叠层要合成的真实父背景：页内提示压在卡片上（默认
-- statusNoticeBase），浮动 Toast 压在弹出层底色上（toast）。不按父级猜，
-- 由调用方声明，避免把 popup 专属色当成通用提示底。
function EXUI:CreateStatusNotice(parent, width, kind, title, description, options)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(width or GM.size.toastWidth,
        description and GM.size.statusNoticeHeightWithDesc or GM.size.statusNoticeHeight)
    frame._exStatusSurface = type(options) == "table" and options.surface or nil
    frame.icon = CreateFrame("Frame", nil, frame)
    frame.icon:SetSize(GM.size.statusIconSize, GM.size.statusIconSize)
    -- 图标比标题多 1px 上内缩，让 16px 图标与 14px 标题视觉对中。
    frame.icon:SetPoint("TOPLEFT", GM.space.statusPaddingX, -(GM.space.statusPaddingY + 1))
    frame.title = FeedbackText(frame, GM.font.label, FeedbackColors().statusDesc, "")
    frame.title:SetPoint("TOPLEFT", GM.space.statusTextIndent, -GM.space.statusPaddingY)
    frame.title:SetPoint("TOPRIGHT", -GM.space.statusPaddingX, -GM.space.statusPaddingY)
    frame.description = FeedbackText(frame, GM.font.text, FeedbackColors().statusDesc, "")
    frame.description:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -GM.space.statusDescGap)
    frame.description:SetPoint("TOPRIGHT", frame.title, "BOTTOMRIGHT", 0, -GM.space.statusDescGap)
    frame.SetStatus = function(self, nextKind, nextTitle, nextDescription)
        local c = FeedbackColors()
        local fg, border, tint, normalized = StatusPalette(nextKind)
        local base = self._exStatusSurface == "toast" and c.toast or c.statusNoticeBase
        local alpha = tint[4] or 1
        local fill = { base[1] * (1 - alpha) + tint[1] * alpha,
            base[2] * (1 - alpha) + tint[2] * alpha,
            base[3] * (1 - alpha) + tint[3] * alpha, 1 }
        self:SetHeight(nextDescription and nextDescription ~= ""
            and GM.size.statusNoticeHeightWithDesc or GM.size.statusNoticeHeight)
        EXUI:SetControlSurface(self, GM.radius.popup, fill, border)
        SetContextGlyph(self.icon, "status" .. normalized, fg)
        self.title:SetText(nextTitle or "")
        self.title:SetTextColor(unpack(fg))
        self.description:SetText(nextDescription or "")
        self.description:SetTextColor(unpack(c.statusDesc))
    end
    frame:SetStatus(kind, title, description)
    return frame
end

local function ReflowToasts()
    local list = EXUI._statusToasts or {}
    local margin = GM.space.toastScreenMargin
    local offset = margin
    for index = #list, 1, -1 do
        local toast = list[index]
        toast._stackOffset = offset
        toast:ClearAllPoints()
        toast:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -margin, offset)
        offset = offset + toast:GetHeight() + GM.space.toastStackGap
    end
end

function EXUI:ShowStatusToast(kind, title, description)
    local list = self._statusToasts or {}
    self._statusToasts = list
    self._statusToastPool = self._statusToastPool or {}
    local toast = table.remove(self._statusToastPool)
    if toast then
        toast:SetStatus(kind, title, description)
    else
        toast = self:CreateStatusNotice(UIParent, GM.size.toastWidth, kind, title, description,
            { surface = "toast" })
        toast:SetFrameStrata("FULLSCREEN_DIALOG")
        toast:SetFrameLevel(9200)
        toast.shadow = toast:CreateTexture(nil, "BACKGROUND", nil, -2)
        toast.shadow:SetPoint("TOPLEFT", -GM.space.statusDescGap, GM.space.statusDescGap)
        toast.shadow:SetPoint("BOTTOMRIGHT", GM.space.statusDescGap, -GM.space.statusDescGap)
        toast.close = CreateFrame("Button", nil, toast)
        toast.close:SetSize(GM.size.toastCloseSize, GM.size.toastCloseSize)
        -- 关闭按钮与图标左右对称；-2 是 18px 按钮与 14px 标题的对中差。
        toast.close:SetPoint("TOPRIGHT", -GM.space.statusPaddingX, -(GM.space.statusPaddingY - 2))
        toast.close:SetScript("OnClick", function() EXUI:DismissStatusToast(toast) end)
        toast.closeGlyph = CreateFrame("Frame", nil, toast.close)
        toast.closeGlyph:SetSize(GM.size.toastCloseGlyphSize, GM.size.toastCloseGlyphSize)
        toast.closeGlyph:SetPoint("CENTER")
        toast.title:ClearAllPoints()
        toast.title:SetPoint("TOPLEFT", GM.space.statusTextIndent, -GM.space.statusPaddingY)
        toast.title:SetPoint("TOPRIGHT",
            -(GM.space.statusPaddingX + GM.size.toastCloseSize + GM.space.statusDescGap),
            -GM.space.statusPaddingY)
    end
    -- 用户要求移除 Toast 外围纯黑半透明方框；保留纹理对象供池复用，只隐藏。
    toast.shadow:SetColorTexture(unpack(FeedbackColors().toastShadow))
    toast.shadow:Hide()
    SetContextGlyph(toast.closeGlyph, "close", FeedbackColors().statusDesc)
    toast._life = 0
    toast._inactive = nil
    list[#list + 1] = toast
    ReflowToasts()
    toast:SetAlpha(0)
    toast:Show()
    toast:SetScript("OnUpdate", function(self, elapsed)
        self._life = (self._life or 0) + elapsed
        local duration = (kind == "error" or kind == "err") and 5 or 3
        local margin = GM.space.toastScreenMargin
        if self._life < 0.15 then
            local progress = self._life / 0.15
            self:SetAlpha(progress)
            self:ClearAllPoints()
            self:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -margin,
                (self._stackOffset or margin) - GM.space.toastStackGap * (1 - progress))
        elseif self._life >= duration + 0.15 then
            EXUI:DismissStatusToast(self)
        elseif self._life >= duration then
            self:SetAlpha(1 - (self._life - duration) / 0.15)
        else
            self:SetAlpha(1)
            self:ClearAllPoints()
            self:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -margin, self._stackOffset or margin)
        end
    end)
    return toast
end

function EXUI:DismissStatusToast(toast)
    if not toast or toast._inactive then return end
    toast._inactive = true
    toast:SetScript("OnUpdate", nil)
    toast:Hide()
    local list = self._statusToasts or {}
    for index, item in ipairs(list) do
        if item == toast then table.remove(list, index); break end
    end
    self._statusToastPool[#self._statusToastPool + 1] = toast
    ReflowToasts()
end

function EXUI:HideContextMenu()
    -- 点击某一项时，行自己会先把会话从菜单上摘下（见 CreateContextRow 的 OnClick），
    -- 所以这里看到的会话一定是“菜单被放弃”的情形：直接判为失效。
    local session = self._contextMenu and self._contextMenu._v2Session
    if session then
        session.alive = false
        self._contextMenu._v2Session = nil
    end
    for _, menu in ipairs({ self._contextMenu, self._contextSubmenu }) do
        if menu then
            menu:Hide()
            for _, row in ipairs(menu._rows or {}) do row._item = nil end
        end
    end
    if self._contextCloser then self._contextCloser:Hide() end
    -- onHide 只属于本次显示：先摘下再调用，回调里再开新菜单也不会被重复通知。
    local onHide = self._contextOnHide
    self._contextOnHide = nil
    if onHide then onHide() end
end

-- 菜单和状态符号共用正式 Unified 资源；Lucide 只接受已登记 ID。
local CONTEXT_ICON_ROOT = "Interface\\AddOns\\ExwindCore\\Textures\\Icons\\Unified\\"
local CONTEXT_ICONS = {
    add = "plus", delete = "trash", edit = "edit", copy = "copy", move = "move",
    eye = "eye", check = "check", arrow = "arrow-right", close = "close",
    statusinfo = "info", statusok = "success", statuserror = "error",
    import = "import", export = "export", duplicate = "duplicate", rename = "edit",
    settings = "settings", refresh = "refresh", play = "play", stop = "stop",
    lock = "lock", unlock = "unlock", reset = "reset", info = "info",
}

SetContextGlyph = function(host, name, color)
    local resource = CONTEXT_ICONS[name]
    local texture
    if type(name) == "number" then
        texture = name
    elseif type(name) == "string" and (name:find("\\", 1, true) or name:find("/", 1, true)) then
        texture = name
    elseif resource then
        texture = CONTEXT_ICON_ROOT .. resource .. ".tga"
    elseif ExwindTools.GUIIcons.ids[name] then
        texture = EXUI:GetIcon(name)
    end
    if not texture then
        host:Hide()
        return
    end
    if not host._iconTexture then
        host._iconTexture = host:CreateTexture(nil, "OVERLAY")
        host._iconTexture:SetAllPoints()
    end
    host._iconTexture:SetTexture(texture)
    host._iconTexture:SetVertexColor(unpack(color))
    host:Show()
end

local BuildContextPanel

-- [WEB-REQ 57] 长右键菜单：滚轮滚动视口（行/分隔线都在可滚动内容框内），并刷新右侧滚动指示条。
local function ScrollContextMenu(menu, delta)
    local viewport = menu.viewport
    if not viewport or (menu._scrollMax or 0) <= 0 then return end
    local offset = math.max(0, math.min(menu._scrollMax, (viewport:GetVerticalScroll() or 0) - delta * GM.size.menuRowHeight * 2))
    viewport:SetVerticalScroll(offset)
    local thumb = menu.thumb
    if thumb and thumb:IsShown() then
        local travel = menu._viewportHeight - thumb:GetHeight() - 4
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", viewport, "TOPRIGHT", -2, -2 - travel * offset / menu._scrollMax)
    end
end

local function CreateContextRow(menu)
    local c = FeedbackColors()
    local padX, slotGap = GM.space.menuRowPaddingX, GM.space.menuRowSlotGap
    local row = CreateFrame("Button", nil, menu.content or menu)
    row:SetHeight(GM.size.menuRowHeight)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", function(_, delta) ScrollContextMenu(menu, delta) end)
    row.hover = row:CreateTexture(nil, "BACKGROUND")
    row.hover:SetAllPoints()
    row.hover:Hide()
    row.icon = CreateFrame("Frame", nil, row)
    row.icon:SetSize(GM.size.menuIconSize, GM.size.menuIconSize)
    row.icon:SetPoint("LEFT", padX, 0)
    row.label = FeedbackText(row, GM.font.label, c.contextMenuText, "")
    row.label:SetPoint("LEFT", row.icon, "RIGHT", slotGap, 0)
    -- 右界在 BuildContextPanel 里按本项是否有勾/箭头重设：没有标记的项不空出标记槽。
    row.label:SetPoint("RIGHT", -padX, 0)
    row.label:SetWordWrap(false) -- 宽度按真实文字测量；极端超长文字单行截断而不是撑高行
    -- 快捷键列（item.shortcut）：靠行右缘、次要文字色；位置在 BuildContextPanel 里按本项有没有勾/箭头重设。
    row.shortcut = FeedbackText(row, GM.font.label, c.textDim, "")
    row.shortcut:SetJustifyH("RIGHT")
    row.shortcut:SetWordWrap(false)
    row.check = CreateFrame("Frame", nil, row)
    row.check:SetSize(GM.size.menuCheckSize, GM.size.menuCheckSize)
    row.check:SetPoint("RIGHT", -padX, 0)
    row.arrow = CreateFrame("Frame", nil, row)
    row.arrow:SetSize(GM.size.menuArrowSize, GM.size.menuArrowSize)
    row.arrow:SetPoint("RIGHT", -padX, 0)
    row:SetScript("OnEnter", function(self)
        local item = self._item
        if not item or item.disabled then return end
        self.hover:Show()
        if menu == EXUI._contextMenu and EXUI._contextSubmenu then EXUI._contextSubmenu:Hide() end
        if item.submenu then
            local submenu = BuildContextPanel(item.submenu, nil, 9404, EXUI._contextSubmenu)
            EXUI._contextSubmenu = submenu
            local right = menu:GetRight() + 2
            local left = right + submenu:GetWidth() > UIParent:GetWidth() - 4
                and menu:GetLeft() - submenu:GetWidth() - 2 or right
            PlaceClamped(submenu, left, self:GetTop() + 5)
            submenu:Show()
        end
    end)
    row:SetScript("OnLeave", function(self) self.hover:Hide() end)
    row:SetScript("OnClick", function(self)
        local item = self._item
        if not item or item.disabled or item.submenu then return end
        local callback = item.onClick
        local menuFrame = EXUI._contextMenu
        local session = menuFrame and menuFrame._v2Session
        -- 先把会话从菜单上摘下再隐藏菜单：HideContextMenu 因此不会把本次会话判成
        -- “被放弃”而提前置为失效，声明式菜单回调里的 Guard 仍能看到有效会话。
        if session then menuFrame._v2Session = nil end
        EXUI:HideContextMenu()
        if callback then callback() end
        -- 声明式菜单的回调自己会 Release；普通菜单在这里收尾。错误直接向上抛，
        -- 不做保护调用，也不吞。
        if session then session:Release() end
    end)
    return row
end

BuildContextPanel = function(items, title, level, reuse)
    local c = FeedbackColors()
    local edge, padX, slotGap =
        GM.space.menuEdgePadding, GM.space.menuRowPaddingX, GM.space.menuRowSlotGap
    -- 标记槽：勾与箭头取较宽的一个，加上它与文字之间的间隙。
    local markSlot = math.max(GM.size.menuCheckSize, GM.size.menuArrowSize)
    local menu = reuse or CreateFrame("Frame", nil, UIParent)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(level)
    menu:EnableMouse(true)
    if not menu._rows then
        menu._rows, menu._dividers = {}, {}
        menu.title = FeedbackText(menu, GM.font.small, c.contextMenuTitle, "")
        -- 标题与菜单项的文字左边缘对齐（外边距 + 行内内边距 + 图标 + 间隙）。
        menu.title:SetPoint("TOPLEFT", edge + padX + GM.size.menuIconSize + slotGap, -edge * 2)
        menu.title:SetPoint("TOPRIGHT", -(edge + padX), -edge * 2)
        -- [WEB-REQ 57] 视口 + 内容框：行与分隔线都挂在内容框上，超过最大高度时滚动。
        menu.viewport = CreateFrame("ScrollFrame", nil, menu)
        menu.content = CreateFrame("Frame", nil, menu.viewport)
        menu.viewport:SetScrollChild(menu.content)
        menu.viewport:EnableMouseWheel(true)
        menu.viewport:SetScript("OnMouseWheel", function(_, delta) ScrollContextMenu(menu, delta) end)
        menu:EnableMouseWheel(true)
        menu:SetScript("OnMouseWheel", function(_, delta) ScrollContextMenu(menu, delta) end)
        menu.thumb = menu.viewport:CreateTexture(nil, "OVERLAY")
        menu.thumb:SetWidth(GM.size.menuScrollThumbWidth)
        menu._measure = FeedbackText(menu, GM.font.label, c.contextMenuText, "")
        menu._measure:Hide()
    end
    -- [WEB-REQ 57] 真实测宽：用同字体 FontString 的 GetUnboundedStringWidth（与暴雪 MenuTemplates 同法），
    -- 不再用“54 + 字节数 × 8”估算（中文/多语言会严重高估）。
    -- 行横向开销 = 两侧菜单外边距 + 行内左右内边距 + 图标 + 间隙 + 标记槽（勾/箭头及其间隙）。
    local screenWidth = UIParent:GetWidth()
    local width = GM.size.menuMinWidth
    local rowChrome = edge * 2 + padX * 2 + GM.size.menuIconSize + slotGap + markSlot + slotGap
    for _, item in ipairs(items) do
        if item.text then
            menu._measure:SetText(tostring(item.text))
            local textWidth = math.ceil(menu._measure:GetUnboundedStringWidth())
            if item.shortcut then
                -- 快捷键列：文字后至少留 menuShortcutGap，再放快捷键。
                menu._measure:SetText(tostring(item.shortcut))
                textWidth = textWidth + GM.space.menuShortcutGap + math.ceil(menu._measure:GetUnboundedStringWidth())
            end
            width = math.max(width, textWidth + rowChrome)
        end
    end
    if title and title ~= "" then
        menu._measure:SetText(title)
        width = math.max(width, math.ceil(menu._measure:GetUnboundedStringWidth()) + (edge + padX) * 2)
    end
    width = math.min(width, GM.size.menuMaxWidth, math.max(100, screenWidth - edge * 2))
    for _, row in ipairs(menu._rows) do row:Hide(); row._item = nil end
    for _, line in ipairs(menu._dividers) do line:Hide() end
    local y = -edge
    local titleOffset = 0
    if title and title ~= "" then
        menu.title:SetText(title)
        menu.title:SetTextColor(unpack(c.contextMenuTitle))
        menu.title:Show()
        titleOffset = GM.size.menuTitleHeight
    else
        menu.title:Hide()
    end
    local rowIndex, dividerIndex = 0, 0
    for _, item in ipairs(items) do
        if item.divider then
            dividerIndex = dividerIndex + 1
            local line = menu._dividers[dividerIndex]
            if not line then
                line = menu.content:CreateTexture(nil, "ARTWORK")
                menu._dividers[dividerIndex] = line
            end
            line:SetColorTexture(unpack(c.contextMenuDivider))
            line:SetHeight(1)
            line:ClearAllPoints()
            -- 分隔线左右与行内文字区同一内缩，上下各留一个分隔间距。
            line:SetPoint("TOPLEFT", edge + padX, y - GM.space.menuDividerGap)
            line:SetPoint("TOPRIGHT", -(edge + padX), y - GM.space.menuDividerGap)
            line:Show()
            y = y - (GM.space.menuDividerGap * 2 + 1)
        else
            rowIndex = rowIndex + 1
            local row = menu._rows[rowIndex]
            if not row then
                row = CreateContextRow(menu)
                menu._rows[rowIndex] = row
            end
            row._item = item
            row:SetSize(width - edge * 2, GM.size.menuRowHeight)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", edge, y)
            row.hover:SetColorTexture(unpack(item.danger and c.contextMenuDangerHover or c.contextMenuHover))
            row.hover:Hide()
            local color = item.disabled and c.contextMenuDisabled or (item.danger and c.contextMenuDanger or c.contextMenuText)
            SetContextGlyph(row.icon, item.icon, item.disabled and c.contextMenuDisabled or
                (item.danger and c.contextMenuDanger or c.contextMenuIcon))
            -- 文字右界按需：只有真的有勾或箭头才让出标记槽。
            local itemMark = item.submenu and GM.size.menuArrowSize
                or (item.checked and GM.size.menuCheckSize) or 0
            local right = padX + (itemMark > 0 and (itemMark + slotGap) or 0)
            row.label:ClearAllPoints()
            row.label:SetPoint("LEFT", row.icon, "RIGHT", slotGap, 0)
            row.shortcut:ClearAllPoints()
            if item.shortcut then
                row.shortcut:SetText(tostring(item.shortcut))
                row.shortcut:SetTextColor(unpack(item.disabled and c.contextMenuDisabled or c.textDim))
                row.shortcut:SetPoint("RIGHT", -right, 0)
                row.shortcut:Show()
                row.label:SetPoint("RIGHT", row.shortcut, "LEFT", -GM.space.menuShortcutGap, 0)
            else
                row.shortcut:SetText("")
                row.shortcut:Hide()
                row.label:SetPoint("RIGHT", -right, 0)
            end
            row.label:SetText(item.text or "")
            row.label:SetTextColor(unpack(color))
            if item.checked then
                SetContextGlyph(row.check, "check", c.contextMenuCheck)
                row.check:Show()
            else
                row.check:Hide()
            end
            if item.submenu then
                SetContextGlyph(row.arrow, "arrow", c.contextMenuIcon)
                row.arrow:Show()
            else
                row.arrow:Hide()
            end
            row:Show()
            y = y - GM.size.menuRowHeight
        end
    end
    -- [WEB-REQ 57] 限高 + 滚动：菜单最高 menuMaxHeight（再受屏幕高度约束），内容更高时视口内滚动，
    -- 因此 40 项的菜单也能滚到每一项；高度始终 <= 屏幕高 - 两侧外边距，PlaceClamped 才能把整块夹进屏幕。
    local contentHeight = -y + edge
    local limit = math.min(GM.size.menuMaxHeight,
        math.max(GM.size.menuRowHeight + edge * 2, UIParent:GetHeight() - edge * 2))
    local viewportHeight = math.min(contentHeight, limit - titleOffset)
    menu.content:SetSize(width, contentHeight)
    menu.viewport:ClearAllPoints()
    menu.viewport:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, -titleOffset)
    menu.viewport:SetPoint("TOPRIGHT", menu, "TOPRIGHT", 0, -titleOffset)
    menu.viewport:SetHeight(viewportHeight)
    menu.viewport:SetVerticalScroll(0)
    menu._viewportHeight = viewportHeight
    menu._scrollMax = math.max(0, contentHeight - viewportHeight)
    local scrollable = menu._scrollMax > 0
    menu.thumb:SetShown(scrollable)
    if scrollable then
        menu.thumb:SetColorTexture(unpack(c.contextMenuIcon))
        menu.thumb:SetHeight(math.max(20, (viewportHeight - 4) * viewportHeight / contentHeight))
        menu.thumb:ClearAllPoints()
        menu.thumb:SetPoint("TOPRIGHT", menu.viewport, "TOPRIGHT", -2, -2)
    end
    menu:SetSize(width, titleOffset + viewportHeight)
    EXUI:SetControlSurface(menu, GM.radius.popup, c.contextMenu, c.contextMenuBorder)
    return menu
end

-- options: items（必填）、title、x / y（屏幕坐标，默认鼠标处由调用方给出）、
--   anchor（可选 Frame：菜单贴在它下方、左边对齐，仍夹在屏幕内；给了 anchor 就不看 x / y）、
--   onHide()（可选：本次菜单以任何方式关闭时调用一次——点选、点外部、Esc、被下一个菜单替换）。
function EXUI:ShowContextMenu(options)
    assert(type(options) == "table" and type(options.items) == "table", "context menu needs items")
    assert(options.onHide == nil or type(options.onHide) == "function", "context menu onHide must be a function")
    assert(options.anchor == nil or (type(options.anchor) == "table" and type(options.anchor.GetLeft) == "function"),
        "context menu anchor must be a frame")
    self:HideContextMenu()
    local closer = self._contextCloser
    if not closer then
        closer = CreateFrame("Button", nil, UIParent)
        closer:SetAllPoints(UIParent)
        closer:SetFrameStrata("FULLSCREEN_DIALOG")
        closer:SetFrameLevel(9400)
        closer:EnableMouse(true)
        -- 右键菜单只拦鼠标（点空白处关），不拦任何按键。
        closer:SetScript("OnClick", function() EXUI:HideContextMenu() end)
        self._contextCloser = closer
    end
    local menu = BuildContextPanel(options.items, options.title or "", 9402, self._contextMenu)
    self._contextMenu = menu
    local x, y = options.x, options.y
    local anchor = options.anchor
    if anchor and anchor:GetLeft() and anchor:GetBottom() then
        local scale = anchor:GetEffectiveScale() / UIParent:GetEffectiveScale()
        x, y = anchor:GetLeft() * scale, anchor:GetBottom() * scale - 2
    end
    PlaceClamped(menu, x, y)
    self._contextOnHide = options.onHide
    closer:Show()
    menu:Show()
    return menu
end


-- =========================================================
-- 人物卡片（PersonCards）：声明式人物卡片网格 + 只读网址框
--
-- 用法（Grid 自定义条目或 V1 custom section；调用方只给数据表，不写布局）：
--   { key = "people", type = "custom", renderer = "EXUI.PersonCards", measure = true,
--     x = 1, y = 1, w = 198, h = 1,
--     opts = { columns = 4, minColumnWidth = 210,            -- 必填；宽度不足时自动降列
--              columnGap = 8, rowGap = 8,                     -- 可选，默认 GM.space.settingsV2Gap
--              compact = true,                                -- 可选，二级小号卡：小头像/小字，不显示网址框
--              layout = "portrait",                           -- 可选，竖排高卡：圆形头像在上，名称/标签/描述居中，网址框贴底
--                                                             -- 或 "chip"：按名字长度自适应宽度的小胶囊，自动换行；
--                                                             --   只显示头像与名字，columns/minColumnWidth 可省
--              surface = "plain",                             -- 可选，默认 "card"。"plain" 不画卡片底色与边框：
--                                                             --   头像外圈改细边框色、不画柔光、首字母底透明，
--                                                             --   供细线风格的页面使用
--              showAvatar = false,                            -- 可选，只对 layout="chip" 有效：不画头像，
--                                                             --   胶囊改为纯文字并放大一档留白与字号
--              people = {
--                  { name = "名称", description = "描述", avatar = "Interface\\...\\头像.tga",
--                    url = "https://example.com",
--                    badge = { icon = "Interface\\...\\平台.png", color = { r, g, b, a } },
--                    tags = { "创作者", { text = "特别感谢", style = "accent" } } },
--              } } }
-- name 必填；description / avatar / url / badge 可选；tags 可选，元素为字符串（默认样式）
-- 或 { text, style }，style 只能是 "default" 或 "accent"。未声明 avatar 时显示名称首字色块。
-- badge 为头像右下角的平台角标；style="icon" 使用原尺寸品牌色图标，不画圆底。
-- 默认仍为白色单色图标 + 平台色圆底。chip 不接受 description / url / tags / badge。
-- V2 owner 复用 PersonCardsRenderer；实际高度在 layout 中经 ctx:SetContentHeight 上报。
-- =========================================================
do
    local Factory = _G.ExwindFactory
    local GC = ExwindTools.GUIColors
    local PERSON_CARD, PERSON_TAG = "EXUI.PersonCard", "EXUI.PersonTag"

    -- 间距、尺寸、字号全部读 GM。头像边长与标签高度/横向内边距暂无专用键，
    -- 取最接近的现有键（见任务报告中的“需要新增的键”）。
    local PAD = GM.space.cardBodyPadding
    local GAP = GM.space.descriptionGap
    local DEFAULT_GRID_GAP = GM.space.settingsV2Gap
    local AVATAR_SIZE = GM.size.tabHeight
    local TAG_HEIGHT = GM.size.sliderInputHeight
    local TAG_PAD_X = GM.space.settingsV2Gap
    local URL_HEIGHT = GM.size.inputHeight
    local NAME_FONT, DESC_FONT, TAG_FONT, INITIAL_FONT =
        GM.font.title, GM.font.small, GM.font.hint, GM.font.cardTitle

    -- 一级（默认）与二级（opts.compact = true）人物卡的尺寸表。二级：小头像、小字、无网址框。
    local FULL_METRICS = { pad = PAD, avatar = AVATAR_SIZE, nameFont = NAME_FONT, descFont = DESC_FONT,
        initialFont = INITIAL_FONT, url = true }
    local COMPACT_METRICS = { pad = GM.space.settingsV2Gap, avatar = GM.size.sliderInputHeight + 6,
        nameFont = GM.font.text, descFont = GM.font.hint, initialFont = GM.font.title, url = false, circle = true }
    -- 竖排高卡（opts.layout = "portrait"）：圆形头像在上，其余内容居中。
    local PORTRAIT_METRICS = { pad = PAD, avatar = GM.size.personPortraitAvatar, nameFont = NAME_FONT,
        descFont = DESC_FONT, initialFont = GM.font.pageTitle, url = true, portrait = true, circle = true }
    local PORTRAIT_RING = GM.size.personPortraitRing
    -- 小胶囊（opts.layout = "chip"）：小圆头像 + 单行名字，宽度随名字长度。
    local CHIP_METRICS = { pad = GAP, avatar = GM.size.personChipAvatar, nameFont = GM.font.text,
        initialFont = GM.font.hint, url = false, circle = true, chip = true }
    local BADGE_SIZE = GM.size.personBadgeSize
    local function BaseMetricsFor(opts)
        if opts.layout == "portrait" then return PORTRAIT_METRICS end
        if opts.layout == "chip" then return CHIP_METRICS end
        return opts.compact and COMPACT_METRICS or FULL_METRICS
    end

    -- surface="plain" 与无头像胶囊都是同一张常量表的派生；常量表本身不被改写。
    local function MetricsFor(opts)
        local base = BaseMetricsFor(opts)
        local plain = opts.surface == "plain"
        local noAvatar = base.chip and opts.showAvatar == false
        if not plain and not noAvatar and not opts.avatarSize and not opts.avatarStyle and not opts.avatarRing then return base end
        local m = {}
        for key, value in pairs(base) do m[key] = value end
        m.plain = plain or nil
        m.avatarIcon = opts.avatarStyle == "icon"
        m.avatarRing = opts.avatarRing
        if opts.avatarSize then m.avatar = opts.avatarSize end
        if noAvatar then
            m.noAvatar, m.circle = true, nil
            m.avatar = 0
            m.pad = PAD
            m.nameFont = GM.font.title
        end
        return m
    end
    -- 人物头像使用无大幅透明留白的高清圆形材质。
    local CIRCLE_TEXTURE = "Interface\\AddOns\\ExwindCore\\Textures\\Materials\\ExwindTools\\PlayerPosition\\Circle.png"
    -- 竖排卡头像背后的柔光：白色径向渐变（四边全透明），着主色后以 ADD 叠加。
    local GLOW_TEXTURE = "Interface\\AddOns\\ExwindCore\\Textures\\GUI\\SoftGlow.png"
    local PORTRAIT_GLOW_ALPHA = 0.45

    local TAG_STYLES = {
        default = { fill = GC.transparent, border = GC.tagBorder, text = GC.tagText },
        accent = { fill = GC.tagSelected, border = GC.tagSelectedBorder, text = GC.accent },
    }

    local function StyleText(region, size, color)
        MODERN.Font(region, size, color)
        region:SetJustifyH("LEFT")
        region:SetJustifyV("TOP")
        region:SetWordWrap(true)
    end

    local function TagParts(tag)
        if type(tag) == "table" then return tag.text, tag.style or "default" end
        return tag, "default"
    end

    local function FirstCharacter(text)
        return text:match("^[\1-\127\194-\244][\128-\191]*")
    end

    local function CountCharacters(text)
        return select(2, text:gsub("[^\128-\191]", ""))
    end

    local function ValidateOptions(opts)
        assert(type(opts) == "table" and type(opts.people) == "table", "PersonCards: opts.people must be an array")
        assert(opts.compact == nil or type(opts.compact) == "boolean", "PersonCards: opts.compact must be a boolean")
        assert(opts.surface == nil or opts.surface == "card" or opts.surface == "plain",
            "PersonCards: opts.surface must be card or plain")
        assert(opts.showAvatar == nil or type(opts.showAvatar) == "boolean",
            "PersonCards: opts.showAvatar must be a boolean")
        assert(opts.showAvatar ~= false or opts.layout == "chip",
            "PersonCards: showAvatar = false only applies to layout = chip")
        assert(opts.layout == nil or opts.layout == "row" or opts.layout == "portrait" or opts.layout == "chip",
            "PersonCards: opts.layout must be row, portrait or chip")
        assert(not (opts.compact and (opts.layout == "portrait" or opts.layout == "chip")),
            "PersonCards: compact cannot be combined with portrait or chip")
        assert(opts.avatarRing == nil or (opts.layout == "portrait" and type(opts.avatarRing) == "table"
            and type(opts.avatarRing.texture) == "string" and type(opts.avatarRing.texCoords) == "table"
            and #opts.avatarRing.texCoords == 4), "PersonCards: avatarRing requires texture and four texCoords")
        assert(opts.avatarStyle == nil or (opts.avatarStyle == "icon" and opts.layout == "portrait"),
            "PersonCards: avatarStyle = icon only applies to portrait layout")
        assert(opts.avatarSize == nil or (opts.layout == "portrait" and type(opts.avatarSize) == "number"
            and opts.avatarSize > 0 and opts.avatarSize < math.huge),
            "PersonCards: avatarSize must be a finite positive number for portrait layout")
        local chip = opts.layout == "chip"
        if not chip then
            assert(type(opts.columns) == "number" and opts.columns >= 1, "PersonCards: opts.columns must be a number >= 1")
            assert(type(opts.minColumnWidth) == "number" and opts.minColumnWidth > 0,
                "PersonCards: opts.minColumnWidth must be a positive number")
        end
        for _, field in ipairs({ "columnGap", "rowGap", "padX", "padTop", "padBottom" }) do
            assert(opts[field] == nil or (type(opts[field]) == "number" and opts[field] >= 0),
                "PersonCards: opts." .. field .. " must be a number >= 0")
        end
        for index, person in ipairs(opts.people) do
            local at = "PersonCards: people[" .. index .. "]"
            assert(type(person) == "table", at .. " must be a table")
            assert(type(person.name) == "string" and person.name ~= "", at .. ".name must be a non-empty string")
            for _, field in ipairs({ "description", "avatar", "url" }) do
                assert(person[field] == nil or (type(person[field]) == "string" and person[field] ~= ""),
                    at .. "." .. field .. " must be a non-empty string")
            end
            assert(person.badge == nil or (type(person.badge) == "table" and type(person.badge.icon) == "string"
                and person.badge.icon ~= "" and type(person.badge.color) == "table"),
                at .. ".badge must be { icon = path, color = { r, g, b, a } }")
            assert(not person.badge or person.badge.style == nil or person.badge.style == "icon",
                at .. ".badge.style must be icon or nil")
            if chip then
                assert(person.description == nil and person.url == nil and person.tags == nil and person.badge == nil,
                    at .. ": chip layout shows only avatar and name")
            end
            assert(person.tags == nil or type(person.tags) == "table", at .. ".tags must be an array")
            for tagIndex, tag in ipairs(person.tags or {}) do
                local text, style = TagParts(tag)
                assert(type(text) == "string" and text ~= "", at .. ".tags[" .. tagIndex .. "] needs text")
                assert(TAG_STYLES[style], at .. ".tags[" .. tagIndex .. "].style must be default or accent")
            end
        end
    end

    local function ResolveColumns(width, opts)
        local gap = opts.columnGap or DEFAULT_GRID_GAP
        local fit = math.max(1, math.floor((width + gap) / (opts.minColumnWidth + gap)))
        return math.min(math.floor(opts.columns), fit), gap
    end

    -- Grid 的 measure 合同要求不创建 Frame，这里只按字数粗估首次高度；
    -- 真实高度由 layout 量出后经 ctx:SetContentHeight 上报。
    local function EstimatePortraitHeight(person, width, m)
        local inner = math.max(1, width - m.pad * 2)
        local height = m.pad + m.avatar + PORTRAIT_RING * 2 + GAP + math.ceil(m.nameFont * 1.25)
        if person.tags and #person.tags > 0 then
            local used = 0
            for _, tag in ipairs(person.tags) do
                used = used + CountCharacters((TagParts(tag))) * TAG_FONT + TAG_PAD_X * 2 + GAP
            end
            local rows = math.ceil(used / inner)
            height = height + GAP + rows * TAG_HEIGHT + (rows - 1) * GAP
        end
        if person.description then
            height = height + GAP + math.ceil(CountCharacters(person.description) * m.descFont / inner)
                * math.ceil(m.descFont * 1.25)
        end
        if person.url then height = height + GAP + URL_HEIGHT end
        return height + m.pad
    end

    local function EstimateCardHeight(person, width, m)
        if m.portrait then return EstimatePortraitHeight(person, width, m) end
        local inner = width - m.pad * 2
        local textWidth = math.max(1, inner - m.avatar - DEFAULT_GRID_GAP)
        local tagsHeight = 0
        if person.tags and #person.tags > 0 then
            local used = 0
            for _, tag in ipairs(person.tags) do
                used = used + CountCharacters((TagParts(tag))) * TAG_FONT + TAG_PAD_X * 2 + GAP
            end
            local rows = math.ceil(used / textWidth)
            tagsHeight = rows * TAG_HEIGHT + (rows - 1) * GAP
        end
        local height = m.pad * 2 + math.max(m.avatar, m.nameFont + (tagsHeight > 0 and GAP + tagsHeight or 0))
        if person.description then
            height = height + GAP + math.ceil(CountCharacters(person.description) * m.descFont / inner) * m.descFont
        end
        if person.url and m.url then height = height + GAP + URL_HEIGHT end
        return height
    end

    -- 胶囊的宽高：左右留白 + 头像 + 间距 + 名字宽（右侧多留一份留白，视觉居中）。
    local function ChipWidth(m, nameWidth)
        if m.noAvatar then return m.pad * 2 + nameWidth end
        return m.pad * 3 + m.avatar + GAP + nameWidth
    end
    local function ChipHeight(m)
        if m.noAvatar then return math.ceil(m.nameFont * 1.25) + m.pad * 2 end
        return m.avatar + m.pad * 2
    end

    -- 粗估名字宽度：单字节字符按半个字号，多字节（中日韩）按一个字号。
    local function EstimateNameWidth(text, fontSize)
        local wide = select(2, text:gsub("[\194-\244]", ""))
        -- 乘一点余量：measure 只能粗估，估窄了会少算一行，后面的内容会被压到胶囊上。
        return math.ceil(((CountCharacters(text) - wide) * fontSize * 0.55 + wide * fontSize) * 1.08)
    end

    -- 胶囊按行流式排列；measure 与 layout 共用这一换行规则。
    local function FlowRows(widths, available, gap)
        local rows, x = 0, 0
        for _, itemWidth in ipairs(widths) do
            if rows == 0 or (x > 0 and x + gap + itemWidth > available) then
                rows, x = rows + 1, itemWidth
            else
                x = x + gap + itemWidth
            end
        end
        return rows
    end

    local function EstimateHeight(outerWidth, opts)
        ValidateOptions(opts)
        local padX = opts.padX or 0
        local width = outerWidth - padX * 2
        if opts.layout == "chip" then
            local m, widths = MetricsFor(opts), {}
            for index, person in ipairs(opts.people) do
                widths[index] = ChipWidth(m, EstimateNameWidth(person.name, m.nameFont))
            end
            local rowGap = opts.rowGap or DEFAULT_GRID_GAP
            local rows = FlowRows(widths, width, opts.columnGap or DEFAULT_GRID_GAP)
            return math.max(1, rows * ChipHeight(m) + math.max(0, rows - 1) * rowGap
                + (opts.padTop or 0) + (opts.padBottom or 0))
        end
        local columns, gap = ResolveColumns(width, opts)
        local cardWidth = (width - gap * (columns - 1)) / columns
        local total, rowHeight = 0, 0
        for index, person in ipairs(opts.people) do
            rowHeight = math.max(rowHeight, EstimateCardHeight(person, cardWidth, MetricsFor(opts)))
            if index % columns == 0 or index == #opts.people then
                total, rowHeight = total + rowHeight + (opts.rowGap or DEFAULT_GRID_GAP), 0
            end
        end
        return math.max(1, total - (opts.rowGap or DEFAULT_GRID_GAP) + (opts.padTop or 0) + (opts.padBottom or 0))
    end

    Factory:InitPool(PERSON_TAG, "Frame", "BackdropTemplate", function(tag)
        tag.label = EXUI:CreateVisualFontString(tag, _G.EXFONTFRAME, "GameFontHighlightSmall")
        tag.label:SetPoint("CENTER")
        tag.label:SetWordWrap(false)
    end)

    Factory:InitPool(PERSON_CARD, "Frame", "BackdropTemplate", function(card)
        local avatar = CreateFrame("Frame", nil, card, "BackdropTemplate")
        card.avatarFrame = avatar
        card.avatarImage = avatar:CreateTexture(nil, "ARTWORK")
        card.avatarImage:SetPoint("TOPLEFT", avatar, "TOPLEFT", 1, -1)
        card.avatarImage:SetPoint("BOTTOMRIGHT", avatar, "BOTTOMRIGHT", -1, 1)
        -- 竖排圆形头像：外彩环 → 留缝（卡片底色）→ 圆底/遮罩后的图片；横排时全部隐藏。
        card.avatarRing = avatar:CreateTexture(nil, "BACKGROUND", nil, 0)
        card.avatarRing:SetTexture(CIRCLE_TEXTURE)
        card.avatarRing:SetPoint("CENTER")
        card.avatarGap = avatar:CreateTexture(nil, "BACKGROUND", nil, 1)
        card.avatarGap:SetTexture(CIRCLE_TEXTURE)
        card.avatarGap:SetPoint("CENTER")
        card.avatarDisc = avatar:CreateTexture(nil, "BORDER")
        card.avatarDisc:SetTexture(CIRCLE_TEXTURE)
        card.avatarDisc:SetAllPoints(avatar)
        card.avatarMask = avatar:CreateMaskTexture()
        card.avatarMask:SetTexture(CIRCLE_TEXTURE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        card.avatarMask:SetAllPoints(avatar)
        -- 柔光画在卡片填充之上、边框之下（公共表面：填充 BACKGROUND 0，边框 BORDER）。
        card.portraitGlow = card:CreateTexture(nil, "BACKGROUND", nil, 3)
        card.portraitGlow:SetTexture(GLOW_TEXTURE)
        card.portraitGlow:SetBlendMode("ADD")
        -- 平台角标：卡片底色圆（与头像隔开）→ 平台色圆 → 白色图标，压在头像右下角、不受头像遮罩影响。
        card.badgeGap = avatar:CreateTexture(nil, "OVERLAY", nil, 0)
        card.badgeGap:SetTexture(CIRCLE_TEXTURE)
        card.badgeDisc = avatar:CreateTexture(nil, "OVERLAY", nil, 1)
        card.badgeDisc:SetTexture(CIRCLE_TEXTURE)
        card.badgeIcon = avatar:CreateTexture(nil, "OVERLAY", nil, 2)
        for _, region in ipairs({ card.avatarRing, card.avatarGap, card.avatarDisc, card.portraitGlow,
            card.badgeGap, card.badgeDisc, card.badgeIcon }) do region:Hide() end
        card.avatarInitial = EXUI:CreateVisualFontString(avatar, _G.EXFONTFRAME, "GameFontHighlight")
        card.avatarInitial:SetPoint("CENTER")
        card.nameText = EXUI:CreateVisualFontString(card, _G.EXFONTFRAME, "GameFontHighlight")
        card.descText = EXUI:CreateVisualFontString(card, _G.EXFONTFRAME, "GameFontHighlight")
    end)

    -- 只读网址框：点击/聚焦全选，Ctrl+C 复制；任何改动都会被还原。
    -- textRole 可选："urlValue"（默认）或 "urlCompact"（小一号字，供窄卡完整显示网址）。
    function EXUI:CreateCopyableUrlBox(parent, url, width, textRole)
        assert(type(url) == "string" and url ~= "", "CreateCopyableUrlBox: url must be a non-empty string")
        textRole = textRole or "urlValue"
        assert(textRole == "urlValue" or textRole == "urlCompact",
            "CreateCopyableUrlBox: textRole must be urlValue or urlCompact")
        local box = self:CreateEditBox(parent, url, width, URL_HEIGHT, nil, {})
        local edit = box.editBox or box
        edit._exInputTextRole = textRole
        MODERN.ApplyTextRole(edit, textRole)
        edit:SetScript("OnTextChanged", function(self)
            if self:GetText() ~= url then
                self:SetText(url)
                self:HighlightText()
            end
        end)
        -- 焦点槽位里有输入框的焦点画器：连安装记录一起清掉，写完再补装。
        self:ClearControlScript(edit, "OnEditFocusGained")
        edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        edit:SetScript("OnMouseUp", function(self) self:HighlightText() end)
        self:ApplyControlAppearance(box)
        return box
    end

    function EXUI:ReleaseCopyableUrlBox(box)
        local edit = box.editBox or box
        edit._exInputTextRole = nil
        edit:SetScript("OnTextChanged", nil)
        EXUI:ClearControlScript(edit, "OnEditFocusGained")
        edit:SetScript("OnMouseUp", nil)
        edit:ClearFocus()
        Factory:ReleaseGridWidget(box)
    end

    local function BuildTag(card, tagSpec)
        local text, styleName = TagParts(tagSpec)
        local style = TAG_STYLES[styleName]
        local tag = Factory:Acquire(PERSON_TAG, card)
        tag:SetFrameLevel(card:GetFrameLevel() + 1)
        EXUI:SetControlSurface(tag, GM.radius.card, style.fill, style.border)
        MODERN.Font(tag.label, TAG_FONT, style.text)
        tag.label:SetText(text)
        tag:SetHeight(TAG_HEIGHT)
        tag.naturalWidth = math.ceil(tag.label:GetStringWidth()) + TAG_PAD_X * 2
        Factory:AttachPoolRelease(tag, function(self)
            EXUI:ClearControlSurface(self)
            self.label:SetText("")
            self.naturalWidth = nil
        end)
        return tag
    end

    local function BuildCard(host, person, m)
        local card = Factory:Acquire(PERSON_CARD, host)
        card.personMetrics = m
        EXUI:SetControlFontStyle(card, "settings")
        card:SetFrameLevel(host:GetFrameLevel() + 1)
        -- plain：不画卡片底色与边框；头像留缝改用宿主卡片底色。
        local hostFill = m.plain and GC.card or GC.subcard
        if m.plain then
            -- 胶囊靠描边才看得出边界，所以 plain 只去掉底色；卡片则底色与边框一起去掉。
            EXUI:SetControlSurface(card, GM.radius.card, GC.transparent,
                m.chip and GC.tagBorder or GC.transparent)
        else
            EXUI:SetControlSurface(card, GM.radius.card, GC.subcard, GC.subcardBorder)
        end
        local childLevel = card:GetFrameLevel() + 1

        card.avatarFrame:SetFrameLevel(childLevel)
        card.avatarFrame:SetShown(not m.noAvatar)
        card.avatarFrame:SetSize(math.max(1, m.avatar), math.max(1, m.avatar))
        card.avatarImage:ClearAllPoints()
        card.avatarRing:SetTexture(CIRCLE_TEXTURE)
        card.avatarRing:SetTexCoord(0, 1, 0, 1)
        card.avatarMask:SetShown(person.avatar ~= nil and not m.avatarIcon)
        if m.avatarIcon then
            card.avatarRing:Hide()
            card.avatarGap:Hide()
            card.avatarDisc:Hide()
            card.portraitGlow:Hide()
        end
        if m.circle then
            card.avatarImage:SetAllPoints(card.avatarFrame)
            if m.portrait and not m.avatarIcon and not m.avatarRing then
                card.avatarRing:SetSize(m.avatar + PORTRAIT_RING * 2, m.avatar + PORTRAIT_RING * 2)
                card.avatarRing:SetVertexColor(unpack(m.plain and GC.cardBorder or GC.primaryFill))
                card.avatarRing:Show()
                card.avatarGap:SetSize(m.avatar + 2, m.avatar + 2)
                card.avatarGap:SetVertexColor(unpack(hostFill))
                card.avatarGap:Show()
                if not m.plain then
                    local glow = GC.primaryFill
                    card.portraitGlow:SetVertexColor(glow[1], glow[2], glow[3], PORTRAIT_GLOW_ALPHA)
                    card.portraitGlow:Show()
                end
            end
        else
            card.avatarImage:SetPoint("TOPLEFT", card.avatarFrame, "TOPLEFT", 1, -1)
            card.avatarImage:SetPoint("BOTTOMRIGHT", card.avatarFrame, "BOTTOMRIGHT", -1, 1)
        end
        if person.avatar then
            card.avatarImage:SetTexture(person.avatar)
            card.avatarImage:Show()
            card.avatarInitial:Hide()
            if m.circle and not m.avatarIcon then
                card.avatarImage:AddMaskTexture(card.avatarMask)
                card.avatarMasked = true
            elseif not m.avatarIcon then
                EXUI:SetControlSurface(card.avatarFrame, GM.radius.control, GC.input, GC.subcardBorder)
            end
        else
            card.avatarImage:Hide()
            StyleText(card.avatarInitial, m.initialFont, GC.accent)
            card.avatarInitial:SetText(FirstCharacter(person.name))
            card.avatarInitial:Show()
            if m.circle and not m.avatarRing then
                card.avatarDisc:SetVertexColor(unpack(m.plain and GC.transparent or GC.tagSelected))
                card.avatarDisc:Show()
            elseif not m.avatarRing then
                EXUI:SetControlSurface(card.avatarFrame, GM.radius.control, GC.tagSelected, GC.tagSelectedBorder)
            end
        end

        if m.avatarRing then
            card.avatarGap:Hide()
            card.avatarDisc:Hide()
            card.portraitGlow:Hide()
            card.avatarRing:SetTexture(m.avatarRing.texture)
            card.avatarRing:SetTexCoord(unpack(m.avatarRing.texCoords))
            card.avatarRing:SetSize(m.avatar, m.avatar)
            card.avatarRing:SetVertexColor(unpack(m.plain and GC.cardBorder or GC.primaryFill))
            card.avatarRing:Show()
        end

        if person.badge then
            -- 中心落在头像圆周 45° 处：距右下角各内缩半径的 (1 - √2/2) ≈ 0.29。
            local inset = math.floor(m.avatar / 2 * 0.29 + 0.5)
            local color = person.badge.color
            card.badgeGap:SetSize(BADGE_SIZE + 4, BADGE_SIZE + 4)
            card.badgeGap:SetVertexColor(unpack(hostFill))
            card.badgeDisc:SetSize(BADGE_SIZE, BADGE_SIZE)
            card.badgeDisc:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
            card.badgeIcon:SetSize(math.floor(BADGE_SIZE * 0.7), math.floor(BADGE_SIZE * 0.7))
            card.badgeIcon:SetTexture(person.badge.icon)
            if person.badge.texCoords then
                card.badgeIcon:SetTexCoord(unpack(person.badge.texCoords))
            else
                card.badgeIcon:SetTexCoord(0, 1, 0, 1)
            end
            for _, region in ipairs({ card.badgeGap, card.badgeDisc, card.badgeIcon }) do
                region:ClearAllPoints()
                region:SetPoint("CENTER", card.avatarFrame, "BOTTOMRIGHT", -inset, inset)
                region:Show()
            end
            if person.badge.style == "icon" then
                card.badgeGap:Hide()
                card.badgeDisc:Hide()
                card.badgeIcon:SetSize(GM.size.personPlatformIcon, GM.size.personPlatformIcon)
                card.badgeIcon:SetVertexColor(unpack(color))
            else
                card.badgeIcon:SetVertexColor(1, 1, 1, 1)
            end
        end

        StyleText(card.nameText, m.nameFont, GC.white)
        if m.chip then card.nameText:SetWordWrap(false) end
        card.nameText:SetText(person.name)
        card.descText:SetShown(person.description ~= nil)
        if person.description then
            StyleText(card.descText, m.descFont, GC.textDim)
            card.descText:SetText(person.description)
        end

        card.personTags = {}
        for index, tagSpec in ipairs(person.tags or {}) do
            card.personTags[index] = BuildTag(card, tagSpec)
        end
        card.personUrlBox = nil
        if person.url and m.url then
            card.personUrlBox = EXUI:CreateCopyableUrlBox(card, person.url, 1, m.portrait and "urlCompact" or nil)
            card.personUrlBox:SetFrameLevel(childLevel)
        end

        Factory:AttachPoolRelease(card, function(self)
            for index = #self.personTags, 1, -1 do Factory:Release(PERSON_TAG, self.personTags[index]) end
            self.personTags = nil
            self.personMetrics = nil
            if self.personUrlBox then
                EXUI:ReleaseCopyableUrlBox(self.personUrlBox)
                self.personUrlBox = nil
            end
            if self.avatarMasked then
                self.avatarImage:RemoveMaskTexture(self.avatarMask)
                self.avatarMasked = nil
            end
            self.avatarFrame:Show()
            self.avatarRing:Hide()
            self.avatarGap:Hide()
            self.avatarDisc:Hide()
            self.portraitGlow:Hide()
            self.badgeGap:Hide()
            self.badgeDisc:Hide()
            self.badgeIcon:SetTexture(nil)
            self.badgeIcon:SetVertexColor(1, 1, 1, 1)
            self.badgeIcon:Hide()
            self.avatarImage:SetTexture(nil)
            self.avatarInitial:SetText("")
            self.nameText:SetText("")
            self.descText:SetText("")
            EXUI:ClearControlSurface(self.avatarFrame)
            EXUI:ClearControlSurface(self)
        end)
        return card
    end

    -- 竖排：头像居中在上，名称、标签（按行居中）、描述依次居中，网址框贴底。
    local function LayoutPortraitCard(card, width)
        local m = card.personMetrics
        local inner = math.max(1, width - m.pad * 2)
        local y = m.pad + PORTRAIT_RING

        card.avatarFrame:ClearAllPoints()
        card.avatarFrame:SetPoint("TOP", card, "TOP", 0, -y)
        -- 柔光以头像为中心，上下不超出卡片顶边，左右留出圆角边框的 2px。
        local glowHalf = y + math.floor(m.avatar / 2) - 2
        card.portraitGlow:ClearAllPoints()
        card.portraitGlow:SetPoint("CENTER", card.avatarFrame, "CENTER", 0, 0)
        card.portraitGlow:SetSize(math.max(1, width - 4), glowHalf * 2)
        y = y + m.avatar + PORTRAIT_RING + GAP

        card.nameText:SetJustifyH("CENTER")
        card.nameText:SetWidth(inner)
        card.nameText:ClearAllPoints()
        card.nameText:SetPoint("TOPLEFT", card, "TOPLEFT", m.pad, -y)
        y = y + math.ceil(card.nameText:GetStringHeight())

        local tags = card.personTags
        if #tags > 0 then
            y = y + GAP
            local first = 1
            while first <= #tags do
                local rowWidth, last = 0, first
                for index = first, #tags do
                    local tagWidth = math.min(tags[index].naturalWidth, inner)
                    local nextWidth = rowWidth + (index > first and GAP or 0) + tagWidth
                    if index > first and nextWidth > inner then break end
                    rowWidth, last = nextWidth, index
                end
                local x = m.pad + math.floor((inner - rowWidth) / 2)
                for index = first, last do
                    local tag = tags[index]
                    local tagWidth = math.min(tag.naturalWidth, inner)
                    tag:SetWidth(tagWidth)
                    tag:ClearAllPoints()
                    tag:SetPoint("TOPLEFT", card, "TOPLEFT", x, -y)
                    x = x + tagWidth + GAP
                end
                y, first = y + TAG_HEIGHT + (last < #tags and GAP or 0), last + 1
            end
        end

        if card.descText:IsShown() then
            y = y + GAP
            card.descText:SetJustifyH("CENTER")
            card.descText:SetWidth(inner)
            card.descText:ClearAllPoints()
            card.descText:SetPoint("TOPLEFT", card, "TOPLEFT", m.pad, -y)
            y = y + math.ceil(card.descText:GetStringHeight())
        end
        if card.personUrlBox then
            -- 竖排卡较窄，网址框左右只留 GAP，尽量完整显示网址。
            card.personUrlBox:SetWidth(math.max(1, width - GAP * 2))
            card.personUrlBox:ClearAllPoints()
            card.personUrlBox:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", GAP, m.pad)
            y = y + GAP + URL_HEIGHT
        end
        return y + m.pad
    end

    -- 胶囊：头像在左垂直居中，名字单行紧随其后；返回按名字实际宽度算出的宽高。
    local function LayoutChipCard(card)
        local m = card.personMetrics
        local nameWidth = math.ceil(card.nameText:GetUnboundedStringWidth())
        local height = ChipHeight(m)
        card.avatarFrame:ClearAllPoints()
        card.avatarFrame:SetPoint("LEFT", card, "LEFT", m.pad, 0)
        card.nameText:SetWidth(nameWidth + 1)
        card.nameText:ClearAllPoints()
        card.nameText:SetPoint("LEFT", card, "LEFT", m.noAvatar and m.pad or (m.pad + m.avatar + GAP), 0)
        return ChipWidth(m, nameWidth), height
    end

    -- 按给定宽度排好卡片内部，返回自然高度；URL 框贴底，行内等高后仍然对齐。
    local function LayoutCard(card, width)
        local m = card.personMetrics
        if m.portrait then return LayoutPortraitCard(card, width) end
        local inner = width - m.pad * 2
        local textX = m.pad + m.avatar + DEFAULT_GRID_GAP
        local textWidth = math.max(1, width - textX - m.pad)

        card.avatarFrame:ClearAllPoints()
        card.avatarFrame:SetPoint("TOPLEFT", card, "TOPLEFT", m.pad, -m.pad)

        card.nameText:SetWidth(textWidth)
        local nameHeight = math.ceil(card.nameText:GetStringHeight())
        local tags = card.personTags
        local nameTop = m.pad
        if #tags == 0 then nameTop = m.pad + math.max(0, math.floor((m.avatar - nameHeight) / 2)) end
        card.nameText:ClearAllPoints()
        card.nameText:SetPoint("TOPLEFT", card, "TOPLEFT", textX, -nameTop)

        local tagsHeight = 0
        if #tags > 0 then
            local cursorX, cursorY = 0, 0
            for _, tag in ipairs(tags) do
                local tagWidth = math.min(tag.naturalWidth, textWidth)
                if cursorX > 0 and cursorX + tagWidth > textWidth then
                    cursorX, cursorY = 0, cursorY + TAG_HEIGHT + GAP
                end
                tag:SetWidth(tagWidth)
                tag:ClearAllPoints()
                tag:SetPoint("TOPLEFT", card, "TOPLEFT", textX + cursorX, -(m.pad + nameHeight + GAP + cursorY))
                cursorX = cursorX + tagWidth + GAP
            end
            tagsHeight = cursorY + TAG_HEIGHT
        end

        local height = m.pad + math.max(m.avatar, nameHeight + (tagsHeight > 0 and GAP + tagsHeight or 0))
        if card.descText:IsShown() then
            card.descText:SetWidth(inner)
            card.descText:ClearAllPoints()
            card.descText:SetPoint("TOPLEFT", card, "TOPLEFT", m.pad, -(height + GAP))
            height = height + GAP + math.ceil(card.descText:GetStringHeight())
        end
        if card.personUrlBox then
            card.personUrlBox:SetWidth(inner)
            card.personUrlBox:ClearAllPoints()
            card.personUrlBox:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", m.pad, m.pad)
            height = height + GAP + URL_HEIGHT
        end
        return height + m.pad
    end

    -- opts.padX / padTop / padBottom：卡片组自身的内边距（放进外层卡片时使用，默认 0）。
    local function LayoutAll(host, outerWidth)
        local opts, cards = host.personOpts, host.personCards
        local padX, padTop, padBottom = opts.padX or 0, opts.padTop or 0, opts.padBottom or 0
        local width = outerWidth - padX * 2
        if opts.layout == "chip" then
            local gap, rowGap = opts.columnGap or DEFAULT_GRID_GAP, opts.rowGap or DEFAULT_GRID_GAP
            local x, y, rowHeight = 0, padTop, 0
            for _, card in ipairs(cards) do
                local chipWidth, chipHeight = LayoutChipCard(card)
                chipWidth = math.min(chipWidth, width)
                if x > 0 and x + chipWidth > width then
                    x, y = 0, y + rowHeight + rowGap
                end
                card:SetSize(chipWidth, chipHeight)
                card:ClearAllPoints()
                card:SetPoint("TOPLEFT", host, "TOPLEFT", padX + x, -y)
                x, rowHeight = x + chipWidth + gap, chipHeight
            end
            return math.max(0, y + rowHeight + padBottom)
        end
        local columns, gap = ResolveColumns(width, opts)
        local rowGap = opts.rowGap or DEFAULT_GRID_GAP
        local cardWidth = math.floor((width - gap * (columns - 1)) / columns)
        local y, first = padTop, 1
        while first <= #cards do
            local last = math.min(first + columns - 1, #cards)
            local rowHeight = 0
            for index = first, last do
                rowHeight = math.max(rowHeight, LayoutCard(cards[index], cardWidth))
            end
            for index = first, last do
                local card = cards[index]
                card:SetSize(cardWidth, rowHeight)
                card:ClearAllPoints()
                card:SetPoint("TOPLEFT", host, "TOPLEFT", padX + (index - first) * (cardWidth + gap), -y)
            end
            y, first = y + rowHeight + rowGap, last + 1
        end
        return math.max(0, y - rowGap + padBottom)
    end

    EXUI.PersonCardsRenderer = {
        measure = function(pixelWidth, opts)
            return EstimateHeight(pixelWidth, opts)
        end,
        mount = function(host, ctx)
            local opts = ctx.element.opts
            ValidateOptions(opts)
            host.personOpts = opts
            host.personCards = {}
            for index, person in ipairs(opts.people) do
                host.personCards[index] = BuildCard(host, person, MetricsFor(opts))
            end
        end,
        layout = function(host, ctx, layoutWidth)
            local height = LayoutAll(host, math.max(1, tonumber(layoutWidth) or ctx:GetContentWidth()))
            ctx:SetContentHeight(height)
            return height
        end,
        update = function(host)
            local width = host:GetWidth()
            if width > 1 then LayoutAll(host, width) end
        end,
        release = function(host)
            for index = #(host.personCards or {}), 1, -1 do
                Factory:Release(PERSON_CARD, host.personCards[index])
            end
            host.personCards, host.personOpts = nil, nil
        end,
    }
end

-- =========================================================
-- 贴行提示：贴在某个控件 / 行下方的就地提示（右下角浮动提示见 ShowStatusToast）。
-- EXUI:ShowInlineNotice(anchor, text, opts) -> notice
--   anchor：贴靠的控件或行；提示在它下方左对齐，下方放不下放上方，左右夹在屏幕内；anchor 移动会跟着走，anchor 隐藏时提示自动收起。
--   opts = { kind = "info" | "warn" | "error"（默认 info）, duration = 秒（默认 info 3 / warn 4 / error 5；0 = 不自动消失）,
--            width = 宽（可选；默认取 anchor 宽，最窄 GM.size.inlineNoticeMinWidth） }
--            dragAnywhere = true（可选）：提示可拖（可拖出屏幕），拖过就留在拖到的位置、不再跟 anchor；点一下（没拖）仍收起
--   同一个 anchor 再调用时替换原来那条。点一下提示即收起。
-- EXUI:HideInlineNotice(anchorOrNotice)：提前收起。
-- 颜色照状态提示（statusXxxTint / Border / Fg），字号照页内提示条（GM.settings.parts.noticeFont）。
-- =========================================================
do
    local INLINE_TONES = { info = "Info", warn = "Warn", error = "Err" }
    local INLINE_ICONS = { info = "statusinfo", warn = CONTEXT_ICON_ROOT .. "warning.tga", error = "statuserror" }
    local INLINE_DURATION = { info = 3, warn = 4, error = 5 }
    local FADE = 0.15

    local function ToParentUnits(anchor)
        return anchor:GetEffectiveScale() / UIParent:GetEffectiveScale()
    end

    local function PlaceInlineNotice(notice)
        local anchor = notice._anchor
        local scale = ToParentUnits(anchor)
        local left, bottom, top = anchor:GetLeft(), anchor:GetBottom(), anchor:GetTop()
        local gap, margin = GM.space.inlineNoticeGap, GM.space.inlineNoticeScreenMargin
        if not left then
            notice:ClearAllPoints()
            notice:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -gap)
            return
        end
        left, bottom, top = left * scale, bottom * scale, top * scale
        if notice._placedLeft == left and notice._placedBottom == bottom and notice._placedTop == top then return end
        notice._placedLeft, notice._placedBottom, notice._placedTop = left, bottom, top
        local width, height = notice:GetWidth(), notice:GetHeight()
        local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
        local x = math.max(margin, math.min(left, screenWidth - margin - width))
        notice:ClearAllPoints()
        if bottom - gap - height < margin and top + gap + height <= screenHeight - margin then
            notice:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, top + gap)
        else
            notice:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, math.max(margin + height, bottom - gap))
        end
    end

    local function NewInlineNotice()
        local notice = CreateFrame("Frame", nil, UIParent)
        notice:SetFrameStrata("FULLSCREEN_DIALOG")
        notice:SetFrameLevel(9200)
        notice:EnableMouse(true)
        notice.icon = CreateFrame("Frame", nil, notice)
        notice.icon:SetSize(GM.size.statusIconSize, GM.size.statusIconSize)
        notice.text = FeedbackText(notice, GM.settings.parts.noticeFont, FeedbackColors().statusDesc, "")
        notice.text:SetJustifyV("TOP")
        notice.text:SetWordWrap(true)
        return notice
    end

    local function InlineNoticeClick(self) EXUI:HideInlineNotice(self) end
    local function InlineNoticePress(self) self._pressMoved = nil end
    local function InlineNoticeRelease(self) if not self._pressMoved then EXUI:HideInlineNotice(self) end end
    local INLINE_DRAG = { onDragStart = function(notice) notice._dragged, notice._pressMoved = true, true end }

    local function InlineNoticeUpdate(self, elapsed)
        local anchor = self._anchor
        if not anchor:IsVisible() then EXUI:HideInlineNotice(self) return end
        if not self._dragged then PlaceInlineNotice(self) end
        self._life = self._life + elapsed
        local duration = self._duration
        if self._life < FADE then
            self:SetAlpha(self._life / FADE)
        elseif duration > 0 and self._life >= duration + FADE then
            EXUI:HideInlineNotice(self)
        elseif duration > 0 and self._life >= duration then
            self:SetAlpha(1 - (self._life - duration) / FADE)
        else
            self:SetAlpha(1)
        end
    end

    function EXUI:ShowInlineNotice(anchor, text, opts)
        opts = opts or {}
        local kind = opts.kind or "info"
        local tone = INLINE_TONES[kind]
        if not tone then error("ShowInlineNotice: kind must be info, warn or error", 2) end
        if type(anchor) ~= "table" or not anchor.GetEffectiveScale then error("ShowInlineNotice: anchor must be a frame", 2) end
        if opts.dragAnywhere ~= nil and type(opts.dragAnywhere) ~= "boolean" then error("ShowInlineNotice: dragAnywhere must be boolean", 2) end
        self._inlineNotices = self._inlineNotices or {}
        self._inlineNoticePool = self._inlineNoticePool or {}
        local notice = self._inlineNotices[anchor] or table.remove(self._inlineNoticePool) or NewInlineNotice()
        self._inlineNotices[anchor] = notice
        notice._anchor = anchor
        notice._inactive = nil
        notice._dragged, notice._pressMoved = nil, nil
        if opts.dragAnywhere then
            -- 可拖：按下拖动不收起，松开时这一按没拖过才收起；拖过就留在拖到的位置，不再跟着 anchor。
            notice:SetMovable(true)
            EXUI:SetDragAnywhere(notice, INLINE_DRAG)
            notice:SetScript("OnMouseDown", InlineNoticePress)
            notice:SetScript("OnMouseUp", InlineNoticeRelease)
        else
            EXUI:SetDragAnywhere(notice, nil)
            notice:SetScript("OnMouseDown", InlineNoticeClick)
            notice:SetScript("OnMouseUp", nil)
        end
        local c = FeedbackColors()
        local fg, border, tint = c["status" .. tone .. "Fg"], c["status" .. tone .. "Border"], c["status" .. tone .. "Tint"]
        local base, alpha = c.toast, tint[4] or 1
        local fill = { base[1] * (1 - alpha) + tint[1] * alpha, base[2] * (1 - alpha) + tint[2] * alpha,
            base[3] * (1 - alpha) + tint[3] * alpha, 1 }
        EXUI:SetControlSurface(notice, GM.radius.control, fill, border)
        SetContextGlyph(notice.icon, INLINE_ICONS[kind], fg)
        notice.text:SetTextColor(unpack(self.ControlAppearance.colors.text))
        notice.text:SetText(text or "")
        -- 尺寸：宽取 opts.width 或 anchor 宽（换算到 UIParent），夹在最窄和屏幕宽之间；高按文字折行。
        local padX, padY = GM.space.inlineNoticePaddingX, GM.space.inlineNoticePaddingY
        local iconSize, iconGap = GM.size.statusIconSize, GM.space.inlineNoticeIconGap
        local margin = GM.space.inlineNoticeScreenMargin
        local width = opts.width or (anchor:GetWidth() * ToParentUnits(anchor))
        width = math.min(math.max(width, GM.size.inlineNoticeMinWidth), UIParent:GetWidth() - margin * 2)
        local textWidth = math.max(1, width - padX * 2 - iconSize - iconGap)
        notice.text:ClearAllPoints()
        notice.text:SetPoint("TOPLEFT", notice, "TOPLEFT", padX + iconSize + iconGap, -padY)
        notice.text:SetWidth(textWidth)
        notice.icon:ClearAllPoints()
        -- 16px 图标比 13 号字高，上移 1px 与首行对中。
        notice.icon:SetPoint("TOPLEFT", notice, "TOPLEFT", padX, -(padY - 1))
        notice:SetSize(width, math.max(iconSize, math.ceil(notice.text:GetStringHeight())) + padY * 2)
        notice._placedLeft, notice._placedBottom, notice._placedTop = nil, nil, nil
        notice._duration = opts.duration or INLINE_DURATION[kind]
        notice._life = 0
        notice:SetAlpha(0)
        PlaceInlineNotice(notice)
        notice:Show()
        notice:SetScript("OnUpdate", InlineNoticeUpdate)
        return notice
    end

    function EXUI:HideInlineNotice(target)
        local list = self._inlineNotices
        if not list or not target then return end
        local notice = list[target] or (target._anchor and list[target._anchor] == target and target) or nil
        if not notice or notice._inactive then return end
        notice._inactive = true
        notice:SetScript("OnUpdate", nil)
        EXUI:SetDragAnywhere(notice, nil)
        notice:Hide()
        list[notice._anchor] = nil
        notice._anchor = nil
        self._inlineNoticePool[#self._inlineNoticePool + 1] = notice
    end
end
