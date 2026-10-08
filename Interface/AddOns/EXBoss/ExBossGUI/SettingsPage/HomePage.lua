---@diagnostic disable: undefined-global, undefined-field, need-check-nil

ExBoss.UI.Panel.HomePage = ExBoss.UI.Panel.HomePage or {}
local Page = ExBoss.UI.Panel.HomePage
local L = ExBoss.L or setmetatable({}, { __index = function(_, key) return key end })
local EXUI = _G.ExwindTools and _G.ExwindTools.UI
local GC = _G.ExwindTools and _G.ExwindTools.GUIColors
local GM = _G.ExwindTools and _G.ExwindTools.GUIMetrics

do
    local zhCN = ExBoss.NewLocale and ExBoss:NewLocale("zhCN")
    if zhCN then
        zhCN["隐藏 EXBoss 小地图按钮"] = true
        zhCN["感谢以下人员在插件发展过程中给予的协助。每次打开首页时，上下两组名单均随机排序。感谢不代表本插件支持或反对任何立场。如有遗漏，请私聊我提醒。"] = true
    end
    local enUS = ExBoss.NewLocale and ExBoss:NewLocale("enUS")
    if enUS then
        enUS["隐藏 EXBoss 小地图按钮"] = "Hide EXBoss Minimap Button"
        enUS["感谢以下人员在插件发展过程中给予的协助。每次打开首页时，上下两组名单均随机排序。感谢不代表本插件支持或反对任何立场。如有遗漏，请私聊我提醒。"] = "Thank you to everyone below for helping develop the addon. Both lists are shuffled each time the home page opens. Acknowledgment does not imply endorsement of any views. Please message me if someone is missing."
    end
end

local MODULE_KEY = "ExBoss.HomePage"
local INFORMATION_RENDERER = "ExBoss.HomePage.Information"
local CARD_GAP = 8

local scrollChild = nil
local missingDepsText = nil
local RefreshPage = nil
local pageLayoutData = nil
local cardSession = nil
local layoutGeneration = 0

local LOCALE_ITEMS = {
    { L["自动跟随客户端"], "AUTO" },
    { L["强制 zhCN"], "zhCN" },
    { L["强制 zhTW"], "zhTW" },
    { L["强制 enUS"], "enUS" },
    { L["强制 koKR"], "koKR" },
    { L["强制 deDE"], "deDE" },
    { L["强制 esES"], "esES" },
    { L["强制 esMX"], "esMX" },
    { L["强制 itIT"], "itIT" },
    { L["强制 ptBR"], "ptBR" },
    { L["强制 frFR"], "frFR" },
    { L["强制 ruRU"], "ruRU" },
}

-- 首页资料只用于本次绘制，不参与配置、默认值、保存或通知通道。
-- 增删人物/资料只改下面的表；人物卡片由 Core 的 EXUI.PersonCards 渲染。
-- 首页专用图标按显示尺寸绘制，只裁掉贴图画布的透明补边。
local UNIFIED_ICON_ROOT = "Interface\\AddOns\\ExwindCore\\Textures\\Icons\\EXBoss\\HomeResources\\"
local HOME_RESOURCES = {
    { icon = UNIFIED_ICON_ROOT .. "message.tga", title = L["蓝帖追踪"], description = L["实时追踪魔兽世界蓝帖（中文）。"], url = "https://exwind.net" },
    { icon = UNIFIED_ICON_ROOT .. "help.tga", title = L["常见问题"], description = L["插件常见问题与使用帮助。"], url = "https://exwind.net/faq/general" },
    { icon = UNIFIED_ICON_ROOT .. "music.tga", title = L["LSM 音频打包"], description = L["上传音频，自动打包成插件；可在游戏内所有音频选项中使用。"], url = "https://exwind.net/lsm" },
    { icon = UNIFIED_ICON_ROOT .. "settings.tga", title = L["配置原理"], description = L["了解 EXBoss 的配置原理。"], url = "https://exwind.net/exboss/config" },
    { icon = UNIFIED_ICON_ROOT .. "headphones.tga", title = L["语音包说明"], description = L["EXBoss 语音包使用说明。"], url = "https://exwind.net/exboss/voices" },
    { icon = UNIFIED_ICON_ROOT .. "microphone.tga", title = L["语音包制作"], description = L["制作自己的 EXBoss 语音包。"], url = "https://exwind.net/exboss" },
}

-- 顶部联系方式使用白色图标；感谢名单使用独立彩色平台素材。
local CONTACT_ICON_ROOT = "Interface\\AddOns\\ExwindCore\\Textures\\Icons\\EXBoss\\Contact\\"
local THANKS_ICON_ROOT = "Interface\\AddOns\\ExwindCore\\Textures\\Icons\\EXBoss\\Thanks\\"
local function PlatformBadge(platform)
    return { icon = THANKS_ICON_ROOT .. platform .. ".tga", color = GC.white, style = "icon", texCoords = { 0, 0.75, 0, 0.75 } }
