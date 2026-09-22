--[[
	Custom glows for unit frames and on-screen alerts.

	Test/whisper glows sit on UIParent and cover the raid cell. Compact
	unit frames clip children and reject new child frames in combat.
	Live raid glows parent a child overlay to the AuraButton (so engine
	show/hide drives it) and size that overlay to the unit frame. Do not
	stretch the AuraButton or Play animations on it.

	Pixel (marching ants) uses four clipped strips and Translation
	AnimationGroups. Layout happens in ApplyGlow; the engine moves the
	strips. Do not drive pixel glows from OnUpdate. Live overlays stay
	created on every raid cell and are only shown or hidden.

	Countdown is a StatusBar over the raid cell. SetDurationBar lets the
	engine drain remaining time, same as duration text. Do not read aura
	remaining, and do not drive it from CooldownFrames.
]]

local ADDON_NAME, addon = ...

local WHITE = "Interface\\Buttons\\WHITE8X8"
local MAX_EDGE_DASHES = 12
local PIXEL_KEYS = { "top", "bottom", "left", "right" }

local FrameIsForbidden = addon.FrameIsForbidden

local function PlainNumber(value, fallback)
	if type(value) ~= "number" or addon.IsSecret(value) then
		return fallback
	end
	return value
end

local function ReadSize(frame)
	if not frame or not frame.GetWidth or not frame.GetHeight then
		return nil, nil
	end
	local okw, w = pcall(frame.GetWidth, frame)
	local okh, h = pcall(frame.GetHeight, frame)
	w = okw and PlainNumber(w, nil) or nil
	h = okh and PlainNumber(h, nil) or nil
	if w and w >= 8 then
		return w, h or w
	end
	return nil, nil
end

local function FrameSize(frame, fallback)
	fallback = fallback or 64
	local w, h = ReadSize(frame)
	if w then
		return w, h
	end
	return fallback, fallback
end

local function Color(opts)
	if opts and opts.r then
		return opts.r, opts.g or 1, opts.b or 1, opts.a or 0.9
	end
	local r, g, b, a = addon.GetGlowColor()
	return r or (234 / 255), g or (162 / 255), b or (33 / 255), a or 0.90
end

local function PulseDuration(speed)
	return 0.55 / math.max(0.08, speed or 1.5)
end

local function GlowLevel(frame, cover)
	local level = 1
	local function consider(f)
		if not f or not f.GetFrameLevel then
			return
		end
		local ok, value = pcall(f.GetFrameLevel, f)
		if not ok then
			return
		end
		value = PlainNumber(value, nil)
		if value and value > level then
			level = value
		end
	end
	consider(frame)
	consider(cover)
	if frame then
		consider(frame.healthBar)
		consider(frame.HealthBar)
		consider(frame.powerBar)
		consider(frame.PowerBar)
		consider(frame.PIHelperContainer)
		consider(frame.selectionHighlight)
		consider(frame.aggroHighlight)
	end
	return level + 12
end

local function EnsureOverlay(frame)
	if not frame or FrameIsForbidden(frame) then
		return nil
	end
	local overlay = frame.PIHelperGlow
	if overlay then
		return overlay
	end
	local ok
	ok, overlay = pcall(CreateFrame, "Frame", nil, frame, "DisableUntrustedLayoutScriptsTemplate")
	if not ok or not overlay then
		overlay = CreateFrame("Frame", nil, frame)
	end
	pcall(overlay.SetAllPoints, overlay, frame)
	overlay:EnableMouse(false)
	if overlay.SetClipsChildren then
		overlay:SetClipsChildren(true)
	end
	pcall(overlay.SetFrameLevel, overlay, GlowLevel(frame))
	frame.PIHelperGlow = overlay
	return overlay
end

local function EnsureFill(overlay)
	local fill = overlay.fill
	if not fill then
		fill = overlay:CreateTexture(nil, "BACKGROUND")
		fill:SetAllPoints()
		fill:SetTexture(WHITE)
		overlay.fill = fill
	end
	return fill
end

local function EnsureEdges(overlay)
	if overlay.edges then
		return overlay.edges
	end
	local edges = {}
	local keys = { "top", "bottom", "left", "right" }
	for i = 1, #keys do
		local tex = overlay:CreateTexture(nil, "OVERLAY")
		tex:SetTexture(WHITE)
		edges[keys[i]] = tex
	end
	overlay.edges = edges
	return edges
end

