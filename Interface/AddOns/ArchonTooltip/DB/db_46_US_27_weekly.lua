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

local lookup = {'Warlock-Destruction','Warlock-Demonology','Unknown-Unknown','Hunter-BeastMastery','Mage-Arcane','Mage-Frost','DeathKnight-Unholy','Hunter-Survival','DeathKnight-Frost','Monk-Mistweaver','Monk-Brewmaster','Monk-Windwalker','Priest-Shadow','Paladin-Retribution','Druid-Guardian','Druid-Restoration','Hunter-Marksmanship','Paladin-Protection','DemonHunter-Devourer','DeathKnight-Blood','Druid-Feral','Priest-Holy','Warrior-Arms','Warrior-Protection','Warrior-Fury','Druid-Balance','Shaman-Restoration','Rogue-Subtlety','DemonHunter-Havoc','Rogue-Outlaw','Rogue-Assassination','Priest-Discipline','DemonHunter-Vengeance','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Paladin-Holy','Shaman-Elemental','Warlock-Affliction','Shaman-Enhancement',}
local provider = {region='US',realm='Azuremyst',name='US',type='weekly',zone=46,date='2026-07-19',data={Aa='Aaravos:BAABLgAECn8iAAMBAAkJhhrRBwDUAQABAAkJiBfRBwDUAQACAAUJDhdZCwAeAQAAAA==.Aardia:BAAALgAECgUJBwAAAA==.Aarynae:BAAALgAECgkJDAAAAA==.',
Ab='Abysseon:BAAALgAECgUJDgABLgAECgQJCAADAAAAAA==.',
Ac='Accretion:BAAALgAECgYJBgAAAA==.',
Ad='Adaria:BAABLgAECn8WAAIEAAcJWAWSZQA3AQAEAAcJWAWSZQA3AQAAAA==.Adrillbear:BAAALgAFFAEJAQAAAA==.Adura:BAAALgAECgYJCAAAAA==.',
Ae='Aeirith:BAACLgAFFH8OAAIFAAQJ5hRoAQAjAQAFAAQJ5hRoAQAjAQAuAAQKfyQAAwUACQmwHegBAGYCAAUACQmwHegBAGYCAAYAAQlFChlgATEAAAAA.Aelion:BAAALgAECgEJAQAAAA==.',
Ah='Ahheevoker:BAAALgAECgYJEgAAAA==.',
Ai='Ailsà:BAAALgADCgEJAQAAAA==.',
Ak='Akarias:BAAALgAECgEJAQABLgAECgcJBwADAAAAAA==.',
Al='Aladaria:BAAALgAECgMJAwAAAA==.Aldyah:BAAALgAFFAMJAwAAAA==.Alias:BAAALgAECgYJBQAAAA==.Alistair:BAAALgAECgEJAwAAAA==.Allanonn:BAAALgAECgQJBAAAAA==.Alohomora:BAAALgAECgUJEAAAAA==.Alprazolam:BAAALgAECgEJAQAAAA==.Alvist:BAABLgAECn8UAAIHAAQJrx6gggBeAQAHAAQJrx6gggBeAQAAAA==.',
Am='Amarasu:BAABLgAECn8cAAIIAAkJig+RGwDBAQAIAAkJig+RGwDBAQAAAA==.Amarlly:BAABLgAECn8zAAIJAAkJJhngBwAVAgAJAAkJJhngBwAVAgAAAA==.Amenedil:BAAALgAECgUJDAAAAA==.',
An='Anbrew:BAABLgAECn8UAAQKAAcJdxJoSwA/AQAKAAYJDBJoSwA/AQALAAUJjA6FQAD4AAAMAAEJMwe0rwAlAAABLgAFFAcJEAAHAHYeAA==.Ancelina:BAABLgAECn8qAAINAAkJeyR3AgBCAwANAAkJeyR3AgBCAwAAAA==.Anderton:BAABLgAECn87AAIOAAgJNRqSDABjAQAOAAgJNRqSDABjAQAAAA==.Andilocks:BAAALgADCgMJAwAAAA==.Andrela:BAAALgAECgYJCgAAAA==.Andromadda:BAAALgADCggJCAAAAA==.Aneira:BAABLgAECn8nAAMPAAcJ8BGdBQAvAQAPAAcJ8BGdBQAvAQAQAAMJYQySmQB/AAAAAA==.Annovera:BAAALgAECgMJBgAAAA==.Anyi:BAAALgAECgEJAQAAAA==.',
Ap='Apexxd:BAAALgAECgUJBQAAAA==.Applefritter:BAAALgAECgUJCAABLgAECgkJKAANAJYbAA==.',
Ar='Araga:BAAALgAECgEJAQAAAA==.Archérhiro:BAACLgAFFH8nAAMEAAgJkRXHCAAyAgAEAAcJUxjHCAAyAgARAAMJRwTfIQCHAAAuAAQKfyoAAwQACQmGH+0YAJECAAQACQl6H+0YAJECABEACAkrGdobAEoCAAAA.Arilias:BAAALgAECgEJAQABLgAECgkJQwAEANEfAA==.Arillann:BAABLgAECn89AAISAAkJUR+3BACuAgASAAkJUR+3BACuAgAAAA==.Arrook:BAAALgAECgMJAwAAAA==.Arrtonomis:BAAALgAECgUJCAABLgAECgkJEgADAAAAAA==.Artdemsamis:BAAALgAECgkJEgAAAA==.Arte:BAABLgAECn89AAIEAAkJaxOnLAABAgAEAAkJaxOnLAABAgAAAA==.Arthundermis:BAAALgAECgkJEQABLgAECgkJEgADAAAAAA==.Artlunarmis:BAAALgADCgEJAQABLgAECgkJEgADAAAAAA==.Arvena:BAABLgAECn8nAAITAAkJVgoWdAA5AQATAAkJVgoWdAA5AQAAAA==.',
As='Asclëpius:BAAALgADCgcJBgABLgAECgEJAQADAAAAAA==.Asheron:BAAALgAECgYJCAAAAA==.Ashylock:BAAALgAECgEJAQABLgAFFAUJEAAGAGAWAA==.Ashymage:BAACLgAFFH8QAAIGAAUJYBabYAAgAQAGAAUJYBabYAAgAQAuAAQKfzcAAgYACQlYHLYpAMwCAAYACQlYHLYpAMwCAAAA.Askevar:BAABLgAECn8wAAMHAAkJTww2CgBjAQAHAAkJnws2CgBjAQAUAAYJ5wlHJwAEAQAAAA==.Aspect:BAAALgADCgEJAQABLgAFFAIJAwADAAAAAA==.Asriél:BAAALgAECgYJDQAAAA==.Astor:BAAALgADCgMJBQAAAA==.Astrona:BAAALgADCgkJFwAAAA==.',
At='Atreus:BAABLgAECn8YAAIOAAkJbAXUwQAGAQAOAAkJbAXUwQAGAQAAAA==.Attalaguy:BAAALgAECgYJDgAAAA==.',
Au='Audra:BAAALgADCgcJDgAAAA==.',
Av='Avabeatrix:BAAALgADCgEJAQAAAA==.Avinthoro:BAAALgADCgIJAgAAAA==.',
Ay='Ayyayyron:BAAALgAECgUJCQAAAA==.',
Az='Azaleah:BAABLgAECn9MAAIOAAkJRx3xGQCoAgAOAAkJRx3xGQCoAgAAAA==.Azanoth:BAAALgADCgIJAgAAAA==.Azraesha:BAABLgAECn8rAAITAAkJ/BUDKgAhAgATAAkJ/BUDKgAhAgAAAA==.Azureflamez:BAAALgAECgEJAQAAAA==.Azurewraith:BAAALgAECgQJBAAAAA==.Azzul:BAAALgADCgcJBwAAAA==.',
Ba='Backy:BAABLgAECn8ZAAIVAAkJtRRyAQDrAQAVAAkJtRRyAQDrAQAAAA==.Baiken:BAAALgAECgIJAgABLgAECgQJCAADAAAAAA==.Banjoman:BAABLgAECn8kAAIWAAcJXSTpCgC4AgAWAAcJXSTpCgC4AgAAAA==.Baza:BAAALgADCgYJBgAAAA==.Baýlei:BAABLgAECn8WAAIKAAYJ5A0kWwAHAQAKAAYJ5A0kWwAHAQAAAA==.',
Be='Beareold:BAAALgAECgMJAwAAAA==.Beary:BAAALgAECgQJCAAAAA==.Beenaughty:BAAALgAECgEJAQABLgAECgEJAQADAAAAAA==.Belaanna:BAAALgADCgYJCQAAAA==.Beliria:BAAALgADCgUJBgAAAA==.Benimaru:BAAALgAECgUJDwAAAA==.Beriko:BAAALgAECgMJAwAAAA==.Bernat:BAAALgAECgEJAQAAAA==.Beàrdfáce:BAAALgADCgQJBAAAAA==.',
Bi='Bigblunt:BAAALgAECgEJAQAAAA==.Bigjuicy:BAABLgAECn8UAAQXAAkJBxghCACqAAAYAAYJNxEpJAAPAQAXAAUJVRkhCACqAAAZAAUJBhUREACpAAAAAA==.Billie:BAAALgAECgcJCwAAAA==.Bimboficate:BAAALgADCgYJBwAAAA==.',
Bl='Black:BAAALgAFFAEJAQAAAA==.Blackadder:BAABLgAECn8oAAISAAcJPw4ZBQAOAQASAAcJPw4ZBQAOAQAAAA==.Blondie:BAAALgADCgQJBAABLgAECgYJEwADAAAAAA==.Bloodie:BAAALgAECgMJAwAAAA==.Blue:BAABLgAECn88AAIMAAkJxRvlDgBbAgAMAAkJxRvlDgBbAgAAAA==.Blueguy:BAAALgAECgQJBgAAAA==.Bluestreak:BAAALgAECgEJAwABLgAECgcJCQADAAAAAA==.',
Bo='Bobthefist:BAAALgADCgcJBwAAAA==.Bode:BAAALgAECgYJEwAAAA==.Bogern:BAAALgADCgcJBwAAAA==.Bolau:BAAALgADCgYJBwAAAA==.Boltz:BAAALgADCgYJBgAAAA==.Boogy:BAAALgAFFAEJAQAAAA==.Bopdiz:BAAALgAECgEJAQABLgAECgQJFAAHAK8eAA==.Borledish:BAAALgAECgMJBAABLgAECgQJFAAHAK8eAA==.Bottosai:BAAALgAECgEJAgAAAA==.',
Br='Brambles:BAAALgAECgEJAQAAAA==.Branwynn:BAAALgAECgYJEQAAAA==.Breezyfight:BAAALgAFFAIJAgAAAA==.Breezyrocks:BAAALgADCgQJCQAAAA==.Breezysha:BAAALgADCgcJCAAAAA==.Brenz:BAABLgAFFH8GAAMOAAMJOQIKqgBuAAAOAAMJOwEKqgBuAAASAAEJvQR6HAAhAAAAAA==.Brewdaddy:BAAALgAECgUJEwABLgAECgkJOwASAHwRAA==.Brewdude:BAAALgAECgEJAQAAAA==.Brigor:BAAALgAECgYJEAAAAA==.Brokenblade:BAAALgADCgYJBgAAAA==.Brotherblood:BAAALgAECgYJDAAAAA==.',
Bu='Bulldoza:BAAALgAECgQJBQAAAA==.Bullwankle:BAAALgADCggJDQAAAA==.Bullwinkles:BAAALgAECgEJAQAAAA==.Bunbot:BAAALgAECgEJAQAAAA==.Butterknifeo:BAABLgAFFH8FAAIaAAMJxxSHMQC7AAAaAAMJxxSHMQC7AAAAAA==.',
By='Byryja:BAABLgAECn8nAAIGAAcJbAk2GwDSAAAGAAcJbAk2GwDSAAAAAA==.',
Ca='Cabela:BAAALgAECgkJDgAAAA==.Cahrazie:BAACLgAFFH8GAAIOAAMJ9wkqewDAAAAOAAMJ9wkqewDAAAAuAAQKfx0AAg4ACQkaFbZIAOwBAA4ACQkaFbZIAOwBAAAA.Caidinn:BAAALgAECgkJEQAAAA==.Caitrîn:BAAALgADCgkJCQABLgAECgcJJwAPAPARAA==.Calissancia:BAABLgAECn82AAIKAAgJNBdEHwAgAgAKAAgJNBdEHwAgAgAAAA==.Calkey:BAABLgAECn8WAAIBAAYJUQgMHwCyAAABAAYJUQgMHwCyAAAAAA==.Calliaa:BAAALgADCgEJAQABLgADCgcJDQADAAAAAA==.Callmemommy:BAAALgADCgYJBgAAAA==.Carnelia:BAAALgAECgEJAQAAAA==.Carvana:BAAALgAECgkJBwAAAA==.Catalyst:BAAALgADCgMJAwAAAA==.Cathandris:BAAALgADCgEJAQAAAA==.Catovia:BAAALgAECgYJBwAAAA==.',
Ce='Ceri:BAAALgAECgkJBwAAAA==.Ceska:BAAALgADCgEJAQAAAA==.',
Ch='Chadarack:BAAALgAECgYJBwAAAA==.Chadaracks:BAAALgAECgEJAQAAAA==.Chancy:BAAALgAECgMJBQAAAA==.Channingtotm:BAACLgAFFH8vAAIbAAUJ7iW6BAAHAgAbAAUJ7iW6BAAHAgAuAAQKfzsAAhsACQlhIY4EAG4DABsACQlhIY4EAG4DAAAA.Chantix:BAAALgADCgUJBQAAAA==.Charlemoo:BAAALgADCgUJBQABLgAECgMJAwADAAAAAA==.Cheekymonkey:BAABLgAECn8qAAIFAAkJMQ2EBQB+AQAFAAkJMQ2EBQB+AQAAAA==.Chrispbacon:BAAALgAECgUJEgAAAA==.Chueyé:BAAALgAECgQJBAABLgAFFAMJDAAcAO8dAA==.Chune:BAAALgAECgcJCgAAAA==.Chunkyy:BAAALgADCgYJBgAAAA==.Churros:BAABLgAECn8oAAMNAAkJlhuVEQBJAgANAAkJlhuVEQBJAgAWAAcJThV3JwCKAQAAAA==.',
Ci='Cincog:BAAALgAECgQJBAABLgAECgYJCQADAAAAAA==.',
Cl='Closetcookie:BAAALgAECgQJBAAAAA==.',
Co='Coberren:BAAALgAECgEJAQAAAA==.Cordialkylie:BAAALgAECgIJAgAAAA==.Cowcrusader:BAAALgADCgcJBwAAAA==.',
Cr='Crazyugly:BAAALgAECgQJBQAAAA==.Crogrer:BAAALgAECgMJAwAAAA==.Crosslock:BAAALgAECgUJDwAAAA==.',
Cu='Cuppycakes:BAAALgADCgcJFAAAAA==.',
Cy='Cynnari:BAAALgAECgYJDQAAAA==.',
Da='Daddysecret:BAAALgAECgQJBQAAAA==.Dalan:BAAALgAECgIJAgABLgAFFAQJDgAFAOYUAA==.Dalaris:BAACLgAFFH8LAAIdAAQJlw9lCwDXAAAdAAQJlw9lCwDXAAAuAAQKfyIAAh0ACQmdFiASAAoCAB0ACQmdFiASAAoCAAAA.Danizmi:BAAALgADCgQJBAAAAA==.Dano:BAAALgADCgYJDQAAAA==.Darci:BAAALgAECgYJCwAAAA==.Darkeon:BAAALgAECgcJCwAAAA==.Darkénrahl:BAAALgAECgEJAQABLgAFFAMJBwAEAP4MAA==.Darlenedark:BAAALgAECgEJAQAAAA==.Darling:BAAALgAECgIJAgAAAA==.Darron:BAAALgAECgIJBAABLgAECggJEgADAAAAAA==.Darrosh:BAABLgAECn8bAAQeAAgJuxOEEgDhAAAeAAYJDhCEEgDhAAAcAAcJjQ34PgDLAAAfAAMJ9hB8FAC1AAAAAA==.Dartian:BAAALgADCgcJDQABLgAECgkJQwAEANEfAA==.Daylightt:BAAALgAECgIJAgAAAA==.Dazblood:BAAALgAECgIJAgAAAA==.Dazdot:BAAALgADCgQJBAABLgAECgIJAgADAAAAAA==.Dazsham:BAAALgAECgEJAQABLgAECgIJAgADAAAAAA==.',
De='Deadjuicy:BAAALgAECggJCAAAAA==.Deathdevil:BAAALgAECgUJBQAAAA==.Deathlurker:BAAALgADCgQJBAAAAA==.Deathmare:BAAALgAECgUJBQAAAA==.Deathmommy:BAAALgAECgcJCAAAAA==.Deathty:BAAALgAECgMJCgABLgAFFAEJAgADAAAAAA==.Dementia:BAAALgADCgMJAwAAAA==.Design:BAABLgAECn8lAAICAAkJ4Rc7MgAPAgACAAkJ4Rc7MgAPAgAAAA==.Desmeridian:BAAALgAECgUJBQAAAA==.Dethendrova:BAAALgADCgYJBgABLgAFFAMJBwAEAP4MAA==.Devotee:BAAALgADCgIJAgAAAA==.',
Dh='Dhish:BAABLgAECn8bAAQaAAYJpAdKDQCnAAAaAAYJpAdKDQCnAAAVAAMJMwdTPABoAAAQAAIJ6gIc1AAxAAAAAA==.',
Di='Diltlish:BAAALgAECgUJCgAAAA==.Diocles:BAAALgAECgUJBgAAAA==.Disconcern:BAAALgAECgEJAQAAAA==.Discontent:BAACLgAFFH8GAAIXAAIJUR2wMwCNAAAXAAIJUR2wMwCNAAAuAAQKfxQAAxcABwnwHKQQAOkBABcABwnwHKQQAOkBABkABQknEVxuAP0AAAAA.Discordiä:BAABLgAECn8XAAIgAAgJHRf9HQDeAQAgAAgJHRf9HQDeAQAAAA==.Discspal:BAAALgAECgYJBwAAAA==.Diåblo:BAAALgADCgUJBQAAAA==.',
Dm='Dmginc:BAAALgADCgIJAgAAAA==.',
Do='Doeblin:BAAALgAECgUJEwAAAA==.Domidouse:BAAALgAECgYJCgAAAA==.Domivyr:BAAALgADCgMJAwAAAA==.Donkedixon:BAAALgADCgYJBgAAAA==.Dosar:BAAALgADCgIJAgAAAA==.Doubledeuces:BAAALgADCgIJAgAAAA==.Doubtz:BAAALgAECgQJBQABLgAECgQJFAAHAK8eAA==.',
Dp='Dpalx:BAAALgAECgQJBAAAAA==.Dpxs:BAABLgAFFH8HAAIbAAQJkha7PwDmAAAbAAQJkha7PwDmAAAAAA==.',
Dr='Dracaria:BAAALgAECgEJAQAAAA==.Dracones:BAAALgAECgYJDgAAAA==.Dragondz:BAAALgAECgUJBQAAAA==.Dragonflai:BAABLgAECn8nAAIGAAkJnBdCUwDjAQAGAAkJnBdCUwDjAQAAAA==.Dragonkin:BAAALgAECgQJCAAAAA==.Drakkari:BAABLgAECn8WAAMhAAYJKAc2BQChAAAhAAYJHQc2BQChAAATAAYJGwQ20QCQAAAAAA==.Drakkei:BAABLgAECn9UAAMEAAkJHRsnBwDmAQAEAAkJHRsnBwDmAQAIAAMJIga/SQCSAAAAAA==.Drawbridge:BAAALgAECgEJAQAAAA==.Drerane:BAAALgADCgYJBgAAAA==.Drexxsster:BAAALgADCgQJBAAAAA==.Drshortbus:BAAALgAECgUJCgAAAA==.Drumitus:BAAALgADCgYJCAAAAA==.Drunkngrundl:BAABLgAECn89AAILAAkJHiMoBAAGAwALAAkJHiMoBAAGAwAAAA==.Drylo:BAECLgAFFH8MAAMiAAQJ6R51IABcAQAiAAQJ6R51IABcAQAjAAEJFB64BQBOAAAuAAQKfy0AAyIACQkmII4JAL8CACIACQmLHo4JAL8CACMACAnFH6UGAIgCAAAA.',
Du='Duckeey:BAAALgAFFAIJBAABLgAFFAYJHAAGAF8NAA==.Dunstir:BAABLgAECn8ZAAIOAAgJ6QUgwAAIAQAOAAgJ6QUgwAAIAQAAAA==.Dusktrekker:BAAALgAECgkJBwAAAA==.',
Dy='Dypshyt:BAABLgAECn8aAAQiAAkJhxfkTwDvAAAjAAUJUBJRIgAYAQAiAAYJqxDkTwDvAAAkAAUJTgemLgB1AAAAAA==.Dyyke:BAAALgAECgEJAQAAAA==.',
Ed='Edelweíss:BAAALgAECgUJDwAAAA==.',
Ek='Ekazzik:BAAALgAECgYJBgABLgAFFAMJBwAEAP4MAA==.Ekoh:BAAALgAECgIJAgAAAA==.',
El='Elaaranna:BAAALgAECgMJAwAAAA==.Elarol:BAAALgAECgQJBQAAAA==.Eldons:BAAALgADCgIJAgAAAA==.Elfie:BAAALgADCggJCAAAAA==.Elladra:BAAALgAECgMJAwAAAA==.',
Em='Embers:BAABLgAECn8WAAIZAAYJGxPjWADrAAAZAAYJGxPjWADrAAAAAA==.Emeralde:BAAALgAECgYJCgAAAA==.Emilia:BAAALgADCgIJAwAAAA==.Emptyhands:BAAALgAECgYJBgAAAA==.Emptyheals:BAABLgAECn8zAAIgAAkJ3yC7BABEAwAgAAkJ3yC7BABEAwAAAA==.',
En='Enticedem:BAAALgAECgEJBAAAAA==.',
Er='Ereada:BAAALgADCgUJCgAAAA==.Erfinden:BAAALgADCgEJAQAAAA==.',
Es='Espernite:BAAALgAECgQJBAAAAA==.Espers:BAACLgAFFH8GAAIaAAMJCgfQGACXAAAaAAMJCgfQGACXAAAuAAQKfx8AAhoACQnpD68+ABQBABoACQnpD68+ABQBAAAA.',
Et='Ethellin:BAABLgAECn9BAAIOAAkJ0wheEgAaAQAOAAkJ0wheEgAaAQAAAA==.',
Eu='Euredes:BAAALgADCgYJBgABLgAFFAMJBwAEAP4MAA==.',
Fa='Fahrenheit:BAAALgAECgEJAgAAAA==.Farkuat:BAAALgADCgQJBAAAAA==.Fatcastle:BAAALgADCgcJDgAAAA==.',
Fe='Feedmepizzas:BAAALgAECgMJCAAAAA==.Feildmedic:BAAALgAECgEJAQAAAA==.Feleria:BAABLgAECn8YAAIlAAYJsxR6BgAwAQAlAAYJsxR6BgAwAQAAAA==.Fellslasher:BAAALgAECgIJAgAAAA==.Felmage:BAAALgADCgYJBgAAAA==.Felraiser:BAAALgADCgIJAgABLgADCgUJBgADAAAAAA==.Felwinter:BAABLgAECn81AAICAAkJthrMIQBbAgACAAkJthrMIQBbAgAAAA==.Femcelgoon:BAAALgADCgEJAQAAAA==.Fenna:BAAALgADCgYJDAAAAA==.Fetor:BAAALgAECgcJEAAAAA==.',
Fi='Fingulfin:BAAALgAECgIJAwAAAA==.Finwé:BAAALgAECgQJCgAAAA==.Fistsalot:BAAALgAECgQJCAAAAA==.',
Fl='Flafferthorn:BAAALgAECgMJAwAAAA==.Fluxarata:BAABLgAECn8rAAITAAkJ9g27UwCLAQATAAkJ9g27UwCLAQAAAA==.',
Fo='Forthememes:BAAALgAECgcJCQAAAA==.',
Fr='Fred:BAABLgAECn8vAAIZAAgJBAvGPQBPAQAZAAgJBAvGPQBPAQAAAA==.Freddrick:BAAALgADCgQJBAAAAA==.Friendly:BAAALgAECgEJAQAAAA==.Frostbuddy:BAAALgAECgcJDQAAAA==.Frëya:BAAALgADCgYJDQAAAA==.Frío:BAAALgAECgEJAQAAAA==.Frøstitute:BAABLgAECn8tAAIGAAkJwRenMwBKAgAGAAkJwRenMwBKAgAAAA==.',
Fu='Fullmage:BAAALgADCgQJBAAAAA==.',
['Fè']='Fènrïr:BAAALgADCgQJBAAAAA==.',
Ga='Gabel:BAABLgAECn8nAAIVAAkJQh3JBgB2AgAVAAkJQh3JBgB2AgAAAA==.Gadnabit:BAAALgADCgkJCQAAAA==.Gailardia:BAACLgAFFH8GAAIEAAMJzRIJLADeAAAEAAMJzRIJLADeAAAuAAQKfyQAAgQABwn/HYUvAB4CAAQABwn/HYUvAB4CAAEuAAUUBAkeABYAxx4A.Galand:BAABLgAECn8mAAMHAAcJPB37DQAqAQAHAAcJzBz7DQAqAQAUAAIJoiFoUABTAAAAAA==.Galladin:BAAALgADCggJDgAAAA==.Gardyson:BAABLgAECn8cAAMYAAcJMxemAwBTAQAYAAcJMxemAwBTAQAZAAEJbQNKtAAhAAABLgAFFAMJBwAEAP4MAA==.Gazton:BAAALgAECgUJBQAAAA==.',
Gl='Glaaki:BAAALgAECgUJEAAAAA==.',
Gn='Gnob:BAAALgAECgYJEQAAAA==.',
Go='Gooblet:BAAALgADCgQJBQAAAA==.Goodfellow:BAAALgAECgEJAQABLgAECgYJFQAVAMUcAA==.Goopy:BAAALgADCgYJAwAAAA==.',
Gr='Graendal:BAAALgADCgQJBAAAAA==.Granite:BAAALgAECgMJBAAAAA==.Granted:BAAALgADCgUJBQAAAA==.Greevil:BAAALgAECgEJAwAAAA==.Gremilien:BAABLgAECn8xAAIRAAkJQhg8AQCsAQARAAkJQhg8AQCsAQAAAA==.Grimgorr:BAAALgADCgMJAwAAAA==.Grimmly:BAAALgAECgEJAQAAAA==.Gruggrug:BAAALgAFFAIJAQAAAA==.Grymdevours:BAAALgADCgYJBgAAAA==.Grymmana:BAAALgADCgQJBAAAAA==.',
Ha='Halcyonic:BAAALgAECgUJCgAAAA==.Halleyscomet:BAABLgAECn8WAAIOAAcJPBptRAAXAgAOAAcJPBptRAAXAgAAAA==.Happyhammer:BAAALgADCgcJCAAAAA==.Harrod:BAAALgAECggJCwAAAA==.Hashey:BAAALgAECgEJAgAAAA==.Hawkwave:BAAALgAECgcJEgABLgAECgkJEQADAAAAAA==.Hazardzone:BAAALgAECgMJCgAAAA==.',
He='Heartburn:BAAALgAFFAEJAQABLgAFFAYJHQAZAAUdAA==.Heavyweather:BAAALgADCgcJBwAAAA==.Hefty:BAABLgAECn8XAAMIAAkJ3QtnKQBVAQAIAAcJKQtnKQBVAQAEAAUJ8gm3owD6AAAAAA==.Heftyer:BAAALgAECgMJAwAAAA==.Helioween:BAAALgADCgMJAwAAAA==.Helixon:BAAALgADCgYJBgAAAA==.Hellbad:BAACLgAFFH8MAAILAAQJ7hO+KAAGAQALAAQJ7hO+KAAGAQAuAAQKfxUAAwsACAleGMEnAHMBAAwABgmOG30jALoBAAsACAkXEsEnAHMBAAAA.Hellbine:BAAALgADCgMJAgAAAA==.Hellfella:BAAALgAECgEJAQAAAA==.Hellonheels:BAAALgAECgQJBAAAAA==.Hellsspawn:BAAALgAECgYJEAAAAA==.Hexaverse:BAAALgADCgYJBgABLgAECgQJBAADAAAAAA==.',
Ho='Hoardwither:BAAALgAECgEJAgAAAA==.Hoenheim:BAAALgAECgEJAQAAAA==.Hogrog:BAAALgADCgMJAwAAAA==.Hokàge:BAACLgAFFH8MAAIcAAMJ7x3+JAD8AAAcAAMJ7x3+JAD8AAAuAAQKfzkABBwACQkpIvQIAJYCABwACQkpIvQIAJYCAB8AAgkCGhgbAIwAAB4AAQkZAlosAAkAAAAA.Holymortal:BAAALgAECgYJDAAAAA==.Homealone:BAABLgAECn8aAAMbAAkJAQlefADrAAAbAAgJJQdefADrAAAmAAUJ8gPZfQB3AAAAAA==.Honeycruller:BAAALgAECgMJAwABLgAECgkJKAANAJYbAA==.',
Hu='Huffles:BAAALgAECgQJBwAAAA==.Hugmachine:BAAALgAFFAIJAgAAAA==.Huntinfuzzy:BAAALgAECgkJDwAAAA==.Huntn:BAAALgADCggJCAAAAA==.',
Hy='Hypahypa:BAAALgAECggJEgAAAA==.',
Ia='Iamknot:BAAALgAECgQJBgAAAA==.',
Ic='Icemommy:BAAALgADCgQJCAAAAA==.',
Ig='Igothots:BAACLgAFFH8FAAIQAAIJZBDKVQBvAAAQAAIJZBDKVQBvAAAuAAQKfx4AAxAACQl/HgIQALgCABAACQl/HgIQALgCABUAAQltCb9YACkAAAAA.',
Il='Illariana:BAABLgAECn8aAAQNAAgJNRI5LABzAQANAAgJNRI5LABzAQAWAAEJwQLCegAfAAAgAAEJvgHGigAdAAAAAA==.Illirotica:BAAALgAECgcJCQAAAA==.',
In='Incredibro:BAAALgADCgEJAQAAAA==.Insanitty:BAAALgAECgcJDwAAAA==.Invincible:BAAALgAECgEJAQABLgAECgYJIgAKAIEkAA==.',
Ir='Ironlobo:BAABLgAECn8YAAIGAAYJhxkZfACAAQAGAAYJhxkZfACAAQAAAA==.Ironsolari:BAAALgADCgYJBgAAAA==.Irritable:BAABLgAECn8kAAMnAAkJARs/AwCHAgAnAAkJARs/AwCHAgACAAEJJRftIQFGAAAAAA==.',
It='Itherious:BAAALgAECgUJEAAAAA==.',
Ja='Jacham:BAABLgAECn8WAAIZAAkJ2hSIHwDzAQAZAAkJ2hSIHwDzAQAAAA==.Jackyll:BAAALgAECgQJCAAAAA==.Jacmehof:BAAALgADCgIJAgAAAA==.Jagerboy:BAAALgAECgYJBgAAAA==.Jango:BAAALgAECgIJAgABLgAFFAMJBwAEAP4MAA==.Jatix:BAACLgAFFH8WAAIOAAUJ0CC/GQAXAQAOAAUJ0CC/GQAXAQAuAAQKfyoAAg4ACQkcI3kPAOoCAA4ACQkcI3kPAOoCAAAA.',
Je='Jeetkundo:BAAALgADCgEJAQABLgAECgYJIgAKAIEkAA==.Jellydh:BAAALgAECgUJCgAAAA==.Jellymagus:BAAALgAECgIJAgAAAA==.Jellyms:BAAALgAECgcJDwAAAA==.Jellyspinoff:BAAALgAECgMJBwAAAA==.Jellytown:BAABLgAECn89AAIGAAkJaxRVRQALAgAGAAkJaxRVRQALAgAAAA==.Jelorinea:BAAALgAECgMJCQAAAA==.Jemmi:BAAALgADCgEJAQAAAA==.Jessiana:BAABLgAECn8UAAIBAAYJMxRCAwAsAQABAAYJMxRCAwAsAQAAAA==.Jezelda:BAAALgAECgQJBgAAAA==.',
Jo='Joeydonuts:BAEALgAECgMJAwABLgAECgUJBgADAAAAAA==.Jolten:BAAALgADCgMJAwAAAA==.',
Jp='Jpeppers:BAABLgAECn8iAAIEAAcJYhXODQBfAQAEAAcJYhXODQBfAQAAAA==.',
Ju='Judgementalx:BAAALgAFFAEJAQAAAA==.Juicifer:BAAALgAECgYJBwAAAA==.Jumano:BAAALgAECgUJCgAAAA==.Jundra:BAAALgAECgUJCgAAAA==.Jurih:BAAALgADCgIJAgAAAA==.',
Ka='Kaineh:BAABLgAECn8oAAIRAAgJah3WBQA/AgARAAgJah3WBQA/AgAAAA==.Kainë:BAAALgADCgIJAgAAAA==.Kait:BAABLgAECn8+AAIEAAkJ6R8zEQDHAgAEAAkJ6R8zEQDHAgAAAA==.Kaladil:BAAALgAECgcJDgAAAA==.Kamis:BAAALgAECgMJAwAAAA==.Kanaga:BAAALgAECgQJBQAAAA==.Kannan:BAABLgAECn8YAAMTAAgJzxv/LwA8AgATAAgJzxv/LwA8AgAdAAEJAQdWeQAqAAAAAA==.Kashmihhr:BAAALgADCgIJAgAAAA==.Kashmir:BAAALgAECgQJBAAAAA==.Kasmes:BAAALgADCggJGQAAAA==.Kasmius:BAAALgAECgMJAwAAAA==.Kasmus:BAAALgAECgQJCAAAAA==.Kawdor:BAABLgAECn87AAQSAAkJfBHfFwBgAQASAAgJ2xDfFwBgAQAlAAcJfRRaBgA1AQAOAAMJ8wrNQQFqAAAAAA==.',
Ke='Keanuleaves:BAAALgAECgIJAgAAAA==.Keetsz:BAAALgAECgYJDAAAAA==.Kelaino:BAAALgADCgQJBQAAAA==.Keledish:BAAALgADCgEJAQAAAA==.',
Kh='Khansmebduke:BAACLgAFFH8FAAMdAAQJNxakGQDUAAAdAAMJkRmkGQDUAAATAAEJKgzfnQA9AAAuAAQKfxYAAx0ACAmlHC4WANkBABMACAk1F1w+APsBAB0ABwlXHS4WANkBAAEuAAUUBQkJABUAjh4A.Khota:BAAALgAECgYJDAAAAA==.',
Ki='Kiaf:BAAALgADCgcJDQAAAA==.Kiba:BAAALgADCgEJAQAAAA==.Killakeecat:BAAALgADCgYJBgAAAA==.Killanick:BAAALgAECgEJAQAAAA==.Killdar:BAAALgAECgQJBAAAAA==.Kimia:BAAALgADCgYJCQAAAA==.Kirtthedirt:BAAALgAECgYJCAAAAA==.Kirtthehurt:BAABLgAECn8pAAIGAAkJShhlMABXAgAGAAkJShhlMABXAgAAAA==.',
Ko='Koldfront:BAAALgAECgUJDwAAAA==.Kollinator:BAABLgAECn8cAAIEAAYJzBmQDAB0AQAEAAYJzBmQDAB0AQAAAA==.Korso:BAAALgADCgUJCwABLgAECgcJJwAPAPARAA==.Kotal:BAAALgAECgEJAQAAAA==.',
Ku='Kurtina:BAAALgAECgMJAwAAAA==.',
Ky='Kylair:BAABLgAECn80AAINAAkJ/B4cCgCtAgANAAkJ/B4cCgCtAgAAAA==.Kynreessa:BAAALgADCgYJCAAAAA==.Kyyell:BAAALgAECggJDgAAAA==.Kyønshi:BAAALgADCgUJBgAAAA==.',
['Kì']='Kìrito:BAAALgAECgcJDgAAAA==.',
La='Labeya:BAEALgADCgMJAwAAAA==.Lafty:BAAALgAFFAEJAgAAAA==.Laftydh:BAAALgAECgYJEgABLgAFFAEJAgADAAAAAA==.Lailah:BAAALgADCgIJAgABLgAECgkJTAAOAEcdAA==.Laine:BAAALgADCgMJAwAAAA==.Landrra:BAAALgAECgQJBAAAAA==.Larac:BAAALgAECgkJEwAAAA==.Lastwhisper:BAAALgAECgEJAQAAAA==.Lathsong:BAAALgADCgYJDwAAAA==.Lavi:BAAALgADCgQJAwAAAA==.',
Le='Leadge:BAAALgADCgYJBwAAAA==.Lenik:BAABLgAECn8aAAIcAAYJ+gkGOADxAAAcAAYJ+gkGOADxAAAAAA==.Leskya:BAAALgADCgQJAwAAAA==.',
Li='Libras:BAAALgADCgMJAwAAAA==.Licorice:BAAALgAECgUJDgABLgAECgkJKAANAJYbAA==.Lieree:BAABLgAECn8XAAIGAAgJUg3VggByAQAGAAgJUg3VggByAQAAAA==.Lifeguàrd:BAAALgAECgkJBwAAAA==.Lillana:BAAALgADCgcJDQAAAA==.Lilrayne:BAAALgADCgYJBgABLgAECgkJHAAIAIoPAA==.Lilyfaye:BAAALgADCgkJDAAAAA==.Limosfire:BAABLgAECn8VAAIRAAYJkAO7JACOAAARAAYJkAO7JACOAAAAAA==.Linsatha:BAAALgAECggJEAAAAA==.',
Lo='Loa:BAAALgAECgUJBwAAAA==.Lockty:BAAALgAECgIJBgABLgAFFAEJAgADAAAAAA==.Logi:BAAALgADCgYJCwAAAA==.Lorezever:BAAALgADCgcJDQAAAA==.Lotion:BAAALgADCgIJAgAAAA==.',
Lu='Luar:BAAALgAECgYJDQAAAA==.Lulubean:BAAALgAECgMJAwAAAA==.Lunaris:BAAALgADCgQJBAAAAA==.Lungorthin:BAAALgAECgQJBQAAAA==.Lunà:BAABLgAECn8lAAIBAAgJZgYDBgC/AAABAAgJZgYDBgC/AAAAAA==.',
Ly='Lythalle:BAAALgAECgEJAQAAAA==.Lythwynn:BAABLgAECn8rAAIOAAkJhQ+0cwCGAQAOAAkJhQ+0cwCGAQAAAA==.',
['Lá']='Lásh:BAAALgAECgUJCAABLgAECgcJJwAPAPARAA==.',
Ma='Mace:BAAALgAECgEJAQAAAA==.Madison:BAAALgAECgEJAQAAAA==.Madyorkies:BAAALgAECgkJAQAAAA==.Magdolyn:BAAALgADCgMJAwAAAA==.Mageyboi:BAAALgAECgQJBgABLgAFFAMJDAAcAO8dAA==.Magickul:BAAALgAECgYJDAAAAA==.Magleon:BAAALgADCgIJAgAAAA==.Magonk:BAAALgADCgEJAQAAAA==.Mahano:BAACLgAFFH8HAAIEAAMJ/gzRLwDRAAAEAAMJ/gzRLwDRAAAuAAQKfxcAAgQACAnUGg8fAGwCAAQACAnUGg8fAGwCAAAA.Makis:BAAALgAECgMJBQAAAA==.Malachi:BAAALgAECgYJBwAAAA==.Manavoid:BAABLgAECn8cAAITAAYJkArjpwDVAAATAAYJkArjpwDVAAAAAA==.Mandoanubis:BAAALgADCgcJCgAAAA==.Mandragore:BAAALgAECgIJBAAAAA==.Massili:BAAALgADCgkJGgAAAA==.Mastor:BAAALgADCgQJBwAAAA==.Maynard:BAABLgAECn8hAAIKAAkJ9xErLwC/AQAKAAkJ9xErLwC/AQAAAA==.',
Mc='Mcdouble:BAAALgADCgMJAwAAAA==.',
Me='Meldanis:BAAALgAECgQJBAAAAA==.Meri:BAABLgAECn8cAAIQAAgJlxwrJgAfAgAQAAgJlxwrJgAfAgAAAA==.',
Mi='Miande:BAABLgAECn8VAAInAAcJ0xfLCgCyAQAnAAcJ0xfLCgCyAQAAAA==.Microburst:BAAALgAECgUJBwAAAA==.Minecraft:BAAALgAECgIJAgAAAA==.Minilock:BAABLgAECn85AAMCAAkJoBScBgCIAQACAAkJ4xKcBgCIAQABAAUJDBl1AwAhAQAAAA==.Misogynixy:BAAALgADCgQJBAAAAA==.Missdeeds:BAAALgAECgUJBQAAAA==.Missleading:BAAALgAECgYJCQAAAA==.Missused:BAABLgAECn8XAAIGAAYJkgzbHwC2AAAGAAYJkgzbHwC2AAAAAA==.Mistycat:BAAALgAECgkJDQAAAA==.Mithos:BAAALgAECgUJBwAAAA==.Mithraxa:BAAALgAECgQJBAAAAA==.Miyagifu:BAAALgAECgQJBAAAAA==.',
Mo='Moash:BAAALgADCgkJCQAAAA==.Modsagoodtnk:BAABLgAECn8cAAISAAcJRQ6OBgDdAAASAAcJRQ6OBgDdAAABLgAECggJLwAEAH8ZAA==.Mongermook:BAABLgAECn8iAAMPAAkJ0QvFCwCfAAAPAAkJ0QvFCwCfAAAaAAEJxgFpkQAVAAAAAA==.Monnkysham:BAAALgAECgQJBgABLgAECgYJCQADAAAAAA==.Moogledragon:BAAALgADCgMJAwAAAA==.Mooglefur:BAAALgAECgQJBQAAAA==.Moonbloom:BAABLgAECn8dAAIQAAkJTBxLHwBMAgAQAAkJTBxLHwBMAgAAAA==.Mooseknuhkle:BAAALgAECgEJAQAAAA==.Morgrim:BAAALgAECgIJAwAAAA==.Morlosh:BAAALgAECgMJAwAAAA==.Moryna:BAABLgAECn81AAIXAAkJsQhZJQA9AQAXAAkJsQhZJQA9AQAAAA==.',
Mt='Mthrandir:BAAALgADCgUJBQAAAA==.',
Mu='Muford:BAAALgAECgQJBQABLgAFFAgJFQALAOQfAA==.Mull:BAAALgAECgYJEwAAAA==.Muloc:BAAALgADCgEJAQAAAA==.',
My='Myaka:BAAALgAECgYJBgAAAA==.Mythicc:BAAALgADCgUJCQAAAA==.',
Na='Naatixa:BAAALgAECggJDAAAAA==.Nacronor:BAABLgAECn8UAAIEAAUJEQQ7KgB+AAAEAAUJEQQ7KgB+AAAAAA==.Naiika:BAAALgAECgYJBwAAAA==.Naivaya:BAAALgADCgMJAwAAAA==.Nascha:BAAALgADCgEJAQAAAA==.Nasoj:BAAALgAECgYJCQABLgAECgYJEwADAAAAAA==.',
Ne='Necrasirenea:BAAALgAECggJCAABLgAECgcJCQADAAAAAA==.Necrotic:BAAALgAECgQJBAAAAA==.Nedalla:BAAALgAECgYJDAAAAA==.Neeve:BAAALgAECgMJAwAAAA==.Nekrotik:BAAALgADCgcJBgAAAA==.Neobahamut:BAAALgAECgUJCwABLgAECgcJDgADAAAAAA==.Netharel:BAAALgADCgIJAgAAAA==.Newports:BAAALgAECgEJAQAAAA==.',
Ni='Nichôlasmage:BAAALgAECgYJCwAAAA==.Nickatnite:BAAALgAFFAMJAwAAAA==.Nickelodeon:BAAALgAFFAIJAwAAAA==.Nicksaban:BAABLgAECn8nAAIOAAkJuBuBLgBHAgAOAAkJuBuBLgBHAgAAAA==.Nightgear:BAACLgAFFH8wAAMEAAgJaBcADwDuAQAEAAcJehkADwDuAQARAAIJ/ApJNQBJAAAuAAQKf1kAAwQACQm1IgUIABADAAQACQm1IgUIABADABEABAnfEoAjAJcAAAAA.Nighti:BAAALgADCgIJAQAAAA==.Nightshades:BAAALgADCgQJBAAAAA==.Nilux:BAAALgAECgYJDwAAAA==.Ninetails:BAAALgAECgUJCgAAAA==.Niteshadeth:BAAALgAECgQJBQAAAA==.Niteyknight:BAAALgAECgQJBAAAAA==.Nixeava:BAABLgAECn8dAAImAAkJVQV6VADoAAAmAAkJVQV6VADoAAAAAA==.',
No='Nogooddruid:BAAALgAECgUJDgAAAA==.Nopetsneeded:BAABLgAECn89AAIRAAkJzBRpCAD3AQARAAkJzBRpCAD3AQAAAA==.Norepairbill:BAAALgAECgEJAQABLgAECgkJPQARAMwUAA==.Nostariel:BAAALgAECgQJCgAAAA==.Notadoctor:BAAALgAECgYJCAAAAA==.Noteworthy:BAAALgAECgYJEgABLgAFFAcJEAAHAHYeAA==.',
Nu='Nubuu:BAAALgADCgkJCQAAAA==.',
Ny='Nyctera:BAAALgAFFAEJAQAAAA==.Nysong:BAABLgAECn84AAMBAAgJaQy/EgAfAQABAAgJaQy/EgAfAQACAAMJYwKJGAFPAAAAAA==.',
['Nó']='Nórin:BAAALgAECgUJBQAAAA==.',
Ob='Obali:BAAALgADCgYJCgAAAA==.',
Od='Oddangel:BAAALgAECgYJEwAAAA==.Ode:BAAALgAFFAIJAgAAAA==.Odex:BAACLgAFFH8HAAIiAAQJqQMkIgCXAAAiAAQJqQMkIgCXAAAuAAQKfyoAAyMACQlvDX8IAKgBACMACQlvDX8IAKgBACIAAQmmCE2QADoAAAAA.Odéyemí:BAAALgAECgQJBAAAAA==.',
Oh='Ohblergen:BAAALgAECgIJAgAAAA==.',
Ok='Okragren:BAABLgAECn83AAImAAkJ/A1NMwBvAQAmAAkJ/A1NMwBvAQAAAA==.',
Ol='Olehi:BAAALgADCgcJBwAAAA==.Olynder:BAAALgAECgIJBAAAAA==.',
On='Onos:BAABLgAECn8bAAIEAAcJIyQ4IABEAgAEAAcJIyQ4IABEAgAAAA==.Onto:BAAALgADCgEJAQAAAA==.Ontoquas:BAAALgADCgkJCgAAAA==.',
Or='Orinin:BAAALgAECgUJBQABLgAECgQJCQADAAAAAA==.',
Ou='Outdeath:BAAALgAECgUJBQAAAA==.',
Pa='Paleclaw:BAAALgADCgQJBAAAAA==.Palitroque:BAAALgAECgQJBAAAAA==.Pally:BAAALgAECgUJBQAAAA==.Papasmurfz:BAAALgAFFAEJAQAAAA==.Paramedic:BAABLgAECn8UAAINAAUJAxNICgDlAAANAAUJAxNICgDlAAAAAA==.Pathogen:BAABLgAECn8hAAIHAAkJDR/oOwARAgAHAAkJDR/oOwARAgAAAA==.',
Pe='Penryn:BAAALgAECgQJBwAAAA==.Pepster:BAABLgAECn8bAAIoAAkJtgHgLgCAAAAoAAkJtgHgLgCAAAAAAA==.Persephoknee:BAAALgADCgEJAQAAAA==.Persephoni:BAAALgAECgcJDQAAAA==.',
Pf='Pfchen:BAAALgAECgMJBAAAAA==.',
Pl='Plaguestrip:BAAALgAECgEJAwAAAA==.Plinkerbell:BAAALgAECgMJAwAAAA==.Plumprnickel:BAAALgAECgEJAQAAAA==.Plxkingg:BAAALgADCgUJBQAAAA==.',
Po='Poppit:BAAALgAECgQJBQAAAA==.Porimma:BAABLgAECn8XAAMCAAcJVwZzFQChAAACAAcJVwZzFQChAAABAAIJSgUyEQAXAAAAAA==.Pormas:BAAALgAECgYJDwAAAA==.Poseydon:BAAALgADCgQJBAABLgAECgEJAQADAAAAAA==.',
Pr='Prayerz:BAAALgADCgMJAwAAAA==.Proctology:BAAALgAECgQJBAAAAA==.Prom:BAAALgAECgcJEgAAAA==.Promethèus:BAAALgAECgQJBAAAAA==.Prosby:BAAALgADCgIJAgAAAA==.Prowlnfool:BAAALgADCgUJBQAAAA==.Pryto:BAAALgADCgkJDgABLgAFFAIJAwADAAAAAA==.',
Qu='Queedle:BAABLgAECn8lAAIeAAkJNg49AQAyAQAeAAkJNg49AQAyAQAAAA==.Quickly:BAAALgAECgcJDAAAAA==.',
Ra='Raennis:BAAALgAECgIJAgAAAA==.Ragalstan:BAAALgAECgEJAgAAAA==.Ragnarook:BAAALgAECgEJAQABLgAECgQJCAADAAAAAA==.Rahanumn:BAABLgAECn8YAAIOAAgJ6wktpAAxAQAOAAgJ6wktpAAxAQAAAA==.Rainlette:BAAALgAECggJEgAAAA==.Rainsvoker:BAACLgAFFH8jAAIkAAYJXQ2aEgBqAQAkAAYJXQ2aEgBqAQAuAAQKf1IAAyQACQkOHL4GAJUCACQACQkOHL4GAJUCACIABgk7CAxeAMAAAAAA.Raizak:BAAALgAECgEJAQAAAA==.Ramike:BAAALgAECggJCQAAAA==.Raqtar:BAAALgAECgIJAgABLgAECgkJEgADAAAAAA==.Rasmis:BAAALgAECgIJAwABLgAECgkJEgADAAAAAA==.Ratbreath:BAAALgADCgYJBgAAAA==.Ratrazarke:BAAALgADCgIJAgAAAA==.Razihel:BAAALgADCgYJCQAAAA==.Razzledazzlë:BAAALgAECgEJAQAAAA==.',
Re='Reaver:BAAALgAECgQJBAAAAA==.Reddan:BAABLgAECn8qAAIOAAgJlgzSmwA+AQAOAAgJlgzSmwA+AQAAAA==.Redruth:BAAALgAECgEJAQAAAA==.Renata:BAAALgAFFAIJAgAAAA==.Replicant:BAAALgAECgEJAQAAAA==.Retman:BAAALgAECgMJAQAAAA==.Reverìe:BAAALgAECgcJBwAAAA==.Reylinn:BAAALgAECgQJBAAAAA==.Reyra:BAAALgAECgEJAQABLgAFFAIJAgADAAAAAA==.Reï:BAABLgAECn8iAAIQAAkJsRTZJAAlAgAQAAkJsRTZJAAlAgAAAA==.',
Ri='Ridlei:BAAALgAECgMJBAAAAA==.Rimchester:BAAALgAECgIJAQAAAA==.Rimurutempas:BAAALgAECgEJAQAAAA==.Rinji:BAAALgAECgYJCwAAAA==.Ritzon:BAABLgAECn89AAMZAAkJJSRhBgD4AgAZAAkJJSRhBgD4AgAXAAEJmBdmcQA+AAAAAA==.',
Ro='Rosadita:BAAALgAECgQJBQAAAA==.Roxydan:BAABLgAECn8dAAMBAAgJiQ03KQAdAQACAAgJiQ1KZwCWAQABAAYJ8Ag3KQAdAQAAAA==.',
Ru='Runastalis:BAAALgADCgYJCgAAAA==.Ruwea:BAAALgAECgEJAQAAAA==.',
Ry='Rykken:BAAALgAECgEJAgAAAA==.Ryko:BAABLgAECn8fAAIoAAcJqBSRFwBOAQAoAAcJqBSRFwBOAQAAAA==.',
['Rë']='Rëyra:BAAALgAFFAIJAgAAAA==.',
Sa='Salene:BAAALgAFFAIJAgAAAA==.Sanandume:BAAALgADCgEJAQAAAA==.Sanctess:BAAALgAECggJDgAAAA==.Sankai:BAAALgAECgEJAQABLgAFFAEJAgADAAAAAA==.Saraelle:BAAALgAECgEJAwAAAA==.Sarlas:BAAALgADCgQJBAAAAA==.Sarumanpally:BAAALgAECgYJBwAAAA==.Saruquan:BAAALgAECgkJCQAAAA==.Sayomi:BAAALgADCgcJEwAAAA==.',
Se='Secretjuicy:BAAALgAECgYJCQAAAA==.Senseijundra:BAAALgAECgQJCAAAAA==.Sentinaal:BAAALgADCgcJBwAAAA==.Sethira:BAAALgAECgEJAQABLgAECgYJCgADAAAAAA==.',
Sh='Shabadu:BAAALgADCgQJBAAAAA==.Shadyandi:BAAALgADCgcJCAAAAA==.Shamanhack:BAAALgAFFAIJAwAAAA==.Shan:BAAALgADCgYJBgAAAA==.Sharazad:BAAALgAECggJCQAAAA==.Sheda:BAAALgAECgQJBAAAAA==.Shedia:BAAALgAECgEJAQAAAA==.Shmoove:BAEALgAECgUJBgAAAA==.Shmooves:BAEALgAECgQJBAABLgAECgUJBgADAAAAAA==.Shoukei:BAAALgADCgIJAwAAAA==.',
Si='Sianna:BAAALgADCgYJBgAAAA==.Sieya:BAAALgADCgUJBQAAAA==.Siinful:BAAALgAECgEJAQAAAA==.Simbruh:BAAALgADCgMJAwAAAA==.Simpari:BAABLgAFFH8HAAIHAAIJ8QgWYACIAAAHAAIJ8QgWYACIAAABLgAFFAYJHAAGAF8NAA==.Sinarria:BAAALgAECgEJAQAAAA==.Sithra:BAAALgADCgEJAQAAAA==.',
Sk='Skeemer:BAAALgAECgUJBQAAAA==.Skeetro:BAAALgAECgEJAQAAAA==.Skips:BAAALgAECgQJCQAAAA==.Skullace:BAABLgAECn8qAAIBAAkJuw9GCgChAQABAAkJuw9GCgChAQAAAA==.Skullhead:BAAALgADCgEJAQAAAA==.Skybreaker:BAAALgAECgkJCAAAAA==.Skylette:BAAALgAECgcJCQAAAA==.',
Sm='Smashurfacen:BAAALgADCgcJFAAAAA==.',
Sn='Snitbit:BAAALgADCgkJGgAAAA==.Sno:BAAALgADCgEJAQABLgAECgUJBwADAAAAAA==.Snoopingas:BAAALgAECgEJAQAAAA==.Snpcrklpopu:BAAALgADCgYJCAAAAA==.',
So='Solarana:BAAALgAECgkJCQAAAA==.Sortiebatoru:BAAALgAECgIJAwAAAA==.Sotzi:BAAALgADCggJEQAAAA==.Souldune:BAAALgAECgYJBgAAAA==.',
Sp='Sparkplugg:BAAALgAECgEJAQAAAA==.Sparthos:BAAALgAECgIJAgAAAA==.',
Sr='Srfreaky:BAABLgAECn8UAAIYAAUJ1xvbBAAUAQAYAAUJ1xvbBAAUAQAAAA==.',
St='Sterlìng:BAAALgAECgUJCQAAAA==.Stevejabbs:BAABLgAECn8iAAMKAAYJgSQXAwAmAgAKAAYJgSQXAwAmAgALAAMJ5SAEOQAYAQAAAA==.Stormcunning:BAABLgAECn8WAAImAAYJCAxiTAAWAQAmAAYJCAxiTAAWAQAAAA==.Stormfire:BAAALgADCgcJBwAAAA==.Stormßringer:BAABLgAECn8UAAImAAgJERDXMwCJAQAmAAgJERDXMwCJAQAAAA==.Stownr:BAAALgAECgYJBgAAAA==.Strip:BAAALgAECgEJAQAAAA==.Strongclaw:BAAALgADCgUJBQAAAA==.Stumpyborg:BAABLgAECn8VAAQBAAcJaAY9MgBVAAACAAYJNgSn3gCdAAABAAIJMws9MgBVAAAnAAEJhAcZQwArAAABLgAECgkJFwAIAN0LAA==.Stónéhëárt:BAAALgADCgYJBwABLgAECgkJEQADAAAAAA==.',
Su='Subdue:BAAALgADCgQJBAAAAA==.Subverse:BAAALgAECgQJBAAAAA==.Sukimyheelz:BAAALgAECgQJBAAAAA==.Sundance:BAAALgAECgcJDgAAAA==.Sune:BAABLgAECn8gAAMNAAYJxgvZRwDwAAANAAYJxgvZRwDwAAAgAAEJNwk2ggAqAAAAAA==.Supplicant:BAAALgADCgQJBwAAAA==.',
Sv='Svellulfr:BAAALgAECgEJAQAAAA==.Svuca:BAAALgADCgcJBwAAAA==.',
Sy='Sydneyweenie:BAAALgADCgcJCAAAAA==.Syldi:BAAALgAECgEJAQABLgAECgcJJAAWACsbAA==.Sythis:BAAALgAECgIJAwAAAA==.',
['Sä']='Sästa:BAAALgADCgkJCQAAAA==.',
['Sö']='Sörren:BAABLgAECn8nAAInAAcJYwZEBgC6AAAnAAcJYwZEBgC6AAAAAA==.',
Ta='Tacosdeasada:BAAALgAECgEJAQAAAA==.Taitertot:BAAALgADCgQJBQAAAA==.Tanelórn:BAAALgAECgQJBQAAAA==.Tanlon:BAAALgAECggJEgAAAA==.Taykorra:BAAALgADCggJDQAAAA==.',
Te='Telandril:BAABLgAECn8vAAIQAAkJvxH4MwDNAQAQAAkJvxH4MwDNAQAAAA==.Telphin:BAAALgAECgYJDAAAAA==.Tempestira:BAAALgAECgEJAgAAAA==.Tensuken:BAABLgAECn8ZAAIOAAYJpBidsAAeAQAOAAYJpBidsAAeAQAAAA==.Testarossaa:BAAALgADCgEJAQAAAA==.Teylonna:BAAALgAECgEJAQAAAA==.',
Th='Thadgun:BAAALgADCgkJFQAAAA==.Thadium:BAAALgAECgMJAwAAAA==.Thalgan:BAAALgAECgEJAQAAAA==.Thalyn:BAAALgAECgEJAQAAAA==.Thauríel:BAAALgAECgEJAQAAAA==.Thecword:BAAALgADCgYJBgAAAA==.Themedic:BAABLgAECn8gAAMbAAcJoRduCAB+AQAbAAcJoRduCAB+AQAmAAEJ6gFuxAAXAAAAAA==.Theremar:BAAALgAECgMJAwAAAA==.Thergothon:BAAALgAECgEJAQABLgAECgMJAwADAAAAAA==.Theunclepaul:BAAALgAECgUJBQAAAA==.Thisisdrexx:BAAALgAECgIJAwAAAA==.Thorwrath:BAAALgADCgEJAgAAAA==.Thrazoro:BAAALgAECgQJBAAAAA==.Thrazzoro:BAAALgAECgYJEwAAAA==.Thrægg:BAAALgAECgYJCQABLgAECgYJIgAKAIEkAA==.',
Ti='Tiarl:BAACLgAFFH8KAAIWAAMJohKvDgCsAAAWAAMJohKvDgCsAAAuAAQKfzUAAhYACQkdF6ERAFQCABYACQkdF6ERAFQCAAAA.Tiia:BAAALgADCgIJAgAAAA==.Timex:BAABLgAECn8XAAMjAAYJRCD5DgDrAQAjAAYJRCD5DgDrAQAiAAEJUhdnjgA+AAAAAA==.Tinydots:BAAALgAECgIJAgAAAA==.Tinypaws:BAAALgAECgQJBAAAAA==.Tinysitril:BAAALgAECgYJCQABLgAFFAQJCwAdAJcPAA==.Tinysohei:BAAALgAECgQJBAAAAA==.Titañick:BAAALgAFFAIJAgAAAA==.',
To='Tom:BAABLgAECn8aAAMiAAYJLgvvVgDWAAAiAAYJLgvvVgDWAAAjAAEJZQhLJwAvAAAAAA==.Toosxyfohair:BAABLgAECn8iAAIbAAgJTBmvCQBfAQAbAAgJTBmvCQBfAQAAAA==.',
Tr='Trainwrekk:BAAALgADCgYJBgAAAA==.Tranqar:BAAALgAECgQJBgAAAA==.Tresg:BAAALgAECgYJCQAAAA==.Trissandra:BAAALgAECgEJAQAAAA==.Trolltoll:BAAALgADCgEJAwAAAA==.Trüth:BAAALgADCggJEAAAAA==.',
Tw='Twentytwo:BAAALgAECgUJBQAAAA==.Twylidan:BAEALgAECgkJCgABLgAFFAQJDAAiAOkeAA==.',
Ty='Tyrannt:BAAALgAECgEJAQAAAA==.Tyrannus:BAAALgADCgcJCgAAAA==.Tyregar:BAAALgAECgEJAQAAAA==.Tyrànda:BAAALgAECgUJCwAAAA==.Tyzy:BAAALgAECgEJAgAAAA==.',
['Tö']='Tötém:BAAALgAECgEJAQAAAA==.',
Ul='Ulanhi:BAABLgAECn8VAAIVAAUJzh31EACdAQAVAAUJzh31EACdAQAAAA==.',
Un='Undeadjelly:BAABLgAECn8VAAMHAAcJsB7oZgCZAQAHAAYJ6B/oZgCZAQAJAAYJehiLFgAkAQAAAA==.Unholy:BAAALgAECgYJDwAAAA==.',
Ur='Urkzul:BAAALgADCgMJAwAAAA==.Ursoth:BAAALgADCgUJCgAAAA==.',
Ut='Uthèrsmight:BAAALgAECgYJBgAAAA==.Uti:BAAALgADCgUJBQAAAA==.',
Uu='Uubs:BAAALgADCgEJAQABLgAFFAMJCgAOAJoSAA==.',
Va='Valakk:BAAALgAECgYJCQAAAA==.Vallak:BAAALgADCgIJBAAAAA==.Valsitril:BAAALgAECgYJEAABLgAFFAQJCwAdAJcPAA==.Valthaczar:BAAALgAECgMJBgAAAA==.Vanara:BAAALgAECgEJAgAAAA==.Varadun:BAAALgAFFAIJAwAAAA==.Varrosh:BAAALgADCgYJBgAAAA==.Vathan:BAAALgAECgQJBQAAAA==.',
Ve='Velmora:BAAALgAECgkJCQAAAA==.Velsetin:BAABLgAECn8dAAIGAAcJTBsyTABSAgAGAAcJTBsyTABSAgABLgAFFAMJBQAaAMcUAA==.Verathina:BAAALgADCgEJAgAAAA==.Versed:BAAALgADCgUJBQABLgAECgQJBAADAAAAAA==.Veryspooky:BAABLgAECn8eAAICAAgJZBsHOAD5AQACAAgJZBsHOAD5AQAAAA==.Vexian:BAABLgAECn8fAAMmAAkJJh3EAgD7AQAmAAkJJh3EAgD7AQAbAAEJ3B/FtwBcAAAAAA==.Vexlock:BAAALgAECgMJAwABLgAECgkJHwAmACYdAA==.',
Vf='Vfl:BAAALgADCgcJBwAAAA==.',
Vi='Vicas:BAAALgAECgcJEgAAAA==.',
Vl='Vladdek:BAAALgAFFAEJAwAAAA==.Vladdok:BAAALgAECgUJBQAAAA==.Vladok:BAAALgAECgQJCwAAAA==.Vladokk:BAAALgAECgMJAwAAAA==.',
Vo='Voidofdeath:BAAALgADCgQJBAAAAA==.Voidshiekah:BAAALgADCgEJAQAAAA==.Vorteia:BAAALgADCgYJBgAAAA==.',
['Vé']='Véngéánçé:BAAALgAECgMJBAAAAA==.',
Wa='Wald:BAAALgAECgYJEAAAAA==.Warmongerr:BAAALgADCgIJAgAAAA==.Waruh:BAAALgADCgcJCQAAAA==.',
We='Webgar:BAAALgAECgEJAQAAAA==.Webrune:BAAALgAECgMJAwAAAA==.',
Wh='Whisperlia:BAAALgAECgQJCAAAAA==.Whisperwindd:BAAALgAECgYJDAAAAA==.White:BAABLgAFFH8JAAMnAAMJcBVgCACIAAACAAIJIxjHOgCYAAAnAAIJRgxgCACIAAAAAA==.Whitetoothe:BAABLgAECn84AAIEAAcJxRadVgCgAQAEAAcJxRadVgCgAQAAAA==.',
Wi='Witemandown:BAAALgADCgcJCAAAAA==.Witherbear:BAAALgAECgEJAQAAAA==.Witherhoard:BAAALgADCgEJAQAAAA==.Wizzy:BAAALgADCgEJAQAAAA==.',
Wo='Workin:BAAALgADCgEJAQABLgAECggJIgAQAEIXAA==.',
['Wå']='Wånheda:BAAALgAECggJEwAAAA==.',
Xa='Xaniana:BAAALgAECgkJEAAAAA==.Xaosin:BAAALgADCgUJBQAAAA==.',
Xe='Xenzak:BAAALgAECgEJAQAAAA==.Xephir:BAAALgADCgMJAwAAAA==.Xerxës:BAAALgAECgEJAQAAAA==.',
Xl='Xl:BAAALgAECgQJCwAAAA==.',
Xo='Xoito:BAAALgAECgEJAQABLgAFFAEJAQADAAAAAA==.Xotiko:BAAALgAECgYJDAAAAA==.',
Xu='Xubris:BAAALgADCgYJCQAAAA==.',
['Xâ']='Xâxâs:BAAALgAECgMJAwABLgAECggJGwAiAHQFAA==.',
Ya='Yaerin:BAACLgAFFH8ZAAIgAAQJcCMSGwCLAQAgAAQJcCMSGwCLAQAuAAQKfyYAAiAACQnnI/MDAFsDACAACQnnI/MDAFsDAAAA.Yaoi:BAAALgAFFAIJAgAAAA==.',
Yu='Yunarä:BAAALgAECgYJCAAAAA==.Yuukon:BAABLgAECn8bAAQUAAgJtxfwHABxAQAUAAgJtxfwHABxAQAHAAQJ5gOZOQFkAAAJAAEJDwgrGAAvAAAAAA==.',
Za='Zakuul:BAAALgADCgQJBAAAAA==.Zalezaar:BAAALgAECgIJAgAAAA==.Zangetsu:BAAALgAECgcJBwAAAA==.Zarusthra:BAAALgAECgEJAQAAAA==.Zaxie:BAABLgAECn8/AAITAAkJrh1TAgBOAgATAAkJrh1TAgBOAgAAAA==.',
Ze='Zenjuice:BAAALgAECgcJAgAAAA==.Zenwu:BAAALgADCgkJGwAAAA==.Zephrylia:BAAALgAECgUJCQAAAA==.Zerama:BAAALgAECgUJBQAAAA==.',
Zh='Zheratul:BAAALgAECgEJAQAAAA==.Zhirl:BAAALgAECgkJCQAAAA==.Zhivet:BAAALgAECgYJBwAAAA==.',
Zi='Zilphia:BAABLgAECn8lAAIGAAkJJRA2CAC0AQAGAAkJJRA2CAC0AQAAAA==.',
Zu='Zuriel:BAAALgAECgIJAgAAAA==.',
Zy='Zyku:BAAALgAECgEJAQAAAA==.Zylphie:BAAALgADCgcJBwAAAA==.',
['Àm']='Àmagezing:BAAALgAFFAIJAgABLgAFFAYJGwAOACweAA==.',
['Åj']='Åj:BAAALgADCgcJBwAAAA==.',
['Åp']='Åpexx:BAABLgAECn8cAAMTAAYJKAYEHACCAAATAAYJCAYEHACCAAAdAAEJzAYcfQAjAAAAAA==.',
['Çw']='Çwÿbàbý:BAAALgAECgYJDwAAAA==.',
['Ór']='Órión:BAABLgAECn8VAAIEAAYJ1BLuoQD+AAAEAAYJ1BLuoQD+AAAAAA==.',
['Ös']='Östara:BAABLgAECn8iAAIQAAgJQhdHLQDyAQAQAAgJQhdHLQDyAQAAAA==.',
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
