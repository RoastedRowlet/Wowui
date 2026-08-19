local _, NS = ...

-------------------------------------------------------------------------------
-- Tint rules engine.
--
-- A rule is a colour plus debuffs that must all be on the unit. Aura state is
-- never read: the engine decides what shows, because a texture living on an
-- aura button draws only while that button is shown.
--
-- Several debuffs are ANDed by NESTING -- one container per debuff, each
-- created inside a button of the one before it, with the tint on the deepest
-- button. Ancestry is the AND: a frame does not render if any ancestor is
-- hidden. Every touch is same-button, which is the only thing the engine
-- permits once auras are secret.
--
-- ⚠ The mask-intersection scheme this file used to describe is DEAD in
-- instances and the comment describing it was wrong for a long time. A texture
-- may only carry masks its OWN button owns -- AddMaskTexture rejects another
-- button's mask as a forbidden object -- so cross-button masking cannot work
-- where it matters. Nesting is the replacement, not the other way round.
--
-- ⚠ So is the pool^N cost that used to justify NS.MAX_RULE_CONDITIONS. That
-- belonged to AddAuraGroup, which pools ~10 buttons and displays an arbitrary
-- one, forcing a rule to cover every combination. AddAuraSlot pools ONE (see
-- SlotsAvailable below), so a chain costs one container and one texture PER
-- LEVEL. The cap is now about the RULE -- each level is another aura that must
-- be live -- not about affordability. Do not quote the old numbers.
--
-- Matching on a debuff's ABSENCE is back (v1.5.0) and works several rules
-- deep. It is drawn unconditionally and covered by a bar replica once the
-- debuff lands; several coexist because their conditions are made mutually
-- exclusive rather than arbitrated. See the Missing-debuff rules header below.
-------------------------------------------------------------------------------

-- A safety stop, not a budget. With aura slots a rule builds one combination,
-- so this is never approached; it exists so that a client falling back to the
-- pooled AddAuraGroup path -- where the old pool^N applies -- cannot grow
-- without bound and freeze the game while it does.
local MAX_TINTS_PER_RULE = 1200

-- Aura SLOTS instead of aura GROUPS.
--
-- A group pools TEN frames and calls initializeFrame on every one, and a
-- texture has to be attached in that callback because it is the only context
-- where an aura button is touchable. Chain two groups for a combo rule and the
-- count is 10 x 10 = 100 textures per nameplate. That -- not the number of
-- aura combinations -- is where this addon's cost has always come from.
--
-- AddAuraSlot is the same idea with a pool of ONE. Verified on a live plate
-- before this was written: it fires initializeFrame once, its button accepts a
-- texture, a second container nests inside that button, and the button is
-- shown only while the aura is actually present -- which is the whole contract,
-- since ancestry is the AND.
--
--   single rule   10 textures -> 1
--   combo rule   100 textures -> 1
--
-- Kept behind a switch, and the switch checks the API exists, because this is
-- the mechanism the entire addon rests on. /pt slots off falls back to the
-- pooled-group path without a reload if anything is ever wrong with this one.
-- Asked of the container we are ALREADY creating, at the moment we create it.
--
-- The first version probed for the API during ADDON_LOADED and cached the
-- answer. Blizzard_AuraContainer has not necessarily loaded that early, so the
-- probe's CreateFrame failed, the answer cached as "unavailable", and the
-- engine quietly used the ten-frame path for the whole session while the
-- feature looked switched on. Asking the real object at the real moment cannot
-- be early.
local function SlotsAvailable(frame)
  if NS.db and NS.db.useAuraSlots == false then return false end
  local present = type(frame.AddAuraSlot) == "function"
    and type(frame.SetAuraSlotCandidateFilters) == "function"
  -- Recorded for /pt status, which otherwise has nothing to report until a
  -- rig has been built.
  NS.slotApiPresent = present
  return present
end
local LEVELS_PER_RULE = 4

-- An underlay needs no overdraw of its own. It must hide the tint of any lower
-- rule, and lower rules are now inset FURTHER than the rule above them (see
-- RANK_INSET), so an underlay drawn at its own rule's rect already extends
-- past everything it has to cover.
local UNDERLAY_OVERDRAW = 0

-- A missing rule's cover, on the other hand, DOES need one. It hides a wash
-- anchored to the same rect on a different frame, with no rank inset between
-- them to absorb rounding, and a hairline of leftover colour in the state that
-- is supposed to look like an untouched bar would be permanent.
local MISSING_COVER_OVERDRAW = 1

-- Pixels each priority RANK is inset, capped.
--
-- Two rules that do not cover each other (Haunt and Agony, say) build no
-- underlay -- neither is a subset of the other -- so their tints would draw at
-- identical size and the higher one would win only on frame level, which
-- cannot arbitrate in an instance. Any rounding then leaks a hairline of the
-- lower colour around the edge.
--
-- The fix is that the higher tint must be strictly larger, which is a RELATIVE
-- relationship -- it never required growing past the bar. Earlier this was
-- done by expanding the top rule outward, and that painted over the
-- nameplate's own black border, since the border sits just outside the fill.
-- Insetting the lower rules instead gives the identical guarantee and leaves
-- every tint within the fill, so the plate's border always survives.
--
-- The visible cost is the opposite one: a lower-priority rule showing on its
-- own is up to 1px smaller than the bar. Capped low for that reason.
--
-- ⚠ Applied only where a leak is actually POSSIBLE -- see the inset ladder in
-- NS.BuildTints. It used to be a flat (rank - 1) * RANK_INSET on every rule,
-- which was wrong in the common case and increasingly visible as the condition
-- cap rose: NS.SortRules orders more-specific rules first, so rank tracks
-- DEBUFF COUNT, and a 1/2/3/4-debuff set therefore drew four visibly different
-- fill sizes on the same bar. Most of those rules cover each other and are
-- masked by an underlay, which needs no size difference at all.
local RANK_INSET = 0.5
local RANK_INSET_MAX = 1

-- Pairings are built in each button's own initializeFrame callback, so the
-- work is naturally spread across button arrivals rather than needing a
-- ticker to slice it. A 2-debuff rule builds at most 10 combinations per
-- arrival; only a 3-debuff rule's last arrivals do 100 at once, and those
-- stay under the per-rule cap below.

-- Pull the tint in from the bar's edges.
--
-- Tints sit at a HIGHER frame level than the host bar so they are visible at
-- all, which means anything the nameplate addon draws at the bar's edge --
-- most borders -- ends up underneath. Lowering our level is not an option
-- (the tint would vanish behind the bar itself), so the fix is geometric:
-- stop a pixel or two short and let the border show through.
-- Flush with the bar is the BASELINE. The stored number is an ADJUSTMENT
-- either side of it: 0 covers the fill exactly, positive pulls in off a
-- nameplate addon's border, negative overhangs.
--
-- This was 1px in, to stay clear of borders. But that left a one-pixel ring of
-- the real health bar showing inside every tint, and as the bar animates that
-- ring moves -- reading as a flicker under the colour. Borders now default to
-- growing OUTSIDE the bar, so the inset is no longer earning its keep, and
-- anyone whose plate art does need it has the Bar Edges slider.
local BASE_INSET = 0
NS.BASE_INSET = BASE_INSET

-- Frame level our containers/tints sit at, relative to the health bar.
--
-- Elevated above the bar by default so our tint is never hidden BEHIND the
-- bar's own fill -- frame level always wins over draw layer, so this alone
-- guarantees visibility regardless of what draw layer/sublevel we use.
--
-- Plater is the one exception: it parents its own unit-name text directly
-- onto the health bar frame, at the top OVERLAY sublevel (see Plater.lua:
-- healthBar.unitName, SetDrawLayer("overlay", 7)) rather than on a separate,
-- higher frame the way other nameplate addons do. Any elevation at all would
-- put our tint above that text too, since frame level beats sublevel. Staying
-- level with the bar instead lets draw-layer order decide: our tint (OVERLAY)
-- still beats the fill (ARTWORK) so it stays visible, but Plater's sublevel-7
-- text now outranks our sublevel-0 tint in that tie, so the name survives.
--
-- healthBar.unitName existing is Plater's own signature for "this bar owns
-- its own text region" -- every other addon's health bar lacks that field,
-- so this is a no-op for them.
-- Whether a rule/border/outline needs to stay pinned at the bar's own frame
-- level rather than stepping up per rank. healthBar.unitName existing is
-- Plater's own signature for "this bar owns its own text region" -- every
-- other addon's health bar lacks that field, so this is false for them.
function NS.IsPlaterBar(healthBar)
  return healthBar.unitName ~= nil
end

function NS.BaseLevelFor(healthBar)
  local offset = NS.IsPlaterBar(healthBar) and 0 or (NS.db.levelOffset or 1)
  return healthBar:GetFrameLevel() + offset
end

