---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 3201,
    dungeon = { key = "the_blinding_vale", name = "The Blinding Vale", zhCN = "夺目谷" },
    boss = { key = "lightwarden_ruia", name = "Lightwarden Ruia", zhCN = "护光者鲁伊亚" },
    healthThresholds = {
        { threshold = 70, preset = "phase_transition" },
        { threshold = 40, preset = "phase_transition" },
    },
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})
