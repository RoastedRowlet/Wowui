--[[
	PI Helper constants and saved-variable defaults.
]]

local ADDON_NAME, addon = ...

addon.VERSION = "1.7.0"
addon.PI_SPELL_ID = 10060
addon.GROUP_KEY = "pihelper"

-- Healer specializations. Shadow priest is 258.
addon.HEALER_SPEC_IDS = {
	[65] = true,   -- Paladin Holy
	[105] = true,  -- Druid Restoration
	[256] = true,  -- Priest Discipline
	[257] = true,  -- Priest Holy
	[264] = true,  -- Shaman Restoration
	[270] = true,  -- Monk Mistweaver
	[1468] = true, -- Evoker Preservation
}

addon.CLASS_ORDER = {
	"Death Knight",
	"Demon Hunter",
	"Druid",
	"Evoker",
	"Hunter",
	"Mage",
	"Monk",
	"Paladin",
	"Priest",
	"Rogue",
	"Shaman",
	"Warlock",
	"Warrior",
	"Potion",
	"Custom",
}

addon.DEFAULT_SPELLS = {
	{ spellID = 51271,   name = "Pillar of Frost",              class = "Death Knight" },
	{ spellID = 42650,   name = "Army of the Dead",             class = "Death Knight" },
	{ spellID = 162264,  name = "Metamorphosis",                class = "Demon Hunter" },
	{ spellID = 1217607, name = "Void Metamorphosis",           class = "Demon Hunter" },
	{ spellID = 102560,  name = "Incarnation: Chosen of Elune", class = "Druid" },
	{ spellID = 194223,  name = "Celestial Alignment",          class = "Druid" },
	{ spellID = 106951,  name = "Berserk",                      class = "Druid" },
	{ spellID = 375087,  name = "Dragonrage",                   class = "Evoker" },
	{ spellID = 19574,   name = "Bestial Wrath",                class = "Hunter" },
	{ spellID = 288613,  name = "Trueshot",                     class = "Hunter" },
	{ spellID = 1250646, name = "Takedown",                     class = "Hunter" },
	{ spellID = 365362,  name = "Arcane Surge",                 class = "Mage" },
	{ spellID = 190319,  name = "Combustion",                    class = "Mage" },
	{ spellID = 1247908, name = "Splinterstorm",                class = "Mage" },
	{ spellID = 1249625, name = "Zenith",                       class = "Monk" },
	{ spellID = 1248992, name = "Celestial Conduit (Invoke Xuen, the White Tiger)", label = "Celestial Conduit (Invoke Xuen, the White Tiger)", class = "Monk" },
	{ spellID = 31884,   name = "Avenging Wrath",               class = "Paladin" },
	{ spellID = 194249,  name = "Voidform",                     class = "Priest" },
	{ spellID = 1249810, name = "Finish the Job (Deathmark)", label = "Finish the Job (Deathmark)", class = "Rogue" },
	{ spellID = 121471,  name = "Shadow Blades",                class = "Rogue" },
	{ spellID = 13750,   name = "Adrenaline Rush",              class = "Rogue" },
	{ spellID = 1219480, name = "Ascendance (Elemental)",       label = "Ascendance (Elemental)",    class = "Shaman" },
	{ spellID = 114051,  name = "Ascendance (Enhancement)",     label = "Ascendance (Enhancement)",  class = "Shaman" },
	{ spellID = 1276166, name = "Dominion of Argus (Summon Demonic Tyrant)", label = "Dominion of Argus (Summon Demonic Tyrant)", class = "Warlock" },
	{ spellID = 266087,  name = "Rain of Chaos (Summon Infernal)", label = "Rain of Chaos (Summon Infernal)", class = "Warlock" },
	{ spellID = 417282,  name = "Crashing Chaos (Summon Infernal)", label = "Crashing Chaos (Summon Infernal)", class = "Warlock" },
	{ spellID = 107574,  name = "Avatar",                       class = "Warrior" },
	{ spellID = 1719,    name = "Recklessness",                 class = "Warrior" },
	{ spellID = 1236994, name = "Potion of Recklessness",       class = "Potion", isPotion = true },
	{ spellID = 1236616, name = "Light's Potential",            class = "Potion", isPotion = true },
}

