-- ===================================================================
-- ArcUI_AuraFrames.lua
-- Owns all logic specific to true aura frames (_arcViewerType == "aura"):
--   BuffIconCooldownViewer frames showing buff/debuff/totem duration
--
-- Responsibilities:
--   - ShouldShowAuraActiveGlow / ShowAuraActiveGlow / HideAuraActiveGlow
--   - UpdateAuraFrame (was OptimizedApplyIconVisuals in CDMEnhance)
--   - SetAuraInstanceInfo / ClearAuraInstanceInfo hook installation
--   - Initial glow + alpha eval on frame enhancement
--   - EnhanceAuraFrame: single entry point called by CDMEnhance.EnhanceFrame
--   - Threshold glow ticker: GetGlowThresholdCurve / GetGlowThresholdCurveSeconds
--     Start/StopThresholdGlowTracking + 0.5s EvaluateThresholdGlows ticker
--     (CDMEnhance delegates to ns.AuraFrames — single authority)
--
-- NOT responsible for:
--   - Cooldown frames with wasSetFromAura (still owned by CDMEnhance/CooldownState)
--   - auraActiveState.glow on cooldown frames (CDMEnhance calls Show/HideAuraActiveGlow
--     via ns.CDMEnhance.ShowAuraActiveGlow which re-exports from here)
--   - ArcAuras frames (classified as "cooldown", handled by CDMEnhance)
-- ===================================================================

local ADDON, ns = ...

ns.AuraFrames = ns.AuraFrames or {}
local AF = ns.AuraFrames

-- ===================================================================
-- LOCAL DEPENDENCY SHORTCUTS
-- All resolved lazily via ns so load order doesn't matter
-- ===================================================================

local function HasAuraInstanceID(value)
  if ns.API and ns.API.HasAuraInstanceID then
    return ns.API.HasAuraInstanceID(value)
  end
  if value == nil then return false end
  if issecretvalue and issecretvalue(value) then return true end
  return value ~= 0 and value ~= false
end

local function GetEffectiveIconSettingsForFrame(frame)
  return ns.CDMEnhance and ns.CDMEnhance.GetEffectiveIconSettingsForFrame
    and ns.CDMEnhance.GetEffectiveIconSettingsForFrame(frame)
end

local function GetEffectiveStateVisuals(cfg)
  return ns.CDMEnhance and ns.CDMEnhance.GetEffectiveStateVisuals
    and ns.CDMEnhance.GetEffectiveStateVisuals(cfg)
end

local function GetEffectiveReadyAlpha(stateVisuals)
  return ns.CDMEnhance and ns.CDMEnhance.GetEffectiveReadyAlpha
    and ns.CDMEnhance.GetEffectiveReadyAlpha(stateVisuals) or 1.0
end

local function IsFrameHiddenByBar(frame)
  return ns.CDMEnhance and ns.CDMEnhance.IsFrameHiddenByBar
    and ns.CDMEnhance.IsFrameHiddenByBar(frame) or false
end

local function IsCDMEnabled()
  return ns.CDMEnhance and ns.CDMEnhance.IsCDMGroupsEnabledCached
    and ns.CDMEnhance.IsCDMGroupsEnabledCached() or false
end

local function ShowReadyGlow(frame, stateVisuals)
  if ns.CDMEnhance and ns.CDMEnhance.ShowReadyGlow then
    ns.CDMEnhance.ShowReadyGlow(frame, stateVisuals)
  end
end

local function HideReadyGlow(frame)
  if ns.CDMEnhance and ns.CDMEnhance.HideReadyGlow then
    ns.CDMEnhance.HideReadyGlow(frame)
  end
end

local function ShouldShowReadyGlow(stateVisuals, frame)
  return ns.CDMEnhance and ns.CDMEnhance.ShouldShowReadyGlow
    and ns.CDMEnhance.ShouldShowReadyGlow(stateVisuals, frame) or false
end

local function ApplyBorderDesaturation(frame, value)
  if ns.CDMEnhance and ns.CDMEnhance.ApplyBorderDesaturation then
    ns.CDMEnhance.ApplyBorderDesaturation(frame, value)
  end
end

-- ===================================================================
-- THRESHOLD GLOW TICKER
-- Owns curve builders + 0.5s ticker for % and seconds-based glow thresholds.
-- AuraFrames is the single authority; CDMEnhance delegates via ns.AuraFrames.
-- ===================================================================

local glowThresholdCurveCache    = {}
local glowThresholdCurveCacheSec = {}

-- Returns 1 when remaining% <= threshold, 0 above — use with EvaluateRemainingPercent
function AF.GetGlowThresholdCurve(threshold)
  if not C_CurveUtil or not C_CurveUtil.CreateCurve then return nil end
  local key = math.floor(threshold * 1000)
  if glowThresholdCurveCache[key] then return glowThresholdCurveCache[key] end
  local curve = C_CurveUtil.CreateCurve()
  curve:AddPoint(0.0, 1)
  curve:AddPoint(threshold, 1)
  curve:AddPoint(threshold + 0.001, 0)
  curve:AddPoint(1.0, 0)
  glowThresholdCurveCache[key] = curve
  return curve
end

