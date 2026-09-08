-- =============================================================
-- [[ 聊天频道快捷栏 ]]
-- 唯一 Renderer：BuildPresentation -> ApplyPresentation -> IconCollection。
-- runtime 的频道动作由 Core runtimeAction 承担；world/panel 永不拥有项目输入。
-- =============================================================
local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI, L = ExwindTools.UI, ExwindTools.L or setmetatable({}, { __index = function(_, key) return key end })
local EXWIND_MODULE_KEY = "ExTools.ChatChannelBar"

-- x/y 是频道栏唯一正式的世界锚点资料。面板样本永不读取它们；运行时与
-- 世界编辑则由同一 AnchorController 读写，不能存在第二套实际位置。
local DEFAULTS = {
    enabled = true,
    buttonPadding = 3,
    buttonSize = 30,
    x = 46,
    y = 207,
    attachToCustom = false,
    customAttachTarget = "",
    font_style = { font = "默认", size = 16, r = 1, g = 1, b = 1, a = 1, autoWidth = false, justifyH = "CENTER", justifyV = "MIDDLE", outline = "OUTLINE", shadow = false, shadowX = 1, shadowY = -1 },
}
local CHANNELS = {
    { id = "world", name = L["世"], command = "/1", isWorld = true, show = true, r = 1, g = .5, b = .5, channel = "大脚世界频道" }, { id = "say", name = L["说"], command = "/s", show = true },
    { id = "yell", name = L["喊"], command = "/y", show = true, r = 1, g = .25, b = .25 }, { id = "party", name = L["队"], command = "/p", show = true, r = .67, g = .67, b = 1 },
    { id = "guild", name = L["会"], command = "/g", show = true, r = .25, g = 1, b = .25 }, { id = "instance", name = L["副"], command = "/i", show = true, r = 1, g = .5, b = 0 },
    { id = "raid", name = L["团"], command = "/raid", show = true, r = 1, g = .5, b = 0 }, { id = "roll", name = L["骰"], command = "/roll", isCommand = true, show = true, r = 1, g = 1, b = 0 },
    { id = "rc", name = L["确"], command = "/rc", isCommand = true, show = true, r = 0, g = 1, b = 1 }, { id = "pull", name = L["倒"], command = "/cd 10", isCommand = true, show = true, r = 1, g = 0, b = 1 },
    { id = "custom1", name = L["自1"], isCommand = true, show = false }, { id = "custom2", name = L["自2"], isCommand = true, show = false }, { id = "custom3", name = L["自3"], isCommand = true, show = false },
}
for _, channel in ipairs(CHANNELS) do
    DEFAULTS["show_" .. channel.id] = channel.show; DEFAULTS[channel.id .. "R"] = channel.r or 1; DEFAULTS[channel.id .. "G"] =
        channel.g or 1; DEFAULTS[channel.id .. "B"] = channel.b or 1
    DEFAULTS[channel.id .. "_name"] = ""; DEFAULTS[channel.id .. "_channel"] = channel.channel or channel.command or ""
end

