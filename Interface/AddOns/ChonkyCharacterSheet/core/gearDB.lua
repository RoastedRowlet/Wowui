-- The purpose of the this file is to house the seasonal gear information.
-- It currently holds the M+ dungeon, raid, and class tier information
-- for building a master loot list.
local addonName, ns = ...
local L = ns.L  -- grab the localization table
local CCS = ns.CCS

if CCS.GetCurrentVersion() ~= CCS.RETAIL then
    return
end

local locale = GetLocale()
local _, _, _, tocversion = GetBuildInfo()
local playerLevel = UnitLevel("player")

CCS.Dungeon = CCS.Dungeon or {}
CCS.Raid = CCS.Raid or {}
CCS.Season = CCS.Season or {}
CCS.MasterLoot = {}
CCS.CurrenSeasonNumber = 1
CCS.bisIlvl = 289

CCS.FooterFilters = {
    slot = "ALL",
    class = "ALL",
    armor = "ALL",
    primary = "ALL",
    secondaries = {
        CRIT = false,
        HASTE = false,
        MASTERY = false,
        VERS = false,
    },
    instance = "ALL",
    includeDungeons = true,
    includeRaids = true,
    ilvl = 289,
    track = "Myth",
}

-- EJ_GetInstanceInfo(ejID) to get the name of the dungeon
-- EJ_GetEncounterInfo(boss.id) to get boss name
-- Magister's Terrace (EJ ID 249)
CCS.Dungeon.MagistersTerrace = {
    ejID = 249,
    bosses = {
        {
            id = 2659, -- Arcanotron Custos
            loot = {
                { itemID = 251100 },
                { itemID = 251101 },
                { itemID = 251103 },
                { itemID = 251102 },
                { itemID = 251104 },
                { itemID = 250246 },
            },
        },
        {
            id = 2661, -- Seranel Sunlash
            loot = {
                { itemID = 251106 },
                { itemID = 251105 },
                { itemID = 251109 },
                { itemID = 260312 },
                { itemID = 251108 },
                { itemID = 251110 },
                { itemID = 251107 },
            },
        },
        {
            id = 2660, -- Gemellus
            loot = {
                { itemID = 251111 },
                { itemID = 251114 },
                { itemID = 251113 },
                { itemID = 251112 },
                { itemID = 251115 },
                { itemID = 250242 },
            },
        },
        {
            id = 2662, -- Degentrius
            loot = {
                { itemID = 251117 },
                { itemID = 251118 },
                { itemID = 251119 },
                { itemID = 251120 },
                { itemID = 251121 },
                { itemID = 251122 },
                { itemID = 250257 },
            },
        },
    },
}

-- Maisara Caverns (EJ ID 1315)
CCS.Dungeon.MaisaraCaverns = {
    ejID = 1315,
    bosses = {
        {
            id = 2810, -- Muro'jin and Nekraxx
            loot = {
                { itemID = 251162 },
                { itemID = 251174 },
                { itemID = 251176 },
                { itemID = 263193 },
                { itemID = 251166 },
                { itemID = 251167 },
            },
        },
        {
            id = 2811, -- Vordaza
            loot = {
                { itemID = 251178 },
                { itemID = 251171 },
                { itemID = 251161 },
                { itemID = 251172 },
                { itemID = 251170 },
                { itemID = 251169 },
                { itemID = 250223 },
            },
        },
        {
            id = 2812, -- Rak'tul, Vessel of Souls
            loot = {
                { itemID = 251168 },
                { itemID = 251163 },
                { itemID = 251175 },
                { itemID = 251177 },
                { itemID = 251164 },
                { itemID = 251179 },
                { itemID = 250258 },
            },
        },
    },
}

-- Nexus-Point Xenas (EJ ID 1316)
CCS.Dungeon.NexusPointXenas = {
    ejID = 1316,
    bosses = {
        {
            id = 2813, -- Chief Corewright Kasreth
            loot = {
                { itemID = 251202 },
                { itemID = 251206 },
                { itemID = 251203 },
                { itemID = 251204 },
                { itemID = 251205 },
                { itemID = 251201 },
            },
        },
        {
            id = 2814, -- Corewarden Nysarra
            loot = {
                { itemID = 251213 },
                { itemID = 251209 },
                { itemID = 251208 },
                { itemID = 251210 },
                { itemID = 251093 },
                { itemID = 251207 },
                { itemID = 250253 },
            },
        },
        {
            id = 2815, -- Lothraxion
            loot = {
                { itemID = 251212 },
                { itemID = 251157 },
                { itemID = 251216 },
                { itemID = 251211 },
                { itemID = 251215 },
                { itemID = 251217 },
                { itemID = 250241 },
            },
        },
    },
}

