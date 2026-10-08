-- =========================================================
-- ExwindGUITree.lua: 树控件 EXUI:CreateTree。
-- 缩进、折叠箭头、图标、左侧徽标、右侧状态文字与数量胶囊、行内三态勾选（CreateTriStateCheckbox）、
-- 选中/悬停/容器底色、点击修饰键信息、拖放源与落点回调。
-- 新增文件理由：树是自带滚动区、行对象池与拖放状态的独立控件族（约 500 行）；ExwindGUI.lua 与
-- ExwindGUIComposite.lua 已分别接近 6000 与 5000 行，ExwindChoiceGroup.lua 只管 Tab/选项组，
-- 都不适合再塞入。本文件依赖 ExwindGUI.lua（CreateTriStateCheckbox / CreateScrollFrame / ControlAppearance）
-- 与 ExwindFramePool.lua，在 TOC 中紧跟 ExwindChoiceGroup.lua 加载。
-- 控件只画外观并转发事件：选中集合、展开状态、Ctrl/Shift 多选逻辑、数据移动都归使用方。
-- =========================================================
local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI
local Factory = _G.ExwindFactory
local GC = ExwindTools.GUIColors
local GM = ExwindTools.GUIMetrics
local Appearance = EXUI.ControlAppearance
local MODERN_MEDIA = EXUI._GUIInternal.MODERN_MEDIA

local TREE_POOL = "EXUI.Tree"
local ROW_POOL = "EXUI.TreeRow"
local TRI_STATES = { checked = true, unchecked = true, mixed = true }
-- 落点区域：容器行分上 1/4（之前）、中间（之内）、下 1/4（之后）；非容器行分上下各一半。
local DROP_EDGE = 0.25

-- 折叠箭头资源 GlyphChevron 默认朝下；逆时针转 90 度朝右（Texture:SetRotation 正值为逆时针）。
local FOLD_ROTATION_COLLAPSED = math.pi / 2

local function Modifiers()
    return { ctrl = IsControlKeyDown(), shift = IsShiftKeyDown(), alt = IsAltKeyDown() }
end

-- ---------------------------------------------------------
-- 行
-- ---------------------------------------------------------
local function PaintRow(row)
    local data = row._treeData
    if not data then return end
    local fill
    if data.selected then fill = GC.listSelected
    elseif row._treeHover then fill = GC.rowHover
    elseif data.container then fill = GC.subcard end
    -- 选中/悬停底色是半透明色，边框用透明，避免边缘叠两层 alpha。
    if fill then EXUI:SetControlSurface(row, GM.radius.control, fill, GC.transparent)
    else EXUI:ClearControlSurface(row) end
    row._treeName:SetTextColor(unpack(data.selected and GC.selectedText or GC.text))
    row._treeFoldIcon:SetVertexColor(unpack(row._treeHover and GC.text or GC.textDim))
end

local function ReleaseRowCheck(row)
    local check = row._treeCheck
    if not check then return end
    row._treeCheck = nil
    check.checkbox._exTreeCheckRow = nil
    Factory:Release(check._fromPool, check)
end

