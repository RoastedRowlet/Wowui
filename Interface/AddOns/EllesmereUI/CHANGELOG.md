# EllesmereUI

## [v8.7.5](https://github.com/EllesmereGaming/EllesmereUI/tree/v8.7.5) (2026-08-04)
[Full Changelog](https://github.com/EllesmereGaming/EllesmereUI/compare/v8.7.4...v8.7.5) [Previous Releases](https://github.com/EllesmereGaming/EllesmereUI/releases)

- Release v8.7.5  
- Merge pull request #1186 from Crazyyoungs/main  
     koKR : Update koKR translations and add missing strings  
- Merge pull request #1185 from dfrisone/rf-tier-container-stale-geometry  
    RaidFrames: re-base the hidden container when leaving a raid (tier position drift)  
- Fix duplicate keybind translation in koKR.lua  
- Add new localization strings for Korean  
- Merge remote-tracking branch 'upstream/main' into rf-tier-container-stale-geometry  
- Merge pull request #1184 from Kirihasio2/feature/partymode-spinning-bars  
    Party Mode: add optional spinning action bars  
- Merge pull request #1183 from Kirihasio2/feature/actionbar1-disable-auto-paging  
    Add Action Bar 1 auto-paging opt-outs for forms and skyriding  
- Merge pull request #1182 from Kirihasio2/feature/loot-roll-invite-skins  
    [Feature] New Reskins  
- Merge pull request #1181 from LoChinAn/locale-zhtw-damage-meters-mplus-delves  
    zhTW: translate 22 keys and correct the Delves wording  
- Merge pull request #1085 from DlargeX/main  
    add more missing German Locals, removed double entrys, little Optimizations in german translation  
- RaidFrames: re-base the hidden container when leaving a raid (tier drift)  
    With an alternate raid size override configured, leaving the raid left the  
    (now hidden) raid container at the last tier's position and footprint: the  
    roster handler gated LayoutGroups AND \_ApplyTierOffset on framesVisible, so  
    nothing re-derived the dormant container's geometry. Unlock mode's mover  
    reads live container geometry, so out of raid the Raid Frames control  
    appeared at the stale tier spot with a stale tier-sized box. Dragging it  
    "back where it belongs" and saving then stored a center measured on the  
    wrong footprint with no rebase (no override resolves outside the raid),  
    shifting the saved base by half the width delta plus the tier offset --  
    the "whole layout drifts left after visiting a raid" corruption, which  
    compounds on every fix-up attempt.  
    \_ApplyTierOffset now also re-derives the container SIZE while the frames  
    are hidden (LayoutGroups still owns it while shown), and both the roster  
    and combat-end paths call it outside the framesVisible gate so leaving a  
    raid immediately re-bases the dormant container to the geometry the mover  
    save path assumes.  
- Party Mode: add optional spinning action bars  
    Adds a "Spinning Action Bars" toggle to the Party Mode options page, with  
    a cog holding a Speed slider (degrees per second, default 120).  
    While Party Mode is active the buttons orbit around their own bar's  
    centre. They are re-anchored rather than rotated, so every button stays  
    upright and square and clicking, cooldowns and keybinds are unaffected.  
    Re-anchoring a button is SetPoint on a protected frame, which is blocked  
    in combat, so the orbit holds position there and resumes when the  
    lockdown lifts.  
    Costs nothing when off: the driver frame is only shown while Party Mode  
    is active and the option is on, so its OnUpdate does not fire otherwise.  
    All new state lives in a do/end block published on ns, so the file's  
    main-chunk local count is unchanged (already at the 200 cap).  
    Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>  
- Add Action Bar 1 auto-paging opt-outs for forms and skyriding  
    Two new toggles under Action Bar 1 > PAGING:  
    - Disable Form Paging: bar 1 stops following bonusbar 1-4 (shapeshift,  
      stealth, stance)  
    - Disable Skyriding Paging: bar 1 stops following bonusbar 5  
    Both are off by default, so existing behaviour is unchanged.  
    Suppressing the swap in the state driver is only half of it. MainBar  
    keybinds are native ACTIONBUTTONn commands, which resolve against the  
    engine's paging, and bonusbar stays a native concept whether or not our  
    icons follow it. Left on the native route, a stealthed keypress would  
    cast the page-7 ability the button no longer shows. Both toggles  
    therefore force MainBar onto the click route in UpdateKeybinds, the same  
    route custom paging already uses, so key and icon always agree. The cost  
    is press-and-hold repeat casting on bar 1 while a toggle is on; both  
    tooltips say so.  
    Vehicle, override and possess paging are deliberately untouched: those  
    replace the player's abilities outright, so suppressing them would leave  
    no way to use the vehicle. Manual [bar:N] paging is untouched too. An  
    explicit per-form page set in the dropdowns still applies under Disable  
    Form Paging, since that is a stated choice rather than an implicit swap.  
    Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>  
- Add loot roll, Loot Rolls window and group invite window skins  
    Three new packs for the Blizzard Window Skins system, each with its own  
    style card (EllesmereUI / Modern / Blizz Default):  
      lootroll     GroupLootFrame roll popups -- shell + atlas border, squared  
                   icon, flat roll timer in the user's bar-fill color. The roll  
                   glyphs (dice / coin / transmog / pass) stay Blizzard's, and  
                   the item name keeps its quality color.  
      loothistory  GroupLootHistoryFrame -- shell, encounter dropdown, roll  
                   timer, flattened scroll bar, result rows and resize grip.  
      groupinvite  LFGListInviteDialog and LFGInvitePopup -- shell, Accept /  
                   Decline, role check buttons.  
    Notes for review:  
    * All three live in one do...end block declaring a single file-scope local,  
      the shape the Social UI pack uses. WindowPacks.lua sits near Lua 5.1's  
      200-local ceiling, where going over is a compile error rather than a  
      warning; peak is 192 after this change.  
    * GroupLootHistoryFrame is skinned on its FIRST OnShow, never from the load  
      pass. Touching a ScrollBox-backed frame's geometry before its first layout  
      poisons ScrollBox.updateLock, which ScrollBoxListMixin:Update reads on its  
      first line, and every later Update then taints its own execution. The pack  
      is also enumerative for the same reason -- no CommonChrome or ButtonsIn  
      sweeps, since the tree here is pooled loot rows.  
    * GroupLootContainer is deliberately never written to: it is a UIParent  
      managed frame, and writing its layout flags taints the secure  
      managed-layout pass. The roll frames themselves are skinned instead, and  
      every hook is debounced to the next frame so nothing runs inside  
      GroupLootContainer\_Update's own call stack.  
    * On the invite dialogs the role glyph is a region of the dialog, so the  
      shell's region fade would take it along with the border art. It is found  
      by inspecting each texture rather than by key name (the key has moved  
      between templates) and parked on WSkin's PROTECT\_KEYS list, which both the  
      initial fade and later Restrip passes honor.  
    Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>  
- zhTW: fill 13 keys a full-tree scan turned up  
    These predate this batch. They sit in dropdown/segmented-control value tables  
    whose siblings are all translated, so each one rendered as the lone English  
    entry in an otherwise translated list:  
      Damage (DPS)                 next to DPS / Damage / Damage | DPS  
      Left (Top), Right (Bottom)   the CDM Show Icon dropdown  
      When Any/All Present/Missing the Buff Manager Show When dropdown  
      Single, Form specific        the druid power bar mode switch  
      Clean (Flat)                 the absorb style list, next to the stripe set  
      Favor                        the bar label list, next to Micro/Bags/XP/Rep  
    Beacon Reminders is a module title, matching AuraBuff Reminders next to it.  
    Sporefall is the Midnight raid; the zhTW client calls it 孢子之殞, which is  
    where the neighbouring Voidspire and Dreamrift entries came from too.  
- zhTW: use the official 探究 for Delves  
    探掘 does not appear anywhere in the client's zhTW GlobalStrings. The  
    official rendering is 探究 (DELVES\_LABEL), 探究夥伴 (DELVES\_COMPANION\_LABEL)  
    and 探究旅程 (DELVES\_REPUTATION\_BAR\_TITLE). Correct the three existing  
    entries rather than have the new Hide in Delves follow the fan wording.  
- zhTW: translate 9 keys from the Lf() rewrites in Damage Meters and M+  
    Upstream replaced several string concatenations with single Lf() calls, so  
    the catalog key is now the whole sentence rather than its fragments. Four of  
    these reuse the wording the fragments already carried, verbatim:  
      You may only have %1$d windows active  <- "You may only have " + " windows active"  
      %1$s's Death Recap                     <- "'s Death Recap"  
      %1$s's %2$s Breakdown                  <- " Breakdown"  
      Overall %1$s                           <- "Overall Deaths"  
    The superseded fragment entries are left in place. The tail fragments of  
    those chains never reached the catalog either, so clearing the dead set is  
    a separate pass.  
    Also covers the Damage Meters window menu (Hide in Delves, Hide in PvP),  
    the add-window hint, and the Mythic+ death counter. Chinese has no plural  
    form, so the singular and plural death lines share one translation.  
- Merge pull request #1178 from dfrisone/cdm-focuskick-rearm  
    fix(cdm): FocusKick cast sound goes silent and never re-arms  
- Merge pull request #1177 from math280h/chore/improve-workflow-security  
    chore(ci): improve github workflow security  
- refactor(cdm): tidy RefreshFocusKickProxies after review, no behaviour change  
    Self-review of the five focus-kick commits before opening the PR. Control  
    flow is byte-for-byte equivalent; only structure and comments move.  
    - The two identical 'if bd and bd.enabled ~= false' guards are merged, so  
      hasContent and soundWanted are derived in one pass over the same data.  
    - The rationale for the sound's weaker requirement now sits where  
      soundWanted is computed, instead of above the hasContent branch it does  
      not describe.  
    - Two comments that had run together in the retry block are separated, so  
      the note about arming during the unresolved window reads against the line  
      it explains.  
    - The inner loop variable and the interrupt-spell pick no longer share the  
      name 'sid'.  
    Two things verified while reviewing, both clean: RefreshFocusCastProxyUnit  
    is only ever called from the options file, so the new call into  
    RefreshFocusKickProxies cannot recurse; and CDMFinishSetup is the  
    documented one-time construction hub guarded by \_cdmSetupStarted, so the  
    PLAYER\_ENTERING\_WORLD frame is created once per session rather than  
    accumulating.  
- fix(cdm): re-arm FocusKick when its bar content changes  
    Last gap in the focus cast sound. The tester's sequence: log in with an  
    empty kick bar (NOT CREATED, correct), add the interrupt spell, sound still  
    dead, take a portal, sound starts working.  
    AddSpellToBar and RemoveSpellFromBar are the chokepoints for assignedSpells  
    and neither re-evaluated the FocusKick proxies, whose arming is gated on  
    exactly that content. Nothing else re-runs it either, so the state stayed  
    wrong until an unrelated rebuild happened to fire -- a spec change, or the  
    PLAYER\_ENTERING\_WORLD re-arm added earlier, which is precisely why a portal  
    'fixed' it.  
    Both now call RefreshFocusKickProxies, tagged so the probe shows which edge  
    ran. The remove side is a re-evaluation rather than a teardown: with an  
    explicit interrupt spell the cast sound is meant to survive an empty bar.  
    Guarded on the focuskick key, so every other bar's add/remove is unchanged  
    -- including the ghost-bar removal AddSpellToBar performs internally.  
- feat(cdm): the focus cast sound no longer requires the kick on the focus bar  
    Requested: play the focus-cast sound without having to put the interrupt  
    icon on the FocusKick bar.  
    The sound handler never needed it. It requires exactly two things, a  
    configured sound and an interrupt spell id to run its 'is my kick ready'  
    cooldown check against, and the bar's assigned spells are only the FALLBACK  
    source for that id -- an explicit focusKickInterruptSpellID satisfies it  
    alone. But arming was gated on hasContent, which demands a positive spell  
    on the bar, so the runtime handler and the gate that installs it disagreed  
    about what the feature needs. Taking the kick off the bar killed a sound  
    that had everything required to keep working.  
    The cast sound now arms on its own condition: a configured sound plus a  
    resolvable spell id, explicit or from the bar. The icon-bearing parts of  
    the family, the anchor proxy and the reminders, keep the original  
    bar-content gate and are unchanged.  
    It also arms during the store-unresolved window, since an explicit spell id  
    lives on the bar data rather than in the per-spec spell store and does not  
    have to wait for the retry.  
- fix(cdm): re-arm the FocusKick cast sound after loading screens and late spell data  
    The previous two commits fixed real defects but not the one the reporter  
    keeps hitting. His probe output after that build was unchanged:  
    spells=1(1 pos) alongside sound=NOT CREATED -- a fully populated bar with  
    no proxy.  
    Arming is demand-gated and effectively one-shot: RefreshFocusKickProxies  
    builds the proxy only on its hasContent branch, and its only callers are  
    setup and the tail of BuildAllCDMBars. GetBarSpellData returns nil until  
    the active spec key resolves, so any pass that runs during that window sees  
    an apparently empty bar, declines to arm, and is never retried. The sound  
    then stays dead for the whole session while the bar looks fine, which is  
    exactly why a spec change 'fixes' it -- that reruns BuildAllCDMBars.  
    Two re-arms, both cheap and idempotent:  
    - when the refresh finds the spell store unresolved it schedules one bounded  
      retry rather than simply returning,  
    - and PLAYER\_ENTERING\_WORLD schedules a deferred refresh, so a login or a  
      zone change cannot leave the proxy permanently unbuilt.  
    The refresh early-returns on a genuinely empty bar, so neither path installs  
    anything for users who do not use the feature.  
- fix(cdm): show a spell name, not a raw id, for a stale FocusKick interrupt  
    Removing the kick from the FocusKick bar empties assignedSpells while  
    focusKickInterruptSpellID keeps pointing at it. The dropdown builds its  
    label map only from spells currently on the bar, so the stored key had no  
    label and the widget fell back to rendering the key itself: the row showed  
    a bare '47528'.  
    The selection now gets a resolved spell name, but deliberately is NOT added  
    to spellOrder, so it renders correctly without appearing as a selectable  
    option on a bar that no longer holds it. The list still reads  
    '(no spells on bar)', which is accurate.  
    Cosmetic only; no change to which spell the kick logic uses.  
- fix(cdm): do not tear down the FocusKick proxy when the spell store is unresolved  
    Second half of the focus cast sound bug, and the one that matches the  
    original report: sound works, dies after a port or a zone change, and only  
    returns when something rebuilds the bars.  
    hasContent read the spell list as:  
        local sd = ns.GetBarSpellData(FOCUSKICK\_BAR\_KEY)  
        local spells = sd and sd.assignedSpells  
    GetBarSpellData returns nil while the active spec key is unresolved (not  
    specKey or specKey == "0"), which is precisely the state during a loading  
    screen. That nil was indistinguishable from an empty bar, so the else  
    branch ran and unregistered a working proxy. Nothing re-armed afterwards,  
    because the only two arming callers are setup and the BuildAllCDMBars tail.  
    Now a nil store is treated as 'unknown', not 'empty': the refresh returns  
    without touching the proxy and the next rebuild arms it properly.  
    Confirmed against the probe: a spec change fired BuildAllCDMBars with  
    spells=1(1 pos) and the proxy went NOT CREATED -> LISTENING, proving the  
    arming path itself is correct and only its reachability was at fault.  
- fix(cdm): let the FocusKick options path create the cast-sound proxy  
    The focus cast sound stayed dead with the bar fully populated. The probe  
    caught both facts at the same instant: spells=1(1 pos) and  
    sound=NOT CREATED, which cannot both be true if the arming had run.  
    RefreshFocusKickProxies only builds the proxy on its hasContent branch, and  
    it has exactly two callers: setup, and the tail of BuildAllCDMBars. Adding  
    a spell in the options writes assignedSpells without re-arming anything, so  
    a bar that was empty when the last arming ran stays soundless no matter  
    what is added to it afterwards.  
    RefreshFocusCastProxyUnit is what the options page calls, and it opened  
    with 'if not \_focusCastProxy then return end' -- so the one path the user  
    can reach by hand was also the one path that could not recover the state.  
    It now runs the full refresh instead of returning, which makes the  
    reporter's own workaround (touch the options) reliable rather than  
    incidental.  
    Known gap, deliberately not guessed at: the spell picker writes  
    assignedSpells in several places in the options file and none of them  
    re-arm. Locating that commit path needs one more test round; this change  
    does not depend on it.  
- chore(ci): improve github workflow security  
- add more missing German Locals  
- Merge remote-tracking branch 'upstream/main'  
- Merge pull request #1148 from jacpub/feature/damage-meters-delve-pvp-visibility  
    FEATURE: Damage Meters: add Delve and PvP hide options  
- Merge pull request #1174 from dfrisone/ab-vehicle-leave-combat-block  
    fix(actionbars): don't touch the vehicle leave button during combat  
- Merge pull request #1172 from Shiyan66666/main  
    Update zhCN.lua  for  8.7.4  
- Merge pull request #1171 from dfrisone/ab-castkick-gate-reopen  
    fix(actionbars): the cast kick must re-open the rate gates it re-arms the wave for  
- Merge pull request #1170 from labrie75/Localization-wrap-remaining-untranslated-strings-with-L()  
    Localization: wrap remaining untranslated strings with L()  
- Merge pull request #1168 from LoChinAn/zhtw-sync-2026-08-03  
    zhTW: translate 89 new keys (supersedes #1121)  
- Merge pull request #1167 from dfrisone/ab-range-reacquire-sweep  
    fix(actionbars): re-evaluate range state when a bar re-acquires its slots  
- Merge pull request #1166 from nulltyto/fix/chat-chrome-strata  
    Drop chat chrome from DIALOG to MEDIUM strata  
- Merge pull request #1164 from dfrisone/Empowered-Issue  
    Fix empowered spells reverting to Press-and-Tap after a loading screen  
- Merge pull request #1163 from dfrisone/ab-drag-empty-combat  
    Action bars: allow combat spell drags to reveal empty slots with Always Show Buttons off  
- Merge pull request #1162 from jtokoph/patch-1  
    fix(performance): Properly set graphicsSpellDensity to 0 when optimizing performance  
- fix(actionbars): the cast kick must re-open the rate gates it re-arms the wave for  
    Cooldown swipes started visibly late on 8.7.4, and worse while spamming a  
    keybind.  
    UNIT\_SPELLCAST\_SUCCEEDED zeroes both rate gates so the cast's own repaint  
    cannot be throttled, and schedules the kick as the guaranteed post-cascade  
    pass. But a cooldown event arriving in the cast's OWN frame consumes that  
    opening: it runs a pass off state read inside the cooldown API's transient  
    window, then re-arms the storm cap to +0.15s and the slow tier to +0.5s.  
    The kick already re-armed the cast wave to survive exactly that theft, but  
    left the gates re-armed, so the corrective pass it exists to perform was  
    capped out of the walk, and the slow tier -- every utility spell, item and  
    macro, which is most of the bar -- kept whatever the transient push painted  
    until its 0.5s gate expired, or until the ~1/sec heartbeat if no event  
    landed on the gate.  
    Measured with a repaint-latency harness across two captures before and one  
    after, roughly 8-11k frames each: swipe start a mean of 304ms and 231ms late  
    over ~240 samples each, max 616ms, falling to a mean of 85ms with nothing  
    past 208ms and the entire 500ms-plus band empty. What named the cause was  
    the shape rather than the mean: both pre-fix captures showed an identical 51  
    sub-frame paints, a fixed subset always prompt while the rest were always  
    late, which is a tier split and not a throttle. The worst offender in every  
    capture was a utility spell, that is, slow tier.  
    Reopening is self-limiting: the kick runs once per cast behind its pending  
    guard, and when the wave was not stolen both values are already 0, so the  
    common path is unchanged.  
- fix(actionbars): don't touch the vehicle leave button during combat  
    ADDON\_ACTION\_BLOCKED on MainMenuBarVehicleLeaveButton:HideBase(), reported  
    from the end of a Mythic+ run on 8.7.4.  
    The button is EditMode-managed, so SetShown routes through the protected  
    HideBase/ShowBase and is blocked in any combat. The gate gave up its combat  
    check unless InProtectedInstance() also agreed, but that helper requires  
    IsChallengeModeActive() for a party instance, so it is false in every normal  
    dungeon and goes false the instant a key completes. A vehicle event landing  
    in combat then called straight through into the protected op, which is  
    exactly the reported scenario.  
    The module already documents the correct rule at the micro menu and bag bar  
    site: the restriction being worked around is a protected frame op blocked in  
    combat, so InCombatLockdown is the whole gate, while InProtectedInstance is  
    for secret-value reads and reports true for a whole keystone run. This site  
    never got that treatment. Nothing is lost by deferring, since the protected  
    call could not have succeeded in combat either way and the existing  
    PLAYER\_REGEN\_ENABLED arm re-applies the state as soon as lockdown clears.  
    Two adjacent defects in the same handler, both from the same reading:  
    a redundant SetShown on a frame already in that state still trips the block,  
    so the call is now issued only on a real transition, matching the same  
    precedent; and PLAYER\_ENTERING\_WORLD's first argument is isInitialLogin, not  
    a unit, so testing it as one skipped the whole pass on a fresh login.  
- Update zhCN.lua  
- Update zhCN.lua  
- zhTW: rename Update at Upgrader to 在升級師處更新  
    The refresh tooltip quotes this button by name, so the button's own entry  
    has to read the same way.  
- zhTW: reword the band help tip and the upgrade refresh tooltip  
    Prefers 計量條 over 長條, 門檻 over 臨界值 and 浮動提示 over 提示資訊 in  
    these two entries, and keeps % as the symbol rather than spelling it out.  
- zhTW: translate 7 keys the scanner could not assemble before  
    These are concatenated strings: the fragments reach L() already joined, so  
    the key is the whole assembled sentence. harvest.py returned only the head  
    fragment until now, which is why they read as missing.  
    Covers the graphics optimizer panel, the Item Upgrade calculator's two  
    button tooltips, the Resource Bars multi-band and buff-recolor help tips,  
    the Unlock Mode grow-direction hint and the CDM custom-spell notice.  
    Where a head fragment was already translated, the assembled entry reuses  
    that wording verbatim. Blizzard graphics setting names follow the official  
    zhTW GlobalStrings.  
- zhTW: translate 43 keys from v8.7.2-v8.7.4  
    Covers the Edit Mode manual-fix popup (CDM), Blizzard atlas bar artwork  
    and split backgrounds (Resource Bars), vertical health bar fill (Unit and  
    Raid Frames), friendly nameplate title/guild subtitle, the countdown size  
    cap (Action Bars), the breakdown tooltip anchor (Damage Meters) and the  
    currency description toggle (DataBars).  
    The CDM popup message is built by concatenation and reaches L() as one  
    string, so the whole assembled message is the key -- not the leading  
    fragment the key scanner reported. Blizzard Edit Mode element names in  
    it follow the official zhTW GlobalStrings, since the steps tell the user  
    what to look for in Blizzard's own interface.  
    Also adds Recolor Text Instead Of Bar, which was never translated: the  
    new atlas warning points at it by name.  
- Update \_keys.txt  
- Update koKR.lua  
- Update EllesmereUIMythicTimer.lua  
- zhTW: add strings reached by two more scanner channels  
    Seven more keys, from options text the key scanner could not classify until  
    now: five subnav labels in the cooldown manager passed positionally to a  
    module-local helper, and two resource-bar tooltips hoisted into a local  
    before being used as a field value.  
    Ignore Pain is 無視苦痛 and Sweeping Strikes is 橫掃攻擊, both per the  
    in-game Traditional Chinese names.  
- zhTW: add v8.7.1 keys, disabledTooltip strings, threshold wording  
    Covers the friendly nameplate subtitle (title/guild), charge count hiding  
    on action buttons and the cooldown manager, Always Show Pet Frame, and the  
    battle-res tracker's display style, font outline and color options.  
    Also adds disabledTooltip strings that were never collected before: they  
    are returned from inside `disabledTooltip = function() ... end`, which the  
    key scanner classified too weakly to surface.  
    Replaces 閾值 with 臨界值 or 門檻 in seven existing entries so each one  
    matches the term already used by the neighbouring options in its panel.  
- zhTW: translate 7 new keys (Bags, Unit Frames, CDM, QoL, eyebrow badge)  
    Covers Merge Duplicate Items (Bags), Custom Duration Format warning  
    (Unit Frames), Bar/Bars pluralization (CDM), Voidforged track name  
    (QoL Upgrade Calculator), and the SPECIAL UPDATE eyebrow badge.  
- Update EUI\_RaidFrames\_BuffManager.lua  
- Update EUI\_RaidFrames\_ManagerPages.lua  
- Update EUI\_PartyMode\_Options.lua  
- Update EUI\_DamageMeters\_Options.lua  
- Update EllesmereUIDamageMeters.lua  
- fix(actionbars): re-evaluate range state whenever a bar re-acquires its slots  
    Action buttons could stay red out of range while the player stood in  
    melee, intermittently and mostly in combat, since 8.7.4.  
    Slot acquisition became refcounted in the performance series, so  
    EnableRangeCheckForBar now releases the bar's old snapshot before  
    re-acquiring. For any slot only one bar holds, that release drops the  
    refcount to zero, which wipes the cached out-of-range state and disables  
    the engine check; the re-acquire enables it again, but  
    EnableActionRangeCheck fires no initial event, so nothing repaints. The  
    button keeps the tint it was already wearing while the cache claims it is  
    in range, and the flip handler's no-change gate then swallows the next  
    in-range report. Walking into melee is exactly the report that gets  
    swallowed. Before the refcount work this could not happen: acquisition  
    only ever added slots and never touched the cache or the tint.  
    The debounced ACTIONBAR\_SLOT\_CHANGED pass re-acquires every bar, so any  
    slot change during a fight could strand a red button until the player  
    left range and came back.  
    ns.\_eabRangeSweepBar re-reads IsActionInRange for a bar, refills the cache  
    and repaints, and EnableRangeCheckForBar calls it on every acquire so no  
    caller can forget. That also fixes the dormancy reveal, which repainted  
    from a cache the hide-side release had already wiped and so painted every  
    revealed button as in range. ApplyRangeColoring's inline copy of the same  
    sweep is now redundant and drops out.  
    Dormant bars are still skipped, so the hidden-bar range savings stand.  
- Drop chat chrome from DIALOG to MEDIUM strata  
    The tab host clip, the per-tab border/separator/underline hosts and the  
    chat panel border were all pinned to DIALOG, so the 1px active-tab  
    underline and the panel border drew on top of MEDIUM Blizzard panels that  
    Raise() over the UI -- most visibly the maximized world map.  
    MEDIUM still clears everything this chrome has to cover: ChatTabTemplate  
    and DockManagerTemplate are both LOW, and the chat frame itself is LOW at  
    level 5, while these hosts sit at levels 90-100. Every frame level is  
    unchanged, so the existing interleave (per-tab border 100 > panel border  
    96-98 > underline 95 > separators 90) is preserved exactly.  
    LOW was tried first and washes out the active-tab underline; that is  
    recorded in the comment at the clip so it is not retried.  
- Update EllesmereUI.lua  
- Update EllesmereUI\_FirstInstall.lua  
- fix(actionbars): stop the empower snippet clearing typerelease  
    Blizzard sets typerelease to "actionrelease" once in the action button  
    mixin's OnLoad and never clears it, and SecureTemplates reads it on every key  
    release when the ActionButtonUseKeyHeldSpell CVar is on, not only for  
    empowered spells:  
        releasePressAndHoldAction = (not down) and (pressAndHoldAction or CVar)  
    so clearing it on non-empower buttons would leave those users' key-up path  
    with no action type and nothing to perform. Their own  
    UpdatePressAndHoldAction writes pressAndHoldAction and nothing else; this now  
    matches.  
    Harmless until now only because the snippet never ran outside a page change,  
    the trigger that would have run it elsewhere being wired to a handler the  
    state template does not implement. Fixing that trigger makes this snippet  
    live addon-wide, so the clear has to go with it. Caught in a tester dump the  
    moment the trigger started working: a flyout that had always read  
    typerelease=actionrelease came back nil.  
- fix(actionbars): empowered spells revert to Press-and-Tap after a loading screen  
    Hold-and-release needs two things: the key routed through our button, and  
    pressAndHoldAction set on that button. Only the first was ever maintained  
    reliably, and the mechanism meant to maintain the second was inert.  
    The re-check was wired as an \_onattributechanged snippet keyed on a plain  
    "eab-empower-trigger" attribute, set on the bar header frames. Those frames  
    are SecureHandlerStateTemplate, whose script is  
    SecureHandler\_StateOnAttributeChanged: it matches "^state%-(.+)" and  
    dispatches to "\_onstate-<id>", and has no \_onattributechanged path at all.  
    That belongs to SecureHandlerAttributeTemplate, which is what the override  
    controller uses. So setting the attribute fired nothing, and had fired  
    nothing since the mechanism was written. The re-check only ever ran as the  
    tail of \_childupdate-eab-page, which is installed on MainBar and custom-paged  
    bars alone, so it ran on page changes and nowhere else.  
    Blizzard writes the same attribute and gets the last word on every loading  
    screen: BUTTON\_EVENT\_LISTS.action registers PLAYER\_ENTERING\_WORLD per button,  
    the template wires OnEvent to their mixin, and its PEW branch runs Update()  
    -> UpdatePressAndHoldAction(). Zoning into an instance lands that write as  
    false. The page state does not change across the loading screen, so nothing  
    re-ran our snippet, and the spell stayed on pressAndHoldAction=false, which  
    behaves exactly like Press-and-Tap with the CVar untouched, for the rest of  
    the session. Reported as the Empowered Spell Input setting changing itself in  
    dungeons.  
    Two changes, both needed. The handler is now \_onstate-eabempower driven by a  
    state-eabempower attribute, which the state template does dispatch. And the  
    trigger moves out of the ACTIONBAR\_SLOT\_CHANGED reroute into UpdateKeybinds'  
    success path, so no caller can omit it: load time, UPDATE\_BINDINGS, the  
    combat re-arm, the housing restore and the post-loading-screen restore all  
    rebuilt the routing and left the attribute stale. Zoning needs that last one,  
    because no slot changes across a loading screen and nothing else would fire  
    the re-check.  
    The signature short-circuit is unchanged, so mouseover-conditional macro  
    storms still do not rebuild every bar every frame, and the protected  
    SetAttribute is unreachable in combat because the function bails at the top.  
    Verified in game on an Evoker: Fire Breath and Upheaval hold  
    pressAndHoldAction through a dungeon zone-in and in combat, where every  
    earlier build read false.  
- add more missing German locals  
- Merge remote-tracking branch 'upstream/main'  
- fix(actionbars): combat spell drags reveal empty slots for dropping  
    Reported: with "Always Show Buttons" disabled, an ability cannot be  
    dragged onto an empty (keybound) slot while in combat -- the empty  
    targets never appear.  
    With the option off, empty slots are parked statehidden + Hidden +  
    alpha 0 + mouse off, and EVERY reversal path was gated on being out of  
    combat: OnGridChange hard-returns in lockdown, and SetShowGridInsecure  
    defers. The secure grid path (the ActionButton1 showgrid monitor ->  
    controller broadcast) did fire, but the per-button visibility snippets  
    treated statehidden as an absolute veto, and nothing secure restored  
    alpha or mouse -- so a combat drag had no drop targets at all.  
    Fix, entirely in the restricted environment (all combat-legal):  
    - The per-button SetShowGrid/UpdateShown snippets now treat any  
      TRANSIENT grid reason (drag/spellbook/quick-keybind -- every bit below  
      ALWAYS) as overriding statehidden for within-cutoff buttons, and  
      restore alpha and mouse on the hidden->shown edge (HANDLE:SetAlpha and  
      HANDLE:EnableMouse exist in the restricted API). The edge gate keeps a  
      live on-CD alpha from being stomped; a new eab-click attribute carries  
      the bar's click-through setting so a reveal never turns a click-through  
      bar clickable; eab-withincutoff keeps icon-cutoff buttons excluded  
      (revealing those would paint slots the user configured away).  
      ApplyAlwaysShowButtons stamps both attributes for every managed bar  
      (MainBar already carried eab-withincutoff via page sync).  
    - Belt: an OnDragStart wrap on our buttons raises the grid through the  
      controller broadcast directly, so a drag that ORIGINATES from a bar  
      reveals targets even if Blizzard's monitored showgrid chain is ever  
      tainted out from under the ActionButton1 wrap.  
    - Heal: the ApplyAlwaysShowButtons grid pass clears stuck transient bits  
      outside a live drag, so a mid-combat drag whose HIDEGRID landed while  
      the insecure handler was combat-gated cannot leave empty slots visible  
      after combat (post-drag re-assert and regen ApplyAll both route here).  
    Out-of-combat behavior is unchanged (the insecure OnGridChange path  
    still runs and remains the cosmetic-complete version).  
- Change graphicsSpellDensity from 1 to 0  
    The FPS & Graphics optimization says it's supposed to be setting Spell Density to "Essential" but the code currently sets it to "Reduced"  
    I'm not sure if this was always a bug or if blizzard changed some indexes, but `"0"` is `Essential` and `"1"` is `Reduced`.  
    This corrects the logic to match the described intent.  
- updated tooltip local string  
- Merge remote-tracking branch 'upstream/main'  
- Update deDE.lua  
- Update deDE.lua  
- Update deDE.lua  
- Update \_keys.txt  
- Merge remote-tracking branch 'upstream/main'  
- Damage Meters: add Delve and PvP hide options  
- Merge remote-tracking branch 'upstream/main'  
- Merge remote-tracking branch 'upstream/main'  
- Merge remote-tracking branch 'upstream/main'  
- Merge remote-tracking branch 'upstream/main'  
- Update deDE.lua  
- Merge remote-tracking branch 'upstream/main'  
- Update \_keys.txt  
- Merge remote-tracking branch 'upstream/main'  
- Merge remote-tracking branch 'upstream/main'  
- removed double entrys, little Optimizations in german translation  
- add more missing German Locals  
- Update deDE.lua  
- Update deDE.lua  