-- On a normal bar, simultaneous rules are told apart by frame level: each
-- rank sits LEVELS_PER_RULE above the one below it, so a higher rule (and
-- its underlay, masking whatever is beneath) always wins regardless of draw
-- layer. On a Plater bar every rule is pinned to ONE frame level instead
-- (see NS.BaseLevelFor), so that lever is gone -- rank has to be expressed as
-- a draw-layer SUBLEVEL within that single level instead.
--
-- OVERLAY sublevels run -8..7; 7 is reserved for Plater's own name text, and
-- 6 for our border/outline (see below), leaving 5 downward for tints. THREE
-- sublevels per rank now -- the tint, its own underlay one below it (only has
-- to clear the NEXT rank's tint, one sublevel further down), and its own
-- missing-health cover one ABOVE it. The cover needs to be strictly above its
-- own tint, not just spatially separate from it: a texture-mode fill is
-- anchored to the BAR FRAME and only MASKED down to the fill's live edge, and
-- that mask can leave a sub-pixel sliver unclipped right at the boundary --
-- sharing a sublevel with the tint left that sliver's winner undefined, which
-- is what "the cover isn't overlapping the texture" turned out to be. Ranks
-- beyond the budget collapse onto the floor: reachable at 5+ simultaneously
-- stacked rules, and a collapsed rank still draws, just with less precise
-- ordering against its neighbours.
local function PlaterRankSublevels(rank)
  local tint = math.max(-8, 4 - 3 * (rank - 1))
  return tint, math.max(-8, tint - 1), math.min(6, tint + 1)
end

-- Memo for values that depend on the CONFIG, not on the texture being drawn.
--
-- NS.AnchorTints re-applies every texture on every rig on each reposition, and
-- a combo rule carries about a hundred textures per plate. Each of those calls
-- re-derived the same handful of config-wide answers: an LSM Fetch for the bar
-- texture path, a linear scan of the pattern library, a walk of every border
-- rule for the widest inside border, and the edge inset. At forty plates in a
-- raid that is thousands of identical lookups per pass.
--
-- Invalidated explicitly rather than by timestamp -- every path that can change
-- the answers already goes through Live/Restyle/Structural or a rebuild, and
-- those call NS.InvalidateFillCache. A generation counter rather than clearing
-- fields, so a stale cached table can never be half-updated.
local fillCache = {}

function NS.InvalidateFillCache()
  fillCache = {}
end

-- Off makes every cached read miss, which is the pre-cache behaviour exactly.
-- Exists for the benchmark: an A/B against the same rules on the same frame is
-- worth more than a claim about what the cache saves.
local fillCacheEnabled = true
function NS.SetFillCacheEnabled(value)
  fillCacheEnabled = value and true or false
  fillCache = {}
end

function NS.FillInset()
  local cached = fillCacheEnabled and fillCache.inset
  if cached then return cached end
  local adjust = NS.db and NS.db.tints and NS.db.tints.edgeAdjust or 0
  cached = math.max(-4, math.min(8, BASE_INSET + adjust))
  fillCache.inset = cached
  return cached
end
local FillInset = NS.FillInset

-- The widest INSIDE border any enabled rule asks for.
--
-- Underlays are opaque copies of the bar that let a rule mask lower-priority
-- ones. They cover the whole bar, so they also cover a LOWER rule's border,
-- and "Moonfire+Sunfire colours the bar" would swallow "Sunfire draws a
-- border". Frame levels cannot fix that -- SetFrameLevel on an aura button is
-- refused while auras are secret -- so the underlay is shrunk instead, by
-- enough to leave every inside border showing.
--
-- Outside borders need no allowance: they are already beyond the bar.
-- Which edges the PLATE border draws. Absent means on, so a profile that
-- predates the setting keeps all four.
--
-- Declared here, above PlateOutlineReserve, rather than beside BORDER_SIDES
-- where it reads more naturally: BORDER_SIDES is defined further down, and a
-- local declared after its caller is not in scope inside it -- the call
-- resolves to a nil global and throws at runtime.
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
      -- Padding pushes the band further in, so the reserve covers both.
      widest = math.max(widest,
        math.min(8, b.thickness or 2) + math.max(0, math.min(12, b.padding or 0)))
    end
  end
  fillCache.insideBorder = widest
  return widest
end

-- How far the PLATE BORDER reaches inside the bar.
--
-- Reserved for the same reason a rule border is, and it took a while to see
-- that it had to be. The outline is drawn on a frame we own, at a frame level
-- far above every rule's -- and it still lost. The reason is that the buttons
-- carrying a rule's tint report a SECRET frame strata: strata beats level
-- outright, and a strata that cannot be read cannot be out-ranked. There is no
-- layering fight to win here.
--
-- So do not fight it. Stop the tint short of the band instead, exactly as the
-- rule borders already do -- geometry does not care what strata anything is in.
local function PlateOutlineReserve()
  local cached = fillCacheEnabled and fillCache.outlineReserve
  if cached then return cached end
  local cfg = (NS.db and NS.db.tints) or {}
  local reserve = 0
  local anySide = PlateOutlineSide("top") or PlateOutlineSide("bottom")
    or PlateOutlineSide("left") or PlateOutlineSide("right")
  if cfg.plateOutline ~= false and anySide then
    local t = math.max(1, math.min(8, cfg.plateOutlineSize or 1))
    -- Positive offset pulls the band further in, so it deepens the reserve;
    -- negative pushes it outward, where no tint reaches, and can only reduce
    -- it to zero.
    local off = math.max(-8, math.min(8, cfg.plateOutlineOffset or 0))
    reserve = math.max(0, t + off)
  end
  fillCache.outlineReserve = reserve
  return reserve
end

-- The deeper of the two bands. Both measure inward from the bar's edge, so a
-- tint only has to clear whichever reaches further.
local function EdgeReserve()
  return math.max(MaxInsideBorder(), PlateOutlineReserve())
end

-- Everything that paints the bar BODY -- tints, underlays, the pandemic
-- flash, the preview -- goes through here, so they all reserve the same
-- border band and cannot disagree about it.
-- The expand argument grows the texture outward by that many pixels. Used by underlays:
-- an underlay's only job is to hide the rule beneath it, and two textures
-- anchored to the same rect on different frames can still leave a hairline of
-- the lower colour at the edges after rounding. Overdrawing by a pixel costs
-- nothing and removes the seam entirely.
local function AnchorToFill(tex, healthBar, expand)
  local fill = healthBar:GetStatusBarTexture() or healthBar
  -- Two insets, not one.
  --
  -- `base` is the edge inset alone; `inset` adds the border reserve on top --
  -- room for the plate border and the widest inside rule border, so a tint
  -- never paints over either.
  --
  -- The reserve applies to three sides only. The fill's RIGHT edge is the live
  -- health mark, not an edge of the bar, and no border is ever drawn there --
  -- so reserving for one just exposes a strip of the bar's own colour that
  -- slides around as health changes. That strip is what the red band inside
  -- the tint turned out to be.
  --
  -- At full health that edge coincides with the bar's, and the tint then runs
  -- under the border instead of stopping short of it. That is fine: borders
  -- draw at the top OVERLAY sublevel and a tint at the bottom, so the border
  -- still wins the pixels it wants.
  local base = FillInset() - (expand or 0)
  local inset = base + EdgeReserve()
  tex:ClearAllPoints()
  -- PixelUtil, not plain SetPoint. The fill's RIGHT edge moves with health%
  -- and is the one edge nothing else covers -- the black outline patches the
  -- static frame edges, but this boundary is live. Plain SetPoint can place
  -- it at a fractional UI coordinate that lands between physical pixels at
  -- most scales, leaving a hairline of the bar's own colour showing through
  -- right at the health mark. PixelUtil rounds to the actual pixel grid.
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

-- Same shape as AnchorToFill, but pinned to the BAR FRAME -- which does not
-- resize as health changes -- instead of the fill texture, which does. Used
-- only by library texture patterns: a repeating tile's own on-screen size has
-- to stay constant regardless of current health, or the same fixed UV range
-- stretched across a shrinking rectangle squishes thinner as health drops.
-- Paired with a MASK tracking the fill's live edge (see EnsureOwnFillMask)
-- so the pattern is still cropped to current health, just without resizing.
local function AnchorToBarFrame(tex, healthBar, expand)
  local inset = FillInset() + EdgeReserve() - (expand or 0)
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

-- The inverse of AnchorToFill: covers the MISSING side of the bar -- from
-- the fill's live edge out to the bar's own far edge -- instead of the
-- filled side. Used only by a rule's "missing cover", an opaque replica of
-- the bar's own current art (see NS.UpdateCovers) painted over whatever the
-- host bar shows once its fill has receded.
--
-- The left edge ties to the fill's own live corner, same as AnchorToFill --
-- it moves with health% automatically, no polling needed, and meets the
-- tint's own edge exactly since both are anchored off the same live point.
-- The other three edges match AnchorToBarFrame's, since this side of the
-- bar does not move. Assumes a standard left-to-right fill, same as the
-- rest of this file.
local function AnchorToMissingFill(tex, healthBar, expand)
  local fill = healthBar:GetStatusBarTexture() or healthBar
  local inset = FillInset() + EdgeReserve() - (expand or 0)
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

-------------------------------------------------------------------------------
-- Missing-debuff rules
--
-- A missing rule washes the health bar in its colour until its debuff is up.
--
-- Absence has no direct expression: a texture on an aura button is drawn
-- exactly while the aura is present, and there is no readable inverse. So it
-- is built by OCCLUSION -- draw the wash unconditionally, and let a texture on
-- an aura button paint over it once the debuff lands. That cover has to be an
-- opaque replica of the bar's own art (NS.UpdateCovers maintains it), because
-- it is restoring something the user can see.
--
-------------------------------------------------------------------------------
-- Why several missing rules work, when one cover would seem to blank the next
--
-- Each cover is an opaque repaint of the entire bar, so two washes lit at
-- once would be a real conflict. The resolution is to make that state
-- unreachable rather than to arbitrate it. Rank the rules and define:
--
--   wash 1 shows iff  D1 absent
--   wash 2 shows iff  D1 present AND D2 absent
--   wash k shows iff  D1..D(k-1) present AND Dk absent
--
-- which is just "the bar shows the highest-priority rule you still owe" --
-- the same resolution presence tints already use. Rule k requires D(k-1)
-- PRESENT and rule k-1 requires it ABSENT, so no two washes can ever be lit
-- together, and no cover ever has another rule's wash to blank.
--
-- The "D1..D(k-1) present" half is the AND-chain combo rules already use, so
-- one chain serves the whole ladder: container k filters Dk, and its button --
-- which the engine shows exactly while D1..Dk are all present -- carries
-- BOTH cover k and wash k+1. Depth 0 is our own frame, carrying wash 1.
--
-- Cost is linear, not exponential: AddAuraSlot pools ONE button per container
-- (see SlotsAvailable), so the ladder is one container and two textures per
-- rule. The 10-per-level pooling that made chains expensive belongs to the
-- older AddAuraGroup path, which is now the fallback.
--
-- Ordering is by DRAW SUBLEVEL, never frame level. Aura buttons report a
-- secret frame strata and refuse SetFrameLevel while auras are secret, so
-- nothing about the hierarchy can be relied on to sort two of them -- but a
-- single global ladder of sublevels sorts every piece regardless of which
-- frame it sits on:
--
--   wash 1, cover 1, wash 2, cover 2, ...   bottom to top
--
-- cover k must beat its own wash k, and wash k+1 must beat cover k (it is lit
-- while cover k is up -- that is precisely the state it describes). Both fall
-- out of the interleave. See MissingWashSublevel / MissingCoverSublevel.

-- The ladder's sublevel budget. OVERLAY runs -8..7; 6 and 7 are the
-- border/outline band (see PlaterRankSublevels), so the ladder gets -8..5.
-- Two sublevels per rule -- its wash and its cover, interleaved -- which is
-- what caps the ladder rather than any cost.
local MISSING_SUBLEVEL_MIN = -8
local MISSING_SUBLEVEL_MAX = 5
NS.MAX_MISSING_RULES =
  math.floor((MISSING_SUBLEVEL_MAX - MISSING_SUBLEVEL_MIN + 1) / 2)

local function MissingWashSublevel(rank)
  return MISSING_SUBLEVEL_MIN + 2 * (rank - 1)
end
local function MissingCoverSublevel(rank)
  return MISSING_SUBLEVEL_MIN + 2 * (rank - 1) + 1
end

-- Four edges of a rectangle. Each is pinned to two corners of the health bar
-- and given a thickness on its short axis; the offsets are unit vectors so
-- one number (grow-out distance) drives all four consistently.
local BORDER_SIDES = {
  { side = "top",    a = "TOPLEFT",     b = "TOPRIGHT",    ax = -1, ay =  1, bx =  1, by =  1, vertical = false },
  { side = "bottom", a = "BOTTOMLEFT",  b = "BOTTOMRIGHT", ax = -1, ay = -1, bx =  1, by = -1, vertical = false },
  { side = "left",   a = "TOPLEFT",     b = "BOTTOMLEFT",  ax = -1, ay =  1, bx = -1, by = -1, vertical = true  },
  { side = "right",  a = "TOPRIGHT",    b = "BOTTOMRIGHT", ax =  1, ay =  1, bx =  1, by = -1, vertical = true  },
}


-- Lifetime counters. WoW has no API to destroy a frame or texture, so
-- everything created here is resident until /reload -- retiring a rig only
-- disables and hides it. Comparing what has been created against what is
-- currently live is the only way to see that accumulation.
NS.stats = { containers = 0, textures = 0, rebuilds = 0 }

local function CreateBarTexture(owner, healthBar, sublayer, expand)
  local tex = owner:CreateTexture(nil, "OVERLAY", nil, sublayer or 0)
  NS.stats.textures = NS.stats.textures + 1
  return AnchorToFill(tex, healthBar, expand)
end

local function CreateMissingCoverTexture(owner, healthBar, sublayer, expand)
  local tex = owner:CreateTexture(nil, "OVERLAY", nil, sublayer or 0)
  NS.stats.textures = NS.stats.textures + 1
  return AnchorToMissingFill(tex, healthBar, expand)
end

-- Small curated set of tileable overlay patterns, shipped as plain white
-- TGA masks (opaque where the pattern is "on", semi-transparent where it is
-- "off") under media/textures. A rule picks one via `fillTexture`; nil/"auto"
-- means "no library pattern" -- see ApplyRuleFill below for what that falls
-- back to. Vertex colour does the tinting, so one greyscale file works for
-- every rule that chooses it, at whatever colour that rule has.
--
-- Each entry knows its own native tile size in PIXELS, because the two
-- shapes in this library are not interchangeable:
--   * the isotropic ones (dots, chevron, crosshatch, checker) are a small
--     square motif meant to repeat in a grid, so they tile on both axes;
--   * the stripe banners are one long band that already spans a bar's full
--     height by design (400x48, used from EllesmereUI) -- tiling THOSE
--     vertically would repeat a partial, cropped slice of the band rather
--     than showing the whole diagonal, which is what actually produced the
--     "only stretches horizontally" symptom. tileVertical = false instead
--     stretches the full band to the bar's height every time, same as the
--     source art was drawn to be used.
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
  -- Indexed once instead of scanned per texture. The library is static, so
  -- this could be built at load -- it lives in the same cache purely so there
  -- is one place that clears everything derived from configuration.
  local index = fillCacheEnabled and fillCache.textureIndex
  if not index then
    index = {}
    for _, entry in ipairs(NS.FillTextures) do index[entry.key] = entry end
    if fillCacheEnabled then fillCache.textureIndex = index end
  end
  return index[key]
end

-- Bar textures from LibSharedMedia, used by the SOLID overlay.
--
-- Its own rule field (rule.barTexture) rather than sharing rule.fillTexture
-- with the pattern library, because the two overlays are separate choices a
-- rule can hold at once: pick a bar texture for Solid Overlay, switch to
-- Texture Overlay to try a stripe, switch back, and your bar texture is still
-- there. One shared field would silently destroy whichever choice you were
-- not currently looking at.
--
-- These are NOT like the bundled patterns. A LibSharedMedia statusbar is
-- drawn to be stretched across a bar once (that is what a status bar texture
-- is), not tiled at a fixed pixel size, so ApplyRuleFill anchors it to the
-- FILL like a solid colour -- stretching with health, no tiling, no bar-frame
-- anchor, no crop mask.

-- Resolved file path for a bar-texture name, or nil. Nil also covers "the
-- addon that supplied this texture is gone" -- a user can uninstall the media
-- pack a saved rule points at, and that has to degrade to a flat colour
-- rather than erroring on every nameplate.
function NS.BarTexturePath(name)
  if type(name) ~= "string" or name == "" then return nil end
  -- Keyed by NAME, so it stays correct when a rule switches texture -- only
  -- the name-to-path lookup is cached, not the rule's choice. `false` is the
  -- miss marker: nil cannot be distinguished from "not looked up yet".
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

-- Every registered bar texture, as { name = , path = }, sorted by name.
-- Whatever the user has installed -- SharedMedia, ElvUI, WeakAuras, Plater
-- and so on all register into the same table, so this grows with their setup
-- and ships nothing extra.
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

-- A plain opaque rectangle, used as a MASK rather than drawn directly: a
-- MaskTexture's own alpha channel decides how much of whatever it is masking
-- shows through, and a solid white bitmap is fully-opaque everywhere, so the
-- crop it produces is exactly its own anchored rectangle -- no more, no less.
--
-- Created on `tex`'s own owner (an aura button on a busy plate), never on the
-- health bar or anywhere else: masks made on one secure aura button and used
-- on a texture belonging to a DIFFERENT one are refused once auras are
-- secret ("AddMaskTexture rejects another button's mask as a forbidden
-- object" -- see the AttachContainer comment above). Owning it locally avoids
-- that path entirely instead of relying on it happening to work.
--
-- Anchored with NO inset, unlike the tint itself: this mask's only job is to
-- track the fill's live health-percent edge, and the tint's own anchor
-- already handles clearing space for a border. Intersecting a tighter rect
-- (the tint, inset) with a looser one (this mask, flush) always yields the
-- tighter of the two on every side, so the two never fight each other.
local function EnsureOwnFillMask(tex, healthBar)
  local mask = tex.ptFillMask
  if not mask then
    local host = tex:GetParent()
    mask = host:CreateMaskTexture(nil, "OVERLAY")
    -- No wrap-mode args: this mask is always a flat 1:1 rectangle, never
    -- tiled, so there is nothing for a wrap mode to do -- and MaskTexture's
    -- SetTexture does not necessarily take the same argument shape as a
    -- plain Texture's, so the fewer assumptions here the better.
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

-- Adds or removes the shared fill mask, tracking current state on the
-- texture itself so repeat calls (every recolour, every appearance change)
-- do not double-add or remove-what-was-never-added.
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

-- Paints a rule's bar tint. "solid" (the original, and the fallback if
-- anything below fails) is a flat colour, anchored straight to the fill --
-- stretching with health is exactly right for a flat colour, which looks
-- identical at any size. "texture" has two sources:
--   * a library pattern (rule.fillTexture set) -- anchored to the BAR FRAME
--     instead, which does not resize as health changes, then cropped to the
--     fill's current edge with a mask. Tiled at a fixed pixel size this way,
--     so it reads as a texture whose tiles stay a constant size as health
--     drops, rather than the same fixed tile count squishing thinner;
--   * otherwise the host bar's OWN art -- atlas or texture path, its
--     tex-coords -- copied onto our texture and anchored to the fill exactly
--     like solid, so whatever pattern the nameplate addon draws (a gradient,
--     a hash overlay) keeps showing through exactly as THEY draw it, health
--     stretch included -- it is a copy of their own live art, not a tile.
-- Every branch re-anchors and re-masks unconditionally, every call, rather
-- than assuming whatever a previous call left behind: fillStyle is a Live
-- (no-rebuild) change, so the same texture object has to be able to swap
-- cleanly between all three without a stale anchor or a leftover mask from
-- whichever mode it was in a moment ago.
local function ApplyRuleFill(tex, healthBar, rule, expand)
  local color = rule and rule.color or NS.DefaultColor()

  -- SOLID OVERLAY with a bar texture chosen. Anchored to the FILL, not the
  -- bar frame: these are drawn to be stretched across a bar once, so tiling
  -- one at fixed pixel size (what the bundled patterns want) would repeat art
  -- that was never meant to repeat. Stretching with health is right here for
  -- the same reason it is right for a flat colour -- there is no motif whose
  -- on-screen size has to stay constant.
  if rule and rule.fillStyle ~= "texture" then
    local barPath = NS.BarTexturePath(rule.barTexture)
    if barPath then
      local ok = pcall(function()
        tex:SetTexture(barPath)
        -- Reset explicitly: this same texture object may have been tiling a
        -- pattern a moment ago (fillStyle/fillTexture are Live changes), and
        -- a leftover tiling tex-coord would sample a crop of this file rather
        -- than the whole thing.
        tex:SetTexCoord(0, 1, 0, 1)

        AnchorToFill(tex, healthBar, expand)
        SetFillMasked(tex, healthBar, false)

        tex:SetVertexColor(color.r, color.g, color.b)
        tex:SetAlpha(color.a or 1)
      end)
      if ok then tex.ptTexturedFill = true return end
      -- Fall through to the flat colour below on any failure -- a media pack
      -- the user uninstalled leaves a saved name pointing at nothing.
    end
  end

  if rule and rule.fillStyle == "texture" then
    local library = NS.FillTextureByKey(rule.fillTexture)
    if library then
      local ok = pcall(function()
        -- The tiling args are booleans (true = REPEAT), not strings -- a
        -- string here is a type error the client rejects, which used to trip
        -- this pcall and fall straight through to solid every time.
        tex:SetTexture(library.path, true, true)
        local okW, w = pcall(healthBar.GetWidth, healthBar)
        local okH, h = pcall(healthBar.GetHeight, healthBar)
        -- Tiled at each pattern's own native pixel size -- see NS.FillTextures
        -- for why that differs by entry.
        local repX = math.max(1, (okW and w or 100) / library.tileW)
        local repY
        if library.tileVertical then
          repY = math.max(1, (okH and h or 10) / library.tileH)
        else
          -- Exactly one span, full [0,1] -- NOT a repeat count under 1. A
          -- fractional vMax here would sample a cropped sliver off the top
          -- of the source and stretch just that sliver to fill the bar,
          -- which is what made the vertical axis look wrong before: the
          -- pattern seemed to only ever "stretch" because you were always
          -- looking at a stretched crop, never the whole band.
          repY = 1
        end
        tex:SetTexCoord(0, repX, 0, repY)

        AnchorToBarFrame(tex, healthBar, expand)
        SetFillMasked(tex, healthBar, true)

        tex:SetVertexColor(color.r, color.g, color.b)
        tex:SetAlpha(color.a or 1)
      end)
      if ok then tex.ptTexturedFill = true return end
      -- Fall through to solid on any failure -- a forbidden read, a bar with
      -- no fill texture yet -- rather than leaving the tint looking however
      -- it happened to be left by whatever drew it last.
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
  -- What this texture ACTUALLY ended up painted as, which is not always what
  -- the rule asked for -- every branch above falls through to here when its
  -- source is unavailable. ApplyRuleColor needs the truth, not the intent:
  -- recolouring a flat SetColorTexture through SetVertexColor (or the
  -- reverse) silently does nothing, and the colour picker would appear dead.
  tex.ptTexturedFill = false
end
NS.ApplyRuleFill = ApplyRuleFill

-- Cheap recolour, for a hot path that ApplyRuleFill is not: the colour
-- picker calls its swatchFunc/opacityFunc on every frame you drag it, and
-- that reaches NS.ApplyTintColors unthrottled -- no debounce, every tint on
-- every rig, every frame. Before texture fills existed that loop was one
-- SetColorTexture per tint, which is nothing. Routing it through the full
-- ApplyRuleFill would mean a texture-mode tint re-picking its file, redoing
-- its tex-coord math, and re-anchoring, 60 times a second, across every
-- plate on screen, to end up with a colour that was the only thing that
-- actually changed. This does only that: no texture reassignment, no
-- tex-coords, no anchor, no mask -- all of which were already set correctly
-- the moment fillStyle/fillTexture last changed, by ApplyRuleFill itself,
-- and none of which a colour edit touches.
local function ApplyRuleColor(tex, rule)
  local color = rule and rule.color or NS.DefaultColor()
  -- Set by ApplyRuleFill to whatever it actually managed to paint. Preferred
  -- over re-deriving it from the rule, because a rule can ask for a texture
  -- and get a flat colour anyway (missing media, forbidden read) -- and
  -- picking the wrong recolour call for what is really on the texture is a
  -- silent no-op, i.e. a colour picker that does nothing.
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

-- The color every "Cover missing health" texture uses, wherever it is
-- created. One shared getter so the engine, Test Mode, and the Options
-- preview can never disagree about what "missing" looks like.
function NS.MissingCoverColor()
  return (NS.db and NS.db.tints and NS.db.tints.missingCoverColor)
    or { r = 0.08, g = 0.08, b = 0.08, a = 0.95 }
end

-- Single-call version of the missing-cover feature, for callers that own
-- exactly one texture rather than a per-rig list -- Test Mode and the
-- Options preview stage, neither of which goes through BuildCombination.
-- A flat configured color, deliberately NOT a copy of the bar's own fill:
-- that read as "still full health" instead of "missing", which is the
-- opposite of the point. Anchors and shows/hides in one call, mirroring how
-- NS.ApplyRuleFill already works as a one-shot for the same two callers.
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

local function BuildRule(rig, healthBar, rule, level, needsUnderlay, overdraw, tintSublevel, underlaySublevel, borderSublevel, missingCoverSublevel)
  tintSublevel = tintSublevel or 0
  underlaySublevel = underlaySublevel or -1
  borderSublevel = borderSublevel or 7
  -- Strictly above the tint, not just spatially separate: a texture-mode
  -- fill's mask can leave an unclipped sliver right at the live edge, and
  -- without a firm sublevel gap the cover's win there is undefined.
  missingCoverSublevel = missingCoverSublevel or (tintSublevel + 2)
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
    -- Refuse rather than build something that can only fire by luck.
    record.unsupported = true
    return record
  end

  -- A rule with neither half enabled paints nothing, so building its
  -- containers is pure cost. Flagged rather than silently skipped, so the
  -- options panel can say why the rule does nothing.
  if rule.barEnabled == false and not (rule.border and rule.border.enabled) then
    record.inert = true
    return record
  end

  record.spellCount = #spells

  -- One (host, mask...) combination's worth of textures. Split out of the
  -- pump so it can also run inside initializeFrame, where the aura button is
  -- still touchable -- from a timer it is a forbidden object and every call
  -- here is refused.
  local function BuildCombination(stack)
    local host = stack[1]

    -- Underlay: an opaque copy of the bar beneath this rule's tint, so
    -- this rule masks lower-priority ones instead of blending with
    -- them. Only built when a lower rule can actually match at the
    -- same time — otherwise it is pure waste.
    -- Only when this rule actually paints the BAR. A border-only
    -- rule would otherwise still stamp an opaque copy of the health bar
    -- to mask lower rules -- blanking the bar it was deliberately not
    -- colouring, and hiding any lower rule's tint underneath it.
    if needsUnderlay and record.rule.barEnabled ~= false then
      local underlay = CreateBarTexture(host, healthBar, underlaySublevel, UNDERLAY_OVERDRAW + record.overdraw)
      for index = 2, #stack do underlay:AddMaskTexture(stack[index]) end
      table.insert(record.underlays, underlay)
    end
    -- The bar tint is now optional: a rule may colour the border only.
    if record.rule.barEnabled ~= false then
      local tint = CreateBarTexture(host, healthBar, tintSublevel, record.overdraw)
      ApplyRuleFill(tint, healthBar, record.rule, record.overdraw)
      for index = 2, #stack do tint:AddMaskTexture(stack[index]) end
      table.insert(record.tints, tint)
    end

    -- Opaque cover for the MISSING side of the bar, in the shared "missing"
    -- color (NS.MissingCoverColor) rather than a copy of the bar's own fill
    -- -- a copy read as "still full health", the opposite of the point.
    -- Deliberately ABOVE the tint's own sublevel (missingCoverSublevel), not
    -- sharing it: the two are clipped to opposite sides of the live fill
    -- edge, but a texture-mode fill is only MASKED down to that edge rather
    -- than physically sized to it, and the mask can leave an unclipped sliver
    -- right at the boundary. Sharing a sublevel left that sliver's winner
    -- undefined; being strictly above guarantees the cover wins it.
    if record.rule.barEnabled ~= false and record.rule.missingCover then
      local cover = CreateMissingCoverTexture(host, healthBar, missingCoverSublevel, record.overdraw)
      local mc = NS.MissingCoverColor()
      cover:SetColorTexture(mc.r, mc.g, mc.b, mc.a)
      for index = 2, #stack do cover:AddMaskTexture(stack[index]) end
      table.insert(record.missingCovers, cover)
    end

    -- Border: four edge textures on the same host, carrying the same
    -- masks, so it is gated identically to the bar tint.
    --
    -- Textures rather than a BackdropTemplate frame. A frame parented to
    -- an aura button is silently refused -- verified A/B against this,
    -- where the frame route drew nothing and the texture route worked.
    -- Textures are also maskable, so this one path covers combo rules
    -- too; a frame never could.
    local border = record.rule.border
    if border and border.enabled then
      local bc = border.color or { r = 1, g = 1, b = 1, a = 1 }
      local t = math.max(1, math.min(8, border.thickness or 2))
      -- Positive grows into the bar, negative out past its edge. Growing
      -- in never fights the nameplate addon's own border; growing out
      -- reads as a halo around the plate.
      local pad = math.max(0, math.min(12, border.padding or 0))
      -- Displacement of the border's OUTER edge from the bar's edge.
      -- Growing out, the band sits beyond the bar and must clear its own
      -- thickness as well as the padding; growing in, padding just
      -- pushes it further inside.
      local out = (border.grow == "OUT") and (t + pad) or -pad

      for _, side in ipairs(BORDER_SIDES) do
        -- Sublayer 7 normally, the top of OVERLAY -- the outermost thing
        -- this addon draws, so anything drawn later on the same host (the
        -- pandemic flash, a second rule's replica) cannot land on top of it.
        -- On a Plater bar 7 is reserved for Plater's own name text (see
        -- PlaterTintSublevel), so borderSublevel comes in one step lower
        -- there instead.
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

    -- Pandemic: AddPandemicRegion hands the engine a region it reveals
    -- only while the aura is inside its refresh window. Entirely
    -- declarative — no duration read, no curve, no polling. The region
    -- carries this rule's masks too, so on a combo rule it means "all
    -- debuffs present AND the host one is expiring".
    -- Single-debuff rules only. A flash region doubles a rule's texture
    -- count, which is fine at ~10 but ruinous at the ~1000 a 3-debuff
    -- rule already costs. Refresh timing also matters most on a plain
    -- DoT, where you are deciding whether to reapply it.
    local pandemic = NS.db.tints.pandemic
    if pandemic and pandemic.enabled and record.spellCount == 1 and host.AddPandemicRegion then
      local pc = pandemic.color or { r = 1, g = 1, b = 1, a = 0.45 }
      local region

      -- AddPandemicRegion only shows and hides — it has no notion of a
      -- pulse. To animate, wrap the flash in a frame we own and loop an
      -- alpha animation on it forever. We never learn when the window
      -- opens; the engine simply reveals an already-pulsing region.
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

      -- Static fallback: animation groups on a forbidden parent may be
      -- refused, and a steady flash still beats nothing.
      if not region then
        -- One above the tint it flashes over, whatever sublevel that tint
        -- landed on (0+1 = 1, same as before, on every non-Plater bar).
        local flash = CreateBarTexture(host, healthBar, tintSublevel + 1)
        flash:SetColorTexture(pc.r, pc.g, pc.b, pc.a)
        for index = 2, #stack do flash:AddMaskTexture(stack[index]) end
        region = flash
      end

      -- Hidden until the engine decides otherwise; AddPandemicRegion
      -- takes ownership of its visibility from here.
      region:Hide()
      host:AddPandemicRegion(region)
      table.insert(record.pandemics, region)
    end
  end

  -- A chain of containers, one per debuff, each nested inside a button of the
  -- one before it. The tint hangs off the LAST link, so it renders only when
  -- every ancestor button is shown -- which is exactly "all these debuffs are
  -- present". Ancestry is the AND.
  --
  -- This replaces mask intersection, which cannot work here. A texture may
  -- only carry masks owned by its own button: AddMaskTexture rejects another
  -- button's mask as a forbidden object, just as CreateTexture rejects another
  -- button as a forbidden self. Both routes across buttons are closed once
  -- auras are secret, and the mask version only ever verified outside an
  -- instance, where nothing is forbidden.
  --
  -- Every touch here is same-button: the nested container is created inside
  -- its parent button's own callback, and the tint inside its own button's.
  --
  -- Cost is containers^depth. Two debuffs is 1 + 10 = 11 containers and 100
  -- tints per plate -- the same texture count as the mask version. Three is
  -- 111 containers, which has not held up in practice.
  local AttachContainer

  AttachContainer = function(parent, depth)
    local okFrame, frame = pcall(CreateFrame, "AuraContainer", nil, parent, "CustomAuraContainerTemplate")
    if not okFrame or not frame then
      record.failures = record.failures + 1
      record.lastError = record.lastError or ("container at depth " .. depth .. ": " .. tostring(frame))
      return
    end

    NS.stats.containers = NS.stats.containers + 1

    frame:SetEnabled(false)
    -- Anchored to the health bar, never to the parent button. Ours-to-theirs
    -- anchoring is refused; theirs-to-ours is fine.
    pcall(frame.SetAllPoints, frame, healthBar)

    local key = "M" .. depth
    local useSlot = SlotsAvailable(frame)
    local Register = useSlot and frame.AddAuraSlot or frame.AddAuraGroup
    Register(frame, key, "HARMFUL|PLAYER", {
      initializeFrame = function(button)
        if depth == 1 then
          table.insert(record.hosts, button)
        end
        -- Every depth, not just the first. BuildCombination always attaches
        -- its textures to the DEEPEST button in the chain (stack[1] there is
        -- whichever button triggered the final callback) -- for a
        -- single-debuff rule that IS the depth-1 button, but for a combo
        -- rule it is a nested button this call never used to reach, left at
        -- whatever level the pooled aura-button template happened to default
        -- to. That default being "high enough" was invisible everywhere this
        -- addon only needed to sit somewhere above the bar; it stopped being
        -- invisible the moment a Plater bar needed an EXACT level (see
        -- NS.BaseLevelFor) instead of just a big enough one.
        -- Refused while auras are secret; worth doing when they are not.
        pcall(button.SetFrameLevel, button, level)
        record.dirty = true

        if depth < record.spellCount then
          -- One nested container per pooled button. It must hang off EVERY
          -- button, not just the first: the engine displays an arbitrary one
          -- and a chain missing from the button it picked fails silently.
          AttachContainer(button, depth + 1)
          return
        end

        record.combos = (record.combos or 0) + 1
        if record.combos >= MAX_TINTS_PER_RULE then
          record.truncated = true
          return
        end
        table.insert(record.tintHosts, button)
        -- No masks: the ancestry already gates this to all debuffs present.
        local okBuild, errBuild = pcall(BuildCombination, { button })
        if not okBuild then
          record.failures = record.failures + 1
          record.lastError = record.lastError or tostring(errBuild)
        end
      end,
    })

    -- Not just the ID in the rule: also every ID the Cooldown Manager links
    -- to it. An ability whose aura is a separate spell (Rend casts 772 and
    -- applies 388539) would otherwise filter on an ID that never lands.
    -- The set costs nothing extra -- the engine still matches at most one.
    local spellID = spells[depth]
    local ids = (NS.RelatedSpellIDs and NS.RelatedSpellIDs(spellID)) or { [spellID] = true }
    if useSlot then
      -- No MaxFrameCount: a slot is one frame by definition, which is the
      -- entire point. Setting the cap on a group never sized its pool anyway
      -- (measured: 10 either way), it only limited what was displayed.
      frame:SetAuraSlotCandidateFilters(key, { includeSpellIDs = ids })
    else
      frame:SetAuraGroupCandidateFilters(key, { includeSpellIDs = ids })
      frame:SetAuraGroupMaxFrameCount(key, 1)
    end

    table.insert(record.containers, frame)
    NS.ActivateContainer(rig, frame, record)
  end

  AttachContainer(healthBar, 1)

  return record
end

-------------------------------------------------------------------------------
-- Fill-path benchmark
--
-- Measures the ONE hot loop -- ApplyRuleFill over N textures -- on a synthetic
-- health bar, with no nameplates, no aura containers and no group required.
-- That is the whole point: the path that costs the most in a raid is the path
-- that is hardest to observe in a raid, and everything it does is a function
-- of a texture, a bar and a rule rather than of anything secure.
--
-- What this DOES measure: our own Lua -- the LSM fetch, the library scan, the
-- border-rule walk, the inset arithmetic. That is exactly what the fill cache
-- changed, so it is the right instrument for judging it.
--
-- What it does NOT measure: the client's own cost inside SetPoint, SetTexture
-- and AddMaskTexture. Those are C calls we can only time in aggregate, and
-- they scale with real plate count in ways a single synthetic bar will not
-- show. For that, profile in game.
--
-- The frame and textures are created ONCE and reused for the session. WoW
-- cannot destroy either, so a bench that allocated per run would be a leak
-- that grew every time you measured for one.
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

-- Returns milliseconds for `iterations` passes over `count` textures.
function NS.BenchFillPath(count, iterations, rule)
  count = math.max(1, count or 100)
  iterations = math.max(1, iterations or 20)
  rule = rule or (NS.db and NS.db.tints and NS.db.tints.rules and NS.db.tints.rules[1])
  if not rule then return nil, "no rule to measure -- create one first" end

  local textures = EnsureBench(count)
  -- One untimed pass, so the first run does not pay for texture setup and
  -- whatever the client caches on first use of a path.
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

  -- Opt-in: drop rules this character cannot possibly trigger.
  --
  -- Off by default, and gated on positive evidence only (see NS.CanApplyAura),
  -- because the cost of being wrong is a rule that silently stops working. The
  -- rules stay in the config and in the options window either way -- this only
  -- decides what gets BUILT on the plates.
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

  -- Each module is gated on its own flag, so either can run without the other.
  --
  -- Missing rules are split out before anything below touches the list. They
  -- paint an edge band, not the bar body, so they have no overlap to arbitrate
  -- and nothing to underlay -- and leaving one in the presence list would have
  -- it consume a frame-level band and a rank-inset step for geometry it never
  -- uses, quietly shrinking the real tints below it. Relative order is
  -- preserved within each group, so the priority field still means what the
  -- options window says it does: for bands, which slot sits nearest the bar.
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

  -- Presence rules start ONE BAND above the rig's base, leaving that base for
  -- the missing ladder underneath them.
  --
  -- A lit missing wash and a matching presence tint want the same pixels, and
  -- the missing one is lit by DEFAULT -- nothing is applied yet -- so putting
  -- it on top made it cover presence tints almost all the time. Presence wins
  -- instead: the reminder shows on mobs where no rule matches, and steps aside
  -- once one does.
  local ruleBase = isPlater and rig.baseLevel or (rig.baseLevel + LEVELS_PER_RULE)

  -- How far each rank is inset, resolved as a ladder rather than as a flat
  -- step per rank. A rule only has to be strictly smaller than a HIGHER rule
  -- that can be lit at the same time and does NOT cover it -- where the higher
  -- rule does cover it, its underlay masks this one completely and no size
  -- difference is needed (see RANK_INSET).
  --
  -- In the ordinary setup that is most rules: NS.SortRules puts the combo
  -- above its own singles, and a combo covers every single it contains, so
  -- they all sit flush at zero. Only genuinely disjoint rules -- Haunt beside
  -- Agony, neither a subset of the other -- step down, and then only past each
  -- other rather than past the whole list.
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

  for index, rule in ipairs(ordered) do
    -- On a Plater bar every rule is pinned to the bar's own frame level (see
    -- NS.BaseLevelFor), so rank has no frame-level room to work with -- it is
    -- expressed as a sublevel instead, via PlaterRankSublevels. Every other
    -- bar is untouched: same frame-level step as always, and the default
    -- sublevels BuildRule falls back to.
    local level, tintSublevel, underlaySublevel, missingCoverSublevel
    if isPlater then
      level = rig.baseLevel
      tintSublevel, underlaySublevel, missingCoverSublevel = PlaterRankSublevels(index)
    else
      level = ruleBase + (count - index) * LEVELS_PER_RULE
    end
    -- A rule needs to mask what is beneath it only if some lower-priority
    -- rule can match at the same moment, which happens exactly when that
    -- rule's debuffs are a subset of this one's.
    local needsUnderlay = false
    for lower = index + 1, count do
      if NS.RuleCovers(rule, ordered[lower]) then needsUnderlay = true break end
    end
    -- Negative expand = inset. Resolved above, so a rule that nothing can leak
    -- against stays flush with the fill however far down the list it is.
    local overdraw = -(insets[index] or 0)
    local record = BuildRule(rig, healthBar, rule, level, needsUnderlay, overdraw,
      tintSublevel, underlaySublevel, isPlater and 6 or nil, missingCoverSublevel)
    -- What NS.AnchorTints replays on every reposition. Stored rather than
    -- recomputed there, so the two can never disagree about which band this
    -- record belongs to.
    record.levelOffset = level - rig.baseLevel
    table.insert(rig.rules, record)
  end

  -- Border rules, in a level band above every bar rule. Their own priority
  -- among themselves, and never underlaid: a border masks nothing, so the top
  -- bar rule and the top border rule both show. That is the point of the two
  -- lists rather than two halves of one rule.
  local borders = NS.db.tints.borderEnabled ~= false
    and Castable(NS.GetOrderedBorderRules()) or {}
  local bcount = #borders
  local borderBase = isPlater and rig.baseLevel or (ruleBase + (count + 1) * LEVELS_PER_RULE)
  for index, rule in ipairs(borders) do
    local level = isPlater and rig.baseLevel or (borderBase + (bcount - index) * LEVELS_PER_RULE)
    local record = BuildRule(rig, healthBar, rule, level, false, nil, nil, nil, isPlater and 6 or nil)
    record.levelOffset = level - rig.baseLevel
    table.insert(rig.rules, record)
  end

  -- The missing ladder, in the rules' own priority order.
  --
  -- Single-debuff only (NS.MAX_MISSING_CONDITIONS). Rank k already spends a
  -- chain level on every rule above it plus one on its own debuff; a second
  -- condition would need another level interleaved into a sublevel budget with
  -- no room for it. The options window never offers a second debuff on a
  -- missing rule, so anything caught here is data that predates the feature --
  -- skipped and reported rather than half-built.
  local ladder = {}
  for _, rule in ipairs(missingRules) do
    if #(rule.conditions or {}) == 1 and #ladder < NS.MAX_MISSING_RULES then
      ladder[#ladder + 1] = rule
    end
  end

  -- Rank 1's wash first, so the cover the ladder is about to build has
  -- something underneath it.
  --
  -- The ladder sits at the rig's base, BELOW every presence rule (see
  -- ruleBase). Its own internal order still works: the covers live on aura
  -- buttons, whose secret strata beats any frame level, so a cover always
  -- wins over the wash it hides -- while a presence tint, also on an aura
  -- button but at a higher frame level, wins over the whole ladder.
  --
  -- On a Plater bar there is no frame-level room at all: everything is pinned
  -- to the bar's own level so Plater's sublevel-7 name text survives (see
  -- NS.BaseLevelFor). The ladder takes the BOTTOM of the sublevel budget and
  -- presence ranks take the top, which separates them until a deep presence
  -- stack and a deep ladder meet in the middle -- roughly four of each.
  local missingLevel = rig.baseLevel
  -- BEFORE BuildMissingWash, which asks LadderCombatAllows for the wash's
  -- opening state -- and that reads rig.missingLadder. Set afterwards, as it
  -- used to be, the question was answered against the PREVIOUS build's ladder.
  rig.missingLadder = ladder
  -- Likewise cleared before anything can consult it: a rebuild that drops to
  -- zero missing rules must not leave the gate working off the last one.
  rig.missingGateOpen = nil
  NS.BuildMissingWash(rig, healthBar, missingLevel, ladder[1])
  -- Cleared before the branch below re-sets it, so a rebuild that drops to
  -- zero missing rules doesn't leave the poll working off last build's record.
  rig.missingLadderRecord = nil
  if #ladder > 0 then
    local record = NS.BuildMissingBarStack(rig, healthBar, ladder, missingLevel)
    record.levelOffset = missingLevel - rig.baseLevel
    table.insert(rig.rules, record)
    -- Direct reference for NS.UpdateMissingCombatGate, which needs the root
    -- container on every poll tick and would otherwise have to search
    -- rig.rules for the one record carrying missingStack.
    rig.missingLadderRecord = record
  end
  rig.missingLevelOffset = missingLevel - rig.baseLevel

  -- Settle the gate now rather than waiting up to a quarter second for the
  -- first poll tick. Without this a ladder that should open closed is briefly
  -- lit on every plate that spawns mid-pull, which is exactly the flicker the
  -- option exists to prevent.
  NS.UpdateMissingCombatGate(rig)

  -- Recorded for the same reason the rules' offsets are: NS.AnchorTints used
  -- its own arithmetic here too, and that copy did not match either.
  -- One band above the border rules, which are above every bar rule, which are
  -- above the missing ladder -- so the plate outline stays the outermost thing
  -- drawn.
  rig.outlineLevelOffset = isPlater and 0
    or ((borderBase - rig.baseLevel) + (bcount + 1) * LEVELS_PER_RULE)
  NS.BuildOutline(rig, healthBar, rig.baseLevel + rig.outlineLevelOffset)
