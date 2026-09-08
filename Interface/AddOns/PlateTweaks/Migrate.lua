local _, NS = ...

-- Profile migrations.
--
-- Pure table work, deliberately in its own file with no frames, no events and
-- no engine calls: these run once against someone's saved profile, where being
-- wrong costs them rules they built by hand. A file that can be loaded by the
-- headless tests in dev/ is a file whose migrations are actually tested before
-- they touch a profile.

local ipairs, pairs, type = ipairs, pairs, type

-- Two rules match when they fire on the same thing: the same debuffs, and the
-- same answer to present-or-missing. Order within the condition list does not
-- matter -- `Agony + Corruption` and `Corruption + Agony` are one rule.
local function SameConditions(a, b)
  local ca, cb = a.conditions or {}, b.conditions or {}
  if #ca ~= #cb then return false end
  if (a.showWhenMissing and true or false) ~= (b.showWhenMissing and true or false) then
    return false
  end
  local seen = {}
  for _, condition in ipairs(ca) do seen[condition.spellID] = (seen[condition.spellID] or 0) + 1 end
  for _, condition in ipairs(cb) do
    local left = seen[condition.spellID]
    if not left or left == 0 then return false end
    seen[condition.spellID] = left - 1
  end
  return true
end

-- Fold the border list into the bar list.
--
-- The two were separate lists with separate priorities, which meant a rule
-- that coloured both halves had to be authored twice, in two places, with
-- nothing saying they were related. A rule has ALWAYS carried both halves
-- (rule.color and rule.border) -- the split was in the lists, not the rules --
-- so this is a list merge, not a rule rewrite.
--
--   match      a bar rule fires on exactly the same debuffs: the border half
--              moves onto it, and one row now says what two rows said
--   no match    the border rule joins the list as a rule whose bar half is
--              off, keeping its own colour and its position relative to the
--              other unmatched ones
--
-- A bar rule that already has an enabled border is left alone: it is already
-- expressing what the border rule would have said, and overwriting it would
-- silently change a colour the user chose.
--
-- Returns a summary rather than printing one -- the caller knows whether
-- anyone is around to be told.
function NS.MergeRuleLists(tints)
  local result = { merged = 0, moved = 0, skipped = 0 }
  if type(tints) ~= "table" then return result end

  local rules = tints.rules
  local borders = tints.borderRules
  if type(rules) ~= "table" or type(borders) ~= "table" then return result end

  local appended = {}
  for _, border in ipairs(borders) do
    local half = border.border
    if type(half) ~= "table" or not half.enabled then
      -- A border rule with its border switched off drew nothing before this
      -- and would draw nothing after. Counted, not carried.
      result.skipped = result.skipped + 1
    else
      local target
      for _, rule in ipairs(rules) do
        if SameConditions(rule, border) then target = rule break end
      end

      if target and not (target.border and target.border.enabled) then
        target.border = half
        result.merged = result.merged + 1
      elseif target then
        result.skipped = result.skipped + 1
      else
        -- Bar half off, so it costs no draw slot and paints exactly what it
        -- painted before: a border and nothing else.
        appended[#appended + 1] = {
          enabled = border.enabled,
          conditions = border.conditions,
          showWhenMissing = border.showWhenMissing,
          barEnabled = false,
          color = border.color,
          border = half,
          onTarget = border.onTarget,
          onFocus = border.onFocus,
        }
        result.moved = result.moved + 1
      end
    end
  end

  -- Appended below every existing rule, in their own original order. Ordering
  -- between the two lists never existed, so there is no ordering to preserve
  -- and no ordering to invent: the bottom is the position that changes the
  -- fewest outcomes, since a border-only rule cannot shadow a bar rule.
  for _, rule in ipairs(appended) do rules[#rules + 1] = rule end

  -- Emptied, and kept.
  --
  -- Emptied because everything that walks the profile -- spell gating, the
  -- preview, the diagnostics dump -- walks both lists, and a rule sitting in
  -- both would be counted twice by every one of them. Kept, under another
  -- key, because this is the only record of what the profile looked like
  -- before the merge, and a few kilobytes is a cheap price for being able to
  -- put someone's rules back.
  tints.borderRulesBackup = borders
  tints.borderRules = {}
  return result
end

-- The rules in a list that carry an enabled border.
--
-- Here rather than in Core so the import summary can use it on a payload's
-- tables, before those tables are anyone's profile.
function NS.BorderHalves(rules)
  local out = {}
  for _, rule in ipairs(rules or {}) do
    if rule.border and rule.border.enabled then out[#out + 1] = rule end
  end
  return out
end

-- Every migration this build knows, in order, each behind its own flag.
--
-- Flags rather than a version number: a profile that skipped three releases
-- and one written yesterday both arrive here, and "has this particular thing
-- happened" is answerable where "which version wrote this" is not.
function NS.RunMigrations(db)
  if type(db) ~= "table" or type(db.tints) ~= "table" then return end
  local notes = {}

  -- Borders are not a module any more.
  --
  -- They were one when they lived in their own list on their own page. Now a
  -- border is half of a rule, switched on in that rule's own row -- so a
  -- profile carrying borderEnabled = false has every border silently off with
  -- nothing on screen to say why. Cleared once, not read again.
  if db.tints.borderEnabled == false then
    db.tints.borderEnabled = true
    notes[#notes + 1] = "border coloring is per rule now -- the module switch is gone, and your border halves are on"
  end

  -- The threat border's own enable is retired: one row, one switch. A profile
  -- carrying it has the border half of every threat state inert while the
  -- chips beside them show colour, which is the worst of both.
  if type(db.tints.threatBorder) == "table" and db.tints.threatBorder.enabled ~= nil then
    db.tints.threatBorder.enabled = nil
  end

  if not db.tints.rulesMerged then
    local result = NS.MergeRuleLists(db.tints)
    db.tints.rulesMerged = true
    if result.merged > 0 or result.moved > 0 then
      notes[#notes + 1] = ("border rules folded into one list: %d merged into a matching rule, %d kept as border-only")
        :format(result.merged, result.moved)
    end
  end

  return notes
end
