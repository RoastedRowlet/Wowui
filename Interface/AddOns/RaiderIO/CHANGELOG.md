# Raider.IO Mythic Plus, Raiding, and Recruitment

## [v202605042033](https://github.com/RaiderIO/raiderio-addon/tree/v202605042033) (2026-05-04)
[Full Changelog](https://github.com/RaiderIO/raiderio-addon/compare/v202605040600...v202605042033) [Previous Releases](https://github.com/RaiderIO/raiderio-addon/releases)

- Vlad's Dropdown Taint Fix (#372)  
    * Until the dropdown taint is fixed by Blizzard, this is an attempting to avoid calling `Menu.ModifyMenu` too early in the session, by delaying it until the first menu has been opened by the player.  
    * Noticed that the friend list bnet data can return secret faction string.  
    * A player level can be secret under certain conditions.  
    ---------  
    Authored-by: Alex Pedersen <vladix@gmail.com>  
- [Raider.IO] Classic Database Refresh  
