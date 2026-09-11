# EllesmereUI

## [v9.1.8](https://github.com/EllesmereGaming/EllesmereUI/tree/v9.1.8) (2026-09-10)
[Full Changelog](https://github.com/EllesmereGaming/EllesmereUI/compare/v9.1.7...v9.1.8) [Previous Releases](https://github.com/EllesmereGaming/EllesmereUI/releases)

- Release v9.1.8  
- Merge pull request #1913 from dfrisone/fix/chat-popout-newwindow-taint  
    Fix(Chat): keep the display bridge off windows Blizzard has not opened yet  
- Chat: keep the display bridge off windows Blizzard has not opened yet  
    Moving a chat type to a new window threw a secret-value error at  
    ChatFrameUtil.lua:711 and left the pop-out half done. Blizzard seeds the new  
    window from the source frame inside its own loop -- GetMessageInfo, compare the  
    line's accessID, AddMessage -- and our AddMessage post-hook tainted the rest of  
    that loop, so the next GetMessageInfo answered with a secret accessID.  
    Unopened chat frames now stay unbridged, and the first integrate pass after  
    Blizzard opens one installs the bridge and backfills our window from its  
    buffer.  
- Merge pull request #2023 from dfrisone/fix/castbar-centered-text-width  
    Fix centered cast-bar spell text truncation  
- Merge pull request #1997 from dfrisone/fix/tbb-target-aura-fallback  
    fix(cdm): let a tracked bar find its debuff on the target  
- Merge pull request #2043 from dfrisone/fix/cdm-per-spell-duration-text  
    cdm: keep per-spell Duration Text through a reanchor  
- cdm: keep per-spell Duration Text through a reanchor  
- Merge pull request #2042 from dfrisone/fix/actionbar-broadcaster-secret-cooldowns  
    actionbars: keep the broadcaster off while cooldowns are secret  
- Merge pull request #2041 from Barbiero/locale/ptbr-since-5a0fe20d  
    ptBR: translate Chat Bubbles and Cooldown Manager Rotation Assist styling  
- actionbars: keep the broadcaster off while cooldowns are secret  
- Refresh translatable-key count in EllesmereUILocales/\_keys.txt  
    The list itself was already current; only the header's key count had  
    drifted stale from an earlier merge.  
- fix(cdm): skip the requirement-sentence wrapper on two Rotation Assist tooltips  
    Thickness and Outset already carry complete sentences, so the "This option  
    requires X to be enabled" template was double-wrapping them into nonsense  
    in every language.  
- ptBR: translate Chat Bubbles, Cooldown Manager Rotation Assist styling, and class-special aura reminders content picker; refresh Chat search keywords  
- Merge pull request #2040 from andybergon/t3code/fix-shadowform-active-state  
    Fix Shadowform stance highlight after Voidform  
- Merge pull request #1933 from JuJuFX-dev/feature/nameplate-chat-bubbles  
    Feat: Add chat bubble customization  
- Merge branch 'main' into feature/nameplate-chat-bubbles  
- fix(actionbars): reconcile active stance highlights  
- Merge pull request #1125 from mTx87/feature/rotation-assist-styling  
    feat(cdm): customize Rotation Assist highlight  
- Merge pull request #2039 from LoChinAn/locale-zhtw-stack-splitter-stack-glow-signup-note  
    locale(zhTW): translate 40 new keys, drop 4 unreachable ones  
- locale(zhTW): translate 40 new keys, drop 4 unreachable ones  
    Covers the v9.1.6 -> v9.1.7 additions: the Bags stack splitter (its  
    dialog, the Auto Split button and the option that extends both to the  
    other bag windows), the Cooldown Manager buff-bar At Stacks glow with  
    its comparison cog and the Replace with Buff row, the global Show Glows  
    Only in Combat gate, the QoL persistent signup note popup, the Bloodlust  
    icon's Sated and Ready states, the cursor circle's centre dot, the  
    Damage Meters show/hide keybind and its scope cog, the Player Aura Bars  
    debuff display header, the Quickdraw Outfits palette and the Raid Frames  
    small-raid party layout.  
    Three older AuraBuff Reminders tooltips are backfilled in the same pass:  
    the "Where to Show" hints for the Auras, Consumables and class-special  
    sections. Only the Raid Buffs one of that family of four had ever been  
    translated, and the other three predate this range, so an incremental  
    scan would not surface them again.  
    Sated and Exhaustion use the client's own spell names (spells 57724 and  
    57723), Outfits follows Blizzard's transmog wording, and the  
    class-special reminder tooltip reuses the four nouns from its own  
    section headers (ROGUE POISONS, PALADIN RITES, SHAMAN IMBUES &  
    SHIELDS). At Stacks reads as the existing per-icon Glow at Stacks  
    feature it mirrors, so its disabled tooltip matches that feature's  
    wording too, and the Ready keys stay on the string the icon itself  
    draws rather than a shorter coinage.  
    Four lines are removed. Upstream replaced the Persistent Signup Note  
    tooltip inside this same range and renamed the Player Aura Bars section  
    header from DEBUFF TYPE ICON to DEBUFF DISPLAY, so neither old key can  
    be looked up again; the OneBag stack warning and the Nature's Swiftness  
    / Convoke macro label were dropped from the source outright. Older  
    unreachable keys are left in place -- the other locale files still carry  
    them, so pruning those is a cross-locale cleanup, not part of a zhTW  
    batch.  
