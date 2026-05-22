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

local lookup = {'Priest-Holy','Priest-Shadow','Priest-Discipline','Mage-Frost','Unknown-Unknown','DemonHunter-Devourer','Shaman-Restoration','DemonHunter-Vengeance','DemonHunter-Havoc','Paladin-Retribution','Warrior-Fury','Warrior-Arms','DeathKnight-Blood','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Holy','Druid-Guardian','Warlock-Demonology','DeathKnight-Unholy','Mage-Arcane','Shaman-Enhancement','Monk-Windwalker','Shaman-Elemental','Warlock-Destruction','Warlock-Affliction','Druid-Balance','Rogue-Assassination','Druid-Restoration','Monk-Brewmaster','Druid-Feral','Warrior-Protection','Hunter-Survival','Evoker-Preservation','Evoker-Augmentation','Paladin-Protection','Evoker-Devastation','Monk-Mistweaver',}
local provider = {region='US',realm='Suramar',name='US',type='weekly',zone=46,date='2026-05-16',data={Aa='Aassvik:BAABLgAECn8rAAIBAAgJMiBgBwC2AgABAAgJMiBgBwC2AgAAAA==.',
Ab='Absolute:BAAALgAECgEJAwAAAA==.',
Ac='Accident:BAAALgAECgIJAwAAAA==.Achievless:BAAALgAECgcJDQAAAA==.Achievsome:BAACLgAFFH8bAAQCAAYJ8R+DAwDdAQACAAYJ8R+DAwDdAQADAAQJFgnWCwAdAQABAAIJOgmRIgBLAAAuAAQKfygABAIACQk/IUwMAEMCAAIACAlNIUwMAEMCAAEAAwnjGZRTAOkAAAMAAQm8Hh9OAFkAAAAA.',
Ad='Adava:BAAALgAECgYJEQABLgAFFAYJFgAEALshAA==.Adennoko:BAAALgADCgkJCQAAAA==.',
Ae='Aery:BAAALgADCgcJBwAAAA==.Aesomx:BAAALgAECgEJBgABLgAECgIJAwAFAAAAAA==.',
Ag='Agrajag:BAAALgADCgkJCQABLgAECgkJMwAGADgZAA==.',
Ai='Aiona:BAAALgAECgUJCgAAAA==.Aithea:BAAALgAECgQJBAAAAA==.',
Ak='Akagrats:BAAALgAECgYJDAAAAA==.Aknutiak:BAAALgAECgIJAgAAAA==.',
Al='Alabelina:BAAALgADCgUJBQAAAA==.Aldenwarlock:BAAALgAECgQJCwAAAA==.Alekhine:BAAALgADCgIJAgAAAA==.Alessandro:BAAALgAECgYJCwAAAA==.Alestar:BAAALgADCgYJBgABLgAECgYJFgAHAEkkAA==.Aliengrey:BAAALgAECgYJEwAAAA==.Allimore:BAAALgAECgQJBQAAAA==.Alonsusfaol:BAAALgADCgUJBgAAAA==.Alyx:BAAALgAECgQJBAAAAA==.',
Am='Amane:BAABLgAECn8jAAMIAAgJTBrpBQDsAQAIAAgJOxnpBQDsAQAJAAYJ/xWzHgAdAQAAAA==.American:BAAALgAECgYJEQAAAA==.Amulisha:BAAALgAECgIJAgAAAA==.Amytenchi:BAAALgADCgcJDQAAAA==.',
An='Angrystake:BAAALgADCgMJAwAAAA==.Annya:BAABLgAECn8iAAMBAAkJNBNRLACWAQABAAgJkRRRLACWAQACAAYJPguMNADzAAAAAA==.Anowon:BAAALgADCgcJBwABLgAECgkJCwAFAAAAAA==.',
Ar='Arassaka:BAAALgAFFAEJAQAAAA==.Archdragon:BAAALgAECgUJCAAAAA==.Archtrishop:BAAALgADCgkJEAAAAA==.Arcius:BAAALgAECgYJDQAAAA==.Aristae:BAAALgAECgEJAQABLgAECgcJJQAKAKMWAA==.Arkanis:BAABLgAECn83AAILAAkJth2KCQCHAgALAAkJth2KCQCHAgAAAA==.Arlestia:BAAALgADCgEJAQAAAA==.Armament:BAABLgAECn8eAAMLAAgJIxW6LABSAQALAAcJVhW6LABSAQAMAAYJkhGmIAD+AAAAAA==.Arrolexancas:BAAALgAECgYJEgAAAA==.Arrows:BAAALgADCgQJBAAAAA==.Arturiouss:BAABLgAECn8cAAINAAgJ0RFaGAAvAQANAAgJ0RFaGAAvAQAAAA==.Arwenn:BAAALgAECgEJAQAAAA==.Arzuul:BAAALgAECgUJDQAAAA==.',
As='Ashlenna:BAAALgAECgYJCgAAAA==.Asperwind:BAAALgAECgEJAQAAAA==.',
At='Athira:BAAALgADCgUJCQAAAA==.',
Au='Audi:BAAALgAECgEJAQAAAA==.Auid:BAAALgADCgUJBQAAAA==.Aurafiora:BAABLgAECn88AAMOAAkJmSGgEACFAgAOAAkJmSGgEACFAgAPAAIJjQxvdgBlAAAAAA==.Aurelio:BAABLgAECn8cAAIQAAgJMBa3LgDIAQAQAAgJMBa3LgDIAQAAAA==.Auther:BAAALgAECgEJAQAAAA==.',
Av='Avalancha:BAABLgAECn8jAAIRAAgJBBatDACvAQARAAgJBBatDACvAQAAAA==.Avangela:BAAALgAECgYJBQAAAA==.Avanish:BAAALgADCgEJAQABLgAECgQJBgAFAAAAAA==.Avinoch:BAABLgAECn8dAAIRAAcJFgubIADIAAARAAcJFgubIADIAAAAAA==.',
Aw='Awenyedd:BAAALgAECgMJBQAAAA==.',
Ax='Axon:BAAALgADCgcJBwAAAA==.',
Az='Azaliene:BAAALgAECgQJBAAAAA==.Azambregon:BAAALgADCgcJCwAAAA==.Azenroth:BAAALgAECgEJAQAAAA==.Azulhail:BAAALgAECgQJCAAAAA==.Azurhan:BAAALgADCgMJAwAAAA==.',
Ba='Bahadir:BAAALgADCgEJAQAAAA==.Bakimono:BAAALgAECgMJBQAAAA==.Balthizer:BAAALgAECgQJBAAAAA==.Banehellborn:BAAALgAECgIJAgAAAA==.Barloran:BAAALgADCgEJAQAAAA==.Bastoosebata:BAAALgAECgkJEgAAAA==.Bazzi:BAAALgAECgMJBAAAAA==.',
Be='Bearbud:BAAALgADCggJCAABLgAFFAYJFwASAGggAA==.Beardicuss:BAAALgAECgQJCgAAAA==.Beastdrank:BAAALgAECgMJAwAAAA==.Beauxjingles:BAAALgAECgQJBgAAAA==.Beefjerkietu:BAAALgAECgUJBQAAAA==.Beefsirloin:BAAALgADCgkJCQABLgAECgkJDAAFAAAAAA==.Beezlebumon:BAAALgAECggJEQAAAA==.Belakor:BAAALgADCgMJAwAAAA==.Beld:BAAALgADCgYJBgAAAA==.Bellcross:BAAALgAECgYJDQAAAA==.Bewater:BAAALgAECgUJCAAAAA==.',
Bh='Bhutcheeks:BAAALgAECgQJBAAAAA==.',
Bi='Birr:BAAALgADCgUJCAAAAA==.',
Bl='Bloomflow:BAAALgAECgYJDwAAAA==.Blåzë:BAAALgADCgEJAQAAAA==.',
Bo='Bobabear:BAAALgADCgMJAwAAAA==.Boneitis:BAAALgAECgMJAwAAAA==.Bonersimpsun:BAABLgAECn8XAAITAAgJ9hV8PwDBAQATAAgJ9hV8PwDBAQAAAA==.Boomclap:BAABLgAECn8fAAIHAAgJTRr4IAD0AQAHAAgJTRr4IAD0AQAAAA==.Bootstrap:BAAALgAECgIJAgAAAA==.',
Bp='Bpbreezy:BAACLgAFFH8HAAIBAAMJ0h2OEQDvAAABAAMJ0h2OEQDvAAAuAAQKfzEAAwEACQn9In0CAEIDAAEACQn9In0CAEIDAAIAAQnEHYBWAFIAAAAA.',
Br='Bracknor:BAABLgAECn8pAAIOAAkJChVCMgDnAQAOAAkJChVCMgDnAQAAAA==.Brandonb:BAABLgAECn8/AAMEAAkJaSE2CwDxAgAEAAkJaSE2CwDxAgAUAAEJNhbkHAA5AAAAAA==.Brandondh:BAABLgAECn8jAAIGAAcJFB0SLwDCAQAGAAcJFB0SLwDCAQAAAA==.Brawn:BAAALgAECgMJAwAAAA==.Bredock:BAABLgAECn8aAAIKAAYJYxjncABDAQAKAAYJYxjncABDAQABLgAFFAQJDwAOAIkXAA==.Brickmitts:BAAALgADCgYJBwAAAA==.Brittlehorn:BAAALgADCgEJAQAAAA==.Brotem:BAABLgAECn8cAAIVAAkJjxnSBABPAgAVAAkJjxnSBABPAgAAAA==.Broth:BAAALgAECgQJCgAAAA==.',
Bu='Bullshamy:BAAALgADCgIJAgAAAA==.Bulwarkk:BAAALgAECgQJBAAAAA==.Bumbaklot:BAAALgADCgEJAgAAAA==.Bumblbeetuna:BAAALgADCgcJEQAAAA==.Bumperdemon:BAAALgAECgQJBgAAAA==.Burkisure:BAAALgADCgYJBgAAAA==.',
By='Bysokar:BAACLgAFFH8HAAIWAAIJVRCPHACTAAAWAAIJVRCPHACTAAAuAAQKfyEAAhYACQmDGW8UAEoCABYACQmDGW8UAEoCAAAA.',
['Bü']='Büllshift:BAAALgADCgQJBAAAAA==.',
Ca='Cainfortea:BAAALgAECgEJAQAAAA==.Cakecity:BAABLgAECn8yAAQJAAgJ8SB7CABOAgAJAAgJdSB7CABOAgAIAAcJlRcZCQCJAQAGAAEJDAx+1gAxAAAAAA==.Calikillaoi:BAAALgAECgYJCwAAAA==.Calimage:BAAALgADCgYJCwAAAA==.Calipal:BAABLgAECn8ZAAIKAAYJghPtcQBBAQAKAAYJghPtcQBBAQAAAA==.Caskashah:BAAALgAECgEJBAAAAA==.Catalìna:BAAALgAFFAQJBAABLgAFFAUJEgAHALUdAA==.Catalïna:BAAALgADCgUJBQABLgAFFAUJEgAHALUdAA==.Catälina:BAACLgAFFH8SAAIHAAUJtR2vCgCnAQAHAAUJtR2vCgCnAQAuAAQKfzcAAwcACAk1I24KANQCAAcACAk1I24KANQCABcAAgnzDRZ4ADAAAAAA.',
Ce='Celebrimbjor:BAAALgAECgQJBQAAAA==.Cerberusbone:BAAALgAECgEJAgAAAA==.',
Ch='Cheddthyr:BAAALgAECgQJBAAAAA==.Cherubim:BAAALgAECgEJAQAAAA==.Chrnobog:BAABLgAECn8kAAQYAAkJTBqbEQC/AQASAAgJoBuvOAApAgAYAAYJpxabEQC/AQAZAAQJNh1TDgBNAQABLgAFFAYJFwASAGggAA==.',
Ci='Cinderlily:BAAALgAECgcJCQAAAA==.Cinderz:BAAALgADCgcJDgAAAA==.',
Cl='Classicoil:BAAALgADCgEJAQAAAA==.Clayprincess:BAAALgAECgMJAwABLgAECgcJEgAFAAAAAA==.',
Co='Cocoyibobo:BAAALgAECgQJBQAAAA==.Colty:BAAALgADCgkJHQAAAA==.Conflagrate:BAACLgAFFH8GAAISAAQJEBg+JgBIAQASAAQJEBg+JgBIAQAuAAQKfyIAAhIACQndInAIAOUCABIACQndInAIAOUCAAAA.Coolbeamz:BAAALgAECgYJCAAAAA==.Corvik:BAAALgADCgEJAQAAAA==.',
Cp='Cptcrushingb:BAAALgAECgEJAgAAAA==.',
Cr='Crazyhamster:BAAALgAECgQJBAAAAA==.Crene:BAAALgADCgIJAgAAAA==.Crithappens:BAABLgAECn8yAAIEAAgJCBw4PACGAgAEAAgJCBw4PACGAgAAAA==.Criturrpants:BAAALgAECgcJCgAAAA==.',
Cu='Curadd:BAAALgADCgYJBgAAAA==.Cute:BAAALgADCgYJBwAAAA==.',
Cy='Cynnå:BAAALgAECggJEgAAAA==.Cyp:BAAALgAECgEJAQABLgAECgkJIwATAG8VAA==.',
['Cü']='Cüpcake:BAAALgAECggJDgAAAA==.',
Da='Daikirí:BAABLgAECn8lAAIaAAYJhgdFPQDEAAAaAAYJhgdFPQDEAAAAAA==.Damienator:BAABLgAECn8VAAIGAAcJ9xZKOwCPAQAGAAcJ9xZKOwCPAQAAAA==.Dankiferus:BAAALgADCgcJBwAAAA==.Dannyy:BAAALgAECgQJBAAAAA==.Darren:BAAALgADCgYJBwAAAA==.Dawrk:BAAALgAECgQJBgAAAA==.',
De='Deadincide:BAABLgAECn8cAAITAAgJZBlNNQDlAQATAAgJZBlNNQDlAQAAAA==.Dearia:BAAALgADCgIJAQAAAA==.Decree:BAABLgAECn8XAAIKAAYJjRZNcgBAAQAKAAYJjRZNcgBAAQAAAA==.Delcid:BAAALgAECgQJBgABLgAECgcJFQAKADoZAA==.Delik:BAABLgAECn8jAAIEAAgJzAlreABLAQAEAAgJzAlreABLAQAAAA==.Demonarch:BAAALgADCgUJCAAAAA==.Deneol:BAACLgAFFH8FAAICAAMJlBK9FgDwAAACAAMJlBK9FgDwAAAuAAQKfxgAAwIACAnbFqoVAM4BAAIACAnbFqoVAM4BAAMAAQlGB0BZADAAAAAA.Desola:BAAALgADCgEJAQAAAA==.Destrogen:BAABLgAECn8fAAQZAAgJQBovDgBPAQASAAcJVBSWUABsAQAZAAUJtCAvDgBPAQAYAAIJgg2PTQCFAAAAAA==.Destïny:BAACLgAFFH8TAAITAAYJnRZDBwCxAQATAAYJnRZDBwCxAQAuAAQKfyAAAhMACQkQI9oaAGQCABMACQkQI9oaAGQCAAAA.Desìre:BAABLgAECn8jAAIDAAgJ1xVgFQDZAQADAAgJ1xVgFQDZAQAAAA==.Devastator:BAAALgAECgIJBQAAAA==.Deàthgirls:BAAALgADCgUJBQABLgAECgkJNAAKAAYlAA==.',
Di='Dinonuggies:BAAALgAECgQJBwAAAA==.Diobrandia:BAAALgADCgMJAwAAAA==.Dirty:BAABLgAECn8tAAIEAAgJuCFeGwB+AgAEAAgJuCFeGwB+AgAAAA==.Discotheque:BAAALgAECgQJCAAAAA==.Disk:BAAALgAECgQJBgAAAA==.',
Dn='Dnice:BAAALgAECgEJAQAAAA==.',
Do='Dochunter:BAAALgAECgYJBgAAAA==.Domitia:BAAALgAECgEJAQAAAA==.Doompalm:BAAALgAECgYJBgAAAA==.Doompulse:BAAALgAECgMJAwAAAA==.Doomshield:BAAALgAECgYJEAAAAA==.Doomshroud:BAAALgADCgMJAwABLgAECggJGwAKAJoLAA==.Doomtrain:BAAALgAECgIJAgAAAA==.Dorati:BAAALgAECgUJCAAAAA==.Dorellion:BAAALgAECgMJAwAAAA==.',
Dr='Drackiechan:BAAALgAECgMJAwABLgAFFAMJBwABANIdAA==.Dracodeez:BAABLgAECn8zAAIbAAkJKSLeAAD9AgAbAAkJKSLeAAD9AgAAAA==.Droobid:BAABLgAECn8gAAIcAAkJGB44BQA6AwAcAAkJGB44BQA6AwAAAA==.Drovosh:BAEALgAECgIJAgABLgAFFAYJFwAdAK0XAA==.',
Dy='Dykenasty:BAABLgAECn8YAAIGAAcJ1B6sOAASAgAGAAcJ1B6sOAASAgAAAA==.Dyxx:BAAALgAECgEJAQAAAA==.',
Dz='Dzlightning:BAAALgAECgEJAQAAAA==.Dznts:BAAALgADCgUJBQAAAA==.',
['Dò']='Dòóm:BAAALgAECgEJAQAAAA==.',
Ea='Earendur:BAAALgAECgYJEwAAAA==.',
Ec='Eciruma:BAAALgAECgEJAgAAAA==.',
Ei='Eiseth:BAAALgADCgUJBQAAAA==.',
El='Electronvolt:BAAALgADCgMJBAABLgAECggJHAATAGQZAA==.Elemantus:BAAALgAECgIJAwAAAA==.Elemeesel:BAAALgADCggJCQAAAA==.Elepunchboom:BAAALgAECgIJAwAAAA==.Eltael:BAAALgAECgUJEAAAAA==.Elæna:BAAALgADCgkJCQAAAA==.',
Em='Emilianaluz:BAAALgAECgYJCAAAAA==.',
En='Endeavor:BAAALgAECgYJDAAAAA==.Enkie:BAAALgADCgEJAQABLgAECgcJCwAFAAAAAA==.Enky:BAAALgAECgcJCwAAAA==.Enyxia:BAAALgADCggJEAAAAA==.',
Ep='Epikhotti:BAAALgAECgQJBgAAAA==.',
Er='Eradion:BAAALgAECgEJBQAAAA==.Erisson:BAAALgAECgkJBAAAAA==.',
Es='Eszran:BAABLgAECn8aAAIeAAYJRRDCFAASAQAeAAYJRRDCFAASAQAAAA==.',
Eu='Euthanized:BAAALgADCgIJAgAAAA==.',
Ev='Evelleda:BAAALgADCgIJAgAAAA==.Evendell:BAAALgADCgcJBwAAAA==.',
Ex='Excorsist:BAAALgADCgYJBQAAAA==.',
Fa='Facefisted:BAAALgAECgEJAQAAAA==.Falys:BAAALgADCgYJCQAAAA==.Fasani:BAAALgAECgQJBAAAAA==.',
Fe='Feels:BAAALgAECgEJBwAAAA==.Feixiao:BAAALgADCgIJBAAAAA==.Felbro:BAAALgAECgMJAwAAAA==.Felraiser:BAAALgADCgkJHgAAAA==.Fendalein:BAAALgADCgUJBQAAAA==.Fennar:BAABLgAFFH8FAAITAAMJHQJWfQBkAAATAAMJHQJWfQBkAAAAAA==.Ferosha:BAABLgAECn8jAAMNAAkJEBmHDQCxAQANAAgJBBmHDQCxAQATAAYJYhXqdwAsAQABLgAECggJNAAdAHocAA==.Fexxyr:BAAALgAECgQJBAABLgAFFAYJEwACAIYZAA==.',
Fi='Fidobedo:BAAALgADCgMJAwAAAA==.Firefly:BAAALgADCgEJAQAAAA==.Firstfear:BAAALgAECgMJBAAAAA==.Fisch:BAABLgAECn8sAAIfAAkJ/yWBAABmAwAfAAkJ/yWBAABmAwAAAA==.Fizzlepow:BAAALgADCgYJBgAAAA==.',
Fl='Flagrent:BAAALgAECgQJDQAAAA==.Flashico:BAAALgAECgYJDgAAAA==.Flemingo:BAAALgAECgIJAwAAAA==.Flemruk:BAAALgAECgkJEgAAAA==.Flemta:BAAALgAECggJBAAAAA==.Flemtaur:BAAALgAECgkJDgAAAA==.Flidd:BAABLgAECn8lAAIEAAkJRwiAWQCRAQAEAAkJRwiAWQCRAQAAAA==.Flipingtiska:BAAALgAECgIJAgAAAA==.Floret:BAAALgADCgMJAwAAAA==.Flowforth:BAAALgAECgUJBQAAAA==.Fluht:BAAALgADCgkJDwAAAA==.Flynae:BAABLgAECn8jAAIBAAgJphGRIQBwAQABAAgJphGRIQBwAQAAAA==.',
Fr='Fragmament:BAABLgAECn8VAAIOAAgJExlMJgD4AQAOAAgJExlMJgD4AQAAAA==.Frearyne:BAABLgAECn8iAAMcAAkJoSQzAwBnAwAcAAkJoSQzAwBnAwAeAAQJDA9UFwD1AAAAAA==.Friergren:BAACLgAFFH8OAAIEAAQJghVNQAA5AQAEAAQJghVNQAA5AQAuAAQKfy0AAgQACQl1H7kVAKACAAQACQl1H7kVAKACAAAA.Frostfight:BAAALgADCgYJBgAAAA==.Frylôck:BAAALgADCgIJAgABLgAECgcJCwAFAAAAAA==.',
Fs='Fstingnemo:BAAALgADCgUJCAAAAA==.',
Fy='Fyster:BAAALgAECgQJBQAAAA==.Fyxxer:BAABLgAECn8cAAINAAkJMBf7CgDZAQANAAkJMBf7CgDZAQABLgAFFAYJEwACAIYZAA==.Fyxxie:BAACLgAFFH8TAAICAAYJhhlRBQCsAQACAAYJhhlRBQCsAQAuAAQKfykAAwIACQn6HGkHABIDAAIACQn6HGkHABIDAAMAAQmkFDhSAD4AAAAA.',
Ga='Galex:BAAALgADCgEJAQAAAA==.Garah:BAAALgADCgYJBwAAAA==.',
Ge='Geewonii:BAAALgADCgYJBgAAAA==.Geroesan:BAAALgADCggJCAAAAA==.Geron:BAAALgADCgMJAwAAAA==.',
Gh='Ghostchedd:BAAALgADCggJCwAAAA==.',
Gi='Gialiana:BAACLgAFFH8MAAIPAAUJRxXDCwAqAQAPAAUJRxXDCwAqAQAuAAQKfycAAg8ACQlmGTgHAIwBAA8ACQlmGTgHAIwBAAAA.Giblar:BAAALgADCgUJBQAAAA==.Gikyounoshi:BAAALgADCgUJBwAAAA==.Girthen:BAABLgAECn8mAAMBAAgJySLGBQDzAgABAAgJySLGBQDzAgACAAMJLReJQwDfAAAAAA==.',
Gl='Glukbaglag:BAAALgAECgEJAgAAAA==.',
Gn='Gnx:BAAALgAECgQJCAAAAA==.',
Go='Goobby:BAACLgAFFH8HAAITAAMJCxz9VgCxAAATAAMJCxz9VgCxAAAuAAQKfygAAhMACAm9I5gVAPoCABMACAm9I5gVAPoCAAAA.Goonfred:BAAALgAECgQJBAAAAA==.',
Gr='Greenymeany:BAABLgAECn8qAAILAAcJASXnCwBmAgALAAcJASXnCwBmAgAAAA==.Grrimm:BAAALgADCgMJAwAAAA==.Grukk:BAAALgADCgYJCwABLgAECgEJAwAFAAAAAA==.Grully:BAACLgAFFH8IAAIHAAMJIQ6+MADCAAAHAAMJIQ6+MADCAAAuAAQKfx4AAwcACQmzEX8pAOkBAAcACQmzEX8pAOkBABcAAQmmAXGLABgAAAAA.Gruumsh:BAAALgAFFAEJAgAAAA==.',
Ha='Haggard:BAABLgAECn8dAAIGAAgJFRbjNgChAQAGAAgJFRbjNgChAQAAAA==.Hailsbelle:BAABLgAECn8oAAIJAAcJ2hK0GABWAQAJAAcJ2hK0GABWAQAAAA==.Hayuru:BAAALgADCgMJAwAAAA==.',
Hb='Hbic:BAAALgAECgcJEwAAAA==.',
He='Healingpanda:BAAALgAECgQJCQAAAA==.Healyboar:BAABLgAECn8VAAIQAAgJbRBOJQCSAQAQAAgJbRBOJQCSAQAAAA==.Heartstabber:BAAALgADCggJCwAAAA==.Heascha:BAAALgADCgEJAQAAAA==.Heimerdonker:BAEALgADCgcJBwABLgAFFAUJDwAEAMEIAA==.Helado:BAAALgAECgEJAQAAAA==.Hellbane:BAABLgAECn8WAAISAAgJJQSUggD5AAASAAgJJQSUggD5AAAAAA==.Herdyouleik:BAAALgAECgcJCQAAAA==.Heri:BAAALgADCgEJAQAAAA==.',
Hi='Highwayman:BAAALgAECgYJEgABLgAECgkJPAAgACEkAA==.Himwhome:BAAALgAECgMJBQAAAA==.',
Ho='Holyteamdiff:BAABLgAECn8aAAIDAAgJsxa1FAAEAgADAAgJsxa1FAAEAgAAAA==.Holÿshut:BAAALgADCgEJAQABLgAECgkJJwAHAAkXAA==.Hondurasman:BAAALgAECgEJAQAAAA==.Honkay:BAAALgAECgUJCwAAAA==.Honkhonk:BAABLgAECn8yAAIKAAgJpBjPRACxAQAKAAgJpBjPRACxAQAAAA==.',
Hu='Huahhuahhuah:BAAALgAECgUJBQABLgAECgYJFgAHAEkkAA==.Hulas:BAAALgAECgEJAQAAAA==.Hungbeazt:BAAALgAECgUJBQABLgAECgkJMAAhALIZAA==.Hungidan:BAAALgADCgYJBgABLgAECgkJMAAhALIZAA==.Huntdemonz:BAAALgAECgYJDgABLgAECggJKgALAGUYAA==.',
Ic='Icelynsnow:BAAALgAECgQJBAAAAA==.Icrono:BAAALgADCgIJAgAAAA==.Icwiener:BAABLgAECn8WAAIHAAYJSSSMEwB5AgAHAAYJSSSMEwB5AgAAAA==.',
Il='Illaria:BAAALgADCgIJAgAAAA==.Illith:BAAALgADCgMJAgAAAA==.Illumis:BAAALgAECgYJBgAAAA==.',
Im='Imjustpika:BAAALgADCgcJBwABLgAFFAUJEAAiAFkKAA==.',
In='Indeathinite:BAAALgADCgIJAgAAAA==.Inferniö:BAACLgAFFH8WAAIEAAYJuyFaDwDaAQAEAAYJuyFaDwDaAQAuAAQKfzUAAgQACQnnJGcEALoDAAQACQnnJGcEALoDAAAA.Inkurushio:BAABLgAECn8pAAMMAAcJfBVBFABoAQAMAAcJfBVBFABoAQALAAYJNQy9SADRAAAAAA==.Insector:BAAALgADCgIJAgAAAA==.Inshallah:BAAALgAECgEJBAABLgAECgIJAwAFAAAAAA==.Inyoguts:BAAALgAECgcJBwAAAA==.',
Io='Iolanie:BAAALgAECgMJAwAAAA==.',
Ip='Ipewdmyself:BAAALgADCgYJCAAAAA==.',
Is='Ismat:BAABLgAECn8+AAIHAAkJRh/2DgCMAgAHAAkJRh/2DgCMAgAAAA==.',
Iv='Ivorybones:BAAALgAECgcJEgAAAA==.',
Ix='Ixxi:BAAALgADCgUJBQAAAA==.Ixxia:BAAALgAECgEJAQABLgAECgIJAgAFAAAAAA==.Ixxy:BAAALgAECgQJBQAAAA==.',
Iz='Izbiar:BAAALgADCgcJDAAAAA==.',
Ja='Jabahnzulash:BAAALgAECgIJAwABLgAFFAQJEAATAAwZAA==.Jabzularu:BAABLgAECn8eAAMHAAgJrQ+fLgCiAQAHAAgJrQ+fLgCiAQAXAAEJuAbEgwAlAAAAAA==.Jaeko:BAABLgAECn8bAAIWAAYJtxKyMwDnAAAWAAYJtxKyMwDnAAAAAA==.Jaekyrn:BAAALgADCgIJAgABLgAECgYJGwAWALcSAA==.Jaeza:BAAALgAECgQJCwABLgAECgUJCQAFAAAAAA==.Jamrock:BAABLgAECn8jAAITAAkJbxVlWADoAQATAAkJbxVlWADoAQAAAA==.Jarshh:BAABLgAECn8zAAILAAkJGCE1BgDBAgALAAkJGCE1BgDBAgAAAA==.',
Je='Jedburgh:BAAALgAECgEJAQAAAA==.Jethic:BAAALgADCgUJCwAAAA==.Jezabell:BAAALgAECgYJBgAAAA==.',
Ji='Jibberwhocky:BAAALgADCgYJCgABLgAECggJHwAZAEAaAA==.',
Jo='Jonald:BAABLgAECn8jAAMOAAkJMRYIHwAfAgAOAAkJMRYIHwAfAgAPAAQJTALVdQBnAAAAAA==.Jonwic:BAAALgADCgIJAgAAAA==.',
Ju='Judge:BAAALgAECgYJCQABLgAECggJNAAdAHocAA==.',
Ka='Kaelostrasza:BAACLgAFFH8GAAIiAAQJ4BB1HAAhAQAiAAQJ4BB1HAAhAQAuAAQKfxYAAiIABgklHoUgAIYBACIABgklHoUgAIYBAAEuAAUUBQkHAAIABw0A.Kallaiopi:BAAALgAECgMJAwAAAA==.Kallaiopie:BAAALgAECgEJAQAAAA==.Kallindrya:BAAALgAECgQJBAAAAA==.Kaly:BAAALgADCgEJAQAAAA==.Kass:BAAALgAECgEJAQAAAA==.Kasselliea:BAAALgADCgEJAQAAAA==.Kaveros:BAAALgAECgYJEwAAAA==.',
Ke='Kefurion:BAAALgAECgQJBAABLgAECgcJCQAFAAAAAA==.Kelaan:BAABLgAECn8pAAMjAAgJYCIRAwCjAgAjAAgJYCIRAwCjAgAKAAQJdhVBzwDrAAAAAA==.Kelimao:BAABLgAECn8yAAMaAAgJURBIIABtAQAaAAgJURBIIABtAQAcAAYJoAgzdQCUAAAAAA==.Kellin:BAAALgADCgMJAwAAAA==.Kelthannaras:BAABLgAECn8jAAMPAAgJSRvOBgCWAQAPAAgJSRvOBgCWAQAgAAIJPQjIRwA+AAAAAA==.Kendrà:BAAALgADCgMJAwAAAA==.Kerunirus:BAAALgADCgYJBgAAAA==.Kevinns:BAAALgAECgYJCwAAAA==.Kevwave:BAAALgAECgMJBQAAAA==.Keyadon:BAAALgAECggJDwAAAA==.',
Ki='Kilian:BAABLgAECn8fAAMSAAcJ6AgLdwARAQASAAYJ6AgLdwARAQAZAAIJ9QLwJwBRAAAAAA==.Kiritos:BAAALgAECgMJCQAAAA==.Kiserys:BAAALgAECgcJCQAAAA==.Kitsuné:BAAALgADCgcJCAAAAA==.',
Ko='Kode:BAAALgADCgcJBwAAAA==.Kohor:BAAALgADCgUJCQAAAA==.Koko:BAAALgADCgYJDQAAAA==.Komekaka:BAAALgADCgQJCAAAAA==.Korpse:BAAALgAECgQJCQAAAA==.Kostard:BAAALgAECgIJAgAAAA==.',
Kr='Kryemhild:BAAALgADCggJEQAAAA==.Krysto:BAABLgAECn8jAAIOAAgJTxRYPACbAQAOAAgJTxRYPACbAQAAAA==.',
Ku='Kurandos:BAAALgAECgEJAgAAAA==.',
Kw='Kwatli:BAAALgAECgMJAwAAAA==.',
Ky='Kyferon:BAAALgADCggJCgAAAA==.Kyral:BAAALgADCgIJAgAAAA==.',
La='Ladiegp:BAAALgADCgEJAQAAAA==.Lanria:BAAALgAECgQJBgAAAA==.Laquisha:BAABLgAECn8qAAILAAgJZRiWGgDMAQALAAgJZRiWGgDMAQAAAA==.Lays:BAAALgADCgQJBAAAAA==.Lazarusgrimm:BAAALgADCgIJAgAAAA==.',
Le='Lelét:BAAALgADCgYJDwAAAA==.Lenin:BAAALgAECgEJAgAAAA==.Letaz:BAAALgADCgUJBQAAAA==.Lexicology:BAAALgAECgQJCgAAAA==.',
Li='Lickithom:BAAALgAECgQJBQAAAA==.Lilgup:BAAALgADCgUJBgAAAA==.Lilydari:BAAALgAECgUJEgAAAA==.Limerick:BAAALgAECgIJAgAAAA==.Limitless:BAAALgADCgcJBwAAAA==.Linaa:BAAALgADCgEJAQAAAA==.Lishna:BAAALgADCgYJBgAAAA==.Lissathshonk:BAAALgAECgEJAgAAAA==.',
Lo='Lookforlight:BAABLgAECn80AAIKAAkJBiUQBQAhAwAKAAkJBiUQBQAhAwAAAA==.Lorenth:BAABLgAECn8xAAMBAAgJJQhhKQA0AQABAAgJJQhhKQA0AQACAAEJFwW1awAlAAAAAA==.',
Lu='Lucid:BAAALgADCgEJAQAAAA==.Luckyjade:BAAALgAECgcJEgAAAA==.Luunya:BAABLgAECn8vAAQCAAkJ+Q2XGACwAQACAAkJ+Q2XGACwAQADAAgJBw0oJABRAQABAAUJvwj7VwDVAAAAAA==.',
Ly='Lyralia:BAAALgADCgkJEQAAAA==.',
Ma='Mabi:BAAALgAECgEJAQAAAA==.Madcowburger:BAAALgAECgYJDQAAAA==.Madelyine:BAAALgADCgIJAgAAAA==.Mageyoulookk:BAAALgAECgYJEQAAAA==.Mahziir:BAAALgAECgYJBwAAAA==.Maithieran:BAAALgADCgYJDAAAAA==.Maizen:BAAALgAECgQJBgABLgAECgQJCgAFAAAAAA==.Majax:BAAALgAFFAIJBAAAAA==.Malidros:BAABLgAECn8eAAMBAAcJkCD6CQCAAgABAAcJkCD6CQCAAgACAAEJPAcbaAAsAAAAAA==.Manogawd:BAAALgAECgYJEAAAAA==.Manwathiel:BAAALgADCgMJAwAAAA==.Marhault:BAABLgAECn88AAQgAAkJISSLAQAaAwAgAAkJIyOLAQAaAwAOAAgJdyJ0EAC2AgAPAAUJCxLzVQDyAAAAAA==.Marriage:BAAALgAECgQJBQAAAA==.Masitaka:BAAALgAECgQJCQABLgAECgQJCgAFAAAAAA==.Mathollas:BAAALgAECgYJCwAAAA==.Matt:BAAALgAECgEJAgAAAA==.Maxicat:BAAALgAECgcJEAAAAA==.Maximus:BAABLgAECn8eAAIKAAgJAhYVPgDGAQAKAAgJAhYVPgDGAQAAAA==.Mayaplc:BAAALgADCgEJAQAAAA==.Mazah:BAABLgAECn83AAMHAAgJIx8TCwC9AgAHAAgJIx8TCwC9AgAVAAcJfRWCDQBsAQABLgAECgkJLwACAPkNAA==.Mazlo:BAABLgAECn8aAAIEAAkJuxTHMAAVAgAEAAkJuxTHMAAVAgAAAA==.',
Mc='Mckrakin:BAAALgADCgEJAQAAAA==.Mclovìns:BAAALgAECgUJBwAAAA==.',
Me='Megafrost:BAAALgAECgEJAQAAAA==.Meibao:BAABLgAECn80AAIdAAgJehy/DAAvAgAdAAgJehy/DAAvAgAAAA==.Meleebrain:BAABLgAECn8zAAIGAAkJOBmTGwAtAgAGAAkJOBmTGwAtAgAAAA==.Mesaana:BAAALgADCgUJBQABLgAFFAIJBwAWAFUQAA==.Messalina:BAAALgAECgUJBQABLgAECgcJHgABAJAgAA==.Mex:BAAALgAECgQJBwAAAA==.',
Mi='Miaoyi:BAAALgADCgEJBAAAAA==.Mightylurkin:BAAALgADCgQJBAAAAA==.Millîe:BAAALgAECgQJCQAAAA==.Mimikay:BAAALgADCgIJAgAAAA==.Missclick:BAAALgAECgUJCwAAAA==.Missoxx:BAAALgAECgMJAwAAAA==.Mistbringer:BAABLgAECn8ZAAIcAAYJPRNPPgBSAQAcAAYJPRNPPgBSAQAAAA==.Mistmaker:BAAALgAECgcJDQABLgAECggJHwAZAEAaAA==.Miwi:BAAALgAECgYJEQAAAA==.',
Mo='Moiest:BAAALgADCgcJBwABLgAECgUJFQAiABgYAA==.Moiesttuna:BAABLgAECn8VAAQiAAUJGBj7NgD+AAAiAAUJGBj7NgD+AAAhAAQJJxPoHQDCAAAkAAIJKgGZOwA/AAAAAA==.Monfalauda:BAAALgADCgEJAgAAAA==.Monkazz:BAAALgADCgYJEAAAAA==.Monkorith:BAECLgAFFH8XAAIdAAYJrRe+CACQAQAdAAYJrRe+CACQAQAuAAQKfyAAAh0ACQlaEJgkAN0BAB0ACQlaEJgkAN0BAAAA.Moongyal:BAABLgAECn8YAAIcAAgJKRiEIQD3AQAcAAgJKRiEIQD3AQAAAA==.Mordeth:BAAALgAECgcJBgAAAA==.Mordoboinik:BAAALgAFFAQJBAAAAA==.Mortis:BAAALgADCgQJCgAAAA==.Mosaden:BAABLgAECn8UAAIWAAYJiR8NGgCRAQAWAAYJiR8NGgCRAQAAAA==.',
Mu='Mudahnk:BAAALgAECgEJAQAAAA==.Mullett:BAABLgAECn8iAAMKAAgJJxAuXQBwAQAKAAgJJxAuXQBwAQAQAAEJ8wK9gAAeAAAAAA==.',
My='Mymeii:BAAALgAECgEJAgAAAA==.Mysticheart:BAAALgADCgEJAQAAAA==.Mystogaan:BAAALgAECgUJBQAAAA==.',
['Mï']='Mïra:BAAALgAECgYJDAABLgAECggJKQAjAGAiAA==.',
Na='Nadrael:BAAALgAECgEJAQAAAA==.Nakiki:BAABLgAECn8VAAIeAAYJEhN6EwAiAQAeAAYJEhN6EwAiAQAAAA==.Nastyiam:BAABLgAECn8zAAIVAAgJKxT9CQC3AQAVAAgJKxT9CQC3AQAAAA==.',
Ne='Necromeany:BAAALgADCgQJBwABLgAECgcJKgALAAElAA==.Nennya:BAAALgAECgYJCwAAAA==.Nerfornothin:BAABLgAECn8kAAIOAAgJHQc1WwA5AQAOAAgJHQc1WwA5AQAAAA==.Nethflap:BAACLgAFFH8KAAMiAAQJMQVgLwC9AAAiAAMJjwVgLwC9AAAhAAQJrAIAAAAAAAAuAAQKfx8AAyIACAl3EPUfAMIBACIACAl3EPUfAMIBACEABwntB2kxAOUAAAAA.Netsmear:BAABLgAECn8ZAAIDAAcJHB7bCwBcAgADAAcJHB7bCwBcAgAAAA==.Newdawn:BAAALgAECgIJAgAAAA==.',
Ni='Niftypackage:BAAALgADCgcJDwAAAA==.Nik:BAACLgAFFH8FAAIDAAQJfAPPHADrAAADAAQJfAPPHADrAAAuAAQKfyoAAwEACQmzGZoQAF8CAAEACAlVGpoQAF8CAAMACAkFFKUWAMsBAAAA.',
No='Noctiss:BAAALgAECgIJAgAAAA==.Nosferato:BAAALgADCgYJDAAAAA==.Nowa:BAAALgADCgIJAgAAAA==.',
Nu='Nutmilker:BAACLgAFFH8IAAIVAAIJAR3eBwDBAAAVAAIJAR3eBwDBAAAuAAQKfzEAAhUACQntJAwCAMoCABUACQntJAwCAMoCAAAA.',
Ny='Nycterine:BAAALgAECgEJAQAAAA==.Nyxnight:BAAALgADCgYJBgAAAA==.',
Oa='Oakenhart:BAAALgAECgIJAgAAAA==.Oathtaker:BAAALgADCgQJBAAAAA==.',
Ob='Obi:BAAALgAFFAEJAgAAAA==.',
Ok='Okoye:BAAALgADCgkJEgAAAA==.',
Ol='Olahla:BAAALgADCgYJCwAAAA==.',
Om='Omacron:BAAALgADCggJEwAAAA==.Omroko:BAAALgADCgQJAwAAAA==.',
Op='Ophriala:BAAALgAECgQJBAAAAA==.Optimistic:BAAALgAECgEJAQAAAA==.',
Or='Oriion:BAAALgAECgEJAQAAAA==.Orthae:BAAALgAECgMJBQABLgAECgUJCQAFAAAAAA==.',
Pa='Paladio:BAAALgAECgMJBAAAAA==.Pandoosevelt:BAAALgAECgEJAQAAAA==.Panodoc:BAAALgADCgMJAwAAAA==.Parmenion:BAAALgAECgUJBQABLgAECgcJDQAFAAAAAA==.',
Pe='Pelotuda:BAAALgAECgQJDQAAAA==.Penix:BAAALgADCgEJAQAAAA==.Petrovna:BAAALgAFFAMJAwAAAA==.',
Pi='Picklerickz:BAAALgADCgYJBgAAAA==.Pikagosa:BAACLgAFFH8QAAMiAAUJWQqWIAAOAQAiAAUJWQqWIAAOAQAkAAIJ8wNSBwCVAAAuAAQKfyoAAyIACQmOFmoSAFcCACIACQlsE2oSAFcCACQABwkKGlENAAQCAAAA.Pilgor:BAABLgAECn8VAAIiAAgJgxGfJQBgAQAiAAgJgxGfJQBgAQAAAA==.Pils:BAAALgADCgYJBgAAAA==.Pitchief:BAAALgAECgEJAgAAAA==.',
Pl='Plopping:BAAALgADCgMJAwAAAA==.',
Po='Pocky:BAAALgADCgMJAwAAAA==.',
Pr='Priestkidx:BAAALgADCggJCgAAAA==.Primax:BAAALgAECgIJAgAAAA==.',
Pu='Punchballz:BAAALgADCgIJAgAAAA==.Punchkín:BAABLgAECn8YAAQdAAYJCiAUHgASAgAdAAYJyR4UHgASAgAWAAQJShshPAAsAQAlAAQJpxkpMwAYAQAAAA==.Purplemage:BAAALgAECgQJBAAAAA==.',
['Pæ']='Pæsta:BAABLgAECn8pAAIYAAkJKxq0AgA5AgAYAAkJKxq0AgA5AgAAAA==.',
['Pó']='Póókie:BAAALgAECgEJAQAAAA==.',
Qu='Quivering:BAAALgAECgEJAQAAAA==.',
Ra='Ragdenar:BAAALgAECgMJBQAAAA==.Ragepounce:BAABLgAECn8UAAMaAAYJZhYkJABQAQAaAAYJZhYkJABQAQAeAAYJQQl2GQDdAAAAAA==.Ragingblownr:BAAALgAECgQJBAABLgAECgYJDwAFAAAAAA==.Rangikü:BAAALgAECgUJCAAAAA==.Rast:BAAALgADCgYJBgABLgAECgcJEgAFAAAAAA==.Rastabout:BAABLgAECn8iAAMBAAgJ1xcRJwC1AQABAAcJSxkRJwC1AQACAAUJSw0bPADNAAAAAA==.Rathannar:BAABLgAECn8dAAMJAAcJhxLrHAAuAQAJAAcJhxLrHAAuAQAGAAMJIQc5wACAAAAAAA==.Ravel:BAABLgAECn8zAAIlAAkJGCCuBAATAwAlAAkJGCCuBAATAwAAAA==.Raxxar:BAEALgADCgcJBwAAAA==.Razah:BAABLgAECn8bAAIiAAYJ5gh7RgC9AAAiAAYJ5gh7RgC9AAAAAA==.',
Re='Reahla:BAAALgADCgcJBwAAAA==.Realchad:BAAALgAFFAIJAgAAAA==.Redeem:BAAALgAECgcJCAAAAA==.Reios:BAABLgAECn8ZAAISAAcJeRxgNQDFAQASAAcJeRxgNQDFAQAAAA==.Remedis:BAAALgADCgYJBgAAAA==.Remina:BAAALgAECgEJAQABLgAECgkJIgABADQTAA==.Remy:BAAALgAECggJCwAAAA==.Renara:BAAALgAECgMJAwAAAA==.Resora:BAAALgADCgMJAwAAAA==.',
Rh='Rhaz:BAABLgAECn8kAAIQAAgJ+xIPIgCqAQAQAAgJ+xIPIgCqAQAAAA==.Rhoup:BAABLgAECn8YAAMeAAYJnBpkDQCCAQAeAAYJnBpkDQCCAQARAAEJmAi/SAAfAAAAAA==.',
Ri='Richter:BAAALgAECgkJEQAAAA==.Rickyspanish:BAABLgAECn8iAAIGAAgJmRzJHwATAgAGAAgJmRzJHwATAgAAAA==.Rifter:BAAALgAECgYJEQAAAA==.',
Ro='Roarke:BAAALgADCgMJAwAAAA==.',
Ru='Rubyouraw:BAABLgAECn8eAAILAAcJHxIqKQBnAQALAAcJHxIqKQBnAQAAAA==.Rubyus:BAAALgADCgcJBwAAAA==.Ruematoid:BAABLgAECn8UAAISAAYJXwujjQDjAAASAAYJXwujjQDjAAAAAA==.Ruffneck:BAABLgAECn8jAAIOAAgJWhOTNgCyAQAOAAgJWhOTNgCyAQAAAA==.Ruine:BAAALgADCgYJCgAAAA==.Rumina:BAAALgAECgIJAwAAAA==.Runiic:BAAALgAECgYJAgAAAA==.Russk:BAAALgADCgUJBQAAAA==.',
Sa='Saelirria:BAAALgADCggJCAABLgAFFAUJDAAPAEcVAA==.Sailboat:BAAALgAECgEJAQABLgAECgEJAwAFAAAAAA==.Sakau:BAABLgAECn8ZAAQZAAgJFQjvCwAyAQAZAAgJ0gfvCwAyAQASAAYJ/wQjrwD7AAAYAAEJvgaBeQApAAAAAA==.Sakua:BAAALgADCgcJBwAAAA==.Sakurá:BAABLgAECn8eAAIlAAcJjw6SKwBHAQAlAAcJjw6SKwBHAQAAAA==.Samo:BAABLgAECn8jAAICAAgJBx4ADABHAgACAAgJBx4ADABHAgAAAA==.Sandarr:BAABLgAECn8oAAIjAAgJoxegDAClAQAjAAgJoxegDAClAQAAAA==.Sanguinne:BAABLgAECn8bAAIYAAcJZQ4lDgARAQAYAAcJZQ4lDgARAQAAAA==.Saphran:BAAALgAECgQJBgAAAA==.Sarah:BAAALgAECggJCQABLgAFFAQJDAACAL0bAA==.Sargemarge:BAAALgAECgMJAwAAAA==.Sauccy:BAAALgAECgEJAgAAAA==.',
Sc='Scaly:BAABLgAECn8wAAMhAAkJshn/AwC2AgAhAAkJshn/AwC2AgAiAAMJRw00UQCTAAAAAA==.Scrotosaggin:BAAALgAECgUJBQAAAA==.',
Se='Seafoame:BAAALgADCgcJCAABLgAFFAEJAQAFAAAAAA==.See:BAABLgAFFH8OAAIMAAMJGCA4BAD2AAAMAAMJGCA4BAD2AAAAAA==.Selener:BAAALgAECgYJEQAAAA==.Sendisth:BAAALgADCgYJDQABLgAFFAMJCgAVAGIYAA==.Sennia:BAAALgAECgcJDQAAAA==.Severus:BAAALgAECgYJBgAAAA==.',
Sh='Shadoryan:BAAALgADCgYJBgABLgAFFAQJBgASABAYAA==.Shadowrock:BAAALgADCgQJBAAAAA==.Shaggiê:BAAALgAECgYJBgAAAA==.Shamydavisjr:BAAALgADCgEJAQAAAA==.Shellenne:BAAALgADCgIJAQAAAA==.Shiftychedd:BAAALgAECgEJAQAAAA==.Shikamáru:BAAALgAECgcJCAAAAA==.Shirius:BAAALgADCgYJBgAAAA==.',
Si='Silentsnipe:BAAALgADCgQJAwAAAA==.Silther:BAABLgAECn8tAAIKAAkJbx6ODgC5AgAKAAkJbx6ODgC5AgAAAA==.Sinnabun:BAAALgAECgIJAgAAAA==.',
Sk='Skol:BAAALgAFFAEJAQAAAA==.',
Sl='Slapslap:BAAALgAECgIJAgAAAA==.Slavka:BAAALgAECgEJAQAAAA==.Sleepyjoee:BAAALgAECgUJCgABLgAECgYJEQAFAAAAAA==.Sleepypriest:BAAALgADCgIJAgABLgAECgYJEQAFAAAAAA==.Sleepyyjoe:BAAALgAECgQJBQABLgAECgYJEQAFAAAAAA==.Slock:BAAALgAECgEJAQABLgAECgcJGQADABweAA==.Slothymoon:BAAALgADCgcJBwAAAA==.Slurandos:BAAALgAECgEJAQAAAA==.Sluxso:BAAALgADCgYJBgAAAA==.',
Sm='Smalliam:BAAALgADCgYJDgABLgAECggJMwAVACsUAA==.Smoted:BAAALgADCgUJBQABLgAECgcJBgAFAAAAAA==.',
Sn='Snaerbear:BAAALgAECgUJBQABLgAECgkJNAAKAAYlAA==.Snikrot:BAAALgADCgQJCgAAAA==.Snâppy:BAABLgAECn8jAAIcAAgJgw0UQABKAQAcAAgJgw0UQABKAQAAAA==.',
So='Soloron:BAABLgAECn8kAAIHAAgJSRciHgAGAgAHAAgJSRciHgAGAgAAAA==.Somebody:BAAALgADCgEJAQAAAA==.Sorceremy:BAAALgAECgcJEwABLgAECggJCwAFAAAAAA==.Southvik:BAAALgAECgYJCgABLgAECggJKwABADIgAA==.',
Sp='Sparke:BAAALgAECgIJBQAAAA==.Sparrhawk:BAAALgAECgUJCAAAAA==.Spiced:BAACLgAFFH8IAAIaAAIJmSGaIADJAAAaAAIJmSGaIADJAAAuAAQKfykAAhoACQnzJF8CACMDABoACQnzJF8CACMDAAAA.Spiceweasel:BAAALgAECgEJAQAAAA==.Spiritbound:BAAALgAECgIJAwAAAA==.',
St='Starlörd:BAAALgAECgEJAQAAAA==.Starquake:BAAALgAECgEJAQABLgAECgQJCgAFAAAAAA==.Starskream:BAAALgAECgQJBwAAAA==.Steliokontos:BAAALgAECgcJCAAAAA==.Stickes:BAAALgAECgEJAQAAAA==.Stormclaw:BAAALgAFFAEJAgAAAA==.Streea:BAAALgAECgQJBgABLgAECgUJCQAFAAAAAA==.Sttriker:BAABLgAECn8jAAIJAAkJDwVqMABNAQAJAAkJDwVqMABNAQAAAA==.',
Su='Survival:BAAALgAECgUJCgABLgAFFAYJFQATAOkkAA==.Suzierulz:BAAALgAECgQJBAAAAA==.',
Sw='Sweetcheese:BAAALgAECgEJAQAAAA==.Sweetchekz:BAAALgADCgYJBwAAAA==.',
Sy='Syn:BAAALgADCgkJCgAAAA==.Synsairis:BAABLgAECn8yAAIWAAkJeRy0CgBPAgAWAAkJeRy0CgBPAgAAAA==.',
Ta='Talenelat:BAAALgADCgMJBAAAAA==.Talietha:BAAALgADCgUJBQAAAA==.Tallonk:BAAALgADCgEJAQAAAA==.Talonknight:BAABLgAECn8jAAIiAAgJoxA1JQBjAQAiAAgJoxA1JQBjAQAAAA==.Talset:BAABLgAECn8jAAIdAAgJwg1aJQBEAQAdAAgJwg1aJQBEAQAAAA==.Tatarin:BAAALgAECgEJAQAAAA==.Taurrows:BAAALgADCgMJAwAAAA==.Tazures:BAAALgADCgIJAgAAAA==.',
Tb='Tbill:BAAALgAECgUJCgAAAA==.',
Te='Teaux:BAAALgADCgQJBQAAAA==.Tellina:BAAALgAECgIJAgAAAA==.Tenson:BAAALgAECgQJCQAAAA==.',
Th='Thad:BAAALgADCgYJBgAAAA==.Thaendofyou:BAABLgAECn8WAAILAAgJmBBiLgBJAQALAAgJmBBiLgBJAQAAAA==.Thagda:BAAALgAECgcJDQAAAA==.Theevoker:BAACLgAFFH8KAAIhAAQJFga9FADpAAAhAAQJFga9FADpAAAuAAQKfyUABCEACQnJDnYLANgBACEACQnJDnYLANgBACIAAQlpBZB4ACEAACQAAQnUAdBFAB4AAAAA.Theproject:BAAALgAECgcJBgAAAA==.Thestarman:BAAALgADCgUJBQAAAA==.Thizzordie:BAAALgAECgEJAQAAAA==.Tholnar:BAAALgAECgUJDgAAAA==.Thoroughbred:BAAALgAECgUJBQAAAA==.Throwdini:BAABLgAECn8kAAIOAAkJYh2DEAC2AgAOAAkJYh2DEAC2AgAAAA==.',
Ti='Tigerboy:BAAALgAECgYJCQAAAA==.Tikva:BAAALgAECgQJBQABLgAECgkJLwACAPkNAA==.Timotthy:BAABLgAFFH8FAAIeAAIJDhHNCQCrAAAeAAIJDhHNCQCrAAAAAA==.Titant:BAAALgADCgEJAQAAAA==.Titanta:BAABLgAECn8UAAIEAAYJzAnvngAEAQAEAAYJzAnvngAEAQAAAA==.Tixxle:BAAALgADCgUJBwAAAA==.',
Tm='Tmate:BAAALgAECgYJCgAAAA==.',
To='Totempics:BAAALgADCgUJBQABLgAECggJIQAcAAEgAA==.Touchmé:BAAALgAECgMJAwAAAA==.',
Ts='Tsunaris:BAABLgAECn8gAAIPAAkJqhl5BADaAQAPAAkJqhl5BADaAQAAAA==.',
Tu='Tulanis:BAABLgAECn8+AAIPAAkJHyJIAQCNAgAPAAkJHyJIAQCNAgAAAA==.Turbotax:BAAALgAECgUJBQAAAA==.',
Ty='Tyriem:BAABLgAECn8qAAIOAAkJUxzJDwCMAgAOAAkJUxzJDwCMAgAAAA==.Tyssanton:BAABLgAECn8jAAQhAAgJnwWlHwCwAAAhAAYJ+gKlHwCwAAAkAAUJqQVFEgCeAAAiAAIJVwKXbAA2AAAAAA==.',
Tz='Tziganin:BAABLgAECn8kAAIVAAkJ0BidBQAwAgAVAAkJ0BidBQAwAgAAAA==.',
Ug='Uggork:BAAALgAECgYJCAAAAA==.',
Um='Umi:BAAALgAECgIJAgAAAA==.',
Un='Unholybussy:BAABLgAECn8yAAITAAkJDBrxJAArAgATAAkJDBrxJAArAgAAAA==.Unicorns:BAAALgAECgEJAQAAAA==.',
Ur='Urvazlite:BAABLgAECn8jAAILAAgJ9gs1KgBiAQALAAgJ9gs1KgBiAQAAAA==.',
Ut='Utaadh:BAABLgAECn8gAAIJAAkJpRbiDQDlAQAJAAkJpRbiDQDlAQAAAA==.',
Va='Vallerin:BAABLgAECn8oAAIVAAgJpxffBwDrAQAVAAgJpxffBwDrAQAAAA==.Vanestor:BAAALgADCgkJCQABLgAFFAQJDwAOAIkXAA==.Varahk:BAAALgADCgMJAwAAAA==.Varus:BAAALgADCggJFAAAAA==.',
Ve='Velaar:BAABLgAECn89AAITAAkJOyVyAwBJAwATAAkJOyVyAwBJAwABLgAECggJEQAGAIwaAA==.Velamuna:BAAALgADCgQJBAAAAA==.Velindraela:BAAALgADCgMJAgABLgAECggJIQAcAAEgAA==.Verras:BAAALgADCgIJAgAAAA==.',
Vi='Vikingnorth:BAAALgAECgEJAQABLgAECggJKwABADIgAA==.Vikthyr:BAAALgADCgcJDQABLgAECggJKwABADIgAA==.Villain:BAAALgADCgYJBgABLgAECgkJPAAgACEkAA==.',
Vo='Vodlock:BAAALgADCggJCAABLgAFFAQJDwAOAIkXAA==.Vodnar:BAACLgAFFH8PAAMOAAQJiRcqDQD3AAAOAAQJiRcqDQD3AAAPAAEJegAYLgA1AAAuAAQKfykAAw4ACQlvHnEYAEgCAA4ACAljInEYAEgCAA8ABglhCEFGADwBAAAA.Vohnkhar:BAAALgADCgQJBQAAAA==.Voidatfear:BAAALgAECgUJEgAAAA==.Voidhunter:BAAALgAECgMJAwAAAA==.Voodoodoo:BAAALgAECgYJDwAAAA==.Voxramus:BAAALgADCgQJBAABLgAECgEJAwAFAAAAAA==.',
Vu='Vulcos:BAAALgAECgYJBwAAAA==.Vulnixia:BAAALgAECgEJAQAAAA==.',
Vy='Vyreth:BAAALgAECgIJBAAAAA==.',
Wa='Wagwan:BAAALgAECgEJAQABLgAECgIJAwAFAAAAAA==.Walls:BAABLgAECn8lAAIKAAcJoxb3VwB8AQAKAAcJoxb3VwB8AQAAAA==.Wasil:BAAALgADCgYJBgAAAA==.Waste:BAABLgAECn8gAAMSAAkJ5htmHgAyAgASAAgJWBtmHgAyAgAYAAQJiA4YIABqAAAAAA==.Waylander:BAAALgAECgYJCQABLgAECgcJDQAFAAAAAA==.',
We='Werragan:BAAALgADCgcJBwAAAA==.',
Wh='Wham:BAAALgAECgIJAgAAAA==.Whameradetu:BAAALgAECgEJAgAAAA==.Whipps:BAAALgAECgYJBgAAAA==.',
Wi='Willîe:BAAALgAECgEJAQAAAA==.Wilt:BAAALgAECgEJAgAAAA==.Winstagram:BAAALgAECgEJAQAAAA==.',
Wo='Wompazuzu:BAABLgAECn8YAAIJAAcJXAV7KQDMAAAJAAcJXAV7KQDMAAAAAA==.',
Wr='Wraithewyn:BAAALgAECgEJAQAAAA==.Wrékt:BAAALgADCgMJAwAAAA==.',
Xa='Xanosina:BAAALgAECgQJBQAAAA==.',
Yi='Yilongma:BAAALgAECgIJAwAAAA==.',
Yl='Ylaran:BAAALgAECgMJAwAAAA==.',
Yn='Yn:BAAALgAECgYJEgAAAA==.',
Yo='Yogí:BAABLgAECn8rAAIVAAkJZxz8AwBtAgAVAAkJZxz8AwBtAgAAAA==.Yokos:BAAALgAFFAEJAgAAAA==.Yonokojo:BAAALgAECgYJCwAAAA==.Yornic:BAAALgAECgYJCgABLgAECgkJHgATAJUYAA==.Yotokia:BAAALgAECgEJAQABLgAECggJKwABADIgAA==.',
Za='Zacksquach:BAAALgADCgMJAwAAAA==.Zahneel:BAABLgAECn8tAAIcAAkJARmDFgBMAgAcAAkJARmDFgBMAgAAAA==.Zalanar:BAAALgADCgkJDAAAAA==.Zaney:BAAALgAECgYJEQAAAA==.Zaps:BAAALgAECgEJAQAAAA==.Zaratul:BAACLgAFFH8OAAIKAAUJ9hl4KQAuAQAKAAUJ9hl4KQAuAQAuAAQKfzMAAgoACQlEIQ4IAFQDAAoACQlEIQ4IAFQDAAAA.Zaroth:BAACLgAFFH8OAAIBAAQJrCC8BwBwAQABAAQJrCC8BwBwAQAuAAQKfxwAAgEACAm2FNcnALEBAAEACAm2FNcnALEBAAAA.',
Ze='Zeleste:BAAALgAECggJEQAAAA==.Zelnorac:BAAALgAECgQJDgAAAA==.Zenma:BAAALgAECgMJAwAAAA==.Zerovii:BAACLgAFFH8KAAIVAAMJYhg0BgD2AAAVAAMJYhg0BgD2AAAuAAQKfx0AAhUACAndHSYEAOACABUACAndHSYEAOACAAAA.Zetsubou:BAAALgAECgMJAwAAAA==.Zettsuo:BAAALgAECgYJBgAAAA==.',
Zh='Zharrak:BAAALgAECgUJCAAAAA==.',
Zi='Zilyana:BAAALgAECgQJBAAAAA==.',
Zu='Zubuûuûuûuûu:BAAALgAECgUJCQAAAA==.',
Zy='Zyrian:BAAALgAECgMJBgAAAA==.',
['Zä']='Zärthan:BAAALgADCgIJAgAAAA==.',
['Éd']='Édz:BAAALgAECgQJCwAAAA==.',
['Ía']='Íamjakehill:BAAALgAECgMJBgAAAA==.',
['Îr']='Îris:BAAALgADCgcJEAAAAA==.',
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
