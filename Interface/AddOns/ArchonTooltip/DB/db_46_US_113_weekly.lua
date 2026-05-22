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

local lookup = {'Monk-Windwalker','Mage-Frost','Monk-Brewmaster','Warlock-Destruction','Hunter-BeastMastery','Unknown-Unknown','Druid-Restoration','Druid-Feral','Paladin-Holy','Paladin-Protection','Warrior-Fury','Shaman-Elemental','Shaman-Restoration','Priest-Discipline','Warlock-Demonology','Warrior-Protection','Paladin-Retribution','Monk-Mistweaver','DeathKnight-Unholy','Evoker-Devastation','DeathKnight-Frost','DeathKnight-Blood','Druid-Balance','Shaman-Enhancement','Warrior-Arms','DemonHunter-Devourer','Priest-Shadow','Priest-Holy','Evoker-Augmentation','Evoker-Preservation','DemonHunter-Havoc','Druid-Guardian','Warlock-Affliction','Mage-Fire','Mage-Arcane','Hunter-Marksmanship','Rogue-Subtlety','Hunter-Survival','Rogue-Outlaw',}
local provider = {region='US',realm='GrizzlyHills',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Abramz:BAAALgADCgMJAwAAAA==.',
Ad='Adely:BAAALgAECgEJAQAAAA==.Adelymon:BAAALgAFFAIJAgAAAA==.Adelymonk:BAAALgAECgYJCwAAAA==.Adonysroth:BAAALgAECgIJAgAAAA==.Adrahil:BAAALgADCgIJAgAAAA==.',
Ae='Aeonra:BAAALgADCgIJAgAAAA==.',
Ag='Agronak:BAAALgAECgQJBgAAAA==.',
Al='Aldan:BAAALgADCgMJAwAAAA==.Aldazen:BAACLgAFFH8GAAIBAAIJqyI3FgDOAAABAAIJqyI3FgDOAAAuAAQKfy4AAgEACAnxIwQHAA4DAAEACAnxIwQHAA4DAAAA.Alenara:BAAALgAECgYJDwABLgAECggJHAACAJwKAA==.Aletheìa:BAAALgAECgEJAQAAAA==.Alovan:BAAALgADCgEJAQABLgAECgcJHAADACQGAA==.Alyssandra:BAABLgAECn8UAAIEAAYJLxe0CgBFAQAEAAYJLxe0CgBFAQAAAA==.',
Am='Amarella:BAABLgAECn8UAAIFAAcJqiCkKQAQAgAFAAcJqiCkKQAQAgAAAA==.Amarrite:BAAALgAECgEJAgABLgAECgIJAgAGAAAAAA==.Ammalane:BAAALgAECgIJAgAAAA==.Amunzo:BAAALgAECgEJAQABLgAECgYJCwAGAAAAAA==.',
An='Angler:BAAALgAECgMJAwAAAA==.Angyrolaj:BAAALgAECgYJEAAAAA==.',
Aq='Aquadora:BAAALgADCgMJAwAAAA==.',
Ar='Arangarr:BAABLgAECn8vAAMHAAkJpx3YCADvAgAHAAkJpx3YCADvAgAIAAEJ8AyuMQA2AAAAAA==.Arcin:BAAALgADCgEJAQAAAA==.Areyana:BAAALgAECgYJDwAAAA==.Areyoudead:BAAALgAECgQJBAABLgADCgYJCwAGAAAAAA==.Aristoi:BAAALgAECgEJAQAAAA==.Arkand:BAAALgADCgUJBAAAAA==.Arkandra:BAAALgAECgQJCwAAAA==.Arkara:BAAALgADCgEJAQAAAA==.Arrietty:BAABLgAECn8XAAIJAAYJlxVYMQBAAQAJAAYJlxVYMQBAAQAAAA==.Arthues:BAAALgAECgQJBwAAAA==.Arthâs:BAAALgAECgYJBQAAAA==.Arumathe:BAABLgAECn8XAAIKAAkJyBKJCwC2AQAKAAkJyBKJCwC2AQAAAA==.',
As='Asura:BAACLgAFFH8IAAILAAMJkCKsGwABAQALAAMJkCKsGwABAQAuAAQKfyAAAgsACQnKItkIAB4DAAsACQnKItkIAB4DAAAA.',
Au='Aurelian:BAAALgAECgEJAgAAAA==.',
Az='Az:BAABLgAECn8VAAILAAYJOCZzEgAWAgALAAYJOCZzEgAWAgAAAA==.Azeriall:BAACLgAFFH8GAAIMAAIJfgMcMABvAAAMAAIJfgMcMABvAAAuAAQKfzcAAwwACAl1E8wcAKUBAAwACAl1E8wcAKUBAA0ABAlKAVuGAHsAAAAA.Azerowolf:BAAALgADCggJCAAAAA==.Azráèl:BAAALgADCgMJAwAAAA==.',
Ba='Babyboom:BAAALgAECgEJAQAAAA==.Baconhammr:BAAALgAECgYJEQAAAA==.Badazmf:BAAALgADCgcJDAABLgAECggJJAAOAOEXAA==.Badcompany:BAAALgADCgUJBQABLgAECggJHgAHAKkNAA==.Baddream:BAAALgAECgYJCgAAAA==.Baelmyre:BAAALgADCgUJBQAAAA==.Balenciagosa:BAAALgADCgUJBQABLgAECggJHAACAJwKAA==.Banshiï:BAABLgAECn8kAAIEAAgJsRF0CAB1AQAEAAgJsRF0CAB1AQAAAA==.Baratheøn:BAABLgAECn8cAAIHAAcJ9RftLgCfAQAHAAcJ9RftLgCfAQAAAA==.Bax:BAAALgADCgIJAgAAAA==.Baxar:BAAALgAECgIJAgAAAA==.',
Bb='Bbd:BAAALgAECggJCQABLgAECgYJDgAGAAAAAA==.',
Be='Beeftard:BAABLgAECn8XAAIJAAgJzRhiKgDfAQAJAAgJzRhiKgDfAQAAAA==.Bellavix:BAAALgADCgMJBAAAAA==.Benafflic:BAAALgAECgEJAQABLgAECgMJAwAGAAAAAA==.Berserrk:BAAALgADCgYJBgAAAA==.Bershale:BAAALgAECgEJAQABLgAECgYJBwAGAAAAAA==.',
Bi='Bifficus:BAAALgAECgYJDgAAAA==.Big:BAAALgADCgMJBAAAAA==.',
Bl='Blackscorn:BAAALgADCgEJAQAAAA==.Blackthôrne:BAAALgADCgUJCQAAAA==.Blucki:BAABLgAECn8cAAIPAAgJ7AlWaAAuAQAPAAgJ7AlWaAAuAQAAAA==.',
Bo='Bobfu:BAAALgADCgYJCAAAAA==.',
Br='Brieze:BAAALgADCgIJAgAAAA==.Brige:BAAALgAECggJBgAAAA==.Brightstar:BAAALgADCgEJAQAAAA==.Brimaz:BAAALgADCgEJAQAAAA==.',
Bu='Buhhead:BAAALgADCgUJBgAAAA==.Bunana:BAAALgADCgEJAQAAAA==.Bunbear:BAAALgAECgIJAgAAAA==.Bunette:BAAALgADCgEJAQAAAA==.',
Bw='Bwamsamdi:BAAALgADCgYJBgAAAA==.',
By='Byzantium:BAABLgAECn8ZAAIQAAYJrQZUJgC2AAAQAAYJrQZUJgC2AAAAAA==.',
['Bô']='Bônebeard:BAAALgAECgEJAQAAAA==.',
Ca='Cabledryer:BAAALgAECgQJEAAAAA==.Caelidpackx:BAAALgADCgYJBwAAAA==.Caluu:BAAALgADCgEJAQAAAA==.Carnry:BAAALgADCgQJBAAAAA==.Catboy:BAABLgAECn8aAAICAAgJ6RQppgCMAQACAAgJ6RQppgCMAQAAAA==.Catnips:BAABLgAECn8cAAIRAAgJUBhQRwCnAQARAAgJUBhQRwCnAQAAAA==.Catpow:BAAALgAECgkJAgAAAA==.',
Ch='Chanaranach:BAAALgAECgYJCgAAAA==.Charitey:BAAALgADCgQJBAAAAA==.Cheelo:BAAALgAECggJDgAAAA==.Chknnugget:BAAALgAECgMJBQAAAA==.Chromatic:BAABLgAECn8iAAMNAAgJARR6IgDnAQANAAgJARR6IgDnAQAMAAQJYg5oSgCzAAAAAA==.',
Ci='Cindrethresh:BAAALgAECgEJAQAAAA==.',
Co='Coffeeblak:BAABLgAECn8ZAAMBAAgJBRNLJgCmAQABAAcJlxNLJgCmAQASAAUJFQ65PwDkAAAAAA==.Coldstorm:BAAALgAECgYJCgAAAA==.Collision:BAAALgAECgEJAQAAAA==.Compensating:BAAALgADCgYJBgAAAA==.Connor:BAAALgADCgcJBwAAAA==.Connsumption:BAAALgAECgYJCgAAAA==.Corrine:BAAALgAECgYJBgAAAA==.',
Cr='Crazybatt:BAAALgAECgYJDQAAAA==.Crypt:BAAALgAECgYJCgAAAA==.',
Cu='Cuckchairpov:BAACLgAFFH8OAAMDAAQJJRR6FAAxAQADAAQJpBN6FAAxAQABAAIJQg15DACgAAAuAAQKfywAAwEACQkrH2gKANICAAEACAl4HWgKANICAAMACQneFI0OABMCAAAA.',
Cy='Cynderleena:BAAALgAECgYJBwAAAA==.Cynyia:BAABLgAECn8uAAIFAAgJnBUrKwAIAgAFAAgJnBUrKwAIAgAAAA==.',
Cz='Czk:BAAALgADCgYJBgABLgAECggJGQABAAUTAA==.',
['Có']='Cóldblóód:BAAALgAECgIJAgAAAA==.',
Da='Daddyelessar:BAAALgAECgQJCAAAAA==.Dafattyup:BAABLgAECn8aAAIPAAYJlRxUYwCgAQAPAAYJlRxUYwCgAQAAAA==.Daghmar:BAAALgADCgUJBQAAAA==.Dagon:BAAALgAECgMJAwAAAA==.Dakotarain:BAAALgADCgIJAgAAAA==.Dalerontwo:BAAALgADCgEJAQAAAA==.Darruin:BAABLgAECn8VAAITAAgJUiHYHQBQAgATAAgJUiHYHQBQAgABLgAFFAYJHAAUAM8cAA==.Dayrun:BAAALgAECgUJDQAAAA==.',
De='Deadicee:BAAALgAECgIJAgABLgAECgYJEwAGAAAAAA==.Deathturtle:BAABLgAECn8eAAITAAgJLxBwaQBJAQATAAgJLxBwaQBJAQAAAA==.Deavaos:BAAALgAECgQJBwAAAA==.Dedmartigan:BAAALgADCgUJBQAAAA==.Deeanndra:BAABLgAECn8WAAMTAAYJnQ6XhwALAQATAAYJnQ6XhwALAQAVAAEJDAnNJAAoAAAAAA==.Deevz:BAAALgAECgIJAgAAAA==.Demandred:BAAALgAECgUJBQAAAA==.Demiz:BAABLgAECn8vAAMNAAgJtRoBFgBGAgANAAgJtRoBFgBGAgAMAAcJaA1oNAAPAQAAAA==.Deredris:BAAALgAECgQJBAABLgAECgYJCgAGAAAAAA==.Dertka:BAAALgAECgYJDAAAAA==.',
Di='Discodruid:BAABLgAECn8UAAIHAAYJKRNUQgA+AQAHAAYJKRNUQgA+AQAAAA==.Dishsoap:BAAALgAECgMJAwABLgAFFAQJDgALAAgVAA==.Dixie:BAAALgAECgEJAQAAAA==.',
Dj='Djall:BAAALgAECgUJBQAAAA==.',
Do='Dommy:BAAALgAECgcJCgABLgAECgcJHwADAMomAA==.Domw:BAAALgAECgYJCgABLgAECgcJHwADAMomAA==.Donham:BAACLgAFFH8TAAMTAAYJxhtkEgCsAQATAAUJxhtkEgCsAQAWAAEJAABBEwBZAAAuAAQKfx8AAhMACAnLHzweAMsCABMACAnLHzweAMsCAAAA.Dorkimedes:BAAALgAECgQJCgAAAA==.Dottie:BAABLgAECn8oAAMEAAgJMBM2FwCQAQAEAAcJJQ82FwCQAQAPAAgJ6hEsRACQAQAAAA==.Dotvinci:BAAALgAECgYJBgAAAA==.',
Dr='Draelesh:BAABLgAECn8lAAIXAAgJ9ROdGQCkAQAXAAgJ9ROdGQCkAQAAAA==.Draenk:BAAALgADCgUJBQAAAA==.Dragún:BAAALgAECgYJCwAAAA==.Drakari:BAAALgADCgYJBgAAAA==.Drazon:BAAALgADCgIJAgAAAA==.Drewit:BAABLgAECn8VAAIIAAYJPxA1FQBiAQAIAAYJPxA1FQBiAQAAAA==.',
Du='Ducan:BAAALgADCgYJCQAAAA==.Duskmane:BAAALgAECgMJBQAAAA==.',
Dw='Dwadler:BAABLgAECn8aAAIQAAYJrBzyEACJAQAQAAYJrBzyEACJAQAAAA==.',
Dy='Dyrkonian:BAAALgAECgQJBwAAAA==.',
Ei='Eireann:BAAALgADCgcJCQAAAA==.',
El='Elerrak:BAAALgAECgEJAQABLgAFFAYJGAAYABIdAA==.Elindalia:BAAALgAECgMJAwAAAA==.',
Em='Emberash:BAAALgAECgEJAQAAAA==.Embre:BAAALgAFFAMJBAAAAA==.Emorri:BAAALgAECgYJBgAAAA==.Empyrea:BAAALgAECgQJBQAAAA==.',
Er='Eraina:BAAALgADCgIJAgAAAA==.Ericles:BAABLgAECn8ZAAMZAAcJ8R2UDgCpAQAZAAcJ8R2UDgCpAQALAAIJlAVwlwBkAAAAAA==.Erys:BAAALgAECgYJCQAAAA==.Erébus:BAABLgAECn8iAAIaAAkJ7xgMGgA2AgAaAAkJ7xgMGgA2AgAAAA==.',
Ev='Ev:BAAALgAECgQJBAAAAA==.Evergreene:BAAALgADCggJCAABLgAECgIJAgAGAAAAAA==.Evlpotato:BAABLgAECn8kAAQOAAgJ4RclFQDZAQAOAAcJNRolFQDZAQAbAAcJbx32GQCiAQAcAAEJlAdTfwAzAAAAAA==.Evojak:BAAALgAECgYJDgAAAA==.',
Fa='Fabiyo:BAAALgADCgMJAwAAAA==.Faevelia:BAAALgAECgEJAgAAAA==.Fairaday:BAABLgAECn8uAAIFAAkJeAnfSQBqAQAFAAkJeAnfSQBqAQAAAA==.Fanshen:BAAALgAECgMJBQAAAA==.Fauchi:BAAALgADCgEJAQAAAA==.Faxqueenmage:BAABLgAECn8VAAICAAYJdwLXzwCsAAACAAYJdwLXzwCsAAAAAA==.',
Fe='Felador:BAAALgAECgYJBgABLgAECggJHAAPAKEMAA==.Feldo:BAAALgAECgYJCQAAAA==.Felmès:BAAALgADCgYJBgABLgAECggJHAACAJwKAA==.Fennec:BAAALgAECgUJDAAAAA==.Feralarak:BAAALgAECgQJDAABLgAFFAYJGAAYABIdAA==.',
Fi='Firebrandd:BAACLgAFFH8cAAMUAAYJzxztAACHAQAUAAUJnyDtAACHAQAdAAUJZhGGDgCAAQAuAAQKfzoAAxQACAk2JmACAA8DABQACAksImACAA8DAB0ACAnPJCEJAIUCAAAA.Fizehbubbleh:BAEALgADCgYJBgABLgAECggJIAAMAOcaAA==.Fizehtotems:BAEBLgAECn8gAAMMAAgJ5xq3HQCeAQAMAAgJ5xq3HQCeAQANAAUJixZGQQBGAQAAAA==.',
Fl='Fleshoracle:BAAALgAECgQJBAABLgAECgQJBQAGAAAAAA==.Fluctuates:BAAALgAECgQJCAAAAA==.',
Fo='Foragarn:BAAALgAECgUJBQAAAA==.Foron:BAAALgAECgIJAgAAAA==.',
Fr='Frankkastle:BAAALgAECgYJDwAAAA==.Frazelia:BAAALgADCgkJDgABLgAECgYJFQAIAD8QAA==.Fribble:BAAALgAECgcJDwABLgAECggJHQAKAJ8GAA==.Froggierlynx:BAAALgAFFAQJBAAAAA==.Froznfate:BAABLgAECn8kAAIKAAgJlCXOAQDiAgAKAAgJlCXOAQDiAgAAAA==.Fryes:BAAALgAECgkJDAAAAA==.',
Fu='Fuzziebutt:BAAALgADCgMJBAAAAA==.',
Fw='Fwibble:BAAALgAECgYJCgABLgAECggJHQAKAJ8GAA==.',
Fy='Fyrelady:BAAALgADCggJDgABLgAECgMJBQAGAAAAAA==.Fyrestone:BAAALgAECgMJBQAAAA==.',
['Fæ']='Fæder:BAAALgADCgYJBgAAAA==.',
Ga='Gabarnak:BAAALgADCgIJAgABLgAECgYJEwAGAAAAAA==.Galencharred:BAABLgAECn8XAAIRAAYJ/QhPoADqAAARAAYJ/QhPoADqAAAAAA==.Garagon:BAABLgAECn8lAAIeAAgJiBarCQAAAgAeAAgJiBarCQAAAgAAAA==.Gauss:BAABLgAECn8dAAIKAAgJnwYFHADfAAAKAAgJnwYFHADfAAAAAA==.Gaîîa:BAABLgAECn8cAAIFAAgJCBq2MADtAQAFAAgJCBq2MADtAQAAAA==.',
Ge='Gerva:BAABLgAECn8iAAITAAgJ1A7xVAB9AQATAAgJ1A7xVAB9AQAAAA==.',
Gh='Ghlain:BAAALgAECgQJBQAAAA==.Ghorfindor:BAABLgAECn8WAAIfAAcJjwO+KwC9AAAfAAcJjwO+KwC9AAAAAA==.Ghostlybrew:BAACLgAFFH8UAAIDAAYJbBrmBACHAQADAAYJbBrmBACHAQAuAAQKfxYAAgMACAmpH94TAHECAAMACAmpH94TAHECAAAA.',
Gi='Gigastorm:BAAALgADCgIJAQAAAA==.Gilas:BAABLgAECn8YAAQWAAYJcBAvIwDjAAAWAAYJcBAvIwDjAAAVAAUJWgUHFwCSAAATAAEJjwTHKwEjAAAAAA==.',
Gl='Glaivemstake:BAAALgADCgcJBwAAAA==.',
Gn='Gnik:BAAALgAECggJDgAAAA==.',
Gr='Graahak:BAAALgADCgMJAwAAAA==.Graveborn:BAAALgAECgQJBQAAAA==.Graydenton:BAAALgAECgkJCQABLgAECggJBgAGAAAAAA==.Greenfelpowa:BAAALgAECgkJEAAAAA==.Gruuven:BAAALgADCgUJBwAAAA==.',
Gu='Gutmtmon:BAABLgAECn8VAAIBAAYJCAjSNwDSAAABAAYJCAjSNwDSAAAAAA==.',
Gw='Gwenivive:BAABLgAECn8gAAIFAAgJdRcGJQD9AQAFAAgJdRcGJQD9AQAAAA==.',
['Gí']='Gízmo:BAAALgADCgUJBQAAAA==.',
Ha='Haenus:BAABLgAECn8dAAIaAAgJ8hObWQApAQAaAAgJ8hObWQApAQAAAA==.Hamor:BAAALgAECgkJCgAAAA==.Harrynear:BAAALgADCgMJAwABLgAECgYJEAAGAAAAAA==.Haunt:BAAALgAECgUJBgAAAA==.Havark:BAAALgAECgMJAwAAAA==.',
He='Healbilly:BAAALgADCgEJAQAAAA==.Healingdeath:BAAALgADCgMJBAAAAA==.Hecatombe:BAAALgADCgUJBQAAAA==.Hellzdruid:BAAALgADCgQJBAAAAA==.Hellzknîght:BAABLgAECn8aAAITAAYJCRKbiQAHAQATAAYJCRKbiQAHAQAAAA==.',
Ho='Holek:BAAALgAECgYJDwAAAA==.Holgo:BAABLgAECn8bAAIQAAkJHyX3AABFAwAQAAkJHyX3AABFAwAAAA==.Holgy:BAACLgAFFH8ZAAIgAAYJJSAWAQDxAQAgAAYJJSAWAQDxAQAuAAQKfyQAAiAACQlWI0wBAEkDACAACQlWI0wBAEkDAAAA.Holybeard:BAABLgAECn8uAAIRAAgJvR4PGABzAgARAAgJvR4PGABzAgAAAA==.Hooks:BAAALgADCggJEgAAAA==.',
Hu='Hunterturtle:BAAALgADCgUJBQAAAA==.',
Ic='Icia:BAAALgAECgEJAQAAAA==.',
Id='Idontmiss:BAAALgAECgIJCAAAAA==.',
Il='Ilickboody:BAAALgADCgQJBAAAAA==.Illustra:BAAALgAECgcJEQABLgAECggJHAACAJwKAA==.',
Im='Imcaldo:BAAALgADCgYJBgAAAA==.Imcaldoo:BAAALgADCgUJCgAAAA==.',
In='Interrupt:BAAALgAECgUJDQAAAA==.',
Ir='Irox:BAAALgADCgMJAwAAAA==.',
Is='Isaic:BAAALgADCgIJAgAAAA==.Iseila:BAABLgAECn8YAAICAAkJ+A0jTQCxAQACAAkJ+A0jTQCxAQAAAA==.Isevio:BAAALgAECgMJBwAAAA==.',
It='Ithorus:BAAALgAECgUJCwAAAA==.',
Ja='Jaadb:BAAALgAECgMJAwAAAA==.Jaadd:BAAALgAECgIJAgAAAA==.Jaadi:BAAALgAECgIJAwAAAA==.Jaata:BAAALgADCgcJEAAAAA==.Jamien:BAABLgAECn8qAAMRAAgJLx89HABaAgARAAgJLx89HABaAgAJAAUJHQEsdwCdAAAAAA==.Jasnah:BAAALgAECgYJCwAAAA==.Jasnos:BAAALgAECgUJDAAAAA==.',
Jd='Jdk:BAAALgAECgUJBwAAAA==.',
Je='Jelf:BAAALgAECgQJBAAAAA==.Jenzing:BAABLgAECn8VAAMPAAgJqh0QKwBjAgAPAAcJqh0QKwBjAgAhAAEJAACuIwBjAAAAAA==.Jessemyn:BAAALgAECgUJBQAAAA==.',
Jh='Jholy:BAAALgADCggJCAAAAA==.',
Jo='Jobokenhones:BAABLgAECn8oAAIaAAkJHxrLFgBNAgAaAAkJHxrLFgBNAgAAAA==.Johadgan:BAAALgADCgEJAQAAAA==.',
Jp='Jproudmore:BAAALgADCgUJBQABLgADCgYJCwAGAAAAAA==.',
Js='Jsberg:BAABLgAECn8YAAILAAgJwRUxHwCmAQALAAgJwRUxHwCmAQAAAA==.',
Ka='Kaathe:BAABLgAECn8lAAMCAAYJGx7ihADHAQACAAYJGx7ihADHAQAiAAEJjhqXDwA4AAAAAA==.Kaboomalis:BAAALgADCgUJBQAAAA==.Kadance:BAAALgAECgYJDwAAAA==.Kaidiis:BAABLgAECn8hAAIRAAgJoA3WZgBWAQARAAgJoA3WZgBWAQAAAA==.Kaido:BAAALgAECgEJAQAAAA==.Kalder:BAAALgADCgcJBwAAAA==.Karbonn:BAAALgAECgYJDwAAAA==.Kay:BAAALgAECgcJBwAAAA==.Kazeraz:BAAALgADCgEJAQAAAA==.',
Ke='Kegbreaker:BAABLgAECn8uAAIcAAkJXgkvIQByAQAcAAkJXgkvIQByAQAAAA==.',
Kh='Khanas:BAAALgAECgYJDwAAAA==.Kheru:BAAALgADCgkJDgAAAA==.Khoan:BAAALgAECgYJCgAAAA==.',
Ki='Kimbustible:BAABLgAECn85AAICAAkJNySiBgAlAwACAAkJNySiBgAlAwAAAA==.Kimchi:BAAALgAECgcJDAABLgAECgkJOQACADckAA==.',
Kn='Knockknocko:BAAALgAECgcJDQAAAA==.',
Ko='Kobir:BAAALgADCgEJAQAAAA==.Komodostyle:BAABLgAECn8kAAQeAAgJ+Al9FQAnAQAeAAcJgAl9FQAnAQAUAAIJWw64NQBoAAAdAAEJaRBGawA4AAAAAA==.Koobideh:BAAALgADCgEJAQAAAA==.',
Kr='Kriddler:BAAALgADCgQJBAAAAA==.Krisarugala:BAABLgAECn8VAAIXAAcJgg1DMAACAQAXAAcJgg1DMAACAQAAAA==.',
Ku='Kujoluvsmilf:BAAALgAECgcJCAAAAA==.Kunuku:BAAALgADCgUJBQAAAA==.Kurash:BAAALgADCgcJBwAAAA==.Kurion:BAAALgAECgkJBAAAAA==.Kurogami:BAAALgADCggJDQAAAA==.',
Ky='Kylesxmom:BAACLgAFFH8IAAMTAAQJ3AvaUgALAQATAAQJ3AvaUgALAQAWAAEJuA20JwA2AAAuAAQKf0cAAxMACQm5IUoIAPwCABMACQmKIUoIAPwCABYACAliHH8RAJ4BAAAA.Kymal:BAABLgAECn81AAIaAAkJzBXZJADzAQAaAAkJzBXZJADzAQAAAA==.Kymbria:BAAALgADCgUJCAAAAA==.Kymora:BAAALgADCgcJBwAAAA==.Kyndrissa:BAAALgADCgUJBQAAAA==.',
['Kë']='Këy:BAACLgAFFH8IAAITAAMJ6RD3YgDuAAATAAMJ6RD3YgDuAAAuAAQKfykAAhMACAnUHYwsAIYCABMACAnUHYwsAIYCAAAA.',
La='Latrice:BAACLgAFFH8aAAICAAcJsBi6CQASAgACAAcJsBi6CQASAgAuAAQKfygABAIACQk5I9wJAHYDAAIACQk5I9wJAHYDACIAAwm4GWwGAOUAACMAAQltGN0YAFEAAAAA.Lavynder:BAABLgAECn8XAAIaAAgJ5hUVWgCTAQAaAAgJ5hUVWgCTAQAAAA==.Lazerturkey:BAAALgAECggJCAAAAA==.Laërtes:BAAALgAECgUJCAAAAA==.',
Le='Leiamirage:BAAALgAECgUJCwAAAA==.Leviscus:BAAALgAECgMJBQAAAA==.',
Li='Lifetap:BAAALgADCgMJAwAAAA==.Lightbill:BAAALgAECggJCAABLgAECgkJJgAHAModAA==.Lightbàne:BAABLgAECn8aAAIIAAgJtx5CBABuAgAIAAgJtx5CBABuAgAAAA==.Lightningrod:BAAALgAECgYJBwAAAA==.Lightshaolin:BAAALgAECgQJBAAAAA==.Lildruidz:BAABLgAECn8YAAMHAAcJAhNaMwCHAQAHAAcJAhNaMwCHAQAXAAEJLQIZegAZAAAAAA==.Lillivarak:BAABLgAECn8UAAIRAAcJFgfOmAD3AAARAAcJFgfOmAD3AAAAAA==.Lilzdrlockz:BAAALgAECgEJAQAAAA==.Lithedra:BAAALgADCgcJDwAAAA==.',
Lu='Lucavi:BAAALgAECgMJAwAAAA==.Luke:BAAALgADCgUJBwAAAA==.Luma:BAAALgAECgMJBQAAAA==.Luther:BAABLgAECn8XAAIDAAkJNw9XJQDYAQADAAkJNw9XJQDYAQAAAA==.',
Ly='Lyla:BAAALgADCgQJBgAAAA==.',
Ma='Magnux:BAAALgAECgEJAgAAAA==.Malazark:BAAALgADCgYJBgAAAA==.Malríus:BAAALgAECgQJEQAAAA==.Manales:BAAALgAECgcJBgAAAA==.Marhukai:BAABLgAECn8nAAIRAAkJXB0rFQCGAgARAAkJXB0rFQCGAgAAAA==.Marotal:BAABLgAECn8dAAICAAYJexc6cQBYAQACAAYJexc6cQBYAQAAAA==.Martysparty:BAABLgAECn8eAAIKAAgJUh2ACAD1AQAKAAgJUh2ACAD1AQAAAA==.Mavaena:BAAALgAECgQJBwAAAA==.Mavrane:BAAALgADCgEJAgAAAA==.',
Me='Meashakegs:BAAALgAECggJEQAAAA==.Mechaboomer:BAABLgAECn8kAAIFAAgJXhoaKADuAQAFAAgJXhoaKADuAQAAAA==.Megafire:BAAALgADCggJDQAAAA==.Melcanthet:BAAALgADCggJCAAAAA==.Mellowrock:BAAALgAECgUJBgABLgAECgYJBQAGAAAAAA==.',
Mi='Mickhaggis:BAAALgADCgIJAgAAAA==.Micktarogar:BAAALgAECgcJEwAAAA==.Mickwutang:BAAALgAFFAEJAQAAAA==.Miklaga:BAAALgAECgEJAgAAAA==.Milince:BAAALgADCgMJAgAAAA==.Minikloon:BAAALgAECgYJDgAAAA==.Minphoria:BAAALgADCgQJBgAAAA==.Missylock:BAAALgADCgYJBgAAAA==.Mistilinn:BAABLgAECn8hAAIkAAkJgAUjEAAPAQAkAAkJgAUjEAAPAQAAAA==.Miyri:BAAALgAECgEJAQABLgAFFAIJAgAGAAAAAA==.',
Mo='Mollyporph:BAAALgAECgEJAQAAAA==.Monoco:BAAALgAECgYJEwAAAA==.Moopandax:BAACLgAFFH8QAAIXAAQJEB7jCQB5AQAXAAQJEB7jCQB5AQAuAAQKfzQAAxcACQmbIkkDAP8CABcACQl0IkkDAP8CACAACAmhH38EAHgCAAEuAAUUBQkQABcASBkA.Mortrum:BAAALgADCgQJBAAAAA==.Moxestime:BAAALgAECgEJAgAAAA==.Moxsdeath:BAAALgADCgEJAQAAAA==.Moxsdeaths:BAAALgADCgcJBwAAAA==.',
Mu='Mushaboom:BAAALgAECgYJDwAAAA==.Muzzler:BAABLgAECn83AAICAAgJSB/2IgBTAgACAAgJSB/2IgBTAgAAAA==.',
My='Myeyes:BAAALgAECgEJAgAAAA==.Mylinkah:BAAALgADCgQJBAAAAA==.Mynamefizz:BAEALgAECgkJEgABLgAECggJIAAMAOcaAA==.Myotonic:BAAALgADCgQJBAAAAA==.Mythlok:BAAALgAECgMJAwAAAA==.Mythreiel:BAAALgAECgUJBgAAAA==.Mythykal:BAAALgAECgIJAgAAAA==.',
['Mé']='Méasha:BAAALgAECgYJBgAAAA==.',
Na='Nachtmar:BAAALgAECgQJBAABLgAECggJEQAGAAAAAA==.Nadis:BAEALgAECgIJAwAAAA==.Narcessa:BAAALgADCgQJBAAAAA==.Nawk:BAAALgAECgEJAQAAAA==.',
Ne='Nennerb:BAAALgADCgQJBAAAAA==.',
Ni='Nicola:BAAALgAECgQJBwAAAA==.Nightxwish:BAABLgAECn8XAAIOAAYJ2RV8HACPAQAOAAYJ2RV8HACPAQAAAA==.Niranye:BAAALgADCgEJAQAAAA==.',
No='Noisemarine:BAABLgAFFH8FAAIQAAMJDxKiEgDDAAAQAAMJDxKiEgDDAAAAAA==.Nokk:BAAALgADCgEJAQAAAA==.Nokkco:BAAALgAECgEJAgAAAA==.Norellia:BAAALgAECgEJAQAAAA==.Northleo:BAAALgADCgcJCwAAAA==.Northspirit:BAAALgAECgUJDwAAAA==.',
Nu='Nuit:BAAALgADCgUJBQABLgAECgYJCwAGAAAAAA==.',
Ny='Nyarlothep:BAAALgADCgkJJgAAAA==.Nyx:BAAALgADCgUJBQABLgAECggJKgARAC8fAA==.',
Oa='Oakenshièld:BAAALgAECgQJBQAAAA==.',
Od='Odindh:BAAALgAECgYJEgAAAA==.Odins:BAAALgAECgMJAwABLgAECgYJEgAGAAAAAA==.',
Oh='Ohwhelp:BAABLgAFFH8FAAIdAAMJXxUAJQDyAAAdAAMJXxUAJQDyAAABLgAFFAYJHQAXADwmAA==.Ohyikers:BAACLgAFFH8dAAIXAAYJPCbFAQAzAgAXAAYJPCbFAQAzAgAuAAQKfy8AAhcACAkCJiwGADYDABcACAkCJiwGADYDAAAA.',
Ok='Oken:BAAALgADCgUJBQAAAA==.',
Om='Om:BAAALgADCgcJCQAAAA==.',
Or='Orklock:BAAALgADCgMJAwAAAA==.',
Pa='Pallek:BAAALgADCggJCgABLgAECgYJDwAGAAAAAA==.Palli:BAABLgAECn8dAAIJAAcJ+BU7IgCnAQAJAAcJ+BU7IgCnAQAAAA==.Paogao:BAAALgAECgIJAwAAAA==.Parry:BAAALgADCgQJBAAAAA==.Pasghetti:BAAALgADCgMJAwAAAA==.Pasta:BAABLgAECn8iAAIlAAcJgRt9GwAlAgAlAAcJgRt9GwAlAgAAAA==.',
Pe='Pewpewbite:BAAALgAECgYJCQAAAA==.',
Ph='Phantomarrow:BAACLgAFFH8RAAQmAAUJdBHRDQAvAQAmAAQJGAzRDQAvAQAkAAUJHQtbEgDGAAAFAAEJzAG4aQA7AAAuAAQKfxUABAUABgk8IAZOAH8BAAUABgkbHgZOAH8BACQABQmzGbBCAE0BACYAAQkAAKhSAAAAAAAA.Phatcow:BAABLgAECn8qAAMNAAkJCht7FwBaAgANAAgJ4hl7FwBaAgAYAAkJQxSOBgAPAgAAAA==.Phoseidon:BAAALgADCgcJCQAAAA==.Phude:BAACLgAFFH8GAAIRAAIJxQw9XQCYAAARAAIJxQw9XQCYAAAuAAQKfzsAAhEACAk7GuQrAAkCABEACAk7GuQrAAkCAAAA.',
Pi='Pinch:BAAALgAECgMJAwAAAA==.',
Po='Pohl:BAAALgAECgYJCwAAAA==.Pokimana:BAAALgADCgEJAQAAAA==.Poohynok:BAABLgAECn82AAICAAkJwyREBQA4AwACAAkJwyREBQA4AwAAAA==.',
Pu='Pukefeast:BAAALgAECgYJDAAAAA==.',
Py='Pyramys:BAACLgAFFH8TAAIlAAUJLB8cCgBqAQAlAAUJLB8cCgBqAQAuAAQKfyEAAiUACAm4IAIRAJkCACUACAm4IAIRAJkCAAAA.',
['Pè']='Pèrce:BAAALgAECgYJCQAAAA==.',
Qu='Quepaoka:BAAALgADCgIJAgAAAA==.',
Ra='Raklem:BAAALgAECgMJAwABLgAECgYJCgAGAAAAAA==.Ramble:BAAALgADCgQJBAABLgAECgQJBgAGAAAAAA==.Ramstein:BAAALgAECgMJAwAAAA==.Raphînîty:BAAALgADCgMJBQAAAA==.Rashari:BAAALgADCgYJCAAAAA==.Rawhawk:BAAALgAECgUJCAABLgAECgYJEAAGAAAAAA==.Razgrizz:BAAALgAECgMJBQAAAA==.',
Re='Retro:BAAALgAECgIJBAAAAA==.Revelatus:BAAALgAECgQJBgAAAA==.Reythanas:BAAALgAECgQJBwAAAA==.Rezzin:BAAALgAECgEJAQAAAA==.',
Ri='Rileyann:BAABLgAECn8cAAMcAAgJrwigJwA/AQAcAAgJrwigJwA/AQAbAAYJAwNMRADaAAAAAA==.',
Ro='Roozer:BAAALgAECgMJBAAAAA==.',
['Rå']='Råphå:BAAALgAECgMJBAAAAA==.',
Sa='Saelyria:BAAALgAFFAIJAgAAAA==.Saga:BAAALgADCgUJBQABLgAECgkJMQAKACcSAA==.Sagethepally:BAAALgAECgcJAwAAAA==.Saintfail:BAAALgAECgcJEwABLgAECgcJIAASACogAA==.Sainthymn:BAAALgAECgcJDQABLgAECgcJIAASACogAA==.Saintmist:BAABLgAECn8gAAISAAcJKiBRCwCBAgASAAcJKiBRCwCBAgAAAA==.Salero:BAAALgADCgIJAQAAAA==.Sandiera:BAABLgAECn8cAAMCAAgJnAqIfABBAQACAAgJnAqIfABBAQAjAAMJPAOoFwBcAAAAAA==.Saxtön:BAAALgADCggJEwAAAA==.',
Sc='Scoreboard:BAACLgAFFH8YAAInAAYJix9YAAD8AQAnAAYJix9YAAD8AQAuAAQKfyEAAycACQkgJg0AAOsDACcACQkgJg0AAOsDACUAAQnwFJhaAE8AAAAA.Scorn:BAAALgAECgYJDgAAAA==.Scottx:BAAALgAFFAIJAwAAAA==.',
Se='Sebas:BAAALgAECgEJAQAAAA==.Sedric:BAAALgAECgYJCAAAAA==.Selkz:BAAALgAECgcJDQAAAA==.Selsonblue:BAAALgAECgMJAwAAAA==.Sesskaa:BAAALgAECgYJCgAAAA==.',
Sh='Shadowcursed:BAAALgADCgcJCgAAAA==.Shadowstorm:BAAALgADCgQJBAAAAA==.Shadøws:BAAALgAECgEJAQAAAA==.Shakenhealz:BAAALgADCgYJBgAAAA==.Shathos:BAAALgADCgEJAQAAAA==.Sheebá:BAAALgADCgYJCwAAAA==.Shishkbob:BAAALgADCgkJCQAAAA==.Shivax:BAAALgAECgYJDgAAAA==.Shünúkh:BAAALgADCgYJBgAAAA==.',
Si='Sigewulf:BAAALgAECgIJAwABLgAECgcJHAADACQGAA==.Signal:BAAALgAECgEJAQAAAA==.Singbow:BAAALgADCgYJBgABLgAECggJHgAHAKkNAA==.Sinogad:BAABLgAECn8YAAMXAAgJlBE1HgB8AQAXAAgJlBE1HgB8AQAHAAUJ4xNBRAA2AQAAAA==.Sinol:BAAALgAECgYJDwABLgAECggJGAAXAJQRAA==.Sioux:BAAALgADCgEJAQAAAA==.Sixosix:BAAALgADCgIJAgAAAA==.',
Sk='Skaro:BAAALgAECgYJDwAAAA==.Skyborn:BAAALgAECgYJDwAAAA==.',
Sl='Slamahoochee:BAAALgAECgYJCQAAAA==.Slay:BAACLgAFFH8JAAIXAAMJpRnhGgD4AAAXAAMJpRnhGgD4AAAuAAQKfyoABBcACAmPIbUJAG8CABcACAmPIbUJAG8CAAgABglkG48TAHgBAAcAAQk/AzrHAB0AAAAA.',
Sm='Smokedademon:BAAALgAECgMJCQAAAA==.Smokiebear:BAAALgAECgQJBwAAAA==.Smunkie:BAABLgAECn8fAAIDAAcJyibDBgCXAgADAAcJyibDBgCXAgAAAA==.',
Sn='Snickeers:BAAALgAECgEJAQAAAA==.',
So='Somapeace:BAAALgAECgEJAgAAAA==.Somogyi:BAAALgADCgIJAgAAAA==.',
Sp='Spopovich:BAAALgADCggJCAABLgAECgMJAwAGAAAAAA==.Sprints:BAAALgAECgQJBAAAAA==.',
St='Stinko:BAAALgADCgEJAgAAAA==.Stitchlock:BAAALgAECgIJAgAAAA==.Stitchofevil:BAABLgAECn8WAAQhAAcJuBoEBgACAgAhAAYJUB8EBgACAgAPAAQJpAlcxgBvAAAEAAIJtQ8hYQBMAAAAAA==.Stonedshaman:BAAALgADCgYJBgABLgAECgIJAgAGAAAAAA==.Stormhands:BAAALgAECgYJDwAAAA==.Stormhugger:BAAALgAFFAEJAQAAAA==.Stoutnholy:BAAALgAECgYJDgAAAA==.Stratichnut:BAABLgAECn8eAAIHAAgJqQ1fOQBoAQAHAAgJqQ1fOQBoAQAAAA==.Stromar:BAAALgADCgcJEgAAAA==.Stwampadin:BAABLgAECn8hAAIJAAkJyyGGAQB4AwAJAAkJyyGGAQB4AwAAAA==.Stwevoker:BAAALgAECgMJAwABLgAECgkJIQAJAMshAA==.Stwonkfu:BAAALgAECggJCAABLgAECgkJIQAJAMshAA==.',
Su='Sumire:BAAALgADCggJDgABLgAECgYJCgAGAAAAAA==.',
Sv='Sveny:BAAALgAECgEJAQAAAA==.',
Sw='Swampert:BAACLgAFFH8OAAILAAQJCBUWFwAgAQALAAQJCBUWFwAgAQAuAAQKfx8AAgsACQnRH+gMAO8CAAsACQnRH+gMAO8CAAAA.Swamperting:BAAALgAECgcJEQABLgAFFAQJDgALAAgVAA==.Swaye:BAABLgAECn8mAAIbAAkJWBKNFgDDAQAbAAkJWBKNFgDDAQAAAA==.Sweetfox:BAAALgAECgQJBAAAAA==.Swimchick:BAAALgAECgUJBQAAAA==.Switched:BAAALgADCgcJBwABLgAECgcJHwADAMomAA==.Swizzle:BAAALgAECgQJBAAAAA==.',
Sy='Syllvanas:BAAALgAECgYJDgAAAA==.Sythia:BAAALgAECgEJAQABLgAFFAQJCAAPAIkUAA==.',
Ta='Taltost:BAAALgAECgYJEAAAAA==.Tantrik:BAAALgADCgEJAQAAAA==.Tartin:BAAALgAECgMJAwAAAA==.Tarv:BAAALgADCgMJAQAAAA==.Tashamirage:BAAALgAECgMJBAAAAA==.Tauriel:BAAALgAECgUJBwAAAA==.',
Te='Teex:BAAALgADCgYJBwAAAA==.Teksuo:BAACLgAFFH8GAAIBAAIJtBE2HACUAAABAAIJtBE2HACUAAAuAAQKfz4AAgEACAmfHYMNACECAAEACAmfHYMNACECAAAA.Telamontay:BAAALgADCgkJFQAAAA==.Telferas:BAAALgAECgYJEQABLgAFFAYJHAAUAM8cAA==.Tenithon:BAACLgAFFH8GAAIJAAMJah3TGAARAQAJAAMJah3TGAARAQAuAAQKfyoAAgkACQm7IX4FABQDAAkACQm7IX4FABQDAAAA.Tenshenzen:BAAALgAECggJEgAAAA==.',
Th='Therandis:BAAALgADCgUJBQAAAA==.Thetombo:BAAALgAECgMJAwAAAA==.Thierry:BAAALgADCgUJBQAAAA==.Thierrye:BAABLgAECn8VAAIaAAYJlhtmTQC/AQAaAAYJlhtmTQC/AQAAAA==.Tholaren:BAABLgAECn8jAAMFAAgJ6xEJOwCdAQAFAAgJ6xEJOwCdAQAkAAUJVQeGGwCUAAAAAA==.Threed:BAAALgAECgYJCwAAAA==.Threewar:BAAALgAECgIJAgABLgAECgYJCwAGAAAAAA==.Thrissa:BAAALgAECgYJDwAAAA==.',
To='Torrque:BAAALgADCgkJCQABLgADCgYJCwAGAAAAAA==.Totemlicker:BAAALgAECgEJAQAAAA==.',
Tr='Trandeath:BAAALgAECgQJBAAAAA==.Trangon:BAABLgAECn8fAAIRAAkJDApYVgB+AQARAAkJDApYVgB+AQAAAA==.Traveler:BAAALgADCgEJAQAAAA==.Traygon:BAAALgAECgYJBgAAAA==.Trillion:BAAALgADCggJCAAAAA==.',
Tu='Tunzoffun:BAAALgAECgIJAwAAAA==.',
Un='Underbyte:BAAALgADCggJDwAAAA==.Unknownname:BAAALgADCgMJAwAAAA==.',
Ur='Urholiness:BAAALgADCgkJDwAAAA==.',
Va='Vaeleia:BAAALgAECgQJBgAAAA==.Vahnkar:BAAALgADCgYJCQAAAA==.Valentinu:BAAALgADCgcJDwAAAA==.Valkyrie:BAAALgAECgEJAgAAAA==.Vaneshk:BAAALgADCgEJAQAAAA==.Varchemical:BAAALgAECgcJBwAAAA==.Varithal:BAACLgAFFH8GAAIeAAIJ+RkfGQCiAAAeAAIJ+RkfGQCiAAAuAAQKfzUAAh4ACAnzH9oEAI8CAB4ACAnzH9oEAI8CAAEuAAEKBgkJAAYAAAAA.Varri:BAAALgAECgMJBQAAAA==.Vastectomy:BAAALgAECggJCgAAAA==.',
Ve='Vegasana:BAAALgADCgYJEQAAAA==.Velwing:BAAALgAECgUJBwAAAA==.Venawyn:BAABLgAECn8ZAAIFAAYJ4w1taQATAQAFAAYJ4w1taQATAQAAAA==.Verakhaa:BAAALgAECgQJBAAAAA==.',
Vi='Vibepriest:BAAALgADCgEJAQAAAA==.Vindfaramaðr:BAABLgAECn8cAAIDAAcJJAZ/PQDKAAADAAcJJAZ/PQDKAAAAAA==.Vixin:BAAALgAECgYJDAAAAA==.',
Vo='Voidsaack:BAAALgAECgMJAwAAAA==.Voidz:BAAALgAECgEJAQAAAA==.Volfguar:BAAALgAECgQJAQAAAA==.Vortan:BAAALgAECgcJEwAAAA==.',
Vr='Vreya:BAAALgADCgkJFQABLgAECgMJBQAGAAAAAA==.',
Vy='Vynthus:BAAALgAECgQJCAAAAA==.',
['Vä']='Värys:BAAALgAECgEJAQAAAA==.',
Wa='Wan:BAAALgADCgEJAQAAAA==.Warhundin:BAEALgAECgUJBQABLgAFFAIJBgARAJwEAA==.Warwan:BAAALgADCgIJAgAAAA==.Wazzdh:BAAALgADCgQJBAAAAA==.Wazzdot:BAAALgAECgQJBAAAAA==.Wazzhunnah:BAABLgAECn8kAAMmAAgJ3xHOFQCrAQAmAAgJ3xHOFQCrAQAkAAQJZAlhZQCqAAAAAA==.',
We='Werg:BAAALgAECggJCgABLgAFFAEJAQAGAAAAAA==.',
Wh='Whatmyname:BAABLgAECn8pAAIgAAgJ2wq2GwDuAAAgAAgJ2wq2GwDuAAAAAA==.Whispp:BAAALgAECgYJCAAAAA==.',
Wo='Wonsok:BAAALgAECgcJDgAAAA==.',
Wy='Wyvoker:BAABLgAECn8cAAIeAAgJ/xb6CQD6AQAeAAgJ/xb6CQD6AQABLgAECgkJDwAGAAAAAA==.',
['Wì']='Wìllow:BAAALgADCgIJAgAAAA==.',
['Wÿ']='Wÿm:BAAALgAECgkJDwAAAA==.',
Xa='Xaoleth:BAAALgADCgEJAQAAAA==.',
Xe='Xenorion:BAAALgAECgMJAwAAAA==.Xephora:BAAALgAECgEJBQAAAA==.',
Xi='Xiq:BAAALgADCgUJBQAAAA==.',
Xr='Xrinch:BAAALgADCgYJBgAAAA==.',
Xu='Xunadin:BAAALgADCggJEAAAAA==.Xuny:BAAALgAECgQJCwAAAA==.',
Yo='Yordi:BAAALgAECgUJDQAAAA==.',
Yu='Yuzuriha:BAACLgAFFH8GAAIFAAIJEh7lQQC3AAAFAAIJEh7lQQC3AAAuAAQKfzUAAgUACAk/JBgIAA8DAAUACAk/JBgIAA8DAAAA.',
Za='Zaelia:BAAALgADCgYJBgABLgAECggJKgARAC8fAA==.Zamaze:BAABLgAECn8lAAMQAAkJDiCLBACaAgAQAAkJDiCLBACaAgAZAAEJLwkpVQApAAAAAA==.Zannah:BAAALgAECgMJAwAAAA==.Zant:BAAALgAECgIJAQAAAA==.',
Ze='Zeekielle:BAEBLgAECn8qAAIfAAgJdhPuEgCZAQAfAAgJdhPuEgCZAQABLgAFFAIJBgARAJwEAA==.Zenius:BAAALgAECgYJCgAAAA==.Zerithrielle:BAABLgAECn8pAAIfAAgJ2BaTEgCfAQAfAAgJ2BaTEgCfAQAAAA==.',
Zi='Zippii:BAAALgAECgYJBwAAAA==.Zipy:BAABLgAECn8lAAIcAAgJVx7mBgDAAgAcAAgJVx7mBgDAAgAAAA==.',
Zo='Zof:BAAALgAECgYJDgAAAA==.Zorathar:BAAALgADCgYJBgAAAA==.',
Zu='Zugtag:BAABLgAECn8uAAITAAkJwh6nEACpAgATAAkJwh6nEACpAgAAAA==.',
Zy='Zyllo:BAAALgAECgMJBAAAAA==.',
['Zá']='Závier:BAAALgAECgUJDAAAAA==.',
['Zõ']='Zõf:BAAALgAECgEJAgABLgAECgYJDgAGAAAAAA==.',
['Äe']='Äemond:BAAALgADCgMJAwAAAA==.',
['Ål']='Ålïce:BAABLgAECn86AAIRAAgJJhryKwAIAgARAAgJJhryKwAIAgAAAA==.',
['Ëd']='Ëdward:BAAALgADCgcJCgABLgAECgUJCAAGAAAAAA==.',
['Ôh']='Ôhmyn:BAAALgADCgMJAwABLgAECgYJEQAGAAAAAA==.',
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
