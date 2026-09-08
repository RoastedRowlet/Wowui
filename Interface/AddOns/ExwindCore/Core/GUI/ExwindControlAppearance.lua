-- Opt-in control appearance. Each variant owns its pools, including retained
-- composite hosts: a flat child must never be borrowed by a default page.
local UI, Factory = _G.ExwindTools.UI, _G.ExwindFactory
local A = {}
UI.ControlAppearance = A
local unpack = unpack or table.unpack
A.colors = {
    text = { .898, .929, .957, 1 }, muted = { .569, .635, .698, 1 },
    disabled = { .38, .46, .51, 1 }, line = { .161, .231, .298, 1 },
    input = { .035, .075, .110, 1 }, button = { .075, .149, .196, 1 },
    accent = { .294, .824, .910, 1 },
    neutral = { .76, .81, .85, 1 }, include = { .286, .859, .631, 1 },
    exclude = { .933, .443, .502, 1 },
}
A.metrics = { title = 18, section = 15, text = 13, control = 13, hint = 11, height = 28 }
local C = A.colors
-- EXBoss AuraSound typography and dimensions, with semantic color roles for
-- the editor: headings, live facts and editable values are distinct.
A.DungeonAura = {
    row = 42, buttonWidth = 62, buttonHeight = 24, gap = 8,
    text = { .80, .85, .90, 1 }, muted = { .60, .66, .72, 1 },
    title = { .94, .79, .49, 1 }, fact = { .46, .72, .79, 1 },
    value = { .95, .97, 1, 1 }, focus = { .34, .79, .98, 1 },
    success = { .43, .87, .65, 1 }, warning = { .97, .72, .38, 1 }, danger = { .97, .45, .47, 1 },
    input = { .063, .102, .145, 1 }, inputBorder = { .28, .40, .51, 1 },
    inputFocus = { .074, .133, .184, 1 }, header = { .065, .079, .099, 1 },
    panel = { .067, .090, .129, .98 }, panelDeep = { .039, .059, .086, .98 },
    line = { .27, .34, .42, .35 }, lineStrong = { .27, .34, .42, .65 },
    button = { .050, .064, .090, .98 }, hover = { .090, .100, .120, 1 },
    gold = { .953, .788, .424, 1 },
}
-- Load-card palette from the supplied HTML; opt-in, separate from other pages.
A.LoadCard = setmetatable({
    id = "load-card", row = 52, buttonHeight = 26, buttonWidth = 88,
    text = { .80, .80, .80, 1 }, value = { 1, 1, 1, 1 }, title = { 1, 1, 1, 1 },
    muted = { .52, .52, .52, 1 }, fact = { .80, .80, .80, 1 }, focus = { .43, .43, .43, 1 },
    background = { .118, .118, .118, 1 }, header = { .133, .133, .141, 1 },
    panelDeep = { .106, .106, .110, 1 }, panel = { .078, .078, .078, 1 },
    input = { .094, .094, .094, 1 }, inputFocus = { .118, .118, .118, 1 },
    inputBorder = { .20, .20, .20, 1 }, button = { .145, .145, .149, 1 },
    hover = { .176, .176, .176, 1 }, line = { .157, .157, .157, 1 },
    lineStrong = { .220, .220, .227, 1 }, gold = { 1, .784, 0, 1 },
    choiceFill = { 1, 1, 1, 1 }, choiceText = { .059, .067, .082, 1 },
}, { __index = A.DungeonAura })
function A.GetReference(frame)
    local style = UI:GetControlFontStyle(frame)
    return style == "load-card" and A.LoadCard or (style == "dungeon-aura" and A.DungeonAura or nil)
end
function A.ReferenceText(region, template, color)
    if not region then return end
    local font = _G[template] or template
    region:SetFontObject(font)
    -- Pooled regions can retain direct overrides from their previous owner.
    -- Copy the live template's attributes as well as its inheritance link.
    if font.GetFont then
        local path, size, flags = font:GetFont()
        region:SetFont(path, size, flags)
        if font.GetShadowOffset and region.SetShadowOffset then region:SetShadowOffset(font:GetShadowOffset()) end
        if font.GetShadowColor and region.SetShadowColor then region:SetShadowColor(font:GetShadowColor()) end
    end
    region:SetTextColor(unpack(color or A.DungeonAura.text))
