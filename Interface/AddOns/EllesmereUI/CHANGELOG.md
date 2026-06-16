# EllesmereUI

## [v8.1.6](https://github.com/EllesmereGaming/EllesmereUI/tree/v8.1.6) (2026-06-14)
[Full Changelog](https://github.com/EllesmereGaming/EllesmereUI/compare/v8.1.5...v8.1.6) [Previous Releases](https://github.com/EllesmereGaming/EllesmereUI/releases)

- Release v8.1.6  
- Merge pull request #342 from a-stephany/feat/boss-stack-direction  
    Feat/boss stack direction  
- Merge main (8.1.5) into feat/boss-stack-direction  
    # Conflicts:  
    #	EllesmereUIUnitFrames/EUI\_UnitFrames\_Options.lua  
- feat: Add boss frame stack direction option  
    - Fix dropdown label order: Up before Down  
    - Add dropdown to select boss frame stacking direction (up/down)  
    - Allow negative vertical spacing values for boss frames  
    - Update boss frame anchoring to respect frame height in both directions:  
      * Up: BOTTOMLEFT of new frame anchors to TOPLEFT of previous frame  
      * Down: TOPLEFT of new frame anchors to BOTTOMLEFT of previous frame  
    - Add spacer widget type for UI layout flexibility  
    This ensures consistent spacing behavior regardless of stack direction.  
    The dropdown uses DualRow with a spacer to avoid spanning full width  
