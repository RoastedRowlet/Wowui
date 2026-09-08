--------------------------------------------------------------------------------
-- Module Declaration
--

local mod, CL = BigWigs:NewBoss("The Blinding Vale Trash", 2859)
if not mod then return end
mod:SetTrashModule(true)

--------------------------------------------------------------------------------
-- Auras
--

mod:SetAuraData({
	{1238084, header = 245410, duration = 16, dispel = "magic", soundOnAppliedDose = "none", note = CL.debuffTankAfterCastNote:format(mod:SpellName(1238084))}, -- Spore Spines (Lasher)
	{1237858, header = 245346, soundOnApplied = "underyou", note = CL.debuffUnderYouNote}, -- Ruptured Earth (Virid Grovekeeper)
	{1238076, header = 245339, duration = 8, dispel = "bleed", mechanic = "bleeding", note = CL.debuffDotAfterCastNote:format(mod:SpellName(1238066))}, -- Thornblade (Underbrush Stalker)
	{1242135, header = 246871, duration = 16, dispel = "bleed", soundOnAppliedDose = "none", note = CL.debuffTankAfterCastNote:format(mod:SpellName(1242135))}, -- Grievous Gash (Luminous Thornmaw)
	{1251345, header = mod:SpellName(1251345), soundOnApplied = "underyou", note = CL.debuffUnderYouNote}, -- Blight Resin (environmental)
	{1250937, header = 249756, duration = 9, dispel = "poison", note = CL.debuffGroupAfterCastNote:format(mod:SpellName(1250937))}, -- Toxic Spew (Potatoad Matriarch)
	{1238294, header = 245484, duration = 3, mechanic = "disoriented", note = CL.debuffFailureInterruptNote:format(mod:SpellName(1238294))}, -- Disorienting Screech (Lightfeather Petalwing)
	{1238368, header = 245513, duration = 6, soundOnApplied = "alarm", note = CL.debuffPossibleAfterCastNote:format(mod:SpellName(1238368))}, -- Lightmaw Beams (Overgrown Hydra)
})

--------------------------------------------------------------------------------
-- Initialization
--

function mod:GetOptions()
	return {
		-- TODO there is an autotalk in here (Light-Starved Blossom)
	}
end