-- Grid 只导出已声明的 ModuleDB 字段。频道默认值有一部分由 CHANNELS 生成，
-- 因此在生成完成后登记一次；导入工具只替换这张覆盖表，不触碰频道业务或布局。
local DEFAULTS_EXPORT_OVERRIDES = {
            attachToCustom = false,
            buttonPadding = 3,
            buttonSize = 30,
            custom1B = 1,
            custom1G = 1,
            custom1R = 1,
            custom1_channel = "",
            custom1_name = "",
            custom2B = 1,
            custom2G = 1,
            custom2R = 1,
            custom2_channel = "",
            custom2_name = "",
            custom3B = 1,
            custom3G = 1,
            custom3R = 1,
            custom3_channel = "",
            custom3_name = "",
            customAttachTarget = "",
            enabled = true,
            font_style = {
                a = 1,
                autoWidth = false,
                b = 1,
                enabled = true,
                fixedWidth = 200,
                font = "默认",
                g = 1,
                gradientEnabled = false,
                gradientLength = 0,
                gradientStart = 0,
                justifyH = "CENTER",
                justifyV = "MIDDLE",
                maxWidth = 0,
                outline = "OUTLINE",
                r = 1,
                rotation = 0,
                shadow = false,
                shadowColorA = 1,
                shadowColorB = 0,
                shadowColorG = 0,
                shadowColorR = 0,
                shadowX = 1,
                shadowY = -1,
                size = 16,
                x = 0,
                y = 0,
            },
            guildB = 0.25,
            guildG = 1,
            guildR = 0.25,
            guild_channel = "/g",
            guild_name = "",
            instanceB = 0,
            instanceG = 0.5,
            instanceR = 1,
            instance_channel = "/i",
            instance_name = "",
            partyB = 1,
            partyG = 0.67,
            partyR = 0.67,
            party_channel = "/p",
            party_name = "",
            pullB = 1,
            pullG = 0,
            pullR = 1,
            pull_channel = "/cd 10",
            pull_name = "",
            raidB = 0,
            raidG = 0.5,
            raidR = 1,
            raid_channel = "/raid",
            raid_name = "",
            rcB = 1,
            rcG = 1,
            rcR = 0,
            rc_channel = "/rc",
            rc_name = "",
            rollB = 0,
            rollG = 1,
            rollR = 1,
            roll_channel = "/roll",
            roll_name = "",
            sayB = 1,
            sayG = 1,
            sayR = 1,
            say_channel = "/s",
            say_name = "",
            show_custom1 = false,
            show_custom2 = false,
            show_custom3 = false,
            show_guild = true,
            show_instance = true,
            show_party = true,
            show_pull = true,
            show_raid = true,
            show_rc = true,
            show_roll = true,
            show_say = true,
            show_world = true,
            show_yell = true,
            worldB = 0.5,
            worldG = 0.5,
            worldR = 1,
            world_channel = "大脚世界频道",
            world_name = "",
            x = 19,
            y = 386,
            yellB = 0.25,
            yellG = 0.25,
            yellR = 1,
            yell_channel = "/y",
            yell_name = "",
        }
for key, value in pairs(DEFAULTS_EXPORT_OVERRIDES) do DEFAULTS[key] = value end
ExwindTools:DeclareModuleSpecDefaults(EXWIND_MODULE_KEY, { root = DEFAULTS })

local EnsureAnchorController

-- 频道栏的整体锚点只有 root DB 的 x/y、attachToCustom、customAttachTarget。
-- 运行时 point 固定 BOTTOMLEFT；relative point 由 AnchorController 按是否依附
-- 合法目标决定为 BOTTOMLEFT/TOPLEFT，故不能另造 point/relativePoint 数据字段。
local function PickChatChannelBarAnchor()
    return EnsureAnchorController():StartFramePicker()
end

local CHAT_CHANNEL_BAR_ANCHOR_OPTS = {
    bindRoot = true,
    offsetXKey = "x",
    offsetYKey = "y",
    defaultOffsetX = DEFAULTS.x,
    defaultOffsetY = DEFAULTS.y,
    attachEnabledKey = "attachToCustom",
    attachTargetKey = "customAttachTarget",
    onPickFrame = PickChatChannelBarAnchor,
}

