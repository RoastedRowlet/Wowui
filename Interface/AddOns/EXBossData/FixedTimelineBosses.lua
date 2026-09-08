---@diagnostic disable: undefined-global
-- =============================================================
-- EXBossData/FixedTimelineBosses.lua
-- 统一触发配置中心（TIME / AI / BLZ）
--
-- 触发类型说明：
--   TIME = 固定轴（first/interval 展开）
--   AI   = duration->eventID 映射推理
--   BLZ  = 暴雪原生时间轴
--
-- 兼容导出：
--   _G.EXBOSS_FIXED_TIMELINE_ENCOUNTERS  (TIME 白名单)
--   _G.EXBOSS_DURATION_EVENT_RULES        (AI 映射表)
--   _G.EXBOSS_ENCOUNTER_TRIGGERS          (完整触发配置)
-- =============================================================
-- 如果STATE不FINISH 单独处里语音  格式
--   eventActions = {
--       [145] = { finishMode = "timer" },
--       [168] = { castStartUnit = "boss1" }, -- 首领圆环/怪物施法进度条只认 boss1 真实读条开始
--   },





local TRIGGER_TIME = "TIME"
local TRIGGER_AI = "AI"
local TRIGGER_BLZ = "BLZ"

local function NormalizeTrigger(v)
    local t = tostring(v or ""):upper()
    if t == TRIGGER_TIME or t == TRIGGER_AI or t == TRIGGER_BLZ then
        return t
    end
    return TRIGGER_BLZ
end