end
local originalFontPaths = setmetatable({}, { __mode = "k" })

function A.Font(region, size, color, flags, template)
    if not region or not region.SetFont then return end
    local reference = A.GetReference(region)
    if reference then
        originalFontPaths[region] = originalFontPaths[region] or region:GetFont() or GameFontHighlight:GetFont()
        A.ReferenceText(region, template or "GameFontHighlight", color or reference.text)
        return
    end
    local settings = UI:GetControlFontStyle(region) == "settings"
    local path = region:GetFont()
    if settings then
        originalFontPaths[region] = originalFontPaths[region] or path or GameFontHighlight:GetFont()
        path = _G.ExwindTools.MAIN_FONT or path
    elseif originalFontPaths[region] then
        path, originalFontPaths[region] = originalFontPaths[region], nil
    end
    path = path or GameFontHighlight:GetFont()
    region:SetFont(path, size or A.metrics.text, flags or (settings and "OUTLINE" or ""))
    region:SetTextColor(unpack(color or C.text))
    if region.SetShadowOffset then region:SetShadowOffset(0, 0) end
end

function UI:SetControlAppearance(root, appearance)
    assert(appearance == "flat" or appearance == "default" or appearance == nil, "Unknown control appearance")
    root._exControlAppearance = appearance
end

function UI:GetControlAppearance(root)
    while root do
        if root._exControlAppearance then return root._exControlAppearance end
        if root._exFlatControl then return "flat" end
        root = root.GetParent and root:GetParent()
    end
end

-- Typography is scoped to an opt-in page, never to shared game FontObjects.
-- Set before constructing children; state repaints resolve the current owner.
function UI:SetControlFontSize(root, size)
    assert(size == nil or (type(size) == "number" and size >= 10 and size <= 24), "Invalid control font size")
    root._exControlFontSize = size
end

function UI:GetControlFontSize(root)
    while root do
        if root._exControlFontSize then return root._exControlFontSize end
        root = root.GetParent and root:GetParent()
    end
end

-- Same font family and thin outline as the standard settings Grid.
-- Hints and editable values explicitly opt out of the outline at paint time.
function UI:SetControlFontStyle(root, style)
    assert(style == nil or style == "settings" or style == "dungeon-aura" or style == "load-card", "Unknown control font style")
    root._exControlFontStyle = style
end

function UI:GetControlFontStyle(root)
    while root do
        if root._exControlFontStyle then return root._exControlFontStyle end
        root = root.GetParent and root:GetParent()
    end
end

function UI:ResolveControlPool(poolType, parent, appearance)
    if poolType:match("^EXUI.Flat%.") then return poolType end
    if (appearance or self:GetControlAppearance(parent)) ~= "flat" then return poolType end
    local source = Factory.Pools[poolType]
    if not source then return poolType end
    -- EXAura-owned pools already have one appearance. Shared hosts need their
    -- own variant even when the host itself has no visible artwork.
    if not (poolType:match("^Grid") or source.exComposite) then return poolType end
    if poolType:match("^EXAura%.") or poolType:match("^EXUI%.Choice") then return poolType end
    local name = "EXUI.Flat." .. poolType
    if not Factory.Pools[name] then
        local template = poolType == "GridButton" and "BackdropTemplate" or source.exTemplate
        Factory:InitPool(name, source.exFrameType, template, function(frame)
            frame._exFlatControl = true
            if source.customInit then source.customInit(frame) end
            if poolType == "GridButton" then
                local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                frame:SetFontString(label)
                label:SetPoint("LEFT", 6, 0); label:SetPoint("RIGHT", -6, 0)
                label:SetWordWrap(false)
                frame.label = label
            end
        end)
        Factory.Pools[name].exComposite = source.exComposite
    end
    return name
end

function UI:AcquireControl(poolType, parent)
    return Factory:Acquire(poolType, parent, self._requestedAppearance)
end

