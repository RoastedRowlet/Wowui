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

local lookup = {'Rogue-Outlaw','Paladin-Holy','DeathKnight-Blood','Unknown-Unknown','Shaman-Restoration','Hunter-BeastMastery','Warlock-Destruction','Mage-Arcane','Warlock-Demonology','Warrior-Arms','Warrior-Fury','Paladin-Protection','Paladin-Retribution','Mage-Frost','Warrior-Protection','DeathKnight-Unholy','DeathKnight-Frost','Shaman-Elemental','Hunter-Marksmanship','Shaman-Enhancement','Druid-Balance','Warlock-Affliction','Monk-Brewmaster','Monk-Windwalker','DemonHunter-Devourer','DemonHunter-Havoc','DemonHunter-Vengeance','Monk-Mistweaver','Rogue-Assassination','Druid-Restoration','Druid-Guardian','Druid-Feral','Evoker-Augmentation','Hunter-Survival','Priest-Shadow','Priest-Holy','Evoker-Devastation','Evoker-Preservation',}
local provider = {region='US',realm='Zangarmarsh',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aafra:BAAANQADCgcIBwAAAA==.Aaminae:BAABNQAECoEfAAIBAAcKhRkeCAAMAgABAAcKhRkeCAAMAgAAAA==.',
Ab='Abracadaver:BAAANQAECgEIAQAAAA==.Abracastabya:BAAANQADCgQIBAABNQAECggIGgACAP0dAA==.Abysstral:BAAANQABCgYIBgAAAA==.',
Ae='Aedar:BAABNQAECoExAAIDAAgKYx0tIwCEAgADAAgKYx0tIwCEAgAAAA==.Aegon:BAAANQABCgMIAwAAAA==.Aenledron:BAAANQAECgEIAQABNQAECgUIBQAEAAAAAA==.Aeturnas:BAABNQAECoElAAICAAgKVyHqFgAPAwACAAgKVyHqFgAPAwAAAA==.',
Af='Afukeenba:BAAANQADCgYIDQAAAA==.',
Ai='Aire:BAAANQAECgYIEAAAAA==.',
Al='Alanima:BAAANQAECgUIBgAAAA==.Alauradona:BAAANQADCgUIBwAAAA==.Aliana:BAAANQAECgMIAwABNQAECggIGAAFANwYAA==.Alittlegeeky:BAAANQADCgIJAgABNQAECgYJEQAEAAAAAA==.Allesta:BAAANQADCgYICQAAAA==.Allypally:BAAANQADCggIDwAAAA==.Aloriz:BAAANQADCgMIAwAAAA==.Alphamage:BAAANQAECgQIBgAAAA==.Alphamonk:BAAANQADCgEIAQABNQADCgYIBgAEAAAAAA==.Alphawarrior:BAAANQADCgYIBgAAAA==.Alros:BAABNQAECoEiAAIGAAgKkBy6NgCkAgAGAAgKkBy6NgCkAgAAAA==.',
An='Andralynn:BAAANQAECgEIAQAAAA==.',
Ao='Aoiryo:BAAANQADCgIIAgABNQAECgQIBAAEAAAAAA==.',
Aq='Aquilas:BAAANQAECgYIBgAAAA==.',
Ar='Arcstream:BAAANQAECgMIAwAAAA==.Arctica:BAAANQADCgUIBQAAAA==.Arette:BAAANQADCgMIAwAAAA==.Arkshade:BAAANQAECgQIBgAAAA==.',
As='Asmo:BAAANQADCgEIAQAAAA==.Astarii:BAAANQAECggIAgAAAA==.Asterica:BAABNQAECoEjAAIHAAcK2BoXCwA7AgAHAAcK2BoXCwA7AgAAAA==.',
Av='Averynicole:BAAANQADCgIIAgAAAA==.',
Aw='Awasjr:BAABNQAECoEcAAIGAAgKkBSJWABAAgAGAAgKkBSJWABAAgAAAA==.',
Ay='Ayano:BAABNQAECoEsAAIIAAkKmiK9GABrAwAIAAkKmiK9GABrAwAAAA==.Ayulur:BAAANQAECgEIAwAAAA==.',
Az='Azraél:BAAANQADCggIBwAAAA==.Azurefalls:BAABNQAECoEmAAIDAAgKrSKaEAAVAwADAAgKrSKaEAAVAwAAAA==.',
Ba='Badfiremage:BAABNQAECoEdAAMJAAgKaxnOTQBLAgAJAAgKaxnOTQBLAgAHAAEKVwJ9fwAiAAAAAA==.Balthïer:BAABNQAECoEcAAICAAcKLx4YOwBbAgACAAcKLx4YOwBbAgAAAA==.Bark:BAABNQAECoEjAAMKAAcKGSGuUAB8AgAKAAcK/yCuUAB8AgALAAUKlhzqEABxAQAAAA==.',
Be='Bearshock:BAAANQAECgEIAQAAAA==.Beatriixx:BAAANQADCgEIAQAAAA==.Bee:BAABNQAECoEUAAMMAAgKqyLLCAD1AgAMAAcKXCbLCAD1AgANAAQKPRP29AD6AAABNQAECgkJKAADAH4kAA==.Beeb:BAAANQAECgUIBgABNQAECgkJKAADAH4kAA==.Beefisting:BAAANQADCgIIAgABNQAECgkJKAADAH4kAA==.Beezz:BAABNQAECoEoAAIDAAkKfiTXAwCtAwADAAkKfiTXAwCtAwAAAA==.Belardor:BAAANQAECggICAAAAA==.Beliara:BAAANQAECgIIAgAAAA==.Bendovar:BAAANQADCgEIAQAAAA==.',
Bi='Bilithi:BAAANQAECgEIAQAAAA==.Bionarra:BAABNQAECoEiAAMOAAgKtx6BBAC6AgAOAAgKtx6BBAC6AgAIAAEKoQIJwwEhAAAAAA==.Bishopwr:BAABNQAECoEYAAMKAAgKyw0ziwDZAQAKAAgKyw0ziwDZAQAPAAUKzAF7LwCEAAAAAA==.',
Bl='Blaire:BAAANQADCgQIBAAAAA==.',
Bo='Bobdobbs:BAAANQADCgYIBgAAAA==.Bohica:BAAANQAECgQIBgAAAA==.',
Br='Branch:BAAANQADCgYIBgABNQAECggIHAADAJwRAA==.Brem:BAABNQAECoEnAAIIAAkKAR1fVwDAAgAIAAkKAR1fVwDAAgAAAA==.Briara:BAAANQADCggIHgAAAA==.Broknüs:BAAANQAECgMIBAAAAA==.Broníx:BAAANQAECgIIAgAAAA==.Bropeep:BAABNQAECoEdAAMQAAcKPiN8HADFAgAQAAcKPiN8HADFAgARAAIK/QqngQBhAAAAAA==.',
Bu='Bullshott:BAAANQAECgMIBAAAAA==.Burritobolts:BAAANQADCggICAAAAA==.',
By='Bylun:BAAANQADCggIBQAAAA==.',
Ca='Callaghar:BAAANQADCgQIBAABNQAECgYICQAEAAAAAA==.Calyen:BAAANQAECgMIAwAAAA==.Carartha:BAAANQAECgUIDgAAAA==.Carnitine:BAAANQADCgYIBgABNQAECggIHQAJAGsZAA==.Carrots:BAAANQAECgQIBgAAAA==.Cashmoolah:BAABNQAECoEeAAINAAgKnA4JmQC6AQANAAgKnA4JmQC6AQAAAA==.Catfight:BAAANQAECgEIAQAAAA==.',
Ch='Chadilton:BAAANQADCgYIDwAAAA==.Chadsmon:BAACNQAFFIEGAAISAAMKSApqFwDYAAASAAMKSApqFwDYAAA1AAQKgS0AAhIACQptF88xAI0CABIACQptF88xAI0CAAAA.Charcoal:BAABNQAECoEkAAMHAAkK6BZmCABuAgAHAAkKZBRmCABuAgAJAAcKaw+SiACiAQAAAA==.Chasebakes:BAABNQAECoEnAAMTAAkKryANDAAKAwATAAkKah4NDAAKAwAGAAIKOSB/CwGhAAAAAA==.Cheesecake:BAAANQAECgQIBgAAAA==.Choks:BAAANQAECgEIAQAAAA==.Chumbawamba:BAAANQADCgYJBgAAAA==.Chéfboyrlee:BAAANQAECgYICgABNQAFFAUIEgAUAMIXAA==.',
Ci='Cindiyoohoo:BAABNQAECoEfAAIVAAgKZxm4KQBmAgAVAAgKZxm4KQBmAgAAAA==.Cizmac:BAAANQADCgUIBwAAAA==.',
Cm='Cmdrshepard:BAAANQADCgEIAQABNQAECgQIBwAEAAAAAA==.',
Co='Corruptdata:BAAANQADCgIIBAAAAA==.Cownado:BAAANQAECgEIAQABNQAECgMIAwAEAAAAAA==.',
Cr='Crawlerkarl:BAAANQADCgIIAgAAAA==.',
Ct='Ctrlaltchill:BAAANQADCgQIBAAAAA==.',
Cu='Cursedspirit:BAAANQADCgMIAwAAAA==.Custard:BAAANQAECgMIAwAAAA==.Cut:BAAANQADCgcIEQABNQAECgYIEAAEAAAAAA==.',
Cy='Cyfelen:BAABNQAECoEjAAMJAAgKnBywSQBYAgAJAAcKdRywSQBYAgAWAAEKsB2HIQBXAAAAAA==.Cynleel:BAAANQAECgQIBgAAAA==.Cyris:BAAANQAECgIIAQAAAA==.',
Da='Dahrena:BAAANQAECgYICwAAAA==.Darthmall:BAAANQAECgUIDQABNQAECgkJHwAXAE0cAA==.Dawntyrant:BAAANQADCgIIAwAAAA==.',
De='Demidru:BAAANQAECgUIDgAAAA==.Derat:BAAANQADCggICAAAAA==.Deucalion:BAAANQADCgIIAgAAAA==.',
Di='Dibbydab:BAAANQAECgcIEAAAAA==.',
Dj='Django:BAAANQAECgcIEQAAAA==.Djehrtey:BAAANQADCggIHwAAAA==.Djinni:BAABNQAECoEfAAMXAAkKTRz3BwCWAgAXAAkKTRz3BwCWAgAYAAMKJg/iSgCaAAAAAA==.Djwiltumble:BAAANQADCgUIBQAAAA==.',
Dk='Dkota:BAAANQADCgYIEQAAAA==.',
Do='Doodle:BAAANQAECgUIEAAAAA==.',
Dr='Dracnahr:BAAANQAECgYICQAAAA==.Drenleah:BAAANQAECgYICQABNQAECgcIEQAEAAAAAA==.Drenlee:BAAANQAECgIIAgABNQAECgcIEQAEAAAAAA==.',
Du='Dumblegear:BAABNQAECoEZAAIIAAgK8RqcbgCLAgAIAAgK8RqcbgCLAgAAAA==.Duramei:BAAANQADCgMIAwAAAA==.Durian:BAABNQAECoEYAAIFAAgK3BhWOwBJAgAFAAgK3BhWOwBJAgAAAA==.',
Dw='Dwagon:BAAANQADCgYJBgABNQAECgkJIAAFAIgRAA==.',
Dy='Dysdayne:BAAANQAECgIIAgABNQAECgQIBAAEAAAAAA==.',
Ed='Edinna:BAABNQAECoEXAAIIAAgKggowzwDDAQAIAAgKggowzwDDAQAAAA==.',
Ei='Eileamaid:BAAANQADCgYIEQAAAA==.',
El='Elessedil:BAAANQAECgQIBQAAAA==.Ellemystic:BAAANQADCgcIGQAAAA==.Elspeth:BAAANQADCggICAABNQAECgYICQAEAAAAAA==.Elyriana:BAAANQAECgcIDwAAAA==.',
Em='Emila:BAEANQADCgcIGgABNQAECggIHwAGAJ0hAA==.Emirozu:BAAANQADCgIIAgAAAA==.Emma:BAAANQABCgQIBgAAAA==.Emokilla:BAAANQAECgQIBAAAAA==.Emriq:BAAANQAECgMIBAAAAA==.',
En='Enrique:BAABNQAECoE8AAINAAkKviKCGABPAwANAAkKviKCGABPAwAAAA==.',
Ep='Epedemik:BAAANQAECgEIAQAAAA==.',
Er='Erazath:BAAANQAECgMIAwABNQAECggIHAADAJwRAA==.Erussh:BAAANQADCgQIBQAAAA==.',
Es='Estanna:BAAANQAECggIBgAAAA==.',
Ev='Evöö:BAAANQAECgYIBgAAAA==.',
Ex='Exhul:BAAANQAECgMIBAAAAA==.',
Fa='Faewing:BAAANQAECgEIAQAAAA==.Falar:BAAANQAECgQIBQAAAA==.',
Fe='Fearlesfreep:BAABNQAECoEiAAIGAAgKbg9XaAAYAgAGAAgKbg9XaAAYAgAAAA==.Febz:BAAANQAECgUICAAAAA==.Felatonin:BAABNQAECoEZAAIZAAgKsB+qFACqAgAZAAgKsB+qFACqAgAAAA==.Felfüry:BAABNQAECoEjAAMaAAkKng7rLgAAAgAaAAkKqg3rLgAAAgAbAAQKogu9HQCxAAAAAA==.Fenixshaw:BAAANQADCgYIFQAAAA==.Festyr:BAAANQADCgQIBAAAAA==.Feyd:BAAANQADCgYIBgAAAA==.',
Fi='Finella:BAAANQAECgEIAQAAAA==.Finneas:BAAANQAECgUIEQAAAA==.',
Fo='Foggpy:BAABNQAECoEbAAIWAAgKfCEIAgD1AgAWAAgKfCEIAgD1AgAAAA==.',
Fr='Freinkenbaby:BAAANQADCgEIAQAAAA==.Frostey:BAAANQAECgUIDAAAAA==.Fröstmöurne:BAABNQAECoEZAAIDAAgKiQoaVwB1AQADAAgKiQoaVwB1AQAAAA==.',
Fu='Furbetime:BAAANQADCgMIAwAAAA==.',
Ga='Gabrièllè:BAAANQADCgcIBwAAAA==.Galaythien:BAAANQADCggIGQAAAA==.',
Ge='Geluria:BAAANQAECgQICgABNQAECgcIGgAJAOwcAA==.Genghiskhan:BAABNQAECoElAAIQAAgKihrCMQBCAgAQAAgKihrCMQBCAgAAAA==.Geren:BAAANQAECggIDwAAAA==.Geret:BAABNQAECoEiAAINAAgKoRVxeAAMAgANAAgKoRVxeAAMAgAAAA==.',
Gh='Ghanaria:BAAANQADCgQJBAAAAA==.',
Gi='Gingervex:BAAANQADCggIEAAAAA==.Gissmo:BAAANQADCgYICwAAAA==.',
Gl='Glitchy:BAABNQAECoEhAAIVAAgK0RVANQAXAgAVAAgK0RVANQAXAgAAAA==.Gloppy:BAAANQADCgcIBwAAAA==.',
Go='Gogmagog:BAAANQADCgEIAQAAAA==.Goingtogetu:BAABNQAECoEhAAIMAAgKbh9CCwDGAgAMAAgKbh9CCwDGAgAAAA==.Goldfarmr:BAAANQAECgEIAQABNQAECgkJJgAIAFweAA==.Goldglazeher:BAABNQAECoEmAAIIAAkKXB5zNAAVAwAIAAkKXB5zNAAVAwAAAA==.Goldrawr:BAAANQADCgYIBgABNQAECgkJJgAIAFweAA==.Golgotha:BAAANQABCgcICQAAAA==.',
Gr='Graddy:BAAANQADCgQIBAAAAA==.Gradhrek:BAAANQABCgIIAwAAAA==.Greeley:BAAANQAECgYIEgAAAA==.Greganir:BAABNQAECoEYAAMOAAgKdRphFwAaAQAIAAgKVhYqkwA9AgAOAAQKUxlhFwAaAQABNQAECgUICwAEAAAAAA==.Gregdapro:BAAANQAECgUICwAAAA==.Grimshady:BAAANQAECgIIAgAAAA==.Gritty:BAAANQABCgMIAwAAAA==.',
Gu='Gunnyal:BAAANQAECgEIAQAAAA==.',
Gy='Gyathew:BAABNQAECoEhAAISAAkKnCAHFgAwAwASAAkKnCAHFgAwAwAAAA==.',
Ha='Hagunn:BAABNQAECoEZAAMKAAkKXxbvbQAoAgAKAAkKdBTvbQAoAgALAAMK9RuAFwAEAQAAAA==.',
He='Heladaa:BAAANQADCgMIAwAAAA==.Hervöralvit:BAAANQADCgIIAgAAAA==.Hevy:BAAANQAECgcIEQAAAA==.',
Hi='Hidensneak:BAAANQADCggICAAAAA==.Hildzap:BAAANQADCgYICwAAAA==.',
Ho='Holyshots:BAABNQAECoEjAAINAAgKWxOMhADsAQANAAgKWxOMhADsAQAAAA==.Howlinnbrews:BAAANQADCggICgAAAA==.',
Hu='Huyu:BAAANQADCgUIAQAAAA==.',
Id='Idrizzt:BAAANQABCgMIAwAAAA==.',
Ig='Ignore:BAAANQADCgcIDgABNQAECggIHQAJAGsZAA==.',
In='Invariable:BAAANQAECgYIEgAAAA==.',
Io='Iobo:BAAANQAECgEIAQAAAA==.',
Ir='Ironhidez:BAABNQAECoEbAAINAAcKLgkJywBMAQANAAcKLgkJywBMAQAAAA==.',
Is='Ishiza:BAAANQABCgIIAgAAAA==.',
It='Itsatrap:BAAANQAECgMIBQABNQAECggIGAAFANwYAA==.',
Iz='Izerol:BAABNQAECoEzAAIYAAkKPyThAwCMAwAYAAkKPyThAwCMAwAAAA==.',
Ja='Jasmini:BAAANQADCgQIBAAAAA==.',
Je='Jeb:BAAANQABCgUIBQABNQAECggIGgACAP0dAA==.Jebopally:BAABNQAECoEaAAMCAAgK/R0hMwB8AgACAAcKiB4hMwB8AgANAAcKlxkmiADjAQAAAA==.Jeouleous:BAAANQADCgcIBwAAAA==.Jetblack:BAABNQAECoEdAAIJAAcKBRisaAD8AQAJAAcKBRisaAD8AQAAAA==.',
Ji='Jiblows:BAAANQADCgYIBgAAAA==.Jibolls:BAAANQAECgUICwAAAA==.',
Jo='Joehex:BAABNQAECoEcAAIPAAgKHCCEBgDcAgAPAAgKHCCEBgDcAgAAAA==.Jointjester:BAAANQADCggICAAAAA==.Joulez:BAAANQADCgYICwAAAA==.',
Ju='Judgematt:BAAANQADCggIDAAAAA==.Judgemental:BAAANQADCgQIBAAAAA==.Justin:BAAANQAECgUICAAAAA==.',
Ka='Kaidoe:BAAANQAECgEIAQAAAA==.Kaleesh:BAACNQAFFIEHAAIUAAQKWBxMAgB6AQAUAAQKWBxMAgB6AQA1AAQKgRwAAhQACQrQJVkBAK4DABQACQrQJVkBAK4DAAAA.Kallux:BAABNQAECoEgAAIDAAgK/B0KHQCvAgADAAgK/B0KHQCvAgAAAA==.Kalma:BAABNQAECoEYAAIDAAgKeR1tHQCsAgADAAgKeR1tHQCsAgAAAA==.Kananga:BAAANQAECgEIAQAAAA==.Kasca:BAAANQAECgQICgAAAA==.Kato:BAAANQADCggICAABNQAECgYIEwAEAAAAAA==.Kazeem:BAAANQADCgEIAQAAAA==.',
Kh='Khadran:BAAANQADCgEIAQAAAA==.Khalyraa:BAAANQAECgQICAAAAA==.',
Ki='Kiermac:BAAANQAECgQIBAAAAA==.Kindred:BAAANQADCgQIBAAAAA==.Kiragrande:BAABNQAECoEcAAIcAAkK4g+7FAADAgAcAAkK4g+7FAADAgAAAA==.Kiriku:BAAANQAECgQIBwAAAA==.Kithane:BAAANQADCgMIAwAAAA==.',
Kl='Klorto:BAAANQADCgEIAQAAAA==.',
Ko='Korbinf:BAAANQAECgUIBQAAAA==.Kotok:BAAANQAECgQIBgAAAA==.',
Kr='Krelein:BAAANQAECgQIBgAAAA==.',
Ku='Kurth:BAAANQADCgUICAAAAA==.',
Ky='Kyu:BAAANQADCgcIDQAAAA==.',
La='Lancaster:BAAANQADCgIIAgAAAA==.',
Le='Lee:BAABNQAECoEZAAIYAAcKXiNeEwCcAgAYAAcKXiNeEwCcAgAAAA==.Levin:BAAANQAECgIIAwAAAA==.',
Li='Linissa:BAAANQAECgMJBgABNQAECgkJHwAXAE0cAA==.',
Ll='Llght:BAAANQAECgMIAwAAAA==.',
Lo='Logankord:BAABNQAECoEdAAILAAgKUB9UBADVAgALAAgKUB9UBADVAgAAAA==.Lokeira:BAABNQAECoEgAAIFAAkKiBHZVADmAQAFAAkKiBHZVADmAQAAAA==.Loonnah:BAAANQADCgQIBQAAAA==.',
Lu='Luuniren:BAAANQADCggIFgABNQAECgQIBAAEAAAAAA==.Luvbug:BAAANQAECgYJEQAAAA==.',
Ly='Lyais:BAAANQAECgQIBQAAAA==.Lyara:BAABNQAECoEmAAMFAAkKWx77IgC8AgAFAAkKWx77IgC8AgASAAYKLhUjeQCHAQAAAA==.Lythos:BAABNQAECoEcAAIDAAgKnBFaRgDAAQADAAgKnBFaRgDAAQAAAA==.',
['Lø']='Lørdøfßud:BAABNQAECoEeAAMPAAgKnyBoBgDeAgAPAAgKnyBoBgDeAgAKAAEKwA9qLwE6AAAAAA==.',
Ma='Machomans:BAAANQAECgQIBQABNQAECgcIEAAEAAAAAA==.Magdann:BAAANQABCgIJAgAAAA==.Mahasamatman:BAAANQAECgEIAQAAAA==.Mankilla:BAAANQADCgMIAwAAAA==.Mansa:BAABNQAECoEkAAIdAAkK/w1nJgAqAgAdAAkK/w1nJgAqAgAAAA==.Mastamojo:BAABNQAECoEfAAICAAgKwgdGeQCEAQACAAgKwgdGeQCEAQAAAA==.Mattheals:BAAANQAECggIDQAAAA==.',
Mc='Mcmurphy:BAAANQADCgYIBgAAAA==.',
Me='Meissen:BAAANQAECgQIBwAAAA==.Melendaren:BAAANQADCgcIEwAAAA==.Meltara:BAAANQADCgQIBAAAAA==.Messìah:BAAANQAECgUIEQAAAA==.Metamonster:BAAANQAECgEIAQAAAA==.',
Mi='Mickie:BAAANQAECgYICQAAAA==.Miniav:BAAANQADCgcIGQAAAA==.Mirko:BAAANQADCgYJCQABNQAECgcIEAAEAAAAAA==.',
Ml='Mladjo:BAAANQAECgMIBgAAAA==.',
Mo='Mockery:BAABNQAECoEkAAIIAAgKzw3luQDsAQAIAAgKzw3luQDsAQAAAA==.Mokokniki:BAABNQAECoEaAAIeAAgKaxDEJgC7AQAeAAgKaxDEJgC7AQAAAA==.Moneie:BAAANQADCgEIAQAAAA==.Monger:BAAANQADCgEIAQAAAA==.Moog:BAAANQADCgQIBAAAAA==.Moondo:BAAANQADCgQIBAAAAA==.Moothyr:BAAANQAECgQIBwAAAA==.Morticiá:BAAANQADCgcIFgAAAA==.Mourningstar:BAABNQAECoEXAAMQAAkKUyPdEgALAwAQAAgK1SPdEgALAwADAAUK1x5QVwB0AQABNQAFFAQICgADAO4YAA==.Mozaic:BAABNQAECoEhAAIPAAgKyB/UBgDTAgAPAAgKyB/UBgDTAgAAAA==.',
My='Myselia:BAAANQADCgYICAAAAA==.',
Na='Nad:BAAANQADCgcIGwAAAA==.Naec:BAAANQADCgEIAQABNQADCgYIGQAEAAAAAA==.Naek:BAAANQADCgYIGQAAAA==.Nalthis:BAAANQAECgcIBwAAAA==.',
Ne='Necromus:BAAANQADCggILgAAAA==.Nekra:BAAANQAECgQIBAAAAA==.',
Ni='Nibbi:BAAANQADCgYJBgAAAA==.Nicehair:BAAANQAECgcICgAAAA==.',
No='Nocturnum:BAABNQAECoElAAIZAAkK9R7CCABAAwAZAAkK9R7CCABAAwAAAA==.',
Nu='Numb:BAAANQADCgEIAQAAAA==.',
Ny='Nyctea:BAAANQADCgQIBAAAAA==.Nyria:BAAANQADCgEIAQAAAA==.',
Ol='Oldmongerpal:BAAANQADCggICgAAAA==.Oltiyet:BAAANQAECgQIBAAAAA==.',
On='Onepuffman:BAACNQAFFIESAAIUAAUKwhd7AQDTAQAUAAUKwhd7AQDTAQA1AAQKgSUAAhQACQpKIDEGABYDABQACQpKIDEGABYDAAAA.Onetwocowpow:BAABNQAECoEjAAIcAAgKGxHJGADDAQAcAAgKGxHJGADDAQAAAA==.',
Or='Ordanith:BAABNQAECoEiAAINAAcKYCB/UQB4AgANAAcKYCB/UQB4AgAAAA==.Orionn:BAACNQAFFIENAAIGAAQKXhlbCwBmAQAGAAQKXhlbCwBmAQA1AAQKgTIAAgYACQogJfUFAKUDAAYACQogJfUFAKUDAAAA.',
Os='Osø:BAAANQAECgUIDwAAAA==.',
Ov='Oven:BAABNQAECoEhAAQcAAgKrBb1GADAAQAcAAcKbxX1GADAAQAYAAUKMxMxNQA0AQAXAAEKDw6ELAA1AAAAAA==.',
Ow='Owlxero:BAAANQADCggIDQAAAA==.',
Pe='Pelma:BAAANQADCgIIAgABNQAECgQICgAEAAAAAA==.',
Ph='Phyras:BAAANQABCgcIBwAAAA==.',
Pi='Pinesoul:BAAANQADCgQIBAAAAA==.Pippins:BAAANQADCgEIAQAAAA==.',
Po='Polytotems:BAAANQAECgYIDgAAAA==.',
Pr='Praystation:BAAANQAECgEIAQABNQAECgQIBwAEAAAAAA==.',
Qu='Quora:BAAANQABCggIEgAAAA==.',
Ra='Raelone:BAABNQAECoEYAAMHAAcKGxbVIgBPAQAHAAUKcRTVIgBPAQAWAAMKqxVJFADZAAAAAA==.Rageofmommy:BAAANQADCgIIAwAAAA==.Raidoe:BAAANQAECgQICgAAAA==.Raknslash:BAAANQADCgYIBgAAAA==.Rameumptom:BAAANQADCgYIDAAAAA==.Randers:BAAANQADCgMIAwAAAA==.Rangérz:BAABNQAECoEiAAIGAAgKcBeyTABgAgAGAAgKcBeyTABgAgAAAA==.Ranoa:BAAANQAECgcIEgABNQAECgkJKAAfABYhAA==.Rant:BAAANQAECgMIBAAAAA==.Ravencraw:BAAANQADCgYJCgAAAA==.Ravid:BAAANQADCgEIAQAAAA==.',
Re='Rebirth:BAAANQADCgUIBQAAAA==.Redxrum:BAAANQAECgIIAgAAAA==.Regress:BAAANQAECgQICQAAAA==.Reo:BAAANQADCgQIBAAAAA==.',
Rh='Rhell:BAABNQAECoEbAAICAAgKRSDKHQDlAgACAAgKRSDKHQDlAgAAAA==.Rhellen:BAAANQAECgYIDAABNQAECggIGwACAEUgAA==.',
Ri='Rinche:BAAANQAECgYIEQAAAA==.Rintche:BAAANQADCgUIBQAAAA==.',
Ro='Rolland:BAAANQAECgYIDgAAAA==.Rootbeamxo:BAAANQAECgQJBAAAAA==.Rosefyre:BAABNQAECoEaAAIJAAkKCQ/LXwAWAgAJAAkKCQ/LXwAWAgAAAA==.',
Ru='Rudo:BAAANQAECgcIEAAAAA==.Rumproblem:BAAANQAECgcIEwAAAA==.Ruri:BAAANQAECgMIBAABNQAECgcIEAAEAAAAAA==.',
Ry='Ryegar:BAAANQADCgUJBQAAAA==.Ryeger:BAABNQAECoEaAAIgAAgKwhe6CgBUAgAgAAgKwhe6CgBUAgAAAA==.Ryuaoi:BAAANQAECgEIAwABNQAECgQIBAAEAAAAAA==.',
['Ró']='Róótbear:BAAANQAECgUICgAAAA==.',
Sa='Safety:BAAANQAECgMIAwAAAA==.Salaine:BAAANQADCgcIDAAAAA==.Salfros:BAAANQADCgUIBQAAAA==.Samovar:BAABNQAECoEYAAMNAAgK6wzmnQCvAQANAAgK6wzmnQCvAQACAAIKPwQO/gBEAAAAAA==.Sandwiches:BAAANQAECggIEQAAAA==.Sanielan:BAAANQADCgMIAwAAAA==.',
Sc='Scalebagz:BAABNQAECoEiAAIhAAgKBBzmBACHAgAhAAgKBBzmBACHAgAAAA==.Schism:BAAANQAFFAEIAgAAAA==.',
Se='Sentren:BAAANQAECgIIAgAAAA==.Seo:BAAANQADCgQIBAAAAA==.Setresh:BAABNQAECoEjAAIiAAcK4hKABgAEAgAiAAcK4hKABgAEAgAAAA==.',
Sh='Shaken:BAAANQADCgMIAwAAAA==.Shamwowhex:BAAANQAECgYICQAAAA==.Shangöh:BAAANQADCgUICQABNQAECgcIHAACAC8eAA==.Sharatira:BAAANQADCgYIDAAAAA==.Shivyn:BAABNQAECoEhAAIFAAgKeBCLYwC0AQAFAAgKeBCLYwC0AQAAAA==.',
Si='Sibadeekay:BAABNQAECoEkAAMQAAgK6x3eMgA9AgAQAAgK6x3eMgA9AgADAAMKtgaDoAByAAAAAA==.Sickkid:BAAANQAECgYIDQAAAA==.Silvertier:BAAANQADCgMIAwAAAA==.Silverwulf:BAAANQADCgUIBwAAAA==.Sin:BAAANQAECgMIBgAAAA==.Sindrya:BAAANQAECgQIBAAAAA==.',
Sm='Smeef:BAAANQADCgIIAgAAAA==.Smoothvelvet:BAAANQAECgYIEwAAAA==.',
Sn='Snuggles:BAAANQADCgcIBwABNQAECgkJIgAiALgWAA==.',
So='Solára:BAABNQAECoEaAAMZAAgKOg40NQBzAQAZAAcKdQs0NQBzAQAbAAMK6Q+8HQCxAAAAAA==.',
Sp='Spellforge:BAAANQADCgcIEQAAAA==.Spinach:BAAANQADCgYIBgAAAA==.Sprath:BAAANQADCggICQAAAA==.',
St='Staretra:BAABNQAECoEjAAMjAAgKKQ/wLwB7AQAjAAcKSAzwLwB7AQAkAAgKawJxjQAzAQAAAA==.Sterarcher:BAAANQADCgIIAgAAAA==.',
Su='Sungjinwoo:BAAANQAECgEIAQAAAA==.Superdestror:BAAANQABCgcICgAAAA==.',
Ta='Taadra:BAABNQAECoEfAAIFAAgKlhJrWgDSAQAFAAgKlhJrWgDSAQAAAA==.Talerah:BAABNQAECoEaAAIRAAgK+wnzPgCLAQARAAgK+wnzPgCLAQAAAA==.Taliliia:BAAANQABCgIIAgAAAA==.Talilyia:BAAANQADCgcIGgAAAA==.Talohae:BAABNQAECoEpAAIeAAkKYCU4AQDBAwAeAAkKYCU4AQDBAwAAAA==.Tanjent:BAAANQAECgEIAQAAAA==.Tatsuma:BAAANQADCgYIEgABNQAECgYIEgAEAAAAAA==.Tavv:BAABNQAECoEfAAIUAAcKSQiuGQCaAQAUAAcKSQiuGQCaAQAAAA==.',
Te='Tekkesh:BAAANQADCgMIAwAAAA==.Terp:BAAANQABCgYIBgAAAA==.',
Th='Thenakedpaly:BAAANQADCgEIAQAAAA==.Thibbildorf:BAAANQABCgEIAQAAAA==.Thirain:BAAANQADCgcIBwABNQAECgUIBwAEAAAAAA==.Thorrs:BAABNQAECoEXAAISAAkKvAz0ZQC+AQASAAkKvAz0ZQC+AQAAAA==.Thuglifé:BAABNQAECoEcAAIPAAkKbAuaFQChAQAPAAkKbAuaFQChAQAAAA==.Thundacat:BAABNQAECoEgAAIfAAgKVCV7AwBjAwAfAAgKVCV7AwBjAwAAAA==.',
Ti='Tia:BAAANQADCgUIBQABNQAECgYIEAAEAAAAAA==.Tidemaiden:BAABNQAECoEZAAMFAAgKPA1SawCbAQAFAAgKPA1SawCbAQAUAAEK0AFQMwApAAAAAA==.Tipsymancer:BAABNQAECoEjAAIXAAgKcSCqBQDnAgAXAAgKcSCqBQDnAgAAAA==.',
Tr='Treesus:BAABNQAECoEeAAIVAAgKPRKhPADmAQAVAAgKPRKhPADmAQAAAA==.Treëfrog:BAAANQABCgIIAgAAAA==.Trickytrey:BAAANQADCgIIAgABNQAECgYIEQAEAAAAAA==.',
Ts='Tsu:BAAANQADCgYIBgAAAA==.',
['Tñ']='Tñer:BAAANQAECgYIEQAAAA==.',
Ur='Uruloke:BAAANQADCgYIDAABNQAECgEIAQAEAAAAAA==.',
Va='Valry:BAAANQADCgQIBAAAAA==.Vashdin:BAAANQAECgEIAQAAAA==.',
Ve='Velashis:BAAANQAECgcIEwAAAA==.Vermin:BAABNQAECoEeAAISAAgKOBpTOwBgAgASAAgKOBpTOwBgAgAAAA==.',
Vi='Vicvega:BAAANQAECgYIDAABNQAECgcIEAAEAAAAAA==.Visandar:BAAANQAECgYIAwAAAA==.Vivif:BAABNQAECoEjAAQXAAkK6R6/CAB9AgAXAAgKmB2/CAB9AgAcAAYKiRrlFwDPAQAYAAUKmh16JwCzAQAAAA==.Vivila:BAAANQADCggIDgABNQAECgcIEQAEAAAAAA==.',
Vo='Void:BAAANQADCgYIEgAAAA==.Voldemotor:BAAANQAECgcIEAAAAA==.Volstak:BAAANQADCgUIBwAAAA==.',
Vr='Vresim:BAABNQAECoEXAAMlAAgKDhrNFQDNAQAlAAcKRxjNFQDNAQAmAAcK+RLAIACsAQAAAA==.',
Vu='Vugnus:BAAANQAECgEIAQAAAA==.Vugowulf:BAAANQADCggICwAAAA==.',
['Vé']='Véxx:BAAANQAECgQIBgAAAA==.',
Wa='Wadewilson:BAAANQADCgcIBwAAAA==.Waltahflight:BAAANQAECgEIAQAAAA==.Waycaps:BAAANQAECgYIDQAAAA==.',
We='Westrin:BAABNQAECoEaAAIWAAkKDB+qAQARAwAWAAkKDB+qAQARAwAAAA==.',
Wi='Wiegraf:BAAANQADCgYJCQABNQAECgcIHAACAC8eAA==.Wife:BAABNQAECoEZAAMNAAkKFyKAKwD9AgANAAkKFyKAKwD9AgACAAMK+wVq5ACFAAAAAA==.Wingedmonkey:BAAANQADCgEIAQAAAA==.',
Wr='Wrathe:BAAANQAECgUIBwAAAA==.',
Ya='Yacob:BAAANQAECgUIEQAAAA==.Yarlyn:BAAANQAECgEIAQABNQAECgQICgAEAAAAAA==.',
Ye='Yenneferr:BAABNQAECoEYAAIZAAgKYA0rKQDaAQAZAAgKYA0rKQDaAQAAAA==.',
Ym='Ymir:BAABNQAECoEeAAINAAkK0xmBSgCOAgANAAkK0xmBSgCOAgABNQAECgEIAQAEAAAAAA==.',
Yo='Yosaf:BAAANQAECgYIEAAAAA==.',
Yu='Yukitaiga:BAAANQADCgYIBgABNQAECgQIBAAEAAAAAA==.',
Za='Zaft:BAABNQAECoEiAAMNAAgKRw8ZnACzAQANAAgKwAwZnACzAQAMAAIKPBedUABzAAAAAA==.Zaha:BAAANQAECgcIEwAAAA==.Zappsz:BAAANQADCggIGQAAAA==.Zardoc:BAAANQADCgIIAgAAAA==.',
Ze='Zedfrey:BAAANQAECgYJEgAAAA==.Zem:BAAANQAECgcIEgAAAA==.Zemangoose:BAAANQABCgIIAgAAAA==.Zenithyr:BAAANQADCgQJBAABNQAECgYJEQAEAAAAAA==.Zennish:BAAANQADCgUIDQAAAA==.Zeplen:BAABNQAECoEgAAICAAkK/xDbQABDAgACAAkK/xDbQABDAgAAAA==.Zeroultra:BAAANQAECgQIBgAAAA==.Zeusmos:BAABNQAECoEVAAIYAAgK5CAJDwDVAgAYAAgK5CAJDwDVAgAAAA==.',
Zi='Zithenex:BAAANQAECgEIAQAAAA==.',
Zu='Zugleesh:BAAANQAFFAEIAQAAAA==.',
Zw='Zwar:BAAANQAECgEIAQAAAA==.',
['Ál']='Álister:BAAANQAECgEIAQAAAA==.',
['Æó']='Æón:BAAANQAECgIIAgAAAA==.',
['ßo']='ßoru:BAAANQAECgIIAgAAAA==.',
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
