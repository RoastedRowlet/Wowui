local _, NS = ...

-- Tint rules engine. A rule is a colour plus debuffs that must all be on the
-- unit. Aura state is never read -- a texture on an aura button draws only
-- while that button is shown. Several debuffs are ANDed by nesting containers,
-- tint on the deepest button; cross-button masking is refused as forbidden.

-- Hoisted to upvalues. Every reference to a global is a hash lookup in _G, and
-- the maintenance sweep reaches these once per container, per rule, per rig,
-- per second. Standard addon practice, and the one classic Lua idiom this file
-- was missing.
local pairs, ipairs, pcall, type = pairs, ipairs, pcall, type

-- Shared and NEVER mutated. `x or {}` allocates a fresh table on every
-- evaluation where x is nil, which on the per-second sweep is garbage per rig
-- per rule. Only ever used where the result is READ -- handing this to
-- something that inserts would corrupt every other caller at once.
local EMPTY = {}

local MAX_TINTS_PER_RULE = 1200

-- Aura slots, not groups: a group pools ten buttons and calls initializeFrame
-- on each, so a combo rule costs 100 textures per plate. A slot pools one.
-- Asked of the container as it is created -- probing at ADDON_LOADED cached
-- "unavailable" before Blizzard_AuraContainer had loaded. /pt slots off.
local function SlotsAvailable(frame)
  -- PROBE FIRST, always. slotApiPresent describes the CLIENT, not the user's
  -- preference, and returning early on the setting left it nil -- so after
  -- /pt slots off plus a reload everything reported "unavailable on this
  -- client", which reads as "your client cannot do this" rather than "you
  -- turned it off". The switch to pooled groups was working the whole time;
  -- only the reporting was wrong, and it made a deliberate A/B test look like
  -- a failed command.
  local present = type(frame.AddAuraSlot) == "function"
    and type(frame.SetAuraSlotCandidateFilters) == "function"
  NS.slotApiPresent = present
  if NS.db and NS.db.useAuraSlots == false then return false end
  return present
end
local LEVELS_PER_RULE = 4

-- OVERLAY is -8..7; 6 and 7 are the border band, so the ladder gets -8..5,
-- two per rule. That is what caps the ladder, not cost.
--
-- Declared HERE, not next to the ladder code that reads them. These were
-- file-locals defined below PlaterMissingPlan, and a Lua local is only in
-- scope for what follows it -- so inside that function both names compiled as
-- globals and read nil. Every missing-debuff rule on a Plater bar threw
-- (`bad argument #1 to 'min'`), which aborts the rig build, so the plate ended
-- with zero containers and could not colour at all. Not a level problem, and
-- the sublevel maths was never reached.
local MISSING_SUBLEVEL_MIN = -8
local MISSING_SUBLEVEL_MAX = 5

-- Cumulative, for the session. Per-record failure counts are the only evidence
-- a container was refused, and a rig is DISCARDED when it gets repaired -- so
-- the recovery attempt destroys the proof of what went wrong. These survive it.
--
-- Split by lockdown because that is the whole question: secure containers
-- cannot be created in combat, so a plate first seen mid-pull can build empty.
-- "Refused while in combat" climbing during a big pull is that theory being
-- confirmed; refusals OUT of combat mean something else entirely.
NS.buildFailures = { containers = 0, containersInCombat = 0, combos = 0 }

function NS.NoteContainerRefused()
  local f = NS.buildFailures
  f.containers = f.containers + 1
  if InCombatLockdown() then
    f.containersInCombat = f.containersInCombat + 1
  end
end

local UNDERLAY_OVERDRAW = 0

-- A missing cover needs overdraw: it hides a wash on the same rect on a
-- different frame, with no inset to absorb rounding.
local MISSING_COVER_OVERDRAW = 1

-- Pixels each rank is inset. Two rules that do not cover each other build no
-- underlay, so without this the higher wins only on frame level, which cannot
-- arbitrate in an instance. Inset the lower rules, never grow the top one --
-- growing paints over the plate's border.
local RANK_INSET = 0.5
local RANK_INSET_MAX = 1


-- Pull the tint in from the bar's edges, so the host's border shows through.
-- Flush is the baseline; this adjusts either side.
local BASE_INSET = 0
NS.BASE_INSET = BASE_INSET

-- Frame level for our containers and tints, relative to the health bar.
-- Elevated by default so the tint is not hidden behind the bar's fill.
--
-- Pinned flat on Plater (its name text is on the bar at OVERLAY 7, so any
-- elevation covers it) and on Blizzard's default plate (per-rule elevation has
-- no cap and climbs past unitFrame's name).
function NS.IsPlaterBar(healthBar)
  -- Per adapter, then the structural test as a backstop. The shipped defaults
  -- reproduce that test exactly (Plater and Blizzard flat, everyone else
  -- elevated), so this is belt and braces rather than two answers.
  local pin = NS.AdapterSetting and NS.AdapterSetting(healthBar, "pinFlat")
  if pin ~= nil then return pin and true or false end
  return healthBar.unitName ~= nil or healthBar.ptDefaultBlizzardBar == true
end

function NS.BaseLevelFor(healthBar)
  local perAdapter = NS.AdapterSetting and NS.AdapterSetting(healthBar, "levelOffset")
  local offset = NS.IsPlaterBar(healthBar) and 0
    or (perAdapter or NS.db.levelOffset or 1)
  return healthBar:GetFrameLevel() + offset
end

-- Lowest OVERLAY sublevel Plater's own text uses on this bar. Some skins draw
-- a health value on the bar too, so this is discovered, not hardcoded to 7.
--
-- okLayer only proves the CALL succeeded, not that what it returned is safe
-- to touch: unlike healthBar.unitName (a specific FontString known to be
-- plain -- see PrintBarDebug), an arbitrary region found by scanning every
-- FontString on the bar is NOT guaranteed non-secret, and a raw "layer ==
-- "OVERLAY"" on a secret value throws ("attempt to compare ... a secret
-- string value, while execution tainted"). This runs during BuildTints on
-- every Plater plate, wrapped in a pcall at the call site -- so an unguarded
-- throw here does not crash the game, but it does silently drop the whole
-- rig as a build error, which is a much worse failure mode than a bad
-- diagnostic print.
function NS.PlaterTextFloor(healthBar)
  local floor = 7
  local okRegions, regions = pcall(function() return { healthBar:GetRegions() } end)
  if okRegions and regions then
    for _, region in ipairs(regions) do
      if region and region.GetObjectType and region:GetObjectType() == "FontString" then
        local okLayer, layer, sublevel = pcall(region.GetDrawLayer, region)
        local safe = okLayer
          and not (issecretvalue and (issecretvalue(layer) or issecretvalue(sublevel)))
        if safe and layer == "OVERLAY" and type(sublevel) == "number" then
          floor = math.min(floor, sublevel)
        end
      end
    end
  end
  return floor
end

-- Draw sublevels for a flat-pinned bar, allocated to what each rule ACTUALLY
-- draws rather than a fixed three per rank.
--
-- floor is where the host's text starts, floor-1 is our border band, and the
-- ladder runs from floor-3 downward to -8.
--
-- The previous version gave every rule three consecutive sublevels -- cover,
-- tint, underlay -- whether or not it had a cover or an underlay to put in
-- them. That is affordable when floor is 7, which is what the design assumed
-- (four clean ranks before anything clamps). It is not affordable on a live
-- Plater bar: every FontString there reports OVERLAY 0, including the ones
-- Plater's own code explicitly sends to 5 and 7, so the entire ladder has to
-- fit between -1 and -8. Three-per-rule into that range is two rules. The
-- third rule's tint and its own underlay both clamp onto -8, and its cover
-- lands on the second rule's underlay -- two real collisions, with undefined
-- draw order between an opaque bar replica and the tint it is supposed to
-- sit under. Measured on a real client, not inferred.
--
-- Most rules need exactly one sublevel. An underlay exists only when the rule
-- covers a lower one, a cover only with "cover missing health", and the
-- pandemic flash is hardcoded to tint+1 in BuildRule, so it claims a slot of
-- its own whenever that module is on. Handing out only what is asked for fits
-- four to six rules in the same space instead of two.
--
-- The TOP of the ladder is deliberately unchanged at floor-3. Compacting
-- downward only means nothing can newly collide with whatever sits above --
-- notably the missing ladder, which shares this range on a flat-pinned bar.
local SUBLEVEL_MIN = -8
local SUBLEVEL_MAX = 7

-- What the host already draws on this bar, per layer.
--
-- EVERY host texture counts, shown or not.
--
-- Shown-only was the obvious reading -- a hidden texture cannot cover anything
-- today -- and it is wrong. Host art is conditional: Plater keeps its target
-- selection and marker textures hidden until you target the mob, then shows
-- them. Measured: ARTWORK 4-7 read hidden on an untargeted plate, so the pool
-- handed rule 4 ARTWORK 5, which Plater owns and would light up the moment
-- that plate became the target.
--
-- We cannot see that happen mid-combat and could not move the rule if we did.
-- So a slot the host has ever claimed is the host's. Occupying it costs one
-- slot; not occupying it costs correctness on exactly the plate you are
-- looking at.
--
-- Our own tints never appear here, which is what makes this safe to run on
-- every rebuild: they are created on the aura BUTTON, not on the bar, so
-- healthBar:GetRegions() returns host art only.
function NS.HostOccupancy(healthBar)
  local occ = { ARTWORK = {}, OVERLAY = {} }
  local okRegions, regions = pcall(function() return { healthBar:GetRegions() } end)
  for _, region in ipairs(okRegions and regions or {}) do
    local okType, kind = pcall(region.GetObjectType, region)
    if okType and kind == "Texture" then
      local okDL, layer, sub = pcall(region.GetDrawLayer, region)
      local secret = issecretvalue and (issecretvalue(layer) or issecretvalue(sub))
      if okDL and not secret and occ[layer] and type(sub) == "number" then
        occ[layer][sub] = true
      end
    end
  end
  return occ
end

local HostOccupancy = NS.HostOccupancy

-- Lowest OVERLAY sublevel the host has claimed -- its border, in practice.
-- Computed from the HOST survey only, and passed around rather than re-derived,
-- because the missing ladder marks its own slots occupied before the presence
-- allocator runs and would otherwise drag this down onto our own textures.
function NS.OverlayCeiling(occ)
  local lowest
  for sub in pairs(occ.OVERLAY) do
    if lowest == nil or sub < lowest then lowest = sub end
  end
  return lowest
end

-- Where the host's own fill sits. Everything we draw has to be strictly above
-- it, and a TIE is worse than losing: the winner is creation order, it differs
-- between hosts (our texture beat a plain bar's fill, Plater's fill beat ours),
-- and it can flip when the host touches its bar.
local function FillSublevel(healthBar)
  local okTex, tex = pcall(healthBar.GetStatusBarTexture, healthBar)
  if okTex and tex then
    local okDL, layer, sub = pcall(tex.GetDrawLayer, tex)
    local secret = issecretvalue and (issecretvalue(layer) or issecretvalue(sub))
    if okDL and not secret and layer == "ARTWORK" and type(sub) == "number" then
      return sub
    end
  end
  return 0
end

-- n CONSECUTIVE free sublevels at or below `cursor`, descending. Returns the
-- run's top sublevel, or nil if it will not fit.
--
-- Consecutive matters: a rule's pieces sit at tint-1, tint and tint+1, so a run
-- with a hole in it would put its underlay or cover on top of host art.
local function TakeRun(occ, layer, cursor, bottom, n)
  local sub = cursor
  while sub - (n - 1) >= bottom do
    local free = true
    for k = 0, n - 1 do
      if occ[layer][sub - k] then free = false break end
    end
    if free then return sub end
    sub = sub - 1
  end
  return nil
end

-- Sublevels for the MISSING ladder on a flat-pinned bar.
--
-- Two bugs this replaces, both Plater-only and both silent:
--
--  1. Collision with presence rules. The presence allocator is handed only the
--     presence list, so it never knew the ladder existed. In occlusion mode the
--     ladder's fixed arithmetic starts at -8 and climbs (wash -8, cover -7,
--     wash -6 ...) while the presence pool runs -3 down to -8 -- the same
--     range, both claiming it, winner decided by aura-button init order. That
--     is per plate, which is the inconsistency.
--  2. Host art. The ladder's sublevels were pure arithmetic and never consulted
--     what the host already draws, while presence rules were surveyed.
--
-- Both are fixed the same way: allocate from the shared occupancy map and mark
-- what is taken, so the presence allocator that runs next sees it.
--
-- Direction differs by mode and that is deliberate. Occlusion sits BELOW every
-- presence rule (its cover is an opaque replica that has to lose to a real
-- tint). Displacement sits ABOVE them: a missing wash and a presence tint can
-- both be lit at once, and the reminder is the one that has to be seen.
function NS.PlaterMissingPlan(occ, count, displace, ceiling)
  local out = {}
  if not count or count <= 0 then return out end

  if displace then
    local top = math.min(MISSING_SUBLEVEL_MAX,
      ceiling and (ceiling - 1) or MISSING_SUBLEVEL_MAX)
    local sub = top
    for rank = 1, count do
      while sub >= MISSING_SUBLEVEL_MIN and occ.OVERLAY[sub] do sub = sub - 1 end
      if sub < MISSING_SUBLEVEL_MIN then break end
      occ.OVERLAY[sub] = true
      out[rank] = { wash = sub }
      sub = sub - 1
    end
  else
    -- Wash and its cover must be ADJACENT and in that order, so this takes
    -- pairs rather than single slots.
    local sub = MISSING_SUBLEVEL_MIN
    for rank = 1, count do
      while sub + 1 <= MISSING_SUBLEVEL_MAX
        and (occ.OVERLAY[sub] or occ.OVERLAY[sub + 1]) do
        sub = sub + 1
      end
      if sub + 1 > MISSING_SUBLEVEL_MAX then break end
      occ.OVERLAY[sub] = true
      occ.OVERLAY[sub + 1] = true
      out[rank] = { wash = sub, cover = sub + 1 }
      sub = sub + 2
    end
  end
  return out