-- 每个池化行只建一次。主脚本会被池的标准重置清掉，所以事件用 HookScript 一次性挂上，
-- 回调只读行字段（_treeOwner / _treeData），归还后字段为 nil，钩子自然失效。
local function BuildRow(row)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:RegisterForDrag("LeftButton")

    local fold = CreateFrame("Button", nil, row)
    fold:RegisterForClicks("LeftButtonUp")
    local foldIcon = fold:CreateTexture(nil, "OVERLAY")
    foldIcon:SetTexture(MODERN_MEDIA .. "GlyphChevron.tga", "CLAMP", "CLAMP", "LINEAR")
    foldIcon:SetSize(GM.size.treeFoldSize, GM.size.treeFoldSize)
    foldIcon:SetPoint("CENTER", fold, "CENTER", 0, 0)
    fold:SetScript("OnClick", function()
        local owner, data = row._treeOwner, row._treeData
        local callback = owner and data and owner._treeOptions.onToggle
        if callback then callback(data.id, owner) end
    end)
    row._treeFold, row._treeFoldIcon = fold, foldIcon

    local icon = EXUI:CreateVisualTexture(row, EXBASEFRAME)
    icon:SetSize(GM.size.treeIconSize, GM.size.treeIconSize)
    row._treeIcon = icon

    local badge = CreateFrame("Frame", nil, row)
    badge:SetSize(GM.size.treeBadgeSize, GM.size.treeBadgeSize)
    badge:EnableMouse(false)
    local badgeText = EXUI:CreateVisualFontString(badge, EXFONTFRAME, "GameFontHighlightSmall")
    badgeText:SetPoint("CENTER", badge, "CENTER", 0, 0)
    badgeText:SetJustifyH("CENTER")
    Appearance.ApplyTextRole(badgeText, "control", GC.white)
    row._treeBadge, row._treeBadgeText = badge, badgeText

    local name = EXUI:CreateVisualFontString(row, EXFONTFRAME, "GameFontHighlight")
    name:SetJustifyH("LEFT")
    name:SetJustifyV("MIDDLE")
    name:SetWordWrap(false)
    Appearance.ApplyTextRole(name, "title", GC.text)
    row._treeName = name

    local mark = EXUI:CreateVisualFontString(row, EXFONTFRAME, "GameFontHighlightSmall")
    mark:SetJustifyH("RIGHT")
    mark:SetWordWrap(false)
    Appearance.ApplyTextRole(mark, "control", GC.text)
    row._treeMark = mark

    local pill = CreateFrame("Frame", nil, row)
    pill:SetHeight(GM.size.treePillHeight)
    pill:EnableMouse(false)
    local pillText = EXUI:CreateVisualFontString(pill, EXFONTFRAME, "GameFontHighlightSmall")
    pillText:SetPoint("CENTER", pill, "CENTER", 0, 0)
    pillText:SetJustifyH("CENTER")
    Appearance.ApplyTextRole(pillText, "control", GC.text)
    row._treePill, row._treePillText = pill, pillText

    row:HookScript("OnMouseDown", function(self) self._treeDragged = false end)
    row:HookScript("OnClick", function(self, mouseButton)
        local owner, data = self._treeOwner, self._treeData
        if not owner or not data then return end
        -- 拖放结束时不再当作一次点击。
        if self._treeDragged then self._treeDragged = false; return end
        local callback = owner._treeOptions.onClick
        if callback then callback(data.id, mouseButton, Modifiers(), owner) end
    end)
    row:HookScript("OnEnter", function(self)
        local owner, data = self._treeOwner, self._treeData
        if not owner or not data then return end
        self._treeHover = true
        PaintRow(self)
        local callback = owner._treeOptions.onEnter
        if callback then callback(data.id, self, owner) end
    end)
    row:HookScript("OnLeave", function(self)
        local owner, data = self._treeOwner, self._treeData
        if not owner or not data then return end
        self._treeHover = false
        PaintRow(self)
        local callback = owner._treeOptions.onLeave
        if callback then callback(data.id, self, owner) end
    end)
    row:HookScript("OnDragStart", function(self)
        local owner, data = self._treeOwner, self._treeData
        if not owner or not data then return end
        local callback = owner._treeOptions.onDragStart
        -- 返回 false 否决这次拖动：不记录拖动源，落点回调也就不会触发；
        -- 也不置 _treeDragged，随后的点击照常触发。
        if callback and callback(data.id, owner) == false then return end
        self._treeDragged = true
        owner._treeDragId = data.id
    end)
    row:HookScript("OnDragStop", function(self)
        local owner = self._treeOwner
        if not owner then return end
        local sourceID = owner._treeDragId
        owner._treeDragId = nil
        if sourceID == nil then return end
        local callback = owner._treeOptions.onDrop
        if not callback then return end
        -- 滚动区之外（含滚动条）松手不算落点；行被滚出可视区时 IsMouseOver 不能代表可见。
        if not owner._treeScroll:IsMouseOver() then return end
        for _, candidate in ipairs(owner._treeRows) do
            if candidate:IsShown() and candidate:IsMouseOver() then
                local target = candidate._treeData
                if target.id == sourceID then return end
                local _, cursorY = GetCursorPosition()
                local top, bottom = candidate:GetTop(), candidate:GetBottom()
                local fraction = (top - cursorY / candidate:GetEffectiveScale()) / (top - bottom)
                local zone
                if target.container then
                    zone = fraction < DROP_EDGE and "before" or (fraction > 1 - DROP_EDGE and "after" or "inside")
                else
                    zone = fraction < 0.5 and "before" or "after"
                end
                callback(sourceID, target.id, zone, owner)
                return
            end
        end
        -- 在滚动区内、没有压在任何行上：空白处落点。
        callback(sourceID, nil, "blank", owner)
    end)