-- encounterID -> { trigger = TIME|AI|BLZ, durationRules = { {time,eventID}, ... }? }
local encounterTriggers = {

    --==============================================================================================================================
    --========================================= 12.1虚空之痕竞技场 =============================================================================================
    --==================================================================================================================================================

    [3285] = {
        trigger = TRIGGER_AI, --[塔兹拉尔] 0729
        durationRules = {
            { time = 31, eventID = 41,  sync = true },
            { time = 16, eventID = 782, sync = true },
            { time = 25, eventID = 39,  sync = true },
            { time = 6,  eventID = 558, sync = true },
        },
        eventActions = {
            [558] = {
                finishMode = "timer",
                timerFinishIgnoreStateWindow = 1.0,
            },
        },
    },




    [3286] = {
        trigger = TRIGGER_AI, -- 阿特洛苏斯 0720核对
        durationRules = {
            { time = 10, eventID = 47,  sync = true },
            { time = 5,  eventID = 55,  sync = true },
            { time = 35, eventID = 297, sync = true },
            { time = 15, eventID = 54,  sync = true },

            { time = 20, eventID = 55,  sequenceGroup = "3286_loop_20", sequenceOrder = 1 },
            { time = 20, eventID = 47,  sequenceGroup = "3286_loop_20", sequenceOrder = 2 },

            { time = 30, eventID = 54, },
        },
    },

    [3287] = {
        trigger = TRIGGER_AI, -- 煞戎努斯 0720更新
        durationRules = {
            { time = 5,  eventID = 56,  sync = true },
            { time = 43, eventID = 171, sync = true },
            { time = 17, eventID = 57,  sync = true },
            { time = 34, eventID = 961, sync = true },
            { time = 28, eventID = 58,  sync = true },
        },
    },






    --==============================================================================================================================
    --========================================= 12.1夺目谷============================================================================================
    --==================================================================================================================================================
    [3199] = {
        trigger = TRIGGER_AI, -- [光明众花] 0720更新
        aiStateMachine = {
            initialPhase = "MAIN",
            phases = {
                MAIN = {
                    normalize = {
                        { min = 41, max = 45, snap = 45 },
                    },
                    rules = {
                        { time = 8,  eventID = 176, sync = true },
                        { time = 5,  eventID = 173, sync = true },
                        { time = 35, eventID = 177, sync = true },
                        { time = 20, eventID = 174, sync = true },

                        { time = 45, eventID = 173, sequenceGroup = "3199_loop_45", sequenceOrder = 1 },
                        { time = 45, eventID = 176, sequenceGroup = "3199_loop_45", sequenceOrder = 2 },
                        { time = 45, eventID = 174, sequenceGroup = "3199_loop_45", sequenceOrder = 3 },
                        { time = 45, eventID = 177, sequenceGroup = "3199_loop_45", sequenceOrder = 4 },
                    },
                },
            },
        },
        eventActions = {
            [176] = { finishMode = "timer" },
        },
    },


    [3200] = {
        trigger = TRIGGER_AI, -- [圣光猎手伊库兹] 0720核对
        durationRules = {
            { time = 6,  eventID = 178, sync = true },
            { time = 22, eventID = 179, sync = true },
            { time = 50, eventID = 180, sync = true },
            { time = 29, eventID = 178, },
        },
    },

    [3201] = {
        trigger = TRIGGER_AI, -- [护光者鲁伊亚] 0720更新
        aiStateMachine = {
            initialPhase = "NONE",
            phases = {
                P1 = {
                    enter = {
                        mode = "sync_batch_all",
                        times = { 0.5, 5, 18 },
                        tolerance = 0.1,
                        priority = 100,
                    },
                    normalize = {
                        { min = 20, max = 21, snap = 20 },
                    },
                    rules = {
                        { time = 0.5, eventID = 186, sync = true },
                        { time = 5,   eventID = 181, sync = true },
                        { time = 18,  eventID = 182, sync = true },

                        { time = 20,  eventID = 181, sequenceGroup = "3201_P1_loop_20", sequenceOrder = 1 },
                        { time = 20,  eventID = 182, sequenceGroup = "3201_P1_loop_20", sequenceOrder = 2 },
                    },
                },
                P2 = {
                    enter = {
                        mode = "sync_batch_all",
                        times = { 3, 9 },
                        tolerance = 0.1,
                        priority = 110,
                    },
                    normalize = {
                        { min = 20, max = 21, snap = 20 },
                    },
                    rules = {
                        { time = 3,  eventID = 184, sync = true },
                        { time = 9,  eventID = 183, sync = true },

                        { time = 20, eventID = 184, sequenceGroup = "3201_P2_loop_20", sequenceOrder = 1 },
                        { time = 20, eventID = 183, sequenceGroup = "3201_P2_loop_20", sequenceOrder = 2 },
                    },
                },
                P3 = {
                    enter = {
                        mode = "duration_once",
                        time = 2.5,
                        tolerance = 0.1,
                        priority = 120,
                    },
                    normalize = {
                        { min = 31.5, max = 32.5, snap = 32 },
                    },
                    rules = {
                        { time = 2.5,  eventID = 188 },

                        { time = 7.3,  eventID = 181, sync = true },
                        { time = 15.3, eventID = 184, sync = true },
                        { time = 23.3, eventID = 182, sync = true },
                        { time = 31.1, eventID = 183, sync = true },

                        { time = 32,   eventID = 181, sequenceGroup = "3201_loop_32", sequenceOrder = 1 },
                        { time = 32,   eventID = 184, sequenceGroup = "3201_loop_32", sequenceOrder = 2 },
                        { time = 32,   eventID = 182, sequenceGroup = "3201_loop_32", sequenceOrder = 3 },
                        { time = 32,   eventID = 183, sequenceGroup = "3201_loop_32", sequenceOrder = 4 },
                    },
                    eventActions = {
                        [181] = { finishMode = "timer", timerFinishIgnoreStateWindow = 1.0 },
                        [184] = { finishMode = "timer", timerFinishIgnoreStateWindow = 1.0 },
                        [182] = { finishMode = "timer", timerFinishIgnoreStateWindow = 1.0 },
                        [183] = { finishMode = "timer", timerFinishIgnoreStateWindow = 1.0 },
                    },
                },
            },
        },
    },

    [3202] = {
        trigger = TRIGGER_AI, -- [兹欧凯特] 0727更新
        strictDurationMatch = true,
        durationRules = {
            { time = 26, eventID = 190, sync = true },
            { time = 4,  eventID = 189, sync = true },
            { time = 40, eventID = 191, sync = true },
            { time = 14, eventID = 192, sync = true },

            { time = 50, eventID = 189, sequenceGroup = "3202_loop_50", sequenceOrder = 1 },
            { time = 50, eventID = 192, sequenceGroup = "3202_loop_50", sequenceOrder = 2 },
            { time = 50, eventID = 190, sequenceGroup = "3202_loop_50", sequenceOrder = 3 },
            { time = 50, eventID = 191, sequenceGroup = "3202_loop_50", sequenceOrder = 4 },
        },
    },
    --==================================================================================================================================================
    --========================================= 12.1 密谋小径============================================================================================
    --===================================================================================================================================================
    [3101] = {
        trigger = TRIGGER_AI, -- [凯斯媞亚·魔力之心]
        durationRules = {
            { time = 8,    eventID = 122, sync = true },
            { time = 12,   eventID = 202, sync = true },
            { time = 15,   eventID = 120, sync = true },

            { time = 27.5, eventID = 122, },
            { time = 30,   eventID = 120, },
            { time = 12,   eventID = 202, },

        },
    },

    [3102] = {
        trigger = TRIGGER_AI, -- [赞恩·刃悲]
        durationRules = {
            { time = 12, eventID = 124, sync = true },
            { time = 26, eventID = 193, sync = true },
            { time = 36, eventID = 125, sync = true },
            { time = 18, eventID = 123, sync = true },
            { time = 8,  eventID = 127, sync = true },


            { time = 16, eventID = 124, },

        },
    },
    [3103] = {
        trigger = TRIGGER_AI, -- [歼灭者萨祖克斯]
        durationRules = {
            { time = 6,  eventID = 30,  sync = true },
            { time = 15, eventID = 559, sync = true },
            { time = 35, eventID = 32,  sync = true },
            { time = 30, eventID = 752, sync = true },

            { time = 27, eventID = 30, },

        },
    },
    [3105] = {
        trigger = TRIGGER_AI, -- [利希尔·烬怒]
        durationRules = {
            { time = 15, eventID = 37,  sync = true },
            { time = 10, eventID = 38,  sync = true },
            { time = 24, eventID = 207, sync = true },

            { time = 57, eventID = 38, },
            { time = 55, eventID = 37, },
            { time = 59, eventID = 207, },

        },
    },



    --==================================================================================================================================================
    --========================================= 12.1 纳洛拉克的洞穴======================================================================================
    --================================================================================================================================================

    [3207] = {
        trigger = TRIGGER_AI, -- [囤宝狂人]
        durationRules = {
            { time = 30, eventID = 86, sync = true },
            { time = 6,  eventID = 88, sync = true },
            { time = 16, eventID = 87, sync = true },
        },
    },

    [3208] = {
        trigger = TRIGGER_AI, -- [寒冬哨兵]
        durationRules = {
            { time = 7,  eventID = 67, sync = true },
            { time = 13, eventID = 68, sync = true },
            { time = 25, eventID = 69, sync = true },
            { time = 50, eventID = 70, sync = true },
        },
    },


    [3209] = {
        trigger = TRIGGER_AI, -- [纳洛拉克]
        durationRules = {
            { time = 13, eventID = 92,  sync = true },
            { time = 5,  eventID = 911, sync = true },
            { time = 54, eventID = 910, sync = true },

            { time = 25, eventID = 911, sequenceGroup = "3209_loop_25", sequenceOrder = 1 },
            { time = 25, eventID = 92,  sequenceGroup = "3209_loop_25", sequenceOrder = 2 },

        },
    },
    --==================================================================================================================================================
    --========================================= 12.1 塞塔里斯神庙============================================================================================
    --===================================================================================================================================================
    [2124] = {
        trigger = TRIGGER_AI, -- [阿德里斯和阿斯匹克斯] 0720 FINISH
        aiStateMachine = {
            initialPhase = "NONE",
            phases = {
                P1 = {
                    enter = {
                        mode = "sync_batch_all",
                        times = { 9, 39, 29, 5 },
                        tolerance = 0.1,
                        priority = 100,
                    },

                    rules = {
                        { time = 9,  eventID = 689, sync = true },
                        { time = 39, eventID = 690, sync = true },
                        { time = 29, eventID = 691, sync = true },
                        { time = 5,  eventID = 692, sync = true },

                        { time = 4,  eventID = 689, sync = true },
                        { time = 29, eventID = 691, sync = true },
                        { time = 35, eventID = 690, sync = true },
                        { time = 25, eventID = 691, sync = true },
                        { time = 1,  eventID = 692, sync = true },

                        { time = 45, eventID = 692, sequenceGroup = "2124_loop_45", sequenceOrder = 1 },
                        { time = 45, eventID = 689, sequenceGroup = "2124_loop_45", sequenceOrder = 2 },
                        { time = 45, eventID = 691, sequenceGroup = "2124_loop_45", sequenceOrder = 3 },
                        { time = 45, eventID = 690, sequenceGroup = "2124_loop_45", sequenceOrder = 4 },

                    },
                },
                P2 = {
                    enter = {
                        mode = "sync_batch_all",
                        times = { 12, 5 },
                        tolerance = 0.1,
                        priority = 110,
                    },

                    rules = {
                        { time = 12, eventID = 691, sync = true },
                        { time = 5,  eventID = 692, sync = true },

                        { time = 19, eventID = 692, sequenceGroup = "2124_loop_19", sequenceOrder = 1 },
                        { time = 19, eventID = 691, sequenceGroup = "2124_loop_19", sequenceOrder = 2 },

                    },
                },

            },
        },
    },


    [2125] = {
        trigger = TRIGGER_AI, -- [米利克萨] 0720 核对
        durationRules = {
            { time = 13, eventID = 702, sync = true },
            { time = 36, eventID = 706, sync = true },
            { time = 5,  eventID = 705, sync = true },
            { time = 25, eventID = 703, sync = true },
            { time = 44, eventID = 704, sync = true },
            { time = 49, eventID = 701, sync = true },
        },
    },

    [2126] = {
        trigger = TRIGGER_AI, -- [加瓦兹特] 0729 FINISH
        durationRules = {
            { time = 20, eventID = 697, sync = true },
            { time = 5,  eventID = 698, sync = true },


            { time = 22, eventID = 698, sequenceGroup = "2126_loop_22", sequenceOrder = 1 },
            { time = 22, eventID = 697, sequenceGroup = "2126_loop_22", sequenceOrder = 2 },

        },
    },

    [2127] = {
        trigger = TRIGGER_AI, -- [塞塔里斯的化身]
        durationRules = {
            { time = 13, eventID = 92,  sync = true },
            { time = 15, eventID = 828, sync = true },


        },
    },

    --==================================================================================================================================================
    --========================================= 12.1 红玉新生法池============================================================================================
    --===================================================================================================================================================
    [2609] = {
        trigger = TRIGGER_AI, -- [梅莉杜莎·寒妆] 0709 需要测试
        durationRules = {
            { time = 5,  eventID = 866, sync = true },
            { time = 15, eventID = 867, sync = true },


            { time = 12, eventID = 868 },

            { time = 24, eventID = 866, sequenceGroup = "2609_loop_27", sequenceOrder = 1 },
            { time = 24, eventID = 867, sequenceGroup = "2609_loop_27", sequenceOrder = 2 },

        },
    },

    [2606] = {
        trigger = TRIGGER_AI, -- [柯姬雅·焰蹄]  0709 FINISH
        durationRules = {
            { time = 28, eventID = 884, sync = true },
            { time = 19, eventID = 883, sync = true },
            { time = 8,  eventID = 882, sync = true },

            { time = 20, eventID = 883 },

            { time = 40, eventID = 882, sequenceGroup = "2606_loop_40", sequenceOrder = 1 },
            { time = 40, eventID = 884, sequenceGroup = "2606_loop_40", sequenceOrder = 2 },

        },
    },

    [2623] = {
        trigger = TRIGGER_AI, -- [基拉卡与厄克哈特·风脉] 0713  FINISH
        durationRules = {
            { time = 10,   eventID = 887, sync = true },
            { time = 21,   eventID = 885, sync = true },
            { time = 5,    eventID = 888, sync = true },
            { time = 1,    eventID = 890, sync = true },
            { time = 12,   eventID = 889, sync = true },

            { time = 22.5, eventID = 888 },
            { time = 21.5, eventID = 887 },
            { time = 25,   eventID = 885 },

            { time = 9,    eventID = 894 },

            { time = 20,   eventID = 890, sequenceGroup = "2623_loop_20", sequenceOrder = 1 },
            { time = 20,   eventID = 889, sequenceGroup = "2623_loop_20", sequenceOrder = 2 },

            { time = 16,   eventID = 890, sequenceGroup = "2623_loop_16", sequenceOrder = 1 },
            { time = 16,   eventID = 894, sequenceGroup = "2623_loop_16", sequenceOrder = 2 },
        },
    },

    --==================================================================================================================================================
    --========================================= 12.1 诸王之眠============================================================================================
    --===================================================================================================================================================

    [2139] = {
        trigger = TRIGGER_AI, -- [黄金风蛇] 0720 更新
        durationRules = {
            { time = 8,  eventID = 891, sync = true },
            { time = 5,  eventID = 767, sync = true },
            { time = 54, eventID = 893, sync = true },
            { time = 14, eventID = 892, sync = true },

            { time = 28, eventID = 892 },

            { time = 25, eventID = 767, sequenceGroup = "2139_loop_25", sequenceOrder = 1 },
            { time = 25, eventID = 891, sequenceGroup = "2139_loop_25", sequenceOrder = 2 },

        },
    },

    [2142] = {
        trigger = TRIGGER_AI, -- [殓尸者姆沁巴] 0720 更新
        durationRules = {
            { time = 20, eventID = 878, sync = true },
            { time = 60, eventID = 879, sync = true },
            { time = 5,  eventID = 880, sync = true },
            { time = 30, eventID = 973, sync = true },

            { time = 32, eventID = 880 },
            { time = 30, eventID = 878 },

        },
    },

    [2140] = {
        trigger = TRIGGER_AI, -- [部族议会] 0720 更新
        aiStateMachine = {
            initialPhase = "NONE",
            phases = {
                P1 = {
                    enter = {
                        mode = "sync_batch_all",
                        times = { 8, 15 },
                        tolerance = 0.1,
                        priority = 100,
                    },
                    rules = {
                        { time = 8,     eventID = 870, sync = true },
                        { time = 15,    eventID = 871, sync = true },

                        { time = 14.75, eventID = 870 },
                        { time = 16.5,  eventID = 871 },
                    },
                },
                P2 = {
                    enter = {
                        mode = "sync_batch_all",
                        times = { 5, 14 },
                        tolerance = 0.1,
                        priority = 110,
                    },

                    rules = {
                        { time = 5,  eventID = 872, sync = true },
                        { time = 14, eventID = 873, sync = true },

                        { time = 20, eventID = 872 },
                        { time = 22, eventID = 873 },

                    },
                },
                P3 = {
                    enter = {
                        mode = "sync_batch_all",
                        times = { 2, 10, 20 },
                        tolerance = 0.1,
                        priority = 120,
                    },
                    rules = {
                        { time = 2,    eventID = 874, sync = true },
                        { time = 10,   eventID = 875, sync = true },
                        { time = 20,   eventID = 876, sync = true },

                        { time = 7,    eventID = 874 },
                        { time = 24.4, eventID = 875 },
                        { time = 52.5, eventID = 876 },
                    },
                },

            },
        },
    },







    [2143] = {
        trigger = TRIGGER_AI, -- [始皇达萨] 0720 更新
        durationRules = {

            --P1
            { time = 23, eventID = 832, sync = true },
            { time = 30, eventID = 833, sync = true },
            { time = 15, eventID = 831, sync = true },
            { time = 8,  eventID = 834, sync = true },
            { time = 14, eventID = 835, sync = true },

            { time = 10, eventID = 834, sequenceGroup = "2143_loop_10", sequenceOrder = 1 },
            { time = 10, eventID = 835, sequenceGroup = "2143_loop_10", sequenceOrder = 2 },

            -- P2
            { time = 36, eventID = 837, sync = true },
            { time = 9,  eventID = 836, sync = true },
            { time = 38, eventID = 832, sync = true },
            { time = 24, eventID = 833, sync = true },

        },
        eventActions = {
            [834] = {
                finishMode = "timer",
                timerFinishIgnoreStateWindow = 1.0,
            },
            [831] = {
                finishMode = "timer",
                timerFinishIgnoreStateWindow = 1.0,
            },
        },
    },

    --==================================================================================================================================================
    --========================================= 12.1 毒牙祭坛============================================================================================
    --===================================================================================================================================================
    [3456] = {
        trigger = TRIGGER_AI,                          -- [拉维]
        durationRules = {
            { time = 8,  eventID = 797, sync = true }, --三重
            { time = 25, eventID = 795, sync = true }, --食腐
            { time = 13, eventID = 798, sync = true }, --反刍
            { time = 45, eventID = 795, sync = true }, --食腐
            { time = 23, eventID = 899, sync = true },
            { time = 24, eventID = 797, },             --三重

        },
        eventActions = {
            [795] = {
                finishMode = "timer",
                timerFinishIgnoreStateWindow = 1.0,
            },
        },
    },




    [3457] = {
        trigger = TRIGGER_AI, -- [扭缠盘蛇]
        aiStateMachine = {
            initialPhase = "NONE",
            phases = {
                P1 = {
                    enter = {
                        mode = "sync_batch_all",
                        times = { 1, 7, 44, 14, 30 },
                        tolerance = 0.1,
                        priority = 100,
                    },

                    rules = {
                        { time = 1,  eventID = 813, sync = true },
                        { time = 7,  eventID = 814, sync = true },
                        { time = 44, eventID = 816, sync = true },
                        { time = 14, eventID = 938, sync = true },
                        { time = 30, eventID = 815, sync = true },

                    },
                },
                P2 = {
                    enter = {
                        mode = "sync_batch_all",
                        times = { 10, 25 },
                        tolerance = 0.1,
                        priority = 110,
                    },

                    rules = {
                        { time = 10, eventID = 939, sync = true },
                        { time = 25, eventID = 818, sync = true },

                    },
                },
                P3 = {
                    enter = {
                        mode = "sync_batch_all",
                        times = { 10, 53, 23, 16, 39 },
                        tolerance = 0.1,
                        priority = 120,
                    },
                    rules = {
                        { time = 10, eventID = 813, sync = true },
                        { time = 53, eventID = 816, sync = true },
                        { time = 23, eventID = 938, sync = true },
                        { time = 16, eventID = 814, sync = true },
                        { time = 39, eventID = 815, sync = true },
                    },
                },
            },
        },
    },









    [3458] = {
        trigger = TRIGGER_AI, -- [尾王]
        durationRules = {
            { time = 32, eventID = 821, sync = true },
            { time = 14, eventID = 823, sync = true },
            { time = 26, eventID = 824, sync = true },
            { time = 26, eventID = 824, sync = true },

            { time = 64, eventID = 822, },
            { time = 30, eventID = 824, },
            { time = 14, eventID = 821, },

        },
        eventActions = {
            [822] = {
                finishMode = "timer",
                timerFinishIgnoreStateWindow = 1.0,
            },
        },
    },
}

