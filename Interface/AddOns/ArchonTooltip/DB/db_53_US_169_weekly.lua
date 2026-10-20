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

local lookup = {'DemonHunter-Vengeance','DemonHunter-Havoc','DemonHunter-Devourer','Warlock-Demonology','Mage-Arcane','Mage-Frost','Priest-Holy','Unknown-Unknown','Evoker-Preservation','Warrior-Arms','Paladin-Holy','DeathKnight-Blood','Druid-Balance','Rogue-Assassination','Shaman-Restoration','Warrior-Protection','Warrior-Fury','DeathKnight-Frost','DeathKnight-Unholy','Monk-Brewmaster','Warlock-Destruction','Shaman-Enhancement','Druid-Feral','Paladin-Retribution','Hunter-Marksmanship','Rogue-Subtlety','Hunter-BeastMastery','Shaman-Elemental','Priest-Shadow','Druid-Restoration','Priest-Discipline','Monk-Mistweaver','Monk-Windwalker','Druid-Guardian','Evoker-Devastation','Paladin-Protection','Mage-Fire','Warlock-Affliction','Hunter-Survival',}
local provider = {region='US',realm='Nordrassil',name='US',type='weekly',zone=53,date='2026-10-20',data={Aa='Aairidari:BAABNQAECn8lAAQBAAgKDAjEGwD+AAACAAgKVQbTVAA8AQABAAYK4QnEGwD+AAADAAEK1wFOOwAYAAAAAA==.',
Ab='Abruna:BAABNQAECn8WAAIEAAgK/BPXbwAQAgAEAAgK/BPXbwAQAgABNQAFFAYIEwAFAAkSAA==.Abruno:BAACNQAFFH8TAAIFAAYKCRJRHACbAQAFAAYKCRJRHACbAQA1AAQKfyoAAwUACgoWIgJBAAMDAAUACgolIQJBAAMDAAYAAQpaHQAAAAAAAAAA.Abruto:BAAANQAECgYIDgABNQAFFAYIEwAFAAkSAA==.',
Ae='Aeown:BAAANQAECgMIBgABNQAECgoKQgAHAGUUAA==.Aerdis:BAAANQADCggIFQABNQAECgYIDQAIAAAAAA==.',
Ah='Aharuka:BAAANQADCgEIAQAAAA==.',
Ak='Akukho:BAAANQADCgIIAgAAAA==.',
Al='Alandrìas:BAABNQAECn8pAAIBAAoKVwguCADsAAABAAoKVwguCADsAAAAAA==.Altera:BAABNQAECn8iAAIJAAgKwxD0IADKAQAJAAgKwxD0IADKAQAAAA==.',
Am='Amuri:BAAANQAECgUIBgAAAA==.',
An='Andelarenn:BAAANQABCgIIAgAAAA==.Andere:BAAANQAECgYICQAAAA==.Androo:BAABNQAECn8VAAIKAAcK4At4LwBPAQAKAAcK4At4LwBPAQABNQAFFAYIEwALAKkXAA==.Androonatorz:BAACNQAFFH8TAAILAAYKqRd6CgC1AQALAAYKqRd6CgC1AQA1AAQKfyYAAgsACgrqIZcbAAcDAAsACgrqIZcbAAcDAAAA.Anfernay:BAABNQAECn8jAAIKAAkKExK+egAoAgAKAAkKExK+egAoAgAAAA==.Antheion:BAAANQAECgEIAQABNQAECgYIIQAMAIwTAA==.Antiaxxis:BAAANQADCgEIAQAAAA==.',
Ap='Apawthetic:BAAANQAECggIEwABNQAFFAYIEgANAGUTAA==.',
Aq='Aquadab:BAAANQADCgQICAAAAA==.',
Ar='Arcanodare:BAAANQADCggICAAAAA==.Arkalis:BAAANQADCgYIBgAAAA==.Arveiturace:BAAANQAECgMICQAAAA==.',
As='Ashborrn:BAAANQADCgUIBQAAAA==.Ashtar:BAABNQAECn8oAAIKAAgKnxA2jwD2AQAKAAgKnxA2jwD2AQAAAA==.Asukajo:BAAANQADCgMIAwAAAA==.',
At='Attack:BAAANQAECgcICgAAAA==.',
Ax='Axhure:BAAANQABCgMIAgAAAA==.',
Ba='Babydoll:BAAANQAECgQICAAAAA==.Bajablast:BAAANQADCgcIDQAAAA==.Barma:BAAANQAECgYICQAAAA==.Barrin:BAAANQAECgcIDgAAAA==.',
Be='Bearlyseen:BAABNQAECn8eAAIOAAgKsB12AgBCAgAOAAgKsB12AgBCAgABNQAFFAUIEAAPACgMAA==.Beltirra:BAAANQAECgIIAgAAAA==.',
Bh='Bhangbros:BAAANQADCgcIBwAAAA==.',
Bi='Biggums:BAAANQAECgMIBAAAAA==.Bigmobility:BAABNQAECn8vAAIMAAoKiCAKCAB8AwAMAAoKiCAKCAB8AwAAAA==.Bigwill:BAABNQAECn86AAIGAAoKkCGCAACVAgAGAAoKkCGCAACVAgAAAA==.',
Bl='Blargy:BAABNQAECn84AAINAAoKiBbeBQDiAQANAAoKiBbeBQDiAQAAAA==.Bleach:BAAANQAECgYIDgAAAA==.Bluewaffles:BAAANQADCgEIAQABNQAECgIIAgAIAAAAAA==.',
Bo='Borealslam:BAAANQADCgQIBAAAAA==.Bouzol:BAAANQAECgYIBgAAAA==.',
Br='Brighterbonk:BAAANQAECgIIAgAAAA==.Brimara:BAAANQAECgUIDAAAAA==.Brothaagamor:BAAANQADCgIIAgAAAA==.',
Bu='Bucketojoy:BAABNQAECn8VAAIFAAgKPgK4qwB4AAAFAAgKPgK4qwB4AAAAAA==.',
['Bà']='Bàtman:BAAANQAECgQIBwAAAA==.',
Ca='Caliburne:BAABNQAECn81AAQKAAoKNB1CGACmAQAQAAUKhh+5FgC/AQAKAAoKmBxCGACmAQARAAMK6h4xGQAPAQAAAA==.Captamerica:BAAANQABCgQIBgAAAA==.Capz:BAACNQAFFH8YAAIKAAgKTxvCBACHAgAKAAgKTxvCBACHAgA1AAQKfyUAAgoACgqaJe8fADgDAAoACgqaJe8fADgDAAAA.',
Ce='Cedrin:BAAANQADCggIHwAAAA==.Ceez:BAAANQAECgYIDwAAAA==.Ceezinator:BAAANQADCgQIBAAAAA==.',
Ch='Chichujongar:BAABNQAECn8UAAQSAAcKwwucKwDvAAAMAAcKcwsFbwA5AQATAAYKwwUziwD3AAASAAYKmwWcKwDvAAABNQAFFAYIEgAUAAsSAA==.Chickenstwip:BAAANQADCgEIAgABNQAECgoKKgAFAAUaAA==.Chopperr:BAAANQAECgQIBAABNQAECgoKKgAFAAUaAA==.Chosenöne:BAAANQADCgEIAQAAAA==.Chèn:BAAANQAECgcIEgAAAA==.',
Ci='Cindrella:BAABNQAECn8uAAIGAAkKCSWXAADDAwAGAAkKCSWXAADDAwAAAA==.',
Cl='Clayre:BAACNQAFFH8PAAIVAAUKjBGMAACgAQAVAAUKjBGMAACgAQA1AAQKf0EAAhUACgpaI7gAALMDABUACgpaI7gAALMDAAAA.Clow:BAAANQAECgUIDgAAAA==.',
Co='Colossus:BAAANQAECgEIAgAAAA==.Coolcrush:BAAANQADCgMIBgABNQAECgoKJwAWAA8kAA==.Corven:BAACNQAFFH8SAAIEAAYKCBQcDwCLAQAEAAYKCBQcDwCLAQA1AAQKf0EAAwQACgqLIa4LAG8DAAQACgqLIa4LAG8DABUAAQpFBbiEACUAAAAA.',
Cr='Craziks:BAAANQADCgIIAgAAAA==.Critzwar:BAACNQAFFH8QAAIKAAYKfRXsEACtAQAKAAYKfRXsEACtAQA1AAQKfyAAAgoACgo2IWQxAPoCAAoACgo2IWQxAPoCAAAA.Crönus:BAAANQAECgIIAgAAAA==.',
Ct='Cthuluwu:BAAANQADCggICAAAAA==.',
Da='Daedyxes:BAABNQAECn8fAAIMAAgK/Q04JQDhAAAMAAgK/Q04JQDhAAAAAA==.Daní:BAAANQADCgUIBwABNQAECgEIAQAIAAAAAA==.Darfur:BAAANQAECggIBgAAAA==.Darkensi:BAAANQABCgYICQAAAA==.Dasherdeez:BAAANQADCgQJBwAAAA==.Daygath:BAAANQAECgEJAQAAAA==.',
De='Deadlyiris:BAABNQAECn8tAAIKAAoKfRtwOgDcAgAKAAoKfRtwOgDcAgABNQAECgoKGgAPAKsYAA==.Deadshot:BAAANQAECgQICwAAAA==.Deatharin:BAAANQADCgUIBgAAAA==.Deathjak:BAAANQAECgcICAABNQAECgoKJwAFADchAA==.Demonbulio:BAABNQAECn8UAAICAAgK9QZNSgB7AQACAAgK9QZNSgB7AQAAAA==.Demonisthicc:BAABNQAECn8zAAIXAAoK2RycBgABAwAXAAoK2RycBgABAwAAAA==.Demonskitten:BAAANQADCgUIBQABNQAECgoKMwAXANkcAA==.Demonslayeer:BAAANQADCggIDQAAAA==.Devi:BAAANQAECgUICwAAAA==.',
Di='Diaravynn:BAAANQADCgMIBQAAAA==.Dithehealer:BAABNQAECn8lAAIYAAkKeRMVkgAAAgAYAAkKeRMVkgAAAgAAAA==.Divain:BAAANQADCgQIBgAAAA==.',
Dk='Dkdi:BAAANQADCggIFwAAAA==.',
Do='Dozekar:BAAANQAECgEIAQAAAA==.',
Dr='Drenamai:BAAANQAECgUIDgAAAA==.Drexywexyuwu:BAAANQADCgcJBwAAAA==.',
Du='Duhmptruhk:BAABNQAECn8kAAIKAAoKkxbnCQAeAgAKAAoKkxbnCQAeAgAAAA==.Dunbroch:BAACNQAFFH8SAAIZAAYKZhq8BwDPAQAZAAYKZhq8BwDPAQA1AAQKfzAAAhkACgrjHasDANcBABkACgrjHasDANcBAAAA.Duskforge:BAAANQABCgIJAgAAAA==.',
Dw='Dwagen:BAAANQAECgQIBAAAAA==.',
['Dé']='Démonicblood:BAACNQAFFH8NAAISAAUKoxzGBgCSAQASAAUKoxzGBgCSAQA1AAQKfykAAhIACgqOGrcQAH8BABIACgqOGrcQAH8BAAAA.',
Eg='Eggplantgodx:BAABNQAECn8wAAMBAAoKeyNhAQAWAgACAAgKKRlqLwArAgABAAkKeyNhAQAWAgAAAA==.',
Ek='Ekhart:BAAANQAECgEIAQAAAA==.',
El='Elfajah:BAAANQADCgYICQAAAA==.Eliicia:BAACNQAFFH8RAAIOAAYKYg6BCACGAQAOAAYKYg6BCACGAQA1AAQKfygAAw4ACgpqHbQYALcCAA4ACgpqHbQYALcCABoACAqwDYAyACgBAAAA.',
Em='Emmy:BAAANQAECgQIDwAAAA==.Emofineshyt:BAAANQADCgcICgAAAA==.Emogothbabe:BAABNQAECn8qAAMFAAoKBRq9ZgCwAgAFAAoKBRq9ZgCwAgAGAAMK8w5RLACZAAAAAA==.Emowrecky:BAABNQAECn8eAAMEAAgKbx0GYwAwAgAEAAgKbx0GYwAwAgAVAAEKYwyYdwA2AAAAAA==.',
En='Endo:BAACNQAFFH8PAAMTAAYKKBmuCgBlAQATAAUKGh6uCgBlAQASAAMKhQ8tEQDMAAA1AAQKfzUAAxMACgp4I00SACUDABMACAq1JU0SACUDABIACApqHyItADYCAAAA.Endorush:BAABNQAECn8jAAICAAgKhx+bCgCiAQACAAgKhx+bCgCiAQABNQAFFAYIDwATACgZAA==.Endrigosa:BAAANQAECgUIBgAAAA==.Eneldenes:BAAANQAECgUICwAAAA==.Enjoyer:BAAANQAECgcIDgAAAA==.',
Er='Ereitherla:BAABNQAECn8dAAIbAAYK4AcpcwDGAAAbAAYK4AcpcwDGAAAAAA==.',
Es='Esmenet:BAAANQAECgYIEAAAAA==.Espressð:BAABNQAECn8cAAIHAAkKvB+LBQCnAgAHAAkKvB+LBQCnAgABNQAECgoKKgAFAAUaAA==.',
Ex='Excalibear:BAAANQAECgYIDwABNQAFFAUIEAAPACgMAA==.',
Ey='Eydis:BAAANQADCgcIDgAAAA==.Eyepisspeas:BAAANQABCgMIBAAAAA==.',
Fe='Feironor:BAAANQAECgMIAwAAAA==.Fenrys:BAAANQAECgMIAwAAAA==.',
Fi='Fikareous:BAAANQADCggIDQABNQAECgUIBQAIAAAAAA==.',
Fl='Flayre:BAABNQAECn8oAAMPAAkK3RtQRQBMAgAPAAgK3BtQRQBMAgAcAAcKMBcNaADoAQAAAA==.Fleredil:BAABNQAECn8sAAMdAAoK0h4vBgCXAQAdAAoK0h4vBgCXAQAHAAEKgQXG/gAuAAAAAA==.Flingernle:BAABNQAECn8fAAIcAAkKPiFyJAD0AgAcAAkKPiFyJAD0AgAAAA==.',
Fo='Forepray:BAACNQAFFH8PAAIdAAQKExGNCwAzAQAdAAQKExGNCwAzAQA1AAQKfzYAAh0ACgrXHqUJAEUDAB0ACgrXHqUJAEUDAAAA.Forger:BAABNQAECn8nAAMQAAkKDAwtGwCGAQAQAAkKDAwtGwCGAQAKAAIKQQjVOQFhAAAAAA==.Forsakey:BAAANQADCggIFAABNQAFFAYIDQAeAIQYAA==.',
Fr='Fraun:BAAANQADCggJEQAAAA==.Freshdk:BAAANQAECgQIBAAAAA==.',
Fu='Fullyprotpal:BAAANQAECgEIAQAAAA==.Furioustotem:BAABNQAECn8eAAIcAAYKXBkVLwACAQAcAAYKXBkVLwACAQAAAA==.Future:BAAANQADCgUIBgABNQAECgkJLAAFAMQjAA==.',
Fy='Fycat:BAAANQAECgIIAgABNQAFFAMICAAEAKEeAA==.',
Ga='Galten:BAAANQADCgUIBQAAAA==.Gantz:BAAANQADCgIJAgAAAA==.',
Ge='Geekbarr:BAAANQADCgUIBQABNQAECgoKKgAFAAUaAA==.',
Gh='Ghettox:BAAANQADCgYICAAAAA==.Ghostw:BAAANQAECgUIDwAAAA==.',
Gi='Giovanni:BAAANQAECggICAAAAA==.Gizik:BAAANQADCgcIDQABNQAFFAcIFwAdABESAA==.',
Gn='Gnasher:BAAANQABCgQIBAAAAA==.',
Go='Golgotterath:BAACNQAFFH8QAAIPAAUKKAwODwBeAQAPAAUKKAwODwBeAQA1AAQKfzUAAw8ACgpVGyZIAEECAA8ACgpVGyZIAEECABwAAQqNB/I6ATAAAAAA.Gorm:BAABNQAECn8gAAIFAAoKPhmwVgDTAgAFAAoKPhmwVgDTAgABNQAECgQIBQAIAAAAAA==.',
Gr='Grippyshocks:BAAANQAECgIIAQABNQAECgkJIAACAGchAA==.',
Ha='Halbruck:BAAANQAECgcIEQAAAA==.Haldane:BAABNQAECn8vAAIYAAkKFgl7OgBTAQAYAAkKFgl7OgBTAQABNQAECgoKGgAPAKsYAA==.Harrydottur:BAAANQAECgcIDQABNQAFFAUICQAEAIgYAA==.Havochunter:BAAANQAECgUIBgAAAA==.',
He='Heidegger:BAAANQADCgYICgAAAA==.Helinndealin:BAACNQAFFH8PAAIfAAUKXiCtAADoAQAfAAUKXiCtAADoAQA1AAQKfywAAx8ACgrEJFQBAEcDAB8ACQryJFQBAEcDAAcACAotIsZJAEgCAAAA.Hellin:BAAANQADCgMIAQAAAA==.Heolstor:BAABNQAECn8rAAIMAAoKMhpQBgDaAQAMAAoKMhpQBgDaAQAAAA==.Hephsdh:BAAANQAECgYIDwAAAA==.Heraois:BAABNQAECn8bAAIZAAkK9gisNgCZAQAZAAkK9gisNgCZAQAAAA==.',
Hg='Hgshake:BAAANQADCgYIBgAAAA==.',
Ho='Holytës:BAAANQADCggIFQAAAA==.Holywráth:BAAANQADCgUIDwAAAA==.',
Hu='Hunterdh:BAABNQAECn8dAAIbAAgKmAXBQQAyAQAbAAgKmAXBQQAyAQAAAA==.',
Hy='Hynixx:BAABNQAECn8jAAMRAAkKDRodCQBKAgARAAgKJRodCQBKAgAKAAYKGxRORwASAQABNQAFFAQIDwAdABMRAA==.',
Il='Illidope:BAABNQAECn8gAAQCAAkKZyHcFQDuAgACAAkKQSHcFQDuAgADAAgK+xwZIwAxAgABAAEKAACILgBGAAAAAA==.',
In='Infinitevoid:BAAANQADCggIFQAAAA==.Innervatez:BAABNQAFFH8LAAIeAAUKJCMuBADuAQAeAAUKJCMuBADuAQAAAA==.Inteaus:BAAANQADCggIGgAAAA==.',
Io='Ionúin:BAAANQADCgQJBAAAAA==.',
Iv='Ivÿ:BAAANQADCgMIBQAAAA==.',
Ja='Jabkhan:BAAANQAECgUIBQAAAA==.Jaekir:BAABNQAECn8iAAIGAAgKERWRCwAHAgAGAAgKERWRCwAHAgAAAA==.Jakfrost:BAABNQAECn8nAAMFAAoKNyE7FgC5AQAFAAkKHiE7FgC5AQAGAAMKKiLkGgAcAQAAAA==.Jakie:BAAANQADCgYICgABNQAECggIFwAKAN8aAA==.Jarten:BAACNQAFFH8PAAISAAUKXxlRCABvAQASAAUKXxlRCABvAQA1AAQKfzUAAhIACgqMH9QQAAkDABIACgqMH9QQAAkDAAAA.Jayaah:BAAANQAECgIIAgAAAA==.Jaylebate:BAAANQAECgQICgAAAA==.',
Je='Jerrenn:BAAANQAECgQIBAAAAA==.Jesseatamer:BAACNQAFFH8PAAIbAAUKbCDlAwAhAQAbAAUKbCDlAwAhAQA1AAQKfzMAAhsACgq2JB0IAJwDABsACgq2JB0IAJwDAAAA.',
Ji='Jitsuru:BAAANQADCgUIBQAAAA==.',
Jo='Jox:BAAANQABCgUIBQAAAA==.Joxor:BAAANQABCgUIBQAAAA==.',
Js='Jstdeath:BAAANQADCgEIAQABNQAECgoKMAAKAAsUAA==.Jstrawr:BAABNQAECn8wAAIKAAoKCxRvYgBnAgAKAAoKCxRvYgBnAgAAAA==.Jsttotem:BAAANQAECgUIBQABNQAECgoKMAAKAAsUAA==.',
Ka='Kalmek:BAAANQAECggIDgAAAA==.Kaln:BAAANQAECgIIBgABNQAECgQIBQAIAAAAAA==.Karen:BAAANQAECgUIDgAAAA==.Kasalu:BAAANQABCgQIBAAAAA==.Kasanzzar:BAAANQAECgQIBAAAAA==.Kastia:BAAANQAECgQIBgAAAA==.Katrynwel:BAAANQAECgQIBAAAAA==.Katsumi:BAAANQAECgEIAgAAAA==.',
Ke='Keliki:BAABNQAECn8oAAMPAAkKvB0rAwDtAgAPAAkKvB0rAwDtAgAcAAgKzhigQQBvAgAAAA==.Kellenah:BAAANQADCgYIEAAAAA==.Kettama:BAAANQADCggIEAABNQAECgoKKgAFAAUaAA==.',
Kh='Khold:BAABNQAECn8hAAMSAAkKkhk+KgBJAgASAAkKkhk+KgBJAgAMAAQKBw5mMwCpAAAAAA==.Khrogann:BAAANQAECggIEQAAAA==.',
Ki='Kijana:BAAANQADCggICAAAAA==.Killalltoday:BAABNQAECn8kAAIPAAgK1hF9aQDQAQAPAAgK1hF9aQDQAQAAAA==.Killersmile:BAAANQADCgQIBAAAAA==.Kirkk:BAAANQAECgEIAQAAAA==.',
Kl='Klaminus:BAAANQADCgQIBAABNQAECgIIAgAIAAAAAA==.',
Kn='Knixx:BAACNQAFFH8TAAIHAAYK/hEIEACUAQAHAAYK/hEIEACUAQA1AAQKf0YAAwcACgqgI+sAAOQDAAcACgqgI+sAAOQDAB8ABgrzEYsPADIBAAAA.Knuppelus:BAAANQADCgYIDAAAAA==.',
Ko='Kobyashimaru:BAAANQADCgUIBQAAAA==.Koshi:BAAANQADCgMIAwAAAA==.Kotastrophe:BAAANQAECgMIAwABNQAECgoKJAAKAJMWAA==.Koveras:BAAANQADCgYIBwAAAA==.Koyaanis:BAAANQADCggIDgAAAA==.Koyya:BAABNQAECn8iAAMWAAoK4Qw3FAAlAgAWAAkK5Ao3FAAlAgAPAAkKkBDKKgA3AQAAAA==.',
Kr='Krathos:BAAANQAECgMIBAAAAA==.Krenmonk:BAAANQAECgEIAQAAAA==.Krennic:BAAANQADCgcIBwAAAA==.Krunchee:BAAANQAECgMIBAAAAA==.',
Ku='Kufoo:BAABNQAECn8pAAIRAAoKcyGWAgBOAwARAAoKcyGWAgBOAwAAAA==.Kurao:BAAANQAECgMIBQAAAA==.Kurukai:BAAANQADCgMIAwAAAA==.',
Ky='Kyrian:BAACNQAFFH8fAAMaAAcKriBiAQBaAgAaAAcKriBiAQBaAgAOAAMKvREHEADrAAA1AAQKfywAAxoACgoLIygFADgDABoACgoLIygFADgDAA4AAwpZHHlvAPMAAAAA.',
La='Lagøless:BAABNQAECn8gAAIbAAoKpB8hEwBTAwAbAAoKpB8hEwBTAwAAAA==.',
Le='Leo:BAAANQAECgEIAQAAAA==.',
Li='Liatris:BAAANQAECgUIBQAAAA==.Likestoflash:BAEANQADCgYIBgABNQAECgoKNgAbAAEdAA==.Lissaris:BAAANQADCgEIAgAAAA==.',
Lo='Lohal:BAABNQAECn8oAAIEAAkKqxf4CwDuAQAEAAkKqxf4CwDuAQAAAA==.Lohmi:BAAANQAECgUIEAAAAA==.Lormn:BAAANQADCgEIAQAAAA==.',
Lu='Luania:BAAANQAECgQIBgAAAA==.',
Ly='Lyna:BAAANQADCggJDAAAAA==.Lyravega:BAAANQADCggICAAAAA==.Lyshkä:BAABNQAECn8xAAIgAAoKaBpAEAB7AgAgAAoKaBpAEAB7AgAAAA==.Lyzzardkng:BAABNQAECn8gAAIYAAkKEQi2OwBQAQAYAAkKEQi2OwBQAQAAAA==.',
['Lý']='Lýra:BAAANQAECgQIBwAAAA==.',
Ma='Maango:BAAANQAECggIEAAAAA==.Maemu:BAAANQABCgUIBwAAAA==.Magerthat:BAAANQADCgQIBgAAAA==.Magicaltickl:BAABNQAECn8VAAIFAAgKvgqT4ADHAQAFAAgKvgqT4ADHAQAAAA==.Magiki:BAAANQADCgcICwAAAA==.Makyaihua:BAAANQABCggIGgAAAA==.Malkala:BAAANQADCgMIAwAAAA==.Malonormu:BAAANQABCgcIBgAAAA==.Mamadeezy:BAAANQADCgYJCwAAAA==.Mando:BAAANQAECgIIBAABNQAECgYIHQAhAGoaAA==.Manical:BAAANQAECgMICAAAAA==.Marcel:BAAANQADCgYIEQABNQAECgIIAgAIAAAAAA==.Martinikiss:BAAANQAECgcIDAAAAA==.Mashiach:BAACNQAFFH8LAAIHAAUKEB2gDADBAQAHAAUKEB2gDADBAQA1AAQKfyYAAwcACgpTIdgPAEcDAAcACgpTIdgPAEcDAB0AAQoAALx4ADYAAAAA.Matthyjsz:BAAANQADCgIIAgAAAA==.',
Me='Megumin:BAAANQAECgQIBwABNQAECgoKMwAYAFIjAA==.Melikefire:BAABNQAECn8bAAIFAAkK1hZXmgBMAgAFAAkK1hZXmgBMAgAAAA==.Melodious:BAAANQAECgEIAQAAAA==.Memecompdall:BAAANQAECgIIAgAAAA==.Merek:BAABNQAECn8gAAIUAAgKyB8JBwDSAgAUAAgKyB8JBwDSAgAAAA==.Mettix:BAAANQADCgIIAgAAAA==.',
Mi='Mirigosa:BAAANQAECgEIAQABNQAECgkJLgAGAAklAA==.Mistybdk:BAABNQAECn8fAAIMAAoKcRJXCgCcAQAMAAoKcRJXCgCcAQABNQAFFAcIFgAiAOITAA==.Mistyd:BAACNQAFFH8WAAIiAAcK4hOIAABGAgAiAAcK4hOIAABGAgA1AAQKf0AAAiIACgo8JIkBAMwDACIACgo8JIkBAMwDAAAA.',
Mo='Mogfooyen:BAAANQABCgUICAAAAA==.Moonbeam:BAAANQAECgUIBgAAAA==.Morgause:BAABNQAECn8VAAIEAAYKGAbGTQDqAAAEAAYKGAbGTQDqAAAAAA==.Morllan:BAABNQAECn8eAAIEAAoKdQ0qggDgAQAEAAoKdQ0qggDgAQAAAA==.',
Mu='Muirdin:BAAANQADCgEIAQAAAA==.',
My='Mykinlive:BAAANQADCgIIAgAAAA==.',
['Må']='Mångix:BAAANQAECgQIBAAAAA==.',
['Mé']='Mélusine:BAABNQAECn8ZAAMKAAkKURJ5igABAgAKAAkKpw95igABAgARAAQKrRB2HQDYAAAAAA==.',
Na='Naanomage:BAAANQAECgMIAwAAAA==.Nagakabouros:BAAANQABCgIIAgAAAA==.Naija:BAAANQADCgIIAgAAAA==.Narcotx:BAAANQADCgIIAgAAAA==.',
Ne='Necrotoxin:BAAANQADCgYIBgAAAA==.',
Ni='Nightmaratic:BAAANQADCgYIBgAAAA==.Nightsdeath:BAAANQAECgEIAQAAAA==.Nightsever:BAABNQAECn8nAAIDAAkKwSJIBwBeAwADAAkKwSJIBwBeAwAAAA==.Nirath:BAABNQAECn8kAAIjAAgK6wSeIABOAQAjAAgK6wSeIABOAQAAAA==.',
No='Noiire:BAAANQAECggICgABNQAFFAYIEQAOAGIOAA==.',
Od='Odysse:BAAANQADCgYICQAAAA==.Odyssé:BAABNQAECn8dAAIbAAkKTR7UIQAQAwAbAAkKTR7UIQAQAwAAAA==.',
Oi='Oio:BAAANQAECgcIAQAAAA==.',
Ok='Okami:BAABNQAECn8WAAIhAAYKFB7eCACAAQAhAAYKFB7eCACAAQAAAA==.',
On='Onehotelf:BAAANQAECgQIBAAAAA==.',
Oo='Ooyagoddess:BAAANQAECgEIAQAAAA==.',
Or='Orienn:BAAANQADCgYIBgAAAA==.',
Pa='Pacamonk:BAABNQAECn8vAAIhAAoKYRwsDQAIAwAhAAoKYRwsDQAIAwAAAA==.Palenar:BAAANQADCgQIBAAAAA==.Papatiny:BAAANQAECgYIDwAAAA==.Papábear:BAAANQADCgQIBAAAAA==.Pawsa:BAAANQAECgUICwABNQAECgoKKgAFAAUaAA==.Pawthetic:BAACNQAFFH8SAAQNAAYKZRNdEgBEAQANAAQKlBhdEgBEAQAXAAEK2AMVAgBSAAAeAAEKVw6PFABNAAA1AAQKfzYAAw0ACgrCHFcfANACAA0ACgrCHFcfANACAB4ACAq4I5sFAAECAAAA.',
Pe='Peelforheals:BAACNQAFFH8FAAIdAAMKLAcGFACMAAAdAAMKLAcGFACMAAA1AAQKfzEAAx0ACgqkHpwOAAYDAB0ACgqkHpwOAAYDAB8ABAq4C3sXALoAAAAA.Penguindemic:BAABNQAECn8hAAMEAAkKvySaBgCaAwAEAAkKvySaBgCaAwAVAAEKoCISagBNAAAAAA==.Pep:BAAANQAECgcIEQAAAA==.Pepperoni:BAAANQADCggIDQAAAA==.Perdator:BAAANQAECgQICAAAAA==.Petruccius:BAACNQAFFH8SAAINAAQK6gpKCADYAAANAAQK6gpKCADYAAA1AAQKf0oAAg0ACgqbH1EMAGgDAA0ACgqbH1EMAGgDAAAA.Pewpewlepew:BAAANQAECgQICQAAAA==.',
Ph='Phaeku:BAAANQADCgMIAwAAAA==.',
Pi='Picklebreath:BAAANQADCgUICgAAAA==.Pinksparklez:BAAANQADCgUICAABNQAECgEIAQAIAAAAAA==.',
Pl='Plague:BAAANQAECgMIAwAAAA==.',
Po='Poptartsz:BAAANQAECgQICQAAAA==.Potatolockx:BAAANQAECgQIAwAAAA==.',
Pr='Prayre:BAAANQAECgMIAwAAAA==.Precht:BAAANQAECgIIAgAAAA==.Prikarea:BAAANQAECgUIBQAAAA==.Prospa:BAAANQAECgEIAQABNQAECgoKKgAFAAUaAA==.Prumper:BAABNQAECn8YAAIFAAgKhBI1xQD6AQAFAAgKhBI1xQD6AQAAAA==.Príest:BAAANQAECggICAAAAA==.',
Pu='Purah:BAAANQADCgEIAgAAAA==.',
['Pä']='Päncake:BAAANQAECgEIAQAAAA==.',
Qu='Quesoblanco:BAABNQAECn8bAAMkAAgKcxAxOwAXAQAYAAgKeQhB1QBxAQAkAAUKKhkxOwAXAQAAAA==.',
Qy='Qybxboogietk:BAABNQAECn8dAAICAAkKJhSDMQAdAgACAAkKJhSDMQAdAgAAAA==.',
Ra='Rabid:BAAANQAECgQICwAAAA==.Raeliana:BAAANQADCgQIBAAAAA==.Raghallov:BAAANQAECgMIBgAAAA==.Rampa:BAAANQADCgYIEQABNQAECgoKKgAFAAUaAA==.',
Re='Reaperan:BAAANQAECgEIAQAAAA==.Regena:BAABNQAECn9CAAMHAAoKZRToDAAaAgAHAAoKZRToDAAaAgAdAAMKOQKLagBYAAAAAA==.Rekriss:BAAANQADCgYIBgAAAA==.Remorse:BAACNQAFFH8SAAIQAAYKZRKNAgBrAQAQAAYKZRKNAgBrAQA1AAQKf0MAAhAACgpeIWYGAAADABAACgpeIWYGAAADAAAA.Rendwick:BAAANQADCgYICQAAAA==.Required:BAAANQAECgcICgABNQAFFAYIEQACANAgAA==.',
Ri='Rikahoe:BAAANQAECgUIBQABNQAECgUIBQAIAAAAAA==.Riker:BAAANQADCgQIBAABNQAECgEIAQAIAAAAAA==.Rim:BAABNQAECn8nAAIPAAkKlRodNACPAgAPAAkKlRodNACPAgAAAA==.',
Ro='Ronfar:BAACNQAFFH8QAAIWAAUKSBh4AgCoAQAWAAUKSBh4AgCoAQA1AAQKf0oAAhYACgqDH8oAALoCABYACgqDH8oAALoCAAAA.Rootx:BAAANQAECgMIAwABNQAFFAcIJQANADQjAA==.',
Ru='Rukidingme:BAAANQADCgEIAQAAAA==.Rustyglass:BAAANQABCgYIBAAAAA==.Ruttisðir:BAAANQAECgIIAwAAAA==.',
Ry='Ryhorn:BAAANQADCggIDgAAAA==.Ryno:BAAANQADCgUIBwAAAA==.Ryujin:BAABNQAECn8XAAIYAAkKqAkvyQCJAQAYAAkKqAkvyQCJAQAAAA==.Ryù:BAAANQAECgMIBQAAAA==.',
Sa='Salo:BAAANQADCgMIBgAAAA==.Salòme:BAAANQADCgQIBgABNQAECgkJGwAbAGoJAA==.Sanazenet:BAAANQADCggJDAAAAA==.Saphiriel:BAAANQAECgMIBQAAAA==.Saviorself:BAAANQADCgMIAwABNQAFFAYIEgANAGUTAA==.',
Sc='Scarscar:BAAANQAECgcIDAAAAA==.Schwinn:BAAANQADCgQIBAAAAA==.',
Se='Segarth:BAABNQAECn8WAAMcAAkKXhVPKgAUAQAcAAkKXhVPKgAUAQAPAAQKkRB8xADfAAAAAA==.Selen:BAAANQAECgcIEQAAAA==.Semballin:BAAANQABCgMJAwAAAA==.Seråphiel:BAAANQAECgEIAQAAAA==.Seswatha:BAAANQAECgUIBQABNQAFFAUIEAAPACgMAA==.',
Sh='Shamandroo:BAABNQAECn8YAAIPAAkK0Bo7JwDHAgAPAAkK0Bo7JwDHAgABNQAFFAYIEwALAKkXAA==.Shamdi:BAAANQADCgYIBgAAAA==.Shanghaied:BAAANQADCgcIDAAAAA==.Shawtyy:BAAANQADCgMIAwAAAA==.Shmongus:BAAANQADCgIIAgABNQAECgcIDgAIAAAAAA==.Shortandold:BAAANQAECggIDwAAAA==.Shådowfire:BAAANQAECgEIAQAAAA==.Shìft:BAABNQAECn8mAAIeAAgKzx2ZEwCvAgAeAAgKzx2ZEwCvAgAAAA==.',
Si='Sightofhand:BAAANQADCgQIBAAAAA==.Sintram:BAAANQAECgMIAwAAAA==.',
Sl='Slighted:BAAANQAECgMIBgABNQAECgcIEgAIAAAAAA==.Slimydruid:BAAANQAECgQIBgAAAA==.Slow:BAABNQAECn8sAAIFAAkKxCPCHABkAwAFAAkKxCPCHABkAwAAAA==.',
Sm='Smokinontech:BAAANQADCgQIBAABNQAECgoKKgAFAAUaAA==.Smokze:BAAANQADCggJCAAAAA==.',
So='Sockoh:BAABNQAECn8XAAQFAAgK5A9TvwAGAgAFAAgKtw5TvwAGAgAGAAIK2xXrLwCBAAAlAAEKmwb2DQAzAAAAAA==.Sonicberger:BAAANQAECgUIBAABNQAECgkJIgAMAJsbAA==.Sonicbergger:BAAANQADCgQIBAABNQAECgkJIgAMAJsbAA==.Sonicoberg:BAAANQAECgQIBwABNQAECgkJIgAMAJsbAA==.Soniko:BAAANQAECgcIEgAAAA==.Sonícberger:BAABNQAECn8iAAMMAAkKmxvoDACAAQAMAAkKmxvoDACAAQATAAIKXhsJvAB0AAAAAA==.Soulcaliber:BAAANQADCgQIBwAAAA==.Sovious:BAAANQADCgUIBQAAAA==.',
Sq='Squizzy:BAAANQAECgIIAgAAAA==.',
St='Stain:BAAANQAECgQJCAAAAA==.Stealth:BAAANQAECgQIBAABNQAECggIJAAmACUbAA==.Stinkfist:BAAANQADCgcIFgAAAA==.Stonehenge:BAABNQAECn8aAAIPAAoKqxhwHwBsAQAPAAoKqxhwHwBsAQAAAA==.Stonepalm:BAAANQADCgcIIgAAAA==.Stratan:BAAANQAECgIIAgAAAA==.Strawk:BAABNQAECn8dAAIcAAcKBQ5APQDSAAAcAAcKBQ5APQDSAAAAAA==.Stürm:BAAANQAECgMIAwABNQAECgoKMQAgAGgaAA==.',
Su='Subbzero:BAAANQADCgEIAQAAAA==.Suffer:BAAANQADCggICQABNQAECgkJLAAFAMQjAA==.Sunlight:BAAANQAECgMIAwAAAA==.Supercat:BAAANQAECgEIAQAAAA==.Surf:BAAANQAECgUIDAAAAA==.',
Sw='Swankydranky:BAACNQAFFH8SAAQUAAYKCxLuBQAQAQAUAAUKKQbuBQAQAQAhAAQKAgomCwAFAQAgAAIKVABXBwArAAA1AAQKfywABBQACgo7FW0SAL4BABQACAoQE20SAL4BACEACgpkEmo0AHIBACAAAgphBMZIAEYAAAAA.Swankypally:BAAANQAECgcICgABNQAFFAYIEgAUAAsSAA==.',
Sy='Syesc:BAAANQABCgQJBAAAAA==.Sylandris:BAAANQADCgIIAgAAAA==.Sympathy:BAAANQAECgYIBgAAAA==.',
['Sá']='Sásukeuchiha:BAAANQADCgYIEwABNQAECgkJGwAbAGoJAA==.',
Ta='Tabbz:BAABNQAECn8lAAIcAAoKJhh5MQC1AgAcAAoKJhh5MQC1AgAAAA==.Tallael:BAABNQAECn8vAAIWAAoK9BASAgAvAgAWAAoK9BASAgAvAgAAAA==.Tallyhochick:BAABNQAECn8nAAIbAAkKgQ37fQARAgAbAAkKgQ37fQARAgAAAA==.Taman:BAABNQAECn8bAAIPAAgKNx1lQABeAgAPAAgKNx1lQABeAgAAAA==.Taylerswift:BAAANQAECgEJAQAAAA==.',
Th='Thebestname:BAABNQAECn8YAAIiAAgKEAalMQARAQAiAAgKEAalMQARAQAAAA==.Thebigonion:BAAANQADCggIGgAAAA==.Theexile:BAABNQAECn8oAAMOAAoKghduKwA7AgAOAAkKixZuKwA7AgAaAAcKcBe8IQC+AQAAAA==.Theigh:BAAANQAECgEIAQAAAA==.Thonard:BAAANQAECgYIDwABNQAECgoKUAASAF0kAA==.',
Ti='Tinydeath:BAABNQAECn8fAAIMAAgKwhUsSgDPAQAMAAgKwhUsSgDPAQABNQAECgkJJAAbADsaAA==.Tinyfu:BAAANQADCgQIBAAAAA==.Tinytamer:BAABNQAECn8kAAMbAAkKOxrVIQCQAQAbAAkKsBnVIQCQAQAnAAMKRRIbDgDMAAAAAA==.',
Tm='Tmakrist:BAAANQAECgEIBAAAAA==.',
To='Toko:BAACNQAFFH8MAAIbAAUKZBk5CQC1AQAbAAUKZBk5CQC1AQA1AAQKfy0AAhsACgp0I+AdACADABsACgp0I+AdACADAAAA.Tomblord:BAABNQAECn8XAAMSAAcK6gooUgBoAQASAAcKwgooUgBoAQAMAAYKuAUshQDoAAAAAA==.',
Tr='Trailblazah:BAAANQAECgUICgAAAA==.Treeheals:BAAANQADCggICAAAAA==.Truthes:BAAANQADCgYIBwABNQAECggIJAAmACUbAA==.Truths:BAAANQADCgIJAgABNQAECggIJAAmACUbAA==.Truthsx:BAABNQAECn8kAAMmAAgKJRv6AwCpAgAmAAgKJRv6AwCpAgAEAAUKZw494gAEAQAAAA==.Truthy:BAAANQADCgYICAABNQAECggIJAAmACUbAA==.Truthz:BAAANQADCgYJBgABNQAECggIJAAmACUbAA==.',
Ts='Tsukúne:BAAANQADCgQIBAAAAA==.',
Ty='Tyg:BAAANQADCggIEQAAAA==.Tylaatape:BAABNQAECn8fAAQSAAgKiQ8TIAAlAQASAAcKnw0TIAAlAQATAAcK5AWLgAAbAQAMAAEKXhrCvQBMAAAAAA==.Tyraell:BAAANQAECggIDwAAAA==.',
['Tõ']='Tõkó:BAAANQADCgUIBQABNQAFFAUIDAAbAGQZAA==.',
Um='Umbrae:BAAANQADCgMIAQAAAA==.Umfray:BAAANQAECgIIAwABNQAECgUIDgAIAAAAAA==.',
Us='Usgasdanelv:BAABNQAECn8fAAIWAAkK5BnODAChAgAWAAkK5BnODAChAgAAAA==.',
Uz='Uzala:BAABNQAECn8VAAIEAAYK3QYxfACKAAAEAAYK3QYxfACKAAAAAA==.',
Va='Vanleiden:BAAANQADCgEIAQAAAA==.Vazro:BAABNQAECn8xAAMLAAoKBhU1JgBKAQALAAoKBhU1JgBKAQAYAAYKLQZiFAH9AAAAAA==.',
Ve='Vendiyre:BAAANQAECgYIBgAAAA==.Venthyl:BAACNQAFFH8IAAINAAUK/SAvDQCYAQANAAUK/SAvDQCYAQA1AAQKfy0AAw0ACgo0JFEKAHoDAA0ACgo0JFEKAHoDABcAAgoQJHoWAGwAAAAA.Veyra:BAAANQABCgMIAwAAAA==.',
Vi='Vindictina:BAAANQABCgMIAwAAAA==.Vizan:BAAANQABCgcIBwABNQAECggIJAAmACUbAA==.',
Wa='Warzone:BAAANQADCgUIBQAAAA==.',
We='Wellby:BAAANQAECgIIAgAAAA==.Westerin:BAABNQAECn8iAAIVAAkKPg/WDwAAAgAVAAkKPg/WDwAAAgAAAA==.',
Wi='Wildnature:BAAANQADCggIDgAAAA==.Wildwest:BAAANQADCgcIBwAAAA==.Wimateeka:BAABNQAECn8qAAQYAAkKBhhoOgBUAQAkAAYKnRviHQD6AQAYAAgKWhVoOgBUAQALAAMKtAoGhQBKAAAAAA==.Windfury:BAAANQAECgYICAABNQAECgkJLAAFAMQjAA==.Windigo:BAAANQAECgIIAgAAAA==.Winginit:BAAANQAECgEIAQABNQAFFAYIEgANAGUTAA==.',
Wo='Wooqles:BAAANQADCgUIBQABNQADCgYICAAIAAAAAA==.',
Wr='Wrastelas:BAAANQADCggICAAAAA==.',
Wu='Wuilhem:BAAANQADCgEIAQAAAA==.Wurkim:BAAANQADCgQIBAABNQADCggICAAIAAAAAA==.',
Xa='Xaala:BAAANQAECgQIBQAAAA==.',
Xo='Xosderdk:BAAANQADCgIIAgAAAA==.',
Ya='Yarjuul:BAAANQAECgIIAgABNQAECgUIDgAIAAAAAA==.',
Ye='Yespaladin:BAACNQAFFH8NAAIMAAUK4hRCDgBvAQAMAAUK4hRCDgBvAQA1AAQKfzAAAgwACQquIBIPADYDAAwACQquIBIPADYDAAAA.',
Yi='Yimity:BAAANQAECgMIAwAAAA==.',
Yo='Yogí:BAACNQAFFH8RAAIPAAYKjBQcDQB7AQAPAAYKjBQcDQB7AQA1AAQKfzEAAg8ACgo5HwIPAEsDAA8ACgo5HwIPAEsDAAAA.Yozomoto:BAACNQAFFH8SAAIbAAYKTR8tCADJAQAbAAYKTR8tCADJAQA1AAQKfzUAAxsACgrnJGcCANkCABsACgrnJGcCANkCABkAAgo8D3B2AGMAAAAA.',
Za='Zalandria:BAABNQAECn8WAAIQAAYKARVMDQDcAAAQAAYKARVMDQDcAAAAAA==.Zarelasong:BAAANQADCgIIAgAAAA==.',
Ze='Zeltemis:BAABNQAECn8XAAIbAAgKpQicjwDqAQAbAAgKpQicjwDqAQAAAA==.',
Zi='Zipsion:BAABNQAECn8vAAIbAAoKxyE5GAA5AwAbAAoKxyE5GAA5AwAAAA==.Zivver:BAABNQAECn8mAAIQAAkKlSL4AgB6AwAQAAkKlSL4AgB6AwAAAA==.Zizka:BAABNQAECn8cAAIdAAgKlgVROQBcAQAdAAgKlgVROQBcAQAAAA==.',
Zo='Zolandir:BAAANQAECgMIAwAAAA==.',
Zu='Zuljia:BAAANQADCggICAABNQAECgYIIgAeAMgcAA==.',
['Òh']='Òhká:BAAANQAECgEIAQAAAA==.',
['Üt']='Üther:BAABNQAECn8zAAIYAAoKUiPXEACGAwAYAAoKUiPXEACGAwAAAA==.',
['ßu']='ßubbleøseven:BAABNQAECn8VAAMYAAkK/hwnTACwAgAYAAkK/hwnTACwAgAkAAMK0BKKGADIAAAAAA==.',
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