addon.SOUND_PRESETS = {
	{ key = "ALARM_CLOCK_WARNING_3", id = 12889, name = "Bell", fileID = 567458, path = "Sound\\Interface\\AlarmClockWarning3.ogg" },
}

addon.SOUND_CHANNELS = {
	"Master",
	"SFX",
	"Ambience",
	"Music",
	"Dialog",
}

addon.GLOW_STYLES = {
	{ id = "pixel",     name = "Pixel",     tooltip = "Marching dashes around the raid frame." },
	{ id = "starburst", name = "Proc",      tooltip = "Starburst flash on the raid frame." },
	{ id = "border",    name = "Border",    tooltip = "Solid outline around the raid frame." },
	{ id = "countdown", name = "Countdown", tooltip = "Bar on the raid frame that shrinks as the buff runs out." },
	{ id = "fill",      name = "Fill",      tooltip = "Tints the whole raid frame." },
}

addon.ALERT_GLOW_STYLES = {
	{ id = "starburst", name = "Proc", tooltip = "Starburst flash on the on-screen alert." },
	{ id = "none",      name = "None", tooltip = "No glow on the on-screen alert." },
}

addon.WHISPER_MODES = {
	{ id = "listed",   name = "Priority",  tooltip = "Any whisper highlights the first listed player who is in the group." },
	{ id = "sequence", name = "Rotation", tooltip = "Any whisper highlights the current name. After you PI, move to the next." },
}

addon.TRACK_PLAYER_MODES = {
	{ id = "all",    name = "Everyone", tooltip = "Glow and alert for everyone in the group." },
	{ id = "listed", name = "Listed",   tooltip = "Only glow and alert for the people on your Tracked players list." },
}

addon.ALERT_LAYOUTS = {
	{ id = "overlay", name = "On icon", tooltip = "Player name over the alert icon." },
	{ id = "left",    name = "Left",    tooltip = "Player name to the left of the icon." },
	{ id = "right",   name = "Right",   tooltip = "Player name to the right of the icon." },
	{ id = "none",    name = "None",    tooltip = "Hide the player name on the alert." },
}

addon.DURATION_HOSTS = {
	{ id = "frame", name = "Raid frame", tooltip = "Draw remaining time on the glowing raid or party cell." },
	{ id = "alert", name = "Alert", tooltip = "Draw remaining time on the on-screen alert icon. Use Position if it overlaps the name. Needs Show alert in Tracking." },
	{ id = "both", name = "Both", tooltip = "Draw remaining time on the raid cell and the on-screen alert." },
}

addon.DURATION_ANCHORS = {
	{ id = "topleft",     name = "Top Left" },
	{ id = "top",         name = "Top" },
	{ id = "topright",    name = "Top Right" },
	{ id = "left",        name = "Left" },
	{ id = "center",      name = "Center" },
	{ id = "right",       name = "Right" },
	{ id = "bottomleft",  name = "Bottom Left" },
	{ id = "bottom",      name = "Bottom" },
	{ id = "bottomright", name = "Bottom Right" },
}

addon.COUNTDOWN_ANCHORS = {
	{ id = "top",    name = "Top" },
	{ id = "center", name = "Middle" },
	{ id = "bottom", name = "Bottom" },
}

