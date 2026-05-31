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

local lookup = {'Warlock-Destruction','Hunter-BeastMastery','Unknown-Unknown','Mage-Arcane','Mage-Frost','Hunter-Survival','DeathKnight-Frost','DeathKnight-Unholy','Priest-Shadow','Paladin-Retribution','Priest-Holy','Hunter-Marksmanship','Paladin-Protection','DemonHunter-Devourer','DeathKnight-Blood','Monk-Mistweaver','Monk-Windwalker','Paladin-Holy','Druid-Balance','Shaman-Restoration','Rogue-Subtlety','DemonHunter-Havoc','Rogue-Outlaw','Rogue-Assassination','Warlock-Demonology','Warrior-Arms','Priest-Discipline','Monk-Brewmaster','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Warrior-Fury','Druid-Feral','Shaman-Elemental','Druid-Restoration','Warlock-Affliction','Druid-Guardian','Shaman-Enhancement',}
local provider = {region='US',realm='Azuremyst',name='US',type='weekly',zone=46,date='2026-05-30',data={Aa='Aaravos:BAABLgAECn8UAAIBAAgJLxNxCQCUAQABAAgJLxNxCQCUAQAAAA==.',
Ab='Abysseon:BAAALgAECgUJDgAAAA==.',
Ac='Accretion:BAAALgAECgYJBgAAAA==.',
Ad='Adaria:BAABLgAECn8WAAICAAcJWAWSZQA3AQACAAcJWAWSZQA3AQAAAA==.Adrillbear:BAAALgAECgIJAgABLgAECgYJDgADAAAAAA==.Adura:BAAALgADCggJFQAAAA==.',
Ae='Aeirith:BAACLgAFFH8HAAIEAAMJSxdyAQDuAAAEAAMJSxdyAQDuAAAuAAQKfyQAAwQACQmwHZABAHMCAAQACQmwHZABAHMCAAUAAQlFCn9FATIAAAAA.Aelion:BAAALgAECgEJAQAAAA==.',
Ah='Ahheevoker:BAAALgAECgYJEgAAAA==.',
Ai='Ailsà:BAAALgADCgEJAQAAAA==.',
Al='Aladaria:BAAALgAECgMJAwAAAA==.Aldyah:BAAALgAECgYJCQAAAA==.Alias:BAAALgAECgYJBQAAAA==.Allanonn:BAAALgAECgQJBAAAAA==.Alohomora:BAAALgAECgUJEAAAAA==.Alvist:BAAALgAECgQJEAAAAA==.',
Am='Amarasu:BAABLgAECn8aAAIGAAgJUxDFIACIAQAGAAgJUxDFIACIAQAAAA==.Amarlly:BAABLgAECn8nAAIHAAgJEhZiCQDAAQAHAAgJEhZiCQDAAQAAAA==.Amenedil:BAAALgAECgUJDAAAAA==.',
An='Anbrew:BAAALgAECgYJDgABLgAFFAYJDwAIAN0dAA==.Ancelina:BAABLgAECn8jAAIJAAgJSiRsBgDSAgAJAAgJSiRsBgDSAgAAAA==.Anderton:BAABLgAECn8sAAIKAAgJShmsQwDjAQAKAAgJShmsQwDjAQAAAA==.Andilocks:BAAALgADCgMJAwAAAA==.Aneira:BAAALgAECgUJDAAAAA==.Annovera:BAAALgAECgMJBgAAAA==.Anuubis:BAAALgADCgYJBgAAAA==.Anyi:BAAALgAECgEJAQAAAA==.',
Ap='Apexxd:BAAALgADCgYJCwAAAA==.Applefritter:BAAALgAECgUJCAABLgAECggJIwALAFAUAA==.',
Ar='Archérhiro:BAACLgAFFH8eAAMCAAgJbRT4BQAGAgACAAcJ/xb4BQAGAgAMAAMJRwTfIQCHAAAuAAQKfygAAwIACQnrHuYVAI4CAAIACQnfHuYVAI4CAAwACAkrGdobAEoCAAAA.Arilias:BAAALgAECgEJAQABLgAECgkJKAACAKcSAA==.Arillann:BAABLgAECn89AAINAAkJUR/eAwC0AgANAAkJUR/eAwC0AgAAAA==.Arrook:BAAALgADCgMJAwAAAA==.Arte:BAABLgAECn89AAICAAkJaxOZPADWAQACAAkJaxOZPADWAQAAAA==.Arthundermis:BAAALgAECgkJEQAAAA==.Artlunarmis:BAAALgADCgEJAQABLgAECgkJEQADAAAAAA==.Arvena:BAABLgAECn8nAAIOAAkJVgpLagA2AQAOAAkJVgpLagA2AQAAAA==.',
As='Asclëpius:BAAALgADCgcJBgABLgAECgEJAQADAAAAAA==.Asheron:BAAALgAECgYJCAAAAA==.Ashylock:BAAALgAECgEJAQABLgAFFAQJDAAFAGAWAA==.Ashymage:BAACLgAFFH8MAAIFAAQJYBbGTAA2AQAFAAQJYBbGTAA2AQAuAAQKfzcAAgUACQlYHLYpAMwCAAUACQlYHLYpAMwCAAAA.Askevar:BAABLgAECn8eAAMIAAgJlQpqiAA+AQAIAAgJfghqiAA+AQAPAAYJ5wlHJwAEAQAAAA==.Aspect:BAAALgADCgEJAQABLgAFFAIJAgADAAAAAA==.Asriél:BAAALgAECgQJBAAAAA==.Astrona:BAAALgADCgkJFwAAAA==.',
At='Atreus:BAABLgAECn8XAAIKAAgJPgVNywDbAAAKAAgJPgVNywDbAAAAAA==.Attalaguy:BAAALgAECgYJDgAAAA==.',
Au='Audra:BAAALgADCgUJBwAAAA==.',
Av='Avabeatrix:BAAALgADCgEJAQAAAA==.Avinthoro:BAAALgADCgIJAgAAAA==.',
Ay='Ayyayyron:BAAALgAECgUJCAAAAA==.',
Az='Azaleah:BAABLgAECn85AAIKAAkJtRqMIABuAgAKAAkJtRqMIABuAgAAAA==.Azanoth:BAAALgADCgIJAgAAAA==.Azraesha:BAABLgAECn8rAAIOAAkJ/BUPJQAkAgAOAAkJ/BUPJQAkAgAAAA==.Azureflamez:BAAALgAECgEJAQAAAA==.Azzul:BAAALgADCgcJBwAAAA==.',
Ba='Baiken:BAAALgAECgIJAgABLgAECgQJCAADAAAAAA==.Banjoman:BAABLgAECn8kAAILAAcJXSQcCQDCAgALAAcJXSQcCQDCAgAAAA==.Baza:BAAALgADCgYJBgAAAA==.Baýlei:BAABLgAECn8WAAIQAAYJ5A3MTAAEAQAQAAYJ5A3MTAAEAQAAAA==.',
Be='Beary:BAAALgAECgQJCAAAAA==.Beenaughty:BAAALgAECgEJAQABLgAECgEJAQADAAAAAA==.Belaanna:BAAALgADCgYJCQAAAA==.Beliria:BAAALgADCgUJBgAAAA==.Benimaru:BAAALgAECgQJCAAAAA==.Beriko:BAAALgAECgMJAwAAAA==.Bernat:BAAALgAECgEJAQAAAA==.Beàrdfáce:BAAALgADCgQJBAAAAA==.',
Bi='Bigblunt:BAAALgADCgUJBQAAAA==.Bigjuicy:BAAALgAECggJCgAAAA==.Billie:BAAALgADCgcJBwAAAA==.Bimboficate:BAAALgADCgYJBwAAAA==.',
Bl='Black:BAAALgAECgQJBAAAAA==.Blackadder:BAAALgAECgUJDwAAAA==.Blessthefall:BAAALgAECgYJCgAAAA==.Blondie:BAAALgADCgQJBAABLgAECgYJEQADAAAAAA==.Bloodie:BAAALgAECgMJAwAAAA==.Blue:BAABLgAECn88AAIRAAkJxRvgDABiAgARAAkJxRvgDABiAgAAAA==.Bluestreak:BAAALgAECgEJAwABLgAECgcJCQADAAAAAA==.',
Bo='Bode:BAAALgAECgYJEwAAAA==.Bogern:BAAALgADCgcJBwAAAA==.Bolau:BAAALgADCgYJBwAAAA==.Boltz:BAAALgADCgYJBgAAAA==.Boogy:BAAALgAECgYJBgAAAA==.Bopdiz:BAAALgAECgEJAQABLgAECgQJEAADAAAAAA==.Borledish:BAAALgAECgMJBAABLgAECgQJEAADAAAAAA==.Bottosai:BAAALgAECgEJAgAAAA==.',
Br='Branwynn:BAAALgAECgEJBgAAAA==.Breezyfight:BAAALgAECgYJCAAAAA==.Breezysha:BAAALgADCgcJCAAAAA==.Brenz:BAABLgAFFH8FAAMKAAMJOQK3mQBFAAAKAAIJ9gC3mQBFAAANAAEJvQQNFwApAAAAAA==.Brewdaddy:BAAALgAECgUJDwABLgAECggJMAASAKwQAA==.Brewdude:BAAALgAECgEJAQAAAA==.Brigor:BAAALgADCgkJCwAAAA==.Brokenblade:BAAALgADCgYJBgAAAA==.Brotherblood:BAAALgAECgMJAwAAAA==.',
Bu='Bulldoza:BAAALgAECgQJBQAAAA==.Bullwinkles:BAAALgAECgEJAQAAAA==.Butterknifeo:BAABLgAFFH8FAAITAAMJxxQ6KQC8AAATAAMJxxQ6KQC8AAAAAA==.',
By='Byryja:BAAALgAECgUJDwAAAA==.',
Ca='Cahrazie:BAAALgAFFAEJAgAAAA==.Caidinn:BAAALgAECgkJEQAAAA==.Caitrîn:BAAALgADCgkJCQABLgAECgUJDAADAAAAAA==.Calissancia:BAABLgAECn8xAAIQAAgJ2hXRHwD0AQAQAAgJ2hXRHwD0AQAAAA==.Calkey:BAABLgAECn8WAAIBAAYJUQjyGgC5AAABAAYJUQjyGgC5AAAAAA==.Cathandris:BAAALgADCgEJAQAAAA==.',
Ce='Ceri:BAAALgAECgkJBwAAAA==.',
Ch='Channingtotm:BAACLgAFFH8bAAIUAAQJHiSSEQCnAQAUAAQJHiSSEQCnAQAuAAQKfzUAAhQACQlhIXQDAHIDABQACQlhIXQDAHIDAAAA.Chantix:BAAALgADCgUJBQAAAA==.Charlemoo:BAAALgADCgUJBQABLgAECgMJAwADAAAAAA==.Cheekymonkey:BAABLgAECn8iAAIEAAgJ8woIBgBNAQAEAAgJ8woIBgBNAQAAAA==.Chrispbacon:BAAALgAECgQJBAAAAA==.Chueyé:BAAALgAECgMJAwABLgAFFAMJCQAVAO8dAA==.Chunkyy:BAAALgADCgYJBgAAAA==.Churros:BAABLgAECn8jAAMLAAgJUBS8IgCXAQALAAcJThW8IgCXAQAJAAcJpxnOJACDAQAAAA==.',
Ci='Cincog:BAAALgAECgQJBAABLgAECgYJCQADAAAAAA==.',
Cl='Closetcookie:BAAALgAECgQJBAAAAA==.',
Co='Coberren:BAAALgAECgEJAQAAAA==.Cordialkylie:BAAALgAECgIJAgAAAA==.Cowcrusader:BAAALgADCgcJBwAAAA==.',
Cr='Crazyugly:BAAALgAECgMJAwAAAA==.Crogrer:BAAALgADCgUJBQAAAA==.Crosslock:BAAALgAECgQJBwAAAA==.',
Cu='Cuppycakes:BAAALgADCgcJFAAAAA==.',
Cy='Cynnari:BAAALgAECgUJBQAAAA==.',
Da='Dalan:BAAALgAECgIJAgABLgAFFAMJBwAEAEsXAA==.Dalaris:BAABLgAECn8gAAIWAAgJoRb3FADFAQAWAAgJoRb3FADFAQAAAA==.Dano:BAAALgADCgYJDQAAAA==.Darci:BAAALgAECgYJCwAAAA==.Darkeon:BAAALgAECgQJBAAAAA==.Darlenedark:BAAALgAECgEJAQAAAA==.Darling:BAAALgAECgIJAgAAAA==.Darron:BAAALgAECgEJAwABLgAECgYJBgADAAAAAA==.Darrosh:BAABLgAECn8bAAQXAAgJuxPDEADiAAAXAAYJDhDDEADiAAAVAAcJjQ3EOADMAAAYAAMJ9hB8FAC1AAAAAA==.Dartian:BAAALgADCgYJBgABLgAECgkJKAACAKcSAA==.Dazdot:BAAALgADCgQJBAABLgAECgEJAQADAAAAAA==.Dazsham:BAAALgAECgEJAQAAAA==.',
De='Deathdevil:BAAALgAECgUJBQAAAA==.Deathlurker:BAAALgADCgQJBAAAAA==.Deathmare:BAAALgAECgQJBAAAAA==.Deathmommy:BAAALgAECgcJCAAAAA==.Deathty:BAAALgAECgMJCgABLgAFFAEJAQADAAAAAA==.Dementia:BAAALgADCgMJAwAAAA==.Design:BAABLgAECn8lAAIZAAkJ4RcbKgAkAgAZAAkJ4RcbKgAkAgAAAA==.Desmeridian:BAAALgAECgUJBQAAAA==.Devotee:BAAALgADCgIJAgAAAA==.',
Dh='Dhish:BAAALgAECgUJBQAAAA==.',
Di='Diltlish:BAAALgAECgMJBQAAAA==.Diocles:BAAALgAECgEJAQAAAA==.Disconcern:BAAALgAECgEJAQAAAA==.Discontent:BAABLgAFFH8GAAIaAAIJUR0BJwCUAAAaAAIJUR0BJwCUAAAAAA==.Discordiä:BAABLgAECn8XAAIbAAgJHRdSGQDlAQAbAAgJHRdSGQDlAQAAAA==.Discspal:BAAALgAECgYJBwAAAA==.',
Dm='Dmginc:BAAALgADCgIJAgAAAA==.',
Do='Doeblin:BAAALgAECgQJCgAAAA==.Donkedixon:BAAALgADCgYJBgAAAA==.Doubtz:BAAALgAECgQJBQABLgAECgQJEAADAAAAAA==.',
Dp='Dpalx:BAAALgAECgQJBAAAAA==.Dpxs:BAABLgAFFH8HAAIUAAQJkhbILwABAQAUAAQJkhbILwABAQAAAA==.',
Dr='Dracaria:BAAALgAECgEJAQAAAA==.Dracones:BAAALgAECgYJDgAAAA==.Dragondz:BAAALgAECgUJBQAAAA==.Dragonflai:BAABLgAECn8mAAIFAAkJnBc7SgDlAQAFAAkJnBc7SgDlAQAAAA==.Dragonkin:BAAALgAECgQJCAAAAA==.Drakkari:BAAALgAECgYJBgAAAA==.Drakkei:BAABLgAECn80AAMCAAgJIxgKOADmAQACAAgJIxgKOADmAQAGAAIJwgJ3UABQAAAAAA==.Drerane:BAAALgADCgYJBgAAAA==.Drexxsster:BAAALgADCgQJBAAAAA==.Drshortbus:BAAALgAECgQJBgAAAA==.Drumitus:BAAALgADCgYJCAAAAA==.Drunkngrundl:BAABLgAECn89AAIcAAkJHiNwAwAMAwAcAAkJHiNwAwAMAwAAAA==.Drylo:BAECLgAFFH8FAAIdAAMJ9BsGKAAFAQAdAAMJ9BsGKAAFAQAuAAQKfy0AAx0ACQkmIFkIALsCAB0ACQmLHlkIALsCAB4ACAnFH+YDADQCAAAA.',
Du='Dunstir:BAABLgAECn8ZAAIKAAgJ6QWMrgAFAQAKAAgJ6QWMrgAFAQAAAA==.Dusktrekker:BAAALgAECgkJBwAAAA==.',
Dy='Dypshyt:BAABLgAECn8ZAAQeAAgJUxVRIgAYAQAeAAUJUBJRIgAYAQAdAAYJqxCiSQDhAAAfAAQJNgfiMQBNAAAAAA==.',
Ed='Edelweíss:BAAALgAECgQJBwAAAA==.',
Ek='Ekoh:BAAALgAECgIJAgAAAA==.',
El='Elarol:BAAALgAECgEJAgAAAA==.Eldons:BAAALgADCgIJAgAAAA==.',
Em='Embers:BAABLgAECn8WAAIgAAYJGxN4UADvAAAgAAYJGxN4UADvAAAAAA==.Emeralde:BAAALgAECgYJBwAAAA==.Emilia:BAAALgADCgIJAwAAAA==.Emptyhands:BAAALgAECgYJBgAAAA==.Emptyheals:BAABLgAECn8xAAIbAAkJ3yDvAwBFAwAbAAkJ3yDvAwBFAwAAAA==.',
Er='Ereada:BAAALgADCgUJCgAAAA==.Erfinden:BAAALgADCgEJAQAAAA==.',
Es='Espers:BAABLgAECn8fAAITAAkJ6Q8ENwAeAQATAAkJ6Q8ENwAeAQAAAA==.',
Et='Ethellin:BAABLgAECn8oAAIKAAgJvgQQugDzAAAKAAgJvgQQugDzAAAAAA==.',
Fa='Fahrenheit:BAAALgAECgEJAgAAAA==.Farkuat:BAAALgADCgQJBAAAAA==.Fatcastle:BAAALgADCgcJDgAAAA==.',
Fe='Feedmepizzas:BAAALgAECgMJCAAAAA==.Feildmedic:BAAALgADCgUJBQAAAA==.Feleria:BAAALgAECgUJBQAAAA==.Fellslasher:BAAALgAECgIJAgAAAA==.Felmage:BAAALgADCgYJBgAAAA==.Felraiser:BAAALgADCgIJAgABLgADCgUJBgADAAAAAA==.Felwinter:BAABLgAECn81AAIZAAkJthquHQBkAgAZAAkJthquHQBkAgAAAA==.Femcelgoon:BAAALgADCgEJAQAAAA==.Fenna:BAAALgADCgYJDAAAAA==.Fetor:BAAALgAECgcJEAAAAA==.',
Fi='Finwé:BAAALgAECgMJBgAAAA==.Fistsalot:BAAALgAECgQJBQAAAA==.',
Fl='Flafferthorn:BAAALgADCgcJCgAAAA==.Fluxarata:BAABLgAECn8lAAIOAAkJcgwBUgB4AQAOAAkJcgwBUgB4AQAAAA==.',
Fo='Forthememes:BAAALgAECgMJBAAAAA==.',
Fr='Fred:BAABLgAECn8lAAIgAAgJZAroNgBXAQAgAAgJZAroNgBXAQAAAA==.Freddrick:BAAALgADCgQJBAAAAA==.Friendly:BAAALgAECgEJAQAAAA==.Frostbuddy:BAAALgAECgcJDQAAAA==.Frëya:BAAALgADCgYJDQAAAA==.Frío:BAAALgAECgEJAQAAAA==.Frøstitute:BAABLgAECn8dAAIFAAcJLxLieABsAQAFAAcJLxLieABsAQAAAA==.',
Fu='Fullmage:BAAALgADCgQJBAAAAA==.',
['Fè']='Fènrïr:BAAALgADCgQJBAAAAA==.',
Ga='Gabel:BAABLgAECn8mAAIhAAkJQh2WBQB5AgAhAAkJQh2WBQB5AgAAAA==.Gadnabit:BAAALgADCgkJCQAAAA==.Gailardia:BAABLgAECn8UAAICAAcJchNxWACCAQACAAcJchNxWACCAQAAAA==.Galand:BAABLgAECn8iAAMIAAYJ+h68ZQCIAQAIAAYJdB68ZQCIAQAPAAIJoiFESABUAAAAAA==.Galladin:BAAALgADCggJDgAAAA==.Gardyson:BAAALgAFFAEJAQAAAA==.Gazton:BAAALgAECgUJBQAAAA==.',
Gl='Glaaki:BAAALgAECgQJBAAAAA==.',
Gn='Gnob:BAAALgAECgEJAQAAAA==.',
Go='Gooblet:BAAALgADCgQJBQAAAA==.Goodfellow:BAAALgAECgEJAQABLgAECgYJFQAhAMUcAA==.Goopy:BAAALgADCgYJAwAAAA==.',
Gr='Graendal:BAAALgADCgQJBAAAAA==.Granite:BAAALgAECgIJAgAAAA==.Granted:BAAALgADCgUJBQAAAA==.Greevil:BAAALgAECgEJAwAAAA==.Gremilien:BAABLgAECn8kAAIMAAkJSBKsCADcAQAMAAkJSBKsCADcAQAAAA==.Grimgorr:BAAALgADCgMJAwAAAA==.Grymdevours:BAAALgADCgYJBgAAAA==.',
Ha='Halcyonic:BAAALgAECgQJBAAAAA==.Halleyscomet:BAABLgAECn8WAAIKAAcJPBptRAAXAgAKAAcJPBptRAAXAgAAAA==.Happyhammer:BAAALgADCgcJCAAAAA==.Harrod:BAAALgAECggJCwAAAA==.Hawkwave:BAAALgAECgcJEgABLgAECgkJEQADAAAAAA==.Hazardzone:BAAALgAECgMJCgAAAA==.',
He='Heavyweather:BAAALgADCgcJBwAAAA==.Hefty:BAAALgAECggJEAAAAA==.Heftyer:BAAALgAECgMJAwAAAA==.Helioween:BAAALgADCgMJAwAAAA==.Helixon:BAAALgADCgYJBgAAAA==.Hellbad:BAACLgAFFH8MAAIcAAQJ7hOtIQAQAQAcAAQJ7hOtIQAQAQAuAAQKfxUAAxwACAleGIgkAHYBABEABgmOG30jALoBABwACAkXEogkAHYBAAAA.Hellbine:BAAALgADCgMJAgAAAA==.Hellsspawn:BAAALgAECgUJBgAAAA==.Hexaverse:BAAALgADCgYJBgABLgAECgQJBAADAAAAAA==.',
Ho='Hoardwither:BAAALgAECgEJAQAAAA==.Hogrog:BAAALgADCgMJAwAAAA==.Hokàge:BAACLgAFFH8JAAIVAAMJ7x28HQAKAQAVAAMJ7x28HQAKAQAuAAQKfzkABBUACQkpIj0HAKECABUACQkpIj0HAKECABgAAgkCGrgYAIwAABcAAQkZAkMmAAkAAAAA.Holyballs:BAAALgADCgEJAQAAAA==.Homealone:BAABLgAECn8VAAMUAAYJvQmCgAC9AAAUAAUJ6AaCgAC9AAAiAAUJ5gLHcgBxAAAAAA==.',
Hu='Huffles:BAAALgAECgQJBwAAAA==.Hugmachine:BAAALgAFFAIJAgAAAA==.Huntinfuzzy:BAAALgAECgkJDwAAAA==.Huntn:BAAALgADCggJCAAAAA==.',
Hy='Hypahypa:BAAALgAECggJCAAAAA==.',
Ia='Iamknot:BAAALgAECgQJBgAAAA==.',
Ic='Icemommy:BAAALgADCgQJCAAAAA==.',
Ig='Igothots:BAABLgAECn8eAAMjAAkJfx4CEAC4AgAjAAkJfx4CEAC4AgAhAAEJbQlYSQApAAAAAA==.',
Il='Illariana:BAABLgAECn8aAAQJAAgJNRI2JwBzAQAJAAgJNRI2JwBzAQALAAEJwQIHcQAgAAAbAAEJvgEteAAeAAAAAA==.Illirotica:BAAALgAECgcJCQAAAA==.',
In='Incredibro:BAAALgADCgEJAQAAAA==.Insanitty:BAAALgAECgcJDwAAAA==.Invincible:BAAALgAECgEJAQABLgAECgYJEAADAAAAAA==.',
Ir='Ironlobo:BAAALgAECgYJEgAAAA==.Ironsolari:BAAALgADCgYJBgAAAA==.Irritable:BAABLgAECn8VAAIkAAYJVB7pDABqAQAkAAYJVB7pDABqAQAAAA==.',
It='Itherious:BAAALgAECgQJBwAAAA==.',
Ja='Jacham:BAABLgAECn8WAAIgAAkJ2hSfGwD9AQAgAAkJ2hSfGwD9AQAAAA==.Jackyll:BAAALgAECgQJCAAAAA==.Jagerboy:BAAALgAECgYJBgAAAA==.Jango:BAAALgAECgIJAgABLgAFFAEJAQADAAAAAA==.Jatix:BAACLgAFFH8JAAIKAAMJiSHMNwAkAQAKAAMJiSHMNwAkAQAuAAQKfyoAAgoACQkcI9ALAPMCAAoACQkcI9ALAPMCAAAA.',
Je='Jeetkundo:BAAALgADCgEJAQABLgAECgYJEAADAAAAAA==.Jellymagus:BAAALgAECgIJAgAAAA==.Jellyms:BAAALgAECgYJCwAAAA==.Jellyspinoff:BAAALgAECgMJBwAAAA==.Jellytown:BAABLgAECn89AAIFAAkJaxS3PQANAgAFAAkJaxS3PQANAgAAAA==.Jelorinea:BAAALgAECgMJAwAAAA==.Jessiana:BAAALgAECgMJBQAAAA==.Jezelda:BAAALgAECgQJBgAAAA==.',
Jp='Jpeppers:BAAALgAECgQJCAAAAA==.',
Ju='Jumano:BAAALgAECgUJCgAAAA==.Jundra:BAAALgAECgUJCgAAAA==.Jurih:BAAALgADCgIJAgAAAA==.',
Ka='Kaineh:BAABLgAECn8oAAIMAAgJah3nBABKAgAMAAgJah3nBABKAgAAAA==.Kainë:BAAALgADCgIJAgAAAA==.Kait:BAABLgAECn8+AAICAAkJ6R9GDQDUAgACAAkJ6R9GDQDUAgAAAA==.Kaladil:BAAALgAECgcJDgAAAA==.Kamis:BAAALgAECgMJAwAAAA==.Kanaga:BAAALgAECgQJBQAAAA==.Kannan:BAABLgAECn8YAAMOAAgJzxv/LwA8AgAOAAgJzxv/LwA8AgAWAAEJAQdWeQAqAAAAAA==.Kashmihhr:BAAALgADCgIJAgAAAA==.Kashmir:BAAALgAECgQJBAAAAA==.Kasmes:BAAALgADCggJGQAAAA==.Kasmius:BAAALgAECgMJAwAAAA==.Kasmus:BAAALgAECgQJCAAAAA==.Kawdor:BAABLgAECn8wAAQSAAgJrBB0OQBOAQASAAcJNw90OQBOAQANAAcJSA/HHQANAQAKAAMJ8wriIAFsAAAAAA==.',
Ke='Keetsz:BAAALgAECgYJDAAAAA==.Kelaino:BAAALgADCgQJBQAAAA==.Keledish:BAAALgADCgEJAQAAAA==.',
Kh='Khansmebduke:BAACLgAFFH8FAAMWAAQJNxZBEwDbAAAWAAMJkRlBEwDbAAAOAAEJKgxYhgBDAAAuAAQKfxYAAxYACAmlHA4TAN8BAA4ACAk1F1w+APsBABYABwlXHQ4TAN8BAAEuAAUUBQkJACEAjh4A.',
Ki='Kiaf:BAAALgADCgcJDQAAAA==.Kiba:BAAALgADCgEJAQAAAA==.Killanick:BAAALgAECgEJAQAAAA==.Killdar:BAAALgAECgQJBAAAAA==.Kimia:BAAALgADCgYJCQAAAA==.Kirtthedirt:BAAALgAECgUJBQAAAA==.Kirtthehurt:BAABLgAECn8oAAIFAAgJKxnrPQAMAgAFAAgJKxnrPQAMAgAAAA==.',
Ko='Koldfront:BAAALgAECgQJBAAAAA==.Kollinator:BAAALgAECgYJBwAAAA==.Korso:BAAALgADCgUJCwABLgAECgUJDAADAAAAAA==.Kotal:BAAALgAECgEJAQAAAA==.',
Ky='Kylair:BAABLgAECn80AAIJAAkJ/B6QCACtAgAJAAkJ/B6QCACtAgAAAA==.Kynreessa:BAAALgADCgYJCAAAAA==.Kyønshi:BAAALgADCgUJBgAAAA==.',
['Kì']='Kìrito:BAAALgAECgUJBwAAAA==.',
La='Labeya:BAAALgADCgMJAwAAAA==.Lafty:BAAALgAFFAEJAQAAAA==.Laftydh:BAAALgAECgUJEQABLgAFFAEJAQADAAAAAA==.Lailah:BAAALgADCgIJAgABLgAECgkJOQAKALUaAA==.Laine:BAAALgADCgMJAwAAAA==.Landrra:BAAALgAECgQJBAAAAA==.Larac:BAAALgAECggJEgAAAA==.Lathsong:BAAALgADCgYJDwAAAA==.Lavi:BAAALgADCgQJAwAAAA==.',
Le='Leadge:BAAALgADCgYJBwAAAA==.Lenik:BAABLgAECn8aAAIVAAYJ+gkiMgD1AAAVAAYJ+gkiMgD1AAAAAA==.Leskya:BAAALgADCgQJAwAAAA==.',
Li='Libras:BAAALgADCgMJAwAAAA==.Licorice:BAAALgAECgUJDgABLgAECggJIwALAFAUAA==.Lieree:BAABLgAECn8XAAIFAAgJUg0udwBwAQAFAAgJUg0udwBwAQAAAA==.Lifeguàrd:BAAALgAECgkJBwAAAA==.Lillana:BAAALgADCgcJDQAAAA==.Lilyfaye:BAAALgADCgcJBwAAAA==.Limosfire:BAABLgAECn8VAAIMAAYJkAO3IACUAAAMAAYJkAO3IACUAAAAAA==.Linsatha:BAAALgAECggJEAAAAA==.',
Lo='Lockty:BAAALgAECgIJBgABLgAFFAEJAQADAAAAAA==.Logi:BAAALgADCgYJCwAAAA==.Lorezever:BAAALgADCgcJDQAAAA==.Lotion:BAAALgADCgIJAgAAAA==.',
Lu='Luar:BAAALgAECgYJCQAAAA==.Lulubean:BAAALgADCgMJBAAAAA==.Lunaris:BAAALgADCgQJBAAAAA==.Lunà:BAAALgAECgcJEwAAAA==.',
Ly='Lythalle:BAAALgAECgEJAQAAAA==.Lythwynn:BAABLgAECn8rAAIKAAkJhQ/DaACEAQAKAAkJhQ/DaACEAQAAAA==.',
['Lá']='Lásh:BAAALgAECgUJBQABLgAECgUJDAADAAAAAA==.',
Ma='Mace:BAAALgAECgEJAQAAAA==.Madison:BAAALgAECgEJAQAAAA==.Magdolyn:BAAALgADCgMJAwAAAA==.Mageyboi:BAAALgAECgQJBgABLgAFFAMJCQAVAO8dAA==.Magickul:BAAALgAECgYJDAAAAA==.Magleon:BAAALgADCgIJAgAAAA==.Magonk:BAAALgADCgEJAQAAAA==.Mahano:BAAALgAECgYJDQABLgAFFAEJAQADAAAAAA==.Makis:BAAALgAECgMJBQAAAA==.Malachi:BAAALgADCgkJCQAAAA==.Manavoid:BAABLgAECn8cAAIOAAYJkAokmwDMAAAOAAYJkAokmwDMAAAAAA==.Massili:BAAALgADCggJEQAAAA==.Mastor:BAAALgADCgQJBwAAAA==.Maynard:BAABLgAECn8fAAIQAAgJ2hIOLgCYAQAQAAgJ2hIOLgCYAQAAAA==.',
Mc='Mcdouble:BAAALgADCgMJAwAAAA==.',
Me='Meri:BAABLgAECn8bAAIjAAcJoB4rJgAfAgAjAAcJoB4rJgAfAgAAAA==.',
Mi='Miande:BAABLgAECn8VAAIkAAcJ0xffCAC4AQAkAAcJ0xffCAC4AQAAAA==.Microburst:BAAALgADCgcJCwAAAA==.Minecraft:BAAALgAECgIJAgAAAA==.Minilock:BAABLgAECn8kAAMZAAgJww0MZABrAQAZAAgJAAwMZABrAQABAAUJTg4pGwC3AAAAAA==.Misogynixy:BAAALgADCgQJBAAAAA==.Missdeeds:BAAALgADCgYJCwAAAA==.Missleading:BAAALgAECgYJBgAAAA==.Missused:BAAALgAECgYJEQAAAA==.Mithos:BAAALgAECgUJBwAAAA==.Mithraxa:BAAALgAECgQJBAAAAA==.',
Mo='Moash:BAAALgADCgkJCQAAAA==.Modsagoodtnk:BAAALgAECgUJBQABLgAECggJJAACAIsXAA==.Mongermook:BAABLgAECn8cAAMlAAgJCQqmLgDLAAAlAAgJCQqmLgDLAAATAAEJxgFpkQAVAAAAAA==.Monnkysham:BAAALgAECgQJBgABLgAECgYJCQADAAAAAA==.Moogledragon:BAAALgADCgMJAwAAAA==.Mooglefur:BAAALgAECgQJBAAAAA==.Moonbloom:BAABLgAECn8cAAIjAAgJQhyxHABNAgAjAAgJQhyxHABNAgAAAA==.Morlosh:BAAALgAECgMJAwAAAA==.Moryna:BAABLgAECn8qAAIaAAgJsAYuLQD8AAAaAAgJsAYuLQD8AAAAAA==.',
Mt='Mthrandir:BAAALgADCgUJBQAAAA==.',
Mu='Muford:BAAALgAECgQJBQABLgAFFAYJEQAcAI8fAA==.Mull:BAAALgAECgYJEQAAAA==.Muloc:BAAALgADCgEJAQAAAA==.',
My='Myaka:BAAALgAECgYJBgAAAA==.',
Na='Naatixa:BAAALgAECggJCwAAAA==.Nacronor:BAAALgAECgQJBwAAAA==.Naiika:BAAALgAECgYJBwAAAA==.Nascha:BAAALgADCgEJAQAAAA==.Nasoj:BAAALgAECgUJCAABLgAECgYJEwADAAAAAA==.',
Ne='Necrotic:BAAALgAECgQJBAAAAA==.Nedalla:BAAALgAECgQJBQAAAA==.Neeve:BAAALgADCgYJBgAAAA==.Nekrotik:BAAALgADCgcJBgAAAA==.Neobahamut:BAAALgADCgEJAQABLgAECgUJBwADAAAAAA==.Netharel:BAAALgADCgIJAgAAAA==.Newports:BAAALgAECgEJAQAAAA==.',
Ni='Nichôlasmage:BAAALgAECgYJCwAAAA==.Nickatnite:BAAALgAECgEJAwAAAA==.Nickelodeon:BAAALgAECgQJBwAAAA==.Nicksaban:BAABLgAECn8mAAIKAAkJOBtsJwBNAgAKAAkJOBtsJwBNAgAAAA==.Nightgear:BAACLgAFFH8uAAMCAAcJ+hYgBABeAQACAAYJYBkgBABeAQAMAAIJ/ArHKgBMAAAuAAQKf1kAAwIACQm1IgUIABADAAIACQm1IgUIABADAAwABAnfEuIfAJsAAAAA.Nilux:BAAALgAECgYJDgAAAA==.Ninetails:BAAALgAECgUJCgAAAA==.Niteshadeth:BAAALgAECgQJBAAAAA==.Niteyknight:BAAALgAECgMJAwAAAA==.Nixeava:BAAALgAECgYJDQAAAA==.',
No='Nogooddruid:BAAALgAECgQJBwAAAA==.Nopetsneeded:BAABLgAECn84AAIMAAkJUBREBwAAAgAMAAkJUBREBwAAAgAAAA==.Nostariel:BAAALgAECgMJAwAAAA==.Notadoctor:BAAALgAECgYJCAAAAA==.Noteworthy:BAAALgAECgYJEgABLgAFFAYJDwAIAN0dAA==.',
Ny='Nysong:BAABLgAECn8uAAMBAAgJ4QjkEgADAQABAAgJ4QjkEgADAQAZAAMJYwJKAAFVAAAAAA==.',
['Nó']='Nórin:BAAALgAECgUJBQAAAA==.',
Od='Oddangel:BAAALgAECgYJEwAAAA==.Ode:BAAALgAECgcJCgAAAA==.Odex:BAABLgAECn8gAAIeAAgJbQzcCQByAQAeAAgJbQzcCQByAQAAAA==.',
Oh='Ohblergen:BAAALgAECgIJAgAAAA==.',
Ok='Okragren:BAABLgAECn81AAIiAAkJhwwfLQB2AQAiAAkJhwwfLQB2AQAAAA==.',
Ol='Olehi:BAAALgADCgcJBwAAAA==.Olynder:BAAALgAECgIJAgAAAA==.',
On='Onos:BAABLgAECn8bAAICAAcJIyQ4IABEAgACAAcJIyQ4IABEAgAAAA==.Ontoquas:BAAALgADCgkJCgAAAA==.',
Pa='Paleclaw:BAAALgADCgQJBAAAAA==.Pally:BAAALgAECgUJBQAAAA==.Papasmurfz:BAAALgAECgEJAwAAAA==.Paramedic:BAAALgAECgQJBwAAAA==.Pathogen:BAABLgAECn8hAAIIAAkJDR+FMwAcAgAIAAkJDR+FMwAcAgAAAA==.',
Pe='Penryn:BAAALgAECgQJBAAAAA==.Pepster:BAAALgAECgkJDwAAAA==.Persephoknee:BAAALgADCgEJAQAAAA==.',
Pf='Pfchen:BAAALgADCgQJBAAAAA==.',
Pl='Plinkerbell:BAAALgADCgcJBgAAAA==.Plumprnickel:BAAALgAECgEJAQAAAA==.Plxkingg:BAAALgADCgUJBQAAAA==.',
Po='Porimma:BAAALgAECgYJDQAAAA==.Pormas:BAAALgAECgYJDwAAAA==.Poseydon:BAAALgADCgQJBAABLgAECgEJAQADAAAAAA==.',
Pr='Prayerz:BAAALgADCgMJAwAAAA==.Proctology:BAAALgAECgQJBAAAAA==.Promethèus:BAAALgAECgQJBAAAAA==.Prosby:BAAALgADCgIJAgAAAA==.Prowlnfool:BAAALgADCgUJBQAAAA==.Pryto:BAAALgADCgkJDgABLgAFFAIJAgADAAAAAA==.',
Qu='Queedle:BAABLgAECn8WAAIXAAgJDwhCDQAkAQAXAAgJDwhCDQAkAQAAAA==.',
Ra='Raennis:BAAALgAECgIJAgAAAA==.Ragalstan:BAAALgAECgEJAQAAAA==.Rahanumn:BAABLgAECn8YAAIKAAgJ6wmklQAtAQAKAAgJ6wmklQAtAQAAAA==.Rainsvoker:BAACLgAFFH8jAAIfAAYJXQ1RDwCAAQAfAAYJXQ1RDwCAAQAuAAQKf1IAAx8ACQkOHC0GAJUCAB8ACQkOHC0GAJUCAB0ABgk7CH5XAK4AAAAA.Ramike:BAAALgAECggJCQAAAA==.Raqtar:BAAALgAECgIJAgABLgAECgkJEQADAAAAAA==.Ratrazarke:BAAALgADCgIJAgAAAA==.Razihel:BAAALgADCgYJCQAAAA==.',
Re='Reaver:BAAALgAECgQJBAAAAA==.Reddan:BAABLgAECn8qAAIKAAgJlgyjigBAAQAKAAgJlgyjigBAAQAAAA==.Renata:BAAALgAFFAIJAgAAAA==.Replicant:BAAALgAECgEJAQAAAA==.Retman:BAAALgAECgMJAQAAAA==.Reverìe:BAAALgAECgcJBwAAAA==.Reylinn:BAAALgAECgQJBAAAAA==.Reï:BAABLgAECn8bAAIjAAgJNhapJwAAAgAjAAgJNhapJwAAAgAAAA==.',
Ri='Ridlei:BAAALgAECgMJBAAAAA==.Ritzon:BAABLgAECn89AAMgAAkJJSTmBAAEAwAgAAkJJSTmBAAEAwAaAAEJmBdAYgA+AAAAAA==.',
Ro='Rosadita:BAAALgAECgEJAQAAAA==.Roxydan:BAABLgAECn8dAAMBAAgJiQ03KQAdAQAZAAgJiQ1KZwCWAQABAAYJ8Ag3KQAdAQAAAA==.',
Ry='Ryko:BAABLgAECn8eAAImAAcJDRPFDwC8AQAmAAcJDRPFDwC8AQAAAA==.',
Sa='Sanandume:BAAALgADCgEJAQAAAA==.Sanctess:BAAALgAECggJDQAAAA==.Sankai:BAAALgAECgEJAQABLgAECgYJDgADAAAAAA==.Sarlas:BAAALgADCgQJBAAAAA==.Sarumanpally:BAAALgAECgYJBwAAAA==.Sayomi:BAAALgADCgcJEwAAAA==.',
Se='Secretjuice:BAAALgAECgYJCQAAAA==.Senseijundra:BAAALgAECgQJCAAAAA==.',
Sh='Shabadu:BAAALgADCgQJBAAAAA==.Shadyandi:BAAALgADCgcJCAAAAA==.Shamanhack:BAAALgAFFAIJAwAAAA==.Shan:BAAALgADCgYJBgAAAA==.Sharazad:BAAALgAECgEJAQAAAA==.Sheda:BAAALgAECgQJBAAAAA==.Shedia:BAAALgADCgYJCQAAAA==.Shmoove:BAEALgAECgUJBQAAAA==.Shmooves:BAEALgAECgMJAwABLgAECgUJBQADAAAAAA==.Shoukei:BAAALgADCgIJAwAAAA==.',
Si='Sianna:BAAALgADCgYJBgAAAA==.Siinful:BAAALgAECgEJAQAAAA==.Simbruh:BAAALgADCgMJAwAAAA==.Sinarria:BAAALgAECgEJAQAAAA==.Sithra:BAAALgADCgEJAQAAAA==.',
Sk='Skeemer:BAAALgAECgQJBAAAAA==.Skeetro:BAAALgAECgEJAQAAAA==.Skips:BAAALgAECgQJCQAAAA==.Skullace:BAABLgAECn8kAAIBAAgJgQ4WDQBPAQABAAgJgQ4WDQBPAQAAAA==.Skybreaker:BAAALgAECgUJCAAAAA==.',
Sm='Smashurfacen:BAAALgADCgcJFAAAAA==.',
Sn='Snitbit:BAAALgADCgkJGgAAAA==.Sno:BAAALgADCgEJAQABLgAECgUJBwADAAAAAA==.Snoopingas:BAAALgADCgEJAQAAAA==.Snpcrklpopu:BAAALgADCgYJCAAAAA==.',
So='Solarana:BAAALgAECgkJCQAAAA==.Sortiebatoru:BAAALgAECgIJAgAAAA==.Sotzi:BAAALgADCggJEQAAAA==.Souldune:BAAALgAECgYJBgAAAA==.',
Sp='Sparkplugg:BAAALgAECgEJAQAAAA==.',
Sr='Srfreaky:BAAALgAECgQJBwAAAA==.',
St='Stormcunning:BAABLgAECn8WAAIiAAYJCAxiTAAWAQAiAAYJCAxiTAAWAQAAAA==.Stormfire:BAAALgADCgcJBwAAAA==.Stormßringer:BAABLgAECn8UAAIiAAgJERDXMwCJAQAiAAgJERDXMwCJAQAAAA==.Stownr:BAAALgAECgYJBgAAAA==.Strip:BAAALgADCgUJCAAAAA==.Strongclaw:BAAALgADCgUJBQAAAA==.Stumpyborg:BAABLgAECn8VAAQBAAcJaAahLABXAAAZAAYJNgSZzQCmAAABAAIJMwuhLABXAAAkAAEJhAelOQArAAABLgAECggJEAADAAAAAA==.Stónéhëárt:BAAALgADCgYJBwABLgAECgkJEQADAAAAAA==.',
Su='Subverse:BAAALgAECgQJBAAAAA==.Sundance:BAAALgAECgcJDgAAAA==.Sune:BAABLgAECn8fAAMJAAYJxgtPPwDvAAAJAAYJxgtPPwDvAAAbAAEJNwkDcQArAAAAAA==.Supplicant:BAAALgADCgQJBwAAAA==.',
Sv='Svellulfr:BAAALgAECgEJAQAAAA==.Svuca:BAAALgADCgcJBwAAAA==.',
Sy='Sydneyweenie:BAAALgADCgcJCAAAAA==.Syldi:BAAALgAECgEJAQABLgAFFAEJAQADAAAAAA==.Sythis:BAAALgAECgEJAQAAAA==.',
['Sä']='Sästa:BAAALgADCgkJCQAAAA==.',
['Sö']='Sörren:BAAALgAECgUJDwAAAA==.',
Ta='Tacosdeasada:BAAALgAECgEJAQAAAA==.Taitertot:BAAALgADCgQJBQAAAA==.Tanelórn:BAAALgAECgEJAQAAAA==.Tanlon:BAAALgAECgYJBgAAAA==.Taykorra:BAAALgADCggJDQAAAA==.',
Te='Telandril:BAABLgAECn8vAAIjAAkJvxGZMADMAQAjAAkJvxGZMADMAQAAAA==.Telphin:BAAALgAECgYJCQAAAA==.Tempestira:BAAALgADCgIJCAAAAA==.Tensuken:BAABLgAECn8ZAAIKAAYJpBgQnwAdAQAKAAYJpBgQnwAdAQAAAA==.Teylonna:BAAALgAECgEJAQAAAA==.',
Th='Thadgun:BAAALgADCgkJFQAAAA==.Thadium:BAAALgADCgYJCQAAAA==.Thalgan:BAAALgAECgEJAQAAAA==.Thecword:BAAALgADCgYJBgAAAA==.Themedic:BAAALgAECgcJEgAAAA==.Theremar:BAAALgAECgMJAwAAAA==.Thergothon:BAAALgAECgEJAQABLgAECgMJAwADAAAAAA==.Thisisdrexx:BAAALgAECgIJAwAAAA==.Thorwrath:BAAALgADCgEJAgAAAA==.Thrazoro:BAAALgAECgMJAwAAAA==.Thrazzoro:BAAALgAECgYJEwAAAA==.',
Ti='Tiarl:BAABLgAECn8uAAILAAgJDxn5FAAXAgALAAgJDxn5FAAXAgAAAA==.Tiia:BAAALgADCgIJAgAAAA==.Timex:BAABLgAECn8XAAMeAAYJRCD5DgDrAQAeAAYJRCD5DgDrAQAdAAEJUhd2fgA+AAAAAA==.Tinysitril:BAAALgAECgYJCQABLgAECggJIAAWAKEWAA==.Titañick:BAAALgAECgEJAwAAAA==.',
To='Tom:BAAALgAECgYJEAAAAA==.Toosxyfohair:BAAALgAECgcJCgAAAA==.',
Tr='Trainwrekk:BAAALgADCgYJBgAAAA==.Tranqar:BAAALgAECgQJBgAAAA==.Tresg:BAAALgAECgYJCQAAAA==.Trissandra:BAAALgAECgEJAQAAAA==.Trolltoll:BAAALgADCgEJAwAAAA==.Trüth:BAAALgADCggJEAAAAA==.',
Tw='Twylidan:BAEALgAECgkJBAABLgAFFAMJBQAdAPQbAA==.',
Ty='Tyrannus:BAAALgADCgYJBgAAAA==.Tyregar:BAAALgAECgEJAQAAAA==.Tyrànda:BAAALgADCgMJAwAAAA==.Tyzy:BAAALgAECgEJAgAAAA==.',
['Tö']='Tötém:BAAALgAECgEJAQAAAA==.',
Ul='Ulanhi:BAABLgAECn8VAAIhAAUJzh31EACdAQAhAAUJzh31EACdAQAAAA==.',
Un='Undeadjelly:BAAALgAECgUJBwAAAA==.Unholy:BAAALgAECgYJDwAAAA==.',
Ur='Urkzul:BAAALgADCgMJAwAAAA==.Ursoth:BAAALgADCgUJCgAAAA==.',
Ut='Uthèrsmight:BAAALgAECgYJBgAAAA==.Uti:BAAALgADCgUJBQAAAA==.',
Uu='Uubs:BAAALgADCgEJAQABLgAFFAMJCgAKAJoSAA==.',
Va='Valakk:BAAALgAECgIJBQAAAA==.Vallak:BAAALgADCgIJBAAAAA==.Valsitril:BAAALgAECgYJDAABLgAECggJIAAWAKEWAA==.Valthaczar:BAAALgAECgMJBgAAAA==.Vanara:BAAALgAECgEJAgAAAA==.Varadun:BAAALgAFFAIJAgAAAA==.Varrosh:BAAALgADCgYJBgAAAA==.Vathan:BAAALgAECgQJBQAAAA==.',
Ve='Velmora:BAAALgAECgkJCQAAAA==.Velsetin:BAABLgAECn8dAAIFAAcJTBsyTABSAgAFAAcJTBsyTABSAgABLgAFFAMJBQATAMcUAA==.Versed:BAAALgADCgUJBQABLgAECgQJBAADAAAAAA==.Veryspooky:BAABLgAECn8XAAIZAAgJMhc/RQC/AQAZAAgJMhc/RQC/AQAAAA==.Vexian:BAAALgAECgkJEAAAAA==.',
Vf='Vfl:BAAALgADCgcJBwAAAA==.',
Vi='Vicas:BAAALgAECgUJDwAAAA==.',
Vl='Vladdok:BAAALgAECgUJBQAAAA==.',
Vo='Voidofdeath:BAAALgADCgQJBAAAAA==.Voidshiekah:BAAALgADCgEJAQAAAA==.Vorteia:BAAALgADCgYJBgAAAA==.',
['Vé']='Véngéánçé:BAAALgAECgMJBAAAAA==.',
Wa='Wald:BAAALgAECgYJEAAAAA==.Warmongerr:BAAALgADCgIJAgAAAA==.Waruh:BAAALgADCgcJCQAAAA==.',
We='Webgar:BAAALgAECgEJAQAAAA==.',
Wh='Whisperlia:BAAALgAECgEJAQAAAA==.Whitetoothe:BAABLgAECn8dAAICAAYJkxLoeQAyAQACAAYJkxLoeQAyAQAAAA==.',
Wi='Wistmeaver:BAAALgAECgYJEAAAAA==.Witherbear:BAAALgADCgcJBwAAAA==.Witherhoard:BAAALgADCgEJAQAAAA==.',
['Wå']='Wånheda:BAAALgAECggJEwAAAA==.',
Xa='Xaniana:BAAALgAECgkJCQAAAA==.Xaosin:BAAALgADCgUJBQAAAA==.',
Xe='Xenzak:BAAALgAECgEJAQAAAA==.Xephir:BAAALgADCgMJAwAAAA==.Xerxës:BAAALgAECgEJAQAAAA==.',
Xl='Xl:BAAALgAECgQJCwAAAA==.',
Xo='Xotiko:BAAALgAECgYJDAAAAA==.',
Xu='Xubris:BAAALgADCgYJCQAAAA==.',
['Xâ']='Xâxâs:BAAALgAECgMJAwABLgAECggJGQAdAFsEAA==.',
Ya='Yaerin:BAACLgAFFH8RAAIbAAQJKiE8FgCCAQAbAAQJKiE8FgCCAQAuAAQKfyMAAhsACQmzIZcDAFEDABsACQmzIZcDAFEDAAAA.',
Yu='Yunarä:BAAALgAECgYJBwAAAA==.Yuukon:BAABLgAECn8ZAAQPAAgJkRUaGQB9AQAPAAgJkRUaGQB9AQAIAAQJ5gNGGAFoAAAHAAEJDwgrGAAvAAAAAA==.',
Za='Zakuul:BAAALgADCgQJBAAAAA==.Zalezaar:BAAALgAECgIJAgAAAA==.Zangetsu:BAAALgAECgcJBwAAAA==.Zaxie:BAABLgAECn8gAAIOAAcJFBplQwCmAQAOAAcJFBplQwCmAQAAAA==.',
Ze='Zenwu:BAAALgADCgkJGwAAAA==.Zephrylia:BAAALgAECgQJBQAAAA==.Zerama:BAAALgAECgUJBQAAAA==.',
Zh='Zheratul:BAAALgAECgEJAQAAAA==.Zhirl:BAAALgAECgkJCQAAAA==.Zhivet:BAAALgAECgUJBQAAAA==.',
Zi='Zilphia:BAAALgAECggJEgAAAA==.',
Zu='Zuriel:BAAALgAECgEJAQAAAA==.',
Zy='Zyku:BAAALgAECgEJAQAAAA==.Zylphie:BAAALgADCgcJBwAAAA==.',
['Àm']='Àmagezing:BAAALgAFFAEJAQABLgAFFAQJCwAKABIgAA==.',
['Åj']='Åj:BAAALgADCgcJBwAAAA==.',
['Åp']='Åpexx:BAAALgAECgYJCgAAAA==.',
['Çw']='Çwÿbàbý:BAAALgAECgIJAwAAAA==.',
['Ór']='Órión:BAABLgAECn8VAAICAAYJ1BJMjwAGAQACAAYJ1BJMjwAGAQAAAA==.',
['Ös']='Östara:BAABLgAECn8WAAIjAAYJ5he9OAChAQAjAAYJ5he9OAChAQAAAA==.',
['ßj']='ßjörn:BAAALgADCgQJBAAAAA==.',
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
