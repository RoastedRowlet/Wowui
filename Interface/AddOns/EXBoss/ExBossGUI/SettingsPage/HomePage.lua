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
        zhCN["首页依赖 ExwindTools.UI 与 SettingsV2，当前未就绪。请确认 ExwindCore 已正确加载后重开面板。"] = true
        zhCN["感谢以下人员在插件发展过程中给予的协助。每次打开首页时，上下两组名单均随机排序。感谢不代表本插件支持或反对任何立场。如有遗漏，请私聊我提醒。"] = true
    end
    local enUS = ExBoss.NewLocale and ExBoss:NewLocale("enUS")
    if enUS then
        enUS["隐藏 EXBoss 小地图按钮"] = "Hide EXBoss Minimap Button"
        enUS["首页依赖 ExwindTools.UI 与 SettingsV2，当前未就绪。请确认 ExwindCore 已正确加载后重开面板。"] = "The home page requires ExwindTools.UI and SettingsV2, which are not ready. Make sure ExwindCore is loaded correctly, then reopen the panel."
        enUS["感谢以下人员在插件发展过程中给予的协助。每次打开首页时，上下两组名单均随机排序。感谢不代表本插件支持或反对任何立场。如有遗漏，请私聊我提醒。"] = "Thank you to everyone below for helping develop the addon. Both lists are shuffled each time the home page opens. Acknowledgment does not imply endorsement of any views. Please message me if someone is missing."
    end
end

local MODULE_KEY = "ExBoss.HomePage"

