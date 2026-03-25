# EllesmereUI

## [v5.5.4](https://github.com/EllesmereGaming/EllesmereUI/tree/v5.5.4) (2026-03-25)
[Full Changelog](https://github.com/EllesmereGaming/EllesmereUI/compare/v5.5.3...v5.5.4) [Previous Releases](https://github.com/EllesmereGaming/EllesmereUI/releases)

- Release v5.5.4  
- Merge pull request #221 from dnlxh/fix/monk-flickering-staggerbar  
    Fix Brewmaster Stagger bar flickering  
- Fix Brewmaster Stagger bar flickering  
    Fix Brewmaster Stagger bar flickering by preventing unnecessary SetValue(0) resets and caching color/max values to avoid redundant updates. Stagger threshold colors now apply regardless of classColored setting.  
