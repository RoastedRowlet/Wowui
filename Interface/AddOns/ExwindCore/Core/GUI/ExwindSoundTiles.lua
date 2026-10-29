-- 声音选择（soundselector）的格子排法：opts.tiles = true 时“播放什么”一排四格——
-- 来源 / 声音（或文件路径）/ 声道，每格小标题在上、值在下、右边下拉箭头，最右一格“▶ 试听”。
-- 每格整格都能点：每格自己有一个整格按钮；下拉格点了打开藏在格子下面的标准下拉的菜单（读写、菜单都用它），
-- 试听格点了试听、悬停有提示。声音格最宽，来源、声道不超过预设宽、也不超过声音格。
-- 读写、字段后缀、试听回调和连体声音选择完全一样（ExwindSettingsV2.lua 的 SoundSelectorComponent 转到这里），
-- 只有外观不同。尺寸全在 GM.settings.parts 的 soundTile*（样式预设可覆盖），颜色只用 GUIColors。
local UI = _G.ExwindTools.UI
local GM = _G.ExwindTools.GUIMetrics

local function Part(style, key)
    local value = style and style[key]
    if value == nil then value = GM.settings.parts[key] end
    if value == nil then error("SoundTiles: GM.settings.parts." .. key .. " missing", 2) end
    return value
end

-- 内容格的小标题按来源换。
local CONTENT_CAPTION = { lsm = "声音", pack = "声音", file = "文件路径", tts = "朗读文字" }

-- 一格：底板 + 小标题 + 值 + 箭头（没有下拉的格子不画箭头）。格子挂在组合宿主上、跟宿主一起复用。
local TileMethods = {}
TileMethods.__index = TileMethods
function TileMethods:Paint()
    local GC = _G.ExwindTools.GUIColors
    local hover = self.enabled and self.hit:IsShown() and self.hit:IsMouseOver()
    local border = hover and (self.play and GC.primaryFill or GC.cardHoverBorder) or GC.cardBorder
    UI:SetControlSurface(self.frame, GM.radius.card, GC.card, border)
    self.frame:SetAlpha(self.enabled and 1 or Part(self.style, "soundTileDisabledAlpha"))
end