local function RegisterLayout()
    local layout = {
        { key = "header", type = "header", x = 1, y = 1, w = 200, h = 6, label = L["聊天频道快捷栏"], labelSize = 25 },
        { key = "sub_basic", type = "subheader", x = 1, y = 9, w = 200, h = 6, label = L["通用设置"], labelSize = 20 },
        { key = "enabled", type = "checkbox", x = 1, y = 17, w = 46, h = 6, label = L["启用"] },
        { key = "btn_reset_pos", type = "button", x = 51, y = 17, w = 46, h = 6, label = L["重置位置"] },
        { key = "buttonPadding", type = "slider", x = 1, y = 30, w = 46, h = 6, label = L["按钮间距"], min = 0, max = 20, step = 1 },
        { key = "buttonSize", type = "slider", x = 51, y = 30, w = 46, h = 6, label = L["按钮大小"], min = 20, max = 50, step = 1 },
        { key = "x", type = "slider", x = 101, y = 30, w = 46, h = 6, label = "X", min = -1200, max = 1200, step = 1 },
        { key = "y", type = "slider", x = 151, y = 30, w = 46, h = 6, label = "Y", min = -1000, max = 1000, step = 1 },
        -- 与 TimerBarPage 相同的标准锚点组：直接绑定 root ModuleDB，选择器
        -- 调用同一 AnchorController，不能再由散装依附下拉覆盖 picker 的结果。
        { key = "anchor", type = "anchorgroup", x = 1, y = 40, w = 200, h = 18, measure = true, label = L["锚点设置"], opts = CHAT_CHANNEL_BAR_ANCHOR_OPTS },
        { key = "channels", type = "header", x = 1, y = 58, w = 200, h = 6, label = L["频道设置"], labelSize = 20 },
        { key = "channel_world_enabled", type = "checkbox", x = 1, y = 70, w = 46, h = 6, label = L["世"], setKey = "show_world" },
        { key = "channel_world_name", type = "input", x = 51, y = 70, w = 46, h = 6, label = L["文字"], setKey = "world_name", labelPos = "top" },
        { key = "channel_world_command", type = "input", x = 101, y = 70, w = 46, h = 6, label = L["频道/命令"], setKey = "world_channel", labelPos = "top" },
        { key = "world", type = "color", x = 151, y = 70, w = 46, h = 6, label = L["颜色"] },
        { key = "channel_say_enabled", type = "checkbox", x = 1, y = 80, w = 46, h = 6, label = L["说"], setKey = "show_say" },
        { key = "channel_say_name", type = "input", x = 51, y = 80, w = 46, h = 6, label = L["文字"], setKey = "say_name", labelPos = "top" },
        { key = "channel_say_command", type = "input", x = 101, y = 80, w = 46, h = 6, label = L["频道/命令"], setKey = "say_channel", labelPos = "top" },
        { key = "say", type = "color", x = 151, y = 80, w = 46, h = 6, label = L["颜色"] },
        { key = "channel_yell_enabled", type = "checkbox", x = 1, y = 90, w = 46, h = 6, label = L["喊"], setKey = "show_yell" },
        { key = "channel_yell_name", type = "input", x = 51, y = 90, w = 46, h = 6, label = L["文字"], setKey = "yell_name", labelPos = "top" },
        { key = "channel_yell_command", type = "input", x = 101, y = 90, w = 46, h = 6, label = L["频道/命令"], setKey = "yell_channel", labelPos = "top" },
        { key = "yell", type = "color", x = 151, y = 90, w = 46, h = 6, label = L["颜色"] },
        { key = "channel_party_enabled", type = "checkbox", x = 1, y = 100, w = 46, h = 6, label = L["队"], setKey = "show_party" },
        { key = "channel_party_name", type = "input", x = 51, y = 100, w = 46, h = 6, label = L["文字"], setKey = "party_name", labelPos = "top" },
        { key = "channel_party_command", type = "input", x = 101, y = 100, w = 46, h = 6, label = L["频道/命令"], setKey = "party_channel", labelPos = "top" },
        { key = "party", type = "color", x = 151, y = 100, w = 46, h = 6, label = L["颜色"] },
        { key = "channel_guild_enabled", type = "checkbox", x = 1, y = 110, w = 46, h = 6, label = L["会"], setKey = "show_guild" },
        { key = "channel_guild_name", type = "input", x = 51, y = 110, w = 46, h = 6, label = L["文字"], setKey = "guild_name", labelPos = "top" },
        { key = "channel_guild_command", type = "input", x = 101, y = 110, w = 46, h = 6, label = L["频道/命令"], setKey = "guild_channel", labelPos = "top" },
        { key = "guild", type = "color", x = 151, y = 110, w = 46, h = 6, label = L["颜色"] },
        { key = "channel_instance_enabled", type = "checkbox", x = 1, y = 120, w = 46, h = 6, label = L["副"], setKey = "show_instance" },
        { key = "channel_instance_name", type = "input", x = 51, y = 120, w = 46, h = 6, label = L["文字"], setKey = "instance_name", labelPos = "top" },
        { key = "channel_instance_command", type = "input", x = 101, y = 120, w = 46, h = 6, label = L["频道/命令"], setKey = "instance_channel", labelPos = "top" },
        { key = "instance", type = "color", x = 151, y = 120, w = 46, h = 6, label = L["颜色"] },
        { key = "channel_raid_enabled", type = "checkbox", x = 1, y = 130, w = 46, h = 6, label = L["团"], setKey = "show_raid" },
        { key = "channel_raid_name", type = "input", x = 51, y = 130, w = 46, h = 6, label = L["文字"], setKey = "raid_name", labelPos = "top" },
        { key = "channel_raid_command", type = "input", x = 101, y = 130, w = 46, h = 6, label = L["频道/命令"], setKey = "raid_channel", labelPos = "top" },
        { key = "raid", type = "color", x = 151, y = 130, w = 46, h = 6, label = L["颜色"] },
        { key = "channel_roll_enabled", type = "checkbox", x = 1, y = 140, w = 46, h = 6, label = L["骰"], setKey = "show_roll" },
        { key = "channel_roll_name", type = "input", x = 51, y = 140, w = 46, h = 6, label = L["文字"], setKey = "roll_name", labelPos = "top" },
        { key = "channel_roll_command", type = "input", x = 101, y = 140, w = 46, h = 6, label = L["频道/命令"], setKey = "roll_channel", labelPos = "top" },
        { key = "roll", type = "color", x = 151, y = 140, w = 46, h = 6, label = L["颜色"] },
        { key = "channel_rc_enabled", type = "checkbox", x = 1, y = 150, w = 46, h = 6, label = L["确"], setKey = "show_rc" },
        { key = "channel_rc_name", type = "input", x = 51, y = 150, w = 46, h = 6, label = L["文字"], setKey = "rc_name", labelPos = "top" },
        { key = "channel_rc_command", type = "input", x = 101, y = 150, w = 46, h = 6, label = L["频道/命令"], setKey = "rc_channel", labelPos = "top" },
        { key = "rc", type = "color", x = 151, y = 150, w = 46, h = 6, label = L["颜色"] },
        { key = "channel_pull_enabled", type = "checkbox", x = 1, y = 160, w = 46, h = 6, label = L["倒"], setKey = "show_pull" },
        { key = "channel_pull_name", type = "input", x = 51, y = 160, w = 46, h = 6, label = L["文字"], setKey = "pull_name", labelPos = "top" },
        { key = "channel_pull_command", type = "input", x = 101, y = 160, w = 46, h = 6, label = L["频道/命令"], setKey = "pull_channel", labelPos = "top" },
        { key = "pull", type = "color", x = 151, y = 160, w = 46, h = 6, label = L["颜色"] },
        { key = "channel_custom1_enabled", type = "checkbox", x = 1, y = 170, w = 46, h = 6, label = L["自1"], setKey = "show_custom1" },
        { key = "channel_custom1_name", type = "input", x = 51, y = 170, w = 46, h = 6, label = L["文字"], setKey = "custom1_name", labelPos = "top" },
        { key = "channel_custom1_command", type = "input", x = 101, y = 170, w = 46, h = 6, label = L["频道/命令"], setKey = "custom1_channel", labelPos = "top" },
        { key = "custom1", type = "color", x = 151, y = 170, w = 46, h = 6, label = L["颜色"] },
        { key = "channel_custom2_enabled", type = "checkbox", x = 1, y = 180, w = 46, h = 6, label = L["自2"], setKey = "show_custom2" },
        { key = "channel_custom2_name", type = "input", x = 51, y = 180, w = 46, h = 6, label = L["文字"], setKey = "custom2_name", labelPos = "top" },
        { key = "channel_custom2_command", type = "input", x = 101, y = 180, w = 46, h = 6, label = L["频道/命令"], setKey = "custom2_channel", labelPos = "top" },
        { key = "custom2", type = "color", x = 151, y = 180, w = 46, h = 6, label = L["颜色"] },
        { key = "channel_custom3_enabled", type = "checkbox", x = 1, y = 190, w = 46, h = 6, label = L["自3"], setKey = "show_custom3" },
        { key = "channel_custom3_name", type = "input", x = 51, y = 190, w = 46, h = 6, label = L["文字"], setKey = "custom3_name", labelPos = "top" },
        { key = "channel_custom3_command", type = "input", x = 101, y = 190, w = 46, h = 6, label = L["频道/命令"], setKey = "custom3_channel", labelPos = "top" },
        { key = "custom3", type = "color", x = 151, y = 190, w = 46, h = 6, label = L["颜色"] },
        { key = "font_style", type = "fontgroup", x = 1, y = 202, w = 200, h = 50, label = L["频道文字"], labelSize = 20,
          opts = {} },
    }
    ExwindTools:RegisterModuleLayout(EXWIND_MODULE_KEY, layout)
