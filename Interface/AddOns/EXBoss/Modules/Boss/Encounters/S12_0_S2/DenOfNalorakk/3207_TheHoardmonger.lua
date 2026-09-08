---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 3207,
    dungeon = { key = "den_of_nalorakk", name = "Den of Nalorakk", zhCN = "纳洛拉克的洞穴" },
    boss = { key = "the_hoardmonger", name = "The Hoardmonger", zhCN = "囤宝狂人" },
    healthThresholds = {
        { threshold = 90, preset = "phase_transition" },
        { threshold = 70, preset = "phase_transition" },
        { threshold = 40, preset = "phase_transition" },
    },
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})