- Merge pull request #2038 from dfrisone/fix/raid-size-spec-dimensions  
    Fix custom raid-size dimensions reverting with spec overrides  
- Merge pull request #2037 from Crazyyoungs/main  
    koKR: Add Korean translations for various UI elements  
- Merge pull request #2036 from dfrisone/fix/name-only-lost-in-instances  
    fix(nameplates): keep friendly name-only through an instance  
- Fix raid-size preview overrides mutating editable dimensions  
- Merge pull request #2035 from JuJuFX-dev/fix/tooltip-anchor-secret-point  
    Fix(BlizzardSkin): Lua error on world cursor tooltips from secret anchor points  
- Merge pull request #2033 from dfrisone/fix/actionbars-loadout-mouseover  
    Fix loadout swap lag with mouseover action bars  
- Merge pull request #2034 from Barbiero/locale/ptbr-since-3860a8d5  
    ptBR: translate Cooldown Manager, Bags, Raid Frames, and Warlock reminders strings  
- Add Korean translations for various UI elements  
- Merge pull request #2031 from dfrisone/fix/cdm-trinket-glow-reset  
    Fix trinket glow ignoring Cooldown State Effect None  
- fix(nameplates): keep friendly name-only through an instance  
    Reported: with Make Friendly Nameplates Name Only enabled, friendly health  
    bars come back on entering an instance, and again on entering combat.  
    Unticking and re-ticking the option fixes it until the next time.  
    nameplateShowOnlyNameForFriendlyPlayerUnits was only re-asserted in the  
    open-world branch of the visibility pass. The in-instance branch handles the  
    NPC visibility CVars and deliberately leaves player VISIBILITY alone, but  
    name-only is presentation rather than visibility, so it was dropped with it.  
    Once the CVar drifted, nothing rewrote it until the player was back outside,  
    which is the whole-instance symptom.  
    The combat half is the same branch: the pass is skipped under lockdown and  
    retried on PLAYER\_REGEN\_ENABLED, which still lands in the instance branch.  
    Toggling the option worked around it because the options setter writes the  
    CVar directly.  
    IsNameOnlyMode itself is unchanged and never depended on instance type, so the  
    mode was always still on -- only the CVar backing it went stale.  
- Fix Lua error on world cursor tooltips from secret anchor points  
    GameTooltip\_SetDefaultAnchor reached through SetWorldCursor leaves the  
    tooltip anchored by restricted code, so GetPoint hands back a secret  
    point string. Both default-anchor enforcers compared that value directly  
    and raised, spamming the error log while questing.  
    Classify with issecretvalue ahead of the comparisons: the fixed anchor  
    treats a secret point as a deviation and re-points onto its own box,  
    growth direction skips the pass because the forced corner cannot be  
    derived from a secret point at all.  