end
local EX_DB = ExwindTools:GetModuleDB(EXWIND_MODULE_KEY)
local function DB() return EX_DB end
local function Trim(value) return string.gsub(tostring(value or ""), "^%s*(.-)%s*$", "%1") end

local anchorFrame, anchorController, runtimeCollection, worldCollection, panelPreview, panelDock
local worldPreviewActive = false
EnsureAnchorController = function()
    if anchorController then return anchorController end
    anchorController = ExwindTools:CreateAnchorController({
        moduleKey = EXWIND_MODULE_KEY,
        frameName = "ExChatChannelBarAnchor",
        title = L["聊天频道快捷栏"],
        getDB = DB,
        offsetXKey = "x",
        offsetYKey = "y",
        defaultOffsetX = DEFAULTS.x,
        defaultOffsetY = DEFAULTS.y,
        syncWidgets = { "x", "y" },
        widgetRanges = { x = { min = -1200, max = 1200, step = 1 }, y = { min = -1000, max = 1000, step = 1 } },
        attachEnabledKey = "attachToCustom",
        attachTargetKey = "customAttachTarget",
        anchorPoint = "BOTTOMLEFT",
        getRelativePoint = function(self) return self:IsAttachEnabled() and "TOPLEFT" or "BOTTOMLEFT" end,
        clampedToScreen = true,
        onPositionSaved = function()
            -- 世界编辑只保存同一份 ModuleDB；当前设置页随后必须回读它，而不能
            -- 留下旧的 x/y Slider 数值。
            if EXUI.CurrentModule ~= EXWIND_MODULE_KEY then return end
            if EXUI.MainFrame and EXUI.MainFrame:IsShown() and type(EXUI.RefreshContent) == "function" then
                -- x/y 是普通 Grid Slider，不是复合组；按 RangeCheck 的正式页面
                -- 重绘路径回读，避免只回读一部分组合控件。
                EXUI:RefreshContent()
            end
        end
    })
    return anchorController
