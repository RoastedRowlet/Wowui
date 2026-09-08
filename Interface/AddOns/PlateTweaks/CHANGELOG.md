# Changelog

All notable changes to PlateTweaks are recorded here. No file like this
existed before 1.8.4, so history prior to that release is not reconstructed.

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

## 1.10.0

### Added

- **Threat colouring.** A colour chosen by the unit's threat state rather than
  by a debuff, drawn above every spell rule on both the health bar and the
  border. It lives in a **Threat** section at the top of the Health Bar page.

  It reads as one row -- a strip of the four colours, what it is doing in
  words, Edit, and a switch -- with the situations themselves behind Edit.
  Threat is one thing you turn on, not four rules to maintain.

  **The border is its own module**, on the Border page, with its own switch,
  its own four colours and its own thickness. It was a column inside the bar's
  row, which meant every border question had to be asked again there -- and it
  costs nothing from the draw-slot budget, so pricing it beside something that
  does was misleading.

  **There is no combat option.** Threat colouring is in-combat only, always.
  Out of combat every plate reports the same state, so the "not tanking"
  colour would paint the whole screen and none of the others could ever fire:
  the switch had one correct position. A stored opt-out from a profile written
  against the first build is dropped on load.

  Three situations -- **Has Aggro**, **Near Aggro**, **No Aggro** -- named the
  same way everywhere: the rows in Edit, the colour chips on the collapsed
  row, and `/pt threat`. The client reports four threat values; "tanking
  securely" and "tanking, but only just" are the same news on a nameplate read
  at a glance, while the warning shot -- top of a mob's list without holding it
  yet -- is the one you can still act on, so it keeps its own colour.

  The **Role** dropdown (Automatic from your spec, Tank, Damage, Healer)
  decides which of the three ships switched on: a tank is alarmed by losing a
  mob, everyone else by drawing one. No Aggro ships off either way --
  colouring every plate in a pull green is noise, and it costs a draw slot a
  warning colour could have had. The role changes nothing else; a state is a
  fact about the mob, so it reads the same whatever you are playing.

  Priority over spell rules is structural rather than a comparison made while
  painting: threat reserves its draw sublevel before the missing ladder and
  before any spell rule is allocated one. The spell rules underneath are still
  built and still hold their own slots, so when the threat state clears their
  colour comes straight back with no rebuild.

  Nothing here rides an aura button, which is what makes the whole feature
  possible: threat holders are frames of ours, so they can be shown and hidden
  in combat. State is read through `UnitThreatSituation`, a readable carve-out
  inside instances, and an unreadable answer colours nothing rather than being
  treated as zero. Updates arrive on the client's threat events and on the
  existing quarter-second poll.

  `/pt threat` reports the role in force, which situations are coloured, and
  what your current target reports right now.

- **Draw slots.** Nameplate addons leave a finite amount of room to draw in,
  and a profile that asks for more than fits has always failed the same quiet
  way: the lowest rules share a slot, which of them wins is undefined, and the
  same rules then colour some plates and not others in one pull. That was only
  reported after the fact, on a plate that had already built.

  The Spell Rules header now reads **Rule Capacity: 30%**, amber past 80% and
  red over budget. A percentage rather than a fraction because the denominator
  is a measurement of the host addon's leftover draw sublevels: a number nobody
  has a feel for, and one that differs between skins of the same addon, so
  "6 / 8" invited reading the 8 as meaningful. One line of text rather than a
  row of pips, because a gauge earns its width when you watch it move, not when
  it reads the same number every time you open the window. Each rule row and each rule row shows what it spends and on what (its tint, an
  underlay, Cover missing health, Pandemic Flash). Border-only rules read as
  costing nothing, because they draw outside the bar.

  Addons that pin every rule to one frame level (Plater, Blizzard's default
  plates, NDui) are the ones with a finite pool, and they get the gauge. On
  Platynator, EllesmereUI and generic plates each rule gets its own frame
  level, so the budget is level headroom in the hundreds; those report the
  count in use and leave it at that rather than showing a bar nobody can fill.

  The budget is measured off a live nameplate when one is up, since the host
  addon's own textures decide the ceiling and it differs between skins of the
  same addon. With no plate on screen the meter falls back to the shipped
  estimate for your addon and says so.

  `/pt slots` prints the same accounting, including which pool the room comes
  from and what to drop when the profile is over budget.

