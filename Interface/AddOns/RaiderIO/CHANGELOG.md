# Raider.IO Mythic Plus, Raiding, and Recruitment

## [v202607160600](https://github.com/RaiderIO/raiderio-addon/tree/v202607160600) (2026-07-16)
[Full Changelog](https://github.com/RaiderIO/raiderio-addon/compare/v202607150600...v202607160600) [Previous Releases](https://github.com/RaiderIO/raiderio-addon/releases)

- [Raider.IO] Database Refresh  
- [Raider.IO] Classic Database Refresh  
- The Settings module might not have the talents module available on classic flavors, so we have to account for that to avoid an error.  
- Merge pull request #384 from RaiderIO/bugfix/talents-shortcut-visibility-adjustment  
    Minor fix to Talent Builds shortcut Settings  
- Not that this is used, but if the module is actually disabled, then ensure to keep the EJ shortcut hidden.  
- - This commit fixes a bug with the EJ function hooks not properly hiding the button after it was initialized.  
    - The old show and hide button methods were irrelevant, because we did add a Setting which the user controls.  
    - Removed old show/hide button methods, and instead put all the visibility logic inside `UpdateShortcutsVisibility`.  
    - `UpdateShortcutsVisibility` also supports the module disable method, not that we use it, but that's why it has a `forceHide` flag to just hide the buttons regardless of the user preference.  
    - Each button has its own `UpdateVisibility` method which is responsible to handle its own visibility state.  
