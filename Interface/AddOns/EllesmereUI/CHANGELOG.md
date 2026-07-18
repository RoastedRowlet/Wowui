# EllesmereUI

## [v8.4.8](https://github.com/EllesmereGaming/EllesmereUI/tree/v8.4.8) (2026-07-16)
[Full Changelog](https://github.com/EllesmereGaming/EllesmereUI/compare/v8.4.7...v8.4.8) [Previous Releases](https://github.com/EllesmereGaming/EllesmereUI/releases)

- Release v8.4.8  
- Merge pull request #768 from danvernon/fix/tooltip-first-show-layout  
    fix(blizzskin): re-layout tooltip after font changes on first show  
- Merge pull request #766 from dfrisone/auto-container-bag  
    fix(qol): stop auto-open double-using a locked container (stuck greyed items)  
- Merge pull request #764 from dfrisone/button-glow-cd-state-bug  
    fix(cdm): track cooldown for CD-Ready glow on trinkets/racials/potions  
- fix(blizzskin): re-layout tooltip after font changes on first show  
    The OnShow hook changes font face and size after the tooltip has already  
    calculated its layout, causing mis-sized text on the first show after  
    /reload. Subsequent shows worked because font strings retained the  
    custom font from last time. A guarded re-show forces recalculation.  
- fix(qol): stop auto-open double-using a locked container (stuck greyed items)  
    Auto Open Containers could leave a container stuck LOCKED (greyed out and  
    unopenable, even after disabling the setting), reported for Artisan's  
    Consortium Payouts. Opening a container fires BAG\_UPDATE\_DELAYED, which starts  
    an overlapping open pass; without an isLocked check it could call  
    UseContainerItem on the same slot while the previous open was still resolving  
    (a loot window or a >0.5s server round-trip). That double-use strands the item  
    in a client-side lock.  
    Both open passes now skip slots reported as isLocked before using them, and no  
    longer cache a still-locked slot as "failed" at the post-open recheck (it is  
    in-progress, not a real failure; a later pass retries). Checking isLocked  
    before UseContainerItem is the standard bag-addon guard; a locked slot is never  
    safe to act on.  
- Merge pull request #762 from dfrisone/show-rank-action-bar-bug  
    fix(actionbars): refresh item rank icon when an item is swapped in place  
- Merge pull request #761 from dfrisone/cdm-buff-timer-rounding  
    fix(cdm): buff bar seconds timer rounds up to match Blizzard's aura timers  
- Merge pull request #763 from JuJuFX-dev/fix/unitframes-bossframes-name-class-color  
    Fix: Boss frame class color  
- fix(cdm): track cooldown for CD-Ready glow on trinkets/racials/potions  
    The per-spell "Pixel/Button Glow (CD Ready)" effect stayed lit through the  
    whole cooldown when applied to a trinket, racial, or potion preset, rather  
    than turning off while the ability was on cooldown. It worked for normal  
    spells. Two independent causes:  
    1. Item presets (potions/healthstones): PresetOnCD queried only the primary  
       itemID, whose item-cooldown API returns a start with no duration. The real  
       cooldown ticks on whichever alternate id the player actually owns, so walk  
       the preset's altItemIDs (as ProcessPresetCooldowns already does) and the  
       on-CD read succeeds. The spell-cooldown path also re-lit the shared glow  
       overlay on these frames every desat tick (it cannot read a negative item  
       key, so it always saw them ready); PresetHasCdState now hands preset frames  
       off to the Fake-Active engine, clearing both glow flags so the preset path  
       re-asserts the correct state.  
    2. Racials/custom frames on a native Cooldown viewer bar: EUI's custom frames  
       drive desaturation via SetDesaturation(float), which never fires the  
       SetDesaturated hook the plain glow relied on to re-evaluate, so the glow was  
       never cleared on the cooldown transition. Register custom frames' plain glow  
       for the existing SPELL\_UPDATE\_COOLDOWN watch (its loop now handles plain  
       variants too); genuine Blizzard frames keep the zero-event path.  
- fixed boss frame class colour  
- fix(actionbars): refresh item rank icon when an item is swapped in place  
    With "Show item rank" on, replacing an item in an action slot with a different  
    rank in the SAME slot (e.g. a rank 1 Silvermoon Health Potion -> rank 2 from  
    bags) left the rank overlay showing the OLD rank until you hovered the button  
    twice. Blizzard doesn't re-run its ProfessionQualityOverlayFrame update on an  
    in-place slot swap, and the existing ACTIONBAR\_SLOT\_CHANGED scan only handled  
    the feature-OFF case (hiding overlays).  
    Re-run Blizzard's own UpdateProfessionQuality for rank-enabled bars on the same  
    scan so the rank tracks the new item immediately. Gated to item slots: rank  
    icons only apply to items, and ACTIONBAR\_SLOT\_CHANGED storms (mouseover-macros  
    re-resolving, in combat) must not run a quality lookup on every spell button  
    each frame -- a non-item slot just gets any lingering rank overlay hidden.  
- fix(cdm): buff bar seconds timer rounds up to match Blizzard's aura timers  
    The CDM buff bar's FormatTime floored the remaining seconds, so a buff read one  
    second below Blizzard's own frame -- e.g. Aug Evoker Ebon Might showed 16 while  
    Blizzard showed 17. It was never a stale duplicate or a refresh lag (an  
    instrumented capture showed the bar's remaining matches the live aura exactly);  
    only the displayed integer was floored, while Blizzard rounds aura timers up.  
    Ceil the whole-second branch so a buff with 16.5s left reads "17". Minutes/hours  
    stay floor (their round-up isn't verified against Blizzard, and buffs seldom sit  
    that high); sub-10s still shows tenths.  
- Merge pull request #760 from Snsei987/fix/power-icon-addon-button-alpha  
    Change on/off addon icon based on addon status  
- Merge pull request #759 from Filpet96/fix/detached-power-border-live-update  
    fix(unitframes): reapply detached power border after reparent  
- Merge pull request #757 from danvernon/fix/rf-tier-offset-regen  
    fix(raidframes): apply tier offset after combat-exit and party-preview relayout  
- Merge pull request #758 from danvernon/fix/cdm-pvp-vanish  
    fix(cdm): restore CDM bars after PvP instance transitions  
- Merge pull request #755 from danvernon/fix/spec-overrides-raid-size  
    fix(spec-overrides): custom raid size settings now save to override groups  
- Change on/off addon icon based on addon status  
- Merge pull request #754 from danvernon/fix/cdm-trinket-tooltip-cache  
    fix(cdm): trinket cooldown disappears when visiting crafting vendor  
- Merge pull request #753 from danvernon/fix/warbank-aggregate-stacking  
    fix(bags): warbank aggregate views now stack across all tabs  
- Merge pull request #752 from danvernon/fix/bags-rightclick-during-refresh  
    fix(bags): prevent click-through during rapid right-click transfers  
- Merge pull request #751 from danvernon/fix/bags-rename-miscellaneous  
    fix(bags): allow renaming the Miscellaneous category  
- Merge pull request #750 from danvernon/fix/onebag-reagent-sort  
    fix(bags): include reagent bag in OneBag sort  
- Merge pull request #749 from danvernon/fix/quest-item-hotkey  
    fix(questtracker): quest item hotkey not finding quest items  
- Merge pull request #747 from danvernon/fix/mail-body-font  
    fix(blizzardskin): apply skin font to mail body text  
- chore: regenerate locale keys  
- fix(unitframes): reapply detached power border after reparent  
    Live updates ran UpdatePowerBorder before ReparentBarsToClip, so switching  
    to Detached Top/Bottom left border and power text at stale frame levels  
    until the option was selected again or the UI was reloaded.  
- fix(cdm): restore CDM bars after PvP instance transitions  
    CDM bars vanished after entering/exiting PvP instances because:  
    1. Blizzard rebuilds viewer pool frames during zone transitions,  
       but CollectAndReanchor (which re-collects the new frames) did  
       not call \_CDMApplyVisibility afterward -- icons entered  
       cdmBarIcons at alpha 0 and were never restored.  
    2. The arena exit backstop only covered arena->world transitions  
       (\_cdmWasInArena), missing battlegrounds and other PvP instance  
       types entirely.  
    3. Entering PvP instances did not trigger a reanchor, so Blizzard's  
       freshly-acquired pool frames (for PvP talents) were never claimed.  
    Fix:  
    - Call CDMApplyVisibility after every CollectAndReanchor so newly  
      collected icons get their visibility restored immediately  
    - Extend the PvP backstop to cover all PvP instance types (arena  
      and pvp), not just arenas  
    - Queue a reanchor when entering a PvP instance  
    - Add a second deferred visibility pass at 3s to catch late viewer  
      pool rebuilds  
- fix(raidframes): apply tier offset after combat-exit and party-preview relayout  
    The REGEN (combat-exit) handler called LayoutGroups() without  
    \_ApplyTierOffset() when the roster changed during combat but the  
    tier dimensions stayed the same. Two tiers sharing identical  
    width/height but differing in offset or growth direction would  
    leave the container stuck at the old tier's position until the  
    next full reload.  
    - Compare the resolved tier override reference (not just dimensions)  
      during combat roster updates so same-dimension tier transitions  
      are detected  
    - Call \_ApplyTierOffset after LayoutGroups in the REGEN path  
    - Call \_ApplyTierOffset after LayoutGroups in HidePartyPreview  
      (mirrors HidePreview)  
    - Add /run EllesmereUI.\_RF\_DumpOffset() diagnostic command for  
      runtime offset troubleshooting  
- fix(visibility): druid flight form now triggers dragonriding visibility  
    IsAirborneSkyriding used IsMounted() which returns false for druid  
    flight form. Switched to IsPlayerMountedLike() which covers druid  
    mount-like shapeshift forms. Also removed the IsFlying() requirement  
    so bars hide as soon as the skyriding mount/form is active, not only  
    after takeoff.  
    Updated CDM's UPDATE\_SHAPESHIFT\_FORM handler to also check for  
    dragonriding visibility modes, not just visHideMounted.  
- fix(spec-overrides): allow custom raid size settings to be captured  
    raidSizeOverrides uses numeric keys (10, 15, 25, 30) for tier sizes.  
    The auto-capture system rejected these as unsafe numeric-keyed paths  
    because NumAllowedFKey only whitelisted CDM bar indices. Added the  
    raidSizeOverrides prefix so frame size, growth, and offset overrides  
    per tier are correctly captured into spec override groups.  
- fix(cdm): preserve trinket on-use state when tooltip data is unavailable  
    UpdateTrinketFrame scans tooltip lines to determine if a trinket is  
    on-use. When tooltip data is temporarily unavailable (e.g. during  
    crafting order vendor interaction), the scan returned no lines and  
    reset \_trinketIsOnUse to false, hiding the trinket icon. Now the  
    previous on-use state is preserved when the tooltip scan is  
    inconclusive.  
- fix(bags): search all warbank tabs for stacking in aggregate views  
    When using OneWarbank or All Warbank views, transfers now scan all  
    warband tabs for partial stacks before falling back to empty slots.  
    Previously GetSelectedTabBagID returned the first tab with any empty  
    slot, skipping full tabs that had stackable items of the same type.  
- fix(bags): prevent slots hiding during rapid right-click transfers  
    Defer hiding unused item slots until after the render pass completes  
    instead of hiding all slots at the start of RefreshInventory. This  
    eliminates the brief window where all slots are hidden during the  
    debounced refresh, which caused clicks to fall through to action bars.  
- fix(bags): allow renaming the Miscellaneous category  
    RenameCategory blocked catch-all categories from being renamed. The  
    isCatchAll flag is only used for item classification and ordering; the  
    display name is purely cosmetic.  
- fix(bags): include reagent bag in OneBag sort  
    ConsolidateStacks and ComputeAndExecute only scanned bags 0-4, skipping  
    the reagent bag (bag 5). Sorting now consolidates stacks across all bags  
    and runs the physical sort in two passes — bags 0-4 then bag 5 — so  
    items in the reagent bag are sorted without cross-bag-type moves.  
- fix(questtracker): quest item hotkey scans all quests, not just watched  
    ScanForQuestItem only considered watched quests (GetQuestWatchType ~=  
    nil), so quest items from untracked quests were never found. The  
    button's item attribute stayed nil and no override binding was created,  
    making the hotkey do nothing.  
    Scan all quests for items, prioritising watched quests but falling back  
    to any quest with a usable item.  
- chore: trim comment  
- fix(blizzardskin): apply skin font to mail body text  
    WhitenMailText only set text colors on the OpenMailBodyText SimpleHTML  
    but left the stationery-specific font untouched. AH and crafting mails  
    use ornate stationery fonts that look out of place on the dark skin  
    background.  
    Set Theme.fontPath on P/H1/H2/H3 elements of the mail body, and apply  
    WSkin.Font to the subject and sender labels in the open mail view.  
