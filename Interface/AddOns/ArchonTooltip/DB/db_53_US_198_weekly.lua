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

local lookup = {'Unknown-Unknown','Paladin-Holy','Shaman-Enhancement','Druid-Guardian','Mage-Arcane','Evoker-Augmentation','Hunter-Marksmanship','Shaman-Elemental','Evoker-Devastation','Evoker-Preservation','Druid-Restoration','Monk-Windwalker','Warlock-Demonology','Warlock-Destruction','Mage-Frost','Rogue-Assassination','Rogue-Subtlety','Paladin-Retribution','DeathKnight-Unholy','DeathKnight-Blood','Warlock-Affliction','Warrior-Arms',}
local provider = {region='US',realm='Skullcrusher',name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Abzdh:BAAANQABCgQIBAABNQAECgYIDgABAAAAAA==.Abzmage:BAAANQAECgYIDgAAAA==.Abzp:BAAANQAECgEIAQAAAA==.',
Ac='Acoreüs:BAEANQAECgQICgAAAA==.',
Ad='Adramelk:BAAANQAECgIIAgABNQAECgUICgABAAAAAA==.',
Ae='Aed:BAAANQABCgEIAQAAAA==.Aeiay:BAAANQAECgIIAgAAAA==.',
Ai='Aibh:BAAANQADCgUIBwAAAA==.',
Al='Alastorias:BAAANQADCggIEQAAAA==.Alethice:BAAANQADCgcIBwAAAA==.Alexandrap:BAAANQADCgcIDgAAAA==.Allmighto:BAECNQAFFIEHAAICAAQJihQ+BABaAQACAAQJihQ+BABaAQA1AAQKgRgAAgIACQmhHnAJAC4DAAIACQmhHnAJAC4DAAAA.Alyssaxoo:BAAANQAECgcIEwAAAA==.',
An='Androstraz:BAAANQADCggICAAAAA==.Anjkh:BAAANQADCgYIBgAAAA==.Anniesthesia:BAAANQAECgEIAgAAAA==.Anoobyss:BAAANQAECgUIEAAAAA==.Anorexorcist:BAAANQABCgEIAQABNQAFFAEIAgABAAAAAA==.Anorxorcist:BAAANQADCgYIBgABNQAFFAEIAgABAAAAAA==.Anorxxorcist:BAAANQAFFAEIAgAAAA==.Anthraxx:BAAANQADCggIDwAAAA==.',
Ar='Archenemyy:BAAANQAECgQIBAAAAA==.Arda:BAAANQAECggIDwAAAA==.Arune:BAAANQAECgMIAwAAAA==.',
As='Aspyrx:BAAANQAECgQIBwAAAA==.Assol:BAAANQADCgUICgAAAA==.Astelan:BAEANQAECgMIBAAAAA==.Astärea:BAAANQAECgQIBgAAAA==.',
Au='Aurorä:BAAANQADCggICAAAAA==.',
Ay='Ayeola:BAAANQADCgEIAQAAAA==.',
Az='Aztëk:BAAANQAECgIIAgAAAA==.',
Ba='Bachaterah:BAAANQADCgEIAQAAAA==.Baddawg:BAAANQAECgEIAQAAAA==.Baeldaeg:BAAANQADCggIDQAAAA==.Bahahahamut:BAAANQADCgcIBwABNQADCggIDQABAAAAAA==.Bannett:BAAANQAECgEIAwAAAA==.Baoboi:BAAANQADCgQIBAAAAA==.Bauce:BAAANQADCgQIBAAAAA==.Baxterevo:BAAANQAECgIIAgAAAA==.Baybx:BAAANQABCgUIBgAAAA==.',
Be='Beardgrim:BAAANQADCggICAAAAA==.Beefyweefy:BAAANQABCgYIBgABNQAECgMIAwABAAAAAA==.Bella:BAAANQAECgMIAwAAAA==.',
Bi='Bianchi:BAAANQAECgcIBwAAAA==.Bibleman:BAAANQADCggICAAAAA==.Biddy:BAAANQADCgYIBgAAAA==.Bigchungus:BAAANQADCgYIBgAAAA==.Bigguns:BAAANQADCgQIBAAAAA==.Bigpumpa:BAAANQAECgQIBAAAAA==.Billygoatgrf:BAAANQAECgQIBQAAAA==.',
Bl='Blackvomit:BAAANQAECgIIAgAAAA==.Blakkbeard:BAABNQAECoEeAAIDAAkJIh6fAgBBAwADAAkJIh6fAgBBAwAAAA==.Blazefort:BAAANQAFFAEIAQAAAA==.Blitzeye:BAAANQAECgUIDwAAAA==.',
Bo='Bolger:BAAANQADCgMIAwAAAA==.Bonix:BAAANQADCgIIBAAAAA==.Boozeftw:BAAANQADCgUIBQAAAA==.Bowjobdamage:BAAANQADCgMIAwAAAA==.',
Br='Braincell:BAAANQAECgUIEQABNQADCggIDQABAAAAAA==.Breemonic:BAAANQAECgYIDgAAAA==.Brewdie:BAAANQADCgUIBgAAAA==.Brrooks:BAAANQADCggICAAAAA==.Bruce:BAAANQAECgcIEgAAAA==.',
Bu='Bubblekush:BAAANQAECgIIAgAAAA==.Bubbleøseven:BAAANQADCgQIBAAAAA==.Bullshifter:BAAANQADCgQIBAAAAA==.Burgleslight:BAAANQABCgEIAQAAAA==.Butturz:BAAANQADCggIGgAAAA==.',
['Bø']='Bønecrusher:BAAANQABCgEIAQAAAA==.',
Ca='Cabala:BAAANQADCgYIDAAAAA==.Cailleach:BAAANQAECgIIAgAAAA==.',
Ce='Celeryman:BAAANQAECgUICgAAAA==.Centuro:BAAANQAECgEIAQAAAA==.',
Ch='Chobi:BAABNQAECoEZAAIEAAkJDyVZAADbAwAEAAkJDyVZAADbAwAAAA==.',
Ci='Cinnamen:BAAANQAECgUICQAAAA==.',
Cl='Claudine:BAAANQAECgIIAwAAAA==.Clearstoned:BAAANQADCgUIBQABNQAECggIFwAFANAZAA==.',
Co='Coaa:BAAANQAECgQIBgAAAA==.Colossus:BAAANQAECgUICwAAAA==.Contrap:BAAANQAECgcIDQAAAA==.Coolbreeze:BAAANQAECgIIAwAAAA==.Corpsgrinder:BAAANQAECgUICwAAAA==.Cowbroni:BAAANQAECgUIBgAAAA==.',
Cr='Crashöut:BAAANQADCgIIAgAAAA==.Crysix:BAAANQABCgQIBAAAAA==.',
Cu='Curtland:BAAANQADCgYICwAAAA==.',
Cz='Cz:BAAANQADCgQIBAAAAA==.Czera:BAAANQADCgMIAwAAAA==.',
Da='Dahialkahina:BAAANQADCgEIAQAAAA==.Darkmeadow:BAAANQAECgEIAgAAAA==.Dastard:BAAANQAECgYICwAAAA==.',
De='Deadplank:BAAANQAECgQIBQAAAA==.Deathlyfrost:BAAANQADCggICAAAAA==.Deftonia:BAAANQAECgQIBgAAAA==.Degenerate:BAAANQADCgYICAAAAA==.Dementïa:BAAANQAECggIBgAAAA==.Demonbläde:BAAANQADCgcIBwAAAA==.Dethany:BAAANQADCggIDAAAAA==.Devondric:BAAANQAECgUICgAAAA==.Devotion:BAAANQADCgUIBQABNQAECgkJIgACAM4VAA==.Devotional:BAABNQAECoEiAAICAAkJzhUvEADjAgACAAkJzhUvEADjAgAAAA==.',
Di='Diekuh:BAAANQAECgEIAQAAAA==.Diivinity:BAAANQABCgQIBAABNQAECgYIEQABAAAAAA==.Dimepiece:BAAANQADCgUIBwAAAA==.Dithi:BAAANQADCgQIBAAAAA==.Divinaputits:BAAANQAECgcIBgAAAA==.',
Do='Dojoh:BAAANQADCgMIAwAAAA==.Dommiemommie:BAAANQAECgQIBgAAAA==.Doozpal:BAABNQAECoEZAAICAAgJnxGHKwAeAgACAAgJnxGHKwAeAgAAAA==.Dorinspins:BAEANQAECggICAAAAA==.Downset:BAAANQADCgcIBwAAAA==.',
Dr='Drakonman:BAAANQAECgIIAgAAAA==.Draynen:BAAANQAECgYIBgABNQAECgkJJwAGAJIgAA==.Drbanner:BAAANQADCgUIBQAAAA==.Drboom:BAAANQAECgIIAgAAAA==.Drezd:BAABNQAECoEaAAIHAAYJgQ9iIwBwAQAHAAYJgQ9iIwBwAQAAAA==.',
Du='Duck:BAAANQADCgQICwABNQADCgcIEgABAAAAAA==.Dulcïnea:BAAANQAECgEIAQABNQAECggIBgABAAAAAA==.Dumpymilk:BAAANQADCgcIEwABNQADCggIDQABAAAAAA==.',
Ea='Eao:BAAANQAECgUICwAAAA==.',
Ed='Edrana:BAAANQADCgYIBgABNQADCggIEQABAAAAAA==.',
Eh='Ehvyn:BAAANQADCggICgABNQAECgEIAQABAAAAAA==.',
El='Elitistjerk:BAAANQADCgEIAQAAAA==.Ellisis:BAAANQAECgQIBAAAAA==.',
Em='Emriq:BAAANQAECgQIBwAAAA==.',
En='Enmai:BAAANQAECgQICQAAAA==.',
Ep='Epiphany:BAAANQAECgMIBQAAAA==.',
Er='Eraylina:BAAANQADCggIDAAAAA==.Ertivoker:BAAANQADCggICAABNQAECgQIBQABAAAAAA==.',
Eu='Eulogy:BAAANQAECgUICwAAAA==.',
Ev='Evangelise:BAAANQADCgEIAQAAAA==.Eveille:BAAANQABCgIIAgAAAA==.',
Ex='Exxitus:BAAANQAECgUIBwAAAA==.',
Fa='Faith:BAAANQAECgMIBgAAAA==.Falsoqt:BAAANQADCgIIAgAAAA==.Fatblackcow:BAAANQADCgEIAQAAAA==.',
Fe='Fecalmatters:BAAANQADCgcIBwAAAA==.Felachio:BAAANQAECgQIBwAAAA==.',
Fj='Fjörgyn:BAACNQAFFIEHAAIIAAQJshOyAwBgAQAIAAQJshOyAwBgAQA1AAQKgRoAAggACQmTIdcJAFIDAAgACQmTIdcJAFIDAAAA.',
Fl='Flanksterr:BAAANQADCgQIBAAAAA==.',
Fo='Fork:BAAANQAECggIEAAAAA==.Fozziedaburr:BAAANQAECgUICQAAAA==.',
Fr='Frasierkrane:BAAANQADCgQIBwAAAA==.Frontmage:BAAANQADCggICAAAAA==.',
Ft='Ftfk:BAAANQADCggIDgABNQAECgUICwABAAAAAA==.',
Ga='Galie:BAAANQAECgYIDAAAAA==.Galiè:BAAANQABCgcICQAAAA==.Garrahoth:BAAANQAECgMIAwAAAA==.',
Ge='Gekk:BAAANQAECgQIBwAAAA==.',
Gi='Giaus:BAAANQAECgYIDAAAAA==.Girby:BAAANQADCgcIBwAAAA==.',
Gl='Glaaive:BAAANQADCgEIAQAAAA==.',
Go='Gobzilla:BAAANQAECgYICgAAAA==.Gonn:BAAANQADCgUIBQAAAA==.Goub:BAAANQAECgMIAwAAAA==.',
Gr='Grapefantuh:BAAANQAECgEIAQAAAA==.Grapeinator:BAAANQAECgEIAQAAAA==.Grimreapr:BAAANQAECgEIAQAAAA==.Grimrieber:BAAANQAECgcIDQAAAA==.Gromn:BAAANQAECgYIEgAAAA==.',
Ha='Hashed:BAAANQAECgEIAQAAAA==.Haysevoker:BAABNQAECoEbAAQGAAkJwxm4AwA/AgAGAAcJhR64AwA/AgAJAAgJGRJ+DgDqAQAKAAMJxA1SJQDDAAAAAA==.',
He='Henn:BAAANQAECgIIAgAAAA==.',
Ho='Hobb:BAAANQADCgUIBQAAAA==.Holemilk:BAAANQADCggICAAAAA==.Holycopter:BAAANQADCggIGgAAAA==.Holymojo:BAAANQAECgYIDgAAAA==.Hoodler:BAECNQAFFIEFAAILAAQJIh+CAQCEAQALAAQJIh+CAQCEAQA1AAQKgRwAAgsACQlJJMUBAIEDAAsACQlJJMUBAIEDAAAA.Hoodlery:BAEANQAECggIDwABNQAFFAQIBQALACIfAA==.Hoofjob:BAACNQAFFIEFAAIMAAQJagUsAwAhAQAMAAQJagUsAwAhAQA1AAQKgRwAAgwACQn4G+MJALcCAAwACQn4G+MJALcCAAAA.',
Hu='Huskydots:BAAANQAECgcIDQAAAA==.',
['Hé']='Hércules:BAAANQADCgIIAgAAAA==.',
Ia='Iaell:BAAANQADCgIIAgABNQAECgQIBwABAAAAAA==.',
Ib='Iblastpants:BAAANQAECgIIAwAAAA==.',
Id='Idd:BAAANQAECgIIAgAAAA==.',
Ig='Iggyy:BAAANQAECgMIBQAAAA==.',
In='Inflammo:BAAANQABCgEIAQAAAA==.Insaneness:BAAANQADCggIEAAAAA==.',
Ir='Irila:BAAANQAECgIIAgAAAA==.',
It='Ithrein:BAAANQADCgYICwAAAA==.',
Iz='Izumî:BAAANQADCgYICwAAAA==.',
Ja='Jakè:BAAANQAECgIIAgAAAA==.Jangutu:BAAANQAECgYIEAAAAA==.Jaslen:BAAANQADCgYIBgAAAA==.Jasono:BAAANQADCgQIBAAAAA==.Jaspy:BAAANQAECgUICwAAAA==.',
Je='Jeffdennis:BAAANQAECggIDQAAAA==.',
Ji='Jimmybuffler:BAAANQAECgUIBQAAAA==.',
Jo='Jomgpallie:BAAANQAECgQIBwAAAA==.Jonra:BAAANQADCgMIBAAAAA==.Josefbugman:BAAANQAECgIIAgAAAA==.',
Ju='Judykiki:BAAANQADCgcICwAAAA==.Juju:BAAANQAECgIIAwAAAA==.Juktal:BAAANQAECgQIBAAAAA==.Justyn:BAAANQAECgIIAwAAAA==.',
Ka='Kaeden:BAAANQADCgQIBAAAAA==.Kahlán:BAAANQABCgUIBQAAAA==.Kainz:BAAANQAECgIIAgAAAA==.Kaoscontrol:BAAANQADCgUICQAAAA==.Kazaju:BAABNQAECoEWAAMNAAkJfx7eMgAKAgANAAYJvBzeMgAKAgAOAAMJBSLYIQAqAQAAAA==.',
Ki='Kialorstus:BAAANQAECgUICQAAAA==.Kirbo:BAAANQAECgEIAQAAAA==.Kitagawa:BAAANQAECgQIBgAAAA==.Kitten:BAAANQADCgcIDgAAAA==.',
Kl='Klondikecow:BAAANQABCgMIBAAAAA==.',
Ko='Kolakua:BAAANQADCgQIBAAAAA==.Korianth:BAAANQAECgUIBwAAAA==.Korlon:BAAANQADCgYICwAAAA==.Kouw:BAAANQAECgYICAAAAA==.',
Kr='Kradyn:BAAANQADCgYICAAAAA==.Kragfoerend:BAAANQADCggINwAAAA==.Krankenstein:BAAANQAECgQIBwAAAA==.Krankson:BAAANQADCgIIAgAAAA==.Kriix:BAAANQAECgQICgAAAA==.Krusnik:BAAANQADCgUICAAAAA==.Kruurk:BAAANQADCgQIBAAAAA==.',
Ks='Ksubii:BAAANQAECgEIAQAAAA==.',
Ku='Kuhtta:BAAANQADCggIFgAAAA==.Kumdobeast:BAAANQAECgQICgAAAA==.Kuothe:BAAANQAECgQIBwAAAA==.',
Ky='Kyina:BAAANQADCgcIBwAAAA==.Kyotpal:BAAANQADCgIIAgAAAA==.',
La='Lazyriver:BAAANQAECgQIBQABNQADCgUIIQABAAAAAA==.',
Le='Legoland:BAAANQAECgEIAQAAAA==.Leonphelps:BAAANQADCgYIBwAAAA==.Lesnichii:BAAANQAECgYICgAAAA==.Lewakex:BAAANQAECgcIBwAAAA==.Leyninade:BAAANQAECgQIBAAAAA==.',
Li='Lightbrngr:BAAANQAECgYIDgAAAA==.Lihuai:BAAANQADCggICAAAAA==.Liilpeep:BAAANQAECggICQAAAA==.Lilbertha:BAAANQAECgIIAgAAAA==.Lilchigirl:BAAANQADCgYIBgAAAA==.Lildipster:BAAANQADCgYICgABNQADCggIDQABAAAAAA==.Lildump:BAAANQADCgMIAwABNQAECgYIBgABAAAAAA==.Limitlessone:BAAANQAECgMIAwAAAA==.Lionescanor:BAAANQADCgEIAQAAAA==.Liptonaysti:BAAANQAECgEIAQAAAA==.Lissandine:BAAANQAECgYIDgAAAA==.Liya:BAAANQAECgEIAQABNQAFFAIIAgABAAAAAA==.Lizzywizzy:BAAANQADCgYIBgABNQADCggIDQABAAAAAA==.',
Lo='Locrian:BAAANQABCgQIBAAAAA==.Lotharn:BAAANQADCgMIAQAAAA==.Lowdy:BAAANQAECgQICwAAAA==.',
Lu='Luulk:BAAANQAECgUIBQAAAA==.',
Ly='Lych:BAAANQADCgYIBgAAAA==.Lyclaw:BAAANQADCgMIAwAAAA==.',
['Lì']='Lìllith:BAAANQAECgMIBAAAAA==.',
Ma='Madoris:BAAANQADCgcIBwAAAA==.Magemagerson:BAAANQAECgYIDQAAAA==.Magnuss:BAAANQAECgYIDAAAAA==.Mahini:BAAANQADCgYIBgAAAA==.Malleus:BAAANQAECgEIAQAAAA==.Mammutos:BAAANQAECgIIAwAAAA==.Manifred:BAAANQADCgYIBgAAAA==.Manion:BAAANQAECgUICwAAAA==.Manipepper:BAAANQAECgQIBgAAAA==.Manippiez:BAAANQAECgMIAwAAAA==.Manipulation:BAAANQADCgEIAQAAAA==.Mannarchy:BAAANQADCgQIBAAAAA==.Mantrà:BAAANQADCggIDAAAAA==.Maplemaga:BAAANQAECgEIAQAAAA==.Margot:BAAANQADCgYIBgABNQADCgcIDgABAAAAAA==.Masochista:BAAANQAFFAIIAgAAAA==.Mastavas:BAAANQAECgEIAQABNQAECgQIBQABAAAAAA==.Mastric:BAEANQAECgUICwAAAA==.',
Mc='Mccaffrey:BAAANQAECgQIBwAAAA==.',
Me='Meetch:BAAANQAECgcICgAAAA==.Megdar:BAAANQAECgMIBAAAAA==.Melledreu:BAABNQAECoEqAAMPAAgJygpdCACNAQAPAAgJvwpdCACNAQAFAAYJUgGG/QC/AAAAAA==.Merix:BAABNQAECoEXAAMQAAkJpht5GADCAQAQAAUJ7x15GADCAQARAAUJRxhxGwCaAQAAAA==.Mestea:BAAANQAECgEIAQAAAA==.Mewing:BAAANQADCggIEAABNQAECgcIFAASAMIhAA==.',
Mi='Miraclemill:BAAANQADCgYIDgAAAA==.Mirra:BAAANQAECgMIAwAAAA==.',
Mo='Mojobtw:BAAANQADCgcIBwAAAA==.Monsterboy:BAAANQADCgIIAgAAAA==.Mortamur:BAAANQAECgYIDgAAAA==.Mortelinnos:BAAANQAECgUICwAAAA==.',
My='Mysticguru:BAAANQAECgQICgAAAA==.Mythrax:BAAANQAECgYIDQAAAA==.',
Na='Naradrae:BAAANQADCgUIBQAAAA==.Narodaran:BAAANQAECgEIAQAAAA==.Naughtyrawr:BAAANQADCggIEwAAAA==.',
Ne='Nevets:BAAANQAECggIEAAAAA==.Nevrs:BAAANQADCggIFQAAAA==.Newworld:BAAANQADCgQICAAAAA==.',
Ni='Nikolajokic:BAAANQAECgEIAQAAAA==.Nimit:BAAANQAECgQIBgAAAA==.',
No='Notzee:BAAANQAECgEIAQAAAA==.Novic:BAAANQAECgYIDgAAAA==.',
Nu='Nualia:BAAANQAECgYIDgAAAA==.',
['Né']='Némésis:BAAANQAECgEIAQAAAA==.',
Oj='Ojacks:BAAANQADCggIDQAAAA==.Ojaks:BAAANQAECgcIDAAAAA==.',
Op='Operendi:BAAANQADCgYIBgAAAA==.',
Or='Orbian:BAAANQADCgcIBwAAAA==.Orobus:BAAANQAECgcICwAAAA==.',
Os='Oscassey:BAAANQAECgQIBwAAAA==.',
Ox='Oxley:BAAANQAECgQIBAAAAA==.',
Pa='Paladingus:BAAANQAECgYICwAAAA==.Pandidin:BAAANQAECgYIDAAAAA==.Pauldrons:BAABNQAECoEsAAITAAgJGA8UJwABAgATAAgJGA8UJwABAgAAAA==.',
Pe='Peenar:BAAANQAECgUICQAAAA==.Peenpikmin:BAAANQADCgQIBAAAAA==.Pejorative:BAAANQADCgYIBgAAAA==.',
Ph='Pharlock:BAAANQAECgIIAwAAAA==.Phobia:BAAANQADCggICAABNQAECgUICwABAAAAAA==.',
Pl='Plankie:BAAANQADCgUICAAAAA==.Plankreaver:BAAANQADCgIIAgAAAA==.Planks:BAAANQADCggIDwAAAA==.Plankz:BAAANQADCgMIAwAAAA==.',
Po='Pooterdiddle:BAAANQAECgEIAQAAAA==.',
Pr='Priesttess:BAAANQADCgQIBAAAAA==.Prohealin:BAAANQAECgYIDAAAAA==.',
Ps='Psarahdactyl:BAAANQADCgIIAgAAAA==.',
Pt='Ptiteagacee:BAAANQAECgQIBwAAAA==.',
Pu='Pufdaddy:BAAANQAECgIIAgAAAA==.Puffymüffins:BAAANQADCgIIAgABNQAECgEIBAABAAAAAA==.Pumpkinq:BAABNQAECoEbAAMRAAkJtiCaBQD/AgARAAgJzCCaBQD/AgAQAAMJAw1kNADDAAAAAA==.',
Py='Pyre:BAAANQABCgIIAgAAAA==.',
['Pì']='Pìkachu:BAAANQAECgUICwAAAA==.',
Ra='Ragemommie:BAAANQAECgMIBAABNQAECgQIBgABAAAAAA==.Rainer:BAAANQABCgYIBgAAAA==.Rasmus:BAAANQAECgUIBwAAAA==.Raykwan:BAAANQADCgUIBQAAAA==.Rayquaza:BAAANQAECgUICwAAAA==.Razzmatazz:BAAANQAECgQIBgAAAA==.',
Re='Reddeyes:BAAANQAECgIIAwAAAA==.Rescue:BAAANQAECgYIDgAAAA==.Reva:BAEANQAECgEIAQABNQAECgMIBAABAAAAAA==.',
Ri='Rising:BAAANQADCggIDgAAAA==.',
Ro='Roamin:BAAANQADCggICAAAAA==.Roasted:BAAANQAECgYIDgAAAA==.Rockma:BAAANQAECggIAQAAAA==.Rollandburn:BAAANQAECgQIDwAAAA==.Roxymigurdia:BAAANQAECgYIDQAAAA==.',
Ru='Rufföaddy:BAAANQAECgUICwAAAA==.Runeesa:BAAANQAECgIIAwAAAA==.',
Ry='Rylena:BAAANQAECgQICQAAAA==.Ryuke:BAAANQADCggICAAAAA==.Ryvalry:BAAANQABCgIIAgAAAA==.',
['Rà']='Ràvenn:BAAANQABCgIIAgABNQADCggIDwABAAAAAA==.',
['Râ']='Râmên:BAAANQADCgEIAQAAAA==.',
Sa='Sagikos:BAEANQAECgcIDQAAAA==.Sardras:BAAANQAECgUICwAAAA==.Sark:BAAANQAECgYIBwAAAA==.Sathor:BAAANQAECgUICgAAAA==.Saucecity:BAAANQADCgYICwAAAA==.Saucyjenkins:BAAANQAECgEIAQAAAA==.',
Sc='Scranton:BAAANQADCgYICAAAAA==.',
Se='Sellout:BAAANQAECgEIAQAAAA==.Semprefi:BAAANQADCgcIBwAAAA==.',
Sh='Shaani:BAAANQAECgEIAQAAAA==.Shace:BAAANQABCgQIBAAAAA==.Shadowfoot:BAAANQADCgUIBQAAAA==.Shadowhut:BAAANQADCgQIBAAAAA==.Shalanot:BAEANQAECgUICgABNQAECgcIDQABAAAAAA==.Shamerific:BAAANQADCgcIBwAAAA==.Shamlus:BAAANQAECgEIAQABNQAECgYIEgABAAAAAA==.Shammooz:BAABNQAECoEqAAIDAAgJGhiEBgCmAgADAAgJGhiEBgCmAgAAAA==.Shinier:BAAANQAECgYIEAAAAA==.Shockwoods:BAAANQAECgQICAAAAA==.',
Si='Silversmage:BAAANQADCgQIBAAAAA==.Simohayha:BAAANQADCgIIAgAAAA==.',
Sk='Skeeboo:BAAANQABCgYIBgAAAA==.Skülly:BAAANQAECgQIBAAAAA==.',
Sl='Slappywappy:BAAANQAECgQICgAAAA==.',
Sm='Smorcin:BAAANQAECgUICgAAAA==.',
So='Softdeath:BAAANQADCgcIBwAAAA==.',
Sp='Spellnchill:BAAANQAECgIIAgAAAA==.Spintor:BAAANQAECgIIAwAAAA==.Spookyy:BAAANQADCgMIAwAAAA==.',
Sq='Squidseye:BAAANQAECgYICQAAAA==.',
St='Stalk:BAAANQABCgIIAgAAAA==.Steelwaves:BAAANQADCgcIDAAAAA==.Stevelock:BAAANQADCgMIAwABNQADCgcIBwABAAAAAA==.Stoade:BAAANQABCgYIBwAAAA==.Stormfang:BAAANQADCgIIAgAAAA==.Stricker:BAAANQAECgQICAAAAA==.',
Su='Sukuta:BAAANQAECgIIAgAAAA==.Surikesu:BAAANQAECgQIBQAAAA==.Surious:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.',
Sw='Sweettooth:BAAANQADCgMIAwAAAA==.',
Sy='Syphian:BAAANQADCgcIEQAAAA==.',
Ta='Taishigi:BAAANQAECgYICgAAAA==.Tapewyrm:BAAANQAECgQIBwAAAA==.Tatter:BAAANQADCgEIAQAAAA==.',
Te='Tecknique:BAAANQAECgYIDgAAAA==.Teedge:BAABNQAECoEbAAMJAAkJGBptCACNAgAJAAkJZxhtCACNAgAGAAMJ6BihCgDjAAAAAA==.',
Th='Thaldric:BAAANQABCgQIBgAAAA==.Thanos:BAAANQADCgMIAwAAAA==.Thatwhitekid:BAAANQAECgQIBwAAAA==.Thepaintrain:BAAANQAECgMIBAAAAA==.Thomasa:BAAANQADCgQIBAAAAA==.Thorodron:BAAANQADCgEIAQAAAA==.Thundera:BAAANQAECgQIDgAAAA==.',
Ti='Tierjar:BAAANQADCgcIBwAAAA==.Timberdoc:BAAANQAECgMIAwAAAA==.Timmehh:BAAANQADCggICAABNQAECgkJGwAJABgaAA==.Tindril:BAAANQAECgYIDQAAAA==.',
To='Tolan:BAAANQAECgUICgAAAA==.Toovok:BAAANQADCggICAAAAA==.Totemtartt:BAAANQAECgYIDgAAAA==.Toxicai:BAAANQAECgMIBAAAAA==.',
Tr='Treyman:BAAANQAECgYICwAAAA==.Tribune:BAABNQAECoEeAAIUAAgJTyDjDADuAgAUAAgJTyDjDADuAgABNQAECgkJGQAEAA8lAA==.Trinitree:BAAANQADCgcIDAAAAA==.Trinkler:BAAANQAECgMIBQAAAA==.',
Tu='Tunka:BAAANQADCgcIEAAAAA==.',
Tw='Twist:BAAANQAECgIIAwAAAA==.',
Ty='Tychondris:BAAANQAECgUICwAAAA==.',
Ul='Ulsoga:BAAANQAECgQIBQAAAA==.',
Un='Unbórn:BAAANQADCgQIBAAAAA==.Undeadbeast:BAAANQADCgYICgAAAA==.',
Ut='Utica:BAAANQADCgYICAAAAA==.',
Va='Vaiko:BAAANQADCgMIAwAAAA==.Vaspara:BAAANQAECgcICwAAAA==.',
Ve='Vergalis:BAAANQADCgYIDAAAAA==.',
Vi='Vileknight:BAAANQAECgEIAQAAAA==.Visark:BAAANQADCggICAAAAA==.Visz:BAAANQADCgQIBAAAAA==.',
Vo='Voidlìlíth:BAAANQAECgYIDgAAAA==.Voidwak:BAAANQAECgQIBQAAAA==.Vorronni:BAAANQAECgQIBwAAAA==.',
Wa='Wardo:BAACNQAFFIEFAAMNAAQJegssCADuAAANAAMJxA0sCADuAAAOAAEJmgTTDQBRAAA1AAQKgRwABA0ACQmpIoANAPUCAA0ACAngIYANAPUCAA4ABwnSHDoJAEACABUAAQnUGyYbAD0AAAAA.Warhelm:BAAANQADCgMIAwAAAA==.',
We='Wellen:BAAANQADCgUICQAAAA==.Werewolf:BAAANQADCgcIGwABNQADCggIGAABAAAAAA==.',
Wh='Whitepikmin:BAAANQAECgUICQAAAA==.',
Wi='Wilmer:BAAANQAECgYIDgAAAA==.Wily:BAAANQADCggIDgAAAA==.Winterlock:BAAANQADCgYICwAAAA==.Wiseguy:BAAANQADCgYIBgAAAA==.',
Wo='Wookieweener:BAAANQAECgQIBAABNQAECggIFQAWACQXAA==.',
Wr='Wravc:BAAANQAECgIIAgAAAQ==.',
Xa='Xaspen:BAAANQAECgMIAwAAAA==.',
Xe='Xerukin:BAAANQADCgYIBgAAAA==.',
Xo='Xoroth:BAAANQAECgUICQAAAA==.',
Ya='Yargonz:BAAANQADCggICAAAAA==.Yargzdk:BAACNQAFFIEFAAIUAAQJIAb0BwDVAAAUAAQJIAb0BwDVAAA1AAQKgRwAAhQACQlSDo4nAOABABQACQlSDo4nAOABAAAA.',
Ye='Yeyol:BAAANQAECgcICAAAAA==.',
Yo='Yolius:BAAANQAECgQICAAAAA==.Yoogi:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.',
Yu='Yungnetero:BAAANQAECgQIBwAAAA==.Yunikon:BAAANQAECgYICgABNQADCggIDQABAAAAAA==.',
Za='Zabala:BAAANQABCgQIBAABNQAECgQIBwABAAAAAA==.Zavorotnuk:BAAANQADCggICgAAAA==.',
Ze='Zelluss:BAAANQAECgYIEgAAAA==.Zerkerpete:BAAANQAECgUIBQAAAA==.',
Zh='Zhaphiria:BAAANQAECgcIBwABNQAECgkJJwAGAJIgAA==.Zhul:BAAANQAECgQIBAABNQAECgYICwABAAAAAA==.',
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
