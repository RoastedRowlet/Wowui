---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 3208,
    dungeon = { key = "den_of_nalorakk", name = "Den of Nalorakk", zhCN = "纳洛拉克的洞穴" },
    boss = { key = "sentinel_of_winter", name = "Sentinel of Winter", zhCN = "寒冬哨兵" },
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})
