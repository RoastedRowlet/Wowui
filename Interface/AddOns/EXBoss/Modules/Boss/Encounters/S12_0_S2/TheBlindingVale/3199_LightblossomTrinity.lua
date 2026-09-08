---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 3199,
    dungeon = { key = "the_blinding_vale", name = "The Blinding Vale", zhCN = "夺目谷" },
    boss = { key = "lightblossom_trinity", name = "Lightblossom Trinity", zhCN = "光明众花" },
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})
