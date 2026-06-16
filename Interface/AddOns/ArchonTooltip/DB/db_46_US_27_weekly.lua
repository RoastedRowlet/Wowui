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

local lookup = {'Warlock-Destruction','Hunter-BeastMastery','Unknown-Unknown','Mage-Arcane','Mage-Frost','Hunter-Survival','DeathKnight-Frost','Monk-Mistweaver','Monk-Brewmaster','Monk-Windwalker','DeathKnight-Unholy','Priest-Shadow','Paladin-Retribution','Druid-Guardian','Druid-Restoration','Hunter-Marksmanship','Paladin-Protection','DemonHunter-Devourer','DeathKnight-Blood','Priest-Holy','Druid-Balance','Shaman-Restoration','Rogue-Subtlety','DemonHunter-Havoc','Rogue-Outlaw','Rogue-Assassination','Warlock-Demonology','Warrior-Arms','Warrior-Fury','Priest-Discipline','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Druid-Feral','Warrior-Protection','Shaman-Elemental','Warlock-Affliction','Paladin-Holy','Shaman-Enhancement',}
local provider = {region='US',realm='Azuremyst',name='US',type='weekly',zone=46,date='2026-06-13',data={Aa='Aaravos:BAABLgAECn8aAAIBAAgJshaXBwDVAQABAAgJshaXBwDVAQAAAA==.',
Ab='Abysseon:BAAALgAECgUJDgAAAA==.',
Ac='Accretion:BAAALgAECgYJBgAAAA==.',
Ad='Adaria:BAABLgAECn8WAAICAAcJWAWSZQA3AQACAAcJWAWSZQA3AQAAAA==.Adrillbear:BAAALgAECgIJAgABLgAECgYJEwADAAAAAA==.Adura:BAAALgAECgMJAwAAAA==.',
Ae='Aeirith:BAACLgAFFH8KAAIEAAQJthRbAQAjAQAEAAQJthRbAQAjAQAuAAQKfyQAAwQACQmwHd8BAGYCAAQACQmwHd8BAGYCAAUAAQlFCmRbATEAAAAA.Aelion:BAAALgAECgEJAQAAAA==.',
Ah='Ahheevoker:BAAALgAECgYJEgAAAA==.',
Ai='Ailsà:BAAALgADCgEJAQAAAA==.',
Ak='Akarias:BAAALgAECgEJAQABLgAECgcJBwADAAAAAA==.',
Al='Aladaria:BAAALgAECgMJAwAAAA==.Aldyah:BAAALgAECggJDwAAAA==.Alias:BAAALgAECgYJBQAAAA==.Allanonn:BAAALgAECgQJBAAAAA==.Alohomora:BAAALgAECgUJEAAAAA==.Alvist:BAAALgAECgQJEgAAAA==.',
Am='Amarasu:BAABLgAECn8bAAIGAAkJig8OGwDFAQAGAAkJig8OGwDFAQAAAA==.Amarlly:BAABLgAECn8wAAIHAAgJYxq8BwAWAgAHAAgJYxq8BwAWAgAAAA==.Amenedil:BAAALgAECgUJDAAAAA==.',
An='Anbrew:BAABLgAECn8UAAQIAAcJdxKzSQA9AQAIAAYJDBKzSQA9AQAJAAUJjA7nPwD4AAAKAAEJMweTrAAlAAABLgAFFAYJDwALAN0dAA==.Ancelina:BAABLgAECn8qAAIMAAkJeyRjAgBGAwAMAAkJeyRjAgBGAwAAAA==.Anderton:BAABLgAECn8xAAINAAgJShmzSgDkAQANAAgJShmzSgDkAQAAAA==.Andilocks:BAAALgADCgMJAwAAAA==.Aneira:BAABLgAECn8XAAMOAAYJNA4xMwDWAAAOAAYJNA4xMwDWAAAPAAMJYQw6mAB+AAAAAA==.Annovera:BAAALgAECgMJBgAAAA==.Anuubis:BAAALgADCgYJBgAAAA==.Anyi:BAAALgAECgEJAQAAAA==.',
Ap='Apexxd:BAAALgAECgIJAgAAAA==.Applefritter:BAAALgAECgUJCAABLgAECgkJKAAMAJYbAA==.',
Ar='Archérhiro:BAACLgAFFH8nAAMCAAgJkRVsBwA0AgACAAcJUxhsBwA0AgAQAAMJRwTfIQCHAAAuAAQKfykAAwIACQlYHw8YAJICAAIACQlMHw8YAJICABAACAkrGdobAEoCAAAA.Arilias:BAAALgAECgEJAQABLgAECgkJLQACAE0XAA==.Arillann:BAABLgAECn89AAIRAAkJUR+XBACuAgARAAkJUR+XBACuAgAAAA==.Arrook:BAAALgADCgMJAwAAAA==.Arrtonomis:BAAALgAECgUJCAABLgAECgkJEQADAAAAAA==.Artdemsamis:BAAALgAECgIJAwABLgAECgkJEQADAAAAAA==.Arte:BAABLgAECn89AAICAAkJaxOnLAABAgACAAkJaxOnLAABAgAAAA==.Arthundermis:BAAALgAECgkJEQAAAA==.Artlunarmis:BAAALgADCgEJAQABLgAECgkJEQADAAAAAA==.Arvena:BAABLgAECn8nAAISAAkJVgqDcgA5AQASAAkJVgqDcgA5AQAAAA==.',
As='Asclëpius:BAAALgADCgcJBgABLgAECgEJAQADAAAAAA==.Asheron:BAAALgAECgYJCAAAAA==.Ashylock:BAAALgAECgEJAQABLgAFFAUJDgAFAGAWAA==.Ashymage:BAACLgAFFH8OAAIFAAUJYBbPXQAvAQAFAAUJYBbPXQAvAQAuAAQKfzcAAgUACQlYHLYpAMwCAAUACQlYHLYpAMwCAAAA.Askevar:BAABLgAECn8gAAMLAAkJjQrjbwCCAQALAAkJuQjjbwCCAQATAAYJ5wlHJwAEAQAAAA==.Aspect:BAAALgADCgEJAQABLgAFFAIJAwADAAAAAA==.Asriél:BAAALgAECgQJBAAAAA==.Astor:BAAALgADCgMJBQAAAA==.Astrona:BAAALgADCgkJFwAAAA==.',
At='Atreus:BAABLgAECn8YAAINAAkJbAUEvgAIAQANAAkJbAUEvgAIAQAAAA==.Attalaguy:BAAALgAECgYJDgAAAA==.',
Au='Audra:BAAALgADCgcJDgAAAA==.',
Av='Avabeatrix:BAAALgADCgEJAQAAAA==.Avinthoro:BAAALgADCgIJAgAAAA==.',
Ay='Ayyayyron:BAAALgAECgUJCQAAAA==.',
Az='Azaleah:BAABLgAECn9IAAINAAkJQB1eGQCpAgANAAkJQB1eGQCpAgAAAA==.Azanoth:BAAALgADCgIJAgAAAA==.Azraesha:BAABLgAECn8rAAISAAkJ/BVzKQAhAgASAAkJ/BVzKQAhAgAAAA==.Azureflamez:BAAALgAECgEJAQAAAA==.Azurewraith:BAAALgAECgQJBAAAAA==.Azzul:BAAALgADCgcJBwAAAA==.',
Ba='Baiken:BAAALgAECgIJAgABLgAECgQJCAADAAAAAA==.Banjoman:BAABLgAECn8kAAIUAAcJXSSyCgC5AgAUAAcJXSSyCgC5AgAAAA==.Baza:BAAALgADCgYJBgAAAA==.Baýlei:BAABLgAECn8WAAIIAAYJ5A3jWAAGAQAIAAYJ5A3jWAAGAQAAAA==.',
Be='Beary:BAAALgAECgQJCAAAAA==.Beenaughty:BAAALgAECgEJAQABLgAECgEJAQADAAAAAA==.Belaanna:BAAALgADCgYJCQAAAA==.Beliria:BAAALgADCgUJBgAAAA==.Benimaru:BAAALgAECgUJDwAAAA==.Beriko:BAAALgAECgMJAwAAAA==.Bernat:BAAALgAECgEJAQAAAA==.Beàrdfáce:BAAALgADCgQJBAAAAA==.',
Bi='Bigblunt:BAAALgAECgEJAQAAAA==.Bigjuicy:BAAALgAECggJEAAAAA==.Billie:BAAALgAECgYJBgAAAA==.Bimboficate:BAAALgADCgYJBwAAAA==.',
Bl='Black:BAAALgAECgQJBAAAAA==.Blackadder:BAABLgAECn8aAAIRAAYJqgtfKgDDAAARAAYJqgtfKgDDAAAAAA==.Blessthefall:BAAALgAECgYJCgAAAA==.Blondie:BAAALgADCgQJBAABLgAECgYJEwADAAAAAA==.Bloodie:BAAALgAECgMJAwAAAA==.Blue:BAABLgAECn88AAIKAAkJxRuhDgBcAgAKAAkJxRuhDgBcAgAAAA==.Blueguy:BAAALgAECgEJAQAAAA==.Bluestreak:BAAALgAECgEJAwABLgAECgcJCQADAAAAAA==.',
Bo='Bobthefist:BAAALgADCgcJBwAAAA==.Bode:BAAALgAECgYJEwAAAA==.Bogern:BAAALgADCgcJBwAAAA==.Bolau:BAAALgADCgYJBwAAAA==.Boltz:BAAALgADCgYJBgAAAA==.Boogy:BAAALgAECgYJBgAAAA==.Bopdiz:BAAALgAECgEJAQABLgAECgQJEgADAAAAAA==.Borledish:BAAALgAECgMJBAABLgAECgQJEgADAAAAAA==.Bottosai:BAAALgAECgEJAgAAAA==.',
Br='Brambles:BAAALgAECgEJAQAAAA==.Branwynn:BAAALgAECgEJBgAAAA==.Breezyfight:BAAALgAFFAIJAgAAAA==.Breezysha:BAAALgADCgcJCAAAAA==.Brenz:BAABLgAFFH8GAAMNAAMJOQKvpABuAAANAAMJOwGvpABuAAARAAEJvQSRGwAhAAAAAA==.Brewdaddy:BAAALgAECgUJEwABLgAECgkJNAARAHwRAA==.Brewdude:BAAALgAECgEJAQAAAA==.Brigor:BAAALgAECgYJCgAAAA==.Brokenblade:BAAALgADCgYJBgAAAA==.Brotherblood:BAAALgAECgMJBgAAAA==.',
Bu='Bulldoza:BAAALgAECgQJBQAAAA==.Bullwinkles:BAAALgAECgEJAQAAAA==.Butterknifeo:BAABLgAFFH8FAAIVAAMJxxQXMAC8AAAVAAMJxxQXMAC8AAAAAA==.',
By='Byryja:BAABLgAECn8aAAIFAAYJQgYZ4QDVAAAFAAYJQgYZ4QDVAAAAAA==.',
Ca='Cahrazie:BAACLgAFFH8FAAINAAMJcQg7dwDAAAANAAMJcQg7dwDAAAAuAAQKfxkAAg0ACQlBE8pGAO8BAA0ACQlBE8pGAO8BAAAA.Caidinn:BAAALgAECgkJEQAAAA==.Caitrîn:BAAALgADCgkJCQABLgAECgYJFwAOADQOAA==.Calissancia:BAABLgAECn82AAIIAAgJNBeLHgAfAgAIAAgJNBeLHgAfAgAAAA==.Calkey:BAABLgAECn8WAAIBAAYJUQhpHgCyAAABAAYJUQhpHgCyAAAAAA==.Cathandris:BAAALgADCgEJAQAAAA==.',
Ce='Ceri:BAAALgAECgkJBwAAAA==.',
Ch='Chadarack:BAAALgAECgYJBwAAAA==.Chadaracks:BAAALgAECgEJAQAAAA==.Channingtotm:BAACLgAFFH8iAAIWAAUJLiXECgAWAgAWAAUJLiXECgAWAgAuAAQKfzYAAhYACQlhIWMEAG4DABYACQlhIWMEAG4DAAAA.Chantix:BAAALgADCgUJBQAAAA==.Charlemoo:BAAALgADCgUJBQABLgAECgMJAwADAAAAAA==.Cheekymonkey:BAABLgAECn8kAAIEAAkJIAthBQCAAQAEAAkJIAthBQCAAQAAAA==.Chrispbacon:BAAALgAECgUJDQAAAA==.Chueyé:BAAALgAECgMJAwABLgAFFAMJCQAXAO8dAA==.Chunkyy:BAAALgADCgYJBgAAAA==.Churros:BAABLgAECn8oAAMMAAkJlhtmEQBLAgAMAAkJlhtmEQBLAgAUAAcJThXLJgCKAQAAAA==.',
Ci='Cincog:BAAALgAECgQJBAABLgAECgYJCQADAAAAAA==.',
Cl='Closetcookie:BAAALgAECgQJBAAAAA==.',
Co='Coberren:BAAALgAECgEJAQAAAA==.Cordialkylie:BAAALgAECgIJAgAAAA==.Cowcrusader:BAAALgADCgcJBwAAAA==.',
Cr='Crazyugly:BAAALgAECgQJBQAAAA==.Crogrer:BAAALgAECgMJAwAAAA==.Crosslock:BAAALgAECgUJDgAAAA==.',
Cu='Cuppycakes:BAAALgADCgcJFAAAAA==.',
Cy='Cynnari:BAAALgAECgUJBQAAAA==.',
Da='Daddysecret:BAAALgAECgQJBQAAAA==.Dalan:BAAALgAECgIJAgABLgAFFAQJCgAEALYUAA==.Dalaris:BAACLgAFFH8GAAIYAAQJlQ2EEwAEAQAYAAQJlQ2EEwAEAQAuAAQKfyIAAhgACQmdFtwRAAsCABgACQmdFtwRAAsCAAAA.Danizmi:BAAALgADCgQJBAAAAA==.Dano:BAAALgADCgYJDQAAAA==.Darci:BAAALgAECgYJCwAAAA==.Darkeon:BAAALgAECgcJCwAAAA==.Darlenedark:BAAALgAECgEJAQAAAA==.Darling:BAAALgAECgIJAgAAAA==.Darron:BAAALgAECgEJAwABLgAECgcJCwADAAAAAA==.Darrosh:BAABLgAECn8bAAQZAAgJuxNUEgDjAAAZAAYJDhBUEgDjAAAXAAcJjQ3uPQDLAAAaAAMJ9hB8FAC1AAAAAA==.Dartian:BAAALgADCgcJDQABLgAECgkJLQACAE0XAA==.Dazdot:BAAALgADCgQJBAABLgAECgEJAQADAAAAAA==.Dazsham:BAAALgAECgEJAQAAAA==.',
De='Deathdevil:BAAALgAECgUJBQAAAA==.Deathlurker:BAAALgADCgQJBAAAAA==.Deathmare:BAAALgAECgUJBQAAAA==.Deathmommy:BAAALgAECgcJCAAAAA==.Deathty:BAAALgAECgMJCgABLgAFFAEJAgADAAAAAA==.Dementia:BAAALgADCgMJAwAAAA==.Design:BAABLgAECn8lAAIbAAkJ4RegMAAUAgAbAAkJ4RegMAAUAgAAAA==.Desmeridian:BAAALgAECgUJBQAAAA==.Devotee:BAAALgADCgIJAgAAAA==.',
Dh='Dhish:BAAALgAECgYJEAAAAA==.',
Di='Diltlish:BAAALgAECgMJBQAAAA==.Diocles:BAAALgAECgUJBgAAAA==.Disconcern:BAAALgAECgEJAQAAAA==.Discontent:BAACLgAFFH8GAAIcAAIJUR2bMQCOAAAcAAIJUR2bMQCOAAAuAAQKfxQAAxwABwnwHFcQAOkBABwABwnwHFcQAOkBAB0ABQknEVxuAP0AAAAA.Discordiä:BAABLgAECn8XAAIeAAgJHRcRHQDiAQAeAAgJHRcRHQDiAQAAAA==.Discspal:BAAALgAECgYJBwAAAA==.Diåblo:BAAALgADCgUJBQAAAA==.',
Dm='Dmginc:BAAALgADCgIJAgAAAA==.',
Do='Doeblin:BAAALgAECgUJEQAAAA==.Domidouse:BAAALgAECgQJBAAAAA==.Donkedixon:BAAALgADCgYJBgAAAA==.Doubtz:BAAALgAECgQJBQABLgAECgQJEgADAAAAAA==.',
Dp='Dpalx:BAAALgAECgQJBAAAAA==.Dpxs:BAABLgAFFH8HAAIWAAQJkhbRPQDlAAAWAAQJkhbRPQDlAAAAAA==.',
Dr='Dracaria:BAAALgAECgEJAQAAAA==.Dracones:BAAALgAECgYJDgAAAA==.Dragondz:BAAALgAECgUJBQAAAA==.Dragonflai:BAABLgAECn8mAAIFAAkJnBfgUQDjAQAFAAkJnBfgUQDjAQAAAA==.Dragonkin:BAAALgAECgQJCAAAAA==.Drakkari:BAAALgAECgYJDQAAAA==.Drakkei:BAABLgAECn9BAAMCAAkJphkIIwBUAgACAAkJphkIIwBUAgAGAAMJIgZiSACWAAAAAA==.Drerane:BAAALgADCgYJBgAAAA==.Drexxsster:BAAALgADCgQJBAAAAA==.Drshortbus:BAAALgAECgUJCQAAAA==.Drumitus:BAAALgADCgYJCAAAAA==.Drunkngrundl:BAABLgAECn89AAIJAAkJHiMJBAAHAwAJAAkJHiMJBAAHAwAAAA==.Drylo:BAECLgAFFH8JAAIfAAQJ6R7PHgBiAQAfAAQJ6R7PHgBiAQAuAAQKfy0AAx8ACQkmIGcJAMACAB8ACQmLHmcJAMACACAACAnFH6UGAIgCAAAA.',
Du='Duckeey:BAAALgAFFAEJAQABLgAFFAUJFAAFAKQOAA==.Dunstir:BAABLgAECn8ZAAINAAgJ6QWOvAAKAQANAAgJ6QWOvAAKAQAAAA==.Dusktrekker:BAAALgAECgkJBwAAAA==.',
Dy='Dypshyt:BAABLgAECn8aAAQfAAkJhxeXTgDvAAAgAAUJUBJRIgAYAQAfAAYJqxCXTgDvAAAhAAUJTgcBLgB1AAAAAA==.',
Ed='Edelweíss:BAAALgAECgQJCgAAAA==.',
Ek='Ekazzik:BAAALgAECgYJBgABLgAECggJFgACAEoaAA==.Ekoh:BAAALgAECgIJAgAAAA==.',
El='Elarol:BAAALgAECgEJAgAAAA==.Eldons:BAAALgADCgIJAgAAAA==.',
Em='Embers:BAABLgAECn8WAAIdAAYJGxObVwDuAAAdAAYJGxObVwDuAAAAAA==.Emeralde:BAAALgAECgYJCgAAAA==.Emilia:BAAALgADCgIJAwAAAA==.Emptyhands:BAAALgAECgYJBgAAAA==.Emptyheals:BAABLgAECn8xAAIeAAkJ3yCVBABHAwAeAAkJ3yCVBABHAwAAAA==.',
Er='Ereada:BAAALgADCgUJCgAAAA==.Erfinden:BAAALgADCgEJAQAAAA==.',
Es='Espernite:BAAALgAECgQJBAAAAA==.Espers:BAABLgAECn8fAAIVAAkJ6Q8JPQAYAQAVAAkJ6Q8JPQAYAQAAAA==.',
Et='Ethellin:BAABLgAECn8xAAINAAkJgAUlpQAtAQANAAkJgAUlpQAtAQAAAA==.',
Fa='Fahrenheit:BAAALgAECgEJAgAAAA==.Farkuat:BAAALgADCgQJBAAAAA==.Fatcastle:BAAALgADCgcJDgAAAA==.',
Fe='Feedmepizzas:BAAALgAECgMJCAAAAA==.Feildmedic:BAAALgAECgEJAQAAAA==.Feleria:BAAALgAECgUJDAAAAA==.Fellslasher:BAAALgAECgIJAgAAAA==.Felmage:BAAALgADCgYJBgAAAA==.Felraiser:BAAALgADCgIJAgABLgADCgUJBgADAAAAAA==.Felwinter:BAABLgAECn81AAIbAAkJthozIQBcAgAbAAkJthozIQBcAgAAAA==.Femcelgoon:BAAALgADCgEJAQAAAA==.Fenna:BAAALgADCgYJDAAAAA==.Fetor:BAAALgAECgcJEAAAAA==.',
Fi='Finwé:BAAALgAECgQJCQAAAA==.Fistsalot:BAAALgAECgQJCAAAAA==.',
Fl='Flafferthorn:BAAALgADCgcJDgAAAA==.Fluxarata:BAABLgAECn8qAAISAAkJiA3YUwCHAQASAAkJiA3YUwCHAQAAAA==.',
Fo='Forthememes:BAAALgAECgcJCQAAAA==.',
Fr='Fred:BAABLgAECn8sAAIdAAgJhQoCPABVAQAdAAgJhQoCPABVAQAAAA==.Freddrick:BAAALgADCgQJBAAAAA==.Friendly:BAAALgAECgEJAQAAAA==.Frostbuddy:BAAALgAECgcJDQAAAA==.Frëya:BAAALgADCgYJDQAAAA==.Frío:BAAALgAECgEJAQAAAA==.Frøstitute:BAABLgAECn8pAAIFAAkJ+hbwMwBGAgAFAAkJ+hbwMwBGAgAAAA==.',
Fu='Fullmage:BAAALgADCgQJBAAAAA==.',
['Fè']='Fènrïr:BAAALgADCgQJBAAAAA==.',
Ga='Gabel:BAABLgAECn8mAAIiAAkJQh2mBgB1AgAiAAkJQh2mBgB1AgAAAA==.Gadnabit:BAAALgADCgkJCQAAAA==.Gailardia:BAABLgAECn8kAAICAAcJ/x1FLgAfAgACAAcJ/x1FLgAfAgABLgAFFAQJEwAUAAkZAA==.Galand:BAABLgAECn8iAAMLAAYJ+h6DbgCFAQALAAYJdB6DbgCFAQATAAIJoiFWTwBTAAAAAA==.Galladin:BAAALgADCggJDgAAAA==.Gardyson:BAABLgAECn8WAAMjAAcJUhWWGgBhAQAjAAcJUhWWGgBhAQAdAAEJbQNKtAAhAAABLgAECggJFgACAEoaAA==.Gazton:BAAALgAECgUJBQAAAA==.',
Gl='Glaaki:BAAALgAECgUJCwAAAA==.',
Gn='Gnob:BAAALgAECgQJCAAAAA==.',
Go='Gooblet:BAAALgADCgQJBQAAAA==.Goodfellow:BAAALgAECgEJAQABLgAECgYJFQAiAMUcAA==.Goopy:BAAALgADCgYJAwAAAA==.',
Gr='Graendal:BAAALgADCgQJBAAAAA==.Granite:BAAALgAECgMJBAAAAA==.Granted:BAAALgADCgUJBQAAAA==.Greevil:BAAALgAECgEJAwAAAA==.Gremilien:BAABLgAECn8mAAIQAAkJSBIOCgDMAQAQAAkJSBIOCgDMAQAAAA==.Grimgorr:BAAALgADCgMJAwAAAA==.Grimmly:BAAALgAECgEJAQAAAA==.Grymdevours:BAAALgADCgYJBgAAAA==.',
Ha='Halcyonic:BAAALgAECgUJCgAAAA==.Halleyscomet:BAABLgAECn8WAAINAAcJPBptRAAXAgANAAcJPBptRAAXAgAAAA==.Happyhammer:BAAALgADCgcJCAAAAA==.Harrod:BAAALgAECggJCwAAAA==.Hawkwave:BAAALgAECgcJEgABLgAECgkJEQADAAAAAA==.Hazardzone:BAAALgAECgMJCgAAAA==.',
He='Heavyweather:BAAALgADCgcJBwAAAA==.Hefty:BAABLgAECn8XAAMGAAkJ3QuxKABbAQAGAAcJKQuxKABbAQACAAUJ8gmioAD6AAAAAA==.Heftyer:BAAALgAECgMJAwAAAA==.Helioween:BAAALgADCgMJAwAAAA==.Helixon:BAAALgADCgYJBgAAAA==.Hellbad:BAACLgAFFH8MAAIJAAQJ7hPPJwAGAQAJAAQJ7hPPJwAGAQAuAAQKfxUAAwkACAleGEcnAHMBAAoABgmOG30jALoBAAkACAkXEkcnAHMBAAAA.Hellbine:BAAALgADCgMJAgAAAA==.Hellfella:BAAALgAECgEJAQAAAA==.Hellonheels:BAAALgAECgQJBAAAAA==.Hellsspawn:BAAALgAECgYJCQAAAA==.Hexaverse:BAAALgADCgYJBgABLgAECgQJBAADAAAAAA==.',
Ho='Hoardwither:BAAALgAECgEJAgAAAA==.Hoenheim:BAAALgAECgEJAQAAAA==.Hogrog:BAAALgADCgMJAwAAAA==.Hokàge:BAACLgAFFH8JAAIXAAMJ7x3GIwD9AAAXAAMJ7x3GIwD9AAAuAAQKfzkABBcACQkpIrgIAJgCABcACQkpIrgIAJgCABoAAgkCGrwaAIwAABkAAQkZAkUrAAkAAAAA.Holyballs:BAAALgAECgQJBwAAAA==.Homealone:BAABLgAECn8YAAMWAAcJZwlGegDrAAAWAAYJ/QZGegDrAAAkAAUJ8gNoewB4AAAAAA==.',
Hu='Huffles:BAAALgAECgQJBwAAAA==.Hugmachine:BAAALgAFFAIJAgAAAA==.Huntinfuzzy:BAAALgAECgkJDwAAAA==.Huntn:BAAALgADCggJCAAAAA==.',
Hy='Hypahypa:BAAALgAECggJCAAAAA==.',
Ia='Iamknot:BAAALgAECgQJBgAAAA==.',
Ic='Icemommy:BAAALgADCgQJCAAAAA==.',
Ig='Igothots:BAACLgAFFH8FAAIPAAIJZBDlUwBvAAAPAAIJZBDlUwBvAAAuAAQKfx4AAw8ACQl/HgIQALgCAA8ACQl/HgIQALgCACIAAQltCQFWACkAAAAA.',
Il='Illariana:BAABLgAECn8aAAQMAAgJNRKmKwB1AQAMAAgJNRKmKwB1AQAUAAEJwQLreAAfAAAeAAEJvgGRhwAdAAAAAA==.Illirotica:BAAALgAECgcJCQAAAA==.',
In='Incredibro:BAAALgADCgEJAQAAAA==.Insanitty:BAAALgAECgcJDwAAAA==.Invincible:BAAALgAECgEJAQABLgAECgYJHAAIALcjAA==.',
Ir='Ironlobo:BAABLgAECn8YAAIFAAYJhxlxegCAAQAFAAYJhxlxegCAAQAAAA==.Ironsolari:BAAALgADCgYJBgAAAA==.Irritable:BAABLgAECn8iAAMlAAgJZxvzBABAAgAlAAgJZxvzBABAAgAbAAEJJRekHgFGAAAAAA==.',
It='Itherious:BAAALgAECgUJDgAAAA==.',
Ja='Jacham:BAABLgAECn8WAAIdAAkJ2hTxHgD2AQAdAAkJ2hTxHgD2AQAAAA==.Jackyll:BAAALgAECgQJCAAAAA==.Jagerboy:BAAALgAECgYJBgAAAA==.Jango:BAAALgAECgIJAgABLgAECggJFgACAEoaAA==.Jatix:BAACLgAFFH8NAAINAAQJjx4ZKQBgAQANAAQJjx4ZKQBgAQAuAAQKfyoAAg0ACQkcI/EOAOwCAA0ACQkcI/EOAOwCAAAA.',
Je='Jeetkundo:BAAALgADCgEJAQABLgAECgYJHAAIALcjAA==.Jellydh:BAAALgAECgIJBAAAAA==.Jellymagus:BAAALgAECgIJAgAAAA==.Jellyms:BAAALgAECgYJDQAAAA==.Jellyspinoff:BAAALgAECgMJBwAAAA==.Jellytown:BAABLgAECn89AAIFAAkJaxQyRAAMAgAFAAkJaxQyRAAMAgAAAA==.Jelorinea:BAAALgAECgMJAwAAAA==.Jessiana:BAAALgAECgQJCAAAAA==.Jezelda:BAAALgAECgQJBgAAAA==.',
Jp='Jpeppers:BAAALgAECgYJEwAAAA==.',
Ju='Jumano:BAAALgAECgUJCgAAAA==.Jundra:BAAALgAECgUJCgAAAA==.Jurih:BAAALgADCgIJAgAAAA==.',
Ka='Kaineh:BAABLgAECn8oAAIQAAgJah2yBQBAAgAQAAgJah2yBQBAAgAAAA==.Kainë:BAAALgADCgIJAgAAAA==.Kait:BAABLgAECn8+AAICAAkJ6R+SEADIAgACAAkJ6R+SEADIAgAAAA==.Kaladil:BAAALgAECgcJDgAAAA==.Kamis:BAAALgAECgMJAwAAAA==.Kanaga:BAAALgAECgQJBQAAAA==.Kannan:BAABLgAECn8YAAMSAAgJzxv/LwA8AgASAAgJzxv/LwA8AgAYAAEJAQdWeQAqAAAAAA==.Kashmihhr:BAAALgADCgIJAgAAAA==.Kashmir:BAAALgAECgQJBAAAAA==.Kasmes:BAAALgADCggJGQAAAA==.Kasmius:BAAALgAECgMJAwAAAA==.Kasmus:BAAALgAECgQJCAAAAA==.Kawdor:BAABLgAECn80AAQRAAkJfBGTFwBgAQARAAgJ2xCTFwBgAQAmAAcJNw+7PQBMAQANAAMJ8woOOgFtAAAAAA==.',
Ke='Keetsz:BAAALgAECgYJDAAAAA==.Kelaino:BAAALgADCgQJBQAAAA==.Keledish:BAAALgADCgEJAQAAAA==.',
Kh='Khansmebduke:BAACLgAFFH8FAAMYAAQJNxYlGADZAAAYAAMJkRklGADZAAASAAEJKgzEmQA9AAAuAAQKfxYAAxgACAmlHMAVANoBABIACAk1F1w+APsBABgABwlXHcAVANoBAAEuAAUUBQkJACIAjh4A.',
Ki='Kiaf:BAAALgADCgcJDQAAAA==.Kiba:BAAALgADCgEJAQAAAA==.Killanick:BAAALgAECgEJAQAAAA==.Killdar:BAAALgAECgQJBAAAAA==.Kimia:BAAALgADCgYJCQAAAA==.Kirtthedirt:BAAALgAECgYJBwAAAA==.Kirtthehurt:BAABLgAECn8pAAIFAAkJShiZLwBYAgAFAAkJShiZLwBYAgAAAA==.',
Ko='Koldfront:BAAALgAECgUJCwAAAA==.Kollinator:BAAALgAECgYJDgAAAA==.Korso:BAAALgADCgUJCwABLgAECgYJFwAOADQOAA==.Kotal:BAAALgAECgEJAQAAAA==.',
Ky='Kylair:BAABLgAECn80AAIMAAkJ/B7iCQCwAgAMAAkJ/B7iCQCwAgAAAA==.Kynreessa:BAAALgADCgYJCAAAAA==.Kyyell:BAAALgAECgYJBgAAAA==.Kyønshi:BAAALgADCgUJBgAAAA==.',
['Kì']='Kìrito:BAAALgAECgcJDgAAAA==.',
La='Labeya:BAAALgADCgMJAwAAAA==.Lafty:BAAALgAFFAEJAgAAAA==.Laftydh:BAAALgAECgYJEgABLgAFFAEJAgADAAAAAA==.Lailah:BAAALgADCgIJAgABLgAECgkJSAANAEAdAA==.Laine:BAAALgADCgMJAwAAAA==.Landrra:BAAALgAECgQJBAAAAA==.Larac:BAAALgAECggJEwAAAA==.Lathsong:BAAALgADCgYJDwAAAA==.Lavi:BAAALgADCgQJAwAAAA==.',
Le='Leadge:BAAALgADCgYJBwAAAA==.Lenik:BAABLgAECn8aAAIXAAYJ+gkUNwDyAAAXAAYJ+gkUNwDyAAAAAA==.Leskya:BAAALgADCgQJAwAAAA==.',
Li='Libras:BAAALgADCgMJAwAAAA==.Licorice:BAAALgAECgUJDgABLgAECgkJKAAMAJYbAA==.Lieree:BAABLgAECn8XAAIFAAgJUg3kgAByAQAFAAgJUg3kgAByAQAAAA==.Lifeguàrd:BAAALgAECgkJBwAAAA==.Lillana:BAAALgADCgcJDQAAAA==.Lilrayne:BAAALgADCgYJBgABLgAECgkJGwAGAIoPAA==.Lilyfaye:BAAALgADCgkJDAAAAA==.Limosfire:BAABLgAECn8VAAIQAAYJkAMpJACOAAAQAAYJkAMpJACOAAAAAA==.Linsatha:BAAALgAECggJEAAAAA==.',
Lo='Loa:BAAALgADCgYJBwAAAA==.Lockty:BAAALgAECgIJBgABLgAFFAEJAgADAAAAAA==.Logi:BAAALgADCgYJCwAAAA==.Lorezever:BAAALgADCgcJDQAAAA==.Lotion:BAAALgADCgIJAgAAAA==.',
Lu='Luar:BAAALgAECgYJDQAAAA==.Lulubean:BAAALgADCgMJBAAAAA==.Lunaris:BAAALgADCgQJBAAAAA==.Lungorthin:BAAALgAECgQJBAAAAA==.Lunà:BAABLgAECn8aAAIBAAcJwwOlIgCXAAABAAcJwwOlIgCXAAAAAA==.',
Ly='Lythalle:BAAALgAECgEJAQAAAA==.Lythwynn:BAABLgAECn8rAAINAAkJhQ8BcQCJAQANAAkJhQ8BcQCJAQAAAA==.',
['Lá']='Lásh:BAAALgAECgUJCAABLgAECgYJFwAOADQOAA==.',
Ma='Mace:BAAALgAECgEJAQAAAA==.Madison:BAAALgAECgEJAQAAAA==.Magdolyn:BAAALgADCgMJAwAAAA==.Mageyboi:BAAALgAECgQJBgABLgAFFAMJCQAXAO8dAA==.Magickul:BAAALgAECgYJDAAAAA==.Magleon:BAAALgADCgIJAgAAAA==.Magonk:BAAALgADCgEJAQAAAA==.Mahano:BAABLgAECn8WAAICAAgJShogHgBtAgACAAgJShogHgBtAgAAAA==.Makis:BAAALgAECgMJBQAAAA==.Malachi:BAAALgAECgYJBgAAAA==.Manavoid:BAABLgAECn8cAAISAAYJkAp6pQDVAAASAAYJkAp6pQDVAAAAAA==.Mandragore:BAAALgAECgIJBAAAAA==.Massili:BAAALgADCgkJGgAAAA==.Mastor:BAAALgADCgQJBwAAAA==.Maynard:BAABLgAECn8hAAIIAAkJ9xEKLgC+AQAIAAkJ9xEKLgC+AQAAAA==.',
Mc='Mcdouble:BAAALgADCgMJAwAAAA==.',
Me='Meldanis:BAAALgAECgQJBAAAAA==.Meri:BAABLgAECn8cAAIPAAgJlxwrJgAfAgAPAAgJlxwrJgAfAgAAAA==.',
Mi='Miande:BAABLgAECn8VAAIlAAcJ0xeDCgCzAQAlAAcJ0xeDCgCzAQAAAA==.Microburst:BAAALgADCgcJCwAAAA==.Minecraft:BAAALgAECgIJAgAAAA==.Minilock:BAABLgAECn8sAAMbAAkJeQ45UACqAQAbAAkJUA05UACqAQABAAUJTg4IHgC1AAAAAA==.Misogynixy:BAAALgADCgQJBAAAAA==.Missdeeds:BAAALgAECgUJBQAAAA==.Missleading:BAAALgAECgYJCQAAAA==.Missused:BAAALgAECgYJEgAAAA==.Mithos:BAAALgAECgUJBwAAAA==.Mithraxa:BAAALgAECgQJBAAAAA==.Miyagifu:BAAALgADCgQJBAAAAA==.',
Mo='Moash:BAAALgADCgkJCQAAAA==.Modsagoodtnk:BAAALgAECgcJEAABLgAECggJLAACAH8ZAA==.Mongermook:BAABLgAECn8eAAMOAAkJ+QmdLQDyAAAOAAkJ+QmdLQDyAAAVAAEJxgFpkQAVAAAAAA==.Monnkysham:BAAALgAECgQJBgABLgAECgYJCQADAAAAAA==.Moogledragon:BAAALgADCgMJAwAAAA==.Mooglefur:BAAALgAECgQJBQAAAA==.Moonbloom:BAABLgAECn8cAAIPAAgJQhz3HgBLAgAPAAgJQhz3HgBLAgAAAA==.Morgrim:BAAALgAECgEJAQAAAA==.Morlosh:BAAALgAECgMJAwAAAA==.Moryna:BAABLgAECn8tAAIcAAgJ4wdXMAADAQAcAAgJ4wdXMAADAQAAAA==.',
Mt='Mthrandir:BAAALgADCgUJBQAAAA==.',
Mu='Muford:BAAALgAECgQJBQABLgAFFAcJFAAJAFMfAA==.Mull:BAAALgAECgYJEwAAAA==.Muloc:BAAALgADCgEJAQAAAA==.',
My='Myaka:BAAALgAECgYJBgAAAA==.Mythicc:BAAALgADCgQJBAAAAA==.',
Na='Naatixa:BAAALgAECggJDAAAAA==.Nacronor:BAAALgAECgUJDgAAAA==.Naiika:BAAALgAECgYJBwAAAA==.Nascha:BAAALgADCgEJAQAAAA==.Nasoj:BAAALgAECgYJCQABLgAECgYJEwADAAAAAA==.',
Ne='Necrotic:BAAALgAECgQJBAAAAA==.Nedalla:BAAALgAECgYJCwAAAA==.Neeve:BAAALgAECgEJAQAAAA==.Nekrotik:BAAALgADCgcJBgAAAA==.Neobahamut:BAAALgADCgEJAQABLgAECgcJDgADAAAAAA==.Netharel:BAAALgADCgIJAgAAAA==.Newports:BAAALgAECgEJAQAAAA==.',
Ni='Nichôlasmage:BAAALgAECgYJCwAAAA==.Nickatnite:BAAALgAFFAEJAQAAAA==.Nickelodeon:BAAALgAFFAIJAwAAAA==.Nicksaban:BAABLgAECn8mAAINAAkJOBuoLQBIAgANAAkJOBuoLQBIAgAAAA==.Nightgear:BAACLgAFFH8wAAMCAAgJaBdHDQDvAQACAAcJehlHDQDvAQAQAAIJ/AqvMwBJAAAuAAQKf1kAAwIACQm1IgUIABADAAIACQm1IgUIABADABAABAnfEu8iAJcAAAAA.Nightshades:BAAALgADCgQJBAAAAA==.Nilux:BAAALgAECgYJDwAAAA==.Ninetails:BAAALgAECgUJCgAAAA==.Niteshadeth:BAAALgAECgQJBAAAAA==.Niteyknight:BAAALgAECgQJBAAAAA==.Nixeava:BAABLgAECn8ZAAIkAAYJCQUOaACqAAAkAAYJCQUOaACqAAAAAA==.',
No='Nogooddruid:BAAALgAECgUJDAAAAA==.Nopetsneeded:BAABLgAECn89AAIQAAkJzBQ2CAD3AQAQAAkJzBQ2CAD3AQAAAA==.Norepairbill:BAAALgAECgEJAQABLgAECgkJPQAQAMwUAA==.Nostariel:BAAALgAECgMJBgAAAA==.Notadoctor:BAAALgAECgYJCAAAAA==.Noteworthy:BAAALgAECgYJEgABLgAFFAYJDwALAN0dAA==.',
Ny='Nysong:BAABLgAECn8wAAMBAAgJAAo8FAAIAQABAAgJAAo8FAAIAQAbAAMJYwKsEwFRAAAAAA==.',
['Nó']='Nórin:BAAALgAECgUJBQAAAA==.',
Ob='Obali:BAAALgADCgQJCAAAAA==.',
Od='Oddangel:BAAALgAECgYJEwAAAA==.Ode:BAAALgAECgcJCgAAAA==.Odex:BAABLgAECn8qAAMgAAkJbw1jCACoAQAgAAkJbw1jCACoAQAfAAEJpgiqjQA6AAAAAA==.',
Oh='Ohblergen:BAAALgAECgIJAgAAAA==.',
Ok='Okragren:BAABLgAECn81AAIkAAkJhwyNMgBvAQAkAAkJhwyNMgBvAQAAAA==.',
Ol='Olehi:BAAALgADCgcJBwAAAA==.Olynder:BAAALgAECgIJBAAAAA==.',
On='Onos:BAABLgAECn8bAAICAAcJIyQ4IABEAgACAAcJIyQ4IABEAgAAAA==.Onto:BAAALgADCgEJAQAAAA==.Ontoquas:BAAALgADCgkJCgAAAA==.',
Or='Orinin:BAAALgADCgkJDwABLgAECgQJCAADAAAAAA==.',
Pa='Paleclaw:BAAALgADCgQJBAAAAA==.Pally:BAAALgAECgUJBQAAAA==.Papasmurfz:BAAALgAECgEJAwAAAA==.Paramedic:BAAALgAECgQJDAAAAA==.Pathogen:BAABLgAECn8hAAILAAkJDR9IOgAVAgALAAkJDR9IOgAVAgAAAA==.',
Pe='Penryn:BAAALgAECgQJBAAAAA==.Pepster:BAABLgAECn8XAAInAAkJpQGtLQCAAAAnAAkJpQGtLQCAAAAAAA==.Persephoknee:BAAALgADCgEJAQAAAA==.',
Pf='Pfchen:BAAALgAECgIJAwAAAA==.',
Pl='Plaguestrip:BAAALgAECgEJAQAAAA==.Plinkerbell:BAAALgADCgcJBgAAAA==.Plumprnickel:BAAALgAECgEJAQAAAA==.Plxkingg:BAAALgADCgUJBQAAAA==.',
Po='Porimma:BAAALgAECgYJDwAAAA==.Pormas:BAAALgAECgYJDwAAAA==.Poseydon:BAAALgADCgQJBAABLgAECgEJAQADAAAAAA==.',
Pr='Prayerz:BAAALgADCgMJAwAAAA==.Proctology:BAAALgAECgQJBAAAAA==.Prom:BAAALgAECgUJCAAAAA==.Promethèus:BAAALgAECgQJBAAAAA==.Prosby:BAAALgADCgIJAgAAAA==.Prowlnfool:BAAALgADCgUJBQAAAA==.Pryto:BAAALgADCgkJDgABLgAFFAIJAwADAAAAAA==.',
Qu='Queedle:BAABLgAECn8cAAIZAAkJWAn7CgBsAQAZAAkJWAn7CgBsAQAAAA==.',
Ra='Raennis:BAAALgAECgIJAgAAAA==.Ragalstan:BAAALgAECgEJAgAAAA==.Rahanumn:BAABLgAECn8YAAINAAgJ6wlroAA0AQANAAgJ6wlroAA0AQAAAA==.Rainlette:BAAALgAECgYJDAAAAA==.Rainsvoker:BAACLgAFFH8jAAIhAAYJXQ0JEgBrAQAhAAYJXQ0JEgBrAQAuAAQKf1IAAyEACQkOHJ0GAJQCACEACQkOHJ0GAJQCAB8ABgk7CORbAMIAAAAA.Ramike:BAAALgAECggJCQAAAA==.Raqtar:BAAALgAECgIJAgABLgAECgkJEQADAAAAAA==.Ratrazarke:BAAALgADCgIJAgAAAA==.Razihel:BAAALgADCgYJCQAAAA==.',
Re='Reaver:BAAALgAECgQJBAAAAA==.Reddan:BAABLgAECn8qAAINAAgJlgwumABBAQANAAgJlgwumABBAQAAAA==.Renata:BAAALgAFFAIJAgAAAA==.Replicant:BAAALgAECgEJAQAAAA==.Retman:BAAALgAECgMJAQAAAA==.Reverìe:BAAALgAECgcJBwAAAA==.Reylinn:BAAALgAECgQJBAAAAA==.Reyra:BAAALgAECgEJAQAAAA==.Reï:BAABLgAECn8dAAIPAAkJUBRSJAAmAgAPAAkJUBRSJAAmAgAAAA==.',
Ri='Ridlei:BAAALgAECgMJBAAAAA==.Rimchester:BAAALgAECgIJAQAAAA==.Ritzon:BAABLgAECn89AAMdAAkJJSQ0BgD6AgAdAAkJJSQ0BgD6AgAcAAEJmBembgA/AAAAAA==.',
Ro='Rosadita:BAAALgAECgQJBAAAAA==.Roxydan:BAABLgAECn8dAAMBAAgJiQ03KQAdAQAbAAgJiQ1KZwCWAQABAAYJ8Ag3KQAdAQAAAA==.',
Ru='Runastalis:BAAALgADCgYJBgAAAA==.',
Ry='Ryko:BAABLgAECn8fAAInAAcJqBQYFwBOAQAnAAcJqBQYFwBOAQAAAA==.',
Sa='Sanandume:BAAALgADCgEJAQAAAA==.Sanctess:BAAALgAECggJDgAAAA==.Sankai:BAAALgAECgEJAQABLgAECgYJDgADAAAAAA==.Sarlas:BAAALgADCgQJBAAAAA==.Sarumanpally:BAAALgAECgYJBwAAAA==.Sayomi:BAAALgADCgcJEwAAAA==.',
Se='Secretjuice:BAAALgAECgYJCQAAAA==.Senseijundra:BAAALgAECgQJCAAAAA==.Sentinaal:BAAALgADCgcJBwAAAA==.',
Sh='Shabadu:BAAALgADCgQJBAAAAA==.Shadyandi:BAAALgADCgcJCAAAAA==.Shamanhack:BAAALgAFFAIJAwAAAA==.Shan:BAAALgADCgYJBgAAAA==.Sharazad:BAAALgAECgUJBgAAAA==.Sheda:BAAALgAECgQJBAAAAA==.Shedia:BAAALgADCgYJCQAAAA==.Shmoove:BAEALgAECgUJBgAAAA==.Shmooves:BAEALgAECgQJBAABLgAECgUJBgADAAAAAA==.Shoukei:BAAALgADCgIJAwAAAA==.',
Si='Sianna:BAAALgADCgYJBgAAAA==.Siinful:BAAALgAECgEJAQAAAA==.Simbruh:BAAALgADCgMJAwAAAA==.Sinarria:BAAALgAECgEJAQAAAA==.Sithra:BAAALgADCgEJAQAAAA==.',
Sk='Skeemer:BAAALgAECgUJBQAAAA==.Skeetro:BAAALgAECgEJAQAAAA==.Skips:BAAALgAECgQJCQAAAA==.Skullace:BAABLgAECn8qAAIBAAkJuw8CCgCiAQABAAkJuw8CCgCiAQAAAA==.Skullhead:BAAALgADCgEJAQAAAA==.Skybreaker:BAAALgAECgkJCAAAAA==.',
Sm='Smashurfacen:BAAALgADCgcJFAAAAA==.',
Sn='Snitbit:BAAALgADCgkJGgAAAA==.Sno:BAAALgADCgEJAQABLgAECgUJBwADAAAAAA==.Snoopingas:BAAALgADCgIJAgAAAA==.Snpcrklpopu:BAAALgADCgYJCAAAAA==.',
So='Solarana:BAAALgAECgkJCQAAAA==.Sortiebatoru:BAAALgAECgIJAgAAAA==.Sotzi:BAAALgADCggJEQAAAA==.Souldune:BAAALgAECgYJBgAAAA==.',
Sp='Sparkplugg:BAAALgAECgEJAQAAAA==.',
Sr='Srfreaky:BAAALgAECgUJDgAAAA==.',
St='Stevejabbs:BAABLgAECn8cAAMIAAYJtyMtFgBjAgAIAAYJtyMtFgBjAgAJAAMJ5SB0OAAYAQAAAA==.Stormcunning:BAABLgAECn8WAAIkAAYJCAxiTAAWAQAkAAYJCAxiTAAWAQAAAA==.Stormfire:BAAALgADCgcJBwAAAA==.Stormßringer:BAABLgAECn8UAAIkAAgJERDXMwCJAQAkAAgJERDXMwCJAQAAAA==.Stownr:BAAALgAECgYJBgAAAA==.Strip:BAAALgADCgUJCAAAAA==.Strongclaw:BAAALgADCgUJBQAAAA==.Stumpyborg:BAABLgAECn8VAAQBAAcJaAZGMQBWAAAbAAYJNgSd2wCgAAABAAIJMwtGMQBWAAAlAAEJhAdmQQArAAABLgAECgkJFwAGAN0LAA==.Stónéhëárt:BAAALgADCgYJBwABLgAECgkJEQADAAAAAA==.',
Su='Subdue:BAAALgADCgQJBAAAAA==.Subverse:BAAALgAECgQJBAAAAA==.Sundance:BAAALgAECgcJDgAAAA==.Sune:BAABLgAECn8gAAMMAAYJxgvPRgDxAAAMAAYJxgvPRgDxAAAeAAEJNwlyfwAqAAAAAA==.Supplicant:BAAALgADCgQJBwAAAA==.',
Sv='Svellulfr:BAAALgAECgEJAQAAAA==.Svuca:BAAALgADCgcJBwAAAA==.',
Sy='Sydneyweenie:BAAALgADCgcJCAAAAA==.Syldi:BAAALgAECgEJAQABLgAECgYJHAAUAPYbAA==.Sythis:BAAALgAECgIJAwAAAA==.',
['Sä']='Sästa:BAAALgADCgkJCQAAAA==.',
['Sö']='Sörren:BAABLgAECn8aAAIlAAYJEAXWHQDMAAAlAAYJEAXWHQDMAAAAAA==.',
Ta='Tacosdeasada:BAAALgAECgEJAQAAAA==.Taitertot:BAAALgADCgQJBQAAAA==.Tanelórn:BAAALgAECgQJBQAAAA==.Tanlon:BAAALgAECgcJCwAAAA==.Taykorra:BAAALgADCggJDQAAAA==.',
Te='Telandril:BAABLgAECn8vAAIPAAkJvxGpMwDMAQAPAAkJvxGpMwDMAQAAAA==.Telphin:BAAALgAECgYJCwAAAA==.Tempestira:BAAALgAECgEJAgAAAA==.Tensuken:BAABLgAECn8ZAAINAAYJpBh/rAAiAQANAAYJpBh/rAAiAQAAAA==.Teylonna:BAAALgAECgEJAQAAAA==.',
Th='Thadgun:BAAALgADCgkJFQAAAA==.Thadium:BAAALgADCgYJCQAAAA==.Thalgan:BAAALgAECgEJAQAAAA==.Thalyn:BAAALgAECgEJAQAAAA==.Thecword:BAAALgADCgYJBgAAAA==.Themedic:BAABLgAECn8XAAMWAAcJxRDXUABqAQAWAAcJxRDXUABqAQAkAAEJ6gFbwAAXAAAAAA==.Theremar:BAAALgAECgMJAwAAAA==.Thergothon:BAAALgAECgEJAQABLgAECgMJAwADAAAAAA==.Thisisdrexx:BAAALgAECgIJAwAAAA==.Thorwrath:BAAALgADCgEJAgAAAA==.Thrazoro:BAAALgAECgQJBAAAAA==.Thrazzoro:BAAALgAECgYJEwAAAA==.',
Ti='Tiarl:BAABLgAECn81AAIUAAkJHRdWEQBUAgAUAAkJHRdWEQBUAgAAAA==.Tiia:BAAALgADCgIJAgAAAA==.Timex:BAABLgAECn8XAAMgAAYJRCD5DgDrAQAgAAYJRCD5DgDrAQAfAAEJUhfjiwA+AAAAAA==.Tinydots:BAAALgADCgUJBQAAAA==.Tinysitril:BAAALgAECgYJCQABLgAFFAQJBgAYAJUNAA==.Tinysohei:BAAALgAECgMJAwAAAA==.Titañick:BAAALgAECgEJAwAAAA==.',
To='Tom:BAABLgAECn8WAAMfAAYJLgugVQDWAAAfAAYJLgugVQDWAAAgAAEJZQitJgAvAAAAAA==.Toosxyfohair:BAABLgAECn8VAAIWAAcJ5hJYPgCwAQAWAAcJ5hJYPgCwAQAAAA==.',
Tr='Trainwrekk:BAAALgADCgYJBgAAAA==.Tranqar:BAAALgAECgQJBgAAAA==.Tresg:BAAALgAECgYJCQAAAA==.Trissandra:BAAALgAECgEJAQAAAA==.Trolltoll:BAAALgADCgEJAwAAAA==.Trüth:BAAALgADCggJEAAAAA==.',
Tw='Twylidan:BAEALgAECgkJCgABLgAFFAQJCQAfAOkeAA==.',
Ty='Tyrannt:BAAALgAECgEJAQAAAA==.Tyrannus:BAAALgADCgYJBgAAAA==.Tyregar:BAAALgAECgEJAQAAAA==.Tyrànda:BAAALgAECgEJAQAAAA==.Tyzy:BAAALgAECgEJAgAAAA==.',
['Tö']='Tötém:BAAALgAECgEJAQAAAA==.',
Ul='Ulanhi:BAABLgAECn8VAAIiAAUJzh31EACdAQAiAAUJzh31EACdAQAAAA==.',
Un='Undeadjelly:BAAALgAECgYJEwAAAA==.Unholy:BAAALgAECgYJDwAAAA==.',
Ur='Urkzul:BAAALgADCgMJAwAAAA==.Ursoth:BAAALgADCgUJCgAAAA==.',
Ut='Uthèrsmight:BAAALgAECgYJBgAAAA==.Uti:BAAALgADCgUJBQAAAA==.',
Uu='Uubs:BAAALgADCgEJAQABLgAFFAMJCgANAJoSAA==.',
Va='Valakk:BAAALgAECgIJBQAAAA==.Vallak:BAAALgADCgIJBAAAAA==.Valsitril:BAAALgAECgYJEAABLgAFFAQJBgAYAJUNAA==.Valthaczar:BAAALgAECgMJBgAAAA==.Vanara:BAAALgAECgEJAgAAAA==.Varadun:BAAALgAFFAIJAwAAAA==.Varrosh:BAAALgADCgYJBgAAAA==.Vathan:BAAALgAECgQJBQAAAA==.',
Ve='Velmora:BAAALgAECgkJCQAAAA==.Velsetin:BAABLgAECn8dAAIFAAcJTBsyTABSAgAFAAcJTBsyTABSAgABLgAFFAMJBQAVAMcUAA==.Verathina:BAAALgADCgEJAQAAAA==.Versed:BAAALgADCgUJBQABLgAECgQJBAADAAAAAA==.Veryspooky:BAABLgAECn8aAAIbAAgJNhlfNwD6AQAbAAgJNhlfNwD6AQAAAA==.Vexian:BAABLgAECn8UAAMkAAkJVBvSDgB/AgAkAAkJVBvSDgB/AgAWAAEJ3B9ptABcAAAAAA==.',
Vf='Vfl:BAAALgADCgcJBwAAAA==.',
Vi='Vicas:BAAALgAECgcJEgAAAA==.',
Vl='Vladdek:BAAALgAECgMJAwAAAA==.Vladdok:BAAALgAECgUJBQAAAA==.Vladok:BAAALgAECgQJBQAAAA==.Vladokk:BAAALgAECgMJAwAAAA==.',
Vo='Voidofdeath:BAAALgADCgQJBAAAAA==.Voidshiekah:BAAALgADCgEJAQAAAA==.Vorteia:BAAALgADCgYJBgAAAA==.',
['Vé']='Véngéánçé:BAAALgAECgMJBAAAAA==.',
Wa='Wald:BAAALgAECgYJEAAAAA==.Warmongerr:BAAALgADCgIJAgAAAA==.Waruh:BAAALgADCgcJCQAAAA==.',
We='Webgar:BAAALgAECgEJAQAAAA==.',
Wh='Whisperlia:BAAALgAECgQJBgAAAA==.Whisperwindd:BAAALgAECgMJAQAAAA==.White:BAAALgAECgEJAQAAAA==.Whitetoothe:BAABLgAECn8rAAICAAYJOBgqawBmAQACAAYJOBgqawBmAQAAAA==.',
Wi='Witemandown:BAAALgADCgYJBgAAAA==.Witherbear:BAAALgADCgcJBwAAAA==.Witherhoard:BAAALgADCgEJAQAAAA==.Wizzy:BAAALgADCgEJAQAAAA==.',
['Wå']='Wånheda:BAAALgAECggJEwAAAA==.',
Xa='Xaniana:BAAALgAECgkJDwAAAA==.Xaosin:BAAALgADCgUJBQAAAA==.',
Xe='Xenzak:BAAALgAECgEJAQAAAA==.Xephir:BAAALgADCgMJAwAAAA==.Xerxës:BAAALgAECgEJAQAAAA==.',
Xl='Xl:BAAALgAECgQJCwAAAA==.',
Xo='Xoito:BAAALgAECgEJAQABLgAECgcJBQADAAAAAA==.Xotiko:BAAALgAECgYJDAAAAA==.',
Xu='Xubris:BAAALgADCgYJCQAAAA==.',
['Xâ']='Xâxâs:BAAALgAECgMJAwABLgAECggJGQAfAFsEAA==.',
Ya='Yaerin:BAACLgAFFH8ZAAIeAAQJcCPzGQCNAQAeAAQJcCPzGQCNAQAuAAQKfyQAAh4ACQkAItQDAF4DAB4ACQkAItQDAF4DAAAA.',
Yu='Yunarä:BAAALgAECgYJBwAAAA==.Yuukon:BAABLgAECn8ZAAQTAAgJkRV3HABzAQATAAgJkRV3HABzAQALAAQJ5gMuMwFmAAAHAAEJDwgrGAAvAAAAAA==.',
Za='Zakuul:BAAALgADCgQJBAAAAA==.Zalezaar:BAAALgAECgIJAgAAAA==.Zangetsu:BAAALgAECgcJBwAAAA==.Zaxie:BAABLgAECn8uAAISAAgJ9xycIABOAgASAAgJ9xycIABOAgAAAA==.',
Ze='Zenwu:BAAALgADCgkJGwAAAA==.Zephrylia:BAAALgAECgQJBQAAAA==.Zerama:BAAALgAECgUJBQAAAA==.',
Zh='Zheratul:BAAALgAECgEJAQAAAA==.Zhirl:BAAALgAECgkJCQAAAA==.Zhivet:BAAALgAECgYJBwAAAA==.',
Zi='Zilphia:BAAALgAECggJEgAAAA==.',
Zu='Zuriel:BAAALgAECgIJAgAAAA==.',
Zy='Zyku:BAAALgAECgEJAQAAAA==.Zylphie:BAAALgADCgcJBwAAAA==.',
['Àm']='Àmagezing:BAAALgAFFAIJAgAAAA==.',
['Åj']='Åj:BAAALgADCgcJBwAAAA==.',
['Åp']='Åpexx:BAABLgAECn8WAAMSAAYJ1AVbvgCrAAASAAYJgAVbvgCrAAAYAAEJzAaheQAkAAAAAA==.',
['Çw']='Çwÿbàbý:BAAALgAECgIJBAAAAA==.',
['Ór']='Órión:BAABLgAECn8VAAICAAYJ1BLhngD+AAACAAYJ1BLhngD+AAAAAA==.',
['Ös']='Östara:BAABLgAECn8bAAIPAAcJgBj6LADxAQAPAAcJgBj6LADxAQAAAA==.',
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
