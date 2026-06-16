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

local lookup = {'DemonHunter-Havoc','DemonHunter-Vengeance','Paladin-Protection','Unknown-Unknown','Paladin-Retribution','Warlock-Demonology','Priest-Shadow','Priest-Discipline','Shaman-Restoration','Shaman-Elemental','Evoker-Preservation','Shaman-Enhancement','Druid-Guardian','Rogue-Outlaw','DeathKnight-Unholy','Warrior-Fury','Warrior-Arms','DemonHunter-Devourer','Hunter-BeastMastery','Hunter-Marksmanship','Mage-Frost','Druid-Feral','Monk-Windwalker','Priest-Holy','Warlock-Destruction','Monk-Brewmaster','DeathKnight-Blood','DeathKnight-Frost','Evoker-Augmentation','Monk-Mistweaver','Mage-Arcane','Druid-Restoration','Warlock-Affliction','Evoker-Devastation','Rogue-Subtlety','Warrior-Protection','Druid-Balance','Paladin-Holy','Rogue-Assassination','Hunter-Survival','Mage-Fire',}
local provider = {region='US',realm='AzjolNerub',name='US',type='weekly',zone=46,date='2026-06-13',data={Ad='Adapt:BAAALgAECgMJCQAAAA==.Addy:BAACLgAFFH8GAAIBAAMJuxf8FQDuAAABAAMJuxf8FQDuAAAuAAQKf0MAAwEACQloI4ACADkDAAEACQloI4ACADkDAAIAAQlCCDs5ACEAAAAA.',
Ae='Aeonis:BAAALgAECgQJDgAAAA==.Aestian:BAABLgAECn8xAAIDAAkJ5Rm2DAD2AQADAAkJ5Rm2DAD2AQAAAA==.',
Ag='Agamesh:BAAALgADCgUJCQAAAA==.',
Ah='Ahoma:BAAALgADCgkJBgAAAA==.',
Ai='Ailysely:BAAALgADCgUJBQABLgAECgQJDgAEAAAAAA==.Airees:BAABLgAECn8iAAIFAAcJOx7oQQAfAgAFAAcJOx7oQQAfAgAAAA==.Aispere:BAAALgAECgYJEwAAAA==.',
Al='Alastria:BAAALgADCgcJBwAAAA==.Alektra:BAAALgADCgUJBwAAAA==.Alerzhulan:BAABLgAECn8bAAIGAAkJMgu6WQCPAQAGAAkJMgu6WQCPAQAAAA==.Allanquatre:BAAALgAECgYJBgAAAA==.Alledria:BAACLgAFFH8FAAIFAAQJBwRAcQDKAAAFAAQJBwRAcQDKAAAuAAQKfxoAAgUACAmaEn92AH8BAAUACAmaEn92AH8BAAAA.Allenaena:BAAALgAECgMJBgAAAA==.Alorely:BAABLgAECn8gAAMHAAkJ/gzaLwBdAQAHAAgJ0A3aLwBdAQAIAAcJoxPTMABYAQAAAA==.Altonas:BAAALgAECgMJAwAAAA==.',
Am='Amanara:BAAALgAECgcJDQAAAA==.Amillah:BAAALgAECgQJBgAAAA==.Amooka:BAAALgAECgEJAQAAAA==.',
An='Ancientmonk:BAAALgAECgEJAQABLgAECgYJCQAEAAAAAA==.Anciientpaw:BAABLgAECn8iAAMJAAkJGyBlHQAvAgAJAAkJGyBlHQAvAgAKAAUJbBWrWQDTAAAAAA==.Andramalyus:BAABLgAECn8pAAIGAAgJ3AwMbgBeAQAGAAgJ3AwMbgBeAQAAAA==.Andrasomnium:BAAALgAECggJDwAAAA==.Angbar:BAABLgAECn8vAAILAAkJWRYRCQBWAgALAAkJWRYRCQBWAgAAAA==.Anguirus:BAABLgAECn88AAMKAAkJfAUpTQD8AAAKAAkJWwUpTQD8AAAMAAYJAgM0LACNAAAAAA==.Animà:BAAALgAECgYJDwAAAA==.Ankhnstein:BAAALgAECgQJBAAAAA==.Antiheroo:BAAALgAECgUJCAAAAA==.Antoine:BAAALgAECgIJAgAAAA==.Anuksunàmun:BAAALgAECgkJBgAAAA==.',
Ap='Apolloni:BAAALgAECgIJAgABLgAECgkJMgANABYKAA==.Appynoxusrog:BAABLgAECn8cAAIOAAYJuhguBQCcAQAOAAYJuhguBQCcAQAAAA==.',
Aq='Aqulenas:BAABLgAFFH8FAAIPAAMJsROBmQDaAAAPAAMJsROBmQDaAAAAAA==.',
Ar='Arakhan:BAAALgAFFAEJAQAAAA==.Arasaka:BAAALgAECgQJCAAAAA==.Arcadian:BAABLgAECn8zAAMQAAkJHB1VEAB0AgAQAAkJHB1VEAB0AgARAAEJzAfURAAvAAAAAA==.Arcadiann:BAABLgAECn8XAAIQAAcJ3xZ5LACgAQAQAAcJ3xZ5LACgAQAAAA==.Arcadin:BAAALgAECgEJAgAAAA==.Arcoyflecha:BAAALgAECgYJCgAAAA==.Arextheelder:BAAALgAFFAEJAQAAAA==.Aridas:BAABLgAECn8dAAMSAAgJJBhuMwAsAgASAAgJJBhuMwAsAgABAAIJRQsGYABiAAABLgAECgkJKAARAAcaAA==.Arikdeath:BAABLgAECn8pAAMTAAkJlRfpKwApAgATAAcJbxjpKwApAgAUAAcJTgx+FQAKAQAAAA==.Armorscales:BAACLgAFFH8UAAIGAAYJ+xrvKQCUAQAGAAYJ+xrvKQCUAQAuAAQKfy0AAgYACQm/IVgQAPcCAAYACQm/IVgQAPcCAAAA.Arniix:BAAALgAECgEJAQABLgAECgQJDQAEAAAAAA==.Arnixskitty:BAAALgAECgEJAQABLgAECgQJDQAEAAAAAA==.Arntraz:BAAALgADCgkJSAAAAA==.Arçadia:BAAALgAECgMJBQAAAA==.',
As='Ashegen:BAAALgAECgQJBAAAAA==.Ashnikko:BAAALgAECgEJAQAAAA==.Ashtori:BAAALgADCgEJAgAAAA==.Asis:BAAALgAECgEJAQAAAA==.Asprika:BAAALgAECgMJAwAAAA==.Astayoni:BAAALgADCgEJAQAAAA==.Astrine:BAACLgAFFH8UAAIVAAYJyBZVOgCFAQAVAAYJyBZVOgCFAQAuAAQKfysAAhUACQlJIAYiAOsCABUACQlJIAYiAOsCAAAA.',
Au='Auberon:BAABLgAECn8oAAIWAAkJ/xl6BgCSAgAWAAkJ/xl6BgCSAgAAAA==.Aufta:BAABLgAECn8wAAIXAAkJPAc7NwAiAQAXAAkJPAc7NwAiAQAAAA==.Aumer:BAAALgAECgEJAQAAAA==.',
Av='Avalonia:BAAALgAECgEJAQAAAA==.',
Az='Azdh:BAAALgAECgQJBgAAAA==.Azi:BAACLgAFFH8cAAIUAAcJix7kCADWAQAUAAcJix7kCADWAQAuAAQKfykAAhQACQkGIMUDAIYCABQACQkGIMUDAIYCAAAA.Azshanorel:BAAALgADCgcJBwAAAA==.Azunea:BAAALgAECgIJBwAAAA==.Azurite:BAAALgAECgkJDwAAAA==.',
Ba='Backpedal:BAABLgAECn8VAAIXAAcJFBKhLwBHAQAXAAcJFBKhLwBHAQAAAA==.Badankhadonk:BAACLgAFFH8UAAIJAAUJaCIIEQDTAQAJAAUJaCIIEQDTAQAuAAQKfy0AAgkACQl7JVICAF8DAAkACQl7JVICAF8DAAAA.Balen:BAABLgAECn80AAIDAAkJqhbtCgAXAgADAAkJqhbtCgAXAgAAAA==.Bandrösh:BAAALgADCgMJAwAAAA==.Barradune:BAAALgADCgYJDAAAAA==.Baubles:BAAALgAECgMJAgAAAA==.',
Be='Belholy:BAABLgAECn8xAAIYAAkJzB/cBQAVAwAYAAkJzB/cBQAVAwAAAA==.Beliice:BAAALgADCgkJIAABLgAECgkJMQAYAMwfAA==.Bellanei:BAAALgAECgEJBAAAAA==.Ben:BAAALgAECgEJAQAAAA==.Benafflockk:BAAALgADCggJCAAAAA==.Benefitdruid:BAAALgAECgEJAQAAAA==.Benilok:BAACLgAFFH8RAAMGAAUJ+yGfHwDGAQAGAAUJ+yGfHwDGAQAZAAEJ6hDLJgBGAAAuAAQKfysAAgYACQkcJSEMABkDAAYACQkcJSEMABkDAAAA.Bethgibbons:BAAALgADCgkJQQAAAA==.',
Bi='Bibimbap:BAAALgAECgEJAQAAAA==.Bigsuccubus:BAABLgAECn8cAAIZAAkJ0xbVBAAoAgAZAAkJ0xbVBAAoAgAAAA==.Biohazard:BAAALgADCgUJBQAAAA==.Bizël:BAAALgAECgYJDQAAAA==.',
Bl='Blackblood:BAABLgAECn8mAAIBAAkJLRXUEwDyAQABAAkJLRXUEwDyAQAAAA==.Blackclouds:BAAALgADCgkJCQAAAA==.Blackspiral:BAAALgADCgEJAQAAAA==.Bladestriker:BAAALgAECgUJBwAAAA==.Blindside:BAAALgAECgMJBgAAAA==.Bloodache:BAABLgAECn8VAAISAAcJKSFgKQBcAgASAAcJKSFgKQBcAgAAAA==.Bloodkissed:BAAALgADCgUJBgABLgAECgkJOAAYAEQgAA==.Bluebuberry:BAAALgAECgQJBgAAAA==.Bluesaphire:BAAALgAECgIJAgAAAA==.Blux:BAAALgAECgQJCAAAAA==.',
Bo='Boil:BAABLgAECn8kAAIOAAgJbgcjDwAXAQAOAAgJbgcjDwAXAQAAAA==.Bonemarrow:BAABLgAECn8XAAIFAAUJPRDl2wDgAAAFAAUJPRDl2wDgAAAAAA==.Bournx:BAAALgAECgIJAgAAAA==.Boysenbar:BAAALgADCgYJCAAAAA==.',
Br='Bradrenna:BAACLgAFFH8LAAMBAAQJ2wz9FgDkAAABAAQJuQX9FgDkAAACAAIJWRRSDAB9AAAuAAQKf1cABAIACQlPG+UEAGICAAIACQlPG+UEAGICAAEAAglaDwhXAFwAABIAAQmlAcf0ABsAAAAA.Brakeable:BAAALgAECgUJBQAAAA==.Braké:BAABLgAECn8eAAIDAAkJaB0/BQCcAgADAAkJaB0/BQCcAgAAAA==.Brandrale:BAAALgAECgEJAwAAAA==.Breakthrough:BAABLgAECn8hAAIJAAYJOCM3HgBYAgAJAAYJOCM3HgBYAgAAAA==.Brenzull:BAAALgADCgYJCwAAAA==.Brewskies:BAABLgAECn8nAAIaAAcJDyVqDABtAgAaAAcJDyVqDABtAgABLgAECgkJNQAbAPYiAA==.Brewsli:BAAALgADCgIJAgABLgAECgkJIAAcABULAA==.Brightstar:BAAALgAECgcJEwAAAA==.Brokenaltar:BAABLgAECn8VAAMBAAYJNRheOQAdAQASAAYJgRFacwBLAQABAAUJCRpeOQAdAQAAAA==.Brownington:BAACLgAFFH8GAAMWAAMJJRJJFACGAAAWAAIJFA1JFACGAAANAAEJSByCNABLAAAuAAQKfxkAAw0ABwlWJNIIAFsCAA0ABwlWJNIIAFsCABYAAQmjCgFVACsAAAAA.Bruhilda:BAABLgAECn8dAAIVAAkJ7hKuSgD4AQAVAAkJ7hKuSgD4AQAAAA==.Brymstone:BAAALgAECgQJBwAAAA==.Brynthebuff:BAAALgAECgEJAQAAAA==.Brìonik:BAACLgAFFH8eAAMZAAcJ5h1XCAAPAQAGAAYJABtpKACaAQAZAAQJTx9XCAAPAQAuAAQKfyoAAxkACQkPJIoFAA8CABkABgkoJYoFAA8CAAYABQkeI2pyAFQBAAAA.',
Bu='Bufferfish:BAABLgAECn82AAIdAAkJUQxELgB/AQAdAAkJUQxELgB/AQAAAA==.',
Ca='Calinnea:BAABLgAECn8VAAMeAAgJDBBpMgCnAQAeAAgJDBBpMgCnAQAXAAIJDgOFiAAnAAAAAA==.Cantheartitz:BAABLgAECn8WAAIVAAUJPxmBnQCbAQAVAAUJPxmBnQCbAQAAAA==.Catastrophe:BAABLgAECn8pAAIXAAkJJSJuBAAPAwAXAAkJJSJuBAAPAwAAAA==.',
Ce='Celira:BAAALgADCgMJAwAAAA==.Celthol:BAABLgAECn8hAAISAAYJwxSebgBCAQASAAYJwxSebgBCAQAAAA==.',
Ch='Chelraani:BAABLgAECn9AAAIFAAkJMSQcBgA/AwAFAAkJMSQcBgA/AwAAAA==.Chiichard:BAAALgADCgYJCgAAAA==.Chipnuts:BAABLgAECn8bAAIXAAkJ8CTAAgBtAwAXAAkJ8CTAAgBtAwAAAA==.Chonchoo:BAAALgADCgEJAQAAAA==.Chosethebear:BAAALgADCgkJEAAAAA==.Chunkamonk:BAAALgADCgUJBgAAAA==.',
Ci='Cigar:BAAALgAECgQJCQABLgAFFAcJGAAPAFQaAA==.Cinderat:BAAALgADCgEJAQAAAA==.',
Cl='Clambumper:BAAALgAECgEJAQAAAA==.Clarabellax:BAAALgAECgQJBQAAAA==.Clarkkentt:BAAALgADCgcJDQAAAA==.Claymore:BAACLgAFFH8RAAIQAAYJBBYtDgCOAQAQAAYJBBYtDgCOAQAuAAQKfxUAAhAACAkMGcscAGcCABAACAkMGcscAGcCAAAA.Clazzicola:BAACLgAFFH8PAAMeAAUJPxLaJQAwAQAeAAUJPxLaJQAwAQAXAAMJJgvADQCWAAAuAAQKfx8ABBcACQmbFmIeAOUBABcABwlYHGIeAOUBAB4ACAniEYomAH4BABoAAQlhA8uVAB8AAAAA.Cloudbeast:BAAALgAECgMJBAABLgAECgcJEAAEAAAAAA==.Clue:BAAALgADCgYJBgAAAA==.',
Co='Cocito:BAAALgAECgEJAwAAAA==.Commândment:BAAALgAECgcJDgAAAA==.Conjredcukee:BAABLgAECn8WAAIVAAcJ7AN45ADQAAAVAAcJ7AN45ADQAAAAAA==.Coo:BAAALgAECgQJBAABLgAECgUJBwAEAAAAAA==.Coogsayer:BAABLgAECn8UAAIHAAcJyh2aEQBxAgAHAAcJyh2aEQBxAgAAAA==.Couch:BAAALgAECgUJBQAAAA==.',
Cp='Cptncrush:BAABLgAECn8fAAMJAAgJBBqMKAAYAgAJAAgJBBqMKAAYAgAKAAMJoBcRaQCoAAAAAA==.',
Cr='Crackstalion:BAAALgAECgEJAQAAAA==.Croquetica:BAAALgADCgMJBAAAAA==.Crossed:BAAALgADCgcJCwAAAA==.Crowshadow:BAABLgAECn8cAAIGAAgJ8BrCKAA3AgAGAAgJ8BrCKAA3AgAAAA==.',
Cy='Cylina:BAAALgADCgcJCAABLgADCgcJFAAEAAAAAA==.Cyliya:BAAALgADCgIJAwABLgADCgcJFAAEAAAAAA==.Cylore:BAAALgADCgcJBgABLgADCgcJFAAEAAAAAA==.Cypherrellik:BAAALgAECgMJAwABLgAECgkJHAABAIUQAA==.Cyrax:BAAALgADCgYJCQAAAA==.Cyther:BAACLgAFFH8iAAIQAAcJjSCsBAAcAgAQAAcJjSCsBAAcAgAuAAQKfykAAhAACQmXIqwHAC4DABAACQmXIqwHAC4DAAAA.',
['Cÿ']='Cÿthera:BAABLgAECn8bAAISAAkJ4BzDHAClAgASAAkJ4BzDHAClAgAAAA==.',
Da='Dakk:BAABLgAECn9KAAIPAAkJOiMOCgAdAwAPAAkJOiMOCgAdAwAAAA==.Dangbor:BAAALgAECgEJAQABLgAECgkJLwALAFkWAA==.Daraghor:BAABLgAECn8bAAINAAkJoCIMAgAbAwANAAkJoCIMAgAbAwAAAA==.Darkdottie:BAAALgAECgQJCAAAAA==.Darkenstormy:BAAALgAECgcJDwAAAA==.Darlyndra:BAAALgADCgUJBQAAAA==.Darsae:BAAALgAECgQJDAAAAA==.Darthiono:BAAALgAECgEJAQAAAA==.Darthmaull:BAAALgADCgEJAQAAAA==.',
De='Deadlight:BAABLgAECn8wAAMPAAkJ+BEZUgDLAQAPAAkJZBEZUgDLAQAcAAEJYBKmNwA4AAAAAA==.Deathkillhun:BAAALgAECgQJBwAAAA==.Deathpooch:BAAALgAFFAEJAQAAAA==.Deathshooter:BAAALgAECgcJAQAAAA==.Deavant:BAAALgADCgMJAwAAAA==.Deermon:BAAALgAECgYJCwAAAA==.Deet:BAAALgAECgUJBQAAAA==.Deforest:BAAALgADCgcJFgAAAA==.Deity:BAABLgAECn8yAAIQAAkJMSTAAwArAwAQAAkJMSTAAwArAwAAAA==.Demogon:BAAALgAECgQJBwAAAA==.Demondeano:BAABLgAECn8bAAISAAkJAROlSQCmAQASAAkJAROlSQCmAQAAAA==.Demonllxll:BAAALgAECgYJCwAAAA==.Demonlxl:BAABLgAECn8cAAIKAAgJ/xW1IQDTAQAKAAgJ/xW1IQDTAQAAAA==.Demonthorx:BAAALgAECgUJBQAAAA==.Demonx:BAABLgAECn8zAAIPAAkJ+x3oGQCpAgAPAAkJ+x3oGQCpAgAAAA==.Dennis:BAAALgAECgYJCAABLgAECgkJFQAFAAIVAA==.Desolation:BAABLgAECn9SAAIfAAkJ+iUkAABuAwAfAAkJ+iUkAABuAwAAAA==.Despia:BAABLgAECn87AAMYAAkJZCSpAQCcAwAYAAkJZCSpAQCcAwAHAAYJzxHlMQBSAQAAAA==.Devastacia:BAAALgADCgUJBQAAAA==.Deviarc:BAAALgAECgQJBAABLgAFFAYJGQALAP8cAA==.',
Dh='Dharkon:BAAALgAECgIJBAAAAA==.',
Di='Dicot:BAABLgAECn8yAAIgAAkJRxOMJgAYAgAgAAkJRxOMJgAYAgAAAA==.',
Dj='Djpallyd:BAAALgAECgkJEAAAAA==.',
Do='Doinks:BAAALgAECgIJAgAAAA==.Domilthri:BAACLgAFFH8LAAIGAAMJhANKiwCoAAAGAAMJhANKiwCoAAAuAAQKf0EAAwYACAlCEABfAIIBAAYACAlCEABfAIIBACEABgnyBUMQACoBAAAA.Dontormenta:BAAALgAECgcJCAAAAA==.Donut:BAAALgADCgIJAgABLgAECggJHgAiACchAA==.Dotdaddy:BAAALgAECgQJBwABLgAECggJFQAeAAwQAA==.Doughy:BAAALgAECgYJBgAAAA==.',
Dr='Dracoly:BAAALgAECggJEgAAAA==.Draconu:BAACLgAFFH8mAAIdAAYJ+xlMFwCkAQAdAAYJ+xlMFwCkAQAuAAQKfyIAAx0ACQk4H1kMAJQCAB0ACQk4H1kMAJQCAAsAAQmaAX1OACIAAAAA.Draenyth:BAABLgAECn8bAAISAAcJKBDpagBLAQASAAcJKBDpagBLAQAAAA==.Dragoncurry:BAABLgAECn8WAAILAAYJIga1JwCqAAALAAYJIga1JwCqAAAAAA==.Dragonmite:BAAALgAECgEJAQAAAA==.Drakka:BAAALgADCgkJDgABLgAECgkJFQAFAAIVAA==.Draktyr:BAACLgAFFH8GAAIQAAMJtRZeFgCyAAAQAAMJtRZeFgCyAAAuAAQKfyQAAhAACQn2HncJABYDABAACQn2HncJABYDAAAA.Draxoths:BAAALgAECgMJBQABLgAFFAMJBwAgADkZAA==.Dropeadita:BAAALgAECgQJBAAAAA==.Droptop:BAAALgADCgcJCAAAAA==.Druadh:BAAALgADCgYJBgABLgAECgIJAgAEAAAAAA==.',
Du='Dumbsht:BAABLgAECn8ZAAMUAAgJ6xbDMQCpAQAUAAcJ6xXDMQCpAQATAAYJVhHjXQBOAQAAAA==.',
Dy='Dyvyne:BAAALgAECgQJBwAAAA==.',
Ea='Easystreet:BAAALgAECgIJAwAAAA==.',
Ef='Effluv:BAAALgADCgcJDgAAAA==.',
El='Elandir:BAAALgADCgQJAQAAAA==.Elanora:BAAALgAECgYJCQAAAA==.Elbrookel:BAAALgAECgIJAgAAAA==.Eleshnorn:BAAALgAFFAEJAwAAAA==.Eliza:BAAALgADCgkJCQAAAA==.Ellismom:BAABLgAECn9BAAIPAAkJ+SFzDQD/AgAPAAkJ+SFzDQD/AgAAAA==.Elosong:BAAALgAECgEJAQAAAA==.Elvea:BAABLgAECn8kAAMdAAgJjRrLGQAHAgAdAAgJjRrLGQAHAgAiAAEJ9QoWQgArAAABLgAFFAYJGAAjADMUAA==.',
Em='Emeralddemon:BAAALgAECgUJCQAAAA==.Emeraldshade:BAAALgADCgcJDwABLgAECgUJCQAEAAAAAA==.Emeråld:BAAALgAECgUJBwAAAA==.',
En='Enamorada:BAAALgAECgIJAgABLgAECgIJAgAEAAAAAA==.',
Er='Eregon:BAAALgADCgYJBgAAAA==.Ereithelda:BAACLgAFFH8gAAMeAAcJ4BLmFQDCAQAeAAcJ4BLmFQDCAQAXAAIJOxX6LACOAAAuAAQKfyYAAh4ACAm2IhcHAOkCAB4ACAm2IhcHAOkCAAAA.Ericka:BAAALgAECgIJAgAAAA==.Erowid:BAAALgAECgcJBwABLgAFFAYJJgAdAPsZAA==.Erreya:BAAALgADCgEJAQAAAA==.',
Es='Esma:BAAALgADCgkJCQAAAA==.',
Ev='Evox:BAAALgAECggJEwAAAA==.',
Ey='Eyris:BAAALgADCgMJAwAAAA==.Eyrndor:BAAALgADCgIJAwAAAA==.',
Fa='Faacee:BAAALgAECgIJAgAAAA==.Falgar:BAAALgAECgMJAwAAAA==.Fann:BAABLgAECn8gAAIgAAkJgAT0agDxAAAgAAkJgAT0agDxAAAAAA==.Fauna:BAAALgAECgYJBwAAAA==.Fawn:BAAALgAECgIJBAAAAA==.Faytl:BAAALgAECgMJAwAAAA==.',
Fe='Felbubu:BAABLgAECn8jAAQCAAkJlyIeBACAAgACAAkJLCIeBACAAgABAAYJOyAmIgCrAQASAAMJNRxKpQDVAAAAAA==.Femboy:BAAALgAECgUJDgAAAA==.Fewz:BAACLgAFFH8MAAIVAAQJ3BjydAD3AAAVAAQJ3BjydAD3AAAuAAQKfyQAAhUACQnjIXIcAK4CABUACQnjIXIcAK4CAAAA.',
Fi='Fireybuns:BAAALgAECgEJAwAAAA==.',
Fl='Flakiron:BAACLgAFFH8ZAAIkAAYJAhPKEQATAQAkAAYJAhPKEQATAQAuAAQKfy0AAiQACQkjHJkLAFQCACQACQkjHJkLAFQCAAAA.Flakov:BAAALgAECgIJAgABLgAFFAYJGQAkAAITAA==.Flaktop:BAAALgAECgUJCAABLgAFFAYJGQAkAAITAA==.Fler:BAAALgAECgQJCAAAAA==.',
Fo='Forbacon:BAABLgAECn8gAAMcAAkJFQu/EwA9AQAcAAkJuAq/EwA9AQAPAAYJgQlC0QDjAAAAAA==.Force:BAABLgAECn8iAAQcAAkJygrcEQBWAQAcAAgJnwvcEQBWAQAPAAUJEASgEAGSAAAbAAEJ+wRQZQAcAAAAAA==.Fornost:BAAALgADCgkJDgAAAA==.Forsaken:BAAALgAECgYJDAABLgAECgkJMgAQADEkAA==.Fourdragon:BAAALgADCgQJBAABLgAECggJFwAKACQXAA==.Fouris:BAABLgAECn8XAAIKAAgJJBc7KgCcAQAKAAgJJBc7KgCcAQAAAA==.',
Fr='Fremosth:BAAALgADCgMJAwAAAA==.Fretman:BAAALgADCgcJCQAAAA==.Fridgie:BAACLgAFFH8YAAITAAUJZhkzBABdAQATAAUJZhkzBABdAQAuAAQKfyMAAhMACQm6Im0PAMACABMACQm6Im0PAMACAAAA.Froline:BAAALgAECgYJDQAAAA==.Frostreaper:BAAALgAECgIJAgAAAA==.Frozenflyer:BAAALgAECgUJEAAAAA==.Frozenturtle:BAABLgAECn8gAAIbAAkJQxwqCwBbAgAbAAkJQxwqCwBbAgAAAA==.Fryea:BAAALgAECgEJAQAAAA==.',
Ft='Ftwiamtank:BAABLgAECn8VAAIkAAYJmw4iKQDnAAAkAAYJmw4iKQDnAAABLgAECggJLQAMAIIMAA==.',
Fu='Fuoco:BAAALgAECgkJCgAAAA==.Furah:BAAALgAECgEJAQAAAA==.',
Ga='Gabriél:BAAALgAECgYJCQAAAA==.Garcutt:BAACLgAFFH8fAAIVAAcJDRaGJADoAQAVAAcJDRaGJADoAQAuAAQKfysAAhUACQm0HZQrAGkCABUACQm0HZQrAGkCAAAA.Gardon:BAAALgAECgYJCgAAAA==.Gaurdinn:BAABLgAECn8uAAQdAAgJMBPwMABxAQAdAAgJrhLwMABxAQAiAAYJfxDKEAD5AAALAAIJagJyOwAyAAABLgAECgkJJQAKAKgYAA==.',
Ge='Gebuss:BAAALgADCgQJBAAAAA==.Generickk:BAAALgAECgIJAgAAAA==.Generickmonk:BAACLgAFFH8YAAIXAAUJox3IDQBMAQAXAAUJox3IDQBMAQAuAAQKfy8AAhcACQnyIpoFAPQCABcACQnyIpoFAPQCAAAA.Gensis:BAAALgADCgYJBgAAAA==.Geomatic:BAAALgAECgEJAQAAAA==.Gethsemåne:BAAALgADCgMJBQAAAA==.',
Gi='Giovannucci:BAAALgAECgEJAgAAAA==.Gitan:BAAALgADCgQJBQAAAA==.',
Gl='Gladstone:BAABLgAECn8VAAIDAAYJ+Ah9KwCxAAADAAYJ+Ah9KwCxAAAAAA==.',
Go='Gomlvirgin:BAAALgADCgYJBgABLgAECggJIgAGAHcUAA==.Gonwean:BAAALgAECgEJAQABLgAFFAYJFAATAAkYAA==.',
Gr='Gracehimeûwû:BAABLgAFFH8FAAIaAAIJahHJSAB3AAAaAAIJahHJSAB3AAAAAA==.Grampsie:BAAALgAECgUJBwAAAA==.Grayeyes:BAAALgAECgMJAwAAAA==.Greenngoblin:BAAALgAFFAEJAQAAAA==.Grimmlie:BAAALgADCgUJBQAAAA==.Grinzler:BAAALgADCgIJAgAAAA==.Grumpybear:BAAALgADCggJDwAAAA==.Grumpykat:BAAALgAECggJEgAAAA==.Grumpypros:BAAALgADCgUJBQAAAA==.',
Gt='Gtatedk:BAAALgAFFAEJAgAAAA==.',
Gu='Guino:BAAALgAECgUJCwAAAA==.Guinodruid:BAAALgADCgcJDgAAAA==.',
Gw='Gwenelly:BAAALgAECgEJAQAAAA==.',
Ha='Hamncheeks:BAAALgAECgEJAQAAAA==.Hamnqueso:BAAALgAECgIJAgAAAA==.Haptism:BAAALgADCgcJBwAAAA==.Hardeesdelux:BAAALgAECgYJBwABLgAECgcJEAAEAAAAAA==.Hardnarples:BAAALgADCgEJAQAAAA==.Hayzerade:BAAALgAECgYJCAAAAA==.Hazis:BAABLgAECn8rAAIbAAkJEyEbCACkAgAbAAkJEyEbCACkAgAAAA==.',
Hi='Highflyr:BAAALgAECgEJAQAAAA==.Hinala:BAAALgADCgIJAgAAAA==.Hippiecritz:BAAALgADCgYJBwAAAA==.Hitokiri:BAAALgADCgMJAwAAAA==.',
Ho='Holy:BAACLgAFFH8YAAIDAAYJ/Qj8BwD1AAADAAYJ/Qj8BwD1AAAuAAQKfywAAgMACQmkFvMQALcBAAMACQmkFvMQALcBAAAA.Holydad:BAACLgAFFH8FAAIDAAQJzA9mDQCgAAADAAQJzA9mDQCgAAAuAAQKfywAAgMACAkHICMKACYCAAMACAkHICMKACYCAAAA.Holydust:BAAALgAECgcJEQAAAA==.Holyhoette:BAAALgADCgQJBAAAAA==.Holymoki:BAAALgAECggJCAAAAA==.Holymoliie:BAAALgADCgEJAQAAAA==.Holyroundie:BAABLgAECn9PAAIYAAkJqBOYGAAEAgAYAAkJqBOYGAAEAgAAAA==.Holyshock:BAACLgAFFH8hAAIFAAcJRxsEEQDXAQAFAAcJRxsEEQDXAQAuAAQKfykAAgUACQlkJWUIACUDAAUACQlkJWUIACUDAAAA.Holystax:BAAALgAECgEJBAAAAA==.Honeybutter:BAACLgAFFH8hAAMRAAYJByYNBQAaAgARAAYJ9SUNBQAaAgAQAAUJ2SWCCQC/AQAuAAQKfzsAAxEACQkzJvsAAGkDABEACQkzJvsAAGkDABAABwmLHtAjADgCAAAA.Hordebreaker:BAAALgAECgYJEQAAAA==.Hotflash:BAAALgAECgEJAQAAAA==.',
Hu='Huukend:BAABLgAECn9OAAITAAkJ6yPrBQAyAwATAAkJ6yPrBQAyAwAAAA==.',
Ib='Iblindbenice:BAAALgAECgYJBgAAAA==.',
Ic='Icebabyman:BAABLgAECn8fAAIVAAgJER7kOACSAgAVAAgJER7kOACSAgAAAA==.Icedmoki:BAAALgADCgQJBAAAAA==.',
Im='Imnotspeed:BAAALgAECgcJCAAAAA==.',
In='Inanitas:BAAALgADCgcJBwAAAA==.Ineffectual:BAABLgAECn8fAAIJAAgJvBMeMgC9AQAJAAgJvBMeMgC9AQAAAA==.',
Ir='Irion:BAAALgADCgMJAwAAAA==.Irukox:BAAALgAECgYJDQAAAA==.',
It='Itty:BAAALgADCgcJBwAAAA==.',
Ja='Jadaveon:BAAALgAECgQJBAAAAA==.Jadefleur:BAAALgAECgEJAQAAAA==.Jagger:BAAALgADCgcJCQAAAA==.Jalene:BAAALgAECgYJDwAAAA==.Janewayy:BAABLgAECn8yAAISAAkJGA0AYQBjAQASAAkJGA0AYQBjAQAAAA==.Jazmean:BAAALgAECgcJEQAAAA==.',
Jb='Jbournz:BAAALgADCgQJBAAAAA==.',
Je='Jeks:BAAALgADCgcJBwABLgAFFAcJIAAJANwXAA==.Jemma:BAABLgAECn8vAAIZAAkJ6hRTBgD5AQAZAAkJ6hRTBgD5AQAAAA==.Jerikos:BAAALgADCgYJBgAAAA==.Jettadari:BAACLgAFFH8RAAISAAcJ5RMXEABNAQASAAcJ5RMXEABNAQAuAAQKfyYAAxIACQlsIO0WAM0CABIACQlsIO0WAM0CAAIAAQlADk00ADAAAAAA.Jettadin:BAABLgAECn8aAAIFAAgJ9yGnDwARAwAFAAgJ9yGnDwARAwABLgAFFAcJEQASAOUTAA==.Jettakins:BAAALgAFFAEJAQABLgAFFAcJEQASAOUTAA==.Jettathyr:BAAALgAECgcJDQABLgAFFAcJEQASAOUTAA==.',
Ju='Jubba:BAABLgAECn8fAAIVAAkJ1xTVRwABAgAVAAkJ1xTVRwABAgAAAA==.Juderius:BAAALgADCgQJBAABLgAECgYJEwAEAAAAAA==.Junk:BAABLgAECn81AAIbAAkJ9iLaAgAZAwAbAAkJ9iLaAgAZAwAAAA==.',
['Jë']='Jëks:BAACLgAFFH8gAAIJAAcJ3BcEDQD9AQAJAAcJ3BcEDQD9AQAuAAQKfykAAwkACQlhJXEDAEEDAAkACQlhJXEDAEEDAAwAAgkvDloyAGEAAAAA.',
Ka='Kaghroxxar:BAAALgADCgkJIAAAAA==.Kahea:BAAALgAECgQJBAAAAA==.Kaitou:BAABLgAECn82AAMWAAkJMSJXAwDdAgAWAAkJMSJXAwDdAgAlAAEJrQ7DjQAvAAAAAA==.Kalamiti:BAABLgAECn8eAAMZAAkJFRP2DABrAQAZAAgJCQ/2DABrAQAhAAcJ/hBtDwBiAQAAAA==.Kallar:BAABLgAECn84AAMYAAkJRCBsBgAKAwAYAAkJRCBsBgAKAwAHAAIJUQZWdwBMAAAAAA==.Karesh:BAAALgAECgQJBAAAAA==.Katween:BAAALgADCgcJBwABLgAECgIJAgAEAAAAAA==.Kayeera:BAABLgAECn8dAAMYAAgJ8xW2GwDlAQAYAAgJ8xW2GwDlAQAHAAQJBQUDTwCWAAAAAA==.Kayha:BAAALgADCgYJCAAAAA==.Kaylrandi:BAABLgAECn8UAAIVAAcJKQJ7/gCqAAAVAAcJKQJ7/gCqAAAAAA==.Kazarath:BAAALgAECgEJAQAAAA==.Kaztiel:BAAALgAECgIJAgAAAA==.',
Ke='Keadon:BAAALgAFFAEJAQAAAA==.Kearza:BAAALgAECgQJCAAAAA==.Keeper:BAAALgAECgUJBQABLgAECgkJMgAQADEkAA==.Keh:BAAALgADCgkJCQAAAA==.Keiyona:BAAALgAECgcJCgABLgAECgkJIgAFAKodAA==.Keladas:BAAALgAECgUJBQAAAA==.Kennethv:BAAALgAECggJDgAAAA==.Kenze:BAAALgAECgEJAQAAAA==.Kethra:BAAALgADCggJEgAAAA==.Kev:BAAALgAECgcJBwAAAA==.',
Kh='Khel:BAAALgADCgcJBwAAAA==.Khibanee:BAAALgADCgQJBAAAAA==.Khiell:BAACLgAFFH8LAAIQAAQJgQ+zKwD+AAAQAAQJgQ+zKwD+AAAuAAQKfyIAAhAACQkmGusaABUCABAACQkmGusaABUCAAAA.',
Ki='Kilyse:BAAALgADCgYJBgAAAA==.Kinigit:BAAALgAFFAQJBAABLgAFFAYJGQAlAMMZAA==.Kirïtö:BAAALgAECgUJCwAAAA==.Kitarah:BAEALgAECgIJAgABLgAECgkJEAAEAAAAAA==.Kitarazen:BAEALgAECgkJEAAAAA==.Kizli:BAAALgAECgUJBQAAAA==.',
Kn='Knoway:BAAALgAECgMJAwAAAA==.',
Ko='Kokushimosu:BAAALgAECgYJDgAAAA==.Koo:BAAALgAECgUJBwAAAA==.Koviel:BAAALgAECgYJBwAAAA==.',
Kr='Kragon:BAAALgAECgkJEQAAAA==.Krátos:BAABLgAECn8oAAMRAAkJBxrLCABiAgARAAkJBxrLCABiAgAQAAgJaRG7MQCFAQAAAA==.',
Ks='Ksper:BAAALgAECgcJEgAAAA==.',
Ku='Kukalak:BAABLgAECn8YAAIkAAgJ7BvSEQDrAQAkAAgJ7BvSEQDrAQAAAA==.Kuranaa:BAAALgAECgMJAQABLgAECgYJEwAEAAAAAA==.Kurulak:BAABLgAECn82AAISAAkJHxPbNwDjAQASAAkJHxPbNwDjAQAAAA==.Kuzcotopiajr:BAAALgADCgEJAQAAAA==.',
Ky='Kymru:BAAALgADCgcJDQAAAA==.Kynigoshanta:BAAALgADCgEJAQAAAA==.',
['Ké']='Kénnéth:BAAALgAECgYJEQAAAA==.',
La='Lacerveza:BAAALgAECgIJBQAAAA==.Lahyanhou:BAABLgAECn84AAIUAAkJawiZEQA8AQAUAAkJawiZEQA8AQAAAA==.Lalalalala:BAAALgAECgcJCgAAAA==.Lalin:BAAALgAECgEJBQAAAA==.Larkwyn:BAAALgAECgQJBAABLgAFFAYJEAAGAI8NAA==.Laylah:BAAALgADCgYJBAAAAA==.',
Le='Lebrand:BAAALgAECgEJAQAAAA==.Leriope:BAABLgAECn9aAAIGAAkJhxqUGwB9AgAGAAkJhxqUGwB9AgAAAA==.Leàf:BAABLgAECn8aAAIJAAgJFhmoHgBVAgAJAAgJFhmoHgBVAgAAAA==.',
Li='Lichfiend:BAAALgADCgEJAQAAAA==.Lightbeer:BAAALgAECgYJBwAAAA==.Lihpfu:BAAALgAFFAIJAwABLgAFFAQJHAAQAJclAA==.Lihplock:BAAALgAECgQJCAABLgAFFAQJHAAQAJclAA==.Lilandri:BAAALgAECgYJBwAAAA==.Lildragonboi:BAAALgADCgUJBQAAAA==.Lilem:BAAALgADCgcJEgAAAA==.Lilpooch:BAAALgAECgYJEAAAAA==.Listenlinda:BAAALgAECgMJBQAAAA==.Lithariel:BAAALgADCgkJCAAAAA==.Littlemerald:BAAALgAECgUJEgAAAA==.',
Lj='Lj:BAABLgAECn9TAAImAAkJDB/QCgDeAgAmAAkJDB/QCgDeAgAAAA==.',
Lo='Localsingles:BAAALgADCgcJBwAAAA==.Lorath:BAAALgADCgEJAQAAAA==.Lovecrafft:BAAALgAECgQJCwAAAA==.Lovetrain:BAAALgAECgYJBQAAAA==.',
Lu='Lu:BAABLgAFFH8HAAMbAAMJzxc3PwAvAAAPAAIJzxcT2QCIAAAbAAIJtA43PwAvAAABLgAFFAUJDwAeAD8SAA==.Lucinà:BAABLgAECn8+AAQFAAkJeSLEFgC4AgAFAAgJ8CPEFgC4AgAmAAkJQR+TDAC1AgADAAUJkB0/HAAwAQAAAA==.Lusande:BAAALgAECgQJBgAAAA==.Luxure:BAAALgAECgYJBgAAAA==.Luxùria:BAAALgAECgIJAgAAAA==.',
Ly='Lyndall:BAAALgAECgQJBgAAAA==.',
Ma='Machamp:BAAALgAECgYJDAAAAA==.Madammìm:BAAALgAECgYJBgAAAA==.Maegan:BAABLgAECn8aAAIFAAcJHwk1vAALAQAFAAcJHwk1vAALAQAAAA==.Maewyn:BAAALgAECgEJAgAAAA==.Mager:BAAALgAECgUJEAAAAA==.Magerhunter:BAAALgAECgYJCAAAAA==.Magolock:BAAALgAECgUJEgAAAA==.Mahll:BAAALgAECgMJAwAAAA==.Maidrim:BAACLgAFFH8aAAInAAcJ3xYVAQD9AQAnAAcJ3xYVAQD9AQAuAAQKfx8AAicACQmrIfICALICACcACQmrIfICALICAAAA.Makaveli:BAAALgAECgcJDwAAAA==.Makavelli:BAAALgADCgEJAQAAAA==.Mamajumbo:BAABLgAECn8fAAITAAkJexw8FgCeAgATAAkJexw8FgCeAgAAAA==.Marage:BAAALgADCgEJAQAAAA==.Marellias:BAAALgAECgMJBAABLgAFFAMJBQAFACQdAA==.Marikel:BAAALgAECgUJEwAAAA==.Markwel:BAAALgAECgIJAgAAAA==.Marrack:BAAALgAECgYJDQAAAA==.',
Me='Melador:BAAALgADCgIJAgAAAA==.Meletha:BAAALgAECgYJDwAAAA==.Melpuis:BAAALgAECgEJAgAAAA==.Merinda:BAAALgAECgEJAQAAAA==.Metahorfasis:BAAALgAECgUJBQAAAA==.',
Mi='Michaelken:BAABLgAECn8iAAMmAAkJDhfKFQBbAgAmAAkJDhfKFQBbAgAFAAEJsAfYkwEvAAAAAA==.Mierín:BAAALgADCgYJBgAAAA==.Migrains:BAABLgAECn9bAAIDAAkJQCXlAABVAwADAAkJQCXlAABVAwAAAA==.Mineo:BAAALgAECgYJBwAAAA==.Mirâjâne:BAAALgAECgEJAQAAAA==.Miskaabin:BAABLgAECn81AAMFAAkJARLHTADeAQAFAAkJARLHTADeAQADAAUJogr+MwCOAAAAAA==.Miststress:BAAALgAECgcJCAAAAA==.',
Mo='Mobal:BAABLgAECn88AAMJAAkJhhxeEwCuAgAJAAkJhhxeEwCuAgAKAAQJxgiteAB/AAAAAA==.Modarku:BAAALgADCgQJBAAAAA==.Mojogreens:BAAALgAECgYJEQAAAA==.Montydh:BAAALgAECgEJAQAAAA==.Moonblades:BAAALgADCgUJBQAAAA==.Moonpetals:BAAALgAECgMJBQAAAA==.Moonrush:BAAALgAECgMJCAAAAA==.Mortiis:BAABLgAECn8UAAMMAAcJ6gubFgBWAQAMAAcJ6gubFgBWAQAJAAIJowc0kABYAAAAAA==.Motako:BAABLgAECn8gAAIJAAcJRCCfFQBoAgAJAAcJRCCfFQBoAgAAAA==.',
Mp='Mpd:BAABLgAECn8VAAIWAAcJthabEQCaAQAWAAcJthabEQCaAQAAAA==.',
My='Mybizël:BAABLgAECn8pAAITAAcJwR7oIABAAgATAAcJwR7oIABAAgAAAA==.Myrlifax:BAAALgADCgEJAQABLgAECgkJFQAFAAIVAA==.Mystique:BAABLgAECn8XAAICAAkJbwh5EABAAQACAAkJbwh5EABAAQAAAA==.Mythdaraghma:BAABLgAECn8UAAIBAAYJNQghPADCAAABAAYJNQghPADCAAAAAA==.',
['Má']='Máximo:BAAALgAECgYJEAAAAA==.',
['Mí']='Míerin:BAAALgAECgQJBAAAAA==.Míerín:BAACLgAFFH8WAAIoAAYJYR2oBgCeAQAoAAYJYR2oBgCeAQAuAAQKfzcAAygACQnBJUcCACcDACgACQnBJUcCACcDABMABAm+G0NgAEcBAAAA.',
['Mø']='Møøse:BAAALgAECgQJBwAAAA==.',
Na='Naama:BAAALgADCgkJKAAAAA==.Nadaar:BAABLgAECn8bAAIfAAgJWhlLAwDyAQAfAAgJWhlLAwDyAQAAAA==.Naelih:BAABLgAECn8tAAIUAAkJ+Q0bDQCLAQAUAAkJ+Q0bDQCLAQAAAA==.Naharuk:BAAALgADCgMJAwAAAA==.Natholomas:BAAALgADCgQJBAAAAA==.Natlès:BAAALgAECggJCwABLgAECggJFQAeAAwQAA==.Nattwenty:BAAALgAECgQJBAAAAA==.Nazeer:BAAALgADCgcJBwABLgAFFAUJCQAgAMkEAA==.Nazgrim:BAACLgAFFH8JAAIgAAUJyQR9MQDjAAAgAAUJyQR9MQDjAAAuAAQKfz4AAiAACAnIFlsvAO8BACAACAnIFlsvAO8BAAAA.',
Ne='Necronu:BAABLgAFFH8KAAIPAAMJDBcMlADhAAAPAAMJDBcMlADhAAABLgAFFAYJJgAdAPsZAA==.',
Ni='Nikkolos:BAABLgAECn8cAAIBAAgJ5gzAJABNAQABAAgJ5gzAJABNAQAAAA==.Ninjastax:BAAALgAECgEJAwAAAA==.Nissie:BAAALgAECgEJAQAAAA==.Nitazendezot:BAAALgAFFAEJAwABLgAFFAQJDgAPALsVAA==.',
No='Nogusta:BAACLgAFFH8ZAAIQAAYJNxyEDgCLAQAQAAYJNxyEDgCLAQAuAAQKfykAAhAACQloH2kLAP8CABAACQloH2kLAP8CAAAA.Norberta:BAABLgAECn8jAAMdAAkJBAiINwBOAQAdAAkJ8AeINwBOAQAiAAYJWAbxIwAIAQAAAA==.Nossanir:BAAALgAECgIJAgAAAA==.Nossellia:BAAALgAECgQJBwAAAA==.',
Nu='Nuggetssham:BAAALgAECgEJAQAAAA==.Nurana:BAAALgADCgEJAQAAAA==.',
Ny='Nycecritz:BAAALgAECgEJAQAAAA==.',
['Nä']='Näturi:BAAALgAECgQJBAAAAA==.',
Od='Odor:BAAALgAECgQJBgAAAA==.',
Ol='Oldie:BAAALgAFFAEJAQAAAA==.Olielno:BAAALgADCgMJAwAAAA==.',
On='Onlyshams:BAABLgAECn8hAAIJAAgJtBgvGQBNAgAJAAgJtBgvGQBNAgAAAA==.Onlytides:BAEBLgAECn8dAAMJAAkJ2SPlBwD2AgAJAAkJ2SPlBwD2AgAKAAcJXRiAHwAUAgABLgAFFAcJHgAgAH4bAA==.Onubis:BAACLgAFFH8QAAMTAAUJriF5LABSAQATAAUJriF5LABSAQAoAAIJ5yBiJACoAAAuAAQKfx8ABBMACQmaHw8MAOECABMACQmOHw8MAOECABQABgnGHdk0AJcBACgAAQmkI6xTAFsAAAEuAAUUBgkmAB0A+xkA.Onublue:BAAALgAFFAEJAQABLgAFFAYJJgAdAPsZAA==.Onuchi:BAABLgAFFH8KAAMXAAUJRRElGAD+AAAXAAUJRRElGAD+AAAeAAUJTwSgMwDSAAABLgAFFAYJJgAdAPsZAA==.Onulock:BAAALgAECgYJCgABLgAFFAYJJgAdAPsZAA==.Onux:BAABLgAFFH8SAAISAAYJOBsJIgCgAQASAAYJOBsJIgCgAQABLgAFFAYJJgAdAPsZAA==.',
Op='Opgarbage:BAAALgAECgQJCwAAAA==.',
Ou='Oukei:BAAALgAECgcJEgABLgAFFAYJFAAEAAAAAQ==.Oumura:BAAALgAECgYJDgAAAA==.',
Ov='Overlordainz:BAABLgAECn8UAAMIAAYJeBPfMwBGAQAIAAYJ7hDfMwBGAQAYAAQJLxPjVgDaAAAAAA==.',
Pa='Paarthürnax:BAAALgAECgYJDAAAAA==.Padamee:BAAALgAECgQJBwAAAA==.Paganini:BAAALgAECgQJBAABLgAECgkJHwATAHUdAA==.Pallyoop:BAABLgAECn8WAAImAAcJMg/lVADhAAAmAAcJMg/lVADhAAAAAA==.Pandaa:BAAALgAECgEJAQAAAA==.Papapaw:BAAALgAECgQJBgAAAA==.Pathator:BAAALgAECgYJBgABLgAECgkJGQAPAAYdAA==.Pathaviendha:BAAALgAECgQJAQAAAA==.Patherion:BAAALgADCgEJAQABLgAECgkJGQAPAAYdAA==.Patholans:BAABLgAECn8ZAAIPAAkJBh2rGgClAgAPAAkJBh2rGgClAgAAAA==.Pathology:BAAALgAECgMJAwABLgAECgkJGQAPAAYdAA==.Paxman:BAAALgAECgQJBwAAAA==.',
Pe='Peanits:BAAALgAECgQJCwABLgAECgkJIwACAJciAA==.Peanutsuckr:BAACLgAFFH8hAAIbAAcJGiDoBgAVAgAbAAcJGiDoBgAVAgAuAAQKfykAAhsACQnGJQoCADQDABsACQnGJQoCADQDAAAA.Pearserve:BAAALgADCgYJBgABLgAECggJFAAKANoPAA==.',
Ph='Phantöm:BAAALgAECgQJDAAAAA==.Phosphate:BAABLgAECn8QAAISAAYJNxKvbgBYAQASAAYJNxKvbgBYAQAAAA==.',
Pi='Piccolo:BAAALgAECgQJBgAAAA==.Pingg:BAAALgAECgQJBQAAAA==.Pinkeye:BAAALgAECgcJCgAAAA==.Pippafan:BAAALgAECgEJAQABLgAECgEJAwAEAAAAAA==.',
Pl='Placcid:BAABLgAECn9MAAITAAkJIh0iFgCfAgATAAkJIh0iFgCfAgAAAA==.Planknstein:BAAALgADCgMJAwAAAA==.Playdohh:BAAALgAECgcJCQAAAA==.Plutonia:BAAALgAECgMJBwAAAA==.',
Po='Pockett:BAABLgAECn8iAAMKAAcJKBGSPgA2AQAKAAcJKBGSPgA2AQAMAAUJBQnnGwAMAQAAAA==.Powrwordgoat:BAACLgAFFH8PAAIIAAQJFQ6SKAABAQAIAAQJFQ6SKAABAQAuAAQKfzYAAggACQnRFJgUADQCAAgACQnRFJgUADQCAAAA.',
Pr='Prestoh:BAABLgAECn8zAAIKAAkJvxGlJAC/AQAKAAkJvxGlJAC/AQAAAA==.Prismclaw:BAABLgAECn9SAAIVAAkJhhWqOgAsAgAVAAkJhhWqOgAsAgAAAA==.Prisoner:BAAALgAECgEJAwAAAA==.Processing:BAAALgAECgYJBgAAAA==.',
Ps='Pseudoruski:BAAALgADCgMJAwAAAA==.',
Pu='Purplehaze:BAAALgAECgUJBQAAAA==.',
Pv='Pvlolz:BAABLgAECn8ZAAIYAAkJ3QpDMACAAQAYAAkJ3QpDMACAAQAAAA==.',
Pw='Pwnstarz:BAAALgAECgYJCgAAAA==.',
Py='Pyrada:BAABLgAECn8VAAMCAAkJxRZCCQDVAQACAAgJAhdCCQDVAQASAAgJJBQAPgDMAQAAAA==.',
Qa='Qaharn:BAAALgAECgQJBwAAAA==.',
Qp='Qplus:BAABLgAECn8iAAITAAkJ5AiOWgCQAQATAAkJ5AiOWgCQAQAAAA==.',
Qu='Quackadilly:BAAALgADCgcJDQAAAA==.Quaenie:BAABLgAECn8hAAIYAAkJ7hY/FgAcAgAYAAkJ7hY/FgAcAgAAAA==.Quintin:BAABLgAECn8VAAIiAAgJIw7JCgBrAQAiAAgJIw7JCgBrAQAAAA==.',
Ra='Raged:BAAALgAECgUJCgAAAA==.Ragegauge:BAAALgAECgQJBgAAAA==.Ragetotem:BAABLgAECn8kAAMKAAYJmRwgKADSAQAKAAYJmRwgKADSAQAJAAMJAAU6tQBbAAAAAA==.Ragewarg:BAAALgAFFAIJAgAAAA==.Ragnashock:BAAALgAECgQJBgAAAA==.Ralvarr:BAABLgAECn8aAAIeAAgJIBimGwDbAQAeAAgJIBimGwDbAQAAAA==.Raptorjésus:BAAALgADCgcJCwAAAA==.Rastik:BAAALgADCgIJAgAAAA==.Rathaes:BAAALgADCgMJAwAAAA==.Ravenstryke:BAAALgAECgEJAQAAAA==.Raylea:BAAALgADCgcJBwAAAA==.Rayleigh:BAAALgAECgcJDgABLgAECgUJCwAEAAAAAA==.Razzgix:BAAALgAECgUJBgAAAA==.',
Re='Redchord:BAAALgADCgUJDAAAAA==.Regidør:BAABLgAECn8ZAAMmAAgJ/CBcCADoAgAmAAgJ/CBcCADoAgAFAAYJxx0XYQDBAQAAAA==.Relik:BAABLgAECn8jAAIkAAkJjwwvGgBlAQAkAAkJjwwvGgBlAQAAAA==.Resith:BAAALgAECgYJCAAAAA==.',
Rh='Rhaelia:BAABLgAECn8ZAAIFAAcJFQmovgAHAQAFAAcJFQmovgAHAQAAAA==.Rhaspus:BAAALgADCgQJBAAAAA==.',
Ri='Rilliccine:BAAALgADCgkJCwAAAA==.Rillinetti:BAABLgAECn8mAAIGAAkJQBR0NgD+AQAGAAkJQBR0NgD+AQAAAA==.Rillini:BAAALgADCgcJBwAAAA==.Rilliti:BAABLgAECn8ZAAIJAAYJRA7dZAAoAQAJAAYJRA7dZAAoAQAAAA==.Risky:BAAALgAECgEJAQABLgAECgcJFwAgAMYEAA==.',
Ro='Robïn:BAAALgAECgIJAgABLgAECggJFQAeAAwQAA==.Rondon:BAABLgAECn88AAITAAkJXCYbAQCIAwATAAkJXCYbAQCIAwAAAA==.Rookdh:BAACLgAFFH8OAAMBAAUJvQarFwDeAAABAAQJUQSrFwDeAAASAAUJogbnWwDUAAAuAAQKfykAAxIACQnkFqRbAHEBABIACAk+GKRbAHEBAAEABwkyFucsAGMBAAAA.Rorcia:BAAALgADCgcJFAAAAA==.Rosey:BAABLgAECn8sAAIFAAkJcxX1PQALAgAFAAkJcxX1PQALAgAAAA==.Rotmaxxer:BAAALgAFFAQJBAAAAA==.Roxania:BAAALgADCgYJBgAAAA==.Royale:BAAALgAECgcJBwAAAA==.',
Ru='Rudyeightbal:BAABLgAECn8bAAMGAAgJCQzwmQAJAQAGAAYJhw3wmQAJAQAZAAIJFQNBRQAfAAAAAA==.Ruedons:BAAALgAECgMJAwAAAA==.Rugsalon:BAACLgAFFH8IAAIVAAMJCwmtigDIAAAVAAMJCwmtigDIAAAuAAQKfycAAhUACQn1HPM0AJ8CABUACQn1HPM0AJ8CAAAA.Rustedbarrel:BAACLgAFFH8IAAIaAAMJqwvIPACvAAAaAAMJqwvIPACvAAAuAAQKfxsAAhoACQmnE3YhAPYBABoACQmnE3YhAPYBAAAA.',
Ry='Ryptar:BAAALgADCgkJHAAAAA==.',
['Rè']='Rèaper:BAAALgAECgMJAwAAAA==.',
['Ré']='Réxxar:BAABLgAECn8cAAINAAcJPRTbDQClAQANAAcJPRTbDQClAQAAAA==.',
Sa='Saelyres:BAABLgAECn8hAAMCAAkJyhwYBACGAgACAAkJyhwYBACGAgABAAEJ1wNHegApAAAAAA==.Sagesse:BAAALgADCgYJBgAAAA==.Saikye:BAAALgAECgEJAQAAAA==.Sairu:BAAALgADCgEJAQAAAA==.Saisera:BAABLgAFFH8FAAMcAAIJehf6GwCYAAAPAAIJeheLxgCYAAAcAAIJ1hX6GwCYAAAAAA==.Samistraza:BAAALgADCgEJAQAAAA==.Sammy:BAABLgAECn8jAAIFAAkJvQnyhgBfAQAFAAkJvQnyhgBfAQAAAA==.Santaclaaws:BAACLgAFFH8RAAISAAQJXxvzOgAyAQASAAQJXxvzOgAyAQAuAAQKfzUABBIACQmkIjAUAJ4CABIACQmkIjAUAJ4CAAIAAwldFtgbALgAAAEAAgk1GY5bAHIAAAAA.Santapal:BAACLgAFFH8IAAMmAAQJiRYfIAAXAQAmAAQJiRYfIAAXAQAFAAEJ3gF1xAA2AAAuAAQKfy0ABCYACAkOGvQnAMkBACYABwmhGvQnAMkBAAUAAgl6BRZrAUcAAAMAAglpEmRNADUAAAEuAAUUBAkRABIAXxsA.Santatumblr:BAACLgAFFH8GAAMeAAMJdh1rKwAHAQAeAAMJdh1rKwAHAQAXAAEJLgzMQQA3AAAuAAQKfxoABB4ACAlRG7gVAGcCAB4ACAlRG7gVAGcCABcABAlyEDpvAG4AABoAAQlNA2SoABoAAAEuAAUUBAkRABIAXxsA.Santhin:BAAALgADCgcJCgAAAA==.Saphira:BAAALgAECgQJBAAAAA==.Sareit:BAABLgAECn8cAAMIAAcJHw6dPAAaAQAIAAYJIQydPAAaAQAHAAYJAhITPgAWAQAAAA==.Sassee:BAAALgAECgQJCAAAAA==.Sayvil:BAAALgAECgUJCwABLgAECgkJOAAYAEQgAQ==.',
Sc='Scripture:BAAALgADCgYJBgAAAA==.',
Se='Seawolph:BAABLgAECn85AAIJAAkJBRn1GAB/AgAJAAkJBRn1GAB/AgAAAA==.Selenia:BAAALgAECgMJAwAAAA==.Semmers:BAAALgAECgkJCQAAAA==.Sensational:BAABLgAECn8aAAMeAAcJWhx+EwAvAgAeAAcJWhx+EwAvAgAXAAUJZwiLWQCoAAAAAA==.Sergio:BAAALgAECgcJCgAAAA==.Seyren:BAABLgAFFH8GAAIRAAMJwwiTKgC6AAARAAMJwwiTKgC6AAAAAA==.',
Sh='Shamiska:BAAALgAECgcJEgAAAA==.Shammerdown:BAAALgAECgIJAwAAAA==.Shampooh:BAAALgAECgQJBwABLgAECgcJFwAgAMYEAA==.Shamtastyk:BAAALgAECgQJBAAAAA==.Shaokhan:BAABLgAECn8qAAMJAAkJiSHGBwAwAwAJAAkJiSHGBwAwAwAMAAcJuwqwGgAnAQAAAA==.Sheilla:BAAALgADCgUJBQAAAA==.Shian:BAABLgAECn9CAAINAAkJ+BhFCgA9AgANAAkJ+BhFCgA9AgAAAA==.Shieldee:BAABLgAECn82AAMFAAkJ1RypIwB1AgAFAAkJ1RypIwB1AgAmAAEJTgPHmwAiAAAAAA==.Shiftystax:BAAALgAECgEJAQAAAA==.Shlectrinell:BAABLgAECn9LAAMjAAkJ7A5oGADUAQAjAAkJ7A5oGADUAQAnAAgJBAUICwB+AQAAAA==.Shockeei:BAACLgAFFH8eAAMVAAYJACHlDgCiAQAVAAYJACHlDgCiAQApAAEJ6g9RBwA5AAAuAAQKfykABBUACQkqJRMJADADABUACQkqJRMJADADACkAAwlSGHcJALkAAB8AAQnWIEcSAFYAAAAA.Shocktroop:BAAALgADCgYJCgAAAA==.Shortdon:BAAALgAECgEJAQAAAA==.Shortebread:BAAALgAFFAIJAgAAAA==.Shurp:BAAALgAECgMJAwAAAA==.',
Si='Siakora:BAABLgAECn8VAAIjAAgJXRgLGwAoAgAjAAgJXRgLGwAoAgABLgAFFAcJIQAlAKkaAA==.Sicksty:BAAALgADCgcJBwAAAA==.Sighh:BAAALgAECgYJBwAAAA==.Sighhy:BAAALgAECgYJDwAAAA==.Sijth:BAACLgAFFH8LAAIFAAQJcROpQAAkAQAFAAQJcROpQAAkAQAuAAQKf1YAAgUACQlGIosOAO8CAAUACQlGIosOAO8CAAAA.Silentchaos:BAAALgADCgMJBQAAAA==.Siler:BAAALgADCgYJBgAAAA==.Silverwar:BAABLgAECn80AAIQAAkJjh4kCQDOAgAQAAkJjh4kCQDOAgAAAA==.Simmi:BAECLgAFFH8eAAIgAAcJfhuXCABlAgAgAAcJfhuXCABlAgAuAAQKfykAAiAACQnBJSQGAFMDACAACQnBJSQGAFMDAAAA.Sinnis:BAAALgAECgEJAQAAAA==.Sirlavan:BAAALgAECgYJCwAAAA==.Sixte:BAAALgAECgcJCwAAAA==.Sixtea:BAABLgAECn81AAIKAAkJ9B7ICADOAgAKAAkJ9B7ICADOAgAAAA==.',
Sk='Skarredd:BAAALgADCgkJEQAAAA==.Skellington:BAAALgAECgEJAQAAAA==.Skepti:BAABLgAECn8tAAITAAkJ7Bq7IQBaAgATAAkJ7Bq7IQBaAgAAAA==.Skysong:BAAALgAECgMJAwAAAA==.',
Sl='Slapdemhoes:BAAALgAECgcJAgAAAA==.Slimfoo:BAAALgAECgcJDQAAAA==.Slunkyspit:BAAALgADCgUJCAAAAA==.Slybearclaw:BAAALgADCgUJBQAAAA==.Slyeulogy:BAAALgAECggJEgAAAA==.',
Sm='Smeeta:BAACLgAFFH8IAAIPAAMJ4BmykQDkAAAPAAMJ4BmykQDkAAAuAAQKf2AABA8ACQmHJBoPAPECAA8ACQkxJBoPAPECABwACAldI2MDALECABsABQlQEQ84ALEAAAAA.Smoak:BAAALgADCgUJBQAAAA==.Smolderlight:BAACLgAFFH8MAAImAAQJKRT/IgACAQAmAAQJKRT/IgACAQAuAAQKf0AAAiYACQnWF/gVAFkCACYACQnWF/gVAFkCAAAA.Smoochiebutt:BAAALgAECgUJCQAAAA==.',
So='Solaace:BAAALgAECgEJAQAAAA==.Solo:BAAALgAECgYJCQAAAA==.Soloris:BAAALgADCgcJCAAAAA==.Sonja:BAAALgAECgcJBwAAAA==.Soram:BAAALgAECgYJCgAAAA==.Sosa:BAABLgAFFH8FAAIkAAUJzRlDDwA0AQAkAAUJzRlDDwA0AQAAAA==.Soulstryker:BAAALgAECgEJAQAAAA==.Soùl:BAAALgAECgcJEAAAAA==.',
Sp='Spacepants:BAAALgAECgEJAQAAAA==.Spurgeon:BAAALgAECgEJAQAAAA==.',
St='Staraelle:BAAALgAECgEJAgAAAA==.Stazz:BAAALgAECgYJBgAAAA==.Steelerayne:BAAALgAECggJEQAAAA==.Stormii:BAABLgAECn8jAAMJAAkJKA4yUwBiAQAJAAgJTQwyUwBiAQAKAAMJfhSOYwC2AAAAAA==.Strangelock:BAAALgAECgYJCwABLgAECgkJMgAPALoNAA==.Strangerdk:BAABLgAECn8yAAIPAAkJug1XXQCtAQAPAAkJug1XXQCtAQAAAA==.Streetdog:BAAALgADCgYJBgAAAA==.Stublin:BAAALgADCgEJAQAAAA==.Stuggens:BAAALgADCgkJCQAAAA==.',
Su='Suggondeez:BAAALgAECgYJBwAAAA==.Superfatbaby:BAABLgAECn8dAAIQAAkJKhM/JwC/AQAQAAkJKhM/JwC/AQAAAA==.',
Sw='Swiftstroker:BAAALgAECgEJAQAAAA==.Swikk:BAAALgADCgYJCAAAAA==.Swishersweet:BAABLgAECn8yAAINAAkJFgrmJwATAQANAAkJFgrmJwATAQAAAA==.Swordfish:BAABLgAECn8eAAIiAAgJJyGoAgCLAgAiAAgJJyGoAgCLAgAAAA==.',
Sy='Syannae:BAAALgADCgYJBwAAAA==.Sybelyda:BAAALgADCgYJBgAAAA==.Sybros:BAAALgADCgEJAQAAAA==.Sydonie:BAAALgAECgEJBwAAAA==.Sylus:BAAALgAECgQJBAAAAA==.Symbah:BAAALgADCgYJBgAAAA==.Synvalid:BAABLgAECn8gAAISAAkJ9wfgiAAKAQASAAkJ9wfgiAAKAQAAAA==.Syzrin:BAAALgADCgEJAQABLgAECggJIgAGAHcUAA==.',
Ta='Tabrieus:BAABLgAECn9SAAIVAAkJ5yF5CwAbAwAVAAkJ5yF5CwAbAwAAAA==.Tadokof:BAAALgADCgkJLQAAAA==.Talanth:BAABLgAECn8XAAInAAkJ0AiyCgCGAQAnAAkJ0AiyCgCGAQAAAA==.Talya:BAAALgAECggJCAABLgAECgkJQgANAPgYAA==.Tandisong:BAAALgAECgcJCAAAAA==.Tanknhammerm:BAAALgADCgYJBgAAAA==.Tanknstein:BAAALgADCgYJBgAAAA==.Tanton:BAAALgAECgMJAwAAAA==.Tanzil:BAAALgAECgYJDgAAAA==.Tardigrade:BAAALgAECggJEwAAAA==.Tareyna:BAABLgAECn8hAAIFAAkJeBPfQQD/AQAFAAkJeBPfQQD/AQAAAA==.Tayon:BAABLgAECn8UAAMaAAgJ3gaLQAD2AAAaAAgJ3gaLQAD2AAAeAAEJTgblygAfAAAAAA==.Tayvin:BAAALgAECgUJEAAAAA==.Tazanath:BAAALgADCgEJAgABLgADCgcJFAAEAAAAAA==.',
Te='Tempest:BAAALgAECgUJBQAAAA==.Tengen:BAAALgAECgUJDAAAAA==.Termana:BAACLgAFFH8hAAIkAAYJiyDrAgBxAQAkAAYJiyDrAgBxAQAuAAQKfygAAiQACQmCJLcCABUDACQACQmCJLcCABUDAAAA.',
Th='Thanel:BAAALgADCgQJBAAAAA==.Tharja:BAABLgAECn8bAAIVAAkJXhvvNACfAgAVAAkJXhvvNACfAgAAAA==.Theodyn:BAAALgAECgQJBQAAAA==.Thornp:BAAALgAECgEJAgAAAA==.Thoronk:BAAALgAECgcJBgAAAA==.Thsaric:BAAALgAECgEJAQAAAA==.Thug:BAABLgAECn8WAAMQAAcJ0R/RJQArAgAQAAcJ0R/RJQArAgAkAAIJHxvRNgCRAAAAAA==.Thuggin:BAAALgAECgQJBQAAAA==.',
Ti='Tiferet:BAABLgAECn84AAQYAAkJ+iFdBAA7AwAYAAkJ+iFdBAA7AwAHAAgJQAtgMABaAQAIAAQJzxe5SwDSAAAAAA==.Tigiw:BAAALgAECgMJBAAAAA==.Tinysunshine:BAABLgAECn8VAAIXAAgJMRzjEQAxAgAXAAgJMRzjEQAxAgAAAA==.Tinyt:BAAALgAECgEJAQAAAA==.Tiramisu:BAAALgAECgUJBQAAAA==.Tismtwo:BAAALgAECgEJAQAAAA==.Tismyhammer:BAAALgADCgQJBAAAAA==.',
To='Toasted:BAAALgADCgQJAQAAAA==.Tolenkar:BAABLgAECn8fAAITAAkJdR0tHQByAgATAAkJdR0tHQByAgAAAA==.Tomato:BAACLgAFFH8YAAMZAAYJNxDaBwDxAAAGAAUJwxGLUQAfAQAZAAQJxA3aBwDxAAAuAAQKfyMAAxkACQlpHaYFAHoCABkACAkIHKYFAHoCAAYABQlZFzeaAAkBAAAA.Tomhanks:BAABLgAECn8VAAIFAAkJAhVjOgAXAgAFAAkJAhVjOgAXAgAAAA==.Tormentaa:BAAALgAECgYJBwAAAA==.Torvalar:BAABLgAECn9dAAIFAAkJvRvHHgCMAgAFAAkJvRvHHgCMAgAAAA==.',
Tr='Treemendous:BAAALgADCgYJCQAAAA==.Trolgoskill:BAAALgADCgQJBAAAAA==.Truthslayer:BAABLgAECn8cAAMQAAkJKAnVSAAhAQAQAAkJKAnVSAAhAQARAAEJcgr/QgAzAAAAAA==.Trûth:BAABLgAECn8WAAIHAAgJxBBMIwC9AQAHAAgJxBBMIwC9AQAAAA==.',
Tt='Tteinfante:BAAALgAECggJCAAAAA==.',
Tu='Tugzug:BAAALgAECgEJAgAAAA==.Turdyl:BAABLgAECn8sAAIFAAkJuhE4agCXAQAFAAkJuhE4agCXAQAAAA==.',
Tw='Twindad:BAAALgADCgkJEQAAAA==.Twindadlock:BAAALgAECgYJCgAAAA==.Twowheels:BAAALgAECgQJBQAAAA==.',
Ty='Tyraz:BAAALgAECgcJEwAAAA==.Tystrolf:BAABLgAECn8YAAQlAAcJrg3yRAD0AAAlAAYJ/w7yRAD0AAAWAAUJjAe5NQB/AAANAAIJgAkDbgA2AAAAAA==.',
Tz='Tzar:BAAALgADCgIJAgAAAA==.',
['Tô']='Tôx:BAABLgAECn8XAAMKAAcJWB1YLQCwAQAKAAcJWB1YLQCwAQAJAAIJRhQ00QA1AAAAAA==.',
Ub='Ubrew:BAAALgAECgkJBQAAAA==.',
Ud='Udyrr:BAAALgADCgIJAgAAAA==.',
Ul='Ulfius:BAAALgADCgMJAwAAAA==.Ullume:BAAALgAECgkJDQAAAA==.',
Um='Umbranwings:BAAALgAFFAEJAQAAAA==.',
Un='Unheardjp:BAAALgAECgMJCwAAAA==.Unholy:BAAALgAECgIJBAAAAA==.Unholyarnix:BAAALgAECgQJDQAAAA==.',
Ur='Ursus:BAAALgADCgYJBgAAAA==.Uruloki:BAAALgAECgEJAQAAAA==.',
Va='Vacuum:BAAALgAECgYJEQAAAA==.Vadican:BAAALgADCgQJBAAAAA==.Vaerix:BAABLgAECn8sAAIdAAkJWw/VLACHAQAdAAkJWw/VLACHAQAAAA==.Valdora:BAAALgAECgEJAQAAAA==.Valhals:BAABLgAECn84AAMaAAkJSAuTKgBfAQAaAAkJGQmTKgBfAQAXAAMJUQ4CdgBhAAAAAA==.Valydrin:BAABLgAECn9aAAIYAAkJnx69CQDIAgAYAAkJnx69CQDIAgAAAA==.Vanhelsinky:BAAALgADCgIJAgAAAA==.Vanquished:BAAALgAECgIJBAAAAA==.Varyn:BAAALgADCgIJAgAAAA==.',
Ve='Velandia:BAAALgAECgcJDAAAAA==.Ventis:BAAALgAECgQJBwAAAA==.',
Vi='Vicara:BAAALgADCgYJBgAAAA==.Virgl:BAAALgAECgkJBQAAAA==.',
Vo='Voidifphat:BAAALgAECggJEAAAAA==.Voidtorrent:BAAALgAECgQJCAAAAA==.Voidvanquish:BAAALgAECgYJBwAAAA==.Vorkhan:BAAALgADCgUJCAAAAA==.',
Vu='Vuldrak:BAAALgAECggJEwAAAA==.',
Vy='Vysis:BAACLgAFFH8TAAQIAAQJqAniKwDqAAAIAAQJ8QfiKwDqAAAHAAMJeQkbJwC8AAAYAAIJ1AwHDgCOAAAuAAQKf1gABAcACQkbH78IAMICAAcACQkbH78IAMICAAgACQmUFbcRAFYCABgACQlPG4cSAEwCAAAA.',
['Vä']='Vännic:BAAALgADCgEJAwAAAA==.Vännìc:BAAALgADCgEJAQAAAA==.',
['Ví']='Ví:BAABLgAECn8fAAIXAAkJsQq1LABXAQAXAAkJsQq1LABXAQAAAA==.',
Wh='Whatfoxsay:BAAALgADCgEJAQAAAA==.Whats:BAAALgADCgcJBwABLgAECgcJFQAXABQSAA==.When:BAAALgADCgQJBAAAAA==.Whicker:BAAALgAECgUJBgAAAA==.Whipsnchains:BAAALgAECgUJBgAAAA==.Whipsntricks:BAAALgAECgQJBgAAAA==.',
Wi='Wickèr:BAACLgAFFH8KAAIaAAMJpA9bNwDEAAAaAAMJpA9bNwDEAAAuAAQKfzgAAxoACQkHHh4JAJ4CABoACQkHHh4JAJ4CABcAAQnIF8iKAEQAAAAA.Wieldblade:BAABLgAECn8/AAMFAAkJ/x9IEADiAgAFAAkJ/x9IEADiAgADAAgJiBaDDwDHAQAAAA==.Wigdrag:BAAALgAECgEJAQAAAA==.Wilsondk:BAAALgAECgEJAwAAAA==.Winslett:BAAALgADCgQJBAAAAA==.',
Wo='Woggo:BAAALgAECgEJAQAAAA==.Wolfemoon:BAABLgAECn8UAAITAAgJwwrsdwBLAQATAAgJwwrsdwBLAQAAAA==.Worganlefey:BAAALgAECgMJBwABLgAECgkJWgAGAIcaAA==.',
Wr='Wrexd:BAABLgAECn8qAAIGAAgJChvHQwDPAQAGAAgJChvHQwDPAQAAAA==.',
Wu='Wunderbar:BAABLgAECn9CAAMKAAkJOyKXBAAVAwAKAAkJOyKXBAAVAwAJAAkJ5xhPGQB8AgAAAA==.',
Wy='Wyldfire:BAACLgAFFH8ZAAQlAAYJwxnwGwA0AQAlAAUJlhjwGwA0AQAgAAEJ/AZcaABGAAANAAEJHgoQQAApAAAuAAQKfy8AAyUACQleI/kLANgCACUACQleI/kLANgCACAAAwksEo2eAI4AAAAA.Wyndclaw:BAABLgAECn8WAAIeAAYJcBYhOACKAQAeAAYJcBYhOACKAQAAAA==.',
Xa='Xanith:BAABLgAECn8tAAIQAAgJehiyIADpAQAQAAgJehiyIADpAQAAAA==.',
Xe='Xebubble:BAAALgADCgEJAQABLgAECgEJAQAEAAAAAA==.Xemonk:BAAALgAECgEJAQAAAA==.',
Xi='Xia:BAAALgADCgYJBgAAAA==.',
Xr='Xroi:BAAALgAECgIJAgAAAA==.',
Ya='Yaganor:BAAALgADCgUJBgAAAA==.',
Ye='Yeto:BAAALgADCgYJBwAAAA==.',
Yi='Yia:BAAALgAECgUJCQABLgAECgUJEgAEAAAAAA==.Yilnara:BAABLgAECn8bAAISAAkJDgeJfAAjAQASAAkJDgeJfAAjAQAAAA==.',
Yo='Yondo:BAAALgAECgMJAwAAAA==.',
Ys='Ysa:BAABLgAECn8eAAMXAAcJuCShEAB3AgAXAAcJuCShEAB3AgAeAAEJlA2UbAApAAAAAA==.',
Za='Zajindor:BAAALgADCgEJAQAAAA==.Zarathul:BAAALgADCgIJAgAAAA==.',
Ze='Zekkun:BAAALgAECgEJAQAAAA==.',
Zh='Zheria:BAAALgAECgQJBAAAAA==.',
Zi='Zirael:BAAALgADCgYJCgAAAA==.',
Zo='Zod:BAAALgAECgkJCQAAAA==.Zoganian:BAEALgAECgUJEgABLgAECgkJJwAYAAUhAA==.Zogula:BAEBLgAECn8nAAQYAAkJBSGrCwCqAgAYAAkJ0iCrCwCqAgAHAAQJXxbJQAAKAQAIAAEJaiOjZQBgAAAAAA==.',
Zu='Zu:BAAALgAECgcJEAAAAA==.',
Zy='Zynara:BAAALgAECgYJCAAAAA==.',
['År']='Årtemis:BAABLgAECn8xAAIoAAgJwB2bDQBOAgAoAAgJwB2bDQBOAgAAAA==.',
['Æb']='Æbony:BAAALgADCgMJAwAAAA==.',
['Ïr']='Ïrini:BAAALgAECgIJAwABLgAECggJFQAeAAwQAA==.',
['Ða']='Ðante:BAAALgAECgEJAQAAAA==.',
['Ðe']='Ðelusion:BAAALgAECgMJCAAAAA==.',
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
