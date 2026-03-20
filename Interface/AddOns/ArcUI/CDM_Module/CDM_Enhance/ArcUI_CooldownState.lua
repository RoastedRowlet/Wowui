-- ===================================================================
-- ArcUI_CooldownState.lua
-- Consolidated cooldown state visual system
-- v3.3.0: ArcAuras-pattern refactor — single feed+apply, no cascade
--
-- ARCHITECTURE: Owns two invisible shadow Cooldown frames per icon:
--
-- _arcCDMShadowCooldown (main CD):
--   Fed with GetSpellCooldownDuration. GCD filtered.
--   IsShown()=true  → ALL charges depleted / full cooldown active
--   IsShown()=false → ready or has charges available
--
-- _arcCDMChargeShadow (charge recharge):
--   SetCooldown(0,0) then SetCooldownFromDurationObject(GetSpellChargeDuration).
--   Clear-first ensures proc resets and CDR clear immediately.
--   IsShown()=true  → recharge timer active
--   IsShown()=false → all charges full
--
-- EVENT-DRIVEN ARCHITECTURE (matches ArcAuras):
--   Per-icon event handler catches SPELL_UPDATE_COOLDOWN/CHARGES.
--   Feeds shadows, then calls ApplyCooldownStateVisuals ONCE.
--   OnCooldownDone on each shadow catches natural timer expiry.
--   NO hooks on SetCooldown/SetCooldownFromDurationObject —
--   we call those ourselves, so hooking them was reacting to our
--   own writes = 5-13x cascade per event. ArcAuras never does this.
--
-- ENFORCEMENT HOOKS (on CDM parent frame):
--   SetAlpha, SetDesaturated, SetVertexColor hooks BLOCK CDM's
--   native writes and enforce our values. These never re-feed
--   or re-dispatch — they just guard the values we already set.
-- ===================================================================

local ADDON, ns = ...

ns.CooldownState = ns.CooldownState or {}

-- ═══════════════════════════════════════════════════════════════════
-- SECRET-SAFE AURAINSTANCEID HELPER
-- ═══════════════════════════════════════════════════════════════════
local function HasAuraInstanceID(value)
  if ns.API and ns.API.HasAuraInstanceID then
    return ns.API.HasAuraInstanceID(value)
  end
  if value == nil then return false end
  if issecretvalue and issecretvalue(value) then return true end
  if type(value) == "number" and value == 0 then return false end
  return value ~= nil
end

-- ═══════════════════════════════════════════════════════════════════
-- DEPENDENCY REFERENCES (resolved lazily on first call)
-- ═══════════════════════════════════════════════════════════════════
local CDM
local InitCooldownCurves
local GetEffectiveStateVisuals
local GetEffectiveReadyAlpha
local GetGlowThresholdCurve
local ShowReadyGlow
local HideReadyGlow
local SetGlowAlpha
local ShouldShowReadyGlow
local ApplyBorderDesaturation
local HideAuraActiveGlow
local ShowAuraActiveGlow
local ShouldShowAuraActiveGlow
local EvaluateAuraActiveGlow

local resolved = false

local function ResolveDependencies()
  CDM = ns.CDMEnhance
  if not CDM then return false end

  InitCooldownCurves          = CDM.InitCooldownCurves
  GetEffectiveStateVisuals    = CDM.GetEffectiveStateVisuals
  GetEffectiveReadyAlpha      = CDM.GetEffectiveReadyAlpha
  GetGlowThresholdCurve       = CDM.GetGlowThresholdCurve
  ShowReadyGlow               = CDM.ShowReadyGlow
  HideReadyGlow               = CDM.HideReadyGlow       or function() end
  SetGlowAlpha                = CDM.SetGlowAlpha
  ShouldShowReadyGlow         = CDM.ShouldShowReadyGlow
  ApplyBorderDesaturation     = CDM.ApplyBorderDesaturation
  HideAuraActiveGlow          = CDM.HideAuraActiveGlow       or function() end
  ShowAuraActiveGlow          = CDM.ShowAuraActiveGlow       or function() end
  ShouldShowAuraActiveGlow    = CDM.ShouldShowAuraActiveGlow or function() return false end

  resolved = true
  return true
end

-- ═══════════════════════════════════════════════════════════════════
-- SMALL HELPERS
-- ═══════════════════════════════════════════════════════════════════

local function ResolveCurrentSpellID(frame, cfg)
  if frame.cooldownInfo then
    local live = frame.cooldownInfo.overrideSpellID or frame.cooldownInfo.spellID
    if live then return live end
  end
  return cfg._spellID
end

local function ResolveIconTexture(frame)
  local iconTex = frame.Icon or frame.icon
  if not iconTex then return nil end
  if not iconTex.SetDesaturated and iconTex.Icon then
    iconTex = iconTex.Icon
  end
  return iconTex
end

local function SetDesat(iconTex, value)
  if not iconTex then return end
  if iconTex.SetDesaturation then
    iconTex:SetDesaturation(value or 0)
  end
end

local function SetVertexColorSafe(frame, iconTex, r, g, b, a)
  if not iconTex then return end
  frame._arcDesiredVertexColor = { r = r, g = g, b = b }
  frame._arcBypassVertexHook = true
  iconTex:SetVertexColor(r, g, b, a or 1)
  frame._arcBypassVertexHook = false
end

local function ResetDurationText(frame)
  local skip = frame._arcSwipeWaitForNoCharges
  if frame._arcCooldownText and frame._arcCooldownText.SetIgnoreParentAlpha then
    if not skip then frame._arcCooldownText:SetIgnoreParentAlpha(false) end
  end
  if frame._arcChargeText and frame._arcChargeText.SetIgnoreParentAlpha then
    if not skip then frame._arcChargeText:SetIgnoreParentAlpha(false) end
  end
  -- Restore chargeFrame container
  if not skip then
    local chargeFrame = frame.ChargeCount or frame.Applications
    if chargeFrame and chargeFrame.SetIgnoreParentAlpha then
      chargeFrame:SetIgnoreParentAlpha(false)
    end
  end
  if frame.Cooldown and frame.Cooldown.Text and frame.Cooldown.Text.SetIgnoreParentAlpha then
    if not skip then frame.Cooldown.Text:SetIgnoreParentAlpha(false) end
  end
  if frame.Cooldown and frame.Cooldown.SetIgnoreParentAlpha then
    frame.Cooldown:SetIgnoreParentAlpha(false)
  end
  -- Walk native Cooldown regions
  if frame.Cooldown and not skip then
    local countdownFS = frame.Cooldown.GetCountdownFontString and frame.Cooldown:GetCountdownFontString()
    if countdownFS and countdownFS.SetIgnoreParentAlpha then
      countdownFS:SetIgnoreParentAlpha(false)
    end
    for _, region in ipairs({frame.Cooldown:GetRegions()}) do
      if region:IsObjectType("FontString") and region.SetIgnoreParentAlpha
         and not region._arcIsChargeText then
        region:SetIgnoreParentAlpha(false)
      end
    end
  end
end

local function PreserveDurationText(frame)
  -- Don't enable IgnoreParentAlpha if the group container is hidden
  -- Check both frame and parent: icons added after SafeShowContainer don't have the flag
  if frame._arcGroupHidden then return end
  local parent = frame:GetParent()
  if parent and parent._arcGroupHidden then return end
  
  -- Skip cooldown text if charge-conditional hide is active
  if not frame._arcHideCDTextForCharges then
    if frame._arcCooldownText and frame._arcCooldownText.SetIgnoreParentAlpha then
      frame._arcCooldownText:SetIgnoreParentAlpha(true)
      frame._arcCooldownText:SetAlpha(1)
    end
    if frame.Cooldown and frame.Cooldown.Text and frame.Cooldown.Text.SetIgnoreParentAlpha then
      frame.Cooldown.Text:SetIgnoreParentAlpha(true)
      frame.Cooldown.Text:SetAlpha(1)
    end
  end
  -- Skip charge text if hideAtZero is active
  if not frame._arcHideChargeAtZero then
    if frame._arcChargeText and frame._arcChargeText.SetIgnoreParentAlpha then
      frame._arcChargeText:SetIgnoreParentAlpha(true)
      frame._arcChargeText:SetAlpha(1)
    end
    -- Also protect the chargeFrame container (ChargeCount/Applications).
    -- SetIgnoreParentAlpha on the FontString only ignores inherited alpha —
    -- CDM calls chargeFrame:SetAlpha(0) directly which still affects the text.
    -- SetIgnoreParentAlpha on the container makes it ignore the icon frame's alpha.
    local chargeFrame = frame.ChargeCount or frame.Applications
    if chargeFrame and chargeFrame.SetIgnoreParentAlpha then
      chargeFrame:SetIgnoreParentAlpha(true)
      chargeFrame:SetAlpha(1)
    end
  end
  -- Native Cooldown FontStrings: The Cooldown widget can recreate/reset
  -- its internal text when CDM pushes new DurationObjects. Walk regions
  -- every call to catch any new or reset FontStrings.
  if frame.Cooldown then
    local countdownFS = frame.Cooldown.GetCountdownFontString and frame.Cooldown:GetCountdownFontString()
    if countdownFS and countdownFS.SetIgnoreParentAlpha then
      countdownFS:SetIgnoreParentAlpha(true)
      countdownFS:SetAlpha(1)
    end
    for _, region in ipairs({frame.Cooldown:GetRegions()}) do
      if region:IsObjectType("FontString") and region.SetIgnoreParentAlpha
         and not region._arcIsChargeText then
        region:SetIgnoreParentAlpha(true)
        region:SetAlpha(1)
      end
    end
  end