end

-- The nameplate's own black border sits INSIDE the health bar's rect and below
-- our overlay layer, so a tint flush with the fill paints over it, and a tint
-- inset far enough to spare it exposes the bar's default colour around the
-- edge instead. Neither is acceptable: one loses the border, the other draws a
-- coloured halo.
--
-- So draw it ourselves. The border is present regardless of which rule is
-- active, which means it does not belong on an aura button at all -- it is not
-- conditional on anything. One frame per plate, four edges, always shown,
-- above every tint. Four textures per nameplate instead of four per
-- combination, and it covers the rank inset as well, since the band is drawn
-- from the bar edge inward across exactly the region a lower rule vacates.
-- Whether THIS missing rule's wash is allowed to show right now, given its
-- own "only while target is in combat" option. Always true for a rule that
-- doesn't use it, so a rule that never touches this setting is unaffected.
--
-- UnitAffectingCombat is PLAIN -- not secret, not gated -- so this is a real
-- read rather than the predicate/alpha-gate machinery everything else in
-- this file needs to infer state without observing it. The answer only ever
-- drives Shown() on a texture we created ourselves, the same as every other
-- post-hoc touch in this file (NS.AnchorTints re-colours these same washes
-- from outside their creation context already).
-- Whether the missing ladder's washes are allowed to show right now.
--
-- LADDER-WIDE, not per rule, and that is forced rather than chosen. Only one
-- wash is ever lit -- that is the ladder's whole invariant -- and which one
-- depends on aura state we are not allowed to read, so "apply the lit rule's
-- setting" is a question with no answer available to us.
--
-- The gate therefore engages only when EVERY rule in the ladder asks for it.
-- A mixed ladder fails toward SHOWING: a reminder that lights up when it
-- should not is visible and can be switched off, while one silently
-- suppressed is indistinguishable from the feature being broken.
--
-- UnitAffectingCombat is PLAIN -- not secret, not gated -- so this is a real
-- read rather than the inference machinery the rest of this file needs.
local function LadderCombatAllows(rig)
  local ladder = rig and rig.missingLadder
  if not ladder or #ladder == 0 then return true end
  for _, rule in ipairs(ladder) do
    if not rule.missingCombatOnly then return true end
  end
  local unit = rig.unit
  if not (unit and UnitAffectingCombat(unit)) then return false end
  return UnitAffectingCombat("player") and true or false