end
-- 联系人：统一白色单色图，不画底色方块。
-- 三项严格等宽，不按网址长短分配宽度。
local HOME_CONTACTS = {
    { icon = CONTACT_ICON_ROOT .. "discord.tga", brand = GC.white,
        title = "Discord", description = L["社区交流与反馈"], url = "https://discord.gg/6fwVhRHyg9" },
    { icon = CONTACT_ICON_ROOT .. "qq.tga", brand = GC.white,
        title = L["QQ 群"], description = L["群组交流与反馈"], url = "2168036546" },
    { icon = CONTACT_ICON_ROOT .. "bilibili.tga", brand = GC.white,
        title = "Bilibili", description = L["EX-WIND 私信"], url = "https://space.bilibili.com/3494364483422992" },
}

-- 一级感谢：6 张竖排高卡。卡片较窄，网址省略 https:// 与 www. 并用小一号字才能完整显示（浏览器照样能打开）。
-- avatar 为可选头像图（建议 128×128，会被裁成圆形）；不写则显示名称首字。badge 为头像右下角的平台角标。
local THANKS_ACCENT = { text = L["特别感谢"], style = "accent" }
local HOME_PEOPLE = {
    { name = "MusclebrahTV", tags = { THANKS_ACCENT, L["创作者"] }, url = "instagram.com/musclebrahtv",
        badge = PlatformBadge("instagram"),
        description = L["他提供了非常多的测试反馈以及DC用户的问答，以及后续会协助我们制作介绍视频。"] },
    { name = "tettles", tags = { THANKS_ACCENT, L["创作者"] }, url = "youtube.com/@tettles",
        badge = PlatformBadge("youtube"), description = L["他制作了一个协助我们介绍插件的视频。"] },
    { name = "露露緹婭", tags = { THANKS_ACCENT }, url = "space.bilibili.com/455259",
        badge = PlatformBadge("bilibili"), description = L["在生病期间他给予了很多测试协助支持。"] },
    { name = "叶落初冬", tags = { THANKS_ACCENT }, url = "space.bilibili.com/121538100",
        badge = PlatformBadge("bilibili"), description = L["协助反馈并优化插件，提出了多个更为细致的功能。"] },
    { name = "神秘地瓜", tags = { L["技术交流合作"] },
        url = "space.bilibili.com/242463801", badge = PlatformBadge("bilibili") },
    { name = "Naowh", tags = { L["创作者"] }, url = "twitch.tv/naowh", badge = PlatformBadge("twitch") },
}

-- 二级感谢名单：正文名单，自然换行，不使用按钮式胶囊。为空则整块不显示。
local HOME_PEOPLE_SECONDARY = {
    { name = "Hello Bear" },
    { name = "R'lyeh Text" },
    { name = "誓言" },
    { name = "Shun" },
    { name = "很虚" },
    { name = "清心" },
    { name = "子梦" },
    { name = "毛天使" },
    { name = "Margaret" },
    { name = "西北@QQ" },
    { name = "Liny@QQ" },
    { name = L["DC群组所有反馈的小伙伴"] },
    { name = L["QQ群组所有反馈的小伙伴"] },
}

local function GetPageDBDefaults()
    return {
        localeMode = "AUTO",
    }
end

local function GetPageDB()
    if not (ExwindTools and ExwindTools.GetModuleDB) then
        return GetPageDBDefaults()
    end
    return ExwindTools:GetModuleDB(MODULE_KEY, GetPageDBDefaults())
end

local function SyncPageDBFromRuntime()
    local db = GetPageDB()
    if ExBoss.GetLocaleMode then
        db.localeMode = tostring(ExBoss:GetLocaleMode() or "AUTO")
    end
    return db
end

-- 首页版面块渲染器：页头 / 分区标题 / 细线 / 资源列表行 / 界面语言行 / 说明文字。
-- 首页用留白组织内容，仅在主要分区之间保留细线。
-- 人物卡片不在这里：它由 Core 的 "EXUI.PersonCards" 渲染器负责，见 BuildLayout。
-- 每个块在 opts.entries 里按 kind 声明；高度先粗估，layout 量出真实高度后经 ctx:SetContentHeight 上报。
local HOME_FONT = GM.font
local HOME_PAD = GM.space.cardBodyPadding
local HOME_GAP = GM.space.descriptionGap
local HOME_BLOCK_GAP = GM.space.settingsV2Gap
local HOME_CONTACT_ICON = GM.size.homeContactIcon
local HOME_RESOURCE_ICON = GM.size.homeResourceIcon
local HOME_URL_HEIGHT = GM.size.inputHeight
-- 信息块放进卡片时的内边距：左右与设置列表行一致，上下与卡片正文一致。
local HOME_INSET_X = GM.space.rowPaddingX
local HOME_INSET_Y = GM.space.cardBodyPadding
local HOME_LINE_SPACING = 3
local HOME_TILE_POOL = "ExBoss.HomeTile"
-- 标题与紧随其后的说明小字之间的行内间距（比块间距小一档）。
local HOME_GAP_SMALL = math.floor(HOME_GAP / 2)
-- 分区细线上下各留的空白。
local HOME_RULE_SPACE = 8
-- 页头：第一行是插件名与简介，第二行是三张等宽联系方式，三等分整行宽度
-- （最长的那条 Bilibili 网址要能完整显示）；整体窄于阈值时联系方式改为逐条竖排。
local HOME_BRAND_STACK_WIDTH = 760
-- 资源列表：够宽时两列，否则一列；列间距与右侧网址框宽度。
local HOME_ROWS_TWO_COLUMN_WIDTH = 900
local HOME_ROWS_COLUMN_GAP = 40
local HOME_ROW_URL_WIDTH = 240

