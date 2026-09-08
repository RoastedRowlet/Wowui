---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 3200,
    dungeon = { key = "the_blinding_vale", name = "The Blinding Vale", zhCN = "夺目谷" },
    boss = { key = "ikuzz_the_light_hunter", name = "Ikuzz the Light Hunter", zhCN = "圣光猎手伊库兹" },
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})
