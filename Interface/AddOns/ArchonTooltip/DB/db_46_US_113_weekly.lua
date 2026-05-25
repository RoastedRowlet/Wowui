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

local lookup = {'Shaman-Elemental','Shaman-Restoration','Monk-Windwalker','Mage-Frost','Monk-Brewmaster','Warlock-Destruction','Hunter-BeastMastery','Unknown-Unknown','DeathKnight-Unholy','DeathKnight-Frost','Druid-Restoration','Druid-Feral','Paladin-Holy','Paladin-Protection','Warrior-Fury','Paladin-Retribution','Priest-Shadow','Warlock-Demonology','Warrior-Protection','Monk-Mistweaver','Evoker-Devastation','DeathKnight-Blood','Druid-Balance','Warrior-Arms','Shaman-Enhancement','DemonHunter-Devourer','Priest-Discipline','Priest-Holy','Evoker-Augmentation','Evoker-Preservation','DemonHunter-Havoc','DemonHunter-Vengeance','Hunter-Survival','Druid-Guardian','Warlock-Affliction','Mage-Fire','Mage-Arcane','Hunter-Marksmanship','Rogue-Subtlety','Rogue-Outlaw',}
local provider = {region='US',realm='GrizzlyHills',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Abramz:BAAALgADCgMJAwAAAA==.',
Ad='Adely:BAAALgAECgEJAQAAAA==.Adelymon:BAABLgAECn8XAAMBAAkJZxZREwAmAgABAAkJZxZREwAmAgACAAUJARCLbwDTAAAAAA==.Adelymonk:BAAALgAECgYJDAAAAA==.Adonysroth:BAAALgAECgIJAgAAAA==.Adrahil:BAAALgADCgIJAgAAAA==.',
Ae='Aeonra:BAAALgADCgIJAgAAAA==.',
Ag='Agronak:BAAALgAECgQJBgAAAA==.',
Al='Aldan:BAAALgADCgMJAwAAAA==.Aldazen:BAACLgAFFH8KAAIDAAMJuh14EQAPAQADAAMJuh14EQAPAQAuAAQKfzgAAgMACQnMI3sCADEDAAMACQnMI3sCADEDAAAA.Alenara:BAAALgAECgYJDwABLgAECggJHAAEAJwKAA==.Aletheìa:BAAALgAECgEJAQAAAA==.Alovan:BAAALgADCgEJAQABLgAECgcJHAAFACQGAA==.Alyssandra:BAABLgAECn8jAAIGAAgJhRVXBgDLAQAGAAgJhRVXBgDLAQAAAA==.',
Am='Amarella:BAABLgAECn8UAAIHAAcJqiCkKQAQAgAHAAcJqiCkKQAQAgAAAA==.Amarrite:BAAALgAECgEJAgABLgAECgIJAgAIAAAAAA==.Ammalane:BAAALgAECgIJAgAAAA==.Amunzo:BAAALgAECgEJAQABLgAECggJDAAIAAAAAA==.',
An='Angler:BAAALgAECgMJAwAAAA==.Angyrolaj:BAABLgAECn8XAAMJAAcJ0xcNVQChAQAJAAcJgBcNVQChAQAKAAIJdBUXEQCFAAAAAA==.',
Aq='Aquadora:BAAALgADCgMJAwAAAA==.',
Ar='Arangarr:BAABLgAECn8xAAMLAAkJpx0iCwDtAgALAAkJpx0iCwDtAgAMAAEJ1BEUOgA8AAAAAA==.Arcin:BAAALgADCgEJAQAAAA==.Areyana:BAABLgAECn8WAAIHAAcJvBHYYABXAQAHAAcJvBHYYABXAQAAAA==.Areyoudead:BAAALgAECgQJBAABLgADCgYJCwAIAAAAAA==.Aristoi:BAAALgAECgEJAQAAAA==.Arkand:BAAALgADCgUJBAAAAA==.Arkandra:BAAALgAECgUJEAAAAA==.Arkara:BAAALgADCgEJAQAAAA==.Arrietty:BAABLgAECn8XAAINAAYJlxViOQA8AQANAAYJlxViOQA8AQAAAA==.Arthues:BAAALgAECgcJDgAAAA==.Arthâs:BAAALgAECgYJBQAAAA==.Arumathe:BAABLgAECn8XAAIOAAkJxxI9DgCxAQAOAAkJxxI9DgCxAQAAAA==.',
As='Asura:BAACLgAFFH8PAAIPAAQJ8iAxCQCGAQAPAAQJ8iAxCQCGAQAuAAQKfyAAAg8ACQnLItkIAB4DAA8ACQnLItkIAB4DAAAA.',
Au='Aurelian:BAAALgAECgEJAgAAAA==.',
Az='Az:BAABLgAECn8aAAIPAAYJOCa4FgAUAgAPAAYJOCa4FgAUAgAAAA==.Azeriall:BAACLgAFFH8JAAIBAAMJWAgSKgC7AAABAAMJWAgSKgC7AAAuAAQKfz8AAwEACAkhGIgYAPIBAAEACAkhGIgYAPIBAAIABAlKAVuGAHsAAAAA.Azerowolf:BAAALgADCggJCAAAAA==.Azráèl:BAAALgADCgMJAwAAAA==.',
Ba='Babyboom:BAAALgAECgEJAQAAAA==.Baconhammr:BAABLgAECn8YAAMQAAcJQwyvjgAzAQAQAAcJQwyvjgAzAQANAAUJEgd2eACXAAAAAA==.Badazmf:BAAALgADCgcJDAABLgAECgkJLQARAM0ZAA==.Badcompany:BAAALgADCgUJBQABLgAECggJJQALAMgOAA==.Baddream:BAAALgAECgYJDgAAAA==.Baelmyre:BAAALgADCgUJBQAAAA==.Balenciagosa:BAAALgADCgUJBQABLgAECggJHAAEAJwKAA==.Banshiï:BAABLgAECn8oAAIGAAgJ6hELCgB2AQAGAAgJ6hELCgB2AQAAAA==.Baratheøn:BAABLgAECn8jAAILAAgJ0RYGKwDdAQALAAgJ0RYGKwDdAQAAAA==.Bax:BAAALgADCgIJAgAAAA==.Baxar:BAAALgAECgIJAgAAAA==.',
Bb='Bbd:BAAALgAECggJCQABLgAECgYJDgAIAAAAAA==.',
Be='Beeftard:BAABLgAECn8XAAINAAgJzRhiKgDfAQANAAgJzRhiKgDfAQAAAA==.Bellavix:BAAALgADCgMJBAAAAA==.Benafflic:BAAALgAECgEJAQABLgAECgMJAwAIAAAAAA==.Berserrk:BAAALgADCgYJBgAAAA==.Bershale:BAAALgAECgEJAQABLgAECgYJBwAIAAAAAA==.',
Bi='Bifficus:BAAALgAECgYJDgAAAA==.Big:BAAALgADCgMJBAAAAA==.Biggiecheese:BAAALgAECgIJAgAAAA==.',
Bl='Blackscorn:BAAALgADCgEJAQAAAA==.Blackthôrne:BAAALgADCgUJCQAAAA==.Blucki:BAABLgAECn8fAAISAAgJ7QnZdAA6AQASAAgJ7QnZdAA6AQAAAA==.',
Bo='Bobfu:BAAALgADCgYJCAAAAA==.',
Br='Brieze:BAAALgADCgIJAgAAAA==.Brige:BAAALgAECggJBgAAAA==.Brightstar:BAAALgADCgEJAQAAAA==.Brimaz:BAAALgADCgEJAQAAAA==.',
Bu='Buhhead:BAAALgADCgUJBgAAAA==.Bunana:BAAALgADCgEJAQAAAA==.Bunbear:BAAALgAECgIJAgAAAA==.Bunette:BAAALgADCgEJAQAAAA==.',
Bw='Bwamsamdi:BAAALgADCgYJBgAAAA==.',
By='Byzantium:BAABLgAECn8gAAITAAcJLgZ5JgDVAAATAAcJLgZ5JgDVAAAAAA==.',
['Bô']='Bônebeard:BAAALgAECgEJAQAAAA==.',
Ca='Cabledryer:BAAALgAECgQJEAAAAA==.Caelidpackx:BAAALgADCgYJBwAAAA==.Callmedatty:BAAALgADCgEJAQAAAA==.Caluu:BAAALgADCgEJAQAAAA==.Carnry:BAAALgADCgQJBAAAAA==.Catboy:BAABLgAECn8cAAIEAAkJMhUXbQCEAQAEAAkJMhUXbQCEAQAAAA==.Catnips:BAABLgAECn8cAAIQAAgJURjAVACtAQAQAAgJURjAVACtAQAAAA==.Catpow:BAAALgAECgkJAgAAAA==.',
Ch='Chanaranach:BAAALgAECgYJCgAAAA==.Charitey:BAAALgAECgIJAwAAAA==.Cheelo:BAAALgAECggJDwAAAA==.Chknnugget:BAAALgAECgMJBQAAAA==.Chromatic:BAABLgAECn8iAAMCAAgJARQCKwDfAQACAAgJARQCKwDfAQABAAQJYg4DWACsAAAAAA==.',
Ci='Cindrethresh:BAAALgAECgQJCQAAAA==.',
Co='Coffeeblak:BAABLgAECn8ZAAMDAAgJBRNLJgCmAQADAAcJlxNLJgCmAQAUAAUJFQ65PwDkAAAAAA==.Coldstorm:BAAALgAECgcJCwAAAA==.Collision:BAAALgAECgcJCAAAAA==.Compensating:BAAALgADCgYJBgAAAA==.Connor:BAAALgADCgcJBwAAAA==.Connsumption:BAAALgAECgYJCgAAAA==.Corrine:BAAALgAECgYJBgAAAA==.',
Cr='Crazybatt:BAAALgAECgYJDQAAAA==.Crypt:BAAALgAECgYJCgAAAA==.',
Cu='Cuckchairpov:BAACLgAFFH8OAAMFAAQJJRQTGgApAQAFAAQJpBMTGgApAQADAAIJQg15DACgAAAuAAQKfywAAwMACQkqH2gKANICAAMACAl4HWgKANICAAUACQndFG0RAA0CAAAA.',
Cy='Cynderleena:BAAALgAECgYJBwAAAA==.Cynyia:BAABLgAECn8vAAIHAAkJxRPONADfAQAHAAkJxRPONADfAQAAAA==.',
Cz='Czk:BAAALgADCgYJBgABLgAECggJGQADAAUTAA==.',
['Có']='Cóldblóód:BAAALgAECgIJAgAAAA==.',
Da='Daddyelessar:BAAALgAECgYJDQAAAA==.Dafattyup:BAABLgAECn8aAAISAAYJlRxUYwCgAQASAAYJlRxUYwCgAQAAAA==.Daghmar:BAAALgADCgUJBQAAAA==.Dagon:BAAALgAECgMJAwAAAA==.Dakotarain:BAAALgADCgIJAgAAAA==.Dalerontwo:BAAALgADCgEJAQAAAA==.Darruin:BAACLgAFFH8FAAIJAAIJXxvyiwC2AAAJAAIJXxvyiwC2AAAuAAQKfxUAAgkACAlKIVoZAI0CAAkACAlKIVoZAI0CAAEuAAUUBgkcABUAzxwA.Dayrun:BAAALgAECgUJDQAAAA==.',
De='Deadicee:BAAALgAECgIJAgABLgAECgYJEwAIAAAAAA==.Deathturtle:BAABLgAECn8eAAIJAAgJLxDGegBIAQAJAAgJLxDGegBIAQAAAA==.Deavaos:BAAALgAECgQJBwAAAA==.Dedmartigan:BAAALgADCgUJBQAAAA==.Deeanndra:BAABLgAECn8dAAMJAAcJmQ7GfgBAAQAJAAcJmQ7GfgBAAQAKAAEJDAlBLgAoAAAAAA==.Deevz:BAAALgAECgIJAgAAAA==.Demandred:BAAALgAECgYJCQAAAA==.Demiz:BAABLgAECn84AAMCAAkJ5RrMEQCUAgACAAkJ5RrMEQCUAgABAAcJug4cOwAZAQAAAA==.Deredris:BAAALgAECgQJBAABLgAECgYJCgAIAAAAAA==.Dertka:BAAALgAECgYJDAAAAA==.',
Di='Discodruid:BAABLgAECn8UAAILAAYJKRMgSwA/AQALAAYJKRMgSwA/AQAAAA==.Dishsoap:BAAALgAECgMJAwABLgAFFAUJEAAPAPQUAA==.Dixie:BAAALgAECgEJAQAAAA==.',
Dj='Djall:BAAALgAECgUJBQAAAA==.',
Do='Dommy:BAAALgAECgkJEwAAAA==.Domw:BAAALgAECgYJCgABLgAECgkJEwAIAAAAAA==.Donham:BAACLgAFFH8XAAMJAAYJ9xuiHACeAQAJAAUJ9xuiHACeAQAWAAEJAABBEwBZAAAuAAQKfx8AAgkACAnLHzweAMsCAAkACAnLHzweAMsCAAAA.Dorkimedes:BAAALgAECgQJCwAAAA==.Dottie:BAABLgAECn8oAAMGAAgJNhM2FwCQAQASAAgJ7xFCTwCWAQAGAAcJJQ82FwCQAQAAAA==.Dotvinci:BAAALgAECgYJBgAAAA==.',
Dr='Draelesh:BAABLgAECn8sAAIXAAgJ9RM7HgCoAQAXAAgJ9RM7HgCoAQAAAA==.Draenk:BAAALgADCgUJBQAAAA==.Dragún:BAAALgAECgYJCwAAAA==.Drakari:BAAALgADCgYJBgAAAA==.Dramborleg:BAAALgAECgEJAQAAAA==.Drazon:BAAALgADCgIJAgAAAA==.Drewit:BAABLgAECn8VAAIMAAYJPxA1FQBiAQAMAAYJPxA1FQBiAQAAAA==.',
Du='Ducan:BAAALgADCgYJCQAAAA==.Duskmane:BAAALgAECgMJBwAAAA==.',
Dw='Dwadler:BAABLgAECn8kAAMTAAgJHxzYCwAJAgATAAgJmhrYCwAJAgAYAAEJzhrVUgBPAAAAAA==.',
Dy='Dyrkonian:BAAALgAECgcJDgAAAA==.',
Ei='Eireann:BAAALgADCgcJCQAAAA==.',
El='Elerrak:BAAALgAECgEJAQABLgAFFAcJHAAZALwcAA==.Elindalia:BAAALgAECgMJAwAAAA==.',
Em='Emberash:BAAALgAECgEJAQAAAA==.Embre:BAABLgAFFH8KAAIVAAQJsA7OAwAoAQAVAAQJsA7OAwAoAQAAAA==.Emorri:BAAALgAECgYJBgAAAA==.Empyrea:BAAALgAECgQJBQAAAA==.',
Er='Eraina:BAAALgADCgIJAgAAAA==.Ericles:BAABLgAECn8ZAAMYAAcJ8R1VDADbAQAYAAcJ8R1VDADbAQAPAAIJlAVwlwBkAAAAAA==.Erys:BAAALgAECgcJEAAAAA==.Erébus:BAABLgAECn8iAAIaAAkJ7xgpIQAwAgAaAAkJ7xgpIQAwAgAAAA==.',
Ev='Ev:BAAALgAECgQJBAAAAA==.Evergreene:BAAALgADCggJCAABLgAECgIJAgAIAAAAAA==.Evlpotato:BAABLgAECn8tAAQRAAkJzRnOEQAiAgARAAkJzRnOEQAiAgAbAAcJNBouGgDSAQAcAAEJlAdTfwAzAAAAAA==.Evojak:BAAALgAECgYJEwAAAA==.',
Fa='Fabiyo:BAAALgADCgMJAwAAAA==.Faevelia:BAAALgAECgQJBQAAAA==.Fairaday:BAABLgAECn83AAIHAAkJXwvuQwCqAQAHAAkJXwvuQwCqAQAAAA==.Falloon:BAAALgADCgYJBgAAAA==.Fanshen:BAAALgAECgMJBQAAAA==.Farmerdave:BAAALgAECgEJAQAAAA==.Fauchi:BAAALgADCgEJAQAAAA==.Faxqueenmage:BAABLgAECn8aAAIEAAYJlQK75gCrAAAEAAYJlQK75gCrAAAAAA==.',
Fe='Felador:BAAALgAECgcJDAAAAA==.Feldo:BAAALgAECgYJDwAAAA==.Felmès:BAAALgADCgYJBgABLgAECggJHAAEAJwKAA==.Fennec:BAAALgAECgUJDAAAAA==.Feralarak:BAAALgAECgcJEwABLgAFFAcJHAAZALwcAA==.',
Fi='Firebrandd:BAACLgAFFH8cAAMVAAYJzxxiAQB6AQAVAAUJnyBiAQB6AQAdAAUJZhFWFABoAQAuAAQKfzsAAxUACQl8I2ACAA8DABUACAksImACAA8DAB0ACQlEIkUHAM4CAAAA.Fizehbubbleh:BAEALgAECgMJAwABLgAECggJIAABAOgaAA==.Fizehtotems:BAEBLgAECn8gAAMBAAgJ6BrSJACUAQABAAgJ6BrSJACUAQACAAUJixbMTgBBAQAAAA==.',
Fl='Fleshoracle:BAAALgAECgQJBAABLgAFFAUJBQAWANEbAA==.Fluctuates:BAAALgAECgQJCAAAAA==.',
Fo='Foragarn:BAAALgAECgYJCQAAAA==.Foron:BAAALgAECgIJAgAAAA==.',
Fr='Frankkastle:BAAALgAECgYJDwAAAA==.Frazelia:BAAALgADCgkJDgABLgAECgYJFQAMAD8QAA==.Fribble:BAABLgAECn8ZAAMCAAkJmw5GMADEAQACAAkJmw5GMADEAQAZAAEJAAATNgAAAAAAAA==.Froggierlynx:BAAALgAFFAQJBAAAAA==.Froznfate:BAABLgAECn8oAAIOAAgJ2CVZAgDnAgAOAAgJ2CVZAgDnAgAAAA==.Fryes:BAAALgAECgkJDAAAAA==.',
Fu='Fuzziebutt:BAAALgADCgMJBAAAAA==.',
Fw='Fwibble:BAAALgAECggJEgABLgAECgkJGQACAJsOAA==.',
Fy='Fyrelady:BAAALgADCggJDgABLgAECgMJBQAIAAAAAA==.Fyrestone:BAAALgAECgMJBQAAAA==.',
['Fæ']='Fæder:BAAALgADCgYJBgAAAA==.',
Ga='Gabarnak:BAAALgADCgIJAgAAAA==.Galencharred:BAABLgAECn8eAAIQAAcJeQivowAQAQAQAAcJeQivowAQAQAAAA==.Garagon:BAABLgAECn8sAAIeAAgJxhY1CwACAgAeAAgJxhY1CwACAgAAAA==.Gauss:BAABLgAECn8dAAIOAAgJoAYPIADjAAAOAAgJoAYPIADjAAABLgAECgkJGQACAJsOAA==.Gaîîa:BAABLgAECn8cAAIHAAgJCRq2MADtAQAHAAgJCRq2MADtAQAAAA==.',
Ge='Gerva:BAABLgAECn8pAAIJAAgJXQ+RXwCGAQAJAAgJXQ+RXwCGAQAAAA==.',
Gh='Ghlain:BAAALgAECgQJBwAAAA==.Ghorfindor:BAABLgAECn8dAAIfAAcJ4AOkMwC4AAAfAAcJ4AOkMwC4AAAAAA==.Ghostlybrew:BAACLgAFFH8VAAIFAAcJ9xtjBQDlAQAFAAcJ9xtjBQDlAQAuAAQKfxYAAgUACAmpH94TAHECAAUACAmpH94TAHECAAAA.',
Gi='Gigastorm:BAAALgADCgIJAQAAAA==.Gilas:BAABLgAECn8fAAQWAAcJwA7bKQDZAAAWAAYJcBDbKQDZAAAJAAUJlgQl4AChAAAKAAUJXgXiHQCOAAAAAA==.',
Gl='Glaivemstake:BAAALgADCgcJBwAAAA==.',
Gn='Gnik:BAAALgAECggJDwAAAA==.',
Go='Goswin:BAAALgAECgEJAQAAAA==.',
Gr='Graahak:BAAALgADCgMJAwAAAA==.Graveborn:BAABLgAFFH8FAAIWAAUJ0RuIDgBAAQAWAAUJ0RuIDgBAAQAAAA==.Graydenton:BAAALgAECgkJCQABLgAECggJBgAIAAAAAA==.Greenfelpowa:BAABLgAECn8ZAAISAAkJpQ86PADRAQASAAkJpQ86PADRAQAAAA==.Gruuven:BAAALgADCgUJBwAAAA==.',
Gu='Gutmtmon:BAABLgAECn8VAAIDAAYJCAhSQwDGAAADAAYJCAhSQwDGAAAAAA==.',
Gw='Gwenivive:BAABLgAECn8hAAIHAAkJjBfdHwA+AgAHAAkJjBfdHwA+AgAAAA==.',
['Gí']='Gízmo:BAAALgADCgUJBQAAAA==.',
Ha='Haenus:BAABLgAECn8dAAIaAAgJ8hN+YAB/AQAaAAgJ8hN+YAB/AQAAAA==.Hamor:BAAALgAECgkJCgAAAA==.Harrynear:BAAALgADCgMJAwABLgAECgcJFwAJANMXAA==.Hat:BAABLgAECn8ZAAMaAAkJfCL+BAAlAwAaAAkJfCL+BAAlAwAgAAIJkQouJQBNAAAAAA==.Haunt:BAAALgAECgUJBgAAAA==.Havark:BAAALgAECgMJAwAAAA==.',
He='Healbilly:BAAALgADCgEJAQAAAA==.Healingdeath:BAAALgADCgMJBAAAAA==.Hecatombe:BAAALgADCgUJBQAAAA==.Hellda:BAEALgAECgkJBgABLgAFFAMJCQAQADwIAA==.Hellzdruid:BAAALgADCgQJBAAAAA==.Hellzknîght:BAABLgAECn8gAAIJAAYJcRT0hQAyAQAJAAYJcRT0hQAyAQAAAA==.',
Ho='Holek:BAABLgAECn8UAAMHAAYJQRFfcwArAQAHAAYJ8BBfcwArAQAhAAMJcARIQgCIAAAAAA==.Holgo:BAACLgAFFH8HAAITAAQJcx+YCABoAQATAAQJcx+YCABoAQAuAAQKfyEAAhMACQluJf8AAFADABMACQluJf8AAFADAAAA.Holgy:BAACLgAFFH8aAAIiAAYJtCJIAQARAgAiAAYJtCJIAQARAgAuAAQKfyYAAiIACQlWI0wBAEkDACIACQlWI0wBAEkDAAAA.Holybeard:BAACLgAFFH8FAAIQAAIJThlpYQCoAAAQAAIJThlpYQCoAAAuAAQKfzQAAhAACAmAH00cAH0CABAACAmAH00cAH0CAAAA.Hooks:BAAALgADCggJGgAAAA==.',
Hu='Hugecowballs:BAAALgAECggJCAAAAA==.Hunterturtle:BAAALgADCgUJBQAAAA==.',
Ic='Icia:BAAALgAECgEJAQAAAA==.',
Id='Idontmiss:BAAALgAECgIJCAAAAA==.',
Il='Ilickboody:BAAALgADCgQJBAAAAA==.Illustra:BAABLgAECn8ZAAMcAAgJnAaHMQAgAQAcAAgJnAaHMQAgAQARAAcJ3gKlSgC1AAABLgAECggJHAAEAJwKAA==.',
Im='Imcaldo:BAAALgADCgYJBgAAAA==.Imcaldoo:BAAALgADCgUJCgAAAA==.',
In='Interrupt:BAAALgAECgUJDQAAAA==.',
Ir='Irox:BAAALgADCgMJAwAAAA==.',
Is='Isaic:BAAALgADCgIJAgAAAA==.Iseila:BAABLgAECn8YAAIEAAkJ+A27WQCzAQAEAAkJ+A27WQCzAQAAAA==.Isevio:BAAALgAECgMJBwAAAA==.',
It='Ithorus:BAAALgAECgYJEgAAAA==.',
Ja='Jaadb:BAAALgAECgMJAwAAAA==.Jaadd:BAAALgAECgIJAgAAAA==.Jaadi:BAAALgAECgIJAwAAAA==.Jaata:BAAALgADCgcJEAAAAA==.Jamien:BAABLgAECn8xAAMQAAgJLx/7IwBVAgAQAAgJLx/7IwBVAgANAAUJHQEsdwCdAAAAAA==.Janal:BAAALgADCgEJAQAAAA==.Jasnah:BAAALgAECgYJCwAAAA==.Jasnos:BAAALgAECgUJDAAAAA==.',
Jd='Jdk:BAAALgAECgUJBwAAAA==.',
Je='Jelf:BAAALgAECgQJBAAAAA==.Jenzing:BAABLgAECn8VAAMSAAgJqh0QKwBjAgASAAcJqh0QKwBjAgAjAAEJAACuIwBjAAAAAA==.Jessemyn:BAAALgAECgYJDAAAAA==.',
Jh='Jholy:BAAALgADCggJCAAAAA==.',
Jo='Jobokenhones:BAABLgAECn8xAAIaAAkJIBqXHABMAgAaAAkJIBqXHABMAgAAAA==.Johadgan:BAAALgADCgEJAQAAAA==.',
Jp='Jproudmore:BAAALgADCgUJBQABLgADCgYJCwAIAAAAAA==.',
Js='Jsberg:BAABLgAECn8eAAIPAAgJwRWOJgCgAQAPAAgJwRWOJgCgAQAAAA==.',
Ka='Kaathe:BAABLgAECn8lAAMEAAYJGx7ihADHAQAEAAYJGx7ihADHAQAkAAEJjhqXDwA4AAAAAA==.Kaboomalis:BAAALgADCgUJBQAAAA==.Kadance:BAABLgAECn8WAAIBAAcJmRaoKgBwAQABAAcJmRaoKgBwAQAAAA==.Kaidiis:BAABLgAECn8pAAIQAAgJ6A6IaQB8AQAQAAgJ6A6IaQB8AQAAAA==.Kaido:BAAALgAECgEJAQAAAA==.Kalder:BAAALgADCgcJBwAAAA==.Karbonn:BAABLgAECn8WAAIVAAcJuBVmCACJAQAVAAcJuBVmCACJAQAAAA==.Kay:BAAALgAECgcJBwAAAA==.Kazeraz:BAAALgADCgEJAQAAAA==.',
Ke='Kegbreaker:BAABLgAECn83AAIcAAkJUApAJAB+AQAcAAkJUApAJAB+AQAAAA==.',
Kh='Khanas:BAABLgAECn8WAAINAAcJiBecJgCuAQANAAcJiBecJgCuAQAAAA==.Kheru:BAAALgADCgkJFAAAAA==.Khoan:BAAALgAECgYJCgAAAA==.',
Ki='Kimbustible:BAABLgAECn85AAIEAAkJOCThCQAWAwAEAAkJOCThCQAWAwAAAA==.Kimchi:BAABLgAECn8WAAIFAAgJlhBeIgB4AQAFAAgJlhBeIgB4AQABLgAECgkJOQAEADgkAA==.',
Kn='Knockknocko:BAAALgAECgcJDQAAAA==.',
Ko='Kobir:BAAALgADCgEJAQAAAA==.Komodostyle:BAABLgAECn8sAAQeAAgJfQvUFwAvAQAeAAcJPQvUFwAvAQAVAAIJWw64NQBoAAAdAAEJaRAiegA4AAAAAA==.Koobideh:BAAALgADCgEJAQAAAA==.',
Kr='Krayose:BAAALgAECgEJAQAAAA==.Kriddler:BAAALgADCgQJBAAAAA==.Krisarugala:BAABLgAECn8VAAIXAAcJgA2rNwAEAQAXAAcJgA2rNwAEAQAAAA==.',
Ku='Kujoluvsmilf:BAAALgAECggJCwAAAA==.Kunuku:BAAALgADCgUJBQAAAA==.Kurash:BAAALgADCgcJBwAAAA==.Kurion:BAAALgAECgkJBAAAAA==.Kurogami:BAAALgADCggJDQAAAA==.',
Ky='Kylesxmom:BAACLgAFFH8NAAMJAAUJtQ/hVgAhAQAJAAQJtQ/hVgAhAQAWAAIJuA2uLgA1AAAuAAQKf1gAAwkACQn3I2oGACwDAAkACQnKI2oGACwDABYACAn/HagNAP8BAAAA.Kymal:BAABLgAECn86AAIaAAkJzRUwLQDzAQAaAAkJzRUwLQDzAQAAAA==.Kymbria:BAAALgADCgUJCAAAAA==.Kymora:BAAALgADCgcJBwAAAA==.Kyndrissa:BAAALgADCgUJBQAAAA==.',
['Kë']='Këy:BAACLgAFFH8KAAIJAAMJ0xJJdADlAAAJAAMJ0xJJdADlAAAuAAQKfykAAgkACAnUHYwsAIYCAAkACAnUHYwsAIYCAAAA.',
La='Latrice:BAACLgAFFH8dAAIEAAcJIR45DAAnAgAEAAcJIR45DAAnAgAuAAQKfygABAQACQk5I9wJAHYDAAQACQk5I9wJAHYDACQAAwm4GbsHAOAAACUAAQltGN0YAFEAAAAA.Lavynder:BAABLgAECn8XAAIaAAgJ5hUVWgCTAQAaAAgJ5hUVWgCTAQAAAA==.Lazerturkey:BAAALgAECgkJCQAAAA==.Laërtes:BAAALgAECgUJDAAAAA==.',
Le='Leiamirage:BAAALgAECgUJDQAAAA==.Leviscus:BAAALgAECgMJBQAAAA==.',
Li='Lifetap:BAAALgADCgMJAwAAAA==.Lightbill:BAAALgAECggJCAABLgAECgkJLwALAM4dAA==.Lightbàne:BAABLgAECn8hAAIMAAgJ+R+sBACKAgAMAAgJ+R+sBACKAgAAAA==.Lightningrod:BAAALgAECgYJBwAAAA==.Lightshaolin:BAAALgAECgQJBAAAAA==.Lildruidz:BAABLgAECn8dAAMLAAcJbhPtOACQAQALAAcJbhPtOACQAQAXAAEJLQItiwAZAAAAAA==.Lillivarak:BAABLgAECn8UAAIQAAcJFgcVswD4AAAQAAcJFgcVswD4AAAAAA==.Lilriotzz:BAAALgAECgQJBgAAAA==.Lilzdrlockz:BAAALgAECgUJBgAAAA==.Lithedra:BAAALgADCgcJDwAAAA==.',
Lu='Lucavi:BAAALgAECgMJAwAAAA==.Lucyvar:BAAALgAECgkJBwAAAA==.Luke:BAAALgADCgUJBwAAAA==.Luma:BAAALgAECgMJBQAAAA==.Luther:BAABLgAECn8XAAIFAAkJNw9XJQDYAQAFAAkJNw9XJQDYAQAAAA==.',
Ly='Lyla:BAAALgADCgQJBgAAAA==.',
Ma='Magnux:BAAALgAECgEJAgAAAA==.Malazark:BAAALgADCgYJBgAAAA==.Malríus:BAAALgAECgQJEQAAAA==.Manales:BAAALgAECgcJBgAAAA==.Marhukai:BAABLgAECn8vAAIQAAkJQR8AEQDFAgAQAAkJQR8AEQDFAgAAAA==.Marotal:BAABLgAECn8kAAIEAAcJNxbYXwCkAQAEAAcJNxbYXwCkAQAAAA==.Martysparty:BAABLgAECn8kAAIOAAkJ9huLBwA2AgAOAAkJ9huLBwA2AgAAAA==.Mavaena:BAAALgAECgUJCQAAAA==.Mavrane:BAAALgADCgEJAgAAAA==.',
Me='Meashakegs:BAAALgAECggJEQAAAA==.Mechaboomer:BAABLgAECn8rAAIHAAgJnBp1KQAOAgAHAAgJnBp1KQAOAgAAAA==.Megafire:BAAALgADCggJDQAAAA==.Megahertz:BAAALgADCgYJBgAAAA==.Melcanthet:BAAALgADCggJCAAAAA==.Mellowrock:BAAALgAECgUJBgABLgAECgYJBQAIAAAAAA==.',
Mi='Mickhaggis:BAAALgADCgIJAgAAAA==.Micktarogar:BAAALgAECgcJEwAAAA==.Mickwutang:BAAALgAFFAEJAQAAAA==.Miklaga:BAAALgAECgEJAgAAAA==.Milince:BAAALgADCgMJAgAAAA==.Minikloon:BAAALgAECgYJDgAAAA==.Minphoria:BAAALgADCgQJBgAAAA==.Missylock:BAAALgADCgYJBgAAAA==.Mistilinn:BAABLgAECn8qAAImAAkJXQc9DwA/AQAmAAkJXQc9DwA/AQAAAA==.Miyri:BAAALgAECgEJAgABLgAFFAMJCAALAM8WAA==.',
Mo='Mollyporph:BAAALgAECgEJAQAAAA==.Monoco:BAAALgAECgYJEwAAAA==.Moopandax:BAACLgAFFH8SAAIXAAQJrx5mDgBwAQAXAAQJrx5mDgBwAQAuAAQKf0YAAxcACQnbJccAAHwDABcACQnbJccAAHwDACIACAmhH8kFAHcCAAEuAAUUBQkXABcACyEA.Mortrum:BAAALgADCgQJBAAAAA==.Moxestime:BAAALgAECgEJAgAAAA==.Moxsdeath:BAAALgADCgYJBgAAAA==.Moxsdeaths:BAAALgADCgcJBwAAAA==.',
Mu='Mushaboom:BAABLgAECn8WAAIFAAcJ9gcfOwDwAAAFAAcJ9gcfOwDwAAAAAA==.Muzzler:BAABLgAECn9BAAIEAAgJqSFKHwCHAgAEAAgJqSFKHwCHAgAAAA==.',
My='Myeyes:BAAALgAECgEJAgAAAA==.Mylinkah:BAAALgADCgQJBAAAAA==.Mynamefizz:BAEBLgAECn8UAAQSAAkJKxfCKgAWAgASAAkJ9BXCKgAWAgAGAAMJghQfGwCtAAAjAAIJyhuNHACaAAABLgAECggJIAABAOgaAA==.Myotonic:BAAALgADCgQJBAAAAA==.Mythlok:BAAALgAECgMJAwAAAA==.Mythreiel:BAAALgAECgUJBgAAAA==.Mythykal:BAAALgAECgIJAgAAAA==.',
['Mé']='Méasha:BAAALgAECgYJBgAAAA==.',
['Mï']='Mïlk:BAAALgAECgYJBgAAAQ==.',
Na='Nachtmar:BAAALgAECgQJBAABLgAECggJGQAQAEMPAA==.Nadis:BAAALgAECgIJAwAAAA==.Narcessa:BAAALgADCgQJBAAAAA==.Nawk:BAAALgAECgEJAQAAAA==.',
Ne='Nennerb:BAAALgADCgQJBAAAAA==.',
Ni='Nicola:BAAALgAECgQJBwAAAA==.Nightxwish:BAABLgAECn8XAAIbAAYJ2RWeIgCJAQAbAAYJ2RWeIgCJAQAAAA==.Niranye:BAAALgADCgEJAQAAAA==.',
No='Noisemarine:BAACLgAFFH8JAAITAAQJzhCiEAD+AAATAAQJzhCiEAD+AAAuAAQKfxcAAhMACAmeGlQMAAACABMACAmeGlQMAAACAAAA.Nokk:BAAALgADCgEJAQAAAA==.Nokkco:BAAALgAECgEJAgAAAA==.Norellia:BAAALgAECgEJAgAAAA==.Northleo:BAAALgADCgcJDQAAAA==.Northspirit:BAAALgAECgUJDwAAAA==.',
Nu='Nuit:BAAALgADCgUJBQABLgAECgYJCwAIAAAAAA==.',
Ny='Nyarlothep:BAAALgAECgQJBAAAAA==.Nyx:BAAALgADCgUJBQABLgAECggJMQAQAC8fAA==.',
Oa='Oakenshièld:BAAALgAECgYJCAAAAA==.',
Od='Odindh:BAAALgAFFAEJAQAAAA==.Odins:BAAALgAECgMJAwABLgAFFAEJAQAIAAAAAA==.',
Oh='Ohwhelp:BAABLgAFFH8GAAIdAAMJXxVvLADmAAAdAAMJXxVvLADmAAABLgAFFAYJIwAXADwmAA==.Ohyikers:BAACLgAFFH8jAAIXAAYJPCaDAwAnAgAXAAYJPCaDAwAnAgAuAAQKfzQAAhcACAnRJlcDABgDABcACAnRJlcDABgDAAAA.',
Ok='Oken:BAAALgADCgUJBQAAAA==.',
Om='Om:BAAALgADCgcJCQAAAA==.',
Or='Orklock:BAAALgADCgMJAwAAAA==.',
Pa='Pallek:BAAALgAECgcJBwABLgAECgYJFAAHAEERAA==.Palli:BAABLgAECn8dAAINAAcJ8BXUKACgAQANAAcJ8BXUKACgAQAAAA==.Paogao:BAAALgAECgIJAwAAAA==.Parry:BAAALgADCgQJBAAAAA==.Pasghetti:BAAALgADCgMJAwAAAA==.Pasta:BAABLgAECn8rAAInAAkJSh6PBQC5AgAnAAkJSh6PBQC5AgAAAA==.',
Pe='Pewpewbite:BAAALgAECgcJEAAAAA==.',
Ph='Phantomarrow:BAACLgAFFH8SAAQhAAUJlRKcEQAiAQAhAAQJGAycEQAiAQAmAAUJHQv+FQDCAAAHAAEJ9g6KdQBJAAAuAAQKfxwABAcABgnsIUA4ANIBAAcABgnsIUA4ANIBACYABQmzGbBCAE0BACEAAQkAAOpdAAAAAAAA.Phatcow:BAABLgAECn80AAMCAAkJgxt7FwBaAgACAAgJaxp7FwBaAgAZAAkJRhSICAAIAgAAAA==.Phoseidon:BAAALgADCgcJCQAAAA==.Phude:BAACLgAFFH8JAAIQAAMJ6RPdSADwAAAQAAMJ6RPdSADwAAAuAAQKf0QAAhAACQl4HekSALYCABAACQl4HekSALYCAAAA.',
Pi='Pinch:BAAALgAECgMJAwAAAA==.',
Po='Pohl:BAAALgAECgYJDQAAAA==.Pokimana:BAAALgADCgEJAQAAAA==.Poohynok:BAABLgAECn85AAIEAAkJDSXrBgA1AwAEAAkJDSXrBgA1AwAAAA==.',
Pu='Pukefeast:BAAALgAECgYJEgAAAA==.',
Py='Pyramys:BAACLgAFFH8TAAInAAUJLB/eEABUAQAnAAUJLB/eEABUAQAuAAQKfyMAAicACAmQIQIRAJkCACcACAmQIQIRAJkCAAAA.',
['Pè']='Pèrce:BAAALgAECgYJCQAAAA==.',
Qu='Quepaoka:BAAALgADCgIJAgAAAA==.',
Ra='Raklem:BAAALgAECgMJAwABLgAECgYJCgAIAAAAAA==.Ramble:BAAALgADCgQJBAABLgAECgQJBgAIAAAAAA==.Ramstein:BAAALgAECgMJAwAAAA==.Raphînîty:BAAALgADCgMJBQAAAA==.Rashari:BAAALgADCgYJCAAAAA==.Rawhawk:BAAALgAECgUJCgABLgAECgcJFQAHACgPAA==.Razgrizz:BAAALgAECgMJBQAAAA==.',
Re='Retro:BAAALgAECgIJBAAAAA==.Revelatus:BAAALgAECgQJBgAAAA==.Reythanas:BAAALgAECgQJBwAAAA==.Rezzin:BAAALgAECgEJAQAAAA==.',
Ri='Rileyann:BAABLgAECn8fAAMcAAgJOQxmJAB9AQAcAAgJOQxmJAB9AQARAAYJAwNMRADaAAAAAA==.',
Ro='Rolls:BAAALgAECgQJBAAAAA==.Roozer:BAAALgAECgMJBAAAAA==.',
['Rå']='Råphå:BAAALgAECgMJBAAAAA==.',
Sa='Saelyria:BAACLgAFFH8IAAILAAMJzxYiLgDZAAALAAMJzxYiLgDZAAAuAAQKfxgAAgsACQkiHNkKAPECAAsACQkiHNkKAPECAAAA.Saga:BAAALgADCgUJBQABLgAECgkJOgAOAOMSAA==.Sagepower:BAAALgADCgYJBgAAAA==.Sagethepally:BAAALgAECgcJBAAAAA==.Saintfail:BAABLgAECn8cAAINAAYJbSRbFQA6AgANAAYJbSRbFQA6AgABLgAECgcJJQAUAAMhAA==.Sainthymn:BAAALgAECgcJEgABLgAECgcJJQAUAAMhAA==.Saintmist:BAABLgAECn8lAAIUAAcJAyG2DACaAgAUAAcJAyG2DACaAgAAAA==.Salero:BAAALgADCgIJAQAAAA==.Sandiera:BAABLgAECn8cAAMEAAgJnAoGkwA3AQAEAAgJnAoGkwA3AQAlAAMJPAOoFwBcAAAAAA==.Saxtön:BAAALgADCggJEwAAAA==.Sayberix:BAAALgAECgcJBwABLgAFFAQJCgAYAIUPAA==.',
Sc='Scoreboard:BAACLgAFFH8fAAIoAAcJ4CUWAADDAgAoAAcJ4CUWAADDAgAuAAQKfyEAAygACQkgJg0AAOsDACgACQkgJg0AAOsDACcAAQnwFJhaAE8AAAAA.Scorn:BAAALgAECgYJDgAAAA==.Scottx:BAACLgAFFH8FAAILAAIJmAgmSQB3AAALAAIJmAgmSQB3AAAuAAQKfxQAAgsABwlPFJQ1AKEBAAsABwlPFJQ1AKEBAAAA.',
Se='Sebas:BAAALgAECgEJAQAAAA==.Sedric:BAAALgAECgYJDgAAAA==.Selkz:BAAALgAECgcJDQAAAA==.Selsonblue:BAAALgAECgMJAwAAAA==.Sesskaa:BAAALgAECgcJDAAAAA==.',
Sh='Shadowcursed:BAAALgADCgcJCgAAAA==.Shadowstorm:BAAALgADCgQJBAAAAA==.Shadøws:BAAALgAECgEJAQAAAA==.Shakenhealz:BAAALgADCgYJBgAAAA==.Sharhox:BAAALgAECgEJAQAAAA==.Shathos:BAAALgADCgEJAQAAAA==.Sheebá:BAAALgADCgYJCwAAAA==.Shishkbob:BAAALgADCgkJCQAAAA==.Shivax:BAAALgAECgYJDgAAAA==.Shünúkh:BAAALgADCgYJBgAAAA==.',
Si='Sigewulf:BAAALgAFFAIJBAABLgAECgcJHAAFACQGAA==.Signal:BAAALgAECgEJAQAAAA==.Singbow:BAAALgADCgYJBgABLgAECggJJQALAMgOAA==.Sinogad:BAABLgAECn8YAAMXAAgJlBF1IwCAAQAXAAgJlBF1IwCAAQALAAUJ4xNVTQA2AQAAAA==.Sinol:BAAALgAECgYJDwABLgAECggJGAAXAJQRAA==.Sioux:BAAALgADCgEJAQAAAA==.Sixosix:BAAALgADCgIJAgAAAA==.',
Sk='Skaro:BAABLgAECn8VAAIUAAcJgQ8+PQAiAQAUAAcJgQ8+PQAiAQAAAA==.Skyborn:BAABLgAECn8WAAIEAAcJ0w3khwBLAQAEAAcJ0w3khwBLAQAAAA==.',
Sl='Slamahoochee:BAAALgAECgYJCQAAAA==.Slay:BAACLgAFFH8MAAIXAAQJUh3CDwBjAQAXAAQJUh3CDwBjAQAuAAQKfyoABBcACAmPIbgMAGYCABcACAmPIbgMAGYCAAwABglkG48TAHgBAAsAAQk/A9TaAB0AAAAA.',
Sm='Smokedademon:BAAALgAECgMJCQAAAA==.Smokiebear:BAAALgAECgUJDAAAAA==.Smunkie:BAABLgAECn8fAAIFAAcJyiZPCACSAgAFAAcJyiZPCACSAgABLgAECgkJEwAIAAAAAA==.',
Sn='Snickeers:BAAALgAECgEJAQAAAA==.',
So='Somapeace:BAAALgAECgYJCAAAAA==.Somogyi:BAAALgADCgIJAgAAAA==.',
Sp='Spopovich:BAAALgADCggJCAABLgAECgMJAwAIAAAAAA==.Sprints:BAAALgAECgQJBAAAAA==.',
St='Stinko:BAAALgADCgEJAgAAAA==.Stitchlock:BAAALgAECgIJAgAAAA==.Stitchofevil:BAABLgAECn8WAAQjAAcJuBoEBgACAgAjAAYJUB8EBgACAgASAAQJpAlu4ABvAAAGAAIJtQ8hYQBMAAAAAA==.Stonedshaman:BAAALgADCgYJBgABLgAECgIJAgAIAAAAAA==.Stormhands:BAAALgAECgYJDwAAAA==.Stormhugger:BAAALgAFFAEJAQAAAA==.Stormslight:BAAALgAECgQJBQAAAA==.Stoutnholy:BAABLgAECn8VAAIQAAcJwQlOlwAlAQAQAAcJwQlOlwAlAQAAAA==.Stratichnut:BAABLgAECn8lAAILAAgJyA4SPwBzAQALAAgJyA4SPwBzAQAAAA==.Stromar:BAAALgADCgkJFQAAAA==.Stwampadin:BAABLgAECn8hAAINAAkJyyGAAgBqAwANAAkJyyGAAgBqAwAAAA==.Stwevoker:BAAALgAECgMJAwABLgAECgkJIQANAMshAA==.Stwonkfu:BAAALgAECggJCwABLgAECgkJIQANAMshAA==.',
Su='Sumire:BAAALgADCggJDgABLgAECgYJCgAIAAAAAA==.Surloyn:BAAALgAECgQJBAAAAA==.',
Sv='Sveny:BAAALgAECgEJAQAAAA==.',
Sw='Swampert:BAACLgAFFH8QAAIPAAUJ9BSxGQAnAQAPAAUJ9BSxGQAnAQAuAAQKfx8AAg8ACQnTH+gMAO8CAA8ACQnTH+gMAO8CAAAA.Swamperting:BAABLgAECn8XAAIPAAcJMhNFMABmAQAPAAcJMhNFMABmAQABLgAFFAUJEAAPAPQUAA==.Swaye:BAABLgAECn8pAAIRAAkJQxSEFgDxAQARAAkJQxSEFgDxAQAAAA==.Sweetfox:BAAALgAECgYJCgAAAA==.Swimchick:BAAALgAECgUJCQAAAA==.Switched:BAAALgADCgcJBwABLgAECgkJEwAIAAAAAA==.Swizzle:BAAALgAECgQJBAAAAA==.',
Sy='Syllvanas:BAABLgAECn8YAAIHAAgJehC3RgChAQAHAAgJehC3RgChAQAAAA==.Sythia:BAABLgAFFH8FAAIcAAMJ1QVxHACoAAAcAAMJ1QVxHACoAAABLgAFFAUJCQASAH4UAA==.',
Ta='Taltost:BAABLgAECn8VAAIHAAcJKA9xYQBVAQAHAAcJKA9xYQBVAQAAAA==.Tantrik:BAAALgADCgEJAQAAAA==.Tartin:BAAALgAECgMJAwAAAA==.Tarv:BAAALgADCgMJAQAAAA==.Tashamirage:BAAALgAECgMJBAAAAA==.Tauriel:BAAALgAECgUJBwAAAA==.',
Te='Teex:BAAALgADCgYJBwAAAA==.Teksuo:BAACLgAFFH8JAAIDAAMJ+BJNGQDXAAADAAMJ+BJNGQDXAAAuAAQKf0cAAgMACQkmHPgJAIACAAMACQkmHPgJAIACAAAA.Telamontay:BAAALgADCgkJFQAAAA==.Telferas:BAABLgAECn8VAAIXAAgJ+RmhHwCdAQAXAAgJ+RmhHwCdAQABLgAFFAYJHAAVAM8cAA==.Tenithon:BAACLgAFFH8HAAINAAMJah2zHQADAQANAAMJah2zHQADAQAuAAQKfzEAAg0ACQmsIoIEADADAA0ACQmsIoIEADADAAAA.Tenshenzen:BAABLgAECn8ZAAIUAAkJ4hNxFwAgAgAUAAkJ4hNxFwAgAgAAAA==.',
Th='Therandis:BAAALgADCgUJBQAAAA==.Thetombo:BAAALgAECgYJCAAAAA==.Thierry:BAAALgADCgUJBQAAAA==.Thierrye:BAABLgAECn8VAAIaAAYJlhtmTQC/AQAaAAYJlhtmTQC/AQAAAA==.Tholaren:BAABLgAECn8qAAMHAAgJABL9RQCjAQAHAAgJABL9RQCjAQAmAAUJVQctHwCSAAAAAA==.Threed:BAAALgAECggJDAAAAA==.Threewar:BAAALgAECgIJAgABLgAECggJDAAIAAAAAA==.Thrissa:BAABLgAECn8WAAILAAcJXRHuPAB9AQALAAcJXRHuPAB9AQAAAA==.Thulgrim:BAAALgADCgYJBgAAAA==.',
To='Torrque:BAAALgADCgkJCQABLgADCgYJCwAIAAAAAA==.Totemlicker:BAAALgAECgEJAQAAAA==.',
Tr='Trandeath:BAAALgAECgQJBAAAAA==.Trangon:BAABLgAECn8nAAIQAAkJlgqcXwCSAQAQAAkJlgqcXwCSAQAAAA==.Traveler:BAAALgADCgEJAQAAAA==.Traygon:BAAALgAECgYJBgAAAA==.Trillion:BAAALgADCggJCAAAAA==.',
Tu='Tunzoffun:BAAALgAECgIJBAAAAA==.',
Un='Unanswered:BAAALgAECgEJAQABLgAFFAUJBQAWANEbAA==.Underbyte:BAAALgADCggJDwAAAA==.Unknownname:BAAALgADCgUJBwAAAA==.',
Ur='Urholiness:BAAALgADCgkJDwAAAA==.',
Va='Vaeleia:BAAALgAECgQJBgAAAA==.Vahnkar:BAAALgADCgYJCQAAAA==.Valentinu:BAAALgADCgcJDwAAAA==.Valkyrie:BAAALgAECgEJAgAAAA==.Vaneshk:BAAALgADCgEJAQAAAA==.Varchemical:BAAALgAECgcJBwAAAA==.Varithal:BAACLgAFFH8JAAIeAAMJMhkJFwDxAAAeAAMJMhkJFwDxAAAuAAQKfz4AAh4ACQk8H84DAOICAB4ACQk8H84DAOICAAEuAAEKBgkJAAgAAAAA.Varri:BAAALgAECgMJBQAAAA==.Vastectomy:BAAALgAECggJCgAAAA==.',
Ve='Vegasana:BAAALgAECgYJCwAAAA==.Velwing:BAAALgAECgUJBwAAAA==.Venawyn:BAABLgAECn8gAAIHAAcJTwz2aQBAAQAHAAcJTwz2aQBAAQAAAA==.Verakhaa:BAAALgAECgQJBAAAAA==.',
Vi='Vibepriest:BAAALgADCgEJAQAAAA==.Vindfaramaðr:BAABLgAECn8cAAIFAAcJJAaMRADMAAAFAAcJJAaMRADMAAAAAA==.Vixin:BAAALgAECgYJDQAAAA==.',
Vo='Voidsaack:BAAALgAECgcJCgAAAA==.Voidz:BAAALgAECgEJAQAAAA==.Volfguar:BAAALgAECgQJAQAAAA==.Vortan:BAABLgAECn8bAAIhAAgJZRvhDgAjAgAhAAgJZRvhDgAjAgAAAA==.',
Vr='Vreya:BAAALgADCgkJFQABLgAECgMJBQAIAAAAAA==.',
Vy='Vynthus:BAAALgAECgcJEQAAAA==.',
['Vä']='Värys:BAAALgAECgEJAQAAAA==.',
Wa='Wan:BAAALgADCgEJAQAAAA==.Warhundin:BAEALgAECgUJCAABLgAFFAMJCQAQADwIAA==.Warwan:BAAALgADCgIJAgAAAA==.Wazzbozz:BAAALgAECgQJAgAAAA==.Wazzdh:BAAALgAECgMJAwAAAA==.Wazzdot:BAAALgAECgUJCQAAAA==.Wazzhunnah:BAABLgAECn8kAAMhAAgJ3xGrGgCrAQAhAAgJ3xGrGgCrAQAmAAQJZAlhZQCqAAAAAA==.',
We='Werg:BAAALgAECggJCgABLgAFFAQJBQAiACgHAA==.',
Wh='Whatmyname:BAABLgAECn8wAAIiAAgJ2wqQJADoAAAiAAgJ2wqQJADoAAAAAA==.Whispp:BAAALgAECgYJCAAAAA==.',
Wi='Wildmandave:BAAALgADCgUJBQAAAA==.Willough:BAAALgADCgYJCwAAAA==.',
Wo='Wonsok:BAAALgAECgcJDgAAAA==.',
Wy='Wyvoker:BAABLgAECn8dAAIeAAkJXxeTCABDAgAeAAkJXxeTCABDAgAAAA==.',
['Wì']='Wìllow:BAAALgADCgIJAgAAAA==.',
['Wÿ']='Wÿm:BAAALgAECgkJDwABLgAECgkJHQAeAF8XAA==.',
Xa='Xaoleth:BAAALgADCgEJAQAAAA==.',
Xe='Xenorion:BAAALgAECgMJAwAAAA==.Xephora:BAAALgAECgEJBgAAAA==.',
Xi='Xiq:BAAALgADCgUJBQAAAA==.',
Xr='Xrinch:BAAALgADCgYJBgAAAA==.',
Xu='Xunadin:BAAALgADCgkJIgAAAA==.Xuny:BAAALgAECgUJEAAAAA==.',
Yo='Yordi:BAAALgAECgUJEQAAAA==.',
Yu='Yuzuriha:BAACLgAFFH8JAAIHAAMJNhy0NwAHAQAHAAMJNhy0NwAHAQAuAAQKfz4AAgcACQmQJNACAE4DAAcACQmQJNACAE4DAAAA.',
Za='Zaelia:BAAALgADCgYJBgABLgAECggJMQAQAC8fAA==.Zaletren:BAAALgAECgkJAQAAAA==.Zamaze:BAABLgAECn8nAAMTAAkJkCA4BQCnAgATAAkJkCA4BQCnAgAYAAEJLwkrZgApAAAAAA==.Zannah:BAAALgAECgMJAwAAAA==.Zant:BAAALgAECgIJAQAAAA==.',
Ze='Zeekielle:BAEBLgAECn86AAIfAAkJ4BRoDgAJAgAfAAkJ4BRoDgAJAgABLgAFFAMJCQAQADwIAA==.Zenius:BAAALgAECgYJDQAAAA==.Zerithrielle:BAABLgAECn8pAAIfAAgJ2RYJFwCYAQAfAAgJ2RYJFwCYAQAAAA==.',
Zi='Zippii:BAAALgAECgYJBwAAAA==.Zipy:BAABLgAECn8sAAIcAAgJXB6TCAC9AgAcAAgJXB6TCAC9AgAAAA==.',
Zo='Zof:BAAALgAECgYJDgAAAA==.Zorathar:BAAALgADCgYJBgAAAA==.',
Zu='Zugtag:BAABLgAECn83AAIJAAkJhyE/CAAVAwAJAAkJhyE/CAAVAwAAAA==.',
Zy='Zyllo:BAAALgAECgMJBAAAAA==.',
['Zá']='Závier:BAABLgAECn8UAAIEAAYJ/QLr4gCyAAAEAAYJ/QLr4gCyAAAAAA==.',
['Zõ']='Zõf:BAAALgAECgEJAgABLgAECgYJDgAIAAAAAA==.',
['Äe']='Äemond:BAAALgADCgMJAwAAAA==.',
['Ål']='Ålïce:BAABLgAECn9CAAIQAAkJphyvFQCjAgAQAAkJphyvFQCjAgAAAA==.',
['Ëd']='Ëdward:BAAALgADCgcJCgABLgAECgUJDAAIAAAAAA==.',
['Ôh']='Ôhmyn:BAAALgADCgMJAwABLgAECgcJGAAQAEMMAA==.',
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