end
local function EnsureAnchor()
    if not anchorFrame then anchorFrame = EnsureAnchorController():Ensure() end; EnsureAnchorController():ApplyPosition(); return
        anchorFrame
end

local function FindSlashHandler(slash)
    if type(slash) ~= "string" or slash == "" then return nil end
    slash = slash:upper()
    local handler = _G.hash_SlashCmdList and _G.hash_SlashCmdList[slash]
    if type(handler) == "function" then return handler end

    -- LoadOnDemand/late-loaded AddOns can register after Blizzard has built
    -- hash_SlashCmdList.  Their live handler remains in SlashCmdList until the
    -- next hash rebuild, so resolve aliases there as a compatibility fallback.
    for key, candidate in pairs(_G.SlashCmdList or {}) do
        if type(candidate) == "function" then
            local index = 1
            while true do
                local registered = _G["SLASH_" .. tostring(key) .. index]
                if not registered then break end
                if tostring(registered):upper() == slash then return candidate end
                index = index + 1
            end
        end
    end
    return nil
end

local function Execute(channel)
    local raw = Trim(DB()[channel.id .. "_channel"]); if raw == "" then raw = channel.command or "" end
    if channel.isWorld and raw ~= "" and not raw:match("^/") then
        local id = _G.GetChannelName and _G.GetChannelName(raw); if id and id > 0 and _G.ChatFrame_OpenChat then
            _G.ChatFrame_OpenChat("/" .. id .. " "); return
        end
    end
    if raw ~= "" and not raw:match("^/") then raw = "/" .. raw end
    if channel.isCommand then
        local slash, args = raw:match("^(/[^%s]+)%s*(.*)")
        -- 启动阶段优先使用暴雪生成的 hash；对后加载插件，再扫描仍保留在
        -- SlashCmdList 中的别名。只调用已注册的非安全 handler；受保护命令
        -- 不能由插件伪造执行。
        local handler = FindSlashHandler(slash)
        if type(handler) == "function" then
            local ok = pcall(handler, args or "")
            if ok then return end
        end
        if _G.UIErrorsFrame then _G.UIErrorsFrame:AddMessage("命令未注册或不能由插件直接执行", 1, .2, .2) end
        return
    end
    if _G.ChatFrame_OpenChat then _G.ChatFrame_OpenChat(raw .. " ") end
end
local function Label(channel)
    local value = Trim(DB()[channel.id .. "_name"]); if value == "" then return channel.name end
    return value:sub(1, 3)
