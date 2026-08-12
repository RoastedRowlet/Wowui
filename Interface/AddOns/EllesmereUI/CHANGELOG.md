# EllesmereUI

## [v8.8.3](https://github.com/EllesmereGaming/EllesmereUI/tree/v8.8.3) (2026-08-12)
[Full Changelog](https://github.com/EllesmereGaming/EllesmereUI/compare/v8.8.2...v8.8.3) [Previous Releases](https://github.com/EllesmereGaming/EllesmereUI/releases)

- Release v8.8.3  
- Merge pull request #1338 from dfrisone/pab-custom-bar-filter-loss  
    fix(unitframes): zero an abandoned aura container's groups before releasing it  
- fix(unitframes): zero an abandoned aura container's groups before releasing it  
    AuraContainer frames are permanent and a declared group can never be  
    un-declared -- ApplyGroupConfig's sweep can only zero one. AK.ReleaseContainer  
    therefore hides the frame but leaves every group live on it at its last frame  
    count, and the declared set that named those groups is dropped immediately  
    after. Anything that shows the frame again renders the stale content.  
    The visible case: a bar that was on Show All Buffs before being pointed at a  
    filter set leaves a fully-populated catch-all on the abandoned container, which  
    resurfaces as the bar showing every buff, mount and all. Retire now zeroes each  
    group we still have a name for, plus the out-of-chain "spells" group, so a  
    resurrected container renders nothing.  
- Merge pull request #1337 from Barbiero/main  
    ptBR: translate remaining keys from Locales/\_keys.txt  
- Merge pull request #1329 from Nnoggie/codex/partial-resource-color  
    Resource Bars: add partial resource color toggle  
- Merge pull request #1326 from svart2521/custom-color-on-text-breaking-on-hover  
    OnEnter hook in action bars  
- Merge pull request #1325 from JuJuFX-dev/fix/dragonriding-double-border  
    Fix: rendering issues on the custom Dragonriding HUD  
- ptBR: translate remaining keys from Locales/\_keys.txt  
    Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>  
- Merge pull request #1336 from dfrisone/blizzskin-toast-sweep-secret-strata  
    fix(blizzskin): guard the loot-toast sweep against secret frame properties  
- Merge pull request #1335 from dfrisone/pab-icons-per-row-off-by-one  
    fix(unitframes): Icons Per Row rendered one icon per row short  
- fix(blizzskin): guard the loot-toast sweep against secret frame properties  
    The deep sweep walks EVERY UIParent child, so it meets frames this addon did  
    not create. A widget fed secret data hands back SECRET values from ordinary  
    getters, and comparing one throws for us: addon execution is never untainted,  
    and only untainted code may inspect a secret.  
    Field report, twice: "attempt to compare a secret string value" out of  
    GetFrameStrata on another addon's engine aura container parented to UIParent.  
    Nothing secret-aspected is ever a loot toast, so a secret read now skips the  
    frame. Strata and shown are both resolved before any comparison -- leaving the  
    getter inside the `and` chain throws on the spot instead of skipping.  
- fix(unitframes): Icons Per Row rendered one icon per row short  
    ComputeGrid handed the engine a wrap budget of cols*icon + (cols-1)*pad, i.e.  
    gaps only BETWEEN icons. The engine reserves a trailing elementSpacing after  
    every element, so a full line needs cols*(icon+pad) -- one spacing more than  
    the budget, and the last icon of every row wrapped.  
    Field-verified from a tester slider sweep: Icons Per Row 5 rendered 4 per row,  
    2 rendered 1. At the default 11 it reads as a stray icon on row 2. The bar's  
    own frame still measures lineExtent, so the drag box does not grow by the  
    phantom trailing gap. The preview builder already models it the same way, it  
    accumulates a gap per element and subtracts the trailing one.  
- Merge pull request #1332 from Nnoggie/codex/cdm-cooldown-edge  
    CDM: add cooldown edge option  
- feat(cdm): add cooldown edge option  
- feat(resourcebars): control partial resource shade  
- Render Dragonriding speed text above the pip stacks/icon  
    The pip stacks and Whirling Surge icon nest their bar textures one parent  
    level deeper than the speed bar (stackFrame -> pip, wsIcon -> tex/cd), and  
    frame level always outranks draw layer across frames, so the speed bar's  
    plain OVERLAY fontstring rendered behind them. Give the text its own frame  
    raised well above every level used in this HUD, same pattern already used  
    by CreateWhirlingSurgeIcon's textFrame.  
- Align pip dividers between Skyward Ascent and Second Wind rows  
    LayoutPips distributed leftover pixels onto the first N pips independently  
    per row, so the two charge rows (6 vs 3 pips) could drift up to 1px apart  
    at dividers that should coincide. Compute cumulative boundaries via  
    floor(totalUnits * i / pipCount) instead, which lines them up exactly  
    since one pip count is an integer multiple of the other.  
- Fix double border at 0 Element/Stack Spacing on Dragonriding HUD  
    Each pip and the speed bar drew its own full 4-side border independently,  
    so touching seams (Element Spacing / Stack Spacing = 0) rendered two  
    overlapping border lines instead of one. Suppress the shared edge on one  
    side of each seam via the existing PP border edge-hide flags.  
- OnEnter hook in action bars  
    Added comments to clarify the purpose of the OnEnter hook and the HotKey color handling.  