-- Returns 1 when remaining seconds <= threshold — use with EvaluateRemainingDuration
-- Immune to talent-extended duration bugs (Moonfire/Sunfire + Aetherial Kindling, etc.)
function AF.GetGlowThresholdCurveSeconds(seconds)
  if not C_CurveUtil or not C_CurveUtil.CreateCurve then return nil end
  local key = math.floor(seconds * 100)
  if glowThresholdCurveCacheSec[key] then return glowThresholdCurveCacheSec[key] end
  local curve = C_CurveUtil.CreateCurve()
  curve:AddPoint(0.0, 1)
  curve:AddPoint(seconds, 1)
  curve:AddPoint(seconds + 0.001, 0)
  curve:AddPoint(99999, 0)
  glowThresholdCurveCacheSec[key] = curve
  return curve
end

local activeThresholdGlows = {}  -- cdID -> true
local thresholdGlowTicker  = nil

local function EvaluateThresholdGlows()
  local hasActive = false

  for cdID in pairs(activeThresholdGlows) do
    local data = ns.CDMEnhance and ns.CDMEnhance.GetEnhancedFrameData and ns.CDMEnhance.GetEnhancedFrameData(cdID)
    if data and data.frame then
      local frame = data.frame
      local cfg = GetEffectiveIconSettingsForFrame(frame)
      if cfg then
        local stateVisuals = GetEffectiveStateVisuals(cfg)
        if stateVisuals and stateVisuals.readyGlow
          and (stateVisuals.glowThresholdSeconds or (stateVisuals.glowThreshold and stateVisuals.glowThreshold < 1.0))
          and not stateVisuals.glowFollowPandemic then
          if ShouldShowReadyGlow(stateVisuals, frame) then
            local auraID = frame.auraInstanceID
            local isThresholdPreview = ns.CDMEnhanceOptions
              and ns.CDMEnhanceOptions.IsGlowPreviewActive
              and ns.CDMEnhanceOptions.IsGlowPreviewActive(cdID)
            if isThresholdPreview then
              hasActive = true
              ShowReadyGlow(frame, stateVisuals)
            elseif (frame._arcAuraActive ~= nil and frame._arcAuraActive)
              or (frame._arcAuraActive == nil and HasAuraInstanceID(auraID)) then
              hasActive = true

              -- Determine tracked unit
              local auraType   = stateVisuals.glowAuraType or "auto"
              local trackedUnit = "player"
              if auraType == "debuff" then
                trackedUnit = "target"
              elseif auraType == "auto" then
                local Shared = ns.Shared or ns.CDMEnhance and ns.CDMEnhance.Shared
                local cdInfo = Shared and Shared.SafeGetCDMInfo and Shared.SafeGetCDMInfo(cdID)
                if cdInfo and cdInfo.category == 3 then trackedUnit = "target" end
              end

              local threshSec = stateVisuals.glowThresholdSeconds
              local function evalDurObj(durObj)
                if threshSec then
                  local curve = AF.GetGlowThresholdCurveSeconds(threshSec)
                  if curve then
                    local ok, val = pcall(durObj.EvaluateRemainingDuration, durObj, curve)
                    return ok and val or nil
                  end
                else
                  local curve = AF.GetGlowThresholdCurve(stateVisuals.glowThreshold)
                  if curve then return durObj:EvaluateRemainingPercent(curve) end
                end
              end

              local durObj = C_UnitAuras and C_UnitAuras.GetAuraDuration
                and C_UnitAuras.GetAuraDuration(trackedUnit, auraID)
              if not durObj then
                local fallback = trackedUnit == "player" and "target" or "player"
                durObj = C_UnitAuras and C_UnitAuras.GetAuraDuration
                  and C_UnitAuras.GetAuraDuration(fallback, auraID)
              end

              if durObj then
                local glowAlpha = evalDurObj(durObj)
                if glowAlpha ~= nil then
                  if ns.CDMEnhance and ns.CDMEnhance.SetGlowAlpha then
                    ns.CDMEnhance.SetGlowAlpha(frame, glowAlpha, stateVisuals)
                  end
                else
                  ShowReadyGlow(frame, stateVisuals)
                end
              else
                ShowReadyGlow(frame, stateVisuals)
              end
            else
              activeThresholdGlows[cdID] = nil
              HideReadyGlow(frame)
            end
          else
            activeThresholdGlows[cdID] = nil
            HideReadyGlow(frame)
          end
        else
          activeThresholdGlows[cdID] = nil
        end
      else
        activeThresholdGlows[cdID] = nil
      end
    else
      activeThresholdGlows[cdID] = nil
    end
  end

  if not hasActive and thresholdGlowTicker then
    thresholdGlowTicker:Cancel()
    thresholdGlowTicker = nil
  end
end

function AF.StartThresholdGlowTracking(cdID)
  if not cdID then return end
  activeThresholdGlows[cdID] = true
  EvaluateThresholdGlows()
  if not thresholdGlowTicker then
    thresholdGlowTicker = C_Timer.NewTicker(0.5, EvaluateThresholdGlows)
  end
end