end

-- Sublevels for a flat-pinned bar, drawn from a pool spanning TWO layers.
--
-- OVERLAY alone gives about six usable slots on Plater, and a four-rule
-- profile with Pandemic Flash needs eight -- measured, with two rules landing
-- on -8 together and the winner decided by whichever button initialised first.
-- That is per-plate, which is why identical rules paint some bars and not
-- others in the same pull.
--
-- ARTWORK above the host's fill is the room nobody was using: it sits above
-- the bar's own colour and below EVERYTHING in OVERLAY, which is exactly where
-- a tint wants to be. A staircase probe on a live Plater bar showed ARTWORK 1
-- as the first visible sublevel and 1..7 all drawing.
--
-- Because ARTWORK is entirely below OVERLAY, a rule that spills into it is
-- automatically outranked by every rule above it -- rule priority comes out
-- right for free, with no cross-layer arithmetic. Each rule's own pieces stay
-- within ONE layer, so tint+1 / tint-1 keep meaning what they always did.
-- occ and ceiling come from the caller so the missing ladder can claim its
-- slots first and be seen here. ceiling is the HOST's, deliberately computed
-- before any of our own reservations went into occ.
function NS.PlaterSublevelPlan(ordered, floor, pandemicOn, healthBar, occ, ceiling)
  floor = floor or 7
  local plan, starved = {}, false
  local count = #ordered

  occ = occ or (healthBar and HostOccupancy(healthBar))
    or { ARTWORK = {}, OVERLAY = {} }

  -- The ceiling is the lowest SHOWN host texture on OVERLAY -- its border, in
  -- practice. NOT its text: a texture cannot cover a FontString at any
  -- sublevel (measured across all 16 on a live plate), so text never
  -- constrained where we draw. The old text-derived floor happened to land in
  -- the same place on Plater and had no reason to.
  if ceiling == nil then ceiling = NS.OverlayCeiling(occ) end

  -- NEVER above the old text-derived top, even when the survey says there is
  -- room. Measured regression: on a live Plater bar the survey missed its
  -- border (hidden at scan time, or living on a child frame, or its layer
  -- reading secret in combat -- all three skip the same way) and placed rule 1
  -- at -1, one ABOVE that border, so the tint painted over the plate outline.
  --
  -- HostOccupancy treats anything unreadable as free, and free is the wrong
  -- guess when being wrong means covering the host's art. Clamping to floor-3
  -- keeps the proven ceiling and lets the pool only ever ADD room below it --
  -- which is where the gain was anyway.
  local overlayTop = math.min(ceiling and (ceiling - 1) or (floor - 3), floor - 3)
  if overlayTop > SUBLEVEL_MAX then overlayTop = SUBLEVEL_MAX end

  local layers = {
    { name = "OVERLAY", cursor = overlayTop, bottom = SUBLEVEL_MIN },
    { name = "ARTWORK", cursor = SUBLEVEL_MAX,
      bottom = (healthBar and FillSublevel(healthBar) or 0) + 1 },
  }

  -- Our border band sits one ABOVE the host's, so "keep the plate's border
  -- visible" redraws on top of it rather than under.
  local borderSublevel = ceiling and (ceiling + 1) or (floor - 1)

  for index, rule in ipairs(ordered) do
    local paints = rule.barEnabled ~= false
    local needsUnderlay = false
    if paints then
      for lower = index + 1, count do
        if NS.RuleCovers(rule, ordered[lower]) then needsUnderlay = true break end
      end
    end
    local needsCover = paints and rule.missingCover and true or false
    -- SINGLE-DEBUFF ONLY, matching BuildRule's own gate
    -- (`record.spellCount == 1`): a flash doubles a rule's texture count and a
    -- combo cannot afford it, so multi-debuff rules never get one. Reserving a
    -- slot for every rule held space for textures that are never created, and
    -- pushed real rules off the bottom of the ladder -- starving a three-rule
    -- profile that fits comfortably.
    local needsFlash = paints and pandemicOn
      and #(rule.conditions or {}) == 1 and true or false

    local entry = {
      needsUnderlay = needsUnderlay,
      needsCover = needsCover,
      layer = "OVERLAY",
    }
    if not paints then
      -- Border-only rule: it draws in the border band, so it takes nothing from
      -- either pool. The numbers still have to be valid, since BuildRule is
      -- handed them either way.
      entry.tint = layers[1].cursor
      entry.underlay = math.max(SUBLEVEL_MIN, entry.tint - 1)
      entry.cover = borderSublevel
    else
      -- Reserve above the tint for whichever of cover/flash this rule has: the
      -- flash is hardcoded to tint+1 in BuildRule, so a cover has to clear it
      -- rather than land on top of it.
      local above = (needsCover and 1 or 0) + (needsFlash and 1 or 0)
      local need = above + 1 + (needsUnderlay and 1 or 0)

      local placed
      for _, L in ipairs(layers) do
        local top = TakeRun(occ, L.name, L.cursor, L.bottom, need)
        if top then
          for k = 0, need - 1 do occ[L.name][top - k] = true end
          L.cursor = top - need
          placed = { layer = L.name, top = top }
          break
        end
      end

      if not placed then
        -- Both pools full. Clamp and flag it rather than silently stacking
        -- rules onto one sublevel where the winner is undefined.
        starved = true
        placed = { layer = "OVERLAY", top = SUBLEVEL_MIN + above }
      end

      local tint = placed.top - above
      entry.layer = placed.layer
      entry.tint = tint
      entry.cover = math.min(SUBLEVEL_MAX, tint + 1 + (needsFlash and 1 or 0))
      entry.underlay = math.max(SUBLEVEL_MIN, tint - 1)
    end
    plan[index] = entry
  end
  return plan, starved
end

-- Memo for config-derived values. AnchorTints re-applies every texture on
-- every rig per reposition, each re-deriving the same LSM fetch, library scan
-- and border walk. Cleared by NS.InvalidateFillCache; generation counter so a
-- stale table cannot be half-updated.
local fillCache = {}

function NS.InvalidateFillCache()
  fillCache = {}
end

local fillCacheEnabled = true
function NS.SetFillCacheEnabled(value)
  fillCacheEnabled = value and true or false
  fillCache = {}
end

-- Keyed by adapter now, not one value for the session: edgeAdjust describes
-- the HOST's bar geometry, so two adapters on screen at once would otherwise
-- share whichever was computed first. healthBar is optional -- the options
-- preview has no bar and wants the generic answer.
function NS.FillInset(healthBar)
  local key = NS.HostName and NS.HostName(healthBar) or "unknown"
  local bucket = fillCache.inset
  if not bucket then bucket = {}; fillCache.inset = bucket end
  local cached = fillCacheEnabled and bucket[key]
  if cached then return cached end
  local adjust = (NS.AdapterSetting and NS.AdapterSetting(healthBar, "edgeAdjust"))
    or (NS.db and NS.db.tints and NS.db.tints.edgeAdjust) or 0
  cached = math.max(-4, math.min(8, BASE_INSET + adjust))
  bucket[key] = cached
  return cached
end
local FillInset = NS.FillInset

-- Widest inside border any enabled rule asks for. Underlays are opaque copies
-- of the bar and would cover a lower rule's border; SetFrameLevel on an aura
-- button is refused, so shrink the underlay instead.

-- Absent means on. Declared here because BORDER_SIDES is further down, and a
-- local declared after its caller resolves to a nil global.
local function PlateOutlineSide(side)
  local sides = NS.db and NS.db.tints and NS.db.tints.plateOutlineSides
  if not sides then return true end
  return sides[side] ~= false
end
NS.PlateOutlineSide = PlateOutlineSide

local function MaxInsideBorder()
  local cached = fillCacheEnabled and fillCache.insideBorder
  if cached then return cached end
  local widest = 0
  if NS.db and NS.db.tints and NS.db.tints.borderEnabled == false then
    fillCache.insideBorder = 0
    return 0
  end
  for _, rule in ipairs(NS.db.tints.borderRules or {}) do
    local b = rule.border
    if rule.enabled ~= false and b and b.enabled and b.grow ~= "OUT" then
      widest = math.max(widest,
        math.min(8, b.thickness or 2) + math.max(0, math.min(12, b.padding or 0)))
    end
  end
  fillCache.insideBorder = widest
  return widest
end

-- How far the plate border reaches inside the bar. The outline sits far above
-- every rule and still lost: tint buttons report a SECRET strata, which cannot
-- be out-ranked. So stop the tint short instead of fighting it.
local function PlateOutlineReserve(healthBar)
  local key = NS.HostName and NS.HostName(healthBar) or "unknown"
  local bucket = fillCache.outlineReserve
  if not bucket then bucket = {}; fillCache.outlineReserve = bucket end
  local cached = fillCacheEnabled and bucket[key]
  if cached then return cached end
  local cfg = (NS.db and NS.db.tints) or {}
  local reserve = 0
  local anySide = PlateOutlineSide("top") or PlateOutlineSide("bottom")
    or PlateOutlineSide("left") or PlateOutlineSide("right")
  if cfg.plateOutline ~= false and anySide then
    local t = math.max(1, math.min(8, cfg.plateOutlineSize or 1))
    -- The gap between the host's bar FRAME and its fill TEXTURE, which is the
    -- most adapter-specific number here.
    local off = (NS.AdapterSetting and NS.AdapterSetting(healthBar, "plateOutlineOffset"))
      or cfg.plateOutlineOffset or 0
    off = math.max(-8, math.min(8, off))
    reserve = math.max(0, t + off)
  end
  bucket[key] = reserve
  return reserve
end

local function EdgeReserve(healthBar)
  return math.max(MaxInsideBorder(), PlateOutlineReserve(healthBar))
end

-- Everything painting the bar body goes through here, so they reserve the same
-- border band. expand grows outward; underlays use it against rounding.
local function AnchorToFill(tex, healthBar, expand)
  local fill = healthBar:GetStatusBarTexture() or healthBar
  -- Two insets: base is the edge inset, inset adds the border reserve.
  --
  -- Three sides only. The fill's right edge is the live health mark, and
  -- reserving there exposes a strip of bar colour that slides with health.
  local base = FillInset(healthBar) - (expand or 0)
  local inset = base + EdgeReserve(healthBar)
  tex:ClearAllPoints()
  -- PixelUtil: this edge moves with health and nothing else covers it, so a
  -- fractional coordinate leaves a hairline.
  if PixelUtil and PixelUtil.SetPoint then
    PixelUtil.SetPoint(tex, "TOPLEFT", fill, "TOPLEFT", inset, -inset)
    PixelUtil.SetPoint(tex, "BOTTOMRIGHT", fill, "BOTTOMRIGHT", -base, inset)
  else
    tex:SetPoint("TOPLEFT", fill, "TOPLEFT", inset, -inset)
    tex:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", -base, inset)
  end
  return tex
end
NS.AnchorToFill = AnchorToFill

-- Pinned to the bar frame, which does not resize with health, so a tile keeps
-- a constant size. Cropped by a mask on the live fill edge.
local function AnchorToBarFrame(tex, healthBar, expand)
  local inset = FillInset(healthBar) + EdgeReserve(healthBar) - (expand or 0)
  tex:ClearAllPoints()
  if PixelUtil and PixelUtil.SetPoint then
    PixelUtil.SetPoint(tex, "TOPLEFT", healthBar, "TOPLEFT", inset, -inset)
    PixelUtil.SetPoint(tex, "BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", -inset, inset)
  else
    tex:SetPoint("TOPLEFT", healthBar, "TOPLEFT", inset, -inset)
    tex:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", -inset, inset)
  end
  return tex
end

-- Covers the missing side. Left edge ties to the fill's live corner, so it
-- tracks health with no polling. Assumes a left-to-right fill.
local function AnchorToMissingFill(tex, healthBar, expand)
  local fill = healthBar:GetStatusBarTexture() or healthBar
  local inset = FillInset(healthBar) + EdgeReserve(healthBar) - (expand or 0)
  tex:ClearAllPoints()
  if PixelUtil and PixelUtil.SetPoint then
    PixelUtil.SetPoint(tex, "TOPLEFT", fill, "TOPRIGHT", 0, -inset)
    PixelUtil.SetPoint(tex, "BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", -inset, inset)
  else
    tex:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, -inset)
    tex:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", -inset, inset)
  end
  return tex
end

-- Missing-debuff rules.
--
-- Absence has no direct expression, so OCCLUSION: draw the wash always, and
-- let a texture on an aura button cover it once the debuff lands. The cover is
-- a replica of the bar's art, maintained by NS.UpdateCovers.
--
-- Several coexist because two lit washes are made unreachable:
--
--   wash k shows iff  D1..D(k-1) present AND Dk absent
--
-- so the button at depth k carries cover k and wash k+1. Ordered by draw
-- sublevel, never frame level -- aura buttons report a secret strata:
--
--   wash 1, cover 1, wash 2, cover 2, ...   bottom to top

NS.MAX_MISSING_RULES =
  math.floor((MISSING_SUBLEVEL_MAX - MISSING_SUBLEVEL_MIN + 1) / 2)

-- The allocated slot for this rank if there is one (flat-pinned bars), else
-- the fixed arithmetic. Elevated bars separate the ladder by FRAME level, so
-- they never needed an allocator and still do not.
local function MissingSub(rig, rank, key, fallback)
  local entry = rig and rig.missingSublevels and rig.missingSublevels[rank]
  local value = entry and entry[key]
  if value then return value end
  return fallback
