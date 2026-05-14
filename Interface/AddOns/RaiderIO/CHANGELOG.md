# Raider.IO Mythic Plus, Raiding, and Recruitment

## [v202605130600](https://github.com/RaiderIO/raiderio-addon/tree/v202605130600) (2026-05-13)
[Full Changelog](https://github.com/RaiderIO/raiderio-addon/compare/v202605120600...v202605130600) [Previous Releases](https://github.com/RaiderIO/raiderio-addon/releases)

- [Raider.IO] Database Refresh  
- [Raider.IO] Classic Database Refresh  
- Merge pull request #373 from RaiderIO/bugfix/mop-classic  
    MOP bugfix  
- Log mythic flexible  
- MOP doesn't have the `IsTooltipType` method, hence we can rely on the legacy `GetUnit` method instead, since taint isn't relevant in this variant of the game client.  
