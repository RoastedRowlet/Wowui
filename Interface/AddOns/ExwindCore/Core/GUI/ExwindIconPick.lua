-- 图标选取（V2 节点 kind = "iconpick"）：按分组排一组可点的格子（图标、副本卡、首领卡），点了调用 owner 的动作，
-- 选中状态由 owner 给。职业专精、种族、副本、首领这类“从一大张表里挑几个”的面板，和载入页行下的已选图标都用它。
-- 声明：{ id, kind = "iconpick", source = sources 引用名, toggle = actions 引用名, remove = actions 引用名（可选） }。
-- 写了 remove：icon / label / instance / boss 项右上角（带小图标的 label 在小图标右上角）有删除小叉，同法术芯片角上的删除叉
-- （chipCornerRemoveSize），鼠标移到这一项上才显示，点叉调用 actions[remove](context, 项)；没写不出叉。
-- sources[source](scope) 返回分组数组，每组：
--   { title = 小标题（可选）, head = 一项 label（可选，代替 title：点它通常 = 这一组全选 / 全取消）,
--     pack = nil（占满整行）| "split"（相邻的 split 组平分一行）| "flow"（相邻的 flow 组按宽度自动排成几栏）
--            | "side"（左边一列，按自然宽；紧跟的下一组放在它右边占满剩下的宽：例如左边副本列表、右边当前副本的首领）,
--     rows = { 行, ... } }
--   行 = { items = { 项, ... } }（从左到右排，放不下换行）| { items, grid = 最多几列 }（等分格，最宽的一项放不下时少几列）
--        | { items, grid, lines = 可见几行 }（高固定为 lines 行，超出在格子区里上下滚动，不随项数变高）
--        | { items, wrap = 一行最多几项 }（从左到右排，到数或放不下就换行）| { divider = true }（横线）
--   项 = { kind = "icon" | "instance" | "boss" | "label" | "nav" | "sep" | "more", tip = 悬停说明（可选，"\n" 分行，第一行是标题）,
--          selected = true | false | "part"（"part" = 部分选中，只有 label 用） }，按种类再带：
--     icon = 方格图标：icon = 材质文件 ID 或 atlas = 图集名；crop = 四边各裁掉的比例（可选，0～.5）；
--            coords = { 左, 右, 上, 下 }（可选，先取这块再裁）；portrait = true（可选，首领头像这类 2:1 透明底图：取中间方形，垫深色底）；
--            small = true（可选，用小号边长：载入页行下的已选图标）；plain = true（可选，只显示、不画选中状态，一直是原色）。
--     instance = 副本卡：icon = 冒险手册副本按钮图（材质文件 ID），coords 同上，text = 名字（画在图下面）。
--     boss = 首领卡（同 EXBoss 首领页的首领卡）：左边 3D 头像（displayID = 生物显示 ID，可选，没有就写“无动态头像”），
--            右边 text = 名字，名字下 badge = 小牌文字（首领战 ID）。
--     label = 分组标题：icon / atlas（可选的小图标）+ text；selected 为 true 时文字用正文色；
--             large = true（可选，图标用格子边长，同 icon 格子一样大）。
--     nav = 侧栏导航项：text（icon / atlas 可选），选中、悬停同 Core 树行（公共选中外观 UI:PaintSelectRow、悬停抬底）。
--     sep = 竖分隔线（不能点）；more = 小号方块里写 text（例如“…”：已选太多，后面的不再列出，悬停看全部）。
--   icon / instance / boss 是同一种选中样式：没选的去色压暗，选中的恢复原色 + 公共选中外观 UI:PaintSelectCell（plain 除外）。
-- 点一项（sep 除外）调用 actions[toggle](context, 项, 新状态)，新状态 = 这一项现在不是 true；owner 写好后 context:RefreshPage()。
-- 尺寸全在 GM.settings.parts.iconPick*（页面样式预设可覆盖），颜色只用 GUIColors。
local UI, Factory = _G.ExwindTools.UI, _G.ExwindFactory
local L = _G.ExwindTools.L
local GM = _G.ExwindTools.GUIMetrics
local POOL, ITEM_POOL = "EXUI.SettingsV2.IconPick", "EXUI.SettingsV2.IconPickItem"
Factory:InitCompositePool(POOL)
Factory:InitCompositePool(ITEM_POOL)
local Kinds = { icon = true, instance = true, boss = true, label = true, nav = true, sep = true, more = true }
local Packs = { split = true, flow = true, side = true }
local Removable = { icon = true, label = true, instance = true, boss = true }
-- 首领卡 3D 头像的镜头（同 EXBoss 首领页）。
local MODEL_ZOOM, MODEL_CAMERA = 0.85, 1.05

local function Colors() return _G.ExwindTools.GUIColors end

-- 去色压暗 / 原色：贴图（圆角图像或普通材质）跟着选中、悬停换。
local function Shade(texture, on, hover)
    local GC = Colors()
    texture:SetDesaturated(not on)
    local color = on and GC.white or (hover and GC.pickHoverShade or GC.pickDimShade)
    texture:SetVertexColor(color[1], color[2], color[3], 1)
end

-- 选中外框（公共选中外观，压在格子边上，代替 face 的淡边框）；没选中只留一圈淡边框（画在 face 上）。
local function PaintRing(frame, on, radius)
    UI:PaintSelectCell(frame, on, radius)
end

