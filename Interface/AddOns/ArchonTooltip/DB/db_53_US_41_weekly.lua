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

local lookup = {'Warlock-Destruction','Paladin-Holy','Hunter-Marksmanship','Hunter-BeastMastery','Unknown-Unknown','DeathKnight-Unholy','Druid-Restoration','Evoker-Preservation','DeathKnight-Blood','Paladin-Retribution','Monk-Windwalker','Evoker-Devastation','Rogue-Assassination','Warlock-Demonology','Warlock-Affliction','Paladin-Protection','Warrior-Protection','Shaman-Enhancement','Mage-Arcane','Mage-Frost','Shaman-Restoration','DemonHunter-Devourer','DemonHunter-Havoc','Priest-Holy','Shaman-Elemental','Priest-Shadow','DeathKnight-Frost','Monk-Mistweaver','Hunter-Survival','Evoker-Augmentation','Rogue-Subtlety','Druid-Balance',}
local provider = {region='US',realm='Bloodscalp',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abbpriest:BAAANQADCgYJBgABNQAECggJGQABAO4XAA==.Abruum:BAAANQADCgcIDAAAAA==.',
Ad='Admetus:BAABNQAECoEWAAICAAgKIBpTOwBaAgACAAgKIBpTOwBaAgAAAA==.Adobe:BAAANQADCggIGwAAAA==.',
Am='Amathal:BAAANQAECgcIDwAAAA==.',
An='Anderson:BAAANQADCgQIBAAAAA==.Ankheloios:BAAANQAECgUICgAAAA==.',
Ar='Arcanehonkey:BAAANQADCggICAAAAA==.Aredhela:BAAANQAECgcIEQAAAA==.Arias:BAAANQAECgQIBAAAAA==.Armsdealer:BAAANQADCgUIBQAAAA==.Arro:BAAANQAECgEIAQAAAA==.',
As='Ascending:BAAANQAECgQICAAAAA==.Asha:BAACNQAFFIEKAAIDAAUKbRY6CQCKAQADAAUKbRY6CQCKAQA1AAQKgR4AAwMACQrfG9kQAM4CAAMACQrfG9kQAM4CAAQAAQqxAfNJAScAAAAA.Ashveil:BAAANQADCgQIBAABNQAECgYIEwAFAAAAAA==.Astrialynn:BAAANQADCgYIBwAAAA==.Astrulawa:BAAANQAECgIIAgAAAA==.',
At='Athrea:BAABNQAECoEdAAIGAAgK5SIwIACrAgAGAAgK5SIwIACrAgAAAA==.',
Av='Avasharm:BAAANQABCgMIAwABNQABCgIIAQAFAAAAAA==.',
Ba='Barakah:BAAANQADCgIJAgAAAA==.Barnre:BAAANQAECgIIBAAAAA==.',
Bd='Bdssm:BAAANQAECgcIBwAAAA==.',
Be='Bearito:BAAANQAECgQICwAAAA==.Beefstick:BAAANQAECgYIDQAAAA==.Beserkfury:BAABNQAECoEYAAIDAAcKCgr5NgBqAQADAAcKCgr5NgBqAQAAAA==.',
Bi='Biercan:BAAANQAECgYIDAAAAA==.Bigcarl:BAAANQAECgEIAQAAAA==.Binke:BAAANQADCgQIBAAAAA==.Bittyboop:BAAANQADCgYICwABNQADCggIIAAFAAAAAA==.Bittywhite:BAAANQADCggIIAAAAA==.',
Bj='Bjarna:BAAANQAECgIIAwAAAA==.',
Bl='Blayze:BAAANQADCgUIBQAAAA==.Blinkytime:BAAANQAECgYIEwAAAA==.Bloodskull:BAAANQADCgEIAQAAAA==.Blúnt:BAAANQADCgQIBAAAAA==.',
Bo='Bobheals:BAABNQAECoEZAAIHAAgKvRWKGgA7AgAHAAgKvRWKGgA7AgAAAA==.Boibye:BAAANQAECgQICwAAAA==.Bolblock:BAAANQAECggIDwAAAA==.Bolo:BAABNQAECoEqAAIIAAkK6R5NBgA3AwAIAAkK6R5NBgA3AwAAAA==.Boostedww:BAAANQAECgQICwAAAA==.',
Br='Brambleclaw:BAABNQAECoEoAAIJAAgKriEgEwD+AgAJAAgKriEgEwD+AgAAAA==.Brayker:BAABNQAECoEoAAIKAAgKgB8NPgC2AgAKAAgKgB8NPgC2AgAAAA==.Breadoneal:BAAANQAECgYIEQAAAA==.Brewed:BAAANQAECgMIBAAAAA==.Brynjamin:BAAANQAECgQICAAAAA==.Brüenor:BAAANQAECgMIBQAAAA==.',
Bu='Bubbi:BAAANQADCgEIAQAAAA==.Bukkorosuzo:BAAANQAECgEIAQAAAA==.Burntroot:BAAANQAECgUIEQAAAA==.',
['Bá']='Bálor:BAAANQAECgMIBQAAAA==.',
Ca='Cacci:BAAANQADCgcIBwAAAA==.Caedwyn:BAAANQAECgUICgAAAA==.Camdakablam:BAAANQAECgcJEQAAAA==.Careadin:BAAANQADCgQIBAABNQAECgYIEgAFAAAAAA==.Careradin:BAAANQAECgYIEgAAAA==.Carereaper:BAAANQADCggIDAABNQAECgYIEgAFAAAAAA==.Cartilage:BAAANQAECgUIDAAAAA==.Cassieruth:BAAANQAECgcICgAAAA==.Catalei:BAAANQAECgEIAQAAAA==.',
Ce='Centrest:BAAANQADCgYJCAAAAA==.',
Ch='Chebbles:BAAANQADCgUIBgABNQAECgYIEgAFAAAAAA==.Chillidan:BAAANQAECgMIAwABNQAECgkJJAALAKEhAA==.Chivi:BAAANQADCggIDgABNQAECgcIHQAMALkfAA==.Chonkmonk:BAAANQADCgQIBAAAAA==.Chupacabrass:BAAANQAECgIIAgAAAA==.Chëbbles:BAAANQADCgQJBAABNQAECgYIEgAFAAAAAA==.',
Co='Colman:BAAANQAECgEIAQAAAA==.Coorsbanquet:BAAANQAECgYIDwAAAA==.Coorsbite:BAAANQAECgQIBgABNQAECgYIDwAFAAAAAA==.Coorslight:BAAANQADCgYIBgABNQAECgYIDwAFAAAAAA==.Corrahthecow:BAAANQADCgUIBQABNQAECgYIDwAFAAAAAA==.',
Cr='Craccjar:BAAANQADCgYIBwAAAA==.Crackjar:BAAANQADCgUICAAAAA==.Croc:BAAANQAECgYIEAAAAA==.Crudala:BAAANQADCgUIBQABNQAECgMIAgAFAAAAAA==.Crystle:BAAANQAECgUICQAAAA==.Crystlemarie:BAAANQADCgMIAwAAAA==.',
Cs='Csyasha:BAAANQADCgcIBwABNQAECgYIEAANALAKAA==.',
Cu='Cubcadet:BAAANQAECgYICwAAAA==.',
Cy='Cybear:BAAANQAECgcICwAAAA==.',
Da='Dalanora:BAABNQAECoEoAAQOAAgKSh3xMQCmAgAOAAgKSh3xMQCmAgABAAMK2RYZPwC7AAAPAAMKxREhGACoAAAAAA==.Dammned:BAAANQAECgIIAwAAAA==.Dapalyu:BAABNQAECoEYAAMKAAgKegX97QAHAQAKAAcKGQT97QAHAQAQAAUKuQXRRgCqAAAAAA==.Davidx:BAAANQADCgQIBgAAAA==.',
De='Dekig:BAAANQAECgEIAQAAAA==.Demine:BAAANQAECgMIBAAAAA==.Detrazeral:BAAANQADCggIEAAAAA==.',
Di='Dico:BAAANQAECgUIBgABNQAFFAYIFAARAH4aAA==.Dipper:BAABNQAECoEiAAIKAAgKKRdtdgARAgAKAAgKKRdtdgARAgAAAA==.',
Do='Dohan:BAAANQADCggIEAAAAA==.Dorìan:BAAANQADCggIFgAAAA==.',
Dr='Draael:BAAANQADCgQJBAAAAA==.Draetona:BAAANQADCggIDgAAAA==.',
Ee='Eeveeko:BAABNQAECoEhAAISAAgKhhkvDgBvAgASAAgKhhkvDgBvAgAAAA==.',
Ej='Ejavuday:BAABNQAECoEbAAMTAAgKqxtAbACRAgATAAgKqxtAbACRAgAUAAEKgR3tPwA1AAAAAA==.',
En='Enerchi:BAABNQAECoEkAAILAAkKoSH2BwA9AwALAAkKoSH2BwA9AwAAAA==.',
Er='Erianar:BAAANQADCgEIAQAAAA==.Ervyne:BAAANQAECgcIEgAAAA==.',
Ev='Evera:BAAANQAECgUIDgAAAA==.Evos:BAAANQADCgYJBgAAAA==.',
Ex='Exning:BAAANQADCggICAAAAA==.',
Fa='Fauci:BAAANQAECgYIBgABNQAFFAMICgANAPElAA==.',
Fe='Feihao:BAAANQAECgEIAQAAAA==.Feile:BAABNQAECoEeAAMOAAgK9gytdgDUAQAOAAgK9gytdgDUAQABAAEKzgwQdAA0AAAAAA==.Feltree:BAAANQADCgQIBAAAAA==.',
Fi='Fishbox:BAAANQABCgYIDAAAAA==.',
Fl='Flashir:BAAANQADCgIIAgAAAA==.Flinzza:BAABNQAECoEXAAMSAAgKUBj+EwABAgASAAcKOBj+EwABAgAVAAUKLBbbggBXAQAAAA==.Flyknit:BAAANQAECgUICwAAAA==.',
Fr='Fredthedh:BAABNQAECoEcAAMWAAgKRhYmIQAkAgAWAAgKyhUmIQAkAgAXAAMK+xVOZQCxAAAAAA==.Fromtheback:BAAANQAECgIIAgABNQAECgYIEQAFAAAAAA==.Frosticals:BAABNQAECoEgAAITAAkK3xwIUADRAgATAAkK3xwIUADRAgAAAA==.Frostsugar:BAAANQABCgQIBgAAAA==.',
Ga='Gaashw:BAAANQABCgQIBAAAAA==.Ganandor:BAABNQAECoEZAAINAAkKgRjaGACNAgANAAkKgRjaGACNAgAAAA==.Gaulish:BAAANQADCgcIBwAAAA==.',
Ge='Geocide:BAAANQAECgYIEQAAAA==.Getagrip:BAAANQAECgIIAgABNQAECggIJwANAFQcAA==.Gethalyn:BAAANQAECgUIBwAAAA==.',
Gh='Ghume:BAAANQAECgQIBAAAAA==.',
Gi='Gianthippo:BAAANQADCgYJCgAAAA==.Gilf:BAAANQAECggIEQABNQAFFAUICQAOAC0YAA==.',
Go='Goursh:BAAANQAECgEIAQAAAA==.',
Gr='Grizzoul:BAAANQAECgUICwAAAA==.Grreenry:BAAANQAECgEIAQAAAA==.Grumly:BAAANQAECgQICAAAAA==.',
Ha='Hanswoloqued:BAABNQAECoEfAAIOAAkKchNgSgBWAgAOAAkKchNgSgBWAgAAAA==.Haxz:BAAANQADCgUIBQAAAA==.',
He='Healufast:BAABNQAECoEeAAIYAAcKJR68OwBXAgAYAAcKJR68OwBXAgAAAA==.Heck:BAAANQADCgYIBgAAAA==.Helstrom:BAAANQADCggIDgAAAA==.',
Hj='Hjalmar:BAAANQAECgcIEQAAAA==.',
Ho='Holycõw:BAAANQAECggIEQAAAA==.Holysabeline:BAABNQAECoEoAAICAAgKpxkuMQCGAgACAAgKpxkuMQCGAgAAAA==.Hotpots:BAAANQAECggIEgAAAA==.',
Hu='Huchar:BAABNQAECoEjAAIRAAgKOhuhCwBTAgARAAgKOhuhCwBTAgAAAA==.Humpf:BAAANQADCgEIAQAAAA==.Hunterpanda:BAAANQADCgYIBgAAAA==.',
Hy='Hydraxix:BAAANQADCggICAAAAA==.Hypnose:BAAANQADCggIDgAAAA==.',
Ic='Iceblade:BAAANQAECgcICgAAAA==.',
Id='Idtrapdat:BAAANQAECgIIAgAAAA==.',
If='If:BAAANQADCgQIBAAAAA==.',
In='Incowgnito:BAAANQAECgIIAgAAAA==.',
Ir='Ironßest:BAAANQABCgUICwAAAA==.',
Ja='Jadzi:BAAANQADCgYJCwAAAA==.Jaxxion:BAAANQADCgYIBgAAAA==.',
Je='Jensthyra:BAAANQABCgcICgAAAA==.Jessaiyan:BAAANQAECgcICQAAAA==.',
Jo='Jobo:BAAANQAECgcIDgAAAA==.Jobodot:BAAANQAECgYIDwAAAA==.',
Ju='Julaudette:BAAANQADCgcIBwAAAA==.Julzaria:BAAANQAECgQIBAAAAA==.Jurny:BAAANQAECgUIDgAAAA==.',
Ka='Kahlandra:BAABNQAECoEnAAITAAgKWRUmmwAsAgATAAgKWRUmmwAsAgAAAA==.Kaizer:BAABNQAECoEuAAIZAAkK9RlgKwCuAgAZAAkK9RlgKwCuAgAAAA==.Kandera:BAAANQADCgUIBQAAAA==.Karina:BAAANQADCgUJBQABNQAECggIIAAEAD4jAA==.Karmelo:BAAANQADCgQICQAAAA==.',
Ke='Keizer:BAAANQAECgEIAQAAAA==.Keunen:BAAANQAECgQICQAAAA==.Kevlock:BAAANQADCgYIBgAAAA==.Keyzer:BAAANQAECgcICwAAAA==.',
Kh='Khanjuror:BAAANQAECgEIAQAAAA==.Khornedog:BAABNQAECoEZAAIOAAcKlRwNYAAVAgAOAAcKlRwNYAAVAgAAAA==.Khrama:BAABNQAECoEjAAIJAAgK8iPoDQAwAwAJAAgK8iPoDQAwAwAAAA==.',
Kl='Kleenonean:BAACNQAFFIENAAIaAAUKqiWzAgAqAgAaAAUKqiWzAgAqAgA1AAQKgWkAAhoACQrUJhcAAA8EABoACQrUJhcAAA8EAAAA.',
Kr='Krackjarr:BAAANQAECgYIDQAAAA==.Kredor:BAAANQAECgIIBAAAAA==.',
Ku='Kungpowbeef:BAAANQAECgIIAgAAAA==.Kurzaan:BAAANQAECgIIAgAAAA==.Kuyaj:BAAANQADCgIIAgAAAA==.',
La='Lacio:BAABNQAECoEmAAIaAAgKYAZ/MwBfAQAaAAgKYAZ/MwBfAQAAAA==.Larune:BAAANQABCgEIAQAAAA==.',
Le='Lemonpepper:BAABNQAECoEZAAIIAAkK0Q/CGAAZAgAIAAkK0Q/CGAAZAgAAAA==.Lexxix:BAAANQADCgcIDAAAAA==.Leyru:BAAANQAECgUIDAAAAA==.',
Li='Liberos:BAAANQAECgUIDAAAAA==.Littlechiken:BAAANQADCgUIBQABNQAFFAMIBgAJAIAHAA==.',
Ln='Lninedkhack:BAAANQAECgYIEwAAAA==.',
Lo='Logaar:BAABNQAECoEoAAMCAAkK+Q+GQABFAgACAAkK+Q+GQABFAgAKAAgKGwsboQCnAQAAAA==.',
Lu='Lubuu:BAAANQADCgYICwAAAA==.Lucyfurrawr:BAAANQAECggICQAAAA==.Lunala:BAAANQADCgcIBwABNQAECgMIAgAFAAAAAA==.Luxurix:BAAANQADCggIEQAAAA==.',
Ma='Magtao:BAAANQADCgYIDwAAAA==.Malexannius:BAAANQADCgYIDwAAAA==.Manastorm:BAAANQAECgQICAAAAA==.Maplebrick:BAAANQABCgIIAgAAAA==.Mariangel:BAAANQADCgEIAQAAAA==.Marric:BAAANQAECggJCgAAAA==.',
Me='Medean:BAAANQADCggICAAAAA==.Megtallica:BAAANQAECgQICAAAAA==.Mehunglow:BAAANQADCgUIBAAAAA==.Mellissaa:BAAANQADCggICgAAAA==.Mensrea:BAAANQAECgYIDAAAAA==.Merrycold:BAABNQAECoEcAAMGAAgK7BcYQgDtAQAGAAgK7BcYQgDtAQAbAAUKDhDXWQDyAAAAAA==.',
Mf='Mfgirthquake:BAABNQAECoEwAAMSAAgKayU/AwBmAwASAAgKayU/AwBmAwAVAAMKOx12qAD0AAAAAA==.',
Mi='Miisty:BAAANQAECgEIAQAAAA==.Mikklelee:BAAANQADCggIDwAAAA==.Mings:BAAANQAECgQICAAAAA==.Miniborohs:BAAANQADCgEIAQAAAA==.Mistweaver:BAABNQAECoElAAIcAAgKUiVlAwBpAwAcAAgKUiVlAwBpAwAAAA==.',
Mo='Mochi:BAABNQAECoEbAAITAAgKphXrkQBAAgATAAgKphXrkQBAAgAAAA==.Mochïi:BAAANQADCgIJBAABNQAFFAYIEgATAHMVAA==.Moghorva:BAAANQAECgEIAQAAAA==.Mojoe:BAABNQAECoEWAAIVAAcKDB+hMgBwAgAVAAcKDB+hMgBwAgAAAA==.Mommyswaggin:BAAANQAECgQIBwAAAA==.Moopster:BAABNQAECoEhAAIYAAgKViS5EgAgAwAYAAgKViS5EgAgAwAAAA==.Moopy:BAAANQAECgQIBAABNQAECggIIQAYAFYkAA==.Mootangclan:BAABNQAECoEXAAIZAAgKQBkFPwBPAgAZAAgKQBkFPwBPAgAAAA==.Moxi:BAAANQABCgIIAgAAAA==.',
Na='Nanashi:BAAANQAFFAEIAQAAAA==.Nazgru:BAAANQADCgYIDAAAAA==.',
Ne='Necros:BAAANQAECgIIAgABNQAFFAcIGAAZAD0bAA==.Neiko:BAABNQAECoEdAAINAAkK1xUCHQBtAgANAAkK1xUCHQBtAgAAAA==.Neptuneakis:BAAANQAECgYIEgAAAA==.Neptuno:BAAANQADCgEIAQABNQAECgYIEgAFAAAAAA==.Newcarsmell:BAAANQADCggIJgAAAA==.',
Ng='Ngl:BAAANQAECgQIBAAAAA==.',
Ni='Niceknife:BAAANQADCggIDQAAAA==.Nightwinger:BAAANQADCgQIBAAAAA==.Nimrose:BAAANQAECgIIAgAAAA==.Niquid:BAAANQAECgYICwAAAA==.Niylea:BAAANQADCgUIBQABNQAECggIHQAGAOUiAA==.',
No='Nobu:BAACNQAFFIEKAAINAAMK8SXvBwBQAQANAAMK8SXvBwBQAQA1AAQKgSIAAg0ACQqzJYMDAJADAA0ACQqzJYMDAJADAAAA.Noobhuntard:BAAANQADCggICAAAAA==.Norinari:BAACNQAFFIEJAAMOAAUKLRgmEQBFAQAOAAQKPhcmEQBFAQABAAIKyhIPDACiAAA1AAQKgS0ABA8ACQqjI8MDAJcCAA4ABwq8IRA0AJ8CAA8ABgpXJcMDAJcCAAEAAwoKG/8sAA4BAAAA.Notahealer:BAAANQAECgcIEAAAAA==.Noxloxes:BAAANQADCgIIAgAAAA==.',
Oa='Oakshre:BAABNQAECoEnAAILAAgKVyA1DgDgAgALAAgKVyA1DgDgAgAAAA==.',
Ob='Obliteration:BAAANQAECgYIDQABNQAECgkJJAALAKEhAA==.',
Od='Odsw:BAAANQADCgMJAwAAAA==.',
Oe='Oenaa:BAAANQABCgQIBAAAAA==.',
Ol='Olivertwist:BAAANQAECgQIDAABNQAECgkJJAALAKEhAA==.',
On='Ontwou:BAABNQAECoEeAAIEAAcKvx+uSwBjAgAEAAcKvx+uSwBjAgAAAA==.',
Or='Orbz:BAABNQAECoElAAITAAgKNiLRNwALAwATAAgKNiLRNwALAwAAAA==.Orcazm:BAAANQAECgEIAQAAAA==.',
Pa='Palathal:BAAANQAECgEIAQABNQAECgcIDwAFAAAAAA==.Palyont:BAAANQADCgcIFwAAAA==.Pancakezebra:BAABNQAECoEoAAIdAAkKlRqRAgDwAgAdAAkKlRqRAgDwAgAAAA==.Parse:BAAANQAECgIIAwAAAA==.',
Pe='Perdido:BAAANQADCgIIAgAAAA==.',
Ph='Phoenix:BAABNQAECoEiAAIKAAcKsx1bZgA7AgAKAAcKsx1bZgA7AgAAAA==.',
Pi='Pikechu:BAAANQAECgYIDAAAAA==.Pinkskies:BAAANQAECgIIAgAAAA==.',
Pl='Pleasy:BAAANQAECgQIBwAAAA==.Plugtobacca:BAAANQADCgIIAgABNQAFFAMICgANAPElAA==.',
Po='Pocketchange:BAABNQAECoEcAAMVAAkKxhQeRgAeAgAVAAkKxhQeRgAeAgAZAAUK5BVUkQBIAQAAAA==.Pocketwatch:BAAANQAECgQIBwABNQAECgkJHAAVAMYUAA==.',
Pr='Prayze:BAAANQADCgYIBgAAAA==.Preservation:BAAANQADCgIIAgABNQAECggIJQAcAFIlAA==.Promethêus:BAAANQAECgEIAQAAAA==.',
Pu='Purefriction:BAAANQADCgYICQAAAA==.Purehate:BAAANQAECgUIDAAAAA==.',
Qr='Qrz:BAAANQADCgMIAwAAAA==.',
Rb='Rbackwards:BAAANQADCgUIBQABNQAECggIJwAOAIsbAA==.',
Re='Relovan:BAAANQAECgYIEAAAAA==.Renothidan:BAABNQAECoEeAAIKAAkK9Ba5XABXAgAKAAkK9Ba5XABXAgAAAA==.Ret:BAAANQADCgcICQABNQAECggIMAASAGslAA==.Reuben:BAAANQAECgEIAQAAAA==.Revin:BAAANQAECgYIEQAAAA==.Revrynth:BAABNQAECoEdAAQMAAcKuR9RDQByAgAMAAcKuR9RDQByAgAeAAQKvhXqEQDlAAAIAAEK4hOmRQBHAAAAAA==.Rexorcist:BAAANQAECgYICQAAAA==.',
Ri='Rimed:BAABNQAECoEbAAMTAAcKGBCY1AC3AQATAAcKIQ+Y1AC3AQAUAAEKaBABQAA1AAAAAA==.Rippèd:BAAANQADCgYIBgAAAA==.Rithcice:BAAANQADCgcIBwAAAA==.Rizzard:BAAANQAECgIIAgAAAA==.Rizzdolphler:BAACNQAFFIEJAAICAAQKtA7rDgA2AQACAAQKtA7rDgA2AQA1AAQKgSAAAwIACQoPG6EbAPECAAIACQoPG6EbAPECAAoAAwqmBa1SAVkAAAAA.',
['Rö']='Rönburgundy:BAABNQAECoEnAAIOAAgKixsMSgBXAgAOAAgKixsMSgBXAgAAAA==.',
Sa='Sanako:BAAANQAECgcIDgAAAA==.Saneros:BAAANQAECgQIBAAAAA==.',
Sc='Scraggle:BAAANQAECgEIAQAAAA==.Scuffito:BAAANQAECgMIBAAAAA==.',
Sd='Sdh:BAAANQADCgEIAQAAAA==.',
Se='Seasondpally:BAAANQADCgcIBwAAAA==.Setheron:BAAANQAECgEIAQAAAA==.',
Sh='Shlea:BAABNQAECoEcAAIeAAkKAApSCgChAQAeAAkKAApSCgChAQAAAA==.Shley:BAAANQADCgYIBgABNQAECgkJHAAeAAAKAA==.',
Si='Silvanna:BAAANQAECgEIAQAAAA==.Sivi:BAAANQAECgIIAgAAAA==.',
Sl='Slinkstir:BAAANQADCgYIBgAAAA==.',
So='Solendros:BAAANQAECgQIBAAAAA==.Sonoa:BAAANQAECgcICAAAAA==.Sonthar:BAAANQADCgQJBAAAAA==.Sorix:BAAANQADCgIIAgAAAA==.Sorlight:BAAANQAECgUICQAAAA==.Soulelf:BAAANQADCgEIAQAAAA==.Sourpets:BAAANQAECgYIDQAAAA==.Sourwords:BAAANQAECgEIAQAAAA==.',
St='Standarshh:BAABNQAECoEeAAIEAAkKmBjwMAC4AgAEAAkKmBjwMAC4AgAAAA==.Stevenz:BAAANQAECgcIEQAAAA==.Stillflygon:BAAANQADCgYIDgAAAA==.Stormcare:BAAANQADCgUIBQAAAA==.',
Su='Subtle:BAABNQAECoEnAAMNAAgKVBwyGgCDAgANAAgK/xsyGgCDAgAfAAYKPxYaIAC5AQAAAA==.Sugarbabi:BAAANQAECggIEwAAAA==.Sugarrush:BAAANQADCggIDQAAAA==.Sugarshot:BAAANQAECgIIAgAAAA==.Sugartotem:BAAANQAECgIIBAAAAA==.Sunmere:BAAANQADCgUIBQAAAA==.',
Sw='Swiftwing:BAAANQADCgQIBAAAAA==.',
Sy='Sydarliia:BAAANQAECgYIEAAAAA==.Sylrianah:BAABNQAECoEoAAIYAAgKEA59ZQC7AQAYAAgKEA59ZQC7AQAAAA==.Sylveste:BAABNQAECoEXAAICAAkK/RmhJQC7AgACAAkK/RmhJQC7AgAAAA==.',
Ta='Tal:BAAANQAECggICgABNQAECggIEQAFAAAAAA==.Talridor:BAAANQADCgcIBgAAAA==.Tankhiskhan:BAAANQAECgYIEAAAAA==.',
Te='Tei:BAAANQADCgEIAQAAAA==.Terily:BAAANQADCgcICgAAAA==.',
Th='Thannill:BAAANQAECgYIEwAAAA==.',
Ti='Ticktoklock:BAAANQADCgIIAgAAAA==.Tie:BAABNQAECoEYAAIQAAcK9hd9HwC+AQAQAAcK9hd9HwC+AQAAAA==.Tirala:BAAANQAECgcICwAAAA==.',
To='Tomari:BAAANQABCgEIAQAAAA==.Torzhu:BAAANQAECgUIEwAAAA==.Toy:BAAANQAECgcIDQABNQAFFAYIFgAIAM0XAA==.',
Tr='Trauck:BAAANQAECgEIAQAAAA==.Travvy:BAACNQAFFIEbAAMfAAgKYB4oBADeAQAfAAUKiiEoBADeAQANAAMKGhmVCQAbAQA1AAQKgSEAAx8ACQojJu0CAHcDAB8ACQpGIu0CAHcDAA0AAwr2IHRUABsBAAAA.Trevmo:BAAANQAECgcIDwAAAA==.Trexin:BAAANQAECgEIAQAAAA==.',
Tu='Turaylon:BAAANQADCgQIBAAAAA==.',
Tz='Tzuyu:BAABNQAECoEgAAMEAAgKPiMBFwAnAwAEAAgKPiMBFwAnAwADAAEKIxGVdwA4AAAAAA==.',
Ud='Uddershock:BAAANQADCggIDgAAAA==.',
Un='Unapologetic:BAAANQAECgUIBQABNQAECggIJQAcAFIlAA==.Unbreakabull:BAAANQAECggIDwAAAA==.Unver:BAAANQADCgYIBgAAAA==.',
Va='Vae:BAAANQAECgYJEQABNQAECgkJHAALACobAA==.Valka:BAAANQAECgEIAQAAAA==.',
Ve='Veldtt:BAAANQADCgIIAgAAAA==.Velera:BAAANQAECgUICAAAAA==.Veyle:BAABNQAECoEoAAMNAAgK1iPACAA1AwANAAgK1iPACAA1AwAfAAYKbx8BGgD3AQAAAA==.',
Vi='Viibryd:BAAANQAECgEIAQAAAA==.Vine:BAAANQADCgIIAgAAAA==.',
Vy='Vyndria:BAAANQADCgcIDQAAAA==.Vynstus:BAAANQADCggIFQAAAA==.Vyran:BAAANQADCgIIAgAAAA==.',
Wa='Waypal:BAAANQADCggIFwAAAA==.',
We='Weashock:BAAANQADCgYIDAAAAA==.Weasy:BAAANQAECgUIBQAAAA==.',
Wi='Windfury:BAABNQAECoEaAAISAAgKBh9YCQDOAgASAAgKBh9YCQDOAgAAAA==.Wingzard:BAABNQAECoEaAAITAAgKxxLEmwArAgATAAgKxxLEmwArAgAAAA==.',
Wo='Wowdudesame:BAAANQAECgYIDwABNQAECggIMAASAGslAA==.',
Xl='Xl:BAABNQAECoEZAAIXAAkKFxbwHwB0AgAXAAkKFxbwHwB0AgAAAA==.',
Ya='Yaitoopmfp:BAAANQAECggIEgABNQAECggIHAAGAOwXAA==.Yao:BAABNQAECoEmAAIJAAgKlSBLFwDdAgAJAAgKlSBLFwDdAgAAAA==.Yasrena:BAAANQAECgUIDwAAAA==.',
Za='Zabara:BAAANQADCgYIBgABNQAECgcIEQAFAAAAAA==.Zair:BAAANQADCgUIBQAAAA==.Zakaraki:BAABNQAECoEoAAMMAAgKah/GCADUAgAMAAgKah/GCADUAgAIAAcKqBccHADrAQAAAA==.Zaki:BAABNQAECoEcAAIWAAkKXBomEgDFAgAWAAkKXBomEgDFAgAAAA==.Zalujin:BAAANQABCgUIBAAAAA==.',
Ze='Zealot:BAAANQAECgUICgAAAA==.Zeleria:BAAANQAECgMIAgAAAA==.Zerathis:BAAANQADCgEJAQAAAA==.',
Zi='Zinbek:BAAANQADCgUIBQAAAA==.Zip:BAAANQABCgYJBgAAAA==.Zipstin:BAAANQAECgEIAQAAAA==.',
Zo='Zoo:BAAANQAECgIIAgAAAA==.Zorb:BAABNQAECoEmAAIgAAgK1h4PHADNAgAgAAgK1h4PHADNAgABNQAFFAIIAgAFAAAAAA==.Zoshow:BAAANQAECgUICgAAAA==.Zoshôw:BAAANQAECgIIAgAAAA==.',
['Zõ']='Zõshow:BAAANQAECgMJAwAAAA==.',
['Ða']='Ðaredevil:BAABNQAECoEcAAILAAkKKhsuEQC5AgALAAkKKhsuEQC5AgAAAA==.',
['Ðp']='Ðp:BAAANQAECgcIEgAAAA==.',
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
