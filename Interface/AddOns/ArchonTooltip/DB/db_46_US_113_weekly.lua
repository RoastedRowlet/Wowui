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

local lookup = {'Shaman-Elemental','Shaman-Restoration','Monk-Windwalker','Mage-Frost','Monk-Brewmaster','DeathKnight-Blood','Warlock-Destruction','Hunter-BeastMastery','Unknown-Unknown','DeathKnight-Unholy','DeathKnight-Frost','Druid-Restoration','Druid-Feral','Druid-Balance','Paladin-Holy','Paladin-Protection','Warrior-Fury','Paladin-Retribution','Priest-Shadow','Warlock-Demonology','Warrior-Protection','Monk-Mistweaver','Warrior-Arms','Shaman-Enhancement','Evoker-Devastation','DemonHunter-Devourer','Priest-Discipline','Priest-Holy','Evoker-Augmentation','Evoker-Preservation','DemonHunter-Havoc','DemonHunter-Vengeance','Hunter-Survival','Druid-Guardian','Warlock-Affliction','Mage-Fire','Mage-Arcane','Hunter-Marksmanship','Rogue-Subtlety','Rogue-Outlaw',}
local provider = {region='US',realm='GrizzlyHills',name='US',type='weekly',zone=46,date='2026-06-06',data={Ab='Abramz:BAAALgADCgMJAwAAAA==.',
Ad='Addly:BAAALgAECgMJAwAAAA==.Adely:BAAALgAECgEJAQAAAA==.Adelymon:BAABLgAECn8ZAAMBAAkJlRenFAA2AgABAAkJlRenFAA2AgACAAUJARAJfwDSAAAAAA==.Adelymonk:BAAALgAFFAIJAgAAAA==.Adonysroth:BAAALgAECgIJAgAAAA==.Adrahil:BAAALgADCgIJAgAAAA==.',
Ae='Aeonra:BAAALgADCgIJAgAAAA==.',
Ag='Agronak:BAAALgAECgQJBgAAAA==.',
Al='Aldan:BAAALgADCgMJAwAAAA==.Aldazen:BAACLgAFFH8QAAIDAAMJnSNNEAAxAQADAAMJnSNNEAAxAQAuAAQKfzoAAgMACQkeJOcCADEDAAMACQkeJOcCADEDAAAA.Alenara:BAAALgAECgYJDwABLgAECggJHgAEABsLAA==.Aletheìa:BAAALgAECgEJAQAAAA==.Alovan:BAAALgADCgEJAQABLgAECgcJHgAFANoKAA==.Alterbeast:BAAALgAECgUJBQABLgAFFAYJEAAGADoaAA==.Alyssandra:BAABLgAECn8oAAIHAAgJQhmWBQAFAgAHAAgJQhmWBQAFAgAAAA==.',
Am='Amarella:BAABLgAECn8UAAIIAAcJqiCkKQAQAgAIAAcJqiCkKQAQAgAAAA==.Amarrite:BAAALgAECgQJCQAAAA==.Ammalane:BAAALgAECgMJAwABLgAECgQJCQAJAAAAAA==.Amunzo:BAAALgAECgEJAQABLgAECgkJEwAJAAAAAA==.',
An='Angler:BAAALgAECgMJAwAAAA==.Angyrolaj:BAABLgAECn8XAAMKAAcJ0xfSYACfAQAKAAcJgBfSYACfAQALAAIJdBUXEQCFAAAAAA==.',
Aq='Aquadora:BAAALgADCgMJAwAAAA==.',
Ar='Arangarr:BAABLgAECn8xAAMMAAkJpx0zDQDpAgAMAAkJpx0zDQDpAgANAAEJ1BE9SAA5AAAAAA==.Arcin:BAAALgADCgEJAQAAAA==.Areyana:BAABLgAECn8YAAIIAAgJPRCBXQCBAQAIAAgJPRCBXQCBAQAAAA==.Areyoudead:BAAALgAECgQJBAABLgADCgYJCwAJAAAAAA==.Ariolas:BAAALgADCgYJCQAAAA==.Aristoi:BAAALgAECgEJAQAAAA==.Arkand:BAAALgADCgUJBAAAAA==.Arkandra:BAABLgAECn8UAAIOAAYJOhYvMwA/AQAOAAYJOhYvMwA/AQAAAA==.Arkara:BAAALgADCgEJAQAAAA==.Arrietty:BAABLgAECn8gAAIPAAYJxBbvOQBXAQAPAAYJxBbvOQBXAQAAAA==.Arthues:BAABLgAECn8WAAIQAAgJDBw7CQAwAgAQAAgJDBw7CQAwAgAAAA==.Arthâs:BAAALgAECgYJBQAAAA==.Arumathe:BAABLgAECn8XAAIQAAkJxxLnEACpAQAQAAkJxxLnEACpAQAAAA==.',
As='Asura:BAACLgAFFH8TAAIRAAQJWiT6CQCnAQARAAQJWiT6CQCnAQAuAAQKfyAAAhEACQnLItkIAB4DABEACQnLItkIAB4DAAAA.',
Au='Aurelian:BAAALgAECgEJAgAAAA==.',
Az='Az:BAABLgAECn8fAAIRAAcJKyYFDwB9AgARAAcJKyYFDwB9AgAAAA==.Azeriall:BAACLgAFFH8PAAIBAAMJHA4fMQC8AAABAAMJHA4fMQC8AAAuAAQKf0UAAwEACQnUFs4WACECAAEACQnUFs4WACECAAIABAlKAVuGAHsAAAAA.Azerowolf:BAAALgADCggJCAAAAA==.Azráèl:BAAALgADCgMJAwAAAA==.',
Ba='Babyboom:BAAALgAECgEJAQAAAA==.Baconhammr:BAABLgAECn8bAAMSAAgJWQ1ghgBYAQASAAgJWQ1ghgBYAQAPAAUJEgd2eACXAAAAAA==.Badazmf:BAAALgADCgcJDAABLgAECgkJNAATACEbAA==.Badcompany:BAAALgADCgUJBQABLgAECgkJMgAMAJsOAA==.Baddream:BAAALgAECgYJDgAAAA==.Baelmyre:BAAALgADCgUJBQAAAA==.Balenciagosa:BAAALgADCgUJBQABLgAECggJHgAEABsLAA==.Banshiï:BAABLgAECn8wAAIHAAkJhRNbBwDRAQAHAAkJhRNbBwDRAQAAAA==.Baratheøn:BAABLgAECn8uAAIMAAkJ+xYVIQA2AgAMAAkJ+xYVIQA2AgAAAA==.Bax:BAAALgADCgIJAgAAAA==.Baxar:BAAALgAECgIJAgAAAA==.',
Bb='Bbd:BAAALgAECggJCQABLgAECgYJDgAJAAAAAA==.',
Be='Beeftard:BAABLgAECn8YAAIPAAkJWRZiKgDfAQAPAAkJWRZiKgDfAQAAAA==.Bellavix:BAAALgADCgMJBAAAAA==.Benafflic:BAAALgAECgEJAQABLgAECgUJBwAJAAAAAA==.Berserrk:BAAALgADCgYJBgAAAA==.Bershale:BAAALgAECgEJAQABLgAECgYJBwAJAAAAAA==.',
Bi='Bifficus:BAAALgAECgYJDgAAAA==.Big:BAAALgADCgMJBAAAAA==.Biggiecheese:BAAALgAECgMJBAAAAA==.',
Bl='Blackscorn:BAAALgADCgEJAQAAAA==.Blackthôrne:BAAALgAECgUJBQAAAA==.Blucki:BAABLgAECn8fAAIUAAgJ7QnnggAuAQAUAAgJ7QnnggAuAQAAAA==.',
Bo='Bobfu:BAAALgADCgYJCAAAAA==.',
Br='Brieze:BAAALgADCgIJAgAAAA==.Brige:BAAALgAECggJBgAAAA==.Brightstar:BAAALgADCgEJAQAAAA==.Brimaz:BAAALgADCgEJAQAAAA==.',
Bu='Buhhead:BAAALgADCgUJBgAAAA==.Bunana:BAAALgADCgEJAQAAAA==.Bunbear:BAAALgAECgIJAgAAAA==.Bunette:BAAALgADCgEJAQAAAA==.',
Bw='Bwamsamdi:BAAALgADCgYJBgAAAA==.',
By='Byzantium:BAABLgAECn8mAAIVAAgJmwd/JAD/AAAVAAgJmwd/JAD/AAAAAA==.',
['Bô']='Bônebeard:BAAALgAECgEJAQAAAA==.',
Ca='Cabledryer:BAAALgAECgQJEAAAAA==.Caelidpackx:BAAALgADCgYJBwAAAA==.Calamitty:BAAALgAECgMJAwAAAA==.Calistin:BAAALgAECgYJBgAAAA==.Callmedatty:BAAALgAECgEJAQAAAA==.Caluu:BAAALgADCgEJAQAAAA==.Carnry:BAAALgADCgQJBAAAAA==.Catboy:BAABLgAECn8fAAIEAAkJNhbzaQChAQAEAAkJNhbzaQChAQAAAA==.Catnips:BAABLgAECn8cAAISAAgJURjAZwCVAQASAAgJURjAZwCVAQAAAA==.Catpow:BAAALgAECgkJAgAAAA==.',
Ch='Chanaranach:BAAALgAECgYJCgAAAA==.Charitey:BAAALgAECgMJBAAAAA==.Cheelo:BAAALgAECgkJEgAAAA==.Chknnugget:BAAALgAECgMJBQAAAA==.Chromatic:BAABLgAECn8tAAMCAAgJphaaJgAZAgACAAgJphaaJgAZAgABAAQJIA9tWwDCAAAAAA==.',
Ci='Cindrethresh:BAAALgAECgQJCQAAAA==.',
Co='Coffeeblak:BAABLgAECn8ZAAMDAAgJBRNLJgCmAQADAAcJlxNLJgCmAQAWAAUJFQ65PwDkAAAAAA==.Coldstorm:BAAALgAECgcJCwAAAA==.Collision:BAAALgAECggJEQAAAA==.Compensating:BAAALgADCgYJBgAAAA==.Connor:BAAALgADCgcJBwAAAA==.Connsumption:BAAALgAECgYJCgAAAA==.Corrine:BAAALgAECgYJCwAAAA==.',
Cr='Crazybatt:BAABLgAECn8UAAISAAYJXQZu6wDDAAASAAYJXQZu6wDDAAAAAA==.Crypt:BAAALgAECgYJCgAAAA==.',
Cu='Cuckchairpov:BAACLgAFFH8OAAMFAAQJJRQIIQAdAQAFAAQJpBMIIQAdAQADAAIJQg15DACgAAAuAAQKfywAAwMACQkqH2gKANICAAMACAl4HWgKANICAAUACQndFAsUAAYCAAAA.',
Cy='Cynderleena:BAAALgAECgcJCAAAAA==.Cynyia:BAABLgAECn8vAAIIAAkJxRMrKwAIAgAIAAkJxRMrKwAIAgAAAA==.',
Cz='Czk:BAAALgADCgYJBgABLgAECggJGQADAAUTAA==.',
['Có']='Cóldblóód:BAAALgAECgIJAgAAAA==.',
Da='Daddyelessar:BAAALgAECggJDwAAAA==.Dafattyup:BAABLgAECn8aAAIUAAYJlRxUYwCgAQAUAAYJlRxUYwCgAQAAAA==.Daghmar:BAAALgADCgUJBQAAAA==.Dagon:BAAALgAECgMJAwAAAA==.Dakotarain:BAAALgADCgIJAgAAAA==.Dalerontwo:BAAALgADCgEJAQAAAA==.Darruin:BAACLgAFFH8OAAMKAAgJ0B7HBQCjAgAKAAcJ0B7HBQCjAgAGAAEJAAA9WgAAAAAuAAQKfycAAgoACAkeJNcQAN4CAAoACAkeJNcQAN4CAAAA.Dayrun:BAAALgAECgUJDQAAAA==.',
De='Deadicee:BAAALgAECgIJAgABLgAECgYJFAASAHwOAA==.Deadlyvixin:BAAALgAECgEJAQAAAA==.Deadstorm:BAAALgAECgUJBQAAAA==.Deathturtle:BAABLgAECn8eAAIKAAgJLxA0iwBFAQAKAAgJLxA0iwBFAQAAAA==.Deavaos:BAAALgAECgcJCwAAAA==.Dedmartigan:BAAALgADCgUJBQAAAA==.Deeanndra:BAABLgAECn8mAAMKAAgJqRAMZQCVAQAKAAgJqRAMZQCVAQALAAEJDAlWOgAoAAAAAA==.Deevz:BAAALgAECgIJAgAAAA==.Demandred:BAAALgAECgYJCQAAAA==.Demiz:BAABLgAECn84AAMCAAkJ5Rr+FQCOAgACAAkJ5Rr+FQCOAgABAAcJug5IRAASAQAAAA==.Deredris:BAAALgAECgQJBAABLgAECgYJCgAJAAAAAA==.Dertka:BAAALgAECgYJDAAAAA==.',
Di='Diiviiniity:BAAALgADCgQJBAAAAA==.Discodruid:BAABLgAECn8UAAIMAAYJKROCUQA/AQAMAAYJKROCUQA/AQAAAA==.Dishsoap:BAAALgAECgMJAwABLgAFFAYJGAARACAYAA==.Dixie:BAAALgAECgEJAQAAAA==.',
Dj='Djall:BAAALgAECgUJBQAAAA==.',
Do='Dommy:BAABLgAECn8bAAIGAAkJ1iSoAQBCAwAGAAkJ1iSoAQBCAwAAAA==.Domw:BAAALgAECgYJDAABLgAECgkJGwAGANYkAA==.Donham:BAACLgAFFH8XAAMKAAYJ9xvjLACVAQAKAAUJ9xvjLACVAQAGAAEJAABBEwBZAAAuAAQKfx8AAgoACAnLHzweAMsCAAoACAnLHzweAMsCAAAA.Dorkimedes:BAAALgAECgQJCwAAAA==.Dottie:BAABLgAECn8oAAMHAAgJNhM2FwCQAQAHAAcJJQ82FwCQAQAUAAgJ7xEvWwCIAQAAAA==.Dotvinci:BAAALgAECgYJBgAAAA==.',
Dr='Draelesh:BAABLgAECn85AAIOAAkJoxOKGQDzAQAOAAkJoxOKGQDzAQAAAA==.Draenk:BAAALgADCgUJBQAAAA==.Dragún:BAAALgAECgYJCwAAAA==.Drakari:BAAALgADCgYJBgAAAA==.Dramborleg:BAAALgAECgEJAQAAAA==.Drazon:BAAALgADCgIJAgAAAA==.Drewit:BAABLgAECn8WAAINAAYJPxA1FQBiAQANAAYJPxA1FQBiAQAAAA==.',
Du='Ducan:BAAALgADCgYJCQAAAA==.Duskmane:BAAALgAECgMJCAAAAA==.',
Dw='Dwadler:BAACLgAFFH8LAAMXAAYJCBCEFAAjAQAXAAYJCBCEFAAjAQAVAAIJnQqbJQBVAAAuAAQKfzAAAxUACAltHkgJAFcCABUACAltHkgJAFcCABcABQkmFYMuAAUBAAAA.',
Dy='Dyrkonian:BAAALgAECggJEgAAAA==.',
Ei='Eireann:BAAALgADCgcJCQAAAA==.',
El='Elerrak:BAAALgAECgEJAQABLgAFFAcJIQAYAJ0dAA==.Elindalia:BAAALgAECgMJAwAAAA==.',
Em='Emberash:BAAALgAECgEJAQAAAA==.Embre:BAABLgAFFH8LAAIZAAQJsA7eBAAWAQAZAAQJsA7eBAAWAQAAAA==.Emorri:BAAALgAECgYJBgAAAA==.Empyrea:BAAALgAECgQJBQAAAA==.',
Er='Eraina:BAAALgADCgIJAgAAAA==.Ericles:BAABLgAECn8ZAAMXAAcJ8R1VDADbAQAXAAcJ8R1VDADbAQARAAIJlAVwlwBkAAAAAA==.Erys:BAAALgAECgcJEQAAAA==.Erébus:BAABLgAECn8iAAIaAAkJ7xhfJgAoAgAaAAkJ7xhfJgAoAgAAAA==.',
Ev='Ev:BAAALgAECgQJBAAAAA==.Evergreene:BAAALgAECgEJAQABLgAECgQJCQAJAAAAAA==.Evlpotato:BAABLgAECn80AAQTAAkJIRsKEgA9AgATAAkJIRsKEgA9AgAbAAcJNBpVHgDNAQAcAAEJlAdTfwAzAAAAAA==.Evojak:BAABLgAECn8cAAMdAAgJ3QaeQgAUAQAdAAgJ3QaeQgAUAQAZAAMJxAOFHABgAAAAAA==.',
Fa='Fabiyo:BAAALgADCgMJBQAAAA==.Faevelia:BAAALgAECgUJBgAAAA==.Fairaday:BAACLgAFFH8FAAIIAAMJugHXdQCWAAAIAAMJugHXdQCWAAAuAAQKfzcAAggACQlfC/JPAKYBAAgACQlfC/JPAKYBAAAA.Falloon:BAAALgADCgYJBgAAAA==.Fanshen:BAAALgAECgMJBQAAAA==.Farmerdave:BAAALgAECgEJAQAAAA==.Fatdoinkz:BAAALgAECgUJBwABLgAFFAYJEAAGADoaAA==.Fauchi:BAAALgADCgEJAQAAAA==.Faxqueenmage:BAABLgAECn8bAAIEAAcJgQIf6wDDAAAEAAcJgQIf6wDDAAAAAA==.',
Fe='Felador:BAAALgAECgcJEgABLgAECggJMAAUAGEXAA==.Feldo:BAABLgAECn8SAAIaAAYJjyFtNwDdAQAaAAYJjyFtNwDdAQAAAA==.Felmès:BAAALgADCgYJBgABLgAECggJHgAEABsLAA==.Fennec:BAAALgAECgUJDAAAAA==.Feralarak:BAAALgAECgcJEwABLgAFFAcJIQAYAJ0dAA==.',
Fi='Firebrandd:BAACLgAFFH8cAAMZAAYJzxwbAgBmAQAZAAUJnyAbAgBmAQAdAAUJZhFGHgBQAQAuAAQKf0EAAxkACQl8I2ACAA8DABkACAlIImACAA8DAB0ACQlEImwIAMsCAAEuAAUUCAkOAAoA0B4A.Fizehbubbleh:BAEALgAECgYJCAABLgAECggJIAABAOgaAA==.Fizehtotems:BAEBLgAECn8gAAMBAAgJ6BouKwCMAQABAAgJ6BouKwCMAQACAAUJixZkWgA+AQAAAA==.',
Fl='Fleshoracle:BAAALgAECgQJBAABLgAFFAYJEAAGADoaAA==.Fluctuates:BAAALgAECgQJCAAAAA==.',
Fo='Foragarn:BAAALgAECgYJCQAAAA==.Foron:BAAALgAECgIJAgAAAA==.',
Fr='Frankkastle:BAAALgAECgYJDwAAAA==.Frazelia:BAAALgADCgkJDgABLgAECgYJFgANAD8QAA==.Fribble:BAABLgAECn8ZAAMCAAkJmw5BOADBAQACAAkJmw5BOADBAQAYAAEJAACmQwAAAAAAAA==.Froggierlynx:BAAALgAFFAQJBAAAAA==.Frostalot:BAAALgAECgMJAwAAAA==.Froznfate:BAABLgAECn8wAAMQAAkJaiXpAABOAwAQAAkJaiXpAABOAwASAAIJpQfeUQFRAAAAAA==.Fryes:BAAALgAECgkJDAAAAA==.',
Fu='Fuzziebutt:BAAALgAECgQJBgAAAA==.',
Fw='Fwibble:BAAALgAECggJEgABLgAECgkJGQACAJsOAA==.',
Fy='Fyrelady:BAAALgADCggJDgABLgAECgQJCQAJAAAAAA==.Fyrestone:BAAALgAECgQJCQAAAA==.',
['Fæ']='Fæder:BAAALgADCgYJBgAAAA==.',
Ga='Gabarnak:BAAALgADCgIJAgABLgAECggJGwAWAKEfAA==.Gabuse:BAAALgAECgQJBAAAAA==.Galencharred:BAABLgAECn8jAAISAAgJqQjBoAAqAQASAAgJqQjBoAAqAQAAAA==.Garagon:BAABLgAECn85AAIeAAkJOBbyCQA9AgAeAAkJOBbyCQA9AgAAAA==.Gauss:BAABLgAECn8dAAIQAAgJoAYAJQDfAAAQAAgJoAYAJQDfAAABLgAECgkJGQACAJsOAA==.Gaîîa:BAABLgAECn8cAAIIAAgJCRq2MADtAQAIAAgJCRq2MADtAQAAAA==.',
Ge='Gelber:BAAALgAECgQJBAAAAA==.Gerva:BAABLgAECn82AAIKAAkJfhN5MwAoAgAKAAkJfhN5MwAoAgAAAA==.',
Gh='Ghlain:BAAALgAECgQJBwAAAA==.Ghorfindor:BAABLgAECn8jAAIfAAgJ8wO0OQC/AAAfAAgJ8wO0OQC/AAAAAA==.Ghostlybrew:BAACLgAFFH8VAAIFAAcJ9xv1CQDNAQAFAAcJ9xv1CQDNAQAuAAQKfxYAAgUACAmpH94TAHECAAUACAmpH94TAHECAAAA.',
Gi='Gigastorm:BAAALgADCgIJAQAAAA==.Gilas:BAABLgAECn8oAAQKAAgJEw5qjQBBAQAKAAgJVAdqjQBBAQAGAAYJcBDaLwDWAAALAAUJXgXqJACTAAAAAA==.',
Gl='Glaivemstake:BAAALgADCgcJBwAAAA==.',
Gn='Gnik:BAAALgAECgkJEgAAAA==.Gnikole:BAAALgAECgIJAgABLgAECgkJEgAJAAAAAA==.Gnoeme:BAAALgAECgEJAQAAAA==.',
Go='Goswin:BAAALgAECgIJBAAAAA==.',
Gr='Graahak:BAAALgADCgMJAwAAAA==.Graveborn:BAABLgAFFH8QAAIGAAYJOhoBDQCNAQAGAAYJOhoBDQCNAQAAAA==.Graydenton:BAAALgAECgkJCQABLgAECggJBgAJAAAAAA==.Greenfelpowa:BAABLgAECn8ZAAIUAAkJpQ+wRQDEAQAUAAkJpQ+wRQDEAQAAAA==.Gruuven:BAAALgADCgUJBwAAAA==.',
Gu='Gutmtmon:BAABLgAECn8YAAIDAAgJTwcgPgD5AAADAAgJTwcgPgD5AAAAAA==.',
Gw='Gwenivive:BAABLgAECn8hAAIIAAkJjBdZJwA3AgAIAAkJjBdZJwA3AgAAAA==.',
['Gí']='Gízmo:BAAALgADCgUJBQAAAA==.',
Ha='Haenus:BAABLgAECn8dAAIaAAgJ8hMPeAAkAQAaAAgJ8hMPeAAkAQAAAA==.Hamor:BAAALgAECgkJCgAAAA==.Harrynear:BAAALgADCgMJAwABLgAECgcJFwAKANMXAA==.Hat:BAACLgAFFH8FAAIaAAIJ9CJOXADHAAAaAAIJ9CJOXADHAAAuAAQKfxkAAxoACQl8IoYGABoDABoACQl8IoYGABoDACAAAgmRCmoqAE0AAAAA.Haunt:BAAALgAECgUJBgAAAA==.Havark:BAAALgAECgMJAwAAAA==.',
He='Healbilly:BAAALgADCgEJAQAAAA==.Healingdeath:BAAALgADCgMJBAAAAA==.Hecatombe:BAAALgADCgUJBQAAAA==.Hellda:BAEALgAECgkJBgABLgAFFAMJDQASADwIAA==.Hellzdruid:BAAALgADCgQJBAAAAA==.Hellzknîght:BAABLgAECn8hAAIKAAcJuxRjcgB3AQAKAAcJuxRjcgB3AQAAAA==.Hellzshaman:BAAALgADCgIJAQAAAA==.',
Ho='Holek:BAABLgAECn8ZAAMIAAgJphHaTACvAQAIAAgJphHaTACvAQAhAAMJcAQ2SQCHAAAAAA==.Holgo:BAACLgAFFH8MAAIVAAUJLyM9BAADAgAVAAUJLyM9BAADAgAuAAQKfyEAAhUACQluJZkBADwDABUACQluJZkBADwDAAAA.Holgy:BAACLgAFFH8aAAIiAAYJtCJcAgAFAgAiAAYJtCJcAgAFAgAuAAQKfyYAAiIACQlWI0wBAEkDACIACQlWI0wBAEkDAAAA.Holybeard:BAACLgAFFH8LAAISAAQJaRTPTQADAQASAAQJaRTPTQADAQAuAAQKfzkAAhIACAnyINQcAI4CABIACAnyINQcAI4CAAAA.Hooks:BAAALgAECgQJCAAAAA==.',
Hu='Hugecowballs:BAAALgAECgkJCQAAAA==.Hunterturtle:BAAALgADCgUJBQAAAA==.',
Ic='Icia:BAAALgAECgEJAQAAAA==.',
Id='Idontmiss:BAAALgAECgIJCAAAAA==.',
Il='Ilickboody:BAAALgADCgQJBAAAAA==.Illustra:BAABLgAECn8aAAMcAAgJnAYlOAANAQAcAAgJnAYlOAANAQATAAcJ3gKhVQCwAAABLgAECggJHgAEABsLAA==.',
Im='Imaeru:BAAALgADCgYJDAAAAA==.Imcaldo:BAAALgADCgYJBgAAAA==.Imcaldoo:BAAALgADCgUJCgAAAA==.',
In='Interrupt:BAAALgAECgUJDQAAAA==.',
Ir='Irox:BAAALgADCgMJAwAAAA==.',
Is='Isaic:BAAALgADCgIJAgAAAA==.Iseila:BAABLgAECn8YAAIEAAkJ+A2GZgCpAQAEAAkJ+A2GZgCpAQAAAA==.Isevio:BAAALgAECgMJBwAAAA==.',
It='Ithorus:BAAALgAECgYJEgAAAA==.',
Ja='Jaadb:BAAALgAECgQJBwAAAA==.Jaadd:BAAALgAECgIJAgAAAA==.Jaadi:BAAALgAECgIJAwAAAA==.Jaata:BAAALgADCgcJEAAAAA==.Jairl:BAAALgAECgQJBwAAAA==.Jamien:BAABLgAECn85AAMSAAkJ5R4nGACpAgASAAkJ5R4nGACpAgAPAAUJigUsdwCdAAAAAA==.Janal:BAAALgADCgEJAQAAAA==.Jasnah:BAABLgAECn8WAAMBAAYJHhWCOABGAQABAAYJHhWCOABGAQACAAMJnBP1iwCwAAAAAA==.Jasnos:BAAALgAECgUJDAAAAA==.',
Jd='Jdk:BAAALgAECgUJBwAAAA==.',
Je='Jelf:BAAALgAECgUJCAAAAA==.Jenzing:BAABLgAECn8VAAMUAAgJqh0QKwBjAgAUAAcJqh0QKwBjAgAjAAEJAACuIwBjAAAAAA==.Jessemyn:BAAALgAECgYJEQAAAA==.',
Jh='Jholy:BAAALgAECgMJAwAAAA==.',
Jo='Jobokenhones:BAACLgAFFH8FAAIaAAMJPg0tYwC1AAAaAAMJPg0tYwC1AAAuAAQKfzEAAhoACQkgGgMiAD8CABoACQkgGgMiAD8CAAAA.Johadgan:BAAALgADCgEJAQAAAA==.',
Jp='Jproudmore:BAAALgADCgUJBQABLgADCgYJCwAJAAAAAA==.',
Js='Jsberg:BAABLgAECn8eAAIRAAgJwRVALACbAQARAAgJwRVALACbAQAAAA==.',
Ka='Kaathe:BAABLgAECn8lAAMEAAYJGx7ihADHAQAEAAYJGx7ihADHAQAkAAEJjhqXDwA4AAAAAA==.Kaboomalis:BAAALgADCgUJBQAAAA==.Kadance:BAABLgAECn8WAAIBAAcJmRaWMQBpAQABAAcJmRaWMQBpAQAAAA==.Kaelyn:BAAALgAECgQJBAABLgAFFAMJCgAMAKsaAA==.Kaidiis:BAABLgAECn8uAAISAAkJzA4DYACmAQASAAkJzA4DYACmAQAAAA==.Kaido:BAAALgAECgEJAQAAAA==.Kalder:BAAALgADCgcJBwAAAA==.Karbonn:BAABLgAECn8YAAIZAAgJjBR0BwC4AQAZAAgJjBR0BwC4AQAAAA==.Kay:BAAALgAECgcJBwAAAA==.Kazeraz:BAAALgADCgEJAQAAAA==.',
Ke='Kegbreaker:BAACLgAFFH8FAAIcAAMJIwYhJACJAAAcAAMJIwYhJACJAAAuAAQKfzcAAhwACQlQCjsqAGkBABwACQlQCjsqAGkBAAAA.',
Kh='Khanas:BAABLgAECn8YAAMPAAgJaRaUKwCqAQAPAAcJiBeUKwCqAQASAAEJOQI+twEZAAAAAA==.Kheru:BAAALgAECgUJBgAAAA==.Khoan:BAAALgAECgYJCgAAAA==.',
Ki='Kimbliddan:BAAALgAECgEJAQABLgAECgkJOQAEADgkAA==.Kimbustible:BAABLgAECn85AAIEAAkJOCQVDQALAwAEAAkJOCQVDQALAwAAAA==.Kimchi:BAABLgAECn8WAAIFAAgJlhBaJgBzAQAFAAgJlhBaJgBzAQABLgAECgkJOQAEADgkAA==.',
Kn='Knockknocko:BAAALgAECgcJDgAAAA==.',
Ko='Kobir:BAAALgADCgEJAQAAAA==.Komodostyle:BAABLgAECn86AAQeAAkJYg2rFgBcAQAeAAgJywqrFgBcAQAdAAYJ9RJ4OwAyAQAZAAIJWw64NQBoAAAAAA==.Koobideh:BAAALgADCgEJAQAAAA==.',
Kr='Krayose:BAAALgAECgcJDwAAAA==.Kriddler:BAAALgADCgQJBAAAAA==.Krisarugala:BAABLgAECn8VAAIOAAcJgA1qPwACAQAOAAcJgA1qPwACAQAAAA==.',
Ku='Kujoluvsmilf:BAAALgAECggJCwAAAA==.Kunuku:BAAALgADCgUJBQAAAA==.Kurash:BAAALgADCgcJBwAAAA==.Kurion:BAAALgAECgkJCgAAAA==.Kurogami:BAAALgAECgUJCAAAAA==.',
Ky='Kylesxmom:BAACLgAFFH8UAAMKAAYJDRAiPwBlAQAKAAUJDRAiPwBlAQAGAAIJuA1uOgAwAAAuAAQKf2AAAwoACQltJA0HADcDAAoACQlAJA0HADcDAAYACAn/HakQAPUBAAAA.Kymal:BAABLgAECn88AAIaAAkJzRWINADoAQAaAAkJzRWINADoAQAAAA==.Kymbria:BAAALgADCgUJCAAAAA==.Kymora:BAAALgADCgcJBwAAAA==.Kyndrissa:BAAALgADCgUJBQAAAA==.',
['Kë']='Këy:BAACLgAFFH8MAAIKAAMJQBhriQDkAAAKAAMJQBhriQDkAAAuAAQKfykAAgoACAnUHYwsAIYCAAoACAnUHYwsAIYCAAAA.',
La='Latrice:BAACLgAFFH8pAAIEAAgJECN3BADPAgAEAAgJECN3BADPAgAuAAQKfygABAQACQk5I9wJAHYDAAQACQk5I9wJAHYDACQAAwm4GZUJANEAACUAAQltGN0YAFEAAAAA.Lavynder:BAABLgAECn8XAAIaAAgJ5hUVWgCTAQAaAAgJ5hUVWgCTAQAAAA==.Lazerturkey:BAAALgAECgkJDwAAAA==.Laërtes:BAAALgAECgUJEwAAAA==.',
Le='Leiamirage:BAAALgAECgYJDwAAAA==.Leviscus:BAAALgAECgUJDgAAAA==.',
Li='Lifetap:BAAALgADCgMJAwAAAA==.Lightbill:BAAALgAFFAMJAwAAAA==.Lightbàne:BAABLgAECn8qAAINAAkJ2CKgAQAfAwANAAkJ2CKgAQAfAwAAAA==.Lightningrod:BAAALgAECgYJBwAAAA==.Lightrogue:BAAALgAECgUJBQABLgAECgkJKgANANgiAA==.Lightshaolin:BAAALgAECgQJBAAAAA==.Lildruidz:BAABLgAECn8dAAMMAAcJbhMgPgCRAQAMAAcJbhMgPgCRAQAOAAEJLQKfngAZAAAAAA==.Lillivarak:BAABLgAECn8UAAISAAcJFgfVzADqAAASAAcJFgfVzADqAAAAAA==.Lilriotz:BAAALgAECgUJBgAAAA==.Lilriotzz:BAABLgAECn8XAAICAAgJuxkJHABeAgACAAgJuxkJHABeAgAAAA==.Lilzdrlockz:BAAALgAECgUJCgAAAA==.Lithedra:BAAALgADCgcJDwAAAA==.Littlehand:BAAALgADCgUJBAABLgAECgYJIAAPAMQWAA==.',
Lo='Lovecraft:BAAALgADCgYJCwAAAA==.',
Lu='Lucavi:BAAALgAECgMJAwAAAA==.Lucyvar:BAAALgAECgkJEQAAAA==.Luke:BAAALgADCgUJBwAAAA==.Luma:BAAALgAECgQJCAAAAA==.Luther:BAABLgAECn8XAAIFAAkJNw9XJQDYAQAFAAkJNw9XJQDYAQAAAA==.',
Ly='Lyla:BAAALgADCgQJBgAAAA==.',
Ma='Magnux:BAAALgAECgEJAgAAAA==.Malazark:BAAALgADCgYJBgAAAA==.Malríus:BAAALgAECgQJEQAAAA==.Manales:BAAALgAECgcJBgAAAA==.Marhukai:BAACLgAFFH8FAAISAAMJoBhYWADrAAASAAMJoBhYWADrAAAuAAQKfy8AAhIACQlBH0kWALQCABIACQlBH0kWALQCAAAA.Marotal:BAABLgAECn8mAAIEAAgJNBQsWQDLAQAEAAgJNBQsWQDLAQAAAA==.Martysparty:BAABLgAECn8yAAIQAAkJER1uBgBzAgAQAAkJER1uBgBzAgAAAA==.Mavaena:BAAALgAECgYJDAAAAA==.Mavrane:BAAALgADCgEJAgAAAA==.',
Me='Meashakegs:BAAALgAECggJEQAAAA==.Meashaman:BAAALgAECgMJAwAAAA==.Mechaboomer:BAABLgAECn84AAIIAAkJ0xsDGQCEAgAIAAkJ0xsDGQCEAgAAAA==.Megafire:BAAALgAECgEJAQAAAA==.Megahertz:BAAALgAECgQJBAAAAA==.Melcanthet:BAAALgADCggJCAAAAA==.Mellowrock:BAAALgAECgUJBgABLgAECgYJBQAJAAAAAA==.',
Mi='Mickhaggis:BAAALgADCgIJAgAAAA==.Micktarogar:BAAALgAECgcJEwAAAA==.Mickwutang:BAAALgAFFAEJAQAAAA==.Miklaga:BAAALgAECgEJAgAAAA==.Milince:BAAALgADCgMJAgAAAA==.Milkfridge:BAAALgAECgEJAQABLgAFFAMJBQANAF4EAA==.Minikloon:BAAALgAECgYJDgAAAA==.Minphoria:BAAALgADCgQJBgAAAA==.Missylock:BAAALgADCgYJBgAAAA==.Mistilinn:BAACLgAFFH8FAAImAAMJ+wB6IQCHAAAmAAMJ+wB6IQCHAAAuAAQKfyoAAiYACQldB+wRADEBACYACQldB+wRADEBAAAA.Miyri:BAAALgAECgEJAwABLgAFFAMJCgAMAKsaAA==.',
Mo='Mollyporph:BAAALgAECgEJAQAAAA==.Monoco:BAAALgAECgYJEwAAAA==.Moopandax:BAACLgAFFH8bAAIOAAcJFx0PBgAkAgAOAAcJFx0PBgAkAgAuAAQKf1gAAw4ACQl5JlkAAJEDAA4ACQl5JlkAAJEDACIACAmhH1sHAHECAAEuAAUUBQkbAA4AYCIA.Mortrum:BAAALgADCgQJBAAAAA==.Moxestime:BAAALgAECgEJAgAAAA==.Moxsdeath:BAAALgADCgYJBgAAAA==.Moxsdeaths:BAAALgADCgcJBwAAAA==.',
Mu='Mushaboom:BAABLgAECn8YAAIFAAgJJwdcOAATAQAFAAgJJwdcOAATAQAAAA==.Muzzler:BAABLgAECn9aAAIEAAkJvCOQBgBIAwAEAAkJvCOQBgBIAwAAAA==.',
My='Myeyes:BAAALgAECgEJAwAAAA==.Mylinkah:BAAALgADCgQJBAAAAA==.Mynamefizz:BAEBLgAECn8XAAQUAAkJNBlEMAASAgAUAAkJ9xVEMAASAgAjAAMJeh1fFwD2AAAHAAMJghSyHgCqAAABLgAECggJIAABAOgaAA==.Myotonic:BAAALgADCgQJBAAAAA==.Mythlok:BAAALgAECgMJAwAAAA==.Mythreiel:BAAALgAECgUJBgAAAA==.Mythykal:BAAALgAECgUJBwAAAA==.',
['Mé']='Méasha:BAAALgAECgkJCgAAAA==.',
['Mï']='Mïlk:BAAALgAECggJCAAAAQ==.',
Na='Nachtmar:BAAALgAECgQJBAABLgAECgkJGgASAIkPAA==.Nadis:BAAALgAECgIJAwAAAA==.Narcessa:BAAALgADCgQJBAAAAA==.Nawk:BAAALgAECgEJAQAAAA==.',
Ne='Nennerb:BAAALgADCgQJBAAAAA==.',
Ni='Nicola:BAAALgAECgcJDgAAAA==.Nightxwish:BAABLgAECn8iAAIbAAYJ9BtZGwDmAQAbAAYJ9BtZGwDmAQAAAA==.Niranye:BAAALgADCgEJAQAAAA==.',
No='Noisemarine:BAACLgAFFH8RAAIVAAQJvxWBEgADAQAVAAQJvxWBEgADAQAuAAQKfxoAAhUACAm7G7ANAAQCABUACAm7G7ANAAQCAAAA.Nokk:BAAALgADCgEJAQAAAA==.Nokkco:BAAALgAECgEJAgAAAA==.Norellia:BAAALgAECgQJBgAAAA==.Northleo:BAAALgADCgcJEQAAAA==.Northspirit:BAABLgAECn8UAAIBAAUJzQVMbgCNAAABAAUJzQVMbgCNAAAAAA==.',
Nu='Nuit:BAAALgADCgUJBQABLgAECgYJCwAJAAAAAA==.',
Ny='Nyarlothep:BAAALgAECgQJBAAAAA==.Nyx:BAAALgAECgUJBQABLgAECgkJOQASAOUeAA==.',
Oa='Oakenshièld:BAAALgAECgcJDAAAAA==.',
Od='Odindh:BAAALgAFFAIJAwAAAA==.Odins:BAAALgAFFAEJAQABLgAFFAIJAwAJAAAAAA==.',
Oh='Ohwhelp:BAABLgAFFH8IAAIdAAMJ5BlkNQDjAAAdAAMJ5BlkNQDjAAABLgAFFAcJLAAOAKYkAA==.Ohyikers:BAACLgAFFH8sAAIOAAcJpiQTAwB/AgAOAAcJpiQTAwB/AgAuAAQKfzUAAg4ACAnRJjEEABYDAA4ACAnRJjEEABYDAAAA.',
Ok='Oken:BAAALgADCgUJBQAAAA==.',
Om='Om:BAAALgADCgcJCQAAAA==.',
Op='Open:BAAALgADCgcJBwABLgAECgYJIAAPAMQWAA==.Opportunity:BAAALgAECgYJBgABLgAFFAMJCwAPAMUeAA==.',
Or='Orklock:BAAALgADCgMJAwAAAA==.',
Pa='Pallek:BAAALgAECgcJBwABLgAECggJGQAIAKYRAA==.Palli:BAABLgAECn8dAAIPAAcJ8BUPLgCbAQAPAAcJ8BUPLgCbAQAAAA==.Paogao:BAAALgAECgIJAwAAAA==.Parry:BAAALgADCgQJBAAAAA==.Pasghetti:BAAALgADCgMJAwAAAA==.Pasta:BAABLgAECn8rAAInAAkJSh58BwClAgAnAAkJSh58BwClAgAAAA==.',
Pe='Perpetual:BAAALgAECgEJAQAAAA==.Pewpewbite:BAAALgAECggJEgAAAA==.',
Ph='Phantomarrow:BAACLgAFFH8VAAQhAAUJQROcFgALAQAhAAQJGAycFgALAQAmAAUJHQu0GwC4AAAIAAIJPg6BdwCTAAAuAAQKfxwABAgABgnsIcREAMcBAAgABgnsIcREAMcBACYABQmzGbBCAE0BACEAAQkAAChpAAAAAAAA.Phatcow:BAABLgAECn81AAMCAAkJgxt7FwBaAgACAAgJaxp7FwBaAgAYAAkJRhSTCgABAgAAAA==.Pheral:BAEALgAECggJDwABLgAFFAMJDQASADwIAA==.Phoseidon:BAAALgADCgcJCQAAAA==.Phude:BAACLgAFFH8PAAISAAMJ8RdZVQDyAAASAAMJ8RdZVQDyAAAuAAQKf0wAAhIACQnTIPEMAPUCABIACQnTIPEMAPUCAAAA.',
Pi='Pinch:BAAALgAECgMJAwAAAA==.',
Po='Pohl:BAAALgAECgYJDQAAAA==.Pokimana:BAAALgADCgEJAQAAAA==.Poohynok:BAACLgAFFH8LAAIEAAQJlh2dQgBXAQAEAAQJlh2dQgBXAQAuAAQKfzwAAgQACQkXJSwJAC0DAAQACQkXJSwJAC0DAAAA.',
Pu='Pukefeast:BAABLgAECn8UAAIEAAcJ3RewcgCOAQAEAAcJ3RewcgCOAQAAAA==.',
Py='Pyramys:BAACLgAFFH8TAAInAAUJLB+WGABBAQAnAAUJLB+WGABBAQAuAAQKfyoAAicACAkxI6cGALcCACcACAkxI6cGALcCAAAA.',
['Pè']='Pèrce:BAAALgAECgYJEQAAAA==.',
Qu='Quepaoka:BAAALgADCgIJAgAAAA==.',
Ra='Raklem:BAAALgAECgMJAwABLgAECgYJCgAJAAAAAA==.Ramble:BAAALgADCgQJBAABLgAECgQJBgAJAAAAAA==.Ramstein:BAAALgAECgMJAwAAAA==.Raphînîty:BAAALgADCgMJBQAAAA==.Rashari:BAAALgADCgYJCAAAAA==.Rawhawk:BAAALgAECgUJCgABLgAECggJGwAIAFEUAA==.Razgrizz:BAAALgAECgUJDgAAAA==.',
Re='Retro:BAAALgAECgIJBAAAAA==.Revelatus:BAAALgAECgQJBgAAAA==.Reythanas:BAAALgAECgQJBwAAAA==.Rezzin:BAAALgAECgEJAQAAAA==.',
Ri='Rileyann:BAABLgAECn8fAAMcAAgJOQzMKQBsAQAcAAgJOQzMKQBsAQATAAYJAwNMRADaAAAAAA==.',
Ro='Rolls:BAAALgAECgQJBAAAAA==.Roozer:BAAALgAECgUJDQAAAA==.',
Ru='Runearius:BAAALgAECgYJBgABLgAFFAQJCwASAGkUAA==.',
['Rå']='Råphå:BAAALgAECgMJBAAAAA==.',
Sa='Saelyria:BAACLgAFFH8KAAIMAAMJqxo8LwDuAAAMAAMJqxo8LwDuAAAuAAQKfxwAAgwACQmmHeEJABUDAAwACQmmHeEJABUDAAAA.Saga:BAAALgADCgUJBQABLgAECgkJRAAQALwUAA==.Sagepower:BAAALgAECgQJBQAAAA==.Sagethepally:BAAALgAECgcJBAAAAA==.Saintfail:BAABLgAECn8hAAIPAAYJ7SRLFABiAgAPAAYJ7SRLFABiAgABLgAECgcJMwAWAGQhAA==.Sainthymn:BAABLgAECn8XAAIbAAYJnCRUDgB9AgAbAAYJnCRUDgB9AgABLgAECgcJMwAWAGQhAA==.Saintmist:BAABLgAECn8zAAIWAAcJZCHVDQCwAgAWAAcJZCHVDQCwAgAAAA==.Salero:BAAALgADCgIJAQAAAA==.Sandiera:BAABLgAECn8eAAMEAAgJGwvLoQAzAQAEAAgJGwvLoQAzAQAlAAMJPAOoFwBcAAAAAA==.Saxtön:BAAALgADCggJEwAAAA==.Sayberix:BAAALgAFFAIJAgABLgAFFAQJDgAXALEcAA==.',
Sc='Scarlett:BAAALgAECgEJAQAAAA==.Scoreboard:BAACLgAFFH8lAAIoAAcJ4CUuAACpAgAoAAcJ4CUuAACpAgAuAAQKfyEAAygACQkgJg0AAOsDACgACQkgJg0AAOsDACcAAQnwFJhaAE8AAAAA.Scorn:BAAALgAECgYJDgAAAA==.Scottx:BAACLgAFFH8FAAIMAAIJmAhHVgBoAAAMAAIJmAhHVgBoAAAuAAQKfxQAAgwABwlPFL86AKEBAAwABwlPFL86AKEBAAAA.',
Se='Sebas:BAAALgAECgEJAQAAAA==.Sedric:BAABLgAECn8UAAIOAAcJpgkcQwDyAAAOAAcJpgkcQwDyAAAAAA==.Selkz:BAAALgAECgcJDQAAAA==.Selsonblue:BAAALgAECgUJBwAAAA==.Sesskaa:BAABLgAECn8VAAICAAgJQB2TFQCSAgACAAgJQB2TFQCSAgAAAA==.Severoth:BAAALgADCgUJBQAAAA==.',
Sh='Shadowcursed:BAAALgADCgcJCgAAAA==.Shadowstorm:BAAALgADCgQJBAAAAA==.Shadøws:BAAALgAECgEJAQAAAA==.Shakenhealz:BAAALgADCgYJBgAAAA==.Shaldria:BAAALgADCgEJAQAAAA==.Sharhox:BAAALgAECgIJBAAAAA==.Shathos:BAAALgADCgEJAQAAAA==.Sheebá:BAAALgADCgYJCwAAAA==.Shishkbob:BAAALgADCgkJCQAAAA==.Shivax:BAAALgAECgYJDgAAAA==.Shugma:BAAALgADCggJCAAAAA==.Shünúkh:BAAALgADCgYJBgAAAA==.',
Si='Sigewulf:BAAALgAFFAIJBAABLgAECgcJHgAFANoKAA==.Signal:BAAALgAECgEJAQAAAA==.Singbow:BAAALgADCgYJBgABLgAECgkJMgAMAJsOAA==.Sinogad:BAABLgAECn8YAAMOAAgJlBG4KAB9AQAOAAgJlBG4KAB9AQAMAAUJ4xPiUwA2AQAAAA==.Sinol:BAAALgAECgYJDwABLgAECggJGAAOAJQRAA==.Sioux:BAAALgADCgEJAQAAAA==.Sixosix:BAAALgADCgIJAgAAAA==.',
Sk='Skaro:BAABLgAECn8XAAMWAAgJYxJGTAAhAQAWAAcJgQ9GTAAhAQADAAEJRw3ykwAxAAAAAA==.Skyborn:BAABLgAECn8YAAIEAAgJnwwfggBtAQAEAAgJnwwfggBtAQAAAA==.',
Sl='Slamahoochee:BAAALgAECgYJCQAAAA==.Slay:BAACLgAFFH8RAAIOAAQJ5B56FQBXAQAOAAQJ5B56FQBXAQAuAAQKfyoABA4ACAmPISEPAGICAA4ACAmPISEPAGICAA0ABglkG48TAHgBAAwAAQk/AxXxABoAAAAA.',
Sm='Smokedademon:BAAALgAECgMJCQAAAA==.Smokiebear:BAAALgAECgcJDgAAAA==.Smunkie:BAABLgAECn8fAAIFAAcJyibHCQCOAgAFAAcJyibHCQCOAgABLgAECgkJGwAGANYkAA==.',
Sn='Snickeers:BAAALgAECgEJAQAAAA==.',
So='Sofa:BAAALgAECgQJBAAAAA==.Somapeace:BAAALgAECgYJCwAAAA==.Somogyi:BAAALgADCgIJAgAAAA==.',
Sp='Spopovich:BAAALgADCggJCAABLgAECgMJAwAJAAAAAA==.Sprints:BAAALgAECgQJBAAAAA==.',
St='Stitchlock:BAAALgAECgIJAgAAAA==.Stitchofevil:BAABLgAECn8WAAQjAAcJuBoEBgACAgAjAAYJUB8EBgACAgAUAAQJpAmz8wBuAAAHAAIJtQ8hYQBMAAAAAA==.Stonedshaman:BAAALgADCgYJBgABLgAECgIJAgAJAAAAAA==.Stormhands:BAAALgAECgYJDwAAAA==.Stormhugger:BAAALgAFFAEJAQAAAA==.Stormslight:BAAALgAECgQJBQAAAA==.Stoutnholy:BAABLgAECn8XAAISAAgJdQmYlAA+AQASAAgJdQmYlAA+AQAAAA==.Stratichnut:BAABLgAECn8yAAMMAAkJmw5WOACsAQAMAAkJmw5WOACsAQAOAAMJSwh1egBGAAAAAA==.Stromar:BAAALgAECgQJBAAAAA==.Stwampadin:BAABLgAECn8hAAIPAAkJyyFnAwBiAwAPAAkJyyFnAwBiAwAAAA==.Stwevoker:BAAALgAECgMJAwABLgAECgkJIQAPAMshAA==.Stwonkfu:BAAALgAECggJCwABLgAECgkJIQAPAMshAA==.',
Su='Sumire:BAAALgADCggJDgABLgAECgYJCgAJAAAAAA==.Surloyn:BAAALgAECgcJEQAAAA==.',
Sv='Sveny:BAAALgAECgEJAQAAAA==.',
Sw='Swampert:BAACLgAFFH8YAAIRAAYJIBj1CQCnAQARAAYJIBj1CQCnAQAuAAQKfyAAAhEACQmJIOgMAO8CABEACQmJIOgMAO8CAAAA.Swamperting:BAABLgAECn8XAAIRAAcJMhP6NgBjAQARAAcJMhP6NgBjAQABLgAFFAYJGAARACAYAA==.Swaye:BAACLgAFFH8JAAITAAMJ6QkcJQC4AAATAAMJ6QkcJQC4AAAuAAQKfysAAhMACQlUFqgWAAwCABMACQlUFqgWAAwCAAAA.Sweetfox:BAAALgAECgYJCgAAAA==.Swiftorius:BAAALgAECgEJAQAAAA==.Swimchick:BAAALgAECgUJEAAAAA==.Switched:BAAALgADCgcJBwABLgAECgkJGwAGANYkAA==.Swizzle:BAAALgAFFAEJAQAAAA==.',
Sy='Syllvanas:BAABLgAECn8dAAIIAAgJ7hF7SwCzAQAIAAgJ7hF7SwCzAQAAAA==.Syrindra:BAAALgADCgUJAwAAAA==.Sythia:BAACLgAFFH8HAAIcAAQJmAtZFwDuAAAcAAQJmAtZFwDuAAAuAAQKfxgAAhwACAkhI0oFAB4DABwACAkhI0oFAB4DAAAA.',
Ta='Taltost:BAABLgAECn8bAAIIAAgJURRWRQDFAQAIAAgJURRWRQDFAQAAAA==.Tantrik:BAAALgADCgEJAQAAAA==.Tartin:BAAALgAECgMJAwAAAA==.Tarv:BAAALgAECgEJAQAAAA==.Tashamirage:BAAALgAECgMJBAAAAA==.Tauriel:BAAALgAECgUJBwAAAA==.',
Te='Teex:BAAALgADCgYJBwAAAA==.Teksuo:BAACLgAFFH8PAAIDAAMJARPCIADMAAADAAMJARPCIADMAAAuAAQKf08AAgMACQkqH64IALACAAMACQkqH64IALACAAAA.Telamontay:BAAALgADCgkJFQAAAA==.Telferas:BAABLgAECn8VAAIOAAgJ+RmGJACZAQAOAAgJ+RmGJACZAQABLgAFFAgJDgAKANAeAA==.Tenithon:BAACLgAFFH8LAAMPAAMJxR4bIAASAQAPAAMJxR4bIAASAQASAAEJMQRVrwA+AAAuAAQKfzUAAg8ACQnLImgDAGIDAA8ACQnLImgDAGIDAAAA.Tenshenzen:BAABLgAECn8eAAIWAAkJ9RWXFgBSAgAWAAkJ9RWXFgBSAgAAAA==.',
Th='Therandis:BAAALgADCgUJBQAAAA==.Thetombo:BAAALgAECgYJDwAAAA==.Thierry:BAAALgADCgUJBQAAAA==.Thierrye:BAABLgAECn8VAAIaAAYJlhtmTQC/AQAaAAYJlhtmTQC/AQAAAA==.Tholaren:BAABLgAECn83AAMIAAkJZBKqMwADAgAIAAkJZBKqMwADAgAmAAUJVQdiIwCLAAAAAA==.Threed:BAAALgAECgkJEwAAAA==.Threewar:BAAALgAECgIJAgABLgAECgkJEwAJAAAAAA==.Thrissa:BAABLgAECn8YAAIMAAgJRxK9MwDEAQAMAAgJRxK9MwDEAQAAAA==.Thulgrim:BAAALgADCgYJBgAAAA==.',
To='Torrque:BAAALgADCgkJCQABLgADCgYJCwAJAAAAAA==.Totemlicker:BAAALgAECgEJAQAAAA==.',
Tr='Trandeath:BAAALgAECgQJBAAAAA==.Trangon:BAABLgAECn8nAAISAAkJlgr5dAB5AQASAAkJlgr5dAB5AQAAAA==.Traveler:BAAALgADCgEJAQAAAA==.Traygon:BAAALgAECgYJEAAAAA==.Trillion:BAAALgADCggJCAAAAA==.',
Tu='Tunzoffun:BAAALgAECgIJBQAAAA==.',
Un='Unanswered:BAAALgAECgEJAQABLgAFFAYJEAAGADoaAA==.Underbyte:BAAALgADCggJDwAAAA==.Unknownname:BAAALgAECgMJAwAAAA==.',
Ur='Urholiness:BAAALgADCgkJDwAAAA==.',
Va='Vaeleia:BAAALgAECgQJBgAAAA==.Vahnkar:BAAALgADCgYJCQAAAA==.Valentinu:BAAALgADCgcJDwAAAA==.Valkyrie:BAAALgAECgEJAgAAAA==.Vaneshk:BAAALgADCgEJAQAAAA==.Varchemical:BAAALgAECgcJBwAAAA==.Varithal:BAACLgAFFH8PAAIeAAMJJhoyGgDdAAAeAAMJJhoyGgDdAAAuAAQKf0IAAh4ACQngIDUDABMDAB4ACQngIDUDABMDAAEuAAQKAQkBAAkAAAAA.Varri:BAAALgAECgMJBQAAAA==.Varðarvörðr:BAAALgAECgEJAQABLgAECgcJHgAFANoKAA==.Vastectomy:BAAALgAECggJCwAAAA==.',
Ve='Vegasana:BAAALgAFFAEJAwAAAA==.Velwing:BAAALgAECgUJBwAAAA==.Venawyn:BAABLgAECn8oAAIIAAgJmQuCcgBPAQAIAAgJmQuCcgBPAQAAAA==.Verakhaa:BAAALgAECgQJBAAAAA==.',
Vi='Vibepriest:BAAALgADCgEJAQAAAA==.Vindfaramaðr:BAABLgAECn8eAAIFAAcJ2gp4PgD5AAAFAAcJ2gp4PgD5AAAAAA==.Vixin:BAABLgAECn8YAAICAAcJbxHPTwBkAQACAAcJbxHPTwBkAQAAAA==.',
Vo='Voidsaack:BAAALgAECggJDQAAAA==.Voidz:BAAALgAECgEJAQAAAA==.Volfguar:BAAALgAECgQJAQAAAA==.Vortan:BAABLgAECn8oAAIhAAkJZBvqCACLAgAhAAkJZBvqCACLAgAAAA==.',
Vr='Vreya:BAAALgADCgkJFQABLgAECgUJDgAJAAAAAA==.',
Vy='Vynthus:BAAALgAECgcJEgAAAA==.',
['Vä']='Värys:BAAALgAECgEJAQAAAA==.',
Wa='Wan:BAAALgADCgEJAQAAAA==.Warhundin:BAEALgAECgYJDgABLgAFFAMJDQASADwIAA==.Warwan:BAAALgADCgIJAgAAAA==.Wazzbozz:BAAALgAECgQJAwAAAA==.Wazzdh:BAAALgAECgYJCgAAAA==.Wazzdot:BAAALgAECgUJEAAAAA==.Wazzhunnah:BAABLgAECn8nAAMhAAkJ0hTREgAOAgAhAAkJ0hTREgAOAgAmAAQJZAlhZQCqAAAAAA==.Wazzmage:BAAALgAECgMJAwAAAA==.',
We='Werg:BAAALgAECggJCgABLgAFFAUJCgAiAKUJAA==.',
Wh='Whatmyname:BAABLgAECn9EAAIiAAkJbgoEJQAXAQAiAAkJbgoEJQAXAQAAAA==.Whispp:BAAALgAECgYJCAAAAA==.',
Wi='Wildmandave:BAAALgADCgUJBQAAAA==.Willough:BAAALgAECgUJBwAAAA==.',
Wo='Wonsok:BAAALgAECgcJEAAAAA==.',
Wy='Wyvoker:BAABLgAECn8mAAIeAAkJPhvkBADJAgAeAAkJPhvkBADJAgAAAA==.',
['Wì']='Wìllow:BAAALgADCgIJAgAAAA==.',
['Wÿ']='Wÿm:BAABLgAECn8VAAIKAAgJFx3fIwBuAgAKAAgJFx3fIwBuAgABLgAECgkJJgAeAD4bAA==.',
Xa='Xaoleth:BAAALgADCgEJAQAAAA==.',
Xe='Xenorion:BAAALgAECgMJAwAAAA==.Xephora:BAAALgAECgEJBgAAAA==.',
Xi='Xiq:BAAALgADCgUJBQAAAA==.',
Xr='Xrinch:BAAALgADCgYJBgAAAA==.',
Xu='Xunadin:BAAALgAECgIJAgAAAA==.Xuny:BAAALgAECgUJEgAAAA==.',
Ya='Yarrggh:BAAALgADCgYJBgAAAA==.',
Yo='Yordi:BAAALgAECgUJEwAAAA==.',
Yu='Yuzuriha:BAACLgAFFH8PAAIIAAMJPyByRgAPAQAIAAMJPyByRgAPAQAuAAQKf0IAAggACQmQJJMEAEEDAAgACQmQJJMEAEEDAAAA.',
Za='Zaelia:BAAALgADCgYJBgABLgAECgkJOQASAOUeAA==.Zaletren:BAAALgAECgkJBQAAAA==.Zamaze:BAABLgAECn8nAAMVAAkJkCDkBgCPAgAVAAkJkCDkBgCPAgAXAAEJLwkweQAoAAAAAA==.Zannah:BAAALgAECgMJAwAAAA==.Zant:BAAALgAECgIJAQAAAA==.',
Ze='Zeekielle:BAEBLgAECn88AAIfAAkJFhXLEQD/AQAfAAkJFhXLEQD/AQABLgAFFAMJDQASADwIAA==.Zemesa:BAAALgAECgMJAwAAAA==.Zenius:BAABLgAECn8UAAIYAAcJQBFZFwBAAQAYAAcJQBFZFwBAAQAAAA==.Zerithrielle:BAABLgAECn8yAAIfAAgJRhhQEwDsAQAfAAgJRhhQEwDsAQAAAA==.',
Zi='Zippii:BAAALgAECgYJBwAAAA==.Zipy:BAABLgAECn83AAIcAAkJeR4+BgAHAwAcAAkJeR4+BgAHAwAAAA==.',
Zo='Zof:BAAALgAECgYJDgAAAA==.Zorathar:BAAALgADCgYJBgAAAA==.',
Zu='Zugtag:BAACLgAFFH8FAAIKAAMJ+SCKZgAiAQAKAAMJ+SCKZgAiAQAuAAQKfzcAAgoACQmHIQULAA4DAAoACQmHIQULAA4DAAAA.',
Zy='Zyllo:BAAALgAECgUJDQAAAA==.',
['Zá']='Závier:BAABLgAECn8UAAIEAAYJ/QKf+ACuAAAEAAYJ/QKf+ACuAAAAAA==.',
['Zõ']='Zõf:BAAALgAECgIJAwABLgAECgYJDgAJAAAAAA==.',
['Äe']='Äemond:BAAALgADCgMJAwAAAA==.',
['Ål']='Ålïce:BAACLgAFFH8GAAISAAMJjQiybgDBAAASAAMJjQiybgDBAAAuAAQKf1QAAhIACQnQH64OAOcCABIACQnQH64OAOcCAAAA.',
['Ëd']='Ëdward:BAAALgADCgcJCgABLgAECgUJEwAJAAAAAA==.',
['Ôh']='Ôhmyn:BAAALgAECgUJBQABLgAECggJGwASAFkNAA==.',
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