local function Paint(frame)
    local state = frame._ip
    if not state then return end
    local GC, item, kind = Colors(), state.item, state.kind
    local hover = state.enabled and frame.button:IsMouseOver()
    local on = item.selected == true
    if kind == "icon" then
        if item.plain then
            Shade(frame.rounded, true, false)
            UI:SetControlSurface(frame.face, GM.radius.popup, item.portrait and GC.header or GC.transparent, GC.subcardBorder)
            PaintRing(frame, false)
        else
            Shade(frame.rounded, on, hover)
            UI:SetControlSurface(frame.face, GM.radius.popup, item.portrait and GC.header or GC.transparent,
                on and GC.transparent or GC.subcardBorder)
            PaintRing(frame, on, GM.radius.popup)
        end
        frame:SetAlpha(state.enabled and 1 or 0.6)
    elseif kind == "instance" then
        Shade(frame.image, on, hover)
        UI:SetControlSurface(frame.face, GM.radius.popup, GC.input, on and GC.transparent or GC.subcardBorder)
        frame.label:SetTextColor(unpack(not state.enabled and GC.textDisabled or ((on or hover) and GC.text or GC.textDim)))
        PaintRing(frame, on, GM.radius.popup)
        frame:SetAlpha(state.enabled and 1 or 0.6)
    elseif kind == "boss" then
        -- 悬停抬底；选中只有外框和外发光，同其它格子。
        UI:SetControlSurface(frame.face, GM.radius.dialog, hover and GC.menuHover or GC.transparent,
            on and GC.transparent or GC.subcardBorder)
        frame.model:SetAlpha((on or hover) and 1 or state.part("iconPickDimAlpha"))
        frame.label:SetTextColor(unpack(not state.enabled and GC.textDisabled or ((on or hover) and GC.text or GC.textDim)))
        PaintRing(frame, on, GM.radius.dialog)
        frame:SetAlpha(state.enabled and 1 or 0.6)
    elseif kind == "label" then
        local lit = item.selected == true or hover
        frame.label:SetTextColor(unpack(not state.enabled and GC.textDisabled or (lit and GC.text or GC.textDim)))
        frame:SetAlpha(state.enabled and 1 or 0.6)
    elseif kind == "nav" then
        -- 侧栏导航项：选中、悬停同 Core 树行（如 EXAura 左树）。
        if hover then UI:SetControlSurface(frame, GM.radius.control, GC.menuHover, GC.transparent)
        else UI:ClearControlSurface(frame) end
        UI:PaintSelectRow(frame, on)
        frame.label:SetTextColor(unpack(not state.enabled and GC.textDisabled or (on and GC.selectedText or GC.text)))
    elseif kind == "more" then
        UI:SetControlSurface(frame.face, GM.radius.popup, GC.input, hover and GC.inputHoverBorder or GC.inputBorder)
        frame.label:SetTextColor(unpack(GC.textDim))
    end
end

-- 选中或可用变了才重画（挂载、刷新、设可用同一轮只画一次；再打开没变不画）。悬停直接 Paint。
local function Sync(frame)
    local state = frame._ip
    local key = tostring(state.item.selected) .. (state.enabled and "+" or "-")
    if state.painted == key then return end
    state.painted = key
    Paint(frame)
end

local function ShowTip(frame)
    local tip = frame._ip and frame._ip.item.tip
    if not tip or tip == "" then return end
    local GC = Colors()
    GameTooltip:SetOwner(frame.button, "ANCHOR_TOP")
    local first = true
    for line in tostring(tip):gmatch("[^\n]+") do
        local color = first and GC.text or GC.textDim
        GameTooltip:AddLine(line, color[1], color[2], color[3], true)
        first = false
    end
    GameTooltip:Show()
end

-- 一项先只建点击按钮，其余零件按种类第一次用到才建（分隔只要线，标题只要字，图标才要圆角图像和选中外框）。
local function NewItem(frame)
    frame.button = CreateFrame("Button", nil, frame)
    frame.button:SetAllPoints(frame)
    frame.button:RegisterForClicks("LeftButtonUp")
    frame.button:SetScript("OnEnter", function()
        Paint(frame); ShowTip(frame)
        if frame.remove and frame._ip and frame._ip.enabled then frame.remove:Show() end
    end)
    frame.button:SetScript("OnLeave", function(self)
        Paint(frame)
        if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
        -- 移到删除小叉上时还在格子里，叉留着；离开格子才收起。
        if frame.remove and not frame:IsMouseOver() then frame.remove:Hide() end
    end)
    frame.button:SetScript("OnMouseDown", function(self) if GameTooltip:GetOwner() == self then GameTooltip:Hide() end end)
    frame.button:SetScript("OnClick", function()
        local state = frame._ip
        if state and state.enabled and state.onClick then state.onClick(state.item) end
    end)
end
local function EnsureFace(frame)
    if frame.face then return end
    frame.face = CreateFrame("Frame", nil, frame)
    frame.face:EnableMouse(false)
    frame.face:SetAllPoints(frame)
end
local function EnsureLabel(frame)
    if frame.label then return end
    EnsureFace(frame)
    frame.label = UI:CreateVisualFontString(frame.face, _G.EXFONTFRAME, "GameFontHighlight")
    frame.label:SetWordWrap(false)
    frame.label:SetJustifyH("LEFT")
