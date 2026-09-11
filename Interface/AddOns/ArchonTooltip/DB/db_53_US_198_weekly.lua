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

local lookup = {'Unknown-Unknown','Shaman-Elemental','Druid-Restoration','Monk-Windwalker','Mage-Frost','Mage-Arcane','DeathKnight-Unholy','Shaman-Enhancement','Evoker-Devastation','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','DeathKnight-Blood',}
local provider = {region='US',realm='Skullcrusher',name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Abzdh:BAAANQABCgQIBAABNQAECgUICAABAAAAAA==.Abzmage:BAAANQAECgUICAAAAA==.',
Ac='Acoreüs:BAEANQAECgQIBAAAAA==.',
Ae='Aed:BAAANQABCgEIAQAAAA==.Aeiay:BAAANQADCgcIEQAAAA==.',
Ai='Aibh:BAAANQADCgIIAgAAAA==.',
Al='Alastorias:BAAANQADCggIDgAAAA==.Alethice:BAAANQADCgcIBwAAAA==.Alexandrap:BAAANQADCgcIDAAAAA==.Allmighto:BAEANQAFFAMIBAAAAA==.Alyssaxoo:BAAANQAECgcIDAAAAA==.',
An='Androstraz:BAAANQADCggICAAAAA==.Anjkh:BAAANQADCgYIBgAAAA==.Anniesthesia:BAAANQAECgEIAQAAAA==.Anoobyss:BAAANQAECgQICQAAAA==.Anorexorcist:BAAANQABCgEIAQABNQAFFAEIAQABAAAAAA==.Anorxorcist:BAAANQADCgYIBgABNQAFFAEIAQABAAAAAA==.Anorxxorcist:BAAANQAFFAEIAQAAAA==.Anthraxx:BAAANQADCggIDwAAAA==.',
Ar='Archenemyy:BAAANQADCgYIBgAAAA==.Arda:BAAANQAECggICQAAAA==.Arune:BAAANQADCgcICwAAAA==.',
As='Aspyrx:BAAANQAECgIIAwAAAA==.Assol:BAAANQADCgUIBQAAAA==.Astelan:BAEANQAECgEIAQAAAA==.Astärea:BAAANQAECgQIBAAAAA==.',
Au='Aurorä:BAAANQADCggICAAAAA==.',
Ay='Ayeola:BAAANQADCgEIAQAAAA==.',
Az='Aztëk:BAAANQAECgIIAgAAAA==.',
Ba='Bachaterah:BAAANQADCgEIAQAAAA==.Baddawg:BAAANQAECgEIAQAAAA==.Baeldaeg:BAAANQADCgYIBgAAAA==.Bannett:BAAANQAECgEIAQAAAA==.Baoboi:BAAANQADCgQIBAAAAA==.Bauce:BAAANQADCgQIBAAAAA==.Baxterevo:BAAANQADCggIFAAAAA==.Baybx:BAAANQABCgUIBgAAAA==.',
Be='Beardgrim:BAAANQADCggICAAAAA==.Bella:BAAANQADCgcIEwAAAA==.',
Bi='Bianchi:BAAANQABCgIIAgAAAA==.Bigchungus:BAAANQADCgYIBgAAAA==.Billygoatgrf:BAAANQAECgEIAQAAAA==.',
Bl='Blackvomit:BAAANQAECgIIAgAAAA==.Blakkbeard:BAAANQAECgcIEgAAAA==.Blazefort:BAAANQAECgQIBwAAAA==.Blitzeye:BAAANQAECgUICgAAAA==.',
Bo='Bolger:BAAANQADCgIIAgAAAA==.Bonix:BAAANQADCgIIBAAAAA==.Boozeftw:BAAANQADCgUIBQAAAA==.Bowjobdamage:BAAANQADCgMIAwAAAA==.',
Br='Braincell:BAAANQAECgQICgABNQADCgYIBgABAAAAAA==.Breemonic:BAAANQAECgUICAAAAA==.Brewdie:BAAANQADCgEIAQAAAA==.Brrooks:BAAANQADCggICAAAAA==.Bruce:BAAANQAECgcIDwAAAA==.',
Bu='Bubblekush:BAAANQAECgIIAgAAAA==.Bubbleøseven:BAAANQADCgQIBAAAAA==.Butturz:BAAANQADCgcIEgAAAA==.',
['Bø']='Bønecrusher:BAAANQABCgEIAQAAAA==.',
Ca='Cabala:BAAANQADCgYIBgAAAA==.Cailleach:BAAANQAECgEIAQAAAA==.',
Ce='Celeryman:BAAANQAECgUIBQAAAA==.Centuro:BAAANQAECgEIAQAAAA==.',
Ch='Chobi:BAAANQAECggIEgAAAA==.',
Ci='Cinnamen:BAAANQAECgQIBAAAAA==.',
Cl='Claudine:BAAANQAECgEIAQAAAA==.Clearstoned:BAAANQADCgUIBQABNQAECgcIDQABAAAAAA==.',
Co='Coaa:BAAANQAECgIIAgAAAA==.Colossus:BAAANQAECgQIBgAAAA==.Contrap:BAAANQAECgQIBgAAAA==.Coolbreeze:BAAANQAECgEIAQAAAA==.Corpsgrinder:BAAANQAECgQIBgAAAA==.Cowbroni:BAAANQAECgUIBgAAAA==.',
Cr='Crashöut:BAAANQADCgIIAgAAAA==.',
Cu='Curtland:BAAANQADCgYICwAAAA==.',
Cz='Cz:BAAANQADCgQIBAAAAA==.Czera:BAAANQADCgMIAwAAAA==.',
Da='Dahialkahina:BAAANQADCgEIAQAAAA==.Darkmeadow:BAAANQAECgEIAQAAAA==.Dastard:BAAANQAECgcICQAAAA==.',
De='Deadplank:BAAANQAECgEIAQAAAA==.Deathlyfrost:BAAANQADCgcIBwAAAA==.Deftonia:BAAANQAECgEIAgAAAA==.Degenerate:BAAANQADCgYICAAAAA==.Dementïa:BAAANQAECggIAQAAAA==.Demonbläde:BAAANQADCgcIBwAAAA==.Dethany:BAAANQADCgUIBQAAAA==.Devondric:BAAANQAECgQIBQAAAA==.Devotion:BAAANQADCgUIBQABNQAECgcIEQABAAAAAA==.Devotional:BAAANQAECgcIEQAAAA==.',
Di='Dimepiece:BAAANQADCgUIBwAAAA==.Dithi:BAAANQADCgQIBAAAAA==.',
Do='Dojoh:BAAANQADCgIIAgAAAA==.Dommiemommie:BAAANQAECgIIAgAAAA==.Doozpal:BAAANQAECgcIDgAAAA==.Dorinspins:BAEANQADCgUIBwAAAA==.',
Dr='Drakonman:BAAANQAECgIIAgAAAA==.Draynen:BAAANQAECgYIBgABNQAECgcIBwABAAAAAA==.Drbanner:BAAANQADCgUIBQAAAA==.Drboom:BAAANQADCgIIAgAAAA==.Drezd:BAAANQAECgUIDQAAAA==.',
Du='Duck:BAAANQADCgQICAABNQADCgYICwABAAAAAA==.Dulcïnea:BAAANQAECgEIAQABNQAECggIAQABAAAAAA==.Dumpymilk:BAAANQADCgcIDQABNQADCgYIBgABAAAAAA==.',
Ea='Eao:BAAANQAECgUIBgAAAA==.',
Ed='Edrana:BAAANQADCgYIBgABNQADCggIDgABAAAAAA==.',
Eh='Ehvyn:BAAANQADCgYIBwAAAA==.',
El='Elitistjerk:BAAANQADCgEIAQAAAA==.Ellisis:BAAANQADCggIEwAAAA==.',
Em='Emriq:BAAANQAECgIIAwAAAA==.',
En='Enmai:BAAANQAECgQIBQAAAA==.',
Ep='Epiphany:BAAANQAECgEIAQAAAA==.',
Er='Eraylina:BAAANQADCggIBwAAAA==.',
Eu='Eulogy:BAAANQAECgUIBgAAAA==.',
Ev='Evangelise:BAAANQADCgEIAQAAAA==.',
Ex='Exxitus:BAAANQAECgQIBgAAAA==.',
Fa='Faith:BAAANQAECgMIBQAAAA==.Fatblackcow:BAAANQADCgEIAQAAAA==.',
Fe='Fecalmatters:BAAANQADCgcIBwAAAA==.Felachio:BAAANQAECgIIAwAAAA==.',
Fj='Fjörgyn:BAABNQAECoEXAAICAAkJWx+PBgBPAwACAAkJWx+PBgBPAwAAAA==.',
Fl='Flanksterr:BAAANQADCgQIBAAAAA==.',
Fo='Fork:BAAANQAECggICAAAAA==.Fozziedaburr:BAAANQAECgQIBAAAAA==.',
Fr='Frasierkrane:BAAANQADCgQIBwAAAA==.',
Ft='Ftfk:BAAANQADCgYIBgABNQAECgUIBgABAAAAAA==.',
Ga='Galie:BAAANQAECgQIBgAAAA==.Galiè:BAAANQABCgUIBQAAAA==.Garrahoth:BAAANQADCggIEQAAAA==.',
Ge='Gekk:BAAANQAECgIIAwAAAA==.',
Gi='Giaus:BAAANQAECgQIBgAAAA==.Girby:BAAANQADCgcIBwAAAA==.',
Gl='Glaaive:BAAANQADCgEIAQAAAA==.Glimmerwisp:BAAANQADCgQIBAAAAA==.',
Go='Gobzilla:BAAANQAECgQIBAAAAA==.Gonn:BAAANQADCgUIBQAAAA==.Goub:BAAANQAECgMIAwAAAA==.',
Gr='Grapefantuh:BAAANQAECgEIAQAAAA==.Grimreapr:BAAANQADCgQIBAAAAA==.Grimrieber:BAAANQAECgQIBgAAAA==.Gromn:BAAANQAECgUIDQAAAA==.',
Ha='Hashed:BAAANQADCgYICwAAAA==.Hashi:BAAANQADCgIIAgAAAA==.Haysevoker:BAAANQAFFAEIAQAAAA==.',
He='Henn:BAAANQAECgIIAgAAAA==.',
Ho='Hobb:BAAANQADCgUIBQAAAA==.Holycopter:BAAANQADCgcIEgAAAA==.Holymojo:BAAANQAECgUICAAAAA==.Hoodler:BAEBNQAECoEXAAIDAAkJLSTxAACNAwADAAkJLSTxAACNAwAAAA==.Hoodlery:BAEANQAECgUICAABNQAECgkJFwADAC0kAA==.Hoofjob:BAABNQAECoEXAAIEAAkJ/xpYBwCuAgAEAAkJ/xpYBwCuAgAAAA==.',
Hu='Huskydots:BAAANQAECgQIBgAAAA==.',
['Hé']='Hércules:BAAANQADCgIIAgAAAA==.',
Ib='Iblastpants:BAAANQAECgEIAQAAAA==.',
Id='Idd:BAAANQADCgMIBgAAAA==.',
Ig='Iggyy:BAAANQAECgEIAgAAAA==.',
In='Inflammo:BAAANQABCgEIAQAAAA==.Insaneness:BAAANQADCggIDAAAAA==.',
Ir='Irila:BAAANQAECgEIAQAAAA==.',
It='Ithrein:BAAANQADCgYICwAAAA==.',
Iz='Izumî:BAAANQADCgEIAQAAAA==.',
Ja='Jakè:BAAANQAECgIIAgAAAA==.Jangutu:BAAANQAECgYICgAAAA==.Jaslen:BAAANQADCgYIBgAAAA==.Jasono:BAAANQADCgQIBAAAAA==.Jaspy:BAAANQAECgQIBgAAAA==.',
Je='Jeffdennis:BAAANQAECgUIBwAAAA==.',
Ji='Jimmybuffler:BAAANQADCgQIBAAAAA==.',
Jo='Jomgpallie:BAAANQAECgQIBAAAAA==.Jonra:BAAANQADCgMIBAAAAA==.Josefbugman:BAAANQAECgIIAgAAAA==.',
Ju='Judykiki:BAAANQADCgUIBgAAAA==.Juju:BAAANQADCggIGwAAAA==.Juktal:BAAANQADCgcIEgAAAA==.Justyn:BAAANQAECgEIAQAAAA==.',
Ka='Kaeden:BAAANQADCgQIBAAAAA==.Kainz:BAAANQAECgEIAQAAAA==.Kaoscontrol:BAAANQADCgUICQAAAA==.Kazaju:BAAANQAECgYIDQAAAA==.',
Ki='Kialorstus:BAAANQAECgQIBAAAAA==.Kirbo:BAAANQAECgEIAQAAAA==.Kitagawa:BAAANQAECgIIAgAAAA==.Kitten:BAAANQADCgYIBgAAAA==.',
Ko='Kolakua:BAAANQADCgQIBAAAAA==.Korianth:BAAANQAECgQIBAAAAA==.Korlon:BAAANQADCgYICwAAAA==.Kouw:BAAANQAECgYICAAAAA==.',
Kr='Kradyn:BAAANQADCgYICAAAAA==.Kragfoerend:BAAANQADCggIJwAAAA==.Krankenstein:BAAANQAECgIIAwAAAA==.Kriix:BAAANQAECgQIBgAAAA==.Krusnik:BAAANQADCgMIAwAAAA==.Kruurk:BAAANQADCgQIBAAAAA==.',
Ks='Ksubii:BAAANQAECgEIAQAAAA==.',
Ku='Kuhtta:BAAANQADCggIDwAAAA==.Kumdobeast:BAAANQAECgQIBgAAAA==.Kuothe:BAAANQAECgMIAwAAAA==.',
Ky='Kyotpal:BAAANQADCgIIAgAAAA==.',
La='Lazyriver:BAAANQAECgEIAQABNQADCgUIEwABAAAAAA==.',
Le='Legoland:BAAANQAECgEIAQAAAA==.Leonphelps:BAAANQADCgYIBgAAAA==.Lesnichii:BAAANQAECgQIBAAAAA==.Lewakex:BAAANQAECgQIAgAAAA==.Leyninade:BAAANQADCgQIBAAAAA==.',
Li='Lightbrngr:BAAANQAECgUICAAAAA==.Liilpeep:BAAANQAECggIAQAAAA==.Lilbertha:BAAANQAECgIIAgAAAA==.Lilchigirl:BAAANQADCgYIBgAAAA==.Lildipster:BAAANQADCgYICgABNQADCgYIBgABAAAAAA==.Limitlessone:BAAANQADCggIDgAAAA==.Liptonaysti:BAAANQAECgEIAQAAAA==.Lissandine:BAAANQAECgUICAAAAA==.Lizzywizzy:BAAANQADCgYIBgABNQADCgYIBgABAAAAAA==.',
Lo='Lotharn:BAAANQADCgMIAQAAAA==.Lowdy:BAAANQAECgQIBwAAAA==.',
Lu='Luulk:BAAANQADCgQIBAAAAA==.',
Ly='Lych:BAAANQADCgYIBgAAAA==.Lyclaw:BAAANQADCgMIAwAAAA==.',
['Lì']='Lìllith:BAAANQAECgEIAgAAAA==.',
Ma='Magemagerson:BAAANQAECgQIBwAAAA==.Magnuss:BAAANQAECgUIBwAAAA==.Mahini:BAAANQADCgYIBgAAAA==.Malleus:BAAANQAECgEIAQAAAA==.Mammutos:BAAANQAECgEIAQAAAA==.Manion:BAAANQAECgQIBgAAAA==.Manipepper:BAAANQAECgEIAgAAAA==.Manippiez:BAAANQADCgYIDgAAAA==.Manipulation:BAAANQADCgEIAQAAAA==.Mannarchy:BAAANQADCgQIBAAAAA==.Mantrà:BAAANQADCgQIBAAAAA==.Maplemaga:BAAANQAECgEIAQAAAA==.Masochista:BAAANQAECggIEgAAAA==.Mastavas:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.Mastric:BAEANQAECgQIBgAAAA==.',
Mc='Mccaffrey:BAAANQAECgIIAwAAAA==.',
Me='Meetch:BAAANQAECgMIAwAAAA==.Megdar:BAAANQAECgEIAQAAAA==.Melledreu:BAABNQAECoEaAAMFAAcJtAS+CQAZAQAFAAYJOQW+CQAZAQAGAAYJUgEBxADDAAAAAA==.Merix:BAAANQAECgcICwAAAA==.Mestea:BAAANQAECgEIAQAAAA==.Mewing:BAAANQADCggIDgABNQAECgcIDwABAAAAAA==.',
Mi='Miraclemill:BAAANQADCgYICgAAAA==.Mirra:BAAANQADCgcIEwAAAA==.',
Mo='Mojobtw:BAAANQADCgcIBwAAAA==.Monsterboy:BAAANQADCgIIAgAAAA==.Mortamur:BAAANQAECgYICAAAAA==.Mortelinnos:BAAANQAECgQIBgAAAA==.',
My='Mysticguru:BAAANQAECgMIBgAAAA==.Mythrax:BAAANQAECgQIBwAAAA==.',
Na='Naisu:BAAANQADCgEIAQAAAA==.Naradrae:BAAANQADCgUIBQAAAA==.Narodaran:BAAANQADCggIDwAAAA==.Naughtyrawr:BAAANQADCggIEwAAAA==.',
Ne='Nevets:BAAANQAECgUICAAAAA==.Nevrs:BAAANQADCggIDwAAAA==.Newworld:BAAANQADCgQIBQAAAA==.',
Ni='Nimit:BAAANQAECgIIAgAAAA==.',
No='Notzee:BAAANQAECgEIAQAAAA==.Novic:BAAANQAECgYICAAAAA==.',
Nu='Nualia:BAAANQAECgUICAAAAA==.',
['Né']='Némésis:BAAANQAECgEIAQAAAA==.',
Oj='Ojaks:BAAANQAECgUIBQAAAA==.',
Or='Orbian:BAAANQADCgcIBwAAAA==.Orobus:BAAANQAECgQIBAAAAA==.',
Os='Oscassey:BAAANQAECgIIAwAAAA==.',
Ox='Oxley:BAAANQAECgIIAgAAAA==.',
Pa='Paladingus:BAAANQAECgQIBQAAAA==.Pandidin:BAAANQAECgQIBgAAAA==.Pauldrons:BAABNQAECoEcAAIHAAcJPQmHLACZAQAHAAcJPQmHLACZAQAAAA==.',
Pe='Peenar:BAAANQAECgQIBAAAAA==.Pejorative:BAAANQADCgYIBgAAAA==.',
Ph='Pharlock:BAAANQAECgEIAQAAAA==.',
Pl='Plankie:BAAANQADCgUICAAAAA==.Planks:BAAANQADCggICAAAAA==.',
Po='Pooterdiddle:BAAANQAECgIIAQAAAA==.',
Pr='Prohealin:BAAANQAECgQIBgAAAA==.',
Ps='Psarahdactyl:BAAANQADCgIIAgAAAA==.',
Pt='Ptiteagacee:BAAANQAECgMIAwAAAA==.',
Pu='Pufdaddy:BAAANQADCggICQAAAA==.Puffymüffins:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.Pumpkinq:BAAANQAFFAEIAQAAAA==.',
Py='Pyre:BAAANQABCgIIAgAAAA==.',
['Pì']='Pìkachu:BAAANQAECgQIBgAAAA==.',
Ra='Rasmus:BAAANQAECgIIAgAAAA==.Raykwan:BAAANQADCgUIBQAAAA==.Rayquaza:BAAANQAECgUIBgAAAA==.Razzmatazz:BAAANQAECgEIAgAAAA==.',
Re='Reddeyes:BAAANQAECgEIAQAAAA==.Rescue:BAAANQAECgYICAAAAA==.Reva:BAEANQAECgEIAQABNQAECgEIAQABAAAAAA==.',
Ri='Rising:BAAANQADCgYIBgAAAA==.',
Ro='Roamin:BAAANQADCggICAAAAA==.Roasted:BAAANQAECgUICAAAAA==.Rockma:BAAANQAECggIAQAAAA==.Rollandburn:BAAANQAECgQIDwAAAA==.Roxymigurdia:BAAANQAECgQIBwAAAA==.',
Ru='Rufföaddy:BAAANQAECgQIBgAAAA==.Runeesa:BAAANQAECgEIAQAAAA==.',
Ry='Rylena:BAAANQAECgQIBQAAAA==.Ryuke:BAAANQADCggICAAAAA==.',
['Râ']='Râmên:BAAANQADCgEIAQAAAA==.',
Sa='Sagikos:BAEANQAECgYIBgAAAA==.Sardras:BAAANQAECgQIBgAAAA==.Sark:BAAANQAECgYIBwAAAA==.Sathor:BAAANQAECgUICQAAAA==.Saucecity:BAAANQADCgUIBQAAAA==.Saucyjenkins:BAAANQAECgEIAQAAAA==.',
Sc='Scranton:BAAANQADCgQIBgAAAA==.',
Se='Sellout:BAAANQAECgEIAQAAAA==.Semprefi:BAAANQADCgcIBwAAAA==.',
Sh='Shaani:BAAANQADCgUICAAAAA==.Shadowfoot:BAAANQADCgUIBQAAAA==.Shadowhut:BAAANQADCgQIBAAAAA==.Shalanot:BAEANQAECgUICgABNQAECgYIBgABAAAAAA==.Shamerific:BAAANQABCgQIBAABNQADCgMIAwABAAAAAA==.Shamlus:BAAANQAECgEIAQABNQAECgQICgABAAAAAA==.Shammooz:BAABNQAECoEaAAIIAAcJARMmCAD8AQAIAAcJARMmCAD8AQAAAA==.Shinier:BAAANQAECgUICgAAAA==.Shockwoods:BAAANQAECgMIBAAAAA==.',
Si='Silversmage:BAAANQADCgQIBAAAAA==.Simohayha:BAAANQADCgIIAgAAAA==.',
Sk='Skeeboo:BAAANQABCgYIBgAAAA==.Skülly:BAAANQAECgQIBAAAAA==.',
Sl='Slappywappy:BAAANQAECgMIBgAAAA==.',
Sm='Smorcin:BAAANQAECgQIBQAAAA==.',
So='Softdeath:BAAANQADCgcIBwAAAA==.',
Sp='Spellnchill:BAAANQADCgcIEAAAAA==.Spintor:BAAANQAECgEIAQAAAA==.Spookyy:BAAANQADCgMIAwAAAA==.',
Sq='Squidseye:BAAANQAECgMIAwAAAA==.',
St='Stalk:BAAANQABCgIIAgAAAA==.Steelwaves:BAAANQADCgQIBQAAAA==.Stevelock:BAAANQADCgMIAwAAAA==.Stricker:BAAANQAECgQIBAAAAA==.',
Su='Surikesu:BAAANQAECgMIAwAAAA==.Surious:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.',
Sw='Sweettooth:BAAANQADCgMIAwAAAA==.',
Sy='Syphian:BAAANQADCgYICgAAAA==.',
Ta='Taishigi:BAAANQAECgQIBAAAAA==.Tapewyrm:BAAANQAECgIIAwAAAA==.',
Te='Tecknique:BAAANQAECgUICAAAAA==.Teedge:BAABNQAECoETAAIJAAgJbhheCABbAgAJAAgJbhheCABbAgAAAA==.',
Th='Thaldric:BAAANQABCgQIBgAAAA==.Thanos:BAAANQADCgMIAwAAAA==.Thatwhitekid:BAAANQAECgMIAwAAAA==.Thomasa:BAAANQADCgQIBAAAAA==.Thorodron:BAAANQADCgEIAQAAAA==.Thundera:BAAANQAECgQICQAAAA==.',
Ti='Tierjar:BAAANQADCgcIBwAAAA==.Timberdoc:BAAANQADCgcIEgAAAA==.Tindril:BAAANQAECgUIBwAAAA==.',
To='Tolan:BAAANQAECgQIBwAAAA==.Toovok:BAAANQADCggICAAAAA==.Totemtartt:BAAANQAECgQICAAAAA==.Toxicai:BAAANQAECgEIAQAAAA==.',
Tr='Treyman:BAAANQAECgUIBQAAAA==.Tribune:BAAANQAECgYIEAABNQAECggIEgABAAAAAA==.Trinitree:BAAANQADCgcIDAAAAA==.Trinkler:BAAANQAECgMIBAAAAA==.',
Tu='Tunka:BAAANQADCgcICwAAAA==.',
Tw='Twist:BAAANQAECgEIAQAAAA==.',
Ty='Tychondris:BAAANQAECgUIBgAAAA==.',
Ul='Ulsoga:BAAANQAECgEIAQAAAA==.',
Un='Unbórn:BAAANQADCgQIBAAAAA==.Undeadbeast:BAAANQADCgYICgAAAA==.',
Ut='Utica:BAAANQADCgQIBgAAAA==.',
Va='Vaiko:BAAANQADCgMIAwAAAA==.Vaspara:BAAANQAECgQIBAAAAA==.',
Ve='Vergalis:BAAANQADCgYIDAAAAA==.',
Vi='Vileknight:BAAANQAECgEIAQAAAA==.Visark:BAAANQADCggICAAAAA==.Visz:BAAANQADCgQIBAAAAA==.',
Vo='Voidlìlíth:BAAANQAECgYICQAAAA==.Voidwak:BAAANQAECgEIAQAAAA==.Vorronni:BAAANQAECgIIAwAAAA==.',
Wa='Wardo:BAABNQAECoEXAAQKAAkJAyDRCwC1AgAKAAgJ5R7RCwC1AgALAAcJ0hzLBwBPAgAMAAEJ1BvPFAA/AAAAAA==.Warhelm:BAAANQADCgIIAgAAAA==.',
We='Wellen:BAAANQADCgUICQAAAA==.Werewolf:BAAANQADCgcIEgAAAA==.',
Wh='Whitepikmin:BAAANQAECgQIBAAAAA==.',
Wi='Wilmer:BAAANQAECgYICAAAAA==.Wily:BAAANQADCggIDgAAAA==.Winterlock:BAAANQADCgYIBgAAAA==.Wiseguy:BAAANQADCgQIBAAAAA==.',
Wo='Wookieweener:BAAANQAECgQIBAABNQAECggIEAABAAAAAA==.',
Wr='Wravc:BAAANQAECgIIAgAAAQ==.',
Xa='Xaspen:BAAANQADCgEIAQAAAA==.',
Xo='Xoroth:BAAANQAECgUICQAAAA==.',
Ya='Yargonz:BAAANQADCggICAAAAA==.Yargzdk:BAABNQAECoEXAAINAAkJegzTHADiAQANAAkJegzTHADiAQAAAA==.',
Yo='Yolius:BAAANQAECgQIBAAAAA==.Yoogi:BAAANQADCgYICgABNQADCggIEQABAAAAAA==.',
Yu='Yungnetero:BAAANQAECgQIBwAAAA==.Yunikon:BAAANQAECgQIBAABNQADCgYIBgABAAAAAA==.',
Za='Zavorotnuk:BAAANQADCggICgAAAA==.',
Ze='Zelluss:BAAANQAECgQICgAAAA==.',
Zh='Zhaphiria:BAAANQAECgcIBwAAAA==.Zhul:BAAANQADCgUIBQABNQAECgQIBQABAAAAAA==.',
Zo='Zoomies:BAAANQAECgQIBAAAAA==.',
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
