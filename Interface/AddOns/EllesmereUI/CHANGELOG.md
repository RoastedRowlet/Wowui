# EllesmereUI

## [v8.4.1](https://github.com/EllesmereGaming/EllesmereUI/tree/v8.4.1) (2026-07-08)
[Full Changelog](https://github.com/EllesmereGaming/EllesmereUI/compare/v8.4...v8.4.1) [Previous Releases](https://github.com/EllesmereGaming/EllesmereUI/releases)

- Release v8.4.1  
- Merge pull request #618 from Snsei987/fix/pet-unit-frame-class-colored  
    Pet unit frame: fix class colored health bar  
- Merge pull request #617 from Filpet96/fix/instance-reset-announce-spam  
    fix(qol): debounce instance reset announce for multi-dungeon resets  
- chore(locale): refresh key list  
- Pet unit frame: fix class colored health bar  
- style: trim instance reset announce comment  
    Co-authored-by: Cursor <cursoragent@cursor.com>  
- chore: regenerate Locales/\_keys.txt  
    Keep the locale key list current for CI.  
    Co-authored-by: Cursor <cursoragent@cursor.com>  
- fix(qol): debounce instance reset announce for multi-dungeon resets  
    Resetting multiple saved instances fires one system message per dungeon,  
    which caused duplicate party announcements. Debounce so only one message  
    is sent per reset batch.  
    Co-authored-by: Cursor <cursoragent@cursor.com>  
- Merge pull request #610 from SamJin98/feat/incoming-resurrection  
    [WIP]  feat(raidframes): incoming resurrection indicator on raid/party frames  
- Merge pull request #612 from luispemu/main  
    feat: Arms Warrior Sweeping Strikes charges as class resource  
- Merge pull request #1 from luispemu/feature/arms-sweeping-strikes  
    Feature/arms sweeping strikes  
- perf: cache talent lookups in the Whirlwind stacks tracker  
    Same optimization as the Sweeping Strikes tracker: GetWhirlwindStacks  
    is polled every 0.1 s by the resource bar, unit frame and personal  
    nameplate readouts (two IsSpellKnown C calls per poll), and  
    HandleWhirlwindStacks ran an IsSpellKnown guard on every player cast  
    for every class. Talents cannot change in combat, so the four flags  
    (Improved Whirlwind, Crashing Thunder, Unhinged, Crackling Thunder)  
    are resolved once per login/spec/talent event by a watcher that is  
    only registered on warriors; other classes keep the flags false and  
    both entry points early-out on a plain upvalue read.  
    Also hoists EnemyInStrikeRange's inner InReach helper to block scope  
    (wide passed as a parameter) so no closure is allocated per generator  
    cast in combat.  
    Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>  
- perf: cache talent lookups in the Sweeping Strikes tracker  
    GetSweepingStrikes is polled every 0.1 s by three surfaces (resource  
    bar, unit frame, personal nameplate) and made two C\_SpellBook  
    IsSpellKnown C calls per poll; HandleSweepingStrikes additionally ran  
    an IsSpellKnown guard on every player cast for every class. Talents  
    cannot change in combat, so resolve the four flags (Sweeping Strikes,  
    Improved, Broad Strokes, Fervor of Battle) once per login/spec/talent  
    event instead -- same rationale as the cached spec ID above  
    GetSoulFragments. The watcher frame is only registered on warriors;  
    other classes keep the flags false and both entry points early-out on  
    a plain upvalue read.  
    Also hoists EnemiesInReach's inner InReach helper to block scope so no  
    closure is allocated per tracked spender cast in combat.  
    Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>  
- fix: sync preview count text with the lit segments  
    The preview's count text recomputed its own filled count from the raw  
    5-pip random value, so it disagreed with the rescaled pip fill (e.g. 12  
    Sweeping Strikes pips lit 8 but the text said 3). The pip loop now  
    exposes its resolved filled count/max and the text mirrors it, shown as  
    "cur / max" like the live bar (single number when Show Max Stacks is  
    off).  
    Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>  
- feat: options preview shows the real pip count for the current spec  
    The Class Resource Bar preview in the ResourceBars options hardcoded 5  
    pips regardless of spec. Resolve the count from the live secondary  
    resource instead (via \_ERB\_GetSecondaryResource plus the tracker maxes),  
    so Arms previews its 12/18 Sweeping Strikes charges, Fury its 4  
    Whirlwind stacks, DK its 6 runes, Enhancement its 5/10 Maelstrom  
    Weapon, etc. Falls back to the generic 5 when there is no discrete  
    secondary.  
    The random preview fill scales to the pip count, and the update pass  
    creates missing pip frames on demand (builder still pre-creates the  
    initial set).  
    Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>  
- feat: Arms Warrior Sweeping Strikes charges as class resource  
    Adds SWEEPING\_STRIKES as the Arms (spec 71) secondary resource, mirroring  
    the Fury WHIRLWIND\_STACKS implementation across all display surfaces:  
    resource bars, unit frames and nameplates.  
    Tracker (core, UNIT\_SPELLCAST\_SUCCEEDED-based, secret-value safe):  
    - Sweeping Strikes (260708): 12 charges, 18 with Improved Sweeping  
      Strikes (383155); 30 s duration  
    - Broad Strokes (1261049): Colossus Smash / Warbreaker also activate it  
    - Spenders consume only with a sweep partner in range (nameplate probe);  
      Demolish consumes 2 charges per channel (two sweeping hits)  
    - Fervor of Battle (202316): Cleave/Whirlwind on 3+ targets consume one  
      charge via the triggered Slam, with an echo-suppression window  
    - Rend and Storm Bolt deliberately excluded (not in the aura's  
      affected-spells list)  
    Also adds the "Sweeping Strikes" entry to Class Resource Colors.  
    Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>  
- feat: incoming resurrection indicator on raid/party frames  
    Show a rez icon on dead units that have an incoming resurrection  
    (UnitHasIncomingResurrection) so healers can see a body is already being  
    picked up and avoid three healers rezzing the same corpse. It shares the  
    ready-check / summon texture slot at lowest priority and has its own  
    toggle under "Ready Check / Summon / Rez" (on by default).  
    - Hide the DEAD status text while a rez is incoming so the icon isn't  
      covered, matching Blizzard's CompactUnitFrame behavior. Handled in both  
      the full and health-only button update paths.  
    - Refresh on INCOMING\_RESURRECT\_CHANGED (status text + shared icon).  
    - Indicator preview shows a second corpse carrying the rez icon; party  
      preview has no free slot for it (documented inline).  
