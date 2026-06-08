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
local provider = {region='US',realm='AzjolNerub',name='US',type='weekly',zone=46,date='2026-06-06',data={Ad='Adapt:BAAALgAECgMJCQAAAA==.Addy:BAACLgAFFH8FAAIBAAMJtROFFgDSAAABAAMJtROFFgDSAAAuAAQKfzoAAwEACQnQIVsDABUDAAEACQnQIVsDABUDAAIAAQlCCJw2ACEAAAAA.',
Ae='Aeonis:BAAALgAECgMJCgAAAA==.Aestian:BAABLgAECn8wAAIDAAgJLBtgDwDBAQADAAgJLBtgDwDBAQAAAA==.',
Ag='Agamesh:BAAALgADCgUJCQAAAA==.',
Ah='Ahoma:BAAALgADCgkJBgAAAA==.',
Ai='Ailysely:BAAALgADCgUJBQABLgAECgMJCgAEAAAAAA==.Airees:BAABLgAECn8iAAIFAAcJOx7oQQAfAgAFAAcJOx7oQQAfAgAAAA==.Aispere:BAAALgAECgQJBQAAAA==.',
Al='Alastria:BAAALgADCgcJBwAAAA==.Alektra:BAAALgADCgUJBwAAAA==.Alerzhulan:BAABLgAECn8bAAIGAAkJMgunVQCXAQAGAAkJMgunVQCXAQAAAA==.Allanquatre:BAAALgAECgYJBgAAAA==.Alledria:BAABLgAECn8aAAIFAAgJmhJjcgB+AQAFAAgJmhJjcgB+AQAAAA==.Allenaena:BAAALgAECgMJBgAAAA==.Alorely:BAABLgAECn8gAAMHAAkJ/gz1LABpAQAHAAgJ0A31LABpAQAIAAcJoxO3LgBYAQAAAA==.Altonas:BAAALgAECgMJAwAAAA==.',
Am='Amanara:BAAALgAECgcJDQAAAA==.Amillah:BAAALgAECgQJBgAAAA==.Amooka:BAAALgAECgEJAQAAAA==.',
An='Ancientmonk:BAAALgAECgEJAQABLgAECgYJCQAEAAAAAA==.Anciientpaw:BAABLgAECn8iAAMJAAkJGyBlHQAvAgAJAAkJGyBlHQAvAgAKAAUJbBW6VQDTAAAAAA==.Andramalyus:BAABLgAECn8pAAIGAAgJ3AzqaABmAQAGAAgJ3AzqaABmAQAAAA==.Andrasomnium:BAAALgAECgYJCAAAAA==.Angbar:BAABLgAECn8vAAILAAkJWRbUCABYAgALAAkJWRbUCABYAgAAAA==.Anguirus:BAABLgAECn81AAMKAAkJNQVZUQDhAAAKAAkJBQVZUQDhAAAMAAYJLwIoLQBvAAAAAA==.Animà:BAAALgAECgYJDwAAAA==.Ankhnstein:BAAALgAECgQJBAAAAA==.Antiheroo:BAAALgAECgUJBwAAAA==.Antoine:BAAALgAECgIJAgAAAA==.Anuksunàmun:BAAALgAECgcJBAAAAA==.',
Ap='Apolloni:BAAALgAECgIJAgABLgAECgkJKgANAJYJAA==.Appynoxusrog:BAABLgAECn8cAAIOAAYJuhguBQCcAQAOAAYJuhguBQCcAQAAAA==.',
Aq='Aqulenas:BAABLgAFFH8FAAIPAAMJsRP8jQDeAAAPAAMJsRP8jQDeAAAAAA==.',
Ar='Arakhan:BAAALgAFFAEJAQAAAA==.Arasaka:BAAALgAECgQJCAAAAA==.Arcadian:BAABLgAECn8xAAMQAAkJHB3BDwB1AgAQAAkJHB3BDwB1AgARAAEJzAfURAAvAAAAAA==.Arcadiann:BAAALgAECgUJEQAAAA==.Arcadin:BAAALgAECgEJAgAAAA==.Arcoyflecha:BAAALgAECgYJCgAAAA==.Arextheelder:BAAALgAECgcJDgAAAA==.Aridas:BAABLgAECn8dAAMSAAgJJBhuMwAsAgASAAgJJBhuMwAsAgABAAIJRQsGYABiAAABLgAECgkJKAARAAcaAA==.Arikdeath:BAABLgAECn8pAAMTAAkJlRcvKQAuAgATAAcJbxgvKQAuAgAUAAcJTgyKFAANAQAAAA==.Armorscales:BAACLgAFFH8UAAIGAAYJ+xoxIwCbAQAGAAYJ+xoxIwCbAQAuAAQKfy0AAgYACQm/IVgQAPcCAAYACQm/IVgQAPcCAAAA.Arniix:BAAALgAECgEJAQABLgAECgQJDQAEAAAAAA==.Arnixskitty:BAAALgAECgEJAQABLgAECgQJDQAEAAAAAA==.Arntraz:BAAALgADCgkJPwAAAA==.Arçadia:BAAALgAECgMJAwAAAA==.',
As='Ashegen:BAAALgAECgQJBAAAAA==.Ashnikko:BAAALgAECgEJAQAAAA==.Ashtori:BAAALgADCgEJAgAAAA==.Asis:BAAALgAECgEJAQAAAA==.Astayoni:BAAALgADCgEJAQAAAA==.Astrine:BAACLgAFFH8UAAIVAAYJyBZfNACFAQAVAAYJyBZfNACFAQAuAAQKfysAAhUACQlJIAYiAOsCABUACQlJIAYiAOsCAAAA.',
Au='Auberon:BAABLgAECn8oAAIWAAkJ/xl6BgCSAgAWAAkJ/xl6BgCSAgAAAA==.Aufta:BAABLgAECn8rAAIXAAkJHgauNwAXAQAXAAkJHgauNwAXAQAAAA==.',
Av='Avalonia:BAAALgAECgEJAQAAAA==.',
Az='Azdh:BAAALgAECgQJBgAAAA==.Azi:BAACLgAFFH8cAAIUAAcJix5bBwDkAQAUAAcJix5bBwDkAQAuAAQKfykAAhQACQkGIG8DAIwCABQACQkGIG8DAIwCAAAA.Azshanorel:BAAALgADCgcJBwAAAA==.Azunea:BAAALgAECgIJBwAAAA==.Azurite:BAAALgAECgkJDwAAAA==.',
Ba='Backpedal:BAAALgAECgcJEgAAAA==.Badankhadonk:BAACLgAFFH8UAAIJAAUJaCJEDgDYAQAJAAUJaCJEDgDYAQAuAAQKfy0AAgkACQl7JVICAF8DAAkACQl7JVICAF8DAAAA.Balen:BAABLgAECn8sAAIDAAkJohQqDQDkAQADAAkJohQqDQDkAQAAAA==.Bandrösh:BAAALgADCgMJAwAAAA==.Barradune:BAAALgADCgYJDAAAAA==.Baubles:BAAALgAECgMJAgAAAA==.',
Be='Belholy:BAABLgAECn8vAAIYAAgJNiKmBwDoAgAYAAgJNiKmBwDoAgAAAA==.Beliice:BAAALgADCgkJIAABLgAECggJLwAYADYiAA==.Bellanei:BAAALgAECgEJBAAAAA==.Ben:BAAALgAECgEJAQAAAA==.Benafflockk:BAAALgADCggJCAAAAA==.Benefitdruid:BAAALgAECgEJAQAAAA==.Benilok:BAACLgAFFH8RAAMGAAUJ+yFmGQDOAQAGAAUJ+yFmGQDOAQAZAAEJ6hCXJABHAAAuAAQKfysAAgYACQkcJSEMABkDAAYACQkcJSEMABkDAAAA.Bethgibbons:BAAALgADCgkJOAAAAA==.',
Bi='Bibimbap:BAAALgAECgEJAQAAAA==.Bigsuccubus:BAABLgAECn8bAAIZAAkJ2hUPBQAWAgAZAAkJ2hUPBQAWAgAAAA==.Biohazard:BAAALgADCgUJBQAAAA==.Bizël:BAAALgAECgYJDQAAAA==.',
Bl='Blackblood:BAABLgAECn8mAAIBAAkJLRXBEgDyAQABAAkJLRXBEgDyAQAAAA==.Blackclouds:BAAALgADCgkJCQAAAA==.Blackspiral:BAAALgADCgEJAQAAAA==.Bladestriker:BAAALgAECgUJBwAAAA==.Blindside:BAAALgAECgMJBgAAAA==.Bloodache:BAABLgAECn8VAAISAAcJKSFgKQBcAgASAAcJKSFgKQBcAgAAAA==.Bloodkissed:BAAALgADCgUJBgABLgAECgkJOAAYAEQgAA==.Bluebuberry:BAAALgAECgQJBgAAAA==.Bluesaphire:BAAALgAECgIJAgABLgAECggJFQAJAP8ZAA==.Blux:BAAALgAECgQJCAAAAA==.',
Bo='Boil:BAABLgAECn8kAAIOAAgJbgeODgAXAQAOAAgJbgeODgAXAQAAAA==.Bonemarrow:BAAALgAECgQJEwAAAA==.Bournx:BAAALgAECgIJAgAAAA==.Boysenbar:BAAALgADCgYJCAAAAA==.',
Br='Bradrenna:BAACLgAFFH8HAAMCAAMJLg4wCwB+AAABAAMJyAMTHACaAAACAAIJWRQwCwB+AAAuAAQKf1MABAIACQlPG7QEAF8CAAIACQlPG7QEAF8CAAEAAglaD1RSAF0AABIAAQmlAcf0ABsAAAAA.Brakeable:BAAALgAECgUJBQAAAA==.Braké:BAABLgAECn8eAAIDAAkJaB3gBACeAgADAAkJaB3gBACeAgAAAA==.Brandrale:BAAALgAECgEJAgAAAA==.Breakthrough:BAABLgAECn8cAAIJAAYJpSJDHgBPAgAJAAYJpSJDHgBPAgAAAA==.Brenzull:BAAALgADCgYJCwAAAA==.Brewskies:BAABLgAECn8nAAIaAAcJDyXcCwBvAgAaAAcJDyXcCwBvAgABLgAECgkJLAAbAOEiAA==.Brewsli:BAAALgADCgIJAgABLgAECgkJHQAcABULAA==.Brightstar:BAAALgAECgcJEwAAAA==.Brokenaltar:BAABLgAECn8VAAMBAAYJNRheOQAdAQASAAYJgRFacwBLAQABAAUJCRpeOQAdAQAAAA==.Brownington:BAACLgAFFH8GAAMWAAMJJRIXEgCNAAAWAAIJFA0XEgCNAAANAAEJSBxdLgBNAAAuAAQKfxkAAw0ABwlWJDsIAFwCAA0ABwlWJDsIAFwCABYAAQmjCqJMADAAAAAA.Bruhilda:BAABLgAECn8dAAIVAAkJ7hIpRwAAAgAVAAkJ7hIpRwAAAgAAAA==.Brymstone:BAAALgAECgQJBwAAAA==.Brynthebuff:BAAALgAECgEJAQAAAA==.Brìonik:BAACLgAFFH8eAAMZAAcJ5h0UBwAXAQAGAAYJABvDIQCiAQAZAAQJTx8UBwAXAQAuAAQKfyoAAxkACQkPJCkFABICABkABgkoJSkFABICAAYABQkeI2xvAFcBAAAA.',
Bu='Bufferfish:BAABLgAECn82AAIdAAkJUQxCLACDAQAdAAkJUQxCLACDAQAAAA==.',
Ca='Calinnea:BAABLgAECn8UAAMeAAgJTA0cOwBrAQAeAAgJTA0cOwBrAQAXAAIJDgOFiAAnAAAAAA==.Cantheartitz:BAABLgAECn8WAAIVAAUJPxmBnQCbAQAVAAUJPxmBnQCbAQAAAA==.Catastrophe:BAABLgAECn8nAAIXAAgJASIFCQCpAgAXAAgJASIFCQCpAgAAAA==.',
Ce='Celira:BAAALgADCgMJAwAAAA==.Celthol:BAABLgAECn8ZAAISAAYJJBPncAA0AQASAAYJJBPncAA0AQAAAA==.',
Ch='Chelraani:BAABLgAECn84AAIFAAkJeyFUDQDyAgAFAAkJeyFUDQDyAgAAAA==.Chiichard:BAAALgADCgYJCgAAAA==.Chipnuts:BAABLgAECn8bAAIXAAkJ8CTAAgBtAwAXAAkJ8CTAAgBtAwAAAA==.Chonchoo:BAAALgADCgEJAQAAAA==.Chosethebear:BAAALgADCgkJEAAAAA==.Chunkamonk:BAAALgADCgUJBgAAAA==.',
Ci='Cigar:BAAALgAECgQJBgABLgAFFAcJGAAPAFQaAA==.Cinderat:BAAALgADCgEJAQAAAA==.',
Cl='Clambumper:BAAALgADCgUJBQAAAA==.Clarabellax:BAAALgAECgQJBQAAAA==.Clarkkentt:BAAALgADCgcJDQAAAA==.Claymore:BAACLgAFFH8RAAIQAAYJBBZADACQAQAQAAYJBBZADACQAQAuAAQKfxUAAhAACAkMGcscAGcCABAACAkMGcscAGcCAAAA.Clazzicola:BAACLgAFFH8PAAMeAAUJPxIAIQA3AQAeAAUJPxIAIQA3AQAXAAMJJgvADQCWAAAuAAQKfx8ABBcACQmbFmIeAOUBABcABwlYHGIeAOUBAB4ACAniEYomAH4BABoAAQlhA8uVAB8AAAAA.Cloudbeast:BAAALgAECgMJBAABLgAECgcJEAAEAAAAAA==.Clue:BAAALgADCgYJBgAAAA==.',
Co='Cocito:BAAALgAECgEJAwAAAA==.Commândment:BAAALgAECgcJDgAAAA==.Conjredcukee:BAABLgAECn8WAAIVAAcJ7AO33gDWAAAVAAcJ7AO33gDWAAAAAA==.Coo:BAAALgAECgQJBAABLgAECgUJBwAEAAAAAA==.Coogsayer:BAABLgAECn8UAAIHAAcJyh2aEQBxAgAHAAcJyh2aEQBxAgAAAA==.Couch:BAAALgAECgUJBQAAAA==.',
Cp='Cptncrush:BAABLgAECn8fAAMJAAgJBBqqJgAZAgAJAAgJBBqqJgAZAgAKAAMJoBeyZACoAAAAAA==.',
Cr='Croquetica:BAAALgADCgMJBAAAAA==.Crossed:BAAALgADCgcJCwAAAA==.Crowshadow:BAABLgAECn8bAAIGAAcJExtSOgDsAQAGAAcJExtSOgDsAQAAAA==.',
Cy='Cylina:BAAALgADCgcJCAABLgADCgcJFAAEAAAAAA==.Cyliya:BAAALgADCgIJAwABLgADCgcJFAAEAAAAAA==.Cylore:BAAALgADCgcJBgABLgADCgcJFAAEAAAAAA==.Cypherrellik:BAAALgAECgMJAwABLgAECgkJHAABAIUQAA==.Cyrax:BAAALgADCgMJAwAAAA==.Cyther:BAACLgAFFH8iAAIQAAcJjSBmAwAlAgAQAAcJjSBmAwAlAgAuAAQKfykAAhAACQmXIqwHAC4DABAACQmXIqwHAC4DAAAA.',
['Cÿ']='Cÿthera:BAABLgAECn8bAAISAAkJ4BzDHAClAgASAAkJ4BzDHAClAgAAAA==.',
Da='Dakk:BAABLgAECn9KAAIPAAkJOiMbCQAhAwAPAAkJOiMbCQAhAwAAAA==.Daraghor:BAABLgAECn8bAAINAAkJoCIMAgAbAwANAAkJoCIMAgAbAwAAAA==.Darkdottie:BAAALgAECgQJCAAAAA==.Darkenstormy:BAAALgAECgcJDwAAAA==.Darlyndra:BAAALgADCgUJBQAAAA==.Darsae:BAAALgAECgQJDAAAAA==.Darthiono:BAAALgAECgEJAQAAAA==.Darthmaull:BAAALgADCgEJAQAAAA==.',
De='Deadlight:BAABLgAECn8wAAMPAAkJ+BGoTgDQAQAPAAkJZBGoTgDQAQAcAAEJYBLyMwA5AAAAAA==.Deathkillhun:BAAALgAECgQJBwAAAA==.Deathpooch:BAAALgAFFAEJAQAAAA==.Deathshooter:BAAALgAECgcJAQAAAA==.Deavant:BAAALgADCgMJAwAAAA==.Deermon:BAAALgAECgYJCwAAAA==.Deet:BAAALgAECgUJBQAAAA==.Deforest:BAAALgADCgcJFgAAAA==.Deity:BAABLgAECn8xAAIQAAkJ9CK+BAAQAwAQAAkJ9CK+BAAQAwAAAA==.Demogon:BAAALgAECgQJBwAAAA==.Demondeano:BAABLgAECn8bAAISAAkJARMjRwClAQASAAkJARMjRwClAQAAAA==.Demonllxll:BAAALgAECgYJCwAAAA==.Demonlxl:BAABLgAECn8cAAIKAAgJ/xUcIADUAQAKAAgJ/xUcIADUAQAAAA==.Demonthorx:BAAALgAECgUJBQAAAA==.Demonx:BAABLgAECn8zAAIPAAkJ+x1qGACsAgAPAAkJ+x1qGACsAgAAAA==.Desolation:BAABLgAECn9SAAIfAAkJ+iUfAABzAwAfAAkJ+iUfAABzAwAAAA==.Despia:BAABLgAECn8zAAMYAAkJeSM2AgB9AwAYAAkJeSM2AgB9AwAHAAYJzxHGLwBYAQAAAA==.Devastacia:BAAALgADCgUJBQAAAA==.Deviarc:BAAALgAECgQJBAABLgAFFAYJGQALAP8cAA==.',
Dh='Dharkon:BAAALgAECgIJBAAAAA==.',
Di='Dicot:BAABLgAECn8yAAIgAAkJRxOIJQAYAgAgAAkJRxOIJQAYAgAAAA==.',
Dj='Djpallyd:BAAALgAECgkJEAAAAA==.',
Do='Doinks:BAAALgAECgIJAgAAAA==.Domilthri:BAACLgAFFH8IAAIGAAMJWAOehACpAAAGAAMJWAOehACpAAAuAAQKf0AAAwYACAlCEAZcAIYBAAYACAlCEAZcAIYBACEABgnyBUMQACoBAAAA.Donut:BAAALgADCgIJAgABLgAECggJHgAiACchAA==.Dotdaddy:BAAALgAECgQJBwABLgAECggJFAAeAEwNAA==.Doughy:BAAALgAECgYJBgAAAA==.',
Dr='Dracoly:BAAALgAECggJEgAAAA==.Draconu:BAACLgAFFH8mAAIdAAYJ+BnzEwCsAQAdAAYJ+BnzEwCsAQAuAAQKfyIAAx0ACQk4H+YLAJQCAB0ACQk4H+YLAJQCAAsAAQmaAX1OACIAAAAA.Draenyth:BAABLgAECn8aAAISAAcJvw+SagBDAQASAAcJvw+SagBDAQAAAA==.Dragoncurry:BAABLgAECn8WAAILAAYJIgZTJgCuAAALAAYJIgZTJgCuAAAAAA==.Dragonmite:BAAALgAECgEJAQAAAA==.Drakka:BAAALgADCgkJDgABLgAECgkJFQAFAAIVAA==.Draktyr:BAACLgAFFH8GAAIQAAMJtRZeFgCyAAAQAAMJtRZeFgCyAAAuAAQKfyQAAhAACQn2HncJABYDABAACQn2HncJABYDAAAA.Draxoths:BAAALgAECgMJBQABLgAFFAMJBwAgADkZAA==.Dropeadita:BAAALgAECgQJBAAAAA==.Droptop:BAAALgADCgcJCAAAAA==.',
Du='Dumbsht:BAABLgAECn8ZAAMUAAgJ6xbDMQCpAQAUAAcJ6xXDMQCpAQATAAYJVhHjXQBOAQAAAA==.',
Dy='Dyvyne:BAAALgAECgQJBwAAAA==.',
Ea='Easystreet:BAAALgAECgIJAwAAAA==.',
Ef='Effluv:BAAALgADCgcJDgAAAA==.',
El='Elandir:BAAALgADCgQJAQAAAA==.Elanora:BAAALgAECgYJCQAAAA==.Elbrookel:BAAALgAECgIJAgAAAA==.Eleshnorn:BAAALgAFFAEJAwAAAA==.Eliza:BAAALgADCgkJCQAAAA==.Ellismom:BAABLgAECn9BAAIPAAkJ+SFMDAADAwAPAAkJ+SFMDAADAwAAAA==.Elvea:BAABLgAECn8kAAMdAAgJjRoOGQAHAgAdAAgJjRoOGQAHAgAiAAEJ9QoWQgArAAABLgAFFAUJFwAjAOMWAA==.',
Em='Emeralddemon:BAAALgAECgUJCQAAAA==.Emeraldshade:BAAALgADCgcJDwABLgAECgUJCQAEAAAAAA==.Emeråld:BAAALgAECgUJBwAAAA==.',
En='Enamorada:BAAALgAECgIJAgABLgAECggJFQAJAP8ZAA==.',
Er='Ereithelda:BAACLgAFFH8gAAMeAAcJ4BIfEgDLAQAeAAcJ4BIfEgDLAQAXAAIJQRULKgCTAAAuAAQKfyYAAh4ACAm2IhcHAOkCAB4ACAm2IhcHAOkCAAAA.Ericka:BAAALgADCgYJDQAAAA==.Erreya:BAAALgADCgEJAQAAAA==.',
Es='Esma:BAAALgADCgkJCQAAAA==.',
Ev='Evox:BAAALgAECggJEwAAAA==.',
Ey='Eyris:BAAALgADCgMJAwAAAA==.Eyrndor:BAAALgADCgIJAwAAAA==.',
Fa='Faacee:BAAALgAECgIJAgAAAA==.Falgar:BAAALgAECgMJAQAAAA==.Fann:BAABLgAECn8gAAIgAAkJgARGaADyAAAgAAkJgARGaADyAAAAAA==.Fauna:BAAALgAECgYJBgAAAA==.Fawn:BAAALgAECgIJBAAAAA==.Faytl:BAAALgAECgMJAwAAAA==.',
Fe='Felbubu:BAABLgAECn8jAAQCAAkJlyIeBACAAgACAAkJLCIeBACAAgABAAYJOyAmIgCrAQASAAMJNRzrnwDVAAAAAA==.Femboy:BAAALgAECgUJDgAAAA==.Fewz:BAACLgAFFH8MAAIVAAQJ3BjQbQD6AAAVAAQJ3BjQbQD6AAAuAAQKfyQAAhUACQnjIdYaALMCABUACQnjIdYaALMCAAAA.',
Fi='Fireybuns:BAAALgAECgEJAwAAAA==.',
Fl='Flakiron:BAACLgAFFH8ZAAIkAAYJAhPiDwAgAQAkAAYJAhPiDwAgAQAuAAQKfy0AAiQACQkjHJkLAFQCACQACQkjHJkLAFQCAAAA.Flakov:BAAALgAECgIJAgABLgAFFAYJGQAkAAITAA==.Flaktop:BAAALgAECgUJCAABLgAFFAYJGQAkAAITAA==.Fler:BAAALgAECgQJCAAAAA==.',
Fo='Forbacon:BAABLgAECn8dAAMcAAkJFQtTEgBBAQAcAAkJuApTEgBBAQAPAAYJgQlYyQDnAAAAAA==.Force:BAABLgAECn8iAAQcAAkJygp8EABbAQAcAAgJnwt8EABbAQAPAAUJEAR6BAGXAAAbAAEJ+wQJYQAdAAAAAA==.Fornost:BAAALgADCgkJDgAAAA==.Forsaken:BAAALgAECgQJBAABLgAECgkJMQAQAPQiAA==.Fourdragon:BAAALgADCgQJBAABLgAECggJFwAKACQXAA==.Fouris:BAABLgAECn8XAAIKAAgJJBdtKACcAQAKAAgJJBdtKACcAQAAAA==.',
Fr='Fremosth:BAAALgADCgMJAwAAAA==.Fretman:BAAALgADCgcJCQAAAA==.Fridgie:BAACLgAFFH8YAAITAAUJZhkzBABdAQATAAUJZhkzBABdAQAuAAQKfyMAAhMACQm6Im0PAMACABMACQm6Im0PAMACAAAA.Froline:BAAALgAECgUJCAAAAA==.Frostreaper:BAAALgAECgIJAgAAAA==.Frozenflyer:BAAALgAECgUJEAAAAA==.Frozenturtle:BAABLgAECn8gAAIbAAkJQxxjCgBhAgAbAAkJQxxjCgBhAgAAAA==.',
Ft='Ftwiamtank:BAABLgAECn8VAAIkAAYJnA5iJwDpAAAkAAYJnA5iJwDpAAAAAA==.',
Fu='Fuoco:BAAALgAECgkJCgAAAA==.Furah:BAAALgAECgEJAQAAAA==.',
Ga='Gabriél:BAAALgAECgYJCQAAAA==.Garcutt:BAACLgAFFH8fAAIVAAcJDRb8HgDrAQAVAAcJDRb8HgDrAQAuAAQKfysAAhUACQm0HXopAG0CABUACQm0HXopAG0CAAAA.Gardon:BAAALgAECgYJCgAAAA==.Gaurdinn:BAABLgAECn8uAAQdAAgJMBP8LgBzAQAdAAgJrhL8LgBzAQAiAAYJfxATEAD9AAALAAIJagJuOAA3AAABLgAECgkJHAAKAPwXAA==.',
Ge='Gebuss:BAAALgADCgQJBAAAAA==.Generickmonk:BAACLgAFFH8YAAIXAAUJox1JDABVAQAXAAUJox1JDABVAQAuAAQKfy8AAhcACQnyIiYFAPcCABcACQnyIiYFAPcCAAAA.Gensis:BAAALgADCgYJBgAAAA==.Geomatic:BAAALgAECgEJAQAAAA==.Gethsemåne:BAAALgADCgMJBQAAAA==.',
Gi='Giovannucci:BAAALgAECgEJAgAAAA==.Gitan:BAAALgADCgQJBQAAAA==.',
Gl='Gladstone:BAAALgAECgYJEQAAAA==.',
Go='Gomlvirgin:BAAALgADCgYJBgABLgAECggJIgAGAHcUAA==.Gonwean:BAAALgAECgEJAQABLgAFFAYJFAATAAkYAA==.',
Gr='Gracehimeûwû:BAABLgAFFH8FAAIaAAIJahESRgB5AAAaAAIJahESRgB5AAAAAA==.Grampsie:BAAALgAECgUJBwAAAA==.Grayeyes:BAAALgAECgMJAwAAAA==.Greenngoblin:BAAALgAECgEJAgAAAA==.Grimmlie:BAAALgADCgUJBQAAAA==.Grinzler:BAAALgADCgIJAgAAAA==.Grumpybear:BAAALgADCggJDwAAAA==.Grumpykat:BAAALgAECggJEgAAAA==.Grumpypros:BAAALgADCgUJBQAAAA==.',
Gt='Gtatedk:BAAALgAFFAEJAQAAAA==.',
Gu='Guino:BAAALgAECgUJCwAAAA==.Guinodruid:BAAALgADCgcJDgAAAA==.',
Gw='Gwenelly:BAAALgAECgEJAQAAAA==.',
Ha='Hamncheeks:BAAALgAECgEJAQAAAA==.Haptism:BAAALgADCgcJBwAAAA==.Hardeesdelux:BAAALgAECgQJBAABLgAECgcJEAAEAAAAAA==.Hardnarples:BAAALgADCgEJAQAAAA==.Hayzerade:BAAALgAECgYJCAAAAA==.Hazis:BAABLgAECn8rAAIbAAkJEyEbCACkAgAbAAkJEyEbCACkAgAAAA==.',
Hi='Highflyr:BAAALgAECgEJAQAAAA==.Hippiecritz:BAAALgADCgYJBwAAAA==.Hitokiri:BAAALgADCgMJAwAAAA==.',
Ho='Holy:BAACLgAFFH8YAAIDAAYJ/QgEBwAAAQADAAYJ/QgEBwAAAQAuAAQKfywAAgMACQmkFvMQALcBAAMACQmkFvMQALcBAAAA.Holydad:BAACLgAFFH8FAAIDAAQJzA9tDACjAAADAAQJzA9tDACjAAAuAAQKfywAAgMACAkHIKYJACcCAAMACAkHIKYJACcCAAAA.Holydust:BAAALgAECgcJEQAAAA==.Holyhoette:BAAALgADCgQJBAAAAA==.Holymoki:BAAALgADCgYJCgAAAA==.Holymoliie:BAAALgADCgEJAQAAAA==.Holyroundie:BAABLgAECn9PAAIYAAkJqBNCFwAHAgAYAAkJqBNCFwAHAgAAAA==.Holyshock:BAACLgAFFH8hAAIFAAcJRxtgDQDgAQAFAAcJRxtgDQDgAQAuAAQKfykAAgUACQlkJY8HACkDAAUACQlkJY8HACkDAAAA.Holystax:BAAALgAECgEJBAAAAA==.Honeybutter:BAACLgAFFH8hAAMRAAYJBybyAwAjAgARAAYJ9SXyAwAjAgAQAAUJ2SWzBwDDAQAuAAQKfzsAAxEACQkzJtEAAG0DABEACQkzJtEAAG0DABAABwmLHtAjADgCAAAA.Hordebreaker:BAAALgAECgYJEQAAAA==.Hotflash:BAAALgAECgEJAQAAAA==.',
Hu='Huukend:BAABLgAECn9LAAITAAkJ6yMoBQA3AwATAAkJ6yMoBQA3AwAAAA==.',
Ib='Iblindbenice:BAAALgAECgYJBgAAAA==.',
Ic='Icebabyman:BAABLgAECn8fAAIVAAgJER7kOACSAgAVAAgJER7kOACSAgAAAA==.Icedmoki:BAAALgADCgQJBAAAAA==.',
Im='Imnotspeed:BAAALgAECgcJBwAAAA==.',
In='Inanitas:BAAALgADCgcJBwAAAA==.Ineffectual:BAABLgAECn8fAAIJAAgJvBMeMgC9AQAJAAgJvBMeMgC9AQAAAA==.',
Ir='Irukox:BAAALgAECgYJDQAAAA==.',
It='Itty:BAAALgADCgcJBwAAAA==.',
Ja='Jadaveon:BAAALgAECgQJBAAAAA==.Jagger:BAAALgADCgcJCQAAAA==.Jalene:BAAALgAECgYJDwAAAA==.Janewayy:BAABLgAECn8yAAISAAkJGA3uXQBjAQASAAkJGA3uXQBjAQAAAA==.Jazmean:BAAALgAECgcJDAAAAA==.',
Je='Jeks:BAAALgADCgcJBwABLgAFFAcJIAAJANwXAA==.Jemma:BAABLgAECn8vAAIZAAkJ6hTlBQD8AQAZAAkJ6hTlBQD8AQAAAA==.Jettadari:BAACLgAFFH8RAAISAAcJ5RMXEABNAQASAAcJ5RMXEABNAQAuAAQKfyYAAxIACQlsIO0WAM0CABIACQlsIO0WAM0CAAIAAQlADuIxADAAAAAA.Jettadin:BAABLgAECn8aAAIFAAgJ9yGnDwARAwAFAAgJ9yGnDwARAwABLgAFFAcJEQASAOUTAA==.Jettakins:BAAALgAFFAEJAQABLgAFFAcJEQASAOUTAA==.Jettathyr:BAAALgAECgcJDQABLgAFFAcJEQASAOUTAA==.',
Ju='Jubba:BAABLgAECn8fAAIVAAkJ1xTuQwAJAgAVAAkJ1xTuQwAJAgAAAA==.Juderius:BAAALgADCgQJBAABLgAECgQJBQAEAAAAAA==.Junk:BAABLgAECn8sAAIbAAkJ4SK3AgAcAwAbAAkJ4SK3AgAcAwAAAA==.',
['Jë']='Jëks:BAACLgAFFH8gAAIJAAcJ3Bd9CgACAgAJAAcJ3Bd9CgACAgAuAAQKfykAAwkACQlhJXEDAEEDAAkACQlhJXEDAEEDAAwAAgkvDncvAGIAAAAA.',
Ka='Kaghroxxar:BAAALgADCgkJGgAAAA==.Kahea:BAAALgAECgQJBAAAAA==.Kaitou:BAABLgAECn82AAMWAAkJMSIJAwDgAgAWAAkJMSIJAwDgAgAlAAEJrQ6qiAAvAAAAAA==.Kalamiti:BAABLgAECn8eAAMZAAkJFRMVDABvAQAZAAgJCQ8VDABvAQAhAAcJ/hBZDgBjAQAAAA==.Kallar:BAABLgAECn84AAMYAAkJRCDoBQANAwAYAAkJRCDoBQANAwAHAAIJUQZocABSAAAAAA==.Karesh:BAAALgAECgQJBAAAAA==.Kayeera:BAABLgAECn8bAAMYAAgJ8xVpGgDnAQAYAAgJ8xVpGgDnAQAHAAQJBQUDTwCWAAAAAA==.Kayha:BAAALgADCgYJCAAAAA==.Kaylrandi:BAAALgAECgcJEwAAAA==.Kazarath:BAAALgAECgEJAQAAAA==.Kaztiel:BAAALgAECgIJAgAAAA==.',
Ke='Keadon:BAAALgAFFAEJAQAAAA==.Kearza:BAAALgAECgQJCAAAAA==.Keeper:BAAALgADCgMJAwABLgAECgkJMQAQAPQiAA==.Keh:BAAALgADCgkJCQAAAA==.Keiyona:BAAALgAECgcJCgABLgAECgkJIgAFAKodAA==.Kennethv:BAAALgAECgcJCgAAAA==.Kenze:BAAALgAECgEJAQAAAA==.Kethra:BAAALgADCggJEgAAAA==.Kev:BAAALgAECgcJBwAAAA==.',
Kh='Khel:BAAALgADCgcJBwAAAA==.Khibanee:BAAALgADCgQJBAAAAA==.Khiell:BAACLgAFFH8LAAIQAAQJgQ+SKAD/AAAQAAQJgQ+SKAD/AAAuAAQKfyIAAhAACQkmGm8ZABsCABAACQkmGm8ZABsCAAAA.',
Ki='Kilyse:BAAALgADCgYJBgAAAA==.Kinigit:BAAALgAECgYJCAABLgAFFAYJGQAlAMMZAA==.Kirïtö:BAAALgAECgUJCwAAAA==.Kitarah:BAEALgAECgIJAgABLgAECgkJEAAEAAAAAA==.Kitarazen:BAEALgAECgkJEAAAAA==.Kizli:BAAALgAECgEJAQAAAA==.',
Kn='Knoway:BAAALgAECgMJAwAAAA==.',
Ko='Kokushimosu:BAAALgAECgYJDgAAAA==.Koo:BAAALgAECgUJBwAAAA==.Koviel:BAAALgAECgEJAQAAAA==.',
Kr='Kragon:BAAALgAECggJCQAAAA==.Krátos:BAABLgAECn8oAAMRAAkJBxpLCABjAgARAAkJBxpLCABjAgAQAAgJaRF6LwCKAQAAAA==.',
Ks='Ksper:BAAALgAECgcJEgAAAA==.',
Ku='Kukalak:BAABLgAECn8YAAIkAAgJ7BvSEQDrAQAkAAgJ7BvSEQDrAQAAAA==.Kuranaa:BAAALgAECgMJAQABLgAECgQJBQAEAAAAAA==.Kurulak:BAABLgAECn82AAISAAkJHxPUNQDjAQASAAkJHxPUNQDjAQAAAA==.Kuzcotopiajr:BAAALgADCgEJAQAAAA==.',
Ky='Kymru:BAAALgADCgcJDQAAAA==.',
['Ké']='Kénnéth:BAAALgAECgYJDgAAAA==.',
La='Lacerveza:BAAALgAECgIJBQAAAA==.Lahyanhou:BAABLgAECn84AAIUAAkJawilEABBAQAUAAkJawilEABBAQAAAA==.Lalalalala:BAAALgAECgcJCgAAAA==.Lalin:BAAALgAECgEJBQAAAA==.Larkwyn:BAAALgAECgQJBAABLgAFFAUJCwAGAFkNAA==.Laylah:BAAALgADCgYJBAAAAA==.',
Le='Lebrand:BAAALgAECgEJAQAAAA==.Leriope:BAABLgAECn9RAAIGAAkJNBl3HgBnAgAGAAkJNBl3HgBnAgAAAA==.Leàf:BAABLgAECn8UAAIJAAgJfxjUHQBSAgAJAAgJfxjUHQBSAgAAAA==.',
Li='Lichfiend:BAAALgADCgEJAQAAAA==.Lightbeer:BAAALgAECgYJBwAAAA==.Lihpfu:BAAALgAECgYJBgABLgAFFAQJGAAQAJclAA==.Lihplock:BAAALgAECgQJCAABLgAFFAQJGAAQAJclAA==.Lilandri:BAAALgAECgYJBwAAAA==.Lildragonboi:BAAALgADCgUJBQAAAA==.Lilem:BAAALgADCgcJEgAAAA==.Lilpooch:BAAALgAECgYJEAAAAA==.Listenlinda:BAAALgAECgMJBQAAAA==.Lithariel:BAAALgADCgkJCAAAAA==.Littlemerald:BAAALgAECgUJEgAAAA==.',
Lj='Lj:BAABLgAECn9KAAImAAkJDB8gCgDfAgAmAAkJDB8gCgDfAgAAAA==.',
Lo='Localsingles:BAAALgADCgcJBwAAAA==.Lorath:BAAALgADCgEJAQAAAA==.Lovecrafft:BAAALgAECgMJBwAAAA==.Lovetrain:BAAALgAECgYJBQAAAA==.',
Lu='Lu:BAABLgAFFH8HAAMbAAMJzxfxOgAvAAAPAAIJzxexyACNAAAbAAIJtA7xOgAvAAABLgAFFAUJDwAeAD8SAA==.Lucinà:BAABLgAECn8+AAQFAAkJeSIMFQC8AgAFAAgJ8CMMFQC8AgAmAAkJQR+TDAC1AgADAAUJkB0gGwAxAQAAAA==.Lusande:BAAALgAECgQJBgAAAA==.Luxure:BAAALgAECgYJBgAAAA==.Luxùria:BAAALgAECgEJAQAAAA==.',
Ly='Lyndall:BAAALgAECgQJBgAAAA==.',
Ma='Machamp:BAAALgAECgYJCwAAAA==.Madammìm:BAAALgAECgYJBgAAAA==.Maegan:BAABLgAECn8WAAIFAAcJEAj4uAAGAQAFAAcJEAj4uAAGAQAAAA==.Maewyn:BAAALgAECgEJAgAAAA==.Mager:BAAALgAECgUJDQAAAA==.Magerhunter:BAAALgAECgYJCAAAAA==.Magolock:BAAALgAECgUJEgAAAA==.Mahll:BAAALgAECgMJAwAAAA==.Maidrim:BAACLgAFFH8aAAInAAcJ3xblAAAGAgAnAAcJ3xblAAAGAgAuAAQKfx8AAicACQmrIfICALICACcACQmrIfICALICAAAA.Makaveli:BAAALgAECgcJCAAAAA==.Makavelli:BAAALgADCgEJAQAAAA==.Mamajumbo:BAABLgAECn8cAAITAAkJRhwZFQCgAgATAAkJRhwZFQCgAgAAAA==.Marage:BAAALgADCgEJAQAAAA==.Marellias:BAAALgAECgMJBAABLgAFFAMJBQAFAC4dAA==.Marikel:BAAALgAECgUJEwAAAA==.Markwel:BAAALgAECgIJAgAAAA==.Marrack:BAAALgAECgYJDQAAAA==.',
Me='Melador:BAAALgADCgIJAgAAAA==.Meletha:BAAALgAECgYJDwAAAA==.Melpuis:BAAALgAECgEJAgAAAA==.Metahorfasis:BAAALgAECgUJBQAAAA==.',
Mi='Michaelken:BAABLgAECn8iAAMmAAkJDhfHFABdAgAmAAkJDhfHFABdAgAFAAEJsAeghQEvAAAAAA==.Mierín:BAAALgADCgYJBgAAAA==.Migrains:BAABLgAECn9SAAIDAAkJPSXNAABVAwADAAkJPSXNAABVAwAAAA==.Mineo:BAAALgAECgYJBwAAAA==.Mirâjâne:BAAALgAECgEJAQAAAA==.Miskaabin:BAABLgAECn8yAAMFAAgJ3RJ3XACuAQAFAAgJ3RJ3XACuAQADAAUJogolMgCPAAAAAA==.Miststress:BAAALgAECgcJCAAAAA==.',
Mo='Mobal:BAABLgAECn88AAMJAAkJhhxfEgCvAgAJAAkJhhxfEgCvAgAKAAQJxgiicwB/AAAAAA==.Modarku:BAAALgADCgQJBAAAAA==.Mojogreens:BAAALgAECgYJEQAAAA==.Montydh:BAAALgAECgEJAQAAAA==.Moonblades:BAAALgADCgUJBQAAAA==.Moonpetals:BAAALgAECgMJBAAAAA==.Moonrush:BAAALgAECgMJCAAAAA==.Mortiis:BAAALgAECgYJEwAAAA==.Motako:BAABLgAECn8gAAIJAAcJRCCfFQBoAgAJAAcJRCCfFQBoAgAAAA==.',
Mp='Mpd:BAAALgAECgcJEgAAAA==.',
My='Mybizël:BAABLgAECn8pAAITAAcJwR7oIABAAgATAAcJwR7oIABAAgAAAA==.Myrlifax:BAAALgADCgEJAQABLgAECgkJFQAFAAIVAA==.Mystique:BAABLgAECn8VAAICAAgJ4gd2EwAJAQACAAgJ4gd2EwAJAQAAAA==.Mythdaraghma:BAABLgAECn8UAAIBAAYJNQj6OADCAAABAAYJNQj6OADCAAAAAA==.',
['Má']='Máximo:BAAALgAECgYJEAAAAA==.',
['Mí']='Míerin:BAAALgAECgQJBAAAAA==.Míerín:BAACLgAFFH8VAAIoAAYJYR2YBQCfAQAoAAYJYR2YBQCfAQAuAAQKfzcAAygACQnBJQwCACwDACgACQnBJQwCACwDABMABAm+G0NgAEcBAAAA.',
['Mø']='Møøse:BAAALgAECgMJBAAAAA==.',
Na='Naama:BAAALgADCgkJKAAAAA==.Nadaar:BAABLgAECn8bAAIfAAgJWhkcAwD0AQAfAAgJWhkcAwD0AQAAAA==.Naelih:BAABLgAECn8tAAIUAAkJ+Q1bDACRAQAUAAkJ+Q1bDACRAQAAAA==.Naharuk:BAAALgADCgMJAwAAAA==.Natholomas:BAAALgADCgQJBAAAAA==.Natlès:BAAALgAECggJCwABLgAECggJFAAeAEwNAA==.Nattwenty:BAAALgAECgQJBAAAAA==.Nazeer:BAAALgADCgcJBwABLgAFFAUJCQAgAMkEAA==.Nazgrim:BAACLgAFFH8JAAIgAAUJyQStLAD7AAAgAAUJyQStLAD7AAAuAAQKfz4AAiAACAnIFlsvAO8BACAACAnIFlsvAO8BAAAA.',
Ne='Necronu:BAABLgAFFH8KAAIPAAMJDBeghwDnAAAPAAMJDBeghwDnAAABLgAFFAYJJgAdAPgZAA==.',
Ni='Nikkolos:BAABLgAECn8cAAIBAAgJ5gzWIgBOAQABAAgJ5gzWIgBOAQAAAA==.Ninjastax:BAAALgAECgEJAgAAAA==.Nissie:BAAALgAECgEJAQAAAA==.Nitazendezot:BAAALgAFFAEJAgABLgAFFAQJDgAPALsVAA==.',
No='Nogusta:BAACLgAFFH8ZAAIQAAYJNxy3DACMAQAQAAYJNxy3DACMAQAuAAQKfykAAhAACQloH2kLAP8CABAACQloH2kLAP8CAAAA.Norberta:BAABLgAECn8jAAMdAAkJBAgMNQBSAQAdAAkJ8AcMNQBSAQAiAAYJWAbxIwAIAQAAAA==.Nossanir:BAAALgAECgIJAgAAAA==.Nossellia:BAAALgAECgQJBwAAAA==.',
Nu='Nuggetssham:BAAALgADCgkJDAAAAA==.Nurana:BAAALgADCgEJAQAAAA==.',
Ny='Nycecritz:BAAALgAECgEJAQAAAA==.',
['Nä']='Näturi:BAAALgAECgQJBAAAAA==.',
Od='Odor:BAAALgAECgQJBgAAAA==.',
Ol='Oldie:BAAALgAFFAEJAQAAAA==.Olielno:BAAALgADCgMJAwAAAA==.',
On='Onlyshams:BAABLgAECn8hAAIJAAgJtBgvGQBNAgAJAAgJtBgvGQBNAgAAAA==.Onlytides:BAEBLgAECn8dAAMJAAkJ2SPlBwD2AgAJAAkJ2SPlBwD2AgAKAAcJXRiAHwAUAgABLgAFFAcJHgAgAH4bAA==.Onubis:BAACLgAFFH8QAAMTAAUJriFdJABfAQATAAUJriFdJABfAQAoAAIJ5yDuIQCsAAAuAAQKfx8ABBMACQmaHw8MAOECABMACQmOHw8MAOECABQABgnGHdk0AJcBACgAAQmkIzVRAFwAAAEuAAUUBgkmAB0A+BkA.Onuchi:BAABLgAFFH8KAAMXAAUJRRFkFQAOAQAXAAUJRRFkFQAOAQAeAAUJTwQbLgDYAAABLgAFFAYJJgAdAPgZAA==.Onulock:BAAALgAECgYJCgABLgAFFAYJJgAdAPgZAA==.Onux:BAABLgAFFH8SAAISAAYJOBt0HQCoAQASAAYJOBt0HQCoAQABLgAFFAYJJgAdAPgZAA==.',
Op='Opgarbage:BAAALgAECgQJCwAAAA==.',
Ou='Oukei:BAAALgAECgcJEgABLgAFFAYJFAAEAAAAAQ==.Oumura:BAAALgAECgYJDgAAAA==.',
Ov='Overlordainz:BAABLgAECn8UAAMIAAYJeBOMMQBHAQAIAAYJ7hCMMQBHAQAYAAQJLxPjVgDaAAAAAA==.',
Pa='Paarthürnax:BAAALgAECgYJDAAAAA==.Padamee:BAAALgAECgQJBwAAAA==.Paganini:BAAALgAECgQJBAABLgAECgkJHwATAHUdAA==.Pallyoop:BAABLgAECn8WAAImAAcJMg+TUgDiAAAmAAcJMg+TUgDiAAAAAA==.Pandaa:BAAALgAECgEJAQAAAA==.Papapaw:BAAALgAECgQJBgAAAA==.Pathator:BAAALgAECgEJAQABLgAECgkJGQAPAAYdAA==.Pathaviendha:BAAALgAECgQJAQAAAA==.Patherion:BAAALgADCgEJAQABLgAECgkJGQAPAAYdAA==.Patholans:BAABLgAECn8ZAAIPAAkJBh3ZGACqAgAPAAkJBh3ZGACqAgAAAA==.Pathology:BAAALgAECgMJAwABLgAECgkJGQAPAAYdAA==.Paxman:BAAALgAECgQJBwAAAA==.',
Pe='Peanits:BAAALgAECgQJCwABLgAECgkJIwACAJciAA==.Peanutsuckr:BAACLgAFFH8hAAIbAAcJGiCZBQAdAgAbAAcJGiCZBQAdAgAuAAQKfykAAhsACQnGJdkBADoDABsACQnGJdkBADoDAAAA.Pearserve:BAAALgADCgYJBgABLgAECggJFAAKANoPAA==.',
Ph='Phantöm:BAAALgAECgQJDAAAAA==.Phosphate:BAABLgAECn8QAAISAAYJNxKvbgBYAQASAAYJNxKvbgBYAQAAAA==.',
Pi='Piccolo:BAAALgAECgQJBgAAAA==.Pingg:BAAALgAECgQJBQAAAA==.Pinkeye:BAAALgAECgcJCgAAAA==.Pippafan:BAAALgAECgEJAQABLgAECgEJAwAEAAAAAA==.',
Pl='Placcid:BAABLgAECn9DAAITAAkJIh1gFACkAgATAAkJIh1gFACkAgAAAA==.Planknstein:BAAALgADCgMJAwAAAA==.Playdohh:BAAALgAECgcJCQAAAA==.Plutonia:BAAALgAECgMJBwAAAA==.',
Po='Pockett:BAABLgAECn8hAAMKAAcJKBHYOwA2AQAKAAcJKBHYOwA2AQAMAAUJBQnnGwAMAQAAAA==.Powrwordgoat:BAACLgAFFH8LAAIIAAMJrwl+MAC1AAAIAAMJrwl+MAC1AAAuAAQKfy8AAggACQleFGwWABcCAAgACQleFGwWABcCAAAA.',
Pr='Prestoh:BAABLgAECn8rAAIKAAkJCBFBJwCkAQAKAAkJCBFBJwCkAQAAAA==.Prismclaw:BAABLgAECn9JAAIVAAkJyBRYOwAmAgAVAAkJyBRYOwAmAgAAAA==.Prisoner:BAAALgAECgEJAwAAAA==.Processing:BAAALgAECgYJBgAAAA==.',
Ps='Pseudoruski:BAAALgADCgMJAwAAAA==.',
Pu='Purplehaze:BAAALgAECgQJBAAAAA==.',
Pv='Pvlolz:BAABLgAECn8ZAAIYAAkJ3QpDMACAAQAYAAkJ3QpDMACAAQAAAA==.',
Pw='Pwnstarz:BAAALgAECgYJBwAAAA==.',
Py='Pyrada:BAABLgAECn8VAAMCAAkJxRbOCADWAQACAAgJAhfOCADWAQASAAgJJBTrOwDMAQAAAA==.',
Qa='Qaharn:BAAALgAECgQJBwAAAA==.',
Qp='Qplus:BAABLgAECn8iAAITAAkJ5Ag8VQCXAQATAAkJ5Ag8VQCXAQAAAA==.',
Qu='Quackadilly:BAAALgADCgcJDQAAAA==.Quaenie:BAABLgAECn8hAAIYAAkJ7hb4FAAgAgAYAAkJ7hb4FAAgAgAAAA==.Quintin:BAABLgAECn8VAAIiAAgJIw4zCgBwAQAiAAgJIw4zCgBwAQAAAA==.',
Ra='Raged:BAAALgAECgUJCgAAAA==.Ragegauge:BAAALgAECgQJBgAAAA==.Ragetotem:BAABLgAECn8hAAIKAAYJmRwgKADSAQAKAAYJmRwgKADSAQAAAA==.Ragewarg:BAAALgAFFAEJAQAAAA==.Ragnashock:BAAALgAECgQJBgAAAA==.Ralvarr:BAABLgAECn8aAAIeAAgJIBimGwDbAQAeAAgJIBimGwDbAQAAAA==.Raptorjésus:BAAALgADCgcJCwAAAA==.Rastik:BAAALgADCgIJAgAAAA==.Rathaes:BAAALgADCgMJAwAAAA==.Ravenstryke:BAAALgAECgEJAQAAAA==.Raylea:BAAALgADCgcJBwAAAA==.Rayleigh:BAAALgAECgcJDQABLgAECgUJCwAEAAAAAA==.Razzgix:BAAALgAECgUJBgAAAA==.',
Re='Redchord:BAAALgADCgUJDAAAAA==.Regidør:BAABLgAECn8ZAAMmAAgJ/CBcCADoAgAmAAgJ/CBcCADoAgAFAAYJxx0XYQDBAQAAAA==.Relik:BAABLgAECn8jAAIkAAkJjwz0GABoAQAkAAkJjwz0GABoAQAAAA==.Resith:BAAALgAECgYJCAAAAA==.',
Rh='Rhaelia:BAABLgAECn8ZAAIFAAcJFQnhtwAHAQAFAAcJFQnhtwAHAQAAAA==.Rhaspus:BAAALgADCgQJBAAAAA==.',
Ri='Rilliccine:BAAALgADCgkJCwAAAA==.Rillinetti:BAABLgAECn8mAAIGAAkJQBQiNAADAgAGAAkJQBQiNAADAgAAAA==.Rillini:BAAALgADCgcJBwAAAA==.Rilliti:BAAALgAECgYJEwAAAA==.',
Ro='Rondon:BAABLgAECn80AAITAAkJvCUpAgBqAwATAAkJvCUpAgBqAwAAAA==.Rookdh:BAACLgAFFH8OAAMBAAUJvQZeFQDeAAABAAQJUQReFQDeAAASAAUJogZ5VQDbAAAuAAQKfykAAxIACQnkFpxYAHEBABIACAk+GJxYAHEBAAEABwkyFucsAGMBAAAA.Rorcia:BAAALgADCgcJFAAAAA==.Rosey:BAABLgAECn8sAAIFAAkJcxXGOgANAgAFAAkJcxXGOgANAgAAAA==.Rotmaxxer:BAAALgAFFAQJBAAAAA==.Roxania:BAAALgADCgYJBgAAAA==.Royale:BAAALgAECgcJBwAAAA==.',
Ru='Rudyeightbal:BAABLgAECn8bAAMGAAgJCQzWlAANAQAGAAYJhw3WlAANAQAZAAIJFQOoQgAgAAAAAA==.Ruedons:BAAALgAECgMJAwAAAA==.Rugsalon:BAACLgAFFH8IAAIVAAMJCwmOgwDJAAAVAAMJCwmOgwDJAAAuAAQKfycAAhUACQn1HPM0AJ8CABUACQn1HPM0AJ8CAAAA.Rustedbarrel:BAACLgAFFH8IAAIaAAMJqwsPOgCyAAAaAAMJqwsPOgCyAAAuAAQKfxsAAhoACQmnE3YhAPYBABoACQmnE3YhAPYBAAAA.',
Ry='Ryptar:BAAALgADCgkJHAAAAA==.',
['Rè']='Rèaper:BAAALgAECgMJAwAAAA==.',
['Ré']='Réxxar:BAABLgAECn8cAAINAAcJPRTbDQClAQANAAcJPRTbDQClAQAAAA==.',
Sa='Saelyres:BAABLgAECn8hAAMCAAkJyhzPAwCHAgACAAkJyhzPAwCHAgABAAEJ1wNHegApAAAAAA==.Sagesse:BAAALgADCgYJBgAAAA==.Saikye:BAAALgAECgEJAQAAAA==.Sairu:BAAALgADCgEJAQAAAA==.Saisera:BAAALgAFFAIJAwAAAA==.Samistraza:BAAALgADCgEJAQAAAA==.Sammy:BAABLgAECn8jAAIFAAkJvQlegQBhAQAFAAkJvQlegQBhAQAAAA==.Santaclaaws:BAACLgAFFH8RAAISAAQJXxtINAA9AQASAAQJXxtINAA9AQAuAAQKfzUABBIACQmkIkcTAJ4CABIACQmkIkcTAJ4CAAIAAwldFpQaALgAAAEAAgk1GY5bAHIAAAAA.Santapal:BAACLgAFFH8IAAMmAAQJiRbFHQAlAQAmAAQJiRbFHQAlAQAFAAEJ3gEvuAA2AAAuAAQKfy0ABCYACAkOGrImAMoBACYABwmhGrImAMoBAAUAAgl6BURcAUkAAAMAAglpEnRKADUAAAEuAAUUBAkRABIAXxsA.Santatumblr:BAACLgAFFH8GAAMeAAMJdh3pJgAJAQAeAAMJdh3pJgAJAQAXAAEJLgyaPQA7AAAuAAQKfxoABB4ACAlRG2QUAGYCAB4ACAlRG2QUAGYCABcABAlyEKdqAG4AABoAAQlNA2OiABwAAAEuAAUUBAkRABIAXxsA.Santhin:BAAALgADCgcJCgAAAA==.Saphira:BAAALgAECgQJBAAAAA==.Sareit:BAABLgAECn8cAAMIAAcJHw6JOQAdAQAIAAYJIQyJOQAdAQAHAAYJAhI/OwAcAQAAAA==.Sassee:BAAALgAECgQJCAAAAA==.Sayvil:BAAALgAECgUJCwABLgAECgkJOAAYAEQgAQ==.',
Sc='Scripture:BAAALgADCgYJBgAAAA==.',
Se='Seawolph:BAABLgAECn85AAIJAAkJBRmpFwCAAgAJAAkJBRmpFwCAAgAAAA==.Selenia:BAAALgAECgMJAwAAAA==.Semmers:BAAALgAECgkJCQAAAA==.Sensational:BAABLgAECn8aAAMeAAcJWhx+EwAvAgAeAAcJWhx+EwAvAgAXAAUJZwgFVgCoAAAAAA==.Sergio:BAAALgAECgcJCgAAAA==.Seyren:BAABLgAFFH8FAAIRAAMJygcBJwC4AAARAAMJygcBJwC4AAAAAA==.',
Sh='Shamiska:BAAALgAECgcJDgAAAA==.Shammerdown:BAAALgAECgIJAwAAAA==.Shampooh:BAAALgAECgQJBQABLgAECgcJFgAgAMYEAA==.Shamtastyk:BAAALgAECgQJBAAAAA==.Shaokhan:BAABLgAECn8qAAMJAAkJiSElBwAyAwAJAAkJiSElBwAyAwAMAAcJuwrkGAAuAQAAAA==.Sheilla:BAAALgADCgUJBQAAAA==.Shian:BAABLgAECn86AAINAAkJhhV0DQD6AQANAAkJhhV0DQD6AQAAAA==.Shieldee:BAABLgAECn8uAAMFAAgJUxycQQD3AQAFAAgJUxycQQD3AQAmAAEJTgNslwAiAAAAAA==.Shiftystax:BAAALgAECgEJAQAAAA==.Shlectrinell:BAABLgAECn9LAAMjAAkJ7A5jFwDUAQAjAAkJ7A5jFwDUAQAnAAgJBAUICwB+AQAAAA==.Shockeei:BAACLgAFFH8eAAMVAAYJACHlDgCiAQAVAAYJACHlDgCiAQApAAEJ6g9QBgA5AAAuAAQKfykABBUACQkqJVUIADUDABUACQkqJVUIADUDACkAAwlSGHcJALkAAB8AAQnWIAURAFYAAAAA.Shocktroop:BAAALgADCgYJCgAAAA==.Shortdon:BAAALgAECgEJAQAAAA==.Shortebread:BAAALgAFFAIJAgAAAA==.Shurp:BAAALgAECgMJAwAAAA==.',
Si='Siakora:BAABLgAECn8VAAIjAAgJXRgLGwAoAgAjAAgJXRgLGwAoAgABLgAFFAcJIQAlAKkaAA==.Sicksty:BAAALgADCgcJBwAAAA==.Sighh:BAAALgAECgYJBwAAAA==.Sighhy:BAAALgAECgYJDwAAAA==.Sijth:BAACLgAFFH8HAAIFAAMJYBTJWQDnAAAFAAMJYBTJWQDnAAAuAAQKf1YAAgUACQlGIjINAPMCAAUACQlGIjINAPMCAAAA.Silentchaos:BAAALgADCgMJBQAAAA==.Siler:BAAALgADCgYJBgAAAA==.Silverwar:BAABLgAECn8sAAIQAAkJFxwTDgCIAgAQAAkJFxwTDgCIAgAAAA==.Simmi:BAECLgAFFH8eAAIgAAcJfhscBwBvAgAgAAcJfhscBwBvAgAuAAQKfykAAiAACQnBJcgFAFQDACAACQnBJcgFAFQDAAAA.Sinnis:BAAALgAECgEJAQAAAA==.Sirlavan:BAAALgAECgUJBQAAAA==.Sixte:BAAALgAECgcJCwAAAA==.Sixtea:BAABLgAECn8sAAIKAAkJEh2YCwCdAgAKAAkJEh2YCwCdAgAAAA==.',
Sk='Skarredd:BAAALgADCgkJEQAAAA==.Skellington:BAAALgAECgEJAQAAAA==.Skepti:BAABLgAECn8qAAITAAkJiBoaIQBWAgATAAkJiBoaIQBWAgAAAA==.Skysong:BAAALgAECgMJAwAAAA==.',
Sl='Slapdemhoes:BAAALgAECgcJAgAAAA==.Slimfoo:BAAALgAECgcJDQAAAA==.Slunkyspit:BAAALgADCgUJCAAAAA==.Slybearclaw:BAAALgADCgUJBQAAAA==.Slyeulogy:BAAALgAECggJDQAAAA==.',
Sm='Smeeta:BAACLgAFFH8IAAIPAAMJ4BkPhgDpAAAPAAMJ4BkPhgDpAAAuAAQKf14ABA8ACQmHJNoNAPUCAA8ACQkxJNoNAPUCABwACAldIxEDALQCABsABQlQERc2ALMAAAAA.Smoak:BAAALgADCgUJBQAAAA==.Smolderlight:BAACLgAFFH8IAAImAAQJLBImIQAJAQAmAAQJLBImIQAJAQAuAAQKfz0AAiYACQmTFWAaACcCACYACQmTFWAaACcCAAAA.Smoochiebutt:BAAALgAECgUJCQAAAA==.',
So='Solaace:BAAALgAECgEJAQABLgAECgcJFgAbANQSAA==.Solo:BAAALgAECgYJCQAAAA==.Soloris:BAAALgADCgcJCAAAAA==.Sonja:BAAALgAECgcJBwAAAA==.Soram:BAAALgAECgYJCgAAAA==.Soulstryker:BAAALgAECgEJAQAAAA==.Soùl:BAAALgAECgIJAgAAAA==.',
Sp='Spacepants:BAAALgAECgEJAQAAAA==.Spurgeon:BAAALgAECgEJAQAAAA==.',
St='Staraelle:BAAALgAECgEJAgAAAA==.Stazz:BAAALgAECgYJBgAAAA==.Steelerayne:BAAALgAECggJEQAAAA==.Stormii:BAABLgAECn8iAAMJAAkJKA4CUABjAQAJAAgJTQwCUABjAQAKAAMJfhRKXwC2AAAAAA==.Strangelock:BAAALgAECgYJBgABLgAECgkJMgAPALoNAA==.Strangerdk:BAABLgAECn8yAAIPAAkJug0uWAC1AQAPAAkJug0uWAC1AQAAAA==.Streetdog:BAAALgADCgYJBgAAAA==.Stublin:BAAALgADCgEJAQAAAA==.Stuggens:BAAALgADCgkJCQAAAA==.',
Su='Suggondeez:BAAALgAECgYJBwAAAA==.Superfatbaby:BAABLgAECn8dAAIQAAkJKhNCJQDGAQAQAAkJKhNCJQDGAQAAAA==.',
Sw='Swikk:BAAALgADCgYJCAAAAA==.Swishersweet:BAABLgAECn8qAAINAAkJlgnGJgAMAQANAAkJlgnGJgAMAQAAAA==.Swordfish:BAABLgAECn8eAAIiAAgJJyF5AgCOAgAiAAgJJyF5AgCOAgAAAA==.',
Sy='Syannae:BAAALgADCgYJBwAAAA==.Sybros:BAAALgADCgEJAQAAAA==.Sydonie:BAAALgAECgEJBgAAAA==.Sylus:BAAALgAECgQJBAAAAA==.Symbah:BAAALgADCgYJBgAAAA==.Synvalid:BAABLgAECn8gAAISAAkJ9wdEhAAKAQASAAkJ9wdEhAAKAQAAAA==.Syzrin:BAAALgADCgEJAQABLgAECggJIgAGAHcUAA==.',
Ta='Tabrieus:BAABLgAECn9JAAIVAAkJ5yGnCgAfAwAVAAkJ5yGnCgAfAwAAAA==.Tadokof:BAAALgADCgkJIwAAAA==.Talanth:BAABLgAECn8XAAInAAkJ0AhVCgCIAQAnAAkJ0AhVCgCIAQAAAA==.Talya:BAAALgAECggJCAABLgAECgkJOgANAIYVAA==.Tandisong:BAAALgAECgcJCAAAAA==.Tanknhammerm:BAAALgADCgYJBgAAAA==.Tanknstein:BAAALgADCgYJBgAAAA==.Tanton:BAAALgAECgMJAwAAAA==.Tanzil:BAAALgAECgYJDgAAAA==.Tardigrade:BAAALgAECggJEwAAAA==.Tareyna:BAABLgAECn8hAAIFAAkJeBOHPgABAgAFAAkJeBOHPgABAgAAAA==.Tayon:BAAALgAECggJEwAAAA==.Tayvin:BAAALgAECgUJEAAAAA==.Tazanath:BAAALgADCgEJAgABLgADCgcJFAAEAAAAAA==.',
Te='Tempest:BAAALgADCgcJBwAAAA==.Tengen:BAAALgAECgUJDAAAAA==.Termana:BAACLgAFFH8hAAIkAAYJiyDrAgBxAQAkAAYJiyDrAgBxAQAuAAQKfygAAiQACQmCJGoCABoDACQACQmCJGoCABoDAAAA.',
Th='Thanel:BAAALgADCgQJBAAAAA==.Tharja:BAABLgAECn8bAAIVAAkJXhvvNACfAgAVAAkJXhvvNACfAgAAAA==.Theodyn:BAAALgAECgQJBAAAAA==.Thornp:BAAALgAECgEJAgAAAA==.Thoronk:BAAALgAECgcJBgAAAA==.Thsaric:BAAALgAECgEJAQAAAA==.Thug:BAABLgAECn8WAAMQAAcJ0R/RJQArAgAQAAcJ0R/RJQArAgAkAAIJHxvRNgCRAAAAAA==.Thuggin:BAAALgAECgQJBQAAAA==.',
Ti='Tiferet:BAABLgAECn81AAQYAAkJ+iEQBAA+AwAYAAkJ+iEQBAA+AwAHAAgJQAuGLQBlAQAIAAQJzxdwSADSAAAAAA==.Tigiw:BAAALgAECgMJBAAAAA==.Tinysunshine:BAABLgAECn8VAAIXAAgJMRwGEQAzAgAXAAgJMRwGEQAzAgAAAA==.Tinyt:BAAALgAECgEJAQAAAA==.Tiramisu:BAAALgAECgUJBQAAAA==.Tismtwo:BAAALgAECgEJAQAAAA==.Tismyhammer:BAAALgADCgQJBAAAAA==.',
To='Toasted:BAAALgADCgQJAQAAAA==.Tolenkar:BAABLgAECn8fAAITAAkJdR3jGgB4AgATAAkJdR3jGgB4AgAAAA==.Tomato:BAACLgAFFH8YAAMZAAYJNxDaBwDxAAAGAAUJwxGPSwAiAQAZAAQJxA3aBwDxAAAuAAQKfyMAAxkACQlpHaYFAHoCABkACAkIHKYFAHoCAAYABQlZF4aWAAsBAAAA.Tomhanks:BAABLgAECn8VAAIFAAkJAhUPNwAaAgAFAAkJAhUPNwAaAgAAAA==.Tormentaa:BAAALgAECgYJBwAAAA==.Torvalar:BAABLgAECn9UAAIFAAkJSxqVIwBtAgAFAAkJSxqVIwBtAgAAAA==.',
Tr='Treemendous:BAAALgADCgYJCQAAAA==.Trolgoskill:BAAALgADCgQJBAAAAA==.Truthslayer:BAABLgAECn8cAAMQAAkJKAmcRgAhAQAQAAkJKAmcRgAhAQARAAEJcgr/QgAzAAAAAA==.Trûth:BAABLgAECn8WAAIHAAgJxBBMIwC9AQAHAAgJxBBMIwC9AQAAAA==.',
Tu='Tugzug:BAAALgAECgEJAQAAAA==.Turdyl:BAABLgAECn8sAAIFAAkJuhGvZQCZAQAFAAkJuhGvZQCZAQAAAA==.',
Tw='Twindad:BAAALgADCgkJEQAAAA==.Twindadlock:BAAALgAECgEJAgAAAA==.Twowheels:BAAALgAECgQJBQAAAA==.',
Ty='Tyraz:BAAALgAECgcJEwAAAA==.Tystrolf:BAABLgAECn8YAAQlAAcJrg2AQgD1AAAlAAYJ/w6AQgD1AAAWAAUJjAeDMQCFAAANAAIJgAl9ZgA2AAAAAA==.',
Tz='Tzar:BAAALgADCgIJAgAAAA==.',
['Tô']='Tôx:BAABLgAECn8XAAMKAAcJWB1YLQCwAQAKAAcJWB1YLQCwAQAJAAIJRhRpyAA1AAAAAA==.',
Ub='Ubrew:BAAALgAECgkJBQAAAA==.',
Ud='Udyrr:BAAALgADCgIJAgAAAA==.',
Ul='Ulfius:BAAALgADCgMJAwAAAA==.Ullume:BAAALgAECgkJDQAAAA==.',
Um='Umbranwings:BAAALgAECgUJBQAAAA==.',
Un='Unheardjp:BAAALgAECgMJCwAAAA==.Unholy:BAAALgAECgIJAgAAAA==.Unholyarnix:BAAALgAECgQJDQAAAA==.',
Ur='Ursus:BAAALgADCgYJBgAAAA==.Uruloki:BAAALgAECgEJAQAAAA==.',
Va='Vacuum:BAAALgAECgYJEQAAAA==.Vadican:BAAALgADCgQJBAAAAA==.Vaerix:BAABLgAECn8sAAIdAAkJWw/BKgCLAQAdAAkJWw/BKgCLAQAAAA==.Valdora:BAAALgAECgEJAQAAAA==.Valhals:BAABLgAECn84AAMaAAkJSAuGKQBgAQAaAAkJGQmGKQBgAQAXAAMJUQ7KcABhAAAAAA==.Valydrin:BAABLgAECn9SAAIYAAkJ9B3nCQC8AgAYAAkJ9B3nCQC8AgAAAA==.Vanhelsinky:BAAALgADCgIJAgAAAA==.Vanquished:BAAALgAECgIJBAAAAA==.Varyn:BAAALgADCgIJAgAAAA==.',
Ve='Velandia:BAAALgAECgcJDAAAAA==.Ventis:BAAALgAECgQJBwAAAA==.',
Vi='Vicara:BAAALgADCgYJBgAAAA==.Virgl:BAAALgAECgkJBQAAAA==.',
Vo='Voidifphat:BAAALgAECggJEAAAAA==.Voidtorrent:BAAALgAECgQJCAAAAA==.Voidvanquish:BAAALgAECgYJBwAAAA==.Vorkhan:BAAALgADCgUJCAAAAA==.',
Vu='Vuldrak:BAAALgAECggJEwAAAA==.',
Vy='Vysis:BAACLgAFFH8QAAQHAAMJeQlgJAC9AAAHAAMJeQlgJAC9AAAIAAMJUAlrMQCwAAAYAAIJ1AwHDgCOAAAuAAQKf1YABAcACQnyHeEJAKwCAAcACQnyHeEJAKwCABgACQlPG4cSAEwCAAgACAloFasWABUCAAAA.',
['Vä']='Vännic:BAAALgADCgEJAwAAAA==.Vännìc:BAAALgADCgEJAQAAAA==.',
['Ví']='Ví:BAABLgAECn8fAAIXAAkJsQqZKgBaAQAXAAkJsQqZKgBaAQAAAA==.',
Wh='Whatfoxsay:BAAALgADCgEJAQAAAA==.Whats:BAAALgADCgcJBwABLgAECgcJEgAEAAAAAA==.When:BAAALgADCgQJBAAAAA==.Whicker:BAAALgAECgUJBgAAAA==.Whipsnchains:BAAALgAECgUJBgAAAA==.Whipsntricks:BAAALgAECgQJBgAAAA==.',
Wi='Wickèr:BAACLgAFFH8IAAIaAAMJ7Q1aNwC9AAAaAAMJ7Q1aNwC9AAAuAAQKfzgAAxoACQkHHqMIAKACABoACQkHHqMIAKACABcAAQnIF4GEAEQAAAAA.Wieldblade:BAABLgAECn83AAMFAAkJsh1TJQBkAgAFAAkJsh1TJQBkAgADAAgJiBbfDgDJAQAAAA==.Wilsondk:BAAALgAECgEJAwAAAA==.Winslett:BAAALgADCgQJBAAAAA==.',
Wo='Woggo:BAAALgAECgEJAQAAAA==.Wolfemoon:BAABLgAECn8UAAITAAgJwwpBcQBSAQATAAgJwwpBcQBSAQAAAA==.Worganlefey:BAAALgAECgMJBwABLgAECgkJUQAGADQZAA==.',
Wr='Wrexd:BAABLgAECn8qAAIGAAgJChvLQQDRAQAGAAgJChvLQQDRAQAAAA==.',
Wu='Wunderbar:BAABLgAECn86AAMKAAkJcSCfBgDoAgAKAAkJcSCfBgDoAgAJAAgJWBniIAA9AgAAAA==.',
Wy='Wyldfire:BAACLgAFFH8ZAAQlAAYJwxk4GQA5AQAlAAUJlhg4GQA5AQAgAAEJ/AbnYwBGAAANAAEJHgrAOAAqAAAuAAQKfy8AAyUACQleI/kLANgCACUACQleI/kLANgCACAAAwksEo2eAI4AAAAA.Wyndclaw:BAABLgAECn8WAAIeAAYJcBbrNACJAQAeAAYJcBbrNACJAQAAAA==.',
Xa='Xanith:BAABLgAECn8tAAIQAAgJehgNHwDwAQAQAAgJehgNHwDwAQAAAA==.',
Xe='Xebubble:BAAALgADCgEJAQABLgAECgEJAQAEAAAAAA==.Xemonk:BAAALgAECgEJAQAAAA==.',
Xi='Xia:BAAALgADCgYJBgAAAA==.',
Xr='Xroi:BAAALgAECgIJAgAAAA==.',
Ya='Yaganor:BAAALgADCgUJBgAAAA==.',
Ye='Yeto:BAAALgADCgYJBwAAAA==.',
Yi='Yia:BAAALgAECgUJCQABLgAECgUJEgAEAAAAAA==.Yilnara:BAABLgAECn8bAAISAAkJDgdTeAAjAQASAAkJDgdTeAAjAQAAAA==.',
Ys='Ysa:BAABLgAECn8eAAMXAAcJuCShEAB3AgAXAAcJuCShEAB3AgAeAAEJlA2UbAApAAAAAA==.',
Za='Zajindor:BAAALgADCgEJAQAAAA==.Zarathul:BAAALgADCgIJAgAAAA==.',
Ze='Zekkun:BAAALgAECgEJAQAAAA==.',
Zh='Zheria:BAAALgAECgQJBAAAAA==.',
Zi='Zirael:BAAALgADCgYJCgAAAA==.',
Zo='Zod:BAAALgAECgkJCQAAAA==.Zoganian:BAEALgAECgUJEgABLgAECgkJJwAYAAUhAA==.Zogula:BAEBLgAECn8nAAQYAAkJBSHjCgCsAgAYAAkJ0iDjCgCsAgAHAAQJXxYkPwAMAQAIAAEJaiP0YABgAAAAAA==.',
Zu='Zu:BAAALgAECgcJEAAAAA==.',
Zy='Zynara:BAAALgAECgYJCAAAAA==.',
['År']='Årtemis:BAABLgAECn8xAAIoAAgJwB3iDABTAgAoAAgJwB3iDABTAgAAAA==.',
['Æb']='Æbony:BAAALgADCgMJAwAAAA==.',
['Ïr']='Ïrini:BAAALgAECgIJAwABLgAECggJFAAeAEwNAA==.',
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