-- Windrunner Spire (EJ ID 1299)
CCS.Dungeon.WindrunnerSpire = {
    ejID = 1299,
    bosses = {
        {
            id = 2655, -- Emberdawn
            loot = {
                { itemID = 251078 },
                { itemID = 251077 },
                { itemID = 251080 },
                { itemID = 251079 },
                { itemID = 251081 },
                { itemID = 251082 },
                { itemID = 250144 },
            },
        },
        {
            id = 2656, -- Derelict Duo
            loot = {
                { itemID = 251083 },
                { itemID = 251085 },
                { itemID = 251086 },
                { itemID = 251087 },
                { itemID = 251084 },
                { itemID = 250226 },
            },
        },
        {
            id = 2657, -- Commander Kroluk
            loot = {
                { itemID = 251088 },
                { itemID = 251092 },
                { itemID = 251089 },
                { itemID = 251090 },
                { itemID = 251091 },
                { itemID = 250227 },
            },
        },
        {
            id = 2658, -- The Restless Heart
            loot = {
                { itemID = 251094 },
                { itemID = 251095 },
                { itemID = 251096 },
                { itemID = 251097 },
                { itemID = 251098 },
                { itemID = 251099 },
                { itemID = 250256 },
            },
        },
    },
}

-- Algeth'ar Academy (EJ ID 1201)
CCS.Dungeon.AlgetharAcademy = {
    ejID = 1201,
    bosses = {
        {
            id = 2509, -- Vexamus
            loot = {
                { itemID = 258529 },
                { itemID = 193711 },
                { itemID = 193710 },
                { itemID = 193709 },
                { itemID = 193708 },
            },
        },
        {
            id = 2512, -- Overgrown Ancient
            loot = {
                { itemID = 193716 },
                { itemID = 193717 },
                { itemID = 193712 },
                { itemID = 193714 },
                { itemID = 193713 },
                { itemID = 193715 },
            },
        },
        {
            id = 2495, -- Crawth
            loot = {
                { itemID = 193723 },
                { itemID = 258531 },
                { itemID = 193720 },
                { itemID = 193721 },
                { itemID = 193722 },
                { itemID = 193719 },
                { itemID = 193718 },
            },
        },
        {
            id = 2514, -- Echo of Doragosa
            loot = {
                { itemID = 193707 },
                { itemID = 193703 },
                { itemID = 193704 },
                { itemID = 193705 },
                { itemID = 193706 },
                { itemID = 193701 },
            },
        },
    },
}

-- Pit of Saron (EJ ID 278)
CCS.Dungeon.PitOfSaron = {
    ejID = 278,
    bosses = {
        {
            id = 608, -- Forgemaster Garfrost
            loot = {
                { itemID = 49802 },
                { itemID = 50227 },
                { itemID = 50228 },
                { itemID = 50234 },
                { itemID = 50233 },
                { itemID = 49806 },
                { itemID = 49805 },
            },
        },
        {
            id = 609, -- Ick and Krick
            loot = {
                { itemID = 49807 },
                { itemID = 50264 },
                { itemID = 49809 },
                { itemID = 49808 },
                { itemID = 50263 },
                { itemID = 49810 },
                { itemID = 49811 },
                { itemID = 49812 },
                { itemID = 252421 },
            },
        },
        {
            id = 610, -- Scourgelord Tyrannus
            loot = {
                { itemID = 49813 },
                { itemID = 49824 },
                { itemID = 49819 },
                { itemID = 49823 },
                { itemID = 50272 },
                { itemID = 49825 },
                { itemID = 49817 },
                { itemID = 50259 },
            },
        },
    },
}

