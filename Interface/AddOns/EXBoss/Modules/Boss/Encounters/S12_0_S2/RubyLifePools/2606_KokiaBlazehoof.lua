---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 2606,
    dungeon = { key = "ruby_life_pools", name = "Ruby Life Pools", zhCN = "红玉新生法池" },
    boss = { key = "kokia_blazehoof", name = "Kokia Blazehoof", zhCN = "柯姬雅·焰蹄" },
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})