local function Surface(frame, fill, edge)
    local skin = frame._exFlatSurface
    if not skin then
        skin = {}
        frame._exFlatSurface = skin
        for i = 1, 5 do skin[i] = frame:CreateTexture(nil, i == 1 and "BACKGROUND" or "BORDER") end
        skin[1]:SetAllPoints()
        skin[2]:SetPoint("TOPLEFT"); skin[2]:SetPoint("TOPRIGHT"); skin[2]:SetHeight(1)
        skin[3]:SetPoint("BOTTOMLEFT"); skin[3]:SetPoint("BOTTOMRIGHT"); skin[3]:SetHeight(1)
        skin[4]:SetPoint("TOPLEFT"); skin[4]:SetPoint("BOTTOMLEFT"); skin[4]:SetWidth(1)
        skin[5]:SetPoint("TOPRIGHT"); skin[5]:SetPoint("BOTTOMRIGHT"); skin[5]:SetWidth(1)
    end
    if frame.SetBackdrop then frame:SetBackdrop(nil) end
    for _, texture in ipairs(skin) do texture:Show() end
    local reference = A.GetReference(frame)
    skin[1]:SetColorTexture(unpack(fill or (reference and reference.panelDeep) or C.input))
    for i = 2, 5 do skin[i]:SetColorTexture(unpack(edge or (reference and reference.lineStrong) or C.line)) end
end

local function InputFocus(frame)
    if not frame._exFlatControl then return end
    local reference = A.GetReference(frame)
    Surface(frame, reference and (frame:HasFocus() and reference.inputFocus or reference.input) or C.input,
        frame:HasFocus() and (reference and reference.focus or C.accent) or (reference and reference.inputBorder or C.line))
end

local function DropdownState(frame)
    local reference = A.GetReference(frame)
    local native = reference == A.DungeonAura
    if frame.Background then frame.Background:SetAlpha(native and 1 or 0) end
    if frame.Arrow then frame.Arrow:SetAlpha(native and 1 or 0) end
    if frame._exFlatArrow then frame._exFlatArrow:SetShown(not reference) end
    for _, texture in ipairs(frame._exLoadChevron or {}) do
        texture:SetShown(reference == A.LoadCard)
        texture:SetVertexColor(unpack(frame:IsEnabled() and A.LoadCard.muted or C.disabled))
    end
    local color = frame:IsEnabled() and (reference and reference.value or C.text) or C.disabled
    A.Font(frame.Text, UI:GetControlFontSize(frame) or A.metrics.control, color, "")
    if frame._exFlatArrow then frame._exFlatArrow:SetTextColor(unpack(color)) end
end

local fontObjects = {}
local fontObjectSerial = 0
local function ButtonFont(role, size, settings, reference)
    local path = settings and _G.ExwindTools.MAIN_FONT or GameFontHighlight:GetFont()
    path = path or GameFontHighlight:GetFont()
    local flags = settings and "OUTLINE" or ""
    local key = role .. size .. flags .. path .. (reference and (reference.id or "DungeonAura") or "")
    if not fontObjects[key] then
        fontObjectSerial = fontObjectSerial + 1
        local font = CreateFont("EXUIFlatButtonFont" .. fontObjectSerial)
        if reference then font:SetFontObject(GameFontNormalSmall)
        else font:SetFont(path, size, flags); font:SetShadowOffset(0, 0) end
        font:SetTextColor(unpack(reference and (reference[role] or C[role]) or C[role] or C.text))
        fontObjects[key] = font
    end
    return fontObjects[key]
end

local function ButtonTexture(frame, method, color, alpha)
    local texture = frame[method](frame)
    if texture then
        texture:SetColorTexture(color[1], color[2], color[3], alpha)
        texture:ClearAllPoints(); texture:SetAllPoints()
        texture:SetTexCoord(0, 1, 0, 1)
    end
end

local function ReferenceButtonHover(frame, hovered)
    local reference = A.GetReference(frame)
    if not reference then return end
    if not frame:IsEnabled() then return end
    Surface(frame, hovered and reference.inputFocus or reference.button,
        hovered and reference.focus or reference.lineStrong)
    frame:GetFontString():SetTextColor(unpack(hovered and reference.value or reference.text))
end

