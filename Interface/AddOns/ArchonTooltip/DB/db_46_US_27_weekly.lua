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

local lookup = {'Warlock-Destruction','Warlock-Demonology','Unknown-Unknown','Hunter-BeastMastery','Mage-Arcane','Mage-Frost','DeathKnight-Unholy','Hunter-Survival','DeathKnight-Frost','Monk-Mistweaver','Monk-Brewmaster','Monk-Windwalker','Priest-Shadow','Paladin-Retribution','Druid-Guardian','Druid-Restoration','Hunter-Marksmanship','Paladin-Protection','DemonHunter-Devourer','DeathKnight-Blood','Druid-Feral','Priest-Holy','Warrior-Protection','Warrior-Arms','Warrior-Fury','Paladin-Holy','Druid-Balance','Shaman-Restoration','Rogue-Subtlety','DemonHunter-Havoc','Rogue-Outlaw','Rogue-Assassination','Priest-Discipline','DemonHunter-Vengeance','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Shaman-Elemental','Warlock-Affliction','Shaman-Enhancement',}
local provider = {region='US',realm='Azuremyst',name='US',type='weekly',zone=46,date='2026-07-28',data={Aa='Aaravos:BAABLgAECn8iAAMBAAkJhhrRBwDUAQABAAkJiBfRBwDUAQACAAUJDhfIDAAcAQAAAA==.Aardia:BAAALgAECgUJBwAAAA==.Aarynae:BAAALgAECgkJEgAAAA==.',
Ab='Abysseon:BAAALgAECgUJDgABLgAECgQJCAADAAAAAA==.',
Ac='Accretion:BAAALgAECgYJBgAAAA==.',
Ad='Adaria:BAABLgAECn8WAAIEAAcJWAWSZQA3AQAEAAcJWAWSZQA3AQAAAA==.Addath:BAAALgADCgYJBgAAAA==.Adrillbear:BAAALgAFFAEJAQAAAA==.Adura:BAAALgAECgYJCAAAAA==.',
Ae='Aeirith:BAACLgAFFH8OAAIFAAQJ5hRoAQAjAQAFAAQJ5hRoAQAjAQAuAAQKfyQAAwUACQmwHegBAGYCAAUACQmwHegBAGYCAAYAAQlFChlgATEAAAAA.Aelion:BAAALgAECgEJAQAAAA==.',
Ah='Ahheevoker:BAAALgAECgYJEgAAAA==.',
Ai='Ailsà:BAAALgADCgEJAQAAAA==.',
Ak='Akarias:BAAALgAECgEJAQABLgAECgcJBwADAAAAAA==.',
Al='Aladaria:BAAALgAECgMJAwAAAA==.Alannon:BAAALgADCgEJAQAAAA==.Aldyah:BAAALgAFFAMJAwAAAA==.Alias:BAAALgAECgYJBQAAAA==.Alistair:BAAALgAECgEJAwAAAA==.Allanonn:BAAALgAECgQJBAAAAA==.Alohomora:BAAALgAECgUJEAAAAA==.Alprazolam:BAAALgAECgEJAQAAAA==.Alvist:BAABLgAECn8UAAIHAAQJrx6gggBeAQAHAAQJrx6gggBeAQAAAA==.',
Am='Amarasu:BAABLgAECn8cAAIIAAkJig+RGwDBAQAIAAkJig+RGwDBAQAAAA==.Amarlly:BAABLgAECn8zAAIJAAkJJhngBwAVAgAJAAkJJhngBwAVAgAAAA==.Amenedil:BAAALgAECgUJDAAAAA==.',
An='Anbrew:BAABLgAECn8UAAQKAAcJdxJoSwA/AQAKAAYJDBJoSwA/AQALAAUJjA6FQAD4AAAMAAEJMwe0rwAlAAABLgAFFAcJEAAHAHYeAA==.Ancelina:BAABLgAECn8qAAINAAkJeyR3AgBCAwANAAkJeyR3AgBCAwAAAA==.Anderton:BAABLgAECn89AAIOAAgJyhq1CgCcAQAOAAgJyhq1CgCcAQAAAA==.Andilocks:BAAALgADCgMJAwAAAA==.Andraenei:BAAALgADCgcJBwAAAA==.Andrela:BAAALgAECgcJCwAAAA==.Andromadda:BAAALgADCggJCAAAAA==.Aneira:BAABLgAECn8pAAMPAAcJ8BFzBgAqAQAPAAcJ8BFzBgAqAQAQAAMJYQySmQB/AAAAAA==.Annovera:BAAALgAECgMJBgAAAA==.Anyi:BAAALgAECgEJAQAAAA==.',
Ap='Apexxd:BAAALgAECgUJBQAAAA==.Applefritter:BAAALgAECgUJCAABLgAECgkJKAANAJYbAA==.',
Ar='Araga:BAAALgAECgEJAQAAAA==.Archérhiro:BAACLgAFFH8oAAMEAAkJ8BXHCAAyAgAEAAgJWxjHCAAyAgARAAMJRwTfIQCHAAAuAAQKfyoAAwQACQmGH+0YAJECAAQACQl6H+0YAJECABEACAkrGdobAEoCAAAA.Arilias:BAAALgAECgEJAQABLgAECgkJRwAEANEfAA==.Arillann:BAABLgAECn89AAISAAkJUR+3BACuAgASAAkJUR+3BACuAgAAAA==.Arrook:BAAALgAECgMJAwAAAA==.Arrtonomis:BAAALgAECgUJCAABLgAECgkJEgADAAAAAA==.Artdemsamis:BAAALgAECgkJEgAAAA==.Arte:BAABLgAECn89AAIEAAkJaxOnLAABAgAEAAkJaxOnLAABAgAAAA==.Arthundermis:BAAALgAECgkJEQABLgAECgkJEgADAAAAAA==.Artlunarmis:BAAALgADCgEJAQABLgAECgkJEgADAAAAAA==.Arvena:BAABLgAECn8nAAITAAkJVgoWdAA5AQATAAkJVgoWdAA5AQAAAA==.',
As='Asclëpius:BAAALgADCgcJBgABLgAECgEJAQADAAAAAA==.Asheron:BAAALgAECgYJCAAAAA==.Ashylock:BAAALgAECgEJAQABLgAFFAUJEAAGAGAWAA==.Ashymage:BAACLgAFFH8QAAIGAAUJYBabYAAgAQAGAAUJYBabYAAgAQAuAAQKfzcAAgYACQlYHLYpAMwCAAYACQlYHLYpAMwCAAAA.Askevar:BAABLgAECn8wAAMHAAkJTwwDDABcAQAHAAkJnwsDDABcAQAUAAYJ5wlHJwAEAQAAAA==.Aspect:BAAALgADCgEJAQABLgAFFAIJAwADAAAAAA==.Asriél:BAAALgAECgYJEwAAAA==.Astor:BAAALgADCgMJBQAAAA==.Astrona:BAAALgADCgkJFwAAAA==.',
At='Atreus:BAABLgAECn8YAAIOAAkJbAXUwQAGAQAOAAkJbAXUwQAGAQAAAA==.Attalaguy:BAAALgAECgYJDgAAAA==.',
Au='Audra:BAAALgADCgcJDgAAAA==.',
Av='Avabeatrix:BAAALgADCgEJAQAAAA==.Avinthoro:BAAALgADCgIJAgAAAA==.',
Ay='Ayyayyron:BAAALgAECgUJCQAAAA==.',
Az='Azaleah:BAABLgAECn9MAAIOAAkJRx3xGQCoAgAOAAkJRx3xGQCoAgAAAA==.Azanoth:BAAALgADCgIJAgAAAA==.Azraesha:BAABLgAECn8rAAITAAkJ/BUDKgAhAgATAAkJ/BUDKgAhAgAAAA==.Azureflamez:BAAALgAECgEJAQAAAA==.Azurewraith:BAAALgAECgQJBAAAAA==.Azzul:BAAALgADCgcJBwAAAA==.',
Ba='Backy:BAABLgAECn8kAAIVAAkJOxrzAABjAgAVAAkJOxrzAABjAgAAAA==.Baiken:BAAALgAECgIJAgABLgAECgQJCAADAAAAAA==.Banjoman:BAABLgAECn8kAAIWAAcJXSTpCgC4AgAWAAcJXSTpCgC4AgAAAA==.Baza:BAAALgADCgYJBgAAAA==.Baýlei:BAABLgAECn8WAAIKAAYJ5A0kWwAHAQAKAAYJ5A0kWwAHAQAAAA==.',
Be='Beareold:BAAALgAECgQJBAAAAA==.Beary:BAAALgAECgQJCAAAAA==.Bebide:BAAALgAECgEJAQABLgAECgcJCQADAAAAAA==.Beenaughty:BAAALgAECgEJAQABLgAECgEJAQADAAAAAA==.Belaanna:BAAALgADCgYJCQAAAA==.Beliria:BAAALgADCgUJBgAAAA==.Benimaru:BAAALgAECgUJDwAAAA==.Beriko:BAAALgAECgMJAwAAAA==.Bernat:BAAALgAECgEJAQAAAA==.Beàrdfáce:BAAALgADCgQJBAAAAA==.',
Bi='Bigblunt:BAAALgAECgEJAQAAAA==.Bigjuicy:BAABLgAECn8ZAAQXAAkJchhgBQAVAQAXAAYJCRVgBQAVAQAYAAUJVRl/CQCrAAAZAAUJBhUNEgCpAAAAAA==.Billie:BAAALgAECgcJDAAAAA==.Bimboficate:BAAALgADCgYJBwAAAA==.',
Bl='Black:BAAALgAFFAEJAQAAAA==.Blackadder:BAABLgAECn8qAAISAAcJLg/FBQATAQASAAcJLg/FBQATAQAAAA==.Blondie:BAAALgADCgQJBAABLgAECgYJEwADAAAAAA==.Bloodie:BAAALgAECgMJAwAAAA==.Blue:BAABLgAECn88AAIMAAkJxRvlDgBbAgAMAAkJxRvlDgBbAgAAAA==.Blueguy:BAAALgAECgQJBgAAAA==.Bluestreak:BAAALgAECgEJAwABLgAECgcJCQADAAAAAA==.',
Bo='Bobthefist:BAAALgADCgcJBwAAAA==.Bode:BAAALgAECgYJEwAAAA==.Bogern:BAAALgADCgcJBwAAAA==.Bolau:BAAALgADCgYJBwAAAA==.Boltz:BAAALgADCgYJBgAAAA==.Boogy:BAAALgAFFAEJAQAAAA==.Bopdiz:BAAALgAECgEJAQABLgAECgQJFAAHAK8eAA==.Borledish:BAAALgAECgMJBAABLgAECgQJFAAHAK8eAA==.Bottosai:BAAALgAECgEJAgAAAA==.',
Br='Brambles:BAAALgAECgEJAQAAAA==.Branwynn:BAAALgAECgcJEgAAAA==.Breezyfight:BAAALgAFFAIJAgAAAA==.Breezyrocks:BAAALgADCgQJCQAAAA==.Breezysha:BAAALgADCgcJCAAAAA==.Brenz:BAABLgAFFH8GAAMOAAMJOQIKqgBuAAAOAAMJOwEKqgBuAAASAAEJvQR6HAAhAAAAAA==.Brewdaddy:BAAALgAECgUJEwABLgAECgkJOwAaAKEUAA==.Brewdude:BAAALgAECgEJAQAAAA==.Brigor:BAAALgAECgYJEAAAAA==.Brokenblade:BAAALgADCgYJBgAAAA==.Brotherblood:BAAALgAECgYJDAAAAA==.',
Bu='Bulldoza:BAAALgAECgQJBQAAAA==.Bullwankle:BAAALgADCggJDQAAAA==.Bullwinkles:BAAALgAECgEJAQAAAA==.Bunbot:BAAALgAECgEJAQAAAA==.Butterknifeo:BAABLgAFFH8FAAIbAAMJxxSHMQC7AAAbAAMJxxSHMQC7AAAAAA==.',
By='Byryja:BAABLgAECn8pAAIGAAcJbAmbHwDLAAAGAAcJbAmbHwDLAAAAAA==.',
Ca='Cabela:BAAALgAECgkJEwAAAA==.Cahrazie:BAACLgAFFH8GAAIOAAMJ9wkqewDAAAAOAAMJ9wkqewDAAAAuAAQKfx0AAg4ACQkaFbZIAOwBAA4ACQkaFbZIAOwBAAAA.Caidinn:BAAALgAECgkJEQAAAA==.Caitrîn:BAAALgADCgkJCQABLgAECgcJKQAPAPARAA==.Calissancia:BAABLgAECn82AAIKAAgJNBdEHwAgAgAKAAgJNBdEHwAgAgAAAA==.Calkey:BAABLgAECn8WAAIBAAYJUQgMHwCyAAABAAYJUQgMHwCyAAAAAA==.Calliaa:BAAALgADCgEJAQABLgADCgcJDQADAAAAAA==.Callmemommy:BAAALgADCgYJBgAAAA==.Carnelia:BAAALgAECgEJAgAAAA==.Carvana:BAAALgAECgkJBwAAAA==.Catalyst:BAAALgADCgMJAwAAAA==.Cathandris:BAAALgADCgEJAQAAAA==.Catovia:BAAALgAECgYJBwAAAA==.',
Ce='Ceri:BAAALgAECgkJBwAAAA==.Ceska:BAAALgADCgEJAQAAAA==.',
Ch='Chadarack:BAAALgAECgYJBwAAAA==.Chadaracks:BAAALgAECgEJAQAAAA==.Chancy:BAAALgAECgMJBQAAAA==.Channingtotm:BAACLgAFFH8vAAIcAAUJ7iWUBQD/AQAcAAUJ7iWUBQD/AQAuAAQKfzsAAhwACQlhIY4EAG4DABwACQlhIY4EAG4DAAAA.Chantix:BAAALgADCgUJBQAAAA==.Charlemoo:BAAALgADCgUJBQABLgAECgMJAwADAAAAAA==.Cheekymonkey:BAABLgAECn8qAAIFAAkJMQ2EBQB+AQAFAAkJMQ2EBQB+AQAAAA==.Chrispbacon:BAAALgAECgUJEgAAAA==.Chueyé:BAAALgAECgQJBAABLgAFFAMJDAAdAO8dAA==.Chune:BAAALgAECgcJCwAAAA==.Chunkyy:BAAALgADCgYJBgAAAA==.Churros:BAABLgAECn8oAAMNAAkJlhuVEQBJAgANAAkJlhuVEQBJAgAWAAcJThV3JwCKAQAAAA==.',
Ci='Cincog:BAAALgAECgQJBAABLgAECgYJCQADAAAAAA==.',
Cl='Closetcookie:BAAALgAECgQJBAAAAA==.',
Co='Coberren:BAAALgAECgEJAQAAAA==.Coldhands:BAAALgAECgIJAgAAAA==.Cordialkylie:BAAALgAECgIJAgAAAA==.Cowcrusader:BAAALgADCgcJBwAAAA==.',
Cr='Crazyugly:BAAALgAECgQJBQAAAA==.Crogrer:BAAALgAECgMJAwAAAA==.Crosslock:BAAALgAECgUJEAAAAA==.',
Cu='Cuppycakes:BAAALgADCgcJFAAAAA==.',
Cy='Cynnari:BAAALgAECgYJDQAAAA==.',
Da='Daddysecret:BAAALgAECgQJBQAAAA==.Dalan:BAAALgAECgIJAgABLgAFFAQJDgAFAOYUAA==.Dalaris:BAACLgAFFH8LAAIeAAQJlw+mDADVAAAeAAQJlw+mDADVAAAuAAQKfyIAAh4ACQmdFiASAAoCAB4ACQmdFiASAAoCAAAA.Danizmi:BAAALgADCgQJBAAAAA==.Dano:BAAALgADCgYJDQAAAA==.Darci:BAAALgAECgYJCwAAAA==.Darkeon:BAAALgAECgcJCwAAAA==.Darkpriestes:BAAALgAECgQJBAAAAA==.Darkénrahl:BAAALgAECgEJAQABLgAFFAMJCAAEAOoRAA==.Darlenedark:BAAALgAECgEJAQAAAA==.Darling:BAAALgAECgIJAgAAAA==.Darron:BAAALgAECgIJBAABLgAECggJEgADAAAAAA==.Darrosh:BAABLgAECn8bAAQfAAgJuxOEEgDhAAAfAAYJDhCEEgDhAAAdAAcJjQ34PgDLAAAgAAMJ9hB8FAC1AAAAAA==.Dartian:BAAALgADCgcJDQABLgAECgkJRwAEANEfAA==.Daylightt:BAAALgAECgIJAgAAAA==.Dazblood:BAAALgAECgIJAgAAAA==.Dazdot:BAAALgADCgQJBAABLgAECgIJAgADAAAAAA==.Dazsham:BAAALgAECgEJAQABLgAECgIJAgADAAAAAA==.',
De='Deadjuicy:BAAALgAECggJCQAAAA==.Deathdevil:BAAALgAECgUJBQAAAA==.Deathlurker:BAAALgADCgQJBAAAAA==.Deathmare:BAAALgAECgUJBQAAAA==.Deathmommy:BAAALgAECgcJCAAAAA==.Deathty:BAAALgAECgMJCgABLgAFFAEJAgADAAAAAA==.Dementia:BAAALgADCgMJAwAAAA==.Design:BAABLgAECn8lAAICAAkJ4Rc7MgAPAgACAAkJ4Rc7MgAPAgAAAA==.Desmeridian:BAAALgAECgUJBQAAAA==.Dethendrova:BAAALgADCgYJBgABLgAFFAMJCAAEAOoRAA==.Devotee:BAAALgADCgIJAgAAAA==.',
Dh='Dhish:BAABLgAECn8dAAQbAAcJBgmuDADLAAAbAAcJBgmuDADLAAAVAAMJMwdTPABoAAAQAAIJ6gIc1AAxAAAAAA==.',
Di='Diltlish:BAAALgAECgUJCgAAAA==.Diocles:BAAALgAECgUJBgAAAA==.Disconcern:BAAALgAECgEJAQAAAA==.Discontent:BAACLgAFFH8GAAIYAAIJUR2wMwCNAAAYAAIJUR2wMwCNAAAuAAQKfxQAAxgABwnwHKQQAOkBABgABwnwHKQQAOkBABkABQknEVxuAP0AAAAA.Discordiä:BAABLgAECn8XAAIhAAgJHRf9HQDeAQAhAAgJHRf9HQDeAQAAAA==.Discspal:BAAALgAECgYJBwAAAA==.Diåblo:BAAALgADCgUJBQAAAA==.',
Dm='Dmginc:BAAALgAECgYJCwAAAA==.',
Do='Doeblin:BAABLgAECn8SAAIEAAUJ0B5heABPAQAEAAUJ0B5heABPAQAAAA==.Domidouse:BAAALgAECgYJCgAAAA==.Domivyr:BAAALgAECgEJAQAAAA==.Donkedixon:BAAALgADCgYJBgAAAA==.Dosar:BAAALgADCgIJAgAAAA==.Doubledeuces:BAAALgADCgIJAgAAAA==.Doubtz:BAAALgAECgQJBQABLgAECgQJFAAHAK8eAA==.',
Dp='Dpalx:BAAALgAECgQJBAAAAA==.Dpxs:BAABLgAFFH8HAAIcAAQJkha7PwDmAAAcAAQJkha7PwDmAAAAAA==.',
Dr='Dracaria:BAAALgAECgEJAQAAAA==.Dracones:BAAALgAECgYJDgAAAA==.Dragondz:BAAALgAECgUJBQAAAA==.Dragonflai:BAABLgAECn8nAAIGAAkJnBdCUwDjAQAGAAkJnBdCUwDjAQAAAA==.Dragonkin:BAAALgAECgQJCAAAAA==.Drakkari:BAABLgAECn8bAAMiAAYJPAjvBQChAAAiAAYJHQfvBQChAAATAAYJCAeSHwB+AAAAAA==.Drakkei:BAACLgAFFH8FAAIEAAIJahPUSgCFAAAEAAIJahPUSgCFAAAuAAQKf1YAAwQACQlrG9kHAOkBAAQACQlrG9kHAOkBAAgAAwkiBr9JAJIAAAAA.Drawbridge:BAAALgAECgEJAQAAAA==.Drerane:BAAALgADCgYJBgAAAA==.Drexxsster:BAAALgADCgQJBAAAAA==.Drshortbus:BAAALgAECgUJCgAAAA==.Drumitus:BAAALgADCgYJCAAAAA==.Drunkngrundl:BAABLgAECn89AAILAAkJHiMoBAAGAwALAAkJHiMoBAAGAwAAAA==.Drylo:BAECLgAFFH8MAAMjAAQJ6R51IABcAQAjAAQJ6R51IABcAQAkAAEJFB54BgBMAAAuAAQKfy0AAyMACQkmII4JAL8CACMACQmLHo4JAL8CACQACAnFH6UGAIgCAAAA.',
Du='Duckeey:BAAALgAFFAIJBAABLgAFFAYJHAAGAF8NAA==.Dunstir:BAABLgAECn8ZAAIOAAgJ6QUgwAAIAQAOAAgJ6QUgwAAIAQAAAA==.Dusktrekker:BAAALgAECgkJBwAAAA==.',
Dy='Dypshyt:BAABLgAECn8aAAQjAAkJhxfkTwDvAAAkAAUJUBJRIgAYAQAjAAYJqxDkTwDvAAAlAAUJTgemLgB1AAAAAA==.Dyyke:BAAALgAECgEJAQAAAA==.',
Ed='Edelweíss:BAAALgAECgUJEAAAAA==.',
Ek='Ekazzik:BAAALgAECgYJBgABLgAFFAMJCAAEAOoRAA==.Ekoh:BAAALgAECgIJAgAAAA==.',
El='Elaaranna:BAAALgAECgMJAwAAAA==.Elarol:BAAALgAECgQJBQAAAA==.Eldons:BAAALgADCgIJAgAAAA==.Elfie:BAAALgAECgIJAgAAAA==.Elladra:BAAALgAECgMJAwAAAA==.',
Em='Embers:BAABLgAECn8WAAIZAAYJGxPjWADrAAAZAAYJGxPjWADrAAAAAA==.Emeralde:BAAALgAECgYJCgAAAA==.Emilia:BAAALgADCgIJAwAAAA==.Emptyhands:BAAALgAECgYJBgAAAA==.Emptyheals:BAABLgAECn8zAAIhAAkJ3yC7BABEAwAhAAkJ3yC7BABEAwAAAA==.',
En='Enticedem:BAAALgAECgEJBAAAAA==.',
Er='Ereada:BAAALgADCgUJCgAAAA==.Erfinden:BAAALgADCgEJAQAAAA==.',
Es='Espernite:BAAALgAECgQJBAAAAA==.Espers:BAACLgAFFH8GAAIbAAMJCgcmHACLAAAbAAMJCgcmHACLAAAuAAQKfx8AAhsACQnpD68+ABQBABsACQnpD68+ABQBAAAA.',
Et='Ethellin:BAABLgAECn9BAAIOAAkJ0whBFQAWAQAOAAkJ0whBFQAWAQAAAA==.',
Eu='Euredes:BAAALgADCgYJBgABLgAFFAMJCAAEAOoRAA==.',
Fa='Fahrenheit:BAAALgAECgEJAgAAAA==.Farkuat:BAAALgADCgQJBAAAAA==.Fatcastle:BAAALgADCgcJDgAAAA==.',
Fe='Feedmepizzas:BAAALgAECgMJCAAAAA==.Feildmedic:BAAALgAECgEJAQAAAA==.Feleria:BAABLgAECn8cAAIaAAYJQxVYBgBbAQAaAAYJQxVYBgBbAQAAAA==.Fellslasher:BAAALgAECgIJAgAAAA==.Felmage:BAAALgADCgYJBgAAAA==.Felraiser:BAAALgADCgIJAgABLgADCgUJBgADAAAAAA==.Felwinter:BAABLgAECn81AAICAAkJthrMIQBbAgACAAkJthrMIQBbAgAAAA==.Femcelgoon:BAAALgADCgEJAQAAAA==.Fenna:BAAALgADCgYJDAAAAA==.Fetor:BAAALgAECgcJEAAAAA==.',
Fi='Fingulfin:BAAALgAECgIJAwAAAA==.Finwé:BAAALgAECgQJCgAAAA==.Fistofwar:BAAALgAECgMJAwAAAA==.Fistsalot:BAAALgAECgQJCAAAAA==.',
Fl='Flafferthorn:BAAALgAECgMJAwAAAA==.Fluxarata:BAABLgAECn8sAAITAAkJGQ67UwCLAQATAAkJGQ67UwCLAQAAAA==.',
Fo='Forthememes:BAAALgAECgcJCQAAAA==.',
Fr='Fred:BAABLgAECn8xAAIZAAkJpgvGPQBPAQAZAAkJpgvGPQBPAQAAAA==.Freddrick:BAAALgADCgQJBAAAAA==.Friendly:BAAALgAECgEJAQAAAA==.Frostbuddy:BAAALgAECgcJDQAAAA==.Frëya:BAAALgADCgYJDQAAAA==.Frío:BAAALgAECgEJAQAAAA==.Frøstitute:BAABLgAECn8tAAIGAAkJwRenMwBKAgAGAAkJwRenMwBKAgAAAA==.',
Fu='Fullmage:BAAALgADCgQJBAAAAA==.',
['Fè']='Fènrïr:BAAALgADCgQJBAAAAA==.',
Ga='Gabel:BAABLgAECn8nAAIVAAkJQh3JBgB2AgAVAAkJQh3JBgB2AgAAAA==.Gadnabit:BAAALgADCgkJCQAAAA==.Gailardia:BAACLgAFFH8GAAIEAAMJzRLeMADXAAAEAAMJzRLeMADXAAAuAAQKfyQAAgQABwn/HYUvAB4CAAQABwn/HYUvAB4CAAEuAAUUBAkeABYAxx4A.Galand:BAABLgAECn8mAAMHAAcJPB3BDwApAQAHAAcJzBzBDwApAQAUAAIJoiFoUABTAAAAAA==.Galladin:BAAALgADCggJDgAAAA==.Gardyson:BAABLgAECn8eAAMXAAcJuhf9AwBZAQAXAAcJuhf9AwBZAQAZAAEJbQNKtAAhAAABLgAFFAMJCAAEAOoRAA==.Gazton:BAAALgAECgUJBQAAAA==.',
Gl='Glaaki:BAAALgAECgUJEAAAAA==.',
Gn='Gnob:BAAALgAECgYJEQAAAA==.',
Go='Gooblet:BAAALgADCgQJBQAAAA==.Goodfellow:BAAALgAECgEJAQABLgAECgYJFQAVAMUcAA==.Goopy:BAAALgADCgYJAwAAAA==.',
Gr='Graendal:BAAALgADCgQJBAAAAA==.Granite:BAAALgAECgMJBAAAAA==.Granted:BAAALgADCgUJBQAAAA==.Greevil:BAAALgAECgEJAwAAAA==.Gremilien:BAABLgAECn8xAAIRAAkJQhhzAQCsAQARAAkJQhhzAQCsAQAAAA==.Grimgorr:BAAALgADCgMJAwAAAA==.Grimmly:BAAALgAECgEJAQAAAA==.Gruggrug:BAAALgAFFAIJAQAAAA==.Grymdevours:BAAALgADCgYJBgAAAA==.Grymmana:BAAALgADCgQJBAAAAA==.',
Ha='Halcyonic:BAAALgAECgUJCgAAAA==.Halleyscomet:BAABLgAECn8WAAIOAAcJPBptRAAXAgAOAAcJPBptRAAXAgAAAA==.Happyhammer:BAAALgADCgcJCAAAAA==.Harrod:BAAALgAECggJCwAAAA==.Hashey:BAAALgAECgEJAgAAAA==.Hawkwave:BAAALgAECgcJEgABLgAECgkJEQADAAAAAA==.Hazardzone:BAAALgAECgMJCgAAAA==.',
He='Heartburn:BAAALgAFFAEJAQABLgAFFAYJHQAZAAUdAA==.Heavyweather:BAAALgADCgcJBwAAAA==.Hefty:BAABLgAECn8XAAMIAAkJ3QtnKQBVAQAIAAcJKQtnKQBVAQAEAAUJ8gm3owD6AAAAAA==.Heftyer:BAAALgAECgMJAwAAAA==.Helioween:BAAALgADCgMJAwAAAA==.Helixon:BAAALgADCgYJBgAAAA==.Hellbad:BAACLgAFFH8MAAILAAQJ7hO+KAAGAQALAAQJ7hO+KAAGAQAuAAQKfxUAAwsACAleGMEnAHMBAAwABgmOG30jALoBAAsACAkXEsEnAHMBAAAA.Hellbine:BAAALgADCgMJAgAAAA==.Hellfella:BAAALgAECgEJAQAAAA==.Hellonheels:BAAALgAECgQJBAAAAA==.Hellsspawn:BAAALgAECgYJEAAAAA==.Hexaverse:BAAALgADCgYJBgABLgAECgQJBAADAAAAAA==.',
Ho='Hoardwither:BAAALgAECgEJAgAAAA==.Hoenheim:BAAALgAECgEJAQAAAA==.Hogrog:BAAALgADCgMJAwAAAA==.Hokàge:BAACLgAFFH8MAAIdAAMJ7x3+JAD8AAAdAAMJ7x3+JAD8AAAuAAQKfzsABB0ACQkpIvQIAJYCAB0ACQkpIvQIAJYCACAAAgkCGhgbAIwAAB8AAQkZAlosAAkAAAAA.Holymortal:BAAALgAECgYJDAAAAA==.Homealone:BAABLgAECn8aAAMcAAkJAQlefADrAAAcAAgJJQdefADrAAAmAAUJ8gPZfQB3AAAAAA==.Honeycruller:BAAALgAECgMJAwABLgAECgkJKAANAJYbAA==.',
Hu='Huffles:BAAALgAECgQJBwAAAA==.Hugmachine:BAAALgAFFAIJAgAAAA==.Huntinfuzzy:BAAALgAECgkJDwAAAA==.Huntn:BAAALgADCggJCAAAAA==.',
Hy='Hypahypa:BAAALgAECggJEwAAAA==.',
Ia='Iamknot:BAAALgAECgQJBgAAAA==.',
Ic='Icemommy:BAAALgADCgQJCAAAAA==.',
Ig='Igothots:BAACLgAFFH8FAAIQAAIJZBDKVQBvAAAQAAIJZBDKVQBvAAAuAAQKfx4AAxAACQl/HgIQALgCABAACQl/HgIQALgCABUAAQltCb9YACkAAAAA.',
Il='Illariana:BAABLgAECn8aAAQNAAgJNRI5LABzAQANAAgJNRI5LABzAQAWAAEJwQLCegAfAAAhAAEJvgHGigAdAAAAAA==.Illirotica:BAAALgAECgcJCQAAAA==.',
In='Incredibro:BAAALgADCgEJAQAAAA==.Insanitty:BAAALgAECgcJDwAAAA==.Invincible:BAAALgAECgEJAQABLgAECgYJIgAKAIEkAA==.',
Ir='Ironlobo:BAABLgAECn8YAAIGAAYJhxkZfACAAQAGAAYJhxkZfACAAQAAAA==.Ironsolari:BAAALgADCgYJBgAAAA==.Irritable:BAABLgAECn8kAAMnAAkJARs/AwCHAgAnAAkJARs/AwCHAgACAAEJJRftIQFGAAAAAA==.',
It='Itherious:BAAALgAECgUJEQAAAA==.',
Ja='Jacham:BAABLgAECn8WAAIZAAkJ2hSIHwDzAQAZAAkJ2hSIHwDzAQAAAA==.Jackyll:BAAALgAECgQJCAAAAA==.Jacmehof:BAAALgADCgIJAgAAAA==.Jagerboy:BAAALgAECgYJBgAAAA==.Jango:BAAALgAECgIJAgABLgAFFAMJCAAEAOoRAA==.Jatix:BAACLgAFFH8WAAIOAAUJ0CDXKwBeAQAOAAUJ0CDXKwBeAQAuAAQKfyoAAg4ACQkcI3kPAOoCAA4ACQkcI3kPAOoCAAAA.',
Je='Jeetkundo:BAAALgADCgEJAQABLgAECgYJIgAKAIEkAA==.Jellydh:BAAALgAECgUJCgAAAA==.Jellymagus:BAAALgAECgIJAgAAAA==.Jellyms:BAAALgAECgcJDwAAAA==.Jellyspinoff:BAAALgAECgMJBwAAAA==.Jellytown:BAABLgAECn89AAIGAAkJaxRVRQALAgAGAAkJaxRVRQALAgAAAA==.Jelorinea:BAAALgAECgMJCQAAAA==.Jemmi:BAAALgADCgEJAQAAAA==.Jessiana:BAABLgAECn8UAAIBAAYJMxSzAwAvAQABAAYJMxSzAwAvAQAAAA==.Jezelda:BAAALgAECgQJBgAAAA==.',
Jo='Joeydonuts:BAEALgAECgMJAwABLgAECgUJBgADAAAAAA==.Johnwickneo:BAAALgADCgEJAQAAAA==.Jolten:BAAALgADCgMJBAAAAA==.',
Jp='Jpeppers:BAABLgAECn8kAAIEAAcJYhUnEABTAQAEAAcJYhUnEABTAQAAAA==.',
Ju='Judgementalx:BAAALgAFFAEJAQAAAA==.Juicifer:BAAALgAECgYJBwAAAA==.Jumano:BAAALgAECgUJCgAAAA==.Jundra:BAAALgAECgUJCgAAAA==.Jurih:BAAALgADCgIJAgAAAA==.',
Ka='Kaineh:BAABLgAECn8oAAIRAAgJah3WBQA/AgARAAgJah3WBQA/AgAAAA==.Kainë:BAAALgADCgIJAgAAAA==.Kait:BAABLgAECn8+AAIEAAkJ6R8zEQDHAgAEAAkJ6R8zEQDHAgAAAA==.Kaladil:BAAALgAECgcJDgAAAA==.Kamis:BAAALgAECgMJAwAAAA==.Kanaga:BAAALgAECgQJBQAAAA==.Kannan:BAABLgAECn8YAAMTAAgJzxv/LwA8AgATAAgJzxv/LwA8AgAeAAEJAQdWeQAqAAAAAA==.Kashmihhr:BAAALgADCgIJAgAAAA==.Kashmir:BAAALgAECgQJBAAAAA==.Kasmes:BAAALgADCggJGQAAAA==.Kasmius:BAAALgAECgMJAwAAAA==.Kasmus:BAAALgAECgQJCAAAAA==.Kawdor:BAABLgAECn87AAQaAAkJoRQMBgBmAQAaAAcJfRQMBgBmAQASAAgJ2xDfFwBgAQAOAAMJ8wrNQQFqAAAAAA==.',
Ke='Keanuleaves:BAAALgAECgIJBAABLgAECgYJIgAKAIEkAA==.Keetsz:BAAALgAECgYJDAAAAA==.Kelaino:BAAALgADCgQJBQAAAA==.Keledish:BAAALgADCgEJAQAAAA==.',
Kh='Khansmebduke:BAACLgAFFH8FAAMeAAQJNxakGQDUAAAeAAMJkRmkGQDUAAATAAEJKgzfnQA9AAAuAAQKfxYAAx4ACAmlHC4WANkBABMACAk1F1w+APsBAB4ABwlXHS4WANkBAAEuAAUUBQkJABUAjh4A.Khota:BAAALgAECgYJDAAAAA==.',
Ki='Kiaf:BAAALgADCgcJDQAAAA==.Kiba:BAAALgADCgEJAQAAAA==.Killakeecat:BAAALgADCgYJBgAAAA==.Killanick:BAAALgAECgEJAQAAAA==.Killdar:BAAALgAECgQJBAAAAA==.Kimia:BAAALgADCgYJCQAAAA==.Kirtthedirt:BAAALgAECgYJCAAAAA==.Kirtthehurt:BAABLgAECn8pAAIGAAkJShhlMABXAgAGAAkJShhlMABXAgAAAA==.',
Ko='Koldfront:BAAALgAECgUJDwAAAA==.Kollinator:BAABLgAECn8cAAIEAAYJzBkrDgBuAQAEAAYJzBkrDgBuAQAAAA==.Korso:BAAALgADCgUJCwABLgAECgcJKQAPAPARAA==.Kotal:BAAALgAECgEJAQAAAA==.',
Ku='Kurtina:BAAALgAECgMJAwAAAA==.',
Ky='Kylair:BAABLgAECn80AAINAAkJ/B4cCgCtAgANAAkJ/B4cCgCtAgAAAA==.Kynreessa:BAAALgADCgYJCAAAAA==.Kythis:BAAALgAECgEJAQABLgAECgkJEgADAAAAAA==.Kyyell:BAAALgAECggJDgAAAA==.Kyønshi:BAAALgADCgUJBgAAAA==.',
['Kì']='Kìrito:BAAALgAECgcJDgAAAA==.',
La='Labeya:BAEALgADCgMJAwAAAA==.Lafty:BAAALgAFFAEJAgAAAA==.Laftydh:BAAALgAECgYJEgABLgAFFAEJAgADAAAAAA==.Lailah:BAAALgADCgIJAgABLgAECgkJTAAOAEcdAA==.Laine:BAAALgADCgMJAwAAAA==.Landrra:BAAALgAECgQJBAAAAA==.Larac:BAAALgAECgkJEwAAAA==.Lastwhisper:BAAALgAECgEJAQAAAA==.Lathsong:BAAALgADCgYJDwAAAA==.Lavi:BAAALgADCgQJAwAAAA==.',
Le='Leadge:BAAALgADCgYJBwAAAA==.Lenik:BAABLgAECn8aAAIdAAYJ+gkGOADxAAAdAAYJ+gkGOADxAAAAAA==.Leskya:BAAALgADCgQJAwAAAA==.',
Li='Libras:BAAALgADCgMJAwAAAA==.Licorice:BAAALgAECgUJDgABLgAECgkJKAANAJYbAA==.Lieree:BAABLgAECn8XAAIGAAgJUg3VggByAQAGAAgJUg3VggByAQAAAA==.Lifeguàrd:BAAALgAECgkJBwAAAA==.Lillana:BAAALgADCgcJDQAAAA==.Lilrayne:BAAALgADCgYJBgABLgAECgkJHAAIAIoPAA==.Lilyfaye:BAAALgADCgkJDAAAAA==.Limosfire:BAABLgAECn8WAAIRAAYJEwS7JACOAAARAAYJEwS7JACOAAAAAA==.Linsatha:BAAALgAECggJEAAAAA==.',
Lo='Loa:BAAALgAECgUJBwAAAA==.Lockty:BAAALgAECgIJBgABLgAFFAEJAgADAAAAAA==.Logi:BAAALgADCgYJCwAAAA==.Lorezever:BAAALgADCgcJDQAAAA==.Lotion:BAAALgADCgIJAgAAAA==.',
Lu='Luar:BAAALgAECgYJDQAAAA==.Lucity:BAAALgADCgQJAgABLgAFFAUJFgAOANAgAA==.Lulubean:BAAALgAECgUJCAAAAA==.Lunafae:BAAALgADCggJCAAAAA==.Lunaris:BAAALgADCgQJBAAAAA==.Lungorthin:BAAALgAECgQJBQAAAA==.Lunà:BAABLgAECn8sAAIBAAgJIAg6BgDQAAABAAgJIAg6BgDQAAAAAA==.',
Ly='Lythalle:BAAALgAECgEJAQAAAA==.Lythwynn:BAABLgAECn8rAAIOAAkJhQ+0cwCGAQAOAAkJhQ+0cwCGAQAAAA==.',
['Lá']='Lásh:BAAALgAECgUJCAABLgAECgcJKQAPAPARAA==.',
Ma='Mace:BAAALgAECgEJAQAAAA==.Madison:BAAALgAECgEJAQAAAA==.Madyorkies:BAAALgAECgkJAQAAAA==.Magdolyn:BAAALgADCgMJAwAAAA==.Mageyboi:BAAALgAECgQJBgABLgAFFAMJDAAdAO8dAA==.Magickul:BAAALgAECgYJDAAAAA==.Magleon:BAAALgADCgIJAgAAAA==.Magonk:BAAALgADCgEJAQAAAA==.Mahano:BAACLgAFFH8IAAIEAAMJ6hF1MQDWAAAEAAMJ6hF1MQDWAAAuAAQKfxgAAwQACAnUGg8fAGwCAAQACAnUGg8fAGwCABEAAQn+EyALAD0AAAAA.Makis:BAAALgAECgMJBQAAAA==.Malachi:BAAALgAECgYJBwAAAA==.Manavoid:BAABLgAECn8cAAITAAYJkArjpwDVAAATAAYJkArjpwDVAAAAAA==.Mandoanubis:BAAALgADCgcJCgAAAA==.Mandragore:BAAALgAECgIJBAAAAA==.Marakesh:BAAALgADCgEJAQAAAA==.Massili:BAAALgADCgkJGgAAAA==.Mastor:BAAALgADCgQJBwAAAA==.Maynard:BAABLgAECn8hAAIKAAkJ9xErLwC/AQAKAAkJ9xErLwC/AQAAAA==.',
Mc='Mcdouble:BAAALgADCgMJAwAAAA==.',
Me='Melancholy:BAAALgADCggJCAAAAA==.Meldanis:BAAALgAECgQJBAAAAA==.Meri:BAABLgAECn8cAAIQAAgJlxwrJgAfAgAQAAgJlxwrJgAfAgAAAA==.',
Mi='Miande:BAABLgAECn8VAAInAAcJ0xfLCgCyAQAnAAcJ0xfLCgCyAQAAAA==.Microburst:BAAALgAECgUJCgAAAA==.Minecraft:BAAALgAECgIJAgAAAA==.Minilock:BAABLgAECn8/AAMCAAkJtBSEBwCHAQACAAkJ9xKEBwCHAQABAAUJDBnxAwAjAQAAAA==.Misogynixy:BAAALgADCgQJBAAAAA==.Missdeeds:BAAALgAECgUJBQAAAA==.Missleading:BAAALgAECgYJCQAAAA==.Missused:BAABLgAECn8XAAIGAAYJkgxQJACzAAAGAAYJkgxQJACzAAAAAA==.Mistycat:BAAALgAECgkJDQAAAA==.Mithos:BAAALgAECgUJBwAAAA==.Mithraxa:BAAALgAECgQJBAAAAA==.Miyagifu:BAAALgAECgQJBAAAAA==.',
Mo='Moash:BAAALgADCgkJCQAAAA==.Modsagoodtnk:BAABLgAECn8cAAISAAcJRQ6QBwDcAAASAAcJRQ6QBwDcAAABLgAECggJLwAEAH8ZAA==.Mongermook:BAABLgAECn8iAAMPAAkJ0QsZDQCcAAAPAAkJ0QsZDQCcAAAbAAEJxgFpkQAVAAAAAA==.Monnkysham:BAAALgAECgQJBgABLgAECgYJCQADAAAAAA==.Moogledragon:BAAALgADCgMJAwAAAA==.Mooglefur:BAAALgAECgQJBQAAAA==.Moonbloom:BAABLgAECn8dAAIQAAkJTBxLHwBMAgAQAAkJTBxLHwBMAgAAAA==.Mooseknuhkle:BAAALgAECgEJAQAAAA==.Morgrim:BAAALgAECgIJAwAAAA==.Morlosh:BAAALgAECgMJAwAAAA==.Moryna:BAABLgAECn81AAIYAAkJsQhZJQA9AQAYAAkJsQhZJQA9AQAAAA==.',
Mt='Mthrandir:BAAALgADCgUJBQAAAA==.',
Mu='Muford:BAAALgAECgQJBQABLgAFFAgJFQALAOQfAA==.Mull:BAAALgAECgYJEwAAAA==.Muloc:BAAALgADCgEJAQAAAA==.',
My='Myaka:BAAALgAECgYJBgAAAA==.Mythicc:BAAALgADCgUJCQAAAA==.',
Na='Naatixa:BAAALgAECggJDAAAAA==.Nacronor:BAABLgAECn8VAAIEAAUJHwSxLgB6AAAEAAUJHwSxLgB6AAAAAA==.Naiika:BAAALgAECgYJBwAAAA==.Naivaya:BAAALgADCgMJAwAAAA==.Nascha:BAAALgADCgEJAQAAAA==.Nasoj:BAAALgAECgYJCQABLgAECgYJEwADAAAAAA==.',
Ne='Necrasirenea:BAAALgAECggJCAABLgAECgcJCQADAAAAAA==.Necrotic:BAAALgAECgQJBAAAAA==.Nedalla:BAAALgAECgYJDAAAAA==.Neeve:BAAALgAECgMJAwAAAA==.Nekrotik:BAAALgADCgcJBgAAAA==.Neobahamut:BAAALgAECgUJCwABLgAECgcJDgADAAAAAA==.Netharel:BAAALgADCgIJAgAAAA==.Newports:BAAALgAECgEJAQAAAA==.',
Ni='Nichôlasmage:BAAALgAECgYJCwAAAA==.Nickatnite:BAAALgAFFAMJBAAAAA==.Nickelodeon:BAAALgAFFAIJAwAAAA==.Nicksaban:BAABLgAECn8nAAIOAAkJuBuBLgBHAgAOAAkJuBuBLgBHAgAAAA==.Nightgear:BAACLgAFFH8yAAMEAAkJAxYADwDuAQAEAAgJlhcADwDuAQARAAIJ/ApJNQBJAAAuAAQKf1kAAwQACQm1IgUIABADAAQACQm1IgUIABADABEABAnfEoAjAJcAAAAA.Nighti:BAAALgADCgIJAQAAAA==.Nightshades:BAAALgADCgQJBAAAAA==.Nilux:BAAALgAECgYJDwAAAA==.Ninetails:BAAALgAECgUJCgAAAA==.Niteshadeth:BAAALgAECgQJBQAAAA==.Niteyknight:BAAALgAECgQJBAAAAA==.Nixeava:BAABLgAECn8dAAImAAkJVQV6VADoAAAmAAkJVQV6VADoAAAAAA==.',
No='Nogooddruid:BAAALgAECgUJDwAAAA==.Nopetsneeded:BAABLgAECn89AAIRAAkJzBRpCAD3AQARAAkJzBRpCAD3AQAAAA==.Norepairbill:BAAALgAECgEJAQABLgAECgkJPQARAMwUAA==.Nostariel:BAAALgAECgQJCgAAAA==.Notadoctor:BAAALgAECgYJCAAAAA==.Noteworthy:BAAALgAECgYJEgABLgAFFAcJEAAHAHYeAA==.',
Nu='Nubuu:BAAALgADCgkJCQAAAA==.',
Ny='Nyctera:BAAALgAFFAEJAQAAAA==.Nysong:BAABLgAECn84AAMBAAgJaQy/EgAfAQABAAgJaQy/EgAfAQACAAMJYwKJGAFPAAAAAA==.',
['Nó']='Nórin:BAAALgAECgUJBQAAAA==.',
Oa='Oakenforge:BAAALgAECgUJBQABLgAFFAIJBQAEAGoTAA==.',
Ob='Obali:BAAALgADCgYJCgAAAA==.',
Od='Oddangel:BAAALgAECgYJEwAAAA==.Ode:BAAALgAFFAIJAgAAAA==.Odex:BAACLgAFFH8JAAMkAAQJ+wQ3BQBvAAAjAAQJqQOPJQCMAAAkAAIJCAc3BQBvAAAuAAQKfyoAAyQACQlvDX8IAKgBACQACQlvDX8IAKgBACMAAQmmCE2QADoAAAAA.Odéyemí:BAAALgAECgQJBAAAAA==.',
Oh='Ohblergen:BAAALgAECgIJAgAAAA==.',
Ok='Okragren:BAABLgAECn83AAImAAkJ/A1NMwBvAQAmAAkJ/A1NMwBvAQAAAA==.',
Ol='Olehi:BAAALgADCgcJBwAAAA==.Olynder:BAAALgAECgIJBAAAAA==.',
On='Onos:BAABLgAECn8bAAIEAAcJIyQ4IABEAgAEAAcJIyQ4IABEAgAAAA==.Onto:BAAALgADCgEJAQAAAA==.Ontoquas:BAAALgADCgkJCgAAAA==.',
Or='Orinin:BAAALgAECgUJBQABLgAECgQJCQADAAAAAA==.',
Ou='Outdeath:BAAALgAECgUJBQAAAA==.',
Pa='Paleclaw:BAAALgADCgQJBAAAAA==.Palitroque:BAAALgAECgQJBAAAAA==.Pally:BAAALgAECgUJBQAAAA==.Papasmurfz:BAAALgAFFAEJAQAAAA==.Paramedic:BAABLgAECn8UAAINAAUJAxPfCwDhAAANAAUJAxPfCwDhAAAAAA==.Pathogen:BAABLgAECn8hAAIHAAkJDR/oOwARAgAHAAkJDR/oOwARAgAAAA==.',
Pe='Penryn:BAAALgAECgQJBwAAAA==.Pepster:BAABLgAECn8bAAIoAAkJtgHgLgCAAAAoAAkJtgHgLgCAAAAAAA==.Persephoknee:BAAALgADCgEJAQAAAA==.Persephoni:BAAALgAECgcJDgAAAA==.',
Pf='Pfchen:BAAALgAECgMJBAAAAA==.',
Pl='Plaguestrip:BAAALgAECgEJAwAAAA==.Plinkerbell:BAAALgAECgMJAwAAAA==.Plumprnickel:BAAALgAECgEJAQAAAA==.Plxkingg:BAAALgADCgUJBQAAAA==.',
Po='Poppit:BAAALgAECgQJBQAAAA==.Porimma:BAABLgAECn8YAAMCAAcJVwYlGACfAAACAAcJVwYlGACfAAABAAMJdgWiEAAzAAAAAA==.Pormas:BAAALgAECgYJDwAAAA==.Poseydon:BAAALgADCgQJBAABLgAECgEJAQADAAAAAA==.',
Pr='Prayerz:BAAALgADCgMJAwAAAA==.Proctology:BAAALgAECgQJBAAAAA==.Prom:BAAALgAECgcJEgAAAA==.Promethèus:BAAALgAECgQJBAAAAA==.Prosby:BAAALgADCgIJAgAAAA==.Protection:BAAALgAFFAEJAQAAAA==.Prowlnfool:BAAALgADCgUJBQAAAA==.Pryto:BAAALgADCgkJDgABLgAFFAIJAwADAAAAAA==.',
Qu='Queedle:BAABLgAECn8lAAIfAAkJNg5lAQA1AQAfAAkJNg5lAQA1AQAAAA==.Quickly:BAAALgAECgcJEgAAAA==.',
Ra='Raennis:BAAALgAECgIJAgAAAA==.Ragalstan:BAAALgAECgEJAgAAAA==.Ragnarook:BAAALgAECgEJAQABLgAECgQJCAADAAAAAA==.Rahanumn:BAABLgAECn8YAAIOAAgJ6wktpAAxAQAOAAgJ6wktpAAxAQAAAA==.Rainlette:BAAALgAECggJEgAAAA==.Rainsvoker:BAACLgAFFH8jAAIlAAYJXQ2aEgBqAQAlAAYJXQ2aEgBqAQAuAAQKf1IAAyUACQkOHL4GAJUCACUACQkOHL4GAJUCACMABgk7CAxeAMAAAAAA.Raizak:BAAALgAECgEJAQAAAA==.Ramike:BAAALgAECggJCQAAAA==.Raqtar:BAAALgAECgIJAgABLgAECgkJEgADAAAAAA==.Rasmis:BAAALgAECgIJAwABLgAECgkJEgADAAAAAA==.Ratbreath:BAAALgADCgYJBgAAAA==.Ratrazarke:BAAALgADCgIJAgAAAA==.Razihel:BAAALgADCgYJCQAAAA==.Razzledazzlë:BAAALgAECgEJAQAAAA==.',
Re='Reaver:BAAALgAECgQJBAAAAA==.Reddan:BAABLgAECn8qAAIOAAgJlgzSmwA+AQAOAAgJlgzSmwA+AQAAAA==.Redruth:BAAALgAECgEJAQAAAA==.Renata:BAAALgAFFAIJAgAAAA==.Replicant:BAAALgAECgEJAQAAAA==.Retman:BAAALgAECgMJAQAAAA==.Reverìe:BAAALgAECgcJBwAAAA==.Reylinn:BAAALgAECgQJBAAAAA==.Reyra:BAAALgAECgEJAQABLgAFFAIJAgADAAAAAA==.Reï:BAABLgAECn8iAAIQAAkJsRTZJAAlAgAQAAkJsRTZJAAlAgAAAA==.',
Ri='Ridlei:BAAALgAECgMJBAAAAA==.Rimchester:BAAALgAECgIJAQAAAA==.Rimurutempas:BAAALgAECgEJAgAAAA==.Rinji:BAAALgAECgYJCwAAAA==.Ritzon:BAABLgAECn89AAMZAAkJJSRhBgD4AgAZAAkJJSRhBgD4AgAYAAEJmBdmcQA+AAAAAA==.',
Ro='Rosadita:BAAALgAECgQJBQAAAA==.Roxydan:BAABLgAECn8dAAMBAAgJiQ03KQAdAQACAAgJiQ1KZwCWAQABAAYJ8Ag3KQAdAQAAAA==.',
Ru='Runastalis:BAAALgADCgYJCwAAAA==.Ruwea:BAAALgAECgEJAQAAAA==.',
Ry='Ryanrainolds:BAAALgAECgYJCQABLgAECgYJIgAKAIEkAA==.Rykken:BAAALgAECgEJAgAAAA==.Ryko:BAABLgAECn8fAAIoAAcJqBSRFwBOAQAoAAcJqBSRFwBOAQAAAA==.',
['Rë']='Rëyra:BAAALgAFFAIJAgAAAA==.',
Sa='Salene:BAAALgAFFAIJAgAAAA==.Sanandume:BAAALgADCgEJAQAAAA==.Sanctess:BAAALgAECggJDgAAAA==.Sankai:BAAALgAECgEJAQABLgAFFAEJAgADAAAAAA==.Saraelle:BAAALgAECgEJAwAAAA==.Sarlas:BAAALgADCgQJBAAAAA==.Sarumanpally:BAAALgAECgYJBwAAAA==.Saruquan:BAAALgAECgkJCQAAAA==.Sayomi:BAAALgADCgcJEwAAAA==.',
Se='Secretjuicy:BAAALgAECgYJCQAAAA==.Sellex:BAAALgAECgEJAQAAAA==.Senseijundra:BAAALgAECgQJCAAAAA==.Sentinaal:BAAALgAECgEJAQAAAA==.Sethira:BAAALgAECgEJAQABLgAECgcJCwADAAAAAA==.',
Sh='Shabadu:BAAALgADCgQJBAAAAA==.Shadyandi:BAAALgADCgcJCAAAAA==.Shamanhack:BAAALgAFFAIJAwAAAA==.Shan:BAAALgADCgYJBgAAAA==.Sharazad:BAAALgAECggJCQAAAA==.Sheda:BAAALgAECgQJBAAAAA==.Shedia:BAAALgAECgEJAQAAAA==.Shmoove:BAEALgAECgUJBgAAAA==.Shmooves:BAEALgAECgQJBAABLgAECgUJBgADAAAAAA==.Shoukei:BAAALgADCgIJAwAAAA==.',
Si='Sianna:BAAALgADCgYJBgAAAA==.Sieya:BAAALgAECgEJAQAAAA==.Siinful:BAAALgAECgEJAQAAAA==.Simbruh:BAAALgADCgMJAwAAAA==.Simpari:BAABLgAFFH8HAAIHAAIJ8Qh3aQB8AAAHAAIJ8Qh3aQB8AAABLgAFFAYJHAAGAF8NAA==.Sinarria:BAAALgAECgEJAQAAAA==.Sithra:BAAALgADCgEJAQAAAA==.',
Sk='Skeemer:BAAALgAECgUJBQAAAA==.Skeetro:BAAALgAECgEJAQAAAA==.Skips:BAAALgAECgQJCQAAAA==.Skullace:BAABLgAECn8qAAIBAAkJuw9GCgChAQABAAkJuw9GCgChAQAAAA==.Skullhead:BAAALgADCgEJAQAAAA==.Skybreaker:BAAALgAECgkJCAAAAA==.Skylette:BAAALgAECgcJCQAAAA==.',
Sm='Smashurfacen:BAAALgADCgcJFAAAAA==.',
Sn='Snitbit:BAAALgADCgkJGgAAAA==.Sno:BAAALgADCgEJAQABLgAECgUJBwADAAAAAA==.Snoopingas:BAAALgAECgEJAQAAAA==.Snpcrklpopu:BAAALgADCgYJCAAAAA==.',
So='Solarana:BAAALgAECgkJCQAAAA==.Sortiebatoru:BAAALgAECgIJAwAAAA==.Sotzi:BAAALgADCggJEQAAAA==.Souldune:BAAALgAECgYJBgAAAA==.',
Sp='Sparkplugg:BAAALgAECgEJAQAAAA==.Sparthos:BAAALgAECgIJAgAAAA==.',
Sr='Srfreaky:BAABLgAECn8VAAIXAAUJ1xtHBQAYAQAXAAUJ1xtHBQAYAQAAAA==.',
St='Sterlìng:BAAALgAECgUJCQAAAA==.Stevejabbs:BAABLgAECn8iAAMKAAYJgSSZAwAkAgAKAAYJgSSZAwAkAgALAAMJ5SAEOQAYAQAAAA==.Stocklock:BAAALgAECgEJAQAAAA==.Stormcunning:BAABLgAECn8WAAImAAYJCAxiTAAWAQAmAAYJCAxiTAAWAQAAAA==.Stormfire:BAAALgADCgcJBwAAAA==.Stormßringer:BAABLgAECn8UAAImAAgJERDXMwCJAQAmAAgJERDXMwCJAQAAAA==.Stownr:BAAALgAECgYJBgAAAA==.Strip:BAAALgAECgEJAQAAAA==.Strongclaw:BAAALgADCgUJBQAAAA==.Stumpyborg:BAABLgAECn8VAAQBAAcJaAY9MgBVAAACAAYJNgSn3gCdAAABAAIJMws9MgBVAAAnAAEJhAcZQwArAAABLgAECgkJFwAIAN0LAA==.Stónéhëárt:BAAALgADCgYJBwABLgAECgkJEQADAAAAAA==.',
Su='Subdue:BAAALgADCgQJBAAAAA==.Subverse:BAAALgAECgQJBAAAAA==.Sukimyheelz:BAAALgAECgQJBAAAAA==.Sundance:BAAALgAECgcJDgAAAA==.Sune:BAABLgAECn8gAAMNAAYJxgvZRwDwAAANAAYJxgvZRwDwAAAhAAEJNwk2ggAqAAAAAA==.Supplicant:BAAALgADCgQJBwAAAA==.',
Sv='Svellulfr:BAAALgAECgEJAQAAAA==.Svuca:BAAALgADCgcJBwAAAA==.',
Sy='Sydneyweenie:BAAALgADCgcJCAAAAA==.Syldi:BAAALgAECgEJAQABLgAECgcJJAAWACsbAA==.Sythis:BAAALgAECgIJAwAAAA==.',
['Sä']='Sästa:BAAALgADCgkJCQAAAA==.',
['Sö']='Sörren:BAABLgAECn8pAAInAAcJYwZUBwCvAAAnAAcJYwZUBwCvAAAAAA==.',
Ta='Tacosdeasada:BAAALgAECgEJAQAAAA==.Taitertot:BAAALgADCgQJBQAAAA==.Tanelórn:BAAALgAECgQJBQAAAA==.Tanlon:BAAALgAECggJEgAAAA==.Tayko:BAAALgAECgEJAQAAAA==.Taykorra:BAAALgADCggJDQAAAA==.',
Te='Telandril:BAABLgAECn8vAAIQAAkJvxH4MwDNAQAQAAkJvxH4MwDNAQAAAA==.Telphin:BAAALgAECgYJDAAAAA==.Tempestira:BAAALgAECgEJAgAAAA==.Tensuken:BAABLgAECn8ZAAIOAAYJpBidsAAeAQAOAAYJpBidsAAeAQAAAA==.Testarossaa:BAAALgADCgEJAQAAAA==.Teylonna:BAAALgAECgEJAQAAAA==.',
Th='Thadgun:BAAALgADCgkJFQAAAA==.Thadium:BAAALgAECgMJAwAAAA==.Thalgan:BAAALgAECgEJAQAAAA==.Thalyn:BAAALgAECgEJAQAAAA==.Thauríel:BAAALgAECgEJAQAAAA==.Thecword:BAAALgADCgYJBgAAAA==.Themedic:BAABLgAECn8gAAMcAAcJoRcoBwC+AQAcAAcJoRcoBwC+AQAmAAEJ6gFuxAAXAAAAAA==.Theremar:BAAALgAECgMJAwAAAA==.Thergothon:BAAALgAECgEJAQABLgAECgMJAwADAAAAAA==.Theunclepaul:BAAALgAECgcJCwAAAA==.Thisisdrexx:BAAALgAECgIJAwAAAA==.Thorwrath:BAAALgADCgEJAgAAAA==.Thrazoro:BAAALgAECgQJBAAAAA==.Thrazzoro:BAAALgAECgYJEwAAAA==.',
Ti='Tiarl:BAACLgAFFH8MAAIWAAMJohLyDwCpAAAWAAMJohLyDwCpAAAuAAQKfzUAAhYACQkdF6ERAFQCABYACQkdF6ERAFQCAAAA.Tiia:BAAALgADCgIJAgAAAA==.Timex:BAABLgAECn8XAAMkAAYJRCD5DgDrAQAkAAYJRCD5DgDrAQAjAAEJUhdnjgA+AAAAAA==.Tinydots:BAAALgAECgcJCAAAAA==.Tinypaws:BAAALgAECgQJBAAAAA==.Tinysitril:BAAALgAECgYJCQABLgAFFAQJCwAeAJcPAA==.Tinysohei:BAAALgAECgQJBAAAAA==.Titañick:BAAALgAFFAIJAgAAAA==.',
To='Tom:BAABLgAECn8aAAMjAAYJLgvvVgDWAAAjAAYJLgvvVgDWAAAkAAEJZQhLJwAvAAAAAA==.Toosxyfohair:BAABLgAECn8pAAIcAAgJFRtPCQCHAQAcAAgJFRtPCQCHAQAAAA==.',
Tr='Trainwrekk:BAAALgADCgYJBgAAAA==.Tranqar:BAAALgAECgQJBgAAAA==.Tresg:BAAALgAECgYJCQAAAA==.Trissandra:BAAALgAECgEJAQAAAA==.Trolltoll:BAAALgADCgEJAwAAAA==.Trüth:BAAALgADCggJEAAAAA==.',
Tu='Tuv:BAAALgAECgMJAwAAAA==.',
Tw='Twentytwo:BAAALgAECgUJBQAAAA==.Twylidan:BAEALgAECgkJCgABLgAFFAQJDAAjAOkeAA==.',
Ty='Tygar:BAAALgAECgEJAQAAAA==.Tyrannt:BAAALgAECgEJAQAAAA==.Tyrannus:BAAALgADCgcJCgAAAA==.Tyrànda:BAAALgAECgUJDAAAAA==.Tyzy:BAAALgAECgEJAgAAAA==.',
['Tö']='Tötém:BAAALgAECgEJAQAAAA==.',
Ul='Ulanhi:BAABLgAECn8VAAIVAAUJzh31EACdAQAVAAUJzh31EACdAQAAAA==.Uling:BAAALgADCgIJAgAAAA==.',
Un='Undeadjelly:BAABLgAECn8VAAMHAAcJsB7oZgCZAQAHAAYJ6B/oZgCZAQAJAAYJehiLFgAkAQAAAA==.Unholy:BAAALgAECgYJDwAAAA==.',
Ur='Urkzul:BAAALgADCgMJAwAAAA==.Ursoth:BAAALgADCgUJCgAAAA==.',
Ut='Uthèrsmight:BAAALgAECgYJBgAAAA==.Uti:BAAALgADCgUJBQAAAA==.',
Uu='Uubs:BAAALgADCgEJAQABLgAFFAMJCgAOAJoSAA==.',
Va='Valakk:BAAALgAECgcJDgAAAA==.Vallak:BAAALgADCgIJBAAAAA==.Valsitril:BAAALgAECgYJEAABLgAFFAQJCwAeAJcPAA==.Valthaczar:BAAALgAECgMJBgAAAA==.Vanara:BAAALgAECgEJAgAAAA==.Varadun:BAAALgAFFAIJAwAAAA==.Varrosh:BAAALgADCgYJBgAAAA==.Vathan:BAAALgAECgQJBQAAAA==.',
Ve='Velmora:BAAALgAECgkJCQAAAA==.Velsetin:BAABLgAECn8dAAIGAAcJTBsyTABSAgAGAAcJTBsyTABSAgABLgAFFAMJBQAbAMcUAA==.Verathina:BAAALgADCgEJAgAAAA==.Versailespq:BAAALgAECgEJAQAAAA==.Versed:BAAALgADCgUJBQABLgAECgQJBAADAAAAAA==.Veryspooky:BAABLgAECn8eAAICAAgJZBsHOAD5AQACAAgJZBsHOAD5AQAAAA==.Vexian:BAABLgAECn8fAAMmAAkJJh1QAwD6AQAmAAkJJh1QAwD6AQAcAAEJ3B/FtwBcAAAAAA==.Vexlock:BAAALgAECgMJAwABLgAECgkJHwAmACYdAA==.',
Vf='Vfl:BAAALgADCgcJBwAAAA==.',
Vi='Vicas:BAAALgAECgcJEgAAAA==.',
Vl='Vladdek:BAAALgAFFAEJAwAAAA==.Vladdok:BAAALgAECgUJBQAAAA==.Vladok:BAAALgAECgQJCwAAAA==.Vladokk:BAAALgAECgMJAwAAAA==.',
Vo='Voidofdeath:BAAALgADCgQJBAAAAA==.Voidshiekah:BAAALgADCgEJAQAAAA==.Vorteia:BAAALgADCgYJBgAAAA==.',
['Vé']='Véngéánçé:BAAALgAECgMJBAAAAA==.',
Wa='Wald:BAAALgAECgYJEAAAAA==.Warmongerr:BAAALgADCgIJAgAAAA==.Waruh:BAAALgADCgcJCQAAAA==.Warzy:BAAALgAECgEJAQAAAA==.',
We='Webgar:BAAALgAECgEJAQAAAA==.Webrune:BAAALgAECgMJAwAAAA==.',
Wh='Whisperlia:BAAALgAECgQJCAAAAA==.Whisperwindd:BAAALgAECgYJDAAAAA==.White:BAABLgAFFH8JAAMnAAMJcBVeCQCFAAACAAIJIxj3PgCUAAAnAAIJRgxeCQCFAAAAAA==.Whitetoothe:BAABLgAECn8/AAIEAAcJ7RadVgCgAQAEAAcJ7RadVgCgAQAAAA==.',
Wi='Witemandown:BAAALgADCgcJCAAAAA==.Witherbear:BAAALgAECgEJAQAAAA==.Witherhoard:BAAALgAECgUJBQAAAA==.Wizzy:BAAALgADCgEJAQAAAA==.',
Wo='Workin:BAAALgADCgEJAQABLgAECgkJIwAQANUVAA==.',
['Wå']='Wånheda:BAAALgAECggJEwAAAA==.',
Xa='Xaniana:BAAALgAECgkJEAAAAA==.Xaosin:BAAALgADCgUJBQAAAA==.',
Xe='Xenzak:BAAALgAECgEJAQAAAA==.Xephir:BAAALgADCgMJAwAAAA==.Xerxës:BAAALgAECgEJAQAAAA==.',
Xl='Xl:BAAALgAECgQJCwAAAA==.',
Xo='Xoito:BAAALgAECgEJAQABLgAFFAEJAQADAAAAAA==.Xotiko:BAAALgAECgYJDAAAAA==.',
Xu='Xubris:BAAALgADCgYJCQAAAA==.',
['Xâ']='Xâxâs:BAAALgAECgMJAwABLgAECggJGwAjAHQFAA==.',
Ya='Yaerin:BAACLgAFFH8ZAAIhAAQJcCMSGwCLAQAhAAQJcCMSGwCLAQAuAAQKfyYAAiEACQnnI/MDAFsDACEACQnnI/MDAFsDAAAA.Yaoi:BAAALgAFFAIJAgAAAA==.',
Yu='Yunarä:BAAALgAECgYJCAAAAA==.Yuukon:BAABLgAECn8bAAQUAAgJtxfwHABxAQAUAAgJtxfwHABxAQAHAAQJ5gOZOQFkAAAJAAEJDwgrGAAvAAAAAA==.',
Za='Zackman:BAAALgAECgQJBAAAAA==.Zakuul:BAAALgADCgQJBAAAAA==.Zalezaar:BAAALgAECgIJAgAAAA==.Zangetsu:BAAALgAECgcJBwAAAA==.Zarusthra:BAAALgAECgEJAQAAAA==.Zaxie:BAABLgAECn8/AAITAAkJrh21AgBLAgATAAkJrh21AgBLAgAAAA==.',
Ze='Zenjuice:BAAALgAECgcJAgAAAA==.Zenwu:BAAALgADCgkJGwAAAA==.Zephrylia:BAAALgAECgUJCgAAAA==.Zerama:BAAALgAECgUJBQAAAA==.',
Zh='Zheratul:BAAALgAECgEJAQAAAA==.Zhirl:BAAALgAECgkJCQAAAA==.Zhivet:BAAALgAECgYJBwAAAA==.',
Zi='Zilphia:BAABLgAECn8qAAIGAAkJzBDfCADAAQAGAAkJzBDfCADAAQAAAA==.',
Zu='Zuriel:BAAALgAECgIJAgAAAA==.',
Zy='Zyku:BAAALgAECgEJAQAAAA==.Zylphie:BAAALgADCgcJBwAAAA==.',
['Àm']='Àmagezing:BAAALgAFFAIJAgABLgAFFAYJGwAOACweAA==.',
['Åj']='Åj:BAAALgADCgcJBwAAAA==.',
['Åp']='Åpexx:BAABLgAECn8cAAMTAAYJKAZ3HwB/AAATAAYJCAZ3HwB/AAAeAAEJzAYcfQAjAAAAAA==.',
['Çw']='Çwÿbàbý:BAAALgAECgYJEwAAAA==.',
['Ór']='Órión:BAABLgAECn8VAAIEAAYJ1BLuoQD+AAAEAAYJ1BLuoQD+AAAAAA==.',
['Ös']='Östara:BAABLgAECn8jAAIQAAkJ1RXkBgBaAQAQAAkJ1RXkBgBaAQAAAA==.',
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
