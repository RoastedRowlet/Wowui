PlateTweaks
Version 1.9.3  ·  World of Warcraft 12.1 (Midnight)

Colors enemy nameplate health bars and borders based on which of your own
debuffs are active on them -- or missing from them.


INSTALL
-------
Extract the PlateTweaks folder into:

    World of Warcraft\_retail_\Interface\AddOns\

You should end up with ...\Interface\AddOns\PlateTweaks\PlateTweaks.toc

Restart the game, or type /reload if it is already running.


GETTING STARTED
---------------
Type  /pt  to open the settings window.

    1. Health Coloring -> Color Rules -> New Rule
    2. Add a debuff from the dropdown, or type its name
    3. Click the color swatch and pick something you will notice

Use the Test buttons at the top of either coloring page to see your colors on
real nameplates without needing the debuffs up. Test mode draws its own
copies, so it shows your exact colors, thickness and geometry at real size --
but it cannot tell you whether a rule would actually MATCH. A wrong spell ID
looks perfect in test mode.

The settings window will not open in combat. Opening it rebuilds secure aura
containers, which the game refuses mid-fight.


MODULES
-------
Health Coloring   tints the health bar
Border Coloring   draws a colored border, with its own separate rules
Aura Icons        an optional row of icons; off by default
Missing Debuffs   a reminder icon that displaces when it lands; off by default
Optional Tweaks   small conveniences unrelated to nameplates; off by default

Under Setup you will also find Profiles, Import / Export, Help and
Diagnostics.

Each is enabled independently from the switch beside its heading in the left
rail. The window header lists which are currently on.

Optional Tweaks currently holds Tooltip IDs, which appends the numeric ID to
spell, aura, item and creature tooltips. That is worth having here because a
rule needs the ID of the aura that LANDS, which is frequently not the ID of
the spell you cast -- hovering the debuff on a target is the most direct way
to read it.


RULES
-----
A rule is a color plus the debuffs that must ALL be on the unit for it to
show. Up to four debuffs per rule. Rules are ordered and the first match
wins; Health and Border rules keep entirely separate priority stacks.

Each rule has two panels:

    Edit Conditions          its debuffs
    Edit Color/Appearance    everything about how it looks

Appearance covers the color, whether the rule may paint your own target and
focus plates, and the fill:

    Solid Overlay      a flat color, or any bar texture you have installed
                       (LibSharedMedia -- SharedMedia, ElvUI, WeakAuras and
                       Plater all register into the same table)
    Texture Overlay    tiles a pattern from the built-in library over the
                       fill at a fixed size

A Texture Overlay can visually clash with target/focus highlight art some
nameplate addons already draw over the health bar -- the appearance panel
warns about this when it applies.

Cover missing health is a per-rule option in the same panel. It paints the
empty part of the bar -- health the unit has already lost -- in one opaque
color, so the rule's coloring reads clearly no matter what your nameplate
addon draws there. Because it is opaque it will also cover other addons'
overlays on that side of the bar, which is the point, but worth knowing
before you turn it on. Its color and opacity are shared by every rule that
uses it, and the swatch appears at the bottom of the rule list once at least
one rule has the option enabled.

Note: rules of three and four debuffs are lightly tested. If one misbehaves
the symptom to expect is INTERMITTENT firing rather than an error -- watch
for a rule that works right after /reload and stops later.


MISSING-DEBUFF RULES
--------------------
A rule can be inverted to wash the bar in its color while its debuff is
ABSENT, which turns it into a reminder that something needs reapplying.
Toggled in the rule's own panel.

These are single-debuff by construction and that cannot be raised. The
option is not offered on a rule that already has two.

Several missing rules can coexist and stack normally against each other.

There is also a combat-only option, which holds the wash off while the unit
is out of combat -- so an untouched reminder does not light up every mob
standing around before a pull. It is off by default, because some missing
rules are exactly for a pre-pull buff check, where out of combat is
precisely when you want the reminder.

The option is ticked on a rule, but it applies to all of your missing rules
together, and only takes effect once every one of them has it ticked. That
is not a simplification: only one missing wash is ever lit at a time, and
which one depends on aura state the game does not let an addon read, so the
choice genuinely cannot be made per rule. The settings panel says so when
you have it ticked on some but not all.

There are two ways the addon can take a lit wash away once the debuff
lands, and you can pick between them:

    /pt missingmode displace   (default) the wash rides a mask that is
                               shoved off screen
    /pt missingmode occlude    the wash is covered by an opaque replica of
                               the bar

