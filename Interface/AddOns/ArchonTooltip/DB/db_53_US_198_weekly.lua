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

local lookup = {'Mage-Arcane','Warlock-Demonology','Unknown-Unknown','Paladin-Holy','Paladin-Retribution','DemonHunter-Devourer','DeathKnight-Blood','Hunter-BeastMastery','Priest-Shadow','Warrior-Fury','Shaman-Enhancement','Hunter-Survival','Warrior-Arms','Warrior-Protection','Druid-Guardian','Rogue-Subtlety','Shaman-Elemental','Priest-Holy','Priest-Discipline','Shaman-Restoration','Hunter-Marksmanship','DeathKnight-Frost','Druid-Restoration','Druid-Balance','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Monk-Mistweaver','Monk-Windwalker','Warlock-Destruction','DeathKnight-Unholy','Rogue-Assassination','DemonHunter-Vengeance','Mage-Frost','DemonHunter-Havoc','Warlock-Affliction','Druid-Feral','Paladin-Protection',}
local provider = {region='US',realm='Skullcrusher',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Abzdh:BAAANQABCgQIBAABNQAECggIHgABALIjAA==.Abzlock:BAAANQAECgQIBAABNQAECggIHgABALIjAA==.Abzmage:BAABNQAECoEeAAIBAAgKsiOHJgAvAwABAAgKsiOHJgAvAwAAAA==.Abzp:BAAANQAECgMIBQABNQAECggIHgABALIjAA==.Abzrogue:BAAANQAECgIIAgABNQAECggIHgABALIjAA==.',
Ac='Acoreüs:BAEBNQAECoEbAAICAAYK/AxQkQBWAQACAAYK/AxQkQBWAQAAAA==.',
Ad='Adramelk:BAAANQAECgIIBAABNQAECgYIDgADAAAAAA==.',
Ae='Aed:BAAANQABCgEIAQAAAA==.Aeiay:BAAANQAECgQIBgAAAA==.',
Ai='Aibh:BAAANQADCgUIBwAAAA==.',
Al='Alastorias:BAAANQAECgIIAgAAAA==.Alethice:BAAANQADCgcIBwAAAA==.Alexandrap:BAAANQAECgIIAgAAAA==.Allmighto:BAECNQAFFIETAAIEAAYKZxodAwAVAgAEAAYKZxodAwAVAgA1AAQKgSIAAgQACQpJIw4EAJ8DAAQACQpJIw4EAJ8DAAAA.Alyssaxoo:BAABNQAECoEdAAMEAAkKxhIxNgBPAgAEAAkKxhIxNgBPAgAFAAEKVAqDVgEuAAAAAA==.',
An='Androstraz:BAAANQADCggICAAAAA==.Anjkh:BAAANQADCgYIBgAAAA==.Anniesthesia:BAAANQAECgUJBwAAAA==.Anoobyss:BAABNQAECoEVAAIGAAUKaQ4lPAAVAQAGAAUKaQ4lPAAVAQAAAA==.Anorexorcist:BAAANQABCgEIAQABNQAECggIGAAHAK8RAA==.Anorxorcist:BAAANQADCgYICgABNQAECggIGAAHAK8RAA==.Anorxxorcist:BAABNQAECoEYAAIHAAgKrxEqQwCsAQAHAAgKrxEqQwCsAQAAAA==.Ansky:BAAANQADCggICAAAAA==.Anthraxx:BAAANQADCggJDwABNQAECgUIDAADAAAAAA==.Anyone:BAAANQAECgMIBQABNQAECgYIDgADAAAAAA==.',
Ap='Aporkchop:BAAANQAECgEIAQAAAA==.',
Ar='Archenemyy:BAAANQAECgUIDQAAAA==.Arda:BAABNQAECoEeAAIIAAgKyRycKQC2AgAIAAgKyRycKQC2AgAAAA==.Arelina:BAAANQAECgIIAgAAAA==.Arune:BAAANQAECgYICQAAAA==.',
As='Aspyrx:BAAANQAECgYIEgAAAA==.Assol:BAAANQADCgUIDQAAAA==.Astelan:BAEBNQAECoEZAAIJAAkKbx+CCAA0AwAJAAkKbx+CCAA0AwAAAA==.Astärea:BAAANQAECgYIDgAAAA==.',
Au='Aurorä:BAAANQAECgYICAAAAA==.',
Ay='Ayeola:BAAANQADCgEIAQAAAA==.',
Az='Aztëk:BAAANQAECgIIAgAAAA==.',
Ba='Bachaterah:BAAANQADCgEIAQAAAA==.Baddawg:BAAANQAECgEIAQAAAA==.Baeldaeg:BAAANQAECgUIBQAAAA==.Bahahahamut:BAAANQAECgcIDQABNQAECgUIBQADAAAAAA==.Bannett:BAAANQAECgUIBwAAAA==.Baoboi:BAAANQADCgQIBAAAAA==.Bashing:BAAANQADCggICAABNQAECgkJGwAHANEbAA==.Bauce:BAAANQADCgQIBAAAAA==.Baxterevo:BAAANQAECgUICgAAAA==.Baybx:BAAANQABCgUIBgAAAA==.',
Be='Beardgrim:BAAANQADCggICAAAAA==.Beefyweefy:BAAANQADCggIDQABNQAECgYIDAADAAAAAA==.Bella:BAAANQAECgUIDAAAAA==.',
Bi='Bianchi:BAAANQAECggIDwAAAA==.Bibleman:BAAANQADCggICAAAAA==.Biddy:BAAANQADCgYIBgAAAA==.Bigbowlp:BAEANQAECgQIBAABNQAFFAYIEwAKANUlAA==.Bigchungus:BAAANQADCgYIBgAAAA==.Bigguns:BAAANQAECgEJAQAAAA==.Bigpumpa:BAAANQAECgQIBAAAAA==.Billygoatgrf:BAAANQAECgYICwAAAA==.',
Bl='Blackvomit:BAAANQAECgIIAgAAAA==.Blakkbeard:BAABNQAECoEhAAILAAkK5h77BQAFAwALAAkK5h77BQAFAwAAAA==.Blazefort:BAAANQAFFAMIBAAAAA==.Blightmommie:BAAANQAECgUIBgAAAA==.Blitzeye:BAABNQAECoEdAAIMAAgKjRN3BABOAgAMAAgKjRN3BABOAgAAAA==.Bludskal:BAAANQADCgYIBgABNQAECgkJGwAHANEbAA==.Bløod:BAAANQABCgUIBQAAAA==.',
Bo='Bolger:BAAANQADCgMIAwAAAA==.Bonix:BAAANQADCgIIBAAAAA==.Boozeftw:BAAANQADCgUIBQAAAA==.Bowjobdamage:BAAANQADCgMIAwAAAA==.',
Br='Braincell:BAAANQAECgUIEgABNQAECgUIBQADAAAAAA==.Breemonic:BAAANQAECgcIEQAAAA==.Brewdie:BAAANQADCgUIBgAAAA==.Brrooks:BAAANQADCggICAAAAA==.Bruce:BAABNQAECoEcAAQNAAkKuxzZQgCHAgANAAkK1xvZQgCHAgAOAAgKghZXDQAFAgAKAAEKpiZHHgB0AAAAAA==.',
Bu='Bubblekush:BAAANQAECgIIAgAAAA==.Bubbleøseven:BAAANQADCgQIBAAAAA==.Bullshifter:BAAANQADCgQIBQAAAA==.Burgleslight:BAAANQABCgEIAQAAAA==.Butturz:BAAANQAECgQIBwAAAA==.',
['Bø']='Bønecrusher:BAAANQABCgEIAQAAAA==.',
Ca='Cabala:BAAANQADCgcIGAAAAA==.Cailleach:BAAANQAECgIJAgAAAA==.Cainz:BAAANQAECgQIBAAAAA==.',
Ce='Celeryman:BAAANQAECgYIEAAAAA==.Centuro:BAAANQAECgEIAQAAAA==.',
Ch='Chobi:BAABNQAECoEZAAIPAAkKDyUBAQDGAwAPAAkKDyUBAQDGAwAAAA==.',
Ci='Cinnamen:BAABNQAECoEYAAIQAAgKbhxaCwClAgAQAAgKbhxaCwClAgAAAA==.',
Cl='Claudine:BAAANQAECgQICQABNQAECgYICgADAAAAAA==.Clearstoned:BAAANQADCgUIBQABNQAECgkJJQABAIQeAA==.',
Co='Coaa:BAAANQAECgYIDAAAAA==.Colossus:BAAANQAECgUIEAAAAA==.Contrap:BAABNQAECoEdAAIIAAgKwBtkNACLAgAIAAgKwBtkNACLAgAAAA==.Coolbreeze:BAAANQAECgUICAAAAA==.Corpsgrinder:BAAANQAFFAEIAgAAAA==.',
Cr='Crashöut:BAAANQADCgIIAgAAAA==.Crysix:BAAANQABCgQIBAAAAA==.',
Cz='Cz:BAAANQADCgQIBAAAAA==.Czera:BAAANQADCgMIAwAAAA==.',
Da='Dahialkahina:BAAANQADCgEIAQAAAA==.Damagenpayne:BAAANQABCgEIAQAAAA==.Darkmeadow:BAAANQAECgQICQAAAA==.Dastard:BAABNQAECoEcAAIRAAkK4BkqIwDCAgARAAkK4BkqIwDCAgAAAA==.',
De='Deadlock:BAAANQAECgEIAgAAAA==.Deadplank:BAAANQAECgUICwAAAA==.Deathlyfrost:BAAANQADCggICAAAAA==.Deftonia:BAAANQAECgQIBgAAAA==.Degenerate:BAAANQADCgYICAAAAA==.Dementïa:BAAANQAECggIEwAAAA==.Demonbläde:BAAANQADCgcIBwAAAA==.Dethany:BAAANQAECgUICQABNQAECgYICgADAAAAAA==.Devondric:BAABNQAECoEjAAMSAAgKDR21IgCqAgASAAgKDR21IgCqAgATAAEKeQbgJAAtAAAAAA==.Devotion:BAAANQADCgUJBQABNQAFFAMIBwAEANsJAA==.Devotional:BAACNQAFFIEHAAIEAAMK2wllEADfAAAEAAMK2wllEADfAAA1AAQKgS0AAgQACQqXHAwUAAsDAAQACQqXHAwUAAsDAAAA.',
Di='Diekuh:BAAANQAECgEIAQAAAA==.Diivinity:BAAANQABCgQIBAABNQAECggIIQAFALQZAA==.Dimepiece:BAAANQADCgUIBwAAAA==.Dithi:BAAANQADCgQIBAAAAA==.Divinaputits:BAAANQAECgcJCgAAAA==.',
Dm='Dmatch:BAAANQAECgQIBgAAAA==.',
Do='Docholigay:BAAANQAECgEIAQAAAA==.Dojoh:BAAANQADCgMIAwAAAA==.Dommiemommie:BAAANQAECgQICgABNQAECgUIBgADAAAAAA==.Doozpal:BAABNQAECoEoAAIEAAkKVBaIIwCsAgAEAAkKVBaIIwCsAgAAAA==.Dorinspins:BAEBNQAECoEYAAINAAkK7xB3ZAAYAgANAAkK7xB3ZAAYAgAAAA==.Downset:BAAANQADCgcIBwAAAA==.',
Dr='Drakonman:BAAANQAECgIIAgAAAA==.Draynen:BAABNQAECoEZAAMLAAkKMB+6BwDXAgALAAgKZh66BwDXAgAUAAIKfAtWzAB5AAAAAA==.Drbanner:BAAANQADCgUIBQAAAA==.Drboom:BAAANQAECgIIAgAAAA==.Drezd:BAABNQAECoEhAAIVAAkK2QwIJADnAQAVAAkK2QwIJADnAQAAAA==.',
Du='Duck:BAAANQADCgYIDQABNQAECgIIAQADAAAAAA==.Dulcïnea:BAAANQAECgEIAQABNQAECggIEwADAAAAAA==.Dumpymilk:BAAANQADCggIGQABNQAECgUIBQADAAAAAA==.',
Ea='Eao:BAABNQAECoEcAAIIAAgKvwpyZAD2AQAIAAgKvwpyZAD2AQAAAA==.',
Ed='Edrana:BAAANQADCgYIBgABNQAECgIIAgADAAAAAA==.',
Eh='Ehvyn:BAAANQADCggICgABNQAECgQICAADAAAAAA==.',
El='Elitistjerk:BAAANQADCgEIAQAAAA==.Ellisis:BAAANQAECgUIDgAAAA==.',
Em='Emriq:BAAANQAECgUIEAAAAA==.',
En='Enmai:BAABNQAECoEWAAICAAcKywyqfACRAQACAAcKywyqfACRAQAAAA==.',
Ep='Epiphany:BAAANQAECgYICgAAAA==.',
Er='Eraylina:BAAANQAECgUIDAAAAA==.Ertivoker:BAAANQADCggICAABNQAECgYICwADAAAAAA==.',
Eu='Eugima:BAAANQADCgUIBQAAAA==.Eulogy:BAABNQAECoEcAAIJAAgKexg9GABMAgAJAAgKexg9GABMAgAAAA==.',
Ev='Evangelise:BAAANQADCgEIAQAAAA==.Eveille:BAAANQABCgIIAgAAAA==.',
Ex='Exxitus:BAAANQAECgUIBwAAAA==.',
Fa='Faerielana:BAEANQAECgYIBgABNQAECgcIEAADAAAAAA==.Faith:BAAANQAECgMIBgAAAA==.Falsoqt:BAAANQAECgYICQAAAA==.Fatblackcow:BAAANQADCgEIAQAAAA==.Fatgum:BAEANQADCgQIBAABNQAFFAYIEwAEAGcaAA==.',
Fe='Fecalmatters:BAAANQADCggIEgAAAA==.Felachio:BAAANQAECgYIEgAAAA==.',
Fj='Fjörgyn:BAACNQAFFIETAAIRAAcKgRzSAACtAgARAAcKgRzSAACtAgA1AAQKgSIAAhEACQrWI5oIAJADABEACQrWI5oIAJADAAAA.',
Fl='Flankster:BAAANQAECgMIBAAAAA==.Flanksterr:BAAANQAECgIIAwAAAA==.',
Fo='Fork:BAABNQAECoEfAAIWAAkKnyPABAB3AwAWAAkKnyPABAB3AwAAAA==.Forsetí:BAAANQADCgUIBQAAAA==.Fozziedaburr:BAABNQAECoEbAAMXAAkKbxrJDADKAgAXAAkKbxrJDADKAgAYAAQKVRasWgAVAQAAAA==.',
Fr='Frasierkrane:BAAANQADCgQIBwAAAA==.Frontmage:BAAANQAECgcIDQAAAA==.',
Ft='Ftfk:BAAANQADCggIFgABNQAECgYIEgADAAAAAA==.',
Ga='Galie:BAABNQAECoEdAAMYAAgKEBP9MAATAgAYAAgKEBP9MAATAgAPAAUK0wtCJgDYAAAAAA==.Galiè:BAAANQADCgUICQAAAA==.Garrahoth:BAAANQAECgYIDAAAAA==.',
Ge='Gekk:BAAANQAECgYIEgAAAA==.',
Gi='Giaus:BAABNQAECoEcAAIBAAgK7xsqXwCTAgABAAgK7xsqXwCTAgAAAA==.Girby:BAAANQADCgcIBwAAAA==.',
Gl='Glaaive:BAAANQADCgEIAQAAAA==.Glimmerwisp:BAAANQAECgYIEgAAAA==.',
Go='Gobzilla:BAABNQAECoEWAAIUAAgKWBF2VQC/AQAUAAgKWBF2VQC/AQAAAA==.Gonn:BAAANQADCgUIBQAAAA==.Goub:BAAANQAECgQIBQAAAA==.',
Gr='Grapefantuh:BAAANQAECgEIAgAAAA==.Grapeinator:BAAANQAECgUICwAAAA==.Grimreapr:BAAANQAECgIIAwAAAA==.Grimrieber:BAABNQAECoEZAAMOAAkKgRj/CgA8AgAOAAgKURn/CgA8AgANAAEKBRJSEQE/AAAAAA==.Gromn:BAABNQAECoEkAAIMAAgK+iAUAgD+AgAMAAgK+iAUAgD+AgAAAA==.',
Ha='Hanb:BAAANQADCgYICQABNQAECgIIAgADAAAAAA==.Hashed:BAAANQAECgcIDwAAAA==.Hays:BAAANQAECgUIBQAAAA==.Haysevoker:BAACNQAFFIENAAQZAAUKIxNMDwCaAAAZAAIKmw5MDwCaAAAaAAIKcRYfCQCUAAAbAAEKSSLYBgBgAAA1AAQKgR4ABBsACQodHdcEAGcCABsACAq2HtcEAGcCABoACAoZEq4UAL8BABkAAwrEDZkyALsAAAAA.',
He='Heebb:BAAANQADCggICAAAAA==.Henn:BAAANQAECgIIAgAAAA==.',
Ho='Hobb:BAAANQADCgUIBQAAAA==.Holemilk:BAAANQADCggIEAAAAA==.Holycopter:BAAANQADCggIGgAAAA==.Holymojo:BAABNQAECoEXAAMSAAgKqyISDgAsAwASAAgKqyISDgAsAwATAAEKOQ+QIAA4AAAAAA==.Hoodler:BAEBNQAECoErAAIXAAkK+CTHAQCnAwAXAAkK+CTHAQCnAwABNQAFFAUICgAcAG8hAA==.Hoodlery:BAECNQAFFIEKAAIcAAUKbyHTAQDXAQAcAAUKbyHTAQDXAQA1AAQKgRYAAhwACQpDHM8IANMCABwACQpDHM8IANMCAAAA.Hoofjob:BAABNQAECoEjAAIdAAkKPxw2FABqAgAdAAkKPxw2FABqAgAAAA==.',
Hu='Huskydots:BAABNQAECoEgAAMCAAkKjBQUTwAfAgACAAgKYRQUTwAfAgAeAAMKKw4sQACtAAAAAA==.',
['Hé']='Hércules:BAAANQADCgIIAgAAAA==.',
Ia='Iaell:BAAANQADCgIIAgABNQAECgYIEgADAAAAAA==.',
Ib='Iblastpants:BAAANQAECgMIBgAAAA==.',
Id='Idd:BAAANQAECgIIAgAAAA==.',
Ig='Iggyy:BAAANQAECgUIDwAAAA==.',
In='Inflammo:BAAANQABCgIIAgAAAA==.Insaneness:BAAANQAECgQIBAAAAA==.',
Ir='Irila:BAAANQAECgMJBAAAAA==.',
It='Ithrein:BAAANQADCgYICwAAAA==.Its:BAAANQAECgQIBwABNQAECgYIDgADAAAAAA==.',
Iz='Izumî:BAAANQADCggJEwAAAA==.',
Ja='Jackdáripper:BAAANQABCgYIBgAAAA==.Jakè:BAAANQAECgIIAgAAAA==.Jangosan:BAAANQAECgIIAgABNQAECgkJGwAQAIUNAA==.Jaslen:BAAANQADCgYIBgAAAA==.Jasono:BAAANQADCgUJCQAAAA==.Jaspy:BAABNQAECoEcAAIPAAgK5RsnCQB3AgAPAAgK5RsnCQB3AgAAAA==.',
Je='Jeffdennis:BAABNQAECoEXAAINAAgKORMYcAD1AQANAAgKORMYcAD1AQAAAA==.',
Ji='Jimmybuffler:BAABNQAECoEWAAIEAAgKBRttKQCMAgAEAAgKBRttKQCMAgAAAA==.',
Jo='Jomgpallie:BAAANQAECgcIEAAAAA==.Jonra:BAAANQADCgMIBAAAAA==.Josefbugman:BAAANQAECgQIBgAAAA==.',
Ju='Judykiki:BAAANQAECgEIAQABNQAECgUICwADAAAAAA==.Juecy:BAAANQAECgcIBwAAAA==.Juju:BAAANQAECgUICgAAAA==.Juktal:BAAANQAECgUIDQAAAA==.Justyn:BAAANQAECgUICwAAAA==.',
Ka='Kaeden:BAAANQADCgQJBAAAAA==.Kahlán:BAAANQABCgcICQAAAA==.Kainz:BAAANQAECgIIAgAAAA==.Kaoscontrol:BAAANQADCgUIDgAAAA==.Kazaju:BAABNQAECoEZAAMCAAkKEh9QXAD0AQACAAYKmR1QXAD0AQAeAAMKBSJtKAAfAQAAAA==.',
Ki='Kialorstus:BAABNQAECoEYAAQWAAgKAhcqIwAfAgAWAAgKAhcqIwAfAgAfAAQKUQq2fwCzAAAHAAEK5gTMsAAsAAAAAA==.Kirbo:BAAANQAECgQICAAAAA==.Kitagawa:BAABNQAECoEbAAIHAAkK0RtYFQDUAgAHAAkK0RtYFQDUAgAAAA==.Kitten:BAAANQAECgUICQAAAA==.',
Kl='Klondikecow:BAAANQABCgMIBAAAAA==.',
Ko='Kolakua:BAAANQADCgQIBAAAAA==.Korianth:BAAANQAECgUIBwAAAA==.Korlon:BAAANQADCgYICwAAAA==.Kouw:BAAANQAECgcIDwAAAA==.',
Kr='Kradyn:BAAANQAECgUJBgAAAA==.Kragfoerend:BAABNQAECoEXAAINAAcKuwJLyQDyAAANAAcKuwJLyQDyAAAAAA==.Kramx:BAAANQAECgMIAwAAAA==.Krankenstein:BAAANQAECgYIEgAAAA==.Krankson:BAAANQADCgIIAgAAAA==.Kriix:BAABNQAECoEVAAIgAAYKJyN6GABnAgAgAAYKJyN6GABnAgAAAA==.Krusnik:BAAANQADCgUICAAAAA==.Kruurk:BAAANQADCgQIBAAAAA==.',
Ks='Ksubii:BAAANQAECgYIBwAAAA==.',
Ku='Kuhtta:BAAANQAECgUIBwAAAA==.Kumdobeast:BAAANQAECgQIDQAAAA==.Kuothe:BAAANQAECgUIDwAAAA==.',
Ky='Kyina:BAAANQADCgcIBwAAAA==.Kyotpal:BAAANQADCgIIAgAAAA==.Kyotsas:BAAANQAECggIAwAAAA==.',
La='Lazyriver:BAAANQAECgUICwABNQADCgUIJwADAAAAAA==.',
Le='Legoland:BAAANQAECggIAQAAAA==.Leonphelps:BAAANQADCgYIBwAAAA==.Lesnichii:BAABNQAECoEUAAIYAAcKDhD/PAC9AQAYAAcKDhD/PAC9AQAAAA==.Lewakex:BAAANQAECggIEQAAAA==.Leyninade:BAAANQAECgYIDgAAAA==.',
Li='Lightbrngr:BAABNQAECoEcAAIFAAgKkBtkTABhAgAFAAgKkBtkTABhAgAAAA==.Lihuai:BAAANQADCggIDAAAAA==.Liilpeep:BAAANQAECggICwAAAA==.Lilbertha:BAAANQAECgIIAgAAAA==.Lilchigirl:BAAANQADCgYIBgAAAA==.Lildipster:BAAANQADCggIGAABNQAECgUIBQADAAAAAA==.Lildump:BAAANQAECgUIBwAAAA==.Limitlessone:BAAANQAECgUIDgAAAA==.Lionescanor:BAAANQADCgEIAQAAAA==.Liptonaysti:BAAANQAECgMIBAAAAA==.Lissandine:BAABNQAECoEZAAIhAAgKsRW6CAAKAgAhAAgKsRW6CAAKAgAAAA==.Liya:BAAANQAECgEIAgABNQAFFAMIBwAHAGghAA==.Lizzywizzy:BAAANQADCgYIBgABNQAECgUIBQADAAAAAA==.',
Lo='Locrian:BAAANQABCgQIBAAAAA==.Lokikillz:BAAANQAECgQIBgAAAA==.Lotharn:BAAANQADCgMIAQAAAA==.Lowdy:BAABNQAECoEaAAMNAAcKmRIEigCpAQANAAcKdxEEigCpAQAKAAIK5xdLHQCAAAAAAA==.',
Lu='Luulk:BAAANQAECgUICwAAAA==.',
Ly='Lych:BAAANQAECgQIBAAAAA==.Lyclaw:BAAANQADCgMIAwAAAA==.',
['Lì']='Lìllith:BAAANQAECgUICAAAAA==.Lìvíd:BAAANQADCgIIAgAAAA==.',
Ma='Madoris:BAAANQAECgQICQAAAA==.Magemagerson:BAABNQAECoEWAAIBAAgKdSCwTwC7AgABAAgKdSCwTwC7AgAAAA==.Magnuss:BAAANQAECgcIDQAAAA==.Mahini:BAAANQADCgYIBgAAAA==.Mahnion:BAAANQADCggICAAAAA==.Malleus:BAAANQAECgUICQAAAA==.Mammutos:BAAANQAECgUICwAAAA==.Manifred:BAAANQADCgYJCgAAAA==.Manion:BAABNQAECoEcAAMUAAgKYiApKQCCAgAUAAcKFiApKQCCAgARAAYK6xPpZwCUAQAAAA==.Manipepper:BAAANQAECgUIDAAAAA==.Manippiez:BAAANQAECgMIAwAAAA==.Manipulation:BAAANQADCgEIAQAAAA==.Mannarchy:BAAANQADCgQIBAAAAA==.Mantrà:BAAANQADCggIFAAAAA==.Maplemaga:BAAANQAECggICwAAAA==.Margot:BAAANQADCgYIDAABNQAECgIIAgADAAAAAA==.Masochista:BAACNQAFFIEHAAIHAAMKaCEvDAAtAQAHAAMKaCEvDAAtAQA1AAQKgRgAAgcACQpXJUIEAJwDAAcACQpXJUIEAJwDAAAA.Mastric:BAEBNQAECoEbAAICAAgKZQQukQBWAQACAAgKZQQukQBWAQAAAA==.',
Mc='Mccaffrey:BAAANQAECgYIEgAAAA==.',
Me='Meetch:BAABNQAECoEYAAIfAAgKbBk0LQAlAgAfAAgKbBk0LQAlAgAAAA==.Megdar:BAAANQAECgYIDQAAAA==.Melledreu:BAABNQAECoFIAAMiAAkKxgvXDQCHAQABAAkKtgNl1gCIAQAiAAgKHAzXDQCHAQAAAA==.Mellessan:BAAANQADCggICAAAAA==.Merix:BAABNQAECoEhAAMgAAkKWRzJMAClAQAgAAUKER7JMAClAQAQAAUKVhqXIgCNAQAAAA==.Mestea:BAAANQAECgQICAAAAA==.Mewing:BAAANQAECgQJBAABNQAECggIHgAFAI4iAA==.',
Mi='Miraclemill:BAAANQADCgYIDgAAAA==.Mirra:BAAANQAECgUIDAAAAA==.',
Mo='Mojobtw:BAAANQADCgcIBwAAAA==.Momoshirow:BAAANQADCgQIBAAAAA==.Momø:BAAANQADCgUJBQAAAA==.Monsterboy:BAAANQADCgIIAgAAAA==.Mortamur:BAABNQAECoEXAAIBAAgKehfwggA9AgABAAgKehfwggA9AgAAAA==.Mortelinnos:BAABNQAECoEcAAIjAAgKQyT9CwAhAwAjAAgKQyT9CwAhAwAAAA==.',
My='Mysticguru:BAAANQAECgUIEwAAAA==.Mythrax:BAABNQAECoEbAAMMAAkKUxsaAgD8AgAMAAkKUxsaAgD8AgAVAAIKxwcTXABnAAAAAA==.',
Na='Naradrae:BAAANQAECgMIBAAAAA==.Narodaran:BAAANQAECggIAwAAAA==.Naughtyrawr:BAAANQAECgQIBwAAAA==.',
Ne='Necropete:BAAANQADCgEIAQABNQAFFAEIAQADAAAAAA==.Neondemon:BAAANQAECgEIAQAAAA==.Nevets:BAABNQAECoEeAAIVAAkK9RuXDQDiAgAVAAkK9RuXDQDiAgAAAA==.Nevrs:BAAANQAECgQICAAAAA==.Newworld:BAAANQADCgQICwAAAA==.',
Ni='Nikolajokic:BAAANQAECgEIAQAAAA==.Nimit:BAAANQAECgYIEQAAAA==.',
No='Notzee:BAAANQAECgQIBAAAAA==.Novic:BAABNQAECoEdAAISAAgKBxNVUgDTAQASAAgKBxNVUgDTAQAAAA==.Noxinox:BAAANQADCgYIBgAAAA==.Nozom:BAAANQADCgEIAQABNQAECgYIDAADAAAAAA==.',
Nu='Nualia:BAAANQAECgcIDgAAAA==.',
['Né']='Némésis:BAAANQAECgIIBAAAAA==.',
Oc='Oceaná:BAAANQADCggICAAAAA==.',
Oj='Ojacks:BAAANQAECgMIAwAAAA==.Ojaks:BAAANQAECgcIEwAAAA==.',
Op='Operendi:BAAANQADCgYIBgAAAA==.',
Or='Orbian:BAAANQADCgcIBwAAAA==.Orobus:BAAANQAFFAIIAgAAAA==.',
Os='Oscassey:BAAANQAECgYIEgAAAA==.',
Ox='Oxley:BAAANQAECgYIDwAAAA==.',
Pa='Paladingus:BAAANQAECgcIEwAAAA==.Pandidin:BAABNQAECoEfAAMcAAgKcRaMEQAUAgAcAAgKcRaMEQAUAgAdAAIKOg8jSgBiAAAAAA==.Pauldrons:BAABNQAECoFAAAMfAAkKWBEGNQD2AQAfAAkKUBEGNQD2AQAWAAcKZAZFRAA0AQAAAA==.',
Pe='Peenar:BAAANQAECgcIEQAAAA==.Peenpikmin:BAAANQADCgQJBAAAAA==.Pejorative:BAAANQADCgYIBgAAAA==.',
Ph='Pharlock:BAAANQAECgUICgAAAA==.Pharlòck:BAAANQADCgUIBgABNQAECgUICgADAAAAAA==.Phobia:BAAANQADCggICAABNQAECggIHAAJAHsYAA==.',
Pi='Picklelips:BAAANQADCgQIBQAAAA==.',
Pl='Plankie:BAAANQADCgUICAAAAA==.Plankreaver:BAAANQADCgIIAgAAAA==.Planks:BAAANQAECgIIAgAAAA==.Plankz:BAAANQADCgMIAwAAAA==.',
Po='Pooterdiddle:BAAANQAECgUIBgAAAA==.',
Pr='Priesttess:BAAANQADCgcICgAAAA==.Prohealin:BAABNQAECoEbAAISAAgK6QWMaAB9AQASAAgK6QWMaAB9AQAAAA==.',
Ps='Psarahdactyl:BAAANQADCgIIAgAAAA==.',
Pt='Ptiteagacee:BAAANQAECgYIEQAAAA==.',
Pu='Pufdaddy:BAAANQAECgUICAAAAA==.Puffymüffins:BAAANQADCgIIAgABNQAECgEIDAADAAAAAA==.Pumpkinq:BAABNQAECoE0AAMQAAkK3SEJAwBqAwAQAAkKmiEJAwBqAwAgAAQKWxQuRQAjAQAAAA==.',
Py='Pyre:BAAANQABCgIJAgAAAA==.',
['Pì']='Pìkachu:BAABNQAECoEbAAMBAAgKSh7UXgCUAgABAAgK+xzUXgCUAgAiAAMKphyXGgDXAAAAAA==.',
Ra='Raby:BAAANQADCgYIBgAAAA==.Ragemommie:BAAANQAECgMIBAABNQAECgUIBgADAAAAAA==.Rainer:BAAANQABCgYIBgAAAA==.Rasmus:BAAANQAECgcIDgAAAA==.Raykwan:BAAANQADCgUIBQAAAA==.Rayquaza:BAAANQAECgYIEgAAAA==.Razzmatazz:BAAANQAECgYIEQAAAA==.',
Re='Reddeyes:BAAANQAECgUICwAAAA==.Regulüs:BAAANQAECgYICAAAAA==.Rescue:BAABNQAECoEgAAIBAAgKIhW0jAAmAgABAAgKIhW0jAAmAgAAAA==.Reva:BAEANQAECgEJAQABNQAECgkJGQAJAG8fAA==.',
Ri='Rising:BAAANQADCggIDgAAAA==.',
Ro='Roamin:BAAANQADCggJCAAAAA==.Roasted:BAABNQAECoEbAAIBAAkK/hYnXQCYAgABAAkK/hYnXQCYAgAAAA==.Rockma:BAAANQAECggIAQAAAA==.Rollandburn:BAAANQAECgQIDwAAAA==.Romantacykmc:BAAANQADCgUIBQAAAA==.Roxymigurdia:BAABNQAECoEWAAIIAAgKsCTTDgBGAwAIAAgKsCTTDgBGAwAAAA==.',
Ru='Rufföaddy:BAABNQAECoEcAAIEAAgKAyKlEgAVAwAEAAgKAyKlEgAVAwAAAA==.Rumproast:BAAANQAECgEIAQABNQAECgYIDAADAAAAAA==.Runeesa:BAAANQAECgUICgAAAA==.',
Ry='Rylena:BAABNQAECoEWAAMIAAcKYSA5MgCUAgAIAAcKYSA5MgCUAgAVAAUKjw6jPAAEAQAAAA==.Ryuke:BAAANQADCggICAAAAA==.Ryvalry:BAAANQABCgIIAgAAAA==.',
['Rà']='Ràvenn:BAAANQABCgIIAgABNQAECgUIBgADAAAAAA==.',
['Râ']='Râmên:BAAANQADCgEIAQAAAA==.',
Sa='Sagikos:BAEANQAECgcIEAAAAA==.Sardras:BAABNQAECoEcAAIXAAgKRiQXBgA8AwAXAAgKRiQXBgA8AwAAAA==.Sark:BAAANQAECgYIBwAAAA==.Sathor:BAAANQAECgUICgAAAA==.Sauccyy:BAAANQAECgEIAQAAAA==.Saucecity:BAAANQAECgQIBAAAAA==.Saucyjenkins:BAAANQAECgQICAAAAA==.',
Sc='Scranton:BAAANQADCgcICQAAAA==.',
Se='Sean:BAAANQADCgYIBgAAAA==.Sellout:BAAANQAECgEJAQAAAA==.Semprefi:BAAANQADCgcIBwAAAA==.',
Sh='Shaani:BAAANQAECgEIAQAAAA==.Shace:BAAANQABCgQIBAAAAA==.Shadowfoot:BAAANQADCgUIBQAAAA==.Shadowhut:BAAANQADCgQIBAAAAA==.Shalanot:BAEANQAECgUICgABNQAECgcIEAADAAAAAA==.Shamerific:BAAANQADCgcIBwAAAA==.Shamlus:BAAANQAECgEIAQABNQAECgYIEgADAAAAAA==.Shammooz:BAABNQAECoFKAAILAAkKJByhBQAOAwALAAkKJByhBQAOAwAAAA==.Shinier:BAABNQAECoEdAAIEAAgKjiGgEgAVAwAEAAgKjiGgEgAVAwAAAA==.Shockwoods:BAAANQAECgYIEQAAAA==.Shondo:BAAANQAECgYIBgAAAA==.',
Si='Silversmage:BAAANQAECgUIBwAAAA==.Simohayha:BAAANQADCgIIAgAAAA==.Sixseven:BAAANQAECgUJBQAAAA==.',
Sk='Skeeboo:BAAANQABCgYIBgAAAA==.Skülly:BAAANQAECgQIBAAAAA==.',
Sl='Slappywappy:BAAANQAECgUIEwAAAA==.',
Sm='Smorcin:BAABNQAECoEVAAINAAcKrR8BUgBTAgANAAcKrR8BUgBTAgAAAA==.',
So='Softdeath:BAAANQADCgcIBwAAAA==.Sosoh:BAAANQAECgEIAQABNQAECgUICwADAAAAAA==.',
Sp='Spellnchill:BAAANQAECgUICAAAAA==.Spintor:BAAANQAECgUICQAAAA==.Spookyy:BAAANQADCgMIAwAAAA==.',
Sq='Squidseye:BAAANQAECgYICgAAAA==.',
St='Stainn:BAAANQAECgMIAwAAAA==.Stalk:BAAANQABCgIIAgAAAA==.Steelwaves:BAAANQAECgEJAQAAAA==.Stevelock:BAAANQADCgMIAwABNQADCgcIBwADAAAAAA==.Stoade:BAAANQADCgQJBAAAAA==.Stormfang:BAAANQADCgIIAgAAAA==.Stricker:BAABNQAECoEbAAMXAAkK9R6fBgAzAwAXAAkK9R6fBgAzAwAYAAMKaxqIZgDdAAAAAA==.',
Su='Sukuta:BAAANQAECgIIAgAAAA==.Surious:BAAANQADCgYIBgABNQAECgQIBgADAAAAAA==.',
Sw='Sweettooth:BAAANQAECgEIAQAAAA==.',
Sy='Syphian:BAAANQADCgcIEQAAAA==.',
Ta='Tacoboat:BAABNQAECoEXAAINAAcKqghEnwBrAQANAAcKqghEnwBrAQAAAA==.Taishigi:BAABNQAECoEZAAICAAcKuBFIcQCzAQACAAcKuBFIcQCzAQAAAA==.Tapewyrm:BAAANQAECgUJDAAAAA==.Tatter:BAAANQADCgEIAQAAAA==.',
Te='Tecknique:BAABNQAECoEZAAIHAAgKYAvFTwBxAQAHAAgKYAvFTwBxAQAAAA==.Teedge:BAABNQAECoEsAAMaAAkKWx4EBwDuAgAaAAkK9xwEBwDuAgAbAAQKxhvsCwBAAQAAAA==.Teefz:BAAANQAECgUIBQAAAA==.Terraphy:BAAANQADCgUIBQABNQAECgUJBwADAAAAAA==.',
Th='Thaldric:BAAANQABCgQIBgAAAA==.Thanos:BAAANQADCgMIAwAAAA==.Thatwhitekid:BAAANQAECgUIEAAAAA==.Thepaintrain:BAAANQAECgYIDgAAAA==.Thomasa:BAAANQADCgQIBAAAAA==.Thorodron:BAAANQADCgEJAQAAAA==.Thundera:BAAANQAECgQIDgAAAA==.',
Ti='Tierjar:BAAANQADCgcIBwAAAA==.Timberdoc:BAAANQAECgUICgAAAA==.Timmehh:BAAANQADCggICAABNQAECgkJLAAaAFseAA==.Tindril:BAABNQAECoEgAAQXAAgKiyOJBgA0AwAXAAgKiyOJBgA0AwAPAAQKywvhLQCcAAAYAAEKhAxumAAnAAAAAA==.',
To='Tolan:BAAANQAECgYIDgAAAA==.Toovok:BAAANQADCggICAAAAA==.Totemtartt:BAABNQAECoEgAAIUAAkKTBwKHgC/AgAUAAkKTBwKHgC/AgAAAA==.Toxicai:BAAANQAECgYIDwAAAA==.',
Tr='Trakeus:BAAANQAECgYICAAAAA==.Treyman:BAABNQAECoEZAAIFAAcKwBOlfADOAQAFAAcKwBOlfADOAQAAAA==.Tribune:BAABNQAECoElAAIHAAgKTyC5FgDIAgAHAAgKTyC5FgDIAgABNQAECgkJGQAPAA8lAA==.Trinitree:BAAANQAECgQIBQAAAA==.Trinkler:BAAANQAECgMIBwAAAA==.',
Tu='Tunka:BAAANQADCgcIEAAAAA==.',
Tw='Twist:BAAANQAECgUICwAAAA==.',
Ty='Tychondris:BAABNQAECoEcAAIIAAgKEwl6eQC9AQAIAAgKEwl6eQC9AQAAAA==.',
Ul='Ulsoga:BAAANQAECgYIDgAAAA==.',
Un='Unbórn:BAAANQADCgQIBAAAAA==.Undeadbeast:BAAANQADCgYICgAAAA==.',
Ut='Utica:BAAANQADCgcJCQAAAA==.',
Va='Vaiko:BAAANQADCgMIAwAAAA==.Varibash:BAAANQADCggICAABNQAECggIHAAJAHsYAA==.Vaspara:BAAANQAFFAIIAwAAAA==.',
Ve='Vergalis:BAAANQADCgYIDAAAAA==.',
Vi='Vileknight:BAAANQAECgEIAQAAAA==.Visark:BAAANQADCggICAAAAA==.Visz:BAAANQADCgQIBAAAAA==.Vitlania:BAAANQADCggICAAAAA==.',
Vo='Voidlìlíth:BAAANQAECgYIEAAAAA==.Voidwak:BAAANQAECgUJCgAAAA==.Vorronni:BAAANQAECgYIEQAAAA==.',
Wa='Wardo:BAACNQAFFIEPAAMCAAUKlh3OCAB5AQACAAQKESDOCAB5AQAeAAEKqhPfEgBaAAA1AAQKgS0ABAIACQrxIykNAD8DAAIACArLIykNAD8DAB4ABwrSHFYLAC8CACQAAQrUG/MlADkAAAAA.Warhelm:BAAANQADCgMIAwAAAA==.Wastedtank:BAAANQABCgIIAgAAAA==.',
We='Wellen:BAAANQADCgUICQAAAA==.Werewolf:BAAANQADCggIKgAAAA==.',
Wh='Whitemist:BAAANQAECgEIAQAAAA==.Whitepikmin:BAABNQAECoEYAAMPAAgKRxw7CgBaAgAPAAcKmh07CgBaAgAlAAEK/xK2KgA/AAAAAA==.',
Wi='Wilmer:BAABNQAECoEdAAIIAAgKHSCEJQDIAgAIAAgKHSCEJQDIAgAAAA==.Wily:BAAANQADCggIDgAAAA==.Windowsvista:BAAANQAECgUIBQAAAA==.Winterlock:BAAANQADCgcJDQAAAA==.Wiseguy:BAAANQADCgcICQAAAA==.',
Wo='Wookieweener:BAAANQAECgQIBAABNQAECggIFQANACQXAA==.',
Wr='Wravc:BAAANQAECgMIBAAAAQ==.',
Xa='Xaspen:BAAANQAECgUICAAAAA==.',
Xe='Xerukin:BAAANQADCgYJDAAAAA==.',
Xo='Xoroth:BAAANQAECgUICQAAAA==.',
Ya='Yargonz:BAAANQAECgcIBwAAAA==.Yargz:BAAANQAECgYICwABNQAFFAUIDwAHAEMHAA==.Yargzdk:BAACNQAFFIEPAAIHAAUKQwdCDgAIAQAHAAUKQwdCDgAIAQA1AAQKgSEAAgcACQrOD1dAALsBAAcACQrOD1dAALsBAAAA.',
Ye='Yeyol:BAABNQAECoEWAAIgAAgKXxa7IQAXAgAgAAgKXxa7IQAXAgAAAA==.',
Yo='Yolius:BAAANQAECgQIDgAAAA==.Yoogi:BAAANQAECgEIAQABNQAECgYIDAADAAAAAA==.',
Yu='Yungnetero:BAAANQAECgQIBwAAAA==.Yunikon:BAABNQAECoEfAAQFAAkKmB06JwDxAgAFAAkKDB06JwDxAgAmAAcK7hZQHQClAQAEAAYKihApcwBsAQABNQAECgUIBQADAAAAAA==.',
Za='Zabala:BAAANQABCgQIBAABNQAECgUIEAADAAAAAA==.Zavorotnuk:BAAANQADCggICgAAAA==.',
Ze='Zell:BAAANQAECgUIBwABNQAECgYIEgADAAAAAA==.Zelluss:BAAANQAECgYIEgAAAA==.Zelrin:BAAANQADCgQIBAAAAA==.Zeltari:BAAANQADCgQIBAAAAA==.Zephyrex:BAAANQAECgEIAQAAAA==.Zerkerpete:BAAANQAFFAEIAQAAAA==.',
Zh='Zhaphiria:BAAANQAECgcIBwABNQAECgkJGQALADAfAA==.Zhul:BAAANQAECgUIDQABNQAECgcIEwADAAAAAA==.',
Zi='Zimmy:BAAANQADCgYIBgAAAA==.',
Zo='Zoomies:BAAANQAECgQICAAAAA==.',
Zu='Zuldahn:BAAANQADCgYIBgAAAA==.',
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