function AF.StopThresholdGlowTracking(cdID)
  if not cdID then return end
  activeThresholdGlows[cdID] = nil
  if not next(activeThresholdGlows) and thresholdGlowTicker then
    thresholdGlowTicker:Cancel()
    thresholdGlowTicker = nil
  end
end

-- Local aliases for internal callers (UpdateAuraFrame references these)
local function StartThresholdGlowTracking(cdID) AF.StartThresholdGlowTracking(cdID) end
local function StopThresholdGlowTracking(cdID)  AF.StopThresholdGlowTracking(cdID)  end

-- ===================================================================
-- AURA ACTIVE GLOW
-- Glow shown when the associated buff/debuff is active (or missing,
-- for glowWhenMissing). Used by both true aura frames AND cooldown
-- frames that have auraActiveState.glow configured.
-- ===================================================================

function AF.ShouldShowAuraActiveGlow(auraActiveCfg, frame, isReady)
  -- Preview mode: always show
  if frame and frame.cooldownID then
    if ns.CDMEnhanceOptions and ns.CDMEnhanceOptions.IsAuraGlowPreviewActive then
      if ns.CDMEnhanceOptions.IsAuraGlowPreviewActive(frame.cooldownID) then
        return true
      end
    end
  end

  if not auraActiveCfg then return false end

  -- glowFollowPandemic: CDM pandemic hooks own show/hide — suppress normal aura-gain path
  if auraActiveCfg.glowFollowPandemic then return false end

  local glowOnActive  = auraActiveCfg.glow == true
  local glowOnMissing = auraActiveCfg.glowWhenMissing == true
  if not glowOnActive and not glowOnMissing then return false end

  if auraActiveCfg.glowCombatOnly then
    local inCombat = InCombatLockdown() or UnitAffectingCombat("player")
    if not inCombat then return false end
  end

  if isReady ~= nil then
    if isReady  and glowOnActive  then return true end
    if not isReady and glowOnMissing then return true end
    return false
  end

  return true
end

function AF.ShowAuraActiveGlow(frame, auraActiveCfg)
  if not frame or not auraActiveCfg or not ns.Glows then return end

  local glowType  = auraActiveCfg.glowType or "button"
  local r, g, b   = 1, 0.85, 0.1
  if auraActiveCfg.glowColor then
    r = auraActiveCfg.glowColor.r or 1
    g = auraActiveCfg.glowColor.g or 0.85
    b = auraActiveCfg.glowColor.b or 0.1
  end
  local intensity  = auraActiveCfg.glowIntensity  or 1.0
  local scale      = auraActiveCfg.glowScale      or 1.0
  local speed      = auraActiveCfg.glowSpeed      or 0.25
  local lines      = auraActiveCfg.glowLines      or 8
  local thickness  = auraActiveCfg.glowThickness  or 2
  local particles  = auraActiveCfg.glowParticles  or 4
  local strata     = auraActiveCfg.glowFrameStrata
  local frameLevel = auraActiveCfg.glowFrameLevel

  local padding = 0
  if frame._arcConfig and frame._arcConfig.padding then
    padding = frame._arcConfig.padding
  elseif frame._arcPadding then
    padding = frame._arcPadding
  end
  local glowOffset = -(padding or 0)

  ns.Glows.Start(frame, "ArcUI_AuraGlow", glowType, {
    color     = {r, g, b, intensity},
    intensity = intensity,
    scale     = scale,
    frequency = speed,
    lines     = lines,
    thickness = thickness,
    particles = particles,
    xOffset   = glowOffset + (auraActiveCfg.glowXOffset or 0),
    yOffset   = glowOffset + (auraActiveCfg.glowYOffset or 0),
    translateX = auraActiveCfg.glowTranslateX or 0,
    translateY = auraActiveCfg.glowTranslateY or 0,
    strata    = (strata ~= "inherit") and strata or nil,
    frameLevel = frameLevel,
  })

  frame._arcAuraActiveGlowActive = true
  frame._arcAuraActiveGlowType   = glowType
end

function AF.HideAuraActiveGlow(frame)
  if not frame then return end
  if not frame._arcAuraActiveGlowActive then return end
  if ns.Glows then ns.Glows.Stop(frame, "ArcUI_AuraGlow") end
  frame._arcAuraActiveGlowActive = false
  frame._arcAuraActiveGlowType   = nil
  frame._arcAuraActiveGlowSig    = nil
  -- Restore alpha if it was forced visible for preview
  if frame._arcAuraGlowPreviewAlpha then
    frame._arcBypassAlphaHook = true
    frame:SetAlpha(frame._arcAuraGlowPreviewAlpha)
    frame._arcBypassAlphaHook = false
    frame._arcAuraGlowPreviewAlpha = nil
  end
end

-- ===================================================================
-- UPDATE AURA FRAME
-- Was OptimizedApplyIconVisuals in CDMEnhance.
-- Called from:
--   1. SetAuraInstanceInfo hook  (aura gained)
--   2. ClearAuraInstanceInfo hook (aura lost)
--   3. EnhanceAuraFrame initial eval (login/reload)
--   4. CDMEnhance.OptimizedApplyIconVisuals shim (backward compat)
-- ===================================================================

