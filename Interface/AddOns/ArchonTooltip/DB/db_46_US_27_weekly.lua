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

local lookup = {'Warlock-Destruction','Hunter-BeastMastery','Unknown-Unknown','Mage-Arcane','Mage-Frost','Hunter-Survival','DeathKnight-Frost','Monk-Mistweaver','Monk-Brewmaster','Monk-Windwalker','DeathKnight-Unholy','Priest-Shadow','Paladin-Retribution','Druid-Guardian','Druid-Restoration','Hunter-Marksmanship','Paladin-Protection','DemonHunter-Devourer','DeathKnight-Blood','Priest-Holy','Druid-Balance','Shaman-Restoration','Rogue-Subtlety','DemonHunter-Havoc','Rogue-Outlaw','Rogue-Assassination','Warlock-Demonology','Druid-Feral','Warrior-Arms','Warrior-Fury','Priest-Discipline','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Warrior-Protection','Shaman-Elemental','Warlock-Affliction','Paladin-Holy','Shaman-Enhancement',}
local provider = {region='US',realm='Azuremyst',name='US',type='weekly',zone=46,date='2026-06-20',data={Aa='Aaravos:BAABLgAECn8aAAIBAAgJshbRBwDUAQABAAgJshbRBwDUAQAAAA==.',
Ab='Abysseon:BAAALgAECgUJDgAAAA==.',
Ac='Accretion:BAAALgAECgYJBgAAAA==.',
Ad='Adaria:BAABLgAECn8WAAICAAcJWAWSZQA3AQACAAcJWAWSZQA3AQAAAA==.Adrillbear:BAAALgAECgIJAgABLgAECgYJEwADAAAAAA==.Adura:BAAALgAECgMJBAAAAA==.',
Ae='Aeirith:BAACLgAFFH8KAAIEAAQJthRpAQAjAQAEAAQJthRpAQAjAQAuAAQKfyQAAwQACQmwHegBAGYCAAQACQmwHegBAGYCAAUAAQlFChRgATEAAAAA.Aelion:BAAALgAECgEJAQAAAA==.',
Ah='Ahheevoker:BAAALgAECgYJEgAAAA==.',
Ai='Ailsà:BAAALgADCgEJAQAAAA==.',
Ak='Akarias:BAAALgAECgEJAQABLgAECgcJBwADAAAAAA==.',
Al='Aladaria:BAAALgAECgMJAwAAAA==.Aldyah:BAAALgAECggJDwAAAA==.Alias:BAAALgAECgYJBQAAAA==.Allanonn:BAAALgAECgQJBAAAAA==.Alohomora:BAAALgAECgUJEAAAAA==.Alvist:BAAALgAECgQJEwAAAA==.',
Am='Amarasu:BAABLgAECn8bAAIGAAkJig+SGwDBAQAGAAkJig+SGwDBAQAAAA==.Amarlly:BAABLgAECn8wAAIHAAgJYxrgBwAVAgAHAAgJYxrgBwAVAgAAAA==.Amenedil:BAAALgAECgUJDAAAAA==.',
An='Anbrew:BAABLgAECn8UAAQIAAcJdxJoSwA/AQAIAAYJDBJoSwA/AQAJAAUJjA6DQAD4AAAKAAEJMweyrwAlAAABLgAFFAYJDwALAN0dAA==.Ancelina:BAABLgAECn8qAAIMAAkJeyR5AgBCAwAMAAkJeyR5AgBCAwAAAA==.Anderton:BAABLgAECn8xAAINAAgJShnSSwDjAQANAAgJShnSSwDjAQAAAA==.Andilocks:BAAALgADCgMJAwAAAA==.Andrela:BAAALgAECgIJAgAAAA==.Aneira:BAABLgAECn8cAAMOAAYJTBCrAQDNAAAOAAYJTBCrAQDNAAAPAAMJYQyTmQB/AAAAAA==.Annovera:BAAALgAECgMJBgAAAA==.Anuubis:BAAALgADCgYJBgAAAA==.Anyi:BAAALgAECgEJAQAAAA==.',
Ap='Apexxd:BAAALgAECgMJAwAAAA==.Applefritter:BAAALgAECgUJCAABLgAECgkJKAAMAJYbAA==.',
Ar='Archérhiro:BAACLgAFFH8nAAMCAAgJkRXJCAAyAgACAAcJUxjJCAAyAgAQAAMJRwTfIQCHAAAuAAQKfykAAwIACQlYH+8YAJECAAIACQlMH+8YAJECABAACAkrGdobAEoCAAAA.Arilias:BAAALgAECgEJAQABLgAECgkJNQACABIfAA==.Arillann:BAABLgAECn89AAIRAAkJUR+3BACuAgARAAkJUR+3BACuAgAAAA==.Arrook:BAAALgADCgMJAwAAAA==.Arrtonomis:BAAALgAECgUJCAABLgAECgkJEQADAAAAAA==.Artdemsamis:BAAALgAECgIJBAABLgAECgkJEQADAAAAAA==.Arte:BAABLgAECn89AAICAAkJaxOnLAABAgACAAkJaxOnLAABAgAAAA==.Arthundermis:BAAALgAECgkJEQAAAA==.Artlunarmis:BAAALgADCgEJAQABLgAECgkJEQADAAAAAA==.Arvena:BAABLgAECn8nAAISAAkJVgoWdAA5AQASAAkJVgoWdAA5AQAAAA==.',
As='Asclëpius:BAAALgADCgcJBgABLgAECgEJAQADAAAAAA==.Asheron:BAAALgAECgYJCAAAAA==.Ashylock:BAAALgAECgEJAQABLgAFFAUJDgAFAGAWAA==.Ashymage:BAACLgAFFH8OAAIFAAUJYBa2YAAgAQAFAAUJYBa2YAAgAQAuAAQKfzcAAgUACQlYHLYpAMwCAAUACQlYHLYpAMwCAAAA.Askevar:BAABLgAECn8hAAMLAAkJrgpncgB/AQALAAkJ2ghncgB/AQATAAYJ5wlHJwAEAQAAAA==.Aspect:BAAALgADCgEJAQABLgAFFAIJAwADAAAAAA==.Asriél:BAAALgAECgQJBAAAAA==.Astor:BAAALgADCgMJBQAAAA==.Astrona:BAAALgADCgkJFwAAAA==.',
At='Atreus:BAABLgAECn8YAAINAAkJbAXTwQAGAQANAAkJbAXTwQAGAQAAAA==.Attalaguy:BAAALgAECgYJDgAAAA==.',
Au='Audra:BAAALgADCgcJDgAAAA==.',
Av='Avabeatrix:BAAALgADCgEJAQAAAA==.Avinthoro:BAAALgADCgIJAgAAAA==.',
Ay='Ayyayyron:BAAALgAECgUJCQAAAA==.',
Az='Azaleah:BAABLgAECn9JAAINAAkJQB3vGQCoAgANAAkJQB3vGQCoAgAAAA==.Azanoth:BAAALgADCgIJAgAAAA==.Azraesha:BAABLgAECn8rAAISAAkJ/BUGKgAhAgASAAkJ/BUGKgAhAgAAAA==.Azureflamez:BAAALgAECgEJAQAAAA==.Azurewraith:BAAALgAECgQJBAAAAA==.Azzul:BAAALgADCgcJBwAAAA==.',
Ba='Baiken:BAAALgAECgIJAgABLgAECgQJCAADAAAAAA==.Banjoman:BAABLgAECn8kAAIUAAcJXSTpCgC4AgAUAAcJXSTpCgC4AgAAAA==.Baza:BAAALgADCgYJBgAAAA==.Baýlei:BAABLgAECn8WAAIIAAYJ5A0jWwAHAQAIAAYJ5A0jWwAHAQAAAA==.',
Be='Beareold:BAAALgAECgIJAgAAAA==.Beary:BAAALgAECgQJCAAAAA==.Beenaughty:BAAALgAECgEJAQABLgAECgEJAQADAAAAAA==.Belaanna:BAAALgADCgYJCQAAAA==.Beliria:BAAALgADCgUJBgAAAA==.Benimaru:BAAALgAECgUJDwAAAA==.Beriko:BAAALgAECgMJAwAAAA==.Bernat:BAAALgAECgEJAQAAAA==.Beàrdfáce:BAAALgADCgQJBAAAAA==.',
Bi='Bigblunt:BAAALgAECgEJAQAAAA==.Bigjuicy:BAAALgAECggJEAAAAA==.Billie:BAAALgAECgYJBgAAAA==.Bimboficate:BAAALgADCgYJBwAAAA==.',
Bl='Black:BAAALgAECgQJBAAAAA==.Blackadder:BAABLgAECn8fAAIRAAYJ/w2TAQCyAAARAAYJ/w2TAQCyAAAAAA==.Blessthefall:BAAALgAECgYJCgAAAA==.Blondie:BAAALgADCgQJBAABLgAECgYJEwADAAAAAA==.Bloodie:BAAALgAECgMJAwAAAA==.Blue:BAABLgAECn88AAIKAAkJxRvlDgBbAgAKAAkJxRvlDgBbAgAAAA==.Blueguy:BAAALgAECgEJAQAAAA==.Bluestreak:BAAALgAECgEJAwABLgAECgcJCQADAAAAAA==.',
Bo='Bobthefist:BAAALgADCgcJBwAAAA==.Bode:BAAALgAECgYJEwAAAA==.Bogern:BAAALgADCgcJBwAAAA==.Bolau:BAAALgADCgYJBwAAAA==.Boltz:BAAALgADCgYJBgAAAA==.Boogy:BAAALgAECgYJBgAAAA==.Bopdiz:BAAALgAECgEJAQABLgAECgQJEwADAAAAAA==.Borledish:BAAALgAECgMJBAABLgAECgQJEwADAAAAAA==.Bottosai:BAAALgAECgEJAgAAAA==.',
Br='Brambles:BAAALgAECgEJAQAAAA==.Branwynn:BAAALgAECgMJCAAAAA==.Breezyfight:BAAALgAFFAIJAgAAAA==.Breezyrocks:BAAALgADCgQJCQAAAA==.Breezysha:BAAALgADCgcJCAAAAA==.Brenz:BAABLgAFFH8GAAMNAAMJOQILqgBuAAANAAMJOwELqgBuAAARAAEJvQR3HAAhAAAAAA==.Brewdaddy:BAAALgAECgUJEwABLgAECgkJNAARAHwRAA==.Brewdude:BAAALgAECgEJAQAAAA==.Brigor:BAAALgAECgYJCgAAAA==.Brokenblade:BAAALgADCgYJBgAAAA==.Brotherblood:BAAALgAECgMJBgAAAA==.',
Bu='Bulldoza:BAAALgAECgQJBQAAAA==.Bullwinkles:BAAALgAECgEJAQAAAA==.Butterknifeo:BAABLgAFFH8FAAIVAAMJxxSKMQC7AAAVAAMJxxSKMQC7AAAAAA==.',
By='Byryja:BAABLgAECn8fAAIFAAYJTgb+BwCQAAAFAAYJTgb+BwCQAAAAAA==.',
Ca='Cahrazie:BAACLgAFFH8GAAINAAMJ9wk0ewDAAAANAAMJ9wk0ewDAAAAuAAQKfxwAAg0ACQlBE7dIAOwBAA0ACQlBE7dIAOwBAAAA.Caidinn:BAAALgAECgkJEQAAAA==.Caitrîn:BAAALgADCgkJCQABLgAECgYJHAAOAEwQAA==.Calissancia:BAABLgAECn82AAIIAAgJNBdGHwAgAgAIAAgJNBdGHwAgAgAAAA==.Calkey:BAABLgAECn8WAAIBAAYJUQgKHwCyAAABAAYJUQgKHwCyAAAAAA==.Cathandris:BAAALgADCgEJAQAAAA==.',
Ce='Ceri:BAAALgAECgkJBwAAAA==.',
Ch='Chadarack:BAAALgAECgYJBwAAAA==.Chadaracks:BAAALgAECgEJAQAAAA==.Chancy:BAAALgAECgMJBAAAAA==.Channingtotm:BAACLgAFFH8nAAIWAAUJsyWYAAABAgAWAAUJsyWYAAABAgAuAAQKfzcAAhYACQlhIY4EAG4DABYACQlhIY4EAG4DAAAA.Chantix:BAAALgADCgUJBQAAAA==.Charlemoo:BAAALgADCgUJBQABLgAECgMJAwADAAAAAA==.Cheekymonkey:BAABLgAECn8kAAIEAAkJIAuEBQB+AQAEAAkJIAuEBQB+AQAAAA==.Chrispbacon:BAAALgAECgUJEgAAAA==.Chueyé:BAAALgAECgMJAwABLgAFFAMJCQAXAO8dAA==.Chunkyy:BAAALgADCgYJBgAAAA==.Churros:BAABLgAECn8oAAMMAAkJlhuVEQBJAgAMAAkJlhuVEQBJAgAUAAcJThVvJwCKAQAAAA==.',
Ci='Cincog:BAAALgAECgQJBAABLgAECgYJCQADAAAAAA==.',
Cl='Closetcookie:BAAALgAECgQJBAAAAA==.',
Co='Coberren:BAAALgAECgEJAQAAAA==.Cordialkylie:BAAALgAECgIJAgAAAA==.Cowcrusader:BAAALgADCgcJBwAAAA==.',
Cr='Crazyugly:BAAALgAECgQJBQAAAA==.Crogrer:BAAALgAECgMJAwAAAA==.Crosslock:BAAALgAECgUJDgAAAA==.',
Cu='Cuppycakes:BAAALgADCgcJFAAAAA==.',
Cy='Cynnari:BAAALgAECgUJCgAAAA==.',
Da='Daddysecret:BAAALgAECgQJBQAAAA==.Dalan:BAAALgAECgIJAgABLgAFFAQJCgAEALYUAA==.Dalaris:BAACLgAFFH8KAAIYAAQJnQ2jAQDmAAAYAAQJnQ2jAQDmAAAuAAQKfyIAAhgACQmdFiISAAoCABgACQmdFiISAAoCAAAA.Danizmi:BAAALgADCgQJBAAAAA==.Dano:BAAALgADCgYJDQAAAA==.Darci:BAAALgAECgYJCwAAAA==.Darkeon:BAAALgAECgcJCwAAAA==.Darlenedark:BAAALgAECgEJAQAAAA==.Darling:BAAALgAECgIJAgAAAA==.Darron:BAAALgAECgEJAwABLgAECgcJDAADAAAAAA==.Darrosh:BAABLgAECn8bAAQZAAgJuxOEEgDhAAAZAAYJDhCEEgDhAAAXAAcJjQ32PgDLAAAaAAMJ9hB8FAC1AAAAAA==.Dartian:BAAALgADCgcJDQABLgAECgkJNQACABIfAA==.Daylightt:BAAALgAECgIJAgAAAA==.Dazdot:BAAALgADCgQJBAABLgAECgEJAQADAAAAAA==.Dazsham:BAAALgAECgEJAQAAAA==.',
De='Deathdevil:BAAALgAECgUJBQAAAA==.Deathlurker:BAAALgADCgQJBAAAAA==.Deathmare:BAAALgAECgUJBQAAAA==.Deathmommy:BAAALgAECgcJCAAAAA==.Deathty:BAAALgAECgMJCgABLgAFFAEJAgADAAAAAA==.Dementia:BAAALgADCgMJAwAAAA==.Design:BAABLgAECn8lAAIbAAkJ4Rc7MgAPAgAbAAkJ4Rc7MgAPAgAAAA==.Desmeridian:BAAALgAECgUJBQAAAA==.Devotee:BAAALgADCgIJAgAAAA==.',
Dh='Dhish:BAABLgAECn8VAAQVAAYJCAerAgCfAAAVAAYJCAerAgCfAAAcAAMJMwdUPABoAAAPAAIJ6gIc1AAxAAAAAA==.',
Di='Diltlish:BAAALgAECgMJBQAAAA==.Diocles:BAAALgAECgUJBgAAAA==.Disconcern:BAAALgAECgEJAQAAAA==.Discontent:BAACLgAFFH8GAAIdAAIJUR2yMwCNAAAdAAIJUR2yMwCNAAAuAAQKfxQAAx0ABwnwHKUQAOkBAB0ABwnwHKUQAOkBAB4ABQknEVxuAP0AAAAA.Discordiä:BAABLgAECn8XAAIfAAgJHRf7HQDeAQAfAAgJHRf7HQDeAQAAAA==.Discspal:BAAALgAECgYJBwAAAA==.Diåblo:BAAALgADCgUJBQAAAA==.',
Dm='Dmginc:BAAALgADCgIJAgAAAA==.',
Do='Doeblin:BAAALgAECgUJEgAAAA==.Domidouse:BAAALgAECgQJBAAAAA==.Donkedixon:BAAALgADCgYJBgAAAA==.Doubtz:BAAALgAECgQJBQABLgAECgQJEwADAAAAAA==.',
Dp='Dpalx:BAAALgAECgQJBAAAAA==.Dpxs:BAABLgAFFH8HAAIWAAQJkha4PwDmAAAWAAQJkha4PwDmAAAAAA==.',
Dr='Dracaria:BAAALgAECgEJAQAAAA==.Dracones:BAAALgAECgYJDgAAAA==.Dragondz:BAAALgAECgUJBQAAAA==.Dragonflai:BAABLgAECn8mAAIFAAkJnBdDUwDjAQAFAAkJnBdDUwDjAQAAAA==.Dragonkin:BAAALgAECgQJCAAAAA==.Drakkari:BAAALgAECgYJDgAAAA==.Drakkei:BAABLgAECn9BAAMCAAkJphkEJABTAgACAAkJphkEJABTAgAGAAMJIga+SQCSAAAAAA==.Drawbridge:BAAALgAECgEJAQAAAA==.Drerane:BAAALgADCgYJBgAAAA==.Drexxsster:BAAALgADCgQJBAAAAA==.Drshortbus:BAAALgAECgUJCQAAAA==.Drumitus:BAAALgADCgYJCAAAAA==.Drunkngrundl:BAABLgAECn89AAIJAAkJHiMoBAAGAwAJAAkJHiMoBAAGAwAAAA==.Drylo:BAECLgAFFH8JAAIgAAQJ6R5+IABcAQAgAAQJ6R5+IABcAQAuAAQKfy0AAyAACQkmII8JAL8CACAACQmLHo8JAL8CACEACAnFH6UGAIgCAAAA.',
Du='Duckeey:BAAALgAFFAEJAQABLgAFFAUJFQAFAJ4OAA==.Dunstir:BAABLgAECn8ZAAINAAgJ6QUfwAAIAQANAAgJ6QUfwAAIAQAAAA==.Dusktrekker:BAAALgAECgkJBwAAAA==.',
Dy='Dypshyt:BAABLgAECn8aAAQgAAkJhxfkTwDvAAAhAAUJUBJRIgAYAQAgAAYJqxDkTwDvAAAiAAUJTgemLgB1AAAAAA==.',
Ed='Edelweíss:BAAALgAECgQJCgAAAA==.',
Ek='Ekazzik:BAAALgAECgYJBgABLgAECggJFwACANQaAA==.Ekoh:BAAALgAECgIJAgAAAA==.',
El='Elarol:BAAALgAECgEJAgAAAA==.Eldons:BAAALgADCgIJAgAAAA==.',
Em='Embers:BAABLgAECn8WAAIeAAYJGxPcWADrAAAeAAYJGxPcWADrAAAAAA==.Emeralde:BAAALgAECgYJCgAAAA==.Emilia:BAAALgADCgIJAwAAAA==.Emptyhands:BAAALgAECgYJBgAAAA==.Emptyheals:BAABLgAECn8xAAIfAAkJ3yC7BABEAwAfAAkJ3yC7BABEAwAAAA==.',
Er='Ereada:BAAALgADCgUJCgAAAA==.Erfinden:BAAALgADCgEJAQAAAA==.',
Es='Espernite:BAAALgAECgQJBAAAAA==.Espers:BAABLgAECn8fAAIVAAkJ6Q+pPgAUAQAVAAkJ6Q+pPgAUAQAAAA==.',
Et='Ethellin:BAABLgAECn8yAAINAAkJgAWNqAAqAQANAAkJgAWNqAAqAQAAAA==.',
Fa='Fahrenheit:BAAALgAECgEJAgAAAA==.Farkuat:BAAALgADCgQJBAAAAA==.Fatcastle:BAAALgADCgcJDgAAAA==.',
Fe='Feedmepizzas:BAAALgAECgMJCAAAAA==.Feildmedic:BAAALgAECgEJAQAAAA==.Feleria:BAAALgAECgUJDAAAAA==.Fellslasher:BAAALgAECgIJAgAAAA==.Felmage:BAAALgADCgYJBgAAAA==.Felraiser:BAAALgADCgIJAgABLgADCgUJBgADAAAAAA==.Felwinter:BAABLgAECn81AAIbAAkJthrMIQBbAgAbAAkJthrMIQBbAgAAAA==.Femcelgoon:BAAALgADCgEJAQAAAA==.Fenna:BAAALgADCgYJDAAAAA==.Fetor:BAAALgAECgcJEAAAAA==.',
Fi='Finwé:BAAALgAECgQJCQAAAA==.Fistsalot:BAAALgAECgQJCAAAAA==.',
Fl='Flafferthorn:BAAALgADCgcJDgAAAA==.Fluxarata:BAABLgAECn8rAAISAAkJ9g29UwCLAQASAAkJ9g29UwCLAQAAAA==.',
Fo='Forthememes:BAAALgAECgcJCQAAAA==.',
Fr='Fred:BAABLgAECn8sAAIeAAgJhQrFPQBPAQAeAAgJhQrFPQBPAQAAAA==.Freddrick:BAAALgADCgQJBAAAAA==.Friendly:BAAALgAECgEJAQAAAA==.Frostbuddy:BAAALgAECgcJDQAAAA==.Frëya:BAAALgADCgYJDQAAAA==.Frío:BAAALgAECgEJAQAAAA==.Frøstitute:BAABLgAECn8qAAIFAAkJLReqMwBKAgAFAAkJLReqMwBKAgAAAA==.',
Fu='Fullmage:BAAALgADCgQJBAAAAA==.',
['Fè']='Fènrïr:BAAALgADCgQJBAAAAA==.',
Ga='Gabel:BAABLgAECn8mAAIcAAkJQh3IBgB2AgAcAAkJQh3IBgB2AgAAAA==.Gadnabit:BAAALgADCgkJCQAAAA==.Gailardia:BAABLgAECn8kAAICAAcJ/x2GLwAeAgACAAcJ/x2GLwAeAgABLgAFFAQJFwAUAL0dAA==.Galand:BAABLgAECn8iAAMLAAYJ+h7abwCFAQALAAYJdB7abwCFAQATAAIJoiFoUABTAAAAAA==.Galladin:BAAALgADCggJDgAAAA==.Gardyson:BAABLgAECn8WAAMjAAcJUhUJGwBgAQAjAAcJUhUJGwBgAQAeAAEJbQNKtAAhAAABLgAECggJFwACANQaAA==.Gazton:BAAALgAECgUJBQAAAA==.',
Gl='Glaaki:BAAALgAECgUJCwAAAA==.',
Gn='Gnob:BAAALgAECgQJCwAAAA==.',
Go='Gooblet:BAAALgADCgQJBQAAAA==.Goodfellow:BAAALgAECgEJAQABLgAECgYJFQAcAMUcAA==.Goopy:BAAALgADCgYJAwAAAA==.',
Gr='Graendal:BAAALgADCgQJBAAAAA==.Granite:BAAALgAECgMJBAAAAA==.Granted:BAAALgADCgUJBQAAAA==.Greevil:BAAALgAECgEJAwAAAA==.Gremilien:BAABLgAECn8oAAIQAAkJExVCCgDMAQAQAAkJExVCCgDMAQAAAA==.Grimgorr:BAAALgADCgMJAwAAAA==.Grimmly:BAAALgAECgEJAQAAAA==.Grymdevours:BAAALgADCgYJBgAAAA==.',
Ha='Halcyonic:BAAALgAECgUJCgAAAA==.Halleyscomet:BAABLgAECn8WAAINAAcJPBptRAAXAgANAAcJPBptRAAXAgAAAA==.Happyhammer:BAAALgADCgcJCAAAAA==.Harrod:BAAALgAECggJCwAAAA==.Hawkwave:BAAALgAECgcJEgABLgAECgkJEQADAAAAAA==.Hazardzone:BAAALgAECgMJCgAAAA==.',
He='Heartburn:BAAALgADCgEJAQAAAA==.Heavyweather:BAAALgADCgcJBwAAAA==.Hefty:BAABLgAECn8XAAMGAAkJ3QtlKQBVAQAGAAcJKQtlKQBVAQACAAUJ8gmyowD6AAAAAA==.Heftyer:BAAALgAECgMJAwAAAA==.Helioween:BAAALgADCgMJAwAAAA==.Helixon:BAAALgADCgYJBgAAAA==.Hellbad:BAACLgAFFH8MAAIJAAQJ7hPGKAAGAQAJAAQJ7hPGKAAGAQAuAAQKfxUAAwkACAleGL0nAHMBAAoABgmOG30jALoBAAkACAkXEr0nAHMBAAAA.Hellbine:BAAALgADCgMJAgAAAA==.Hellfella:BAAALgAECgEJAQAAAA==.Hellonheels:BAAALgAECgQJBAAAAA==.Hellsspawn:BAAALgAECgYJDgAAAA==.Hexaverse:BAAALgADCgYJBgABLgAECgQJBAADAAAAAA==.',
Ho='Hoardwither:BAAALgAECgEJAgAAAA==.Hoenheim:BAAALgAECgEJAQAAAA==.Hogrog:BAAALgADCgMJAwAAAA==.Hokàge:BAACLgAFFH8JAAIXAAMJ7x0DJQD8AAAXAAMJ7x0DJQD8AAAuAAQKfzkABBcACQkpIvIIAJYCABcACQkpIvIIAJYCABoAAgkCGhIbAIwAABkAAQkZAlgsAAkAAAAA.Holyballs:BAAALgAECgQJBwAAAA==.Homealone:BAABLgAECn8YAAMWAAcJZwlXfADrAAAWAAYJ/QZXfADrAAAkAAUJ8gPZfQB3AAAAAA==.',
Hu='Huffles:BAAALgAECgQJBwAAAA==.Hugmachine:BAAALgAFFAIJAgAAAA==.Huntinfuzzy:BAAALgAECgkJDwAAAA==.Huntn:BAAALgADCggJCAAAAA==.',
Hy='Hypahypa:BAAALgAECggJCgAAAA==.',
Ia='Iamknot:BAAALgAECgQJBgAAAA==.',
Ic='Icemommy:BAAALgADCgQJCAAAAA==.',
Ig='Igothots:BAACLgAFFH8FAAIPAAIJZBDNVQBvAAAPAAIJZBDNVQBvAAAuAAQKfx4AAw8ACQl/HgIQALgCAA8ACQl/HgIQALgCABwAAQltCbtYACkAAAAA.',
Il='Illariana:BAABLgAECn8aAAQMAAgJNRI3LABzAQAMAAgJNRI3LABzAQAUAAEJwQK7egAfAAAfAAEJvgHGigAdAAAAAA==.Illirotica:BAAALgAECgcJCQAAAA==.',
In='Incredibro:BAAALgADCgEJAQAAAA==.Insanitty:BAAALgAECgcJDwAAAA==.Invincible:BAAALgAECgEJAQABLgAECgYJIQAIAIEkAA==.',
Ir='Ironlobo:BAABLgAECn8YAAIFAAYJhxkdfACAAQAFAAYJhxkdfACAAQAAAA==.Ironsolari:BAAALgADCgYJBgAAAA==.Irritable:BAABLgAECn8jAAMlAAkJARs/AwCHAgAlAAkJARs/AwCHAgAbAAEJJRfsIQFGAAAAAA==.',
It='Itherious:BAAALgAECgUJDwAAAA==.',
Ja='Jacham:BAABLgAECn8WAAIeAAkJ2hSHHwDzAQAeAAkJ2hSHHwDzAQAAAA==.Jackyll:BAAALgAECgQJCAAAAA==.Jagerboy:BAAALgAECgYJBgAAAA==.Jango:BAAALgAECgIJAgABLgAECggJFwACANQaAA==.Jatix:BAACLgAFFH8QAAINAAQJjx7WAwAZAQANAAQJjx7WAwAZAQAuAAQKfyoAAg0ACQkcI3cPAOoCAA0ACQkcI3cPAOoCAAAA.',
Je='Jeetkundo:BAAALgADCgEJAQABLgAECgYJIQAIAIEkAA==.Jellydh:BAAALgAECgIJBQAAAA==.Jellymagus:BAAALgAECgIJAgAAAA==.Jellyms:BAAALgAECgYJDQAAAA==.Jellyspinoff:BAAALgAECgMJBwAAAA==.Jellytown:BAABLgAECn89AAIFAAkJaxRYRQALAgAFAAkJaxRYRQALAgAAAA==.Jelorinea:BAAALgAECgMJAwAAAA==.Jessiana:BAAALgAECgUJDAAAAA==.Jezelda:BAAALgAECgQJBgAAAA==.',
Jp='Jpeppers:BAABLgAECn8YAAICAAYJBRbUAwAPAQACAAYJBRbUAwAPAQAAAA==.',
Ju='Jumano:BAAALgAECgUJCgAAAA==.Jundra:BAAALgAECgUJCgAAAA==.Jurih:BAAALgADCgIJAgAAAA==.',
Ka='Kaineh:BAABLgAECn8oAAIQAAgJah3WBQA/AgAQAAgJah3WBQA/AgAAAA==.Kainë:BAAALgADCgIJAgAAAA==.Kait:BAABLgAECn8+AAICAAkJ6R82EQDHAgACAAkJ6R82EQDHAgAAAA==.Kaladil:BAAALgAECgcJDgAAAA==.Kamis:BAAALgAECgMJAwAAAA==.Kanaga:BAAALgAECgQJBQAAAA==.Kannan:BAABLgAECn8YAAMSAAgJzxv/LwA8AgASAAgJzxv/LwA8AgAYAAEJAQdWeQAqAAAAAA==.Kashmihhr:BAAALgADCgIJAgAAAA==.Kashmir:BAAALgAECgQJBAAAAA==.Kasmes:BAAALgADCggJGQAAAA==.Kasmius:BAAALgAECgMJAwAAAA==.Kasmus:BAAALgAECgQJCAAAAA==.Kawdor:BAABLgAECn80AAQRAAkJfBHfFwBgAQARAAgJ2xDfFwBgAQAmAAcJNw/2PgBJAQANAAMJ8wrBQQFqAAAAAA==.',
Ke='Keetsz:BAAALgAECgYJDAAAAA==.Kelaino:BAAALgADCgQJBQAAAA==.Keledish:BAAALgADCgEJAQAAAA==.',
Kh='Khansmebduke:BAACLgAFFH8FAAMYAAQJNxaiGQDUAAAYAAMJkRmiGQDUAAASAAEJKgzenQA9AAAuAAQKfxYAAxgACAmlHC8WANkBABIACAk1F1w+APsBABgABwlXHS8WANkBAAEuAAUUBQkJABwAjh4A.',
Ki='Kiaf:BAAALgADCgcJDQAAAA==.Kiba:BAAALgADCgEJAQAAAA==.Killanick:BAAALgAECgEJAQAAAA==.Killdar:BAAALgAECgQJBAAAAA==.Kimia:BAAALgADCgYJCQAAAA==.Kirtthedirt:BAAALgAECgYJBwAAAA==.Kirtthehurt:BAABLgAECn8pAAIFAAkJShhoMABXAgAFAAkJShhoMABXAgAAAA==.',
Ko='Koldfront:BAAALgAECgUJCwAAAA==.Kollinator:BAAALgAECgYJEQAAAA==.Korso:BAAALgADCgUJCwABLgAECgYJHAAOAEwQAA==.Kotal:BAAALgAECgEJAQAAAA==.',
Ky='Kylair:BAABLgAECn80AAIMAAkJ/B4cCgCtAgAMAAkJ/B4cCgCtAgAAAA==.Kynreessa:BAAALgADCgYJCAAAAA==.Kyyell:BAAALgAECgcJCAAAAA==.Kyønshi:BAAALgADCgUJBgAAAA==.',
['Kì']='Kìrito:BAAALgAECgcJDgAAAA==.',
La='Labeya:BAAALgADCgMJAwAAAA==.Lafty:BAAALgAFFAEJAgAAAA==.Laftydh:BAAALgAECgYJEgABLgAFFAEJAgADAAAAAA==.Lailah:BAAALgADCgIJAgABLgAECgkJSQANAEAdAA==.Laine:BAAALgADCgMJAwAAAA==.Landrra:BAAALgAECgQJBAAAAA==.Larac:BAAALgAECggJEwAAAA==.Lathsong:BAAALgADCgYJDwAAAA==.Lavi:BAAALgADCgQJAwAAAA==.',
Le='Leadge:BAAALgADCgYJBwAAAA==.Lenik:BAABLgAECn8aAAIXAAYJ+gkDOADxAAAXAAYJ+gkDOADxAAAAAA==.Leskya:BAAALgADCgQJAwAAAA==.',
Li='Libras:BAAALgADCgMJAwAAAA==.Licorice:BAAALgAECgUJDgABLgAECgkJKAAMAJYbAA==.Lieree:BAABLgAECn8XAAIFAAgJUg3VggByAQAFAAgJUg3VggByAQAAAA==.Lifeguàrd:BAAALgAECgkJBwAAAA==.Lillana:BAAALgADCgcJDQAAAA==.Lilrayne:BAAALgADCgYJBgABLgAECgkJGwAGAIoPAA==.Lilyfaye:BAAALgADCgkJDAAAAA==.Limosfire:BAABLgAECn8VAAIQAAYJkAO7JACOAAAQAAYJkAO7JACOAAAAAA==.Linsatha:BAAALgAECggJEAAAAA==.',
Lo='Loa:BAAALgAECgEJAgAAAA==.Lockty:BAAALgAECgIJBgABLgAFFAEJAgADAAAAAA==.Logi:BAAALgADCgYJCwAAAA==.Lorezever:BAAALgADCgcJDQAAAA==.Lotion:BAAALgADCgIJAgAAAA==.',
Lu='Luar:BAAALgAECgYJDQAAAA==.Lulubean:BAAALgADCgMJBAAAAA==.Lunaris:BAAALgADCgQJBAAAAA==.Lungorthin:BAAALgAECgQJBAAAAA==.Lunà:BAABLgAECn8aAAIBAAcJwwNNIwCWAAABAAcJwwNNIwCWAAAAAA==.',
Ly='Lythalle:BAAALgAECgEJAQAAAA==.Lythwynn:BAABLgAECn8rAAINAAkJhQ+3cwCGAQANAAkJhQ+3cwCGAQAAAA==.',
['Lá']='Lásh:BAAALgAECgUJCAABLgAECgYJHAAOAEwQAA==.',
Ma='Mace:BAAALgAECgEJAQAAAA==.Madison:BAAALgAECgEJAQAAAA==.Magdolyn:BAAALgADCgMJAwAAAA==.Mageyboi:BAAALgAECgQJBgABLgAFFAMJCQAXAO8dAA==.Magickul:BAAALgAECgYJDAAAAA==.Magleon:BAAALgADCgIJAgAAAA==.Magonk:BAAALgADCgEJAQAAAA==.Mahano:BAABLgAECn8XAAICAAgJ1BoRHwBsAgACAAgJ1BoRHwBsAgAAAA==.Makis:BAAALgAECgMJBQAAAA==.Malachi:BAAALgAECgYJBgAAAA==.Manavoid:BAABLgAECn8cAAISAAYJkAripwDVAAASAAYJkAripwDVAAAAAA==.Mandragore:BAAALgAECgIJBAAAAA==.Massili:BAAALgADCgkJGgAAAA==.Mastor:BAAALgADCgQJBwAAAA==.Maynard:BAABLgAECn8hAAIIAAkJ9xEoLwC/AQAIAAkJ9xEoLwC/AQAAAA==.',
Mc='Mcdouble:BAAALgADCgMJAwAAAA==.',
Me='Meldanis:BAAALgAECgQJBAAAAA==.Meri:BAABLgAECn8cAAIPAAgJlxwrJgAfAgAPAAgJlxwrJgAfAgAAAA==.',
Mi='Miande:BAABLgAECn8VAAIlAAcJ0xfKCgCyAQAlAAcJ0xfKCgCyAQAAAA==.Microburst:BAAALgADCgcJCwAAAA==.Minecraft:BAAALgAECgIJAgAAAA==.Minilock:BAABLgAECn8sAAMbAAkJeQ4QUgClAQAbAAkJUA0QUgClAQABAAUJTg6rHgC0AAAAAA==.Misogynixy:BAAALgADCgQJBAAAAA==.Missdeeds:BAAALgAECgUJBQAAAA==.Missleading:BAAALgAECgYJCQAAAA==.Missused:BAAALgAECgYJEgAAAA==.Mithos:BAAALgAECgUJBwAAAA==.Mithraxa:BAAALgAECgQJBAAAAA==.Miyagifu:BAAALgAECgQJBAAAAA==.',
Mo='Moash:BAAALgADCgkJCQAAAA==.Modsagoodtnk:BAABLgAECn8WAAIRAAcJfA17AQC/AAARAAcJfA17AQC/AAABLgAECggJLAACAH8ZAA==.Mongermook:BAABLgAECn8iAAMOAAkJ0QssAgCmAAAOAAkJ0QssAgCmAAAVAAEJxgFpkQAVAAAAAA==.Monnkysham:BAAALgAECgQJBgABLgAECgYJCQADAAAAAA==.Moogledragon:BAAALgADCgMJAwAAAA==.Mooglefur:BAAALgAECgQJBQAAAA==.Moonbloom:BAABLgAECn8cAAIPAAgJQhxNHwBMAgAPAAgJQhxNHwBMAgAAAA==.Morgrim:BAAALgAECgEJAQAAAA==.Morlosh:BAAALgAECgMJAwAAAA==.Moryna:BAABLgAECn80AAIdAAkJsQhYJQA9AQAdAAkJsQhYJQA9AQAAAA==.',
Mt='Mthrandir:BAAALgADCgUJBQAAAA==.',
Mu='Muford:BAAALgAECgQJBQABLgAFFAcJFAAJAFMfAA==.Mull:BAAALgAECgYJEwAAAA==.Muloc:BAAALgADCgEJAQAAAA==.',
My='Myaka:BAAALgAECgYJBgAAAA==.Mythicc:BAAALgADCgQJBAAAAA==.',
Na='Naatixa:BAAALgAECggJDAAAAA==.Nacronor:BAAALgAECgUJDwAAAA==.Naiika:BAAALgAECgYJBwAAAA==.Nascha:BAAALgADCgEJAQAAAA==.Nasoj:BAAALgAECgYJCQABLgAECgYJEwADAAAAAA==.',
Ne='Necrotic:BAAALgAECgQJBAAAAA==.Nedalla:BAAALgAECgYJCwAAAA==.Neeve:BAAALgAECgMJAwAAAA==.Nekrotik:BAAALgADCgcJBgAAAA==.Neobahamut:BAAALgADCgEJAQABLgAECgcJDgADAAAAAA==.Netharel:BAAALgADCgIJAgAAAA==.Newports:BAAALgAECgEJAQAAAA==.',
Ni='Nichôlasmage:BAAALgAECgYJCwAAAA==.Nickatnite:BAAALgAFFAEJAQAAAA==.Nickelodeon:BAAALgAFFAIJAwAAAA==.Nicksaban:BAABLgAECn8mAAINAAkJOBuDLgBHAgANAAkJOBuDLgBHAgAAAA==.Nightgear:BAACLgAFFH8wAAMCAAgJaBcDDwDuAQACAAcJehkDDwDuAQAQAAIJ/ApTNQBJAAAuAAQKf1kAAwIACQm1IgUIABADAAIACQm1IgUIABADABAABAnfEoAjAJcAAAAA.Nightshades:BAAALgADCgQJBAAAAA==.Nilux:BAAALgAECgYJDwAAAA==.Ninetails:BAAALgAECgUJCgAAAA==.Niteshadeth:BAAALgAECgQJBQAAAA==.Niteyknight:BAAALgAECgQJBAAAAA==.Nixeava:BAABLgAECn8bAAIkAAgJ+wR4VADoAAAkAAgJ+wR4VADoAAAAAA==.',
No='Nogooddruid:BAAALgAECgUJDQAAAA==.Nopetsneeded:BAABLgAECn89AAIQAAkJzBRpCAD3AQAQAAkJzBRpCAD3AQAAAA==.Norepairbill:BAAALgAECgEJAQABLgAECgkJPQAQAMwUAA==.Nostariel:BAAALgAECgMJCQAAAA==.Notadoctor:BAAALgAECgYJCAAAAA==.Noteworthy:BAAALgAECgYJEgABLgAFFAYJDwALAN0dAA==.',
Ny='Nysong:BAABLgAECn82AAMBAAgJNQu/EgAfAQABAAgJNQu/EgAfAQAbAAMJYwKHGAFPAAAAAA==.',
['Nó']='Nórin:BAAALgAECgUJBQAAAA==.',
Ob='Obali:BAAALgADCgYJCgAAAA==.',
Od='Oddangel:BAAALgAECgYJEwAAAA==.Ode:BAAALgAECgkJDgAAAA==.Odex:BAABLgAECn8qAAMhAAkJbw1/CACoAQAhAAkJbw1/CACoAQAgAAEJpghLkAA6AAAAAA==.',
Oh='Ohblergen:BAAALgAECgIJAgAAAA==.',
Ok='Okragren:BAABLgAECn81AAIkAAkJhwxKMwBvAQAkAAkJhwxKMwBvAQAAAA==.',
Ol='Olehi:BAAALgADCgcJBwAAAA==.Olynder:BAAALgAECgIJBAAAAA==.',
On='Onos:BAABLgAECn8bAAICAAcJIyQ4IABEAgACAAcJIyQ4IABEAgAAAA==.Onto:BAAALgADCgEJAQAAAA==.Ontoquas:BAAALgADCgkJCgAAAA==.',
Or='Orinin:BAAALgAECgEJAQABLgAECgQJCQADAAAAAA==.',
Pa='Paleclaw:BAAALgADCgQJBAAAAA==.Pally:BAAALgAECgUJBQAAAA==.Papasmurfz:BAAALgAECgEJAwAAAA==.Paramedic:BAAALgAECgUJDwAAAA==.Pathogen:BAABLgAECn8hAAILAAkJDR/lOwARAgALAAkJDR/lOwARAgAAAA==.',
Pe='Penryn:BAAALgAECgQJBAAAAA==.Pepster:BAABLgAECn8XAAInAAkJpQHfLgCAAAAnAAkJpQHfLgCAAAAAAA==.Persephoknee:BAAALgADCgEJAQAAAA==.Persephoni:BAAALgADCgcJBwAAAA==.',
Pf='Pfchen:BAAALgAECgIJAwAAAA==.',
Pl='Plaguestrip:BAAALgAECgEJAgAAAA==.Plinkerbell:BAAALgAECgMJAwAAAA==.Plumprnickel:BAAALgAECgEJAQAAAA==.Plxkingg:BAAALgADCgUJBQAAAA==.',
Po='Poppit:BAAALgAECgQJBQAAAA==.Porimma:BAAALgAECgYJDwAAAA==.Pormas:BAAALgAECgYJDwAAAA==.Poseydon:BAAALgADCgQJBAABLgAECgEJAQADAAAAAA==.',
Pr='Prayerz:BAAALgADCgMJAwAAAA==.Proctology:BAAALgAECgQJBAAAAA==.Prom:BAAALgAECgcJDgAAAA==.Promethèus:BAAALgAECgQJBAAAAA==.Prosby:BAAALgADCgIJAgAAAA==.Prowlnfool:BAAALgADCgUJBQAAAA==.Pryto:BAAALgADCgkJDgABLgAFFAIJAwADAAAAAA==.',
Qu='Queedle:BAABLgAECn8cAAIZAAkJWAkzCwBoAQAZAAkJWAkzCwBoAQAAAA==.',
Ra='Raennis:BAAALgAECgIJAgAAAA==.Ragalstan:BAAALgAECgEJAgAAAA==.Rahanumn:BAABLgAECn8YAAINAAgJ6wkupAAxAQANAAgJ6wkupAAxAQAAAA==.Rainlette:BAAALgAECgcJDgAAAA==.Rainsvoker:BAACLgAFFH8jAAIiAAYJXQ2eEgBqAQAiAAYJXQ2eEgBqAQAuAAQKf1IAAyIACQkOHL8GAJUCACIACQkOHL8GAJUCACAABgk7CAxeAMAAAAAA.Ramike:BAAALgAECggJCQAAAA==.Raqtar:BAAALgAECgIJAgABLgAECgkJEQADAAAAAA==.Ratrazarke:BAAALgADCgIJAgAAAA==.Razihel:BAAALgADCgYJCQAAAA==.',
Re='Reaver:BAAALgAECgQJBAAAAA==.Reddan:BAABLgAECn8qAAINAAgJlgzTmwA+AQANAAgJlgzTmwA+AQAAAA==.Renata:BAAALgAFFAIJAgAAAA==.Replicant:BAAALgAECgEJAQAAAA==.Retman:BAAALgAECgMJAQAAAA==.Reverìe:BAAALgAECgcJBwAAAA==.Reylinn:BAAALgAECgQJBAAAAA==.Reyra:BAAALgAECgEJAQAAAA==.Reï:BAABLgAECn8dAAIPAAkJUBTcJAAlAgAPAAkJUBTcJAAlAgAAAA==.',
Ri='Ridlei:BAAALgAECgMJBAAAAA==.Rimchester:BAAALgAECgIJAQAAAA==.Ritzon:BAABLgAECn89AAMeAAkJJSRgBgD4AgAeAAkJJSRgBgD4AgAdAAEJmBdmcQA+AAAAAA==.',
Ro='Rosadita:BAAALgAECgQJBQAAAA==.Roxydan:BAABLgAECn8dAAMBAAgJiQ03KQAdAQAbAAgJiQ1KZwCWAQABAAYJ8Ag3KQAdAQAAAA==.',
Ru='Runastalis:BAAALgADCgYJBgAAAA==.',
Ry='Ryko:BAABLgAECn8fAAInAAcJqBSRFwBOAQAnAAcJqBSRFwBOAQAAAA==.',
Sa='Sanandume:BAAALgADCgEJAQAAAA==.Sanctess:BAAALgAECggJDgAAAA==.Sankai:BAAALgAECgEJAQABLgAECgYJDgADAAAAAA==.Sarlas:BAAALgADCgQJBAAAAA==.Sarumanpally:BAAALgAECgYJBwAAAA==.Sayomi:BAAALgADCgcJEwAAAA==.',
Se='Secretjuicy:BAAALgAECgYJCQAAAA==.Senseijundra:BAAALgAECgQJCAAAAA==.Sentinaal:BAAALgADCgcJBwAAAA==.',
Sh='Shabadu:BAAALgADCgQJBAAAAA==.Shadyandi:BAAALgADCgcJCAAAAA==.Shamanhack:BAAALgAFFAIJAwAAAA==.Shan:BAAALgADCgYJBgAAAA==.Sharazad:BAAALgAECggJCQAAAA==.Sheda:BAAALgAECgQJBAAAAA==.Shedia:BAAALgAECgEJAQAAAA==.Shmoove:BAEALgAECgUJBgAAAA==.Shmooves:BAEALgAECgQJBAABLgAECgUJBgADAAAAAA==.Shoukei:BAAALgADCgIJAwAAAA==.',
Si='Sianna:BAAALgADCgYJBgAAAA==.Siinful:BAAALgAECgEJAQAAAA==.Simbruh:BAAALgADCgMJAwAAAA==.Sinarria:BAAALgAECgEJAQAAAA==.Sithra:BAAALgADCgEJAQAAAA==.',
Sk='Skeemer:BAAALgAECgUJBQAAAA==.Skeetro:BAAALgAECgEJAQAAAA==.Skips:BAAALgAECgQJCQAAAA==.Skullace:BAABLgAECn8qAAIBAAkJuw9GCgChAQABAAkJuw9GCgChAQAAAA==.Skullhead:BAAALgADCgEJAQAAAA==.Skybreaker:BAAALgAECgkJCAAAAA==.',
Sm='Smashurfacen:BAAALgADCgcJFAAAAA==.',
Sn='Snitbit:BAAALgADCgkJGgAAAA==.Sno:BAAALgADCgEJAQABLgAECgUJBwADAAAAAA==.Snoopingas:BAAALgAECgEJAQAAAA==.Snpcrklpopu:BAAALgADCgYJCAAAAA==.',
So='Solarana:BAAALgAECgkJCQAAAA==.Sortiebatoru:BAAALgAECgIJAwAAAA==.Sotzi:BAAALgADCggJEQAAAA==.Souldune:BAAALgAECgYJBgAAAA==.',
Sp='Sparkplugg:BAAALgAECgEJAQAAAA==.',
Sr='Srfreaky:BAAALgAECgUJDwAAAA==.',
St='Sterlìng:BAAALgAECgUJBQAAAA==.Stevejabbs:BAABLgAECn8hAAMIAAYJgSS4AADgAQAIAAYJgSS4AADgAQAJAAMJ5SABOQAYAQAAAA==.Stormcunning:BAABLgAECn8WAAIkAAYJCAxiTAAWAQAkAAYJCAxiTAAWAQAAAA==.Stormfire:BAAALgADCgcJBwAAAA==.Stormßringer:BAABLgAECn8UAAIkAAgJERDXMwCJAQAkAAgJERDXMwCJAQAAAA==.Stownr:BAAALgAECgYJBgAAAA==.Strip:BAAALgADCgUJCAAAAA==.Strongclaw:BAAALgADCgUJBQAAAA==.Stumpyborg:BAABLgAECn8VAAQBAAcJaAY6MgBVAAAbAAYJNgSn3gCdAAABAAIJMws6MgBVAAAlAAEJhAcbQwArAAABLgAECgkJFwAGAN0LAA==.Stónéhëárt:BAAALgADCgYJBwABLgAECgkJEQADAAAAAA==.',
Su='Subdue:BAAALgADCgQJBAAAAA==.Subverse:BAAALgAECgQJBAAAAA==.Sundance:BAAALgAECgcJDgAAAA==.Sune:BAABLgAECn8gAAMMAAYJxgvURwDwAAAMAAYJxgvURwDwAAAfAAEJNwk2ggAqAAAAAA==.Supplicant:BAAALgADCgQJBwAAAA==.',
Sv='Svellulfr:BAAALgAECgEJAQAAAA==.Svuca:BAAALgADCgcJBwAAAA==.',
Sy='Sydneyweenie:BAAALgADCgcJCAAAAA==.Syldi:BAAALgAECgEJAQABLgAECgYJHAAUAPYbAA==.Sythis:BAAALgAECgIJAwAAAA==.',
['Sä']='Sästa:BAAALgADCgkJCQAAAA==.',
['Sö']='Sörren:BAABLgAECn8fAAIlAAYJQwW0AQCFAAAlAAYJQwW0AQCFAAAAAA==.',
Ta='Tacosdeasada:BAAALgAECgEJAQAAAA==.Taitertot:BAAALgADCgQJBQAAAA==.Tanelórn:BAAALgAECgQJBQAAAA==.Tanlon:BAAALgAECgcJDAAAAA==.Taykorra:BAAALgADCggJDQAAAA==.',
Te='Telandril:BAABLgAECn8vAAIPAAkJvxH5MwDNAQAPAAkJvxH5MwDNAQAAAA==.Telphin:BAAALgAECgYJDAAAAA==.Tempestira:BAAALgAECgEJAgAAAA==.Tensuken:BAABLgAECn8ZAAINAAYJpBigsAAeAQANAAYJpBigsAAeAQAAAA==.Teylonna:BAAALgAECgEJAQAAAA==.',
Th='Thadgun:BAAALgADCgkJFQAAAA==.Thadium:BAAALgADCgYJCQAAAA==.Thalgan:BAAALgAECgEJAQAAAA==.Thalyn:BAAALgAECgEJAQAAAA==.Thecword:BAAALgADCgYJBgAAAA==.Themedic:BAABLgAECn8XAAMWAAcJxRAhUgBqAQAWAAcJxRAhUgBqAQAkAAEJ6gFsxAAXAAAAAA==.Theremar:BAAALgAECgMJAwAAAA==.Thergothon:BAAALgAECgEJAQABLgAECgMJAwADAAAAAA==.Thisisdrexx:BAAALgAECgIJAwAAAA==.Thorwrath:BAAALgADCgEJAgAAAA==.Thrazoro:BAAALgAECgQJBAAAAA==.Thrazzoro:BAAALgAECgYJEwAAAA==.',
Ti='Tiarl:BAABLgAECn81AAIUAAkJHRehEQBUAgAUAAkJHRehEQBUAgAAAA==.Tiia:BAAALgADCgIJAgAAAA==.Timex:BAABLgAECn8XAAMhAAYJRCD5DgDrAQAhAAYJRCD5DgDrAQAgAAEJUhdijgA+AAAAAA==.Tinydots:BAAALgADCgUJBQAAAA==.Tinysitril:BAAALgAECgYJCQABLgAFFAQJCgAYAJ0NAA==.Tinysohei:BAAALgAECgMJAwAAAA==.Tisiphonee:BAAALgADCgEJAQABLgAECggJLQAPAL0RAA==.Titañick:BAAALgAECgEJAwAAAA==.',
To='Tom:BAABLgAECn8XAAMgAAYJLgvwVgDWAAAgAAYJLgvwVgDWAAAhAAEJZQhLJwAvAAAAAA==.Toosxyfohair:BAABLgAECn8aAAIWAAgJExRpLwD4AQAWAAgJExRpLwD4AQAAAA==.',
Tr='Trainwrekk:BAAALgADCgYJBgAAAA==.Tranqar:BAAALgAECgQJBgAAAA==.Tresg:BAAALgAECgYJCQAAAA==.Trissandra:BAAALgAECgEJAQAAAA==.Trolltoll:BAAALgADCgEJAwAAAA==.Trüth:BAAALgADCggJEAAAAA==.',
Tw='Twylidan:BAEALgAECgkJCgABLgAFFAQJCQAgAOkeAA==.',
Ty='Tyrannt:BAAALgAECgEJAQAAAA==.Tyrannus:BAAALgADCgYJBgAAAA==.Tyregar:BAAALgAECgEJAQAAAA==.Tyrànda:BAAALgAECgQJBgAAAA==.Tyzy:BAAALgAECgEJAgAAAA==.',
['Tö']='Tötém:BAAALgAECgEJAQAAAA==.',
Ul='Ulanhi:BAABLgAECn8VAAIcAAUJzh31EACdAQAcAAUJzh31EACdAQAAAA==.',
Un='Undeadjelly:BAAALgAECgYJEwAAAA==.Unholy:BAAALgAECgYJDwAAAA==.',
Ur='Urkzul:BAAALgADCgMJAwAAAA==.Ursoth:BAAALgADCgUJCgAAAA==.',
Ut='Uthèrsmight:BAAALgAECgYJBgAAAA==.Uti:BAAALgADCgUJBQAAAA==.',
Uu='Uubs:BAAALgADCgEJAQABLgAFFAMJCgANAJoSAA==.',
Va='Valakk:BAAALgAECgIJBQAAAA==.Vallak:BAAALgADCgIJBAAAAA==.Valsitril:BAAALgAECgYJEAABLgAFFAQJCgAYAJ0NAA==.Valthaczar:BAAALgAECgMJBgAAAA==.Vanara:BAAALgAECgEJAgAAAA==.Varadun:BAAALgAFFAIJAwAAAA==.Varrosh:BAAALgADCgYJBgAAAA==.Vathan:BAAALgAECgQJBQAAAA==.',
Ve='Velmora:BAAALgAECgkJCQAAAA==.Velsetin:BAABLgAECn8dAAIFAAcJTBsyTABSAgAFAAcJTBsyTABSAgABLgAFFAMJBQAVAMcUAA==.Verathina:BAAALgADCgEJAQAAAA==.Versed:BAAALgADCgUJBQABLgAECgQJBAADAAAAAA==.Veryspooky:BAABLgAECn8aAAIbAAgJNhkFOAD5AQAbAAgJNhkFOAD5AQAAAA==.Vexian:BAABLgAECn8VAAMkAAkJsxscDwB+AgAkAAkJsxscDwB+AgAWAAEJ3B+9twBcAAAAAA==.',
Vf='Vfl:BAAALgADCgcJBwAAAA==.',
Vi='Vicas:BAAALgAECgcJEgAAAA==.',
Vl='Vladdek:BAAALgAFFAEJAQAAAA==.Vladdok:BAAALgAECgUJBQAAAA==.Vladok:BAAALgAECgQJCQAAAA==.Vladokk:BAAALgAECgMJAwAAAA==.',
Vo='Voidofdeath:BAAALgADCgQJBAAAAA==.Voidshiekah:BAAALgADCgEJAQAAAA==.Vorteia:BAAALgADCgYJBgAAAA==.',
['Vé']='Véngéánçé:BAAALgAECgMJBAAAAA==.',
Wa='Wald:BAAALgAECgYJEAAAAA==.Warmongerr:BAAALgADCgIJAgAAAA==.Waruh:BAAALgADCgcJCQAAAA==.',
We='Webgar:BAAALgAECgEJAQAAAA==.',
Wh='Whisperlia:BAAALgAECgQJBgAAAA==.Whisperwindd:BAAALgAECgUJAwAAAA==.White:BAAALgAFFAEJAgAAAA==.Whitetoothe:BAABLgAECn8sAAICAAcJqxadVgCgAQACAAcJqxadVgCgAQAAAA==.',
Wi='Witemandown:BAAALgADCgcJCAAAAA==.Witherbear:BAAALgADCgcJBwAAAA==.Witherhoard:BAAALgADCgEJAQAAAA==.Wizzy:BAAALgADCgEJAQAAAA==.',
Wo='Workin:BAAALgADCgEJAQABLgAECgcJGwAPAIAYAA==.',
['Wå']='Wånheda:BAAALgAECggJEwAAAA==.',
Xa='Xaniana:BAAALgAECgkJDwAAAA==.Xaosin:BAAALgADCgUJBQAAAA==.',
Xe='Xenzak:BAAALgAECgEJAQAAAA==.Xephir:BAAALgADCgMJAwAAAA==.Xerxës:BAAALgAECgEJAQAAAA==.',
Xl='Xl:BAAALgAECgQJCwAAAA==.',
Xo='Xoito:BAAALgAECgEJAQABLgAECgcJBQADAAAAAA==.Xotiko:BAAALgAECgYJDAAAAA==.',
Xu='Xubris:BAAALgADCgYJCQAAAA==.',
['Xâ']='Xâxâs:BAAALgAECgMJAwABLgAECggJGQAgAFsEAA==.',
Ya='Yaerin:BAACLgAFFH8ZAAIfAAQJcCMmGwCKAQAfAAQJcCMmGwCKAQAuAAQKfyQAAh8ACQkAIvMDAFsDAB8ACQkAIvMDAFsDAAAA.',
Yu='Yunarä:BAAALgAECgYJCAAAAA==.Yuukon:BAABLgAECn8ZAAQTAAgJkRXuHABxAQATAAgJkRXuHABxAQALAAQJ5gOPOQFkAAAHAAEJDwgrGAAvAAAAAA==.',
Za='Zakuul:BAAALgADCgQJBAAAAA==.Zalezaar:BAAALgAECgIJAgAAAA==.Zangetsu:BAAALgAECgcJBwAAAA==.Zaxie:BAABLgAECn83AAISAAkJWx37EgCrAgASAAkJWx37EgCrAgAAAA==.',
Ze='Zenwu:BAAALgADCgkJGwAAAA==.Zephrylia:BAAALgAECgQJBQAAAA==.Zerama:BAAALgAECgUJBQAAAA==.',
Zh='Zheratul:BAAALgAECgEJAQAAAA==.Zhirl:BAAALgAECgkJCQAAAA==.Zhivet:BAAALgAECgYJBwAAAA==.',
Zi='Zilphia:BAAALgAECggJEgAAAA==.',
Zu='Zuriel:BAAALgAECgIJAgAAAA==.',
Zy='Zyku:BAAALgAECgEJAQAAAA==.Zylphie:BAAALgADCgcJBwAAAA==.',
['Àm']='Àmagezing:BAAALgAFFAIJAgAAAA==.',
['Åj']='Åj:BAAALgADCgcJBwAAAA==.',
['Åp']='Åpexx:BAABLgAECn8aAAMSAAYJ1AWcBgBzAAASAAYJtAWcBgBzAAAYAAEJzAYafQAjAAAAAA==.',
['Çw']='Çwÿbàbý:BAAALgAECgIJBQAAAA==.',
['Ór']='Órión:BAABLgAECn8VAAICAAYJ1BLsoQD+AAACAAYJ1BLsoQD+AAAAAA==.',
['Ös']='Östara:BAABLgAECn8bAAIPAAcJgBhJLQDyAQAPAAcJgBhJLQDyAQAAAA==.',
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