local fixedSet = {}
local durationRules = {}

for encounterID, row in pairs(encounterTriggers) do
    if type(row) == "table" then
        row.trigger = NormalizeTrigger(row.trigger)
        if row.trigger == TRIGGER_TIME then
            fixedSet[encounterID] = true
        end
        if type(row.durationRules) == "table" and #row.durationRules > 0 then
            durationRules[encounterID] = row.durationRules
            durationRules[tostring(encounterID)] = row.durationRules
        end
    else
        local t = NormalizeTrigger(row)
        encounterTriggers[encounterID] = { trigger = t }
        if t == TRIGGER_TIME then
            fixedSet[encounterID] = true
        end
    end
end

_G.EXBOSS_FIXED_TIMELINE_ENCOUNTERS = fixedSet
_G.EXBOSS_DURATION_EVENT_RULES = durationRules
_G.EXBOSS_ENCOUNTER_TRIGGERS = encounterTriggers

_G.EXBossData = _G.EXBossData or {}

function _G.EXBossData.GetEncounterTriggerConfig()
    return _G.EXBOSS_ENCOUNTER_TRIGGERS
end

function _G.EXBossData.GetEncounterTrigger(encounterID)
    local id = tonumber(encounterID) or encounterID
    local row = encounterTriggers[id]
    if row == nil then
        row = encounterTriggers[tostring(id)]
    end
    if type(row) == "table" then
        return NormalizeTrigger(row.trigger)
    end
    return NormalizeTrigger(row)
end

return encounterTriggers
