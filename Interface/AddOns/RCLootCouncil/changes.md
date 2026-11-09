## Changes

### Bonus Rolls Display

Bonus rolls are now divided from non-tradeables and aligned to the bottom right side of the Voting Frame.

Both groups now dynamically scales up to half the width of the frame, and adds additional rows when required (looking at you Ula'tek bonus roll mayham!).

### Loot History

Added number of items displayed to the Loot History frame, as well as in the Loot History options.

Updated filter and right-click menus to use BlizzardMenu. These are way newer and supports scrolling, finally fixing the old problem of not being able to select candidates when changing winners.  
*Implementing this also fixed a number of bugs with the old system.*

- Added filter for bonus rolls (previously part of "Status")
- Added filter for award reasons
- Each button group can now be filtered seperately.

*Note: when you have a mix of responses from the same button group and button (e.g. default, button 1) that are different (can be caused by two different leaders with different settings), the button name and visuals are resolved in this order: Your settings, your leaders settings (if present), the loot db.*

Because of these changes, saved filters have been reset.

