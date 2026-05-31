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

local lookup = {'Shaman-Elemental','Shaman-Restoration','Monk-Windwalker','Mage-Frost','Monk-Brewmaster','DeathKnight-Blood','Warlock-Destruction','Hunter-BeastMastery','Unknown-Unknown','DeathKnight-Unholy','DeathKnight-Frost','Druid-Restoration','Druid-Feral','Paladin-Holy','Paladin-Protection','Warrior-Fury','Paladin-Retribution','Priest-Shadow','Warlock-Demonology','Warrior-Protection','Monk-Mistweaver','Evoker-Devastation','Druid-Balance','Warrior-Arms','Shaman-Enhancement','DemonHunter-Devourer','Priest-Discipline','Priest-Holy','Evoker-Augmentation','Evoker-Preservation','DemonHunter-Havoc','DemonHunter-Vengeance','Hunter-Survival','Druid-Guardian','Warlock-Affliction','Mage-Fire','Mage-Arcane','Hunter-Marksmanship','Rogue-Subtlety','Rogue-Outlaw',}
local provider = {region='US',realm='GrizzlyHills',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Abramz:BAAALgADCgMJAwAAAA==.',
Ad='Addly:BAAALgADCgkJDQAAAA==.Adely:BAAALgAECgEJAQAAAA==.Adelymon:BAABLgAECn8YAAMBAAkJZxaPFQAiAgABAAkJZxaPFQAiAgACAAUJARDfeADSAAAAAA==.Adelymonk:BAAALgAECgYJEAAAAA==.Adonysroth:BAAALgAECgIJAgAAAA==.Adrahil:BAAALgADCgIJAgAAAA==.',
Ae='Aeonra:BAAALgADCgIJAgAAAA==.',
Ag='Agronak:BAAALgAECgQJBgAAAA==.',
Al='Aldan:BAAALgADCgMJAwAAAA==.Aldazen:BAACLgAFFH8NAAIDAAMJnSMHDwAxAQADAAMJnSMHDwAxAQAuAAQKfzgAAgMACQnMI+UCACwDAAMACQnMI+UCACwDAAAA.Alenara:BAAALgAECgYJDwABLgAECggJHAAEAJwKAA==.Aletheìa:BAAALgAECgEJAQAAAA==.Alovan:BAAALgADCgEJAQABLgAECgcJHgAFANoKAA==.Alterbeast:BAAALgAECgIJAgABLgAFFAUJCgAGAAEdAA==.Alyssandra:BAABLgAECn8jAAIHAAgJhRU5BwDGAQAHAAgJhRU5BwDGAQAAAA==.',
Am='Amarella:BAABLgAECn8UAAIIAAcJqiCkKQAQAgAIAAcJqiCkKQAQAgAAAA==.Amarrite:BAAALgAECgQJBgAAAA==.Ammalane:BAAALgAECgIJAgABLgAECgQJBgAJAAAAAA==.Amunzo:BAAALgAECgEJAQABLgAECgkJDQAJAAAAAA==.',
An='Angler:BAAALgAECgMJAwAAAA==.Angyrolaj:BAABLgAECn8XAAMKAAcJ0xfNWwCgAQAKAAcJgBfNWwCgAQALAAIJdBUXEQCFAAAAAA==.',
Aq='Aquadora:BAAALgADCgMJAwAAAA==.',
Ar='Arangarr:BAABLgAECn8xAAMMAAkJpx1jDADrAgAMAAkJpx1jDADrAgANAAEJ1BGYQQA6AAAAAA==.Arcin:BAAALgADCgEJAQAAAA==.Areyana:BAABLgAECn8WAAIIAAcJvBFRaABaAQAIAAcJvBFRaABaAQAAAA==.Areyoudead:BAAALgAECgQJBAABLgADCgYJCwAJAAAAAA==.Ariolas:BAAALgADCgYJCQAAAA==.Aristoi:BAAALgAECgEJAQAAAA==.Arkand:BAAALgADCgUJBAAAAA==.Arkandra:BAAALgAECgYJEgAAAA==.Arkara:BAAALgADCgEJAQAAAA==.Arrietty:BAABLgAECn8aAAIOAAYJlxUPPABAAQAOAAYJlxUPPABAAQAAAA==.Arthues:BAABLgAECn8WAAIPAAgJDBxyCAA1AgAPAAgJDBxyCAA1AgAAAA==.Arthâs:BAAALgAECgYJBQAAAA==.Arumathe:BAABLgAECn8XAAIPAAkJxxKwDwCuAQAPAAkJxxKwDwCuAQAAAA==.',
As='Asura:BAACLgAFFH8QAAIQAAQJMCKhCgCOAQAQAAQJMCKhCgCOAQAuAAQKfyAAAhAACQnLItkIAB4DABAACQnLItkIAB4DAAAA.',
Au='Aurelian:BAAALgAECgEJAgAAAA==.',
Az='Az:BAABLgAECn8fAAIQAAcJKya0DQCAAgAQAAcJKya0DQCAAgAAAA==.Azeriall:BAACLgAFFH8MAAIBAAMJHAvoLQC5AAABAAMJHAvoLQC5AAAuAAQKf0EAAwEACQksFpgVACECAAEACQksFpgVACECAAIABAlKAVuGAHsAAAAA.Azerowolf:BAAALgADCggJCAAAAA==.Azráèl:BAAALgADCgMJAwAAAA==.',
Ba='Babyboom:BAAALgAECgEJAQAAAA==.Baconhammr:BAABLgAECn8YAAMRAAcJQww6oQAaAQARAAcJQww6oQAaAQAOAAUJEgd2eACXAAAAAA==.Badazmf:BAAALgADCgcJDAABLgAECgkJNAASACEbAA==.Badcompany:BAAALgADCgUJBQABLgAECggJLAAMAMgOAA==.Baddream:BAAALgAECgYJDgAAAA==.Baelmyre:BAAALgADCgUJBQAAAA==.Balenciagosa:BAAALgADCgUJBQABLgAECggJHAAEAJwKAA==.Banshiï:BAABLgAECn8rAAIHAAgJihK1CgB5AQAHAAgJihK1CgB5AQAAAA==.Baratheøn:BAABLgAECn8nAAIMAAgJURfSLADiAQAMAAgJURfSLADiAQAAAA==.Bax:BAAALgADCgIJAgAAAA==.Baxar:BAAALgAECgIJAgAAAA==.',
Bb='Bbd:BAAALgAECggJCQABLgAECgYJDgAJAAAAAA==.',
Be='Beeftard:BAABLgAECn8YAAIOAAkJWRZiKgDfAQAOAAkJWRZiKgDfAQAAAA==.Bellavix:BAAALgADCgMJBAAAAA==.Benafflic:BAAALgAECgEJAQABLgAECgQJBAAJAAAAAA==.Berserrk:BAAALgADCgYJBgAAAA==.Bershale:BAAALgAECgEJAQABLgAECgYJBwAJAAAAAA==.',
Bi='Bifficus:BAAALgAECgYJDgAAAA==.Big:BAAALgADCgMJBAAAAA==.Biggiecheese:BAAALgAECgMJBAAAAA==.',
Bl='Blackscorn:BAAALgADCgEJAQAAAA==.Blackthôrne:BAAALgADCgUJCQAAAA==.Blucki:BAABLgAECn8fAAITAAgJ7QnlfAA0AQATAAgJ7QnlfAA0AQAAAA==.',
Bo='Bobfu:BAAALgADCgYJCAAAAA==.',
Br='Brieze:BAAALgADCgIJAgAAAA==.Brige:BAAALgAECggJBgAAAA==.Brightstar:BAAALgADCgEJAQAAAA==.Brimaz:BAAALgADCgEJAQAAAA==.',
Bu='Buhhead:BAAALgADCgUJBgAAAA==.Bunana:BAAALgADCgEJAQAAAA==.Bunbear:BAAALgAECgIJAgAAAA==.Bunette:BAAALgADCgEJAQAAAA==.',
Bw='Bwamsamdi:BAAALgADCgYJBgAAAA==.',
By='Byzantium:BAABLgAECn8kAAIUAAcJJAe1KADVAAAUAAcJJAe1KADVAAAAAA==.',
['Bô']='Bônebeard:BAAALgAECgEJAQAAAA==.',
Ca='Cabledryer:BAAALgAECgQJEAAAAA==.Caelidpackx:BAAALgADCgYJBwAAAA==.Calamitty:BAAALgAECgMJAwAAAA==.Calistin:BAAALgAECgYJBgAAAA==.Callmedatty:BAAALgAECgEJAQAAAA==.Caluu:BAAALgADCgEJAQAAAA==.Carnry:BAAALgADCgQJBAAAAA==.Catboy:BAABLgAECn8cAAIEAAkJMhXUcAB+AQAEAAkJMhXUcAB+AQAAAA==.Catnips:BAABLgAECn8cAAIRAAgJURjhXwCXAQARAAgJURjhXwCXAQAAAA==.Catpow:BAAALgAECgkJAgAAAA==.',
Ch='Chanaranach:BAAALgAECgYJCgAAAA==.Charitey:BAAALgAECgMJBAAAAA==.Cheelo:BAAALgAECggJEAAAAA==.Chknnugget:BAAALgAECgMJBQAAAA==.Chromatic:BAABLgAECn8pAAMCAAgJphYmJAAbAgACAAgJphYmJAAbAgABAAQJYg7BXgCsAAAAAA==.',
Ci='Cindrethresh:BAAALgAECgQJCQAAAA==.',
Co='Coffeeblak:BAABLgAECn8ZAAMDAAgJBRNLJgCmAQADAAcJlxNLJgCmAQAVAAUJFQ65PwDkAAAAAA==.Coldstorm:BAAALgAECgcJCwAAAA==.Collision:BAAALgAECgcJDwAAAA==.Compensating:BAAALgADCgYJBgAAAA==.Connor:BAAALgADCgcJBwAAAA==.Connsumption:BAAALgAECgYJCgAAAA==.Corrine:BAAALgAECgYJCwAAAA==.',
Cr='Crazybatt:BAABLgAECn8UAAIRAAYJXgYF4wC7AAARAAYJXgYF4wC7AAAAAA==.Crypt:BAAALgAECgYJCgAAAA==.',
Cu='Cuckchairpov:BAACLgAFFH8OAAMFAAQJJRQSHgAhAQAFAAQJpBMSHgAhAQADAAIJQg15DACgAAAuAAQKfywAAwMACQkqH2gKANICAAMACAl4HWgKANICAAUACQndFAETAAgCAAAA.',
Cy='Cynderleena:BAAALgAECgYJBwAAAA==.Cynyia:BAABLgAECn8vAAIIAAkJxROsOgDdAQAIAAkJxROsOgDdAQAAAA==.',
Cz='Czk:BAAALgADCgYJBgABLgAECggJGQADAAUTAA==.',
['Có']='Cóldblóód:BAAALgAECgIJAgAAAA==.',
Da='Daddyelessar:BAAALgAECgcJDgAAAA==.Dafattyup:BAABLgAECn8aAAITAAYJlRxUYwCgAQATAAYJlRxUYwCgAQAAAA==.Daghmar:BAAALgADCgUJBQAAAA==.Dagon:BAAALgAECgMJAwAAAA==.Dakotarain:BAAALgADCgIJAgAAAA==.Dalerontwo:BAAALgADCgEJAQAAAA==.Darruin:BAACLgAFFH8IAAIKAAQJ+B5MKwCEAQAKAAQJ+B5MKwCEAQAuAAQKfyEAAgoACAl5I5kSAMcCAAoACAl5I5kSAMcCAAEuAAUUBgkcABYAzxwA.Dayrun:BAAALgAECgUJDQAAAA==.',
De='Deadicee:BAAALgAECgIJAgABLgAECgYJEwAJAAAAAA==.Deadlyvixin:BAAALgADCgUJBQAAAA==.Deadstorm:BAAALgAECgUJBQAAAA==.Deathturtle:BAABLgAECn8eAAIKAAgJLxCEhABFAQAKAAgJLxCEhABFAQAAAA==.Deavaos:BAAALgAECgUJCAAAAA==.Dedmartigan:BAAALgADCgUJBQAAAA==.Deeanndra:BAABLgAECn8kAAMKAAcJChBxfgBRAQAKAAcJChBxfgBRAQALAAEJDAkuOQAUAAAAAA==.Deevz:BAAALgAECgIJAgAAAA==.Demandred:BAAALgAECgYJCQAAAA==.Demiz:BAABLgAECn84AAMCAAkJ5Ro0FACQAgACAAkJ5Ro0FACQAgABAAcJug7JPwAYAQAAAA==.Deredris:BAAALgAECgQJBAABLgAECgYJCgAJAAAAAA==.Dertka:BAAALgAECgYJDAAAAA==.',
Di='Discodruid:BAABLgAECn8UAAIMAAYJKRP9TgBAAQAMAAYJKRP9TgBAAQAAAA==.Dishsoap:BAAALgAECgMJAwABLgAFFAYJEgAQAF4WAA==.Dixie:BAAALgAECgEJAQAAAA==.',
Dj='Djall:BAAALgAECgUJBQAAAA==.',
Do='Dommy:BAABLgAECn8bAAIGAAkJ1iRqAQBGAwAGAAkJ1iRqAQBGAwAAAA==.Domw:BAAALgAECgYJCwABLgAECgkJGwAGANYkAA==.Donham:BAACLgAFFH8XAAMKAAYJ9xsRJQCXAQAKAAUJ9xsRJQCXAQAGAAEJAABBEwBZAAAuAAQKfx8AAgoACAnLHzweAMsCAAoACAnLHzweAMsCAAAA.Dorkimedes:BAAALgAECgQJCwAAAA==.Dottie:BAABLgAECn8oAAMHAAgJNhM2FwCQAQAHAAcJJQ82FwCQAQATAAgJ7xHFVQCPAQAAAA==.Dotvinci:BAAALgAECgYJBgAAAA==.',
Dr='Draelesh:BAABLgAECn8zAAIXAAgJLRRwHwCzAQAXAAgJLRRwHwCzAQAAAA==.Draenk:BAAALgADCgUJBQAAAA==.Dragún:BAAALgAECgYJCwAAAA==.Drakari:BAAALgADCgYJBgAAAA==.Dramborleg:BAAALgAECgEJAQAAAA==.Drazon:BAAALgADCgIJAgAAAA==.Drewit:BAABLgAECn8WAAINAAYJPxA1FQBiAQANAAYJPxA1FQBiAQAAAA==.',
Du='Ducan:BAAALgADCgYJCQAAAA==.Duskmane:BAAALgAECgMJBwAAAA==.',
Dw='Dwadler:BAACLgAFFH8LAAMYAAYJCBDkEAAqAQAYAAYJCBDkEAAqAQAUAAIJnQppIQBlAAAuAAQKfyoAAxQACAmDHUIJAEwCABQACAmDHUIJAEwCABgAAQnOGq9cAEwAAAAA.',
Dy='Dyrkonian:BAAALgAECggJDwAAAA==.',
Ei='Eireann:BAAALgADCgcJCQAAAA==.',
El='Elerrak:BAAALgAECgEJAQABLgAFFAcJHwAZACcdAA==.Elindalia:BAAALgAECgMJAwAAAA==.',
Em='Emberash:BAAALgAECgEJAQAAAA==.Embre:BAABLgAFFH8KAAIWAAQJsA5oBAAjAQAWAAQJsA5oBAAjAQAAAA==.Emorri:BAAALgAECgYJBgAAAA==.Empyrea:BAAALgAECgQJBQAAAA==.',
Er='Eraina:BAAALgADCgIJAgAAAA==.Ericles:BAABLgAECn8ZAAMYAAcJ8R1VDADbAQAYAAcJ8R1VDADbAQAQAAIJlAVwlwBkAAAAAA==.Erys:BAAALgAECgcJEAAAAA==.Erébus:BAABLgAECn8iAAIaAAkJ7xgBJAAqAgAaAAkJ7xgBJAAqAgAAAA==.',
Ev='Ev:BAAALgAECgQJBAAAAA==.Evergreene:BAAALgADCggJCAABLgAECgQJBgAJAAAAAA==.Evlpotato:BAABLgAECn80AAQSAAkJIRuzEAA3AgASAAkJIRuzEAA3AgAbAAcJNBpAHADKAQAcAAEJlAdTfwAzAAAAAA==.Evojak:BAABLgAECn8aAAMdAAcJqwbETgDMAAAdAAcJqwbETgDMAAAWAAMJxAMEGwBkAAAAAA==.',
Fa='Fabiyo:BAAALgADCgMJBQAAAA==.Faevelia:BAAALgAECgUJBgAAAA==.Fairaday:BAABLgAECn83AAIIAAkJXwt0SgCqAQAIAAkJXwt0SgCqAQAAAA==.Falloon:BAAALgADCgYJBgAAAA==.Fanshen:BAAALgAECgMJBQAAAA==.Farmerdave:BAAALgAECgEJAQAAAA==.Fauchi:BAAALgADCgEJAQAAAA==.Faxqueenmage:BAABLgAECn8bAAIEAAcJgQKF5ACyAAAEAAcJgQKF5ACyAAAAAA==.',
Fe='Felador:BAAALgAECgcJDAABLgAECggJKgATABYRAA==.Feldo:BAABLgAECn8SAAIaAAYJjyE7NQDaAQAaAAYJjyE7NQDaAQAAAA==.Felmès:BAAALgADCgYJBgABLgAECggJHAAEAJwKAA==.Fennec:BAAALgAECgUJDAAAAA==.Feralarak:BAAALgAECgcJEwABLgAFFAcJHwAZACcdAA==.',
Fi='Firebrandd:BAACLgAFFH8cAAMWAAYJzxzAAQBzAQAWAAUJnyDAAQBzAQAdAAUJZhE4GQBaAQAuAAQKfzsAAxYACQl8I2ACAA8DABYACAksImACAA8DAB0ACQlEIuMHAMMCAAAA.Fizehbubbleh:BAEALgAECgYJCAABLgAECggJIAABAOgaAA==.Fizehtotems:BAEBLgAECn8gAAMBAAgJ6BpkKACRAQABAAgJ6BpkKACRAQACAAUJixbCVQA/AQAAAA==.',
Fl='Fleshoracle:BAAALgAECgQJBAABLgAFFAUJCgAGAAEdAA==.Fluctuates:BAAALgAECgQJCAAAAA==.',
Fo='Foragarn:BAAALgAECgYJCQAAAA==.Foron:BAAALgAECgIJAgAAAA==.',
Fr='Frankkastle:BAAALgAECgYJDwAAAA==.Frazelia:BAAALgADCgkJDgABLgAECgYJFgANAD8QAA==.Fribble:BAABLgAECn8ZAAMCAAkJmw7KNADDAQACAAkJmw7KNADDAQAZAAEJAADHPQAAAAAAAA==.Froggierlynx:BAAALgAFFAQJBAAAAA==.Frostalot:BAAALgADCgcJBwAAAA==.Froznfate:BAABLgAECn8rAAIPAAgJ4yWZAgDtAgAPAAgJ4yWZAgDtAgAAAA==.Fryes:BAAALgAECgkJDAAAAA==.',
Fu='Fuzziebutt:BAAALgAECgQJBAAAAA==.',
Fw='Fwibble:BAAALgAECggJEgABLgAECgkJGQACAJsOAA==.',
Fy='Fyrelady:BAAALgADCggJDgABLgAECgMJCAAJAAAAAA==.Fyrestone:BAAALgAECgMJCAAAAA==.',
['Fæ']='Fæder:BAAALgADCgYJBgAAAA==.',
Ga='Gabarnak:BAAALgADCgIJAgAAAA==.Gabuse:BAAALgAECgQJBAAAAA==.Galencharred:BAABLgAECn8hAAIRAAcJ3AjXtQD6AAARAAcJ3AjXtQD6AAAAAA==.Garagon:BAABLgAECn8zAAIeAAgJxhYbDAADAgAeAAgJxhYbDAADAgAAAA==.Gauss:BAABLgAECn8dAAIPAAgJoAbFIgDiAAAPAAgJoAbFIgDiAAABLgAECgkJGQACAJsOAA==.Gaîîa:BAABLgAECn8cAAIIAAgJCRq2MADtAQAIAAgJCRq2MADtAQAAAA==.',
Ge='Gerva:BAABLgAECn8wAAIKAAgJFhKlWACoAQAKAAgJFhKlWACoAQAAAA==.',
Gh='Ghlain:BAAALgAECgQJBwAAAA==.Ghorfindor:BAABLgAECn8gAAIfAAcJ5wNvOAC1AAAfAAcJ5wNvOAC1AAAAAA==.Ghostlybrew:BAACLgAFFH8VAAIFAAcJ9xvOBwDZAQAFAAcJ9xvOBwDZAQAuAAQKfxYAAgUACAmpH94TAHECAAUACAmpH94TAHECAAAA.',
Gi='Gigastorm:BAAALgADCgIJAQAAAA==.Gilas:BAABLgAECn8mAAQKAAcJKA/bpAAPAQAKAAcJOwfbpAAPAQAGAAYJcBB0LQDXAAALAAUJXgUPIwB8AAAAAA==.',
Gl='Glaivemstake:BAAALgADCgcJBwAAAA==.',
Gn='Gnik:BAAALgAECggJEAAAAA==.',
Go='Goswin:BAAALgAECgEJAgAAAA==.',
Gr='Graahak:BAAALgADCgMJAwAAAA==.Graveborn:BAABLgAFFH8KAAIGAAUJAR2YEABCAQAGAAUJAR2YEABCAQAAAA==.Graydenton:BAAALgAECgkJCQABLgAECggJBgAJAAAAAA==.Greenfelpowa:BAABLgAECn8ZAAITAAkJpQ/AQQDKAQATAAkJpQ/AQQDKAQAAAA==.Gruuven:BAAALgADCgUJBwAAAA==.',
Gu='Gutmtmon:BAABLgAECn8WAAIDAAYJHggGSQDGAAADAAYJHggGSQDGAAAAAA==.',
Gw='Gwenivive:BAABLgAECn8hAAIIAAkJjBc5JAA6AgAIAAkJjBc5JAA6AgAAAA==.',
['Gí']='Gízmo:BAAALgADCgUJBQAAAA==.',
Ha='Haenus:BAABLgAECn8dAAIaAAgJ8hPncgAhAQAaAAgJ8hPncgAhAQAAAA==.Hamor:BAAALgAECgkJCgAAAA==.Harrynear:BAAALgADCgMJAwABLgAECgcJFwAKANMXAA==.Hat:BAACLgAFFH8FAAIaAAIJ9CJlVQDMAAAaAAIJ9CJlVQDMAAAuAAQKfxkAAxoACQl8IuYFABsDABoACQl8IuYFABsDACAAAgmRCg0oAE0AAAAA.Haunt:BAAALgAECgUJBgAAAA==.Havark:BAAALgAECgMJAwAAAA==.',
He='Healbilly:BAAALgADCgEJAQAAAA==.Healingdeath:BAAALgADCgMJBAAAAA==.Hecatombe:BAAALgADCgUJBQAAAA==.Hellda:BAEALgAECgkJBgABLgAFFAMJCwARADwIAA==.Hellzdruid:BAAALgADCgQJBAAAAA==.Hellzknîght:BAABLgAECn8hAAIKAAcJuxTTbAB3AQAKAAcJuxTTbAB3AQAAAA==.Hellzshaman:BAAALgADCgIJAQAAAA==.',
Ho='Holek:BAABLgAECn8WAAMIAAgJ+Q5OUwCQAQAIAAgJvw5OUwCQAQAhAAMJcARtRgCIAAAAAA==.Holgo:BAACLgAFFH8HAAIUAAQJcx8rCwBVAQAUAAQJcx8rCwBVAQAuAAQKfyEAAhQACQluJVIBAEUDABQACQluJVIBAEUDAAAA.Holgy:BAACLgAFFH8aAAIiAAYJtCLFAQANAgAiAAYJtCLFAQANAgAuAAQKfyYAAiIACQlWI0wBAEkDACIACQlWI0wBAEkDAAAA.Holybeard:BAACLgAFFH8IAAIRAAMJlBn2TwDuAAARAAMJlBn2TwDuAAAuAAQKfzkAAhEACAnyIDkaAI8CABEACAnyIDkaAI8CAAAA.Hooks:BAAALgAECgMJAwAAAA==.',
Hu='Hugecowballs:BAAALgAECgkJCQAAAA==.Hunterturtle:BAAALgADCgUJBQAAAA==.',
Ic='Icia:BAAALgAECgEJAQAAAA==.',
Id='Idontmiss:BAAALgAECgIJCAAAAA==.',
Il='Ilickboody:BAAALgADCgQJBAAAAA==.Illustra:BAABLgAECn8ZAAMcAAgJnAb7NAAYAQAcAAgJnAb7NAAYAQASAAcJ3gLQUwCYAAABLgAECggJHAAEAJwKAA==.',
Im='Imcaldo:BAAALgADCgYJBgAAAA==.Imcaldoo:BAAALgADCgUJCgAAAA==.',
In='Interrupt:BAAALgAECgUJDQAAAA==.',
Ir='Irox:BAAALgADCgMJAwAAAA==.',
Is='Isaic:BAAALgADCgIJAgAAAA==.Iseila:BAABLgAECn8YAAIEAAkJ+A1yZQCZAQAEAAkJ+A1yZQCZAQAAAA==.Isevio:BAAALgAECgMJBwAAAA==.',
It='Ithorus:BAAALgAECgYJEgAAAA==.',
Ja='Jaadb:BAAALgAECgMJBgAAAA==.Jaadd:BAAALgAECgIJAgAAAA==.Jaadi:BAAALgAECgIJAwAAAA==.Jaata:BAAALgADCgcJEAAAAA==.Jairl:BAAALgAECgMJAwAAAA==.Jamien:BAABLgAECn84AAMRAAgJQB+uJQBVAgARAAgJQB+uJQBVAgAOAAUJigUsdwCdAAAAAA==.Janal:BAAALgADCgEJAQAAAA==.Jasnah:BAAALgAECgYJEAAAAA==.Jasnos:BAAALgAECgUJDAAAAA==.',
Jd='Jdk:BAAALgAECgUJBwAAAA==.',
Je='Jelf:BAAALgAECgQJBAAAAA==.Jenzing:BAABLgAECn8VAAMTAAgJqh0QKwBjAgATAAcJqh0QKwBjAgAjAAEJAACuIwBjAAAAAA==.Jessemyn:BAAALgAECgYJEQAAAA==.',
Jh='Jholy:BAAALgAECgMJAwAAAA==.',
Jo='Jobokenhones:BAABLgAECn8xAAIaAAkJIBqpHwBDAgAaAAkJIBqpHwBDAgAAAA==.Johadgan:BAAALgADCgEJAQAAAA==.',
Jp='Jproudmore:BAAALgADCgUJBQABLgADCgYJCwAJAAAAAA==.',
Js='Jsberg:BAABLgAECn8eAAIQAAgJwRXDKQCcAQAQAAgJwRXDKQCcAQAAAA==.',
Ka='Kaathe:BAABLgAECn8lAAMEAAYJGx7ihADHAQAEAAYJGx7ihADHAQAkAAEJjhqXDwA4AAAAAA==.Kaboomalis:BAAALgADCgUJBQAAAA==.Kadance:BAABLgAECn8WAAIBAAcJmRZKLgBvAQABAAcJmRZKLgBvAQAAAA==.Kaidiis:BAABLgAECn8sAAIRAAgJAg+zdQBoAQARAAgJAg+zdQBoAQAAAA==.Kaido:BAAALgAECgEJAQAAAA==.Kalder:BAAALgADCgcJBwAAAA==.Karbonn:BAABLgAECn8WAAIWAAcJuBUPCQCHAQAWAAcJuBUPCQCHAQAAAA==.Kay:BAAALgAECgcJBwAAAA==.Kazeraz:BAAALgADCgEJAQAAAA==.',
Ke='Kegbreaker:BAABLgAECn83AAIcAAkJUAppJwB1AQAcAAkJUAppJwB1AQAAAA==.',
Kh='Khanas:BAABLgAECn8WAAIOAAcJiBePKQCrAQAOAAcJiBePKQCrAQAAAA==.Kheru:BAAALgADCgkJFAAAAA==.Khoan:BAAALgAECgYJCgAAAA==.',
Ki='Kimbustible:BAABLgAECn85AAIEAAkJOCSZCwAIAwAEAAkJOCSZCwAIAwAAAA==.Kimchi:BAABLgAECn8WAAIFAAgJlhC9JAB0AQAFAAgJlhC9JAB0AQABLgAECgkJOQAEADgkAA==.',
Kn='Knockknocko:BAAALgAECgcJDgAAAA==.',
Ko='Kobir:BAAALgADCgEJAQAAAA==.Komodostyle:BAABLgAECn81AAQeAAkJYg3TFQBdAQAeAAgJywrTFQBdAQAdAAUJ/hOGRQDxAAAWAAIJWw64NQBoAAAAAA==.Koobideh:BAAALgADCgEJAQAAAA==.',
Kr='Krayose:BAAALgAECgYJBgAAAA==.Kriddler:BAAALgADCgQJBAAAAA==.Krisarugala:BAABLgAECn8VAAIXAAcJgA0+PAADAQAXAAcJgA0+PAADAQAAAA==.',
Ku='Kujoluvsmilf:BAAALgAECggJCwAAAA==.Kunuku:BAAALgADCgUJBQAAAA==.Kurash:BAAALgADCgcJBwAAAA==.Kurion:BAAALgAECgkJBAAAAA==.Kurogami:BAAALgAECgMJAwAAAA==.',
Ky='Kylesxmom:BAACLgAFFH8SAAMKAAUJlxPyVQArAQAKAAQJlxPyVQArAQAGAAIJuA3PNAAwAAAuAAQKf2AAAwoACQltJCAGADsDAAoACQlAJCAGADsDAAYACAn/HVgPAPkBAAAA.Kymal:BAABLgAECn88AAIaAAkJzRVrMQDqAQAaAAkJzRVrMQDqAQAAAA==.Kymbria:BAAALgADCgUJCAAAAA==.Kymora:BAAALgADCgcJBwAAAA==.Kyndrissa:BAAALgADCgUJBQAAAA==.',
['Kë']='Këy:BAACLgAFFH8MAAIKAAMJQBi1egDoAAAKAAMJQBi1egDoAAAuAAQKfykAAgoACAnUHYwsAIYCAAoACAnUHYwsAIYCAAAA.',
La='Latrice:BAACLgAFFH8hAAIEAAgJ7h2fBwCBAgAEAAgJ7h2fBwCBAgAuAAQKfygABAQACQk5I9wJAHYDAAQACQk5I9wJAHYDACQAAwm4GcMIANUAACUAAQltGN0YAFEAAAAA.Lavynder:BAABLgAECn8XAAIaAAgJ5hUVWgCTAQAaAAgJ5hUVWgCTAQAAAA==.Lazerturkey:BAAALgAECgkJDwAAAA==.Laërtes:BAAALgAECgUJDwAAAA==.',
Le='Leiamirage:BAAALgAECgYJDwAAAA==.Leviscus:BAAALgAECgQJCQAAAA==.',
Li='Lifetap:BAAALgADCgMJAwAAAA==.Lightbill:BAAALgAECggJCAABLgAECgkJLwAMAM4dAA==.Lightbàne:BAABLgAECn8lAAINAAgJWiNmAwDEAgANAAgJWiNmAwDEAgAAAA==.Lightningrod:BAAALgAECgYJBwAAAA==.Lightshaolin:BAAALgAECgQJBAAAAA==.Lildruidz:BAABLgAECn8dAAMMAAcJbhMrPACRAQAMAAcJbhMrPACRAQAXAAEJLQKClgAZAAAAAA==.Lillivarak:BAABLgAECn8UAAIRAAcJFgeSxQDjAAARAAcJFgeSxQDjAAAAAA==.Lilriotz:BAAALgAECgQJBQAAAA==.Lilriotzz:BAAALgAECggJEAAAAA==.Lilzdrlockz:BAAALgAECgUJBgAAAA==.Lithedra:BAAALgADCgcJDwAAAA==.Littlehand:BAAALgADCgUJBAABLgAECgYJGgAOAJcVAA==.',
Lo='Lovecraft:BAAALgADCgUJBQAAAA==.',
Lu='Lucavi:BAAALgAECgMJAwAAAA==.Lucyvar:BAAALgAECgkJCwAAAA==.Luke:BAAALgADCgUJBwAAAA==.Luma:BAAALgAECgQJCAAAAA==.Luther:BAABLgAECn8XAAIFAAkJNw9XJQDYAQAFAAkJNw9XJQDYAQAAAA==.',
Ly='Lyla:BAAALgADCgQJBgAAAA==.',
Ma='Magnux:BAAALgAECgEJAgAAAA==.Malazark:BAAALgADCgYJBgAAAA==.Malríus:BAAALgAECgQJEQAAAA==.Manales:BAAALgAECgcJBgAAAA==.Marhukai:BAABLgAECn8vAAIRAAkJQR/0EwC2AgARAAkJQR/0EwC2AgAAAA==.Marotal:BAABLgAECn8kAAIEAAcJNxaIZQCZAQAEAAcJNxaIZQCZAQAAAA==.Martysparty:BAABLgAECn8yAAIPAAkJER3aBQB3AgAPAAkJER3aBQB3AgAAAA==.Mavaena:BAAALgAECgYJCwAAAA==.Mavrane:BAAALgADCgEJAgAAAA==.',
Me='Meashakegs:BAAALgAECggJEQAAAA==.Meashaman:BAAALgAECgMJAwAAAA==.Mechaboomer:BAABLgAECn8yAAIIAAgJyRu6JwAqAgAIAAgJyRu6JwAqAgAAAA==.Megafire:BAAALgADCgkJEwAAAA==.Megahertz:BAAALgADCggJCAAAAA==.Melcanthet:BAAALgADCggJCAAAAA==.Mellowrock:BAAALgAECgUJBgABLgAECgYJBQAJAAAAAA==.',
Mi='Mickhaggis:BAAALgADCgIJAgAAAA==.Micktarogar:BAAALgAECgcJEwAAAA==.Mickwutang:BAAALgAFFAEJAQAAAA==.Miklaga:BAAALgAECgEJAgAAAA==.Milince:BAAALgADCgMJAgAAAA==.Milkfridge:BAAALgAECgEJAQAAAA==.Minikloon:BAAALgAECgYJDgAAAA==.Minphoria:BAAALgADCgQJBgAAAA==.Missylock:BAAALgADCgYJBgAAAA==.Mistilinn:BAABLgAECn8qAAImAAkJXQeOEAA6AQAmAAkJXQeOEAA6AQAAAA==.Miyri:BAAALgAECgEJAgABLgAFFAMJCQAMAM8WAA==.',
Mo='Mollyporph:BAAALgAECgEJAQAAAA==.Monoco:BAAALgAECgYJEwAAAA==.Moopandax:BAACLgAFFH8aAAIXAAYJqR+dBwDfAQAXAAYJqR+dBwDfAQAuAAQKf0YAAxcACQnbJe4AAHkDABcACQnbJe4AAHkDACIACAmhH68GAHQCAAEuAAUUBQkXABcACyEA.Mortrum:BAAALgADCgQJBAAAAA==.Moxestime:BAAALgAECgEJAgAAAA==.Moxsdeath:BAAALgADCgYJBgAAAA==.Moxsdeaths:BAAALgADCgcJBwAAAA==.',
Mu='Mushaboom:BAABLgAECn8WAAIFAAcJ9gerPgDuAAAFAAcJ9gerPgDuAAAAAA==.Muzzler:BAABLgAECn9MAAIEAAgJGiIwHgCSAgAEAAgJGiIwHgCSAgAAAA==.',
My='Myeyes:BAAALgAECgEJAwAAAA==.Mylinkah:BAAALgADCgQJBAAAAA==.Mynamefizz:BAEBLgAECn8XAAQTAAkJNBn6LQAUAgATAAkJ9xX6LQAUAgAjAAMJeh1LFQD6AAAHAAMJghQVHQCrAAABLgAECggJIAABAOgaAA==.Myotonic:BAAALgADCgQJBAAAAA==.Mythlok:BAAALgAECgMJAwAAAA==.Mythreiel:BAAALgAECgUJBgAAAA==.Mythykal:BAAALgAECgUJBwAAAA==.',
['Mé']='Méasha:BAAALgAECgkJCgAAAA==.',
['Mï']='Mïlk:BAAALgAECgcJBwAAAQ==.',
Na='Nachtmar:BAAALgAECgQJBAABLgAECggJGQARAEMPAA==.Nadis:BAAALgAECgIJAwAAAA==.Narcessa:BAAALgADCgQJBAAAAA==.Nawk:BAAALgAECgEJAQAAAA==.',
Ne='Nennerb:BAAALgADCgQJBAAAAA==.',
Ni='Nicola:BAAALgAECgUJCQAAAA==.Nightxwish:BAABLgAECn8cAAIbAAYJhhczIACoAQAbAAYJhhczIACoAQAAAA==.Niranye:BAAALgADCgEJAQAAAA==.',
No='Noisemarine:BAACLgAFFH8NAAIUAAQJvxU6EAASAQAUAAQJvxU6EAASAQAuAAQKfxgAAhQACAmeGuUNAPMBABQACAmeGuUNAPMBAAAA.Nokk:BAAALgADCgEJAQAAAA==.Nokkco:BAAALgAECgEJAgAAAA==.Norellia:BAAALgAECgEJAwAAAA==.Northleo:BAAALgADCgcJEQAAAA==.Northspirit:BAABLgAECn8UAAIBAAUJzQWeZwCRAAABAAUJzQWeZwCRAAAAAA==.',
Nu='Nuit:BAAALgADCgUJBQABLgAECgYJCwAJAAAAAA==.',
Ny='Nyarlothep:BAAALgAECgQJBAAAAA==.Nyx:BAAALgADCgUJBQABLgAECggJOAARAEAfAA==.',
Oa='Oakenshièld:BAAALgAECgcJDAAAAA==.',
Od='Odindh:BAAALgAFFAEJAQAAAA==.Odins:BAAALgAECgQJBAABLgAFFAEJAQAJAAAAAA==.',
Oh='Ohwhelp:BAABLgAFFH8IAAIdAAMJ5BlcMADmAAAdAAMJ5BlcMADmAAABLgAFFAcJKgAXAHYkAA==.Ohyikers:BAACLgAFFH8qAAIXAAcJdiQaAgCKAgAXAAcJdiQaAgCKAgAuAAQKfzQAAhcACAnRJtYDABcDABcACAnRJtYDABcDAAAA.',
Ok='Oken:BAAALgADCgUJBQAAAA==.',
Om='Om:BAAALgADCgcJCQAAAA==.',
Op='Open:BAAALgADCgcJBwABLgAECgYJGgAOAJcVAA==.',
Or='Orklock:BAAALgADCgMJAwAAAA==.',
Pa='Pallek:BAAALgAECgcJBwABLgAECggJFgAIAPkOAA==.Palli:BAABLgAECn8dAAIOAAcJ8BX7KwCcAQAOAAcJ8BX7KwCcAQAAAA==.Paogao:BAAALgAECgIJAwAAAA==.Parry:BAAALgADCgQJBAAAAA==.Pasghetti:BAAALgADCgMJAwAAAA==.Pasta:BAABLgAECn8rAAInAAkJSh6uBgCsAgAnAAkJSh6uBgCsAgAAAA==.',
Pe='Pewpewbite:BAAALgAECgcJEAAAAA==.',
Ph='Phantomarrow:BAACLgAFFH8TAAQhAAUJlRJDFAAdAQAhAAQJGAxDFAAdAQAmAAUJHQstGQC5AAAIAAEJ9g5ehgBJAAAuAAQKfxwABAgABgnsIWQ/AM0BAAgABgnsIWQ/AM0BACYABQmzGbBCAE0BACEAAQkAAJtkAAAAAAAA.Phatcow:BAABLgAECn81AAMCAAkJgxt7FwBaAgACAAgJaxp7FwBaAgAZAAkJRhSxCQAGAgAAAA==.Pheral:BAEALgADCgMJAwABLgAFFAMJCwARADwIAA==.Phoseidon:BAAALgADCgcJCQAAAA==.Phude:BAACLgAFFH8MAAIRAAMJ9RSKVADjAAARAAMJ9RSKVADjAAAuAAQKf0gAAhEACQmhH8URAMUCABEACQmhH8URAMUCAAAA.',
Pi='Pinch:BAAALgAECgMJAwAAAA==.',
Po='Pohl:BAAALgAECgYJDQAAAA==.Pokimana:BAAALgADCgEJAQAAAA==.Poohynok:BAACLgAFFH8HAAIEAAQJMxerSQA7AQAEAAQJMxerSQA7AQAuAAQKfzwAAgQACQkXJf0HACoDAAQACQkXJf0HACoDAAAA.',
Pu='Pukefeast:BAABLgAECn8UAAIEAAcJ3RfzawCKAQAEAAcJ3RfzawCKAQAAAA==.',
Py='Pyramys:BAACLgAFFH8TAAInAAUJLB9xFQBFAQAnAAUJLB9xFQBFAQAuAAQKfyoAAicACAkxIwcGALwCACcACAkxIwcGALwCAAAA.',
['Pè']='Pèrce:BAAALgAECgYJDQAAAA==.',
Qu='Quepaoka:BAAALgADCgIJAgAAAA==.',
Ra='Raklem:BAAALgAECgMJAwABLgAECgYJCgAJAAAAAA==.Ramble:BAAALgADCgQJBAABLgAECgQJBgAJAAAAAA==.Ramstein:BAAALgAECgMJAwAAAA==.Raphînîty:BAAALgADCgMJBQAAAA==.Rashari:BAAALgADCgYJCAAAAA==.Rawhawk:BAAALgAECgUJCgABLgAECgcJGQAIAC4SAA==.Razgrizz:BAAALgAECgQJCQAAAA==.',
Re='Retro:BAAALgAECgIJBAAAAA==.Revelatus:BAAALgAECgQJBgAAAA==.Reythanas:BAAALgAECgQJBwAAAA==.Rezzin:BAAALgAECgEJAQAAAA==.',
Ri='Rileyann:BAABLgAECn8fAAMcAAgJOQxSJwB1AQAcAAgJOQxSJwB1AQASAAYJAwNMRADaAAAAAA==.',
Ro='Rolls:BAAALgAECgQJBAAAAA==.Roozer:BAAALgAECgQJCAAAAA==.',
['Rå']='Råphå:BAAALgAECgMJBAAAAA==.',
Sa='Saelyria:BAACLgAFFH8JAAIMAAMJzxbzMgDTAAAMAAMJzxbzMgDTAAAuAAQKfxgAAgwACQkiHNgLAPECAAwACQkiHNgLAPECAAAA.Saga:BAAALgADCgUJBQABLgAECgkJOgAPAOMSAA==.Sagepower:BAAALgAECgQJBAAAAA==.Sagethepally:BAAALgAECgcJBAAAAA==.Saintfail:BAABLgAECn8hAAIOAAYJ7ST+EgBkAgAOAAYJ7ST+EgBkAgABLgAECgcJLgAVAGQhAA==.Sainthymn:BAABLgAECn8XAAIbAAYJnCR6DQB4AgAbAAYJnCR6DQB4AgABLgAECgcJLgAVAGQhAA==.Saintmist:BAABLgAECn8uAAIVAAcJZCHVDACvAgAVAAcJZCHVDACvAgAAAA==.Salero:BAAALgADCgIJAQAAAA==.Sandiera:BAABLgAECn8cAAMEAAgJnApGqgCGAQAEAAgJnApGqgCGAQAlAAMJPAOoFwBcAAAAAA==.Saxtön:BAAALgADCggJEwAAAA==.Sayberix:BAAALgAECgcJBwABLgAFFAQJDgAYALEcAA==.',
Sc='Scarlett:BAAALgAECgEJAQAAAA==.Scoreboard:BAACLgAFFH8lAAIoAAcJ4CUbAAC3AgAoAAcJ4CUbAAC3AgAuAAQKfyEAAygACQkgJg0AAOsDACgACQkgJg0AAOsDACcAAQnwFJhaAE8AAAAA.Scorn:BAAALgAECgYJDgAAAA==.Scottx:BAACLgAFFH8FAAIMAAIJmAh2UABvAAAMAAIJmAh2UABvAAAuAAQKfxQAAgwABwlPFKs4AKEBAAwABwlPFKs4AKEBAAAA.',
Se='Sebas:BAAALgAECgEJAQAAAA==.Sedric:BAAALgAECgYJEwAAAA==.Selkz:BAAALgAECgcJDQAAAA==.Selsonblue:BAAALgAECgQJBAAAAA==.Sesskaa:BAAALgAECgcJEwAAAA==.',
Sh='Shadowcursed:BAAALgADCgcJCgAAAA==.Shadowstorm:BAAALgADCgQJBAAAAA==.Shadøws:BAAALgAECgEJAQAAAA==.Shakenhealz:BAAALgADCgYJBgAAAA==.Shaldria:BAAALgADCgEJAQAAAA==.Sharhox:BAAALgAECgEJAgAAAA==.Shathos:BAAALgADCgEJAQAAAA==.Sheebá:BAAALgADCgYJCwAAAA==.Shishkbob:BAAALgADCgkJCQAAAA==.Shivax:BAAALgAECgYJDgAAAA==.Shünúkh:BAAALgADCgYJBgAAAA==.',
Si='Sigewulf:BAAALgAFFAIJBAABLgAECgcJHgAFANoKAA==.Signal:BAAALgAECgEJAQAAAA==.Singbow:BAAALgADCgYJBgABLgAECggJLAAMAMgOAA==.Sinogad:BAABLgAECn8YAAMXAAgJlBGQJgB/AQAXAAgJlBGQJgB/AQAMAAUJ4xNoUQA2AQAAAA==.Sinol:BAAALgAECgYJDwABLgAECggJGAAXAJQRAA==.Sioux:BAAALgADCgEJAQAAAA==.Sixosix:BAAALgADCgIJAgAAAA==.',
Sk='Skaro:BAABLgAECn8VAAIVAAcJgQ+YRQAhAQAVAAcJgQ+YRQAhAQAAAA==.Skyborn:BAABLgAECn8WAAIEAAcJ0w05jgBAAQAEAAcJ0w05jgBAAQAAAA==.',
Sl='Slamahoochee:BAAALgAECgYJCQAAAA==.Slay:BAACLgAFFH8QAAIXAAQJ5B7TEQBgAQAXAAQJ5B7TEQBgAQAuAAQKfyoABBcACAmPIR0OAGMCABcACAmPIR0OAGMCAA0ABglkG48TAHgBAAwAAQk/A3DlAB0AAAAA.',
Sm='Smokedademon:BAAALgAECgMJCQAAAA==.Smokiebear:BAAALgAECgUJDAAAAA==.Smunkie:BAABLgAECn8fAAIFAAcJyiYnCQCPAgAFAAcJyiYnCQCPAgABLgAECgkJGwAGANYkAA==.',
Sn='Snickeers:BAAALgAECgEJAQAAAA==.',
So='Somapeace:BAAALgAECgYJCwAAAA==.Somogyi:BAAALgADCgIJAgAAAA==.',
Sp='Spopovich:BAAALgADCggJCAABLgAECgMJAwAJAAAAAA==.Sprints:BAAALgAECgQJBAAAAA==.',
St='Stinko:BAAALgADCgEJAgAAAA==.Stitchlock:BAAALgAECgIJAgAAAA==.Stitchofevil:BAABLgAECn8WAAQjAAcJuBoEBgACAgAjAAYJUB8EBgACAgATAAQJpAma6wBvAAAHAAIJtQ8hYQBMAAAAAA==.Stonedshaman:BAAALgADCgYJBgABLgAECgIJAgAJAAAAAA==.Stormhands:BAAALgAECgYJDwAAAA==.Stormhugger:BAAALgAFFAEJAQAAAA==.Stormslight:BAAALgAECgQJBQAAAA==.Stoutnholy:BAABLgAECn8VAAIRAAcJwQkVqQAOAQARAAcJwQkVqQAOAQAAAA==.Stratichnut:BAABLgAECn8sAAIMAAgJyA5zQgB0AQAMAAgJyA5zQgB0AQAAAA==.Stromar:BAAALgAECgQJBAAAAA==.Stwampadin:BAABLgAECn8hAAIOAAkJyyH2AgBmAwAOAAkJyyH2AgBmAwAAAA==.Stwevoker:BAAALgAECgMJAwABLgAECgkJIQAOAMshAA==.Stwonkfu:BAAALgAECggJCwABLgAECgkJIQAOAMshAA==.',
Su='Sumire:BAAALgADCggJDgABLgAECgYJCgAJAAAAAA==.Surloyn:BAAALgAECgcJCwAAAA==.',
Sv='Sveny:BAAALgAECgEJAQAAAA==.',
Sw='Swampert:BAACLgAFFH8SAAIQAAYJXhafCwCGAQAQAAYJXhafCwCGAQAuAAQKfx8AAhAACQnTH+gMAO8CABAACQnTH+gMAO8CAAAA.Swamperting:BAABLgAECn8XAAIQAAcJMhMlNABkAQAQAAcJMhMlNABkAQABLgAFFAYJEgAQAF4WAA==.Swaye:BAACLgAFFH8HAAISAAMJ6QnWIADHAAASAAMJ6QnWIADHAAAuAAQKfysAAhIACQlUFiYVAAYCABIACQlUFiYVAAYCAAAA.Sweetfox:BAAALgAECgYJCgAAAA==.Swimchick:BAAALgAECgUJDAAAAA==.Switched:BAAALgADCgcJBwABLgAECgkJGwAGANYkAA==.Swizzle:BAAALgAECgQJBAAAAA==.',
Sy='Syllvanas:BAABLgAECn8YAAIIAAgJehBETgCeAQAIAAgJehBETgCeAQAAAA==.Syrindra:BAAALgADCgIJAgAAAA==.Sythia:BAACLgAFFH8HAAIcAAQJmAtjFAD8AAAcAAQJmAtjFAD8AAAuAAQKfxgAAhwACAkhI7IEACUDABwACAkhI7IEACUDAAEuAAUUBQkKABMAfhQA.',
Ta='Taltost:BAABLgAECn8ZAAIIAAcJLhJ9XgByAQAIAAcJLhJ9XgByAQAAAA==.Tantrik:BAAALgADCgEJAQAAAA==.Tartin:BAAALgAECgMJAwAAAA==.Tarv:BAAALgAECgEJAQAAAA==.Tashamirage:BAAALgAECgMJBAAAAA==.Tauriel:BAAALgAECgUJBwAAAA==.',
Te='Teex:BAAALgADCgYJBwAAAA==.Teksuo:BAACLgAFFH8MAAIDAAMJAROCHQDQAAADAAMJAROCHQDQAAAuAAQKf0sAAgMACQm9HRwKAI0CAAMACQm9HRwKAI0CAAAA.Telamontay:BAAALgADCgkJFQAAAA==.Telferas:BAABLgAECn8VAAIXAAgJ+RmLIgCbAQAXAAgJ+RmLIgCbAQABLgAFFAYJHAAWAM8cAA==.Tenithon:BAACLgAFFH8KAAIOAAMJxR4gHgAVAQAOAAMJxR4gHgAVAQAuAAQKfzUAAg4ACQnLIvMCAGcDAA4ACQnLIvMCAGcDAAAA.Tenshenzen:BAABLgAECn8eAAIVAAkJ9RWwFABTAgAVAAkJ9RWwFABTAgAAAA==.',
Th='Therandis:BAAALgADCgUJBQAAAA==.Thetombo:BAAALgAECgYJDwAAAA==.Thierry:BAAALgADCgUJBQAAAA==.Thierrye:BAABLgAECn8VAAIaAAYJlhtmTQC/AQAaAAYJlhtmTQC/AQAAAA==.Tholaren:BAABLgAECn8xAAMIAAgJExN5RAC8AQAIAAgJExN5RAC8AQAmAAUJVQdaIQCQAAAAAA==.Threed:BAAALgAECgkJDQAAAA==.Threewar:BAAALgAECgIJAgABLgAECgkJDQAJAAAAAA==.Thrissa:BAABLgAECn8WAAIMAAcJXRE5QAB+AQAMAAcJXRE5QAB+AQAAAA==.Thulgrim:BAAALgADCgYJBgAAAA==.',
To='Torrque:BAAALgADCgkJCQABLgADCgYJCwAJAAAAAA==.Totemlicker:BAAALgAECgEJAQAAAA==.',
Tr='Trandeath:BAAALgAECgQJBAAAAA==.Trangon:BAABLgAECn8nAAIRAAkJlgpEcQBxAQARAAkJlgpEcQBxAQAAAA==.Traveler:BAAALgADCgEJAQAAAA==.Traygon:BAAALgAECgYJCwAAAA==.Trillion:BAAALgADCggJCAAAAA==.',
Tu='Tunzoffun:BAAALgAECgIJBQAAAA==.',
Un='Unanswered:BAAALgAECgEJAQABLgAFFAUJCgAGAAEdAA==.Underbyte:BAAALgADCggJDwAAAA==.Unknownname:BAAALgADCgUJBwAAAA==.',
Ur='Urholiness:BAAALgADCgkJDwAAAA==.',
Va='Vaeleia:BAAALgAECgQJBgAAAA==.Vahnkar:BAAALgADCgYJCQAAAA==.Valentinu:BAAALgADCgcJDwAAAA==.Valkyrie:BAAALgAECgEJAgAAAA==.Vaneshk:BAAALgADCgEJAQAAAA==.Varchemical:BAAALgAECgcJBwAAAA==.Varithal:BAACLgAFFH8MAAIeAAMJMhmRGQDlAAAeAAMJMhmRGQDlAAAuAAQKf0AAAh4ACQk8H/EDAOgCAB4ACQk8H/EDAOgCAAEuAAQKAQkBAAkAAAAA.Varri:BAAALgAECgMJBQAAAA==.Vastectomy:BAAALgAECggJCwAAAA==.',
Ve='Vegasana:BAAALgAFFAEJAgAAAA==.Velwing:BAAALgAECgUJBwAAAA==.Venawyn:BAABLgAECn8nAAIIAAcJcQ2/bABQAQAIAAcJcQ2/bABQAQAAAA==.Verakhaa:BAAALgAECgQJBAAAAA==.',
Vi='Vibepriest:BAAALgADCgEJAQAAAA==.Vindfaramaðr:BAABLgAECn8eAAIFAAcJ2goXPAD6AAAFAAcJ2goXPAD6AAAAAA==.Vixin:BAAALgAECgYJEwAAAA==.',
Vo='Voidsaack:BAAALgAECgcJCgAAAA==.Voidz:BAAALgAECgEJAQAAAA==.Volfguar:BAAALgAECgQJAQAAAA==.Vortan:BAABLgAECn8iAAIhAAgJVhzGDgAxAgAhAAgJVhzGDgAxAgAAAA==.',
Vr='Vreya:BAAALgADCgkJFQABLgAECgQJCQAJAAAAAA==.',
Vy='Vynthus:BAAALgAECgcJEQAAAA==.',
['Vä']='Värys:BAAALgAECgEJAQAAAA==.',
Wa='Wan:BAAALgADCgEJAQAAAA==.Warhundin:BAEALgAECgYJDgABLgAFFAMJCwARADwIAA==.Warwan:BAAALgADCgIJAgAAAA==.Wazzbozz:BAAALgAECgQJAwAAAA==.Wazzdh:BAAALgAECgQJBAAAAA==.Wazzdot:BAAALgAECgUJCwAAAA==.Wazzhunnah:BAABLgAECn8nAAMhAAkJ0hS+EQAQAgAhAAkJ0hS+EQAQAgAmAAQJZAlhZQCqAAAAAA==.Wazzmage:BAAALgAECgMJAwAAAA==.',
We='Werg:BAAALgAECggJCgABLgAFFAUJCQAiAKUJAA==.',
Wh='Whatmyname:BAABLgAECn85AAIiAAgJ2wo5KQDoAAAiAAgJ2wo5KQDoAAAAAA==.Whispp:BAAALgAECgYJCAAAAA==.',
Wi='Wildmandave:BAAALgADCgUJBQAAAA==.Willough:BAAALgAECgEJAQAAAA==.',
Wo='Wonsok:BAAALgAECgcJEAAAAA==.',
Wy='Wyvoker:BAABLgAECn8mAAIeAAkJPhugBADJAgAeAAkJPhugBADJAgAAAA==.',
['Wì']='Wìllow:BAAALgADCgIJAgAAAA==.',
['Wÿ']='Wÿm:BAABLgAECn8UAAIKAAgJwRxXIwBkAgAKAAgJwRxXIwBkAgABLgAECgkJJgAeAD4bAA==.',
Xa='Xaoleth:BAAALgADCgEJAQAAAA==.',
Xe='Xenorion:BAAALgAECgMJAwAAAA==.Xephora:BAAALgAECgEJBgAAAA==.',
Xi='Xiq:BAAALgADCgUJBQAAAA==.',
Xr='Xrinch:BAAALgADCgYJBgAAAA==.',
Xu='Xunadin:BAAALgADCgkJIgAAAA==.Xuny:BAAALgAECgUJEAAAAA==.',
Yo='Yordi:BAAALgAECgUJEwAAAA==.',
Yu='Yuzuriha:BAACLgAFFH8MAAIIAAMJPyCsOwAaAQAIAAMJPyCsOwAaAQAuAAQKf0AAAggACQmQJM0DAEYDAAgACQmQJM0DAEYDAAAA.',
Za='Zaelia:BAAALgADCgYJBgABLgAECggJOAARAEAfAA==.Zaletren:BAAALgAECgkJBAAAAA==.Zamaze:BAABLgAECn8nAAMUAAkJkCAhBgCZAgAUAAkJkCAhBgCZAgAYAAEJLwnXcQAoAAAAAA==.Zannah:BAAALgAECgMJAwAAAA==.Zant:BAAALgAECgIJAQAAAA==.',
Ze='Zeekielle:BAEBLgAECn86AAIfAAkJ4BRaEAACAgAfAAkJ4BRaEAACAgABLgAFFAMJCwARADwIAA==.Zenius:BAAALgAECgcJEgAAAA==.Zerithrielle:BAABLgAECn8sAAIfAAgJMxceFQDDAQAfAAgJMxceFQDDAQAAAA==.',
Zi='Zippii:BAAALgAECgYJBwAAAA==.Zipy:BAABLgAECn8xAAIcAAgJXB7eCQC1AgAcAAgJXB7eCQC1AgAAAA==.',
Zo='Zof:BAAALgAECgYJDgAAAA==.Zorathar:BAAALgADCgYJBgAAAA==.',
Zu='Zugtag:BAABLgAECn83AAIKAAkJhyHPCQARAwAKAAkJhyHPCQARAwAAAA==.',
Zy='Zyllo:BAAALgAECgQJBQAAAA==.',
['Zá']='Závier:BAABLgAECn8UAAIEAAYJ/QKj8gCcAAAEAAYJ/QKj8gCcAAAAAA==.',
['Zõ']='Zõf:BAAALgAECgIJAwABLgAECgYJDgAJAAAAAA==.',
['Äe']='Äemond:BAAALgADCgMJAwAAAA==.',
['Ål']='Ålïce:BAACLgAFFH8GAAIRAAMJjQhfYgDJAAARAAMJjQhfYgDJAAAuAAQKf0sAAhEACQmHHZMVAKwCABEACQmHHZMVAKwCAAAA.',
['Ëd']='Ëdward:BAAALgADCgcJCgABLgAECgUJDwAJAAAAAA==.',
['Ôh']='Ôhmyn:BAAALgADCgMJAwABLgAECgcJGAARAEMMAA==.',
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
