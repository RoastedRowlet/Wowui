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

local lookup = {'Priest-Holy','Unknown-Unknown','Priest-Shadow','Priest-Discipline','Evoker-Augmentation','Evoker-Devastation','Mage-Frost','DemonHunter-Havoc','Shaman-Restoration','Hunter-BeastMastery','DemonHunter-Vengeance','Hunter-Marksmanship','Paladin-Retribution','Warrior-Fury','Warrior-Arms','DeathKnight-Blood','Paladin-Holy','Druid-Guardian','Shaman-Enhancement','Warlock-Demonology','DeathKnight-Unholy','Mage-Arcane','DemonHunter-Devourer','Monk-Windwalker','Shaman-Elemental','Warlock-Destruction','Warlock-Affliction','Evoker-Preservation','Druid-Balance','DeathKnight-Frost','Monk-Mistweaver','Rogue-Assassination','Druid-Restoration','Monk-Brewmaster','Paladin-Protection','Druid-Feral','Warrior-Protection','Hunter-Survival','Rogue-Subtlety',}
local provider = {region='US',realm='Suramar',name='US',type='weekly',zone=46,date='2026-06-06',data={Aa='Aassvik:BAABLgAECn8zAAIBAAgJRyB4CgCyAgABAAgJRyB4CgCyAgAAAA==.',
Ab='Absolute:BAAALgAECgQJCAABLgAFFAEJAQACAAAAAA==.',
Ac='Accident:BAAALgAECgIJAwAAAA==.Achievless:BAAALgAECgcJDQAAAA==.Achievsome:BAACLgAFFH8nAAQDAAcJbCIHAwBUAgADAAcJbCIHAwBUAgAEAAQJFgnWCwAdAQABAAIJOgnTMABCAAAuAAQKfygABAMACQk/IcQMALcCAAMACAlNIcQMALcCAAEAAwnjGZRTAOkAAAQAAQm8Hh9OAFkAAAAA.',
Ad='Adava:BAACLgAFFH8FAAIFAAMJQBbgOADTAAAFAAMJQBbgOADTAAAuAAQKfx0AAwUABgmvGektAHkBAAUABgmvGektAHkBAAYABglrDUgQAPkAAAEuAAUUCAkdAAcA8yEA.Adennoko:BAAALgADCgkJCQAAAA==.',
Ae='Aery:BAAALgADCgcJBwAAAA==.Aesodx:BAAALgAECgEJAQABLgAECgQJCwACAAAAAA==.Aesomx:BAAALgAECgQJCwAAAA==.',
Ag='Agrajag:BAAALgADCgkJCQABLgAFFAMJDQAIAGQbAA==.',
Ai='Aiona:BAAALgAECgUJCgAAAA==.Aithea:BAAALgAECgQJBAAAAA==.',
Ak='Akagrats:BAAALgAECgYJDAAAAA==.Akirax:BAAALgAECgIJBAAAAA==.Aknutiak:BAAALgAECgIJAgAAAA==.Akumahunter:BAAALgADCgcJBwABLgAECggJMwABAEcgAA==.',
Al='Alabelina:BAAALgADCgYJCgAAAA==.Alassar:BAAALgAECgcJCwAAAA==.Aldenwarlock:BAAALgAECgQJCwAAAA==.Alekhine:BAAALgADCgIJAgAAAA==.Alessandro:BAABLgAECn8UAAIFAAgJxgc8QQAZAQAFAAgJxgc8QQAZAQAAAA==.Alestar:BAAALgADCgkJDwABLgAECggJKgAJAFAjAA==.Aliengrey:BAABLgAECn8cAAIKAAgJ6xSuSwCyAQAKAAgJ6xSuSwCyAQAAAA==.Allimore:BAAALgAECgQJBQAAAA==.Alonsusfaol:BAAALgADCgUJBgAAAA==.Alyx:BAAALgAECgQJBAAAAA==.',
Am='Amane:BAABLgAECn8oAAMLAAgJDxwPBwAJAgALAAgJqxoPBwAJAgAIAAYJHhgiJwAuAQAAAA==.American:BAABLgAECn8WAAIHAAcJCg47lgBHAQAHAAcJCg47lgBHAQAAAA==.Amulisha:BAAALgAECgIJAgAAAA==.Amytenchi:BAAALgADCgcJFAAAAA==.',
An='Angrystake:BAAALgADCgMJAwAAAA==.Anizeta:BAAALgADCgYJBwABLgAECgkJLQAKAFMcAA==.Annya:BAABLgAECn8iAAMBAAkJNBNRLACWAQABAAgJkRRRLACWAQADAAYJOgu8RQDuAAAAAA==.Anowon:BAAALgADCgcJBwABLgAECgkJCwACAAAAAA==.',
Ar='Arassaka:BAABLgAFFH8FAAIMAAQJrxgIEwAhAQAMAAQJrxgIEwAhAQAAAA==.Archdragon:BAAALgAECgUJCAAAAA==.Archtrishop:BAAALgADCgkJFwAAAA==.Arcius:BAAALgAECgYJDQAAAA==.Aristae:BAAALgAECgEJAQABLgAECggJMgANAIMVAA==.Arkanis:BAABLgAECn85AAIOAAkJuB2LEABsAgAOAAkJuB2LEABsAgAAAA==.Arlestia:BAAALgADCgEJAQAAAA==.Armament:BAABLgAECn8kAAMOAAgJHBasLwCJAQAOAAcJfxasLwCJAQAPAAYJkhGhMgDxAAAAAA==.Arrolexancas:BAAALgAECgYJEgAAAA==.Arrows:BAAALgADCgQJBAAAAA==.Arturiouss:BAACLgAFFH8JAAIQAAMJQQj1KQCSAAAQAAMJQQj1KQCSAAAuAAQKfx8AAhAACQkKEK0bAHEBABAACQkKEK0bAHEBAAAA.Arwenn:BAAALgAECgEJAQAAAA==.Arzuul:BAAALgAECgUJDQAAAA==.',
As='Ashlenna:BAAALgAECgYJCgAAAA==.Asperwind:BAAALgAECgEJAgAAAA==.Astrae:BAAALgAECgYJDAABLgAFFAUJDAAFANkRAA==.',
At='Athira:BAAALgAECgUJBwAAAA==.',
Au='Audi:BAAALgAFFAEJAQAAAA==.Auid:BAAALgADCgUJBQAAAA==.Aurafiora:BAACLgAFFH8KAAIKAAMJUx4zSwABAQAKAAMJUx4zSwABAQAuAAQKf0kAAwoACQmaJOIDAEwDAAoACQmaJOIDAEwDAAwAAgmNDG92AGUAAAAA.Aurelio:BAABLgAECn8iAAIRAAgJMha3LgDIAQARAAgJMha3LgDIAQAAAA==.Auther:BAAALgAECgEJAQAAAA==.',
Av='Avalancha:BAABLgAECn8rAAISAAkJLBj/CgAiAgASAAkJLBj/CgAiAgAAAA==.Avangela:BAAALgAECgYJBQAAAA==.Avanish:BAAALgADCgEJAQABLgAECgQJBgACAAAAAA==.Avinoch:BAABLgAECn8zAAISAAgJgQvEKQD5AAASAAgJgQvEKQD5AAAAAA==.',
Aw='Awenyedd:BAAALgAECgYJDAAAAA==.',
Ax='Axon:BAAALgADCgcJBwAAAA==.',
Az='Azaliene:BAAALgAECgQJBAAAAA==.Azambregon:BAAALgADCgcJEAAAAA==.Azenroth:BAAALgAECgEJAQAAAA==.Azulhail:BAAALgAECgQJCAAAAA==.Azurhan:BAAALgADCgMJAwAAAA==.',
Ba='Bahadir:BAAALgADCgEJAQAAAA==.Bakimono:BAAALgAECgMJCAAAAA==.Balthizer:BAAALgAECgQJBAAAAA==.Banehellborn:BAAALgAECgIJAgAAAA==.Barloran:BAAALgADCgEJAQAAAA==.Bastoosebata:BAABLgAECn8dAAITAAkJmAi+FgBHAQATAAkJmAi+FgBHAQAAAA==.Bazzi:BAAALgAECgMJBAAAAA==.',
Be='Bearbud:BAAALgADCggJCAABLgAFFAYJIAAUAAEhAA==.Beardicuss:BAAALgAECgQJCgAAAA==.Beastdrank:BAAALgAECgMJAwAAAA==.Beauxjingles:BAAALgAECgQJBgAAAA==.Beefjerkietu:BAAALgAECgUJBQAAAA==.Beefsirloin:BAAALgADCgkJCQABLgAECgkJDQACAAAAAA==.Beezlebumon:BAAALgAECggJEgAAAA==.Belakor:BAAALgADCgMJAwAAAA==.Beld:BAAALgADCgYJBgAAAA==.Bellcross:BAAALgAECgYJDQAAAA==.Benedis:BAAALgAECgQJBQAAAA==.Berington:BAAALgAECgEJAQAAAA==.Bewater:BAAALgAECgUJCAAAAA==.',
Bh='Bhutcheeks:BAAALgAECgQJBAAAAA==.',
Bi='Bigfatcow:BAAALgAECgkJDAAAAA==.Birr:BAAALgADCgUJCAAAAA==.',
Bl='Bloomflow:BAAALgAECgYJDwAAAA==.Blåzë:BAAALgAECgUJBgAAAA==.',
Bo='Bobabear:BAAALgADCgMJAwAAAA==.Boneitis:BAAALgAECgQJBQAAAA==.Bonersimpsun:BAABLgAECn8aAAIVAAgJGxZkVgC6AQAVAAgJGxZkVgC6AQAAAA==.Boomclap:BAACLgAFFH8KAAIJAAQJ4xB0NAD5AAAJAAQJ4xB0NAD5AAAuAAQKfyEAAgkACQlvGOEmABgCAAkACQlvGOEmABgCAAAA.Bootstrap:BAAALgAECgQJBAAAAA==.',
Bp='Bpbreezy:BAACLgAFFH8HAAIBAAMJ0h09GgDUAAABAAMJ0h09GgDUAAAuAAQKfzEAAwEACQn9In0CAEIDAAEACQn9In0CAEIDAAMAAQnEHRxyAE0AAAAA.',
Br='Bracknor:BAACLgAFFH8KAAIKAAMJYwlOXgDTAAAKAAMJYwlOXgDTAAAuAAQKfz8AAgoACQnSF/soAC8CAAoACQnSF/soAC8CAAAA.Braknight:BAAALgAECgYJBgAAAA==.Brandonb:BAACLgAFFH8NAAIHAAMJkBrQagAEAQAHAAMJkBrQagAEAQAuAAQKf1cAAwcACQkrJUQEAGMDAAcACQkrJUQEAGMDABYAAQk2FuQcADkAAAAA.Brandondh:BAABLgAECn8uAAIXAAgJtRxrJAAyAgAXAAgJtRxrJAAyAgAAAA==.Brawn:BAAALgAECgkJDAAAAA==.Breata:BAAALgAECgEJAgAAAA==.Bredock:BAABLgAECn8aAAINAAYJYxiOnwAsAQANAAYJYxiOnwAsAQABLgAFFAYJGgAKAMkWAA==.Brickmitts:BAAALgADCgYJBwAAAA==.Brittlehorn:BAAALgADCgEJAQAAAA==.Brotem:BAABLgAECn8tAAITAAkJpiAsAgD5AgATAAkJpiAsAgD5AgAAAA==.Broth:BAAALgAECgQJCgAAAA==.Brynnbramble:BAAALgAECgEJAgAAAA==.',
Bu='Buddhistpalm:BAAALgAECgIJAwAAAA==.Bullshamy:BAAALgADCgIJAgAAAA==.Bulwarkk:BAAALgAECgQJBAAAAA==.Bumbaklot:BAAALgADCgEJAgAAAA==.Bumblbeetuna:BAAALgADCgcJEQAAAA==.Bumperdemon:BAAALgAECgQJBgAAAA==.Burkisure:BAAALgADCgYJBgAAAA==.',
By='Bysokar:BAACLgAFFH8QAAIYAAQJhhe8EAAtAQAYAAQJhhe8EAAtAQAuAAQKfyUAAhgACQmbGQwUABACABgACQmbGQwUABACAAAA.',
['Bü']='Büllshift:BAAALgADCgQJBAAAAA==.',
Ca='Cainfortea:BAAALgAECgUJDAAAAA==.Cakecity:BAABLgAECn87AAQIAAkJGB8iCACeAgAIAAkJwB4iCACeAgALAAcJlhexDAB7AQAXAAEJDAwmCwEvAAAAAA==.Calikillaoi:BAABLgAECn8cAAIVAAYJ2g4LqAAXAQAVAAYJ2g4LqAAXAQAAAA==.Calilock:BAAALgAECgYJCAAAAA==.Calimage:BAAALgAECgUJBwAAAA==.Calipal:BAABLgAECn8qAAINAAcJuRMCfABrAQANAAcJuRMCfABrAQAAAA==.Calisha:BAAALgAECgYJCgAAAA==.Caskashah:BAAALgAECgEJBAAAAA==.Catalìna:BAAALgAFFAQJBAABLgAFFAgJHgAJAMscAA==.Catalïna:BAAALgADCgUJBQABLgAFFAgJHgAJAMscAA==.Catälina:BAACLgAFFH8eAAIJAAgJyxy7AgCSAgAJAAgJyxy7AgCSAgAuAAQKfzcAAwkACAk0I24KANQCAAkACAk0I24KANQCABkAAgnzDWecADAAAAAA.',
Ce='Celebrimbjor:BAAALgAECgUJBgAAAA==.Cerberusbone:BAAALgAECgIJBAAAAA==.',
Ch='Cheddthyr:BAAALgAECgUJBgAAAA==.Cherubim:BAAALgAECgEJAQAAAA==.Chokehana:BAAALgAECgEJAQAAAA==.Chrnobog:BAABLgAECn8kAAQaAAkJTBqbEQC/AQAUAAgJoBuvOAApAgAaAAYJpxabEQC/AQAbAAQJNh1TDgBNAQABLgAFFAYJIAAUAAEhAA==.',
Ci='Cinderlily:BAABLgAECn8fAAMFAAgJGgx4NQBPAQAFAAgJGgx4NQBPAQAcAAMJ5w3NKQCRAAAAAA==.Cinderz:BAAALgAECgQJBAAAAA==.',
Cl='Classicoil:BAAALgADCgEJAQAAAA==.Clayprincess:BAAALgAECgMJAwABLgAECgcJEgACAAAAAA==.',
Co='Cocoyibobo:BAAALgAECgQJBQAAAA==.Coldfront:BAAALgAECgEJAgAAAA==.Colty:BAAALgAECgUJDAAAAA==.Conflagrate:BAACLgAFFH8LAAIUAAQJkR+5LAB3AQAUAAQJkR+5LAB3AQAuAAQKfykAAhQACQnfIm4MAOUCABQACQnfIm4MAOUCAAAA.Connery:BAAALgADCgcJBwAAAA==.Coolbeamz:BAAALgAECgYJCAAAAA==.Corvik:BAAALgADCgEJAQAAAA==.',
Cp='Cptcrushingb:BAAALgAECgEJAgAAAA==.',
Cr='Crazyhamster:BAAALgAECgQJBAAAAA==.Crene:BAAALgADCgIJAgAAAA==.Crithappens:BAABLgAECn8yAAIHAAgJCBw4PACGAgAHAAgJCBw4PACGAgAAAA==.Criturrpants:BAAALgAFFAEJAgAAAA==.',
Cu='Curadd:BAAALgAECgQJBAAAAA==.Cute:BAAALgADCgYJBwAAAA==.',
Cy='Cynnå:BAABLgAECn8VAAIHAAkJPhWGoQCUAQAHAAkJPhWGoQCUAQAAAA==.Cyp:BAAALgAECgEJAQABLgAECgkJIwAVAG8VAA==.',
['Cü']='Cüpcake:BAAALgAECggJDgAAAA==.',
Da='Daikirí:BAABLgAECn8mAAIdAAcJqQZQSgDUAAAdAAcJqQZQSgDUAAAAAA==.Damienator:BAABLgAECn8VAAIXAAcJ+BZvTQCRAQAXAAcJ+BZvTQCRAQAAAA==.Dankiferus:BAAALgADCgcJBwAAAA==.Dannyy:BAAALgAECgQJBAAAAA==.Darren:BAAALgADCgcJEAAAAA==.Dawrk:BAAALgAECgQJBgAAAA==.',
De='Deadincide:BAEBLgAECn8rAAMVAAkJwRgkMgAuAgAVAAkJwRgkMgAuAgAeAAYJ7A5QFwANAQAAAA==.Dearia:BAAALgADCgIJAQAAAA==.Deathblight:BAAALgAECgEJAgAAAA==.Decree:BAABLgAECn8mAAINAAcJlhgEVgC+AQANAAcJlhgEVgC+AQAAAA==.Delcid:BAAALgAFFAEJAQABLgAECgcJFQANADoZAA==.Delik:BAABLgAECn8rAAIHAAkJ5Q2kYQC2AQAHAAkJ5Q2kYQC2AQAAAA==.Deluded:BAAALgAECgkJBAAAAA==.Demonarch:BAAALgAECgEJAQAAAA==.Deneol:BAACLgAFFH8IAAIDAAMJfh/9GAAQAQADAAMJfh/9GAAQAQAuAAQKfx8AAwMACQkLGEsSADoCAAMACQkLGEsSADoCAAQAAQlGB0BZADAAAAAA.Desola:BAAALgADCgEJAQAAAA==.Destrogen:BAABLgAECn8oAAQbAAgJwxsiEABMAQAUAAcJqhSSXwB9AQAbAAYJ+B4iEABMAQAaAAIJgg2PTQCFAAAAAA==.Destïny:BAACLgAFFH8cAAMVAAcJCRnYEgAcAgAVAAcJCRnYEgAcAgAeAAEJ0w4YIwBBAAAuAAQKfyAAAhUACQkQI44qAE4CABUACQkQI44qAE4CAAAA.Desìre:BAABLgAECn8rAAIEAAkJoRYwFAAwAgAEAAkJoRYwFAAwAgAAAA==.Devastator:BAAALgAECgIJBQAAAA==.Dextaros:BAAALgADCgcJBwAAAA==.Deàthgirls:BAAALgADCgUJBQABLgAFFAMJBgANAJAXAA==.Deäthgär:BAAALgAECgMJAwABLgAECgUJBgACAAAAAA==.',
Di='Dinonuggies:BAAALgAECgYJDwAAAA==.Diobrandia:BAAALgADCgMJAwAAAA==.Dirty:BAABLgAECn8tAAIHAAgJuCFwKwBlAgAHAAgJuCFwKwBlAgAAAA==.Discotheque:BAAALgAECgUJDQAAAA==.Disk:BAAALgAECgQJBgAAAA==.',
Dk='Dksura:BAAALgADCgEJAQAAAA==.',
Dn='Dnice:BAAALgAECgEJAQAAAA==.',
Do='Dochunter:BAAALgAECgYJBgAAAA==.Domitia:BAAALgAECgMJAwAAAA==.Doompalm:BAAALgAECgYJBgAAAA==.Doompulse:BAAALgAECgQJBQAAAA==.Doomshield:BAAALgAFFAEJAQAAAA==.Doomshroud:BAAALgADCgMJBAABLgAECgkJKwAfAHcYAA==.Doomtrain:BAAALgAECgQJBAAAAA==.Dorati:BAAALgAECgYJDwAAAA==.Dorellion:BAAALgAECgMJAwAAAA==.',
Dr='Drackiechan:BAAALgAECgMJAwABLgAFFAMJBwABANIdAA==.Dracodeez:BAABLgAECn88AAIgAAkJEiPpAAAeAwAgAAkJEiPpAAAeAwAAAA==.Dranks:BAAALgAECgYJBgAAAA==.Droobid:BAABLgAECn8gAAIhAAkJGB44BQA6AwAhAAkJGB44BQA6AwAAAA==.Drovosh:BAAALgAECgIJAgABLgAFFAgJIgAiAPQUAA==.Druud:BAAALgAECgcJAgAAAA==.',
Dy='Dykenasty:BAABLgAECn8YAAIXAAcJ1B6sOAASAgAXAAcJ1B6sOAASAgAAAA==.Dyxx:BAAALgAECgEJAQAAAA==.',
Dz='Dzlightning:BAAALgAECgIJAgAAAA==.Dznts:BAAALgADCgUJBQAAAA==.',
['Dò']='Dòóm:BAAALgAECgMJBQAAAA==.',
Ea='Earendur:BAABLgAECn8YAAMDAAcJGAezQwD4AAADAAcJGAezQwD4AAABAAMJ3wMlZgA9AAAAAA==.',
Ec='Eciruma:BAAALgAECgEJAgAAAA==.',
Eh='Ehlena:BAAALgAECgEJAgAAAA==.',
Ei='Eiseth:BAAALgADCgUJBQAAAA==.',
El='Electronvolt:BAEALgADCgkJDQABLgAECgkJKwAVAMEYAA==.Elemantus:BAACLgAFFH8FAAIJAAMJoxucNwDtAAAJAAMJoxucNwDtAAAuAAQKfxoAAgkACQnuIv0CAIoDAAkACQnuIv0CAIoDAAAA.Elemeesel:BAAALgADCggJCQAAAA==.Elepunchboom:BAAALgAECgcJDgAAAA==.Eltael:BAAALgAECgYJEQAAAA==.Elæna:BAAALgADCgkJCQAAAA==.',
Em='Emilianaluz:BAABLgAECn8VAAMjAAYJYwFQPgBZAAAjAAYJYwFQPgBZAAANAAEJ9QCGuwEPAAAAAA==.',
En='Endeavor:BAABLgAECn8VAAIEAAgJCxO2IgCpAQAEAAgJCxO2IgCpAQAAAA==.Enkie:BAAALgADCgEJAQABLgAECggJEAACAAAAAA==.Enky:BAAALgAECggJEAAAAA==.Enyxia:BAAALgADCggJEAAAAA==.',
Ep='Epikhotti:BAAALgAECgQJBgAAAA==.',
Er='Eradion:BAAALgAECgEJBQAAAA==.Erisson:BAAALgAECgkJBAAAAA==.',
Es='Eszran:BAABLgAECn8dAAIkAAgJ0A/FFABlAQAkAAgJ0A/FFABlAQAAAA==.',
Eu='Euthanized:BAAALgADCgIJAgAAAA==.',
Ev='Evelleda:BAAALgADCgIJAgAAAA==.Evendell:BAAALgADCgcJBwAAAA==.',
Ex='Excorsist:BAAALgAECgIJAgAAAA==.',
Fa='Facefisted:BAAALgAECgEJAQAAAA==.Falys:BAAALgADCgcJDwAAAA==.Fasani:BAAALgAECgUJDAAAAA==.',
Fe='Feels:BAAALgAECgEJBwAAAA==.Feixiao:BAAALgADCgIJBAAAAA==.Felbro:BAAALgAECgMJAwAAAA==.Felinar:BAAALgADCgEJAQAAAA==.Felraiser:BAAALgADCgkJHgAAAA==.Felsun:BAAALgADCgEJAQAAAA==.Fendalein:BAAALgADCgUJBQAAAA==.Fennar:BAACLgAFFH8GAAIVAAMJAgMmrQCvAAAVAAMJAgMmrQCvAAAuAAQKfxgAAhUABwkCDVSyAAcBABUABwkCDVSyAAcBAAAA.Ferosha:BAABLgAECn8uAAMQAAkJWB4mCgBmAgAQAAgJDR8mCgBmAgAVAAYJYhUnowAeAQABLgAFFAMJCwAiAHUfAA==.Fexxyr:BAAALgAECgQJBAABLgAFFAgJHgADAGAVAA==.',
Fi='Fidobedo:BAAALgADCgMJAwAAAA==.Firefly:BAAALgADCgEJAQAAAA==.Firstfear:BAAALgAECgMJBAAAAA==.Fisch:BAABLgAECn81AAIlAAkJEybeAABhAwAlAAkJEybeAABhAwAAAA==.Fizzlepow:BAAALgADCgYJBgAAAA==.Fiënd:BAAALgAECgUJBQABLgAFFAQJCwAUAJEfAA==.',
Fl='Flagrent:BAAALgAECgQJDQAAAA==.Flashico:BAAALgAECgcJEAAAAA==.Flemingo:BAAALgAECgIJAwAAAA==.Flemruk:BAAALgAECgkJEgAAAA==.Flemta:BAAALgAECggJEwAAAA==.Flemtaur:BAAALgAECgkJDgAAAA==.Flidd:BAABLgAECn8vAAIHAAkJuQxCXQDBAQAHAAkJuQxCXQDBAQAAAA==.Flipingtiska:BAAALgAECgIJAgAAAA==.Floisa:BAAALgADCgQJBAAAAA==.Floret:BAAALgADCgMJAwAAAA==.Flowforth:BAAALgAECgUJBQAAAA==.Fluht:BAAALgAECgUJCgAAAA==.Flynae:BAABLgAECn8oAAIBAAkJpxLTHgC/AQABAAkJpxLTHgC/AQAAAA==.',
Fo='Foible:BAAALgAFFAEJAQAAAA==.',
Fr='Fragmament:BAABLgAECn8bAAIKAAgJ1RlLOADyAQAKAAgJ1RlLOADyAQAAAA==.Frankdrebin:BAAALgAECgEJAQABLgAECggJIAAJACEYAA==.Frearyne:BAABLgAECn8iAAMhAAkJoSTuBABiAwAhAAkJoSTuBABiAwAkAAQJDA+CIgDhAAAAAA==.Friergren:BAACLgAFFH8UAAIHAAUJ8RakUwA1AQAHAAUJ8RakUwA1AQAuAAQKfy0AAgcACQl1HzobAAoDAAcACQl1HzobAAoDAAAA.Frostfight:BAAALgADCgYJBgAAAA==.Frylôck:BAAALgADCgIJAgABLgAECggJEAACAAAAAA==.',
Fs='Fstingnemo:BAAALgADCgUJCAAAAA==.',
Fu='Furrita:BAAALgAECgQJBAAAAA==.',
Fy='Fyster:BAAALgAECgQJBQAAAA==.Fyxxer:BAABLgAECn8dAAIQAAkJ/xc/EAD6AQAQAAkJ/xc/EAD6AQABLgAFFAgJHgADAGAVAA==.Fyxxie:BAACLgAFFH8eAAIDAAgJYBVlAwBGAgADAAgJYBVlAwBGAgAuAAQKfzEAAwMACQl4HWkHABIDAAMACQl4HWkHABIDAAQAAQmkFARtADwAAAAA.',
Ga='Galex:BAAALgADCgEJAQAAAA==.Garah:BAAALgADCgYJBwAAAA==.',
Ge='Geewonii:BAAALgADCgYJBgAAAA==.Geroesan:BAAALgAECgYJCgAAAA==.Geron:BAAALgADCgMJAwAAAA==.',
Gh='Ghostchedd:BAAALgADCggJCwAAAA==.',
Gi='Gialiana:BAACLgAFFH8WAAIMAAYJEBOSDQBxAQAMAAYJEBOSDQBxAQAuAAQKfycAAgwACQljGZIXAHICAAwACQljGZIXAHICAAAA.Giblar:BAAALgADCgUJBQAAAA==.Gikyounoshi:BAAALgADCgUJBwAAAA==.Girthen:BAABLgAECn8mAAMBAAgJySLGBQDzAgABAAgJySLGBQDzAgADAAMJLReJQwDfAAAAAA==.',
Gl='Gloobby:BAAALgAECgEJAQAAAA==.Glukbaglag:BAAALgAFFAIJAwAAAA==.',
Gn='Gnx:BAAALgAECgQJCAAAAA==.',
Go='Goobby:BAACLgAFFH8QAAQVAAUJwR3rRgBUAQAVAAQJwR3rRgBUAQAeAAEJFQskJAA+AAAQAAEJAADsSQAAAAAuAAQKfygAAhUACAm9I5gVAPoCABUACAm9I5gVAPoCAAAA.Goonfred:BAAALgAECgQJBAAAAA==.',
Gr='Greenymeany:BAABLgAECn8xAAIOAAgJHiS8CQDAAgAOAAgJHiS8CQDAAgAAAA==.Grrimm:BAAALgADCgMJAwAAAA==.Grukk:BAAALgADCgYJCwABLgAECgYJEQACAAAAAA==.Grully:BAACLgAFFH8LAAIJAAMJ4Q4jTgClAAAJAAMJ4Q4jTgClAAAuAAQKfyAAAwkACQlcE38pAOkBAAkACQlcE38pAOkBABkAAQmmAUu3ABgAAAAA.Gruumsh:BAABLgAECn8gAAMJAAgJIRjgLwDoAQAJAAgJIRjgLwDoAQAZAAIJxQZVigBNAAAAAA==.',
Ha='Haggard:BAABLgAECn8iAAIXAAkJNxbsMwDrAQAXAAkJNxbsMwDrAQAAAA==.Hailsbelle:BAABLgAECn86AAIIAAgJjhT0GACpAQAIAAgJjhT0GACpAQAAAA==.Hayuru:BAAALgADCgMJAwAAAA==.',
Hb='Hbic:BAABLgAECn8XAAIKAAcJ5QOrnwDzAAAKAAcJ5QOrnwDzAAAAAA==.',
He='Healingpanda:BAAALgAECgQJDAAAAA==.Healyboar:BAABLgAECn8VAAIRAAgJbRCuMACLAQARAAgJbRCuMACLAQAAAA==.Heartstabber:BAAALgADCggJCwAAAA==.Heascha:BAAALgADCgEJAQAAAA==.Heiheii:BAAALgADCgUJBQAAAA==.Heimerdonker:BAEALgADCgcJBwABLgAFFAYJEwAHAJIJAA==.Helado:BAAALgAECgEJAQAAAA==.Hellbane:BAABLgAECn8nAAIUAAkJqgjuZgBrAQAUAAkJqgjuZgBrAQAAAA==.Herdyouleik:BAAALgAECgkJEwAAAA==.Heri:BAAALgADCgEJAQAAAA==.',
Hi='Hiddengrass:BAAALgAECgQJBAAAAA==.Highwayman:BAAALgAECgYJEgABLgAFFAMJDQAmAJ8dAA==.Himwhome:BAAALgAECgMJBQAAAA==.',
Ho='Holyschmidt:BAAALgADCgEJAQAAAA==.Holyteamdiff:BAABLgAECn8aAAIEAAgJsxa1FAAEAgAEAAgJsxa1FAAEAgAAAA==.Holÿshut:BAAALgADCgEJAQABLgAECgkJKwAJAAgXAA==.Hondurasman:BAAALgAECgEJAQAAAA==.Honkay:BAAALgAECgUJCwAAAA==.Honkhonk:BAACLgAFFH8JAAINAAQJnwR9WQDoAAANAAQJnwR9WQDoAAAuAAQKfz8AAg0ACQmAGV82AB0CAA0ACQmAGV82AB0CAAAA.',
Hu='Huahhuahhuah:BAAALgAECgUJBQABLgAECggJKgAJAFAjAA==.Hulas:BAAALgAECgEJAQAAAA==.Hungbeazt:BAAALgAECgUJBQABLgAECgkJNwAcAEIaAA==.Hungidan:BAAALgAECgEJAQABLgAECgkJNwAcAEIaAA==.Huntdemonz:BAAALgAECgYJDgABLgAECggJMQAOAPMYAA==.',
['Hé']='Hécaté:BAAALgAECgEJAQAAAA==.',
Ic='Icelynsnow:BAAALgAECgYJBwAAAA==.Icrono:BAAALgADCgIJAgAAAA==.Icwiener:BAABLgAECn8qAAIJAAgJUCOqCQANAwAJAAgJUCOqCQANAwAAAA==.',
Il='Illaria:BAAALgADCgIJAgAAAA==.Illith:BAAALgADCgMJAgAAAA==.Illumis:BAAALgAECgYJBgAAAA==.Iláiftá:BAAALgAECgEJAQAAAA==.',
Im='Imjustpika:BAAALgADCgcJBwABLgAFFAUJFwAFADQZAA==.',
In='Indeathinite:BAAALgADCgIJAgAAAA==.Infective:BAAALgAECggJDAAAAA==.Inferniö:BAACLgAFFH8dAAIHAAgJ8yGMBgCuAgAHAAgJ8yGMBgCuAgAuAAQKfzUAAgcACQnnJGcEALoDAAcACQnnJGcEALoDAAAA.Inkurushio:BAABLgAECn8pAAMPAAcJexXbHQBiAQAPAAcJexXbHQBiAQAOAAYJNQzcXwDKAAAAAA==.Insector:BAAALgADCgIJAgAAAA==.Inshallah:BAAALgAECgMJCAABLgAECgQJCwACAAAAAA==.Inyoguts:BAAALgAECgcJBwAAAA==.',
Io='Iolanie:BAAALgAECgkJCgAAAA==.',
Ip='Ipewdmyself:BAAALgADCgYJCAAAAA==.',
Is='Ismat:BAACLgAFFH8NAAIJAAMJpCF5KgAhAQAJAAMJpCF5KgAhAQAuAAQKf1UAAgkACQldJcMAANADAAkACQldJcMAANADAAAA.',
Iv='Ivorybones:BAABLgAECn8ZAAIdAAgJbAhWQAD9AAAdAAgJbAhWQAD9AAAAAA==.',
Ix='Ixxi:BAAALgAECgEJAgAAAA==.Ixxia:BAAALgAFFAIJAwAAAA==.Ixxy:BAAALgAECgQJCwAAAA==.',
Iz='Izbiar:BAAALgADCgcJDAAAAA==.',
Ja='Jabahnzulash:BAAALgAFFAEJAQABLgAFFAQJEQAVAD0cAA==.Jabzularu:BAABLgAECn8sAAMJAAgJERWHKwD+AQAJAAgJERWHKwD+AQAZAAEJuAbWrAAkAAAAAA==.Jaekahunt:BAAALgAECgYJDgABLgAECgYJHgAYAGoTAA==.Jaekly:BAAALgAECgIJAgABLgAECgYJHgAYAGoTAA==.Jaeko:BAABLgAECn8eAAIYAAYJahOcQgDmAAAYAAYJahOcQgDmAAAAAA==.Jaekyrn:BAAALgADCgIJAgABLgAECgYJHgAYAGoTAA==.Jaeza:BAABLgAECn8VAAIKAAYJqiEXPgDeAQAKAAYJqiEXPgDeAQAAAA==.Jalynfein:BAAALgADCgYJBgAAAA==.Jamrock:BAABLgAECn8jAAIVAAkJbxVlWADoAQAVAAkJbxVlWADoAQAAAA==.Jaqu:BAAALgAECgEJAgAAAA==.Jarshh:BAABLgAECn88AAIOAAkJ6yECBwDnAgAOAAkJ6yECBwDnAgAAAA==.',
Je='Jedburgh:BAAALgAECgEJAQAAAA==.Jethic:BAAALgADCgUJCwAAAA==.Jezabell:BAAALgAECgYJBgAAAA==.',
Ji='Jibberwhocky:BAAALgADCgYJCgABLgAECggJKAAbAMMbAA==.',
Jo='Jonald:BAABLgAECn8jAAMKAAkJMRb4MwABAgAKAAkJMRb4MwABAgAMAAQJTALVdQBnAAAAAA==.Jonwic:BAAALgADCgIJAgAAAA==.',
Ju='Judge:BAAALgAECgYJDQABLgAFFAMJCwAiAHUfAA==.',
Ka='Kaedra:BAAALgAECgQJBAAAAA==.Kaelostrasza:BAACLgAFFH8MAAIFAAUJ2RECHQBZAQAFAAUJ2RECHQBZAQAuAAQKfxYAAgUABgklHjItAH0BAAUABgklHjItAH0BAAAA.Kallaiopi:BAAALgAECgMJAwAAAA==.Kallaiopie:BAAALgAECgMJAwAAAA==.Kallindrya:BAAALgAECgYJBgAAAA==.Kaly:BAAALgADCgEJAQAAAA==.Kamchatka:BAAALgAFFAEJAQAAAA==.Kass:BAAALgAECgEJAQAAAA==.Kasselliea:BAAALgADCgEJAQAAAA==.Kaveros:BAAALgAECgYJEwAAAA==.Kazara:BAAALgADCgYJBgAAAA==.',
Ke='Kefurion:BAAALgAECgQJBAABLgAECgcJCQACAAAAAA==.Kelaan:BAABLgAECn8qAAMjAAkJMiEyAwDeAgAjAAkJMiEyAwDeAgANAAQJdhVBzwDrAAAAAA==.Kelimao:BAABLgAECn87AAMdAAkJBRADIgCrAQAdAAkJBRADIgCrAQAhAAYJoAgXjQCRAAAAAA==.Kellin:BAAALgADCgMJAwAAAA==.Kelthannaras:BAABLgAECn8jAAMMAAgJSRvzCQDGAQAMAAgJSRvzCQDGAQAmAAIJPQgeWwA9AAAAAA==.Kendrà:BAAALgAECgEJAQAAAA==.Kerunirus:BAAALgADCgYJBgAAAA==.Kevinns:BAAALgAECgYJCwAAAA==.Kevwave:BAAALgAECgMJBQAAAA==.Keyadon:BAAALgAECggJDwAAAA==.',
Ki='Kilian:BAABLgAECn8lAAMUAAcJ6QgbkwARAQAUAAcJ6QgbkwARAQAbAAIJ9QLwJwBRAAAAAA==.Kiritos:BAAALgAECgQJCwAAAA==.Kiserys:BAAALgAECgcJCQAAAA==.Kitsuné:BAAALgAECgEJAQAAAA==.',
Ko='Kode:BAAALgADCgcJBwAAAA==.Kohor:BAAALgAECgEJAQAAAA==.Koko:BAAALgADCgYJDQAAAA==.Komekaka:BAAALgADCgQJCAAAAA==.Korpse:BAAALgAECgQJCQAAAA==.Kostard:BAAALgAECgQJBgAAAA==.',
Kr='Kristallie:BAAALgADCgQJBAAAAA==.Kryemhild:BAAALgADCggJEQAAAA==.Krysto:BAABLgAECn8rAAIKAAkJOhTKPADiAQAKAAkJOhTKPADiAQAAAA==.',
Ku='Kurandos:BAAALgAECgEJAgAAAA==.',
Kw='Kwatli:BAAALgAECgYJCQAAAA==.',
Ky='Kyferon:BAAALgADCggJCgAAAA==.Kyral:BAAALgADCgIJAgAAAA==.',
La='Ladiegp:BAAALgADCgEJAQAAAA==.Laniana:BAAALgADCgQJBAAAAA==.Lanria:BAAALgAECgQJBgAAAA==.Laqmysack:BAAALgAECgQJBwABLgAECggJMQAOAPMYAA==.Laquisha:BAABLgAECn8xAAIOAAgJ8xhJHAAFAgAOAAgJ8xhJHAAFAgAAAA==.Lays:BAAALgADCgQJBAAAAA==.Lazarusgrimm:BAAALgADCgIJAgAAAA==.',
Le='Lelét:BAAALgADCgYJDwAAAA==.Lenin:BAAALgAFFAEJAQAAAA==.Letaz:BAAALgADCgUJBQAAAA==.Lexicology:BAAALgAECgQJDAAAAA==.',
Li='Lickithom:BAAALgAECgQJBQAAAA==.Lilgup:BAAALgADCgUJBgAAAA==.Lilydari:BAAALgAECgUJEgAAAA==.Limeades:BAAALgADCgcJBwAAAA==.Limerick:BAAALgAECgIJAgAAAA==.Limitless:BAAALgADCgcJBwAAAA==.Linaa:BAAALgADCgEJAQAAAA==.Lishna:BAAALgADCgYJBgAAAA==.Lissathshonk:BAAALgAECgEJAgAAAA==.',
Lo='Lokidru:BAAALgAECgYJCQAAAA==.Lookforlight:BAACLgAFFH8GAAINAAMJkBeOXgDdAAANAAMJkBeOXgDdAAAuAAQKfzQAAg0ACQkGJR4IAFMDAA0ACQkGJR4IAFMDAAAA.Lorenth:BAABLgAECn86AAMBAAkJkgcfMQA5AQABAAkJkgcfMQA5AQADAAEJFwXJiwAmAAAAAA==.',
Lu='Lucid:BAAALgADCgEJAQAAAA==.Luckyjade:BAABLgAECn8dAAIZAAgJ3AWNTwDoAAAZAAgJ3AWNTwDoAAAAAA==.Lukou:BAAALgAECgMJAwABLgAFFAMJCwAiAHUfAA==.Luunya:BAACLgAFFH8NAAQDAAMJ+AJJKACcAAADAAMJ+AJJKACcAAABAAIJfAFHLgBPAAAEAAEJbAGhSgAwAAAuAAQKfzMABAMACQkuD10gALsBAAMACQkuD10gALsBAAQACAkGDUEzAD4BAAEABQm/CPtXANUAAAAA.',
Ly='Lyralia:BAAALgADCgkJEQAAAA==.',
Ma='Mabi:BAAALgAECgEJAQAAAA==.Madcowburger:BAAALgAECgkJEAAAAA==.Madelyine:BAAALgADCgIJAgAAAA==.Mageyoulookk:BAAALgAECgYJEQAAAA==.Mahziir:BAAALgAECgYJBwAAAA==.Maithieran:BAAALgADCgYJDwAAAA==.Maizen:BAAALgAECgQJBgABLgAECgQJDAACAAAAAA==.Majax:BAAALgAFFAIJBAAAAA==.Malidros:BAABLgAECn8fAAMBAAgJESB9CgCyAgABAAgJESB9CgCyAgADAAEJPAfXiAApAAAAAA==.Mallson:BAAALgAECgYJBgABLgAECgkJIgAVAOUgAA==.Manogawd:BAAALgAECgYJEAAAAA==.Manwathiel:BAAALgADCgMJAwAAAA==.Marhault:BAACLgAFFH8NAAImAAMJnx03FwAGAQAmAAMJnx03FwAGAQAuAAQKf1IABCYACQm6JZoAAHUDACYACQlsJZoAAHUDAAoACAmgI3QQALYCAAwABQkLEvNVAPIAAAAA.Marriage:BAAALgAECgQJBQAAAA==.Masitaka:BAAALgAECgQJCQABLgAECgQJDAACAAAAAA==.Mathollas:BAABLgAECn8VAAMaAAYJwBDoFAD2AAAaAAYJwBDoFAD2AAAbAAIJcQTlPQArAAAAAA==.Matt:BAAALgAECgUJBgAAAA==.Maxicat:BAABLgAECn8VAAINAAgJdxfcSwDZAQANAAgJdxfcSwDZAQAAAA==.Maximus:BAABLgAECn8eAAINAAgJAhaDXACuAQANAAgJAhaDXACuAQAAAA==.Mayaplc:BAAALgADCgEJAQAAAA==.Mazah:BAABLgAECn9GAAMJAAkJAyDABwAqAwAJAAkJAyDABwAqAwATAAcJixWOFABiAQABLgAFFAMJDQADAPgCAA==.Mazlo:BAABLgAECn8sAAIHAAkJpxmnIQCRAgAHAAkJpxmnIQCRAgAAAA==.',
Mc='Mckrakin:BAAALgADCgEJAQAAAA==.Mclovìns:BAAALgAECgcJCQAAAA==.',
Me='Meibao:BAACLgAFFH8LAAIiAAMJdR8rIQAcAQAiAAMJdR8rIQAcAQAuAAQKf0IAAyIACAkQJZwEAPQCACIACAkQJZwEAPQCABgAAgm7H9ZQALcAAAAA.Meleebrain:BAACLgAFFH8NAAMIAAMJZBtYEwDzAAAIAAMJZBtYEwDzAAAXAAMJkQj0ZACxAAAuAAQKfzsAAwgACQl0H90NADYCAAgABwnPIN0NADYCABcACQk5GXInACICAAAA.Mellethir:BAAALgADCgcJBwAAAA==.Mesaana:BAAALgAECgEJAQABLgAFFAQJEAAYAIYXAA==.Messalina:BAAALgAECgUJBQABLgAECggJHwABABEgAA==.Mex:BAAALgAECgQJCgAAAA==.',
Mi='Miaoyi:BAAALgADCgEJBAAAAA==.Mightylurkin:BAAALgAECgEJAgAAAA==.Millîe:BAABLgAFFH8HAAIfAAMJsgYePwCGAAAfAAMJsgYePwCGAAAAAA==.Mimikay:BAAALgADCgIJAgAAAA==.Miscreant:BAAALgAECgEJAgAAAA==.Missclick:BAAALgAECgYJEgAAAA==.Missoxx:BAAALgAECgUJBQAAAA==.Mistbringer:BAABLgAECn8qAAIhAAcJThkIKQABAgAhAAcJThkIKQABAgAAAA==.Mistmaker:BAABLgAECn8YAAIiAAcJdRuCFwDkAQAiAAcJdRuCFwDkAQABLgAECggJKAAbAMMbAA==.Miwi:BAAALgAECgYJEQAAAA==.',
Mo='Moiest:BAAALgAECgMJBQABLgAECggJIQAFAMsWAA==.Moiesttuna:BAABLgAECn8hAAQFAAgJyxa5IADLAQAFAAgJyxa5IADLAQAcAAQJJxM0JADBAAAGAAIJKgGZOwA/AAAAAA==.Monfalauda:BAAALgADCgEJAgAAAA==.Monkazz:BAAALgADCgYJEAAAAA==.Monkorith:BAACLgAFFH8iAAIiAAgJ9BTZBQAXAgAiAAgJ9BTZBQAXAgAuAAQKfyAAAiIACQlaEJgkAN0BACIACQlaEJgkAN0BAAAA.Moongyal:BAABLgAECn8dAAIhAAkJ8BYjIgAuAgAhAAkJ8BYjIgAuAgAAAA==.Mordeth:BAAALgAECggJDgAAAA==.Mordoboinik:BAABLgAFFH8IAAIgAAQJ6BDoBAAzAQAgAAQJ6BDoBAAzAQAAAA==.Mortin:BAAALgAECgcJBwAAAA==.Mortis:BAAALgADCgQJCgAAAA==.Mosaden:BAABLgAECn8UAAIYAAYJiR/TJACAAQAYAAYJiR/TJACAAQAAAA==.',
Mu='Mudahnk:BAAALgAECgEJAQAAAA==.Mugetsu:BAAALgAECgUJBQAAAA==.Mullett:BAABLgAECn8xAAMNAAkJMRCTVgC9AQANAAkJMRCTVgC9AQARAAEJ8wJ4mgAeAAAAAA==.',
My='Mymeii:BAAALgAECgEJAgAAAA==.Mysticheart:BAAALgADCgEJAQAAAA==.Mystogaan:BAAALgAECgYJBwAAAA==.',
['Mï']='Mïra:BAAALgAECgYJDAABLgAECgkJKgAjADIhAA==.',
Na='Nadrael:BAAALgAECgEJBAAAAA==.Nakiki:BAABLgAECn8kAAIkAAgJWRXLDQDIAQAkAAgJWRXLDQDIAQAAAA==.Nastyiam:BAABLgAECn82AAITAAkJiRStCwDsAQATAAkJiRStCwDsAQAAAA==.',
Ne='Necromeany:BAAALgADCgQJBwABLgAECggJMQAOAB4kAA==.Nennya:BAAALgAECgYJCwAAAA==.Nerfornothin:BAABLgAECn89AAIKAAkJBAqqWACOAQAKAAkJBAqqWACOAQAAAA==.Nethflap:BAACLgAFFH8MAAMcAAUJgAWFGAD1AAAcAAUJgAWFGAD1AAAFAAMJjwVORgChAAAuAAQKfx8AAwUACAl3EPUfAMIBAAUACAl3EPUfAMIBABwABwntB2kxAOUAAAAA.Netsmear:BAABLgAECn8hAAIEAAgJqx9HCQDTAgAEAAgJqx9HCQDTAgAAAA==.Newdawn:BAAALgAECgIJAgAAAA==.',
Ni='Nialin:BAAALgAECgYJCAAAAA==.Niftypackage:BAAALgADCgcJDwAAAA==.Niik:BAABLgAFFH8IAAIJAAMJDQprUgCaAAAJAAMJDQprUgCaAAABLgAFFAQJBQAEAHwDAA==.Nik:BAACLgAFFH8FAAIEAAQJfAMJLADOAAAEAAQJfAMJLADOAAAuAAQKfyoAAwEACQmzGZoQAF8CAAEACAlVGpoQAF8CAAQACAkFFAUhALcBAAAA.',
No='Noctiss:BAAALgAECgIJAgAAAA==.Nomadix:BAAALgADCgEJAQAAAA==.Notcreative:BAAALgAECgEJAQAAAA==.Nowa:BAAALgADCgIJAgAAAA==.',
Nu='Nutmilker:BAACLgAFFH8NAAITAAMJVx2oCQATAQATAAMJVx2oCQATAQAuAAQKfzMAAhMACQnvJFoCACgDABMACQnvJFoCACgDAAAA.',
Ny='Nycterine:BAAALgAECgEJAQAAAA==.Nyxnight:BAAALgADCgYJBgAAAA==.',
Oa='Oakenhart:BAAALgAECgIJAgAAAA==.Oathtaker:BAAALgADCgQJBAAAAA==.',
Ob='Obi:BAABLgAECn8UAAMHAAcJQQqzrwAdAQAHAAcJQQizrwAdAQAWAAMJrAtWEwCQAAAAAA==.',
Ok='Okoye:BAAALgADCgkJEgAAAA==.',
Ol='Olahla:BAAALgADCgYJCwAAAA==.',
Om='Omacron:BAAALgAECgUJBwAAAA==.Omroko:BAAALgADCgQJAwAAAA==.',
Op='Ophriala:BAAALgAECgQJBAAAAA==.Optimistic:BAAALgAECgEJAQAAAA==.',
Or='Oriion:BAAALgAECgEJAwAAAA==.Orthae:BAAALgAECgYJEgABLgAECgYJFQAKAKohAA==.',
Ou='Oubec:BAAALgAECggJCAAAAA==.',
Pa='Paladio:BAAALgAECgMJBQAAAA==.Pandoosevelt:BAAALgAECgUJDAAAAA==.Panodoc:BAAALgADCgMJAwAAAA==.Parmenion:BAABLgAFFH8FAAIUAAMJCgk5eQDCAAAUAAMJCgk5eQDCAAAAAA==.',
Pe='Pelotuda:BAAALgAECgQJDQAAAA==.Penix:BAAALgADCgEJAQAAAA==.Petrovna:BAABLgAFFH8FAAMBAAMJGQj/IwCKAAABAAMJGQj/IwCKAAAEAAEJ4QbCRwA3AAAAAA==.',
Pi='Picklerickz:BAAALgADCgYJBgAAAA==.Pikagosa:BAACLgAFFH8XAAMFAAUJNBlZIABCAQAFAAUJNBlZIABCAQAGAAIJ8wNSBwCVAAAuAAQKfzEAAwUACQkqGWoSAFcCAAUACQkxF2oSAFcCAAYABwkKGlENAAQCAAAA.Pilgor:BAABLgAECn8VAAIFAAgJhRGpMQBlAQAFAAgJhRGpMQBlAQAAAA==.Pils:BAAALgADCgYJBgAAAA==.Pitchief:BAAALgAECgEJAgAAAA==.',
Pl='Plopping:BAAALgADCgMJAwAAAA==.',
Po='Pocky:BAAALgADCgMJAwAAAA==.Popper:BAAALgADCgQJBAAAAA==.',
Pr='Priestkidx:BAAALgADCggJCgAAAA==.Primax:BAAALgAECgIJAgAAAA==.',
Pu='Punchballz:BAAALgADCgIJAgAAAA==.Punchkín:BAABLgAECn8dAAQiAAYJCiAUHgASAgAiAAYJ7x4UHgASAgAfAAQJjRsYSQAuAQAYAAQJShshPAAsAQAAAA==.Purplemage:BAAALgAECgQJBwAAAA==.',
['Pà']='Pàllywacker:BAAALgAECgQJBAABLgAECggJEAACAAAAAA==.',
['Pæ']='Pæsta:BAACLgAFFH8JAAIaAAMJOxIpCgDkAAAaAAMJOxIpCgDkAAAuAAQKfykAAhoACQkrGtQEAB8CABoACQkrGtQEAB8CAAAA.',
['Pé']='Pércy:BAAALgADCgEJAQAAAA==.',
['Pó']='Póókie:BAAALgAECggJEwAAAA==.',
Qu='Quivering:BAAALgAECgEJAgAAAA==.',
Ra='Ragdenar:BAAALgAECgUJEAAAAA==.Ragepounce:BAABLgAECn8UAAMdAAYJXBbaMQBGAQAdAAYJXBbaMQBGAQAkAAYJQQlqJADSAAAAAA==.Ragingblownr:BAAALgAECgQJBAABLgAECgYJDwACAAAAAA==.Raknharok:BAAALgAFFAEJAQAAAA==.Rangikü:BAAALgAECgcJDAAAAA==.Rast:BAAALgAECgQJBgABLgAECggJGQAdAGwIAA==.Rastabout:BAABLgAECn8uAAQBAAkJFhprEwAxAgABAAgJmhprEwAxAgADAAUJ3w3xTgDKAAAEAAEJThLrbgA4AAAAAA==.Rathannar:BAABLgAECn8dAAMIAAcJhxJDKgAZAQAIAAcJhxJDKgAZAQAXAAMJIQc5wACAAAAAAA==.Ravel:BAABLgAECn88AAIfAAkJAyFeBgAwAwAfAAkJAyFeBgAwAwAAAA==.Raxxar:BAEALgADCgcJBwAAAA==.Razah:BAABLgAECn8iAAMFAAgJ5Ac4RwADAQAFAAgJ5Ac4RwADAQAcAAQJaATxLAB1AAAAAA==.',
Re='Reahla:BAAALgADCgcJBwAAAA==.Realchad:BAAALgAFFAIJAgAAAA==.Redeem:BAAALgAECgcJCAAAAA==.Reios:BAABLgAECn8aAAIUAAcJeRx4TACwAQAUAAcJeRx4TACwAQAAAA==.Rellandis:BAAALgAECgEJAQAAAA==.Remedis:BAAALgADCgYJBgAAAA==.Remina:BAAALgAECgEJAQABLgAECgkJIgABADQTAA==.Remy:BAAALgAFFAIJAgAAAA==.Renara:BAAALgAECgMJAwAAAA==.Resora:BAAALgADCgMJAwAAAA==.',
Rh='Rhaz:BAABLgAECn89AAIRAAkJhhV7GgAmAgARAAkJhhV7GgAmAgAAAA==.Rhoup:BAABLgAECn8gAAMkAAYJnBo8EwB4AQAkAAYJnBo8EwB4AQASAAEJmAg8dgAeAAABLgAECgcJEQACAAAAAA==.',
Ri='Richter:BAABLgAECn8iAAMVAAkJ5SBpCgAVAwAVAAkJ5SBpCgAVAwAeAAIJchw2IgCpAAAAAA==.Rickyspanish:BAABLgAECn8wAAIXAAkJCB6uDwC8AgAXAAkJCB6uDwC8AgAAAA==.Rictor:BAAALgAECgMJBAAAAA==.Rifter:BAABLgAECn8iAAMjAAgJixg2EwCKAQAjAAcJzBY2EwCKAQARAAYJXRbZMQCEAQAAAA==.Rivensong:BAAALgAECgIJAwAAAA==.',
Ro='Roarke:BAAALgADCgMJAwAAAA==.Rocksalt:BAAALgAECgEJAQAAAA==.',
Ru='Rubyouraw:BAABLgAECn8nAAIOAAgJcRIDLQCXAQAOAAgJcRIDLQCXAQAAAA==.Rubyus:BAAALgADCgcJBwAAAA==.Ruematoid:BAABLgAECn8UAAIUAAYJXwt3swDaAAAUAAYJXwt3swDaAAAAAA==.Ruffneck:BAABLgAECn8pAAIKAAkJnxMuNwD2AQAKAAkJnxMuNwD2AQAAAA==.Ruik:BAAALgADCgMJAwAAAA==.Ruine:BAAALgAECgMJAwAAAA==.Rumina:BAAALgAECgIJAwAAAA==.Runiic:BAAALgAECgYJAgAAAA==.Russk:BAAALgADCgUJBQAAAA==.',
Sa='Saelaan:BAABLgAECn8VAAIiAAkJShRcEwANAgAiAAkJShRcEwANAgABLgAECgkJKgAjADIhAA==.Saelirria:BAAALgADCggJCAABLgAFFAYJFgAMABATAA==.Sailboat:BAAALgAECgEJAQABLgAFFAEJAQACAAAAAA==.Sakau:BAABLgAECn8aAAQbAAgJKgh2EwAjAQAbAAgJ5wd2EwAjAQAUAAYJ/wQjrwD7AAAaAAEJvgaBeQApAAAAAA==.Sakrine:BAAALgAECgEJAgAAAA==.Sakua:BAAALgADCggJDQAAAA==.Sakurá:BAABLgAECn8gAAIfAAgJFg6ZOwBpAQAfAAgJFg6ZOwBpAQAAAA==.Samo:BAABLgAECn8jAAIDAAgJCR7NEgA1AgADAAgJCR7NEgA1AgAAAA==.Sandarr:BAABLgAECn81AAMjAAkJ0xiICgAVAgAjAAkJkhiICgAVAgANAAEJUxBWfAEyAAAAAA==.Sanguinne:BAABLgAECn8tAAIaAAgJfg/VDQBSAQAaAAgJfg/VDQBSAQAAAA==.Saphran:BAAALgAECgYJDgAAAA==.Sarah:BAAALgAFFAMJAwABLgAFFAUJDgADAL0bAA==.Sargemarge:BAAALgAECgMJAwAAAA==.Sauccy:BAAALgAECgEJAgAAAA==.',
Sc='Scaleboat:BAAALgAECgEJAQABLgAFFAEJAQACAAAAAA==.Scaly:BAABLgAECn83AAMcAAkJQhphBQC5AgAcAAkJQhphBQC5AgAFAAMJRw2gaACTAAAAAA==.Scrotosaggin:BAAALgAECgYJCgAAAA==.',
Se='Seabear:BAAALgAECgEJAQAAAA==.Seafoame:BAAALgADCgcJCAABLgAECgcJFAAhAIoXAA==.See:BAABLgAFFH8OAAIPAAMJGCA4BAD2AAAPAAMJGCA4BAD2AAAAAA==.Selener:BAABLgAECn8aAAIdAAgJzQ1PLgBaAQAdAAgJzQ1PLgBaAQAAAA==.Sendisth:BAAALgADCgYJDQABLgAFFAMJDAATAEoZAA==.Sennia:BAABLgAECn8ZAAIYAAcJNRYnIwCLAQAYAAcJNRYnIwCLAQAAAA==.Severus:BAAALgAECgYJBgAAAA==.',
Sh='Shadoryan:BAAALgADCgYJBgABLgAFFAQJCwAUAJEfAA==.Shadowrock:BAAALgADCgQJBAAAAA==.Shaggiê:BAAALgAECgYJBgAAAA==.Shamydavisjr:BAAALgADCgEJAQAAAA==.Shankles:BAAALgAECgMJAwAAAA==.Shellenne:BAAALgADCgIJAQAAAA==.Shenlong:BAAALgADCgQJBAAAAA==.Shiftychedd:BAAALgAECgEJAQAAAA==.Shikamáru:BAAALgAECgcJCAAAAA==.Shirius:BAAALgADCgYJBgAAAA==.Shorynn:BAAALgADCgUJBQAAAA==.',
Si='Silentsnipe:BAAALgADCgQJAwAAAA==.Silther:BAABLgAECn82AAINAAkJ7B9+EwDFAgANAAkJ7B9+EwDFAgAAAA==.Sinnabun:BAAALgAECgIJAgAAAA==.',
Sk='Skol:BAAALgAFFAEJAQAAAA==.',
Sl='Slapslap:BAAALgAECgQJBgAAAA==.Slavka:BAAALgAECgEJAwAAAA==.Sleepyjoee:BAAALgAECgUJCgABLgAECgYJEQACAAAAAA==.Sleepypriest:BAAALgADCgIJAgABLgAECgYJEQACAAAAAA==.Sleepyyjoe:BAAALgAECgQJBQABLgAECgYJEQACAAAAAA==.Slock:BAAALgAECgEJAQABLgAECggJIQAEAKsfAA==.Slothymoon:BAAALgADCgcJBwAAAA==.Slurandos:BAAALgAECgEJAwAAAA==.Sluxso:BAAALgADCgYJBgAAAA==.',
Sm='Smalliam:BAAALgADCgYJDgABLgAECgkJNgATAIkUAA==.Smoted:BAAALgADCgUJBQABLgAECggJDgACAAAAAA==.',
Sn='Snaerbear:BAAALgAECgUJBQABLgAFFAMJBgANAJAXAA==.Snikrot:BAAALgADCgQJCgAAAA==.Snâppy:BAABLgAECn8qAAIhAAgJOw56TQBPAQAhAAgJOw56TQBPAQAAAA==.',
So='Soloron:BAABLgAECn89AAIJAAkJbxbZIAA9AgAJAAkJbxbZIAA9AgAAAA==.Somebody:BAAALgADCgEJAQAAAA==.Sorceremy:BAAALgAECgcJEwABLgAFFAIJAgACAAAAAA==.Sorrowsöng:BAAALgAECgUJBQAAAA==.Southvik:BAABLgAECn8UAAIRAAYJZR0TIQDwAQARAAYJZR0TIQDwAQABLgAECggJMwABAEcgAA==.',
Sp='Sparke:BAAALgAECgIJBQAAAA==.Sparrhawk:BAABLgAECn8WAAIOAAgJBg+2LwCJAQAOAAgJBg+2LwCJAQAAAA==.Spiced:BAACLgAFFH8LAAIdAAMJOB9RIQADAQAdAAMJOB9RIQADAQAuAAQKfyoAAh0ACQnzJMYDACEDAB0ACQnzJMYDACEDAAAA.Spiceweasel:BAAALgAECgEJAgAAAA==.Spiritbound:BAAALgAECgIJAwAAAA==.Spliffripper:BAAALgADCgEJAQAAAA==.',
St='Starlörd:BAAALgAECgEJAQAAAA==.Starquake:BAAALgAECgEJAQABLgAECgQJDAACAAAAAA==.Starskream:BAAALgAECgcJCwAAAA==.Staysee:BAAALgAECgQJBAAAAA==.Steliokontos:BAAALgAECgcJCAAAAA==.Stickes:BAAALgAECgcJCQAAAA==.Stoke:BAAALgADCgYJBgABLgAECggJHwABABEgAA==.Stormclaw:BAAALgAFFAEJAgAAAA==.Stormfall:BAAALgAECgMJAwAAAA==.Streea:BAAALgAECgQJCQABLgAECgYJFQAKAKohAA==.Sttriker:BAABLgAECn8mAAIIAAkJCgZqMABNAQAIAAkJCgZqMABNAQAAAA==.',
Su='Survival:BAAALgAFFAIJAgABLgAFFAgJHgAVAF8fAA==.Suzierulz:BAAALgAECgUJCAAAAA==.',
Sw='Sweetcheese:BAAALgAECgEJAQAAAA==.Sweetchekz:BAAALgADCgYJBwAAAA==.Sweezey:BAAALgAECgYJBgAAAA==.',
Sy='Syn:BAAALgADCgkJCgAAAA==.Synsairis:BAABLgAECn87AAIYAAkJGB2LDQBjAgAYAAkJGB2LDQBjAgAAAA==.',
Ta='Talenelat:BAAALgADCgUJCQAAAA==.Talietha:BAAALgADCgUJBQAAAA==.Tallonk:BAAALgADCgEJAQAAAA==.Talonknight:BAABLgAECn8jAAIFAAgJoxBPMQBnAQAFAAgJoxBPMQBnAQAAAA==.Talset:BAABLgAECn8jAAIiAAgJwg1kLwA+AQAiAAgJwg1kLwA+AQAAAA==.Tatarin:BAAALgAECgEJAQAAAA==.Taurrows:BAAALgADCgMJAwAAAA==.Tazures:BAAALgADCgIJAgAAAA==.',
Tb='Tbill:BAAALgAECgUJCgAAAA==.',
Te='Teaux:BAAALgADCgQJBQAAAA==.Tellina:BAAALgAECgIJAgAAAA==.Tenson:BAAALgAECgQJCQAAAA==.Teratoma:BAAALgAECgIJAgAAAA==.',
Th='Thad:BAAALgADCgYJBgAAAA==.Thaendofyou:BAABLgAECn8eAAIOAAgJgBZTHwDuAQAOAAgJgBZTHwDuAQAAAA==.Thagda:BAAALgAECgcJDQABLgAFFAMJBQAUAAoJAA==.Theevoker:BAACLgAFFH8SAAIcAAQJhgfZGwDKAAAcAAQJhgfZGwDKAAAuAAQKfywABBwACQmSEKMNAO0BABwACQmSEKMNAO0BAAUABQlkBbZjAKEAAAYAAQnUAdBFAB4AAAAA.Themonk:BAAALgAECgUJBQABLgAFFAQJEgAcAIYHAA==.Theproject:BAAALgAECgcJBgAAAA==.Therise:BAAALgAECgcJDQABLgAFFAMJDQADAPgCAA==.Thestarman:BAAALgADCgUJBQAAAA==.Thizzy:BAAALgAECgEJAQAAAA==.Tholnar:BAAALgAECgYJDwAAAA==.Thoroughbred:BAAALgAECgUJBQAAAA==.Throwdini:BAABLgAECn8kAAIKAAkJYh2DEAC2AgAKAAkJYh2DEAC2AgAAAA==.',
Ti='Tidewrought:BAAALgAECgYJCQAAAA==.Tigerboy:BAAALgAECgYJCQAAAA==.Tikva:BAAALgAECggJDAABLgAFFAMJDQADAPgCAA==.Timotthy:BAABLgAFFH8FAAIkAAIJDhGdEgCJAAAkAAIJDhGdEgCJAAAAAA==.Titant:BAAALgADCgEJAQAAAA==.Titanta:BAABLgAECn8XAAIHAAcJyAjWsQAaAQAHAAcJyAjWsQAaAQAAAA==.Tixxle:BAAALgADCgcJDAAAAA==.',
Tm='Tmate:BAAALgAECgYJCgAAAA==.',
To='Totempics:BAAALgADCgUJBQABLgAECggJIQAhAP4fAA==.Touchmé:BAABLgAECn8UAAIOAAcJFAxfQgAzAQAOAAcJFAxfQgAzAQAAAA==.',
Tr='Treateak:BAAALgAECgEJAgAAAA==.Trotsky:BAAALgAFFAEJAQAAAA==.Trögdor:BAAALgAECgYJBgAAAA==.',
Ts='Tsunaris:BAABLgAECn8gAAIMAAkJqhkNCAD0AQAMAAkJqhkNCAD0AQAAAA==.',
Tu='Tulanis:BAACLgAFFH8NAAIMAAMJnh55FQABAQAMAAMJnh55FQABAQAuAAQKf0IAAgwACQkCI4cBAP0CAAwACQkCI4cBAP0CAAAA.Turbotax:BAAALgAECgUJBQAAAA==.',
Tw='Twiggee:BAAALgAECgEJAQABLgAFFAMJDQADAPgCAA==.',
Ty='Tyriem:BAABLgAECn8tAAIKAAkJUxwYGwB3AgAKAAkJUxwYGwB3AgAAAA==.Tyssanton:BAABLgAECn8nAAQcAAkJwwUdIwDMAAAcAAcJ0wIdIwDMAAAGAAUJqQXGFwCQAAAFAAMJPwKzfQBTAAAAAA==.',
Tz='Tziganin:BAABLgAECn8tAAITAAkJrRytBACYAgATAAkJrRytBACYAgAAAA==.',
Ug='Uggork:BAAALgAECgYJCAAAAA==.',
Um='Umbragos:BAAALgADCgYJBgABLgAECgkJIgAVAOUgAA==.Umi:BAAALgAECgUJCAAAAA==.',
Un='Unholybussy:BAABLgAECn87AAIVAAkJLxunKQBSAgAVAAkJLxunKQBSAgAAAA==.Unicorns:BAAALgAECgEJAQAAAA==.',
Ur='Urvazlite:BAABLgAECn8jAAIOAAgJ9wv5OABbAQAOAAgJ9wv5OABbAQAAAA==.',
Ut='Utaadh:BAABLgAECn8qAAIIAAkJpha1FADZAQAIAAkJpha1FADZAQAAAA==.',
Va='Vael:BAAALgAECggJDgABLgAECggJEQAXAI0aAA==.Vallerin:BAABLgAECn83AAITAAkJZx7MAgDeAgATAAkJZx7MAgDeAgAAAA==.Vanestor:BAAALgADCgkJCQABLgAFFAYJGgAKAMkWAA==.Vanheal:BAAALgAECgcJBwAAAA==.Varahk:BAAALgADCgMJAwAAAA==.Varus:BAAALgADCggJFAAAAA==.',
Ve='Velaar:BAACLgAFFH8NAAIVAAMJUyUhTQBIAQAVAAMJUyUhTQBIAQAuAAQKf0kAAxUACQl+Jr0BAIEDABUACQl+Jr0BAIEDAB4AAgn4HksgALgAAAEuAAQKCAkRABcAjRoA.Velamuna:BAAALgADCgQJBAAAAA==.Velindraela:BAAALgADCgMJAgABLgAECggJIQAhAP4fAA==.Velrius:BAAALgAECgEJAQABLgAECggJEQAXAI0aAA==.Verras:BAAALgADCgIJAgAAAA==.',
Vi='Vikingnorth:BAAALgAECgYJDAABLgAECggJMwABAEcgAA==.Vikthyr:BAAALgADCgcJDQABLgAECggJMwABAEcgAA==.Villain:BAAALgADCgYJBgABLgAFFAMJDQAmAJ8dAA==.',
Vo='Vodlock:BAAALgADCggJCAABLgAFFAYJGgAKAMkWAA==.Vodnar:BAACLgAFFH8aAAMKAAYJyRZaCQD9AQAKAAYJyRZaCQD9AQAMAAEJegAYLgA1AAAuAAQKfykAAwoACQlvHlUZAHACAAoACAljIlUZAHACAAwABglhCEFGADwBAAAA.Vohnkhar:BAAALgADCgUJCAABLgAECgQJBAACAAAAAA==.Voidatfear:BAABLgAECn8dAAIUAAYJKgmCqADrAAAUAAYJKgmCqADrAAAAAA==.Voidhunter:BAAALgAECgcJCgAAAA==.Voodoodoo:BAAALgAECgYJDwAAAA==.Voxramus:BAAALgADCgQJBAABLgAECgYJEQACAAAAAA==.',
Vu='Vulcos:BAAALgAECgYJBwAAAA==.Vulnixia:BAAALgAECgUJCQAAAA==.',
Vy='Vyreth:BAAALgAECgIJBAAAAA==.',
Wa='Wagwan:BAAALgAECgMJBgABLgAECgQJCwACAAAAAA==.Walls:BAABLgAECn8yAAINAAgJgxXUUwDDAQANAAgJgxXUUwDDAQAAAA==.Wasil:BAAALgADCgYJBgAAAA==.Waste:BAABLgAECn8pAAMUAAkJhSAqFwCUAgAUAAgJlyAqFwCUAgAaAAQJnA43JwBvAAAAAA==.Waylander:BAABLgAECn8UAAInAAcJeB4WEAAhAgAnAAcJeB4WEAAhAgABLgAFFAMJBQAUAAoJAA==.',
We='Werragan:BAAALgADCgcJBwAAAA==.',
Wh='Wham:BAAALgAECgIJAgAAAA==.Whameradetu:BAAALgAECgEJAgAAAA==.Whipps:BAAALgAECgYJBgAAAA==.',
Wi='Wickedpriest:BAAALgADCgEJAQAAAA==.Willîe:BAAALgAECgYJCAAAAA==.Wilt:BAAALgAECgIJBAAAAA==.Winstagram:BAAALgAECgIJBQAAAA==.Winterbrook:BAAALgAECgEJAQAAAA==.Wintersgaze:BAAALgAECgEJAQAAAA==.',
Wo='Wompazuzu:BAABLgAECn8dAAMIAAgJuAW7MgDjAAAIAAgJuAW7MgDjAAAXAAEJ6wFDLgEVAAAAAA==.',
Wr='Wraithewyn:BAAALgAECgEJAQAAAA==.Wrathomar:BAAALgADCgYJBwAAAA==.Wrékt:BAAALgAECgQJCQAAAA==.',
Xa='Xandess:BAAALgAECgcJCQAAAA==.Xanosina:BAAALgAECgQJBQAAAA==.',
Xe='Xerethis:BAAALgAECgEJAQAAAA==.',
Xi='Xibaba:BAAALgAECgYJCgAAAA==.',
Xy='Xyro:BAAALgADCgYJBgABLgAECgcJFAAHAEEKAA==.',
Yi='Yilongma:BAAALgAECgIJAwABLgAECgQJCwACAAAAAA==.',
Yl='Ylaran:BAAALgAECgMJAwAAAA==.',
Yn='Yn:BAAALgAECgYJEgAAAA==.',
Yo='Yogí:BAABLgAECn8rAAITAAkJaBxZBwBLAgATAAkJaBxZBwBLAgAAAA==.Yokos:BAABLgAECn8ZAAIlAAcJOhY6FwB8AQAlAAcJOhY6FwB8AQAAAA==.Yonokojo:BAAALgAECgYJDAAAAA==.Yornic:BAAALgAECgYJCwABLgAECgkJHwAVAAQaAA==.Yotokia:BAAALgAECgUJBgABLgAECggJMwABAEcgAA==.',
Yu='Yunkali:BAAALgADCgkJCwAAAA==.',
Za='Zacksquach:BAAALgADCgMJAwAAAA==.Zahneel:BAABLgAECn82AAIhAAkJARlEHgBKAgAhAAkJARlEHgBKAgAAAA==.Zalanar:BAAALgADCgkJDAAAAA==.Zaney:BAAALgAECgYJEQAAAA==.Zangetsen:BAAALgAECgEJAQAAAA==.Zaps:BAAALgAECgEJAQAAAA==.Zaratul:BAACLgAFFH8UAAINAAYJPRteGACRAQANAAYJPRteGACRAQAuAAQKfzQAAg0ACQnvIQ4IAFQDAA0ACQnvIQ4IAFQDAAAA.Zaroth:BAACLgAFFH8PAAIBAAQJSiMjCwB9AQABAAQJSiMjCwB9AQAuAAQKfx0AAgEACAn5FNcnALEBAAEACAn5FNcnALEBAAAA.',
Ze='Zeleste:BAAALgAECggJEQAAAA==.Zelnorac:BAAALgAECgQJDgAAAA==.Zenma:BAAALgAECgMJAwAAAA==.Zerovii:BAACLgAFFH8MAAITAAMJShmiCwDtAAATAAMJShmiCwDtAAAuAAQKfx0AAhMACAndHSYEAOACABMACAndHSYEAOACAAAA.Zetsubou:BAAALgAECgMJAwAAAA==.Zettsuo:BAAALgAECgYJBgAAAA==.',
Zh='Zharrak:BAAALgAECgUJCAAAAA==.',
Zi='Zilyana:BAAALgAECgQJBAAAAA==.',
Zo='Zoburg:BAAALgAECgQJBQABLgAECggJMwABAEcgAA==.',
Zu='Zubuûuûuûuûu:BAAALgAECgYJDwAAAA==.',
Zy='Zyrian:BAABLgAECn8YAAINAAYJtQiE1QDeAAANAAYJtQiE1QDeAAAAAA==.',
['Zä']='Zärthan:BAAALgADCgIJAgAAAA==.',
['Éd']='Édz:BAAALgAECgQJDAAAAA==.',
['Ía']='Íamjakehill:BAAALgAECgMJBgAAAA==.',
['Îr']='Îris:BAAALgADCgcJEAABLgAECgUJEAACAAAAAA==.',
['Ör']='Örnak:BAAALgADCgUJBQAAAA==.',
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
