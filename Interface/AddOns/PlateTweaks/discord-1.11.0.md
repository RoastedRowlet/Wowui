# RELEASE: PlateTweaks 1.11.0

The biggest update yet — the colouring pages have been rebuilt.

**Threat coloring**
Color plates by whether a mob is on you: Has Aggro, Near Aggro, No Aggro, on the bar and the border. It knows your role, so tanks get No Aggro first and turned on by default. There's an optional flash for the moment you lose aggro. Threat always draws above your spell rules.

**Target & focus coloring**
Your target and focus get their own colors, borders and edge markers, ranked just under threat. On by default, at half opacity over diagonal stripes so your health color still shows through.

**Zone-Gated rule conditions**
Allows you to pick and choose the content types that your rules will start coloring plates.

**One rule list**
Bar rules and border rules were two separate lists with two separate priorities. They're now one list, with threat and target/focus pinned above it, so "what colors this plate" has one answer you can read top to bottom. Your old border rules fold in automatically on first load, and the old list is kept as a backup in your profile.

**Rules are edited in place**
No more jumping to a separate page. Click Edit and the rule opens inside the list.

**Draw slots**
Nameplate addons only leave so much room to draw in. Every rule now shows what it costs and the list shows how much room is left, so you can see it coming instead of hitting a wall.

**A learned-debuff list**
The addon quietly remembers debuffs it has seen you apply, account-wide, and offers them in the rule editor alongside the Cooldown Manager — so procs, trinkets and anything a patch added are there without you hunting for spell IDs. `/pt learned` shows the list, `/pt forget <id>` drops one.

**Also**
A color picker of the addon's own, with proper opacity control and live previews. A "What Colors This Plate" strip showing the resolution order with live counts. Section help moved into a `?` on each header. Plus a pile of fixes.

## 1.11.1

**"Hide Blizzard's own aura icons" now works.** It was looking for Blizzard's aura row under names this client doesn't use, so it never found anything to hide. It also only ran on hostile plates, and only once when the plate appeared — so anything Blizzard re-showed stayed showing. Grab 1.11.1 if you use that option.