### Changed

- **The Health Bar and Border pages are laid out by a flexbox engine**,
  vendored from FlexProto as `Libs\Flex\Flex.lua`. Every other section in the options window
  anchors each control to an x taken from a constant, while its column headings
  take their x from a second copy of that constant -- which is how this section
  first shipped with its headings a column off and its footnote printed through
  a button. Under Flex the header and a row are the same node shape, so a
  column cannot be in two places, a hidden block costs exactly zero height, and
  the section's height is measured rather than guessed. `dev/` gains a layout
  test asserting all three.

  The rule lists moved onto it too. What that replaces is a single running
  `y` threaded through every block -- rows, the warning, the button row, the
  missing-health colour, the mob-tier swatches -- each one subtracting its own
  height from it. Every overlap on those pages came from one block guessing
  that height wrong: a wrapped warning counted as 32px, a button row as 26.
  Optional blocks are now hidden nodes, which cost exactly zero height, and
  the mob-tier swatches wrap onto a second line at a narrow window rather than
  running off the edge -- something a running `y` could never do.

  Alignment across both pages now comes from one set of numbers (`NS.UI`) and
  one centring helper, rather than per-widget offsets: a heading is a cell of
  the same width as the control it names, so the two share a centre line, and
  explanatory text is indented past the rows so it reads as commentary rather
  than another entry. Padding on a Flex *item* is silently ignored -- only
  boxes have it -- which is why every footnote had been sitting flush against
  the section's left edge; notes are wrapped in a padded box now, with a test
  pinning both behaviours.

  The library is a straight copy: fixes go upstream in FlexProto and come back
  as a whole-file replacement.

- **Section prose moved into a `?` button on each header.** Every list carried
  a paragraph underneath saying what the list was for -- read once, then
  permanent, costing a band of vertical space on every page on every visit.
  The text is now one hover away and takes no room at all. Warnings stay in the
  page: those are about the current profile being wrong right now, and
  something you have to hover to discover is something you will not discover.

- **"Color Rules" is now "Spell Rules"**, since threat colouring sits above it
  and both are colour rules.

- Profile export and import carry the threat settings. A state the sender never
  touched stays absent rather than being filled in on the way through -- the
  recipient's own role decides its shipped colour.

## 1.9.23

### Changed

- **Expected aura-button re-pins are no longer counted as failures.** A bound
  aura button only accepts a frame level inside its own `initializeFrame`, so
  `RepinLevels` always fails on one -- in every environment, group or solo, in
  combat or not. Those failures are the mechanism working: the button repairs
  itself from `record.level` the next time the pool initialises it.

  They were counted in the same number as a container refusing, which is a real
  fault with no self-repair. A healthy 128-second dungeon therefore reported
  `1 re-pinned | 46 needed a rebuild | 184 refused` when the honest reading was
  47 drifts, all of them handled -- measured in the same capture as 3772 rule
  samples at `lvlSet=1 lvlRefused=nil`, and 100 out of 100 readable tint-host
  levels verified correct.

  `Pin` now takes the two cases apart by which list the frame came from, since
  an aura button's own fields are refused under secrecy and asking it what it
  is would fail exactly where it matters. `NS.levelDrift` gains `pending` (the
  buttons) and `selfHealing` (drifts whose only failures were buttons); a drift
  of that shape counts as re-pinned rather than deferred, and no longer sets
  `rig.levelDirty`.

  No behaviour change on screen. Every frame is still asked for the level in
  the same order, and `appliedLevel` is still only advanced when the whole rig
  confirms.

- `/pt status` prints the button count on its own grey line under `bar level
  drift`, and `/pt bar` names both numbers separately rather than reporting one
  total as refusals.

## 1.9.22

### Fixed

- **On Plater, any profile with a missing-debuff rule built nothing at all.**
  `MISSING_SUBLEVEL_MIN` and `MISSING_SUBLEVEL_MAX` were file-locals declared
  *below* `NS.PlaterMissingPlan`, which reads them. A Lua local is only in scope
  for what follows its declaration, so inside that function both names compiled
  as globals and read nil:

      tints: Tints.lua:258: bad argument #1 to 'min' (number expected, got nil)

  The occlusion branch failed the same way one line further on, arithmetic on a
  nil instead of `math.min`. The throw happens before the rule loop, so the rig
  was abandoned with zero containers and zero textures -- the plate could not
  colour at all, rather than colouring wrongly. Captured live as 5 rigs, 5
  errored, 0 containers, 0 textures.

  The declarations moved above their first use. No behaviour change beyond the
  names now resolving: -8 and 5 were always the intended values.

  Frame levels were healthy in the same capture (3 drifts detected, 3 re-pinned,
  0 refused), so this is unrelated to the 1.9.16/1.9.21 level work and was not
  introduced by it.

