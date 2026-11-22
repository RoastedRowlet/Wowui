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

local lookup = {'DeathKnight-Unholy','DeathKnight-Frost','Warrior-Arms','Paladin-Protection','Paladin-Retribution','Warrior-Protection','Mage-Arcane','Shaman-Elemental','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Shaman-Restoration','Unknown-Unknown','Druid-Balance','Druid-Restoration','Paladin-Holy','Druid-Guardian','Druid-Feral','Rogue-Subtlety','Evoker-Preservation','Shaman-Enhancement','Priest-Shadow','DemonHunter-Havoc','Hunter-BeastMastery','Warrior-Fury','Mage-Frost','DeathKnight-Blood','DemonHunter-Devourer','Hunter-Marksmanship','Priest-Holy','DemonHunter-Vengeance','Monk-Brewmaster','Monk-Windwalker','Rogue-Assassination','Evoker-Devastation','Evoker-Augmentation','Hunter-Survival','Rogue-Outlaw','Priest-Discipline','Monk-Mistweaver',}
local provider = {region='US',realm='Perenolde',name='US',type='weekly',zone=53,date='2026-11-17',data={Aa='Aanien:BAAANQADCgYICAAAAA==.',
Ac='Acedk:BAABNQAECn8hAAMBAAkKoiEyGgDvAgABAAkKPCAyGgDvAgACAAUKdiAWRACyAQAAAA==.Aceslam:BAABNQAECn8YAAIDAAgKuiFKMwDzAgADAAgKuiFKMwDzAgABNQAECgkJIQABAKIhAA==.',
Ad='Adrador:BAABNQAECn9BAAMEAAoKWB6jCQADAwAEAAkKLx+jCQADAwAFAAcKahbM4QAaAQAAAA==.Adrenaline:BAACNQAFFH8VAAIGAAYKnB5nAQBbAQAGAAYKnB5nAQBbAQA1AAQKf0cAAgYACgrpJHoCAI4DAAYACgrpJHoCAI4DAAAA.',
Ae='Aelik:BAABNQAECn8qAAIBAAgKxxXLaABuAQABAAgKxxXLaABuAQAAAA==.Aeolian:BAAANQADCgYIDgAAAA==.Aeru:BAAANQADCgQIBAAAAA==.',
Af='Afk:BAAANQAECgMIAwAAAA==.',
Aj='Ajaila:BAAANQADCgQIBAAAAA==.',
Ak='Akueria:BAAANQADCgcIBwAAAA==.',
Al='Alayssa:BAABNQAECn8oAAIHAAoKzhtRNQBuAgAHAAoKzhtRNQBuAgAAAA==.Alda:BAAANQADCgYIFgAAAA==.Alemental:BAABNQAECn8kAAIIAAoKqgwRTwCcAQAIAAoKqgwRTwCcAQAAAA==.Aleska:BAABNQAECn8ZAAQJAAgKzRXeCAA9AQAJAAYKlhbeCAA9AQAKAAcKVwyZ6AD4AAALAAEKXwzsLQA6AAAAAA==.Allarius:BAAANQAECgUIBAAAAA==.Allevist:BAAANQAECgMIAwABNQAECggIMQAHABEHAA==.Alo:BAABNQAECn86AAIMAAoKvxbGPgBlAgAMAAoKvxbGPgBlAgABNQAECgEJAQANAAAAAA==.',
Am='Amilee:BAAANQAECgIIAgAAAA==.Amoondai:BAAANQADCgYICwAAAA==.Amoondrin:BAABNQAECn8oAAMOAAoKZQeIQQAiAQAOAAoKZQeIQQAiAQAPAAEK3wPDewAnAAAAAA==.',
An='Analiya:BAAANQADCgQJBQAAAA==.Anatyr:BAAANQAECgMIAwAAAA==.Andoria:BAAANQABCggICwAAAA==.',
Ar='Aramathis:BAAANQAECgUIBQAAAA==.Araviin:BAAANQAECgUICAAAAA==.Arbor:BAAANQAECgQIBwAAAA==.Arcillias:BAABNQAECn8eAAMQAAoKrxUGMwBTAgAQAAoKrxUGMwBTAgAFAAEKDAIurQEmAAABNQAECgQIDAANAAAAAA==.Arilas:BAAANQAECgQICAABNQAECgQIDAANAAAAAA==.Arkanist:BAABNQAECn8xAAIHAAgKEQdlzgAMAQAHAAgKEQdlzgAMAQAAAA==.Arthia:BAAANQADCgYICQAAAA==.Arvidpally:BAABNQAECn8VAAIFAAcKiwdUCQHbAAAFAAcKiwdUCQHbAAAAAA==.',
As='Ashesius:BAABNQAECn9WAAQJAAoKAB2GBADhAgAJAAoKAB2GBADhAgAKAAMKYQmcHgGHAAALAAIKaxyHHgCHAAAAAA==.Ashmehameha:BAAANQAECgQIBAABNQAECgYIDAANAAAAAA==.Ashstabber:BAAANQAECgQIBgABNQAECgYIDAANAAAAAA==.',
At='Atredes:BAAANQAECgYIDQAAAA==.',
Au='Auspex:BAABNQAECn8qAAIRAAoKjwn6LQAhAQARAAoKjwn6LQAhAQAAAA==.',
Av='Avaryn:BAABNQAECn8aAAIPAAkKiBbVHwAtAgAPAAkKiBbVHwAtAgAAAA==.',
Ax='Aximlii:BAAANQADCgUICQAAAA==.',
Ba='Babavoss:BAAANQAECggIEAAAAA==.Babs:BAAANQADCggIDgAAAA==.Badaracka:BAACNQAFFH8LAAISAAYKPw0wAQCoAQASAAYKPw0wAQCoAQA1AAQKf0gABBIACgppJJUCACoDABIACgppJJUCACoDABEACAojHX0XANABAA4ABgpqFLg6AEUBAAAA.Badash:BAAANQAECgQIDAABNQAECgYIDAANAAAAAA==.Bahamuth:BAABNQAECn9OAAIFAAoKAB01MgCaAgAFAAoKAB01MgCaAgAAAA==.Bahamutsrage:BAAANQADCggIDgABNQAECggIHwAJACoJAA==.Balder:BAAANQAECggIGQABNQAFFAYIDwANAAAAAQ==.Bandage:BAAANQAECgYIBgABNQAECgoKOAATAMMWAA==.Barbattos:BAACNQAFFH8VAAIUAAYKPhl5CQCYAQAUAAYKPhl5CQCYAQA1AAQKfzkAAhQACgroIxUGAEgDABQACgroIxUGAEgDAAAA.Batmon:BAAANQAECgUIBQAAAA==.',
Bd='Bdyrk:BAABNQAECn8ZAAIVAAgKDw84GQCCAQAVAAgKDw84GQCCAQABNQAFFAYICwASAD8NAA==.',
Be='Bealzeboss:BAAANQADCgcICQAAAA==.Bexley:BAABNQAECn9KAAMEAAoKLSH6BQD6AgAEAAoKLSH6BQD6AgAFAAEKAACn1gEAAAAAAA==.',
Bi='Biggerbunny:BAABNQAECn8jAAIWAAoKmRPqJQD/AQAWAAoKmRPqJQD/AQAAAA==.Biglarry:BAAANQADCgMJBQAAAA==.Biianca:BAAANQADCgUICQAAAA==.',
Bl='Blacklok:BAAANQAECgIIBAABNQAECgoKOgAXANMlAA==.Blanne:BAAANQABCgIIAgAAAA==.Blargle:BAAANQAECgYIEAAAAA==.Blegh:BAACNQAFFH8HAAIFAAMKARnHFQABAQAFAAMKARnHFQABAQA1AAQKfyQAAgUACgoNILwvAAoDAAUACgoNILwvAAoDAAE1AAUUBAgHABgAYQoA.Blessyaheart:BAABNQAECn8eAAIQAAoKXRBzPgAcAgAQAAoKXRBzPgAcAgAAAA==.Blincyto:BAAANQAECgEIAQAAAA==.Blinx:BAAANQAECgEIAgAAAA==.Bloodrake:BAABNQAECn9IAAIYAAoKGhgoQwChAgAYAAoKGhgoQwChAgAAAA==.Blueray:BAAANQADCgYIBgAAAA==.',
Bm='Bman:BAABNQAECn8gAAIDAAcKlhqSdgChAQADAAcKlhqSdgChAQAAAA==.',
Br='Braneour:BAABNQAECn85AAMEAAoKehJzJwCjAQAEAAoKehJzJwCjAQAQAAYK1QcEswAYAQAAAA==.Bravisimo:BAAANQAECgIIAgAAAA==.Browel:BAABNQAECn8vAAIKAAoK4Rl9LwBRAgAKAAoK4Rl9LwBRAgAAAA==.',
Bu='Bubblfett:BAAANQAECgcICwAAAA==.Bumm:BAAANQAECgMIAwAAAA==.',
Bz='Bzspy:BAABNQAECn8zAAMDAAoKxBknYwBlAgADAAoKxBknYwBlAgAZAAIK9ApMKwBZAAAAAA==.',
['Bë']='Bëar:BAAANQAECgEIAQAAAA==.',
Ca='Cabooselul:BAAANQAECgYIDQAAAA==.Calyptus:BAABNQAECn8yAAMJAAkKew/mBQCPAQAJAAkK6w7mBQCPAQAKAAMK1gmO3gCVAAAAAA==.Capylaura:BAAANQAECgMIBgAAAA==.Caratine:BAAANQADCgcIDQAAAA==.Cassandrah:BAABNQAECn9QAAIHAAoK1x/dKACbAgAHAAoK1x/dKACbAgAAAA==.',
Ce='Celìa:BAABNQAECn8XAAIYAAoKPgUmvAA5AQAYAAoKPgUmvAA5AQAAAA==.',
Ch='Chillymage:BAAANQADCgcIBwAAAA==.Chpchop:BAAANQABCggIEQAAAA==.Christy:BAAANQADCgYIGwAAAA==.Chugg:BAABNQAECn8tAAIMAAgKWAbGlQD4AAAMAAgKWAbGlQD4AAAAAA==.',
Ci='Ciaphus:BAABNQAECn82AAQFAAoKqxCbtwCvAQAFAAgK6A+btwCvAQAQAAoKOQrZYwCNAQAEAAcKNgxENgA1AQAAAA==.Cinnamonster:BAABNQAECn8aAAMJAAkKKgsEDQDuAAAKAAYKJAs/5gD8AAAJAAgK4ggEDQDuAAAAAA==.',
Cl='Clogs:BAAANQAECgUIBgAAAA==.',
Co='Coffeedemon:BAAANQAECgQIBgAAAA==.Coldslappins:BAAANQAECgYICQABNQAECgoKOQAEAHoSAA==.Convalescent:BAAANQADCgYIBgAAAA==.Coragrr:BAAANQAECgIIAwAAAA==.',
Cr='Cracklepants:BAACNQAFFH8KAAIIAAUKaAlMEABoAQAIAAUKaAlMEABoAQA1AAQKf0oAAggACgp+IjQXAD0DAAgACgp+IjQXAD0DAAE1AAUUBggPAA4AwhEA.Crashout:BAABNQAECn8UAAIDAAgKixL8owA0AQADAAgKixL8owA0AQAAAA==.',
Cu='Curtastrophe:BAABNQAECn9EAAIaAAoK2yIpAQCQAwAaAAoK2yIpAQCQAwAAAA==.Curticus:BAAANQADCgYIBgAAAA==.',
Da='Daelanos:BAABNQAECn8ZAAIDAAgKIAtbrwCmAQADAAgKIAtbrwCmAQAAAA==.Dallas:BAAANQAECggICgAAAA==.Danorman:BAAANQADCgQIBAABNQAECgQIBwANAAAAAA==.',
De='Deathisreal:BAAANQADCgEIAgABNQAECgUIDQANAAAAAA==.Deathoof:BAABNQAECn84AAQbAAkKTBchIAD7AQABAAkKRxb8GwAEAgAbAAkK5hQhIAD7AQACAAEKGgWKtAArAAABNQAECgoKIAARALobAA==.Demonblaze:BAAANQAECgIIBgAAAA==.Demonilla:BAABNQAECn8uAAIcAAoKrBr0DwBYAgAcAAoKrBr0DwBYAgAAAA==.Destro:BAABNQAECn8+AAIKAAoKNg1sWQDIAQAKAAoKNg1sWQDIAQAAAA==.',
Di='Dilaudyd:BAAANQAECgMIAwAAAA==.Disbeleaf:BAAANQAECgcIEQAAAA==.Dishu:BAAANQABCgQIBAAAAA==.Dispel:BAAANQADCgYIBgAAAA==.Disputatious:BAAANQADCgQIBAAAAA==.',
Dn='Dntblink:BAAANQADCgUIBQAAAA==.',
Do='Dogaz:BAAANQADCgYIGwAAAA==.Dogsoldier:BAAANQADCgQIBAAAAA==.Donori:BAAANQAECgYIDwAAAA==.Doomphoenix:BAAANQAECgQIAwAAAA==.',
Dr='Dragonias:BAABNQAECn8cAAIdAAgKpQc/LAAJAQAdAAgKpQc/LAAJAQAAAA==.Drakthorn:BAAANQADCggIGgAAAA==.Drinny:BAABNQAECn8xAAIeAAoKfgXzcQCGAQAeAAoKfgXzcQCGAQAAAA==.Dripington:BAACNQAFFH8GAAICAAUKFxQFEADUAAACAAUKFxQFEADUAAA1AAQKfysAAwIACgqZIZUUAOgCAAIACgqZIZUUAOgCAAEAAQoAAGngADMAAAAA.',
Ea='Earthangel:BAABNQAECn8qAAIeAAcKHgp4kgAiAQAeAAcKHgp4kgAiAQAAAA==.',
Ef='Efon:BAAANQADCgUIBQABNQAECgoKKAAHAM4bAA==.',
Ei='Eine:BAABNQAECn9AAAIYAAoK4REWVgAfAgAYAAoK4REWVgAfAgAAAA==.',
El='Eldergreen:BAAANQAECgYIEQAAAA==.Elemanda:BAAANQAECgMIAwABNQAECgcIJwAEALsOAA==.Elfwine:BAABNQAECn8qAAIWAAcKsAmEMAAHAQAWAAcKsAmEMAAHAQAAAA==.Elindria:BAABNQAECn86AAMXAAoK0yXCBACnAwAXAAoKiyXCBACnAwAfAAUK/iRJEQA0AQAAAA==.Elminstir:BAABNQAECn83AAIaAAoK1xb1CgAWAgAaAAoK1xb1CgAWAgAAAA==.Eluzhion:BAAANQADCgUICAAAAA==.Elysian:BAAANQAECgUICQAAAA==.',
Er='Erisa:BAAANQADCgMIAwAAAA==.Erizhal:BAAANQABCgIIAgAAAA==.Eruptyon:BAAANQAECgEIAQABNQAECgoKLwAHAJYgAA==.',
Es='Esabel:BAAANQAECgcIDgABNQAECgoKKAAHAM4bAA==.',
Ev='Eviae:BAABNQAECn8qAAIbAAcKEQXdYgC7AAAbAAcKEQXdYgC7AAAAAA==.Evillure:BAAANQAECgYICgAAAA==.',
Ex='Explanation:BAAANQADCgQIBAAAAA==.',
Fa='Falan:BAAANQAECgEIAQAAAA==.Farfins:BAAANQADCgYIBgAAAA==.',
Fe='Fedor:BAAANQAECggICAAAAA==.Feår:BAABNQAECn8fAAMKAAkK9xDMbwCLAQAKAAcKOhHMbwCLAQAJAAIKMBAsWwBvAAAAAA==.',
Fi='Finley:BAAANQADCgQIBAAAAA==.Fixation:BAAANQABCgIIAgAAAA==.',
Fl='Flane:BAACNQAFFH8WAAIgAAcKABm+AQD2AQAgAAcKABm+AQD2AQA1AAQKfzYAAyAACgq2IvwBAAoDACAACgq2IvwBAAoDACEAAQoAAEdkAE4AAAAA.Flexdruid:BAAANQAECgUIBQAAAA==.',
Fr='Fragil:BAABNQAECn9CAAMTAAoK1SAlEgDmAgATAAkKEB8lEgDmAgAiAAoK7xs2FwDCAgAAAA==.Frostmane:BAABNQAECn8iAAMbAAkKPB6GEwB1AgAbAAgKlB6GEwB1AgABAAkKnRRbFwAxAgABNQAFFAYIDwAOAMIRAA==.Frostssiah:BAAANQAECgUICQAAAA==.',
Ga='Galena:BAABNQAECn8eAAIPAAkKthIvIwDdAQAPAAkKthIvIwDdAQAAAA==.Galian:BAAANQADCggIEgAAAA==.Ganonn:BAAANQAECgQICQABNQAECgcIEQANAAAAAA==.',
Ge='Geshtal:BAABNQAECn8YAAMXAAgKAwxUQAA3AQAXAAgKAwxUQAA3AQAfAAEKAAAcNAAsAAAAAA==.',
Gi='Girion:BAABNQAECn8nAAIEAAcKuw4uMQD1AAAEAAcKuw4uMQD1AAAAAA==.',
Gl='Glaiven:BAECNQAFFH8RAAIXAAYKNBGMCwBnAQAXAAYKNBGMCwBnAQA1AAQKfzcAAxcACgotIpAOADEDABcACgotIpAOADEDABwABwoxFzoxALcBAAAA.Glyr:BAAANQAECgEJAQAAAA==.',
Gn='Gnofear:BAAANQABCggIEwABNQAECgUICwANAAAAAA==.Gnora:BAAANQADCggIEwAAAA==.Gnova:BAAANQADCgUIBgAAAA==.',
Go='Gorgrin:BAABNQAECn8XAAILAAkK6QlmDQBlAQALAAkK6QlmDQBlAQAAAA==.',
Gr='Groguu:BAAANQAECgQIBAABNQAECgkJIQABAKIhAA==.',
Ha='Harkanum:BAABNQAECn8sAAMjAAgKSAq+HACBAQAjAAgKSAq+HACBAQAUAAgK6QQ1KwBSAQAAAA==.Harvester:BAABNQAECn8ZAAMPAAUKXwlNTwC+AAAPAAUKXwlNTwC+AAAOAAUKNwx8ZACUAAAAAA==.',
He='Healinturds:BAAANQADCgEIAQAAAA==.Healsurazz:BAAANQADCgQIBAAAAA==.Helloagain:BAABNQAECn8WAAIHAAkK3RucfgCBAgAHAAkK3RucfgCBAgAAAA==.',
Hi='Hidethetotem:BAAANQAECgYIEgAAAA==.Hiimdeath:BAAANQADCgQIBAABNQAECgUIDQANAAAAAA==.Hikari:BAACNQAFFH8MAAIFAAYKJwwAGgDDAAAFAAYKJwwAGgDDAAA1AAQKfzIAAgUACgrWHaw/AGsCAAUACgrWHaw/AGsCAAAA.Hiown:BAAANQABCgYICAAAAA==.',
Ho='Holyrebel:BAAANQAECgQIBQABNQAECgUIDQANAAAAAA==.Holyspike:BAABNQAECn8eAAMMAAkKBhKETgDZAQAMAAkKBhKETgDZAQAIAAEKAAAFLQEAAAAAAA==.Homerr:BAABNQAECn8bAAIYAAgKhAyrpABqAQAYAAgKhAyrpABqAQAAAA==.Honiahaka:BAABNQAECn9WAAIYAAoK7xIcSgA8AgAYAAoK7xIcSgA8AgAAAA==.Hotsdog:BAAANQADCgIIAgAAAA==.Hottcakes:BAABNQAECn9KAAIHAAoKgiElDwCWAwAHAAoKgiElDwCWAwABNQAFFAkJIQAKANAYAA==.',
Hu='Humanoidlite:BAAANQAFFAEIAgABNQAFFAUICgADAEYIAA==.Humanoidlock:BAAANQADCgcIDAABNQAFFAUICgADAEYIAA==.Humanoidwar:BAACNQAFFH8KAAMDAAUKRgioFwDyAAADAAUKRgioFwDyAAAGAAEKoAP3CgAtAAA1AAQKfzMAAwMACgoEHy40APACAAMACgoEHy40APACAAYABQr+D50pAO4AAAAA.',
['Hà']='Hàvòc:BAAANQADCgQIBAAAAA==.',
['Hö']='Hölyçow:BAAANQADCgUIBQAAAA==.',
Ic='Icedtea:BAAANQAECgQIBAAAAA==.',
In='Inoru:BAAANQAECgUIDAAAAA==.Intgrumblyeo:BAAANQAECggICgAAAA==.',
Ip='Ipseity:BAAANQABCgMIAwAAAA==.',
Ir='Irmaline:BAABNQAECn8eAAIeAAkKng3AZwCoAQAeAAkKng3AZwCoAQAAAA==.',
It='Ithurtshuh:BAAANQAECgIIBQABNQAECgUIDQANAAAAAA==.',
Ja='Jabbawockie:BAABNQAECn8XAAIXAAgKFwhqYwDsAAAXAAgKFwhqYwDsAAAAAA==.Jackcat:BAAANQADCgQIAwAAAA==.Jackyl:BAAANQABCgYIBgAAAA==.',
Je='Jeffee:BAABNQAECn8jAAICAAkKsxgPKQBQAgACAAkKsxgPKQBQAgAAAA==.Jennifleur:BAAANQADCgcIBwAAAA==.Jequalsjosh:BAABNQAECn8fAAIiAAkKoRNlHgA0AQAiAAkKoRNlHgA0AQAAAA==.Jerk:BAACNQAFFH8ZAAIcAAgKIh++BADxAQAcAAgKIh++BADxAQA1AAQKfz8AAhwACgrHJTgEAJIDABwACgrHJTgEAJIDAAAA.Jerp:BAAANQADCgQIBAAAAA==.Jesper:BAABNQAECn9WAAIMAAoKlSIyCgB6AwAMAAoKlSIyCgB6AwAAAA==.Jetz:BAAANQAECgQICQAAAA==.Jetzul:BAAANQAECgUICAAAAA==.Jezelle:BAAANQADCggICAAAAA==.',
Ji='Jilara:BAABNQAECn8ZAAIFAAYKFQhqCwHYAAAFAAYKFQhqCwHYAAAAAA==.Jimmyjim:BAABNQAECn8YAAIaAAkKFwoXEwBcAQAaAAkKFwoXEwBcAQAAAA==.',
Jo='Joink:BAAANQADCgYICQAAAA==.',
Jp='Jpepps:BAABNQAECn8mAAMKAAgK2A0tigDNAQAKAAgK2A0tigDNAQAJAAMKcAThXgBoAAAAAA==.',
Jr='Jrose:BAAANQADCggIGQAAAA==.',
Ka='Kagozo:BAEANQAECgEIAQABNQAECgIIAgANAAAAAA==.Kahlanrahl:BAAANQADCgIIAgAAAA==.Kaiatra:BAABNQAECn8eAAICAAkKBRnWNwDBAQACAAkKBRnWNwDBAQAAAA==.Kalamor:BAAANQAECgUIBQAAAA==.Kaliguala:BAAANQADCgUIBwAAAA==.Kaloran:BAAANQAECgcIDgAAAA==.Katalaystar:BAAANQADCgYIDAABNQAECgoKTQAPAHoiAA==.Katalegdh:BAAANQAECgYIDwAAAA==.Kative:BAAANQADCgcIEQAAAA==.Kaìju:BAABNQAECn8rAAIFAAoK8h98JQDLAgAFAAoK8h98JQDLAgAAAA==.',
Ke='Kellytgt:BAAANQAECgcIDAAAAA==.',
Kh='Khaelyn:BAAANQADCgQIBQAAAA==.Khai:BAABNQAECn8WAAIFAAgKyA1X4ABbAQAFAAgKyA1X4ABbAQAAAA==.',
Ki='Kiae:BAAANQADCgYIBwAAAA==.Kidneyspears:BAAANQADCgYICAAAAA==.Kilaura:BAAANQADCgUIBQAAAA==.Kilmandaros:BAAANQAECgUIBgAAAA==.Kimblee:BAAANQADCgQIBAAAAA==.',
Ko='Korbix:BAAANQABCgUIBAABNQAECgUICwANAAAAAA==.',
Kr='Kraxxas:BAAANQAECggIDgAAAA==.Kronmon:BAAANQADCgQIBAAAAA==.',
Ku='Kudria:BAABNQAECn8uAAIYAAoK4xEwZgD4AQAYAAoK4xEwZgD4AQAAAA==.Kunei:BAAANQABCgYICQABNQAECgQIBwANAAAAAA==.Kurdran:BAAANQABCgQIBAAAAA==.Kuroyukihime:BAABNQAECn8vAAIaAAoKHBtNBgCfAgAaAAoKHBtNBgCfAgAAAA==.',
Ky='Kynae:BAAANQAECgQIEQAAAA==.Kyross:BAAANQABCgIIAgAAAA==.',
['Ká']='Kárma:BAAANQADCgYICwABNQAECgkJHwAKAPcQAA==.',
La='Landoridan:BAAANQAECggICAAAAA==.Lashela:BAABNQAECn8uAAIdAAkKTQeiIwBMAQAdAAkKTQeiIwBMAQAAAA==.Laughter:BAABNQAECn8WAAIGAAgKZQZCIgDoAAAGAAgKZQZCIgDoAAAAAA==.Lavamylash:BAAANQAECgcIEQAAAA==.Laylla:BAAANQAECgQICgAAAA==.Lazulie:BAAANQAECgQICAAAAA==.',
Le='Lefnedrav:BAAANQADCgYICgABNQAECgoKMgAgAHAaAA==.Lektrik:BAAANQAECgUICgAAAA==.Lenexa:BAAANQADCgcIDAAAAA==.Lexapayne:BAAANQADCgEIAQABNQAECgoKNQAYAPkTAA==.Leyra:BAABNQAECn8oAAIdAAoK5xpQDwBHAgAdAAoK5xpQDwBHAgABNQAECgoKOgAXANMlAA==.',
Li='Lighthammer:BAAANQADCggIDgAAAA==.Lightmessiah:BAABNQAECn89AAQFAAoKKxysfgAsAgAFAAgK9xqsfgAsAgAQAAgKnBYJQAAVAgAEAAIKgwafcQAgAAAAAA==.Lightnig:BAAANQADCgUIBQAAAA==.Lilyvain:BAAANQAECgEIAQAAAA==.Lireal:BAABNQAECn8gAAMQAAoKKx7MIwDcAgAQAAkKNB3MIwDcAgAFAAEKKAwzoAEwAAAAAA==.Livnod:BAAANQAECgMIAwAAAA==.',
Lo='Logdiir:BAAANQAECgMIAwAAAA==.Lonon:BAABNQAECn8XAAIIAAgKJA5tcwDHAQAIAAgKJA5tcwDHAQAAAA==.Loosescrew:BAAANQADCgQIBQAAAA==.Lorine:BAABNQAECn9CAAIEAAoKoRsEDQBeAgAEAAoKoRsEDQBeAgAAAA==.',
Lu='Lunara:BAAANQADCgYIDAAAAA==.',
Ly='Lynnethe:BAAANQAECgYIEgAAAA==.Lyyse:BAAANQADCgIIAgAAAA==.',
Ma='Malkiel:BAAANQAECgQIDgAAAA==.Mantang:BAAANQABCgIIAgAAAA==.Mastakillah:BAAANQADCgQICAABNQAECgUIEQANAAAAAA==.Maxamus:BAAANQAECgEIAgAAAA==.',
Me='Meeseeks:BAAANQAECgcIDQAAAA==.Merckel:BAABNQAECn84AAIcAAoKJB1READvAgAcAAoKJB1READvAgAAAA==.Messorom:BAAANQADCgEIAQAAAA==.',
Mi='Michello:BAABNQAECn8eAAIYAAkKPRG/cwDYAQAYAAkKPRG/cwDYAQAAAA==.Mightytot:BAAANQAECgQIBAAAAA==.Millia:BAABNQAECn8vAAMHAAoKliCoYgDxAQAHAAgKZiGoYgDxAQAaAAIKJh6rKQCqAAAAAA==.Mint:BAABNQAECn8fAAIQAAkKGBW5QgBaAgAQAAkKGBW5QgBaAgAAAA==.Mintberrytea:BAAANQAECgQJBAABNQAECgkJHwAQABgVAA==.Misstress:BAABNQAECn8tAAMOAAoKLgxaMgB4AQAOAAoKxgtaMgB4AQARAAQK0gsVXgBXAAAAAA==.',
Mo='Moistweaver:BAAANQADCgYIBgAAAA==.Monkussy:BAAANQADCgUIBQAAAA==.Monoxide:BAAANQADCgUIBQABNQAECgkJGAAXADMSAA==.Mooncloud:BAAANQAECgUICAAAAA==.Moonhunt:BAAANQAECgQIBAAAAA==.Morkleb:BAAANQAECgYIDAAAAA==.Morrag:BAABNQAECn83AAMKAAoK8AqvZACoAQAKAAoK8AqvZACoAQAJAAEKAACJQgAAAAAAAA==.Morrtisha:BAAANQAECgcIDAAAAA==.',
Mu='Munchkins:BAAANQADCgMIAwAAAA==.Munden:BAAANQADCgUIBQABNQAECgQIDgANAAAAAA==.',
My='Myxie:BAABNQAECn81AAIMAAoKUxahNQBEAgAMAAoKUxahNQBEAgAAAA==.',
['Mí']='Mísfìt:BAABNQAECn9EAAIMAAoKXx+aEgAkAwAMAAoKXx+aEgAkAwAAAA==.',
Na='Nakaito:BAABNQAECn8VAAIKAAgK4Ae0vwBMAQAKAAgK4Ae0vwBMAQABNQAECgoKPwAiAM4TAA==.Narcoleptic:BAACNQAFFH8FAAIUAAQKeBEPEwCbAAAUAAQKeBEPEwCbAAA1AAQKf1MABBQACgrhF9sJAJwCABQACgrgF9sJAJwCACMABQrNC5gmAAEBACQABgraESUQAN8AAAAA.Nashty:BAAANQADCgIIAgAAAA==.Naturaljuice:BAAANQAECggIEwABNQAFFAkJIQAKANAYAA==.Naturebreakr:BAABNQAECn8bAAIOAAkKwhK+PQAKAgAOAAkKwhK+PQAKAgAAAA==.',
Ne='Nex:BAABNQAECn88AAIHAAoKDiEwOAAYAwAHAAoKDiEwOAAYAwAAAA==.',
Ni='Niceshield:BAAANQAECggIDwAAAA==.Nightsawdy:BAABNQAECn8tAAMYAAkKXRQXawDtAQAYAAkKXRQXawDtAQAlAAEKLRMAEwBGAAAAAA==.Niightstorm:BAABNQAECn8iAAMYAAYK/w/wyABwAQAYAAYK/w/wyABwAQAlAAEKAACQFwAAAAAAAA==.Nilvannas:BAAANQADCggICAAAAA==.Nitefire:BAAANQADCgYIGgAAAA==.Nitélifé:BAABNQAECn8WAAIMAAcKvRB4agB1AQAMAAcKvRB4agB1AQAAAA==.',
Of='Offspring:BAAANQABCgIIAgAAAA==.',
Om='Omora:BAABNQAECn8lAAQEAAoK2RaCEwD1AQAEAAoK2RaCEwD1AQAQAAYKWgm5rwAgAQAFAAIKmwwfcgFrAAABNQAECgoKMgAgAHAaAA==.',
Op='Opalinnas:BAABNQAECn9NAAIPAAoKeiJOBgB/AwAPAAoKeiJOBgB/AwAAAA==.Optimism:BAAANQADCgUIBQAAAA==.',
Pa='Paladrone:BAAANQABCggIDwABNQADCgcICgANAAAAAA==.Palestrina:BAAANQADCgMIAwAAAA==.Pallyandtank:BAAANQAECgEIAQAAAA==.Panzer:BAABNQAECn8zAAIRAAgKXxZ5HwCiAQARAAgKXxZ5HwCiAQAAAA==.Parts:BAABNQAECn84AAQTAAoKwxbHQwDvAQATAAgKLhjHQwDvAQAiAAYKwg+MUAB8AQAmAAMK0gpNFQCbAAAAAA==.Passionfruit:BAAANQAECgcIBwAAAA==.Paul:BAAANQAECgUICgAAAA==.',
Pe='Peachtea:BAAANQAECgYICwAAAA==.Pepecojon:BAAANQADCggIDwAAAA==.',
Pi='Piebaby:BAAANQADCgUIBgAAAA==.Pirodeath:BAAANQAECgYICAAAAA==.',
Pl='Plovdiv:BAAANQADCgcJCQAAAA==.',
Po='Poah:BAAANQAECgYIBgAAAA==.',
Pr='Pray:BAABNQAECn9JAAMeAAoKgiWjAgAWBAAeAAoKGyWjAgAWBAAnAAgKMiR5AQA5AwAAAA==.Prodarkangel:BAAANQADCgcJCQAAAA==.',
Pu='Puckllane:BAAANQAECgEIAgAAAA==.Punkin:BAAANQAECgMIAwAAAA==.',
Py='Pyre:BAABNQAECn8+AAMnAAoKCQ2VCgCeAQAnAAgKWg2VCgCeAQAeAAoK0gYkbgCSAQABNQAECgEJAQANAAAAAA==.',
['Pü']='Püff:BAAANQADCgEIAQABNQAECgQIDAANAAAAAA==.',
Qu='Quanah:BAABNQAECn8cAAIMAAgKrB5gNwA8AgAMAAgKrB5gNwA8AgAAAA==.Quivver:BAAANQADCgYIGAAAAA==.',
Ra='Rabmaxx:BAABNQAECn8wAAIXAAkKSggPRAAiAQAXAAkKSggPRAAiAQAAAA==.Raina:BAAANQAECgIIAwAAAA==.Rap:BAAANQAECgMIAwAAAA==.Ravenlight:BAACNQAFFH8KAAIFAAUKFwWoGgC/AAAFAAUKFwWoGgC/AAA1AAQKfyYAAgUACgolFlJ1AEMCAAUACgolFlJ1AEMCAAAA.Ravenwynnd:BAABNQAECn8+AAMDAAoKjCFSHQBCAwADAAoKjCFSHQBCAwAGAAYKFh23FQDMAQAAAA==.Raynman:BAABNQAECn9CAAMIAAoKUhNbPgDbAQAIAAoKUhNbPgDbAQAMAAoKjAS/dgBOAQAAAA==.',
Re='Restotuition:BAAANQABCgQICAABNQAFFAYIEgAeAB0cAA==.Reylariel:BAAANQADCgMIAwAAAA==.',
Rh='Rhydian:BAAANQADCgQIBAAAAA==.Rhyzer:BAABNQAECn8lAAIZAAcK1xmjEQBfAQAZAAcK1xmjEQBfAQAAAA==.',
Ri='Riiver:BAAANQAECgUICQAAAA==.',
Ro='Roderick:BAAANQAECgMIAwAAAA==.Root:BAABNQAECn8/AAIRAAoKxiZqAACTAwARAAoKxiZqAACTAwAAAA==.',
Ru='Rubmytotem:BAAANQAECgYICwAAAA==.',
Sa='Sabazia:BAABNQAECn8tAAMbAAgKHxPfSADUAQAbAAgKHxPfSADUAQABAAIK1gVikwAmAAAAAA==.Sabelinå:BAAANQAECgQIBwAAAA==.Sable:BAAANQADCgEIAQAAAA==.Sacred:BAABNQAECn8YAAMSAAkKUhBFIAAAAQASAAgKvg9FIAAAAQAOAAIKzBOdlQCBAAAAAA==.Saerise:BAAANQAECgMIAwAAAA==.Sairalindë:BAAANQAECgcIDgAAAA==.Salamandra:BAAANQADCggIGQABNQAECgoKMgAgAHAaAA==.Saleath:BAAANQAECgIIAgAAAA==.Salios:BAAANQAECgEIAQAAAA==.Sanara:BAAANQABCgUIBwABNQAECgcIKgAQAN8NAA==.Sanctifier:BAAANQADCgUIBQAAAA==.',
Sc='Scrept:BAAANQAECggICgAAAA==.Scynix:BAEBNQAECn8cAAMUAAgKvQkhJwCAAQAUAAgKvQkhJwCAAQAkAAcKRQzADQBwAQAAAA==.Scÿph:BAEANQAECgMIBQABNQAECggIHAAUAL0JAA==.',
Se='Sedaline:BAAANQAECgEIAQAAAA==.Seizuregoat:BAAANQAECgMIAwAAAA==.Senus:BAAANQADCgEIAQAAAA==.Servoker:BAAANQAECggIEQAAAA==.',
Sh='Shabzshooter:BAAANQAECgUICgAAAA==.Shabzyt:BAABNQAECn8ZAAMBAAkKsRZdUADSAQABAAcK6hldUADSAQACAAcKVA6ZYAAWAQAAAA==.Shaienne:BAAANQADCgcIDgAAAA==.Shammander:BAABNQAECn8YAAIIAAcKngiXjgDuAAAIAAcKngiXjgDuAAAAAA==.Shamrockshak:BAAANQAECgIIBAAAAA==.Shamron:BAAANQADCgcICgAAAA==.Shenuton:BAABNQAECn8hAAIFAAkKsQhm0AA3AQAFAAkKsQhm0AA3AQAAAA==.Shieldbash:BAABNQAECn9EAAIGAAoKASb9AADNAwAGAAoKASb9AADNAwAAAA==.Shockthêràpy:BAABNQAECn8pAAMMAAoKjSKvHgDwAgAMAAoKjSKvHgDwAgAIAAEKzw4lMgE3AAAAAA==.Shoes:BAAANQAECgYICgAAAA==.Shtdruid:BAAANQAECgEIAQAAAA==.',
Si='Sibearian:BAABNQAECn8gAAMRAAoKuhtlEQAiAgARAAoKuhtlEQAiAgASAAMKTQyhLwCVAAAAAA==.Sibeson:BAABNQAECn8zAAMLAAoK2BPoCADJAQALAAkKjBXoCADJAQAKAAgKyAqurgB0AQABNQAECgoKIAARALobAA==.Simi:BAABNQAECn81AAIYAAoK+RPvTwAtAgAYAAoK+RPvTwAtAgAAAA==.',
Sm='Smithnwesson:BAAANQABCgcICgAAAA==.Smokesçreen:BAABNQAECn9GAAMfAAoKtxAkDQB8AQAfAAoKtxAkDQB8AQAXAAcKKQlqTwBcAQAAAA==.',
So='Soonerpride:BAABNQAECn8pAAIFAAkKbiNrOQCAAgAFAAkKbiNrOQCAAgAAAA==.Soothed:BAAANQADCggICAAAAA==.',
Sp='Spearminttea:BAAANQADCgIIAgAAAA==.Spellbreakr:BAACNQAFFH8KAAMHAAUKwAmZPgDAAAAHAAQKcQmZPgDAAAAaAAEKqgpwEgBOAAA1AAQKfysAAgcACgpUIGwqAJUCAAcACgpUIGwqAJUCAAAA.Spirtbreaker:BAABNQAECn8VAAIIAAgKnhLBmABnAQAIAAgKnhLBmABnAQAAAA==.Sprockette:BAAANQADCgIIAgAAAA==.',
Sq='Squeak:BAEANQADCgcIEAABNQAECgMIAwANAAAAAA==.Squiby:BAABNQAECn9SAAMWAAoKSCPrBQB5AwAWAAoKSCPrBQB5AwAeAAcKrCGZKQClAgAAAA==.',
St='Stankowitz:BAAANQABCgQICAABNQADCgYIBgANAAAAAA==.Starboi:BAAANQADCgUIBQAAAA==.Starce:BAAANQABCgMIAwAAAA==.Steveirwin:BAAANQADCgYICgAAAA==.Stheris:BAABNQAECn8zAAIiAAoKxBjLCQBBAgAiAAoKxBjLCQBBAgAAAA==.Stoops:BAAANQADCggICAAAAA==.Stuefester:BAABNQAECn8UAAMbAAcKTyAFPAATAgAbAAcKIh0FPAATAgABAAcK9x1AWgCnAQAAAA==.Stäirs:BAABNQAECn8gAAQDAAoKfBHJWgDuAQADAAoKhw/JWgDuAQAGAAEKTh4OOgBYAAAZAAEKVw85NgAzAAAAAA==.',
Sv='Sveika:BAABNQAECn8YAAIRAAcKFgZvSwCQAAARAAcKFgZvSwCQAAAAAA==.',
Sy='Sylaria:BAEANQAECgMIAwAAAA==.Syreline:BAAANQAECgQIBAAAAA==.',
['Sï']='Sïn:BAABNQAECn8mAAIKAAoKUhvgSgDzAQAKAAoKUhvgSgDzAQAAAA==.',
['Sý']='Sýlver:BAABNQAECn8hAAIOAAgKkwxcUQCXAQAOAAgKkwxcUQCXAQAAAA==.',
Ta='Tantric:BAAANQAECgMIAQABNQAECggIMwARAF8WAA==.Tarathiel:BAAANQADCgIIAgAAAA==.Tarpalantir:BAAANQADCgcICAAAAA==.Taurne:BAABNQAECn9DAAMPAAoKzBu7EwCPAgAPAAoKzBu7EwCPAgAOAAMKiQX6lwB5AAAAAA==.',
Tc='Tchnce:BAAANQADCgcICgAAAA==.',
Te='Teknoman:BAABNQAECn9BAAMDAAoKvxvLNABrAgADAAoKvxvLNABrAgAGAAEKWgq6SQApAAAAAA==.Telephone:BAAANQAECgEIBQAAAA==.Tempered:BAABNQAECn8rAAIDAAoKNRPZegCVAQADAAoKNRPZegCVAQABNQAECgoKOAATAMMWAA==.Tendrian:BAAANQAECgEIAQAAAA==.Teresen:BAAANQADCgIIAgAAAA==.',
Th='Thaitea:BAAANQADCgIIBAAAAA==.Thalindra:BAABNQAECn8qAAIYAAcKKw9BsABSAQAYAAcKKw9BsABSAQAAAA==.Tharain:BAAANQAECgQIBQAAAA==.Thebigbeast:BAABNQAECn8bAAMEAAcKiR0WJABOAQAEAAUKZh0WJABOAQAQAAYKzx06nwBHAQABNQAFFAkJIQAKANAYAA==.Thecurt:BAABNQAECn9PAAIgAAoKBSQ0AQBDAwAgAAoKBSQ0AQBDAwAAAA==.Thunderrbutt:BAABNQAECn8WAAIIAAcKoAw3kgB3AQAIAAcKoAw3kgB3AQABNQAECgoKHgAQAF0QAA==.Thyralizen:BAAANQADCgUICQAAAA==.',
Ti='Tiael:BAAANQAECgIIAgAAAA==.Timaeus:BAAANQADCggIGgAAAA==.Tinylef:BAABNQAECn8yAAQgAAoKcBrOCQCpAQAhAAcKpxePJwDlAQAgAAcKwh3OCQCpAQAoAAYKXhExHwAgAQAAAA==.Tirouke:BAAANQAECgQIBgAAAA==.Titanlock:BAAANQAECgIIAgAAAA==.',
Tk='Tkdfath:BAAANQADCgYIBgAAAA==.',
To='Toralina:BAAANQAECgEIAQAAAA==.Torvia:BAAANQAECgMIAwAAAA==.',
Tr='Trisinz:BAABNQAECn8dAAIOAAkKJQ35NABnAQAOAAkKJQ35NABnAQAAAA==.',
Tu='Tuerto:BAABNQAECn8qAAIYAAoKNRJlWgAVAgAYAAoKNRJlWgAVAgAAAA==.Tuiarmstrong:BAAANQAECgUIDwABNQAFFAYIEgAeAB0cAA==.Tuipasteur:BAACNQAFFH8SAAMeAAYKHRycDgCmAQAeAAYKHRycDgCmAQAnAAMK/QNVAQCsAAA1AAQKfzYABB4ACgq2IZEZAAsDAB4ACgq2IZEZAAsDABYABQp6C5hKAIAAACcAAgriCqkfAGQAAAAA.Tuithexiv:BAAANQAECgcIDwABNQAFFAYIEgAeAB0cAA==.Turbojohnson:BAAANQAECgEIAQAAAA==.Turk:BAABNQAECn9OAAIcAAoKcBXdHQBiAgAcAAoKcBXdHQBiAgAAAA==.Turkish:BAABNQAECn80AAICAAoKrA4yNwDEAQACAAoKrA4yNwDEAQAAAA==.',
Tw='Twinkytoes:BAAANQADCggIEwAAAA==.',
Ty='Tychaa:BAAANQADCgYIEgAAAA==.Tylat:BAAANQABCgMIAwAAAA==.Tyranay:BAABNQAECn9ZAAIeAAoKOCAoCwCLAwAeAAoKOCAoCwCLAwAAAA==.Tyrith:BAAANQADCgQIBQAAAA==.',
Ui='Uintah:BAABNQAECn8fAAIRAAoKTBm7DwA7AgARAAoKTBm7DwA7AgAAAA==.',
Ul='Ullyr:BAACNQAFFH8PAAIOAAYKwhGbCgBxAQAOAAYKwhGbCgBxAQA1AAQKf0IABA4ACgrhIHsLAOkCAA4ACgrhIHsLAOkCABEAAgrqG15GAKQAABIAAQoAAJVOABkAAAAA.',
Um='Umbryss:BAAANQAECgUIBwABNQAECgoKOgAXANMlAA==.',
Us='Userdel:BAABNQAECn8dAAIMAAYKXwj+vADwAAAMAAYKXwj+vADwAAAAAA==.',
Va='Vadose:BAAANQAECggICAABNQAECgoKNQAYAPkTAA==.Valytrois:BAAANQAECggICQAAAA==.Variant:BAAANQAECgMIAwAAAA==.Varinix:BAAANQAECgEIAQAAAA==.Vauld:BAAANQADCgQJBQAAAA==.',
Ve='Veiksla:BAAANQADCgYIGgAAAA==.Vengerr:BAAANQADCgYIFQAAAA==.Verace:BAAANQAECggICQAAAA==.Verradic:BAABNQAECn8fAAMJAAgKKgkCDQDvAAAJAAgKyggCDQDvAAAKAAcKYwaytQDoAAAAAA==.',
Vi='Vilanelle:BAAANQABCgUIBwAAAA==.Vitur:BAABNQAECn84AAIcAAkKxCN1AwChAwAcAAkKxCN1AwChAwAAAA==.Vivi:BAAANQADCgYIBgAAAA==.',
Vo='Voidbunny:BAAANQAECgYIDwAAAA==.Volaine:BAABNQAECn8oAAQJAAcKbwpCKQBXAAAKAAUKwgmk1QCnAAAJAAIKcgpCKQBXAAALAAEKCA1GKwA/AAAAAA==.Volgar:BAAANQADCgcIEgAAAA==.Volition:BAAANQADCgYIBgAAAA==.Volt:BAABNQAECn8nAAIVAAoKoxcpEABmAgAVAAoKoxcpEABmAgABNQAECgoKPgAKADYNAA==.Vorarephilia:BAAANQAECgUIBQAAAA==.',
Vr='Vrye:BAABNQAECn8cAAIcAAkKQwTnSwD6AAAcAAkKQwTnSwD6AAAAAA==.',
Vy='Vynaeda:BAABNQAECn8UAAIHAAcKEhSc6gC1AQAHAAcKEhSc6gC1AQAAAA==.',
['Vô']='Vôx:BAAANQAECgIIBQABNQAECgcIDAANAAAAAA==.',
Wa='Wakko:BAAANQADCgcIEwAAAA==.Walkure:BAAANQADCgYIHAAAAA==.',
We='Weirdscience:BAAANQABCgQIBAAAAA==.Wetasstotem:BAABNQAECn8dAAMIAAoK5BzkKwDPAgAIAAoK5BzkKwDPAgAMAAYKrhUZbABwAQABNQAFFAkJIQAKANAYAA==.',
Wh='Whew:BAAANQADCggICQAAAA==.',
Wi='Widge:BAAANQAECgQIBAAAAA==.Wikker:BAAANQADCgQIBAAAAA==.Wishy:BAAANQABCgQIBgAAAA==.',
Wo='Worldlight:BAAANQADCgIIAgAAAA==.',
Wr='Wreckbums:BAAANQAECgMIBAAAAA==.Wreckd:BAABNQAECn8ZAAIcAAgKVRDnIwB+AQAcAAgKVRDnIwB+AQABNQAECgoKOAATAMMWAA==.Wrongway:BAAANQADCgcICgAAAA==.',
Xa='Xanthad:BAAANQADCgUICAAAAA==.',
Xb='Xb:BAAANQADCgYIFgAAAA==.',
Xi='Xitãozinho:BAAANQAECgQIBwAAAA==.',
Xy='Xyomi:BAAANQADCgcIBwAAAA==.',
Ya='Yaalia:BAABNQAECn8qAAMQAAcK3w1bfQA9AQAQAAcK3w1bfQA9AQAFAAYKWwSdGgHCAAAAAA==.Yaan:BAABNQAECn8aAAIIAAoK+gtKYwBdAQAIAAoK+gtKYwBdAQAAAA==.Yalane:BAAANQAECgMIAwAAAA==.',
Yo='Yogi:BAAANQAECgUIBQAAAA==.',
Za='Zain:BAAANQADCgYIBgABNQAECgoKVgAJAAAdAA==.Zalaan:BAAANQAECgcIEgABNQAECgoKKAAHAM4bAA==.Zandibar:BAABNQAECn8jAAIZAAcKQRL2FAApAQAZAAcKQRL2FAApAQAAAA==.Zaptoasted:BAAANQADCgYIBgAAAA==.Zariea:BAAANQAECgIIAgABNQAECggIKgABAMcVAA==.Zavac:BAAANQADCgUIBwAAAA==.',
Ze='Zellezugtail:BAAANQADCgYIBgABNQAECgoKHQAKADAFAA==.Zelritch:BAAANQADCggICAAAAA==.',
Zi='Zinfandell:BAAANQAECgUICwAAAA==.',
Zo='Zorrloc:BAAANQADCgQIBAAAAA==.',
Zu='Zuggie:BAABNQAECn8dAAIKAAoKMAUlkQA4AQAKAAoKMAUlkQA4AQAAAA==.Zugtail:BAAANQAECgEIAQABNQAECgoKHQAKADAFAA==.Zurtrinik:BAAANQAECgUICwABNQAFFAcIFgAgAAAZAA==.',
Zy='Zyntalla:BAABNQAECn8oAAMcAAcK0w0jMQAPAQAcAAcK0w0jMQAPAQAfAAMKjwyIJwBXAAAAAA==.',
Zz='Zzonked:BAAANQAECgEIAQAAAA==.',
['Zê']='Zêp:BAAANQADCgcIFwAAAA==.',
['Àr']='Àrròw:BAAANQADCgYICgAAAA==.',
['Ðo']='Ðoogle:BAABNQAECn8bAAMVAAkK/gwGGwBpAQAVAAkK/gwGGwBpAQAMAAIKdRDjAwFhAAABNQADCgIIAgANAAAAAA==.',
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