-- Seat of the Triumvirate (EJ ID 945)
CCS.Dungeon.SeatOfTheTriumvirate = {
    ejID = 945,
    bosses = {
        {
            id = 1979, -- Zuraal the Ascended
            loot = {
                { itemID = 258514 },
                { itemID = 151336 },
                { itemID = 151329 },
                { itemID = 151300 },
                { itemID = 151320 },
                { itemID = 151308 },
                { itemID = 151312 },
            },
        },
        {
            id = 1980, -- Saprish
            loot = {
                { itemID = 258516 },
                { itemID = 151337 },
                { itemID = 151323 },
                { itemID = 151303 },
                { itemID = 151321 },
                { itemID = 151318 },
                { itemID = 151327 },
                { itemID = 151314 },
                { itemID = 151330 },
                { itemID = 151307 },
            },
        },
        {
            id = 1981, -- Viceroy Nezhar
            loot = {
                { itemID = 258524 },
                { itemID = 258523 },
                { itemID = 151333 },
                { itemID = 151309 },
                { itemID = 151299 },
                { itemID = 151325 },
                { itemID = 151305 },
                { itemID = 151332 },
                { itemID = 151317 },
                { itemID = 151310 },
            },
        },
        {
            id = 1982, -- L'ura
            loot = {
                { itemID = 258525 },
                { itemID = 151319 },
                { itemID = 151313 },
                { itemID = 151328 },
                { itemID = 151322 },
                { itemID = 151302 },
                { itemID = 151301 },
                { itemID = 151311 },
                { itemID = 151340 },
            },
        },
    },
}

-- Skyreach (EJ ID 476)
CCS.Dungeon.Skyreach = {
    ejID = 476,
    bosses = {
        {
            id = 965, -- Ranjit
            loot = {
                { itemID = 258046 },
                { itemID = 258218 },
                { itemID = 258412 },
                { itemID = 258575 },
                { itemID = 258574 },
            },
        },
        {
            id = 966, -- Araknath
            loot = {
                { itemID = 258047 },
                { itemID = 258436 },
                { itemID = 258579 },
                { itemID = 258578 },
                { itemID = 258576 },
                { itemID = 258577 },
                { itemID = 252418 },
            },
        },
        {
            id = 967, -- Rukhran
            loot = {
                { itemID = 258048 },
                { itemID = 258438 },
                { itemID = 258472 },
                { itemID = 258581 },
                { itemID = 258580 },
                { itemID = 258583 },
                { itemID = 258582 },
                { itemID = 252411 },
            },
        },
        {
            id = 968, -- High Sage Viryx
            loot = {
                { itemID = 258484 },
                { itemID = 258050 },
                { itemID = 258049 },
                { itemID = 258585 },
                { itemID = 258587 },
                { itemID = 258586 },
                { itemID = 258584 },
                { itemID = 252420 },
            },
        },
    },
}


-- The Dreamrift (EJ ID 1314)
CCS.Raid.Dreamrift = {
    ejID = 1314,
    bosses = {
        {
            id = 2795, -- Chimaerus the Undreamt God
            loot = {
                --{ itemID = 249347 },
                --{ itemID = 249348 },
                --{ itemID = 249349 },
                --{ itemID = 249350 },
                { itemID = 249278 },
                { itemID = 249922 },
                { itemID = 249374 },
                { itemID = 249371 },
                { itemID = 249373 },
                { itemID = 249381 },
                { itemID = 249343 },
                { itemID = 249805 },
            },
        },
    },
}

-- The Sporefall (EJ ID 1305)
CCS.Raid.Sporefall = {
    ejID = 1305,
    bosses = {
        {
            id = 2711, -- Rotmire
            loot = {
                { itemID = 268283 },
                { itemID = 268291 },
                { itemID = 268284 },
                { itemID = 268285 },
                { itemID = 268289 },
                { itemID = 268286 },
                { itemID = 268288 },
                { itemID = 268287 },
                { itemID = 268282 },
                { itemID = 268292 },
                { itemID = 268290 },
            },
        },
    },
}