local function Checkbox(frame)
    local box = frame.checkbox
    box:SetSize(22, 22)
    Surface(box)
    ButtonTexture(box, "GetNormalTexture", C.input, 0)
    ButtonTexture(box, "GetPushedTexture", C.accent, .24)
    ButtonTexture(box, "GetHighlightTexture", C.accent, .13)
    for _, entry in ipairs({ { box:GetCheckedTexture(), C.accent }, { box:GetDisabledCheckedTexture(), C.disabled } }) do
        local texture, color = entry[1], entry[2]
        if texture then
            texture:SetDesaturated(true)
            texture:SetVertexColor(unpack(color))
            texture:ClearAllPoints(); texture:SetPoint("CENTER"); texture:SetSize(20, 20)
        end
    end
end

local function Slider(frame)
    local slider = frame.Slider or frame
    for _, key in ipairs({ "Left", "Middle", "Right" }) do
        if slider[key] then slider[key]:SetAlpha(0) end
    end
    if not slider._exFlatTrack then
        local track = slider:CreateTexture(nil, "BACKGROUND")
        track:SetPoint("LEFT"); track:SetPoint("RIGHT"); track:SetHeight(3)
        track:SetColorTexture(unpack(C.line))
        slider._exFlatTrack = track
    end
    local thumb = slider.GetThumbTexture and slider:GetThumbTexture()
    if thumb then thumb:SetColorTexture(unpack(C.accent)); thumb:SetSize(8, 14) end
    for _, key in ipairs({ "Back", "Forward" }) do
        local stepper = frame[key]
        if stepper and not stepper._exFlatGlyph then
            for _, region in ipairs({ stepper:GetRegions() }) do
                if region:IsObjectType("Texture") then region:SetAlpha(0) end
            end
            local glyph = stepper:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            glyph:SetPoint("CENTER"); glyph:SetText(key == "Back" and "‹" or "›")
            A.Font(glyph, 16, C.muted)
            stepper._exFlatGlyph = glyph
        end
    end
    if frame.numberInput then
        Surface(frame.numberInput)
        A.Font(frame.numberInput, 11)
    end
    A.Font(frame.Title, A.metrics.text)
end