end

local function MissingWashSublevel(rank)
  return MISSING_SUBLEVEL_MIN + 2 * (rank - 1)
end
local function MissingCoverSublevel(rank)
  return MISSING_SUBLEVEL_MIN + 2 * (rank - 1) + 1
end

-- DISPLACEMENT mode -- the default, NS.db.tints.missingMode.
--
-- The wash is masked, and the mask is shoved off screen when the debuff lands:
--
--   holder     a plain Frame of ours on the health bar
--   wash       a texture on it, two corners pinned to the fill
--   mask       ours, same frame, anchored to a container's moving edge
--   container  filters this rule's debuff, registered LAST
--
-- Nothing of ours touches an aura button -- the button exists only to grow the
-- container. The mask's WRAP MODE is load-bearing: the default masks outside
-- its rect IN, leaving the wash permanently visible.
--
-- Priority falls out free -- every lit wash covers the bar, ranked by sublevel.
local DISPLACE_PUSH = 4000
-- Oversized: the anchor cannot be re-set once the group is registered, so it
-- has to absorb a later resize.
local DISPLACE_MASK_SLACK = 200

-- One sublevel per rule -- no covers to interleave. Rank 1 takes the top.
local function DisplaceWashSublevel(rank)
  return math.max(MISSING_SUBLEVEL_MIN, MISSING_SUBLEVEL_MAX - (rank - 1))
end

-- Only two sublevels sit under the presence border band. Sharing the ladder's
-- top is not a collision -- EdgeReserve keeps bar fills clear of that band.
NS.MAX_MISSING_BORDER_RULES = 2

local function MissingBorderSublevel(rank, top)
  return math.max(MISSING_SUBLEVEL_MIN, (top or 7) - rank)
end

-- Not "occlude" means displacement: it is the default, so an unset field has
-- to mean it here too.
local function MissingModeIsDisplace()
  return not (NS.db and NS.db.tints and NS.db.tints.missingMode == "occlude")
end
NS.MissingModeIsDisplace = MissingModeIsDisplace

-- Four edges. Offsets are unit vectors, so one grow-out distance drives all.
local BORDER_SIDES = {
  { side = "top",    a = "TOPLEFT",     b = "TOPRIGHT",    ax = -1, ay =  1, bx =  1, by =  1, vertical = false },
  { side = "bottom", a = "BOTTOMLEFT",  b = "BOTTOMRIGHT", ax = -1, ay = -1, bx =  1, by = -1, vertical = false },
  { side = "left",   a = "TOPLEFT",     b = "BOTTOMLEFT",  ax = -1, ay =  1, bx = -1, by = -1, vertical = true  },
  { side = "right",  a = "TOPRIGHT",    b = "BOTTOMRIGHT", ax =  1, ay =  1, bx =  1, by = -1, vertical = true  },
}


-- Nothing here can be destroyed, so created-vs-live is the only view of it.
NS.stats = { containers = 0, textures = 0, rebuilds = 0 }

-- layer defaults to OVERLAY. A presence rule can now be placed in ARTWORK
-- instead when OVERLAY is full (see NS.PlaterSublevelPlan); everything else --
-- borders, the missing ladder -- stays in OVERLAY and simply omits the
-- argument. The layer is set at CREATION and never changed afterwards, which
-- is deliberate: nothing in this addon calls SetDrawLayer, so a texture's
-- layer is fixed for its lifetime and cannot drift out of step with the plan.
local function CreateBarTexture(owner, healthBar, sublayer, expand, layer)
  local tex = owner:CreateTexture(nil, layer or "OVERLAY", nil, sublayer or 0)
  NS.stats.textures = NS.stats.textures + 1
  return AnchorToFill(tex, healthBar, expand)
end

local function CreateMissingCoverTexture(owner, healthBar, sublayer, expand, layer)
  local tex = owner:CreateTexture(nil, layer or "OVERLAY", nil, sublayer or 0)
  NS.stats.textures = NS.stats.textures + 1
  return AnchorToMissingFill(tex, healthBar, expand)
end

-- Tileable patterns, white TGA masks; vertex colour tints them. Each carries
-- its native tile size: the isotropic ones tile both axes, the stripe banners
-- are one band already spanning a bar's height and must not tile vertically.
local TEXTURE_PATH = "Interface\\AddOns\\PlateTweaks\\media\\textures\\"

NS.FillTextures = {
  { key = "stripes-tiny",    label = "Stripes (Tiny)",           path = TEXTURE_PATH .. "stripes-tiny.tga",    tileW = 400, tileH = 48, tileVertical = false },
  { key = "stripes-close",   label = "Stripes (Small, Close)",   path = TEXTURE_PATH .. "stripes-close.tga",   tileW = 400, tileH = 48, tileVertical = false },
  { key = "stripes-spread",  label = "Stripes (Small, Spread)",  path = TEXTURE_PATH .. "stripes-spread.tga",  tileW = 400, tileH = 48, tileVertical = false },
  { key = "stripes-medium",  label = "Stripes (Medium)",         path = TEXTURE_PATH .. "stripes-medium.tga",  tileW = 400, tileH = 48, tileVertical = false },
  { key = "stripes-diag",    label = "Stripes (Diagonal)",       path = TEXTURE_PATH .. "stripes-diagonal.tga",tileW = 400, tileH = 48, tileVertical = false },
  { key = "stripes-wide",    label = "Stripes (Wide)",           path = TEXTURE_PATH .. "stripes-wide.tga",    tileW = 400, tileH = 48, tileVertical = false },
  { key = "dots",       label = "Dots",       path = TEXTURE_PATH .. "dots.tga",       tileW = 64, tileH = 64, tileVertical = true },
  { key = "chevron",    label = "Chevron",    path = TEXTURE_PATH .. "chevron.tga",    tileW = 64, tileH = 64, tileVertical = true },
  { key = "crosshatch", label = "Crosshatch", path = TEXTURE_PATH .. "crosshatch.tga", tileW = 64, tileH = 64, tileVertical = true },
  { key = "checker",    label = "Checker",    path = TEXTURE_PATH .. "checker.tga",    tileW = 64, tileH = 64, tileVertical = true },
}

function NS.FillTextureByKey(key)
  if not key then return nil end
  local index = fillCacheEnabled and fillCache.textureIndex
  if not index then
    index = {}
    for _, entry in ipairs(NS.FillTextures) do index[entry.key] = entry end
    if fillCacheEnabled then fillCache.textureIndex = index end
  end
  return index[key]
end

-- LSM bar textures for the Solid overlay. Its own field, not fillTexture --
-- the two overlays are choices a rule holds at once. Drawn to be stretched
-- across a bar once, so ApplyRuleFill anchors it to the fill.

-- Nil also covers "the media pack is uninstalled", which must degrade to a
-- flat colour rather than error on every plate.
function NS.BarTexturePath(name)
  if type(name) ~= "string" or name == "" then return nil end
-- false is the miss marker; nil cannot be told from "not looked up yet".
  local paths = fillCache.barPaths
  if not paths then paths = {}; fillCache.barPaths = paths end
  local cached = fillCacheEnabled and paths[name]
  if cached ~= nil and cached ~= false then return cached end
  if fillCacheEnabled and cached == false then return nil end

  local LSM = NS.LSM
  if not LSM then return nil end
  local ok, path = pcall(LSM.Fetch, LSM, "statusbar", name, true)
  local resolved = (ok and type(path) == "string") and path or false
  paths[name] = resolved
  return resolved or nil
end

function NS.LSMStatusbars()
  local LSM = NS.LSM
  if not LSM then return {} end
  local okList, names = pcall(LSM.List, LSM, "statusbar")
  if not okList or type(names) ~= "table" then return {} end
  local out = {}
  for _, name in ipairs(names) do
    local okPath, path = pcall(LSM.Fetch, LSM, "statusbar", name, true)
    if okPath and type(path) == "string" then
      table.insert(out, { name = name, path = path })
    end
  end
  table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
  return out
end

-- Opaque white rect used as a MASK, so the crop is exactly its anchored rect.
--
-- Created on tex's own owner: a mask made on one aura button and used on
-- another's texture is refused once auras are secret. Anchored with no inset --
-- intersecting a tighter rect with a looser one yields the tighter.
local function EnsureOwnFillMask(tex, healthBar)
  local mask = tex.ptFillMask
  if not mask then
    local host = tex:GetParent()
    mask = host:CreateMaskTexture(nil, "OVERLAY")
-- No wrap args: always a flat 1:1 rect, and MaskTexture's SetTexture does not
-- necessarily take a plain Texture's argument shape.
    mask:SetTexture("Interface\\Buttons\\WHITE8X8")
    NS.stats.textures = NS.stats.textures + 1
    tex.ptFillMask = mask
  end
  local fill = healthBar:GetStatusBarTexture()
  if fill then
    mask:ClearAllPoints()
    mask:SetPoint("TOPLEFT", fill, "TOPLEFT", 0, 0)
    mask:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
  end
  return mask
end

local function SetFillMasked(tex, healthBar, masked)
  if masked then
    if tex.ptFillMasked then return end
    local ok = pcall(function()
      tex:AddMaskTexture(EnsureOwnFillMask(tex, healthBar))
    end)
    if ok then tex.ptFillMasked = true end
  elseif tex.ptFillMasked and tex.ptFillMask then
    pcall(tex.RemoveMaskTexture, tex, tex.ptFillMask)
    tex.ptFillMasked = false
  end
end

-- Paints a rule's bar tint. Solid anchors to the fill; a library pattern
-- anchors to the bar frame and is cropped by a mask; otherwise the host bar's
-- own art is copied. Every branch re-anchors and re-masks unconditionally --
-- fillStyle is a Live change, so one object swaps between all three.
local function ApplyRuleFill(tex, healthBar, rule, expand)
  local color = rule and rule.color or NS.DefaultColor()

  if rule and rule.fillStyle ~= "texture" then
    local barPath = NS.BarTexturePath(rule.barTexture)
    if barPath then
      local ok = pcall(function()
        tex:SetTexture(barPath)
-- Reset: this object may have been tiling a pattern a moment ago.
        tex:SetTexCoord(0, 1, 0, 1)

        AnchorToFill(tex, healthBar, expand)
        SetFillMasked(tex, healthBar, false)

        tex:SetVertexColor(color.r, color.g, color.b)
        tex:SetAlpha(color.a or 1)
      end)
      if ok then tex.ptTexturedFill = true return end
    end
  end

  if rule and rule.fillStyle == "texture" then
    local library = NS.FillTextureByKey(rule.fillTexture)
    if library then
      local ok = pcall(function()
-- Tiling args are booleans, not strings.
        tex:SetTexture(library.path, true, true)
        local okW, w = pcall(healthBar.GetWidth, healthBar)
        local okH, h = pcall(healthBar.GetHeight, healthBar)
        local repX = math.max(1, (okW and w or 100) / library.tileW)
        local repY
        if library.tileVertical then
          repY = math.max(1, (okH and h or 10) / library.tileH)
        else
-- One full span, not a repeat count under 1 -- a fractional vMax samples a
-- cropped sliver and stretches that.
          repY = 1
        end
        tex:SetTexCoord(0, repX, 0, repY)

        AnchorToBarFrame(tex, healthBar, expand)
        SetFillMasked(tex, healthBar, true)

        tex:SetVertexColor(color.r, color.g, color.b)
        tex:SetAlpha(color.a or 1)
      end)
      if ok then tex.ptTexturedFill = true return end
    else
      local ok = pcall(function()
        local fill = healthBar:GetStatusBarTexture()
        if not fill then error("no fill texture") end

        local atlas
        if fill.GetAtlas then
          local okAtlas, value = pcall(fill.GetAtlas, fill)
          if okAtlas then atlas = value end
        end

        if atlas then
          tex:SetAtlas(atlas)
        elseif fill.GetTexture then
          local okTex, path = pcall(fill.GetTexture, fill)
          if not (okTex and type(path) == "string") then error("no texture path") end
          tex:SetTexture(path)
        else
          error("no usable texture")
        end

        if not atlas and fill.GetTexCoord then
          local okCoord, a1, a2, a3, a4, a5, a6, a7, a8 = pcall(fill.GetTexCoord, fill)
          if okCoord and a1 then tex:SetTexCoord(a1, a2, a3, a4, a5, a6, a7, a8) end
        end

        AnchorToFill(tex, healthBar, expand)
        SetFillMasked(tex, healthBar, false)

        tex:SetVertexColor(color.r, color.g, color.b)
        tex:SetAlpha(color.a or 1)
      end)
      if ok then tex.ptTexturedFill = true return end
    end
  end
  AnchorToFill(tex, healthBar, expand)
  SetFillMasked(tex, healthBar, false)
  tex:SetVertexColor(1, 1, 1)
  tex:SetColorTexture(color.r, color.g, color.b, color.a)
-- What the texture was actually painted as, not what the rule asked for.
-- Recolouring a flat SetColorTexture through SetVertexColor silently does
-- nothing, and the picker looks dead.
  tex.ptTexturedFill = false
end
NS.ApplyRuleFill = ApplyRuleFill

-- Cheap recolour: the picker fires every frame you drag it, across every tint
-- on every rig.
local function ApplyRuleColor(tex, rule)
  local color = rule and rule.color or NS.DefaultColor()
  local textured = tex.ptTexturedFill
  if textured == nil then
    textured = rule and rule.fillStyle == "texture"
  end
  if textured then
    tex:SetVertexColor(color.r, color.g, color.b)
    tex:SetAlpha(color.a or 1)
  else
    tex:SetVertexColor(1, 1, 1)
    tex:SetColorTexture(color.r, color.g, color.b, color.a)
  end
end
NS.ApplyRuleColor = ApplyRuleColor