local function NewText(parent, text, size, color, justify)
    local control = EXUI:CreateDescription(parent, text, 1)
    local region = control.text
    EXUI.ControlAppearance.Font(region, size, color)
    region:SetWordWrap(true)
    region:SetJustifyH(justify or "LEFT")
    region:SetJustifyV("TOP")
    region:SetSpacing(HOME_LINE_SPACING)
    control:SetFrameLevel(parent:GetFrameLevel() + 1)
    return control
end

local function MeasureText(control, width)
    control:SetWidth(width)
    control.text:SetWidth(width)
    local height = math.max(1, math.ceil(control.text:GetStringHeight()))
    control:SetHeight(height)
    return height
end

local function PlaceTopLeft(frame, parent, x, y)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
end

-- 粗估文字高度：按硬换行逐段算，空段也占一行。
-- 否则带 \n 的说明会被估矮，下一块会压到它上面。
local function EstimateText(text, size, width)
    local lineHeight = math.ceil(size * 1.25) + HOME_LINE_SPACING
    local rows = 0
    for line in (tostring(text) .. "\n"):gmatch("([^\n]*)\n") do
        local characters = select(2, line:gsub("[^\128-\191]", ""))
        rows = rows + math.max(1, math.ceil(characters * size / math.max(1, width)))
    end
    return math.max(1, rows) * lineHeight
end

local function AcquireTile(parent, fill, border)
    local factory = _G.ExwindFactory
    local tile = factory:Acquire(HOME_TILE_POOL, parent)
    tile:SetFrameLevel(parent:GetFrameLevel() + 1)
    EXUI:SetControlSurface(tile, GM.radius.card, fill, border)
    factory:AttachPoolRelease(tile, function(self)
        EXUI:ClearControlSurface(self)
        self.letterText:SetText("")
        self.letterText:Hide()
        if self.iconTexture then
            self.iconTexture:SetTexture(nil)
            self.iconTexture:SetVertexColor(1, 1, 1, 1)
            self.iconTexture:Hide()
        end
        if self.glowTexture then
            self.glowTexture:ClearAllPoints()
            self.glowTexture:Hide()
        end
    end)
    return tile
end

-- 顶部联系方式与资源列表各自使用尺寸规范中的图标大小。
local function SetTileIcon(tile, path, color, size)
    tile.iconTexture = tile.iconTexture or tile:CreateTexture(nil, "ARTWORK")
    tile.iconTexture:ClearAllPoints()
    tile.iconTexture:SetPoint("CENTER")
    tile.iconTexture:SetSize(size, size)
    tile.iconTexture:SetSnapToPixelGrid(true)
    tile.iconTexture:SetTexelSnappingBias(0)
    tile.iconTexture:SetTexture(path)
    tile.iconTexture:SetTexCoord(0, 0.75, 0, 0.75)
    if color then tile.iconTexture:SetVertexColor(unpack(color)) end
    tile.iconTexture:Show()
end

-- 通栏细线：分区之间与列表行之间唯一的分隔手段（首页不画卡片底色与边框）。
-- 线按 host 缓存复用，mount 前由渲染器重置游标，release 只隐藏不销毁。
local function AcquireRule(host)
    local pool = host._exHomeRules
    pool.used = pool.used + 1
    local rule = pool[pool.used]
    if not rule then
        rule = EXUI:CreateSettingsSeparator(host, 1)
        pool[pool.used] = rule
    end
    rule:SetParent(host)
    rule:Show()
    return rule
end

local function PlaceRule(rule, host, x, y, width)
    rule:SetWidth(math.max(1, width))
    PlaceTopLeft(rule, host, x, y)
    return rule:GetHeight()
end

local HOME_BLOCKS = {}

HOME_BLOCKS.text = {
    estimate = function(block, width)
        return EstimateText(block.text, block.role == "hint" and HOME_FONT.hint or HOME_FONT.text, width)
    end,
    mount = function(host, block, state)
        local hint = block.role == "hint"
        state.texts = { NewText(host, block.text, hint and HOME_FONT.hint or HOME_FONT.text,
            hint and GC.textDim or GC.text) }
    end,
    layout = function(host, block, state, width, top)
        PlaceTopLeft(state.texts[1], host, 0, top)
        return MeasureText(state.texts[1], width)
    end,
}

-- 通栏细线，上下各留一个块间距。
HOME_BLOCKS.rule = {
    estimate = function()
        return HOME_RULE_SPACE * 2 + 1
    end,
    mount = function(host, block, state)
        state.rules = { AcquireRule(host) }
    end,
    layout = function(host, block, state, width, top)
        local height = PlaceRule(state.rules[1], host, 0, top + HOME_RULE_SPACE, width)
        return HOME_RULE_SPACE * 2 + height
    end,
}

