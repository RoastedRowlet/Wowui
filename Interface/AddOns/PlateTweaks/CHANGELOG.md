# Changelog

All notable changes to PlateTweaks are recorded here. No file like this
existed before 1.8.4, so history prior to that release is not reconstructed.

## 1.8.5

### Added

- **Rig repair attempts is now a setting** (Setup -> All Plates -> Performance
  -> "Rig repair attempts", 1-5, default 1). A rig built while
  `InCombatLockdown()` is true is suspected structurally incomplete (secure
  `AuraContainer` creation can be silently refused mid-combat) and previously
  got exactly one chance, ever, to be discarded and rebuilt once combat
  allowed it. In a long boss fight or a tightly chained M+ pull, combat can
  stay up for minutes, so a plate whose one repair attempt itself landed
  during a brief regen flicker between two pulls was stuck uncolored for the
  rest of the session on that health bar -- this is the likely explanation
  for "the rule works sometimes, not all the time" reports that are not
  actually about the rule's condition. Raising the cap gives a plate more
  chances to recover, at the cost of leaking a bounded number of frames per
  extra attempt (WoW cannot destroy secure frames once created) -- the
  in-game control carries an explicit warning about that tradeoff, and the
  original default (1) is unchanged.
- `/pt status` now prints the configured cap alongside the rebuilt-rig count,
  e.g. `rigs rebuilt after a bad build: 9 (built in combat, or a container
  was refused; cap 1)`, so the setting's effect is visible without opening
  the options window.

## 1.8.4

### Fixed

- **"NOT KNOWN" false negative on legitimately-applicable auras.** `NS.CanApplyAura`
  (Spells.lua) only trusted the Cooldown Manager's aura list and `IsPlayerSpell`
  when deciding whether a rule's debuff can ever land on this character. Both
  miss an aura that lands as a side effect of a talent/hero-tree passive
  rather than as its own trackable ability or spellbook entry (e.g. Sentinel's
  Mark) -- the rule was flagged `NOT KNOWN` in `/pt status` and could never
  fire even though the spec genuinely applies it.

  `CanApplyAura` now also checks the addon's own aura-observation log
  (`NS.LearnAuras`, which already passively records every `name -> spellID`
  pair actually seen landing as a player aura) and trusts a direct
  observation over the spellbook heuristic.

- **Learned aura IDs were never actually saved.** The observation log wrote to
  a global (`BOONPLATES_SETTINGS`) left over from before the BoonPlates ->
  PlateTweaks rename, which the `.toc` never declared under
  `## SavedVariables`. Everything recorded there was silently discarded on
  every `/reload` or relog. Moved to `PLATETWEAKS_SETTINGS.auraIDs`, which is
  declared and persists correctly.