function AF.UpdateAuraFrame(frame)
  if not frame then return end

  if not IsCDMEnabled() then return end
  if IsFrameHiddenByBar(frame) then return end

  -- THROTTLE: same state, called too recently → skip
  local now           = GetTime()
  local lastCall      = frame._arcLastOptimizedCall or 0
  local lastAuraActive= frame._arcLastAuraActive
  local currentAuraActive = HasAuraInstanceID(frame.auraInstanceID)
  local cdID          = frame.cooldownID

  local hasDelay = frame._arcDelayAlphaUntil and now < frame._arcDelayAlphaUntil
  if ns.DynamicLayoutDebug and ns.DynamicLayoutDebug.IsAlphaTraceEnabled
      and ns.DynamicLayoutDebug.IsAlphaTraceEnabled() and hasDelay then
    ns.DynamicLayoutDebug.AddAlphaTrace("OPTIMIZE_ENTRY", cdID,
      string.format("hasDelay=%s throttle=%s", tostring(hasDelay),
        tostring((now - lastCall) < 0.1)))
  end

  if (now - lastCall) < 0.1 and lastAuraActive == currentAuraActive then
    if ns.DynamicLayoutDebug and ns.DynamicLayoutDebug.IsAlphaTraceEnabled
        and ns.DynamicLayoutDebug.IsAlphaTraceEnabled() and hasDelay then
      ns.DynamicLayoutDebug.AddAlphaTrace("OPTIMIZE_THROTTLED", cdID, "same state, too recent")
    end
    return
  end
  frame._arcLastOptimizedCall = now
  frame._arcLastAuraActive    = currentAuraActive

  local optionsPanelOpen = ns.CDMEnhance.IsOptionsPanelOpen
    and ns.CDMEnhance.IsOptionsPanelOpen() or false

  local cfg = GetEffectiveIconSettingsForFrame(frame)
  if not cfg then return end

  -- ignoreAuraOverride: cooldown state owns alpha, not aura state
  local ignoreAuraOverride = (cfg.auraActiveState and cfg.auraActiveState.ignoreAuraOverride)
                          or (cfg.cooldownSwipe   and cfg.cooldownSwipe.ignoreAuraOverride)
  if ignoreAuraOverride then return end

  local stateVisuals    = GetEffectiveStateVisuals(cfg)
  local hasAuraActiveGlow = cfg.auraActiveState
    and (cfg.auraActiveState.glow == true or cfg.auraActiveState.glowWhenMissing == true)
  local isAuraGlowPreview = ns.CDMEnhanceOptions and ns.CDMEnhanceOptions.IsAuraGlowPreviewActive
    and ns.CDMEnhanceOptions.IsAuraGlowPreviewActive(frame.cooldownID)

  if not stateVisuals and not hasAuraActiveGlow and not isAuraGlowPreview then
    if not optionsPanelOpen then
      if frame._arcAuraActiveGlowActive then AF.HideAuraActiveGlow(frame) end
      if ns.CustomLabel and ns.CustomLabel.UpdateVisibility then
        ns.CustomLabel.UpdateVisibility(frame)
      end
      return
    end
  end

  -- Icon texture
  local iconTex = frame.Icon or frame.icon
  if iconTex then
    local actualTex = iconTex
    if not iconTex.SetDesaturated and iconTex.Icon then actualTex = iconTex.Icon end
    iconTex = actualTex
  end

  -- Route: only process if this is actually an aura/totem frame
  -- wasSetFromAura covers cooldown frames that happen to show aura data —
  -- those stay in CDMEnhance/CooldownState for Phase 1.
  if not cfg._isAura and not frame.totemData and frame.wasSetFromAura ~= true then
    if not hasAuraActiveGlow and not frame._arcAuraActiveGlowActive then return end
  end

  local hasAuraOrTotem = HasAuraInstanceID(frame.auraInstanceID) or (frame.totemData ~= nil)
  -- _arcAuraStateHooked: frame is a real aura type, buff just not currently active
  local isAura         = cfg._isAura or hasAuraOrTotem or (frame._arcAuraStateHooked == true)
  local isReady        = false

  if isAura or hasAuraOrTotem then
    isReady = hasAuraOrTotem
  else
    -- Cooldown frame with no tracked aura — handle aura active glow only
    if hasAuraActiveGlow or frame._arcAuraActiveGlowActive or isAuraGlowPreview then
      local aaCfg = cfg.auraActiveState or (isAuraGlowPreview and {} or nil)
      if AF.ShouldShowAuraActiveGlow(aaCfg, frame, false) then
        AF.ShowAuraActiveGlow(frame, aaCfg)
      else
        AF.HideAuraActiveGlow(frame)
      end
    end
    if ns.CustomLabel and ns.CustomLabel.UpdateVisibility then
      ns.CustomLabel.UpdateVisibility(frame)
    end
    return
  end

  -- No state visuals configured: glow-only path (unless options panel open for preview)
  if not stateVisuals then
    local aaCfg = cfg.auraActiveState or (isAuraGlowPreview and {} or nil)
    if aaCfg and (aaCfg.glow or aaCfg.glowWhenMissing or isAuraGlowPreview) then
      if AF.ShouldShowAuraActiveGlow(aaCfg, frame, isReady) then
        AF.ShowAuraActiveGlow(frame, aaCfg)
      else
        AF.HideAuraActiveGlow(frame)
      end
    end
    if ns.CustomLabel and ns.CustomLabel.UpdateVisibility then
      ns.CustomLabel.UpdateVisibility(frame)
    end
    if not optionsPanelOpen then return end
    -- options panel open: fall through to apply 0.35 preview opacity
  end

  -- Alpha + desat
  local targetAlpha, targetDesat
  if not stateVisuals then
    -- Only preview at 0.35 if the frame is actually hidden (alpha 0).
    -- If the frame is already visible (e.g. missing-aura opacity set to 1),
    -- leave it alone — don't force it down to 0.35.
    local currentAlpha = frame._arcTargetAlpha or 0
    targetAlpha = (currentAlpha <= 0) and 0.35 or currentAlpha
    targetDesat = 0
  elseif isReady then
    targetAlpha = GetEffectiveReadyAlpha(stateVisuals)
    targetDesat = stateVisuals.readyDesaturate and 1 or 0
  else
    local cdAlpha = stateVisuals.cooldownAlpha
    targetAlpha = (cdAlpha <= 0) and (optionsPanelOpen and 0.35 or 0) or cdAlpha
    targetDesat = stateVisuals.cooldownDesaturate and 1 or 0
  end

  local effectiveReadyAlpha = stateVisuals and GetEffectiveReadyAlpha(stateVisuals) or 1
  if isReady and effectiveReadyAlpha < 1.0 then
    frame._arcEnforceReadyAlpha  = true
    frame._arcReadyAlphaValue    = effectiveReadyAlpha
  else
    frame._arcEnforceReadyAlpha  = false
  end

  -- Center alignment delay
  local delayAlpha = frame._arcDelayAlphaUntil and now < frame._arcDelayAlphaUntil
  if delayAlpha and targetAlpha > 0 then
    if ns.DynamicLayoutDebug and ns.DynamicLayoutDebug.IsAlphaTraceEnabled
        and ns.DynamicLayoutDebug.IsAlphaTraceEnabled() then
      ns.DynamicLayoutDebug.AddAlphaTrace("ALPHA_BLOCKED_BY_DELAY", cdID,
        string.format("target=%.2f remaining=%.3fms", targetAlpha,
          (frame._arcDelayAlphaUntil - now) * 1000))
    end
    frame._arcTargetAlpha          = nil
    frame._arcBypassFrameAlphaHook = true
    frame:SetAlpha(0)
    if frame.Cooldown then frame.Cooldown:SetAlpha(0) end
    frame._arcBypassFrameAlphaHook = false
    return
  elseif frame._arcDelayAlphaUntil and now >= frame._arcDelayAlphaUntil then
    if ns.DynamicLayoutDebug and ns.DynamicLayoutDebug.IsAlphaTraceEnabled
        and ns.DynamicLayoutDebug.IsAlphaTraceEnabled() then
      ns.DynamicLayoutDebug.AddAlphaTrace("DELAY_EXPIRED_AUTO", cdID, "clearing flag")
    end
    frame._arcDelayAlphaUntil = nil
  end

  if ns.DynamicLayoutDebug and ns.DynamicLayoutDebug.IsAlphaTraceEnabled
      and ns.DynamicLayoutDebug.IsAlphaTraceEnabled() then
    ns.DynamicLayoutDebug.AddAlphaTrace("SETALPHA", cdID,
      string.format("%.2f -> %.2f", frame._arcTargetAlpha or 0, targetAlpha))
  end

  frame._arcTargetAlpha          = targetAlpha
  frame._arcBypassFrameAlphaHook = true
  frame:SetAlpha(targetAlpha)
  if frame.Cooldown then frame.Cooldown:SetAlpha(targetAlpha) end
  frame._arcBypassFrameAlphaHook = false
  frame._lastAppliedAlpha = targetAlpha

  -- Preserve duration text: keep aura countdown readable when active but alpha < 1
  local rs = cfg.cooldownStateVisuals and cfg.cooldownStateVisuals.readyState
  local shouldPreserve = isReady and rs and rs.preserveDurationText == true and targetAlpha < 1.0
  frame._arcPreserveDurationText = shouldPreserve == true
  if shouldPreserve and ns.CooldownState and ns.CooldownState.PreserveDurationText then
    if frame.Cooldown then frame.Cooldown:SetAlpha(1) end
    ns.CooldownState.PreserveDurationText(frame)
  elseif not shouldPreserve and frame.Cooldown and frame.Cooldown.SetIgnoreParentAlpha then
    frame.Cooldown:SetIgnoreParentAlpha(false)
  end

  if not frame:IsShown() then frame:Show() end

  if iconTex then
    frame._arcTargetDesat        = targetDesat
    frame._arcBypassDesatHook    = true
    if iconTex.SetDesaturation then
      iconTex:SetDesaturation(targetDesat)
    else
      iconTex:SetDesaturated(targetDesat == 1)
    end
    frame._arcBypassDesatHook = false
    ApplyBorderDesaturation(frame, targetDesat)
  end

  -- Tint
  local targetTintR, targetTintG, targetTintB = 1, 1, 1
  if not isReady and stateVisuals and stateVisuals.cooldownTint and stateVisuals.cooldownTintColor then
    local col = stateVisuals.cooldownTintColor
    targetTintR = col.r or 0.5
    targetTintG = col.g or 0.5
    targetTintB = col.b or 0.5
  end
  local tintKey = string.format("%.2f,%.2f,%.2f", targetTintR, targetTintG, targetTintB)
  if iconTex and frame._arcTargetTint ~= tintKey then
    frame._arcTargetTint = tintKey
    iconTex:SetVertexColor(targetTintR, targetTintG, targetTintB)
  end

  -- Ready glow: only pure aura frames (not wasSetFromAura cooldown frames)
  -- Cooldown frames use the curve-driven glow path in ApplyCooldownStateVisuals
  -- If _arcCooldownEventDriven=true the cooldown path fully owns the ready glow.
  -- Defer a forced OnCooldownEvent so CDM's totem sweep finishes before we
  -- re-read the shadow. forceVisuals=true bypasses the idle-skip cache so the
  -- glow is correctly hidden out of combat after totem placement.
  local isCooldownFrame = not cfg._isAura and (frame.totemData == nil or frame._arcCooldownEventDriven)
  if not isCooldownFrame and stateVisuals then
    local isReadyGlowPreview = ns.CDMEnhanceOptions and ns.CDMEnhanceOptions.IsGlowPreviewActive
      and ns.CDMEnhanceOptions.IsGlowPreviewActive(frame.cooldownID)
    local threshold = stateVisuals.glowThreshold or 1.0
    local isReadyOrPreview = isReady or isReadyGlowPreview
    if stateVisuals.glowFollowPandemic then
      -- ShowPandemicStateFrame/CheckTriggerAuraAppliedAlert own show/hide for live play.
      -- Preview: always show. Aura lost: always hide.
      -- Aura active: check _arcPandemicGlowActive — if pandemic window is over, hide.
      if isReadyGlowPreview then
        ShowReadyGlow(frame, stateVisuals)
      elseif not isReady then
        HideReadyGlow(frame)
      elseif not frame._arcPandemicGlowActive then
        -- Aura active but pandemic window ended (flag cleared by CheckTriggerAuraAppliedAlert
        -- or TriggerAlertEvent) — hide the glow now.
        HideReadyGlow(frame)
      end
      frame._arcTargetGlow = true
    elseif threshold >= 1.0 and not stateVisuals.glowThresholdSeconds then
      if ShouldShowReadyGlow(stateVisuals, frame) and isReadyOrPreview then
        ShowReadyGlow(frame, stateVisuals)
      else
        HideReadyGlow(frame)
      end
      frame._arcTargetGlow = true
    else
      if ShouldShowReadyGlow(stateVisuals, frame) and isReadyOrPreview then
        if cdID then StartThresholdGlowTracking(cdID) end
      else
        if cdID then StopThresholdGlowTracking(cdID) end
        HideReadyGlow(frame)
      end
      frame._arcTargetGlow = true
    end
  elseif frame._arcCooldownEventDriven and not frame._arcTotemCooldownPending then
    -- Schedule a deferred forced re-evaluation so CDM's totem sweep has time
    -- to finish updating the shadow before we read it.
    frame._arcTotemCooldownPending = true
    C_Timer.After(0.1, function()
      frame._arcTotemCooldownPending = nil
      if ns.CDMEnhance and ns.CDMEnhance.OnCooldownEvent then
        ns.CDMEnhance.OnCooldownEvent(frame, false, false, true) -- forceVisuals=true
      end
    end)
  end

  -- Aura active glow (both aura frames and cooldown frames with auraActiveState.glow)
  if hasAuraActiveGlow or frame._arcAuraActiveGlowActive or isAuraGlowPreview then
    local aaCfg = cfg.auraActiveState or (isAuraGlowPreview and {} or nil)
    if AF.ShouldShowAuraActiveGlow(aaCfg, frame, isReady) then
      -- Preview: force frame visible if alpha=0 (icon invisible when buff inactive)
      if isAuraGlowPreview and frame:GetAlpha() <= 0 then
        frame._arcBypassAlphaHook = true
        frame:SetAlpha(0.35)
        frame._arcBypassAlphaHook = false
      end
      AF.ShowAuraActiveGlow(frame, aaCfg)
    else
      AF.HideAuraActiveGlow(frame)
    end
  end

  if ns.CustomLabel and ns.CustomLabel.UpdateVisibility then
    ns.CustomLabel.UpdateVisibility(frame)
  end