end

Factory:InitCompositePool(TREE_POOL)
Factory:InitPool(ROW_POOL, "Button", "BackdropTemplate", BuildRow)

local function AcquireRow(tree)
    local row = Factory:Acquire(ROW_POOL, tree._treeContent)
    -- 池的 Acquire 把按钮重置为只收左键抬起；本控件要收右键。
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row._treeOwner = tree
    row._treeHover, row._treeDragged = false, false
    Factory:AttachPoolRelease(row, function(self)
        ReleaseRowCheck(self)
        self._treeOwner, self._treeData, self._treeHover, self._treeDragged = nil, nil, nil, nil
        self._treeFold:Hide()
        self._treeIcon:SetTexture(nil)
        self._treeIcon:Hide()
        self._treeBadge:Hide()
        self._treePill:Hide()
        self._treeMark:SetText("")
        self._treeName:SetText("")
    end)
    return row
end

local function ReleaseRow(row)
    Factory:Release(row._fromPool, row)
end

local function BindRow(tree, row, index, data)
    row._treeData = data
    local rowHeight = tree._treeRowHeight
    local pad, gap = GM.space.treePadding, GM.space.treeSlotGap
    local y = -(index - 1) * (rowHeight + GM.space.treeRowGap)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", tree._treeContent, "TOPLEFT", data.depth * GM.space.treeIndent, y)
    row:SetPoint("TOPRIGHT", tree._treeContent, "TOPRIGHT", 0, y)
    row:SetHeight(rowHeight)

    -- 左侧：折叠槽（只有容器行预留）、图标、徽标，剩下的给名称。
    local fold = row._treeFold
    local x = pad
    if data.container then
        fold:ClearAllPoints()
        fold:SetPoint("LEFT", row, "LEFT", 0, 0)
        fold:SetSize(pad * 2 + GM.size.treeFoldSize, rowHeight)
        fold:SetShown(data.hasChildren)
        row._treeFoldIcon:SetRotation(data.expanded and 0 or FOLD_ROTATION_COLLAPSED)
        x = pad * 2 + GM.size.treeFoldSize
    else
        fold:Hide()
    end
    local icon = row._treeIcon
    if data.icon ~= nil then
        local coreIcon = type(data.icon) == "string" and ExwindTools.GUIIcons.ids[data.icon] ~= nil
        icon:SetTexture(coreIcon and EXUI:GetIcon(data.icon) or data.icon)
        -- 统一图标库是白色线条贴图，跟随文字色；其它图标（法术/物品）保持原色并裁掉边缘。
        icon:SetTexCoord(unpack(coreIcon and { 0, 1, 0, 1 } or { 0.08, 0.92, 0.08, 0.92 }))
        icon:SetVertexColor(unpack(coreIcon and GC.text or GC.white))
        icon:ClearAllPoints()
        icon:SetPoint("LEFT", row, "LEFT", x, 0)
        icon:Show()
        x = x + GM.size.treeIconSize + gap
    else
        icon:Hide()
    end
    local badge = row._treeBadge
    if data.badge then
        EXUI:SetControlSurface(badge, GM.radius.control, data.badge.color, data.badge.color)
        row._treeBadgeText:SetText(data.badge.text)
        row._treeBadgeText:SetTextColor(unpack(data.badge.textColor or GC.white))
        badge:ClearAllPoints()
        badge:SetPoint("LEFT", row, "LEFT", x, 0)
        badge:Show()
        x = x + GM.size.treeBadgeSize + gap
    else
        badge:Hide()
    end

    -- 右侧从右到左：行内勾选、数量胶囊、状态文字；rx 是下一个元素右边缘相对行右边缘的偏移。
    local rx = -pad
    if data.check ~= nil then
        local check = row._treeCheck
        if not check then
            check = EXUI:CreateTriStateCheckbox(row, "", data.check, function(nextState)
                local owner, current = row._treeOwner, row._treeData
                local callback = owner and current and owner._treeOptions.onCheck
                if callback then callback(current.id, nextState, owner) end
            end)
            row._treeCheck = check
            local box = check.checkbox
            box._exTreeCheckRow = row
            if not box._exTreeCheckHoverHook then
                box._exTreeCheckHoverHook = true
                box:HookScript("OnEnter", function(self)
                    local currentRow = self._exTreeCheckRow
                    local owner = currentRow and currentRow._treeOwner
                    local data = currentRow and currentRow._treeData
                    local callback = owner and owner._treeOptions and owner._treeOptions.onCheckEnter
                    if callback and data then callback(data.id, self, owner) end
                end)
                box:HookScript("OnLeave", function(self)
                    local currentRow = self._exTreeCheckRow
                    local owner = currentRow and currentRow._treeOwner
                    local data = currentRow and currentRow._treeData
                    local callback = owner and owner._treeOptions and owner._treeOptions.onCheckLeave
                    if callback and data then callback(data.id, self, owner) end
                end)
            end
            check:SetFrameLevel(row:GetFrameLevel() + 2)
        end
        check:SetState(data.check)
        check.checkbox:SetEnabled(data.checkEnabled)
        -- 池化勾选框的可点击方框比画出来的方框宽一截；让画出来的方框右缘落在内边距上。
        local frameWidth, frameHeight = check.checkbox:GetSize()
        check:SetSize(frameWidth, frameHeight)
        check:ClearAllPoints()
        check:SetPoint("RIGHT", row, "RIGHT", rx + (frameWidth - GM.size.checkboxBoxSize), 0)
        rx = rx - GM.size.checkboxBoxSize - gap
    else
        ReleaseRowCheck(row)
    end
    local pill = row._treePill
    if data.pill ~= nil then
        row._treePillText:SetText(data.pill)
        local pillWidth = math.max(GM.size.treePillHeight, math.ceil(row._treePillText:GetUnboundedStringWidth()) + pad * 2)
        EXUI:SetControlSurface(pill, GM.radius.control, GC.input, GC.input)
        pill:SetWidth(pillWidth)
        pill:ClearAllPoints()
        pill:SetPoint("RIGHT", row, "RIGHT", rx, 0)
        pill:Show()
        rx = rx - pillWidth - gap
    else
        pill:Hide()
    end
    local mark = row._treeMark
    if data.mark then
        mark:SetText(data.mark.text)
        mark:SetTextColor(unpack(data.mark.color or GC.text))
        local markWidth = math.ceil(mark:GetUnboundedStringWidth())
        mark:SetWidth(markWidth)
        mark:ClearAllPoints()
        mark:SetPoint("RIGHT", row, "RIGHT", rx, 0)
        mark:Show()
        rx = rx - markWidth - gap
    else
        mark:SetText("")
        mark:Hide()
    end

    local name = row._treeName
    name:SetText(data.text)
    name:ClearAllPoints()
    name:SetPoint("LEFT", row, "LEFT", x, 0)
    name:SetPoint("RIGHT", row, "RIGHT", rx, 0)

    -- 行被原地重新绑定后，鼠标可能正压在另一行的数据上：以真实位置重算悬停。
    row._treeHover = tree._treeScroll:IsMouseOver() and row:IsMouseOver() or false
    PaintRow(row)
