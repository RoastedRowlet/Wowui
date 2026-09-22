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

local lookup = {'Mage-Arcane','Unknown-Unknown','Paladin-Holy','Paladin-Retribution','DeathKnight-Blood','Hunter-BeastMastery','Warrior-Fury','Shaman-Enhancement','Hunter-Survival','Warrior-Arms','Warrior-Protection','Druid-Guardian','Hunter-Marksmanship','Shaman-Elemental','DeathKnight-Frost','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Priest-Holy','Priest-Discipline','Druid-Restoration','Monk-Windwalker','Warlock-Demonology','Warlock-Destruction','DemonHunter-Vengeance','Mage-Frost','Rogue-Assassination','Rogue-Subtlety','DeathKnight-Unholy','Druid-Balance','Shaman-Restoration','Warlock-Affliction','Paladin-Protection',}
local provider = {region='US',realm='Skullcrusher',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abzdh:BAAANQABCgQIBAABNQAECggJGAABAK8jAA==.Abzmage:BAABNQAECoEYAAIBAAgKryOIHwA5AwABAAgKryOIHwA5AwAAAA==.Abzp:BAAANQAECgEIAgAAAA==.',
Ac='Acoreüs:BAEANQAECgQIDwAAAA==.',
Ad='Adramelk:BAAANQAECgIIAgABNQAECgUICgACAAAAAA==.',
Ae='Aed:BAAANQABCgEIAQAAAA==.Aeiay:BAAANQAECgIIAgAAAA==.',
Ai='Aibh:BAAANQADCgUIBwAAAA==.',
Al='Alastorias:BAAANQAECgIIAgAAAA==.Alethice:BAAANQADCgcIBwAAAA==.Alexandrap:BAAANQADCggJDwAAAA==.Allmighto:BAECNQAFFIENAAIDAAYKZxrTAQAlAgADAAYKZxrTAQAlAgA1AAQKgSAAAgMACQozIysDAKMDAAMACQozIysDAKMDAAAA.Alyssaxoo:BAABNQAECoEaAAMDAAgKKhR0NwAcAgADAAgKKhR0NwAcAgAEAAEKVAq3IQEzAAAAAA==.',
An='Androstraz:BAAANQADCggICAAAAA==.Anjkh:BAAANQADCgYIBgAAAA==.Anniesthesia:BAAANQAECgUJBwAAAA==.Anoobyss:BAAANQAECgUIEQAAAA==.Anorexorcist:BAAANQABCgEIAQABNQAECggJFwAFAI8RAA==.Anorxorcist:BAAANQADCgYJCgABNQAECggJFwAFAI8RAA==.Anorxxorcist:BAABNQAECoEXAAIFAAgKjxGuNgC+AQAFAAgKjxGuNgC+AQAAAA==.Ansky:BAAANQADCggICAAAAA==.Anthraxx:BAAANQADCggJDwABNQAECgUIBwACAAAAAA==.Anyone:BAAANQAECgMIAwABNQAECgUICQACAAAAAA==.',
Ar='Archenemyy:BAAANQAECgUICQAAAA==.Arda:BAABNQAECoEZAAIGAAgKQxviIQCyAgAGAAgKQxviIQCyAgAAAA==.Arelina:BAAANQADCgMJAwAAAA==.Arune:BAAANQAECgUICAAAAA==.',
As='Aspyrx:BAAANQAECgUJDAAAAA==.Assol:BAAANQADCgUICgAAAA==.Astelan:BAEANQAECgUICQAAAA==.Astärea:BAAANQAECgQICQAAAA==.',
Au='Aurorä:BAAANQAECgUIBQAAAA==.',
Ay='Ayeola:BAAANQADCgEIAQAAAA==.',
Az='Aztëk:BAAANQAECgIIAgAAAA==.',
Ba='Bachaterah:BAAANQADCgEIAQAAAA==.Baddawg:BAAANQAECgEIAQAAAA==.Baeldaeg:BAAANQADCggIFAAAAA==.Bahahahamut:BAAANQAECgUIBQABNQADCggIFAACAAAAAA==.Bannett:BAAANQAECgUIBwAAAA==.Baoboi:BAAANQADCgQIBAAAAA==.Bauce:BAAANQADCgQIBAAAAA==.Baxterevo:BAAANQAECgMIBQAAAA==.Baybx:BAAANQABCgUIBgAAAA==.',
Be='Beardgrim:BAAANQADCggICAAAAA==.Beefyweefy:BAAANQADCgcIBwABNQAECgUICAACAAAAAA==.Bella:BAAANQAECgQIBwAAAA==.',
Bi='Bianchi:BAAANQAECggJDwAAAA==.Bibleman:BAAANQADCggICAAAAA==.Biddy:BAAANQADCgYIBgAAAA==.Bigbowlp:BAAANQAECgQIBAABNQAFFAYIDQAHABIiAA==.Bigchungus:BAAANQADCgYIBgAAAA==.Bigguns:BAAANQAECgEJAQAAAA==.Bigpumpa:BAAANQAECgQIBAAAAA==.Billygoatgrf:BAAANQAECgYICwAAAA==.',
Bl='Blackvomit:BAAANQAECgIIAgAAAA==.Blakkbeard:BAABNQAECoEeAAIIAAkKIh5tBAAbAwAIAAkKIh5tBAAbAwAAAA==.Blazefort:BAAANQAFFAEIAQAAAA==.Blightmommie:BAAANQAECgUIBgAAAA==.Blitzeye:BAABNQAECoEZAAIJAAcK8BOfBAAMAgAJAAcK8BOfBAAMAgAAAA==.',
Bo='Bolger:BAAANQADCgMIAwAAAA==.Bonix:BAAANQADCgIIBAAAAA==.Boozeftw:BAAANQADCgUIBQAAAA==.Bowjobdamage:BAAANQADCgMIAwAAAA==.',
Br='Braincell:BAAANQAECgUJEQABNQADCggIFAACAAAAAA==.Breemonic:BAAANQAECgcJDwAAAA==.Brewdie:BAAANQADCgUIBgAAAA==.Brrooks:BAAANQADCggICAAAAA==.Bruce:BAABNQAECoEYAAMKAAkK1BpGMwCbAgAKAAkKQxpGMwCbAgALAAgKgharCQAiAgAAAA==.',
Bu='Bubblekush:BAAANQAECgIIAgAAAA==.Bubbleøseven:BAAANQADCgQIBAAAAA==.Bullshifter:BAAANQADCgQIBQAAAA==.Burgleslight:BAAANQABCgEIAQAAAA==.Butturz:BAAANQAECgMIAwAAAA==.',
['Bø']='Bønecrusher:BAAANQABCgEIAQAAAA==.',
Ca='Cabala:BAAANQADCgYJEQAAAA==.Cailleach:BAAANQAECgIJAgAAAA==.Cainz:BAAANQAECgEIAQAAAA==.',
Ce='Celeryman:BAAANQAECgUJDwAAAA==.Centuro:BAAANQAECgEIAQAAAA==.',
Ch='Chobi:BAABNQAECoEZAAIMAAkKDyWmAADPAwAMAAkKDyWmAADPAwAAAA==.',
Ci='Cinnamen:BAAANQAECgcIEAAAAA==.',
Cl='Claudine:BAAANQAECgQIBwAAAA==.Clearstoned:BAAANQADCgUIBQABNQAECggJHwABAIEcAA==.',
Co='Coaa:BAAANQAECgQIBgAAAA==.Colossus:BAAANQAECgUJEAAAAA==.Contrap:BAABNQAECoEWAAIGAAgKnhuHKACTAgAGAAgKnhuHKACTAgAAAA==.Coolbreeze:BAAANQAECgIIAwAAAA==.Corpsgrinder:BAAANQAFFAEJAQAAAA==.Cowbroni:BAAANQAECgUIBgAAAA==.',
Cr='Crashöut:BAAANQADCgIIAgAAAA==.Crysix:BAAANQABCgQIBAAAAA==.',
Cu='Curtland:BAAANQADCgYICwAAAA==.',
Cz='Cz:BAAANQADCgQIBAAAAA==.Czera:BAAANQADCgMIAwAAAA==.',
Da='Dahialkahina:BAAANQADCgEIAQAAAA==.Darkmeadow:BAAANQAECgMIBQAAAA==.Dastard:BAAANQAECgYJEQAAAA==.',
De='Deadlock:BAAANQAECgEJAQAAAA==.Deadplank:BAAANQAECgUIBgAAAA==.Deathlyfrost:BAAANQADCggICAAAAA==.Deftonia:BAAANQAECgQIBgAAAA==.Degenerate:BAAANQADCgYICAAAAA==.Dementïa:BAAANQAECggJDAAAAA==.Demonbläde:BAAANQADCgcIBwAAAA==.Dethany:BAAANQAECgUIBQAAAA==.Devondric:BAAANQAECgYIEwAAAA==.Devotion:BAAANQADCgUJBQABNQAECgkJKgADACgcAA==.Devotional:BAABNQAECoEqAAIDAAkKKBxnEAAIAwADAAkKKBxnEAAIAwAAAA==.',
Di='Diekuh:BAAANQAECgEIAQAAAA==.Diivinity:BAAANQABCgQIBAABNQAECggJGgAEAKIXAA==.Dimepiece:BAAANQADCgUIBwAAAA==.Dithi:BAAANQADCgQIBAAAAA==.Divinaputits:BAAANQAECgcJCgAAAA==.',
Dm='Dmatch:BAAANQAECgMIAwAAAA==.',
Do='Docholigay:BAAANQADCgMIAwAAAA==.Dojoh:BAAANQADCgMIAwAAAA==.Dommiemommie:BAAANQAECgQICgABNQAECgUIBgACAAAAAA==.Doozpal:BAABNQAECoEhAAIDAAgK7BdvJQB4AgADAAgK7BdvJQB4AgAAAA==.Dorinspins:BAEANQAECggJDwAAAA==.Downset:BAAANQADCgcIBwAAAA==.',
Dr='Drakonman:BAAANQAECgIIAgAAAA==.Draynen:BAAANQAECggIDgAAAA==.Drbanner:BAAANQADCgUIBQAAAA==.Drboom:BAAANQAECgIIAgAAAA==.Drezd:BAABNQAECoEfAAINAAcKgg/BJACrAQANAAcKgg/BJACrAQAAAA==.',
Du='Duck:BAAANQADCgQICwABNQAECgEIAQACAAAAAA==.Dulcïnea:BAAANQAECgEIAQABNQAECggJDAACAAAAAA==.Dumpymilk:BAAANQADCggIGQABNQADCggIFAACAAAAAA==.',
Ea='Eao:BAAANQAECgYJEQAAAA==.',
Ed='Edrana:BAAANQADCgYIBgABNQAECgIIAgACAAAAAA==.',
Eh='Ehvyn:BAAANQADCggICgABNQAECgMIBAACAAAAAA==.',
El='Elitistjerk:BAAANQADCgEIAQAAAA==.Ellisis:BAAANQAECgUJCQAAAA==.',
Em='Emriq:BAAANQAECgUJDAAAAA==.',
En='Enmai:BAAANQAECgUJDgAAAA==.',
Ep='Epiphany:BAAANQAECgUJCQAAAA==.',
Er='Eraylina:BAAANQAECgUIBwAAAA==.Ertivoker:BAAANQADCggICAABNQAECgYICwACAAAAAA==.',
Eu='Eulogy:BAAANQAECgYJEQAAAA==.',
Ev='Evangelise:BAAANQADCgEIAQAAAA==.Eveille:BAAANQABCgIIAgAAAA==.',
Ex='Exxitus:BAAANQAECgUIBwAAAA==.',
Fa='Faerielana:BAEANQADCgQIBAABNQAECgcIEAACAAAAAA==.Faith:BAAANQAECgMIBgAAAA==.Falsoqt:BAAANQAECgQIBAAAAA==.Fatblackcow:BAAANQADCgEIAQAAAA==.Fatgum:BAEANQADCgQIBAABNQAFFAYIDQADAGcaAA==.',
Fe='Fecalmatters:BAAANQADCgcIDAAAAA==.Felachio:BAAANQAECgUJDAAAAA==.',
Fj='Fjörgyn:BAACNQAFFIENAAIOAAYKkBl5AQAvAgAOAAYKkBl5AQAvAgA1AAQKgR8AAg4ACQoWIs0KAGYDAA4ACQoWIs0KAGYDAAAA.',
Fl='Flankster:BAAANQAECgIIAgAAAA==.Flanksterr:BAAANQAECgEJAQAAAA==.',
Fo='Fork:BAABNQAECoEYAAIPAAkKHSI4BQBgAwAPAAkKHSI4BQBgAwAAAA==.Fozziedaburr:BAAANQAECgcJEQAAAA==.',
Fr='Frasierkrane:BAAANQADCgQIBwAAAA==.Frontmage:BAAANQAECgYJBgAAAA==.',
Ft='Ftfk:BAAANQADCggIFgABNQAECgYJEQACAAAAAA==.',
Ga='Galie:BAAANQAFFAEIAQAAAA==.Galiè:BAAANQADCgQIBAAAAA==.Garrahoth:BAAANQAECgUICAAAAA==.',
Ge='Gekk:BAAANQAECgUJDAAAAA==.',
Gi='Giaus:BAAANQAECgcJEwAAAA==.Girby:BAAANQADCgcIBwAAAA==.',
Gl='Glaaive:BAAANQADCgEIAQAAAA==.Glimmerwisp:BAAANQAECgMJBAAAAA==.',
Go='Gobzilla:BAAANQAECgYIDwAAAA==.Gonn:BAAANQADCgUIBQAAAA==.Goub:BAAANQAECgQIBQAAAA==.',
Gr='Grapefantuh:BAAANQAECgEIAgAAAA==.Grapeinator:BAAANQAECgQIBgAAAA==.Grimreapr:BAAANQAECgEIAQAAAA==.Grimrieber:BAAANQAECgcJDwAAAA==.Gromn:BAABNQAECoEdAAIJAAgKIh1kAgCuAgAJAAgKIh1kAgCuAgAAAA==.',
Ha='Hanb:BAAANQADCgUIBQABNQADCggJDwACAAAAAA==.Hashed:BAAANQAECgcICAAAAA==.Hays:BAAANQAECgUIBQAAAA==.Haysevoker:BAACNQAFFIEIAAQQAAUKThFODACZAAAQAAIKBQpODACZAAARAAIKmhOmBwCVAAASAAEKtBwCBQBeAAA1AAQKgRwABBIACQrkGQsFACoCABIABwqwHgsFACoCABEACAoZEqsRANsBABAAAwrEDV4sAL0AAAAA.',
He='Heebb:BAAANQADCggICAAAAA==.Henn:BAAANQAECgIIAgAAAA==.',
Ho='Hobb:BAAANQADCgUIBQAAAA==.Holemilk:BAAANQADCggIEAAAAA==.Holycopter:BAAANQADCggIGgAAAA==.Holymojo:BAABNQAECoEXAAMTAAgKqyIPCgA3AwATAAgKqyIPCgA3AwAUAAEKOQ+9GwA4AAAAAA==.Hoodler:BAEBNQAECoEhAAIVAAkKVCRpAgCCAwAVAAkKVCRpAgCCAwABNQAFFAQJBAACAAAAAA==.Hoodlery:BAEANQAFFAQJBAAAAA==.Hoofjob:BAABNQAECoEiAAIWAAkK+BuQDgCTAgAWAAkK+BuQDgCTAgAAAA==.',
Hu='Huskydots:BAABNQAECoEYAAMXAAkK2RP/QAAZAgAXAAgKlxP/QAAZAgAYAAMKKw5NOgC0AAAAAA==.',
['Hé']='Hércules:BAAANQADCgIIAgAAAA==.',
Ia='Iaell:BAAANQADCgIIAgABNQAECgUJDAACAAAAAA==.',
Ib='Iblastpants:BAAANQAECgMJBAAAAA==.',
Id='Idd:BAAANQAECgIIAgAAAA==.',
Ig='Iggyy:BAAANQAECgUJCgAAAA==.',
In='Inflammo:BAAANQABCgEIAQAAAA==.Insaneness:BAAANQADCggIFQAAAA==.',
Ir='Irila:BAAANQAECgMJBAAAAA==.',
It='Ithrein:BAAANQADCgYICwAAAA==.Its:BAAANQAECgMIAwABNQAECgUICQACAAAAAA==.',
Iz='Izumî:BAAANQADCggJEwAAAA==.',
Ja='Jakè:BAAANQAECgIIAgAAAA==.Jaslen:BAAANQADCgYIBgAAAA==.Jasono:BAAANQADCgUJCQAAAA==.Jaspy:BAAANQAECgYJEQAAAA==.',
Je='Jeffdennis:BAABNQAECoEWAAIKAAgKeBLTXQD5AQAKAAgKeBLTXQD5AQAAAA==.',
Ji='Jimmybuffler:BAAANQAECgYICwAAAA==.',
Jo='Jomgpallie:BAAANQAECgYICQAAAA==.Jonra:BAAANQADCgMIBAAAAA==.Josefbugman:BAAANQAECgIIAgAAAA==.',
Ju='Judykiki:BAAANQADCgcICwAAAA==.Juju:BAAANQAECgIIBQAAAA==.Juktal:BAAANQAECgQICAAAAA==.Justyn:BAAANQAECgQIBgAAAA==.',
Ka='Kaeden:BAAANQADCgQJBAAAAA==.Kahlán:BAAANQABCgcJCQAAAA==.Kainz:BAAANQAECgIIAgAAAA==.Kaoscontrol:BAAANQADCgUIDgAAAA==.Kazaju:BAABNQAECoEZAAMXAAkKEh8+RQAIAgAXAAYKmR0+RQAIAgAYAAMKBSI7JQAkAQAAAA==.',
Ki='Kialorstus:BAAANQAECgcJEAAAAA==.Kirbo:BAAANQAECgMJBAAAAA==.Kitagawa:BAAANQAECgUICwAAAA==.Kitten:BAAANQAECgUJBQAAAA==.',
Kl='Klondikecow:BAAANQABCgMIBAAAAA==.',
Ko='Kolakua:BAAANQADCgQIBAAAAA==.Korianth:BAAANQAECgUIBwAAAA==.Korlon:BAAANQADCgYICwAAAA==.Kouw:BAAANQAECgYJCAAAAA==.',
Kr='Kradyn:BAAANQAECgUJBgAAAA==.Kragfoerend:BAAANQAECgQICAAAAA==.Krankenstein:BAAANQAECgUJDAAAAA==.Krankson:BAAANQADCgIIAgAAAA==.Kriix:BAAANQAECgUIDwAAAA==.Krusnik:BAAANQADCgUICAAAAA==.Kruurk:BAAANQADCgQIBAAAAA==.',
Ks='Ksubii:BAAANQAECgEIAQAAAA==.',
Ku='Kuhtta:BAAANQAECgIJAgAAAA==.Kumdobeast:BAAANQAECgQIDQAAAA==.Kuothe:BAAANQAECgQICgAAAA==.',
Ky='Kyina:BAAANQADCgcIBwAAAA==.Kyotpal:BAAANQADCgIJAgAAAA==.',
La='Lazyriver:BAAANQAECgUIBgABNQADCgUIIQACAAAAAA==.',
Le='Legoland:BAAANQAECggIAQAAAA==.Leonphelps:BAAANQADCgYIBwAAAA==.Lesnichii:BAAANQAECgYJDQAAAA==.Lewakex:BAAANQAECggIDgAAAA==.Leyninade:BAAANQAECgYICgAAAA==.',
Li='Lightbrngr:BAABNQAECoEXAAIEAAgKWhquPABgAgAEAAgKWhquPABgAgAAAA==.Lihuai:BAAANQADCggIDAAAAA==.Liilpeep:BAAANQAECggICQAAAA==.Lilbertha:BAAANQAECgIIAgAAAA==.Lilchigirl:BAAANQADCgYIBgAAAA==.Lildipster:BAAANQADCggIEgABNQADCggIFAACAAAAAA==.Lildump:BAAANQAECgIIAgABNQAECgYICwACAAAAAA==.Limitlessone:BAAANQAECgQJCAAAAA==.Lionescanor:BAAANQADCgEIAQAAAA==.Liptonaysti:BAAANQAECgEIAQAAAA==.Lissandine:BAABNQAECoEXAAIZAAgKUxVzBgAZAgAZAAgKUxVzBgAZAgAAAA==.Liya:BAAANQAECgEIAQABNQAECgkJFwAFAFclAA==.Lizzywizzy:BAAANQADCgYIBgABNQADCggIFAACAAAAAA==.',
Lo='Locrian:BAAANQABCgQIBAAAAA==.Lokikillz:BAAANQAECgMIAwAAAA==.Lotharn:BAAANQADCgMIAQAAAA==.Lowdy:BAAANQAECgQIDwAAAA==.',
Lu='Luulk:BAAANQAECgUIBgAAAA==.',
Ly='Lych:BAAANQADCgYIBgAAAA==.Lyclaw:BAAANQADCgMIAwAAAA==.',
['Lì']='Lìllith:BAAANQAECgQJBQAAAA==.',
Ma='Madoris:BAAANQAECgQIBQAAAA==.Magemagerson:BAABNQAECoEVAAIBAAgKdSBPOwDaAgABAAgKdSBPOwDaAgAAAA==.Magnuss:BAAANQAECgYJDAAAAA==.Mahini:BAAANQADCgYIBgAAAA==.Mahnion:BAAANQADCggICAAAAA==.Malleus:BAAANQAECgMIBAAAAA==.Mammutos:BAAANQAECgQIBgAAAA==.Manifred:BAAANQADCgYJCgAAAA==.Manion:BAAANQAECgYIEQAAAA==.Manipepper:BAAANQAECgUIBwAAAA==.Manippiez:BAAANQAECgMIAwAAAA==.Manipulation:BAAANQADCgEIAQAAAA==.Mannarchy:BAAANQADCgQIBAAAAA==.Mantrà:BAAANQADCggIFAAAAA==.Maplemaga:BAAANQAECggICwAAAA==.Margot:BAAANQADCgYIDAABNQADCggJDwACAAAAAA==.Masochista:BAABNQAECoEXAAIFAAkKVyXlAgCvAwAFAAkKVyXlAgCvAwAAAA==.Mastavas:BAAANQAECgEIAQABNQAECgQIBgACAAAAAA==.Mastric:BAEANQAECgYJEQAAAA==.',
Mc='Mccaffrey:BAAANQAECgUJDAAAAA==.',
Me='Meetch:BAAANQAECgcJEQAAAA==.Megdar:BAAANQAECgQIBwAAAA==.Melledreu:BAABNQAECoE4AAMaAAgKJwyWCgCYAQAaAAgKHAyWCgCYAQABAAgKiAJF4ABBAQAAAA==.Mellessan:BAAANQADCggICAAAAA==.Merix:BAABNQAECoEgAAMbAAkKRhwQJQCwAQAbAAUK7x0QJQCwAQAcAAUKVholHgCfAQAAAA==.Mestea:BAAANQAECgMIBAAAAA==.Mewing:BAAANQAECgQJBAABNQAECgcICwACAAAAAA==.',
Mi='Miraclemill:BAAANQADCgYIDgAAAA==.Mirra:BAAANQAECgQIBwAAAA==.',
Mo='Mojobtw:BAAANQADCgcIBwAAAA==.Momø:BAAANQADCgUJBQAAAA==.Monsterboy:BAAANQADCgIIAgAAAA==.Mortamur:BAABNQAECoEWAAIBAAcKcRdVgwAPAgABAAcKcRdVgwAPAgAAAA==.Mortelinnos:BAAANQAECgYJEQAAAA==.',
My='Mysticguru:BAAANQAECgQJDgAAAA==.Mythrax:BAABNQAECoEXAAMJAAgKQhwtAgDDAgAJAAgKQhwtAgDDAgANAAIKxwenTgBqAAAAAA==.',
Na='Naradrae:BAAANQAECgEIAQAAAA==.Narodaran:BAAANQAECgIIAwAAAA==.Naughtyrawr:BAAANQAECgMIAwAAAA==.',
Ne='Neondemon:BAAANQADCgEJAQAAAA==.Nevets:BAABNQAECoEYAAINAAkKihqtDQDMAgANAAkKihqtDQDMAgAAAA==.Nevrs:BAAANQAECgQJBAAAAA==.Newworld:BAAANQADCgQJCwAAAA==.',
Ni='Nikolajokic:BAAANQAECgEIAQAAAA==.Nimit:BAAANQAECgUJCwAAAA==.',
No='Notzee:BAAANQAECgEIAQAAAA==.Novic:BAABNQAECoEWAAITAAcKNhXVTACqAQATAAcKNhXVTACqAQAAAA==.Nozom:BAAANQADCgEIAQABNQAECgUICAACAAAAAA==.',
Nu='Nualia:BAAANQAECgYJDgAAAA==.',
['Né']='Némésis:BAAANQAECgEIAgAAAA==.',
Oc='Oceaná:BAAANQADCggICAAAAA==.',
Oj='Ojacks:BAAANQAECgMIAwAAAA==.Ojaks:BAAANQAECgcIEwAAAA==.',
Op='Operendi:BAAANQADCgYIBgAAAA==.',
Or='Orbian:BAAANQADCgcIBwAAAA==.Orobus:BAAANQAFFAEJAQAAAA==.',
Os='Oscassey:BAAANQAECgUJDAAAAA==.',
Ox='Oxley:BAAANQAECgUJCQAAAA==.',
Pa='Paladingus:BAAANQAECgYIEQAAAA==.Pandidin:BAAANQAECgcJEwAAAA==.Pauldrons:BAABNQAECoE6AAMdAAgKPQ8NMADwAQAdAAgKNQ8NMADwAQAPAAcKZAbcNABOAQAAAA==.',
Pe='Peenar:BAAANQAECgYICgAAAA==.Peenpikmin:BAAANQADCgQJBAAAAA==.Pejorative:BAAANQADCgYIBgAAAA==.',
Ph='Pharlock:BAAANQAECgQIBQAAAA==.Pharlòck:BAAANQADCgUIBQABNQAECgQIBQACAAAAAA==.Phobia:BAAANQADCggICAABNQAECgYJEQACAAAAAA==.',
Pi='Picklelips:BAAANQADCgEJAQAAAA==.',
Pl='Plankie:BAAANQADCgUICAAAAA==.Plankreaver:BAAANQADCgIIAgAAAA==.Planks:BAAANQAECgIIAgAAAA==.Plankz:BAAANQADCgMIAwAAAA==.',
Po='Pooterdiddle:BAAANQAECgUIBgAAAA==.',
Pr='Priesttess:BAAANQADCgYICQAAAA==.Prohealin:BAAANQAECgcJEwAAAA==.',
Ps='Psarahdactyl:BAAANQADCgIIAgAAAA==.',
Pt='Ptiteagacee:BAAANQAECgUIDAAAAA==.',
Pu='Pufdaddy:BAAANQAECgIIAwAAAA==.Puffymüffins:BAAANQADCgIIAgABNQAECgEICQACAAAAAA==.Pumpkinq:BAABNQAECoEmAAMcAAkKLyGyAgBxAwAcAAkKLyGyAgBxAwAbAAQKFg7PPAD8AAAAAA==.',
Py='Pyre:BAAANQABCgIJAgAAAA==.',
['Pì']='Pìkachu:BAAANQAECgYJEAAAAA==.',
Ra='Ragemommie:BAAANQAECgMIBAABNQAECgUIBgACAAAAAA==.Rainer:BAAANQABCgYIBgAAAA==.Rasmus:BAAANQAECgUIBwAAAA==.Raykwan:BAAANQADCgUIBQAAAA==.Rayquaza:BAAANQAECgYJEQAAAA==.Razzmatazz:BAAANQAECgUJCwAAAA==.',
Re='Reddeyes:BAAANQAECgQIBgAAAA==.Regulüs:BAAANQAECgUJBQAAAA==.Rescue:BAABNQAECoEZAAIBAAgKsRQGcgA9AgABAAgKsRQGcgA9AgAAAA==.Reva:BAEANQAECgEJAQABNQAECgUICQACAAAAAA==.',
Ri='Rising:BAAANQADCggIDgAAAA==.',
Ro='Roamin:BAAANQADCggJCAAAAA==.Roasted:BAABNQAECoEZAAIBAAgKihgTWgB+AgABAAgKihgTWgB+AgAAAA==.Rockma:BAAANQAECggIAQAAAA==.Rollandburn:BAAANQAECgQIDwAAAA==.Roxymigurdia:BAAANQAECgcIDgAAAA==.',
Ru='Rufföaddy:BAAANQAECgYJEQAAAA==.Rumproast:BAAANQAECgEIAQABNQAECgUICAACAAAAAA==.Runeesa:BAAANQAECgQIBQAAAA==.',
Ry='Rylena:BAAANQAECgUJDgAAAA==.Ryuke:BAAANQADCggICAAAAA==.Ryvalry:BAAANQABCgIIAgAAAA==.',
['Rà']='Ràvenn:BAAANQABCgIIAgABNQAECgIJAgACAAAAAA==.',
['Râ']='Râmên:BAAANQADCgEIAQAAAA==.',
Sa='Sagikos:BAEANQAECgcIEAAAAA==.Sardras:BAAANQAECgYJEQAAAA==.Sark:BAAANQAECgYIBwAAAA==.Sathor:BAAANQAECgUICgAAAA==.Saucecity:BAAANQAECgQIBAAAAA==.Saucyjenkins:BAAANQAECgMJBAAAAA==.',
Sc='Scranton:BAAANQADCgcICQAAAA==.',
Se='Sellout:BAAANQAECgEJAQAAAA==.Semprefi:BAAANQADCgcIBwAAAA==.',
Sh='Shaani:BAAANQAECgEIAQAAAA==.Shace:BAAANQABCgQIBAAAAA==.Shadowfoot:BAAANQADCgUIBQAAAA==.Shadowhut:BAAANQADCgQIBAAAAA==.Shalanot:BAEANQAECgUICgABNQAECgcIEAACAAAAAA==.Shamerific:BAAANQADCgcIBwAAAA==.Shamlus:BAAANQAECgEIAQABNQAECgYIEgACAAAAAA==.Shammooz:BAABNQAECoE6AAIIAAgKFB36BgDJAgAIAAgKFB36BgDJAgAAAA==.Shinier:BAABNQAECoEXAAIDAAcKziE0GwC4AgADAAcKziE0GwC4AgAAAA==.Shockwoods:BAAANQAECgYIDQAAAA==.',
Si='Silversmage:BAAANQAECgIJAgAAAA==.Simohayha:BAAANQADCgIIAgAAAA==.Sixseven:BAAANQAECgUJBQAAAA==.',
Sk='Skeeboo:BAAANQABCgYIBgAAAA==.Skülly:BAAANQAECgQIBAAAAA==.',
Sl='Slappywappy:BAAANQAECgQJDgAAAA==.',
Sm='Smorcin:BAAANQAECgYJDgAAAA==.',
So='Softdeath:BAAANQADCgcIBwAAAA==.',
Sp='Spellnchill:BAAANQAECgMJAwAAAA==.Spintor:BAAANQAECgQIBQAAAA==.Spookyy:BAAANQADCgMIAwAAAA==.',
Sq='Squidseye:BAAANQAECgYICgAAAA==.',
St='Stalk:BAAANQABCgIIAgAAAA==.Steelwaves:BAAANQAECgEJAQAAAA==.Stevelock:BAAANQADCgMIAwABNQADCgcIBwACAAAAAA==.Stoade:BAAANQADCgQJBAAAAA==.Stormfang:BAAANQADCgIIAgAAAA==.Stricker:BAAANQAECgYIDgAAAA==.',
Su='Sukuta:BAAANQAECgIIAgAAAA==.Surious:BAAANQADCgYIBgABNQAECgQIBgACAAAAAA==.',
Sw='Sweettooth:BAAANQADCgQIBgAAAA==.',
Sy='Syphian:BAAANQADCgcJEQAAAA==.',
Ta='Tacoboat:BAAANQAECgUICwAAAA==.Taishigi:BAAANQAECgYIEAAAAA==.Tapewyrm:BAAANQAECgUJDAAAAA==.Tatter:BAAANQADCgEIAQAAAA==.',
Te='Tecknique:BAABNQAECoEXAAIFAAgKRwuURAB1AQAFAAgKRwuURAB1AQAAAA==.Teedge:BAABNQAECoEiAAMRAAkKXhxUBwDXAgARAAkKCBtUBwDXAgASAAMKBRlODQDhAAAAAA==.',
Th='Thaldric:BAAANQABCgQIBgAAAA==.Thanos:BAAANQADCgMIAwAAAA==.Thatwhitekid:BAAANQAECgUICwAAAA==.Thepaintrain:BAAANQAECgUICQAAAA==.Thomasa:BAAANQADCgQJBAAAAA==.Thorodron:BAAANQADCgEJAQAAAA==.Thundera:BAAANQAECgQIDgAAAA==.',
Ti='Tierjar:BAAANQADCgcIBwAAAA==.Timberdoc:BAAANQAECgQIBQAAAA==.Timmehh:BAAANQADCggICAABNQAECgkJIgARAF4cAA==.Tindril:BAABNQAECoEYAAQVAAgKPSHmBgALAwAVAAgKPSHmBgALAwAMAAQKywtIIwCiAAAeAAEKhAzYhQAsAAAAAA==.',
To='Tolan:BAAANQAECgUICgAAAA==.Toovok:BAAANQADCggICAAAAA==.Totemtartt:BAABNQAECoEXAAIfAAgKJRwnKABjAgAfAAgKJRwnKABjAgAAAA==.Toxicai:BAAANQAECgUJCQAAAA==.',
Tr='Trakeus:BAAANQAECgQIBAAAAA==.Treyman:BAAANQAECgcIEgAAAA==.Tribune:BAABNQAECoEkAAIFAAgKTyCLEQDaAgAFAAgKTyCLEQDaAgABNQAECgkJGQAMAA8lAA==.Trinitree:BAAANQAECgEIAQAAAA==.Trinkler:BAAANQAECgMIBgAAAA==.',
Tu='Tunka:BAAANQADCgcIEAAAAA==.',
Tw='Twist:BAAANQAECgQIBgAAAA==.',
Ty='Tychondris:BAAANQAECgYJEQAAAA==.',
Ul='Ulsoga:BAAANQAECgQJCAAAAA==.',
Un='Unbórn:BAAANQADCgQIBAAAAA==.Undeadbeast:BAAANQADCgYICgAAAA==.',
Ut='Utica:BAAANQADCgcJCQAAAA==.',
Va='Vaiko:BAAANQADCgMIAwAAAA==.Varibash:BAAANQADCggICAABNQAECgYJEQACAAAAAA==.Vaspara:BAAANQAFFAEJAQAAAA==.',
Ve='Vergalis:BAAANQADCgYIDAAAAA==.',
Vi='Vileknight:BAAANQAECgEIAQAAAA==.Visark:BAAANQADCggICAAAAA==.Visz:BAAANQADCgQIBAAAAA==.Vitlania:BAAANQADCggICAAAAA==.',
Vo='Voidlìlíth:BAAANQAECgYIDwAAAA==.Voidwak:BAAANQAECgUJCgAAAA==.Vorronni:BAAANQAECgUJDAAAAA==.',
Wa='Wardo:BAACNQAFFIEKAAMXAAUKGBroBQBmAQAXAAQKiRzoBQBmAQAYAAEKVhCMDwBZAAA1AAQKgSMABBcACQqaI3YKADsDABcACAppI3YKADsDABgABwrSHKAKAC4CACAAAQrUG14gADsAAAAA.Warhelm:BAAANQADCgMIAwAAAA==.Wastedtank:BAAANQABCgIIAgAAAA==.',
We='Wellen:BAAANQADCgUICQAAAA==.Werewolf:BAAANQADCgcJIgAAAA==.',
Wh='Whitepikmin:BAAANQAECgcJEAAAAA==.',
Wi='Wilmer:BAABNQAECoEWAAIGAAcKTiAYLwB3AgAGAAcKTiAYLwB3AgAAAA==.Wily:BAAANQADCggIDgAAAA==.Winterlock:BAAANQADCgcJDQAAAA==.Wiseguy:BAAANQADCgYIBwAAAA==.',
Wo='Wookieweener:BAAANQAECgQIBAABNQAECggIFQAKACQXAA==.',
Wr='Wravc:BAAANQAECgMIBAAAAQ==.',
Xa='Xaspen:BAAANQAECgMIAwAAAA==.',
Xe='Xerukin:BAAANQADCgYJDAAAAA==.',
Xo='Xoroth:BAAANQAECgUICQAAAA==.',
Ya='Yargonz:BAAANQADCggICAAAAA==.Yargz:BAAANQAECgUIBQABNQAFFAUJCgAFAIsFAA==.Yargzdk:BAACNQAFFIEKAAIFAAUKiwUECwDyAAAFAAUKiwUECwDyAAA1AAQKgR4AAgUACQrZDnA2AL8BAAUACQrZDnA2AL8BAAAA.',
Ye='Yeyol:BAAANQAECggIDwAAAA==.',
Yo='Yolius:BAAANQAECgQIDAAAAA==.Yoogi:BAAANQAECgEIAQABNQAECgUICAACAAAAAA==.',
Yu='Yungnetero:BAAANQAECgQIBwAAAA==.Yunikon:BAABNQAECoEXAAQhAAgKrRqLFADUAQAEAAYKxhomWgDyAQAhAAcK7haLFADUAQADAAYKihBMYQByAQABNQADCggIFAACAAAAAA==.',
Za='Zabala:BAAANQABCgQIBAABNQAECgUJDAACAAAAAA==.Zavorotnuk:BAAANQADCggICgAAAA==.',
Ze='Zell:BAAANQAECgQIBQABNQAECgYIEgACAAAAAA==.Zelluss:BAAANQAECgYIEgAAAA==.Zeltari:BAAANQADCgQIBAAAAA==.Zephyrex:BAAANQADCgYIBgAAAA==.Zerkerpete:BAAANQAECgcJCwAAAA==.',
Zh='Zhaphiria:BAAANQAECgcIBwABNQAECggIDgACAAAAAA==.Zhul:BAAANQAECgQJCAABNQAECgYIEQACAAAAAA==.',
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