local function LayoutEdges(overlay, thickness)
	local edges = EnsureEdges(overlay)
	thickness = math.max(1, thickness or 2)
	local w, h = ReadSize(overlay)
	w = w or 0
	h = h or 0
	if w > 0 and h > 0 then
		thickness = math.min(thickness, math.max(1, math.floor(math.min(w, h) / 2)))
	end
	-- Inset the sides so they meet the top/bottom instead of stacking on the corners.
	edges.top:ClearAllPoints()
	edges.top:SetPoint("TOPLEFT")
	edges.top:SetPoint("TOPRIGHT")
	edges.top:SetHeight(thickness)
	edges.bottom:ClearAllPoints()
	edges.bottom:SetPoint("BOTTOMLEFT")
	edges.bottom:SetPoint("BOTTOMRIGHT")
	edges.bottom:SetHeight(thickness)
	edges.left:ClearAllPoints()
	edges.left:SetPoint("TOPLEFT", 0, -thickness)
	edges.left:SetPoint("BOTTOMLEFT", 0, thickness)
	edges.left:SetWidth(thickness)
	edges.right:ClearAllPoints()
	edges.right:SetPoint("TOPRIGHT", 0, -thickness)
	edges.right:SetPoint("BOTTOMRIGHT", 0, thickness)
	edges.right:SetWidth(thickness)
	return edges
end

