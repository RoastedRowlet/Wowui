# EllesmereUI

## [v8.5.7](https://github.com/EllesmereGaming/EllesmereUI/tree/v8.5.7) (2026-07-24)
[Full Changelog](https://github.com/EllesmereGaming/EllesmereUI/compare/v8.5.6...v8.5.7) [Previous Releases](https://github.com/EllesmereGaming/EllesmereUI/releases)

- Release v8.5.7  
- Merge pull request #946 from LoChinAn/locale/zhtw-translations  
    Add missing Traditional Chinese (zhTW) translations  
- Merge pull request #945 from dfrisone/cdm-apply-unapply-restore  
    Fix Apply-to-Bar toggle-off discarding custom colours (CDM)  
- Merge pull request #942 from Nnoggie/codex/nameplate-combine-cast-target  
    Nameplates: combine spell name and target  
- Merge pull request #941 from dfrisone/chat-whisper-secret-taint  
    Fix whisper secret-value taint errors (chat)  
- Merge pull request #940 from Nnoggie/codex/nameplate-negative-spacing  
    Nameplates: allow negative spacing  
- Add missing Traditional Chinese (zhTW) translations  
    Translate ~500 previously-untranslated keys across all modules, and align  
    a few terms with existing usage (window skins, spell and talent names, Delves).  
- fix(cdm): restore custom value to the spell when un-applying a bar apply  
    Clicking an active "Apply to Bar" / "Apply to Bar (All Specs)" scope is a  
    toggle-off (un-apply). For payload-carrying settings - a custom colour's  
    RGB or a scalar popup value - the original apply swept the per-icon  
    copies into the bar tier, so the scope being removed holds the ONLY copy  
    of the value: a plain un-apply discarded it and the setting silently  
    snapped to default (reported for Active State > CD Swipe Color: applying  
    a custom colour and clicking the apply again reset it to yellow).  
    Seed the removed value back into the spell in hand before clearing the  
    scope, so toggle-off recreates that spell's pre-apply own value instead  
    of losing the colour. Non-payload toggles keep their existing un-apply  
    semantics, and a subsequent apply from the restored value works normally.  
- feat(nameplates): combine spell and target text  
- fix(chat): defer login border pass to stop whisper secret-taint errors  
    Running ECHAT.ApplyBorders() synchronously inside the PLAYER\_LOGIN init  
    chains into ApplyExtendedBackground, planting the panel border's anchors  
    in ChatFrame1's rect dependency web while Blizzard's login dock pass is  
    still resolving chat layout. That secure pass then reads the insecure  
    anchors, runs tainted, and its persistent dock state poisons every later  
    temporary whisper window open: each open re-fires the whisper into  
    MessageEventHandler already tainted, which is blocked on the secret  
    sender values (FCFManager\_GetChatTarget string conversion /  
    GetDecoratedSenderName boolean test - the whisper LUA errors testers  
    reported).  
    Field-bisected over a 13-build ladder against live whispers: the errors  
    reproduce with this call synchronous and disappear with it deferred,  
    while the same work run from the deferred tab passes (the module's  
    existing PEW + C\_Timer cadence) has always been clean. Fix accordingly:  
    run ApplyBorders once from a one-shot PLAYER\_ENTERING\_WORLD handler,  
    one tick later. No functional change to borders - identical visuals a  
    frame after login.  
    Exonerated during the ladder (no changes shipped): the whisper URL  
    filter, chat frame HookScripts, temp-frame skinning, the tab border  
    engine, GeneralDockManager anchoring, and the FCFDock\_SelectWindow hook.  
- fix(chat): guard secret geometry read on docked temp-whisper tabs  
    ApplyTabLayout's dynamic-tab seat-normalize read a docked tab's anchor via  
    tab:GetPoint(1) and compared pt == "LEFT". For a temp WHISPER tab whose  
    target is secret (in instances / M+) the anchor point/offset are secret  
    values, so the comparison threw 'attempt to compare a secret string value  
    while tainted by EllesmereUIChat' (5x, reported after a dungeon). Guard the  
    whole block with issecretvalue on pt/relPt/x/y -- the seat normalize is  
    cosmetic -- matching the issecretvalue belt already used for the width record  
    just above.  
- Merge pull request #939 from Nnoggie/codex/boss-castbar-controls  
    Unit Frames: match boss castbar controls  
- feat(nameplates): allow negative spacing  
- Merge pull request #938 from Nnoggie/codex/boss-power-border  
    Add boss power bar border controls  
- Merge pull request #936 from JuJuFX-dev/fix/questtracker-flickering  
    FIX: POI blinking  
- Merge pull request #935 from dfrisone/playerauras-buffframe-taint  
    Fix player-aura reskin tainting Blizzard's BuffFrame (raid lag + border revert)  
- Merge pull request #934 from dfrisone/cdm-cdclaim-marker-override-crash  
    Fix CDM crash when hosting a collided buff (Diabolist Diabolic Ritual) on a Cooldown/Utility bar  
- feat(unitframes): add boss castbar controls  
- fix(unitframes): add boss power border control  
- fixed POI flickering while it should be hidden  
- fix(unitframes): stop player-aura reskin tainting Blizzard's BuffFrame  
    The 'hide expand button' path drove Blizzard's aura layout from addon code:  
    it wrote BuffFrame.isExpanded and called BuffFrame:Update / UpdateGridLayout /  
    RefreshConsolidationFrameVisibility. Running Blizzard's aura machinery under  
    addon taint makes its own UpdateExpirationTime compare the secret  
    expirationTime and error on every aura update -- thousands of errors and  
    heavy lag in raid combat -- and the tainted Update also threw before the  
    border re-skin hook ran, so the icon borders reverted to default on reload  
    until a settings change re-applied them.  
    There is no taint-safe way to force-expand auras from an addon (any write to  
    isExpanded, or any call into Blizzard's aura layout, taints it). Make the  
    setting purely visual: just hide the expand/collapse button (the deferred  
    RefreshConsolidationFrameVisibility hook keeps it hidden across Blizzard's own  
    refreshes). Auras keep Blizzard's native expand state, which defaults to  
    expanded, so all auras still show; only a user who had manually collapsed  
    their auras beforehand would see those stay collapsed.  
    Only affects users with 'hide expand button' enabled; default config is  
    untouched.  
- fix(cdm): also skip cd-claim marker in the CD/util item-materialization pass  
    Follow-up to the spell-order guard: the collided-buff cd-claim marker  
    (-(CD\_CLAIM\_MARKER\_BASE + cooldownID)) leaks in a SECOND reanchor loop too.  
    The CD/util frame-materialization pass skips hosted-buff markers and trinket  
    slots, then treats any remaining sid <= -100 as a custom item preset  
    (itemID = -sid). A cd-claim marker is <= -100, so it was materialized as an  
    item preset with itemID = 3000009472 and fed to C\_Container.GetItemCooldown,  
    which errors outside int32 -> RefreshLayout threw every refresh (reported:  
    adding Diabolic Ritual to the Cooldown/Utility bar as Diabolist).  
    Skip cd-claim markers in the same branch that already skips hosted-buff  
    markers -- both render via the reparent/diversion path (route map ->  
    cdFrames), never as an injected custom frame. Matches the buff-family item  
    loop, which already excludes cd-claim markers with the same guard.  
    Audited all other sid<=-100 sites: the buff-bar item loop, buff-order loop,  
    preview (cd-claim branch precedes item), \_cdmAnyCustomItem (bounded > -2e9),  
    alreadyTracked (harmless), and picker enum (BuffDisplayStableKey returns nil  
    for a marker) are all already safe. These two render loops were the only  
    leaks.  
- fix(cdm): stop crash hosting a collided buff on a CD/Util bar  
    Hosting a collided Diabolist buff (e.g. Diabolic Ritual, two viewer slots  
    sharing one spellID) on a Cooldown/Utility bar tracks it by a cd-claim  
    marker: -(CD\_CLAIM\_MARKER\_BASE + cooldownID), a value well outside int32.  
    The reanchor spell-order loop iterates the bar's assignedSpells (which holds  
    that marker) and, in its non-hosted-buff branch, passed the raw marker to  
    C\_SpellBook.FindSpellOverrideByID / C\_Spell.GetBaseSpell. FindSpellOverrideByID  
    errors outright on an out-of-range id, so RefreshLayout threw on every CDM  
    refresh (53x) and the tracker broke -- appeared 'disabled'. Reported in open  
    world (target dummy), so not secret-value related; purely the marker.  
    The sibling order loops already guard these calls with sid>0 (and one even  
    decodes the cd-claim marker); this one branch missed it. Guard it the same  
    way: a marker is not a real spellID, has no override/base, and its frame  
    routes by cooldownID and orders via the buff-family "c"..cooldownID key, so  
    skipping the lookups is correct. The spellOrder[marker] slot entry is  
    unchanged.  
