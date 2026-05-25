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

local lookup = {'DemonHunter-Havoc','DemonHunter-Vengeance','Paladin-Protection','Unknown-Unknown','Paladin-Retribution','Warlock-Demonology','Priest-Shadow','Priest-Discipline','Shaman-Restoration','Shaman-Elemental','Evoker-Preservation','Shaman-Enhancement','Druid-Guardian','Rogue-Outlaw','Warrior-Fury','Warrior-Arms','DemonHunter-Devourer','Hunter-Marksmanship','Hunter-BeastMastery','Mage-Frost','Druid-Feral','Monk-Windwalker','Priest-Holy','Warlock-Destruction','Monk-Brewmaster','DeathKnight-Blood','DeathKnight-Frost','Evoker-Augmentation','DeathKnight-Unholy','Monk-Mistweaver','Mage-Arcane','Druid-Restoration','Warlock-Affliction','Evoker-Devastation','Rogue-Subtlety','Warrior-Protection','Druid-Balance','Paladin-Holy','Rogue-Assassination','Hunter-Survival','Mage-Fire',}
local provider = {region='US',realm='AzjolNerub',name='US',type='weekly',zone=46,date='2026-05-23',data={Ad='Adapt:BAAALgAECgMJCQAAAA==.Addy:BAABLgAECn8oAAMBAAkJlBoJCACCAgABAAkJlBoJCACCAgACAAEJQghYLgAnAAAAAA==.',
Ae='Aeonis:BAAALgAECgMJBwAAAA==.Aestian:BAABLgAECn8wAAIDAAgJLBvyDADIAQADAAgJLBvyDADIAQAAAA==.',
Ag='Agamesh:BAAALgADCgUJCQAAAA==.',
Ah='Ahoma:BAAALgADCgkJBgAAAA==.',
Ai='Ailysely:BAAALgADCgEJAQABLgAECgMJBwAEAAAAAA==.Airees:BAABLgAECn8iAAIFAAcJOx7oQQAfAgAFAAcJOx7oQQAfAgAAAA==.Aispere:BAAALgAECgMJAwAAAA==.',
Al='Alastria:BAAALgADCgcJBwAAAA==.Alektra:BAAALgADCgUJBwAAAA==.Alerzhulan:BAABLgAECn8aAAIGAAgJyQsgXwBsAQAGAAgJyQsgXwBsAQAAAA==.Allanquatre:BAAALgAECgUJBQAAAA==.Alledria:BAABLgAECn8aAAIFAAgJmhJpXwCSAQAFAAgJmhJpXwCSAQAAAA==.Allenaena:BAAALgAECgMJBgAAAA==.Alorely:BAABLgAECn8bAAMHAAgJ0A2HJgBvAQAHAAgJ0A2HJgBvAQAIAAUJqwomNQD7AAAAAA==.Altonas:BAAALgAECgMJAwAAAA==.',
Am='Amanara:BAAALgAECgMJBgAAAA==.Amillah:BAAALgAECgQJBgAAAA==.',
An='Anciientpaw:BAABLgAECn8iAAMJAAkJGyBlHQAvAgAJAAkJGyBlHQAvAgAKAAUJbBUzRgAwAQAAAA==.Andramalyus:BAABLgAECn8mAAIGAAcJsw37dAA6AQAGAAcJsw37dAA6AQAAAA==.Andrasomnium:BAAALgAECgIJAgAAAA==.Angbar:BAABLgAECn8uAAILAAgJTRaTCgARAgALAAgJTRaTCgARAgAAAA==.Anguirus:BAABLgAECn8oAAMKAAkJAAUgTQDQAAAKAAkJAAUgTQDQAAAMAAQJ4ACTMAAuAAAAAA==.Animà:BAAALgAECgYJDwAAAA==.Ankhnstein:BAAALgAECgQJBAAAAA==.Antoine:BAAALgAECgIJAgAAAA==.',
Ap='Apolloni:BAAALgAECgIJAgABLgAECgkJKgANAJYJAA==.Appynoxusrog:BAABLgAECn8cAAIOAAYJuhguBQCcAQAOAAYJuhguBQCcAQAAAA==.',
Aq='Aqulenas:BAAALgAFFAMJBAAAAA==.',
Ar='Arakhan:BAAALgAECgQJBAAAAA==.Arasaka:BAAALgAECgQJCAAAAA==.Arcadian:BAABLgAECn8xAAMPAAkJHB0RDACFAgAPAAkJHB0RDACFAgAQAAEJzAfURAAvAAAAAA==.Arcadiann:BAAALgAECgUJDQAAAA==.Arcadin:BAAALgAECgEJAgAAAA==.Arcoyflecha:BAAALgAECgYJBwAAAA==.Arextheelder:BAAALgAECgcJCwAAAA==.Ariais:BAAALgADCgcJBwAAAA==.Aridas:BAABLgAECn8dAAMRAAgJJBhuMwAsAgARAAgJJBhuMwAsAgABAAIJRQsGYABiAAABLgAECgkJIAAQAGsZAA==.Arikdeath:BAABLgAECn8hAAMSAAgJeAzhEQAXAQASAAcJTgzhEQAXAQATAAIJcwuGzQBoAAAAAA==.Armorscales:BAACLgAFFH8QAAIGAAQJuBjCNgA3AQAGAAQJuBjCNgA3AQAuAAQKfy0AAgYACQm/IVgQAPcCAAYACQm/IVgQAPcCAAAA.Arniix:BAAALgAECgEJAQABLgAECgQJDQAEAAAAAA==.Arnixskitty:BAAALgAECgEJAQABLgAECgQJDQAEAAAAAA==.Arntraz:BAAALgADCgkJMgAAAA==.Arçadia:BAAALgAECgMJAwAAAA==.',
As='Ashegen:BAAALgAECgQJBAAAAA==.Ashnikko:BAAALgAECgEJAQAAAA==.Ashtori:BAAALgADCgEJAgAAAA==.Asis:BAAALgAECgEJAQAAAA==.Astrine:BAACLgAFFH8RAAIUAAQJmBmEQwA/AQAUAAQJmBmEQwA/AQAuAAQKfysAAhQACQlJIAYiAOsCABQACQlJIAYiAOsCAAAA.',
Au='Auberon:BAABLgAECn8oAAIVAAkJ/xl6BgCSAgAVAAkJ/xl6BgCSAgAAAA==.Aufta:BAABLgAECn8mAAIWAAkJ9wUUMAAeAQAWAAkJ9wUUMAAeAQAAAA==.',
Az='Azdh:BAAALgAECgQJBgAAAA==.Azi:BAACLgAFFH8aAAISAAYJYSH7BgC0AQASAAYJYSH7BgC0AQAuAAQKfykAAhIACQkGIKUCAJ8CABIACQkGIKUCAJ8CAAAA.Azshanorel:BAAALgADCgcJBwAAAA==.Azunea:BAAALgAECgIJBwAAAA==.Azurite:BAAALgADCgkJEAAAAA==.',
Ba='Backpedal:BAAALgAECgcJEAAAAA==.Badankhadonk:BAACLgAFFH8SAAIJAAQJuCOREgCHAQAJAAQJuCOREgCHAQAuAAQKfy0AAgkACQl7JVICAF8DAAkACQl7JVICAF8DAAAA.Balen:BAABLgAECn8pAAIDAAgJ3hW+DQC5AQADAAgJ3hW+DQC5AQAAAA==.Bandrösh:BAAALgADCgMJAwAAAA==.Barradune:BAAALgADCgYJDAAAAA==.Baubles:BAAALgAECgMJAgAAAA==.',
Be='Belholy:BAABLgAECn8jAAIXAAgJAh7MCQCnAgAXAAgJAh7MCQCnAgAAAA==.Beliice:BAAALgADCgkJIAABLgAECggJIwAXAAIeAA==.Bellanei:BAAALgAECgEJBAAAAA==.Ben:BAAALgAECgEJAQAAAA==.Benafflockk:BAAALgADCggJCAAAAA==.Benefitdruid:BAAALgAECgEJAQAAAA==.Benilok:BAACLgAFFH8OAAMGAAQJ9x1VLgBNAQAGAAQJ9x1VLgBNAQAYAAEJ6hAZHQBLAAAuAAQKfysAAgYACQkcJSEMABkDAAYACQkcJSEMABkDAAAA.Bethgibbons:BAAALgADCgkJIAAAAA==.',
Bi='Bibimbap:BAAALgAECgEJAQAAAA==.Bigsuccubus:BAABLgAECn8VAAIYAAgJRw22DQA3AQAYAAgJRw22DQA3AQAAAA==.Biohazard:BAAALgADCgUJBQAAAA==.Bizël:BAAALgAECgYJDQAAAA==.',
Bl='Blackblood:BAABLgAECn8fAAIBAAgJhBXgEwC8AQABAAgJhBXgEwC8AQAAAA==.Blackclouds:BAAALgADCgkJCQAAAA==.Blackspiral:BAAALgADCgEJAQAAAA==.Bladestriker:BAAALgAECgIJAwAAAA==.Blindside:BAAALgAECgMJBgAAAA==.Bloodache:BAABLgAECn8VAAIRAAcJKSFgKQBcAgARAAcJKSFgKQBcAgAAAA==.Bloodkissed:BAAALgADCgUJBgABLgAECgkJNgAXAAIgAA==.Bluebuberry:BAAALgAECgQJBgAAAA==.Bluesaphire:BAAALgAECgIJAgABLgAECggJFQAJAP8ZAA==.Blux:BAAALgAECgQJCAAAAA==.',
Bo='Boil:BAABLgAECn8gAAIOAAgJYAeUDAAbAQAOAAgJYAeUDAAbAQAAAA==.Bonemarrow:BAAALgAECgQJEgAAAA==.Bournx:BAAALgADCggJCQAAAA==.Boysenbar:BAAALgADCgYJCAAAAA==.',
Br='Bradrenna:BAABLgAECn9FAAQCAAkJ/hcHBgA5AgACAAkJ/hcHBgA5AgABAAEJsRHsVQAzAAARAAEJpQHH9AAbAAAAAA==.Braké:BAABLgAECn8aAAIDAAgJNBwbCAAoAgADAAgJNBwbCAAoAgAAAA==.Breakthrough:BAABLgAECn8WAAIJAAYJpSKMGQBRAgAJAAYJpSKMGQBRAgAAAA==.Brenzull:BAAALgADCgYJCwAAAA==.Brewskies:BAABLgAECn8nAAIZAAcJDyUfCgB1AgAZAAcJDyUfCgB1AgABLgAECgkJGgAaAKEgAA==.Brewsli:BAAALgADCgIJAgABLgAECggJHAAbAJALAA==.Brightstar:BAAALgAECgcJEwAAAA==.Brokenaltar:BAABLgAECn8VAAMBAAYJNRheOQAdAQARAAYJgRFacwBLAQABAAUJCRpeOQAdAQAAAA==.Brownington:BAABLgAECn8ZAAMNAAcJViSSBgBgAgANAAcJViSSBgBgAgAVAAEJowqFPQAyAAAAAA==.Bruhilda:BAABLgAECn8ZAAIUAAgJ5ROuVQC+AQAUAAgJ5ROuVQC+AQAAAA==.Brymstone:BAAALgAECgQJBwAAAA==.Brynthebuff:BAAALgAECgEJAQAAAA==.Brìonik:BAACLgAFFH8bAAMGAAYJwh39GACaAQAGAAYJAxn9GACaAQAYAAMJoSSVCADNAAAuAAQKfyoAAxgACQkPJBgEABoCABgABgkoJRgEABoCAAYABQkeI2dkAF8BAAAA.',
Bu='Bufferfish:BAABLgAECn80AAIcAAkJUQxqJgCMAQAcAAkJUQxqJgCMAQAAAA==.',
Ca='Calinnea:BAAALgAECgcJDwABLgAECggJCwAEAAAAAA==.Cantheartitz:BAABLgAECn8UAAIUAAUJPxmBnQCbAQAUAAUJPxmBnQCbAQAAAA==.Catastrophe:BAABLgAECn8eAAIWAAgJVCE+CACeAgAWAAgJVCE+CACeAgAAAA==.',
Ce='Celira:BAAALgADCgMJAwAAAA==.Celthol:BAABLgAECn8VAAIRAAYJJBPbZQA1AQARAAYJJBPbZQA1AQAAAA==.',
Ch='Chelraani:BAABLgAECn8vAAIFAAgJ+CBuGACTAgAFAAgJ+CBuGACTAgAAAA==.Chiichard:BAAALgADCgYJCgAAAA==.Chipnuts:BAABLgAECn8bAAIWAAkJ8CTAAgBtAwAWAAkJ8CTAAgBtAwAAAA==.Chonchoo:BAAALgADCgEJAQAAAA==.Chosethebear:BAAALgADCgkJEAAAAA==.Chunkamonk:BAAALgADCgEJAQAAAA==.',
Ci='Cigar:BAAALgAECgMJAgABLgAFFAUJEAAdAGkbAA==.Cinderat:BAAALgADCgEJAQAAAA==.',
Cl='Clarabellax:BAAALgAECgQJBQAAAA==.Clarkkentt:BAAALgADCgcJDQAAAA==.Claymore:BAACLgAFFH8QAAIPAAUJCRf3EQBJAQAPAAUJCRf3EQBJAQAuAAQKfxUAAg8ACAkMGcscAGcCAA8ACAkMGcscAGcCAAAA.Clazzicola:BAACLgAFFH8OAAMeAAQJqQ8rHwD6AAAeAAQJqQ8rHwD6AAAWAAMJJgvADQCWAAAuAAQKfx8ABBYACQmbFmIeAOUBABYABwlYHGIeAOUBAB4ACAniEYomAH4BABkAAQlhA8uVAB8AAAAA.Cloudbeast:BAAALgAECgMJBAABLgAECgQJDQAEAAAAAA==.Clue:BAAALgADCgYJBgAAAA==.',
Co='Cocito:BAAALgAECgEJAwAAAA==.Commândment:BAAALgAECgMJBgAAAA==.Conjredcukee:BAABLgAECn8WAAIUAAcJ7AOYyQDdAAAUAAcJ7AOYyQDdAAAAAA==.Coo:BAAALgAECgQJBAABLgAECgUJBwAEAAAAAA==.Coogsayer:BAABLgAECn8UAAIHAAcJyh2aEQBxAgAHAAcJyh2aEQBxAgAAAA==.',
Cp='Cptncrush:BAABLgAECn8fAAMJAAgJBBpuIAAgAgAJAAgJBBpuIAAgAgAKAAMJoBcxWQCpAAAAAA==.',
Cr='Croquetica:BAAALgADCgMJBAAAAA==.Crossed:BAAALgADCgcJCwAAAA==.Crowshadow:BAAALgAECgUJDwAAAA==.',
Cy='Cylina:BAAALgADCgcJCAAAAA==.Cylore:BAAALgADCgcJBgAAAA==.Cypherrellik:BAAALgAECgMJAwABLgAECgkJHAABAIUQAA==.Cyther:BAACLgAFFH8fAAIPAAYJnCS4AgD4AQAPAAYJnCS4AgD4AQAuAAQKfykAAg8ACQmXIqwHAC4DAA8ACQmXIqwHAC4DAAAA.',
['Cÿ']='Cÿthera:BAABLgAECn8bAAIRAAkJ4BzDHAClAgARAAkJ4BzDHAClAgAAAA==.',
Da='Dakk:BAABLgAECn9KAAIdAAkJOiO0BgAoAwAdAAkJOiO0BgAoAwAAAA==.Daraghor:BAABLgAECn8bAAINAAkJoCIMAgAbAwANAAkJoCIMAgAbAwAAAA==.Darkdottie:BAAALgAECgQJBAAAAA==.Darkenstormy:BAAALgAECgYJDQAAAA==.Darlyndra:BAAALgADCgUJBQAAAA==.Darsae:BAAALgAECgQJDAAAAA==.Darthiono:BAAALgAECgEJAQAAAA==.Darthmaull:BAAALgADCgEJAQAAAA==.',
De='Deadlight:BAABLgAECn8wAAMdAAkJ+BH+QwDUAQAdAAkJZBH+QwDUAQAbAAEJYBLzKAA5AAAAAA==.Deathkillhun:BAAALgAECgQJBwAAAA==.Deathpooch:BAAALgAECgUJBwAAAA==.Deathshooter:BAAALgAECgcJAQAAAA==.Deavant:BAAALgADCgMJAwAAAA==.Deermon:BAAALgAECgYJCwAAAA==.Deet:BAAALgAECgUJBQAAAA==.Deforest:BAAALgADCgcJFgAAAA==.Deity:BAABLgAECn8pAAIPAAcJECN2EQBHAgAPAAcJECN2EQBHAgAAAA==.Demogon:BAAALgAECgQJBwAAAA==.Demondeano:BAABLgAECn8bAAIRAAkJAROZPgCtAQARAAkJAROZPgCtAQAAAA==.Demonllxll:BAAALgAECgYJBwAAAA==.Demonlxl:BAABLgAECn8VAAIKAAgJrAsoNAA7AQAKAAgJrAsoNAA7AQAAAA==.Demonx:BAABLgAECn8yAAIdAAkJkx1qFQCmAgAdAAkJkx1qFQCmAgAAAA==.Desolation:BAABLgAECn9AAAIfAAkJQCUkAABaAwAfAAkJQCUkAABaAwAAAA==.Despia:BAABLgAECn8qAAIXAAgJ4yRJAwBEAwAXAAgJ4yRJAwBEAwAAAA==.Devastacia:BAAALgADCgUJBQAAAA==.Deviarc:BAAALgAECgQJBAAAAA==.',
Dh='Dharkon:BAAALgAECgIJBAAAAA==.',
Di='Dicot:BAABLgAECn8pAAIgAAgJEhRtKwDaAQAgAAgJEhRtKwDaAQAAAA==.',
Dj='Djpallyd:BAAALgAECgkJEAAAAA==.',
Do='Doinks:BAAALgAECgIJAgAAAA==.Domilthri:BAABLgAECn87AAMGAAgJ/Q7PVwCAAQAGAAgJ/Q7PVwCAAQAhAAYJ8gVDEAAqAQAAAA==.Dotdaddy:BAAALgAECgQJBwABLgAECggJCwAEAAAAAA==.',
Dr='Dracoly:BAAALgAECggJEgAAAA==.Draconu:BAACLgAFFH8bAAIcAAUJSR25FQBdAQAcAAUJSR25FQBdAQAuAAQKfyIAAxwACQk4HzoKAJgCABwACQk4HzoKAJgCAAsAAQmaAX1OACIAAAAA.Draenyth:BAAALgAECgcJEQAAAA==.Dragoncurry:BAABLgAECn8WAAILAAYJIgYTIwCvAAALAAYJIgYTIwCvAAAAAA==.Dragonmite:BAAALgAECgEJAQAAAA==.Drakka:BAAALgADCgkJDgABLgAECgUJDQAEAAAAAA==.Draktyr:BAACLgAFFH8GAAIPAAMJtRZeFgCyAAAPAAMJtRZeFgCyAAAuAAQKfyQAAg8ACQn2HncJABYDAA8ACQn2HncJABYDAAAA.Draxoths:BAAALgAECgMJBQABLgAFFAMJBwAgADkZAA==.Dropeadita:BAAALgAECgQJBAAAAA==.Droptop:BAAALgADCgcJCAAAAA==.',
Du='Dumbsht:BAABLgAECn8ZAAMSAAgJ6xbDMQCpAQASAAcJ6xXDMQCpAQATAAYJVhHjXQBOAQAAAA==.',
Ea='Easystreet:BAAALgAECgIJAwAAAA==.',
Ef='Effluv:BAAALgADCgcJDgAAAA==.',
El='Elandir:BAAALgADCgQJAQAAAA==.Elanora:BAAALgAECgYJCQAAAA==.Elbrookel:BAAALgAECgIJAgAAAA==.Eleshnorn:BAAALgAECgQJCgAAAA==.Eliza:BAAALgADCgkJCQAAAA==.Ellismom:BAABLgAECn84AAIdAAkJ1SBcDgDaAgAdAAkJ1SBcDgDaAgAAAA==.Elvea:BAABLgAECn8kAAMcAAgJjRqtFQALAgAcAAgJjRqtFQALAgAiAAEJ9QoWQgArAAABLgAFFAUJFQAjAOMWAA==.',
Em='Emeralddemon:BAAALgAECgMJBgAAAA==.Emeraldshade:BAAALgADCgcJDwABLgAECgMJBgAEAAAAAA==.Emeråld:BAAALgAECgUJBgAAAA==.',
En='Enamorada:BAAALgAECgIJAgABLgAECggJFQAJAP8ZAA==.',
Er='Ereithelda:BAACLgAFFH8bAAIeAAYJHxV/DwCgAQAeAAYJHxV/DwCgAQAuAAQKfyYAAh4ACAm2IhcHAOkCAB4ACAm2IhcHAOkCAAAA.Ericka:BAAALgADCgYJDQAAAA==.Erreya:BAAALgADCgEJAQAAAA==.',
Es='Esma:BAAALgADCgkJCQAAAA==.',
Ev='Evox:BAAALgAECgcJEAAAAA==.',
Ey='Eyris:BAAALgADCgMJAwAAAA==.Eyrndor:BAAALgADCgIJAwAAAA==.',
Fa='Faacee:BAAALgAECgIJAgAAAA==.Falgar:BAAALgADCgYJBgAAAA==.Fann:BAABLgAECn8cAAIgAAgJiwSAagDUAAAgAAgJiwSAagDUAAAAAA==.Fawn:BAAALgAECgIJBAAAAA==.Faytl:BAAALgAECgMJAwAAAA==.',
Fe='Felbubu:BAABLgAECn8jAAQCAAkJlyIeBACAAgACAAkJLCIeBACAAgABAAYJOyAmIgCrAQARAAMJNRycjwDXAAAAAA==.Femboy:BAAALgAECgUJDgAAAA==.Fewz:BAACLgAFFH8KAAIUAAQJiRJwbADdAAAUAAQJiRJwbADdAAAuAAQKfyQAAhQACQnjIYAVAL4CABQACQnjIYAVAL4CAAAA.',
Fi='Fireybuns:BAAALgAECgEJAwAAAA==.',
Fl='Flakiron:BAACLgAFFH8VAAIkAAQJ2RYjDgAaAQAkAAQJ2RYjDgAaAQAuAAQKfy0AAiQACQkjHJkLAFQCACQACQkjHJkLAFQCAAAA.Flakov:BAAALgAECgIJAgABLgAFFAQJFQAkANkWAA==.Flaktop:BAAALgAECgUJCAABLgAFFAQJFQAkANkWAA==.Fler:BAAALgAECgQJCAAAAA==.',
Fo='Forbacon:BAABLgAECn8cAAMbAAgJkAuBEgAKAQAbAAgJJguBEgAKAQAdAAYJgQkpsgDnAAAAAA==.Force:BAABLgAECn8eAAQbAAgJ6AmCFQDlAAAbAAYJRgyCFQDlAAAdAAUJEASo5QCZAAAaAAEJ+wTGVAAdAAAAAA==.Fornost:BAAALgADCgkJDgAAAA==.Fourdragon:BAAALgADCgQJBAABLgAECggJFwAKACQXAA==.Fouris:BAABLgAECn8XAAIKAAgJJBeIIgCkAQAKAAgJJBeIIgCkAQAAAA==.',
Fr='Fremosth:BAAALgADCgMJAwAAAA==.Fretman:BAAALgADCgcJCQAAAA==.Fridgie:BAACLgAFFH8YAAITAAUJZhkzBABdAQATAAUJZhkzBABdAQAuAAQKfyMAAhMACQm6Im0PAMACABMACQm6Im0PAMACAAAA.Froline:BAAALgAECgMJAwAAAA==.Frostreaper:BAAALgAECgIJAgAAAA==.Frozenflyer:BAAALgAECgUJEAAAAA==.Frozenturtle:BAABLgAECn8fAAIaAAgJ4xyQCwAmAgAaAAgJ4xyQCwAmAgAAAA==.',
Ft='Ftwiamtank:BAAALgAECgYJCgAAAA==.',
Fu='Fuoco:BAAALgAECgkJCgAAAA==.',
Ga='Gabriél:BAAALgAECgYJCQAAAA==.Garcutt:BAACLgAFFH8cAAIUAAYJiRieIACgAQAUAAYJiRieIACgAQAuAAQKfysAAhQACQm0HbwiAHYCABQACQm0HbwiAHYCAAAA.Gardon:BAAALgAECgQJBAAAAA==.Gaurdinn:BAABLgAECn8uAAQcAAgJMBN8KQB4AQAcAAgJrhJ8KQB4AQAiAAYJfxAfDgALAQALAAIJagKHMwA3AAABLgAECgkJCgAEAAAAAA==.',
Ge='Gebuss:BAAALgADCgQJBAAAAA==.Generickmonk:BAACLgAFFH8TAAIWAAUJrRq6CwA+AQAWAAUJrRq6CwA+AQAuAAQKfysAAhYACQlDIv4IAOgCABYACQlDIv4IAOgCAAAA.Gensis:BAAALgADCgYJBgAAAA==.Geomatic:BAAALgAECgEJAQAAAA==.Gethsemåne:BAAALgADCgMJBQAAAA==.',
Gi='Giovannucci:BAAALgAECgEJAgAAAA==.Gitan:BAAALgADCgQJBQAAAA==.',
Gl='Gladstone:BAAALgAECgYJDQAAAA==.',
Go='Gomlvirgin:BAAALgADCgYJBgABLgAECggJIgAGAHcUAA==.',
Gr='Gracehimeûwû:BAABLgAFFH8FAAIZAAIJahGrPACGAAAZAAIJahGrPACGAAAAAA==.Grampsie:BAAALgAECgUJBwAAAA==.Grayeyes:BAAALgAECgMJAwAAAA==.Greenngoblin:BAAALgADCgEJAQAAAA==.Grimmlie:BAAALgADCgUJBQAAAA==.Grinzler:BAAALgADCgIJAgAAAA==.Grumpybear:BAAALgADCggJDwAAAA==.Grumpykat:BAAALgAECggJEgAAAA==.Grumpypros:BAAALgADCgUJBQAAAA==.',
Gt='Gtatedk:BAAALgAFFAEJAQAAAA==.',
Gu='Guino:BAAALgAECgMJBAAAAA==.Guinodruid:BAAALgADCgcJDgAAAA==.',
Gw='Gwenelly:BAAALgAECgEJAQAAAA==.',
Ha='Hamncheeks:BAAALgAECgEJAQAAAA==.Haptism:BAAALgADCgcJBwAAAA==.Hardeesdelux:BAAALgADCgcJDAABLgAECgQJDQAEAAAAAA==.Hardnarples:BAAALgADCgEJAQAAAA==.Hayzerade:BAAALgAECgYJCAAAAA==.Hazis:BAABLgAECn8rAAIaAAkJEyEbCACkAgAaAAkJEyEbCACkAgAAAA==.',
Hi='Hippiecritz:BAAALgADCgYJBwAAAA==.Hitokiri:BAAALgADCgMJAwAAAA==.',
Ho='Holy:BAACLgAFFH8VAAIDAAQJTQlnCADDAAADAAQJTQlnCADDAAAuAAQKfywAAgMACQmkFvMQALcBAAMACQmkFvMQALcBAAAA.Holydad:BAACLgAFFH8FAAIDAAQJzA90CQCuAAADAAQJzA90CQCuAAAuAAQKfywAAgMACAkHINQHAC8CAAMACAkHINQHAC8CAAAA.Holydust:BAAALgAECgcJEQAAAA==.Holymoki:BAAALgADCgYJCgAAAA==.Holymoliie:BAAALgADCgEJAQAAAA==.Holyroundie:BAABLgAECn9GAAIXAAkJbw5FIgCOAQAXAAkJbw5FIgCOAQAAAA==.Holyshock:BAACLgAFFH8fAAIFAAYJ9x9YCgDCAQAFAAYJ9x9YCgDCAQAuAAQKfykAAgUACQlkJRgFADkDAAUACQlkJRgFADkDAAAA.Holystax:BAAALgAECgEJAgAAAA==.Honeybutter:BAACLgAFFH8WAAMQAAYJmSMgAgAdAgAQAAYJmSMgAgAdAgAPAAEJCAkTIgBRAAAuAAQKfzsAAxAACQkzJncAAHoDABAACQkzJncAAHoDAA8ABwmLHtAjADgCAAAA.Hordebreaker:BAAALgAECgYJEQAAAA==.Hotflash:BAAALgAECgEJAQAAAA==.',
Hu='Huukend:BAABLgAECn85AAITAAkJbSL5BwD7AgATAAkJbSL5BwD7AgAAAA==.',
Ib='Iblindbenice:BAAALgAECgYJBgAAAA==.',
Ic='Icebabyman:BAABLgAECn8fAAIUAAgJER7kOACSAgAUAAgJER7kOACSAgAAAA==.',
In='Inanitas:BAAALgADCgcJBwAAAA==.Ineffectual:BAABLgAECn8fAAIJAAgJvBMeMgC9AQAJAAgJvBMeMgC9AQAAAA==.',
Ir='Irukox:BAAALgAECgYJDQAAAA==.',
It='Itty:BAAALgADCgcJBwAAAA==.',
Ja='Jadaveon:BAAALgADCgEJAQAAAA==.Jagger:BAAALgADCgcJCQAAAA==.Jalene:BAAALgAECgYJDwAAAA==.Janewayy:BAABLgAECn8yAAIRAAkJGA1qUAByAQARAAkJGA1qUAByAQAAAA==.Jazmean:BAAALgAECgQJBQAAAA==.',
Je='Jeks:BAAALgADCgcJBwABLgAFFAYJHgAJABEbAA==.Jemma:BAABLgAECn8kAAIYAAkJBhB+BwCtAQAYAAkJBhB+BwCtAQAAAA==.Jettadari:BAACLgAFFH8QAAIRAAYJrBYXEABNAQARAAYJrBYXEABNAQAuAAQKfyYAAxEACQlsIO0WAM0CABEACQlsIO0WAM0CAAIAAQlADrUrADAAAAAA.Jettadin:BAABLgAECn8aAAIFAAgJ9yGnDwARAwAFAAgJ9yGnDwARAwABLgAFFAYJEAARAKwWAA==.Jettathyr:BAAALgAECgcJDQABLgAFFAYJEAARAKwWAA==.',
Ju='Jubba:BAABLgAECn8bAAIUAAgJyRT5VgC7AQAUAAgJyRT5VgC7AQAAAA==.Juderius:BAAALgADCgQJBAABLgAECgMJAwAEAAAAAA==.Junk:BAABLgAECn8aAAIaAAkJoSDKAwDgAgAaAAkJoSDKAwDgAgAAAA==.',
['Jë']='Jëks:BAACLgAFFH8eAAIJAAYJERv7CQDbAQAJAAYJERv7CQDbAQAuAAQKfykAAwkACQlhJXEDAEEDAAkACQlhJXEDAEEDAAwAAgkvDtAmAGIAAAAA.',
Ka='Kaghroxxar:BAAALgADCgYJDgAAAA==.Kahea:BAAALgAECgQJBAAAAA==.Kaitou:BAABLgAECn82AAMVAAkJMSIhAgDvAgAVAAkJMSIhAgDvAgAlAAEJrQ4beAAwAAAAAA==.Kalamiti:BAAALgAECggJEAAAAA==.Kallar:BAABLgAECn82AAMXAAkJAiC0BAAXAwAXAAkJAiC0BAAXAwAHAAIJUQalYQBUAAAAAA==.Karesh:BAAALgAECgQJBAAAAA==.Kayeera:BAAALgAECgYJEwAAAA==.Kayha:BAAALgADCgYJCAAAAA==.Kaylrandi:BAAALgADCgcJFgAAAA==.Kaztiel:BAAALgAECgIJAgAAAA==.',
Ke='Keadon:BAAALgAFFAEJAQAAAA==.Kearza:BAAALgAECgEJAQAAAA==.Keeper:BAAALgADCgMJAwABLgAECgcJKQAPABAjAA==.Keh:BAAALgADCgkJCQAAAA==.Keiyona:BAAALgAECgYJBgABLgAECggJGgAFAJQeAA==.Kennethv:BAAALgAECgYJCAAAAA==.Kenze:BAAALgAECgEJAQAAAA==.Kethra:BAAALgADCggJEgAAAA==.Kev:BAAALgAECgcJBwAAAA==.',
Kh='Khel:BAAALgADCgcJBwAAAA==.Khibanee:BAAALgADCgQJBAAAAA==.Khiell:BAACLgAFFH8LAAIPAAQJgQ+8HwAIAQAPAAQJgQ+8HwAIAQAuAAQKfyIAAg8ACQkmGnsUACgCAA8ACQkmGnsUACgCAAAA.',
Ki='Kilyse:BAAALgADCgYJBgAAAA==.Kinigit:BAAALgAECgUJCAABLgAFFAQJFQAlAGEXAA==.Kirïtö:BAAALgAECgUJCwAAAA==.Kitarah:BAEALgAECgIJAgABLgAECgkJEAAEAAAAAA==.Kitarazen:BAEALgAECgkJEAAAAA==.Kizli:BAAALgADCgUJBQAAAA==.',
Kn='Knoway:BAAALgADCgUJBQAAAA==.',
Ko='Kokushimosu:BAAALgAECgYJDgAAAA==.Koo:BAAALgAECgUJBwAAAA==.Koviel:BAAALgADCgcJBwAAAA==.',
Kr='Krátos:BAABLgAECn8gAAMQAAkJaxmFBwBYAgAQAAkJ9RiFBwBYAgAPAAgJaRFTKQCPAQAAAA==.',
Ks='Ksper:BAAALgAECgcJEgAAAA==.',
Ku='Kukalak:BAABLgAECn8YAAIkAAgJ7BvSEQDrAQAkAAgJ7BvSEQDrAQAAAA==.Kuranaa:BAAALgADCgkJIQABLgAECgMJAwAEAAAAAA==.Kurulak:BAABLgAECn8kAAIRAAgJxxE7TgB4AQARAAgJxxE7TgB4AQAAAA==.',
Ky='Kymru:BAAALgADCgcJDQAAAA==.',
['Ké']='Kénnéth:BAAALgAECgYJDgAAAA==.',
La='Lacerveza:BAAALgAECgIJBQAAAA==.Lahyanhou:BAABLgAECn8tAAISAAkJLQhuDgBNAQASAAkJLQhuDgBNAQAAAA==.Lalalalala:BAAALgAECgcJCgAAAA==.Lalin:BAAALgAECgEJBQAAAA==.Larkwyn:BAAALgAECgQJBAABLgAFFAMJCQAGAK8QAA==.Laylah:BAAALgADCgYJBAAAAA==.',
Le='Lebrand:BAAALgAECgEJAQAAAA==.Leriope:BAABLgAECn8/AAIGAAkJTQ4zQwC6AQAGAAkJTQ4zQwC6AQAAAA==.Leàf:BAAALgAECgUJBQAAAA==.',
Li='Lichfiend:BAAALgADCgEJAQAAAA==.Lightbeer:BAAALgAECgYJBwAAAA==.Lihplock:BAAALgAECgQJCAABLgAFFAMJEAAPAKglAA==.Lilandri:BAAALgADCgkJCQAAAA==.Lildragonboi:BAAALgADCgUJBQAAAA==.Lilem:BAAALgADCgcJEgAAAA==.Lilpooch:BAAALgAECgUJBQAAAA==.Listenlinda:BAAALgAECgIJAgAAAA==.Lithariel:BAAALgADCgkJCAAAAA==.Littlemerald:BAAALgAECgUJCwAAAA==.',
Lj='Lj:BAABLgAECn84AAImAAkJah4VCADlAgAmAAkJah4VCADlAgAAAA==.',
Lo='Localsingles:BAAALgADCgcJBwAAAA==.Lorath:BAAALgADCgEJAQAAAA==.Lovecrafft:BAAALgAECgMJBQAAAA==.',
Lu='Lu:BAABLgAFFH8HAAMaAAMJzxeELgA2AAAdAAIJzxdHoACXAAAaAAIJtA6ELgA2AAABLgAFFAQJDgAeAKkPAA==.Lucinà:BAABLgAECn8+AAQFAAkJeSJREADKAgAFAAgJ8CNREADKAgAmAAkJQR+TDAC1AgADAAUJkB1pFwA1AQAAAA==.Lusande:BAAALgAECgQJBgAAAA==.Luxure:BAAALgAECgYJBgAAAA==.Luxùria:BAAALgAECgEJAQAAAA==.',
Ly='Lyndall:BAAALgAECgQJBgAAAA==.',
Ma='Machamp:BAAALgAECgEJAQAAAA==.Madammìm:BAAALgADCgEJAQAAAA==.Maegan:BAAALgAECgYJDwAAAA==.Maewyn:BAAALgAECgEJAgAAAA==.Mager:BAAALgAECgUJCgAAAA==.Magerhunter:BAAALgAECgIJAgAAAA==.Magolock:BAAALgAECgQJDAAAAA==.Mahll:BAAALgAECgMJAwAAAA==.Maidrim:BAACLgAFFH8XAAInAAYJbRn6AADMAQAnAAYJbRn6AADMAQAuAAQKfx8AAicACQmrIfICALICACcACQmrIfICALICAAAA.Makavelli:BAAALgADCgEJAQAAAA==.Mamajumbo:BAABLgAECn8WAAITAAcJKBjEQwCqAQATAAcJKBjEQwCqAQAAAA==.Marage:BAAALgADCgEJAQAAAA==.Marellias:BAAALgAECgMJBAABLgAECggJJwAFADokAA==.Marikel:BAAALgAECgQJCAAAAA==.Markwel:BAAALgAECgIJAgAAAA==.Marrack:BAAALgAECgYJDQAAAA==.',
Me='Melador:BAAALgADCgIJAgAAAA==.Meletha:BAAALgAECgYJDwAAAA==.Melpuis:BAAALgAECgEJAgAAAA==.Metahorfasis:BAAALgAECgMJAwAAAA==.',
Mi='Michaelken:BAABLgAECn8eAAImAAgJsRiCFgAvAgAmAAgJsRiCFgAvAgAAAA==.Mierín:BAAALgADCgYJBgAAAA==.Migrains:BAABLgAECn9AAAIDAAkJOCQ8AQAqAwADAAkJOCQ8AQAqAwAAAA==.Mineo:BAAALgAECgYJBwAAAA==.Mirâjâne:BAAALgAECgEJAQAAAA==.Miskaabin:BAABLgAECn8kAAMFAAcJMgy9kQAuAQAFAAcJEQy9kQAuAQADAAUJogpJLACPAAAAAA==.Miststress:BAAALgAECgcJCAAAAA==.',
Mo='Mobal:BAABLgAECn8yAAMJAAkJAh3nFAB3AgAJAAgJjx3nFAB3AgAKAAQJxggDZQCDAAAAAA==.Modarku:BAAALgADCgQJBAAAAA==.Mojogreens:BAAALgAECgYJEQAAAA==.Montydh:BAAALgAECgEJAQAAAA==.Moonblades:BAAALgADCgUJBQAAAA==.Moonpetals:BAAALgAECgEJAgAAAA==.Moonrush:BAAALgAECgMJCAAAAA==.Mortiis:BAAALgAECgYJEwAAAA==.Motako:BAABLgAECn8gAAIJAAcJRCCfFQBoAgAJAAcJRCCfFQBoAgAAAA==.',
Mp='Mpd:BAAALgAECgcJDAAAAA==.',
My='Mybizël:BAABLgAECn8pAAITAAcJwR7oIABAAgATAAcJwR7oIABAAgAAAA==.Myrlifax:BAAALgADCgEJAQABLgAECgUJDQAEAAAAAA==.Mystique:BAAALgAECggJEwAAAA==.Mythdaraghma:BAAALgAECgUJCgAAAA==.',
['Má']='Máximo:BAAALgAECgYJEAAAAA==.',
['Mí']='Míerin:BAAALgAECgQJBAAAAA==.Míerín:BAACLgAFFH8RAAIoAAQJnRxpCgBYAQAoAAQJnRxpCgBYAQAuAAQKfzEAAygACQnBJZgBAC0DACgACQnBJZgBAC0DABMABAm+G0NgAEcBAAAA.',
Na='Naama:BAAALgADCggJFwAAAA==.Nadaar:BAABLgAECn8bAAIfAAgJWhmVAgAFAgAfAAgJWhmVAgAFAgAAAA==.Naelih:BAABLgAECn8oAAISAAgJFg54DQBfAQASAAgJFg54DQBfAQAAAA==.Naharuk:BAAALgADCgMJAwAAAA==.Natholomas:BAAALgADCgQJBAAAAA==.Natlès:BAAALgAECggJCwAAAA==.Nattwenty:BAAALgAECgQJBAAAAA==.Nazeer:BAAALgADCgcJBwABLgAFFAQJBgAgACYEAA==.Nazgrim:BAACLgAFFH8GAAIgAAQJJgRlLgDYAAAgAAQJJgRlLgDYAAAuAAQKfzkAAiAACAkbFlsvAO8BACAACAkbFlsvAO8BAAAA.',
Ne='Necronu:BAABLgAFFH8HAAIdAAIJsBN5ngCZAAAdAAIJsBN5ngCZAAABLgAFFAUJGwAcAEkdAA==.',
Ni='Nikkolos:BAABLgAECn8XAAIBAAcJtAmnKAD8AAABAAcJtAmnKAD8AAAAAA==.Ninjastax:BAAALgAECgEJAgAAAA==.Nissie:BAAALgAECgEJAQAAAA==.Nitazendezot:BAAALgAECgEJAgABLgAFFAQJCgAdAOIPAA==.',
No='Nogusta:BAACLgAFFH8XAAIPAAYJNxySBwCWAQAPAAYJNxySBwCWAQAuAAQKfykAAg8ACQloH48IALkCAA8ACQloH48IALkCAAAA.Norberta:BAAALgAECgcJEwAAAA==.Nossanir:BAAALgAECgIJAgAAAA==.Nossellia:BAAALgAECgQJBwAAAA==.',
Nu='Nurana:BAAALgADCgEJAQAAAA==.',
Ny='Nycecritz:BAAALgAECgEJAQAAAA==.',
Od='Odor:BAAALgAECgQJBgAAAA==.',
Ol='Oldie:BAAALgAECgIJAgAAAA==.Olielno:BAAALgADCgMJAwAAAA==.',
On='Onlyshams:BAABLgAECn8hAAIJAAgJtBgvGQBNAgAJAAgJtBgvGQBNAgAAAA==.Onlytides:BAEBLgAECn8dAAMJAAkJ2SPlBwD2AgAJAAkJ2SPlBwD2AgAKAAcJXRiAHwAUAgABLgAFFAYJHAAgABkeAA==.Onubis:BAACLgAFFH8QAAMTAAUJriFKFABvAQATAAUJriFKFABvAQAoAAIJ5yC1GwC5AAAuAAQKfx8ABBMACQmaHw8MAOECABMACQmOHw8MAOECABIABgnGHdk0AJcBACgAAQmkI6lIAF8AAAEuAAUUBQkbABwASR0A.Onulock:BAAALgAECgYJCgABLgAFFAUJGwAcAEkdAA==.Onux:BAABLgAFFH8QAAIRAAUJHRx2IQBiAQARAAUJHRx2IQBiAQABLgAFFAUJGwAcAEkdAA==.',
Op='Opgarbage:BAAALgAECgQJCwAAAA==.',
Ou='Oukei:BAAALgAECgcJEgABLgAFFAUJEQAEAAAAAQ==.Oumura:BAAALgAECgYJDgAAAA==.',
Ov='Overlordainz:BAAALgAECgUJDgAAAA==.',
Pa='Paarthürnax:BAAALgAECgYJDAAAAA==.Padamee:BAAALgAECgQJBwAAAA==.Paganini:BAAALgAECgQJBAABLgAECggJGwATALEbAA==.Pallyoop:BAABLgAECn8WAAImAAcJMg/ISgDmAAAmAAcJMg/ISgDmAAAAAA==.Pandaa:BAAALgAECgEJAQAAAA==.Papapaw:BAAALgAECgQJBgAAAA==.Pathator:BAAALgAECgEJAQABLgAECggJEAAEAAAAAA==.Patherion:BAAALgADCgEJAQABLgAECggJEAAEAAAAAA==.Patholans:BAAALgAECggJEAAAAA==.Pathology:BAAALgAECgMJAwABLgAECggJEAAEAAAAAA==.Paxman:BAAALgAECgMJAwAAAA==.',
Pe='Peanits:BAAALgAECgQJCwABLgAECgkJIwACAJciAA==.Peanutsuckr:BAACLgAFFH8fAAIaAAYJjiNZBAD2AQAaAAYJjiNZBAD2AQAuAAQKfykAAhoACQnGJTQBAEQDABoACQnGJTQBAEQDAAAA.Pearserve:BAAALgADCgYJBgABLgAECggJFAAKANoPAA==.',
Ph='Phantöm:BAAALgAECgQJDAAAAA==.Phosphate:BAABLgAECn8QAAIRAAYJNxKvbgBYAQARAAYJNxKvbgBYAQAAAA==.',
Pi='Piccolo:BAAALgAECgQJBgAAAA==.Pingg:BAAALgAECgQJBQAAAA==.Pinkeye:BAAALgAECgQJBAAAAA==.Pippafan:BAAALgAECgEJAQABLgAECgEJAwAEAAAAAA==.',
Pl='Placcid:BAABLgAECn8xAAITAAkJuBvIFwBvAgATAAkJuBvIFwBvAgAAAA==.Planknstein:BAAALgADCgMJAwAAAA==.Playdohh:BAAALgAECgcJCQAAAA==.Plutonia:BAAALgAECgMJBwAAAA==.',
Po='Pockett:BAABLgAECn8ZAAMKAAcJTw3uPQAMAQAMAAUJBQnnGwAMAQAKAAcJPQ3uPQAMAQAAAA==.Powrwordgoat:BAACLgAFFH8IAAIIAAMJrwkRJgDPAAAIAAMJrwkRJgDPAAAuAAQKfy0AAggACAllE3QbAMYBAAgACAllE3QbAMYBAAAA.',
Pr='Prestoh:BAABLgAECn8iAAIKAAcJ2hO1NAA4AQAKAAcJ2hO1NAA4AQAAAA==.Prismclaw:BAABLgAECn84AAIUAAkJ+A5JTADaAQAUAAkJ+A5JTADaAQAAAA==.Prisoner:BAAALgAECgEJAwAAAA==.Processing:BAAALgAECgYJBgAAAA==.',
Ps='Pseudoruski:BAAALgADCgMJAwAAAA==.',
Pu='Purplehaze:BAAALgAECgQJBAAAAA==.',
Pv='Pvlolz:BAABLgAECn8ZAAIXAAkJ3QpDMACAAQAXAAkJ3QpDMACAAQAAAA==.',
Pw='Pwnstarz:BAAALgAECgUJBQAAAA==.',
Qa='Qaharn:BAAALgAECgQJBwAAAA==.',
Qp='Qplus:BAABLgAECn8eAAITAAgJFQm7XgBcAQATAAgJFQm7XgBcAQAAAA==.',
Qu='Quackadilly:BAAALgADCgcJCAAAAA==.Quaenie:BAABLgAECn8dAAIXAAgJ+xaEGADhAQAXAAgJ+xaEGADhAQAAAA==.Quintin:BAAALgAECgYJDQAAAA==.',
Ra='Raged:BAAALgAECgUJCgAAAA==.Ragegauge:BAAALgADCgIJAgAAAA==.Ragetotem:BAABLgAECn8gAAIKAAYJmRwgKADSAQAKAAYJmRwgKADSAQAAAA==.Ragewarg:BAAALgAECgcJDAAAAA==.Ragnashock:BAAALgAECgQJBgAAAA==.Ralvarr:BAABLgAECn8aAAIeAAgJIBimGwDbAQAeAAgJIBimGwDbAQAAAA==.Raptorjésus:BAAALgADCgcJCwAAAA==.Rastik:BAAALgADCgIJAgAAAA==.Rathaes:BAAALgADCgMJAwAAAA==.Ravenstryke:BAAALgAECgEJAQAAAA==.Raylea:BAAALgADCgcJBwAAAA==.Rayleigh:BAAALgAECgYJCgABLgAECgUJCwAEAAAAAA==.Razzgix:BAAALgAECgUJBgAAAA==.',
Re='Redchord:BAAALgADCgUJDAAAAA==.Regidør:BAABLgAECn8ZAAMmAAgJ/CBcCADoAgAmAAgJ/CBcCADoAgAFAAYJxx0XYQDBAQAAAA==.Relik:BAABLgAECn8fAAIkAAgJ4QsHHQAjAQAkAAgJ4QsHHQAjAQAAAA==.Resith:BAAALgAECgYJCAAAAA==.',
Rh='Rhaelia:BAABLgAECn8ZAAIFAAcJFQk3nwAXAQAFAAcJFQk3nwAXAQAAAA==.Rhaspus:BAAALgADCgQJBAAAAA==.',
Ri='Rilliccine:BAAALgADCgkJCwAAAA==.Rillinetti:BAABLgAECn8aAAIGAAgJIRIeTwCXAQAGAAgJIRIeTwCXAQAAAA==.Rillini:BAAALgADCgcJBwAAAA==.Rilliti:BAAALgAECgYJCgAAAA==.',
Ro='Rondon:BAABLgAECn8tAAITAAgJsCUdCAD5AgATAAgJsCUdCAD5AgAAAA==.Rookdh:BAACLgAFFH8MAAMBAAUJvQYuDwD3AAABAAQJUQQuDwD3AAARAAUJogb9RADrAAAuAAQKfykAAxEACQnkFv9LAIABABEACAk+GP9LAIABAAEABwkyFucsAGMBAAAA.Rorcia:BAAALgADCgcJFAAAAA==.Rosey:BAABLgAECn8nAAIFAAgJXBJ6VQCrAQAFAAgJXBJ6VQCrAQAAAA==.Rotmaxxer:BAAALgAECgEJAQAAAA==.Roxania:BAAALgADCgYJBgAAAA==.Royale:BAAALgADCgUJBQAAAA==.',
Ru='Rudyeightbal:BAABLgAECn8bAAMGAAgJCQzmhQAZAQAGAAYJhw3mhQAZAQAYAAIJFQNkOwAgAAAAAA==.Ruedons:BAAALgAECgIJAgAAAA==.Rugsalon:BAACLgAFFH8IAAIUAAMJCwncbwDUAAAUAAMJCwncbwDUAAAuAAQKfycAAhQACQn1HPM0AJ8CABQACQn1HPM0AJ8CAAAA.Rustedbarrel:BAACLgAFFH8IAAIZAAMJqwujMQDAAAAZAAMJqwujMQDAAAAuAAQKfxsAAhkACQmnE3YhAPYBABkACQmnE3YhAPYBAAAA.',
Ry='Ryptar:BAAALgADCgkJHAAAAA==.',
['Ré']='Réxxar:BAABLgAECn8cAAINAAcJPRTbDQClAQANAAcJPRTbDQClAQAAAA==.',
Sa='Saelyres:BAABLgAECn8gAAMCAAgJxx1rBABQAgACAAgJxx1rBABQAgABAAEJ1wNHegApAAAAAA==.Sagesse:BAAALgADCgYJBgAAAA==.Saikye:BAAALgAECgEJAQAAAA==.Sairu:BAAALgADCgEJAQAAAA==.Saisera:BAAALgAECgYJDAAAAA==.Samistraza:BAAALgADCgEJAQAAAA==.Sammy:BAABLgAECn8fAAIFAAgJjgk9jgA0AQAFAAgJjgk9jgA0AQAAAA==.Santaclaaws:BAACLgAFFH8PAAIRAAQJXxvZJgBLAQARAAQJXxvZJgBLAQAuAAQKfzUABBEACQmkIg4QAKYCABEACQmkIg4QAKYCAAIAAwldFoQXALsAAAEAAgk1GY5bAHIAAAAA.Santapal:BAABLgAECn8tAAQmAAgJDhrKIQDPAQAmAAcJoRrKIQDPAQAFAAIJegUyLQFTAAADAAIJaRIxQQA2AAABLgAFFAQJDwARAF8bAA==.Santatumblr:BAABLgAECn8aAAQeAAgJURvJEABmAgAeAAgJURvJEABmAgAWAAQJchDhXABwAAAZAAEJTQNRlQAcAAABLgAFFAQJDwARAF8bAA==.Santhin:BAAALgADCgcJCgAAAA==.Saphira:BAAALgAECgQJBAAAAA==.Sareit:BAABLgAECn8cAAMIAAcJHw7fMQAkAQAIAAYJIQzfMQAkAQAHAAYJAhJVMwAjAQAAAA==.Sassee:BAAALgAECgQJCAAAAA==.Sayvil:BAAALgAECgUJCwABLgAECgkJNgAXAAIgAQ==.',
Sc='Scripture:BAAALgADCgYJBgAAAA==.',
Se='Seawolph:BAABLgAECn8nAAIJAAkJwRXyHgAqAgAJAAkJwRXyHgAqAgAAAA==.Selenia:BAAALgAECgMJAwAAAA==.Semmers:BAAALgAECgkJCQAAAA==.Sensational:BAABLgAECn8aAAMeAAcJWhx+EwAvAgAeAAcJWhx+EwAvAgAWAAUJZwigSgCtAAAAAA==.Sergio:BAAALgAECgcJCgAAAA==.',
Sh='Shamiska:BAAALgAECgQJBwAAAA==.Shammerdown:BAAALgAECgIJAwAAAA==.Shampooh:BAAALgAECgQJBQABLgAECgcJFQAgAMYEAA==.Shamtastyk:BAAALgAECgQJBAAAAA==.Shaokhan:BAABLgAECn8qAAMJAAkJiSEsBQA7AwAJAAkJiSEsBQA7AwAMAAcJuwqyFAAuAQAAAA==.Sheilla:BAAALgADCgUJBQAAAA==.Shian:BAABLgAECn8xAAINAAgJyxa6DQDMAQANAAgJyxa6DQDMAQAAAA==.Shieldee:BAABLgAECn8uAAMFAAgJUxy3NgAGAgAFAAgJUxy3NgAGAgAmAAEJTgOqigAiAAAAAA==.Shlectrinell:BAABLgAECn85AAMjAAkJrQ1tFQDNAQAjAAkJrQ1tFQDNAQAnAAgJBAUICwB+AQAAAA==.Shockeei:BAACLgAFFH8bAAIUAAUJMiXlDgCiAQAUAAUJMiXlDgCiAQAuAAQKfykABBQACQkqJRAGAEADABQACQkqJRAGAEADACkAAwlSGHcJALkAAB8AAQnWIFIOAFoAAAAA.Shocktroop:BAAALgADCgYJCgAAAA==.Shortdon:BAAALgAECgEJAQAAAA==.Shurp:BAAALgAECgMJAwAAAA==.',
Si='Siakora:BAABLgAECn8VAAIjAAgJXRgLGwAoAgAjAAgJXRgLGwAoAgABLgAFFAYJHgAlALEbAA==.Sicksty:BAAALgADCgcJBwAAAA==.Sighh:BAAALgADCgYJBwAAAA==.Sighhy:BAAALgAECgUJDQAAAA==.Sijth:BAABLgAECn9KAAIFAAkJNx+UFwCXAgAFAAkJNx+UFwCXAgAAAA==.Silentchaos:BAAALgADCgMJBQAAAA==.Siler:BAAALgADCgYJBgAAAA==.Silverwar:BAABLgAECn8jAAIPAAgJwRrcFgATAgAPAAgJwRrcFgATAgAAAA==.Simmi:BAECLgAFFH8cAAIgAAYJGR5VBwAsAgAgAAYJGR5VBwAsAgAuAAQKfykAAiAACQnBJbMEAFgDACAACQnBJbMEAFgDAAAA.Sinnis:BAAALgAECgEJAQAAAA==.Sixte:BAAALgAECgMJAwAAAA==.Sixtea:BAABLgAECn8iAAIKAAgJzxgrGgDkAQAKAAgJzxgrGgDkAQAAAA==.',
Sk='Skarredd:BAAALgADCgYJCAAAAA==.Skepti:BAABLgAECn8mAAITAAkJfxS9JQAfAgATAAkJfxS9JQAfAgAAAA==.Skysong:BAAALgAECgMJAwAAAA==.',
Sl='Slapdemhoes:BAAALgAECgcJAgAAAA==.Slimfoo:BAAALgAECgcJDQAAAA==.Slunkyspit:BAAALgADCgUJCAAAAA==.Slybearclaw:BAAALgADCgUJBQAAAA==.Slyeulogy:BAAALgAECgEJAQAAAA==.',
Sm='Smeeta:BAACLgAFFH8FAAIdAAIJRRptmQCdAAAdAAIJRRptmQCdAAAuAAQKf10ABB0ACQmHJEkKAP8CAB0ACQkxJEkKAP8CABsACAldIyoCALkCABoABQlQEcouALgAAAAA.Smoak:BAAALgADCgUJBQAAAA==.Smolderlight:BAABLgAECn86AAImAAkJ6BR5GAAcAgAmAAkJ6BR5GAAcAgAAAA==.Smoochiebutt:BAAALgAECgUJCQAAAA==.',
So='Solaace:BAAALgAECgEJAQAAAA==.Solo:BAAALgAECgYJCQAAAA==.Soloris:BAAALgADCgcJCAAAAA==.Sonja:BAAALgAECgcJBwAAAA==.Soram:BAAALgAECgYJCgAAAA==.Soulstryker:BAAALgAECgEJAQAAAA==.Soùl:BAAALgADCgQJBAAAAA==.',
Sp='Spacepants:BAAALgAECgEJAQAAAA==.Spurgeon:BAAALgAECgEJAQAAAA==.',
St='Staraelle:BAAALgAECgEJAgAAAA==.Stazz:BAAALgAECgYJBgAAAA==.Steelerayne:BAAALgAECgcJDwAAAA==.Stormii:BAAALgAECgkJEQAAAA==.Strangerdk:BAABLgAECn8vAAIdAAgJsw7vXwCFAQAdAAgJsw7vXwCFAQAAAA==.Streetdog:BAAALgADCgYJBgAAAA==.Stublin:BAAALgADCgEJAQAAAA==.',
Su='Suggondeez:BAAALgAECgYJBgAAAA==.Superfatbaby:BAABLgAECn8dAAIPAAkJKhM5HwDRAQAPAAkJKhM5HwDRAQAAAA==.',
Sw='Swikk:BAAALgADCgYJCAAAAA==.Swishersweet:BAABLgAECn8qAAINAAkJlgmBHgAWAQANAAkJlgmBHgAWAQAAAA==.Swordfish:BAABLgAECn8XAAIiAAYJdB6GCACEAQAiAAYJdB6GCACEAQAAAA==.',
Sy='Syannae:BAAALgADCgYJBwAAAA==.Sybros:BAAALgADCgEJAQAAAA==.Sydonie:BAAALgAECgEJBQAAAA==.Sylus:BAAALgAECgQJBAAAAA==.Symbah:BAAALgADCgYJBgAAAA==.Synvalid:BAABLgAECn8gAAIRAAkJ9wc4dAATAQARAAkJ9wc4dAATAQAAAA==.Syzrin:BAAALgADCgEJAQABLgAECggJIgAGAHcUAA==.',
Ta='Tabrieus:BAABLgAECn83AAIUAAkJXB4MFgC6AgAUAAkJXB4MFgC6AgAAAA==.Tadokof:BAAALgADCgkJGAAAAA==.Talanth:BAAALgAECggJEwAAAA==.Tandisong:BAAALgAECgcJCAAAAA==.Tanknhammerm:BAAALgADCgYJBgAAAA==.Tanknstein:BAAALgADCgYJBgAAAA==.Tanton:BAAALgAECgMJAwAAAA==.Tanzil:BAAALgAECgYJDgAAAA==.Tardigrade:BAAALgAECggJDwAAAA==.Tareyna:BAAALgAECggJEQAAAA==.Tayon:BAAALgAECgcJEAAAAA==.Tayvin:BAAALgAECgQJBQAAAA==.Tazanath:BAAALgADCgEJAgAAAA==.',
Te='Tempest:BAAALgADCgcJBwAAAA==.Tengen:BAAALgAECgUJDAAAAA==.Termana:BAACLgAFFH8gAAIkAAYJiyBYBADDAQAkAAYJiyBYBADDAQAuAAQKfygAAiQACQmCJJcBAC0DACQACQmCJJcBAC0DAAAA.',
Th='Tharja:BAABLgAECn8bAAIUAAkJXhvvNACfAgAUAAkJXhvvNACfAgAAAA==.Thornp:BAAALgAECgEJAgAAAA==.Thoronk:BAAALgAECgcJBgAAAA==.Thsaric:BAAALgAECgEJAQAAAA==.Thug:BAABLgAECn8WAAMPAAcJ0R/RJQArAgAPAAcJ0R/RJQArAgAkAAIJHxvRNgCRAAAAAA==.Thuggin:BAAALgAECgEJAQAAAA==.',
Ti='Tiferet:BAABLgAECn8pAAQXAAkJLiDuBAATAwAXAAkJLiDuBAATAwAHAAUJ+QzQQwDVAAAIAAMJfRLoPgC3AAAAAA==.Tigiw:BAAALgAECgEJAQAAAA==.Tinysunshine:BAAALgAECgcJEAAAAA==.Tinyt:BAAALgAECgEJAQAAAA==.Tismyhammer:BAAALgADCgQJBAAAAA==.',
To='Toasted:BAAALgADCgQJAQAAAA==.Tolenkar:BAABLgAECn8bAAITAAgJsRuSMQDsAQATAAgJsRuSMQDsAQAAAA==.Tomato:BAACLgAFFH8WAAMYAAYJNxDaBwDxAAAGAAUJwxFDOAA0AQAYAAQJxA3aBwDxAAAuAAQKfyMAAxgACQlpHaYFAHoCABgACAkIHKYFAHoCAAYABQlZF3aIABQBAAAA.Tomhanks:BAAALgAECgUJDQAAAA==.Tormentaa:BAAALgAECgYJBwAAAA==.Torvalar:BAABLgAECn9CAAIFAAkJeBfLLAAsAgAFAAkJeBfLLAAsAgAAAA==.',
Tr='Treemendous:BAAALgADCgYJCQAAAA==.Trolgoskill:BAAALgADCgEJAQAAAA==.Truthslayer:BAABLgAECn8cAAMPAAkJKAlzPgAjAQAPAAkJKAlzPgAjAQAQAAEJcgr/QgAzAAAAAA==.Trûth:BAABLgAECn8WAAIHAAgJxBBMIwC9AQAHAAgJxBBMIwC9AQAAAA==.',
Tu='Turdyl:BAABLgAECn8sAAIFAAkJuhECVgCqAQAFAAkJuhECVgCqAQAAAA==.',
Tw='Twindad:BAAALgADCgkJEQAAAA==.Twindadlock:BAAALgAECgEJAQAAAA==.Twowheels:BAAALgAECgMJBAAAAA==.',
Ty='Tyraz:BAAALgAECgcJEwAAAA==.Tystrolf:BAABLgAECn8YAAQlAAcJrg2sOgD1AAAlAAYJ/w6sOgD1AAAVAAUJjAdxKACQAAANAAIJgAlHUAA5AAAAAA==.',
Tz='Tzar:BAAALgADCgIJAgAAAA==.',
['Tô']='Tôx:BAABLgAECn8XAAMKAAcJWB1YLQCwAQAKAAcJWB1YLQCwAQAJAAIJRhSYrgA2AAAAAA==.',
Ub='Ubrew:BAAALgAECgkJBQAAAA==.',
Ud='Udyrr:BAAALgADCgIJAgAAAA==.',
Ul='Ulfius:BAAALgADCgMJAwAAAA==.Ullume:BAAALgAECgkJCwAAAA==.',
Um='Umbranwings:BAAALgAECgUJBQAAAA==.',
Un='Unheardjp:BAAALgAECgMJCwAAAA==.Unholy:BAAALgADCgMJAwAAAA==.Unholyarnix:BAAALgAECgQJDQAAAA==.',
Ur='Ursus:BAAALgADCgYJBgAAAA==.Uruloki:BAAALgADCgIJAgAAAA==.',
Va='Vacuum:BAAALgAECgYJEQAAAA==.Vadican:BAAALgADCgQJBAAAAA==.Vaerix:BAABLgAECn8pAAIcAAkJ1Q0iJwCHAQAcAAkJ1Q0iJwCHAQAAAA==.Valdora:BAAALgAECgEJAQAAAA==.Valhals:BAABLgAECn8qAAMZAAkJDAiONQAKAQAZAAgJTAWONQAKAQAWAAMJUQ7pYABlAAAAAA==.Valydrin:BAABLgAECn9AAAIXAAkJ9B0JCADIAgAXAAkJ9B0JCADIAgAAAA==.Vanhelsinky:BAAALgADCgIJAgAAAA==.Vanquished:BAAALgAECgIJBAAAAA==.Varyn:BAAALgADCgIJAgAAAA==.',
Ve='Velandia:BAAALgAECgcJDAAAAA==.Ventis:BAAALgAECgQJBwAAAA==.',
Vi='Vicara:BAAALgADCgYJBgAAAA==.Virgl:BAAALgAECgkJBQAAAA==.',
Vo='Voidifphat:BAAALgAECggJEAAAAA==.Voidtorrent:BAAALgAECgQJCAAAAA==.Voidvanquish:BAAALgAECgYJBwAAAA==.Vorkhan:BAAALgADCgUJCAAAAA==.',
Vu='Vuldrak:BAAALgAECggJEwAAAA==.',
Vy='Vysis:BAACLgAFFH8QAAQHAAMJeQkkHQDWAAAHAAMJeQkkHQDWAAAIAAMJUAmtJgDKAAAXAAIJ1AwHDgCOAAAuAAQKf0cABBcACQluGYcSAEwCABcACQlQF4cSAEwCAAcACAmGG1ERACcCAAgACAkMFMgVAPwBAAAA.',
['Vä']='Vännic:BAAALgADCgEJAwAAAA==.Vännìc:BAAALgADCgEJAQAAAA==.',
['Ví']='Ví:BAABLgAECn8YAAIWAAgJ3gezMwALAQAWAAgJ3gezMwALAQAAAA==.',
Wh='Whatfoxsay:BAAALgADCgEJAQAAAA==.Whats:BAAALgADCgcJBwABLgAECgcJEAAEAAAAAA==.When:BAAALgADCgQJBAAAAA==.Whicker:BAAALgAECgUJBgAAAA==.Whipsnchains:BAAALgAECgUJBgAAAA==.Whipsntricks:BAAALgAECgIJAgAAAA==.',
Wi='Wickèr:BAACLgAFFH8GAAIZAAIJ9hKpOQCRAAAZAAIJ9hKpOQCRAAAuAAQKfzcAAhkACQkHHhMHAKgCABkACQkHHhMHAKgCAAAA.Wieldblade:BAABLgAECn83AAMFAAkJsh26HQB1AgAFAAkJsh26HQB1AgADAAgJiBZQDADTAQAAAA==.Wilsondk:BAAALgAECgEJAwAAAA==.Winslett:BAAALgADCgQJBAAAAA==.',
Wo='Wolfemoon:BAABLgAECn8UAAITAAgJwwqXYQBVAQATAAgJwwqXYQBVAQAAAA==.Worganlefey:BAAALgAECgMJBwABLgAECgkJPwAGAE0OAA==.',
Wr='Wrexd:BAABLgAECn8qAAIGAAgJChudOQDbAQAGAAgJChudOQDbAQAAAA==.',
Wu='Wunderbar:BAABLgAECn8xAAMKAAgJNR9cDQBuAgAKAAgJNR9cDQBuAgAJAAgJWBlUGwBDAgAAAA==.',
Wy='Wyldfire:BAACLgAFFH8VAAIlAAQJYRcVFQA6AQAlAAQJYRcVFQA6AQAuAAQKfy8AAyUACQleI/kLANgCACUACQleI/kLANgCACAAAwksEo2eAI4AAAAA.Wyndclaw:BAABLgAECn8WAAIeAAYJcBYEKwCIAQAeAAYJcBYEKwCIAQAAAA==.',
Xa='Xanith:BAABLgAECn8pAAIPAAgJARZDIQDBAQAPAAgJARZDIQDBAQAAAA==.',
Xe='Xebubble:BAAALgADCgEJAQABLgAECgEJAQAEAAAAAA==.Xemonk:BAAALgAECgEJAQAAAA==.',
Xi='Xia:BAAALgADCgYJBgAAAA==.',
Xr='Xroi:BAAALgAECgIJAgAAAA==.',
Ya='Yaganor:BAAALgADCgUJBgAAAA==.',
Ye='Yeto:BAAALgADCgYJBwAAAA==.',
Yi='Yia:BAAALgAECgQJCAABLgAECgQJDAAEAAAAAA==.Yilnara:BAABLgAECn8YAAIRAAgJsAayegAEAQARAAgJsAayegAEAQAAAA==.',
Ys='Ysa:BAABLgAECn8dAAMWAAcJqiShEAB3AgAWAAcJqiShEAB3AgAeAAEJlA2UbAApAAAAAA==.',
Za='Zajindor:BAAALgADCgEJAQAAAA==.Zarathul:BAAALgADCgIJAgAAAA==.',
Ze='Zekkun:BAAALgAECgEJAQAAAA==.',
Zh='Zheria:BAAALgAECgQJBAAAAA==.',
Zi='Zirael:BAAALgADCgYJCgAAAA==.',
Zo='Zod:BAAALgAECgkJCQAAAA==.Zoganian:BAEALgAECgQJCQABLgAECggJHQAXAO0jAA==.Zogula:BAEBLgAECn8dAAMXAAgJ7SN1CwCIAgAXAAgJsyN1CwCIAgAIAAEJaiPTUwBjAAAAAA==.',
Zu='Zu:BAAALgAECgQJDQAAAA==.',
['År']='Årtemis:BAABLgAECn8xAAIoAAgJwB1iCgBgAgAoAAgJwB1iCgBgAgAAAA==.',
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
