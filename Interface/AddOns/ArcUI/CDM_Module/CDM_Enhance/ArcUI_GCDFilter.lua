-- ===================================================================
-- ArcUI_GCDFilter.lua
-- Single source of truth for GCD filtering on CDM visual Cooldown frames.
-- NOT for shadow frames — ArcUI_CooldownState owns those.
--
-- All logic that controls what frame.Cooldown shows during a GCD window
-- for charge spells lives here and NOWHERE ELSE.
--
-- Responsibilities:
--   SetCooldown hook:
--     Charge spells where wasSetFromAura=false (or ignoreAuraOverride=on):
--     CDM pushes the GCD duration object every cycle, making the recharge
--     swipe animate to the wrong 1.5s timer. Push GetSpellChargeDuration
--     immediately after to correct it. Skipped when wasSetFromAura=true
--     and ignoreAuraOverride is off — CDM owns the duration on those frames.
--
--   SetDrawSwipe / SetDrawEdge hooks:
--     ShouldSuppressGCD: single unified decision — suppress swipe/edge
--     when frame is GCD-only (isOnGCD=true, isOnActualCooldown=false).
--     Charge spell exception: if charges are recharging
--     (GetSpellCharges().isActive == true), do NOT suppress — the
--     recharge swipe must remain visible. Race condition handled naturally:
--     CDM calls SetDrawSwipe(true) when isActive just became true, so
--     ShouldSuppressGCD returns false and it passes through immediately.
--
-- Install: ns.GCDFilter.Install(frame, cdID)
--   Called from ArcUI_CDMEnhance.ApplyIconStyle after _arcNoGCDSwipeEnabled
--   is stored on the frame. Safe to call multiple times — guarded by
--   frame.Cooldown._arcGCDFilterHooked.
-- ===================================================================

local ADDON, ns = ...

ns.GCDFilter = ns.GCDFilter or {}
local GCDFilter = ns.GCDFilter

-- ═══════════════════════════════════════════════════════════════════
-- SINGLE GCD SUPPRESSION DECISION
-- Called at hook-fire time (runtime), reads live CDM fields.
-- ═══════════════════════════════════════════════════════════════════
local function ShouldSuppressGCD(frame)
  if not frame then return false end
  if not frame._arcNoGCDSwipeEnabled then return false end
  if not frame.isOnGCD then return false end
  if frame.isOnActualCooldown then return false end
  if frame._arcConfig or frame._arcAuraID then return false end
  if frame.wasSetFromAura == true and not frame._arcIgnoreAuraOverride then return false end
  if frame._arcViewerType == "aura" then return false end
  -- Charge spell: isOnGCD stays true while a charge is recharging.
  -- GetSpellCharges().isActive is non-secret and tells us a recharge is running.
  -- If recharging, do NOT suppress — the swipe must show the recharge timer.
  if frame._arcIsChargeSpellCached then
    local ci = frame.cooldownInfo
    local spellID = ci and (ci.overrideSpellID or ci.spellID)
    if spellID then
      local chargeInfo = C_Spell.GetSpellCharges(spellID)
      if chargeInfo and chargeInfo.isActive == true then return false end
    end
  end
  return true
end

GCDFilter.ShouldSuppressGCD = ShouldSuppressGCD

-- ═══════════════════════════════════════════════════════════════════
-- INSTALL
-- Hooks frame.Cooldown (the CDM visual Cooldown widget) once per icon.
-- ═══════════════════════════════════════════════════════════════════
function GCDFilter.Install(frame, cdID)
  if not frame or not frame.Cooldown then return end
  if frame.Cooldown._arcGCDFilterHooked then return end
  frame.Cooldown._arcGCDFilterHooked = true
  -- Stash parent reference — all three hooks read it via self._arcParentFrame.
  -- Don't overwrite if already set by another hook installer.
  if not frame.Cooldown._arcParentFrame then
    frame.Cooldown._arcParentFrame = frame
  end
  if not frame.Cooldown._arcCdID then
    frame.Cooldown._arcCdID = cdID
  end

  local cd = frame.Cooldown

  -- ── SetCooldown: push charge recharge duration ──────────────────
  -- CDM calls SetCooldown with the GCD duration every cycle. For charge
  -- spells this makes the swipe animate to the wrong 1.5s timer instead
  -- of the real recharge duration.
  -- Replace it with GetSpellChargeDuration immediately after CDM writes.
  -- Gate: skip when wasSetFromAura=true and ignoreAuraOverride is off —
  -- those frames let CDM own the duration (aura display). All other
  -- charge frames need the push.
  hooksecurefunc(cd, "SetCooldown", function(self)
    local pf = self._arcParentFrame
    if not pf then return end
    if not pf._arcNoGCDSwipeEnabled then return end
    if not pf._arcIsChargeSpellCached then return end
    if pf._arcBypassCDHook then return end
    -- Skip aura-display frames:
    -- If wasSetFromAura=true and no IAO: CDM owns the duration, skip.
    -- If wasSetFromAura=true and IAO=true: IAOFight owns the push, skip here too.
    -- GCDFilter only handles charge duration push for non-aura frames.
    if pf.wasSetFromAura == true then return end
    local ci = pf.cooldownInfo
    local spellID = ci and (ci.overrideSpellID or ci.spellID)
    if not spellID then return end
    -- Trust _arcIsChargeSpellCached — set at scan time when maxCharges>1 was confirmed.
    -- maxCharges can be nil at runtime (secret/timing), re-checking it here breaks pushes.
    local chargesInfo = C_Spell.GetSpellCharges(spellID)
    if not chargesInfo then return end
    if chargesInfo.isActive ~= true then return end
    if not C_Spell.GetSpellChargeDuration then return end
    local durObj = C_Spell.GetSpellChargeDuration(spellID)
    if not durObj then return end
    pf._arcBypassCDHook = true
    self:SetCooldownFromDurationObject(durObj)
    pf._arcBypassCDHook = false
  end)

  -- ── SetDrawSwipe: suppress GCD-only swipe ───────────────────────
  hooksecurefunc(cd, "SetDrawSwipe", function(self, show)
    if show and ShouldSuppressGCD(self._arcParentFrame) then
      self:SetDrawSwipe(false)
    end
  end)

  -- ── SetDrawEdge: suppress GCD-only edge ─────────────────────────
  hooksecurefunc(cd, "SetDrawEdge", function(self, show)
    if show and ShouldSuppressGCD(self._arcParentFrame) then
      self:SetDrawEdge(false)
    end
  end)
end