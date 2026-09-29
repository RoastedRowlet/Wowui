# EllesmereUI

## [v9.3](https://github.com/EllesmereGaming/EllesmereUI/tree/v9.3) (2026-09-27)
[Full Changelog](https://github.com/EllesmereGaming/EllesmereUI/compare/v9.2.9...v9.3) [Previous Releases](https://github.com/EllesmereGaming/EllesmereUI/releases)

- Release v9.3  
- Merge pull request #2270 from Caedis/caedis/databars-blocks-split  
    refactor(databars): split blocks into Blocks/ files  
- refactor(databars): split blocks into Blocks/ files  
    One file per block type; shared helpers in Blocks/Shared.lua exposed via  
    ns.BlockKit. Block code moved verbatim, no behavior change.  
- Merge pull request #2268 from DlargeX/main  
    added new Strings for German Locals  
- added new Strings for German Locals  
- Merge pull request #2267 from Caedis/caedis/classColorPlayerNamesPlates  
    feat(nameplates): class color friendly player names  
- Merge pull request #2264 from denis-makula/dev/fix-damage-meter-empty-rows  
    fix(damage-meters): prevent empty row outlines  
- Merge pull request #2266 from scavienger/feat/aurabuff-growth-direction  
    feat(aurabuffreminders): add grow direction option (centered/left/right)  
- feat(nameplates): class color friendly player names  
    Opt-in toggle in friendly plate cog, default off. Name-only mode unaffected.  
- Merge pull request #2263 from dfrisone/feat/forever-nameplate-threat-pct  
    feat(forever): threat % text on nameplates and target/focus frames  
- feat(aurabuffreminders): add grow direction option (right/centered/left)  
    - Add Grow Direction setting to AuraBuff Reminders (Grow Right, Grow Centered, Grow Left)  
    - Default to Grow Centered for zero behavior change  
    - Sync with Unlock Mode mover dropdown and directional arrows  
    - Add tooltip on label to explain edge anchoring and prevent shifting  
    - Add Korean localization for the new setting and tooltip  
- Merge remote-tracking branch 'upstream/main' into feat/forever-nameplate-threat-pct  
- fix(forever): create the nameplate threat % text on first use, restore the unit frame watcher only on Forever  
- fix(damage-meters): prevent empty row outlines  
    - Initialize row layout and colors even when class and spec data are missing.  
    - Settle scrolling and pinned rows before populating visible content, including unresolved initial layouts.  
    - Preserve hidden or disabled icon borders after styling and clear stale pinned data when sessions disappear.  
- Merge pull request #2260 from dfrisone/feat/raid-portrait-char-size  
- Merge pull request #2258 from lkshrk/fix/2154-healthstone-count  
- feat(forever): threat % text on nameplates and target/focus frames  
    Shows your own threat percentage on enemy nameplates and on the target  
    and focus unit frames, set from the Forever Essentials Threat page (the  
    nameplate row is also on the Enemy Nameplates page). Off by default,  
    Forever only.  
    Forever returns the percent and status secret for nameplate units, so  
    the percent goes straight to SetFormattedText and the color comes from  
    the isTanking flag through the curve boolean fold. Target and focus  
    values are readable and use all four threat status colors.  
- feat(raidframes): portrait 3D Zoom to a full-body view, Character Size for Inside portraits  
- fix(cdm): count Demonic Healthstones on the Healthstone preset and refresh charges at once  
    Pact of Gluttony turns self-conjured Healthstones into Demonic Healthstones,  
    so the Healthstone preset showed 0 for warlocks with the talent. The preset  
    now lists 224464 as a family alternate and, with the new countAllAlts flag,  
    always shows the sum, since a warlock can hold both stones.  
    Using or refilling a Healthstone charge moves no bag contents, so no  
    BAG\_UPDATE fires; the new count only becomes readable with  
    BAG\_UPDATE\_COOLDOWN, 0.3-1.4 s after the cast. The cast's fast-lane pass had  
    already read the old count by then, so the icon stayed stale until an  
    unrelated edge re-armed it. BAG\_UPDATE\_COOLDOWN now re-reads the shown  
    non-pot item counts, arms only on a real change and bypasses the 1 Hz cap  
    like a cast does.  
    Fixes #2154  
- Merge pull request #2254 from Walhaell/unitframes-nonplayer-portrait  
    feat(unitframes): pick what a non-player shows in Class art style  
- Merge pull request #2256 from Barbiero/locale/ptbr-post-929  
    ptBR: translate reworked Threat Meter, CDM Talent Conditions, pet frames, party targets and more  
- ptBR: translate the reworked WoW Forever Threat Meter, CDM Talent Conditions, raid frame pet frames, party target buttons, Sunder Armor on nameplates, important cast glow sync, the Custom Icon Shape crop requirement and the mana regen spark; drop keys for removed Threat Meter strings  
- Merge pull request #2253 from Caedis/caedis/mp5  
    feat(forever): add mana regen spark to power bars  
- feat(unitframes): pick what a non-player shows in Class art style  
    Class art is player-only: UnitClass reports most NPCs as warriors, so the  
    class lane fell back to the unit's 2D portrait unconditionally, the way  
    Blizzard's own class portraits do. That fallback is now a per-frame setting  
    (portraitNonPlayer): the 2D portrait (default, unchanged behavior), nothing at  
    all, or the 3D model.  
    The 3D answer is applied as a real portrait mode swap rather than by painting  
    a model from the class lane, so the model events, the blank-model heal and the  
    re-show path keep working exactly as they do for a portrait genuinely set to  
    3D, and a player landing on a frame that is showing the model as a fallback  
    goes back to its class icon. The PlayerModel stays lazily created, so it costs  
    nothing until a non-player actually asks for it. Blizzard Style keeps its own  
    answers (2D art, never off) and the options row is disabled there.  
- feat(forever): add mana regen spark to power bars  
    Opt-in spark on the resource bar power bar and player unit frame  
    power bar: 5s sweep after a mana-costing cast, then 2s regen tick  
    sweeps until mana stops changing. Player mana is secret, so it keys  
    off cast and power events, never mana values.  
- Merge pull request #2084 from galadam4/feat/cdm-custom-spell-range-tint  
- Merge pull request #2247 from choppaoops/feat/cdm-talent-conditions  
- Merge pull request #1510 from apainter2/feature/party-target-frames  
    Add opt-in Party Target frames to party frames  
- Merge pull request #2246 from msromike/fix/forever-caster-range-cutoff  
    fix(forever): casters get the 5 yd melee range cutoff (no specs); derive it from the spellbook  
- Merge pull request #2245 from msromike/fix/ilvl-secure-character-click  
    fix(databars): Item Level block opens the character sheet via a secure passthrough  
- feat(raidframes): recreate party target frames  
- feat(cdm): per-spell Talent Conditions for cooldown/utility icons  
    A cooldown or utility icon can now require talents: it shows only while  
    every chosen condition holds ("taken" or "not taken"). Example: Unholy  
    Death Knight keeps Death and Decay on the bar only while the talent that  
    makes it worth pressing is taken; on a single-target build it disappears  
    without editing the bar.  
    Setting: right-click an icon in the CDM preview > Talent Conditions. The  
    popup draws the current spec's class tree and spec tree from the game's  
    node positions; clicking a talent cycles Taken > Not Taken > cleared, and  
    a choice node is split so either side can be required. Hero trees are out  
    of scope.  
    Runtime: stored per spell in the spec's spellSettingsCD entry  
    (talentConditions), never in the Apply-to-Bar tiers. A failing condition  
    drops the frame from the reanchor pass like an unlearned spell, so Phase 4  
    parks it and the bar closes the gap. Node state comes from C\_Traits through  
    a lazy per-node cache keyed by the active config and cleared on talent  
    edits; talent edits already queue a CDM rebuild, so no events are added.  
    Cost: gated on ns.\_cdmAnyTalentCond, set by a login scan or on first use,  
    like the other per-spell gates. Users without a condition run nothing new.  
    In the options preview an icon whose conditions are not met is dimmed like  
    an unlearned spell and keeps its slot, and a small corner mark shows which  
    icons carry conditions.  
    Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>  
- perf(cdm): keep Out of Range Coloring off the idle drain  
    Out of range, PaintTint returned before touching the dim memo, so an  
    icon that was dimmed when it left range kept the preset drain unsettled  
    (letting the ambient SPELL\_UPDATE\_COOLDOWN/CHARGES lanes keep waking it)  
    after the spell turned usable again. The memo now clears out of range,  
    the tint write is edge-gated, and a repaint outside the pass that lands  
    dimmed wakes the drain so its usable edge is still polled.  
    SPELL\_RANGE\_CHECK\_UPDATE is nearly always one of Blizzard's own  
    registrations: a readable id no icon armed now returns before any frame  
    is touched, and a matching or unreadable id (instanced secrecy) re-reads  
    only the range answer instead of the full re-resolve.  
    PLAYER\_TARGET\_CHANGED keeps the full re-resolve.  
    Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>  
- fix(forever): caster attack-range cutoff from the spellbook  
    WoW Forever has no specs, so SpecAttackCutoff returned the 5 yd melee  
    cutoff for every class and the crosshair / nameplate out-of-range  
    checks treated casters as melee. On Forever, Druid, Priest, Mage and  
    Warlock now use their longest harmful spellbook rung (<= 40 yd), so the  
    cutoff lands on a real spell the probe can test directly. Hunter and  
    hybrids stay at 5 as before.  
    Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>  
- fix(databars): open the character sheet from the Item Level block via a secure passthrough  
    The Item Level block's OnClick called ToggleCharacter("PaperDollFrame")  
    from addon Lua, tainting CharacterFrame's show path: the player health bar  
    values come back secret and TextStatusBar.lua:110 throws (#2244).  
    The block now gets the same secure click passthrough the Location and  
    Micro Menu blocks use, to CharacterMicroButton: lazy overlay, never built  
    in lockdown, click dropped in combat via the combatlock state driver.  
    Because the overlay puts the bar under protection, Refresh skips sizing  
    and anchoring in lockdown, PLAYER\_REGEN\_ENABLED is added to the block's  
    events, Enable/Disable/Destroy only Show/Hide out of combat, and Destroy  
    parks the overlay with ParkSecureFrame. The plain OnClick remains as the  
    fallback before the overlay exists.  
    Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>  
- Merge pull request #2236 from dfrisone/feat/raidframes-pet-frames  
    feat(raidframes): pet frames for party and raid  
- feat(raidframes): pet frames Beside Owner for the party  
    Beside Owner (Party tab Position, with a Pet Side of Right, Left or  
    Below): a pet button parented to each party frame, its unit the owner's  
    plus the "pet" suffix, so SecureButton\_GetUnit resolves partypetN or  
    raidpetN and each pet follows its owner through the header's re-sorts,  
    in combat too, with a unit watch for show/hide. Stored as a flag over  
    the shared position, so the Raid tab keeps its own. Your own pet hangs  
    off the party container: beside the self button, or with Hide Self in  
    the slot after the last party frame. The pet trackers match the shown  
    owner button, since two can carry your pet.  
    Fixes on the pet frames: button anchors are cleared before a re-layout,  
    since a leftover column anchor from the pre-create pass pinned button 1  
    to the header's old height; under the Party Frames layout the pets take  
    the raid frame size instead of the portrait box.  
- feat(raidframes): pet frames Free Move and options preview  
    Free Move for the pet group: the header is pinned at the corner its pets  
    grow from, so the first pet stays put as pets come and go, with a Move  
    Frames overlay sized for five pets (FB.SetMoverShown gains an owner  
    PlaceMover hook; Friendly Boss and Extra Frames keep their own path).  
    The raid and party options previews show made-up pets where the real  
    ones would go, and the preview overlay grows to hold them. The real pet  
    header dims with the other real frames while a preview is up.  
    Fixes on the pet frames: the header gets a column anchor before its  
    pre-create pass; pet buttons repaint their target border on assignment  
    and FB.ApplyBorderColor tolerates a button with no unit yet; in party  
    mode the pets follow the party growth and line up with the first party  
    frame. Turning Show Pets off drops the move overlay, and Extra  
    Width/Height resize it while it is up.  
- feat(raidframes): pet frames for party and raid  
    Show Pets on the Party and Raid tabs (each off by default) adds the  
    group's pets beside the frames: one SecureGroupPetHeaderTemplate header,  
    so Blizzard's secure code adds and removes pets in combat. The buttons  
    are Friendly Boss style (health, name, health text, range fade, hover  
    and target borders, click to target, click-casting); no auras, power,  
    roles or threat. Before first / after last group, or beside the party  
    frames in party mode, after Friendly Boss or Extra Frames on the same  
    side; hidden in pet battles; Small Raid mode shows group 1's pets only.  
    The Friendly Boss per-button build and styling move into FB.BuildVisuals  
    and FB.StyleVisuals unchanged so the pet buttons share them; FB.Update  
    takes an optional owner for its health colour, and FB.Anchor gains an  
    owner chain hook and a party attach for owners other than FB. The shell  
    pool grows to 120 for the pet trackers (two pet tokens per frame).  
    Nothing is built or registered until a toggle is on. Range is re-read on  
    a 0.5s ticker only while a pet button is visible, since  
    UNIT\_IN\_RANGE\_UPDATE is not documented for pet tokens. Pure secure  
    attributes and a visibility driver, no restricted snippets, so it runs  
    the same on WoW Forever.  
- Merge pull request #2223 from DlargeX/main  
    spelling fixes, removed unused strings, added new Strings for German Locals  
- Merge pull request #2242 from andybergon/fix/character-crafted-colours  
    Fix crafted item-level colours on the character sheet  
- Merge pull request #2241 from dfrisone/feat/forever-nameplate-sunder  
    feat(forever): Show Sunder Armor on enemy nameplates  
- Merge pull request #2240 from msromike/fix/forever-gcd-spell  
    fix(forever): GCD circle and GCD bar never show on Forever  
- Merge pull request #2239 from Shiyan66666/main  
    Update zhCN for v9.2.9  
- Merge pull request #2238 from labrie75/Fix-health-text-and-Run-Summary-show-K/M-instead-of-만/万-units-on-Korean-and-Chinese-clients  
    Fix: health text and Run Summary show K/M instead of 만/万 units on Korean and Chinese clients  
- Merge branch 'main' into Fix-health-text-and-Run-Summary-show-K/M-instead-of-만/万-units-on-Korean-and-Chinese-clients  
- fix(forever): GCD circle in combat when 29515 values are secret  
    On Forever, 29515's duration/startTime are secret in combat:  
    - the stop-event compare threw "attempt to compare ... secret number";  
      it is now pcall'd and a secret read keeps the ring (same rule as the  
      ResourceBars GCD bar stop handler)  
    - the pcall'd start read failed silently, so the ring never showed in  
      combat; start logic moves to ArmGCDRing(), which on secret values pushes  
      C\_Spell.GetSpellCooldownDuration into the ring's Cooldown via  
      SetCooldownFromDurationObject (gated on the readable isActive), like the  
      GCD bar's native path  
    - with Combat Only, the pull GCD was dropped because the pull cast lands  
      before combat starts; the combat-start visibility pass now arms the ring  
      for whatever of that GCD remains  
    Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>  
- fix(locales): refresh generated keys  
- fix(character): colour crafted item levels by crest tier  
- Merge pull request #2235 from labrie75/koKR-+927-keys-across-all-modules  
    koKR: +927 keys across all modules, fix two broken format strings, un…  
- feat(forever): Show Sunder Armor on enemy nameplates  
    Warrior tanks on WoW Forever want to watch Sunder Armor stacks on their  
    pulls. Sunder is one debuff per target that every warrior's casts stack  
    onto, so with the default Only My Casts filtering a tank loses sight of  
    it the moment someone else applies the last stack, and each of its five  
    ranks is a separate spell id.  
    Add a Show Sunder Armor toggle to the nameplate Extras, built only for  
    warriors on Forever and off by default. When on, the debuff container  
    gets its own single-frame group for all five ranks from any caster, and  
    every other debuff group excludes them, the same shape as the Blood  
    Plague show-once group. Ranks the user already lists in Tracked Auras  
    stay with those lists. The class and client are checked where the  
    groups are built, so a profile shared with other classes or copied to  
    retail does nothing.  
    Cost: nothing while off. While on, one extra engine aura group per  
    debuff container; no new events and no Lua aura reads.  
- fix(forever): read the GCD from spell 29515 on Forever  
    C\_Spell.GetSpellCooldown(61304) returns nil on the Forever client, so the  
    QoL cursor GCD circle and the ResourceBars standalone GCD bar never  
    started. Forever reports the GCD on Classic's 29515. Each file now picks  
    the reference spell once via EllesmereUI.IS\_FOREVER; Midnight keeps 61304.  
    Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>  
- Merge pull request #2233 from takiguru/threat-meter-rework  
    Threat meter rework  
- Merge branch 'EllesmereGaming:main' into Fix-health-text-and-Run-Summary-show-K/M-instead-of-만/万-units-on-Korean-and-Chinese-clients  
- Merge pull request #2225 from Barbiero/feat/skyriding-classic-vigor  
    feat(skyriding): Blizzard / Classic WoW UI bar styles and classic vigor gems  
- Update zhCN  
- Add files via upload  
- Add files via upload  
- Add files via upload  
- Add files via upload  
- Merge branch 'main' into feat/skyriding-classic-vigor  
- Merge pull request #2226 from AlexTheAlmighty/feat/unitframe-important-cast-glow  
    feat(unitframes): opt-in Important Cast Glow on target and focus cast…  
- Merge pull request #2229 from dfrisone/fix/forever-secondary-stats  
    fix(forever): show spell, ranged or melee crit and haste; drop Mastery and Versatility  
- Merge pull request #2227 from dfrisone/feat/raid-text-offset-range  
    feat(raidframes): wider text offset range on Text Display  
- Merge pull request #2191 from JuJuFX-dev/fix/tooltip-ilvl-inspect-throttle  
    Fix(BlizzSkin): tooltip ilvl inspect throttle  
- Merge pull request #2219 from dfrisone/fix/forever-profile-spec  
    Fix(Profiles): resolve the spec through C\_SpecializationInfo  
- Merge pull request #2222 from dfrisone/feat/raid-buff-size-80  
    feat(raidframes): buff indicator size slider goes up to 80  
- Update koKR.lua  
- Merge pull request #2218 from dfrisone/feat/raid-debuff-size-80  
    feat(raidframes): debuff size sliders go up to 80  
- Merge pull request #2217 from Barbiero/locale/ptbr-since-929  
    ptBR: translate Threat Meter, faction indicator, heal/spell cost prediction, pet happiness and more  
- Merge pull request #2216 from RoakStatic/feat/cdm-adjust-crop  
    [Feature] Add Adjust Crop for Cropped icon shape in CDM  
- koKR: +927 keys across all modules, fix two broken format strings, unify Shifter wording  
    ## What does this PR do?  
    Updates the Korean locale only -- no source changes. 7,301 -> 8,228 keys  
    (+927 new, 6 values corrected, none removed). New keys are placed in each  
    module's existing section, not in a separate block.  
    | Area | Added |  
    |---|---|  
    | Core | style cards and restyle launch popup, video guide and overrides warning, performance (taintLog) reminder, visibility-condition notes, Style page descriptions, texture/font tooltips, donor page labels, global search keywords |  
    | Patch Notes | 57 entries that other locales already carry |  
    | Unit Frames | Frame Source & Visibility cog, absorbs/heal prediction (Overheal, texture, preview eye), Faction Indicator and its settings/icon styles, level difficulty color, dynamic health color, purgeable buff glow, debuff filter match modes, pet happiness, section header ABSORBS AND HEALS |  
    | Raid Frames | party frame style, custom group order, Show In, highlight borders, per-size layout tooltips (incl. 20/40 Man), click-cast keybind conflict |  
    | Resource Bars | Swing Timer, Arcane Soul helper, threshold notes, Blizzard class resource art, Border Around All |  
    | Data Bars | volume block, crest block (all options), zone/coordinates, gold abbreviation |  
    | QoL | right-click targeting, signup note, Raid Tools (markers, pull timer, Compact Band), cursor circles, Party Mode, Battle Res, search keywords |  
    | Blizzard Skin | reload notices for all 30 window reskins, window skin on/off, widget bar |  
    | Cooldown Manager | Replace with Buff, column grow direction, apply height/width to all horizontal/vertical bars |  
    | Quickdraw / Mythic+ Tools / Nameplates / Chat / Bags / others | pings, grid settings, split-time compare, current pull, level/elite icon position, channel abbreviations, split dialog, and smaller gaps |  
    | WoW Forever | Threat Meter and Flight Timer settings, character sheet stat abbreviations |  
-  Value changes (6)  
    | Key | Before | After | Why |  
    |---|---|---|---|  
    | `(%1$d Chest)` | `(상자 %1$개)` | `(상자 %1$d개)` | missing `d` -- `Lf` raised "invalid option in format" in the Run Summary |  
    | `%1$d Deaths` | `사망 %1$회` | `사망 %1$d회` | same broken specifier |  
    | 4 Shifter strings | Shifter / 시프터 | 패널 이동 | match the module name already used in settings (`Shifter` = 패널 이동) |  
    ## How was it tested?  
    Running on a live koKR client as the working copy; the Run Summary format  
    error is gone after the fix. File parses clean, 8,228 unique keys with zero  
    duplicates, every `%1$d`-style specifier in a key is present in its value,  
    and a line scan confirms no raw newlines inside string literals.  
- fix: make it more resource friendly  
-  refactor(forever essentials): rework threat meter  
- feat(raidframes): Name offset range to -500..500  
    Requested by Ellesmere: the Name Offset cog on Text Display now spans -500 to 500  
    on both axes. The runtime passes the offsets straight to the anchor, so no clamp  
    needs widening.  
- fix(forever): show spell, ranged or melee crit and haste; drop Mastery and Versatility  
- feat(raidframes): wider text offset range on Text Display  
- fix(skyriding): show HUD parts before laying them out  
    A row, the Whirling Surge icon or the gem row that was re-anchored and  
    resized while hidden, then shown in the same pass, drew its pips piled  
    up in one place, or did not draw at all, until a later rebuild. This  
    happened when switching Vigor Style between Bars and Classic Gems,  
    toggling Whirling Surge back on, or hiding the speed bar. Rebuild now  
    shows each part before anchoring and sizing it.  
- feat(unitframes): opt-in Important Cast Glow on target and focus cast bars  
- ptBR: translate the Dragon Riding bar and vigor styles, bar and icon toggles, full-charge sound and Whirling Surge icon size; use the official name for Second Wind  
- feat(skyriding): bar styles and classic vigor gems on the Dragon Riding HUD  
    Adds two independent options to the Dragon Riding HUD:  
    - Bar Style: Modern (the existing look, still the default), Blizzard or  
      Classic WoW UI, framed exactly like the Resource Bars' Blizzard Style  
      and Classic WoW UI so the HUD and the class resource bar match.  
      Both frame the bar column as one box, like the Resource Bars' Border  
      Around All, with a one-pixel divider between the rows and between the  
      charges: Blizzard with the Cooldown Manager bar panel (border drawn  
      above the bars) and each row clipped to the stock bar shape and  
      bevelled, as the Resource Bars keep their grouped bars, Classic WoW UI with the shared vanilla cast bar frame  
      (Border Size sizes it, as on the Resource Bars). The Whirling Surge  
      icon gets the action button frame, rounded mask and rounded cooldown  
      swipe under Blizzard, and the vanilla slot ring under Classic WoW UI.  
      Bars keep their own texture and colours in every style.  
    - Vigor Style: Bars (the existing charge row, still the default) or  
      Classic Gems. Classic Gems rebuilds Blizzard's original skyriding vigor  
      display from the art the client still ships, in place of the charge  
      row: the six gems with their wing decor, the refill swirl and pulse on  
      the charging gem, the spark on the fill line, and the flash when a gem  
      fills. It sits above the bar column and has its own scale slider.  
    Also:  
    - The speed bar, Second Wind and Whirling Surge can each be hidden.  
    - The Whirling Surge icon can be given its own size. Until it is, it  
      stays as tall as the full bar column, as before; the shorter of the  
      icon and the shown bars is centred on the other.  
    - Optional sound when a skyriding charge fills (off by default).  
    - Unlock Mode sizing follows whichever parts are shown.  
    - HUD sizes are rounded to whole physical pixel pairs so the  
      centre-anchored HUD stays on the pixel grid.  
    - Rows that stay in the layout are no longer hidden and re-shown on every  
      rebuild.  
    - Hidden parts of the HUD are not updated, and charges that refill while  
      the HUD is hidden repaint without the chime or flash.  
- removed unused Strings, added new Strings for German Locals  
- feat(raidframes): buff indicator size slider goes up to 80  
- Fix(Profiles): resolve the spec through C\_SpecializationInfo  
    WoW Forever does not load Blizzard\_DeprecatedSpecialization, so the loose  
    GetSpecialization and GetSpecializationInfo globals are nil there and the  
    profile system read every Forever character as having no spec:  
    - the login spec handler never saw a spec transition, so SpecOverrides\_Apply  
      never ran after login and an imported profile's layout layer was never  
      applied (its import window stayed open for good, leaving live anchors as  
      import residue: unit frames anchored in the layer sat at screen center);  
    - its new-character retry ticker restarted at every login;  
    - spec resolution at import time and the CDM spec list saw no spec.  
    The same five call sites now use C\_SpecializationInfo, as the Cooldown Manager  
    already does since #2211. Retail is unchanged: the globals were aliases of  
    these functions there.  
- feat(raidframes): debuff size sliders go up to 80  
- Update deDE.lua  
- Update deDE.lua  
- ptBR: translate the WoW Forever Threat Meter, faction indicator on unit frames and nameplates, heal prediction and spell cost prediction, pet happiness, level difficulty color, character sheet item stats, swing timer weapon options and Party Mode spinning; drop keys for removed strings  
- Merge remote-tracking branch 'upstream/main'  
- CDM: Adjust Crop for Cropped icon shape  
- Merge pull request #2215 from LoChinAn/locale-zhtw-threat-meter-faction-indicator  
    zhTW: translate 161 new keys and prune 49 dead ones  
- zhTW: translate 161 new keys and prune 49 dead ones  
    Add Traditional Chinese for the v9.2.7-v9.2.9 additions: the Forever  
    Essentials threat meter page, the faction indicator on unit frames and  
    nameplates, heal prediction, spell cost prediction, hunter pet happiness,  
    the WoW Forever character sheet item stats, swing timer tracked weapons,  
    custom raid group order and the Party Mode spinning checklist. Also cover  
    the unit frame preview-eye tooltips and the Forever Essentials search  
    terms, which static scanning cannot see.  
    Remove 49 keys no source string can produce any more (deleted features,  
    removed dead code, retired WoW Forever beta notices) and fix one Cleave  
    spell name typo to the official client rendering.  
- Merge remote-tracking branch 'upstream/main'  
- spelling fixes, removed unused strings  
- Tooltip: simplify item level inspect pacing  
    A fresh analysis of the traces showed the dropped inspects come from  
    request bursts only; single requests close together are all answered.  
    That leaves several parts of the pacing without a job, and some of them  
    caused problems of their own.  
    - Remove the inspect window watchdog. It never fired once the bursts  
      were gone, could open a window mid-combat or for an earlier target,  
      and made tooltip requests wait until its deadline.  
    - Remove the post-Inspect hold-off; the 2s gap after any request,  
      Blizzard's included, already covers it.  
    - Timed gaps now postpone the dwell instead of dropping the hover, since  
      raid and party frames never refresh their tooltip.  
    - Passive mode starts only after another addon's request was actually  
      seen, not at login, and the user's own Inspect no longer counts as a  
      foreign request.  
- Tooltip: harden item level inspect handling  
    - pcall the tooltip re-Show in the INSPECT\_READY handler; it now runs  
      for every source's result, also in combat, and a tainted re-Show can  
      be denied as forbidden access.  
    - Skip the InspectUnit hold-off and watchdog once Show Item Level is  
      turned off, even before the handler has cleared the active flag.  
    - Install the InspectUnit hook together with the rest of the inspect  
      machinery, so nothing is hooked while the option is off.  
    - Return early from the tooltip request while a dwell for the same unit  
      is already pending; the dwell re-checks every gate itself.  
- Tooltip: keep item level inspect pacing at zero cost while disabled  
    The inspect machinery added for Show Item Level ran regardless of the  
    setting: the INSPECT\_READY handler stayed registered, the NotifyInspect  
    hook recorded every request, and the watchdog re-sent inspects for users  
    who had the option off.  
    - Register INSPECT\_READY and install the NotifyInspect hook only when  
      Show Item Level is on (at login from the tooltip data init, or on the  
      first unit tooltip after it is turned back on). With the option or the  
      tooltip reskin off after a reload, nothing is registered or hooked.  
    - The handler unregisters itself once the option is turned off; the  
      hooks then return immediately.  
    - The watchdog and the tooltip hold-off after InspectUnit only run while  
      the option is active.  
    - Check the hard blocks (own inspect, talent inspect, passive mode)  
      before arming the dwell timer, and never request the player held by an  
      inspect window that never opened, which would pop it open later.  
    - Sweep expired item level cache entries at most once per TTL.  
- Tooltip: pace item level inspects so Blizzard's inspect window opens  
    With Show Item Level enabled, the tooltip sent ClearInspectPlayer plus  
    NotifyInspect for every uncached player it was shown for. Sweeping the  
    cursor over raid frames fired several requests in under a second, after  
    which the server silently dropped inspect requests for a few seconds,  
    including Blizzard's own. The inspect window only opens on a matching  
    INSPECT\_READY, so it stayed closed with no error.  
    - Tooltip requests wait for the cursor to rest on a unit (0.9s) and keep  
      2s clear of the last request from any source (tracked via a  
      NotifyInspect hook).  
    - Passive mode: while another addon polls inspects, the tooltip sends  
      nothing. The INSPECT\_READY handler is now always registered and caches  
      every result, whoever requested it.  
    - Watchdog: if the inspect window has not opened, re-send the request  
      once at about 1.2s and once at about 5s, keeping clear of other  
      requests. A single timer chain serves all inspects.  
    - No tooltip requests while the talent frame is inspecting someone.  
- feat(cdm): Out of Range Coloring for spells added by Spell ID  
    Spells added by Spell ID render on EllesmereUI's own icon frames, so  
    Blizzard's viewer never tinted them out of range. Add a per-spell  
    Out of Range Coloring option (default Off) for those spells. When on,  
    the range check is armed only if the spell has a range, and the icon is  
    repainted on SPELL\_RANGE\_CHECK\_UPDATE and PLAYER\_TARGET\_CHANGED with  
    Blizzard's out-of-range color, outranking the resource dim. Events  
    register on the first arm and drop when the last armed icon releases;  
    override-range disarming now leaves ids a custom icon still holds.  
    Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>  
