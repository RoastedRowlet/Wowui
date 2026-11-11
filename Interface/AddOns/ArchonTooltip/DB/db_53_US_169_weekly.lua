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

local lookup = {'DemonHunter-Vengeance','DemonHunter-Havoc','DemonHunter-Devourer','Warlock-Demonology','Mage-Arcane','Mage-Frost','Priest-Holy','Evoker-Preservation','Warrior-Arms','Paladin-Holy','Paladin-Retribution','DeathKnight-Blood','Shaman-Restoration','Shaman-Elemental','Druid-Balance','Unknown-Unknown','Evoker-Devastation','Rogue-Assassination','Rogue-Subtlety','Warrior-Protection','Warrior-Fury','DeathKnight-Unholy','DeathKnight-Frost','Monk-Brewmaster','Warlock-Destruction','Shaman-Enhancement','Warlock-Affliction','Druid-Feral','Hunter-BeastMastery','Hunter-Marksmanship','Priest-Shadow','Druid-Restoration','Priest-Discipline','Monk-Mistweaver','Monk-Windwalker','Druid-Guardian','Paladin-Protection','Mage-Fire','Hunter-Survival',}
local provider = {region='US',realm='Nordrassil',name='US',type='weekly',zone=53,date='2026-11-10',data={Aa='Aairidari:BAABNQAECn85AAQBAAkKiAjEGwD+AAACAAgK2QbTVAA8AQABAAcKYQnEGwD+AAADAAIKVATATwA/AAAAAA==.',
Ab='Abruna:BAABNQAECn8WAAIEAAgK/BPXbwAQAgAEAAgK/BPXbwAQAgABNQAFFAcIFAAFAGcUAA==.Abruno:BAACNQAFFH8UAAMFAAcKZxRRHACbAQAFAAYKCRJRHACbAQAGAAEK4B2LDABXAAA1AAQKfzsAAwUACgr4IgJBAAMDAAUACgqBIQJBAAMDAAYAAQqPIXcxAFgAAAAA.Abruto:BAAANQAECgYIDgABNQAFFAcIFAAFAGcUAA==.',
Ae='Aeown:BAAANQAECgMIBgABNQAECgoKVgAHAO0XAA==.',
Ah='Aharuka:BAAANQADCgEIAQAAAA==.',
Ak='Akukho:BAAANQADCgIIAgAAAA==.',
Al='Alandrìas:BAABNQAECn9FAAMBAAoKUBD3CgCRAQABAAoKUBD3CgCRAQACAAEKAACGlAAAAAAAAA==.Alkasia:BAAANQAECgEIAQAAAA==.Almostxtinct:BAAANQAECgEIAQAAAA==.Altera:BAABNQAECn8oAAIIAAoKCg/0IADKAQAIAAoKCg/0IADKAQAAAA==.',
Am='Amuri:BAAANQAECgUIBwAAAA==.',
An='Andelarenn:BAAANQABCgIIAgAAAA==.Andere:BAAANQAECgYICQAAAA==.Androo:BAABNQAECn8fAAIJAAoK9A/ZZwCzAQAJAAoK9A/ZZwCzAQABNQAFFAcIFAAKAOMXAA==.Androonatorz:BAACNQAFFH8UAAIKAAcK4xd6CgC1AQAKAAcK4xd6CgC1AQA1AAQKfzQAAwoACgrqIZcbAAcDAAoACgrqIZcbAAcDAAsACgp1EFtsAOQBAAAA.Anfernay:BAABNQAECn8nAAIJAAoKbxG+egAoAgAJAAoKbxG+egAoAgAAAA==.Antheion:BAAANQAECgYICAABNQAECggINQAMADETAA==.Antiaxxis:BAAANQADCgEIAQAAAA==.',
Ap='Apawthetic:BAABNQAECn8bAAMNAAkKRiEqFQD7AgANAAkKRiEqFQD7AgAOAAQKiAZ48wCuAAABNQAFFAcIEwAPAHwRAA==.',
Aq='Aquadab:BAAANQADCgQICAAAAA==.',
Ar='Arashatora:BAAANQAECgEIAQABNQAECgMIBAAQAAAAAA==.Arcanodare:BAAANQADCggICAAAAA==.Arkalis:BAAANQAECgEIAgAAAA==.Arveiturace:BAABNQAECn8XAAIRAAUK+gOXGgCJAAARAAUK+gOXGgCJAAAAAA==.',
As='Ashborrn:BAAANQADCgUIBQAAAA==.Ashtar:BAABNQAECn8pAAIJAAkKrxA2jwD2AQAJAAkKrxA2jwD2AQAAAA==.Asukajo:BAAANQADCgMIAwAAAA==.',
At='Attack:BAAANQAECgcIEAAAAA==.',
Ax='Axhure:BAAANQABCgMIAgAAAA==.',
Ba='Babydoll:BAAANQAECgQICAAAAA==.Bajablast:BAAANQADCgcIDQAAAA==.Barma:BAAANQAECgYICwAAAA==.Barrin:BAABNQAECn8eAAIFAAoKuhzOKwCEAgAFAAoKuhzOKwCEAgAAAA==.',
Be='Bearlyseen:BAABNQAECn8rAAISAAkKSx/xBADJAgASAAkKSx/xBADJAgABNQAFFAUIEQANACgMAA==.Beltirra:BAAANQAECgMIBwAAAA==.',
Bh='Bhangbros:BAAANQADCgcIBwAAAA==.',
Bi='Biggums:BAAANQAECgMIBgAAAA==.Bigmobility:BAABNQAECn81AAIMAAoKeyIKCAB8AwAMAAoKeyIKCAB8AwAAAA==.Bigwill:BAABNQAECn9bAAIGAAoKkCHnAgAsAwAGAAoKkCHnAgAsAwAAAA==.',
Bl='Blargy:BAABNQAECn9EAAIPAAoKsBnKGwAUAgAPAAoKsBnKGwAUAgAAAA==.Bleach:BAABNQAECn8aAAMSAAgKIwk+NAC1AAATAAYKlQpDjwDWAAASAAYK/AY+NAC1AAAAAA==.Bluewaffles:BAAANQADCgQIBQABNQAECgMIAwAQAAAAAA==.',
Bo='Borealslam:BAAANQADCgQIBAAAAA==.Bouzol:BAAANQAECgYIBwAAAA==.',
Br='Brighterbonk:BAAANQAECgMIBwAAAA==.Brimara:BAAANQAECgUIDwAAAA==.Brothaagamor:BAAANQAECgEIAgAAAA==.Brunomirror:BAAANQAECgUIBQABNQAFFAcIFAAFAGcUAA==.',
Bu='Bucketojoy:BAABNQAECn8gAAIFAAoKNAP3zgD6AAAFAAoKNAP3zgD6AAAAAA==.Bunsen:BAAANQAECgQIBAABNQAECgoKKQANAHEcAA==.',
['Bà']='Bàtman:BAAANQAECgQICAABNQAECgUIDwAQAAAAAA==.',
['Bö']='Böop:BAAANQADCgYIBgABNQAECgUIDwAQAAAAAA==.',
Ca='Caliburne:BAABNQAECn89AAQJAAoKuh4qJwCYAgAJAAoKHx4qJwCYAgAUAAUKhh+5FgC/AQAVAAMK6h4xGQAPAQAAAA==.Captamerica:BAAANQABCgQIBgAAAA==.Capz:BAACNQAFFH8YAAIJAAgKTxvCBACHAgAJAAgKTxvCBACHAgA1AAQKfyUAAgkACgqaJe8fADgDAAkACgqaJe8fADgDAAAA.',
Ce='Ceez:BAABNQAECn8kAAMJAAkKDBN4fwBzAQAJAAkKjw14fwBzAQAUAAQKFBugIADfAAAAAA==.Ceezinator:BAAANQAECgMIAwAAAA==.',
Ch='Chichujongar:BAABNQAECn8UAAQMAAcKwwsFbwA5AQAMAAcKcwsFbwA5AQAWAAYKwwUziwD3AAAXAAYKmgVlbADUAAABNQAFFAcIEwAYAM4OAA==.Chickenstwip:BAAANQADCgEIAgABNQAECgoKOwAFALQdAA==.Chipotle:BAAANQAECgYIAgAAAA==.Chopperr:BAAANQAECgUICAABNQAECgoKOwAFALQdAA==.Chosenöne:BAAANQADCgEIAQAAAA==.Chèn:BAAANQAECgcIEgAAAA==.',
Ci='Cindrella:BAABNQAECn86AAIGAAoKXCSXAADDAwAGAAoKXCSXAADDAwAAAA==.',
Cl='Clayre:BAACNQAFFH8aAAIZAAYKFRmMAACgAQAZAAYKFRmMAACgAQA1AAQKf2MAAhkACgoNJUsAAF8DABkACgoNJUsAAF8DAAAA.Clow:BAABNQAECn8UAAMJAAYKdCHShgBiAQAJAAYKzR/ShgBiAQAVAAEKAR+dKwBXAAAAAA==.',
Co='Colossus:BAAANQAECgIIBAAAAA==.Coolcrush:BAAANQADCgUICAABNQAFFAQIBQAaANkYAA==.Corven:BAACNQAFFH8TAAIEAAcKshQcDwCLAQAEAAcKshQcDwCLAQA1AAQKf1YABAQACgpcI64LAG8DAAQACgpcI64LAG8DABsAAQpJF/snAEEAABkAAQpFBbiEACUAAAAA.',
Cr='Craziks:BAAANQADCgIIAgAAAA==.Critzwar:BAACNQAFFH8RAAIJAAcKphPsEACtAQAJAAcKphPsEACtAQA1AAQKfyQAAgkACgqZIWQxAPoCAAkACgqZIWQxAPoCAAAA.Crönus:BAAANQAECgIIAgAAAA==.',
Ct='Cthuluwu:BAAANQADCggICAAAAA==.',
Da='Daedyxes:BAABNQAECn80AAIMAAoKvxD1JgC3AQAMAAoKvxD1JgC3AQAAAA==.Danrod:BAAANQAECgIIAgAAAA==.Daní:BAAANQADCgUIBwABNQAECgEIAQAQAAAAAA==.Darfur:BAABNQAECn8nAAIFAAoKhxohLACDAgAFAAoKhxohLACDAgAAAA==.Darkensi:BAAANQABCgYICQAAAA==.Dasherdeez:BAAANQAECgEIAQAAAA==.Daygath:BAAANQAECgEJAQAAAA==.',
De='Deadlyiris:BAABNQAECn83AAIJAAoKNR/UMABuAgAJAAoKNR/UMABuAgABNQAECgoKKQANAHEcAA==.Deadshot:BAAANQAECgQIDAAAAA==.Deatharin:BAAANQADCgUIBgAAAA==.Deathjak:BAAANQAECgcIDwABNQAECgoKOAAFAKkjAA==.Decompose:BAAANQADCgQIBAAAAA==.Demonbulio:BAABNQAECn8bAAICAAgKcQdNSgB7AQACAAgKcQdNSgB7AQAAAA==.Demonisthicc:BAABNQAECn85AAIcAAoKDB6cBgABAwAcAAoKDB6cBgABAwAAAA==.Demonskitten:BAAANQADCgUIBQABNQAECgoKOQAcAAweAA==.Demonslayeer:BAAANQADCggIDQAAAA==.Demoronicon:BAAANQAFFAEIAQAAAA==.Devi:BAAANQAECgYIDgAAAA==.',
Di='Diaravynn:BAAANQADCgMIBQAAAA==.Diddylord:BAAANQAECgMIBAABNQAECgoKOwAFALQdAA==.Dithehealer:BAABNQAECn8uAAILAAoKmhYVkgAAAgALAAoKmhYVkgAAAgAAAA==.Divain:BAAANQAECgEIAQAAAA==.',
Dk='Dkdi:BAAANQAECgYIDAAAAA==.',
Do='Dozekar:BAAANQAECgEIAQAAAA==.',
Dr='Drenamai:BAABNQAECn8XAAIdAAgKcxBBiwCEAQAdAAgKcxBBiwCEAQAAAA==.Drexywexyuwu:BAAANQADCgcJBwAAAA==.',
Du='Duhmptruhk:BAABNQAECn83AAMJAAoKFxlNRgAeAgAJAAoKrxhNRgAeAgAUAAIKtRKmLwB1AAAAAA==.Dunbroch:BAACNQAFFH8SAAIeAAYKZhq8BwDPAQAeAAYKZhq8BwDPAQA1AAQKfzUAAh4ACgolHncVALICAB4ACgolHncVALICAAAA.Duskfire:BAAANQADCgQIBAAAAA==.Duskforge:BAAANQAECgEIAgAAAA==.',
Dw='Dwagen:BAAANQAECgQIBQAAAA==.',
['Dé']='Démonicblood:BAACNQAFFH8SAAIXAAYKJB/GBgCSAQAXAAYKJB/GBgCSAQA1AAQKfzkAAhcACgp/IWcLAPcCABcACgp/IWcLAPcCAAAA.',
Eg='Eggplantgodx:BAABNQAECn82AAMBAAoKSSVzAgDsAgABAAkKSSVzAgDsAgACAAgKKRlqLwArAgAAAA==.',
Ek='Ekhart:BAAANQAECgEIBAAAAA==.',
El='Elfajah:BAAANQADCgYICQAAAA==.Eliicia:BAACNQAFFH8SAAMSAAcKrwyBCACGAQASAAYKYg6BCACGAQATAAEK5AURIwBRAAA1AAQKfy4AAxIACgpbILQYALcCABIACgpbILQYALcCABMACQpeDIAyACgBAAAA.Elvwyr:BAAANQAECgEIAQAAAA==.',
Em='Emmy:BAAANQAECgQIEAAAAA==.Emofineshyt:BAAANQADCgcICgAAAA==.Emogothbabe:BAABNQAECn87AAMFAAoKtB1IOgBSAgAFAAoKtB1IOgBSAgAGAAMK8w5RLACZAAAAAA==.Emowrecky:BAABNQAECn8lAAMEAAgKbx0GYwAwAgAEAAgKbx0GYwAwAgAZAAEKjA5RMwA7AAAAAA==.',
En='Endo:BAACNQAFFH8QAAMWAAcKIRuuCgBlAQAWAAUKGh6uCgBlAQAXAAQKBhYtEQDMAAA1AAQKf0EAAxYACgoLJU0SACUDABYACQooJU0SACUDABcACAoEIiItADYCAAAA.Endorush:BAABNQAECn83AAMCAAoKfiBBFQBhAgACAAoKJiBBFQBhAgADAAcK5Rz9HACqAQABNQAFFAcIEAAWACEbAA==.Endrigosa:BAAANQAECgUIBgAAAA==.Eneldenes:BAAANQAECgUICwAAAA==.Enjoyer:BAAANQAECgcIEAAAAA==.',
Er='Ereitherla:BAABNQAECn8xAAIdAAgKmAmPowBQAQAdAAgKmAmPowBQAQAAAA==.Erodrine:BAAANQABCgMIBAAAAA==.',
Es='Esmenet:BAAANQAECgYIEAAAAA==.Espressð:BAABNQAECn83AAIHAAoKmCGyCACcAwAHAAoKmCGyCACcAwABNQAECgoKOwAFALQdAA==.',
Ex='Excalibear:BAABNQAECn8fAAIKAAoKYBuTIQCjAgAKAAoKYBuTIQCjAgABNQAFFAUIEQANACgMAA==.',
Ey='Eydis:BAAANQADCgcIDgAAAA==.Eyepisspeas:BAAANQABCgMIBAAAAA==.',
Fe='Feironor:BAAANQAECgUIBwAAAA==.Fenrys:BAAANQAECgQIBAAAAA==.',
Fi='Fikareous:BAAANQADCggIDQABNQAECgUIBQAQAAAAAA==.',
Fl='Flayre:BAABNQAECn8oAAMNAAkK3RtQRQBMAgANAAgK3BtQRQBMAgAOAAcKMBcNaADoAQAAAA==.Fleredil:BAABNQAECn9DAAMfAAoKECIYBwDvAgAfAAoKECIYBwDvAgAHAAEKgQXG/gAuAAAAAA==.Flingernle:BAABNQAECn8yAAIOAAoKeSP6BwA1AwAOAAoKeSP6BwA1AwAAAA==.',
Fo='Forepray:BAACNQAFFH8QAAIfAAUKVA2NCwAzAQAfAAUKVA2NCwAzAQA1AAQKf0EAAh8ACgpWIKUJAEUDAB8ACgpWIKUJAEUDAAAA.Forger:BAABNQAECn8sAAMUAAkKDAwtGwCGAQAUAAkKDAwtGwCGAQAJAAIKQQjVOQFhAAAAAA==.Forsakey:BAAANQADCggIFAABNQAFFAcIDgAgAGIWAA==.',
Fr='Fraun:BAAANQADCggJEQAAAA==.Freshdk:BAAANQAECgQIBAAAAA==.',
Fu='Fullyprotpal:BAAANQAECgEIBAAAAA==.Funbagz:BAAANQAECgIIAgAAAA==.Furioustotem:BAABNQAECn8yAAIOAAgKcBfNVQBvAQAOAAgKcBfNVQBvAQAAAA==.Future:BAAANQADCgUIBgABNQAECgkJLAAFAMQjAA==.',
Fy='Fycat:BAAANQAECggICgABNQAFFAQIDAAEANkfAA==.',
Ga='Galten:BAAANQADCgUIBQAAAA==.Gantz:BAAANQADCgIJAgAAAA==.',
Ge='Geekbarr:BAAANQADCgUIBQABNQAECgoKOwAFALQdAA==.',
Gh='Ghettox:BAAANQADCgYIDAAAAA==.Ghostw:BAABNQAECn8WAAIJAAYKux1JhgBjAQAJAAYKux1JhgBjAQAAAA==.',
Gi='Giovanni:BAAANQAECggICQAAAA==.Gizik:BAAANQADCgcIDQABNQAFFAgIGQAfALoQAA==.',
Gn='Gnasher:BAAANQAECgEIAQAAAA==.',
Go='Golgotterath:BAACNQAFFH8RAAINAAUKKAwODwBeAQANAAUKKAwODwBeAQA1AAQKfzoAAw0ACgrKH/MnAHcCAA0ACgrKH/MnAHcCAA4AAQqNB/I6ATAAAAAA.Goreshade:BAAANQAECgIIAgAAAA==.Gorm:BAABNQAECn8wAAIFAAoKnBywVgDTAgAFAAoKnBywVgDTAgABNQAECgQIBQAQAAAAAA==.',
Gr='Grippyshocks:BAAANQAECgIIAQABNQAECgoKKQACAGIgAA==.',
Ha='Halbruck:BAABNQAECn8XAAMNAAgKbB0VQQBcAgANAAgKbB0VQQBcAgAOAAQKIQ691ADrAAAAAA==.Haldane:BAABNQAECn8zAAILAAkKRAoevQBCAQALAAkKRAoevQBCAQABNQAECgoKKQANAHEcAA==.Harrydottur:BAAANQAECggIDwABNQAFFAUIEQAEAAYcAA==.Havochunter:BAABNQAECn8XAAIdAAkKJhWlZgDeAQAdAAkKJhWlZgDeAQAAAA==.Hawley:BAAANQABCgIIAgAAAA==.',
He='Heidegger:BAAANQADCgYICgAAAA==.Heihei:BAAANQAECgMIAQAAAA==.Helinndealin:BAACNQAFFH8UAAIhAAcKwhpnAACxAQAhAAcKwhpnAACxAQA1AAQKfy0AAyEACgrEJFQBAEcDACEACQryJFQBAEcDAAcACAotIsZJAEgCAAAA.Hellin:BAAANQADCgMIAQAAAA==.Hempie:BAAANQAECgEIAQAAAA==.Heolstor:BAABNQAECn89AAIMAAoKBR56EgB2AgAMAAoKBR56EgB2AgAAAA==.Hephsdh:BAAANQAECggIEAAAAA==.Heraois:BAABNQAECn8iAAIeAAoKtgmsNgCZAQAeAAoKtgmsNgCZAQAAAA==.Heriod:BAAANQAECgEIAwAAAA==.',
Hg='Hgshake:BAAANQADCgYIBgAAAA==.',
Ho='Holytës:BAAANQAECgYIDAAAAA==.Holywráth:BAAANQAECgQICQAAAA==.',
Hu='Hunterdh:BAABNQAECn8zAAIdAAkKzgfBiACKAQAdAAkKzgfBiACKAQAAAA==.',
Hy='Hynixx:BAABNQAECn8vAAMVAAoKqxsdCQBKAgAVAAkKphodCQBKAgAJAAcKjRh8eACFAQABNQAFFAUIEAAfAFQNAA==.',
Il='Illidope:BAABNQAECn8pAAQCAAoKYiDcFQDuAgACAAoKSyDcFQDuAgADAAgK+xwZIwAxAgABAAEKAACILgBGAAAAAA==.',
In='Infinitevoid:BAAANQADCggIFQAAAA==.Infliximab:BAAANQAECggIEAAAAA==.Innervatez:BAABNQAFFH8LAAIgAAUKJCMuBADuAQAgAAUKJCMuBADuAQAAAA==.Inteaus:BAAANQADCggIGgAAAA==.',
Io='Ionúin:BAAANQADCgQJBAAAAA==.',
Iv='Ivÿ:BAAANQADCgMIBQABNQAECgUIDwAQAAAAAA==.',
Ja='Jabkhan:BAABNQAECn8VAAIPAAYKwwEzdwBPAAAPAAYKwwEzdwBPAAAAAA==.Jaekir:BAABNQAECn8oAAIGAAoK6xORCwAHAgAGAAoK6xORCwAHAgAAAA==.Jakfrost:BAABNQAECn84AAMFAAoKqSOfOgBRAgAFAAkK6iOfOgBRAgAGAAMKKiLkGgAcAQAAAA==.Jakie:BAAANQADCgYICgABNQAECggIFwAJAN8aAA==.Jarten:BAACNQAFFH8RAAIXAAcKOxiWBQB/AQAXAAcKOxiWBQB/AQA1AAQKf0kAAhcACgp/IcsNANwCABcACgp/IcsNANwCAAAA.Jayaah:BAAANQAECgMIBwAAAA==.Jaylebate:BAABNQAECn8aAAMWAAgKrxkvJACqAQAWAAgK9xcvJACqAQAMAAYKbxpcXACBAQAAAA==.',
Je='Jerrenn:BAAANQAECgQIBgAAAA==.Jesseatamer:BAACNQAFFH8RAAIdAAcKRiGmAgDQAQAdAAcKRiGmAgDQAQA1AAQKf0kAAh0ACgqvJawEAGYDAB0ACgqvJawEAGYDAAAA.',
Ji='Jigme:BAAANQAECgMIAwAAAA==.Jitsuru:BAAANQADCgUIBQAAAA==.',
Jo='Jox:BAAANQABCgUIBQAAAA==.Joxor:BAAANQABCgUIBQAAAA==.',
Js='Jstdeath:BAAANQADCgEIAQABNQAECgoKNQAJAHEVAA==.Jstrawr:BAABNQAECn81AAIJAAoKcRVvYgBnAgAJAAoKcRVvYgBnAgAAAA==.Jsttotem:BAAANQAECgUIBgABNQAECgoKNQAJAHEVAA==.',
Ju='Julberry:BAAANQAECgEIAQAAAA==.Julri:BAAANQAECgEIAQAAAA==.',
Ka='Kalmek:BAABNQAECn8VAAMWAAkKLw0cLwBeAQAWAAkKkAwcLwBeAQAXAAIKMQZ1sAAuAAAAAA==.Kaln:BAAANQAECgIIBwABNQAECgQIBQAQAAAAAA==.Karen:BAAANQAECgUIDgAAAA==.Kasalu:BAAANQABCgQIBAAAAA==.Kasanzzar:BAAANQAECgYIBwAAAA==.Kastia:BAAANQAECgQICwAAAA==.Kasumï:BAAANQAECgEIAgABNQAFFAYIEgAdAD4gAA==.Katrynwel:BAAANQAECgQIBQAAAA==.Katsumi:BAAANQAECgQICgAAAA==.',
Ke='Keliki:BAABNQAECn88AAMNAAoKOB6XEQAcAwANAAoKOB6XEQAcAwAOAAgKzhigQQBvAgAAAA==.Kellenah:BAAANQAECgMIBQAAAA==.Kettama:BAAANQAECgUIBQABNQAECgoKOwAFALQdAA==.',
Kh='Khold:BAABNQAECn8xAAMXAAoKDRstJgARAgAXAAoKDRstJgARAgAMAAQKBw5obQCOAAAAAA==.Khrogann:BAAANQAECggIEgAAAA==.',
Ki='Kijana:BAAANQADCggICAAAAA==.Killalltoday:BAABNQAECn8pAAINAAgKWRJ9aQDQAQANAAgKWRJ9aQDQAQAAAA==.Killersmile:BAAANQADCgQIBAAAAA==.Kirkk:BAAANQAECgMIBAAAAA==.',
Kl='Klaminus:BAAANQADCgQIBAABNQAECgMIBAAQAAAAAA==.',
Kn='Knixx:BAACNQAFFH8UAAIHAAcKIBEIEACUAQAHAAcKIBEIEACUAQA1AAQKf1gAAwcACgrvJesAAOQDAAcACgrvJesAAOQDACEABgrzEYsPADIBAAAA.Knuppelus:BAAANQADCgYIDAAAAA==.',
Ko='Kobyashimaru:BAAANQADCgUIBQAAAA==.Koshi:BAAANQADCgMIAwAAAA==.Kotastrophe:BAAANQAECgMIBAABNQAECgoKNwAJABcZAA==.Kotastrophic:BAAANQAECgUIBQAAAA==.Koveras:BAAANQADCgYIBwAAAA==.Koyaanis:BAAANQAECgEIAwAAAA==.Koyya:BAABNQAECn8xAAMaAAoKnA03FAAlAgAaAAkK5Ao3FAAlAgANAAoK4RLuUQCzAQAAAA==.',
Kr='Krathos:BAAANQAECgUIDAAAAA==.Krenmonk:BAAANQAECgEIAgAAAA==.Krennic:BAAANQADCgcIBwAAAA==.Krunchee:BAAANQAECgQICQAAAA==.',
Ku='Kufoo:BAABNQAECn88AAMVAAoKbyXLAABdAwAVAAoKbyXLAABdAwAUAAEKkx6uNwBSAAAAAA==.Kurao:BAAANQAECgMIBQAAAA==.Kurukai:BAAANQADCgMIAwAAAA==.',
Ky='Kyrian:BAACNQAFFH8fAAMTAAcKriBiAQBaAgATAAcKriBiAQBaAgASAAMKvREHEADrAAA1AAQKfzYAAxMACgrcIygFADgDABMACgrcIygFADgDABIAAwpZHHlvAPMAAAAA.',
La='Lagøless:BAABNQAECn8jAAIdAAoKHSMhEwBTAwAdAAoKHSMhEwBTAwAAAA==.',
Le='Leo:BAAANQAECgEIAQAAAA==.',
Li='Liatris:BAAANQAECgUIBgAAAA==.Likestoflash:BAEANQADCgYIBgABNQAECgoKSQAdAIweAA==.Lissaris:BAAANQADCgEIAgAAAA==.',
Lo='Lohal:BAABNQAECn89AAIEAAoKVBn0MQA4AgAEAAoKVBn0MQA4AgAAAA==.Lohmi:BAABNQAECn8aAAIOAAkKzgZAZQA/AQAOAAkKzgZAZQA/AQAAAA==.Lormn:BAAANQADCgEIAQAAAA==.',
Lu='Luania:BAAANQAECgQICwAAAA==.',
Ly='Lyna:BAAANQADCggIDAAAAA==.Lyravega:BAAANQAECggIAQAAAA==.Lyshkä:BAABNQAECn8xAAIiAAoKaBpAEAB7AgAiAAoKaBpAEAB7AgAAAA==.Lyzzardkng:BAABNQAECn80AAILAAoKuwkKnACAAQALAAoKuwkKnACAAQAAAA==.',
['Lý']='Lýra:BAAANQAECgQICQAAAA==.',
Ma='Maango:BAABNQAECn8pAAILAAoKph4sLACkAgALAAoKph4sLACkAgAAAA==.Maemu:BAAANQABCgUIBwAAAA==.Magebulio:BAAANQAECgEIAgAAAA==.Magerthat:BAAANQADCgQIBgAAAA==.Magicaltickl:BAABNQAECn8jAAIFAAoKZg0waADTAQAFAAoKZg0waADTAQAAAA==.Magiki:BAAANQADCgcICwAAAA==.Makyaihua:BAAANQABCggIHAAAAA==.Malkala:BAAANQADCgMIAwAAAA==.Malonormu:BAAANQABCgcIBgAAAA==.Mamadeezy:BAAANQAECgEIAQAAAA==.Mando:BAAANQAECgUIDQABNQAECggIMQAjAA8aAA==.Manical:BAAANQAECgMIDwAAAA==.Marcel:BAAANQADCgYIEQABNQAECgMIBwAQAAAAAA==.Martinikiss:BAAANQAECgcIEAAAAA==.Mashiach:BAACNQAFFH8MAAIHAAYKDBugDADBAQAHAAYKDBugDADBAQA1AAQKfysAAwcACgpTIdgPAEcDAAcACgpTIdgPAEcDAB8AAQoAALx4ADYAAAAA.Matthyjsz:BAAANQADCgIIAgAAAA==.',
Me='Megumin:BAAANQAECgYICwABNQAECgoKOQALABgkAA==.Melikefire:BAABNQAECn8hAAIFAAoKURZXmgBMAgAFAAoKURZXmgBMAgAAAA==.Melodious:BAAANQAECgEIAQAAAA==.Memecompdall:BAAANQAECgIIBQAAAA==.Merek:BAABNQAECn8kAAIYAAgKyB8JBwDSAgAYAAgKyB8JBwDSAgAAAA==.Mettix:BAAANQAECgEIAQAAAA==.',
Mi='Mirigosa:BAAANQAECgEIAQABNQAECgoKOgAGAFwkAA==.Mistybdk:BAABNQAECn81AAIMAAoKTBktFwA+AgAMAAoKTBktFwA+AgABNQAFFAgIGAAkAGgVAA==.Mistyd:BAACNQAFFH8YAAIkAAgKaBWIAABGAgAkAAgKaBWIAABGAgA1AAQKf14AAiQACgqzJWUBAHADACQACgqzJWUBAHADAAAA.',
Mo='Mogfooyen:BAAANQABCgYICQAAAA==.Moonbeam:BAAANQAECgUIBwAAAA==.Morgause:BAABNQAECn8eAAIEAAYKhgcNqADxAAAEAAYKhgcNqADxAAABNQAECgoKHgAPAHwHAA==.Morllan:BAABNQAECn8oAAIEAAoK9w0qggDgAQAEAAoK9w0qggDgAQAAAA==.',
Mu='Muirdin:BAAANQADCgEIAQAAAA==.',
My='Mykinlive:BAAANQADCgIIAgAAAA==.',
['Má']='Mááââybèèëëè:BAAANQADCgEIAQAAAA==.',
['Må']='Mångix:BAAANQAECgQIBQAAAA==.',
['Mé']='Mélusine:BAABNQAECn8ZAAMJAAkKURJ5igABAgAJAAkKpw95igABAgAVAAQKrRB2HQDYAAAAAA==.',
Na='Naanomage:BAAANQAECgYIDwAAAA==.Nagakabouros:BAAANQAECgEIAgAAAA==.Naija:BAAANQADCgIIAgAAAA==.Narcotx:BAAANQADCgIIAgAAAA==.',
Ne='Necrotoxin:BAAANQADCgYIBgAAAA==.',
Ni='Nightmaratic:BAAANQADCgYIBgAAAA==.Nightsdeath:BAAANQAECgEIAQAAAA==.Nightsever:BAABNQAECn8nAAIDAAkKwSJIBwBeAwADAAkKwSJIBwBeAwAAAA==.Nirath:BAABNQAECn8pAAIRAAkKYAWeIABOAQARAAkKYAWeIABOAQAAAA==.',
No='Noiire:BAABNQAECn8bAAIdAAkKpBSfUgARAgAdAAkKpBSfUgARAgABNQAFFAcIEgASAK8MAA==.',
Od='Odysse:BAAANQADCgYICQAAAA==.Odyssé:BAABNQAECn8mAAIdAAoKqR3UIQAQAwAdAAoKqR3UIQAQAwAAAA==.',
Oi='Oio:BAAANQAECggIAgAAAA==.',
Ok='Okami:BAABNQAECn8iAAIjAAYKUR5WIACEAQAjAAYKUR5WIACEAQAAAA==.',
On='Onehotelf:BAAANQAECgQIBQAAAA==.',
Oo='Ooyagoddess:BAAANQAECggIDgAAAA==.',
Or='Orienn:BAAANQAECgQIAgAAAA==.',
Pa='Pacamonk:BAABNQAECn9DAAIjAAoKFB8sDQAIAwAjAAoKFB8sDQAIAwAAAA==.Palenar:BAAANQADCgQIBAAAAA==.Papatiny:BAAANQAECgcIEQAAAA==.Papábear:BAAANQADCgQIBAAAAA==.Pawsa:BAABNQAECn8WAAMYAAgKfhyaDQAgAgAYAAcKnSCaDQAgAgAjAAYKmw0iLQAaAQABNQAECgoKOwAFALQdAA==.Pawthetic:BAACNQAFFH8TAAQPAAcKfBFdEgBEAQAPAAUK5RRdEgBEAQAgAAEKVw6PFABNAAAcAAEK2ANdBABDAAA1AAQKf0gAAyAACgqJIygLAAMDACAACgqJIygLAAMDAA8ACgpfIO0KAOUCAAAA.',
Pe='Peelforheals:BAACNQAFFH8FAAIfAAMKLAcGFACMAAAfAAMKLAcGFACMAAA1AAQKfzMAAx8ACgqkHpwOAAYDAB8ACgqkHpwOAAYDACEABQpdDHsXALoAAAAA.Penguindemic:BAABNQAECn80AAQEAAoKVSWaBgCaAwAEAAoKVSWaBgCaAwAbAAEKRx70IQBZAAAZAAEKoCISagBNAAAAAA==.Pep:BAABNQAECn8UAAIjAAkKhQpJPAAzAQAjAAkKhQpJPAAzAQAAAA==.Pepperoni:BAAANQAECgEIAQAAAA==.Perdator:BAAANQAECgQICAAAAA==.Petruccius:BAACNQAFFH8gAAIPAAUK4BUtDwDtAAAPAAUK4BUtDwDtAAA1AAQKf2wAAg8ACgrbIFEMAGgDAA8ACgrbIFEMAGgDAAAA.Pewpewlepew:BAAANQAECgQICgAAAA==.',
Ph='Phaeku:BAAANQADCgMIAwAAAA==.',
Pi='Picklebreath:BAAANQADCgUICgAAAA==.Pinksparklez:BAAANQADCgUICAABNQAECgEIAQAQAAAAAA==.',
Pl='Plague:BAAANQAECgMIAwAAAA==.',
Po='Ponglenis:BAAANQAECgIIAgAAAA==.Poptartsz:BAAANQAECgQICgAAAA==.Potatolockx:BAAANQAECgQIBQAAAA==.',
Pr='Prayre:BAABNQAECn8hAAMHAAoKPg0iRgAKAgAHAAoKPg0iRgAKAgAfAAUKYAqhNQDQAAAAAA==.Precht:BAAANQAECgMIBwAAAA==.Prikarea:BAAANQAECgUIBQAAAA==.Prospa:BAAANQAECgUICgABNQAECgoKOwAFALQdAA==.Prumper:BAABNQAECn8oAAIFAAoKVhD8ewChAQAFAAoKVhD8ewChAQAAAA==.Príest:BAAANQAECggICwAAAA==.',
Pu='Purah:BAAANQADCgEIAgAAAA==.',
['Pä']='Päncake:BAAANQAECgUIDwAAAA==.',
Qu='Quesoblanco:BAABNQAECn8fAAMLAAoKaQ4gwQA7AQALAAoKbgggwQA7AQAlAAUKKhkxOwAXAQAAAA==.',
Qy='Qybxboogietk:BAABNQAECn8jAAICAAkK8hSDMQAdAgACAAkK8hSDMQAdAgAAAA==.',
Ra='Rabid:BAAANQAECgQIDAAAAA==.Raeliana:BAAANQADCgQIBAAAAA==.Raghallov:BAAANQAECggIEwAAAA==.Rampa:BAAANQADCgYIEQABNQAECgoKOwAFALQdAA==.',
Re='Reaperan:BAAANQAECgEIAQAAAA==.Regena:BAABNQAECn9WAAMHAAoK7Rd3KQCSAgAHAAoK7Rd3KQCSAgAfAAMKOQKLagBYAAAAAA==.Rekriss:BAAANQADCgYIBgAAAA==.Remorse:BAACNQAFFH8SAAIUAAYKZRKNAgBrAQAUAAYKZRKNAgBrAQA1AAQKf0MAAhQACgpeIWYGAAADABQACgpeIWYGAAADAAAA.Rendwick:BAAANQADCgYICQAAAA==.Required:BAABNQAECn8bAAIeAAkKvRPBEQAUAgAeAAkKvRPBEQAUAgABNQAFFAcIFAACAOQhAA==.',
Ri='Rikahoe:BAAANQAECgUIBQABNQAECgUIBQAQAAAAAA==.Riker:BAAANQADCgQIBAABNQAECgMIBAAQAAAAAA==.Rim:BAABNQAECn9BAAINAAoKxh0GGwDLAgANAAoKxh0GGwDLAgAAAA==.',
Ro='Rockandshock:BAAANQAECgUIBAABNQAECgoKKQACAGIgAA==.Ronfar:BAACNQAFFH8SAAIaAAYKohYpAgAdAQAaAAYKohYpAgAdAQA1AAQKf2YAAxoACgpmI9cCAHgDABoACgpmI9cCAHgDAA4ACQr7FXU/AMABAAAA.Rootx:BAAANQAECgMIAwABNQAFFAgIJwAPANciAA==.',
Ru='Rukidingme:BAAANQAECgQIBAAAAA==.Rustyglass:BAAANQAECgEIAQAAAA==.Ruttisðir:BAAANQAECgIIBQAAAA==.',
Ry='Ryhorn:BAAANQADCggIDgAAAA==.Ryno:BAAANQADCgUIBwAAAA==.Ryujin:BAABNQAECn8bAAILAAoK7QkvyQCJAQALAAoK7QkvyQCJAQAAAA==.Ryù:BAAANQAECgQICgAAAA==.',
Sa='Salo:BAAANQADCgMIBgAAAA==.Salòme:BAAANQAECgQIBQABNQAECgoKIAAdAFwKAA==.Sanazenet:BAAANQAECgEIAQAAAA==.Saphiriel:BAAANQAECgMIBwAAAA==.Saviorself:BAAANQADCgMIAwABNQAFFAcIEwAPAHwRAA==.',
Sc='Scalewalker:BAAANQAECgEIAQAAAA==.Scarscar:BAAANQAECggIDgAAAA==.Schwinn:BAAANQADCgQIBAAAAA==.Scracky:BAAANQAECggIDAAAAA==.',
Se='Segarth:BAABNQAECn8kAAMOAAoKmxZILQASAgAOAAoKmxZILQASAgANAAQKkRB8xADfAAAAAA==.Selen:BAABNQAECn8WAAIKAAgKCxbrUQAlAgAKAAgKCxbrUQAlAgAAAA==.Semballin:BAAANQAECgcIEAAAAA==.Seråphiel:BAAANQAECgUIBwAAAA==.Seswatha:BAAANQAECgYICQABNQAFFAUIEQANACgMAA==.',
Sh='Shamandroo:BAABNQAECn8YAAINAAkK0Bo7JwDHAgANAAkK0Bo7JwDHAgABNQAFFAcIFAAKAOMXAA==.Shamdi:BAAANQADCgYIBgAAAA==.Shanghaied:BAAANQADCgcIDAAAAA==.Shawtyy:BAAANQADCgMIAwAAAA==.Shmongus:BAAANQADCgIIAgABNQAECgcIEAAQAAAAAA==.Shortandold:BAABNQAECn8fAAMTAAoKqQsATAC2AQATAAoKqQsATAC2AQASAAEKagMjZQAwAAAAAA==.Shådowfire:BAAANQAECgEIAwAAAA==.Shìft:BAABNQAECn83AAIgAAoK/hqZEwCvAgAgAAoK/hqZEwCvAgAAAA==.',
Si='Sightofhand:BAAANQADCgQIBAAAAA==.Sintram:BAAANQAECgMIBAAAAA==.',
Sl='Slighted:BAAANQAECgMIBgABNQAECgoKFwAUACIJAA==.Slimydruid:BAAANQAECgYIDgAAAA==.Slow:BAABNQAECn8sAAIFAAkKxCPCHABkAwAFAAkKxCPCHABkAwAAAA==.',
Sm='Smokinontech:BAAANQADCgQIBAABNQAECgoKOwAFALQdAA==.Smokze:BAAANQAECgEIAQAAAA==.',
So='Sockoh:BAABNQAECn8XAAQFAAgK5A9TvwAGAgAFAAgKtw5TvwAGAgAGAAIK2xXrLwCBAAAmAAEKmwb2DQAzAAAAAA==.Solera:BAEANQAECggIAQAAAA==.Sonicberger:BAAANQAECgUICAABNQAECgoKMwAMABYdAA==.Sonicbergger:BAAANQADCgQIBAABNQAECgoKMwAMABYdAA==.Sonicoberg:BAAANQAECgUICwABNQAECgoKMwAMABYdAA==.Soniko:BAABNQAECn8XAAIUAAoKIgkeHgBkAQAUAAoKIgkeHgBkAQAAAA==.Sonícberger:BAABNQAECn8zAAMMAAoKFh0YFABiAgAMAAoKFh0YFABiAgAWAAMKTBcJvAB0AAAAAA==.Soulcaliber:BAAANQAECgMIBAAAAA==.Sovious:BAAANQADCgYIBQAAAA==.',
Sq='Squizzy:BAAANQAECgIIAgAAAA==.',
St='Stain:BAAANQAECgUICQAAAA==.Stealth:BAAANQAECgQIBAABNQAECgkJJwAbAGoZAA==.Stinkfist:BAAANQADCggIHQAAAA==.Stonehenge:BAABNQAECn8pAAINAAoKcRz+FQDzAgANAAoKcRz+FQDzAgAAAA==.Stonepalm:BAAANQADCgcIMAAAAA==.Stratan:BAAANQAECgMIBAAAAA==.Strawk:BAABNQAECn8jAAIOAAkKXA2FTACOAQAOAAkKXA2FTACOAQAAAA==.Stürm:BAAANQAECgMIAwABNQAECgoKMQAiAGgaAA==.',
Su='Subbzero:BAAANQADCgQIBAAAAA==.Suffer:BAAANQADCggICQABNQAECgkJLAAFAMQjAA==.Sunlight:BAAANQAECgcICQAAAA==.Supercat:BAAANQAECgEIAQAAAA==.Surf:BAAANQAECgUIDwAAAA==.',
Sw='Swankydranky:BAACNQAFFH8TAAQYAAcKzg7uBQAQAQAYAAUKKQbuBQAQAQAjAAUK+AcmCwAFAQAiAAIKVADTDAApAAA1AAQKfzAABBgACgoFF20SAL4BABgACAoQE20SAL4BACMACgrkFGo0AHIBACIAAgphBMZIAEYAAAAA.Swankyorcs:BAABNQAECn8VAAIGAAoKxQ9PCgDjAQAGAAoKxQ9PCgDjAQABNQAFFAcIEwAYAM4OAA==.Swankypally:BAAANQAECggIDQABNQAFFAcIEwAYAM4OAA==.',
Sy='Syesc:BAAANQABCgQJBAAAAA==.Sylandris:BAAANQADCgIIAgAAAA==.Sympathy:BAABNQAECn8eAAIlAAoKDhuoCgB6AgAlAAoKDhuoCgB6AgAAAA==.',
['Sá']='Sásukeuchiha:BAAANQAECgUICgABNQAECgoKIAAdAFwKAA==.',
Ta='Tabbz:BAABNQAECn8mAAIOAAoKyRh5MQC1AgAOAAoKyRh5MQC1AgAAAA==.Tallael:BAABNQAECn9MAAIaAAoKOxqhCACMAgAaAAoKOxqhCACMAgAAAA==.Tallyhochick:BAABNQAECn85AAIdAAoKHA6hZQDgAQAdAAoKHA6hZQDgAQAAAA==.Taman:BAABNQAECn8fAAINAAgKNx1lQABeAgANAAgKNx1lQABeAgAAAA==.Tayam:BAAANQAECgUIBQAAAA==.Taylerswift:BAAANQAECgEJAQAAAA==.',
Th='Thebestname:BAABNQAECn8ZAAMkAAkKIAmlMQARAQAkAAgKEAalMQARAQAgAAEKhxDpbgA1AAAAAA==.Thebigonion:BAAANQAECgYIBwAAAA==.Theexile:BAABNQAECn8oAAMSAAoKghduKwA7AgASAAkKixZuKwA7AgATAAcKcBe8IQC+AQAAAA==.Theigh:BAAANQAECgEIAQAAAA==.Thonard:BAAANQAECggIHAABNQAECgoKggAXAN8lAQ==.',
Ti='Tinydeath:BAABNQAECn8fAAIMAAgKwhUsSgDPAQAMAAgKwhUsSgDPAQABNQAECgkJLAAdACAdAA==.Tinyfu:BAAANQADCgQIBAAAAA==.Tinytamer:BAABNQAECn8sAAMdAAkKIB0ISgAoAgAdAAkKyBwISgAoAgAnAAMKRRIbDgDMAAAAAA==.',
Tm='Tmakrist:BAAANQAECgIIDgAAAA==.',
To='Toko:BAACNQAFFH8NAAIdAAYKZBk5CQC1AQAdAAYKZBk5CQC1AQA1AAQKf0IAAh0ACgrAJboFAFsDAB0ACgrAJboFAFsDAAAA.Tomblord:BAABNQAECn8bAAMXAAkKgAkoUgBoAQAXAAkKYgkoUgBoAQAMAAYKuAUshQDoAAAAAA==.',
Tr='Trailblazah:BAAANQAECgUIDgAAAA==.Treeheals:BAAANQAECgEIAQAAAA==.Truthes:BAAANQAECgEIAQABNQAECgkJJwAbAGoZAA==.Truths:BAAANQADCgIJAgABNQAECgkJJwAbAGoZAA==.Truthsx:BAABNQAECn8nAAMbAAkKahn6AwCpAgAbAAgKJRv6AwCpAgAEAAcKEw094gAEAQAAAA==.Truthy:BAAANQADCgYICAABNQAECgkJJwAbAGoZAA==.Truthz:BAAANQAECgIIAwABNQAECgkJJwAbAGoZAA==.',
Ts='Tsukúne:BAAANQADCgQIBAAAAA==.',
Ty='Tyg:BAAANQADCggIFQAAAA==.Tylaatape:BAABNQAECn8sAAQMAAgK+RrdJQC+AQAMAAcK+RrdJQC+AQAWAAcK5AWLgAAbAQAXAAgKnw0tXgAIAQAAAA==.Tyraell:BAAANQAECggIEwAAAA==.',
['Tõ']='Tõkó:BAAANQADCgUIBQABNQAFFAYIDQAdAGQZAA==.',
Um='Umbrae:BAAANQADCgMIAQAAAA==.Umfray:BAAANQAECgIIAwABNQAECgYIFAAJAHQhAA==.',
Us='Usgasdanelv:BAACNQAFFH8FAAIaAAIKWw2+BQCSAAAaAAIKWw2+BQCSAAA1AAQKfyIAAxoACgqhGc4MAKECABoACgqhGc4MAKECAA0AAQq4A1b8ACkAAAAA.',
Uz='Uzala:BAABNQAECn8qAAIEAAYK5glYtwDQAAAEAAYK5glYtwDQAAAAAA==.',
Va='Vanleiden:BAAANQADCgEIAQAAAA==.Varilla:BAAANQAECgEIAQAAAA==.Vazro:BAABNQAECn9LAAMKAAoKoxrcGADgAgAKAAoKoxrcGADgAgALAAYKLQZiFAH9AAAAAA==.',
Ve='Vendiyre:BAAANQAECggICwAAAA==.Venthyl:BAACNQAFFH8KAAIPAAcK7R4vDQCYAQAPAAcK7R4vDQCYAQA1AAQKfzcAAw8ACgp4JjUHABwDAA8ACgqbJDUHABwDABwABQquJQUPALcBAAAA.Veyra:BAAANQAECgEIAgAAAA==.',
Vi='Vindictina:BAAANQABCgMIAwAAAA==.Vizan:BAAANQABCgcIBwABNQAECgkJJwAbAGoZAA==.',
Vo='Voodruid:BAAANQAECgEIBAAAAA==.',
Wa='Warzone:BAAANQADCgUIBQAAAA==.',
We='Wellby:BAAANQAECgMIAwAAAA==.Westerin:BAABNQAECn8xAAIZAAoK3xNxBAC4AQAZAAoK3xNxBAC4AQAAAA==.',
Wi='Wildnature:BAAANQADCggIDgAAAA==.Wildwest:BAAANQADCggIDwAAAA==.Wimateeka:BAABNQAECn82AAQlAAoK3hziHQD6AQAlAAgKuR7iHQD6AQALAAoKJxLhlgD2AQAKAAMKtAp44ABGAAAAAA==.Windfury:BAAANQAECgYICAABNQAECgkJLAAFAMQjAA==.Windigo:BAAANQAECgIIAgAAAA==.Winginit:BAAANQAECgEIAQABNQAFFAcIEwAPAHwRAA==.',
Wo='Wooqles:BAAANQAECgEIBAAAAA==.',
Wr='Wrastelas:BAAANQAECgEIAQAAAA==.',
Wu='Wuilhem:BAAANQADCgEIAQAAAA==.Wurkim:BAAANQADCgQIBAABNQAECgEIAQAQAAAAAA==.',
Wy='Wyldpriest:BAAANQAECgEIAgAAAA==.',
Xa='Xaala:BAAANQAECgQICAAAAA==.',
Xo='Xosderdk:BAAANQADCgIIAgAAAA==.',
Ya='Yarjuul:BAAANQAECgIIAgABNQAECgYIFAAJAHQhAA==.',
Ye='Yespaladin:BAACNQAFFH8WAAIMAAYK9R3BCwAtAQAMAAYK9R3BCwAtAQA1AAQKf0UAAgwACgrYIXoJAO4CAAwACgrYIXoJAO4CAAAA.',
Yi='Yimity:BAAANQAECgMIAwAAAA==.',
Yo='Yogí:BAACNQAFFH8SAAINAAcK0RMcDQB7AQANAAcK0RMcDQB7AQA1AAQKf0sAAg0ACgpiIUsFALsDAA0ACgpiIUsFALsDAAAA.Yozomoto:BAACNQAFFH8TAAIdAAcKLSAtCADJAQAdAAcKLSAtCADJAQA1AAQKfzwAAx0ACgofJe4SAPgCAB0ACgofJe4SAPgCAB4AAgo8D3B2AGMAAAAA.',
Za='Zalandria:BAABNQAECn8lAAIUAAgKuBXpFABYAQAUAAgKuBXpFABYAQAAAA==.Zarelasong:BAAANQADCgIIAgAAAA==.',
Ze='Zeltemis:BAABNQAECn8YAAIdAAgKAgmcjwDqAQAdAAgKAgmcjwDqAQAAAA==.Zeno:BAAANQADCgUIBQAAAA==.',
Zi='Zipsion:BAABNQAECn9FAAIdAAoKJyM5GAA5AwAdAAoKJyM5GAA5AwAAAA==.Zivver:BAABNQAECn86AAMUAAoKuCMxAgAtAwAUAAoKuCMxAgAtAwAJAAIKlgpu9QB2AAAAAA==.Zizka:BAABNQAECn8kAAIfAAoKFQZROQBcAQAfAAoKFQZROQBcAQAAAA==.',
Zo='Zolandir:BAAANQAECgYIDwAAAA==.',
Zu='Zuljia:BAAANQAECgYIBwABNQAECggINQAgAGcdAA==.',
['Òh']='Òhká:BAAANQAECgUIEAAAAA==.',
['Üt']='Üther:BAABNQAECn85AAILAAoKGCTXEACGAwALAAoKGCTXEACGAwAAAA==.',
['ßu']='ßubbleøseven:BAABNQAECn8gAAMLAAkKnx/ZLwCVAgALAAkKnx/ZLwCVAgAlAAYKfhX+IwA5AQAAAA==.',
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
