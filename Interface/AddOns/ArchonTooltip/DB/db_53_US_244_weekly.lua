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

local lookup = {'Rogue-Outlaw','Rogue-Subtlety','Paladin-Holy','DeathKnight-Blood','Unknown-Unknown','DemonHunter-Havoc','DemonHunter-Vengeance','Shaman-Restoration','Hunter-BeastMastery','DeathKnight-Unholy','Warlock-Destruction','Mage-Arcane','Warlock-Demonology','Warrior-Arms','Warrior-Fury','Warrior-Protection','Paladin-Protection','Paladin-Retribution','Mage-Frost','DeathKnight-Frost','Druid-Guardian','Shaman-Elemental','Hunter-Marksmanship','Priest-Shadow','Shaman-Enhancement','Druid-Balance','Warlock-Affliction','Monk-Brewmaster','Monk-Windwalker','DemonHunter-Devourer','Monk-Mistweaver','Rogue-Assassination','Priest-Holy','Druid-Restoration','Hunter-Survival','Priest-Discipline','Druid-Feral','Evoker-Augmentation','Evoker-Devastation','Mage-Fire','Evoker-Preservation',}
local provider = {region='US',realm='Zangarmarsh',name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aafra:BAAANQADCgcIBwAAAA==.Aaminae:BAABNQAECn8tAAMBAAkK0xqmBgBeAgABAAkKiRimBgBeAgACAAEKnR+mhwBeAAAAAA==.',
Ab='Abracadaver:BAAANQAECgIIAgAAAA==.Abracastabya:BAAANQADCgQIBAABNQAECggIGgADAP0dAA==.Abysstral:BAAANQABCgYIBgAAAA==.',
Ae='Aedar:BAABNQAECn83AAIEAAkKQB2lIACvAgAEAAkKQB2lIACvAgAAAA==.Aegon:BAAANQADCgcIBwAAAA==.Aenledron:BAAANQAECgEIAQABNQAECggIEAAFAAAAAA==.Aeturnas:BAABNQAECn8yAAIDAAoKBh0yDgBYAwADAAoKBh0yDgBYAwAAAA==.',
Af='Afukeenba:BAAANQAECgIIAgAAAA==.',
Ag='Aghori:BAAANQAECgMIAwAAAA==.',
Ai='Aire:BAABNQAECn8UAAMGAAcKvAbqXwD+AAAGAAcK+wXqXwD+AAAHAAQKigX/JgCBAAAAAA==.',
Al='Alanima:BAAANQAECgUIBgAAAA==.Alauradona:BAAANQADCgUIBwAAAA==.Aliana:BAAANQAECgYIDAABNQAECgoKKAAIAGMZAA==.Alittlegeeky:BAAANQADCgIJAgABNQAECgcIFAAJALscAA==.Allesta:BAAANQADCgYICQAAAA==.Allypally:BAAANQADCggIDwAAAA==.Aloriz:BAAANQADCgMIAwAAAA==.Alphamage:BAAANQAECgYIBwAAAA==.Alphamonk:BAAANQADCgEIAQABNQADCgYIBgAFAAAAAA==.Alphawarrior:BAAANQADCgYIBgAAAA==.Alros:BAABNQAECn87AAIJAAoK3hoiIQBjAgAJAAoK3hoiIQBjAgAAAA==.',
An='Andralynn:BAAANQAECgQIAwAAAA==.',
Ao='Aoiryo:BAAANQADCgIIAgABNQABCgQIBQAFAAAAAA==.',
Aq='Aquilas:BAAANQAECgYIBgAAAA==.',
Ar='Arassa:BAAANQADCgcIBwAAAA==.Archsparks:BAAANQABCgEIAQAAAA==.Arcstream:BAAANQAECgcIEAAAAA==.Arctica:BAAANQAECgQICwAAAA==.Arete:BAAANQADCggIEAAAAA==.Arette:BAAANQADCgMIAwAAAA==.Arkshade:BAABNQAECn8WAAIKAAUKPgw+jwDqAAAKAAUKPgw+jwDqAAAAAA==.',
As='Asmo:BAAANQADCgEIAQAAAA==.Astarii:BAAANQAECggIAgAAAA==.Asterica:BAABNQAECn82AAILAAoKYBk7AgDjAQALAAoKYBk7AgDjAQAAAA==.',
At='Atåvvi:BAAANQADCgQIBAAAAA==.',
Av='Averynicole:BAAANQADCgIIAgAAAA==.',
Aw='Awasjr:BAABNQAECn8vAAIJAAkKShUvTAC4AQAJAAkKShUvTAC4AQAAAA==.',
Ay='Ayano:BAABNQAECn9AAAIMAAoK+SJSGABzAwAMAAoK+SJSGABzAwAAAA==.Ayulur:BAAANQAECgEIAwAAAA==.',
Az='Azraél:BAAANQADCggIBwAAAA==.Azurefalls:BAABNQAECn8xAAIEAAoKRyFkCwBYAwAEAAoKRyFkCwBYAwAAAA==.',
Ba='Badfiremage:BAABNQAECn8nAAMNAAoKURq/RgB+AgANAAoKURq/RgB+AgALAAEKVwLGhgAhAAAAAA==.Balthïer:BAABNQAECn81AAIDAAoK4RvgFwCFAgADAAoK4RvgFwCFAgAAAA==.Bark:BAABNQAECn82AAQOAAoK3yGiGABWAwAOAAoK3yGiGABWAwAPAAUK0hvAEwBkAQAQAAEKtRtSKQBWAAAAAA==.',
Be='Bearshock:BAAANQAECgEIAQAAAA==.Beatriixx:BAAANQADCgEIAQAAAA==.Bee:BAABNQAECn8oAAMRAAkKPCb7AwB8AwARAAkKPCb7AwB8AwASAAUK3hJ5HAHvAAABNQAECgoKPQAEAAYmAA==.Beeb:BAABNQAECn8ZAAIHAAkK7CI8AQAJAwAHAAkK7CI8AQAJAwABNQAECgoKPQAEAAYmAA==.Beefisting:BAAANQADCgIIAgABNQAECgoKPQAEAAYmAA==.Beezz:BAABNQAECn89AAIEAAoKBiaSAwC4AwAEAAoKBiaSAwC4AwAAAA==.Belardor:BAAANQAECggICAAAAA==.Beliara:BAAANQAECgQIAwAAAA==.Bendovar:BAAANQADCgEIAQAAAA==.',
Bi='Bilithi:BAAANQAECgEIAQAAAA==.Bionarra:BAABNQAECn83AAMTAAoKkx63BADZAgATAAoKkx63BADZAgAMAAEKAACy4wEhAAAAAA==.Bishopwr:BAABNQAECn8kAAMOAAkKYg7bVQCAAQAOAAkKYg7bVQCAAQAQAAUKvgFRNgCAAAAAAA==.',
Bl='Blaire:BAAANQADCgQIBAAAAA==.',
Bo='Bobdobbs:BAAANQADCgYIBwAAAA==.Bohica:BAAANQAECgYIBwAAAA==.',
Br='Branch:BAAANQADCgYIBgABNQAECgkJKAAEAMUTAA==.Brem:BAABNQAECn82AAIMAAoKFR3qXADGAgAMAAoKFR3qXADGAgAAAA==.Briara:BAAANQAECgQIBAAAAA==.Broknüs:BAAANQAECgMIBAAAAA==.Broníx:BAAANQAECgQICQAAAA==.Bropeep:BAABNQAECn8pAAMKAAcKjyK7IQDAAgAKAAcKjyK7IQDAAgAUAAIKnQnhmQBgAAAAAA==.',
Bu='Bullshott:BAAANQAECgMIBAAAAA==.Burritobolts:BAAANQADCggICAAAAA==.',
By='Bylun:BAAANQADCggICwAAAA==.',
Ca='Callaghar:BAAANQADCgQIBAABNQAECgcIGwAVAAoDAA==.Calyen:BAAANQAECgMIAwABNQAECgMIAwAFAAAAAA==.Carartha:BAABNQAECn8jAAISAAgKGQjxpQAKAQASAAgKGQjxpQAKAQAAAA==.Carnitine:BAAANQADCgYIBgABNQAECgoKJwANAFEaAA==.Carrots:BAAANQAECgQIDgAAAA==.Cashmoolah:BAABNQAECn83AAMSAAoK4Q45XgCfAQASAAoK4Q45XgCfAQARAAIKzgGDVQAfAAAAAA==.Catfight:BAAANQAECgQICwAAAA==.',
Ch='Chadilton:BAAANQADCgYIDwAAAA==.Chadsmon:BAACNQAFFH8PAAMWAAYK9BCFDwB2AQAWAAUKLA2FDwB2AQAIAAEKHAGJIwA5AAA1AAQKf0YAAhYACgqKG6IXAEQCABYACgqKG6IXAEQCAAAA.Change:BAAANQAECgQIBAAAAA==.Charcoal:BAABNQAECn81AAMLAAoKYhYhCQBoAgALAAkKtRMhCQBoAgANAAgKQRVtXABOAQAAAA==.Chasebakes:BAABNQAECn84AAMXAAoKZSCwDQAFAwAXAAoKnB2wDQAFAwAJAAMK6Bv4xACoAAAAAA==.Cheesecake:BAABNQAECn8UAAILAAUKLAs6MQACAQALAAUKLAs6MQACAQAAAA==.Choks:BAAANQAECgQICgAAAA==.Chumbawamba:BAAANQADCgYJBgAAAA==.Chéfboyrlee:BAABNQAECn8eAAIYAAkKhB2KDgDsAQAYAAkKhB2KDgDsAQABNQAFFAYIGAAZALscAA==.',
Ci='Cindiyoohoo:BAABNQAECn8yAAIaAAoKjhp7DwBQAgAaAAoKjhp7DwBQAgAAAA==.Cizmac:BAAANQADCgcICwAAAA==.',
Cl='Clada:BAAANQADCgUIBQAAAA==.Claus:BAAANQADCggICAABNQAECgoKIgARADwMAA==.',
Cm='Cmdrshepard:BAAANQADCgEIAQABNQAECgcIHAALAOYPAA==.',
Co='Corruptdata:BAAANQADCgMIBgAAAA==.Cownado:BAAANQAECgMIAwAAAA==.',
Cr='Crawlerkarl:BAAANQADCgIIAgAAAA==.',
Ct='Ctrlaltchill:BAAANQADCgUIBAAAAA==.',
Cu='Cursedspirit:BAAANQADCgMIAwAAAA==.Custard:BAAANQAECgMIAwAAAA==.Cut:BAAANQADCgYIEQABNQAECgcIFAAGALwGAA==.',
Cy='Cyfelen:BAABNQAECn86AAQLAAoKuxtXAgDVAQANAAoKZxjSRACEAgALAAgK+h1XAgDVAQAbAAIKsB28HQCOAAAAAA==.Cynleel:BAAANQAECgYIBwAAAA==.Cyris:BAAANQAECgcIBgAAAA==.',
Da='Dahrena:BAAANQAECgYICwAAAA==.Darthmall:BAAANQAECgYIDwABNQAFFAMIBAAFAAAAAA==.Dawgg:BAAANQAECgEIAQAAAA==.Dawntyrant:BAAANQADCgIIAwAAAA==.',
De='Delyta:BAAANQADCgcIBwAAAA==.Demidru:BAABNQAECn8fAAIVAAoKqRxREwAuAgAVAAoKqRxREwAuAgAAAA==.Derat:BAAANQADCggICAAAAA==.Deucalion:BAAANQADCgcICQAAAA==.Deveruxx:BAAANQADCgEIAQAAAA==.',
Di='Dibbydab:BAAANQAECgcIEAAAAA==.',
Dj='Django:BAABNQAECn8eAAIaAAkKkRbvJgCcAgAaAAkKkRbvJgCcAgAAAA==.Djehrtey:BAAANQAECgMIBQAAAA==.Djinni:BAABNQAECn8oAAMcAAkKmh1rBgDnAgAcAAkKmh1rBgDnAgAdAAQKXRHTMgCYAAABNQAFFAMIBAAFAAAAAA==.Djwiltumble:BAAANQADCgUIBQAAAA==.',
Dk='Dkota:BAAANQADCgYIEQAAAA==.',
Do='Doodle:BAABNQAECn8fAAIUAAgKMBg4QQDBAQAUAAgKMBg4QQDBAQAAAA==.',
Dr='Dracnahr:BAAANQAECgcIEgAAAA==.Drenleah:BAAANQAECgYIDwABNQAECgoKJgAeALQUAA==.Drenlee:BAAANQAECgIIAgABNQAECgoKJgAeALQUAA==.Dromokafrapp:BAAANQAECgIIAgAAAA==.',
Du='Dumblegear:BAABNQAECn8aAAIMAAgKeBryfQCCAgAMAAgKeBryfQCCAgAAAA==.Duramei:BAAANQADCgMIAwAAAA==.Durian:BAABNQAECn8oAAIIAAoKYxm1KQC8AgAIAAoKYxm1KQC8AgAAAA==.',
Dw='Dwagon:BAAANQADCgYJBgABNQAECgoKLAAIAAoSAA==.',
Dy='Dysdayne:BAAANQAECgQIBwAAAA==.',
['Dë']='Dëathx:BAAANQADCgcIBwABNQAECgcIHgAPAJsXAA==.',
Ed='Edinna:BAABNQAECn8wAAIMAAoK5QmjUgC1AQAMAAoK5QmjUgC1AQAAAA==.',
Ei='Eileamaid:BAAANQADCgYIEQAAAA==.',
El='Elessedil:BAAANQAECgUIBgAAAA==.Elpally:BAAANQADCgMIAwAAAA==.Elspeth:BAAANQADCggICAABNQAECgcIGwAVAAoDAA==.Elyriana:BAAANQAECgcIDwAAAA==.',
Em='Emila:BAEANQAECgcIBwABNQAECgoKLAAJADwhAA==.Emirozu:BAAANQADCgUIBQAAAA==.Emma:BAAANQABCgQIBgAAAA==.Emokilla:BAAANQAECggIDQAAAA==.Emriq:BAAANQAECgMIBAAAAA==.',
En='Enrique:BAABNQAECn9RAAMSAAoKlCNXIwA3AwASAAoKlCNXIwA3AwARAAEK0xP1agA8AAAAAA==.',
Ep='Epedemik:BAAANQAECgEIAQAAAA==.',
Er='Erazath:BAAANQAECgMIAwABNQAECgkJKAAEAMUTAA==.Erussh:BAAANQADCgQIBQAAAA==.',
Es='Estanna:BAAANQAECggIBgAAAA==.',
Ev='Evöö:BAAANQAECgYIBgAAAA==.',
Ex='Exhul:BAAANQAECgMIBAAAAA==.',
Fa='Faeng:BAAANQAFFAMIBAAAAA==.Faewing:BAAANQAECgEIAQAAAA==.Falar:BAAANQAECgcIDQAAAA==.Faubito:BAAANQAECgYIBgAAAA==.',
Fe='Fearlesfreep:BAABNQAECn81AAIJAAoKShDPOwDyAQAJAAoKShDPOwDyAQAAAA==.Febz:BAAANQAECgUICAAAAA==.Felatonin:BAABNQAECn8ZAAIeAAgK6B+8GgCCAgAeAAgK6B+8GgCCAgAAAA==.Felfüry:BAABNQAECn86AAMGAAoKzhKUGwDAAQAGAAoKDxKUGwDAAQAHAAgKMw1xEQDAAAAAAA==.Fenixshaw:BAAANQADCgYIFQAAAA==.Festyr:BAAANQADCgQIBAAAAA==.Feyd:BAAANQADCgcIDQAAAA==.',
Fi='Finella:BAAANQAECgEIAQAAAA==.Finneas:BAABNQAECn8fAAMXAAkKwQ/wHQAOAQAXAAYKFg3wHQAOAQAJAAUKJA9zpgDhAAAAAA==.',
Fo='Foggpy:BAABNQAECn8yAAIbAAoK8x84AQBWAwAbAAoK8x84AQBWAwAAAA==.',
Fr='Freinkenbaby:BAAANQADCgEIAQAAAA==.Frostey:BAAANQAECgUIDAAAAA==.Fröstmöurne:BAABNQAECn8sAAIEAAkKlAz3JgBhAQAEAAkKlAz3JgBhAQAAAA==.',
Fu='Furbetime:BAAANQADCgMIAwAAAA==.Furydeath:BAAANQAECgIIAgAAAA==.',
Ga='Gabrièllè:BAAANQADCgcIBwAAAA==.',
Ge='Geluria:BAAANQAECgQICgABNQAECgcIGgANAHUdAA==.Genghiskhan:BAABNQAECn8sAAIKAAkKxRrAKgCLAgAKAAkKxRrAKgCLAgAAAA==.Geren:BAAANQAECggIDwAAAA==.Geret:BAABNQAECn8pAAISAAgKhRPsjgAHAgASAAgKhRPsjgAHAgAAAA==.',
Gh='Ghanaria:BAAANQADCgQJBAAAAA==.',
Gi='Gingervex:BAAANQADCggIEAAAAA==.Gissmo:BAAANQADCgYICwAAAA==.',
Gl='Glitchy:BAABNQAECn86AAIaAAoKRhUCFQABAgAaAAoKRhUCFQABAgAAAA==.Gloppy:BAAANQADCgcIBwAAAA==.',
Go='Gogmagog:BAAANQADCgEIAQAAAA==.Goingtogetu:BAABNQAECn86AAIRAAoKYBzsCAA0AgARAAoKYBzsCAA0AgAAAA==.Goldfarmr:BAAANQAECggIEgABNQAECgoKNQAMAB4eAA==.Goldglazeher:BAABNQAECn81AAIMAAoKHh40OgATAwAMAAoKHh40OgATAwAAAA==.Goldrawr:BAAANQAECgYIBwABNQAECgoKNQAMAB4eAA==.Golgotha:BAAANQABCgcICQAAAA==.',
Gr='Graddy:BAAANQADCgQIBAAAAA==.Gradhrek:BAAANQABCgIIAwAAAA==.Greeley:BAABNQAECn8jAAIXAAoKfB3QCQBJAgAXAAoKfB3QCQBJAgAAAA==.Greganir:BAABNQAECn8YAAMTAAgKdxroGwARAQAMAAgKaxaGrQAnAgATAAQKOhroGwARAQABNQAECgcIGAAEAL4bAA==.Gregdapro:BAABNQAECn8YAAIEAAcKvhuXNwArAgAEAAcKvhuXNwArAgAAAA==.Grimshady:BAAANQAECgIIAgAAAA==.Gritty:BAAANQABCgMIAwAAAA==.',
Gu='Gunnyal:BAAANQAECgQICwAAAA==.',
Gy='Gyathew:BAABNQAECn8qAAIWAAkKRyBWEwBXAwAWAAkKRyBWEwBXAwAAAA==.',
Ha='Hagunn:BAABNQAECn8ZAAMOAAkKPxdPgwATAgAOAAkKxxRPgwATAgAPAAMK9Ru6GgD6AAAAAA==.Happerixie:BAAANQADCgcIBwAAAA==.',
He='Heladaa:BAAANQADCgMIAwAAAA==.Hervöralvit:BAAANQADCgIIAgAAAA==.Hevy:BAABNQAECn8mAAIeAAoKtBSIEADgAQAeAAoKtBSIEADgAQAAAA==.',
Hi='Hidensneak:BAAANQADCggICAAAAA==.Hildzap:BAAANQADCgYICwAAAA==.',
Ho='Holygriff:BAAANQAECgIIAgAAAA==.Holyshots:BAABNQAECn88AAISAAoKIBMhRgDmAQASAAoKIBMhRgDmAQAAAA==.Howlinnbrews:BAAANQADCggICgAAAA==.',
Hu='Huyu:BAAANQADCgUIAQAAAA==.',
Id='Idrizzt:BAAANQABCgYICAAAAA==.',
Ig='Ignore:BAAANQAECggICgABNQAECgoKJwANAFEaAA==.',
Io='Iobo:BAAANQAECgQICwAAAA==.',
Ir='Ironhidez:BAABNQAECn8vAAISAAgKDAoZzgB/AQASAAgKDAoZzgB/AQAAAA==.',
Is='Isaarek:BAAANQAECgEIAQAAAA==.Ishiza:BAAANQABCgIIAgAAAA==.',
It='Itsatrap:BAABNQAECn8UAAIJAAcKtxhiZwBsAQAJAAcKtxhiZwBsAQABNQAECgoKKAAIAGMZAA==.',
Iz='Izerol:BAABNQAECn9OAAIdAAoKviRZBACOAwAdAAoKviRZBACOAwAAAA==.',
Ja='Jasmini:BAAANQADCgQIBAAAAA==.Jaylea:BAAANQABCgUICAAAAA==.',
Je='Jeb:BAAANQABCgUIBQABNQAECggIGgADAP0dAA==.Jebopally:BAABNQAECn8aAAMDAAgK/R2dPAByAgADAAcKiB6dPAByAgASAAcKnhk/qADPAQAAAA==.Jeouleous:BAAANQADCgcIBwAAAA==.Jetblack:BAABNQAECn8dAAINAAcKfxlGfwDoAQANAAcKfxlGfwDoAQAAAA==.',
Ji='Jiblows:BAAANQADCgYIBgAAAA==.Jibolls:BAAANQAECgUICwAAAA==.',
Jo='Joehex:BAABNQAECn8wAAIQAAkKgiBaBwDmAgAQAAkKgiBaBwDmAgAAAA==.Jointjester:BAAANQADCggICAAAAA==.Joulez:BAAANQADCgYICwAAAA==.',
Ju='Judgematt:BAAANQADCggIDAAAAA==.Judgemental:BAAANQADCgQIBAAAAA==.Justin:BAABNQAECn8VAAIOAAgKlhCtewAeAQAOAAgKlhCtewAeAQAAAA==.',
Ka='Kaidoe:BAAANQAECgYIBwAAAA==.Kaleesh:BAACNQAFFH8PAAIZAAUKbCKGAQD/AQAZAAUKbCKGAQD/AQA1AAQKfy8AAhkACgpKJm0AAGwDABkACgpKJm0AAGwDAAAA.Kallux:BAABNQAECn85AAIEAAoKTB4MDACHAgAEAAoKTB4MDACHAgAAAA==.Kalma:BAABNQAECn8rAAIEAAoKyx60DQBqAgAEAAoKyx60DQBqAgAAAA==.Kananga:BAAANQAECgQICwAAAA==.Kasca:BAABNQAECn8VAAIaAAcKQAjsdQDzAAAaAAcKQAjsdQDzAAAAAA==.Kato:BAAANQAECgQIBAABNQAECgoKLAAZAOIYAA==.Kazeem:BAAANQAECgcIDAAAAA==.',
Ke='Kerah:BAAANQADCggICAABNQAECgoKKAAIAGMZAA==.',
Kh='Khadran:BAAANQADCgIIAwAAAA==.Khalyraa:BAAANQAECgUICQAAAA==.',
Ki='Kiermac:BAAANQAECgYIDAAAAA==.Kindred:BAAANQADCgQIBAAAAA==.Kiragrande:BAABNQAECn8qAAIfAAoKvhGgFQAiAgAfAAoKvhGgFQAiAgAAAA==.Kiriku:BAAANQAECgQIDwAAAA==.Kithane:BAAANQADCgMIBgAAAA==.',
Kl='Klorto:BAAANQADCgEIAQAAAA==.',
Ko='Korbinf:BAAANQAECgUIBQAAAA==.Kotok:BAAANQAECgQIDgAAAA==.',
Kr='Krelein:BAABNQAECn8WAAIRAAUKJRnnMgBLAQARAAUKJRnnMgBLAQAAAA==.',
Ku='Kurth:BAAANQADCgUICAAAAA==.',
Ky='Kyu:BAAANQADCgcIDQAAAA==.',
La='Lancaster:BAAANQADCgIIAgAAAA==.',
Le='Lee:BAABNQAECn8ZAAIdAAcK4yIZGACIAgAdAAcK4yIZGACIAgAAAA==.Leenaashala:BAAANQAECgQICQABNQAECgoKLAAZAOIYAA==.Levin:BAAANQAECgIIAwAAAA==.',
Li='Linissa:BAAANQAECgMIBgABNQAFFAMIBAAFAAAAAA==.',
Ll='Llght:BAAANQAECggIEQAAAA==.',
Lo='Logankord:BAABNQAECn8xAAIPAAkK+R8NBQDaAgAPAAkK+R8NBQDaAgAAAA==.Lokeira:BAABNQAECn8sAAIIAAoKChJqXQD3AQAIAAoKChJqXQD3AQAAAA==.Lono:BAAANQAECgUIBQAAAA==.Loonnah:BAAANQADCgQIBQAAAA==.',
Lu='Luuniren:BAAANQADCggIIwABNQAECgQIBwAFAAAAAA==.Luvbug:BAABNQAECn8UAAIJAAcKuxzRagA+AgAJAAcKuxzRagA+AgAAAA==.',
Ly='Lyais:BAAANQAECgQIBQAAAA==.Lyara:BAACNQAFFH8JAAIIAAUKkRrfCgA6AQAIAAUKkRrfCgA6AQA1AAQKfzAAAwgACgqFHucrALMCAAgACgqFHucrALMCABYACQqpG48VAFgCAAAA.Lythos:BAABNQAECn8oAAIEAAkKxRM3TgC9AQAEAAkKxRM3TgC9AQAAAA==.',
['Lø']='Lørdøfßud:BAABNQAECn8yAAMQAAgK5CG/BQASAwAQAAgK5CG/BQASAwAOAAEKAAANUAE2AAAAAA==.',
Ma='Machomans:BAAANQAECgQIBQABNQAECgcIEAAFAAAAAA==.Magdann:BAAANQABCgIJAgAAAA==.Magicmeat:BAAANQAECgEIAQAAAA==.Mahasamatman:BAAANQAECgEIAQAAAA==.Makimá:BAAANQADCgYIBgABNQAECgoKFgACAAILAA==.Mandragora:BAAANQADCgIIAgAAAA==.Mankilla:BAAANQADCgMIAwAAAA==.Mansa:BAABNQAECn88AAIgAAoKZQ+aCgDaAQAgAAoKZQ+aCgDaAQAAAA==.Mastamojo:BAABNQAECn8fAAIDAAgKwgdiiwB6AQADAAgKwgdiiwB6AQAAAA==.Mattheals:BAABNQAECn8oAAIhAAoKxhikGACdAgAhAAoKxhikGACdAgAAAA==.',
Mc='Mcmurphy:BAAANQADCgYIBgAAAA==.',
Me='Meanieman:BAAANQABCggIDAAAAA==.Meanpaula:BAAANQADCgMIAwAAAA==.Meissen:BAABNQAECn8cAAILAAcK5g9KCADpAAALAAcK5g9KCADpAAAAAA==.Meltara:BAAANQADCgQIBAAAAA==.Messìah:BAABNQAECn8fAAIaAAYK+g8hMwADAQAaAAYK+g8hMwADAQAAAA==.Metamonster:BAAANQAECgUICwAAAA==.',
Mi='Mickie:BAABNQAECn8bAAIVAAcKCgPNNACMAAAVAAcKCgPNNACMAAAAAA==.Mirko:BAAANQADCgYJCQABNQAECgcIEAAFAAAAAA==.',
Ml='Mladjo:BAAANQAECgMIBgAAAA==.',
Mo='Mockery:BAABNQAECn8+AAIMAAoKNA3QSADXAQAMAAoKNA3QSADXAQAAAA==.Mokokniki:BAABNQAECn8kAAIiAAgKIhGILQCvAQAiAAgKIhGILQCvAQAAAA==.Moneie:BAAANQADCgEIAQAAAA==.Monger:BAAANQADCgEIAQAAAA==.Moog:BAAANQADCgQIBAAAAA==.Moondo:BAAANQADCgQIBAAAAA==.Moothyr:BAAANQAECgYIEQAAAA==.Morticiá:BAAANQAECgIIAgAAAA==.Mourningstar:BAACNQAFFH8KAAIKAAUK0R2MBQDLAQAKAAUK0R2MBQDLAQA1AAQKfyIAAwoACgp6I+EUABIDAAoACAqAI+EUABIDAAQABgr0HrdiAGcBAAE1AAUUBggUAAQAlxoA.Mozaic:BAABNQAECn84AAIQAAoKWh/2AwCHAgAQAAoKWh/2AwCHAgAAAA==.',
My='Myselia:BAAANQADCgYICAAAAA==.',
Na='Nad:BAAANQAECgQIBAAAAA==.Naec:BAAANQADCgEIAQAAAA==.Nalthis:BAAANQAECggICQAAAA==.',
Ne='Necromus:BAAANQAECgQICgAAAA==.Nekra:BAAANQAECgQIDwAAAA==.',
Ni='Nibbi:BAAANQADCgYJBgAAAA==.Nicehair:BAAANQAECgcIDAAAAA==.',
No='Nocturnum:BAACNQAFFH8FAAIeAAMKlwq8EQCCAAAeAAMKlwq8EQCCAAA1AAQKfzcAAh4ACgpoIdIHAFQDAB4ACgpoIdIHAFQDAAAA.',
Nu='Numb:BAAANQADCgEIAQAAAA==.',
Ny='Nyctea:BAAANQADCgQIBAAAAA==.Nyria:BAAANQADCgEIAQAAAA==.',
Oh='Oha:BAAANQAECgQIAwAAAA==.',
Ol='Oldmongerpal:BAAANQADCggICgAAAA==.Oltiyet:BAAANQAECgQIBAABNQAECgQIBwAFAAAAAA==.',
On='Onepuffman:BAACNQAFFH8YAAIZAAYKuxzxAAA9AgAZAAYKuxzxAAA9AgA1AAQKfzQAAhkACgrZI9YIAOoCABkACgrZI9YIAOoCAAAA.Onetwocowpow:BAABNQAECn88AAIfAAoKtBBfDADOAQAfAAoKtBBfDADOAQAAAA==.',
Or='Ordanith:BAABNQAECn81AAISAAoK9CBmFADXAgASAAoK9CBmFADXAgAAAA==.Orionn:BAACNQAFFH8YAAIJAAYKGxq8AwBxAQAJAAYKGxq8AwBxAQA1AAQKf0wAAgkACgqlJmYCAGgDAAkACgqlJmYCAGgDAAAA.',
Os='Osø:BAAANQAECgUIDwAAAA==.',
Ov='Oven:BAABNQAECn8xAAQfAAoKwhVJFQAnAgAfAAgKfhZJFQAnAgAdAAkK/A/RGgBYAQAcAAEKDw4qMQA1AAAAAA==.',
Ow='Owlette:BAAANQAECgQIBAAAAA==.Owlxero:BAAANQADCggIEAAAAA==.',
Pa='Patelz:BAAANQADCgYIBgAAAA==.',
Pe='Pelma:BAAANQADCgIIAgABNQAECgQICgAFAAAAAA==.',
Ph='Phyras:BAAANQABCgcIBwAAAA==.',
Pi='Pinesoul:BAAANQADCgQIBAAAAA==.Pippins:BAAANQADCgEIAQAAAA==.',
Po='Polytotems:BAAANQAECgYIDgAAAA==.',
Pr='Praystation:BAAANQAECgEIAQABNQAECgYIEQAFAAAAAA==.',
Ps='Psygon:BAAANQADCgYIBgAAAA==.',
Qu='Quora:BAAANQABCggIEgAAAA==.',
Ra='Raelone:BAABNQAECn8nAAMLAAgKIBcUCADwAAALAAYKuxcUCADwAAAbAAMKGRQ1FgDnAAAAAA==.Rageofmommy:BAAANQADCgIIAwAAAA==.Raidoe:BAAANQAECgYIEAAAAA==.Raknslash:BAAANQADCgYIBgAAAA==.Rameumptom:BAAANQADCgYIDAAAAA==.Randers:BAAANQADCgMIAwAAAA==.Rangérz:BAABNQAECn80AAIJAAoKIxh0LwAiAgAJAAoKIxh0LwAiAgAAAA==.Ranoa:BAABNQAECn8UAAIRAAgKqxBzKwCBAQARAAgKqxBzKwCBAQABNQAECgoKMgAVAN0eAA==.Rant:BAAANQAECgUICwAAAA==.Ravencraw:BAAANQADCgYJCgAAAA==.Ravid:BAAANQADCgEIAQAAAA==.',
Re='Rebirth:BAAANQADCgUIBQAAAA==.Redxrum:BAAANQAECgIIAgAAAA==.Regress:BAAANQAECgQICQAAAA==.Reo:BAAANQADCgQIBAAAAA==.Reàper:BAAANQAECgEIAQAAAA==.',
Rh='Rheavin:BAAANQABCgQIBQAAAA==.Rhell:BAABNQAECn8bAAIDAAgKRSDoIwDbAgADAAgKRSDoIwDbAgAAAA==.Rhellen:BAABNQAECn8rAAIhAAoKEB+xDAAZAwAhAAoKEB+xDAAZAwABNQAECggIGwADAEUgAA==.',
Ri='Rinche:BAABNQAECn8VAAMWAAcK+wfYogBQAQAWAAcK+wfYogBQAQAIAAMKOgcx+AB6AAAAAA==.Rintche:BAAANQADCgUIBQAAAA==.',
Ro='Rolland:BAABNQAECn8WAAIXAAgK8hY0JAAsAgAXAAgK8hY0JAAsAgAAAA==.Rootbeamxo:BAAANQAECgQJBAAAAA==.Rosefyre:BAACNQAFFH8GAAINAAMKzQd5EQDDAAANAAMKzQd5EQDDAAA1AAQKfyUAAg0ACgqaEThsABkCAA0ACgqaEThsABkCAAAA.',
Ru='Rudo:BAABNQAECn8bAAQXAAkKGxSVOACLAQAJAAcKKRYXrQCqAQAXAAgKWwqVOACLAQAjAAMK6wdtDwCXAAABNQAECgoKFgACAAILAA==.Rumproblem:BAABNQAECn8hAAQkAAoK7Q7CDwAuAQAhAAgK9QsvigB3AQAYAAgKNgvgFwBYAQAkAAYKMg7CDwAuAQAAAA==.Ruri:BAAANQAECgMIBAABNQAECgoKFgACAAILAA==.',
Ry='Ryegar:BAAANQADCgcIDAABNQAECgoKLQAlAOkXAA==.Ryeger:BAABNQAECn8tAAMlAAoK6RfUCAC8AQAlAAoK6RfUCAC8AQAaAAUK0gVmfgDTAAAAAA==.Ryuaoi:BAAANQAECgEIAwABNQABCgQIBQAFAAAAAA==.',
['Ró']='Róótbear:BAAANQAECgUICgAAAA==.',
Sa='Safety:BAAANQAECgQICQAAAA==.Salfros:BAAANQADCgUIBQAAAA==.Samovar:BAABNQAECn8xAAMSAAoK3A//UgC9AQASAAoK3A//UgC9AQADAAYKywWowAD7AAAAAA==.Samovaro:BAAANQADCgQIBAAAAA==.Sandbones:BAAANQAECgQIBAABNQAECgoKPgAMADQNAA==.Sandwiches:BAAANQAECggIEQAAAA==.Sanielan:BAAANQADCgMIAwAAAA==.',
Sc='Scalebagz:BAABNQAECn8rAAMmAAoKDxjZBQB8AgAmAAoKDxjZBQB8AgAnAAUKPhhDDQAGAQAAAA==.Schism:BAAANQAFFAEIAgAAAA==.',
Se='Sentren:BAAANQAECgIIAgAAAA==.Setresh:BAABNQAECn82AAIjAAoK9hILAwATAgAjAAoK9hILAwATAgAAAA==.',
Sh='Shaken:BAAANQADCgMIAwAAAA==.Shammatty:BAAANQADCgcIBwAAAA==.Shamwowhex:BAAANQAECgYICQAAAA==.Shangöh:BAAANQADCgUICQABNQAECgoKNQADAOEbAA==.Sharatira:BAAANQADCgYIDAAAAA==.Shivver:BAAANQADCgQIBAAAAA==.Shivyn:BAABNQAECn84AAIIAAkKyhG7NQDGAQAIAAkKyhG7NQDGAQAAAA==.',
Si='Sibadeekay:BAABNQAECn87AAMKAAoK8RyEDgAzAgAKAAoKwRuEDgAzAgAEAAUKHCH+UACxAQAAAA==.Sickkid:BAABNQAECn8kAAMPAAkKYhAyCACaAQAPAAgKjw8yCACaAQAOAAcKxwlhwwB0AQAAAA==.Silvertier:BAAANQADCgMIAwAAAA==.Silverwulf:BAAANQADCgUIBwAAAA==.Sin:BAAANQAECgUICwAAAA==.Sindrya:BAAANQAECgQIBwAAAA==.',
Sk='Skunkt:BAAANQADCgMIAwAAAA==.',
Sm='Smoothvelvet:BAABNQAECn8sAAIZAAoK4hhpDgCnAQAZAAoK4hhpDgCnAQAAAA==.',
Sn='Snooker:BAAANQADCgEIAQAAAA==.Snuggles:BAAANQADCgcIBwABNQAECgoKKwAjAJ4YAA==.',
So='Solára:BAABNQAECn8eAAMHAAoKpQ8LHQDuAAAeAAgKLAsnPQBfAQAHAAUKlRALHQDuAAAAAA==.',
Sp='Spellforge:BAAANQAECgMIAwAAAA==.Spinach:BAAANQAECgQIBAAAAA==.Sprath:BAAANQAECgQIBwAAAA==.',
St='Staretra:BAABNQAECn88AAMYAAoKzxI6NgByAQAYAAcKBgk6NgByAQAhAAoKlQObUABvAQAAAA==.Sterarcher:BAAANQADCgIIAgAAAA==.',
Su='Sumar:BAAANQABCgEIAQAAAA==.Summersky:BAAANQAECgEIAQAAAA==.Sungjinwoo:BAAANQAECgEIAQAAAA==.Superdestror:BAAANQABCgcICgAAAA==.',
Ta='Taadra:BAABNQAECn84AAIIAAoKzhQKMgDZAQAIAAoKzhQKMgDZAQAAAA==.Talerah:BAABNQAECn8rAAIUAAkKuAvhMABhAQAUAAkKuAvhMABhAQAAAA==.Taliliia:BAAANQABCgIIAgAAAA==.Talilyia:BAAANQADCgcIHgAAAA==.Talohae:BAACNQAFFH8HAAIiAAMKVx31CgAfAQAiAAMKVx31CgAfAQA1AAQKfzIAAiIACgq7JGEBAMMDACIACgq7JGEBAMMDAAAA.Tanjent:BAAANQAECgQIBgAAAA==.Tapio:BAAANQAECgIIAgAAAA==.Tatsuma:BAAANQADCgYIEgABNQAECgcIHgAVAFUVAA==.Tatsumå:BAAANQAECgYICgABNQAECgcIHgAVAFUVAA==.Tavv:BAABNQAECn8kAAIZAAgKFghYGwCvAQAZAAgKFghYGwCvAQAAAA==.',
Te='Tekkesh:BAAANQADCgMIAwAAAA==.Terp:BAAANQABCgYIBgAAAA==.',
Th='Thenakedpaly:BAAANQADCgEIAQAAAA==.Thibbildorf:BAAANQABCgEIAQAAAA==.Thirain:BAAANQADCgcIBwABNQAECgUICQAFAAAAAA==.Thoghar:BAAANQABCgEIAQABNQADCgMIAwAFAAAAAA==.Thorrs:BAABNQAECn8fAAIWAAoKiw6zWQAWAgAWAAoKiw6zWQAWAgAAAA==.Thuglifé:BAABNQAECn8cAAIQAAkK1gqhGQCaAQAQAAkK1gqhGQCaAQAAAA==.Thundacat:BAABNQAECn8sAAIVAAoK8CQ9AgAvAwAVAAoK8CQ9AgAvAwAAAA==.',
Ti='Tia:BAAANQADCgUIBQABNQAECgcIFAAGALwGAA==.Tidemaiden:BAABNQAECn8jAAMIAAgKaRE+bgDAAQAIAAgKaRE+bgDAAQAZAAIKzgKIKwAsAAAAAA==.Tipsymancer:BAABNQAECn88AAIcAAoKkh9EAgCkAgAcAAoKkh9EAgCkAgAAAA==.',
Tr='Treesus:BAABNQAECn8mAAIaAAoKeg92NgA4AgAaAAoKeg92NgA4AgAAAA==.Treëfrog:BAAANQABCgIIAgAAAA==.Trickytrey:BAAANQADCgIIAgABNQAECgoKHgAMAP0WAA==.Troutman:BAAANQAECgEIAQAAAA==.Tryantjhg:BAAANQABCgQIBAAAAA==.',
Ts='Tsu:BAAANQADCgYIBgAAAA==.',
['Tñ']='Tñer:BAABNQAECn8eAAMMAAoK/RYATgDFAQAMAAoK/RYATgDFAQAoAAEKAADaBwAAAAAAAA==.',
Ur='Uruloke:BAAANQADCgYIDAABNQAECgEIAQAFAAAAAA==.',
Va='Valry:BAAANQADCgQIBAAAAA==.Vashdin:BAAANQAECgQICwAAAA==.',
Ve='Velashis:BAABNQAECn8eAAMiAAkKZRkZHABVAgAiAAkKZRkZHABVAgAaAAIKUgK7swAwAAAAAA==.Venomable:BAABNQAECn8fAAMCAAgKABPtIQC8AQACAAgKWRHtIQC8AQAgAAUK9gzLLgC0AAAAAA==.Vermin:BAABNQAECn8uAAIWAAkKthq0PQB/AgAWAAkKthq0PQB/AgAAAA==.',
Vi='Vicvega:BAABNQAECn8WAAMCAAoKAgv0RwA/AQACAAgK/wv0RwA/AQAgAAcKCgavYQAuAQAAAA==.Vivif:BAABNQAECn8+AAQcAAoKix7RBgDZAgAcAAoKVB7RBgDZAgAfAAoKdBivDADHAQAdAAUK2B5wLgClAQAAAA==.Vivila:BAAANQAECgMIBQABNQAECgoKJgAeALQUAA==.',
Vo='Void:BAAANQADCgYIEgAAAA==.Voldemotor:BAAANQAECgcIEAAAAA==.Volstak:BAAANQADCgUIBwAAAA==.',
Vr='Vresim:BAABNQAECn8XAAMnAAgKQhlzGADBAQAnAAcKmxZzGADBAQApAAcK+RJYJAChAQAAAA==.',
Vu='Vugnus:BAAANQAECgQICwAAAA==.Vugowulf:BAAANQADCggIDgAAAA==.',
['Vé']='Véxx:BAABNQAECn8VAAIHAAUKWBl1FABmAQAHAAUKWBl1FABmAQAAAA==.',
['Vï']='Vïx:BAAANQAECgYIBQAAAA==.',
Wa='Wadewilson:BAAANQADCgcICwAAAA==.Waltahflight:BAAANQAECgEIAQAAAA==.Wannan:BAAANQADCggICAAAAA==.Waye:BAABNQAECn8UAAMVAAkKOB/5DgB0AgAVAAgKjx/5DgB0AgAlAAMK4xnCEwD2AAAAAA==.',
We='Westrin:BAACNQAFFH8JAAIbAAQK5x2iAQAsAQAbAAQK5x2iAQAsAQA1AAQKfywAAhsACgomJT4AAFYDABsACgomJT4AAFYDAAAA.',
Wi='Wiegraf:BAAANQADCgYJCQABNQAECgoKNQADAOEbAA==.Wife:BAABNQAECn8aAAMSAAkKwSExPQDeAgASAAkKwSExPQDeAgADAAMK+wUF/ACFAAAAAA==.Wingedmonkey:BAAANQADCgEIAQAAAA==.',
Wr='Wrathe:BAAANQAECgUICQAAAA==.',
Ya='Yacob:BAABNQAECn8lAAMhAAkKihr1KAAnAgAhAAkKihr1KAAnAgAYAAMKTw+QXACTAAAAAA==.Yarlyn:BAAANQAECgEIAQABNQAECgQICgAFAAAAAA==.',
Ye='Yenneferr:BAABNQAECn8dAAIeAAoKTwypMAC8AQAeAAoKTwypMAC8AQAAAA==.',
Yh='Yhwach:BAABNQAECn8UAAIEAAoK0A2THQCkAQAEAAoK0A2THQCkAQAAAA==.',
Ym='Ymir:BAABNQAECn8eAAISAAkKiBl3YgBzAgASAAkKiBl3YgBzAgABNQAECgEIAQAFAAAAAA==.',
Yo='Yosaf:BAABNQAECn8hAAISAAgKkhz+UgC9AQASAAgKkhz+UgC9AQAAAA==.',
Yu='Yuie:BAAANQAECgQIBwABNQAECgcIFAAGALwGAA==.Yukitaiga:BAAANQADCggIDAABNQABCgQIBQAFAAAAAA==.',
Za='Zaft:BAABNQAECn87AAMSAAoKIxEETADTAQASAAoKKBAETADTAQARAAIKPBeHWgByAAAAAA==.Zaha:BAABNQAECn8UAAIMAAgKDyBJhwBwAgAMAAgKDyBJhwBwAgAAAA==.Zappsz:BAAANQADCggIGQAAAA==.Zardoc:BAAANQADCgIIAgAAAA==.',
Ze='Zedfrey:BAABNQAECn8WAAISAAcKMAmj7QBBAQASAAcKMAmj7QBBAQAAAA==.Zem:BAABNQAECn8jAAMOAAkKYRYVUQCQAQAOAAkKYRYVUQCQAQAPAAIK4AkMJgB9AAAAAA==.Zemangoose:BAAANQAECgEIAQAAAA==.Zennish:BAAANQADCgUIDQAAAA==.Zeplen:BAABNQAECn8tAAIDAAoKBBb2RQBOAgADAAoKBBb2RQBOAgAAAA==.Zeroultra:BAABNQAECn8eAAIPAAcKmxesDgDDAQAPAAcKmxesDgDDAQAAAA==.Zeräse:BAAANQAECgIIAgABNQAECgoKNQADAOEbAA==.Zeusmos:BAABNQAECn8gAAIdAAkKViA4CgAuAwAdAAkKViA4CgAuAwAAAA==.',
Zi='Zithenex:BAAANQAECgQICwAAAA==.',
Zu='Zugleesh:BAAANQAFFAEIAgAAAA==.',
Zw='Zwar:BAAANQAECgEIAQAAAA==.',
['Ál']='Álister:BAAANQAECgQICwAAAA==.',
['Æó']='Æón:BAAANQAECgIIAgAAAA==.',
['Ér']='Éragon:BAAANQABCgIIAgAAAA==.',
['ßo']='ßoru:BAAANQAECgMIBQABNQAECgUICgAFAAAAAA==.',
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