function NS.MissingCoverColor()
  return (NS.db and NS.db.tints and NS.db.tints.missingCoverColor)
    or { r = 0.08, g = 0.08, b = 0.08, a = 0.95 }
end

-- One-shot missing cover for Test Mode and the preview. Flat colour, not a
-- copy of the fill -- a copy read as "still full health".
function NS.ApplyMissingCover(tex, healthBar, rule, expand)
  if not (rule and rule.missingCover) then
    tex:Hide()
    return
  end

  AnchorToMissingFill(tex, healthBar, expand)
  local c = NS.MissingCoverColor()
  tex:SetColorTexture(c.r, c.g, c.b, c.a)
  tex:Show()
end

local function BuildRule(rig, healthBar, rule, level, needsUnderlay, overdraw, tintSublevel, underlaySublevel, borderSublevel, missingCoverSublevel, tintLayer)
  tintSublevel = tintSublevel or 0
  underlaySublevel = underlaySublevel or -1
  borderSublevel = borderSublevel or 7
-- Strictly above the tint: the mask can leave a sliver at the live edge.
  missingCoverSublevel = missingCoverSublevel or (tintSublevel + 2)
-- Which layer this rule's own pieces live in. All four -- underlay, tint,
-- flash, cover -- share it, so their +1/-1 relationships hold. Only the
-- BORDER stays in OVERLAY, since it is placed against the host's border band
-- rather than against this rule's tint.
  tintLayer = tintLayer or "OVERLAY"
  local record = {
    rule = rule,
    containers = {},
    tints = {},
    underlays = {},
    missingCovers = {},
    borders = {},
    pandemics = {},
    hosts = {},    -- buttons of the first debuff; display/count only
    tintHosts = {}, -- buttons that actually carry the tints (see initializeFrame)
    built = {},    -- combinations already created (marked only on success)
    failures = 0,
    truncated = false,
    dirty = true,  -- new buttons arrived; the pump has pairing to do
    level = level,
    overdraw = overdraw or 0,
  }

  local spells = {}
  for _, condition in ipairs(rule.conditions or {}) do
    table.insert(spells, condition.spellID)
  end
  if #spells == 0 then return record end
  if #spells > NS.MAX_RULE_CONDITIONS then
    record.unsupported = true
    return record
  end

-- Flagged, not silently skipped, so the options panel can say why.
  if rule.barEnabled == false and not (rule.border and rule.border.enabled) then
    record.inert = true
    return record
  end

  record.spellCount = #spells

-- Split out of the pump so it can also run inside initializeFrame, where the
-- aura button is still touchable.
  local function BuildCombination(stack)
    local host = stack[1]

-- Underlay: opaque copy of the bar, so this rule masks lower ones. Only when
-- a lower rule can match, and only when this rule paints the bar.
    if needsUnderlay and record.rule.barEnabled ~= false then
      local underlay = CreateBarTexture(host, healthBar, underlaySublevel, UNDERLAY_OVERDRAW + record.overdraw, tintLayer)
      for index = 2, #stack do underlay:AddMaskTexture(stack[index]) end
      table.insert(record.underlays, underlay)
    end
    if record.rule.barEnabled ~= false then
      local tint = CreateBarTexture(host, healthBar, tintSublevel, record.overdraw, tintLayer)
      ApplyRuleFill(tint, healthBar, record.rule, record.overdraw)
      for index = 2, #stack do tint:AddMaskTexture(stack[index]) end
      table.insert(record.tints, tint)
    end

    -- Shared missing colour, not a copy of the fill. Strictly above the
    -- tint's sublevel -- the mask can leave a sliver whose winner would
    -- otherwise be undefined.
    if record.rule.barEnabled ~= false and record.rule.missingCover then
      local cover = CreateMissingCoverTexture(host, healthBar, missingCoverSublevel, record.overdraw, tintLayer)
      local mc = NS.MissingCoverColor()
      cover:SetColorTexture(mc.r, mc.g, mc.b, mc.a)
      for index = 2, #stack do cover:AddMaskTexture(stack[index]) end
      table.insert(record.missingCovers, cover)
    end

    -- Textures, not a BackdropTemplate frame: a frame parented to an aura
    -- button is silently refused, and textures are maskable where frames are
    -- not.
    local border = record.rule.border
    if border and border.enabled then
      local bc = border.color or { r = 1, g = 1, b = 1, a = 1 }
      local t = math.max(1, math.min(8, border.thickness or 2))
      local pad = math.max(0, math.min(12, border.padding or 0))
      -- Growing out must clear its own thickness as well as the padding.
      local out = (border.grow == "OUT") and (t + pad) or -pad

      for _, side in ipairs(BORDER_SIDES) do
        -- Top of OVERLAY; one lower on a Plater bar, where 7 is its name text.
        local tex = host:CreateTexture(nil, "OVERLAY", nil, borderSublevel)
        NS.stats.textures = NS.stats.textures + 1
        tex:SetColorTexture(bc.r, bc.g, bc.b, bc.a)
        tex:SetPoint(side.a, healthBar, side.a, side.ax * out, side.ay * out)
        tex:SetPoint(side.b, healthBar, side.b, side.bx * out, side.by * out)
        if side.vertical then tex:SetWidth(t) else tex:SetHeight(t) end
        for index = 2, #stack do tex:AddMaskTexture(stack[index]) end
        table.insert(record.borders, tex)
      end
    end

    -- AddPandemicRegion reveals a region only inside the refresh window -- no
    -- duration read. Single-debuff only: it doubles a rule's texture count.
    local pandemic = NS.db.tints.pandemic
    if pandemic and pandemic.enabled and record.spellCount == 1 and host.AddPandemicRegion then
      local pc = pandemic.color or { r = 1, g = 1, b = 1, a = 0.45 }
      local region

    -- AddPandemicRegion only shows and hides, so the pulse is our own looping
    -- alpha animation on a frame we own.
      if pandemic.pulse ~= false then
        pcall(function()
          local f = CreateFrame("Frame", nil, host)
          f:SetAllPoints(healthBar)
          local tex = f:CreateTexture(nil, "OVERLAY")
          tex:SetColorTexture(pc.r, pc.g, pc.b, pc.a)
          AnchorToFill(tex, healthBar)
          for index = 2, #stack do tex:AddMaskTexture(stack[index]) end

          local ag = f:CreateAnimationGroup()
          ag:SetLooping("BOUNCE")
          local fade = ag:CreateAnimation("Alpha")
          fade:SetFromAlpha(1)
          fade:SetToAlpha(0.1)
          fade:SetDuration(pandemic.pulseSpeed or 0.35)
          ag:Play()
          region = f
        end)
      end

      if not region then
        local flash = CreateBarTexture(host, healthBar, tintSublevel + 1, nil, tintLayer)
        flash:SetColorTexture(pc.r, pc.g, pc.b, pc.a)
        for index = 2, #stack do flash:AddMaskTexture(stack[index]) end
        region = flash
      end

      region:Hide()
      host:AddPandemicRegion(region)
      table.insert(record.pandemics, region)
    end
  end

  -- One container per debuff, nested inside a button of the one before it;
  -- tint on the last link, so ancestry is the AND. Cost is containers^depth --
  -- two debuffs is 11 containers and 100 tints per plate, three is 111.
  local AttachContainer

  AttachContainer = function(parent, depth)
    local okFrame, frame = pcall(CreateFrame, "AuraContainer", nil, parent, "CustomAuraContainerTemplate")
    if not okFrame or not frame then
      NS.NoteContainerRefused()
      record.failures = record.failures + 1
      record.lastError = record.lastError or ("container at depth " .. depth .. ": " .. tostring(frame))
      return
    end

    NS.stats.containers = NS.stats.containers + 1

    frame:SetEnabled(false)
    -- To the health bar, never the parent button: ours-to-theirs is refused.
    pcall(frame.SetAllPoints, frame, healthBar)

    local key = "M" .. depth
    local useSlot = SlotsAvailable(frame)
    local Register = useSlot and frame.AddAuraSlot or frame.AddAuraGroup
    Register(frame, key, "HARMFUL|PLAYER", {
      initializeFrame = function(button)
        if depth == 1 then
          table.insert(record.hosts, button)
        end
        -- Every depth: BuildCombination attaches to the deepest button.
        --
        -- ACCEPTED here even in combat, measured on a live plate: this is the
        -- button's own initializeFrame callback, the one place a forbidden
        -- object may be touched. The "refused while auras are secret" note that
        -- used to sit here is true of the re-level pass in AnchorTints, which
        -- reaches buttons from OUTSIDE any callback -- do not generalise it to
        -- this line.
        --
        -- The result is RECORDED, because it cannot be recovered later: in
        -- combat the button's own frame level and strata both read back as
        -- secret, so "did flat-pinning take?" is unanswerable after the fact --
        -- and out of combat the re-level pass has already repaired it, so the
        -- answer is always yes by the time anyone can look. This callback is
        -- the only moment the truth is observable, and a plain counter is
        -- carried out of it.
        --
        -- It matters because when this call fails the button keeps the higher
        -- level its container gave it, frame level then beats draw layer, and
        -- the tint draws over the host's border and name whatever sublevel it
        -- was assigned.
        -- record.level, NOT the captured `level`. The upvalue is the level this
        -- plate had when the rig was BUILT; record.level is what it should be
        -- now, and both AnchorTints and RepinLevels keep it current.
        --
        -- Plater raises a plate by 5000 the instant it becomes your target.
        -- RepinLevels then re-levels the containers, which accept, and the aura
        -- buttons, which do not: a bound button takes a level only inside this
        -- callback. So the container moved to 5051 while the button carrying
        -- the tint stayed at 51 -- frame level beats draw layer, and the bar's
        -- own fill covered the tint at every sublevel.
        --
        -- Measured over one session: 73 drift events, 69 deferred, 276 refused
        -- frames, 4 successful re-pins -- and all 4 were out of combat.
        --
        -- Reading the current level here lets a pooled button correct itself
        -- the next time it is initialised, inside the one callback the engine
        -- allows, instead of waiting for combat to end.
        local okLevel = pcall(button.SetFrameLevel, button, record.level or level)
        if okLevel then
          record.levelSet = (record.levelSet or 0) + 1
          -- This IS the repair, so record it. rig.appliedLevel previously only
          -- advanced when a full external re-pin succeeded, which stopped
          -- happening once buttons started fixing themselves here -- leaving
          -- the field permanently stale and every diagnostic reading off it
          -- crying failure over work that had already been done. Measured at
          -- an 88% false positive rate against the buttons' real levels.
          --
          -- rig.baseLevel, not record.level: record.level carries this rule's
          -- own offset, while appliedLevel is compared against the bar.
          if rig.baseLevel then rig.appliedLevel = rig.baseLevel end
        else
          record.levelRefused = (record.levelRefused or 0) + 1
        end
        record.dirty = true

        if depth < record.spellCount then
      -- Must hang off EVERY pooled button -- the engine displays an arbitrary
      -- one, and a chain missing from the one it picks fails silently.
          AttachContainer(button, depth + 1)
          return
        end

        record.combos = (record.combos or 0) + 1
        if record.combos >= MAX_TINTS_PER_RULE then
          record.truncated = true
          return
        end
        table.insert(record.tintHosts, button)
        local okBuild, errBuild = pcall(BuildCombination, { button })
        if not okBuild then
          record.failures = record.failures + 1
          record.lastError = record.lastError or tostring(errBuild)
        end
      end,
    })

      -- Also every linked ID: an ability whose aura is a separate spell would
      -- filter on an ID that never lands.
    local spellID = spells[depth]
    local ids = (NS.RelatedSpellIDs and NS.RelatedSpellIDs(spellID)) or { [spellID] = true }
    if useSlot then
      frame:SetAuraSlotCandidateFilters(key, { includeSpellIDs = ids })
    else
      frame:SetAuraGroupCandidateFilters(key, { includeSpellIDs = ids })
      frame:SetAuraGroupMaxFrameCount(key, 1)
    end

    -- Only the depth-1 container is a child of the HEALTH BAR and therefore
    -- ours to show and hide. Deeper links are children of aura buttons, where
    -- Show is refused -- see NS.RetireTints.
    frame.ptRootContainer = (depth == 1)
    table.insert(record.containers, frame)
    NS.ActivateContainer(rig, frame, record)
  end

  AttachContainer(healthBar, 1)

  return record
end

-- Fill-path benchmark: times ApplyRuleFill over N textures on a synthetic bar.
-- Measures our own Lua, not the client's cost inside SetPoint. Frame and
-- textures are created once -- nothing here can be destroyed.
local benchBar, benchTextures

local function EnsureBench(count)
  if not benchBar then
    benchBar = CreateFrame("StatusBar", nil, UIParent)
    benchBar:SetSize(120, 12)
    benchBar:SetStatusBarTexture("Interface\Buttons\WHITE8X8")
    benchBar:SetMinMaxValues(0, 1)
    benchBar:SetValue(0.72)
    benchBar:Hide() -- never drawn; it exists to be measured against
    benchTextures = {}
  end
  for index = #benchTextures + 1, count do
    benchTextures[index] = benchBar:CreateTexture(nil, "OVERLAY")
  end
  return benchTextures
end

function NS.BenchFillPath(count, iterations, rule)
  count = math.max(1, count or 100)
  iterations = math.max(1, iterations or 20)
  rule = rule or (NS.db and NS.db.tints and NS.db.tints.rules and NS.db.tints.rules[1])
  if not rule then return nil, "no rule to measure -- create one first" end

  local textures = EnsureBench(count)
  for index = 1, count do
    pcall(ApplyRuleFill, textures[index], benchBar, rule, 0)
  end

  local start = debugprofilestop()
  for _ = 1, iterations do
    for index = 1, count do
      ApplyRuleFill(textures[index], benchBar, rule, 0)
    end
  end
  return debugprofilestop() - start