end

-- ═══════════════════════════════════════════════════════════════════
-- CHARGE-CONDITIONAL TEXT VISIBILITY
--
-- Uses shadow state (non-secret) to conditionally show/hide text:
--   chargeText.hideAtZero: hide charge count when charges = 0
--   cooldownText.hideWhenHasCharges: hide CD text when charges > 0
-- ═══════════════════════════════════════════════════════════════════
local function ApplyChargeConditionalText(frame, cfg, isChargeSpell, isRecharging, isOnCooldown)
  if not isChargeSpell then
    -- Not a charge spell — clear any override flags
    frame._arcHideChargeAtZero = nil
    frame._arcHideCDTextForCharges = nil
    return
  end

  -- Derive charge state from shadows (non-secret):
  --   isRecharging = charges > 0 (charge shadow shown)
  --   isOnCooldown && !isRecharging = charges = 0 (all spent)
  --   !isOnCooldown && !isRecharging = all charges ready
  -- With both shadows read independently (matches shadow tester):
  -- DEPLETED   = isOnCooldown and isRecharging     (0 charges, one recharging)
  -- RECHARGING = not isOnCooldown and isRecharging (1+ charges, one recharging)
  -- FULL       = not isOnCooldown and not isRecharging
  -- DEPLETED   (isOnCooldown=true,  isRecharging=true):  0 charges
  -- RECHARGING (isOnCooldown=false, isRecharging=true):  1+ charges, recharging
  -- FULL       (isOnCooldown=false, isRecharging=false): all charges ready
  local chargesSpent = isOnCooldown and isRecharging   -- DEPLETED only: 0 charges
  local hasCharges   = not isOnCooldown                -- RECHARGING + FULL: 1+ charges

  -- ── CHARGE TEXT: hideAtZero ──
  local chargeCfg = cfg.chargeText
  local wantHideAtZero = chargeCfg and chargeCfg.hideAtZero and chargeCfg.enabled ~= false
  if wantHideAtZero and chargesSpent then
    frame._arcHideChargeAtZero = true
    if frame._arcChargeText then
      -- SetIgnoreParentAlpha: decouple from chargeFrame container so CDM
      -- showing/alpha-ing the container can't drag the fontstring back visible.
      if frame._arcChargeText.SetIgnoreParentAlpha then
        frame._arcChargeText:SetIgnoreParentAlpha(true)
      end
      frame._arcChargeText:SetAlpha(0)
    end
  else
    frame._arcHideChargeAtZero = nil
    -- Restore charge text unconditionally — RECHARGING means 1+ charges available,
    -- text must show regardless of frame alpha (cdAlpha dim does not mean text hidden).
    -- SetIgnoreParentAlpha(false) lets CDM's container alpha manage it naturally.
    if chargeCfg and chargeCfg.enabled ~= false and frame._arcChargeText then
      if frame._arcChargeText.SetIgnoreParentAlpha then
        frame._arcChargeText:SetIgnoreParentAlpha(false)
      end
      frame._arcChargeText:SetAlpha(1)
    end
  end

  -- ── COOLDOWN TEXT: hideWhenHasCharges ──
  local cdTextCfg = cfg.cooldownText
  local wantHideCDWithCharges = cdTextCfg and cdTextCfg.hideWhenHasCharges and cdTextCfg.enabled ~= false
  if wantHideCDWithCharges and hasCharges then
    frame._arcHideCDTextForCharges = true
    -- Use SetHideCountdownNumbers to properly suppress the Cooldown widget's
    -- built-in countdown — SetAlpha alone gets overwritten by CDM updates.
    if frame.Cooldown then
      frame.Cooldown:SetHideCountdownNumbers(true)
    end
    if frame._arcCooldownText then
      frame._arcCooldownText:SetAlpha(0)
    end
  else
    local wasHidden = frame._arcHideCDTextForCharges
    frame._arcHideCDTextForCharges = nil
    -- Only restore if cooldown text is enabled and was previously hidden by us
    if wasHidden and cdTextCfg and cdTextCfg.enabled ~= false then
      if frame.Cooldown then
        frame.Cooldown:SetHideCountdownNumbers(false)
      end
      if (frame._lastAppliedAlpha or 1) > 0.01 then
        if frame._arcCooldownText then
          frame._arcCooldownText:SetAlpha(1)
        end
      end
    end
  end
end

-- ═══════════════════════════════════════════════════════════════════
-- DUAL SHADOW COOLDOWN FRAMES — Creation + Feeding + CDM Write Hook
--
-- Shadow frames are our independent cooldown detection system.
-- CDM never sees them. We feed them, we read them.
--
-- Hooks:
--   1. OnCooldownDone on each shadow — natural timer expiry
--   2. SetCooldownFromDurationObject on CDM's VISIBLE Cooldown —
--      CDM writes to its cooldown → we react by feeding our shadows
--      and applying visuals. Independent of CDM's event dispatch.
--
-- NO hooks on shadow SetCooldown / SetCooldownFromDurationObject —
-- we call those during feeding. Hooking them = cascade.
-- ═══════════════════════════════════════════════════════════════════

local function CreateInvisibleCooldown(frame)
  local cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
  cd:SetAllPoints(frame)
  cd:SetDrawSwipe(false)
  cd:SetDrawEdge(false)
  cd:SetDrawBling(false)
  cd:SetHideCountdownNumbers(true)
  cd:SetAlpha(0)
  return cd
end

local FeedShadowCooldown
local EnforceCooldownReadyGlow

-- Shared dispatch: apply visuals + glow + label after shadow state changes.
-- Called from OnCooldownDone hooks AND CDM Cooldown write hook.
local function DispatchAfterShadowUpdate(frame)
  local cachedCfg = frame._arcCfg
  if not cachedCfg then return end
  -- Update CDMEnhance cache flags BEFORE calling ApplyCooldownStateVisuals.
  -- Without this, CDMEnhance's ticker sees stale _arcLastShadowShown/_arcLastChargeShown
  -- and skips the next visual update (state-change detection false-negative).
  local shadowCD    = frame._arcCDMShadowCooldown
  local chargeShadow = frame._arcCDMChargeShadow
  frame._arcLastShadowShown = shadowCD    and shadowCD:IsShown()    or false
  frame._arcLastChargeShown = chargeShadow and chargeShadow:IsShown() or false
  ns.CDMEnhance.ApplyCooldownStateVisuals(frame, cachedCfg)
  if ns.CDMSpellUsability and ns.CDMSpellUsability.UpdateGlow then
    ns.CDMSpellUsability.UpdateGlow(frame, cachedCfg)
  end
  if frame._arcCLHasText and ns.CustomLabel and ns.CustomLabel.UpdateVisibility then
    ns.CustomLabel.UpdateVisibility(frame)
  end
end

