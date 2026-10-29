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

local lookup = {'DeathKnight-Unholy','DeathKnight-Frost','Warrior-Arms','Paladin-Protection','Paladin-Retribution','Warrior-Protection','Mage-Arcane','Shaman-Restoration','Unknown-Unknown','Druid-Balance','Druid-Restoration','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Druid-Guardian','Druid-Feral','Rogue-Subtlety','Evoker-Preservation','Shaman-Enhancement','Priest-Shadow','DemonHunter-Havoc','Shaman-Elemental','Hunter-BeastMastery','Paladin-Holy','Warrior-Fury','Mage-Frost','DeathKnight-Blood','DemonHunter-Devourer','Hunter-Marksmanship','Priest-Holy','DemonHunter-Vengeance','Monk-Brewmaster','Monk-Windwalker','Rogue-Assassination','Evoker-Devastation','Evoker-Augmentation','Rogue-Outlaw','Priest-Discipline','Monk-Mistweaver',}
local provider = {region='US',realm='Perenolde',name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aanien:BAAANQADCgYICAAAAA==.',
Ac='Acedk:BAABNQAECn8hAAMBAAkKoiEyGgDvAgABAAkKPCAyGgDvAgACAAUKdiAWRACyAQAAAA==.Aceslam:BAABNQAECn8YAAIDAAgKuiFKMwDzAgADAAgKuiFKMwDzAgABNQAECgkJIQABAKIhAA==.',
Ad='Adrador:BAABNQAECn8wAAMEAAoKPByjCQADAwAEAAkKBB+jCQADAwAFAAUKzA4LIQHoAAAAAA==.Adrenaline:BAACNQAFFH8QAAIGAAUKxB5jAQAGAQAGAAUKxB5jAQAGAQA1AAQKf0AAAgYACgq8JHoCAI4DAAYACgq8JHoCAI4DAAAA.',
Ae='Aelik:BAABNQAECn8oAAIBAAgKEBXLaABuAQABAAgKEBXLaABuAQAAAA==.Aeolian:BAAANQADCgYIDgAAAA==.Aeru:BAAANQADCgQIBAAAAA==.',
Af='Afk:BAAANQAECgMIAwAAAA==.',
Aj='Ajaila:BAAANQADCgQIBAAAAA==.',
Ak='Akueria:BAAANQADCgcIBwAAAA==.',
Al='Alayssa:BAABNQAECn8dAAIHAAoKrRV4NAAgAgAHAAoKrRV4NAAgAgAAAA==.Alda:BAAANQADCgYIFgAAAA==.Alemental:BAAANQAECggIDwAAAA==.Aleska:BAAANQAECgQIEAAAAA==.Allarius:BAAANQAECgQIBAAAAA==.Allevist:BAAANQADCgUICQABNQAECgYIIQAHANMHAA==.Alo:BAABNQAECn85AAIIAAoKvxbGPgBlAgAIAAoKvxbGPgBlAgABNQAECgEJAQAJAAAAAA==.',
Am='Amilee:BAAANQAECgEIAQAAAA==.Amoondai:BAAANQADCgYICAAAAA==.Amoondrin:BAABNQAECn8eAAMKAAkKTAjhVwB2AQAKAAgK5wfhVwB2AQALAAEK3wPDewAnAAAAAA==.',
An='Analiya:BAAANQADCgQJBQAAAA==.Anatyr:BAAANQAECgEIAQAAAA==.Andoria:BAAANQABCggIDAAAAA==.',
Ar='Aramathis:BAAANQAECgUIBQAAAA==.Araviin:BAAANQAECgUICAAAAA==.Arbor:BAAANQAECgQIBwAAAA==.Arcillias:BAAANQAECgcIEAABNQAECgYIDAAJAAAAAA==.Arilas:BAAANQAECgQICAABNQAECgYIDAAJAAAAAA==.Arkanist:BAABNQAECn8hAAIHAAYK0wcUvwDKAAAHAAYK0wcUvwDKAAAAAA==.Arthia:BAAANQADCgYICQAAAA==.Arvidpally:BAABNQAECn8VAAIFAAcKiwdYugDmAAAFAAcKiwdYugDmAAAAAA==.',
As='Ashesius:BAABNQAECn9FAAQMAAoKAB2GBADhAgAMAAoKAB2GBADhAgANAAMKYQmcHgGHAAAOAAIKaxyHHgCHAAAAAA==.Ashmehameha:BAAANQAECgMIBAABNQAECgcIFgAOAPgMAA==.',
At='Atredes:BAAANQAECgYIDQAAAA==.',
Au='Auspex:BAABNQAECn8mAAIPAAgKtwgWJwDVAAAPAAgKtwgWJwDVAAAAAA==.',
Av='Avaryn:BAABNQAECn8aAAILAAkKiBbVHwAtAgALAAkKiBbVHwAtAgAAAA==.',
Ax='Aximlii:BAAANQADCgUICQAAAA==.',
Ba='Babavoss:BAAANQAECggIEAAAAA==.Babs:BAAANQADCgcIDAAAAA==.Badaracka:BAACNQAFFH8LAAIQAAYKPw0wAQCoAQAQAAYKPw0wAQCoAQA1AAQKfzsAAxAACgrNInEBACQDABAACgrNInEBACQDAA8ABwoEHDETAIIBAAAA.Badash:BAAANQAECgQICQABNQAECgcIFgAOAPgMAA==.Bahamuth:BAABNQAECn83AAIFAAoKhhYZQQD3AQAFAAoKhhYZQQD3AQAAAA==.Bahamutsrage:BAAANQADCggIDgABNQAECgYIDgAJAAAAAA==.Balder:BAAANQAECggIGQABNQAFFAQIEAAJAAAAAQ==.Bandage:BAAANQAECgYIBgABNQAECgkJIwARANkSAA==.Barbattos:BAACNQAFFH8QAAISAAUKDRjnBgBHAQASAAUKDRjnBgBHAQA1AAQKfzcAAhIACgroIxUGAEgDABIACgroIxUGAEgDAAAA.Batmon:BAAANQAECgUIBQAAAA==.',
Bd='Bdyrk:BAABNQAECn8VAAITAAgKTAqpEQBrAQATAAgKTAqpEQBrAQABNQAFFAYICwAQAD8NAA==.',
Be='Bealzeboss:BAAANQADCgcICQAAAA==.Bexley:BAABNQAECn8zAAIEAAoKFhxdBwBmAgAEAAoKFhxdBwBmAgAAAA==.',
Bi='Biggerbunny:BAABNQAECn8bAAIUAAkKNhLqJQD/AQAUAAkKNhLqJQD/AQAAAA==.Biglarry:BAAANQADCgMJBQAAAA==.Biianca:BAAANQADCgUICQAAAA==.',
Bl='Blacklok:BAAANQAECgIIBAABNQAECgoKNwAVANMlAA==.Blanne:BAAANQABCgIIAgAAAA==.Blargle:BAAANQAECgUICAAAAA==.Blegh:BAACNQAFFH8HAAIFAAMKARnHFQABAQAFAAMKARnHFQABAQA1AAQKfyQAAgUACgoNILwvAAoDAAUACgoNILwvAAoDAAAA.Blessyaheart:BAAANQAECgUIDwABNQAECgcIFgAWAKAMAA==.Blincyto:BAAANQAECgEIAQAAAA==.Blinx:BAAANQAECgEIAgAAAA==.Bloodrake:BAABNQAECn85AAIXAAoKGhgoQwChAgAXAAoKGhgoQwChAgAAAA==.Blueray:BAAANQADCgYIBgAAAA==.',
Bm='Bman:BAABNQAECn8bAAIDAAcKVRoKSgCoAQADAAcKVRoKSgCoAQAAAA==.',
Br='Braneour:BAABNQAECn8vAAMEAAoKERJzJwCjAQAEAAoKERJzJwCjAQAYAAYK1QcEswAYAQAAAA==.Bravisimo:BAAANQAECgIIAgAAAA==.Browel:BAABNQAECn8fAAINAAoKwxZkTgBpAgANAAoKwxZkTgBpAgAAAA==.',
Bu='Bubblfett:BAAANQAECgcICAAAAA==.Bumm:BAAANQAECgMIAwAAAA==.',
Bz='Bzspy:BAABNQAECn8vAAMDAAoKxBmUOwDjAQADAAoKxBmUOwDjAQAZAAIK9ApMKwBZAAAAAA==.',
['Bë']='Bëar:BAAANQAECgEIAQAAAA==.',
Ca='Cabooselul:BAAANQAECgQIBAAAAA==.Calyptus:BAABNQAECn8sAAMMAAkKsg41AwCbAQAMAAkKsg41AwCbAQANAAIK1Ai6zABeAAAAAA==.Capylaura:BAAANQAECgMIBgAAAA==.Caratine:BAAANQADCgcIDQAAAA==.Cassandrah:BAABNQAECn85AAIHAAoKyx7IJgBaAgAHAAoKyx7IJgBaAgAAAA==.',
Ce='Celìa:BAAANQAECggIEAAAAA==.',
Ch='Chillymage:BAAANQADCgcIBwAAAA==.Chpchop:BAAANQABCggIEQAAAA==.Christy:BAAANQADCgYIGwAAAA==.Chugg:BAABNQAECn8kAAIIAAcKtwY1cwDkAAAIAAcKtwY1cwDkAAAAAA==.',
Ci='Ciaphus:BAABNQAECn82AAQYAAoKOQqMOgCwAQAYAAoKOQqMOgCwAQAFAAgK6A+btwCvAQAEAAcKNgxENgA1AQAAAA==.Cinnamonster:BAAANQAECgQIDAAAAA==.',
Cl='Clogs:BAAANQAECgUIBgAAAA==.',
Co='Coffeedemon:BAAANQAECgQIBgAAAA==.Coldslappins:BAAANQAECgMIAwABNQAECgoKLwAEABESAA==.Convalescent:BAAANQADCgYIBgAAAA==.Coragrr:BAAANQAECgIIAwAAAA==.',
Cr='Cracklepants:BAACNQAFFH8KAAIWAAUKaAlMEABoAQAWAAUKaAlMEABoAQA1AAQKf0AAAhYACgqTITQXAD0DABYACgqTITQXAD0DAAAA.Crashout:BAAANQAECggIDQAAAA==.',
Cu='Curtastrophe:BAABNQAECn86AAIaAAoKlCIpAQCQAwAaAAoKlCIpAQCQAwAAAA==.Curticus:BAAANQADCgYIBgAAAA==.',
Da='Daelanos:BAABNQAECn8ZAAIDAAgKIAtbrwCmAQADAAgKIAtbrwCmAQAAAA==.Dallas:BAAANQAECggICgAAAA==.Danorman:BAAANQADCgQIBAABNQAECgIIAwAJAAAAAA==.',
De='Deathisreal:BAAANQADCgEIAgABNQAECgQIBQAJAAAAAA==.Deathoof:BAABNQAECn8iAAQBAAgK7xTFVgC2AQABAAgK7xTFVgC2AQAbAAMK/hHKlwCuAAACAAEKGgWKtAArAAAAAA==.Demonblaze:BAAANQAECgIIBgAAAA==.Demonilla:BAABNQAECn8gAAIcAAoK7BSuHQBkAgAcAAoK7BSuHQBkAgAAAA==.Destro:BAABNQAECn8qAAINAAoKUgsOfwDoAQANAAoKUgsOfwDoAQAAAA==.',
Di='Dilaudyd:BAAANQAECgEIAQAAAA==.Disbeleaf:BAAANQAECgYIEAAAAA==.Dishu:BAAANQABCgQIBAAAAA==.Dispel:BAAANQADCgYIBgAAAA==.Disputatious:BAAANQADCgQIBAAAAA==.',
Dn='Dntblink:BAAANQADCgUIBQAAAA==.',
Do='Dogaz:BAAANQADCgYIGwAAAA==.Dogsoldier:BAAANQADCgQIBAAAAA==.Donori:BAAANQAECgYIBQAAAA==.Doomphoenix:BAAANQADCggIDAAAAA==.',
Dr='Dragonias:BAABNQAECn8YAAIdAAYKzQepKQC6AAAdAAYKzQepKQC6AAAAAA==.Drinny:BAABNQAECn8nAAIeAAkKRAU/hACKAQAeAAkKRAU/hACKAQAAAA==.Dripington:BAABNQAECn8qAAMCAAoKmSGVFADoAgACAAoKmSGVFADoAgABAAEKAABp4AAzAAAAAA==.',
Ea='Earthangel:BAAANQAECgUIEgAAAA==.',
Ef='Efon:BAAANQADCgUIBQABNQAECgoKHQAHAK0VAA==.',
Ei='Eine:BAABNQAECn8vAAIXAAoK7BCUWwBiAgAXAAoK7BCUWwBiAgAAAA==.',
El='Eldergreen:BAAANQAECgYIEQAAAA==.Elfwine:BAABNQAECn8YAAIUAAYKGgbATADiAAAUAAYKGgbATADiAAAAAA==.Elindria:BAABNQAECn83AAMVAAoK0yXCBACnAwAVAAoKiyXCBACnAwAfAAUKwSTfCgAxAQAAAA==.Elminstir:BAABNQAECn8hAAIaAAkKfhX1CgAWAgAaAAkKfhX1CgAWAgAAAA==.Eluzhion:BAAANQADCgUICAAAAA==.Elysian:BAAANQAECgUICQAAAA==.',
Er='Erisa:BAAANQADCgMIAwAAAA==.Erizhal:BAAANQABCgIIAgAAAA==.Eruptyon:BAAANQAECgEIAQABNQAECgkJJwAHAFkgAA==.',
Es='Esabel:BAAANQAECgcIDgABNQAECgoKHQAHAK0VAA==.',
Ev='Eviae:BAABNQAECn8YAAIbAAYKAASrWQCIAAAbAAYKAASrWQCIAAAAAA==.Evillure:BAAANQAECgYICgAAAA==.',
Ex='Explanation:BAAANQADCgQIBAAAAA==.',
Fa='Falan:BAAANQAECgEIAQAAAA==.Farfins:BAAANQADCgYIBgAAAA==.',
Fe='Fedor:BAAANQAECggICAAAAA==.Feår:BAABNQAECn8XAAMNAAkKUAxaiADhAAANAAcKtwtaiADhAAAMAAIKGw4sWwBvAAAAAA==.',
Fi='Finley:BAAANQADCgQIBAAAAA==.Fixation:BAAANQABCgIIAwAAAA==.',
Fl='Flane:BAACNQAFFH8WAAIgAAcKABm+AQD2AQAgAAcKABm+AQD2AQA1AAQKfzEAAyAACgo3Ik8BAAUDACAACgo3Ik8BAAUDACEAAQoAAEdkAE4AAAAA.Flexdruid:BAAANQAECgUIBQAAAA==.',
Fr='Fragil:BAABNQAECn8uAAMiAAoKhx82FwDCAgAiAAoK7xs2FwDCAgARAAgKwx1oIwAHAgAAAA==.Frostmane:BAAANQAECggIDAABNQAFFAUICgAWAGgJAA==.',
Ga='Galena:BAABNQAECn8aAAILAAcKEBM0HQB5AQALAAcKEBM0HQB5AQAAAA==.Galian:BAAANQADCggIEgAAAA==.Ganonn:BAAANQAECgQICQABNQAECgcIEQAJAAAAAA==.Gargameal:BAAANQABCgEIAQAAAA==.',
Ge='Geshtal:BAABNQAECn8UAAMVAAgKFwtzLAA7AQAVAAgKFwtzLAA7AQAfAAEKAAAcNAAsAAAAAA==.',
Gi='Girion:BAABNQAECn8YAAIEAAYK0A61KgC1AAAEAAYK0A61KgC1AAAAAA==.',
Gl='Glaiven:BAECNQAFFH8MAAIVAAUK+xOMCwBnAQAVAAUK+xOMCwBnAQA1AAQKfzQAAxUACgoGIpAOADEDABUACgoGIpAOADEDABwABwoxFzoxALcBAAAA.Glyr:BAAANQAECgEJAQAAAA==.',
Gn='Gnofear:BAAANQABCggIEwABNQAECgYICwAJAAAAAA==.Gnora:BAAANQADCggIEgAAAA==.',
Go='Gorgrin:BAAANQAECgcIDwAAAA==.',
Gr='Groguu:BAAANQAECgQIBAABNQAECgkJIQABAKIhAA==.',
Ha='Harkanum:BAABNQAECn8sAAMjAAgKSAq+HACBAQAjAAgKSAq+HACBAQASAAgK6QQ1KwBSAQAAAA==.Harvester:BAAANQAECgUIDgAAAA==.',
He='Healinturds:BAAANQADCgEIAQAAAA==.Helloagain:BAABNQAECn8WAAIHAAkK3RucfgCBAgAHAAkK3RucfgCBAgAAAA==.',
Hi='Hidethetotem:BAAANQAECgYIEgAAAA==.Hikari:BAACNQAFFH8LAAIFAAUK7g1RGwDOAAAFAAUK7g1RGwDOAAA1AAQKfyoAAgUACgqfHb5TAJoCAAUACgqfHb5TAJoCAAAA.Hiown:BAAANQABCgYICAAAAA==.',
Ho='Holyrebel:BAAANQAECgQIBQAAAA==.Holyspike:BAABNQAECn8aAAMIAAcKBRL2UABTAQAIAAcKBRL2UABTAQAWAAEKAADw6AAAAAAAAA==.Homerr:BAABNQAECn8YAAIXAAcKcwvCfwAzAQAXAAcKcwvCfwAzAQAAAA==.Honiahaka:BAABNQAECn8/AAIXAAoK1g3ZPwDkAQAXAAoK1g3ZPwDkAQAAAA==.Hotsdog:BAAANQADCgIIAgAAAA==.Hottcakes:BAABNQAECn88AAIHAAoKyx4lDwCWAwAHAAoKyx4lDwCWAwABNQAFFAgIGAANADMTAA==.',
Hu='Humanoidlite:BAAANQAFFAEIAgABNQAFFAQICQADAP0JAA==.Humanoidlock:BAAANQADCgYIDAABNQAFFAQICQADAP0JAA==.Humanoidwar:BAACNQAFFH8JAAMDAAQK/QlAFADCAAADAAQK/QlAFADCAAAGAAEKoAP3CgAtAAA1AAQKfy4AAwMACgoIHi40APACAAMACgoIHi40APACAAYABQr+D50pAO4AAAAA.',
['Hà']='Hàvòc:BAAANQADCgQIBAAAAA==.',
['Hö']='Hölyçow:BAAANQADCgUIBQAAAA==.',
Ic='Icedtea:BAAANQAECgQIBAAAAA==.',
In='Inoru:BAAANQAECgYIDAAAAA==.Intgrumblyeo:BAAANQAECggICAAAAA==.',
Ip='Ipseity:BAAANQABCgMIAwAAAA==.',
Ir='Irmaline:BAABNQAECn8aAAIeAAcKHQ+RVQBcAQAeAAcKHQ+RVQBcAQAAAA==.',
It='Ithurtshuh:BAAANQAECgIIBQABNQAECgQIBQAJAAAAAA==.',
Ja='Jabbawockie:BAABNQAECn8XAAIVAAgKFwhqYwDsAAAVAAgKFwhqYwDsAAAAAA==.Jackcat:BAAANQADCgQIAwAAAA==.Jackyl:BAAANQABCgYIBgAAAA==.',
Je='Jeffee:BAABNQAECn8jAAICAAkKsxgPKQBQAgACAAkKsxgPKQBQAgAAAA==.Jennifleur:BAAANQADCgcIBwAAAA==.Jequalsjosh:BAABNQAECn8ZAAIiAAkKKhI8NQAFAgAiAAkKKhI8NQAFAgAAAA==.Jerk:BAACNQAFFH8XAAIcAAcKYB++BADxAQAcAAcKYB++BADxAQA1AAQKfzsAAhwACgqTJTgEAJIDABwACgqTJTgEAJIDAAAA.Jesper:BAABNQAECn9FAAIIAAoKKx6fEgA0AwAIAAoKKx6fEgA0AwAAAA==.Jetz:BAAANQAECgQICQAAAA==.Jetzul:BAAANQABCgQIBAAAAA==.Jezelle:BAAANQADCggICAAAAA==.',
Ji='Jilara:BAABNQAECn8ZAAIFAAYKFQi/vADiAAAFAAYKFQi/vADiAAAAAA==.Jimmyjim:BAABNQAECn8UAAIaAAcK8wiFEQD0AAAaAAcK8wiFEQD0AAAAAA==.',
Jo='Joink:BAAANQADCgYICQAAAA==.',
Jp='Jpepps:BAABNQAECn8mAAMNAAgK2A0tigDNAQANAAgK2A0tigDNAQAMAAMKcAThXgBoAAAAAA==.',
Jr='Jrose:BAAANQADCggIGQAAAA==.',
Ka='Kagozo:BAEANQAECgEIAQABNQAECgIIAgAJAAAAAA==.Kahlanrahl:BAAANQADCgIIAgAAAA==.Kaiatra:BAABNQAECn8aAAICAAcKzBdhPADcAQACAAcKzBdhPADcAQAAAA==.Kalamor:BAAANQAECgUIBQAAAA==.Kaliguala:BAAANQADCgUIBwAAAA==.Kaloran:BAAANQAECgcIDgAAAA==.Katalaystar:BAAANQADCgYIDAABNQAECgoKPAALAIQgAA==.Katalegdh:BAAANQAECgUIDAAAAA==.Kaìju:BAABNQAECn8hAAIFAAcKoyAjTQDPAQAFAAcKoyAjTQDPAQAAAA==.',
Ke='Kellytgt:BAAANQAECgcIDAAAAA==.',
Kh='Khaelyn:BAAANQADCgQIBQAAAA==.Khai:BAABNQAECn8WAAIFAAgKyA1X4ABbAQAFAAgKyA1X4ABbAQAAAA==.',
Ki='Kiae:BAAANQADCgYJBwAAAA==.Kidneyspears:BAAANQADCgYICAAAAA==.Kilaura:BAAANQADCgUIBQAAAA==.Kilmandaros:BAAANQAECgUIBgAAAA==.Kimblee:BAAANQADCgQIBAAAAA==.',
Ko='Korbix:BAAANQABCgUIBAABNQAECgYICwAJAAAAAA==.',
Kr='Kronmon:BAAANQADCgQIBAAAAA==.',
Ku='Kudria:BAABNQAECn8gAAIXAAgK/hMbigD2AQAXAAgK/hMbigD2AQAAAA==.Kunei:BAAANQABCgYICQABNQAECgIIAwAJAAAAAA==.Kurdran:BAAANQABCgQIAgAAAA==.Kuroyukihime:BAABNQAECn8tAAIaAAkKbhxNBgCfAgAaAAkKbhxNBgCfAgAAAA==.',
Ky='Kynae:BAAANQAECgQIEQAAAA==.Kyross:BAAANQABCgIIAgAAAA==.',
['Ká']='Kárma:BAAANQADCgYICwABNQAECgkJFwANAFAMAA==.',
La='Lashela:BAABNQAECn8iAAIdAAcKQgeUIgDoAAAdAAcKQgeUIgDoAAAAAA==.Laughter:BAABNQAECn8UAAIGAAcKuAXDGQDEAAAGAAcKuAXDGQDEAAAAAA==.Lavamylash:BAAANQAECgcIEQAAAA==.Laylla:BAAANQAECgQICgAAAA==.Lazulie:BAAANQAECgYICAAAAA==.',
Le='Lefnedrav:BAAANQADCgYICgABNQAECgoKLQAgAO8YAA==.Lektrik:BAAANQAECgQICAAAAA==.Lenexa:BAAANQADCgUICAAAAA==.Lexapayne:BAAANQADCgEIAQABNQAECgoKIQAXANMQAA==.Leyra:BAABNQAECn8mAAIdAAoKpxgyCgBBAgAdAAoKpxgyCgBBAgABNQAECgoKNwAVANMlAA==.',
Li='Lighthammer:BAAANQADCggIDgAAAA==.Lightmessiah:BAABNQAECn8pAAMFAAkKVRqsfgAsAgAFAAgKERmsfgAsAgAYAAcK9BJUOwCsAQAAAA==.Lightnig:BAAANQADCgUIBQAAAA==.Lilyvain:BAAANQAECgEIAQAAAA==.Lireal:BAABNQAECn8gAAMYAAoKKx7MIwDcAgAYAAkKNB3MIwDcAgAFAAEKKAx+SQExAAAAAA==.Livnod:BAAANQAECgIIAQAAAA==.',
Lo='Logdiir:BAAANQABCgEIAQAAAA==.Lonon:BAABNQAECn8XAAIWAAgKJA5tcwDHAQAWAAgKJA5tcwDHAQAAAA==.Loosescrew:BAAANQADCgQIBQAAAA==.Lorine:BAABNQAECn84AAIEAAoKAhpSCgASAgAEAAoKAhpSCgASAgAAAA==.',
Lu='Lunara:BAAANQADCgYIDAAAAA==.',
Ly='Lynnethe:BAAANQAECgYIDgAAAA==.',
Ma='Malkiel:BAAANQAECgQIDgAAAA==.Mantang:BAAANQABCgIIAgAAAA==.Mastakillah:BAAANQADCgQICAABNQAECgUIEQAJAAAAAA==.Maxamus:BAAANQAECgIIAQAAAA==.',
Me='Meeseeks:BAAANQAECgcIDQAAAA==.Merckel:BAABNQAECn80AAIcAAoK2hxREADvAgAcAAoK2hxREADvAgAAAA==.Messorom:BAAANQADCgEIAQAAAA==.',
Mi='Michello:BAABNQAECn8aAAIXAAcKVg3QeABDAQAXAAcKVg3QeABDAQAAAA==.Millia:BAABNQAECn8nAAMHAAkKWSBBWwCbAQAHAAcKOyFBWwCbAQAaAAIKJh6rKQCqAAAAAA==.Mint:BAABNQAECn8fAAIYAAkKGBW5QgBaAgAYAAkKGBW5QgBaAgAAAA==.Mintberrytea:BAAANQAECgQJBAABNQAECgkJHwAYABgVAA==.Misstress:BAABNQAECn8pAAMKAAkKjgttJgBSAQAKAAkKjgttJgBSAQAPAAEKAABzcAAdAAAAAA==.',
Mo='Moistweaver:BAAANQADCgYIBgAAAA==.Monkussy:BAAANQADCgUIBQAAAA==.Monoxide:BAAANQADCgUIBQABNQAECgcIGgATAD4MAA==.Mooncloud:BAAANQAECgEIAQAAAA==.Moonhunt:BAAANQAECgUIBAAAAA==.Morkleb:BAAANQAECgUICwAAAA==.Morrag:BAABNQAECn8iAAMNAAgKMgg+cwAUAQANAAgKMgg+cwAUAQAMAAEKAACXMAAAAAAAAA==.Morrtisha:BAAANQAECgcIDAAAAA==.',
Mu='Munchkins:BAAANQABCgcIDgAAAA==.Munden:BAAANQADCgUIBQABNQAECgQIDgAJAAAAAA==.',
My='Myxie:BAABNQAECn8nAAIIAAgKRBUdOQC3AQAIAAgKRBUdOQC3AQAAAA==.',
['Mí']='Mísfìt:BAABNQAECn86AAIIAAoKpB3BIwDXAgAIAAoKpB3BIwDXAgAAAA==.',
Na='Nakaito:BAAANQAECgcIEgABNQAECgoKMAAiAJsQAA==.Narcoleptic:BAABNQAECn89AAQSAAoKWBcwBgCPAgASAAoKWBcwBgCPAgAjAAUKzQuYJgABAQAkAAQKLxHsEQBdAAAAAA==.Nashty:BAAANQADCgIIAgAAAA==.Naturaljuice:BAAANQAECggICwABNQAFFAgIGAANADMTAA==.Naturebreakr:BAABNQAECn8aAAIKAAkKBxK+PQAKAgAKAAkKBxK+PQAKAgAAAA==.',
Ne='Nex:BAABNQAECn8yAAIHAAoKDiFEHQCIAgAHAAoKDiFEHQCIAgAAAA==.',
Ni='Niceshield:BAAANQAECgIIAgAAAA==.Nightsawdy:BAABNQAECn8eAAIXAAcKgxR4cABWAQAXAAcKgxR4cABWAQAAAA==.Niightstorm:BAABNQAECn8XAAIXAAYKpQ7MnQD0AAAXAAYKpQ7MnQD0AAAAAA==.Nilvannas:BAAANQADCggICAAAAA==.Nitefire:BAAANQADCgYIGgAAAA==.Nitélifé:BAAANQAECgUICQAAAA==.',
Of='Offspring:BAAANQABCgIIAgAAAA==.',
Om='Omora:BAABNQAECn8jAAQEAAoK2RbqCQAdAgAEAAoK2RbqCQAdAgAYAAYKWgm5rwAgAQAFAAIKmwwfcgFrAAABNQAECgoKLQAgAO8YAA==.',
Op='Opalinnas:BAABNQAECn88AAILAAoKhCBUCABAAwALAAoKhCBUCABAAwAAAA==.Optimism:BAAANQADCgIIAgAAAA==.',
Pa='Paladrone:BAAANQABCggIEQABNQADCgcICgAJAAAAAA==.Palestrina:BAAANQADCgMIAwAAAA==.Pallyandtank:BAAANQAECgEIAQAAAA==.Panzer:BAABNQAECn8qAAIPAAcK8BR5HwCiAQAPAAcK8BR5HwCiAQAAAA==.Parts:BAABNQAECn8jAAQRAAkK2RKBSgAzAQAiAAYKwg+MUAB8AQARAAYKJxaBSgAzAQAlAAMK0gpNFQCbAAAAAA==.Passionfruit:BAAANQAECgcIBwAAAA==.Paul:BAAANQAECgUICgAAAA==.',
Pe='Peachtea:BAAANQAECgYICwAAAA==.Pepecojon:BAAANQADCggIDwAAAA==.',
Pi='Pirodeath:BAAANQAECgYICAAAAA==.',
Pl='Plovdiv:BAAANQADCgcJCQAAAA==.',
Po='Poah:BAAANQAECgYIBgAAAA==.',
Pr='Pray:BAABNQAECn8/AAMeAAoKXyUUAQAcBAAeAAoKjyQUAQAcBAAmAAgKMiR5AQA5AwAAAA==.Prodarkangel:BAAANQADCgcJCQAAAA==.',
Pu='Puckllane:BAAANQAECgEIAgAAAA==.Punkin:BAAANQAECgEIAQAAAA==.',
Py='Pyre:BAABNQAECn8qAAMmAAkKjw2VCgCeAQAmAAgKWg2VCgCeAQAeAAgKmwaSXABDAQABNQAECgEJAQAJAAAAAA==.',
['Pü']='Püff:BAAANQADCgEIAQABNQAECgYIDAAJAAAAAA==.',
Qu='Quanah:BAABNQAECn8cAAIIAAgKrB4zHQBZAgAIAAgKrB4zHQBZAgAAAA==.Quivver:BAAANQADCgYIGAAAAA==.',
Ra='Rabmaxx:BAABNQAECn8cAAIVAAkKWQTuVwAqAQAVAAkKWQTuVwAqAQAAAA==.Raina:BAAANQADCgYIBgAAAA==.Rap:BAAANQAECgMIAwAAAA==.Ravenlight:BAACNQAFFH8FAAIFAAQKDwbDEQCzAAAFAAQKDwbDEQCzAAA1AAQKfyMAAgUACgqbFVJ1AEMCAAUACgqbFVJ1AEMCAAAA.Ravenwynnd:BAABNQAECn8uAAMDAAoKeB5SHQBCAwADAAoKeB5SHQBCAwAGAAYKFh23FQDMAQAAAA==.Raynman:BAABNQAECn84AAIWAAoKUhO9IgDpAQAWAAoKUhO9IgDpAQAAAA==.',
Re='Restotuition:BAAANQABCgQICAABNQAFFAUIDQAeABkcAA==.Reylariel:BAAANQADCgMIAwAAAA==.',
Rh='Rhydian:BAAANQADCgQIBAAAAA==.Rhyzer:BAABNQAECn8YAAIZAAYKdRV8EwBoAQAZAAYKdRV8EwBoAQAAAA==.',
Ri='Riiver:BAAANQADCgYIBgAAAA==.',
Ro='Roderick:BAAANQAECgEIAQAAAA==.Root:BAABNQAECn8qAAIPAAoKqSZfAACOAwAPAAoKqSZfAACOAwAAAA==.',
Ru='Rubmytotem:BAAANQAECgYICwAAAA==.',
Sa='Sabazia:BAABNQAECn8rAAIbAAgKHxPfSADUAQAbAAgKHxPfSADUAQAAAA==.Sabelinå:BAAANQAECgIIAwAAAA==.Sable:BAAANQADCgEIAQAAAA==.Sacred:BAAANQAECgcIDQAAAA==.Saerise:BAAANQAECgEIAQAAAA==.Sairalindë:BAAANQAECgYIDQAAAA==.Salamandra:BAAANQADCggIGQABNQAECgoKLQAgAO8YAA==.Saleath:BAAANQAECgIIAgAAAA==.Salios:BAAANQAECgEIAQAAAA==.Sanara:BAAANQABCgUIBwABNQAECgYIEgAJAAAAAA==.Sanctifier:BAAANQADCgUIBQAAAA==.',
Sc='Scrept:BAAANQAECggICgAAAA==.Scynix:BAEBNQAECn8cAAMSAAgKvQkhJwCAAQASAAgKvQkhJwCAAQAkAAcKRQzADQBwAQAAAA==.Scÿph:BAEANQAECgMIAwABNQAECggIHAASAL0JAA==.',
Se='Sedaline:BAAANQAECgEIAQAAAA==.Seizuregoat:BAAANQAECgMJAwAAAA==.Senus:BAAANQADCgEIAQAAAA==.Servoker:BAAANQAECgcIDgAAAA==.',
Sh='Shabzshooter:BAAANQADCgMIAgAAAA==.Shabzyt:BAABNQAECn8WAAMBAAgKrRddUADSAQABAAcK6hldUADSAQACAAYKCQ4MTADlAAAAAA==.Shaienne:BAAANQADCgcIDgAAAA==.Shammander:BAAANQAECgYIDwAAAA==.Shamrockshak:BAAANQAECgIIBAAAAA==.Shamron:BAAANQADCgcICgAAAA==.Shenuton:BAABNQAECn8YAAIFAAgKXAk9ogAQAQAFAAgKXAk9ogAQAQAAAA==.Shieldbash:BAABNQAECn9DAAIGAAoKASanAABkAwAGAAoKASanAABkAwAAAA==.Shockthêràpy:BAABNQAECn8pAAMIAAoKjSKvHgDwAgAIAAoKjSKvHgDwAgAWAAEKzw4lMgE3AAAAAA==.Shoes:BAAANQAECgYICgAAAA==.Shtdruid:BAAANQAECgEIAQAAAA==.',
Si='Sibearian:BAAANQAECgUIDgABNQAECggIIgABAO8UAA==.Sibeson:BAABNQAECn8dAAMOAAcKiBOjCgDrAAANAAcKMgqurgB0AQAOAAQKOByjCgDrAAABNQAECggIIgABAO8UAA==.Simi:BAABNQAECn8hAAIXAAoK0xAnSADGAQAXAAoK0xAnSADGAQAAAA==.',
Sm='Smithnwesson:BAAANQABCgcICwAAAA==.Smokesçreen:BAABNQAECn8vAAMfAAoKjw8MDwDGAQAfAAoKjw8MDwDGAQAVAAcKKQlqTwBcAQAAAA==.',
So='Soonerpride:BAABNQAECn8gAAIFAAkKUyGcOwAMAgAFAAkKUyGcOwAMAgAAAA==.Soothed:BAAANQADCggICAAAAA==.',
Sp='Spearminttea:BAAANQADCgIIAgAAAA==.Spellbreakr:BAACNQAFFH8JAAIHAAQKcQmZPgDAAAAHAAQKcQmZPgDAAAA1AAQKfykAAgcACgpUII8SAMgCAAcACgpUII8SAMgCAAAA.Spirtbreaker:BAAANQAECggIEAAAAA==.',
Sq='Squeak:BAEANQADCgUIDAABNQAECgEIAQAJAAAAAA==.Squiby:BAABNQAECn87AAMUAAoKNSPrBQB5AwAUAAkK6yLrBQB5AwAeAAQKigzinACSAAAAAA==.',
St='Stankowitz:BAAANQABCgQICAABNQADCgYIBgAJAAAAAA==.Starboi:BAAANQADCgUIBQAAAA==.Starce:BAAANQABCgMIAwAAAA==.Steveirwin:BAAANQADCgYICgAAAA==.Stheris:BAABNQAECn8lAAIiAAoKFRQoCAAQAgAiAAoKFRQoCAAQAgAAAA==.Stoops:BAAANQADCggICAAAAA==.Stuefester:BAABNQAECn8UAAMbAAcKTyAFPAATAgAbAAcKIh0FPAATAgABAAcK9x1AWgCnAQAAAA==.Stäirs:BAAANQAECggICAAAAA==.',
Sv='Sveika:BAABNQAECn8UAAIPAAUKRgO5QgCrAAAPAAUKRgO5QgCrAAAAAA==.',
Sy='Sylaria:BAEANQAECgEIAQAAAA==.Syreline:BAAANQAECgMIAwAAAA==.',
['Sï']='Sïn:BAABNQAECn8eAAINAAcK+B7EYgAxAgANAAcK+B7EYgAxAgAAAA==.',
['Sý']='Sýlver:BAABNQAECn8hAAIKAAgKkwxcUQCXAQAKAAgKkwxcUQCXAQAAAA==.',
Ta='Tantric:BAAANQAECgMIAQABNQAECgcIKgAPAPAUAA==.Tarathiel:BAAANQADCgIIAgAAAA==.Tarpalantir:BAAANQADCgcICAAAAA==.Taurne:BAABNQAECn83AAMLAAoKJxqcEAAdAgALAAoKJxqcEAAdAgAKAAMKiQX6lwB5AAAAAA==.',
Tc='Tchnce:BAAANQADCgcICgAAAA==.',
Te='Teknoman:BAABNQAECn8xAAMDAAoK4BmIcABCAgADAAoK4BmIcABCAgAGAAEKBwWNSgAgAAAAAA==.Telephone:BAAANQAECgEIBQAAAA==.Tempered:BAABNQAECn8cAAIDAAgKXRFglADpAQADAAgKXRFglADpAQABNQAECgkJIwARANkSAA==.Teresen:BAAANQADCgIIAgAAAA==.',
Th='Thaitea:BAAANQADCgIIBAAAAA==.Thalindra:BAABNQAECn8YAAIXAAYKCw1lngDyAAAXAAYKCw1lngDyAAAAAA==.Tharain:BAAANQAECgQIBQAAAA==.Thebigbeast:BAAANQAECgYIEQABNQAFFAgIGAANADMTAA==.Thecurt:BAABNQAECn8/AAIgAAoK5iIBAQAkAwAgAAoK5iIBAQAkAwAAAA==.Thunderrbutt:BAABNQAECn8WAAIWAAcKoAw3kgB3AQAWAAcKoAw3kgB3AQAAAA==.Thyralizen:BAAANQADCgUICAAAAA==.',
Ti='Tiael:BAAANQAECgIIAgAAAA==.Timaeus:BAAANQADCggIGgAAAA==.Tinylef:BAABNQAECn8tAAQgAAoK7xhNBwCEAQAhAAcKpxePJwDlAQAgAAcK/RpNBwCEAQAnAAYKXhGLFAAwAQAAAA==.Tirouke:BAAANQAECgQIBAAAAA==.Titanlock:BAAANQAECgEIAQAAAA==.',
Tk='Tkdfath:BAAANQADCgYIBgAAAA==.',
To='Toralina:BAAANQAECgEIAQAAAA==.Torvia:BAAANQAECgEIAQAAAA==.',
Tr='Trisinz:BAAANQAECgYIDgAAAA==.',
Tu='Tuerto:BAABNQAECn8mAAIXAAoKMxJLLwAjAgAXAAoKMxJLLwAjAgAAAA==.Tuiarmstrong:BAAANQAECgUIDwABNQAFFAUIDQAeABkcAA==.Tuipasteur:BAACNQAFFH8NAAIeAAUKGRycDgCmAQAeAAUKGRycDgCmAQA1AAQKfzIABB4ACgqwISELAC4DAB4ACgqwISELAC4DABQABQp6CyYzAIMAACYAAgriCqkfAGQAAAAA.Tuithexiv:BAAANQAECgcIDwABNQAFFAUIDQAeABkcAA==.Turbojohnson:BAAANQAECgEIAQAAAA==.Turk:BAABNQAECn9EAAIcAAoKgRTvEgC8AQAcAAoKgRTvEgC8AQAAAA==.Turkish:BAABNQAECn8qAAICAAoKKw7aIQC9AQACAAoKKw7aIQC9AQAAAA==.',
Tw='Twinkytoes:BAAANQADCggIEwAAAA==.',
Ty='Tychaa:BAAANQADCgYIEgAAAA==.Tylat:BAAANQABCgMIAwAAAA==.Tyranax:BAABNQAECn81AAIeAAkKsByQHAB7AgAeAAkKsByQHAB7AgAAAA==.Tyrith:BAAANQADCgQIBQAAAA==.',
Ui='Uintah:BAABNQAECn8UAAIPAAcKixgSFgBiAQAPAAcKixgSFgBiAQAAAA==.',
Ul='Ullyr:BAACNQAFFH8JAAIKAAQKtw4gDADXAAAKAAQKtw4gDADXAAA1AAQKfywAAwoACgrdHCEOAGgCAAoACgrdHCEOAGgCABAAAQoAAJVOABkAAAE1AAUUBQgKABYAaAkA.',
Us='Userdel:BAABNQAECn8dAAIIAAYKXwj+vADwAAAIAAYKXwj+vADwAAAAAA==.',
Va='Vadose:BAAANQADCgYIBgABNQAECgoKIQAXANMQAA==.Valytrois:BAAANQAECggICQAAAA==.Variant:BAAANQAECgMIAwAAAA==.Varinix:BAAANQADCgUICAAAAA==.Vauld:BAAANQADCgQJBQAAAA==.',
Ve='Veiksla:BAAANQADCgYIGgAAAA==.Vengerr:BAAANQADCgYIFQAAAA==.Verace:BAAANQAECggICQAAAA==.Verradic:BAAANQAECgYIDgAAAA==.',
Vi='Vilanelle:BAAANQABCgUIBwAAAA==.Vitur:BAABNQAECn84AAIcAAkKxCN1AwChAwAcAAkKxCN1AwChAwAAAA==.Vivi:BAAANQADCgYIBgAAAA==.',
Vo='Voidbunny:BAAANQAECgYJDwAAAA==.Volaine:BAABNQAECn8WAAMMAAYK3QiVHgBTAAANAAQKcQhFyABmAAAMAAIKSQmVHgBTAAAAAA==.Volgar:BAAANQADCgUIDAAAAA==.Volition:BAAANQADCgYIBgAAAA==.Volt:BAABNQAECn8kAAITAAoK9RUpEABmAgATAAoK9RUpEABmAgABNQAECgoKKgANAFILAA==.',
Vr='Vrye:BAABNQAECn8cAAIcAAkKQwTnSwD6AAAcAAkKQwTnSwD6AAAAAA==.',
Vy='Vynaeda:BAABNQAECn8UAAIHAAcKEhSc6gC1AQAHAAcKEhSc6gC1AQAAAA==.',
['Vô']='Vôx:BAAANQAECgIIBQABNQAECgcIDAAJAAAAAA==.',
Wa='Wakko:BAAANQADCgcIEwAAAA==.Walkure:BAAANQADCgYIHAAAAA==.',
We='Weirdscience:BAAANQABCgQIBAAAAA==.Wetasstotem:BAABNQAECn8XAAIWAAoK5BzkKwDPAgAWAAoK5BzkKwDPAgABNQAFFAgIGAANADMTAA==.',
Wh='Whew:BAAANQADCggICQAAAA==.',
Wi='Widge:BAAANQAECgQIBAAAAA==.Wikker:BAAANQADCgQIBAAAAA==.Wishy:BAAANQABCgQIBwAAAA==.',
Wo='Worldlight:BAAANQADCgIIAgAAAA==.',
Wr='Wreckbums:BAAANQAECgMIBAAAAA==.Wreckd:BAAANQAECggIDQABNQAECgkJIwARANkSAA==.Wrongway:BAAANQADCgQIBQAAAA==.',
Xa='Xanthad:BAAANQADCgUICAAAAA==.',
Xb='Xb:BAAANQADCgYIFgAAAA==.',
Xi='Xitãozinho:BAAANQAECgQIBwAAAA==.',
Xy='Xyomi:BAAANQADCgIIAgAAAA==.',
Ya='Yaalia:BAAANQAECgYIEgAAAA==.Yaan:BAABNQAECn8UAAIWAAkKVwqZTwAeAQAWAAkKVwqZTwAeAQAAAA==.Yalane:BAAANQAECgMIAwAAAA==.',
Za='Zain:BAAANQADCgYIBgABNQAECgoKRQAMAAAdAA==.Zalaan:BAAANQAECgcIEgABNQAECgoKHQAHAK0VAA==.Zandibar:BAABNQAECn8YAAIZAAYKRRI+FgA4AQAZAAYKRRI+FgA4AQAAAA==.Zaptoasted:BAAANQADCgYIBgAAAA==.Zariea:BAAANQAECgIIAgABNQAECggIKAABABAVAA==.Zavac:BAAANQADCgUIBwAAAA==.',
Ze='Zellezugtail:BAAANQADCgYIBgABNQAECggIGQANAMIEAA==.Zelritch:BAAANQADCggICAAAAA==.',
Zi='Zinfandell:BAAANQAECgYICwAAAA==.',
Zo='Zorrloc:BAAANQADCgQIBAAAAA==.',
Zu='Zuggie:BAABNQAECn8ZAAINAAgKwgTPggDvAAANAAgKwgTPggDvAAAAAA==.Zugtail:BAAANQAECgEIAQABNQAECggIGQANAMIEAA==.Zurtrinik:BAAANQAECgUICwABNQAFFAcIFgAgAAAZAA==.',
Zy='Zyntalla:BAABNQAECn8XAAIcAAYKVQ73KQDYAAAcAAYKVQ73KQDYAAAAAA==.',
Zz='Zzonked:BAAANQAECgEIAQAAAA==.',
['Zê']='Zêp:BAAANQADCgcIFwAAAA==.',
['Àr']='Àrròw:BAAANQADCgYICgAAAA==.',
['Ðo']='Ðoogle:BAABNQAECn8XAAMTAAcK6w19HwBnAQATAAcK6w19HwBnAQAIAAIKdRDjAwFhAAABNQABCgUIBQAJAAAAAA==.',
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
