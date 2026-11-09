-- The border-list merge, against profiles that already exist.
--
-- This one runs on someone's saved rules, once, with no undo in the moment --
-- so what matters is not that it produces a tidy list but that every rule
-- which painted before still paints, in the same order, at the same cost.
local dir = ...

local NS = {}
local chunk = assert(loadfile(dir .. "/Migrate.lua"))
chunk("PlateTweaks", NS)

local failures = 0
local function check(name, got, want)
  if got ~= want then
    failures = failures + 1
    print(("FAIL %s: got %s want %s"):format(name, tostring(got), tostring(want)))
  else
    print("ok   " .. name)
  end
end

local function Rule(spellIDs, opts)
  local rule = { enabled = true, conditions = {}, color = { r = 1, g = 0, b = 0, a = 0.75 } }
  for _, id in ipairs(spellIDs) do rule.conditions[#rule.conditions + 1] = { spellID = id } end
  for key, value in pairs(opts or {}) do rule[key] = value end
  return rule
end

local function Border(enabled, r)
  return { enabled = enabled, color = { r = r or 1, g = 0.85, b = 0.1, a = 1 }, thickness = 2 }
end

-- ---- a rule that exists in both lists becomes one rule ----------------------
local tints = {
  rules = { Rule({ 980 }), Rule({ 980, 172 }) },
  borderRules = { Rule({ 980 }, { border = Border(true, 0.2) }) },
}
local result = NS.MergeRuleLists(tints)
check("the matching pair merged", result.merged, 1)
check("nothing was moved", result.moved, 0)
check("the list did not grow", #tints.rules, 2)
check("the border half landed on the matching rule", tints.rules[1].border.color.r, 0.2)
check("the rule keeps its bar half", tints.rules[1].barEnabled, nil)
check("the other rule is untouched", tints.rules[2].border, nil)
check("the old list is emptied", #tints.borderRules, 0)
check("and kept, in full", #tints.borderRulesBackup, 1)

-- ---- condition order does not make two rules different ---------------------
tints = {
  rules = { Rule({ 980, 172 }) },
  borderRules = { Rule({ 172, 980 }, { border = Border(true, 0.3) }) },
}
NS.MergeRuleLists(tints)
check("the same debuffs in another order still match", #tints.rules, 1)
check("and the border came with it", tints.rules[1].border.color.r, 0.3)

-- ---- present and missing are different rules -------------------------------
tints = {
  rules = { Rule({ 980 }) },
  borderRules = { Rule({ 980 }, { showWhenMissing = true, border = Border(true) }) },
}
NS.MergeRuleLists(tints)
check("a MISSING border rule does not merge into a presence rule", #tints.rules, 2)
check("it arrives as its own rule", tints.rules[2].showWhenMissing, true)
check("with its bar half off, so it costs no draw slot", tints.rules[2].barEnabled, false)

-- ---- a border rule with no twin is carried, not dropped --------------------
tints = {
  rules = { Rule({ 980 }) },
  borderRules = {
    Rule({ 172 }, { border = Border(true, 0.4) }),
    Rule({ 589 }, { border = Border(true, 0.5), enabled = false }),
  },
}
result = NS.MergeRuleLists(tints)
check("both unmatched rules moved", result.moved, 2)
check("they land below the existing rules", tints.rules[2].conditions[1].spellID, 172)
check("in their own original order", tints.rules[3].conditions[1].spellID, 589)
check("a disabled one stays disabled", tints.rules[3].enabled, false)
check("their colours survive", tints.rules[2].border.color.r, 0.4)

-- ---- a rule that painted nothing does not start painting -------------------
tints = {
  rules = { Rule({ 980 }) },
  borderRules = { Rule({ 172 }, { border = Border(false) }) },
}
result = NS.MergeRuleLists(tints)
check("a border rule with its border off is dropped", #tints.rules, 1)
check("and counted as skipped", result.skipped, 1)

-- ---- a colour the user chose is never overwritten --------------------------
tints = {
  rules = { Rule({ 980 }, { border = Border(true, 0.9) }) },
  borderRules = { Rule({ 980 }, { border = Border(true, 0.1) }) },
}
result = NS.MergeRuleLists(tints)
check("an existing enabled border wins", tints.rules[1].border.color.r, 0.9)
check("and the incoming one is skipped, not appended", #tints.rules, 1)
check("counted as skipped", result.skipped, 1)

-- ---- what painted before still paints --------------------------------------
--
-- The real contract. Build a two-list profile, note what each list would have
-- drawn, merge, then ask the merged list the same questions.
local before = {
  rules = { Rule({ 980 }), Rule({ 172 }), Rule({ 589 }, { barEnabled = false }) },
  borderRules = {
    Rule({ 980 }, { border = Border(true, 0.2) }),
    Rule({ 31 }, { border = Border(true, 0.6) }),
  },
}
local barCount, borderCount = 0, 0
for _, rule in ipairs(before.rules) do
  if rule.enabled ~= false and rule.barEnabled ~= false then barCount = barCount + 1 end
end
for _, rule in ipairs(before.borderRules) do
  if rule.enabled ~= false and rule.border.enabled then borderCount = borderCount + 1 end
end

NS.MergeRuleLists(before)

local barAfter, borderAfter = 0, 0
for _, rule in ipairs(before.rules) do
  if rule.enabled ~= false and rule.barEnabled ~= false then barAfter = barAfter + 1 end
end
borderAfter = #NS.BorderHalves(before.rules)
check("the same number of bars paint", barAfter, barCount)
check("the same number of borders paint", borderAfter, borderCount)
check("the bar rules keep their order", before.rules[1].conditions[1].spellID, 980)
check("and their relative order to each other", before.rules[2].conditions[1].spellID, 172)

-- ---- running it twice does nothing the second time -------------------------
local db = { tints = before }
db.tints.rulesMerged = nil
local sizeBefore = #db.tints.rules
NS.RunMigrations(db)
check("the flag is set", db.tints.rulesMerged, true)
local sizeAfter = #db.tints.rules
NS.RunMigrations(db)
check("a second run changes nothing", #db.tints.rules, sizeAfter)
check("and the first run was itself idempotent on an emptied list",
  sizeAfter, sizeBefore)

-- ---- a profile with nothing in it survives ---------------------------------
local empty = { tints = { rules = {}, borderRules = {} } }
NS.RunMigrations(empty)
check("an empty profile merges to empty", #empty.tints.rules, 0)
check("and is marked done", empty.tints.rulesMerged, true)

local partial = { tints = { rules = {} } }
NS.RunMigrations(partial)
check("a profile with no border list at all is left alone", #partial.tints.rules, 0)

print(failures == 0 and "ALL PASS" or (failures .. " FAILURES"))
return failures
