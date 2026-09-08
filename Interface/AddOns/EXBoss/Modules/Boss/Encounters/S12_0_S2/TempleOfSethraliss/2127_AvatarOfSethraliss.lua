---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 2127,
    dungeon = { key = "temple_of_sethraliss", name = "Temple of Sethraliss", zhCN = "塞塔里斯神庙" },
    boss = { key = "avatar_of_sethraliss", name = "Avatar of Sethraliss", zhCN = "塞塔里斯的化身" },
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})
