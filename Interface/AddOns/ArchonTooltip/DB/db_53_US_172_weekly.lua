local V2_TAG_NUMBER = 4

---@param v2Rankings ProviderProfileV2Rankings
---@return ProviderProfileSpec
local function convertRankingsToV1Format(v2Rankings, difficultyId, sizeId)
	---@type ProviderProfileSpec
	local v1Rankings = {}
	v1Rankings.progress = v2Rankings.progressKilled
	v1Rankings.total = v2Rankings.progressPossible
	v1Rankings.average = v2Rankings.bestAverage
	v1Rankings.spec = v2Rankings.spec
	v1Rankings.asp = v2Rankings.allStarPoints
	v1Rankings.rank = v2Rankings.allStarRank
	v1Rankings.difficulty = difficultyId
	v1Rankings.size = sizeId

	v1Rankings.encounters = {}
	for id, encounter in pairs(v2Rankings.encountersById) do
		v1Rankings.encounters[id] = {
			kills = encounter.kills,
			best = encounter.best,
		}
	end

	return v1Rankings
end

---Convert a v2 profile to a v1 profile
---@param v2 ProviderProfileV2
---@return ProviderProfile
local function convertToV1Format(v2)
	---@type ProviderProfile
	local v1 = {}
	v1.subscriber = v2.isSubscriber
	v1.perSpec = {}

	if v2.summary ~= nil then
		v1.progress = v2.summary.progressKilled
		v1.total = v2.summary.progressPossible
		v1.totalKillCount = v2.summary.totalKills
		v1.difficulty = v2.summary.difficultyId
		v1.size = v2.summary.sizeId
	else
		local bestSection = v2.sections[1]
		v1.progress = bestSection.anySpecRankings.progressKilled
		v1.total = bestSection.anySpecRankings.progressPossible
		v1.average = bestSection.anySpecRankings.bestAverage
		v1.totalKillCount = bestSection.totalKills
		v1.difficulty = bestSection.difficultyId
		v1.size = bestSection.sizeId
		v1.anySpec = convertRankingsToV1Format(bestSection.anySpecRankings, bestSection.difficultyId, bestSection.sizeId)
		for i, rankings in pairs(bestSection.perSpecRankings) do
			v1.perSpec[i] = convertRankingsToV1Format(rankings, bestSection.difficultyId, bestSection.sizeId)
		end
		v1.encounters = v1.anySpec.encounters
	end

	if v2.mainCharacter ~= nil then
		v1.mainCharacter = {}
		v1.mainCharacter.spec = v2.mainCharacter.spec
		v1.mainCharacter.average = v2.mainCharacter.bestAverage
		v1.mainCharacter.difficulty = v2.mainCharacter.difficultyId
		v1.mainCharacter.size = v2.mainCharacter.sizeId
		v1.mainCharacter.progress = v2.mainCharacter.progressKilled
		v1.mainCharacter.total = v2.mainCharacter.progressPossible
		v1.mainCharacter.totalKillCount = v2.mainCharacter.totalKills
	end

	return v1
end

---Parse a single set of rankings from `state`
---@param decoder BitDecoder
---@param state ParseState
---@param lookup table<number, string>
---@return ProviderProfileV2Rankings
local function parseRankings(decoder, state, lookup)
	---@type ProviderProfileV2Rankings
	local result = {}
	result.spec = decoder.decodeString(state, lookup)
	result.progressKilled = decoder.decodeInteger(state, 1)
	result.progressPossible = decoder.decodeInteger(state, 1)
	result.bestAverage = decoder.decodePercentileFixed(state)
	result.allStarRank = decoder.decodeInteger(state, 3)
	result.allStarPoints = decoder.decodeInteger(state, 2)

	local encounterCount = decoder.decodeInteger(state, 1)
	result.encountersById = {}
	for i = 1, encounterCount do
		local id = decoder.decodeInteger(state, 4)
		local kills = decoder.decodeInteger(state, 2)
		local best = decoder.decodeInteger(state, 1)
		local isHidden = decoder.decodeBoolean(state)

		result.encountersById[id] = { kills = kills, best = best, isHidden = isHidden }
	end

	return result
end