end
local function BuildPresentation(sample)
    local db, style = DB(), DB().font_style or DEFAULTS.font_style
    local entries = {}
    for _, channel in ipairs(CHANNELS) do
        entries[#entries + 1] = {
            channel = channel,
            shown = sample or db["show_" .. channel.id] == true,
            label = Label(channel),
            r = db[channel.id .. "R"] or 1,
            g = db[channel.id .. "G"] or 1,
            b = db[channel.id .. "B"] or 1,
        }
    end
    local size = math.max(20, tonumber(db.buttonSize) or 30)
    return {
        entries = entries,
        -- IconCollection 的 FLOW Body 是频道按钮本身；一份 presentation 内
        -- 每个按钮显式共用这组尺寸，不能由各 item 的最终 Frame 量测决定。
        bodySize = { width = size, height = size },
        size = size,
        padding = math.max(0, tonumber(db.buttonPadding) or 3),
        font = style,
    }
end
-- 频道文字必须落在 Icon Body 内：runtimeAction 的正式业务按钮覆盖 Body，不能
-- 让可见文字排到 Body 之外后再人为把子按钮拉出父命中范围。这里仍用同一份
-- 字体资料声明 line box，三宿主随后都把 label 锚到 Body 正中心。
local function GetLabelLineHeight(font)
    local fontSize = math.max(1, math.ceil(tonumber(font and font.size) or 14))
    local outline = tostring(font and font.outline or ""):upper()
    local outlinePadding = outline == "THICKOUTLINE" and 2 or (outline ~= "" and 1 or 0)
    local shadowPadding = font and font.shadow == true and math.abs(tonumber(font.shadowY) or 0) or 0
    -- IconWidget 旧的默认 label line box 是 20；保留它作为下限，同时把用户更大
    -- 的字体/描边/阴影完整纳入声明与实际 TextWidget Bounds。
    return math.max(20, fontSize + outlinePadding * 2 + shadowPadding * 2)
end

-- label 的正式锚点是 Icon Body 中心；缩放 TextWidget root 时维持同一中心，
-- runtime hover 不会向下偏移。
local function SetRuntimeLabelScale(item, scale)
    local label = item and item.widget and item.widget.labelText
    if not label then return end
    scale = tonumber(scale) or 1
    label:SetScale(scale)
    label:SetAnchor("CENTER", label:GetParent(), "CENTER")
end

-- IconWidget 的通用 label 默认排在 icon 下方，适用于普通图标说明；频道栏的
-- Icon 本身完全隐藏，文字就是可点击主体，故必须在每次 Apply 后把同一 label
-- 放回 Body 中心。Panel 的局部意图层以 label 为 parent，会跟随这一正式锚点；
-- world 没有 runtimeAction，仍只由 AnchorController 接管整体拖动。
local function BindChannelLabelToBody(item)
    local label = item and item.widget and item.widget.labelText
    if not label then return end
    label:SetScale(1)
    label:SetAnchor("CENTER", label:GetParent(), "CENTER")
end

local function BuildItem(entry, p)
    local size = p.bodySize.width
    local lineHeight = GetLabelLineHeight(p.font)
    return {
        style = { icon = { width = size, height = size, showIcon = false, showBorder = false }, text = { label = { font = p.font.font, size = p.font.size, outline = p.font.outline, r = entry.r, g = entry.g, b = entry.b, a = 1, shadow = p.font.shadow, shadowX = p.font.shadowX, shadowY = p.font.shadowY, justifyH = "CENTER", justifyV = "MIDDLE", unboundedWidth = true, height = lineHeight } } },
        coreLayout = { label = { bounds = { width = size, height = lineHeight }, anchor = { point = "CENTER", relativeElement = "core.root", relativePoint = "CENTER" } } },
        bodySize = p.bodySize,
        label = entry.label,
        declaredBounds = { left = -size / 2, right = size / 2, bottom = -size / 2, top = size / 2 },
        -- runtime 与 panel 由 Collection 的 interactionMode 分流：前者保留频道
        -- 鼠标业务，后者仅派发静态预览意图，绝不能执行聊天命令。
        runtimeAction = {
            -- 频道栏唯一可见内容是 Body 中心的 label。hover 只放大实际文字，
            -- 不给隐藏 Icon 改 alpha，以免出现看似无反馈的假交互。
            onEnter = function(item) SetRuntimeLabelScale(item, 1.20) end,
            onLeave = function(item) SetRuntimeLabelScale(item, 1) end,
            onDown = function(item) SetRuntimeLabelScale(item, 1.05) end,
            onUp = function(item) SetRuntimeLabelScale(item, 1.20) end,
            onClick = function() Execute(entry.channel) end,
        },
        -- Panel 的命中/选取框绑定同一文字 slot；runtime 使用 IconCollection
        -- runtimeAction 的唯一正式入口，覆盖文字所在的 Icon Body。
        interaction = { slots = { ["core.label"] = { textRole = "label", movable = false, guiTarget = "channel_" .. entry.channel.id .. "_name", tooltip = L["频道按钮"] } } },
    }
