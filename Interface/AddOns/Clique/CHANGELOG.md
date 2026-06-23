# Changelog

All notable user-visible changes to Clique are documented here.
Only features, bug fixes, and changes that affect end users are tracked.
Internal refactoring, test additions, and code cleanup are not included.

## [Unreleased]

## [5.0.4] - 2026-06-21

### Fixed
- Click bindings doing nothing on unit frames whose addon sets specific modified-click actions (e.g. EllesmereUI)

## [5.0.3] - 2026-06-21

### Added
- Warning when Target or Show Menu actions are unbound, with an option to dismiss it

### Changed
- Binding tooltip no longer appears on denylisted frames

## [5.0.2] - 2026-06-21

### Fixed
- Click bindings doing nothing on unit frames whose addon sets specific left/right-click actions directly (e.g. Dander's)

## [5.0.1] - 2026-06-21

### Added
- `/clique inspect [pattern]` command to report the click-routing state of registered frames
- Warning banner when Blizzard in-game click-casting conflicts with Clique settings

### Fixed
- Click bindings no longer stop working on third-party unit frames (e.g. EQOL party/raid) after they rebuild their frames
- Denylisting or removing a unit frame from the denylist now takes effect immediately instead of requiring a UI reload
- Spurious denylist reload prompt on closing Interface Options
- OnEnter/OnLeave snippet firing multiple times per hover
- Key bindings (non-global) doing nothing on unit frame hover
- Right-click context menu not working on NPC party members unless targeted

## [5.0.0] - 2026-06-21

### Added
- General Options, Frame Denylist, and Profile management integrated into the main Clique config window
- Tabs in the action catalog window
- Pet spells in the action catalog, with a dedicated Pet tab for pet classes
- "Use item: Primary/Secondary Trinket" actions
- Click-direction option (Down / Up / Both Up/Down) for when bindings fire, in both the config window and Interface Options

### Changed
- Interface Options panels for General Options and Frame Denylist now point to the main config window

### Removed
- "Remove wildcard target and menu actions" option (the underlying feature was removed)

---

Template for new versions:

```markdown
## [X.Y.Z] - YYYY-MM-DD

### Added
- (new features visible to users)

### Fixed
- (bug fixes affecting user experience)

### Changed
- (behavior changes, UI changes, setting changes)
```

Remove sections that have no entries. Keep entries concise and user-focused.
