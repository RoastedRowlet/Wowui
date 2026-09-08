---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 3202,
    dungeon = { key = "the_blinding_vale", name = "The Blinding Vale", zhCN = "夺目谷" },
    boss = { key = "ziekett", name = "Ziekett", zhCN = "兹欧凯特" },
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})