end

function NS.BuildTints(rig, healthBar)
  rig.rules = {}

  local okW, w = pcall(healthBar.GetWidth, healthBar)
  local okH, h = pcall(healthBar.GetHeight, healthBar)
  rig.barWidth = okW and w or 100
  rig.barHeight = okH and h or 10

  local isPlater = NS.IsPlaterBar(healthBar)
  local platerTextFloor = isPlater and NS.PlaterTextFloor(healthBar) or nil

  -- Opt-in, gated on positive evidence: being wrong means a rule silently
  -- stops working. Only affects what gets built.
  local function Castable(list)
    if not NS.db.tints.gateUnknownSpells then return list end
    local kept = {}
    for _, rule in ipairs(list) do
      local ok = true
      for _, condition in ipairs(rule.conditions or {}) do
        if NS.CanApplyAura and not NS.CanApplyAura(condition.spellID) then ok = false break end
      end
      if ok then kept[#kept + 1] = rule end
    end
    return kept
  end

  -- Split out first, or one consumes a frame-level band and a rank-inset step
  -- for geometry it never uses.
  local candidates = NS.db.tints.enabled and Castable(NS.GetOrderedRules()) or {}
  local ordered, missingRules = {}, {}
  for _, rule in ipairs(candidates) do
    if rule.showWhenMissing then
      missingRules[#missingRules + 1] = rule
    else
      ordered[#ordered + 1] = rule
    end
  end
  local count = #ordered

  -- Presence starts one band above the base. The missing wash is lit by
  -- default, so on top it covered presence tints almost always.
  local ruleBase = isPlater and rig.baseLevel or (rig.baseLevel + LEVELS_PER_RULE)

  -- Inset as a ladder, not a flat step: a rule only has to be smaller than a
  -- higher one that can be lit at the same time and does NOT cover it. Most
  -- rules sit flush; only disjoint rules step down, and only past each other.
  local insets = {}
  for index, rule in ipairs(ordered) do
    local inset = 0
    for higher = 1, index - 1 do
      if not NS.RuleCovers(ordered[higher], rule) then
        inset = math.max(inset, (insets[higher] or 0) + RANK_INSET)
      end
    end
    insets[index] = math.min(RANK_INSET_MAX, inset)
  end

  -- Derived here rather than further down, because on a flat-pinned bar the
  -- ladder competes for the SAME draw sublevels as the presence rules and has
  -- to claim its slots before they are handed out.
  --
  -- Single-debuff only: rank k already spends a chain level per rule above it,
  -- and a second condition needs another with no room for it.
  local ladder = {}
  for _, rule in ipairs(missingRules) do
    if #(rule.conditions or {}) == 1 and #ladder < NS.MAX_MISSING_RULES then
      ladder[#ladder + 1] = rule
    end
  end

  -- Allocated once for the whole ladder, up front: what sublevel a rule gets
  -- depends on what the rules ABOVE it consumed, which cannot be decided one
  -- rule at a time the way a fixed three-per-rank could.
  local plan
  rig.missingSublevels = nil
  if isPlater then
    local pandemicOn = (NS.db.tints.pandemic or {}).enabled and true or false
    -- ONE occupancy map, shared. The survey is what turns this from arithmetic
    -- into a measurement: the host's own textures are read off the bar, so the
    -- ceiling and the free slots are per bar instead of assumed per adapter.
    --
    -- The ceiling is taken BEFORE anything of ours is marked, or our own
    -- reservations would drag it down and move the border band with it.
    local occ = NS.HostOccupancy(healthBar)
    local ceiling = NS.OverlayCeiling(occ)
    -- Missing ladder first: it marks its slots taken, so the presence
    -- allocator below can no longer be handed the same ones.
    rig.missingSublevels =
      NS.PlaterMissingPlan(occ, #ladder, MissingModeIsDisplace(), ceiling)
    plan, rig.sublevelStarved =
      NS.PlaterSublevelPlan(ordered, platerTextFloor, pandemicOn, healthBar,
        occ, ceiling)
  end

  for index, rule in ipairs(ordered) do
    -- Plater pins every rule to one level, so rank becomes a sublevel.
    local level, tintSublevel, underlaySublevel, missingCoverSublevel
    local entry = plan and plan[index]
    if isPlater then
      level = rig.baseLevel
      tintSublevel = entry.tint
      underlaySublevel = entry.underlay
      missingCoverSublevel = entry.cover
    else
      level = ruleBase + (count - index) * LEVELS_PER_RULE
    end
    -- Needed only when a lower rule's debuffs are a subset of this one's.
    -- Taken from the plan where there is one: the allocator already decided
    -- this to size the rule, and recomputing it here could disagree, which
    -- would put a texture on a sublevel nothing reserved.
    local needsUnderlay
    if entry then
      needsUnderlay = entry.needsUnderlay
    else
      needsUnderlay = false
      for lower = index + 1, count do
        if NS.RuleCovers(rule, ordered[lower]) then needsUnderlay = true break end
      end
    end
    -- Insets exist because frame level cannot arbitrate between two rules that
    -- can be lit at once and do not cover each other. On a flat-pinned bar
    -- draw sublevel does arbitrate, so the shrink buys nothing and costs up to
    -- a pixel off every tint.
    local overdraw = isPlater and 0 or -(insets[index] or 0)
    local record = BuildRule(rig, healthBar, rule, level, needsUnderlay, overdraw,
      tintSublevel, underlaySublevel, isPlater and (platerTextFloor - 1) or nil,
      missingCoverSublevel, entry and entry.layer or nil)
    -- Replayed by NS.AnchorTints. Stored, not recomputed, so they cannot
    -- disagree.
    record.levelOffset = level - rig.baseLevel
    -- Same reason, and now load-bearing: /pt layers used to re-derive these
    -- from the rule's index, which stopped being possible the moment
    -- allocation depended on what earlier rules asked for.
    record.tintLayer = entry and entry.layer or "OVERLAY"
    record.tintSublevel = tintSublevel
    record.underlaySublevel = underlaySublevel
    record.missingCoverSublevel = missingCoverSublevel
    record.needsUnderlay = needsUnderlay
    table.insert(rig.rules, record)
  end

  -- Counted separately from the per-rule drops below. With the module off the
  -- rules never reach the partition at all, so every counter there stayed 0
  -- and /pt status said nothing -- the exact "silently does nothing" case the
  -- other warnings exist to prevent.
  local borderModuleOff = NS.db.tints.borderEnabled == false
  rig.borderRulesOff = borderModuleOff and #(NS.GetOrderedBorderRules() or {}) or 0
  local allBorders = (not borderModuleOff)
    and Castable(NS.GetOrderedBorderRules()) or {}

  -- Missing borders split off too, and exist in displacement mode only --
  -- there is no replica to make of whatever the host drew under the band.
  local borders, missingBorders = {}, {}
  for _, rule in ipairs(allBorders) do
    if rule.showWhenMissing then
      missingBorders[#missingBorders + 1] = rule
    else
      borders[#borders + 1] = rule
    end
  end
  -- Dropped rather than built as presence borders, which would light them at
  -- exactly the wrong times. Counted for /pt status.
  rig.missingBorderSkipped = 0
  rig.missingBorderIncomplete = 0
  if not MissingModeIsDisplace() then
    rig.missingBorderSkipped = #missingBorders
    missingBorders = {}
  else
    -- Before the cap, not after: trimming first let an unbuildable rule occupy
    -- a slot and evict a working one, then blamed the budget.
    local buildable = {}
    for _, rule in ipairs(missingBorders) do
      local condition = (rule.conditions or {})[1]
      if condition and rule.border and rule.border.enabled then
        buildable[#buildable + 1] = rule
      else
        rig.missingBorderIncomplete = rig.missingBorderIncomplete + 1
      end
    end
    missingBorders = buildable
    while #missingBorders > NS.MAX_MISSING_BORDER_RULES do
      table.remove(missingBorders)
      rig.missingBorderSkipped = rig.missingBorderSkipped + 1
    end
  end

  local bcount = #borders
  local borderBase = isPlater and rig.baseLevel or (ruleBase + (count + 1) * LEVELS_PER_RULE)
  for index, rule in ipairs(borders) do
    local level = isPlater and rig.baseLevel or (borderBase + (bcount - index) * LEVELS_PER_RULE)
    local record = BuildRule(rig, healthBar, rule, level, false, nil, nil, nil, isPlater and (platerTextFloor - 1) or nil)
    record.levelOffset = level - rig.baseLevel
    table.insert(rig.rules, record)
  end

  -- Rank 1's wash first, so the cover has something underneath it. The ladder
  -- sits below every presence rule; covers live on aura buttons whose secret
  -- strata beats frame level, so a cover always wins over the wash it hides.
  -- TOP of the missing band, not the bottom.
  --
  -- The band is baseLevel .. ruleBase-1 and only ever held one thing, which
  -- was pinned to the floor of it. That put the lowest thing we draw one level
  -- above the health bar and nothing else -- so a host frame sitting just over
  -- its own bar covered the missing wash while every presence rule, a full
  -- band higher, kept working. A missing reminder that silently never lights.
  --
  -- Using the top of the band is free: still below every presence rule, so our
  -- own ordering is unchanged, but now clear of anything hugging the bar.
  -- Plater keeps the floor -- it is pinned flat, so its ranks are separated by
  -- draw sublevel and this number does not arbitrate anything there.
  local missingLevel = isPlater and rig.baseLevel or (rig.baseLevel + LEVELS_PER_RULE - 1)
  -- Before BuildMissingWash, which reads it for the opening state.
  rig.missingLadder = ladder
  -- Cleared first, so a rebuild dropping to zero rules does not leave the gate
  -- or the poll working off the last one.
  rig.missingGateOpen = nil
  rig.missingLadderRecord = nil
  rig.missingDisplace = nil
  if MissingModeIsDisplace() then
    NS.BuildMissingDisplace(rig, healthBar, ladder, missingLevel)
    -- Same entry list: a border entry differs only in which textures ride the
    -- mask. One band below the presence borders.
    NS.BuildMissingBorderDisplace(rig, healthBar, missingBorders,
      isPlater and rig.baseLevel or (borderBase - LEVELS_PER_RULE),
      isPlater and (platerTextFloor - 1) or 7)
  else
    NS.BuildMissingWash(rig, healthBar, missingLevel, ladder[1])
    if #ladder > 0 then
      local record = NS.BuildMissingBarStack(rig, healthBar, ladder, missingLevel)
      record.levelOffset = missingLevel - rig.baseLevel
      table.insert(rig.rules, record)
      -- Direct reference for the gate, which needs the root every poll tick.
      rig.missingLadderRecord = record
    end
  end
  rig.missingLevelOffset = missingLevel - rig.baseLevel

  -- Settle now, or a ladder that should open closed is briefly lit on every
  -- plate that spawns mid-pull.
  NS.UpdateMissingCombatGate(rig)

  rig.outlineLevelOffset = isPlater and 0
    or ((borderBase - rig.baseLevel) + (bcount + 1) * LEVELS_PER_RULE)
  NS.BuildOutline(rig, healthBar, rig.baseLevel + rig.outlineLevelOffset)
end

-- The plate border is unconditional, so it does not belong on an aura button:
-- one frame per plate, four edges, above every tint. Also covers the rank
-- inset.


-- LADDER-WIDE, forced: only one wash is ever lit and which one depends on
-- aura state we may not read. Engages only when every rule asks for it, and a
-- mixed ladder fails toward SHOWING.
-- "Am I fighting this mob?"
--
-- UnitAffectingCombat(unit) alone was too strict. It reports the MOB's own
-- combat flag, which plenty of things you are actively fighting never set:
-- a mob dotted at range before it aggros, an add on someone else's threat
-- that has not engaged, scripted or immune mobs, training dummies. On those
-- the gate stayed shut and the reminder never lit -- the "enemies without
-- threat show no combat rules" report.
--
-- Threat closes the gap without opening it too far: being on a mob's threat
-- table means you have touched it, which is exactly the population a missing
-- reminder is for. A mob standing untouched across the room has neither flag
-- and still stays dark, which is the whole point of the option.
--
-- UnitThreatSituation is a readable carve-out in instances, same as
-- UnitAffectingCombat, so this costs nothing in a key. pcall anyway: it is
-- called at 4Hz on every rigged plate and a throw here kills the ticker.
function NS.UnitEngaged(unit)
  if not unit then return false end
  if not UnitAffectingCombat("player") then return false end
  if UnitAffectingCombat(unit) then return true end
  local ok, threat = pcall(UnitThreatSituation, "player", unit)
  if ok and threat ~= nil and not (issecretvalue and issecretvalue(threat)) then
    return true
  end
  return false
end

local function LadderCombatAllows(rig)
  local ladder = rig and rig.missingLadder
  if not ladder or #ladder == 0 then return true end
  for _, rule in ipairs(ladder) do
    if not rule.missingCombatOnly then return true end
  end
  return NS.UnitEngaged(rig.unit)
end
NS.LadderCombatAllows = LadderCombatAllows

-- From the 0.25s poll in Core.lua.
--
-- Must NOT touch the deep washes. They are textures on secure aura buttons --
-- creating one inside initializeFrame is fine, SetShown later is refused:
--
--   calling 'SetShown' on bad self (Attempt to access forbidden object
--   from code tainted by an AddOn)
--
-- Enablement of a container we created is not reserved, so the gate disables
-- the ROOT and the chain goes with it.
function NS.UpdateMissingCombatGate(rig)
  -- Displacement gates per rule: each owns a holder frame that is ours.
  local displace = rig.missingDisplace
  if displace then
    local unit = rig.unit
    local inCombat = NS.UnitEngaged(unit)
    for _, entry in ipairs(displace.entries or {}) do
      local allow = (not entry.rule.missingCombatOnly) or inCombat
      if entry.allowed ~= allow then
        entry.allowed = allow
        entry.holder:SetShown(allow)
      end
    end
    return
  end

  local allowed = LadderCombatAllows(rig)
  -- Edge-triggered: 4Hz on every rigged plate.
  if rig.missingGateOpen == allowed then return end
  rig.missingGateOpen = allowed

  local frame = rig.missingWash
  if frame and frame.wash then
    frame.wash:SetShown(allowed)
  end

  local record = rig.missingLadderRecord
  local root = record and record.root
  if not root then return end

  -- Visibility first: hiding neither tears the chain down nor re-runs
  -- initializeFrame. The root's parent is the health bar, not an aura button,
  -- so it is worth trying rather than assuming refused.
  if record.gateLever ~= "enabled" then
    if pcall(root.SetShown, root, allowed) then
      record.gateLever = "shown"
  -- Visibility does the gating, so the container must stay bound and enabled.
      NS.ActivateContainer(rig, root, record)
      return
    end
    record.gateLever = "enabled"
  end

  -- Fallback: re-initialises the buttons, so it leans on the guard above.
  if allowed then
    -- Through ActivateContainer: the unit binding and target/focus opt-outs
    -- have to be re-applied.
    NS.ActivateContainer(rig, root, record)
  else
    root:SetEnabled(false)
  end
end

-- Rank 1's wash -- unconditional, so it cannot live on an aura button. Kept on
-- the health bar, not the rig, so it caps at one per plate.
function NS.BuildMissingWash(rig, healthBar, level, topRule)
  local frame = healthBar.ptMissingWash
  if not frame then
    frame = CreateFrame("Frame", nil, healthBar)
    healthBar.ptMissingWash = frame
  end
  rig.missingWash = frame
  frame:SetAllPoints(healthBar)
  pcall(frame.SetFrameLevel, frame, level)

  -- Test mode draws its own copy. A missing wash is lit BECAUSE nothing is
  -- applied, so it would read as a test wash that will not clear. Suppressed
  -- on every plate, not just the ones test mode covers.
  if not topRule or (NS.TestModeActive and NS.TestModeActive()) then
    frame:Hide()
    return
  end

  local tex = frame.wash
  if not tex then
    tex = frame:CreateTexture(nil, "OVERLAY", nil,
      MissingSub(rig, 1, "wash", MissingWashSublevel(1)))
    NS.stats.textures = NS.stats.textures + 1
    frame.wash = tex
  end
  ApplyRuleFill(tex, healthBar, topRule, 0)
  tex:SetShown(LadderCombatAllows(rig))
  frame:Show()
end

-- The ladder. One record for all of it -- the containers are a single nested
-- structure and cannot be enabled or retired independently.
function NS.BuildMissingBarStack(rig, healthBar, rules, level)
  local record = {
    rule = rules and rules[1],
    missingStack = rules or {},
    containers = {}, tints = {}, underlays = {}, missingCovers = {},
    borders = {}, pandemics = {},
    hosts = {}, tintHosts = {}, built = {},
    washes = {},
    -- Must hide its wash completely, or a leftover rim never goes away.
    failures = 0, level = level, overdraw = MISSING_COVER_OVERDRAW,
  }
  if not rules or #rules == 0 then return record end

  local AttachLevel
  AttachLevel = function(parent, rank)
    local rule = rules[rank]
    if not rule then return end
    local condition = (rule.conditions or {})[1]
    if not condition then return end

    local okFrame, frame = pcall(CreateFrame, "AuraContainer", nil, parent,
      "CustomAuraContainerTemplate")
    if not okFrame or not frame then
      NS.NoteContainerRefused()
      record.failures = record.failures + 1
      record.lastError = record.lastError
        or ("missing ladder at rank " .. rank .. ": " .. tostring(frame))
      return
    end
    NS.stats.containers = NS.stats.containers + 1

    frame:SetEnabled(false)
    pcall(frame.SetAllPoints, frame, healthBar)

    local key = "N" .. rank
    local useSlot = SlotsAvailable(frame)
    local Register = useSlot and frame.AddAuraSlot or frame.AddAuraGroup
    Register(frame, key, "HARMFUL|PLAYER", {
      initializeFrame = function(button)
        -- Fires more than once per button: the engine re-initialises when a
        -- container is re-enabled, which the combat gate does. Unguarded,
        -- every combat transition built a second cover and wash. Keyed on
        -- record, a fresh table per build.
        if button.ptLadderRecord == record and button.ptLadderRank == rank then
          record.reinits = (record.reinits or 0) + 1
          return
        end
        button.ptLadderRecord, button.ptLadderRank = record, rank

        pcall(button.SetFrameLevel, button, level)
        table.insert(record.hosts, button)
        record.dirty = true

      -- Into underlays, because that is the list NS.UpdateCovers repaints.
        local cover = button:CreateTexture(nil, "OVERLAY", nil,
          MissingSub(rig, rank, "cover", MissingCoverSublevel(rank)))
        NS.stats.textures = NS.stats.textures + 1
      -- record.overdraw, not UNDERLAY_OVERDRAW -- AnchorTints replays this as
      -- the sum, so they agree only if the same field is used.
        AnchorToFill(cover, healthBar, record.overdraw)
        table.insert(record.underlays, cover)

        local nextRule = rules[rank + 1]
        if nextRule then
          local wash = button:CreateTexture(nil, "OVERLAY", nil,
            MissingSub(rig, rank + 1, "wash", MissingWashSublevel(rank + 1)))
          NS.stats.textures = NS.stats.textures + 1
          ApplyRuleFill(wash, healthBar, nextRule, 0)
      -- Unconditional by necessity: this belongs to a secure aura button and
      -- cannot be re-shown later. Gating comes from the root being disabled.
          wash:Show()
          record.washes[rank + 1] = wash
          AttachLevel(button, rank + 1)
        end
      end,
    })

    local ids = (NS.RelatedSpellIDs and NS.RelatedSpellIDs(condition.spellID))
      or { [condition.spellID] = true }
    if useSlot then
      frame:SetAuraSlotCandidateFilters(key, { includeSpellIDs = ids })
    else
      frame:SetAuraGroupCandidateFilters(key, { includeSpellIDs = ids })
      frame:SetAuraGroupMaxFrameCount(key, 1)
    end

    table.insert(record.containers, frame)
  -- Named, not containers[1]: rank 1's initializeFrame can fire during
  -- Register above and insert the rank-2 container first.
    if rank == 1 then record.root = frame end
    NS.ActivateContainer(rig, frame, record)
  end

  AttachLevel(healthBar, 1)
  return record
end

-- Displacement build. One independent chain per rule, which is why
-- combat-only can be per rule here.
function NS.BuildMissingDisplace(rig, healthBar, rules, level)
  rig.missingDisplace = { entries = {}, failures = 0 }
  if not rules or #rules == 0 then return end

  local barW = rig.barWidth or 150
  local barH = rig.barHeight or 14

  for rank, rule in ipairs(rules) do
    local condition = (rule.conditions or {})[1]
    if condition then
      local ok = pcall(function()
        local holder = CreateFrame("Frame", nil, healthBar)
        holder:SetAllPoints(healthBar)
        pcall(holder.SetFrameLevel, holder, level)

        local wash = holder:CreateTexture(nil, "OVERLAY", nil,
          MissingSub(rig, rank, "wash", DisplaceWashSublevel(rank)))
        NS.stats.textures = NS.stats.textures + 1
        ApplyRuleFill(wash, healthBar, rule, 0)

        -- Container first, no groups, so the mask can still anchor to it.
        local container = CreateFrame("AuraContainer", nil, healthBar,
          "CustomAuraContainerTemplate")
        NS.stats.containers = NS.stats.containers + 1
        container:SetEnabled(false)
        container:SetSize(1, barH)
        pcall(container.SetFlowLayoutAnchorPoint, container, "LEFT")
        pcall(container.SetFlowLayoutPadding, container, 0, 0, 0, 0)
        container:ClearAllPoints()
        container:SetPoint("LEFT", healthBar, "LEFT", 0, 0)

        local okRest, rest = pcall(container.GetWidth, container)
        if not okRest or (issecretvalue and issecretvalue(rest)) or not rest then rest = 1 end

        local mask = holder:CreateMaskTexture(nil, "OVERLAY")
        NS.stats.textures = NS.stats.textures + 1
        -- Wrap mode is the difference between working and silently inverted.
        if not pcall(mask.SetTexture, mask, "Interface\\Buttons\\WHITE8X8",
            "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") then
          pcall(mask.SetTexture, mask, "Interface\\Buttons\\WHITE8X8")
        end
        mask:SetSize(barW + DISPLACE_MASK_SLACK, barH + DISPLACE_MASK_SLACK)
        mask:SetPoint("CENTER", container, "RIGHT", barW / 2 - rest, 0)
        wash:AddMaskTexture(mask)

        -- Before registration, so initializeFrame can count into it. The
        -- pooled buttons are the whole cost difference between the modes.
        local entry = {
          holder = holder, wash = wash, mask = mask,
          container = container, rule = rule, rank = rank, buttons = 0,
          kind = "wash",
          levelOffset = level - rig.baseLevel,
          textures = 2,
        }

        -- LAST. Nothing may anchor to the container after this.
        local ids = (NS.RelatedSpellIDs and NS.RelatedSpellIDs(condition.spellID))
          or { [condition.spellID] = true }
        container:AddAuraGroup("D1", "HARMFUL|PLAYER", {
          initializeFrame = function(button)
            entry.buttons = entry.buttons + 1
            pcall(button.SetSize, button, DISPLACE_PUSH, barH)
            pcall(button.EnableMouse, button, false)
          end,
        })
        container:SetAuraGroupCandidateFilters("D1", { includeSpellIDs = ids })
        pcall(container.SetAuraGroupMaxFrameCount, container, "D1", 1)

        table.insert(rig.missingDisplace.entries, entry)
      end)
      if not ok then
        rig.missingDisplace.failures = rig.missingDisplace.failures + 1
      end
    end
  end
end

-- Missing BORDER rules, displacement only. Same shape as
-- NS.BuildMissingDisplace, into the same entries list, with four edge textures
-- riding the mask instead of one wash.
function NS.BuildMissingBorderDisplace(rig, healthBar, rules, level, topSublevel)
  if not rules or #rules == 0 then return end
  rig.missingDisplace = rig.missingDisplace or { entries = {}, failures = 0 }

  local barW = rig.barWidth or 150
  local barH = rig.barHeight or 14

  for rank, rule in ipairs(rules) do
    local condition = (rule.conditions or {})[1]
    local border = rule.border
    if condition and border and border.enabled then
      local ok = pcall(function()
        local holder = CreateFrame("Frame", nil, healthBar)
        holder:SetAllPoints(healthBar)
        pcall(holder.SetFrameLevel, holder, level)

        local sublevel = MissingBorderSublevel(rank, topSublevel)
        local bc = border.color or { r = 1, g = 1, b = 1, a = 1 }
        local t = math.max(1, math.min(8, border.thickness or 2))
        local pad = math.max(0, math.min(12, border.padding or 0))
        local out = (border.grow == "OUT") and (t + pad) or -pad

        local edges = {}
        for _, side in ipairs(BORDER_SIDES) do
          local tex = holder:CreateTexture(nil, "OVERLAY", nil, sublevel)
          NS.stats.textures = NS.stats.textures + 1
          tex:SetColorTexture(bc.r, bc.g, bc.b, bc.a)
          tex:SetPoint(side.a, healthBar, side.a, side.ax * out, side.ay * out)
          tex:SetPoint(side.b, healthBar, side.b, side.bx * out, side.by * out)
          if side.vertical then tex:SetWidth(t) else tex:SetHeight(t) end
          table.insert(edges, tex)
        end

        local container = CreateFrame("AuraContainer", nil, healthBar,
          "CustomAuraContainerTemplate")
        NS.stats.containers = NS.stats.containers + 1
        container:SetEnabled(false)
        container:SetSize(1, barH)
        pcall(container.SetFlowLayoutAnchorPoint, container, "LEFT")
        pcall(container.SetFlowLayoutPadding, container, 0, 0, 0, 0)
        container:ClearAllPoints()
        container:SetPoint("LEFT", healthBar, "LEFT", 0, 0)

        local okRest, rest = pcall(container.GetWidth, container)
        if not okRest or (issecretvalue and issecretvalue(rest)) or not rest then rest = 1 end

        local mask = holder:CreateMaskTexture(nil, "OVERLAY")
        NS.stats.textures = NS.stats.textures + 1
        -- Load-bearing wrap mode -- see the displacement header.
        if not pcall(mask.SetTexture, mask, "Interface\\Buttons\\WHITE8X8",
            "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") then
          pcall(mask.SetTexture, mask, "Interface\\Buttons\\WHITE8X8")
        end
        -- Oversized: this anchor cannot be re-set once the group registers.
        mask:SetSize(barW + DISPLACE_MASK_SLACK, barH + DISPLACE_MASK_SLACK)
        mask:SetPoint("CENTER", container, "RIGHT", barW / 2 - rest, 0)
        for _, tex in ipairs(edges) do tex:AddMaskTexture(mask) end

        local entry = {
          holder = holder, mask = mask, borders = edges,
          border = border, out = out, thickness = t,
          container = container, rule = rule, rank = rank, buttons = 0,
          kind = "border",
          levelOffset = level - rig.baseLevel,
          -- Four edges plus the mask, so /pt perf does not assume two.
          textures = #edges + 1,
        }

        -- LAST. Nothing may anchor to the container after this.
        local ids = (NS.RelatedSpellIDs and NS.RelatedSpellIDs(condition.spellID))
          or { [condition.spellID] = true }
        container:AddAuraGroup("D1", "HARMFUL|PLAYER", {
          initializeFrame = function(button)
            entry.buttons = entry.buttons + 1
            pcall(button.SetSize, button, DISPLACE_PUSH, barH)
            pcall(button.EnableMouse, button, false)
          end,
        })
        container:SetAuraGroupCandidateFilters("D1", { includeSpellIDs = ids })
        pcall(container.SetAuraGroupMaxFrameCount, container, "D1", 1)

        table.insert(rig.missingDisplace.entries, entry)
      end)
      if not ok then
        rig.missingDisplace.failures = rig.missingDisplace.failures + 1
      end
    end
  end
end

function NS.BuildOutline(rig, healthBar, level)
  local cfg = NS.db.tints or {}
  if cfg.plateOutline == false then
    if rig.outline then rig.outline:Hide() end
    return
  end

  -- On the health bar, not the rig: a frame cannot be destroyed, so this caps
  -- at one per plate.
  local frame = healthBar.ptOutline
  if not frame then
    frame = CreateFrame("Frame", nil, healthBar)
    frame.edges = {}
    -- One below Plater's own text there, since every rule is pinned flat.
    local sublevel = NS.IsPlaterBar(healthBar) and (NS.PlaterTextFloor(healthBar) - 1) or 7
    for _ = 1, #BORDER_SIDES do
      table.insert(frame.edges, frame:CreateTexture(nil, "OVERLAY", nil, sublevel))
    end
    healthBar.ptOutline = frame
  end
  rig.outline = frame

  -- Aura buttons keep whatever level the secure container gave them --
  -- SetFrameLevel is refused while auras are secret -- so if that is above this
  -- frame the fill draws over the plate's border. GetFrameLevel stays readable,
  -- so ask. Plater bars excluded: raising this would clear its name text.
  if not NS.IsPlaterBar(healthBar) then
    local ceiling = healthBar:GetFrameLevel() + 500
    for _, record in ipairs(rig.rules or {}) do
      for _, group in ipairs({ record.containers, record.hosts, record.tintHosts }) do
        for _, host in ipairs(group or {}) do
          local ok, hostLevel = pcall(host.GetFrameLevel, host)
          if ok and type(hostLevel) == "number" and hostLevel >= level then
            level = math.min(ceiling, hostLevel + 1)
          end
        end
      end
    end
  end

  pcall(frame.SetFrameLevel, frame, level)
  frame:SetAllPoints(healthBar)

  local t = math.max(1, math.min(8, cfg.plateOutlineSize or 1))
  local c = cfg.plateOutlineColor or { r = 0, g = 0, b = 0, a = 1 }
  -- Positive pulls the band inward, negative out past the bar. This frame is
  -- pinned to the bar FRAME while a tint anchors to the fill TEXTURE, and
  -- addons differ on the room between them -- hence a setting.
  local off = math.max(-8, math.min(8,
    (NS.AdapterSetting and NS.AdapterSetting(healthBar, "plateOutlineOffset"))
      or cfg.plateOutlineOffset or 0))

    -- PixelUtil: plain positioning lands between physical pixels and blurs.
  local hasPixelUtil = PixelUtil and PixelUtil.SetPoint and PixelUtil.SetWidth and PixelUtil.SetHeight

  for index, side in ipairs(BORDER_SIDES) do
    local tex = frame.edges[index]
    if not PlateOutlineSide(side.side) then
      tex:Hide()
    else
    tex:SetColorTexture(c.r, c.g, c.b, c.a)
    tex:ClearAllPoints()
    -- ax/ay point out of the bar, so negating moves the band inward.
    local ax, ay = side.ax * -off, side.ay * -off
    local bx, by = side.bx * -off, side.by * -off
    if hasPixelUtil then
      PixelUtil.SetPoint(tex, side.a, healthBar, side.a, ax, ay)
      PixelUtil.SetPoint(tex, side.b, healthBar, side.b, bx, by)
      if side.vertical then PixelUtil.SetWidth(tex, t) else PixelUtil.SetHeight(tex, t) end
    else
      tex:SetPoint(side.a, healthBar, side.a, ax, ay)
      tex:SetPoint(side.b, healthBar, side.b, bx, by)
      if side.vertical then tex:SetWidth(t) else tex:SetHeight(t) end
    end
    tex:Show()
    end
  end
  frame:Show()
end

function NS.AnchorTints(rig)
  local healthBar = rig.healthBar
  local baseLevel = NS.BaseLevelFor(healthBar)
  rig.baseLevel = baseLevel
  -- The full re-anchor runs out of combat, where every frame accepts a level,
  -- so this is the one path allowed to declare the level actually applied.
  -- RepinLevels only claims it when nothing was refused.
  rig.appliedLevel = baseLevel
  rig.levelRefusedCount = nil

  local okW, w = pcall(healthBar.GetWidth, healthBar)
  local okH, h = pcall(healthBar.GetHeight, healthBar)
  if okW and w and w > 0 then rig.barWidth = w end
  if okH and h and h > 0 then rig.barHeight = h end

  local isPlater = NS.IsPlaterBar(healthBar)

  if rig.outline then
    NS.BuildOutline(rig, healthBar, baseLevel + (rig.outlineLevelOffset or 0))
  end

  for _, record in ipairs(rig.rules) do
    -- Replays the recorded offset. rig.rules holds both lists, built with
    -- different formulas -- recomputing dropped the border records under the
    -- bar rules on the first reposition.
    local level = isPlater and baseLevel or (baseLevel + (record.levelOffset or 0))
    record.level = level
      -- Only the root takes a level; nested ones are aura-button children.
    for _, frame in ipairs(record.containers) do
      pcall(frame.SetFrameLevel, frame, level)
    end
    for _, host in ipairs(record.hosts) do
      pcall(host.SetFrameLevel, host, level)
    end
      -- For a combo rule these are nested deeper than record.hosts and need
      -- relevelling too.
    for _, host in ipairs(record.tintHosts or {}) do
      pcall(host.SetFrameLevel, host, level)
    end

    -- Re-apply the edge inset -- it is read at creation time. Through
    -- ApplyRuleFill, not AnchorToFill: a texture-mode tint is anchored to the
    -- bar frame, and re-anchoring it would let the pattern squish with health.
    for _, tex in ipairs(record.tints) do
      pcall(ApplyRuleFill, tex, healthBar, record.rule, record.overdraw)
    end
    for _, tex in ipairs(record.underlays) do
      -- Same overdraw as at creation, or the hairline returns.
      pcall(AnchorToFill, tex, healthBar, UNDERLAY_OVERDRAW + (record.overdraw or 0))
    end
    for _, tex in ipairs(record.pandemics or {}) do
      pcall(AnchorToFill, tex, healthBar)
    end
    for _, tex in ipairs(record.missingCovers) do
      pcall(AnchorToMissingFill, tex, healthBar, record.overdraw)
    end
    -- pairs, not ipairs: keyed by rank and starting at 2.
    for rank, tex in pairs(record.washes or {}) do
      pcall(ApplyRuleFill, tex, healthBar, record.missingStack[rank], 0)
    end
  end

  if rig.missingWash then
    NS.BuildMissingWash(rig, healthBar,
      isPlater and baseLevel or (baseLevel + (rig.missingLevelOffset or 0)),
      (rig.missingLadder or {})[1])
  end

  -- Re-anchored, not rebuilt: the mask's anchor to its container cannot be
  -- re-set, so a rebuild would have to discard the containers too.
  local displaceLevel = isPlater and baseLevel or (baseLevel + (rig.missingLevelOffset or 0))
  for _, entry in ipairs((rig.missingDisplace or {}).entries or {}) do
    -- Each entry's own offset -- border entries sit a band above the washes.
    pcall(entry.holder.SetFrameLevel, entry.holder,
      isPlater and baseLevel or (baseLevel + (entry.levelOffset or rig.missingLevelOffset or 0)))
    if entry.kind == "border" then
      for index, side in ipairs(BORDER_SIDES) do
        local tex = entry.borders and entry.borders[index]
        if tex then
          pcall(tex.ClearAllPoints, tex)
          pcall(tex.SetPoint, tex, side.a, healthBar, side.a, side.ax * entry.out, side.ay * entry.out)
          pcall(tex.SetPoint, tex, side.b, healthBar, side.b, side.bx * entry.out, side.by * entry.out)
          if side.vertical then
            pcall(tex.SetWidth, tex, entry.thickness)
          else
            pcall(tex.SetHeight, tex, entry.thickness)
          end
        end
      end
    else
      pcall(ApplyRuleFill, entry.wash, healthBar, entry.rule, 0)
    end
    pcall(entry.mask.SetSize, entry.mask,
      (rig.barWidth or 150) + DISPLACE_MASK_SLACK,
      (rig.barHeight or 14) + DISPLACE_MASK_SLACK)
  end

  NS.UpdateCovers(rig)
end

-- Session-cumulative. Split because they answer different questions: detected
-- is "did the host move the bar out from under us at all", refused is "and
-- could we do anything about it there and then".
NS.levelDrift = { detected = 0, repinned = 0, refused = 0, deferred = 0 }

-- The host bar's frame level is read ONCE, when the rig is built, and every
-- container and aura button is pinned to it. Plater raises its unit frame by
-- 5000 AFTER the plate appears, so a rig built inside that window latches the
-- pre-bump number -- measured on live plates as bar 5011 against baseLevel 11,
-- bar 5151 against 151, while the one plate that coloured had 5081 against
-- 5081. Health bars are pooled, so the stale level then rides that bar onto
-- later mobs.
--
-- Nothing FAILS when this happens, which is why no counter ever caught it:
-- SetFrameLevel was accepted, it was simply aimed at the wrong number. Frame
-- level is decided before draw layer, so from 5000 below every region the bar
-- owns -- the health fill included -- draws over our tint at every sublevel.
-- The plate just never colours.
--
-- AnchorTints already re-reads the level, but the only thing that calls it
-- mid-pull is combat ending, which is exactly too late. Hence a ticker.
--
-- Levels only, deliberately: AnchorTints also redoes anchors, sizes, masks and
-- covers, which is far too much to run every second. Nothing has MOVED here --
-- the bar is where it was, at a new level -- so there is nothing else to redo.
function NS.RepinLevels(rig)
  local healthBar = rig.healthBar
  if not healthBar then return false end
  local okLevel, wanted = pcall(NS.BaseLevelFor, healthBar)
  if not okLevel or type(wanted) ~= "number" then return false end
  if wanted == rig.baseLevel then return false end

  NS.levelDrift.detected = NS.levelDrift.detected + 1
  -- Set BEFORE anything is pinned, deliberately: the offsets below are all
  -- computed against it, and leaving it stale would make a retry every tick.
  --
  -- The cost is that it is a statement of intent, not of fact, and every
  -- diagnostic was reading it as fact. When the pins were refused this field
  -- still matched the bar, so `/pt bar` reported no drift and an external
  -- probe computing BaseLevelFor(bar) - rig.baseLevel got 0 -- on a plate
  -- whose tint was sitting 5000 levels below its bar and could not draw.
  -- Months of "same rules, some mobs colour and some do not" looked healthy
  -- in every diagnostic for exactly this reason.
  --
  -- rig.appliedLevel below is the honest one: it only advances when every
  -- frame accepted and read back the new level.
  rig.baseLevel = wanted
  local isPlater = NS.IsPlaterBar(healthBar)
  local refused = 0

  -- Accepted is not applied. A pcall that returns true only proves the call
  -- did not throw, so the level is read back rather than trusted -- the same
  -- trap that made this bug invisible in the first place.
  local function Pin(frame, level)
    if not frame then return end
    if pcall(frame.SetFrameLevel, frame, level) then
      local okGot, got = pcall(frame.GetFrameLevel, frame)
      if okGot and got == level then return end
    end
    refused = refused + 1
  end

  if rig.outline then Pin(rig.outline, wanted + (rig.outlineLevelOffset or 0)) end

  for _, record in ipairs(rig.rules or EMPTY) do
    local level = isPlater and wanted or (wanted + (record.levelOffset or 0))
    record.level = level
    for _, frame in ipairs(record.containers or EMPTY) do Pin(frame, level) end
    for _, host in ipairs(record.hosts or EMPTY) do Pin(host, level) end
    for _, host in ipairs(record.tintHosts or EMPTY) do Pin(host, level) end
  end

  if rig.missingWash then
    Pin(rig.missingWash, isPlater and wanted or (wanted + (rig.missingLevelOffset or 0)))
  end
  for _, entry in ipairs((rig.missingDisplace or EMPTY).entries or EMPTY) do
    Pin(entry.holder,
      isPlater and wanted or (wanted + (entry.levelOffset or rig.missingLevelOffset or 0)))
  end

  if refused > 0 then
    NS.levelDrift.refused = NS.levelDrift.refused + refused
    NS.levelDrift.deferred = NS.levelDrift.deferred + 1
    -- An aura button only accepts a level inside its own initializeFrame, so
    -- some of these can only be fixed by a rebuild. Marked, not rebuilt here:
    -- rebuilding mid-combat is the churn this whole area exists to avoid, and
    -- Reapply on PLAYER_REGEN_ENABLED re-anchors every rig anyway.
    --
    -- Since the initializeFrame callback now reads record.level rather than
    -- the level captured at build time, a refused button also repairs itself
    -- the next time the pool initialises it -- which under a HARMFUL|PLAYER
    -- filter is the next time the debuff lands. The deferral is the backstop
    -- now, not the only route.
    rig.levelDirty = true
    -- appliedLevel deliberately NOT advanced: the frames are not there.
    rig.levelRefusedCount = refused
  else
    NS.levelDrift.repinned = NS.levelDrift.repinned + 1
    rig.levelDirty = nil
    rig.levelRefusedCount = nil
    rig.appliedLevel = wanted
  end
  return true
end

function NS.SetTintsUnit(rig)
  for _, record in ipairs(rig.rules or {}) do
    for _, frame in ipairs(record.containers) do
      NS.ActivateContainer(rig, frame, record)
    end
  end
  -- Displacement entries are not in rig.rules, so they bind separately.
  local displace = rig.missingDisplace
  for _, entry in ipairs((displace or {}).entries or {}) do
    -- RetireTints hides the holder too, and the combat gate is edge-triggered
    -- on entry.allowed -- so a holder hidden while the gate already believed
    -- it was shown would never be corrected. Clearing allowed forces the gate
    -- below to re-assert visibility from scratch.
    pcall(entry.holder.Show, entry.holder)
    entry.allowed = nil
    NS.ActivateContainer(rig, entry.container)
  end
  -- Settle the gate now rather than leaving the wash lit for up to a quarter
  -- second on every rebind.
  if displace and #(displace.entries or {}) > 0 and NS.UpdateMissingCombatGate then
    NS.UpdateMissingCombatGate(rig)
  end
end

-- Nested containers are children of aura buttons: SetEnabled and field writes
-- are accepted, Hide is refused. SetEnabled(false) is what retires one.
-- Combat-safe recovery: notice a container that has gone dark and switch it
-- back on, WITHOUT rebuilding anything.
--
-- Every other fix in this area works by stopping a container being turned off
-- in the first place, which only helps for causes already identified. This
-- does not care why. If a root container on a bound plate is hidden or
-- disabled, that plate cannot colour, and both are reversible in combat --
-- unlike Show on a NESTED container, which is refused, and unlike a rebuild,
-- which needs lockdown to end.
--
-- Cheap on purpose, because it runs on a ticker: a couple of boolean reads per
-- root container, and nothing at all for a plate that is healthy. Root
-- containers only -- one per rule, not one per pooled button.
--
-- SetUnit is deliberately NOT called here. Re-assigning the same unit churns
-- the container's button pool, which is what drove runaway button counts
-- before; ActivateContainer owns that decision and guards it with boonUnit.
function NS.ReviveContainers(rig)
  if not rig.unit then return 0 end
  local revived = 0
  for _, record in ipairs(rig.rules or EMPTY) do
    for _, frame in ipairs(record.containers or EMPTY) do
      if frame.ptRootContainer ~= false then
        local okShown, shown = pcall(frame.IsShown, frame)
        local okEnabled, enabled = pcall(frame.IsEnabled, frame)
        -- Only act on a definite negative. A refused or secret read means we
        -- do not know, and switching something on every tick because we
        -- cannot read it would be its own churn.
        local darkShown = okShown and shown == false
        local darkEnabled = okEnabled and enabled == false
        if darkShown or darkEnabled then
          if darkShown then pcall(frame.Show, frame) end
          if darkEnabled and frame.boonUnit then
            pcall(frame.SetEnabled, frame, true)
          end
          revived = revived + 1
        end
      end
    end
  end
  return revived
end

function NS.RetireTints(rig)
  -- The missing wash is shown unconditionally, so a retired rig that left it
  -- up would keep a reminder on a plate this addon no longer drives.
  if rig.outline then rig.outline:Hide() end
  if rig.missingWash then rig.missingWash:Hide() end
  -- Same for a displacement wash. The holder is ours, so Hide is allowed.
  for _, entry in ipairs((rig.missingDisplace or {}).entries or {}) do
    pcall(entry.holder.Hide, entry.holder)
    pcall(entry.container.SetEnabled, entry.container, false)
    pcall(entry.container.Hide, entry.container)
  end
  for _, record in ipairs(rig.rules or {}) do
    for _, frame in ipairs(record.containers) do
      pcall(frame.SetEnabled, frame, false)
      frame.boonEnabled = false
      frame.boonUnit = nil
      -- ROOT ONLY. A nested container is a child of an aura button, where
      -- Show is refused -- so hiding one is a ONE-WAY DOOR: it goes dark and
      -- nothing can bring it back, for the life of that health bar. Bars are
      -- pooled, so every later mob handed that bar inherits the dead chain.
      --
      -- ActivateContainer already assumed this, in as many words: "those were
      -- never hidden in the first place, so a refusal costs nothing". They
      -- were, right here. Only combo rules can be hit -- a single-debuff rule
      -- owns just the root -- which shows up as some rules painting on a bar
      -- while others never do again.
      --
      -- Disabling the root is sufficient anyway: with it disabled the engine
      -- pools no buttons, so the nested containers have nothing to hang off
      -- and draw nothing regardless of their shown state.
      if frame.ptRootContainer ~= false then
        pcall(frame.Hide, frame)
      end
    end
  end
end

-- Missing-health covers are excluded: they paint a fixed colour, not a live
-- replica, so NS.ApplyTintColors handles them.
function NS.AnyCovers()
  for _, rig in pairs(NS.rigs) do
    for _, record in ipairs(rig.rules or {}) do
      if #record.underlays > 0 then return true end
    end
  end
  return false
end

-- A readable value, or nil. A secret used as a table key throws.
local function Plain(ok, value)
  if not ok or value == nil then return nil end
  if issecretvalue and issecretvalue(value) then return nil end
  return value
end

-- Unit tier: boss, lieutenant, caster, rare, elite, normal.
--
-- UnitClassification alone is useless in a dungeon -- almost all trash reports
-- "elite". These three separate them, and are category questions rather than
-- identity ones (identity is sealed in instances):
--
--   UnitIsLieutenant          mini-boss marker
--   UnitHasPowerType(.Mana)   second arg must be the enum NUMBER; the global
--                             MANA is a localized string and never matches
--   UnitEffectiveLevel        -1 is a skull. Can be secret, hence Plain().
function NS.UnitTier(unit)
  if not unit then return "normal" end

  local classification = Plain(pcall(UnitClassification, unit))
  local level = Plain(pcall(UnitEffectiveLevel, unit))
  local playerLevel = Plain(pcall(UnitEffectiveLevel, "player"))

  local isSkull = level == -1
  local aboveOne = level and playerLevel and level >= playerLevel + 1
  local aboveTwo = level and playerLevel and level >= playerLevel + 2

  -- Ranked mobs only -- a same-level elite is not a mini-boss.
  if isSkull or aboveOne then
    local lieutenant = (not isSkull) and UnitIsLieutenant
      and Plain(pcall(UnitIsLieutenant, unit))
    if not lieutenant and (isSkull or aboveTwo or classification == "worldboss") then
      return "boss"
    end
    return "lieutenant"
  end

  if UnitHasPowerType and Enum and Enum.PowerType then
    if Plain(pcall(UnitHasPowerType, unit, Enum.PowerType.Mana)) then
      return "caster"
    end
  end

  if classification == "rare" or classification == "rareelite" then return "rare" end
  if classification == "elite" then return "elite" end
  return "normal"
end

function NS.ClassificationColor(unit)
  local cfg = NS.db and NS.db.tints
  if not (cfg and cfg.missingAppliedByClass) then return nil end
  local colors = cfg.missingAppliedClassColors
  if not colors then return nil end

  local ok, tier = pcall(NS.UnitTier, unit)
  -- Falls back to normal rather than painting nothing: an unpainted cover
  -- leaves the wash showing on a mob that has the debuff.
  local defaults = NS.Defaults.tints.missingAppliedClassColors
  local key = (ok and tier) or "normal"
  return colors[key] or colors.normal or defaults[key] or defaults.normal
end

-- Covers copy the bar's full appearance -- hosts derive tex coords from bar
-- width, and a path-only copy reads as flat. Unless the classification option
-- is on, where a missing rule's cover is a flat colour instead.
function NS.UpdateCovers(rig)
  local healthBar = rig.healthBar
  if not healthBar then return end

  local classColor = NS.ClassificationColor(rig.unit)
  if classColor then
    for _, record in ipairs(rig.rules or {}) do
      if record.missingStack then
        for _, cover in ipairs(record.underlays) do
          pcall(function()
            -- Reset both: it may carry a replica's tex-coords and tint.
            cover:SetTexCoord(0, 1, 0, 1)
            cover:SetVertexColor(1, 1, 1)
            cover:SetColorTexture(classColor.r, classColor.g, classColor.b,
              classColor.a or 1)
          end)
        end
      end
    end
  end

  local anyReplicas = false
  for _, record in ipairs(rig.rules or {}) do
    if #record.underlays > 0 and not (classColor and record.missingStack) then
      anyReplicas = true
      break
    end
  end
  if not anyReplicas then return end

  local okColor, r, g, b = pcall(healthBar.GetStatusBarColor, healthBar)
  if not okColor or not r then return end

  local fill = healthBar:GetStatusBarTexture()
  if not fill then return end

  local atlas
  if fill.GetAtlas then
    local okAtlas, value = pcall(fill.GetAtlas, fill)
    if okAtlas then atlas = value end
  end

  local texturePath
  if not atlas and fill.GetTexture then
    local okTex, path = pcall(fill.GetTexture, fill)
    if okTex then texturePath = path end
  end

  local coords
  if fill.GetTexCoord then
    local okCoord, a1, a2, a3, a4, a5, a6, a7, a8 = pcall(fill.GetTexCoord, fill)
    if okCoord and a1 then
      coords = { a1, a2, a3, a4, a5, a6, a7, a8 }
    end
  end

  local horizTile = fill.GetHorizTile and select(2, pcall(fill.GetHorizTile, fill)) or nil
  local vertTile = fill.GetVertTile and select(2, pcall(fill.GetVertTile, fill)) or nil

  local function Repaint(replica)
    pcall(function()
      if atlas then
        replica:SetAtlas(atlas)
      elseif type(texturePath) == "string" then
        replica:SetTexture(texturePath)
      else
        replica:SetColorTexture(1, 1, 1, 1)
      end
      if horizTile ~= nil and replica.SetHorizTile then replica:SetHorizTile(horizTile) end
      if vertTile ~= nil and replica.SetVertTile then replica:SetVertTile(vertTile) end
      if coords and not atlas then replica:SetTexCoord(unpack(coords)) end
      replica:SetVertexColor(r, g, b, 1)
    end)
  end

  for _, record in ipairs(rig.rules or {}) do
    if not (classColor and record.missingStack) then
      for _, underlay in ipairs(record.underlays) do Repaint(underlay) end
    end
  end
end


function NS.DescribeChain(record, healthBar)
  if record.unsupported then
    return ("|cffff0000not built — %d debuffs exceeds the limit of %d|r")
      :format(#(record.rule.conditions or {}), NS.MAX_RULE_CONDITIONS)
  end
  if record.blocked then
    return "|cffff0000not built — refused while auras are secret|r"
  end

  -- The ladder carries no tints, so the generic line would report it as
  -- "N containers, 0 tints" -- which looks like a failed build.
  if record.missingStack then
    return ("missing ladder — %d rank(s), %d container(s), %d wash(es), %d cover(s)%s")
      :format(#record.missingStack, #record.containers,
        1 + (function() local n = 0 for _ in pairs(record.washes or {}) do n = n + 1 end return n end)(),
        #record.underlays,
        record.failures > 0 and (" |cffff0000%d failure(s)|r"):format(record.failures) or "")
  end

  local parts = {
    ("%d container(s)"):format(#record.containers),
    ("%d tint(s)"):format(#record.tints),
  }
  local state
  if record.truncated then
    state = " |cffff0000(TRUNCATED — pool larger than expected)|r"
  elseif record.dirty then
    state = " |cffffcc00(building...)|r"
  else
    state = " |cff00ff00(COMPLETE)|r"
  end
  return table.concat(parts, ", ") .. state
end

-- Applied without a rebuild. This used to bail on NS.IsRestricted(), which is
-- true for a whole dungeon, so no colour change ever landed inside a key.
function NS.ApplyTintColors()
  if InCombatLockdown() then
    NS.colorPending = true
    return
  end
  NS.colorPending = false
  for _, rig in pairs(NS.rigs) do
    for _, record in ipairs(rig.rules or {}) do
      local color = record.rule and record.rule.color
      if color then
        for _, tex in ipairs(record.tints) do
          pcall(ApplyRuleColor, tex, record.rule)
        end
      end
  -- Thickness is baked into each edge texture at creation; colour is not.
      local border = record.rule and record.rule.border
      local bc = border and border.color
      if bc then
        for _, tex in ipairs(record.borders or {}) do
          pcall(tex.SetColorTexture, tex, bc.r, bc.g, bc.b, bc.a)
        end
      end
      if #record.missingCovers > 0 then
        local mc = NS.MissingCoverColor()
        for _, tex in ipairs(record.missingCovers) do
          pcall(tex.SetColorTexture, tex, mc.r, mc.g, mc.b, mc.a)
        end
      end
    -- Covers are live replicas of the host bar, so they are not recoloured.
      for rank, tex in pairs(record.washes or {}) do
        local washRule = record.missingStack and record.missingStack[rank]
        if washRule and washRule.color then
          pcall(ApplyRuleColor, tex, washRule)
        end
      end
    end
    local frame = rig.missingWash
    local top = (rig.missingLadder or {})[1]
    if frame and frame.wash and top and top.color then
      pcall(ApplyRuleColor, frame.wash, top)
    end
    -- Each displacement wash follows its own rule; there is no single top.
    for _, entry in ipairs((rig.missingDisplace or {}).entries or {}) do
      if entry.kind == "border" then
        local bc = entry.border and entry.border.color
        if bc then
          for _, tex in ipairs(entry.borders or {}) do
            pcall(tex.SetColorTexture, tex, bc.r, bc.g, bc.b, bc.a)
          end
        end
      elseif entry.rule and entry.rule.color then
        pcall(ApplyRuleColor, entry.wash, entry.rule)
      end
    end
  end
end
