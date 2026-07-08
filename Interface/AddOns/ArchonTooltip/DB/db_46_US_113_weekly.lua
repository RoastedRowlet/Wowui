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

local lookup = {'Monk-Windwalker','Monk-Brewmaster','Monk-Mistweaver','Shaman-Elemental','Shaman-Restoration','DemonHunter-Devourer','Mage-Frost','DeathKnight-Blood','Warlock-Destruction','Hunter-BeastMastery','Unknown-Unknown','Paladin-Protection','DeathKnight-Unholy','DeathKnight-Frost','Druid-Restoration','Druid-Feral','Druid-Balance','Paladin-Holy','Warrior-Fury','Paladin-Retribution','Priest-Shadow','Warlock-Demonology','Warrior-Protection','Warrior-Arms','Shaman-Enhancement','Evoker-Devastation','Evoker-Augmentation','Priest-Discipline','Priest-Holy','Evoker-Preservation','DemonHunter-Havoc','Mage-Fire','DemonHunter-Vengeance','Hunter-Survival','Druid-Guardian','Warlock-Affliction','Hunter-Marksmanship','Mage-Arcane','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw',}
local provider = {region='US',realm='GrizzlyHills',name='US',type='weekly',zone=46,date='2026-07-05',data={Ab='Abramz:BAAALgADCgMJAwAAAA==.',
Ac='Achicken:BAAALgAECgEJAQAAAA==.',
Ad='Addely:BAAALgAFFAEJAQAAAA==.Addly:BAAALgAFFAEJAQAAAA==.Adeley:BAACLgAFFH8FAAQBAAMJfwteNQBwAAABAAIJSAheNQBwAAACAAEJ7RHXGgA8AAADAAEJFQPRcQAfAAAuAAQKfxwABAEABwl/GQcoAHgBAAEABwm0FAcoAHgBAAIABgnXErIDAO8AAAMAAwlMAz+nAE4AAAAA.Adely:BAAALgADCgkJCQAAAA==.Adelybeast:BAAALgAECgEJAQAAAA==.Adelymon:BAABLgAECn8bAAMEAAkJlRdEFgA0AgAEAAkJlRdEFgA0AgAFAAUJARD7hQDRAAAAAA==.Adonysroth:BAAALgAECgMJAwAAAA==.Adrahil:BAAALgADCgIJAgAAAA==.',
Ae='Aeonra:BAAALgADCgIJAgAAAA==.',
Ag='Agronak:BAAALgAECgQJBgAAAA==.',
Al='Aldan:BAAALgADCgMJAwAAAA==.Aldazen:BAACLgAFFH8YAAIBAAQJmiQNBwCmAQABAAQJmiQNBwCmAQAuAAQKfz0AAgEACQkeJFcDAC0DAAEACQkeJFcDAC0DAAAA.Alenara:BAABLgAECn8VAAIGAAgJEgsCEAC6AAAGAAgJEgsCEAC6AAABLgAECgkJJAAHANMMAA==.Aletheìa:BAAALgAECgEJAQAAAA==.Alishalian:BAAALgAECgcJDQAAAA==.Alovan:BAAALgADCgEJAQABLgAECgcJHgACANoKAA==.Alterbeast:BAAALgAECgUJBgABLgAFFAYJEAAIADoaAA==.Alyssandra:BAABLgAECn8uAAIJAAkJ2xs/BAA+AgAJAAkJ2xs/BAA+AgAAAA==.',
Am='Amarella:BAABLgAECn8WAAIKAAkJ6R2kKQAQAgAKAAkJ6R2kKQAQAgAAAA==.Amarrite:BAAALgAECgQJCQABLgAECgUJDwALAAAAAA==.Ammalane:BAAALgAECgUJDwAAAA==.Amrah:BAAALgAECgQJCAAAAA==.Amunzo:BAAALgAECgEJAQABLgAECgkJFgAMAPEPAA==.',
An='Angler:BAAALgAECgMJAwAAAA==.Angyrolaj:BAABLgAECn8XAAMNAAcJ0xf8ZQCbAQANAAcJgBf8ZQCbAQAOAAIJdBUXEQCFAAAAAA==.',
Aq='Aquadora:BAAALgADCgMJAwAAAA==.',
Ar='Arangarr:BAABLgAECn8xAAMPAAkJpx0HDgDpAgAPAAkJpx0HDgDpAgAQAAEJ1BFZUQA2AAAAAA==.Arcin:BAAALgADCgEJAQAAAA==.Areyana:BAABLgAECn8dAAIKAAkJehCxTQC5AQAKAAkJehCxTQC5AQAAAA==.Areyoudead:BAAALgAECgQJBAABLgADCgYJCwALAAAAAA==.Ariolas:BAAALgADCgYJCQAAAA==.Aristoi:BAAALgAECgEJAQAAAA==.Arkand:BAAALgADCgUJBAAAAA==.Arkandra:BAABLgAECn8VAAIRAAcJjxf2NQA+AQARAAcJjxf2NQA+AQAAAA==.Arkara:BAAALgADCgEJAQAAAA==.Arrietty:BAABLgAECn86AAISAAkJwxN/BAAzAQASAAkJwxN/BAAzAQAAAA==.Arthues:BAABLgAECn8WAAIMAAgJDBzuCQAuAgAMAAgJDBzuCQAuAgAAAA==.Arthâs:BAAALgAECgYJBQAAAA==.Arumathe:BAABLgAECn8XAAIMAAkJxxICEgCmAQAMAAkJxxICEgCmAQAAAA==.',
As='Asura:BAACLgAFFH8TAAITAAQJWiQZDQCfAQATAAQJWiQZDQCfAQAuAAQKfyAAAhMACQnLItkIAB4DABMACQnLItkIAB4DAAAA.',
Au='Aurelian:BAAALgAECgEJAgAAAA==.',
Ay='Ayisa:BAAALgAECgMJAwAAAA==.',
Az='Az:BAABLgAECn8gAAITAAgJyCQLEAB5AgATAAgJyCQLEAB5AgAAAA==.Azeriall:BAACLgAFFH8XAAIEAAQJnAwPEQDPAAAEAAQJnAwPEQDPAAAuAAQKf0wAAwQACQlwGHgYACACAAQACQlwGHgYACACAAUABAlKAVuGAHsAAAAA.Azerowolf:BAAALgADCggJCAAAAA==.Azráèl:BAAALgADCgMJAwAAAA==.',
Ba='Babyboom:BAAALgAECgEJAQAAAA==.Baconhammr:BAABLgAECn8pAAMUAAkJXw8pEAD2AAAUAAkJXw8pEAD2AAASAAYJhAgRdQBlAAAAAA==.Badazmf:BAAALgADCgcJDAABLgAECgkJNAAVACEbAA==.Badcompany:BAAALgADCgUJBQABLgAECgkJOgAPAFMQAA==.Baddream:BAAALgAECgYJDgAAAA==.Baelmyre:BAAALgADCgUJBQAAAA==.Balenciagosa:BAAALgADCgUJBQABLgAECgkJJAAHANMMAA==.Banshiï:BAABLgAECn89AAIJAAkJhhSxBwDXAQAJAAkJhhSxBwDXAQAAAA==.Baratheøn:BAABLgAECn8xAAIPAAkJvBeuIgA0AgAPAAkJvBeuIgA0AgAAAA==.Bax:BAAALgADCgIJAgAAAA==.Baxar:BAAALgAECgIJAgAAAA==.',
Bb='Bbd:BAAALgAECggJCQABLgAECgYJDgALAAAAAA==.',
Be='Beanz:BAAALgAFFAMJBAAAAA==.Beeftard:BAABLgAECn8YAAISAAkJWRZiKgDfAQASAAkJWRZiKgDfAQAAAA==.Bellavix:BAAALgAECgEJAQAAAA==.Benafflic:BAAALgAECgEJAQABLgAECgUJDAALAAAAAA==.Berserrk:BAAALgADCgYJBgAAAA==.Bershale:BAAALgAECgEJAQABLgAECgYJBwALAAAAAA==.',
Bi='Bifficus:BAABLgAECn8VAAIUAAkJbhcDOgAbAgAUAAkJbhcDOgAbAgAAAA==.Big:BAAALgADCgMJBAAAAA==.Biggiecheese:BAAALgAECgMJBAAAAA==.Bippity:BAAALgAECgIJAwAAAA==.',
Bl='Blackbell:BAAALgAECgMJAwAAAA==.Blackscorn:BAAALgADCgEJAQAAAA==.Blackthôrne:BAAALgAECgYJDgAAAA==.Bloombone:BAAALgADCgQJBAAAAA==.Blucki:BAABLgAECn8fAAIWAAgJ7QmfigAlAQAWAAgJ7QmfigAlAQAAAA==.',
Bo='Bobfu:BAAALgADCgYJCAAAAA==.',
Br='Brieze:BAAALgADCgIJAgAAAA==.Brige:BAAALgAECggJBgAAAA==.Brightstar:BAAALgADCgEJAQAAAA==.Brimaz:BAAALgADCgEJAQAAAA==.',
Bu='Buhhead:BAAALgADCgUJBgAAAA==.Bunana:BAAALgADCgEJAQAAAA==.Bunbear:BAAALgAECgIJAgAAAA==.Bunette:BAAALgADCgEJAQAAAA==.',
Bw='Bwamsamdi:BAAALgADCgYJBgAAAA==.',
By='Byzantium:BAABLgAECn81AAIXAAkJqwnMHgA9AQAXAAkJqwnMHgA9AQAAAA==.',
['Bô']='Bônebeard:BAAALgAECgEJAQAAAA==.',
Ca='Cabledryer:BAAALgAECgQJEAAAAA==.Caelidpackx:BAAALgADCgYJBwAAAA==.Cakron:BAAALgAECgUJBwABLgAECgkJFgAMAPEPAA==.Calamitty:BAAALgAECgUJCAAAAA==.Calistin:BAAALgAECgYJCgAAAA==.Callmedatty:BAAALgAECgEJAQAAAA==.Caluu:BAAALgAECgIJAgAAAA==.Carnry:BAAALgADCgQJBAAAAA==.Catboy:BAABLgAECn8fAAIHAAkJNhZDbgCeAQAHAAkJNhZDbgCeAQAAAA==.Catnips:BAABLgAECn8cAAIUAAgJURhybgCRAQAUAAgJURhybgCRAQAAAA==.Catpow:BAAALgAECgkJAgAAAA==.',
Ch='Chanaranach:BAAALgAECgYJCgAAAA==.Chaosfade:BAAALgAECgEJAQAAAA==.Charitey:BAAALgAECgMJBAAAAA==.Cheelo:BAAALgAECgkJEwAAAA==.Chelyse:BAEALgAECggJBgABLgAFFAMJEQAUANMNAA==.Chknnugget:BAAALgAECgMJBQAAAA==.Chromatic:BAABLgAECn81AAMFAAkJKBj6KAAaAgAFAAgJvxb6KAAaAgAEAAcJUBODOwBHAQAAAA==.',
Ci='Cindrethresh:BAAALgAECgQJCQAAAA==.',
Co='Coffeeblak:BAABLgAECn8ZAAMBAAgJBRNLJgCmAQABAAcJlxNLJgCmAQADAAUJFQ65PwDkAAAAAA==.Coldstorm:BAAALgAECgcJCwAAAA==.Collision:BAAALgAECgkJEgAAAA==.Compensating:BAAALgADCgYJBgAAAA==.Connor:BAAALgADCgcJBwAAAA==.Connsumption:BAAALgAECgYJCgAAAA==.Corrine:BAAALgAECgYJDgAAAA==.',
Cr='Crazybatt:BAABLgAECn8VAAIUAAYJXQaS+ADAAAAUAAYJXQaS+ADAAAAAAA==.Crypt:BAAALgAECgYJCgAAAA==.',
Cu='Cuckchairpov:BAACLgAFFH8OAAMCAAQJJRTFJAAXAQACAAQJpBPFJAAXAQABAAIJQg15DACgAAAuAAQKfywAAwEACQkqH2gKANICAAEACAl4HWgKANICAAIACQndFGYVAAICAAAA.',
Cy='Cynderleena:BAAALgAECgcJCAAAAA==.Cynyia:BAACLgAFFH8GAAIKAAQJUAdoHAABAQAKAAQJUAdoHAABAQAuAAQKfzIAAgoACQkmFSsrAAgCAAoACQkmFSsrAAgCAAAA.',
Cz='Czk:BAAALgADCgYJBgABLgAECggJGQABAAUTAA==.',
['Có']='Cóldblóód:BAAALgAECgIJAgAAAA==.',
Da='Daddyelessar:BAABLgAECn8UAAIIAAgJKRdHFQDDAQAIAAgJKRdHFQDDAQAAAA==.Dafattyup:BAABLgAECn8aAAIWAAYJlRxUYwCgAQAWAAYJlRxUYwCgAQAAAA==.Daghmar:BAAALgADCgUJBQAAAA==.Dagon:BAAALgAECgMJAwAAAA==.Dakotarain:BAAALgADCgIJAgAAAA==.Dalerontwo:BAAALgADCgEJAQAAAA==.Darruin:BAACLgAFFH8UAAMNAAgJ9yD6CQCWAgANAAcJ9yD6CQCWAgAIAAEJAAAZZAAAAAAuAAQKfygAAg0ACQlAJBsGAEgDAA0ACQlAJBsGAEgDAAAA.Dayrun:BAAALgAECgUJDQAAAA==.',
De='Deadicee:BAAALgAECgIJAgABLgAECgYJFAAUAHwOAA==.Deadlyvixin:BAAALgAECgQJBAAAAA==.Deadstorm:BAAALgAECgUJBQAAAA==.Deathtovixin:BAAALgAECgMJAwAAAA==.Deathturtle:BAABLgAECn8eAAINAAgJLxDPlQA8AQANAAgJLxDPlQA8AQAAAA==.Deavaos:BAAALgAECgcJCwAAAA==.Dedmartigan:BAAALgADCgUJBQAAAA==.Deeanndra:BAABLgAECn80AAMNAAkJdRSrCABAAQANAAkJdRSrCABAAQAOAAEJDAkBQQAlAAAAAA==.Deefiler:BAAALgAECgkJAgABLgAECgkJNAANAHUUAA==.Deeversity:BAAALgAECggJAgABLgAECgkJNAANAHUUAA==.Deevz:BAAALgAECgIJAgAAAA==.Demandred:BAAALgAECgYJCQAAAA==.Demiz:BAABLgAECn84AAMFAAkJ5RqMFwCNAgAFAAkJ5RqMFwCNAgAEAAcJug7ISAARAQAAAA==.Deredris:BAAALgAECgQJBAABLgAECgYJCgALAAAAAA==.Dertka:BAAALgAECgYJDAAAAA==.',
Di='Diiviiniity:BAAALgAECgEJAQAAAA==.Discodruid:BAABLgAECn8UAAIPAAYJKRP6UwBAAQAPAAYJKRP6UwBAAQAAAA==.Discover:BAAALgAECgYJBgAAAA==.Dishsoap:BAAALgAECgYJCAABLgAFFAcJGQATAG4WAA==.Dixie:BAAALgAECgIJAgAAAA==.',
Dj='Djall:BAAALgAFFAEJAQAAAA==.Djöflaveiðim:BAAALgAECgIJAgABLgAECgcJHgACANoKAA==.',
Do='Dommy:BAABLgAECn8fAAIIAAkJKCWEAQBJAwAIAAkJKCWEAQBJAwAAAA==.Domw:BAAALgAECgYJDAABLgAECgkJHwAIACglAA==.Donham:BAACLgAFFH8XAAMNAAYJ9xszNwCPAQANAAUJ9xszNwCPAQAIAAEJAABBEwBZAAAuAAQKfx8AAg0ACAnLHzweAMsCAA0ACAnLHzweAMsCAAAA.Dorkimedes:BAABLgAECn8XAAIPAAYJ1BqLAwCIAQAPAAYJ1BqLAwCIAQAAAA==.Dottie:BAABLgAECn8oAAMJAAgJNhM2FwCQAQAJAAcJJQ82FwCQAQAWAAgJ7xHfYAB+AQAAAA==.Dotvinci:BAAALgAECgYJBgAAAA==.',
Dr='Draelesh:BAABLgAECn9AAAIRAAkJwxNIGwDwAQARAAkJwxNIGwDwAQAAAA==.Draenk:BAAALgADCgUJBQAAAA==.Dragún:BAAALgAECgYJCwAAAA==.Drakari:BAAALgADCgYJBgAAAA==.Dramborleg:BAAALgAECgEJAQAAAA==.Drazon:BAAALgADCgIJAgAAAA==.Drewit:BAABLgAECn8WAAIQAAYJPxA1FQBiAQAQAAYJPxA1FQBiAQAAAA==.',
Du='Ducan:BAAALgAECgMJAwAAAA==.Dudeabides:BAAALgAECgcJBwABLgAECgkJHwAMADQGAA==.Duskmane:BAAALgAECgMJCAAAAA==.',
Dw='Dwadler:BAACLgAFFH8QAAMYAAYJCBCNGAAfAQAYAAYJCBCNGAAfAQAXAAMJQxHkHQCpAAAuAAQKfzoAAxcACQmsHcMGAJwCABcACQmsHcMGAJwCABgABQkmFeIxAAABAAAA.',
Dy='Dyrkonian:BAAALgAECggJEgAAAA==.',
Ei='Eireann:BAAALgADCgcJCQAAAA==.',
El='Elerrak:BAAALgAECgEJAQABLgAFFAkJNAAZANIgAA==.Elindalia:BAAALgAECgMJAwAAAA==.',
Em='Emberash:BAAALgAECgEJAQAAAA==.Embre:BAABLgAFFH8MAAMaAAUJsA6NBQALAQAaAAQJsA6NBQALAQAbAAEJAAAmcgAAAAAAAA==.Emorri:BAAALgAECgYJBgAAAA==.Empyrea:BAAALgAECgQJBQAAAA==.',
Er='Eraina:BAAALgADCgIJAgAAAA==.Ericles:BAABLgAECn8ZAAMYAAcJ8R1VDADbAQAYAAcJ8R1VDADbAQATAAIJlAVwlwBkAAAAAA==.Erys:BAAALgAECgcJEQAAAA==.Erébus:BAABLgAECn8kAAIGAAkJ+BhdKAApAgAGAAkJ+BhdKAApAgAAAA==.',
Ev='Ev:BAAALgAECgQJBAAAAA==.Evergreene:BAAALgAECgEJAQABLgAECgUJDwALAAAAAA==.Evibes:BAAALgAECgIJAQAAAA==.Evlpotato:BAABLgAECn80AAQVAAkJIRt6EwA1AgAVAAkJIRt6EwA1AgAcAAcJNBpQIADLAQAdAAEJlAdTfwAzAAAAAA==.Evojak:BAABLgAECn8qAAMbAAkJSQonBQD4AAAbAAkJSQonBQD4AAAaAAMJxAPNHQBgAAAAAA==.',
Fa='Fabiyo:BAAALgADCgMJBQAAAA==.Faevelia:BAAALgAECgUJCAAAAA==.Fairaday:BAACLgAFFH8OAAIKAAQJ5AOjIADtAAAKAAQJ5AOjIADtAAAuAAQKfzcAAgoACQlfCwFXAJ8BAAoACQlfCwFXAJ8BAAAA.Falloon:BAAALgADCgYJBgAAAA==.Fanshen:BAAALgAECgMJBQAAAA==.Farmerdave:BAAALgAECgEJAQAAAA==.Fatdoinkz:BAAALgAECgUJCQABLgAFFAYJEAAIADoaAA==.Fauchi:BAAALgADCgEJAQAAAA==.Faxqueenmage:BAABLgAECn8cAAIHAAgJtwIr9QC9AAAHAAgJtwIr9QC9AAAAAA==.',
Fe='Felador:BAAALgAECgcJEgABLgAECgkJMgAWAIQVAA==.Feldo:BAABLgAECn8SAAIGAAYJjyGYOgDcAQAGAAYJjyGYOgDcAQAAAA==.Felmès:BAAALgADCgYJBgABLgAECgkJJAAHANMMAA==.Fennec:BAAALgAECgUJDAAAAA==.Feralarak:BAAALgAECgcJEwABLgAFFAkJNAAZANIgAA==.Ferl:BAAALgADCgIJAgAAAA==.',
Fi='Figless:BAAALgAECgIJAgABLgAECgcJMwADAGQhAA==.Firebrandd:BAACLgAFFH8cAAMaAAYJzxycAgBcAQAaAAUJnyCcAgBcAQAbAAUJZhHqIwBDAQAuAAQKf0IAAxsACQl8IzcEACYDABsACQmzIjcEACYDABoACAlIImACAA8DAAEuAAUUCAkUAA0A9yAA.Fishtank:BAAALgAECgQJAwABLgAECgkJOAAKAGMgAA==.Fizehbubbleh:BAEALgAECgYJCAABLgAECggJIAAEAOgaAA==.Fizehtotems:BAEBLgAECn8gAAMEAAgJ6BoZLgCKAQAEAAgJ6BoZLgCKAQAFAAUJixZbXwA+AQAAAA==.',
Fl='Fleshoracle:BAAALgAECgQJBAABLgAFFAYJEAAIADoaAA==.Fluctuates:BAAALgAECgQJCAAAAA==.',
Fo='Foragarn:BAAALgAECgYJCQAAAA==.Foron:BAAALgAECgIJAgAAAA==.',
Fr='Frankkastle:BAAALgAECgYJDwAAAA==.Frazelia:BAAALgADCgkJDgABLgAECgYJFgAQAD8QAA==.Fribble:BAABLgAECn8aAAMFAAkJmw6POwDAAQAFAAkJmw6POwDAAQAZAAEJAADwSgAAAAABLgAECgkJHwAMADQGAA==.Fridgexd:BAAALgAECgEJAQABLgAECgYJDgALAAAAAA==.Froggierlynx:BAAALgAFFAQJBAAAAA==.Frostalot:BAAALgAECgMJBwAAAA==.Froznfate:BAABLgAECn89AAMMAAkJkCXpAABWAwAMAAkJkCXpAABWAwAUAAIJpQcVaAFOAAAAAA==.Fryes:BAAALgAECgkJDAAAAA==.',
Fu='Fuzziebutt:BAAALgAECgQJBgAAAA==.',
Fw='Fwibble:BAAALgAECggJEgABLgAECgkJHwAMADQGAA==.',
Fy='Fyrelady:BAAALgAECgMJAwABLgAECgUJEgALAAAAAA==.Fyrestone:BAAALgAECgUJEgAAAA==.',
['Fæ']='Fæder:BAAALgADCgYJBgAAAA==.',
Ga='Gabarnak:BAAALgADCgIJAgABLgAECggJGwADAKEfAA==.Gabuse:BAAALgAECgQJBAAAAA==.Galencharred:BAABLgAECn8uAAIUAAgJsAx4CgBBAQAUAAgJsAx4CgBBAQAAAA==.Garagon:BAABLgAECn9BAAIeAAkJihdMCQBUAgAeAAkJihdMCQBUAgAAAA==.Gauss:BAABLgAECn8fAAIMAAkJNAZkIgABAQAMAAkJNAZkIgABAQAAAA==.Gaîîa:BAABLgAECn8cAAIKAAgJCRq2MADtAQAKAAgJCRq2MADtAQAAAA==.',
Ge='Gelber:BAAALgAECgQJBAAAAA==.Gerva:BAABLgAECn88AAINAAkJORR0NQApAgANAAkJORR0NQApAgAAAA==.',
Gh='Ghlain:BAAALgAECgQJBwAAAA==.Ghorfindor:BAABLgAECn8xAAIfAAgJYgehCQCPAAAfAAgJYgehCQCPAAAAAA==.Ghostlybrew:BAACLgAFFH8VAAICAAcJ9xvmBACHAQACAAcJ9xvmBACHAQAuAAQKfxYAAgIACAmpH94TAHECAAIACAmpH94TAHECAAAA.',
Gi='Gigastorm:BAAALgADCgIJAQAAAA==.Gilas:BAABLgAECn87AAQNAAkJAhXQBAC3AQANAAkJ2hLQBAC3AQAIAAYJdBEsMwDPAAAOAAUJXgWTKACPAAAAAA==.',
Gl='Glaivemstake:BAAALgADCgcJBwAAAA==.Glee:BAAALgAECgMJAwAAAA==.',
Gn='Gnik:BAAALgAECgkJEwAAAA==.Gnikole:BAAALgAECgIJAgABLgAECgkJEwALAAAAAA==.Gnoeme:BAAALgAECgEJAwAAAA==.Gnomewarloc:BAAALgAECgMJAwAAAA==.',
Go='Goswin:BAAALgAECgQJCAAAAA==.Gotmlk:BAAALgADCgEJAQABLgAECgkJDAALAAAAAA==.',
Gr='Graahak:BAAALgADCgMJAwAAAA==.Graveborn:BAABLgAFFH8QAAIIAAYJOhppEAB9AQAIAAYJOhppEAB9AQAAAA==.Graydenton:BAAALgAECgkJCQABLgAECggJBgALAAAAAA==.Greenfelpowa:BAACLgAFFH8IAAMWAAQJ8Qk4HQDpAAAWAAQJMwg4HQDpAAAJAAEJ/wnYDQAzAAAuAAQKfxkAAhYACQmlD4pKALsBABYACQmlD4pKALsBAAAA.Gruu:BAAALgAECgEJAQAAAA==.Gruuven:BAABLgAFFH8FAAIgAAMJ3gW0BACaAAAgAAMJ3gW0BACaAAAAAA==.',
Gu='Gutmtmon:BAABLgAECn8dAAIBAAkJywcQCACmAAABAAkJywcQCACmAAAAAA==.',
Gw='Gwenivive:BAABLgAECn8hAAIKAAkJjBdEKwAwAgAKAAkJjBdEKwAwAgAAAA==.',
['Gí']='Gízmo:BAAALgADCgUJBQAAAA==.',
Ha='Haenus:BAABLgAECn8dAAIGAAgJ8hODfQAlAQAGAAgJ8hODfQAlAQAAAA==.Hamor:BAAALgAECgkJCwAAAA==.Harrynear:BAAALgADCgMJAwABLgAECgcJFwANANMXAA==.Hat:BAACLgAFFH8FAAIGAAIJ9CICZgDBAAAGAAIJ9CICZgDBAAAuAAQKfxkAAwYACQl8IlsHABkDAAYACQl8IlsHABkDACEAAgmRCkstAE0AAAAA.Haunt:BAAALgAECgUJBgAAAA==.Havark:BAAALgAECgMJAwAAAA==.',
He='Healbilly:BAAALgADCgEJAQAAAA==.Healingdeath:BAAALgADCgMJBAAAAA==.Hecatombe:BAAALgADCgUJBQAAAA==.Hellzdruid:BAAALgADCgQJBAAAAA==.Hellzknîght:BAABLgAECn8jAAINAAkJpxLYZQCbAQANAAkJpxLYZQCbAQAAAA==.Hellzshaman:BAAALgADCgIJAQAAAA==.Heyah:BAAALgADCgIJAgAAAA==.',
Ho='Holek:BAABLgAECn8aAAMKAAgJGRNCVACmAQAKAAgJGRNCVACmAQAiAAMJcAT0TACAAAAAAA==.Holgo:BAACLgAFFH8SAAIXAAYJRiP1AgBeAgAXAAYJRiP1AgBeAgAuAAQKfyEAAhcACQluJekBADYDABcACQluJekBADYDAAAA.Holgy:BAACLgAFFH8cAAIjAAYJliTNAgAOAgAjAAYJliTNAgAOAgAuAAQKfyYAAiMACQlWI0wBAEkDACMACQlWI0wBAEkDAAAA.Holybeard:BAACLgAFFH8OAAIUAAYJyhEuWAD/AAAUAAYJyhEuWAD/AAAuAAQKfzkAAhQACAnyIOofAIgCABQACAnyIOofAIgCAAAA.Holysmoker:BAAALgADCgcJBwAAAA==.Holywazzle:BAAALgADCgUJBQAAAA==.Hooks:BAAALgAECgQJDQAAAA==.',
Hu='Hugecowballs:BAAALgAECgkJCQAAAA==.Hunterturtle:BAAALgADCgUJBQAAAA==.',
Ic='Icia:BAAALgAECgQJBgABLgAECgUJBgALAAAAAA==.',
Id='Ideclarewar:BAABLgAFFH8GAAIXAAQJJxehBQBBAQAXAAQJJxehBQBBAQABLgAFFAYJEAAIADoaAA==.Idontmiss:BAAALgAECgIJCAAAAA==.',
Il='Ilickboody:BAAALgADCgQJBAAAAA==.Illustra:BAABLgAECn8aAAMdAAgJnAbmOgALAQAdAAgJnAbmOgALAQAVAAcJ3gJkWwCoAAABLgAECgkJJAAHANMMAA==.',
Im='Imaeru:BAAALgAECgMJAwAAAA==.Imcaldo:BAAALgADCgYJBgAAAA==.Imcaldoo:BAAALgADCgUJCgAAAA==.Imhotness:BAAALgAECgEJAQAAAA==.',
In='Interrupt:BAAALgAECgUJDQAAAA==.',
Ir='Irox:BAAALgADCgMJAwAAAA==.',
Is='Isaic:BAAALgADCgIJAgAAAA==.Iseila:BAABLgAECn8jAAIHAAkJjRDlYgC5AQAHAAkJjRDlYgC5AQAAAA==.Isevio:BAAALgAECgMJBwAAAA==.',
It='Ithorus:BAAALgAECgYJEgAAAA==.Itszof:BAAALgAECgEJAwAAAA==.',
Ja='Jaadb:BAAALgAECgQJBwAAAA==.Jaadd:BAAALgAECgIJAgAAAA==.Jaadi:BAAALgAECgIJAwAAAA==.Jaata:BAAALgADCgcJEAAAAA==.Jairl:BAAALgAECgQJBwAAAA==.Jamien:BAABLgAECn8/AAMUAAkJ5R4dGQCsAgAUAAkJ5R4dGQCsAgASAAUJigUsdwCdAAAAAA==.Janal:BAAALgADCgEJAQAAAA==.Jasnah:BAABLgAECn8lAAMEAAkJPRZdAwCCAQAEAAkJPRZdAwCCAQAFAAQJ0xJAkwCwAAAAAA==.Jasnos:BAAALgAECgUJDwAAAA==.',
Jd='Jdk:BAAALgAECgUJBwAAAA==.',
Je='Jelf:BAAALgAECgUJCQAAAA==.Jenzing:BAABLgAECn8VAAMWAAgJqh0QKwBjAgAWAAcJqh0QKwBjAgAkAAEJAACuIwBjAAAAAA==.Jessemyn:BAABLgAECn8aAAQGAAYJrQk9vACzAAAGAAYJ1AU9vACzAAAfAAQJAAgdWwBXAAAhAAEJZxA+NQAwAAAAAA==.',
Jh='Jholy:BAAALgAECgkJAwAAAA==.',
Jl='Jlockk:BAAALgAECgkJCQAAAA==.',
Jo='Jobokenhones:BAACLgAFFH8IAAIGAAMJ7w8eJgCzAAAGAAMJ7w8eJgCzAAAuAAQKfzEAAgYACQkgGtgjAEACAAYACQkgGtgjAEACAAAA.Johadgan:BAAALgADCgEJAQAAAA==.',
Jp='Jproudmore:BAAALgADCgUJBQABLgADCgYJCwALAAAAAA==.',
Js='Jsberg:BAABLgAECn8gAAITAAgJWRb5LgCTAQATAAgJWRb5LgCTAQAAAA==.',
Ka='Kaathe:BAABLgAECn8lAAMHAAYJGx7ihADHAQAHAAYJGx7ihADHAQAgAAEJjhqXDwA4AAAAAA==.Kaboomalis:BAAALgADCgUJBQAAAA==.Kadance:BAABLgAECn8WAAIEAAcJmRaaNABpAQAEAAcJmRaaNABpAQAAAA==.Kaelyn:BAAALgAECgQJBAABLgAECgYJFQADAJciAA==.Kaidiis:BAABLgAECn8wAAIUAAkJbA8TZgCjAQAUAAkJbA8TZgCjAQAAAA==.Kaido:BAAALgAECgEJAQAAAA==.Kalder:BAAALgADCgcJBwAAAA==.Karbonn:BAABLgAECn8iAAIaAAkJFRV/BQAHAgAaAAkJFRV/BQAHAgAAAA==.Kay:BAAALgAECgcJBwAAAA==.Kazeraz:BAAALgADCgEJAQAAAA==.',
Ke='Kegbreaker:BAACLgAFFH8OAAIdAAQJFAZECwCuAAAdAAQJFAZECwCuAAAuAAQKfzcAAh0ACQlQClwsAGcBAB0ACQlQClwsAGcBAAAA.',
Kh='Khamuur:BAAALgAECgcJDQAAAA==.Khanas:BAABLgAECn8eAAMSAAkJzRU4JQDdAQASAAgJtRY4JQDdAQAUAAEJOQKY0AEYAAAAAA==.Kheru:BAAALgAECgUJBgAAAA==.Khoan:BAAALgAECgYJCgAAAA==.',
Ki='Kimbliddan:BAAALgAECgIJAgABLgAFFAMJBwAHAFgaAA==.Kimbustible:BAACLgAFFH8HAAIHAAMJWBprdQDyAAAHAAMJWBprdQDyAAAuAAQKfzoAAgcACQlBJJEOAAYDAAcACQlBJJEOAAYDAAAA.Kimchi:BAABLgAECn8WAAICAAgJlhDgJwByAQACAAgJlhDgJwByAQABLgAFFAMJBwAHAFgaAA==.Kinpatsu:BAAALgADCgEJAQABLgAECgcJGwAKAEYPAA==.',
Kn='Knockknocko:BAAALgAECgcJDgAAAA==.',
Ko='Kobir:BAAALgADCgEJAQAAAA==.Komodostyle:BAABLgAECn9AAAQbAAkJtxYoPwAtAQAbAAcJYRMoPwAtAQAeAAgJMA66AgDeAAAaAAIJWw64NQBoAAAAAA==.Konny:BAEALgAFFAIJAgABLgAFFAMJEQAUANMNAA==.Koobideh:BAAALgADCgEJAQAAAA==.',
Kr='Krayose:BAABLgAECn8aAAINAAkJwRtOJwBlAgANAAkJwRtOJwBlAgAAAA==.Krian:BAAALgADCgEJAQAAAA==.Kriddler:BAAALgADCgQJBAAAAA==.Krisarugala:BAABLgAECn8XAAIRAAkJWQ/yQgABAQARAAkJWQ/yQgABAQAAAA==.Kriskko:BAAALgAECgEJAgAAAA==.',
Ku='Kujoluvsmilf:BAAALgAECgkJEgAAAA==.Kunuku:BAAALgADCgUJBQAAAA==.Kurash:BAAALgADCgcJBwAAAA==.Kurion:BAAALgAECgkJDgAAAA==.Kurogami:BAABLgAECn8TAAMKAAUJ4AnbFwC4AAAKAAUJ4AnbFwC4AAAlAAMJtAX7BgBDAAAAAA==.',
Ky='Kylesxmom:BAACLgAFFH8VAAMNAAcJgw7ESgBdAQANAAYJgw7ESgBdAQAIAAIJuA0gQgAqAAAuAAQKf2AAAw0ACQltJD0IADEDAA0ACQlAJD0IADEDAAgACAn/HeYRAO8BAAAA.Kymal:BAABLgAECn8+AAIGAAkJ8RYSNwDqAQAGAAkJ8RYSNwDqAQAAAA==.Kymbria:BAAALgADCgUJCAAAAA==.Kymora:BAAALgADCgcJBwAAAA==.Kyndrissa:BAAALgADCgUJBQAAAA==.',
['Kë']='Këy:BAACLgAFFH8MAAINAAMJQBgxmgDbAAANAAMJQBgxmgDbAAAuAAQKfykAAg0ACAnUHYwsAIYCAA0ACAnUHYwsAIYCAAAA.',
La='Laiya:BAAALgADCgEJAQAAAA==.Lancashire:BAAALgADCgUJBwAAAA==.Larthanar:BAAALgAECgYJBgABLgAFFAYJDgAUAMoRAA==.Latrice:BAACLgAFFH8pAAIHAAgJECN7CAC2AgAHAAgJECN7CAC2AgAuAAQKfygABAcACQk5I9wJAHYDAAcACQk5I9wJAHYDACAAAwm4GZEKAM8AACYAAQltGN0YAFEAAAAA.Lavynder:BAABLgAECn8XAAIGAAgJ5hUVWgCTAQAGAAgJ5hUVWgCTAQAAAA==.Lazerturkey:BAAALgAECgkJDwAAAA==.Laërtes:BAABLgAECn8XAAIUAAUJEgm8EQGkAAAUAAUJEgm8EQGkAAAAAA==.',
Le='Leiamirage:BAAALgAECgYJDwAAAA==.Leviscus:BAABLgAECn8VAAInAAUJdx7yAABYAQAnAAUJdx7yAABYAQAAAA==.',
Li='Lifetap:BAAALgADCgMJAwAAAA==.Lightbill:BAABLgAFFH8MAAISAAQJfxkxBwBPAQASAAQJfxkxBwBPAQAAAA==.Lightbàne:BAABLgAECn8qAAIQAAkJ2CLdAQAaAwAQAAkJ2CLdAQAaAwAAAA==.Lightningrod:BAAALgAECgYJBwAAAA==.Lightrogue:BAAALgAECgUJBQABLgAECgkJKgAQANgiAA==.Lightshaolin:BAAALgAECgQJBAAAAA==.Lildruidz:BAABLgAECn8dAAMPAAcJbhPBPwCTAQAPAAcJbhPBPwCTAQARAAEJLQLSpwAYAAAAAA==.Lillivarak:BAABLgAECn8UAAIUAAcJFget2ADnAAAUAAcJFget2ADnAAAAAA==.Lilriotz:BAAALgAFFAEJAgAAAA==.Lilriotzz:BAACLgAFFH8MAAIFAAMJJh2DFgDUAAAFAAMJJh2DFgDUAAAuAAQKfx4AAgUACQntGv0QAMgCAAUACQntGv0QAMgCAAAA.Lilzdrlockz:BAAALgAECgUJDgAAAA==.Lithedra:BAAALgADCgcJDwAAAA==.Littlehand:BAAALgADCgUJBAABLgAECgkJOgASAMMTAA==.',
Lo='Loot:BAABLgAFFH8FAAIEAAUJsBdlHwAkAQAEAAUJsBdlHwAkAQAAAA==.Lovecraft:BAAALgAECgMJAwAAAA==.',
Lu='Lucavi:BAAALgAECgMJAwAAAA==.Lucyvar:BAABLgAECn8XAAIfAAcJBQt8NQDoAAAfAAcJBQt8NQDoAAAAAA==.Luke:BAAALgADCgUJBwAAAA==.Luma:BAAALgAECgUJEAAAAA==.Luther:BAABLgAECn8XAAICAAkJNw9XJQDYAQACAAkJNw9XJQDYAQAAAA==.',
Ly='Lyla:BAAALgADCgQJBgAAAA==.',
Ma='Magiceraser:BAAALgAECgMJAwABLgAFFAcJGQATAG4WAA==.Magnux:BAAALgAECgEJAgAAAA==.Malazark:BAAALgADCgYJBgAAAA==.Malríus:BAAALgAECgQJEQAAAA==.Manales:BAAALgAECgcJBgAAAA==.Marhukai:BAACLgAFFH8LAAIUAAQJgRgKFQAPAQAUAAQJgRgKFQAPAQAuAAQKfy8AAhQACQlBH7kYAK8CABQACQlBH7kYAK8CAAAA.Marici:BAAALgAECgcJBwAAAA==.Marotal:BAACLgAFFH8FAAIHAAUJ/Aj+awALAQAHAAUJ/Aj+awALAQAuAAQKfzEAAgcACQmDFSFFAAwCAAcACQmDFSFFAAwCAAAA.Marr:BAAALgADCgUJBQAAAA==.Martysparty:BAABLgAECn8yAAIMAAkJER0VBwBwAgAMAAkJER0VBwBwAgAAAA==.Mavaena:BAAALgAECgYJEAAAAA==.Mavrane:BAAALgADCgEJAgAAAA==.',
Me='Meashakegs:BAAALgAECggJEQAAAA==.Meashaman:BAAALgAECgMJAwAAAA==.Meatbone:BAAALgAECgEJAQAAAA==.Mebo:BAAALgAECgEJAwAAAA==.Mechaboomer:BAABLgAECn9AAAIKAAkJPB7/FgCdAgAKAAkJPB7/FgCdAgAAAA==.Megafire:BAAALgAECgMJBAAAAA==.Megahertz:BAAALgAECgcJDgAAAA==.Melcanthet:BAAALgADCggJCAAAAA==.Mellowrock:BAAALgAECgUJBgABLgAECgYJBQALAAAAAA==.',
Mi='Mickhaggis:BAAALgADCgIJAgAAAA==.Micktarogar:BAAALgAECgcJEwAAAA==.Mickwutang:BAAALgAFFAEJAQAAAA==.Miklaga:BAAALgAECgEJAgAAAA==.Milince:BAAALgADCgMJAgAAAA==.Milkfridge:BAAALgAECgEJAQABLgAFFAMJBQAQAF4EAA==.Minikloon:BAAALgAECgYJDgAAAA==.Minphoria:BAAALgADCgQJBgAAAA==.Missylock:BAAALgADCgYJBgAAAA==.Mistilinn:BAACLgAFFH8OAAIlAAQJXAG4CgCVAAAlAAQJXAG4CgCVAAAuAAQKfyoAAiUACQldByoTACwBACUACQldByoTACwBAAAA.Miyri:BAAALgAECgEJBQABLgAECgYJFQADAJciAA==.',
Mo='Mollyporph:BAAALgAECgEJAQAAAA==.Monoco:BAABLgAECn8dAAIGAAgJZhNVWQB7AQAGAAgJZhNVWQB7AQAAAA==.Moopandax:BAACLgAFFH8qAAIRAAkJmBx7AQB/AgARAAkJmBx7AQB/AgAuAAQKf4EAAxEACQndJgYAAJ8DABEACQndJgYAAJ8DACMACAkJIA4IAG8CAAAA.Mordric:BAAALgAECgkJCQAAAA==.Mortrum:BAAALgADCgQJBAAAAA==.Moxestime:BAAALgAECgMJBQAAAA==.Moxsdeath:BAAALgAECggJAgAAAA==.Moxsdeaths:BAAALgAECgkJCQAAAA==.Moxshunter:BAAALgAECgEJAgAAAA==.Mozaic:BAAALgADCgEJAQAAAA==.',
Mu='Mushaboom:BAABLgAECn8jAAICAAkJywmvKgBhAQACAAkJywmvKgBhAQAAAA==.Muzzler:BAACLgAFFH8FAAIHAAMJGBTNJgDrAAAHAAMJGBTNJgDrAAAuAAQKf2QAAgcACQmjJEwFAFoDAAcACQmjJEwFAFoDAAAA.',
My='Myeyes:BAAALgAECgEJAwAAAA==.Mylinkah:BAAALgADCgQJBAAAAA==.Mynamefizz:BAEBLgAECn8XAAQWAAkJNBkEMwANAgAWAAkJ9xUEMwANAgAkAAMJeh2XGQD0AAAJAAMJghSiIACoAAABLgAECggJIAAEAOgaAA==.Myotonic:BAAALgADCgQJBAAAAA==.Mythlok:BAAALgAECgMJAwAAAA==.Mythreiel:BAAALgAECgUJBgAAAA==.Mythykal:BAAALgAECgcJDAAAAA==.',
['Mé']='Méasha:BAAALgAECgkJCgAAAA==.',
Na='Nachtmar:BAAALgAECgQJBAABLgAECgkJGgAUAIkPAA==.Nadis:BAAALgAECgIJAwAAAA==.Narcessa:BAAALgADCgQJBAAAAA==.Nawk:BAAALgAECgEJAQAAAA==.',
Ne='Nennerb:BAAALgADCgQJBAAAAA==.',
Ni='Nicola:BAAALgAECgkJEQAAAA==.Nightxwish:BAABLgAECn83AAMcAAkJZBw6AQBgAgAcAAkJZBw6AQBgAgAVAAEJzQ6SFwAxAAAAAA==.Niranye:BAAALgADCgEJAQAAAA==.',
No='Noisemarine:BAACLgAFFH8WAAIXAAUJvxVuFQD0AAAXAAUJvxVuFQD0AAAuAAQKfyUAAhcACQmLG7YIAG0CABcACQmLG7YIAG0CAAAA.Nokk:BAAALgADCgEJAQAAAA==.Nokkco:BAAALgAECgEJAgAAAA==.Nolan:BAAALgAECgQJBAAAAA==.Norellia:BAAALgAECgUJDAAAAA==.Northleo:BAAALgADCgcJEQAAAA==.Northspirit:BAABLgAECn8nAAIEAAgJcwxgBQAlAQAEAAgJcwxgBQAlAQAAAA==.',
Nu='Nuit:BAAALgADCgUJBQABLgAECgYJCwALAAAAAA==.',
Ny='Nyarlothep:BAAALgAECgQJBAAAAA==.Nyx:BAAALgAECgUJBQABLgAECgkJPwAUAOUeAA==.',
Oa='Oakenshièld:BAAALgAECgcJDAAAAA==.',
Od='Odindh:BAAALgAFFAIJAwABLgAFFAMJBAALAAAAAA==.Odins:BAAALgAFFAMJBAAAAA==.',
Oh='Ohwhelp:BAABLgAFFH8JAAIbAAMJ5Bk1OwDaAAAbAAMJ5Bk1OwDaAAABLgAFFAgJLwARAI4kAA==.Ohyikers:BAACLgAFFH8vAAIRAAgJjiScAQDfAgARAAgJjiScAQDfAgAuAAQKfzkAAhEACQnXJogAAIsDABEACQnXJogAAIsDAAAA.',
Ok='Oken:BAAALgADCgUJBQAAAA==.',
Om='Om:BAAALgADCgcJCQAAAA==.',
On='Onlyspirits:BAAALgAECgEJAQAAAA==.',
Op='Open:BAAALgADCgcJBwABLgAECgkJOgASAMMTAA==.Opportunity:BAAALgAECgYJBgABLgAFFAMJDgASAOceAA==.',
Or='Orklock:BAAALgADCgMJAwAAAA==.',
Ot='Otso:BAAALgAECgEJAQAAAA==.',
Pa='Pallek:BAAALgAECgcJBwABLgAECggJGgAKABkTAA==.Palli:BAABLgAECn8gAAISAAcJiRrTBAAlAQASAAcJiRrTBAAlAQAAAA==.Paogao:BAAALgAECgYJCAAAAA==.Parry:BAAALgADCgQJBAAAAA==.Pasghetti:BAAALgADCgMJAwAAAA==.Pasta:BAABLgAECn8vAAIoAAkJSx5dCACgAgAoAAkJSx5dCACgAgAAAA==.',
Pe='Perpetual:BAAALgAECgEJAgAAAA==.Pewpewbite:BAABLgAECn8dAAIKAAkJ5R9vDwDVAgAKAAkJ5R9vDwDVAgAAAA==.',
Ph='Phantomarrow:BAACLgAFFH8VAAQiAAUJQRMGGQAKAQAiAAQJGAwGGQAKAQAlAAUJHQvIHwCtAAAKAAIJPg45hwCOAAAuAAQKfxwABAoABgnsIaNKAMEBAAoABgnsIaNKAMEBACUABQmzGbBCAE0BACIAAQkAAIluAAAAAAAA.Phatcow:BAABLgAECn82AAMFAAkJgxt7FwBaAgAFAAgJaxp7FwBaAgAZAAkJShW1CwD5AQAAAA==.Pheral:BAEBLgAECn8ZAAIQAAkJghiICgAXAgAQAAkJghiICgAXAgABLgAFFAMJEQAUANMNAA==.Phoseidon:BAAALgADCgcJCQAAAA==.Phude:BAACLgAFFH8WAAIUAAQJdhcbOQA6AQAUAAQJdhcbOQA6AQAuAAQKf1cAAhQACQntIaAMAAADABQACQntIaAMAAADAAAA.',
Pi='Pinch:BAAALgAECgMJAwAAAA==.',
Po='Pohl:BAAALgAECgYJDQAAAA==.Pokimana:BAAALgADCgEJAQAAAA==.Poohynok:BAACLgAFFH8LAAIHAAQJlh27TgBBAQAHAAQJlh27TgBBAQAuAAQKfzwAAgcACQkXJVoKACcDAAcACQkXJVoKACcDAAAA.',
Pu='Pukefeast:BAABLgAECn8YAAIHAAgJPBgDbACjAQAHAAgJPBgDbACjAQAAAA==.',
Py='Pyramys:BAACLgAFFH8TAAIoAAUJLB8ADAAjAQAoAAUJLB8ADAAjAQAuAAQKfy0AAigACQmfIwgDACADACgACQmfIwgDACADAAAA.',
['Pè']='Pèrce:BAABLgAECn8WAAQkAAgJ6QNmBgBxAAAWAAYJZwSk0gCvAAAkAAcJ4gJmBgBxAAAJAAIJxQHrbwA2AAAAAA==.',
Qu='Quepaoka:BAAALgADCgIJAgAAAA==.',
Ra='Raklem:BAAALgAECgMJAwABLgAECgYJCgALAAAAAA==.Ramble:BAAALgADCgQJBAABLgAECgYJBwALAAAAAA==.Ramstein:BAAALgAECgMJAwAAAA==.Raphînîty:BAAALgADCgMJBQAAAA==.Rashari:BAAALgADCgYJCAAAAA==.Rawcky:BAAALgAECgQJBAAAAA==.Rawhawk:BAAALgAECgUJDAABLgAECgkJKgAKABoXAA==.Razgrizz:BAABLgAECn8TAAMOAAUJEhjOAgAOAQAOAAUJEhjOAgAOAQANAAMJLBP3+wCxAAAAAA==.',
Re='Retro:BAAALgAECgMJBwAAAA==.Revelatus:BAAALgAECgQJBgAAAA==.Reythanas:BAAALgAECgQJBwAAAA==.Rezzin:BAAALgAECgEJAQAAAA==.',
Ri='Rileyann:BAABLgAECn8fAAMdAAgJOQzdKwBrAQAdAAgJOQzdKwBrAQAVAAYJAwNMRADaAAAAAA==.',
Ro='Rolls:BAAALgAECgQJBAAAAA==.Ronmaclean:BAAALgADCgYJBgABLgAECgcJCwALAAAAAA==.Roozer:BAABLgAECn8VAAIKAAUJiAhnHgCFAAAKAAUJiAhnHgCFAAAAAA==.',
Ru='Runearius:BAAALgAECgcJCwABLgAFFAYJDgAUAMoRAA==.',
['Rå']='Råphå:BAAALgAECgMJBQAAAA==.',
Sa='Sabadahoo:BAAALgAECgEJAQABLgAFFAMJDQAeAIMbAA==.Saelyria:BAACLgAFFH8KAAIPAAMJqxp/MQDpAAAPAAMJqxp/MQDpAAAuAAQKfx8AAw8ACQmmHbIKABIDAA8ACQmmHbIKABIDABEAAQk5EWOMADQAAAEuAAQKBgkVAAMAlyIA.Saga:BAAALgADCgUJBQABLgAECgkJRAAMALwUAA==.Sagepower:BAAALgAECgQJCAAAAA==.Sagethepally:BAAALgAECgcJBAAAAA==.Saintfail:BAABLgAECn8hAAISAAYJ7SSYFQBgAgASAAYJ7SSYFQBgAgABLgAECgcJMwADAGQhAA==.Sainthymn:BAABLgAECn8dAAIcAAYJNSULAgD5AQAcAAYJNSULAgD5AQABLgAECgcJMwADAGQhAA==.Saintmist:BAABLgAECn8zAAIDAAcJZCEODwCxAgADAAcJZCEODwCxAgAAAA==.Salero:BAAALgADCgIJAQAAAA==.Sandiera:BAABLgAECn8kAAMHAAkJ0wxkaACrAQAHAAkJ0wxkaACrAQAmAAMJPAOoFwBcAAAAAA==.Saxtön:BAAALgADCggJEwAAAA==.Sayberix:BAABLgAFFH8MAAQnAAYJ5xH8AAA6AQAnAAQJ9w78AAA6AQApAAMJIREOCQDoAAAoAAQJuQvZDgDgAAABLgAFFAQJDgAYALEcAA==.',
Sc='Scarlett:BAAALgAECgEJAQAAAA==.Scoreboard:BAACLgAFFH8pAAIpAAgJMiE/AACiAgApAAgJMiE/AACiAgAuAAQKfyEAAykACQkgJg0AAOsDACkACQkgJg0AAOsDACgAAQnwFJhaAE8AAAAA.Scorn:BAAALgAECgYJDgAAAA==.Scottx:BAACLgAFFH8FAAIPAAIJmAhWXABiAAAPAAIJmAhWXABiAAAuAAQKfxQAAg8ABwlPFPQ8AJ8BAA8ABwlPFPQ8AJ8BAAAA.Scruff:BAAALgADCgYJDgAAAA==.',
Se='Sebas:BAAALgAECgEJAQAAAA==.Sedric:BAABLgAECn8YAAIRAAcJpgnHRgDxAAARAAcJpgnHRgDxAAAAAA==.Selkz:BAAALgAECgcJDQAAAA==.Selsonblue:BAAALgAECgUJDAAAAA==.Sesskaa:BAABLgAECn8kAAIFAAkJax1tEADNAgAFAAkJax1tEADNAgAAAA==.Severoth:BAAALgAECgMJAwAAAA==.',
Sh='Shadowcursed:BAAALgADCgcJCgAAAA==.Shadowstorm:BAAALgADCgQJBAAAAA==.Shadøws:BAAALgAECgEJAQAAAA==.Shakenhealz:BAAALgADCgYJBgAAAA==.Shaldria:BAAALgADCgEJAQAAAA==.Sharhox:BAAALgAECgQJCAAAAA==.Shathos:BAAALgADCgEJAQAAAA==.Sheebá:BAAALgADCgYJCwAAAA==.Shishkbob:BAAALgADCgkJCQAAAA==.Shivax:BAAALgAECgYJDgAAAA==.Shugma:BAAALgADCggJCAAAAA==.Shünúkh:BAAALgADCgYJBgAAAA==.',
Si='Sigewulf:BAABLgAFFH8FAAIIAAIJTQ5yNgBcAAAIAAIJTQ5yNgBcAAABLgAECgcJHgACANoKAA==.Signal:BAAALgAECgEJAQAAAA==.Silhouete:BAAALgAECgkJEAAAAA==.Singbow:BAAALgADCgYJBgABLgAECgkJOgAPAFMQAA==.Sinoga:BAAALgAECgYJBgABLgAECggJGAARAJQRAA==.Sinogad:BAABLgAECn8YAAMRAAgJlBHvKgB9AQARAAgJlBHvKgB9AQAPAAUJ4xMWVwA0AQAAAA==.Sinol:BAAALgAECgYJDwABLgAECggJGAARAJQRAA==.Sioux:BAAALgADCgEJAQAAAA==.Sixosix:BAAALgADCgIJAgAAAA==.',
Sk='Skaro:BAABLgAECn8iAAMDAAkJZhPUPgBzAQADAAgJARHUPgBzAQABAAEJOA+VmwA0AAAAAA==.Skaroraks:BAAALgAECgYJAwABLgAECgkJIgADAGYTAA==.Skyborn:BAABLgAECn8aAAIHAAkJ1AtebQCgAQAHAAkJ1AtebQCgAQAAAA==.',
Sl='Slamahoochee:BAAALgAECgYJCQAAAA==.Slambulance:BAAALgAECgIJAgABLgAFFAYJEAAIADoaAA==.Slay:BAACLgAFFH8RAAIRAAQJ5B51GQBOAQARAAQJ5B51GQBOAQAuAAQKfyoABBEACAmPISIQAGECABEACAmPISIQAGECABAABglkG48TAHgBAA8AAQk/A5z5ABoAAAAA.',
Sm='Smokedademon:BAAALgAECgMJCQAAAA==.Smokiebear:BAAALgAECgcJEAAAAA==.Smunkie:BAABLgAECn8fAAICAAcJyiZ0CgCMAgACAAcJyiZ0CgCMAgABLgAECgkJHwAIACglAA==.',
Sn='Snickeers:BAAALgAECgEJAQAAAA==.',
So='Sofa:BAAALgAECgQJBAAAAA==.Somapeace:BAAALgAECgYJCwAAAA==.Somogyi:BAAALgADCgIJAgAAAA==.',
Sp='Spopovich:BAAALgADCggJCAABLgAECgMJAwALAAAAAA==.Sprints:BAAALgAECgQJBAAAAA==.',
St='Stinko:BAAALgAECgQJAwAAAA==.Stitchlock:BAAALgAECgIJAgAAAA==.Stitchofevil:BAABLgAECn8WAAQkAAcJuBoEBgACAgAkAAYJUB8EBgACAgAWAAQJpAll+wBuAAAJAAIJtQ8hYQBMAAAAAA==.Stonedshaman:BAAALgADCgYJBgABLgAECgIJAgALAAAAAA==.Stormhands:BAAALgAECgYJDwAAAA==.Stormhugger:BAAALgAFFAEJAQAAAA==.Stormslight:BAAALgAECgQJBQAAAA==.Stoutnholy:BAABLgAECn8eAAIUAAkJSwmpfgBxAQAUAAkJSwmpfgBxAQAAAA==.Stratichnut:BAABLgAECn86AAMPAAkJUxA5OgCsAQAPAAkJUxA5OgCsAQARAAMJSwgAgQBGAAAAAA==.Stromar:BAAALgAECgQJBAAAAA==.Stwampadin:BAABLgAECn8iAAISAAkJriJ/AwBoAwASAAkJriJ/AwBoAwAAAA==.Stwevoker:BAAALgAECgMJAwABLgAECgkJIgASAK4iAA==.Stwonkfu:BAAALgAECggJDAABLgAECgkJIgASAK4iAA==.',
Su='Sumire:BAAALgADCggJDgABLgAECgYJCgALAAAAAA==.Sunman:BAAALgADCgEJAQAAAA==.Surloyn:BAAALgAECgcJEgAAAA==.',
Sv='Sveny:BAAALgAECgEJAQAAAA==.',
Sw='Swampert:BAACLgAFFH8ZAAITAAcJbhaMDACkAQATAAcJbhaMDACkAQAuAAQKfyAAAhMACQmJIOgMAO8CABMACQmJIOgMAO8CAAAA.Swamperting:BAABLgAECn8ZAAITAAgJ0xfxOQBeAQATAAgJ0xfxOQBeAQABLgAFFAcJGQATAG4WAA==.Swayaos:BAABLgAFFH8HAAMWAAMJkAI9MwCLAAAWAAMJkAI9MwCLAAAJAAIJmwFCHABaAAAAAA==.Swaye:BAACLgAFFH8YAAIVAAQJvg71CgDoAAAVAAQJvg71CgDoAAAuAAQKfysAAhUACQlUFngYAAMCABUACQlUFngYAAMCAAAA.Sweetfox:BAAALgAECgYJEAAAAA==.Swiftorius:BAAALgAECgYJBgAAAA==.Swimchick:BAABLgAECn8bAAIKAAcJRg9ODAAyAQAKAAcJRg9ODAAyAQAAAA==.Switched:BAAALgADCgcJBwABLgAECgkJHwAIACglAA==.Swizzle:BAAALgAFFAEJAQAAAA==.',
Sy='Syfa:BAAALgAECgkJAQAAAA==.Syllvanas:BAABLgAECn8hAAMKAAgJmxKsUACwAQAKAAgJEhKsUACwAQAlAAEJ7BmpMwBNAAAAAA==.Syrindra:BAAALgADCgUJAwAAAA==.Sythia:BAACLgAFFH8QAAIdAAUJlQ93CADgAAAdAAUJlQ93CADgAAAuAAQKfxgAAh0ACAkhI9IFABoDAB0ACAkhI9IFABoDAAAA.',
Ta='Taltost:BAABLgAECn8qAAIKAAkJGheyBQC+AQAKAAkJGheyBQC+AQAAAA==.Tantrik:BAAALgADCgEJAQAAAA==.Tartin:BAAALgAECgMJAwAAAA==.Tarv:BAAALgAECgUJBQAAAA==.Tarvält:BAAALgAECgMJAwAAAA==.Tashamirage:BAAALgAECgMJBAAAAA==.Tatofarmer:BAAALgAECgcJBwAAAA==.Tauriel:BAAALgAECgUJBwAAAA==.',
Te='Teex:BAAALgADCgYJBwAAAA==.Teksuo:BAACLgAFFH8XAAIBAAQJ6Q9FCQDMAAABAAQJ6Q9FCQDMAAAuAAQKf1sAAgEACQmAH/cIALYCAAEACQmAH/cIALYCAAAA.Telamontay:BAAALgADCgkJFQAAAA==.Telferas:BAABLgAECn8VAAIRAAgJ+Rm2JgCYAQARAAgJ+Rm2JgCYAQABLgAFFAgJFAANAPcgAA==.Tenithon:BAACLgAFFH8OAAMSAAMJ5x6gIgALAQASAAMJ5x6gIgALAQAUAAEJMQTbvwA+AAAuAAQKfzwAAhIACQnTIsEDAGIDABIACQnTIsEDAGIDAAAA.Tenshenzen:BAABLgAECn8eAAIDAAkJ9RW3GABTAgADAAkJ9RW3GABTAgAAAA==.',
Th='Therandis:BAAALgADCgUJBQAAAA==.Thetombo:BAABLgAECn8UAAIUAAYJmQnN2wDjAAAUAAYJmQnN2wDjAAAAAA==.Thierry:BAAALgADCgUJBQAAAA==.Thierrye:BAABLgAECn8VAAIGAAYJlhtmTQC/AQAGAAYJlhtmTQC/AQAAAA==.Tholaren:BAABLgAECn8/AAMKAAkJEhWqNAAKAgAKAAkJEhWqNAAKAgAlAAUJVQc8JQCLAAAAAA==.Threed:BAABLgAECn8WAAMMAAgJ8Q80GwA+AQAMAAcJGRE0GwA+AQAUAAEJBAmVsgEoAAAAAA==.Threewar:BAAALgAECgQJBgABLgAECgkJFgAMAPEPAA==.Thrissa:BAABLgAECn8jAAIPAAkJqxL5LwDjAQAPAAkJqxL5LwDjAQAAAA==.Thulgrim:BAAALgADCgYJBgAAAA==.',
To='Torrque:BAAALgADCgkJCQABLgADCgYJCwALAAAAAA==.Totemicdeath:BAAALgADCgMJAwAAAA==.Totemlicker:BAAALgAECgEJAQAAAA==.',
Tr='Trandeath:BAAALgAECgQJBAAAAA==.Trangon:BAABLgAECn8nAAIUAAkJlgoDfQB0AQAUAAkJlgoDfQB0AQAAAA==.Traplobstah:BAAALgADCgkJCQAAAA==.Traveler:BAAALgADCgEJAQAAAA==.Traygon:BAAALgAECgYJEAAAAA==.Trillion:BAAALgADCggJCAAAAA==.',
Tu='Tunakue:BAAALgAECgEJAQABLgAFFAQJHQAUAFscAA==.Tunzoffun:BAAALgAECgIJBQAAAA==.',
Un='Unanswered:BAAALgAECgEJAQABLgAFFAYJEAAIADoaAA==.Underbyte:BAAALgADCggJDwAAAA==.Unknownname:BAAALgAECgQJBAAAAA==.',
Ur='Urholiness:BAAALgADCgkJDwAAAA==.',
Va='Vaeleia:BAAALgAECgQJBgAAAA==.Vahnkar:BAAALgADCgYJCQAAAA==.Valentinu:BAAALgADCgcJDwAAAA==.Valkyrie:BAAALgAECgEJAgAAAA==.Vaneshk:BAAALgADCgEJAQAAAA==.Varchemical:BAAALgAECgcJBwAAAA==.Varithal:BAACLgAFFH8XAAIeAAQJkRnzBwDdAAAeAAQJkRnzBwDdAAAuAAQKf0YAAh4ACQngIGsDABEDAB4ACQngIGsDABEDAAEuAAQKAQkBAAsAAAAA.Varri:BAAALgAECgMJBQAAAA==.Varðarvörðr:BAAALgAECgEJAgABLgAECgcJHgACANoKAA==.Vastectomy:BAAALgAECggJDAAAAA==.',
Ve='Vegasana:BAAALgAFFAEJAwAAAA==.Velwing:BAAALgAECgUJBwAAAA==.Venawyn:BAABLgAECn88AAIKAAkJWRFTCAB5AQAKAAkJWRFTCAB5AQAAAA==.Verakhaa:BAAALgAECgQJBAAAAA==.',
Vi='Vibepriest:BAAALgADCgEJAQAAAA==.Vindfaramaðr:BAABLgAECn8eAAICAAcJ2gqVQAD4AAACAAcJ2gqVQAD4AAAAAA==.Vixin:BAABLgAECn8jAAMFAAgJWhVYAwDuAQAFAAgJWhVYAwDuAQAEAAEJQQvfGwAnAAAAAA==.',
Vo='Voidsaack:BAAALgAFFAEJAQAAAA==.Voidz:BAAALgAECgEJAQAAAA==.Volfguar:BAAALgAECgQJAQAAAA==.Vortan:BAABLgAECn8sAAIiAAkJTxy6CQCDAgAiAAkJTxy6CQCDAgAAAA==.',
Vr='Vreya:BAAALgAECgIJAgABLgAECgUJEwAOABIYAA==.',
Vy='Vynthus:BAAALgAECgcJEgAAAA==.',
['Vä']='Värys:BAAALgAECgEJAQAAAA==.',
Wa='Wan:BAAALgADCgEJAQAAAA==.Warhundin:BAEALgAECgYJEgABLgAFFAMJEQAUANMNAA==.Warwan:BAAALgADCgIJAgAAAA==.Watercheck:BAAALgAECgEJAQAAAA==.Wazzbozz:BAAALgAECgQJAwAAAA==.Wazzdh:BAAALgAECgYJCgAAAA==.Wazzdot:BAAALgAECgUJEAAAAA==.Wazzhunnah:BAABLgAECn8nAAMiAAkJ0hRKFAACAgAiAAkJ0hRKFAACAgAlAAQJZAlhZQCqAAAAAA==.Wazzmage:BAAALgAECgMJAwAAAA==.Wazzvoker:BAAALgADCgQJBAAAAA==.',
We='Werg:BAAALgAECggJCgABLgAFFAYJDQAjAHELAA==.',
Wh='Whatmyname:BAABLgAECn9YAAIjAAkJ+gssBQD/AAAjAAkJ+gssBQD/AAAAAA==.Whispp:BAAALgAECgYJCAAAAA==.',
Wi='Willough:BAAALgAECgYJDwAAAA==.',
Wo='Wonsok:BAAALgAECgcJEAAAAA==.',
Wy='Wyvoker:BAABLgAECn8mAAIeAAkJPhtMBQDDAgAeAAkJPhtMBQDDAgAAAA==.',
['Wì']='Wìllow:BAAALgADCgIJAgAAAA==.',
['Wÿ']='Wÿm:BAABLgAECn8VAAINAAgJFx29JgBoAgANAAgJFx29JgBoAgABLgAECgkJJgAeAD4bAA==.',
Xa='Xaoleth:BAAALgADCgEJAQAAAA==.',
Xe='Xenorion:BAAALgAECgMJAwAAAA==.Xephora:BAAALgAECgEJBwAAAA==.',
Xi='Xiq:BAAALgADCgUJBQAAAA==.',
Xr='Xrinch:BAAALgADCgYJBgAAAA==.',
Xu='Xunadin:BAAALgAECgIJAgAAAA==.Xuny:BAAALgAECgYJEwAAAA==.',
Ya='Yarrggh:BAAALgAECgMJBQAAAA==.',
Yo='Yoonie:BAAALgAECgUJBgAAAA==.Yordi:BAAALgAECgUJEwAAAA==.',
Yu='Yuzuriha:BAACLgAFFH8XAAIKAAQJRSEbEABWAQAKAAQJRSEbEABWAQAuAAQKf0UAAgoACQm9JIgFADoDAAoACQm9JIgFADoDAAAA.',
Za='Zaelia:BAAALgADCgYJBgABLgAECgkJPwAUAOUeAA==.Zaletren:BAAALgAECgkJCAAAAA==.Zalthar:BAAALgADCgEJAQAAAA==.Zamaze:BAABLgAECn8nAAMXAAkJkCCYBwCIAgAXAAkJkCCYBwCIAgAYAAEJLwm1gwAmAAAAAA==.Zannah:BAAALgAECgMJAwAAAA==.Zant:BAAALgAECgIJAQAAAA==.',
Ze='Zeekielle:BAEBLgAECn88AAIfAAkJFhVTEwD7AQAfAAkJFhVTEwD7AQABLgAFFAMJEQAUANMNAA==.Zemesa:BAAALgAECgMJBAAAAA==.Zenius:BAABLgAECn8fAAIZAAkJMxW3AAAPAgAZAAkJMxW3AAAPAgAAAA==.Zerithrielle:BAABLgAECn8/AAIfAAkJzhkoAgC8AQAfAAkJzhkoAgC8AQAAAA==.',
Zi='Zippii:BAAALgAECgcJCAAAAA==.Zipy:BAABLgAECn8/AAIdAAkJ7iAZBQAsAwAdAAkJ7iAZBQAsAwAAAA==.',
Zo='Zof:BAAALgAECgYJDgAAAA==.Zorathar:BAAALgADCgYJBgAAAA==.',
Zu='Zugtag:BAACLgAFFH8OAAMOAAQJ7B03BgD7AAAOAAMJKxY3BgD7AAANAAMJ+SCmLQDlAAAuAAQKfzcAAg0ACQmHIWsMAAkDAA0ACQmHIWsMAAkDAAAA.',
Zy='Zyllo:BAAALgAECgUJDQAAAA==.',
['Zá']='Závier:BAABLgAECn8UAAIHAAYJ/QLFAgGoAAAHAAYJ/QLFAgGoAAAAAA==.',
['Zõ']='Zõf:BAAALgAECgIJAwABLgAECgYJDgALAAAAAA==.',
['Äe']='Äemond:BAAALgADCgMJAwAAAA==.',
['Ål']='Ålïce:BAACLgAFFH8GAAIUAAMJjQgcfAC+AAAUAAMJjQgcfAC+AAAuAAQKf10AAhQACQl1IFsOAPMCABQACQl1IFsOAPMCAAAA.',
['Ëd']='Ëdward:BAAALgADCgcJCgABLgAECgUJFwAUABIJAA==.',
['Ôh']='Ôhmyn:BAAALgAECgUJBQABLgAECgkJKQAUAF8PAA==.',
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
