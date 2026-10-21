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

local lookup = {'Rogue-Outlaw','Paladin-Holy','DeathKnight-Blood','Unknown-Unknown','DemonHunter-Havoc','DemonHunter-Vengeance','Shaman-Restoration','Hunter-BeastMastery','Warlock-Destruction','Mage-Arcane','Warlock-Demonology','Warrior-Arms','Warrior-Fury','Warrior-Protection','Paladin-Protection','Paladin-Retribution','Mage-Frost','DeathKnight-Unholy','DeathKnight-Frost','Shaman-Elemental','Hunter-Marksmanship','Priest-Shadow','Shaman-Enhancement','Druid-Balance','Warlock-Affliction','Priest-Discipline','Druid-Guardian','Monk-Brewmaster','Monk-Windwalker','DemonHunter-Devourer','Monk-Mistweaver','Rogue-Assassination','Priest-Holy','Druid-Restoration','Hunter-Survival','Druid-Feral','Evoker-Augmentation','Evoker-Devastation','Rogue-Subtlety','Evoker-Preservation',}
local provider = {region='US',realm='Zangarmarsh',name='US',type='weekly',zone=53,date='2026-10-20',data={Aa='Aafra:BAAANQADCgcIBwAAAA==.Aaminae:BAABNQAECn8pAAIBAAkKiRimBgBeAgABAAkKiRimBgBeAgAAAA==.',
Ab='Abracadaver:BAAANQAECgEIAQAAAA==.Abracastabya:BAAANQADCgQIBAABNQAECggIGgACAP0dAA==.Abysstral:BAAANQABCgYIBgAAAA==.',
Ae='Aedar:BAABNQAECn83AAIDAAkKQB2lIACvAgADAAkKQB2lIACvAgAAAA==.Aegon:BAAANQABCgMIAwAAAA==.Aenledron:BAAANQAECgEIAQABNQAECggIDQAEAAAAAA==.Aeturnas:BAABNQAECn8xAAICAAoKBh0yDgBYAwACAAoKBh0yDgBYAwAAAA==.',
Af='Afukeenba:BAAANQAECgIIAgAAAA==.',
Ai='Aire:BAABNQAECn8UAAMFAAcKvAbqXwD+AAAFAAcK+wXqXwD+AAAGAAQKigX/JgCBAAAAAA==.',
Al='Alanima:BAAANQAECgUIBgAAAA==.Alauradona:BAAANQADCgUIBwAAAA==.Aliana:BAAANQAECgUICQABNQAECgkJJgAHAFwbAA==.Alittlegeeky:BAAANQADCgIJAgABNQAECgcIFAAIALscAA==.Allesta:BAAANQADCgYICQAAAA==.Allypally:BAAANQADCggIDwAAAA==.Aloriz:BAAANQADCgMIAwAAAA==.Alphamage:BAAANQAECgYIBwAAAA==.Alphamonk:BAAANQADCgEIAQABNQADCgYIBgAEAAAAAA==.Alphawarrior:BAAANQADCgYIBgAAAA==.Alros:BAABNQAECn8yAAIIAAoKKxr7BACDAgAIAAoKKxr7BACDAgAAAA==.',
An='Andralynn:BAAANQAECgQIAwAAAA==.',
Ao='Aoiryo:BAAANQADCgIIAgABNQABCgQIBQAEAAAAAA==.',
Aq='Aquilas:BAAANQAECgYIBgAAAA==.',
Ar='Arcstream:BAAANQAECgYICgAAAA==.Arctica:BAAANQAECgIIAwAAAA==.Arete:BAAANQADCggIEAAAAA==.Arette:BAAANQADCgMIAwAAAA==.Arkshade:BAAANQAECgQIDgAAAA==.',
As='Asmo:BAAANQADCgEIAQAAAA==.Astarii:BAAANQAECggIAgAAAA==.Asterica:BAABNQAECn8tAAIJAAoK+xZWBgCoAgAJAAoK+xZWBgCoAgAAAA==.',
At='Atåvvi:BAAANQADCgQIBAAAAA==.',
Av='Averynicole:BAAANQADCgIIAgAAAA==.',
Aw='Awasjr:BAABNQAECn8oAAIIAAkKoRMQaABEAgAIAAkKoRMQaABEAgAAAA==.',
Ay='Ayano:BAABNQAECn84AAIKAAoKCiJSGABzAwAKAAoKCiJSGABzAwAAAA==.Ayulur:BAAANQAECgEIAwAAAA==.',
Az='Azraél:BAAANQADCggIBwAAAA==.Azurefalls:BAABNQAECn8sAAIDAAoKRyFkCwBYAwADAAoKRyFkCwBYAwAAAA==.',
Ba='Badfiremage:BAABNQAECn8nAAMLAAoKURq/RgB+AgALAAoKURq/RgB+AgAJAAEKVwLGhgAhAAAAAA==.Balthïer:BAABNQAECn8sAAICAAgKfhyqDAD9AQACAAgKfhyqDAD9AQAAAA==.Bark:BAABNQAECn8tAAQMAAoK1B6iGABWAwAMAAoK1B6iGABWAwANAAUK0hvAEwBkAQAOAAEKtRvJGwBZAAAAAA==.',
Be='Bearshock:BAAANQAECgEIAQAAAA==.Beatriixx:BAAANQADCgEIAQAAAA==.Bee:BAABNQAECn8iAAMPAAkKpST7AwB8AwAPAAgKeyb7AwB8AwAQAAUK3hJAogCaAAABNQAECgoKNwADAOkkAA==.Beeb:BAAANQAECgYIEgABNQAECgoKNwADAOkkAA==.Beefisting:BAAANQADCgIIAgABNQAECgoKNwADAOkkAA==.Beezz:BAABNQAECn83AAIDAAoK6SSSAwC4AwADAAoK6SSSAwC4AwAAAA==.Belardor:BAAANQAECggICAAAAA==.Beliara:BAAANQAECgQIAwAAAA==.Bendovar:BAAANQADCgEIAQAAAA==.',
Bi='Bilithi:BAAANQAECgEIAQAAAA==.Bionarra:BAABNQAECn8uAAMRAAoKNhy3BADZAgARAAoKNhy3BADZAgAKAAEKAACy4wEhAAAAAA==.Bishopwr:BAABNQAECn8cAAMMAAgKJQ85oADMAQAMAAgKJQ85oADMAQAOAAUKvgFRNgCAAAAAAA==.',
Bl='Blaire:BAAANQADCgQIBAAAAA==.',
Bo='Bobdobbs:BAAANQADCgYIBwAAAA==.Bohica:BAAANQAECgYIBwAAAA==.',
Br='Branch:BAAANQADCgYIBgABNQAECgkJJAADAJcTAA==.Brem:BAABNQAECn8yAAIKAAoK0BvqXADGAgAKAAoK0BvqXADGAgAAAA==.Briara:BAAANQAECgQIBAAAAA==.Broknüs:BAAANQAECgMIBAAAAA==.Broníx:BAAANQAECgQICQAAAA==.Bropeep:BAABNQAECn8mAAMSAAcKjyK7IQDAAgASAAcKjyK7IQDAAgATAAIKnQnhmQBgAAAAAA==.',
Bu='Bullshott:BAAANQAECgMIBAAAAA==.Burritobolts:BAAANQADCggICAAAAA==.',
By='Bylun:BAAANQADCggICwAAAA==.',
Ca='Callaghar:BAAANQADCgQIBAABNQAECgYIEQAEAAAAAA==.Calyen:BAAANQAECgMIAwABNQAECgMIAwAEAAAAAA==.Carartha:BAABNQAECn8cAAIQAAcKAAimcQDjAAAQAAcKAAimcQDjAAAAAA==.Carnitine:BAAANQADCgYIBgABNQAECgoKJwALAFEaAA==.Carrots:BAAANQAECgQICgAAAA==.Cashmoolah:BAABNQAECn8uAAMQAAoKUA4hLAB7AQAQAAoKUA4hLAB7AQAPAAIKzgEWPQAlAAAAAA==.Catfight:BAAANQAECgQIBwAAAA==.',
Ch='Chadilton:BAAANQADCgYIDwAAAA==.Chadsmon:BAACNQAFFH8OAAMUAAYK9BCFDwB2AQAUAAUKLA2FDwB2AQAHAAEKHAFoGQA7AAA1AAQKfz0AAhQACgqKG8oEAC8CABQACgqKG8oEAC8CAAAA.Change:BAAANQAECgQIBAAAAA==.Charcoal:BAABNQAECn81AAMJAAoKYhYhCQBoAgAJAAkKtRMhCQBoAgALAAgKQRUAIgBmAQAAAA==.Chasebakes:BAABNQAECn80AAMVAAoKOx4JBQCiAQAVAAkKgR0JBQCiAQAIAAMKcBpDKgGdAAAAAA==.Cheesecake:BAAANQAECgQIDQAAAA==.Choks:BAAANQAECgQIBgAAAA==.Chumbawamba:BAAANQADCgYJBgAAAA==.Chéfboyrlee:BAABNQAECn8aAAIWAAkKEB16AgAXAgAWAAkKEB16AgAXAgABNQAFFAYIGAAXALscAA==.',
Ci='Cindiyoohoo:BAABNQAECn8pAAIYAAkKxxk6KQCNAgAYAAkKxxk6KQCNAgAAAA==.Cizmac:BAAANQADCgcICwAAAA==.',
Cl='Clada:BAAANQADCgUIBQAAAA==.Claus:BAAANQADCggICAABNQAECgkJHgAPABoMAA==.',
Cm='Cmdrshepard:BAAANQADCgEIAQABNQAECgcIFwAJAM8MAA==.',
Co='Corruptdata:BAAANQADCgMIBgAAAA==.Cownado:BAAANQAECgMIAwAAAA==.',
Cr='Crawlerkarl:BAAANQADCgIIAgAAAA==.',
Ct='Ctrlaltchill:BAAANQADCgQIBAAAAA==.',
Cu='Cursedspirit:BAAANQADCgMIAwAAAA==.Custard:BAAANQAECgMIAwAAAA==.Cut:BAAANQADCgYIEQABNQAECgcIFAAFALwGAA==.',
Cy='Cyfelen:BAABNQAECn8zAAQJAAgKhB+9AADhAQALAAgKWRzSRACEAgAJAAgKthy9AADhAQAZAAIKsB28HQCOAAAAAA==.Cynleel:BAAANQAECgYIBwABNQAECgcIGQAaAC4SAA==.Cyris:BAAANQAECgIIAQAAAA==.',
Da='Dahrena:BAAANQAECgYICwAAAA==.Darthmall:BAAANQAECgUIDQABNQAFFAIIAgAEAAAAAA==.Dawntyrant:BAAANQADCgIIAwAAAA==.',
De='Demidru:BAABNQAECn8aAAIbAAkKeBxREwAuAgAbAAkKeBxREwAuAgAAAA==.Derat:BAAANQADCggICAAAAA==.Deucalion:BAAANQADCgcICQAAAA==.Deveruxx:BAAANQADCgEIAQAAAA==.',
Di='Dibbydab:BAAANQAECgcIEAAAAA==.',
Dj='Django:BAABNQAECn8eAAIYAAkKkRbvJgCcAgAYAAkKkRbvJgCcAgAAAA==.Djehrtey:BAAANQAECgMIBQAAAA==.Djinni:BAABNQAECn8kAAMcAAkKmh1rBgDnAgAcAAkKmh1rBgDnAgAdAAMKJg9tVQCXAAABNQAFFAIIAgAEAAAAAA==.Djwiltumble:BAAANQADCgUIBQAAAA==.',
Dk='Dkota:BAAANQADCgYIEQAAAA==.',
Do='Doodle:BAABNQAECn8cAAITAAcKlBk4QQDBAQATAAcKlBk4QQDBAQAAAA==.',
Dr='Dracnahr:BAAANQAECgcIEQAAAA==.Drenleah:BAAANQAECgYIDwABNQAECgkJHQAeALgUAA==.Drenlee:BAAANQAECgIIAgABNQAECgkJHQAeALgUAA==.',
Du='Dumblegear:BAABNQAECn8aAAIKAAgKeBryfQCCAgAKAAgKeBryfQCCAgAAAA==.Duramei:BAAANQADCgMIAwAAAA==.Durian:BAABNQAECn8mAAIHAAkKXBt5EgDCAQAHAAkKXBt5EgDCAQAAAA==.',
Dw='Dwagon:BAAANQADCgYJBgABNQAECgoKKAAHACkRAA==.',
Dy='Dysdayne:BAAANQAECgIIAwABNQAECgQIBAAEAAAAAA==.',
['Dë']='Dëathx:BAAANQADCgcIBwABNQAECgcIFQANAJsXAA==.',
Ed='Edinna:BAABNQAECn8nAAIKAAoKqwiKFADEAQAKAAoKqwiKFADEAQAAAA==.',
Ei='Eileamaid:BAAANQADCgYIEQAAAA==.',
El='Elessedil:BAAANQAECgYIBgAAAA==.Ellemystic:BAAANQADCgcIHQAAAA==.Elpally:BAAANQADCgMIAwAAAA==.Elspeth:BAAANQADCggICAABNQAECgYIEQAEAAAAAA==.Elyriana:BAAANQAECgcIDwAAAA==.',
Em='Emila:BAEANQAECgcIBwABNQAECgoKIwAIADUgAA==.Emirozu:BAAANQADCgUIBQAAAA==.Emma:BAAANQABCgQIBgAAAA==.Emokilla:BAAANQAECgQIBQAAAA==.Emriq:BAAANQAECgMIBAAAAA==.',
En='Enrique:BAABNQAECn9JAAMQAAoKKCJXIwA3AwAQAAoKKCJXIwA3AwAPAAEK0xP1agA8AAAAAA==.',
Ep='Epedemik:BAAANQAECgEIAQAAAA==.',
Er='Erazath:BAAANQAECgMIAwABNQAECgkJJAADAJcTAA==.Erussh:BAAANQADCgQIBQAAAA==.',
Es='Estanna:BAAANQAECggIBgAAAA==.',
Ev='Evöö:BAAANQAECgYIBgAAAA==.',
Ex='Exhul:BAAANQAECgQIBAAAAA==.',
Fa='Faeng:BAAANQAFFAIIAgAAAA==.Faewing:BAAANQAECgEIAQAAAA==.Falar:BAAANQAECgcIDQAAAA==.Faubito:BAAANQAECgYIBgAAAA==.',
Fe='Fearlesfreep:BAABNQAECn8sAAIIAAkK1g7MewAXAgAIAAkK1g7MewAXAgAAAA==.Febz:BAAANQAECgUICAAAAA==.Felatonin:BAABNQAECn8ZAAIeAAgK6B+8GgCCAgAeAAgK6B+8GgCCAgAAAA==.Felfüry:BAABNQAECn8yAAMGAAkKLg8qCQDYAAAFAAkK0A21NwDzAQAGAAgKMw0qCQDYAAAAAA==.Fenixshaw:BAAANQADCgYIFQAAAA==.Festyr:BAAANQADCgQIBAAAAA==.Feyd:BAAANQADCgYIBgAAAA==.',
Fi='Finella:BAAANQAECgEIAQAAAA==.Finneas:BAABNQAECn8XAAMVAAcKNBCpUQDjAAAVAAQKZw+pUQDjAAAIAAQK1Q9OgwCmAAAAAA==.',
Fo='Foggpy:BAABNQAECn8pAAIZAAkK9B44AQBWAwAZAAkK9B44AQBWAwAAAA==.',
Fr='Freinkenbaby:BAAANQADCgEIAQAAAA==.Frostey:BAAANQAECgUIDAAAAA==.Fröstmöurne:BAABNQAECn8kAAIDAAkK+gkoGwAXAQADAAkK+gkoGwAXAQAAAA==.',
Fu='Furbetime:BAAANQADCgMIAwAAAA==.',
Ga='Gabrièllè:BAAANQADCgcIBwAAAA==.Galaythien:BAAANQADCggIGgAAAA==.',
Ge='Geluria:BAAANQAECgQICgABNQAECgcIGgALAHUdAA==.Genghiskhan:BAABNQAECn8sAAISAAkKxRrAKgCLAgASAAkKxRrAKgCLAgAAAA==.Geren:BAAANQAECggIDwAAAA==.Geret:BAABNQAECn8pAAIQAAgKhRPsjgAHAgAQAAgKhRPsjgAHAgAAAA==.',
Gh='Ghanaria:BAAANQADCgQJBAAAAA==.',
Gi='Gingervex:BAAANQADCggIEAAAAA==.Gissmo:BAAANQADCgYICwAAAA==.',
Gl='Glitchy:BAABNQAECn8xAAIYAAgK7RXHCACrAQAYAAgK7RXHCACrAQAAAA==.Gloppy:BAAANQADCgcIBwAAAA==.',
Go='Gogmagog:BAAANQADCgEIAQAAAA==.Goingtogetu:BAABNQAECn8xAAIPAAgKkR5uBQCsAQAPAAgKkR5uBQCsAQAAAA==.Goldfarmr:BAAANQAECggIDAABNQAECgoKMwAKAM0cAA==.Goldglazeher:BAABNQAECn8zAAIKAAoKzRw9DQACAgAKAAoKzRw9DQACAgAAAA==.Goldrawr:BAAANQAECgYIBgABNQAECgoKMwAKAM0cAA==.Golgotha:BAAANQABCgcICQAAAA==.',
Gr='Graddy:BAAANQADCgQIBAAAAA==.Gradhrek:BAAANQABCgIIAwAAAA==.Greeley:BAABNQAECn8aAAIVAAgKEhq1JQAfAgAVAAgKEhq1JQAfAgAAAA==.Greganir:BAABNQAECn8YAAMRAAgKdxroGwARAQAKAAgKaxaGrQAnAgARAAQKOhroGwARAQABNQAECgcIGAADAL4bAA==.Gregdapro:BAABNQAECn8YAAIDAAcKvhsPEgBRAQADAAcKvhsPEgBRAQAAAA==.Grimshady:BAAANQAECgIIAgAAAA==.Gritty:BAAANQABCgMIAwAAAA==.',
Gu='Gunnyal:BAAANQAECgQIBwAAAA==.',
Gy='Gyathew:BAABNQAECn8nAAIUAAkKRyBWEwBXAwAUAAkKRyBWEwBXAwAAAA==.',
Ha='Hagunn:BAABNQAECn8ZAAMMAAkKPxdPgwATAgAMAAkKxxRPgwATAgANAAMK9Ru6GgD6AAAAAA==.',
He='Heladaa:BAAANQADCgMIAwAAAA==.Hervöralvit:BAAANQADCgIIAgAAAA==.Hevy:BAABNQAECn8dAAIeAAkKuBRZBQC+AQAeAAkKuBRZBQC+AQAAAA==.',
Hi='Hidensneak:BAAANQADCggICAAAAA==.Hildzap:BAAANQADCgYICwAAAA==.',
Ho='Holygriff:BAAANQAECgIIAgAAAA==.Holyshots:BAABNQAECn8zAAIQAAgKDhRDLAB6AQAQAAgKDhRDLAB6AQAAAA==.Howlinnbrews:BAAANQADCggICgAAAA==.',
Hu='Huyu:BAAANQADCgUIAQAAAA==.',
Id='Idrizzt:BAAANQABCgMIAwAAAA==.',
Ig='Ignore:BAAANQAECggICgABNQAECgoKJwALAFEaAA==.',
Io='Iobo:BAAANQAECgQIBwAAAA==.',
Ir='Ironhidez:BAABNQAECn8oAAIQAAgKDApAZAD9AAAQAAgKDApAZAD9AAAAAA==.',
Is='Isaarek:BAAANQAECgEIAQAAAA==.Ishiza:BAAANQABCgIIAgAAAA==.',
It='Itsatrap:BAAANQAECgUIEwABNQAECgkJJgAHAFwbAA==.',
Iz='Izerol:BAABNQAECn8/AAIdAAoKYSSRAAAaAwAdAAoKYSSRAAAaAwAAAA==.',
Ja='Jasmini:BAAANQADCgQIBAAAAA==.Jaylea:BAAANQABCgUICAAAAA==.',
Je='Jeb:BAAANQABCgUIBQABNQAECggIGgACAP0dAA==.Jebopally:BAABNQAECn8aAAMCAAgK/R2dPAByAgACAAcKiB6dPAByAgAQAAcKnhk/qADPAQAAAA==.Jeouleous:BAAANQADCgcIBwAAAA==.Jetblack:BAABNQAECn8dAAILAAcKfxlGfwDoAQALAAcKfxlGfwDoAQAAAA==.',
Ji='Jiblows:BAAANQADCgYIBgAAAA==.Jibolls:BAAANQAECgUICwAAAA==.',
Jo='Joehex:BAABNQAECn8oAAIOAAkKgiBaBwDmAgAOAAkKgiBaBwDmAgAAAA==.Jointjester:BAAANQADCggICAAAAA==.Joulez:BAAANQADCgYICwAAAA==.',
Ju='Judgematt:BAAANQADCggIDAAAAA==.Judgemental:BAAANQADCgQIBAAAAA==.Justin:BAAANQAECgcIDgAAAA==.',
Ka='Kaidoe:BAAANQAECgYIBwAAAA==.Kaleesh:BAACNQAFFH8PAAIXAAUKbCKGAQD/AQAXAAUKbCKGAQD/AQA1AAQKfyYAAhcACgqDJfoBAJMDABcACgqDJfoBAJMDAAAA.Kallux:BAABNQAECn8wAAIDAAoKyBsIAgCeAgADAAoKyBsIAgCeAgAAAA==.Kalma:BAABNQAECn8nAAIDAAkKORyyBQDqAQADAAkKORyyBQDqAQAAAA==.Kananga:BAAANQAECgQIBwAAAA==.Kasca:BAABNQAECn8VAAIYAAcKQAjsdQDzAAAYAAcKQAjsdQDzAAAAAA==.Kato:BAAANQAECgQIBAABNQAECgkJIAAXAOQXAA==.Kazeem:BAAANQAECgcICwAAAA==.',
Ke='Kerah:BAAANQADCggICAABNQAECgkJJgAHAFwbAA==.',
Kh='Khadran:BAAANQADCgIIAwAAAA==.Khalyraa:BAAANQAECgUICQAAAA==.',
Ki='Kiermac:BAAANQAECggICAAAAA==.Kindred:BAAANQADCgQIBAAAAA==.Kiragrande:BAABNQAECn8qAAIfAAoKvhGuBwBkAQAfAAoKvhGuBwBkAQAAAA==.Kiriku:BAAANQAECgUICwAAAA==.Kithane:BAAANQADCgMIBgAAAA==.',
Kl='Klorto:BAAANQADCgEIAQAAAA==.',
Ko='Korbinf:BAAANQAECgUIBQAAAA==.Kotok:BAAANQAECgQICgAAAA==.',
Kr='Krelein:BAAANQAECgQIDgAAAA==.',
Ku='Kurth:BAAANQADCgUICAAAAA==.',
Ky='Kyu:BAAANQADCgcIDQAAAA==.',
La='Lancaster:BAAANQADCgIIAgAAAA==.',
Le='Lee:BAABNQAECn8ZAAIdAAcK4yIZGACIAgAdAAcK4yIZGACIAgAAAA==.Leenaashala:BAAANQAECgQICQABNQAECgkJIAAXAOQXAA==.Levin:BAAANQAECgIIAwAAAA==.',
Li='Linissa:BAAANQAECgMJBgABNQAFFAIIAgAEAAAAAA==.',
Ll='Llght:BAAANQAECgQICQAAAA==.',
Lo='Logankord:BAABNQAECn8pAAINAAkKHx8NBQDaAgANAAkKHx8NBQDaAgAAAA==.Lokeira:BAABNQAECn8oAAIHAAoKKRFqXQD3AQAHAAoKKRFqXQD3AQAAAA==.Loonnah:BAAANQADCgQIBQAAAA==.',
Lu='Luuniren:BAAANQADCggIIwABNQAECgQIBAAEAAAAAA==.Luvbug:BAABNQAECn8UAAIIAAcKuxzRagA+AgAIAAcKuxzRagA+AgAAAA==.',
Ly='Lyais:BAAANQAECgQIBQAAAA==.Lyara:BAABNQAECn8nAAMHAAoKhR7nKwCzAgAHAAoKhR7nKwCzAgAUAAYKbxMfkAB8AQAAAA==.Lythos:BAABNQAECn8kAAIDAAkKlxN9IAD6AAADAAkKlxN9IAD6AAAAAA==.',
['Lø']='Lørdøfßud:BAABNQAECn8rAAMOAAgKhCG/BQASAwAOAAgKhCG/BQASAwAMAAEKAAANUAE2AAAAAA==.',
Ma='Machomans:BAAANQAECgQIBQABNQAECgcIEAAEAAAAAA==.Magdann:BAAANQABCgIJAgAAAA==.Mahasamatman:BAAANQAECgEIAQAAAA==.Makimá:BAAANQADCgYIBgABNQAECgkJGwAVABsUAA==.Mandragora:BAAANQADCgIIAgAAAA==.Mankilla:BAAANQADCgMIAwAAAA==.Mansa:BAABNQAECn8zAAIgAAoKMw2iDgBPAQAgAAoKMw2iDgBPAQAAAA==.Mastamojo:BAABNQAECn8fAAICAAgKwgdiiwB6AQACAAgKwgdiiwB6AQAAAA==.Mattheals:BAABNQAECn8fAAIhAAoK1RbSBQCeAgAhAAoK1RbSBQCeAgAAAA==.',
Mc='Mcmurphy:BAAANQADCgYIBgAAAA==.',
Me='Meanieman:BAAANQABCggIDAAAAA==.Meissen:BAABNQAECn8XAAIJAAcKzwzPBADeAAAJAAcKzwzPBADeAAAAAA==.Melendaren:BAAANQADCgcIEwAAAA==.Meltara:BAAANQADCgQIBAAAAA==.Messìah:BAABNQAECn8bAAIYAAYKMg+WJQDPAAAYAAYKMg+WJQDPAAAAAA==.Metamonster:BAAANQAECgUIBgAAAA==.',
Mi='Mickie:BAAANQAECgYIEQAAAA==.Miniav:BAAANQADCgcIHQAAAA==.Mirko:BAAANQADCgYJCQABNQAECgcIEAAEAAAAAA==.',
Ml='Mladjo:BAAANQAECgMIBgAAAA==.',
Mo='Mockery:BAABNQAECn80AAIKAAoK8gvLFADCAQAKAAoK8gvLFADCAQAAAA==.Mokokniki:BAABNQAECn8kAAIiAAgKIhGILQCvAQAiAAgKIhGILQCvAQAAAA==.Moneie:BAAANQADCgEIAQAAAA==.Monger:BAAANQADCgEIAQAAAA==.Moog:BAAANQADCgQIBAAAAA==.Moondo:BAAANQADCgQIBAAAAA==.Moothyr:BAAANQAECgYIDQAAAA==.Morticiá:BAAANQAECgIIAgAAAA==.Mourningstar:BAACNQAFFH8KAAISAAUK0R2MBQDLAQASAAUK0R2MBQDLAQA1AAQKfyAAAxIACQqAI+EUABIDABIACAqAI+EUABIDAAMABQqBHbdiAGcBAAE1AAUUBQgPAAMA2x0A.Mozaic:BAABNQAECn8vAAIOAAoKGh+lAQArAgAOAAoKGh+lAQArAgAAAA==.',
My='Myselia:BAAANQADCgYICAAAAA==.',
Na='Nad:BAAANQAECgQIBAAAAA==.Naec:BAAANQADCgEIAQABNQADCgYIGQAEAAAAAA==.Naek:BAAANQADCgYIGQAAAA==.Nalthis:BAAANQAECggICQAAAA==.',
Ne='Necromus:BAAANQAECgQIBgAAAA==.Nekra:BAAANQAECgQICwAAAA==.',
Ni='Nibbi:BAAANQADCgYJBgAAAA==.Nicehair:BAAANQAECgcICwAAAA==.',
No='Nocturnum:BAABNQAECn8uAAIeAAkKqCLSBwBUAwAeAAkKqCLSBwBUAwAAAA==.',
Nu='Numb:BAAANQADCgEIAQAAAA==.',
Ny='Nyctea:BAAANQADCgQIBAAAAA==.Nyria:BAAANQADCgEIAQAAAA==.',
Oh='Oha:BAAANQAECgQIAwAAAA==.',
Ol='Oldmongerpal:BAAANQADCggICgAAAA==.Oltiyet:BAAANQAECgQIBAAAAA==.',
On='Onepuffman:BAACNQAFFH8YAAIXAAYKuxzxAAA9AgAXAAYKuxzxAAA9AgA1AAQKfy4AAhcACgpPIz8CACMCABcACgpPIz8CACMCAAAA.Onetwocowpow:BAABNQAECn8zAAIfAAgKGxGmCQA9AQAfAAgKGxGmCQA9AQAAAA==.',
Or='Ordanith:BAABNQAECn8sAAIQAAoKvR6tIgA5AwAQAAoKvR6tIgA5AwAAAA==.Orionn:BAACNQAFFH8XAAIIAAUKmSBNBgDsAQAIAAUKmSBNBgDsAQA1AAQKfz8AAggACgoEJo8DAM4DAAgACgoEJo8DAM4DAAAA.',
Os='Osø:BAAANQAECgUIDwAAAA==.',
Ov='Oven:BAABNQAECn8xAAQfAAoKwhVJFQAnAgAfAAgKfhZJFQAnAgAdAAkK/A84CQB8AQAcAAEKDw4qMQA1AAAAAA==.',
Ow='Owlette:BAAANQADCgYIBgAAAA==.Owlxero:BAAANQADCggIDwAAAA==.',
Pa='Patelz:BAAANQADCgYIBgAAAA==.',
Pe='Pelma:BAAANQADCgIIAgABNQAECgQICgAEAAAAAA==.',
Ph='Phyras:BAAANQABCgcIBwAAAA==.',
Pi='Pinesoul:BAAANQADCgQIBAAAAA==.Pippins:BAAANQADCgEIAQAAAA==.',
Po='Polytotems:BAAANQAECgYIDgAAAA==.',
Pr='Praystation:BAAANQAECgEIAQABNQAECgYIDQAEAAAAAA==.',
Ps='Psygon:BAAANQADCgYIBgAAAA==.',
Qu='Quora:BAAANQABCggIEgAAAA==.',
Ra='Raelone:BAABNQAECn8lAAMJAAcKlhn4BADbAAAZAAMKGRQ1FgDnAAAJAAUK9Rr4BADbAAAAAA==.Rageofmommy:BAAANQADCgIIAwAAAA==.Raidoe:BAAANQAECgYIEAAAAA==.Raknslash:BAAANQADCgYIBgAAAA==.Rameumptom:BAAANQADCgYIDAAAAA==.Randers:BAAANQADCgMIAwAAAA==.Rangérz:BAABNQAECn8rAAIIAAgK0RhmSgCOAgAIAAgK0RhmSgCOAgAAAA==.Ranoa:BAABNQAECn8UAAIPAAgKqxBzKwCBAQAPAAgKqxBzKwCBAQABNQAECgoKMQAbAN0eAA==.Rant:BAAANQAECgUICwAAAA==.Ravencraw:BAAANQADCgYJCgAAAA==.Ravid:BAAANQADCgEIAQAAAA==.',
Re='Rebirth:BAAANQADCgUIBQAAAA==.Redxrum:BAAANQAECgIIAgAAAA==.Regress:BAAANQAECgQICQAAAA==.Reo:BAAANQADCgQIBAAAAA==.Reàper:BAAANQADCgUIBQAAAA==.',
Rh='Rheavin:BAAANQABCgQIBQAAAA==.Rhell:BAABNQAECn8bAAICAAgKRSDoIwDbAgACAAgKRSDoIwDbAgAAAA==.Rhellen:BAABNQAECn8jAAIhAAoKEB9EAgBMAwAhAAoKEB9EAgBMAwABNQAECggIGwACAEUgAA==.',
Ri='Rinche:BAABNQAECn8VAAMUAAcK+wfYogBQAQAUAAcK+wfYogBQAQAHAAMKOgcx+AB6AAAAAA==.Rintche:BAAANQADCgUIBQAAAA==.',
Ro='Rolland:BAABNQAECn8WAAIVAAgK8hY0JAAsAgAVAAgK8hY0JAAsAgAAAA==.Rootbeamxo:BAAANQAECgQJBAAAAA==.Rosefyre:BAABNQAECn8iAAILAAoKgw84bAAZAgALAAoKgw84bAAZAgAAAA==.',
Ru='Rudo:BAABNQAECn8bAAQVAAkKGxSVOACLAQAIAAcKKRYXrQCqAQAVAAgKWwqVOACLAQAjAAMK6wdtDwCXAAAAAA==.Rumproblem:BAABNQAECn8YAAQaAAkKTA7CDwAuAQAhAAgKHgsvigB3AQAaAAYKMg7CDwAuAQAWAAYK3ws1RQAOAQAAAA==.Ruri:BAAANQAECgMIBAABNQAECgkJGwAVABsUAA==.',
Ry='Ryegar:BAAANQADCgUJBQABNQAECgkJJAAkAO8YAA==.Ryeger:BAABNQAECn8kAAMkAAkK7xinDABYAgAkAAkK7xinDABYAgAYAAUK0gVmfgDTAAAAAA==.Ryuaoi:BAAANQAECgEIAwABNQABCgQIBQAEAAAAAA==.',
['Ró']='Róótbear:BAAANQAECgUICgAAAA==.',
Sa='Safety:BAAANQAECgQICQAAAA==.Salaine:BAAANQADCgcIEAAAAA==.Salfros:BAAANQADCgUIBQAAAA==.Samovar:BAABNQAECn8oAAMQAAoKdg5iGADCAQAQAAoKdg5iGADCAQACAAYKywWowAD7AAAAAA==.Sandbones:BAAANQAECgQIBAABNQAECgoKNAAKAPILAA==.Sandwiches:BAAANQAECggIEQAAAA==.Sanielan:BAAANQADCgMIAwAAAA==.',
Sc='Scalebagz:BAABNQAECn8rAAMlAAoKDxjZBQB8AgAlAAoKDxjZBQB8AgAmAAUKPhjNBQArAQAAAA==.Schism:BAAANQAFFAEIAgAAAA==.',
Se='Sentren:BAAANQAECgIIAgAAAA==.Setresh:BAABNQAECn8tAAIjAAoK3RKwBACRAgAjAAoK3RKwBACRAgAAAA==.',
Sh='Shaken:BAAANQADCgMIAwAAAA==.Shamwowhex:BAAANQAECgYICQAAAA==.Shangöh:BAAANQADCgUICQABNQAECggILAACAH4cAA==.Sharatira:BAAANQADCgYIDAAAAA==.Shivver:BAAANQADCgQIBAAAAA==.Shivyn:BAABNQAECn8vAAIHAAgKlxIXJABUAQAHAAgKlxIXJABUAQAAAA==.',
Si='Sibadeekay:BAABNQAECn8xAAMSAAoKPRwuLgB5AgASAAoKDRsuLgB5AgADAAUKHCH+UACxAQAAAA==.Sickkid:BAABNQAECn8dAAMNAAgKIQ3tBABeAQAMAAcKxwlhwwB0AQANAAcKKwztBABeAQAAAA==.Silvertier:BAAANQADCgMIAwAAAA==.Silverwulf:BAAANQADCgUIBwAAAA==.Sin:BAAANQAECgUICgAAAA==.Sindrya:BAAANQAECgQIBwAAAA==.',
Sk='Skunkt:BAAANQADCgMIAwAAAA==.',
Sm='Smoothvelvet:BAABNQAECn8gAAIXAAkK5BfXEgA8AgAXAAkK5BfXEgA8AgAAAA==.',
Sn='Snuggles:BAAANQADCgcIBwABNQAECgoKKwAjAJ4YAA==.',
So='Solára:BAABNQAECn8cAAMGAAgKgRALHQDuAAAeAAcKUgsnPQBfAQAGAAQK4RALHQDuAAAAAA==.',
Sp='Spellforge:BAAANQAECgMIAwAAAA==.Spinach:BAAANQAECgQIBAAAAA==.Sprath:BAAANQAECgQIBwAAAA==.',
St='Staretra:BAABNQAECn8zAAMWAAgKew06NgByAQAWAAcKBgk6NgByAQAhAAgKjQJePQARAQAAAA==.Sterarcher:BAAANQADCgIIAgAAAA==.',
Su='Sumar:BAAANQABCgEIAQAAAA==.Summersky:BAAANQAECgEIAQAAAA==.Sungjinwoo:BAAANQAECgEIAQAAAA==.Superdestror:BAAANQABCgcICgAAAA==.',
Ta='Taadra:BAABNQAECn8vAAIHAAoK7hKlDgDnAQAHAAoK7hKlDgDnAQAAAA==.Talerah:BAABNQAECn8oAAITAAgK4AvyGABJAQATAAgK4AvyGABJAQAAAA==.Taliliia:BAAANQABCgIIAgAAAA==.Talilyia:BAAANQADCgcIHgAAAA==.Talohae:BAACNQAFFH8HAAIiAAMKVx31CgAfAQAiAAMKVx31CgAfAQA1AAQKfzAAAiIACgq7JGEBAMMDACIACgq7JGEBAMMDAAAA.Tanjent:BAAANQAECgQIBgAAAA==.Tapio:BAAANQAECgIIAgAAAA==.Tatsuma:BAAANQADCgYIEgABNQAECgcIGgAbAFUVAA==.Tatsumå:BAAANQAECgUIBQABNQAECgcIGgAbAFUVAA==.Tavv:BAABNQAECn8kAAIXAAgKFghYGwCvAQAXAAgKFghYGwCvAQAAAA==.',
Te='Tekkesh:BAAANQADCgMIAwAAAA==.Terp:BAAANQABCgYIBgAAAA==.',
Th='Thenakedpaly:BAAANQADCgEIAQAAAA==.Thibbildorf:BAAANQABCgEIAQAAAA==.Thirain:BAAANQADCgcIBwABNQAECgUICQAEAAAAAA==.Thorrs:BAABNQAECn8cAAIUAAkKhA6zWQAWAgAUAAkKhA6zWQAWAgAAAA==.Thuglifé:BAABNQAECn8cAAIOAAkK1gqhGQCaAQAOAAkK1gqhGQCaAQAAAA==.Thundacat:BAABNQAECn8jAAIbAAkK/CS7BABZAwAbAAkK/CS7BABZAwAAAA==.',
Ti='Tia:BAAANQADCgUIBQABNQAECgcIFAAFALwGAA==.Tidemaiden:BAABNQAECn8hAAMHAAgKaRE+bgDAAQAHAAgKaRE+bgDAAQAXAAEK0AGZOgAkAAAAAA==.Tipsymancer:BAABNQAECn8zAAIcAAgKpiCXAQDhAQAcAAgKpiCXAQDhAQAAAA==.',
Tr='Treesus:BAABNQAECn8mAAIYAAoKeg92NgA4AgAYAAoKeg92NgA4AgAAAA==.Treëfrog:BAAANQABCgIIAgAAAA==.Trickytrey:BAAANQADCgIIAgABNQAECggIGgAKAEAYAA==.Troutman:BAAANQAECgEIAQAAAA==.Tryantjhg:BAAANQABCgQIBAAAAA==.',
Ts='Tsu:BAAANQADCgYIBgAAAA==.',
['Tñ']='Tñer:BAABNQAECn8aAAIKAAgKQBgaLwBkAQAKAAgKQBgaLwBkAQAAAA==.',
Ur='Uruloke:BAAANQADCgYIDAABNQAECgEIAQAEAAAAAA==.',
Va='Valry:BAAANQADCgQIBAAAAA==.Vashdin:BAAANQAECgQIBwAAAA==.',
Ve='Velashis:BAABNQAECn8eAAMiAAkKZRkZHABVAgAiAAkKZRkZHABVAgAYAAIKUgK7swAwAAAAAA==.Venomable:BAABNQAECn8bAAMnAAgKRhHtIQC8AQAnAAcKCxDtIQC8AQAgAAUK9gwMJwC0AAAAAA==.Vermin:BAABNQAECn8qAAIUAAkKNxi0PQB/AgAUAAkKNxi0PQB/AgAAAA==.',
Vi='Vicvega:BAAANQAECgYIDwABNQAECgkJGwAVABsUAA==.Vivif:BAABNQAECn8sAAQcAAoKix7RBgDZAgAcAAoKVB7RBgDZAgAfAAYKiRrEGwDHAQAdAAUK2B5wLgClAQAAAA==.Vivila:BAAANQAECgIIAgABNQAECgkJHQAeALgUAA==.',
Vo='Void:BAAANQADCgYIEgAAAA==.Voldemotor:BAAANQAECgcIEAAAAA==.Volstak:BAAANQADCgUIBwAAAA==.',
Vr='Vresim:BAABNQAECn8XAAMmAAgKQhlzGADBAQAmAAcKmxZzGADBAQAoAAcK+RJYJAChAQAAAA==.',
Vu='Vugnus:BAAANQAECgQIBwAAAA==.Vugowulf:BAAANQADCggIDQAAAA==.',
['Vé']='Véxx:BAAANQAECgQIDgAAAA==.',
['Vï']='Vïx:BAAANQAECgYIBQAAAA==.',
Wa='Wadewilson:BAAANQADCgcICwAAAA==.Waltahflight:BAAANQAECgEIAQAAAA==.Wannan:BAAANQADCggICAAAAA==.Waycaps:BAAANQAECggIEAAAAA==.',
We='Westrin:BAACNQAFFH8IAAIZAAMK5x2eAADKAAAZAAMK5x2eAADKAAA1AAQKfyMAAhkACgraH/wBABoDABkACgraH/wBABoDAAAA.',
Wi='Wiegraf:BAAANQADCgYJCQABNQAECggILAACAH4cAA==.Wife:BAABNQAECn8aAAMQAAkKwSExPQDeAgAQAAkKwSExPQDeAgACAAMK+wUF/ACFAAAAAA==.Wingedmonkey:BAAANQADCgEIAQAAAA==.',
Wr='Wrathe:BAAANQAECgUICQAAAA==.',
Ya='Yacob:BAABNQAECn8iAAMhAAkKiho7CQBSAgAhAAkKiho7CQBSAgAWAAMKTw+QXACTAAAAAA==.Yarlyn:BAAANQAECgEIAQABNQAECgQICgAEAAAAAA==.',
Ye='Yenneferr:BAABNQAECn8ZAAIeAAgKyAypMAC8AQAeAAgKyAypMAC8AQAAAA==.',
Yh='Yhwach:BAAANQAECgYICQAAAA==.',
Ym='Ymir:BAABNQAECn8eAAIQAAkKiBl3YgBzAgAQAAkKiBl3YgBzAgABNQAECgEIAQAEAAAAAA==.',
Yo='Yosaf:BAABNQAECn8UAAIQAAcKDBvudwA8AgAQAAcKDBvudwA8AgAAAA==.',
Yu='Yuie:BAAANQAECgMIAwABNQAECgcIFAAFALwGAA==.Yukitaiga:BAAANQADCggIDAABNQABCgQIBQAEAAAAAA==.',
Za='Zaft:BAABNQAECn8yAAMQAAgKuA5bPQBMAQAQAAgKawxbPQBMAQAPAAIKPBeHWgByAAAAAA==.Zaha:BAABNQAECn8UAAIKAAgKDyBJhwBwAgAKAAgKDyBJhwBwAgAAAA==.Zappsz:BAAANQADCggIGQAAAA==.Zardoc:BAAANQADCgIIAgAAAA==.',
Ze='Zedfrey:BAABNQAECn8WAAIQAAcKMAmj7QBBAQAQAAcKMAmj7QBBAQAAAA==.Zem:BAABNQAECn8gAAMMAAkKQhSNKgBeAQAMAAkKQhSNKgBeAQANAAIK4AkMJgB9AAAAAA==.Zemangoose:BAAANQAECgEIAQAAAA==.Zennish:BAAANQADCgUIDQAAAA==.Zeplen:BAABNQAECn8pAAICAAoKBBb2RQBOAgACAAoKBBb2RQBOAgAAAA==.Zeroultra:BAABNQAECn8VAAINAAcKmxesDgDDAQANAAcKmxesDgDDAQAAAA==.Zeräse:BAAANQAECgIIAgABNQAECggILAACAH4cAA==.Zeusmos:BAABNQAECn8gAAIdAAkKViA4CgAuAwAdAAkKViA4CgAuAwAAAA==.',
Zi='Zithenex:BAAANQAECgQIBwAAAA==.',
Zu='Zugleesh:BAAANQAFFAEIAgAAAA==.',
Zw='Zwar:BAAANQAECgEIAQAAAA==.',
['Ál']='Álister:BAAANQAECgQIBwAAAA==.',
['Æó']='Æón:BAAANQAECgIIAgAAAA==.',
['Ér']='Éragon:BAAANQABCgIIAgAAAA==.',
['ßo']='ßoru:BAAANQAECgMIBQAAAA==.',
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