end

local function CopyColor(value, rowIndex, field)
    if type(value) ~= "table" then
        error(string.format("CreateTree: rows[%d].%s must be a color table {r,g,b,a}", rowIndex, field), 4)
    end
    return value
end

local function CopyRow(row, index, seen)
    if type(row) ~= "table" then
        error(string.format("CreateTree: rows[%d] must be a table", index), 3)
    end
    local id = row.id
    if type(id) ~= "string" and type(id) ~= "number" then
        error(string.format("CreateTree: rows[%d].id must be a string or number", index), 3)
    end
    if seen[id] then error("CreateTree: duplicate row id " .. tostring(id), 3) end
    seen[id] = true
    local depth = row.depth == nil and 0 or row.depth
    if type(depth) ~= "number" or depth < 0 or depth ~= math.floor(depth) then
        error(string.format("CreateTree: rows[%d].depth must be a non-negative integer", index), 3)
    end
    if row.check ~= nil and not TRI_STATES[row.check] then
        error(string.format("CreateTree: rows[%d].check must be checked/unchecked/mixed", index), 3)
    end
    if row.icon ~= nil and type(row.icon) ~= "string" and type(row.icon) ~= "number" then
        error(string.format("CreateTree: rows[%d].icon must be a Core icon id, texture path or file id", index), 3)
    end
    local badge, mark
    if row.badge ~= nil then
        if type(row.badge) ~= "table" then
            error(string.format("CreateTree: rows[%d].badge must be a table", index), 3)
        end
        badge = { text = tostring(row.badge.text or ""), color = CopyColor(row.badge.color, index, "badge.color"),
            textColor = row.badge.textColor }
    end
    if row.mark ~= nil then
        if type(row.mark) ~= "table" then
            error(string.format("CreateTree: rows[%d].mark must be a table", index), 3)
        end
        mark = { text = tostring(row.mark.text or ""), color = row.mark.color }
    end
    return {
        id = id, depth = depth, text = row.text ~= nil and tostring(row.text) or "",
        container = row.container == true, hasChildren = row.hasChildren == true, expanded = row.expanded == true,
        icon = row.icon, badge = badge, mark = mark,
        pill = row.pill ~= nil and tostring(row.pill) or nil,
        check = row.check, checkEnabled = row.checkEnabled ~= false,
        selected = row.selected == true,
    }