local function EnsureShadowCooldown(frame)
  if not frame._arcCDMShadowCooldown then
    frame._arcCDMShadowCooldown = CreateInvisibleCooldown(frame)
    -- Initialize as idle so GlobalCooldownSweep auto-stop works on first pass.
    -- nil means "never evaluated" which the sweep treats as active (keeps ticker running).
    frame._arcLastShadowShown  = false
    frame._arcLastChargeShown  = false
    frame._arcLastIsOnGCD      = false

    -- OnShow/OnHide: skip during feed — _arcFeedingShadow guard prevents cascade.
    -- GCD gate on OnShow only: shadow cleared by GCD, not a real state change.
    -- OnHide: NO GCD gate — natural expiry (DEPLETED→RECHARGING) fires OnHide at
    -- same instant as SPELL_UPDATE_CD [nil] which sets isOnGCD=true. Gating blocks it.
    -- OnCooldownDone: always dispatch, deferred 0.1s (IsShown() not updated yet at fire time).
    local _Track = _G.ArcUIProfiler_Track
    local function shadowOnShow()
      if frame._arcFeedingShadow and frame._arcFeedingShadow > 0 then return end
      if frame._arcLastIsOnGCD then return end
      DispatchAfterShadowUpdate(frame)
    end
    local function shadowOnHide()
      if frame._arcFeedingShadow and frame._arcFeedingShadow > 0 then return end
      DispatchAfterShadowUpdate(frame)
    end
    local function shadowOnDone()
      C_Timer.After(0.1, function() DispatchAfterShadowUpdate(frame) end)
    end
    frame._arcCDMShadowCooldown:HookScript("OnShow",        _Track and _Track("CooldownState.ShadowOnShow",        shadowOnShow)        or shadowOnShow)
    frame._arcCDMShadowCooldown:HookScript("OnHide",        _Track and _Track("CooldownState.ShadowOnHide",        shadowOnHide)        or shadowOnHide)
    frame._arcCDMShadowCooldown:HookScript("OnCooldownDone",_Track and _Track("CooldownState.ShadowOnCooldownDone",shadowOnDone)        or shadowOnDone)

    -- Hook CDM's visible Cooldown:Clear — fires at exact CD expiry moment, very low frequency.
    -- From the log: Cooldown:Clear fires ~16x vs 693 SPELL_UPDATE_COOLDOWN events.
    -- When CDM clears its frame the real CD is done — clear our shadow immediately
    -- and dispatch. This gives us the same timing as CDM without any polling or
    -- event spam. Guard with _arcFeedingShadow to avoid cascade from our own feeds.
    if frame.Cooldown and not frame.Cooldown._arcCDSyncHooked then
      frame.Cooldown._arcCDSyncHooked = true
      -- When CDM feeds its visible cooldown, feed our shadow at the exact same moment.
      -- Both get GetSpellCooldownDuration at the same time = same DurObj = same expiry.
      -- No args needed — FeedShadow queries the API itself.
      hooksecurefunc(frame.Cooldown, "SetCooldownFromDurationObject", function(self)
        if frame._arcFeedingShadow and frame._arcFeedingShadow > 0 then return end
        local cfg = frame._arcCfg
        if not cfg then return end
        local spellID = frame._arcCachedSpellID
                     or (frame.cooldownInfo and (frame.cooldownInfo.overrideSpellID or frame.cooldownInfo.spellID))
        if not spellID then return end
        ns.CooldownState.FeedShadow(frame, cfg)
        DispatchAfterShadowUpdate(frame)
      end)
    end
    -- Installed here so it lives entirely within CooldownState alongside
    -- the shadow frames it feeds. Each frame gets one event frame.
    -- SPELL_UPDATE_COOLDOWN: feed on exact spellID match, base match, or
    --   nil (global = GCD expiry / server sync).
    -- UNIT_SPELLCAST_SUCCEEDED: feed on spellID match — catches the cast
    --   moment before SPELL_UPDATE_COOLDOWN fires.
    -- GCD filter: frame.isOnGCD==true means only GCD swipe is active — skip.
    -- Shadow OnCooldownDone above handles expiry — no polling needed.
    -- ═══════════════════════════════════════════════════════════════════
    local ef = CreateFrame("Frame")
    frame._arcPerFrameEvFrame = ef
    ef:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    ef:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    local _TrackEv = _G.ArcUIProfiler_Track
    local function perFrameEventHandler(_, ev, a1, a2, a3)
      if not frame._arcEnhanced then
        ef:UnregisterAllEvents()
        frame._arcPerFrameEvFrame = nil
        return
      end
      -- Build the full set of spellIDs this frame can respond to:
      --   _arcCachedSpellID   — set at enhancement time and updated by override handler
      --   overrideSpellID     — live from CDM (changes during override windows)
      --   spellID (base)      — always the base spell
      -- Matching any of these means an event for this frame should trigger a feed.
      -- This covers short-lived override spells whose SPELL_UPDATE_COOLDOWN fires
      -- before _arcCachedSpellID has been updated by the override event handler.
      local ci = frame.cooldownInfo
      local baseSpell     = ci and ci.spellID
      local overrideSpell = ci and ci.overrideSpellID
      local cachedSpell   = frame._arcCachedSpellID
      -- Primary spellID for FeedShadow (prefer live override, then cached, then base)
      local spellID = overrideSpell or cachedSpell or baseSpell
      if not spellID then return end

      if ev == "SPELL_UPDATE_COOLDOWN" then
        local matches = (a1 == nil)
                     or (a1 == cachedSpell)
                     or (a1 == overrideSpell)
                     or (a1 == baseSpell)
                     or (a2 == cachedSpell)
                     or (a2 == overrideSpell)
                     or (a2 == baseSpell)
        -- Expiry is now handled by the Cooldown:SetCooldown(0,0) hook above —
        -- fires at exact CDM clear time with very low frequency (~16x vs 693 events).
        -- Revert to strict spellID filter here: no throttle needed, no CPU waste.
        if not matches then return end
      elseif ev == "UNIT_SPELLCAST_SUCCEEDED" then
        if a3 ~= cachedSpell and a3 ~= overrideSpell and a3 ~= baseSpell then return end
      end

      local cfg = frame._arcCfg
      if cfg then
        ns.CooldownState.FeedShadow(frame, cfg)
        DispatchAfterShadowUpdate(frame)
      end
    end
    ef:SetScript("OnEvent", _TrackEv and _TrackEv("CooldownState.PerFrameEvent", perFrameEventHandler) or perFrameEventHandler)
  end

  -- Only create charge shadow for charge spells (saves frame creation + feed cost)
  if frame._arcIsChargeSpellCached and not frame._arcCDMChargeShadow then
    frame._arcCDMChargeShadow = CreateInvisibleCooldown(frame)

    -- Same pattern as main shadow: skip during feed to avoid clear-first cascade.
    -- No GCD gate — charge state changes are always real.
    local _Track2 = _G.ArcUIProfiler_Track
    local function chargeOnShow()
      if frame._arcFeedingShadow and frame._arcFeedingShadow > 0 then return end
      DispatchAfterShadowUpdate(frame)
    end
    local function chargeOnHide()
      if frame._arcFeedingShadow and frame._arcFeedingShadow > 0 then return end
      DispatchAfterShadowUpdate(frame)
    end
    local function chargeOnDone()
      C_Timer.After(0.1, function() DispatchAfterShadowUpdate(frame) end)
    end
    frame._arcCDMChargeShadow:HookScript("OnShow",        _Track2 and _Track2("CooldownState.ChargeOnShow",        chargeOnShow) or chargeOnShow)
    frame._arcCDMChargeShadow:HookScript("OnHide",        _Track2 and _Track2("CooldownState.ChargeOnHide",        chargeOnHide) or chargeOnHide)
    frame._arcCDMChargeShadow:HookScript("OnCooldownDone",_Track2 and _Track2("CooldownState.ChargeOnCooldownDone",chargeOnDone) or chargeOnDone)

    -- SPELL_UPDATE_CHARGES removed — simple 2-event approach (SPELL_UPDATE_COOLDOWN
    -- + UNIT_SPELLCAST_SUCCEEDED) with SetCooldown(0,0) before DurationObject feed
    -- handles all cases including proc CDR and charge resets cleanly.
  end

  return frame._arcCDMShadowCooldown, frame._arcCDMChargeShadow
end