-- 二级分区标题：标题 + 右侧说明小字。分区之间已有通栏细线，标题本身不再拖一条线。
HOME_BLOCKS.header = {
    estimate = function(block)
        return math.ceil((block.fontSize or HOME_FONT.section) * 1.4)
    end,
    mount = function(host, block, state)
        state.title = NewText(host, block.title, block.fontSize or HOME_FONT.section, GC.white)
        state.texts = { state.title }
        if block.hint then
            state.hint = NewText(host, block.hint, HOME_FONT.hint, GC.textDim)
            state.texts[2] = state.hint
        end
    end,
    layout = function(host, block, state, width, top)
        local titleWidth = math.min(width, math.ceil(state.title.text:GetUnboundedStringWidth()) + 1)
        local titleHeight = MeasureText(state.title, titleWidth)
        PlaceTopLeft(state.title, host, 0, top)
        if state.hint then
            local x = titleWidth + HOME_BLOCK_GAP * 2
            local hintHeight = MeasureText(state.hint, math.max(1, width - x))
            PlaceTopLeft(state.hint, host, x, top + math.max(0, titleHeight - hintHeight) - 1)
            return math.max(titleHeight, hintHeight)
        end
        return titleHeight
    end,
}

-- 三级小标题：只有一行灰字，用于「同样感谢」这类段首。
HOME_BLOCKS.subhead = {
    estimate = function()
        return math.ceil(HOME_FONT.small * 1.4)
    end,
    mount = function(host, block, state)
        state.texts = { NewText(host, block.text, HOME_FONT.small, GC.textDim) }
    end,
    layout = function(host, block, state, width, top)
        PlaceTopLeft(state.texts[1], host, 0, top)
        return MeasureText(state.texts[1], width)
    end,
}

-- 页头：左侧插件名与简介，右侧三张等宽联系方式（图标 | 名称 说明 / 网址框）。
-- 三张严格等宽，宽度不按网址长短分配；图标用平台色，不画底色方块。
local function LayoutContactColumn(parts, host, x, y, columnWidth)
    local textX = x + HOME_CONTACT_ICON + HOME_BLOCK_GAP
    local textWidth = math.max(1, columnWidth - HOME_CONTACT_ICON - HOME_BLOCK_GAP)
    local titleWidth = math.min(textWidth, math.ceil(parts.title.text:GetUnboundedStringWidth()) + 1)
    local titleHeight = MeasureText(parts.title, titleWidth)
    local descWidth = math.max(1, textWidth - titleWidth - HOME_BLOCK_GAP)
    MeasureText(parts.description, descWidth)
    PlaceTopLeft(parts.title, host, textX, y)
    PlaceTopLeft(parts.description, host, textX + titleWidth + HOME_BLOCK_GAP,
        y + math.max(0, titleHeight - parts.description:GetHeight()))
    parts.url:SetWidth(textWidth)
    PlaceTopLeft(parts.url, host, textX, y + titleHeight + HOME_GAP)
    parts.icon:SetSize(HOME_CONTACT_ICON, HOME_CONTACT_ICON)
    PlaceTopLeft(parts.icon, host, x, y + math.floor((titleHeight + HOME_GAP + HOME_URL_HEIGHT - HOME_CONTACT_ICON) / 2))
    return titleHeight + HOME_GAP + HOME_URL_HEIGHT
end