-- The Voidspire (EJ ID 1307)
CCS.Raid.Voidspire = {
    ejID = 1307,
    bosses = {
        {
            id = 2733, -- Imperator Averzian
            loot = {
                { itemID = 249293 },
                { itemID = 249279 },
                { itemID = 249275 },
                { itemID = 249306 },
                { itemID = 249313 },
                { itemID = 249335 },
                { itemID = 249310 },
                { itemID = 249326 },
                { itemID = 249319 },
                { itemID = 249323 },
                { itemID = 249320 },
                { itemID = 249334 },
                { itemID = 249344 },
            },
        },
        {
            id = 2734, -- Vorasius
            loot = {
                --{ itemID = 249353 },
                --{ itemID = 249352 },
                --{ itemID = 249354 },
                --{ itemID = 249351 },
                { itemID = 249302 },
                { itemID = 249925 },
                { itemID = 249276 },
                { itemID = 249317 },
                { itemID = 249327 },
                { itemID = 249315 },
                { itemID = 249332 },
                { itemID = 249336 },
                { itemID = 249342 },
            },
        },
        {
            id = 2736, -- Fallen-King Salhadaar
            loot = {
                --{ itemID = 249365 },
                --{ itemID = 249364 },
                --{ itemID = 249366 },
                --{ itemID = 249363 },
                { itemID = 249281 },
                { itemID = 249298 },
                { itemID = 249316 },
                { itemID = 249337 },
                { itemID = 249308 },
                { itemID = 249304 },
                { itemID = 249314 },
                { itemID = 249341 },
                { itemID = 249340 },
            },
        },
        {
            id = 2735, -- Vaelgor & Ezzorak
            loot = {
                --{ itemID = 249361 },
                --{ itemID = 249360 },
                --{ itemID = 249362 },
                --{ itemID = 249359 },
                { itemID = 249287 },
                { itemID = 249280 },
                { itemID = 249318 },
                { itemID = 249370 },
                { itemID = 249321 },
                { itemID = 249331 },
                { itemID = 249305 },
                { itemID = 249339 },
                { itemID = 249346 },
            },
        },
        {
            id = 2737, -- Lightblinded Vanguard
            loot = {
                --{ itemID = 249357 },
                --{ itemID = 249356 },
                --{ itemID = 249358 },
                --{ itemID = 249355 },
                { itemID = 249277 },
                { itemID = 249294 },
                { itemID = 249333 },
                { itemID = 249330 },
                { itemID = 249303 },
                { itemID = 249311 },
                { itemID = 249369 },
                { itemID = 249808 },
            },
        },
        {
            id = 2738, -- Crown of the Cosmos
            loot = {
                { itemID = 260423 },
                { itemID = 249295 },
                { itemID = 249288 },
                { itemID = 249329 },
                { itemID = 249309 },
                { itemID = 249325 },
                { itemID = 249380 },
                { itemID = 249312 },
                { itemID = 249382 },
                { itemID = 249809 },
                { itemID = 249345 },
                { itemID = 249368 },
            },
        },
    },
}

-- March on Quel'Danas (EJ ID 1308)
CCS.Raid.MarchOnQueldanas = {
    ejID = 1308,
    bosses = {
        {
            id = 2739, -- Belo'ren, Child of Al'ar
            loot = {
                { itemID = 249283 },
                { itemID = 249284 },
                { itemID = 249921 },
                { itemID = 249328 },
                { itemID = 249322 },
                { itemID = 249307 },
                { itemID = 249376 },
                { itemID = 249324 },
                { itemID = 249377 },
                { itemID = 249919 },
                { itemID = 249806 },
                { itemID = 249807 },
                { itemID = 260235 },
            },
        },
        {
            id = 2740, -- Midnight Falls
            loot = {
                { itemID = 249296 },
                { itemID = 249286 },
                { itemID = 260408 },
                { itemID = 249913 },
                { itemID = 249914 },
                { itemID = 250247 },
                { itemID = 249912 },
                { itemID = 249915 },
                { itemID = 249811 },
                { itemID = 249810 },
                { itemID = 249920 },
            },
        },
    },
}

CCS.ClassSets = {
    [1]  = { setID = 1990, items = { {itemID=249955},{itemID=249953},{itemID=249952},{itemID=249951},{itemID=249950} } }, -- Warrior
    [2]  = { setID = 1985, items = { {itemID=249964},{itemID=249962},{itemID=249961},{itemID=249960},{itemID=249959} } }, -- Paladin
    [3]  = { setID = 1982, items = { {itemID=249991},{itemID=249989},{itemID=249988},{itemID=249987},{itemID=249986} } }, -- Hunter
    [4]  = { setID = 1987, items = { {itemID=250009},{itemID=250007},{itemID=250006},{itemID=250005},{itemID=250004} } }, -- Rogue
    [5]  = { setID = 1986, items = { {itemID=250052},{itemID=250051},{itemID=250050},{itemID=250054},{itemID=250049} } }, -- Priest
    [6]  = { setID = 1978, items = { {itemID=249973},{itemID=249971},{itemID=249970},{itemID=249969},{itemID=249968} } }, -- Death Knight
    [7]  = { setID = 1988, items = { {itemID=249982},{itemID=249980},{itemID=249979},{itemID=249978},{itemID=249977} } }, -- Shaman
    [8]  = { setID = 1983, items = { {itemID=250063},{itemID=250061},{itemID=250060},{itemID=250059},{itemID=250058} } }, -- Mage
    [9]  = { setID = 1989, items = { {itemID=250043},{itemID=250042},{itemID=250041},{itemID=250045},{itemID=250040} } }, -- Warlock
    [10] = { setID = 1984, items = { {itemID=250018},{itemID=250016},{itemID=250015},{itemID=250014},{itemID=250013} } }, -- Monk
    [11] = { setID = 1980, items = { {itemID=250027},{itemID=250025},{itemID=250024},{itemID=250023},{itemID=250022} } }, -- Druid
    [12] = { setID = 1979, items = { {itemID=250036},{itemID=250034},{itemID=250033},{itemID=250032},{itemID=250031} } }, -- Demon Hunter
    [13] = { setID = 1981, items = { {itemID=250000},{itemID=249998},{itemID=249997},{itemID=249996},{itemID=249995} } }, -- Evoker
}

