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

local lookup = {'Warlock-Destruction','Warlock-Demonology','DemonHunter-Havoc','DemonHunter-Vengeance','Unknown-Unknown','Hunter-BeastMastery','Mage-Arcane','Mage-Frost','DeathKnight-Unholy','Hunter-Survival','DeathKnight-Frost','Monk-Mistweaver','Monk-Brewmaster','Monk-Windwalker','Priest-Shadow','Paladin-Retribution','Druid-Guardian','Druid-Restoration','Hunter-Marksmanship','Paladin-Protection','DemonHunter-Devourer','DeathKnight-Blood','Druid-Feral','Priest-Holy','Warrior-Protection','Warrior-Arms','Warrior-Fury','Druid-Balance','Shaman-Restoration','Rogue-Subtlety','Rogue-Outlaw','Rogue-Assassination','Priest-Discipline','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Paladin-Holy','Shaman-Elemental','Warlock-Affliction','Shaman-Enhancement',}
local provider = {region='US',realm='Azuremyst',name='US',type='weekly',zone=46,date='2026-08-11',data={Aa='Aaravos:BAABLgAECn8kAAMBAAkJhhrRBwDUAQABAAkJiBfRBwDUAQACAAUJcxdNDgAdAQAAAA==.Aardia:BAAALgAECgUJBwAAAA==.Aarynae:BAABLgAECn8XAAMDAAkJHRppAgBWAgADAAkJShlpAgBWAgAEAAQJIxs8AwA3AQAAAA==.',
Ab='Abysseon:BAAALgAECgUJDgABLgAECgQJCAAFAAAAAA==.',
Ac='Accretion:BAAALgAECgYJBgAAAA==.',
Ad='Adaria:BAABLgAECn8WAAIGAAcJWAWSZQA3AQAGAAcJWAWSZQA3AQAAAA==.Addath:BAAALgADCgYJBgAAAA==.Adrillbear:BAAALgAFFAEJAQAAAA==.Adura:BAAALgAECggJCgAAAA==.',
Ae='Aeirith:BAACLgAFFH8OAAIHAAQJ5hRoAQAjAQAHAAQJ5hRoAQAjAQAuAAQKfyQAAwcACQmwHegBAGYCAAcACQmwHegBAGYCAAgAAQlFChlgATEAAAAA.Aelion:BAAALgAECgEJAQAAAA==.',
Ah='Ahheevoker:BAAALgAECgYJEgAAAA==.',
Ai='Ailsà:BAAALgADCgEJAQAAAA==.',
Ak='Akarias:BAAALgAECgEJAQABLgAECgcJBwAFAAAAAA==.',
Al='Aladaria:BAAALgAECgMJAwAAAA==.Alannon:BAAALgADCgEJAQAAAA==.Aldyah:BAAALgAFFAMJAwAAAA==.Alias:BAAALgAECgYJBQAAAA==.Alistair:BAAALgAECgEJAwAAAA==.Allanonn:BAAALgAECgQJBAAAAA==.Alohomora:BAAALgAECgUJEAAAAA==.Alprazolam:BAAALgAECgEJAQAAAA==.Alvist:BAABLgAECn8UAAIJAAQJrx6gggBeAQAJAAQJrx6gggBeAQAAAA==.',
Am='Amarasu:BAABLgAECn8cAAIKAAkJig+RGwDBAQAKAAkJig+RGwDBAQAAAA==.Amarlly:BAABLgAECn8zAAILAAkJJhngBwAVAgALAAkJJhngBwAVAgAAAA==.Amenedil:BAAALgAECgUJDAAAAA==.',
An='Anakiddo:BAAALgAECgEJAQAAAA==.Anbrew:BAABLgAECn8UAAQMAAcJdxJoSwA/AQAMAAYJDBJoSwA/AQANAAUJjA6FQAD4AAAOAAEJMwe0rwAlAAABLgAFFAcJEAAJAHYeAA==.Ancelina:BAABLgAECn8qAAIPAAkJeyR3AgBCAwAPAAkJeyR3AgBCAwAAAA==.Anderton:BAABLgAECn9CAAIQAAkJOxsFBgBHAgAQAAkJOxsFBgBHAgAAAA==.Andilocks:BAAALgADCgMJAwAAAA==.Anditracks:BAAALgADCgEJAQAAAA==.Andraenei:BAAALgADCgcJDAAAAA==.Andrela:BAAALgAECggJDAAAAA==.Andromadda:BAAALgADCggJCAAAAA==.Aneira:BAABLgAECn8sAAMRAAkJoBB8BACEAQARAAkJoBB8BACEAQASAAMJYQySmQB/AAAAAA==.Annovera:BAAALgAECgMJBgAAAA==.Anyi:BAAALgAECgEJAQAAAA==.',
Ap='Apexxd:BAAALgAECgUJBQAAAA==.Applefritter:BAAALgAECgUJCAABLgAECgkJKAAPAJYbAA==.',
Ar='Araga:BAAALgAECgEJAQAAAA==.Archérhiro:BAACLgAFFH8oAAMGAAkJ8BXHCAAyAgAGAAgJWxjHCAAyAgATAAMJRwTfIQCHAAAuAAQKfyoAAwYACQmGH+0YAJECAAYACQl6H+0YAJECABMACAkrGdobAEoCAAAA.Arilias:BAAALgAECgEJAQABLgAECgkJTAAGAK4gAA==.Arillann:BAABLgAECn89AAIUAAkJUR+3BACuAgAUAAkJUR+3BACuAgAAAA==.Arrook:BAAALgAECgMJAwAAAA==.Arrtonomis:BAAALgAECgUJCAABLgAECgkJEgAFAAAAAA==.Artdemsamis:BAAALgAECgkJEgAAAA==.Arte:BAABLgAECn89AAIGAAkJaxOnLAABAgAGAAkJaxOnLAABAgAAAA==.Arthundermis:BAAALgAECgkJEQABLgAECgkJEgAFAAAAAA==.Artlunarmis:BAAALgADCgEJAQABLgAECgkJEgAFAAAAAA==.Arvena:BAABLgAECn8nAAIVAAkJVgoWdAA5AQAVAAkJVgoWdAA5AQAAAA==.',
As='Asclëpius:BAAALgADCgcJBgABLgAECgEJAQAFAAAAAA==.Asheron:BAAALgAECgYJCAAAAA==.Ashylock:BAAALgAECgEJAQABLgAFFAUJEAAIAGAWAA==.Ashymage:BAACLgAFFH8QAAIIAAUJYBabYAAgAQAIAAUJYBabYAAgAQAuAAQKfzcAAggACQlYHLYpAMwCAAgACQlYHLYpAMwCAAAA.Askevar:BAABLgAECn8wAAMJAAkJTwzTDQBZAQAJAAkJnwvTDQBZAQAWAAYJ5wlHJwAEAQAAAA==.Aspect:BAAALgADCgEJAQABLgAFFAIJAwAFAAAAAA==.Asriél:BAAALgAECgYJEwABLgAECgkJJAASALEUAA==.Astor:BAAALgADCgMJBQAAAA==.Astrona:BAAALgADCgkJFwAAAA==.',
At='Atlassian:BAAALgAECgEJAQAAAA==.Atreus:BAABLgAECn8YAAIQAAkJbAXUwQAGAQAQAAkJbAXUwQAGAQAAAA==.Attalaguy:BAAALgAECgYJDgAAAA==.',
Au='Audra:BAAALgADCgcJDgAAAA==.',
Av='Avabeatrix:BAAALgADCgEJAQAAAA==.Avinthoro:BAAALgADCgIJAgAAAA==.',
Ay='Ayyayyron:BAAALgAECgUJCQAAAA==.',
Az='Azaleah:BAABLgAECn9MAAIQAAkJRx3xGQCoAgAQAAkJRx3xGQCoAgAAAA==.Azanoth:BAAALgADCgIJAgAAAA==.Azraesha:BAABLgAECn8rAAIVAAkJ/BUDKgAhAgAVAAkJ/BUDKgAhAgAAAA==.Azureflamez:BAAALgAECgEJAQAAAA==.Azurewraith:BAAALgAECgQJBAAAAA==.Azzul:BAAALgADCgcJBwAAAA==.',
Ba='Backy:BAABLgAECn8kAAIXAAkJOxokAQBbAgAXAAkJOxokAQBbAgAAAA==.Baiken:BAAALgAECgIJAgABLgAECgQJCAAFAAAAAA==.Banjoman:BAABLgAECn8kAAIYAAcJXSTpCgC4AgAYAAcJXSTpCgC4AgAAAA==.Baza:BAAALgADCgYJBgAAAA==.Baýlei:BAABLgAECn8WAAIMAAYJ5A0kWwAHAQAMAAYJ5A0kWwAHAQAAAA==.',
Be='Beareold:BAAALgAECgQJBAAAAA==.Beary:BAAALgAECgQJCAAAAA==.Bebide:BAAALgAECgEJAQABLgAECgcJCQAFAAAAAA==.Beenaughty:BAAALgAECgEJAQABLgAECgEJAQAFAAAAAA==.Belaanna:BAAALgADCgYJCQAAAA==.Beliria:BAAALgADCgUJBgAAAA==.Benimaru:BAAALgAECgUJDwAAAA==.Beriko:BAAALgAECgMJAwAAAA==.Bernat:BAAALgAECgEJAQAAAA==.Beàrdfáce:BAAALgADCgQJBAAAAA==.',
Bi='Bigblunt:BAAALgAECgEJAQAAAA==.Bigjuicy:BAABLgAECn8ZAAQZAAkJchhbBgATAQAZAAYJCRVbBgATAQAaAAUJVRn7CwCrAAAbAAUJBhWTFACoAAAAAA==.Billie:BAAALgAECgcJDgAAAA==.Bimboficate:BAAALgADCgYJBwAAAA==.',
Bl='Black:BAAALgAFFAEJAQAAAA==.Blackadder:BAABLgAECn8tAAIUAAkJ5A2dBABhAQAUAAkJ5A2dBABhAQAAAA==.Blondie:BAAALgADCgQJBAABLgAECgYJEwAFAAAAAA==.Bloodie:BAAALgAECgMJAwAAAA==.Blue:BAABLgAECn88AAIOAAkJxRvlDgBbAgAOAAkJxRvlDgBbAgAAAA==.Blueguy:BAAALgAECgQJBgAAAA==.Bluestreak:BAAALgAECgEJAwABLgAECgcJCQAFAAAAAA==.',
Bo='Bobthefist:BAAALgADCgcJBwAAAA==.Bode:BAAALgAECgYJEwAAAA==.Bogern:BAAALgADCgcJBwAAAA==.Bolau:BAAALgADCgYJBwAAAA==.Boltz:BAAALgADCgYJBgAAAA==.Boogy:BAAALgAFFAEJAQAAAA==.Bopdiz:BAAALgAECgEJAQABLgAECgQJFAAJAK8eAA==.Borledish:BAAALgAECgMJBAABLgAECgQJFAAJAK8eAA==.Bottosai:BAAALgAECgEJAgAAAA==.',
Br='Brambles:BAAALgAECgEJAQAAAA==.Branwynn:BAAALgAECgcJEgAAAA==.Breezyfight:BAAALgAFFAIJAgAAAA==.Breezyrocks:BAAALgADCgQJCQAAAA==.Breezysha:BAAALgADCgcJCAAAAA==.Brenz:BAABLgAFFH8GAAMQAAMJOQIKqgBuAAAQAAMJOwEKqgBuAAAUAAEJvQR6HAAhAAAAAA==.Brewdaddy:BAAALgAECgUJEwABLgAECgkJOwAUAHwRAA==.Brewdude:BAAALgAECgEJAQAAAA==.Brigor:BAAALgAECgYJEAAAAA==.Brokenblade:BAAALgADCgYJBgAAAA==.Brotherblood:BAAALgAECgYJDAAAAA==.',
Bu='Bulldoza:BAAALgAECgQJBQAAAA==.Bullwankle:BAAALgAECgMJAwAAAA==.Bullwinkles:BAAALgAECgEJAQAAAA==.Bullwrinkle:BAAALgADCgcJBwAAAA==.Bunbot:BAAALgAECgEJAQAAAA==.Butterknifeo:BAABLgAFFH8FAAIcAAMJxxSHMQC7AAAcAAMJxxSHMQC7AAAAAA==.',
By='Byryja:BAABLgAECn8pAAIIAAcJbAkkJADJAAAIAAcJbAkkJADJAAAAAA==.',
Ca='Cabela:BAABLgAECn8XAAIKAAkJvhEuAgDuAQAKAAkJvhEuAgDuAQAAAA==.Cahrazie:BAACLgAFFH8GAAIQAAMJ9wkqewDAAAAQAAMJ9wkqewDAAAAuAAQKfx0AAhAACQkaFbZIAOwBABAACQkaFbZIAOwBAAAA.Caidinn:BAAALgAECgkJEQAAAA==.Caitrîn:BAAALgADCgkJCQABLgAECgkJLAARAKAQAA==.Calissancia:BAABLgAECn82AAIMAAgJNBdEHwAgAgAMAAgJNBdEHwAgAgAAAA==.Calkey:BAABLgAECn8WAAIBAAYJUQgMHwCyAAABAAYJUQgMHwCyAAAAAA==.Calliaa:BAAALgADCgEJAQABLgADCgcJDQAFAAAAAA==.Callmemommy:BAAALgADCgYJBgAAAA==.Carnelia:BAAALgAECgEJAgAAAA==.Carvana:BAAALgAECgkJBwAAAA==.Catalyst:BAAALgADCgMJAwAAAA==.Cathandris:BAAALgADCgEJAQAAAA==.Catovia:BAAALgAECgYJBwAAAA==.',
Ce='Ceri:BAAALgAECgkJBwAAAA==.Ceska:BAAALgADCgEJAQAAAA==.',
Ch='Chadarack:BAAALgAECgYJBwAAAA==.Chadaracks:BAAALgAECgEJAQAAAA==.Chancy:BAAALgAECgMJBQAAAA==.Channingtotm:BAACLgAFFH8vAAIdAAUJ7iWBBgD1AQAdAAUJ7iWBBgD1AQAuAAQKfzsAAh0ACQlhIY4EAG4DAB0ACQlhIY4EAG4DAAAA.Chantix:BAAALgADCgUJBQAAAA==.Charlemoo:BAAALgAECgEJAQABLgAECgMJAwAFAAAAAA==.Cheekymonkey:BAABLgAECn8qAAIHAAkJMQ2EBQB+AQAHAAkJMQ2EBQB+AQAAAA==.Chrispbacon:BAAALgAECgUJEgAAAA==.Chueyé:BAAALgAECgQJBAABLgAFFAMJDAAeAO8dAA==.Chune:BAAALgAECgkJDQAAAA==.Chunkyy:BAAALgADCgYJBgAAAA==.Churros:BAABLgAECn8oAAMPAAkJlhuVEQBJAgAPAAkJlhuVEQBJAgAYAAcJThV3JwCKAQAAAA==.',
Ci='Cincog:BAAALgAECgQJBAABLgAECgYJCQAFAAAAAA==.',
Cl='Closetcookie:BAAALgAECgQJBAAAAA==.Cloudy:BAAALgADCgIJAgABLgAECgMJAwAFAAAAAA==.',
Co='Coberren:BAAALgAECgEJAQAAAA==.Coldhands:BAAALgAECgIJAgAAAA==.Cordialkylie:BAAALgAECgIJAgAAAA==.Cowcrusader:BAAALgADCgcJBwAAAA==.',
Cr='Crazyugly:BAAALgAECgQJBQAAAA==.Crogrer:BAAALgAECgMJAwAAAA==.Crosslock:BAAALgAECgUJEAAAAA==.',
Cu='Cuppycakes:BAAALgADCgcJFAAAAA==.',
Cy='Cynnari:BAAALgAECggJDwAAAA==.',
Da='Daddysecret:BAAALgAECgQJBQAAAA==.Dalan:BAAALgAECgIJAgABLgAFFAQJDgAHAOYUAA==.Dalaris:BAACLgAFFH8LAAIDAAQJlw/iDQDPAAADAAQJlw/iDQDPAAAuAAQKfyIAAgMACQmdFiASAAoCAAMACQmdFiASAAoCAAAA.Danizmi:BAAALgADCgQJBAAAAA==.Dano:BAAALgADCgYJDQAAAA==.Darci:BAAALgAECgYJCwAAAA==.Darkeon:BAAALgAECgcJCwAAAA==.Darkpriestes:BAAALgAECgQJBAAAAA==.Darlenedark:BAAALgAECgEJAQAAAA==.Darling:BAAALgAECgIJAgAAAA==.Darron:BAAALgAECgIJBAABLgAECggJEgAFAAAAAA==.Darrosh:BAABLgAECn8bAAQfAAgJuxOEEgDhAAAfAAYJDhCEEgDhAAAeAAcJjQ34PgDLAAAgAAMJ9hB8FAC1AAAAAA==.Dartian:BAAALgADCgcJDQABLgAECgkJTAAGAK4gAA==.Daylightt:BAAALgAECgIJAgAAAA==.Dazblood:BAAALgAECgIJAgAAAA==.Dazdot:BAAALgADCgQJBAABLgAECgIJAgAFAAAAAA==.Dazsham:BAAALgAECgEJAQABLgAECgIJAgAFAAAAAA==.',
De='Deadjuicy:BAAALgAECggJCQAAAA==.Deathdevil:BAAALgAECgUJBQAAAA==.Deathlurker:BAAALgADCgQJBAAAAA==.Deathmare:BAAALgAECgUJBQAAAA==.Deathmommy:BAAALgAECgcJCAAAAA==.Deathty:BAAALgAECgMJCgABLgAFFAEJAgAFAAAAAA==.Dementia:BAAALgADCgMJAwAAAA==.Design:BAABLgAECn8lAAICAAkJ4Rc7MgAPAgACAAkJ4Rc7MgAPAgAAAA==.Desmeridian:BAAALgAECgUJBQAAAA==.Dethendrova:BAAALgADCgYJBgABLgAFFAMJDAAGABwYAA==.Devotee:BAAALgADCgIJAgAAAA==.',
Dh='Dhish:BAABLgAECn8dAAQcAAcJBgkZEADBAAAcAAcJBgkZEADBAAAXAAMJMwdTPABoAAASAAIJ6gIc1AAxAAAAAA==.',
Di='Diltlish:BAAALgAECgUJCgAAAA==.Diocles:BAAALgAECgUJBgAAAA==.Disconcern:BAAALgAECgMJAwAAAA==.Discontent:BAACLgAFFH8GAAIaAAIJUR2wMwCNAAAaAAIJUR2wMwCNAAAuAAQKfxQAAxoABwnwHKQQAOkBABoABwnwHKQQAOkBABsABQknEVxuAP0AAAAA.Discordiä:BAABLgAECn8XAAIhAAgJHRf9HQDeAQAhAAgJHRf9HQDeAQAAAA==.Discspal:BAAALgAECgYJBwAAAA==.Diåblo:BAAALgADCgUJBQAAAA==.',
Dm='Dmginc:BAAALgAECgYJCwAAAA==.',
Do='Doeblin:BAABLgAECn8SAAIGAAUJ0B5heABPAQAGAAUJ0B5heABPAQAAAA==.Domidouse:BAAALgAECgYJDwAAAA==.Domivyr:BAAALgAECgEJAwAAAA==.Donkedixon:BAAALgADCgYJBgAAAA==.Dosar:BAAALgADCgIJAgAAAA==.Doubledeuces:BAAALgADCgIJAgAAAA==.Doubtz:BAAALgAECgQJBQABLgAECgQJFAAJAK8eAA==.',
Dp='Dpalx:BAAALgAECgQJBAAAAA==.Dpxs:BAABLgAFFH8HAAIdAAQJkha7PwDmAAAdAAQJkha7PwDmAAAAAA==.',
Dr='Dracaria:BAAALgAECgEJAQAAAA==.Dracones:BAAALgAECgYJDgAAAA==.Dragondz:BAAALgAECgUJBQAAAA==.Dragonflai:BAABLgAECn8nAAIIAAkJnBdCUwDjAQAIAAkJnBdCUwDjAQAAAA==.Dragonkin:BAAALgAECgQJCAAAAA==.Drakkari:BAABLgAECn8lAAMEAAcJLQ93AwAqAQAEAAcJLQ93AwAqAQAVAAYJUwjUIQCFAAAAAA==.Drakkei:BAACLgAFFH8FAAIGAAIJahPzTgCFAAAGAAIJahPzTgCFAAAuAAQKf1sAAwYACQn3Gy4IAAcCAAYACQn3Gy4IAAcCAAoAAwkiBr9JAJIAAAAA.Drawbridge:BAAALgAECgEJAQAAAA==.Drerane:BAAALgADCgYJBgAAAA==.Drexxsster:BAAALgADCgQJBAAAAA==.Drshortbus:BAAALgAECgUJCgAAAA==.Drumitus:BAAALgADCgYJCAAAAA==.Drunkngrundl:BAABLgAECn89AAINAAkJHiMoBAAGAwANAAkJHiMoBAAGAwAAAA==.Drylo:BAECLgAFFH8MAAMiAAQJ6R51IABcAQAiAAQJ6R51IABcAQAjAAEJFB6GBwBHAAAuAAQKfy0AAyIACQkmII4JAL8CACIACQmLHo4JAL8CACMACAnFH6UGAIgCAAAA.',
Du='Duckeey:BAAALgAFFAIJBAABLgAFFAMJDAAJAJcMAA==.Dunstir:BAABLgAECn8ZAAIQAAgJ6QUgwAAIAQAQAAgJ6QUgwAAIAQAAAA==.Dusktrekker:BAAALgAECgkJBwAAAA==.',
Dy='Dypshyt:BAABLgAECn8aAAQiAAkJhxfkTwDvAAAjAAUJUBJRIgAYAQAiAAYJqxDkTwDvAAAkAAUJTgemLgB1AAAAAA==.Dyyke:BAAALgAECgEJAQAAAA==.',
Ed='Edelweíss:BAAALgAECgUJEAAAAA==.',
Ek='Ekazzik:BAAALgAECgYJBgABLgAFFAMJDAAGABwYAA==.Ekoh:BAAALgAECgIJAgAAAA==.',
El='Elaaranna:BAAALgAECgMJAwAAAA==.Elarol:BAAALgAECgQJBQAAAA==.Eldons:BAAALgADCgIJAgAAAA==.Elfie:BAAALgAECgIJAgAAAA==.Elladra:BAAALgAECgMJAwAAAA==.',
Em='Embers:BAABLgAECn8WAAIbAAYJGxPjWADrAAAbAAYJGxPjWADrAAAAAA==.Emeralde:BAAALgAECgYJCgAAAA==.Emilia:BAAALgADCgIJAwAAAA==.Emptyhands:BAAALgAECgYJBgAAAA==.Emptyheals:BAABLgAECn8zAAIhAAkJ3yC7BABEAwAhAAkJ3yC7BABEAwAAAA==.',
En='Enticedem:BAAALgAECgEJBAAAAA==.',
Er='Ereada:BAAALgADCgUJCgAAAA==.Erfinden:BAAALgADCgEJAQAAAA==.',
Es='Espernite:BAAALgAECgQJBAAAAA==.Espers:BAACLgAFFH8GAAIcAAMJCgf0HgCLAAAcAAMJCgf0HgCLAAAuAAQKfx8AAhwACQnpD68+ABQBABwACQnpD68+ABQBAAAA.',
Et='Ethellin:BAABLgAECn9BAAIQAAkJ0whpGQASAQAQAAkJ0whpGQASAQAAAA==.',
Eu='Euredes:BAAALgADCgYJBgABLgAFFAMJDAAGABwYAA==.',
Fa='Fahrenheit:BAAALgAECgEJAgAAAA==.Farkuat:BAAALgADCgQJBAAAAA==.Fatcastle:BAAALgADCgcJDgAAAA==.',
Fe='Feedmepizzas:BAAALgAECgMJCAAAAA==.Feildmedic:BAAALgAECgEJAQAAAA==.Feleria:BAABLgAECn8qAAIlAAcJ8xVnBQCqAQAlAAcJ8xVnBQCqAQAAAA==.Fellslasher:BAAALgAECgIJAgAAAA==.Felmage:BAAALgADCgYJBgAAAA==.Felraiser:BAAALgADCgIJAgABLgADCgUJBgAFAAAAAA==.Felwinter:BAABLgAECn81AAICAAkJthrMIQBbAgACAAkJthrMIQBbAgAAAA==.Femcelgoon:BAAALgADCgEJAQAAAA==.Fenna:BAAALgADCgYJDAAAAA==.Fetor:BAAALgAECgcJEAAAAA==.',
Fi='Fingulfin:BAAALgAECgIJAwAAAA==.Finwé:BAAALgAECgQJCgAAAA==.Fisha:BAAALgADCgEJAQAAAA==.Fistofwar:BAAALgAECgMJAwAAAA==.Fistsalot:BAAALgAECgQJCAAAAA==.',
Fl='Flafferthorn:BAAALgAECgMJAwAAAA==.Fluxarata:BAABLgAECn8sAAIVAAkJGQ67UwCLAQAVAAkJGQ67UwCLAQAAAA==.',
Fo='Forthememes:BAAALgAECgcJCQAAAA==.',
Fr='Fred:BAABLgAECn8yAAIbAAkJxwvGPQBPAQAbAAkJxwvGPQBPAQAAAA==.Freddrick:BAAALgADCgQJBAAAAA==.Friendly:BAAALgAECgEJAQAAAA==.Friskymage:BAAALgADCgkJCQAAAA==.Frostbuddy:BAAALgAECgcJDQAAAA==.Frëya:BAAALgADCgYJDQAAAA==.Frío:BAAALgAECgEJAQAAAA==.Frøstitute:BAABLgAECn8tAAIIAAkJwRenMwBKAgAIAAkJwRenMwBKAgAAAA==.',
Fu='Fullmage:BAAALgADCgQJBAAAAA==.',
['Fè']='Fènrïr:BAAALgADCgQJBAAAAA==.',
Ga='Gabel:BAABLgAECn8nAAIXAAkJQh3JBgB2AgAXAAkJQh3JBgB2AgAAAA==.Gadnabit:BAAALgADCgkJCQAAAA==.Gailardia:BAACLgAFFH8GAAIGAAMJzRIoNADWAAAGAAMJzRIoNADWAAAuAAQKfyQAAgYABwn/HYUvAB4CAAYABwn/HYUvAB4CAAEuAAUUBAkeABgAxx4A.Galand:BAABLgAECn8mAAMJAAcJPB35EQAoAQAJAAcJzBz5EQAoAQAWAAIJoiFoUABTAAAAAA==.Galladin:BAAALgADCggJDgAAAA==.Gardyson:BAABLgAECn8hAAMZAAgJlxbHAgDZAQAZAAgJlxbHAgDZAQAbAAEJbQNKtAAhAAABLgAFFAMJDAAGABwYAA==.Gazton:BAAALgAECgUJBQAAAA==.',
Gl='Glaaki:BAAALgAECgUJEAAAAA==.',
Gn='Gnob:BAAALgAECgYJEQAAAA==.',
Go='Gooblet:BAAALgADCgQJBQAAAA==.Goodfellow:BAAALgAECgEJAQABLgAECgYJFQAXAMUcAA==.Goopy:BAAALgADCgYJAwAAAA==.',
Gr='Graendal:BAAALgADCgQJBAAAAA==.Granite:BAAALgAECgMJBAAAAA==.Granted:BAAALgADCgUJBQAAAA==.Greevil:BAAALgAECgEJAwAAAA==.Gremilien:BAABLgAECn8xAAITAAkJQhi+AQCrAQATAAkJQhi+AQCrAQAAAA==.Grimgorr:BAAALgADCgMJAwAAAA==.Grimmly:BAAALgAECgEJAQAAAA==.Gruggrug:BAAALgAFFAIJAQAAAA==.Grymdevours:BAAALgADCgYJBgAAAA==.Grymmana:BAAALgADCgQJBAAAAA==.',
Ha='Halcyonic:BAAALgAECgUJCgAAAA==.Halleyscomet:BAABLgAECn8WAAIQAAcJPBptRAAXAgAQAAcJPBptRAAXAgAAAA==.Happyhammer:BAAALgADCgcJCAAAAA==.Harrod:BAAALgAECggJCwAAAA==.Hashey:BAAALgAECgEJAgAAAA==.Hawkwave:BAAALgAECgcJEgABLgAECgkJEQAFAAAAAA==.Hazardzone:BAAALgAECgMJCgAAAA==.',
He='Heartburn:BAAALgAFFAEJAQABLgAFFAYJHQAbAAUdAA==.Heavyweather:BAAALgADCgcJBwAAAA==.Hefty:BAABLgAECn8XAAMKAAkJ3QtnKQBVAQAKAAcJKQtnKQBVAQAGAAUJ8gm3owD6AAAAAA==.Heftyer:BAAALgAECgMJAwAAAA==.Helioween:BAAALgADCgMJAwAAAA==.Helixon:BAAALgADCgYJBgAAAA==.Hellbad:BAACLgAFFH8MAAINAAQJ7hO+KAAGAQANAAQJ7hO+KAAGAQAuAAQKfxUAAw0ACAleGMEnAHMBAA4ABgmOG30jALoBAA0ACAkXEsEnAHMBAAAA.Hellbine:BAAALgADCgMJAgAAAA==.Hellfella:BAAALgAECgEJAQAAAA==.Hellonheels:BAAALgAECgQJBAAAAA==.Hellsspawn:BAAALgAECgYJEAAAAA==.Hexaverse:BAAALgADCgYJBgABLgAECgQJBAAFAAAAAA==.',
Ho='Hoardwither:BAAALgAECgEJAgAAAA==.Hoenheim:BAAALgAECgEJAQAAAA==.Hogrog:BAAALgADCgMJAwAAAA==.Hokàge:BAACLgAFFH8MAAIeAAMJ7x3+JAD8AAAeAAMJ7x3+JAD8AAAuAAQKfzsABB4ACQkpIvQIAJYCAB4ACQkpIvQIAJYCACAAAgkCGhgbAIwAAB8AAQkZAlosAAkAAAAA.Holymortal:BAAALgAECgYJDAAAAA==.Homealone:BAABLgAECn8aAAMdAAkJAQlefADrAAAdAAgJJQdefADrAAAmAAUJ8gPZfQB3AAAAAA==.Honeycruller:BAAALgAECgMJAwABLgAECgkJKAAPAJYbAA==.',
Hu='Huffles:BAAALgAECgQJBwAAAA==.Hugmachine:BAAALgAFFAIJAgAAAA==.Huntinfuzzy:BAAALgAECgkJDwAAAA==.Huntn:BAAALgADCggJCAAAAA==.',
Hy='Hypahypa:BAABLgAECn8UAAIQAAkJ3hOpCQDXAQAQAAkJ3hOpCQDXAQAAAA==.',
Ia='Iamknot:BAAALgAECgQJBgAAAA==.',
Ic='Icemommy:BAAALgADCgQJCAAAAA==.',
Ig='Igothots:BAACLgAFFH8FAAISAAIJZBDKVQBvAAASAAIJZBDKVQBvAAAuAAQKfx4AAxIACQl/HgIQALgCABIACQl/HgIQALgCABcAAQltCb9YACkAAAAA.',
Il='Ildiri:BAAALgADCgMJAwABLgAFFAIJBQAGAGoTAA==.Illariana:BAABLgAECn8aAAQPAAgJNRI5LABzAQAPAAgJNRI5LABzAQAYAAEJwQLCegAfAAAhAAEJvgHGigAdAAAAAA==.Illirotica:BAAALgAECgcJCQAAAA==.',
In='Incredibro:BAAALgADCgEJAQAAAA==.Insanitty:BAAALgAECgcJDwAAAA==.Invincible:BAAALgAECgEJAQABLgAECggJJAAMABMiAA==.',
Ir='Ironlobo:BAABLgAECn8YAAIIAAYJhxkZfACAAQAIAAYJhxkZfACAAQAAAA==.Ironsolari:BAAALgADCgYJBgAAAA==.Irritable:BAABLgAECn8kAAMnAAkJARs/AwCHAgAnAAkJARs/AwCHAgACAAEJJRftIQFGAAAAAA==.',
It='Itherious:BAAALgAECgUJEQAAAA==.',
Ja='Jacham:BAABLgAECn8WAAIbAAkJ2hSIHwDzAQAbAAkJ2hSIHwDzAQAAAA==.Jackyll:BAAALgAECgQJCAAAAA==.Jacmehof:BAAALgADCgIJAgAAAA==.Jagerboy:BAAALgAECgYJBgAAAA==.Jango:BAAALgAECgIJAgABLgAFFAMJDAAGABwYAA==.Jatix:BAACLgAFFH8WAAIQAAUJ0CDXKwBeAQAQAAUJ0CDXKwBeAQAuAAQKfyoAAhAACQkcI3kPAOoCABAACQkcI3kPAOoCAAAA.',
Je='Jeetkundo:BAAALgADCgEJAQABLgAECggJJAAMABMiAA==.Jellydh:BAAALgAECgUJCgAAAA==.Jellymagus:BAAALgAECgIJAgAAAA==.Jellyms:BAAALgAECgcJDwAAAA==.Jellyspinoff:BAAALgAECgMJBwAAAA==.Jellytown:BAABLgAECn89AAIIAAkJaxRVRQALAgAIAAkJaxRVRQALAgAAAA==.Jelorinea:BAAALgAECgMJCQAAAA==.Jemmi:BAAALgADCgEJAQAAAA==.Jessiana:BAABLgAECn8UAAIBAAYJMxRuBAAvAQABAAYJMxRuBAAvAQAAAA==.Jezelda:BAAALgAECgQJBgAAAA==.',
Ji='Jitters:BAAALgADCgEJAQAAAA==.',
Jo='Joeydonuts:BAEALgAECgMJAwABLgAECgUJBgAFAAAAAA==.Johnwickneo:BAAALgAECgEJAQAAAA==.Jolten:BAAALgADCgMJBAAAAA==.',
Jp='Jpeppers:BAABLgAECn8lAAIGAAcJYhW4EgBSAQAGAAcJYhW4EgBSAQAAAA==.',
Ju='Judgementalx:BAAALgAFFAEJAQAAAA==.Juicifer:BAAALgAECgYJBwAAAA==.Jumano:BAAALgAECgUJCgAAAA==.Jundra:BAAALgAECgUJCgAAAA==.Jurih:BAAALgADCgIJAgAAAA==.Justine:BAAALgAECgEJAQAAAA==.',
Ka='Kaineh:BAABLgAECn8oAAITAAgJah3WBQA/AgATAAgJah3WBQA/AgAAAA==.Kainë:BAAALgADCgIJAgAAAA==.Kait:BAABLgAECn8+AAIGAAkJ6R8zEQDHAgAGAAkJ6R8zEQDHAgAAAA==.Kaladil:BAAALgAECgcJDgAAAA==.Kamis:BAAALgAECgMJAwAAAA==.Kanaga:BAAALgAECgQJBQAAAA==.Kannan:BAABLgAECn8YAAMVAAgJzxv/LwA8AgAVAAgJzxv/LwA8AgADAAEJAQdWeQAqAAAAAA==.Kashmihhr:BAAALgADCgIJAgAAAA==.Kashmir:BAAALgAECgQJBAAAAA==.Kasmes:BAAALgADCggJGQAAAA==.Kasmius:BAAALgAECgMJAwAAAA==.Kasmus:BAAALgAECgQJCAAAAA==.Kawdor:BAABLgAECn87AAQUAAkJfBHfFwBgAQAUAAgJ2xDfFwBgAQAlAAcJfRSRBwBfAQAQAAMJ8wrNQQFqAAAAAA==.',
Ke='Keanuleaves:BAAALgAECgIJBQABLgAECggJJAAMABMiAA==.Keetsz:BAAALgAECgYJDAAAAA==.Kelaino:BAAALgADCgQJBQAAAA==.Keledish:BAAALgADCgEJAQAAAA==.',
Kh='Khansmebduke:BAACLgAFFH8FAAMDAAQJNxakGQDUAAADAAMJkRmkGQDUAAAVAAEJKgzfnQA9AAAuAAQKfxYAAwMACAmlHC4WANkBABUACAk1F1w+APsBAAMABwlXHS4WANkBAAEuAAUUBQkJABcAjh4A.Khota:BAAALgAECgYJDAABLgAECgkJRwARAEMVAA==.',
Ki='Kiaf:BAAALgADCgcJDQAAAA==.Kiba:BAAALgADCgEJAQAAAA==.Killakeecat:BAAALgADCgYJBgAAAA==.Killanick:BAAALgAECgEJAQAAAA==.Killdar:BAAALgAECgQJBAAAAA==.Kimia:BAAALgADCgYJCQAAAA==.Kirtthedirt:BAAALgAECgYJCAAAAA==.Kirtthehurt:BAABLgAECn8pAAIIAAkJShhlMABXAgAIAAkJShhlMABXAgAAAA==.',
Ko='Koldfront:BAAALgAECgUJDwAAAA==.Kollinator:BAABLgAECn8dAAIGAAcJPhf/DACgAQAGAAcJPhf/DACgAQAAAA==.Korso:BAAALgADCgUJCwABLgAECgkJLAARAKAQAA==.Kotal:BAAALgAECgEJAQAAAA==.',
Ku='Kurtina:BAAALgAECgUJBgAAAA==.',
Ky='Kylair:BAABLgAECn80AAIPAAkJ/B4cCgCtAgAPAAkJ/B4cCgCtAgAAAA==.Kynreessa:BAAALgADCgYJCAAAAA==.Kythis:BAAALgAECgEJAgABLgAECgkJEgAFAAAAAA==.Kyyell:BAAALgAECggJDgAAAA==.Kyønshi:BAAALgADCgUJBgAAAA==.',
['Kì']='Kìrito:BAAALgAECgcJDgAAAA==.',
La='Labeya:BAEALgAECgMJAwAAAA==.Lafty:BAAALgAFFAEJAgAAAA==.Laftydh:BAAALgAECgYJEgABLgAFFAEJAgAFAAAAAA==.Lailah:BAAALgADCgIJAgABLgAECgkJTAAQAEcdAA==.Laine:BAAALgADCgMJAwAAAA==.Landrra:BAAALgAECgQJBAAAAA==.Larac:BAAALgAECgkJEwAAAA==.Lastwhisper:BAAALgAECgEJAQAAAA==.Lathsong:BAAALgADCgYJDwAAAA==.Lavi:BAAALgADCgQJAwAAAA==.',
Le='Leadge:BAAALgADCgYJBwAAAA==.Lenik:BAABLgAECn8aAAIeAAYJ+gkGOADxAAAeAAYJ+gkGOADxAAAAAA==.Leskya:BAAALgADCgQJAwAAAA==.',
Li='Libras:BAAALgADCgMJAwAAAA==.Licorice:BAAALgAECgUJDgABLgAECgkJKAAPAJYbAA==.Lieree:BAABLgAECn8XAAIIAAgJUg3VggByAQAIAAgJUg3VggByAQAAAA==.Lifeguàrd:BAAALgAECgkJBwAAAA==.Lillana:BAAALgAECgIJAgAAAA==.Lilrayne:BAAALgADCgYJBgABLgAECgkJHAAKAIoPAA==.Lilyfaye:BAAALgADCgkJDAAAAA==.Limosfire:BAABLgAECn8XAAITAAcJeQW7JACOAAATAAcJeQW7JACOAAAAAA==.Linsatha:BAAALgAECggJEAAAAA==.',
Lo='Loa:BAAALgAECgUJBwAAAA==.Lockty:BAAALgAECgIJBgABLgAFFAEJAgAFAAAAAA==.Logi:BAAALgADCgYJCwAAAA==.Lorezever:BAAALgADCgcJDQAAAA==.Lotion:BAAALgADCgIJAgAAAA==.Loun:BAAALgADCgQJBAAAAA==.',
Lu='Luar:BAAALgAECgYJDQAAAA==.Lucity:BAAALgADCgQJAgABLgAFFAUJFgAQANAgAA==.Lulubean:BAAALgAECgcJCgAAAA==.Lunafae:BAAALgADCggJCAAAAA==.Lunaris:BAAALgADCgQJBAAAAA==.Lungorthin:BAAALgAECgQJBQAAAA==.Lunà:BAABLgAECn8sAAIBAAgJIAhgBwDQAAABAAgJIAhgBwDQAAAAAA==.',
Ly='Lythalle:BAAALgAECgEJAQAAAA==.Lythwynn:BAABLgAECn8rAAIQAAkJhQ+0cwCGAQAQAAkJhQ+0cwCGAQAAAA==.',
['Lá']='Lásh:BAAALgAECgUJCAABLgAECgkJLAARAKAQAA==.',
Ma='Mace:BAAALgAECgEJAQAAAA==.Madison:BAAALgAECgEJAQAAAA==.Madyorkies:BAAALgAECgkJAQAAAA==.Magdolyn:BAAALgADCgMJAwAAAA==.Mageyboi:BAAALgAECgQJBgABLgAFFAMJDAAeAO8dAA==.Magickul:BAAALgAECgYJDAAAAA==.Magleon:BAAALgADCgIJAgAAAA==.Magonk:BAAALgADCgEJAQAAAA==.Mahano:BAACLgAFFH8MAAMGAAMJHBjLLADxAAAGAAMJHBjLLADxAAATAAEJVwUaIgA0AAAuAAQKfxgAAwYACAnUGg8fAGwCAAYACAnUGg8fAGwCABMAAQn+E2QNAD4AAAAA.Makis:BAAALgAECgMJBQAAAA==.Malachi:BAAALgAECgYJBwAAAA==.Manavoid:BAABLgAECn8cAAIVAAYJkArjpwDVAAAVAAYJkArjpwDVAAAAAA==.Mandoanubis:BAAALgADCgcJCgAAAA==.Mandragore:BAAALgAECgIJBAAAAA==.Marakesh:BAAALgADCgEJAQAAAA==.Marinas:BAAALgADCgMJAwAAAA==.Massili:BAAALgADCgkJGgAAAA==.Mastor:BAAALgADCgQJBwAAAA==.Maynard:BAABLgAECn8hAAIMAAkJ9xErLwC/AQAMAAkJ9xErLwC/AQAAAA==.',
Mc='Mcdouble:BAAALgADCgMJAwAAAA==.',
Me='Meditation:BAAALgAECgEJAQABLgAECgMJAwAFAAAAAA==.Melancholy:BAAALgADCggJCAAAAA==.Meldanis:BAAALgAECgQJBAAAAA==.Meri:BAABLgAECn8cAAISAAgJlxwrJgAfAgASAAgJlxwrJgAfAgAAAA==.',
Mi='Miande:BAABLgAECn8VAAInAAcJ0xfLCgCyAQAnAAcJ0xfLCgCyAQAAAA==.Microburst:BAAALgAECgUJCgAAAA==.Minecraft:BAAALgAECgIJAgAAAA==.Minilock:BAABLgAECn9BAAMCAAkJEhVnCACLAQACAAkJVRNnCACLAQABAAUJDBnGBAAiAQAAAA==.Misogynixy:BAAALgADCgQJBAAAAA==.Missdeeds:BAAALgAECgUJBQAAAA==.Missleading:BAAALgAECgYJCQAAAA==.Missused:BAABLgAECn8YAAIIAAYJiQ6jIADcAAAIAAYJiQ6jIADcAAAAAA==.Mistycat:BAAALgAECgkJDQAAAA==.Mithos:BAAALgAECgUJBwAAAA==.Mithraxa:BAAALgAECgQJBAAAAA==.Miyagifu:BAAALgAECgQJBAAAAA==.',
Mo='Moash:BAAALgADCgkJCQAAAA==.Modsagoodtnk:BAABLgAECn8cAAIUAAcJRQ7dCADaAAAUAAcJRQ7dCADaAAABLgAECggJLwAGAH8ZAA==.Mongermook:BAABLgAECn8iAAMRAAkJ0QugDgCbAAARAAkJ0QugDgCbAAAcAAEJxgFpkQAVAAAAAA==.Monnkysham:BAAALgAECgQJBgABLgAECgYJCQAFAAAAAA==.Moogledragon:BAAALgADCgMJAwAAAA==.Mooglefur:BAAALgAECgQJBQAAAA==.Moonbloom:BAABLgAECn8dAAISAAkJTBxLHwBMAgASAAkJTBxLHwBMAgAAAA==.Mooseknuhkle:BAAALgAECgEJAQAAAA==.Morgrim:BAAALgAECgIJBAAAAA==.Morlosh:BAAALgAECgMJAwAAAA==.Moryna:BAABLgAECn81AAIaAAkJsQhZJQA9AQAaAAkJsQhZJQA9AQAAAA==.',
Mt='Mthrandir:BAAALgADCgUJBQAAAA==.',
Mu='Muford:BAAALgAECgQJBQABLgAFFAgJFQANAOQfAA==.Mull:BAAALgAECgYJEwAAAA==.Muloc:BAAALgADCgEJAQAAAA==.',
My='Myaka:BAAALgAECgYJBgAAAA==.Mythicc:BAAALgAECgMJAwAAAA==.',
Na='Naatixa:BAAALgAECggJDAAAAA==.Nacronor:BAABLgAECn8VAAIGAAUJHwTxNAB6AAAGAAUJHwTxNAB6AAAAAA==.Naiika:BAAALgAECgYJBwAAAA==.Naivaya:BAAALgADCgMJAwAAAA==.Nascha:BAAALgADCgEJAQAAAA==.Nasoj:BAAALgAECgcJCwAAAA==.',
Ne='Necrasirenea:BAAALgAECggJCAABLgAECgcJCQAFAAAAAA==.Necrotic:BAAALgAECgQJBAAAAA==.Nedalla:BAAALgAECgYJDAAAAA==.Neeve:BAAALgAECgMJAwAAAA==.Nekrotik:BAAALgADCgcJBgAAAA==.Neobahamut:BAAALgAECgUJCwABLgAECgcJDgAFAAAAAA==.Netharel:BAAALgADCgIJAgAAAA==.Newports:BAAALgAECgQJBQAAAA==.',
Ni='Nichôlasmage:BAAALgAECgYJCwAAAA==.Nickatnite:BAAALgAFFAMJBAAAAA==.Nickelodeon:BAAALgAFFAIJAwAAAA==.Nicksaban:BAABLgAECn8nAAIQAAkJuBuBLgBHAgAQAAkJuBuBLgBHAgAAAA==.Nightgear:BAACLgAFFH80AAMGAAkJ2BYADwDuAQAGAAgJihgADwDuAQATAAIJ/ApJNQBJAAAuAAQKf1kAAwYACQm1IgUIABADAAYACQm1IgUIABADABMABAnfEoAjAJcAAAAA.Nighti:BAAALgAECgUJBgAAAA==.Nightshades:BAAALgADCgQJBAAAAA==.Nilux:BAAALgAECgYJDwAAAA==.Ninetails:BAAALgAECgUJCgAAAA==.Niteshadeth:BAAALgAECgQJBQAAAA==.Niteyknight:BAAALgAECgQJBAAAAA==.Nixeava:BAABLgAECn8dAAImAAkJVQV6VADoAAAmAAkJVQV6VADoAAAAAA==.',
No='Nogooddruid:BAAALgAECgUJDwAAAA==.Nopetsneeded:BAABLgAECn89AAITAAkJzBRpCAD3AQATAAkJzBRpCAD3AQAAAA==.Norepairbill:BAAALgAECgEJAQABLgAECgkJPQATAMwUAA==.Nostariel:BAAALgAECgQJCgAAAA==.Notadoctor:BAAALgAECgYJCAAAAA==.Noteworthy:BAAALgAECgYJEgABLgAFFAcJEAAJAHYeAA==.',
Nu='Nubuu:BAAALgADCgkJCQAAAA==.',
Ny='Nyctera:BAAALgAFFAEJAQAAAA==.Nysong:BAABLgAECn84AAMBAAgJaQy/EgAfAQABAAgJaQy/EgAfAQACAAMJYwKJGAFPAAAAAA==.Nyxra:BAAALgAECgEJAQAAAA==.',
['Nó']='Nórin:BAAALgAECgUJBQAAAA==.',
Oa='Oakenforge:BAAALgAECgcJBwABLgAFFAIJBQAGAGoTAA==.',
Ob='Obali:BAAALgADCgYJCgAAAA==.',
Od='Oddangel:BAAALgAECgYJEwABLgAECgcJCwAFAAAAAA==.Ode:BAABLgAECn8UAAIIAAkJLw/qDwBqAQAIAAkJLw/qDwBqAQAAAA==.Odex:BAACLgAFFH8JAAMjAAQJ+wTgBQBuAAAiAAQJqQPJKACAAAAjAAIJCAfgBQBuAAAuAAQKfyoAAyMACQlvDX8IAKgBACMACQlvDX8IAKgBACIAAQmmCE2QADoAAAAA.Odéyemí:BAAALgAECgUJBwAAAA==.',
Oh='Ohblergen:BAAALgAECgIJAgAAAA==.',
Ok='Okragren:BAABLgAECn83AAImAAkJ/A1NMwBvAQAmAAkJ/A1NMwBvAQAAAA==.',
Ol='Olehi:BAAALgADCgcJBwAAAA==.Olynder:BAAALgAECgIJBAAAAA==.',
On='Onos:BAABLgAECn8eAAIGAAkJOCA4IABEAgAGAAkJOCA4IABEAgAAAA==.Onto:BAAALgADCgEJAQAAAA==.Ontoquas:BAAALgADCgkJCgAAAA==.',
Or='Orinin:BAAALgAECgUJBgABLgAECgQJCQAFAAAAAA==.',
Ou='Outdeath:BAAALgAECgUJBwAAAA==.',
Pa='Paleclaw:BAAALgADCgQJBAAAAA==.Palitroque:BAAALgAECgQJBAAAAA==.Pally:BAAALgAECgUJBQAAAA==.Papasmurfz:BAAALgAFFAEJAQAAAA==.Paramedic:BAABLgAECn8UAAIPAAUJAxPUDQDfAAAPAAUJAxPUDQDfAAAAAA==.Pathogen:BAABLgAECn8hAAIJAAkJDR/oOwARAgAJAAkJDR/oOwARAgAAAA==.',
Pe='Penryn:BAAALgAECgQJBwAAAA==.Pepster:BAABLgAECn8bAAIoAAkJtgHgLgCAAAAoAAkJtgHgLgCAAAAAAA==.Persephoknee:BAAALgADCgEJAQAAAA==.Persephoni:BAABLgAECn8UAAILAAcJah66AQAXAgALAAcJah66AQAXAgAAAA==.',
Pf='Pfchen:BAAALgAECgMJBQAAAA==.',
Pl='Plaguestrip:BAAALgAECgEJAwAAAA==.Plinkerbell:BAAALgAECgMJAwAAAA==.Plumprnickel:BAAALgAECgEJAQAAAA==.Plxkingg:BAAALgADCgUJBQAAAA==.',
Po='Poppit:BAAALgAECgkJDgAAAA==.Porimma:BAABLgAECn8YAAMCAAcJVwauGwCbAAACAAcJVwauGwCbAAABAAMJdgVnEwAzAAAAAA==.Pormas:BAAALgAECgYJDwAAAA==.Poseydon:BAAALgADCgQJBAABLgAECgEJAQAFAAAAAA==.',
Pr='Prayerz:BAAALgADCgMJAwAAAA==.Proctology:BAAALgAECgQJBAAAAA==.Prom:BAAALgAECgcJEwAAAA==.Promethèus:BAAALgAECgQJBAAAAA==.Prosby:BAAALgADCgIJAgAAAA==.Protection:BAAALgAFFAEJAgAAAA==.Prowlnfool:BAAALgADCgUJBQAAAA==.Pryto:BAAALgADCgkJDgABLgAFFAIJAwAFAAAAAA==.',
Qu='Queedle:BAABLgAECn8nAAIfAAkJsw9wAQBSAQAfAAkJsw9wAQBSAQAAAA==.Quickly:BAAALgAECgcJEgAAAA==.',
Ra='Raennis:BAAALgAECgIJAgAAAA==.Ragalstan:BAAALgAECgEJAgAAAA==.Ragnarook:BAAALgAECgEJAQABLgAECgQJCAAFAAAAAA==.Rahanumn:BAABLgAECn8YAAIQAAgJ6wktpAAxAQAQAAgJ6wktpAAxAQAAAA==.Rainlette:BAAALgAECggJEgAAAA==.Rainsvoker:BAACLgAFFH8jAAIkAAYJXQ2aEgBqAQAkAAYJXQ2aEgBqAQAuAAQKf1IAAyQACQkOHL4GAJUCACQACQkOHL4GAJUCACIABgk7CAxeAMAAAAAA.Raizak:BAAALgAECgEJAQAAAA==.Ramike:BAAALgAECggJCQAAAA==.Raqtar:BAAALgAECgIJAgABLgAECgkJEgAFAAAAAA==.Rasmis:BAAALgAECgIJAwABLgAECgkJEgAFAAAAAA==.Ratbreath:BAAALgADCgYJBgAAAA==.Ratrazarke:BAAALgADCgIJAgAAAA==.Razihel:BAAALgADCgYJCQAAAA==.Razzledazzlë:BAAALgAECgEJAQAAAA==.',
Re='Reaver:BAAALgAECgQJBAAAAA==.Reddan:BAABLgAECn8qAAIQAAgJlgzSmwA+AQAQAAgJlgzSmwA+AQAAAA==.Redruth:BAAALgAECgEJAgAAAA==.Renata:BAAALgAFFAIJAgAAAA==.Replicant:BAAALgAECgEJAQAAAA==.Retman:BAAALgAECgMJAQAAAA==.Reverìe:BAAALgAECgcJBwAAAA==.Reylinn:BAAALgAECgQJBAAAAA==.Reyra:BAAALgAECgEJAQABLgAFFAIJAgAFAAAAAA==.Reï:BAABLgAECn8kAAISAAkJsRTZJAAlAgASAAkJsRTZJAAlAgAAAA==.',
Ri='Ridlei:BAAALgAECgMJBAAAAA==.Rimchester:BAAALgAECgIJAQAAAA==.Rimurutempas:BAAALgAECgEJAgAAAA==.Rinji:BAAALgAECgYJCwAAAA==.Ritzon:BAABLgAECn89AAMbAAkJJSRhBgD4AgAbAAkJJSRhBgD4AgAaAAEJmBdmcQA+AAAAAA==.',
Ro='Rosadita:BAAALgAECgQJBQABLgAECggJHQAbAE0VAA==.Roxydan:BAABLgAECn8dAAMBAAgJiQ03KQAdAQACAAgJiQ1KZwCWAQABAAYJ8Ag3KQAdAQAAAA==.',
Ru='Runastalis:BAAALgADCgYJCwAAAA==.Ruwea:BAAALgAECgEJAQABLgAECgkJJAASALEUAA==.',
Ry='Ryanrainolds:BAAALgAECgYJCQABLgAECggJJAAMABMiAA==.Rykken:BAAALgAECgEJAgAAAA==.Ryko:BAABLgAECn8fAAIoAAcJqBSRFwBOAQAoAAcJqBSRFwBOAQAAAA==.',
['Rë']='Rëyra:BAAALgAFFAIJAgAAAA==.',
Sa='Salene:BAAALgAFFAIJAgAAAA==.Sanandume:BAAALgADCgEJAQAAAA==.Sanctess:BAAALgAECggJDgAAAA==.Sankai:BAAALgAECgEJAQABLgAFFAEJAgAFAAAAAA==.Saraelle:BAAALgAECgEJAwAAAA==.Sarlas:BAAALgADCgQJBAAAAA==.Sarumanpally:BAAALgAECgYJBwAAAA==.Saruquan:BAAALgAECgkJCQAAAA==.Satora:BAAALgAECgQJBAAAAA==.Sayomi:BAAALgADCgcJEwAAAA==.',
Se='Secretjuicy:BAAALgAECgYJCQAAAA==.Sellex:BAAALgAECgEJAQAAAA==.Senseijundra:BAAALgAECgQJCAAAAA==.Sentinaal:BAAALgAECgEJAQAAAA==.Sethira:BAAALgAECgEJAQABLgAECggJDAAFAAAAAA==.',
Sh='Shabadu:BAAALgADCgQJBAAAAA==.Shadyandi:BAAALgADCgcJCAAAAA==.Shamanhack:BAAALgAFFAIJAwAAAA==.Shan:BAAALgADCgYJBgAAAA==.Sharazad:BAAALgAFFAEJAQAAAA==.Sheda:BAAALgAECgQJBAAAAA==.Shedia:BAAALgAECgEJAQAAAA==.Shmoove:BAEALgAECgUJBgAAAA==.Shmooves:BAEALgAECgQJBAABLgAECgUJBgAFAAAAAA==.Shoukei:BAAALgADCgIJAwAAAA==.',
Si='Sianna:BAAALgADCgYJBgAAAA==.Sieya:BAAALgAECgEJAQAAAA==.Siinful:BAAALgAECgEJAQAAAA==.Simbruh:BAAALgADCgMJAwAAAA==.Simpari:BAABLgAFFH8MAAIJAAMJlwyPTQDAAAAJAAMJlwyPTQDAAAAAAA==.Sinarria:BAAALgAECgEJAQAAAA==.Sithra:BAAALgADCgEJAQAAAA==.',
Sk='Skeemer:BAAALgAECgUJBQAAAA==.Skeetro:BAAALgAECgEJAQAAAA==.Skips:BAAALgAECgQJCQAAAA==.Skullace:BAABLgAECn8qAAIBAAkJuw9GCgChAQABAAkJuw9GCgChAQAAAA==.Skullhead:BAAALgADCgEJAQAAAA==.Skybreaker:BAAALgAECgkJCAAAAA==.Skylette:BAAALgAECgcJCQAAAA==.',
Sm='Smashurfacen:BAAALgADCgcJFAAAAA==.',
Sn='Snitbit:BAAALgADCgkJGgAAAA==.Sno:BAAALgADCgEJAQABLgAECgUJBwAFAAAAAA==.Snoopingas:BAAALgAECgEJAQAAAA==.Snpcrklpopu:BAAALgADCgYJCAAAAA==.',
So='Solarana:BAAALgAECgkJCQAAAA==.Sortiebatoru:BAAALgAECgIJAwAAAA==.Sotzi:BAAALgADCggJEQAAAA==.Souldune:BAAALgAECgYJBgAAAA==.',
Sp='Sparkplugg:BAAALgAECgEJAQAAAA==.Sparthos:BAAALgAECgIJAgAAAA==.',
Sr='Srfreaky:BAABLgAECn8VAAIZAAUJ1xs8BgAWAQAZAAUJ1xs8BgAWAQAAAA==.',
St='Sterlìng:BAAALgAECgUJCQAAAA==.Stevejabbs:BAABLgAECn8kAAMMAAgJEyL/AQC9AgAMAAgJEyL/AQC9AgANAAMJ5SAEOQAYAQAAAA==.Stocklock:BAAALgAECgEJAQAAAA==.Stormcunning:BAABLgAECn8WAAImAAYJCAxiTAAWAQAmAAYJCAxiTAAWAQAAAA==.Stormfire:BAAALgADCgcJBwAAAA==.Stormßringer:BAABLgAECn8UAAImAAgJERDXMwCJAQAmAAgJERDXMwCJAQAAAA==.Stownr:BAAALgAECgYJBgAAAA==.Strip:BAAALgAECgEJAQAAAA==.Strongclaw:BAAALgADCgUJBQAAAA==.Stumpyborg:BAABLgAECn8VAAQBAAcJaAY9MgBVAAACAAYJNgSn3gCdAAABAAIJMws9MgBVAAAnAAEJhAcZQwArAAABLgAECgkJFwAKAN0LAA==.Stónéhëárt:BAAALgADCgYJBwABLgAECgkJEQAFAAAAAA==.',
Su='Subdue:BAAALgADCgQJBAAAAA==.Subverse:BAAALgAECgQJBAAAAA==.Suicune:BAAALgAECgEJAgAAAA==.Sukimyheelz:BAAALgAECgQJBAAAAA==.Sundance:BAAALgAECgcJDgAAAA==.Sune:BAABLgAECn8gAAMPAAYJxgvZRwDwAAAPAAYJxgvZRwDwAAAhAAEJNwk2ggAqAAAAAA==.Supplicant:BAAALgADCgQJBwAAAA==.',
Sv='Svellulfr:BAAALgAECgEJAQAAAA==.Svuca:BAAALgADCgcJBwAAAA==.',
Sy='Sydneyweenie:BAAALgADCgcJCAAAAA==.Syldi:BAAALgAECgEJAQABLgAECgcJJAAYACsbAA==.Sythis:BAAALgAECgIJAwAAAA==.',
['Sä']='Sästa:BAAALgADCgkJCQAAAA==.',
['Sö']='Sörren:BAABLgAECn8pAAInAAcJYwaRCACvAAAnAAcJYwaRCACvAAAAAA==.',
Ta='Tacosdeasada:BAAALgAECgEJAQAAAA==.Taitertot:BAAALgAECgUJBQAAAA==.Tanelórn:BAAALgAECgQJBQAAAA==.Tanlon:BAAALgAECggJEgAAAA==.Tayko:BAAALgAECgEJAQAAAA==.Taykorra:BAAALgADCggJDQAAAA==.',
Te='Telandril:BAABLgAECn8vAAISAAkJvxH4MwDNAQASAAkJvxH4MwDNAQAAAA==.Telphin:BAAALgAECgYJDAAAAA==.Tempestira:BAAALgAECgEJAgAAAA==.Tensuken:BAABLgAECn8ZAAIQAAYJpBidsAAeAQAQAAYJpBidsAAeAQAAAA==.Testarossaa:BAAALgADCgEJAQAAAA==.Teylonna:BAAALgAECgEJAQAAAA==.',
Th='Thadgun:BAAALgADCgkJFQAAAA==.Thadium:BAAALgAECgMJAwAAAA==.Thalgan:BAAALgAECgEJAQAAAA==.Thalyn:BAAALgAECgEJAQAAAA==.Thauríel:BAAALgAECgEJAQAAAA==.Thecword:BAAALgADCgYJBgAAAA==.Thejuiciest:BAAALgAECgYJBwAAAA==.Themedic:BAABLgAECn8gAAMdAAcJoRd2CAC+AQAdAAcJoRd2CAC+AQAmAAEJ6gFuxAAXAAAAAA==.Theremar:BAAALgAECgUJAwAAAA==.Thergothon:BAAALgAECgEJAQABLgAECgMJAwAFAAAAAA==.Theunclepaul:BAAALgAECggJDwAAAA==.Thisisdrexx:BAAALgAECgIJAwAAAA==.Thorwrath:BAAALgADCgEJAgAAAA==.Thrazoro:BAAALgAECgQJBAAAAA==.Thrazzoro:BAAALgAECgYJEwAAAA==.',
Ti='Tiarl:BAACLgAFFH8MAAIYAAMJohLfEACkAAAYAAMJohLfEACkAAAuAAQKfzcAAhgACQliGKERAFQCABgACQliGKERAFQCAAAA.Tiia:BAAALgADCgIJAgAAAA==.Timex:BAABLgAECn8XAAMjAAYJRCD5DgDrAQAjAAYJRCD5DgDrAQAiAAEJUhdnjgA+AAAAAA==.Tinydots:BAAALgAECgkJDAAAAA==.Tinypaws:BAAALgAECgQJBAAAAA==.Tinysitril:BAAALgAECgYJCQABLgAFFAQJCwADAJcPAA==.Tinysohei:BAAALgAECgQJBAAAAA==.Titañick:BAAALgAFFAIJAgAAAA==.',
To='Tom:BAABLgAECn8aAAMiAAYJLgvvVgDWAAAiAAYJLgvvVgDWAAAjAAEJZQhLJwAvAAAAAA==.Toosxyfohair:BAABLgAECn8sAAIdAAgJFRsBCwCGAQAdAAgJFRsBCwCGAQAAAA==.',
Tr='Trainwrekk:BAAALgADCgYJBgAAAA==.Tranqar:BAAALgAECgQJBgAAAA==.Tresg:BAAALgAECgYJCQAAAA==.Trissandra:BAAALgAECgEJAQAAAA==.Trolltoll:BAAALgADCgEJAwAAAA==.Trüth:BAAALgADCggJEAAAAA==.',
Tu='Tuv:BAAALgAECgQJCAAAAA==.',
Tw='Twentytwo:BAAALgAECgUJBwAAAA==.Twylidan:BAEALgAECgkJCgABLgAFFAQJDAAiAOkeAA==.',
Ty='Tygar:BAAALgAECgEJAQAAAA==.Tyrannt:BAAALgAECgEJAQAAAA==.Tyrannus:BAAALgADCgcJCgAAAA==.Tyrànda:BAAALgAECgUJDwAAAA==.Tyzy:BAAALgAECgEJAgAAAA==.',
['Tö']='Tötém:BAAALgAECgEJAQAAAA==.',
Ul='Ulanhi:BAABLgAECn8VAAIXAAUJzh31EACdAQAXAAUJzh31EACdAQAAAA==.Uling:BAAALgAECgEJAQAAAA==.',
Un='Undeadjelly:BAABLgAECn8YAAMJAAkJ2h7oZgCZAQAJAAcJHSDoZgCZAQALAAcJUhmLFgAkAQAAAA==.Unholy:BAAALgAECgYJDwAAAA==.',
Ur='Urkzul:BAAALgADCgMJAwAAAA==.Ursoth:BAAALgADCgUJCgAAAA==.',
Ut='Uthèrsmight:BAAALgAECgYJBgAAAA==.Uti:BAAALgADCgUJBQAAAA==.',
Uu='Uubs:BAAALgADCgEJAQABLgAFFAMJCgAQAJoSAA==.',
Va='Valakk:BAAALgAECggJEAAAAA==.Vallak:BAAALgADCgIJBAAAAA==.Valsitril:BAAALgAECgYJEAABLgAFFAQJCwADAJcPAA==.Valthaczar:BAAALgAECgMJBgAAAA==.Vanara:BAAALgAECgEJAgAAAA==.Varadun:BAAALgAFFAIJAwAAAA==.Varrosh:BAAALgADCgYJBgAAAA==.Vathan:BAAALgAECgQJBQAAAA==.',
Ve='Velmora:BAAALgAECgkJCQAAAA==.Velsetin:BAABLgAECn8dAAIIAAcJTBsyTABSAgAIAAcJTBsyTABSAgABLgAFFAMJBQAcAMcUAA==.Verathina:BAAALgADCgEJAgAAAA==.Versailespq:BAAALgAECgMJAwAAAA==.Versed:BAAALgADCgUJBQABLgAECgQJBAAFAAAAAA==.Veryspooky:BAABLgAECn8fAAICAAgJkRsHOAD5AQACAAgJkRsHOAD5AQAAAA==.Vexian:BAABLgAECn8fAAMmAAkJJh0jBADzAQAmAAkJJh0jBADzAQAdAAEJ3B/FtwBcAAAAAA==.Vexlock:BAAALgAECgMJAwABLgAECgkJHwAmACYdAA==.',
Vf='Vfl:BAAALgADCgcJBwAAAA==.',
Vi='Vicas:BAAALgAECgcJEgAAAA==.',
Vl='Vladdek:BAAALgAFFAEJAwAAAA==.Vladdok:BAAALgAECgUJBQAAAA==.Vladok:BAAALgAECgQJCwAAAA==.Vladokk:BAAALgAECgMJAwAAAA==.',
Vo='Voidofdeath:BAAALgADCgQJBAAAAA==.Voidshiekah:BAAALgADCgEJAQAAAA==.Vorteia:BAAALgADCgYJBgAAAA==.',
['Vé']='Véngéánçé:BAAALgAECgMJBAAAAA==.',
Wa='Wald:BAAALgAECgYJEAAAAA==.Warmongerr:BAAALgADCgIJAgAAAA==.Waruh:BAAALgADCgcJCQAAAA==.Warzy:BAAALgAECgEJAQAAAA==.',
We='Webgar:BAAALgAECgEJAQAAAA==.Webrune:BAAALgAECgMJAwAAAA==.',
Wh='Whisperlia:BAAALgAECgQJCAAAAA==.Whisperwindd:BAAALgAECgYJDAAAAA==.White:BAABLgAFFH8JAAMnAAMJcBUgCgCEAAACAAIJIxitQwCKAAAnAAIJRgwgCgCEAAAAAA==.Whitetoothe:BAABLgAECn9LAAIGAAcJ0BltDwB8AQAGAAcJ0BltDwB8AQAAAA==.',
Wi='Witemandown:BAAALgADCgcJCAAAAA==.Witherbear:BAAALgAECgEJAQAAAA==.Witherhoard:BAAALgAECgUJBQAAAA==.Wizzy:BAAALgADCgEJAQAAAA==.',
Wo='Workin:BAAALgADCgEJAQABLgAECgkJIwASANUVAA==.',
['Wå']='Wånheda:BAAALgAECggJEwAAAA==.',
Xa='Xaniana:BAAALgAECgkJEAAAAA==.Xaosin:BAAALgADCgUJBQAAAA==.',
Xe='Xenzak:BAAALgAECgEJAQAAAA==.Xephir:BAAALgADCgMJAwAAAA==.Xerxës:BAAALgAECgEJAQAAAA==.',
Xl='Xl:BAAALgAECgQJCwAAAA==.',
Xo='Xoito:BAAALgAECgEJAQABLgAFFAEJAQAFAAAAAA==.Xotiko:BAAALgAECgYJDAAAAA==.',
Xu='Xubris:BAAALgADCgYJCQAAAA==.',
['Xâ']='Xâxâs:BAAALgAECgMJAwABLgAECggJGwAiAHQFAA==.',
Ya='Yaerin:BAACLgAFFH8ZAAIhAAQJcCMSGwCLAQAhAAQJcCMSGwCLAQAuAAQKfyYAAiEACQnnI/MDAFsDACEACQnnI/MDAFsDAAAA.Yaoi:BAAALgAFFAIJAgAAAA==.',
Yu='Yunarä:BAAALgAECgYJCAAAAA==.Yuukon:BAABLgAECn8bAAQWAAgJtxfwHABxAQAWAAgJtxfwHABxAQAJAAQJ5gOZOQFkAAALAAEJDwgrGAAvAAAAAA==.',
Za='Zackman:BAAALgAECgQJBAAAAA==.Zadira:BAAALgAECgUJBQAAAA==.Zakuul:BAAALgADCgQJBAAAAA==.Zalezaar:BAAALgAECgIJAgAAAA==.Zangetsu:BAAALgAECgcJBwAAAA==.Zarusthra:BAAALgAECgEJAQAAAA==.Zaxie:BAABLgAECn8/AAIVAAkJrh0pAwBGAgAVAAkJrh0pAwBGAgAAAA==.',
Ze='Zenjuice:BAAALgAECgcJAgAAAA==.Zenwu:BAAALgADCgkJGwAAAA==.Zephrylia:BAAALgAECgUJCgAAAA==.Zerama:BAAALgAECgUJBQAAAA==.',
Zh='Zheratul:BAAALgAECgEJAQAAAA==.Zhirl:BAAALgAECgkJCQAAAA==.Zhivet:BAAALgAECgYJBwAAAA==.',
Zi='Zilphia:BAABLgAECn8wAAIIAAkJKxE8CgDDAQAIAAkJKxE8CgDDAQAAAA==.',
Zu='Zuriel:BAAALgAECgIJAgAAAA==.',
Zy='Zyku:BAAALgAECgEJAQAAAA==.Zylphie:BAAALgADCgcJBwAAAA==.',
['Àm']='Àmagezing:BAAALgAFFAIJAgABLgAFFAYJGwAQACweAA==.',
['Åj']='Åj:BAAALgADCgcJBwAAAA==.',
['Åp']='Åpexx:BAABLgAECn8cAAMVAAYJKAZnIwB8AAAVAAYJCAZnIwB8AAADAAEJzAYcfQAjAAAAAA==.',
['Çw']='Çwÿbàbý:BAAALgAECgYJEwAAAA==.',
['Ða']='Ðark:BAAALgAECgEJAQAAAA==.',
['Ór']='Órión:BAABLgAECn8VAAIGAAYJ1BLuoQD+AAAGAAYJ1BLuoQD+AAAAAA==.',
['Ös']='Östara:BAABLgAECn8jAAISAAkJ1RW2BwBbAQASAAkJ1RW2BwBbAQAAAA==.',
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
