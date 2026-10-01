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

local lookup = {'Paladin-Retribution','Priest-Holy','Priest-Shadow','Unknown-Unknown','Rogue-Assassination','Shaman-Restoration','Warlock-Demonology','Mage-Arcane','Mage-Fire','DemonHunter-Havoc','DeathKnight-Unholy','Druid-Balance','Druid-Guardian','Warlock-Affliction','Warlock-Destruction','Hunter-Marksmanship','Hunter-BeastMastery','Monk-Mistweaver','Warrior-Arms','Monk-Windwalker','Priest-Discipline','DemonHunter-Devourer','DeathKnight-Blood','Warrior-Protection','Mage-Frost','DeathKnight-Frost','Paladin-Holy','Rogue-Subtlety','Shaman-Elemental','Druid-Restoration',}
local provider = {region='US',realm='LaughingSkull',name='US',type='weekly',zone=53,date='2026-09-29',data={Ac='Acanaline:BAAANQADCgYJBgAAAA==.Achannara:BAABNQAECoEaAAIBAAgK8ANCwAAoAQABAAgK8ANCwAAoAQAAAA==.',
Ae='Aeoliana:BAAANQAECgQICQAAAA==.',
Aj='Ajier:BAABNQAECoEgAAICAAkKjxf4PQApAgACAAkKjxf4PQApAgAAAA==.',
Al='Aleraz:BAABNQAECoElAAMDAAkKzx+XDwDHAgADAAgKCh+XDwDHAgACAAkKPwuvUwDOAQAAAA==.Allcapwne:BAAANQADCggIGgAAAA==.Alucart:BAAANQAECgIIBAAAAA==.',
An='Angela:BAABNQAECoEgAAICAAgKvB3eJACeAgACAAgKvB3eJACeAgAAAA==.Animalchin:BAAANQABCgEJAQABNQAECgcIEQAEAAAAAA==.Annadanna:BAAANQAECgUICwAAAA==.Annalunà:BAAANQAECgIJAgAAAA==.Antithicus:BAAANQADCgYIBgAAAA==.',
Ap='Apeople:BAABNQAECoEmAAIFAAgKJR4/FACRAgAFAAgKJR4/FACRAgAAAA==.Apocalýpsè:BAAANQAECgQJBgAAAA==.Applebottum:BAAANQAECgQIBAAAAA==.Applebottumj:BAAANQADCgIIAgAAAA==.Appärition:BAAANQAECgYIEQAAAA==.',
Ar='Arondael:BAAANQAECgYIDAAAAA==.',
As='Ashelaandrii:BAACNQAFFIEFAAIGAAIKpiAGEgDAAAAGAAIKpiAGEgDAAAA1AAQKgSMAAgYACQo2IxUJAFoDAAYACQo2IxUJAFoDAAAA.Astryd:BAAANQAECgcICwABNQAECgcIEAAEAAAAAA==.Asunayu:BAAANQADCgMIAwAAAA==.',
Av='Avanti:BAAANQAECgYIEQAAAA==.',
Az='Azrael:BAAANQADCgUIBQAAAA==.',
['Aù']='Aùvina:BAAANQADCgIJAgAAAA==.',
Ba='Badru:BAAANQAECgIIAwAAAA==.Bagmaster:BAABNQAECoEmAAICAAgKCCYNCABjAwACAAgKCCYNCABjAwAAAA==.Bahm:BAAANQADCgIIAgAAAA==.Ballocks:BAAANQAECggIDwAAAA==.Barthallomew:BAAANQAECgEIAQABNQAECgQICgAEAAAAAA==.Bayonetta:BAAANQAECgYICQAAAA==.',
Be='Bellann:BAAANQAECgEIAQAAAA==.',
Bi='Birghid:BAAANQABCgIIAgAAAA==.Birgite:BAAANQAECgIIAwAAAA==.',
Bl='Blackdracula:BAAANQADCggIHAAAAA==.Blasphemar:BAAANQABCggIDgAAAA==.Blazefury:BAAANQAECgMIAwAAAA==.Blazeknight:BAAANQAECggIEgAAAA==.Blazemaker:BAAANQAECgYIDwAAAA==.Blazemaster:BAAANQADCggIKQAAAA==.Blinktzy:BAAANQADCggIDQAAAA==.',
Bo='Bonecrushers:BAAANQAECgMICQAAAA==.Boohah:BAAANQADCgYICwAAAA==.Bookend:BAAANQAECgYICwAAAA==.Books:BAAANQAECgcIDgABNQAECgYICwAEAAAAAA==.',
Br='Brainbread:BAAANQAECgQIDAABNQAECgkJJAAHADkUAA==.Braski:BAAANQADCgYIBgAAAA==.Brink:BAAANQAECgEIAQAAAA==.Broadside:BAAANQADCgUIBQAAAA==.Brokil:BAAANQAECgEIAQAAAA==.Brolymorph:BAABNQAECoEdAAIIAAkKhhp3TQDAAgAIAAkKhhp3TQDAAgAAAA==.Brossiere:BAAANQADCgQIBAAAAA==.Broverheal:BAAANQAECgIIAwAAAA==.Bru:BAAANQAECgYIDAAAAA==.',
Bu='Bubbleoseven:BAAANQABCgIIAgAAAA==.Bullsmcgee:BAAANQAECgYIDwAAAA==.Burninglight:BAAANQADCgYIDAAAAA==.Burningtree:BAAANQAECgIIAwAAAA==.Buthunter:BAAANQAECgIIAwAAAA==.',
['Bê']='Bêarcub:BAAANQADCgUIBQABNQAECggINAAJACwhAA==.',
Ca='Camamoonmana:BAAANQAECgcIDAAAAA==.Caplevi:BAAANQAECgcICgAAAA==.Carrìon:BAAANQADCgEIAQAAAA==.Caskket:BAAANQADCgMIAwAAAA==.Catdog:BAAANQADCgYJBgAAAA==.Catechism:BAAANQAECgIIBAAAAA==.',
Ce='Cemeo:BAAANQADCgYICgAAAA==.Cerberusalfa:BAABNQAECoEmAAIKAAgK5SIgDgAEAwAKAAgK5SIgDgAEAwAAAA==.',
Ch='Chaningtotèm:BAAANQADCgUIBQAAAA==.Chickennuggi:BAAANQADCgQJBwABNQAFFAMIBgALALMjAA==.Chiphoof:BAAANQAECgIIBAAAAA==.Chopndot:BAAANQAECgQICgAAAA==.',
Cl='Clarabuns:BAAANQAECggIEgAAAA==.Clawdragoon:BAEBNQAECoElAAMMAAkKkhz+GQDJAgAMAAkKkhz+GQDJAgANAAUKGQRVLACoAAAAAA==.',
Co='Corine:BAAANQADCgEIAQAAAA==.Corndogmatt:BAAANQADCgUIBwAAAA==.',
Cr='Creatlach:BAACNQAFFIEJAAIGAAUKWhGoBwCOAQAGAAUKWhGoBwCOAQA1AAQKgSgAAgYACQqoIpUJAFUDAAYACQqoIpUJAFUDAAAA.Creeptoken:BAAANQADCgQIBQAAAA==.Crystallight:BAAANQAECgYICAAAAA==.',
Cy='Cytherea:BAAANQAECggICgAAAA==.',
Da='Daddybod:BAAANQADCgEIAQABNQAECgUIDQAEAAAAAA==.Dalinek:BAAANQAECgYIDgAAAA==.Dandelo:BAAANQADCgYIBgAAAA==.Danicarkel:BAABNQAECoEmAAQOAAgKIh1bAgDJAgAOAAgKIh1bAgDJAgAPAAQKUg49MgDnAAAHAAIKtQmu9ABhAAAAAA==.Darkdlord:BAAANQAECgQIBQABNQAECgUICgAEAAAAAA==.',
Dd='Ddpaladini:BAAANQAECgUICgAAAA==.',
De='Deathtracker:BAAANQAECgUICwAAAA==.Deathtrops:BAAANQAECgIIAgABNQAFFAUIDgAHAAwcAA==.Demise:BAACNQAFFIEOAAIIAAYKCAyFCwDVAQAIAAYKCAyFCwDVAQA1AAQKgSsAAggACQptHuZAAOICAAgACQptHuZAAOICAAAA.Demontickler:BAAANQADCggIDQABNQAECgYJEAAEAAAAAA==.',
Di='Dianabol:BAAANQAECgIIAgABNQAECgkJGgAGAIIkAA==.Diego:BAAANQADCgYIDAABNQADCggIEAAEAAAAAA==.Dirkuatah:BAAANQAECgIIAgAAAA==.Dista:BAABNQAECoEbAAIHAAkKuxZKMQCJAgAHAAkKuxZKMQCJAgAAAA==.Divinebovine:BAAANQAECgEIAQAAAA==.Divinedragon:BAAANQAECgYIEQAAAA==.',
Do='Doublevegan:BAAANQADCgMJAwAAAA==.',
Dr='Drakin:BAAANQAECgcIDgAAAA==.Dreya:BAAANQADCgMIAwAAAA==.Drinkcoolaid:BAABNQAECoEiAAIGAAkKchFKQwAHAgAGAAkKchFKQwAHAgAAAA==.Drinkoolaide:BAAANQADCgIIAgABNQAECgkJIgAGAHIRAA==.Drybooger:BAAANQABCgQIBQAAAA==.',
Du='Dumb:BAAANQADCgYIBgAAAA==.Dunamis:BAABNQAECoEVAAIIAAcKfRHGtgDIAQAIAAcKfRHGtgDIAQAAAA==.Dungodon:BAAANQADCggIDgAAAA==.Durrt:BAAANQAECgQICAAAAA==.Dustyolbones:BAAANQADCgcICQAAAA==.Dutchman:BAACNQAFFIELAAMQAAUKzRByCAB0AQAQAAUKSw9yCAB0AQARAAEKvhtDJABSAAA1AAQKgScAAxEACQpHJvUHAIEDABEACQpHJvUHAIEDABAACQpDHCITAJ4CAAAA.',
El='Eldrene:BAAANQAECgYIDwAAAA==.Elyseia:BAAANQAECgYIDgAAAA==.',
En='Enpower:BAAANQADCgYICwABNQAECgkJIgASAN4YAA==.',
Es='Escata:BAAANQADCgYJCgAAAA==.Españamor:BAEANQAECgcIEgAAAA==.',
Eu='Eunite:BAABNQAECoE0AAILAAgK7xoHJgBWAgALAAgK7xoHJgBWAgAAAA==.',
Fa='Falkorne:BAAANQAECgMIBAABNQAECggIHgASAP4YAA==.Farael:BAAANQABCgQIBgAAAA==.Fatalmann:BAAANQAECgIIAgAAAA==.',
Fe='Felorc:BAAANQAECgQICwABNQAECgcIEAAEAAAAAA==.',
Fi='Fintan:BAAANQADCggICAABNQAFFAUICQAGAFoRAA==.',
Fo='Forsakenemp:BAAANQADCggICQABNQAECgUICgAEAAAAAA==.',
Fr='Frassk:BAAANQAECgYIDgAAAA==.Froggystyle:BAAANQAECgQJCAAAAA==.Frozenheart:BAAANQAECgcIEAAAAA==.Fruk:BAAANQADCgUIBQAAAA==.Frösting:BAAANQADCgYIBgABNQAECgMIBgAEAAAAAA==.',
Ft='Ftx:BAABNQAECoEeAAITAAgKPx36QgCGAgATAAgKPx36QgCGAgAAAA==.',
Fu='Fundidos:BAAANQADCggIEAAAAA==.',
Ga='Garbarn:BAAANQADCgcJDQAAAA==.',
Ge='Geminichi:BAABNQAECoEiAAMSAAkK3hhhCgCtAgASAAkK3hhhCgCtAgAUAAEKhRDwUAA8AAAAAA==.',
Gh='Ghauri:BAAANQADCgYJBgAAAA==.',
Gi='Gia:BAAANQAECgYIEQAAAA==.Gigasauce:BAAANQAECgEIAQAAAA==.Giraffage:BAAANQAECgYIEwABNQADCggICAAEAAAAAA==.',
Go='Golgroth:BAAANQADCgQJBAAAAA==.Gorearrow:BAABNQAECoEjAAIRAAgKOhygLACpAgARAAgKOhygLACpAgAAAA==.',
Gr='Griffoo:BAAANQADCgEIAQAAAA==.Groggyfroggy:BAAANQADCgMJAwAAAA==.Grralt:BAAANQADCgcIBwABNQADCggIHAAEAAAAAA==.Grís:BAABNQAECoEaAAITAAgKyhSIYgAeAgATAAgKyhSIYgAeAgAAAA==.',
Ha='Hazed:BAAANQAECgMIAwAAAA==.Hazzaa:BAAANQAECgQIBAAAAA==.',
He='Herioffy:BAAANQADCgEIAQAAAA==.Hexxan:BAAANQADCgYIBgAAAA==.',
Ho='Holier:BAABNQAECoEfAAIBAAgK0AyChwCwAQABAAgK0AyChwCwAQAAAA==.Holybishh:BAAANQADCgYICwAAAA==.Holyregerts:BAAANQAECgcIEAAAAA==.Honk:BAAANQAECgQJCAAAAA==.Hoochurcooch:BAAANQADCgcJBwAAAA==.Hopperstotem:BAAANQADCgcICgAAAA==.Horsebiter:BAABNQAFFIEHAAMRAAYK1w1GDgD1AAAQAAQKRA3RDAAZAQARAAMK8QpGDgD1AAAAAA==.',
Hu='Hurrdurr:BAAANQADCgUIBQAAAA==.',
Ia='Iamanoobnow:BAAANQADCgQIBAAAAA==.',
Ic='Icys:BAAANQADCgYIDwAAAA==.',
Il='Illumi:BAAANQABCgYIBgAAAA==.',
In='Infamus:BAAANQAECgIIBQAAAA==.Invysion:BAABNQAECoEhAAIVAAkKNAbrCACbAQAVAAkKNAbrCACbAQAAAA==.',
Is='Islander:BAAANQAECgQIBAAAAA==.',
Ja='Jackychang:BAAANQADCgUIDQAAAA==.Jaidess:BAAANQADCggIDgAAAA==.Jakeypoo:BAAANQAECgQIBAAAAA==.',
Je='Jellybea:BAAANQAECgYIDQAAAA==.',
Ju='Jukoti:BAAANQABCgIIBAAAAA==.Junglebrew:BAAANQADCggJDgAAAA==.Jurisdiction:BAAANQAECgIIBAAAAA==.',
Ka='Kabea:BAAANQABCgMIAwAAAA==.Kadath:BAAANQADCgEIAQAAAA==.Kaizokuo:BAABNQAECoEdAAIUAAkKLhjRFABiAgAUAAkKLhjRFABiAgAAAA==.Kalypsoe:BAAANQADCgQIBAAAAA==.Kasey:BAAANQAECgUIEwAAAA==.Kazarke:BAAANQADCgUIBQAAAA==.',
Ke='Keenlan:BAAANQADCgMIAwAAAA==.Keho:BAAANQAECgIIBAAAAA==.Kerzermern:BAAANQAECgEIAQAAAA==.Kevic:BAABNQAECoEpAAMWAAkKnB+CDwDTAgAWAAkKTx6CDwDTAgAKAAkKXBpxGACTAgABNQADCggICAAEAAAAAA==.',
Kh='Khurzgan:BAAANQADCgYIBgAAAA==.',
Ki='Kilgreed:BAAANQADCgYIDgAAAA==.Killaban:BAAANQAECgcIBwAAAA==.Killbydeath:BAAANQAECgIIAwAAAA==.Kimberlyhárt:BAAANQAECgYJEAAAAA==.Kimdk:BAAANQAECgEIAQABNQAECgYJEAAEAAAAAA==.Kimdruid:BAAANQADCgQIBAAAAA==.Kissmydots:BAABNQAECoEuAAIHAAgKihVGQwBIAgAHAAgKihVGQwBIAgAAAA==.',
Ko='Kohman:BAABNQAECoEkAAMHAAkKORRPTwAfAgAHAAgKOxNPTwAfAgAPAAMKMg1KSQCOAAAAAA==.Komatose:BAAANQADCgYIBgAAAA==.Kong:BAAANQADCgIIAgAAAA==.',
Kr='Krftpnk:BAACNQAFFIETAAIKAAcK3R+6AAC1AgAKAAcK3R+6AAC1AgA1AAQKgSwAAgoACQpqJuQAAOwDAAoACQpqJuQAAOwDAAAA.Kronas:BAAANQAECgYICwAAAA==.Kronosity:BAAANQAECgYIDQABNQAECggIJgAXAFEiAA==.Kronotality:BAABNQAECoEmAAIXAAgKUSK+DQAfAwAXAAgKUSK+DQAfAwAAAA==.Kronotekken:BAAANQAECgEIAQABNQAECggIJgAXAFEiAA==.Kronotide:BAAANQADCgQIBAABNQAECggIJgAXAFEiAA==.',
Ku='Kungfukittn:BAAANQAECgQIDAAAAA==.Kurze:BAAANQAECgIIAwAAAA==.',
Ky='Kylorai:BAAANQAECgQIBAAAAA==.Kyojuro:BAAANQABCgYIBgAAAA==.',
Kz='Kzorx:BAAANQADCgYIBgAAAA==.',
La='Laimaster:BAAANQADCgcIGAAAAA==.Lakiri:BAAANQAECgYIEQAAAA==.Lascivia:BAABNQAECoEaAAIYAAgK1h4jBwClAgAYAAgK1h4jBwClAgAAAA==.Latrice:BAAANQAECgUIBQABNQAFFAUIDQAZALogAA==.Laylahh:BAAANQADCgQIBAAAAA==.',
Le='Leademon:BAAANQAECgYIDgAAAA==.Leadmln:BAAANQAECgMIAwABNQAECgYIDgAEAAAAAA==.Lebwonsamdi:BAAANQAECgEIAQABNQAECggIGgATAMoUAA==.',
Li='Lighterfluîd:BAAANQABCgIIAgABNQAECggIHwASABceAA==.Ligmadk:BAAANQADCgUIBQABNQAECgkJHwAKAHsYAA==.Lilbeebs:BAAANQAECgIIAgAAAA==.Lilflea:BAAANQAECgcIEQAAAA==.Lillidari:BAAANQAECgcICQABNQAECgkJIwAXALYiAA==.Lilzuki:BAAANQAECgEIAQAAAA==.Lilïth:BAABNQAECoEjAAIXAAkKtiIbBwBvAwAXAAkKtiIbBwBvAwAAAA==.Linguine:BAAANQADCggICAABNQAECgkJJQADAM8fAA==.Lisalisa:BAAANQAECgQICAAAAA==.Littlej:BAAANQAECgQJBAAAAA==.Littlejohn:BAABNQAECoEeAAISAAgK/hhHEAAtAgASAAgK/hhHEAAtAgAAAA==.',
Lo='Logaothe:BAAANQAECgUICgAAAA==.',
Lu='Lucky:BAAANQAECgEIAQAAAA==.Lularia:BAAANQADCgUIBQAAAA==.Lunaa:BAAANQAECgQJBAAAAA==.Lusid:BAAANQABCgYIBwAAAA==.',
Ma='Magikzy:BAAANQADCgYIBgAAAA==.Marnix:BAAANQAECgQIBQAAAA==.',
Me='Medikus:BAAANQAECgUIDQAAAA==.Megajoo:BAAANQAECgEIAQAAAA==.Melianni:BAAANQADCggIHAAAAA==.Melkinov:BAAANQABCgYIBgAAAA==.Merryl:BAAANQAECgUJBwAAAA==.',
Mf='Mfive:BAAANQAECgQIBAAAAA==.',
Mi='Mike:BAEBNQAECoEcAAIIAAkKMiJfMAAQAwAIAAkKMiJfMAAQAwAAAA==.Minijeangen:BAAANQAECgMJAwAAAA==.Missluana:BAAANQABCgEIAQAAAA==.',
Mo='Mockra:BAABNQAECoEwAAIIAAgKUBbnggA9AgAIAAgKUBbnggA9AgAAAA==.Moistmunnky:BAAANQADCgYIBgABNQAECgIIBAAEAAAAAA==.Montera:BAEANQAECgQJBgABNQAECgcIEgAEAAAAAA==.Moohammered:BAAANQAECgQIBAAAAA==.Moolou:BAAANQAECgcIEQAAAA==.Mootarded:BAAANQAECgQIBAABNQAECgcIEAAEAAAAAA==.Mordiggian:BAABNQAECoEkAAMLAAgK0CQUFQDbAgALAAgKbSQUFQDbAgAXAAMKHx8JZwAMAQAAAA==.Morechie:BAAANQAECgUIDgAAAA==.Morgatho:BAAANQABCgcICQAAAA==.Morsz:BAAANQAECgQIBQAAAA==.Mortiferon:BAABNQAECoEZAAILAAgKaxpiKgA4AgALAAgKaxpiKgA4AgAAAA==.',
Mu='Munnky:BAAANQADCgMIAwABNQAECgIIBAAEAAAAAA==.Munnkypox:BAAANQAECgIIBAAAAA==.Murkhoof:BAAANQADCgYIBgABNQAECgIIBAAEAAAAAA==.',
Na='Nakovii:BAAANQAECgUIBQAAAA==.',
Ne='Nealite:BAAANQABCgQIBwAAAA==.Neerem:BAAANQABCgYIAwAAAA==.Neferata:BAABNQAECoEbAAMHAAgKBxk7PgBYAgAHAAgKBxk7PgBYAgAPAAUKsAuWLAAGAQAAAA==.Nertmage:BAABNQAECoE0AAMJAAgKLCGnAAAbAwAJAAgKLCGnAAAbAwAIAAEKsxCSfwFFAAAAAA==.Neublood:BAAANQAECgQIBwAAAA==.',
Ni='Nicodemus:BAAANQAECgQIBAAAAA==.Nineiota:BAAANQAECgUIDQAAAA==.',
No='Noblewarrior:BAACNQAFFIEZAAITAAUKORMODACJAQATAAUKORMODACJAQA1AAQKgSwAAhMACQoiIlYQAGgDABMACQoiIlYQAGgDAAAA.Nobukawaii:BAAANQAECgMIAwAAAA==.Noctilus:BAAANQADCgcIDwAAAA==.Noke:BAAANQAECgIJAgAAAA==.Notakoala:BAACNQAFFIEGAAIMAAMKjhWODwD6AAAMAAMKjhWODwD6AAA1AAQKgSIAAgwACQrfHFYVAPQCAAwACQrfHFYVAPQCAAAA.Nothnx:BAAANQAFFAIIAgAAAA==.Notoriouspat:BAAANQAECgQIBAAAAA==.Novia:BAAANQAECgUIBQABNQAECggIGgATAMoUAA==.Noxeternis:BAABNQAECoEhAAMDAAgKyhreFwBRAgADAAgKyhreFwBRAgAVAAIKMgYVHABSAAAAAA==.Noy:BAAANQADCgMIAwAAAA==.Noyber:BAAANQADCgMIAwAAAA==.Noydin:BAAANQADCgYIBgAAAA==.',
['Ní']='Níghtfall:BAAANQADCgIIAgAAAA==.Nínebreaker:BAAANQADCggICgAAAA==.',
Ob='Obern:BAAANQAECgcIDAAAAA==.Oblïna:BAAANQAECgIIBAAAAA==.',
Od='Oddishh:BAAANQAECgYICwAAAA==.',
Ol='Olleg:BAAANQADCgYICQAAAA==.',
Om='Omnicarkel:BAAANQADCgcJDAAAAA==.',
On='Onsen:BAAANQAECgUIDAABNQAECgkJJAAHADkUAA==.',
Or='Orisys:BAAANQADCgQIBAAAAA==.Orkorc:BAAANQADCgQJBAAAAA==.',
Pa='Pajl:BAAANQAECgcIEQABNQAFFAUICQAaAI4XAA==.Pandablaze:BAAANQADCggIIwAAAA==.Pandajoy:BAAANQADCgEIAQAAAA==.Panterarey:BAAANQAECgIIAgAAAA==.Papanurrgle:BAAANQAECgUICQAAAA==.Papazilla:BAAANQAECgMJAwAAAA==.Parakka:BAAANQAECgIIAgAAAA==.Pawp:BAAANQAECgQICAABNQAECgkJKAACAMoWAA==.Paxiel:BAAANQAECgQIBgAAAA==.',
Pe='Pearagon:BAAANQADCgQIBAABNQAFFAUICgAGAGcdAA==.Pepsidew:BAAANQAECgMIAwAAAA==.Pepsisprite:BAAANQAECgYICwAAAA==.',
Ph='Phdbeef:BAAANQAECgEIAQABNQAECgkJIwAXALYiAA==.Phlemm:BAAANQADCgEIAQAAAA==.Phuriousdeff:BAAANQADCggIHQAAAA==.',
Pi='Picklez:BAAANQAECgQICAAAAA==.',
Po='Porkshamwich:BAAANQADCgQIBAAAAA==.Portwings:BAAANQADCggICAAAAA==.',
Ps='Psyop:BAAANQADCgcIDgABNQAECgQIDQAEAAAAAA==.Psyrax:BAAANQADCgUJBwAAAA==.',
Ra='Ragerade:BAAANQADCgEIAQAAAA==.Ramindeep:BAAANQADCgQIBAAAAA==.Razzberry:BAAANQAECgEIAQAAAA==.',
Re='Rebrowth:BAAANQADCggIDgAAAA==.Redkoala:BAAANQAECgYIBwABNQAFFAMIBgAMAI4VAA==.Repete:BAAANQAECgIIAwAAAA==.Requis:BAAANQADCgEIAQAAAA==.Resyek:BAABNQAECoE0AAIZAAgK5SGgAgAEAwAZAAgK5SGgAgAEAwAAAA==.Reven:BAAANQAECgUICAAAAA==.',
Rh='Rhak:BAAANQAECgEIAQAAAA==.',
Ro='Roguè:BAAANQAECgQICgAAAA==.Rollinburn:BAAANQADCgUJBQAAAA==.Romanoff:BAAANQAECgUIDQAAAA==.Rosearcana:BAAANQAECgEIAQAAAA==.',
['Rõ']='Rõx:BAABNQAECoE0AAIbAAgKOBrbLwBsAgAbAAgKOBrbLwBsAgAAAA==.',
Sa='Sackoss:BAAANQAECgUICQAAAA==.Saffronspark:BAAANQAECgMIBAABNQAECgcIGwAUAEQdAA==.Sainsei:BAAANQAECgQICQABNQAECggIGgATAMoUAA==.Sandwitch:BAABNQAECoE0AAIPAAgKoxKsDAAaAgAPAAgKoxKsDAAaAgAAAA==.Sargatanas:BAABNQAECoEaAAIXAAgKnA0NRACoAQAXAAgKnA0NRACoAQAAAA==.Sars:BAAANQADCgUIBQABNQAECgMIAwAEAAAAAA==.',
Sc='Schrodinger:BAAANQAECgIIBAAAAA==.Scravenhoof:BAAANQADCgYIBgAAAA==.',
Se='Seraphael:BAAANQADCgIIAgAAAA==.Severum:BAAANQAECgYIDwAAAA==.',
Sh='Shadrad:BAAANQAECggIDgAAAA==.Shallot:BAABNQAECoEiAAIIAAkKhR6nIgA8AwAIAAkKhR6nIgA8AwAAAA==.Shammoo:BAAANQAECgIJAgABNQAECgkJKgABAGMkAA==.Shammyd:BAAANQAECgMIAwAAAA==.Shantz:BAAANQAECgUIDwAAAA==.Shotmissed:BAAANQADCgEIAQAAAA==.',
Si='Sinterdeath:BAAANQAECgQIBAAAAA==.',
Sk='Skatervan:BAAANQADCggJEwABNQAECggIHwADAMoYAA==.Skylie:BAAANQADCgUICQAAAA==.',
Sm='Smorthian:BAAANQAECgQIBAAAAA==.',
Sn='Sniffinsteak:BAAANQAECgYJEAAAAA==.Snoosnooftww:BAAANQADCgMIAwAAAA==.',
So='Solas:BAAANQAECgEIAQAAAA==.Soryan:BAAANQAECgUIBQAAAA==.',
Sp='Spankenstine:BAAANQAECgcIDwAAAA==.Sparkyy:BAAANQAECgIIAgAAAA==.Sphaeram:BAAANQAECgUIBQAAAA==.Spicypepsi:BAAANQADCgEIAQAAAA==.Spinfalldown:BAAANQAECgMIAwAAAA==.',
St='Stanfield:BAAANQADCgIIAgAAAA==.Stash:BAAANQAECgUIEAAAAA==.Stinkydeathy:BAAANQADCgYJBgABNQADCggIHQAEAAAAAA==.Stinkydragon:BAAANQADCggIHQAAAA==.Stormknight:BAAANQADCggIIAAAAA==.',
Su='Suneater:BAAANQAECgQIBAAAAA==.Superpi:BAAANQADCgYIBgABNQAECgUICAAEAAAAAA==.Superret:BAAANQAECgUICAAAAA==.Suzygreen:BAAANQADCgQIBAAAAA==.',
Sv='Svetllama:BAAANQAECgMIAwAAAA==.',
Sw='Swíper:BAABNQAECoEcAAMFAAkKaCCKBQBSAwAFAAkKaCCKBQBSAwAcAAUKLgtbLwAIAQAAAA==.',
Sy='Sylphièl:BAABNQAECoEcAAMFAAkK7g6RKQDaAQAFAAkKegmRKQDaAQAcAAYKtA1YJAB6AQAAAA==.',
Ta='Tacoknight:BAAANQADCgEIAQAAAA==.Taela:BAAANQADCgYIBgAAAA==.Talixis:BAAANQADCgYIBgAAAA==.Talwaar:BAAANQADCgMIAwAAAA==.Tandarì:BAABNQAECoEhAAIBAAkKzSFeGgAxAwABAAkKzSFeGgAxAwAAAA==.Tankenstine:BAAANQAECgYIDQABNQAECgcIDwAEAAAAAA==.Tawnii:BAAANQAECgEIAQAAAA==.Taírn:BAAANQADCgUIBgAAAA==.',
Te='Tenderloin:BAAANQAECgIIBAAAAA==.',
Th='Thanitose:BAAANQAECgIIAwAAAA==.Thevelo:BAAANQAECgEIAQABNQAECgQIBgAEAAAAAA==.Theßigshot:BAAANQADCgYIBwAAAA==.Thorul:BAAANQADCgEIAQAAAA==.Thundurus:BAABNQAECoEsAAIdAAkK+hNLNwBTAgAdAAkK+hNLNwBTAgAAAA==.',
Ti='Timmayy:BAAANQAECgIIAgABNQAECggIHgASAP4YAA==.Tindrill:BAAANQADCgMIAwABNQAECggIIAAeAIsjAA==.Tinggoskrrah:BAAANQADCggIEgAAAA==.',
To='Toasties:BAAANQAECgQIBAAAAA==.Tomraedisk:BAAANQAECgYIDwAAAA==.Toopuretodie:BAAANQADCgYIBgABNQAFFAcIEwAKAN0fAA==.Totemagoat:BAABNQAECoEjAAMGAAkKkxz+GgDRAgAGAAkKkxz+GgDRAgAdAAcK3xadVQDTAQAAAA==.',
Tr='Treefist:BAAANQADCgMIAwAAAA==.Trollietoes:BAAANQADCgcIDAAAAA==.',
Tu='Tummygummy:BAAANQAECgQIBQAAAA==.',
Tw='Twentyfour:BAABNQAECoEgAAIeAAkKyg8FGgAYAgAeAAkKyg8FGgAYAgAAAA==.',
Un='Undeadkiels:BAAANQADCggICAABNQAECgUICgAEAAAAAA==.Undeadmonks:BAAANQADCgYIBgAAAA==.',
Ur='Uraharakun:BAAANQAECgEIAQABNQAECgkJGgABAL0IAA==.',
Va='Vagalion:BAAANQADCgYICQAAAA==.Vale:BAAANQADCgYICgAAAA==.Valeshot:BAABNQAECoEaAAIRAAgK5g1nYgD8AQARAAgK5g1nYgD8AQAAAA==.Valimyr:BAAANQABCgMIBAABNQABCgUIBQAEAAAAAA==.Valkillrie:BAAANQADCggICAAAAA==.Valthyrion:BAAANQADCggIIwAAAA==.Vanhellsin:BAAANQAECgUIDAAAAA==.',
Ve='Vedbow:BAAANQADCgQIBwABNQAECgkJFgABAPoiAA==.Vedronas:BAABNQAECoEWAAIBAAkK+iKnEABoAwABAAkK+iKnEABoAwAAAA==.Veos:BAABNQAECoEdAAIZAAgKXhyMBACbAgAZAAgKXhyMBACbAgAAAA==.Verdict:BAAANQADCgYIDAAAAA==.Vern:BAAANQAECgYICgAAAA==.Vernah:BAAANQADCgIIAgABNQAECgYICgAEAAAAAA==.',
Vi='Vidar:BAAANQADCgIIAgAAAA==.',
Vo='Volætile:BAAANQADCgYIBgABNQAECgMIBgAEAAAAAA==.Vorn:BAABNQAECoE0AAIXAAgKXBdaLgAeAgAXAAgKXBdaLgAeAgAAAA==.',
['Vè']='Vèronique:BAAANQADCgMIAwAAAA==.',
Wa='Waambler:BAAANQAECgYIDgAAAA==.Waamchifu:BAAANQAECgEJAQAAAA==.Waltersight:BAAANQAECgMIBQAAAA==.Warbritt:BAAANQADCgYJBgAAAA==.Waterwalkerr:BAAANQADCgYIBgAAAA==.',
We='Weggie:BAAANQADCgUIBQAAAA==.',
Wh='Whateley:BAAANQAECgQIBAAAAA==.Whoforted:BAAANQAECgcIDwAAAA==.',
Wo='Wormchild:BAAANQADCgIIAgAAAA==.',
Wu='Wulrat:BAAANQAECgYIDgAAAA==.',
Wy='Wyle:BAAANQADCgcIEwAAAA==.',
Xe='Xelí:BAABNQAECoEyAAIGAAgKDhfzPAAiAgAGAAgKDhfzPAAiAgAAAA==.',
Xi='Xil:BAAANQAECgQIBwAAAA==.',
Xp='Xplosiv:BAAANQAECgYIDgABNQAFFAUICQAGAFoRAA==.',
Xt='Xtremes:BAAANQADCggICwABNQAECgkJIgASAN4YAA==.',
Yo='Youarefail:BAAANQADCgQIBAAAAA==.',
Yu='Yudah:BAAANQAECgEIAQABNQAECgQIBAAEAAAAAA==.',
Za='Zanghonghua:BAABNQAECoEbAAIUAAcKRB1wFgBLAgAUAAcKRB1wFgBLAgAAAA==.',
Ze='Zemy:BAABNQAECoEaAAMMAAkKryWUBwCBAwAMAAkKryWUBwCBAwANAAcK6xhREQDHAQAAAA==.Zeneca:BAAANQAECgIIAgABNQAECgkJJQADAM8fAA==.',
Zo='Zodstrike:BAAANQAECgUIDQAAAA==.Zooboo:BAAANQAECgUIDAAAAA==.',
Zu='Zugzuggler:BAAANQAECgYIEAAAAA==.',
Zy='Zyrick:BAAANQABCgcICQAAAA==.',
['Ät']='Ätticus:BAAANQADCgQIBAABNQAECgQICgAEAAAAAA==.',
['Öv']='Överpöwered:BAAANQAECgQICQABNQAECgQICgAEAAAAAA==.',
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
