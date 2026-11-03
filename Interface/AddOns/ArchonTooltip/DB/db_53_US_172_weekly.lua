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
local provider = {region='US',realm='Perenolde',name='US',type='weekly',zone=53,date='2026-11-03',data={Ac='Acedk:BAABNQAECn8hAAMBAAkKoiEyGgDvAgABAAkKPCAyGgDvAgACAAUKdiAWRACyAQAAAA==.Aceslam:BAABNQAECn8YAAIDAAgKuiFKMwDzAgADAAgKuiFKMwDzAgABNQAECgkJIQABAKIhAA==.',
Ad='Adrador:BAABNQAECn87AAMEAAoKlRyjCQADAwAEAAkKLx+jCQADAwAFAAcKLhJZ0AD5AAAAAA==.Adrenaline:BAACNQAFFH8UAAIGAAUK5yCBAQAfAQAGAAUK5yCBAQAfAQA1AAQKf0IAAgYACgrfJHoCAI4DAAYACgrfJHoCAI4DAAAA.',
Ae='Aelik:BAABNQAECn8qAAIBAAgKxxXLaABuAQABAAgKxxXLaABuAQAAAA==.Aeolian:BAAANQADCgYIDgAAAA==.Aeru:BAAANQADCgQIBAAAAA==.',
Af='Afk:BAAANQAECgMIAwAAAA==.',
Aj='Ajaila:BAAANQADCgQIBAAAAA==.',
Ak='Akueria:BAAANQADCgcIBwAAAA==.',
Al='Alayssa:BAABNQAECn8mAAIHAAoKzhvUKAB+AgAHAAoKzhvUKAB+AgAAAA==.Alda:BAAANQADCgYIFgAAAA==.Alemental:BAABNQAECn8bAAIIAAoK1gtQRQCFAQAIAAoK1gtQRQCFAQAAAA==.Aleska:BAABNQAECn8VAAQJAAcKURaACwDgAAAKAAYKvgyZ6AD4AAAJAAUKXRaACwDgAAALAAEKXwzsLQA6AAAAAA==.Allarius:BAAANQAECgUIBAAAAA==.Allevist:BAAANQAECgMIAwABNQAECggIKAAHAGIGAA==.Alo:BAABNQAECn85AAIMAAoKvxbGPgBlAgAMAAoKvxbGPgBlAgABNQAECgEJAQANAAAAAA==.',
Am='Amilee:BAAANQAECgEIAQAAAA==.Amoondai:BAAANQADCgYICAAAAA==.Amoondrin:BAABNQAECn8oAAMOAAoKZQceNwAjAQAOAAoKZQceNwAjAQAPAAEK3wPDewAnAAAAAA==.',
An='Analiya:BAAANQADCgQJBQAAAA==.Anatyr:BAAANQAECgIIAgAAAA==.Andoria:BAAANQABCggICwAAAA==.',
Ar='Aramathis:BAAANQAECgUIBQAAAA==.Araviin:BAAANQAECgUICAAAAA==.Arbor:BAAANQAECgQIBwAAAA==.Arcillias:BAABNQAECn8bAAMQAAkK0xWRMQAmAgAQAAkK0xWRMQAmAgAFAAEKDAJmfAEpAAABNQAECgYIDAANAAAAAA==.Arilas:BAAANQAECgQICAABNQAECgYIDAANAAAAAA==.Arkanist:BAABNQAECn8oAAIHAAgKYgYhugAIAQAHAAgKYgYhugAIAQAAAA==.Arthia:BAAANQADCgYICQAAAA==.Arvidpally:BAABNQAECn8VAAIFAAcKiweo3wDgAAAFAAcKiweo3wDgAAAAAA==.',
As='Ashesius:BAABNQAECn9PAAQJAAoKAB3dAQBVAgAJAAoKAB3dAQBVAgAKAAMKYQmcHgGHAAALAAIKaxyHHgCHAAAAAA==.Ashmehameha:BAAANQAECgMIBAABNQAECggIDAANAAAAAA==.Ashstabber:BAAANQAECgMIAwABNQAECggIDAANAAAAAA==.',
At='Atredes:BAAANQAECgYIDQAAAA==.',
Au='Auspex:BAABNQAECn8oAAIRAAoKjwmZJAAnAQARAAoKjwmZJAAnAQAAAA==.',
Av='Avaryn:BAABNQAECn8aAAIPAAkKiBbVHwAtAgAPAAkKiBbVHwAtAgAAAA==.',
Ax='Aximlii:BAAANQADCgUICQAAAA==.',
Ba='Babavoss:BAAANQAECggIEAAAAA==.Babs:BAAANQADCgcIDAAAAA==.Badaracka:BAACNQAFFH8LAAISAAYKPw0wAQCoAQASAAYKPw0wAQCoAQA1AAQKf0cABBIACgppJL4BADUDABIACgppJL4BADUDABEACAojHeYRANwBAA4ABgpqFMkwAEgBAAAA.Badash:BAAANQAECgQIDAABNQAECggIDAANAAAAAA==.Bahamuth:BAABNQAECn9BAAIFAAoKxBolMgBuAgAFAAoKxBolMgBuAgAAAA==.Bahamutsrage:BAAANQADCggIDgABNQAECgcIFwAJAH4HAA==.Balder:BAAANQAECggIGQABNQAFFAUIDwANAAAAAQ==.Bandage:BAAANQAECgYIBgABNQAECgoKKgATAFUTAA==.Barbattos:BAACNQAFFH8UAAIUAAUK3BleCgCEAQAUAAUK3BleCgCEAQA1AAQKfzgAAhQACgroIxUGAEgDABQACgroIxUGAEgDAAAA.Batmon:BAAANQAECgUIBQAAAA==.',
Bd='Bdyrk:BAABNQAECn8ZAAIVAAgKDw+3FACCAQAVAAgKDw+3FACCAQABNQAFFAYICwASAD8NAA==.',
Be='Bealzeboss:BAAANQADCgcICQAAAA==.Bexley:BAABNQAECn89AAIEAAoKjiAqBQDxAgAEAAoKjiAqBQDxAgAAAA==.',
Bi='Biggerbunny:BAABNQAECn8fAAIWAAoKahHqJQD/AQAWAAoKahHqJQD/AQAAAA==.Biglarry:BAAANQADCgMJBQAAAA==.Biianca:BAAANQADCgUICQAAAA==.',
Bl='Blacklok:BAAANQAECgIIBAABNQAECgoKOAAXANMlAA==.Blanne:BAAANQABCgIIAgAAAA==.Blargle:BAAANQAECgUIDAAAAA==.Blegh:BAACNQAFFH8HAAIFAAMKARnHFQABAQAFAAMKARnHFQABAQA1AAQKfyQAAgUACgoNILwvAAoDAAUACgoNILwvAAoDAAAA.Blessyaheart:BAAANQAECgUIEAABNQAECgcIFgAIAKAMAA==.Blincyto:BAAANQAECgEIAQAAAA==.Blinx:BAAANQAECgEIAgAAAA==.Bloodrake:BAABNQAECn9DAAIYAAoKGhiFNwA5AgAYAAoKGhiFNwA5AgAAAA==.Blueray:BAAANQADCgYIBgAAAA==.',
Bm='Bman:BAABNQAECn8eAAIDAAcKVRpIYAClAQADAAcKVRpIYAClAQAAAA==.',
Br='Braneour:BAABNQAECn82AAMEAAoKShJzJwCjAQAEAAoKShJzJwCjAQAQAAYK1QcEswAYAQAAAA==.Bravisimo:BAAANQAECgIIAgAAAA==.Browel:BAABNQAECn8jAAIKAAoKdxhkTgBpAgAKAAoKdxhkTgBpAgAAAA==.',
Bu='Bubblfett:BAAANQAECggICQAAAA==.Bumm:BAAANQAECgMIAwAAAA==.',
Bz='Bzspy:BAABNQAECn8xAAMDAAoKxBknYwBlAgADAAoKxBknYwBlAgAZAAIK9ApMKwBZAAAAAA==.',
['Bë']='Bëar:BAAANQAECgEIAQAAAA==.',
Ca='Cabooselul:BAAANQAECgUICgAAAA==.Calyptus:BAABNQAECn8yAAMJAAkKew9TBACbAQAJAAkK6w5TBACbAQAKAAMK1gnjywCKAAAAAA==.Capylaura:BAAANQAECgMIBgAAAA==.Caratine:BAAANQADCgcIDQAAAA==.Cassandrah:BAABNQAECn9DAAIHAAoKyx69KgB2AgAHAAoKyx69KgB2AgAAAA==.',
Ce='Celìa:BAABNQAECn8XAAIYAAoKPgUBmwA3AQAYAAoKPgUBmwA3AQAAAA==.',
Ch='Chillymage:BAAANQADCgcIBwAAAA==.Chpchop:BAAANQABCggIEQAAAA==.Christy:BAAANQADCgYIGwAAAA==.Chugg:BAABNQAECn8rAAIMAAgKWAYBfAANAQAMAAgKWAYBfAANAQAAAA==.',
Ci='Ciaphus:BAABNQAECn82AAQFAAoKqxCbtwCvAQAFAAgK6A+btwCvAQAQAAoKOQq1TwChAQAEAAcKNgxENgA1AQAAAA==.Cinnamonster:BAABNQAECn8aAAMJAAkKKgsQCgD3AAAKAAYKJAs/5gD8AAAJAAgK4ggQCgD3AAAAAA==.',
Cl='Clogs:BAAANQAECgUIBgAAAA==.',
Co='Coffeedemon:BAAANQAECgQIBgAAAA==.Coldslappins:BAAANQAECgMIAwABNQAECgoKNgAEAEoSAA==.Convalescent:BAAANQADCgYIBgAAAA==.Coragrr:BAAANQAECgIIAwAAAA==.',
Cr='Cracklepants:BAACNQAFFH8KAAIIAAUKaAlMEABoAQAIAAUKaAlMEABoAQA1AAQKf0IAAggACgqTITQXAD0DAAgACgqTITQXAD0DAAE1AAUUBQgOAA4AEBAA.Crashout:BAAANQAECggIEQAAAA==.',
Cu='Curtastrophe:BAABNQAECn9EAAIaAAoK2yIpAQCQAwAaAAoK2yIpAQCQAwAAAA==.Curticus:BAAANQADCgYIBgAAAA==.',
Da='Daelanos:BAABNQAECn8ZAAIDAAgKIAtbrwCmAQADAAgKIAtbrwCmAQAAAA==.Dallas:BAAANQAECggICgAAAA==.Danorman:BAAANQADCgQIBAABNQAECgIIAwANAAAAAA==.',
De='Deathisreal:BAAANQADCgEIAgABNQAECgQIBQANAAAAAA==.Deathoof:BAABNQAECn8sAAQBAAkK+RUfFwAFAgABAAkK+RUfFwAFAgAbAAMK/hHKlwCuAAACAAEKGgWKtAArAAABNQAECgoKJgALAEgQAA==.Demonblaze:BAAANQAECgIIBgAAAA==.Demonilla:BAABNQAECn8qAAIcAAoK2xlrDQBZAgAcAAoK2xlrDQBZAgAAAA==.Destro:BAABNQAECn80AAIKAAoKpQwMTQC1AQAKAAoKpQwMTQC1AQAAAA==.',
Di='Dilaudyd:BAAANQAECgIIAgAAAA==.Disbeleaf:BAAANQAECgcIEQAAAA==.Dishu:BAAANQABCgQIBAAAAA==.Dispel:BAAANQADCgYIBgAAAA==.Disputatious:BAAANQADCgQIBAAAAA==.',
Dn='Dntblink:BAAANQADCgUIBQAAAA==.',
Do='Dogaz:BAAANQADCgYIGwAAAA==.Dogsoldier:BAAANQADCgQIBAAAAA==.Donori:BAAANQAECgYIBwAAAA==.Doomphoenix:BAAANQAECgQIAgAAAA==.',
Dr='Dragonias:BAABNQAECn8aAAIdAAcKQAeAKwDYAAAdAAcKQAeAKwDYAAAAAA==.Drakthorn:BAAANQADCggIGQAAAA==.Drinny:BAABNQAECn8xAAIeAAoKfgXHWwCUAQAeAAoKfgXHWwCUAQAAAA==.Dripington:BAACNQAFFH8GAAICAAUKFxSECwDcAAACAAUKFxSECwDcAAA1AAQKfysAAwIACgqZIZUUAOgCAAIACgqZIZUUAOgCAAEAAQoAAGngADMAAAAA.',
Ea='Earthangel:BAABNQAECn8fAAIeAAcK4gdYgAAdAQAeAAcK4gdYgAAdAQAAAA==.',
Ef='Efon:BAAANQADCgUIBQABNQAECgoKJgAHAM4bAA==.',
Ei='Eine:BAABNQAECn85AAIYAAoKrhGIRwAGAgAYAAoKrhGIRwAGAgAAAA==.',
El='Eldergreen:BAAANQAECgYIEQAAAA==.Elfwine:BAABNQAECn8fAAIWAAcK7AifKQD8AAAWAAcK7AifKQD8AAAAAA==.Elindria:BAABNQAECn84AAMXAAoK0yXCBACnAwAXAAoKiyXCBACnAwAfAAUKwSRwDgAsAQAAAA==.Elminstir:BAABNQAECn8nAAIaAAkKhhX1CgAWAgAaAAkKhhX1CgAWAgAAAA==.Eluzhion:BAAANQADCgUICAAAAA==.Elysian:BAAANQAECgUICQAAAA==.',
Er='Erisa:BAAANQADCgMIAwAAAA==.Erizhal:BAAANQABCgIIAgAAAA==.Eruptyon:BAAANQAECgEIAQABNQAECgkJKQAHAFkgAA==.',
Es='Esabel:BAAANQAECgcIDgABNQAECgoKJgAHAM4bAA==.',
Ev='Eviae:BAABNQAECn8fAAIbAAcKwAQiWAC5AAAbAAcKwAQiWAC5AAAAAA==.Evillure:BAAANQAECgYICgAAAA==.',
Ex='Explanation:BAAANQADCgQIBAAAAA==.',
Fa='Falan:BAAANQAECgEIAQAAAA==.Farfins:BAAANQADCgYIBgAAAA==.',
Fe='Fedor:BAAANQAECggICAAAAA==.Feår:BAABNQAECn8dAAMKAAkKOhCJYQB3AQAKAAcKPRCJYQB3AQAJAAIKMBAsWwBvAAAAAA==.',
Fi='Finley:BAAANQADCgQIBAAAAA==.Fixation:BAAANQABCgIIAgAAAA==.',
Fl='Flane:BAACNQAFFH8WAAIgAAcKABm+AQD2AQAgAAcKABm+AQD2AQA1AAQKfzUAAyAACgq2IokBABADACAACgq2IokBABADACEAAQoAAEdkAE4AAAAA.Flexdruid:BAAANQAECgUIBQAAAA==.',
Fr='Fragil:BAABNQAECn82AAMiAAoKDSA2FwDCAgAiAAoK7xs2FwDCAgATAAgKKx/PKAApAgAAAA==.Frostmane:BAAANQAECggIDgABNQAFFAUIDgAOABAQAA==.Frostssiah:BAAANQAECgQIBAAAAA==.',
Ga='Galena:BAABNQAECn8cAAIPAAgKhRJHIQCfAQAPAAgKhRJHIQCfAQAAAA==.Galian:BAAANQADCggIEgAAAA==.Ganonn:BAAANQAECgQICQABNQAECgcIEQANAAAAAA==.',
Ge='Geshtal:BAABNQAECn8YAAMXAAgKAwwbNQA4AQAXAAgKAwwbNQA4AQAfAAEKAAAcNAAsAAAAAA==.',
Gi='Girion:BAABNQAECn8fAAIEAAcKEA5qKgDuAAAEAAcKEA5qKgDuAAAAAA==.',
Gl='Glaiven:BAECNQAFFH8QAAIXAAUK+xOMCwBnAQAXAAUK+xOMCwBnAQA1AAQKfzUAAxcACgotIpAOADEDABcACgotIpAOADEDABwABwoxFzoxALcBAAAA.Glyr:BAAANQAECgEJAQAAAA==.',
Gn='Gnofear:BAAANQABCggIEwABNQAECgUICwANAAAAAA==.Gnora:BAAANQADCggIEwAAAA==.Gnova:BAAANQADCgQIBQAAAA==.',
Go='Gorgrin:BAAANQAECggIEAAAAA==.',
Gr='Groguu:BAAANQAECgQIBAABNQAECgkJIQABAKIhAA==.',
Ha='Harkanum:BAABNQAECn8sAAMjAAgKSAq+HACBAQAjAAgKSAq+HACBAQAUAAgK6QQ1KwBSAQAAAA==.Harvester:BAAANQAECgQIDwAAAA==.',
He='Healinturds:BAAANQADCgEIAQAAAA==.Healsurazz:BAAANQADCgQIBAAAAA==.Helloagain:BAABNQAECn8WAAIHAAkK3RucfgCBAgAHAAkK3RucfgCBAgAAAA==.',
Hi='Hidethetotem:BAAANQAECgYIEgAAAA==.Hiimdeath:BAAANQADCgMIAwABNQAECgQIBQANAAAAAA==.Hikari:BAACNQAFFH8MAAIFAAYKJwy8EwDHAAAFAAYKJwy8EwDHAAA1AAQKfzEAAgUACgrWHaEsAIYCAAUACgrWHaEsAIYCAAAA.Hiown:BAAANQABCgYICAAAAA==.',
Ho='Holyrebel:BAAANQAECgQIBQAAAA==.Holyspike:BAABNQAECn8cAAMMAAgKqhIaSQC8AQAMAAgKqhIaSQC8AQAIAAEKAAB4DAEAAAAAAA==.Homerr:BAABNQAECn8ZAAIYAAcKcwt+oAAsAQAYAAcKcwt+oAAsAQAAAA==.Honiahaka:BAABNQAECn9JAAIYAAoK+BGIPgAiAgAYAAoK+BGIPgAiAgAAAA==.Hotsdog:BAAANQADCgIIAgAAAA==.Hottcakes:BAABNQAECn9CAAIHAAoKgiElDwCWAwAHAAoKgiElDwCWAwABNQAFFAgIGQAKADMTAA==.',
Hu='Humanoidlite:BAAANQAFFAEIAgABNQAFFAQICQADAP0JAA==.Humanoidlock:BAAANQADCgcIDAABNQAFFAQICQADAP0JAA==.Humanoidwar:BAACNQAFFH8JAAMDAAQK/QnzGQC8AAADAAQK/QnzGQC8AAAGAAEKoAP3CgAtAAA1AAQKfzIAAwMACgoEHy40APACAAMACgoEHy40APACAAYABQr+D50pAO4AAAAA.',
['Hà']='Hàvòc:BAAANQADCgQIBAAAAA==.',
['Hö']='Hölyçow:BAAANQADCgUIBQAAAA==.',
Ic='Icedtea:BAAANQAECgQIBAAAAA==.',
In='Inoru:BAAANQAECgYIDAAAAA==.Intgrumblyeo:BAAANQAECggICQAAAA==.',
Ip='Ipseity:BAAANQABCgMIAwAAAA==.',
Ir='Irmaline:BAABNQAECn8cAAIeAAgKbw6fXwCHAQAeAAgKbw6fXwCHAQAAAA==.',
It='Ithurtshuh:BAAANQAECgIIBQABNQAECgQIBQANAAAAAA==.',
Ja='Jabbawockie:BAABNQAECn8XAAIXAAgKFwhqYwDsAAAXAAgKFwhqYwDsAAAAAA==.Jackcat:BAAANQADCgQIAwAAAA==.Jackyl:BAAANQABCgYIBgAAAA==.',
Je='Jeffee:BAABNQAECn8jAAICAAkKsxgPKQBQAgACAAkKsxgPKQBQAgAAAA==.Jennifleur:BAAANQADCgcIBwAAAA==.Jequalsjosh:BAABNQAECn8dAAIiAAkKfBIsHQApAQAiAAkKfBIsHQApAQAAAA==.Jerk:BAACNQAFFH8XAAIcAAcKYB++BADxAQAcAAcKYB++BADxAQA1AAQKfz8AAhwACgrHJTgEAJIDABwACgrHJTgEAJIDAAAA.Jesper:BAABNQAECn9PAAIMAAoKTSBdDQAzAwAMAAoKTSBdDQAzAwAAAA==.Jetz:BAAANQAECgQICQAAAA==.Jetzul:BAAANQAECgMIAwAAAA==.Jezelle:BAAANQADCggICAAAAA==.',
Ji='Jilara:BAABNQAECn8ZAAIFAAYKFQgL4gDcAAAFAAYKFQgL4gDcAAAAAA==.Jimmyjim:BAABNQAECn8WAAIaAAgKIwl9EgAnAQAaAAgKIwl9EgAnAQAAAA==.',
Jo='Joink:BAAANQADCgYICQAAAA==.',
Jp='Jpepps:BAABNQAECn8mAAMKAAgK2A0tigDNAQAKAAgK2A0tigDNAQAJAAMKcAThXgBoAAAAAA==.',
Jr='Jrose:BAAANQADCggIGQAAAA==.',
Ka='Kagozo:BAEANQAECgEIAQABNQAECgIIAgANAAAAAA==.Kahlanrahl:BAAANQADCgIIAgAAAA==.Kaiatra:BAABNQAECn8cAAICAAgKEhhhPADcAQACAAgKEhhhPADcAQAAAA==.Kalamor:BAAANQAECgUIBQAAAA==.Kaliguala:BAAANQADCgUIBwAAAA==.Kaloran:BAAANQAECgcIDgAAAA==.Katalaystar:BAAANQADCgYIDAABNQAECgoKRgAPAHYhAA==.Katalegdh:BAAANQAECgcIDwAAAA==.Kaìju:BAABNQAECn8jAAIFAAgK9h+eTQANAgAFAAgK9h+eTQANAgAAAA==.',
Ke='Kellytgt:BAAANQAECggIDAAAAA==.',
Kh='Khaelyn:BAAANQADCgQIBQAAAA==.Khai:BAABNQAECn8WAAIFAAgKyA1X4ABbAQAFAAgKyA1X4ABbAQAAAA==.',
Ki='Kiae:BAAANQADCgYJBwAAAA==.Kidneyspears:BAAANQADCgYICAAAAA==.Kilaura:BAAANQADCgUIBQAAAA==.Kilmandaros:BAAANQAECgUIBgAAAA==.Kimblee:BAAANQADCgQIBAAAAA==.',
Ko='Korbix:BAAANQABCgUIBAABNQAECgUICwANAAAAAA==.',
Kr='Kraxxas:BAAANQAECggICAAAAA==.Kronmon:BAAANQADCgQIBAAAAA==.',
Ku='Kudria:BAABNQAECn8oAAIYAAgKzxXdcACWAQAYAAgKzxXdcACWAQAAAA==.Kunei:BAAANQABCgYICQABNQAECgIIAwANAAAAAA==.Kurdran:BAAANQABCgQIBAAAAA==.Kuroyukihime:BAABNQAECn8vAAIaAAoKHBtNBgCfAgAaAAoKHBtNBgCfAgAAAA==.',
Ky='Kynae:BAAANQAECgQIEQAAAA==.Kyross:BAAANQABCgIIAgAAAA==.',
['Ká']='Kárma:BAAANQADCgYICwABNQAECgkJHQAKADoQAA==.',
La='Lashela:BAABNQAECn8pAAIdAAgK6gY1IwAWAQAdAAgK6gY1IwAWAQAAAA==.Laughter:BAABNQAECn8UAAIGAAcKuAXcIAC/AAAGAAcKuAXcIAC/AAAAAA==.Lavamylash:BAAANQAECgcIEQAAAA==.Laylla:BAAANQAECgQICgAAAA==.Lazulie:BAAANQAECgYICAAAAA==.',
Le='Lefnedrav:BAAANQADCgYICgABNQAECgoKMQAgAHAaAA==.Lektrik:BAAANQAECgUICgAAAA==.Lenexa:BAAANQADCgUICAAAAA==.Lexapayne:BAAANQADCgEIAQABNQAECgoKKAAYAAUTAA==.Leyra:BAABNQAECn8nAAIdAAoKFxpPDQA7AgAdAAoKFxpPDQA7AgABNQAECgoKOAAXANMlAA==.',
Li='Lighthammer:BAAANQADCggIDgAAAA==.Lightmessiah:BAABNQAECn8wAAQFAAoKshqsfgAsAgAFAAgKGBmsfgAsAgAQAAgKFBaeMgAhAgAEAAIKgwYjYwAiAAAAAA==.Lightnig:BAAANQADCgUIBQAAAA==.Lilyvain:BAAANQAECgEIAQAAAA==.Lireal:BAABNQAECn8gAAMQAAoKKx7MIwDcAgAQAAkKNB3MIwDcAgAFAAEKKAyOcQExAAAAAA==.Livnod:BAAANQAECgMIAgAAAA==.',
Lo='Logdiir:BAAANQAECgMIAwAAAA==.Lonon:BAABNQAECn8XAAIIAAgKJA5tcwDHAQAIAAgKJA5tcwDHAQAAAA==.Loosescrew:BAAANQADCgQIBQAAAA==.Lorine:BAABNQAECn9CAAIEAAoKoRurCQBxAgAEAAoKoRurCQBxAgAAAA==.',
Lu='Lunara:BAAANQADCgYIDAAAAA==.',
Ly='Lynnethe:BAAANQAECgYIDgAAAA==.Lyyse:BAAANQADCgIIAgAAAA==.',
Ma='Malkiel:BAAANQAECgQIDgAAAA==.Mantang:BAAANQABCgIIAgAAAA==.Mastakillah:BAAANQADCgQICAABNQAECgUIEQANAAAAAA==.Maxamus:BAAANQAECgEIAgAAAA==.',
Me='Meeseeks:BAAANQAECgcIDQAAAA==.Merckel:BAABNQAECn84AAIcAAoKJB1READvAgAcAAoKJB1READvAgAAAA==.Messorom:BAAANQADCgEIAQAAAA==.',
Mi='Michello:BAABNQAECn8cAAIYAAgK9A+KcgCRAQAYAAgK9A+KcgCRAQAAAA==.Mightytot:BAAANQAECgQIAwAAAA==.Millia:BAABNQAECn8pAAMHAAkKWSACdwCPAQAHAAcKOyECdwCPAQAaAAIKJh6rKQCqAAAAAA==.Mint:BAABNQAECn8fAAIQAAkKGBW5QgBaAgAQAAkKGBW5QgBaAgAAAA==.Mintberrytea:BAAANQAECgQJBAABNQAECgkJHwAQABgVAA==.Misstress:BAABNQAECn8qAAMOAAoKxguCKQB6AQAOAAoKxguCKQB6AQARAAEKAABzcAAdAAAAAA==.',
Mo='Moistweaver:BAAANQADCgYIBgAAAA==.Monkussy:BAAANQADCgUIBQAAAA==.Monoxide:BAAANQADCgUIBQABNQAECgkJFAAXAMcQAA==.Mooncloud:BAAANQAECgIIAgAAAA==.Moonhunt:BAAANQAECgQIBAAAAA==.Morkleb:BAAANQAECgYIDAAAAA==.Morrag:BAABNQAECn8rAAMKAAkKiQhpcwBHAQAKAAkKiQhpcwBHAQAJAAEKAAB0OgAAAAAAAA==.Morrtisha:BAAANQAECgcIDAAAAA==.',
Mu='Munchkins:BAAANQABCgcIDQAAAA==.Munden:BAAANQADCgUIBQABNQAECgQIDgANAAAAAA==.',
My='Myxie:BAABNQAECn8pAAIMAAgKURYLSwC0AQAMAAgKURYLSwC0AQAAAA==.',
['Mí']='Mísfìt:BAABNQAECn9EAAIMAAoKXx/NDAA7AwAMAAoKXx/NDAA7AwAAAA==.',
Na='Nakaito:BAABNQAECn8UAAIKAAgK4Ae0vwBMAQAKAAgK4Ae0vwBMAQABNQAECgoKOQAiAM4TAA==.Narcoleptic:BAABNQAECn9IAAQUAAoKxxeNCACMAgAUAAoKxxeNCACMAgAjAAUKzQuYJgABAQAkAAYK2hF9DQDfAAAAAA==.Nashty:BAAANQADCgIIAgAAAA==.Naturaljuice:BAAANQAECggIEwABNQAFFAgIGQAKADMTAA==.Naturebreakr:BAABNQAECn8bAAIOAAkKwhK+PQAKAgAOAAkKwhK+PQAKAgAAAA==.',
Ne='Nex:BAABNQAECn88AAIHAAoKDiFSJACSAgAHAAoKDiFSJACSAgAAAA==.',
Ni='Niceshield:BAAANQAECgYIBwAAAA==.Nightsawdy:BAABNQAECn8jAAMYAAcKhhSUjABVAQAYAAcKhhSUjABVAQAlAAEKLRNYDwBLAAAAAA==.Niightstorm:BAABNQAECn8dAAMYAAYK/w/wyABwAQAYAAYK/w/wyABwAQAlAAEKAAB/EwAAAAAAAA==.Nilvannas:BAAANQADCggICAAAAA==.Nitefire:BAAANQADCgYIGgAAAA==.Nitélifé:BAAANQAECgcIDgAAAA==.',
Of='Offspring:BAAANQABCgIIAgAAAA==.',
Om='Omora:BAABNQAECn8lAAQEAAoK2RawDgAJAgAEAAoK2RawDgAJAgAQAAYKWgm5rwAgAQAFAAIKmwwfcgFrAAABNQAECgoKMQAgAHAaAA==.',
Op='Opalinnas:BAABNQAECn9GAAIPAAoKdiFUBgBNAwAPAAoKdiFUBgBNAwAAAA==.Optimism:BAAANQADCgIIAgAAAA==.',
Pa='Paladrone:BAAANQABCggIDwABNQADCgcICgANAAAAAA==.Palestrina:BAAANQADCgMIAwAAAA==.Pallyandtank:BAAANQAECgEIAQAAAA==.Panzer:BAABNQAECn8xAAIRAAgK2hQ5IABIAQARAAgK2hQ5IABIAQAAAA==.Parts:BAABNQAECn8qAAQTAAoKVRNNTACDAQATAAcKPxZNTACDAQAiAAYKwg+MUAB8AQAmAAMK0gpNFQCbAAAAAA==.Passionfruit:BAAANQAECgcIBwAAAA==.Paul:BAAANQAECgUICgAAAA==.',
Pe='Peachtea:BAAANQAECgYICwAAAA==.Pepecojon:BAAANQADCggIDwAAAA==.',
Pi='Piebaby:BAAANQADCgUIBgAAAA==.Pirodeath:BAAANQAECgYICAAAAA==.',
Pl='Plovdiv:BAAANQADCgcJCQAAAA==.',
Po='Poah:BAAANQAECgYIBgAAAA==.',
Pr='Pray:BAABNQAECn9JAAMeAAoKgiV3AQAoBAAeAAoKGyV3AQAoBAAnAAgKMiR5AQA5AwAAAA==.Prodarkangel:BAAANQADCgcJCQAAAA==.',
Pu='Puckllane:BAAANQAECgEIAgAAAA==.Punkin:BAAANQAECgIIAgAAAA==.',
Py='Pyre:BAABNQAECn80AAMnAAoKCQ2VCgCeAQAeAAoK0gaSVwCjAQAnAAgKWg2VCgCeAQABNQAECgEJAQANAAAAAA==.',
['Pü']='Püff:BAAANQADCgEIAQABNQAECgYIDAANAAAAAA==.',
Qu='Quanah:BAABNQAECn8cAAIMAAgKrB5/KgBNAgAMAAgKrB5/KgBNAgAAAA==.Quivver:BAAANQADCgYIGAAAAA==.',
Ra='Rabmaxx:BAABNQAECn8mAAIXAAkK6gTuVwAqAQAXAAkK6gTuVwAqAQAAAA==.Raina:BAAANQAECgEIAQAAAA==.Rap:BAAANQAECgMIAwAAAA==.Ravenlight:BAACNQAFFH8JAAIFAAQKXgbjFgCuAAAFAAQKXgbjFgCuAAA1AAQKfyQAAgUACgolFlJ1AEMCAAUACgolFlJ1AEMCAAAA.Ravenwynnd:BAABNQAECn84AAMDAAoKjCHWFQDiAgADAAoKjCHWFQDiAgAGAAYKFh23FQDMAQAAAA==.Raynman:BAABNQAECn9CAAMIAAoKUhOrMADfAQAIAAoKUhOrMADfAQAMAAoKjATfXwBmAQAAAA==.',
Re='Restotuition:BAAANQABCgQICAABNQAFFAUIEQAeABkcAA==.Reylariel:BAAANQADCgMIAwAAAA==.',
Rh='Rhydian:BAAANQADCgQIBAAAAA==.Rhyzer:BAABNQAECn8fAAIZAAcK3xhDDgBXAQAZAAcK3xhDDgBXAQAAAA==.',
Ri='Riiver:BAAANQAECgQIBAAAAA==.',
Ro='Roderick:BAAANQAECgIIAgAAAA==.Root:BAABNQAECn8yAAIRAAoKriZwAAD9AwARAAoKriZwAAD9AwAAAA==.',
Ru='Rubmytotem:BAAANQAECgYICwAAAA==.',
Sa='Sabazia:BAABNQAECn8rAAIbAAgKHxPfSADUAQAbAAgKHxPfSADUAQAAAA==.Sabelinå:BAAANQAECgIIAwAAAA==.Sable:BAAANQADCgEIAQAAAA==.Sacred:BAABNQAECn8VAAMSAAcKexUdGgDyAAASAAYK5hUdGgDyAAAOAAIKzBOdlQCBAAAAAA==.Saerise:BAAANQAECgIIAgAAAA==.Sairalindë:BAAANQAECgcIDgAAAA==.Salamandra:BAAANQADCggIGQABNQAECgoKMQAgAHAaAA==.Saleath:BAAANQAECgIIAgAAAA==.Salios:BAAANQAECgEIAQAAAA==.Sanara:BAAANQABCgUIBwABNQAECgcIHwAQAEoMAA==.Sanctifier:BAAANQADCgUIBQAAAA==.',
Sc='Scrept:BAAANQAECggICgAAAA==.Scynix:BAEBNQAECn8cAAMUAAgKvQkhJwCAAQAUAAgKvQkhJwCAAQAkAAcKRQzADQBwAQAAAA==.Scÿph:BAEANQAECgMIBQABNQAECggIHAAUAL0JAA==.',
Se='Sedaline:BAAANQAECgEIAQAAAA==.Seizuregoat:BAAANQAECgMIAwAAAA==.Senus:BAAANQADCgEIAQAAAA==.Servoker:BAAANQAECggIEQAAAA==.',
Sh='Shabzshooter:BAAANQAECgUIBgAAAA==.Shabzyt:BAABNQAECn8ZAAMBAAkKsRZdUADSAQABAAcK6hldUADSAQACAAcKVA4hTwAaAQAAAA==.Shaienne:BAAANQADCgcIDgAAAA==.Shammander:BAABNQAECn8XAAIIAAYKDwlFiwC9AAAIAAYKDwlFiwC9AAAAAA==.Shamrockshak:BAAANQAECgIIBAAAAA==.Shamron:BAAANQADCgcICgAAAA==.Shenuton:BAABNQAECn8cAAIFAAgKyAnyvAAaAQAFAAgKyAnyvAAaAQAAAA==.Shieldbash:BAABNQAECn9EAAIGAAoKASb9AADNAwAGAAoKASb9AADNAwAAAA==.Shockthêràpy:BAABNQAECn8pAAMMAAoKjSKvHgDwAgAMAAoKjSKvHgDwAgAIAAEKzw4lMgE3AAAAAA==.Shoes:BAAANQAECgYICgAAAA==.Shtdruid:BAAANQAECgEIAQAAAA==.',
Si='Sibearian:BAAANQAECgcIEQABNQAECgoKJgALAEgQAA==.Sibeson:BAABNQAECn8mAAMLAAoKSBD/CQBgAQAKAAgKyAqurgB0AQALAAcKGxL/CQBgAQAAAA==.Simi:BAABNQAECn8oAAIYAAoKBRPtTwDuAQAYAAoKBRPtTwDuAQAAAA==.',
Sm='Smithnwesson:BAAANQABCgcICgAAAA==.Smokesçreen:BAABNQAECn82AAMfAAoKjw8MDwDGAQAfAAoKjw8MDwDGAQAXAAcKKQlqTwBcAQAAAA==.',
So='Soonerpride:BAABNQAECn8gAAIFAAkKUyHKWQCKAgAFAAkKUyHKWQCKAgAAAA==.Soothed:BAAANQADCggICAAAAA==.',
Sp='Spearminttea:BAAANQADCgIIAgAAAA==.Spellbreakr:BAACNQAFFH8JAAIHAAQKcQmZPgDAAAAHAAQKcQmZPgDAAAA1AAQKfysAAgcACgpUIIAfAKgCAAcACgpUIIAfAKgCAAAA.Spirtbreaker:BAAANQAECgYIEQAAAA==.',
Sq='Squeak:BAEANQADCgUIDAABNQAECgIIAgANAAAAAA==.Squiby:BAABNQAECn9FAAMWAAoKSCPrBQB5AwAWAAoKSCPrBQB5AwAeAAQKigzYtQCSAAAAAA==.',
St='Stankowitz:BAAANQABCgQICAABNQADCgYIBgANAAAAAA==.Starboi:BAAANQADCgUIBQAAAA==.Starce:BAAANQABCgMIAwAAAA==.Steveirwin:BAAANQADCgYICgAAAA==.Stheris:BAABNQAECn8uAAIiAAoKNRgfCABAAgAiAAoKNRgfCABAAgAAAA==.Stoops:BAAANQADCggICAAAAA==.Stuefester:BAABNQAECn8UAAMbAAcKTyAFPAATAgAbAAcKIh0FPAATAgABAAcK9x1AWgCnAQAAAA==.Stäirs:BAAANQAECggIEAAAAA==.',
Sv='Sveika:BAABNQAECn8WAAIRAAYKFQW5QgCrAAARAAYKFQW5QgCrAAAAAA==.',
Sy='Sylaria:BAEANQAECgIIAgAAAA==.Syreline:BAAANQAECgQIBAAAAA==.',
['Sï']='Sïn:BAABNQAECn8gAAIKAAgKRB3EYgAxAgAKAAgKRB3EYgAxAgAAAA==.',
['Sý']='Sýlver:BAABNQAECn8hAAIOAAgKkwxcUQCXAQAOAAgKkwxcUQCXAQAAAA==.',
Ta='Tantric:BAAANQAECgMIAQABNQAECggIMQARANoUAA==.Tarathiel:BAAANQADCgIIAgAAAA==.Tarpalantir:BAAANQADCgcICAAAAA==.Taurne:BAABNQAECn8/AAMPAAoKMBugEQBnAgAPAAoKMBugEQBnAgAOAAMKiQX6lwB5AAAAAA==.',
Tc='Tchnce:BAAANQADCgcICgAAAA==.',
Te='Teknoman:BAABNQAECn84AAMDAAoK5hoPVgDGAQADAAoK5hoPVgDGAQAGAAEKWgpIPgArAAAAAA==.Telephone:BAAANQAECgEIBQAAAA==.Tempered:BAABNQAECn8iAAIDAAoKaA9glADpAQADAAoKaA9glADpAQABNQAECgoKKgATAFUTAA==.Teresen:BAAANQADCgIIAgAAAA==.',
Th='Thaitea:BAAANQADCgIIBAAAAA==.Thalindra:BAABNQAECn8fAAIYAAcKzw3AlQBCAQAYAAcKzw3AlQBCAQAAAA==.Tharain:BAAANQAECgQIBQAAAA==.Thebigbeast:BAABNQAECn8ZAAMEAAcKKR0sHQBQAQAEAAUK1hwsHQBQAQAQAAYKzx06nwBHAQABNQAFFAgIGQAKADMTAA==.Thecurt:BAABNQAECn9JAAIgAAoKWSNHAQAqAwAgAAoKWSNHAQAqAwAAAA==.Thunderrbutt:BAABNQAECn8WAAIIAAcKoAw3kgB3AQAIAAcKoAw3kgB3AQAAAA==.Thyralizen:BAAANQADCgUICAAAAA==.',
Ti='Tiael:BAAANQAECgIIAgAAAA==.Timaeus:BAAANQADCggIGgAAAA==.Tinylef:BAABNQAECn8xAAQgAAoKcBrkBwCtAQAhAAcKpxePJwDlAQAgAAcKwh3kBwCtAQAoAAYKXhE8GgAnAQAAAA==.Tirouke:BAAANQAECgUIBQAAAA==.Titanlock:BAAANQAECgEIAQAAAA==.',
Tk='Tkdfath:BAAANQADCgYIBgAAAA==.',
To='Toralina:BAAANQAECgEIAQAAAA==.Torvia:BAAANQAECgIIAgAAAA==.',
Tr='Trisinz:BAABNQAECn8dAAIOAAkKJQ3wKwBpAQAOAAkKJQ3wKwBpAQAAAA==.',
Tu='Tuerto:BAABNQAECn8oAAIYAAoKNRJ9RQAMAgAYAAoKNRJ9RQAMAgAAAA==.Tuiarmstrong:BAAANQAECgUIDwABNQAFFAUIEQAeABkcAA==.Tuipasteur:BAACNQAFFH8RAAMeAAUKGRycDgCmAQAeAAUKGRycDgCmAQAnAAMK/QMEAQCxAAA1AAQKfzQABB4ACgq2IdMRAB8DAB4ACgq2IdMRAB8DABYABQp6Cw4/AIAAACcAAgriCqkfAGQAAAAA.Tuithexiv:BAAANQAECgcIDwABNQAFFAUIEQAeABkcAA==.Turbojohnson:BAAANQAECgEIAQAAAA==.Turk:BAABNQAECn9OAAIcAAoKcBUPFADyAQAcAAoKcBUPFADyAQAAAA==.Turkish:BAABNQAECn80AAICAAoKrA7rKgDLAQACAAoKrA7rKgDLAQAAAA==.',
Tw='Twinkytoes:BAAANQADCggIEwAAAA==.',
Ty='Tychaa:BAAANQADCgYIEgAAAA==.Tylat:BAAANQABCgMIAwAAAA==.Tyranay:BAABNQAECn9DAAIeAAkK5B7DHADEAgAeAAkK5B7DHADEAgAAAA==.Tyrith:BAAANQADCgQIBQAAAA==.',
Ui='Uintah:BAABNQAECn8aAAIRAAkKpBivEADvAQARAAkKpBivEADvAQAAAA==.',
Ul='Ullyr:BAACNQAFFH8OAAIOAAUKEBDOCQAhAQAOAAUKEBDOCQAhAQA1AAQKfzUAAw4ACgrPIGoKANoCAA4ACgrPIGoKANoCABIAAQoAAJVOABkAAAAA.',
Um='Umbryss:BAAANQAECgIIAgABNQAECgoKOAAXANMlAA==.',
Us='Userdel:BAABNQAECn8dAAIMAAYKXwj+vADwAAAMAAYKXwj+vADwAAAAAA==.',
Va='Vadose:BAAANQADCgYIBgABNQAECgoKKAAYAAUTAA==.Valytrois:BAAANQAECggICQAAAA==.Variant:BAAANQAECgMIAwAAAA==.Varinix:BAAANQADCgUICAAAAA==.Vauld:BAAANQADCgQJBQAAAA==.',
Ve='Veiksla:BAAANQADCgYIGgAAAA==.Vengerr:BAAANQADCgYIFQAAAA==.Verace:BAAANQAECggICQAAAA==.Verradic:BAABNQAECn8XAAMJAAcKfgeYLQAWAQAJAAYK1AaYLQAWAQAKAAcKYwa5mgDsAAAAAA==.',
Vi='Vilanelle:BAAANQABCgUIBwAAAA==.Vitur:BAABNQAECn84AAIcAAkKxCN1AwChAwAcAAkKxCN1AwChAwAAAA==.Vivi:BAAANQADCgYIBgAAAA==.',
Vo='Voidbunny:BAAANQAECgYIDwAAAA==.Volaine:BAABNQAECn8dAAMJAAcKdwikJQBRAAAKAAUK6wdQwgCdAAAJAAIKSQmkJQBRAAAAAA==.Volgar:BAAANQADCgUIDgAAAA==.Volition:BAAANQADCgYIBgAAAA==.Volt:BAABNQAECn8mAAIVAAoK9RUpEABmAgAVAAoK9RUpEABmAgABNQAECgoKNAAKAKUMAA==.Vorarephilia:BAAANQAECgUIBQAAAA==.',
Vr='Vrye:BAABNQAECn8cAAIcAAkKQwTnSwD6AAAcAAkKQwTnSwD6AAAAAA==.',
Vy='Vynaeda:BAABNQAECn8UAAIHAAcKEhSc6gC1AQAHAAcKEhSc6gC1AQAAAA==.',
['Vô']='Vôx:BAAANQAECgIIBQABNQAECgcIDAANAAAAAA==.',
Wa='Wakko:BAAANQADCgcIEwAAAA==.Walkure:BAAANQADCgYIHAAAAA==.',
We='Weirdscience:BAAANQABCgQIBAAAAA==.Wetasstotem:BAABNQAECn8dAAMIAAoK5BzkKwDPAgAIAAoK5BzkKwDPAgAMAAYKrhXyVwCCAQABNQAFFAgIGQAKADMTAA==.',
Wh='Whew:BAAANQADCggICQAAAA==.',
Wi='Widge:BAAANQAECgQIBAAAAA==.Wikker:BAAANQADCgQIBAAAAA==.',
Wo='Worldlight:BAAANQADCgIIAgAAAA==.',
Wr='Wreckbums:BAAANQAECgMIBAAAAA==.Wreckd:BAAANQAECgcIEAABNQAECgoKKgATAFUTAA==.Wrongway:BAAANQADCgQIBwAAAA==.',
Xa='Xanthad:BAAANQADCgUICAAAAA==.',
Xb='Xb:BAAANQADCgYIFgAAAA==.',
Xi='Xitãozinho:BAAANQAECgQIBwAAAA==.',
Xy='Xyomi:BAAANQADCgQIBAAAAA==.',
Ya='Yaalia:BAABNQAECn8fAAIQAAcKSgwnbgA5AQAQAAcKSgwnbgA5AQAAAA==.Yaan:BAABNQAECn8WAAIIAAkKowqahACZAQAIAAkKowqahACZAQAAAA==.Yalane:BAAANQAECgMIAwAAAA==.',
Yo='Yogi:BAAANQAECgUIBQAAAA==.',
Za='Zain:BAAANQADCgYIBgABNQAECgoKTwAJAAAdAA==.Zalaan:BAAANQAECgcIEgABNQAECgoKJgAHAM4bAA==.Zandibar:BAABNQAECn8fAAIZAAcKQRLCEAAqAQAZAAcKQRLCEAAqAQAAAA==.Zaptoasted:BAAANQADCgYIBgAAAA==.Zariea:BAAANQAECgIIAgABNQAECggIKgABAMcVAA==.Zavac:BAAANQADCgUIBwAAAA==.',
Ze='Zellezugtail:BAAANQADCgYIBgABNQAECgkJGwAKAA0FAA==.Zelritch:BAAANQADCggICAAAAA==.',
Zi='Zinfandell:BAAANQAECgUICwAAAA==.',
Zo='Zorrloc:BAAANQADCgQIBAAAAA==.',
Zu='Zuggie:BAABNQAECn8bAAIKAAkKDQU6iwAPAQAKAAkKDQU6iwAPAQAAAA==.Zugtail:BAAANQAECgEIAQABNQAECgkJGwAKAA0FAA==.Zurtrinik:BAAANQAECgUICwABNQAFFAcIFgAgAAAZAA==.',
Zy='Zyntalla:BAABNQAECn8dAAIcAAcK0w22KQASAQAcAAcK0w22KQASAQAAAA==.',
Zz='Zzonked:BAAANQAECgEIAQAAAA==.',
['Zê']='Zêp:BAAANQADCgcIFwAAAA==.',
['Àr']='Àrròw:BAAANQADCgYICgAAAA==.',
['Ðo']='Ðoogle:BAABNQAECn8ZAAMVAAgKPQ1QGgAuAQAVAAgKPQ1QGgAuAQAMAAIKdRDjAwFhAAABNQABCgUIBQANAAAAAA==.',
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
