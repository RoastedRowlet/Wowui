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

local lookup = {'Hunter-BeastMastery','Unknown-Unknown','Paladin-Retribution','Paladin-Protection','Monk-Mistweaver','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Priest-Holy','Mage-Arcane','Mage-Frost','Evoker-Devastation','Paladin-Holy','Priest-Shadow','DemonHunter-Devourer','Druid-Restoration','Evoker-Preservation','DeathKnight-Frost','DemonHunter-Vengeance','Shaman-Elemental','Warrior-Arms','Warrior-Fury','Rogue-Subtlety','Rogue-Assassination','DeathKnight-Blood','DeathKnight-Unholy','Druid-Balance','Monk-Windwalker','Shaman-Enhancement','Warrior-Protection','Hunter-Marksmanship','Shaman-Restoration','Monk-Brewmaster','DemonHunter-Havoc','Rogue-Outlaw','Druid-Feral','Priest-Discipline','Mage-Fire','Hunter-Survival',}
local provider = {region='US',realm='Malygos',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Absofsteels:BAAANQAECgYIEgAAAA==.',
Ac='Acaric:BAAANQAECgYIEwAAAA==.',
Ad='Adøra:BAACNQAFFH8FAAIBAAIKiga1KQCNAAABAAIKiga1KQCNAAA1AAQKfzkAAgEACQooHBklAAEDAAEACQooHBklAAEDAAAA.',
Ag='Agumon:BAAANQAECgUIDQAAAA==.',
Al='Alchemist:BAAANQADCgIIBAAAAA==.Alistair:BAAANQADCgUIBQAAAA==.Alluriel:BAAANQAECgIIBAAAAA==.Alonas:BAAANQAECgYICAABNQAECggIEwACAAAAAA==.Altharoth:BAABNQAECn8rAAMDAAkK9xo0WwCCAgADAAkK9xo0WwCCAgAEAAEKzAxmcAAuAAAAAA==.',
Am='Amique:BAAANQABCgIIAgAAAA==.Amira:BAAANQADCgYIDwABNQAFFAUICgAFAMkZAA==.Amormage:BAAANQAECgQICAAAAA==.Amphitrite:BAAANQADCgUIBQAAAA==.',
An='Anabolicrage:BAAANQADCgYIBwAAAA==.Anteiku:BAAANQAECgIIBAAAAA==.Anteikudeath:BAAANQADCgEIAQAAAA==.',
Ap='Applemoose:BAABNQAECn8eAAQGAAgK3xvOcQAHAgAGAAYKjB3OcQAHAgAHAAIKhBiRUACMAAAIAAEK8BX/KABGAAAAAA==.',
Ar='Aragrar:BAAANQAECgIIAgAAAA==.Arauial:BAABNQAECn8cAAIJAAcKFiHRMwCVAgAJAAcKFiHRMwCVAgAAAA==.Arcanis:BAABNQAECn8oAAMKAAgKlBYVpwAyAgAKAAgKTRYVpwAyAgALAAIKBxddLwCBAAAAAA==.Aribella:BAABNQAECn8bAAIBAAkKoBF5XwBWAgABAAkKoBF5XwBWAgAAAA==.Arizae:BAAANQAECgQIBQAAAA==.Arizann:BAAANQAECgYIDgAAAA==.Arobotev:BAABNQAECn8lAAIMAAgK5BEIFQD5AQAMAAgK5BEIFQD5AQAAAA==.',
As='Astaren:BAAANQADCgcIEAAAAA==.Asuran:BAAANQAECggICgAAAA==.',
At='Atiya:BAABNQAECn8dAAINAAkK0hKqTQAxAgANAAkK0hKqTQAxAgAAAA==.',
Az='Azaris:BAABNQAECn8dAAMOAAkKDxSwIgAbAgAOAAgKBRawIgAbAgAJAAEKownZ8gBBAAAAAA==.',
Ba='Babykraze:BAABNQAECn8bAAIBAAcK1w2HnwDDAQABAAcK1w2HnwDDAQAAAA==.Baelrog:BAAANQAECgYIDQAAAA==.Baiene:BAAANQAECgYICAAAAA==.Baiken:BAAANQAECgEIAQAAAA==.Baldheadelf:BAAANQADCgQIBAAAAA==.Bandalar:BAABNQAECn8lAAIPAAgKYxf5IgAvAgAPAAgKYxf5IgAvAgAAAA==.Banerino:BAAANQADCgIIAgAAAA==.Barnabust:BAAANQAECgUIBgAAAA==.Bashems:BAAANQAECgEJAQAAAA==.Baston:BAAANQADCgIIAgAAAA==.Bastrd:BAAANQAECgMIAwAAAA==.',
Be='Bearypie:BAAANQAECggICAAAAA==.Beastums:BAABNQAECn8nAAIBAAgKORXzXABcAgABAAgKORXzXABcAgAAAA==.',
Bi='Bigbôotyjudy:BAAANQADCgIIAgAAAA==.Bigchungus:BAAANQADCggICQAAAA==.Bingbong:BAAANQADCgEIAQAAAA==.',
Bl='Blacken:BAAANQADCgQIBgAAAA==.Bleak:BAAANQADCgQIBAAAAA==.Blindmonk:BAAANQAECggIAwAAAA==.Blite:BAAANQADCgUICQAAAA==.Bloodmary:BAAANQAECgYIEgAAAA==.Bloodor:BAAANQADCggICQAAAA==.Bloöm:BAABNQAECn8yAAIQAAkK8SIbBQBvAwAQAAkK8SIbBQBvAwAAAA==.',
Bm='Bmaazi:BAABNQAECn8eAAMRAAcKTRe0HgDlAQARAAcKTRe0HgDlAQAMAAUKYgT2KwDAAAAAAA==.',
Bo='Bonerina:BAAANQAECgQICQAAAA==.Boomadk:BAACNQAFFH8FAAISAAMKTA58EADPAAASAAMKTA58EADPAAA1AAQKfy8AAhIACQpqIiIKAEgDABIACQpqIiIKAEgDAAAA.',
Br='Bradburn:BAAANQADCgYIDAAAAA==.Bradkink:BAAANQAECgEIAQAAAA==.Brasserz:BAAANQAECgUIEQAAAA==.Breezybone:BAABNQAECn8jAAILAAkK4xkQBAD0AgALAAkK4xkQBAD0AgAAAA==.Briaela:BAAANQADCgIIAgAAAA==.Brice:BAAANQADCgYICgAAAA==.Briochebun:BAABNQAECn8cAAIDAAkKRxULdwA7AgADAAkKRxULdwA7AgAAAA==.',
Bw='Bwangifer:BAABNQAECn8mAAITAAgKVhiCCQBLAgATAAgKVhiCCQBLAgAAAA==.',
['Bë']='Bëcky:BAABNQAECn8jAAMDAAkKWyU2IQA9AwADAAkKWyU2IQA9AwANAAYKYxKpkABpAQAAAA==.',
Ca='Caloren:BAABNQAECn8aAAIBAAkK0iAKDQB1AwABAAkK0iAKDQB1AwABNQAECgkJIwAPAIQZAA==.Camerarius:BAAANQAECgEIAQAAAA==.Cannala:BAAANQADCgUICQAAAA==.Cargae:BAAANQADCgUICQAAAA==.Caso:BAAANQADCgMIBAABNQAECgUICwACAAAAAA==.',
Ce='Cellysia:BAABNQAECn8gAAMJAAcKmgS0pQAfAQAJAAcKmgS0pQAfAQAOAAIKFgMzdAA7AAAAAA==.Ceramyth:BAAANQADCgcIGQAAAA==.Ceres:BAABNQAECn8nAAIHAAgKbBQ+CgBSAgAHAAgKbBQ+CgBSAgAAAA==.Cesara:BAABNQAECn8yAAIOAAkKMhvAEQDfAgAOAAkKMhvAEQDfAgAAAA==.',
Ch='Chal:BAABNQAECn8dAAIDAAcKxAmd6ABEAQADAAcKxAmd6ABEAQAAAA==.Chaplin:BAAANQAECgMIBAABNQAECgcIGQAUAPMNAA==.Chasterra:BAAANQADCgEIAQABNQAECgkJIgAQACAYAA==.Chbribs:BAAANQAECgUIBwAAAA==.Chestypanda:BAAANQADCgQIBAAAAA==.Chiptewth:BAAANQABCgYICQAAAA==.Chiron:BAAANQADCgEIAQAAAA==.',
Co='Coldsteel:BAAANQADCggIIwAAAA==.Columbina:BAABNQAECn8dAAIPAAgKVBQxKAD/AQAPAAgKVBQxKAD/AQAAAA==.Cooperhowerd:BAAANQADCgUIBwAAAA==.Corky:BAAANQADCgEIAQABNQAECgYIDgACAAAAAA==.Corn:BAAANQADCgIIAgABNQAECgUICQACAAAAAA==.',
Cp='Cptredbeardd:BAAANQADCgYIDgAAAA==.',
Cr='Crackmonger:BAACNQAFFH8FAAIVAAIKLxX5KwCWAAAVAAIKLxX5KwCWAAA1AAQKfyMAAhUACQquGupXAIACABUACQquGupXAIACAAAA.Crackundead:BAABNQAECn8tAAISAAkK0Bk7IQB/AgASAAkK0Bk7IQB/AgAAAA==.Crapdragon:BAAANQAECgQIBgAAAA==.',
Cy='Cyphr:BAABNQAECn8nAAIQAAgK4hrtFwB8AgAQAAgK4hrtFwB8AgAAAA==.Cyrinx:BAAANQAECgYIDQAAAA==.',
Da='Daen:BAAANQADCggICAAAAA==.Dagravytrain:BAAANQAECgUJBgAAAA==.Dain:BAAANQADCgYIBgAAAA==.Dalend:BAAANQAECgcIDwAAAA==.Damerot:BAABNQAECn8dAAIWAAkKQhFRCwAMAgAWAAkKQhFRCwAMAgAAAA==.Dangerous:BAAANQAECgQICQAAAA==.Danpal:BAAANQADCggICQAAAA==.Dansharo:BAAANQADCgMIAwAAAA==.Darc:BAAANQAECgQIBAAAAA==.Darnnix:BAAANQAECgUICwAAAA==.Darthrevin:BAABNQAECn8cAAMXAAgKIw7kIwCmAQAXAAcK9wzkIwCmAQAYAAYKMAi8XgAzAQAAAA==.Dawnsingers:BAAANQADCggIFgAAAA==.',
De='Deadbeard:BAABNQAECn82AAQSAAkKhiXDAgC5AwASAAkKhiXDAgC5AwAZAAYKJR3TSADRAQAaAAQKASSddwA3AQAAAA==.Deathbash:BAAANQADCgEIAQAAAA==.Deathdream:BAAANQADCggIDgAAAA==.Deathrar:BAAANQADCgcICwAAAA==.Deathviix:BAAANQADCggIIgAAAA==.Debased:BAABNQAECn8fAAIaAAgKRhS8RgD5AQAaAAgKRhS8RgD5AQAAAA==.Demini:BAAANQADCgYIDQAAAA==.Demisê:BAABNQAECn8zAAIZAAkKkBYxNgAwAgAZAAkKkBYxNgAwAgAAAA==.Demonn:BAAANQAECgQIBwAAAA==.Derbygirl:BAAANQADCgYIDQAAAA==.Desperation:BAAANQAECgcIEAAAAA==.Desso:BAAANQAECgYICgAAAA==.Detraz:BAAANQABCgEIAQAAAA==.Devilskin:BAAANQADCgUICgAAAA==.',
Di='Dillinger:BAAANQAECgQIBQAAAA==.Dingodgaf:BAABNQAECn8cAAIDAAcKegZZ7QA7AQADAAcKegZZ7QA7AQAAAA==.',
Dj='Djinnjuicy:BAABNQAECn8dAAIKAAcKpQgWGgFdAQAKAAcKpQgWGgFdAQAAAA==.',
Do='Dodo:BAAANQAECgQICgAAAA==.Dorianmyth:BAABNQAECn8aAAIEAAgKRAfhNwAnAQAEAAgKRAfhNwAnAQAAAA==.',
Dr='Dragonshammy:BAAANQADCgMIAwAAAA==.Drazzi:BAAANQAECgEIAQAAAA==.Dreamclaw:BAAANQAECgYIEQAAAA==.Drippindots:BAACNQAFFH8FAAIGAAIKiR/LKAC8AAAGAAIKiR/LKAC8AAA1AAQKfy4AAwYACQp2IxkLAHIDAAYACQp2IxkLAHIDAAcAAQreCA1/AC0AAAAA.Driztette:BAAANQAECgYICgAAAA==.Drnewport:BAAANQADCggIEwAAAA==.Drokash:BAAANQAECgYIBgAAAA==.Drystine:BAAANQAECgUIEgAAAA==.',
Dy='Dyronebiggum:BAAANQADCggIDAAAAA==.',
['Dí']='Dín:BAAANQAECgUIDAAAAA==.',
Ec='Ectharienne:BAAANQABCgMIAwAAAA==.',
Ee='Eedeeweewee:BAAANQADCgUICQAAAA==.',
Eg='Eggs:BAAANQADCgEIAQAAAA==.',
Ei='Eillaura:BAABNQAECn8yAAIJAAkKSxddQQBiAgAJAAkKSxddQQBiAgAAAA==.',
El='Eleredra:BAAANQADCgYIBgABNQAECgcIHwAOAIkVAA==.Elipsis:BAABNQAECn8uAAIJAAkKAyUfBwCKAwAJAAkKAyUfBwCKAwAAAA==.Elm:BAABNQAECn8ZAAMbAAcKBBSHQAD0AQAbAAcKBBSHQAD0AQAQAAIK6gzVZgBjAAAAAA==.Elybella:BAAANQADCgMIAwABNQAECgkJHwARANkUAA==.Elycia:BAAANQAECgUIBQABNQAECgkJHwARANkUAA==.Elyenora:BAABNQAECn8fAAIRAAkK2RTaFQBWAgARAAkK2RTaFQBWAgAAAA==.',
En='Enquea:BAAANQAECgQIBQABNQAECgYIDgACAAAAAA==.Enricco:BAAANQADCggIFAAAAA==.',
Er='Eraeste:BAAANQABCgQIAwAAAA==.Ereko:BAABNQAECn8bAAIBAAcKuw0AowC8AQABAAcKuw0AowC8AQAAAA==.Eriss:BAABNQAECn8ZAAIKAAgKNRGKtgAVAgAKAAgKNRGKtgAVAgAAAA==.Erythorbic:BAAANQAECgYIEgAAAA==.',
Es='Estralage:BAAANQADCgUICwAAAA==.',
Ev='Evictor:BAAANQADCgIJAgABNQAECgcIDAACAAAAAA==.',
Fa='Fanaticism:BAAANQAECgMIAwAAAA==.Fangs:BAAANQAECgIIAgABNQAECgkJGQAHABwZAA==.Faranth:BAAANQAECgUIDgAAAA==.',
Fe='Feer:BAAANQADCgQICAAAAA==.Feldron:BAAANQAECggIEQAAAA==.',
Ff='Ffugher:BAAANQAECgUICQAAAA==.Ffugme:BAABNQAECn8eAAIEAAcKbQqDNwAqAQAEAAcKbQqDNwAqAQAAAA==.Ffugnutz:BAAANQADCgQIBAAAAA==.Ffugoff:BAAANQAECgYICwAAAA==.Ffugtard:BAABNQAECn8ZAAIBAAcK2gtsrgCjAQABAAcK2gtsrgCjAQAAAA==.Ffugyou:BAAANQADCggICwAAAA==.',
Fi='Finnian:BAABNQAECn8cAAINAAgKUgy+ewCiAQANAAgKUgy+ewCiAQAAAA==.Fio:BAAANQAECgYICQAAAA==.Firiona:BAAANQAECgUIBgABNQAECggIJAAXAA4cAA==.',
Fl='Flowers:BAABNQAECn8aAAIPAAcKrR8mIABKAgAPAAcKrR8mIABKAgAAAA==.Fläva:BAAANQADCgMIAwAAAA==.',
Fo='Foot:BAAANQADCgYICgAAAA==.Foxhound:BAABNQAECn8bAAIcAAcKAQ3lNQBhAQAcAAcKAQ3lNQBhAQAAAA==.',
Fr='Fracture:BAAANQADCggICAABNQAECgYIGQAdAAQJAA==.Fresca:BAAANQADCgEIAQAAAA==.Frostypie:BAAANQADCggIEAAAAA==.',
Fu='Furyswarm:BAAANQAECggIBgAAAA==.',
['Fö']='Föx:BAAANQADCgYIBgAAAA==.',
Ga='Gaius:BAAANQAECgQIBQAAAA==.Gawdcomplex:BAABNQAECn8bAAINAAcKYQyMigB5AQANAAcKYQyMigB5AQAAAA==.',
Ge='Gernaj:BAAANQADCgcICwAAAA==.',
Gh='Ghostfrudge:BAAANQADCggICAAAAA==.Ghostfudge:BAABNQAECn8kAAIEAAgK4h4uDgC2AgAEAAgK4h4uDgC2AgAAAA==.',
Gi='Ginny:BAAANQAECgYIDgAAAA==.Ginsan:BAAANQADCgEIAQAAAA==.Ginthalos:BAAANQADCgYIDwAAAA==.',
Go='Golaru:BAAANQABCgIIAgAAAA==.',
Gr='Gramthyr:BAAANQADCgUICQAAAA==.Grep:BAAANQADCgMIAwAAAA==.Greygor:BAAANQAECgIIBgAAAA==.Grotok:BAAANQADCggIDgABNQAECgcIGAABACMWAA==.',
Gu='Gumer:BAAANQAECgYIEgAAAA==.Gurgatron:BAAANQAECgQIBgABNQAECgkJJgAeAEcjAA==.Guulen:BAAANQADCgIIAgAAAA==.',
['Gá']='Gárd:BAAANQADCggICAAAAA==.',
Ha='Halontier:BAAANQADCgUIBwAAAA==.Halygos:BAAANQAECgMIBAAAAA==.Hariffug:BAAANQADCgcIBwAAAA==.Hasklaufien:BAAANQAECgcIEAAAAA==.',
He='Healinside:BAAANQAECgEIAQAAAA==.',
Hi='Hinderberg:BAAANQAECgEIAQAAAA==.',
Ho='Holdor:BAAANQAECgUIDQAAAA==.Horde:BAAANQADCgIIAgAAAA==.',
Hu='Huntsum:BAABNQAECn8YAAMBAAcKIxYqegAXAgABAAcKvBUqegAXAgAfAAQK0ArxVwDBAAAAAA==.',
Ia='Iahsotgievhu:BAAANQADCgYIBwAAAA==.Iamspeed:BAAANQABCgEIAQAAAA==.',
Ic='Iceblocklulz:BAAANQADCgIIAgAAAA==.Icedsoul:BAAANQAECgUIDAAAAA==.Iceflame:BAAANQADCgYIBgABNQAECgcIGwAQAP0XAA==.',
Ig='Iggey:BAABNQAECn8aAAIVAAgKXw8GlgDhAQAVAAgKXw8GlgDhAQAAAA==.',
Il='Ilandras:BAABNQAECn8cAAIPAAgKUhfTIwAmAgAPAAgKUhfTIwAmAgAAAA==.Illadus:BAAANQAECgUIDwAAAA==.Illiviix:BAAANQADCgcIHgAAAA==.',
In='Indra:BAABNQAECn8nAAIDAAgKVB/QSQC0AgADAAgKVB/QSQC0AgAAAA==.Intoxicated:BAAANQAECgIIAgAAAA==.',
Ir='Iranna:BAACNQAFFH8QAAMYAAQK8ySYCAB+AQAYAAQKQCOYCAB+AQAXAAEKASWqEABsAAA1AAQKfx0AAxgACQppJNUMABwDABgACQppJNUMABwDABcAAgp4F8JCAJsAAAAA.',
It='Itsredbelow:BAAANQAECgEIAwAAAA==.',
Iz='Izlaz:BAAANQADCggICAAAAA==.',
Ja='Jacrispy:BAAANQAECgIJAwAAAA==.Jaggedace:BAAANQAECgYIEwAAAA==.Janaki:BAABNQAECn8iAAMQAAkKIBiaFgCLAgAQAAkKIBiaFgCLAgAbAAYKiQhGbwAJAQAAAA==.',
Je='Jellyfish:BAAANQAECgUIDQAAAA==.',
Ji='Jibbtotem:BAAANQADCgYIDQABNQAECgkJHAAOANwUAA==.Jivanos:BAAANQADCgUIBQAAAA==.',
Jo='Joexotick:BAAANQABCgMIBQAAAA==.Jonnyquestt:BAABNQAECn8nAAIDAAgKXA1KswCyAQADAAgKXA1KswCyAQAAAA==.',
Ju='Junlock:BAAANQAECgYICgABNQAFFAUIDwAPAMIZAA==.Junrush:BAACNQAFFH8PAAIPAAUKwhkRCAB9AQAPAAUKwhkRCAB9AQA1AAQKfyMAAw8ACQqhHekVALECAA8ACQqhHekVALECABMAAQoAAB8vAD8AAAAA.Junshot:BAAANQAECgEIAQABNQAFFAUIDwAPAMIZAA==.',
Ka='Kalietha:BAAANQAECgYIEAAAAA==.Karaizula:BAABNQAECn8bAAMgAAgKEgvVggCAAQAgAAgKEgvVggCAAQAUAAQKTwHFAgGBAAAAAA==.Katsuko:BAABNQAECn8cAAIZAAcK6BWUUACwAQAZAAcK6BWUUACwAQAAAA==.Kattnirra:BAABNQAECn8bAAIBAAcKyAuxpwCyAQABAAcKyAuxpwCyAQAAAA==.Katze:BAABNQAECn8eAAIBAAkKpg+6YgBOAgABAAkKpg+6YgBOAgAAAA==.Kaylé:BAAANQAECgMIAwAAAA==.',
Ke='Keepper:BAAANQAECgMIBAAAAA==.Kenj:BAABNQAECn8jAAIJAAkKsCPCBgCOAwAJAAkKsCPCBgCOAwABNQAFFAUICwAQAMAXAA==.Kenjurr:BAABNQAECn8fAAMRAAkKTB+2BgA7AwARAAkKTB+2BgA7AwAMAAIKOAvnNABiAAABNQAFFAUICwAQAMAXAA==.Kenslynn:BAABNQAECn8eAAIJAAkKSxvpKADDAgAJAAkKSxvpKADDAgAAAA==.',
Ki='Kiannor:BAABNQAECn8YAAIcAAgK4QRFPgAcAQAcAAgK4QRFPgAcAQAAAA==.Killahaseo:BAABNQAECn8aAAIDAAgKzSFLSAC5AgADAAgKzSFLSAC5AgAAAA==.Killmoedee:BAABNQAECn8iAAIEAAcK3iIJEACbAgAEAAcK3iIJEACbAgAAAA==.Kishibe:BAAANQAECgUICQAAAA==.Kiss:BAAANQAECggIEwABNQAFFAcIJwAgAKIkAA==.Kitwryn:BAAANQADCgUICQAAAA==.',
Kl='Klexios:BAAANQAECgQIBQAAAA==.',
Ko='Koopa:BAAANQAECgYIEAAAAA==.',
Kr='Kraulhoof:BAAANQAECgEIAQABNQAECgIIAgACAAAAAA==.Kronohs:BAAANQAECgIIAwAAAA==.Krymson:BAAANQADCgcIBwAAAA==.',
Ku='Kui:BAABNQAECn8iAAIhAAgKIhd0DQAhAgAhAAgKIhd0DQAhAgAAAA==.Kuneia:BAAANQADCgQIBAABNQAECgkJIgAQACAYAA==.Kurakka:BAAANQADCgEIAQAAAA==.Kuyna:BAAANQADCgYIDgAAAA==.',
Ky='Kylohendrix:BAAANQAECgQIBAAAAA==.',
['Kö']='Köz:BAAANQADCgQIBAAAAA==.',
La='Laetri:BAAANQAECgQIBAAAAA==.Lailiia:BAABNQAECn8aAAIFAAcKBRIWHwCVAQAFAAcKBRIWHwCVAQAAAA==.Laindrin:BAAANQADCgYIBwAAAA==.Lavendarlace:BAAANQADCgYIDAAAAA==.Lawrence:BAAANQADCggICAAAAA==.Lazloo:BAABNQAECn8eAAIVAAgKvCOcJQAgAwAVAAgKvCOcJQAgAwAAAA==.Lazymidget:BAABNQAECn8YAAIfAAkKYgfMOACFAQAfAAkKYgfMOACFAQAAAA==.',
Le='Leftÿ:BAABNQAECn8zAAISAAkKLR6hEQD+AgASAAkKLR6hEQD+AgAAAA==.Legindkiller:BAAANQADCgUICQAAAA==.Lenie:BAAANQAECgcICgABNQAFFAYIEwAZAGghAA==.Levoyon:BAAANQAECgEIAQAAAA==.Lexibelle:BAABNQAECn8eAAIGAAcKuAs2qgB5AQAGAAcKuAs2qgB5AQAAAA==.',
Lf='Lfty:BAAANQADCgQIBAABNQAECgkJMwASAC0eAA==.',
Li='Lightace:BAABNQAECn8dAAMEAAcKmAtCPAAMAQADAAcKcwZm+QAlAQAEAAYKAwxCPAAMAQAAAA==.Lightbunny:BAAANQAECggIEQAAAA==.Lincia:BAAANQAECgQIBgAAAA==.Linkkil:BAAANQAECgUIBQAAAA==.Liv:BAAANQADCgMIAwABNQAECgcIEwACAAAAAA==.',
Lo='Loastotem:BAAANQADCgIIAgAAAA==.Lobos:BAABNQAECn8pAAIGAAgKyhBbcwADAgAGAAgKyhBbcwADAgAAAA==.Lockrah:BAAANQADCgUIBwAAAA==.Lorvinion:BAAANQADCgYIBgAAAA==.Lostdraco:BAAANQAECgYIDgAAAA==.Lostdream:BAABNQAECn8kAAMiAAgKbAiNRwCGAQAiAAgKbAiNRwCGAQATAAgKkwMtHgDaAAAAAA==.Loun:BAAANQAECgYIDgAAAA==.',
Lu='Luiss:BAAANQAECgQIEgAAAA==.Luminism:BAABNQAECn8WAAMNAAgKAxpJPgBpAgANAAgKAxpJPgBpAgADAAEKAABriAFGAAABNQAECgUICAACAAAAAA==.Luvlycruelty:BAAANQAECgYIDQAAAA==.',
Ly='Lyn:BAEBNQAECn8pAAIhAAkKIyZgAADwAwAhAAkKIyZgAADwAwAAAA==.',
['Lê']='Lêônà:BAAANQABCggICAAAAA==.',
Ma='Maazi:BAAANQADCgYIBgAAAA==.Mackenziiee:BAABNQAECn8rAAIBAAkKsBnpOQC6AgABAAkKsBnpOQC6AgAAAA==.Madglowup:BAABNQAECn8YAAIjAAcKtR51BQCTAgAjAAcKtR51BQCTAgAAAA==.Magerick:BAAANQAECgUIBgAAAA==.Magicwater:BAAANQADCggICwABNQAECgkJHwADAMgfAA==.Magtaki:BAAANQADCgEJAQAAAA==.Mainline:BAAANQAECgMIAwAAAA==.Maizepriest:BAABNQAECn8aAAIOAAYKIyE1HgBLAgAOAAYKIyE1HgBLAgAAAA==.Maliaa:BAAANQADCgUIEgAAAA==.Malloryrose:BAAANQADCgcIBwAAAA==.Mandrison:BAAANQAECgEIAQAAAA==.Masfima:BAAANQADCgIIAgAAAA==.Maxz:BAAANQADCggIHAAAAA==.',
Me='Meerkat:BAAANQAECgQIBAAAAA==.Mellowblink:BAAANQAECgUIEwABNQAECggIJAAXAA4cAA==.Mellowlink:BAABNQAECn8kAAMXAAgKDhzIDQCYAgAXAAgKDhzIDQCYAgAYAAEK0A2HoAAzAAAAAA==.',
Mi='Migglet:BAAANQAECgEIAQAAAA==.Miirya:BAAANQADCgYIAwAAAA==.Mimi:BAACNQAFFH8eAAMBAAgKayUjAgBYAgAfAAcKkCLHAgBvAgABAAYK9CUjAgBYAgA1AAQKfy0AAx8ACQq8JloGAGoDAB8ACQpOJloGAGoDAAEABwrCJqYlAP8CAAAA.Miramage:BAAANQADCgcIBwABNQAECgUIDAACAAAAAA==.Miravus:BAAANQAECgUIDAAAAA==.Misttie:BAAANQAECgcIDwABNQAECgkJLgAJAAMlAA==.Mitcheoff:BAAANQAECgQICwAAAA==.',
Mo='Moisturizer:BAAANQAECgUICQAAAA==.Monkerick:BAAANQADCgQIBwAAAA==.Mowte:BAAANQADCgUICQAAAA==.',
Mu='Murkoobi:BAAANQAECgEIAQAAAA==.Mursk:BAAANQABCgEIAQAAAA==.',
My='Mystrial:BAAANQABCgUICQAAAA==.Mystáke:BAAANQAECgcIDgAAAA==.',
['Mó']='Mómo:BAAANQADCgMIAwAAAA==.Móus:BAAANQADCgIIAgABNQAECggIGQAgABIVAA==.',
Na='Narbus:BAAANQAECgYIDwAAAA==.Narcissus:BAAANQADCgUICQAAAA==.Naromancer:BAABNQAECn8oAAIKAAcKeSFoZwCvAgAKAAcKeSFoZwCvAgAAAA==.Nathadon:BAABNQAECn8cAAIOAAkKwR8VCQBKAwAOAAkKwR8VCQBKAwAAAA==.Nautrium:BAAANQAECgMIAwAAAA==.',
Ne='Necrotis:BAAANQADCgUICQAAAA==.Nekhraros:BAABNQAECn8ZAAMHAAkKHBlUMAAGAQAGAAYK9hTonwCRAQAHAAMKox5UMAAGAQAAAA==.Neko:BAAANQAECggICAAAAA==.Nergál:BAAANQADCgYIBQABNQADCggICAACAAAAAA==.Neytfury:BAAANQADCgUIBQAAAA==.Neyti:BAAANQADCgIIAgAAAA==.Neytvengy:BAAANQADCggIDQAAAA==.Nezukô:BAAANQADCgUICQAAAA==.',
Ni='Nienna:BAAANQAECgMIBAABNQAECgYIDgACAAAAAA==.Nikkikynz:BAAANQABCgIIAgAAAA==.Nikkisan:BAAANQADCgYIGAAAAA==.Nixk:BAAANQAECgQICwAAAA==.',
No='Noapte:BAAANQADCgIIBAAAAA==.Noixi:BAAANQAECgYIDwAAAA==.Noras:BAAANQAECgcIDAAAAA==.Nordicslayer:BAAANQAECgEIAQAAAA==.Notagnoblin:BAECNQAFFH8RAAIZAAUKzCABCADcAQAZAAUKzCABCADcAQA1AAQKfykAAhkACQpVJuMCAMMDABkACQpVJuMCAMMDAAAA.Notrick:BAAANQAECgQIBwAAAA==.',
Nu='Nuffsaid:BAAANQADCgUIBgAAAA==.',
Ny='Nyko:BAAANQADCgUIBgAAAA==.',
Oa='Oaklyn:BAAANQADCgUIBQAAAA==.',
Ob='Obsidious:BAAANQAECgUICQAAAA==.',
Og='Ogrelurd:BAABNQAECn8pAAIVAAkK4RgnPgDOAgAVAAkK4RgnPgDOAgAAAA==.',
Op='Opalfox:BAAANQADCgEIAQAAAA==.Ophelia:BAABNQAECn8qAAQIAAkKIBxECwC2AQAGAAYKHxs4ggDcAQAIAAUKXhtECwC2AQAHAAIK6xIfVACBAAAAAA==.',
Or='Orakwa:BAAANQAECgcIEQAAAA==.',
Pa='Pachez:BAAANQAECgIIAgAAAA==.Paladont:BAAANQAECgUICwAAAA==.Pallinda:BAABNQAECn8dAAMNAAcKIBgGWgAIAgANAAcKIBgGWgAIAgADAAYKoQ6y5wBFAQAAAA==.Palmogant:BAAANQAECgYIEQAAAA==.Panztide:BAAANQADCgcIBwABNQAECggIGwAkAH8NAA==.Pappyoblues:BAAANQAECgEIAgAAAA==.Patt:BAAANQADCgUIBQAAAA==.',
Pe='Pendulumlaw:BAACNQAFFH8MAAIVAAUKbwhsGQBGAQAVAAUKbwhsGQBGAQA1AAQKfyYAAhUACQpUGBRmAFoCABUACQpUGBRmAFoCAAAA.Pennypacker:BAAANQAECgMIAwABNQAECgYIDgACAAAAAA==.Pepe:BAAANQADCgEIAQAAAA==.',
Ph='Phinn:BAABNQAECn8eAAIbAAcKnAdLZwArAQAbAAcKnAdLZwArAQAAAA==.Phoel:BAAANQADCgUIBwAAAA==.Phoopanchu:BAAANQAECgYICwAAAA==.',
Pi='Pimikoh:BAAANQAECgQIBAAAAA==.Pinkbuns:BAAANQAECgYIDgAAAA==.',
Pn='Pneuma:BAAANQAECgUICAAAAA==.',
Po='Pollonius:BAAANQADCgQIBAAAAA==.Poncho:BAAANQADCgIIAgAAAA==.Popsy:BAAANQAECgUIBQAAAA==.',
Pr='Prenton:BAABNQAECn8fAAIVAAcKxxwwbQBHAgAVAAcKxxwwbQBHAgAAAA==.Prepotente:BAAANQAECgMIBAABNQAECggIJAAXAA4cAA==.Prideflag:BAAANQADCggICAAAAA==.Priestin:BAAANQAECgEIAQAAAA==.Profundity:BAAANQAECgEIAQABNQAECgYIDgACAAAAAA==.',
Ps='Psyduck:BAAANQAFFAQIBAABNQAFFAgIHgADALIfAA==.',
Pu='Punie:BAABNQAECn8dAAIUAAcKKRcyVQAhAgAUAAcKKRcyVQAhAgAAAA==.Puzzykat:BAAANQADCgYIBgAAAA==.',
Qe='Qeini:BAABNQAECn8bAAIlAAcKAgweDgBMAQAlAAcKAgweDgBMAQAAAA==.',
Ra='Radrin:BAAANQADCgcIDQAAAA==.Rafoff:BAAANQAECgEIAQAAAA==.Ragnarax:BAAANQAECggIEwAAAA==.Rahll:BAAANQADCgIIAgAAAA==.Raikami:BAAANQAECgIIAgAAAA==.Rancoramble:BAAANQAECgQICgAAAA==.Randis:BAABNQAECn8fAAIaAAcKfQ1+agBlAQAaAAcKfQ1+agBlAQAAAA==.Raysonna:BAAANQAECgUIDAAAAA==.',
Re='Rengår:BAAANQAECgMIBAAAAA==.Reticent:BAAANQAECgUIBgAAAA==.Reversewally:BAAANQAECgcIEAAAAA==.Rexiis:BAAANQAECgYIDwAAAA==.Reyth:BAAANQAECgQICQAAAA==.',
Rh='Rhuby:BAABNQAECn8cAAIZAAcK+haPTgC4AQAZAAcK+haPTgC4AQAAAA==.',
Ri='Rimos:BAAANQAECgMIBAAAAA==.Riptîde:BAAANQADCggIEwAAAA==.Rivening:BAAANQAECgQIBgAAAA==.',
Rk='Rk:BAAANQADCgYICAAAAA==.',
Ro='Rochelle:BAAANQADCggIIQAAAA==.Roeyth:BAAANQADCggICAAAAA==.Rokki:BAABNQAECn8tAAIKAAgKnwiW6gCyAQAKAAgKnwiW6gCyAQAAAA==.Roostor:BAAANQADCggIEQAAAA==.Rosael:BAAANQADCgQJBAAAAA==.Roundhouse:BAABNQAECn8bAAIhAAcKMhzBDQAaAgAhAAcKMhzBDQAaAgAAAA==.',
Ru='Rubbmytotems:BAAANQAECgUICgAAAA==.Rubicôn:BAAANQABCgYICAABNQAFFAYIEwAKAEAcAA==.Rubmyoysters:BAAANQADCgEIAQAAAA==.Ruleti:BAABNQAECn8lAAIBAAkKsBkjPgCuAgABAAkKsBkjPgCuAgAAAA==.Rumí:BAAANQADCggJIgAAAA==.Russell:BAAANQADCgUICQAAAA==.',
Sa='Sabado:BAAANQAECgMIAwAAAA==.Safewerd:BAEANQAECgYIDQAAAA==.Saitama:BAAANQAECgYICQABNQAECgkJKAAVABIVAA==.Sangriel:BAABNQAECn8cAAIZAAcKUA/bZgBUAQAZAAcKUA/bZgBUAQAAAA==.Saraceleste:BAAANQADCggIFAAAAA==.Sarahfi:BAAANQAECgIJAgABNQAECgQIBwACAAAAAA==.Saralanna:BAABNQAECn8iAAIGAAgK2g1XhQDUAQAGAAgK2g1XhQDUAQAAAA==.Sarasophie:BAAANQADCgcIGAAAAA==.Sarefina:BAAANQAECgQIBQAAAA==.Sathenazarke:BAAANQAFFAMIAwABNQAFFAQIEAAYAPMkAA==.',
Sc='Schism:BAAANQADCgcIFgAAAA==.Schmingus:BAAANQADCgIIAgAAAA==.Scoban:BAABNQAFFH8JAAINAAUKcReiCgCuAQANAAUKcReiCgCuAQAAAA==.',
Se='Seaworld:BAAANQAECgYICAABNQAECggIJAAXAA4cAA==.Seraphnite:BAAANQADCgIIAgAAAA==.Seriousjakk:BAAANQADCgEIAQABNQADCgQIBwACAAAAAA==.',
Sh='Shadeebear:BAAANQADCgEIAQAAAA==.Shadowtax:BAAANQADCgYIBgAAAA==.Shan:BAAANQAECgcIEwAAAA==.Shaohlin:BAAANQADCggIDgAAAA==.Shaqfu:BAAANQADCgUICQAAAA==.Shavemybush:BAAANQADCgcJBwAAAA==.Shayy:BAABNQAECn8oAAIlAAkKWRjfAwCeAgAlAAkKWRjfAwCeAgAAAA==.Sheve:BAAANQAECgQIBAABNQAECgYIGgAgAJweAA==.Shigure:BAABNQAECn8eAAMLAAkK/gpOFgBKAQAKAAkKuwh70ADjAQALAAcKOQpOFgBKAQAAAA==.Sholin:BAAANQAECgYIDwAAAA==.Shomea:BAAANQAECgQIBQAAAA==.Shugz:BAAANQADCgUICAAAAA==.Shumai:BAAANQAECgUIBwAAAA==.',
Si='Sikotick:BAAANQAECgUIEgAAAA==.Sikxrapture:BAAANQADCgYIBgAAAA==.Siliconista:BAACNQAFFH8FAAIKAAIKEBxJQACrAAAKAAIKEBxJQACrAAA1AAQKfzkAAwoACQrOI9MUAIADAAoACQrAItMUAIADAAsABwrgJHYLAAUCAAAA.',
Sk='Skitrit:BAAANQADCgYIEAABNQAECgkJJQABALAZAA==.Skyjin:BAAANQADCgYJCQAAAA==.',
Sl='Slammurai:BAAANQADCgcICwAAAA==.Slippie:BAAANQADCgQIBAAAAA==.Slippinwater:BAABNQAECn8fAAIDAAkKyB/1HABNAwADAAkKyB/1HABNAwAAAA==.Sllew:BAABNQAECn8sAAIaAAkKax0XGQD1AgAaAAkKax0XGQD1AgAAAA==.Slyyce:BAAANQAECgcIDgAAAA==.',
Sm='Smoulder:BAAANQADCgIIBAAAAA==.',
Sn='Snigles:BAAANQAECgYIEQAAAA==.Snowlily:BAAANQAECgIIAgABNQAECgcIHwAOAIkVAA==.Snurp:BAAANQAECgUIDAABNQAECgkJHgAfALogAA==.',
So='Softnsquishy:BAAANQAECgEIAgAAAA==.Solmarrow:BAABNQAECn8YAAQLAAcKmgj2FwA4AQALAAcKRgj2FwA4AQAKAAQKaARTgAG9AAAmAAEKFAacDQA0AAAAAA==.',
Sp='Spanksbar:BAAANQADCggIFAAAAA==.Spartos:BAABNQAECn8bAAIVAAYKXxfSqgCtAQAVAAYKXxfSqgCtAQAAAA==.Speedy:BAAANQAECgUIEgAAAA==.Speedyspeed:BAAANQADCgQIBQAAAA==.Spokes:BAAANQADCgYICQABNQAECggIAwACAAAAAA==.Sposi:BAEBNQAECn8ZAAIZAAgKZCHKGgDWAgAZAAgKZCHKGgDWAgAAAA==.Sprinkle:BAAANQAECggJCQABNQAECggIEQACAAAAAA==.',
Sr='Srimrithyu:BAAANQADCgYIEwAAAA==.',
Ss='Sselionn:BAAANQAECgUICQAAAA==.',
St='Stomps:BAABNQAECn8cAAIeAAcKhRneDwAnAgAeAAcKhRneDwAnAgAAAA==.Stonezef:BAABNQAECn8YAAIKAAcKkwyM9gCcAQAKAAcKkwyM9gCcAQAAAA==.',
Su='Suffocation:BAAANQADCgYIBwAAAA==.Sumbtch:BAAANQAECgUIBgAAAA==.Sungdihhwoo:BAAANQADCgQIBwAAAA==.Susann:BAABNQAECn8ZAAIgAAgKEhVCaADQAQAgAAgKEhVCaADQAQAAAA==.',
Sy='Syravia:BAAANQAECgUIEQAAAA==.',
['Sò']='Sòlushan:BAAANQAECgEIAQABNQAECgkJHgADABQaAA==.',
Ta='Tahoa:BAAANQABCgQIBwAAAA==.Tameka:BAABNQAECn8sAAIBAAkKnxvNNADKAgABAAkKnxvNNADKAgAAAA==.Tardis:BAAANQAECgcIBwABNQAECggIHAAJAKAaAA==.Tatersdh:BAEANQAECgQIBgABNQAFFAUIEQAZAMwgAA==.Tavinrayn:BAAANQAECgUICwAAAA==.',
Te='Tekesh:BAAANQAECgYIDQAAAA==.Teksham:BAAANQADCgYIEgAAAA==.Telarin:BAABNQAECn8cAAInAAcKdxOvBwDtAQAnAAcKdxOvBwDtAQAAAA==.Tezrian:BAAANQADCgYJCgABNQAECggIJAAXAA4cAA==.',
Th='Thebigdawg:BAAANQADCggICQAAAA==.Theladyboy:BAABNQAECn8YAAMTAAgKpxQkDgDVAQATAAgKpxQkDgDVAQAiAAMKtgoheACRAAAAAA==.Thomss:BAABNQAECn8hAAIBAAgKrRMjagA8AgABAAgKrRMjagA8AgAAAA==.Thraiene:BAAANQAECgUIDwABNQAECgYICAACAAAAAA==.Throhk:BAAANQADCgcIFQAAAA==.Thrumgar:BAAANQAECgEIAgAAAA==.',
Ti='Tigerliley:BAAANQAECgQIBAABNQAECgcIHwAOAIkVAA==.Tinneas:BAAANQAECgEIAQAAAA==.',
To='Tomás:BAABNQAECn8ZAAIUAAcK8w2aigCGAQAUAAcK8w2aigCGAQAAAA==.Topg:BAAANQADCgYICAAAAA==.Torstai:BAAANQAECgUIDQAAAA==.Totemic:BAAANQADCggIEgAAAA==.Toyun:BAAANQADCgMIAwAAAA==.',
Tr='Trap:BAAANQADCgQIBAAAAA==.Trueshöt:BAABNQAECn8bAAMfAAcKahdsMADGAQAfAAcKUhNsMADGAQAnAAYK7xCLCQCYAQAAAA==.',
Ts='Tserendolgor:BAAANQAECgYICQABNQAECggIJAAXAA4cAA==.',
Tu='Tukker:BAAANQADCgYIBgABNQAECgkJJgAeAEcjAA==.',
Ty='Tyedindis:BAAANQADCgEIAQAAAA==.Tyresious:BAAANQAECgYIEwAAAA==.',
Ut='Utherrex:BAAANQAECgEIAQABNQAECgYIDwACAAAAAA==.',
Va='Vahaghn:BAABNQAECn8tAAIVAAkKbSOLEgBxAwAVAAkKbSOLEgBxAwAAAA==.Valcerus:BAAANQAECgQIBQAAAA==.Valedus:BAABNQAECn8lAAIDAAgKSiIGOADtAgADAAgKSiIGOADtAgAAAA==.',
Ve='Veelete:BAAANQADCgcICwABNQAECggILAANADAjAA==.Vengeancedh:BAAANQAECgQIBgAAAA==.Veroya:BAAANQAECgEIAQAAAA==.Vespra:BAAANQADCgYIBgAAAA==.Veylara:BAAANQADCgIIAgAAAA==.',
Vi='Viix:BAAANQADCgIIAgAAAA==.Vinno:BAAANQAECgEIAQAAAA==.Virr:BAAANQAECgQIBwAAAA==.',
Vo='Volcker:BAABNQAECn8fAAIEAAcKdQjkOAAhAQAEAAcKdQjkOAAhAQAAAA==.Volthreal:BAAANQADCggICAABNQAECgkJJgAeAEcjAA==.Voltuk:BAABNQAECn8mAAMeAAkKRyM2AwBtAwAeAAgK9SU2AwBtAwAWAAIKNBNrJQB/AAAAAA==.',
Wa='Walrustusk:BAAANQAECgcIBwAAAA==.Wariius:BAAANQAECgIIAgAAAA==.Warwarb:BAAANQAECgUIBgABNQAECggIKgAGAH0XAA==.Wasabijack:BAAANQADCgcJCgAAAA==.Waterliliy:BAABNQAECn8fAAQOAAcKiRUxKADkAQAOAAcKiRUxKADkAQAlAAIKPQs8IABdAAAJAAIKhAGz8wA/AAAAAA==.Wayhn:BAAANQADCgYIBgAAAA==.',
Wh='Whathehay:BAAANQADCgQIBAAAAA==.',
Wi='Windfurypie:BAAANQADCggICQAAAA==.',
Wo='Wolfbish:BAAANQAECgUICAAAAA==.',
['Wý']='Wýler:BAAANQADCgMIAgABNQADCggICAACAAAAAA==.',
Xa='Xacious:BAAANQAECgUICwAAAA==.',
Xh='Xhuri:BAAANQADCgYIBgAAAA==.',
['Xë']='Xëna:BAABNQAECn8bAAMQAAcK/RdCJwDjAQAQAAcK/RdCJwDjAQAbAAIKSwSppQBJAAAAAA==.',
Yo='Yorllik:BAAANQAECgUICQAAAA==.',
Yt='Yt:BAAANQAECgQIBgAAAA==.',
Yu='Yueguanghua:BAAANQADCgUIBQAAAA==.Yuzuha:BAAANQADCgIIAgAAAA==.',
Ze='Zendragon:BAABNQAECn8cAAMEAAgKCSAkDgC2AgAEAAcKuCMkDgC2AgADAAYK2wkL/gAdAQABNQAECgkJJgAeAEcjAA==.',
Zh='Zhorvan:BAAANQADCggIGQABNQAECggIGgAEAEQHAA==.',
Zi='Zilstar:BAAANQAECgUIBQAAAA==.',
Zu='Zuggondeez:BAAANQADCgMIAwABNQAECgcIGAABACMWAA==.Zuggsalot:BAAANQADCgcIBwAAAA==.',
['Âr']='Ârtëmïs:BAAANQAECgYIEgAAAA==.',
['Åp']='Åpollo:BAACNQAFFH8KAAIFAAUKyRn3AwCkAQAFAAUKyRn3AwCkAQA1AAQKfxcAAgUACQqCGp8QAHECAAUACQqCGp8QAHECAAAA.',
['Òm']='Òmgitsbwòng:BAABNQAECn8bAAIfAAgKGgosNACoAQAfAAgKGgosNACoAQAAAA==.',
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
