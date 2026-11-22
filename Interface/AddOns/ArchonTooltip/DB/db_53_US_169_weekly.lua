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
local provider = {region='US',realm='Nordrassil',name='US',type='weekly',zone=53,date='2026-11-17',data={Aa='Aairidari:BAABNQAECn8/AAQBAAoKZwjEGwD+AAABAAcKYQnEGwD+AAACAAkK7waiTQDwAAADAAIKWASsUgA/AAAAAA==.',
Ab='Abruna:BAABNQAECn8WAAIEAAgK/BPXbwAQAgAEAAgK/BPXbwAQAgABNQAFFAcIFAAFAGcUAA==.Abruno:BAACNQAFFH8UAAMFAAcKZxRRHACbAQAFAAYKCRJRHACbAQAGAAEK4B0FDgBXAAA1AAQKfzsAAwUACgr4IgJBAAMDAAUACgqBIQJBAAMDAAYAAQqPIX41AFYAAAAA.Abruto:BAAANQAECgYIDgABNQAFFAcIFAAFAGcUAA==.',
Ae='Aeown:BAAANQAECgMIBgABNQAECgoKXQAHAB0YAA==.',
Ah='Aharuka:BAAANQADCgEIAQAAAA==.',
Ak='Akukho:BAAANQADCgIIAgAAAA==.',
Al='Alandrìas:BAABNQAECn9JAAMBAAoKUBA0DACQAQABAAoKUBA0DACQAQACAAEKAAD/mwAAAAAAAA==.Almostxtinct:BAAANQAECgEIAgAAAA==.Altera:BAABNQAECn8sAAIIAAoK1Q/0IADKAQAIAAoK1Q/0IADKAQAAAA==.',
Am='Amuri:BAAANQAECgYICgAAAA==.',
An='Andelarenn:BAAANQABCgIIAgAAAA==.Andere:BAAANQAECgYICQAAAA==.Androo:BAABNQAECn8fAAIJAAoK9A+JcACxAQAJAAoK9A+JcACxAQABNQAFFAcIFAAKAOMXAA==.Androonatorz:BAACNQAFFH8UAAIKAAcK4xd6CgC1AQAKAAcK4xd6CgC1AQA1AAQKfzQAAwoACgrqIZcbAAcDAAoACgrqIZcbAAcDAAsACgp1EKR3AN8BAAAA.Anfernay:BAABNQAECn8nAAIJAAoKbxG+egAoAgAJAAoKbxG+egAoAgAAAA==.Antheion:BAAANQAECgYICAABNQAECggIQQAMAMkTAA==.Antiaxxis:BAAANQADCgEIAQAAAA==.',
Ap='Apawthetic:BAABNQAECn8bAAMNAAkKRiH5FwD2AgANAAkKRiH5FwD2AgAOAAQKiAZ48wCuAAABNQAFFAcIEwAPAHwRAA==.',
Aq='Aquadab:BAAANQADCgQICAAAAA==.',
Ar='Arashatora:BAAANQAECgEIAQABNQAECgMIBAAQAAAAAA==.Arcanodare:BAAANQADCggICAAAAA==.Arkalis:BAAANQAECgEIAQAAAA==.Arveiturace:BAABNQAECn8cAAIRAAUKGAbPGQCkAAARAAUKGAbPGQCkAAAAAA==.',
As='Ashborrn:BAAANQADCgUIBQAAAA==.Ashtar:BAABNQAECn8pAAIJAAkKrxA2jwD2AQAJAAkKrxA2jwD2AQAAAA==.Asukajo:BAAANQADCgMIAwAAAA==.',
At='Attack:BAAANQAECgcIDgAAAA==.',
Ax='Axhure:BAAANQABCgMIAgAAAA==.',
Ba='Babydoll:BAAANQAECgQICAAAAA==.Bajablast:BAAANQADCgcIDQAAAA==.Barma:BAAANQAECgYICQAAAA==.Barrin:BAABNQAECn8fAAIFAAoKuhysMAB+AgAFAAoKuhysMAB+AgAAAA==.',
Be='Bearlyseen:BAABNQAECn8sAAISAAkKSx9sBQDDAgASAAkKSx9sBQDDAgABNQAFFAUIEQANACgMAA==.Beltirra:BAAANQAECgMIBAAAAA==.',
Bh='Bhangbros:BAAANQADCgcIBwAAAA==.',
Bi='Biggums:BAAANQAECgMIBAAAAA==.Bigmobility:BAABNQAECn81AAIMAAoKeyIKCAB8AwAMAAoKeyIKCAB8AwAAAA==.Bigwill:BAABNQAECn9kAAIGAAoKkCHnAgAsAwAGAAoKkCHnAgAsAwAAAA==.',
Bl='Blargy:BAABNQAECn9EAAIPAAoKsBnlHQATAgAPAAoKsBnlHQATAgAAAA==.Bleach:BAABNQAECn8aAAMSAAgKIwlVNgCyAAATAAYKlQq7mgDWAAASAAYK/AZVNgCyAAAAAA==.Bluewaffles:BAAANQADCgUIBgABNQAECgMIAwAQAAAAAA==.',
Bo='Borealslam:BAAANQADCgQIBAAAAA==.Bouzol:BAAANQAECgYIBgAAAA==.',
Br='Brighterbonk:BAAANQAECgMIBAAAAA==.Brimara:BAAANQAECgUIDAAAAA==.Brothaagamor:BAAANQADCgIIAgAAAA==.Brunomirror:BAAANQAECgUIBQABNQAFFAcIFAAFAGcUAA==.',
Bu='Bucketojoy:BAABNQAECn8gAAIFAAoKNANA2QD5AAAFAAoKNANA2QD5AAAAAA==.Bunsen:BAAANQAECgQIBAABNQAECgoKKQANAHEcAA==.',
['Bà']='Bàtman:BAAANQAECgQICAABNQAECgUIDwAQAAAAAA==.',
['Bö']='Böop:BAAANQADCgYIBgABNQAECgUIDwAQAAAAAA==.',
Ca='Caliburne:BAABNQAECn8+AAQJAAoKOSBlIgC5AgAJAAoKnh9lIgC5AgAUAAUKhh+5FgC/AQAVAAMK6h4xGQAPAQAAAA==.Captamerica:BAAANQABCgQIBgAAAA==.Capz:BAACNQAFFH8YAAIJAAgKTxvCBACHAgAJAAgKTxvCBACHAgA1AAQKfyUAAgkACgqaJe8fADgDAAkACgqaJe8fADgDAAAA.',
Ce='Ceez:BAABNQAECn8sAAMJAAoKDhPWZQDPAQAJAAoKxQ7WZQDPAQAUAAQKFBu8IwDcAAAAAA==.Ceezinator:BAAANQAECgMIAwAAAA==.',
Ch='Chichujongar:BAABNQAECn8UAAQMAAcKwwsFbwA5AQAMAAcKcwsFbwA5AQAWAAYKwwUziwD3AAAXAAYKmgUcdADSAAABNQAFFAcIEwAYAM4OAA==.Chickenstwip:BAAANQADCgEIAgABNQAFFAQIBQAFALULAA==.Chopperr:BAAANQAECgUICQABNQAFFAQIBQAFALULAA==.Chosenöne:BAAANQADCgEIAQAAAA==.Chèn:BAAANQAECgcIEgAAAA==.',
Ci='Cindrella:BAABNQAECn89AAIGAAoKZCSXAADDAwAGAAoKZCSXAADDAwAAAA==.',
Cl='Clayre:BAACNQAFFH8aAAIZAAYKFRmMAACgAQAZAAYKFRmMAACgAQA1AAQKf2kAAhkACgoxJUQAAGUDABkACgoxJUQAAGUDAAAA.Clow:BAABNQAECn8VAAMJAAYKdCG1kABgAQAJAAYKzR+1kABgAQAVAAEKAR+dKwBXAAAAAA==.',
Co='Colossus:BAAANQAECgIIBAAAAA==.Coolcrush:BAAANQADCgUICAABNQAFFAQICwAaAK0ZAA==.Corven:BAACNQAFFH8TAAIEAAcKshQcDwCLAQAEAAcKshQcDwCLAQA1AAQKf1YABAQACgpcI64LAG8DAAQACgpcI64LAG8DABsAAQpJF7sqAEEAABkAAQpFBbiEACUAAAAA.',
Cr='Craziks:BAAANQADCgIIAgAAAA==.Critzwar:BAACNQAFFH8RAAIJAAcKphPsEACtAQAJAAcKphPsEACtAQA1AAQKfyUAAgkACgqZIWQxAPoCAAkACgqZIWQxAPoCAAAA.Crönus:BAAANQAECgIIAgAAAA==.',
Ct='Cthuluwu:BAAANQADCggICAAAAA==.',
Da='Daedyxes:BAABNQAECn8+AAIMAAoKhhU5HgAKAgAMAAoKhhU5HgAKAgAAAA==.Danrod:BAAANQAECgIIAgAAAA==.Daní:BAAANQADCgUIBwABNQAECgEIAQAQAAAAAA==.Darfur:BAABNQAECn8nAAIFAAoKhxqEMAB/AgAFAAoKhxqEMAB/AgAAAA==.Darkensi:BAAANQABCgYICQAAAA==.Dasherdeez:BAAANQAECgEIAQAAAA==.Daygath:BAAANQAECgEJAQAAAA==.',
De='Deadlyiris:BAABNQAECn83AAIJAAoKNR9wOgDcAgAJAAoKNR9wOgDcAgABNQAECgoKKQANAHEcAA==.Deadshot:BAAANQAECgQIDAAAAA==.Deatharin:BAAANQADCgUIBgAAAA==.Deathjak:BAAANQAECgcIDwABNQAECgoKOQAFAKkjAA==.Decompose:BAAANQADCgQIBAAAAA==.Demonbulio:BAABNQAECn8fAAICAAoKDQlNSgB7AQACAAoKDQlNSgB7AQAAAA==.Demonisthicc:BAABNQAECn85AAIcAAoKDB6cBgABAwAcAAoKDB6cBgABAwAAAA==.Demonskitten:BAAANQADCgUIBQABNQAECgoKOQAcAAweAA==.Demonslayeer:BAAANQADCggIDQAAAA==.Demoronicon:BAAANQAFFAEIAgAAAA==.Devi:BAAANQAECgYICwAAAA==.',
Di='Diaravynn:BAAANQADCgMIBQAAAA==.Diddylord:BAAANQAECgMIBAABNQAFFAQIBQAFALULAA==.Dithehealer:BAABNQAECn8yAAILAAoKmhYVkgAAAgALAAoKmhYVkgAAAgAAAA==.Divain:BAAANQADCgQIBgAAAA==.',
Dk='Dkdi:BAAANQAECgYIEQAAAA==.',
Do='Dozekar:BAAANQAECgEIAQAAAA==.',
Dr='Dragonlife:BAAANQAECgQIBAAAAA==.Drenamai:BAABNQAECn8YAAIdAAgKcxCamACDAQAdAAgKcxCamACDAQAAAA==.Drexywexyuwu:BAAANQADCgcJBwAAAA==.',
Du='Duhmptruhk:BAABNQAECn83AAMJAAoKFxk/TAAbAgAJAAoKrxg/TAAbAgAUAAIKtRI7MwB1AAAAAA==.Dunbroch:BAACNQAFFH8UAAIeAAcKlRm8BwDPAQAeAAcKlRm8BwDPAQA1AAQKfzUAAh4ACgolHncVALICAB4ACgolHncVALICAAAA.Duskfire:BAAANQADCgQIBAAAAA==.Duskforge:BAAANQABCgIJAgAAAA==.',
Dw='Dwagen:BAAANQAECgQIBAAAAA==.',
['Dé']='Démonicblood:BAACNQAFFH8TAAIXAAcKNB+gBQCoAQAXAAcKNB+gBQCoAQA1AAQKfzkAAhcACgp/IewMAPACABcACgp/IewMAPACAAAA.',
Eg='Eggplantgodx:BAABNQAECn82AAMBAAoKSSW1AgDrAgABAAkKSSW1AgDrAgACAAgKKRlqLwArAgAAAA==.',
Ek='Ekhart:BAAANQAECgEIAQAAAA==.',
El='Elfajah:BAAANQADCgYICQAAAA==.Eliicia:BAACNQAFFH8SAAMSAAcKrwyBCACGAQASAAYKYg6BCACGAQATAAEK5AUQJgBRAAA1AAQKfy4AAxIACgpbILQYALcCABIACgpbILQYALcCABMACQpeDIAyACgBAAAA.',
Em='Emmy:BAAANQAECgQIDwAAAA==.Emofineshyt:BAAANQADCgcICgAAAA==.Emogothbabe:BAACNQAFFH8FAAMFAAQKtQuOPACDAAAFAAMKMAyOPACDAAAGAAEKvwrKFgBCAAA1AAQKfzsAAwUACgq0HZs/AE4CAAUACgq0HZs/AE4CAAYAAwrzDlEsAJkAAAAA.Emowrecky:BAABNQAECn8mAAMEAAgKbx0GYwAwAgAEAAgKbx0GYwAwAgAZAAEKjA7gNQA7AAAAAA==.',
En='Endo:BAACNQAFFH8QAAMWAAcKIRuuCgBlAQAWAAUKGh6uCgBlAQAXAAQKBhYtEQDMAAA1AAQKf0MAAxYACgoLJU0SACUDABYACQooJU0SACUDABcACAoIIiItADYCAAAA.Endorush:BAABNQAECn83AAMCAAoKfiBaFwBeAgACAAoKJiBaFwBeAgADAAcK5RziHwCiAQABNQAFFAcIEAAWACEbAA==.Endrigosa:BAAANQAECgUIBgAAAA==.Eneldenes:BAAANQAECgUICwAAAA==.Enjoyer:BAAANQAECgcIDgAAAA==.',
Er='Ereitherla:BAABNQAECn89AAIdAAgKKgs1oQBxAQAdAAgKKgs1oQBxAQAAAA==.Erodrine:BAAANQABCgMIBAAAAA==.',
Es='Esmenet:BAAANQAECgYIEAAAAA==.Espressð:BAABNQAECn86AAIHAAoK/SHcCQCbAwAHAAoK/SHcCQCbAwABNQAFFAQIBQAFALULAA==.',
Ex='Excalibear:BAABNQAECn8fAAIKAAoKYBvPJQCZAgAKAAoKYBvPJQCZAgABNQAFFAUIEQANACgMAA==.',
Ey='Eydis:BAAANQADCgcIDgAAAA==.Eyepisspeas:BAAANQABCgMIBAAAAA==.',
Fe='Feironor:BAAANQAECgUIBwAAAA==.Fenrys:BAAANQAECgQICAAAAA==.',
Fi='Fikareous:BAAANQADCggIDQABNQAECgUIBQAQAAAAAA==.',
Fl='Flayre:BAABNQAECn8oAAMNAAkK3RtQRQBMAgANAAgK3BtQRQBMAgAOAAcKMBcNaADoAQAAAA==.Fleredil:BAABNQAECn9DAAMfAAoKECKtBwDvAgAfAAoKECKtBwDvAgAHAAEKgQXG/gAuAAAAAA==.Flingernle:BAABNQAECn86AAIOAAoKvySrBABeAwAOAAoKvySrBABeAwAAAA==.',
Fo='Forepray:BAACNQAFFH8QAAIfAAUKVA2NCwAzAQAfAAUKVA2NCwAzAQA1AAQKf0EAAh8ACgpWIKUJAEUDAB8ACgpWIKUJAEUDAAAA.Forger:BAABNQAECn8sAAMUAAkKDAwtGwCGAQAUAAkKDAwtGwCGAQAJAAIKQQjVOQFhAAAAAA==.Forsakey:BAAANQADCggIFAABNQAFFAcIDgAgAGIWAA==.',
Fr='Fraun:BAAANQADCggIEQAAAA==.Freshdk:BAAANQAECgQIBAAAAA==.',
Fu='Fullyprotpal:BAAANQAECgEIAQAAAA==.Funbagz:BAAANQAECgUICQAAAA==.Furioustotem:BAABNQAECn85AAIOAAgKcxdyVwCBAQAOAAgKcxdyVwCBAQAAAA==.Future:BAAANQADCgUIBgABNQAECgkJLAAFAMQjAA==.',
Fy='Fycat:BAAANQAECggICgABNQAFFAQIDAAEANkfAA==.',
Ga='Galten:BAAANQADCgUIBQAAAA==.Gantz:BAAANQADCgIJAgAAAA==.',
Ge='Geekbarr:BAAANQADCgUIBQABNQAFFAQIBQAFALULAA==.',
Gh='Ghettox:BAAANQADCgYIEQAAAA==.Ghostw:BAABNQAECn8WAAIJAAYKux1OkQBeAQAJAAYKux1OkQBeAQAAAA==.',
Gi='Giovanni:BAAANQAECggICAAAAA==.Gizik:BAAANQADCgcIDQABNQAFFAkJGwAfANMPAA==.',
Gn='Gnasher:BAAANQABCgQIBAAAAA==.',
Go='Golgotterath:BAACNQAFFH8RAAINAAUKKAwODwBeAQANAAUKKAwODwBeAQA1AAQKfz0AAw0ACgpNIYMbANwCAA0ACgpNIYMbANwCAA4AAQqNB/I6ATAAAAAA.Goreshade:BAAANQAECgIIAgAAAA==.Gorm:BAABNQAECn80AAIFAAoKnBywVgDTAgAFAAoKnBywVgDTAgABNQAECgQIBQAQAAAAAA==.',
Gr='Grippyshocks:BAAANQAECgIIAQABNQAECgoKKwACANsgAA==.',
Ha='Halbruck:BAAANQAECgcIEQAAAA==.Haldane:BAABNQAECn8zAAILAAkKRArN0AB6AQALAAkKRArN0AB6AQABNQAECgoKKQANAHEcAA==.Harrydottur:BAAANQAECggIDQABNQAFFAUIEQAEAAYcAA==.Havochunter:BAABNQAECn8XAAIdAAkKJhXrcwDXAQAdAAkKJhXrcwDXAQAAAA==.Hawley:BAAANQABCgIIAgAAAA==.',
He='Heidegger:BAAANQADCgYICgAAAA==.Helinndealin:BAACNQAFFH8VAAIhAAcKwhqtAADoAQAhAAcKwhqtAADoAQA1AAQKfy4AAyEACgrEJFQBAEcDACEACQryJFQBAEcDAAcACAotIsZJAEgCAAAA.Hellin:BAAANQADCgMIAQAAAA==.Heolstor:BAABNQAECn9DAAIMAAoKBR6DEwB1AgAMAAoKBR6DEwB1AgAAAA==.Hephsdh:BAAANQAECggIDwAAAA==.Heraois:BAABNQAECn8iAAIeAAoKtgmsNgCZAQAeAAoKtgmsNgCZAQAAAA==.',
Hg='Hgshake:BAAANQADCgYIBgAAAA==.',
Ho='Holytës:BAAANQAECgYIEQAAAA==.Holywráth:BAAANQAECgQIDQAAAA==.',
Hu='Hunterdh:BAABNQAECn83AAIdAAoKKwjEfgC9AQAdAAoKKwjEfgC9AQAAAA==.',
Hy='Hynixx:BAABNQAECn8wAAMVAAoKqxsdCQBKAgAVAAkKphodCQBKAgAJAAcKjRi/gQCDAQABNQAFFAUIEAAfAFQNAA==.',
Il='Illidope:BAABNQAECn8rAAQCAAoK2yDcFQDuAgACAAoKSyDcFQDuAgADAAgK+xwZIwAxAgABAAMK5SP1GADSAAAAAA==.',
In='Infinitevoid:BAAANQADCggIFQAAAA==.Infliximab:BAAANQAECggIEAAAAA==.Innervatez:BAABNQAFFH8LAAIgAAUKJCMuBADuAQAgAAUKJCMuBADuAQAAAA==.Inteaus:BAAANQADCggIGgAAAA==.',
Io='Ionúin:BAAANQADCgQJBAAAAA==.',
Iv='Ivÿ:BAAANQADCgMIBQABNQAECgUIDwAQAAAAAA==.',
Ja='Jabkhan:BAABNQAECn8VAAIPAAYKwwHpfABPAAAPAAYKwwHpfABPAAAAAA==.Jaekir:BAABNQAECn8oAAIGAAoK6xORCwAHAgAGAAoK6xORCwAHAgAAAA==.Jakfrost:BAABNQAECn85AAMFAAoKqSMYQABNAgAFAAkK6iMYQABNAgAGAAMKKiLkGgAcAQAAAA==.Jakie:BAAANQADCgYICgABNQAECggIFwAJAN8aAA==.Jarten:BAACNQAFFH8RAAIXAAcKOxgTBwB8AQAXAAcKOxgTBwB8AQA1AAQKf0oAAhcACgp/IcwOAN0CABcACgp/IcwOAN0CAAAA.Jayaah:BAAANQAECgMIBAAAAA==.Jaylebate:BAABNQAECn8aAAMWAAgKrxkKJwCpAQAWAAgK9xcKJwCpAQAMAAYKbxpcXACBAQAAAA==.',
Je='Jerrenn:BAAANQAECgQIBAAAAA==.Jesseatamer:BAACNQAFFH8RAAIdAAcKRiHkAwDIAQAdAAcKRiHkAwDIAQA1AAQKf0oAAh0ACgqvJY8FAGIDAB0ACgqvJY8FAGIDAAAA.',
Ji='Jigme:BAAANQAECgMIAwAAAA==.Jitsuru:BAAANQADCgUIBQAAAA==.',
Jo='Jox:BAAANQABCgUIBQAAAA==.Joxor:BAAANQABCgUIBQAAAA==.',
Js='Jstdeath:BAAANQADCgEIAQABNQAECgoKNQAJAHEVAA==.Jstrawr:BAABNQAECn81AAIJAAoKcRVvYgBnAgAJAAoKcRVvYgBnAgAAAA==.Jsttotem:BAAANQAECgUIBQABNQAECgoKNQAJAHEVAA==.',
Ka='Kalmek:BAABNQAECn8VAAMWAAkKLw06MgBdAQAWAAkKkAw6MgBdAQAXAAIKMQaYuQAuAAAAAA==.Kaln:BAAANQAECgIIBwABNQAECgQIBQAQAAAAAA==.Karen:BAAANQAECgUIDgAAAA==.Kasalu:BAAANQABCgQIBAAAAA==.Kasanzzar:BAAANQAECgYIBwAAAA==.Kastia:BAAANQAECgQICQAAAA==.Kasumï:BAAANQAECgEIAgABNQAFFAYIEgAdAD4gAA==.Katrynwel:BAAANQAECgQIBAAAAA==.Katsumi:BAAANQAECgQICwAAAA==.',
Ke='Keliki:BAABNQAECn88AAMNAAoKOB47FAAVAwANAAoKOB47FAAVAwAOAAgKzhigQQBvAgAAAA==.Kellenah:BAAANQAECgMIAwAAAA==.Kettama:BAAANQAECgUIBQABNQAFFAQIBQAFALULAA==.',
Kh='Khold:BAABNQAECn8xAAMXAAoKDRvPKgAJAgAXAAoKDRvPKgAJAgAMAAQKBw6mcgCKAAAAAA==.Khrogann:BAAANQAECggIEQAAAA==.',
Ki='Kijana:BAAANQADCggICAAAAA==.Killalltoday:BAABNQAECn8tAAINAAoKmA99aQDQAQANAAoKmA99aQDQAQAAAA==.Killersmile:BAAANQADCgQIBAAAAA==.Kirkk:BAAANQAECgMIBAAAAA==.',
Kl='Klaminus:BAAANQADCgQIBAABNQAECgMIAwAQAAAAAA==.',
Kn='Knixx:BAACNQAFFH8UAAIHAAcKIBEIEACUAQAHAAcKIBEIEACUAQA1AAQKf1gAAwcACgrvJesAAOQDAAcACgrvJesAAOQDACEABgrzEYsPADIBAAAA.Knuppelus:BAAANQADCgYIDAAAAA==.',
Ko='Kobyashimaru:BAAANQADCgUIBQAAAA==.Koshi:BAAANQADCgMIAwAAAA==.Kotastrophe:BAAANQAECgMIAwABNQAECgoKNwAJABcZAA==.Kotastrophic:BAAANQAECgUIBQAAAA==.Koveras:BAAANQADCgYIBwAAAA==.Koyaanis:BAAANQADCggIDgAAAA==.Koyya:BAABNQAECn82AAMaAAoKnA03FAAlAgAaAAkK5Ao3FAAlAgANAAoKXhN8VQC9AQAAAA==.',
Kr='Krathos:BAAANQAECgUIEAAAAA==.Krenmonk:BAAANQAECgEIAQAAAA==.Krennic:BAAANQADCgcIBwAAAA==.Krunchee:BAAANQAECgUIDAAAAA==.',
Ku='Kufoo:BAABNQAECn9AAAMVAAoK5SWHAABzAwAVAAoK5SWHAABzAwAUAAEKkx6zOwBRAAAAAA==.Kurao:BAAANQAECgMIBQAAAA==.Kurukai:BAAANQADCgMIAwAAAA==.',
Ky='Kyrian:BAACNQAFFH8gAAMTAAgK8yBiAQBaAgATAAgK8yBiAQBaAgASAAMKvREHEADrAAA1AAQKfzYAAxMACgrcIygFADgDABMACgrcIygFADgDABIAAwpZHHlvAPMAAAAA.',
La='Lagøless:BAABNQAECn8jAAIdAAoKHSMhEwBTAwAdAAoKHSMhEwBTAwAAAA==.',
Le='Leo:BAAANQAECgEIAQAAAA==.',
Li='Liatris:BAAANQAECgUIBQAAAA==.Likestoflash:BAEANQADCgYIBgABNQAECgoKSQAdAIweAA==.Lissaris:BAAANQADCgEIAgAAAA==.',
Lo='Lohal:BAABNQAECn89AAIEAAoKVBnPNwAyAgAEAAoKVBnPNwAyAgAAAA==.Lohmi:BAABNQAECn8aAAIOAAkKzgbebQA+AQAOAAkKzgbebQA+AQAAAA==.Lormn:BAAANQADCgEIAQAAAA==.',
Lu='Luania:BAAANQAECgQICQAAAA==.',
Ly='Lyna:BAAANQADCggIDAAAAA==.Lyshkä:BAABNQAECn8xAAIiAAoKaBpAEAB7AgAiAAoKaBpAEAB7AgAAAA==.Lyzzardkng:BAABNQAECn80AAILAAoKuwnqqQB7AQALAAoKuwnqqQB7AQAAAA==.',
['Lý']='Lýra:BAAANQAECgQIBwAAAA==.',
Ma='Maango:BAABNQAECn8pAAILAAoKph5pMgCZAgALAAoKph5pMgCZAgAAAA==.Maemu:BAAANQABCgUIBwAAAA==.Magerthat:BAAANQADCgQIBgAAAA==.Magicaltickl:BAABNQAECn8jAAIFAAoKZg2obwDSAQAFAAoKZg2obwDSAQAAAA==.Magiki:BAAANQADCgcICwAAAA==.Makyaihua:BAAANQABCggIHAAAAA==.Malkala:BAAANQADCgMIAwAAAA==.Malonormu:BAAANQABCgcIBgAAAA==.Mamadeezy:BAAANQADCgYJCwAAAA==.Manalisa:BAAANQAECgQIBAAAAA==.Mando:BAAANQAECgUIEAABNQAECggIOAAjACcaAA==.Manical:BAAANQAECgMICwAAAA==.Marcel:BAAANQADCgYIEQABNQAECgMIBAAQAAAAAA==.Martinikiss:BAAANQAECgcIEAAAAA==.Mashiach:BAACNQAFFH8MAAIHAAYKDBugDADBAQAHAAYKDBugDADBAQA1AAQKfysAAwcACgpTIdgPAEcDAAcACgpTIdgPAEcDAB8AAQoAALx4ADYAAAAA.Matthyjsz:BAAANQADCgIIAgAAAA==.',
Me='Megumin:BAAANQAECgYICgABNQAECgoKOQALABgkAA==.Melikefire:BAABNQAECn8hAAIFAAoKURZXmgBMAgAFAAoKURZXmgBMAgAAAA==.Melodious:BAAANQAECgEIAQAAAA==.Memecompdall:BAAANQAECgIIAgAAAA==.Merek:BAABNQAECn8oAAIYAAoKaB0JBwDSAgAYAAoKaB0JBwDSAgAAAA==.Mettix:BAAANQADCgIIAgAAAA==.',
Mi='Mirigosa:BAAANQAECgEIAQABNQAECgoKPQAGAGQkAA==.Mistybdk:BAABNQAECn89AAIMAAoK/hmgFABoAgAMAAoK/hmgFABoAgABNQAFFAgIHAAkABIYAA==.Mistyd:BAACNQAFFH8cAAIkAAgKEhiIAABGAgAkAAgKEhiIAABGAgA1AAQKf2IAAiQACgqzJYgBAG4DACQACgqzJYgBAG4DAAAA.',
Mo='Mogfooyen:BAAANQABCgYICQAAAA==.Moonbeam:BAAANQAECgUIBgAAAA==.Morgause:BAABNQAECn8eAAIEAAYKhgdhsQDxAAAEAAYKhgdhsQDxAAABNQAECgoKJQAPAL4HAA==.Morllan:BAABNQAECn8oAAIEAAoK9w0qggDgAQAEAAoK9w0qggDgAQAAAA==.',
Mu='Muirdin:BAAANQADCgEIAQAAAA==.',
My='Mykinlive:BAAANQADCgIIAgAAAA==.',
['Má']='Mááââybèèëëè:BAAANQADCgEIAQAAAA==.',
['Må']='Mångix:BAAANQAECgQIBAAAAA==.',
['Mé']='Mélusine:BAABNQAECn8ZAAMJAAkKURJ5igABAgAJAAkKpw95igABAgAVAAQKrRB2HQDYAAAAAA==.',
Na='Naanomage:BAAANQAECgYIDQAAAA==.Nagakabouros:BAAANQABCgIIAgAAAA==.Naija:BAAANQADCgIIAgAAAA==.Narcotx:BAAANQADCgIIAgAAAA==.',
Ne='Necrotoxin:BAAANQADCgYIBgAAAA==.',
Ni='Nightmaratic:BAAANQADCgYIBgAAAA==.Nightsdeath:BAAANQAECgEIAQAAAA==.Nightsever:BAABNQAECn8nAAIDAAkKwSJIBwBeAwADAAkKwSJIBwBeAwAAAA==.Nirath:BAABNQAECn8tAAIRAAoKwQWeIABOAQARAAoKwQWeIABOAQAAAA==.',
No='Noiire:BAABNQAECn8bAAIdAAkKpBQAXQAOAgAdAAkKpBQAXQAOAgABNQAFFAcIEgASAK8MAA==.',
Od='Odysse:BAAANQADCgYICQAAAA==.Odyssé:BAABNQAECn8mAAIdAAoKqR3UIQAQAwAdAAoKqR3UIQAQAwAAAA==.',
Oi='Oio:BAAANQAECggIAgAAAA==.',
Ok='Okami:BAABNQAECn8iAAIjAAYKUR4gIwCCAQAjAAYKUR4gIwCCAQAAAA==.',
On='Onehotelf:BAAANQAECgQIBAAAAA==.',
Oo='Ooyagoddess:BAAANQAECggIDAAAAA==.',
Or='Orienn:BAAANQAECgQIAgAAAA==.',
Pa='Pacamonk:BAABNQAECn9EAAIjAAoKFB8sDQAIAwAjAAoKFB8sDQAIAwAAAA==.Palenar:BAAANQADCgQIBAAAAA==.Papatiny:BAAANQAECgcIEAAAAA==.Papábear:BAAANQADCgQIBAAAAA==.Pawsa:BAABNQAECn8WAAMYAAgKfhyaDQAgAgAYAAcKnSCaDQAgAgAjAAYKmw1DMAAZAQABNQAFFAQIBQAFALULAA==.Pawthetic:BAACNQAFFH8TAAQPAAcKfBFdEgBEAQAPAAUK5RRdEgBEAQAgAAEKVw6PFABNAAAcAAEK2AP6BABAAAA1AAQKf0wAAyAACgqJI6kDAMUDACAACgqJI6kDAMUDAA8ACgpfIAMMAOICAAAA.',
Pe='Peelforheals:BAACNQAFFH8FAAIfAAMKLAcGFACMAAAfAAMKLAcGFACMAAA1AAQKfzMAAx8ACgqkHpwOAAYDAB8ACgqkHpwOAAYDACEABQpdDHsXALoAAAAA.Penguindemic:BAABNQAECn86AAQEAAoKVSWaBgCaAwAEAAoKVSWaBgCaAwAbAAMKlSHfEAAoAQAZAAEKoCISagBNAAAAAA==.Pep:BAABNQAECn8UAAIjAAkKhQpJPAAzAQAjAAkKhQpJPAAzAQAAAA==.Pepperoni:BAAANQADCggIDQAAAA==.Perdator:BAAANQAECgQICAAAAA==.Petruccius:BAACNQAFFH8hAAIPAAUK4BW7EQDpAAAPAAUK4BW7EQDpAAA1AAQKf20AAg8ACgrbIFEMAGgDAA8ACgrbIFEMAGgDAAAA.Pewpewlepew:BAAANQAECgQICQAAAA==.',
Ph='Phaeku:BAAANQADCgMIAwAAAA==.',
Pi='Picklebreath:BAAANQADCgUICgAAAA==.Pinksparklez:BAAANQADCgUICAABNQAECgEIAQAQAAAAAA==.',
Pl='Plague:BAAANQAECgMIAwAAAA==.',
Po='Ponglenis:BAAANQAECgIIAgAAAA==.Poptartsz:BAAANQAECgQICQAAAA==.Potatolockx:BAAANQAECgQIAwAAAA==.',
Pr='Prayre:BAABNQAECn8mAAMHAAoKpw56SQASAgAHAAoKpw56SQASAgAfAAUKYApsOQDQAAAAAA==.Precht:BAAANQAECgMIBAAAAA==.Prikarea:BAAANQAECgUIBQAAAA==.Prospa:BAAANQAECgUICQABNQAFFAQIBQAFALULAA==.Prumper:BAABNQAECn8oAAIFAAoKVhBZhACgAQAFAAoKVhBZhACgAQAAAA==.Príest:BAAANQAECggICAAAAA==.',
Pu='Purah:BAAANQADCgEIAgAAAA==.',
['Pä']='Päncake:BAAANQAECgUIDwAAAA==.',
Qh='Qhiraji:BAAANQADCgUIBQAAAA==.',
Qu='Quesoblanco:BAABNQAECn8lAAMLAAoKaQ44ygBCAQALAAoKgAg4ygBCAQAlAAUKKhkxOwAXAQAAAA==.',
Qy='Qybxboogietk:BAABNQAECn8jAAICAAkK8hSDMQAdAgACAAkK8hSDMQAdAgAAAA==.',
Ra='Rabid:BAAANQAECgQIDAAAAA==.Raeliana:BAAANQADCgQIBAAAAA==.Raghallov:BAABNQAECn8UAAIKAAgKpRJ4VwC4AQAKAAgKpRJ4VwC4AQAAAA==.Rampa:BAAANQADCgYIEQABNQAFFAQIBQAFALULAA==.',
Re='Reaperan:BAAANQAECgEIAQAAAA==.Regena:BAABNQAECn9dAAQHAAoKHRjiIgDNAgAHAAoKHRjiIgDNAgAhAAIK5Q7VEQBsAAAfAAMKOQKLagBYAAAAAA==.Rekriss:BAAANQADCgYIBgAAAA==.Remorse:BAACNQAFFH8SAAIUAAYKZRKNAgBrAQAUAAYKZRKNAgBrAQA1AAQKf0MAAhQACgpeIWYGAAADABQACgpeIWYGAAADAAAA.Rendwick:BAAANQADCgYICQAAAA==.Required:BAABNQAECn8bAAIeAAkKvRMoEwAQAgAeAAkKvRMoEwAQAgABNQAFFAcIFAACAOQhAA==.Retpaladin:BAAANQADCggICAAAAA==.',
Ri='Rikahoe:BAAANQAECgUIBQABNQAECgUIBQAQAAAAAA==.Riker:BAAANQADCgQIBAABNQAECgMIBAAQAAAAAA==.Rim:BAABNQAECn9HAAINAAoKPR/uGADuAgANAAoKPR/uGADuAgAAAA==.',
Ro='Rockandshock:BAAANQAECgQIBAABNQAECgoKKwACANsgAA==.Rocketbunny:BAAANQADCgUICAAAAA==.Ronfar:BAACNQAFFH8SAAIaAAYKohacAgAXAQAaAAYKohacAgAXAQA1AAQKf3AAAxoACgpmI9cCAHgDABoACgpmI9cCAHgDAA4ACgqDGP4mAEkCAAAA.Rootx:BAAANQAECgMIAwABNQAFFAgIJwAPANciAA==.',
Ru='Rukidingme:BAAANQAECgQIBAAAAA==.Rustyglass:BAAANQABCgYIBAAAAA==.Ruttisðir:BAAANQAECgIIAwAAAA==.',
Ry='Ryhorn:BAAANQADCggIDgAAAA==.Ryno:BAAANQADCgUIBwAAAA==.Ryujin:BAABNQAECn8bAAILAAoK7QkvyQCJAQALAAoK7QkvyQCJAQAAAA==.Ryù:BAAANQAECgQICgAAAA==.',
Sa='Salo:BAAANQADCgMIBgAAAA==.Salòme:BAAANQAECgQICQABNQAECgoKJAAdACgMAA==.Sanazenet:BAAANQADCggJDAAAAA==.Saphiriel:BAAANQAECgMIBQAAAA==.Saviorself:BAAANQADCgMIAwABNQAFFAcIEwAPAHwRAA==.',
Sc='Scarscar:BAAANQAECggIDAAAAA==.Schwinn:BAAANQADCgQIBAAAAA==.Scracky:BAAANQAECggIDAAAAA==.',
Se='Segarth:BAABNQAECn8kAAMOAAoKmxYOMgAPAgAOAAoKmxYOMgAPAgANAAQKkRB8xADfAAAAAA==.Selen:BAAANQAECgcIEQAAAA==.Semballin:BAABNQAECn8VAAINAAcKzRKNZgCCAQANAAcKzRKNZgCCAQAAAA==.Seråphiel:BAAANQAECgQICQAAAA==.Seswatha:BAAANQAECgYICAABNQAFFAUIEQANACgMAA==.',
Sh='Shamandroo:BAABNQAECn8YAAINAAkK0Bo7JwDHAgANAAkK0Bo7JwDHAgABNQAFFAcIFAAKAOMXAA==.Shamdi:BAAANQADCgYIBgAAAA==.Shanghaied:BAAANQADCgcIDAAAAA==.Shawtyy:BAAANQADCgMIAwAAAA==.Shmongus:BAAANQADCgIIAgABNQAECgcIDgAQAAAAAA==.Shortandold:BAABNQAECn8kAAMTAAoKog39SQDYAQATAAoKog39SQDYAQASAAEKagPjZwAwAAAAAA==.Shådowfire:BAAANQAECgEIAQAAAA==.Shìft:BAABNQAECn87AAIgAAoKbhyZEwCvAgAgAAoKbhyZEwCvAgAAAA==.',
Si='Sightofhand:BAAANQADCgQIBAAAAA==.Sintram:BAAANQAECgMIAwAAAA==.',
Sl='Slighted:BAAANQAECgMIBgABNQAECgoKFwAUACIJAA==.Slimydruid:BAABNQAECn8UAAIkAAoKEB7vCACzAgAkAAoKEB7vCACzAgAAAA==.Slow:BAABNQAECn8sAAIFAAkKxCPCHABkAwAFAAkKxCPCHABkAwAAAA==.',
Sm='Smokinontech:BAAANQADCgQIBAABNQAFFAQIBQAFALULAA==.Smokze:BAAANQADCggJCAAAAA==.',
So='Sockoh:BAABNQAECn8XAAQFAAgK5A9TvwAGAgAFAAgKtw5TvwAGAgAGAAIK2xXrLwCBAAAmAAEKmwb2DQAzAAAAAA==.Sonicberger:BAAANQAECgUICAABNQAECgoKNwAMACgdAA==.Sonicbergger:BAAANQADCgQIBAABNQAECgoKNwAMACgdAA==.Sonicoberg:BAAANQAECgUIDQABNQAECgoKNwAMACgdAA==.Soniko:BAABNQAECn8XAAIUAAoKIgkeHgBkAQAUAAoKIgkeHgBkAQAAAA==.Sonícberger:BAABNQAECn83AAMMAAoKKB2PFABpAgAMAAoKKB2PFABpAgAWAAMKTBcJvAB0AAAAAA==.Soulcaliber:BAAANQAECgMIBAAAAA==.Sovious:BAAANQADCgYIBQAAAA==.',
Sq='Squizzy:BAAANQAECgIIAgAAAA==.',
St='Stain:BAAANQAECgUICAAAAA==.Stealth:BAAANQAECgQIBAABNQAECgoKKwAbAOYZAA==.Stinkfist:BAAANQADCggIHQAAAA==.Stonehenge:BAABNQAECn8pAAINAAoKcRw2GQDsAgANAAoKcRw2GQDsAgAAAA==.Stonepalm:BAAANQADCgcINQAAAA==.Stratan:BAAANQAECgMIAwAAAA==.Strawk:BAABNQAECn8kAAIOAAkKXA1nUwCNAQAOAAkKXA1nUwCNAQAAAA==.Stürm:BAAANQAECgMIAwABNQAECgoKMQAiAGgaAA==.',
Su='Subbzero:BAAANQADCgQIBAAAAA==.Suffer:BAAANQADCggICQABNQAECgkJLAAFAMQjAA==.Sunlight:BAAANQAECgcICQAAAA==.Supercat:BAAANQAECgEIAQAAAA==.Surf:BAAANQAECgUIDwAAAA==.',
Sw='Swankydranky:BAACNQAFFH8TAAQYAAcKzg7uBQAQAQAYAAUKKQbuBQAQAQAjAAUK+AcmCwAFAQAiAAIKVACODQApAAA1AAQKfzQABBgACgpHF20SAL4BABgACAoQE20SAL4BACMACgomFVYtAC8BACIAAgphBMZIAEYAAAAA.Swankyorcs:BAABNQAECn8VAAIGAAoKxQ/jCwDfAQAGAAoKxQ/jCwDfAQABNQAFFAcIEwAYAM4OAA==.Swankypally:BAAANQAECggICwABNQAFFAcIEwAYAM4OAA==.',
Sy='Syesc:BAAANQABCgQJBAAAAA==.Sylandris:BAAANQADCgIIAgAAAA==.Sympathy:BAABNQAECn8eAAIlAAoKDhvkCwB1AgAlAAoKDhvkCwB1AgAAAA==.',
['Sá']='Sásukeuchiha:BAAANQAECgUICgABNQAECgoKJAAdACgMAA==.',
Ta='Tabbz:BAABNQAECn8mAAIOAAoKyRh5MQC1AgAOAAoKyRh5MQC1AgAAAA==.Tallael:BAACNQAFFH8GAAIaAAMKEw7sAwDgAAAaAAMKEw7sAwDgAAA1AAQKf1UAAhoACgoSHLYHAKwCABoACgoSHLYHAKwCAAAA.Tallyhochick:BAABNQAECn85AAIdAAoKHA4TcQDeAQAdAAoKHA4TcQDeAQAAAA==.Taman:BAABNQAECn8fAAINAAgKNx1lQABeAgANAAgKNx1lQABeAgAAAA==.Tayam:BAAANQAECgUIBQAAAA==.Taylerswift:BAAANQAECgEJAQAAAA==.',
Th='Thebestname:BAABNQAECn8ZAAMkAAkKIAmlMQARAQAkAAgKEAalMQARAQAgAAEKhxArdQA1AAAAAA==.Thebigonion:BAAANQAECgcICAAAAA==.Theexile:BAABNQAECn8oAAMSAAoKghduKwA7AgASAAkKixZuKwA7AgATAAcKcBe8IQC+AQAAAA==.Theigh:BAAANQAECgEIAQAAAA==.Thonard:BAAANQAECggIJAABNQAECgoKiwAXAPQlAQ==.',
Ti='Tinydeath:BAABNQAECn8fAAIMAAgKwhUsSgDPAQAMAAgKwhUsSgDPAQABNQAECgkJLAAdACAdAA==.Tinyfu:BAAANQADCgQIBAAAAA==.Tinytamer:BAABNQAECn8sAAMdAAkKIB0OUwAmAgAdAAkKyBwOUwAmAgAnAAMKRRIbDgDMAAAAAA==.',
Tm='Tmakrist:BAAANQAECgIIBgAAAA==.',
To='Toko:BAACNQAFFH8NAAIdAAYKZBk5CQC1AQAdAAYKZBk5CQC1AQA1AAQKf0IAAh0ACgrAJR0HAFQDAB0ACgrAJR0HAFQDAAAA.Tomblord:BAABNQAECn8bAAMXAAkKgAkoUgBoAQAXAAkKYgkoUgBoAQAMAAYKuAUshQDoAAAAAA==.',
Tr='Trailblazah:BAAANQAECgUICgAAAA==.Treeheals:BAAANQADCggICAAAAA==.Truthes:BAAANQADCgYIBwABNQAECgoKKwAbAOYZAA==.Truths:BAAANQADCgIJAgABNQAECgoKKwAbAOYZAA==.Truthsx:BAABNQAECn8rAAMbAAoK5hn6AwCpAgAbAAoK5hn6AwCpAgAEAAcKEw094gAEAQAAAA==.Truthy:BAAANQADCgYICAABNQAECgoKKwAbAOYZAA==.Truthz:BAAANQAECgIIAwABNQAECgoKKwAbAOYZAA==.',
Ts='Tsukúne:BAAANQADCgQIBAAAAA==.',
Ty='Tyg:BAAANQADCggIFQAAAA==.Tylaatape:BAABNQAECn8sAAQMAAgK+RrkKAC4AQAMAAcK+RrkKAC4AQAWAAcK5AWLgAAbAQAXAAgKnw3bZQAEAQAAAA==.Tyraell:BAAANQAECggIEQAAAA==.',
['Tõ']='Tõkó:BAAANQADCgUIBQABNQAFFAYIDQAdAGQZAA==.',
Um='Umbrae:BAAANQADCgMIAQAAAA==.Umfray:BAAANQAECgIIAwABNQAECgYIFQAJAHQhAA==.',
Us='Usgasdanelv:BAACNQAFFH8FAAIaAAIKWw1OBgCRAAAaAAIKWw1OBgCRAAA1AAQKfyIAAxoACgqhGc4MAKECABoACgqhGc4MAKECAA0AAQq4A0AFASkAAAAA.',
Uz='Uzala:BAABNQAECn8wAAIEAAcKEQqspQAKAQAEAAcKEQqspQAKAQAAAA==.',
Va='Vanleiden:BAAANQADCgEIAQAAAA==.Vazro:BAABNQAECn9LAAMKAAoKoxpCHADXAgAKAAoKoxpCHADXAgALAAYKLQZiFAH9AAAAAA==.',
Ve='Vendiyre:BAAANQAECggICwAAAA==.Venthyl:BAACNQAFFH8KAAIPAAcK7R4vDQCYAQAPAAcK7R4vDQCYAQA1AAQKfzcAAw8ACgp4JvkHABoDAA8ACgqbJPkHABoDABwABQquJQ8RALYBAAAA.Veyra:BAAANQABCgMIAwAAAA==.',
Vi='Vindictina:BAAANQABCgMIAwAAAA==.Vizan:BAAANQABCgcIBwABNQAECgoKKwAbAOYZAA==.',
Wa='Warzone:BAAANQADCgUIBQAAAA==.',
We='Wellby:BAAANQAECgMIAwAAAA==.Westerin:BAABNQAECn8xAAIZAAoK3xP4BAC2AQAZAAoK3xP4BAC2AQAAAA==.',
Wi='Wildnature:BAAANQADCggIDgAAAA==.Wildwest:BAAANQADCggIDwAAAA==.Wimateeka:BAABNQAECn88AAQlAAoKSR73EAAbAgAlAAkKqh/3EAAbAgALAAoKJxLhlgD2AQAKAAMKtArk6QBFAAAAAA==.Windfury:BAAANQAECgYICAABNQAECgkJLAAFAMQjAA==.Windigo:BAAANQAECgIIAgAAAA==.Winginit:BAAANQAECgEIAQABNQAFFAcIEwAPAHwRAA==.',
Wr='Wrastelas:BAAANQADCggICAAAAA==.',
Wu='Wuilhem:BAAANQADCgEIAQAAAA==.Wurkim:BAAANQADCgQIBAABNQADCggICAAQAAAAAA==.',
Xa='Xaala:BAAANQAECgQIBQAAAA==.',
Xo='Xosderdk:BAAANQADCgIIAgAAAA==.',
Ya='Yarjuul:BAAANQAECgIIAgABNQAECgYIFQAJAHQhAA==.',
Ye='Yespaladin:BAACNQAFFH8WAAIMAAYK9R1CDgBvAQAMAAYK9R1CDgBvAQA1AAQKf0kAAgwACgpMIh4HABUDAAwACgpMIh4HABUDAAAA.',
Yi='Yimity:BAAANQAECgMIAwAAAA==.',
Yo='Yogí:BAACNQAFFH8SAAINAAcK0RMcDQB7AQANAAcK0RMcDQB7AQA1AAQKf08AAg0ACgpiIRMGALgDAA0ACgpiIRMGALgDAAAA.Yozomoto:BAACNQAFFH8TAAIdAAcKLSAtCADJAQAdAAcKLSAtCADJAQA1AAQKfz0AAx0ACgofJYIWAO0CAB0ACgofJYIWAO0CAB4AAgo8D3B2AGMAAAAA.',
Za='Zalandria:BAABNQAECn8pAAIUAAoK3ROLDwC+AQAUAAoK3ROLDwC+AQAAAA==.Zarelasong:BAAANQADCgIIAgAAAA==.',
Ze='Zeltemis:BAABNQAECn8YAAIdAAgKAgmcjwDqAQAdAAgKAgmcjwDqAQAAAA==.Zeno:BAAANQADCgUIBQAAAA==.',
Zi='Zipsion:BAABNQAECn9FAAIdAAoKJyM5GAA5AwAdAAoKJyM5GAA5AwAAAA==.Zivver:BAABNQAECn86AAMUAAoKuCOIAgApAwAUAAoKuCOIAgApAwAJAAIKlgoZAAF1AAAAAA==.Zizka:BAABNQAECn8kAAIfAAoKFQZROQBcAQAfAAoKFQZROQBcAQAAAA==.',
Zo='Zolandir:BAAANQAECgYIDQAAAA==.',
Zu='Zuljia:BAAANQAECgUIDAABNQAECggIPAAgAIYdAA==.',
['Òh']='Òhká:BAAANQAECgUIEwAAAA==.',
['Üt']='Üther:BAABNQAECn85AAILAAoKGCTXEACGAwALAAoKGCTXEACGAwAAAA==.',
['ßu']='ßubbleøseven:BAABNQAECn8gAAMLAAkKnx+uNQCNAgALAAkKnx+uNQCNAgAlAAYKfhVsJwA2AQAAAA==.',
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
