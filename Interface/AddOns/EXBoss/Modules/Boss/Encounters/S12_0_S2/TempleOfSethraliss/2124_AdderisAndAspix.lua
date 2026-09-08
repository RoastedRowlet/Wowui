---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 2124,
    dungeon = { key = "temple_of_sethraliss", name = "Temple of Sethraliss", zhCN = "塞塔里斯神庙" },
    boss = { key = "adderis_and_aspix", name = "Adderis and Aspix", zhCN = "阿德里斯和阿斯匹克斯" },
    healthThresholds = {
        -- 双首领都使用同一组阈值；分别按 boss1 / boss2 的真实血量独立显示。
        { unit = "boss1", threshold = 66, preset = "phase_transition" },
        { unit = "boss1", threshold = 35, preset = "phase_transition" },
        { unit = "boss2", threshold = 66, preset = "phase_transition" },
        { unit = "boss2", threshold = 35, preset = "phase_transition" },
    },
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})