-- AuraContainer has UntrustedLayoutScriptExecution. SetPoint/SetAllPoints
-- onto it taints; fall back to the unit frame if that happens.
local function LayoutToFrame(region, frame, pad)
	pcall(region.ClearAllPoints, region)
	if pad then
		local w, h = FrameSize(frame, 64)
		local ox, oy = w * pad, h * pad
		pcall(region.SetPoint, region, "TOPLEFT", frame, "TOPLEFT", -ox, oy)
		pcall(region.SetPoint, region, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", ox, -oy)
	else
		pcall(region.SetAllPoints, region, frame)
	end
	return true
end

local function LayoutRegionToCover(region, frame, cover, pad)
	if not region or not frame then
		return false
	end
	if not cover or cover == frame then
		return LayoutToFrame(region, frame, pad)
	end
	-- AuraContainer size is secretwrapped. Anchoring onto it inherits
	-- UntrustedLayoutScriptExecution unless this region opted in.
	pcall(region.ClearAllPoints, region)
	if pcall(region.SetAllPoints, region, cover) then
		pcall(region.Show, region)
		return true
	end
	return LayoutToFrame(region, frame, pad)
end

local function StopPulse(overlay)
	if overlay.pulse then
		pcall(overlay.pulse.Stop, overlay.pulse)
	end
end

local function PulseOverlay(overlay, fromA, toA, speed)
	local group = overlay.pulse
	if not group then
		group = overlay:CreateAnimationGroup()
		group:SetLooping("BOUNCE")
		local anim = group:CreateAnimation("Alpha")
		anim:SetSmoothing("IN_OUT")
		group.anim = anim
		overlay.pulse = group
	end
	group.anim:SetFromAlpha(fromA)
	group.anim:SetToAlpha(toA)
	group.anim:SetDuration(PulseDuration(speed))
	pcall(group.Stop, group)
	pcall(overlay.SetAlpha, overlay, 1)
	pcall(group.Play, group)
end

local function SnapPixel(tex)
	if not tex then
		return
	end
	if tex.SetSnapToPixelGrid then
		pcall(tex.SetSnapToPixelGrid, tex, true)
	end
	if tex.SetTexelSnappingBias then
		pcall(tex.SetTexelSnappingBias, tex, 0)
	end
end

local function HideAnts(overlay)
	local ants = overlay and overlay.pihAnts
	if not ants then
		return
	end
	for i = 1, #PIXEL_KEYS do
		local edge = ants[PIXEL_KEYS[i]]
		if edge then
			if edge.group then
				pcall(edge.group.Stop, edge.group)
			end
			pcall(edge.Hide, edge)
		end
	end
end

local function HideEdges(overlay)
	if not overlay.edges then
		return
	end
	pcall(overlay.edges.top.Hide, overlay.edges.top)
	pcall(overlay.edges.bottom.Hide, overlay.edges.bottom)
	pcall(overlay.edges.left.Hide, overlay.edges.left)
	pcall(overlay.edges.right.Hide, overlay.edges.right)
end

local function HideCountdown(overlay)
	local bar = overlay and overlay.pihCountdownBar
	if not bar then
		return
	end
	if bar.SetScript then
		pcall(bar.SetScript, bar, "OnUpdate", nil)
	end
	local auraButton = overlay.pihCountdownAuraButton
	if auraButton and auraButton.ClearDurationBar then
		pcall(auraButton.ClearDurationBar, auraButton)
	end
	overlay.pihCountdownAuraButton = nil
	pcall(bar.Hide, bar)
end

local function DurationBarOpts()
	local opts = {}
	if Enum and Enum.StatusBarInterpolation then
		opts.interpolation = Enum.StatusBarInterpolation.Immediate
	end
	if Enum and Enum.StatusBarTimerDirection then
		opts.direction = Enum.StatusBarTimerDirection.RemainingTime
	end
	return opts
end

local COUNTDOWN_POINTS = {
	center = { point = "CENTER" },
	top    = { point = "TOP" },
	bottom = { point = "BOTTOM" },
}

local function LayoutCountdownBar(bar, overlay)
	local db = addon.db
	local id = db and db.countdownAnchor or "top"
	local spec = COUNTDOWN_POINTS[id] or COUNTDOWN_POINTS.top
	local x = 0
	local y = 0
	if db and type(db.countdownX) == "number" then
		x = db.countdownX
	end
	if db and type(db.countdownY) == "number" then
		y = db.countdownY
	end
	local height = 0
	if db and type(db.countdownHeight) == "number" then
		height = math.max(0, math.min(40, db.countdownHeight))
	end
	local w, frameH = ReadSize(overlay)
	pcall(bar.ClearAllPoints, bar)
	if height <= 0 then
		if frameH then
			pcall(bar.SetHeight, bar, frameH)
		else
			pcall(bar.SetPoint, bar, "TOPLEFT", overlay, "TOPLEFT", x, y)
			pcall(bar.SetPoint, bar, "BOTTOMRIGHT", overlay, "BOTTOMRIGHT", x, y)
			pcall(bar.SetFrameLevel, bar, GlowLevel(overlay))
			return
		end
	else
		pcall(bar.SetHeight, bar, height)
	end
	if w then
		pcall(bar.SetWidth, bar, w)
		pcall(bar.SetPoint, bar, spec.point, overlay, spec.point, x, y)
	else
		pcall(bar.SetPoint, bar, spec.point, overlay, spec.point, x, y)
		pcall(bar.SetPoint, bar, "LEFT", overlay, "LEFT", x, 0)
		pcall(bar.SetPoint, bar, "RIGHT", overlay, "RIGHT", x, 0)
	end
	pcall(bar.SetFrameLevel, bar, GlowLevel(overlay))
end

local function EnsureCountdownBar(overlay, auraButton)
	local bar = overlay.pihCountdownBar
	if bar then
		return bar
	end
	local parent = auraButton or overlay
	local ok
	ok, bar = pcall(CreateFrame, "StatusBar", nil, parent)
	if not ok or not bar then
		ok, bar = pcall(CreateFrame, "StatusBar", nil, overlay)
	end
	if not ok or not bar then
		return nil
	end
	bar:EnableMouse(false)
	pcall(bar.SetStatusBarTexture, bar, WHITE)
	pcall(bar.SetMinMaxValues, bar, 0, 1)
	pcall(bar.SetValue, bar, 1)
	overlay.pihCountdownBar = bar
	return bar
end

local function StartTestCountdown(bar, seconds, repeatOn)
	if bar.SetScript then
		pcall(bar.SetScript, bar, "OnUpdate", nil)
	end
	pcall(bar.SetMinMaxValues, bar, 0, 1)
	local period = seconds
	local started = GetTime()
	pcall(bar.SetScript, bar, "OnUpdate", function(self)
		local elapsed = (GetTime() - started) % period
		if not repeatOn and elapsed >= period then
			pcall(self.SetValue, self, 0)
			pcall(self.SetScript, self, "OnUpdate", nil)
			return
		end
		pcall(self.SetValue, self, 1 - (elapsed / period))
	end)
end

local function ShowCountdown(overlay, r, g, b, a, opts)
	opts = opts or {}
	local bar = EnsureCountdownBar(overlay, opts.auraButton)
	if not bar then
		return false
	end
	LayoutCountdownBar(bar, overlay)
	if bar.SetStatusBarColor then
		pcall(bar.SetStatusBarColor, bar, r, g, b, a)
	end
	pcall(bar.Show, bar)

	local auraButton = opts.auraButton
	local seconds = opts.countdownSeconds
	if type(seconds) ~= "number" or seconds <= 0 then
		seconds = nil
	end

	if seconds then
		StartTestCountdown(bar, seconds, opts.countdownRepeat == true)
		return true
	end

	if auraButton and auraButton.SetDurationBar then
		overlay.pihCountdownAuraButton = auraButton
		local ok = pcall(auraButton.SetDurationBar, auraButton, bar, DurationBarOpts())
		if not ok then
			ok = pcall(auraButton.SetDurationBar, auraButton, bar)
		end
		if ok then
			return true
		end
	end

	pcall(bar.SetMinMaxValues, bar, 0, 1)
	pcall(bar.SetValue, bar, 1)
	return true
end

local function EnsureAntEdge(overlay, ants, key)
	local edge = ants[key]
	if edge then
		return edge
	end
	local ok
	ok, edge = pcall(CreateFrame, "Frame", nil, overlay)
	if not ok or not edge then
		return nil
	end
	edge:EnableMouse(false)
	if edge.SetClipsChildren then
		pcall(edge.SetClipsChildren, edge, true)
	end
	local strip = CreateFrame("Frame", nil, edge)
	strip:EnableMouse(false)
	local group = strip:CreateAnimationGroup()
	group:SetLooping("REPEAT")
	local trans = group:CreateAnimation("Translation")
	pcall(trans.SetSmoothing, trans, "NONE")
	edge.strip = strip
	edge.group = group
	edge.trans = trans
	edge.dashes = {}
	ants[key] = edge
	return edge
end

local function LayoutAntClip(edge, key, thickness)
	pcall(edge.ClearAllPoints, edge)
	if key == "top" then
		pcall(edge.SetPoint, edge, "TOPLEFT")
		pcall(edge.SetPoint, edge, "TOPRIGHT")
		pcall(edge.SetHeight, edge, thickness)
	elseif key == "bottom" then
		pcall(edge.SetPoint, edge, "BOTTOMLEFT")
		pcall(edge.SetPoint, edge, "BOTTOMRIGHT")
		pcall(edge.SetHeight, edge, thickness)
	elseif key == "left" then
		pcall(edge.SetPoint, edge, "TOPLEFT")
		pcall(edge.SetPoint, edge, "BOTTOMLEFT")
		pcall(edge.SetWidth, edge, thickness)
	else
		pcall(edge.SetPoint, edge, "TOPRIGHT")
		pcall(edge.SetPoint, edge, "BOTTOMRIGHT")
		pcall(edge.SetWidth, edge, thickness)
	end
end

local function AntDash(edge, i)
	local tex = edge.dashes[i]
	if tex then
		return tex
	end
	tex = edge.strip:CreateTexture(nil, "OVERLAY")
	tex:SetTexture(WHITE)
	SnapPixel(tex)
	edge.dashes[i] = tex
	return tex
end

local function PlayAntEdge(edge, edgeLen, period, length, thickness, phaseStart, fromStart, isVert, r, g, b, a)
	local strip = edge.strip
	local span = period + edgeLen + length
	pcall(strip.ClearAllPoints, strip)
	if isVert then
		pcall(strip.SetSize, strip, thickness, span)
		if fromStart then
			pcall(strip.SetPoint, strip, "TOP", edge, "TOP", 0, period)
		else
			pcall(strip.SetPoint, strip, "TOP", edge, "TOP", 0, 0)
		end
	else
		pcall(strip.SetSize, strip, span, thickness)
		if fromStart then
			pcall(strip.SetPoint, strip, "LEFT", edge, "LEFT", -period, 0)
		else
			pcall(strip.SetPoint, strip, "LEFT", edge, "LEFT", 0, 0)
		end
	end

	local n = 0
	local k0 = math.floor((phaseStart - period) / period + 0.0001)
	local k1 = math.floor((phaseStart + edgeLen) / period + 0.0001)
	for k = k0, k1 do
		n = n + 1
		if n > MAX_EDGE_DASHES then
			break
		end
		local d = k * period - phaseStart
		local phys
		if fromStart then
			phys = d
		else
			phys = edgeLen - d - length
		end
		local localPos = fromStart and (phys + period) or phys
		local tex = AntDash(edge, n)
		tex:ClearAllPoints()
		if isVert then
			tex:SetSize(thickness, length)
			tex:SetPoint("TOP", strip, "TOP", 0, -localPos)
		else
			tex:SetSize(length, thickness)
			tex:SetPoint("LEFT", strip, "LEFT", localPos, 0)
		end
		tex:SetVertexColor(r, g, b, a)
		tex:Show()
	end
	for i = n + 1, #edge.dashes do
		edge.dashes[i]:Hide()
	end

	local speed = math.max(0.08, (addon.db and addon.db.glowSpeed) or 1.5)
	local duration = period / math.max(12, 100 * speed)
	local trans = edge.trans
	pcall(edge.group.Stop, edge.group)
	pcall(trans.SetDuration, trans, duration)
	if isVert then
		pcall(trans.SetOffset, trans, 0, fromStart and -period or period)
	else
		pcall(trans.SetOffset, trans, fromStart and period or -period, 0)
	end
	pcall(edge.Show, edge)
	pcall(edge.group.Play, edge.group)
end

local function ShowPixel(overlay, frame, r, g, b, a, thickness)
	local w, h = ReadSize(overlay)
	if not w or w < 8 then
		if frame and frame.pixelW and frame.pixelW >= 8 then
			w, h = frame.pixelW, frame.pixelH or frame.pixelW
		else
			w, h = FrameSize(frame, 64)
		end
	end
	if not w or w < 8 then
		HideAnts(overlay)
		return
	end
	h = h or w
	local db = addon.db
	local lines = math.max(4, math.min(16, math.floor((db and db.glowPixelLines) or 10)))
	local length = math.max(4, math.min(36, math.floor((db and db.glowPixelLength) or 20)))
	thickness = math.max(1, math.min(thickness, math.max(1, math.floor(math.min(w, h) / 2))))
	local period = (2 * (w + h)) / lines
	if period < length + 1 then
		length = math.max(1, period - 1)
	end
	local ants = overlay.pihAnts
	if not ants then
		ants = {}
		overlay.pihAnts = ants
	end
	local specs = {
		{ key = "top",    edgeLen = w, phase = 0,         fromStart = true,  isVert = false },
		{ key = "right",  edgeLen = h, phase = w,         fromStart = true,  isVert = true },
		{ key = "bottom", edgeLen = w, phase = w + h,     fromStart = false, isVert = false },
		{ key = "left",   edgeLen = h, phase = w + h + w, fromStart = false, isVert = true },
	}
	for i = 1, 4 do
		local spec = specs[i]
		local edge = EnsureAntEdge(overlay, ants, spec.key)
		if edge then
			LayoutAntClip(edge, spec.key, thickness)
			PlayAntEdge(edge, spec.edgeLen, period, length, thickness, spec.phase, spec.fromStart, spec.isVert, r, g, b, a)
		end
	end
end

local function HideStarburst(frame)
	if not frame then
		return
	end
	local burst = frame.PIHelperStarburst
	if not burst then
		return
	end
	if burst.ProcStartAnim then
		pcall(burst.ProcStartAnim.Stop, burst.ProcStartAnim)
	end
	if burst.ProcLoopAnim then
		pcall(burst.ProcLoopAnim.Stop, burst.ProcLoopAnim)
	end
	pcall(burst.Hide, burst)
end

local function FrameGlowSize(frame)
	if frame and frame.pixelW and frame.pixelW >= 8 then
		return frame.pixelW, frame.pixelH or frame.pixelW
	end
	local fallback = (addon.db and addon.db.alertIconSize) or 64
	return FrameSize(frame, fallback)
end

local function EnsureStarburst(frame)
	local burst = frame.PIHelperStarburst
	if burst then
		return burst
	end
	local ok
	ok, burst = pcall(CreateFrame, "Frame", nil, frame, "DisableUntrustedLayoutScriptsTemplate")
	if not ok or not burst then
		burst = CreateFrame("Frame", nil, frame)
	end
	burst:EnableMouse(false)
	burst.ProcStart = burst:CreateTexture(nil, "ARTWORK")
	burst.ProcStart:SetBlendMode("ADD")
	burst.ProcStart:SetPoint("CENTER")
	burst.ProcLoop = burst:CreateTexture(nil, "ARTWORK")
	burst.ProcLoop:SetBlendMode("ADD")
	burst.ProcLoop:SetAllPoints()
	local startAtlas = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("UI-HUD-ActionBar-Proc-Start-Flipbook")
	local loopAtlas = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("UI-HUD-ActionBar-Proc-Loop-Flipbook")
	if startAtlas then
		burst.ProcStart:SetAtlas("UI-HUD-ActionBar-Proc-Start-Flipbook")
	else
		burst.ProcStart:SetTexture("Interface\\Cooldown\\star4")
	end
	if loopAtlas then
		burst.ProcLoop:SetAtlas("UI-HUD-ActionBar-Proc-Loop-Flipbook")
	else
		burst.ProcLoop:SetTexture("Interface\\Cooldown\\star4")
	end

	burst.ProcLoopAnim = burst:CreateAnimationGroup()
	burst.ProcLoopAnim:SetLooping("REPEAT")
	local useFlip = false
	if loopAtlas then
		local ok, flipLoop = pcall(burst.ProcLoopAnim.CreateAnimation, burst.ProcLoopAnim, "FlipBook")
		if ok and flipLoop and flipLoop.SetFlipBookRows then
			flipLoop:SetChildKey("ProcLoop")
			flipLoop:SetDuration(1)
			pcall(flipLoop.SetFlipBookRows, flipLoop, 6)
			pcall(flipLoop.SetFlipBookColumns, flipLoop, 5)
			pcall(flipLoop.SetFlipBookFrames, flipLoop, 30)
			burst.pihLoopFlip = flipLoop
			useFlip = true
		end
	end
	if not useFlip then
		burst.ProcLoopAnim:SetLooping("BOUNCE")
		local pulse = burst.ProcLoopAnim:CreateAnimation("Alpha")
		pulse:SetChildKey("ProcLoop")
		pulse:SetFromAlpha(0.35)
		pulse:SetToAlpha(1)
		pulse:SetDuration(0.6)
		pulse:SetSmoothing("IN_OUT")
	end

	burst.ProcStartAnim = burst:CreateAnimationGroup()
	local startFlip = false
	if startAtlas then
		local ok, flipStart = pcall(burst.ProcStartAnim.CreateAnimation, burst.ProcStartAnim, "FlipBook")
		if ok and flipStart and flipStart.SetFlipBookRows then
			flipStart:SetChildKey("ProcStart")
			flipStart:SetDuration(0.7)
			flipStart:SetOrder(1)
			pcall(flipStart.SetFlipBookRows, flipStart, 6)
			pcall(flipStart.SetFlipBookColumns, flipStart, 5)
			pcall(flipStart.SetFlipBookFrames, flipStart, 30)
			burst.pihStartFlip = flipStart
			startFlip = true
		end
	end
	if not startFlip then
		local fade = burst.ProcStartAnim:CreateAnimation("Alpha")
		fade:SetChildKey("ProcStart")
		fade:SetFromAlpha(1)
		fade:SetToAlpha(0)
		fade:SetDuration(0.35)
	end
	burst.ProcStartAnim:SetScript("OnFinished", function(self)
		local parent = self:GetParent()
		if not parent then
			return
		end
		parent.ProcStart:Hide()
		parent.ProcLoop:Show()
		parent.ProcLoopAnim:Play()
	end)
	frame.PIHelperStarburst = burst
	return burst
end

local function CropFlipbookCell(tex, columns, rows)
	if not tex or not tex.SetTexCoord then
		return
	end
	columns = columns or 5
	rows = rows or 6
	pcall(tex.SetTexCoord, tex, 0, 1 / columns, 0, 1 / rows)
end

local function ShowStarburst(frame, r, g, b, a, cover, loopOnly)
	if not frame or FrameIsForbidden(frame) then
		return
	end
	cover = cover or frame
	local burst = EnsureStarburst(frame)
	burst.pihLoopOnly = loopOnly and true or nil
	LayoutRegionToCover(burst, frame, cover, 0.2)
	local w, h
	if cover ~= frame then
		w, h = ReadSize(cover)
	end
	if not w then
		w, h = FrameGlowSize(frame)
	end
	pcall(burst.SetFrameLevel, burst, GlowLevel(frame, cover))
	r = r or (234 / 255)
	g = g or (162 / 255)
	b = b or (33 / 255)
	a = a or 0.90
	burst.ProcStart:SetDesaturated(true)
	burst.ProcStart:SetVertexColor(r, g, b, a)
	burst.ProcLoop:SetDesaturated(true)
	burst.ProcLoop:SetVertexColor(r, g, b, a)
	-- Do not scale FlipBook by glowSpeed (that slider is for pixel/border/fill).
	if burst.pihLoopFlip then
		pcall(burst.pihLoopFlip.SetDuration, burst.pihLoopFlip, 1)
	end
	if burst.pihStartFlip then
		pcall(burst.pihStartFlip.SetDuration, burst.pihStartFlip, 0.7)
	end
	local bw, bh = w * 1.4, h * 1.4
	burst.ProcStart:SetSize((bw / 42 * 150) / 1.4, (bh / 42 * 150) / 1.4)
	pcall(burst.ProcStartAnim.Stop, burst.ProcStartAnim)
	pcall(burst.ProcLoopAnim.Stop, burst.ProcLoopAnim)
	-- AuraButtons forbid addon scripts, so OnFinished never runs there.
	-- Live glows start the repeating loop directly; test/whisper still play
	-- the intro FlipBook on normal frames.
	if burst.pihLoopOnly then
		-- Full flipbook sheets look like a solid yellow fill if FlipBook is
		-- not cropping them. Show one cell; Play still animates when it can.
		pcall(burst.ProcStart.Hide, burst.ProcStart)
		pcall(burst.ProcStart.SetAlpha, burst.ProcStart, 0)
		pcall(burst.ProcStart.SetSize, burst.ProcStart, 1, 1)
		CropFlipbookCell(burst.ProcLoop, 5, 6)
		pcall(burst.ProcLoop.Show, burst.ProcLoop)
		if cover == frame or (w and w >= 8) then
			pcall(burst.Show, burst)
			pcall(burst.ProcLoopAnim.Play, burst.ProcLoopAnim)
		end
		return
	end
	pcall(burst.ProcLoop.Hide, burst.ProcLoop)
	pcall(burst.ProcStart.Show, burst.ProcStart)
	if cover == frame or (w and w >= 8) then
		pcall(burst.Show, burst)
		pcall(burst.ProcStartAnim.Play, burst.ProcStartAnim)
	end
end

-- Hide the engine buff icon so a 1x1 AuraButton does not flash spell art.
local function ShrinkEngineIcon(button)
	local keys = { "Icon", "icon", "IconTexture", "iconTexture" }
	for i = 1, #keys do
		local tex = button[keys[i]]
		if tex and tex.SetAlpha then
			pcall(tex.SetAlpha, tex, 0)
			pcall(tex.SetSize, tex, 1, 1)
		end
	end
end

-- Child of the AuraButton, sized to the unit frame. FlipBook lives here,
-- not on the AuraButton (scripts/anims on that button break SetShown).
local function EnsureLiveHolder(button, host, w, h)
	local holder = button.pihGlowHost
	if not holder then
		local ok
		ok, holder = pcall(CreateFrame, "Frame", nil, button, "DisableUntrustedLayoutScriptsTemplate")
		if not ok or not holder then
			ok, holder = pcall(CreateFrame, "Frame", nil, button)
		end
		if not ok or not holder then
			return nil
		end
		holder:EnableMouse(false)
		if holder.SetClipsChildren then
			pcall(holder.SetClipsChildren, holder, false)
		end
		button.pihGlowHost = holder
	end
	holder:ClearAllPoints()
	local okTL = pcall(holder.SetPoint, holder, "TOPLEFT", host, "TOPLEFT")
	local okBR = pcall(holder.SetPoint, holder, "BOTTOMRIGHT", host, "BOTTOMRIGHT")
	if not (okTL and okBR) then
		pcall(holder.SetPoint, holder, "CENTER", host, "CENTER")
		pcall(holder.SetSize, holder, w or 40, h or w or 40)
	end
	pcall(holder.SetFrameLevel, holder, GlowLevel(host))
	holder.pixelW = w
	holder.pixelH = h
	return holder
end

function addon.DecorateAuraGlow(button, opts)
	if not button then
		return
	end
	local db = addon.db
	if not db then
		return
	end
	opts = opts or {}
	local style = opts.style
	if not style then
		if opts.alert then
			style = db.alertGlowStyle or "starburst"
		else
			style = db.glowStyle or "pixel"
		end
	end
	if style == "proc" then
		style = "starburst"
	end
	if opts.alert and style ~= "none" and style ~= "starburst" then
		style = "starburst"
	end
	if style == "none" then
		addon.ClearGlow(button)
		if button.pihGlowHost then
			addon.ClearGlow(button.pihGlowHost)
			pcall(button.pihGlowHost.Hide, button.pihGlowHost)
		end
		if opts.alert and button.PIHelperFrameGlowHost then
			addon.StopFrameGlow(button)
		elseif opts.host and opts.host.PIHelperFrameGlowHost then
			addon.StopFrameGlow(opts.host)
		end
		return
	end
	local w = opts.width or button.pixelW or 40
	local h = opts.height or button.pixelH or w
	button.pixelW = w
	button.pixelH = h

	local target = button
	local host = opts.host
	if host and not opts.alert then
		addon.ClearGlow(host)
		if host.PIHelperFrameGlowHost then
			addon.StopFrameGlow(host)
		end
		pcall(button.SetSize, button, 1, 1)
		ShrinkEngineIcon(button)
		target = EnsureLiveHolder(button, host, w, h)
		if not target then
			return
		end
		if target.fill then
			pcall(target.fill.Hide, target.fill)
		end
		if target.edges then
			HideEdges(target)
		end
	else
		pcall(button.SetSize, button, w, h)
		if opts.alert then
			addon.ClearGlow(button)
			if button.PIHelperFrameGlowHost then
				addon.StopFrameGlow(button)
			end
			target = EnsureLiveHolder(button, button, w, h)
			if not target then
				target = button
			end
			pcall(target.Show, target)
		end
	end

	local paintOpts = { style = style, auraButton = button }
	if (host and not opts.alert) or opts.alert then
		paintOpts.loopOnly = true
	end
	if opts.alert then
		local ar, ag, ab, aa = addon.GetAlertGlowColor()
		paintOpts.r, paintOpts.g, paintOpts.b, paintOpts.a = ar, ag, ab, aa
	end
	addon.ApplyGlow(target, paintOpts)
	target.pihPaintStyle = style
end

function addon.ClearGlow(frame)
	if not frame then
		return
	end
	HideStarburst(frame)
	local overlay = frame.PIHelperGlow
	if not overlay then
		return
	end
	StopPulse(overlay)
	HideAnts(overlay)
	HideEdges(overlay)
	HideCountdown(overlay)
	if overlay.fill then
		pcall(overlay.fill.Hide, overlay.fill)
	end
	pcall(overlay.SetAlpha, overlay, 1)
	pcall(overlay.Hide, overlay)
end

function addon.ApplyGlow(frame, opts)
	if not frame or FrameIsForbidden(frame) then
		return
	end
	local db = addon.db
	if not db then
		return
	end
	opts = opts or {}
	local style = opts.style or db.glowStyle or "pixel"
	if style == "proc" then
		style = "starburst"
	end
	local r, g, b, a = Color(opts)
	HideStarburst(frame)
	if style == "starburst" then
		local existing = frame.PIHelperGlow
		if existing then
			StopPulse(existing)
			HideAnts(existing)
			HideEdges(existing)
			HideCountdown(existing)
			if existing.fill then
				existing.fill:Hide()
			end
			existing:Hide()
		end
		ShowStarburst(frame, r, g, b, a, frame, opts.loopOnly)
		return
	end
	local overlay = EnsureOverlay(frame)
	if not overlay then
		return
	end
	local thickness = math.max(1, math.min(6, db.glowThickness or 2))
	pcall(overlay.Show, overlay)
	pcall(overlay.SetAlpha, overlay, 1)
	LayoutRegionToCover(overlay, frame, frame)
	pcall(overlay.SetFrameLevel, overlay, GlowLevel(frame))
	StopPulse(overlay)
	HideAnts(overlay)
	HideEdges(overlay)
	HideCountdown(overlay)

	local fill = EnsureFill(overlay)
	if style == "fill" then
		fill:SetVertexColor(r, g, b, math.min(0.55, a * 0.5))
		fill:Show()
		if db.glowBorderPulse ~= false then
			PulseOverlay(overlay, 0.35, 1, db.glowSpeed)
		end
		return
	end
	fill:Hide()

	if style == "pixel" then
		ShowPixel(overlay, frame, r, g, b, a, thickness)
		return
	end

	if style == "countdown" then
		if ShowCountdown(overlay, r, g, b, a, opts) then
			return
		end
	end

	local edges = LayoutEdges(overlay, thickness)
	edges.top:SetVertexColor(r, g, b, a)
	edges.bottom:SetVertexColor(r, g, b, a)
	edges.left:SetVertexColor(r, g, b, a)
	edges.right:SetVertexColor(r, g, b, a)
	edges.top:Show()
	edges.bottom:Show()
	edges.left:Show()
	edges.right:Show()
	if style ~= "countdown" and db.glowBorderPulse ~= false then
		PulseOverlay(overlay, 0.35, 1, db.glowSpeed)
	end
end

-- Whisper/test glows cannot parent to compact unit frames in combat, and
-- those cells clip children. Sit on UIParent and cover the cell instead.
local function LayoutFrameGlowHost(host, frame)
	pcall(host.SetFrameStrata, host, "HIGH")
	pcall(host.SetFrameLevel, host, GlowLevel(frame))
	pcall(host.ClearAllPoints, host)
	if not pcall(host.SetAllPoints, host, frame) then
		LayoutToFrame(host, frame)
	end
	local w, h = ReadSize(frame)
	if w then
		host.pixelW = w
		host.pixelH = h
	end
end

local function EnsureFrameGlowHost(frame)
	if not frame or FrameIsForbidden(frame) then
		return nil
	end
	local host = frame.PIHelperFrameGlowHost
	if not host then
		local ok
		ok, host = pcall(CreateFrame, "Frame", nil, UIParent, "DisableUntrustedLayoutScriptsTemplate")
		if not ok or not host then
			ok, host = pcall(CreateFrame, "Frame", nil, UIParent)
		end
		if not ok or not host then
			return nil
		end
		host:EnableMouse(false)
		if host.SetClipsChildren then
			pcall(host.SetClipsChildren, host, false)
		end
		frame.PIHelperFrameGlowHost = host
		if not frame.PIHelperGlowHostHooked then
			frame.PIHelperGlowHostHooked = true
			pcall(frame.HookScript, frame, "OnHide", function(self)
				local glowHost = self.PIHelperFrameGlowHost
				if glowHost then
					glowHost:Hide()
				end
			end)
			pcall(frame.HookScript, frame, "OnShow", function(self)
				local glowHost = self.PIHelperFrameGlowHost
				if glowHost and glowHost.pihWanted then
					LayoutFrameGlowHost(glowHost, self)
					glowHost:Show()
				end
			end)
		end
	end
	LayoutFrameGlowHost(host, frame)
	host.pihWanted = true
	pcall(host.Show, host)
	return host
end

function addon.StartFrameGlow(frame, opts)
	if not frame or FrameIsForbidden(frame) then
		return
	end
	if addon.IsDisplayedGroupFrame and not addon.IsDisplayedGroupFrame(frame) then
		addon.StopFrameGlow(frame)
		return
	end
	local host = EnsureFrameGlowHost(frame)
	addon.ApplyGlow(host or frame, opts)
	return host or frame
end

function addon.StopFrameGlow(frame)
	if not frame then
		return
	end
	local host = frame.PIHelperFrameGlowHost
	if host then
		host.pihWanted = nil
		addon.ClearGlow(host)
		pcall(host.Hide, host)
	end
	addon.ClearGlow(frame)
end

function addon.StartAlertGlow(frame)
	if not frame then
		return
	end
	local db = addon.db
	local style = db and db.alertGlowStyle or "starburst"
	if not db or style == "none" then
		addon.StopAlertGlow(frame)
		return
	end
	if style ~= "starburst" then
		style = "starburst"
	end
	local target = frame.iconHost or frame
	local ar, ag, ab, aa = addon.GetAlertGlowColor()
	addon.ApplyGlow(target, { style = style, r = ar, g = ag, b = ab, a = aa })
end

function addon.StopAlertGlow(frame)
	if not frame then
		return
	end
	if frame.iconHost then
		addon.ClearGlow(frame.iconHost)
	end
	addon.ClearGlow(frame)
end
