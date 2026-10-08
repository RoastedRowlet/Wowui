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

local lookup = {'DeathKnight-Unholy','DeathKnight-Frost','Warrior-Arms','Warrior-Protection','Shaman-Restoration','Unknown-Unknown','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','Druid-Restoration','Druid-Feral','Druid-Guardian','Paladin-Retribution','Evoker-Preservation','Paladin-Protection','DemonHunter-Havoc','Hunter-BeastMastery','Paladin-Holy','Warrior-Fury','Mage-Arcane','Shaman-Elemental','Mage-Frost','DeathKnight-Blood','Priest-Holy','DemonHunter-Vengeance','Monk-Brewmaster','Monk-Windwalker','Rogue-Assassination','Rogue-Subtlety','DemonHunter-Devourer','Evoker-Devastation','Priest-Discipline','Priest-Shadow','Druid-Balance','Monk-Mistweaver','Shaman-Enhancement',}
local provider = {region='US',realm='Perenolde',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aanien:BAAANQADCgYICAAAAA==.',
Ac='Acedk:BAABNQAECoEhAAMBAAkKSSJAFQD4AgABAAkKMiFAFQD4AgACAAUKKyEyNQDIAQABNQAECggIFQADAIwhAA==.Aceslam:BAABNQAECoEVAAIDAAgKjCHoKgD+AgADAAgKjCHoKgD+AgAAAA==.',
Ad='Adrador:BAAANQAECgYIEgAAAA==.Adrenaline:BAABNQAECoEwAAIEAAkKKyTSAQCYAwAEAAkKKyTSAQCYAwAAAA==.',
Ae='Aelik:BAABNQAECoEfAAIBAAYKSBiWXQByAQABAAYKSBiWXQByAQAAAA==.Aeolian:BAAANQADCgYIDgAAAA==.Aeru:BAAANQADCgQIBAAAAA==.',
Ak='Akueria:BAAANQADCgcIBwAAAA==.',
Al='Alayssa:BAAANQAECgUIDQAAAA==.Alda:BAAANQADCgYIFgAAAA==.Alemental:BAAANQAECgYICwAAAA==.Aleska:BAAANQAECgQIDwAAAA==.Allarius:BAAANQAECgQIBAAAAA==.Alo:BAABNQAECoEhAAIFAAgKGBbLTAAEAgAFAAgKGBbLTAAEAgABNQAECgEJAQAGAAAAAA==.',
Am='Amilee:BAAANQADCggICgAAAA==.Amoondai:BAAANQADCgYICAAAAA==.Amoondrin:BAAANQAECgcIEQAAAA==.',
An='Analiya:BAAANQADCgQJBQAAAA==.Anatyr:BAAANQADCggICAAAAA==.',
Ar='Aramathis:BAAANQAECgUIBQAAAA==.Araviin:BAAANQAECgUICAAAAA==.Arbor:BAAANQAECgQIBwAAAA==.Arcillias:BAAANQADCgYICAABNQAECgQJBwAGAAAAAA==.Arilas:BAAANQAECgQICAABNQAECgQJBwAGAAAAAA==.Arkanist:BAAANQAECgUICwAAAA==.Arthia:BAAANQADCgYICQAAAA==.Arvidpally:BAAANQAECgQIBwAAAA==.',
As='Asclepias:BAAANQADCgQIBAAAAA==.Ashesius:BAABNQAECoEsAAQHAAgKEhq9CgBCAgAHAAgKGRe9CgBCAgAIAAIKrxOPGgCLAAAJAAMKtghBAwGHAAAAAA==.Ashmehameha:BAAANQAECgEIAQABNQAECgYIDQAGAAAAAA==.',
At='Atredes:BAAANQAECgYIDQAAAA==.',
Au='Auspex:BAAANQAECgYIEwAAAA==.',
Av='Avaryn:BAABNQAECoEaAAIKAAkKiBaZGgA6AgAKAAkKiBaZGgA6AgAAAA==.',
Ax='Aximlii:BAAANQADCgUICQAAAA==.',
Ba='Babs:BAAANQADCgMIAwAAAA==.Badaracka:BAACNQAFFIEHAAILAAQKhw9JAQBSAQALAAQKhw9JAQBSAQA1AAQKgSYAAwsACQr5IskCAGsDAAsACQr5IskCAGsDAAwABQqWHlcXALUBAAAA.Bahamuth:BAABNQAECoEjAAINAAgKWRaBdwAOAgANAAgKWRaBdwAOAgAAAA==.Bahamutsrage:BAAANQADCggIDgABNQAECgQIBAAGAAAAAA==.Balder:BAAANQAECgcIDgABNQAFFAIIBgAGAAAAAQ==.Barbattos:BAABNQAECoEsAAIOAAkKFCJ0BQBJAwAOAAkKFCJ0BQBJAwAAAA==.',
Bd='Bdyrk:BAAANQAECgYICgABNQAFFAQIBwALAIcPAA==.',
Be='Bealzeboss:BAAANQADCgcICQAAAA==.Bexley:BAABNQAECoEfAAIPAAgKyx2tDQCdAgAPAAgKyx2tDQCdAgAAAA==.',
Bi='Biggerbunny:BAAANQAECgcIDgAAAA==.Biglarry:BAAANQADCgMJBQAAAA==.Biianca:BAAANQADCgUICQAAAA==.',
Bl='Blacklok:BAAANQAECgIIBAABNQAECgkJIwAQAP4jAA==.Blanne:BAAANQABCgIIAgAAAA==.Blargle:BAAANQAECgIIAwAAAA==.Blegh:BAABNQAECoEgAAINAAkKTyEzIQAnAwANAAkKTyEzIQAnAwAAAA==.Blessyaheart:BAAANQAECgUIBQABNQAECgYIEwAGAAAAAA==.Blinx:BAAANQAECgEIAgAAAA==.Bloodrake:BAABNQAECoEkAAIRAAgKUxmyUwBNAgARAAgKUxmyUwBNAgAAAA==.Blueray:BAAANQADCgYIBgAAAA==.',
Bm='Bman:BAAANQAECgUICwAAAA==.',
Br='Braneour:BAABNQAECoEiAAMPAAgK0BS2IACzAQAPAAgK0BS2IACzAQASAAYK1QeOnwAbAQAAAA==.Browel:BAABNQAECoEXAAIJAAcKBBdAagD3AQAJAAcKBBdAagD3AQAAAA==.',
Bu='Bubblfett:BAAANQADCggICAAAAA==.Bumm:BAAANQAECgMIAwAAAA==.',
Bz='Bzspy:BAABNQAECoEdAAMDAAkKkhbwXgBSAgADAAkKkhbwXgBSAgATAAIK9ApWJQBgAAAAAA==.',
['Bë']='Bëar:BAAANQAECgEIAQAAAA==.',
Ca='Calyptus:BAABNQAECoEVAAIHAAcKGgsuIABlAQAHAAcKGgsuIABlAQAAAA==.Capylaura:BAAANQAECgMIBgAAAA==.Caratine:BAAANQADCgcIDQAAAA==.Cassandrah:BAABNQAECoEgAAIUAAgKDB81XgCwAgAUAAgKDB81XgCwAgAAAA==.',
Ce='Celìa:BAAANQAECgUIBQAAAA==.',
Ch='Chillymage:BAAANQADCgcIBwAAAA==.Christy:BAAANQADCgYIFQAAAA==.Chugg:BAAANQAECgUIEAAAAA==.',
Ci='Ciaphus:BAABNQAECoEkAAQNAAgKShCEmAC8AQANAAgKShCEmAC8AQASAAcKawrNfQB2AQAPAAMKtwoEUAB2AAAAAA==.Cinnamonster:BAAANQAECgQICgAAAA==.',
Cl='Clogs:BAAANQAECgUIBgAAAA==.',
Co='Coffeedemon:BAAANQAECgQIBgAAAA==.Coldslappins:BAAANQADCgcIBwABNQAECggIIgAPANAUAA==.Convalescent:BAAANQADCgYIBgAAAA==.Coragrr:BAAANQAECgIIAwAAAA==.',
Cr='Cracklepants:BAACNQAFFIEKAAIVAAUKpAh5DABqAQAVAAUKpAh5DABqAQA1AAQKgS8AAhUACQqyHkkYACEDABUACQqyHkkYACEDAAAA.Crashout:BAAANQAECgYIBgAAAA==.',
Cu='Curtastrophe:BAABNQAECoEhAAIWAAgKHSBAAwD3AgAWAAgKHSBAAwD3AgAAAA==.Curticus:BAAANQADCgYIBgAAAA==.',
Da='Daelanos:BAAANQAECgYIEAAAAA==.Dallas:BAAANQADCgYICwAAAA==.',
De='Deathisreal:BAAANQADCgEIAgABNQAECgEIAQAGAAAAAA==.Deathoof:BAABNQAECoEWAAQBAAcKKBScWQCCAQABAAYKdxWcWQCCAQAXAAEKTwzXugA0AAACAAEKGgXFmQArAAAAAA==.Demonblaze:BAAANQAECgIJAgAAAA==.Demonilla:BAAANQAFFAEIAQAAAA==.Destro:BAABNQAECoEfAAIJAAgKcAuHfgC+AQAJAAgKcAuHfgC+AQAAAA==.',
Di='Dilaudyd:BAAANQADCgcICQAAAA==.Disbeleaf:BAAANQAECgYIDQAAAA==.Dishu:BAAANQABCgQIBAAAAA==.Dispel:BAAANQADCgYIBgAAAA==.Disputatious:BAAANQADCgQIBAAAAA==.',
Dn='Dntblink:BAAANQADCgUIBQAAAA==.',
Do='Dogaz:BAAANQADCgYIFQAAAA==.Dogsoldier:BAAANQADCgQIBAAAAA==.Donori:BAAANQADCgEIAQAAAA==.Doomphoenix:BAAANQADCgQJBAAAAA==.',
Dr='Dragonias:BAAANQAECgQIBwAAAA==.Drakthorn:BAAANQADCggIEwAAAA==.Drinny:BAABNQAECoEZAAIYAAgKEgSfgQBZAQAYAAgKEgSfgQBZAQAAAA==.Dripington:BAABNQAECoEfAAMCAAgKryDMFQC6AgACAAgKryDMFQC6AgABAAEKGRPlygA1AAAAAA==.',
Ea='Earthangel:BAAANQAECgMIBQAAAA==.',
Ef='Efon:BAAANQADCgUIBQABNQAECgUIDQAGAAAAAA==.',
Ei='Eine:BAABNQAECoEfAAIRAAkKfw/TWAA/AgARAAkKfw/TWAA/AgAAAA==.',
El='Eldergreen:BAAANQAECgUIEAAAAA==.Elfwine:BAAANQAECgMIBQAAAA==.Elindria:BAABNQAECoEjAAMQAAkK/iN7BACiAwAQAAkK/iN7BACiAwAZAAEKLQrQKwAxAAAAAA==.Elminstir:BAAANQAECgYIEQAAAA==.Eluzhion:BAAANQADCgUICAAAAA==.Elysian:BAAANQAECgUICQAAAA==.',
Er='Erizhal:BAAANQABCgIIAgAAAA==.Eruptyon:BAAANQAECgEIAQABNQAECgYIFwAUANohAA==.',
Es='Esabel:BAAANQAECgcIDgABNQAECgUIDQAGAAAAAA==.',
Ev='Eviae:BAAANQAECgMIBQAAAA==.Evillure:BAAANQAECgYICgAAAA==.',
Ex='Explanation:BAAANQADCgQIBAAAAA==.',
Fa='Falan:BAAANQAECgEIAQAAAA==.Farfins:BAAANQADCgYIBgAAAA==.',
Fe='Feår:BAAANQAECgUIDAAAAA==.',
Fi='Finley:BAAANQADCgQIBAAAAA==.Fixation:BAAANQABCgIIAgAAAA==.',
Fl='Flane:BAACNQAFFIEQAAIaAAUKORiZAgCPAQAaAAUKORiZAgCPAQA1AAQKgSEAAxoACQq+HygFAPwCABoACQq+HygFAPwCABsAAQonHThYAE8AAAAA.Flexdruid:BAAANQADCgQIBgAAAA==.',
Fr='Fragil:BAABNQAECoEdAAMcAAgKOhvFGwB2AgAcAAgKsRrFGwB2AgAdAAQKGhZqMAAbAQAAAA==.',
Ga='Galena:BAAANQAECgQIBwAAAA==.Galian:BAAANQADCggIDgAAAA==.Ganonn:BAAANQAECgQICQABNQAECgUIBQAGAAAAAA==.',
Ge='Geshtal:BAAANQAECgYICwAAAA==.',
Gi='Girion:BAAANQAECgMIBQAAAA==.',
Gl='Glaiven:BAEBNQAECoEtAAMQAAkK9yH0CwA2AwAQAAkK4iH0CwA2AwAeAAcKzxgyKgDQAQAAAA==.Glyr:BAAANQAECgEJAQAAAA==.',
Gn='Gnora:BAAANQADCgQIBAAAAA==.',
Go='Gorgrin:BAAANQAECgQIBQAAAA==.',
Gr='Groguu:BAAANQAECgQIBAABNQAECggIFQADAIwhAA==.',
Ha='Harkanum:BAABNQAECoEsAAMfAAgK5ggqGgCIAQAfAAgK5ggqGgCIAQAOAAgK6QQ8JwBaAQAAAA==.Harvester:BAAANQAECgMIBwAAAA==.',
He='Healinturds:BAAANQADCgEIAQAAAA==.Helloagain:BAAANQAECggJEgAAAA==.',
Hi='Hidethetotem:BAAANQAECgUIBwAAAA==.Hikari:BAABNQAECoEdAAINAAkKpxyWQQCrAgANAAkKpxyWQQCrAgAAAA==.Hiown:BAAANQABCgYICAAAAA==.',
Ho='Holyrebel:BAAANQAECgEIAQAAAA==.Holyspike:BAAANQAECgQIBwAAAA==.Homerr:BAAANQAECgQIBgAAAA==.Honiahaka:BAABNQAECoEkAAIRAAgKdwrlfQDiAQARAAgKdwrlfQDiAQAAAA==.Hotsdog:BAAANQADCgIIAgAAAA==.Hottcakes:BAABNQAECoEmAAIUAAkKfyASHABeAwAUAAkKfyASHABeAwABNQAFFAcIFAAJAEoVAA==.',
Hu='Humanoidlite:BAAANQAFFAEIAgAAAA==.Humanoidlock:BAAANQADCgYIDAABNQAFFAEIAgAGAAAAAA==.Humanoidwar:BAABNQAECoEmAAMDAAkKDB9yKgAAAwADAAkKDB9yKgAAAwAEAAUKdg0lJAD1AAABNQAFFAEIAgAGAAAAAA==.',
In='Inoru:BAAANQAECgQIBwAAAA==.',
Ir='Irmaline:BAAANQAECgQIBwAAAA==.',
It='Ithurtshuh:BAAANQAECgEIAQABNQAECgEIAQAGAAAAAA==.',
Ja='Jabbawockie:BAABNQAECoEXAAIQAAgKgweEVwDyAAAQAAgKgweEVwDyAAAAAA==.Jackcat:BAAANQADCgQIAwAAAA==.Jackyl:BAAANQABCgIIAgAAAA==.',
Je='Jeffee:BAABNQAECoEVAAICAAcKPRuAKAAhAgACAAcKPRuAKAAhAgAAAA==.Jennifleur:BAAANQADCgcIBwAAAA==.Jequalsjosh:BAAANQAECgcIDQAAAA==.Jerk:BAACNQAFFIEQAAIeAAUKviN5AwAJAgAeAAUKviN5AwAJAgA1AAQKgSsAAh4ACQrtJEYDAJ8DAB4ACQrtJEYDAJ8DAAAA.Jesper:BAABNQAECoEsAAIFAAgKLCDvGwDjAgAFAAgKLCDvGwDjAgAAAA==.Jetz:BAAANQAECgQICQAAAA==.',
Ji='Jilara:BAAANQAECgUICgAAAA==.Jimmyjim:BAAANQAECgQIBwAAAA==.',
Jo='Joink:BAAANQADCgYICQAAAA==.',
Jp='Jpepps:BAABNQAECoEhAAMJAAgK2w0scgDhAQAJAAgK2w0scgDhAQAHAAMKcATsWQBpAAAAAA==.',
Jr='Jrose:BAAANQADCgYIEQAAAA==.',
Ka='Kagozo:BAEANQAECgEIAQABNQAECgIIAgAGAAAAAA==.Kaiatra:BAAANQAECgUIBwAAAA==.Kalamor:BAAANQADCggICAAAAA==.Kaloran:BAAANQAECgUIDAAAAA==.Katalaystar:BAAANQADCgYIDAABNQAECggIIwAKAHAbAA==.Katalegdh:BAAANQAECgIIAgAAAA==.Kative:BAAANQADCgMIAwAAAA==.Kaìju:BAAANQAECgUIDQAAAA==.',
Kh='Khaelyn:BAAANQADCgQIBQAAAA==.Khai:BAAANQAECggIDQAAAA==.',
Ki='Kiae:BAAANQADCgYJBwAAAA==.Kidneyspears:BAAANQADCgYIBgAAAA==.Kilaura:BAAANQADCgUIBQAAAA==.Kilmandaros:BAAANQAECgUIBQAAAA==.Kimblee:BAAANQADCgQIBAAAAA==.',
Ko='Korbix:BAAANQABCgUIBAABNQAECgUIBgAGAAAAAA==.',
Kr='Kronmon:BAAANQADCgQIBAAAAA==.',
Ku='Kudria:BAAANQAECgYIEQAAAA==.Kunei:BAAANQABCgYICQABNQAECgEIAQAGAAAAAA==.Kurdran:BAAANQABCgQIAgAAAA==.Kuroyukihime:BAABNQAECoEbAAIWAAcK8B2VBwBGAgAWAAcK8B2VBwBGAgAAAA==.',
Ky='Kylas:BAAANQADCgMIAwAAAA==.Kynae:BAAANQAECgQIEQAAAA==.Kyross:BAAANQABCgIIAgAAAA==.',
['Ká']='Kárma:BAAANQADCgYICwABNQAECgUIDAAGAAAAAA==.',
La='Lashela:BAAANQAECgUIDQAAAA==.Laughter:BAAANQAECgQIBgAAAA==.Lavamylash:BAAANQAECgUIBQAAAA==.Laylla:BAAANQAECgMIBAAAAA==.Lazulie:BAAANQAECgQIBAAAAA==.',
Le='Lefnedrav:BAAANQADCgYIBgABNQAECggIGQAbAKEXAA==.Lektrik:BAAANQAECgEIAQAAAA==.Lenexa:BAAANQADCgMIAwAAAA==.Lexapayne:BAAANQADCgEIAQABNQAECgcIEQAGAAAAAA==.Leyra:BAAANQAECgYIEQABNQAECgkJIwAQAP4jAA==.',
Li='Lighthammer:BAAANQADCggIDgAAAA==.Lightmessiah:BAABNQAECoEaAAMNAAgKuBmFYQBJAgANAAgKuBmFYQBJAgASAAUK0RFhnQAhAQAAAA==.Lightnig:BAAANQADCgUIBQAAAA==.Lilyvain:BAAANQAECgEIAQAAAA==.Lireal:BAABNQAECoEbAAISAAgK4R9RHQDnAgASAAgK4R9RHQDnAgAAAA==.Livnod:BAAANQADCggICAAAAA==.',
Lo='Lonon:BAAANQAECgcJEwAAAA==.Loosescrew:BAAANQADCgQIBQAAAA==.Lorine:BAABNQAECoEfAAIPAAgKURnPEQBdAgAPAAgKURnPEQBdAgAAAA==.',
Lu='Lunara:BAAANQADCgYIDAAAAA==.',
Ly='Lynnethe:BAAANQAECgYIDgAAAA==.',
Ma='Malkiel:BAAANQAECgQICwAAAA==.Mantang:BAAANQABCgIIAgAAAA==.Mastakillah:BAAANQADCgQICAABNQAECgUIEQAGAAAAAA==.',
Me='Meeseeks:BAAANQAECgcIDQAAAA==.Merckel:BAABNQAECoEmAAIeAAkKtBprEADcAgAeAAkKtBprEADcAgAAAA==.Messorom:BAAANQADCgEIAQAAAA==.',
Mi='Michello:BAAANQAECgQIBwAAAA==.Mightytot:BAAANQADCgYIBwAAAA==.Millia:BAABNQAECoEXAAMUAAYK2iHzugDqAQAUAAUKxSLzugDqAQAWAAEKQx1JNQBPAAAAAA==.Mint:BAABNQAECoEfAAISAAkKGBWCNgBuAgASAAkKGBWCNgBuAgAAAA==.Mintberrytea:BAAANQAECgQJBAABNQAECgkJHwASABgVAA==.Misstress:BAAANQAECgUIEAAAAA==.',
Mo='Moistweaver:BAAANQADCgYJBgAAAA==.Monoxide:BAAANQADCgUIBQABNQAECgYIEwAGAAAAAA==.Mooncloud:BAAANQADCgMIAwAAAA==.Moonhunt:BAAANQADCggIIAAAAA==.Morkleb:BAAANQAECgUIBgAAAA==.Morrag:BAAANQAECgQICwAAAA==.Morrtisha:BAAANQAECgYICwAAAA==.',
Mu='Munden:BAAANQADCgUIBQABNQAECgQICwAGAAAAAA==.',
My='Myxie:BAAANQAECgUIDwAAAA==.',
['Mí']='Mísfìt:BAABNQAECoEhAAIFAAgKyB69JwCkAgAFAAgKyB69JwCkAgAAAA==.',
Na='Nakaito:BAAANQAECgUICwABNQAECggIHQAcAFoRAA==.Narcoleptic:BAABNQAECoEmAAMOAAgKlhbWFABPAgAOAAgKlhbWFABPAgAfAAUKPw9yIwAJAQAAAA==.Nashty:BAAANQADCgIIAgAAAA==.Naturaljuice:BAAANQAECgcICgABNQAFFAcIFAAJAEoVAA==.Naturebreakr:BAAANQAECgcIEAAAAA==.',
Ne='Nex:BAABNQAECoEcAAIUAAkKeB/DNgAOAwAUAAkKeB/DNgAOAwAAAA==.',
Ni='Nightsawdy:BAAANQAECgQICgAAAA==.Niightstorm:BAAANQAECgIIBAAAAA==.Nilvannas:BAAANQADCggICAAAAA==.Nitefire:BAAANQADCgYIFgAAAA==.Nitélifé:BAAANQAECgMIAwAAAA==.',
Of='Offspring:BAAANQABCgIIAgAAAA==.',
Om='Omora:BAAANQAECgUIDQABNQAECggIGQAbAKEXAA==.',
Op='Opalinnas:BAABNQAECoEjAAIKAAgKcBuVEwCOAgAKAAgKcBuVEwCOAgAAAA==.Optimism:BAAANQADCgIIAgAAAA==.',
Pa='Paladrone:BAAANQABCggIDwABNQADCgcICAAGAAAAAA==.Pallyandtank:BAAANQAECgEJAQAAAA==.Panzer:BAAANQAECgYIEgAAAA==.Parts:BAAANQAECgcIEQABNQAECggIGwADADwTAA==.Passionfruit:BAAANQADCgQJBAAAAA==.Paul:BAAANQAECgUICgAAAA==.',
Pe='Peachtea:BAAANQAECgIIBAAAAA==.Pepecojon:BAAANQADCggIDwAAAA==.',
Pi='Piebaby:BAAANQADCgEIAgAAAA==.Pirodeath:BAAANQAECgUIBgAAAA==.',
Pl='Plovdiv:BAAANQADCgcJCQAAAA==.',
Po='Poah:BAAANQAECgYIBgAAAA==.',
Pr='Pray:BAABNQAECoEkAAMgAAgKRCQaAQBDAwAgAAgKMiQaAQBDAwAYAAgKrSC2GQD3AgAAAA==.Prodarkangel:BAAANQADCgcJCQAAAA==.',
Pu='Puckllane:BAAANQAECgEIAgAAAA==.Punkin:BAAANQADCgcICAAAAA==.',
Py='Pyre:BAABNQAECoEeAAIgAAgKWg3yCAC2AQAgAAgKWg3yCAC2AQABNQAECgEJAQAGAAAAAA==.',
['Pü']='Püff:BAAANQADCgEIAQABNQAECgQJBwAGAAAAAA==.',
Qu='Quanah:BAAANQAECgUIDgAAAA==.Quivver:BAAANQADCgYIEgAAAA==.',
Ra='Rabmaxx:BAAANQAECggIDwAAAA==.Raina:BAAANQADCgYIBgAAAA==.Ravenlight:BAABNQAECoEcAAINAAkKnhRlaAA1AgANAAkKnhRlaAA1AgAAAA==.Ravenwynnd:BAABNQAECoEfAAMDAAgKzR87PwC1AgADAAgKYR87PwC1AgAEAAYK3Ru2EQDcAQAAAA==.Raynman:BAABNQAECoEiAAIVAAgKjhKiUwD9AQAVAAgKjhKiUwD9AQAAAA==.',
Re='Refrigtuitor:BAAANQAECgUIBQABNQAECgkJIQAYAAUcAA==.Reylariel:BAAANQADCgMIAwAAAA==.',
Rh='Rhydian:BAAANQADCgQIBAAAAA==.Rhyzer:BAAANQAECgMIBQAAAA==.',
Ri='Riiver:BAAANQADCgYIBgAAAA==.',
Ro='Roderick:BAAANQADCggICgAAAA==.Root:BAAANQAECggICwABNQAECgkJLwABAFQfAA==.',
Ru='Rubmytotem:BAAANQAECgQJBQAAAA==.',
Sa='Sabazia:BAABNQAECoEiAAIXAAgKyxRlPwDiAQAXAAgKyxRlPwDiAQAAAA==.Sabelinå:BAAANQAECgEIAQAAAA==.Sable:BAAANQADCgEIAQAAAA==.Sacred:BAAANQAECgUICgAAAA==.Saerise:BAAANQADCggICAAAAA==.Sairalindë:BAAANQAECgEIAgAAAA==.Salamandra:BAAANQADCggIDAABNQAECggIGQAbAKEXAA==.Saleath:BAAANQAECgIIAgAAAA==.Salios:BAAANQAECgEIAQAAAA==.Sanara:BAAANQABCgUIBwABNQAECgMIBQAGAAAAAA==.Sanctifier:BAAANQADCgUIBQAAAA==.',
Sc='Scrept:BAAANQAECggICgAAAA==.Scynix:BAEANQAECgcIEgAAAA==.',
Se='Seizuregoat:BAAANQAECgMJAwAAAA==.Senus:BAAANQADCgEIAQAAAA==.Servoker:BAAANQAECgUICQAAAA==.',
Sh='Shabzyt:BAAANQAECgYIDAAAAA==.Shaienne:BAAANQADCgcIDgAAAA==.Shammander:BAAANQAECgEIAQAAAA==.Shamrockshak:BAAANQAECgIIBAAAAA==.Shamron:BAAANQADCgcICAAAAA==.Shenuton:BAAANQAECgUIBQAAAA==.Shieldbash:BAABNQAECoErAAIEAAgKIyZ/AgB2AwAEAAgKIyZ/AgB2AwAAAA==.Shockthêràpy:BAABNQAECoEfAAMFAAkKHCDdFwD6AgAFAAkKHCDdFwD6AgAVAAEKzw5XEQE3AAAAAA==.Shoes:BAAANQAECgYICgAAAA==.Shtdruid:BAAANQAECgEIAQAAAA==.',
Si='Sibearian:BAAANQAECgUIDgABNQAECgcIFgABACgUAA==.Sibeson:BAAANQAECgUICgABNQAECgcIFgABACgUAA==.Simi:BAAANQAECgcIEQAAAA==.',
Sm='Smokesçreen:BAABNQAECoEjAAMZAAgKwhHRDADFAQAZAAgKmhHRDADFAQAQAAcKjAqTRQBhAQAAAA==.',
So='Soonerpride:BAAANQAECgUIDgAAAA==.Soothed:BAAANQADCggICAAAAA==.',
Sp='Spearminttea:BAAANQADCgIIAgAAAA==.Spellbreakr:BAABNQAECoEYAAIUAAkK6xyZYACqAgAUAAkK6xyZYACqAgAAAA==.Spirtbreaker:BAAANQAECgQICwAAAA==.',
Sq='Squeak:BAAANQADCgQIBAAAAA==.Squiby:BAABNQAECoEiAAMhAAgKYCJiCwAaAwAhAAgKYCJiCwAaAwAYAAEKlxWO3wA3AAAAAA==.',
St='Stankowitz:BAAANQABCgQICAABNQADCgYIBgAGAAAAAA==.Starboi:BAAANQADCgUIBQAAAA==.Starce:BAAANQABCgMIAwAAAA==.Steveirwin:BAAANQADCgUIBQAAAA==.Stheris:BAAANQAECgcIEAAAAA==.Stuefester:BAAANQAECgYIEQAAAA==.',
Sv='Sveika:BAAANQAECgQIBwAAAA==.',
Sy='Sylaria:BAEANQADCggICgAAAA==.Syreline:BAAANQAECgEIAQAAAA==.',
['Sï']='Sïn:BAAANQAECgUIDAAAAA==.',
['Sý']='Sýlver:BAAANQAECgYIEgAAAA==.',
Ta='Tarathiel:BAAANQADCgIIAgAAAA==.Tarpalantir:BAAANQADCgcICAAAAA==.Taurne:BAABNQAECoEoAAMKAAgK8hrzFwBaAgAKAAgK8hrzFwBaAgAiAAMKiQWEiQB6AAAAAA==.',
Tc='Tchnce:BAAANQADCgcICgAAAA==.',
Te='Teknoman:BAABNQAECoEiAAMDAAgKDhhhZQBAAgADAAgKDhhhZQBAAgAEAAEKBwUNQAAiAAAAAA==.Telephone:BAAANQAECgEIBQAAAA==.Tempered:BAABNQAECoEbAAIDAAgKPBMxfgD8AQADAAgKPBMxfgD8AQAAAA==.Teresen:BAAANQADCgIIAgAAAA==.',
Th='Thaitea:BAAANQADCgIIBAAAAA==.Thalindra:BAAANQAECgMIBQAAAA==.Tharain:BAAANQAECgEIAQAAAA==.Thebigbeast:BAAANQAECgQIDAABNQAFFAcIFAAJAEoVAA==.Thecurt:BAABNQAECoEkAAIaAAgKsyPXAwAxAwAaAAgKsyPXAwAxAwAAAA==.Thunderrbutt:BAAANQAECgYIEwAAAA==.Thyralizen:BAAANQADCgQIBQAAAA==.',
Ti='Tiael:BAAANQAECgIIAgAAAA==.Timaeus:BAAANQADCgUIEgAAAA==.Tinylef:BAABNQAECoEZAAQbAAgKoRdEIgDpAQAbAAcKeRdEIgDpAQAjAAYKrAUeLQDYAAAaAAEKuRixKgBEAAAAAA==.Tirouke:BAAANQAECgMIBAAAAA==.Titanlock:BAAANQADCgUIBwAAAA==.',
Tk='Tkdfath:BAAANQADCgYIBgAAAA==.',
To='Toralina:BAAANQAECgEIAQAAAA==.Torvia:BAAANQADCgcICQAAAA==.',
Tr='Trisinz:BAAANQAECgUJCQAAAA==.',
Tu='Tuerto:BAAANQAECgQIBgAAAA==.Turbojohnson:BAAANQAECgEIAQAAAA==.Turk:BAABNQAECoErAAIeAAgK3Q5KJwDqAQAeAAgK3Q5KJwDqAQAAAA==.Turkish:BAABNQAECoEaAAICAAcK2gwhQgB3AQACAAcK2gwhQgB3AQAAAA==.',
Tw='Twinkytoes:BAAANQADCggIEwAAAA==.',
Ty='Tychaa:BAAANQADCgYIEgAAAA==.Tylat:BAAANQABCgMIAwAAAA==.Tyranax:BAABNQAECoEWAAIYAAcKpR5pNgBsAgAYAAcKpR5pNgBsAgAAAA==.Tyrith:BAAANQADCgMJAwAAAA==.',
Ui='Uintah:BAAANQAECgIIAgAAAA==.',
Ul='Ullyr:BAAANQAECggIEwABNQAFFAUICgAVAKQIAA==.',
Us='Userdel:BAAANQAECgUIEQAAAA==.',
Va='Vadose:BAAANQADCgYIBgABNQAECgcIEQAGAAAAAA==.Valytrois:BAAANQAECgEIAQAAAA==.Variant:BAAANQAECgMIAwAAAA==.Varinix:BAAANQADCgUIBQAAAA==.Vauld:BAAANQADCgQJBQAAAA==.',
Ve='Veiksla:BAAANQADCgYIFAAAAA==.Vengerr:BAAANQADCgYIDwAAAA==.Verace:BAAANQAECggIAQAAAA==.Verradic:BAAANQAECgQIBAAAAA==.',
Vi='Vitur:BAABNQAECoEwAAIeAAkKsyPyAgCoAwAeAAkKsyPyAgCoAwAAAA==.Vivi:BAAANQADCgYIBgAAAA==.',
Vo='Voidbunny:BAAANQAECgYJDwAAAA==.Volaine:BAAANQAECgMIBQAAAA==.Volgar:BAAANQADCgMIBAAAAA==.Volition:BAAANQADCgYIBgAAAA==.Volt:BAABNQAECoEYAAIkAAgKRxOoEABCAgAkAAgKRxOoEABCAgABNQAECggIHwAJAHALAA==.',
Vr='Vrye:BAAANQAECggIDwAAAA==.',
Vy='Vynaeda:BAAANQAECgUIDwAAAA==.',
['Vô']='Vôx:BAAANQAECgIIBQABNQAECgUICAAGAAAAAA==.',
Wa='Wakko:BAAANQADCgcIEwAAAA==.Walkure:BAAANQADCgYIFgAAAA==.',
We='Weirdscience:BAAANQABCgQIBAAAAA==.Wetasstotem:BAAANQAECggIDwABNQAFFAcIFAAJAEoVAA==.',
Wh='Whew:BAAANQADCggICQAAAA==.',
Wi='Widge:BAAANQAECgQIBAAAAA==.Wikker:BAAANQADCgQIBAAAAA==.',
Wo='Worldlight:BAAANQADCgIIAgAAAA==.',
Wr='Wreckbums:BAAANQAECgMIBAAAAA==.Wrongway:BAAANQADCgQIBQAAAA==.',
Xa='Xanthad:BAAANQADCgUICAAAAA==.',
Xb='Xb:BAAANQADCgYIFgAAAA==.',
Xi='Xitãozinho:BAAANQAECgEIAQAAAA==.',
Xy='Xyomi:BAAANQADCgIJAgAAAA==.',
Ya='Yaalia:BAAANQAECgMIBQAAAA==.Yaan:BAAANQAECgYICQAAAA==.',
Za='Zain:BAAANQADCgYIBgABNQAECggILAAHABIaAA==.Zalaan:BAAANQAECgUIBQABNQAECgUIDQAGAAAAAA==.Zandibar:BAAANQAECgMIBQAAAA==.Zaptoasted:BAAANQADCgYIBgAAAA==.Zariea:BAAANQAECgIIAgABNQAECgcIHwABAEgYAA==.Zavac:BAAANQADCgUIBwAAAA==.',
Ze='Zelritch:BAAANQADCggICAAAAA==.',
Zi='Zinfandell:BAAANQAECgUIBgAAAA==.',
Zo='Zorrloc:BAAANQADCgQIBAAAAA==.',
Zu='Zuggie:BAAANQAECgQIBgAAAA==.Zugtail:BAAANQAECgEIAQABNQAECgQIBgAGAAAAAA==.Zurtrinik:BAAANQAECgUICwABNQAFFAUIEAAaADkYAA==.',
Zy='Zyntalla:BAAANQAECgMIBQAAAA==.',
Zz='Zzonked:BAAANQAECgEIAQAAAA==.',
['Zê']='Zêp:BAAANQADCgcIFwAAAA==.',
['Àr']='Àrròw:BAAANQADCgYICgAAAA==.',
['Ðo']='Ðoogle:BAAANQAECgQIBwABNQABCgUIBQAGAAAAAA==.',
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
