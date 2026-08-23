# Raider.IO Mythic Plus, Raiding, and Recruitment

## [v202608230600](https://github.com/RaiderIO/raiderio-addon/tree/v202608230600) (2026-08-23)
[Full Changelog](https://github.com/RaiderIO/raiderio-addon/compare/v202608220600...v202608230600) [Previous Releases](https://github.com/RaiderIO/raiderio-addon/releases)

- [Raider.IO] Database Refresh  
- - Added a chat event filter secret value guard in case the text argument is a secret value. (#390)  
    This would have lead to an error when typing /who during instance combat as the addon attempted to add mythic plus score.  
    - Talent builds will attempt to change filters automatically if some filters may be the cause for the frame to be empty.  
    For example, mythic raid will be set to heroic when there is no mythic data to display, but there is heroic data.  
    Like before, the weapon or speed selection still resets those back to the "all" option if set and there is no data to display.  