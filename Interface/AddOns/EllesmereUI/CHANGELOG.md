# EllesmereUI

## [v5.4.6](https://github.com/EllesmereGaming/EllesmereUI/tree/v5.4.6) (2026-03-23)
[Full Changelog](https://github.com/EllesmereGaming/EllesmereUI/compare/v5.4.5...v5.4.6) [Previous Releases](https://github.com/EllesmereGaming/EllesmereUI/releases)

- Release v5.4.6  
- Merge pull request #199 from Lyrex/castbar/blizard-castbar-showing-up  
    fix(castbar): centralize Blizzard cast bar ownership  
- fix(castbar): centralize Blizzard cast bar ownership  
    Why this change was needed:  
    Disabling EllesmereUI's replacement player cast bar could still bring  
    Blizzard's `PlayerCastingBarFrame` back, which created duplicate cast  
    bars for users who rely on another addon to hide or replace the default  
    bar.  
    What changed:  
    Added a shared suppression helper in the root addon and switched  
    Resource Bars and Unit Frames to register themselves as cast bar owners  
    through that helper instead of each module reparen ting or restoring  
    Blizzard's bar independently.  
    Problem solved:  
    EllesmereUI now suppresses Blizzard's player cast bar only while an EUI  
    replacement bar is active, then hands control back to Blizzard or other  
    addons without forcing the default bar visible again. The shared release  
    path still calls Blizzard's own `SetUnit("player")` setup so existing  
    profiles keep the expected default cast bar behavior when no EUI owner  
    is active.  