end

-- ---------------------------------------------------------
-- 树宿主
-- ---------------------------------------------------------
local function BuildTree(tree)
    local scroll = EXUI:CreateScrollFrame(tree)
    scroll:SetPoint("TOPLEFT", tree, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", tree, "BOTTOMRIGHT", -EXUI.MODERN_SCROLL_FRAME_RIGHT_INSET, 0)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    tree._treeScroll, tree._treeContent = scroll, content
    tree:HookScript("OnSizeChanged", function(self, width)
        self._treeContent:SetWidth(math.max(1, width - EXUI.MODERN_SCROLL_FRAME_RIGHT_INSET))
    end)

    -- rows: 平铺行数组，行的层级用 depth 表示（0 为最外层），顺序就是显示顺序。
    function tree:SetRows(rows)
        if type(rows) ~= "table" then error("Tree:SetRows expects an array of rows", 2) end
        local copied, seen = {}, {}
        for index, row in ipairs(rows) do copied[index] = CopyRow(row, index, seen) end
        local active = self._treeRows
        for index = #active, #copied + 1, -1 do
            ReleaseRow(active[index])
            active[index] = nil
        end
        for index, data in ipairs(copied) do
            local row = active[index]
            if not row then
                row = AcquireRow(self)
                active[index] = row
            end
            BindRow(self, row, index, data)
        end
        self._treeContent:SetHeight(math.max(1, #copied * (self._treeRowHeight + GM.space.treeRowGap)))
    end
    function tree:GetDragId() return self._treeDragId end
    function tree:GetScrollFrame() return self._treeScroll end
    function tree:Release() Factory:ReleaseCompositeHost(self) end
end

-- options（纯数据 + 回调）:
--   rowHeight   可选，行高，默认 GM.size.treeRowHeight
--   onClick(id, mouseButton, modifiers, tree)   点行（左键/右键）；modifiers = { ctrl, shift, alt } 布尔值。
--                                               选中集合与 Ctrl/Shift 多选逻辑由使用方维护，之后用 SetRows 回传 selected。
--   onToggle(id, tree)                          点折叠箭头（展开状态由使用方维护，用 SetRows 回传 expanded）
--   onCheck(id, state, tree)                    点行内勾选框；state 为 "checked" 或 "unchecked"（控件已切到该状态）
--   onCheckEnter(id, checkFrame, tree) / onCheckLeave(id, checkFrame, tree) 勾选框提示锚点
--   onEnter(id, rowFrame, tree) / onLeave(id, rowFrame, tree)   悬停进入/离开（提示条由使用方用 rowFrame 做锚点）
--   onDragStart(id, tree)                       开始拖动；返回 false 否决
--   onDrop(sourceId, targetId, zone, tree)      松手落点：zone = "before" / "inside"（仅容器行）/ "after"；
--                                               在滚动区内但没压在任何行上时 targetId 为 nil、zone 为 "blank"。
--                                               控件不移动数据、不处理批量移动，也不画落点高亮。
-- 行数据（SetRows 的 rows[i]，纯数据）:
--   id（必填，字符串或数字，不可重复）、depth（整数，默认 0）、text、
--   container（容器行：预留折叠槽并用 subcard 底色）、hasChildren（容器行是否显示折叠箭头）、expanded、
--   icon（统一图标库 id、贴图路径或文件 id）、badge = { text, color, textColor? }（左侧彩色方块徽标）、
--   pill（右侧数量胶囊文字）、mark = { text, color? }（右侧状态文字）、
--   check（"checked"/"unchecked"/"mixed"，有值才画行内勾选框）、checkEnabled（默认 true）、selected。
-- 返回池化宿主：SetRows(rows)、GetDragId()、GetScrollFrame()、Release()。
function EXUI:CreateTree(parent, width, height, options)
    options = options or {}
    if type(options) ~= "table" then error("CreateTree: options must be a table", 2) end
    if type(width) ~= "number" or width <= 0 or type(height) ~= "number" or height <= 0 then
        error("CreateTree: width and height must be positive numbers", 2)
    end
    if options.rowHeight ~= nil and (type(options.rowHeight) ~= "number" or options.rowHeight <= 0) then
        error("CreateTree: options.rowHeight must be a positive number", 2)
    end
    for _, key in ipairs({ "onClick", "onToggle", "onCheck", "onCheckEnter", "onCheckLeave", "onEnter", "onLeave", "onDragStart", "onDrop" }) do
        if options[key] ~= nil and type(options[key]) ~= "function" then
            error("CreateTree: options." .. key .. " must be a function", 2)
        end
    end
    local tree, isNew = Factory:AcquireCompositeHost(TREE_POOL, parent)
    if isNew then BuildTree(tree) end
    tree._treeOptions = options
    tree._treeRowHeight = options.rowHeight or GM.size.treeRowHeight
    tree._treeRows = {}
    tree._treeDragId = nil
    tree:SetSize(width, height)
    tree._treeContent:SetWidth(math.max(1, width - EXUI.MODERN_SCROLL_FRAME_RIGHT_INSET))
    tree._treeContent:SetHeight(1)
    tree._treeScroll:SetVerticalScroll(0)
    Factory:AttachPoolRelease(tree, function(self)
        for index = #self._treeRows, 1, -1 do ReleaseRow(self._treeRows[index]) end
        self._treeRows, self._treeOptions, self._treeDragId = nil, nil, nil
    end)
    return tree
end