Displacement is the default even though it costs more -- a ten-button pool
per rule where occlusion costs one slot -- because it is the only one that
leaves your bar alone. Occlusion's cover repaints the whole bar, so
whatever your nameplate addon was encoding there (threat, mob-tier colors,
execute range) is gone for as long as the debuff is up, which is most of
the time. Displacement paints nothing in that state, so all of it survives.

If you switch to occlusion, "Color by mob rank once applied" on the Health
Coloring page claws some of that back: instead of restoring the bar's own
art, the cover is painted a flat color chosen by the mob's tier. That
option exists only in occlusion mode -- displacement has no cover to color,
because it never covers anything.

BORDER rules can be inverted too, and they need displacement specifically.
Taking a lit reminder away means one of two things -- covering it with a
copy of whatever was underneath, or sliding it off screen. Only the second
works for a border. The addon can replicate the health bar's own art well
enough to cover a wash, but it cannot replicate whatever your nameplate
addon drew beneath the border band, so there is no cover to build there.

In occlusion mode a missing border rule is not built at all, and /pt status
says how many were skipped rather than leaving you with a rule in the
options window that quietly does nothing. Two missing border rules is the
cap -- the sublevels immediately under the border band are all there are to
give, and everything below them belongs to the bar ladder.

/pt perf counts displacement's real cost honestly, so you can see what it
is spending on your setup before deciding. Combat-only, on the other hand,
is genuinely per rule in displacement mode -- the all-or-nothing limitation
described above is a property of the occlusion ladder, not of the feature.


MISSING DEBUFFS (ICON)
-----------------------
A different reminder from the missing-debuff wash above. Instead of tinting
the bar, an icon sits near the nameplate and gets pushed off it the instant
the tracked debuff lands, then slides back once it drops. Its own module,
off by default, and independent of everything above -- either can be used
without the other.

Each tracked debuff is its own entry and can be set to show its spell icon
or a flat color, and can have its own combat-only option -- unlike the wash's
version of that option, this one is genuinely per debuff, since each icon
here does not share state with the others.

With several debuffs tracked, Collapse (on by default) slides later icons
toward the anchor as earlier ones land, instead of leaving a gap. It turns
itself off past 4 tracked debuffs -- collapsing costs real per-debuff frames,
and that stops being worth it beyond a handful.


PANDEMIC FLASH
--------------
An optional highlight, on its own page under Health Coloring, revealed
inside an aura's refresh window. Nothing is timed or polled on this addon's
side -- the game's own aura engine owns when it shows. It costs one extra
texture per built combination, so it is opt-in.


PROFILES
--------
Profiles are named, account-wide and shareable. A character points AT a
profile rather than owning one, so two characters can share a setup, and one
character can keep a different setup per spec.

    Setup -> Profiles

Resolution is: this spec's binding, else this character's default, else
"Default". Binding a spec is what "link this profile to a spec" means --
switch spec and the profile follows, with no separate scope switch to
remember.

A new character starts blank rather than inheriting. Rules name specific
spell IDs, so an inherited set is mostly rules that can never fire.


IMPORT / EXPORT
---------------
    Setup -> Import / Export

Settings are saved per account, so a text string is the only way a profile
reaches a different one.

Export picks a profile and produces a string. Select it, press Ctrl+C. The
string is a snapshot, not a link -- change a rule afterwards and you need a
new one.

Import is three steps on purpose: paste, Check, Import. Check only decodes.
It shows you the profile's name, its rules with their icons, which modules
it turns on, and how big it is, all before anything is written. Nothing
touches your settings until you press Import, and importing onto a name that
already exists asks first.

Rules name exact spell IDs, so a profile built on one class is inert on
another -- it does not error, it simply never matches, which is the most
confusing way for an import to go wrong. The preview therefore marks any
rule naming a debuff your current character cannot apply with an orange "!".
Those rules still import intact and still work on a character that can apply
them; the mark is a warning, not a refusal.

Two things do not travel with a profile: which characters and specs were
assigned to it, and window position and layout. Both describe the sender's
account rather than the profile.


COMPATIBILITY
-------------
Works with Blizzard's default nameplates and with other nameplate addons
(EllesmereUI, Plater, Platynator, NDui and others). It draws on whatever health bar
it finds rather than replacing your plates.

If your nameplate addon already shows aura icons, leave the Aura Icons module
off so you do not get two rows.


PERFORMANCE
-----------
Rules are cheap as of 1.5.