end
NS.LadderCombatAllows = LadderCombatAllows

-- Opens and closes that gate, from the 0.25s poll in Core.lua. Combat state
-- changes with no config event to hook, so this is polled rather than pushed.
--
-- ⚠ It does NOT touch the deep washes, and must not. Rank 2+ washes are
-- textures on SECURE AURA BUTTONS: creating one inside initializeFrame is
-- permitted, but SetShown on it later from this poll is refused outright --
--
--   calling 'SetShown' on bad self (Attempt to access forbidden object
--   from code tainted by an AddOn)
--
-- The engine reserves VISIBILITY on the objects it owns. It does not reserve
-- ENABLEMENT of a container we created: NS.SetTintsUnit calls SetEnabled and
-- SetUnit on nested containers, after the build, from exactly this kind of
-- tainted path, un-pcall'd, every time a plate is rebound.
--
-- So the gate is expressed the only way it can be -- disable the ROOT
-- container, and the whole chain below it goes with it, every cover and every
-- deep wash included. Which is precisely what ladder-wide means.
function NS.UpdateMissingCombatGate(rig)
  local allowed = LadderCombatAllows(rig)
  -- Edge-triggered. At 4Hz across every rigged plate, re-asserting an unchanged
  -- state would be the most frequent thing this addon does.
  if rig.missingGateOpen == allowed then return end
  rig.missingGateOpen = allowed

  -- Rank 1's wash lives on healthBar.ptMissingWash -- our frame, our texture,
  -- so visibility here is ours to set and always has been.
  local frame = rig.missingWash
  if frame and frame.wash then
    frame.wash:SetShown(allowed)
  end

  local record = rig.missingLadderRecord
  local root = record and record.root
  if not root then return end

  -- Preferred lever: plain visibility on the root container.
  --
  -- Hiding a frame neither tears the chain down nor re-runs initializeFrame,
  -- so it is instant and leaves nothing to rebuild. Disabling does both, which
  -- is why the guard above exists and why the gate felt laggy before.
  --
  -- Worth trying rather than assuming refused: the ROOT container's parent is
  -- the health bar, not an aura button, so it is not the case NS.RetireTints
  -- describes. Asked of the real object at the real moment, the same way
  -- SlotsAvailable settles the aura-slot API, because a cached guess made
  -- somewhere else has been wrong here before.
  if record.gateLever ~= "enabled" then
    if pcall(root.SetShown, root, allowed) then
      -- Set BEFORE the rebind below, which reads it.
      record.gateLever = "shown"
      -- Visibility is doing the gating now, so the container underneath must
      -- stay bound and enabled. Without this, a rebind that happened while the
      -- gate was shut would have left it disabled -- and the reopening path
      -- only calls SetShown, so nothing would ever switch it back on.
      NS.ActivateContainer(rig, root, record)
      return
    end
    record.gateLever = "enabled"
  end

  -- Fallback: enablement. Correct, but it re-initialises the buttons on the
  -- way back up, so it leans on the guard above to stay idempotent.
  if allowed then
    -- Back through ActivateContainer rather than SetEnabled(true): the unit
    -- binding and the show-on-target/focus opt-outs have to be re-applied,
    -- and that function is the one place that knows all three.
    NS.ActivateContainer(rig, root, record)
  else
    root:SetEnabled(false)
  end