-- Feed shadow frames. Matches standalone shadow tester: no Clear(), no guards.
-- Charge shadow only fed if it exists (charge spells only).
FeedShadowCooldown = function(frame, spellID)
  if not spellID then return end
  if frame._arcFeedingShadow and frame._arcFeedingShadow > 0 then return end
  frame._arcFeedingShadow = (frame._arcFeedingShadow or 0) + 1

  -- SPELL CHANGE DETECTION: When CDM reassigns a frame to a different spell
  -- (via layout manager / Pools recycle), the shadow still has the OLD spell's
  -- cooldown timer. Invalidate cache so state-change detection doesn't skip
  -- visuals, and kill any stale ready glow from the previous spell immediately.
  local prevSpellID = frame._arcShadowFedSpellID
  if prevSpellID and prevSpellID ~= spellID then
    frame._arcLastShadowShown = false
    frame._arcLastChargeShown = false
    if frame._arcReadyGlowActive and ns.CDMEnhance and ns.CDMEnhance.HideReadyGlow then
      ns.CDMEnhance.HideReadyGlow(frame)
    end
  end
  frame._arcShadowFedSpellID = spellID

  local isOnGCD = nil
  local isChargeSpell = false
  pcall(function()
    local cdInfo = C_Spell.GetSpellCooldown(spellID)
    if cdInfo and cdInfo.isOnGCD == true then isOnGCD = true end
  end)
  pcall(function() isChargeSpell = C_Spell.GetSpellCharges(spellID) ~= nil end)
  -- Fallback: some spells (e.g. override spellIDs) return nil from GetSpellCharges
  -- even though CDM tracks them as charge spells. Trust CDM's own flag.
  if not isChargeSpell and frame.cooldownInfo and frame.cooldownInfo.charges == true then
    isChargeSpell = true
  end

  -- Cache BEFORE EnsureShadowCooldown — charge shadow is only created when
  -- _arcIsChargeSpellCached is true, so it must be set before EnsureShadow runs.
  -- Previously set after — charge shadow was never created on the first feed.
  frame._arcLastIsOnGCD         = (isOnGCD == true)
  frame._arcIsChargeSpellCached = isChargeSpell

  local shadowCD, chargeShadow = EnsureShadowCooldown(frame)

  if isOnGCD then
    shadowCD:SetCooldown(0, 0)
  else
    -- Snapshot (matches standalone tester): SetCooldown takes values at call time.
    -- GetSpellCooldownDuration DurationObject was causing GCD contamination —
    -- the live binding could reflect GCD timing after feed. Snapshot is immune.
    local info = nil
    pcall(function() info = C_Spell.GetSpellCooldown(spellID) end)
    if info and info.startTime and info.duration then
      shadowCD:SetCooldown(info.startTime, info.duration)
    else
      shadowCD:SetCooldown(0, 0)
    end
  end

  if chargeShadow then
    -- Always clear first — SetCooldownFromDurationObject won't clear a running frame.
    -- SetCooldown(0,0) resets to idle so the engine can then correctly show or hide
    -- based on the new durObj. If durObj has remaining time it shows; if zero, stays hidden.
    chargeShadow:SetCooldown(0, 0)
    pcall(function()
      local durObj = C_Spell.GetSpellChargeDuration(spellID)
      if durObj then
        chargeShadow:SetCooldownFromDurationObject(durObj, true)
      end
    end)
  end

  frame._arcFeedingShadow = frame._arcFeedingShadow - 1
end

-- ═══════════════════════════════════════════════════════════════════
-- BINARY STATE DETECTION via dual shadow cooldown frames
-- ═══════════════════════════════════════════════════════════════════
local function GetBinaryCooldownState(frame)
  -- Read both shadows independently — never gate one on the other.
  -- DEPLETED:   mainShown=true,  chargeShown=true  (0 charges, recharging)
  -- RECHARGING: mainShown=false, chargeShown=true  (1+ charges, recharging)
  -- ON_CD:      mainShown=true,  chargeShown=false (non-charge spell on cooldown)
  -- FULL/READY: mainShown=false, chargeShown=false
  local shadowCD    = frame._arcCDMShadowCooldown
  local chargeShadow = frame._arcCDMChargeShadow
  local isOnCooldown = shadowCD    and shadowCD:IsShown()    or false
  local isRecharging = chargeShadow and chargeShadow:IsShown() or false
  return isOnCooldown, isRecharging
end

