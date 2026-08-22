# Grid2

## [4.0.22](https://github.com/michaelnpsp/Grid2/tree/4.0.22) (2026-08-21)
[Full Changelog](https://github.com/michaelnpsp/Grid2/compare/4.0.18...4.0.22) [Previous Releases](https://github.com/michaelnpsp/Grid2/releases)

- Removed delayed updates for icons indicators (not necessary with the new aura system).  
- Added a new "health-max-loss" status compatible with bar/multibar indicators.  
- BugFix: Text(aura) indicator frame level setting was not working.  
- Small fix in square indicators for big indicator sizes.  
- Increased the limit for bar aura colors to 3.  
    Better handling of bar and multibar aura colors slots.  
- Now bar and multibar indicators support up to two aura statuses linked to the colors tab. This allows to color the main health bar  
    with several buffs/debuffs without creating two bar indicators. The aura  limit is kept low (2) to avoid possible performance  
    issues: the new blizzard aura system does not allow to use the same texture for several auras, so instead of one graphical widget now we have create a lot of textures&auras stacked at the same place to implement this.  