local function NewTile(widget)
    local tile = setmetatable({ enabled = true }, TileMethods)
    local frame = CreateFrame("Frame", nil, widget)
    frame:EnableMouse(false)
    tile.frame = frame
    tile.caption = UI:CreateVisualFontString(frame, _G.EXFONTFRAME, "GameFontHighlightSmall")
    tile.caption:SetJustifyH("LEFT")
    tile.caption:SetWordWrap(false)
    tile.value = UI:CreateVisualFontString(frame, _G.EXFONTFRAME, "GameFontHighlight")
    tile.value:SetJustifyH("LEFT")
    tile.value:SetWordWrap(false)
    tile.arrow = frame:CreateTexture(nil, "ARTWORK")
    -- 整格按钮：下拉格点了开 / 关 cover 的菜单，试听格点了调 onClick；悬停换边框色，写了 tip 时显示提示。
    local hit = CreateFrame("Button", nil, frame)
    hit:SetAllPoints(frame)
    hit:RegisterForClicks("LeftButtonUp")
    hit:SetScript("OnEnter", function(self)
        tile:Paint()
        if tile.tip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(tile.tip, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    hit:SetScript("OnLeave", function(self)
        tile:Paint()
        if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
    end)
    -- 下拉格：菜单开着时再点同一格要关上。暴雪菜单在全局按下时可能先把菜单关掉，等到 OnClick 已经看不出
    -- “刚才开着”，于是又重开。所以按下时就记住菜单开没开：此刻还开着，或就在这一帧（同一次按下）刚被关掉，
    -- 都算开着，松开时只关不开。鼠标下的框写了 HandlesGlobalMouseEvent 时暴雪不关，交给这里关。
    hit:SetScript("OnMouseDown", function(_, buttonName)
        local dropdown = tile.cover
        if buttonName ~= "LeftButton" or not dropdown then return end
        if not dropdown._exSoundTileCloseHook and dropdown.RegisterCallback and DropdownButtonMixin then
            dropdown._exSoundTileCloseHook = true
            dropdown:RegisterCallback(DropdownButtonMixin.Event.OnMenuClose, function()
                dropdown._exSoundTileClosedAt = GetTime()
            end)
        end
        tile.openAtDown = (dropdown.IsMenuOpen and dropdown:IsMenuOpen()) or dropdown._exSoundTileClosedAt == GetTime()
    end)
    hit:SetScript("OnClick", function(self)
        if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
        if tile.onClick then return tile.onClick() end
        local dropdown = tile.cover
        if not dropdown then return end
        local wasOpen = tile.openAtDown
        tile.openAtDown = nil
        if dropdown.IsMenuOpen and dropdown:IsMenuOpen() then dropdown:CloseMenu()
        elseif not wasOpen then dropdown:OpenMenu() end
    end)
    hit.HandlesGlobalMouseEvent = function(_, buttonName, event)
        return tile.cover ~= nil and event == "GLOBAL_MOUSE_DOWN" and buttonName == "LeftButton"
    end
    tile.hit = hit
    return tile
end

local function Tiles(widget)
    local set = widget._exSoundTiles
    if not set then
        set = { source = NewTile(widget), content = NewTile(widget), channel = NewTile(widget), play = NewTile(widget) }
        local play = set.play
        play.play = true
        -- 里面的小按钮只是播放图标 / 跳动竖线的载体，不接鼠标（点击、悬停都在整格按钮上）。
        play.glyph = CreateFrame("Button", nil, play.frame)
        play.glyph:EnableMouse(false)
        widget._exSoundTiles = set
    end
    return set
end

-- 组合宿主被别的控件借走时格子不能露出来。
local function HideTiles(widget)
    local set = widget._exSoundTiles
    if not set then return end
    for _, tile in pairs(set) do
        tile.frame:Hide()
        tile.cover, tile.onClick, tile.tip = nil, nil, nil
    end
end

-- helpers：SettingsV2 的内部件（建绑定、借宿主、摆放、归还、默认启用）与声音来源表。
function UI:CreateSoundTilesAdapter(spec, bindingFor, runtimeOpts, helpers)
    local opts = spec.opts or {}
    local H = helpers
    local states = setmetatable({}, { __mode = "k" })
    local adapter = { component = spec.component }
    local single = #opts.sources == 1

    local function SourceOf(state)
        local value = state.fields.source:Read()
        return state.contents[value] and value or opts.sources[1]
    end
    local function DisplayText(dropdown)
        return dropdown.Text and dropdown.Text:GetText() or ""
    end
    -- 格子上显示的值跟着下拉自己的显示文字（选项名、LSM 名字、默认值都由下拉算好）。
    local function Sync(widget)
        local state = states[widget]
        local L = _G.ExwindTools.L
        local tiles, source = state.tiles, SourceOf(state)
        tiles.source.value:SetText(DisplayText(state.parts.source))
        tiles.content.caption:SetText(L[CONTENT_CAPTION[source]] or CONTENT_CAPTION[source])
        for name, control in pairs(state.contents) do control:SetShown(name == source) end
        local content = state.contents[source]
        local dropdown = content and content.OpenMenu ~= nil
        tiles.content.cover = dropdown and content or nil
        -- 内容是输入框（文件路径）时整格按钮收起，让输入框能点。
        tiles.content.hit:SetShown(dropdown)
        tiles.content.value:SetShown(dropdown)
        tiles.content.arrow:SetShown(dropdown)
        if dropdown then tiles.content.value:SetText(DisplayText(content)) end
        if state.channel then tiles.channel.value:SetText(DisplayText(state.channel)) end
        for _, tile in pairs(tiles) do tile:Paint() end
    end

    function adapter.mount(host, context)
        local style = context._exStyle
        local base = bindingFor(context)
        local fields = {}
        for name, suffix in pairs(H.SoundSuffix) do
            fields[name] = H.CreateBinding(base.moduleKey, base.root, base.path .. suffix)
        end
        if opts.channel then fields.channel = H.CreateBinding(base.moduleKey, base.root, base.path .. "Channel") end
        local widget = H.Acquire(host)
        local L = _G.ExwindTools.L
        local height = Part(style, "soundTileEditHeight")
        local function Commit(name)
            return function(value)
                if not context:IsCurrent() then return end
                fields[name]:Write(value, "commit")
                context:RefreshPage()
            end
        end
        local sourceItems = {}
        for i, source in ipairs(opts.sources) do sourceItems[i] = { L[H.SoundSources[source]], source } end
        local width = GM.size.controlDefaultWidth
        local parts = {
            source = UI:CreateDropdown(widget, width, nil, sourceItems, fields.source:Read(), Commit("source")),
            lsm = UI:CreateLSMSoundDropdown(widget, width, nil, fields.lsm:Read(), Commit("lsm"), { search = true }),
            file = UI:CreateEditBox(widget, fields.file:Read() or "", width, height, nil,
                { onEnter = Commit("file"), onEditFocusLost = Commit("file") }),
            tts = UI:CreateEditBox(widget, fields.tts:Read() or "", width, height, nil,
                { onEnter = Commit("tts"), onEditFocusLost = Commit("tts") }),
        }
        if opts.labelSource then
            parts.pack = UI:CreateDropdown(widget, width, nil, H.SelectItems({ optionsSource = opts.labelSource }),
                fields.pack:Read(), Commit("pack"), { search = true })
        end
        local channel
        if opts.channel then
            local channelItems = {}
            for i, name in ipairs(H.SoundChannel.order) do
                channelItems[i] = { _G[H.SoundChannel.names[name]] or name, name }
            end
            channel = UI:CreateDropdown(widget, width, nil, channelItems, fields.channel:Read() or "Master", Commit("channel"))
            parts.channel = channel
        end
        for _, part in pairs(parts) do UI:PrepareSettingsListControl(part, { ordinaryControl = true, hideLabel = true }) end
        local contents = {}
        for _, source in ipairs(opts.sources) do contents[source] = parts[source] end
        for name, part in pairs(parts) do
            if name ~= "source" and name ~= "channel" and not contents[name] then part:Hide() end
        end
        local tiles = Tiles(widget)
        for key, tile in pairs(tiles) do
            tile.style, tile.enabled = style, true
            local GC = _G.ExwindTools.GUIColors
            UI.ControlAppearance.Font(tile.caption, Part(style, "soundTileCaptionFont"), GC.textDim, "", "GameFontHighlightSmall")
            UI.ControlAppearance.Font(tile.value, Part(style, "soundTileValueFont"), GC.text, "", "GameFontHighlight")
            tile.arrow:SetTexture(UI:GetIcon("chevron-down"))
            tile.arrow:SetVertexColor(unpack(GC.textDim))
            tile.arrow:SetShown(key ~= "play")
            tile.frame:SetShown(key ~= "channel" or channel ~= nil)
        end
        tiles.source.frame:SetShown(not single)
        tiles.source.caption:SetText(L["来源"])
        tiles.channel.caption:SetText(L["声道"])
        tiles.play.caption:SetText(L[opts.testTip or "试听"] or opts.testTip or "试听")
        tiles.play.value:SetText("")
        tiles.source.cover, tiles.channel.cover = parts.source, channel
        tiles.play.tip = L["播放一次所选声音"]
        -- 下拉藏在格子下面（透明、不接鼠标，点击都落到整格按钮上）：只用它的读写和菜单，菜单是独立窗口，不受透明影响。
        for _, name in ipairs({ "source", "lsm", "pack", "channel" }) do
            if parts[name] then
                parts[name]:SetAlpha(0)
                parts[name]:EnableMouse(false)
            end
        end
        local glyph = tiles.play.glyph
        UI:ApplySoundPreviewAppearance(glyph)
        tiles.play.onClick = function()
            if not context:IsCurrent() then return end
            if runtimeOpts and runtimeOpts.onTest then return runtimeOpts.onTest(context, glyph) end
            if not opts.test then return end
            _G.ExwindTools:UpdateState(base.moduleKey .. ".ButtonClicked", { key = opts.test, fullPath = base.path, ts = GetTime() })
        end
        widget:SetSize(GM.settings.soundSelectorWidth, Part(style, "soundTileHeight"))
        states[widget] = { host = host, fields = fields, parts = parts, contents = contents, channel = channel,
            tiles = tiles, style = style, enabled = true }
        Sync(widget)
        return widget
    end

    function adapter.update(widget)
        local state = states[widget]
        UI:SetDropdownValue(state.parts.source, SourceOf(state))
        UI:SetDropdownValue(state.parts.lsm, state.fields.lsm:Read())
        if state.parts.pack then UI:SetDropdownValue(state.parts.pack, state.fields.pack:Read()) end
        if state.channel then UI:SetDropdownValue(state.channel, state.fields.channel:Read() or "Master") end
        for _, name in ipairs({ "file", "tts" }) do
            local box = state.parts[name]
            if not box:HasFocus() then box:SetText(state.fields[name]:Read() or "") end
        end
        Sync(widget)
    end

    function adapter.measure(widget) return Part(states[widget].style, "soundTileHeight") end

    function adapter.layout(widget, context, width, height)
        local state = states[widget]
        local style, tiles = state.style, state.tiles
        H.Place(widget, state.host, 0, 0, width, height)
        local gap, tileHeight = Part(style, "soundTileGap"), Part(style, "soundTileHeight")
        local padX, lineGap = Part(style, "soundTilePadX"), Part(style, "soundTileLineGap")
        local arrowSize = Part(style, "soundTileArrowSize")
        local playWidth = Part(style, "soundTilePlayWidth")
        -- 声音格最宽：来源、声道各取预设宽，但不超过（扣掉试听格后的宽）/（边格数 + 2），声音格分剩下的。
        local sides = (single and 0 or 1) + (state.channel and 1 or 0)
        local room = math.max(1, width - playWidth - gap * (sides + 1))
        local sideMax = math.floor(room / (sides + 2))
        local sourceWidth = single and 0 or math.min(Part(style, "soundTileSourceWidth"), sideMax)
        local channelWidth = state.channel and math.min(Part(style, "soundTileChannelWidth"), sideMax) or 0
        local contentWidth = math.max(1, room - sourceWidth - channelWidth)
        local x = 0
        local order = {}
        if not single then order[#order + 1] = { tiles.source, sourceWidth } end
        order[#order + 1] = { tiles.content, contentWidth }
        if state.channel then order[#order + 1] = { tiles.channel, channelWidth } end
        order[#order + 1] = { tiles.play, playWidth }
        for _, entry in ipairs(order) do
            local tile, tileWidth = entry[1], entry[2]
            H.Place(tile.frame, widget, x, 0, tileWidth, tileHeight)
            tile.frame:SetFrameLevel(widget:GetFrameLevel() + 1)
            local captionHeight = select(2, tile.caption:GetFont()) or Part(style, "soundTileCaptionFont")
            local valueHeight = select(2, tile.value:GetFont()) or Part(style, "soundTileValueFont")
            local top = (tileHeight - captionHeight - lineGap - valueHeight) / 2
            local textRight = tile.play and padX or (padX + arrowSize + lineGap * 2)
            tile.caption:ClearAllPoints()
            tile.value:ClearAllPoints()
            tile.arrow:ClearAllPoints()
            if tile.play then
                -- 试听格：播放图标在上、“试听”在下，整组竖直居中。
                local glyphSize = GM.size.playIndicatorIconSize
                local stack = glyphSize + lineGap * 2 + captionHeight
                local glyphTop = (tileHeight - stack) / 2
                H.Place(tile.glyph, tile.frame, (tileWidth - glyphSize) / 2, glyphTop, glyphSize, glyphSize)
                tile.caption:SetJustifyH("CENTER")
                tile.caption:SetPoint("TOP", tile.frame, "TOP", 0, -(glyphTop + glyphSize + lineGap * 2))
                tile.caption:SetTextColor(unpack(_G.ExwindTools.GUIColors.accent))
            else
                tile.caption:SetJustifyH("LEFT")
                tile.caption:SetPoint("TOPLEFT", tile.frame, "TOPLEFT", padX, -top)
                tile.caption:SetPoint("RIGHT", tile.frame, "RIGHT", -textRight, 0)
                tile.value:SetPoint("TOPLEFT", tile.frame, "TOPLEFT", padX, -(top + captionHeight + lineGap))
                tile.value:SetPoint("RIGHT", tile.frame, "RIGHT", -textRight, 0)
                tile.arrow:SetSize(arrowSize, arrowSize)
                tile.arrow:SetPoint("RIGHT", tile.frame, "RIGHT", -padX, 0)
            end
            tile.hit:SetFrameLevel(tile.frame:GetFrameLevel() + 5)
            x = x + tileWidth + gap
        end
        -- 透明下拉盖满各自的格子；内容是输入框时输入框放在值那一行。
        for _, entry in ipairs({ { state.parts.source, tiles.source }, { state.channel, tiles.channel } }) do
            local control, tile = entry[1], entry[2]
            if control then
                control._exGridFixedHeight = tileHeight
                control:ClearAllPoints()
                control:SetAllPoints(tile.frame)
                control:SetFrameLevel(tile.frame:GetFrameLevel() + 3)
            end
        end
        local content = tiles.content
        local captionHeight = select(2, content.caption:GetFont()) or Part(style, "soundTileCaptionFont")
        local editHeight = Part(style, "soundTileEditHeight")
        local editTop = (tileHeight - captionHeight - lineGap - editHeight) / 2
        for name, control in pairs(state.contents) do
            control:ClearAllPoints()
            if control.OpenMenu then
                control._exGridFixedHeight = tileHeight
                control:SetAllPoints(content.frame)
            else
                if name == SourceOf(state) then
                    content.caption:ClearAllPoints()
                    content.caption:SetPoint("TOPLEFT", content.frame, "TOPLEFT", padX, -editTop)
                end
                control:SetPoint("TOPLEFT", content.frame, "TOPLEFT", padX, -(editTop + captionHeight + lineGap))
                control:SetPoint("TOPRIGHT", content.frame, "TOPRIGHT", -padX, -(editTop + captionHeight + lineGap))
                control:SetHeight(editHeight)
            end
            control:SetFrameLevel(content.frame:GetFrameLevel() + 3)
        end
        if not single then state.parts.source:SetShown(true) else state.parts.source:Hide() end
        Sync(widget)
    end

    function adapter.setEnabled(widget, context, enabled)
        local state = states[widget]
        state.enabled = enabled
        for _, part in pairs(state.parts) do H.ControlDefaults.setEnabled(part, context, enabled) end
        for _, tile in pairs(state.tiles) do
            tile.enabled = enabled
            tile.hit:SetEnabled(enabled)
        end
        Sync(widget)
    end

    adapter.setVisible = H.ControlDefaults.setVisible

    function adapter.release(widget)
        local state = states[widget]
        states[widget] = nil
        for _, part in pairs(state.parts) do
            part:SetAlpha(1)
            if part.OpenMenu then part:EnableMouse(true) end
            H.ReleaseBoundWidget(part)
        end
        local glyph = state.tiles.play.glyph
        if glyph._exPreviewDriver then glyph._exPreviewDriver:Stop() end
        for _, tile in pairs(state.tiles) do tile.hit:SetEnabled(true) end
        HideTiles(widget)
        H.ReleaseCompositeHost(widget)
    end
    return adapter
end
