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

local lookup = {'Warlock-Affliction','Warlock-Destruction','Paladin-Protection','Druid-Balance','Hunter-BeastMastery','Shaman-Restoration','Unknown-Unknown','Shaman-Elemental','Monk-Windwalker','Hunter-Marksmanship','Priest-Holy','Priest-Shadow','Paladin-Holy','Paladin-Retribution','Hunter-Survival','Shaman-Enhancement','Monk-Brewmaster','Druid-Feral','DeathKnight-Blood','DeathKnight-Unholy','Warlock-Demonology','Priest-Discipline','Warrior-Protection','Druid-Restoration','DemonHunter-Havoc','Evoker-Devastation','DemonHunter-Vengeance','Warrior-Arms','Warrior-Fury','Druid-Guardian','DeathKnight-Frost','Mage-Arcane','Mage-Frost','DemonHunter-Devourer',}
local provider = {region='US',realm='Dawnbringer',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abdalhazred:BAACNQAFFH8PAAIBAAQKriA+AAAqAQABAAQKriA+AAAqAQA1AAQKfzMAAwEACgp0IhoBAGEDAAEACgpwIhoBAGEDAAIAAgqsGTdMAJsAAAAA.Abilus:BAABNQAECn8cAAIDAAYKARg8DwAbAQADAAYKARg8DwAbAQAAAA==.Abolis:BAAANQAECgQIEgAAAA==.',
Ad='Adarlan:BAAANQAECgIIAgAAAA==.Adolin:BAAANQAECgEIAQAAAA==.',
Ae='Aelianna:BAAANQAECgEIAQAAAA==.',
Ah='Ahqwanken:BAAANQADCgIIAgAAAA==.',
Ai='Aintnowei:BAAANQAECgQIBAAAAA==.',
Al='Allina:BAAANQADCgYIBgAAAA==.Alnara:BAAANQAECgUICwAAAA==.',
Am='Amoradis:BAAANQADCgYIDQAAAA==.',
An='Anarran:BAAANQAECgIIAgAAAA==.Animalfury:BAABNQAECn8hAAIEAAYK8gfsKADAAAAEAAYK8gfsKADAAAAAAA==.Anthestria:BAAANQAECgQIBwAAAA==.',
Aq='Aqurala:BAABNQAECn8nAAIFAAoK4CBkFgBBAwAFAAoK4CBkFgBBAwAAAA==.',
Ar='Arasham:BAAANQADCgQIBAABNQAECgkJHAAFAPQUAA==.Aravenn:BAABNQAECn8cAAIFAAkK9BRqeAAeAgAFAAkK9BRqeAAeAgAAAA==.Arionaa:BAAANQABCgIIAgAAAA==.Arkangel:BAAANQADCgYIBgAAAA==.Artemesia:BAAANQAECgYICQABNQAFFAQIDwAGALsgAA==.Artison:BAAANQADCgYIBgABNQAECgYIDgAHAAAAAA==.',
As='Ashiru:BAAANQADCgMIBQAAAA==.Assandra:BAAANQADCgUIBQAAAA==.',
At='Ateup:BAAANQADCgQJBQABNQAECgUICwAHAAAAAA==.Atlás:BAAANQAECgUIBwAAAA==.',
Au='Aurum:BAAANQAFFAQIBAAAAA==.',
Av='Avatartele:BAABNQAECn8pAAIIAAoKXRPfBgD7AQAIAAoKXRPfBgD7AQAAAA==.Avatartouka:BAABNQAECn88AAMGAAoKhCO3BwCEAwAGAAoKhCO3BwCEAwAIAAcK7BjNJgAhAQAAAA==.Avrala:BAAANQADCgIJAgAAAA==.Avraria:BAAANQAECggIDAAAAA==.Avylastral:BAAANQAECgIIAgAAAA==.',
Az='Azshaxa:BAACNQAFFH8RAAIJAAUKSRcHBADfAAAJAAUKSRcHBADfAAA1AAQKfywAAgkACgocGV4ZAHkCAAkACgocGV4ZAHkCAAAA.',
['Aí']='Aísling:BAAANQAECgUICAAAAA==.',
Ba='Bagador:BAABNQAECn8VAAIKAAkKHRRRJwAQAgAKAAkKHRRRJwAQAgAAAA==.Barby:BAAANQAECgEIAQAAAA==.Barrs:BAAANQADCgMIAwAAAA==.',
Be='Bearbuthealz:BAAANQAECgIIAgAAAA==.Beautifulluv:BAABNQAECn8eAAMLAAoKuxMYHwCJAQALAAoKuxMYHwCJAQAMAAYK1gqYQAArAQAAAA==.Bekabeka:BAACNQAFFH8PAAINAAQKXRY/BgBBAQANAAQKXRY/BgBBAQA1AAQKfzMAAw0ACgoQH4YZABIDAA0ACgoQH4YZABIDAA4AAQqJDVWeATgAAAAA.Bekabekabeka:BAAANQABCggJAQABNQAFFAQIDwANAF0WAA==.Belfour:BAAANQADCgQIBAAAAA==.Bera:BAAANQAECggIBAAAAA==.',
Bi='Billybobjr:BAABNQAECn8aAAIGAAoKDRgeTgArAgAGAAoKDRgeTgArAgAAAA==.',
Bl='Blackbart:BAAANQADCgQIBAAAAA==.Bloodar:BAAANQAECggIAQAAAA==.',
Bo='Bonski:BAAANQAECgIIAgAAAA==.Boomdoom:BAAANQADCgQIBAAAAA==.Boosterman:BAABNQAECn8dAAMOAAgKnB5kKgCAAQAOAAgKnB5kKgCAAQANAAEKiwtWHAE7AAAAAA==.',
Br='Brakkar:BAAANQAECgIIAgAAAA==.Brandish:BAAANQAECgEIAQAAAA==.Braxxis:BAAANQAECgYIDgABNQAFFAYIEgAPAGkSAA==.Breadstick:BAAANQAECgUIDAAAAA==.Bress:BAAANQADCgYIBgABNQAECggIGAADAG4hAA==.Brihunts:BAAANQAECgYIDQAAAA==.Britotems:BAAANQAECgEIAQAAAA==.Brutaal:BAAANQADCgQJBAAAAA==.Bruutaal:BAAANQAECgEIAQAAAA==.Bryndel:BAAANQADCgYIBgAAAA==.',
Bu='Bubsydogo:BAAANQADCggICAAAAA==.',
Ca='Cacellice:BAAANQADCggICAAAAA==.Canoodles:BAAANQAECgcICQAAAA==.',
Ce='Celaian:BAAANQAECgQICAABNQAECgQICAAHAAAAAA==.Celpanda:BAAANQAECgQICAAAAA==.',
Ch='Chadee:BAAANQADCggICAABNQAECggIFAAHAAAAAA==.Charybdia:BAAANQADCggJGwAAAA==.Cheesecake:BAABNQAECn8XAAIFAAgKIg85jQDwAQAFAAgKIg85jQDwAQAAAA==.Chidõri:BAABNQAECn8eAAQQAAoKXBXAEQBNAgAQAAkKMBPAEQBNAgAIAAQKNBQa0wDuAAAGAAEK2AG/oQAsAAAAAA==.Chunni:BAABNQAECn8gAAMRAAoK2wc3CADcAAAJAAcKxQUAQQAPAQARAAoKWwY3CADcAAAAAA==.',
Co='Codap:BAAANQADCgEIAQAAAA==.Coolbeard:BAAANQAECgQIBAAAAA==.Cortex:BAAANQAECgYICgABNQAECgoKIQASAK0bAA==.',
Cr='Crayonman:BAABNQAECn8WAAIQAAkKbRa+FAAdAgAQAAkKbRa+FAAdAgAAAA==.Cronus:BAAANQAECgYIDAABNQAECgcIDwAHAAAAAA==.Cruelkitty:BAAANQAECgQIBQAAAA==.',
Cy='Cyralai:BAAANQADCgEIAQAAAA==.',
Da='Dahlinar:BAAANQAECgQIBwAAAA==.Dalov:BAABNQAECn8bAAMNAAYKrSERSQBDAgANAAYKrSERSQBDAgAOAAQK1R8H5QBRAQAAAA==.Damageworg:BAAANQAECgEIAQAAAA==.Dankley:BAAANQAECgUICgAAAA==.Danystorm:BAAANQADCgcIBwABNQAFFAQIDwAGALsgAA==.',
Dd='Ddream:BAAANQADCgEIAQAAAA==.',
De='Deaddude:BAABNQAECn8oAAITAAgKvxujLABlAgATAAgKvxujLABlAgABNQAECgoKGQAIABMXAA==.Deathboi:BAABNQAECn8ZAAIUAAcKDg+hGwAKAQAUAAcKDg+hGwAKAQAAAA==.Deathburgur:BAAANQAECggICwAAAA==.Deathcuddles:BAAANQAECgUIEAAAAA==.Dedcow:BAABNQAECn8XAAITAAgKzwsHGgAdAQATAAgKzwsHGgAdAQAAAA==.',
Di='Diana:BAABNQAECn8lAAIFAAgKIgnKSAAiAQAFAAgKIgnKSAAiAQAAAA==.',
Do='Dontjudgemê:BAAANQADCgYJCgAAAA==.Dorcina:BAAANQADCgcICAAAAA==.Downpour:BAAANQADCgUIBQAAAA==.',
Dr='Dracthyr:BAAANQADCgYIFwAAAA==.Dragam:BAAANQAECgQIBAABNQAECgkJGwAVAHYXAA==.Dragonwarrio:BAABNQAECn8kAAIJAAoK/BwpEwDBAgAJAAoK/BwpEwDBAgAAAA==.Draltina:BAABNQAECn8XAAICAAkK+wf3IABpAQACAAkK+wf3IABpAQAAAA==.Drazira:BAAANQAECgEIAQAAAA==.Dresstokill:BAAANQADCggJEQAAAA==.Drmonkborg:BAAANQAECgUICwABNQAECgoKHQALAJYdAA==.Drovis:BAAANQADCgIIAgAAAA==.Druzzlek:BAAANQADCggIEQAAAA==.',
Du='Dubalnuar:BAAANQADCgUIEAAAAA==.Dubalpally:BAAANQADCgQIBAAAAA==.Dubaltrok:BAAANQADCgYIDgAAAA==.Dudde:BAABNQAECn8ZAAMIAAoKExenNwCYAgAIAAoKExenNwCYAgAQAAIKNAdkGgB5AAAAAA==.Dulapin:BAAANQADCgIIAgAAAA==.Duskfu:BAABNQAECn8cAAIJAAoKdxthEwC+AgAJAAoKdxthEwC+AgAAAA==.Dustylock:BAABNQAECn8bAAMVAAkKdhe1VABXAgAVAAkKdhe1VABXAgACAAEKzQeAfQAvAAAAAA==.',
Ea='Earthele:BAAANQAECgYIEgAAAA==.',
El='Elfcaster:BAAANQAECgIIAwAAAA==.Elfowl:BAAANQADCgYIBwABNQAECgkJKQALALEMAA==.',
Em='Emanonsahi:BAAANQABCgQIBAAAAA==.Emmel:BAAANQADCgcIDQAAAA==.',
Eq='Equeslucis:BAAANQAECggIBAAAAA==.',
Er='Eromir:BAAANQAECgQIBwABNQAECgUICwAHAAAAAA==.Eryi:BAAANQAECgIIAwAAAA==.',
Ev='Eviserator:BAAANQADCgYIDAAAAA==.',
Fa='Fable:BAABNQAECn8ZAAINAAgKVRgbIwBYAQANAAgKVRgbIwBYAQAAAA==.Faegen:BAAANQADCgMIAwAAAA==.Fallumn:BAAANQADCgEIAQAAAA==.Fangytooth:BAAANQADCgYIBgABNQAECgkJFgAQAG0WAA==.Faze:BAAANQAECgUICgAAAA==.',
Fb='Fbitortamilf:BAAANQAECgYICQAAAA==.',
Fe='Fenlian:BAAANQADCgIIAgAAAA==.Feydoria:BAAANQAECgQIBAAAAA==.',
Fi='Firstfira:BAAANQAECgQIBQAAAA==.',
Fr='Frontman:BAABNQAECn8bAAMNAAgKiBllVQAZAgANAAgKiBllVQAZAgAOAAIKjQ0DYwGBAAAAAA==.',
Fu='Funkycolors:BAAANQAECgQIBAABNQAECgkJGwAVAHYXAA==.',
Ga='Gabomonk:BAAANQADCgEIAQABNQAECgIIAgAHAAAAAA==.Gavrael:BAAANQADCgQIBwAAAA==.',
Ge='Genma:BAAANQAECgQIBwAAAA==.Gewch:BAAANQAECgQIBAAAAA==.',
Gi='Gitgudder:BAAANQAECgQIBQAAAA==.',
Gl='Gloçk:BAAANQAECgcIDwAAAA==.',
Go='Goofy:BAAANQAECggICwAAAA==.',
Gr='Graeae:BAAANQAECgIIAgAAAA==.Grimaldi:BAAANQAECgcICwAAAA==.Grimvaka:BAAANQADCgYIBwAAAA==.Gripforceone:BAAANQAECggIAQAAAA==.',
Gu='Gunduin:BAABNQAECn8rAAIFAAkKjBZpPwA4AQAFAAkKjBZpPwA4AQAAAA==.',
Gw='Gwinden:BAAANQADCgUIBQAAAA==.',
Gy='Gyda:BAABNQAECn87AAMLAAoKwB0CHgD5AgALAAoKwB0CHgD5AgAWAAIKCgyhIABdAAAAAA==.Gyuyuki:BAABNQAECn8vAAIIAAoKYg2qCQDMAQAIAAoKYg2qCQDMAQAAAA==.',
['Gó']='Gódofwàr:BAAANQAECgIIAgAAAA==.',
Ha='Haggish:BAAANQAECgQIBgAAAA==.Hakeo:BAEBNQAECn8eAAIXAAkKDSFTAgDpAQAXAAkKDSFTAgDpAQAAAA==.Hanokan:BAAANQADCgIIAgAAAA==.',
He='Heidie:BAAANQAECgUIBgAAAA==.Hermin:BAAANQADCggIDgAAAA==.',
Hi='Hikomosil:BAABNQAECn8WAAIBAAcKiA18CwCzAQABAAcKiA18CwCzAQAAAA==.',
Ho='Holdmybeerz:BAAANQADCgUIBQAAAA==.Homiekissér:BAAANQAECgcICQAAAA==.',
Hu='Hudsonhawk:BAAANQAECgEIAQAAAA==.',
['Hë']='Hëllen:BAAANQADCgIIAgAAAA==.',
['Hú']='Húñtrèss:BAAANQAECgEIAgAAAA==.',
Im='Imakittycat:BAABNQAECn8nAAIYAAkK5x2+FACiAgAYAAkK5x2+FACiAgAAAA==.Impared:BAAANQAECgYIBgABNQAECggIEAAHAAAAAA==.',
Is='Isummon:BAAANQADCgEIAQAAAA==.',
Iv='Ivey:BAAANQADCggIDAAAAA==.',
Ja='Jacburton:BAAANQADCgEIAQAAAA==.Jacenne:BAAANQAECgEIAgAAAA==.',
Je='Jenesis:BAABNQAECn8qAAMOAAoKGCBwAwDZAgAOAAoKGCBwAwDZAgANAAEKHgOZMwEkAAAAAA==.Jerkme:BAAANQAECggICQAAAA==.',
Jo='Josephyn:BAABNQAECn8iAAINAAoKEBSHIABmAQANAAoKEBSHIABmAQABNQAFFAQIDwAGALsgAA==.Jotaro:BAAANQADCgUIBQAAAA==.',
Ju='Juggernåut:BAAANQADCgMIAwAAAA==.',
Ka='Kaale:BAAANQABCgUIBwABNQAECgQIEAAHAAAAAA==.Kahoa:BAAANQAECgQIBAAAAA==.Kakuta:BAABNQAECn8zAAINAAoKfSFWDQBfAwANAAoKfSFWDQBfAwAAAA==.Kakutæ:BAAANQAECgUICQABNQAECgoKMwANAH0hAA==.Kalru:BAAANQADCgQIAQAAAA==.Kalypsso:BAAANQADCgMIAwAAAA==.Kargar:BAAANQAECgEJAgAAAA==.Karot:BAAANQAECgUICgAAAA==.Katharsis:BAABNQAECn8kAAIOAAoKqRfodQBBAgAOAAoKqRfodQBBAgAAAA==.',
Ke='Keba:BAAANQAECgIIAgABNQAFFAQIDwANAF0WAA==.Keit:BAEANQADCgUIBQABNQAFFAUIDAAZAIIWAA==.Keévs:BAAANQADCgUIBQAAAA==.',
Kh='Khalidisi:BAABNQAECn8bAAINAAgK3BzPKwC4AgANAAgK3BzPKwC4AgAAAA==.Khalizar:BAAANQADCgUIBQAAAA==.Khanna:BAAANQADCgIIAgAAAA==.Khenja:BAAANQADCgUIBQAAAA==.',
Ki='Killinthyme:BAAANQADCgYIBgAAAA==.',
Kk='Kkiilleerr:BAAANQADCgcIBwAAAA==.',
Ko='Korath:BAAANQABCgIIAgAAAA==.Korbulo:BAAANQAECgUIBwAAAA==.Korlothel:BAAANQABCgIIAgABNQAECgkJHAAFAPQUAA==.',
Kr='Kriptos:BAAANQADCgEIAQABNQADCgEIAQAHAAAAAA==.Kronar:BAAANQADCgYICQAAAA==.Kronu:BAAANQADCgYIBgAAAA==.Krumpus:BAAANQAECgEIAQAAAA==.Kryma:BAAANQAECgMIAwAAAA==.',
Ku='Kungfuuy:BAAANQADCgQIBgAAAA==.',
Ky='Kylogos:BAAANQAECgEIAQAAAA==.Kynsong:BAABNQAECn8kAAMLAAkKnhHbHgCKAQALAAkKnhHbHgCKAQAWAAEKJAHzNAAHAAAAAA==.Kysia:BAAANQAECgUICQABNQAFFAMICQAOAC0PAA==.',
['Ké']='Kéévály:BAAANQADCgYIBgAAAA==.',
['Kî']='Kîrah:BAABNQAECn8cAAILAAkKOiG3BgCEAgALAAkKOiG3BgCEAgAAAA==.',
Le='Lerazal:BAABNQAECn8WAAIaAAoKIRWgAgCgAQAaAAoKIRWgAgCgAQAAAA==.Leshah:BAAANQADCggICwAAAA==.Lexanteus:BAAANQADCgUIBQABNQAECgoKFgAaACEVAA==.',
Li='Liir:BAAANQAECgUIBQAAAA==.Lilbilly:BAAANQAECgIIAgAAAA==.Lildh:BAABNQAECn8aAAIbAAkKoA7pCQDKAAAbAAkKoA7pCQDKAAAAAA==.Liyi:BAAANQAECgEIAwAAAA==.',
Lo='Lorastyrell:BAAANQAECgEIAQAAAA==.Loughalnan:BAAANQADCgQIBAABNQAECgoKJwAFAOAgAA==.Loìsbethe:BAAANQAECgQIBgAAAA==.',
Lu='Luciferra:BAABNQAECn80AAILAAkKdx6RCwAsAgALAAkKdx6RCwAsAgABNQAFFAQIDwAGALsgAA==.Luu:BAAANQAECgMIBAABNQAECgcIDwAHAAAAAA==.',
Ly='Lytho:BAAANQAECgUIBgAAAA==.',
Ma='Magelock:BAAANQAECgIIAgABNQAECgQIBwAHAAAAAA==.Magickul:BAAANQAECgYIAQABNQAECgQIBwAHAAAAAA==.Malakii:BAAANQADCgEIAQAAAA==.Maletsy:BAAANQAECgYIEAABNQAECgkJKwAFAIwWAA==.Maliboo:BAAANQAECgcIEgAAAA==.Mandalor:BAAANQADCgEIAQAAAA==.Maxamus:BAABNQAECn8oAAMcAAoKXR3yIwApAwAcAAoKXR3yIwApAwAdAAEKVh+RKgBdAAAAAA==.',
Mc='Mceuan:BAAANQADCgIIAgAAAA==.',
Me='Medarisa:BAAANQAECgQIEgAAAA==.Mederia:BAAANQADCgEIAQAAAA==.Medívh:BAAANQAECgUIBwAAAA==.Meelly:BAAANQADCgQIBAAAAA==.Melisandr:BAAANQADCgUIBQAAAA==.Merkenier:BAABNQAECn8aAAMEAAcK9QqKXABfAQAEAAcK9QqKXABfAQAeAAEKAACZSwAAAAAAAA==.Merkshamalot:BAAANQAECgIIAgABNQAECgcIGgAEAPUKAA==.Merkur:BAAANQADCggIJAABNQAECgcIGgAEAPUKAA==.Merkurry:BAAANQADCgQIBQABNQAECgcIGgAEAPUKAA==.',
Mi='Missmayhem:BAAANQAECgQIBAAAAA==.',
Mo='Modifiedmix:BAAANQADCgUICwABNQADCggICQAHAAAAAA==.Monatazumaa:BAAANQADCggIDwAAAA==.',
Mu='Mugato:BAAANQABCgEIAQAAAA==.Murdette:BAAANQAECgUIBQABNQAECgkJJgAcAJQjAA==.',
My='Mystych:BAAANQAECggIDgAAAA==.',
['Må']='Mågi:BAAANQAECgQICAAAAA==.',
['Mé']='Méabh:BAAANQAECgIIAgABNQAECgUICAAHAAAAAA==.',
['Mö']='Möôôöõöóòòõô:BAABNQAECn8yAAMNAAgKWhM/YAD3AQANAAgKWhM/YAD3AQAOAAUKYA62HQHtAAAAAA==.',
Na='Nakednwasted:BAAANQADCgYIBgAAAA==.Nanakii:BAAANQAECgIJAwAAAA==.Nathrold:BAAANQAECgQIBgABNQAECgcIDwAHAAAAAA==.',
Ne='Neptune:BAACNQAFFH8PAAIGAAQKuyDpBABwAQAGAAQKuyDpBABwAQA1AAQKfzIAAgYACgrwH0odAPgCAAYACgrwH0odAPgCAAAA.Nerfpaladins:BAAANQAECgUIBgAAAA==.Nerfpriests:BAABNQAECn8ZAAIMAAgKORSmIwAVAgAMAAgKORSmIwAVAgAAAA==.Nerissl:BAAANQADCgIIAgAAAA==.',
Ni='Niemwa:BAAANQADCgQIBAAAAA==.Nightbird:BAAANQAECgMIAwAAAA==.Nightwingqt:BAAANQAECggICwAAAA==.Nimrock:BAAANQABCgIIAgAAAA==.Ninediewatt:BAAANQADCgcIDAAAAA==.',
['Nè']='Nèo:BAAANQADCgYIEAAAAA==.',
Ob='Obsaedia:BAAANQAECgcICwABNQAECggIFAAHAAAAAQ==.',
Od='Odysseus:BAAANQAECggIEgAAAA==.',
Ok='Oktobra:BAAANQAECgUIEAAAAA==.',
On='Onos:BAAANQADCggJCAAAAA==.',
Or='Orillin:BAABNQAECn8kAAMfAAgKchzWGABKAQAfAAgKchzWGABKAQAUAAIKdg+yygBXAAAAAA==.Orioan:BAABNQAECn8kAAIOAAgKhR9wFwDGAQAOAAgKhR9wFwDGAQAAAA==.',
Os='Osun:BAAANQAECgEIAQAAAA==.Osÿrus:BAAANQADCgQIBAAAAA==.',
Pa='Padcadaver:BAAANQAECgEIAQAAAA==.Paddy:BAAANQAECgUICgAAAA==.Padeönwë:BAAANQAECgEIAQAAAA==.Padraig:BAAANQAECgEIAQABNQAECgEIAQAHAAAAAA==.Padspectre:BAAANQAECgEIAQAAAA==.Padtipsy:BAAANQAECgEIAQAAAA==.Padvici:BAAANQAECgEIAQAAAA==.Palantyr:BAACNQAFFH8GAAIIAAMK0g+MHADcAAAIAAMK0g+MHADcAAA1AAQKf0kAAggACgp2HBYEAEMCAAgACgp2HBYEAEMCAAAA.Pallytings:BAAANQADCgQIBAAAAA==.Panurita:BAABNQAECn8eAAIGAAkKeBqFJwDGAgAGAAkKeBqFJwDGAgAAAA==.',
Pe='Pellidillion:BAAANQADCgcICwAAAA==.Pepas:BAAANQAECggIDQAAAA==.',
Po='Polgára:BAAANQAECgIIAgAAAA==.',
Pr='Prepotente:BAAANQAECgEIAQAAAA==.',
Pu='Puppysmacks:BAAANQAECgEIAQAAAA==.Purity:BAAANQAECgMIAwAAAA==.',
Qe='Qevelana:BAAANQADCgMIBAAAAA==.',
Qu='Quetzalcoatl:BAAANQADCgUICQAAAA==.',
Ra='Raambox:BAABNQAECn8kAAIcAAkK0Q2wHQCNAQAcAAkK0Q2wHQCNAQAAAA==.Raddish:BAAANQAECgUIEAAAAA==.Raedl:BAAANQAECgYICwAAAA==.Ragriefy:BAAANQADCgUIBQAAAA==.Raiinn:BAAANQADCgEIAQAAAA==.Ramantu:BAAANQADCgIJAgAAAA==.Ramranch:BAAANQAECgQIBQABNQAECgoKGgAGAA0YAA==.Randay:BAAANQAECggIDQAAAA==.Rathix:BAAANQABCgIIAQAAAA==.Raylee:BAAANQAECgMIBAAAAA==.Razuki:BAAANQAECgUICgAAAA==.',
Re='Reeker:BAAANQABCgQIAgAAAA==.Retton:BAAANQAECgUIBAABNQAECgQIEAAHAAAAAA==.Revenge:BAABNQAECn83AAIOAAgKgyUXEgDqAQAOAAgKgyUXEgDqAQAAAA==.',
Rh='Rhovanion:BAAANQADCgUIBQABNQAECggIIgATADQNAA==.Rhuac:BAAANQADCggICgAAAA==.',
Ri='Riddik:BAAANQADCggIDQAAAA==.Rifle:BAAANQAECgUIBgABNQAECgoKLgAIAKsSAA==.Rika:BAAANQAECgQIBgAAAA==.',
Ro='Robolich:BAABNQAECn8ZAAITAAgKCSDBAwAsAgATAAgKCSDBAwAsAgAAAA==.Rosefist:BAEANQAECgUIBQAAAA==.Rosemourne:BAEANQADCggICAABNQAECgUIBQAHAAAAAA==.Roshwyn:BAAANQAECgMICAAAAA==.Rottedmeat:BAAANQAECggIDAAAAA==.',
Ru='Rubmytotems:BAABNQAECn8bAAMGAAcKxxXMHgBvAQAGAAcKxxXMHgBvAQAIAAEKAAABPwEuAAAAAA==.Ruckus:BAABNQAECn8pAAIOAAoKwhXjbgBSAgAOAAoKwhXjbgBSAgAAAA==.',
Rx='Rxmblock:BAAANQAECgEIAQAAAA==.Rxmboxx:BAAANQADCgIIAgAAAA==.',
Sa='Saelin:BAAANQAECgcICgABNQAECgQIEAAHAAAAAA==.Sareenastar:BAABNQAECn8cAAILAAkKPSWVEwAwAwALAAkKPSWVEwAwAwAAAA==.',
Sc='Scarless:BAAANQADCgcIBwAAAA==.',
Se='Seafood:BAAANQAECggIDwAAAA==.Sennara:BAAANQAECgcIDwAAAA==.Sephiróth:BAAANQAECgIIAQAAAA==.Serenitynow:BAAANQADCgYICAAAAA==.Sethworgen:BAAANQADCggICAAAAA==.',
Sh='Shadowlillee:BAAANQABCgIIAgAAAA==.Shadowmeteor:BAABNQAFFH8IAAIMAAMK5hJ+BgCrAAAMAAMK5hJ+BgCrAAAAAA==.Shakey:BAAANQAECgEIAQAAAA==.Shalen:BAAANQAECggICAAAAA==.Shamrox:BAAANQAECgYIDAAAAA==.Sharar:BAAANQAECgUJBwAAAA==.Sharker:BAAANQADCgMIAwAAAA==.Sharkerprest:BAAANQADCgYIBgAAAA==.Sharkerwarlo:BAAANQAECgEJAQAAAA==.Sharpenator:BAAANQAECgEIAQAAAA==.Sheraa:BAAANQAECgQIBgAAAA==.Shieldknight:BAAANQAECgYICQAAAA==.Shiftystrike:BAAANQAECgQIDQAAAA==.Shifushield:BAAANQADCggIEQAAAA==.Shirazormu:BAAANQAECgEIAQABNQAECgUIBQAHAAAAAA==.Shrike:BAAANQADCgYICgABNQAFFAcIFwAMABESAA==.',
Si='Silentwindy:BAAANQADCgYJCQAAAA==.Silmarkthree:BAABNQAECn8dAAIgAAgKAQ6zxAD7AQAgAAgKAQ6zxAD7AQAAAA==.Sinbåd:BAAANQADCggICgAAAA==.',
Sk='Skol:BAABNQAECn8iAAITAAgKNA22WwCDAQATAAgKNA22WwCDAQAAAA==.',
Sl='Slipknoth:BAACNQAFFH8cAAMMAAcK0RcLBQDxAQAMAAcK0RcLBQDxAQALAAYKxxBGAwDaAQA1AAQKfy4ABAwACgpFHxYLADIDAAwACQqIIhYLADIDAAsABAriFJxXAMYAABYAAwrBD6EGAHcAAAAA.',
Sn='Snakeplizken:BAAANQADCggIAQAAAA==.',
So='Sorean:BAACNQAFFH8SAAIPAAYKaRKhAAC3AQAPAAYKaRKhAAC3AQA1AAQKfyoAAw8ACgoTHOgCAPMCAA8ACgoTHOgCAPMCAAoAAQpjDdGJADUAAAAA.Sorrel:BAAANQADCggICQAAAA==.',
Sp='Specialmove:BAAANQAECgYICQAAAA==.',
St='Staghealz:BAAANQADCgYICAAAAA==.Staldorn:BAAANQADCgIIAgAAAA==.Starlet:BAAANQADCgIIAgAAAA==.Starlune:BAAANQADCgMIAwAAAA==.Stifs:BAABNQAECn8cAAIDAAoK+xFYBwCJAQADAAoK+xFYBwCJAQAAAA==.Stinkinglily:BAAANQABCgQIBwAAAA==.Stonebeard:BAAANQADCggIIQAAAA==.Stormstream:BAAANQADCgMICQAAAA==.',
Su='Suelustra:BAAANQAECgYIDgAAAA==.',
Sy='Sykotyk:BAABNQAECn8hAAIGAAkK/xfJOgB0AgAGAAkK/xfJOgB0AgAAAA==.',
Ta='Tadagain:BAAANQAECgUIEAAAAA==.Talairn:BAAANQADCgYICQAAAA==.Talix:BAAANQAECgIIAgAAAA==.Tamaira:BAAANQAECgUICQAAAA==.Tankybears:BAAANQAECgQIEAAAAA==.Tart:BAAANQAECgUICAAAAA==.',
Te='Telekinesis:BAABNQAECn8dAAQFAAgK2xUXeQAdAgAFAAgK2xUXeQAdAgAKAAYKwAYYTAAEAQAPAAEKAADNEwAxAAAAAA==.Tenara:BAABNQAECn8eAAMGAAoKPh22PABtAgAGAAoKPh22PABtAgAIAAMKmA2O+wCbAAABNQAECgQIEAAHAAAAAA==.Teos:BAAANQADCgYIBgABNQAECggIIgATADQNAA==.',
Th='Thaliak:BAAANQADCgYIBwABNQAECgQIBwAHAAAAAA==.Tharad:BAAANQAECgQIBQABNQAECgcIDwAHAAAAAA==.Tharris:BAAANQAECgEIAQAAAA==.Tholin:BAAANQADCggIEwAAAA==.Thunderlily:BAABNQAECn8VAAMgAAcKDAl0EgFuAQAgAAcKJwh0EgFuAQAhAAEKvQZURwA1AAAAAA==.',
Ti='Tinychaos:BAAANQAECgEIAgAAAA==.Tirra:BAAANQADCggIDgAAAA==.',
Tr='Tracther:BAAANQADCgYIDwAAAA==.Trapps:BAAANQADCgYIDAAAAA==.Treedemon:BAAANQADCgYIBgAAAA==.Treelock:BAABNQAECn8UAAIVAAgKDRtOcAAOAgAVAAgKDRtOcAAOAgAAAA==.Trelapin:BAAANQADCggIDQAAAA==.',
Tw='Twinrova:BAAANQADCggICAAAAA==.',
Ty='Tybearon:BAAANQADCgYIBgAAAA==.Tyrelitha:BAAANQADCgQIBgAAAA==.',
Uh='Uhtrad:BAAANQAECgcIEQAAAA==.Uhura:BAAANQADCgYIBgAAAA==.',
Ul='Ulfrir:BAAANQADCgYIBgAAAA==.Ullhr:BAAANQADCgYICwAAAA==.Ultradukes:BAAANQADCgEIAQAAAA==.',
Un='Unleashed:BAAANQAECgEIAQAAAA==.',
Ur='Ursaline:BAAANQAECgEIAQABNQAECgcICQAHAAAAAA==.',
Va='Valock:BAAANQAECgUICgAAAA==.Vanshifty:BAABNQAECn82AAIYAAgKMh9DEQDJAgAYAAgKMh9DEQDJAgAAAA==.',
Ve='Venli:BAAANQAECgMIBQAAAA==.',
Vo='Voidentine:BAAANQABCggIBgAAAA==.',
Vy='Vyx:BAAANQAECgIIAwAAAA==.',
Wa='Waffle:BAABNQAECn8YAAIFAAcK3xDBTgAVAQAFAAcK3xDBTgAVAQAAAA==.Wardaelos:BAAANQAECgEIAQAAAA==.Wargue:BAAANQAECggIEAAAAA==.Wasprepared:BAAANQADCgQIBAAAAA==.Watson:BAAANQAECgYICQABNQAECgcIDwAHAAAAAA==.',
We='Weeaboos:BAAANQADCgQICgAAAA==.Welindis:BAAANQADCgcJBwABNQAECgIIAwAHAAAAAA==.Wenus:BAAANQABCgQIAwAAAA==.',
Wh='Whofurmoover:BAAANQAECgQICQAAAA==.',
Wi='Winrodan:BAABNQAECn8YAAIDAAgKbiF0FQBVAgADAAgKbiF0FQBVAgABNQAECggIGAADAG4hAA==.Wizzard:BAAANQAECggIFAAAAQ==.',
['Wó']='Wóof:BAAANQADCgMIAwAAAA==.',
Xa='Xaandu:BAAANQADCgQIBAAAAA==.Xaris:BAAANQAECgUIEgABNQAECgkJJAALAJ4RAA==.',
Xi='Xiladin:BAAANQAECgIIBAAAAA==.',
Xt='Xtremes:BAAANQADCgcIBwAAAA==.',
['Xí']='Xíe:BAABNQAECn8aAAIXAAgKxREdFwC6AQAXAAgKxREdFwC6AQAAAA==.',
Yi='Yimm:BAAANQADCgEIAQAAAA==.',
Yo='Yourdadsadad:BAAANQAECgUIBQABNQAFFAcIEgAcAFsgAA==.',
['Yø']='Yø:BAAANQAECgQIBAAAAA==.',
Zb='Zbm:BAAANQAECgIJAgAAAA==.',
Ze='Zeldy:BAABNQAECn8kAAIFAAoKWRjDNgDGAgAFAAoKWRjDNgDGAgAAAA==.Zenthareal:BAABNQAECn8mAAMiAAkKOROHFwDxAAAiAAkKOROHFwDxAAAZAAEKYwjglAAyAAAAAA==.Zenzi:BAAANQADCgcIHAAAAA==.',
Zm='Zmaster:BAAANQAECgUIEAAAAA==.',
Zu='Zunarri:BAAANQADCgYICAABNQAECgYIDQAHAAAAAA==.',
Zw='Zwar:BAAANQADCgMJAwABNQAECgUIEAAHAAAAAA==.',
Zy='Zyri:BAAANQAECgEIAQAAAA==.',
['Ða']='Ðark:BAABNQAECn8vAAIFAAoKkh57DAAOAgAFAAoKkh57DAAOAgAAAA==.',
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