function UI:ApplyControlAppearance(frame, appearance)
    if not frame or (appearance or self:GetControlAppearance(frame)) ~= "flat" then return frame end
    local kind = frame._gridType
    local scopedSize = self:GetControlFontSize(frame)
    local controlSize = scopedSize or A.metrics.control
    local reference = A.GetReference(frame)
    if kind == "GridButton" then
        Surface(frame, reference and reference.button or C.button, reference and reference.lineStrong)
        local size = scopedSize or ((frame:GetWidth() < 38 or frame:GetHeight() < 24) and 11 or A.metrics.control)
        local settings = self:GetControlFontStyle(frame) == "settings"
        frame:SetNormalFontObject(ButtonFont("text", size, settings, reference))
        frame:SetHighlightFontObject(ButtonFont(reference and "value" or "text", size, settings, reference))
        frame:SetDisabledFontObject(ButtonFont("disabled", size, settings, reference))
        ButtonTexture(frame, "GetNormalTexture", C.button, 0)
        ButtonTexture(frame, "GetHighlightTexture", reference and reference.focus or C.accent, .13)
        ButtonTexture(frame, "GetPushedTexture", reference and reference.focus or C.accent, .24)
        ButtonTexture(frame, "GetDisabledTexture", C.input, .4)
        frame:SetPushedTextOffset(0, -1)
        A.Font(frame:GetFontString(), size, reference and reference.text or C.text, nil, "GameFontNormalSmall")
        if reference and not frame._exReferenceButtonHover then
            frame._exReferenceButtonHover = true
            frame:HookScript("OnEnter", function(self) ReferenceButtonHover(self, true) end)
            frame:HookScript("OnLeave", function(self) ReferenceButtonHover(self, false) end)
        end
    elseif kind == "GridDropdown" or kind == "GridLSMDropdown" then
        if reference == A.DungeonAura then
            for _, texture in ipairs(frame._exFlatSurface or {}) do texture:Hide() end
        else Surface(frame, reference and reference.input, reference and reference.inputBorder) end
        if reference == A.LoadCard and not frame._exLoadChevron then
            frame._exLoadChevron = {}
            for index = 1, 2 do
                local texture = frame:CreateTexture(nil, "OVERLAY")
                texture:SetColorTexture(1, 1, 1, 1)
                texture:SetSize(7, 2)
                texture:SetPoint("RIGHT", index == 1 and -15 or -11, 0)
                texture:SetRotation(index == 1 and -math.pi / 4 or math.pi / 4)
                frame._exLoadChevron[index] = texture
            end
        end
        if not frame._exFlatArrow then
            frame._exFlatArrow = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            frame._exFlatArrow:SetPoint("RIGHT", -9, 0)
            frame._exFlatArrow:SetText("▾")
            frame:HookScript("OnEnable", DropdownState)
            frame:HookScript("OnDisable", DropdownState)
        end
        A.Font(frame._exFlatArrow, 13, C.muted)
        frame.Text:ClearAllPoints()
        frame.Text:SetPoint("LEFT", 9, 0); frame.Text:SetPoint("RIGHT", -27, 0)
        frame.Text:SetHeight(controlSize + 5)
        frame:SetHeight(A.metrics.height)
        frame._exGridFixedHeight = A.metrics.height
        DropdownState(frame)
    elseif kind == "GridInput" then
        A.Font(frame, controlSize, reference and reference.value, "")
        frame:SetTextInsets(9, 9, 0, 0)
        InputFocus(frame)
        if not frame._exFlatFocusHook then
            frame._exFlatFocusHook = true
            frame:HookScript("OnEditFocusGained", InputFocus)
            frame:HookScript("OnEditFocusLost", InputFocus)
        end
        A.Font(frame.placeholder, scopedSize and math.max(14, scopedSize - 2) or A.metrics.hint, reference == A.LoadCard and reference.muted or C.muted, "")
        if frame.placeholder then
            frame.placeholder:ClearAllPoints()
            frame.placeholder:SetPoint("LEFT", frame, "LEFT", 9, 0)
            frame.placeholder:SetPoint("RIGHT", frame, "RIGHT", -9, 0)
            frame.placeholder:SetJustifyH("LEFT")
            frame.placeholder:SetWordWrap(false)
        end
    elseif kind == "GridHeader" then
        A.Font(frame.Title, A.metrics.section)
        if frame.Line then frame.Line:SetColorTexture(unpack(C.line)) end
    elseif kind == "GridSubheader" then
        A.Font(frame.text, A.metrics.section)
    elseif kind == "GridDescription" then
        A.Font(frame.text, A.metrics.hint, C.muted)
    elseif kind == "GridCheckbox" then
        Checkbox(frame)
    elseif kind == "GridSlider" then
        Slider(frame)
    elseif frame.editBox and frame.editBox ~= frame then
        -- A multiline editor is an exclusive retained subtree of its caller.
        Surface(frame)
        A.Font(frame.editBox, controlSize, nil, "")
    end
    if kind ~= "GridSubheader" and kind ~= "GridDescription" then A.Font(frame.labelText, scopedSize or A.metrics.text) end
    if kind ~= "GridButton" then A.Font(frame.label, scopedSize or A.metrics.text) end
    return frame
end

-- Entry points use the existing constructors, menu/search and commit contracts.
-- Explicit Flat APIs also work under shared hosts without marking that host.
local flatAPI = setmetatable({ _requestedAppearance = "flat" }, { __index = UI })
for _, suffix in ipairs({ "Button", "EditBox", "Dropdown", "MultiSelectDropdown",
    "LSMDropdown", "LSMTextureDropdown", "LSMSoundDropdown", "Checkbox", "Slider", "Header", "ColorButton" }) do
    local original = UI["Create" .. suffix]
    UI["Create" .. suffix] = function(self, parent, ...)
        local frame = original(self, parent, ...)
        return UI:ApplyControlAppearance(frame, self._requestedAppearance or UI:GetControlAppearance(parent))
    end
    UI["CreateFlat" .. suffix] = function(_, parent, ...)
        return UI["Create" .. suffix](flatAPI, parent, ...)
    end
end
