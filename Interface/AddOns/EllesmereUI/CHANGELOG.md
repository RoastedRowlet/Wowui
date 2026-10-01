# EllesmereUI

## [v9.3.3](https://github.com/EllesmereGaming/EllesmereUI/tree/v9.3.3) (2026-09-29)
[Full Changelog](https://github.com/EllesmereGaming/EllesmereUI/compare/v9.3.2...v9.3.3) [Previous Releases](https://github.com/EllesmereGaming/EllesmereUI/releases)

- Release v9.3.3  
- Merge pull request #2336 from JuJuFX-dev/refactor/rb-options-split  
    Refactor(Resource Bars Options): Split Resource Bars options into per-section files  
- Rename the Resource Bars option files to *\_Options  
    ResourceBars/ becomes ResourceBars\_Options/ and every file gets the  
    \_Options suffix, so they read as part of the load-on-demand options addon  
    rather than module code.  
- Merge upstream/main into refactor/rb-options-split  
    Upstream turned the Mana Regen Spark toggle into an Off / 5-Second Rule /  
    Regen Ticks dropdown in the Bar Display page, which this branch moved to  
    ResourceBars/BarDisplayPage.lua. The change is carried over there  
    verbatim (dedented); the main options file keeps this branch's side.  
- Fix Cast Bar preview click targets  
    The icon, spell text and duration hit overlays glowed the wrong slots  
    after the rows were rearranged: the icon landed on Frame Strata, the  
    spell text on Bar Texture and the duration text on Spell Text. Point  
    them at Show Spell Icon, Spell Text and Duration Text.  
- Wire the Resource Bars option files through a shared env table  
    The main options file fills ns.\_ERB\_OptEnv with the closure helpers the  
    sections and pages read, right before RegisterModule. Each moved builder  
    re-imports them at call time; the pages move onto ns (ERB\_Build*Page)  
    and write the preview state through two setters. The new files load  
    before EUI\_ResourceBars\_Options.lua and only define functions.  
- Move Resource Bars option sections and pages into ResourceBars/  
    Verbatim move, dedented by four columns (tab-indented lines unchanged).  
    Not runnable on its own: the wiring follows in the next commit.  
- Remove dead Advanced-mode branches from Resource Bars options  
    The Advanced per-spec page was retired and every caller of the shared  
    section builders passes advanced = false. Drop the statements that only  
    ran with ctx.advanced set (sync button, synced overlay, threshold  
    normalization, spec checks) and their four locale keys.  
    Also shorten the Mana Regen Spark comment block to the comment budget.  
