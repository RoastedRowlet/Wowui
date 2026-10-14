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

local lookup = {'Paladin-Retribution','Unknown-Unknown','Warlock-Affliction','DeathKnight-Unholy','Shaman-Restoration','Hunter-BeastMastery','Druid-Balance','Druid-Restoration','Warlock-Demonology','Warlock-Destruction','DemonHunter-Havoc','DeathKnight-Blood','DeathKnight-Frost','Rogue-Outlaw','Rogue-Assassination','Warrior-Arms','Druid-Feral','Priest-Holy','Paladin-Holy','Mage-Frost','Hunter-Survival','Hunter-Marksmanship','Monk-Mistweaver','Monk-Windwalker','Shaman-Elemental','Priest-Discipline','Rogue-Subtlety','Shaman-Enhancement','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Mage-Arcane','Priest-Shadow','DemonHunter-Vengeance','Paladin-Protection','Warrior-Protection','DemonHunter-Devourer','Druid-Guardian','Warrior-Fury',}
local provider = {region='US',realm='BlackDragonflight',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aarkan:BAABNQAECn8WAAIBAAgKjh8hQgDLAgABAAgKjh8hQgDLAgAAAA==.',
Ac='Acaelis:BAAANQAECggIDgAAAA==.Acanialyn:BAAANQADCgYICwAAAA==.',
Ad='Adamastor:BAAANQAECgMIAwABNQAECgQIEAACAAAAAA==.Adamastora:BAAANQADCgQIBAABNQAECgQIEAACAAAAAA==.Adea:BAABNQAECn8jAAIDAAgKLhQLCAASAgADAAgKLhQLCAASAgAAAA==.',
Ae='Aeiro:BAABNQAECn8nAAIEAAgKnB8fIQDCAgAEAAgKnB8fIQDCAgAAAA==.Aetheriel:BAAANQAECgQICgAAAA==.',
Af='Afflictid:BAAANQADCgEIAQABNQAECggIHwAFADMiAA==.',
Ai='Aireez:BAAANQADCgUIBQAAAA==.Airrin:BAAANQAECgQIBgAAAA==.',
Aj='Ajoseywales:BAABNQAECn8fAAIBAAkKfyI1MQADAwABAAkKfyI1MQADAwAAAA==.',
Ak='Akatala:BAABNQAECn8bAAIGAAcKNR22hAD/AQAGAAcKNR22hAD/AQAAAA==.Akunda:BAAANQAECgIIAgAAAA==.',
Al='Alaanth:BAAANQABCggIDgAAAA==.Alamaania:BAAANQAECgYICwAAAA==.Alaterial:BAAANQADCgUIBQAAAA==.Alexz:BAAANQADCgcICAAAAA==.Aloha:BAACNQAFFH8VAAMHAAYKNBklBwAWAgAHAAYKNBklBwAWAgAIAAEKzQJ+FwA7AAA1AAQKfzMAAwcACQpUJSYEALwDAAcACQpUJSYEALwDAAgAAwrvDP1dAIkAAAAA.Aluriel:BAABNQAECn8jAAQJAAkKcBpqVgBPAgAJAAkK2BZqVgBPAgADAAIKiyCAGwCjAAAKAAEKfxaabgBBAAAAAA==.',
Am='Ambellína:BAAANQADCgcIBwAAAA==.Amenrah:BAAANQADCgQIBAAAAA==.',
An='Androse:BAABNQAECn8rAAIBAAkKeR5DMgAAAwABAAkKeR5DMgAAAwAAAA==.Annamal:BAAANQADCgYIBgAAAA==.',
Ap='Apollon:BAAANQAECgQIBAAAAA==.',
Ar='Arclîght:BAABNQAECn8iAAILAAkKiApvPADPAQALAAkKiApvPADPAQAAAA==.Argyle:BAAANQAECgYIDwAAAA==.Arianwen:BAAANQADCggICAAAAA==.Arilu:BAAANQAECgIJBAAAAA==.Arkerite:BAAANQADCggIDwAAAA==.Arnix:BAAANQAECgUICgAAAA==.Aruj:BAABNQAECn8nAAQMAAkKyxUfNQA1AgAMAAcK0hsfNQA1AgANAAkKtw6MPwDEAQAEAAEKNgiu4gAvAAAAAA==.Aruz:BAAANQAECggICAAAAA==.',
As='Ashkari:BAABNQAECn8iAAINAAgKwhweJgBgAgANAAgKwhweJgBgAgAAAA==.Asteraceae:BAAANQADCgYIBgABNQAECggIJQAGAAsWAA==.Astrea:BAAANQADCgEIAQAAAA==.',
At='Athenis:BAAANQAECgIIAgAAAA==.Atulan:BAAANQAECgYIBwAAAA==.',
Au='Auphelia:BAAANQADCgQIBQAAAA==.',
Av='Aviendho:BAAANQAECgUICQAAAA==.',
Ay='Ayhanu:BAAANQADCgEIAQABNQAECggIJQAOAGQeAA==.Ayllata:BAAANQAECgQICAAAAA==.',
Az='Azmythr:BAACNQAFFH8aAAIPAAYKLCadAQCSAgAPAAYKLCadAQCSAgA1AAQKfxwAAw8ACQr+JcYFAHMDAA8ACQr+JcYFAHMDAA4AAgqtIT8WAIIAAAAA.Azzaerial:BAAANQADCgIIAgAAAA==.Azzrael:BAAANQADCgEIAQAAAA==.',
Ba='Barek:BAABNQAECn8WAAIBAAgKPRsMSQC2AgABAAgKPRsMSQC2AgAAAA==.Bartahk:BAABNQAECn8aAAIQAAgK7BmvWwB2AgAQAAgK7BmvWwB2AgAAAA==.Barto:BAAANQADCggICAAAAA==.Baxtercham:BAAANQAECgcICQABNQAECgIIAgACAAAAAA==.Baxterpala:BAABNQAECn8VAAIBAAgK1B9mTACsAgABAAgK1B9mTACsAgABNQAECgIIAgACAAAAAA==.Baxters:BAAANQAECgYICwABNQAECgIIAgACAAAAAA==.',
Be='Belenn:BAAANQAECgQICwABNQAECgYIDQACAAAAAA==.Belquise:BAAANQADCgYIEQAAAA==.Benosh:BAAANQAECgUIBwAAAA==.Betræÿer:BAAANQAECgQIBAAAAA==.Beyondthedk:BAAANQAECgMIBAAAAA==.',
Bi='Bigangus:BAAANQADCgEIAQAAAA==.Bigkahunas:BAABNQAECn86AAIGAAkKRB5FHgAdAwAGAAkKRB5FHgAdAwAAAA==.Bigman:BAAANQADCgQIBAAAAA==.Bignut:BAAANQADCgYICwABNQAECgkJLQARAKwiAA==.Bigzacky:BAABNQAECn8ZAAISAAkKDSRqBgCRAwASAAkKDSRqBgCRAwAAAA==.Bilcaster:BAABNQAECn8iAAMJAAcKcQvRqgB3AQAJAAcKcQvRqgB3AQAKAAMKJwSgWQByAAAAAA==.Billytell:BAAANQADCggJCAABNQAECgYIBwACAAAAAA==.',
Bj='Björntorock:BAAANQADCggICAAAAA==.',
Bl='Bladlast:BAABNQAECn8kAAITAAgKbBPrXwD2AQATAAgKbBPrXwD2AQAAAA==.Blankee:BAACNQAFFH8TAAIUAAUKfSOTAADXAQAUAAUKfSOTAADXAQA1AAQKfyYAAhQACQqyJQ0BAJUDABQACQqyJQ0BAJUDAAAA.Blankey:BAAANQAECggIDQAAAA==.Blargo:BAAANQAECgUIBQAAAA==.Blinkinn:BAAANQADCgQIBAAAAA==.Bloodraven:BAAANQAECgQICAAAAA==.Bloomthetank:BAAANQADCgQIBAAAAA==.',
Bo='Bobloblawl:BAEANQADCggJCAAAAA==.Bombisevil:BAACNQAFFH8XAAQGAAYK0xO6DACBAQAGAAUKXxG6DACBAQAVAAQKeAsJAQArAQAWAAMKwBltFwDJAAA1AAQKfyQABAYACQrvItVRAHgCAAYABwpZJdVRAHgCABUABwqMHRAIANsBABYABAoBEnVMAPwAAAAA.Boomins:BAAANQAECgUICwAAAA==.Booz:BAAANQAECgYIBgABNQAECgUIBQACAAAAAA==.Booze:BAABNQAECn8fAAMXAAkK/yK+BgApAwAXAAkK/yK+BgApAwAYAAQKCSIrMwB3AQABNQAECgUIBQACAAAAAA==.Bophades:BAAANQADCgYICwAAAA==.Borbadin:BAAANQAECggIAwAAAA==.Borgîr:BAABNQAECn8tAAIZAAkKFh3OKADcAgAZAAkKFh3OKADcAgAAAA==.Bossee:BAABNQAECn8eAAISAAkKBR5fFAApAwASAAkKBR5fFAApAwABNQAFFAUIEwAUAH0jAA==.Bowfdeez:BAAANQADCggICQAAAA==.',
Br='Bracven:BAAANQADCgYICgAAAA==.Bradadin:BAAANQAECgMIBgAAAA==.Bradmage:BAAANQADCgEIAQABNQAECgMIBgACAAAAAA==.Bralex:BAAANQABCgIIAgAAAA==.Braydor:BAAANQAECgUICwAAAA==.Broggzal:BAAANQAECgQIEQAAAA==.Bruisy:BAACNQAFFH8IAAISAAQKlxtvEwBqAQASAAQKlxtvEwBqAQA1AAQKfx0AAxIACApHIlkWAB4DABIACApHIlkWAB4DABoABAqFG54OAEIBAAE1AAQKBQgFAAIAAAAA.Brusque:BAAANQAECgEIAgAAAA==.',
Bu='Bubblerus:BAAANQAECgUIBQAAAA==.Bubbleturts:BAAANQAECgQIBAAAAA==.Bullpal:BAAANQADCgUIBQAAAA==.Burmiya:BAAANQADCgcIDAAAAA==.Buzzlightwgt:BAAANQABCgIIBAAAAA==.',
Bw='Bwomdalah:BAAANQAECgQIBwAAAA==.Bwonurmomdi:BAAANQADCgYICAAAAA==.',
Ca='Caffeineboy:BAAANQABCgQIBwAAAA==.Caitastrophe:BAABNQAECn8dAAIbAAcKGRFpIQC+AQAbAAcKGRFpIQC+AQAAAA==.Calahir:BAAANQADCgUIBgAAAA==.Calyssta:BAABNQAECn8qAAMZAAkKjB9TKwDPAgAZAAgKYSBTKwDPAgAFAAcK/SAcOQB4AgAAAA==.Cantbeatcook:BAABNQAECn8bAAMMAAcK6BsERQDkAQAMAAYKTBwERQDkAQAEAAQKMRg3ewArAQAAAA==.Cantou:BAABNQAECn8dAAIRAAgKuBxYCgCTAgARAAgKuBxYCgCTAgAAAA==.Captcosmo:BAAANQAECgcIDwAAAA==.Catchdahands:BAAANQAECgcIBwABNQAFFAUICgAcAJ8YAA==.',
Ch='Chaiinzz:BAAANQADCgEIAQABNQAECgYIDQACAAAAAA==.Chaosbrand:BAAANQAECgYIDgAAAA==.Chaoticks:BAAANQADCgEJAQABNQAECgIIAwACAAAAAA==.Charízard:BAAANQAECggIBQAAAA==.Chickenfried:BAAANQAECgIIBAAAAA==.Chico:BAAANQAECgQIEAAAAA==.Chillax:BAAANQAECgEIAQAAAA==.Chills:BAAANQAECggIEQABNQAECgkJLgAXAOceAA==.Chithris:BAAANQAECgQIBAAAAA==.Chodoge:BAACNQAFFH8GAAIdAAMKBxEHCQDbAAAdAAMKBxEHCQDbAAA1AAQKfzAABB0ACQp9HuoHAPwCAB0ACQp9HuoHAPwCAB4ABQpXD+AvABsBAB8AAwqTF2gTAPYAAAAA.Chopsooey:BAAANQAECgMIBAAAAA==.Choriza:BAAANQAECgMIAwAAAA==.Chriglol:BAAANQAECggIAQAAAA==.Chrisdk:BAABNQAECn8WAAIEAAcKNx+KOwAwAgAEAAcKNx+KOwAwAgAAAA==.Chungi:BAAANQADCgYICgAAAA==.',
Ci='Ciilokkar:BAAANQAECgQIBQABNQAECggIIQAgAEoZAA==.Ciimagi:BAABNQAECn8hAAIgAAgKShmkfgCBAgAgAAgKShmkfgCBAgAAAA==.Cirno:BAABNQAECn8lAAIhAAgKcxsmGwBtAgAhAAgKcxsmGwBtAgAAAA==.',
Cl='Clamcast:BAAANQAECgcIDwAAAA==.Clawsome:BAAANQADCgUIBQAAAA==.Clíché:BAAANQAECgUICwAAAA==.',
Co='Cocodiablo:BAABNQAECn8lAAINAAkKqBwIHQCeAgANAAkKqBwIHQCeAgAAAA==.Cocoñut:BAAANQAECgMIAwAAAA==.Consecrasian:BAAANQAECgEIAQAAAA==.Constantino:BAABNQAECn8bAAIiAAcKgAnVFgA8AQAiAAcKgAnVFgA8AQAAAA==.Contagious:BAAANQADCgcIDQAAAA==.Copenfist:BAAANQAECggIEAABNQAECggIJAAZAB0jAA==.Copenshock:BAABNQAECn8kAAIZAAgKHSNuGgApAwAZAAgKHSNuGgApAwAAAA==.Coraa:BAAANQAECgYIEgAAAA==.',
Cr='Crataegus:BAAANQADCgYIBgABNQAECggIJQAMAMgbAA==.Creammachine:BAABNQAECn8dAAIGAAkKBiHTDAB3AwAGAAkKBiHTDAB3AwABNQAECgkJLQARAKwiAA==.Creepsly:BAAANQADCgMIAwAAAA==.',
Cu='Curseddemon:BAAANQAECgQIBgABNQAECgUICQACAAAAAA==.Cursedflight:BAAANQAECgUICQAAAA==.Cursedpsyko:BAAANQABCgEIAQAAAA==.',
Cw='Cwem:BAABNQAECn8XAAMBAAgKjBi1XwB2AgABAAgKjBi1XwB2AgAjAAEKWgaxgAAaAAAAAA==.',
Da='Daddee:BAEANQADCgMIAwABNQAECgkJLwAgAD0gAA==.Dagobert:BAAANQAECgQIEgAAAA==.Damien:BAAANQADCggIDgABNQAECggIJAAkAK8PAA==.Dancemagic:BAAANQADCgYIBgAAAA==.Daolin:BAAANQADCgQIBAAAAA==.Darkian:BAAANQAECgQIBAAAAA==.Dasani:BAAANQAECgcIEAABNQAECgkJGgAYAEUXAA==.Davinia:BAAANQAECgUIDgAAAA==.',
De='Dean:BAABNQAECn8dAAIlAAkKoxrXGQCIAgAlAAkKoxrXGQCIAgAAAA==.Deathsidhe:BAAANQAECggIBgAAAA==.Deithknight:BAAANQADCggICgAAAA==.Demonchainz:BAAANQAECgYIDQAAAA==.Demoncook:BAAANQAECgIIBAABNQAECgcIGwAMAOgbAA==.Demono:BAAANQAECgQIBAAAAA==.Demons:BAAANQAECgYIDAAAAA==.Denishath:BAAANQABCgEIAQAAAA==.Depression:BAACNQAFFH8NAAIeAAYKqAvgCAClAQAeAAYKqAvgCAClAQA1AAQKfx0AAh4ACArvFM4WAEkCAB4ACArvFM4WAEkCAAE1AAUUBQgLABcAzhMA.Deputymeow:BAAANQADCgcIDgAAAA==.Desalination:BAAANQADCggICQABNQAFFAYIFQAHADQZAA==.Desiusrye:BAABNQAECn8kAAMkAAgKrw/KHwBMAQAQAAgKDwuJsQCcAQAkAAYK9RDKHwBMAQAAAA==.Deusvûlt:BAAANQAECggIAQAAAA==.Deyjavaknadi:BAAANQADCgYIGQAAAA==.Deûsvûlt:BAAANQAECggJAgAAAA==.',
Di='Diela:BAAANQADCgcIBwAAAA==.Digitalis:BAAANQAECgMIAwAAAA==.Diona:BAAANQADCggIDQAAAA==.Dipndot:BAAANQAECgEIAQAAAA==.Disco:BAACNQAFFH8aAAISAAYKIx9JBgAtAgASAAYKIx9JBgAtAgA1AAQKfyMAAxIACQr7JaEJAHQDABIACQq8JaEJAHQDABoACApNHZgEAHsCAAAA.Divinesmite:BAABNQAECn8bAAMSAAcKMRaAbgDOAQASAAcKMRaAbgDOAQAhAAQKdANTWgCZAAAAAA==.',
Dk='Dkandy:BAABNQAECn8tAAINAAkKpCV+AgC/AwANAAkKpCV+AgC/AwAAAA==.Dkykin:BAACNQAFFH8JAAIHAAQKThpuFAAfAQAHAAQKThpuFAAfAQA1AAQKfycAAgcACQryIHAXAAoDAAcACQryIHAXAAoDAAAA.',
Do='Donklord:BAAANQAECgEIAQABNQAECgkJLQARAKwiAA==.Dotsrus:BAABNQAECn8hAAIJAAkKTyEsEABPAwAJAAkKTyEsEABPAwAAAA==.Downfawl:BAABNQAECn8lAAMNAAgKLhJNOADuAQANAAgKwRFNOADuAQAEAAQKlBC6lwDOAAABNQAFFAYIDwAHADAMAA==.',
Dr='Dracculus:BAAANQAECgUIDgAAAA==.Draginballz:BAAANQAECgcIEgAAAA==.Dragonuts:BAAANQADCgEIAQAAAA==.Drakthor:BAAANQAECgQIBwAAAA==.Draxus:BAAANQADCggICAAAAA==.Dreamsteam:BAAANQADCgYIBgAAAA==.Dregar:BAABNQAECn8XAAIYAAcKVxk7LQCrAQAYAAcKVxk7LQCrAQAAAA==.Dresdenn:BAAANQADCggIFQAAAA==.Drogamel:BAAANQADCgEIAQAAAA==.Drstab:BAABNQAECn8XAAMbAAcK3hZYIADIAQAbAAYK3hdYIADIAQAPAAUKgBL7VABgAQAAAA==.Drujitsu:BAAANQADCgIIAgAAAA==.Drágám:BAAANQAECgMIAwAAAA==.',
Du='Duck:BAAANQAECgQIBAAAAA==.Dundrin:BAAANQADCgUIBwAAAA==.Durf:BAAANQAECgYIEAAAAA==.Duska:BAABNQAECn8ZAAIBAAcKCAWo/AAfAQABAAcKCAWo/AAfAQAAAA==.',
Dy='Dyondra:BAABNQAECn8WAAMIAAcKJBOhNwBbAQAIAAYK5RGhNwBbAQAHAAMKZgYSmQBvAAAAAA==.Dyspare:BAAANQAECgEIAQAAAA==.',
['Dî']='Dîmmu:BAAANQADCggIEAAAAA==.',
Ea='Eamoon:BAAANQAECgQIBAAAAA==.Eatchikn:BAAANQAECgcIEwAAAA==.',
Ed='Edah:BAAANQADCggIDwAAAA==.',
Ee='Eeblez:BAAANQADCgIIAgAAAA==.Eevah:BAABNQAECn8lAAMGAAgKCxajVQBuAgAGAAgKCxajVQBuAgAWAAUKkQqQSAAUAQAAAA==.',
El='Elementsmash:BAAANQAECgMJAwAAAA==.Elepanda:BAAANQAECgUICwAAAA==.Eleventeen:BAAANQAECgYIEAAAAA==.Ellipsisfear:BAAANQADCgUIBQAAAA==.Elosai:BAAANQAECgcIEwAAAA==.',
Em='Emesis:BAAANQADCgUIBQAAAA==.',
Er='Erzsi:BAAANQADCgIIAgAAAA==.',
Es='Eseri:BAAANQAFFAEIAQAAAA==.Esreaver:BAAANQAECgQICwAAAA==.',
Fa='Failing:BAAANQADCgYIBwABNQAECgUIDwACAAAAAA==.Fangaxe:BAACNQAFFH8QAAIkAAYK1RlFAQDdAQAkAAYK1RlFAQDdAQA1AAQKfyAAAyQACQplHzsGAAIDACQACQplHzsGAAIDABAABQrlG167AIMBAAAA.Fangbane:BAAANQAFFAEIAgAAAA==.',
Fe='Felaequitas:BAABNQAECn8eAAIBAAgKFBEDrADCAQABAAgKFBEDrADCAQAAAA==.Feltaco:BAAANQADCgUJCQABNQAECgQIBAACAAAAAA==.Fentastic:BAAANQAECgEIAQAAAA==.Fentrock:BAAANQAECgYICAAAAA==.Fermmogath:BAAANQADCgQIBAABNQAECgYICwACAAAAAA==.',
Fi='Fidelius:BAAANQADCggIDQAAAA==.Fisticuffs:BAABNQAECn8hAAIXAAcKhw/1IgBmAQAXAAcKhw/1IgBmAQAAAA==.',
Fl='Flameburg:BAAANQADCgQJBAAAAA==.Floshotmoo:BAABNQAECn8hAAIIAAcKCAz+OQBLAQAIAAcKCAz+OQBLAQAAAA==.',
Fo='Forestasian:BAAANQAECgcIDgAAAA==.Foxytotem:BAAANQADCggIBQAAAA==.',
Fr='Fragii:BAABNQAECn8iAAMGAAgKORWtYwBLAgAGAAgKORWtYwBLAgAVAAEKHQmjEwAxAAAAAA==.Frierenn:BAAANQADCgYICAAAAA==.Friggi:BAAANQADCggIFAAAAA==.',
Ga='Galakrond:BAAANQAECgEJAQAAAA==.Galaxum:BAAANQADCgEIAQAAAA==.Galford:BAAANQAECgIIAgAAAA==.Galindrae:BAAANQAECgQIBAAAAA==.Garana:BAAANQAECgEIAQABNQADCgYIDAACAAAAAA==.Garzha:BAAANQADCgYIDAAAAA==.Gaypoc:BAAANQAECgUIBQAAAA==.',
Ge='Gehenna:BAAANQAECgQIBwAAAA==.Gelado:BAAANQADCgYICQAAAA==.Gershas:BAACNQAFFH8GAAIQAAMKvRXEIgDjAAAQAAMKvRXEIgDjAAA1AAQKfzMAAhAACAoxI8gjACcDABAACAoxI8gjACcDAAAA.Gezebel:BAABNQAECn8ZAAIGAAcK2RitcQArAgAGAAcK2RitcQArAgAAAA==.',
Gh='Ghiberti:BAABNQAECn8YAAMBAAcKqRF6xQCLAQABAAcK0Q16xQCLAQAjAAUK1hKxPAAJAQAAAA==.Ghostvaladra:BAAANQADCgMIAwAAAA==.Ghouldamn:BAAANQADCggIJAAAAA==.Ghðst:BAABNQAECn8cAAIUAAcKFxcwCwAMAgAUAAcKFxcwCwAMAgAAAA==.',
Gl='Glarghal:BAABNQAECn8rAAISAAkKUiBiGAATAwASAAkKUiBiGAATAwAAAA==.Glasscanon:BAAANQADCggIGAAAAA==.',
Gn='Gnomagi:BAAANQADCgMIAwABNQAECggIIQAgAEoZAA==.',
Go='Gokuu:BAAANQAECgQIBQAAAA==.Golnada:BAABNQAECn8mAAIcAAgKcRAIFQAUAgAcAAgKcRAIFQAUAgAAAA==.Goodmamita:BAAANQAECgIIAgAAAA==.Gooseymane:BAAANQAECgUIBQAAAA==.Goosily:BAAANQADCgEIAQAAAA==.',
Gr='Grapebevrage:BAABNQAECn8cAAMhAAgK0gwCLwCoAQAhAAgK0gwCLwCoAQAaAAUKFwjVFADaAAAAAA==.Greentouch:BAAANQADCgQIBAAAAA==.Grewt:BAACNQAFFH8PAAIHAAYKMAzOCwCsAQAHAAYKMAzOCwCsAQA1AAQKfyQAAgcACQoAG2ghAMACAAcACQoAG2ghAMACAAAA.Grögin:BAABNQAECn8cAAIgAAgKNRF1wQD/AQAgAAgKNRF1wQD/AQAAAA==.',
Gu='Gulunga:BAAANQAECgYICwAAAA==.',
Gw='Gwashington:BAAANQAECgUIEQAAAA==.',
Ha='Halestormdh:BAABNQAECn8pAAIlAAkKNhvRFAC9AgAlAAkKNhvRFAC9AgAAAA==.Haolin:BAAANQADCgYJBgAAAA==.Harps:BAAANQAECgQIBQAAAA==.Harvyr:BAAANQAFFAEIAQAAAA==.Hate:BAAANQAECgYICwAAAA==.Hathaw:BAAANQAECgEIAgAAAA==.Hawktoouh:BAAANQADCgEIAQAAAA==.Hayhay:BAAANQADCggIFwAAAA==.',
He='Helghast:BAAANQAECgQIBAAAAA==.Herja:BAAANQAECgcICgAAAA==.Hey:BAAANQADCgYIBgAAAA==.',
Hi='Hidebound:BAABNQAECn8cAAIOAAgKjhG8CQDnAQAOAAgKjhG8CQDnAQAAAA==.Hisouka:BAABNQAECn8aAAIgAAcKVAmxAgGGAQAgAAcKVAmxAgGGAQABNQAECgkJPQAGALQkAA==.',
Ho='Hobgoblinn:BAACNQAFFH8VAAIZAAYKlhjJBgAIAgAZAAYKlhjJBgAIAgA1AAQKfy8AAhkACQqQHyMiAP4CABkACQqQHyMiAP4CAAAA.Hodordog:BAAANQAECgYIEwAAAA==.Holybel:BAAANQADCgQIBAAAAA==.Holydiver:BAAANQADCgUIBQABNQAECgkJHQAHAO4aAA==.Holydragon:BAAANQADCgcIDQAAAA==.Honeydutchtv:BAACNQAFFH8NAAIBAAYKGR/HAwAwAgABAAYKGR/HAwAwAgA1AAQKfyYAAgEACQrIIpA2APECAAEACQrIIpA2APECAAAA.Hopezbanyruu:BAAANQAECgYICAABNQAECggIDwACAAAAAA==.Hopezblinky:BAAANQAECgcIEwABNQAECggIDwACAAAAAA==.Hopezherbz:BAAANQAECggIDwAAAA==.Hordecore:BAAANQADCgYIEQAAAA==.Horsebananas:BAAANQADCgcIBgABNQAECgYIDwACAAAAAA==.',
Hu='Hubbo:BAAANQAECgYIBwAAAA==.Hugedonut:BAABNQAECn8lAAMLAAkK6hjoJwBbAgALAAkK6hjoJwBbAgAlAAMKZAQ2WwCIAAAAAA==.Hutchand:BAAANQAECgMIAwABNQAECggIKAAVAAgdAA==.',
Hy='Hypojin:BAABNQAECn8mAAIHAAgKvRZ8OgAbAgAHAAgKvRZ8OgAbAgAAAA==.',
['Hö']='Hötpröc:BAAANQAECgQIBAAAAA==.',
Ic='Iceaged:BAABNQAECn8jAAMUAAcKQySlBQCyAgAUAAcKISSlBQCyAgAgAAYKdCIuqAAwAgAAAA==.',
Il='Illos:BAABNQAECn8lAAIOAAgKZB5IBADLAgAOAAgKZB5IBADLAgAAAA==.',
Im='Imheated:BAAANQAECggIDAAAAA==.',
In='Integra:BAABNQAECn8eAAIhAAgKyxSeIAAxAgAhAAgKyxSeIAAxAgAAAA==.Intentions:BAAANQAECgEIAQAAAA==.',
Ir='Ironkami:BAAANQADCgIIAgAAAA==.',
It='Itadori:BAABNQAECn8aAAIYAAkKRRePGwBcAgAYAAkKRRePGwBcAgAAAA==.Itashi:BAAANQADCgEIAQAAAA==.Itheron:BAAANQADCgUIBQAAAA==.',
Ja='Jacknsally:BAAANQAECgIIAgAAAA==.Javijin:BAAANQABCgEJAQAAAA==.',
Jb='Jbandzz:BAAANQADCgYICAAAAA==.Jbruner:BAAANQAECgQICQAAAA==.',
Je='Jessbae:BAABNQAECn8kAAIXAAgKVxsSEQBpAgAXAAgKVxsSEQBpAgAAAA==.Jessibelle:BAAANQAECgUICgAAAA==.Jez:BAAANQADCgYIIQAAAA==.Jezeel:BAAANQAECggIDwAAAA==.',
Ji='Jimmypage:BAABNQAECn8tAAQRAAkKrCJVAgCSAwARAAkKICJVAgCSAwAmAAUKLhHOOgDQAAAHAAIKtA3tmABwAAAAAA==.',
Jo='Jonesstorm:BAAANQADCgMIAwAAAA==.',
Ju='Juicedmoose:BAABNQAECn8kAAQNAAgKXRwMJgBgAgANAAgKPhoMJgBgAgAMAAQKByINYQBrAQAEAAMK9BgaqQCgAAAAAA==.Junundu:BAAANQAECggIDAAAAA==.',
Jv='Jvmec:BAAANQAECggIEwAAAA==.',
Ka='Kaelissa:BAAANQADCgQIBAAAAA==.Kaelisse:BAAANQADCgQIBAAAAA==.Kaelstrada:BAABNQAECn8lAAIMAAgKyBsdIwCcAgAMAAgKyBsdIwCcAgAAAA==.Kaendndeydra:BAAANQADCgQIBgAAAA==.Kaennä:BAAANQAECgQJBgAAAA==.Kailash:BAAANQAECgMIAwAAAA==.Kaldorlon:BAAANQADCgcJCAAAAA==.Kaldresden:BAAANQADCgUIBQAAAA==.Kalladin:BAAANQAECgUIBgABNQAECgYIBwACAAAAAA==.Kallivan:BAAANQAECgcIDwABNQAFFAIIBQABAPITAA==.Kandakai:BAAANQADCgIIAgAAAA==.Karmageddon:BAAANQADCgcIBwAAAA==.Karmasuture:BAAANQAECgMIAwAAAA==.Karmasuturè:BAAANQAECggIDwAAAA==.Karmasuturé:BAAANQAECgEIAQABNQAECgMIAwACAAAAAA==.Kasha:BAAANQAECgYICAAAAA==.Kattah:BAABNQAECn8YAAIiAAcKjglhFwA1AQAiAAcKjglhFwA1AQAAAA==.Kavikk:BAABNQAECn8gAAMGAAYKSB4AdAAlAgAGAAUKkiUAdAAlAgAWAAEKJAH/nwASAAAAAA==.',
Ke='Keestermon:BAAANQADCgQIBAAAAA==.Kenbo:BAAANQADCgQIBAABNQAECggIJQAOAGQeAA==.Kenima:BAAANQAECgYIBgAAAA==.Keymaster:BAAANQAECgcIEwAAAA==.',
Kh='Kharmod:BAAANQAECgQIBgABNQAECgIIAgACAAAAAA==.',
Ki='Kindrella:BAABNQAECn8WAAMaAAkKeRr6BgAOAgAaAAgKwBX6BgAOAgASAAMKCiDNpwAYAQAAAA==.Kirbe:BAABNQAECn8aAAMGAAcKACELVgBtAgAGAAcKACELVgBtAgAWAAUKhwu6TwDpAAAAAA==.',
Kn='Knoctürnal:BAACNQAFFH8MAAMNAAcKJgqaAwDqAQANAAcKJgqaAwDqAQAEAAEK2wPwIgA/AAA1AAQKfywAAw0ACQolIbITAOwCAA0ACQolIbITAOwCAAQAAwpSIB2PAOYAAAAA.',
Ko='Kookieboi:BAABNQAECn86AAMGAAkKpB9gHwAYAwAGAAkKpB9gHwAYAwAWAAIKQgSdewBPAAAAAA==.Kootiekween:BAAANQADCgcICwAAAA==.Kopaka:BAAANQADCgUIBQAAAA==.Kotetsu:BAABNQAECn8kAAMLAAkKxRfvGQDIAgALAAkKxRfvGQDIAgAlAAEKAADXcgAlAAAAAA==.Koufax:BAAANQAECgcIAwAAAA==.Kozzmo:BAAANQADCgUICAAAAA==.Kozzy:BAABNQAECn8fAAILAAgKPRnBLQAyAgALAAgKPRnBLQAyAgAAAA==.',
Kr='Krellian:BAAANQAECgIIAgAAAA==.',
Ku='Kungfubrew:BAAANQADCgcICAAAAA==.',
Ky='Kylene:BAAANQADCgMIAwAAAA==.Kylisse:BAAANQADCgcIFQAAAA==.Kyma:BAABNQAECn8ZAAMFAAcKDiDQNgCBAgAFAAcKDiDQNgCBAgAZAAEKAAC7IAFIAAAAAA==.',
['Kä']='Känakä:BAAANQADCgcIDgABNQAECggIKAAVAAgdAA==.',
La='Labris:BAAANQADCgIIAgAAAA==.Labrys:BAAANQAECgUIDQAAAA==.Laolin:BAAANQADCgYIBgAAAA==.Lasagna:BAABNQAECn8eAAImAAgKuwp7JwBVAQAmAAgKuwp7JwBVAQAAAA==.Lastina:BAAANQAECgUIDgAAAA==.Laufeyenjoy:BAAANQAECggICQAAAA==.Laysia:BAABNQAECn8jAAMXAAkKHR4ICAAOAwAXAAkKHR4ICAAOAwAYAAYKDRVtMwB1AQABNQAFFAIIBQABAPITAA==.Lazypos:BAAANQAECggIEgAAAA==.',
Le='Leecy:BAABNQAECn81AAInAAgK7RUOCwARAgAnAAgK7RUOCwARAgAAAA==.Leget:BAAANQADCggIEgAAAA==.Lelianne:BAAANQADCgUIBQAAAA==.Lewa:BAAANQAECgYIDAAAAA==.',
Li='Lillithen:BAABNQAECn8VAAMmAAgKLCX8AwBuAwAmAAgKLCX8AwBuAwARAAIK+h6GKgC4AAAAAA==.Limpytof:BAAANQADCgEIAQAAAA==.Linzalina:BAABNQAECn8VAAMjAAcKXxcCIwDGAQAjAAcKwxYCIwDGAQABAAMKABL7RwGlAAAAAA==.Litehand:BAAANQAECgUIBwABNQAECgUICgACAAAAAA==.Lixandrya:BAAANQAECgIIAwAAAA==.',
Ll='Lliana:BAAANQABCgIIBAAAAA==.',
Lo='Lockrian:BAABNQAECn8uAAMJAAkKSSXbJwDiAgAJAAcKFyXbJwDiAgAKAAIKxiWcOADdAAAAAA==.Locktober:BAAANQADCgYIBQAAAA==.Locose:BAACNQAFFH8YAAIHAAYKLByABgAmAgAHAAYKLByABgAmAgA1AAQKfyIAAgcACQpcI3wZAPoCAAcACQpcI3wZAPoCAAAA.Lolrush:BAACNQAFFH8aAAIiAAYKQgUpAgAuAQAiAAYKQgUpAgAuAQA1AAQKfyMAAyIACQpPDjEQAKsBACIACQpPDjEQAKsBAAsAAwrZCBx4AJEAAAAA.Longstrongg:BAAANQADCgUIBgAAAA==.Lostdragon:BAAANQAECgYICwAAAA==.Lovesoaked:BAAANQAECgEIAQAAAA==.Lovetea:BAABNQAECn8rAAIXAAkKXSMJBABqAwAXAAkKXSMJBABqAwAAAA==.Lovetohate:BAAANQABCgQIBQAAAA==.Loxier:BAABNQAECn8cAAQSAAgKLRFYbwDLAQASAAgKLRFYbwDLAQAaAAMKLgglHACCAAAhAAIKUwN3cABDAAAAAA==.',
Lu='Lugosh:BAAANQADCgQICgAAAA==.Lumendevout:BAAANQADCgUIBQAAAA==.Lumenshift:BAABNQAECn8nAAUIAAgK+R/4DwDWAgAIAAgK+R/4DwDWAgAHAAYKbxpISgC5AQARAAEKAADIOwBEAAAmAAEK7hUNWQBAAAAAAA==.Lunaumbra:BAAANQADCgcIBwAAAA==.',
Ly='Lyall:BAABNQAECn8hAAIHAAkKOwsQQAD3AQAHAAkKOwsQQAD3AQAAAA==.Lyrnn:BAABNQAECn8cAAMbAAgKZBrcEgBVAgAbAAgKZBrcEgBVAgAPAAMKmQ1cggCeAAAAAA==.',
['Lé']='Léx:BAAANQAECggIDAAAAA==.',
Ma='Maddman:BAAANQADCgIIAgAAAA==.Madheallz:BAAANQAECgMIBAAAAA==.Magecook:BAAANQAECgQIBgABNQAECgcIGwAMAOgbAA==.Mainmoon:BAABNQAECn8iAAIYAAkKMxm6GwBaAgAYAAkKMxm6GwBaAgAAAA==.Majinmuu:BAABNQAECn8mAAMHAAgKhxzTJQChAgAHAAgKhxzTJQChAgARAAMKPgfXMwBvAAAAAA==.Malchor:BAABNQAECn8dAAIEAAgKARYgSADzAQAEAAgKARYgSADzAQAAAA==.Manyas:BAAANQADCgUIEAAAAA==.Maolin:BAAANQADCggIEwAAAA==.Massimo:BAAANQAECgUICgAAAA==.Matilda:BAAANQADCgQIBAAAAA==.Maximoo:BAAANQAECggIAQAAAA==.Mañgos:BAAANQAECgMIAwAAAA==.',
Me='Meagle:BAAANQADCgUIBQAAAA==.Megabonk:BAAANQAECgQICQAAAA==.Megthepriest:BAABNQAECn8YAAMSAAcKZRxIUwAmAgASAAYKBSBIUwAmAgAhAAQK0g0zUQDHAAAAAA==.Menge:BAAANQAECgYIBgAAAA==.Menotorp:BAAANQADCgIIAgAAAA==.Mercifer:BAAANQAECgQIBAAAAA==.Mescareyarch:BAAANQAECggIDwAAAA==.',
Mi='Micha:BAAANQAFFAIIAgABNQAFFAMIBgAgALYKAA==.Mightduy:BAABNQAECn8dAAIYAAgK4h1eFgCYAgAYAAgK4h1eFgCYAgAAAA==.Misdirect:BAABNQAECn8WAAIGAAgKtg9eeQAZAgAGAAgKtg9eeQAZAgAAAA==.',
Mo='Moistbimbo:BAAANQABCgYIBgAAAA==.Monkheals:BAAANQAECgEIAQAAAA==.Montoia:BAAANQADCgYICQAAAA==.Mooina:BAAANQAECgQIBgABNQAECggIHwAkACgWAA==.Moontzu:BAAANQADCgcIMAAAAA==.Morik:BAAANQAECgYIEAAAAA==.Morph:BAABNQAECn8cAAMRAAgKfhlKCwB3AgARAAgKfhlKCwB3AgAmAAQKjhb8NgDoAAAAAA==.Morrwen:BAAANQADCgEIAQAAAA==.Mosha:BAAANQAECgUIDgAAAA==.',
Mu='Mufasaclawsw:BAAANQAECgQICwAAAA==.Muraina:BAAANQAECgQIBgAAAA==.Muscles:BAABNQAECn8bAAIWAAcKcBdyLwDOAQAWAAcKcBdyLwDOAQAAAA==.Muspel:BAAANQAECgYICQAAAA==.',
My='Mylittlepwny:BAAANQADCgYIBwAAAA==.Myrciless:BAAANQADCggICAAAAA==.',
['Mò']='Mòon:BAABNQAECn8uAAMXAAkK5x7JCAD+AgAXAAkK5x7JCAD+AgAYAAEKaQgHdAAiAAAAAA==.',
Na='Narcu:BAAANQADCgUIBQAAAA==.Narios:BAAANQAECgEIAgAAAA==.Nate:BAACNQAFFH8PAAMUAAUK0xr8AACRAQAUAAUK0xr8AACRAQAgAAUKsw03KQA5AQA1AAQKfyoAAyAACQq1IoxNAOYCACAACQpdIYxNAOYCABQAAwrsIU0aAB8BAAAA.Nathzu:BAAANQADCgUIBQAAAA==.',
Ne='Nephthys:BAABNQAECn83AAMWAAkKzCMpBgBsAwAWAAkKzCMpBgBsAwAVAAEKuArBEwAwAAAAAA==.Nerubus:BAABNQAECn8aAAIgAAgK4BzYjQBjAgAgAAgK4BzYjQBjAgAAAA==.Neso:BAABNQAECn8ZAAMhAAcKIB/FGgBxAgAhAAcKIB/FGgBxAgASAAIKZgnr5gBmAAAAAA==.Nexkaa:BAACNQAFFH8XAAIgAAYKmCOHCAA4AgAgAAYKmCOHCAA4AgA1AAQKfzMAAiAACQryJNUOAJgDACAACQryJNUOAJgDAAAA.',
Ni='Niissia:BAAANQADCggJCAAAAA==.Nimbus:BAACNQAFFH8IAAIZAAQKMhYNEQBVAQAZAAQKMhYNEQBVAQA1AAQKfyQAAhkACQpaI7ULAIgDABkACQpaI7ULAIgDAAE1AAUUBwgUABkANBcA.Nimi:BAEBNQAECn8nAAIkAAgKew0aGwCCAQAkAAgKew0aGwCCAQAAAA==.Nindara:BAABNQAECn8jAAIdAAkKKRNmDgB2AgAdAAkKKRNmDgB2AgAAAA==.',
No='Nokonda:BAAANQADCgMIAwAAAA==.Nonhealer:BAABNQAECn8cAAIFAAgKNRR7YQDmAQAFAAgKNRR7YQDmAQAAAA==.Norisse:BAAANQADCgYIDwAAAA==.Novå:BAAANQAECgQIBgAAAA==.',
Ob='Oballi:BAAANQADCggICAAAAA==.',
Og='Ogopogo:BAAANQADCgUIBQAAAA==.',
Ol='Olcadan:BAAANQADCgYICQAAAA==.Oliandia:BAAANQADCgcIDQABNQAECgcIGAASAGUcAA==.',
On='Onlydans:BAABNQAECn8nAAILAAgK+AvXQgCmAQALAAgK+AvXQgCmAQAAAA==.Onlypain:BAAANQADCgcIBwAAAA==.Onlysins:BAAANQAECgQICAAAAA==.Onlyslams:BAAANQAECgQIBQABNQAECgQICQACAAAAAA==.',
Oo='Oofish:BAAANQADCgEIAQAAAA==.',
Or='Orcslug:BAAANQADCgQIAgAAAA==.Ordani:BAAANQADCgEIAQABNQAFFAIIBQABAPITAA==.Orm:BAABNQAECn8nAAIIAAgKQBMpKADaAQAIAAgKQBMpKADaAQAAAA==.',
Ou='Ouilyjambon:BAAANQAECgIIAwABNQAFFAYIDAAKAHkRAA==.',
Ov='Overlooker:BAAANQAECgUICgAAAA==.Overlordzor:BAAANQADCgQIBQAAAA==.',
Pa='Palanth:BAAANQAECgQIBwAAAA==.Pannfried:BAAANQADCgEIAQAAAA==.Panorama:BAABNQAECn8iAAMXAAcKlw5rIwBgAQAXAAcKlw5rIwBgAQAYAAIKlgfVYgBNAAAAAA==.Pastor:BAAANQAECgMIAgABNQAFFAMIBgAgALYKAA==.Patrik:BAABNQAECn8iAAIlAAgKYiSdCQA8AwAlAAgKYiSdCQA8AwAAAA==.',
Pe='Pearlzinha:BAAANQAECgMICgAAAA==.Peonanoob:BAAANQADCgYIBgAAAA==.',
Ph='Phemto:BAAANQADCgEIAQAAAA==.Phrost:BAAANQABCgMIAwAAAA==.Phuga:BAAANQAECgcIEwAAAA==.',
Pi='Piskolet:BAAANQADCgIIAgABNQAECgcIHgAMAM8SAA==.',
Po='Poets:BAABNQAECn8aAAIBAAkK+Bz8OQDmAgABAAkK+Bz8OQDmAgAAAA==.Pollysocket:BAAANQAECgcICwABNQAECgkJLQARAKwiAA==.Ponix:BAAANQAECgQIBAAAAA==.Pookenstein:BAAANQADCgMIAwABNQAECggIJAAXAFcbAA==.Pookthyr:BAAANQADCgQIBAABNQAECggIJAAXAFcbAA==.',
Pr='Preservasian:BAAANQADCgcIDQAAAA==.Prettyfrosty:BAABNQAECn8cAAMUAAcKRiX8AwD3AgAUAAcKRiX8AwD3AgAgAAQKOSGgDwFvAQAAAA==.',
Ps='Psykolight:BAAANQADCgMIAwAAAA==.',
Pu='Puffsummons:BAABNQAECn8kAAMJAAgKPBHuiwDEAQAJAAcK+RDuiwDEAQAKAAIK0xHTVwB3AAAAAA==.Purify:BAABNQAECn8lAAISAAgKCQ9McwC+AQASAAgKCQ9McwC+AQAAAA==.Puxxyslayer:BAAANQAECgYICAAAAA==.',
Pv='Pve:BAAANQADCgIIAgAAAA==.',
Py='Pyrannor:BAAANQAECgUICwAAAA==.Pyx:BAAANQADCggICAAAAA==.',
Qu='Quinifer:BAACNQAFFH8HAAMNAAMK4Qy5EADLAAANAAMKkAm5EADLAAAEAAIKmg7AGACRAAA1AAQKfy0AAwQACQo2Hz0pAJECAAQACQo2Hz0pAJECAA0AAwraGkFsAOQAAAAA.Quintera:BAAANQAECgMIAwAAAA==.',
Ra='Raau:BAAANQAECgQIBAABNQAECgkJKAAHAHYNAA==.Radamantys:BAABNQAECn89AAIGAAkKtCR6AgDeAwAGAAkKtCR6AgDeAwAAAA==.Ragnaroc:BAAANQAECgIIAgAAAA==.Randysavagge:BAAANQAECggIEwABNQAECgkJOgAGAKQfAA==.Ravensword:BAAANQAECgEIAQAAAA==.Razdurin:BAAANQAECgUIDAAAAA==.Razenseth:BAACNQAFFH8HAAIeAAMKUxNnEADfAAAeAAMKUxNnEADfAAA1AAQKfy4AAh4ACQofHe4MANYCAB4ACQofHe4MANYCAAAA.',
Re='Regenerate:BAABNQAECn8cAAIFAAkKIBFcUQAdAgAFAAkKIBFcUQAdAgAAAA==.Relanne:BAAANQAECgYIDQAAAA==.Restorasian:BAAANQAECgYIEAAAAA==.Retnewb:BAABNQAECn8cAAIjAAcK5R1GFgBJAgAjAAcK5R1GFgBJAgAAAA==.Retpetition:BAAANQADCgIIAgAAAA==.Revecca:BAAANQADCgQIBAAAAA==.',
Rh='Rhaskos:BAAANQADCgEIAQABNQAECgYIIAAGAEgeAA==.Rhiannah:BAAANQADCgEIAQAAAA==.',
Ri='Rikez:BAAANQAECgQJBwAAAA==.Rinaku:BAAANQADCgcIBwAAAA==.',
Ro='Robeartoe:BAAANQAECgUIAwAAAA==.Roidrage:BAAANQADCgIIAgAAAA==.Rokrin:BAABNQAECn8cAAQEAAkKnRu9LwBuAgAEAAkKnRu9LwBuAgANAAMKBBMVewCyAAAMAAEKSAdY2QAjAAAAAA==.Roleplay:BAAANQAECgYIEgAAAA==.Rorindar:BAAANQAECgIIAgAAAA==.Rose:BAABNQAECn8mAAIGAAkK+BygJQD/AgAGAAkK+BygJQD/AgAAAA==.Rowsdower:BAABNQAECn8kAAInAAgKpBMWDAD6AQAnAAgKpBMWDAD6AQAAAA==.',
Ru='Rubez:BAABNQAECn8nAAIgAAgK+QvLyADyAQAgAAgK+QvLyADyAQAAAA==.Rucca:BAAANQAECgUICgAAAA==.Rulia:BAAANQADCggICwAAAA==.',
['Rí']='Rínzler:BAAANQAECggIEQABNQAECgkJGQAMADYPAA==.',
Sa='Saerah:BAAANQAECgQIBQAAAA==.Sandya:BAAANQAECgUIBQAAAA==.Sans:BAABNQAECn8uAAMZAAkK3RGXTwA2AgAZAAkK3RGXTwA2AgAFAAkKNRWoTgAmAgAAAA==.Saphea:BAABNQAECn8sAAITAAkKdB8MFAAwAwATAAkKdB8MFAAwAwAAAA==.Sarlalia:BAAANQAECgUIBQABNQAECgkJGQAMADYPAA==.Sarutobi:BAAANQAECgUIBgABNQAECgkJJAALAMUXAA==.Sathrenus:BAAANQADCgYIDgAAAA==.',
Sc='Scarletraven:BAABNQAECn8aAAIBAAcKMQX2/gAbAQABAAcKMQX2/gAbAQAAAA==.',
Se='Seifer:BAABNQAECn8ZAAMMAAkKNg+BSwDGAQAMAAkKyA6BSwDGAQAEAAgKawmyZQB2AQAAAA==.Selistras:BAAANQAECgUICwAAAA==.Selri:BAAANQADCgQICAAAAA==.',
Sh='Shadowwarrio:BAAANQAECgQICAAAAA==.Shadø:BAAANQADCgQIBwAAAA==.Shammÿ:BAACNQAFFH8JAAIZAAQKGhBBEwA4AQAZAAQKGhBBEwA4AQA1AAQKfzEAAhkACQqsHnAbACMDABkACQqsHnAbACMDAAAA.Sharikari:BAAANQADCgYIBgABNQAECgUICgACAAAAAA==.Shedim:BAAANQAECgUIBQAAAA==.Shiftinman:BAAANQADCgYIBgAAAA==.Shocktea:BAAANQAECgEIAQAAAA==.Shovelhead:BAAANQADCgUICQAAAA==.Shunt:BAAANQAECgQIBgAAAA==.Shuraina:BAAANQAECgUIDAAAAA==.Shylachase:BAAANQAECgUIEgAAAA==.Shyllamae:BAAANQADCggIFgAAAA==.',
Si='Sinisteria:BAAANQADCgUJBQABNQAFFAcIDAANACYKAA==.Sinisterion:BAABNQAECn8WAAIQAAgKUxUGcgA6AgAQAAgKUxUGcgA6AgABNQAFFAcIDAANACYKAA==.',
Sk='Skybreaker:BAAANQAECgUICwABNQAECgYIDgACAAAAAA==.Skylane:BAABNQAECn8XAAMJAAcKjwyCpwB/AQAJAAcKjwyCpwB/AQAKAAEKAAC/iQAPAAAAAA==.',
Sm='Smokestrider:BAAANQAECgEIAQAAAA==.',
Sn='Snacck:BAAANQAECgIIAgAAAA==.Snanth:BAABNQAECn8mAAMgAAkKUh2lbgCgAgAgAAgKhBylbgCgAgAUAAMKMRaHIwDNAAAAAA==.Sniperq:BAAANQAECgQICAAAAA==.Snowcreeks:BAABNQAECn8XAAIFAAcKaxQhbwC6AQAFAAcKaxQhbwC6AQAAAA==.Snurbin:BAAANQADCgEJAQAAAA==.Snuudle:BAABNQAECn8cAAMJAAkKHBffUQBcAgAJAAkKHBffUQBcAgAKAAEK4gncewAwAAAAAA==.',
So='Sonniy:BAAANQADCgYIAgAAAA==.',
Sp='Spalling:BAAANQAECgUIDAAAAA==.Spauunn:BAAANQAECgIIAgAAAA==.Spelleria:BAAANQADCgYICwAAAA==.Spleenless:BAAANQADCgcIBwABNQAECggIBQACAAAAAA==.Spoon:BAEBNQAECn8vAAMgAAkKPSA+QwD9AgAgAAgKsyI+QwD9AgAUAAEKeBHlPwBDAAAAAA==.',
St='Starcommand:BAAANQAECgMIAwAAAA==.Steelhide:BAABNQAECn8bAAMBAAcKnBJSrQC/AQABAAcKnBJSrQC/AQATAAcKxQyKjABzAQAAAA==.Stoopedholy:BAABNQAECn8dAAISAAgK+xhwQQBiAgASAAgK+xhwQQBiAgABNQAFFAcIEQADALEFAA==.Stubborn:BAABNQAECn8dAAMHAAkK7hqYOAAmAgAHAAgKFRmYOAAmAgAIAAMK2wUkYgB3AAAAAA==.Stubborndk:BAAANQAECgMIAwABNQAECgkJHQAHAO4aAA==.',
Su='Sumata:BAAANQAECgcIDwABNQAECggIHwAkACgWAA==.Sumato:BAABNQAECn8fAAMkAAgKKBbpGACeAQAQAAcKCBMorwCiAQAkAAcKiRXpGACeAQAAAA==.',
Sy='Syllata:BAACNQAFFH8HAAIIAAMKDhKLDADjAAAIAAMKDhKLDADjAAA1AAQKfy0AAggACQoJI8cGAFQDAAgACQoJI8cGAFQDAAAA.Sylvianna:BAABNQAECn8hAAIWAAkKAhHoIwArAgAWAAkKAhHoIwArAgAAAA==.',
['Sî']='Sîd:BAAANQAECggIDwAAAA==.',
['Sï']='Sïd:BAAANQAECggIDwAAAA==.',
Ta='Tadra:BAAANQADCgYICgABNQAECgkJLgAXAOceAA==.Taladen:BAAANQADCggICQAAAA==.Talahon:BAAANQADCggICgABNQAECgUICgACAAAAAA==.Tayswiftie:BAAANQADCggIAgAAAA==.',
Te='Tenebrion:BAAANQADCgcIBwAAAA==.Tenneland:BAAANQADCgUIBQAAAA==.Teppic:BAABNQAECn8cAAIbAAkKyg22GAATAgAbAAkKyg22GAATAgAAAA==.Teradaemon:BAAANQAECgEIAQAAAA==.Terawar:BAABNQAECn8lAAMQAAgKDiU3HABFAwAQAAgKDiU3HABFAwAnAAIKAAApHQDYAAAAAA==.Terrorîst:BAAANQABCggIDgABNQAECgUIDwACAAAAAA==.Tetadesanti:BAABNQAECn8eAAIMAAcKzxLIVACeAQAMAAcKzxLIVACeAQAAAA==.',
Th='Thaljadrak:BAAANQAECgQICwAAAA==.Thebadthing:BAAANQAECgIIAgABNQAECgkJJQAFAGciAA==.Thenazalth:BAAANQAECgEIAQAAAA==.Therealmundy:BAAANQADCgUJBQAAAA==.Therla:BAAANQAECgIIBAABNQAECgUICgACAAAAAA==.Thuggish:BAAANQADCgYIBgAAAA==.Thunderbum:BAAANQAFFAEIAQAAAA==.Thundron:BAACNQAFFH8FAAIBAAIK8hNAIgCTAAABAAIK8hNAIgCTAAA1AAQKfysAAgEACQq7I84LAKEDAAEACQq7I84LAKEDAAAA.',
Ti='Tiandrel:BAAANQADCgMIBAAAAA==.Tiny:BAABNQAECn8fAAITAAgKqhxFNACRAgATAAgKqhxFNACRAgAAAA==.Tinydingo:BAAANQAECgUIDgAAAA==.Tinysham:BAAANQADCggJEAAAAA==.Tiraflecha:BAAANQADCgYIBgAAAA==.Titamao:BAAANQADCgUICAAAAA==.Tizzt:BAAANQABCgQICAABNQAECgUICQACAAAAAA==.',
To='Tokun:BAAANQAECgUICAABNQAECgkJPQAGALQkAA==.Tooktalligo:BAAANQADCgEIAQAAAA==.Toper:BAAANQADCgQIBAAAAA==.Torrak:BAAANQADCgMIAwAAAA==.Totenschein:BAAANQAECgYIDgABNQADCgYIBgACAAAAAA==.',
Tr='Travisaur:BAAANQADCgcICgABNQAECgkJJQAFAGciAA==.Trixibell:BAABNQAECn8XAAIGAAgK5wm7nwDDAQAGAAgK5wm7nwDDAQAAAA==.Trouble:BAAANQAECgQIBAABNQAECgkJNwAWAMwjAA==.',
Ty='Tylethian:BAAANQAECgMIBwAAAA==.',
Un='Uninterested:BAABNQAECn8WAAQDAAcKHBXLDQB2AQAJAAcK9RDangCUAQADAAQKqB/LDQB2AQAKAAEKFgYmgAArAAAAAA==.',
Ur='Urudeathcow:BAAANQAECgEIAgAAAA==.Urupally:BAAANQADCgEIAQAAAA==.Urver:BAAANQAECgcJEwABNQAFFAEIAQACAAAAAA==.',
Us='Username:BAAANQAECgIIBwAAAA==.',
Va='Vaelendrii:BAAANQAECgUICgAAAA==.Valhallo:BAAANQAECgcIBwABNQAFFAQICgAFACAdAA==.Valistrasza:BAAANQAECgQIBwABNQAECggIJQAGAAsWAA==.Valpina:BAAANQAECggIEQAAAA==.',
Ve='Veeronica:BAAANQAECgEIAQAAAA==.Velthari:BAAANQADCggIEQAAAA==.Venomlock:BAAANQADCgYJEAAAAA==.Verst:BAAANQADCgcJBwAAAA==.',
Vh='Vhx:BAAANQAECgYIEQAAAA==.',
Vi='Vibeiety:BAAANQADCgYIBgAAAA==.Violent:BAAANQADCgIIAgAAAA==.Vixelle:BAAANQAECgEIAgAAAA==.',
Vl='Vladdracule:BAAANQADCgcIBwAAAA==.Vladski:BAABNQAECn8UAAIjAAYKYBoWIgDPAQAjAAYKYBoWIgDPAQAAAA==.',
Vm='Vmjecd:BAAANQAECgUIDwAAAA==.Vmjecm:BAAANQAECgQICAAAAA==.Vmjecw:BAABNQAECn8WAAIQAAcKnxQWlwDeAQAQAAcKnxQWlwDeAQAAAA==.',
Vo='Voidspauun:BAABNQAECn8eAAIlAAgKYRRKJwAGAgAlAAgKYRRKJwAGAgAAAA==.Vortsex:BAAANQAECgYIEwAAAA==.',
['Vï']='Vïxenô:BAACNQAFFH8KAAIFAAQKIB3FDgBdAQAFAAQKIB3FDgBdAQA1AAQKfy4AAgUACQpGIkgOAE0DAAUACQpGIkgOAE0DAAAA.',
Wa='Warxiez:BAAANQADCgUIBQAAAA==.Washiki:BAAANQADCgcIBwAAAA==.',
Wh='Whirt:BAABNQAECn8mAAIgAAgKmwnG6AC1AQAgAAgKmwnG6AC1AQAAAA==.Whý:BAAANQAECgQIDAABNQAECgkJLgAXAOceAA==.',
Wi='Widowmaker:BAABNQAECn8pAAQEAAkKvSBsEAAyAwAEAAkKvSBsEAAyAwANAAUKfhcuZgD/AAAMAAEKlAih1wAkAAAAAA==.Wigglez:BAAANQAECgEIAQAAAA==.Williece:BAAANQABCgQICwAAAA==.Wishes:BAAANQAECgQJBwAAAA==.',
Wo='Wocalax:BAAANQAECgIIBgAAAA==.',
Xa='Xandine:BAAANQABCgIIBAAAAA==.Xavilic:BAABNQAECn8hAAIYAAgKHRvaFwCHAgAYAAgKHRvaFwCHAgAAAA==.',
Xe='Xenyen:BAAANQADCggIDQABNQAECgkJNgAcADsWAA==.',
Xm='Xmaxpower:BAAANQAECgYIDwAAAA==.',
Ya='Yacht:BAAANQAECgUIDgAAAA==.',
Ye='Yeb:BAAANQADCgQJBAAAAA==.',
Yo='Yohei:BAAANQAECgUIBgAAAA==.Yonbon:BAAANQAECgEIAgAAAA==.',
Za='Zadrial:BAAANQAECgQIBwABNQAECggIJQAMAMgbAA==.Zahlxr:BAABNQAECn8kAAMTAAgKzxxlLwCmAgATAAgKzxxlLwCmAgABAAUKnRGd7wA2AQAAAA==.Zanix:BAAANQADCgYIBgAAAA==.Zappyboy:BAABNQAECn8lAAIFAAkKZyLEDwBEAwAFAAkKZyLEDwBEAwAAAA==.Zapra:BAAANQADCgYIBgAAAA==.Zapraz:BAAANQAECgQICQABNQAECgYIIAAGAEgeAA==.',
Ze='Zeero:BAABNQAECn8YAAITAAkKfxxFHwDxAgATAAkKfxxFHwDxAgAAAA==.Zenrah:BAABNQAECn8ZAAISAAcKORVZbADVAQASAAcKORVZbADVAQABNQAECgkJGAATAH8cAA==.Zeraphole:BAAANQADCggIDgAAAA==.Zergturts:BAABNQAECn8YAAIgAAcKJRG66wCvAQAgAAcKJRG66wCvAQAAAA==.Zerolith:BAAANQADCggJCAAAAA==.Zethryx:BAAANQAECgUJBQAAAA==.',
Zi='Zif:BAAANQAECgcIDAAAAA==.Zify:BAABNQAECn8dAAISAAkK3xm2JADWAgASAAkK3xm2JADWAgAAAA==.Zitalan:BAAANQADCggICAAAAA==.',
Zm='Zmamaz:BAABNQAECn8nAAIGAAgKyBYeUQB6AgAGAAgKyBYeUQB6AgAAAA==.',
Zo='Zoidbergmd:BAABNQAECn8yAAQDAAkKtxkxDwBaAQAJAAYK1BYinwCTAQADAAUK6xsxDwBaAQAKAAIKbQ43XgBoAAAAAA==.Zomat:BAAANQAECgIIAwAAAA==.Zombrex:BAAANQAECgMIAwAAAA==.Zoob:BAAANQADCgYIBgABNQAECgUIBQACAAAAAA==.Zorbrix:BAABNQAECn8nAAIiAAgKrRu3BwCDAgAiAAgKrRu3BwCDAgAAAA==.',
Zr='Zrre:BAAANQADCggICAAAAA==.',
Zu='Zulgeteb:BAAANQAECgYIDQAAAA==.',
Zy='Zy:BAAANQAECgQICAABNQAFFAcIGAAlAHMhAA==.Zynner:BAABNQAECn8kAAIWAAkK0h8wFQCyAgAWAAkK0h8wFQCyAgABNQAECgYIBgACAAAAAA==.',
Zz='Zztank:BAABNQAECn8eAAIjAAgKFyBhDwCkAgAjAAgKFyBhDwCkAgAAAA==.',
['Zí']='Zí:BAAANQAECgUICQAAAA==.',
['Äi']='Äiøn:BAAANQADCgYIBwAAAA==.',
['Ça']='Çarnage:BAAANQADCgIIAgAAAA==.',
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
