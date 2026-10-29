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

local lookup = {'DemonHunter-Vengeance','DemonHunter-Havoc','DemonHunter-Devourer','Warlock-Demonology','Mage-Arcane','Mage-Frost','Priest-Holy','Unknown-Unknown','Evoker-Preservation','Warrior-Arms','Paladin-Holy','DeathKnight-Blood','Shaman-Restoration','Shaman-Elemental','Druid-Balance','Rogue-Assassination','Rogue-Subtlety','Warrior-Protection','Warrior-Fury','DeathKnight-Unholy','DeathKnight-Frost','Monk-Brewmaster','Warlock-Destruction','Shaman-Enhancement','Druid-Feral','Paladin-Retribution','Hunter-Marksmanship','Hunter-BeastMastery','Priest-Shadow','Druid-Restoration','Priest-Discipline','Monk-Mistweaver','Monk-Windwalker','Druid-Guardian','Evoker-Devastation','Paladin-Protection','Mage-Fire','Warlock-Affliction','Hunter-Survival',}
local provider = {region='US',realm='Nordrassil',name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aairidari:BAABNQAECn8tAAQBAAkKMQjEGwD+AAACAAgK0wbTVAA8AQABAAYK4QnEGwD+AAADAAIKVAQNQQBBAAAAAA==.',
Ab='Abruna:BAABNQAECn8WAAIEAAgK/BPXbwAQAgAEAAgK/BPXbwAQAgABNQAFFAcIFAAFAGcUAA==.Abruno:BAACNQAFFH8UAAMFAAcKZxRRHACbAQAFAAYKCRJRHACbAQAGAAEK4B2OBwBgAAA1AAQKfzMAAwUACgqdItYlAF8CAAUACgolIdYlAF8CAAYAAQqPIaMjAFwAAAAA.Abruto:BAAANQAECgYIDgABNQAFFAcIFAAFAGcUAA==.',
Ae='Aeown:BAAANQAECgMIBgABNQAECgoKTgAHABUXAA==.Aerdis:BAAANQADCggIFQABNQAECgYIDQAIAAAAAA==.',
Ah='Aharuka:BAAANQADCgEIAQAAAA==.',
Ak='Akukho:BAAANQADCgIIAgAAAA==.',
Al='Alandrìas:BAABNQAECn80AAMBAAoK8Aq/CQBMAQABAAoK8Aq/CQBMAQACAAEKAABueQAAAAAAAA==.Altera:BAABNQAECn8kAAIJAAgKwxD0IADKAQAJAAgKwxD0IADKAQAAAA==.',
Am='Amuri:BAAANQAECgUIBgAAAA==.',
An='Andelarenn:BAAANQABCgIIAgAAAA==.Andere:BAAANQAECgYICQAAAA==.Androo:BAABNQAECn8fAAIKAAoK9A9LRAC+AQAKAAoK9A9LRAC+AQABNQAFFAcIFAALAOMXAA==.Androonatorz:BAACNQAFFH8UAAILAAcK4xd6CgC1AQALAAcK4xd6CgC1AQA1AAQKfyYAAgsACgrqIZcbAAcDAAsACgrqIZcbAAcDAAAA.Anfernay:BAABNQAECn8nAAIKAAoKbxG+egAoAgAKAAoKbxG+egAoAgAAAA==.Antheion:BAAANQAECgIIAwABNQAECgcIKAAMADUUAA==.Antiaxxis:BAAANQADCgEIAQAAAA==.',
Ap='Apawthetic:BAABNQAECn8bAAMNAAkKRiEBCwATAwANAAkKRiEBCwATAwAOAAQKiAZ48wCuAAABNQAFFAcIEwAPAHwRAA==.',
Aq='Aquadab:BAAANQADCgQICAAAAA==.',
Ar='Arashatora:BAAANQAECgEIAQABNQAECgMIAgAIAAAAAA==.Arcanodare:BAAANQADCggICAAAAA==.Arkalis:BAAANQADCgYIBgAAAA==.Arveiturace:BAAANQAECgQIDQAAAA==.',
As='Ashborrn:BAAANQADCgUIBQAAAA==.Ashtar:BAABNQAECn8oAAIKAAgKnxA2jwD2AQAKAAgKnxA2jwD2AQAAAA==.Asukajo:BAAANQADCgMIAwAAAA==.',
At='Attack:BAAANQAECgYIDgAAAA==.',
Ax='Axhure:BAAANQABCgMIAgAAAA==.',
Ba='Babydoll:BAAANQAECgQICAAAAA==.Bajablast:BAAANQADCgcIDQAAAA==.Barma:BAAANQAECgYICQAAAA==.Barrin:BAABNQAECn8aAAIFAAoK3RnuHwB7AgAFAAoK3RnuHwB7AgAAAA==.',
Be='Bearlyseen:BAABNQAECn8kAAIQAAkKYB1aBwAnAgAQAAkKYB1aBwAnAgABNQAFFAUIEAANACgMAA==.Beltirra:BAAANQAECgMIBAAAAA==.',
Bh='Bhangbros:BAAANQADCgcIBwAAAA==.',
Bi='Biggums:BAAANQAECgMIBAAAAA==.Bigmobility:BAABNQAECn81AAIMAAoKeyIKCAB8AwAMAAoKeyIKCAB8AwAAAA==.Bigwill:BAABNQAECn9IAAIGAAoKkCHnAgAsAwAGAAoKkCHnAgAsAwAAAA==.',
Bl='Blargy:BAABNQAECn86AAIPAAoKbxfPJACrAgAPAAoKbxfPJACrAgAAAA==.Bleach:BAABNQAECn8UAAMQAAgKfAhEKwDDAAAQAAYK/AZEKwDDAAARAAYKHgnaZwDBAAAAAA==.Bluewaffles:BAAANQADCgEIAQABNQAECgQIAwAIAAAAAA==.',
Bo='Borealslam:BAAANQADCgQIBAAAAA==.Bouzol:BAAANQAECgYIBgAAAA==.',
Br='Brighterbonk:BAAANQAECgMIBAAAAA==.Brimara:BAAANQAECgUIDAAAAA==.Brothaagamor:BAAANQADCgIIAgAAAA==.',
Bu='Bucketojoy:BAABNQAECn8VAAIFAAgKPgKCUgEHAQAFAAgKPgKCUgEHAQAAAA==.Bunsen:BAAANQAECgQIBAABNQAECgoKNQAKAPkdAA==.',
['Bà']='Bàtman:BAAANQAECgQIBwAAAA==.',
Ca='Caliburne:BAABNQAECn88AAQKAAoKpx7cFgCwAgAKAAoKCx7cFgCwAgASAAUKhh+5FgC/AQATAAMK6h4xGQAPAQAAAA==.Captamerica:BAAANQABCgQIBgAAAA==.Capz:BAACNQAFFH8YAAIKAAgKTxvCBACHAgAKAAgKTxvCBACHAgA1AAQKfyUAAgoACgqaJe8fADgDAAoACgqaJe8fADgDAAAA.',
Ce='Ceez:BAABNQAECn8aAAIKAAkKTAwAXgBoAQAKAAkKTAwAXgBoAQAAAA==.Ceezinator:BAAANQADCgQIBAAAAA==.',
Ch='Chichujongar:BAABNQAECn8UAAQMAAcKwwsFbwA5AQAMAAcKcwsFbwA5AQAUAAYKwwUziwD3AAAVAAYKmgXFTgDbAAABNQAFFAcIEwAWAM4OAA==.Chickenstwip:BAAANQADCgEIAgABNQAECgoKNAAFAEQdAA==.Chopperr:BAAANQAECgQIBAABNQAECgoKNAAFAEQdAA==.Chosenöne:BAAANQADCgEIAQAAAA==.Chèn:BAAANQAECgcIEgAAAA==.',
Ci='Cindrella:BAABNQAECn8vAAIGAAoKXSGXAADDAwAGAAoKXSGXAADDAwAAAA==.',
Cl='Clayre:BAACNQAFFH8UAAIXAAUKXRSMAACgAQAXAAUKXRSMAACgAQA1AAQKf0wAAhcACgp3JLgAALMDABcACgp3JLgAALMDAAAA.Clow:BAAANQAECgYIEAAAAA==.',
Co='Colossus:BAAANQAECgIIBAAAAA==.Coolcrush:BAAANQADCgUICAABNQAECgoKLwAYAFskAA==.Corven:BAACNQAFFH8TAAIEAAcKshQcDwCLAQAEAAcKshQcDwCLAQA1AAQKf0sAAwQACgpGIq4LAG8DAAQACgpGIq4LAG8DABcAAQpFBbiEACUAAAAA.',
Cr='Craziks:BAAANQADCgIIAgAAAA==.Critzwar:BAACNQAFFH8RAAIKAAcKphPsEACtAQAKAAcKphPsEACtAQA1AAQKfyQAAgoACgqZIWQxAPoCAAoACgqZIWQxAPoCAAAA.Crönus:BAAANQAECgIIAgAAAA==.',
Ct='Cthuluwu:BAAANQADCggICAAAAA==.',
Da='Daedyxes:BAABNQAECn8hAAIMAAkKEg14OQD9AAAMAAkKEg14OQD9AAAAAA==.Danrod:BAAANQAECgIIAgAAAA==.Daní:BAAANQADCgUIBwABNQAECgEIAQAIAAAAAA==.Darfur:BAAANQAECggIDgAAAA==.Darkensi:BAAANQABCgYICQAAAA==.Dasherdeez:BAAANQAECgEIAQAAAA==.Daygath:BAAANQAECgEJAQAAAA==.',
De='Deadlyiris:BAABNQAECn81AAIKAAoK+R2CIQBqAgAKAAoK+R2CIQBqAgAAAA==.Deadshot:BAAANQAECgQIDAAAAA==.Deatharin:BAAANQADCgUIBgAAAA==.Deathjak:BAAANQAECgcICAABNQAECgoKLwAFAC0iAA==.Demonbulio:BAABNQAECn8XAAICAAgK9QZNSgB7AQACAAgK9QZNSgB7AQAAAA==.Demonisthicc:BAABNQAECn85AAIZAAoKDB6+BABVAgAZAAoKDB6+BABVAgAAAA==.Demonskitten:BAAANQADCgUIBQABNQAECgoKOQAZAAweAA==.Demonslayeer:BAAANQADCggIDQAAAA==.Demoronicon:BAAANQAECgcIBwAAAA==.Devi:BAAANQAECgYICwAAAA==.',
Di='Diaravynn:BAAANQADCgMIBQAAAA==.Diddylord:BAAANQAECgMIAwABNQAECgoKNAAFAEQdAA==.Dithehealer:BAABNQAECn8oAAIaAAkKrBQVkgAAAgAaAAkKrBQVkgAAAgAAAA==.Divain:BAAANQADCgQIBgAAAA==.',
Dk='Dkdi:BAAANQAECgUIBQAAAA==.',
Do='Dozekar:BAAANQAECgEIAQAAAA==.',
Dr='Drenamai:BAAANQAECgUIDgAAAA==.Drexywexyuwu:BAAANQADCgcJBwAAAA==.',
Du='Duhmptruhk:BAABNQAECn8uAAIKAAoKMxi3MgALAgAKAAoKMxi3MgALAgAAAA==.Dunbroch:BAACNQAFFH8SAAIbAAYKZhq8BwDPAQAbAAYKZhq8BwDPAQA1AAQKfzAAAhsACgrjHXcVALICABsACgrjHXcVALICAAAA.Duskforge:BAAANQABCgIJAgAAAA==.',
Dw='Dwagen:BAAANQAECgQIBAAAAA==.',
['Dé']='Démonicblood:BAACNQAFFH8RAAIVAAUKsSHGBgCSAQAVAAUKsSHGBgCSAQA1AAQKfzMAAhUACgr4IMgGAPwCABUACgr4IMgGAPwCAAAA.',
Eg='Eggplantgodx:BAABNQAECn82AAMBAAoKSSVlAQD8AgABAAkKSSVlAQD8AgACAAgKKRlqLwArAgAAAA==.',
Ek='Ekhart:BAAANQAECgEIAQAAAA==.',
El='Elfajah:BAAANQADCgYICQAAAA==.Eliicia:BAACNQAFFH8SAAMQAAcKrwyBCACGAQAQAAYKYg6BCACGAQARAAEK5AX5GABRAAA1AAQKfy0AAxAACgpbILQYALcCABAACgpbILQYALcCABEACAqwDYAyACgBAAAA.',
Em='Emmy:BAAANQAECgQIDwAAAA==.Emofineshyt:BAAANQADCgcICgAAAA==.Emogothbabe:BAABNQAECn80AAMFAAoKRB1UKQBOAgAFAAoKRB1UKQBOAgAGAAMK8w5RLACZAAAAAA==.Emowrecky:BAABNQAECn8jAAMEAAgKbx0GYwAwAgAEAAgKbx0GYwAwAgAXAAEKjA76JgA9AAAAAA==.',
En='Endo:BAACNQAFFH8QAAMUAAcKIRuuCgBlAQAUAAUKGh6uCgBlAQAVAAQKBhYtEQDMAAA1AAQKfz8AAxQACgoLJU0SACUDABQACQooJU0SACUDABUACApyIGMgAMkBAAAA.Endorush:BAABNQAECn8pAAICAAoKzx59GQDPAgACAAoKzx59GQDPAgABNQAFFAcIEAAUACEbAA==.Endrigosa:BAAANQAECgUIBgAAAA==.Eneldenes:BAAANQAECgUICwAAAA==.Enjoyer:BAAANQAECgcIDgAAAA==.',
Er='Ereitherla:BAABNQAECn8kAAIcAAcK+gg1kwALAQAcAAcK+gg1kwALAQAAAA==.',
Es='Esmenet:BAAANQAECgYIEAAAAA==.Espressð:BAABNQAECn8mAAIHAAkK3CFBCQBJAwAHAAkK3CFBCQBJAwABNQAECgoKNAAFAEQdAA==.',
Ex='Excalibear:BAABNQAECn8cAAILAAoK2hgqGQB6AgALAAoK2hgqGQB6AgABNQAFFAUIEAANACgMAA==.',
Ey='Eydis:BAAANQADCgcIDgAAAA==.Eyepisspeas:BAAANQABCgMIBAAAAA==.',
Fe='Feironor:BAAANQAECgMIAwAAAA==.Fenrys:BAAANQAECgQIBAAAAA==.',
Fi='Fikareous:BAAANQADCggIDQABNQAECgUIBQAIAAAAAA==.',
Fl='Flayre:BAABNQAECn8oAAMNAAkK3RtQRQBMAgANAAgK3BtQRQBMAgAOAAcKMBcNaADoAQAAAA==.Fleredil:BAABNQAECn82AAMdAAoKTSBhBgCxAgAdAAoKTSBhBgCxAgAHAAEKgQXG/gAuAAAAAA==.Flingernle:BAABNQAECn8oAAIOAAkKfCL9BgASAwAOAAkKfCL9BgASAwAAAA==.',
Fo='Forepray:BAACNQAFFH8QAAIdAAUKVA2NCwAzAQAdAAUKVA2NCwAzAQA1AAQKf0AAAh0ACgrVH6UJAEUDAB0ACgrVH6UJAEUDAAAA.Forger:BAABNQAECn8sAAMSAAkKDAwzEwALAQASAAkKDAwzEwALAQAKAAIKQQjVOQFhAAAAAA==.Forsakey:BAAANQADCggIFAABNQAFFAcIDgAeAGIWAA==.',
Fr='Fraun:BAAANQADCggJEQAAAA==.Freshdk:BAAANQAECgQIBAAAAA==.',
Fu='Fullyprotpal:BAAANQAECgEIAQAAAA==.Furioustotem:BAABNQAECn8lAAIOAAcK5BcMTQAmAQAOAAcK5BcMTQAmAQAAAA==.Future:BAAANQADCgUIBgABNQAECgkJLAAFAMQjAA==.',
Fy='Fycat:BAAANQAFFAEIAQABNQAFFAMICAAEAKEeAA==.',
Ga='Galten:BAAANQADCgUIBQAAAA==.Gantz:BAAANQADCgIJAgAAAA==.',
Ge='Geekbarr:BAAANQADCgUIBQABNQAECgoKNAAFAEQdAA==.',
Gh='Ghettox:BAAANQADCgYICAAAAA==.Ghostw:BAABNQAECn8VAAIKAAYKoB3UWQB0AQAKAAYKoB3UWQB0AQAAAA==.',
Gi='Giovanni:BAAANQAECggICAAAAA==.Gizik:BAAANQADCgcIDQABNQAFFAcIFwAdABESAA==.',
Gn='Gnasher:BAAANQABCgQIBAAAAA==.',
Go='Golgotterath:BAACNQAFFH8QAAINAAUKKAwODwBeAQANAAUKKAwODwBeAQA1AAQKfzkAAw0ACgr8HaAdAFYCAA0ACgr8HaAdAFYCAA4AAQqNB/I6ATAAAAAA.Gorm:BAABNQAECn8oAAIFAAoKKhqwVgDTAgAFAAoKKhqwVgDTAgABNQAECgQIBQAIAAAAAA==.',
Gr='Grippyshocks:BAAANQAECgIIAQABNQAECgoKKQACAGIgAA==.',
Ha='Halbruck:BAAANQAECgcIEQAAAA==.Haldane:BAABNQAECn8zAAIaAAkKRAotggBNAQAaAAkKRAotggBNAQABNQAECgoKNQAKAPkdAA==.Harrydottur:BAAANQAECggIDQABNQAFFAUIDQAEABwbAA==.Havochunter:BAAANQAECgYICQAAAA==.Hawley:BAAANQABCgIIAgAAAA==.',
He='Heidegger:BAAANQADCgYICgAAAA==.Helinndealin:BAACNQAFFH8PAAIfAAUKXiCtAADoAQAfAAUKXiCtAADoAQA1AAQKfywAAx8ACgrEJFQBAEcDAB8ACQryJFQBAEcDAAcACAotIsZJAEgCAAAA.Hellin:BAAANQADCgMIAQAAAA==.Heolstor:BAABNQAECn8zAAIMAAoKcRySEwAQAgAMAAoKcRySEwAQAgAAAA==.Hephsdh:BAAANQAECgYIDwAAAA==.Heraois:BAABNQAECn8eAAIbAAkKjgmsNgCZAQAbAAkKjgmsNgCZAQAAAA==.',
Hg='Hgshake:BAAANQADCgYIBgAAAA==.',
Ho='Holytës:BAAANQAECgUIBQAAAA==.Holywráth:BAAANQADCgUIDwAAAA==.',
Hu='Hunterdh:BAABNQAECn8jAAIcAAgK+gaWdwBFAQAcAAgK+gaWdwBFAQAAAA==.',
Hy='Hynixx:BAABNQAECn8sAAMTAAoKnBsdCQBKAgATAAgKJRodCQBKAgAKAAcKeRjLTgCYAQABNQAFFAUIEAAdAFQNAA==.',
Il='Illidope:BAABNQAECn8pAAQCAAoKYiDMDACBAgACAAoKSyDMDACBAgADAAgK+xwZIwAxAgABAAEKAACILgBGAAAAAA==.',
In='Infinitevoid:BAAANQADCggIFQAAAA==.Innervatez:BAABNQAFFH8LAAIeAAUKJCMuBADuAQAeAAUKJCMuBADuAQAAAA==.Inteaus:BAAANQADCggIGgAAAA==.',
Io='Ionúin:BAAANQADCgQJBAAAAA==.',
Iv='Ivÿ:BAAANQADCgMIBQABNQAECgQIBwAIAAAAAA==.',
Ja='Jabkhan:BAAANQAECgUIBwAAAA==.Jaekir:BAABNQAECn8kAAIGAAgKhBWRCwAHAgAGAAgKhBWRCwAHAgAAAA==.Jakfrost:BAABNQAECn8vAAMFAAoKLSKlMwAjAgAFAAkKOCKlMwAjAgAGAAMKKiLkGgAcAQAAAA==.Jakie:BAAANQADCgYICgABNQAECggIFwAKAN8aAA==.Jarten:BAACNQAFFH8PAAIVAAUKXxlRCABvAQAVAAUKXxlRCABvAQA1AAQKf0AAAhUACgonIYUHAO8CABUACgonIYUHAO8CAAAA.Jayaah:BAAANQAECgMIBAAAAA==.Jaylebate:BAABNQAECn8WAAMUAAgKrxkEGwCdAQAUAAgK9xcEGwCdAQAMAAYKbxpcXACBAQAAAA==.',
Je='Jerrenn:BAAANQAECgQIBAAAAA==.Jesseatamer:BAACNQAFFH8PAAIcAAUKbCBsCAATAQAcAAUKbCBsCAATAQA1AAQKfz4AAhwACgptJfICAF4DABwACgptJfICAF4DAAAA.',
Ji='Jitsuru:BAAANQADCgUIBQAAAA==.',
Jo='Jox:BAAANQABCgUIBQAAAA==.Joxor:BAAANQABCgUIBQAAAA==.',
Js='Jstdeath:BAAANQADCgEIAQABNQAECgoKNQAKAHEVAA==.Jstrawr:BAABNQAECn81AAIKAAoKcRVvYgBnAgAKAAoKcRVvYgBnAgAAAA==.Jsttotem:BAAANQAECgUIBQABNQAECgoKNQAKAHEVAA==.',
Ka='Kalmek:BAABNQAECn8VAAMUAAkKLw26IABuAQAUAAkKkAy6IABuAQAVAAIKMQb5iwAyAAAAAA==.Kaln:BAAANQAECgIIBwABNQAECgQIBQAIAAAAAA==.Karen:BAAANQAECgUIDgAAAA==.Kasalu:BAAANQABCgQIBAAAAA==.Kasanzzar:BAAANQAECgYIBwAAAA==.Kastia:BAAANQAECgQIBgAAAA==.Kasumï:BAAANQAECgEIAQABNQAFFAUIEAAcAF8jAA==.Katrynwel:BAAANQAECgQIBAAAAA==.Katsumi:BAAANQAECgQIBgAAAA==.',
Ke='Keliki:BAABNQAECn8yAAMNAAoKGB7SCAA1AwANAAoKGB7SCAA1AwAOAAgKzhigQQBvAgAAAA==.Kettama:BAAANQAECgUIBQABNQAECgoKNAAFAEQdAA==.',
Kh='Khold:BAABNQAECn8oAAMVAAoKnhlPGwDzAQAVAAoKnhlPGwDzAQAMAAQKBw4+VgCTAAAAAA==.Khrogann:BAAANQAECggIEQAAAA==.',
Ki='Kijana:BAAANQADCggICAAAAA==.Killalltoday:BAABNQAECn8mAAINAAgKWRJ9aQDQAQANAAgKWRJ9aQDQAQAAAA==.Killersmile:BAAANQADCgQIBAAAAA==.Kirkk:BAAANQAECgEIAQAAAA==.',
Kl='Klaminus:BAAANQADCgQIBAABNQAECgMIAgAIAAAAAA==.',
Kn='Knixx:BAACNQAFFH8UAAIHAAcKIBEIEACUAQAHAAcKIBEIEACUAQA1AAQKf0oAAwcACgo0JesAAOQDAAcACgo0JesAAOQDAB8ABgrzEYsPADIBAAAA.Knuppelus:BAAANQADCgYIDAAAAA==.',
Ko='Kobyashimaru:BAAANQADCgUIBQAAAA==.Koshi:BAAANQADCgMIAwAAAA==.Kotastrophe:BAAANQAECgMIAwABNQAECgoKLgAKADMYAA==.Koveras:BAAANQADCgYIBwAAAA==.Koyaanis:BAAANQADCggIDgAAAA==.Koyya:BAABNQAECn8oAAMYAAoKnA03FAAlAgAYAAkK5Ao3FAAlAgANAAoKdQ98SQBvAQAAAA==.',
Kr='Krathos:BAAANQAECgIIBgAAAA==.Krenmonk:BAAANQAECgEIAQAAAA==.Krennic:BAAANQADCgcIBwAAAA==.Krunchee:BAAANQAECgIIBgAAAA==.',
Ku='Kufoo:BAABNQAECn8vAAMTAAoKRSSWAgBOAwATAAoKRSSWAgBOAwASAAEKkx7yKABXAAAAAA==.Kurao:BAAANQAECgMIBQAAAA==.Kurukai:BAAANQADCgMIAwAAAA==.',
Ky='Kyrian:BAACNQAFFH8fAAMRAAcKriBiAQBaAgARAAcKriBiAQBaAgAQAAMKvREHEADrAAA1AAQKfzQAAxEACgrcIygFADgDABEACgrcIygFADgDABAAAwpZHHlvAPMAAAAA.',
La='Lagøless:BAABNQAECn8hAAIcAAoKYCAhEwBTAwAcAAoKYCAhEwBTAwAAAA==.',
Le='Leo:BAAANQAECgEIAQAAAA==.',
Li='Liatris:BAAANQAECgUIBQAAAA==.Likestoflash:BAEANQADCgYIBgABNQAECgoKPQAcAAEdAA==.Lissaris:BAAANQADCgEIAgAAAA==.',
Lo='Lohal:BAABNQAECn8yAAIEAAoKvxgmJgAdAgAEAAoKvxgmJgAdAgAAAA==.Lohmi:BAABNQAECn8ZAAIOAAkKnQVGRwA5AQAOAAkKnQVGRwA5AQAAAA==.Lormn:BAAANQADCgEIAQAAAA==.',
Lu='Luania:BAAANQAECgQIBgAAAA==.',
Ly='Lyna:BAAANQADCggJDAAAAA==.Lyshkä:BAABNQAECn8xAAIgAAoKaBpAEAB7AgAgAAoKaBpAEAB7AgAAAA==.Lyzzardkng:BAABNQAECn8qAAIaAAoKQAlXagCBAQAaAAoKQAlXagCBAQAAAA==.',
['Lý']='Lýra:BAAANQAECgUIBwAAAA==.',
Ma='Maango:BAABNQAECn8aAAIaAAoKlxlXKwBSAgAaAAoKlxlXKwBSAgAAAA==.Maemu:BAAANQABCgUIBwAAAA==.Magerthat:BAAANQADCgQIBgAAAA==.Magicaltickl:BAABNQAECn8aAAIFAAkKMgqT4ADHAQAFAAkKMgqT4ADHAQAAAA==.Magiki:BAAANQADCgcICwAAAA==.Makyaihua:BAAANQABCggIHAAAAA==.Malkala:BAAANQADCgMIAwAAAA==.Malonormu:BAAANQABCgcIBgAAAA==.Mamadeezy:BAAANQADCgYJCwAAAA==.Mando:BAAANQAECgIIBgABNQAECgcIJAAhAGQYAA==.Manical:BAAANQAECgMICwAAAA==.Marcel:BAAANQADCgYIEQABNQAECgMIBAAIAAAAAA==.Martinikiss:BAAANQAECgcIEAAAAA==.Mashiach:BAACNQAFFH8LAAIHAAUKEB2gDADBAQAHAAUKEB2gDADBAQA1AAQKfyYAAwcACgpTIdgPAEcDAAcACgpTIdgPAEcDAB0AAQoAALx4ADYAAAAA.Matthyjsz:BAAANQADCgIIAgAAAA==.',
Me='Megumin:BAAANQAECgUICAABNQAECgoKOQAaABgkAA==.Melikefire:BAABNQAECn8hAAIFAAoKURZXmgBMAgAFAAoKURZXmgBMAgAAAA==.Melodious:BAAANQAECgEIAQAAAA==.Memecompdall:BAAANQAECgIIAgAAAA==.Merek:BAABNQAECn8iAAIWAAgKyB8JBwDSAgAWAAgKyB8JBwDSAgAAAA==.Mettix:BAAANQADCgIIAgAAAA==.',
Mi='Mirigosa:BAAANQAECgEIAQABNQAECgoKLwAGAF0hAA==.Mistybdk:BAABNQAECn8pAAIMAAoK1BRrFwDiAQAMAAoK1BRrFwDiAQABNQAFFAcIFgAiAOITAA==.Mistyd:BAACNQAFFH8WAAIiAAcK4hOIAABGAgAiAAcK4hOIAABGAgA1AAQKf0kAAiIACgpKJYkBAMwDACIACgpKJYkBAMwDAAAA.',
Mo='Mogfooyen:BAAANQABCgYICQAAAA==.Moonbeam:BAAANQAECgUIBgAAAA==.Morgause:BAABNQAECn8VAAIEAAYKGAZ+jADXAAAEAAYKGAZ+jADXAAAAAA==.Morllan:BAABNQAECn8hAAIEAAoKeg0qggDgAQAEAAoKeg0qggDgAQAAAA==.',
Mu='Muirdin:BAAANQADCgEIAQAAAA==.',
My='Mykinlive:BAAANQADCgIIAgAAAA==.',
['Må']='Mångix:BAAANQAECgQIBAAAAA==.',
['Mé']='Mélusine:BAABNQAECn8ZAAMKAAkKURJ5igABAgAKAAkKpw95igABAgATAAQKrRB2HQDYAAAAAA==.',
Na='Naanomage:BAAANQAECgMIBgAAAA==.Nagakabouros:BAAANQABCgIIAgAAAA==.Naija:BAAANQADCgIIAgAAAA==.Narcotx:BAAANQADCgIIAgAAAA==.',
Ne='Necrotoxin:BAAANQADCgYIBgAAAA==.',
Ni='Nightmaratic:BAAANQADCgYIBgAAAA==.Nightsdeath:BAAANQAECgEIAQAAAA==.Nightsever:BAABNQAECn8nAAIDAAkKwSJIBwBeAwADAAkKwSJIBwBeAwAAAA==.Nirath:BAABNQAECn8kAAIjAAgK6wSeIABOAQAjAAgK6wSeIABOAQAAAA==.',
No='Noiire:BAAANQAECggIDQABNQAFFAcIEgAQAK8MAA==.',
Od='Odysse:BAAANQADCgYICQAAAA==.Odyssé:BAABNQAECn8gAAIcAAkKTR7UIQAQAwAcAAkKTR7UIQAQAwAAAA==.',
Oi='Oio:BAAANQAECgcIAgAAAA==.',
Ok='Okami:BAABNQAECn8cAAIhAAYKFB79GABrAQAhAAYKFB79GABrAQAAAA==.',
On='Onehotelf:BAAANQAECgQIBAAAAA==.',
Oo='Ooyagoddess:BAAANQAECgEIAgAAAA==.',
Or='Orienn:BAAANQADCgYIBgAAAA==.',
Pa='Pacamonk:BAABNQAECn83AAIhAAoKXh0sDQAIAwAhAAoKXh0sDQAIAwAAAA==.Palenar:BAAANQADCgQIBAAAAA==.Papatiny:BAAANQAECgYIEAAAAA==.Papábear:BAAANQADCgQIBAAAAA==.Pawsa:BAAANQAECgcIDAABNQAECgoKNAAFAEQdAA==.Pawthetic:BAACNQAFFH8TAAQPAAcKfBFdEgBEAQAPAAUK5RRdEgBEAQAeAAEKVw6PFABNAAAZAAEK2AMZAwBLAAA1AAQKfzkAAx4ACgpmIc8HANkCAB4ACgpmIc8HANkCAA8ACgrCHFcfANACAAAA.',
Pe='Peelforheals:BAACNQAFFH8FAAIdAAMKLAcGFACMAAAdAAMKLAcGFACMAAA1AAQKfzMAAx0ACgqkHpwOAAYDAB0ACgqkHpwOAAYDAB8ABQpdDHsXALoAAAAA.Penguindemic:BAABNQAECn8qAAMEAAoKzCSaBgCaAwAEAAoKzCSaBgCaAwAXAAEKoCISagBNAAAAAA==.Pep:BAABNQAECn8UAAIhAAkKhQpJPAAzAQAhAAkKhQpJPAAzAQAAAA==.Pepperoni:BAAANQADCggIDQAAAA==.Perdator:BAAANQAECgQICAAAAA==.Petruccius:BAACNQAFFH8XAAIPAAUKcQ41DADWAAAPAAUKcQ41DADWAAA1AAQKf1kAAg8ACgo1IFEMAGgDAA8ACgo1IFEMAGgDAAAA.Pewpewlepew:BAAANQAECgQICQAAAA==.',
Ph='Phaeku:BAAANQADCgMIAwAAAA==.',
Pi='Picklebreath:BAAANQADCgUICgAAAA==.Pinksparklez:BAAANQADCgUICAABNQAECgEIAQAIAAAAAA==.',
Pl='Plague:BAAANQAECgMIAwAAAA==.',
Po='Poptartsz:BAAANQAECgQICQAAAA==.Potatolockx:BAAANQAECgQIAwAAAA==.',
Pr='Prayre:BAAANQAECggIEAAAAA==.Precht:BAAANQAECgMIBAAAAA==.Prikarea:BAAANQAECgUIBQAAAA==.Prospa:BAAANQAECgQIBgABNQAECgoKNAAFAEQdAA==.Prumper:BAABNQAECn8eAAIFAAkKVxE1xQD6AQAFAAkKVxE1xQD6AQAAAA==.Príest:BAAANQAECggICAAAAA==.',
Pu='Purah:BAAANQADCgEIAgAAAA==.',
['Pä']='Päncake:BAAANQAECgQIBQABNQAECgQIBwAIAAAAAA==.',
Qu='Quesoblanco:BAABNQAECn8bAAMkAAgKcxAxOwAXAQAaAAgKeQhB1QBxAQAkAAUKKhkxOwAXAQAAAA==.',
Qy='Qybxboogietk:BAABNQAECn8iAAICAAkK8hSuIgCAAQACAAkK8hSuIgCAAQAAAA==.',
Ra='Rabid:BAAANQAECgQIDAAAAA==.Raeliana:BAAANQADCgQIBAAAAA==.Raghallov:BAAANQAECggIEAAAAA==.Rampa:BAAANQADCgYIEQABNQAECgoKNAAFAEQdAA==.',
Re='Reaperan:BAAANQAECgEIAQAAAA==.Regena:BAABNQAECn9OAAMHAAoKFRdfGQCWAgAHAAoKFRdfGQCWAgAdAAMKOQKLagBYAAAAAA==.Rekriss:BAAANQADCgYIBgAAAA==.Remorse:BAACNQAFFH8SAAISAAYKZRKNAgBrAQASAAYKZRKNAgBrAQA1AAQKf0MAAhIACgpeIWYGAAADABIACgpeIWYGAAADAAAA.Rendwick:BAAANQADCgYICQAAAA==.Required:BAAANQAECggIEgABNQAFFAYIEQACANAgAA==.',
Ri='Rikahoe:BAAANQAECgUIBQABNQAECgUIBQAIAAAAAA==.Riker:BAAANQADCgQIBAABNQAECgEIAQAIAAAAAA==.Rim:BAABNQAECn8vAAINAAkKch4cFgCWAgANAAkKch4cFgCWAgAAAA==.',
Ro='Ronfar:BAACNQAFFH8QAAIYAAUKSBh4AgCoAQAYAAUKSBh4AgCoAQA1AAQKf1IAAxgACgqDH9cCAHgDABgACgqDH9cCAHgDAA4ACApNFb8mAM4BAAAA.Rootx:BAAANQAECgMIAwABNQAFFAcIJQAPADQjAA==.',
Ru='Rukidingme:BAAANQAECgQIBAAAAA==.Rustyglass:BAAANQABCgYIBAAAAA==.Ruttisðir:BAAANQAECgIIAwAAAA==.',
Ry='Ryhorn:BAAANQADCggIDgAAAA==.Ryno:BAAANQADCgUIBwAAAA==.Ryujin:BAABNQAECn8aAAIaAAoK7QkvyQCJAQAaAAoK7QkvyQCJAQAAAA==.Ryù:BAAANQAECgQICgAAAA==.',
Sa='Salo:BAAANQADCgMIBgAAAA==.Salòme:BAAANQADCgYIDAABNQAECgkJGwAcAGoJAA==.Sanazenet:BAAANQADCggJDAAAAA==.Saphiriel:BAAANQAECgMIBQAAAA==.Saviorself:BAAANQADCgMIAwABNQAFFAcIEwAPAHwRAA==.',
Sc='Scarscar:BAAANQAECggIDAAAAA==.Schwinn:BAAANQADCgQIBAAAAA==.',
Se='Segarth:BAABNQAECn8cAAMOAAoKbBScWwAPAgAOAAoKbBScWwAPAgANAAQKkRB8xADfAAAAAA==.Selen:BAAANQAECgcIEQAAAA==.Semballin:BAAANQABCgMIBQAAAA==.Seråphiel:BAAANQAECgIIAQAAAA==.Seswatha:BAAANQAECgUIBQABNQAFFAUIEAANACgMAA==.',
Sh='Shamandroo:BAABNQAECn8YAAINAAkK0Bo7JwDHAgANAAkK0Bo7JwDHAgABNQAFFAcIFAALAOMXAA==.Shamdi:BAAANQADCgYIBgAAAA==.Shanghaied:BAAANQADCgcIDAAAAA==.Shawtyy:BAAANQADCgMIAwAAAA==.Shmongus:BAAANQADCgIIAgABNQAECgcIDgAIAAAAAA==.Shortandold:BAABNQAECn8WAAMRAAgKMgctWgDzAAARAAgKMgctWgDzAAAQAAEKagOJWwAzAAAAAA==.Shådowfire:BAAANQAECgEIAQAAAA==.Shìft:BAABNQAECn8mAAIeAAgKzx2ZEwCvAgAeAAgKzx2ZEwCvAgAAAA==.',
Si='Sightofhand:BAAANQADCgQIBAAAAA==.Sintram:BAAANQAECgMIAwAAAA==.',
Sl='Slighted:BAAANQAECgMIBgABNQAECgkJFQASAP0IAA==.Slimydruid:BAAANQAECgYIBgAAAA==.Slow:BAABNQAECn8sAAIFAAkKxCPCHABkAwAFAAkKxCPCHABkAwAAAA==.',
Sm='Smokinontech:BAAANQADCgQIBAABNQAECgoKNAAFAEQdAA==.Smokze:BAAANQADCggJCAAAAA==.',
So='Sockoh:BAABNQAECn8XAAQFAAgK5A9TvwAGAgAFAAgKtw5TvwAGAgAGAAIK2xXrLwCBAAAlAAEKmwb2DQAzAAAAAA==.Sonicberger:BAAANQAECgUICAABNQAECgkJKQAMAHIcAA==.Sonicbergger:BAAANQADCgQIBAABNQAECgkJKQAMAHIcAA==.Sonicoberg:BAAANQAECgUICgABNQAECgkJKQAMAHIcAA==.Soniko:BAABNQAECn8VAAISAAkK/QgeHgBkAQASAAkK/QgeHgBkAQAAAA==.Sonícberger:BAABNQAECn8pAAMMAAkKchxyIgCiAgAMAAkKchxyIgCiAgAUAAMKTBcJvAB0AAAAAA==.Soulcaliber:BAAANQAECgEIAQAAAA==.Sovious:BAAANQADCgUIBQAAAA==.',
Sq='Squizzy:BAAANQAECgIIAgAAAA==.',
St='Stain:BAAANQAECgUICAAAAA==.Stealth:BAAANQAECgQIBAABNQAECggIJAAmACUbAA==.Stinkfist:BAAANQADCggIHQAAAA==.Stonehenge:BAABNQAECn8eAAINAAoKbhtCHgBRAgANAAoKbhtCHgBRAgABNQAECgoKNQAKAPkdAA==.Stonepalm:BAAANQADCgcIKQAAAA==.Stratan:BAAANQAECgMIAgAAAA==.Strawk:BAABNQAECn8fAAIOAAcKLg6PgACjAQAOAAcKLg6PgACjAQAAAA==.Stürm:BAAANQAECgMIAwABNQAECgoKMQAgAGgaAA==.',
Su='Subbzero:BAAANQADCgEIAQAAAA==.Suffer:BAAANQADCggICQABNQAECgkJLAAFAMQjAA==.Sunlight:BAAANQAECgcICQAAAA==.Supercat:BAAANQAECgEIAQAAAA==.Surf:BAAANQAECgYIDgAAAA==.',
Sw='Swankydranky:BAACNQAFFH8TAAQWAAcKzg7uBQAQAQAWAAUKKQbuBQAQAQAhAAUK+AcmCwAFAQAgAAIKVAD8CQAqAAA1AAQKfy8ABBYACgoFF20SAL4BABYACAoQE20SAL4BACEACgrkFDEgACUBACAAAgphBMZIAEYAAAAA.Swankyorcs:BAAANQAECgUIBQABNQAFFAcIEwAWAM4OAA==.Swankypally:BAAANQAECggICwABNQAFFAcIEwAWAM4OAA==.',
Sy='Syesc:BAAANQABCgQJBAAAAA==.Sylandris:BAAANQADCgIIAgAAAA==.Sympathy:BAAANQAFFAEIAgAAAA==.',
['Sá']='Sásukeuchiha:BAAANQAECgQIBAABNQAECgkJGwAcAGoJAA==.',
Ta='Tabbz:BAABNQAECn8mAAIOAAoKyRh5MQC1AgAOAAoKyRh5MQC1AgAAAA==.Tallael:BAABNQAECn85AAIYAAoKfhGGCQAZAgAYAAoKfhGGCQAZAgAAAA==.Tallyhochick:BAABNQAECn8qAAIcAAkKEQ77fQARAgAcAAkKEQ77fQARAgAAAA==.Taman:BAABNQAECn8eAAINAAgKNx1lQABeAgANAAgKNx1lQABeAgAAAA==.Taylerswift:BAAANQAECgEJAQAAAA==.',
Th='Thebestname:BAABNQAECn8YAAIiAAgKEAalMQARAQAiAAgKEAalMQARAQAAAA==.Thebigonion:BAAANQADCggIGgAAAA==.Theexile:BAABNQAECn8oAAMQAAoKghduKwA7AgAQAAkKixZuKwA7AgARAAcKcBe8IQC+AQAAAA==.Theigh:BAAANQAECgEIAQAAAA==.Thonard:BAAANQAECgcIFAABNQAECgoKWgAVAKMkAQ==.',
Ti='Tinydeath:BAABNQAECn8fAAIMAAgKwhUsSgDPAQAMAAgKwhUsSgDPAQABNQAECgkJKgAcAIwcAA==.Tinyfu:BAAANQADCgQIBAAAAA==.Tinytamer:BAABNQAECn8qAAMcAAkKjBzfKQA6AgAcAAkKMxzfKQA6AgAnAAMKRRIbDgDMAAAAAA==.',
Tm='Tmakrist:BAAANQAECgIIBQAAAA==.',
To='Toko:BAACNQAFFH8NAAIcAAYKZBk5CQC1AQAcAAYKZBk5CQC1AQA1AAQKfzgAAhwACgpgJQIDAF0DABwACgpgJQIDAF0DAAAA.Tomblord:BAABNQAECn8bAAMVAAkKgAkoUgBoAQAVAAkKYgkoUgBoAQAMAAYKuAUshQDoAAAAAA==.',
Tr='Trailblazah:BAAANQAECgUICgAAAA==.Treeheals:BAAANQADCggICAAAAA==.Truthes:BAAANQADCgYIBwABNQAECggIJAAmACUbAA==.Truths:BAAANQADCgIJAgABNQAECggIJAAmACUbAA==.Truthsx:BAABNQAECn8kAAMmAAgKJRv6AwCpAgAmAAgKJRv6AwCpAgAEAAUKZw494gAEAQAAAA==.Truthy:BAAANQADCgYICAABNQAECggIJAAmACUbAA==.Truthz:BAAANQADCgYJBgABNQAECggIJAAmACUbAA==.',
Ts='Tsukúne:BAAANQADCgQIBAAAAA==.',
Ty='Tyg:BAAANQADCggIEQAAAA==.Tylaatape:BAABNQAECn8kAAQMAAgKExaRLgA0AQAMAAUKXByRLgA0AQAUAAcK5AWLgAAbAQAVAAcKnw2pQQARAQAAAA==.Tyraell:BAAANQAECggIEQAAAA==.',
['Tõ']='Tõkó:BAAANQADCgUIBQABNQAFFAYIDQAcAGQZAA==.',
Um='Umbrae:BAAANQADCgMIAQAAAA==.Umfray:BAAANQAECgIIAwABNQAECgYIEAAIAAAAAA==.',
Us='Usgasdanelv:BAACNQAFFH8FAAIYAAIKWw3IAwCbAAAYAAIKWw3IAwCbAAA1AAQKfyEAAxgACgoVG84MAKECABgACQrkGc4MAKECAA0AAQq4A8LSACoAAAAA.',
Uz='Uzala:BAABNQAECn8aAAIEAAYKZQkMlQDFAAAEAAYKZQkMlQDFAAAAAA==.',
Va='Vanleiden:BAAANQADCgEIAQAAAA==.Vazro:BAABNQAECn83AAMLAAoKbRg5LAD5AQALAAoKbRg5LAD5AQAaAAYKLQZiFAH9AAAAAA==.',
Ve='Vendiyre:BAAANQAECggICAAAAA==.Venthyl:BAACNQAFFH8JAAIPAAYKxh8vDQCYAQAPAAYKxh8vDQCYAQA1AAQKfzIAAw8ACgqbJFkDADsDAA8ACgqbJFkDADsDABkAAgoQJC4lAGMAAAAA.Veyra:BAAANQABCgMIAwAAAA==.',
Vi='Vindictina:BAAANQABCgMIAwAAAA==.Vizan:BAAANQABCgcIBwABNQAECggIJAAmACUbAA==.',
Wa='Warzone:BAAANQADCgUIBQAAAA==.',
We='Wellby:BAAANQAECgQIAwAAAA==.Westerin:BAABNQAECn8lAAIXAAkK/Q/WDwAAAgAXAAkK/Q/WDwAAAgAAAA==.',
Wi='Wildnature:BAAANQADCggIDgAAAA==.Wildwest:BAAANQADCgcIBwAAAA==.Wimateeka:BAABNQAECn8sAAQkAAkKTxniHQD6AQAkAAYK3B3iHQD6AQAaAAgKWhXhlgD2AQALAAMKtAojuQBHAAAAAA==.Windfury:BAAANQAECgYICAABNQAECgkJLAAFAMQjAA==.Windigo:BAAANQAECgIIAgAAAA==.Winginit:BAAANQAECgEIAQABNQAFFAcIEwAPAHwRAA==.',
Wo='Wooqles:BAAANQADCgUIBQABNQADCgYICAAIAAAAAA==.',
Wr='Wrastelas:BAAANQADCggICAAAAA==.',
Wu='Wuilhem:BAAANQADCgEIAQAAAA==.Wurkim:BAAANQADCgQIBAABNQADCggICAAIAAAAAA==.',
Xa='Xaala:BAAANQAECgQIBQAAAA==.',
Xo='Xosderdk:BAAANQADCgIIAgAAAA==.',
Ya='Yarjuul:BAAANQAECgIIAgABNQAECgYIEAAIAAAAAA==.',
Ye='Yespaladin:BAACNQAFFH8QAAIMAAUK4hRCDgBvAQAMAAUK4hRCDgBvAQA1AAQKfzoAAgwACgqNIBIPADYDAAwACgqNIBIPADYDAAAA.',
Yi='Yimity:BAAANQAECgMIAwAAAA==.',
Yo='Yogí:BAACNQAFFH8SAAINAAcK0RMcDQB7AQANAAcK0RMcDQB7AQA1AAQKfzsAAg0ACgohIQoDAMADAA0ACgohIQoDAMADAAAA.Yozomoto:BAACNQAFFH8TAAIcAAcKLSAtCADJAQAcAAcKLSAtCADJAQA1AAQKfzkAAxwACgofJf0IAA8DABwACgofJf0IAA8DABsAAgo8D3B2AGMAAAAA.',
Za='Zalandria:BAABNQAECn8dAAISAAgKmxOuDgBLAQASAAgKmxOuDgBLAQAAAA==.Zarelasong:BAAANQADCgIIAgAAAA==.',
Ze='Zeltemis:BAABNQAECn8XAAIcAAgKpQicjwDqAQAcAAgKpQicjwDqAQAAAA==.Zeno:BAAANQADCgUIBQAAAA==.',
Zi='Zipsion:BAABNQAECn85AAIcAAoKNiI5GAA5AwAcAAoKNiI5GAA5AwAAAA==.Zivver:BAABNQAECn8rAAMSAAoKpCL4AgB6AwASAAoKpCL4AgB6AwAKAAIKlgq6yQB6AAAAAA==.Zizka:BAABNQAECn8dAAIdAAgK4wVROQBcAQAdAAgK4wVROQBcAQAAAA==.',
Zo='Zolandir:BAAANQAECgMIBgAAAA==.',
Zu='Zuljia:BAAANQAECgIIAgABNQAECgcIKAAeAAYdAA==.',
['Òh']='Òhká:BAAANQAECgUIBQAAAA==.',
['Üt']='Üther:BAABNQAECn85AAIaAAoKGCTXEACGAwAaAAoKGCTXEACGAwAAAA==.',
['ßu']='ßubbleøseven:BAABNQAECn8bAAMaAAkKbh4PMQA3AgAaAAkKbh4PMQA3AgAkAAMK0BKwKwCwAAAAAA==.',
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