end
local function EnsureImage(frame)
    if frame.image then return end
    EnsureFace(frame)
    frame.image = frame.face:CreateTexture(nil, "ARTWORK")
end
-- icon / label / nav 的贴图：Core 圆角图像，四角与边框同一圆角。
local function EnsureRounded(frame)
    if frame.rounded then return end
    EnsureFace(frame)
    frame.rounded = UI:CreateRoundedImage(frame.face, GM.radius.popup, true)
end
local PARTS = { "face", "label", "line", "rounded", "image" }

-- 删除小叉（声明写了 remove）：同法术芯片角上的删除叉，整个落在格子里面（离边 2），平时隐藏。
local function ReleaseRemove(frame)
    if not frame.remove then return end
    frame.remove:Release()
    frame.remove = nil
end
local function AttachRemove(frame, part)
    local state = frame._ip
    if not state.onRemove or not Removable[state.kind] then return end
    local size, GC = part("chipCornerRemoveSize"), Colors()
    local remove = UI:CreateIconButton(frame, size, size, { icon = "x", appearance = "ghost", iconSize = size,
        iconColor = GC.dangerText, hoverIconColor = GC.text,
        onClick = function(_, mouseButton)
            local current = frame._ip
            if mouseButton == "LeftButton" and current and current.enabled and current.onRemove then current.onRemove(current.item) end
        end })
    local item = state.item
    local anchor = state.kind == "label" and (item.icon or item.atlas) and frame.face or frame
    remove:ClearAllPoints()
    remove:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -2, -2)
    remove:SetFrameLevel(frame.button:GetFrameLevel() + 2)
    remove:Hide()
    frame.remove = remove
end

-- 首领卡的零件（3D 头像、首领战 ID 小牌）第一次用到才建，照 EXBoss 首领卡的尺寸和锚点。
local function EnsureBossParts(frame, part)
    if frame.model then return end
    frame.model = CreateFrame("PlayerModel", nil, frame.face)
    frame.model:EnableMouse(false)
    frame.noModel = UI:CreateVisualFontString(frame.face, _G.EXFONTFRAME, "GameFontDisableSmall")
    frame.noModel:SetPoint("CENTER", frame.model, "CENTER", 0, 0)
    frame.badge = CreateFrame("Frame", nil, frame.face)
    frame.badge:EnableMouse(false)
    -- 小牌的字和小牌底板同一个 Frame：父卡片的字画不到子 Frame 的底板上面。
    frame.badgeText = UI:CreateVisualFontString(frame.badge, _G.EXFONTFRAME, "GameFontDisableSmall")
    frame.badgeText:SetPoint("CENTER", frame.badge, "CENTER", 0, 0)
    frame.badgeText:SetJustifyH("CENTER")
    frame.badgeText:SetWordWrap(false)
end

local function HideBossParts(frame)
    if not frame.model then return end
    frame.model:ClearModel()
    frame.model:Hide()
    frame.noModel:Hide()
    frame.badge:Hide()
    UI:ClearControlSurface(frame.badge)
end

-- 圆角图像铺进 face（内缩 1 物理像素露出边框）：coords 先取一块，crop = 四边各裁掉的比例（材质文件默认 .08 去掉
-- 自带黑边，图集默认不裁；圆形徽记这类写大一点，让图案铺满方块）；portrait = 2:1 头像取中间方形。
local function FillRounded(frame, item)
    EnsureRounded(frame)
    local edge = PixelUtil.GetNearestPixelSize(1, frame:GetEffectiveScale(), 1)
    local image, crop = frame.rounded, item.crop
    image:ClearAllPoints()
    image:SetPoint("TOPLEFT", frame.face, "TOPLEFT", edge, -edge)
    image:SetPoint("BOTTOMRIGHT", frame.face, "BOTTOMRIGHT", -edge, edge)
    image:SetCornerRadius(GM.radius.popup - edge)
    local left, right, top, bottom = 0, 1, 0, 1
    if item.atlas then
        local info = C_Texture.GetAtlasInfo(item.atlas)
        image:SetTexture(info.file)
        left, right, top, bottom = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
        crop = crop or 0
    else
        image:SetTexture(item.icon)
        crop = crop or ((item.portrait or item.coords) and 0 or .08)
    end
    if item.coords then left, right, top, bottom = item.coords[1], item.coords[2], item.coords[3], item.coords[4] end
    if item.portrait then
        local quarter = (right - left) / 4
        left, right = left + quarter, right - quarter
    end
    local w, h = (right - left) * crop, (bottom - top) * crop
    image:SetTexCoord(left + w, right - w, top + h, bottom - h)
    image:Show()
end