- ptBR: translate Cooldown Manager Replace with Buff, Bags Stack Splitter, Party Frames in Small Raids, and Warlock aura reminders content picker; update Group Finder signup note wording  
- fix(actionbars): use hover fader after loadout cursor clears  
- fix(cdm): honor preset cooldown effect settings when disabled  
- perf(cdm): coalesce rotation highlight updates  
- feat(cdm): customize rotation assist highlight  
- Merge remote-tracking branch 'upstream/main' into fix/castbar-centered-text-width  
- Merge remote-tracking branch 'upstream/main' into fix/tbb-target-aura-fallback  
- Reserve timer space on both sides of centered cast text  
- Filter target fallback by player and probe before waking  
- Fix centered cast-bar spell text truncation  
- fix(cdm): let a tracked bar find its debuff on the target  
    Reported for a rogue Blind macro that sets focus to the target, clears the  
    target, targets and blinds someone else, then restores the original target  
    from focus, all inside one macro. Afterwards the player's bleeds on that  
    target stop showing on the tracked bar until they switch target and back.  
    The stall is Blizzard's. CooldownViewerMixin:OnPlayerTargetChanged only  
    refreshes when UnitGUID("target") differs from the one it stored, and this  
    macro ends on the GUID it started with, so the refresh never runs and the  
    item stays inactive. Its frame-scoped aura cache is keyed on unit token and  
    stamped with GetTime(), and nothing on the target-change path marks it dirty,  
    so a second target change inside one frame reads the stale list.  
    Our display is a faithful mirror of that, so it goes quiet with it. But the  
    bind-miss fallback that already exists for "the viewer has not bound this aura  
    yet" only ever asked GetPlayerAuraBySpellID, which cannot see a debuff on  
    somebody else. It now asks the target too, so the bar rides out the stall.  
    Only a readable sourceUnit mismatch rejects the aura, so another player's copy  
    of the same debuff cannot drive the bar while an unreadable one still shows.  
    Field reads need no new guarding: the consumer already classifies duration,  
    expirationTime and applications before comparing them.  
    PLAYER\_TARGET\_CHANGED joins both tick wake sets as well. Target-applied auras  
    bind and release on that edge and on no player-scoped one, so a parked ticker  
    had no way to learn a new target already carried a tracked debuff.  
- Merge upstream/main into feature/nameplate-chat-bubbles  
    Only EllesmereUILocales/\_keys.txt conflicted. It is generated by  
    .tools/extract-locale-keys.sh, so it was resolved by regenerating it over the  
    merged tree rather than by hand-merging the two key lists: upstream added three  
    keys and this branch adds one, which the header count on either side cannot  
    express. The result is upstream's list plus "Only works outside of Instances",  
    785 keys.  
- Probe for secrets before the nil compare in chat bubbles  
    Every chat event the bubble renderer listens to is declared SecretInChatMessagingLockdown in Blizzard's own ChatInfoDocumentation, and none of their text payloads carries NeverSecret, so arg1 is a secret string whenever that lockdown is in effect. That is a state of the chat system rather than a property of the map, so it reaches the open world, where the feature is not suspended. Comparing a secret to nil raises, so the existence test is type() everywhere now and the secret guard runs ahead of any comparison: the chat handler, OnBlizzShow, Sweep, BlizzTextColor, MatchPending, and both SafeEq and SafeContains, whose contract explicitly allows a secret on either side and which raised on their own first line.  
    Guard the remaining unguarded reads of Blizzard's frames the same way. BlizzParts resolved outer.GetChildren and child.String outside its pcall, and the second of those ran on every call rather than once per frame. Anchor let PP.Point reach SetPoint against a frame that may have been reclassified as forbidden since the claim, which RefreshStyle repeats per slider step. HookOuter called HookScript unguarded. A failed anchor now hands the bubble back instead of leaving a shown frame with no point at all and Blizzard's chrome blanked behind it.  
    Release the claimed bubbles on PLAYER\_LOGOUT as well, so the chrome held at alpha 0 goes back with the CVars rather than only through SetActive(false).  