## 1.9.21

### Fixed

- **A plate could go up to a second without colour after you targeted it.**
  Plater raises a unit frame by 5000 frame levels when it becomes your target
  and drops it back when it stops being one. The 1.9.16 sweep catches that, but
  only on its next tick, so the gap was as much as a full second -- long enough
  to see, and hit repeatedly when you switch quickly between adds. In the
  opposite direction (losing a target) the same gap left our tint 5000 levels
  ABOVE the bar, drawing over Plater's own health fill, text and icons.

  Targeting is the one moment the move is predictable, so
  `PLAYER_TARGET_CHANGED` now re-pins levels directly instead of leaving it to
  the sweep. Deferred by one frame: Plater's handler for the same event may run
  after ours, and reading the level too early returns the pre-bump number --
  which would latch the stale value again and hand the job straight back to the
  ticker.

  Levels only, and every bound rig rather than the two units involved -- the
  old target's unit token is already gone by the time the event fires, and a
  re-pin is a single integer compare on any plate that did not move. The sweep
  is unchanged and still covers every move that is not a target change.

  Not covered by this: an aura button that refuses a re-pin while its debuff is
  already up stays low until the debuff re-applies (or combat ends). That path
  is unchanged, and is the remaining known cause of a plate that will not
  colour.

## 1.9.16

### Fixed

- **Plates could be pinned 5000 frame levels below their own health bar, and
  never colour.** This is the long-standing "same rules, same pull, some mobs
  colour and some do not".

  The bar's frame level is read once, when the rig is built, and every
  container and aura button is pinned to it. Plater raises its unit frame by
  5000 *after* the plate appears, so a rig built inside that window latches the
  pre-bump number. Three live captures, same pull: bar 5011 against baseLevel
  11, bar 5151 against 151, and the one plate that did colour, 5081 against
  5081.

  Nothing failed when this happened, which is why no diagnostic caught it in
  months of looking. `SetFrameLevel` was accepted -- it was aimed at the wrong
  number. Frame level is decided before draw layer, so from 5000 below, every
  region the bar owns (the health fill included) draws over our tint at every
  sublevel. `flat pin ok: level accepted on all 3 button(s)` was true and
  useless.

  Health bars are pooled, so a bar that latched a stale level carried it to
  later mobs. `AnchorTints` re-reads the level correctly, but the only thing
  that called it mid-pull was combat *ending* -- which is why colouring
  "came back afterwards".

  A once-a-second sweep now compares the bar's level against ours and re-pins
  when they differ, in combat, without waiting. One integer compare per bound
  plate; nothing else is re-done, because nothing has moved. Where a re-pin is
  refused -- an aura button only accepts a level inside its own callback -- the
  rig is marked and rebuilt when combat drops.

### Added

- `/pt status` reports `bar level drift`: how many plates were re-pinned, how
  many needed a rebuild, and how many are sitting at the wrong level *right
  now* -- a live count, so it shows whether the sweep is keeping up.
- `/pt bar` calls the mismatch out explicitly (`LEVEL DRIFT: bar wants N, we
  are pinned at M`) rather than leaving two five-digit numbers to be compared
  by eye.

## 1.9.15

Covers the unreleased test builds 1.9.12 through 1.9.14 as well.

### Fixed

- **Containers that went dark mid-fight stayed dark until combat ended.** Every
  previous fix in this area worked by preventing a container being switched
  off, which only helps for a cause already identified. A once-a-second sweep
  now looks at each bound plate's ROOT containers and, if one reads hidden or
  disabled, switches it back on -- without waiting for lockdown to lift, and
  without caring why it went off.

  Root only, deliberately: `Show` on a nested container is refused while auras
  are secret, so retrying one every tick would be pure waste. `SetUnit` is
  never called from the sweep either -- re-assigning the same unit churns the
  button pool, which is the cost this whole area has been trying to avoid.
  Only a definite `false` is acted on; a refused or secret read means we do not
  know, and flipping something on because we cannot read it is its own churn.

  The cost is a couple of boolean reads per root container per rule -- roughly
  forty a second at four rules and ten plates -- and nothing at all happens on
  a healthy plate. It rides the existing ticker rather than adding a timer.