addon.FONT_PRESETS = {
	{ id = "default",  name = "Arial Narrow",  path = "Fonts\\ARIALN.TTF" },
	{ id = "friz",     name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
	{ id = "skurri",   name = "Skurri",        path = "Fonts\\SKURRI.TTF" },
	{ id = "morpheus", name = "Morpheus",      path = "Fonts\\MORPHEUS.TTF" },
}

addon.DEFAULTS = {
	version = 1,
	enabled = true,
	loadForAllClasses = false,
	healerOnly = true,
	showMinimap = true,
	minimapAngle = 250,
	onlyWhenPIReady = true,
	piGrace = 0,
	watchSelf = false,

	watchRaid = true,
	watchParty = true,
	watchFocus = true,
	trackRaidMode = "all",
	trackPartyMode = "all",
	trackNames = {},
	perBuffScope = false,

	focusRemindEnabled = false,
	focusRemindRaid = true,
	focusRemindDungeon = true,

	raidGlowEnabled = true,
	raidGlowFocus = true,
	glowRaid = true,
	glowParty = true,
	glowFocus = true,
	alertEnabled = true,
	alertTracked = false,
	alertRaid = false,
	alertParty = false,
	alertFocus = true,
	alertWhisper = true,
	alertSource = "all",
	alertLayout = "overlay",
	alertIconSize = 64,
	alertTextSize = 16,
	alertClassColor = false,
	alertGlow = true,
	alertGlowStyle = "starburst",
	alertGlowR = 234 / 255,
	alertGlowG = 162 / 255,
	alertGlowB = 33 / 255,
	alertGlowA = 0.90,
	alertX = 0,
	alertY = 180,
	alertLocked = false,

	glowStyle = "pixel",
	glowR = 234 / 255,
	glowG = 162 / 255,
	glowB = 33 / 255,
	glowA = 0.90,
	glowSpeed = 1.5,
	glowThickness = 2,
	glowBorderPulse = true,
	glowPixelLines = 10,
	glowPixelLength = 20,
	countdownAnchor = "top",
	countdownX = 0,
	countdownY = 0,
	countdownHeight = 0,

	durationRaid = false,
	durationParty = false,
	durationHost = "frame",
	durationAnchor = "center",
	durationX = 0,
	durationY = 0,
	durationFont = "default",
	durationSize = 12,
	durationR = 1,
	durationG = 1,
	durationB = 1,
	durationA = 1,

	whisperEnabled = true,
	whisperRaidOnly = false,
	whisperIgnoreBnet = true,
	whisperAlertEnabled = true,
	whisperRaidGlow = true,
	whisperMode = "listed",
	whisperSequence = false,
	whisperCycle = true,
	whisperNames = {},
	sequenceNames = {},

	focusSound = true,
	raidSound = false,
	partySound = false,
	whisperSound = true,
	soundName = "ALARM_CLOCK_WARNING_3",
	soundKitID = 12889,
	soundChannel = "Master",

	spellEnabled = {},
	spellScope = {},
	customSpells = {},
	trackingCollapsed = {},
	cooldownCollapsed = {},

	optionsScale = 100,
}

addon.CLASS_COLORS = {
	["Death Knight"] = { 0.77, 0.12, 0.23 },
	["Demon Hunter"] = { 0.64, 0.19, 0.79 },
	["Druid"]        = { 1.00, 0.49, 0.04 },
	["Evoker"]       = { 0.20, 0.58, 0.50 },
	["Hunter"]       = { 0.67, 0.83, 0.45 },
	["Mage"]         = { 0.25, 0.78, 0.92 },
	["Monk"]         = { 0.00, 1.00, 0.60 },
	["Paladin"]      = { 0.96, 0.55, 0.73 },
	["Priest"]       = { 0.90, 0.91, 0.92 },
	["Rogue"]        = { 1.00, 0.96, 0.41 },
	["Shaman"]       = { 0.00, 0.44, 0.87 },
	["Warlock"]      = { 0.53, 0.53, 0.93 },
	["Warrior"]      = { 0.78, 0.61, 0.43 },
	["Potion"]       = { 234 / 255, 162 / 255, 33 / 255 },
	["Custom"]       = { 0.70, 0.72, 0.74 },
}

addon.C = {
	bg           = { 0.10, 0.11, 0.12, 0.98 },
	panel        = { 0.08, 0.09, 0.10, 1 },
	border       = { 0.24, 0.28, 0.30, 1 },
	windowBorder = { 0.50, 0.35, 0.10, 1 },
	accent       = { 234 / 255, 162 / 255, 33 / 255, 1 },
	gold         = { 234 / 255, 162 / 255, 33 / 255, 1 },
	text         = { 0.90, 0.91, 0.92, 1 },
	textMuted    = { 0.55, 0.58, 0.60, 1 },
	textAccent   = { 0.95, 0.78, 0.48, 1 },
	danger       = { 0.86, 0.36, 0.38, 1 },
}

addon.FONT = "Fonts\\ARIALN.TTF"