- Add Hide Chat Bubbles in Instances  
    Our own bubbles never draw inside a dungeon, raid, scenario or battleground:  
    the engine's bubble frames are forbidden to addons there, which is why the  
    feature suspends itself for the stay. Until now that left Blizzard's own bubbles  
    showing at whatever the player had set. This option switches all three of them  
    off for as long as the instance lasts and back on the way out. Off by default.  
    CVars are the only lever available, not a shortcut. A forbidden frame can be  
    neither read nor hidden, and C\_ChatBubbles offers nothing to disable, so there  
    is no addon-side way to suppress a bubble the engine has decided to draw there.  
    ApplyCVar now takes the value a switch has to sit at rather than a flag saying  
    we want it on, which is the whole mechanical change: hiding means forcing one  
    off, and the existing take-over bookkeeping then covers the rest. Each switch  
    keeps the snapshot it was first taken over on, so the pass that runs on leaving  
    the instance hands it back off that same snapshot, and a logout inside one  
    restores it just as well.  
- Offer Blizzard's own bubble text colour instead of one colour for every channel  
    The bubble drew every channel in a single configured colour, so a yell and a  
    whisper from an NPC came out looking the same. A cog beside the Font row's  
    colour swatch now carries one toggle, Follow Blizzard Default Color, off by  
    default so nothing changes for anyone who does not go looking for it.  
    The colour is read off Blizzard's own FontString when the bubble is claimed,  
    not derived from a table of our own mapping chat events to chat types. The  
    engine has already answered the question per channel, and reading its answer  
    covers channels we never enumerate. The read is guarded like every other access  
    to a Blizzard frame and secret-tested, since a restricted frame answers with  
    numbers SetTextColor cannot take; if it comes back empty the bubble falls back  
    to the configured colour rather than to nothing.  
    The captured colour is kept for the life of the claim, so toggling the option  
    restyles bubbles already on screen through RefreshStyle, and it is cleared when  
    the frame goes back to the pool so no speaker inherits the previous one's  
    colour. While the option is on the colour swatch greys out and says why, with  
    the gate's own wording kept for the case where the whole feature is off.  
- Add chat bubble customization  
    A new Chat Bubbles page on the Chat module restyles the bubbles the game  
    already draws: background colour and opacity, border size and colour, font size  
    and colour, padding, maximum width and a vertical nudge. Off by default, and  
    opt-in behind a confirmation, because switching it on also switches Blizzard's  
    own bubbles on.  
    Blizzard's bubbles are not forbidden outside instances, so rather than replace  
    them the feature rides on them: their switches stay on, the chrome is blanked,  
    and a styled frame is hung on the frame that carries their position, which the  
    engine has already placed over the speaker's head. No nameplate is involved and  
    the player's own lines work too. Inside an instance those frames ARE forbidden  
    to us and can be neither read nor blanked, so the feature stays away entirely  
    for the stay and Blizzard's own bubbles keep working.  
    Blizzard's switches are borrowed, never kept. chatBubbles is taken over while at  
    least one of Say, Yell, NPCs and Emotes is ticked. Party and Raid each have a  
    switch of their own, taken over only while that channel is ticked, and those two  
    ticks are seeded from the live switches the first time the feature is enabled so  
    group bubbles never turn up in a chat that had none. Every switch is handed back  
    on disable, on entering an instance, and at PLAYER\_LOGOUT, which is the only  
    hand-back that survives the addon being disabled outright. The bookkeeping lives  
    in memory only, so no profile or account export can carry one player's switch  
    values to somebody else.  
    A bubble is claimed in the same frame it appears: an OnShow hook reads its text  
    and matches it against the chat lines still waiting, with a timed sweep behind  
    it for the cases a hook cannot cover, and a stamp on both sides so a bubble that  
    was already standing cannot be claimed by a later line that happens to match it.  
    What gets drawn is the bubble's own text, so whatever the client formatted into  
    it, an emote's name prefix or a filled token, carries over unchanged.  
    Access to Blizzard's frames is guarded throughout, because one can be  
    reclassified as forbidden underneath us, and every comparison against a chat  
    string is secret-value safe. Nothing runs while the feature is off: no frames,  
    no event registrations, no hooks on Blizzard's frames and no CVar writes.  