end

-- ===================================================================
-- HOOK INSTALLATION
-- Installs OnAuraInstanceInfoSet / OnAuraInstanceInfoCleared hooks on a frame.
-- These fire exactly once per real aura gained/lost (confirmed via AuraHook debugger).
-- Replaces SetAuraInstanceInfo/ClearAuraInstanceInfo which fired on every CDM general
-- refresh (~2-3/s) even with no aura state change — those were noisy and wasteful.
-- Called once per frame from EnhanceAuraFrame.
-- The hooks call UpdateAuraFrame directly — no duplicate glow calls.
-- ===================================================================

function AF.InstallHooks(frame, cdID)
  if frame._arcAuraStateHooked then return end
  frame._arcAuraStateHooked = true

  if frame.OnAuraInstanceInfoSet then
    hooksecurefunc(frame, "OnAuraInstanceInfoSet", function(self)
      -- glowFollowPandemic: detect genuine reapplication via _arcAuraActive false→true.
      -- Covers both ID-change reapplications AND same-ID totem replacements.
      -- Read previous state BEFORE updating _arcAuraActive below.
      local wasActive = self._arcLastPandemicAuraActive
      local nowActive = HasAuraInstanceID(self.auraInstanceID)
      self._arcLastPandemicAuraActive = nowActive
      if self._arcPandemicGlowActive and nowActive and wasActive == false then
        self._arcPandemicGlowActive = nil
        local cfgP = ns.CDMEnhance and ns.CDMEnhance.GetEffectiveIconSettingsForFrame
          and ns.CDMEnhance.GetEffectiveIconSettingsForFrame(self)
        local aasP = cfgP and cfgP.auraActiveState
        local svP  = cfgP and ns.CDMEnhance.GetEffectiveStateVisuals
          and ns.CDMEnhance.GetEffectiveStateVisuals(cfgP)
        if aasP and aasP.glowFollowPandemic then
          AF.HideAuraActiveGlow(self)
        elseif svP and svP.glowFollowPandemic then
          if ns.CDMEnhance.HideReadyGlow then ns.CDMEnhance.HideReadyGlow(self) end
        end
      end

      -- Confirm aura is actually present before caching true
      self._arcAuraActive = HasAuraInstanceID(self.auraInstanceID)
      if self._arcIgnoreAuraOverride then
        -- Trigger only — CooldownState.Apply reads HasAuraInstanceID(auraInstanceID) fresh.
        if ns.CooldownState and ns.CooldownState.Apply then
          local cfg = ns.CDMEnhance and ns.CDMEnhance.GetEffectiveIconSettingsForFrame
            and ns.CDMEnhance.GetEffectiveIconSettingsForFrame(self)
          if cfg then ns.CooldownState.Apply(self, cfg) end
        end
      else
        -- DIRECT glow call: aura gained = show glow. No routing, no throttle, no stateVisuals check.
        local cfg = ns.CDMEnhance and ns.CDMEnhance.GetEffectiveIconSettingsForFrame
          and ns.CDMEnhance.GetEffectiveIconSettingsForFrame(self)
        local aaCfg = cfg and cfg.auraActiveState
        if aaCfg and (aaCfg.glow or aaCfg.glowWhenMissing) then
          if AF.ShouldShowAuraActiveGlow(aaCfg, self, true) then
            AF.ShowAuraActiveGlow(self, aaCfg)
          else
            AF.HideAuraActiveGlow(self)
          end
        end
        -- UpdateAuraFrame handles alpha/desat/label (may throttle - that is fine for those)
        if ns.AuraFrames and ns.AuraFrames.UpdateAuraFrame then
          ns.AuraFrames.UpdateAuraFrame(self)
        end
      end
      if ns.CustomLabel and ns.CustomLabel.UpdateVisibility then
        ns.CustomLabel.UpdateVisibility(self)
      end
      -- SINGLE STACK
      if self._arcSingleStackText then
        local unit = self.auraDataUnit or "player"
        local count = C_UnitAuras.GetAuraApplicationDisplayCount(unit, self.auraInstanceID, 1)
        self._arcSingleStackText:SetText(count)
      end
    end)
  end

  if frame.OnAuraInstanceInfoCleared then
    hooksecurefunc(frame, "OnAuraInstanceInfoCleared", function(self)
      -- Seed false so the next OnAuraInstanceInfoSet detects the false→true transition
      self._arcLastPandemicAuraActive = false
      -- Confirm aura is actually gone before caching false
      self._arcAuraActive = HasAuraInstanceID(self.auraInstanceID)
      if self._arcIgnoreAuraOverride then
        -- Trigger only — CooldownState.Apply reads HasAuraInstanceID(auraInstanceID) fresh.
        if ns.CooldownState and ns.CooldownState.Apply then
          local cfg = ns.CDMEnhance and ns.CDMEnhance.GetEffectiveIconSettingsForFrame
            and ns.CDMEnhance.GetEffectiveIconSettingsForFrame(self)
          if cfg then ns.CooldownState.Apply(self, cfg) end
        end
      else
        -- DIRECT glow call: aura lost = hide glow (or show glowWhenMissing).
        local cfg = ns.CDMEnhance and ns.CDMEnhance.GetEffectiveIconSettingsForFrame
          and ns.CDMEnhance.GetEffectiveIconSettingsForFrame(self)
        local aaCfg = cfg and cfg.auraActiveState
        if aaCfg and (aaCfg.glow or aaCfg.glowWhenMissing) then
          if AF.ShouldShowAuraActiveGlow(aaCfg, self, false) then
            AF.ShowAuraActiveGlow(self, aaCfg)
          else
            AF.HideAuraActiveGlow(self)
          end
        end
        if ns.AuraFrames and ns.AuraFrames.UpdateAuraFrame then
          ns.AuraFrames.UpdateAuraFrame(self)
        end
      end
      if ns.CustomLabel and ns.CustomLabel.UpdateVisibility then
        ns.CustomLabel.UpdateVisibility(self)
      end
      -- Clear mirror fontstring when aura drops
      if self._arcSingleStackText then
        self._arcSingleStackText:SetText("")
      end
    end)
  end
  frame._arcAuraEventDriven = true

  -- ── TOTEM HOOKS ────────────────────────────────────────────────────
  -- SetTotemData/ClearTotemData fire when PLAYER_TOTEM_UPDATE causes CDM
  -- to assign or remove totem data on the frame. Hooking these gives us
  -- instant dispatch instead of waiting for the 0.5s ticker to notice
  -- totemData changed — same pattern as OnAuraInstanceInfoSet/Cleared.
  -- ── TOTEM HOOK ─────────────────────────────────────────────────────
  -- OnPlayerTotemUpdateEvent fires only when CDM decides this frame actually
  -- needs a totem update (NeedsTotemUpdate check passed) — much sparser than
  -- hooking SetTotemData/ClearTotemData which fire on every CDM refresh cycle.
  -- After this fires, frame.totemData reflects the new state (set or nil).
  if frame.OnPlayerTotemUpdateEvent and not frame._arcTotemDataHooked then
    frame._arcTotemDataHooked = true

    hooksecurefunc(frame, "OnPlayerTotemUpdateEvent", function(self)
      if self._arcCooldownEventDriven then
        local cfg = ns.CDMEnhance and ns.CDMEnhance.GetEffectiveIconSettingsForFrame
          and ns.CDMEnhance.GetEffectiveIconSettingsForFrame(self)
        if cfg and ns.CooldownState and ns.CooldownState.Apply then
          ns.CooldownState.Apply(self, cfg)
        end
      else
        if ns.AuraFrames and ns.AuraFrames.UpdateAuraFrame then
          ns.AuraFrames.UpdateAuraFrame(self)
        end
      end
    end)
  end
