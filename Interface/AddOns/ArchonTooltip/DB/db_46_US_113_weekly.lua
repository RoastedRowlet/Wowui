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

local lookup = {'Shaman-Elemental','Shaman-Restoration','Monk-Windwalker','Monk-Brewmaster','Monk-Mistweaver','Mage-Frost','DeathKnight-Blood','Warlock-Destruction','Hunter-BeastMastery','Unknown-Unknown','DeathKnight-Unholy','DeathKnight-Frost','Druid-Restoration','Druid-Feral','Druid-Balance','Paladin-Holy','Paladin-Protection','Warrior-Fury','Paladin-Retribution','Priest-Shadow','Warlock-Demonology','Warrior-Protection','Warrior-Arms','Shaman-Enhancement','Evoker-Devastation','Evoker-Augmentation','DemonHunter-Devourer','Priest-Discipline','Priest-Holy','Evoker-Preservation','DemonHunter-Havoc','DemonHunter-Vengeance','Hunter-Survival','Druid-Guardian','Warlock-Affliction','Mage-Fire','Mage-Arcane','Hunter-Marksmanship','Rogue-Subtlety','Rogue-Outlaw',}
local provider = {region='US',realm='GrizzlyHills',name='US',type='weekly',zone=46,date='2026-06-13',data={Ab='Abramz:BAAALgADCgMJAwAAAA==.',
Ad='Addly:BAAALgAFFAEJAQAAAA==.Adely:BAAALgAECgEJAQAAAA==.Adelymon:BAABLgAECn8ZAAMBAAkJlRfTFQA1AgABAAkJlRfTFQA1AgACAAUJARC9gwDSAAAAAA==.Adelymonk:BAABLgAECn8VAAQDAAcJtBRdJwB5AQADAAcJtBRdJwB5AQAEAAQJQwm6VQCtAAAFAAMJTAPHoQBOAAAAAA==.Adonysroth:BAAALgAECgIJAgAAAA==.Adrahil:BAAALgADCgIJAgAAAA==.',
Ae='Aeonra:BAAALgADCgIJAgAAAA==.',
Ag='Agronak:BAAALgAECgQJBgAAAA==.',
Al='Aldan:BAAALgADCgMJAwAAAA==.Aldazen:BAACLgAFFH8UAAIDAAQJmiSPBgCnAQADAAQJmiSPBgCnAQAuAAQKfzoAAgMACQkeJDwDAC4DAAMACQkeJDwDAC4DAAAA.Alenara:BAAALgAECgcJEQABLgAECgkJIwAGALoMAA==.Aletheìa:BAAALgAECgEJAQAAAA==.Alovan:BAAALgADCgEJAQABLgAECgcJHgAEANoKAA==.Alterbeast:BAAALgAECgUJBgABLgAFFAYJEAAHADoaAA==.Alyssandra:BAABLgAECn8qAAIIAAkJWxgYBAA/AgAIAAkJWxgYBAA/AgAAAA==.',
Am='Amarella:BAABLgAECn8UAAIJAAcJqiCkKQAQAgAJAAcJqiCkKQAQAgAAAA==.Amarrite:BAAALgAECgQJCQABLgAECgUJCAAKAAAAAA==.Ammalane:BAAALgAECgUJCAAAAA==.Amrah:BAAALgADCgYJBgAAAA==.Amunzo:BAAALgAECgEJAQABLgAECgkJEwAKAAAAAA==.',
An='Angler:BAAALgAECgMJAwAAAA==.Angyrolaj:BAABLgAECn8XAAMLAAcJ0xcsZACcAQALAAcJgBcsZACcAQAMAAIJdBUXEQCFAAAAAA==.',
Aq='Aquadora:BAAALgADCgMJAwAAAA==.',
Ar='Arangarr:BAABLgAECn8xAAMNAAkJpx3ODQDpAgANAAkJpx3ODQDpAgAOAAEJ1BEbTwA2AAAAAA==.Arcin:BAAALgADCgEJAQAAAA==.Areyana:BAABLgAECn8aAAIJAAkJVA/7SwC5AQAJAAkJVA/7SwC5AQAAAA==.Areyoudead:BAAALgAECgQJBAABLgADCgYJCwAKAAAAAA==.Ariolas:BAAALgADCgYJCQAAAA==.Aristoi:BAAALgAECgEJAQAAAA==.Arkand:BAAALgADCgUJBAAAAA==.Arkandra:BAABLgAECn8UAAIPAAYJOhZANQA+AQAPAAYJOhZANQA+AQAAAA==.Arkara:BAAALgADCgEJAQAAAA==.Arrietty:BAABLgAECn8oAAIQAAgJxRWOJgDSAQAQAAgJxRWOJgDSAQAAAA==.Arthues:BAABLgAECn8WAAIRAAgJDBy9CQAuAgARAAgJDBy9CQAuAgAAAA==.Arthâs:BAAALgAECgYJBQAAAA==.Arumathe:BAABLgAECn8XAAIRAAkJxxK8EQCmAQARAAkJxxK8EQCmAQAAAA==.',
As='Asura:BAACLgAFFH8TAAISAAQJWiQeDAChAQASAAQJWiQeDAChAQAuAAQKfyAAAhIACQnLItkIAB4DABIACQnLItkIAB4DAAAA.',
Au='Aurelian:BAAALgAECgEJAgAAAA==.',
Az='Az:BAABLgAECn8fAAISAAcJKya1DwB7AgASAAcJKya1DwB7AgAAAA==.Azeriall:BAACLgAFFH8TAAIBAAQJ4gvMLADaAAABAAQJ4gvMLADaAAAuAAQKf0cAAwEACQnUFgsYACECAAEACQnUFgsYACECAAIABAlKAVuGAHsAAAAA.Azerowolf:BAAALgADCggJCAAAAA==.Azráèl:BAAALgADCgMJAwAAAA==.',
Ba='Babyboom:BAAALgAECgEJAQAAAA==.Baconhammr:BAABLgAECn8iAAMTAAkJuA77YgCoAQATAAkJuA77YgCoAQAQAAYJegbWcwBlAAAAAA==.Badazmf:BAAALgADCgcJDAABLgAECgkJNAAUACEbAA==.Badcompany:BAAALgADCgUJBQABLgAECgkJNgANAMAOAA==.Baddream:BAAALgAECgYJDgAAAA==.Baelmyre:BAAALgADCgUJBQAAAA==.Balenciagosa:BAAALgADCgUJBQABLgAECgkJIwAGALoMAA==.Banshiï:BAABLgAECn84AAIIAAkJiROABwDYAQAIAAkJiROABwDYAQAAAA==.Baratheøn:BAABLgAECn8uAAINAAkJ+xYvIgA0AgANAAkJ+xYvIgA0AgAAAA==.Bax:BAAALgADCgIJAgAAAA==.Baxar:BAAALgAECgIJAgAAAA==.',
Bb='Bbd:BAAALgAECggJCQABLgAECgYJDgAKAAAAAA==.',
Be='Beanz:BAAALgAECgEJAQAAAA==.Beeftard:BAABLgAECn8YAAIQAAkJWRZiKgDfAQAQAAkJWRZiKgDfAQAAAA==.Bellavix:BAAALgADCgMJBAAAAA==.Benafflic:BAAALgAECgEJAQABLgAECgUJCQAKAAAAAA==.Berserrk:BAAALgADCgYJBgAAAA==.Bershale:BAAALgAECgEJAQABLgAECgYJBwAKAAAAAA==.',
Bi='Bifficus:BAAALgAECgcJEAAAAA==.Big:BAAALgADCgMJBAAAAA==.Biggiecheese:BAAALgAECgMJBAAAAA==.',
Bl='Blackscorn:BAAALgADCgEJAQAAAA==.Blackthôrne:BAAALgAECgYJCwAAAA==.Blucki:BAABLgAECn8fAAIVAAgJ7QlgiAAoAQAVAAgJ7QlgiAAoAQAAAA==.',
Bo='Bobfu:BAAALgADCgYJCAAAAA==.',
Br='Brieze:BAAALgADCgIJAgAAAA==.Brige:BAAALgAECggJBgAAAA==.Brightstar:BAAALgADCgEJAQAAAA==.Brimaz:BAAALgADCgEJAQAAAA==.',
Bu='Buhhead:BAAALgADCgUJBgAAAA==.Bunana:BAAALgADCgEJAQAAAA==.Bunbear:BAAALgAECgIJAgAAAA==.Bunette:BAAALgADCgEJAQAAAA==.',
Bw='Bwamsamdi:BAAALgADCgYJBgAAAA==.',
By='Byzantium:BAABLgAECn8tAAIWAAkJiQhlHgA9AQAWAAkJiQhlHgA9AQAAAA==.',
['Bô']='Bônebeard:BAAALgAECgEJAQAAAA==.',
Ca='Cabledryer:BAAALgAECgQJEAAAAA==.Caelidpackx:BAAALgADCgYJBwAAAA==.Cakron:BAAALgAECgUJBQABLgAECgkJEwAKAAAAAA==.Calamitty:BAAALgAECgMJAwAAAA==.Calistin:BAAALgAECgYJBgAAAA==.Callmedatty:BAAALgAECgEJAQAAAA==.Caluu:BAAALgADCgEJAQAAAA==.Carnry:BAAALgADCgQJBAAAAA==.Catboy:BAABLgAECn8fAAIGAAkJNhZ9bACfAQAGAAkJNhZ9bACfAQAAAA==.Catnips:BAABLgAECn8cAAITAAgJURjbbACSAQATAAgJURjbbACSAQAAAA==.Catpow:BAAALgAECgkJAgAAAA==.',
Ch='Chanaranach:BAAALgAECgYJCgAAAA==.Charitey:BAAALgAECgMJBAAAAA==.Cheelo:BAAALgAECgkJEgAAAA==.Chknnugget:BAAALgAECgMJBQAAAA==.Chromatic:BAABLgAECn8xAAMCAAkJERgnKAAaAgACAAgJphYnKAAaAgABAAYJghGhOgBHAQAAAA==.',
Ci='Cindrethresh:BAAALgAECgQJCQAAAA==.',
Co='Coffeeblak:BAABLgAECn8ZAAMDAAgJBRNLJgCmAQADAAcJlxNLJgCmAQAFAAUJFQ65PwDkAAAAAA==.Coldstorm:BAAALgAECgcJCwAAAA==.Collision:BAAALgAECgkJEgAAAA==.Compensating:BAAALgADCgYJBgAAAA==.Connor:BAAALgADCgcJBwAAAA==.Connsumption:BAAALgAECgYJCgAAAA==.Corrine:BAAALgAECgYJCwAAAA==.',
Cr='Crazybatt:BAABLgAECn8UAAITAAYJXQag8wDDAAATAAYJXQag8wDDAAAAAA==.Crypt:BAAALgAECgYJCgAAAA==.',
Cu='Cuckchairpov:BAACLgAFFH8OAAMEAAQJJRSiIwAYAQAEAAQJpBOiIwAYAQADAAIJQg15DACgAAAuAAQKfywAAwMACQkqH2gKANICAAMACAl4HWgKANICAAQACQndFBUVAAICAAAA.',
Cy='Cynderleena:BAAALgAECgcJCAAAAA==.Cynyia:BAABLgAECn8vAAIJAAkJxRMrKwAIAgAJAAkJxRMrKwAIAgAAAA==.',
Cz='Czk:BAAALgADCgYJBgABLgAECggJGQADAAUTAA==.',
['Có']='Cóldblóód:BAAALgAECgIJAgAAAA==.',
Da='Daddyelessar:BAAALgAECggJEgAAAA==.Dafattyup:BAABLgAECn8aAAIVAAYJlRxUYwCgAQAVAAYJlRxUYwCgAQAAAA==.Daghmar:BAAALgADCgUJBQAAAA==.Dagon:BAAALgAECgMJAwAAAA==.Dakotarain:BAAALgADCgIJAgAAAA==.Dalerontwo:BAAALgADCgEJAQAAAA==.Darruin:BAACLgAFFH8OAAMLAAgJ0B6LCACWAgALAAcJ0B6LCACWAgAHAAEJAADUYAAAAAAuAAQKfygAAgsACQlAJNMFAEoDAAsACQlAJNMFAEoDAAAA.Dayrun:BAAALgAECgUJDQAAAA==.',
De='Deadicee:BAAALgAECgIJAgABLgAECgYJFAATAHwOAA==.Deadlyvixin:BAAALgAECgEJAQAAAA==.Deadstorm:BAAALgAECgUJBQAAAA==.Deathturtle:BAABLgAECn8eAAILAAgJLxB+kgA/AQALAAgJLxB+kgA/AQAAAA==.Deavaos:BAAALgAECgcJCwAAAA==.Dedmartigan:BAAALgADCgUJBQAAAA==.Deeanndra:BAABLgAECn8sAAMLAAkJchIyRwDqAQALAAkJchIyRwDqAQAMAAEJDAkNPwAmAAAAAA==.Deevz:BAAALgAECgIJAgAAAA==.Demandred:BAAALgAECgYJCQAAAA==.Demiz:BAABLgAECn84AAMCAAkJ5RoVFwCNAgACAAkJ5RoVFwCNAgABAAcJug5xRwASAQAAAA==.Deredris:BAAALgAECgQJBAABLgAECgYJCgAKAAAAAA==.Dertka:BAAALgAECgYJDAAAAA==.',
Di='Diiviiniity:BAAALgAECgEJAQAAAA==.Discodruid:BAABLgAECn8UAAINAAYJKRNgUwA/AQANAAYJKRNgUwA/AQAAAA==.Dishsoap:BAAALgAECgMJAwABLgAFFAYJGAASACAYAA==.Dixie:BAAALgAECgEJAQAAAA==.',
Dj='Djall:BAAALgAFFAEJAQAAAA==.Djöflaveiðim:BAAALgAECgIJAgABLgAECgcJHgAEANoKAA==.',
Do='Dommy:BAABLgAECn8bAAIHAAkJ1iTWAQA9AwAHAAkJ1iTWAQA9AwAAAA==.Domw:BAAALgAECgYJDAABLgAECgkJGwAHANYkAA==.Donham:BAACLgAFFH8XAAMLAAYJ9xuiMwCRAQALAAUJ9xuiMwCRAQAHAAEJAABBEwBZAAAuAAQKfx8AAgsACAnLHzweAMsCAAsACAnLHzweAMsCAAAA.Dorkimedes:BAAALgAECgQJDAAAAA==.Dottie:BAABLgAECn8oAAMIAAgJNhM2FwCQAQAIAAcJJQ82FwCQAQAVAAgJ7xG5XgCCAQAAAA==.Dotvinci:BAAALgAECgYJBgAAAA==.',
Dr='Draelesh:BAABLgAECn89AAIPAAkJwhOVGgDzAQAPAAkJwhOVGgDzAQAAAA==.Draenk:BAAALgADCgUJBQAAAA==.Dragún:BAAALgAECgYJCwAAAA==.Drakari:BAAALgADCgYJBgAAAA==.Dramborleg:BAAALgAECgEJAQAAAA==.Drazon:BAAALgADCgIJAgAAAA==.Drewit:BAABLgAECn8WAAIOAAYJPxA1FQBiAQAOAAYJPxA1FQBiAQAAAA==.',
Du='Ducan:BAAALgADCgYJCQAAAA==.Dudeabides:BAAALgAECgMJAwABLgAECgkJGQACAJsOAA==.Duskmane:BAAALgAECgMJCAAAAA==.',
Dw='Dwadler:BAACLgAFFH8PAAMXAAYJCBBKFwAhAQAXAAYJCBBKFwAhAQAWAAMJQxHBHACqAAAuAAQKfzYAAxYACQmsHaIGAJ0CABYACQmsHaIGAJ0CABcABQkmFYkwAAEBAAAA.',
Dy='Dyrkonian:BAAALgAECggJEgAAAA==.',
Ei='Eireann:BAAALgADCgcJCQAAAA==.',
El='Elerrak:BAAALgAECgEJAQABLgAFFAcJIQAYAJ0dAA==.Elindalia:BAAALgAECgMJAwAAAA==.',
Em='Emberash:BAAALgAECgEJAQAAAA==.Embre:BAABLgAFFH8MAAMZAAUJsA5pBQAMAQAZAAQJsA5pBQAMAQAaAAEJAADzbgAAAAAAAA==.Emorri:BAAALgAECgYJBgAAAA==.Empyrea:BAAALgAECgQJBQAAAA==.',
Er='Eraina:BAAALgADCgIJAgAAAA==.Ericles:BAABLgAECn8ZAAMXAAcJ8R1VDADbAQAXAAcJ8R1VDADbAQASAAIJlAVwlwBkAAAAAA==.Erys:BAAALgAECgcJEQAAAA==.Erébus:BAABLgAECn8iAAIbAAkJ7xjhJwAoAgAbAAkJ7xjhJwAoAgAAAA==.',
Ev='Ev:BAAALgAECgQJBAAAAA==.Evergreene:BAAALgAECgEJAQABLgAECgUJCAAKAAAAAA==.Evlpotato:BAABLgAECn80AAQUAAkJIRvzEgA6AgAUAAkJIRvzEgA6AgAcAAcJNBq3HwDNAQAdAAEJlAdTfwAzAAAAAA==.Evojak:BAABLgAECn8jAAMaAAkJJQrKMwBhAQAaAAkJJQrKMwBhAQAZAAMJxANWHQBgAAAAAA==.',
Fa='Fabiyo:BAAALgADCgMJBQAAAA==.Faevelia:BAAALgAECgUJBgAAAA==.Fairaday:BAACLgAFFH8FAAIJAAMJugF6fwCSAAAJAAMJugF6fwCSAAAuAAQKfzcAAgkACQlfC05VAJ8BAAkACQlfC05VAJ8BAAAA.Falloon:BAAALgADCgYJBgAAAA==.Fanshen:BAAALgAECgMJBQAAAA==.Farmerdave:BAAALgAECgEJAQAAAA==.Fatdoinkz:BAAALgAECgUJCQABLgAFFAYJEAAHADoaAA==.Fauchi:BAAALgADCgEJAQAAAA==.Faxqueenmage:BAABLgAECn8bAAIGAAcJgQLe8QC9AAAGAAcJgQLe8QC9AAAAAA==.',
Fe='Felador:BAAALgAECgcJEgABLgAECgkJMgAVAIQVAA==.Feldo:BAABLgAECn8SAAIbAAYJjyG/OQDcAQAbAAYJjyG/OQDcAQAAAA==.Felmès:BAAALgADCgYJBgABLgAECgkJIwAGALoMAA==.Fennec:BAAALgAECgUJDAAAAA==.Feralarak:BAAALgAECgcJEwABLgAFFAcJIQAYAJ0dAA==.',
Fi='Firebrandd:BAACLgAFFH8cAAMZAAYJzxx5AgBeAQAZAAUJnyB5AgBeAQAaAAUJZhEGIgBJAQAuAAQKf0IAAxoACQl8IyEEACcDABoACQmzIiEEACcDABkACAlIImACAA8DAAEuAAUUCAkOAAsA0B4A.Fizehbubbleh:BAEALgAECgYJCAABLgAECggJIAABAOgaAA==.Fizehtotems:BAEBLgAECn8gAAMBAAgJ6Bo5LQCLAQABAAgJ6Bo5LQCLAQACAAUJixbCXQA+AQAAAA==.',
Fl='Fleshoracle:BAAALgAECgQJBAABLgAFFAYJEAAHADoaAA==.Fluctuates:BAAALgAECgQJCAAAAA==.',
Fo='Foragarn:BAAALgAECgYJCQAAAA==.Foron:BAAALgAECgIJAgAAAA==.',
Fr='Frankkastle:BAAALgAECgYJDwAAAA==.Frazelia:BAAALgADCgkJDgABLgAECgYJFgAOAD8QAA==.Fribble:BAABLgAECn8ZAAMCAAkJmw6LOgDAAQACAAkJmw6LOgDAAQAYAAEJAAC4SAAAAAAAAA==.Froggierlynx:BAAALgAFFAQJBAAAAA==.Frostalot:BAAALgAECgMJAwAAAA==.Froznfate:BAABLgAECn84AAMRAAkJaiXbAABXAwARAAkJaiXbAABXAwATAAIJpQdBXgFRAAAAAA==.Fryes:BAAALgAECgkJDAAAAA==.',
Fu='Fuzziebutt:BAAALgAECgQJBgAAAA==.',
Fw='Fwibble:BAAALgAECggJEgABLgAECgkJGQACAJsOAA==.',
Fy='Fyrelady:BAAALgADCggJDgABLgAECgUJDgAKAAAAAA==.Fyrestone:BAAALgAECgUJDgAAAA==.',
['Fæ']='Fæder:BAAALgADCgYJBgAAAA==.',
Ga='Gabarnak:BAAALgADCgIJAgABLgAECggJGwAFAKEfAA==.Gabuse:BAAALgAECgQJBAAAAA==.Galencharred:BAABLgAECn8jAAITAAgJqQjWpwApAQATAAgJqQjWpwApAQAAAA==.Garagon:BAABLgAECn89AAIeAAkJ9RYvCQBTAgAeAAkJ9RYvCQBTAgAAAA==.Gauss:BAABLgAECn8dAAIRAAgJoAZYJgDfAAARAAgJoAZYJgDfAAABLgAECgkJGQACAJsOAA==.Gaîîa:BAABLgAECn8cAAIJAAgJCRq2MADtAQAJAAgJCRq2MADtAQAAAA==.',
Ge='Gelber:BAAALgAECgQJBAAAAA==.Gerva:BAABLgAECn86AAILAAkJORSHNAAqAgALAAkJORSHNAAqAgAAAA==.',
Gh='Ghlain:BAAALgAECgQJBwAAAA==.Ghorfindor:BAABLgAECn8pAAIfAAgJyQSyOQDNAAAfAAgJyQSyOQDNAAAAAA==.Ghostlybrew:BAACLgAFFH8VAAIEAAcJ9xvmBACHAQAEAAcJ9xvmBACHAQAuAAQKfxYAAgQACAmpH94TAHECAAQACAmpH94TAHECAAAA.',
Gi='Gigastorm:BAAALgADCgIJAQAAAA==.Gilas:BAABLgAECn8vAAQLAAkJRw2VYgCgAQALAAkJ8QqVYgCgAQAHAAYJcBAGMgDSAAAMAAUJXgWDJwCRAAAAAA==.',
Gl='Glaivemstake:BAAALgADCgcJBwAAAA==.',
Gn='Gnik:BAAALgAECgkJEgAAAA==.Gnikole:BAAALgAECgIJAgABLgAECgkJEgAKAAAAAA==.Gnoeme:BAAALgAECgEJAgAAAA==.',
Go='Goswin:BAAALgAECgIJBAAAAA==.',
Gr='Graahak:BAAALgADCgMJAwAAAA==.Graveborn:BAABLgAFFH8QAAIHAAYJOhpbDwCCAQAHAAYJOhpbDwCCAQAAAA==.Graydenton:BAAALgAECgkJCQABLgAECggJBgAKAAAAAA==.Greenfelpowa:BAABLgAECn8ZAAIVAAkJpQ/xSAC/AQAVAAkJpQ/xSAC/AQAAAA==.Gruu:BAAALgAECgEJAQAAAA==.Gruuven:BAAALgAECgcJBwAAAA==.',
Gu='Gutmtmon:BAABLgAECn8YAAIDAAgJTwdoQQD2AAADAAgJTwdoQQD2AAAAAA==.',
Gw='Gwenivive:BAABLgAECn8hAAIJAAkJjBcxKgAxAgAJAAkJjBcxKgAxAgAAAA==.',
['Gí']='Gízmo:BAAALgADCgUJBQAAAA==.',
Ha='Haenus:BAABLgAECn8dAAIbAAgJ8hPsewAkAQAbAAgJ8hPsewAkAQAAAA==.Hamor:BAAALgAECgkJCgAAAA==.Harrynear:BAAALgADCgMJAwABLgAECgcJFwALANMXAA==.Hat:BAACLgAFFH8FAAIbAAIJ9CK3YgDCAAAbAAIJ9CK3YgDCAAAuAAQKfxkAAxsACQl8Ih4HABkDABsACQl8Ih4HABkDACAAAgmRCnksAE0AAAAA.Haunt:BAAALgAECgUJBgAAAA==.Havark:BAAALgAECgMJAwAAAA==.',
He='Healbilly:BAAALgADCgEJAQAAAA==.Healingdeath:BAAALgADCgMJBAAAAA==.Hecatombe:BAAALgADCgUJBQAAAA==.Hellzdruid:BAAALgADCgQJBAAAAA==.Hellzknîght:BAABLgAECn8iAAILAAgJfBJsZACcAQALAAgJfBJsZACcAQAAAA==.Hellzshaman:BAAALgADCgIJAQAAAA==.Heyah:BAAALgADCgIJAgAAAA==.',
Ho='Holek:BAABLgAECn8ZAAMJAAgJphGNUgCnAQAJAAgJphGNUgCnAQAhAAMJcASxSwCDAAAAAA==.Holgo:BAACLgAFFH8NAAIWAAYJRiOlAgBhAgAWAAYJRiOlAgBhAgAuAAQKfyEAAhYACQluJdYBADcDABYACQluJdYBADcDAAAA.Holgy:BAACLgAFFH8cAAIiAAYJliSRAgASAgAiAAYJliSRAgASAgAuAAQKfyYAAiIACQlWI0wBAEkDACIACQlWI0wBAEkDAAAA.Holybeard:BAACLgAFFH8NAAITAAUJaRTcVAAAAQATAAUJaRTcVAAAAQAuAAQKfzkAAhMACAnyIEAfAIoCABMACAnyIEAfAIoCAAAA.Hooks:BAAALgAECgQJCAAAAA==.',
Hu='Hugecowballs:BAAALgAECgkJCQAAAA==.Hunterturtle:BAAALgADCgUJBQAAAA==.',
Ic='Icia:BAAALgAECgEJAQABLgAECgUJBgAKAAAAAA==.',
Id='Idontmiss:BAAALgAECgIJCAAAAA==.',
Il='Ilickboody:BAAALgADCgQJBAAAAA==.Illustra:BAABLgAECn8aAAMdAAgJnAYCOgALAQAdAAgJnAYCOgALAQAUAAcJ3gJlWQCrAAABLgAECgkJIwAGALoMAA==.',
Im='Imaeru:BAAALgAECgMJAwAAAA==.Imcaldo:BAAALgADCgYJBgAAAA==.Imcaldoo:BAAALgADCgUJCgAAAA==.',
In='Interrupt:BAAALgAECgUJDQAAAA==.',
Ir='Irox:BAAALgADCgMJAwAAAA==.',
Is='Isaic:BAAALgADCgIJAgAAAA==.Iseila:BAABLgAECn8ZAAIGAAkJ+A2JZQCvAQAGAAkJ+A2JZQCvAQAAAA==.Isevio:BAAALgAECgMJBwAAAA==.',
It='Ithorus:BAAALgAECgYJEgAAAA==.',
Ja='Jaadb:BAAALgAECgQJBwAAAA==.Jaadd:BAAALgAECgIJAgAAAA==.Jaadi:BAAALgAECgIJAwAAAA==.Jaata:BAAALgADCgcJEAAAAA==.Jairl:BAAALgAECgQJBwAAAA==.Jamien:BAABLgAECn89AAMTAAkJ5R56GACuAgATAAkJ5R56GACuAgAQAAUJigUsdwCdAAAAAA==.Janal:BAAALgADCgEJAQAAAA==.Jasnah:BAABLgAECn8bAAMBAAgJyxQFJQC9AQABAAgJyxQFJQC9AQACAAMJnBPakACwAAAAAA==.Jasnos:BAAALgAECgUJDwAAAA==.',
Jd='Jdk:BAAALgAECgUJBwAAAA==.',
Je='Jelf:BAAALgAECgUJCAAAAA==.Jenzing:BAABLgAECn8VAAMVAAgJqh0QKwBjAgAVAAcJqh0QKwBjAgAjAAEJAACuIwBjAAAAAA==.Jessemyn:BAABLgAECn8aAAQbAAYJrQlzuQCzAAAbAAYJ1AVzuQCzAAAfAAQJAAh+WABZAAAgAAEJZxA8NAAwAAAAAA==.',
Jh='Jholy:BAAALgAECgkJAwAAAA==.',
Jo='Jobokenhones:BAACLgAFFH8FAAIbAAMJPg02agCxAAAbAAMJPg02agCxAAAuAAQKfzEAAhsACQkgGmUjAEACABsACQkgGmUjAEACAAAA.Johadgan:BAAALgADCgEJAQAAAA==.',
Jp='Jproudmore:BAAALgADCgUJBQABLgADCgYJCwAKAAAAAA==.',
Js='Jsberg:BAABLgAECn8eAAISAAgJwRViLgCWAQASAAgJwRViLgCWAQAAAA==.',
Ka='Kaathe:BAABLgAECn8lAAMGAAYJGx7ihADHAQAGAAYJGx7ihADHAQAkAAEJjhqXDwA4AAAAAA==.Kaboomalis:BAAALgADCgUJBQAAAA==.Kadance:BAABLgAECn8WAAIBAAcJmRbNMwBpAQABAAcJmRbNMwBpAQAAAA==.Kaelyn:BAAALgAECgQJBAABLgAFFAMJCgANAKsaAA==.Kaidiis:BAABLgAECn8uAAITAAkJzA6qZACkAQATAAkJzA6qZACkAQAAAA==.Kaido:BAAALgAECgEJAQAAAA==.Kalder:BAAALgADCgcJBwAAAA==.Karbonn:BAABLgAECn8aAAIZAAkJZRSPBQABAgAZAAkJZRSPBQABAgAAAA==.Kay:BAAALgAECgcJBwAAAA==.Kazeraz:BAAALgADCgEJAQAAAA==.',
Ke='Kegbreaker:BAACLgAFFH8FAAIdAAMJIwbIJgCGAAAdAAMJIwbIJgCGAAAuAAQKfzcAAh0ACQlQCrMrAGcBAB0ACQlQCrMrAGcBAAAA.',
Kh='Khanas:BAABLgAECn8aAAMQAAkJRhVmJADgAQAQAAgJHRZmJADgAQATAAEJOQJfyAEYAAAAAA==.Kheru:BAAALgAECgUJBgAAAA==.Khoan:BAAALgAECgYJCgAAAA==.',
Ki='Kimbliddan:BAAALgAECgIJAgABLgAFFAMJBgAGAFgaAA==.Kimbustible:BAACLgAFFH8GAAIGAAMJWBpucgD/AAAGAAMJWBpucgD/AAAuAAQKfzkAAgYACQk4JBwOAAcDAAYACQk4JBwOAAcDAAAA.Kimchi:BAABLgAECn8WAAIEAAgJlhBzJwByAQAEAAgJlhBzJwByAQABLgAFFAMJBgAGAFgaAA==.',
Kn='Knockknocko:BAAALgAECgcJDgAAAA==.',
Ko='Kobir:BAAALgADCgEJAQAAAA==.Komodostyle:BAABLgAECn86AAQeAAkJYg1DFwBYAQAeAAgJywpDFwBYAQAaAAYJ9RKgPQAwAQAZAAIJWw64NQBoAAAAAA==.Koobideh:BAAALgADCgEJAQAAAA==.',
Kr='Krayose:BAAALgAECggJEQAAAA==.Krian:BAAALgADCgEJAQAAAA==.Kriddler:BAAALgADCgQJBAAAAA==.Krisarugala:BAABLgAECn8VAAIPAAcJgA0CQgABAQAPAAcJgA0CQgABAQAAAA==.',
Ku='Kujoluvsmilf:BAAALgAECggJCwAAAA==.Kunuku:BAAALgADCgUJBQAAAA==.Kurash:BAAALgADCgcJBwAAAA==.Kurion:BAAALgAECgkJDgAAAA==.Kurogami:BAAALgAECgUJDQAAAA==.',
Ky='Kylesxmom:BAACLgAFFH8UAAMLAAYJDRAxRwBfAQALAAUJDRAxRwBfAQAHAAIJuA04PwAvAAAuAAQKf2AAAwsACQltJOUHADMDAAsACQlAJOUHADMDAAcACAn/HY4RAPEBAAAA.Kymal:BAABLgAECn88AAIbAAkJzRV7NgDpAQAbAAkJzRV7NgDpAQAAAA==.Kymbria:BAAALgADCgUJCAAAAA==.Kymora:BAAALgADCgcJBwAAAA==.Kyndrissa:BAAALgADCgUJBQAAAA==.',
['Kë']='Këy:BAACLgAFFH8MAAILAAMJQBhclQDfAAALAAMJQBhclQDfAAAuAAQKfykAAgsACAnUHYwsAIYCAAsACAnUHYwsAIYCAAAA.',
La='Latrice:BAACLgAFFH8pAAIGAAgJECMbBwDBAgAGAAgJECMbBwDBAgAuAAQKfygABAYACQk5I9wJAHYDAAYACQk5I9wJAHYDACQAAwm4GU0KAM8AACUAAQltGN0YAFEAAAAA.Lavynder:BAABLgAECn8XAAIbAAgJ5hUVWgCTAQAbAAgJ5hUVWgCTAQAAAA==.Lazerturkey:BAAALgAECgkJDwAAAA==.Laërtes:BAAALgAECgUJEwAAAA==.',
Le='Leiamirage:BAAALgAECgYJDwAAAA==.Leviscus:BAAALgAECgUJDwAAAA==.',
Li='Lifetap:BAAALgADCgMJAwAAAA==.Lightbill:BAAALgAFFAMJAwAAAA==.Lightbàne:BAABLgAECn8qAAIOAAkJ2CLOAQAbAwAOAAkJ2CLOAQAbAwAAAA==.Lightningrod:BAAALgAECgYJBwAAAA==.Lightrogue:BAAALgAECgUJBQABLgAECgkJKgAOANgiAA==.Lightshaolin:BAAALgAECgQJBAAAAA==.Lildruidz:BAABLgAECn8dAAMNAAcJbhNfPwCSAQANAAcJbhNfPwCSAQAPAAEJLQLFpAAYAAAAAA==.Lillivarak:BAABLgAECn8UAAITAAcJFgdF1ADqAAATAAcJFgdF1ADqAAAAAA==.Lilriotz:BAAALgAECgcJCgAAAA==.Lilriotzz:BAABLgAECn8eAAICAAkJ7RqREADIAgACAAkJ7RqREADIAgAAAA==.Lilzdrlockz:BAAALgAECgUJCgAAAA==.Lithedra:BAAALgADCgcJDwAAAA==.Littlehand:BAAALgADCgUJBAABLgAECggJKAAQAMUVAA==.',
Lo='Loot:BAAALgAFFAQJBAAAAA==.Lovecraft:BAAALgAECgMJAwAAAA==.',
Lu='Lucavi:BAAALgAECgMJAwAAAA==.Lucyvar:BAABLgAECn8WAAIfAAcJHwkZNADrAAAfAAcJHwkZNADrAAAAAA==.Luke:BAAALgADCgUJBwAAAA==.Luma:BAAALgAECgUJDQAAAA==.Luther:BAABLgAECn8XAAIEAAkJNw9XJQDYAQAEAAkJNw9XJQDYAQAAAA==.',
Ly='Lyla:BAAALgADCgQJBgAAAA==.',
Ma='Magnux:BAAALgAECgEJAgAAAA==.Malazark:BAAALgADCgYJBgAAAA==.Malríus:BAAALgAECgQJEQAAAA==.Manales:BAAALgAECgcJBgAAAA==.Marhukai:BAACLgAFFH8FAAITAAMJoBh7YQDlAAATAAMJoBh7YQDlAAAuAAQKfy8AAhMACQlBHxsYALACABMACQlBHxsYALACAAAA.Marotal:BAABLgAECn8oAAIGAAkJ2RImRQAJAgAGAAkJ2RImRQAJAgAAAA==.Marr:BAAALgADCgUJBQAAAA==.Martysparty:BAABLgAECn8yAAIRAAkJER3wBgBwAgARAAkJER3wBgBwAgAAAA==.Mavaena:BAAALgAECgYJDAAAAA==.Mavrane:BAAALgADCgEJAgAAAA==.',
Me='Meashakegs:BAAALgAECggJEQAAAA==.Meashaman:BAAALgAECgMJAwAAAA==.Mechaboomer:BAABLgAECn88AAIJAAkJ0h0yFgCfAgAJAAkJ0h0yFgCfAgAAAA==.Megafire:BAAALgAECgMJBAAAAA==.Megahertz:BAAALgAECgcJCgAAAA==.Melcanthet:BAAALgADCggJCAAAAA==.Mellowrock:BAAALgAECgUJBgABLgAECgYJBQAKAAAAAA==.',
Mi='Mickhaggis:BAAALgADCgIJAgAAAA==.Micktarogar:BAAALgAECgcJEwAAAA==.Mickwutang:BAAALgAFFAEJAQAAAA==.Miklaga:BAAALgAECgEJAgAAAA==.Milince:BAAALgADCgMJAgAAAA==.Milkfridge:BAAALgAECgEJAQABLgAFFAMJBQAOAF4EAA==.Minikloon:BAAALgAECgYJDgAAAA==.Minphoria:BAAALgADCgQJBgAAAA==.Missylock:BAAALgADCgYJBgAAAA==.Mistilinn:BAACLgAFFH8FAAImAAMJ+wB4JACCAAAmAAMJ+wB4JACCAAAuAAQKfyoAAiYACQldB9cSACwBACYACQldB9cSACwBAAAA.Miyri:BAAALgAECgEJBAABLgAFFAMJCgANAKsaAA==.',
Mo='Mollyporph:BAAALgAECgEJAQAAAA==.Monoco:BAAALgAECgYJEwAAAA==.Moopandax:BAACLgAFFH8cAAIPAAcJFx23BwAYAgAPAAcJFx23BwAYAgAuAAQKf2EAAw8ACQmIJl0AAJIDAA8ACQmIJl0AAJIDACIACAmhH9kHAHACAAEuAAUUBQkbAA8AYCIA.Mortrum:BAAALgADCgQJBAAAAA==.Moxestime:BAAALgAECgEJAgAAAA==.Moxsdeath:BAAALgADCgYJBgAAAA==.Moxsdeaths:BAAALgADCgcJBwAAAA==.',
Mu='Mushaboom:BAABLgAECn8aAAIEAAkJVQcoLgBKAQAEAAkJVQcoLgBKAQAAAA==.Muzzler:BAABLgAECn9iAAIGAAkJoyT6BABbAwAGAAkJoyT6BABbAwAAAA==.',
My='Myeyes:BAAALgAECgEJAwAAAA==.Mylinkah:BAAALgADCgQJBAAAAA==.Mynamefizz:BAEBLgAECn8XAAQVAAkJNBlvMgANAgAVAAkJ9xVvMgANAgAjAAMJeh39GAD1AAAIAAMJghQFIACoAAABLgAECggJIAABAOgaAA==.Myotonic:BAAALgADCgQJBAAAAA==.Mythlok:BAAALgAECgMJAwAAAA==.Mythreiel:BAAALgAECgUJBgAAAA==.Mythykal:BAAALgAECgUJBwAAAA==.',
['Mé']='Méasha:BAAALgAECgkJCgAAAA==.',
Na='Nachtmar:BAAALgAECgQJBAABLgAECgkJGgATAIkPAA==.Nadis:BAAALgAECgIJAwAAAA==.Narcessa:BAAALgADCgQJBAAAAA==.Nawk:BAAALgAECgEJAQAAAA==.',
Ne='Nennerb:BAAALgADCgQJBAAAAA==.',
Ni='Nicola:BAAALgAECgcJDwAAAA==.Nightxwish:BAABLgAECn8oAAIcAAgJJBxhDQCVAgAcAAgJJBxhDQCVAgAAAA==.Niranye:BAAALgADCgEJAQAAAA==.',
No='Noisemarine:BAACLgAFFH8VAAIWAAQJvxWYFAD2AAAWAAQJvxWYFAD2AAAuAAQKfxwAAhYACQktGqUKAEACABYACQktGqUKAEACAAAA.Nokk:BAAALgADCgEJAQAAAA==.Nokkco:BAAALgAECgEJAgAAAA==.Norellia:BAAALgAECgQJCAAAAA==.Northleo:BAAALgADCgcJEQAAAA==.Northspirit:BAABLgAECn8ZAAIBAAUJEwYycgCPAAABAAUJEwYycgCPAAAAAA==.',
Nu='Nuit:BAAALgADCgUJBQABLgAECgYJCwAKAAAAAA==.',
Ny='Nyarlothep:BAAALgAECgQJBAAAAA==.Nyx:BAAALgAECgUJBQABLgAECgkJPQATAOUeAA==.',
Oa='Oakenshièld:BAAALgAECgcJDAAAAA==.',
Od='Odindh:BAAALgAFFAIJAwABLgAFFAMJBAAKAAAAAA==.Odins:BAAALgAFFAMJBAAAAA==.',
Oh='Ohwhelp:BAABLgAFFH8IAAIaAAMJ5BkiOQDfAAAaAAMJ5BkiOQDfAAABLgAFFAgJLgAPAI4kAA==.Ohyikers:BAACLgAFFH8uAAIPAAgJjiRlAQDjAgAPAAgJjiRlAQDjAgAuAAQKfzYAAg8ACQnXJoEAAIwDAA8ACQnXJoEAAIwDAAAA.',
Ok='Oken:BAAALgADCgUJBQAAAA==.',
Om='Om:BAAALgADCgcJCQAAAA==.',
On='Onlyspirits:BAAALgAECgEJAQAAAA==.',
Op='Open:BAAALgADCgcJBwABLgAECggJKAAQAMUVAA==.Opportunity:BAAALgAECgYJBgABLgAFFAMJCwAQAMUeAA==.',
Or='Orklock:BAAALgADCgMJAwAAAA==.',
Pa='Pallek:BAAALgAECgcJBwABLgAECggJGQAJAKYRAA==.Palli:BAABLgAECn8dAAIQAAcJ8BWmLwCZAQAQAAcJ8BWmLwCZAQAAAA==.Paogao:BAAALgAECgUJBgAAAA==.Parry:BAAALgADCgQJBAAAAA==.Pasghetti:BAAALgADCgMJAwAAAA==.Pasta:BAABLgAECn8rAAInAAkJSh4tCACiAgAnAAkJSh4tCACiAgAAAA==.',
Pe='Perpetual:BAAALgAECgEJAgAAAA==.Pewpewbite:BAABLgAECn8UAAIJAAkJOh8zDwDTAgAJAAkJOh8zDwDTAgAAAA==.',
Ph='Phantomarrow:BAACLgAFFH8VAAQhAAUJQRNlGAAKAQAhAAQJGAxlGAAKAQAmAAUJHQsjHwCtAAAJAAIJPg73gQCOAAAuAAQKfxwABAkABgnsIbNIAMIBAAkABgnsIbNIAMIBACYABQmzGbBCAE0BACEAAQkAANFsAAAAAAAA.Phatcow:BAABLgAECn81AAMCAAkJgxt7FwBaAgACAAgJaxp7FwBaAgAYAAkJRhRsCwD5AQAAAA==.Pheral:BAEBLgAECn8XAAIOAAgJ1hlVCgAWAgAOAAgJ1hlVCgAWAgABLgAFFAMJEAATANMNAA==.Phoseidon:BAAALgADCgcJCQAAAA==.Phude:BAACLgAFFH8TAAITAAQJdhdANgA7AQATAAQJdhdANgA7AQAuAAQKf1AAAhMACQlfITsMAAEDABMACQlfITsMAAEDAAAA.',
Pi='Pinch:BAAALgAECgMJAwAAAA==.',
Po='Pohl:BAAALgAECgYJDQAAAA==.Pokimana:BAAALgADCgEJAQAAAA==.Poohynok:BAACLgAFFH8LAAIGAAQJlh12SgBSAQAGAAQJlh12SgBSAQAuAAQKfzwAAgYACQkXJfsJACgDAAYACQkXJfsJACgDAAAA.',
Pu='Pukefeast:BAABLgAECn8WAAIGAAcJ3ReeagCjAQAGAAcJ3ReeagCjAQAAAA==.',
Py='Pyramys:BAACLgAFFH8TAAInAAUJLB8ADAAjAQAnAAUJLB8ADAAjAQAuAAQKfysAAicACQlPI+0CACEDACcACQlPI+0CACEDAAAA.',
['Pè']='Pèrce:BAAALgAECgYJEgAAAA==.',
Qu='Quepaoka:BAAALgADCgIJAgAAAA==.',
Ra='Raklem:BAAALgAECgMJAwABLgAECgYJCgAKAAAAAA==.Ramble:BAAALgADCgQJBAABLgAECgQJBgAKAAAAAA==.Ramstein:BAAALgAECgMJAwAAAA==.Raphînîty:BAAALgADCgMJBQAAAA==.Rashari:BAAALgADCgYJCAAAAA==.Rawhawk:BAAALgAECgUJCgABLgAECgkJIQAJALUVAA==.Razgrizz:BAAALgAECgUJEwAAAA==.',
Re='Retro:BAAALgAECgIJBAAAAA==.Revelatus:BAAALgAECgQJBgAAAA==.Reythanas:BAAALgAECgQJBwAAAA==.Rezzin:BAAALgAECgEJAQAAAA==.',
Ri='Rileyann:BAABLgAECn8fAAMdAAgJOQwvKwBrAQAdAAgJOQwvKwBrAQAUAAYJAwNMRADaAAAAAA==.',
Ro='Rolls:BAAALgAECgQJBAAAAA==.Roozer:BAAALgAECgUJEgAAAA==.',
Ru='Runearius:BAAALgAECgYJCgABLgAFFAUJDQATAGkUAA==.',
['Rå']='Råphå:BAAALgAECgMJBQAAAA==.',
Sa='Saelyria:BAACLgAFFH8KAAINAAMJqxoaMADpAAANAAMJqxoaMADpAAAuAAQKfx8AAw0ACQmmHWYKABMDAA0ACQmmHWYKABMDAA8AAQk5EfSJADQAAAAA.Saga:BAAALgADCgUJBQABLgAECgkJRAARALwUAA==.Sagepower:BAAALgAECgQJBQAAAA==.Sagethepally:BAAALgAECgcJBAAAAA==.Saintfail:BAABLgAECn8hAAIQAAYJ7SQ8FQBhAgAQAAYJ7SQ8FQBhAgABLgAECgcJMwAFAGQhAA==.Sainthymn:BAABLgAECn8YAAIcAAYJnCQODwB8AgAcAAYJnCQODwB8AgABLgAECgcJMwAFAGQhAA==.Saintmist:BAABLgAECn8zAAIFAAcJZCG3DgCwAgAFAAcJZCG3DgCwAgAAAA==.Salero:BAAALgADCgIJAQAAAA==.Sandiera:BAABLgAECn8jAAMGAAkJugy4ZgCsAQAGAAkJugy4ZgCsAQAlAAMJPAOoFwBcAAAAAA==.Saxtön:BAAALgADCggJEwAAAA==.Sayberix:BAAALgAFFAIJAgABLgAFFAQJDgAXALEcAA==.',
Sc='Scarlett:BAAALgAECgEJAQAAAA==.Scoreboard:BAACLgAFFH8lAAIoAAcJ4CU9AACjAgAoAAcJ4CU9AACjAgAuAAQKfyEAAygACQkgJg0AAOsDACgACQkgJg0AAOsDACcAAQnwFJhaAE8AAAAA.Scorn:BAAALgAECgYJDgAAAA==.Scottx:BAACLgAFFH8FAAINAAIJmAhpWgBiAAANAAIJmAhpWgBiAAAuAAQKfxQAAg0ABwlPFFE8AKABAA0ABwlPFFE8AKABAAAA.',
Se='Sebas:BAAALgAECgEJAQAAAA==.Sedric:BAABLgAECn8YAAIPAAcJpgnCRQDxAAAPAAcJpgnCRQDxAAAAAA==.Selkz:BAAALgAECgcJDQAAAA==.Selsonblue:BAAALgAECgUJCQAAAA==.Sesskaa:BAABLgAECn8cAAICAAkJYxsHEADNAgACAAkJYxsHEADNAgAAAA==.Severoth:BAAALgAECgMJAwAAAA==.',
Sh='Shadowcursed:BAAALgADCgcJCgAAAA==.Shadowstorm:BAAALgADCgQJBAAAAA==.Shadøws:BAAALgAECgEJAQAAAA==.Shakenhealz:BAAALgADCgYJBgAAAA==.Shaldria:BAAALgADCgEJAQAAAA==.Sharhox:BAAALgAECgIJBAAAAA==.Shathos:BAAALgADCgEJAQAAAA==.Sheebá:BAAALgADCgYJCwAAAA==.Shishkbob:BAAALgADCgkJCQAAAA==.Shivax:BAAALgAECgYJDgAAAA==.Shugma:BAAALgADCggJCAAAAA==.Shünúkh:BAAALgADCgYJBgAAAA==.',
Si='Sigewulf:BAABLgAFFH8FAAIHAAIJTQ5lNABhAAAHAAIJTQ5lNABhAAABLgAECgcJHgAEANoKAA==.Signal:BAAALgAECgEJAQAAAA==.Silhouete:BAAALgAECgYJBgAAAA==.Singbow:BAAALgADCgYJBgABLgAECgkJNgANAMAOAA==.Sinogad:BAABLgAECn8YAAMPAAgJlBFrKgB9AQAPAAgJlBFrKgB9AQANAAUJ4xMaVgA1AQAAAA==.Sinol:BAAALgAECgYJDwABLgAECggJGAAPAJQRAA==.Sioux:BAAALgADCgEJAQAAAA==.Sixosix:BAAALgADCgIJAgAAAA==.',
Sk='Skaro:BAABLgAECn8ZAAMFAAkJxRHKRABRAQAFAAgJLA/KRABRAQADAAEJRw34mgAxAAAAAA==.Skyborn:BAABLgAECn8aAAIGAAkJ1AurawChAQAGAAkJ1AurawChAQAAAA==.',
Sl='Slamahoochee:BAAALgAECgYJCQAAAA==.Slambulance:BAAALgAECgEJAQABLgAFFAYJEAAHADoaAA==.Slay:BAACLgAFFH8RAAIPAAQJ5B4xGABRAQAPAAQJ5B4xGABRAQAuAAQKfyoABA8ACAmPIesPAGACAA8ACAmPIesPAGACAA4ABglkG48TAHgBAA0AAQk/Awj3ABoAAAAA.',
Sm='Smokedademon:BAAALgAECgMJCQAAAA==.Smokiebear:BAAALgAECgcJDwAAAA==.Smunkie:BAABLgAECn8fAAIEAAcJyiZJCgCMAgAEAAcJyiZJCgCMAgABLgAECgkJGwAHANYkAA==.',
Sn='Snickeers:BAAALgAECgEJAQAAAA==.',
So='Sofa:BAAALgAECgQJBAAAAA==.Somapeace:BAAALgAECgYJCwAAAA==.Somogyi:BAAALgADCgIJAgAAAA==.',
Sp='Spopovich:BAAALgADCggJCAABLgAECgMJAwAKAAAAAA==.Sprints:BAAALgAECgQJBAAAAA==.',
St='Stitchlock:BAAALgAECgIJAgAAAA==.Stitchofevil:BAABLgAECn8WAAQjAAcJuBoEBgACAgAjAAYJUB8EBgACAgAVAAQJpAmf+QBuAAAIAAIJtQ8hYQBMAAAAAA==.Stonedshaman:BAAALgADCgYJBgABLgAECgIJAgAKAAAAAA==.Stormhands:BAAALgAECgYJDwAAAA==.Stormhugger:BAAALgAFFAEJAQAAAA==.Stormslight:BAAALgAECgQJBQAAAA==.Stoutnholy:BAABLgAECn8ZAAITAAkJSAnGewB0AQATAAkJSAnGewB0AQAAAA==.Stratichnut:BAABLgAECn82AAMNAAkJwA6dOQCtAQANAAkJwA6dOQCtAQAPAAMJSwjFfgBGAAAAAA==.Stromar:BAAALgAECgQJBAAAAA==.Stwampadin:BAABLgAECn8iAAIQAAkJriJiAwBpAwAQAAkJriJiAwBpAwAAAA==.Stwevoker:BAAALgAECgMJAwABLgAECgkJIgAQAK4iAA==.Stwonkfu:BAAALgAECggJDAABLgAECgkJIgAQAK4iAA==.',
Su='Sumire:BAAALgADCggJDgABLgAECgYJCgAKAAAAAA==.Sunman:BAAALgADCgEJAQAAAA==.Surloyn:BAAALgAECgcJEgAAAA==.',
Sv='Sveny:BAAALgAECgEJAQAAAA==.',
Sw='Swampert:BAACLgAFFH8YAAISAAYJIBjCCwCkAQASAAYJIBjCCwCkAQAuAAQKfyAAAhIACQmJIOgMAO8CABIACQmJIOgMAO8CAAAA.Swamperting:BAABLgAECn8XAAISAAcJMhPPOABiAQASAAcJMhPPOABiAQABLgAFFAYJGAASACAYAA==.Swayaos:BAAALgAFFAIJAgAAAA==.Swaye:BAACLgAFFH8OAAIUAAQJvg7DGwAKAQAUAAQJvg7DGwAKAQAuAAQKfysAAhQACQlUFqIXAAkCABQACQlUFqIXAAkCAAAA.Sweetfox:BAAALgAECgYJEAAAAA==.Swiftorius:BAAALgAECgYJBQAAAA==.Swimchick:BAAALgAECgcJEgAAAA==.Switched:BAAALgADCgcJBwABLgAECgkJGwAHANYkAA==.Swizzle:BAAALgAFFAEJAQAAAA==.',
Sy='Syllvanas:BAABLgAECn8hAAMJAAgJmxLkTgCxAQAJAAgJEhLkTgCxAQAmAAEJ7BneMgBNAAAAAA==.Syrindra:BAAALgADCgUJAwAAAA==.Sythia:BAACLgAFFH8LAAIdAAQJdhHXFQAMAQAdAAQJdhHXFQAMAQAuAAQKfxgAAh0ACAkhI6YFABsDAB0ACAkhI6YFABsDAAEuAAUUBQkLABUADxUA.',
Ta='Taltost:BAABLgAECn8hAAIJAAkJtRUOLAAoAgAJAAkJtRUOLAAoAgAAAA==.Tantrik:BAAALgADCgEJAQAAAA==.Tartin:BAAALgAECgMJAwAAAA==.Tarv:BAAALgAECgEJAQAAAA==.Tashamirage:BAAALgAECgMJBAAAAA==.Tauriel:BAAALgAECgUJBwAAAA==.',
Te='Teex:BAAALgADCgYJBwAAAA==.Teksuo:BAACLgAFFH8TAAIDAAQJLg/THADkAAADAAQJLg/THADkAAAuAAQKf1MAAgMACQkrH8kIALYCAAMACQkrH8kIALYCAAAA.Telamontay:BAAALgADCgkJFQAAAA==.Telferas:BAABLgAECn8VAAIPAAgJ+RkkJgCYAQAPAAgJ+RkkJgCYAQABLgAFFAgJDgALANAeAA==.Tenithon:BAACLgAFFH8LAAMQAAMJxR4eIgAIAQAQAAMJxR4eIgAIAQATAAEJMQTruQA+AAAuAAQKfzUAAhAACQnLIroDAGADABAACQnLIroDAGADAAAA.Tenshenzen:BAABLgAECn8eAAIFAAkJ9RUQGABSAgAFAAkJ9RUQGABSAgAAAA==.',
Th='Therandis:BAAALgADCgUJBQAAAA==.Thetombo:BAABLgAECn8UAAITAAYJmQld1wDmAAATAAYJmQld1wDmAAAAAA==.Thierry:BAAALgADCgUJBQAAAA==.Thierrye:BAABLgAECn8VAAIbAAYJlhtmTQC/AQAbAAYJlhtmTQC/AQAAAA==.Tholaren:BAABLgAECn87AAMJAAkJyBNZMwALAgAJAAkJyBNZMwALAgAmAAUJVQejJACLAAAAAA==.Threed:BAAALgAECgkJEwAAAA==.Threewar:BAAALgAECgIJAgABLgAECgkJEwAKAAAAAA==.Thrissa:BAABLgAECn8aAAINAAkJqRCFLwDjAQANAAkJqRCFLwDjAQAAAA==.Thulgrim:BAAALgADCgYJBgAAAA==.',
To='Torrque:BAAALgADCgkJCQABLgADCgYJCwAKAAAAAA==.Totemlicker:BAAALgAECgEJAQAAAA==.',
Tr='Trandeath:BAAALgAECgQJBAAAAA==.Trangon:BAABLgAECn8nAAITAAkJlgpjegB3AQATAAkJlgpjegB3AQAAAA==.Traplobstah:BAAALgADCgkJCQAAAA==.Traveler:BAAALgADCgEJAQAAAA==.Traygon:BAAALgAECgYJEAAAAA==.Trillion:BAAALgADCggJCAAAAA==.',
Tu='Tunzoffun:BAAALgAECgIJBQAAAA==.',
Un='Unanswered:BAAALgAECgEJAQABLgAFFAYJEAAHADoaAA==.Underbyte:BAAALgADCggJDwAAAA==.Unknownname:BAAALgAECgMJAwAAAA==.',
Ur='Urholiness:BAAALgADCgkJDwAAAA==.',
Va='Vaeleia:BAAALgAECgQJBgAAAA==.Vahnkar:BAAALgADCgYJCQAAAA==.Valentinu:BAAALgADCgcJDwAAAA==.Valkyrie:BAAALgAECgEJAgAAAA==.Vaneshk:BAAALgADCgEJAQAAAA==.Varchemical:BAAALgAECgcJBwAAAA==.Varithal:BAACLgAFFH8TAAIeAAQJkRmkFQAwAQAeAAQJkRmkFQAwAQAuAAQKf0IAAh4ACQngIF0DABEDAB4ACQngIF0DABEDAAEuAAQKAQkBAAoAAAAA.Varri:BAAALgAECgMJBQAAAA==.Varðarvörðr:BAAALgAECgEJAQABLgAECgcJHgAEANoKAA==.Vastectomy:BAAALgAECggJCwAAAA==.',
Ve='Vegasana:BAAALgAFFAEJAwAAAA==.Velwing:BAAALgAECgUJBwAAAA==.Venawyn:BAABLgAECn8vAAIJAAkJ1Q0DVgCdAQAJAAkJ1Q0DVgCdAQAAAA==.Verakhaa:BAAALgAECgQJBAAAAA==.',
Vi='Vibepriest:BAAALgADCgEJAQAAAA==.Vindfaramaðr:BAABLgAECn8eAAIEAAcJ2gr0PwD4AAAEAAcJ2gr0PwD4AAAAAA==.Vixin:BAABLgAECn8YAAICAAcJbxF3UwBhAQACAAcJbxF3UwBhAQAAAA==.',
Vo='Voidsaack:BAAALgAFFAEJAQAAAA==.Voidz:BAAALgAECgEJAQAAAA==.Volfguar:BAAALgAECgQJAQAAAA==.Vortan:BAABLgAECn8oAAIhAAkJZBuECQCFAgAhAAkJZBuECQCFAgAAAA==.',
Vr='Vreya:BAAALgADCgkJFQABLgAECgUJEwAKAAAAAA==.',
Vy='Vynthus:BAAALgAECgcJEgAAAA==.',
['Vä']='Värys:BAAALgAECgEJAQAAAA==.',
Wa='Wan:BAAALgADCgEJAQAAAA==.Warhundin:BAEALgAECgYJEgABLgAFFAMJEAATANMNAA==.Warwan:BAAALgADCgIJAgAAAA==.Watercheck:BAAALgAECgEJAQAAAA==.Wazzbozz:BAAALgAECgQJAwAAAA==.Wazzdh:BAAALgAECgYJCgAAAA==.Wazzdot:BAAALgAECgUJEAAAAA==.Wazzhunnah:BAABLgAECn8nAAMhAAkJ0hTqEwAHAgAhAAkJ0hTqEwAHAgAmAAQJZAlhZQCqAAAAAA==.Wazzmage:BAAALgAECgMJAwAAAA==.',
We='Werg:BAAALgAECggJCgABLgAFFAYJDAAiAHELAA==.',
Wh='Whatmyname:BAABLgAECn9NAAIiAAkJbgqiJgAaAQAiAAkJbgqiJgAaAQAAAA==.Whispp:BAAALgAECgYJCAAAAA==.',
Wi='Willough:BAAALgAECgUJCgAAAA==.',
Wo='Wonsok:BAAALgAECgcJEAAAAA==.',
Wy='Wyvoker:BAABLgAECn8mAAIeAAkJPhs5BQDDAgAeAAkJPhs5BQDDAgAAAA==.',
['Wì']='Wìllow:BAAALgADCgIJAgAAAA==.',
['Wÿ']='Wÿm:BAABLgAECn8VAAILAAgJFx0kJgBpAgALAAgJFx0kJgBpAgABLgAECgkJJgAeAD4bAA==.',
Xa='Xaoleth:BAAALgADCgEJAQAAAA==.',
Xe='Xenorion:BAAALgAECgMJAwAAAA==.Xephora:BAAALgAECgEJBgAAAA==.',
Xi='Xiq:BAAALgADCgUJBQAAAA==.',
Xr='Xrinch:BAAALgADCgYJBgAAAA==.',
Xu='Xunadin:BAAALgAECgIJAgAAAA==.Xuny:BAAALgAECgUJEgAAAA==.',
Ya='Yarrggh:BAAALgAECgIJAgAAAA==.',
Yo='Yoonie:BAAALgAECgUJBgAAAA==.Yordi:BAAALgAECgUJEwAAAA==.',
Yu='Yuzuriha:BAACLgAFFH8TAAIJAAQJuyCIJABrAQAJAAQJuyCIJABrAQAuAAQKf0IAAgkACQmQJEUFADsDAAkACQmQJEUFADsDAAAA.',
Za='Zaelia:BAAALgADCgYJBgABLgAECgkJPQATAOUeAA==.Zaletren:BAAALgAECgkJCAAAAA==.Zamaze:BAABLgAECn8nAAMWAAkJkCBsBwCJAgAWAAkJkCBsBwCJAgAXAAEJLwmufwAnAAAAAA==.Zannah:BAAALgAECgMJAwAAAA==.Zant:BAAALgAECgIJAQAAAA==.',
Ze='Zeekielle:BAEBLgAECn88AAIfAAkJFhXyEgD9AQAfAAkJFhXyEgD9AQABLgAFFAMJEAATANMNAA==.Zemesa:BAAALgAECgMJAwAAAA==.Zenius:BAABLgAECn8UAAIYAAcJQBH9GAA5AQAYAAcJQBH9GAA5AQAAAA==.Zerithrielle:BAABLgAECn83AAIfAAgJ2RlTEgAEAgAfAAgJ2RlTEgAEAgAAAA==.',
Zi='Zippii:BAAALgAECgcJCAAAAA==.Zipy:BAABLgAECn87AAIdAAkJgR/1BAAtAwAdAAkJgR/1BAAtAwAAAA==.',
Zo='Zof:BAAALgAECgYJDgAAAA==.Zorathar:BAAALgADCgYJBgAAAA==.',
Zu='Zugtag:BAACLgAFFH8FAAILAAMJ+SDccQAaAQALAAMJ+SDccQAaAQAuAAQKfzcAAgsACQmHIRUMAAsDAAsACQmHIRUMAAsDAAAA.',
Zy='Zyllo:BAAALgAECgUJDQAAAA==.',
['Zá']='Závier:BAABLgAECn8UAAIGAAYJ/QKW/wCoAAAGAAYJ/QKW/wCoAAAAAA==.',
['Zõ']='Zõf:BAAALgAECgIJAwABLgAECgYJDgAKAAAAAA==.',
['Äe']='Äemond:BAAALgADCgMJAwAAAA==.',
['Ål']='Ålïce:BAACLgAFFH8GAAITAAMJjQgveAC+AAATAAMJjQgveAC+AAAuAAQKf10AAhMACQl1IOQNAPUCABMACQl1IOQNAPUCAAAA.',
['Ëd']='Ëdward:BAAALgADCgcJCgABLgAECgUJEwAKAAAAAA==.',
['Ôh']='Ôhmyn:BAAALgAECgUJBQABLgAECgkJIgATALgOAA==.',
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
