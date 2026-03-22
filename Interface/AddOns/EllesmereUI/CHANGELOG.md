# EllesmereUI

## [v5.3.5](https://github.com/EllesmereGaming/EllesmereUI/tree/v5.3.5) (2026-03-21)
[Full Changelog](https://github.com/EllesmereGaming/EllesmereUI/compare/v5.2.4...v5.3.5) [Previous Releases](https://github.com/EllesmereGaming/EllesmereUI/releases)

- Release v5.3.5  
- Merge pull request #183 from danvernon/feat/chat-enhancements  
    Add chat enhancements module  
- Merge pull request #184 from nulltyto/fix/cdm-pandemic-cog-popup  
    fix(CDM): bind data source before pixel glow popup slider creation  
- fix(CDM): bind data source before pixel glow popup slider creation  
    The shared pandemic pixel glow popup's slider getValue callbacks  
    reference pf.\_getData, which was only set when the popup was shown  
    a second time. On first open, BuildSliderCore called getValue during  
    construction before \_getData was bound, causing a nil call error.  
- Merge pull request #181 from danvernon/feat/minimap-enhancements  
    Add minimap enhancements  
- Merge pull request #182 from nulltyto/feature/cdm-pandemic-glow  
    feat(CDM): add pandemic glow to CDM icons and tracking bars  
- feat(CDM): add pandemic glow to CDM icons and tracking bars  
    Add pandemic window detection (last 30% of aura duration) with  
    configurable glow effects to CDM buff/cooldown/utility icons and  
    tracked buff bars. Mirrors the existing nameplate pandemic glow  
    using secret-safe C\_CurveUtil step curves with DurationObjects.  
    - Rewrite disabled ApplyPandemicGlow stub with working implementation  
    - Add 0.2s OnUpdate ticker for lightweight alpha-only glow updates  
    - Respect glow priority: proc > pandemic > active state > buff glow  
    - Add pandemic glow overlay to tracked buff bar frames  
    - Fall back to Pixel Glow for non-square bar overlay targets  
    - Options UI: style dropdown, color swatch, pixel glow cog, live preview  
    - Cross-module Apply All syncs settings to Nameplates, CDM Bars, and TBBs  
    - Migrate old pandemicR/G/B flat keys to pandemicGlowColor table  
- fix(chat): use hooksecurefunc for SetItemRef + fix search button anchoring  
    - Replace raw SetItemRef override with hooksecurefunc to avoid taint  
    - Re-anchor search button on every UpdateSearchButtons call so it  
      correctly positions relative to copy button when toggled  
- feat(chat): wire extended options into BuildChatPage  
- feat(chat): add extended chat options page — font, enhancements, copy, search  
- Add minimap enhancements: shape, border, coords, zoom, drag, buttons, clock  
    - Shape toggle (square/round) with conditional mask texture  
    - Border thickness slider (1-5px) via PP.SetBorderSize  
    - Coordinates display with configurable decimal precision  
    - Mousewheel zoom with auto-zoom-out timer (10s)  
    - Drag-to-reposition with lock toggle and position persistence  
    - Individual button toggles replacing single hideButtons toggle  
      (zoom, tracking, calendar, mail, difficulty, crafting, compartment)  
    - Addon minimap button mouseover hiding (LibDBIcon support)  
    - Clock display with 12h/24h format  
    - Options page reorganised with section headers  
    - Migration path for existing hideButtons profiles  
- feat(chat): wire new chat features into ApplyChat lifecycle  
- feat(chat): add search dialog with search button on chat frames  
- feat(chat): add copy dialog with /copy command and optional copy button  
- feat(chat): add message filters — class colors, URLs, channel shortening, timestamps  
- feat(chat): add font face, outline, shadow, spacing, and fade to SkinChatFrame  
- feat(chat): add new DB defaults and TOC entries for chat enhancements  
- 5.3.1  
- Merge pull request #175 from danvernon/basics-module  
    Add Basics module  
- Merge pull request #178 from Yupmoh/fix/cdm-druid-form-keybinds  
    fix(CDM): update keybind cache on druid form swap  
- 5.3  
- Merge pull request #176 from Lyrex/cdm/misc-bar-unlock-mode  
    fix(cdm): stabilize empty misc bar unlock sizing  
- fix(CDM): update keybind cache on druid form swap  
    Reads ActionButton.action to resolve the current form's action slots  
    instead of assuming slots 1-12. Rebuilds keybind cache on  
    UPDATE\_SHAPESHIFT\_FORM so CDM hotkey text matches the active bar.  
- Merge pull request #166 from JensBaumannDev/fix\_unitframes\_artstyle  
    fix(UnitFrames): resolve class portrait warrior fallback on reload and fix visibility toggle from "none" causing hidden portrait frames  
- Integrate Quest Tracker and Cursor into Basics module  
    Add Quest Tracker (from PR #91) and Cursor as new tabs within the  
    Basics module. Basics now has 5 pages: Chat, Minimap, Friends List,  
    Quest Tracker, and Cursor Circle. Cursor media files included.  
    Live toggle on/off fix for all skin sections.  
- fix(cdm): stabilize empty misc bar unlock sizing  
    Why this change was needed:  
    Empty CDM Misc bars could enter unlock mode with a zero-sized live  
    frame, which made the mover collapse on hover and pushed drag math  
    toward screen origin when the user tried to reposition the bar. The fix  
    also had to respect Lua 5.1's chunk-local limit because the same file is  
    loaded directly by the in-game runtime.  
    What changed:  
    Shared CDM sizing helpers now derive a stable footprint for empty bars  
    and are reused by both `LayoutCDMBar` and unlock registration so empty  
    custom bars keep valid bounds before any icons exist. The layout path now  
    seeds that fallback size instead of leaving the frame effectively `0x0`.  
    To stay under the Lua 5.1 local limit without exporting extra helpers,  
    this change also trims a few cold locals, restores `GetTime` as a hot-path  
    local, and keeps `SafeEq` scoped to the border code. The file now also  
    annotates the bootstrap, rebuild, tick, and event-driven runtime paths to  
    make hot-path review easier.  
    Problem solved:  
    Empty Misc bars can be dragged normally in unlock mode instead of jumping  
    off-screen, and the CDM runtime still parses under the same Lua 5.1  
    constraints used by WoW itself.  
- Merge pull request #169 from JensBaumannDev/bugfix\_resourcebars  
    fixed(resourcebars): text can now be bigger than the bar itself  
- Merge pull request #171 from JensBaumannDev/fix\_unitframes\_opacity  
    fixed: Disable Bar Opacity slider when Dark Mode is enabled in UnitFrames settings  
- Merge pull request #173 from danvernon/feat/boss-focus-debuffs-castbar  
    Add debuffs to focus/boss frames and cast bar to boss frames  
- Merge pull request #174 from dnlxh/features/detachable-castbar  
    Add detached castbar support for target and focus frames  
- Add Basics module: Chat, Minimap, and Friends List skins  
    - Chat: dark bg, pixel border, edit box skinning, hide buttons/tab flash, font size  
    - Minimap: square mask, dark bg, pixel border, scale, hide buttons/zone text  
    - Friends: load-on-demand aware, NineSlice removal, dark bg, pixel border, tab skinning  
    - 3-page options panel with multiSwatch border color (custom + class)  
    - Combat safety queue for deferred re-apply  
    - Activate roster entry and add pkgmeta move-folders  
- Add detached castbar support for target and focus frames  
- Add debuffs to focus/boss frames and cast bar to boss frames  
    Wire up CreateTargetAuras for focus and boss unit frames so debuffs  
    (and optionally buffs) display on those frames. Add cast bar support  
    to boss frames via CreateCastBar + SetupShowOnCastBar. Include full  
    live-refresh logic in ReloadFrames for both features with proper  
    anchor resolution, castbar offset handling, and cache-key optimization.  
    Default settings: debuffs bottomleft, max 10, player-only; cast bar  
    enabled with hide-when-inactive off for boss frames; buffs off by  
    default on both focus and boss.  
- fixed: Disable Bar Opacity slider when Dark Mode is enabled in UnitFrames settings  
- fixed(resourcebars): text can now be bigger than the bar itself  
- fix(UnitFrames): resolve class portrait warrior fallback on reload and fix visibility toggle from "none" causing hidden portrait frames  