---Parse a binary-encoded data string into a provider profile
---@param decoder BitDecoder
---@param content string
---@param lookup table<number, string>
---@param formatVersion number
---@return ProviderProfile|ProviderProfileV2|nil
local function parse(decoder, content, lookup, formatVersion) -- luacheck: ignore 211
	-- For backwards compatibility. The existing addon will leave this as nil
	-- so we know to use the old format. The new addon will specify this as 2.
	formatVersion = formatVersion or 1
	if formatVersion > 2 then
		return nil
	end

	---@type ParseState
	local state = { content = content, position = 1 }

	local tag = decoder.decodeInteger(state, 1)
	if tag ~= V2_TAG_NUMBER then
		return nil
	end

	---@type ProviderProfileV2
	local result = {}
	result.isSubscriber = decoder.decodeBoolean(state)
	result.summary = nil
	result.sections = {}
	result.progressOnly = false
	result.mainCharacter = nil

	local sectionsCount = decoder.decodeInteger(state, 1)
	if sectionsCount == 0 then
		---@type ProviderProfileV2Summary
		local summary = {}
		summary.zoneId = decoder.decodeInteger(state, 2)
		summary.difficultyId = decoder.decodeInteger(state, 1)
		summary.sizeId = decoder.decodeInteger(state, 1)
		summary.progressKilled = decoder.decodeInteger(state, 1)
		summary.progressPossible = decoder.decodeInteger(state, 1)
		summary.totalKills = decoder.decodeInteger(state, 2)

		result.summary = summary
	else
		for i = 1, sectionsCount do
			---@type ProviderProfileV2Section
			local section = {}
			section.zoneId = decoder.decodeInteger(state, 2)
			section.difficultyId = decoder.decodeInteger(state, 1)
			section.sizeId = decoder.decodeInteger(state, 1)
			section.partitionId = decoder.decodeInteger(state, 1) - 128
			section.totalKills = decoder.decodeInteger(state, 2)

			local specCount = decoder.decodeInteger(state, 1)
			section.anySpecRankings = parseRankings(decoder, state, lookup)

			section.perSpecRankings = {}
			for j = 1, specCount - 1 do
				local specRankings = parseRankings(decoder, state, lookup)
				table.insert(section.perSpecRankings, specRankings)
			end

			table.insert(result.sections, section)
		end
	end

	local hasMainCharacter = decoder.decodeBoolean(state)
	if hasMainCharacter then
		---@type ProviderProfileV2MainCharacter
		local mainCharacter = {}
		mainCharacter.zoneId = decoder.decodeInteger(state, 2)
		mainCharacter.difficultyId = decoder.decodeInteger(state, 1)
		mainCharacter.sizeId = decoder.decodeInteger(state, 1)
		mainCharacter.progressKilled = decoder.decodeInteger(state, 1)
		mainCharacter.progressPossible = decoder.decodeInteger(state, 1)
		mainCharacter.totalKills = decoder.decodeInteger(state, 2)
		mainCharacter.spec = decoder.decodeString(state, lookup)
		mainCharacter.bestAverage = decoder.decodePercentileFixed(state)

		result.mainCharacter = mainCharacter
	end

	local progressOnly = decoder.decodeBoolean(state)
	result.progressOnly = progressOnly

	if formatVersion == 1 then
		return convertToV1Format(result)
	end

	return result
end
--- the utf8 global is not available, so we polyfill utf8.offset so we can correctly find prefixes of utf8 strings
---@param str string
---@param index number
---@return number|nil
local function Utf8Offset(str, index)
	local len = #str

	if index <= 0 or index > len then
		return nil -- Out of bounds
	end

	-- Move forward to the nth character
	local count = 0
	for i = 1, len do
		local byte = string.byte(str, i)
		local isContinuationByte = byte >= 128 and byte < 192
		if not isContinuationByte then
			count = count + 1
			if count == index then
				return i
			end
		end
	end

	return nil -- If the nth character is not found
end

---@param table table<string, string> raw data table with character name prefixes as keys
---@param length number the number of complete characters to include in the prefix
---@return fun(characterName: string):string|nil getChunk function to retrieve a character chunk by prefix using a complete character name
local function getChunkLookup(table, length)
	return function(characterName)
		local startOfNextCharacter = Utf8Offset(characterName, length + 1)

		local prefix
		if startOfNextCharacter == nil then
			prefix = characterName
		else
			prefix = string.sub(characterName, 1, startOfNextCharacter - 1)
		end

		return table[prefix]
	end
end