function CCS:BuildClassSetLookup()
    CCS.ClassSetLookup = {}

    for classID, data in pairs(CCS.ClassSets) do
        CCS.ClassSetLookup[classID] = {}

        for _, entry in ipairs(data.items) do
            CCS.ClassSetLookup[classID][entry.itemID] = true
        end
    end
end

CCS:BuildClassSetLookup()

CCS.Season_upgradeTracks = {
    Champion = {
        id    = CCS.Champion,
        label = L["Champion"],
        bonusByIlvl = {
            [246] = 12785,
            [250] = 12786,
            [253] = 12787,
            [256] = 12788,
            [259] = 12789,
            [263] = 12790,
        },
    },

    Hero = {
        id    = CCS.Hero,
        label = L["Hero"],
        bonusByIlvl = {
            [259] = 12793,
            [263] = 12794,
            [266] = 12795,
            [269] = 12796,
            [272] = 12797,
            [276] = 12798,
            [285] = 13653, -- default to void ascended           
        },
    },

    Myth = {
        id    = CCS.Myth,
        label = L["Myth"],
        bonusByIlvl = {
            [272] = 12801,
            [276] = 12802,
            [279] = 12803,
            [282] = 12804,
            [285] = 12805,
            [289] = 12806,
            [298] = 13654, -- default to void ascended
        },
    },
}

CCS.Season = {
    seasonName = string.format(EXPANSION_SEASON_NAME, EXPANSION_NAME11, CCS.CurrenSeasonNumber),
    
    dungeons = {
        [249]  = CCS.Dungeon.MagistersTerrace,
        [1315] = CCS.Dungeon.MaisaraCaverns,
        [1316] = CCS.Dungeon.NexusPointXenas,
        [1299] = CCS.Dungeon.WindrunnerSpire,
        [1201] = CCS.Dungeon.AlgetharAcademy,
        [278]  = CCS.Dungeon.PitOfSaron,
        [945]  = CCS.Dungeon.SeatOfTheTriumvirate,
        [476]  = CCS.Dungeon.Skyreach,
    },

    raids = {
        [1314] = CCS.Raid.Dreamrift,
        [1307] = CCS.Raid.Voidspire,
        [1308] = CCS.Raid.MarchOnQueldanas,
        [1305] = CCS.Raid.Sporefall,
    },
    -- Class sets for Midnight Season 1
    classSets = CCS.ClassSets,
}

