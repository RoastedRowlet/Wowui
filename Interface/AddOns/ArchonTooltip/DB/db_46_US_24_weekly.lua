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

local lookup = {'DemonHunter-Havoc','DemonHunter-Vengeance','Paladin-Protection','Unknown-Unknown','Paladin-Retribution','Warlock-Demonology','Priest-Shadow','Priest-Discipline','Shaman-Restoration','Shaman-Elemental','Evoker-Preservation','Shaman-Enhancement','Druid-Guardian','Rogue-Outlaw','DeathKnight-Unholy','Warrior-Fury','Warrior-Arms','DemonHunter-Devourer','Hunter-Marksmanship','Hunter-BeastMastery','Mage-Frost','Druid-Feral','Monk-Windwalker','Priest-Holy','Warlock-Destruction','Monk-Brewmaster','DeathKnight-Blood','DeathKnight-Frost','Evoker-Augmentation','Monk-Mistweaver','Mage-Arcane','Druid-Restoration','Warlock-Affliction','Evoker-Devastation','Warrior-Protection','Druid-Balance','Paladin-Holy','Rogue-Assassination','Hunter-Survival','Rogue-Subtlety','Mage-Fire',}
local provider = {region='US',realm='AzjolNerub',name='US',type='weekly',zone=46,date='2026-05-30',data={Ad='Adapt:BAAALgAECgMJCQAAAA==.Addy:BAABLgAECn8xAAMBAAkJCB44BgC6AgABAAkJCB44BgC6AgACAAEJQggIMwAkAAAAAA==.',
Ae='Aeonis:BAAALgAECgMJCQAAAA==.Aestian:BAABLgAECn8wAAIDAAgJLBtTDgDEAQADAAgJLBtTDgDEAQAAAA==.',
Ag='Agamesh:BAAALgADCgUJCQAAAA==.',
Ah='Ahoma:BAAALgADCgkJBgAAAA==.',
Ai='Ailysely:BAAALgADCgUJBQABLgAECgMJCQAEAAAAAA==.Airees:BAABLgAECn8iAAIFAAcJOx7oQQAfAgAFAAcJOx7oQQAfAgAAAA==.Aispere:BAAALgAECgQJBQAAAA==.',
Al='Alastria:BAAALgADCgcJBwAAAA==.Alektra:BAAALgADCgUJBwAAAA==.Alerzhulan:BAABLgAECn8bAAIGAAkJMgvmUACdAQAGAAkJMgvmUACdAQAAAA==.Allanquatre:BAAALgAECgUJBQAAAA==.Alledria:BAABLgAECn8aAAIFAAgJmhLtagB/AQAFAAgJmhLtagB/AQAAAA==.Allenaena:BAAALgAECgMJBgAAAA==.Alorely:BAABLgAECn8gAAMHAAkJ/gwwKwBaAQAHAAgJ0A0wKwBaAQAIAAcJoxOUKwBVAQAAAA==.Altonas:BAAALgAECgMJAwAAAA==.',
Am='Amanara:BAAALgAECgcJDQAAAA==.Amillah:BAAALgAECgQJBgAAAA==.Amooka:BAAALgAECgEJAQAAAA==.',
An='Anciientpaw:BAABLgAECn8iAAMJAAkJGyBlHQAvAgAJAAkJGyBlHQAvAgAKAAUJbBUzRgAwAQAAAA==.Andramalyus:BAABLgAECn8pAAIGAAgJ3AzbYwBsAQAGAAgJ3AzbYwBsAQAAAA==.Andrasomnium:BAAALgAECgIJAgAAAA==.Angbar:BAABLgAECn8vAAILAAkJWRZ4CABXAgALAAkJWRZ4CABXAgAAAA==.Anguirus:BAABLgAECn8qAAMKAAkJAAVeUwDPAAAKAAkJAAVeUwDPAAAMAAQJ4AB7NwAuAAAAAA==.Animà:BAAALgAECgYJDwAAAA==.Ankhnstein:BAAALgAECgQJBAAAAA==.Antiheroo:BAAALgAECgUJBwAAAA==.Antoine:BAAALgAECgIJAgAAAA==.',
Ap='Apolloni:BAAALgAECgIJAgABLgAECgkJKgANAJYJAA==.Appynoxusrog:BAABLgAECn8cAAIOAAYJuhguBQCcAQAOAAYJuhguBQCcAQAAAA==.',
Aq='Aqulenas:BAABLgAFFH8FAAIPAAMJsROygADfAAAPAAMJsROygADfAAAAAA==.',
Ar='Arakhan:BAAALgAFFAEJAQAAAA==.Arasaka:BAAALgAECgQJCAAAAA==.Arcadian:BAABLgAECn8xAAMQAAkJHB1PDgB5AgAQAAkJHB1PDgB5AgARAAEJzAfURAAvAAAAAA==.Arcadiann:BAAALgAECgUJEQAAAA==.Arcadin:BAAALgAECgEJAgAAAA==.Arcoyflecha:BAAALgAECgYJCQAAAA==.Arextheelder:BAAALgAECgcJDgAAAA==.Aridas:BAABLgAECn8dAAMSAAgJJBhuMwAsAgASAAgJJBhuMwAsAgABAAIJRQsGYABiAAABLgAECgkJKAARAAcaAA==.Arikdeath:BAABLgAECn8iAAMTAAkJbAwREwAVAQATAAcJTgwREwAVAQAUAAMJqAsZugCtAAAAAA==.Armorscales:BAACLgAFFH8SAAIGAAUJuBgsPwA1AQAGAAUJuBgsPwA1AQAuAAQKfy0AAgYACQm/IVgQAPcCAAYACQm/IVgQAPcCAAAA.Arniix:BAAALgAECgEJAQABLgAECgQJDQAEAAAAAA==.Arnixskitty:BAAALgAECgEJAQABLgAECgQJDQAEAAAAAA==.Arntraz:BAAALgADCgkJOgAAAA==.Arçadia:BAAALgAECgMJAwAAAA==.',
As='Ashegen:BAAALgAECgQJBAAAAA==.Ashnikko:BAAALgAECgEJAQAAAA==.Ashtori:BAAALgADCgEJAgAAAA==.Asis:BAAALgAECgEJAQAAAA==.Astrine:BAACLgAFFH8SAAIVAAUJmBlMTgA0AQAVAAUJmBlMTgA0AQAuAAQKfysAAhUACQlJIAYiAOsCABUACQlJIAYiAOsCAAAA.',
Au='Auberon:BAABLgAECn8oAAIWAAkJ/xl6BgCSAgAWAAkJ/xl6BgCSAgAAAA==.Aufta:BAABLgAECn8rAAIXAAkJHgaeMwAfAQAXAAkJHgaeMwAfAQAAAA==.',
Az='Azdh:BAAALgAECgQJBgAAAA==.Azi:BAACLgAFFH8bAAITAAcJix69BQDqAQATAAcJix69BQDqAQAuAAQKfykAAhMACQkGIBUDAJYCABMACQkGIBUDAJYCAAAA.Azshanorel:BAAALgADCgcJBwAAAA==.Azunea:BAAALgAECgIJBwAAAA==.Azurite:BAAALgAECgMJAwAAAA==.',
Ba='Backpedal:BAAALgAECgcJEAAAAA==.Badankhadonk:BAACLgAFFH8SAAIJAAQJuCPaFgCAAQAJAAQJuCPaFgCAAQAuAAQKfy0AAgkACQl7JVICAF8DAAkACQl7JVICAF8DAAAA.Balen:BAABLgAECn8sAAIDAAkJohQuDADpAQADAAkJohQuDADpAQAAAA==.Bandrösh:BAAALgADCgMJAwAAAA==.Barradune:BAAALgADCgYJDAAAAA==.Baubles:BAAALgAECgMJAgAAAA==.',
Be='Belholy:BAABLgAECn8rAAIYAAgJzyGCBwDjAgAYAAgJzyGCBwDjAgAAAA==.Beliice:BAAALgADCgkJIAABLgAECggJKwAYAM8hAA==.Bellanei:BAAALgAECgEJBAAAAA==.Ben:BAAALgAECgEJAQAAAA==.Benafflockk:BAAALgADCggJCAAAAA==.Benefitdruid:BAAALgAECgEJAQAAAA==.Benilok:BAACLgAFFH8PAAMGAAQJXh8qNABQAQAGAAQJXh8qNABQAQAZAAEJ6hDPIABKAAAuAAQKfysAAgYACQkcJSEMABkDAAYACQkcJSEMABkDAAAA.Bethgibbons:BAAALgADCgkJLwAAAA==.',
Bi='Bibimbap:BAAALgAECgEJAQAAAA==.Bigsuccubus:BAABLgAECn8aAAIZAAkJxxPzBQDtAQAZAAkJxxPzBQDtAQAAAA==.Biohazard:BAAALgADCgUJBQAAAA==.Bizël:BAAALgAECgYJDQAAAA==.',
Bl='Blackblood:BAABLgAECn8mAAIBAAkJLRVAEQD3AQABAAkJLRVAEQD3AQAAAA==.Blackclouds:BAAALgADCgkJCQAAAA==.Blackspiral:BAAALgADCgEJAQAAAA==.Bladestriker:BAAALgAECgUJBwAAAA==.Blindside:BAAALgAECgMJBgAAAA==.Bloodache:BAABLgAECn8VAAISAAcJKSFgKQBcAgASAAcJKSFgKQBcAgAAAA==.Bloodkissed:BAAALgADCgUJBgABLgAECgkJOAAYAEQgAA==.Bluebuberry:BAAALgAECgQJBgAAAA==.Bluesaphire:BAAALgAECgIJAgABLgAECggJFQAJAP8ZAA==.Blux:BAAALgAECgQJCAAAAA==.',
Bo='Boil:BAABLgAECn8kAAIOAAgJbgfBDQAZAQAOAAgJbgfBDQAZAQAAAA==.Bonemarrow:BAAALgAECgQJEwAAAA==.Bournx:BAAALgAECgIJAgAAAA==.Boysenbar:BAAALgADCgYJCAAAAA==.',
Br='Bradrenna:BAACLgAFFH8GAAMBAAMJAwdGGAChAAABAAMJyANGGAChAAACAAEJjQ1+DwAwAAAuAAQKf04ABAIACQkZGvgEAEgCAAIACQkZGvgEAEgCAAEAAglaD+BMAF0AABIAAQmlAcf0ABsAAAAA.Braké:BAABLgAECn8eAAIDAAkJaB1oBACiAgADAAkJaB1oBACiAgAAAA==.Brandrale:BAAALgAECgEJAQAAAA==.Breakthrough:BAABLgAECn8bAAIJAAYJpSJlHABPAgAJAAYJpSJlHABPAgAAAA==.Brenzull:BAAALgADCgYJCwAAAA==.Brewskies:BAABLgAECn8nAAIaAAcJDyUeCwBxAgAaAAcJDyUeCwBxAgABLgAECgkJIwAbAMAhAA==.Brewsli:BAAALgADCgIJAgABLgAECggJHAAcAJALAA==.Brightstar:BAAALgAECgcJEwAAAA==.Brokenaltar:BAABLgAECn8VAAMBAAYJNRheOQAdAQASAAYJgRFacwBLAQABAAUJCRpeOQAdAQAAAA==.Brownington:BAACLgAFFH8FAAMWAAMJJRKzDwCPAAAWAAIJFA2zDwCPAAANAAEJSBzQJwBQAAAuAAQKfxkAAw0ABwlWJI8HAF8CAA0ABwlWJI8HAF8CABYAAQmjCodFADEAAAAA.Bruhilda:BAABLgAECn8dAAIVAAkJ7hLdQwD5AQAVAAkJ7hLdQwD5AQAAAA==.Brymstone:BAAALgAECgQJBwAAAA==.Brynthebuff:BAAALgAECgEJAQAAAA==.Brìonik:BAACLgAFFH8dAAMGAAcJ5h3AGgCrAQAGAAYJABvAGgCrAQAZAAQJTx+uBQAiAQAuAAQKfyoAAxkACQkPJLUEABUCABkABgkoJbUEABUCAAYABQkeI2trAFoBAAAA.',
Bu='Bufferfish:BAABLgAECn80AAIdAAkJUQxqKgB6AQAdAAkJUQxqKgB6AQAAAA==.',
Ca='Calinnea:BAAALgAECgcJEwABLgAECggJCwAEAAAAAA==.Cantheartitz:BAABLgAECn8VAAIVAAUJPxmBnQCbAQAVAAUJPxmBnQCbAQAAAA==.Catastrophe:BAABLgAECn8kAAIXAAgJASJBCACuAgAXAAgJASJBCACuAgAAAA==.',
Ce='Celira:BAAALgADCgMJAwAAAA==.Celthol:BAABLgAECn8ZAAISAAYJJBMVbAAxAQASAAYJJBMVbAAxAQAAAA==.',
Ch='Chelraani:BAABLgAECn8yAAIFAAkJeyGvCwD0AgAFAAkJeyGvCwD0AgAAAA==.Chiichard:BAAALgADCgYJCgAAAA==.Chipnuts:BAABLgAECn8bAAIXAAkJ8CTAAgBtAwAXAAkJ8CTAAgBtAwAAAA==.Chonchoo:BAAALgADCgEJAQAAAA==.Chosethebear:BAAALgADCgkJEAAAAA==.Chunkamonk:BAAALgADCgUJBQAAAA==.',
Ci='Cigar:BAAALgAECgQJBgABLgAFFAYJEQAPALIXAA==.Cinderat:BAAALgADCgEJAQAAAA==.',
Cl='Clarabellax:BAAALgAECgQJBQAAAA==.Clarkkentt:BAAALgADCgcJDQAAAA==.Claymore:BAACLgAFFH8RAAIQAAYJBBZXCQCaAQAQAAYJBBZXCQCaAQAuAAQKfxUAAhAACAkMGcscAGcCABAACAkMGcscAGcCAAAA.Clazzicola:BAACLgAFFH8PAAMeAAUJPxJ7GwBBAQAeAAUJPxJ7GwBBAQAXAAMJJgvADQCWAAAuAAQKfx8ABBcACQmbFmIeAOUBABcABwlYHGIeAOUBAB4ACAniEYomAH4BABoAAQlhA8uVAB8AAAAA.Cloudbeast:BAAALgAECgMJBAABLgAECgQJDQAEAAAAAA==.Clue:BAAALgADCgYJBgAAAA==.',
Co='Cocito:BAAALgAECgEJAwAAAA==.Commândment:BAAALgAECgYJCgAAAA==.Conjredcukee:BAABLgAECn8WAAIVAAcJ7AOD3AC+AAAVAAcJ7AOD3AC+AAAAAA==.Coo:BAAALgAECgQJBAABLgAECgUJBwAEAAAAAA==.Coogsayer:BAABLgAECn8UAAIHAAcJyh2aEQBxAgAHAAcJyh2aEQBxAgAAAA==.Couch:BAAALgAECgUJBQAAAA==.',
Cp='Cptncrush:BAABLgAECn8fAAMJAAgJBBohJAAcAgAJAAgJBBohJAAcAgAKAAMJoBcgYACoAAAAAA==.',
Cr='Croquetica:BAAALgADCgMJBAAAAA==.Crossed:BAAALgADCgcJCwAAAA==.Crowshadow:BAABLgAECn8UAAIGAAUJAh/hYgBuAQAGAAUJAh/hYgBuAQAAAA==.',
Cy='Cylina:BAAALgADCgcJCAAAAA==.Cyliya:BAAALgADCgIJAgAAAA==.Cylore:BAAALgADCgcJBgAAAA==.Cypherrellik:BAAALgAECgMJAwABLgAECgkJHAABAIUQAA==.Cyther:BAACLgAFFH8hAAIQAAcJjSAfAgA0AgAQAAcJjSAfAgA0AgAuAAQKfykAAhAACQmXIqwHAC4DABAACQmXIqwHAC4DAAAA.',
['Cÿ']='Cÿthera:BAABLgAECn8bAAISAAkJ4BzDHAClAgASAAkJ4BzDHAClAgAAAA==.',
Da='Dakk:BAABLgAECn9KAAIPAAkJOiMTCAAkAwAPAAkJOiMTCAAkAwAAAA==.Daraghor:BAABLgAECn8bAAINAAkJoCIMAgAbAwANAAkJoCIMAgAbAwAAAA==.Darkdottie:BAAALgAECgQJBAAAAA==.Darkenstormy:BAAALgAECgcJDgAAAA==.Darlyndra:BAAALgADCgUJBQAAAA==.Darsae:BAAALgAECgQJDAAAAA==.Darthiono:BAAALgAECgEJAQAAAA==.Darthmaull:BAAALgADCgEJAQAAAA==.',
De='Deadlight:BAABLgAECn8wAAMPAAkJ+BF7SgDQAQAPAAkJZBF7SgDQAQAcAAEJYBKpLgA5AAAAAA==.Deathkillhun:BAAALgAECgQJBwAAAA==.Deathpooch:BAAALgAECggJCgAAAA==.Deathshooter:BAAALgAECgcJAQAAAA==.Deavant:BAAALgADCgMJAwAAAA==.Deermon:BAAALgAECgYJCwAAAA==.Deet:BAAALgAECgUJBQAAAA==.Deforest:BAAALgADCgcJFgAAAA==.Deity:BAABLgAECn8tAAIQAAcJTiPnEgBIAgAQAAcJTiPnEgBIAgAAAA==.Demogon:BAAALgAECgQJBwAAAA==.Demondeano:BAABLgAECn8bAAISAAkJAROLQwClAQASAAkJAROLQwClAQAAAA==.Demonllxll:BAAALgAECgYJCwAAAA==.Demonlxl:BAABLgAECn8cAAIKAAgJ/xXlHQDZAQAKAAgJ/xXlHQDZAQAAAA==.Demonthorx:BAAALgADCgYJBgAAAA==.Demonx:BAABLgAECn8zAAIPAAkJ+x1cFgCuAgAPAAkJ+x1cFgCuAgAAAA==.Desolation:BAABLgAECn9JAAIfAAkJ1iUZAABzAwAfAAkJ1iUZAABzAwAAAA==.Despia:BAABLgAECn8tAAIYAAkJeSP6AQCEAwAYAAkJeSP6AQCEAwAAAA==.Devastacia:BAAALgADCgUJBQAAAA==.Deviarc:BAAALgAECgQJBAAAAA==.',
Dh='Dharkon:BAAALgAECgIJBAAAAA==.',
Di='Dicot:BAABLgAECn8sAAIgAAkJRxMIJAAYAgAgAAkJRxMIJAAYAgAAAA==.',
Dj='Djpallyd:BAAALgAECgkJEAAAAA==.',
Do='Doinks:BAAALgAECgIJAgAAAA==.Domilthri:BAACLgAFFH8FAAIGAAEJnAGXuwA1AAAGAAEJnAGXuwA1AAAuAAQKf0AAAwYACAlCEGtXAIsBAAYACAlCEGtXAIsBACEABgnyBUMQACoBAAAA.Donut:BAAALgADCgIJAgABLgAECgcJHQAiAGEhAA==.Dotdaddy:BAAALgAECgQJBwABLgAECggJCwAEAAAAAA==.Doughy:BAAALgAECgYJBgAAAA==.',
Dr='Dracoly:BAAALgAECggJEgAAAA==.Draconu:BAACLgAFFH8gAAIdAAUJ7R9+FQB7AQAdAAUJ7R9+FQB7AQAuAAQKfyIAAx0ACQk4HycLAI0CAB0ACQk4HycLAI0CAAsAAQmaAX1OACIAAAAA.Draenyth:BAABLgAECn8VAAISAAcJvQ7JZwA8AQASAAcJvQ7JZwA8AQAAAA==.Dragoncurry:BAABLgAECn8WAAILAAYJIgb0JACvAAALAAYJIgb0JACvAAAAAA==.Dragonmite:BAAALgAECgEJAQAAAA==.Drakka:BAAALgADCgkJDgABLgAECgcJEAAEAAAAAA==.Draktyr:BAACLgAFFH8GAAIQAAMJtRZeFgCyAAAQAAMJtRZeFgCyAAAuAAQKfyQAAhAACQn2HncJABYDABAACQn2HncJABYDAAAA.Draxoths:BAAALgAECgMJBQABLgAFFAMJBwAgADkZAA==.Dropeadita:BAAALgAECgQJBAAAAA==.Droptop:BAAALgADCgcJCAAAAA==.',
Du='Dumbsht:BAABLgAECn8ZAAMTAAgJ6xbDMQCpAQATAAcJ6xXDMQCpAQAUAAYJVhHjXQBOAQAAAA==.',
Dy='Dyvyne:BAAALgAECgMJAwAAAA==.',
Ea='Easystreet:BAAALgAECgIJAwAAAA==.',
Ef='Effluv:BAAALgADCgcJDgAAAA==.',
El='Elandir:BAAALgADCgQJAQAAAA==.Elanora:BAAALgAECgYJCQAAAA==.Elbrookel:BAAALgAECgIJAgAAAA==.Eleshnorn:BAAALgAFFAEJAwAAAA==.Eliza:BAAALgADCgkJCQAAAA==.Ellismom:BAABLgAECn9BAAIPAAkJ+SHVCgAHAwAPAAkJ+SHVCgAHAwAAAA==.Elvea:BAABLgAECn8kAAMdAAgJjRqlFwABAgAdAAgJjRqlFwABAgAiAAEJ9QoWQgArAAAAAA==.',
Em='Emeralddemon:BAAALgAECgMJBgAAAA==.Emeraldshade:BAAALgADCgcJDwABLgAECgMJBgAEAAAAAA==.Emeråld:BAAALgAECgUJBgAAAA==.',
En='Enamorada:BAAALgAECgIJAgABLgAECggJFQAJAP8ZAA==.',
Er='Ereithelda:BAACLgAFFH8dAAIeAAcJ4BL4DQDbAQAeAAcJ4BL4DQDbAQAuAAQKfyYAAh4ACAm2IhcHAOkCAB4ACAm2IhcHAOkCAAAA.Ericka:BAAALgADCgYJDQAAAA==.Erreya:BAAALgADCgEJAQAAAA==.',
Es='Esma:BAAALgADCgkJCQAAAA==.',
Ev='Evox:BAAALgAECggJEgAAAA==.',
Ey='Eyris:BAAALgADCgMJAwAAAA==.Eyrndor:BAAALgADCgIJAwAAAA==.',
Fa='Faacee:BAAALgAECgIJAgAAAA==.Falgar:BAAALgADCgYJBgAAAA==.Fann:BAABLgAECn8gAAIgAAkJgAShZAD1AAAgAAkJgAShZAD1AAAAAA==.Fauna:BAAALgAECgYJBgAAAA==.Fawn:BAAALgAECgIJBAAAAA==.Faytl:BAAALgAECgMJAwAAAA==.',
Fe='Felbubu:BAABLgAECn8jAAQCAAkJlyIeBACAAgACAAkJLCIeBACAAgABAAYJOyAmIgCrAQASAAMJNRyhlwDTAAAAAA==.Femboy:BAAALgAECgUJDgAAAA==.Fewz:BAACLgAFFH8LAAIVAAQJ3BgfZQD+AAAVAAQJ3BgfZQD+AAAuAAQKfyQAAhUACQnjIZQYALACABUACQnjIZQYALACAAAA.',
Fi='Fireybuns:BAAALgAECgEJAwAAAA==.',
Fl='Flakiron:BAACLgAFFH8XAAIjAAUJ2RYxEQAHAQAjAAUJ2RYxEQAHAQAuAAQKfy0AAiMACQkjHJkLAFQCACMACQkjHJkLAFQCAAAA.Flakov:BAAALgAECgIJAgABLgAFFAUJFwAjANkWAA==.Flaktop:BAAALgAECgUJCAABLgAFFAUJFwAjANkWAA==.Fler:BAAALgAECgQJCAAAAA==.',
Fo='Forbacon:BAABLgAECn8cAAMcAAgJkAvYFQD8AAAcAAgJJgvYFQD8AAAPAAYJgQluvwDnAAAAAA==.Force:BAABLgAECn8iAAQcAAkJygpNDwBNAQAcAAgJnwtNDwBNAQAPAAUJEAQb+ACXAAAbAAEJ+wTtWwAdAAAAAA==.Fornost:BAAALgADCgkJDgAAAA==.Fourdragon:BAAALgADCgQJBAABLgAECggJFwAKACQXAA==.Fouris:BAABLgAECn8XAAIKAAgJJBe7JQCiAQAKAAgJJBe7JQCiAQAAAA==.',
Fr='Fremosth:BAAALgADCgMJAwAAAA==.Fretman:BAAALgADCgcJCQAAAA==.Fridgie:BAACLgAFFH8YAAIUAAUJZhkzBABdAQAUAAUJZhkzBABdAQAuAAQKfyMAAhQACQm6Im0PAMACABQACQm6Im0PAMACAAAA.Froline:BAAALgAECgMJAwAAAA==.Frostreaper:BAAALgAECgIJAgAAAA==.Frozenflyer:BAAALgAECgUJEAAAAA==.Frozenturtle:BAABLgAECn8fAAIbAAgJ4xwaDQAeAgAbAAgJ4xwaDQAeAgAAAA==.',
Ft='Ftwiamtank:BAAALgAECgYJEgAAAA==.',
Fu='Fuoco:BAAALgAECgkJCgAAAA==.',
Ga='Gabriél:BAAALgAECgYJCQAAAA==.Garcutt:BAACLgAFFH8eAAIVAAcJDRZmGADxAQAVAAcJDRZmGADxAQAuAAQKfysAAhUACQm0HZ8mAGoCABUACQm0HZ8mAGoCAAAA.Gardon:BAAALgAECgUJCQAAAA==.Gaurdinn:BAABLgAECn8uAAQdAAgJMBM3LABvAQAdAAgJrhI3LABvAQAiAAYJfxAzDwAHAQALAAIJagJQNgA3AAABLgAECgkJEwAEAAAAAA==.',
Ge='Gebuss:BAAALgADCgQJBAAAAA==.Generickmonk:BAACLgAFFH8XAAIXAAUJox20CgBZAQAXAAUJox20CgBZAQAuAAQKfy8AAhcACQnyIpYEAPwCABcACQnyIpYEAPwCAAAA.Gensis:BAAALgADCgYJBgAAAA==.Geomatic:BAAALgAECgEJAQAAAA==.Gethsemåne:BAAALgADCgMJBQAAAA==.',
Gi='Giovannucci:BAAALgAECgEJAgAAAA==.Gitan:BAAALgADCgQJBQAAAA==.',
Gl='Gladstone:BAAALgAECgYJDQAAAA==.',
Go='Gomlvirgin:BAAALgADCgYJBgABLgAECggJIgAGAHcUAA==.',
Gr='Gracehimeûwû:BAABLgAFFH8FAAIaAAIJahHKQQB/AAAaAAIJahHKQQB/AAAAAA==.Grampsie:BAAALgAECgUJBwAAAA==.Grayeyes:BAAALgAECgMJAwAAAA==.Greenngoblin:BAAALgAECgEJAgAAAA==.Grimmlie:BAAALgADCgUJBQAAAA==.Grinzler:BAAALgADCgIJAgAAAA==.Grumpybear:BAAALgADCggJDwAAAA==.Grumpykat:BAAALgAECggJEgAAAA==.Grumpypros:BAAALgADCgUJBQAAAA==.',
Gt='Gtatedk:BAAALgAFFAEJAQAAAA==.',
Gu='Guino:BAAALgAECgUJCAAAAA==.Guinodruid:BAAALgADCgcJDgAAAA==.',
Gw='Gwenelly:BAAALgAECgEJAQAAAA==.',
Ha='Hamncheeks:BAAALgAECgEJAQAAAA==.Haptism:BAAALgADCgcJBwAAAA==.Hardeesdelux:BAAALgAECgQJBAABLgAECgQJDQAEAAAAAA==.Hardnarples:BAAALgADCgEJAQAAAA==.Hayzerade:BAAALgAECgYJCAAAAA==.Hazis:BAABLgAECn8rAAIbAAkJEyEbCACkAgAbAAkJEyEbCACkAgAAAA==.',
Hi='Hippiecritz:BAAALgADCgYJBwAAAA==.Hitokiri:BAAALgADCgMJAwAAAA==.',
Ho='Holy:BAACLgAFFH8WAAIDAAUJTQnLCQDBAAADAAUJTQnLCQDBAAAuAAQKfywAAgMACQmkFvMQALcBAAMACQmkFvMQALcBAAAA.Holydad:BAACLgAFFH8FAAIDAAQJzA8eCwCrAAADAAQJzA8eCwCrAAAuAAQKfywAAgMACAkHIOMIACsCAAMACAkHIOMIACsCAAAA.Holydust:BAAALgAECgcJEQAAAA==.Holyhoette:BAAALgADCgQJBAAAAA==.Holymoki:BAAALgADCgYJCgAAAA==.Holymoliie:BAAALgADCgEJAQAAAA==.Holyroundie:BAABLgAECn9PAAIYAAkJqBO0FQAPAgAYAAkJqBO0FQAPAgAAAA==.Holyshock:BAACLgAFFH8hAAIFAAcJRxvaCQDvAQAFAAcJRxvaCQDvAQAuAAQKfykAAgUACQlkJWQGACsDAAUACQlkJWQGACsDAAAA.Holystax:BAAALgAECgEJAwAAAA==.Honeybutter:BAACLgAFFH8WAAMRAAYJkyNyAwATAgARAAYJkyNyAwATAgAQAAEJCAkTIgBRAAAuAAQKfzsAAxEACQkzJqsAAHEDABEACQkzJqsAAHEDABAABwmLHtAjADgCAAAA.Hordebreaker:BAAALgAECgYJEQAAAA==.Hotflash:BAAALgAECgEJAQAAAA==.',
Hu='Huukend:BAABLgAECn9CAAIUAAkJDCOPBwAPAwAUAAkJDCOPBwAPAwAAAA==.',
Ib='Iblindbenice:BAAALgAECgYJBgAAAA==.',
Ic='Icebabyman:BAABLgAECn8fAAIVAAgJER7kOACSAgAVAAgJER7kOACSAgAAAA==.Icedmoki:BAAALgADCgQJBAAAAA==.',
Im='Imnotspeed:BAAALgAECgcJBwAAAA==.',
In='Inanitas:BAAALgADCgcJBwAAAA==.Ineffectual:BAABLgAECn8fAAIJAAgJvBMeMgC9AQAJAAgJvBMeMgC9AQAAAA==.',
Ir='Irukox:BAAALgAECgYJDQAAAA==.',
It='Itty:BAAALgADCgcJBwAAAA==.',
Ja='Jadaveon:BAAALgAECgQJBAAAAA==.Jagger:BAAALgADCgcJCQAAAA==.Jalene:BAAALgAECgYJDwAAAA==.Janewayy:BAABLgAECn8yAAISAAkJGA2DWgBgAQASAAkJGA2DWgBgAQAAAA==.Jazmean:BAAALgAECgYJCgAAAA==.',
Je='Jeks:BAAALgADCgcJBwABLgAFFAcJHwAJANwXAA==.Jemma:BAABLgAECn8mAAIZAAkJJBElCACwAQAZAAkJJBElCACwAQAAAA==.Jettadari:BAACLgAFFH8RAAISAAcJ5RMXEABNAQASAAcJ5RMXEABNAQAuAAQKfyYAAxIACQlsIO0WAM0CABIACQlsIO0WAM0CAAIAAQlADjMvADAAAAAA.Jettadin:BAABLgAECn8aAAIFAAgJ9yGnDwARAwAFAAgJ9yGnDwARAwABLgAFFAcJEQASAOUTAA==.Jettakins:BAAALgAFFAEJAQABLgAFFAcJEQASAOUTAA==.Jettathyr:BAAALgAECgcJDQABLgAFFAcJEQASAOUTAA==.',
Ju='Jubba:BAABLgAECn8fAAIVAAkJ1xTwPwAGAgAVAAkJ1xTwPwAGAgAAAA==.Juderius:BAAALgADCgQJBAABLgAECgQJBQAEAAAAAA==.Junk:BAABLgAECn8jAAIbAAkJwCFQAwAAAwAbAAkJwCFQAwAAAwAAAA==.',
['Jë']='Jëks:BAACLgAFFH8fAAIJAAcJ3Be0BwASAgAJAAcJ3Be0BwASAgAuAAQKfykAAwkACQlhJXEDAEEDAAkACQlhJXEDAEEDAAwAAgkvDq4rAGIAAAAA.',
Ka='Kaghroxxar:BAAALgADCgkJGAAAAA==.Kahea:BAAALgAECgQJBAAAAA==.Kaitou:BAABLgAECn82AAMWAAkJMSKYAgDkAgAWAAkJMSKYAgDkAgAkAAEJrQ6CgQAwAAAAAA==.Kalamiti:BAABLgAECn8YAAMZAAkJEBAKCwBzAQAZAAgJCQ8KCwBzAQAhAAYJswn7FwDeAAAAAA==.Kallar:BAABLgAECn84AAMYAAkJRCA+BQAVAwAYAAkJRCA+BQAVAwAHAAIJUQZwcgA4AAAAAA==.Karesh:BAAALgAECgQJBAAAAA==.Kayeera:BAABLgAECn8aAAMYAAcJGRj9GwDPAQAYAAcJGRj9GwDPAQAHAAQJBQUDTwCWAAAAAA==.Kayha:BAAALgADCgYJCAAAAA==.Kaylrandi:BAAALgAECgcJCwAAAA==.Kaztiel:BAAALgAECgIJAgAAAA==.',
Ke='Keadon:BAAALgAFFAEJAQAAAA==.Kearza:BAAALgAECgQJBQAAAA==.Keeper:BAAALgADCgMJAwABLgAECgcJLQAQAE4jAA==.Keh:BAAALgADCgkJCQAAAA==.Keiyona:BAAALgAECgcJCgABLgAECgkJIgAFAKsdAA==.Kennethv:BAAALgAECgcJCgAAAA==.Kenze:BAAALgAECgEJAQAAAA==.Kethra:BAAALgADCggJEgAAAA==.Kev:BAAALgAECgcJBwAAAA==.',
Kh='Khel:BAAALgADCgcJBwAAAA==.Khibanee:BAAALgADCgQJBAAAAA==.Khiell:BAACLgAFFH8LAAIQAAQJgQ9uJAAGAQAQAAQJgQ9uJAAGAQAuAAQKfyIAAhAACQkmGn4XAB4CABAACQkmGn4XAB4CAAAA.',
Ki='Kilyse:BAAALgADCgYJBgAAAA==.Kinigit:BAAALgAECgUJCAABLgAFFAUJFwAkAGEXAA==.Kirïtö:BAAALgAECgUJCwAAAA==.Kitarah:BAEALgAECgIJAgABLgAECgkJEAAEAAAAAA==.Kitarazen:BAEALgAECgkJEAAAAA==.Kizli:BAAALgADCgUJBQAAAA==.',
Kn='Knoway:BAAALgADCgUJBQAAAA==.',
Ko='Kokushimosu:BAAALgAECgYJDgAAAA==.Koo:BAAALgAECgUJBwAAAA==.Koviel:BAAALgAECgEJAQAAAA==.',
Kr='Kragon:BAAALgAECgEJAQAAAA==.Krátos:BAABLgAECn8oAAMRAAkJBxqNBwBoAgARAAkJBxqNBwBoAgAQAAgJaREULQCKAQAAAA==.',
Ks='Ksper:BAAALgAECgcJEgAAAA==.',
Ku='Kukalak:BAABLgAECn8YAAIjAAgJ7BvSEQDrAQAjAAgJ7BvSEQDrAQAAAA==.Kurulak:BAABLgAECn8tAAISAAkJ5hDKPwCyAQASAAkJ5hDKPwCyAQAAAA==.Kuzcotopiajr:BAAALgADCgEJAQAAAA==.',
Ky='Kymru:BAAALgADCgcJDQAAAA==.',
['Ké']='Kénnéth:BAAALgAECgYJDgAAAA==.',
La='Lacerveza:BAAALgAECgIJBQAAAA==.Lahyanhou:BAABLgAECn8zAAITAAkJLQifDwBHAQATAAkJLQifDwBHAQAAAA==.Lalalalala:BAAALgAECgcJCgAAAA==.Lalin:BAAALgAECgEJBQAAAA==.Larkwyn:BAAALgAECgQJBAABLgAFFAQJCgAGAK8QAA==.Laylah:BAAALgADCgYJBAAAAA==.',
Le='Lebrand:BAAALgAECgEJAQAAAA==.Leriope:BAABLgAECn9IAAIGAAkJkxdJIgBMAgAGAAkJkxdJIgBMAgAAAA==.Leàf:BAAALgAECggJDgAAAA==.',
Li='Lichfiend:BAAALgADCgEJAQAAAA==.Lightbeer:BAAALgAECgYJBwAAAA==.Lihplock:BAAALgAECgQJCAABLgAFFAQJFAAQAN0kAA==.Lilandri:BAAALgAECgYJBwAAAA==.Lildragonboi:BAAALgADCgUJBQAAAA==.Lilem:BAAALgADCgcJEgAAAA==.Lilpooch:BAAALgAECgYJBwAAAA==.Listenlinda:BAAALgAECgIJAwAAAA==.Lithariel:BAAALgADCgkJCAAAAA==.Littlemerald:BAAALgAECgUJCwAAAA==.',
Lj='Lj:BAABLgAECn9BAAIlAAkJDB8nCQDlAgAlAAkJDB8nCQDlAgAAAA==.',
Lo='Localsingles:BAAALgADCgcJBwAAAA==.Lorath:BAAALgADCgEJAQAAAA==.Lovecrafft:BAAALgAECgMJBwAAAA==.Lovetrain:BAAALgAECgYJBQAAAA==.',
Lu='Lu:BAABLgAFFH8HAAMbAAMJzxdUNQAvAAAPAAIJzxfdtgCOAAAbAAIJtA5UNQAvAAABLgAFFAUJDwAeAD8SAA==.Lucinà:BAABLgAECn8+AAQFAAkJeSLjEgC+AgAFAAgJ8CPjEgC+AgAlAAkJQR+TDAC1AgADAAUJkB2ZGQAzAQAAAA==.Lusande:BAAALgAECgQJBgAAAA==.Luxure:BAAALgAECgYJBgAAAA==.Luxùria:BAAALgAECgEJAQAAAA==.',
Ly='Lyndall:BAAALgAECgQJBgAAAA==.',
Ma='Machamp:BAAALgAECgEJAwAAAA==.Madammìm:BAAALgAECgEJAQAAAA==.Maegan:BAAALgAECgcJEAAAAA==.Maewyn:BAAALgAECgEJAgAAAA==.Mager:BAAALgAECgUJDAAAAA==.Magerhunter:BAAALgAECgYJCAAAAA==.Magolock:BAAALgAECgUJEQAAAA==.Mahll:BAAALgAECgMJAwAAAA==.Maidrim:BAACLgAFFH8YAAImAAcJ3xavAAAHAgAmAAcJ3xavAAAHAgAuAAQKfx8AAiYACQmrIfICALICACYACQmrIfICALICAAAA.Makaveli:BAAALgAECgcJBwAAAA==.Makavelli:BAAALgADCgEJAQAAAA==.Mamajumbo:BAABLgAECn8XAAIUAAgJChggNgDtAQAUAAgJChggNgDtAQAAAA==.Marage:BAAALgADCgEJAQAAAA==.Marellias:BAAALgAECgMJBAABLgAECggJJwAFADokAA==.Marikel:BAAALgAECgQJDwAAAA==.Markwel:BAAALgAECgIJAgAAAA==.Marrack:BAAALgAECgYJDQAAAA==.',
Me='Melador:BAAALgADCgIJAgAAAA==.Meletha:BAAALgAECgYJDwAAAA==.Melpuis:BAAALgAECgEJAgAAAA==.Metahorfasis:BAAALgAECgUJBQAAAA==.',
Mi='Michaelken:BAABLgAECn8iAAMlAAkJDhc9EwBhAgAlAAkJDhc9EwBhAgAFAAEJsAeQeAEvAAAAAA==.Mierín:BAAALgADCgYJBgAAAA==.Migrains:BAABLgAECn9JAAIDAAkJ1yT6AABFAwADAAkJ1yT6AABFAwAAAA==.Mineo:BAAALgAECgYJBwAAAA==.Mirâjâne:BAAALgAECgEJAQAAAA==.Miskaabin:BAABLgAECn8qAAMFAAcJGw1EnQAgAQAFAAcJ+gxEnQAgAQADAAUJogqoLwCPAAAAAA==.Miststress:BAAALgAECgcJCAAAAA==.',
Mo='Mobal:BAABLgAECn8zAAMJAAkJRx6wFwBzAgAJAAgJjx2wFwBzAgAKAAQJxgiTbACDAAAAAA==.Modarku:BAAALgADCgQJBAAAAA==.Mojogreens:BAAALgAECgYJEQAAAA==.Montydh:BAAALgAECgEJAQAAAA==.Moonblades:BAAALgADCgUJBQAAAA==.Moonpetals:BAAALgAECgEJAgAAAA==.Moonrush:BAAALgAECgMJCAAAAA==.Mortiis:BAAALgAECgYJEwAAAA==.Motako:BAABLgAECn8gAAIJAAcJRCCfFQBoAgAJAAcJRCCfFQBoAgAAAA==.',
Mp='Mpd:BAAALgAECgcJDAAAAA==.',
My='Mybizël:BAABLgAECn8pAAIUAAcJwR7oIABAAgAUAAcJwR7oIABAAgAAAA==.Myrlifax:BAAALgADCgEJAQABLgAECgcJEAAEAAAAAA==.Mystique:BAABLgAECn8VAAICAAgJ4gd1EgALAQACAAgJ4gd1EgALAQAAAA==.Mythdaraghma:BAAALgAECgUJCgAAAA==.',
['Má']='Máximo:BAAALgAECgYJEAAAAA==.',
['Mí']='Míerin:BAAALgAECgQJBAAAAA==.Míerín:BAACLgAFFH8TAAInAAUJnRwTDQBPAQAnAAUJnRwTDQBPAQAuAAQKfzcAAycACQnBJbwBADEDACcACQnBJbwBADEDABQABAm+G0NgAEcBAAAA.',
['Mø']='Møøse:BAAALgAECgEJAQAAAA==.',
Na='Naama:BAAALgADCggJHwAAAA==.Nadaar:BAABLgAECn8bAAIfAAgJWhnqAgD5AQAfAAgJWhnqAgD5AQAAAA==.Naelih:BAABLgAECn8rAAITAAgJTQ4sDgBhAQATAAgJTQ4sDgBhAQAAAA==.Naharuk:BAAALgADCgMJAwAAAA==.Natholomas:BAAALgADCgQJBAAAAA==.Natlès:BAAALgAECggJCwAAAA==.Nattwenty:BAAALgAECgQJBAAAAA==.Nazeer:BAAALgADCgcJBwABLgAFFAUJCAAgALMEAA==.Nazgrim:BAACLgAFFH8IAAIgAAUJswQ+KAAIAQAgAAUJswQ+KAAIAQAuAAQKfz0AAiAACAnGFlsvAO8BACAACAnGFlsvAO8BAAAA.',
Ne='Necronu:BAABLgAFFH8JAAIPAAMJBRfieQDqAAAPAAMJBRfieQDqAAABLgAFFAUJIAAdAO0fAA==.',
Ni='Nikkolos:BAABLgAECn8aAAIBAAgJvQvPIgA9AQABAAgJvQvPIgA9AQAAAA==.Ninjastax:BAAALgAECgEJAgAAAA==.Nissie:BAAALgAECgEJAQAAAA==.Nitazendezot:BAAALgAECgMJBAABLgAFFAQJDgAPALsVAA==.',
No='Nogusta:BAACLgAFFH8YAAIQAAYJNxzlCgCMAQAQAAYJNxzlCgCMAQAuAAQKfykAAhAACQloHzsKAK0CABAACQloHzsKAK0CAAAA.Norberta:BAABLgAECn8aAAMdAAgJZAc/QgD/AAAiAAYJWAbxIwAIAQAdAAgJ4gY/QgD/AAAAAA==.Nossanir:BAAALgAECgIJAgAAAA==.Nossellia:BAAALgAECgQJBwAAAA==.',
Nu='Nuggetssham:BAAALgADCgcJBwAAAA==.Nurana:BAAALgADCgEJAQAAAA==.',
Ny='Nycecritz:BAAALgAECgEJAQAAAA==.',
['Nä']='Näturi:BAAALgAECgQJBAAAAA==.',
Od='Odor:BAAALgAECgQJBgAAAA==.',
Ol='Oldie:BAAALgAECgIJAgAAAA==.Olielno:BAAALgADCgMJAwAAAA==.',
On='Onlyshams:BAABLgAECn8hAAIJAAgJtBgvGQBNAgAJAAgJtBgvGQBNAgAAAA==.Onlytides:BAEBLgAECn8dAAMJAAkJ2SPlBwD2AgAJAAkJ2SPlBwD2AgAKAAcJXRiAHwAUAgABLgAFFAcJHgAgAH4bAA==.Onubis:BAACLgAFFH8QAAMUAAUJriG4HABmAQAUAAUJriG4HABmAQAnAAIJ5yBkHwCzAAAuAAQKfx8ABBQACQmaHw8MAOECABQACQmOHw8MAOECABMABgnGHdk0AJcBACcAAQmkI85NAF0AAAEuAAUUBQkgAB0A7R8A.Onuchi:BAABLgAFFH8FAAIeAAUJNATzJwDdAAAeAAUJNATzJwDdAAABLgAFFAUJIAAdAO0fAA==.Onulock:BAAALgAECgYJCgABLgAFFAUJIAAdAO0fAA==.Onux:BAABLgAFFH8QAAISAAUJHRwHKABaAQASAAUJHRwHKABaAQABLgAFFAUJIAAdAO0fAA==.',
Op='Opgarbage:BAAALgAECgQJCwAAAA==.',
Ou='Oukei:BAAALgAECgcJEgABLgAFFAYJEwAEAAAAAQ==.Oumura:BAAALgAECgYJDgAAAA==.',
Ov='Overlordainz:BAAALgAECgYJEwAAAA==.',
Pa='Paarthürnax:BAAALgAECgYJDAAAAA==.Padamee:BAAALgAECgQJBwAAAA==.Paganini:BAAALgAECgQJBAABLgAECgkJHwAUAHUdAA==.Pallyoop:BAABLgAECn8WAAIlAAcJMg9QTwDkAAAlAAcJMg9QTwDkAAAAAA==.Pandaa:BAAALgAECgEJAQAAAA==.Papapaw:BAAALgAECgQJBgAAAA==.Pathator:BAAALgAECgEJAQABLgAECggJFwAPAGkbAA==.Patherion:BAAALgADCgEJAQABLgAECggJFwAPAGkbAA==.Patholans:BAABLgAECn8XAAIPAAgJaRvsLQA0AgAPAAgJaRvsLQA0AgAAAA==.Pathology:BAAALgAECgMJAwABLgAECggJFwAPAGkbAA==.Paxman:BAAALgAECgQJBwAAAA==.',
Pe='Peanits:BAAALgAECgQJCwABLgAECgkJIwACAJciAA==.Peanutsuckr:BAACLgAFFH8hAAIbAAcJGiAMBAAlAgAbAAcJGiAMBAAlAgAuAAQKfykAAhsACQnGJZQBAD4DABsACQnGJZQBAD4DAAAA.Pearserve:BAAALgADCgYJBgABLgAECggJFAAKANoPAA==.',
Ph='Phantöm:BAAALgAECgQJDAAAAA==.Phosphate:BAABLgAECn8QAAISAAYJNxKvbgBYAQASAAYJNxKvbgBYAQAAAA==.',
Pi='Piccolo:BAAALgAECgQJBgAAAA==.Pingg:BAAALgAECgQJBQAAAA==.Pinkeye:BAAALgAECgcJCgAAAA==.Pippafan:BAAALgAECgEJAQABLgAECgEJAwAEAAAAAA==.',
Pl='Placcid:BAABLgAECn86AAIUAAkJIh2YEwCfAgAUAAkJIh2YEwCfAgAAAA==.Planknstein:BAAALgADCgMJAwAAAA==.Playdohh:BAAALgAECgcJCQAAAA==.Plutonia:BAAALgAECgMJBwAAAA==.',
Po='Pockett:BAABLgAECn8dAAMKAAcJKhHGOAA4AQAKAAcJKhHGOAA4AQAMAAUJBQnnGwAMAQAAAA==.Powrwordgoat:BAACLgAFFH8IAAIIAAMJrwmcKwC8AAAIAAMJrwmcKwC8AAAuAAQKfy0AAggACAllE38eALcBAAgACAllE38eALcBAAAA.',
Pr='Prestoh:BAABLgAECn8rAAIKAAkJCBHdJACoAQAKAAkJCBHdJACoAQAAAA==.Prismclaw:BAABLgAECn9AAAIVAAkJpRJoQgD+AQAVAAkJpRJoQgD+AQAAAA==.Prisoner:BAAALgAECgEJAwAAAA==.Processing:BAAALgAECgYJBgAAAA==.',
Ps='Pseudoruski:BAAALgADCgMJAwAAAA==.',
Pu='Purplehaze:BAAALgAECgQJBAAAAA==.',
Pv='Pvlolz:BAABLgAECn8ZAAIYAAkJ3QpDMACAAQAYAAkJ3QpDMACAAQAAAA==.',
Pw='Pwnstarz:BAAALgAECgYJBwAAAA==.',
Py='Pyrada:BAAALgAECggJDQAAAA==.',
Qa='Qaharn:BAAALgAECgQJBwAAAA==.',
Qp='Qplus:BAABLgAECn8iAAIUAAkJ5AhhTwCbAQAUAAkJ5AhhTwCbAQAAAA==.',
Qu='Quackadilly:BAAALgADCgcJDQAAAA==.Quaenie:BAABLgAECn8hAAIYAAkJ7hZJEwApAgAYAAkJ7hZJEwApAgAAAA==.Quintin:BAAALgAECgcJDgAAAA==.',
Ra='Raged:BAAALgAECgUJCgAAAA==.Ragegauge:BAAALgAECgQJBgAAAA==.Ragetotem:BAABLgAECn8gAAIKAAYJmRwgKADSAQAKAAYJmRwgKADSAQAAAA==.Ragewarg:BAAALgAECgcJDAAAAA==.Ragnashock:BAAALgAECgQJBgAAAA==.Ralvarr:BAABLgAECn8aAAIeAAgJIBimGwDbAQAeAAgJIBimGwDbAQAAAA==.Raptorjésus:BAAALgADCgcJCwAAAA==.Rastik:BAAALgADCgIJAgAAAA==.Rathaes:BAAALgADCgMJAwAAAA==.Ravenstryke:BAAALgAECgEJAQAAAA==.Raylea:BAAALgADCgcJBwAAAA==.Rayleigh:BAAALgAECgcJDAABLgAECgUJCwAEAAAAAA==.Razzgix:BAAALgAECgUJBgAAAA==.',
Re='Redchord:BAAALgADCgUJDAAAAA==.Regidør:BAABLgAECn8ZAAMlAAgJ/CBcCADoAgAlAAgJ/CBcCADoAgAFAAYJxx0XYQDBAQAAAA==.Relik:BAABLgAECn8jAAIjAAkJjwxIFwBwAQAjAAkJjwxIFwBwAQAAAA==.Resith:BAAALgAECgYJCAAAAA==.',
Rh='Rhaelia:BAABLgAECn8ZAAIFAAcJFQmksQAAAQAFAAcJFQmksQAAAQAAAA==.Rhaspus:BAAALgADCgQJBAAAAA==.',
Ri='Rilliccine:BAAALgADCgkJCwAAAA==.Rillinetti:BAABLgAECn8jAAIGAAkJOROBNgDyAQAGAAkJOROBNgDyAQAAAA==.Rillini:BAAALgADCgcJBwAAAA==.Rilliti:BAAALgAECgYJDgAAAA==.',
Ro='Rondon:BAABLgAECn8wAAIUAAkJoCU9AgBlAwAUAAkJoCU9AgBlAwAAAA==.Rookdh:BAACLgAFFH8NAAMBAAUJvQZoEgDlAAABAAQJUQRoEgDlAAASAAUJogahTQDiAAAuAAQKfykAAxIACQnkFt5SAHUBABIACAk+GN5SAHUBAAEABwkyFucsAGMBAAAA.Rorcia:BAAALgADCgcJFAAAAA==.Rosey:BAABLgAECn8sAAIFAAkJcxVRNgAPAgAFAAkJcxVRNgAPAgAAAA==.Rotmaxxer:BAAALgAECgQJBgAAAA==.Roxania:BAAALgADCgYJBgAAAA==.Royale:BAAALgAECgcJBwAAAA==.',
Ru='Rudyeightbal:BAABLgAECn8bAAMGAAgJCQycjgATAQAGAAYJhw2cjgATAQAZAAIJFQNZPwAgAAAAAA==.Ruedons:BAAALgAECgMJAwAAAA==.Rugsalon:BAACLgAFFH8IAAIVAAMJCwm4egDLAAAVAAMJCwm4egDLAAAuAAQKfycAAhUACQn1HPM0AJ8CABUACQn1HPM0AJ8CAAAA.Rustedbarrel:BAACLgAFFH8IAAIaAAMJqwt1NgC4AAAaAAMJqwt1NgC4AAAuAAQKfxsAAhoACQmnE3YhAPYBABoACQmnE3YhAPYBAAAA.',
Ry='Ryptar:BAAALgADCgkJHAAAAA==.',
['Rè']='Rèaper:BAAALgAECgMJAwAAAA==.',
['Ré']='Réxxar:BAABLgAECn8cAAINAAcJPRTbDQClAQANAAcJPRTbDQClAQAAAA==.',
Sa='Saelyres:BAABLgAECn8gAAMCAAgJxx30BABJAgACAAgJxx30BABJAgABAAEJ1wNHegApAAAAAA==.Sagesse:BAAALgADCgYJBgAAAA==.Saikye:BAAALgAECgEJAQAAAA==.Sairu:BAAALgADCgEJAQAAAA==.Saisera:BAAALgAFFAIJAgAAAA==.Samistraza:BAAALgADCgEJAQAAAA==.Sammy:BAABLgAECn8jAAIFAAkJvQmSfABaAQAFAAkJvQmSfABaAQAAAA==.Santaclaaws:BAACLgAFFH8RAAISAAQJXxvVLQBDAQASAAQJXxvVLQBDAQAuAAQKfzUABBIACQmkIgkSAJ4CABIACQmkIgkSAJ4CAAIAAwldFiIZALkAAAEAAgk1GY5bAHIAAAAA.Santapal:BAABLgAECn8tAAQlAAgJDhq2JADLAQAlAAcJoRq2JADLAQAFAAIJegUFSAFLAAADAAIJaRLFRgA2AAABLgAFFAQJEQASAF8bAA==.Santatumblr:BAABLgAECn8aAAQeAAgJURu/EgBmAgAeAAgJURu/EgBmAgAXAAQJchADZQBwAAAaAAEJTQMsnQAcAAABLgAFFAQJEQASAF8bAA==.Santhin:BAAALgADCgcJCgAAAA==.Saphira:BAAALgAECgQJBAAAAA==.Sareit:BAABLgAECn8cAAMIAAcJHw4/NgAVAQAIAAYJIQw/NgAVAQAHAAYJAhLWNwATAQAAAA==.Sassee:BAAALgAECgQJCAAAAA==.Sayvil:BAAALgAECgUJCwABLgAECgkJOAAYAEQgAQ==.',
Sc='Scripture:BAAALgADCgYJBgAAAA==.',
Se='Seawolph:BAABLgAECn8wAAIJAAkJvxdOGwBXAgAJAAkJvxdOGwBXAgAAAA==.Selenia:BAAALgAECgMJAwAAAA==.Semmers:BAAALgAECgkJCQAAAA==.Sensational:BAABLgAECn8aAAMeAAcJWhx+EwAvAgAeAAcJWhx+EwAvAgAXAAUJZwhQUQCsAAAAAA==.Sergio:BAAALgAECgcJCgAAAA==.',
Sh='Shamiska:BAAALgAECgUJCAAAAA==.Shammerdown:BAAALgAECgIJAwAAAA==.Shampooh:BAAALgAECgQJBQABLgAECgcJFgAgAMYEAA==.Shamtastyk:BAAALgAECgQJBAAAAA==.Shaokhan:BAABLgAECn8qAAMJAAkJiSFeBgA2AwAJAAkJiSFeBgA2AwAMAAcJuwolFwAuAQAAAA==.Sheilla:BAAALgADCgUJBQAAAA==.Shian:BAABLgAECn80AAINAAkJLxWXDAD4AQANAAkJLxWXDAD4AQAAAA==.Shieldee:BAABLgAECn8uAAMFAAgJUxzRPAD5AQAFAAgJUxzRPAD5AQAlAAEJTgMNkgAiAAAAAA==.Shlectrinell:BAABLgAECn9CAAMoAAkJ7A7yFQDXAQAoAAkJ7A7yFQDXAQAmAAgJBAUICwB+AQAAAA==.Shockeei:BAACLgAFFH8dAAIVAAYJACHlDgCiAQAVAAYJACHlDgCiAQAuAAQKfykABBUACQkqJT4HADIDABUACQkqJT4HADIDACkAAwlSGHcJALkAAB8AAQnWIL4PAFcAAAAA.Shocktroop:BAAALgADCgYJCgAAAA==.Shortdon:BAAALgAECgEJAQAAAA==.Shurp:BAAALgAECgMJAwAAAA==.',
Si='Siakora:BAABLgAECn8VAAIoAAgJXRgLGwAoAgAoAAgJXRgLGwAoAgABLgAFFAcJIAAkAD4aAA==.Sicksty:BAAALgADCgcJBwAAAA==.Sighh:BAAALgAECgYJBwAAAA==.Sighhy:BAAALgAECgUJDgAAAA==.Sijth:BAABLgAECn9MAAIFAAkJjCD5GACXAgAFAAkJjCD5GACXAgAAAA==.Silentchaos:BAAALgADCgMJBQAAAA==.Siler:BAAALgADCgYJBgAAAA==.Silverwar:BAABLgAECn8jAAIQAAgJwRoLGgAJAgAQAAgJwRoLGgAJAgAAAA==.Simmi:BAECLgAFFH8eAAIgAAcJfhuKBQB2AgAgAAcJfhuKBQB2AgAuAAQKfykAAiAACQnBJWEFAFYDACAACQnBJWEFAFYDAAAA.Sinnis:BAAALgAECgEJAQAAAA==.Sirlavan:BAAALgAECgUJBQAAAA==.Sixte:BAAALgAECgcJCgAAAA==.Sixtea:BAABLgAECn8kAAIKAAkJYRpPEQBQAgAKAAkJYRpPEQBQAgAAAA==.',
Sk='Skarredd:BAAALgADCgcJDwAAAA==.Skepti:BAABLgAECn8qAAIUAAkJiBqNHQBfAgAUAAkJiBqNHQBfAgAAAA==.Skysong:BAAALgAECgMJAwAAAA==.',
Sl='Slapdemhoes:BAAALgAECgcJAgAAAA==.Slimfoo:BAAALgAECgcJDQAAAA==.Slunkyspit:BAAALgADCgUJCAAAAA==.Slybearclaw:BAAALgADCgUJBQAAAA==.Slyeulogy:BAAALgAECgQJBQAAAA==.',
Sm='Smeeta:BAACLgAFFH8HAAIPAAMJ4BkfewDoAAAPAAMJ4BkfewDoAAAuAAQKf14ABA8ACQmHJF4MAPkCAA8ACQkxJF4MAPkCABwACAldI60CAK4CABsABQlQET0zALUAAAAA.Smoak:BAAALgADCgUJBQAAAA==.Smolderlight:BAABLgAECn86AAIlAAkJ6BS4GgAYAgAlAAkJ6BS4GgAYAgAAAA==.Smoochiebutt:BAAALgAECgUJCQAAAA==.',
So='Solaace:BAAALgAECgEJAQABLgAECgcJEAAEAAAAAA==.Solo:BAAALgAECgYJCQAAAA==.Soloris:BAAALgADCgcJCAAAAA==.Sonja:BAAALgAECgcJBwAAAA==.Soram:BAAALgAECgYJCgAAAA==.Soulstryker:BAAALgAECgEJAQAAAA==.Soùl:BAAALgADCgQJBAAAAA==.',
Sp='Spacepants:BAAALgAECgEJAQAAAA==.Spurgeon:BAAALgAECgEJAQAAAA==.',
St='Staraelle:BAAALgAECgEJAgAAAA==.Stazz:BAAALgAECgYJBgAAAA==.Steelerayne:BAAALgAECggJEAAAAA==.Stormii:BAABLgAECn8ZAAMJAAkJLAxhUABSAQAJAAgJEgphUABSAQAKAAMJfhTzWgC3AAAAAA==.Strangelock:BAAALgAECgYJBgABLgAECgkJMgAPALoNAA==.Strangerdk:BAABLgAECn8yAAIPAAkJug3DUwC1AQAPAAkJug3DUwC1AQAAAA==.Streetdog:BAAALgADCgYJBgAAAA==.Stublin:BAAALgADCgEJAQAAAA==.Stuggens:BAAALgADCgkJCQAAAA==.',
Su='Suggondeez:BAAALgAECgYJBgAAAA==.Superfatbaby:BAABLgAECn8dAAIQAAkJKhMKIwDHAQAQAAkJKhMKIwDHAQAAAA==.',
Sw='Swikk:BAAALgADCgYJCAAAAA==.Swishersweet:BAABLgAECn8qAAINAAkJlgnxIgATAQANAAkJlgnxIgATAQAAAA==.Swordfish:BAABLgAECn8dAAIiAAcJYSHjAwA0AgAiAAcJYSHjAwA0AgAAAA==.',
Sy='Syannae:BAAALgADCgYJBwAAAA==.Sybros:BAAALgADCgEJAQAAAA==.Sydonie:BAAALgAECgEJBgAAAA==.Sylus:BAAALgAECgQJBAAAAA==.Symbah:BAAALgADCgYJBgAAAA==.Synvalid:BAABLgAECn8gAAISAAkJ9wf+fwAEAQASAAkJ9wf+fwAEAQAAAA==.Syzrin:BAAALgADCgEJAQABLgAECggJIgAGAHcUAA==.',
Ta='Tabrieus:BAABLgAECn9AAAIVAAkJliA8DgD0AgAVAAkJliA8DgD0AgAAAA==.Tadokof:BAAALgADCgkJIgAAAA==.Talanth:BAABLgAECn8XAAImAAkJ0AivCQCOAQAmAAkJ0AivCQCOAQAAAA==.Talya:BAAALgAECggJCAABLgAECgkJNAANAC8VAA==.Tandisong:BAAALgAECgcJCAAAAA==.Tanknhammerm:BAAALgADCgYJBgAAAA==.Tanknstein:BAAALgADCgYJBgAAAA==.Tanton:BAAALgAECgMJAwAAAA==.Tanzil:BAAALgAECgYJDgAAAA==.Tardigrade:BAAALgAECggJEwAAAA==.Tareyna:BAABLgAECn8aAAIFAAkJxRHVQgDlAQAFAAkJxRHVQgDlAQAAAA==.Tayon:BAAALgAECggJEgAAAA==.Tayvin:BAAALgAECgQJDAAAAA==.Tazanath:BAAALgADCgEJAgAAAA==.',
Te='Tempest:BAAALgADCgcJBwAAAA==.Tengen:BAAALgAECgUJDAAAAA==.Termana:BAACLgAFFH8gAAIjAAYJiyBgBgCrAQAjAAYJiyBgBgCrAQAuAAQKfygAAiMACQmCJAwCACIDACMACQmCJAwCACIDAAAA.',
Th='Thanel:BAAALgADCgQJBAAAAA==.Tharja:BAABLgAECn8bAAIVAAkJXhvvNACfAgAVAAkJXhvvNACfAgAAAA==.Theaviendha:BAAALgAECgEJAQABLgAECggJFwAPAGkbAA==.Thornp:BAAALgAECgEJAgAAAA==.Thoronk:BAAALgAECgcJBgAAAA==.Thsaric:BAAALgAECgEJAQAAAA==.Thug:BAABLgAECn8WAAMQAAcJ0R/RJQArAgAQAAcJ0R/RJQArAgAjAAIJHxvRNgCRAAAAAA==.Thuggin:BAAALgAECgQJBQAAAA==.',
Ti='Tiferet:BAABLgAECn8sAAQYAAkJLiDRBQAJAwAYAAkJLiDRBQAJAwAHAAgJQAtcLABTAQAIAAMJfRLoPgC3AAAAAA==.Tigiw:BAAALgAECgMJBAAAAA==.Tinysunshine:BAABLgAECn8UAAIXAAgJ6BtXEAAxAgAXAAgJ6BtXEAAxAgAAAA==.Tinyt:BAAALgAECgEJAQAAAA==.Tiramisu:BAAALgADCgQJBAAAAA==.Tismyhammer:BAAALgADCgQJBAAAAA==.',
To='Toasted:BAAALgADCgQJAQAAAA==.Tolenkar:BAABLgAECn8fAAIUAAkJdR0yGAB+AgAUAAkJdR0yGAB+AgAAAA==.Tomato:BAACLgAFFH8XAAMZAAYJNxDaBwDxAAAGAAUJwxGtQwAtAQAZAAQJxA3aBwDxAAAuAAQKfyMAAxkACQlpHaYFAHoCABkACAkIHKYFAHoCAAYABQlZFwySAA0BAAAA.Tomhanks:BAAALgAECgcJEAAAAA==.Tormentaa:BAAALgAECgYJBwAAAA==.Torvalar:BAABLgAECn9LAAIFAAkJoBn5JgBPAgAFAAkJoBn5JgBPAgAAAA==.',
Tr='Treemendous:BAAALgADCgYJCQAAAA==.Trolgoskill:BAAALgADCgQJBAAAAA==.Truthslayer:BAABLgAECn8cAAMQAAkJKAkhQwAhAQAQAAkJKAkhQwAhAQARAAEJcgr/QgAzAAAAAA==.Trûth:BAABLgAECn8WAAIHAAgJxBBMIwC9AQAHAAgJxBBMIwC9AQAAAA==.',
Tu='Tugzug:BAAALgAECgEJAQAAAA==.Turdyl:BAABLgAECn8sAAIFAAkJuhEIXgCcAQAFAAkJuhEIXgCcAQAAAA==.',
Tw='Twindad:BAAALgADCgkJEQAAAA==.Twindadlock:BAAALgAECgEJAQAAAA==.Twowheels:BAAALgAECgMJBAAAAA==.',
Ty='Tyraz:BAAALgAECgcJEwAAAA==.Tystrolf:BAABLgAECn8YAAQkAAcJrg1VPwD1AAAkAAYJ/w5VPwD1AAAWAAUJjAfHLQCGAAANAAIJgAkoXQA4AAAAAA==.',
Tz='Tzar:BAAALgADCgIJAgAAAA==.',
['Tô']='Tôx:BAABLgAECn8XAAMKAAcJWB1YLQCwAQAKAAcJWB1YLQCwAQAJAAIJRhTFvQA1AAAAAA==.',
Ub='Ubrew:BAAALgAECgkJBQAAAA==.',
Ud='Udyrr:BAAALgADCgIJAgAAAA==.',
Ul='Ulfius:BAAALgADCgMJAwAAAA==.Ullume:BAAALgAECgkJDQAAAA==.',
Um='Umbranwings:BAAALgAECgUJBQAAAA==.',
Un='Unheardjp:BAAALgAECgMJCwAAAA==.Unholy:BAAALgAECgIJAgAAAA==.Unholyarnix:BAAALgAECgQJDQAAAA==.',
Ur='Ursus:BAAALgADCgYJBgAAAA==.Uruloki:BAAALgADCgIJAgAAAA==.',
Va='Vacuum:BAAALgAECgYJEQAAAA==.Vadican:BAAALgADCgQJBAAAAA==.Vaerix:BAABLgAECn8pAAIdAAkJ1Q2nKgB4AQAdAAkJ1Q2nKgB4AQAAAA==.Valdora:BAAALgAECgEJAQAAAA==.Valhals:BAABLgAECn8rAAMaAAkJDAgMOAALAQAaAAgJTAUMOAALAQAXAAMJUQ7+aQBkAAAAAA==.Valydrin:BAABLgAECn9JAAIYAAkJ9B0FCQDEAgAYAAkJ9B0FCQDEAgAAAA==.Vanhelsinky:BAAALgADCgIJAgAAAA==.Vanquished:BAAALgAECgIJBAAAAA==.Varyn:BAAALgADCgIJAgAAAA==.',
Ve='Velandia:BAAALgAECgcJDAAAAA==.Ventis:BAAALgAECgQJBwAAAA==.',
Vi='Vicara:BAAALgADCgYJBgAAAA==.Virgl:BAAALgAECgkJBQAAAA==.',
Vo='Voidifphat:BAAALgAECggJEAAAAA==.Voidtorrent:BAAALgAECgQJCAAAAA==.Voidvanquish:BAAALgAECgYJBwAAAA==.Vorkhan:BAAALgADCgUJCAAAAA==.',
Vu='Vuldrak:BAAALgAECggJEwAAAA==.',
Vy='Vysis:BAACLgAFFH8QAAQHAAMJeQkhIQDFAAAHAAMJeQkhIQDFAAAIAAMJUAl8LAC3AAAYAAIJ1AwHDgCOAAAuAAQKf0gABBgACQluGYcSAEwCABgACQlQF4cSAEwCAAcACAmGG3wSACMCAAgACAkMFLgYAOoBAAAA.',
['Vä']='Vännic:BAAALgADCgEJAwAAAA==.Vännìc:BAAALgADCgEJAQAAAA==.',
['Ví']='Ví:BAABLgAECn8dAAIXAAkJsQpoJwBjAQAXAAkJsQpoJwBjAQAAAA==.',
Wh='Whatfoxsay:BAAALgADCgEJAQAAAA==.Whats:BAAALgADCgcJBwABLgAECgcJEAAEAAAAAA==.When:BAAALgADCgQJBAAAAA==.Whicker:BAAALgAECgUJBgAAAA==.Whipsnchains:BAAALgAECgUJBgAAAA==.Whipsntricks:BAAALgAECgIJAgAAAA==.',
Wi='Wickèr:BAACLgAFFH8GAAIaAAIJ9hIdPgCNAAAaAAIJ9hIdPgCNAAAuAAQKfzgAAxoACQkHHv0HAKMCABoACQkHHv0HAKMCABcAAQnIF/B8AEYAAAAA.Wieldblade:BAABLgAECn83AAMFAAkJsh1JIgBlAgAFAAkJsh1JIgBlAgADAAgJiBaqDQDPAQAAAA==.Wilsondk:BAAALgAECgEJAwAAAA==.Winslett:BAAALgADCgQJBAAAAA==.',
Wo='Wolfemoon:BAABLgAECn8UAAIUAAgJwwouagBWAQAUAAgJwwouagBWAQAAAA==.Worganlefey:BAAALgAECgMJBwABLgAECgkJSAAGAJMXAA==.',
Wr='Wrexd:BAABLgAECn8qAAIGAAgJCht+PgDVAQAGAAgJCht+PgDVAQAAAA==.',
Wu='Wunderbar:BAABLgAECn80AAMKAAkJHyC8BgDfAgAKAAkJHyC8BgDfAgAJAAgJWBmbHgA/AgAAAA==.',
Wy='Wyldfire:BAACLgAFFH8XAAMkAAUJYRd8GAApAQAkAAUJYRd8GAApAQANAAEJHgr0LwAxAAAuAAQKfy8AAyQACQleI/kLANgCACQACQleI/kLANgCACAAAwksEo2eAI4AAAAA.Wyndclaw:BAABLgAECn8WAAIeAAYJcBaNMACJAQAeAAYJcBaNMACJAQAAAA==.',
Xa='Xanith:BAABLgAECn8tAAIQAAgJehjyHADzAQAQAAgJehjyHADzAQAAAA==.',
Xe='Xebubble:BAAALgADCgEJAQABLgAECgEJAQAEAAAAAA==.Xemonk:BAAALgAECgEJAQAAAA==.',
Xi='Xia:BAAALgADCgYJBgAAAA==.',
Xr='Xroi:BAAALgAECgIJAgAAAA==.',
Ya='Yaganor:BAAALgADCgUJBgAAAA==.',
Ye='Yeto:BAAALgADCgYJBwAAAA==.',
Yi='Yia:BAAALgAECgQJCAABLgAECgUJEQAEAAAAAA==.Yilnara:BAABLgAECn8bAAISAAkJDgf9cwAfAQASAAkJDgf9cwAfAQAAAA==.',
Ys='Ysa:BAABLgAECn8eAAMXAAcJuCShEAB3AgAXAAcJuCShEAB3AgAeAAEJlA2UbAApAAAAAA==.',
Za='Zajindor:BAAALgADCgEJAQAAAA==.Zarathul:BAAALgADCgIJAgAAAA==.',
Ze='Zekkun:BAAALgAECgEJAQAAAA==.',
Zh='Zheria:BAAALgAECgQJBAAAAA==.',
Zi='Zirael:BAAALgADCgYJCgAAAA==.',
Zo='Zod:BAAALgAECgkJCQAAAA==.Zoganian:BAEALgAECgQJDQABLgAECgkJIgAYAAUhAA==.Zogula:BAEBLgAECn8iAAQYAAkJBSE4CgCuAgAYAAkJ0iA4CgCuAgAHAAQJXxbgOAAOAQAIAAEJaiMPWgBhAAAAAA==.',
Zu='Zu:BAAALgAECgQJDQAAAA==.',
Zy='Zynara:BAAALgAECgIJAgAAAA==.',
['År']='Årtemis:BAABLgAECn8xAAInAAgJwB33CwBXAgAnAAgJwB33CwBXAgAAAA==.',
['Æb']='Æbony:BAAALgADCgMJAwAAAA==.',
['Ïr']='Ïrini:BAAALgAECgIJAwABLgAECggJCwAEAAAAAA==.',
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