end
local function ApplyPresentation(collection, p)
    local items = {}; for i, entry in ipairs(p.entries) do
        local item = collection:AcquireItem("channel-" .. entry.channel.id); collection:ApplyItem(item,
            BuildItem(entry, p)); BindChannelLabelToBody(item)
        if entry.shown then items[#items + 1] = item end
    end
    collection:SetItems(items, { mode = "FLOW", direction = "RIGHT", spacing = p.padding, maxVisible = #items })
    return collection
end
local function RenderPanelPresentation(p)
    if not panelPreview then return end
    if panelDock then panelDock:SetBackdropColor(0.5804, 0.6471, 0.9882, 1) end
    local entries = {}
    for _, entry in ipairs(p.entries) do
        entries[#entries + 1] = { itemID = "channel-" .. entry.channel.id, presentation = BuildItem(entry, p) }
    end
    local items = panelPreview:Render(entries, {
        mode = "FLOW",
        direction = "RIGHT",
        spacing = p.padding,
        maxVisible = #
            entries
    })
    for _, item in ipairs(items or {}) do BindChannelLabelToBody(item) end
end
local function CreateCollection(host, mode) return EXUI:CreateIconCollection(host, mode, EXWIND_MODULE_KEY) end
local function RenderRuntime()
    local host = EnsureAnchor(); runtimeCollection = runtimeCollection or CreateCollection(host, "runtime"); ApplyPresentation(
        runtimeCollection, BuildPresentation(false)); if not worldPreviewActive then host:SetShown(DB().enabled == true) end
end
local function RenderWorld(host)
    worldPreviewActive = true; if runtimeCollection then
        runtimeCollection:Release(); runtimeCollection = nil
    end; if worldCollection then worldCollection:Release() end; worldCollection = CreateCollection(host, "world"); ApplyPresentation(
        worldCollection, BuildPresentation(true))
end
local function ReleaseWorld()
    worldPreviewActive = false; if worldCollection then
        worldCollection:Release(); worldCollection = nil
    end; RenderRuntime()
end
-- 世界选择框必须直接采用这次 world collection 已经实际排出的语义范围。
-- FLOW/SEMANTIC 的第一项是保存的根点，整组内容会只向右增长；手工以“总宽
-- 度 + offset=0”描述会把选择框错误地居中到根点左侧，并让世界编辑看似与
-- runtime 垂直/水平错位。Collection 的 declaredBounds 是唯一几何来源。
local function GetWorldBounds()
    if not worldCollection then
        error("ChatChannelBar GetWorldBounds requires an active world collection", 2)
    end
    return worldCollection:GetWorldBounds()
end
local function Refresh()
    EnsureAnchor()
    if worldPreviewActive and worldCollection then
        ApplyPresentation(worldCollection, BuildPresentation(true))
        -- 按钮尺寸、间距或显示频道改变后，Core 的 SelectionFrame 也必须重新
        -- 取得同一 collection 的 declared bounds；不能只刷新可见项而留下旧框。
        EXUI:RefreshEditableModule("ExwindTools", "chat_channel_bar")
    else
        RenderRuntime()
    end
    if panelPreview then RenderPanelPresentation(BuildPresentation(true)) end
end

local function ReplacePresentation(target, source)
    for key in pairs(target) do target[key] = nil end
    for key, value in pairs(source) do target[key] = value end
end

local function ReapplyExistingSurface(surface, presentation)
    if not surface then return end
    if surface == panelPreview then
        RenderPanelPresentation(presentation)
        return
    end
    -- 频道勾选会让本次可见集合大于上一帧 currentItems。局部 Reapply 只会
    -- 更新旧集合中的 Item；随后把沉睡的旧尺寸 Item 放回 FLOW，便会出现
    -- 29x29 与 30x30 混排。这里沿用正式 Render 路径重套全部已登记频道，
    -- AcquireItem 按 ID 复用现有 Item，不释放也不触碰聊天业务。
    ApplyPresentation(surface, presentation)
end

local function RefreshActiveSurfaces()
    -- X/Y Slider 已写入唯一 ModuleDB 后，必须把同一个 AnchorController 的
    -- 已存在锚点投影到新位置；只重套文字 Item 不会移动整个频道栏。
    EnsureAnchorController():ApplyPosition()
    ReapplyExistingSurface(panelPreview, BuildPresentation(true))
    ReapplyExistingSurface(worldCollection, BuildPresentation(true))
    ReapplyExistingSurface(runtimeCollection, BuildPresentation(false))
end

EXUI:RegisterModuleValueController(EXWIND_MODULE_KEY, { RefreshActiveSurfaces = RefreshActiveSurfaces })

local CHANNEL_GUI_TARGETS = {}
for _, channel in ipairs(CHANNELS) do CHANNEL_GUI_TARGETS["channel_" .. channel.id .. "_name"] = true end
local function HandlePreviewIntent(intent)
    if type(intent) ~= "table" or intent.elementID ~= "core.label" then
        error("ChatChannelBar preview received unsupported intent", 2)
    end
    -- 左键只确认 panel 项目可交互；它绝不能触发 runtime 的聊天频道业务。
    if intent.type == "elementClicked" then return true end
    if intent.type ~= "elementRightClicked" or not CHANNEL_GUI_TARGETS[intent.guiTarget] then
        error("ChatChannelBar preview received invalid GUI target", 2)
    end
    if not EXUI:FocusModuleGridKey(EXWIND_MODULE_KEY, intent.guiTarget, EXUI.ModuleScrollFrame, EXUI.ActivePageFrame) then
        error("ChatChannelBar preview GUI target is not rendered: " .. tostring(intent.guiTarget), 2)
    end
    return true
end

RegisterLayout()
if not ExwindTools:IsModuleEnabled(EXWIND_MODULE_KEY) then return end
EXUI:RegisterEditableModule({
    addon = "ExwindTools",
    key = "chat_channel_bar",
    name = L["聊天频道快捷栏"],
    settingsPage =
        EXWIND_MODULE_KEY,
    orientation = "HORIZONTAL",
    worldAnchorMode = "semantic-root",
    editOverlay = { titleFontSize = 30 },
    getAnchor =
        EnsureAnchor,
    RenderWorld = RenderWorld,
    ReleaseWorld = ReleaseWorld,
    GetWorldBounds = GetWorldBounds
})
ExwindTools:RegisterModulePreview(EXWIND_MODULE_KEY,
    {
        mount = function(dock)
            if panelPreview then panelPreview:Release() end; panelDock = dock
            panelDock:SetBackdropColor(0.5804, 0.6471, 0.9882, 1)
            panelPreview = EXUI:CreateIconPanelPreview(dock,
                EXWIND_MODULE_KEY, { onIntent = HandlePreviewIntent }); RenderPanelPresentation(BuildPresentation(true))
        end,
        update = function() if panelPreview then RenderPanelPresentation(BuildPresentation(true)) end end,
        release = function()
            if panelPreview then
                panelPreview:Release(); panelPreview = nil
            end
            panelDock = nil
        end
    })
ExwindTools:WatchState(EXWIND_MODULE_KEY .. ".ButtonClicked", EXWIND_MODULE_KEY,
    function(info)
        if info and info.key == "btn_reset_pos" then
            DB().x = DEFAULTS.x; DB().y = DEFAULTS.y; Refresh()
        end
    end)
ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", EXWIND_MODULE_KEY, function() Refresh() end)
_G.SLASH_EXCHATCHANNEL1 = "/cc"; _G.SlashCmdList["EXCHATCHANNEL"] = function(msg)
    msg = (msg or ""):lower(); if msg == "show" then
        DB().enabled = true
    elseif msg == "hide" then
        DB().enabled = false
    elseif msg == "toggle" then
        DB().enabled = not
            DB().enabled
    elseif msg == "reset" then
        DB().x = DEFAULTS.x; DB().y = DEFAULTS.y
    else
        ExwindTools:OpenConfig(EXWIND_MODULE_KEY)
    end; Refresh()
end
ExwindTools:ReportReady(EXWIND_MODULE_KEY)
