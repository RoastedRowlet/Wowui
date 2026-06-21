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

local lookup = {'Monk-Brewmaster','Monk-Windwalker','Monk-Mistweaver','Shaman-Elemental','Shaman-Restoration','Mage-Frost','DeathKnight-Blood','Warlock-Destruction','Hunter-BeastMastery','Unknown-Unknown','Paladin-Protection','DeathKnight-Unholy','DeathKnight-Frost','Druid-Restoration','Druid-Feral','Druid-Balance','Paladin-Holy','Warrior-Fury','Paladin-Retribution','Priest-Shadow','Warlock-Demonology','Warrior-Protection','Warrior-Arms','Shaman-Enhancement','Evoker-Devastation','Evoker-Augmentation','DemonHunter-Devourer','Priest-Discipline','Priest-Holy','Evoker-Preservation','DemonHunter-Havoc','DemonHunter-Vengeance','Hunter-Survival','Druid-Guardian','Warlock-Affliction','Mage-Fire','Mage-Arcane','Hunter-Marksmanship','Rogue-Subtlety','Rogue-Outlaw','Rogue-Assassination',}
local provider = {region='US',realm='GrizzlyHills',name='US',type='weekly',zone=46,date='2026-06-20',data={Ab='Abramz:BAAALgADCgMJAwAAAA==.',
Ad='Addely:BAAALgAFFAEJAQAAAA==.Addly:BAAALgAFFAEJAQAAAA==.Adeley:BAABLgAECn8cAAQBAAcJfxn0AAD5AAACAAcJtBQGKAB4AQABAAYJ1xL0AAD5AAADAAMJTAM6pwBOAAAAAA==.Adely:BAAALgAECgEJAQAAAA==.Adelybeast:BAAALgAECgEJAQAAAA==.Adelymon:BAABLgAECn8bAAMEAAkJlRdDFgA0AgAEAAkJlRdDFgA0AgAFAAUJARD1hQDRAAAAAA==.Adonysroth:BAAALgAECgMJAwAAAA==.Adrahil:BAAALgADCgIJAgAAAA==.',
Ae='Aeonra:BAAALgADCgIJAgAAAA==.',
Ag='Agronak:BAAALgAECgQJBgAAAA==.',
Al='Aldan:BAAALgADCgMJAwAAAA==.Aldazen:BAACLgAFFH8UAAICAAQJmiQOBwCmAQACAAQJmiQOBwCmAQAuAAQKfzoAAgIACQkeJFcDAC0DAAIACQkeJFcDAC0DAAAA.Alenara:BAAALgAECgcJEQABLgAECgkJIwAGALoMAA==.Aletheìa:BAAALgAECgEJAQAAAA==.Alishalian:BAAALgAECgYJBgAAAA==.Alovan:BAAALgADCgEJAQABLgAECgcJHgABANoKAA==.Alterbeast:BAAALgAECgUJBgABLgAFFAYJEAAHADoaAA==.Alyssandra:BAABLgAECn8qAAIIAAkJWxg/BAA+AgAIAAkJWxg/BAA+AgAAAA==.',
Am='Amarella:BAABLgAECn8WAAIJAAkJ6R2kKQAQAgAJAAkJ6R2kKQAQAgAAAA==.Amarrite:BAAALgAECgQJCQABLgAECgUJCwAKAAAAAA==.Ammalane:BAAALgAECgUJCwAAAA==.Amrah:BAAALgAECgQJBQAAAA==.Amunzo:BAAALgAECgEJAQABLgAECgkJFgALAPEPAA==.',
An='Angler:BAAALgAECgMJAwAAAA==.Angyrolaj:BAABLgAECn8XAAMMAAcJ0xf7ZQCbAQAMAAcJgBf7ZQCbAQANAAIJdBUXEQCFAAAAAA==.',
Aq='Aquadora:BAAALgADCgMJAwAAAA==.',
Ar='Arangarr:BAABLgAECn8xAAMOAAkJpx0GDgDpAgAOAAkJpx0GDgDpAgAPAAEJ1BFYUQA2AAAAAA==.Arcin:BAAALgADCgEJAQAAAA==.Areyana:BAABLgAECn8aAAIJAAkJVA+wTQC5AQAJAAkJVA+wTQC5AQAAAA==.Areyoudead:BAAALgAECgQJBAABLgADCgYJCwAKAAAAAA==.Ariolas:BAAALgADCgYJCQAAAA==.Aristoi:BAAALgAECgEJAQAAAA==.Arkand:BAAALgADCgUJBAAAAA==.Arkandra:BAABLgAECn8UAAIQAAYJOhbzNQA+AQAQAAYJOhbzNQA+AQAAAA==.Arkara:BAAALgADCgEJAQAAAA==.Arrietty:BAABLgAECn8vAAIRAAgJxRVoAQAcAQARAAgJxRVoAQAcAQAAAA==.Arthues:BAABLgAECn8WAAILAAgJDBzuCQAuAgALAAgJDBzuCQAuAgAAAA==.Arthâs:BAAALgAECgYJBQAAAA==.Arumathe:BAABLgAECn8XAAILAAkJxxICEgCmAQALAAkJxxICEgCmAQAAAA==.',
As='Asura:BAACLgAFFH8TAAISAAQJWiQqDQCfAQASAAQJWiQqDQCfAQAuAAQKfyAAAhIACQnLItkIAB4DABIACQnLItkIAB4DAAAA.',
Au='Aurelian:BAAALgAECgEJAgAAAA==.',
Az='Az:BAABLgAECn8gAAISAAgJyCQLEAB5AgASAAgJyCQLEAB5AgAAAA==.Azeriall:BAACLgAFFH8TAAIEAAQJ4gtWLgDaAAAEAAQJ4gtWLgDaAAAuAAQKf0gAAwQACQnUFnkYACACAAQACQnUFnkYACACAAUABAlKAVuGAHsAAAAA.Azerowolf:BAAALgADCggJCAAAAA==.Azráèl:BAAALgADCgMJAwAAAA==.',
Ba='Babyboom:BAAALgAECgEJAQAAAA==.Baconhammr:BAABLgAECn8mAAMTAAkJuA4qZQClAQATAAkJuA4qZQClAQARAAYJhAgUdQBlAAAAAA==.Badazmf:BAAALgADCgcJDAABLgAECgkJNAAUACEbAA==.Badcompany:BAAALgADCgUJBQABLgAECgkJOAAOALMPAA==.Baddream:BAAALgAECgYJDgAAAA==.Baelmyre:BAAALgADCgUJBQAAAA==.Balenciagosa:BAAALgADCgUJBQABLgAECgkJIwAGALoMAA==.Banshiï:BAABLgAECn87AAIIAAkJjBSxBwDXAQAIAAkJjBSxBwDXAQAAAA==.Baratheøn:BAABLgAECn8xAAIOAAkJvxevIgA0AgAOAAkJvxevIgA0AgAAAA==.Bax:BAAALgADCgIJAgAAAA==.Baxar:BAAALgAECgIJAgAAAA==.',
Bb='Bbd:BAAALgAECggJCQABLgAECgYJDgAKAAAAAA==.',
Be='Beanz:BAAALgAFFAMJAwAAAA==.Beeftard:BAABLgAECn8YAAIRAAkJWRZiKgDfAQARAAkJWRZiKgDfAQAAAA==.Bellavix:BAAALgADCgMJBAAAAA==.Benafflic:BAAALgAECgEJAQABLgAECgUJDAAKAAAAAA==.Berserrk:BAAALgADCgYJBgAAAA==.Bershale:BAAALgAECgEJAQABLgAECgYJBwAKAAAAAA==.',
Bi='Bifficus:BAABLgAECn8VAAITAAkJbhcHOgAbAgATAAkJbhcHOgAbAgAAAA==.Big:BAAALgADCgMJBAAAAA==.Biggiecheese:BAAALgAECgMJBAAAAA==.',
Bl='Blackscorn:BAAALgADCgEJAQAAAA==.Blackthôrne:BAAALgAECgYJDgAAAA==.Blucki:BAABLgAECn8fAAIVAAgJ7QmbigAlAQAVAAgJ7QmbigAlAQAAAA==.',
Bo='Bobfu:BAAALgADCgYJCAAAAA==.',
Br='Brieze:BAAALgADCgIJAgAAAA==.Brige:BAAALgAECggJBgAAAA==.Brightstar:BAAALgADCgEJAQAAAA==.Brimaz:BAAALgADCgEJAQAAAA==.',
Bu='Buhhead:BAAALgADCgUJBgAAAA==.Bunana:BAAALgADCgEJAQAAAA==.Bunbear:BAAALgAECgIJAgAAAA==.Bunette:BAAALgADCgEJAQAAAA==.',
Bw='Bwamsamdi:BAAALgADCgYJBgAAAA==.',
By='Byzantium:BAABLgAECn8vAAIWAAkJiQjLHgA9AQAWAAkJiQjLHgA9AQAAAA==.',
['Bô']='Bônebeard:BAAALgAECgEJAQAAAA==.',
Ca='Cabledryer:BAAALgAECgQJEAAAAA==.Caelidpackx:BAAALgADCgYJBwAAAA==.Cakron:BAAALgAECgUJBwABLgAECgkJFgALAPEPAA==.Calamitty:BAAALgAECgUJCAAAAA==.Calistin:BAAALgAECgYJBwAAAA==.Callmedatty:BAAALgAECgEJAQAAAA==.Caluu:BAAALgADCgEJAQAAAA==.Carnry:BAAALgADCgQJBAAAAA==.Catboy:BAABLgAECn8fAAIGAAkJNhZDbgCeAQAGAAkJNhZDbgCeAQAAAA==.Catnips:BAABLgAECn8cAAITAAgJURh2bgCRAQATAAgJURh2bgCRAQAAAA==.Catpow:BAAALgAECgkJAgAAAA==.',
Ch='Chanaranach:BAAALgAECgYJCgAAAA==.Charitey:BAAALgAECgMJBAAAAA==.Cheelo:BAAALgAECgkJEwAAAA==.Chknnugget:BAAALgAECgMJBQAAAA==.Chromatic:BAABLgAECn8zAAMFAAkJZBj4KAAaAgAFAAgJAxf4KAAaAgAEAAYJghGAOwBHAQAAAA==.',
Ci='Cindrethresh:BAAALgAECgQJCQAAAA==.',
Co='Coffeeblak:BAABLgAECn8ZAAMCAAgJBRNLJgCmAQACAAcJlxNLJgCmAQADAAUJFQ65PwDkAAAAAA==.Coldstorm:BAAALgAECgcJCwAAAA==.Collision:BAAALgAECgkJEgAAAA==.Compensating:BAAALgADCgYJBgAAAA==.Connor:BAAALgADCgcJBwAAAA==.Connsumption:BAAALgAECgYJCgAAAA==.Corrine:BAAALgAECgYJCwAAAA==.',
Cr='Crazybatt:BAABLgAECn8UAAITAAYJXQaP+ADAAAATAAYJXQaP+ADAAAAAAA==.Crypt:BAAALgAECgYJCgAAAA==.',
Cu='Cuckchairpov:BAACLgAFFH8OAAMBAAQJJRTNJAAXAQABAAQJpBPNJAAXAQACAAIJQg15DACgAAAuAAQKfywAAwIACQkqH2gKANICAAIACAl4HWgKANICAAEACQndFGQVAAICAAAA.',
Cy='Cynderleena:BAAALgAECgcJCAAAAA==.Cynyia:BAABLgAECn8vAAIJAAkJxRMrKwAIAgAJAAkJxRMrKwAIAgAAAA==.',
Cz='Czk:BAAALgADCgYJBgABLgAECggJGQACAAUTAA==.',
['Có']='Cóldblóód:BAAALgAECgIJAgAAAA==.',
Da='Daddyelessar:BAAALgAECggJEgAAAA==.Dafattyup:BAABLgAECn8aAAIVAAYJlRxUYwCgAQAVAAYJlRxUYwCgAQAAAA==.Daghmar:BAAALgADCgUJBQAAAA==.Dagon:BAAALgAECgMJAwAAAA==.Dakotarain:BAAALgADCgIJAgAAAA==.Dalerontwo:BAAALgADCgEJAQAAAA==.Darruin:BAACLgAFFH8RAAMMAAgJgiADCgCVAgAMAAcJgiADCgCVAgAHAAEJAAAbZAAAAAAuAAQKfygAAgwACQlAJBsGAEgDAAwACQlAJBsGAEgDAAAA.Dayrun:BAAALgAECgUJDQAAAA==.',
De='Deadicee:BAAALgAECgIJAgABLgAECgYJFAATAHwOAA==.Deadlyvixin:BAAALgAECgQJBAAAAA==.Deadstorm:BAAALgAECgUJBQAAAA==.Deathturtle:BAABLgAECn8eAAIMAAgJLxDOlQA8AQAMAAgJLxDOlQA8AQAAAA==.Deavaos:BAAALgAECgcJCwAAAA==.Dedmartigan:BAAALgADCgUJBQAAAA==.Deeanndra:BAABLgAECn8uAAMMAAkJTxNLSADpAQAMAAkJTxNLSADpAQANAAEJDAkBQQAlAAAAAA==.Deefiler:BAAALgAECgkJAgABLgAECgkJLgAMAE8TAA==.Deeversity:BAAALgAECggJAgABLgAECgkJLgAMAE8TAA==.Deevz:BAAALgAECgIJAgAAAA==.Demandred:BAAALgAECgYJCQAAAA==.Demiz:BAABLgAECn84AAMFAAkJ5RqMFwCNAgAFAAkJ5RqMFwCNAgAEAAcJug7GSAARAQAAAA==.Deredris:BAAALgAECgQJBAABLgAECgYJCgAKAAAAAA==.Dertka:BAAALgAECgYJDAAAAA==.',
Di='Diiviiniity:BAAALgAECgEJAQAAAA==.Discodruid:BAABLgAECn8UAAIOAAYJKRP+UwBAAQAOAAYJKRP+UwBAAQAAAA==.Dishsoap:BAAALgAECgMJAwABLgAFFAYJGAASACAYAA==.Dixie:BAAALgAECgEJAQAAAA==.',
Dj='Djall:BAAALgAFFAEJAQAAAA==.Djöflaveiðim:BAAALgAECgIJAgABLgAECgcJHgABANoKAA==.',
Do='Dommy:BAABLgAECn8fAAIHAAkJKCWEAQBJAwAHAAkJKCWEAQBJAwAAAA==.Domw:BAAALgAECgYJDAABLgAECgkJHwAHACglAA==.Donham:BAACLgAFFH8XAAMMAAYJ9xtANwCPAQAMAAUJ9xtANwCPAQAHAAEJAABBEwBZAAAuAAQKfx8AAgwACAnLHzweAMsCAAwACAnLHzweAMsCAAAA.Dorkimedes:BAAALgAECgQJDAAAAA==.Dottie:BAABLgAECn8oAAMIAAgJNhM2FwCQAQAIAAcJJQ82FwCQAQAVAAgJ7xHfYAB+AQAAAA==.Dotvinci:BAAALgAECgYJBgAAAA==.',
Dr='Draelesh:BAABLgAECn8+AAIQAAkJwhNHGwDwAQAQAAkJwhNHGwDwAQAAAA==.Draenk:BAAALgADCgUJBQAAAA==.Dragún:BAAALgAECgYJCwAAAA==.Drakari:BAAALgADCgYJBgAAAA==.Dramborleg:BAAALgAECgEJAQAAAA==.Drazon:BAAALgADCgIJAgAAAA==.Drewit:BAABLgAECn8WAAIPAAYJPxA1FQBiAQAPAAYJPxA1FQBiAQAAAA==.',
Du='Ducan:BAAALgADCgYJCQAAAA==.Dudeabides:BAAALgAECgYJBgABLgAECgkJHwALADQGAA==.Duskmane:BAAALgAECgMJCAAAAA==.',
Dw='Dwadler:BAACLgAFFH8QAAMXAAYJCBCUGAAfAQAXAAYJCBCUGAAfAQAWAAMJQxHiHQCpAAAuAAQKfzcAAxYACQmsHcYGAJwCABYACQmsHcYGAJwCABcABQkmFeExAAABAAAA.',
Dy='Dyrkonian:BAAALgAECggJEgAAAA==.',
Ei='Eireann:BAAALgADCgcJCQAAAA==.',
El='Elerrak:BAAALgAECgEJAQABLgAFFAcJJgAYAJ0dAA==.Elindalia:BAAALgAECgMJAwAAAA==.',
Em='Emberash:BAAALgAECgEJAQAAAA==.Embre:BAABLgAFFH8MAAMZAAUJsA6QBQALAQAZAAQJsA6QBQALAQAaAAEJAAAncgAAAAAAAA==.Emorri:BAAALgAECgYJBgAAAA==.Empyrea:BAAALgAECgQJBQAAAA==.',
Er='Eraina:BAAALgADCgIJAgAAAA==.Ericles:BAABLgAECn8ZAAMXAAcJ8R1VDADbAQAXAAcJ8R1VDADbAQASAAIJlAVwlwBkAAAAAA==.Erys:BAAALgAECgcJEQAAAA==.Erébus:BAABLgAECn8kAAIbAAkJ9xhgKAApAgAbAAkJ9xhgKAApAgAAAA==.',
Ev='Ev:BAAALgAECgQJBAAAAA==.Evergreene:BAAALgAECgEJAQABLgAECgUJCwAKAAAAAA==.Evlpotato:BAABLgAECn80AAQUAAkJIRt7EwA1AgAUAAkJIRt7EwA1AgAcAAcJNBpOIADLAQAdAAEJlAdTfwAzAAAAAA==.Evojak:BAABLgAECn8mAAMaAAkJJQr9NABeAQAaAAkJJQr9NABeAQAZAAMJxAPNHQBgAAAAAA==.',
Fa='Fabiyo:BAAALgADCgMJBQAAAA==.Faevelia:BAAALgAECgUJBgAAAA==.Fairaday:BAACLgAFFH8IAAIJAAMJtQJtCQCxAAAJAAMJtQJtCQCxAAAuAAQKfzcAAgkACQlfCwJXAJ8BAAkACQlfCwJXAJ8BAAAA.Falloon:BAAALgADCgYJBgAAAA==.Fanshen:BAAALgAECgMJBQAAAA==.Farmerdave:BAAALgAECgEJAQAAAA==.Fatdoinkz:BAAALgAECgUJCQABLgAFFAYJEAAHADoaAA==.Fauchi:BAAALgADCgEJAQAAAA==.Faxqueenmage:BAABLgAECn8cAAIGAAgJswIm9QC9AAAGAAgJswIm9QC9AAAAAA==.',
Fe='Felador:BAAALgAECgcJEgABLgAECgkJMgAVAIQVAA==.Feldo:BAABLgAECn8SAAIbAAYJjyGWOgDcAQAbAAYJjyGWOgDcAQAAAA==.Felmès:BAAALgADCgYJBgABLgAECgkJIwAGALoMAA==.Fennec:BAAALgAECgUJDAAAAA==.Feralarak:BAAALgAECgcJEwABLgAFFAcJJgAYAJ0dAA==.Ferl:BAAALgADCgIJAgAAAA==.',
Fi='Figless:BAAALgAECgIJAgABLgAECgcJMwADAGQhAA==.Firebrandd:BAACLgAFFH8cAAMZAAYJzxydAgBcAQAZAAUJnyCdAgBcAQAaAAUJZhHvIwBDAQAuAAQKf0IAAxoACQl8IzcEACYDABoACQmzIjcEACYDABkACAlIImACAA8DAAEuAAUUCAkRAAwAgiAA.Fizehbubbleh:BAEALgAECgYJCAABLgAECggJIAAEAOgaAA==.Fizehtotems:BAEBLgAECn8gAAMEAAgJ6BoXLgCKAQAEAAgJ6BoXLgCKAQAFAAUJixZVXwA+AQAAAA==.',
Fl='Fleshoracle:BAAALgAECgQJBAABLgAFFAYJEAAHADoaAA==.Fluctuates:BAAALgAECgQJCAAAAA==.',
Fo='Foragarn:BAAALgAECgYJCQAAAA==.Foron:BAAALgAECgIJAgAAAA==.',
Fr='Frankkastle:BAAALgAECgYJDwAAAA==.Frazelia:BAAALgADCgkJDgABLgAECgYJFgAPAD8QAA==.Fribble:BAABLgAECn8ZAAMFAAkJmw6NOwDAAQAFAAkJmw6NOwDAAQAYAAEJAADuSgAAAAABLgAECgkJHwALADQGAA==.Froggierlynx:BAAALgAFFAQJBAAAAA==.Frostalot:BAAALgAECgMJBAAAAA==.Froznfate:BAABLgAECn87AAMLAAkJkCXpAABWAwALAAkJkCXpAABWAwATAAIJpQcRaAFOAAAAAA==.Fryes:BAAALgAECgkJDAAAAA==.',
Fu='Fuzziebutt:BAAALgAECgQJBgAAAA==.',
Fw='Fwibble:BAAALgAECggJEgABLgAECgkJHwALADQGAA==.',
Fy='Fyrelady:BAAALgADCggJDgABLgAECgUJEQAKAAAAAA==.Fyrestone:BAAALgAECgUJEQAAAA==.',
['Fæ']='Fæder:BAAALgADCgYJBgAAAA==.',
Ga='Gabarnak:BAAALgADCgIJAgABLgAECggJGwADAKEfAA==.Gabuse:BAAALgAECgQJBAAAAA==.Galencharred:BAABLgAECn8qAAITAAgJzgpgAwARAQATAAgJzgpgAwARAQAAAA==.Garagon:BAABLgAECn8/AAIeAAkJCxdMCQBUAgAeAAkJCxdMCQBUAgAAAA==.Gauss:BAABLgAECn8fAAILAAkJNAZkIgABAQALAAkJNAZkIgABAQAAAA==.Gaîîa:BAABLgAECn8cAAIJAAgJCRq2MADtAQAJAAgJCRq2MADtAQAAAA==.',
Ge='Gelber:BAAALgAECgQJBAAAAA==.Gerva:BAABLgAECn88AAIMAAkJORRzNQApAgAMAAkJORRzNQApAgAAAA==.',
Gh='Ghlain:BAAALgAECgQJBwAAAA==.Ghorfindor:BAABLgAECn8pAAIfAAgJyQQDOwDLAAAfAAgJyQQDOwDLAAAAAA==.Ghostlybrew:BAACLgAFFH8VAAIBAAcJ9xvmBACHAQABAAcJ9xvmBACHAQAuAAQKfxYAAgEACAmpH94TAHECAAEACAmpH94TAHECAAAA.',
Gi='Gigastorm:BAAALgADCgIJAQAAAA==.Gilas:BAABLgAECn81AAQMAAkJ3w+/AgAXAQAMAAkJVg6/AgAXAQAHAAYJcBAqMwDPAAANAAUJXgWUKACPAAAAAA==.',
Gl='Glaivemstake:BAAALgADCgcJBwAAAA==.Glee:BAAALgAECgMJAwAAAA==.',
Gn='Gnik:BAAALgAECgkJEwAAAA==.Gnikole:BAAALgAECgIJAgABLgAECgkJEwAKAAAAAA==.Gnoeme:BAAALgAECgEJAwAAAA==.',
Go='Goswin:BAAALgAECgIJBQAAAA==.',
Gr='Graahak:BAAALgADCgMJAwAAAA==.Graveborn:BAABLgAFFH8QAAIHAAYJOhpvEAB9AQAHAAYJOhpvEAB9AQAAAA==.Graydenton:BAAALgAECgkJCQABLgAECggJBgAKAAAAAA==.Greenfelpowa:BAACLgAFFH8FAAMVAAMJ5QgrDAB/AAAVAAIJVwgrDAB/AAAIAAEJ/wlhAwA4AAAuAAQKfxkAAhUACQmlD4pKALsBABUACQmlD4pKALsBAAAA.Gruu:BAAALgAECgEJAQAAAA==.Gruuven:BAAALgAFFAMJAwAAAA==.',
Gu='Gutmtmon:BAABLgAECn8dAAICAAkJywfiAQCxAAACAAkJywfiAQCxAAAAAA==.',
Gw='Gwenivive:BAABLgAECn8hAAIJAAkJjBdFKwAwAgAJAAkJjBdFKwAwAgAAAA==.',
['Gí']='Gízmo:BAAALgADCgUJBQAAAA==.',
Ha='Haenus:BAABLgAECn8dAAIbAAgJ8hOCfQAlAQAbAAgJ8hOCfQAlAQAAAA==.Hamor:BAAALgAECgkJCgAAAA==.Harrynear:BAAALgADCgMJAwABLgAECgcJFwAMANMXAA==.Hat:BAACLgAFFH8FAAIbAAIJ9CIPZgDBAAAbAAIJ9CIPZgDBAAAuAAQKfxkAAxsACQl8IlwHABkDABsACQl8IlwHABkDACAAAgmRCkctAE0AAAAA.Haunt:BAAALgAECgUJBgAAAA==.Havark:BAAALgAECgMJAwAAAA==.',
He='Healbilly:BAAALgADCgEJAQAAAA==.Healingdeath:BAAALgADCgMJBAAAAA==.Hecatombe:BAAALgADCgUJBQAAAA==.Hellzdruid:BAAALgADCgQJBAAAAA==.Hellzknîght:BAABLgAECn8iAAIMAAgJfBLWZQCbAQAMAAgJfBLWZQCbAQAAAA==.Hellzshaman:BAAALgADCgIJAQAAAA==.Heyah:BAAALgADCgIJAgAAAA==.',
Ho='Holek:BAABLgAECn8ZAAMJAAgJphFDVACmAQAJAAgJphFDVACmAQAhAAMJcATxTACAAAAAAA==.Holgo:BAACLgAFFH8RAAIWAAYJRiP3AgBeAgAWAAYJRiP3AgBeAgAuAAQKfyEAAhYACQluJekBADYDABYACQluJekBADYDAAAA.Holgy:BAACLgAFFH8cAAIiAAYJliTNAgAOAgAiAAYJliTNAgAOAgAuAAQKfyYAAiIACQlWI0wBAEkDACIACQlWI0wBAEkDAAAA.Holybeard:BAACLgAFFH8NAAITAAUJaRQ6WAD/AAATAAUJaRQ6WAD/AAAuAAQKfzkAAhMACAnyIOkfAIgCABMACAnyIOkfAIgCAAAA.Hooks:BAAALgAECgQJCAAAAA==.',
Hu='Hugecowballs:BAAALgAECgkJCQAAAA==.Hunterturtle:BAAALgADCgUJBQAAAA==.',
Ic='Icia:BAAALgAECgIJAwABLgAECgUJBgAKAAAAAA==.',
Id='Idontmiss:BAAALgAECgIJCAAAAA==.',
Il='Ilickboody:BAAALgADCgQJBAAAAA==.Illustra:BAABLgAECn8aAAMdAAgJnAbhOgALAQAdAAgJnAbhOgALAQAUAAcJ3gJcWwCoAAABLgAECgkJIwAGALoMAA==.',
Im='Imaeru:BAAALgAECgMJAwAAAA==.Imcaldo:BAAALgADCgYJBgAAAA==.Imcaldoo:BAAALgADCgUJCgAAAA==.',
In='Interrupt:BAAALgAECgUJDQAAAA==.',
Ir='Irox:BAAALgADCgMJAwAAAA==.',
Is='Isaic:BAAALgADCgIJAgAAAA==.Iseila:BAABLgAECn8eAAIGAAkJXg7kYgC5AQAGAAkJXg7kYgC5AQAAAA==.Isevio:BAAALgAECgMJBwAAAA==.',
It='Ithorus:BAAALgAECgYJEgAAAA==.Itszof:BAAALgAECgEJAgAAAA==.',
Ja='Jaadb:BAAALgAECgQJBwAAAA==.Jaadd:BAAALgAECgIJAgAAAA==.Jaadi:BAAALgAECgIJAwAAAA==.Jaata:BAAALgADCgcJEAAAAA==.Jairl:BAAALgAECgQJBwAAAA==.Jamien:BAABLgAECn8/AAMTAAkJ5R4cGQCsAgATAAkJ5R4cGQCsAgARAAUJigUsdwCdAAAAAA==.Janal:BAAALgADCgEJAQAAAA==.Jasnah:BAABLgAECn8dAAMEAAgJIhbAJQC7AQAEAAgJIhbAJQC7AQAFAAQJ8BI6kwCwAAAAAA==.Jasnos:BAAALgAECgUJDwAAAA==.',
Jd='Jdk:BAAALgAECgUJBwAAAA==.',
Je='Jelf:BAAALgAECgUJCAAAAA==.Jenzing:BAABLgAECn8VAAMVAAgJqh0QKwBjAgAVAAcJqh0QKwBjAgAjAAEJAACuIwBjAAAAAA==.Jessemyn:BAABLgAECn8aAAQbAAYJrQk+vACzAAAbAAYJ1AU+vACzAAAfAAQJAAgbWwBXAAAgAAEJZxA7NQAwAAAAAA==.',
Jh='Jholy:BAAALgAECgkJAwAAAA==.',
Jo='Jobokenhones:BAACLgAFFH8FAAIbAAMJPg0TbQCxAAAbAAMJPg0TbQCxAAAuAAQKfzEAAhsACQkgGtkjAEACABsACQkgGtkjAEACAAAA.Johadgan:BAAALgADCgEJAQAAAA==.',
Jp='Jproudmore:BAAALgADCgUJBQABLgADCgYJCwAKAAAAAA==.',
Js='Jsberg:BAABLgAECn8gAAISAAgJCBb4LgCTAQASAAgJCBb4LgCTAQAAAA==.',
Ka='Kaathe:BAABLgAECn8lAAMGAAYJGx7ihADHAQAGAAYJGx7ihADHAQAkAAEJjhqXDwA4AAAAAA==.Kaboomalis:BAAALgADCgUJBQAAAA==.Kadance:BAABLgAECn8WAAIEAAcJmRaXNABpAQAEAAcJmRaXNABpAQAAAA==.Kaelyn:BAAALgAECgQJBAABLgAFFAMJCgAOAKsaAA==.Kaidiis:BAABLgAECn8wAAITAAkJbA8WZgCjAQATAAkJbA8WZgCjAQAAAA==.Kaido:BAAALgAECgEJAQAAAA==.Kalder:BAAALgADCgcJBwAAAA==.Karbonn:BAABLgAECn8fAAIZAAkJ3RR/BQAHAgAZAAkJ3RR/BQAHAgAAAA==.Kay:BAAALgAECgcJBwAAAA==.Kazeraz:BAAALgADCgEJAQAAAA==.',
Ke='Kegbreaker:BAACLgAFFH8IAAIdAAMJTAbDAgCEAAAdAAMJTAbDAgCEAAAuAAQKfzcAAh0ACQlQClgsAGcBAB0ACQlQClgsAGcBAAAA.',
Kh='Khamuur:BAAALgAECgYJBgAAAA==.Khanas:BAABLgAECn8aAAMRAAkJRhU3JQDdAQARAAgJHRY3JQDdAQATAAEJOQKV0AEYAAAAAA==.Kheru:BAAALgAECgUJBgAAAA==.Khoan:BAAALgAECgYJCgAAAA==.',
Ki='Kimbliddan:BAAALgAECgIJAgABLgAFFAMJBgAGAFgaAA==.Kimbustible:BAACLgAFFH8GAAIGAAMJWBqJdQDyAAAGAAMJWBqJdQDyAAAuAAQKfzkAAgYACQk4JJUOAAYDAAYACQk4JJUOAAYDAAAA.Kimchi:BAABLgAECn8WAAIBAAgJlhDcJwByAQABAAgJlhDcJwByAQABLgAFFAMJBgAGAFgaAA==.',
Kn='Knockknocko:BAAALgAECgcJDgAAAA==.',
Ko='Kobir:BAAALgADCgEJAQAAAA==.Komodostyle:BAABLgAECn86AAQeAAkJYg2RFwBYAQAeAAgJywqRFwBYAQAaAAYJ9RIlPwAtAQAZAAIJWw64NQBoAAAAAA==.Koobideh:BAAALgADCgEJAQAAAA==.',
Kr='Krayose:BAABLgAECn8WAAIMAAkJ3RhOJwBlAgAMAAkJ3RhOJwBlAgAAAA==.Krian:BAAALgADCgEJAQAAAA==.Kriddler:BAAALgADCgQJBAAAAA==.Krisarugala:BAABLgAECn8XAAIQAAkJVw/uAgCNAAAQAAkJVw/uAgCNAAAAAA==.',
Ku='Kujoluvsmilf:BAAALgAECgkJDAAAAA==.Kunuku:BAAALgADCgUJBQAAAA==.Kurash:BAAALgADCgcJBwAAAA==.Kurion:BAAALgAECgkJDgAAAA==.Kurogami:BAAALgAECgUJEAAAAA==.',
Ky='Kylesxmom:BAACLgAFFH8UAAMMAAYJDRDESgBdAQAMAAUJDRDESgBdAQAHAAIJuA0jQgAqAAAuAAQKf2AAAwwACQltJD0IADEDAAwACQlAJD0IADEDAAcACAn/HeQRAO8BAAAA.Kymal:BAABLgAECn88AAIbAAkJzRUSNwDqAQAbAAkJzRUSNwDqAQAAAA==.Kymbria:BAAALgADCgUJCAAAAA==.Kymora:BAAALgADCgcJBwAAAA==.Kyndrissa:BAAALgADCgUJBQAAAA==.',
['Kë']='Këy:BAACLgAFFH8MAAIMAAMJQBgzmgDbAAAMAAMJQBgzmgDbAAAuAAQKfykAAgwACAnUHYwsAIYCAAwACAnUHYwsAIYCAAAA.',
La='Latrice:BAACLgAFFH8pAAIGAAgJECOFCAC2AgAGAAgJECOFCAC2AgAuAAQKfygABAYACQk5I9wJAHYDAAYACQk5I9wJAHYDACQAAwm4GZAKAM8AACUAAQltGN0YAFEAAAAA.Lavynder:BAABLgAECn8XAAIbAAgJ5hUVWgCTAQAbAAgJ5hUVWgCTAQAAAA==.Lazerturkey:BAAALgAECgkJDwAAAA==.Laërtes:BAABLgAECn8VAAITAAUJUga2EQGkAAATAAUJUga2EQGkAAAAAA==.',
Le='Leiamirage:BAAALgAECgYJDwAAAA==.Leviscus:BAAALgAECgUJEgAAAA==.',
Li='Lifetap:BAAALgADCgMJAwAAAA==.Lightbill:BAABLgAFFH8GAAIRAAMJxxoQAgAIAQARAAMJxxoQAgAIAQAAAA==.Lightbàne:BAABLgAECn8qAAIPAAkJ2CLdAQAaAwAPAAkJ2CLdAQAaAwAAAA==.Lightningrod:BAAALgAECgYJBwAAAA==.Lightrogue:BAAALgAECgUJBQABLgAECgkJKgAPANgiAA==.Lightshaolin:BAAALgAECgQJBAAAAA==.Lildruidz:BAABLgAECn8dAAMOAAcJbhPDPwCTAQAOAAcJbhPDPwCTAQAQAAEJLQLMpwAYAAAAAA==.Lillivarak:BAABLgAECn8UAAITAAcJFget2ADnAAATAAcJFget2ADnAAAAAA==.Lilriotz:BAAALgAFFAEJAQAAAA==.Lilriotzz:BAABLgAECn8eAAIFAAkJ7Rr9EADIAgAFAAkJ7Rr9EADIAgAAAA==.Lilzdrlockz:BAAALgAECgUJDgAAAA==.Lithedra:BAAALgADCgcJDwAAAA==.Littlehand:BAAALgADCgUJBAABLgAECggJLwARAMUVAA==.',
Lo='Loot:BAAALgAFFAQJBAAAAA==.Lovecraft:BAAALgAECgMJAwAAAA==.',
Lu='Lucavi:BAAALgAECgMJAwAAAA==.Lucyvar:BAABLgAECn8WAAIfAAcJHwl6NQDoAAAfAAcJHwl6NQDoAAAAAA==.Luke:BAAALgADCgUJBwAAAA==.Luma:BAAALgAECgUJDQAAAA==.Luther:BAABLgAECn8XAAIBAAkJNw9XJQDYAQABAAkJNw9XJQDYAQAAAA==.',
Ly='Lyla:BAAALgADCgQJBgAAAA==.',
Ma='Magiceraser:BAAALgAECgIJAgABLgAFFAYJGAASACAYAA==.Magnux:BAAALgAECgEJAgAAAA==.Malazark:BAAALgADCgYJBgAAAA==.Malríus:BAAALgAECgQJEQAAAA==.Manales:BAAALgAECgcJBgAAAA==.Marhukai:BAACLgAFFH8FAAITAAMJoBhQZQDkAAATAAMJoBhQZQDkAAAuAAQKfy8AAhMACQlBH7kYAK8CABMACQlBH7kYAK8CAAAA.Marotal:BAACLgAFFH8FAAIGAAUJ/AgXbAALAQAGAAUJ/AgXbAALAQAuAAQKfy0AAgYACQlIEyRFAAwCAAYACQlIEyRFAAwCAAAA.Marr:BAAALgADCgUJBQAAAA==.Martysparty:BAABLgAECn8yAAILAAkJER0VBwBwAgALAAkJER0VBwBwAgAAAA==.Mavaena:BAAALgAECgYJDwAAAA==.Mavrane:BAAALgADCgEJAgAAAA==.',
Me='Meashakegs:BAAALgAECggJEQAAAA==.Meashaman:BAAALgAECgMJAwAAAA==.Mechaboomer:BAABLgAECn8+AAIJAAkJQR4AFwCdAgAJAAkJQR4AFwCdAgAAAA==.Megafire:BAAALgAECgMJBAAAAA==.Megahertz:BAAALgAECgcJCgAAAA==.Melcanthet:BAAALgADCggJCAAAAA==.Mellowrock:BAAALgAECgUJBgABLgAECgYJBQAKAAAAAA==.',
Mi='Mickhaggis:BAAALgADCgIJAgAAAA==.Micktarogar:BAAALgAECgcJEwAAAA==.Mickwutang:BAAALgAFFAEJAQAAAA==.Miklaga:BAAALgAECgEJAgAAAA==.Milince:BAAALgADCgMJAgAAAA==.Milkfridge:BAAALgAECgEJAQABLgAFFAMJBQAPAF4EAA==.Minikloon:BAAALgAECgYJDgAAAA==.Minphoria:BAAALgADCgQJBgAAAA==.Missylock:BAAALgADCgYJBgAAAA==.Mistilinn:BAACLgAFFH8IAAImAAMJ+wBoAwBeAAAmAAMJ+wBoAwBeAAAuAAQKfyoAAiYACQldByoTACwBACYACQldByoTACwBAAAA.Miyri:BAAALgAECgEJBQABLgAFFAMJCgAOAKsaAA==.',
Mo='Mollyporph:BAAALgAECgEJAQAAAA==.Monoco:BAABLgAECn8bAAIbAAgJDxFWWQB7AQAbAAgJDxFWWQB7AQAAAA==.Moopandax:BAACLgAFFH8kAAIQAAcJRR1eCAAZAgAQAAcJRR1eCAAZAgAuAAQKf2oAAxAACQmmJmAAAJEDABAACQmmJmAAAJEDACIACAmhHw4IAG8CAAEuAAUUBQkfABAAYCIA.Mortrum:BAAALgADCgQJBAAAAA==.Moxestime:BAAALgAECgEJAgAAAA==.Moxsdeath:BAAALgAECgcJAQAAAA==.Moxsdeaths:BAAALgADCgcJBwAAAA==.Moxshunter:BAAALgAECgEJAQAAAA==.Mozaic:BAAALgADCgEJAQAAAA==.',
Mu='Mushaboom:BAABLgAECn8fAAIBAAkJnwmtKgBhAQABAAkJnwmtKgBhAQAAAA==.Muzzler:BAABLgAECn9jAAIGAAkJoyRMBQBaAwAGAAkJoyRMBQBaAwAAAA==.',
My='Myeyes:BAAALgAECgEJAwAAAA==.Mylinkah:BAAALgADCgQJBAAAAA==.Mynamefizz:BAEBLgAECn8XAAQVAAkJNBkBMwANAgAVAAkJ9xUBMwANAgAjAAMJeh2YGQD0AAAIAAMJghSgIACoAAABLgAECggJIAAEAOgaAA==.Myotonic:BAAALgADCgQJBAAAAA==.Mythlok:BAAALgAECgMJAwAAAA==.Mythreiel:BAAALgAECgUJBgAAAA==.Mythykal:BAAALgAECgUJCgAAAA==.',
['Mé']='Méasha:BAAALgAECgkJCgAAAA==.',
Na='Nachtmar:BAAALgAECgQJBAABLgAECgkJGgATAIkPAA==.Nadis:BAAALgAECgIJAwAAAA==.Narcessa:BAAALgADCgQJBAAAAA==.Nawk:BAAALgAECgEJAQAAAA==.',
Ne='Nennerb:BAAALgADCgQJBAAAAA==.',
Ni='Nicola:BAAALgAECgkJEQAAAA==.Nightxwish:BAABLgAECn8vAAIcAAgJJBypDQCTAgAcAAgJJBypDQCTAgAAAA==.Niranye:BAAALgADCgEJAQAAAA==.',
No='Noisemarine:BAACLgAFFH8WAAIWAAUJvxVqFQD0AAAWAAUJvxVqFQD0AAAuAAQKfyEAAhYACQmLG7cIAG0CABYACQmLG7cIAG0CAAAA.Nokk:BAAALgADCgEJAQAAAA==.Nokkco:BAAALgAECgEJAgAAAA==.Norellia:BAAALgAECgQJCgAAAA==.Northleo:BAAALgADCgcJEQAAAA==.Northspirit:BAABLgAECn8gAAIEAAcJUwfKAQDrAAAEAAcJUwfKAQDrAAAAAA==.',
Nu='Nuit:BAAALgADCgUJBQABLgAECgYJCwAKAAAAAA==.',
Ny='Nyarlothep:BAAALgAECgQJBAAAAA==.Nyx:BAAALgAECgUJBQABLgAECgkJPwATAOUeAA==.',
Oa='Oakenshièld:BAAALgAECgcJDAAAAA==.',
Od='Odindh:BAAALgAFFAIJAwABLgAFFAMJBAAKAAAAAA==.Odins:BAAALgAFFAMJBAAAAA==.',
Oh='Ohwhelp:BAABLgAFFH8IAAIaAAMJ5Bk1OwDaAAAaAAMJ5Bk1OwDaAAABLgAFFAgJLwAQAI4kAA==.Ohyikers:BAACLgAFFH8vAAIQAAgJjiSdAQDfAgAQAAgJjiSdAQDfAgAuAAQKfzYAAhAACQnXJogAAIsDABAACQnXJogAAIsDAAAA.',
Ok='Oken:BAAALgADCgUJBQAAAA==.',
Om='Om:BAAALgADCgcJCQAAAA==.',
On='Onlyspirits:BAAALgAECgEJAQAAAA==.',
Op='Open:BAAALgADCgcJBwABLgAECggJLwARAMUVAA==.Opportunity:BAAALgAECgYJBgABLgAFFAMJDQARAOceAA==.',
Or='Orklock:BAAALgADCgMJAwAAAA==.',
Pa='Pallek:BAAALgAECgcJBwABLgAECggJGQAJAKYRAA==.Palli:BAABLgAECn8gAAIRAAcJiRpLAQAtAQARAAcJiRpLAQAtAQAAAA==.Paogao:BAAALgAECgUJBgAAAA==.Parry:BAAALgADCgQJBAAAAA==.Pasghetti:BAAALgADCgMJAwAAAA==.Pasta:BAABLgAECn8tAAInAAkJeh5bCACgAgAnAAkJeh5bCACgAgAAAA==.',
Pe='Perpetual:BAAALgAECgEJAgAAAA==.Pewpewbite:BAABLgAECn8ZAAIJAAkJih9yDwDVAgAJAAkJih9yDwDVAgAAAA==.',
Ph='Phantomarrow:BAACLgAFFH8VAAQhAAUJQRMHGQAKAQAhAAQJGAwHGQAKAQAmAAUJHQvVHwCtAAAJAAIJPg45hwCOAAAuAAQKfxwABAkABgnsIaFKAMEBAAkABgnsIaFKAMEBACYABQmzGbBCAE0BACEAAQkAAIhuAAAAAAAA.Phatcow:BAABLgAECn81AAMFAAkJgxt7FwBaAgAFAAgJaxp7FwBaAgAYAAkJRhS1CwD5AQAAAA==.Pheral:BAEBLgAECn8XAAIPAAgJ1hmGCgAXAgAPAAgJ1hmGCgAXAgABLgAFFAMJEAATANMNAA==.Phoseidon:BAAALgADCgcJCQAAAA==.Phude:BAACLgAFFH8TAAITAAQJdhctOQA6AQATAAQJdhctOQA6AQAuAAQKf1EAAhMACQlfIZ4MAAADABMACQlfIZ4MAAADAAAA.',
Pi='Pinch:BAAALgAECgMJAwAAAA==.',
Po='Pohl:BAAALgAECgYJDQAAAA==.Pokimana:BAAALgADCgEJAQAAAA==.Poohynok:BAACLgAFFH8LAAIGAAQJlh3VTgBBAQAGAAQJlh3VTgBBAQAuAAQKfzwAAgYACQkXJV0KACcDAAYACQkXJV0KACcDAAAA.',
Pu='Pukefeast:BAABLgAECn8WAAIGAAcJ3RcBbACjAQAGAAcJ3RcBbACjAQAAAA==.',
Py='Pyramys:BAACLgAFFH8TAAInAAUJLB8ADAAjAQAnAAUJLB8ADAAjAQAuAAQKfywAAicACQmfIwgDACADACcACQmfIwgDACADAAAA.',
['Pè']='Pèrce:BAAALgAECgYJEgAAAA==.',
Qu='Quepaoka:BAAALgADCgIJAgAAAA==.',
Ra='Raklem:BAAALgAECgMJAwABLgAECgYJCgAKAAAAAA==.Ramble:BAAALgADCgQJBAABLgAECgQJBgAKAAAAAA==.Ramstein:BAAALgAECgMJAwAAAA==.Raphînîty:BAAALgADCgMJBQAAAA==.Rashari:BAAALgADCgYJCAAAAA==.Rawhawk:BAAALgAECgUJDAABLgAECgkJJQAJALkWAA==.Razgrizz:BAABLgAECn8PAAMNAAUJpBXsGQADAQANAAUJZxTsGQADAQAMAAMJLBPs+wCxAAAAAA==.',
Re='Retro:BAAALgAECgMJBwAAAA==.Revelatus:BAAALgAECgQJBgAAAA==.Reythanas:BAAALgAECgQJBwAAAA==.Rezzin:BAAALgAECgEJAQAAAA==.',
Ri='Rileyann:BAABLgAECn8fAAMdAAgJOQzYKwBrAQAdAAgJOQzYKwBrAQAUAAYJAwNMRADaAAAAAA==.',
Ro='Rolls:BAAALgAECgQJBAAAAA==.Roozer:BAABLgAECn8VAAIJAAUJiAi7BwCSAAAJAAUJiAi7BwCSAAAAAA==.',
Ru='Runearius:BAAALgAECgYJCgABLgAFFAUJDQATAGkUAA==.',
['Rå']='Råphå:BAAALgAECgMJBQAAAA==.',
Sa='Sabadahoo:BAAALgAECgEJAQABLgAFFAMJDQAeAIMbAA==.Saelyria:BAACLgAFFH8KAAIOAAMJqxqGMQDpAAAOAAMJqxqGMQDpAAAuAAQKfx8AAw4ACQmmHbIKABIDAA4ACQmmHbIKABIDABAAAQk5EV+MADQAAAAA.Saga:BAAALgADCgUJBQABLgAECgkJRAALALwUAA==.Sagepower:BAAALgAECgQJBwAAAA==.Sagethepally:BAAALgAECgcJBAAAAA==.Saintfail:BAABLgAECn8hAAIRAAYJ7SSZFQBgAgARAAYJ7SSZFQBgAgABLgAECgcJMwADAGQhAA==.Sainthymn:BAABLgAECn8dAAIcAAYJNSV9AADyAQAcAAYJNSV9AADyAQABLgAECgcJMwADAGQhAA==.Saintmist:BAABLgAECn8zAAIDAAcJZCERDwCxAgADAAcJZCERDwCxAgAAAA==.Salero:BAAALgADCgIJAQAAAA==.Sandiera:BAABLgAECn8jAAMGAAkJugxjaACrAQAGAAkJugxjaACrAQAlAAMJPAOoFwBcAAAAAA==.Saxtön:BAAALgADCggJEwAAAA==.Sayberix:BAABLgAFFH8FAAQoAAUJ0w8OCQDoAAAoAAMJIREOCQDoAAAnAAEJ1AzgOgBSAAApAAEJ6Q7HEgBAAAABLgAFFAQJDgAXALEcAA==.',
Sc='Scarlett:BAAALgAECgEJAQAAAA==.Scoreboard:BAACLgAFFH8oAAIoAAcJ4CU/AACiAgAoAAcJ4CU/AACiAgAuAAQKfyEAAygACQkgJg0AAOsDACgACQkgJg0AAOsDACcAAQnwFJhaAE8AAAAA.Scorn:BAAALgAECgYJDgAAAA==.Scottx:BAACLgAFFH8FAAIOAAIJmAhZXABiAAAOAAIJmAhZXABiAAAuAAQKfxQAAg4ABwlPFPg8AJ8BAA4ABwlPFPg8AJ8BAAAA.Scruff:BAAALgADCgYJBgAAAA==.',
Se='Sebas:BAAALgAECgEJAQAAAA==.Sedric:BAABLgAECn8YAAIQAAcJpgnCRgDxAAAQAAcJpgnCRgDxAAAAAA==.Selkz:BAAALgAECgcJDQAAAA==.Selsonblue:BAAALgAECgUJDAAAAA==.Sesskaa:BAABLgAECn8gAAIFAAkJvhxtEADNAgAFAAkJvhxtEADNAgAAAA==.Severoth:BAAALgAECgMJAwAAAA==.',
Sh='Shadowcursed:BAAALgADCgcJCgAAAA==.Shadowstorm:BAAALgADCgQJBAAAAA==.Shadøws:BAAALgAECgEJAQAAAA==.Shakenhealz:BAAALgADCgYJBgAAAA==.Shaldria:BAAALgADCgEJAQAAAA==.Sharhox:BAAALgAECgIJBQAAAA==.Shathos:BAAALgADCgEJAQAAAA==.Sheebá:BAAALgADCgYJCwAAAA==.Shishkbob:BAAALgADCgkJCQAAAA==.Shivax:BAAALgAECgYJDgAAAA==.Shugma:BAAALgADCggJCAAAAA==.Shünúkh:BAAALgADCgYJBgAAAA==.',
Si='Sigewulf:BAABLgAFFH8FAAIHAAIJTQ50NgBcAAAHAAIJTQ50NgBcAAABLgAECgcJHgABANoKAA==.Signal:BAAALgAECgEJAQAAAA==.Silhouete:BAAALgAECgcJDQAAAA==.Singbow:BAAALgADCgYJBgABLgAECgkJOAAOALMPAA==.Sinogad:BAABLgAECn8YAAMQAAgJlBHuKgB9AQAQAAgJlBHuKgB9AQAOAAUJ4xMaVwA0AQAAAA==.Sinol:BAAALgAECgYJDwABLgAECggJGAAQAJQRAA==.Sioux:BAAALgADCgEJAQAAAA==.Sixosix:BAAALgADCgIJAgAAAA==.',
Sk='Skaro:BAABLgAECn8eAAMDAAkJKhPTPgBzAQADAAgJvhDTPgBzAQACAAEJOA+VmwA0AAAAAA==.Skaroraks:BAAALgAECgYJAwABLgAECgkJHgADACoTAA==.Skyborn:BAABLgAECn8aAAIGAAkJ1AtebQCgAQAGAAkJ1AtebQCgAQAAAA==.',
Sl='Slamahoochee:BAAALgAECgYJCQAAAA==.Slambulance:BAAALgAECgIJAgABLgAFFAYJEAAHADoaAA==.Slay:BAACLgAFFH8RAAIQAAQJ5B6AGQBOAQAQAAQJ5B6AGQBOAQAuAAQKfyoABBAACAmPISAQAGECABAACAmPISAQAGECAA8ABglkG48TAHgBAA4AAQk/A575ABoAAAAA.',
Sm='Smokedademon:BAAALgAECgMJCQAAAA==.Smokiebear:BAAALgAECgcJEAAAAA==.Smunkie:BAABLgAECn8fAAIBAAcJyiZ0CgCMAgABAAcJyiZ0CgCMAgABLgAECgkJHwAHACglAA==.',
Sn='Snickeers:BAAALgAECgEJAQAAAA==.',
So='Sofa:BAAALgAECgQJBAAAAA==.Somapeace:BAAALgAECgYJCwAAAA==.Somogyi:BAAALgADCgIJAgAAAA==.',
Sp='Spopovich:BAAALgADCggJCAABLgAECgMJAwAKAAAAAA==.Sprints:BAAALgAECgQJBAAAAA==.',
St='Stinko:BAAALgAECgQJBAAAAA==.Stitchlock:BAAALgAECgIJAgAAAA==.Stitchofevil:BAABLgAECn8WAAQjAAcJuBoEBgACAgAjAAYJUB8EBgACAgAVAAQJpAll+wBuAAAIAAIJtQ8hYQBMAAAAAA==.Stonedshaman:BAAALgADCgYJBgABLgAECgIJAgAKAAAAAA==.Stormhands:BAAALgAECgYJDwAAAA==.Stormhugger:BAAALgAFFAEJAQAAAA==.Stormslight:BAAALgAECgQJBQAAAA==.Stoutnholy:BAABLgAECn8eAAITAAkJSwmsfgBxAQATAAkJSwmsfgBxAQAAAA==.Stratichnut:BAABLgAECn84AAMOAAkJsw88OgCsAQAOAAkJsw88OgCsAQAQAAMJSwj/gABGAAAAAA==.Stromar:BAAALgAECgQJBAAAAA==.Stwampadin:BAABLgAECn8iAAIRAAkJriJ/AwBoAwARAAkJriJ/AwBoAwAAAA==.Stwevoker:BAAALgAECgMJAwABLgAECgkJIgARAK4iAA==.Stwonkfu:BAAALgAECggJDAABLgAECgkJIgARAK4iAA==.',
Su='Sumire:BAAALgADCggJDgABLgAECgYJCgAKAAAAAA==.Sunman:BAAALgADCgEJAQAAAA==.Surloyn:BAAALgAECgcJEgAAAA==.',
Sv='Sveny:BAAALgAECgEJAQAAAA==.',
Sw='Swampert:BAACLgAFFH8YAAISAAYJIBiZDACkAQASAAYJIBiZDACkAQAuAAQKfyAAAhIACQmJIOgMAO8CABIACQmJIOgMAO8CAAAA.Swamperting:BAABLgAECn8XAAISAAcJMhPwOQBeAQASAAcJMhPwOQBeAQABLgAFFAYJGAASACAYAA==.Swayaos:BAAALgAFFAIJAgAAAA==.Swaye:BAACLgAFFH8RAAIUAAQJvg6JAwCmAAAUAAQJvg6JAwCmAAAuAAQKfysAAhQACQlUFngYAAMCABQACQlUFngYAAMCAAAA.Sweetfox:BAAALgAECgYJEAAAAA==.Swiftorius:BAAALgAECgYJBgAAAA==.Swimchick:BAABLgAECn8UAAIJAAcJQQgjlAAYAQAJAAcJQQgjlAAYAQAAAA==.Switched:BAAALgADCgcJBwABLgAECgkJHwAHACglAA==.Swizzle:BAAALgAFFAEJAQAAAA==.',
Sy='Syllvanas:BAABLgAECn8hAAMJAAgJmxKsUACwAQAJAAgJEhKsUACwAQAmAAEJ7BmsMwBNAAAAAA==.Syrindra:BAAALgADCgUJAwAAAA==.Sythia:BAACLgAFFH8LAAIdAAQJdhGpFgAKAQAdAAQJdhGpFgAKAQAuAAQKfxgAAh0ACAkhI9MFABoDAB0ACAkhI9MFABoDAAEuAAUUBQkLABUADxUA.',
Ta='Taltost:BAABLgAECn8lAAIJAAkJuRYlLQAoAgAJAAkJuRYlLQAoAgAAAA==.Tantrik:BAAALgADCgEJAQAAAA==.Tartin:BAAALgAECgMJAwAAAA==.Tarv:BAAALgAECgQJBAAAAA==.Tashamirage:BAAALgAECgMJBAAAAA==.Tauriel:BAAALgAECgUJBwAAAA==.',
Te='Teex:BAAALgADCgYJBwAAAA==.Teksuo:BAACLgAFFH8TAAICAAQJLg/OHQDkAAACAAQJLg/OHQDkAAAuAAQKf1QAAgIACQkrH/cIALYCAAIACQkrH/cIALYCAAAA.Telamontay:BAAALgADCgkJFQAAAA==.Telferas:BAABLgAECn8VAAIQAAgJ+RmzJgCYAQAQAAgJ+RmzJgCYAQABLgAFFAgJEQAMAIIgAA==.Tenithon:BAACLgAFFH8NAAMRAAMJ5x6mIgALAQARAAMJ5x6mIgALAQATAAEJMQTivwA+AAAuAAQKfzcAAhEACQnTIsIDAGIDABEACQnTIsIDAGIDAAAA.Tenshenzen:BAABLgAECn8eAAIDAAkJ9RW5GABTAgADAAkJ9RW5GABTAgAAAA==.',
Th='Therandis:BAAALgADCgUJBQAAAA==.Thetombo:BAABLgAECn8UAAITAAYJmQnK2wDjAAATAAYJmQnK2wDjAAAAAA==.Thierry:BAAALgADCgUJBQAAAA==.Thierrye:BAABLgAECn8VAAIbAAYJlhtmTQC/AQAbAAYJlhtmTQC/AQAAAA==.Tholaren:BAABLgAECn89AAMJAAkJ6hSoNAAKAgAJAAkJ6hSoNAAKAgAmAAUJVQc8JQCLAAAAAA==.Threed:BAABLgAECn8WAAMLAAgJ8Q81GwA+AQALAAcJGRE1GwA+AQATAAEJBAmTsgEoAAAAAA==.Threewar:BAAALgAECgIJAgABLgAECgkJFgALAPEPAA==.Thrissa:BAABLgAECn8fAAIOAAkJxxD7LwDjAQAOAAkJxxD7LwDjAQAAAA==.Thulgrim:BAAALgADCgYJBgAAAA==.',
To='Torrque:BAAALgADCgkJCQABLgADCgYJCwAKAAAAAA==.Totemlicker:BAAALgAECgEJAQAAAA==.',
Tr='Trandeath:BAAALgAECgQJBAAAAA==.Trangon:BAABLgAECn8nAAITAAkJlgoGfQB0AQATAAkJlgoGfQB0AQAAAA==.Traplobstah:BAAALgADCgkJCQAAAA==.Traveler:BAAALgADCgEJAQAAAA==.Traygon:BAAALgAECgYJEAAAAA==.Trillion:BAAALgADCggJCAAAAA==.',
Tu='Tunzoffun:BAAALgAECgIJBQAAAA==.',
Un='Unanswered:BAAALgAECgEJAQABLgAFFAYJEAAHADoaAA==.Underbyte:BAAALgADCggJDwAAAA==.Unknownname:BAAALgAECgMJAwAAAA==.',
Ur='Urholiness:BAAALgADCgkJDwAAAA==.',
Va='Vaeleia:BAAALgAECgQJBgAAAA==.Vahnkar:BAAALgADCgYJCQAAAA==.Valentinu:BAAALgADCgcJDwAAAA==.Valkyrie:BAAALgAECgEJAgAAAA==.Vaneshk:BAAALgADCgEJAQAAAA==.Varchemical:BAAALgAECgcJBwAAAA==.Varithal:BAACLgAFFH8TAAIeAAQJkRk8FgAwAQAeAAQJkRk8FgAwAQAuAAQKf0IAAh4ACQngIGsDABEDAB4ACQngIGsDABEDAAEuAAQKAQkBAAoAAAAA.Varri:BAAALgAECgMJBQAAAA==.Varðarvörðr:BAAALgAECgEJAQABLgAECgcJHgABANoKAA==.Vastectomy:BAAALgAECggJDAAAAA==.',
Ve='Vegasana:BAAALgAFFAEJAwAAAA==.Velwing:BAAALgAECgUJBwAAAA==.Venawyn:BAABLgAECn82AAIJAAkJrg5WAwAnAQAJAAkJrg5WAwAnAQAAAA==.Verakhaa:BAAALgAECgQJBAAAAA==.',
Vi='Vibepriest:BAAALgADCgEJAQAAAA==.Vindfaramaðr:BAABLgAECn8eAAIBAAcJ2gqRQAD4AAABAAcJ2gqRQAD4AAAAAA==.Vixin:BAABLgAECn8YAAIFAAcJbxHQVABiAQAFAAcJbxHQVABiAQAAAA==.',
Vo='Voidsaack:BAAALgAFFAEJAQAAAA==.Voidz:BAAALgAECgEJAQAAAA==.Volfguar:BAAALgAECgQJAQAAAA==.Vortan:BAABLgAECn8sAAIhAAkJmBy7CQCCAgAhAAkJmBy7CQCCAgAAAA==.',
Vr='Vreya:BAAALgAECgIJAgABLgAECgUJDwANAKQVAA==.',
Vy='Vynthus:BAAALgAECgcJEgAAAA==.',
['Vä']='Värys:BAAALgAECgEJAQAAAA==.',
Wa='Wan:BAAALgADCgEJAQAAAA==.Warhundin:BAEALgAECgYJEgABLgAFFAMJEAATANMNAA==.Warwan:BAAALgADCgIJAgAAAA==.Watercheck:BAAALgAECgEJAQAAAA==.Wazzbozz:BAAALgAECgQJAwAAAA==.Wazzdh:BAAALgAECgYJCgAAAA==.Wazzdot:BAAALgAECgUJEAAAAA==.Wazzhunnah:BAABLgAECn8nAAMhAAkJ0hROFAACAgAhAAkJ0hROFAACAgAmAAQJZAlhZQCqAAAAAA==.Wazzmage:BAAALgAECgMJAwAAAA==.',
We='Werg:BAAALgAECggJCgABLgAFFAYJDQAiAHELAA==.',
Wh='Whatmyname:BAABLgAECn9SAAIiAAkJWQsRAgCuAAAiAAkJWQsRAgCuAAAAAA==.Whispp:BAAALgAECgYJCAAAAA==.',
Wi='Willough:BAAALgAECgUJCgAAAA==.',
Wo='Wonsok:BAAALgAECgcJEAAAAA==.',
Wy='Wyvoker:BAABLgAECn8mAAIeAAkJPhtMBQDDAgAeAAkJPhtMBQDDAgAAAA==.',
['Wì']='Wìllow:BAAALgADCgIJAgAAAA==.',
['Wÿ']='Wÿm:BAABLgAECn8VAAIMAAgJFx29JgBoAgAMAAgJFx29JgBoAgABLgAECgkJJgAeAD4bAA==.',
Xa='Xaoleth:BAAALgADCgEJAQAAAA==.',
Xe='Xenorion:BAAALgAECgMJAwAAAA==.Xephora:BAAALgAECgEJBgAAAA==.',
Xi='Xiq:BAAALgADCgUJBQAAAA==.',
Xr='Xrinch:BAAALgADCgYJBgAAAA==.',
Xu='Xunadin:BAAALgAECgIJAgAAAA==.Xuny:BAAALgAECgUJEgAAAA==.',
Ya='Yarrggh:BAAALgAECgIJAgAAAA==.',
Yo='Yoonie:BAAALgAECgUJBgAAAA==.Yordi:BAAALgAECgUJEwAAAA==.',
Yu='Yuzuriha:BAACLgAFFH8TAAIJAAQJuyB3JwBpAQAJAAQJuyB3JwBpAQAuAAQKf0IAAgkACQmQJIoFADoDAAkACQmQJIoFADoDAAAA.',
Za='Zaelia:BAAALgADCgYJBgABLgAECgkJPwATAOUeAA==.Zaletren:BAAALgAECgkJCAAAAA==.Zamaze:BAABLgAECn8nAAMWAAkJkCCZBwCIAgAWAAkJkCCZBwCIAgAXAAEJLwm1gwAmAAAAAA==.Zannah:BAAALgAECgMJAwAAAA==.Zant:BAAALgAECgIJAQAAAA==.',
Ze='Zeekielle:BAEBLgAECn88AAIfAAkJFhVVEwD7AQAfAAkJFhVVEwD7AQABLgAFFAMJEAATANMNAA==.Zemesa:BAAALgAECgMJBAAAAA==.Zenius:BAABLgAECn8WAAIYAAgJRBFSFAB1AQAYAAgJRBFSFAB1AQAAAA==.Zerithrielle:BAABLgAECn83AAIfAAgJ2RmuEgAEAgAfAAgJ2RmuEgAEAgAAAA==.',
Zi='Zippii:BAAALgAECgcJCAAAAA==.Zipy:BAABLgAECn89AAIdAAkJBiEaBQAsAwAdAAkJBiEaBQAsAwAAAA==.',
Zo='Zof:BAAALgAECgYJDgAAAA==.Zorathar:BAAALgADCgYJBgAAAA==.',
Zu='Zugtag:BAACLgAFFH8IAAIMAAMJ+SDtCADoAAAMAAMJ+SDtCADoAAAuAAQKfzcAAgwACQmHIWoMAAkDAAwACQmHIWoMAAkDAAAA.',
Zy='Zyllo:BAAALgAECgUJDQAAAA==.',
['Zá']='Závier:BAABLgAECn8UAAIGAAYJ/QK+AgGoAAAGAAYJ/QK+AgGoAAAAAA==.',
['Zõ']='Zõf:BAAALgAECgIJAwABLgAECgYJDgAKAAAAAA==.',
['Äe']='Äemond:BAAALgADCgMJAwAAAA==.',
['Ål']='Ålïce:BAACLgAFFH8GAAITAAMJjQgkfAC+AAATAAMJjQgkfAC+AAAuAAQKf10AAhMACQl1IFkOAPMCABMACQl1IFkOAPMCAAAA.',
['Ëd']='Ëdward:BAAALgADCgcJCgABLgAECgUJFQATAFIGAA==.',
['Ôh']='Ôhmyn:BAAALgAECgUJBQABLgAECgkJJgATALgOAA==.',
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