local function AddItemToMaster(itemID, container, boss, seasonName)
    local entry = CCS.MasterLoot[itemID] or {}

    local item = Item:CreateFromItemID(itemID)
    item:ContinueOnItemLoad(function()

        ---------------------------------------------------------
        -- Get item info
        ---------------------------------------------------------
        local name, link, quality, ilvl, req, classStr, subclassStr, stack, equipLoc =
            C_Item.GetItemInfo(itemID)

        -- Numeric class/subclass IDs (REQUIRED for filtering)
        local itemClassID, itemSubClassID = select(12, GetItemInfo(itemID))
        -- itemClassID: 2 = WEAPON, 4 = ARMOR, etc.
        -- itemSubClassID: numeric weapon/armor subtype

        ---------------------------------------------------------
        -- Armor type (Cloth / Leather / Mail / Plate)
        ---------------------------------------------------------
        local armorType = nil

        if itemClassID == 4 then  -- 4 = ARMOR
            -- Retail armor subclass IDs:
            -- 1 = Cloth, 2 = Leather, 3 = Mail, 4 = Plate
            if itemSubClassID == 1 then
                armorType = "Cloth"
            elseif itemSubClassID == 2 then
                armorType = "Leather"
            elseif itemSubClassID == 3 then
                armorType = "Mail"
            elseif itemSubClassID == 4 then
                armorType = "Plate"
            end
        end

        ---------------------------------------------------------
        -- Primary/secondary stat *types* (not values)
        ---------------------------------------------------------
        local stats = link and C_Item.GetItemStats(link) or nil
        local primary = {}
        local secondary = {}

        if stats then
            if stats["ITEM_MOD_STRENGTH"] then table.insert(primary, "STR") end
            if stats["ITEM_MOD_AGILITY"] then table.insert(primary, "AGI") end
            if stats["ITEM_MOD_INTELLECT"] then table.insert(primary, "INT") end

            if stats["ITEM_MOD_CRIT_RATING"] then secondary.CRIT = true end
            if stats["ITEM_MOD_HASTE_RATING"] then secondary.HASTE = true end
            if stats["ITEM_MOD_MASTERY_RATING"] then secondary.MASTERY = true end
            if stats["ITEM_MOD_VERSATILITY"] then secondary.VERS = true end
        end

        ---------------------------------------------------------
        -- Source info
        ---------------------------------------------------------
        local instanceName = container.instanceName or EJ_GetInstanceInfo(container.ejID)
        local bossName = boss.name or EJ_GetEncounterInfo(boss.id)

        ---------------------------------------------------------
        -- Store static fields
        ---------------------------------------------------------
        entry.itemID         = itemID
        entry.name           = name or ("Item "..itemID)
        entry.slot           = equipLoc
        entry.slotID         = CCS.EQUIPLOC_TO_SLOTID[equipLoc] or 0
        entry.armorType      = armorType
        entry.primary        = primary
        entry.secondary      = secondary

        -- ⭐ Correct numeric class/subclass IDs
        entry.itemClassID    = itemClassID
        entry.itemSubClassID = itemSubClassID

        entry.source = {
            type         = container.type,
            ejID         = container.ejID,
            classID      = container.classID,
            instanceName = instanceName,
            bossID       = boss.id,
            bossName     = bossName,
        }

        entry.seasons = entry.seasons or {}
        entry.seasons[seasonName] = true

        ---------------------------------------------------------
        -- Runtime fields (dummy placeholders)
        ---------------------------------------------------------
        entry.runtime = {
            ilvl = 0,
            track = nil,
            rank = 0,
            stats = {
                crit = 0,
                haste = 0,
                mastery = 0,
                vers = 0,
                str = 0,
                agi = 0,
                int = 0,
            }
        }

        CCS.MasterLoot[itemID] = entry
    end)
end

function CCS.BuildMasterLoot()
    local season =  CCS.Season

    if season == nil then return end -- Bail if season doesn't exist.
    
    local seasonName = season.seasonName

        -- Dungeons
        for ejID, dungeon in pairs(season.dungeons) do
            dungeon.type = "dungeon"
            for _, boss in ipairs(dungeon.bosses) do
                for _, item in ipairs(boss.loot) do
                    AddItemToMaster(item.itemID, dungeon, boss, seasonName)
                end
            end
        end

        ---------------------------------------------------------
        -- Raids (skip ones not yet in EJ so we can pre-load stuff from the PTR)
        ---------------------------------------------------------
        for ejID, raid in pairs(season.raids) do
            -- Skip future raids
            if not EJ_GetInstanceInfo(ejID) then
                -- print("Skipping raid", ejID, "(EJ data not available yet)")
            else
                raid.type = "raid"

                for _, boss in ipairs(raid.bosses) do
                    -- Skip bosses not yet in EJ
                    if EJ_GetEncounterInfo(boss.id) then
                        for _, item in ipairs(boss.loot) do
                            AddItemToMaster(item.itemID, raid, boss, seasonName)
                        end
                    end
                end
            end
        end

        -- Class Sets
        if season.classSets then
            for classID, classSet in pairs(season.classSets) do
                if classSet.items then
                    classSet.type = "classset"
                    classSet.ejID = classID       -- used for uniqueness
                    classSet.classID = classID    -- ⭐ store class ID explicitly
                    classSet.instanceName = "Class Sets"

                    local classInfo = { id = 0, name = select(1, GetClassInfo(classID)) or " "}

                    for _, entry in ipairs(classSet.items) do
                        AddItemToMaster(entry.itemID, classSet, classInfo, seasonName)
                    end
                end
            end
        end
        
end

CCS.BuildMasterLoot()
