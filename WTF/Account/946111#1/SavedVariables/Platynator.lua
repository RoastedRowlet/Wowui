
PLATYNATOR_CONFIG = {
["Version"] = 1,
["CharacterSpecific"] = {
},
["Profiles"] = {
["DEFAULT"] = {
["stack_region_scale_y"] = 1.4,
["design_all"] = {
},
["cast_alpha"] = 1,
["mouseover_alpha"] = 1,
["closer_to_screen_edges"] = true,
["obscured_alpha"] = 0.4,
["cast_scale"] = 1.1,
["simplified_nameplates"] = {
["minor"] = true,
["minion"] = true,
["instancesNormal"] = true,
},
["stacking_nameplates"] = {
["friend"] = false,
["enemy"] = true,
},
["designs_assigned"] = {
["enemySimplifiedCombat"] = "_custom",
["enemyPvPPlayer"] = "_deer",
["enemy"] = "_custom",
["friendCombat"] = "_custom",
["friendPvPPlayer"] = "_name-only",
["friend"] = "_custom",
["enemySimplified"] = "_custom",
["enemyCombat"] = "_custom",
},
["designs_enabled"] = {
["pvpInstance"] = false,
["combat"] = false,
["pvpWorld"] = false,
},
["target_scale"] = 1.2,
["blizzard_widget_scale"] = 1.2,
["show_friendly_in_instances_1"] = "always",
["click_region_scale_x"] = 1,
["show_nameplates_only_needed"] = false,
["apply_cvars"] = true,
["current_skin"] = "blizzard",
["stack_region_scale_x"] = 1.2,
["global_scale"] = 1,
["designs"] = {
["_custom"] = {
["highlights"] = {
{
["scale"] = 1,
["layer"] = 0,
["asset"] = "Platy: Arrow Solid",
["width"] = 1.23,
["kind"] = "target",
["anchor"] = {
},
["sliced"] = true,
["height"] = 1.22,
["color"] = {
["a"] = 1,
["r"] = 1,
["g"] = 1,
["b"] = 1,
},
},
{
["color"] = {
["a"] = 1,
["r"] = 0.6941176652908325,
["g"] = 0.3725490272045136,
["b"] = 0.9215686917304992,
},
["layer"] = 0,
["asset"] = "Platy: Blizzard Cast Bar",
["width"] = 1.03,
["scale"] = 0.99,
["kind"] = "mouseover",
["anchor"] = {
},
["sliced"] = true,
["height"] = 1.24,
["includeTarget"] = true,
},
},
["specialBars"] = {
},
["scale"] = 1.53,
["auras"] = {
{
["direction"] = "LEFT",
["scale"] = 1,
["showCountdown"] = true,
["sorting"] = {
["reversed"] = false,
["kind"] = "duration",
},
["showPandemic"] = true,
["showDispel"] = {
},
["height"] = 1,
["anchor"] = {
"BOTTOMRIGHT",
55.5,
11,
},
["kind"] = "debuffs",
["textScale"] = 1,
["filters"] = {
["fromYou"] = true,
["important"] = true,
},
},
{
["direction"] = "LEFT",
["scale"] = 1,
["showCountdown"] = true,
["sorting"] = {
["reversed"] = false,
["kind"] = "duration",
},
["textScale"] = 1,
["showDispel"] = {
["enrage"] = true,
},
["height"] = 1,
["kind"] = "buffs",
["anchor"] = {
"LEFT",
-96.5,
0,
},
["filters"] = {
["dispelable"] = false,
["important"] = true,
["defensive"] = false,
},
},
{
["direction"] = "RIGHT",
["scale"] = 1,
["showCountdown"] = true,
["sorting"] = {
["reversed"] = false,
["kind"] = "duration",
},
["anchor"] = {
"RIGHT",
96.5,
0,
},
["showDispel"] = {
},
["height"] = 1,
["kind"] = "crowdControl",
["textScale"] = 1,
["filters"] = {
["fromYou"] = false,
},
},
},
["font"] = {
["outline"] = true,
["shadow"] = true,
["asset"] = "RobotoCondensed-Bold",
["slug"] = true,
},
["version"] = 1,
["bars"] = {
{
["absorb"] = {
["color"] = {
["a"] = 1,
["b"] = 1,
["g"] = 1,
["r"] = 1,
},
["asset"] = "Platy: Absorb Wide",
},
["animate"] = false,
["marker"] = {
["asset"] = "wide/glow",
},
["layer"] = 1,
["border"] = {
["color"] = {
["a"] = 1,
["r"] = 0,
["g"] = 0,
["b"] = 0,
},
["height"] = 1,
["asset"] = "Platy: Blizzard Cast Bar",
["width"] = 1,
},
["autoColors"] = {
{
["colors"] = {
},
["kind"] = "classColors",
},
{
["colors"] = {
["tapped"] = {
["r"] = 0.4313725490196079,
["g"] = 0.4313725490196079,
["b"] = 0.4313725490196079,
},
},
["kind"] = "tapped",
},
{
["combatOnly"] = false,
["colors"] = {
["transition"] = {
["r"] = 1,
["g"] = 0.6274509803921569,
["b"] = 0,
},
["warning"] = {
["r"] = 0.8,
["g"] = 0,
["b"] = 0,
},
["safe"] = {
["r"] = 0.05882352941176471,
["g"] = 0.5882352941176471,
["b"] = 0.9019607843137256,
},
["offtank"] = {
["r"] = 0.05882352941176471,
["g"] = 0.6666666666666666,
["b"] = 0.7843137254901961,
},
},
["kind"] = "threat",
["useSafeColor"] = true,
["instancesOnly"] = false,
},
{
["colors"] = {
["neutral"] = {
["r"] = 1,
["g"] = 1,
["b"] = 0,
},
["friendly"] = {
["r"] = 0,
["g"] = 1,
["b"] = 0,
},
["hostile"] = {
["r"] = 1,
["g"] = 0,
["b"] = 0,
},
["unfriendly"] = {
["b"] = 0,
["g"] = 0.5058823529411764,
["r"] = 1,
},
},
["kind"] = "reaction",
},
},
["scale"] = 1,
["kind"] = "health",
["anchor"] = {
},
["background"] = {
["color"] = {
["a"] = 1,
["b"] = 1,
["g"] = 1,
["r"] = 1,
},
["applyColor"] = true,
["asset"] = "Platy: Solid Grey",
},
["foreground"] = {
["asset"] = "Platy: Fade Bottom",
},
["relativeTo"] = 0,
},
{
["scale"] = 1,
["layer"] = 1,
["border"] = {
["color"] = {
["a"] = 1,
["r"] = 0,
["g"] = 0,
["b"] = 0,
},
["height"] = 1,
["asset"] = "Platy: Blizzard Cast Bar",
["width"] = 1,
},
["autoColors"] = {
{
["colors"] = {
["cast"] = {
["b"] = 0.1529411764705883,
["g"] = 0.09411764705882353,
["r"] = 1,
},
["channel"] = {
["b"] = 1,
["g"] = 0.2627450980392157,
["r"] = 0.0392156862745098,
},
},
["kind"] = "importantCast",
},
{
["colors"] = {
["uninterruptable"] = {
["r"] = 0.5137254901960784,
["g"] = 0.7529411764705882,
["b"] = 0.7647058823529411,
},
},
["kind"] = "uninterruptableCast",
},
{
["colors"] = {
["cast"] = {
["r"] = 0.9882352941176472,
["g"] = 0.5490196078431373,
["b"] = 0,
},
["interrupted"] = {
["r"] = 0.9882352941176472,
["g"] = 0.211764705882353,
["b"] = 0.8784313725490196,
},
["channel"] = {
["b"] = 0.2156862745098039,
["g"] = 0.7764705882352941,
["r"] = 0.2431372549019608,
},
},
["kind"] = "cast",
},
},
["marker"] = {
["asset"] = "wide/glow",
},
["kind"] = "cast",
["foreground"] = {
["asset"] = "Platy: Fade Bottom",
},
["background"] = {
["color"] = {
["a"] = 1,
["b"] = 1,
["g"] = 1,
["r"] = 1,
},
["applyColor"] = true,
["asset"] = "Platy: Solid Grey",
},
["anchor"] = {
"TOP",
0,
-9,
},
["interruptMarker"] = {
["asset"] = "none",
["color"] = {
["b"] = 1,
["g"] = 1,
["r"] = 1,
},
},
},
},
["markers"] = {
{
["layer"] = 3,
["color"] = {
["r"] = 1,
["g"] = 1,
["b"] = 1,
},
["scale"] = 0.8,
["kind"] = "quest",
["asset"] = "normal/quest-blizzard",
["anchor"] = {
"BOTTOM",
0,
10,
},
},
{
["layer"] = 3,
["color"] = {
["r"] = 0.3921568627450981,
["g"] = 0.4823529411764706,
["b"] = 0.4980392156862745,
},
["scale"] = 0.5,
["kind"] = "cannotInterrupt",
["asset"] = "normal/shield-soft",
["anchor"] = {
"TOPLEFT",
-70,
-9,
},
},
{
["openWorldOnly"] = true,
["anchor"] = {
"BOTTOMLEFT",
-59,
9.5,
},
["layer"] = 3,
["color"] = {
["r"] = 1,
["g"] = 1,
["b"] = 1,
},
["kind"] = "elite",
["asset"] = "special/blizzard-elite-midnight",
["scale"] = 0.8,
},
{
["layer"] = 3,
["color"] = {
["r"] = 1,
["g"] = 1,
["b"] = 1,
},
["scale"] = 0.75,
["kind"] = "raid",
["asset"] = "normal/blizzard-raid",
["anchor"] = {
"RIGHT",
27.5,
0,
},
},
},
["texts"] = {
{
["displayTypes"] = {
"absolute",
},
["color"] = {
["r"] = 1,
["g"] = 1,
["b"] = 1,
},
["layer"] = 2,
["maxWidth"] = 0,
["significantFigures"] = 0,
["scale"] = 0.98,
["anchor"] = {
"RIGHT",
58.5,
0,
},
["kind"] = "health",
["truncate"] = false,
["align"] = "CENTER",
},
{
["showWhenWowDoes"] = false,
["truncate"] = true,
["color"] = {
["r"] = 1,
["g"] = 1,
["b"] = 1,
},
["layer"] = 2,
["maxWidth"] = 0.71,
["autoColors"] = {
},
["anchor"] = {
"LEFT",
-58,
0,
},
["kind"] = "creatureName",
["align"] = "LEFT",
["scale"] = 1.1,
},
{
["scale"] = 1,
["anchor"] = {
"TOPLEFT",
-57.5,
-7.5,
},
["layer"] = 2,
["truncate"] = true,
["color"] = {
["r"] = 1,
["g"] = 1,
["b"] = 1,
},
["kind"] = "castSpellName",
["align"] = "LEFT",
["maxWidth"] = 0.86,
},
},
},
},
["style"] = "_custom",
["click_region_scale_y"] = 1,
["not_target_alpha"] = 1,
["clickable_nameplates"] = {
["friend"] = false,
["enemy"] = true,
},
["show_nameplates"] = {
["friendlyMinion"] = false,
["enemyMinor"] = true,
["friendlyPlayer"] = true,
["friendlyNPC"] = true,
["enemyMinion"] = true,
["enemy"] = true,
},
["simplified_scale"] = 0.58,
},
},
}