-- ReadCooldownState: reads only cached values — no live API calls.
-- isOnGCD:       written by FeedShadowCooldown (runs first every dispatch cycle).
-- isChargeSpell: written by FeedShadowCooldown (updated every feed, so linked-spell
--                frames that swap spells always reflect the current spell's charge type).
-- GetBinaryCooldownState: reads shadow IsShown() — always non-secret, zero API cost.
local function ReadCooldownState(frame, spellID)
  local isOnGCD       = frame._arcLastIsOnGCD         or false
  local isChargeSpell = frame._arcIsChargeSpellCached or false
  local isOnCooldown, isRecharging = GetBinaryCooldownState(frame)
  return isOnCooldown, isRecharging, isChargeSpell, isOnGCD
end

-- ═══════════════════════════════════════════════════════════════════
-- USABILITY HELPERS
-- ═══════════════════════════════════════════════════════════════════
local function GetUsabilityAlpha(frame, spellID, cfg)
  if not spellID then return nil, false end
  local su = cfg and cfg.spellUsability
  if not su or not su.enabled then return nil, false end
  -- Proc override: if a proc glow is active and the setting is enabled, skip usability dimming
  if frame._arcProcGlowActive and su.procOverride then return nil, false end
  if frame.spellOutOfRange then
    local ri = cfg and cfg.rangeIndicator
    local rangeEnabled = not ri or ri.enabled ~= false
    if rangeEnabled then return nil, false end
  end
  local isUsable, notEnoughMana = C_Spell.IsSpellUsable(spellID)
  if isUsable then return nil, false end
  if notEnoughMana then
    return su.notEnoughResourceAlpha, su.notEnoughResourcePreserveDurationText == true
  else
    return su.notUsableAlpha, su.notUsablePreserveDurationText == true
  end
end



-- ═══════════════════════════════════════════════════════════════════
-- OPTIONS PANEL PREVIEW HELPER
-- ═══════════════════════════════════════════════════════════════════
local function PreviewClampAlpha(alpha)
  if alpha <= 0 then
    if ns.CDMEnhance.IsOptionsPanelOpen and ns.CDMEnhance.IsOptionsPanelOpen() then
      return 0.35
    end
  end
  return alpha
end

-- ═══════════════════════════════════════════════════════════════════
-- APPLY READY STATE
-- ═══════════════════════════════════════════════════════════════════
local function ApplyReadyState(frame, iconTex, stateVisuals, usabilityAlphaOverride, usabilityPreserveText)
  local effectiveReadyAlpha = GetEffectiveReadyAlpha(stateVisuals)
  if usabilityAlphaOverride then
    effectiveReadyAlpha = usabilityAlphaOverride
  end
  -- Proc override: if a proc glow is active and the setting is enabled, show at full alpha
  if frame._arcProcGlowActive and stateVisuals and stateVisuals.readyProcOverride then
    effectiveReadyAlpha = 1.0
  end
  effectiveReadyAlpha = PreviewClampAlpha(effectiveReadyAlpha)
  frame._arcTargetAlpha = nil
  if effectiveReadyAlpha < 1.0 then
    frame._arcEnforceReadyAlpha = true
    frame._arcReadyAlphaValue = effectiveReadyAlpha
  else
    frame._arcEnforceReadyAlpha = false
    frame._arcReadyAlphaValue = nil
  end
  if frame._lastAppliedAlpha ~= effectiveReadyAlpha then
    frame._arcBypassFrameAlphaHook = true
    frame:SetAlpha(effectiveReadyAlpha)
    frame._arcBypassFrameAlphaHook = false
    frame._lastAppliedAlpha = effectiveReadyAlpha
  end
  frame._arcDesatBranch = frame._arcDesatBranch or "READY"
  frame._arcForceDesatValue = nil
  ApplyBorderDesaturation(frame, 0)
  frame:Show()
  -- When a usability state (not enough resource / not usable) requests preserve
  -- duration text, honour it the same way cooldown state does: keep countdown
  -- and charge text visible at full alpha even though the icon is dimmed/hidden.
  if usabilityPreserveText and usabilityAlphaOverride and usabilityAlphaOverride < 1.0 then
    frame._arcPreserveDurationText = true
    if frame.Cooldown then
      frame.Cooldown:SetAlpha(1)
    end
    PreserveDurationText(frame)
  else
    frame._arcPreserveDurationText = false
    ResetDurationText(frame)
  end
end

-- ═══════════════════════════════════════════════════════════════════
-- APPLY COOLDOWN STATE ALPHA
-- ═══════════════════════════════════════════════════════════════════
local function ApplyCooldownAlpha(frame, stateVisuals)
  local cdAlpha = stateVisuals.cooldownAlpha or 1.0
  -- Proc override: if a proc glow is active and the setting is enabled, show at full alpha
  if frame._arcProcGlowActive and stateVisuals.cooldownProcOverride then
    cdAlpha = 1.0
  end
  cdAlpha = PreviewClampAlpha(cdAlpha)
  frame._arcEnforceReadyAlpha = false
  frame._arcReadyAlphaValue = nil
  frame._arcTargetAlpha = cdAlpha
  if frame._lastAppliedAlpha ~= cdAlpha then
    frame._arcBypassFrameAlphaHook = true
    frame:SetAlpha(cdAlpha)
    frame._arcBypassFrameAlphaHook = false
    frame._lastAppliedAlpha = cdAlpha
  end

  -- Preserve duration text: keep countdown + charge text visible even when
  -- frame is dimmed/hidden. This is the WHOLE POINT of the feature — text
  -- stays readable at full opacity while the icon fades to cooldownAlpha.
  -- Arc Auras applies preserve unconditionally regardless of alpha.
  frame._arcPreserveDurationText = stateVisuals.preserveDurationText == true
  if stateVisuals.preserveDurationText then
    -- Cooldown widget must be at alpha 1 so its child text can be visible.
    -- The frame itself is at cdAlpha (possibly 0), but IgnoreParentAlpha
    -- on the FontStrings makes them ignore the entire parent alpha chain.
    if frame.Cooldown then
      frame.Cooldown:SetAlpha(1)
    end
    PreserveDurationText(frame)
  else
    if frame.Cooldown then
      if frame.Cooldown.SetIgnoreParentAlpha then
        frame.Cooldown:SetIgnoreParentAlpha(false)
      end
    end
    ResetDurationText(frame)
  end
end

-- ═══════════════════════════════════════════════════════════════════
-- APPLY COOLDOWN DESATURATION
-- ═══════════════════════════════════════════════════════════════════
local function ApplyCooldownDesat(frame, iconTex, stateVisuals, hasActiveAuraDisplay, isRecharging)
  if hasActiveAuraDisplay then
    frame._arcForceDesatValue = 0
    frame._arcBypassDesatHook = true
    SetDesat(iconTex, 0)
    frame._arcBypassDesatHook = false
    ApplyBorderDesaturation(frame, 0)
  elseif stateVisuals.noDesaturate then
    frame._arcForceDesatValue = 0
    frame._arcBypassDesatHook = true
    SetDesat(iconTex, 0)
    frame._arcBypassDesatHook = false
    ApplyBorderDesaturation(frame, 0)
  else
    frame._arcForceDesatValue = nil
    local shadowCD = frame._arcCDMShadowCooldown
    local borderDesat = (shadowCD and shadowCD:IsShown()) and 1 or 0
    ApplyBorderDesaturation(frame, borderDesat)
  end
end

local function ApplyReadyGlow(frame, stateVisuals)
  if ShouldShowReadyGlow(stateVisuals, frame) then
    ShowReadyGlow(frame, stateVisuals)
  else
    HideReadyGlow(frame)
  end
end

-- ═══════════════════════════════════════════════════════════════════
-- SINGLE SOURCE OF TRUTH: Swipe/Edge decision + apply
--
-- All paths (IAO, CooldownLogic, and the OnCooldownEvent enforcer)
-- call this one function. No decision logic lives anywhere else.
--
-- ownWhenReady = true  → IAO frames: suppress swipe at ready/GCD-show
--                        (prevents aura-duration swipe bleeding through)
-- ownWhenReady = false → Normal CD frames: release to CDM when ready
-- ═══════════════════════════════════════════════════════════════════
local function DecideAndApplySwipeEdge(frame, cfg, isOnCooldown, isRecharging, isChargeSpell, isOnGCD, ownWhenReady)
  if not frame.Cooldown then return end
  local swipeCfg       = cfg.cooldownSwipe
  local userWantsSwipe = not swipeCfg or swipeCfg.showSwipe ~= false
  local userWantsEdge  = not swipeCfg or swipeCfg.showEdge  ~= false
  local noGCDSwipe     = swipeCfg and swipeCfg.noGCDSwipe
  local wantSwipe, wantEdge

  if isChargeSpell then
    local swipeWait    = swipeCfg and swipeCfg.swipeWaitForNoCharges
    local edgeWait     = swipeCfg and swipeCfg.edgeWaitForNoCharges
    local hasWaitFlags = swipeWait or edgeWait
    if isOnCooldown then
      wantSwipe = userWantsSwipe; wantEdge = userWantsEdge
    elseif isRecharging then
      wantSwipe = not swipeWait and userWantsSwipe
      wantEdge  = not edgeWait  and userWantsEdge
    elseif isOnGCD then
      if noGCDSwipe then
        wantSwipe = false; wantEdge = false       -- hide GCD swipe
      else
        wantSwipe = nil; wantEdge = nil           -- release to CDM for GCD swipe
      end
    elseif noGCDSwipe or hasWaitFlags or ownWhenReady then
      wantSwipe = false; wantEdge = false
    else
      wantSwipe = nil; wantEdge = nil
    end
  else
    if isOnCooldown then
      wantSwipe = userWantsSwipe; wantEdge = userWantsEdge
    elseif isOnGCD then
      if noGCDSwipe then
        wantSwipe = false; wantEdge = false       -- hide GCD swipe
      else
        wantSwipe = nil; wantEdge = nil           -- release to CDM for GCD swipe
      end
    elseif ownWhenReady then
      wantSwipe = false; wantEdge = false
    else
      wantSwipe = nil; wantEdge = nil
    end
  end

  frame._arcDesiredSwipe = wantSwipe
  frame._arcDesiredEdge  = wantEdge
  if wantSwipe ~= nil then
    frame._arcBypassSwipeHook = true
    frame.Cooldown:SetDrawSwipe(wantSwipe)
    frame.Cooldown:SetDrawEdge(wantEdge)
    frame._arcBypassSwipeHook = false
  end
end


-- ═══════════════════════════════════════════════════════════════════
-- PATH A: Ignore Aura Override (binary)
-- ═══════════════════════════════════════════════════════════════════
local function HandleIgnoreAuraOverride(frame, iconTex, cfg, stateVisuals)
  local spellID = ResolveCurrentSpellID(frame, cfg)
  if not spellID then
    frame._arcReadyForGlow = false
    frame._arcForceDesatValue = nil
    frame._arcEnforceReadyAlpha = false
    frame._arcReadyAlphaValue = nil
    frame._arcTargetAlpha = nil
    frame._arcDesiredSwipe = nil
    frame._arcDesiredEdge = nil
    frame._arcDesiredVertexColor = nil
    HideReadyGlow(frame)
    return
  end

  local isOnCooldown, isRecharging, isChargeSpell, isOnGCD = ReadCooldownState(frame, spellID)

  local waitForNoCharges = isChargeSpell and stateVisuals.waitForNoCharges
  local glowWhileCharges = stateVisuals.glowWhileChargesAvailable

  -- Match HandleCooldownLogic exactly — isOnGCD is not a cooldown state.
  local useCooldownVisuals
  if isOnCooldown then useCooldownVisuals = true
  elseif isChargeSpell and isRecharging then useCooldownVisuals = not waitForNoCharges
  else useCooldownVisuals = false end

  local isGlowEligible
  if isOnCooldown then isGlowEligible = false
  elseif isChargeSpell and isRecharging and not glowWhileCharges then isGlowEligible = false
  else isGlowEligible = true end

  -- Aura presence via CDM's native auraInstanceID — non-secret, always current.
  -- Only fight CDM desat when aura is actually showing on this frame.
  local isAuraActive = HasAuraInstanceID(frame.auraInstanceID) or (frame.totemData ~= nil)

  frame:Show()

  if useCooldownVisuals then
    frame._arcDesatBranch = "IAO_BIN_CD"
    ApplyCooldownAlpha(frame, stateVisuals)
    if not isAuraActive then
      -- No aura — CDM runs normal cooldown, release desat to it
      frame._arcForceDesatValue = nil
    elseif stateVisuals.noDesaturate or (isRecharging and not isOnCooldown) then
      -- RECHARGING (has charges) or noDesaturate: force colored
      frame._arcForceDesatValue = 0
      frame._arcBypassDesatHook = true
      SetDesat(iconTex, 0)
      frame._arcBypassDesatHook = false
      ApplyBorderDesaturation(frame, 0)
    else
      -- ON_CD / DEPLETED with aura: force desaturated
      frame._arcForceDesatValue = 1
      frame._arcBypassDesatHook = true
      SetDesat(iconTex, 1)
      frame._arcBypassDesatHook = false
      ApplyBorderDesaturation(frame, 1)
    end
    if stateVisuals.cooldownTint and stateVisuals.cooldownTintColor then
      local col = stateVisuals.cooldownTintColor
      SetVertexColorSafe(frame, iconTex, col.r or 0.5, col.g or 0.5, col.b or 0.5)
    else
      frame._arcDesiredVertexColor = nil
    end
    if isGlowEligible then ApplyReadyGlow(frame, stateVisuals) else HideReadyGlow(frame) end
  else
    frame._arcDesatBranch = "IAO_BIN_READY"
    local usabilityAlpha, usabilityPreserveText = GetUsabilityAlpha(frame, spellID, cfg)
    ApplyReadyState(frame, iconTex, stateVisuals, usabilityAlpha, usabilityPreserveText)
    if isAuraActive then
      frame._arcForceDesatValue = 0
      frame._arcBypassDesatHook = true
      SetDesat(iconTex, 0)
      frame._arcBypassDesatHook = false
    else
      frame._arcForceDesatValue = nil
    end
    frame._arcDesiredVertexColor = nil
    if isGlowEligible then ApplyReadyGlow(frame, stateVisuals) else HideReadyGlow(frame) end
  end

  -- CHARGE-CONDITIONAL TEXT (hideAtZero / hideWhenHasCharges)
  ApplyChargeConditionalText(frame, cfg, isChargeSpell, isRecharging, isOnCooldown)

  -- SWIPE/EDGE — single source of truth
  DecideAndApplySwipeEdge(frame, cfg, isOnCooldown, isRecharging, isChargeSpell, isOnGCD, true)

  -- AURA ACTIVE GLOW
  EvaluateAuraActiveGlow(frame, cfg)
end


-- ═══════════════════════════════════════════════════════════════════
-- PATH B: Aura Logic (buffs / debuffs / totems)
-- ═══════════════════════════════════════════════════════════════════
local function HandleAuraLogic(frame, iconTex, cfg, stateVisuals)
  frame._arcTargetAlpha = nil
  frame._arcTargetDesat = nil
  frame._arcTargetTint = nil

  local isAuraActive = HasAuraInstanceID(frame.auraInstanceID) or (frame.totemData ~= nil)
  local isCooldownFrame = not cfg._isAura and frame.totemData == nil

  local cdSpellID, cdOnCooldown, cdRecharging, cdIsCharge, cdIsOnGCD
  if isCooldownFrame then
    cdSpellID = ResolveCurrentSpellID(frame, cfg)
    if cdSpellID then
      cdOnCooldown, cdRecharging, cdIsCharge, cdIsOnGCD = ReadCooldownState(frame, cdSpellID)
    end
  end

  -- ALPHA
  if frame._arcTargetAlpha == nil then
    if isCooldownFrame then
      if cdSpellID then
        local isOnGCD, isChargeSpell = cdIsOnGCD, cdIsCharge
        local isOnCooldown, isRecharging = cdOnCooldown, cdRecharging
        local waitForNoCharges = isChargeSpell and stateVisuals.waitForNoCharges
        local useCooldownVisuals
        if isOnCooldown then useCooldownVisuals = true
        elseif isChargeSpell and isRecharging then useCooldownVisuals = not waitForNoCharges
        else useCooldownVisuals = false end
        if not isChargeSpell and isOnGCD then
          local usabilityAlpha, usabilityPreserveText = GetUsabilityAlpha(frame, cdSpellID, cfg)
          ApplyReadyState(frame, iconTex, stateVisuals, usabilityAlpha, usabilityPreserveText)
        elseif useCooldownVisuals then
          frame:Show()
          ApplyCooldownAlpha(frame, stateVisuals)
        else
          local usabilityAlpha, usabilityPreserveText = GetUsabilityAlpha(frame, cdSpellID, cfg)
          ApplyReadyState(frame, iconTex, stateVisuals, usabilityAlpha, usabilityPreserveText)
        end
      else
        ApplyReadyState(frame, iconTex, stateVisuals)
      end
    else
      local targetAlpha
      if isAuraActive then
        local effectiveReadyAlpha = GetEffectiveReadyAlpha(stateVisuals)
        targetAlpha = effectiveReadyAlpha
        if effectiveReadyAlpha < 1.0 then
          frame._arcEnforceReadyAlpha = true
          frame._arcReadyAlphaValue = effectiveReadyAlpha
        else
          frame._arcEnforceReadyAlpha = false
        end
      else
        frame._arcEnforceReadyAlpha = false
        local cdAlpha = stateVisuals.cooldownAlpha
        targetAlpha = PreviewClampAlpha(cdAlpha)
      end
      frame._arcTargetAlpha = targetAlpha
      if frame._lastAppliedAlpha ~= targetAlpha then
        frame._arcBypassFrameAlphaHook = true
        frame:SetAlpha(targetAlpha)
        if frame.Cooldown then frame.Cooldown:SetAlpha(targetAlpha) end
        frame._arcBypassFrameAlphaHook = false
        frame._lastAppliedAlpha = targetAlpha
      end
      if not frame:IsShown() then frame:Show() end
    end
  end

  -- DESATURATION
  if frame._arcTargetDesat == nil then
    if isCooldownFrame then
      frame._arcDesatBranch = "AURA_CD_NATIVE"
      frame._arcForceDesatValue = nil
      frame._arcTargetDesat = -1
    else
      if isAuraActive then
        -- Aura active = ready state — no desat needed. CDM agrees so no fight.
        frame._arcDesatBranch = "AURA_READY"
        frame._arcForceDesatValue = nil
        frame._arcTargetDesat = 0
        ApplyBorderDesaturation(frame, 0)
      elseif stateVisuals.cooldownDesaturate then
        -- User explicitly wants desat on cooldown — force it.
        frame._arcDesatBranch = "AURA_CD"
        frame._arcForceDesatValue = 1
        frame._arcBypassDesatHook = true
        SetDesat(iconTex, 1)
        frame._arcBypassDesatHook = false
        frame._arcTargetDesat = 1
        ApplyBorderDesaturation(frame, 1)
      else
        -- No user desat option — release to CDM entirely.
        frame._arcDesatBranch = "AURA_CD_NATIVE"
        frame._arcForceDesatValue = nil
        frame._arcTargetDesat = -1
      end
    end
  end

  -- TINT
  if frame._arcTargetTint == nil then
    if isCooldownFrame then
      frame._arcDesiredVertexColor = nil
      frame._arcTargetTint = true
    else
      local tR, tG, tB = 1, 1, 1
      if not isAuraActive and stateVisuals.cooldownTint and stateVisuals.cooldownTintColor then
        local col = stateVisuals.cooldownTintColor
        tR, tG, tB = col.r or 0.5, col.g or 0.5, col.b or 0.5
      end
      frame._arcTargetTint = string.format("%.2f,%.2f,%.2f", tR, tG, tB)
      -- RAW write: do NOT use SetVertexColorSafe for aura frames.
      -- SetVertexColorSafe sets _arcDesiredVertexColor, which the hook enforces
      -- against ALL future writes — blocking CDM from clearing tint when aura activates.
      -- Old working version used raw SetVertexColor; match that behavior.
      frame._arcDesiredVertexColor = nil
      if iconTex then
        frame._arcBypassVertexHook = true
        iconTex:SetVertexColor(tR, tG, tB, 1)
        frame._arcBypassVertexHook = false
      end
    end
  end

  -- SWIPE/EDGE: cooldown frames need proper swipe control even inside HandleAuraLogic.
  -- Previously just nulled desired values and let CDM control swipe — but that breaks
  -- swipeWaitForNoCharges on charge spells that also track an aura (e.g. Shadow Dance,
  -- Feint, Hover). When the aura activates after consuming a charge, the frame routes
  -- here and CDM draws the full swipe, ignoring our waitForNoCharges setting.
  if isCooldownFrame then
    if cdSpellID then
      DecideAndApplySwipeEdge(frame, cfg, cdOnCooldown, cdRecharging, cdIsCharge, cdIsOnGCD, false)
    else
      frame._arcDesiredSwipe = nil
      frame._arcDesiredEdge = nil
    end
  end

  -- GLOW
  local auraID = frame.auraInstanceID
  if isCooldownFrame or frame._arcTargetGlow == nil or not isAuraActive then
    if isCooldownFrame then
      if cdSpellID then
        local glowOnCD, glowRecharging = cdOnCooldown, cdRecharging
        local glowWhileCharges = stateVisuals.glowWhileChargesAvailable
        local glowEligible = true
        if glowOnCD then glowEligible = false
        elseif cdIsCharge and glowRecharging and not glowWhileCharges then glowEligible = false end
        if glowEligible and ShouldShowReadyGlow(stateVisuals, frame) then
          ShowReadyGlow(frame, stateVisuals)
        else
          HideReadyGlow(frame)
        end
      else
        ApplyReadyGlow(frame, stateVisuals)
      end
    elseif ShouldShowReadyGlow(stateVisuals, frame) and isAuraActive then
      local threshold = stateVisuals.glowThreshold or 1.0
      if threshold < 1.0 and auraID then
        local auraType = stateVisuals.glowAuraType or "auto"
        local unit = "player"
        if auraType == "debuff" then unit = "target"
        elseif auraType == "auto" then
          local cat = frame.category
          if cat == 3 then unit = "target" end
        end
        InitCooldownCurves()
        local auraDurObj = C_UnitAuras and C_UnitAuras.GetAuraDuration
                           and C_UnitAuras.GetAuraDuration(unit, auraID)
        if auraDurObj then
          local thresholdCurve = GetGlowThresholdCurve(threshold)
          if thresholdCurve then
            local ok, glowAlpha = pcall(function()
              return auraDurObj:EvaluateRemainingPercent(thresholdCurve)
            end)
            if ok and glowAlpha ~= nil then
              SetGlowAlpha(frame, glowAlpha, stateVisuals)
            else ShowReadyGlow(frame, stateVisuals) end
          else ShowReadyGlow(frame, stateVisuals) end
        else ShowReadyGlow(frame, stateVisuals) end
      else ShowReadyGlow(frame, stateVisuals) end
      frame._arcTargetGlow = true
    else
      HideReadyGlow(frame)
      frame._arcTargetGlow = true
    end
  end
end


-- ═══════════════════════════════════════════════════════════════════
-- SHARED: Aura active glow evaluation for cooldown frames
-- Used by both HandleCooldownLogic and HandleIgnoreAuraOverride.
-- CDM sets frame.auraInstanceID when the aura is active — use that
-- directly rather than any spell-readiness proxy.
-- ═══════════════════════════════════════════════════════════════════
EvaluateAuraActiveGlow = function(frame, cfg)
  local isAuraGlowPreview = ns.CDMEnhanceOptions and ns.CDMEnhanceOptions.IsAuraGlowPreviewActive
    and ns.CDMEnhanceOptions.IsAuraGlowPreviewActive(frame.cooldownID)
  local aaCfg = cfg.auraActiveState
  if isAuraGlowPreview or (aaCfg and (aaCfg.glow or aaCfg.glowWhenMissing)) then
    local resolvedCfg = aaCfg or {}
    local isActive = HasAuraInstanceID(frame.auraInstanceID) or (frame.totemData ~= nil)
    if ShouldShowAuraActiveGlow(resolvedCfg, frame, isActive) then
      ShowAuraActiveGlow(frame, resolvedCfg)
    else
      HideAuraActiveGlow(frame)
    end
  elseif frame._arcAuraActiveGlowActive then
    HideAuraActiveGlow(frame)
  end
end


-- ═══════════════════════════════════════════════════════════════════
-- PATH C: Cooldown Logic — BINARY (matches ArcAuras pattern)
-- ═══════════════════════════════════════════════════════════════════
local function HandleCooldownLogic(frame, iconTex, cfg, stateVisuals)
  local spellID = ResolveCurrentSpellID(frame, cfg)
  if not spellID then
    frame._arcDesatBranch = "C1_NO_SPELL"
    frame._arcForceDesatValue = nil
    frame._arcEnforceReadyAlpha = false
    frame._arcReadyAlphaValue = nil
    frame._arcTargetAlpha = nil
    frame._arcDesiredSwipe = nil
    frame._arcDesiredEdge = nil
    frame._arcDesiredVertexColor = nil
    return
  end

  local isOnCooldown, isRecharging, isChargeSpell, isOnGCD = ReadCooldownState(frame, spellID)

  local waitForNoCharges = isChargeSpell and stateVisuals.waitForNoCharges
  local glowWhileCharges = stateVisuals.glowWhileChargesAvailable

  local useCooldownVisuals
  if isOnCooldown then useCooldownVisuals = true
  elseif isChargeSpell and isRecharging then useCooldownVisuals = not waitForNoCharges
  else useCooldownVisuals = false end

  local isGlowEligible
  if isOnCooldown then isGlowEligible = false
  elseif isChargeSpell and isRecharging and not glowWhileCharges then isGlowEligible = false
  else isGlowEligible = true end

  local cfgHasIgnoreAura = (cfg.auraActiveState and cfg.auraActiveState.ignoreAuraOverride)
                        or (cfg.cooldownSwipe and cfg.cooldownSwipe.ignoreAuraOverride)
  local hasActiveAuraDisplay = not cfgHasIgnoreAura
                               and ((frame.wasSetFromAura == true)
                                    or (frame.totemData ~= nil))

  frame:Show()

  if useCooldownVisuals then
    frame._arcDesatBranch = "C_BIN_CD"
    ApplyCooldownAlpha(frame, stateVisuals)
    ApplyCooldownDesat(frame, iconTex, stateVisuals, hasActiveAuraDisplay, isRecharging)
    if stateVisuals.cooldownTint and stateVisuals.cooldownTintColor then
      local col = stateVisuals.cooldownTintColor
      SetVertexColorSafe(frame, iconTex, col.r or 0.5, col.g or 0.5, col.b or 0.5)
    else
      frame._arcDesiredVertexColor = nil
    end
    if isGlowEligible then ApplyReadyGlow(frame, stateVisuals) else HideReadyGlow(frame) end
  else
    frame._arcDesatBranch = "C_BIN_READY"
    frame._arcPreserveCooldownPath = nil  -- Cooldown ended, allow normal dispatch
    local usabilityAlpha, usabilityPreserveText = GetUsabilityAlpha(frame, spellID, cfg)
    ApplyReadyState(frame, iconTex, stateVisuals, usabilityAlpha, usabilityPreserveText)
    frame._arcDesiredVertexColor = nil
    if isGlowEligible then ApplyReadyGlow(frame, stateVisuals) else HideReadyGlow(frame) end
  end

  -- CHARGE-CONDITIONAL TEXT (hideAtZero / hideWhenHasCharges)
  ApplyChargeConditionalText(frame, cfg, isChargeSpell, isRecharging, isOnCooldown)

  -- SWIPE/EDGE — single source of truth
  DecideAndApplySwipeEdge(frame, cfg, isOnCooldown, isRecharging, isChargeSpell, isOnGCD, false)

  -- AURA ACTIVE GLOW
  EvaluateAuraActiveGlow(frame, cfg)
end


-- ═══════════════════════════════════════════════════════════════════
-- MAIN DISPATCHER
-- ═══════════════════════════════════════════════════════════════════
local function NewApplyCooldownStateVisuals(frame, cfg, normalAlpha, stateVisuals)
  if not frame then return end
  if not resolved then
    if not ResolveDependencies() then return end
  end
  if frame._arcConfig or frame._arcAuraID then return end

  local iconTex = ResolveIconTexture(frame)
  if not iconTex then return end

  if not stateVisuals then
    stateVisuals = GetEffectiveStateVisuals(cfg)
  end

  local cdID = frame.cooldownID
  local isGlowPreview = cdID and ns.CDMEnhanceOptions
                        and ns.CDMEnhanceOptions.IsGlowPreviewActive
                        and ns.CDMEnhanceOptions.IsGlowPreviewActive(cdID)

  local ignoreAuraOverride = (cfg.auraActiveState and cfg.auraActiveState.ignoreAuraOverride)
                          or (cfg.cooldownSwipe and cfg.cooldownSwipe.ignoreAuraOverride)

  local hasSpellUsability = cfg.spellUsability and cfg.spellUsability.enabled == true
  local hasNoGCDSwipe = cfg.cooldownSwipe and cfg.cooldownSwipe.noGCDSwipe
  local hasWaitFlags = cfg.cooldownSwipe and (cfg.cooldownSwipe.swipeWaitForNoCharges or cfg.cooldownSwipe.edgeWaitForNoCharges)
  local hasChargeTextFlags = (cfg.chargeText and cfg.chargeText.enabled ~= false and cfg.chargeText.hideAtZero)
                          or (cfg.cooldownText and cfg.cooldownText.enabled ~= false and cfg.cooldownText.hideWhenHasCharges)

  if not stateVisuals and not isGlowPreview and not ignoreAuraOverride and not hasSpellUsability and not hasNoGCDSwipe and not hasWaitFlags and not hasChargeTextFlags then
    local prevBranch = frame._arcDesatBranch
    local wasManagedDesat = prevBranch ~= nil and prevBranch ~= "NO_SV_EARLY"
    frame._arcForceDesatValue = nil
    frame._arcReadyForGlow = false
    frame._arcDesatBranch = "NO_SV_EARLY"
    frame._arcDesiredSwipe = nil
    frame._arcDesiredEdge = nil
    frame._arcDesiredVertexColor = nil
    HideReadyGlow(frame)
    -- Clean up leftover aura active glow (e.g. glowWhenMissing was just disabled)
    if frame._arcAuraActiveGlowActive then
      HideAuraActiveGlow(frame)
    end
    if wasManagedDesat then
      SetDesat(iconTex, 0)
      frame._arcBypassVertexHook = true
      if iconTex then iconTex:SetVertexColor(1, 1, 1, 1) end
      frame._arcBypassVertexHook = false
      ApplyBorderDesaturation(frame, 0)
    end
    return
  end

  if not stateVisuals then
    local rs = cfg.cooldownStateVisuals and cfg.cooldownStateVisuals.readyState or {}
    stateVisuals = {
      readyAlpha          = 1.0,
      readyGlow           = isGlowPreview and true or (rs.glow == true),
      readyGlowType       = rs.glowType or "button",
      readyGlowColor      = rs.glowColor,
      readyGlowIntensity  = rs.glowIntensity or 1.0,
      readyGlowScale      = rs.glowScale or 1.0,
      readyGlowSpeed      = rs.glowSpeed or 0.25,
      readyGlowLines      = rs.glowLines or 8,
      readyGlowThickness  = rs.glowThickness or 2,
      readyGlowParticles  = rs.glowParticles or 4,
      readyGlowXOffset    = rs.glowXOffset or 0,
      readyGlowYOffset    = rs.glowYOffset or 0,
      cooldownAlpha       = 1.0,
    }
  end

  if isGlowPreview then
    ShowReadyGlow(frame, stateVisuals)
    return
  end

  local useAuraLogic = cfg._isAura or false
  if not useAuraLogic then
    if frame.wasSetFromAura == true then useAuraLogic = true end
  end

  -- OVERRIDE TRANSITION PROTECTION: spell override swaps (e.g. Surging Totem
  -- → Retract → back) can flip wasSetFromAura/totemData, diverting from
  -- cooldown-binary to aura-logic. Aura logic sees totemData as "active aura"
  -- → AURA_READY, hiding the remaining cooldown. If CDMEnhance flagged this
  -- frame during override detection, force cooldown path until CD ends.
  if useAuraLogic and frame._arcPreserveCooldownPath then
    useAuraLogic = false
  end

  -- DISPATCH
  if ignoreAuraOverride then
    -- wasSetFromAura: CDM actively displaying aura duration on the swipe (authoritative).
    -- _arcAuraActive: covers timing gap — OnAuraInstanceInfoSet fires and sets this true
    --                 BEFORE CDM sets wasSetFromAura. Without it the first dispatch after
    --                 aura gained routes wrong.
    -- totemData: totem active on this frame.
    -- NOTE: HasAuraInstanceID alone is wrong — Blizzard sets auraInstanceID internally
    -- on some cooldown frames even when not displaying aura duration.
    local isAuraPresent = (frame.wasSetFromAura == true)
                       or (frame._arcAuraActive == true)
                       or (frame.totemData ~= nil)
    if isAuraPresent then
      frame._arcDesatBranch = "DISPATCH_IAO"
      frame._arcIgnoreAuraOverride = true
      HandleIgnoreAuraOverride(frame, iconTex, cfg, stateVisuals)
    else
      frame._arcDesatBranch = "DISPATCH_IAO_NO_AURA"
      frame._arcIgnoreAuraOverride = true
      HandleCooldownLogic(frame, iconTex, cfg, stateVisuals)
    end
  elseif useAuraLogic then
    -- EVENT-DRIVEN AURA FRAMES: OptimizedApplyIconVisuals is the authority
    -- on alpha/desat/tint for true aura frames (cfg._isAura or totem).
    -- It fires instantly on SetAuraInstanceInfo/ClearAuraInstanceInfo hooks.
    -- CooldownState's HandleAuraLogic duplicates that work and can arrive
    -- late (via rescans/tickers), overwriting the correct values.
    -- Exception: cooldown frames with wasSetFromAura need HandleAuraLogic
    -- because their sub-path uses ReadCooldownState (spell cooldown, not aura).
    if cfg._isAura then
      -- True aura frame — CooldownState never touches these, AuraFrames owns them
      return
    end
    frame._arcDesatBranch = "DISPATCH_AURA"
    frame._arcIgnoreAuraOverride = false
    HandleAuraLogic(frame, iconTex, cfg, stateVisuals)
  else
    frame._arcDesatBranch = "DISPATCH_CD"
    frame._arcIgnoreAuraOverride = false
    HandleCooldownLogic(frame, iconTex, cfg, stateVisuals)
  end
end


-- ═══════════════════════════════════════════════════════════════════
-- STANDALONE READY GLOW ENFORCEMENT (shadow binary detection)
-- Mirrors ArcAurasCooldown lines 540-548: reads shadows, decides glow.
-- Called from DispatchAfterShadowUpdate and exported for CDMEnhance.
-- ═══════════════════════════════════════════════════════════════════
EnforceCooldownReadyGlow = function(frame, stateVisuals)
  if not frame then return end
  if not resolved then
    if not ResolveDependencies() then return end
  end
  if not stateVisuals then return end

  -- Feed shadow first (match ArcAurasCooldown: always feed before reading)
  local spellID
  if frame.cooldownInfo then
    spellID = frame.cooldownInfo.overrideSpellID or frame.cooldownInfo.spellID
  end
  if not spellID then spellID = frame._arcCachedSpellID end
  if spellID then
    EnsureShadowCooldown(frame)
    FeedShadowCooldown(frame, spellID)
  end

  local shadowCD = frame._arcCDMShadowCooldown
  local isOnCooldown = shadowCD and shadowCD:IsShown() or false

  local chargeShadow = frame._arcCDMChargeShadow
  local isRecharging = chargeShadow and chargeShadow:IsShown() or false

  local glowWhileCharges = stateVisuals.glowWhileChargesAvailable

  local isGlowEligible
  if isOnCooldown then
    isGlowEligible = false
  elseif isRecharging and not glowWhileCharges then
    isGlowEligible = false
  else
    isGlowEligible = true
  end

  if isGlowEligible and ShouldShowReadyGlow(stateVisuals, frame) then
    ShowReadyGlow(frame, stateVisuals)
  else
    HideReadyGlow(frame)
  end
end


-- ═══════════════════════════════════════════════════════════════════
-- INSTALL
-- ═══════════════════════════════════════════════════════════════════
ns.CDMEnhance.ApplyCooldownStateVisuals = NewApplyCooldownStateVisuals

ns.CooldownState.Apply                  = NewApplyCooldownStateVisuals
ns.CooldownState.ApplyReadyState        = ApplyReadyState
ns.CooldownState.ApplyReadyGlow         = ApplyReadyGlow
ns.CooldownState.ResolveIconTexture     = ResolveIconTexture
ns.CooldownState.GetUsabilityAlpha      = GetUsabilityAlpha
ns.CooldownState.EnforceReadyGlow       = EnforceCooldownReadyGlow
ns.CooldownState.PreserveDurationText   = PreserveDurationText
-- Exported for profiler auto-wrapping (was local-only, showed as ? in caller analysis)
ns.CooldownState.DispatchAfterShadowUpdate = DispatchAfterShadowUpdate

function ns.CooldownState.FeedShadow(frame, cfg)
  if not frame then return end
  if frame._arcConfig or frame._arcAuraID then return end
  local spellID
  if frame.cooldownInfo then
    spellID = frame.cooldownInfo.overrideSpellID or frame.cooldownInfo.spellID
  end
  if not spellID and cfg then spellID = cfg._spellID end
  if spellID then
    FeedShadowCooldown(frame, spellID)
  end
end

-- Exposed for debugger: read current binary state from shadow frames directly.
function ns.CooldownState.ReadBinaryState(frame)
  if not frame then return nil, nil, nil, nil end
  local isChargeSpell = frame._arcIsChargeSpellCached or false
  local isOnGCD       = frame._arcLastIsOnGCD or false
  local isOnCooldown, isRecharging = GetBinaryCooldownState(frame)
  return isOnCooldown, isRecharging, isChargeSpell, isOnGCD
end

function ns.CooldownState.EnsureShadow(frame)
  if not frame then return end
  EnsureShadowCooldown(frame)
end