end

-- Rank 1's wash -- the one piece of the ladder that is UNCONDITIONAL, and so
-- the one piece that cannot live on an aura button. Every deeper wash hangs
-- off the button above it instead (see NS.BuildMissingBarStack).
--
-- Kept on the health bar rather than on the rig, for the same reason
-- NS.BuildOutline's frame is: a rebuild replaces the rig table, and WoW cannot
-- destroy a frame, so one created per rebuild would accumulate for the
-- session. Health bars are pooled and finite, so this caps at one per plate.
function NS.BuildMissingWash(rig, healthBar, level, topRule)
  local frame = healthBar.ptMissingWash
  if not frame then
    frame = CreateFrame("Frame", nil, healthBar)
    healthBar.ptMissingWash = frame
  end
  rig.missingWash = frame
  frame:SetAllPoints(healthBar)
  pcall(frame.SetFrameLevel, frame, level)

  -- Test mode draws its own copy of every rule and stands in for the engine.
  -- A missing wash is the one visual that is lit BECAUSE nothing is applied,
  -- so without this it sits under the test overlay and reads as a test wash
  -- that will not clear. TestMode hides it per plate as well; this is what
  -- stops the next reposition putting it straight back and flickering.
  --
  -- Suppressed on every plate rather than only the ones test mode covers.
  -- Test mode is a transient diagnostic with a banner saying so, and a
  -- reminder that is honest on half the plates and stale on the other half is
  -- worse than one that is plainly off.
  if not topRule or (NS.TestModeActive and NS.TestModeActive()) then
    frame:Hide()
    return
  end

  -- Through ApplyRuleFill, so a missing rule honours exactly the same fill
  -- style, texture and colour a presence rule does. That matters more here
  -- than it does for a presence tint: this one is lit by DEFAULT on every
  -- plate, so its alpha and its art are what you actually look at.
  local tex = frame.wash
  if not tex then
    tex = frame:CreateTexture(nil, "OVERLAY", nil, MissingWashSublevel(1))
    NS.stats.textures = NS.stats.textures + 1
    frame.wash = tex
  end
  ApplyRuleFill(tex, healthBar, topRule, 0)
  tex:SetShown(LadderCombatAllows(rig))
  frame:Show()
