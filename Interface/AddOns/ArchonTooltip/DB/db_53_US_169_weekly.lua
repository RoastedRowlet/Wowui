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

local lookup = {'DemonHunter-Vengeance','DemonHunter-Havoc','DemonHunter-Devourer','Warlock-Demonology','Mage-Arcane','Mage-Frost','Priest-Holy','Evoker-Preservation','Warrior-Arms','Paladin-Holy','Paladin-Retribution','DeathKnight-Blood','Shaman-Restoration','Shaman-Elemental','Druid-Balance','Unknown-Unknown','Rogue-Assassination','Rogue-Subtlety','Warrior-Protection','Warrior-Fury','DeathKnight-Unholy','DeathKnight-Frost','Monk-Brewmaster','Warlock-Destruction','Shaman-Enhancement','Warlock-Affliction','Druid-Feral','Hunter-BeastMastery','Hunter-Marksmanship','Priest-Shadow','Druid-Restoration','Priest-Discipline','Monk-Mistweaver','Monk-Windwalker','Druid-Guardian','Evoker-Devastation','Paladin-Protection','Mage-Fire','Hunter-Survival',}
local provider = {region='US',realm='Nordrassil',name='US',type='weekly',zone=53,date='2026-11-03',data={Aa='Aairidari:BAABNQAECn8xAAQBAAkKgwjEGwD+AAACAAgK0wbTVAA8AQABAAcKYQnEGwD+AAADAAIKVATFSgA/AAAAAA==.',
Ab='Abruna:BAABNQAECn8WAAIEAAgK/BPXbwAQAgAEAAgK/BPXbwAQAgABNQAFFAcIFAAFAGcUAA==.Abruno:BAACNQAFFH8UAAMFAAcKZxRRHACbAQAFAAYKCRJRHACbAQAGAAEK4B0qCgBgAAA1AAQKfzcAAwUACgqdIgJBAAMDAAUACgolIQJBAAMDAAYAAQqPIZIsAFgAAAAA.Abruto:BAAANQAECgYIDgABNQAFFAcIFAAFAGcUAA==.',
Ae='Aeown:BAAANQAECgMIBgABNQAECgoKUgAHAO0XAA==.',
Ah='Aharuka:BAAANQADCgEIAQAAAA==.',
Ak='Akukho:BAAANQADCgIIAgAAAA==.',
Al='Alandrìas:BAABNQAECn88AAMBAAoKuA/ICQCMAQABAAoKuA/ICQCMAQACAAEKAAAoigAAAAAAAA==.Altera:BAABNQAECn8oAAIIAAoKCg/0IADKAQAIAAoKCg/0IADKAQAAAA==.',
Am='Amuri:BAAANQAECgUIBgAAAA==.',
An='Andelarenn:BAAANQABCgIIAgAAAA==.Andere:BAAANQAECgYICQAAAA==.Androo:BAABNQAECn8fAAIJAAoK9A/MWgC3AQAJAAoK9A/MWgC3AQABNQAFFAcIFAAKAOMXAA==.Androonatorz:BAACNQAFFH8UAAIKAAcK4xd6CgC1AQAKAAcK4xd6CgC1AQA1AAQKfyoAAwoACgrqIZcbAAcDAAoACgrqIZcbAAcDAAsABAovD6bdAOMAAAAA.Anfernay:BAABNQAECn8nAAIJAAoKbxG+egAoAgAJAAoKbxG+egAoAgAAAA==.Antheion:BAAANQAECgYICAABNQAECgcILgAMADUUAA==.Antiaxxis:BAAANQADCgEIAQAAAA==.',
Ap='Apawthetic:BAABNQAECn8bAAMNAAkKRiFNEQAHAwANAAkKRiFNEQAHAwAOAAQKiAZ48wCuAAABNQAFFAcIEwAPAHwRAA==.',
Aq='Aquadab:BAAANQADCgQICAAAAA==.',
Ar='Arashatora:BAAANQAECgEIAQABNQAECgIIBAAQAAAAAA==.Arcanodare:BAAANQADCggICAAAAA==.Arkalis:BAAANQADCgYIBgAAAA==.Arveiturace:BAAANQAECgUIEgAAAA==.',
As='Ashborrn:BAAANQADCgUIBQAAAA==.Ashtar:BAABNQAECn8oAAIJAAgKnxA2jwD2AQAJAAgKnxA2jwD2AQAAAA==.Asukajo:BAAANQADCgMIAwAAAA==.',
At='Attack:BAAANQAECgcIDgAAAA==.',
Ax='Axhure:BAAANQABCgMIAgAAAA==.',
Ba='Babydoll:BAAANQAECgQICAAAAA==.Bajablast:BAAANQADCgcIDQAAAA==.Barma:BAAANQAECgYICQAAAA==.Barrin:BAABNQAECn8eAAIFAAoKuhwnJACTAgAFAAoKuhwnJACTAgAAAA==.',
Be='Bearlyseen:BAABNQAECn8pAAIRAAkKER6cBgB0AgARAAkKER6cBgB0AgABNQAFFAUIEQANACgMAA==.Beltirra:BAAANQAECgMIBAAAAA==.',
Bh='Bhangbros:BAAANQADCgcIBwAAAA==.',
Bi='Biggums:BAAANQAECgMIBAAAAA==.Bigmobility:BAABNQAECn81AAIMAAoKeyIKCAB8AwAMAAoKeyIKCAB8AwAAAA==.Bigwill:BAABNQAECn9SAAIGAAoKkCHnAgAsAwAGAAoKkCHnAgAsAwAAAA==.',
Bl='Blargy:BAABNQAECn9EAAIPAAoKsBl0GAAYAgAPAAoKsBl0GAAYAgAAAA==.Bleach:BAABNQAECn8ZAAMRAAgKIwlSMQC4AAASAAYKlQpafQDWAAARAAYK/AZSMQC4AAAAAA==.Bluewaffles:BAAANQADCgQIBQABNQAECgMIAwAQAAAAAA==.',
Bo='Borealslam:BAAANQADCgQIBAAAAA==.Bouzol:BAAANQAECgYIBgAAAA==.',
Br='Brighterbonk:BAAANQAECgMIBAAAAA==.Brimara:BAAANQAECgUIDAAAAA==.Brothaagamor:BAAANQADCgIIAgAAAA==.',
Bu='Bucketojoy:BAABNQAECn8fAAIFAAoK9wI9xAD1AAAFAAoK9wI9xAD1AAAAAA==.Bunsen:BAAANQAECgQIBAABNQAECgoKKAANAHEcAA==.',
['Bà']='Bàtman:BAAANQAECgQICAABNQAECgUICgAQAAAAAA==.',
['Bö']='Böop:BAAANQADCgYIBgABNQAECgUICgAQAAAAAA==.',
Ca='Caliburne:BAABNQAECn89AAQJAAoKuh7rIACiAgAJAAoKHx7rIACiAgATAAUKhh+5FgC/AQAUAAMK6h4xGQAPAQAAAA==.Captamerica:BAAANQABCgQIBgAAAA==.Capz:BAACNQAFFH8YAAIJAAgKTxvCBACHAgAJAAgKTxvCBACHAgA1AAQKfyUAAgkACgqaJe8fADgDAAkACgqaJe8fADgDAAAA.',
Ce='Ceez:BAABNQAECn8eAAMTAAkKyBE1HADmAAAJAAkKTAzxeABiAQATAAQKFBs1HADmAAAAAA==.Ceezinator:BAAANQADCgQIBAAAAA==.',
Ch='Chichujongar:BAABNQAECn8UAAQMAAcKwwsFbwA5AQAMAAcKcwsFbwA5AQAVAAYKwwUziwD3AAAWAAYKmgV6YQDUAAABNQAFFAcIEwAXAM4OAA==.Chickenstwip:BAAANQADCgEIAgABNQAECgoKOAAFALQdAA==.Chopperr:BAAANQAECgUICAABNQAECgoKOAAFALQdAA==.Chosenöne:BAAANQADCgEIAQAAAA==.Chèn:BAAANQAECgcIEgAAAA==.',
Ci='Cindrella:BAABNQAECn85AAIGAAoKXCSXAADDAwAGAAoKXCSXAADDAwAAAA==.',
Cl='Clayre:BAACNQAFFH8ZAAIYAAYKFRlLAABeAQAYAAYKFRlLAABeAQA1AAQKf1cAAhgACgrrJEUAAFsDABgACgrrJEUAAFsDAAAA.Clow:BAAANQAECgUIEQAAAA==.',
Co='Colossus:BAAANQAECgIIBAAAAA==.Coolcrush:BAAANQADCgUICAABNQAECgoKNAAZAIIkAA==.Corven:BAACNQAFFH8TAAIEAAcKshQcDwCLAQAEAAcKshQcDwCLAQA1AAQKf08ABAQACgocI64LAG8DAAQACgocI64LAG8DABoAAQpJF7oiAEEAABgAAQpFBbiEACUAAAAA.',
Cr='Craziks:BAAANQADCgIIAgAAAA==.Critzwar:BAACNQAFFH8RAAIJAAcKphPsEACtAQAJAAcKphPsEACtAQA1AAQKfyQAAgkACgqZIWQxAPoCAAkACgqZIWQxAPoCAAAA.Crönus:BAAANQAECgIIAgAAAA==.',
Ct='Cthuluwu:BAAANQADCggICAAAAA==.',
Da='Daedyxes:BAABNQAECn8qAAIMAAkKXA+mLwBmAQAMAAkKXA+mLwBmAQAAAA==.Danrod:BAAANQAECgIIAgAAAA==.Daní:BAAANQADCgUIBwABNQAECgEIAQAQAAAAAA==.Darfur:BAABNQAECn8dAAIFAAoKfxbcOgA6AgAFAAoKfxbcOgA6AgAAAA==.Darkensi:BAAANQABCgYICQAAAA==.Dasherdeez:BAAANQAECgEIAQAAAA==.Daygath:BAAANQAECgEJAQAAAA==.',
De='Deadlyiris:BAABNQAECn83AAIJAAoKNR+OKQB2AgAJAAoKNR+OKQB2AgABNQAECgoKKAANAHEcAA==.Deadshot:BAAANQAECgQIDAAAAA==.Deatharin:BAAANQADCgUIBgAAAA==.Deathjak:BAAANQAECgcIDwABNQAECgoKNwAFAKkjAA==.Decompose:BAAANQADCgQIBAAAAA==.Demonbulio:BAABNQAECn8ZAAICAAgKcQdNSgB7AQACAAgKcQdNSgB7AQAAAA==.Demonisthicc:BAABNQAECn85AAIbAAoKDB6cBgABAwAbAAoKDB6cBgABAwAAAA==.Demonskitten:BAAANQADCgUIBQABNQAECgoKOQAbAAweAA==.Demonslayeer:BAAANQADCggIDQAAAA==.Demoronicon:BAAANQAFFAEIAQAAAA==.Devi:BAAANQAECgYICwAAAA==.',
Di='Diaravynn:BAAANQADCgMIBQAAAA==.Diddylord:BAAANQAECgMIBAABNQAECgoKOAAFALQdAA==.Dithehealer:BAABNQAECn8qAAILAAkKrRQVkgAAAgALAAkKrRQVkgAAAgAAAA==.Divain:BAAANQADCgQIBgAAAA==.',
Dk='Dkdi:BAAANQAECgUIBwAAAA==.',
Do='Dozekar:BAAANQAECgEIAQAAAA==.',
Dr='Drenamai:BAABNQAECn8WAAIcAAcKYQ+UmQA6AQAcAAcKYQ+UmQA6AQAAAA==.Drexywexyuwu:BAAANQADCgcJBwAAAA==.',
Du='Duhmptruhk:BAABNQAECn8yAAMJAAoKpBjPPgAaAgAJAAoKMxjPPgAaAgATAAIKtRLGKgB3AAAAAA==.Dunbroch:BAACNQAFFH8SAAIdAAYKZhq8BwDPAQAdAAYKZhq8BwDPAQA1AAQKfzEAAh0ACgrjHXcVALICAB0ACgrjHXcVALICAAAA.Duskfire:BAAANQADCgQIBAAAAA==.Duskforge:BAAANQABCgIJAgAAAA==.',
Dw='Dwagen:BAAANQAECgQIBAAAAA==.',
['Dé']='Démonicblood:BAACNQAFFH8SAAIWAAYKJB+FBQBUAQAWAAYKJB+FBQBUAQA1AAQKfzUAAhYACgpFIZsKAO0CABYACgpFIZsKAO0CAAAA.',
Eg='Eggplantgodx:BAABNQAECn82AAMBAAoKSSUGAgDyAgABAAkKSSUGAgDyAgACAAgKKRlqLwArAgAAAA==.',
Ek='Ekhart:BAAANQAECgEIAQAAAA==.',
El='Elfajah:BAAANQADCgYICQAAAA==.Eliicia:BAACNQAFFH8SAAMRAAcKrwyBCACGAQARAAYKYg6BCACGAQASAAEK5AUVHwBRAAA1AAQKfy4AAxEACgpbILQYALcCABEACgpbILQYALcCABIACQpeDIAyACgBAAAA.',
Em='Emmy:BAAANQAECgQIDwAAAA==.Emofineshyt:BAAANQADCgcICgAAAA==.Emogothbabe:BAABNQAECn84AAMFAAoKtB2bMwBUAgAFAAoKtB2bMwBUAgAGAAMK8w5RLACZAAAAAA==.Emowrecky:BAABNQAECn8kAAMEAAgKbx0GYwAwAgAEAAgKbx0GYwAwAgAYAAEKjA57LwA7AAAAAA==.',
En='Endo:BAACNQAFFH8QAAMVAAcKIRuuCgBlAQAVAAUKGh6uCgBlAQAWAAQKBhYtEQDMAAA1AAQKf0AAAxUACgoLJU0SACUDABUACQooJU0SACUDABYACAoEIiItADYCAAAA.Endorush:BAABNQAECn8tAAMCAAoKZh83FABOAgACAAoKZh83FABOAgADAAIK/RPaPQCCAAABNQAFFAcIEAAVACEbAA==.Endrigosa:BAAANQAECgUIBgAAAA==.Eneldenes:BAAANQAECgUICwAAAA==.Enjoyer:BAAANQAECgcIDgAAAA==.',
Er='Ereitherla:BAABNQAECn8qAAIcAAcKKgp4pAAkAQAcAAcKKgp4pAAkAQAAAA==.Erodrine:BAAANQABCgMIBAAAAA==.',
Es='Esmenet:BAAANQAECgYIEAAAAA==.Espressð:BAABNQAECn8tAAIHAAkKSCIpDgBFAwAHAAkKSCIpDgBFAwABNQAECgoKOAAFALQdAA==.',
Ex='Excalibear:BAABNQAECn8fAAIKAAoKYBvhGgCzAgAKAAoKYBvhGgCzAgABNQAFFAUIEQANACgMAA==.',
Ey='Eydis:BAAANQADCgcIDgAAAA==.Eyepisspeas:BAAANQABCgMIBAAAAA==.',
Fe='Feironor:BAAANQAECgUIBwAAAA==.Fenrys:BAAANQAECgQIBAAAAA==.',
Fi='Fikareous:BAAANQADCggIDQABNQAECgUIBQAQAAAAAA==.',
Fl='Flayre:BAABNQAECn8oAAMNAAkK3RtQRQBMAgANAAgK3BtQRQBMAgAOAAcKMBcNaADoAQAAAA==.Fleredil:BAABNQAECn8/AAMeAAoKVSFHBwDXAgAeAAoKVSFHBwDXAgAHAAEKgQXG/gAuAAAAAA==.Flingernle:BAABNQAECn8yAAIOAAoKeSObBgA6AwAOAAoKeSObBgA6AwAAAA==.',
Fo='Forepray:BAACNQAFFH8QAAIeAAUKVA2NCwAzAQAeAAUKVA2NCwAzAQA1AAQKf0EAAh4ACgpWIKUJAEUDAB4ACgpWIKUJAEUDAAAA.Forger:BAABNQAECn8sAAMTAAkKDAwtGwCGAQATAAkKDAwtGwCGAQAJAAIKQQjVOQFhAAAAAA==.Forsakey:BAAANQADCggIFAABNQAFFAcIDgAfAGIWAA==.',
Fr='Fraun:BAAANQADCggJEQAAAA==.Freshdk:BAAANQAECgQIBAAAAA==.',
Fu='Fullyprotpal:BAAANQAECgEIAQAAAA==.Furioustotem:BAABNQAECn8rAAIOAAcKHBjCeAC4AQAOAAcKHBjCeAC4AQAAAA==.Future:BAAANQADCgUIBgABNQAECgkJLAAFAMQjAA==.',
Fy='Fycat:BAAANQAECggICgABNQAFFAQICgAEANkfAA==.',
Ga='Galten:BAAANQADCgUIBQAAAA==.Gantz:BAAANQADCgIJAgAAAA==.',
Ge='Geekbarr:BAAANQADCgUIBQABNQAECgoKOAAFALQdAA==.',
Gh='Ghettox:BAAANQADCgYIDAAAAA==.Ghostw:BAABNQAECn8WAAIJAAYKux1AdQBrAQAJAAYKux1AdQBrAQAAAA==.',
Gi='Giovanni:BAAANQAECggICAAAAA==.Gizik:BAAANQADCgcIDQABNQAFFAgIGQAeALoQAA==.',
Gn='Gnasher:BAAANQABCgQIBAAAAA==.',
Go='Golgotterath:BAACNQAFFH8RAAINAAUKKAwODwBeAQANAAUKKAwODwBeAQA1AAQKfzoAAw0ACgrKH/IhAIECAA0ACgrKH/IhAIECAA4AAQqNB/I6ATAAAAAA.Gorm:BAABNQAECn8vAAIFAAoKnBywVgDTAgAFAAoKnBywVgDTAgABNQAECgQIBQAQAAAAAA==.',
Gr='Grippyshocks:BAAANQAECgIIAQABNQAECgoKKQACAGIgAA==.',
Ha='Halbruck:BAAANQAECgcIEQAAAA==.Haldane:BAABNQAECn8zAAILAAkKRApGqwA4AQALAAkKRApGqwA4AQABNQAECgoKKAANAHEcAA==.Harrydottur:BAAANQAECggIDQABNQAFFAUIEQAEAAYcAA==.Havochunter:BAAANQAECgcICwAAAA==.Hawley:BAAANQABCgIIAgAAAA==.',
He='Heidegger:BAAANQADCgYICgAAAA==.Helinndealin:BAACNQAFFH8SAAIgAAYKVBytAADoAQAgAAYKVBytAADoAQA1AAQKfywAAyAACgrEJFQBAEcDACAACQryJFQBAEcDAAcACAotIsZJAEgCAAAA.Hellin:BAAANQADCgMIAQAAAA==.Heolstor:BAABNQAECn8zAAIMAAoKcRzKGgD/AQAMAAoKcRzKGgD/AQAAAA==.Hephsdh:BAAANQAECggIDwAAAA==.Heraois:BAABNQAECn8iAAIdAAoKtgmsNgCZAQAdAAoKtgmsNgCZAQAAAA==.',
Hg='Hgshake:BAAANQADCgYIBgAAAA==.',
Ho='Holytës:BAAANQAECgUIBwAAAA==.Holywráth:BAAANQAECgQIBAAAAA==.',
Hu='Hunterdh:BAABNQAECn8rAAIcAAkKiQdTfgB1AQAcAAkKiQdTfgB1AQAAAA==.',
Hy='Hynixx:BAABNQAECn8uAAMUAAoKqxsdCQBKAgAUAAgKJRodCQBKAgAJAAcKjRjSaQCKAQABNQAFFAUIEAAeAFQNAA==.',
Il='Illidope:BAABNQAECn8pAAQCAAoKYiDcFQDuAgACAAoKSyDcFQDuAgADAAgK+xwZIwAxAgABAAEKAACILgBGAAAAAA==.',
In='Infinitevoid:BAAANQADCggIFQAAAA==.Infliximab:BAAANQAECggICAAAAA==.Innervatez:BAABNQAFFH8LAAIfAAUKJCMuBADuAQAfAAUKJCMuBADuAQAAAA==.Inteaus:BAAANQADCggIGgAAAA==.',
Io='Ionúin:BAAANQADCgQJBAAAAA==.',
Iv='Ivÿ:BAAANQADCgMIBQABNQAECgUICgAQAAAAAA==.',
Ja='Jabkhan:BAAANQAECgUIDAAAAA==.Jaekir:BAABNQAECn8oAAIGAAoK6xORCwAHAgAGAAoK6xORCwAHAgAAAA==.Jakfrost:BAABNQAECn83AAMFAAoKqSP8NABPAgAFAAkK6iP8NABPAgAGAAMKKiLkGgAcAQAAAA==.Jakie:BAAANQADCgYICgABNQAECggIFwAJAN8aAA==.Jarten:BAACNQAFFH8QAAIWAAYKOhrUBgAwAQAWAAYKOhrUBgAwAQA1AAQKf0YAAhYACgooIRwMANsCABYACgooIRwMANsCAAAA.Jayaah:BAAANQAECgMIBAAAAA==.Jaylebate:BAABNQAECn8aAAMVAAgKrxkDIACvAQAVAAgK9xcDIACvAQAMAAYKbxpcXACBAQAAAA==.',
Je='Jerrenn:BAAANQAECgQIBAAAAA==.Jesseatamer:BAACNQAFFH8QAAIcAAYKXCEfBQBzAQAcAAYKXCEfBQBzAQA1AAQKf0QAAhwACgqFJYYEAFwDABwACgqFJYYEAFwDAAAA.',
Ji='Jigme:BAAANQAECgIIAgAAAA==.Jitsuru:BAAANQADCgUIBQAAAA==.',
Jo='Jox:BAAANQABCgUIBQAAAA==.Joxor:BAAANQABCgUIBQAAAA==.',
Js='Jstdeath:BAAANQADCgEIAQABNQAECgoKNQAJAHEVAA==.Jstrawr:BAABNQAECn81AAIJAAoKcRVvYgBnAgAJAAoKcRVvYgBnAgAAAA==.Jsttotem:BAAANQAECgUIBQABNQAECgoKNQAJAHEVAA==.',
Ka='Kalmek:BAABNQAECn8VAAMVAAkKLw0mKgBhAQAVAAkKkAwmKgBhAQAWAAIKMQbwogAuAAAAAA==.Kaln:BAAANQAECgIIBwABNQAECgQIBQAQAAAAAA==.Karen:BAAANQAECgUIDgAAAA==.Kasalu:BAAANQABCgQIBAAAAA==.Kasanzzar:BAAANQAECgYIBwAAAA==.Kastia:BAAANQAECgQICQAAAA==.Kasumï:BAAANQAECgEIAgABNQAFFAUIEAAcAF8jAA==.Katrynwel:BAAANQAECgQIBAAAAA==.Katsumi:BAAANQAECgQIBgAAAA==.',
Ke='Keliki:BAABNQAECn88AAMNAAoKOB4qDgAqAwANAAoKOB4qDgAqAwAOAAgKzhigQQBvAgAAAA==.Kettama:BAAANQAECgUIBQABNQAECgoKOAAFALQdAA==.',
Kh='Khold:BAABNQAECn8xAAMWAAoKDRs6IAAUAgAWAAoKDRs6IAAUAgAMAAQKBw7gZQCOAAAAAA==.Khrogann:BAAANQAECggIEQAAAA==.',
Ki='Kijana:BAAANQADCggICAAAAA==.Killalltoday:BAABNQAECn8nAAINAAgKWRJ9aQDQAQANAAgKWRJ9aQDQAQAAAA==.Killersmile:BAAANQADCgQIBAAAAA==.Kirkk:BAAANQAECgMIBAAAAA==.',
Kl='Klaminus:BAAANQADCgQIBAABNQAECgMIAgAQAAAAAA==.',
Kn='Knixx:BAACNQAFFH8UAAIHAAcKIBEIEACUAQAHAAcKIBEIEACUAQA1AAQKf04AAwcACgrvJesAAOQDAAcACgrvJesAAOQDACAABgrzEYsPADIBAAAA.Knuppelus:BAAANQADCgYIDAAAAA==.',
Ko='Kobyashimaru:BAAANQADCgUIBQAAAA==.Koshi:BAAANQADCgMIAwAAAA==.Kotastrophe:BAAANQAECgMIAwABNQAECgoKMgAJAKQYAA==.Kotastrophic:BAAANQAECgUIBQAAAA==.Koveras:BAAANQADCgYIBwAAAA==.Koyaanis:BAAANQADCggIDgAAAA==.Koyya:BAABNQAECn8uAAMZAAoKnA03FAAlAgAZAAkK5Ao3FAAlAgANAAoK4RLSRgDFAQAAAA==.',
Kr='Krathos:BAAANQAECgUICwAAAA==.Krenmonk:BAAANQAECgEIAQAAAA==.Krennic:BAAANQADCgcIBwAAAA==.Krunchee:BAAANQAECgQIBwAAAA==.',
Ku='Kufoo:BAABNQAECn84AAMUAAoKaCXUAABRAwAUAAoKaCXUAABRAwATAAEKkx4mMgBUAAAAAA==.Kurao:BAAANQAECgMIBQAAAA==.Kurukai:BAAANQADCgMIAwAAAA==.',
Ky='Kyrian:BAACNQAFFH8fAAMSAAcKriBiAQBaAgASAAcKriBiAQBaAgARAAMKvREHEADrAAA1AAQKfzUAAxIACgrcIygFADgDABIACgrcIygFADgDABEAAwpZHHlvAPMAAAAA.',
La='Lagøless:BAABNQAECn8iAAIcAAoKwSAhEwBTAwAcAAoKwSAhEwBTAwAAAA==.',
Le='Leo:BAAANQAECgEIAQAAAA==.',
Li='Liatris:BAAANQAECgUIBQAAAA==.Likestoflash:BAEANQADCgYIBgABNQAECgoKRAAcAEQeAA==.Lissaris:BAAANQADCgEIAgAAAA==.',
Lo='Lohal:BAABNQAECn88AAIEAAoKVBlKKgA7AgAEAAoKVBlKKgA7AgAAAA==.Lohmi:BAABNQAECn8aAAIOAAkKzgZkWQA/AQAOAAkKzgZkWQA/AQAAAA==.Lormn:BAAANQADCgEIAQAAAA==.',
Lu='Luania:BAAANQAECgQICQAAAA==.',
Ly='Lyna:BAAANQADCggIDAAAAA==.Lyshkä:BAABNQAECn8xAAIhAAoKaBpAEAB7AgAhAAoKaBpAEAB7AgAAAA==.Lyzzardkng:BAABNQAECn80AAILAAoKuwnEjAByAQALAAoKuwnEjAByAQAAAA==.',
['Lý']='Lýra:BAAANQAECgQIBwAAAA==.',
Ma='Maango:BAABNQAECn8jAAILAAoKLR4HKwCNAgALAAoKLR4HKwCNAgAAAA==.Maemu:BAAANQABCgUIBwAAAA==.Magerthat:BAAANQADCgQIBgAAAA==.Magicaltickl:BAABNQAECn8jAAIFAAoKZg2+XADVAQAFAAoKZg2+XADVAQAAAA==.Magiki:BAAANQADCgcICwAAAA==.Makyaihua:BAAANQABCggIHAAAAA==.Malkala:BAAANQADCgMIAwAAAA==.Malonormu:BAAANQABCgcIBgAAAA==.Mamadeezy:BAAANQADCgYJCwAAAA==.Mando:BAAANQAECgUICwABNQAECgcIKgAiAFoZAA==.Manical:BAAANQAECgMICwAAAA==.Marcel:BAAANQADCgYIEQABNQAECgMIBAAQAAAAAA==.Martinikiss:BAAANQAECgcIEAAAAA==.Mashiach:BAACNQAFFH8MAAIHAAYKDBugDADBAQAHAAYKDBugDADBAQA1AAQKfygAAwcACgpTIdgPAEcDAAcACgpTIdgPAEcDAB4AAQoAALx4ADYAAAAA.Matthyjsz:BAAANQADCgIIAgAAAA==.',
Me='Megumin:BAAANQAECgYICgABNQAECgoKOQALABgkAA==.Melikefire:BAABNQAECn8hAAIFAAoKURZXmgBMAgAFAAoKURZXmgBMAgAAAA==.Melodious:BAAANQAECgEIAQAAAA==.Memecompdall:BAAANQAECgIIAgAAAA==.Merek:BAABNQAECn8iAAIXAAgKyB8JBwDSAgAXAAgKyB8JBwDSAgAAAA==.Mettix:BAAANQADCgIIAgAAAA==.',
Mi='Mirigosa:BAAANQAECgEIAQABNQAECgoKOQAGAFwkAA==.Mistybdk:BAABNQAECn8zAAIMAAoKmBikFQA2AgAMAAoKmBikFQA2AgABNQAFFAcIFgAjAOITAA==.Mistyd:BAACNQAFFH8WAAIjAAcK4hOIAABGAgAjAAcK4hOIAABGAgA1AAQKf1kAAiMACgqVJWIBAGsDACMACgqVJWIBAGsDAAAA.',
Mo='Mogfooyen:BAAANQABCgYICQAAAA==.Moonbeam:BAAANQAECgUIBgAAAA==.Morgause:BAABNQAECn8YAAIEAAYKGAajpADWAAAEAAYKGAajpADWAAABNQAECgkJGQAPAMEGAA==.Morllan:BAABNQAECn8oAAIEAAoK9w3CZABtAQAEAAoK9w3CZABtAQAAAA==.',
Mu='Muirdin:BAAANQADCgEIAQAAAA==.',
My='Mykinlive:BAAANQADCgIIAgAAAA==.',
['Má']='Mááââybèèëëè:BAAANQADCgEIAQAAAA==.',
['Må']='Mångix:BAAANQAECgQIBAAAAA==.',
['Mé']='Mélusine:BAABNQAECn8ZAAMJAAkKURJ5igABAgAJAAkKpw95igABAgAUAAQKrRB2HQDYAAAAAA==.',
Na='Naanomage:BAAANQAECgYICAAAAA==.Naija:BAAANQADCgIIAgAAAA==.Narcotx:BAAANQADCgIIAgAAAA==.',
Ne='Necrotoxin:BAAANQADCgYIBgAAAA==.',
Ni='Nightmaratic:BAAANQADCgYIBgAAAA==.Nightsdeath:BAAANQAECgEIAQAAAA==.Nightsever:BAABNQAECn8nAAIDAAkKwSJIBwBeAwADAAkKwSJIBwBeAwAAAA==.Nirath:BAABNQAECn8nAAIkAAkKOwWeIABOAQAkAAkKOwWeIABOAQAAAA==.',
No='Noiire:BAAANQAECggIEAABNQAFFAcIEgARAK8MAA==.',
Od='Odysse:BAAANQADCgYICQAAAA==.Odyssé:BAABNQAECn8iAAIcAAkK2B7UIQAQAwAcAAkK2B7UIQAQAwAAAA==.',
Oi='Oio:BAAANQAECggIAgAAAA==.',
Ok='Okami:BAABNQAECn8cAAIiAAYKFB4pIABjAQAiAAYKFB4pIABjAQAAAA==.',
On='Onehotelf:BAAANQAECgQIBAAAAA==.',
Oo='Ooyagoddess:BAAANQAECgIIAgAAAA==.',
Or='Orienn:BAAANQAECgQIAgAAAA==.',
Pa='Pacamonk:BAABNQAECn8/AAIiAAoKrR0sDQAIAwAiAAoKrR0sDQAIAwAAAA==.Palenar:BAAANQADCgQIBAAAAA==.Papatiny:BAAANQAECgcIEAAAAA==.Papábear:BAAANQADCgQIBAAAAA==.Pawsa:BAAANQAECgcIDAABNQAECgoKOAAFALQdAA==.Pawthetic:BAACNQAFFH8TAAQPAAcKfBFdEgBEAQAPAAUK5RRdEgBEAQAfAAEKVw6PFABNAAAbAAEK2AP1AwBDAAA1AAQKfz4AAx8ACgqJIzUJAAUDAB8ACgqJIzUJAAUDAA8ACgrCHFcfANACAAAA.',
Pe='Peelforheals:BAACNQAFFH8FAAIeAAMKLAcGFACMAAAeAAMKLAcGFACMAAA1AAQKfzMAAx4ACgqkHpwOAAYDAB4ACgqkHpwOAAYDACAABQpdDHsXALoAAAAA.Penguindemic:BAABNQAECn8wAAMEAAoKVSWaBgCaAwAEAAoKVSWaBgCaAwAYAAEKoCISagBNAAAAAA==.Pep:BAABNQAECn8UAAIiAAkKhQpJPAAzAQAiAAkKhQpJPAAzAQAAAA==.Pepperoni:BAAANQADCggIDQAAAA==.Perdator:BAAANQAECgQICAAAAA==.Petruccius:BAACNQAFFH8bAAIPAAUK3BOxDQDjAAAPAAUK3BOxDQDjAAA1AAQKf2QAAg8ACgrbIFEMAGgDAA8ACgrbIFEMAGgDAAAA.Pewpewlepew:BAAANQAECgQICQAAAA==.',
Ph='Phaeku:BAAANQADCgMIAwAAAA==.',
Pi='Picklebreath:BAAANQADCgUICgAAAA==.Pinksparklez:BAAANQADCgUICAABNQAECgEIAQAQAAAAAA==.',
Pl='Plague:BAAANQAECgMIAwAAAA==.',
Po='Ponglenis:BAAANQAECgIIAgAAAA==.Poptartsz:BAAANQAECgQICQAAAA==.Potatolockx:BAAANQAECgQIAwAAAA==.',
Pr='Prayre:BAABNQAECn8dAAMHAAoKCApdTQDKAQAHAAoKCApdTQDKAQAeAAUKYAoGMADQAAAAAA==.Precht:BAAANQAECgMIBAAAAA==.Prikarea:BAAANQAECgUIBQAAAA==.Prospa:BAAANQAECgUICQABNQAECgoKOAAFALQdAA==.Prumper:BAABNQAECn8oAAIFAAoKVhAxbACqAQAFAAoKVhAxbACqAQAAAA==.Príest:BAAANQAECggICAAAAA==.',
Pu='Purah:BAAANQADCgEIAgAAAA==.',
['Pä']='Päncake:BAAANQAECgUICgAAAA==.',
Qu='Quesoblanco:BAABNQAECn8bAAMlAAgKcxAxOwAXAQALAAgKeQhB1QBxAQAlAAUKKhkxOwAXAQAAAA==.',
Qy='Qybxboogietk:BAABNQAECn8jAAICAAkK8hSDMQAdAgACAAkK8hSDMQAdAgAAAA==.',
Ra='Rabid:BAAANQAECgQIDAAAAA==.Raeliana:BAAANQADCgQIBAAAAA==.Raghallov:BAAANQAECggIEwAAAA==.Rampa:BAAANQADCgYIEQABNQAECgoKOAAFALQdAA==.',
Re='Reaperan:BAAANQAECgEIAQAAAA==.Regena:BAABNQAECn9SAAMHAAoK7RfZIQCgAgAHAAoK7RfZIQCgAgAeAAMKOQKLagBYAAAAAA==.Rekriss:BAAANQADCgYIBgAAAA==.Remorse:BAACNQAFFH8SAAITAAYKZRKNAgBrAQATAAYKZRKNAgBrAQA1AAQKf0MAAhMACgpeIWYGAAADABMACgpeIWYGAAADAAAA.Rendwick:BAAANQADCgYICQAAAA==.Required:BAABNQAECn8ZAAIdAAkK5BJxEAACAgAdAAkK5BJxEAACAgABNQAFFAYIEgACANAgAA==.',
Ri='Rikahoe:BAAANQAECgUIBQABNQAECgUIBQAQAAAAAA==.Riker:BAAANQADCgQIBAABNQAECgMIBAAQAAAAAA==.Rim:BAABNQAECn84AAINAAoKIRznGQC7AgANAAoKIRznGQC7AgAAAA==.',
Ro='Ronfar:BAACNQAFFH8QAAIZAAUKSBh4AgCoAQAZAAUKSBh4AgCoAQA1AAQKf1wAAxkACgpiItcCAHgDABkACgpiItcCAHgDAA4ACApNFfA3ALwBAAAA.Rootx:BAAANQAECgMIAwABNQAFFAcIJQAPADQjAA==.',
Ru='Rukidingme:BAAANQAECgQIBAAAAA==.Rustyglass:BAAANQABCgYIBAAAAA==.Ruttisðir:BAAANQAECgIIAwAAAA==.',
Ry='Ryhorn:BAAANQADCggIDgAAAA==.Ryno:BAAANQADCgUIBwAAAA==.Ryujin:BAABNQAECn8bAAILAAoK7QkvyQCJAQALAAoK7QkvyQCJAQAAAA==.Ryù:BAAANQAECgQICgAAAA==.',
Sa='Salo:BAAANQADCgMIBgAAAA==.Salòme:BAAANQAECgIIAgABNQAECgoKHAAcADIJAA==.Sanazenet:BAAANQADCggJDAAAAA==.Saphiriel:BAAANQAECgMIBQAAAA==.Saviorself:BAAANQADCgMIAwABNQAFFAcIEwAPAHwRAA==.',
Sc='Scarscar:BAAANQAECggIDAAAAA==.Schwinn:BAAANQADCgQIBAAAAA==.Scracky:BAAANQAECgQIBAAAAA==.',
Se='Segarth:BAABNQAECn8cAAMOAAoKbBScWwAPAgAOAAoKbBScWwAPAgANAAQKkRB8xADfAAAAAA==.Selen:BAAANQAECgcIEQAAAA==.Semballin:BAAANQAECgUIBQAAAA==.Seråphiel:BAAANQAECgUIBQAAAA==.Seswatha:BAAANQAECgYICAABNQAFFAUIEQANACgMAA==.',
Sh='Shamandroo:BAABNQAECn8YAAINAAkK0Bo7JwDHAgANAAkK0Bo7JwDHAgABNQAFFAcIFAAKAOMXAA==.Shamdi:BAAANQADCgYIBgAAAA==.Shanghaied:BAAANQADCgcIDAAAAA==.Shawtyy:BAAANQADCgMIAwAAAA==.Shmongus:BAAANQADCgIIAgABNQAECgcIDgAQAAAAAA==.Shortandold:BAABNQAECn8cAAMSAAoK0wrnRAChAQASAAoK0wrnRAChAQARAAEKagOjYQAwAAAAAA==.Shådowfire:BAAANQAECgEIAQAAAA==.Shìft:BAABNQAECn8uAAIfAAkKRBuZEwCvAgAfAAkKRBuZEwCvAgAAAA==.',
Si='Sightofhand:BAAANQADCgQIBAAAAA==.Sintram:BAAANQAECgMIAwAAAA==.',
Sl='Slighted:BAAANQAECgMIBgABNQAECgkJFgATAP0IAA==.Slimydruid:BAAANQAECgYICgAAAA==.Slow:BAABNQAECn8sAAIFAAkKxCPCHABkAwAFAAkKxCPCHABkAwAAAA==.',
Sm='Smokinontech:BAAANQADCgQIBAABNQAECgoKOAAFALQdAA==.Smokze:BAAANQADCggJCAAAAA==.',
So='Sockoh:BAABNQAECn8XAAQFAAgK5A9TvwAGAgAFAAgKtw5TvwAGAgAGAAIK2xXrLwCBAAAmAAEKmwb2DQAzAAAAAA==.Sonicberger:BAAANQAECgUICAABNQAECgoKLwAMANgcAA==.Sonicbergger:BAAANQADCgQIBAABNQAECgoKLwAMANgcAA==.Sonicoberg:BAAANQAECgUIDwABNQAECgoKLwAMANgcAA==.Soniko:BAABNQAECn8WAAITAAkK/QgeHgBkAQATAAkK/QgeHgBkAQAAAA==.Sonícberger:BAABNQAECn8vAAMMAAoK2Bx7FABFAgAMAAoK2Bx7FABFAgAVAAMKTBcJvAB0AAAAAA==.Soulcaliber:BAAANQAECgMIBAAAAA==.Sovious:BAAANQADCgYIBQAAAA==.',
Sq='Squizzy:BAAANQAECgIIAgAAAA==.',
St='Stain:BAAANQAECgUICAAAAA==.Stealth:BAAANQAECgQIBAABNQAECgkJJwAaAGoZAA==.Stinkfist:BAAANQADCggIHQAAAA==.Stonehenge:BAABNQAECn8oAAINAAoKcRx9EQAFAwANAAoKcRx9EQAFAwAAAA==.Stonepalm:BAAANQADCgcIMAAAAA==.Stratan:BAAANQAECgMIAgAAAA==.Strawk:BAABNQAECn8fAAIOAAcKLg6PgACjAQAOAAcKLg6PgACjAQAAAA==.Stürm:BAAANQAECgMIAwABNQAECgoKMQAhAGgaAA==.',
Su='Subbzero:BAAANQADCgQIBAAAAA==.Suffer:BAAANQADCggICQABNQAECgkJLAAFAMQjAA==.Sunlight:BAAANQAECgcICQAAAA==.Supercat:BAAANQAECgEIAQAAAA==.Surf:BAAANQAECgYIDwAAAA==.',
Sw='Swankydranky:BAACNQAFFH8TAAQXAAcKzg7uBQAQAQAXAAUKKQbuBQAQAQAiAAUK+AcmCwAFAQAhAAIKVAC9CwAqAAA1AAQKfy8ABBcACgoFF20SAL4BABcACAoQE20SAL4BACIACgrkFGo0AHIBACEAAgphBMZIAEYAAAAA.Swankyorcs:BAAANQAECggICQABNQAFFAcIEwAXAM4OAA==.Swankypally:BAAANQAECggICwABNQAFFAcIEwAXAM4OAA==.',
Sy='Syesc:BAAANQABCgQJBAAAAA==.Sylandris:BAAANQADCgIIAgAAAA==.Sympathy:BAABNQAECn8UAAIlAAoKqRMOEgDLAQAlAAoKqRMOEgDLAQAAAA==.',
['Sá']='Sásukeuchiha:BAAANQAECgQIBQABNQAECgoKHAAcADIJAA==.',
Ta='Tabbz:BAABNQAECn8mAAIOAAoKyRh5MQC1AgAOAAoKyRh5MQC1AgAAAA==.Tallael:BAABNQAECn9DAAIZAAoK6hX9CQBNAgAZAAoK6hX9CQBNAgAAAA==.Tallyhochick:BAABNQAECn8zAAIcAAoK6Q1UWQDTAQAcAAoK6Q1UWQDTAQAAAA==.Taman:BAABNQAECn8fAAINAAgKNx1lQABeAgANAAgKNx1lQABeAgAAAA==.Tayam:BAAANQAECgUIBQAAAA==.Taylerswift:BAAANQAECgEJAQAAAA==.',
Th='Thebestname:BAABNQAECn8ZAAMjAAkKIAmlMQARAQAjAAgKEAalMQARAQAfAAEKhxBqZQA1AAAAAA==.Thebigonion:BAAANQADCggIGgAAAA==.Theexile:BAABNQAECn8oAAMRAAoKghduKwA7AgARAAkKixZuKwA7AgASAAcKcBe8IQC+AQAAAA==.Theigh:BAAANQAECgEIAQAAAA==.Thonard:BAAANQAECggIFQABNQAECgoKcwAWAMAlAQ==.',
Ti='Tinydeath:BAABNQAECn8fAAIMAAgKwhUsSgDPAQAMAAgKwhUsSgDPAQABNQAECgkJKwAcACAdAA==.Tinyfu:BAAANQADCgQIBAAAAA==.Tinytamer:BAABNQAECn8rAAMcAAkKIB1uOgAwAgAcAAkKyBxuOgAwAgAnAAMKRRIbDgDMAAAAAA==.',
Tm='Tmakrist:BAAANQAECgIIBgAAAA==.',
To='Toko:BAACNQAFFH8NAAIcAAYKZBk5CQC1AQAcAAYKZBk5CQC1AQA1AAQKf0EAAhwACgrAJfADAGMDABwACgrAJfADAGMDAAAA.Tomblord:BAABNQAECn8bAAMWAAkKgAkoUgBoAQAWAAkKYgkoUgBoAQAMAAYKuAUshQDoAAAAAA==.',
Tr='Trailblazah:BAAANQAECgUICgAAAA==.Treeheals:BAAANQADCggICAAAAA==.Truthes:BAAANQADCgYIBwABNQAECgkJJwAaAGoZAA==.Truths:BAAANQADCgIJAgABNQAECgkJJwAaAGoZAA==.Truthsx:BAABNQAECn8nAAMaAAkKahn6AwCpAgAaAAgKJRv6AwCpAgAEAAcKEw094gAEAQAAAA==.Truthy:BAAANQADCgYICAABNQAECgkJJwAaAGoZAA==.Truthz:BAAANQAECgEIAQABNQAECgkJJwAaAGoZAA==.',
Ts='Tsukúne:BAAANQADCgQIBAAAAA==.',
Ty='Tyg:BAAANQADCggIFQAAAA==.Tylaatape:BAABNQAECn8sAAQMAAgK+RomIQDFAQAMAAcK+RomIQDFAQAVAAcK5AWLgAAbAQAWAAgKnw0kVAAIAQAAAA==.Tyraell:BAAANQAECggIEQAAAA==.',
['Tõ']='Tõkó:BAAANQADCgUIBQABNQAFFAYIDQAcAGQZAA==.',
Um='Umbrae:BAAANQADCgMIAQAAAA==.Umfray:BAAANQAECgIIAwABNQAECgUIEQAQAAAAAA==.',
Us='Usgasdanelv:BAACNQAFFH8FAAIZAAIKWw3rBACWAAAZAAIKWw3rBACWAAA1AAQKfyIAAxkACgqhGc4MAKECABkACgqhGc4MAKECAA0AAQq4A1vuACkAAAAA.',
Uz='Uzala:BAABNQAECn8gAAIEAAYKhAlzqgDLAAAEAAYKhAlzqgDLAAAAAA==.',
Va='Vanleiden:BAAANQADCgEIAQAAAA==.Vazro:BAABNQAECn9BAAMKAAoKeRpSGADHAgAKAAoKeRpSGADHAgALAAYKLQZiFAH9AAAAAA==.',
Ve='Vendiyre:BAAANQAECggICAAAAA==.Venthyl:BAACNQAFFH8JAAIPAAYKxh8vDQCYAQAPAAYKxh8vDQCYAQA1AAQKfzMAAw8ACgoKJukFACMDAA8ACgqbJOkFACMDABsAAwqHJQ0dANQAAAAA.Veyra:BAAANQABCgMIAwAAAA==.',
Vi='Vindictina:BAAANQABCgMIAwAAAA==.Vizan:BAAANQABCgcIBwABNQAECgkJJwAaAGoZAA==.',
Wa='Warzone:BAAANQADCgUIBQAAAA==.',
We='Wellby:BAAANQAECgMIAwAAAA==.Westerin:BAABNQAECn8oAAIYAAkKTBHWDwAAAgAYAAkKTBHWDwAAAgAAAA==.',
Wi='Wildnature:BAAANQADCggIDgAAAA==.Wildwest:BAAANQADCggIDwAAAA==.Wimateeka:BAABNQAECn8yAAQlAAoK1hbiHQD6AQAlAAYK3B3iHQD6AQALAAoKJxLhlgD2AQAKAAMKtAqM0gBGAAAAAA==.Windfury:BAAANQAECgYICAABNQAECgkJLAAFAMQjAA==.Windigo:BAAANQAECgIIAgAAAA==.Winginit:BAAANQAECgEIAQABNQAFFAcIEwAPAHwRAA==.',
Wr='Wrastelas:BAAANQADCggICAAAAA==.',
Wu='Wuilhem:BAAANQADCgEIAQAAAA==.Wurkim:BAAANQADCgQIBAABNQADCggICAAQAAAAAA==.',
Xa='Xaala:BAAANQAECgQIBQAAAA==.',
Xo='Xosderdk:BAAANQADCgIIAgAAAA==.',
Ya='Yarjuul:BAAANQAECgIIAgABNQAECgUIEQAQAAAAAA==.',
Ye='Yespaladin:BAACNQAFFH8VAAIMAAYK9R0DCQA2AQAMAAYK9R0DCQA2AQA1AAQKf0QAAgwACgorIU8JAOQCAAwACgorIU8JAOQCAAAA.',
Yi='Yimity:BAAANQAECgMIAwAAAA==.',
Yo='Yogí:BAACNQAFFH8SAAINAAcK0RMcDQB7AQANAAcK0RMcDQB7AQA1AAQKf0MAAg0ACgohIfsEALUDAA0ACgohIfsEALUDAAAA.Yozomoto:BAACNQAFFH8TAAIcAAcKLSAtCADJAQAcAAcKLSAtCADJAQA1AAQKfzoAAxwACgofJZwRAOsCABwACgofJZwRAOsCAB0AAgo8D3B2AGMAAAAA.',
Za='Zalandria:BAABNQAECn8jAAITAAgKmxMyFABAAQATAAgKmxMyFABAAQAAAA==.Zarelasong:BAAANQADCgIIAgAAAA==.',
Ze='Zeltemis:BAABNQAECn8YAAIcAAgKAgmcjwDqAQAcAAgKAgmcjwDqAQAAAA==.Zeno:BAAANQADCgUIBQAAAA==.',
Zi='Zipsion:BAABNQAECn9AAAIcAAoKJSM5GAA5AwAcAAoKJSM5GAA5AwAAAA==.Zivver:BAABNQAECn80AAMTAAoKeyM8AgAbAwATAAoKeyM8AgAbAwAJAAIKlgpR5QB3AAAAAA==.Zizka:BAABNQAECn8hAAIeAAoK9QVROQBcAQAeAAoK9QVROQBcAQAAAA==.',
Zo='Zolandir:BAAANQAECgYICAAAAA==.',
Zu='Zuljia:BAAANQAECgYIBwAAAA==.',
['Òh']='Òhká:BAAANQAECgUICwAAAA==.',
['Üt']='Üther:BAABNQAECn85AAILAAoKGCTXEACGAwALAAoKGCTXEACGAwAAAA==.',
['ßu']='ßubbleøseven:BAABNQAECn8gAAMLAAkKnx/JJgCgAgALAAkKnx/JJgCgAgAlAAYKfhXPHgBCAQAAAA==.',
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