end

-- ===================================================================
-- ENHANCE AURA FRAME
-- Single entry point called from CDMEnhance.EnhanceFrame for
-- _arcViewerType == "aura" frames. Installs hooks + runs initial eval.
-- ===================================================================

function AF.EnhanceAuraFrame(frame, cdID)
  if not frame or not cdID then return end

  -- Always restore _arcAuraEventDriven here, not just inside InstallHooks.
  -- CDMEnhance clears it on spec change then calls EnhanceAuraFrame again,
  -- but InstallHooks bails early on _arcAuraStateHooked=true so flag never restores.
  -- Without it CooldownState leaks ready glow onto aura frames.
  frame._arcAuraEventDriven = true

  -- Install aura state hooks (idempotent)
  AF.InstallHooks(frame, cdID)

  -- Initial glow eval: handles login/reload where hooks haven't fired yet
  local initCfg = GetEffectiveIconSettingsForFrame(frame)
  if initCfg and initCfg.auraActiveState then
    local aaCfg = initCfg.auraActiveState
    if aaCfg.glow or aaCfg.glowWhenMissing then
      local hasAura = HasAuraInstanceID(frame.auraInstanceID)
      frame._arcAuraActive = hasAura  -- seed cache on first enhance (login/reload)
      if AF.ShouldShowAuraActiveGlow(aaCfg, frame, hasAura) then
        AF.ShowAuraActiveGlow(frame, aaCfg)
      else
        AF.HideAuraActiveGlow(frame)
      end
    end
  end

  -- Initial alpha/desat: clear throttle cache so this always runs
  frame._arcLastOptimizedCall = nil
  frame._arcLastAuraActive    = nil
  AF.UpdateAuraFrame(frame)