local scrollFrame, scrollChild = nil, nil
local missingDepsText = nil
local RefreshPage = nil
local pageSession = nil
local pageBody, pageTitle, pageSubtitle = nil, nil, nil
local pageHeaderHeight = 0
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
-- 增删人物/资料只改下面的表；人物卡片直接复用 Core 的 PersonCardsRenderer。
local HOME_RESOURCES = {
    { title = L["蓝帖追踪"], description = L["实时追踪魔兽世界蓝帖（中文）。"], url = "https://exwind.net" },
    { title = L["常见问题"], description = L["插件常见问题与使用帮助。"], url = "https://exwind.net/faq/general" },
    { title = L["LSM 音频打包"], description = L["上传音频，自动打包成插件；可在游戏内所有音频选项中使用。"], url = "https://exwind.net/lsm" },
    { title = L["配置原理"], description = L["了解 EXBoss 的配置原理。"], url = "https://exwind.net/exboss/config" },
    { title = L["语音包说明"], description = L["EXBoss 语音包使用说明。"], url = "https://exwind.net/exboss/voices" },
    { title = L["语音包制作"], description = L["制作自己的 EXBoss 语音包。"], url = "https://exwind.net/exboss" },
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

-- 品牌与名单使用 Core 登记的首页自定义件，设置与资源由标准行排版。
local HOME_FONT = GM.font
local HOME_GAP = GM.space.descriptionGap
local HOME_BLOCK_GAP = GM.space.settingsV2Gap
local HOME_CONTACT_ICON = GM.size.homeContactIcon
local HOME_URL_HEIGHT = GM.size.inputHeight
local HOME_INSET_X = 0
local HOME_INSET_Y = GM.space.cardBodyPadding
local HOME_TILE_POOL = "ExBoss.HomeTile"
local HOME_BODY_POOL = "ExBoss.HomeBody"

local function NewText(parent, text, size, color, justify)
    local control = EXUI:CreateDescription(parent, text, GM.size.controlDefaultWidth)
    local region = control.text
    EXUI.ControlAppearance.Font(region, size, color)
    region:SetWordWrap(true)
    region:SetJustifyH(justify or "LEFT")
    region:SetJustifyV("TOP")
    region:SetSpacing(HOME_GAP / 2)
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

local HOME_BLOCKS = {}

HOME_BLOCKS.text = {
    mount = function(host, block, state)
        state.texts = { NewText(host, block.text, HOME_FONT.text, GC.text) }
    end,
    layout = function(host, block, state, width, top)
        PlaceTopLeft(state.texts[1], host, 0, top)
        return MeasureText(state.texts[1], width)
    end,
}

-- 品牌联系资料：三张等宽联系方式（图标 | 名称 说明 / 网址框）。
-- 三张严格等宽，宽度不按网址长短分配；图标用平台色，不画底色方块。
local function LayoutContactColumn(parts, host, x, y, columnWidth)
    local textX = x + HOME_CONTACT_ICON + HOME_BLOCK_GAP
    local textWidth = math.max(1, columnWidth - HOME_CONTACT_ICON - HOME_BLOCK_GAP)
    local titleWidth = math.min(textWidth, math.ceil(parts.title.text:GetUnboundedStringWidth()) + 1)
    local titleHeight = MeasureText(parts.title, titleWidth)
    local descWidth = math.max(1, textWidth - titleWidth - HOME_BLOCK_GAP)
    local descriptionHeight = MeasureText(parts.description, descWidth)
    local headerHeight = math.max(titleHeight, descriptionHeight)
    PlaceTopLeft(parts.title, host, textX, y)
    PlaceTopLeft(parts.description, host, textX + titleWidth + HOME_BLOCK_GAP,
        y + math.max(0, titleHeight - parts.description:GetHeight()))
    parts.url:SetWidth(textWidth)
    PlaceTopLeft(parts.url, host, textX, y + headerHeight + HOME_GAP)
    parts.icon:SetSize(HOME_CONTACT_ICON, HOME_CONTACT_ICON)
    PlaceTopLeft(parts.icon, host, x, y + math.floor((headerHeight + HOME_GAP + HOME_URL_HEIGHT - HOME_CONTACT_ICON) / 2))
    return headerHeight + HOME_GAP + HOME_URL_HEIGHT
end

HOME_BLOCKS.brand = {
    mount = function(host, block, state)
        state.tiles, state.rows, state.texts, state.urls = {}, {}, {}, {}
        for index, item in ipairs(block.contacts) do
            local icon = AcquireTile(host, GC.transparent, GC.transparent)
            SetTileIcon(icon, item.icon, item.brand, HOME_CONTACT_ICON)
            local parts = {
                icon = icon,
                title = NewText(host, item.title, HOME_FONT.title, GC.white),
                description = NewText(host, item.description, HOME_FONT.small, GC.textDim),
                url = EXUI:CreateCopyableUrlBox(host, item.url, GM.settings.controlWideWidth, "urlCompact"),
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
        local y = top
        if width < (GM.settings.controlWideWidth + HOME_CONTACT_ICON + HOME_BLOCK_GAP) * count then
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

local function ReleaseInformationBlocks(host)
    local factory = _G.ExwindFactory
    local body = host._exHomeBody
    for _, item in ipairs(host._exHomeBlocks or {}) do
        local state = item.state
        for _, url in ipairs(state.urls or {}) do EXUI:ReleaseCopyableUrlBox(url) end
        for _, text in pairs(state.texts or {}) do factory:Release(text._fromPool, text) end
        for _, parts in ipairs(state.tiles or {}) do
            if parts.badge then factory:Release(HOME_TILE_POOL, parts.badge) end
            factory:Release(HOME_TILE_POOL, parts.frame)
        end
    end
    host._exHomeBlocks = nil
    if body then
        factory:ReleaseCompositeHost(body)
        host._exHomeBody = nil
    end
end

local function InitializeHomePools()
    _G.ExwindFactory:InitCompositePool(HOME_BODY_POOL)
    _G.ExwindFactory:InitPool(HOME_TILE_POOL, "Frame", "BackdropTemplate", function(tile)
        tile.letterText = EXUI:CreateVisualFontString(tile, _G.EXFONTFRAME, "GameFontHighlight")
        tile.letterText:SetPoint("CENTER")
    end)
end

local function CreateInformationComponent(opts)
    local function Layout(host, width)
        local padTop, padBottom = opts.padTop or HOME_INSET_Y, opts.padBottom or HOME_INSET_Y
        width = math.max(1, width - HOME_INSET_X * 2)
        local body, y = host._exHomeBody, 0
        for _, item in ipairs(host._exHomeBlocks) do
            y = y + HOME_BLOCKS[item.block.kind].layout(body, item.block, item.state, width, y) + HOME_BLOCK_GAP
        end
        y = math.max(1, y - HOME_BLOCK_GAP)
        body:ClearAllPoints()
        body:SetPoint("TOPLEFT", host, "TOPLEFT", HOME_INSET_X, -padTop)
        body:SetSize(width, y)
        return y + padTop + padBottom
    end
    return {
        component = "homeinformation",
        mount = function(host)
            EXUI:SetControlFontStyle(host, "settings")
            host._exHomeBody = _G.ExwindFactory:AcquireCompositeHost(HOME_BODY_POOL, host)
            host._exHomeBlocks = {}
            for _, block in ipairs(opts.entries) do
                local state = {}
                HOME_BLOCKS[block.kind].mount(host._exHomeBody, block, state)
                host._exHomeBlocks[#host._exHomeBlocks + 1] = { block = block, state = state }
            end
            return host
        end,
        update = function() end,
        measure = function(host, _, width) return Layout(host, width) end,
        layout = function(host, _, width) Layout(host, width) end,
        setEnabled = function() end,
        setVisible = function(host, _, visible) host:SetShown(visible) end,
        release = ReleaseInformationBlocks,
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

local function BuildDeclaration()
    local options = {}
    for index, item in ipairs(LOCALE_ITEMS) do
        options[index] = { label = item[1], value = item[2] }
    end
    local resources = {}
    for index, item in ipairs(HOME_RESOURCES) do
        resources[index] = { id = "resource_" .. index, kind = "control", controlType = "input", ref = "resource_" .. index }
    end
    local people = {
        { id = "thanks_people", kind = "component", ref = "thanks_people", custom = "EXBoss.HomePeople" },
    }
    if #HOME_PEOPLE_SECONDARY > 0 then
        people[#people + 1] = { id = "thanks_people_secondary", kind = "component",
            ref = "thanks_people_secondary", custom = "EXBoss.HomePeople" }
    end
    return { version = 2, cards = {
        { id = "home", kind = "card", title = L["社区交流与反馈"], children = {
            { id = "home_main", kind = "component", ref = "home_main", custom = "EXBoss.HomeBrand" },
        } },
        { id = "language", kind = "card", title = L["界面语言"], children = {
            { id = "locale_row", kind = "setting", label = L["界面语言"], children = {
                { id = "localeMode", kind = "control", controlType = "select", path = "localeMode",
                    options = options, search = true, size = "wide" },
                { id = "btn_reload_ui", kind = "button", text = L["立即重载界面"], action = "reload_ui" },
            } },
        } },
        { id = "resources", kind = "card", title = L["官方资源"], children = resources },
        { id = "thanks", kind = "card", title = L["感谢每一份协助"], children = people },
    } }
end

local function CreatePeopleComponent()
    local renderer = EXUI.PersonCardsRenderer
    local opts = { layout = "portrait", surface = "plain", columns = #HOME_PEOPLE, minColumnWidth = GM.size.controlDefaultWidth,
        columnGap = HOME_BLOCK_GAP, rowGap = HOME_BLOCK_GAP, people = ShuffledPeople(HOME_PEOPLE),
        avatarSize = GM.size.homeThanksAvatar,
        avatarRing = { texture = "Interface\\AddOns\\ExwindCore\\Textures\\Materials\\GUI\\HomeAvatarRing.tga",
            texCoords = { 0, 0.5625, 0, 0.5625 } },
        padX = HOME_INSET_X, padTop = HOME_BLOCK_GAP, padBottom = 0 }
    -- 直接复用 Core 人物卡实现；V2 owner 提供其资料与测量上下文。
    local renderContext = { element = { opts = opts }, SetContentHeight = function() end }
    return {
        component = "personcards",
        mount = function(host)
            renderer.mount(host, renderContext)
            return host
        end,
        update = function(host) renderer.update(host) end,
        measure = function(host, _, width) return renderer.layout(host, renderContext, width) end,
        layout = function(host, _, width) renderer.layout(host, renderContext, width) end,
        setEnabled = function() end,
        setVisible = function(host, _, visible) host:SetShown(visible) end,
        release = renderer.release,
    }
end

local function CreatePageOwner()
    local owner = {
        binding = { moduleKey = MODULE_KEY, config = SyncPageDBFromRuntime() },
        components = {}, controls = {},
        actions = { reload_ui = function() ReloadUI() end },
        onHeightChanged = function(height)
            pageBody:SetHeight(height)
            scrollChild:SetHeight(height + pageHeaderHeight)
        end,
    }
    owner.components.home_main = CreateInformationComponent({ entries = {
        { kind = "brand", contacts = HOME_CONTACTS },
    } })
    owner.components.thanks_people = CreatePeopleComponent()
    if #HOME_PEOPLE_SECONDARY > 0 then
        local names = {}
        for index, person in ipairs(ShuffledPeople(HOME_PEOPLE_SECONDARY)) do names[index] = person.name end
        owner.components.thanks_people_secondary = CreateInformationComponent({ entries = {
            { kind = "text", text = L["同样感谢"] .. "：" .. table.concat(names, "   ·   ") },
        } })
    end
    -- 资源网址用标准输入适配器呈现，只允许选中复制，不写入配置。
    for index, item in ipairs(HOME_RESOURCES) do
        local adapter = EXUI:CreateSettingsV2Control({ controlType = "input", size = "wide", label = item.title,
            description = item.description .. (index == 1 and ("\n" .. L["除「蓝帖追踪」外，其余资源均提供多语言版本。"]) or ""),
        }, function()
            return { Read = function() return item.url end, Write = function() end }
        end)
        local mount, release = adapter.mount, adapter.release
        adapter.mount = function(host, context)
            local widget = mount(host, context)
            widget:SetScript("OnTextChanged", function(self)
                if self:GetText() ~= item.url then self:SetText(item.url); self:HighlightText() end
            end)
            widget:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
            widget:SetScript("OnMouseUp", function(self) self:HighlightText() end)
            return widget
        end
        adapter.release = function(widget, context)
            widget:SetScript("OnTextChanged", nil)
            widget:SetScript("OnEditFocusGained", nil)
            widget:SetScript("OnMouseUp", nil)
            release(widget, context)
        end
        owner.controls["resource_" .. index] = adapter
    end
    return owner
end

local function RelayoutHomeContent(contentFrame)
    if not (contentFrame and scrollChild and pageSession and pageSession.alive) then return end
    local width = math.max(1, scrollFrame:GetWidth() - GM.space.settingsV2Gap)
    scrollChild:SetWidth(width)
    local inset = GM.space.settingsV2Padding
    local textWidth = math.max(1, width - inset * 2)
    PlaceTopLeft(pageTitle, scrollChild, inset, inset)
    local titleHeight = MeasureText(pageTitle, textWidth)
    PlaceTopLeft(pageSubtitle, scrollChild, inset, inset + titleHeight + HOME_GAP)
    pageHeaderHeight = inset + titleHeight + HOME_GAP + MeasureText(pageSubtitle, textWidth) + HOME_BLOCK_GAP
    pageBody:ClearAllPoints()
    pageBody:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -pageHeaderHeight)
    pageBody:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, -pageHeaderHeight)
    scrollChild:SetHeight(pageSession:GetHeight() + pageHeaderHeight)
    pageSession:Invalidate()
end

local function RenderV2(contentFrame)
    if not (EXUI and EXUI.MountSettingsPageV2 and EXUI.PersonCardsRenderer and ExwindTools) then
        return false
    end
    if pageSession and pageSession.alive then
        pageSession:Refresh()
        RelayoutHomeContent(contentFrame)
        return true
    end
    layoutGeneration = layoutGeneration + 1
    local generation = layoutGeneration

    if not scrollChild then
        scrollFrame = EXUI:CreateScrollFrame(contentFrame)
        scrollChild = CreateFrame("Frame", nil, scrollFrame)
        scrollChild:SetHeight(GM.size.controlHeight)
        scrollFrame:SetScrollChild(scrollChild)
        pageBody = CreateFrame("Frame", nil, scrollChild)
        pageBody:SetPoint("TOPLEFT")
        pageBody:SetPoint("TOPRIGHT")
        pageTitle = NewText(scrollChild, "EXBoss", HOME_FONT.pageTitle, GC.accent)
        pageSubtitle = NewText(scrollChild,
            L["副本首领时间轴、语音提示、团队框架发光与配置方案。"] .. "\n"
            .. L["感谢以下人员在插件发展过程中给予的协助。每次打开首页时，上下两组名单均随机排序。感谢不代表本插件支持或反对任何立场。如有遗漏，请私聊我提醒。"] .. "\n"
            .. L["声明：可能还有很多英语/外语主播介绍并协助人们了解插件，我并没有长期活跃于英语主播圈子，所以很可能遗漏，这点非常抱歉。如果发生该情况可以随时私信我（不一定要主播本人，也可以是任何人提醒我）。"],
            HOME_FONT.hint, GC.textDim)
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

    if missingDepsText then missingDepsText:Hide() end
    scrollFrame:SetParent(contentFrame)
    scrollFrame:ClearAllPoints()
    scrollFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", GM.space.compactButtonPaddingX, -GM.space.compactButtonPaddingX)
    scrollFrame:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -scrollFrame:GetVerticalScrollInset(), 0)
    scrollFrame:SetVerticalScroll(0)
    scrollFrame:Show()
    scrollChild:ClearAllPoints()
    scrollChild:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT")
    scrollChild:Show()

    C_Timer.After(0, function()
        if generation ~= layoutGeneration
            or not (scrollChild and scrollChild:IsShown() and Page._contentFrame == contentFrame) then return end
        local width = scrollFrame:GetWidth()
        scrollChild:SetWidth(math.max(1, width - GM.space.settingsV2Gap))
        local owner = CreatePageOwner()
        local session, issue = EXUI:MountSettingsPageV2(pageBody, MODULE_KEY, owner)
        if not session then error(issue.message, 0) end
        pageSession = session
        scrollChild._exV2Owner = owner
        scrollChild._exV2Session = session
        EXUI.ActivePageFrame = scrollChild
        EXUI.CurrentModule = MODULE_KEY
        RelayoutHomeContent(contentFrame)
    end)
    return true
end

RefreshPage = function()
    local contentFrame = Page._contentFrame
    if not contentFrame then return end
    if RenderV2(contentFrame) then return end
    if scrollChild then scrollChild:Hide() end
    if scrollFrame then scrollFrame:Hide() end
    if not missingDepsText then
        missingDepsText = EXUI:CreateVisualFontString(contentFrame, EXFONTFRAME, "GameFontHighlight")
        missingDepsText:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", GM.settings.rowPaddingX, -GM.settings.rowPaddingX)
        missingDepsText:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", -GM.settings.rowPaddingX, 0)
        missingDepsText:SetJustifyH("LEFT")
        missingDepsText:SetJustifyV("TOP")
    end
    missingDepsText:SetText(L["首页依赖 ExwindTools.UI 与 SettingsV2，当前未就绪。请确认 ExwindCore 已正确加载后重开面板。"])
    missingDepsText:Show()
end

local function RefreshActiveSurfaces()
    local db = GetPageDB()
    local mode = tostring(db.localeMode or "AUTO")
    if ExBoss.SetLocaleMode then ExBoss:SetLocaleMode(mode) end
    local page = scrollChild and EXUI:GetModulePage(MODULE_KEY, pageBody)
    if page then page:Refresh() end
end

function Page:Render(contentFrame)
    if Page._contentFrame and Page._contentFrame ~= contentFrame then self:Hide() end
    Page._contentFrame = contentFrame
    SyncPageDBFromRuntime()
    RefreshPage()
end

function Page:Hide()
    layoutGeneration = layoutGeneration + 1
    Page._contentFrame = nil
    if pageSession then
        pageSession:Release()
        pageSession = nil
    end
    if scrollChild then
        scrollChild._exV2Session = nil
        scrollChild._exV2Owner = nil
        if EXUI.ActivePageFrame == scrollChild then
            EXUI.ActivePageFrame = nil
            EXUI.CurrentModule = nil
        end
        scrollChild:Hide()
    end
    if scrollFrame then scrollFrame:Hide() end
    if missingDepsText then missingDepsText:Hide() end
end

if EXUI then
    InitializeHomePools()
    EXUI:RegisterSettingsPageV2(MODULE_KEY, BuildDeclaration())
    EXUI:RegisterModuleValueController(MODULE_KEY, {
        RefreshActiveSurfaces = RefreshActiveSurfaces,
    })
end