local lookup = {'DeathKnight-Unholy','DeathKnight-Frost','Warrior-Protection','Unknown-Unknown','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Druid-Feral','Druid-Guardian','Evoker-Preservation','DemonHunter-Havoc','Paladin-Retribution','Hunter-BeastMastery','Warrior-Arms','Warrior-Fury','Mage-Arcane','Shaman-Elemental','DemonHunter-Vengeance','Monk-Brewmaster','Monk-Windwalker','DemonHunter-Devourer','Evoker-Devastation','Shaman-Restoration','Paladin-Holy','Priest-Shadow','Priest-Holy','Druid-Restoration','Druid-Balance',}
local provider = {region='US',realm='Perenolde',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aanien:BAAANQADCgYJCAAAAA==.',
Ac='Acedk:BAABNQAECoEYAAMBAAkKWCBACwAzAwABAAkKWCBACwAzAwACAAEK1iLuXQBoAAAAAA==.Aceslam:BAAANQAECggJCwABNQAECgkJGAABAFggAA==.',
Ad='Adrador:BAAANQAECgQIBwAAAA==.Adrenaline:BAABNQAECoEiAAIDAAgK1iGJAwADAwADAAgK1iGJAwADAwAAAA==.',
Ae='Aelik:BAABNQAECoEZAAIBAAYKtQ98RwBtAQABAAYKtQ98RwBtAQAAAA==.Aeolian:BAAANQADCgYIDgAAAA==.Aeru:BAAANQADCgQIBAAAAA==.',
Ak='Akueria:BAAANQADCgcIBwAAAA==.',
Al='Alayssa:BAAANQAECgMJBQAAAA==.Alda:BAAANQADCgUJEAAAAA==.Alemental:BAAANQAECgQIBQAAAA==.Aleska:BAAANQAECgQICAAAAA==.Allarius:BAAANQAECgQIBAAAAA==.Alo:BAAANQAECgYJEAABNQAECgEJAQAEAAAAAA==.',
Am='Amilee:BAAANQADCgYJCAAAAA==.Amoondai:BAAANQADCgYICAAAAA==.Amoondrin:BAAANQAECgYJCAAAAA==.',
An='Analiya:BAAANQADCgQJBQAAAA==.Anatyr:BAAANQADCgYJBgAAAA==.',
Ar='Aramathis:BAAANQAECgUIBQAAAA==.Araviin:BAAANQAECgUIBwAAAA==.Arbor:BAAANQAECgQIBwAAAA==.Arcillias:BAAANQADCgYJBgABNQAECgQJBwAEAAAAAA==.Arilas:BAAANQADCgQJBAABNQAECgQJBwAEAAAAAA==.Arkanist:BAAANQAECgIIAwAAAA==.Arthia:BAAANQADCgYICQAAAA==.Arvidpally:BAAANQAECgEIAQAAAA==.',
As='Ashesius:BAABNQAECoEcAAQFAAgKSBKZCwAeAgAFAAgK3RGZCwAeAgAGAAMKtggxwgCTAAAHAAEKBgHbJgAZAAAAAA==.Ashmehameha:BAAANQADCgYIBgABNQAECgUJBQAEAAAAAA==.',
At='Atredes:BAAANQAECgQICgAAAA==.',
Au='Auspex:BAAANQAECgUICAAAAA==.',
Av='Avaryn:BAAANQAECgcIDAAAAA==.',
Ba='Badaracka:BAABNQAECoEZAAMIAAkK6iHmAQBmAwAIAAkK6iHmAQBmAwAJAAEK9CGCKQBiAAAAAA==.Bahamuth:BAAANQAECgYJEAAAAA==.Bahamutsrage:BAAANQADCgYJBgABNQAECgQIBAAEAAAAAA==.Balder:BAAANQAECgUIBwABNQAFFAIJAwAEAAAAAQ==.Barbattos:BAABNQAECoEgAAIKAAgKJyF2CADoAgAKAAgKJyF2CADoAgAAAA==.',
Bd='Bdyrk:BAAANQAECgUIBQABNQAECgkJGQAIAOohAA==.',
Be='Bealzeboss:BAAANQADCgcJCAAAAA==.Bexley:BAAANQAECgYIDwAAAA==.',
Bi='Biglarry:BAAANQADCgMJBQAAAA==.Biianca:BAAANQADCgUICQAAAA==.',
Bl='Blacklok:BAAANQAECgEJAQABNQAECgkJGQALANghAA==.Blanne:BAAANQABCgIIAgAAAA==.Blargle:BAAANQAECgEJAQAAAA==.Blegh:BAABNQAECoEaAAIMAAkK0SAeEQBNAwAMAAkK0SAeEQBNAwAAAA==.Blinx:BAAANQAECgEIAgAAAA==.Bloodrake:BAABNQAECoEcAAINAAgK7hgVMQBvAgANAAgK7hgVMQBvAgAAAA==.Blueray:BAAANQADCgYIBgAAAA==.',
Bm='Bman:BAAANQAECgIIAgAAAA==.',
Br='Braneour:BAAANQAECgYIEAAAAA==.Browel:BAAANQAECgYICgAAAA==.',
Bu='Bumm:BAAANQADCgIIBAAAAA==.',
Bz='Bzspy:BAABNQAECoEWAAMOAAcKCRjqZADhAQAOAAcKCRjqZADhAQAPAAIK9ApLGwBmAAAAAA==.',
['Bë']='Bëar:BAAANQAECgEIAQAAAA==.',
Ca='Calyptus:BAAANQAECgYIDwAAAA==.Capylaura:BAAANQAECgMIBgAAAA==.Caratine:BAAANQADCgcIDQAAAA==.Cassandrah:BAABNQAECoEYAAIQAAgKDB9JPADXAgAQAAgKDB9JPADXAgAAAA==.',
Ce='Celìa:BAAANQADCggICgAAAA==.',
Ch='Christy:BAAANQADCgUJDwAAAA==.Chugg:BAAANQAECgQJBwAAAA==.',
Ci='Ciaphus:BAAANQAECgYJEQAAAA==.Cinnamonster:BAAANQAECgMIBAAAAA==.',
Cl='Clogs:BAAANQAECgUIBgAAAA==.',
Co='Coffeedemon:BAAANQAECgIJAgAAAA==.Coldslappins:BAAANQADCgUIBQABNQAECgYIEAAEAAAAAA==.Convalescent:BAAANQADCgYIBgAAAA==.Coragrr:BAAANQAECgIIAwAAAA==.',
Cr='Cracklepants:BAABNQAECoEjAAIRAAkK2BWgKAB3AgARAAkK2BWgKAB3AgAAAA==.Crashout:BAAANQADCgYICgAAAA==.',
Cu='Curtastrophe:BAAANQAECgcJEAAAAA==.',
Da='Daelanos:BAAANQAECgUIBQAAAA==.Dallas:BAAANQADCgYICwAAAA==.',
De='Deathoof:BAAANQAECgUJCQABNQAECgUIDgAEAAAAAA==.Demonblaze:BAAANQAECgIJAgAAAA==.Demonilla:BAAANQAECgQJCQAAAA==.Destro:BAAANQAECgYJDQAAAA==.',
Di='Dilaudyd:BAAANQADCgYICAAAAA==.Disbeleaf:BAAANQAECgIIAgAAAA==.Dishu:BAAANQABCgQIBAAAAA==.Dispel:BAAANQADCgYIBgAAAA==.Disputatious:BAAANQADCgQIBAAAAA==.',
Dn='Dntblink:BAAANQADCgUIBQAAAA==.',
Do='Dogaz:BAAANQADCgUJDwAAAA==.Dogsoldier:BAAANQADCgQIBAAAAA==.Donori:BAAANQADCgEIAQAAAA==.Doomphoenix:BAAANQADCgQJBAAAAA==.',
Dr='Dragonias:BAAANQAECgEIAQAAAA==.Drakthorn:BAAANQADCgcIDAAAAA==.Drinny:BAAANQAECgYJDgAAAA==.Dripington:BAABNQAECoEWAAMCAAcKjR+WFQBpAgACAAcKjR+WFQBpAgABAAEKGRPajQA9AAAAAA==.',
Ea='Earthangel:BAAANQAECgEIAQAAAA==.',
Ef='Efon:BAAANQADCgUIBQABNQAECgMJBQAEAAAAAA==.',
Ei='Eine:BAAANQAECgYIEQAAAA==.',
El='Eldergreen:BAAANQAECgQICwAAAA==.Elfwine:BAAANQAECgEIAQAAAA==.Elindria:BAABNQAECoEZAAMLAAkK2CERBQB3AwALAAkK2CERBQB3AwASAAEKLQrxHQA3AAAAAA==.Elminstir:BAAANQAECgUJBwAAAA==.Eluzhion:BAAANQADCgUICAAAAA==.Elysian:BAAANQAECgUICQAAAA==.',
Er='Erizhal:BAAANQABCgIIAgAAAA==.Eruptyon:BAAANQAECgEIAQABNQAECgQJCgAEAAAAAA==.',
Es='Esabel:BAAANQAECgQIBwABNQAECgMJBQAEAAAAAA==.',
Ev='Eviae:BAAANQAECgEIAQAAAA==.Evillure:BAAANQAECgQJBAAAAA==.',
Ex='Explanation:BAAANQADCgQIBAAAAA==.',
Fa='Falan:BAAANQAECgEIAQAAAA==.Farfins:BAAANQADCgYIBgAAAA==.',
Fe='Fedor:BAAANQADCggICAAAAA==.Feår:BAAANQAECgQIBwAAAA==.',
Fi='Finley:BAAANQADCgQIBAAAAA==.Fixation:BAAANQABCgIIAgAAAA==.',
Fl='Flane:BAACNQAFFIEHAAITAAUKHBZhAQCAAQATAAUKHBZhAQCAAQA1AAQKgRwAAxMACQp+HXkEANYCABMACQp+HXkEANYCABQAAQonHTNBAFQAAAAA.Flexdruid:BAAANQADCgQIBgAAAA==.',
Fr='Fragil:BAAANQAECgcJEAAAAA==.',
Ga='Galena:BAAANQAECgEIAQAAAA==.Galian:BAAANQADCgIJAgAAAA==.Ganonn:BAAANQAECgMJBQAAAA==.',
Ge='Geshtal:BAAANQAECgQJBAAAAA==.',
Gi='Girion:BAAANQAECgEIAQAAAA==.',
Gl='Glaiven:BAEBNQAECoEiAAMLAAgKFyFHEADJAgALAAgKQCBHEADJAgAVAAcKzxj+HwD4AQAAAA==.Glyr:BAAANQAECgEJAQAAAA==.',
Go='Gorgrin:BAAANQADCggIEQAAAA==.',
Gr='Groguu:BAAANQAECgQIBAABNQAECgkJGAABAFggAA==.',
Ha='Harkanum:BAABNQAECoEcAAMWAAgK/wxxFwB1AQAWAAcKdglxFwB1AQAKAAgKjgQGHwBkAQAAAA==.Harvester:BAAANQAECgMJBQAAAA==.',
He='Healinturds:BAAANQADCgEIAQAAAA==.Helloagain:BAAANQAECggJEgAAAA==.',
Hi='Hidethetotem:BAAANQAECgEIAQAAAA==.Hikari:BAABNQAECoEXAAIMAAkKqhkbKwCwAgAMAAkKqhkbKwCwAgAAAA==.',
Ho='Holyrebel:BAAANQADCgQIBAABNQADCgcIFQAEAAAAAA==.Holyspike:BAAANQAECgEIAQAAAA==.Homerr:BAAANQADCgcIDgAAAA==.Honiahaka:BAAANQAECgYJEQAAAA==.Hotsdog:BAAANQADCgIIAgAAAA==.Hottcakes:BAAANQAECgcIEgABNQAFFAYIDgAGAKcRAA==.',
Hu='Humanoidlite:BAAANQAECgIIAgABNQAECgkJHwAOACsbAA==.Humanoidlock:BAAANQADCgYIDAABNQAECgkJHwAOACsbAA==.Humanoidwar:BAABNQAECoEfAAMOAAkKKxvdJgDVAgAOAAkKKxvdJgDVAgADAAIK8QU8KABKAAAAAA==.',
In='Inoru:BAAANQADCggIEgAAAA==.',
Ir='Irmaline:BAAANQAECgEIAQAAAA==.',
It='Ithurtshuh:BAAANQADCgEIAQABNQADCgcIFQAEAAAAAA==.',
Ja='Jabbawockie:BAAANQAECggICAAAAA==.Jackcat:BAAANQADCgMJAgAAAA==.',
Je='Jeffee:BAAANQAECgQJCQAAAA==.Jennifleur:BAAANQADCgcIBwAAAA==.Jerk:BAACNQAFFIEGAAIVAAQKLR8nBACLAQAVAAQKLR8nBACLAQA1AAQKgSUAAhUACQrtJPIBALUDABUACQrtJPIBALUDAAAA.Jesper:BAABNQAECoEcAAIXAAgK5hwUHQCnAgAXAAgK5hwUHQCnAgAAAA==.Jetz:BAAANQAECgQJBgAAAA==.',
Ji='Jilara:BAAANQAECgIJAgAAAA==.Jimmyjim:BAAANQAECgEIAQAAAA==.',
Jo='Jockko:BAAANQADCggICAAAAA==.Joink:BAAANQADCgYICQAAAA==.',
Jp='Jpepps:BAABNQAECoEXAAMGAAcKXAoNaQCKAQAGAAcKngkNaQCKAQAFAAMKcAT4TQByAAAAAA==.',
Jr='Jrose:BAAANQADCgYIEQAAAA==.',
Ka='Kagozo:BAEANQAECgEIAQABNQAECgIIAgAEAAAAAA==.Kaiatra:BAAANQAECgEIAQAAAA==.Kalamor:BAAANQADCggICAAAAA==.Kaloran:BAAANQAECgUICQAAAA==.Katalaystar:BAAANQADCgYIDAABNQAECgYICwAEAAAAAA==.Katalegdh:BAAANQAECgEIAQAAAA==.Kaìju:BAAANQAECgIIBQAAAA==.',
Kh='Khaelyn:BAAANQADCgIJAgAAAA==.Khai:BAAANQAECggIDAAAAA==.',
Ki='Kiae:BAAANQADCgYJBwAAAA==.Kidneyspears:BAAANQADCgYIBgAAAA==.Kilaura:BAAANQADCgUIBQAAAA==.Kilmandaros:BAAANQADCgIIBAAAAA==.Kimblee:BAAANQADCgQIBAAAAA==.',
Ku='Kudria:BAAANQAECgUJBgAAAA==.Kunei:BAAANQABCgYICQABNQADCgYIBgAEAAAAAA==.Kurdran:BAAANQABCgQIAgAAAA==.Kuroyukihime:BAAANQAECgUJCgAAAA==.',
Ky='Kynae:BAAANQAECgQIDAAAAA==.Kyross:BAAANQABCgIIAgAAAA==.',
['Ká']='Kárma:BAAANQADCgYICwABNQAECgQIBwAEAAAAAA==.',
La='Lashela:BAAANQAECgIJAwAAAA==.Laughter:BAAANQAECgEIAQAAAA==.Laylla:BAAANQAECgEIAQAAAA==.Lazulie:BAAANQADCgYJEwAAAA==.',
Le='Lefnedrav:BAAANQADCgYIBgABNQAECgYIDAAEAAAAAA==.Lektrik:BAAANQADCgYICAAAAA==.Lexapayne:BAAANQADCgEIAQABNQAECgMIBQAEAAAAAA==.Leyra:BAAANQAECgUIBQABNQAECgkJGQALANghAA==.',
Li='Lighthammer:BAAANQADCgcICwAAAA==.Lightmessiah:BAAANQAECgUJDAAAAA==.Lightnig:BAAANQADCgUIBQAAAA==.Lilyvain:BAAANQAECgEJAQAAAA==.Lireal:BAAANQAECgYIDwAAAA==.Livnod:BAAANQADCgYJBgAAAA==.',
Lo='Lonon:BAAANQAECgcJEwAAAA==.Loosescrew:BAAANQADCgQIBQAAAA==.Lorine:BAAANQAECgcJEgAAAA==.',
Lu='Lunara:BAAANQADCgYIDAAAAA==.',
Ly='Lynnethe:BAAANQAECgMIAwAAAA==.',
Ma='Malkiel:BAAANQAECgQICwAAAA==.Mantang:BAAANQABCgIIAgAAAA==.Mastakillah:BAAANQADCgQICAABNQAECgIJBAAEAAAAAA==.',
Me='Meeseeks:BAAANQAECgcIDQAAAA==.Merckel:BAAANQAECgcJEgAAAA==.Messorom:BAAANQABCgEIAQAAAA==.',
Mi='Michello:BAAANQAECgEIAQAAAA==.Mightytot:BAAANQADCgQIBAAAAA==.Millia:BAAANQAECgQJCgAAAA==.Mint:BAABNQAECoEfAAIYAAkKGBWlIwCDAgAYAAkKGBWlIwCDAgAAAA==.Mintberrytea:BAAANQAECgQJBAABNQAECgkJHwAYABgVAA==.Misstress:BAAANQAECgQICAAAAA==.',
Mo='Moistweaver:BAAANQADCgYJBgAAAA==.Monoxide:BAAANQADCgUIBQABNQAECgYJDwAEAAAAAA==.Moonhunt:BAAANQADCggJHgAAAA==.Morkleb:BAAANQAECgEIAQAAAA==.Morrag:BAAANQAECgQIBgAAAA==.Morrtisha:BAAANQAECgUICQAAAA==.',
My='Myxie:BAAANQAECgQJBgAAAA==.',
['Mí']='Mísfìt:BAABNQAECoEYAAIXAAgKpR1eGQC/AgAXAAgKpR1eGQC/AgAAAA==.',
Na='Nakaito:BAAANQAECgIJAgABNQAECgYIDQAEAAAAAA==.Narcoleptic:BAABNQAECoEaAAMKAAgKrBQjEwAiAgAKAAgKrBQjEwAiAgAWAAUKPw81HAAiAQAAAA==.Nashty:BAAANQADCgIIAgAAAA==.Naturaljuice:BAAANQAECgcICAABNQAFFAYIDgAGAKcRAA==.Naturebreakr:BAAANQAECgQIBAAAAA==.',
Ne='Nex:BAAANQAECgYJCgAAAA==.',
Ni='Nightsawdy:BAAANQAECgEJAgAAAA==.Niightstorm:BAAANQAECgEIAQAAAA==.Nilvannas:BAAANQADCggICAAAAA==.Nitefire:BAAANQADCgUJEAAAAA==.Nitélifé:BAAANQADCgcJDAAAAA==.',
Of='Offspring:BAAANQABCgIIAgAAAA==.',
Om='Omora:BAAANQAECgQJCAABNQAECgYIDAAEAAAAAA==.',
Op='Opalinnas:BAAANQAECgYICwAAAA==.Optimism:BAAANQADCgIIAgAAAA==.',
Pa='Pallyandtank:BAAANQAECgEJAQAAAA==.Panzer:BAAANQAECgQJBwAAAA==.Parts:BAAANQAECgUIBgABNQAECgYJEQAEAAAAAA==.Passionfruit:BAAANQADCgQJBAAAAA==.Paul:BAAANQAECgUJBQAAAA==.',
Pe='Peachtea:BAAANQAECgEJAgAAAA==.Pepecojon:BAAANQADCggIDwAAAA==.',
Pi='Pirodeath:BAAANQAECgUIBQAAAA==.',
Pl='Plovdiv:BAAANQADCgcJCQAAAA==.',
Po='Poah:BAAANQAECgYIBgAAAA==.',
Pr='Pray:BAAANQAECgYJEQAAAA==.Prodarkangel:BAAANQADCgcJCQAAAA==.',
Pu='Puckllane:BAAANQAECgEIAgAAAA==.Punkin:BAAANQADCgMJAwAAAA==.',
Py='Pyre:BAAANQAECgYJEQABNQAECgEJAQAEAAAAAA==.',
['Pü']='Püff:BAAANQADCgEIAQABNQAECgQJBwAEAAAAAA==.',
Qu='Quanah:BAAANQAECgMJBQAAAA==.Quivver:BAAANQADCgUJDAAAAA==.',
Ra='Rabmaxx:BAAANQAECgEIAQAAAA==.Raina:BAAANQADCgYIBgAAAA==.Ravenlight:BAAANQAECgcIDgAAAA==.Ravenwynnd:BAAANQAECgcJEwAAAA==.Raynman:BAAANQAECgYJDwAAAA==.',
Rh='Rhydian:BAAANQADCgQIBAAAAA==.Rhyzer:BAAANQAECgEIAQAAAA==.',
Ri='Riiver:BAAANQADCgYJBgAAAA==.',
Ro='Roderick:BAAANQADCgYJCAAAAA==.Root:BAAANQADCgQICAABNQAECggIHwABAEkdAA==.',
Ru='Rubmytotem:BAAANQAECgQJBQAAAA==.',
Sa='Sabazia:BAAANQAECgYIEAAAAA==.Sabelinå:BAAANQADCgYIBgAAAA==.Sable:BAAANQADCgEIAQAAAA==.Saerise:BAAANQADCgYIBgAAAA==.Sairalindë:BAAANQAECgEIAQAAAA==.Salamandra:BAAANQADCgQIBAABNQAECgYIDAAEAAAAAA==.Saleath:BAAANQAECgIIAgAAAA==.Salios:BAAANQAECgEIAQAAAA==.Sanara:BAAANQABCgUIBwABNQAECgEIAQAEAAAAAA==.Sanctifier:BAAANQADCgUIBQAAAA==.',
Sc='Scrept:BAAANQAECgcICQAAAA==.Scynix:BAEANQAECgYJCwAAAA==.',
Se='Seizuregoat:BAAANQAECgMJAwAAAA==.Senus:BAAANQADCgEIAQAAAA==.Servoker:BAAANQAECgUIBQAAAA==.',
Sh='Shabzyt:BAAANQAECgQJBgAAAA==.Shaienne:BAAANQADCgcIDgAAAA==.Shammander:BAAANQADCgcJDgAAAA==.Shamrockshak:BAAANQAECgIIBAAAAA==.Shenuton:BAAANQADCgMIAwAAAA==.Shieldbash:BAABNQAECoEbAAIDAAgKhCW+AQByAwADAAgKhCW+AQByAwAAAA==.Shockthêràpy:BAABNQAECoEfAAMXAAkKHCAxDAAqAwAXAAkKHCAxDAAqAwARAAEKzw7/0wA7AAAAAA==.Shoes:BAAANQAECgYICgAAAA==.Shtdruid:BAAANQAECgEIAQAAAA==.',
Si='Sibearian:BAAANQAECgUIDgAAAA==.Simi:BAAANQAECgMIBQAAAA==.',
Sm='Smokesçreen:BAAANQAECgYJEQAAAA==.',
So='Soonerpride:BAAANQAECgMJBQAAAA==.Soothed:BAAANQADCggICAAAAA==.',
Sp='Spearminttea:BAAANQADCgIIAgAAAA==.Spellbreakr:BAAANQAFFAEJAQAAAA==.Spirtbreaker:BAAANQAECgQICAAAAA==.',
Sq='Squeak:BAAANQADCgEJAQAAAA==.Squiby:BAABNQAECoEaAAMZAAgKMR5RDQDMAgAZAAgKMR5RDQDMAgAaAAEKlxW8pwA8AAAAAA==.',
St='Stankowitz:BAAANQABCgQICAABNQADCgYIBgAEAAAAAA==.Starboi:BAAANQADCgUIBQAAAA==.Starce:BAAANQABCgMIAwAAAA==.Steveirwin:BAAANQADCgUIBQAAAA==.Stheris:BAAANQAECgIJAgAAAA==.Stuefester:BAAANQAECgYIEQAAAA==.',
Sv='Sveika:BAAANQAECgEIAQAAAA==.',
Sy='Sylaria:BAEANQADCgYJCAAAAA==.Syreline:BAAANQAECgEIAQAAAA==.',
['Sï']='Sïn:BAAANQAECgIJBAAAAA==.',
['Sý']='Sýlver:BAAANQAECgUIDAAAAA==.',
Ta='Tarpalantir:BAAANQADCgcICAAAAA==.Taurne:BAABNQAECoEbAAMbAAgK8hqFDwByAgAbAAgK8hqFDwByAgAcAAMKiQUbbQCDAAAAAA==.',
Tc='Tchnce:BAAANQADCgcICgAAAA==.',
Te='Teknoman:BAAANQAECgYIEAAAAA==.Telephone:BAAANQAECgEIAwAAAA==.Tempered:BAAANQAECgYJEQAAAA==.Teresen:BAAANQADCgIIAgAAAA==.',
Th='Thaitea:BAAANQADCgIIBAAAAA==.Thalindra:BAAANQAECgEIAQAAAA==.Tharain:BAAANQADCgUJEAAAAA==.Thebigbeast:BAAANQAECgQIBwABNQAFFAYIDgAGAKcRAA==.Thecurt:BAAANQAECgYJEQAAAA==.Thunderrbutt:BAAANQAECgQIDAAAAA==.Thyralizen:BAAANQADCgIIAgAAAA==.',
Ti='Tiael:BAAANQAECgIIAgAAAA==.Timaeus:BAAANQADCgUJCwAAAA==.Tinylef:BAAANQAECgYIDAAAAA==.Tirouke:BAAANQAECgEIAQAAAA==.Titanlock:BAAANQADCgQJBgAAAA==.',
Tk='Tkdfath:BAAANQADCgYIBgAAAA==.',
To='Toralina:BAAANQAECgEIAQAAAA==.Torvia:BAAANQADCgYJCAAAAA==.',
Tr='Trisinz:BAAANQAECgUJCQAAAA==.',
Tu='Tuerto:BAAANQAECgQIBgAAAA==.Turbojohnson:BAAANQAECgEIAQAAAA==.Turk:BAABNQAECoEbAAIVAAgKag10HwD+AQAVAAgKag10HwD+AQAAAA==.Turkish:BAAANQAECgYIDQAAAA==.',
Tw='Twinkytoes:BAAANQADCggJEQAAAA==.',
Ty='Tychaa:BAAANQADCgUJDAAAAA==.Tyranax:BAAANQAECgIJBQAAAA==.Tyrith:BAAANQADCgMJAwAAAA==.',
Ul='Ullyr:BAAANQAECgYIBwABNQAECgkJIwARANgVAA==.',
Us='Userdel:BAAANQAECgQIBwAAAA==.',
Va='Valytrois:BAAANQAECgEIAQAAAA==.Variant:BAAANQAECgMIAwAAAA==.Vauld:BAAANQADCgQJBQAAAA==.',
Ve='Veiksla:BAAANQADCgUJDgAAAA==.Vengerr:BAAANQADCgUJCQAAAA==.Verace:BAAANQAECgEIAQAAAA==.Verradic:BAAANQAECgQIBAAAAA==.',
Vi='Vitur:BAABNQAECoEeAAIVAAgK1yIzCAAxAwAVAAgK1yIzCAAxAwAAAA==.Vivi:BAAANQADCgYIBgAAAA==.',
Vo='Voidbunny:BAAANQAECgYJDwAAAA==.Volaine:BAAANQAECgEIAQAAAA==.Volgar:BAAANQADCgEIAQAAAA==.Volition:BAAANQADCgYIBgAAAA==.Volt:BAAANQAECgUIBwABNQAECgYJDQAEAAAAAA==.',
Vr='Vrye:BAAANQAECggIBwAAAA==.',
Vy='Vynaeda:BAAANQAECgUIDQAAAA==.',
['Vô']='Vôx:BAAANQAECgIIBQAAAA==.',
Wa='Wakko:BAAANQADCgcIEwAAAA==.Walkure:BAAANQADCgUJEAAAAA==.',
We='Weirdscience:BAAANQABCgQIBAAAAA==.',
Wh='Whew:BAAANQADCgIIAgAAAA==.',
Wi='Wikker:BAAANQADCgQIBAAAAA==.',
Wr='Wreckbums:BAAANQAECgMIBAAAAA==.Wreckd:BAAANQADCgYIBgABNQAECgYJEQAEAAAAAA==.Wrongway:BAAANQADCgIJAgAAAA==.',
Xa='Xanthad:BAAANQADCgUICAAAAA==.',
Xb='Xb:BAAANQADCgUJEAAAAA==.',
Xi='Xitãozinho:BAAANQADCgYIBgAAAA==.',
Xy='Xyomi:BAAANQADCgIJAgAAAA==.',
Ya='Yaalia:BAAANQAECgEIAQAAAA==.Yaan:BAAANQAECgIIAwAAAA==.',
Za='Zain:BAAANQADCgYIBgABNQAECggIHAAFAEgSAA==.Zandibar:BAAANQAECgEIAQAAAA==.Zaptoasted:BAAANQADCgYIBgAAAA==.Zariea:BAAANQAECgIIAgABNQAECgcIGQABALUPAA==.Zavac:BAAANQADCgUIBwAAAA==.',
Ze='Zelritch:BAAANQADCggICAAAAA==.',
Zi='Zinfandell:BAAANQAECgMJAwAAAA==.',
Zo='Zorrloc:BAAANQADCgQIBAAAAA==.',
Zu='Zuggie:BAAANQADCgUJEAABNQAECgEIAQAEAAAAAA==.Zugtail:BAAANQAECgEIAQAAAA==.Zurtrinik:BAAANQAECgUIBwABNQAFFAUJBwATABwWAA==.',
Zy='Zyntalla:BAAANQAECgEIAQAAAA==.',
Zz='Zzonked:BAAANQAECgEIAQAAAA==.',
['Zê']='Zêp:BAAANQADCgcIFwAAAA==.',
['Àr']='Àrròw:BAAANQADCgYJCgAAAA==.',
['Ðo']='Ðoogle:BAAANQAECgEIAQABNQABCgMIAwAEAAAAAA==.',
},}
provider.parse = parse

local rawData = provider.data
provider.data = {}
provider.getChunk = getChunkLookup(rawData, 2)

provider.splitId = 0
provider.splitCount = 1
provider.splitType = 'none'

setmetatable(provider.data, {
	__index = function(table, key)
		provider.getChunk(key)
	end,
})

if _G["ArchonTooltip"] and ArchonTooltip.AddProviderV2 then
	ArchonTooltip.AddProviderV2(lookup, provider)
end