end

-- The ladder. One chain, one container per rule, each filtering that
-- rule's own debuff; the button at depth k means "D1..Dk are all present" and
-- carries cover k plus wash k+1. Rank 1's wash is on our own frame, put there
-- by NS.BuildMissingWash above.
--
-- Returns one record for the whole ladder rather than one per rule: the
-- containers are a single nested structure and cannot be enabled, retired or
-- re-levelled independently of each other.
function NS.BuildMissingBarStack(rig, healthBar, rules, level)
  local record = {
    rule = rules and rules[1],
    missingStack = rules or {},
    containers = {}, tints = {}, underlays = {}, missingCovers = {},
    borders = {}, pandemics = {},
    hosts = {}, tintHosts = {}, built = {},
    -- Washes for rank 2 and deeper, keyed by rank. Rank 1's lives on our own
    -- frame, so it is deliberately absent here.
    washes = {},
    -- A cover has to hide its wash COMPLETELY -- the satisfied state is meant
    -- to be indistinguishable from a plain bar, and a leftover rim of colour
    -- is worse than no feature, since it never goes away.
    --
    -- Presence underlays get away with overdraw 0 because the rule beneath
    -- them is already inset further by RANK_INSET. Nothing insets a wash: the
    -- wash and its cover are anchored to the same rect on DIFFERENT frames, so
    -- rounding at the edges can leak a hairline of the wash. One pixel out
    -- costs nothing and removes it.
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
      record.failures = record.failures + 1
      record.lastError = record.lastError
        or ("missing ladder at rank " .. rank .. ": " .. tostring(frame))
      return
    end
    NS.stats.containers = NS.stats.containers + 1

    frame:SetEnabled(false)
    -- To the health bar, never to the parent button: ours-to-theirs anchoring
    -- is refused, theirs-to-ours is fine.
    pcall(frame.SetAllPoints, frame, healthBar)

    local key = "N" .. rank
    local useSlot = SlotsAvailable(frame)
    local Register = useSlot and frame.AddAuraSlot or frame.AddAuraGroup
    Register(frame, key, "HARMFUL|PLAYER", {
      initializeFrame = function(button)
        -- ⚠ This fires more than once for the same button.
        --
        -- The engine re-initialises a container's buttons when it is
        -- re-enabled, and the combat gate below does exactly that. Unguarded,
        -- every combat transition built a SECOND cover, a SECOND wash and a
        -- SECOND nested container on the same button -- the originals still
        -- present, still drawing, and no longer agreeing with the new ones.
        -- The symptom is a reminder that works intermittently and a texture
        -- count that climbs all fight.
        --
        -- Keyed on `record`, a fresh table per build, so a genuine rebuild
        -- still re-attaches. Plain field writes on an aura button are accepted
        -- even though its visibility is not -- see NS.RetireTints.
        if button.ptLadderRecord == record and button.ptLadderRank == rank then
          record.reinits = (record.reinits or 0) + 1
          return
        end
        button.ptLadderRecord, button.ptLadderRank = record, rank

        pcall(button.SetFrameLevel, button, level)
        table.insert(record.hosts, button)
        record.dirty = true

        -- This rule's cover: shown exactly while its own debuff is up, which
        -- is when its wash must stop showing. Pushed into `underlays` because
        -- that is the list NS.UpdateCovers keeps painted as a live replica of
        -- the host bar's art -- the same machinery a priority underlay uses,
        -- and for the same reason: it is restoring the bar, not colouring it.
        local cover = button:CreateTexture(nil, "OVERLAY", nil,
          MissingCoverSublevel(rank))
        NS.stats.textures = NS.stats.textures + 1
        -- record.overdraw, not UNDERLAY_OVERDRAW: see the note where it is
        -- set. NS.AnchorTints replays this as UNDERLAY_OVERDRAW +
        -- record.overdraw, so the two agree only if the same field is used.
        AnchorToFill(cover, healthBar, record.overdraw)
        table.insert(record.underlays, cover)

        -- The NEXT rule's wash, which is lit while everything above it is
        -- present -- exactly the state this button describes. It sits one
        -- sublevel above the cover just created, so it still shows through it.
        local nextRule = rules[rank + 1]
        if nextRule then
          local wash = button:CreateTexture(nil, "OVERLAY", nil,
            MissingWashSublevel(rank + 1))
          NS.stats.textures = NS.stats.textures + 1
          ApplyRuleFill(wash, healthBar, nextRule, 0)
          -- Deliberately unconditional. This texture cannot be re-shown or
          -- re-hidden after the callback returns -- it belongs to a secure
          -- aura button, and the poll is refused access to it. Its gating
          -- comes from the ROOT container being disabled instead, which takes
          -- the whole chain down with it. See NS.UpdateMissingCombatGate.
          wash:Show()
          record.washes[rank + 1] = wash
          -- The chain continues from THIS button, so the next container's
          -- button means "everything through rank+1 is present".
          AttachLevel(button, rank + 1)
        end
      end,
    })

    -- Every ID the Cooldown Manager links to this one, same as a normal rule:
    -- an ability whose aura is a separate spell would otherwise filter on an
    -- ID that never lands.
    local ids = (NS.RelatedSpellIDs and NS.RelatedSpellIDs(condition.spellID))
      or { [condition.spellID] = true }
    if useSlot then
      frame:SetAuraSlotCandidateFilters(key, { includeSpellIDs = ids })
    else
      frame:SetAuraGroupCandidateFilters(key, { includeSpellIDs = ids })
      frame:SetAuraGroupMaxFrameCount(key, 1)
    end

    table.insert(record.containers, frame)
    -- Named rather than taken as containers[1]: rank 1's initializeFrame can
    -- fire during Register above, which builds and inserts the rank-2
    -- container before this line runs for rank 1.
    if rank == 1 then record.root = frame end
    NS.ActivateContainer(rig, frame, record)
  end

  AttachLevel(healthBar, 1)
  return record
end

function NS.BuildOutline(rig, healthBar, level)
  local cfg = NS.db.tints or {}
  if cfg.plateOutline == false then
    if rig.outline then rig.outline:Hide() end
    return
  end

  -- Kept on the health bar, not the rig. A rebuild replaces the rig table, and
  -- a frame created per rebuild could never be reclaimed -- WoW cannot destroy
  -- one. Health bars are pooled and finite, so this caps at one per plate for
  -- the session however many times the config changes.
  local frame = healthBar.ptOutline
  if not frame then
    frame = CreateFrame("Frame", nil, healthBar)
    frame.edges = {}
    -- 7 normally; one step down on a Plater bar, where 7 is Plater's own
    -- name text (see PlaterTintSublevel) and every rule here is pinned to
    -- the bar's own frame level rather than stepped above it.
    local sublevel = NS.IsPlaterBar(healthBar) and 6 or 7
    for _ = 1, #BORDER_SIDES do
      table.insert(frame.edges, frame:CreateTexture(nil, "OVERLAY", nil, sublevel))
    end
    healthBar.ptOutline = frame
  end
  rig.outline = frame

  -- The caller's level assumes every tint host accepted the level it was
  -- given. Aura buttons do NOT: SetFrameLevel on one is refused while auras
  -- are secret (see MaxInsideBorder), which is exactly the case on a live
  -- nameplate. They keep whatever level the secure container handed them, and
  -- if that is above this frame the rule's fill draws on top of the plate's
  -- border -- the arithmetic says the outline is on top, the screen disagrees.
  --
  -- GetFrameLevel stays readable when SetFrameLevel is refused, so ask instead
  -- of assuming. Plater bars are excluded on purpose: everything there is
  -- pinned to one frame level and ordered by draw sublevel instead, so raising
  -- this frame would put the outline above Plater's own name text.
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
  -- Displacement from the health bar's own edge. Positive pulls the band
  -- inward, negative pushes it outward past the bar.
  --
  -- Needed because "the bar's edge" is not one thing. This frame is pinned to
  -- the health bar FRAME, while a tint is anchored to the fill TEXTURE inside
  -- it, and nameplate addons differ on how much room sits between the two --
  -- so a border drawn at zero can land under the addon's own art, or outside
  -- the part of the bar you can actually see. There is no value that is right
  -- everywhere, which is why it is a setting rather than a constant.
  local off = math.max(-8, math.min(8, cfg.plateOutlineOffset or 0))

  -- PixelUtil, not plain SetPoint/SetWidth: those place a texture at whatever
  -- fractional UI coordinate the math produces, and at most UI scale values
  -- that lands between physical pixels and blurs. PixelUtil rounds to the
  -- screen's actual pixel grid, which is what "pixel perfect" requires and
  -- plain positioning cannot give regardless of how clean the numbers look.
  local hasPixelUtil = PixelUtil and PixelUtil.SetPoint and PixelUtil.SetWidth and PixelUtil.SetHeight

  for index, side in ipairs(BORDER_SIDES) do
    local tex = frame.edges[index]
    if not PlateOutlineSide(side.side) then
      tex:Hide()
    else
    tex:SetColorTexture(c.r, c.g, c.b, c.a)
    tex:ClearAllPoints()
    -- Zero displacement: the band sits just inside the bar's edge, which is
    -- where the plate's own border was.
    -- ax/ay are unit vectors pointing OUT of the bar, so negating them moves
    -- the band inward for a positive offset.
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

  local okW, w = pcall(healthBar.GetWidth, healthBar)
  local okH, h = pcall(healthBar.GetHeight, healthBar)
  if okW and w and w > 0 then rig.barWidth = w end
  if okH and h and h > 0 then rig.barHeight = h end

  local isPlater = NS.IsPlaterBar(healthBar)

  -- Keep the outline above every rule and sized to the current bar.
  if rig.outline then
    NS.BuildOutline(rig, healthBar, baseLevel + (rig.outlineLevelOffset or 0))
  end

  for _, record in ipairs(rig.rules) do
    -- Replays the offset BuildTints recorded, rather than recomputing a level
    -- from the record's position in this table.
    --
    -- rig.rules holds BOTH lists, bar rules then border rules, and they are
    -- built with DIFFERENT formulas -- borders sit in a band above every bar
    -- rule (see borderBase). Recomputing here with the bar-rule formula alone
    -- re-leveled the border records by their index in the combined table, which
    -- dropped them out of that band and underneath the higher bar rules on the
    -- first reposition after a build. That is a target change or a bar resize,
    -- so it happened almost immediately and looked like the borders had simply
    -- never been on top -- for some rules and not others, depending on where
    -- they landed in the combined order.
    --
    -- An offset cannot drift from the build formula the way a second copy of
    -- the arithmetic did, because there is no second copy any more.
    local level = isPlater and baseLevel or (baseLevel + (record.levelOffset or 0))
    record.level = level
    if record.holder then
      record.holder:SetFrameLevel(level)
    end
    -- Only the root container of a chain can take a level; the nested ones
    -- are children of aura buttons and refuse it, hence the pcall.
    for _, frame in ipairs(record.containers) do
      pcall(frame.SetFrameLevel, frame, level)
    end
    for _, host in ipairs(record.hosts) do
      pcall(host.SetFrameLevel, host, level)
    end
    -- The buttons that actually carry the tints -- for a combo rule these
    -- are nested deeper than record.hosts (see AttachContainer) and need
    -- releveling here too, or a reposition leaves them at whatever level
    -- they were built with.
    for _, host in ipairs(record.tintHosts or {}) do
      pcall(host.SetFrameLevel, host, level)
    end

    -- Re-apply the edge inset. Read at creation time, so without this a
    -- change to the slider would only reach textures built afterwards --
    -- exactly the kind of half-applied state that looks like a broken
    -- setting rather than a stale one.
    --
    -- Through ApplyRuleFill, not a bare AnchorToFill: a texture-mode tint is
    -- anchored to the BAR FRAME, not the fill (see ApplyRuleFill), and a
    -- blind AnchorToFill here would silently re-anchor it back to the fill
    -- on every reposition -- a bar resize, an edge-inset change -- undoing
    -- that and letting the pattern squish with health again.
    for _, tex in ipairs(record.tints) do
      pcall(ApplyRuleFill, tex, healthBar, record.rule, record.overdraw)
    end
    for _, tex in ipairs(record.underlays) do
      -- Same overdraw as at creation: without it every Reapply would quietly
      -- shrink underlays back to the tint's exact size and the hairline would
      -- return.
      pcall(AnchorToFill, tex, healthBar, UNDERLAY_OVERDRAW + (record.overdraw or 0))
    end
    for _, tex in ipairs(record.pandemics or {}) do
      pcall(AnchorToFill, tex, healthBar)
    end
    for _, tex in ipairs(record.missingCovers) do
      pcall(AnchorToMissingFill, tex, healthBar, record.overdraw)
    end
    -- Ladder washes. pairs, not ipairs: the table is keyed by rank and starts
    -- at 2, since rank 1's wash lives on our own frame instead.
    for rank, tex in pairs(record.washes or {}) do
      pcall(ApplyRuleFill, tex, healthBar, record.missingStack[rank], 0)
    end
  end

  -- Rank 1's wash. Rebuilt rather than just re-anchored: it is one texture
  -- either way, and going through the builder keeps colour, fill style and
  -- geometry in one place.
  if rig.missingWash then
    NS.BuildMissingWash(rig, healthBar,
      isPlater and baseLevel or (baseLevel + (rig.missingLevelOffset or 0)),
      (rig.missingLadder or {})[1])
  end

  NS.UpdateCovers(rig)
end

function NS.SetTintsUnit(rig)
  for _, record in ipairs(rig.rules or {}) do
    for _, frame in ipairs(record.containers) do
      NS.ActivateContainer(rig, frame, record)
    end
  end
end

-- Retiring a rig cannot assume it may touch what it built. A chain's nested
-- containers are children of aura buttons, which makes them forbidden objects:
-- SetEnabled and plain field writes are accepted, but Hide is refused, since
-- visibility is what the engine drives. SetEnabled(false) is what actually
-- retires a container, so a refused Hide costs nothing.
function NS.RetireTints(rig)
  -- Ours, on a frame we own, so these two are always allowed. The missing wash
  -- matters more than the outline here: it is shown UNCONDITIONALLY, so a
  -- retired rig that left it up would keep a reminder lit on a plate this
  -- addon no longer drives.
  if rig.outline then rig.outline:Hide() end
  if rig.missingWash then rig.missingWash:Hide() end
  for _, record in ipairs(rig.rules or {}) do
    for _, frame in ipairs(record.containers) do
      pcall(frame.SetEnabled, frame, false)
      frame.boonEnabled = false
      frame.boonUnit = nil
      pcall(frame.Hide, frame)
    end
    if record.holder then
      pcall(record.holder.Hide, record.holder)
    end
  end
end

-- Whether any rig has an underlay to maintain. Missing-health covers are NOT
-- included here: they paint a fixed configured color (NS.MissingCoverColor),
-- not a live replica of the bar's own art, so they need no repaint loop --
-- recolored, when the user changes that color, via NS.ApplyTintColors
-- instead. Recomputed rather than cached: a rebuild can add or remove an
-- underlay at any time, and this is two nested loops over small lists that
-- bail on the first hit.
function NS.AnyCovers()
  for _, rig in pairs(NS.rigs) do
    for _, record in ipairs(rig.rules or {}) do
      if #record.underlays > 0 then return true end
    end
  end
  return false
end

-- Covers repaint the bar, so they must copy its full appearance: hosts often
-- use patterned art with tex coords derived from the bar width (Ellesmere
-- tiles its stripes that way), and a path-only copy reads as flat.
function NS.UpdateCovers(rig)
  local healthBar = rig.healthBar
  if not healthBar then return end

  local anyReplicas = false
  for _, record in ipairs(rig.rules or {}) do
    if #record.underlays > 0 then anyReplicas = true break end
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
    for _, underlay in ipairs(record.underlays) do Repaint(underlay) end
  end
end


-- A tint hangs off the last link of the chain, and the chain must be attached
-- to every pooled button at every level. Report how much of it exists.
function NS.DescribeChain(record, healthBar)
  if record.unsupported then
    return ("|cffff0000not built — %d debuffs exceeds the limit of %d|r")
      :format(#(record.rule.conditions or {}), NS.MAX_RULE_CONDITIONS)
  end
  if record.blocked then
    return "|cffff0000not built — refused while auras are secret|r"
  end

  -- The missing ladder carries no tints at all: its output is one wash per
  -- rank plus one cover per rank, and the generic line below would report it
  -- as "N containers, 0 tints" -- which looks exactly like a rule that failed
  -- to build.
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

-- Colors are ours to change any time, so the picker applies without a rebuild.
--
-- This used to bail on NS.IsRestricted(), which is true for the whole of a
-- dungeon rather than just its combat, so no colour change ever landed inside
-- a key. SetColorTexture on a texture we created ourselves is not a protected
-- action; combat is the only thing worth waiting out, and the backstop ticker
-- in Core.lua retries once it ends.
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
      -- Border colour is ours to change live, same as the bar's. Thickness is
      -- NOT -- it is baked into each edge texture's size at creation, so a
      -- thickness change still needs a rebuild.
      local border = record.rule and record.rule.border
      local bc = border and border.color
      if bc then
        for _, tex in ipairs(record.borders or {}) do
          pcall(tex.SetColorTexture, tex, bc.r, bc.g, bc.b, bc.a)
        end
      end
      -- Missing-health covers share ONE color across every rule (see
      -- NS.MissingCoverColor), so this only needs to run once per rig rather
      -- than reading record.rule at all -- still cheap enough to just do it
      -- per record alongside everything else here.
      if #record.missingCovers > 0 then
        local mc = NS.MissingCoverColor()
        for _, tex in ipairs(record.missingCovers) do
          pcall(tex.SetColorTexture, tex, mc.r, mc.g, mc.b, mc.a)
        end
      end
      -- Ladder washes take their own rule's colour, same as any tint. Their
      -- COVERS are not recoloured here: those are live replicas of the host
      -- bar, maintained by NS.UpdateCovers, and a colour picker has no say
      -- over what the bar itself looks like.
      for rank, tex in pairs(record.washes or {}) do
        local washRule = record.missingStack and record.missingStack[rank]
        if washRule and washRule.color then
          pcall(ApplyRuleColor, tex, washRule)
        end
      end
    end
    -- Rank 1's wash, on our own frame, following the top missing rule.
    local frame = rig.missingWash
    local top = (rig.missingLadder or {})[1]
    if frame and frame.wash and top and top.color then
      pcall(ApplyRuleColor, frame.wash, top)
    end
  end
end
