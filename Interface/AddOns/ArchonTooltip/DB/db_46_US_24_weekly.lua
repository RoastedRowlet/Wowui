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

local lookup = {'DemonHunter-Havoc','DemonHunter-Vengeance','Paladin-Protection','Unknown-Unknown','Paladin-Retribution','Warlock-Destruction','Warlock-Demonology','Priest-Shadow','Priest-Discipline','Shaman-Restoration','Shaman-Elemental','Evoker-Preservation','Shaman-Enhancement','Druid-Guardian','Rogue-Outlaw','DeathKnight-Unholy','Warrior-Fury','Warrior-Arms','DemonHunter-Devourer','Hunter-BeastMastery','Hunter-Marksmanship','Mage-Frost','Druid-Feral','Monk-Windwalker','Priest-Holy','Monk-Brewmaster','DeathKnight-Blood','DeathKnight-Frost','Evoker-Augmentation','Monk-Mistweaver','Mage-Arcane','Druid-Restoration','Warlock-Affliction','Evoker-Devastation','Rogue-Subtlety','Warrior-Protection','Druid-Balance','Paladin-Holy','Rogue-Assassination','Hunter-Survival','Mage-Fire',}
local provider = {region='US',realm='AzjolNerub',name='US',type='weekly',zone=46,date='2026-06-20',data={Ad='Adapt:BAAALgAECgMJCQAAAA==.Addy:BAACLgAFFH8GAAIBAAMJuxe7FgDtAAABAAMJuxe7FgDtAAAuAAQKf0MAAwEACQloI64CADcDAAEACQloI64CADcDAAIAAQlCCGU6ACEAAAAA.',
Ae='Aeonis:BAAALgAECgQJDgAAAA==.Aestian:BAABLgAECn8xAAIDAAkJ5Rn9DAD1AQADAAkJ5Rn9DAD1AQAAAA==.',
Ag='Agamesh:BAAALgADCgUJCQAAAA==.',
Ah='Ahoma:BAAALgADCgkJBgAAAA==.',
Ai='Ailysely:BAAALgADCgUJBQABLgAECgQJDgAEAAAAAA==.Airees:BAABLgAECn8iAAIFAAcJOx7oQQAfAgAFAAcJOx7oQQAfAgAAAA==.Aispere:BAABLgAECn8UAAMGAAYJRAVUJACQAAAGAAYJRAVUJACQAAAHAAMJqwDGYwEdAAAAAA==.',
Al='Alastria:BAAALgADCgcJBwAAAA==.Alektra:BAAALgADCgUJBwAAAA==.Alerzhulan:BAABLgAECn8bAAIHAAkJMguLWwCLAQAHAAkJMguLWwCLAQAAAA==.Allanquatre:BAAALgAECgYJBgAAAA==.Alledria:BAACLgAFFH8FAAIFAAQJBwT/dADKAAAFAAQJBwT/dADKAAAuAAQKfxoAAgUACAmaElF5AHwBAAUACAmaElF5AHwBAAAA.Allenaena:BAAALgAECgMJBgAAAA==.Alorely:BAABLgAECn8hAAMIAAkJ/gwCMQBZAQAIAAgJ0A0CMQBZAQAJAAcJoxNiMQBWAQAAAA==.Altonas:BAAALgAECgMJBAAAAA==.',
Am='Amanara:BAAALgAECgcJEAAAAA==.Amillah:BAAALgAECgQJBgAAAA==.Amooka:BAAALgAECgEJAQAAAA==.',
An='Ancientmonk:BAAALgAECgEJAQABLgAECgYJCQAEAAAAAA==.Anciientpaw:BAABLgAECn8iAAMKAAkJGyBlHQAvAgAKAAkJGyBlHQAvAgALAAUJbBUUWwDTAAAAAA==.Andramalyus:BAABLgAECn8pAAIHAAgJ3AwscABaAQAHAAgJ3AwscABaAQAAAA==.Andrasomnium:BAABLgAECn8WAAIMAAgJ/QeAAAAWAQAMAAgJ/QeAAAAWAQAAAA==.Angbar:BAABLgAECn8wAAIMAAkJeRYvCQBXAgAMAAkJeRYvCQBXAgAAAA==.Anguirus:BAABLgAECn88AAMLAAkJfAXSTgD7AAALAAkJWwXSTgD7AAANAAYJAgN+LQCNAAAAAA==.Animà:BAAALgAECgYJDwAAAA==.Ankhnstein:BAAALgAECgQJBAAAAA==.Antiheroo:BAAALgAECgUJCAAAAA==.Antoine:BAAALgAECgIJAgAAAA==.Anuksunàmun:BAAALgAECgkJBgAAAA==.',
Ap='Apolloni:BAAALgAECgIJAgABLgAECgkJMgAOABYKAA==.Appynoxusrog:BAABLgAECn8cAAIPAAYJuhguBQCcAQAPAAYJuhguBQCcAQAAAA==.',
Aq='Aqulenas:BAABLgAFFH8FAAIQAAMJsRNtngDWAAAQAAMJsRNtngDWAAAAAA==.',
Ar='Arakhan:BAAALgAFFAEJAQAAAA==.Arasaka:BAAALgAECgQJCAAAAA==.Arcadian:BAABLgAECn8zAAMRAAkJHB2bEABzAgARAAkJHB2bEABzAgASAAEJzAfURAAvAAAAAA==.Arcadiann:BAABLgAECn8XAAIRAAcJ3xYyLQCdAQARAAcJ3xYyLQCdAQAAAA==.Arcadin:BAAALgAECgEJAgAAAA==.Arcoyflecha:BAAALgAECgYJCwAAAA==.Arextheelder:BAAALgAFFAEJAQAAAA==.Aridas:BAABLgAECn8dAAMTAAgJJBhuMwAsAgATAAgJJBhuMwAsAgABAAIJRQsGYABiAAABLgAECgkJKAASAAcaAA==.Arikdeath:BAABLgAECn8pAAMUAAkJlRcMLQAoAgAUAAcJbxgMLQAoAgAVAAcJTgzdFQAKAQAAAA==.Armorscales:BAACLgAFFH8UAAIHAAYJ+xrfLACSAQAHAAYJ+xrfLACSAQAuAAQKfy0AAgcACQm/IVgQAPcCAAcACQm/IVgQAPcCAAAA.Arniix:BAAALgAECgEJAQABLgAECgQJDQAEAAAAAA==.Arnixskitty:BAAALgAECgEJAQABLgAECgQJDQAEAAAAAA==.Arnixx:BAAALgAECgQJDQAAAA==.Arntraz:BAAALgADCgkJSAAAAA==.Aryel:BAAALgADCgYJBgAAAA==.Arçadia:BAAALgAECgMJBgAAAA==.',
As='Ashegen:BAAALgAECgQJBAAAAA==.Ashnikko:BAAALgAECgEJAQAAAA==.Ashtori:BAAALgADCgEJAgAAAA==.Asis:BAAALgAECgEJAQAAAA==.Asprika:BAABLgAFFH8FAAIIAAQJXwjWIADtAAAIAAQJXwjWIADtAAAAAA==.Astayoni:BAAALgADCgEJAQAAAA==.Astrine:BAACLgAFFH8UAAIWAAYJyBbCPgBzAQAWAAYJyBbCPgBzAQAuAAQKfysAAhYACQlJIAYiAOsCABYACQlJIAYiAOsCAAAA.',
Au='Auberon:BAABLgAECn8oAAIXAAkJ/xl6BgCSAgAXAAkJ/xl6BgCSAgAAAA==.Aufta:BAABLgAECn8wAAIYAAkJPAeZOAAfAQAYAAkJPAeZOAAfAQAAAA==.Aumer:BAAALgAECgEJAQAAAA==.Auranda:BAAALgAECgEJAQAAAA==.',
Av='Avalonia:BAAALgAECgEJAQAAAA==.',
Az='Azdh:BAAALgAECgQJBgAAAA==.Azi:BAACLgAFFH8dAAIVAAgJJRutCQDLAQAVAAgJJRutCQDLAQAuAAQKfykAAhUACQkGIOIDAIUCABUACQkGIOIDAIUCAAAA.Azshanorel:BAAALgADCgcJBwAAAA==.Azunea:BAAALgAECgIJBwAAAA==.Azurite:BAAALgAECgkJEwAAAA==.',
Ba='Backpedal:BAABLgAECn8WAAIYAAgJThJpMABGAQAYAAgJThJpMABGAQAAAA==.Badankhadonk:BAACLgAFFH8UAAIKAAUJaCKEEgDSAQAKAAUJaCKEEgDSAQAuAAQKfy0AAgoACQl7JVICAF8DAAoACQl7JVICAF8DAAAA.Balen:BAABLgAECn80AAIDAAkJqhYoCwAWAgADAAkJqhYoCwAWAgAAAA==.Bandrösh:BAAALgADCgMJAwAAAA==.Barradune:BAAALgADCgYJDAAAAA==.Baubles:BAAALgAECgMJAgAAAA==.',
Be='Belholy:BAABLgAECn8xAAIZAAkJzB8JBgAVAwAZAAkJzB8JBgAVAwAAAA==.Beliice:BAAALgAECgUJBQABLgAECgkJMQAZAMwfAA==.Bellanei:BAAALgAECgEJBAAAAA==.Ben:BAAALgAECgEJAQAAAA==.Benafflockk:BAAALgADCggJCAAAAA==.Benefitdruid:BAAALgAECgEJAQAAAA==.Benilok:BAACLgAFFH8RAAMHAAUJ+yGyIgDDAQAHAAUJ+yGyIgDDAQAGAAEJ6hD0JwBFAAAuAAQKfysAAgcACQkcJSEMABkDAAcACQkcJSEMABkDAAAA.Bethgibbons:BAAALgADCgkJRQAAAA==.',
Bi='Bibimbap:BAAALgAECgEJAQAAAA==.Bigsuccubus:BAABLgAECn8cAAIGAAkJ0xYCBQAnAgAGAAkJ0xYCBQAnAgAAAA==.Biohazard:BAAALgADCgUJBQAAAA==.Bizël:BAAALgAECgYJDQAAAA==.',
Bl='Blackblood:BAABLgAECn8nAAIBAAkJqRUhFADxAQABAAkJqRUhFADxAQAAAA==.Blackclouds:BAAALgADCgkJCQAAAA==.Blackspiral:BAAALgADCgEJAQAAAA==.Bladestriker:BAAALgAECgUJBwAAAA==.Blindside:BAAALgAECgMJBgAAAA==.Bloodache:BAABLgAECn8VAAITAAcJKSFgKQBcAgATAAcJKSFgKQBcAgAAAA==.Bloodkissed:BAAALgADCgUJBgABLgAECgkJOAAZAEQgAA==.Bluebuberry:BAAALgAECgQJBgAAAA==.Bluesaphire:BAAALgAECgIJAgABLgAECggJFQAKAP8ZAA==.Blux:BAAALgAECgQJCAAAAA==.',
Bo='Boil:BAABLgAECn8mAAIPAAkJuQdiDwATAQAPAAkJuQdiDwATAQAAAA==.Bonemarrow:BAABLgAECn8aAAIFAAUJGhLG1ADtAAAFAAUJGhLG1ADtAAAAAA==.Bournx:BAAALgAECgQJBAAAAA==.Boysenbar:BAAALgADCgYJCAAAAA==.',
Br='Bradrenna:BAACLgAFFH8LAAMBAAQJ2wwhGADgAAABAAQJuQUhGADgAAACAAIJWRTEDAB9AAAuAAQKf10ABAIACQloG+kEAGUCAAIACQloG+kEAGUCAAEAAwlkD9VYAFwAABMAAQmlAcf0ABsAAAAA.Brakeable:BAAALgAECgUJBQAAAA==.Braké:BAABLgAECn8eAAIDAAkJaB1lBQCbAgADAAkJaB1lBQCbAgAAAA==.Brandrale:BAAALgAECgQJBgAAAA==.Breakthrough:BAABLgAECn8lAAIKAAYJOCPaHgBXAgAKAAYJOCPaHgBXAgAAAA==.Brenzull:BAAALgADCgYJCwAAAA==.Brewskies:BAABLgAECn8nAAIaAAcJDyWUDABtAgAaAAcJDyWUDABtAgABLgAECgkJNQAbAPYiAA==.Brewsli:BAAALgADCgIJAgABLgAECgkJIwAcABULAA==.Brightstar:BAAALgAECgcJEwAAAA==.Brokenaltar:BAABLgAECn8VAAMBAAYJNRheOQAdAQATAAYJgRFacwBLAQABAAUJCRpeOQAdAQAAAA==.Brownington:BAACLgAFFH8GAAMXAAMJJRJEFQCGAAAXAAIJFA1EFQCGAAAOAAEJSBzzNgBJAAAuAAQKfxkAAw4ABwlWJAkJAFsCAA4ABwlWJAkJAFsCABcAAQmjCrBXACsAAAAA.Bruhilda:BAABLgAECn8dAAIWAAkJ7hLxSwD3AQAWAAkJ7hLxSwD3AQAAAA==.Brymstone:BAAALgAECgQJBwAAAA==.Brynthebuff:BAAALgAECgEJAQAAAA==.Brãke:BAAALgAECgEJAQAAAA==.Brìonik:BAACLgAFFH8fAAMGAAgJEhyyCAAMAQAHAAcJWRmGKwCYAQAGAAQJTx+yCAAMAQAuAAQKfyoAAwYACQkPJL4FAA4CAAYABgkoJb4FAA4CAAcABQkeI4JzAFMBAAAA.',
Bu='Bufferfish:BAABLgAECn82AAIdAAkJUQxiLwB7AQAdAAkJUQxiLwB7AQAAAA==.',
Ca='Calinnea:BAABLgAECn8VAAMeAAgJDBChMwCoAQAeAAgJDBChMwCoAQAYAAIJDgOFiAAnAAAAAA==.Cantheartitz:BAABLgAECn8WAAIWAAUJPxmBnQCbAQAWAAUJPxmBnQCbAQAAAA==.Catastrophe:BAABLgAECn8pAAIYAAkJJSKTBAAOAwAYAAkJJSKTBAAOAwAAAA==.',
Ce='Celira:BAAALgADCgMJAwAAAA==.Celthol:BAABLgAECn8lAAITAAYJyheKAgABAQATAAYJyheKAgABAQAAAA==.',
Ch='Chelraani:BAABLgAECn9AAAIFAAkJMSReBgA+AwAFAAkJMSReBgA+AwAAAA==.Chiichard:BAAALgADCgYJCgAAAA==.Chipnuts:BAABLgAECn8bAAIYAAkJ8CTAAgBtAwAYAAkJ8CTAAgBtAwAAAA==.Chonchoo:BAAALgADCgEJAQAAAA==.Chosethebear:BAAALgADCgkJEAAAAA==.Chunkamonk:BAAALgADCgcJDQAAAA==.',
Ci='Cigar:BAAALgAECgQJCQABLgAFFAcJHAAQAIccAA==.Cinderat:BAAALgADCgEJAQAAAA==.Cinderburn:BAAALgADCgYJBgABLgAECgkJDAAEAAAAAA==.',
Cl='Clambumper:BAAALgAECgEJAQAAAA==.Clarabellax:BAAALgAECgQJBQAAAA==.Clarkkentt:BAAALgADCgcJDQAAAA==.Claymore:BAACLgAFFH8RAAIRAAYJBBYVDwCNAQARAAYJBBYVDwCNAQAuAAQKfxUAAhEACAkMGcscAGcCABEACAkMGcscAGcCAAAA.Clazzicola:BAACLgAFFH8PAAMeAAUJPxIFKAAuAQAeAAUJPxIFKAAuAQAYAAMJJgvADQCWAAAuAAQKfx8ABBgACQmbFmIeAOUBABgABwlYHGIeAOUBAB4ACAniEYomAH4BABoAAQlhA8uVAB8AAAAA.Cloudbeast:BAAALgAECgMJBAABLgAECgkJDAAEAAAAAA==.Clue:BAAALgADCgYJBgAAAA==.',
Co='Cocito:BAAALgAECgEJAwAAAA==.Commândment:BAAALgAECgcJDwAAAA==.Conjredcukee:BAABLgAECn8WAAIWAAcJ7ANC5wDQAAAWAAcJ7ANC5wDQAAAAAA==.Coo:BAAALgAECgQJBAABLgAECgUJBwAEAAAAAA==.Coogsayer:BAABLgAECn8UAAIIAAcJyh2aEQBxAgAIAAcJyh2aEQBxAgAAAA==.Couch:BAAALgAECgUJBQAAAA==.',
Cp='Cptncrush:BAABLgAECn8fAAMKAAgJBBpVKQAYAgAKAAgJBBpVKQAYAgALAAMJoBfHagCnAAAAAA==.',
Cr='Crackstalion:BAAALgAECgEJAQAAAA==.Croquetica:BAAALgADCgMJBAAAAA==.Crossed:BAAALgADCgcJCwAAAA==.Crowshadow:BAABLgAECn8cAAIHAAgJ8Bp9KQA1AgAHAAgJ8Bp9KQA1AgAAAA==.',
Cy='Cylina:BAAALgADCgcJCAABLgADCgcJFAAEAAAAAA==.Cyliya:BAAALgADCgIJAwABLgADCgcJFAAEAAAAAA==.Cylore:BAAALgADCgcJBgABLgADCgcJFAAEAAAAAA==.Cypherrellik:BAAALgAECgMJAwABLgAECgkJHAABAIUQAA==.Cyrax:BAAALgADCgYJCQAAAA==.Cyther:BAACLgAFFH8jAAIRAAgJ8xxBBQAaAgARAAgJ8xxBBQAaAgAuAAQKfykAAhEACQmXIqwHAC4DABEACQmXIqwHAC4DAAAA.',
['Cÿ']='Cÿthera:BAABLgAECn8bAAITAAkJ4BzDHAClAgATAAkJ4BzDHAClAgAAAA==.',
Da='Dakk:BAABLgAECn9KAAIQAAkJOiNnCgAcAwAQAAkJOiNnCgAcAwAAAA==.Dangbor:BAAALgAECgEJAQABLgAECgkJMAAMAHkWAA==.Daraghor:BAABLgAECn8bAAIOAAkJoCIMAgAbAwAOAAkJoCIMAgAbAwAAAA==.Darkdottie:BAAALgAECgQJCQAAAA==.Darkenstormy:BAAALgAECggJEwAAAA==.Darlyndra:BAAALgADCgUJBQAAAA==.Darsae:BAAALgAECgQJDAAAAA==.Darthiono:BAAALgAECgEJAQAAAA==.Darthmaull:BAAALgAECgEJAQAAAA==.',
De='Deadlight:BAABLgAECn8xAAMQAAkJzhJuUwDKAQAQAAkJOhJuUwDKAQAcAAEJYBJ+OQA3AAAAAA==.Deathkillhun:BAAALgAECgQJBwAAAA==.Deathpooch:BAAALgAFFAEJAQAAAA==.Deathshooter:BAAALgAECgcJAQAAAA==.Deavant:BAAALgADCgMJAwAAAA==.Deermon:BAAALgAECgYJCwAAAA==.Deet:BAAALgAECgUJBQAAAA==.Deforest:BAAALgADCgcJFgAAAA==.Deity:BAABLgAECn8yAAIRAAkJMSTqAwAoAwARAAkJMSTqAwAoAwABLgAFFAMJBAAEAAAAAA==.Demogon:BAAALgAECgQJBwAAAA==.Demondeano:BAABLgAECn8bAAITAAkJAROqSgCmAQATAAkJAROqSgCmAQAAAA==.Demonllxll:BAAALgAECgYJCwAAAA==.Demonlxl:BAABLgAECn8cAAILAAgJ/xVUIgDSAQALAAgJ/xVUIgDSAQAAAA==.Demonthorx:BAAALgAECgUJBQAAAA==.Demonx:BAABLgAECn8zAAIQAAkJ+x1cGgCoAgAQAAkJ+x1cGgCoAgAAAA==.Dennis:BAAALgAECgYJCQABLgAECgkJFQAFAAIVAA==.Derpsicle:BAAALgAECgEJAQAAAA==.Desolation:BAABLgAECn9SAAIfAAkJ+iUnAABsAwAfAAkJ+iUnAABsAwAAAA==.Despia:BAABLgAECn87AAMZAAkJZCS3AQCbAwAZAAkJZCS3AQCbAwAIAAYJzxH1MgBOAQAAAA==.Devastacia:BAAALgADCgUJBQAAAA==.Deviarc:BAAALgAECgQJBAABLgAFFAYJGQAMAP8cAA==.',
Dh='Dharkon:BAAALgAECgIJBAAAAA==.',
Di='Dicot:BAABLgAECn8yAAIgAAkJRxPsJgAZAgAgAAkJRxPsJgAZAgAAAA==.',
Dj='Djpallyd:BAAALgAECgkJEAAAAA==.',
Do='Doinks:BAAALgAECgIJAgAAAA==.Domilthri:BAACLgAFFH8LAAIHAAMJhwM7jgCoAAAHAAMJhwM7jgCoAAAuAAQKf0EAAwcACAlCEKhfAIEBAAcACAlCEKhfAIEBACEABgnyBUMQACoBAAAA.Dontormenta:BAAALgAECgcJDAAAAA==.Donut:BAAALgADCgIJAgABLgAECggJHwAiAJkhAA==.Dotdaddy:BAAALgAECgQJBwABLgAECggJFQAeAAwQAA==.Doughy:BAAALgAECgYJBgAAAA==.',
Dr='Dracoly:BAAALgAECggJEgAAAA==.Draconu:BAACLgAFFH8mAAIdAAYJ+xmhGAChAQAdAAYJ+xmhGAChAQAuAAQKfyIAAx0ACQk4H4AMAJMCAB0ACQk4H4AMAJMCAAwAAQmaAX1OACIAAAAA.Draenyth:BAABLgAECn8cAAITAAcJKBBVbABLAQATAAcJKBBVbABLAQAAAA==.Dragoncurry:BAABLgAECn8WAAIMAAYJIgZGKACpAAAMAAYJIgZGKACpAAAAAA==.Dragonmite:BAAALgAECgEJAQAAAA==.Drakka:BAAALgADCgkJDgABLgAECgkJFQAFAAIVAA==.Draktyr:BAACLgAFFH8GAAIRAAMJtRZeFgCyAAARAAMJtRZeFgCyAAAuAAQKfyQAAhEACQn2HncJABYDABEACQn2HncJABYDAAAA.Draxoths:BAAALgAECgMJBQABLgAFFAMJBwAgADkZAA==.Dropeadita:BAAALgAECgQJBAAAAA==.Droptop:BAAALgADCgcJCAAAAA==.Druadh:BAAALgADCgYJBgABLgAECggJFQAKAP8ZAA==.',
Du='Dumbsht:BAABLgAECn8ZAAMVAAgJ6xbDMQCpAQAVAAcJ6xXDMQCpAQAUAAYJVhHjXQBOAQAAAA==.',
Dy='Dyvyne:BAAALgAECgQJBwAAAA==.',
Ea='Easystreet:BAAALgAECgIJAwAAAA==.',
Ef='Effluv:BAAALgADCgcJDgAAAA==.',
El='Elandir:BAAALgADCgQJAQAAAA==.Elanora:BAAALgAECgYJCQAAAA==.Elbrookel:BAAALgAECgIJAgAAAA==.Eleshnorn:BAAALgAFFAEJAwAAAA==.Eliza:BAAALgADCgkJCQAAAA==.Ellismom:BAABLgAECn9BAAIQAAkJ+SHaDQD9AgAQAAkJ+SHaDQD9AgAAAA==.Elosong:BAAALgAECgEJAQAAAA==.Elvea:BAABLgAECn8kAAMdAAgJjRr2GQAHAgAdAAgJjRr2GQAHAgAiAAEJ9QoWQgArAAABLgAFFAYJGAAjADMUAA==.',
Em='Emeralddemon:BAAALgAECgYJDAAAAA==.Emeraldshade:BAAALgADCgcJEwABLgAECgYJDAAEAAAAAA==.Emeråld:BAAALgAECgUJBwAAAA==.',
En='Enamorada:BAAALgAECgIJAgABLgAECggJFQAKAP8ZAA==.',
Er='Eregon:BAAALgADCgYJBgAAAA==.Ereithelda:BAACLgAFFH8jAAMeAAgJhBVmFwDCAQAeAAgJhBVmFwDCAQAYAAIJOxWGLgCNAAAuAAQKfyYAAh4ACAm2IhcHAOkCAB4ACAm2IhcHAOkCAAAA.Ericka:BAAALgAECgUJBwAAAA==.Erowid:BAAALgAFFAMJAwABLgAFFAYJJgAdAPsZAA==.Erreya:BAAALgADCgEJAQAAAA==.',
Es='Esma:BAAALgADCgkJCQAAAA==.',
Ev='Evildeadd:BAAALgAECgIJAgAAAA==.Evox:BAABLgAECn8WAAMLAAkJWBhQAQAjAQALAAgJcxdQAQAjAQAKAAEJEBRl0wA3AAAAAA==.',
Ey='Eyris:BAAALgADCgMJAwAAAA==.Eyrndor:BAAALgADCgIJAwAAAA==.',
Fa='Faacee:BAAALgAECgIJAgAAAA==.Falgar:BAAALgAECgMJBgAAAA==.Fann:BAABLgAECn8gAAIgAAkJgAT4awDwAAAgAAkJgAT4awDwAAAAAA==.Fauna:BAAALgAECgYJCAAAAA==.Fawn:BAAALgAECgIJBAAAAA==.Faytl:BAAALgAECgMJAwAAAA==.',
Fe='Fel:BAAALgAECgEJAgAAAA==.Felbubu:BAABLgAECn8jAAQCAAkJlyIeBACAAgACAAkJLCIeBACAAgABAAYJOyAmIgCrAQATAAMJNRx5pwDVAAAAAA==.Femboy:BAAALgAECgUJDgAAAA==.Fewz:BAACLgAFFH8MAAIWAAQJ3BhpdgDvAAAWAAQJ3BhpdgDvAAAuAAQKfyQAAhYACQnjITUdAK0CABYACQnjITUdAK0CAAAA.',
Fi='Fireybuns:BAAALgAECgEJAwAAAA==.',
Fl='Flakiron:BAACLgAFFH8ZAAIkAAYJAhOeEgASAQAkAAYJAhOeEgASAQAuAAQKfy0AAiQACQkjHJkLAFQCACQACQkjHJkLAFQCAAAA.Flakov:BAAALgAECgIJAgABLgAFFAYJGQAkAAITAA==.Flaktop:BAAALgAECgUJCAABLgAFFAYJGQAkAAITAA==.Fler:BAAALgAECgQJCAAAAA==.',
Fo='Forbacon:BAABLgAECn8jAAMcAAkJFQu3FAA1AQAcAAkJuAq3FAA1AQAQAAYJgQnz1ADiAAAAAA==.Force:BAABLgAECn8jAAQcAAkJygqwEgBOAQAcAAgJnwuwEgBOAQAQAAUJEAS6FQGRAAAbAAEJ+wTIZwAaAAAAAA==.Fornost:BAAALgADCgkJDgAAAA==.Forsaken:BAAALgAFFAMJBAAAAA==.Fourdragon:BAAALgADCgQJBAABLgAECggJFwALACQXAA==.Fouris:BAABLgAECn8XAAILAAgJJBflKgCcAQALAAgJJBflKgCcAQAAAA==.',
Fr='Fremosth:BAAALgADCgMJAwAAAA==.Fretman:BAAALgADCgcJCQAAAA==.Fridgie:BAACLgAFFH8YAAIUAAUJZhkzBABdAQAUAAUJZhkzBABdAQAuAAQKfyMAAhQACQm6Im0PAMACABQACQm6Im0PAMACAAAA.Froline:BAAALgAECgYJDQAAAA==.Frostreaper:BAAALgAECgIJAgAAAA==.Frozenflyer:BAAALgAECgUJEAAAAA==.Frozenturtle:BAABLgAECn8gAAIbAAkJQxxsCwBYAgAbAAkJQxxsCwBYAgAAAA==.Fryea:BAAALgAECgEJAQAAAA==.',
Ft='Ftwiamtank:BAABLgAECn8YAAIkAAYJrw9aKADxAAAkAAYJrw9aKADxAAABLgAECggJLQANAIIMAA==.',
Fu='Fuoco:BAAALgAECgkJCgAAAA==.Furah:BAAALgAECgEJAgAAAA==.',
Ga='Gabriél:BAAALgAECgYJCQAAAA==.Garcutt:BAACLgAFFH8gAAIWAAgJaRQ1KADWAQAWAAgJaRQ1KADWAQAuAAQKfysAAhYACQm0HXIsAGcCABYACQm0HXIsAGcCAAAA.Gardon:BAAALgAECgYJCgAAAA==.Gaurdinn:BAABLgAECn8uAAQdAAgJMBMgMgBtAQAdAAgJrhIgMgBtAQAiAAYJfxAREQD5AAAMAAIJagJAPAAyAAABLgAECgkJJQALAKgYAA==.',
Ge='Gebuss:BAAALgADCgQJBAAAAA==.Generickk:BAAALgAECgUJBwAAAA==.Generickmonk:BAACLgAFFH8YAAIYAAUJox15DgBLAQAYAAUJox15DgBLAQAuAAQKfy8AAhgACQnyIsQFAPMCABgACQnyIsQFAPMCAAAA.Gensis:BAAALgADCgYJBgAAAA==.Geomatic:BAAALgAECgEJAQAAAA==.Gethsemåne:BAAALgADCgMJBQAAAA==.',
Gi='Giovannucci:BAAALgAECgEJAwAAAA==.Gitan:BAAALgADCgQJBQAAAA==.',
Gl='Gladstone:BAABLgAECn8VAAIDAAYJ+Ah9KwCxAAADAAYJ+Ah9KwCxAAAAAA==.',
Go='Gomlvirgin:BAAALgADCgYJBgABLgAECggJIgAHAHcUAA==.Gonwean:BAAALgAECgEJAQABLgAFFAYJFAAUAAkYAA==.',
Gr='Gracehimeûwû:BAABLgAFFH8FAAIaAAIJahETSgB3AAAaAAIJahETSgB3AAAAAA==.Grampsie:BAAALgAECgUJBwAAAA==.Grayeyes:BAAALgAECgMJAwAAAA==.Greenngoblin:BAAALgAFFAEJAQAAAA==.Grimjob:BAAALgADCgIJAgAAAA==.Grimmlie:BAAALgADCgUJBQAAAA==.Grinzler:BAAALgADCgIJAgAAAA==.Grumpybear:BAAALgADCggJDwAAAA==.Grumpykat:BAAALgAECggJEgAAAA==.Grumpypros:BAAALgADCgUJBQAAAA==.',
Gt='Gtatedk:BAAALgAFFAEJAwAAAA==.',
Gu='Guino:BAAALgAECgcJDgAAAA==.Guinodruid:BAAALgADCgcJDgAAAA==.Guinohunter:BAAALgADCgQJBAAAAA==.',
Gw='Gwenelly:BAAALgAECgEJAQAAAA==.',
Ha='Hamncheeks:BAAALgAECgEJAQAAAA==.Hamnqueso:BAAALgAECgMJAwAAAA==.Haptism:BAAALgADCgcJBwAAAA==.Hardeesdelux:BAAALgAECgkJDAAAAA==.Hardnarples:BAAALgADCgEJAQAAAA==.Hayzerade:BAAALgAECgYJCAAAAA==.Hazis:BAABLgAECn8rAAIbAAkJEyEbCACkAgAbAAkJEyEbCACkAgAAAA==.',
Hi='Highflyr:BAAALgAECgEJAQAAAA==.Hinala:BAAALgAECgYJCgAAAA==.Hippiecritz:BAAALgADCgYJBwAAAA==.Hitokiri:BAAALgADCgMJAwAAAA==.Hivemind:BAAALgAECgQJCAABLgAFFAQJCwAFAHETAA==.',
Ho='Holy:BAACLgAFFH8YAAIDAAYJ/QhFCAD0AAADAAYJ/QhFCAD0AAAuAAQKfywAAgMACQmkFvMQALcBAAMACQmkFvMQALcBAAAA.Holydad:BAACLgAFFH8FAAIDAAQJzA/qDQCeAAADAAQJzA/qDQCeAAAuAAQKfywAAgMACAkHIFEKACUCAAMACAkHIFEKACUCAAAA.Holydust:BAAALgAECgcJEQAAAA==.Holyhoette:BAAALgADCgQJBAAAAA==.Holymoki:BAAALgAECggJCAAAAA==.Holymoliie:BAAALgADCgEJAQAAAA==.Holyroundie:BAABLgAECn9PAAIZAAkJqBP9GAAEAgAZAAkJqBP9GAAEAgAAAA==.Holyshock:BAACLgAFFH8iAAIFAAgJkRrgEgDWAQAFAAgJkRrgEgDWAQAuAAQKfykAAgUACQlkJcgIACMDAAUACQlkJcgIACMDAAAA.Holystax:BAAALgAECgEJBAAAAA==.Honeybutter:BAACLgAFFH8hAAMSAAYJByaQBQAXAgASAAYJ9SWQBQAXAgARAAUJ2SU+CgC9AQAuAAQKfzsAAxIACQkzJgkBAGgDABIACQkzJgkBAGgDABEABwmLHtAjADgCAAAA.Hordebreaker:BAAALgAECgYJEQAAAA==.Hotflash:BAAALgAECgEJAQAAAA==.',
Hu='Huukend:BAABLgAECn9OAAIUAAkJ6yNCBgAwAwAUAAkJ6yNCBgAwAwAAAA==.',
Ib='Iblindbenice:BAAALgAECgYJBgAAAA==.',
Ic='Icebabyman:BAABLgAECn8fAAIWAAgJER7kOACSAgAWAAgJER7kOACSAgAAAA==.Icedmoki:BAAALgADCgQJBAAAAA==.',
Im='Imnotspeed:BAAALgAECgcJDQAAAA==.',
In='Inanitas:BAAALgAECgEJAQAAAA==.Ineffectual:BAABLgAECn8fAAIKAAgJvBMeMgC9AQAKAAgJvBMeMgC9AQAAAA==.',
Ir='Irion:BAAALgADCgMJAwAAAA==.Irukox:BAAALgAECgYJDQAAAA==.',
It='Itty:BAAALgADCgcJBwAAAA==.',
Ja='Jadaveon:BAAALgAECgQJBAAAAA==.Jadefleur:BAAALgAECgEJAQAAAA==.Jagger:BAAALgADCgcJCQAAAA==.Jalene:BAAALgAECgYJDwAAAA==.Janewayy:BAABLgAECn8yAAITAAkJGA14YgBjAQATAAkJGA14YgBjAQAAAA==.Jazmean:BAABLgAECn8UAAIJAAcJsw4eLQBwAQAJAAcJsw4eLQBwAQAAAA==.',
Jb='Jbournz:BAAALgADCgUJBQAAAA==.',
Je='Jeks:BAAALgADCgcJBwABLgAFFAcJIAAKANwXAA==.Jemma:BAABLgAECn8vAAIGAAkJ6hSDBgD4AQAGAAkJ6hSDBgD4AQAAAA==.Jerikos:BAAALgADCgYJBgAAAA==.Jettadari:BAACLgAFFH8SAAITAAgJKBIXEABNAQATAAgJKBIXEABNAQAuAAQKfyYAAxMACQlsIO0WAM0CABMACQlsIO0WAM0CAAIAAQlADkg1ADAAAAAA.Jettadin:BAABLgAECn8aAAIFAAgJ9yGnDwARAwAFAAgJ9yGnDwARAwABLgAFFAgJEgATACgSAA==.Jettakins:BAAALgAFFAEJAQABLgAFFAgJEgATACgSAA==.Jettathyr:BAAALgAECgcJDQABLgAFFAgJEgATACgSAA==.',
Ju='Jubba:BAABLgAECn8fAAIWAAkJ1xTaSAABAgAWAAkJ1xTaSAABAgAAAA==.Juderius:BAAALgADCgQJBAABLgAECgYJFAAGAEQFAA==.Junk:BAABLgAECn81AAIbAAkJ9iLyAgAWAwAbAAkJ9iLyAgAWAwAAAA==.',
['Jë']='Jëks:BAACLgAFFH8gAAIKAAcJ3BdNDgD8AQAKAAcJ3BdNDgD8AQAuAAQKfykAAwoACQlhJXEDAEEDAAoACQlhJXEDAEEDAA0AAgkvDsozAGEAAAAA.',
Ka='Kaghroxxar:BAAALgADCgkJIQAAAA==.Kahea:BAAALgAECgQJBAAAAA==.Kaitou:BAABLgAECn82AAMXAAkJMSJpAwDdAgAXAAkJMSJpAwDdAgAlAAEJrQ5hkAAvAAAAAA==.Kalamiti:BAABLgAECn8qAAMGAAkJrBhbAABrAQAhAAcJzBPdDACOAQAGAAkJrBhbAABrAQAAAA==.Kallar:BAABLgAECn84AAMZAAkJRCCVBgAJAwAZAAkJRCCVBgAJAwAIAAIJUQZ2egBKAAAAAA==.Karesh:BAAALgAECgQJBAAAAA==.Katween:BAAALgAECgQJBAAAAA==.Kayeera:BAABLgAECn8eAAMZAAgJdRYzHADlAQAZAAgJdRYzHADlAQAIAAQJBQUDTwCWAAAAAA==.Kayha:BAAALgADCgYJCAAAAA==.Kaylrandi:BAABLgAECn8cAAIWAAcJSwM0CQB0AAAWAAcJSwM0CQB0AAAAAA==.Kazarath:BAAALgAECgEJAQAAAA==.Kaztiel:BAAALgAECgIJAgAAAA==.',
Ke='Keadon:BAAALgAFFAEJAQAAAA==.Kearza:BAAALgAECgYJCwAAAA==.Keeper:BAAALgAECgUJBQABLgAFFAMJBAAEAAAAAA==.Keh:BAAALgADCgkJCQAAAA==.Keiyona:BAAALgAECgcJCgABLgAECgkJIgAFAKodAA==.Keladas:BAAALgAECgYJBgAAAA==.Kennethv:BAAALgAECgkJEgAAAA==.Kenze:BAAALgAECgEJAQAAAA==.Kethra:BAAALgADCggJEgAAAA==.Kev:BAAALgAECgcJBwAAAA==.',
Kh='Khel:BAAALgADCgcJBwAAAA==.Khibanee:BAAALgADCgQJBAAAAA==.Khiell:BAACLgAFFH8LAAIRAAQJgQ8XLQD+AAARAAQJgQ8XLQD+AAAuAAQKfyIAAhEACQkmGkIbABMCABEACQkmGkIbABMCAAAA.',
Ki='Kilyse:BAAALgADCgYJBgAAAA==.Kinigit:BAAALgAFFAQJBAABLgAFFAYJGQAlAMMZAA==.Kirïtö:BAAALgAECgUJCwAAAA==.Kitarah:BAEALgAECgIJAgABLgAECgkJEAAEAAAAAA==.Kitarazen:BAEALgAECgkJEAAAAA==.Kizli:BAAALgAECgUJBQAAAA==.',
Kn='Knghtmre:BAAALgAECgEJAQAAAA==.Knoway:BAAALgAECgMJAwAAAA==.',
Ko='Kokushimosu:BAAALgAECgYJDgAAAA==.Koo:BAAALgAECgUJBwAAAA==.Koviel:BAAALgAECgYJBwAAAA==.',
Kr='Kragon:BAAALgAECgkJEQAAAA==.Krátos:BAABLgAECn8oAAMSAAkJBxr7CABhAgASAAkJBxr7CABhAgARAAgJaRE+MwB+AQAAAA==.',
Ks='Ksper:BAAALgAECgcJEgAAAA==.',
Ku='Kukalak:BAABLgAECn8YAAIkAAgJ7BvSEQDrAQAkAAgJ7BvSEQDrAQAAAA==.Kuranaa:BAAALgAECgYJCAABLgAECgYJFAAGAEQFAA==.Kurulak:BAABLgAECn82AAITAAkJHxOEOADkAQATAAkJHxOEOADkAQAAAA==.Kuzcotopiajr:BAAALgADCgMJAwAAAA==.',
Ky='Kymru:BAAALgADCgcJDQAAAA==.Kynigoshanta:BAAALgADCgEJAQAAAA==.',
['Ké']='Kénnéth:BAAALgAECgYJEQAAAA==.',
La='Lacerveza:BAAALgAECgIJBQAAAA==.Lahyanhou:BAABLgAECn84AAIVAAkJawjjEQA8AQAVAAkJawjjEQA8AQAAAA==.Lalalalala:BAAALgAECgcJCgAAAA==.Lalin:BAAALgAECgEJBQAAAA==.Larkwyn:BAAALgAECgQJBAABLgAFFAYJEAAHAI8NAA==.Laylah:BAAALgADCgYJBAAAAA==.',
Le='Lebrand:BAAALgAECgEJAQAAAA==.Leriope:BAABLgAECn9aAAIHAAkJhxoTHAB8AgAHAAkJhxoTHAB8AgAAAA==.Leàf:BAABLgAECn8bAAIKAAgJMxlIHwBVAgAKAAgJMxlIHwBVAgAAAA==.',
Li='Lichfiend:BAAALgADCgEJAQAAAA==.Lightbeer:BAAALgAECgYJBwAAAA==.Lihpfu:BAAALgAFFAIJAwABLgAFFAQJHwARAJclAA==.Lihplock:BAAALgAECgQJCAABLgAFFAQJHwARAJclAA==.Lilandri:BAAALgAECgYJBwAAAA==.Lildragonboi:BAAALgADCgUJBQAAAA==.Lilem:BAAALgADCgcJEgAAAA==.Lilpooch:BAAALgAECgYJEAAAAA==.Listenlinda:BAAALgAECgMJBwAAAA==.Lithariel:BAAALgADCgkJCAAAAA==.Littlemerald:BAABLgAECn8VAAIOAAYJIAd3RwCLAAAOAAYJIAd3RwCLAAAAAA==.',
Lj='Lj:BAABLgAECn9TAAImAAkJDB8LCwDcAgAmAAkJDB8LCwDcAgAAAA==.',
Lo='Localsingles:BAAALgADCgcJBwAAAA==.Lorath:BAAALgADCgEJAQAAAA==.Lovecrafft:BAAALgAECgQJCwAAAA==.Lovetrain:BAAALgAECgYJBQAAAA==.',
Lu='Lu:BAABLgAFFH8HAAMbAAMJzxc/QQAsAAAQAAIJzxcc4ACEAAAbAAIJtA4/QQAsAAABLgAFFAUJDwAeAD8SAA==.Lucinà:BAABLgAECn8+AAQFAAkJeSJlFwC3AgAFAAgJ8CNlFwC3AgAmAAkJQR+TDAC1AgADAAUJkB2vHAAwAQAAAA==.Lusande:BAAALgAECgQJBgAAAA==.Luxure:BAAALgAECgYJBgAAAA==.Luxùria:BAAALgAECgYJBgAAAA==.',
Ly='Lyndall:BAAALgAECgQJBgAAAA==.',
Ma='Machamp:BAAALgAECgYJDAAAAA==.Madammìm:BAAALgAECgYJBgAAAA==.Maegan:BAABLgAECn8aAAIFAAcJHwkdwAAIAQAFAAcJHwkdwAAIAQAAAA==.Maewyn:BAAALgAECgEJAgAAAA==.Mager:BAAALgAECgUJEAAAAA==.Magerhunter:BAAALgAECgYJCAAAAA==.Magolock:BAAALgAECgUJEgAAAA==.Mahll:BAAALgAECgMJAwAAAA==.Maidrim:BAACLgAFFH8aAAInAAcJ3xYsAQD3AQAnAAcJ3xYsAQD3AQAuAAQKfx8AAicACQmrIfICALICACcACQmrIfICALICAAAA.Makaveli:BAAALgAECgcJDwAAAA==.Makavelli:BAAALgAECgEJAQAAAA==.Mamajumbo:BAABLgAECn8fAAIUAAkJexwXFwCdAgAUAAkJexwXFwCdAgAAAA==.Marage:BAAALgADCgEJAQAAAA==.Marellias:BAAALgAECgMJBAABLgAFFAMJBQAFACQdAA==.Mariag:BAAALgADCgQJBAAAAA==.Marikel:BAABLgAECn8WAAIQAAYJxgjU0wDjAAAQAAYJxgjU0wDjAAAAAA==.Markwel:BAAALgAECgIJAgAAAA==.Marrack:BAAALgAECgYJDQAAAA==.',
Me='Melador:BAAALgADCgIJAgAAAA==.Meletha:BAAALgAECgYJDwAAAA==.Melpuis:BAAALgAECgEJAgAAAA==.Merinda:BAAALgAECgEJAQAAAA==.Metahorfasis:BAAALgAECgUJBQAAAA==.',
Mi='Michaelken:BAABLgAECn8jAAMmAAkJDhckFgBaAgAmAAkJDhckFgBaAgAFAAEJsAdxmgEvAAAAAA==.Mierín:BAAALgADCgYJBgAAAA==.Migrains:BAABLgAECn9bAAIDAAkJQCXyAABUAwADAAkJQCXyAABUAwAAAA==.Mineo:BAAALgAECgYJBwAAAA==.Mirâjâne:BAAALgAECgEJAQAAAA==.Miskaabin:BAABLgAECn8/AAMDAAkJFxWZAABkAQAFAAkJFRPWRQD1AQADAAcJMxKZAABkAQAAAA==.Missusgrey:BAAALgADCgkJCQABLgAECgUJBQAEAAAAAA==.Miststress:BAAALgAECgcJCAAAAA==.',
Mo='Mobal:BAABLgAECn88AAMKAAkJhhzBEwCuAgAKAAkJhhzBEwCuAgALAAQJxgisegB/AAAAAA==.Modarku:BAAALgADCgQJBAAAAA==.Mojogreens:BAAALgAECgYJEQAAAA==.Montydh:BAAALgAECgEJAQAAAA==.Moonblades:BAAALgADCgUJBQAAAA==.Moonpetals:BAAALgAECgMJBQAAAA==.Moonrush:BAAALgAECgMJCAAAAA==.Mortiis:BAABLgAECn8UAAMNAAcJ6gubFgBWAQANAAcJ6gubFgBWAQAKAAIJowc0kABYAAAAAA==.Motako:BAABLgAECn8gAAIKAAcJRCCfFQBoAgAKAAcJRCCfFQBoAgAAAA==.',
Mp='Mpd:BAABLgAECn8ZAAIXAAcJxBb8EQCbAQAXAAcJxBb8EQCbAQAAAA==.',
My='Mybizël:BAABLgAECn8pAAIUAAcJwR7oIABAAgAUAAcJwR7oIABAAgAAAA==.Myrlifax:BAAALgADCgEJAQABLgAECgkJFQAFAAIVAA==.Mystique:BAABLgAECn8bAAICAAkJEgnCEABAAQACAAkJEgnCEABAAQAAAA==.Mythdaraghma:BAABLgAECn8WAAIBAAYJNQivPQC/AAABAAYJNQivPQC/AAAAAA==.',
['Má']='Máximo:BAAALgAECgYJEAAAAA==.',
['Mí']='Míerin:BAAALgAECgQJBAAAAA==.Míerín:BAACLgAFFH8XAAIoAAYJYR36BgCeAQAoAAYJYR36BgCeAQAuAAQKfzcAAygACQnBJWQCACQDACgACQnBJWQCACQDABQABAm+G0NgAEcBAAAA.',
['Mø']='Møøse:BAAALgAECgQJBwAAAA==.',
Na='Naama:BAAALgADCgkJKwAAAA==.Nadaar:BAABLgAECn8bAAIfAAgJWhlaAwDyAQAfAAgJWhlaAwDyAQAAAA==.Naelih:BAABLgAECn8tAAIVAAkJ+Q1ODQCLAQAVAAkJ+Q1ODQCLAQAAAA==.Naharuk:BAAALgADCgMJAwAAAA==.Natholomas:BAAALgADCgQJBAAAAA==.Natlès:BAAALgAECggJCwABLgAECggJFQAeAAwQAA==.Nattwenty:BAAALgAECgQJBAAAAA==.Natzu:BAAALgAECgYJCgAAAA==.Nazeer:BAAALgADCgcJBwABLgAFFAUJCQAgAMkEAA==.Nazgrim:BAACLgAFFH8JAAIgAAUJyQTCMgDjAAAgAAUJyQTCMgDjAAAuAAQKfz4AAiAACAnIFlsvAO8BACAACAnIFlsvAO8BAAAA.',
Ne='Necronu:BAACLgAFFH8MAAIQAAMJDBehDgCbAAAQAAMJDBehDgCbAAAuAAQKfxQAAxAACQm7H2gXALoCABAACQknHmgXALoCABwABAmuHZMRAF8BAAEuAAUUBgkmAB0A+xkA.',
Ni='Nikkolos:BAABLgAECn8cAAIBAAgJ5gzyJQBKAQABAAgJ5gzyJQBKAQAAAA==.Ninjastax:BAAALgAECgEJAwAAAA==.Nissie:BAAALgAECgEJAQAAAA==.Nitazendezot:BAAALgAFFAEJAwABLgAFFAQJDgAQALsVAA==.',
No='Nogusta:BAACLgAFFH8ZAAIRAAYJNxxMDwCLAQARAAYJNxxMDwCLAQAuAAQKfykAAhEACQloH2kLAP8CABEACQloH2kLAP8CAAAA.Norberta:BAABLgAECn8jAAMdAAkJBAivOABLAQAdAAkJ8AevOABLAQAiAAYJWAbxIwAIAQAAAA==.Nossanir:BAAALgAECgIJAgAAAA==.Nossellia:BAAALgAECgQJBwAAAA==.',
Nu='Nuggetssham:BAAALgAECgEJAQAAAA==.Nurana:BAAALgADCgEJAQAAAA==.',
Ny='Nycecritz:BAAALgAECgEJAQAAAA==.',
['Nä']='Näturi:BAAALgAECgQJBAAAAA==.',
Od='Odor:BAAALgAECgQJBgAAAA==.',
Ol='Oldie:BAAALgAFFAIJAwAAAA==.Olielno:BAAALgADCgMJAwAAAA==.',
On='Onlyshams:BAABLgAECn8hAAIKAAgJtBgvGQBNAgAKAAgJtBgvGQBNAgAAAA==.Onlytides:BAEBLgAECn8dAAMKAAkJ2SPlBwD2AgAKAAkJ2SPlBwD2AgALAAcJXRiAHwAUAgABLgAFFAcJHgAgAH4bAA==.Onubis:BAACLgAFFH8QAAMUAAUJriGMLwBRAQAUAAUJriGMLwBRAQAoAAIJ5yBKJQCnAAAuAAQKfx8ABBQACQmaHw8MAOECABQACQmOHw8MAOECABUABgnGHdk0AJcBACgAAQmkI7NUAFsAAAEuAAUUBgkmAB0A+xkA.Onublue:BAABLgAFFH8GAAMLAAYJ8g/ZBAC2AAALAAQJqQfZBAC2AAAKAAIJ4QbpDABOAAABLgAFFAYJJgAdAPsZAA==.Onuchi:BAABLgAFFH8PAAMYAAYJQRbKAQDiAAAYAAUJtBLKAQDiAAAeAAYJvQQXNgDRAAABLgAFFAYJJgAdAPsZAA==.Onulock:BAAALgAECgYJCgABLgAFFAYJJgAdAPsZAA==.Onux:BAABLgAFFH8SAAITAAYJOBtMJACeAQATAAYJOBtMJACeAQABLgAFFAYJJgAdAPsZAA==.',
Op='Opgarbage:BAAALgAECgQJCwAAAA==.',
Ou='Oukei:BAAALgAECgcJEgABLgAFFAcJFQAEAAAAAQ==.Oumura:BAAALgAECgYJDgAAAA==.',
Ov='Overlordainz:BAABLgAECn8UAAMJAAYJeBOpNABDAQAJAAYJ7hCpNABDAQAZAAQJLxPjVgDaAAAAAA==.',
Pa='Paarthürnax:BAAALgAECgYJDAAAAA==.Padamee:BAAALgAECgQJBwAAAA==.Paganini:BAAALgAECgQJBAABLgAECgkJHwAUAHUdAA==.Pallyoop:BAABLgAECn8WAAImAAcJMg81VgDfAAAmAAcJMg81VgDfAAAAAA==.Pandaa:BAAALgAECgEJAQAAAA==.Papapaw:BAAALgAECgQJBgAAAA==.Pathator:BAAALgAECgYJBwABLgAECgkJGQAQAAYdAA==.Pathaviendha:BAAALgAECgUJAgAAAA==.Patherion:BAAALgADCgEJAQABLgAECgkJGQAQAAYdAA==.Patheros:BAAALgADCgQJAwABLgAECgkJGQAQAAYdAA==.Patholans:BAABLgAECn8ZAAIQAAkJBh1JGwCjAgAQAAkJBh1JGwCjAgAAAA==.Pathology:BAAALgAECgMJAwABLgAECgkJGQAQAAYdAA==.Paxman:BAAALgAECgUJCAAAAA==.',
Pe='Peanits:BAAALgAECgQJCwABLgAECgkJIwACAJciAA==.Peanutsuckr:BAACLgAFFH8iAAIbAAgJBCCIBwAQAgAbAAgJBCCIBwAQAgAuAAQKfykAAhsACQnGJSQCADEDABsACQnGJSQCADEDAAAA.Pearserve:BAAALgADCgYJBgABLgAECggJFAALANoPAA==.',
Ph='Phantöm:BAAALgAECgQJDAAAAA==.Phosphate:BAABLgAECn8QAAITAAYJNxKvbgBYAQATAAYJNxKvbgBYAQAAAA==.',
Pi='Piccolo:BAAALgAECgQJBgAAAA==.Pingg:BAAALgAECgQJBQAAAA==.Pinkeye:BAAALgAECgcJCgAAAA==.Pippafan:BAAALgAECgEJAQABLgAECgEJAwAEAAAAAA==.',
Pl='Placcid:BAABLgAECn9MAAIUAAkJIh3zFgCeAgAUAAkJIh3zFgCeAgAAAA==.Planknstein:BAAALgADCgMJAwAAAA==.Playdohh:BAAALgAECgcJCQAAAA==.Plutonia:BAAALgAECgMJBwAAAA==.',
Po='Pockett:BAABLgAECn8iAAMLAAcJKBGRPwA2AQALAAcJKBGRPwA2AQANAAUJBQnnGwAMAQAAAA==.Powrwordgoat:BAACLgAFFH8QAAIJAAQJShACKgD/AAAJAAQJShACKgD/AAAuAAQKfzYAAgkACQnRFA0VADMCAAkACQnRFA0VADMCAAAA.',
Pr='Prestoh:BAABLgAECn8zAAILAAkJvxFUJQC+AQALAAkJvxFUJQC+AQAAAA==.Prismclaw:BAABLgAECn9SAAIWAAkJhhWDOwAsAgAWAAkJhhWDOwAsAgAAAA==.Prisoner:BAAALgAECgEJAwAAAA==.Processing:BAAALgAECgYJBgAAAA==.',
Ps='Pseudoruski:BAAALgADCgMJAwAAAA==.',
Pu='Purplehaze:BAAALgAECgUJBQAAAA==.',
Pv='Pvlolz:BAABLgAECn8ZAAIZAAkJ3QpDMACAAQAZAAkJ3QpDMACAAQAAAA==.',
Pw='Pwnstarz:BAAALgAECgYJCgAAAA==.',
Py='Pyrada:BAABLgAECn8XAAMCAAkJxRZlCQDVAQATAAgJhxUNOwDbAQACAAgJAhdlCQDVAQAAAA==.',
Qa='Qaharn:BAAALgAECgQJBwAAAA==.',
Qp='Qplus:BAABLgAECn8jAAIUAAkJ5AhfXACQAQAUAAkJ5AhfXACQAQAAAA==.',
Qu='Quackadilly:BAAALgADCgcJDQAAAA==.Quaenie:BAABLgAECn8iAAIZAAkJGRecFgAcAgAZAAkJGRecFgAcAgAAAA==.Quintin:BAABLgAECn8ZAAIiAAgJfg7qCgBrAQAiAAgJfg7qCgBrAQAAAA==.',
Ra='Raged:BAAALgAECgUJCgAAAA==.Ragegauge:BAAALgAECgQJBgAAAA==.Ragetotem:BAABLgAECn8kAAMLAAYJmRwgKADSAQALAAYJmRwgKADSAQAKAAMJAAWIuABbAAAAAA==.Ragewarg:BAAALgAFFAIJAgAAAA==.Ragnashock:BAAALgAECgQJBgAAAA==.Ralvarr:BAABLgAECn8aAAIeAAgJIBimGwDbAQAeAAgJIBimGwDbAQAAAA==.Raptorjésus:BAAALgADCgcJCwAAAA==.Rastik:BAAALgADCgIJAgAAAA==.Rathaes:BAAALgADCgMJAwAAAA==.Ravenstryke:BAAALgAECgEJAQAAAA==.Raylea:BAAALgADCgcJBwAAAA==.Rayleigh:BAAALgAECggJEgABLgAECgUJCwAEAAAAAA==.Razzgix:BAAALgAECgUJBgAAAA==.',
Re='Redchord:BAAALgADCgUJDAAAAA==.Regidør:BAABLgAECn8ZAAMmAAgJ/CBcCADoAgAmAAgJ/CBcCADoAgAFAAYJxx0XYQDBAQAAAA==.Relik:BAABLgAECn8kAAIkAAkJjwyPGgBlAQAkAAkJjwyPGgBlAQAAAA==.Resith:BAAALgAECgYJCAAAAA==.',
Rh='Rhaelia:BAABLgAECn8ZAAIFAAcJFQlUwgAFAQAFAAcJFQlUwgAFAQAAAA==.Rhaspus:BAAALgADCgQJBAAAAA==.',
Ri='Rilliccine:BAAALgADCgkJCwAAAA==.Rillinetti:BAABLgAECn8mAAIHAAkJQBQGOAD5AQAHAAkJQBQGOAD5AQAAAA==.Rillini:BAAALgADCgcJBwAAAA==.Rilliti:BAABLgAECn8ZAAIKAAYJRA6PZgAoAQAKAAYJRA6PZgAoAQAAAA==.Risky:BAAALgAECgEJAQABLgAECgcJGAAgAMYEAA==.',
Ro='Robïn:BAAALgAECgIJAgABLgAECggJFQAeAAwQAA==.Rondon:BAABLgAECn88AAIUAAkJXCY3AQCHAwAUAAkJXCY3AQCHAwAAAA==.Rookdh:BAACLgAFFH8PAAMBAAYJAAbuGADaAAABAAQJUQTuGADaAAATAAYJ6wWBXgDUAAAuAAQKfykAAxMACQnkFuJcAHIBABMACAk+GOJcAHIBAAEABwkyFucsAGMBAAAA.Rorcia:BAAALgADCgcJFAAAAA==.Rosey:BAABLgAECn8sAAIFAAkJcxXyPgAKAgAFAAkJcxXyPgAKAgAAAA==.Rotmaxxer:BAAALgAFFAQJBAAAAA==.Roxania:BAAALgADCgYJBgAAAA==.Royale:BAAALgAECgcJBwAAAA==.',
Ru='Rudyeightbal:BAABLgAECn8bAAMHAAgJCQyvnAAEAQAHAAYJhw2vnAAEAQAGAAIJFQOvRgAfAAAAAA==.Ruedons:BAAALgAECgMJAwAAAA==.Rugsalon:BAACLgAFFH8IAAIWAAMJCwlFjgC8AAAWAAMJCwlFjgC8AAAuAAQKfycAAhYACQn1HPM0AJ8CABYACQn1HPM0AJ8CAAAA.Rustedbarrel:BAACLgAFFH8IAAIaAAMJqwvyPQCvAAAaAAMJqwvyPQCvAAAuAAQKfxsAAhoACQmnE3YhAPYBABoACQmnE3YhAPYBAAAA.',
Ry='Ryptar:BAAALgADCgkJHAAAAA==.',
['Rè']='Rèaper:BAAALgAECgMJAwAAAA==.',
['Ré']='Réxxar:BAABLgAECn8cAAIOAAcJPRTbDQClAQAOAAcJPRTbDQClAQAAAA==.',
Sa='Saelyres:BAABLgAECn8hAAMCAAkJyhwoBACGAgACAAkJyhwoBACGAgABAAEJ1wNHegApAAAAAA==.Sagesse:BAAALgADCgYJBgAAAA==.Saikye:BAAALgAECgEJAQAAAA==.Sairu:BAAALgADCgEJAQAAAA==.Saisera:BAABLgAFFH8IAAMQAAIJ+x7cugCzAAAQAAIJ+x7cugCzAAAcAAIJ1hWTHQCXAAAAAA==.Samistraza:BAAALgADCgEJAQAAAA==.Sammy:BAABLgAECn8jAAIFAAkJvQk5igBcAQAFAAkJvQk5igBcAQAAAA==.Santaclaaws:BAACLgAFFH8RAAITAAQJXxtCPQAyAQATAAQJXxtCPQAyAQAuAAQKfzUABBMACQmkIpAUAJ4CABMACQmkIpAUAJ4CAAIAAwldFlUcALgAAAEAAgk1GY5bAHIAAAAA.Santapal:BAACLgAFFH8IAAMmAAQJiRYOIQAWAQAmAAQJiRYOIQAWAQAFAAEJ3gGxygA2AAAuAAQKfy0ABCYACAkOGmooAMgBACYABwmhGmooAMgBAAUAAgl6BVdxAUcAAAMAAglpEqFOADUAAAEuAAUUBAkRABMAXxsA.Santatumblr:BAACLgAFFH8GAAMeAAMJdh2zLQAGAQAeAAMJdh2zLQAGAQAYAAEJLgzvQwA3AAAuAAQKfxoABB4ACAlRG00WAGcCAB4ACAlRG00WAGcCABgABAlyEABxAG4AABoAAQlNAzGqABoAAAEuAAUUBAkRABMAXxsA.Santhin:BAAALgADCgcJCgAAAA==.Saphira:BAAALgAECgQJBAAAAA==.Sareit:BAABLgAECn8cAAMIAAcJ2xESPwAUAQAIAAYJAhISPwAUAQAJAAYJIQxTPgATAQAAAA==.Sassee:BAAALgAECgQJCAAAAA==.Sayvil:BAAALgAECgUJCwABLgAECgkJOAAZAEQgAQ==.',
Sc='Scripture:BAAALgADCgYJBgAAAA==.',
Se='Seawolph:BAABLgAECn85AAIKAAkJBRmFGQB+AgAKAAkJBRmFGQB+AgAAAA==.Selenia:BAAALgAECgMJAwAAAA==.Semmers:BAAALgAECgkJCQAAAA==.Sensational:BAABLgAECn8aAAMeAAcJWhx+EwAvAgAeAAcJWhx+EwAvAgAYAAUJZwiaWwCmAAAAAA==.Sergio:BAAALgAECgcJCgAAAA==.Seyren:BAABLgAFFH8JAAISAAMJ8Q3jKADJAAASAAMJ8Q3jKADJAAAAAA==.',
Sh='Shamiska:BAAALgAECgcJEgAAAA==.Shammerdown:BAAALgAECgIJAwAAAA==.Shampooh:BAAALgAECgQJCAABLgAECgcJGAAgAMYEAA==.Shamtastyk:BAAALgAECgQJBAAAAA==.Shaokhan:BAABLgAECn8qAAMKAAkJiSEACAAvAwAKAAkJiSEACAAvAwANAAcJuwpOGwAmAQAAAA==.Sheilla:BAAALgADCgUJBQAAAA==.Shian:BAABLgAECn9CAAIOAAkJ+Bh4CgA9AgAOAAkJ+Bh4CgA9AgAAAA==.Shieldee:BAABLgAECn82AAMFAAkJ1RxPJAB0AgAFAAkJ1RxPJAB0AgAmAAEJTgOznQAiAAAAAA==.Shiftystax:BAAALgAECgEJAQAAAA==.Shlectrinell:BAABLgAECn9LAAMjAAkJ7A7wGADSAQAjAAkJ7A7wGADSAQAnAAgJBAUICwB+AQAAAA==.Shockeei:BAACLgAFFH8eAAMWAAYJACHlDgCiAQAWAAYJACHlDgCiAQApAAEJ6g/UBwA5AAAuAAQKfykABBYACQkqJXMJAC8DABYACQkqJXMJAC8DACkAAwlSGHcJALkAAB8AAQnWIOoSAFYAAAAA.Shocktroop:BAAALgADCgYJCgAAAA==.Shortdon:BAAALgAECgEJAQAAAA==.Shortebread:BAAALgAFFAIJAgAAAA==.Shurp:BAAALgAECgMJAwAAAA==.',
Si='Siakora:BAABLgAECn8VAAIjAAgJXRgLGwAoAgAjAAgJXRgLGwAoAgABLgAFFAgJIgAlAAQZAA==.Sicksty:BAAALgADCgcJBwAAAA==.Sighh:BAAALgAECgYJBwAAAA==.Sighhy:BAAALgAECgYJDwAAAA==.Sijth:BAACLgAFFH8LAAIFAAQJcRPtQwAjAQAFAAQJcRPtQwAjAQAuAAQKf1YAAgUACQlGIgcPAO4CAAUACQlGIgcPAO4CAAAA.Silentchaos:BAAALgADCgMJBQAAAA==.Siler:BAAALgADCgYJBgAAAA==.Silverwar:BAABLgAECn80AAIRAAkJjh5gCQDMAgARAAkJjh5gCQDMAgAAAA==.Simmi:BAECLgAFFH8eAAIgAAcJfhteCQBiAgAgAAcJfhteCQBiAgAuAAQKfykAAiAACQnBJVIGAFIDACAACQnBJVIGAFIDAAAA.Sinanestesia:BAAALgAECgIJAgAAAA==.Sinnis:BAAALgAECgEJAQAAAA==.Sirlavan:BAAALgAECgYJCwAAAA==.Sixte:BAAALgAECgcJCwAAAA==.Sixtea:BAABLgAECn81AAILAAkJ9B4ECQDNAgALAAkJ9B4ECQDNAgAAAA==.',
Sk='Skarredd:BAAALgADCgkJGQAAAA==.Skellington:BAAALgAECgEJAQAAAA==.Skepti:BAABLgAECn8tAAIUAAkJ7BquIgBZAgAUAAkJ7BquIgBZAgAAAA==.Skysong:BAAALgAECgMJAwAAAA==.',
Sl='Slapdemhoes:BAAALgAECgcJAgAAAA==.Slimfoo:BAAALgAECgcJDQAAAA==.Slunkyspit:BAAALgADCgUJCAAAAA==.Slybearclaw:BAAALgADCgUJBQAAAA==.Slyeulogy:BAAALgAECggJEgAAAA==.',
Sm='Smeeta:BAACLgAFFH8JAAIQAAMJ4BnyjwDrAAAQAAMJ4BnyjwDrAAAuAAQKf2AABBAACQmHJH4PAPACABAACQkxJH4PAPACABwACAldI4ADAK4CABsABQlQETQ5AK8AAAAA.Smoak:BAAALgADCgUJBQAAAA==.Smolderlight:BAACLgAFFH8MAAImAAQJKRT4IwABAQAmAAQJKRT4IwABAQAuAAQKf0AAAiYACQnVF1gWAFgCACYACQnVF1gWAFgCAAAA.Smoochiebutt:BAAALgAECgUJCQAAAA==.',
So='Solaace:BAAALgAECgEJAQABLgAECgcJGgAbANQSAA==.Solo:BAAALgAECgYJCQAAAA==.Soloris:BAAALgADCgcJCAAAAA==.Sonja:BAAALgAECgcJBwAAAA==.Soram:BAAALgAECgYJCgAAAA==.Sosa:BAABLgAFFH8FAAIkAAUJrxkkEAAxAQAkAAUJrxkkEAAxAQAAAA==.Soulstryker:BAAALgAECgEJAQAAAA==.Soùl:BAABLgAECn8UAAIWAAkJFQ1laACrAQAWAAkJFQ1laACrAQAAAA==.',
Sp='Spacepants:BAAALgAECgEJAQAAAA==.Spurgeon:BAAALgAECgEJAQAAAA==.',
St='Staraelle:BAAALgAECgEJAgAAAA==.Stazz:BAAALgAECgYJBgAAAA==.Steelerayne:BAABLgAECn8VAAIUAAkJbhZ0AgBdAQAUAAkJbhZ0AgBdAQAAAA==.Stormii:BAABLgAECn8jAAMKAAkJKA6NVABiAQAKAAgJTQyNVABiAQALAAMJfhQZZQC2AAAAAA==.Strangelock:BAAALgAECgYJDAABLgAECgkJMgAQALoNAA==.Strangerdk:BAABLgAECn8yAAIQAAkJug2CXwCqAQAQAAkJug2CXwCqAQAAAA==.Streetdog:BAAALgADCgYJBgAAAA==.Stublin:BAAALgADCgEJAQAAAA==.Stuggens:BAAALgADCgkJCQAAAA==.',
Su='Suggondeez:BAAALgAECgYJBwAAAA==.Superfatbaby:BAABLgAECn8dAAIRAAkJKhP3JwC7AQARAAkJKhP3JwC7AQAAAA==.',
Sw='Swiftstroker:BAAALgAECgEJAQAAAA==.Swikk:BAAALgADCgYJCAAAAA==.Swishersweet:BAABLgAECn8yAAIOAAkJFgrkKAATAQAOAAkJFgrkKAATAQAAAA==.Swordfish:BAABLgAECn8fAAIiAAgJmSG9AgCKAgAiAAgJmSG9AgCKAgAAAA==.',
Sy='Syannae:BAAALgAECgEJAQAAAA==.Sybelyda:BAAALgADCgYJBgAAAA==.Sybros:BAAALgADCgEJAQAAAA==.Sydonie:BAAALgAECgEJBwAAAA==.Sylus:BAAALgAECgQJBAAAAA==.Symbah:BAAALgADCgYJBgAAAA==.Synvalid:BAABLgAECn8gAAITAAkJ9wfxigAKAQATAAkJ9wfxigAKAQAAAA==.Syzrin:BAAALgADCgEJAQABLgAECggJIgAHAHcUAA==.',
Ta='Tabrieus:BAABLgAECn9SAAIWAAkJ5yHlCwAaAwAWAAkJ5yHlCwAaAwAAAA==.Tadokof:BAAALgADCgkJLwAAAA==.Talanth:BAABLgAECn8XAAInAAkJ0AjXCgCGAQAnAAkJ0AjXCgCGAQAAAA==.Talya:BAAALgAECggJCAABLgAECgkJQgAOAPgYAA==.Tandisong:BAAALgAECgcJCAAAAA==.Tanknhammerm:BAAALgADCgYJBgAAAA==.Tanknstein:BAAALgADCgYJBgAAAA==.Tanton:BAAALgAECgMJAwAAAA==.Tanzil:BAAALgAECgYJDgAAAA==.Tardigrade:BAAALgAECggJEwAAAA==.Tareyna:BAABLgAECn8hAAIFAAkJeBP8QgD+AQAFAAkJeBP8QgD+AQAAAA==.Tayon:BAABLgAECn8YAAMaAAkJEgdwAQC3AAAaAAkJEgdwAQC3AAAeAAEJTgan0QAfAAAAAA==.Tayvin:BAAALgAECgYJEwAAAA==.Tazanath:BAAALgADCgEJAgABLgADCgcJFAAEAAAAAA==.',
Te='Tempest:BAAALgAECgUJBQAAAA==.Tengen:BAAALgAECgUJDAAAAA==.Termana:BAACLgAFFH8iAAIkAAcJZB/rAgBxAQAkAAcJZB/rAgBxAQAuAAQKfygAAiQACQmCJMgCABQDACQACQmCJMgCABQDAAAA.',
Th='Thanel:BAAALgADCgQJBAAAAA==.Thanlel:BAAALgAECgMJAgAAAA==.Tharja:BAABLgAECn8bAAIWAAkJXhvvNACfAgAWAAkJXhvvNACfAgAAAA==.Theodyn:BAAALgAECgQJCgAAAA==.Thornp:BAAALgAECgEJAgAAAA==.Thoronk:BAAALgAECgcJBgAAAA==.Thsaric:BAAALgAECgEJAQAAAA==.Thug:BAABLgAECn8WAAMRAAcJ0R/RJQArAgARAAcJ0R/RJQArAgAkAAIJHxvRNgCRAAAAAA==.Thuggin:BAAALgAECgQJBQAAAA==.',
Ti='Tiferet:BAABLgAECn84AAQZAAkJ+iF7BAA6AwAZAAkJ+iF7BAA6AwAIAAgJQAs6MgBSAQAJAAQJzxepTADRAAAAAA==.Tigiw:BAAALgAECgMJBAAAAA==.Tinysunshine:BAABLgAECn8WAAIYAAgJMRwtEgAwAgAYAAgJMRwtEgAwAgAAAA==.Tinyt:BAAALgAECgEJAQAAAA==.Tiramisu:BAAALgAECgUJBQAAAA==.Tismtwo:BAAALgAECgEJAQAAAA==.Tismyhammer:BAAALgADCgQJBAAAAA==.',
To='Toasted:BAAALgADCgQJAQAAAA==.Tolenkar:BAABLgAECn8fAAIUAAkJdR0mHgBxAgAUAAkJdR0mHgBxAgAAAA==.Tomato:BAACLgAFFH8ZAAMGAAcJ8Q7aBwDxAAAHAAYJ7Q/PUwAfAQAGAAQJxA3aBwDxAAAuAAQKfyMAAwYACQlpHaYFAHoCAAYACAkIHKYFAHoCAAcABQlZFwCdAAQBAAAA.Tomhanks:BAABLgAECn8VAAIFAAkJAhVfOwAWAgAFAAkJAhVfOwAWAgAAAA==.Tormentaa:BAAALgAECgYJBwAAAA==.Torvalar:BAABLgAECn9dAAIFAAkJvRt7HwCKAgAFAAkJvRt7HwCKAgAAAA==.',
Tr='Treemendous:BAAALgADCgYJCQAAAA==.Trolgoskill:BAAALgADCgQJBAAAAA==.Truthslayer:BAABLgAECn8cAAMRAAkJKAmKSgAcAQARAAkJKAmKSgAcAQASAAEJcgr/QgAzAAAAAA==.Trûth:BAABLgAECn8WAAIIAAgJxBBMIwC9AQAIAAgJxBBMIwC9AQAAAA==.',
Tt='Tteinfante:BAAALgAECggJCAAAAA==.',
Tu='Turdyl:BAABLgAECn8sAAIFAAkJuhHOawCXAQAFAAkJuhHOawCXAQAAAA==.',
Tw='Twindad:BAAALgADCgkJEQAAAA==.Twindadlock:BAAALgAECgYJCwAAAA==.Twowheels:BAAALgAECgQJBQAAAA==.',
Ty='Tyraz:BAAALgAECgcJEwAAAA==.Tystrolf:BAABLgAECn8YAAQlAAcJrg3nRQD1AAAlAAYJ/w7nRQD1AAAXAAUJjAciNwB/AAAOAAIJgAmEcQA2AAAAAA==.',
Tz='Tzar:BAAALgADCgIJAgAAAA==.',
['Tô']='Tôx:BAABLgAECn8XAAMLAAcJWB1YLQCwAQALAAcJWB1YLQCwAQAKAAIJRhQk1QA1AAAAAA==.',
Ub='Ubrew:BAAALgAECgkJBQAAAA==.',
Ud='Udyrr:BAAALgADCgIJAgAAAA==.',
Ul='Ulfius:BAAALgADCgMJAwAAAA==.Ullume:BAAALgAECgkJDQAAAA==.',
Um='Umbranwings:BAAALgAFFAEJAQAAAA==.',
Un='Unheardjp:BAAALgAECgMJCwAAAA==.Unholy:BAAALgAECgIJBgAAAA==.',
Ur='Ursus:BAAALgADCgYJBgAAAA==.Uruloki:BAAALgAECgEJAQAAAA==.',
Va='Vacuum:BAAALgAECgYJEQAAAA==.Vadican:BAAALgADCgQJBAAAAA==.Vaerix:BAABLgAECn8vAAIdAAkJXRBmLQCGAQAdAAkJXRBmLQCGAQAAAA==.Valdora:BAAALgAECgEJAQAAAA==.Valhals:BAABLgAECn84AAMaAAkJSAsGKwBfAQAaAAkJGQkGKwBfAQAYAAMJUQ4BeABhAAAAAA==.Valydrin:BAABLgAECn9aAAIZAAkJnx73CQDIAgAZAAkJnx73CQDIAgAAAA==.Vanhelsinky:BAAALgADCgIJAgAAAA==.Vanquished:BAAALgAECgIJBAAAAA==.Varyn:BAAALgADCgIJAgAAAA==.',
Ve='Velandia:BAAALgAECgcJDAAAAA==.Velilla:BAAALgAECgQJBAAAAA==.Ventis:BAAALgAECgQJBwAAAA==.',
Vi='Vicara:BAAALgADCgYJBgAAAA==.Virgl:BAAALgAECgkJBQAAAA==.',
Vo='Voidifphat:BAAALgAECggJEAAAAA==.Voidtorrent:BAAALgAECgQJCAAAAA==.Voidvanquish:BAAALgAECgYJBwAAAA==.Vorkhan:BAAALgADCgUJCAAAAA==.',
Vu='Vuldrak:BAAALgAECggJEwAAAA==.',
Vy='Vysis:BAACLgAFFH8WAAQJAAQJrA1aLQDoAAAJAAQJcgxaLQDoAAAIAAMJKgrRAwCSAAAZAAIJ1AwHDgCOAAAuAAQKf1gABAgACQkbH+cIAL8CAAgACQkbH+cIAL8CAAkACQmUFW4SAFACABkACQlPG4cSAEwCAAAA.',
['Vä']='Vännic:BAAALgADCgEJAwAAAA==.Vännìc:BAAALgADCgEJAQAAAA==.',
['Ví']='Ví:BAABLgAECn8fAAIYAAkJsQpjLQBXAQAYAAkJsQpjLQBXAQAAAA==.',
Wh='Whatfoxsay:BAAALgADCgEJAQAAAA==.Whats:BAAALgADCgcJBwABLgAECggJFgAYAE4SAA==.When:BAAALgADCgQJBAAAAA==.Whicker:BAAALgAECgUJBgAAAA==.Whipsnchains:BAAALgAECgUJBgAAAA==.Whipsntricks:BAAALgAECgYJCQAAAA==.',
Wi='Wickèr:BAACLgAFFH8LAAMaAAMJpA+NOADEAAAaAAMJpA+NOADEAAAeAAEJCQvMaAAsAAAuAAQKfzgAAxoACQkHHk0JAJ0CABoACQkHHk0JAJ0CABgAAQnIF1eNAEQAAAAA.Wieldblade:BAABLgAECn8/AAMFAAkJ/x/NEADgAgAFAAkJ/x/NEADgAgADAAgJiBbHDwDHAQAAAA==.Wigdrag:BAAALgAECgEJAQAAAA==.Wilsondk:BAAALgAECgEJAwAAAA==.Winslett:BAAALgADCgQJBAAAAA==.',
Wo='Woggo:BAAALgAECgEJAQAAAA==.Wolfemoon:BAABLgAECn8UAAIUAAgJwwo5egBLAQAUAAgJwwo5egBLAQAAAA==.Worganlefey:BAAALgAFFAEJAQABLgAECgkJWgAHAIcaAA==.',
Wr='Wrexd:BAABLgAECn8qAAIHAAgJChtPRADOAQAHAAgJChtPRADOAQAAAA==.',
Wu='Wunderbar:BAABLgAECn9CAAMLAAkJOyLIBAAUAwALAAkJOyLIBAAUAwAKAAkJ5xjJGQB8AgAAAA==.',
Wy='Wyldfire:BAACLgAFFH8ZAAQlAAYJwxkRHQAzAQAlAAUJlhgRHQAzAQAgAAEJ/AYLawBEAAAOAAEJHgocRAAkAAAuAAQKfy8AAyUACQleI/kLANgCACUACQleI/kLANgCACAAAwksEo2eAI4AAAAA.Wyndclaw:BAABLgAECn8WAAIeAAYJcBaGOQCLAQAeAAYJcBaGOQCLAQAAAA==.',
Xa='Xanith:BAABLgAECn8tAAIRAAgJehhEIQDnAQARAAgJehhEIQDnAQAAAA==.',
Xe='Xebubble:BAAALgADCgEJAQABLgAECgEJAQAEAAAAAA==.Xemonk:BAAALgAECgEJAQAAAA==.',
Xi='Xia:BAAALgADCgYJBgAAAA==.',
Xr='Xroi:BAAALgAECgIJAgAAAA==.',
Ya='Yaganor:BAAALgADCgUJBgAAAA==.',
Ye='Yeto:BAAALgADCgYJBwAAAA==.',
Yi='Yia:BAAALgAECgUJCQABLgAECgUJEgAEAAAAAA==.Yilnara:BAABLgAECn8bAAITAAkJDgdifgAjAQATAAkJDgdifgAjAQAAAA==.',
Yo='Yondo:BAAALgAECgMJAwAAAA==.',
Ys='Ysa:BAABLgAECn8eAAMYAAcJuCShEAB3AgAYAAcJuCShEAB3AgAeAAEJlA2UbAApAAAAAA==.',
Za='Zajindor:BAAALgADCgEJAQAAAA==.Zarathul:BAAALgADCgIJAgAAAA==.',
Ze='Zekkun:BAAALgAECgEJAQAAAA==.',
Zh='Zheria:BAAALgAECgQJBAAAAA==.',
Zi='Zirael:BAAALgADCgYJCgAAAA==.',
Zo='Zod:BAAALgAECgkJCQAAAA==.Zoganian:BAEALgAECgUJEgABLgAECgkJJwAZAAUhAA==.Zogula:BAEBLgAECn8nAAQZAAkJBSHhCwCpAgAZAAkJ0iDhCwCpAgAIAAQJXxZPQQAKAQAJAAEJaiOJZwBgAAAAAA==.',
Zu='Zu:BAAALgAECgcJEAABLgAECgkJDAAEAAAAAA==.',
Zy='Zynara:BAAALgAECgYJCAAAAA==.',
['År']='Årtemis:BAABLgAECn8xAAIoAAgJwB27DQBMAgAoAAgJwB27DQBMAgAAAA==.',
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
