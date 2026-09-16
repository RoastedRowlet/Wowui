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

local lookup = {'Unknown-Unknown','Mage-Arcane','Warlock-Demonology','Warlock-Destruction','DemonHunter-Devourer','Mage-Frost','Evoker-Preservation','Druid-Balance','Druid-Guardian','Hunter-BeastMastery','Hunter-Marksmanship','Rogue-Subtlety','Rogue-Outlaw','Druid-Restoration','Paladin-Holy','Paladin-Retribution','Priest-Discipline','DeathKnight-Unholy','Evoker-Devastation','DeathKnight-Blood','Priest-Shadow','Monk-Brewmaster','Priest-Holy','Warrior-Arms','DeathKnight-Frost','Shaman-Elemental',}
local provider = {region='US',realm='Kilrogg',name='US',type='weekly',zone=53,date='2026-09-15',data={Ac='Acanoffood:BAAANQAECgQICAAAAA==.',
Ad='Adeptus:BAEANQAECgEIAQAAAA==.',
Ae='Aeliana:BAAANQAECgMIBgAAAA==.Aerilue:BAAANQADCgMIAwAAAA==.',
Ag='Aglet:BAAANQAECgUICwAAAA==.Agriopas:BAAANQADCgEIAQABNQAECgYIDAABAAAAAA==.',
Ah='Aharon:BAAANQADCgcICwAAAA==.Aheftyzandy:BAAANQADCgMIAwAAAA==.',
Aj='Ajacz:BAAANQAECgIIAgAAAA==.',
Ak='Akariel:BAAANQAECgMIBQABNQAECgQIBgABAAAAAA==.',
Al='Alassomorph:BAAANQADCggIEwAAAA==.Albus:BAABNQAECoEXAAICAAgJAR3uOACuAgACAAgJAR3uOACuAgAAAA==.Aliira:BAAANQABCgIIAgAAAA==.Allayna:BAAANQAECgUIDAAAAA==.Aloha:BAAANQAECgEIAQAAAA==.Alysaliu:BAABNQAECoEXAAMDAAgJ4CFzGQCaAgADAAcJOSJzGQCaAgAEAAQJXRCZKAD5AAAAAA==.',
Am='Amishmage:BAAANQABCgMIAwAAAA==.Amishpaladin:BAAANQABCgIIAgABNQABCgMIAwABAAAAAA==.Amory:BAAANQADCgIIAgABNQADCggIFwABAAAAAA==.',
An='Anchor:BAAANQADCgQICAAAAA==.Andja:BAAANQAECgYIEQAAAA==.Andromedae:BAAANQAECgIIAgAAAA==.Andurìl:BAAANQADCgcIBwAAAA==.Angela:BAAANQADCgUIBgAAAA==.Angelicshado:BAAANQABCgQICgAAAA==.',
Ap='Apostasy:BAAANQAECgQICgAAAA==.',
Ar='Arienh:BAAANQABCgYIBQAAAA==.Armorythis:BAAANQAECgEIAQAAAA==.Arngrum:BAAANQADCgcIFgAAAA==.Arthrex:BAAANQADCggIEgAAAA==.Arturias:BAAANQADCgYIDAABNQAECgUIDAABAAAAAA==.',
As='Ascendance:BAAANQADCgYIDgABNQAECgYICQABAAAAAA==.Ashiok:BAAANQAECgEIAQAAAA==.Asmobob:BAAANQAECgIIAgAAAA==.',
At='Atröpine:BAAANQADCgUIBgAAAA==.',
Au='Augmentin:BAAANQAECgYIEAAAAA==.Autumm:BAAANQADCgcIDQAAAA==.',
Av='Ava:BAAANQAECgQIBAAAAA==.Avanie:BAAANQADCgcIDwAAAA==.',
Aw='Aw:BAAANQADCgYIBgABNQAECgIIBAABAAAAAA==.',
Ay='Ayhae:BAAANQADCgcIDAAAAA==.',
Az='Azurelock:BAAANQADCgYICgAAAA==.',
Ba='Babycoffee:BAAANQADCgEIAQAAAA==.Backstabath:BAAANQAECgUIBQAAAA==.Bahamutz:BAAANQADCggIDAAAAA==.Bangbangdou:BAAANQAECgMIAwAAAA==.Bartlebe:BAAANQAECgIIAgAAAA==.Bastor:BAAANQAECgIIAgAAAA==.',
Be='Bearnekkid:BAAANQADCgYICwABNQAECgYICQABAAAAAA==.Bearsgomoo:BAAANQAECgMIBAAAAA==.Beneb:BAAANQADCggIDgAAAA==.Benebeorn:BAABNQAECoEZAAIFAAgJwBk5EgB4AgAFAAgJwBk5EgB4AgAAAA==.Benkinobi:BAAANQADCgYICwAAAA==.',
Bi='Bichewiche:BAAANQADCgEIAQAAAA==.Bigal:BAAANQADCgUIBgABNQAECgUICAABAAAAAA==.Billyjoe:BAAANQADCggIDgAAAA==.Bittronoxus:BAAANQAECgQIDAAAAA==.',
Bj='Bjoran:BAAANQABCgIIAgAAAA==.',
Bl='Blackheart:BAAANQABCggIDAAAAA==.Blackseraph:BAAANQADCgIIAgAAAA==.Bleys:BAAANQADCgYIEgABNQAECgUIDAABAAAAAA==.Blinky:BAAANQADCgQIBAAAAA==.',
Bo='Bobbysmerica:BAAANQAECgIIAwAAAA==.Bodikhan:BAAANQADCggICAAAAA==.',
Br='Braxte:BAAANQAECgUICwAAAA==.Breecy:BAAANQABCggIDQAAAA==.Britziola:BAAANQADCggIEgABNQADCggIFwABAAAAAA==.Brozyn:BAAANQADCgUIBQAAAA==.Brusalt:BAAANQAECgQIBAAAAA==.',
Bu='Buggies:BAABNQAECoEaAAMCAAgJyR/TOQCqAgACAAgJcx/TOQCqAgAGAAIJ8x6aFQClAAAAAA==.Buggs:BAAANQADCgcIDQABNQAECggIGgACAMkfAA==.Buldozz:BAAANQAECgYIDwAAAA==.Burnination:BAAANQAECgQICQAAAA==.Burnzie:BAAANQADCgYICQAAAA==.Butterfayce:BAAANQAECgUIDAAAAA==.',
Ca='Cadastrasz:BAABNQAECoEZAAIHAAgJnA8UEgD3AQAHAAgJnA8UEgD3AQAAAA==.Cae:BAAANQAECgQIBwAAAA==.Camachopres:BAAANQADCgQICQAAAA==.Cameocreme:BAAANQAECgIIAwAAAA==.',
Ce='Ceenit:BAAANQAECgUICwAAAA==.',
Ch='Chainedfire:BAAANQADCgYICQAAAA==.Chasefu:BAAANQADCgQIBAABNQAECgcIFgAIAD0UAA==.Chasefury:BAAANQADCgMIAwABNQAECgcIFgAIAD0UAA==.Chasemon:BAABNQAECoEWAAMIAAcJPRRQJwDvAQAIAAcJpBNQJwDvAQAJAAEJvxh0IwBIAAAAAA==.Chaser:BAAANQADCgUIBQABNQAECgcIFgAIAD0UAA==.Chasergoonie:BAAANQADCgcICwABNQAECgcIFgAIAD0UAA==.Chasewise:BAAANQADCggIEAABNQAECgcIFgAIAD0UAA==.Chazz:BAAANQADCgcIBwAAAA==.Chaøtical:BAAANQAECgIIAgAAAA==.Chelsilly:BAAANQAECgQICAAAAA==.Chicosan:BAAANQADCgYIDwAAAA==.Chowfu:BAAANQADCgEIAQAAAA==.',
Co='Corien:BAAANQADCgcICQAAAA==.',
Cr='Crow:BAAANQAECgcIDQAAAQ==.Cryomara:BAAANQADCggIAgAAAA==.',
Cy='Cyndraexa:BAAANQADCgcIFgAAAA==.Cynia:BAAANQADCggIEgAAAA==.Cyrene:BAACNQAFFIETAAMKAAcJqSJ1AQCVAQALAAUJuB3XAQDcAQAKAAQJbR91AQCVAQA1AAQKgRoAAwsACQmnI0MCAJwDAAsACQmnI0MCAJwDAAoACAlkGKg0ACYCAAAA.',
Da='Daizy:BAAANQADCgYIBgAAAA==.Danika:BAAANQABCgQIBAAAAA==.Dariabell:BAAANQADCgIIAgAAAA==.Darthbane:BAAANQADCgYIEQAAAA==.Darthvada:BAAANQADCggIGwAAAA==.Darthys:BAAANQADCgUIBQAAAA==.Darthzannah:BAAANQABCgYICgAAAA==.',
De='Delia:BAAANQADCgcIBwAAAA==.Demonaria:BAAANQAECgUIDAAAAA==.Denariah:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Dernen:BAAANQADCgcIDgAAAA==.Derpnface:BAAANQADCgcIFgAAAA==.Desecration:BAAANQAECgUIBgABNQAECgcIEgABAAAAAA==.Devilsautho:BAAANQADCggICAAAAA==.',
Di='Diablos:BAAANQABCggIDgAAAA==.Dirgir:BAAANQAECgIIAgAAAA==.Disk:BAABNQAECoEaAAMMAAgJixeWCwB5AgAMAAgJixeWCwB5AgANAAIJMwNYEQBaAAAAAA==.Distonia:BAAANQAECgIIAgAAAA==.',
Dr='Dracheo:BAABNQAECoEaAAMCAAgJIBguTwBfAgACAAgJIBguTwBfAgAGAAEJuRHtJAA+AAAAAA==.Dragonbrr:BAAANQADCgMIAwABNQAECgQICQABAAAAAA==.Drakmore:BAAANQADCgUIBQABNQAECgIIBAABAAAAAA==.Drakonna:BAAANQAECgIIBAAAAA==.Drazz:BAAANQADCgIIAgABNQAECgEIAgABAAAAAA==.Dreammoon:BAAANQABCgYICQAAAA==.Dreygur:BAAANQAECgQIBAAAAA==.Droiden:BAAANQADCggIGQAAAA==.Droidetté:BAAANQADCgEIAQAAAA==.Drotar:BAAANQAECgEIAQAAAA==.',
Du='Dumbdog:BAAANQAECgcIDgABNQAFFAMIBAABAAAAAA==.Dumichauch:BAABNQAECoEaAAIOAAgJCxmsDQBOAgAOAAgJCxmsDQBOAgAAAA==.',
Eg='Egadwall:BAAANQADCgYIDAAAAA==.Eggars:BAAANQAECgIIAgAAAA==.',
Ek='Ekhor:BAAANQADCgcIDwAAAA==.',
El='Eliuwu:BAAANQADCgYIBgABNQAECgUIDAABAAAAAA==.Elyrina:BAAANQADCgQIBAABNQAECgUIDAABAAAAAA==.',
En='Enky:BAAANQAECgQICQAAAA==.Ennuendo:BAAANQADCgIIAgAAAA==.',
Ev='Eviltiger:BAAANQAFFAEIAQAAAA==.',
Ew='Ewik:BAAANQAECgUICQAAAA==.',
Fa='Faent:BAAANQADCggIDgAAAA==.Falimonki:BAAANQADCggIDgAAAA==.Falinora:BAABNQAECoEaAAIPAAgJpBwEFQC4AgAPAAgJpBwEFQC4AgAAAA==.Falstad:BAAANQAECgUICQAAAA==.Fantasticfox:BAABNQAECoEYAAMDAAgJtAUoYwBFAQADAAcJtAQoYwBFAQAEAAQJTgWrMgDBAAAAAA==.Farindor:BAAANQABCgcICAAAAA==.Fattyx:BAABNQAECoEbAAIFAAgJdyRYBgBEAwAFAAgJdyRYBgBEAwAAAA==.',
Fe='Felborn:BAAANQABCgQIBAABNQABCgQIBQABAAAAAA==.Felixs:BAAANQADCgcIFgAAAA==.Feodin:BAABNQAECoEaAAIQAAgJPyJOEwAGAwAQAAgJPyJOEwAGAwAAAA==.',
Fi='Fistariir:BAAANQADCggICAABNQAECggIFwARAAMeAA==.',
Fl='Flannigan:BAAANQABCgMIAwABNQABCgQIBQABAAAAAA==.Flatsham:BAAANQADCggIFQAAAA==.',
Fr='Friean:BAAANQAECgQIBAAAAA==.Frostitut:BAAANQAECgUIDAAAAA==.',
Fu='Furflation:BAAANQAECgIIAgAAAA==.Fuzzychunks:BAAANQADCgcIFAAAAA==.',
Ga='Gabapentin:BAAANQADCgQIBAAAAA==.Gano:BAEANQADCggIDgABNQAECggIFwASANMVAA==.Gazdk:BAAANQAECgIIAgAAAA==.',
Ge='Geekgirl:BAAANQADCgUIBQAAAA==.',
Gi='Giliandra:BAAANQADCgEIAQAAAA==.Gingerbich:BAAANQAECgEIAQAAAA==.',
Gl='Glitch:BAAANQADCgcICAABNQAECgQIBAABAAAAAA==.',
Go='Goonthar:BAAANQAECgcIDAAAAA==.Gorethak:BAAANQADCgcIFQAAAA==.',
Gr='Grindpika:BAAANQADCggICAAAAA==.Grindrage:BAAANQAECgUICAAAAA==.Gripmedaddy:BAAANQAECgEIAQAAAA==.Grollgrr:BAAANQAECgIIAwAAAA==.Grompo:BAAANQAECgEIAQABNQAECgIIBAABAAAAAA==.Grompy:BAAANQAECgIIBAAAAA==.Gruffnstuff:BAAANQADCgcIFgAAAA==.',
Gy='Gyomei:BAAANQADCgUIBQAAAA==.Gyxx:BAAANQADCggICAAAAA==.',
['Gò']='Gòaf:BAAANQAECgMIBAAAAA==.',
Ha='Haddice:BAAANQADCggIGwAAAA==.Hammerdaddy:BAAANQADCgUICQABNQAECgEIAQABAAAAAA==.Hantoll:BAAANQABCgQIBQAAAA==.',
He='Heebiejeebie:BAAANQAECgIIBAAAAA==.Hellaeus:BAAANQAECgQIBgAAAA==.Henne:BAEANQADCgUIDAAAAA==.Heswithme:BAAANQADCggICAAAAA==.',
Hi='Hisokä:BAAANQAECgUICwAAAA==.',
Ho='Holycreambar:BAAANQAECgMIBAAAAA==.Hottrikk:BAAANQABCgQICQAAAA==.',
Hu='Huckanimal:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.Huntingale:BAAANQADCgYICwAAAA==.Huntinshift:BAAANQADCgIIAgAAAA==.Hurajin:BAAANQADCgQIBwAAAA==.',
Hy='Hydronir:BAAANQAECgEIAgABNQAFFAMIBAABAAAAAA==.Hygelak:BAAANQADCggIFAAAAA==.Hypaxia:BAAANQADCggIEgAAAA==.',
Im='Immoc:BAAANQADCggIDgAAAA==.Impresario:BAAANQAECgIIAgAAAA==.',
In='Infidius:BAAANQADCggIFAAAAA==.Intodeep:BAAANQAECgUICAAAAA==.',
Ja='Jagons:BAAANQAECgIIAgAAAA==.Jahfar:BAAANQAECgEIAQAAAA==.Janara:BAAANQADCggICAAAAA==.',
Je='Jehtlock:BAAANQAECgUIDAAAAA==.',
Ji='Jimvisible:BAAANQAECgQICwAAAA==.',
Jo='Johadro:BAAANQADCgYICQAAAA==.',
Ju='Judgejobrown:BAAANQADCgMIAwAAAA==.Judgenawt:BAAANQADCgQIBQAAAA==.',
Ka='Kahlanah:BAAANQADCggICAAAAA==.Kaiá:BAAANQADCgYIBgAAAA==.Kallum:BAAANQAECgEIAQAAAA==.Kaltak:BAAANQADCggIAgAAAA==.Karn:BAAANQAECgUICgAAAA==.Karzdormi:BAEBNQAECoEaAAMTAAkJZCLpBQDgAgATAAgJ7SHpBQDgAgAHAAUJhiACEwDmAQAAAA==.Karzsera:BAEANQADCggICAABNQAECgkJGgATAGQiAA==.Kassicker:BAAANQADCgYIBgAAAA==.Kayyllynt:BAAANQAECgQIDAAAAA==.',
Ke='Keinthdra:BAAANQAECgQIBAAAAA==.Kennaea:BAAANQADCggIDgABNQAECggIGgACACAYAA==.',
Ki='Kinuye:BAAANQAECgMIAwAAAA==.',
Kr='Kraio:BAAANQAECgQIBQAAAA==.',
La='Lampard:BAAANQAECgYICQAAAA==.Landarios:BAAANQADCgcIBwABNQAECgUIDAABAAAAAA==.Langtry:BAAANQAECgQIBgAAAA==.Laraj:BAABNQAECoEbAAIKAAcJ/RXxOgAMAgAKAAcJ/RXxOgAMAgAAAA==.Larissaqt:BAEBNQAECoEfAAIQAAkJlCCMDgAxAwAQAAkJlCCMDgAxAwAAAA==.Latinhunter:BAAANQADCgcIEwAAAA==.Latinmonk:BAAANQADCgYICgAAAA==.Latinshamy:BAAANQADCggIGAAAAA==.Lavande:BAAANQAECgEIAQAAAA==.',
Le='League:BAAANQADCgUIBQAAAA==.Leara:BAAANQADCggIFQABNQAECgcIDwABAAAAAA==.Legomyagro:BAAANQAECgUICwAAAA==.Lenipi:BAAANQADCgcIDwAAAA==.Leorohan:BAAANQABCgMIAwAAAA==.Letitgo:BAAANQADCgYIBgAAAA==.',
Li='Lightshootx:BAAANQAECgEIAgAAAA==.Lilbessy:BAAANQADCggIGwAAAA==.Lizzia:BAAANQAECgIIAgAAAA==.',
Lo='Loathe:BAAANQABCggIDQAAAA==.Logrey:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Lonchainyjr:BAAANQADCgIIAgAAAA==.',
Lu='Lunabellz:BAAANQAECgEIAQAAAA==.Lunavia:BAAANQAECgIIAgAAAA==.Luxembourge:BAAANQADCgUIBQAAAA==.',
Ly='Lynch:BAAANQADCgQIBAAAAA==.',
Ma='Maalgus:BAAANQAECgEIAQAAAA==.Mad:BAAANQADCgEIAQAAAA==.Maery:BAAANQADCgEIAQAAAA==.Maladash:BAAANQADCgIIAgABNQAECggIGgAQAD8iAA==.Manachi:BAAANQADCggICAAAAA==.Mananandict:BAAANQAECgIIAgAAAA==.Margoul:BAAANQAECgQIBgAAAA==.Marikk:BAAANQABCggIEAAAAA==.Mayyhem:BAAANQAFFAMIBAAAAA==.',
Mc='Mcallister:BAAANQADCggIFwAAAA==.Mcjudgin:BAAANQADCgMIAgABNQAECgUICwABAAAAAA==.',
Me='Mechee:BAAANQADCgUIDQAAAA==.Melonballer:BAAANQADCgUIBQAAAA==.Mercý:BAAANQADCgYIDAAAAA==.Metch:BAAANQADCggIEgAAAA==.',
Mi='Mimiker:BAABNQAECoEaAAMTAAgJihl6CACLAgATAAgJihl6CACLAgAHAAEJzAHWNAApAAAAAA==.Mimilock:BAAANQADCggIFQABNQAECggIGgATAIoZAA==.Minime:BAAANQAECggIDwABNQAFFAUICQAKAP4dAA==.Miniobi:BAAANQADCgYIDgAAAA==.Mirabella:BAAANQADCgcIBwAAAA==.Mizahella:BAAANQAECgIIAgAAAA==.',
Mo='Mobo:BAAANQADCgcIFgAAAA==.Mofassa:BAAANQADCgEIAQAAAA==.Mojoso:BAAANQADCgYICwAAAA==.Mokei:BAAANQADCgcIBwAAAA==.Mondragore:BAAANQAECgQICgAAAA==.Moonsilver:BAAANQADCggIEAAAAA==.Moriko:BAAANQAECgcIEgAAAA==.Mourn:BAABNQAECoEaAAIUAAgJnR3OEgChAgAUAAgJnR3OEgChAgAAAA==.',
Mu='Muertomarrow:BAAANQADCggIDAAAAA==.Mulroth:BAAANQADCggIFAAAAA==.Mustardseed:BAAANQAECgUICwAAAA==.',
Na='Naeblis:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Naliannagoat:BAAANQAECgIIAgAAAA==.Narekstwin:BAAANQADCgYIEAABNQAECgIIAgABAAAAAA==.Narradori:BAAANQAECggIDQAAAA==.Nasrith:BAAANQAECgUIDAAAAA==.Nastro:BAAANQADCgEIAQAAAA==.Naughtica:BAAANQAECgQIBgAAAA==.Navellint:BAAANQADCggIGQAAAA==.Nawticlaws:BAAANQAECgEIAQAAAA==.Nawtifox:BAAANQADCgYIBgAAAA==.Nawtishot:BAAANQAECgUICwAAAA==.',
Ne='Neeb:BAAANQADCgYIBgAAAA==.Nekk:BAAANQAECgIIAgAAAA==.',
Ni='Niraleth:BAAANQADCgYICAAAAA==.Nitebrite:BAAANQAECgIIAgAAAA==.',
No='Noctolupus:BAAANQADCgEIAQAAAA==.Noimia:BAAANQAECgUICgAAAA==.Normanosborn:BAAANQADCgIIAgAAAA==.Notfali:BAABNQAECoEaAAIQAAgJmBoTLQBZAgAQAAgJmBoTLQBZAgAAAA==.',
Ob='Obits:BAAANQAECgIIAgAAAA==.Obscûr:BAAANQADCgcIFgAAAA==.',
Od='Oden:BAAANQAECgIIAgAAAA==.',
Ok='Oksanabaiul:BAAANQAECgIIAgABNQAECggIFwADAOAhAA==.',
Ol='Olskimonk:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.',
Om='Omgitsashami:BAAANQAECgQIBAAAAA==.',
Op='Oprawinfury:BAAANQADCgYIBgAAAA==.',
Or='Orcanist:BAAANQAECgIIAgAAAA==.Oronarcane:BAAANQADCgcICwAAAA==.',
Os='Osanyin:BAAANQAECgQICgAAAA==.',
Pa='Padray:BAABNQAECoEaAAIVAAgJrhYBEQBXAgAVAAgJrhYBEQBXAgAAAA==.Pamarolyn:BAAANQADCgYIBgAAAA==.Panhia:BAAANQADCgcIEAAAAA==.',
Pe='Pen:BAAANQAECgIIBAAAAA==.Pepperbottom:BAAANQAECgUICAAAAA==.Perforation:BAAANQAECgcIEgAAAA==.',
Pf='Pfft:BAAANQADCgYIDgABNQAECgYICQABAAAAAA==.',
Ph='Phaided:BAAANQABCgYICQAAAA==.Phoebere:BAAANQAECgIIAgAAAA==.Phungi:BAAANQAECgUICAAAAA==.',
Pi='Pinocclio:BAAANQAECgIIAgAAAA==.',
Po='Pocketwizard:BAAANQADCgYIBgAAAA==.Pomelo:BAAANQAECgEIAQAAAA==.Popeums:BAAANQAECgIIAgAAAA==.Poppyqtpi:BAAANQAECgIIAgAAAA==.Poyoh:BAAANQAECgUIDAAAAA==.',
Pr='Pravoce:BAAANQADCggIDgAAAA==.',
Pu='Purification:BAAANQAECgUIBQABNQAECgcIEgABAAAAAA==.',
['Pí']='Pínt:BAAANQAECgIIAgAAAA==.',
Ra='Radjason:BAAANQADCggIGQAAAA==.Raeagald:BAAANQADCggIDgABNQAECggIGgAUAJ0dAA==.Raelyni:BAAANQAECgUIDAAAAA==.Rajnagaran:BAAANQADCgMIAwAAAA==.Rakkah:BAAANQAECgYIEAAAAA==.Rakkuh:BAAANQADCgYIDgABNQAECgYIEAABAAAAAA==.Raveniss:BAAANQADCgcIBwAAAA==.Rawrie:BAAANQADCggIFwAAAA==.Raygun:BAAANQADCgYIBgABNQADCggIFwABAAAAAA==.Rayzorevoker:BAAANQADCgUIBQAAAA==.Rayzorlock:BAAANQAECgIIAwAAAA==.',
Re='Reconetta:BAAANQAECgQIBAAAAA==.Redhilda:BAAANQAECgEIAQAAAA==.Relyk:BAAANQADCgEIAQAAAA==.',
Ro='Rogersoner:BAAANQAECgIIAgAAAA==.Rotation:BAAANQAECgQIBgAAAA==.Rotblade:BAAANQAECgQICAAAAA==.',
Ru='Rudewenn:BAAANQADCgcIBwAAAA==.Runandhide:BAAANQADCgMIAwAAAA==.',
Ry='Ryanthomas:BAAANQADCgYICwAAAA==.',
Sa='Sammabamma:BAAANQAECgYICQAAAA==.Sapheer:BAAANQADCgQIBAAAAA==.Sathenoth:BAAANQADCgYIDAAAAA==.Sañtoro:BAAANQADCgYIFQAAAA==.',
Sc='Scy:BAAANQADCgcIDwAAAA==.',
Sh='Shadowmorn:BAAANQAECgUIBQAAAA==.Shalako:BAAANQADCgEIAQAAAA==.Shambali:BAAANQAECgcIEAAAAA==.Shamidozz:BAAANQADCgYIBgABNQAECgYIDwABAAAAAA==.Shandro:BAAANQAECgUIDAAAAA==.Shaniallon:BAAANQADCgcIBwABNQAECgQICgABAAAAAA==.Shaunï:BAAANQADCgUIBQAAAA==.Showong:BAAANQAECgQICAAAAA==.',
Si='Silentbolts:BAAANQAECggIEwABNQAECgkJHAAIANwcAA==.Silentchill:BAABNQAECoEcAAIIAAkJ3BxcDwD2AgAIAAkJ3BxcDwD2AgAAAA==.Silentspirit:BAAANQAECgMIBQABNQAECgkJHAAIANwcAA==.Sin:BAAANQADCggICAABNQAECgUIBQABAAAAAA==.Sinomen:BAAANQADCggIEAABNQAFFAUICwAWALEYAA==.',
Sk='Skyblue:BAAANQAECgIIAgAAAA==.',
Sm='Smokebull:BAAANQADCgQIBAAAAA==.',
So='Sonarak:BAAANQAECgUICwAAAA==.Sornafayne:BAAANQADCgcICwAAAA==.Sorrengail:BAAANQADCggIEwAAAA==.',
Sp='Spy:BAAANQADCgQIBAAAAA==.',
St='Stampa:BAAANQADCgcIBwAAAA==.Starcloud:BAAANQABCgQIBAAAAA==.Starrie:BAAANQAECgIIAgAAAA==.Steelhoof:BAABNQAECoEYAAILAAgJZwJrJgBKAQALAAgJZwJrJgBKAQAAAA==.Steil:BAAANQADCgMIBAAAAA==.Steponmyface:BAAANQAECgIIAgABNQAECgMIBAABAAAAAA==.Stonesoul:BAAANQADCgcIBwAAAA==.Stormfury:BAAANQAECgIIAgABNQAECgUIBQABAAAAAA==.Strucker:BAAANQADCgUIBgABNQAECgUIDAABAAAAAA==.Struckerzz:BAAANQAECgMIAwAAAA==.Struckophile:BAAANQADCgYIBgAAAA==.Struckrucker:BAAANQAECgUIDAAAAA==.',
Su='Succubussi:BAABNQAECoEZAAIDAAkJoxUFHwB1AgADAAkJoxUFHwB1AgAAAA==.Sushie:BAAANQADCgIIAgABNQAFFAQIBgAPAFELAA==.',
Sw='Swipe:BAAANQADCggICAAAAA==.',
Sy='Synge:BAAANQABCgYIDAAAAA==.Synn:BAAANQADCgQIBAABNQADCgcIBwABAAAAAA==.Syvina:BAAANQADCgcIFgAAAA==.',
Ta='Tabby:BAAANQADCgEIAQAAAA==.Taconight:BAAANQADCggIEwAAAA==.Tahtanka:BAAANQABCggICAAAAA==.Tallynz:BAAANQAECgIIAgAAAA==.Tamaru:BAAANQABCgMIBAAAAA==.Tankornot:BAAANQADCggIEgAAAA==.Tarasque:BAAANQADCgEIAQAAAA==.Tarlgreyhair:BAAANQADCgcIDwAAAA==.Tarnished:BAAANQAECgUIBwAAAA==.Tateer:BAAANQADCgcIHQAAAA==.Tateerfel:BAAANQADCgIIAgABNQADCgcIHQABAAAAAA==.Tateernugget:BAAANQADCgUIBQABNQADCgcIHQABAAAAAA==.Tawneestone:BAAANQAECgUICwAAAA==.',
Te='Teedizzle:BAAANQADCgcIDQAAAA==.Teek:BAAANQAECgQIBQAAAA==.Telandaraa:BAABNQAECoEXAAIXAAgJchyyGgBxAgAXAAgJchyyGgBxAgAAAA==.Telrae:BAAANQAECgMIBAAAAA==.Teuton:BAAANQABCgMIAwAAAA==.',
Th='Theldara:BAAANQAECgcIDwAAAA==.Themock:BAAANQADCgcIFgAAAA==.Theresjohnny:BAAANQADCgYIDAAAAA==.Thesentinel:BAAANQADCgYICwABNQAECgYICQABAAAAAA==.Theshift:BAABNQAECoEVAAMXAAgJ9RpSFQCcAgAXAAgJ9RpSFQCcAgARAAQJUQ+lDQDQAAAAAA==.Thisisjustin:BAAANQADCgcIBwAAAA==.Thoreen:BAAANQADCgEIAQAAAA==.Thrish:BAABNQAECoEYAAIKAAgJTxoOHwCPAgAKAAgJTxoOHwCPAgAAAA==.Thuggies:BAAANQADCggICAAAAA==.Thunderfist:BAAANQADCggIEAABNQAECggIGgAQAD8iAA==.',
To='Totemiclord:BAAANQAECgYIEAAAAA==.Totumdaddy:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.',
Ts='Tsavo:BAAANQADCggIFQAAAA==.',
Tu='Tukarm:BAAANQADCgUIDQAAAA==.',
Tw='Twixbolt:BAAANQAECgIIAgABNQAECgMIBAABAAAAAA==.',
Ub='Ubdead:BAAANQADCgQIBAAAAA==.Ubpriest:BAAANQAECgEIAQAAAA==.',
Va='Vampyre:BAAANQADCgIIAgAAAA==.Vayne:BAABNQAECoEaAAIYAAgJaRmjNABoAgAYAAgJaRmjNABoAgAAAA==.',
Vi='Vindenna:BAAANQAECgMIBAAAAA==.Vinge:BAEBNQAECoEXAAISAAgJ0xUGHgBLAgASAAgJ0xUGHgBLAgAAAA==.Violetxx:BAAANQAECgMIBAAAAA==.Viral:BAAANQAECgIIAgAAAA==.',
Vl='Vladi:BAAANQADCggICAAAAA==.',
Vo='Voltaic:BAAANQAECgcIDQABNQAECgcIEgABAAAAAA==.Vorsort:BAAANQADCgUIBQAAAA==.',
Vr='Vraylaros:BAAANQAECgUICwAAAA==.',
Vy='Vyrista:BAAANQADCggIGAAAAA==.Vyrzeth:BAAANQADCgEIAQAAAA==.Vyzualize:BAAANQAECgQIBAAAAA==.',
Wa='Wae:BAAANQADCgYIBgAAAA==.Waferblade:BAAANQAECgYIBgAAAA==.Waknipi:BAAANQADCgYICAAAAA==.Wartooth:BAAANQADCggIEwAAAA==.Waycaps:BAAANQAECgcIEwAAAA==.',
Wh='Wheresjohnny:BAAANQAECgUIDAAAAA==.',
Wi='Wiccked:BAAANQAECgYIEAAAAA==.Wildheitt:BAAANQAECgUIDAAAAA==.Windrange:BAAANQADCggIFQAAAA==.Wintérhoof:BAAANQADCgIIAgABNQAECgQIBAABAAAAAA==.',
Wo='Wonderpally:BAAANQADCggIEgAAAA==.Woodscale:BAAANQADCgEIAQAAAA==.Wovenbones:BAABNQAECoEYAAMSAAgJkRDUJQALAgASAAgJkRDUJQALAgAZAAIJPAUVRwBYAAAAAA==.',
Xx='Xxthequeenbe:BAAANQADCgIIAgAAAA==.',
Ya='Yar:BAAANQADCgIIAgAAAA==.',
Ye='Yergat:BAACNQAFFIEJAAMKAAUJ/h2IAAD1AQAKAAUJ/h2IAAD1AQALAAIJPQ1rCwCVAAA1AAQKgTQAAwsACQn9Jf8CAIUDAAsACQkTJP8CAIUDAAoABwlRJt8PAPkCAAAA.',
Yu='Yuhon:BAAANQADCgYIBgAAAA==.Yupa:BAAANQAECgIIAgABNQAECgcIEgABAAAAAA==.Yuzuruhanyu:BAAANQADCgYIBgABNQAECggIFwADAOAhAA==.',
Za='Zafira:BAAANQAECgYIBQAAAA==.Zainea:BAABNQAECoEeAAIXAAkJ7xpOFwCKAgAXAAkJ7xpOFwCKAgABNQAECgYIBQABAAAAAA==.Zarena:BAAANQADCgcIBwAAAA==.',
Ze='Zelblades:BAAANQADCggIDQABNQAECgUIBQABAAAAAA==.Zelrex:BAAANQAECgUIBQAAAA==.Zephyrà:BAAANQADCgYIBgAAAA==.Zerazer:BAAANQAECgIIAgAAAA==.',
Zh='Zhuntyr:BAAANQADCggIEwAAAA==.',
Zi='Zierosouls:BAAANQADCgUIBQAAAA==.Ziggedion:BAAANQAECgUIDAAAAA==.Zindar:BAAANQAECgIIAgAAAA==.Zinnfandel:BAAANQABCgQIBAAAAA==.',
Zo='Zolpidem:BAAANQADCgQIBAAAAA==.',
['Zò']='Zòmi:BAABNQAECoEYAAIaAAkJoB9CCgBMAwAaAAkJoB9CCgBMAwAAAA==.',
['Ár']='Áres:BAAANQAECgQICgAAAA==.',
['Ït']='Ïtzpäpälötl:BAAANQAECgUICAAAAA==.',
['Ðr']='Ðrstrange:BAAANQAECgIIAwAAAA==.',
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
