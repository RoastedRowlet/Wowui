# EllesmereUI

## [v8.3.3](https://github.com/EllesmereGaming/EllesmereUI/tree/v8.3.3) (2026-06-29)
[Full Changelog](https://github.com/EllesmereGaming/EllesmereUI/compare/v8.3.2...v8.3.3) [Previous Releases](https://github.com/EllesmereGaming/EllesmereUI/releases)

- Release v8.3.3  
- Merge pull request #500 from Kneeull/patch-27  
    Add in Support for Feign Death to not show  
- Merge pull request #495 from nulltyto/bugfix/gcd-drops  
    fix(gcd-bar): stop GCD bar dropping while spamming + add Deplete Fill option  
- Update EllesmereUIDamageMeters.lua  
- Update EllesmereUIDamageMeters.lua  
- Merge pull request #499 from labrie75/labrie75-patch-1  
    Update koKR 8.3.2  
- Add in Support for Feign Death to not show  
    Should work, no lua errors in /euidev and shows deaths correctly.  
- Update koKR 8.3.2  
    Update koKR 8.3.2  
- Merge pull request #497 from Nnoggie/codex/quick-keybind-macros  
    Add quick keybind support for macros  
- Merge pull request #498 from Filpet96/fix/mythic-timer-format  
    Fix Mythic+ Timer detail format and show overtime as negative  
- Fix Mythic+ Timer detail format and show overtime as negative  
    The in-bar timer only drew the primary value, so the "(remaining / total)"  
    detail of the detailed format was silently dropped and it looked identical to  
    the plain elapsed option. The detail is now appended in-bar, matching the  
    above-the-bar layout.  
    The remaining clock also stayed frozen at 00:00 once a key was over time. It now  
    counts into the negative (e.g. -01:04) so it's clear by how much you are over.  
- Merge pull request #496 from Filpet96/fix/healthstone-hide-if-missing  
    Fix Hide Items if Missing keeping cross-linked healthstones visible  
- Add quick keybind support for macros  
- fix(gcd-bar): don't drop GCD tracking while spamming; add Deplete Fill option  
    The GCD bar dropped out during sustained spam and stayed gone for the rest of  
    combat. captureGCD only (re)started the bar when the GCD read as 'freshly  
    started' (elapsed < 0.3s). While spamming, the next ability is queued and its  
    UNIT\_SPELLCAST\_SUCCEEDED lands partway into the fresh GCD -- measured elapsed  
    0.4-0.7s -- so that gate rejected every queued cast and the bar never re-armed.  
    (Confirmed in-game: clean, non-secret cooldown reads with elapsed ~0.44s,  
    bar=nil.)  
    Fix: re-arm whenever the read is a genuinely NEWER GCD than the last captured  
    one (actualStart > \_gcdActualStart), instead of gating on how far it has  
    elapsed. That's latency/spell-queue independent and still rejects off-GCD  
    abilities (they read the SAME running GCD, so the start isn't newer). A small  
    remaining-time check skips an already-finished GCD.  
    Also: keep the bar on a failed (secret) stop-event read rather than wiping it,  
    and add a Deplete Fill option that starts the bar full and drains it as the GCD  
    elapses instead of filling up (snaps to the start value on the first frame so  
    deplete mode doesn't ease up from idle).  
- Fix Hide Items if Missing keeping cross-linked healthstones visible  
- Merge pull request #490 from Filpet96/feat/tooltip-cursor-anchor  
    Add Anchor Tooltip to Cursor option  
- Merge pull request #489 from asdfractal/bug/gcd-instant  
    Fix GCD showing on channel/empower  
- Merge pull request #485 from TF0rd/feat/color-picker-enhancements  
    feat(color-picker): add favorites and recent colors swatch rows  
- Merge pull request #486 from TF0rd/feat/quick-keybind-slash  
    feat(action-bars): add /kb slash command for Quick Keybind Mode  
- feat(color-picker): add favorites and recent colors swatch rows  
    Add two interactive swatch rows below the HSV picker:  
    - Favorites: right-click any swatch to add/remove favorites, persisted  
      in EllesmereUIDB.colorPicker.favorites (max 14, FIFO)  
    - Recent Colors: automatically records colors on OK click, deduped by  
      RGB, persisted in EllesmereUIDB.colorPicker.recentColors (max 14, FIFO)  
    Both rows support left-click to apply color and right-click to toggle  
    favorite status. Tooltips show hex code and context-appropriate action  
    text.  
    ![Color Picker Preview](.github/color-picker-preview.png)  
- feat(action-bars): add /kb slash command for Quick Keybind Mode  
- Default cursor tooltip position to Top  
- Instantly hide world-unit tooltip fade while anchored to cursor  
- Regenerate Locales/\_keys.txt  
- Merge remote-tracking branch 'origin/main' into feat/tooltip-cursor-anchor  
- Add Anchor Tooltip to Cursor option  
    Adds an "Anchor Tooltip to Cursor" toggle to Blizz UI Enhanced > Tooltips,  
    Menus & Popups. When enabled the default game tooltip follows the mouse  
    instead of sitting in its default screen corner. A position control exposes a  
    Position dropdown (Top Right by default, plus the other corners/edges and  
    center) and X/Y offset sliders for exact placement relative to the cursor.  
    The tooltip is re-owned to a 1x1 frame that tracks the cursor, hooked through  
    GameTooltip\_SetDefaultAnchor so unit, world, and action button tooltips all  
    follow. Off by default: the hook installs only on first enable and re-checks  
    the flag (Blizzard's default anchor stands when off), and the tracking frame  
    only ticks while a tooltip is shown.  
- Fix GCD showing on channel/empower  
- Merge pull request #487 from Kirihasio2/update1  
    [QoL] Hide Tutorial Button Remake  
- EUI QoL Hide Tutorial Button  
- QoL Hide tutorial implmentation  