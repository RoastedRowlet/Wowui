## 1.11.0

A large overhaul of the colouring pages.

### Added

- **Threat colouring.** Has Aggro / Near Aggro / No Aggro, on the bar and the
  border, drawn above every spell rule. Role-aware: tanks get No Aggro first
  and on by default. Optional flash when you lose aggro.
- **Target and focus colouring.** Its own colours, borders and edge markers,
  ranked under threat and above your rules. Ships on, at half opacity over
  diagonal stripes.
- **Draw slots.** Every rule shows what it costs and the list shows how much
  of your nameplate addon's drawing room is left, so running out is something
  you can see coming.
- **"What Colors This Plate"** at the top of the page: the resolution order,
  with live counts from your profile.
- **A colour picker of our own**, used everywhere in the addon, with an
  opacity switch and slider and live previews.
- **A learned-debuff list.** The addon remembers debuffs it has seen you
  apply, account-wide, and offers them in the rule editor alongside the
  Cooldown Manager. `/pt learned`, `/pt forget <id>`.

### Changed

- **Bar rules and border rules are one list.** Border rules fold in on first
  load; the old list is kept as a backup in your profile.
- **Rules are edited in place**, in the list, instead of on their own page.
- **The colouring pages are laid out by a flexbox engine**, so columns,
  spacing and alignment come from one spec rather than from hand-placed
  coordinates.
- **Health Coloring's switch now governs the whole page** -- threat and
  target/focus included.
- Section prose moved into a `?` button on each header.
- "Color Rules" is now "Spell Rules".

### Fixed

- A missing-debuff rule with its bar half switched off no longer paints the
  bar.
- Target/focus borders can be given a thickness, growth direction and gap.
- Marker opacity previews correctly.
- Test and Test All are back on every preview page.
