# EllesmereUI

## [v5.6.5](https://github.com/EllesmereGaming/EllesmereUI/tree/v5.6.5) (2026-03-27)
[Full Changelog](https://github.com/EllesmereGaming/EllesmereUI/compare/v5.6.2...v5.6.5) [Previous Releases](https://github.com/EllesmereGaming/EllesmereUI/releases)

- Release v5.6.5  
- Merge pull request #226 from dnlxh/fix/devourer-threshold-color  
    Fix threshold color for Devourer Soul Fragments resource bar  
- Merge pull request #227 from Kneeull/patch-21  
    Implement flask state snapshots for PvP and M+  
- Implement flask state snapshots for PvP and M+  
    Add PvP and ChallengeMode flask state snapshots and update detection methods.  
    A secondary function has been to slightly lower the number of local functions to stay below Lua's 200 max limit.  
- Fix threshold color for Devourer Soul Fragments resource bar  
    The existing threshold logic only handled native PowerTypes (Maelstrom, Insanity, Focus, Lunar Power) via UnitPowerPercent. Since Soul Fragments are aura-tracked and not a native PowerType, pType was nil and the threshold check was skipped entirely.  
    Added dedicated handling for SOUL\_FRAGMENTS\_DEVOURER that compares cur directly against thresholdCount  