-- 借一项并按种类摆好里面的零件（尺寸存在 _ip.width / _ip.height；instance / boss 的宽由排法给）。
local function AcquireItem(parent, item, part, onClick, onRemove)
    local frame, isNew = Factory:AcquireCompositeHost(ITEM_POOL, parent)
    if isNew then NewItem(frame) end
    ReleaseRemove(frame)
    local kind = item.kind
    local state = { item = item, kind = kind, part = part, enabled = true, onClick = kind ~= "sep" and onClick or nil,
        onRemove = onRemove }
    frame._ip = state
    frame.button:SetFrameLevel(frame:GetFrameLevel() + 6)
    frame.button:SetShown(kind ~= "sep")
    for _, key in ipairs(PARTS) do if frame[key] then frame[key]:Hide() end end
    UI:PaintSelectCell(frame, false)
    HideBossParts(frame)
    if kind ~= "sep" then
        EnsureFace(frame)
        frame.face:ClearAllPoints()
        frame.face:SetAllPoints(frame)
        frame.face:SetFrameLevel(frame:GetFrameLevel() + 1)
    end
    if frame.image then frame.image:SetTexture(nil); frame.image:ClearAllPoints() end
    if kind ~= "icon" and kind ~= "sep" then EnsureLabel(frame) end
    if frame.label then frame.label:ClearAllPoints() end
    local GC = Colors()
    if kind == "icon" then
        local size = part(item.small and "iconPickSmall" or "iconPickCell")
        state.width, state.height = size, size
        frame.face:Show()
        FillRounded(frame, item)
    elseif kind == "instance" then
        state.width = part("iconPickCardWidth")
        state.height = part("iconPickCardImage") + part("iconPickCardName")
        frame.face:Show()
        EnsureImage(frame)
        local edge = PixelUtil.GetNearestPixelSize(1, frame:GetEffectiveScale(), 1)
        frame.image:SetPoint("TOPLEFT", frame.face, "TOPLEFT", edge, -edge)
        frame.image:SetPoint("TOPRIGHT", frame.face, "TOPRIGHT", -edge, -edge)
        frame.image:SetHeight(part("iconPickCardImage") - edge)
        frame.image:SetTexture(item.icon)
        local c = item.coords or { 0, 1, 0, 1 }
        frame.image:SetTexCoord(c[1], c[2], c[3], c[4])
        frame.image:Show()
        UI.ControlAppearance.Font(frame.label, part("iconPickFont"), GC.text, "", "GameFontHighlight")
        frame.label:SetText(item.text or "")
        frame.label:SetPoint("BOTTOMLEFT", frame.face, "BOTTOMLEFT", part("iconPickTextGap"), 0)
        frame.label:SetPoint("BOTTOMRIGHT", frame.face, "BOTTOMRIGHT", -part("iconPickTextGap"), 0)
        frame.label:SetHeight(part("iconPickCardName"))
        frame.label:Show()
    elseif kind == "boss" then
        EnsureBossParts(frame, part)
        state.width, state.height = part("iconPickCardWidth"), part("iconPickBossHeight")
        frame.face:Show()
        local model = frame.model
        model:ClearAllPoints()
        model:SetPoint("LEFT", frame.face, "LEFT", 9, 0)
        model:SetSize(part("iconPickModelWidth"), part("iconPickModelHeight"))
        model:SetFrameLevel(frame.face:GetFrameLevel() + 1)
        model:Show()
        if item.displayID then
            model:SetDisplayInfo(item.displayID)
            model:SetPortraitZoom(MODEL_ZOOM)
            model:SetCamDistanceScale(MODEL_CAMERA)
            model:SetPosition(0, 0, 0)
            model:SetFacing(0)
        else
            UI.ControlAppearance.Font(frame.noModel, GM.font.text, GC.textPlaceholder, "", "GameFontDisableSmall")
            frame.noModel:SetText(L["无动态头像"])
            frame.noModel:Show()
        end
        UI.ControlAppearance.Font(frame.label, GM.font.exboss.navigationTitle, GC.text, "OUTLINE", "GameFontNormal")
        frame.label:SetText(item.text or "")
        frame.label:SetJustifyV("TOP")
        frame.label:SetPoint("TOPLEFT", model, "TOPRIGHT", 12, -8)
        frame.label:SetPoint("RIGHT", frame.face, "RIGHT", -8, 0)
        frame.label:Show()
        UI.ControlAppearance.Font(frame.badgeText, GM.font.text, GC.textDim, "", "GameFontDisableSmall")
        frame.badgeText:SetText(item.badge or "")
        frame.badge:ClearAllPoints()
        frame.badge:SetPoint("BOTTOMLEFT", model, "BOTTOMRIGHT", 12, 7)
        frame.badge:SetSize(math.max(46, math.ceil(frame.badgeText:GetUnboundedStringWidth()) + 16), 21)
        frame.badge:SetFrameLevel(frame.face:GetFrameLevel() + 2)
        UI:SetControlSurface(frame.badge, 4, GC.panel, GC.cardBorder)
        frame.badge:SetShown(item.badge ~= nil)
    elseif kind == "label" or kind == "nav" then
        -- 分组标题 / 侧栏导航项：小图标（可选）+ 名字。
        local nav = kind == "nav"
        local padX = nav and part("iconPickNavPadX") or 0
        local gap = part("iconPickTextGap")
        UI.ControlAppearance.Font(frame.label, part(nav and "iconPickFont" or "iconPickTitleFont"), GC.text, "", "GameFontHighlight")
        frame.label:SetText(item.text or "")
        frame.label:Show()
        -- 名字挂在 face 上（副本卡、首领卡的字要压在 face 的底板上面），所以没有小图标时 face 也显示（不画东西）。
        frame.face:Show()
        local x = padX
        if item.icon or item.atlas then
            local size = part(nav and "iconPickNavIcon" or (item.large and "iconPickCell" or "iconPickHeadIcon"))
            frame.face:ClearAllPoints()
            frame.face:SetPoint("LEFT", frame, "LEFT", padX, 0)
            frame.face:SetSize(size, size)
            FillRounded(frame, item)
            UI:SetControlSurface(frame.face, GM.radius.popup, GC.transparent, GC.subcardBorder)
            x = padX + size + gap
        end
        frame.label:SetPoint("LEFT", frame, "LEFT", x, 0)
        if nav then
            frame.label:SetPoint("RIGHT", frame, "RIGHT", -padX, 0)
            state.width, state.height = part("iconPickNavWidth"), part("iconPickNavHeight")
        else
            state.width = x + math.ceil(frame.label:GetUnboundedStringWidth()) + gap
            state.height = math.max(part("iconPickHeadHeight"), item.large and part("iconPickCell") or 0)
        end
    elseif kind == "more" then
        local size = part("iconPickSmall")
        state.width, state.height = size, size
        frame.face:Show()
        UI.ControlAppearance.Font(frame.label, part("iconPickFont"), GC.textDim, "", "GameFontHighlight")
        frame.label:SetText(item.text or "")
        frame.label:SetJustifyH("CENTER")
        frame.label:SetPoint("CENTER", frame.face, "CENTER", 0, 0)
        frame.label:Show()
    else -- sep
        local gap = part("iconPickSeparatorGap")
        state.width, state.height = gap * 2 + 1, part("iconPickSeparatorHeight")
        if not frame.line then frame.line = frame:CreateTexture(nil, "ARTWORK") end
        frame.line:SetColorTexture(unpack(GC.popupDivider))
        frame.line:ClearAllPoints()
        frame.line:SetPoint("TOP", frame, "TOP", 0, 0)
        frame.line:SetPoint("BOTTOM", frame, "BOTTOM", 0, 0)
        frame.line:SetWidth(PixelUtil.GetNearestPixelSize(1, frame:GetEffectiveScale(), 1))
        frame.line:Show()
    end
    if frame.label then
        if kind ~= "more" then frame.label:SetJustifyH("LEFT") end
        if kind ~= "boss" then frame.label:SetJustifyV("MIDDLE") end
    end
    AttachRemove(frame, part)
    frame:Show()
    return frame