The addon is never told which auras are on a unit -- 12.1 forbids reading
that -- so its visuals hang off the game's own secure aura frames, which are
shown only while the aura is actually present. Older versions had to use a
pooled container that created ten frames per debuff, so a two-debuff rule
cost around a hundred textures on every nameplate. That is where this
addon's cost used to come from, and it is gone: a rule now builds a single
chain, costing one container per debuff and about one texture for its tint,
however many debuffs it has.

    Any rule, 1-4 debuffs     ~1 container per debuff, ~1 tint texture

Extra textures come from options rather than from debuff count: an underlay
where one rule has to mask another, a bar replica for Cover missing health
or for a missing rule, and one for Pandemic Flash.

If you are on a client that does not offer the aura-slot API, the addon
falls back to the older pooled path automatically, and the old per-debuff
multiplication applies again. /pt perf reports what is actually built.

Missing Debuffs (the displacing icon, not the wash) is the one exception to
all of the above: displacement only works on the older pooled container, so
it always pays that cost regardless of the aura-slot API, and Collapse adds
more of it per debuff before the one collapsing. That is why it is capped at
4 tracked debuffs for collapsing -- see MISSING DEBUFF (ICON) above.


TROUBLESHOOTING
---------------
    /pt status

Prints what the addon has actually built on the nameplates in front of you.
Unlike the settings window it works in combat and inside a dungeon, which is
where problems tend to appear. Include its output in any bug report.

    /pt perf

Prints what the addon is costing right now, and projects that to a full pull
(40 nameplates). Textures and secure frames are the real cost, not CPU time,
which is why this counts those instead.

    /pt bar

For "the settings look right but this particular nameplate is not colored".
Reports what the addon found on your current target specifically: the health
bar it is drawing on, and whether each of that rule's textures is actually
visible. Useful when /pt status looks healthy but one plate does not.

    /pt capture

The one to use for a bug report. Runs status, bar, adapter and layers all at
once and stores the result in SavedVariables instead of chat, along with which
nameplate addon you have loaded, your class and spec, and whether you were in
an instance. Target a mob first, or the parts that need one come out empty.

Works in combat, which matters: the settings window refuses to open in a
dungeon, and a capture taken mid-pull is the useful one. Take it while the
problem is happening, then read it back afterwards in

    /pt  >  Diagnostics  >  Saved captures

Pick one from the dropdown and it fills the box ready to select and Ctrl+C.
With more than one stored there is an "All captures" entry that loads every
run at once, so a whole test session copies in one go.
Captures are kept, not overwritten, and they survive to the next session, so
the one you took in a key is still there tomorrow. The last 25 are held.

/pt capture list shows what is stored, /pt capture clear empties it, and
/pt capture <name> labels a run -- useful when comparing the same setup across
nameplate addons.

The Full Report button on that page does the same thing for the plate you are
targeting right now, and saves it too.

If you cannot open the window at all, the same text is in

    WTF\Account\<your account>\SavedVariables\PlateTweaks.lua

though nothing is written there until you reload or log out.

    /pt layers

For "colouring does not work with <my nameplate addon>". Reports where that
addon draws on the health bar, and where this addon draws, as frame levels
and draw sublevels side by side. Needs a target. This is the one to paste if
colours are simply not appearing on a plate the addon says it has rigged.

    /pt adapter

Four settings describe your nameplate addon's bars rather than your taste:
how far above the bar to draw, whether to elevate at all, how far the host's
border reaches inside, and the gap between its bar frame and its fill. These
are stored per nameplate addon, so the shipped values are simply correct for
Plater and Blizzard's plates and you never need to look.

If yours needs a nudge, /pt adapter shows what is in use on the plate you are
targeting and where each value came from. To change one:

    /pt adapter edgeadjust 2
    /pt adapter leveloffset 3
    /pt adapter outlineoffset -1
    /pt adapter pinflat on
    /pt adapter reset

Any of them takes "auto" to go back to inheriting. Changes apply only to the
nameplate addon you are currently using, so switching addons cannot inherit
someone else's workaround.

    /pt pinflat on | off | auto

Shorthand for /pt adapter pinflat. Changes how rules are stacked against the
host's own artwork. On draws every rule at the bar's own frame level and
separates them by draw sublevel instead. Try it if /pt layers shows the host
drawing above the rule levels, or if colours cover the host's name text.


HELP
----
Discord:  https://discord.gg/cdKSgKyCVJ

This addon is early and changing quickly. Bug reports and suggestions welcome.


CREDITS
-------
Font: Expressway, included in media/fonts.
Libraries: LibStub, CallbackHandler-1.0, LibSharedMedia-3.0.
Textures: some Texture Overlay patterns (media/textures) used from
EllesmereUI.