HOME_BLOCKS.brand = {
    estimate = function(block, width)
        local contact = math.ceil(HOME_FONT.title * 1.25) + HOME_GAP + HOME_URL_HEIGHT
        local brand = math.ceil(HOME_FONT.pageTitle * 1.25)
        if width < HOME_BRAND_STACK_WIDTH then
            return brand + HOME_BLOCK_GAP + #block.contacts * (contact + HOME_BLOCK_GAP)
        end
        return brand + HOME_BLOCK_GAP + contact
    end,
    mount = function(host, block, state)
        state.tiles, state.rows, state.texts, state.urls = {}, {}, {}, {}
        state.title = NewText(host, "EXBoss", HOME_FONT.pageTitle, GC.accent)
        state.subtitle = NewText(host, block.subtitle, HOME_FONT.small, GC.textDim)
        state.texts[1], state.texts[2] = state.title, state.subtitle
        for index, item in ipairs(block.contacts) do
            local icon = AcquireTile(host, GC.transparent, GC.transparent)
            SetTileIcon(icon, item.icon, item.brand, HOME_CONTACT_ICON)
            local parts = {
                icon = icon,
                title = NewText(host, item.title, HOME_FONT.title, GC.white),
                description = NewText(host, item.description, HOME_FONT.small, GC.textDim),
                url = EXUI:CreateCopyableUrlBox(host, item.url, 1, "urlCompact"),
            }
            parts.url:SetFrameLevel(host:GetFrameLevel() + 1)
            state.rows[index] = parts
            state.tiles[index] = { frame = icon }
            state.texts[#state.texts + 1] = parts.title
            state.texts[#state.texts + 1] = parts.description
            state.urls[#state.urls + 1] = parts.url
        end
    end,
    layout = function(host, block, state, width, top)
        local count = #state.rows
        -- 插件名与简介同一行：简介按字号差把基线对齐到插件名下沿。
        local titleWidth = math.min(width, math.ceil(state.title.text:GetUnboundedStringWidth()) + 1)
        local titleHeight = MeasureText(state.title, titleWidth)
        PlaceTopLeft(state.title, host, 0, top)
        local subtitleX = titleWidth + HOME_BLOCK_GAP * 2
        local subtitleHeight = MeasureText(state.subtitle, math.max(1, width - subtitleX))
        PlaceTopLeft(state.subtitle, host, subtitleX, top + math.max(0, titleHeight - subtitleHeight) - 2)
        local y = top + math.max(titleHeight, subtitleHeight) + HOME_BLOCK_GAP

        if width < HOME_BRAND_STACK_WIDTH then
            for _, parts in ipairs(state.rows) do
                y = y + LayoutContactColumn(parts, host, 0, y, width) + HOME_BLOCK_GAP
            end
            return y - HOME_BLOCK_GAP - top
        end
        local columnWidth = math.floor((width - HOME_BLOCK_GAP * (count - 1)) / math.max(1, count))
        local x, rowHeight = 0, 0
        for index, parts in ipairs(state.rows) do
            local thisWidth = index == count and math.max(1, width - x) or columnWidth
            rowHeight = math.max(rowHeight, LayoutContactColumn(parts, host, x, y, thisWidth))
            x = x + columnWidth + HOME_BLOCK_GAP
        end
        return y + rowHeight - top
    end,
}

-- 资源列表行：图标 | 名称与说明 | 右侧网址框，行底一条细线。按列数分栏，列内逐行。
HOME_BLOCKS.rows = {
    estimate = function(block, width)
        local columns = width >= HOME_ROWS_TWO_COLUMN_WIDTH and block.columns or 1
        local rows = math.ceil(#block.items / math.max(1, columns))
        return rows * (HOME_RESOURCE_ICON + HOME_PAD) + 1
    end,
    mount = function(host, block, state)
        state.tiles, state.rows, state.texts, state.urls = {}, {}, {}, {}
        for index, item in ipairs(block.items) do
            local icon = AcquireTile(host, GC.transparent, GC.transparent)
            SetTileIcon(icon, item.icon, GC.textDim, HOME_RESOURCE_ICON)
            local parts = {
                icon = icon,
                title = NewText(host, item.title, HOME_FONT.title, GC.text),
                description = NewText(host, item.description, HOME_FONT.hint, GC.textDim),
                url = EXUI:CreateCopyableUrlBox(host, item.url, 1),
            }
            parts.url:SetFrameLevel(host:GetFrameLevel() + 1)
            state.rows[index] = parts
            state.tiles[index] = { frame = icon }
            state.texts[#state.texts + 1] = parts.title
            state.texts[#state.texts + 1] = parts.description
            state.urls[#state.urls + 1] = parts.url
        end
    end,
    layout = function(host, block, state, width, top)
        local columns = math.max(1, width >= HOME_ROWS_TWO_COLUMN_WIDTH and block.columns or 1)
        local columnWidth = math.floor((width - HOME_ROWS_COLUMN_GAP * (columns - 1)) / columns)
        local urlWidth = math.min(HOME_ROW_URL_WIDTH, math.floor(columnWidth * 0.42))
        local textX = HOME_RESOURCE_ICON + HOME_BLOCK_GAP
        local textWidth = math.max(1, columnWidth - textX - urlWidth - HOME_BLOCK_GAP)
        local perColumn = math.ceil(#state.rows / columns)
        -- 第一遍量出每条的文字高度，同一视觉行（跨列）取较大值，两列才会逐行对齐。
        local bodies, rowHeights = {}, {}
        for index, parts in ipairs(state.rows) do
            local rowIndex = (index - 1) % perColumn + 1
            local titleHeight = MeasureText(parts.title, textWidth)
            local descHeight = MeasureText(parts.description, textWidth)
            bodies[index] = { title = titleHeight, description = descHeight,
                body = math.max(HOME_RESOURCE_ICON, titleHeight + HOME_GAP_SMALL + descHeight) }
            rowHeights[rowIndex] = math.max(rowHeights[rowIndex] or 0, bodies[index].body + HOME_PAD)
        end
        local rowTops, cursor = {}, 0
        for rowIndex = 1, perColumn do
            rowTops[rowIndex] = cursor
            cursor = cursor + (rowHeights[rowIndex] or 0)
        end
        for index, parts in ipairs(state.rows) do
            local column = math.floor((index - 1) / perColumn)
            local rowIndex = (index - 1) % perColumn + 1
            local sizes = bodies[index]
            local rowHeight = rowHeights[rowIndex]
            local body = rowHeight - HOME_PAD
            local x = column * (columnWidth + HOME_ROWS_COLUMN_GAP)
            local y = top + rowTops[rowIndex]
            local textTop = y + math.floor((body - sizes.title - HOME_GAP_SMALL - sizes.description) / 2)
            parts.icon:SetSize(HOME_RESOURCE_ICON, HOME_RESOURCE_ICON)
            PlaceTopLeft(parts.icon, host, x, y + math.floor((body - HOME_RESOURCE_ICON) / 2))
            PlaceTopLeft(parts.title, host, x + textX, textTop)
            PlaceTopLeft(parts.description, host, x + textX, textTop + sizes.title + HOME_GAP_SMALL)
            parts.url:SetWidth(urlWidth)
            PlaceTopLeft(parts.url, host, x + columnWidth - urlWidth,
                y + math.floor((body - HOME_URL_HEIGHT) / 2))
        end
        return cursor
    end,
}

local function ReleaseInformationBlocks(host)
    local factory = _G.ExwindFactory
    local body = host._exHomeBody
    for _, rule in ipairs(body and body._exHomeRules or {}) do rule:Hide() end
    for _, item in ipairs(host._exHomeBlocks or {}) do
        local state = item.state
        for _, url in ipairs(state.urls or {}) do EXUI:ReleaseCopyableUrlBox(url) end
        for _, text in pairs(state.texts or {}) do factory:ReleaseGridWidget(text) end
        for _, parts in ipairs(state.tiles or {}) do
            if parts.badge then factory:Release(HOME_TILE_POOL, parts.badge) end
            factory:Release(HOME_TILE_POOL, parts.frame)
        end
    end
    host._exHomeBlocks = nil
end

local function RegisterInformationRenderer(Grid)
    if Grid:GetCustomRenderer(INFORMATION_RENDERER) then return end

    _G.ExwindFactory:InitPool(HOME_TILE_POOL, "Frame", "BackdropTemplate", function(tile)
        tile.letterText = EXUI:CreateVisualFontString(tile, _G.EXFONTFRAME, "GameFontHighlight")
        tile.letterText:SetPoint("CENTER")
    end)

    Grid:RegisterCustomRenderer(INFORMATION_RENDERER, {
        measure = function(pixelWidth, opts)
            local total = 0
            local inner = pixelWidth - HOME_INSET_X * 2
            for _, block in ipairs(opts.entries) do
                total = total + HOME_BLOCKS[block.kind].estimate(block, inner) + HOME_BLOCK_GAP
            end
            return math.max(1, total - HOME_BLOCK_GAP + (opts.padTop or HOME_INSET_Y) + (opts.padBottom or HOME_INSET_Y))
        end,
        mount = function(host, ctx)
            EXUI:SetControlFontStyle(host, "settings")
            -- 内容都挂在 body 上，body 相对卡片内缩，卡片边缘不贴字。
            host._exHomeBody = host._exHomeBody or CreateFrame("Frame", nil, host)
            host._exHomeBody:Show()
            -- 细线按 body 缓存复用：版面块收到的 host 就是 body。
            host._exHomeBody._exHomeRules = host._exHomeBody._exHomeRules or { used = 0 }
            host._exHomeBody._exHomeRules.used = 0
            host._exHomeBlocks = {}
            for _, block in ipairs(ctx.element.opts.entries) do
                local state = {}
                HOME_BLOCKS[block.kind].mount(host._exHomeBody, block, state)
                host._exHomeBlocks[#host._exHomeBlocks + 1] = { block = block, state = state }
            end
        end,
        layout = function(host, ctx, layoutWidth)
            local opts = ctx.element.opts
            local padTop, padBottom = opts.padTop or HOME_INSET_Y, opts.padBottom or HOME_INSET_Y
            local width = math.max(1, (tonumber(layoutWidth) or ctx:GetContentWidth()) - HOME_INSET_X * 2)
            local body = host._exHomeBody
            local y = 0
            for _, item in ipairs(host._exHomeBlocks) do
                local kind = HOME_BLOCKS[item.block.kind]
                y = y + kind.layout(body, item.block, item.state, width, y) + HOME_BLOCK_GAP
            end
            y = math.max(1, y - HOME_BLOCK_GAP)
            body:ClearAllPoints()
            body:SetPoint("TOPLEFT", host, "TOPLEFT", HOME_INSET_X, -padTop)
            body:SetSize(width, y)
            local total = y + padTop + padBottom
            ctx:SetContentHeight(total)
            return total
        end,
        release = ReleaseInformationBlocks,
    })
end

-- [卡片/Grid 迁移边界：首页]
-- 允许：首页静态资料的版面块与既有语言设置的 x/y/w/h、相对跨度及外观。
-- 禁止：修改 localeMode、ReloadUI 回调、key/type、页面 DB 或 ValueController。
-- 首页是一张不画底色的整页卡片：页头、官方资源（界面语言并入其末行）、感谢三段，
-- 段与段之间只用通栏细线分隔。人物卡片使用 Core 的 "EXUI.PersonCards"（surface = "plain"），
-- 数据是 HOME_PEOPLE 一张表，增删人物只改表。
local function BuildMainEntries()
    return {
        { kind = "brand", subtitle = L["副本首领时间轴、语音提示、团队框架发光与配置方案。"],
            contacts = HOME_CONTACTS },
        { kind = "rule" },
        { kind = "header", title = L["官方资源"], fontSize = HOME_FONT.cardTitle,
            hint = L["除「蓝帖追踪」外，其余资源均提供多语言版本。"] },
        { kind = "rows", columns = 2, items = HOME_RESOURCES },
    }
end

-- 仅洗牌展示数组，不改写人物资料；本次打开后的重排布局沿用同一顺序。
local function ShuffledPeople(source)
    local people = {}
    for index, person in ipairs(source) do people[index] = person end
    for index = #people, 2, -1 do
        local other = math.random(index)
        people[index], people[other] = people[other], people[index]
    end
    return people
end

local function BuildLayout()
    local fullWidth = { ratio = 1 }
    local function InfoItem(key, y, entries, padTop, padBottom)
        return { key = key, type = "custom", renderer = INFORMATION_RENDERER,
            opts = { entries = entries, padTop = padTop, padBottom = padBottom },
            measure = true, x = 1, y = y, w = 200, h = 1 }
    end

    local items = {
        InfoItem("home_main", 1, BuildMainEntries(), nil, HOME_GAP),
        { key = "localeMode", type = "select", label = L["界面语言"], items = LOCALE_ITEMS,
            search = true, x = 1, y = 2, w = 120, h = 10 },
        { key = "btn_reload_ui", type = "button", label = L["立即重载界面"],
            func = function() ReloadUI() end, x = 125, y = 2, w = 74, h = 10 },
        InfoItem("thanks_head", 4, {
            { kind = "rule" },
            { kind = "header", title = L["感谢每一份协助"],
                hint = L["感谢以下人员在插件发展过程中给予的协助。每次打开首页时，上下两组名单均随机排序。感谢不代表本插件支持或反对任何立场。如有遗漏，请私聊我提醒。"] },
        }, nil, 0),
        { key = "thanks_people", type = "custom", renderer = "EXUI.PersonCards", measure = true,
            opts = { layout = "portrait", surface = "plain", columns = 6, minColumnWidth = 190,
                columnGap = HOME_BLOCK_GAP, rowGap = HOME_BLOCK_GAP, people = ShuffledPeople(HOME_PEOPLE),
                avatarSize = GM.size.homeThanksAvatar,
                avatarRing = { texture = "Interface\\AddOns\\ExwindCore\\Textures\\Materials\\GUI\\HomeAvatarRing.tga",
                    texCoords = { 0, 0.5625, 0, 0.5625 } },
                padX = HOME_INSET_X, padTop = HOME_BLOCK_GAP, padBottom = 0 },
            x = 1, y = 5, w = 200, h = 1 },
    }
    local rows = {
        { key = "home_main", fullWidth = true },
        { controls = { { key = "localeMode", width = 170 },
            { key = "btn_reload_ui", width = 150 } } },
        { key = "thanks_head", fullWidth = true },
        { key = "thanks_people", fullWidth = true },
    }

    if #HOME_PEOPLE_SECONDARY > 0 then
        local names = {}
        for index, person in ipairs(ShuffledPeople(HOME_PEOPLE_SECONDARY)) do names[index] = person.name end
        items[#items + 1] = InfoItem("thanks_more_head", 6, {
            { kind = "subhead", text = L["同样感谢"] },
        }, HOME_BLOCK_GAP, 0)
        items[#items + 1] = InfoItem("thanks_people_secondary", 7, {
            { kind = "text", text = table.concat(names, "   ·   ") },
        }, HOME_GAP, HOME_GAP)
        rows[#rows + 1] = { key = "thanks_more_head", fullWidth = true }
        rows[#rows + 1] = { key = "thanks_people_secondary", fullWidth = true }
    end

    items[#items + 1] = InfoItem("home_footer", 8, {
        { kind = "text", role = "hint", text = L["声明：可能还有很多英语/外语主播介绍并协助人们了解插件，我并没有长期活跃于英语主播圈子，所以很可能遗漏，这点非常抱歉。如果发生该情况可以随时私信我（不一定要主播本人，也可以是任何人提醒我）。"] },
    }, HOME_RULE_SPACE)
    rows[#rows + 1] = { key = "home_footer", fullWidth = true }

    local page = {
        id = "home",
        placement = { target = "$container", point = "TOPLEFT", relativePoint = "TOPLEFT",
            width = fullWidth },
        content = { kind = "grid", items = items },
        settingsList = { preserveHeader = false, showDividers = false, rows = rows },
    }

    return {
        version = 1,
        settingsListWidthPercent = 100,
        settingsLayoutBreakpoint = 900,
        cards = { page },
    }
end
local function FindLayoutEntry(layout, key)
    if type(layout) ~= "table" then
        return nil
    end
    local function FindItems(items)
        if type(items) ~= "table" then
            return nil
        end
        for i = 1, #items do
            local item = items[i]
            if item and item.key == key then
                return item
            end
            local found = item and FindItems(item.children)
            if found then
                return found
            end
        end
    end
    if type(layout.cards) == "table" then
        for i = 1, #layout.cards do
            local card = layout.cards[i]
            local found = FindItems(card.content and card.content.items)
            if found then return found end
        end
    end
    return FindItems(layout)
end

local function UpdateLayoutData(layout)
    local db = SyncPageDBFromRuntime()
    local updates = {
        home_main = { opts = { entries = BuildMainEntries(), padBottom = HOME_GAP } },
        localeMode = { items = LOCALE_ITEMS },
    }

    db.localeMode = tostring(ExBoss.GetLocaleMode and ExBoss:GetLocaleMode() or db.localeMode or "AUTO")

    for key, fields in pairs(updates) do
        local item = FindLayoutEntry(layout, key)
        if item then
            for field, value in pairs(fields) do
                item[field] = value
            end
        end
    end
end

local function GetOrBuildLayout()
    if type(pageLayoutData) ~= "table" then
        pageLayoutData = BuildLayout()
    end
    UpdateLayoutData(pageLayoutData)
    return pageLayoutData
end

-- 首页按实际可用宽度排版；Resize 时让原 Grid 重新测量卡片。
local function RelayoutHomeContent(contentFrame)
    if not (contentFrame and scrollChild and cardSession and not cardSession.released) then return end
    scrollChild:SetWidth(math.max(1, contentFrame:GetWidth() - 8))
    cardSession.context.viewportHeight = math.max(1, contentFrame:GetHeight() - 8)
    cardSession:Relayout()
end
local function RenderGrid(contentFrame)
    local Grid = _G.ExwindGrid
    local EXUI = ExwindTools and ExwindTools.UI
    if not (Grid and EXUI and ExwindTools) then
        return false
    end
    layoutGeneration = layoutGeneration + 1
    local generation = layoutGeneration

    RegisterInformationRenderer(Grid)
    local layout = GetOrBuildLayout()
    ExwindTools:RegisterModuleLayout(MODULE_KEY, layout)

    if not scrollChild then
        scrollChild = CreateFrame("Frame", nil, contentFrame)
    end
    if not contentFrame._exBossHomeLayoutHooked then
        contentFrame._exBossHomeLayoutHooked = true
        contentFrame:HookScript("OnSizeChanged", function(self)
            if Page._contentFrame ~= self or not (scrollChild and scrollChild:IsShown()) then return end
            local resizeGeneration = layoutGeneration
            C_Timer.After(0, function()
                if resizeGeneration == layoutGeneration
                    and Page._contentFrame == self and scrollChild:IsShown() then
                    RelayoutHomeContent(self)
                end
            end)
        end)
    end

    if missingDepsText then
        missingDepsText:Hide()
    end

    scrollChild:SetParent(contentFrame)
    scrollChild:ClearAllPoints()
    scrollChild:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 4, -4)
    scrollChild:SetHeight(math.max(1, contentFrame:GetHeight() - 8))
    scrollChild:Show()

    C_Timer.After(0, function()
        if generation ~= layoutGeneration
            or not (scrollChild and scrollChild:IsShown() and Page._contentFrame == contentFrame) then
            return
        end
        local width = contentFrame:GetWidth()
        if width < 100 then
            width = 1380
        end
        scrollChild:SetWidth(math.max(1, width - 8))

        if ExwindTools.UI then
            ExwindTools.UI.ActivePageFrame = scrollChild
            ExwindTools.UI.CurrentModule = MODULE_KEY
        end
        if cardSession and type(cardSession.Release) == "function" then
            cardSession:Release()
            cardSession = nil
        end
        cardSession = Grid:MountCards(scrollChild, layout, {
            pageId = MODULE_KEY,
            regionId = "home",
            config = GetPageDB(),
            moduleKey = MODULE_KEY,
            layoutDefaults = { left = 0, right = 0, top = 0, bottom = 0, gap = CARD_GAP },
            viewportHeight = math.max(1, contentFrame:GetHeight() - 8),
        })
        RelayoutHomeContent(contentFrame)
    end)

    return true
end

RefreshPage = function()
    local contentFrame = Page._contentFrame
    if not contentFrame then
        return
    end

    if RenderGrid(contentFrame) then
        return
    end

    if scrollChild then
        scrollChild:Hide()
    end
    if not missingDepsText then
        missingDepsText = EXUI:CreateVisualFontString(contentFrame, EXFONTFRAME, "GameFontHighlight")
        missingDepsText:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 20, -20)
        missingDepsText:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", -20, 0)
        missingDepsText:SetJustifyH("LEFT")
        missingDepsText:SetJustifyV("TOP")
    end
    missingDepsText:SetText(L["首页依赖 ExwindTools.UI 与 ExwindGrid，当前未就绪。请确认 ExwindCore 已正确加载后重开面板。"])
    missingDepsText:Show()
end

local function RefreshActiveSurfaces()
    local db = GetPageDB()
    local mode = tostring(db.localeMode or "AUTO")
    if ExBoss.SetLocaleMode then
        ExBoss:SetLocaleMode(mode)
    end
end

function Page:Render(contentFrame)
    pageLayoutData = nil
    Page._contentFrame = contentFrame
    SyncPageDBFromRuntime()
    RefreshPage()
end

function Page:Hide()
    layoutGeneration = layoutGeneration + 1
    Page._contentFrame = nil
    if cardSession then
        cardSession:Release()
        cardSession = nil
    end
    if scrollChild then
        scrollChild:Hide()
    end
    if missingDepsText then
        missingDepsText:Hide()
    end
end

if EXUI then
    EXUI:RegisterModuleValueController(MODULE_KEY, {
        RefreshActiveSurfaces = RefreshActiveSurfaces,
    })
end