- **`/pt slots off` no longer survives quietly.** That switch exists to A/B the
  aura-slot API against the older pooled-group path; the group path costs about
  ten times as much per rule and is a visible freeze on a large pull. Anyone
  carrying it from a test is put back on slots once, and `useAuraSlots` is now
  stated as a default rather than relying on nil. Setting it off again sticks.

### Added

- `/pt status` reports `containers revived this session` -- how many root
  containers were found dark mid-fight and switched back on. A climbing number
  during a pull confirms containers genuinely do go dark and that they are now
  being recovered; a flat zero while colouring is still wrong rules that
  mechanism out, which is just as useful.

## 1.9.11

### Fixed

- **A hidden nested container could never be shown again, killing combo rules
  for the rest of a fight.** `RetireTints` hid every container in a rule's
  chain. The depth-1 container is a child of the health bar and ours to show
  again; deeper links are children of aura buttons, where `Show` is REFUSED
  while auras are secret. Hiding one in combat was therefore a one-way door.

  `ActivateContainer` already assumed this could not happen, in as many words:
  "those were never hidden in the first place, so a refusal costs nothing".
  They were -- by `RetireTints`, on the same rig.

  Reachable mid-combat: `DiscardRig` runs from `OnPlateAdded` whenever a
  plate's bar identity changes, and unlike the repair path beside it that is
  not gated on being out of combat. Only multi-debuff rules are affected,
  since a single-debuff rule owns nothing below the root -- so it presents as
  some rules on a bar painting while others stop, for the rest of the fight,
  then recovering once combat ends and `Show` is permitted again. Health bars
  are pooled, so a bar it happened to could carry the dead chain to later mobs.

  Only the root is hidden now. Disabling it is sufficient regardless: with the
  root disabled the engine pools no buttons, so the nested containers have
  nothing to hang off and draw nothing whatever their shown state.

- The two-layer slot pool no longer raises the top of the ladder above the
  previously proven ceiling. On a live Plater bar the survey missed its border
  (hidden at scan time, on a child frame, or reading secret in combat all skip
  identically) and placed rule 1 at OVERLAY -1, one above that border, so the
  tint painted over the plate outline. Anything unreadable counts as free, and
  free is the wrong guess when being wrong means covering host art -- the pool
  can now only ever ADD slots below the old ceiling.

## 1.9.7

### Changed

- **Rules can now be placed in ARTWORK as well as OVERLAY, roughly doubling
  the room on a flat-pinned bar.** OVERLAY alone gives about six usable
  sublevels on Plater, and a four-rule profile with Pandemic Flash needs
  eight -- measured live, with two rules landing on -8 together and the winner
  decided by whichever aura button initialised first. That is decided
  per-plate, which is why identical rules could paint some bars and not others
  in the same pull.

  ARTWORK above the host's own fill was free the whole time: it sits above the
  bar's colour and below EVERYTHING in OVERLAY, which is exactly where a tint
  belongs. A probe on a live Plater bar showed ARTWORK 1 as the first visible
  sublevel with 1..7 all drawing. Because ARTWORK is entirely below OVERLAY, a
  rule that spills into it is automatically outranked by every rule above --
  priority comes out right with no cross-layer arithmetic, and each rule's own
  pieces stay in one layer so tint+1 / tint-1 keep their meaning.

  The pool is now measured per bar rather than assumed per adapter: the plan
  reads the host's shown textures off the health bar, takes the ceiling from
  the lowest shown OVERLAY texture (its border), and only ever hands out
  consecutive free slots -- so a rule's underlay or cover can never land on
  host art, and we never tie with the host's fill.

- `/pt layers` now prints each rule's LAYER as well as its sublevel. With two
  layers in play, "-3" alone no longer says who draws on top.

### Added

- **A Delete button on the Diagnostics page**, beside the Saved captures dropdown: loads-then-removes the capture you picked. Also `/pt capture delete <number>` removes a single saved capture, using the
  number from `/pt capture list`. Clearing everything was previously the only
  way to drop one, which is no good once a run worth keeping sits alongside a
  few junk ones. `/pt capture clear` now also reports how many it removed.

