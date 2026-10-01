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

local lookup = {'Druid-Restoration','Shaman-Restoration','Hunter-BeastMastery','DeathKnight-Unholy','DeathKnight-Frost','Paladin-Retribution','Paladin-Holy','Druid-Balance','Unknown-Unknown','Shaman-Enhancement','Shaman-Elemental','Warlock-Demonology','DemonHunter-Devourer','Priest-Shadow','Priest-Holy','Priest-Discipline','Warlock-Destruction','Paladin-Protection','Hunter-Marksmanship','Evoker-Preservation','Evoker-Devastation','DeathKnight-Blood','Warlock-Affliction','Monk-Brewmaster','Druid-Feral','Mage-Frost','Mage-Arcane','Warrior-Arms','Monk-Mistweaver','Warrior-Protection','DemonHunter-Havoc','Evoker-Augmentation','Hunter-Survival','Warrior-Fury','DemonHunter-Vengeance','Rogue-Assassination','Rogue-Subtlety','Monk-Windwalker',}
local provider = {region='US',realm="Mug'thol",name='US',type='weekly',zone=53,date='2026-09-29',data={Ad='Adjust:BAAANQAECgYICgABNQAFFAYIEQABABMbAA==.Admirlakbar:BAAANQADCgIIAgAAAA==.',
Ae='Aedrenis:BAAANQADCgUIDgAAAA==.Aegrisomnia:BAAANQABCgMIAwABNQAECgkJHAACACgfAA==.Aenstus:BAAANQADCgMJAwAAAA==.Aeropunk:BAAANQADCgIJAgAAAA==.Aerys:BAAANQAECgcIEwAAAA==.Aerøs:BAAANQAECgYIDQAAAA==.',
Ag='Aggiz:BAAANQADCgYICgABNQAECggIGwADAP8cAA==.',
Aj='Ajaxprime:BAABNQAECoEiAAMEAAgK/CVMDAAwAwAEAAgK/CVMDAAwAwAFAAEK6wjQhAAyAAAAAA==.',
Ak='Akiojonës:BAAANQADCgYIBgAAAA==.',
Al='Alfabika:BAAANQAECgQJBAAAAA==.Alzim:BAAANQAECgcIEgAAAA==.',
Am='Amoriara:BAAANQADCgUICQAAAA==.',
An='Angry:BAAANQAECgUIBwAAAA==.Ankelbiter:BAAANQAECggIEAAAAA==.Anûbis:BAAANQAECgYICgAAAA==.',
Ar='Aragos:BAAANQAECgYIDAAAAA==.Arcelon:BAAANQAECgEIAgAAAA==.Arwenatak:BAABNQAECoEcAAMGAAgKVx3ePgCPAgAGAAgKVx3ePgCPAgAHAAQK/w3inwDyAAAAAA==.',
As='Asgardian:BAAANQAECgMIAwAAAA==.Asmoon:BAABNQAFFIEMAAIIAAUKDxyVBgDCAQAIAAUKDxyVBgDCAQAAAA==.',
At='Athren:BAAANQAECgUICgAAAA==.Athrogate:BAAANQAECgYIEgAAAA==.',
Au='Auraloxious:BAAANQAECgMIAwAAAA==.',
Az='Azmun:BAAANQAECgQIBAABNQAFFAUIDAAIAA8cAA==.Azmunn:BAAANQAECgMIAwABNQAFFAUIDAAIAA8cAA==.',
Ba='Baelzadru:BAAANQAECgIIAgAAAA==.Baelzheron:BAAANQAECgIIAgAAAA==.Baksylyk:BAAANQADCgYICwABNQAECgYIDgAJAAAAAA==.Ballador:BAAANQAECgYJCQAAAA==.Barakas:BAAANQADCgUIBQAAAA==.Barakoshamma:BAABNQAECoEhAAIKAAgKNiTAAwBGAwAKAAgKNiTAAwBGAwAAAA==.Barazudar:BAABNQAECoEYAAIHAAcKoBH5XgCuAQAHAAcKoBH5XgCuAQAAAA==.Baroke:BAAANQADCgYIBgAAAA==.Barragadin:BAAANQADCgUIBQABNQAECgYJDwAJAAAAAA==.Barreta:BAABNQAECoEWAAIDAAgK7gwIcQDUAQADAAgK7gwIcQDUAQAAAA==.',
Be='Beck:BAABNQAECoEYAAMCAAcK/wPFkQAEAQACAAcK/wPFkQAEAQALAAYKIALjuQDFAAAAAA==.Beefykin:BAAANQAECgUICAAAAA==.Bellamuerté:BAAANQAECgQIBAABNQAECgcIFgAMACgYAA==.Bellámuerté:BAABNQAECoEWAAIMAAcKKBj9UQAVAgAMAAcKKBj9UQAVAgAAAA==.Bemmy:BAAANQAECgQICAABNQAECgkJHAACACgfAA==.',
Bi='Bigdrandyy:BAAANQAECgYIEgAAAA==.Biggspal:BAAANQADCgYIBgAAAA==.',
Bl='Blackbird:BAABNQAECoEcAAINAAkKmh6ECQAmAwANAAkKmh6ECQAmAwAAAA==.Blackmage:BAAANQADCgYIBgAAAA==.Bloodlordzz:BAAANQAECgYIDQAAAA==.Bloodreina:BAAANQAECgYJEAABNQAECgcIDgAJAAAAAA==.',
Bo='Bob:BAAANQAECgUIBwAAAA==.Bobtheknob:BAAANQADCggIDwAAAA==.Bockandcalls:BAAANQAECgYICgAAAA==.Bolbi:BAAANQAECgIIAwAAAA==.',
Br='Brahm:BAAANQAECgQIBQABNQAECggIGgALAIwZAA==.Brdua:BAAANQADCgYIBgAAAA==.Breadnbudda:BAAANQADCgcIHAAAAA==.Brideofloco:BAAANQABCgEIAQAAAA==.Brogar:BAAANQADCgcJGAAAAA==.',
Bu='Bubblekush:BAAANQAECgYIDAABNQAFFAYIDwAOAAsaAA==.Buffknight:BAAANQADCggIDgABNQAECggIGgALAIwZAA==.Bulkam:BAAANQAECgYIEAAAAA==.Bulkazarr:BAABNQAECoEWAAICAAcKthyKNwA7AgACAAcKthyKNwA7AgAAAA==.Burbuja:BAAANQADCggJCAABNQAECggIGgAPAKMjAA==.',
['Bù']='Bùllrùsh:BAAANQABCgEIAQAAAA==.',
Ca='Callabash:BAABNQAECoEcAAMCAAkKKxsVHgC/AgACAAkKKxsVHgC/AgALAAMKsgXPzwCHAAAAAA==.',
Ce='Celarena:BAAANQAECgYIEAAAAA==.Cermit:BAAANQAECgEIAQAAAA==.',
Ch='Cheefkdavi:BAAANQAECgEIAgABNQAECggIEQAJAAAAAA==.Chewie:BAAANQADCgUIBQAAAA==.Chilla:BAAANQADCgQIBAAAAA==.Chomrogg:BAAANQAECgYJBwAAAA==.Chopzzpala:BAAANQADCgYICAAAAA==.Choubelle:BAAANQADCgQIBAAAAA==.Chyp:BAAANQAECgYIEQAAAA==.Chzpriest:BAABNQAECoEXAAQOAAgKER/KDwDEAgAOAAcKCSDKDwDEAgAPAAgKuxNOPQAsAgAQAAEK8grnIQA0AAAAAA==.',
Ci='Cichorì:BAACNQAFFIENAAMRAAQK2hn7CgCnAAAMAAIKgiIlGQDCAAARAAIKMhH7CgCnAAA1AAQKgSIAAxEACQo0I6kFAKsCAAwABwr0I6skAL0CABEACQqyG6kFAKsCAAAA.Cipa:BAAANQADCgcIBwAAAA==.Circee:BAAANQADCgcIGwAAAA==.',
Co='Colmer:BAAANQADCgMIAwAAAA==.',
Cp='Cptvoker:BAAANQADCgIIAgAAAA==.',
Cr='Creckko:BAAANQADCgEIAQAAAA==.Crockito:BAACNQAFFIEWAAILAAUKNSWWAgAxAgALAAUKNSWWAgAxAgA1AAQKgSMAAwsACQrxJj0AAAsEAAsACQrxJj0AAAsEAAIAAQpXDubyACkAAAAA.',
Cy='Cyrusdavirus:BAAANQADCgUIBQAAAA==.',
Da='Dabu:BAAANQAECgQIBAAAAA==.Danto:BAAANQAECgQIBwABNQAECggIGgALAIwZAA==.Darc:BAAANQADCggIEgAAAA==.Darktroll:BAABNQAECoEeAAIDAAkK/BIlPABvAgADAAkK/BIlPABvAgAAAA==.',
De='Depoprovera:BAABNQAECoEkAAISAAkK/BIQGADgAQASAAkK/BIQGADgAQAAAA==.Deqz:BAABNQAECoEZAAMTAAgKMBm3IwDrAQATAAcKhRi3IwDrAQADAAEK3B0rBQFYAAAAAA==.',
Di='Diezel:BAAANQAECgIIAgABNQAECgMIAwAJAAAAAA==.Dilox:BAAANQADCggIIgAAAA==.Dinosaur:BAABNQAECoEdAAMUAAgKZBo5FAA9AgAUAAgKZBo5FAA9AgAVAAUKORYuGwBaAQABNQAECgkJHAAHAKQcAA==.Dirtydee:BAABNQAECoEcAAIWAAgK+Qk0UABvAQAWAAgK+Qk0UABvAQAAAA==.Disaaya:BAABNQAECoEeAAIDAAgK2g6XWQAVAgADAAgK2g6XWQAVAgAAAA==.Divinecheeks:BAAANQAECgIIBgAAAA==.',
Dj='Djangó:BAAANQAECgEIAQAAAA==.',
Do='Donto:BAAANQAECgMIAwABNQAECggIGgALAIwZAA==.Dontos:BAAANQAECgQICAABNQAECggIGgALAIwZAA==.Doodlebug:BAACNQAFFIEIAAIWAAQKMhi0CgBNAQAWAAQKMhi0CgBNAQA1AAQKgSgAAhYACQryHQsQAAcDABYACQryHQsQAAcDAAAA.Dooshrocket:BAAANQAECgIIAwAAAA==.Dotsntaxes:BAACNQAFFIELAAQMAAUKfQhZFwDXAAAMAAMKBwxZFwDXAAARAAIK3gK9DgB2AAAXAAEK8wDGDQAqAAA1AAQKgSIABAwACQprGXVKAC8CAAwACAoBFnVKAC8CABEABQrHElkhAFIBABcAAQqNFbIgAEkAAAAA.',
Dr='Dracom:BAAANQAECgIIAwAAAA==.Dracuujin:BAAANQADCggICAABNQAFFAUIDwAPAGwcAA==.Dralioli:BAAANQAECgYIDgAAAA==.Dreanil:BAAANQAECgcIEwAAAA==.Droho:BAABNQAECoEeAAIVAAgKbCNLBAA6AwAVAAgKbCNLBAA6AwABNQAFFAcIFwALALwaAA==.Drroog:BAAANQADCgQIBQABNQAECgEIAQAJAAAAAA==.',
Du='Dumper:BAAANQAECgIIAgAAAA==.',
Dw='Dwarfsize:BAAANQADCggICAABNQAFFAYIEQABABMbAA==.',
Dz='Dzievana:BAAANQAECgEIAQAAAA==.',
['Dâ']='Dârn:BAABNQAECoEgAAMMAAgKtCA4IADQAgAMAAgKtCA4IADQAgARAAEKASCDXwBOAAAAAA==.',
El='Eleweaver:BAAANQADCgcIDAAAAA==.Elissra:BAAANQADCgEIAQABNQAECgYIDwAJAAAAAA==.Elvispræstly:BAAANQADCgYIBgAAAA==.',
En='Enoughtalk:BAAANQAECgUICgAAAA==.',
Eo='Eostre:BAABNQAECoEaAAIPAAgKoyN3DgApAwAPAAgKoyN3DgApAwAAAA==.',
Eu='Eupherine:BAABNQAECoEYAAIPAAcK+yKmIAC1AgAPAAcK+yKmIAC1AgAAAA==.',
Ev='Evillarry:BAAANQADCgYIDAAAAA==.Evilpaladin:BAABNQAECoEgAAISAAkKyxeVEABHAgASAAkKyxeVEABHAgAAAA==.',
Ez='Ezluz:BAABNQAECoEWAAIWAAcKnhouMAARAgAWAAcKnhouMAARAgAAAA==.',
Fa='Facsimile:BAABNQAECoEbAAIOAAgKuxZtGABKAgAOAAgKuxZtGABKAgAAAA==.',
Fe='Festers:BAAANQAECggIEgAAAA==.',
Fi='Fingerwalk:BAABNQAECoEaAAIYAAcKqBI3EACiAQAYAAcKqBI3EACiAQAAAA==.',
Fl='Flappi:BAABNQAECoEcAAIOAAgKLxwZEwCRAgAOAAgKLxwZEwCRAgAAAA==.Flappii:BAAANQADCgEIAQAAAA==.Flaster:BAAANQADCgYIBgAAAA==.Fluffykat:BAABNQAECoEWAAIIAAcKLxZvNgDrAQAIAAcKLxZvNgDrAQAAAA==.',
Fo='Fosho:BAACNQAFFIEXAAILAAcKvBryAACjAgALAAcKvBryAACjAgA1AAQKgR0AAgsACQowJAwMAG4DAAsACQowJAwMAG4DAAAA.',
Fr='Franch:BAAANQAECgYIEQAAAA==.Frank:BAAANQAECgEIAQABNQAECgYIDQAJAAAAAA==.Fraud:BAAANQAECgcIDgAAAA==.Freelvlsvnty:BAAANQADCgYIBwAAAA==.Froddy:BAAANQAECgYIDgAAAA==.Frostybox:BAAANQADCgYIBgAAAA==.Frylockk:BAABNQAECoEgAAQXAAkKByAsAQAsAwAXAAgKOyIsAQAsAwAMAAYKlByPbgC7AQARAAEKQB2xXwBOAAAAAA==.',
Fu='Furrykane:BAEBNQAECoEaAAQIAAgKNBcdMAAZAgAIAAgKHxYdMAAZAgAZAAEKyRd3KABLAAABAAEKHgjwVwA+AAAAAA==.Future:BAABNQAECoEeAAIKAAgKYBTdDQBPAgAKAAgKYBTdDQBPAgAAAA==.',
Ga='Gaara:BAAANQAECgYIDgAAAA==.Gamepunisher:BAABNQAECoEZAAMaAAgKRx0HCAAYAgAbAAgK3RRegwA8AgAaAAcKMh8HCAAYAgAAAA==.Gares:BAAANQAECgcIDQAAAA==.',
Gi='Giorbs:BAAANQADCgYIBgAAAA==.',
Go='Goatgeek:BAAANQABCgMIAwABNQAECgMIAwAJAAAAAA==.Goham:BAABNQAECoEcAAICAAkKKB/8EAAUAwACAAkKKB/8EAAUAwAAAA==.Goobe:BAAANQADCgQJBgABNQAECggIGwADAP8cAA==.Goontotem:BAAANQAECgEIAQABNQAECgUIBgAJAAAAAA==.Gorro:BAAANQADCgYIBgAAAA==.',
Gr='Grimkai:BAAANQABCgMIAwAAAA==.Grogon:BAAANQAECgUIBgAAAA==.Gromlo:BAABNQAECoEaAAIBAAgK2iFgCQD/AgABAAgK2iFgCQD/AgAAAA==.Grulog:BAAANQAECgMIBwAAAA==.',
Gu='Guldav:BAAANQADCgMIAwAAAA==.Gunny:BAABNQAECoEgAAMDAAgKdiGHGwD3AgADAAgKdiGHGwD3AgATAAIKKRLVVwB1AAAAAA==.',
['Gã']='Gã:BAAANQADCgUIBQAAAA==.',
['Gö']='Göld:BAAANQAECgUIBQAAAA==.',
Ha='Haeliman:BAAANQADCggICgAAAA==.Haileigh:BAAANQAECgMIAwAAAA==.Harleigh:BAAANQABCgMIAgAAAA==.Havöc:BAABNQAECoEeAAIcAAgKGhyYTABlAgAcAAgKGhyYTABlAgAAAA==.',
He='Herpenderper:BAAANQAECgMIAwAAAA==.',
Hi='Hikawa:BAABNQAECoEnAAIbAAgKayQpHQBPAwAbAAgKayQpHQBPAwAAAA==.Hippocratic:BAAANQAECgcIEAAAAA==.',
Ho='Honortheox:BAAANQADCgEIAQABNQAECgMIAwAJAAAAAA==.',
Hu='Huntemall:BAAANQAECgYICgAAAA==.',
Hy='Hysteriix:BAEBNQAECoEwAAIdAAkKxiQqAQCxAwAdAAkKxiQqAQCxAwAAAA==.',
Ic='Iceborn:BAAANQAECggIAQAAAA==.Iceshards:BAABNQAECoEZAAIaAAcKZBGGDACgAQAaAAcKZBGGDACgAQAAAA==.Icraptotems:BAAANQAECgEIAQAAAA==.',
Id='Idtrapthat:BAAANQAECgQIBQAAAA==.',
Il='Illidankior:BAABNQAECoEYAAIeAAkKLR0vBgDFAgAeAAkKLR0vBgDFAgAAAA==.Illirothas:BAAANQAECgUIBQABNQAECgkJHAADAJkUAA==.',
Im='Imen:BAAANQAECgcIDwAAAA==.Imsassy:BAAANQAECgQIBwAAAA==.',
In='Infect:BAAANQADCgIIAgABNQAECgYICAAJAAAAAA==.Infectedbøb:BAAANQAECgQICgAAAA==.Inmortuae:BAAANQAECgQIBAABNQAECgkJHAADAJkUAA==.Instågram:BAAANQAECgMIBQAAAA==.',
Io='Iornbane:BAAANQAECgUICAAAAA==.',
Ir='Irissela:BAAANQAECgQIBgAAAA==.',
Is='Ispitmagic:BAAANQAECgYIBwAAAA==.',
Iv='Ivalice:BAAANQAECgcIEwAAAA==.',
Iz='Izüal:BAAANQADCgYICQABNQAECgYIDgAJAAAAAA==.',
Ja='Jafbe:BAAANQAECgUICQAAAA==.Jaghatai:BAAANQAECgUIBwAAAA==.Jammer:BAAANQADCgYIBgAAAA==.',
Ji='Jimcarrey:BAAANQAECgIIAwABNQAECggIFwADADEHAA==.Jimmyc:BAAANQAECgQICAABNQAECggIFwADADEHAA==.Jimmysi:BAABNQAECoEXAAIDAAgKMQfGhACgAQADAAgKMQfGhACgAQAAAA==.',
Jo='Joemauma:BAAANQAECgUIDwAAAA==.',
Jp='Jpam:BAABNQAECoEcAAIbAAkKYhpTXwCTAgAbAAkKYhpTXwCTAgAAAA==.',
Ju='Jumbosize:BAACNQAFFIERAAIBAAYKExt0AQAfAgABAAYKExt0AQAfAgA1AAQKgSgAAgEACQqPJXsBALEDAAEACQqPJXsBALEDAAAA.Jupîter:BAAANQAECgEIAQABNQAECgEIAgAJAAAAAA==.Justamuslim:BAAANQADCggICAABNQAECgYICgAJAAAAAA==.',
Ka='Kaerlif:BAAANQAECgYIBgABNQAECgkJHAAfAEkeAA==.Kaiyley:BAAANQAECgcIDAAAAA==.Kalastrian:BAAANQAECgYIEAAAAA==.Karateshock:BAABNQAECoEXAAMCAAgK0AzbYACUAQACAAgK0AzbYACUAQALAAEKmgXOAAEwAAAAAA==.Kargo:BAAANQAECgYIBgAAAA==.Karlmarks:BAAANQABCggICgAAAA==.Kazuren:BAABNQAECoEXAAIVAAcKlgvuGAB8AQAVAAcKlgvuGAB8AQAAAA==.',
Ke='Keano:BAAANQAECgQICgAAAA==.Keeldemall:BAAANQAECgUIBQAAAA==.Kelia:BAAANQADCgMIAwABNQAECgkJHAADAJkUAA==.Kelinna:BAAANQAECgYICQAAAA==.',
Kh='Khmelnitsky:BAAANQADCggICAAAAA==.',
Ki='Kilron:BAAANQABCgMIAgAAAA==.Kirin:BAAANQAECgUIDQAAAA==.',
Kl='Klaye:BAAANQAECgYICQABNQAECggIGgALAIwZAA==.',
Kn='Knatknom:BAAANQAECgIIAgAAAA==.',
Ko='Kodabonk:BAABNQAECoEgAAIYAAgKzx3cBgCWAgAYAAgKzx3cBgCWAgAAAA==.Kodanorth:BAAANQAECgEJAQABNQAECggIIAAYAM8dAA==.Korthos:BAAANQAECgYIEQAAAA==.Kotara:BAAANQADCggIDwAAAA==.',
Kr='Kraur:BAABNQAECoEcAAIDAAkKmRSFOwByAgADAAkKmRSFOwByAgAAAA==.',
['Kì']='Kìngpin:BAABNQAECoEZAAIDAAcKGxrmUQArAgADAAcKGxrmUQArAgAAAA==.',
La='Laarry:BAAANQADCgUIBQABNQAECgkJGQAHAOoYAA==.Lammp:BAABNQAECoEbAAMCAAkK+BeOMgBSAgACAAcKUBuOMgBSAgALAAgK5RK/TAD0AQAAAA==.Lamppally:BAAANQADCgQIBAABNQAECgkJGwACAPgXAA==.Lampshade:BAAANQADCggICAABNQAECgkJGwACAPgXAA==.Laws:BAABNQAECoEgAAIFAAkKbBCvLADVAQAFAAkKbBCvLADVAQAAAA==.Lazydragon:BAABNQAECoEbAAMgAAcKSw4ICwBaAQAgAAcKIg0ICwBaAQAVAAYKcAgxHwAeAQAAAA==.',
Li='Liaeda:BAABNQAECoEaAAMhAAcKVw+jBgDQAQAhAAcKVw+jBgDQAQADAAMKvwl37QChAAAAAA==.Lianshi:BAAANQADCgUIBQAAAA==.Linainverse:BAAANQAECgMIBQAAAA==.Lingbane:BAAANQAECgEIAQABNQAECgkJIAAXAAcgAA==.Lixie:BAAANQADCggICAAAAA==.',
Lo='Lolo:BAAANQADCggICAABNQAFFAcIFwALALwaAA==.Loosie:BAAANQADCgEIAQAAAA==.Lost:BAAANQADCgUIBQABNQAECgkJIAAFAGwQAA==.Lovely:BAAANQAECgUIBwAAAA==.',
Lu='Luduhcris:BAAANQADCgYIEAAAAA==.Lugnuts:BAAANQAECgUIDAAAAA==.Lumiltiand:BAABNQAECoEcAAIEAAgKOiKmGwCkAgAEAAgKOiKmGwCkAgABNQAFFAIIAwAJAAAAAA==.',
Lw='Lwaxana:BAAANQAECgEIAQAAAA==.',
Ma='Makloy:BAAANQABCgYICAAAAA==.Malgoros:BAAANQAECgQIBAABNQAECggIGwAOALsWAA==.Malgrendin:BAABNQAECoEdAAIDAAgKESTsEAA4AwADAAgKESTsEAA4AwAAAA==.Malty:BAABNQAECoEaAAIcAAgK2Rx6SwBpAgAcAAgK2Rx6SwBpAgAAAA==.Malédictias:BAAANQAECgQIBgAAAA==.Manataurus:BAAANQADCgYIBgAAAA==.Manatreat:BAAANQAECgEIAQABNQAECgkJHAADAJkUAA==.Manuall:BAAANQAECgQICQAAAA==.Marbas:BAAANQAECgcIEgAAAA==.Maxidk:BAABNQAECoEgAAIWAAgKkCI0DwAPAwAWAAgKkCI0DwAPAwAAAA==.Maximage:BAAANQAECgQICAABNQAECggIIAAWAJAiAA==.Maximonk:BAAANQADCgQIBgABNQAECggIIAAWAJAiAA==.Mazëkeen:BAAANQADCggICAAAAA==.',
Me='Medîvh:BAAANQAECgUICgAAAA==.',
Mi='Midgemaisel:BAAANQAECgQIBgAAAA==.Mik:BAAANQABCgMIAgABNQADCgYJBgAJAAAAAA==.Mikhael:BAAANQADCgEIAQABNQADCgYJBgAJAAAAAA==.Mirado:BAABNQAECoEaAAIiAAgKxx7yAwC4AgAiAAgKxx7yAwC4AgAAAA==.Mirix:BAAANQADCgUIBQAAAA==.Mithridates:BAAANQAECgcIEgAAAA==.',
Mo='Molonlabe:BAAANQADCgUIBQAAAA==.Monix:BAABNQAECoEUAAMEAAgKLg5ZZQASAQAEAAUKtA9ZZQASAQAWAAQKwAwmfgC1AAAAAA==.Monkragga:BAAANQAECgYJDwAAAA==.Mooseleroy:BAAANQAECgUICwAAAA==.Mortarien:BAAANQAECggIEQAAAA==.Mozai:BAAANQADCgIIAgABNQAECggIGAAGAMMfAA==.',
Mu='Mugged:BAAANQAECgUIDQAAAA==.',
My='Myrtle:BAABNQAECoEXAAIjAAcKOBHyDACRAQAjAAcKOBHyDACRAQAAAA==.',
['Má']='Másóchist:BAABNQAECoEbAAMMAAkKjB3KLgCSAgAMAAgKZBzKLgCSAgARAAIKxSDxOwC9AAAAAA==.',
Ne='Necrophobic:BAAANQADCgQIBAAAAA==.Nevernude:BAAANQAECgQIBAABNQAECgkJHAACACgfAA==.',
Ni='Nice:BAAANQADCgYIDAAAAA==.Nikna:BAAANQADCgIIAgAAAA==.Niwatori:BAABNQAECoEVAAIIAAcKbB9TJQBsAgAIAAcKbB9TJQBsAgAAAA==.',
No='Noah:BAACNQAFFIEWAAMhAAcKUhgYAABkAgAhAAYK2RoYAABkAgATAAQKpQxgDAAhAQA1AAQKgSEAAyEACQrmJc4AAHwDACEACQrmJc4AAHwDABMAAgrJFK9UAIAAAAAA.Nol:BAAANQAECggICgABNQAFFAcIGAAkAA8hAA==.Nolarz:BAACNQAFFIEYAAIkAAcKDyFWAADJAgAkAAcKDyFWAADJAgA1AAQKgScAAiQACQpNJp0BALcDACQACQpNJp0BALcDAAAA.',
Nu='Nukthom:BAAANQADCgcICQAAAA==.',
Ny='Nyneaves:BAABNQAECoEcAAIOAAgKthwsEgCfAgAOAAgKthwsEgCfAgAAAA==.Nyst:BAABNQAECoEcAAIbAAgK8REUlAAVAgAbAAgK8REUlAAVAgAAAA==.',
Ob='Objekt:BAAANQAECgYICAAAAA==.',
Oh='Ohmenwah:BAAANQADCgUICQAAAA==.',
Oj='Ojplosion:BAABNQAECoEXAAMMAAkKXyClHwDTAgAMAAgKcCClHwDTAgARAAMKnh7QLgD7AAABNQADCgMIAwAJAAAAAA==.Ojpyroblast:BAAANQADCgMIAwAAAA==.',
Ol='Olga:BAAANQAECgEIBAAAAA==.Olma:BAAANQAECgYIDwABNQAFFAUIDwAPAGwcAA==.',
Om='Omghunter:BAAANQADCgYIBgAAAA==.',
On='Onisprite:BAAANQAECgMIBAAAAA==.',
Or='Orchaos:BAAANQADCgUIBgAAAA==.Ordhah:BAAANQAECgYIDgAAAA==.',
Os='Osanna:BAAANQADCggJFQAAAA==.',
Pa='Paladout:BAABNQAECoEgAAIGAAgKNR8HQACLAgAGAAgKNR8HQACLAgAAAA==.Palletjack:BAABNQAECoEgAAIWAAgKMSYwBwBvAwAWAAgKMSYwBwBvAwAAAA==.Palli:BAAANQADCgcIFAAAAA==.Paona:BAABNQAECoEaAAIIAAgKyQhfRQCKAQAIAAgKyQhfRQCKAQAAAA==.Papafloppa:BAAANQADCgIIAgAAAA==.Paulioo:BAAANQABCgIIAgAAAA==.',
Pe='Peraroll:BAAANQADCggICAAAAA==.',
Ph='Phenphen:BAABNQAECoEeAAMkAAkKVR6pCgADAwAkAAgKrR+pCgADAwAlAAUK2BLHKQBCAQAAAA==.Physicyan:BAAANQAECgYICwAAAA==.',
Pi='Pipez:BAAANQAECgYICQAAAA==.',
Pl='Planetdru:BAABNQAECoEgAAIIAAgKYx/eGgDCAgAIAAgKYx/eGgDCAgAAAA==.',
Po='Pogster:BAAANQADCgcIBwAAAA==.Pollyy:BAAANQAECgYIEQAAAA==.Popshampain:BAAANQAECgUIDgAAAA==.',
Ps='Psychonight:BAABNQAECoEeAAIQAAkKDRpPAgDUAgAQAAkKDRpPAgDUAgAAAA==.',
Pu='Punchydabear:BAAANQAECgUIAQAAAA==.',
['Pì']='Pìp:BAAANQADCgYJBgAAAA==.',
Ra='Raenlling:BAAANQAFFAIIAwAAAA==.Ratscum:BAEANQADCggIGAAAAA==.Rayssa:BAABNQAECoEgAAIQAAgKWyGTAQAOAwAQAAgKWyGTAQAOAwAAAA==.',
Re='Redeker:BAAANQAECgYJDgAAAA==.Redlossa:BAAANQADCgIIAgAAAA==.Renneth:BAAANQADCgUICgAAAA==.Rentahunter:BAAANQAECgEIAQAAAA==.Revax:BAAANQABCgUJBAABNQAECgkJHAADAJkUAA==.Reyna:BAAANQADCgQIBAABNQADCggICAAJAAAAAA==.',
Rh='Rholand:BAAANQAECgUIBgAAAA==.',
Ri='Ricopsu:BAABNQAECoEZAAMZAAgKSRwDBwCUAgAZAAgKSRwDBwCUAgAIAAEKygZulwAoAAAAAA==.',
Rn='Rngnar:BAAANQAECggICwAAAA==.',
Ro='Roakar:BAAANQADCgYICQAAAA==.Rocklii:BAAANQADCggIDwAAAA==.Roguewolf:BAABNQAECoEgAAIIAAgKgxCnNwDiAQAIAAgKgxCnNwDiAQAAAA==.Rokdomaa:BAAANQAECgcJCwAAAA==.Roki:BAABNQAECoEWAAIUAAcKKw4mIACOAQAUAAcKKw4mIACOAQAAAA==.Rolow:BAABNQAECoEeAAIbAAgKBhuJZACFAgAbAAgKBhuJZACFAgAAAA==.Roony:BAACNQAFFIEUAAIBAAcKPB14AACIAgABAAcKPB14AACIAgA1AAQKgSIAAgEACQrZIlAHACUDAAEACQrZIlAHACUDAAAA.Roper:BAAANQAECgIIBAAAAA==.Roritai:BAAANQABCgQIBAABNQAECgMIBwAJAAAAAA==.Rot:BAABNQAECoEeAAMEAAgK+CX7EwDkAgAEAAgK2SH7EwDkAgAFAAYK7iVqGgBuAgAAAA==.Royle:BAAANQAECgYICgAAAA==.',
Ru='Runes:BAABNQAECoEeAAIEAAgKNhiBMAARAgAEAAgKNhiBMAARAgAAAA==.Runnerjay:BAAANQAECgUIBQABNQAECgkJJAASAPwSAA==.Rush:BAAANQADCgIIAgABNQAECggIGAACAOQVAA==.Ruuf:BAABNQAECoEVAAMSAAcKgSEKDQCDAgASAAcKgSEKDQCDAgAGAAYKRgds3QDsAAAAAA==.',
Ry='Rygik:BAAANQAECgQIBAABNQAECgcIEQAJAAAAAA==.Rysxn:BAAANQAECgcIEQAAAA==.Ryuujins:BAACNQAFFIEPAAIPAAUKbByJBwDLAQAPAAUKbByJBwDLAQA1AAQKgR0AAw8ACQrzJEMOACsDAA8ACQqoJEMOACsDABAABQq/JC4HANEBAAAA.',
Sa='Sago:BAABNQAECoEYAAMcAAcKax8hYAAlAgAcAAcKGR0hYAAlAgAeAAUK+xq+FAB9AQAAAA==.Sandman:BAAANQAECgQICgAAAA==.',
Sc='Scumball:BAEANQADCgcIEgABNQADCggIGAAJAAAAAA==.Scyon:BAACNQAFFIEFAAIbAAIKFQ1tMwCeAAAbAAIKFQ1tMwCeAAA1AAQKgSwAAhsACQpyHpk8AO4CABsACQpyHpk8AO4CAAAA.',
Se='Selinie:BAAANQABCggIEAAAAA==.Senari:BAABNQAECoEZAAMGAAgK9RVhagADAgAGAAgKGBNhagADAgASAAYKxRiqIACDAQAAAA==.Senbane:BAAANQADCggICQAAAA==.Sencia:BAAANQAECgYICwAAAA==.',
Sh='Shadowblazer:BAABNQAECoEdAAIMAAgKxhtsMACMAgAMAAgKxhtsMACMAgAAAA==.Shalizar:BAAANQADCgUICAAAAA==.Shanda:BAABNQAECoEeAAMCAAkKlh7+FQDxAgACAAkKlh7+FQDxAgALAAMKLR2spQDzAAAAAA==.Shanto:BAABNQAECoEaAAILAAgKjBlvNABiAgALAAgKjBlvNABiAgAAAA==.Sheesh:BAAANQADCgcIDgAAAA==.Shesheshenn:BAABNQAECoEeAAMCAAkKyhmqLQBqAgACAAcKkCCqLQBqAgAKAAgKnwG6HwDnAAAAAA==.Shiftinmojo:BAAANQAECgEIAQAAAA==.Shoumei:BAABNQAECoEeAAMmAAgK7xXbGwADAgAmAAgK7xXbGwADAgAdAAYKAAr5IgAUAQAAAA==.Shugz:BAAANQADCgMIAwABNQAECgkJFwAlAGgdAA==.Shuken:BAAANQAECggIAQAAAA==.',
Si='Silfra:BAAANQAECgQIDAAAAA==.Sinfull:BAAANQADCggICAAAAA==.Sintharia:BAAANQADCgUJBQAAAA==.',
Sk='Skolaid:BAABNQAECoEeAAMHAAkKoSCADwAtAwAHAAkKoSCADwAtAwAGAAMKJR111wD4AAAAAA==.',
Sl='Slapparazzi:BAAANQADCgYIBQAAAA==.',
Sm='Smilingdev:BAAANQADCggIEAABNQAECgMIAwAJAAAAAA==.Smoopoodoop:BAAANQAECgUIBQAAAA==.',
Sn='Snagglepuss:BAAANQADCggICAAAAA==.Sneakysin:BAAANQADCgQIBAAAAA==.',
So='Soulmend:BAAANQAECgYIEQAAAA==.Soulsproxy:BAAANQABCgQIBQAAAA==.',
Sp='Spaceman:BAAANQAECgUIDAAAAA==.',
Sq='Sqûïsh:BAAANQADCggICAAAAA==.',
St='Stabbz:BAAANQADCgUIBQAAAA==.Stevetson:BAAANQAECgUIBwAAAA==.Stonatroll:BAAANQAECgEIAQABNQAECgkJHAADAJkUAA==.Stoops:BAAANQADCggIFgAAAA==.Stormdemon:BAAANQAECgYIDgAAAA==.Stormspellz:BAAANQAECgcJEwAAAA==.',
Su='Supay:BAAANQAECgQIBgAAAA==.',
Sw='Swinginsista:BAAANQAECgYIEwAAAA==.',
Ta='Taldath:BAAANQADCggJDwAAAA==.Talicso:BAABNQAECoEdAAIbAAkKGhpjXwCTAgAbAAkKGhpjXwCTAgAAAA==.Talos:BAAANQAECgcIDAABNQAECgcIDgAJAAAAAA==.Talzinn:BAAANQADCgYIBgABNQAECgcIDgAJAAAAAA==.Tardalian:BAAANQADCgYICAAAAA==.Tarkinal:BAABNQAECoEWAAICAAcKrCCAKgB6AgACAAcKrCCAKgB6AgAAAA==.Taurito:BAAANQAECgUICQAAAA==.',
Te='Teezee:BAABNQAECoEcAAIGAAgK7R1KOQClAgAGAAgK7R1KOQClAgAAAA==.Teitterdrud:BAAANQAECgcIEgAAAA==.Telira:BAAANQAECgYIDwAAAA==.Tenderhoof:BAABNQAECoEmAAMIAAkKDx8zDwAvAwAIAAkKDx8zDwAvAwABAAUKBxEMMQApAQAAAA==.',
Th='Thanatus:BAAANQADCgQJBAAAAA==.Thath:BAAANQADCggIJwAAAA==.Thavus:BAAANQADCgYIBgAAAA==.Thearatwo:BAAANQAECggIEQAAAA==.Thruumm:BAAANQAECgYIBgAAAA==.Thunderclapz:BAAANQAECgcJCAAAAA==.Thunsibution:BAAANQADCggICQABNQAECgkJGAAeAC0dAA==.',
Ti='Tickz:BAABNQAECoEcAAQXAAgKKyAoBgANAgAMAAYK+hy7TgAgAgAXAAYK2h0oBgANAgARAAIKwBW8SgCJAAAAAA==.Tinilia:BAAANQADCgQIBQAAAA==.Tirah:BAABNQAECoEeAAIIAAgKbwf8RgCAAQAIAAgKbwf8RgCAAQAAAA==.',
To='Toat:BAAANQADCgYIBgAAAA==.Toeran:BAABNQAECoEbAAISAAgKsR+rCwCdAgASAAgKsR+rCwCdAgAAAA==.Tokémon:BAAANQAECgcICgAAAA==.Toxren:BAABNQAECoEZAAMHAAkK6hj/IQC0AgAHAAkK6hj/IQC0AgAGAAIKEgVJNwFHAAAAAA==.',
Tr='Traelin:BAABNQAECoEeAAIHAAkKBiR5BACZAwAHAAkKBiR5BACZAwAAAA==.Tread:BAAANQAECgMIAwAAAA==.Trickee:BAAANQAECgYICwABNQAECgYIEQAJAAAAAA==.',
Ts='Tskaha:BAAANQAECgUICAAAAA==.',
Ty='Tyria:BAAANQAECgMIBQAAAA==.Tyruunas:BAAANQADCgMIAwAAAA==.',
Ug='Uggthok:BAAANQAECgQICAAAAA==.',
Ur='Urizarah:BAAANQADCgYIDAAAAA==.',
Ut='Uthrid:BAAANQADCgYIBgAAAA==.',
Va='Vanadis:BAAANQADCgcICwAAAA==.Vardamir:BAABNQAECoEcAAIHAAkKpBzPFgD3AgAHAAkKpBzPFgD3AgAAAA==.Vargath:BAAANQADCgMIAwAAAA==.Vashstampede:BAAANQAECgIIAgAAAA==.',
Ve='Vei:BAAANQADCgYIFQABNQADCgIIAgAJAAAAAA==.Velrik:BAAANQAECgQICgAAAA==.Venema:BAAANQADCgIIAgAAAA==.Venüs:BAAANQAECgEIAQAAAA==.Vercy:BAAANQADCgYIBwABNQADCggIGQAJAAAAAA==.Vezkin:BAABNQAECoEdAAIIAAkKrySeCAB2AwAIAAkKrySeCAB2AwAAAA==.',
Vi='Vintagejeans:BAAANQAECgYICwAAAA==.Virtus:BAABNQAECoEZAAIDAAgKGhXFQgBZAgADAAgKGhXFQgBZAgAAAA==.Vitrixz:BAAANQADCgUICAAAAA==.Vizaimor:BAAANQAECgYIDgAAAA==.',
Vo='Voi:BAAANQABCgIIAwABNQAECgEIAQAJAAAAAA==.Vostok:BAABNQAECoEbAAMcAAkKORX8VQBGAgAcAAkKORX8VQBGAgAeAAEKMRMfMgA5AAAAAA==.',
Vu='Vulcãnus:BAAANQAECgEIAgAAAA==.',
Wa='Wallyoak:BAAANQADCgEIAQAAAA==.Warcry:BAAANQAECgEJAQAAAA==.',
We='Wealthyscaly:BAAANQAECgMIBwAAAA==.Weedzzar:BAAANQADCgQIBAAAAA==.Werse:BAABNQAECoEgAAIPAAgK3x7/IQCtAgAPAAgK3x7/IQCtAgAAAA==.Wetloginyou:BAAANQAECgYIDgAAAA==.',
Wh='Whodi:BAAANQAECgYIEQAAAA==.',
Wi='Witt:BAAANQAECgYIDwAAAA==.',
Wo='Woementality:BAAANQADCgMIAwAAAA==.Wolful:BAABNQAECoEYAAICAAgK5BUXQgAMAgACAAgK5BUXQgAMAgAAAA==.',
Wr='Wrathoftitan:BAAANQADCgIIAgAAAA==.',
Wu='Wushoolay:BAAANQAECgQJCgAAAA==.',
Xn='Xnatem:BAABNQAECoEaAAIeAAgKWB3BBwCSAgAeAAgKWB3BBwCSAgAAAA==.',
Xo='Xoliver:BAAANQADCgYICQAAAA==.',
Ya='Yashiro:BAABNQAECoEaAAMHAAgK8wjBZACaAQAHAAgK8wjBZACaAQAGAAEKVgHTcQEbAAAAAA==.',
Ye='Yeraleth:BAABNQAECoEgAAIBAAgKLx2CEACUAgABAAgKLx2CEACUAgAAAA==.',
Yi='Yisiwang:BAAANQADCgcIBwABNQADCggIGQAJAAAAAA==.',
Yo='Yorick:BAAANQADCggIFQAAAA==.Yorkj:BAAANQAECgYIDwAAAA==.',
Za='Zalthorax:BAAANQAECgEIAQABNQAECgkJHAADAJkUAA==.Zatilion:BAABNQAECoEZAAIGAAgK0g4VgADEAQAGAAgK0g4VgADEAQAAAA==.Zavage:BAAANQADCgYICgABNQAECgYIEAAJAAAAAA==.Zayn:BAAANQAECgUICAAAAA==.',
Ze='Zenki:BAAANQADCgQJAgAAAA==.Zenkî:BAAANQADCgEIAQAAAA==.Zenrune:BAAANQAECgcICgAAAA==.Zephiday:BAAANQAECgMIAwAAAA==.',
Zi='Ziggashot:BAABNQAECoEbAAIDAAgK/xydLACpAgADAAgK/xydLACpAgAAAA==.Zinsus:BAAANQADCggJEwABNQAECgkJHAADAJkUAA==.',
Zo='Zongchi:BAAANQAECgEIAQAAAA==.',
Zu='Zurahahsha:BAABNQAECoEZAAIKAAcKVgb+FwCAAQAKAAcKVgb+FwCAAQAAAA==.',
['Ðr']='Ðrow:BAABNQAECoEXAAITAAgKCQ/ZJQDUAQATAAgKCQ/ZJQDUAQAAAA==.',
['Óx']='Óxy:BAAANQAECgUIEQAAAA==.',
['Ör']='Örc:BAAANQADCgUIBQABNQAECgYIDgAJAAAAAA==.',
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
