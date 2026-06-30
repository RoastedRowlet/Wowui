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

local lookup = {'Warlock-Destruction','Hunter-BeastMastery','Unknown-Unknown','Mage-Arcane','Mage-Frost','DeathKnight-Unholy','Hunter-Survival','DeathKnight-Frost','Monk-Mistweaver','Monk-Brewmaster','Monk-Windwalker','Priest-Shadow','Paladin-Retribution','Druid-Guardian','Druid-Restoration','Hunter-Marksmanship','Paladin-Protection','DemonHunter-Devourer','DeathKnight-Blood','Priest-Holy','Druid-Balance','Shaman-Restoration','Rogue-Subtlety','DemonHunter-Havoc','Rogue-Outlaw','Rogue-Assassination','Warlock-Demonology','Druid-Feral','Warrior-Arms','Warrior-Fury','Priest-Discipline','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Warrior-Protection','Shaman-Elemental','Warlock-Affliction','Paladin-Holy','Shaman-Enhancement',}
local provider = {region='US',realm='Azuremyst',name='US',type='weekly',zone=46,date='2026-06-27',data={Aa='Aaravos:BAABLgAECn8cAAIBAAgJShjRBwDUAQABAAgJShjRBwDUAQAAAA==.',
Ab='Abysseon:BAAALgAECgUJDgAAAA==.',
Ac='Accretion:BAAALgAECgYJBgAAAA==.',
Ad='Adaria:BAABLgAECn8WAAICAAcJWAWSZQA3AQACAAcJWAWSZQA3AQAAAA==.Adrillbear:BAAALgAECgIJAgABLgAECgYJEwADAAAAAA==.Adura:BAAALgAECgQJBQAAAA==.',
Ae='Aeirith:BAACLgAFFH8OAAIEAAQJ5hRoAQAjAQAEAAQJ5hRoAQAjAQAuAAQKfyQAAwQACQmwHegBAGYCAAQACQmwHegBAGYCAAUAAQlFChlgATEAAAAA.Aelion:BAAALgAECgEJAQAAAA==.',
Ah='Ahheevoker:BAAALgAECgYJEgAAAA==.',
Ai='Ailsà:BAAALgADCgEJAQAAAA==.',
Ak='Akarias:BAAALgAECgEJAQABLgAECgcJBwADAAAAAA==.',
Al='Aladaria:BAAALgAECgMJAwAAAA==.Aldyah:BAAALgAFFAMJAwAAAA==.Alias:BAAALgAECgYJBQAAAA==.Allanonn:BAAALgAECgQJBAAAAA==.Alohomora:BAAALgAECgUJEAAAAA==.Alprazolam:BAAALgAECgEJAQAAAA==.Alvist:BAABLgAECn8UAAIGAAQJrx6gggBeAQAGAAQJrx6gggBeAQAAAA==.',
Am='Amarasu:BAABLgAECn8cAAIHAAkJig+RGwDBAQAHAAkJig+RGwDBAQAAAA==.Amarlly:BAABLgAECn8xAAIIAAkJJxngBwAVAgAIAAkJJxngBwAVAgAAAA==.Amenedil:BAAALgAECgUJDAAAAA==.',
An='Anbrew:BAABLgAECn8UAAQJAAcJdxJoSwA/AQAJAAYJDBJoSwA/AQAKAAUJjA6FQAD4AAALAAEJMwe0rwAlAAABLgAFFAYJDwAGAN0dAA==.Ancelina:BAABLgAECn8qAAIMAAkJeyR3AgBCAwAMAAkJeyR3AgBCAwAAAA==.Anderton:BAABLgAECn8xAAINAAgJShnQSwDjAQANAAgJShnQSwDjAQAAAA==.Andilocks:BAAALgADCgMJAwAAAA==.Andrela:BAAALgAECgIJAgAAAA==.Aneira:BAABLgAECn8iAAMOAAYJ8hF2AwD/AAAOAAYJ8hF2AwD/AAAPAAMJYQySmQB/AAAAAA==.Annovera:BAAALgAECgMJBgAAAA==.Anuubis:BAAALgADCgYJBgAAAA==.Anyi:BAAALgAECgEJAQAAAA==.',
Ap='Apexxd:BAAALgAECgMJAwAAAA==.Applefritter:BAAALgAECgUJCAABLgAECgkJKAAMAJYbAA==.',
Ar='Araga:BAAALgAECgEJAQAAAA==.Archérhiro:BAACLgAFFH8nAAMCAAgJkRXHCAAyAgACAAcJUxjHCAAyAgAQAAMJRwTfIQCHAAAuAAQKfykAAwIACQlYH+0YAJECAAIACQlMH+0YAJECABAACAkrGdobAEoCAAAA.Arilias:BAAALgAECgEJAQABLgAECgkJPAACABIfAA==.Arillann:BAABLgAECn89AAIRAAkJUR+3BACuAgARAAkJUR+3BACuAgAAAA==.Arrook:BAAALgAECgMJAwAAAA==.Arrtonomis:BAAALgAECgUJCAABLgAECgkJEgADAAAAAA==.Artdemsamis:BAAALgAECgkJEgAAAA==.Arte:BAABLgAECn89AAICAAkJaxOnLAABAgACAAkJaxOnLAABAgAAAA==.Arthundermis:BAAALgAECgkJEQABLgAECgkJEgADAAAAAA==.Artlunarmis:BAAALgADCgEJAQABLgAECgkJEgADAAAAAA==.Arvena:BAABLgAECn8nAAISAAkJVgoWdAA5AQASAAkJVgoWdAA5AQAAAA==.',
As='Asclëpius:BAAALgADCgcJBgABLgAECgEJAQADAAAAAA==.Asheron:BAAALgAECgYJCAAAAA==.Ashylock:BAAALgAECgEJAQABLgAFFAUJDgAFAGAWAA==.Ashymage:BAACLgAFFH8OAAIFAAUJYBabYAAgAQAFAAUJYBabYAAgAQAuAAQKfzcAAgUACQlYHLYpAMwCAAUACQlYHLYpAMwCAAAA.Askevar:BAABLgAECn8nAAMGAAkJYAs9CgDpAAATAAYJ5wlHJwAEAQAGAAkJjAk9CgDpAAAAAA==.Aspect:BAAALgADCgEJAQABLgAFFAIJAwADAAAAAA==.Asriél:BAAALgAECgYJBwAAAA==.Astor:BAAALgADCgMJBQAAAA==.Astrona:BAAALgADCgkJFwAAAA==.',
At='Atreus:BAABLgAECn8YAAINAAkJbAXUwQAGAQANAAkJbAXUwQAGAQAAAA==.Attalaguy:BAAALgAECgYJDgAAAA==.',
Au='Audra:BAAALgADCgcJDgAAAA==.',
Av='Avabeatrix:BAAALgADCgEJAQAAAA==.Avinthoro:BAAALgADCgIJAgAAAA==.',
Ay='Ayyayyron:BAAALgAECgUJCQAAAA==.',
Az='Azaleah:BAABLgAECn9KAAINAAkJRx3xGQCoAgANAAkJRx3xGQCoAgAAAA==.Azanoth:BAAALgADCgIJAgAAAA==.Azraesha:BAABLgAECn8rAAISAAkJ/BUDKgAhAgASAAkJ/BUDKgAhAgAAAA==.Azureflamez:BAAALgAECgEJAQAAAA==.Azurewraith:BAAALgAECgQJBAAAAA==.Azzul:BAAALgADCgcJBwAAAA==.',
Ba='Backy:BAAALgADCgkJDAAAAA==.Baiken:BAAALgAECgIJAgABLgAECgQJCAADAAAAAA==.Banjoman:BAABLgAECn8kAAIUAAcJXSTpCgC4AgAUAAcJXSTpCgC4AgAAAA==.Baza:BAAALgADCgYJBgAAAA==.Baýlei:BAABLgAECn8WAAIJAAYJ5A0kWwAHAQAJAAYJ5A0kWwAHAQAAAA==.',
Be='Beareold:BAAALgAECgIJAgAAAA==.Beary:BAAALgAECgQJCAAAAA==.Beenaughty:BAAALgAECgEJAQABLgAECgEJAQADAAAAAA==.Belaanna:BAAALgADCgYJCQAAAA==.Beliria:BAAALgADCgUJBgAAAA==.Benimaru:BAAALgAECgUJDwAAAA==.Beriko:BAAALgAECgMJAwAAAA==.Bernat:BAAALgAECgEJAQAAAA==.Beàrdfáce:BAAALgADCgQJBAAAAA==.',
Bi='Bigblunt:BAAALgAECgEJAQAAAA==.Bigjuicy:BAAALgAECggJEAAAAA==.Billie:BAAALgAECgYJCAAAAA==.Bimboficate:BAAALgADCgYJBwAAAA==.',
Bl='Black:BAAALgAECgQJBAAAAA==.Blackadder:BAABLgAECn8lAAIRAAYJuw7kAgDqAAARAAYJuw7kAgDqAAAAAA==.Blessthefall:BAAALgAECgcJCwAAAA==.Blondie:BAAALgADCgQJBAABLgAECgYJEwADAAAAAA==.Bloodie:BAAALgAECgMJAwAAAA==.Blue:BAABLgAECn88AAILAAkJxRvlDgBbAgALAAkJxRvlDgBbAgAAAA==.Blueguy:BAAALgAECgQJBgAAAA==.Bluestreak:BAAALgAECgEJAwABLgAECgcJCQADAAAAAA==.',
Bo='Bobthefist:BAAALgADCgcJBwAAAA==.Bode:BAAALgAECgYJEwAAAA==.Bogern:BAAALgADCgcJBwAAAA==.Bolau:BAAALgADCgYJBwAAAA==.Boltz:BAAALgADCgYJBgAAAA==.Boogy:BAAALgAECgkJBgAAAA==.Bopdiz:BAAALgAECgEJAQABLgAECgQJFAAGAK8eAA==.Borledish:BAAALgAECgMJBAABLgAECgQJFAAGAK8eAA==.Bottosai:BAAALgAECgEJAgAAAA==.',
Br='Brambles:BAAALgAECgEJAQAAAA==.Branwynn:BAAALgAECgMJCQAAAA==.Breezyfight:BAAALgAFFAIJAgAAAA==.Breezyrocks:BAAALgADCgQJCQAAAA==.Breezysha:BAAALgADCgcJCAAAAA==.Brenz:BAABLgAFFH8GAAMNAAMJOQIKqgBuAAANAAMJOwEKqgBuAAARAAEJvQR6HAAhAAAAAA==.Brewdaddy:BAAALgAECgUJEwABLgAECgkJOQARAHwRAA==.Brewdude:BAAALgAECgEJAQAAAA==.Brigor:BAAALgAECgYJCwAAAA==.Brokenblade:BAAALgADCgYJBgAAAA==.Brotherblood:BAAALgAECgUJCwAAAA==.',
Bu='Bulldoza:BAAALgAECgQJBQAAAA==.Bullwinkles:BAAALgAECgEJAQAAAA==.Butterknifeo:BAABLgAFFH8FAAIVAAMJxxSHMQC7AAAVAAMJxxSHMQC7AAAAAA==.',
By='Byryja:BAABLgAECn8kAAIFAAYJIQiMEQCvAAAFAAYJIQiMEQCvAAAAAA==.',
Ca='Cahrazie:BAACLgAFFH8GAAINAAMJ9wkqewDAAAANAAMJ9wkqewDAAAAuAAQKfx0AAg0ACQkaFQUHAEMBAA0ACQkaFQUHAEMBAAAA.Caidinn:BAAALgAECgkJEQAAAA==.Caitrîn:BAAALgADCgkJCQABLgAECgYJIgAOAPIRAA==.Calissancia:BAABLgAECn82AAIJAAgJNBdEHwAgAgAJAAgJNBdEHwAgAgAAAA==.Calkey:BAABLgAECn8WAAIBAAYJUQgMHwCyAAABAAYJUQgMHwCyAAAAAA==.Carvana:BAAALgAECgkJBwAAAA==.Cathandris:BAAALgADCgEJAQAAAA==.',
Ce='Ceri:BAAALgAECgkJBwAAAA==.',
Ch='Chadarack:BAAALgAECgYJBwAAAA==.Chadaracks:BAAALgAECgEJAQAAAA==.Chancy:BAAALgAECgMJBAAAAA==.Channingtotm:BAACLgAFFH8sAAIWAAUJsyUpAgD2AQAWAAUJsyUpAgD2AQAuAAQKfzcAAhYACQlhIY4EAG4DABYACQlhIY4EAG4DAAAA.Chantix:BAAALgADCgUJBQAAAA==.Charlemoo:BAAALgADCgUJBQABLgAECgMJAwADAAAAAA==.Cheekymonkey:BAABLgAECn8qAAIEAAkJMQ3MAAD+AAAEAAkJMQ3MAAD+AAAAAA==.Chrispbacon:BAAALgAECgUJEgAAAA==.Chueyé:BAAALgAECgMJAwABLgAFFAMJCgAXAO8dAA==.Chunkyy:BAAALgADCgYJBgAAAA==.Churros:BAABLgAECn8oAAMMAAkJlhuVEQBJAgAMAAkJlhuVEQBJAgAUAAcJThV3JwCKAQAAAA==.',
Ci='Cincog:BAAALgAECgQJBAABLgAECgYJCQADAAAAAA==.',
Cl='Closetcookie:BAAALgAECgQJBAAAAA==.',
Co='Coberren:BAAALgAECgEJAQAAAA==.Cordialkylie:BAAALgAECgIJAgAAAA==.Cowcrusader:BAAALgADCgcJBwAAAA==.',
Cr='Crazyugly:BAAALgAECgQJBQAAAA==.Crogrer:BAAALgAECgMJAwAAAA==.Crosslock:BAAALgAECgUJDwAAAA==.',
Cu='Cuppycakes:BAAALgADCgcJFAAAAA==.',
Cy='Cynnari:BAAALgAECgUJCgAAAA==.',
Da='Daddysecret:BAAALgAECgQJBQAAAA==.Dalan:BAAALgAECgIJAgABLgAFFAQJDgAEAOYUAA==.Dalaris:BAACLgAFFH8KAAIYAAQJnQ2kBQDiAAAYAAQJnQ2kBQDiAAAuAAQKfyIAAhgACQmdFiASAAoCABgACQmdFiASAAoCAAAA.Danizmi:BAAALgADCgQJBAAAAA==.Dano:BAAALgADCgYJDQAAAA==.Darci:BAAALgAECgYJCwAAAA==.Darkeon:BAAALgAECgcJCwAAAA==.Darlenedark:BAAALgAECgEJAQAAAA==.Darling:BAAALgAECgIJAgAAAA==.Darron:BAAALgAECgIJBAABLgAECggJEgADAAAAAA==.Darrosh:BAABLgAECn8bAAQZAAgJuxOEEgDhAAAZAAYJDhCEEgDhAAAXAAcJjQ34PgDLAAAaAAMJ9hB8FAC1AAAAAA==.Dartian:BAAALgADCgcJDQABLgAECgkJPAACABIfAA==.Daylightt:BAAALgAECgIJAgAAAA==.Dazdot:BAAALgADCgQJBAABLgAECgEJAQADAAAAAA==.Dazsham:BAAALgAECgEJAQAAAA==.',
De='Deadjuicy:BAAALgAECgEJAQAAAA==.Deathdevil:BAAALgAECgUJBQAAAA==.Deathlurker:BAAALgADCgQJBAAAAA==.Deathmare:BAAALgAECgUJBQAAAA==.Deathmommy:BAAALgAECgcJCAAAAA==.Deathty:BAAALgAECgMJCgABLgAFFAEJAgADAAAAAA==.Dementia:BAAALgADCgMJAwAAAA==.Design:BAABLgAECn8lAAIbAAkJ4Rc7MgAPAgAbAAkJ4Rc7MgAPAgAAAA==.Desmeridian:BAAALgAECgUJBQAAAA==.Devotee:BAAALgADCgIJAgAAAA==.',
Dh='Dhish:BAABLgAECn8bAAQVAAYJpAcaBgC6AAAVAAYJpAcaBgC6AAAcAAMJMwdTPABoAAAPAAIJ6gIc1AAxAAAAAA==.',
Di='Diltlish:BAAALgAECgMJBQAAAA==.Diocles:BAAALgAECgUJBgAAAA==.Disconcern:BAAALgAECgEJAQAAAA==.Discontent:BAACLgAFFH8GAAIdAAIJUR2wMwCNAAAdAAIJUR2wMwCNAAAuAAQKfxQAAx0ABwnwHKQQAOkBAB0ABwnwHKQQAOkBAB4ABQknEVxuAP0AAAAA.Discordiä:BAABLgAECn8XAAIfAAgJHRf9HQDeAQAfAAgJHRf9HQDeAQAAAA==.Discspal:BAAALgAECgYJBwAAAA==.Diåblo:BAAALgADCgUJBQAAAA==.',
Dm='Dmginc:BAAALgADCgIJAgAAAA==.',
Do='Doeblin:BAAALgAECgUJEwAAAA==.Domidouse:BAAALgAECgUJCQAAAA==.Donkedixon:BAAALgADCgYJBgAAAA==.Dosar:BAAALgADCgIJAgAAAA==.Doubtz:BAAALgAECgQJBQABLgAECgQJFAAGAK8eAA==.',
Dp='Dpalx:BAAALgAECgQJBAAAAA==.Dpxs:BAABLgAFFH8HAAIWAAQJkha7PwDmAAAWAAQJkha7PwDmAAAAAA==.',
Dr='Dracaria:BAAALgAECgEJAQAAAA==.Dracones:BAAALgAECgYJDgAAAA==.Dragondz:BAAALgAECgUJBQAAAA==.Dragonflai:BAABLgAECn8nAAIFAAkJnBdCUwDjAQAFAAkJnBdCUwDjAQAAAA==.Dragonkin:BAAALgAECgQJCAAAAA==.Drakkari:BAAALgAECgYJDgAAAA==.Drakkei:BAABLgAECn9DAAMCAAkJBxoDJABTAgACAAkJBxoDJABTAgAHAAMJIga/SQCSAAAAAA==.Drawbridge:BAAALgAECgEJAQAAAA==.Drerane:BAAALgADCgYJBgAAAA==.Drexxsster:BAAALgADCgQJBAAAAA==.Drshortbus:BAAALgAECgUJCgAAAA==.Drumitus:BAAALgADCgYJCAAAAA==.Drunkngrundl:BAABLgAECn89AAIKAAkJHiMoBAAGAwAKAAkJHiMoBAAGAwAAAA==.Drylo:BAECLgAFFH8MAAMgAAQJ6R51IABcAQAgAAQJ6R51IABcAQAhAAEJFB6mAgBaAAAuAAQKfy0AAyAACQkmII4JAL8CACAACQmLHo4JAL8CACEACAnFH6UGAIgCAAAA.',
Du='Duckeey:BAAALgAFFAEJAgABLgAFFAUJFQAFAJ4OAA==.Dunstir:BAABLgAECn8ZAAINAAgJ6QUgwAAIAQANAAgJ6QUgwAAIAQAAAA==.Dusktrekker:BAAALgAECgkJBwAAAA==.',
Dy='Dypshyt:BAABLgAECn8aAAQgAAkJhxfkTwDvAAAhAAUJUBJRIgAYAQAgAAYJqxDkTwDvAAAiAAUJTgemLgB1AAAAAA==.Dyyke:BAAALgAECgEJAQAAAA==.',
Ed='Edelweíss:BAAALgAECgQJCwAAAA==.',
Ek='Ekazzik:BAAALgAECgYJBgABLgAECgcJGgAjABMXAA==.Ekoh:BAAALgAECgIJAgAAAA==.',
El='Elarol:BAAALgAECgEJAgAAAA==.Eldons:BAAALgADCgIJAgAAAA==.',
Em='Embers:BAABLgAECn8WAAIeAAYJGxPjWADrAAAeAAYJGxPjWADrAAAAAA==.Emeralde:BAAALgAECgYJCgAAAA==.Emilia:BAAALgADCgIJAwAAAA==.Emptyhands:BAAALgAECgYJBgAAAA==.Emptyheals:BAABLgAECn8xAAIfAAkJ3yC7BABEAwAfAAkJ3yC7BABEAwAAAA==.',
En='Enticedem:BAAALgAECgEJAQAAAA==.',
Er='Ereada:BAAALgADCgUJCgAAAA==.Erfinden:BAAALgADCgEJAQAAAA==.',
Es='Espernite:BAAALgAECgQJBAAAAA==.Espers:BAACLgAFFH8GAAIVAAMJCgeuDQCkAAAVAAMJCgeuDQCkAAAuAAQKfx8AAhUACQnpD68+ABQBABUACQnpD68+ABQBAAAA.',
Et='Ethellin:BAABLgAECn84AAINAAkJbQebDgDGAAANAAkJbQebDgDGAAAAAA==.',
Fa='Fahrenheit:BAAALgAECgEJAgAAAA==.Farkuat:BAAALgADCgQJBAAAAA==.Fatcastle:BAAALgADCgcJDgAAAA==.',
Fe='Feedmepizzas:BAAALgAECgMJCAAAAA==.Feildmedic:BAAALgAECgEJAQAAAA==.Feleria:BAAALgAECgUJDAAAAA==.Fellslasher:BAAALgAECgIJAgAAAA==.Felmage:BAAALgADCgYJBgAAAA==.Felraiser:BAAALgADCgIJAgABLgADCgUJBgADAAAAAA==.Felwinter:BAABLgAECn81AAIbAAkJthrMIQBbAgAbAAkJthrMIQBbAgAAAA==.Femcelgoon:BAAALgADCgEJAQAAAA==.Fenna:BAAALgADCgYJDAAAAA==.Fetor:BAAALgAECgcJEAAAAA==.',
Fi='Fingulfin:BAAALgAECgEJAQAAAA==.Finwé:BAAALgAECgQJCgAAAA==.Fistsalot:BAAALgAECgQJCAAAAA==.',
Fl='Flafferthorn:BAAALgAECgMJAwAAAA==.Fluxarata:BAABLgAECn8rAAISAAkJ9g27UwCLAQASAAkJ9g27UwCLAQAAAA==.',
Fo='Forthememes:BAAALgAECgcJCQAAAA==.',
Fr='Fred:BAABLgAECn8tAAIeAAgJ5wrGPQBPAQAeAAgJ5wrGPQBPAQAAAA==.Freddrick:BAAALgADCgQJBAAAAA==.Friendly:BAAALgAECgEJAQAAAA==.Frostbuddy:BAAALgAECgcJDQAAAA==.Frëya:BAAALgADCgYJDQAAAA==.Frío:BAAALgAECgEJAQAAAA==.Frøstitute:BAABLgAECn8tAAIFAAkJwRenMwBKAgAFAAkJwRenMwBKAgAAAA==.',
Fu='Fullmage:BAAALgADCgQJBAAAAA==.',
['Fè']='Fènrïr:BAAALgADCgQJBAAAAA==.',
Ga='Gabel:BAABLgAECn8nAAIcAAkJQh3JBgB2AgAcAAkJQh3JBgB2AgAAAA==.Gadnabit:BAAALgADCgkJCQAAAA==.Gailardia:BAACLgAFFH8FAAICAAMJkhJfFwDnAAACAAMJkhJfFwDnAAAuAAQKfyQAAgIABwn/HYUvAB4CAAIABwn/HYUvAB4CAAEuAAUUBAkYABQAvR0A.Galand:BAABLgAECn8mAAMGAAcJGB21BgAvAQAGAAcJqBy1BgAvAQATAAIJoiFoUABTAAAAAA==.Galladin:BAAALgADCggJDgAAAA==.Gardyson:BAABLgAECn8aAAMjAAcJExe5AgDwAAAjAAcJExe5AgDwAAAeAAEJbQNKtAAhAAAAAA==.Gazton:BAAALgAECgUJBQAAAA==.',
Gl='Glaaki:BAAALgAECgUJCwAAAA==.',
Gn='Gnob:BAAALgAECgUJEAAAAA==.',
Go='Gooblet:BAAALgADCgQJBQAAAA==.Goodfellow:BAAALgAECgEJAQABLgAECgYJFQAcAMUcAA==.Goopy:BAAALgADCgYJAwAAAA==.',
Gr='Graendal:BAAALgADCgQJBAAAAA==.Granite:BAAALgAECgMJBAAAAA==.Granted:BAAALgADCgUJBQAAAA==.Greevil:BAAALgAECgEJAwAAAA==.Gremilien:BAABLgAECn8qAAIQAAkJExVCCgDMAQAQAAkJExVCCgDMAQAAAA==.Grimgorr:BAAALgADCgMJAwAAAA==.Grimmly:BAAALgAECgEJAQAAAA==.Grymdevours:BAAALgADCgYJBgAAAA==.',
Ha='Halcyonic:BAAALgAECgUJCgAAAA==.Halleyscomet:BAABLgAECn8WAAINAAcJPBptRAAXAgANAAcJPBptRAAXAgAAAA==.Happyhammer:BAAALgADCgcJCAAAAA==.Harrod:BAAALgAECggJCwAAAA==.Hawkwave:BAAALgAECgcJEgABLgAECgkJEQADAAAAAA==.Hazardzone:BAAALgAECgMJCgAAAA==.',
He='Heartburn:BAAALgAFFAEJAQABLgAFFAYJHQAeAAUdAA==.Heavyweather:BAAALgADCgcJBwAAAA==.Hefty:BAABLgAECn8XAAMHAAkJ3QtnKQBVAQAHAAcJKQtnKQBVAQACAAUJ8gm3owD6AAAAAA==.Heftyer:BAAALgAECgMJAwAAAA==.Helioween:BAAALgADCgMJAwAAAA==.Helixon:BAAALgADCgYJBgAAAA==.Hellbad:BAACLgAFFH8MAAIKAAQJ7hO+KAAGAQAKAAQJ7hO+KAAGAQAuAAQKfxUAAwoACAleGMEnAHMBAAsABgmOG30jALoBAAoACAkXEsEnAHMBAAAA.Hellbine:BAAALgADCgMJAgAAAA==.Hellfella:BAAALgAECgEJAQAAAA==.Hellonheels:BAAALgAECgQJBAAAAA==.Hellsspawn:BAAALgAECgYJEAAAAA==.Hexaverse:BAAALgADCgYJBgABLgAECgQJBAADAAAAAA==.',
Ho='Hoardwither:BAAALgAECgEJAgAAAA==.Hoenheim:BAAALgAECgEJAQAAAA==.Hogrog:BAAALgADCgMJAwAAAA==.Hokàge:BAACLgAFFH8KAAIXAAMJ7x3+JAD8AAAXAAMJ7x3+JAD8AAAuAAQKfzkABBcACQkpIvQIAJYCABcACQkpIvQIAJYCABoAAgkCGhgbAIwAABkAAQkZAlosAAkAAAAA.Holyballs:BAAALgAECgYJCgAAAA==.Homealone:BAABLgAECn8ZAAMWAAgJ5whefADrAAAWAAcJwwZefADrAAAkAAUJ8gPZfQB3AAAAAA==.',
Hu='Huffles:BAAALgAECgQJBwAAAA==.Hugmachine:BAAALgAFFAIJAgAAAA==.Huntinfuzzy:BAAALgAECgkJDwAAAA==.Huntn:BAAALgADCggJCAAAAA==.',
Hy='Hypahypa:BAAALgAECggJCgAAAA==.',
Ia='Iamknot:BAAALgAECgQJBgAAAA==.',
Ic='Icemommy:BAAALgADCgQJCAAAAA==.',
Ig='Igothots:BAACLgAFFH8FAAIPAAIJZBDKVQBvAAAPAAIJZBDKVQBvAAAuAAQKfx4AAw8ACQl/HgIQALgCAA8ACQl/HgIQALgCABwAAQltCb9YACkAAAAA.',
Il='Illariana:BAABLgAECn8aAAQMAAgJNRI5LABzAQAMAAgJNRI5LABzAQAUAAEJwQLCegAfAAAfAAEJvgHGigAdAAAAAA==.Illirotica:BAAALgAECgcJCQAAAA==.',
In='Incredibro:BAAALgADCgEJAQAAAA==.Insanitty:BAAALgAECgcJDwAAAA==.Invincible:BAAALgAECgEJAQABLgAECgYJIgAJAIEkAA==.',
Ir='Ironlobo:BAABLgAECn8YAAIFAAYJhxkZfACAAQAFAAYJhxkZfACAAQAAAA==.Ironsolari:BAAALgADCgYJBgAAAA==.Irritable:BAABLgAECn8jAAMlAAkJARs/AwCHAgAlAAkJARs/AwCHAgAbAAEJJRftIQFGAAAAAA==.',
It='Itherious:BAAALgAECgUJEAAAAA==.',
Ja='Jacham:BAABLgAECn8WAAIeAAkJ2hSIHwDzAQAeAAkJ2hSIHwDzAQAAAA==.Jackyll:BAAALgAECgQJCAAAAA==.Jacmehof:BAAALgADCgIJAgAAAA==.Jagerboy:BAAALgAECgYJBgAAAA==.Jango:BAAALgAECgIJAgABLgAECgcJGgAjABMXAA==.Jatix:BAACLgAFFH8TAAINAAQJpR6TDQAZAQANAAQJpR6TDQAZAQAuAAQKfyoAAg0ACQkcI3kPAOoCAA0ACQkcI3kPAOoCAAAA.',
Je='Jeetkundo:BAAALgADCgEJAQABLgAECgYJIgAJAIEkAA==.Jellydh:BAAALgAECgUJCgAAAA==.Jellymagus:BAAALgAECgIJAgAAAA==.Jellyms:BAAALgAECgYJDQAAAA==.Jellyspinoff:BAAALgAECgMJBwAAAA==.Jellytown:BAABLgAECn89AAIFAAkJaxRVRQALAgAFAAkJaxRVRQALAgAAAA==.Jelorinea:BAAALgAECgMJBgAAAA==.Jemmi:BAAALgADCgEJAQAAAA==.Jessiana:BAAALgAECgYJEQAAAA==.Jezelda:BAAALgAECgQJBgAAAA==.',
Jo='Joeydonuts:BAEALgAECgMJAwABLgAECgUJBgADAAAAAA==.',
Jp='Jpeppers:BAABLgAECn8eAAICAAYJORbsCAAxAQACAAYJORbsCAAxAQAAAA==.',
Ju='Judgementalx:BAAALgAFFAEJAQAAAA==.Juicifer:BAAALgAECgEJAgAAAA==.Jumano:BAAALgAECgUJCgAAAA==.Jundra:BAAALgAECgUJCgAAAA==.Jurih:BAAALgADCgIJAgAAAA==.',
Ka='Kaineh:BAABLgAECn8oAAIQAAgJah3WBQA/AgAQAAgJah3WBQA/AgAAAA==.Kainë:BAAALgADCgIJAgAAAA==.Kait:BAABLgAECn8+AAICAAkJ6R8zEQDHAgACAAkJ6R8zEQDHAgAAAA==.Kaladil:BAAALgAECgcJDgAAAA==.Kamis:BAAALgAECgMJAwAAAA==.Kanaga:BAAALgAECgQJBQAAAA==.Kannan:BAABLgAECn8YAAMSAAgJzxv/LwA8AgASAAgJzxv/LwA8AgAYAAEJAQdWeQAqAAAAAA==.Kashmihhr:BAAALgADCgIJAgAAAA==.Kashmir:BAAALgAECgQJBAAAAA==.Kasmes:BAAALgADCggJGQAAAA==.Kasmius:BAAALgAECgMJAwAAAA==.Kasmus:BAAALgAECgQJCAAAAA==.Kawdor:BAABLgAECn85AAQRAAkJfBHfFwBgAQARAAgJ2xDfFwBgAQAmAAcJxBOQBADxAAANAAMJ8wrNQQFqAAAAAA==.',
Ke='Keetsz:BAAALgAECgYJDAAAAA==.Kelaino:BAAALgADCgQJBQAAAA==.Keledish:BAAALgADCgEJAQAAAA==.',
Kh='Khansmebduke:BAACLgAFFH8FAAMYAAQJNxakGQDUAAAYAAMJkRmkGQDUAAASAAEJKgzfnQA9AAAuAAQKfxYAAxgACAmlHC4WANkBABIACAk1F1w+APsBABgABwlXHS4WANkBAAEuAAUUBQkJABwAjh4A.Khota:BAAALgADCgEJAQAAAA==.',
Ki='Kiaf:BAAALgADCgcJDQAAAA==.Kiba:BAAALgADCgEJAQAAAA==.Killanick:BAAALgAECgEJAQAAAA==.Killdar:BAAALgAECgQJBAAAAA==.Kimia:BAAALgADCgYJCQAAAA==.Kirtthedirt:BAAALgAECgYJBwAAAA==.Kirtthehurt:BAABLgAECn8pAAIFAAkJShhlMABXAgAFAAkJShhlMABXAgAAAA==.',
Ko='Koldfront:BAAALgAECgUJCwAAAA==.Kollinator:BAABLgAECn8XAAICAAYJ9RZXBgBqAQACAAYJ9RZXBgBqAQAAAA==.Korso:BAAALgADCgUJCwABLgAECgYJIgAOAPIRAA==.Kotal:BAAALgAECgEJAQAAAA==.',
Ky='Kylair:BAABLgAECn80AAIMAAkJ/B4cCgCtAgAMAAkJ/B4cCgCtAgAAAA==.Kynreessa:BAAALgADCgYJCAAAAA==.Kyyell:BAAALgAECgcJCQAAAA==.Kyønshi:BAAALgADCgUJBgAAAA==.',
['Kì']='Kìrito:BAAALgAECgcJDgAAAA==.',
La='Labeya:BAAALgADCgMJAwAAAA==.Lafty:BAAALgAFFAEJAgAAAA==.Laftydh:BAAALgAECgYJEgABLgAFFAEJAgADAAAAAA==.Lailah:BAAALgADCgIJAgABLgAECgkJSgANAEcdAA==.Laine:BAAALgADCgMJAwAAAA==.Landrra:BAAALgAECgQJBAAAAA==.Larac:BAAALgAECgkJEwAAAA==.Lathsong:BAAALgADCgYJDwAAAA==.Lavi:BAAALgADCgQJAwAAAA==.',
Le='Leadge:BAAALgADCgYJBwAAAA==.Lenik:BAABLgAECn8aAAIXAAYJ+gkGOADxAAAXAAYJ+gkGOADxAAAAAA==.Leskya:BAAALgADCgQJAwAAAA==.',
Li='Libras:BAAALgADCgMJAwAAAA==.Licorice:BAAALgAECgUJDgABLgAECgkJKAAMAJYbAA==.Lieree:BAABLgAECn8XAAIFAAgJUg3VggByAQAFAAgJUg3VggByAQAAAA==.Lifeguàrd:BAAALgAECgkJBwAAAA==.Lillana:BAAALgADCgcJDQAAAA==.Lilrayne:BAAALgADCgYJBgABLgAECgkJHAAHAIoPAA==.Lilyfaye:BAAALgADCgkJDAAAAA==.Limosfire:BAABLgAECn8VAAIQAAYJkAO7JACOAAAQAAYJkAO7JACOAAAAAA==.Linsatha:BAAALgAECggJEAAAAA==.',
Lo='Loa:BAAALgAECgEJAwAAAA==.Lockty:BAAALgAECgIJBgABLgAFFAEJAgADAAAAAA==.Logi:BAAALgADCgYJCwAAAA==.Lorezever:BAAALgADCgcJDQAAAA==.Lotion:BAAALgADCgIJAgAAAA==.',
Lu='Luar:BAAALgAECgYJDQAAAA==.Lulubean:BAAALgADCgMJBAAAAA==.Lunaris:BAAALgADCgQJBAAAAA==.Lungorthin:BAAALgAECgQJBAAAAA==.Lunà:BAABLgAECn8iAAIBAAgJ2AUDAwDAAAABAAgJ2AUDAwDAAAAAAA==.',
Ly='Lythalle:BAAALgAECgEJAQAAAA==.Lythwynn:BAABLgAECn8rAAINAAkJhQ+0cwCGAQANAAkJhQ+0cwCGAQAAAA==.',
['Lá']='Lásh:BAAALgAECgUJCAABLgAECgYJIgAOAPIRAA==.',
Ma='Mace:BAAALgAECgEJAQAAAA==.Madison:BAAALgAECgEJAQAAAA==.Madyorkies:BAAALgAECgkJAQAAAA==.Magdolyn:BAAALgADCgMJAwAAAA==.Mageyboi:BAAALgAECgQJBgABLgAFFAMJCgAXAO8dAA==.Magickul:BAAALgAECgYJDAAAAA==.Magleon:BAAALgADCgIJAgAAAA==.Magonk:BAAALgADCgEJAQAAAA==.Mahano:BAABLgAECn8XAAICAAgJ1BoPHwBsAgACAAgJ1BoPHwBsAgABLgAECgcJGgAjABMXAA==.Makis:BAAALgAECgMJBQAAAA==.Malachi:BAAALgAECgYJBwAAAA==.Manavoid:BAABLgAECn8cAAISAAYJkArjpwDVAAASAAYJkArjpwDVAAAAAA==.Mandragore:BAAALgAECgIJBAAAAA==.Massili:BAAALgADCgkJGgAAAA==.Mastor:BAAALgADCgQJBwAAAA==.Maynard:BAABLgAECn8hAAIJAAkJ9xErLwC/AQAJAAkJ9xErLwC/AQAAAA==.',
Mc='Mcdouble:BAAALgADCgMJAwAAAA==.',
Me='Meldanis:BAAALgAECgQJBAAAAA==.Meri:BAABLgAECn8cAAIPAAgJlxwrJgAfAgAPAAgJlxwrJgAfAgAAAA==.',
Mi='Miande:BAABLgAECn8VAAIlAAcJ0xfLCgCyAQAlAAcJ0xfLCgCyAQAAAA==.Microburst:BAAALgAECgUJBwAAAA==.Minecraft:BAAALgAECgIJAgAAAA==.Minilock:BAABLgAECn8xAAMbAAkJ1xDvBgD3AAAbAAkJ1xDvBgD3AAABAAUJTg6vHgC0AAAAAA==.Misogynixy:BAAALgADCgQJBAAAAA==.Missdeeds:BAAALgAECgUJBQAAAA==.Missleading:BAAALgAECgYJCQAAAA==.Missused:BAAALgAECgYJEgAAAA==.Mithos:BAAALgAECgUJBwAAAA==.Mithraxa:BAAALgAECgQJBAAAAA==.Miyagifu:BAAALgAECgQJBAAAAA==.',
Mo='Moash:BAAALgADCgkJCQAAAA==.Modsagoodtnk:BAABLgAECn8bAAIRAAcJRQ5JAwDQAAARAAcJRQ5JAwDQAAABLgAECggJLAACAH8ZAA==.Mongermook:BAABLgAECn8iAAMOAAkJ0QvvBQCiAAAOAAkJ0QvvBQCiAAAVAAEJxgFpkQAVAAAAAA==.Monnkysham:BAAALgAECgQJBgABLgAECgYJCQADAAAAAA==.Moogledragon:BAAALgADCgMJAwAAAA==.Mooglefur:BAAALgAECgQJBQAAAA==.Moonbloom:BAABLgAECn8cAAIPAAgJQhxLHwBMAgAPAAgJQhxLHwBMAgAAAA==.Morgrim:BAAALgAECgEJAQAAAA==.Morlosh:BAAALgAECgMJAwAAAA==.Moryna:BAABLgAECn80AAIdAAkJsQhZJQA9AQAdAAkJsQhZJQA9AQAAAA==.',
Mt='Mthrandir:BAAALgADCgUJBQAAAA==.',
Mu='Muford:BAAALgAECgQJBQABLgAFFAgJFQAKAOQfAA==.Mull:BAAALgAECgYJEwAAAA==.Muloc:BAAALgADCgEJAQAAAA==.',
My='Myaka:BAAALgAECgYJBgAAAA==.Mythicc:BAAALgADCgUJCQAAAA==.',
Na='Naatixa:BAAALgAECggJDAAAAA==.Nacronor:BAAALgAECgUJEAAAAA==.Naiika:BAAALgAECgYJBwAAAA==.Nascha:BAAALgADCgEJAQAAAA==.Nasoj:BAAALgAECgYJCQABLgAECgYJEwADAAAAAA==.',
Ne='Necrotic:BAAALgAECgQJBAAAAA==.Nedalla:BAAALgAECgYJCwAAAA==.Neeve:BAAALgAECgMJAwAAAA==.Nekrotik:BAAALgADCgcJBgAAAA==.Neobahamut:BAAALgADCgEJAQABLgAECgcJDgADAAAAAA==.Netharel:BAAALgADCgIJAgAAAA==.Newports:BAAALgAECgEJAQAAAA==.',
Ni='Nichôlasmage:BAAALgAECgYJCwAAAA==.Nickatnite:BAAALgAFFAEJAQAAAA==.Nickelodeon:BAAALgAFFAIJAwAAAA==.Nicksaban:BAABLgAECn8mAAINAAkJOBuBLgBHAgANAAkJOBuBLgBHAgAAAA==.Nightgear:BAACLgAFFH8wAAMCAAgJaBcADwDuAQACAAcJehkADwDuAQAQAAIJ/ApJNQBJAAAuAAQKf1kAAwIACQm1IgUIABADAAIACQm1IgUIABADABAABAnfEoAjAJcAAAAA.Nightshades:BAAALgADCgQJBAAAAA==.Nilux:BAAALgAECgYJDwAAAA==.Ninetails:BAAALgAECgUJCgAAAA==.Niteshadeth:BAAALgAECgQJBQAAAA==.Niteyknight:BAAALgAECgQJBAAAAA==.Nixeava:BAABLgAECn8bAAIkAAgJ+wR6VADoAAAkAAgJ+wR6VADoAAAAAA==.',
No='Nogooddruid:BAAALgAECgUJDgAAAA==.Nopetsneeded:BAABLgAECn89AAIQAAkJzBRpCAD3AQAQAAkJzBRpCAD3AQAAAA==.Norepairbill:BAAALgAECgEJAQABLgAECgkJPQAQAMwUAA==.Nostariel:BAAALgAECgQJCgAAAA==.Notadoctor:BAAALgAECgYJCAAAAA==.Noteworthy:BAAALgAECgYJEgABLgAFFAYJDwAGAN0dAA==.',
Ny='Nysong:BAABLgAECn83AAMBAAgJPAu/EgAfAQABAAgJPAu/EgAfAQAbAAMJYwKJGAFPAAAAAA==.',
['Nó']='Nórin:BAAALgAECgUJBQAAAA==.',
Ob='Obali:BAAALgADCgYJCgAAAA==.',
Od='Oddangel:BAAALgAECgYJEwAAAA==.Ode:BAAALgAECgkJDgAAAA==.Odex:BAABLgAECn8qAAMhAAkJbw1/CACoAQAhAAkJbw1/CACoAQAgAAEJpghNkAA6AAAAAA==.',
Oh='Ohblergen:BAAALgAECgIJAgAAAA==.',
Ok='Okragren:BAABLgAECn82AAIkAAkJcw1NMwBvAQAkAAkJcw1NMwBvAQAAAA==.',
Ol='Olehi:BAAALgADCgcJBwAAAA==.Olynder:BAAALgAECgIJBAAAAA==.',
On='Onos:BAABLgAECn8bAAICAAcJIyQ4IABEAgACAAcJIyQ4IABEAgAAAA==.Onto:BAAALgADCgEJAQAAAA==.Ontoquas:BAAALgADCgkJCgAAAA==.',
Or='Orinin:BAAALgAECgUJBQABLgAECgQJCQADAAAAAA==.',
Pa='Paleclaw:BAAALgADCgQJBAAAAA==.Palitroque:BAAALgAECgQJBAAAAA==.Pally:BAAALgAECgUJBQAAAA==.Papasmurfz:BAAALgAECgEJAwAAAA==.Paramedic:BAAALgAECgUJDwAAAA==.Pathogen:BAABLgAECn8hAAIGAAkJDR/oOwARAgAGAAkJDR/oOwARAgAAAA==.',
Pe='Penryn:BAAALgAECgQJBgAAAA==.Pepster:BAABLgAECn8XAAInAAkJpQHgLgCAAAAnAAkJpQHgLgCAAAAAAA==.Persephoknee:BAAALgADCgEJAQAAAA==.Persephoni:BAAALgADCgcJBwAAAA==.',
Pf='Pfchen:BAAALgAECgIJAwAAAA==.',
Pl='Plaguestrip:BAAALgAECgEJAgAAAA==.Plinkerbell:BAAALgAECgMJAwAAAA==.Plumprnickel:BAAALgAECgEJAQAAAA==.Plxkingg:BAAALgADCgUJBQAAAA==.',
Po='Poppit:BAAALgAECgQJBQAAAA==.Porimma:BAAALgAECgYJDwAAAA==.Pormas:BAAALgAECgYJDwAAAA==.Poseydon:BAAALgADCgQJBAABLgAECgEJAQADAAAAAA==.',
Pr='Prayerz:BAAALgADCgMJAwAAAA==.Proctology:BAAALgAECgQJBAAAAA==.Prom:BAAALgAECgcJDgAAAA==.Promethèus:BAAALgAECgQJBAAAAA==.Prosby:BAAALgADCgIJAgAAAA==.Prowlnfool:BAAALgADCgUJBQAAAA==.Pryto:BAAALgADCgkJDgABLgAFFAIJAwADAAAAAA==.',
Qu='Queedle:BAABLgAECn8iAAIZAAkJEw6zAAAIAQAZAAkJEw6zAAAIAQAAAA==.',
Ra='Raennis:BAAALgAECgIJAgAAAA==.Ragalstan:BAAALgAECgEJAgAAAA==.Rahanumn:BAABLgAECn8YAAINAAgJ6wktpAAxAQANAAgJ6wktpAAxAQAAAA==.Rainlette:BAAALgAECgcJDwAAAA==.Rainsvoker:BAACLgAFFH8jAAIiAAYJXQ2aEgBqAQAiAAYJXQ2aEgBqAQAuAAQKf1IAAyIACQkOHL4GAJUCACIACQkOHL4GAJUCACAABgk7CAxeAMAAAAAA.Ramike:BAAALgAECggJCQAAAA==.Raqtar:BAAALgAECgIJAgABLgAECgkJEgADAAAAAA==.Ratrazarke:BAAALgADCgIJAgAAAA==.Razihel:BAAALgADCgYJCQAAAA==.',
Re='Reaver:BAAALgAECgQJBAAAAA==.Reddan:BAABLgAECn8qAAINAAgJlgzSmwA+AQANAAgJlgzSmwA+AQAAAA==.Renata:BAAALgAFFAIJAgAAAA==.Replicant:BAAALgAECgEJAQAAAA==.Retman:BAAALgAECgMJAQAAAA==.Reverìe:BAAALgAECgcJBwAAAA==.Reylinn:BAAALgAECgQJBAAAAA==.Reyra:BAAALgAECgEJAQABLgAFFAIJAgADAAAAAA==.Reï:BAABLgAECn8gAAIPAAkJchTZJAAlAgAPAAkJchTZJAAlAgAAAA==.',
Ri='Ridlei:BAAALgAECgMJBAAAAA==.Rimchester:BAAALgAECgIJAQAAAA==.Rinji:BAAALgAECgEJAQAAAA==.Ritzon:BAABLgAECn89AAMeAAkJJSRhBgD4AgAeAAkJJSRhBgD4AgAdAAEJmBdmcQA+AAAAAA==.',
Ro='Rosadita:BAAALgAECgQJBQAAAA==.Roxydan:BAABLgAECn8dAAMBAAgJiQ03KQAdAQAbAAgJiQ1KZwCWAQABAAYJ8Ag3KQAdAQAAAA==.',
Ru='Runastalis:BAAALgADCgYJBgAAAA==.',
Ry='Rykken:BAAALgAECgEJAQAAAA==.Ryko:BAABLgAECn8fAAInAAcJqBSRFwBOAQAnAAcJqBSRFwBOAQAAAA==.',
['Rë']='Rëyra:BAAALgAFFAIJAgAAAA==.',
Sa='Salene:BAAALgAFFAEJAQAAAA==.Sanandume:BAAALgADCgEJAQAAAA==.Sanctess:BAAALgAECggJDgAAAA==.Sankai:BAAALgAECgEJAQABLgAECgYJDgADAAAAAA==.Saraelle:BAAALgAECgEJAQAAAA==.Sarlas:BAAALgADCgQJBAAAAA==.Sarumanpally:BAAALgAECgYJBwAAAA==.Sayomi:BAAALgADCgcJEwAAAA==.',
Se='Secretjuicy:BAAALgAECgYJCQAAAA==.Senseijundra:BAAALgAECgQJCAAAAA==.Sentinaal:BAAALgADCgcJBwAAAA==.',
Sh='Shabadu:BAAALgADCgQJBAAAAA==.Shadyandi:BAAALgADCgcJCAAAAA==.Shamanhack:BAAALgAFFAIJAwAAAA==.Shan:BAAALgADCgYJBgAAAA==.Sharazad:BAAALgAECggJCQAAAA==.Sheda:BAAALgAECgQJBAAAAA==.Shedia:BAAALgAECgEJAQAAAA==.Shmoove:BAEALgAECgUJBgAAAA==.Shmooves:BAEALgAECgQJBAABLgAECgUJBgADAAAAAA==.Shoukei:BAAALgADCgIJAwAAAA==.',
Si='Sianna:BAAALgADCgYJBgAAAA==.Siinful:BAAALgAECgEJAQAAAA==.Simbruh:BAAALgADCgMJAwAAAA==.Simpari:BAAALgAFFAIJAwABLgAFFAUJFQAFAJ4OAA==.Sinarria:BAAALgAECgEJAQAAAA==.Sithra:BAAALgADCgEJAQAAAA==.',
Sk='Skeemer:BAAALgAECgUJBQAAAA==.Skeetro:BAAALgAECgEJAQAAAA==.Skips:BAAALgAECgQJCQAAAA==.Skullace:BAABLgAECn8qAAIBAAkJuw9GCgChAQABAAkJuw9GCgChAQAAAA==.Skullhead:BAAALgADCgEJAQAAAA==.Skybreaker:BAAALgAECgkJCAAAAA==.Skylette:BAAALgAECgEJAQAAAA==.',
Sm='Smashurfacen:BAAALgADCgcJFAAAAA==.',
Sn='Snitbit:BAAALgADCgkJGgAAAA==.Sno:BAAALgADCgEJAQABLgAECgUJBwADAAAAAA==.Snoopingas:BAAALgAECgEJAQAAAA==.Snpcrklpopu:BAAALgADCgYJCAAAAA==.',
So='Solarana:BAAALgAECgkJCQAAAA==.Sortiebatoru:BAAALgAECgIJAwAAAA==.Sotzi:BAAALgADCggJEQAAAA==.Souldune:BAAALgAECgYJBgAAAA==.',
Sp='Sparkplugg:BAAALgAECgEJAQAAAA==.',
Sr='Srfreaky:BAAALgAECgUJEAAAAA==.',
St='Sterlìng:BAAALgAECgUJCQAAAA==.Stevejabbs:BAABLgAECn8iAAMJAAYJgSRUAQAoAgAJAAYJgSRUAQAoAgAKAAMJ5SAEOQAYAQAAAA==.Stormcunning:BAABLgAECn8WAAIkAAYJCAxiTAAWAQAkAAYJCAxiTAAWAQAAAA==.Stormfire:BAAALgADCgcJBwAAAA==.Stormßringer:BAABLgAECn8UAAIkAAgJERDXMwCJAQAkAAgJERDXMwCJAQAAAA==.Stownr:BAAALgAECgYJBgAAAA==.Strip:BAAALgADCgUJCAAAAA==.Strongclaw:BAAALgADCgUJBQAAAA==.Stumpyborg:BAABLgAECn8VAAQBAAcJaAY9MgBVAAAbAAYJNgSn3gCdAAABAAIJMws9MgBVAAAlAAEJhAcZQwArAAABLgAECgkJFwAHAN0LAA==.Stónéhëárt:BAAALgADCgYJBwABLgAECgkJEQADAAAAAA==.',
Su='Subdue:BAAALgADCgQJBAAAAA==.Subverse:BAAALgAECgQJBAAAAA==.Sundance:BAAALgAECgcJDgAAAA==.Sune:BAABLgAECn8gAAMMAAYJxgvZRwDwAAAMAAYJxgvZRwDwAAAfAAEJNwk2ggAqAAAAAA==.Supplicant:BAAALgADCgQJBwAAAA==.',
Sv='Svellulfr:BAAALgAECgEJAQAAAA==.Svuca:BAAALgADCgcJBwAAAA==.',
Sy='Sydneyweenie:BAAALgADCgcJCAAAAA==.Syldi:BAAALgAECgEJAQABLgAECgYJHAAUAPYbAA==.Sythis:BAAALgAECgIJAwAAAA==.',
['Sä']='Sästa:BAAALgADCgkJCQAAAA==.',
['Sö']='Sörren:BAABLgAECn8kAAIlAAYJqgZUAwCnAAAlAAYJqgZUAwCnAAAAAA==.',
Ta='Tacosdeasada:BAAALgAECgEJAQAAAA==.Taitertot:BAAALgADCgQJBQAAAA==.Tanelórn:BAAALgAECgQJBQAAAA==.Tanlon:BAAALgAECggJEgAAAA==.Taykorra:BAAALgADCggJDQAAAA==.',
Te='Telandril:BAABLgAECn8vAAIPAAkJvxH4MwDNAQAPAAkJvxH4MwDNAQAAAA==.Telphin:BAAALgAECgYJDAAAAA==.Tempestira:BAAALgAECgEJAgAAAA==.Tensuken:BAABLgAECn8ZAAINAAYJpBidsAAeAQANAAYJpBidsAAeAQAAAA==.Teylonna:BAAALgAECgEJAQAAAA==.',
Th='Thadgun:BAAALgADCgkJFQAAAA==.Thadium:BAAALgAECgMJAwAAAA==.Thalgan:BAAALgAECgEJAQAAAA==.Thalyn:BAAALgAECgEJAQAAAA==.Thecword:BAAALgADCgYJBgAAAA==.Themedic:BAABLgAECn8cAAMWAAcJyBRzCADfAAAWAAcJyBRzCADfAAAkAAEJ6gFuxAAXAAAAAA==.Theremar:BAAALgAECgMJAwAAAA==.Thergothon:BAAALgAECgEJAQABLgAECgMJAwADAAAAAA==.Thisisdrexx:BAAALgAECgIJAwAAAA==.Thorwrath:BAAALgADCgEJAgAAAA==.Thrazoro:BAAALgAECgQJBAAAAA==.Thrazzoro:BAAALgAECgYJEwAAAA==.Thrægg:BAAALgAECgUJBQABLgAECgYJIgAJAIEkAA==.',
Ti='Tiarl:BAABLgAECn81AAIUAAkJHRehEQBUAgAUAAkJHRehEQBUAgAAAA==.Tiia:BAAALgADCgIJAgAAAA==.Timex:BAABLgAECn8XAAMhAAYJRCD5DgDrAQAhAAYJRCD5DgDrAQAgAAEJUhdnjgA+AAAAAA==.Tinydots:BAAALgAECgEJAQAAAA==.Tinysitril:BAAALgAECgYJCQABLgAFFAQJCgAYAJ0NAA==.Tinysohei:BAAALgAECgMJAwAAAA==.Tisiphonee:BAAALgADCgEJAQAAAA==.Titañick:BAAALgAECgEJAwAAAA==.',
To='Tom:BAABLgAECn8aAAMgAAYJLgvvVgDWAAAgAAYJLgvvVgDWAAAhAAEJZQhLJwAvAAAAAA==.Toosxyfohair:BAABLgAECn8dAAIWAAgJ9xVpLwD4AQAWAAgJ9xVpLwD4AQAAAA==.',
Tr='Trainwrekk:BAAALgADCgYJBgAAAA==.Tranqar:BAAALgAECgQJBgAAAA==.Tresg:BAAALgAECgYJCQAAAA==.Trissandra:BAAALgAECgEJAQAAAA==.Trolltoll:BAAALgADCgEJAwAAAA==.Trüth:BAAALgADCggJEAAAAA==.',
Tw='Twentytwo:BAAALgAECgEJAQAAAA==.Twylidan:BAEALgAECgkJCgABLgAFFAQJDAAgAOkeAA==.',
Ty='Tyrannt:BAAALgAECgEJAQAAAA==.Tyrannus:BAAALgADCgYJBgAAAA==.Tyregar:BAAALgAECgEJAQAAAA==.Tyrànda:BAAALgAECgQJBgAAAA==.Tyzy:BAAALgAECgEJAgAAAA==.',
['Tö']='Tötém:BAAALgAECgEJAQAAAA==.',
Ul='Ulanhi:BAABLgAECn8VAAIcAAUJzh31EACdAQAcAAUJzh31EACdAQAAAA==.',
Un='Undeadjelly:BAAALgAECgYJEwAAAA==.Unholy:BAAALgAECgYJDwAAAA==.',
Ur='Urkzul:BAAALgADCgMJAwAAAA==.Ursoth:BAAALgADCgUJCgAAAA==.',
Ut='Uthèrsmight:BAAALgAECgYJBgAAAA==.Uti:BAAALgADCgUJBQAAAA==.',
Uu='Uubs:BAAALgADCgEJAQABLgAFFAMJCgANAJoSAA==.',
Va='Valakk:BAAALgAECgIJBQAAAA==.Vallak:BAAALgADCgIJBAAAAA==.Valsitril:BAAALgAECgYJEAABLgAFFAQJCgAYAJ0NAA==.Valthaczar:BAAALgAECgMJBgAAAA==.Vanara:BAAALgAECgEJAgAAAA==.Varadun:BAAALgAFFAIJAwAAAA==.Varrosh:BAAALgADCgYJBgAAAA==.Vathan:BAAALgAECgQJBQAAAA==.',
Ve='Velmora:BAAALgAECgkJCQAAAA==.Velsetin:BAABLgAECn8dAAIFAAcJTBsyTABSAgAFAAcJTBsyTABSAgABLgAFFAMJBQAVAMcUAA==.Verathina:BAAALgADCgEJAgAAAA==.Versed:BAAALgADCgUJBQABLgAECgQJBAADAAAAAA==.Veryspooky:BAABLgAECn8aAAIbAAgJNhkHOAD5AQAbAAgJNhkHOAD5AQAAAA==.Vexian:BAABLgAECn8aAAMkAAkJBxwbDwB+AgAkAAkJBxwbDwB+AgAWAAEJ3B/FtwBcAAAAAA==.',
Vf='Vfl:BAAALgADCgcJBwAAAA==.',
Vi='Vicas:BAAALgAECgcJEgAAAA==.',
Vl='Vladdek:BAAALgAFFAEJAgAAAA==.Vladdok:BAAALgAECgUJBQAAAA==.Vladok:BAAALgAECgQJCwAAAA==.Vladokk:BAAALgAECgMJAwAAAA==.',
Vo='Voidofdeath:BAAALgADCgQJBAAAAA==.Voidshiekah:BAAALgADCgEJAQAAAA==.Vorteia:BAAALgADCgYJBgAAAA==.',
['Vé']='Véngéánçé:BAAALgAECgMJBAAAAA==.',
Wa='Wald:BAAALgAECgYJEAAAAA==.Warmongerr:BAAALgADCgIJAgAAAA==.Waruh:BAAALgADCgcJCQAAAA==.',
We='Webgar:BAAALgAECgEJAQAAAA==.Webrune:BAAALgAECgMJAwAAAA==.',
Wh='Whisperlia:BAAALgAECgQJBgAAAA==.Whisperwindd:BAAALgAECgYJBAAAAA==.White:BAAALgAFFAMJBAAAAA==.Whitetoothe:BAABLgAECn8xAAICAAcJxRadVgCgAQACAAcJxRadVgCgAQAAAA==.',
Wi='Witemandown:BAAALgADCgcJCAAAAA==.Witherbear:BAAALgADCgcJBwAAAA==.Witherhoard:BAAALgADCgEJAQAAAA==.Wizzy:BAAALgADCgEJAQAAAA==.',
Wo='Workin:BAAALgADCgEJAQABLgAECgcJHQAPAIAYAA==.',
['Wå']='Wånheda:BAAALgAECggJEwAAAA==.',
Xa='Xaniana:BAAALgAECgkJDwAAAA==.Xaosin:BAAALgADCgUJBQAAAA==.',
Xe='Xenzak:BAAALgAECgEJAQAAAA==.Xephir:BAAALgADCgMJAwAAAA==.Xerxës:BAAALgAECgEJAQAAAA==.',
Xl='Xl:BAAALgAECgQJCwAAAA==.',
Xo='Xoito:BAAALgAECgEJAQABLgAECgcJBQADAAAAAA==.Xotiko:BAAALgAECgYJDAAAAA==.',
Xu='Xubris:BAAALgADCgYJCQAAAA==.',
['Xâ']='Xâxâs:BAAALgAECgMJAwABLgAECggJGwAgAHQFAA==.',
Ya='Yaerin:BAACLgAFFH8ZAAIfAAQJcCMSGwCLAQAfAAQJcCMSGwCLAQAuAAQKfyQAAh8ACQkAIvMDAFsDAB8ACQkAIvMDAFsDAAAA.',
Yu='Yunarä:BAAALgAECgYJCAAAAA==.Yuukon:BAABLgAECn8bAAQTAAgJtxfwHABxAQATAAgJtxfwHABxAQAGAAQJ5gOZOQFkAAAIAAEJDwgrGAAvAAAAAA==.',
Za='Zakuul:BAAALgADCgQJBAAAAA==.Zalezaar:BAAALgAECgIJAgAAAA==.Zangetsu:BAAALgAECgcJBwAAAA==.Zarusthra:BAAALgADCgMJAwAAAA==.Zaxie:BAABLgAECn8/AAISAAkJvh32AABiAgASAAkJvh32AABiAgAAAA==.',
Ze='Zenwu:BAAALgADCgkJGwAAAA==.Zephrylia:BAAALgAECgQJBQAAAA==.Zerama:BAAALgAECgUJBQAAAA==.',
Zh='Zheratul:BAAALgAECgEJAQAAAA==.Zhirl:BAAALgAECgkJCQAAAA==.Zhivet:BAAALgAECgYJBwAAAA==.',
Zi='Zilphia:BAAALgAECggJEwAAAA==.',
Zu='Zuriel:BAAALgAECgIJAgAAAA==.',
Zy='Zyku:BAAALgAECgEJAQAAAA==.Zylphie:BAAALgADCgcJBwAAAA==.',
['Àm']='Àmagezing:BAAALgAFFAIJAgABLgAFFAUJGgANAGgjAA==.',
['Åj']='Åj:BAAALgADCgcJBwAAAA==.',
['Åp']='Åpexx:BAABLgAECn8cAAMSAAYJKAalDgCRAAASAAYJCAalDgCRAAAYAAEJzAYcfQAjAAAAAA==.',
['Çw']='Çwÿbàbý:BAAALgAECgYJCgAAAA==.',
['Ór']='Órión:BAABLgAECn8VAAICAAYJ1BLuoQD+AAACAAYJ1BLuoQD+AAAAAA==.',
['Ös']='Östara:BAABLgAECn8dAAIPAAcJgBhHLQDyAQAPAAcJgBhHLQDyAQAAAA==.',
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