end

-- ===================================================================
-- BACKWARD COMPAT RE-EXPORTS ON ns.CDMEnhance
-- Cooldown frames (auraActiveState.glow, HideAllCombatOnlyGlows, etc.)
-- call these through ns.CDMEnhance — keep those call sites working.
-- ===================================================================

-- Set immediately (AuraFrames loads after CDMEnhance in TOC order)
local function InstallCompatShims()
  if not ns.CDMEnhance then return end

  -- OptimizedApplyIconVisuals → UpdateAuraFrame
  ns.CDMEnhance.OptimizedApplyIconVisuals  = AF.UpdateAuraFrame

  -- Threshold glow ticker (AuraFrames is now the authority)
  ns.CDMEnhance.StartThresholdGlowTracking   = AF.StartThresholdGlowTracking
  ns.CDMEnhance.StopThresholdGlowTracking    = AF.StopThresholdGlowTracking
  ns.CDMEnhance.GetGlowThresholdCurve        = AF.GetGlowThresholdCurve
  ns.CDMEnhance.GetGlowThresholdCurveSeconds = AF.GetGlowThresholdCurveSeconds
end

-- Run after ADDON_LOADED so ns.CDMEnhance is guaranteed populated
local shimFrame = CreateFrame("Frame")
shimFrame:RegisterEvent("ADDON_LOADED")
shimFrame:SetScript("OnEvent", function(self, event, addon)
  if addon == ADDON then
    InstallCompatShims()
    self:UnregisterEvent("ADDON_LOADED")
  end
end)