end

local function ReleaseItem(frame)
    if GameTooltip:GetOwner() == frame.button then GameTooltip:Hide() end
    ReleaseRemove(frame)
    frame._ip = nil
    if frame.label then frame.label:SetText("") end
    if frame.image then frame.image:SetTexture(nil) end
    if frame.rounded then frame.rounded:SetTexture(nil) end
    HideBossParts(frame)
    UI:ClearControlSurface(frame)
    UI:ClearControlSurface(frame.face)
    UI:PaintSelectCell(frame, false)
    frame:SetAlpha(1)
    Factory:ReleaseCompositeHost(frame)
end

local function CheckItem(Check, id, item)
    Check(type(item) == "table" and Kinds[item.kind], id .. ": iconpick item kind must be icon / instance / boss / label / nav / sep / more")
    Check(item.selected == nil or type(item.selected) == "boolean" or (item.kind == "label" and item.selected == "part"),
        id .. ": iconpick selected must be boolean (\"part\" only on label)")
    Check(item.icon == nil or type(item.icon) == "number", id .. ": iconpick icon must be a texture file id")
    Check(item.atlas == nil or type(item.atlas) == "string", id .. ": iconpick atlas must be a string")
    Check(item.tip == nil or type(item.tip) == "string", id .. ": iconpick tip must be a string")
    local rounded = item.kind == "icon" or item.kind == "label" or item.kind == "nav"
    Check(item.crop == nil or (rounded and type(item.crop) == "number" and item.crop >= 0 and item.crop < .5),
        id .. ": iconpick crop must be a number in [0, .5) on icon / label / nav")
    Check(item.coords == nil or ((rounded or item.kind == "instance") and type(item.coords) == "table" and #item.coords == 4),
        id .. ": iconpick coords must be { left, right, top, bottom } on icon / label / nav / instance")
    Check(item.portrait == nil or (rounded and item.portrait == true), id .. ": iconpick portrait must be true on icon / label / nav")
    Check(item.small == nil or (item.kind == "icon" and item.small == true), id .. ": iconpick small must be true on icon")
    Check(item.plain == nil or (item.kind == "icon" and item.plain == true), id .. ": iconpick plain must be true on icon")
    Check(item.large == nil or (item.kind == "label" and item.large == true), id .. ": iconpick large must be true on label")
    Check(item.displayID == nil or (item.kind == "boss" and type(item.displayID) == "number"),
        id .. ": iconpick displayID must be a number on boss")
    Check(item.badge == nil or (item.kind == "boss" and type(item.badge) == "string"), id .. ": iconpick badge must be a string on boss")
    if item.kind ~= "icon" and item.kind ~= "sep" then
        Check(type(item.text) == "string", id .. ": iconpick instance / boss / label / nav / more need text")
    end
    if item.kind == "icon" or item.kind == "instance" then
        Check(item.icon ~= nil or item.atlas ~= nil, id .. ": iconpick icon / instance need icon or atlas")
    end
end

-- 结构签名：分组、行、项的种类与外观没变时只同步选中状态，不重建。
local function Signature(sections)
    local parts = {}
    local function Add(value) parts[#parts + 1] = tostring(value) end
    for _, section in ipairs(sections) do
        Add("S"); Add(section.title); Add(section.pack)
        if section.head then Add(section.head.kind); Add(section.head.text); Add(section.head.icon); Add(section.head.large) end
        for _, row in ipairs(section.rows) do
            Add("R"); Add(row.grid); Add(row.divider); Add(row.wrap); Add(row.lines)
            for _, item in ipairs(row.items or {}) do
                Add(item.kind); Add(item.icon); Add(item.atlas); Add(item.text); Add(item.crop); Add(item.portrait)
                Add(item.small); Add(item.plain); Add(item.displayID); Add(item.badge)
                if item.coords then for _, value in ipairs(item.coords) do Add(value) end end
            end
        end
    end
    return table.concat(parts, "\031")
end

local function Adapter(node, kit)
    local spec, session = node.spec, node.session
    local style = session.style
    local Check = kit.Check
    local function part(key) return kit.Part(style, key) end
    local states = {}
    local adapter = {}
    local function Read()
        local sections = kit.Records(node)
        for _, section in ipairs(sections) do
            Check(section.title == nil or type(section.title) == "string", spec.id .. ": iconpick title must be a string")
            Check(section.pack == nil or Packs[section.pack], spec.id .. ": iconpick pack must be split, flow or side")
            Check(type(section.rows) == "table", spec.id .. ": iconpick section needs rows")
            if section.head then
                CheckItem(Check, spec.id, section.head)
                Check(section.head.kind == "label", spec.id .. ": iconpick head must be a label")
            end
            for _, row in ipairs(section.rows) do
                Check(type(row) == "table", spec.id .. ": iconpick row must be a table")
                Check(row.divider == true or type(row.items) == "table", spec.id .. ": iconpick row needs items or divider")
                Check(row.grid == nil or (type(row.grid) == "number" and row.grid >= 1 and row.grid % 1 == 0),
                    spec.id .. ": iconpick grid must be a positive integer")
                Check(row.wrap == nil or (type(row.wrap) == "number" and row.wrap >= 1 and row.wrap % 1 == 0 and not row.grid),
                    spec.id .. ": iconpick wrap must be a positive integer and not mixed with grid")
                Check(row.lines == nil or (row.grid and type(row.lines) == "number" and row.lines >= 1 and row.lines % 1 == 0),
                    spec.id .. ": iconpick lines must be a positive integer on a grid row")
                for _, item in ipairs(row.items or {}) do CheckItem(Check, spec.id, item) end
            end
        end
        return sections
    end
    local function Text(widget, list, index, size, color)
        local text = list[index]
        if not text then
            text = UI:CreateVisualFontString(widget, _G.EXFONTFRAME, "GameFontHighlightSmall")
            text:SetWordWrap(false)
            text:SetJustifyH("LEFT")
            list[index] = text
        end
        UI.ControlAppearance.Font(text, size, color, "", "GameFontHighlightSmall")
        text:Show()
        return text
    end
    local function ReleaseAll(state)
        for _, section in ipairs(state.sections) do
            if section.head then ReleaseItem(section.head) end
            for _, row in ipairs(section.rows) do
                for _, frame in ipairs(row.items) do ReleaseItem(frame) end
            end
        end
        state.sections = {}
        for _, scroll in ipairs(state.widget._ipScrolls) do scroll:Hide() end
        for _, text in ipairs(state.widget._ipTexts) do text:SetText(""); text:Hide() end
        for _, line in ipairs(state.widget._ipLines) do line:Hide() end
    end
    local function Rebuild(widget, context)
        local state = states[widget]
        local sections = Read()
        local signature = Signature(sections)
        local function Click(item)
            session.owner.actions[spec.toggle](context, item, item.selected ~= true)
        end
        local Remove = spec.remove and function(item) session.owner.actions[spec.remove](context, item) end or nil
        if signature == state.signature then
            -- 结构没变：换成这次的项（新表），只重画选中状态变了的项。
            for s, section in ipairs(sections) do
                local built = state.sections[s]
                built.rec = section
                if built.head then built.head._ip.item = section.head; built.head._ip.onClick = Click; Sync(built.head) end
                for r, row in ipairs(section.rows) do
                    for i, item in ipairs(row.items or {}) do
                        local frame = built.rows[r].items[i]
                        frame._ip.item = item
                        frame._ip.onClick = item.kind ~= "sep" and Click or nil
                        frame._ip.onRemove = Remove
                        Sync(frame)
                    end
                end
            end
            return
        end
        ReleaseAll(state)
        state.signature = signature
        local texts, lines, scrolls = 0, 0, 0
        local GC = Colors()
        for s, section in ipairs(sections) do
            local built = { rec = section, rows = {} }
            if section.head then
                built.head = AcquireItem(widget, section.head, part, Click)
            elseif section.title then
                texts = texts + 1
                built.title = Text(widget, widget._ipTexts, texts, part("iconPickTitleFont"), GC.textDim)
                built.title:SetText(section.title)
            end
            for r, row in ipairs(section.rows) do
                local builtRow = { rec = row, items = {} }
                if row.divider then
                    lines = lines + 1
                    local line = widget._ipLines[lines]
                    if not line then line = widget:CreateTexture(nil, "ARTWORK"); widget._ipLines[lines] = line end
                    line:SetColorTexture(unpack(GC.popupDivider))
                    line:Show()
                    builtRow.line = line
                end
                -- lines 行：格子放进滚动框的内容里；滚动框跟着 widget 复用，结构换了回到顶。
                local parent = widget
                if row.lines then
                    scrolls = scrolls + 1
                    local scroll = widget._ipScrolls[scrolls]
                    if not scroll then
                        scroll = UI:CreateScrollFrame(widget)
                        scroll.scrollBarHideIfUnscrollable = true
                        local content = CreateFrame("Frame", nil, scroll)
                        content:SetSize(1, 1)
                        scroll:SetScrollChild(content)
                        scroll._ipContent = content
                        widget._ipScrolls[scrolls] = scroll
                    end
                    scroll:SetVerticalScroll(0)
                    scroll:Show()
                    builtRow.scroll, parent = scroll, scroll._ipContent
                end
                for i, item in ipairs(row.items or {}) do
                    builtRow.items[i] = AcquireItem(parent, item, part, Click, Remove)
                end
                built.rows[r] = builtRow
            end
            state.sections[s] = built
        end
        for _, section in ipairs(state.sections) do
            for _, row in ipairs(section.rows) do
                for _, frame in ipairs(row.items) do frame._ip.enabled = state.enabled; Sync(frame) end
            end
            if section.head then section.head._ip.enabled = state.enabled; Sync(section.head) end
        end
    end

    -- 一个分组的自然宽（不换行时）。
    local function SectionNatural(section)
        local width = 0
        if section.head then width = section.head._ip.width
        elseif section.title then width = math.ceil(section.title:GetUnboundedStringWidth()) end
        for _, row in ipairs(section.rows) do
            local rowWidth = 0
            for i, frame in ipairs(row.items) do
                rowWidth = rowWidth + frame._ip.width + (i > 1 and part("iconPickGap") or 0)
            end
            if row.rec.grid then rowWidth = 0 end
            width = math.max(width, rowWidth)
        end
        return width
    end
    local function Put(frame, x, y, width, height)
        frame:ClearAllPoints()
        PixelUtil.SetPoint(frame, "TOPLEFT", frame:GetParent(), "TOPLEFT", x, -y, 0, 0)
        PixelUtil.SetSize(frame, math.max(1, width), math.max(1, height), 1, 1)
    end
    -- 排一个分组：返回高；place = true 时同时摆放。
    local function SectionLayout(section, x, y, width, place)
        local top = y
        local gap, padY = part("iconPickGap"), part("iconPickRowPadY")
        local headHeight = 0
        if section.head then headHeight = section.head._ip.height
        elseif section.title then headHeight = part("iconPickTitleHeight") end
        if place then
            if section.head then
                Put(section.head, x, y, section.head._ip.width, headHeight)
            elseif section.title then
                section.title:ClearAllPoints()
                section.title:SetPoint("LEFT", section.title:GetParent(), "TOPLEFT", x, -(y + headHeight / 2))
            end
        end
        y = y + headHeight
        for _, row in ipairs(section.rows) do
            if row.line then
                local height = part("iconPickDividerHeight")
                if place then
                    row.line:ClearAllPoints()
                    PixelUtil.SetPoint(row.line, "TOPLEFT", row.line:GetParent(), "TOPLEFT", x, -(y + math.floor(height / 2)), 0, 0)
                    PixelUtil.SetSize(row.line, math.max(1, width), 1, 1, 1)
                end
                y = y + height
            end
            local items = row.items
            if #items > 0 and row.rec.grid then
                -- grid 是最多几列：最宽的一项放不下时自动少几列。
                local gridGap, widest = part("iconPickGridGap"), 0
                for _, frame in ipairs(items) do widest = math.max(widest, frame._ip.width) end
                local function Columns(space)
                    return math.max(1, math.min(row.rec.grid, math.floor((space + gridGap) / (widest + gridGap))))
                end
                -- lines 行超出可见行数时，右边让出滚动条的宽。
                local scroll, visible = row.scroll, row.rec.lines
                local inner = width
                local over = scroll ~= nil and math.ceil(#items / Columns(width)) > visible
                if over then inner = math.max(1, width - scroll:GetVerticalScrollInset()) end
                local columns = Columns(inner)
                local cell = math.max(1, (inner - gridGap * (columns - 1)) / columns)
                local lineHeight = 0
                for _, frame in ipairs(items) do lineHeight = math.max(lineHeight, frame._ip.height) end
                lineHeight = lineHeight + padY * 2
                local total = math.ceil(#items / columns)
                -- 滚动框里的格子从内容左上角排。
                local ox, oy = scroll and 0 or x, scroll and 0 or y
                for i, frame in ipairs(items) do
                    local column, line = (i - 1) % columns, math.floor((i - 1) / columns)
                    if place then
                        Put(frame, ox + column * (cell + gridGap), oy + line * lineHeight + padY, cell, frame._ip.height)
                    end
                end
                if scroll then
                    if place then
                        Put(scroll, x, y, inner, visible * lineHeight)
                        PixelUtil.SetSize(scroll._ipContent, inner, math.max(1, total * lineHeight), 1, 1)
                        scroll.ScrollBar:SetShown(over)
                    end
                    total = visible
                end
                y = y + total * lineHeight
            elseif #items > 0 then
                -- 从左到右排；放不下或到 wrap 个数就换行。
                local wrap = row.rec.wrap
                local lineStart, cx, lineHeight = 1, 0, 0
                local function Flush(last)
                    if place then
                        local px = 0
                        for i = lineStart, last do
                            local frame = items[i]
                            if i > lineStart then px = px + gap end
                            Put(frame, x + px, y + padY + (lineHeight - frame._ip.height) / 2, frame._ip.width, frame._ip.height)
                            px = px + frame._ip.width
                        end
                    end
                    y = y + lineHeight + padY * 2
                end
                for i, frame in ipairs(items) do
                    local itemWidth = frame._ip.width
                    local start = i == lineStart and 0 or (cx + gap)
                    if i > lineStart and (start + itemWidth > width or (wrap and i - lineStart >= wrap)) then
                        Flush(i - 1)
                        lineStart, lineHeight = i, 0
                        start = 0
                    end
                    cx = start + itemWidth
                    lineHeight = math.max(lineHeight, frame._ip.height)
                end
                Flush(#items)
            end
        end
        return y - top
    end
    -- 样式页的卡片正文没有内距，标准行自带 rowPaddingX / rowPaddingY；这里留同样的内距，内容才和同卡的行对齐、不贴卡边。
    -- 不带样式的卡片正文已有 cardPaddingX，不再另留。
    local padX = style and (style.rowPaddingX or GM.settings.rowPaddingX) or 0
    local padY = style and (style.rowPaddingY or 0) or 0
    local function Arrange(widget, width, place)
        local state = states[widget]
        local sections = state.sections
        local sectionGap, columnGap = part("iconPickSectionGap"), part("iconPickColumnGap")
        local left = padX
        width = math.max(1, width - padX * 2)
        local y, index = padY, 1
        while index <= #sections do
            if index > 1 then y = y + sectionGap end
            local pack = sections[index].rec.pack
            local last = index
            if pack and pack ~= "side" then
                while last < #sections and sections[last + 1].rec.pack == pack do last = last + 1 end
            end
            local count = last - index + 1
            if pack == "side" then
                -- 左边一列按自然宽，紧跟的下一组放右边占满剩下的宽。
                local sideWidth = math.min(width, SectionNatural(sections[index]))
                local tallest = SectionLayout(sections[index], left, y, sideWidth, place)
                if index < #sections then
                    last = index + 1
                    tallest = math.max(tallest, SectionLayout(sections[last], left + sideWidth + columnGap, y,
                        math.max(1, width - sideWidth - columnGap), place))
                end
                y = y + tallest
            elseif not pack then
                y = y + SectionLayout(sections[index], left, y, width, place)
            elseif pack == "split" then
                local columnWidth = math.max(1, (width - columnGap * (count - 1)) / count)
                local tallest = 0
                for i = index, last do
                    tallest = math.max(tallest, SectionLayout(sections[i], left + (i - index) * (columnWidth + columnGap), y, columnWidth, place))
                end
                y = y + tallest
            else
                -- flow：按最宽一组的自然宽算能放几栏，每组放进当前最矮的一栏。
                local natural = 0
                for i = index, last do natural = math.max(natural, SectionNatural(sections[i])) end
                local columns = math.max(1, math.min(count, math.floor((width + columnGap) / (natural + columnGap))))
                local columnWidth = math.max(1, (width - columnGap * (columns - 1)) / columns)
                local heights = {}
                for c = 1, columns do heights[c] = 0 end
                for i = index, last do
                    local column = 1
                    for c = 2, columns do if heights[c] < heights[column] then column = c end end
                    local top = y + heights[column] + (heights[column] > 0 and sectionGap or 0)
                    local height = SectionLayout(sections[i], left + (column - 1) * (columnWidth + columnGap), top, columnWidth, place)
                    heights[column] = top + height - y
                end
                local tallest = 0
                for c = 1, columns do tallest = math.max(tallest, heights[c]) end
                y = y + tallest
            end
            index = last + 1
        end
        return y + padY
    end

    function adapter.mount(host, context)
        local widget, isNew = Factory:AcquireCompositeHost(POOL, host)
        if isNew then widget._ipTexts, widget._ipLines, widget._ipScrolls = {}, {}, {} end
        states[widget] = { host = host, widget = widget, sections = {}, enabled = true }
        widget:SetWidth(GM.settings.controlWideWidth)
        widget:Show()
        Rebuild(widget, context)
        return widget
    end
    function adapter.update(widget, context) Rebuild(widget, context) end
    function adapter.measure(widget, context, width) return Arrange(widget, width, false) end
    function adapter.layout(widget, context, width, height)
        kit.Place(widget, states[widget].host, 0, 0, width, height)
        Arrange(widget, width, true)
    end
    function adapter.setEnabled(widget, context, enabled)
        local state = states[widget]
        state.enabled = enabled
        for _, section in ipairs(state.sections) do
            if section.head then section.head._ip.enabled = enabled; Sync(section.head) end
            for _, row in ipairs(section.rows) do
                for _, frame in ipairs(row.items) do frame._ip.enabled = enabled; Sync(frame) end
            end
        end
    end
    -- 整页收起（祖先已经不显示）时不藏自己：再显示时格子只跟着祖先显示一次，不再各自重排一遍。
    function adapter.setVisible(widget, context, visible)
        if not visible and not widget:IsVisible() then return end
        widget:SetShown(visible)
    end
    function adapter.release(widget)
        local state = states[widget]
        states[widget] = nil
        ReleaseAll(state)
        Factory:ReleaseCompositeHost(widget)
    end
    return adapter
end

UI._SettingsV2IconPickAdapter = Adapter