## 1.9.5

### Fixed

- **Pandemic Flash was reserving a sublevel on every rule, including rules
  that never get one.** `BuildRule` only creates a flash for single-debuff
  rules (`record.spellCount == 1`) -- a flash doubles a rule's texture count
  and a combo cannot afford it -- but the 1.8.9 allocator reserved a slot for
  every rule whenever the module was on. Multi-debuff rules were holding
  space for a texture that was never created, pushing real rules off the
  bottom of the ladder. Measured live: a three-rule profile on Blizzard plates
  reported `ran out of sublevels`, with rule 2's underlay and rule 3's tint
  both landing on -8. With the reservation corrected the same profile fits
  with room to spare and Pandemic Flash stays on.

### Changed

- Corrected a comment claiming `SetFrameLevel` on an aura button is refused
  while auras are secret. Measured on a live plate in combat: it is
  **accepted** inside the button's own `initializeFrame` callback, which is
  the one place a forbidden object may be touched. The refusal is real for
  the re-level pass in `AnchorTints`, which reaches buttons from outside any
  callback -- the note belonged there, not on the build path.

## 1.9.3

### Added

- **`/pt bar` now reports whether flat-pinning actually took.** Flat-pinning
  works by forcing each aura button's frame level down to the bar's, so their
  draw layers interleave and sublevel decides which draws on top. That call is
  refused while auras are secret -- in combat, which is when most plates get
  rigged. When it fails the button keeps the higher level its container gave
  it, frame level beats draw layer, and the tint draws over the host's border
  and name text regardless of the sublevel it was assigned. The outline
  builder already compensates for this and deliberately skips flat-pinned bars
  (raising it there would blank Plater's name), so on Plater and Blizzard
  plates -- the two hosts where flat-pinning IS the mechanism -- nothing
  detected or corrected it.

  Prints `flat pin ok: all N button(s) at the bar's level` or
  `flat pin FAILED on N of M button(s)`. Works in combat: it calls
  GetFrameLevel on the button object we already hold rather than reaching
  through the texture's parent, which is what makes the per-tint `ownerLevel`
  on the next line read `refused`.

### Fixed

- 1.9.2 crashed `/pt bar` with `attempt to call a nil value` -- the new check
  used a helper that exists in a different addon. Never released.

## 1.9.1

### Added

Four more things a capture could not previously show, each one a silent
reason colouring can fail while every existing count looks healthy.

- **Cumulative container refusals, split by combat lockdown.** A refusal was
  only ever recorded on the rig's own record -- and a rig is discarded when it
  is repaired, so the recovery attempt destroyed the evidence of what went
  wrong. The session counter survives it. Secure aura containers cannot be
  created under lockdown, so `refused ... under combat lockdown` climbing
  during a pull is the "plates that first appear mid-fight build empty" theory
  being confirmed; refusals out of combat mean something else entirely.
- **Peak concurrent plates, and peak while in combat.** "It only happens on
  large pulls" is the most common report shape and the least checkable, since
  a capture taken afterwards shows what is on screen now rather than what the
  pull peaked at.
- **`not-on-target` / `not-on-focus` flags per rule.** These per-rule opt-outs
  unbind that rule's containers for that one plate, so it never colours while
  everything reports healthy. Nothing surfaced them anywhere -- a tick someone
  set months ago and forgot reads exactly like "it sometimes just doesn't
  work".
- **A loud warning when Test Mode is on.** Test mode paints its own copies
  onto real nameplates and suppresses the missing wash, so a session left
  running shows colours unrelated to any real debuff, and every other line in
  the capture describes a plate you are not actually looking at.

## 1.9.0

### Added

- **`/pt status` now reports rig health across every plate, not one sample.**
  Chasing a report of "colouring sometimes does not happen at all, usually on
  large pulls with many nameplates" turned up a blind spot that would have
  hidden exactly that: the per-rule lines in `/pt status` are read from a
  single rig picked arbitrarily by `pairs`, described in the code as
  "representative" on the reasoning that every rig builds the same rules.
  That holds for the *config* and not for the *outcome* -- secure aura
  containers cannot be created under combat lockdown, and the builders count
  a refusal rather than raising, so a rig can carry the same rules with
  nothing attached to them. `info.errored` did not catch it either, since
  that only counts builders that actually threw. A pull where half the plates
  built nothing could sample a healthy one and report everything as fine.

  New line, printed only when something is wrong:
  `rig health: N bound plate(s) drawing nothing | N with refused builds | N unsound`.
  A bound plate drawing nothing is the user-visible bug -- it is on screen and
  can never colour, whatever debuffs land on it. Also shown on the
  Diagnostics page.

## 1.8.9

### Fixed

- **Rules on Plater now get a draw sublevel each instead of sharing.**
  Confirmed on a live client via 1.8.8's new diagnostic: every FontString on
  a Plater health bar reports OVERLAY sublevel 0 -- including the unit name
  and health percent, which Plater's own code explicitly sends to 7 and 5.
  So the text floor really is 0 (`PlaterTextFloor` was behaving correctly),
  and the entire rule ladder has to fit between -1 and -8.

  The allocator handed every rule three consecutive sublevels -- cover, tint,
  underlay -- whether or not it had a cover or an underlay to put in them.
  Three-per-rule into that range is two rules. The third rule's tint and its
  own underlay both clamped onto -8, and its cover landed on the second
  rule's underlay: two real collisions, with undefined draw order between an
  opaque replica of the bar and the tint it is supposed to sit beneath. That
  is a direct candidate for the reported "target is right, the mob next to it
  shows the bar's original colour" and "wrong rule applied" on Plater.

  Sublevels are now allocated to what each rule actually draws. Most rules
  need one: an underlay exists only when the rule covers a lower one, a cover
  only with Cover missing health, and the pandemic flash claims its own slot
  only when that module is on. A four-rule set that previously collided twice
  now fits with none, and six single-debuff rules fit where two did. The top
  of the ladder is deliberately unchanged, so nothing can newly collide with
  what sits above it.

- When a ladder genuinely cannot fit -- e.g. three nested rules with both
  Cover missing health and Pandemic Flash on, which wants nine slots in six
  -- `/pt layers` now says so and names what to turn off, instead of printing
  numbers that quietly repeat.

- `/pt layers` reads each rule's sublevels back off the built record rather
  than re-deriving them from the rule's index, which stopped being possible
  once allocation depended on what earlier rules consumed. Unused slots print
  as `unused` rather than a number, so a reserved-but-never-drawn underlay
  cannot send someone chasing an overlap between two textures that were never
  both created.

## 1.8.8

### Added

- **`/pt bar` now names which FontString is holding the text floor down.**
  `NS.PlaterTextFloor` takes the minimum OVERLAY sublevel across every
  FontString on the bar, and `PlaterRankSublevels` derives the whole rank
  ladder from it -- so one text sitting lower than expected compresses every
  rule's sublevel at once. Reading Plater's source shows it creates its level
  text as `CreateFontString(nil, "overlay", ...)` with no sublevel argument
  (landing at 0) while sending its name text to 7 and its health percent to
  5, which would drop the floor to 0 and collapse four clean ranks to two,
  with rank 3+ sharing a sublevel. The old output printed the floor as a bare
  number with no owner, which could not distinguish that from a skin
  legitimately drawing text low. Each FontString is now listed with its
  layer, sublevel, shown state and text, identified by object identity
  against `healthBar.unitName` / `.actorLevel` / `.lifePercent`.
- The `plater name text:` line is replaced by this block. Its layer/sublevel
  reads also went through raw `tostring()`, the same unguarded pattern fixed
  elsewhere in 1.8.7; they now use the secret-safe helper, which was
  previously defined *below* this code and so was unavailable to it.

## 1.8.7

### Fixed

- **`/pt layers` crashed outright on a plate under aura secrecy**
  (`Core.lua:2767: attempt to compare local 'layer' (a secret string value,
  while execution tainted)`), reported live by a user on a Blizzard default
  nameplate. `region:GetDrawLayer()` can return a secret `layer` string even
  when the call itself succeeds; the code did a raw `layer == "OVERLAY"`
  comparison with no secrecy check. Comparing a secret to a literal throws.
  Fixed with an `issecretvalue()` guard before the comparison, matching the
  pattern already used by the `Show()`/`DescribeField()` helpers elsewhere in
  the same functions.
- **The same unguarded pattern existed in `NS.PlaterTextFloor`
  (Tints.lua)** -- not a diagnostic print, but code that runs during actual
  rig construction on every Plater plate (`BuildTints` calls it while
  computing where Plater's own text sits). A throw there is caught by the
  `pcall` around `BuildTints` at the `BuildRig` level, so it doesn't crash
  the game -- but it does get recorded as a build error and the whole rig
  gets marked unsound and dropped, silently, for that plate. This is a
  plausible real contributor to earlier reports of inconsistent Plater
  coloring (wrong rule shown, some plates uncolored) that is independent of,
  and probably more direct than, the combat-timing rig-repair theory from
  1.8.5/1.8.6 -- it depends on secrecy state at build time rather than on
  when the rig was assembled. Fixed the same way.
- A third, not-yet-triggered instance of the same class in `PrintBarDebug`
  (`healthLevel > unitLevel`, plus two unguarded `tostring()` calls on
  `GetDrawLayer` results) fixed proactively for consistency.

## 1.8.6

### Added

- **`/pt bar` and the Diagnostics "Full Report" now show whether the target's
  rig was built during combat lockdown, whether it currently reads sound, and
  how many of its repair attempts are used.** Prompted by a real user report
  of intermittent coloring on Plater (correct on the current target, wrong or
  missing on other simultaneously-visible mobs, and occasionally the wrong
  rule showing) -- the existing per-tint `shown/alpha/... refused` fields
  cannot confirm or rule this out, since that "refused" is a read limitation
  under aura secrecy, not evidence about whether the texture exists. The new
  `rig build: ... | built in combat ... | sound ... | repairs used X/Y` line
  is directly checkable: target the plate that looks wrong and see whether
  it's sitting on an unsound, un-repairable rig. Combined with 1.8.5's rig
  repair attempts setting, this turns "weird inconsistencies" into something
  a report can actually confirm.

## 1.8.5

### Added

- **Rig repair attempts is now a setting** (Setup -> All Plates -> Performance
  -> "Rig repair attempts", 1-5, default 1). A rig built while
  `InCombatLockdown()` is true is suspected structurally incomplete (secure
  `AuraContainer` creation can be silently refused mid-combat) and previously
  got exactly one chance, ever, to be discarded and rebuilt once combat
  allowed it. In a long boss fight or a tightly chained M+ pull, combat can
  stay up for minutes, so a plate whose one repair attempt itself landed
  during a brief regen flicker between two pulls was stuck uncolored for the
  rest of the session on that health bar -- this is the likely explanation
  for "the rule works sometimes, not all the time" reports that are not
  actually about the rule's condition. Raising the cap gives a plate more
  chances to recover, at the cost of leaking a bounded number of frames per
  extra attempt (WoW cannot destroy secure frames once created) -- the
  in-game control carries an explicit warning about that tradeoff, and the
  original default (1) is unchanged.
- `/pt status` now prints the configured cap alongside the rebuilt-rig count,
  e.g. `rigs rebuilt after a bad build: 9 (built in combat, or a container
  was refused; cap 1)`, so the setting's effect is visible without opening
  the options window.

## 1.8.4

### Fixed

- **"NOT KNOWN" false negative on legitimately-applicable auras.** `NS.CanApplyAura`
  (Spells.lua) only trusted the Cooldown Manager's aura list and `IsPlayerSpell`
  when deciding whether a rule's debuff can ever land on this character. Both
  miss an aura that lands as a side effect of a talent/hero-tree passive
  rather than as its own trackable ability or spellbook entry (e.g. Sentinel's
  Mark) -- the rule was flagged `NOT KNOWN` in `/pt status` and could never
  fire even though the spec genuinely applies it.

  `CanApplyAura` now also checks the addon's own aura-observation log
  (`NS.LearnAuras`, which already passively records every `name -> spellID`
  pair actually seen landing as a player aura) and trusts a direct
  observation over the spellbook heuristic.

- **Learned aura IDs were never actually saved.** The observation log wrote to
  a global (`BOONPLATES_SETTINGS`) left over from before the BoonPlates ->
  PlateTweaks rename, which the `.toc` never declared under
  `## SavedVariables`. Everything recorded there was silently discarded on
  every `/reload` or relog. Moved to `PLATETWEAKS_SETTINGS.auraIDs`, which is
  declared and persists correctly.
