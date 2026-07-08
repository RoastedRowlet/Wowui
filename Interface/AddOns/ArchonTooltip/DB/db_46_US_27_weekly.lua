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

local lookup = {'Warlock-Destruction','Hunter-BeastMastery','Unknown-Unknown','Mage-Arcane','Mage-Frost','DeathKnight-Unholy','Hunter-Survival','DeathKnight-Frost','Monk-Mistweaver','Monk-Brewmaster','Monk-Windwalker','Priest-Shadow','Paladin-Retribution','Druid-Guardian','Druid-Restoration','Hunter-Marksmanship','Paladin-Protection','DemonHunter-Devourer','DeathKnight-Blood','Priest-Holy','Druid-Balance','Shaman-Restoration','Rogue-Subtlety','DemonHunter-Havoc','Rogue-Outlaw','Rogue-Assassination','Warlock-Demonology','Warrior-Protection','Druid-Feral','Warrior-Arms','Warrior-Fury','Priest-Discipline','DemonHunter-Vengeance','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Shaman-Elemental','Warlock-Affliction','Paladin-Holy','Shaman-Enhancement',}
local provider = {region='US',realm='Azuremyst',name='US',type='weekly',zone=46,date='2026-07-05',data={Aa='Aaravos:BAABLgAECn8dAAIBAAkJiBfRBwDUAQABAAkJiBfRBwDUAQAAAA==.Aardia:BAAALgAECgIJAgAAAA==.',
Ab='Abysseon:BAAALgAECgUJDgAAAA==.',
Ac='Accretion:BAAALgAECgYJBgAAAA==.',
Ad='Adaria:BAABLgAECn8WAAICAAcJWAWSZQA3AQACAAcJWAWSZQA3AQAAAA==.Adrillbear:BAAALgAECgIJAgABLgAECgYJEwADAAAAAA==.Adura:BAAALgAECgYJCAAAAA==.',
Ae='Aeirith:BAACLgAFFH8OAAIEAAQJ5hRoAQAjAQAEAAQJ5hRoAQAjAQAuAAQKfyQAAwQACQmwHegBAGYCAAQACQmwHegBAGYCAAUAAQlFChlgATEAAAAA.Aelion:BAAALgAECgEJAQAAAA==.',
Ah='Ahheevoker:BAAALgAECgYJEgAAAA==.',
Ai='Ailsà:BAAALgADCgEJAQAAAA==.',
Ak='Akarias:BAAALgAECgEJAQABLgAECgcJBwADAAAAAA==.',
Al='Aladaria:BAAALgAECgMJAwAAAA==.Aldyah:BAAALgAFFAMJAwAAAA==.Alias:BAAALgAECgYJBQAAAA==.Alistair:BAAALgAECgEJAwAAAA==.Allanonn:BAAALgAECgQJBAAAAA==.Alohomora:BAAALgAECgUJEAAAAA==.Alprazolam:BAAALgAECgEJAQAAAA==.Alvist:BAABLgAECn8UAAIGAAQJrx6gggBeAQAGAAQJrx6gggBeAQAAAA==.',
Am='Amarasu:BAABLgAECn8cAAIHAAkJig+RGwDBAQAHAAkJig+RGwDBAQAAAA==.Amarlly:BAABLgAECn8zAAIIAAkJJhngBwAVAgAIAAkJJhngBwAVAgAAAA==.Amenedil:BAAALgAECgUJDAAAAA==.',
An='Anbrew:BAABLgAECn8UAAQJAAcJdxJoSwA/AQAJAAYJDBJoSwA/AQAKAAUJjA6FQAD4AAALAAEJMwe0rwAlAAABLgAFFAYJDwAGAN0dAA==.Ancelina:BAABLgAECn8qAAIMAAkJeyR3AgBCAwAMAAkJeyR3AgBCAwAAAA==.Anderton:BAABLgAECn86AAINAAgJhRnQSwDjAQANAAgJhRnQSwDjAQAAAA==.Andilocks:BAAALgADCgMJAwAAAA==.Andrela:BAAALgAECgYJCgAAAA==.Aneira:BAABLgAECn8kAAMOAAcJqBArBAAlAQAOAAcJqBArBAAlAQAPAAMJYQySmQB/AAAAAA==.Annovera:BAAALgAECgMJBgAAAA==.Anuubis:BAAALgADCgYJBgAAAA==.Anyi:BAAALgAECgEJAQAAAA==.',
Ap='Apexxd:BAAALgAECgUJBQAAAA==.Applefritter:BAAALgAECgUJCAABLgAECgkJKAAMAJYbAA==.',
Ar='Araga:BAAALgAECgEJAQAAAA==.Archérhiro:BAACLgAFFH8nAAMCAAgJkRXHCAAyAgACAAcJUxjHCAAyAgAQAAMJRwTfIQCHAAAuAAQKfyoAAwIACQmGH+0YAJECAAIACQl6H+0YAJECABAACAkrGdobAEoCAAAA.Arilias:BAAALgAECgEJAQABLgAECgkJQwACANEfAA==.Arillann:BAABLgAECn89AAIRAAkJUR+3BACuAgARAAkJUR+3BACuAgAAAA==.Arrook:BAAALgAECgMJAwAAAA==.Arrtonomis:BAAALgAECgUJCAABLgAECgkJEgADAAAAAA==.Artdemsamis:BAAALgAECgkJEgAAAA==.Arte:BAABLgAECn89AAICAAkJaxOnLAABAgACAAkJaxOnLAABAgAAAA==.Arthundermis:BAAALgAECgkJEQABLgAECgkJEgADAAAAAA==.Artlunarmis:BAAALgADCgEJAQABLgAECgkJEgADAAAAAA==.Arvena:BAABLgAECn8nAAISAAkJVgoWdAA5AQASAAkJVgoWdAA5AQAAAA==.',
As='Asclëpius:BAAALgADCgcJBgABLgAECgEJAQADAAAAAA==.Asheron:BAAALgAECgYJCAAAAA==.Ashylock:BAAALgAECgEJAQABLgAFFAUJDgAFAGAWAA==.Ashymage:BAACLgAFFH8OAAIFAAUJYBabYAAgAQAFAAUJYBabYAAgAQAuAAQKfzcAAgUACQlYHLYpAMwCAAUACQlYHLYpAMwCAAAA.Askevar:BAABLgAECn8uAAMGAAkJTwzxBgBsAQAGAAkJnwvxBgBsAQATAAYJ5wlHJwAEAQAAAA==.Aspect:BAAALgADCgEJAQABLgAFFAIJAwADAAAAAA==.Asriél:BAAALgAECgYJDQAAAA==.Astor:BAAALgADCgMJBQAAAA==.Astrona:BAAALgADCgkJFwAAAA==.',
At='Atreus:BAABLgAECn8YAAINAAkJbAXUwQAGAQANAAkJbAXUwQAGAQAAAA==.Attalaguy:BAAALgAECgYJDgAAAA==.',
Au='Audra:BAAALgADCgcJDgAAAA==.',
Av='Avabeatrix:BAAALgADCgEJAQAAAA==.Avinthoro:BAAALgADCgIJAgAAAA==.',
Ay='Ayyayyron:BAAALgAECgUJCQAAAA==.',
Az='Azaleah:BAABLgAECn9LAAINAAkJRx3xGQCoAgANAAkJRx3xGQCoAgAAAA==.Azanoth:BAAALgADCgIJAgAAAA==.Azraesha:BAABLgAECn8rAAISAAkJ/BUDKgAhAgASAAkJ/BUDKgAhAgAAAA==.Azureflamez:BAAALgAECgEJAQAAAA==.Azurewraith:BAAALgAECgQJBAAAAA==.Azzul:BAAALgADCgcJBwAAAA==.',
Ba='Backy:BAAALgAECgcJBwAAAA==.Baiken:BAAALgAECgIJAgABLgAECgQJCAADAAAAAA==.Banjoman:BAABLgAECn8kAAIUAAcJXSTpCgC4AgAUAAcJXSTpCgC4AgAAAA==.Baza:BAAALgADCgYJBgAAAA==.Baýlei:BAABLgAECn8WAAIJAAYJ5A0kWwAHAQAJAAYJ5A0kWwAHAQAAAA==.',
Be='Beareold:BAAALgAECgMJAwAAAA==.Beary:BAAALgAECgQJCAAAAA==.Beenaughty:BAAALgAECgEJAQABLgAECgEJAQADAAAAAA==.Belaanna:BAAALgADCgYJCQAAAA==.Beliria:BAAALgADCgUJBgAAAA==.Benimaru:BAAALgAECgUJDwAAAA==.Beriko:BAAALgAECgMJAwAAAA==.Bernat:BAAALgAECgEJAQAAAA==.Beàrdfáce:BAAALgADCgQJBAAAAA==.',
Bi='Bigblunt:BAAALgAECgEJAQAAAA==.Bigjuicy:BAAALgAECgkJEQAAAA==.Billie:BAAALgAECgcJCQAAAA==.Bimboficate:BAAALgADCgYJBwAAAA==.',
Bl='Black:BAAALgAFFAEJAQAAAA==.Blackadder:BAABLgAECn8lAAIRAAYJuw5XBADlAAARAAYJuw5XBADlAAAAAA==.Blessthefall:BAAALgAECgcJCwAAAA==.Blondie:BAAALgADCgQJBAABLgAECgYJEwADAAAAAA==.Bloodie:BAAALgAECgMJAwAAAA==.Blue:BAABLgAECn88AAILAAkJxRvlDgBbAgALAAkJxRvlDgBbAgAAAA==.Blueguy:BAAALgAECgQJBgAAAA==.Bluestreak:BAAALgAECgEJAwABLgAECgcJCQADAAAAAA==.',
Bo='Bobthefist:BAAALgADCgcJBwAAAA==.Bode:BAAALgAECgYJEwAAAA==.Bogern:BAAALgADCgcJBwAAAA==.Bolau:BAAALgADCgYJBwAAAA==.Boltz:BAAALgADCgYJBgAAAA==.Boogy:BAAALgAFFAEJAQAAAA==.Bopdiz:BAAALgAECgEJAQABLgAECgQJFAAGAK8eAA==.Borledish:BAAALgAECgMJBAABLgAECgQJFAAGAK8eAA==.Bottosai:BAAALgAECgEJAgAAAA==.',
Br='Brambles:BAAALgAECgEJAQAAAA==.Branwynn:BAAALgAECgYJEQAAAA==.Breezyfight:BAAALgAFFAIJAgAAAA==.Breezyrocks:BAAALgADCgQJCQAAAA==.Breezysha:BAAALgADCgcJCAAAAA==.Brenz:BAABLgAFFH8GAAMNAAMJOQIKqgBuAAANAAMJOwEKqgBuAAARAAEJvQR6HAAhAAAAAA==.Brewdaddy:BAAALgAECgUJEwABLgAECgkJOgARAHwRAA==.Brewdude:BAAALgAECgEJAQAAAA==.Brigor:BAAALgAECgYJEAAAAA==.Brokenblade:BAAALgADCgYJBgAAAA==.Brotherblood:BAAALgAECgUJCwAAAA==.',
Bu='Bulldoza:BAAALgAECgQJBQAAAA==.Bullwinkles:BAAALgAECgEJAQAAAA==.Bunbot:BAAALgAECgEJAQAAAA==.Butterknifeo:BAABLgAFFH8FAAIVAAMJxxSHMQC7AAAVAAMJxxSHMQC7AAAAAA==.',
By='Byryja:BAABLgAECn8kAAIFAAYJIQhtGQCpAAAFAAYJIQhtGQCpAAAAAA==.',
Ca='Cahrazie:BAACLgAFFH8GAAINAAMJ9wkqewDAAAANAAMJ9wkqewDAAAAuAAQKfx0AAg0ACQkaFXcKAEEBAA0ACQkaFXcKAEEBAAAA.Caidinn:BAAALgAECgkJEQAAAA==.Caitrîn:BAAALgADCgkJCQABLgAECgcJJAAOAKgQAA==.Calissancia:BAABLgAECn82AAIJAAgJNBdEHwAgAgAJAAgJNBdEHwAgAgAAAA==.Calkey:BAABLgAECn8WAAIBAAYJUQgMHwCyAAABAAYJUQgMHwCyAAAAAA==.Callmemommy:BAAALgADCgYJBgAAAA==.Carvana:BAAALgAECgkJBwAAAA==.Catalyst:BAAALgADCgMJAwAAAA==.Cathandris:BAAALgADCgEJAQAAAA==.Catovia:BAAALgAECgEJAQAAAA==.',
Ce='Ceri:BAAALgAECgkJBwAAAA==.',
Ch='Chadarack:BAAALgAECgYJBwAAAA==.Chadaracks:BAAALgAECgEJAQAAAA==.Chancy:BAAALgAECgMJBQAAAA==.Channingtotm:BAACLgAFFH8sAAIWAAUJsyW2AwDvAQAWAAUJsyW2AwDvAQAuAAQKfzcAAhYACQlhIY4EAG4DABYACQlhIY4EAG4DAAAA.Chantix:BAAALgADCgUJBQAAAA==.Charlemoo:BAAALgADCgUJBQABLgAECgMJAwADAAAAAA==.Cheekymonkey:BAABLgAECn8qAAIEAAkJMQ2EBQB+AQAEAAkJMQ2EBQB+AQAAAA==.Chrispbacon:BAAALgAECgUJEgAAAA==.Chueyé:BAAALgAECgMJAwABLgAFFAMJCgAXAO8dAA==.Chune:BAAALgAECgcJBwAAAA==.Chunkyy:BAAALgADCgYJBgAAAA==.Churros:BAABLgAECn8oAAMMAAkJlhuVEQBJAgAMAAkJlhuVEQBJAgAUAAcJThV3JwCKAQAAAA==.',
Ci='Cincog:BAAALgAECgQJBAABLgAECgYJCQADAAAAAA==.',
Cl='Closetcookie:BAAALgAECgQJBAAAAA==.',
Co='Coberren:BAAALgAECgEJAQAAAA==.Cordialkylie:BAAALgAECgIJAgAAAA==.Cowcrusader:BAAALgADCgcJBwAAAA==.',
Cr='Crazyugly:BAAALgAECgQJBQAAAA==.Crogrer:BAAALgAECgMJAwAAAA==.Crosslock:BAAALgAECgUJDwAAAA==.',
Cu='Cuppycakes:BAAALgADCgcJFAAAAA==.',
Cy='Cynnari:BAAALgAECgUJCgAAAA==.',
Da='Daddysecret:BAAALgAECgQJBQAAAA==.Dalan:BAAALgAECgIJAgABLgAFFAQJDgAEAOYUAA==.Dalaris:BAACLgAFFH8KAAIYAAQJnQ1aCADeAAAYAAQJnQ1aCADeAAAuAAQKfyIAAhgACQmdFiASAAoCABgACQmdFiASAAoCAAAA.Danizmi:BAAALgADCgQJBAAAAA==.Dano:BAAALgADCgYJDQAAAA==.Darci:BAAALgAECgYJCwAAAA==.Darkeon:BAAALgAECgcJCwAAAA==.Darlenedark:BAAALgAECgEJAQAAAA==.Darling:BAAALgAECgIJAgAAAA==.Darron:BAAALgAECgIJBAABLgAECggJEgADAAAAAA==.Darrosh:BAABLgAECn8bAAQZAAgJuxOEEgDhAAAZAAYJDhCEEgDhAAAXAAcJjQ34PgDLAAAaAAMJ9hB8FAC1AAAAAA==.Dartian:BAAALgADCgcJDQABLgAECgkJQwACANEfAA==.Daylightt:BAAALgAECgIJAgAAAA==.Dazblood:BAAALgAECgIJAgAAAA==.Dazdot:BAAALgADCgQJBAABLgAECgIJAgADAAAAAA==.Dazsham:BAAALgAECgEJAQABLgAECgIJAgADAAAAAA==.',
De='Deadjuicy:BAAALgAECgEJAQAAAA==.Deathdevil:BAAALgAECgUJBQAAAA==.Deathlurker:BAAALgADCgQJBAAAAA==.Deathmare:BAAALgAECgUJBQAAAA==.Deathmommy:BAAALgAECgcJCAAAAA==.Deathty:BAAALgAECgMJCgABLgAFFAEJAgADAAAAAA==.Dementia:BAAALgADCgMJAwAAAA==.Design:BAABLgAECn8lAAIbAAkJ4Rc7MgAPAgAbAAkJ4Rc7MgAPAgAAAA==.Desmeridian:BAAALgAECgUJBQAAAA==.Dethendrova:BAAALgADCgYJBgABLgAECgcJHAAcADMXAA==.Devotee:BAAALgADCgIJAgAAAA==.',
Dh='Dhish:BAABLgAECn8bAAQVAAYJpAfvCACzAAAVAAYJpAfvCACzAAAdAAMJMwdTPABoAAAPAAIJ6gIc1AAxAAAAAA==.',
Di='Diltlish:BAAALgAECgMJBQAAAA==.Diocles:BAAALgAECgUJBgAAAA==.Disconcern:BAAALgAECgEJAQAAAA==.Discontent:BAACLgAFFH8GAAIeAAIJUR2wMwCNAAAeAAIJUR2wMwCNAAAuAAQKfxQAAx4ABwnwHKQQAOkBAB4ABwnwHKQQAOkBAB8ABQknEVxuAP0AAAAA.Discordiä:BAABLgAECn8XAAIgAAgJHRf9HQDeAQAgAAgJHRf9HQDeAQAAAA==.Discspal:BAAALgAECgYJBwAAAA==.Diåblo:BAAALgADCgUJBQAAAA==.',
Dm='Dmginc:BAAALgADCgIJAgAAAA==.',
Do='Doeblin:BAAALgAECgUJEwAAAA==.Domidouse:BAAALgAECgUJCQAAAA==.Donkedixon:BAAALgADCgYJBgAAAA==.Dosar:BAAALgADCgIJAgAAAA==.Doubtz:BAAALgAECgQJBQABLgAECgQJFAAGAK8eAA==.',
Dp='Dpalx:BAAALgAECgQJBAAAAA==.Dpxs:BAABLgAFFH8HAAIWAAQJkha7PwDmAAAWAAQJkha7PwDmAAAAAA==.',
Dr='Dracaria:BAAALgAECgEJAQAAAA==.Dracones:BAAALgAECgYJDgAAAA==.Dragondz:BAAALgAECgUJBQAAAA==.Dragonflai:BAABLgAECn8nAAIFAAkJnBdCUwDjAQAFAAkJnBdCUwDjAQAAAA==.Dragonkin:BAAALgAECgQJCAAAAA==.Drakkari:BAABLgAECn8UAAMhAAYJKAdzAwCrAAAhAAYJ+wZzAwCrAAASAAYJGwQ20QCQAAAAAA==.Drakkei:BAABLgAECn9LAAMCAAkJZRqRBQDDAQACAAkJZRqRBQDDAQAHAAMJIga/SQCSAAAAAA==.Drawbridge:BAAALgAECgEJAQAAAA==.Drerane:BAAALgADCgYJBgAAAA==.Drexxsster:BAAALgADCgQJBAAAAA==.Drshortbus:BAAALgAECgUJCgAAAA==.Drumitus:BAAALgADCgYJCAAAAA==.Drunkngrundl:BAABLgAECn89AAIKAAkJHiMoBAAGAwAKAAkJHiMoBAAGAwAAAA==.Drylo:BAECLgAFFH8MAAMiAAQJ6R51IABcAQAiAAQJ6R51IABcAQAjAAEJFB7/AwBVAAAuAAQKfy0AAyIACQkmII4JAL8CACIACQmLHo4JAL8CACMACAnFH6UGAIgCAAAA.',
Du='Duckeey:BAAALgAFFAIJBAABLgAFFAUJGwAFAB4QAA==.Dunstir:BAABLgAECn8ZAAINAAgJ6QUgwAAIAQANAAgJ6QUgwAAIAQAAAA==.Dusktrekker:BAAALgAECgkJBwAAAA==.',
Dy='Dypshyt:BAABLgAECn8aAAQiAAkJhxfkTwDvAAAjAAUJUBJRIgAYAQAiAAYJqxDkTwDvAAAkAAUJTgemLgB1AAAAAA==.Dyyke:BAAALgAECgEJAQAAAA==.',
Ed='Edelweíss:BAAALgAECgQJCwAAAA==.',
Ek='Ekazzik:BAAALgAECgYJBgABLgAECgcJHAAcADMXAA==.Ekoh:BAAALgAECgIJAgAAAA==.',
El='Elarol:BAAALgAECgEJAgAAAA==.Eldons:BAAALgADCgIJAgAAAA==.',
Em='Embers:BAABLgAECn8WAAIfAAYJGxPjWADrAAAfAAYJGxPjWADrAAAAAA==.Emeralde:BAAALgAECgYJCgAAAA==.Emilia:BAAALgADCgIJAwAAAA==.Emptyhands:BAAALgAECgYJBgAAAA==.Emptyheals:BAABLgAECn8zAAIgAAkJ3yC7BABEAwAgAAkJ3yC7BABEAwAAAA==.',
En='Enticedem:BAAALgAECgEJAgAAAA==.',
Er='Ereada:BAAALgADCgUJCgAAAA==.Erfinden:BAAALgADCgEJAQAAAA==.',
Es='Espernite:BAAALgAECgQJBAAAAA==.Espers:BAACLgAFFH8GAAIVAAMJCgf6EgCcAAAVAAMJCgf6EgCcAAAuAAQKfx8AAhUACQnpD68+ABQBABUACQnpD68+ABQBAAAA.',
Et='Ethellin:BAABLgAECn8/AAINAAkJ0wjBDAAgAQANAAkJ0wjBDAAgAQAAAA==.',
Eu='Euredes:BAAALgADCgYJBgABLgAECgcJHAAcADMXAA==.',
Fa='Fahrenheit:BAAALgAECgEJAgAAAA==.Farkuat:BAAALgADCgQJBAAAAA==.Fatcastle:BAAALgADCgcJDgAAAA==.',
Fe='Feedmepizzas:BAAALgAECgMJCAAAAA==.Feildmedic:BAAALgAECgEJAQAAAA==.Feleria:BAAALgAECgUJDwAAAA==.Fellslasher:BAAALgAECgIJAgAAAA==.Felmage:BAAALgADCgYJBgAAAA==.Felraiser:BAAALgADCgIJAgABLgADCgUJBgADAAAAAA==.Felwinter:BAABLgAECn81AAIbAAkJthrMIQBbAgAbAAkJthrMIQBbAgAAAA==.Femcelgoon:BAAALgADCgEJAQAAAA==.Fenna:BAAALgADCgYJDAAAAA==.Fetor:BAAALgAECgcJEAAAAA==.',
Fi='Fingulfin:BAAALgAECgIJAwAAAA==.Finwé:BAAALgAECgQJCgAAAA==.Fistsalot:BAAALgAECgQJCAAAAA==.',
Fl='Flafferthorn:BAAALgAECgMJAwAAAA==.Fluxarata:BAABLgAECn8rAAISAAkJ9g27UwCLAQASAAkJ9g27UwCLAQAAAA==.',
Fo='Forthememes:BAAALgAECgcJCQAAAA==.',
Fr='Fred:BAABLgAECn8uAAIfAAgJBAvGPQBPAQAfAAgJBAvGPQBPAQAAAA==.Freddrick:BAAALgADCgQJBAAAAA==.Friendly:BAAALgAECgEJAQAAAA==.Frostbuddy:BAAALgAECgcJDQAAAA==.Frëya:BAAALgADCgYJDQAAAA==.Frío:BAAALgAECgEJAQAAAA==.Frøstitute:BAABLgAECn8tAAIFAAkJwRenMwBKAgAFAAkJwRenMwBKAgAAAA==.',
Fu='Fullmage:BAAALgADCgQJBAAAAA==.',
['Fè']='Fènrïr:BAAALgADCgQJBAAAAA==.',
Ga='Gabel:BAABLgAECn8nAAIdAAkJQh3JBgB2AgAdAAkJQh3JBgB2AgAAAA==.Gadnabit:BAAALgADCgkJCQAAAA==.Gailardia:BAACLgAFFH8GAAICAAMJzRJzIADuAAACAAMJzRJzIADuAAAuAAQKfyQAAgIABwn/HYUvAB4CAAIABwn/HYUvAB4CAAEuAAUUBAkcABQAxx4A.Galand:BAABLgAECn8mAAMGAAcJPB0DCgAqAQAGAAcJzBwDCgAqAQATAAIJoiFoUABTAAAAAA==.Galladin:BAAALgADCggJDgAAAA==.Gardyson:BAABLgAECn8cAAMcAAcJMxdsAgBZAQAcAAcJMxdsAgBZAQAfAAEJbQNKtAAhAAAAAA==.Gazton:BAAALgAECgUJBQAAAA==.',
Gl='Glaaki:BAAALgAECgUJDAAAAA==.',
Gn='Gnob:BAAALgAECgUJEAAAAA==.',
Go='Gooblet:BAAALgADCgQJBQAAAA==.Goodfellow:BAAALgAECgEJAQABLgAECgYJFQAdAMUcAA==.Goopy:BAAALgADCgYJAwAAAA==.',
Gr='Graendal:BAAALgADCgQJBAAAAA==.Granite:BAAALgAECgMJBAAAAA==.Granted:BAAALgADCgUJBQAAAA==.Greevil:BAAALgAECgEJAwAAAA==.Gremilien:BAABLgAECn8qAAIQAAkJExVCCgDMAQAQAAkJExVCCgDMAQAAAA==.Grimgorr:BAAALgADCgMJAwAAAA==.Grimmly:BAAALgAECgEJAQAAAA==.Gruggrug:BAAALgAFFAIJAQAAAA==.Grymdevours:BAAALgADCgYJBgAAAA==.',
Ha='Halcyonic:BAAALgAECgUJCgAAAA==.Halleyscomet:BAABLgAECn8WAAINAAcJPBptRAAXAgANAAcJPBptRAAXAgAAAA==.Happyhammer:BAAALgADCgcJCAAAAA==.Harrod:BAAALgAECggJCwAAAA==.Hawkwave:BAAALgAECgcJEgABLgAECgkJEQADAAAAAA==.Hazardzone:BAAALgAECgMJCgAAAA==.',
He='Heartburn:BAAALgAFFAEJAQABLgAFFAYJHQAfAAUdAA==.Heavyweather:BAAALgADCgcJBwAAAA==.Hefty:BAABLgAECn8XAAMHAAkJ3QtnKQBVAQAHAAcJKQtnKQBVAQACAAUJ8gm3owD6AAAAAA==.Heftyer:BAAALgAECgMJAwAAAA==.Helioween:BAAALgADCgMJAwAAAA==.Helixon:BAAALgADCgYJBgAAAA==.Hellbad:BAACLgAFFH8MAAIKAAQJ7hO+KAAGAQAKAAQJ7hO+KAAGAQAuAAQKfxUAAwoACAleGMEnAHMBAAsABgmOG30jALoBAAoACAkXEsEnAHMBAAAA.Hellbine:BAAALgADCgMJAgAAAA==.Hellfella:BAAALgAECgEJAQAAAA==.Hellonheels:BAAALgAECgQJBAAAAA==.Hellsspawn:BAAALgAECgYJEAAAAA==.Hexaverse:BAAALgADCgYJBgABLgAECgQJBAADAAAAAA==.',
Ho='Hoardwither:BAAALgAECgEJAgAAAA==.Hoenheim:BAAALgAECgEJAQAAAA==.Hogrog:BAAALgADCgMJAwAAAA==.Hokàge:BAACLgAFFH8KAAIXAAMJ7x3+JAD8AAAXAAMJ7x3+JAD8AAAuAAQKfzkABBcACQkpIvQIAJYCABcACQkpIvQIAJYCABoAAgkCGhgbAIwAABkAAQkZAlosAAkAAAAA.Holymortal:BAAALgAECgYJCwAAAA==.Homealone:BAABLgAECn8aAAMWAAkJAQlefADrAAAWAAgJJQdefADrAAAlAAUJ8gPZfQB3AAAAAA==.Honeycruller:BAAALgAECgMJAwABLgAECgkJKAAMAJYbAA==.',
Hu='Huffles:BAAALgAECgQJBwAAAA==.Hugmachine:BAAALgAFFAIJAgAAAA==.Huntinfuzzy:BAAALgAECgkJDwAAAA==.Huntn:BAAALgADCggJCAAAAA==.',
Hy='Hypahypa:BAAALgAECggJEgAAAA==.',
Ia='Iamknot:BAAALgAECgQJBgAAAA==.',
Ic='Icemommy:BAAALgADCgQJCAAAAA==.',
Ig='Igothots:BAACLgAFFH8FAAIPAAIJZBDKVQBvAAAPAAIJZBDKVQBvAAAuAAQKfx4AAw8ACQl/HgIQALgCAA8ACQl/HgIQALgCAB0AAQltCb9YACkAAAAA.',
Il='Illariana:BAABLgAECn8aAAQMAAgJNRI5LABzAQAMAAgJNRI5LABzAQAUAAEJwQLCegAfAAAgAAEJvgHGigAdAAAAAA==.Illirotica:BAAALgAECgcJCQAAAA==.',
In='Incredibro:BAAALgADCgEJAQAAAA==.Insanitty:BAAALgAECgcJDwAAAA==.Invincible:BAAALgAECgEJAQABLgAECgYJIgAJAIEkAA==.',
Ir='Ironlobo:BAABLgAECn8YAAIFAAYJhxkZfACAAQAFAAYJhxkZfACAAQAAAA==.Ironsolari:BAAALgADCgYJBgAAAA==.Irritable:BAABLgAECn8kAAMmAAkJARs/AwCHAgAmAAkJARs/AwCHAgAbAAEJJRftIQFGAAAAAA==.',
It='Itherious:BAAALgAECgUJEAAAAA==.',
Ja='Jacham:BAABLgAECn8WAAIfAAkJ2hSIHwDzAQAfAAkJ2hSIHwDzAQAAAA==.Jackyll:BAAALgAECgQJCAAAAA==.Jacmehof:BAAALgADCgIJAgAAAA==.Jagerboy:BAAALgAECgYJBgAAAA==.Jango:BAAALgAECgIJAgABLgAECgcJHAAcADMXAA==.Jatix:BAACLgAFFH8UAAINAAUJpR5RFQANAQANAAUJpR5RFQANAQAuAAQKfyoAAg0ACQkcI3kPAOoCAA0ACQkcI3kPAOoCAAAA.',
Je='Jeetkundo:BAAALgADCgEJAQABLgAECgYJIgAJAIEkAA==.Jellydh:BAAALgAECgUJCgAAAA==.Jellymagus:BAAALgAECgIJAgAAAA==.Jellyms:BAAALgAECgcJDwAAAA==.Jellyspinoff:BAAALgAECgMJBwAAAA==.Jellytown:BAABLgAECn89AAIFAAkJaxRVRQALAgAFAAkJaxRVRQALAgAAAA==.Jelorinea:BAAALgAECgMJCQAAAA==.Jemmi:BAAALgADCgEJAQAAAA==.Jessiana:BAAALgAECgYJEQAAAA==.Jezelda:BAAALgAECgQJBgAAAA==.',
Jo='Joeydonuts:BAEALgAECgMJAwABLgAECgUJBgADAAAAAA==.',
Jp='Jpeppers:BAABLgAECn8gAAICAAcJwRRSCQBkAQACAAcJwRRSCQBkAQAAAA==.',
Ju='Judgementalx:BAAALgAFFAEJAQAAAA==.Juicifer:BAAALgAECgEJAgAAAA==.Jumano:BAAALgAECgUJCgAAAA==.Jundra:BAAALgAECgUJCgAAAA==.Jurih:BAAALgADCgIJAgAAAA==.',
Ka='Kaineh:BAABLgAECn8oAAIQAAgJah3WBQA/AgAQAAgJah3WBQA/AgAAAA==.Kainë:BAAALgADCgIJAgAAAA==.Kait:BAABLgAECn8+AAICAAkJ6R8zEQDHAgACAAkJ6R8zEQDHAgAAAA==.Kaladil:BAAALgAECgcJDgAAAA==.Kamis:BAAALgAECgMJAwAAAA==.Kanaga:BAAALgAECgQJBQAAAA==.Kannan:BAABLgAECn8YAAMSAAgJzxv/LwA8AgASAAgJzxv/LwA8AgAYAAEJAQdWeQAqAAAAAA==.Kashmihhr:BAAALgADCgIJAgAAAA==.Kashmir:BAAALgAECgQJBAAAAA==.Kasmes:BAAALgADCggJGQAAAA==.Kasmius:BAAALgAECgMJAwAAAA==.Kasmus:BAAALgAECgQJCAAAAA==.Kawdor:BAABLgAECn86AAQRAAkJfBHfFwBgAQARAAgJ2xDfFwBgAQAnAAcJfRSLBQAJAQANAAMJ8wrNQQFqAAAAAA==.',
Ke='Keetsz:BAAALgAECgYJDAAAAA==.Kelaino:BAAALgADCgQJBQAAAA==.Keledish:BAAALgADCgEJAQAAAA==.',
Kh='Khansmebduke:BAACLgAFFH8FAAMYAAQJNxakGQDUAAAYAAMJkRmkGQDUAAASAAEJKgzfnQA9AAAuAAQKfxYAAxgACAmlHC4WANkBABIACAk1F1w+APsBABgABwlXHS4WANkBAAEuAAUUBQkJAB0Ajh4A.Khota:BAAALgAECgYJBgAAAA==.',
Ki='Kiaf:BAAALgADCgcJDQAAAA==.Kiba:BAAALgADCgEJAQAAAA==.Killakeecat:BAAALgADCgYJBgAAAA==.Killanick:BAAALgAECgEJAQAAAA==.Killdar:BAAALgAECgQJBAAAAA==.Kimia:BAAALgADCgYJCQAAAA==.Kirtthedirt:BAAALgAECgYJBwAAAA==.Kirtthehurt:BAABLgAECn8pAAIFAAkJShhlMABXAgAFAAkJShhlMABXAgAAAA==.',
Ko='Koldfront:BAAALgAECgUJCwAAAA==.Kollinator:BAABLgAECn8XAAICAAYJ9RacCQBfAQACAAYJ9RacCQBfAQAAAA==.Korso:BAAALgADCgUJCwABLgAECgcJJAAOAKgQAA==.Kotal:BAAALgAECgEJAQAAAA==.',
Ku='Kurtina:BAAALgAECgEJAQAAAA==.',
Ky='Kylair:BAABLgAECn80AAIMAAkJ/B4cCgCtAgAMAAkJ/B4cCgCtAgAAAA==.Kynreessa:BAAALgADCgYJCAAAAA==.Kyyell:BAAALgAECgcJCQAAAA==.Kyønshi:BAAALgADCgUJBgAAAA==.',
['Kì']='Kìrito:BAAALgAECgcJDgAAAA==.',
La='Labeya:BAEALgADCgMJAwAAAA==.Lafty:BAAALgAFFAEJAgAAAA==.Laftydh:BAAALgAECgYJEgABLgAFFAEJAgADAAAAAA==.Lailah:BAAALgADCgIJAgABLgAECgkJSwANAEcdAA==.Laine:BAAALgADCgMJAwAAAA==.Landrra:BAAALgAECgQJBAAAAA==.Larac:BAAALgAECgkJEwAAAA==.Lathsong:BAAALgADCgYJDwAAAA==.Lavi:BAAALgADCgQJAwAAAA==.',
Le='Leadge:BAAALgADCgYJBwAAAA==.Lenik:BAABLgAECn8aAAIXAAYJ+gkGOADxAAAXAAYJ+gkGOADxAAAAAA==.Leskya:BAAALgADCgQJAwAAAA==.',
Li='Libras:BAAALgADCgMJAwAAAA==.Licorice:BAAALgAECgUJDgABLgAECgkJKAAMAJYbAA==.Lieree:BAABLgAECn8XAAIFAAgJUg3VggByAQAFAAgJUg3VggByAQAAAA==.Lifeguàrd:BAAALgAECgkJBwAAAA==.Lillana:BAAALgADCgcJDQAAAA==.Lilrayne:BAAALgADCgYJBgABLgAECgkJHAAHAIoPAA==.Lilyfaye:BAAALgADCgkJDAAAAA==.Limosfire:BAABLgAECn8VAAIQAAYJkAO7JACOAAAQAAYJkAO7JACOAAAAAA==.Linsatha:BAAALgAECggJEAAAAA==.',
Lo='Loa:BAAALgAECgEJAwAAAA==.Lockty:BAAALgAECgIJBgABLgAFFAEJAgADAAAAAA==.Logi:BAAALgADCgYJCwAAAA==.Lorezever:BAAALgADCgcJDQAAAA==.Lotion:BAAALgADCgIJAgAAAA==.',
Lu='Luar:BAAALgAECgYJDQAAAA==.Lulubean:BAAALgAECgMJAwAAAA==.Lunaris:BAAALgADCgQJBAAAAA==.Lungorthin:BAAALgAECgQJBQAAAA==.Lunà:BAABLgAECn8iAAIBAAgJ1QWLBAC2AAABAAgJ1QWLBAC2AAAAAA==.',
Ly='Lythalle:BAAALgAECgEJAQAAAA==.Lythwynn:BAABLgAECn8rAAINAAkJhQ+0cwCGAQANAAkJhQ+0cwCGAQAAAA==.',
['Lá']='Lásh:BAAALgAECgUJCAABLgAECgcJJAAOAKgQAA==.',
Ma='Mace:BAAALgAECgEJAQAAAA==.Madison:BAAALgAECgEJAQAAAA==.Madyorkies:BAAALgAECgkJAQAAAA==.Magdolyn:BAAALgADCgMJAwAAAA==.Mageyboi:BAAALgAECgQJBgABLgAFFAMJCgAXAO8dAA==.Magickul:BAAALgAECgYJDAAAAA==.Magleon:BAAALgADCgIJAgAAAA==.Magonk:BAAALgADCgEJAQAAAA==.Mahano:BAABLgAECn8XAAICAAgJ1BoPHwBsAgACAAgJ1BoPHwBsAgABLgAECgcJHAAcADMXAA==.Makis:BAAALgAECgMJBQAAAA==.Malachi:BAAALgAECgYJBwAAAA==.Manavoid:BAABLgAECn8cAAISAAYJkArjpwDVAAASAAYJkArjpwDVAAAAAA==.Mandragore:BAAALgAECgIJBAAAAA==.Massili:BAAALgADCgkJGgAAAA==.Mastor:BAAALgADCgQJBwAAAA==.Maynard:BAABLgAECn8hAAIJAAkJ9xErLwC/AQAJAAkJ9xErLwC/AQAAAA==.',
Mc='Mcdouble:BAAALgADCgMJAwAAAA==.',
Me='Meldanis:BAAALgAECgQJBAAAAA==.Meri:BAABLgAECn8cAAIPAAgJlxwrJgAfAgAPAAgJlxwrJgAfAgAAAA==.',
Mi='Miande:BAABLgAECn8VAAImAAcJ0xfLCgCyAQAmAAcJ0xfLCgCyAQAAAA==.Microburst:BAAALgAECgUJBwAAAA==.Minecraft:BAAALgAECgIJAgAAAA==.Minilock:BAABLgAECn83AAMBAAkJXhRlAgAjAQABAAUJDBllAgAjAQAbAAkJqxGeCQABAQAAAA==.Misogynixy:BAAALgADCgQJBAAAAA==.Missdeeds:BAAALgAECgUJBQAAAA==.Missleading:BAAALgAECgYJCQAAAA==.Missused:BAAALgAECgYJEgAAAA==.Mithos:BAAALgAECgUJBwAAAA==.Mithraxa:BAAALgAECgQJBAAAAA==.Miyagifu:BAAALgAECgQJBAAAAA==.',
Mo='Moash:BAAALgADCgkJCQAAAA==.Modsagoodtnk:BAABLgAECn8bAAIRAAcJRQ71BADLAAARAAcJRQ71BADLAAABLgAECggJLQACAH8ZAA==.Mongermook:BAABLgAECn8iAAMOAAkJ0QuWCACiAAAOAAkJ0QuWCACiAAAVAAEJxgFpkQAVAAAAAA==.Monnkysham:BAAALgAECgQJBgABLgAECgYJCQADAAAAAA==.Moogledragon:BAAALgADCgMJAwAAAA==.Mooglefur:BAAALgAECgQJBQAAAA==.Moonbloom:BAABLgAECn8cAAIPAAgJQhxLHwBMAgAPAAgJQhxLHwBMAgAAAA==.Mooseknuhkle:BAAALgAECgEJAQAAAA==.Morgrim:BAAALgAECgEJAQAAAA==.Morlosh:BAAALgAECgMJAwAAAA==.Moryna:BAABLgAECn80AAIeAAkJsQhZJQA9AQAeAAkJsQhZJQA9AQAAAA==.',
Mt='Mthrandir:BAAALgADCgUJBQAAAA==.',
Mu='Muford:BAAALgAECgQJBQABLgAFFAgJFQAKAOQfAA==.Mull:BAAALgAECgYJEwAAAA==.Muloc:BAAALgADCgEJAQAAAA==.',
My='Myaka:BAAALgAECgYJBgAAAA==.Mythicc:BAAALgADCgUJCQAAAA==.',
Na='Naatixa:BAAALgAECggJDAAAAA==.Nacronor:BAAALgAECgUJEAAAAA==.Naiika:BAAALgAECgYJBwAAAA==.Nascha:BAAALgADCgEJAQAAAA==.Nasoj:BAAALgAECgYJCQABLgAECgYJEwADAAAAAA==.',
Ne='Necrotic:BAAALgAECgQJBAAAAA==.Nedalla:BAAALgAECgYJDAAAAA==.Neeve:BAAALgAECgMJAwAAAA==.Nekrotik:BAAALgADCgcJBgAAAA==.Neobahamut:BAAALgAECgIJAgABLgAECgcJDgADAAAAAA==.Netharel:BAAALgADCgIJAgAAAA==.Newports:BAAALgAECgEJAQAAAA==.',
Ni='Nichôlasmage:BAAALgAECgYJCwAAAA==.Nickatnite:BAAALgAFFAEJAQAAAA==.Nickelodeon:BAAALgAFFAIJAwAAAA==.Nicksaban:BAABLgAECn8nAAINAAkJuBuBLgBHAgANAAkJuBuBLgBHAgAAAA==.Nightgear:BAACLgAFFH8wAAMCAAgJaBcADwDuAQACAAcJehkADwDuAQAQAAIJ/ApJNQBJAAAuAAQKf1kAAwIACQm1IgUIABADAAIACQm1IgUIABADABAABAnfEoAjAJcAAAAA.Nightshades:BAAALgADCgQJBAAAAA==.Nilux:BAAALgAECgYJDwAAAA==.Ninetails:BAAALgAECgUJCgAAAA==.Niteshadeth:BAAALgAECgQJBQAAAA==.Niteyknight:BAAALgAECgQJBAAAAA==.Nixeava:BAABLgAECn8bAAIlAAgJ+wR6VADoAAAlAAgJ+wR6VADoAAAAAA==.',
No='Nogooddruid:BAAALgAECgUJDgAAAA==.Nopetsneeded:BAABLgAECn89AAIQAAkJzBRpCAD3AQAQAAkJzBRpCAD3AQAAAA==.Norepairbill:BAAALgAECgEJAQABLgAECgkJPQAQAMwUAA==.Nostariel:BAAALgAECgQJCgAAAA==.Notadoctor:BAAALgAECgYJCAAAAA==.Noteworthy:BAAALgAECgYJEgABLgAFFAYJDwAGAN0dAA==.',
Ny='Nysong:BAABLgAECn83AAMBAAgJPAu/EgAfAQABAAgJPAu/EgAfAQAbAAMJYwKJGAFPAAAAAA==.',
['Nó']='Nórin:BAAALgAECgUJBQAAAA==.',
Ob='Obali:BAAALgADCgYJCgAAAA==.',
Od='Oddangel:BAAALgAECgYJEwAAAA==.Ode:BAAALgAECgkJDgAAAA==.Odex:BAACLgAFFH8HAAIiAAQJqQOyGgCkAAAiAAQJqQOyGgCkAAAuAAQKfyoAAyMACQlvDX8IAKgBACMACQlvDX8IAKgBACIAAQmmCE2QADoAAAAA.',
Oh='Ohblergen:BAAALgAECgIJAgAAAA==.',
Ok='Okragren:BAABLgAECn83AAIlAAkJ/A1NMwBvAQAlAAkJ/A1NMwBvAQAAAA==.',
Ol='Olehi:BAAALgADCgcJBwAAAA==.Olynder:BAAALgAECgIJBAAAAA==.',
On='Onos:BAABLgAECn8bAAICAAcJIyQ4IABEAgACAAcJIyQ4IABEAgAAAA==.Onto:BAAALgADCgEJAQAAAA==.Ontoquas:BAAALgADCgkJCgAAAA==.',
Or='Orinin:BAAALgAECgUJBQABLgAECgQJCQADAAAAAA==.',
Pa='Paleclaw:BAAALgADCgQJBAAAAA==.Palitroque:BAAALgAECgQJBAAAAA==.Pally:BAAALgAECgUJBQAAAA==.Papasmurfz:BAAALgAECgEJAwAAAA==.Paramedic:BAAALgAECgUJEAAAAA==.Pathogen:BAABLgAECn8hAAIGAAkJDR/oOwARAgAGAAkJDR/oOwARAgAAAA==.',
Pe='Penryn:BAAALgAECgQJBgAAAA==.Pepster:BAABLgAECn8XAAIoAAkJpQHgLgCAAAAoAAkJpQHgLgCAAAAAAA==.Persephoknee:BAAALgADCgEJAQAAAA==.Persephoni:BAAALgAECgUJBAAAAA==.',
Pf='Pfchen:BAAALgAECgIJAwAAAA==.',
Pl='Plaguestrip:BAAALgAECgEJAwAAAA==.Plinkerbell:BAAALgAECgMJAwAAAA==.Plumprnickel:BAAALgAECgEJAQAAAA==.Plxkingg:BAAALgADCgUJBQAAAA==.',
Po='Poppit:BAAALgAECgQJBQAAAA==.Porimma:BAAALgAECgYJDwAAAA==.Pormas:BAAALgAECgYJDwAAAA==.Poseydon:BAAALgADCgQJBAABLgAECgEJAQADAAAAAA==.',
Pr='Prayerz:BAAALgADCgMJAwAAAA==.Proctology:BAAALgAECgQJBAAAAA==.Prom:BAAALgAECgcJDgAAAA==.Promethèus:BAAALgAECgQJBAAAAA==.Prosby:BAAALgADCgIJAgAAAA==.Prowlnfool:BAAALgADCgUJBQAAAA==.Pryto:BAAALgADCgkJDgABLgAFFAIJAwADAAAAAA==.',
Qu='Queedle:BAABLgAECn8jAAIZAAkJEw4eAQAEAQAZAAkJEw4eAQAEAQAAAA==.Quickly:BAAALgAECgcJDAAAAA==.',
Ra='Raennis:BAAALgAECgIJAgAAAA==.Ragalstan:BAAALgAECgEJAgAAAA==.Rahanumn:BAABLgAECn8YAAINAAgJ6wktpAAxAQANAAgJ6wktpAAxAQAAAA==.Rainlette:BAAALgAECgcJDwAAAA==.Rainsvoker:BAACLgAFFH8jAAIkAAYJXQ2aEgBqAQAkAAYJXQ2aEgBqAQAuAAQKf1IAAyQACQkOHL4GAJUCACQACQkOHL4GAJUCACIABgk7CAxeAMAAAAAA.Ramike:BAAALgAECggJCQAAAA==.Raqtar:BAAALgAECgIJAgABLgAECgkJEgADAAAAAA==.Ratbreath:BAAALgADCgYJBgAAAA==.Ratrazarke:BAAALgADCgIJAgAAAA==.Razihel:BAAALgADCgYJCQAAAA==.Razzledazzlë:BAAALgAECgEJAQAAAA==.',
Re='Reaver:BAAALgAECgQJBAAAAA==.Reddan:BAABLgAECn8qAAINAAgJlgzSmwA+AQANAAgJlgzSmwA+AQAAAA==.Renata:BAAALgAFFAIJAgAAAA==.Replicant:BAAALgAECgEJAQAAAA==.Retman:BAAALgAECgMJAQAAAA==.Reverìe:BAAALgAECgcJBwAAAA==.Reylinn:BAAALgAECgQJBAAAAA==.Reyra:BAAALgAECgEJAQABLgAFFAIJAgADAAAAAA==.Reï:BAABLgAECn8gAAIPAAkJchTZJAAlAgAPAAkJchTZJAAlAgAAAA==.',
Ri='Ridlei:BAAALgAECgMJBAAAAA==.Rimchester:BAAALgAECgIJAQAAAA==.Rinji:BAAALgAECgYJCwAAAA==.Ritzon:BAABLgAECn89AAMfAAkJJSRhBgD4AgAfAAkJJSRhBgD4AgAeAAEJmBdmcQA+AAAAAA==.',
Ro='Rosadita:BAAALgAECgQJBQAAAA==.Roxydan:BAABLgAECn8dAAMBAAgJiQ03KQAdAQAbAAgJiQ1KZwCWAQABAAYJ8Ag3KQAdAQAAAA==.',
Ru='Runastalis:BAAALgADCgYJBgAAAA==.Ruwea:BAAALgAECgEJAQAAAA==.',
Ry='Rykken:BAAALgAECgEJAgAAAA==.Ryko:BAABLgAECn8fAAIoAAcJqBSRFwBOAQAoAAcJqBSRFwBOAQAAAA==.',
['Rë']='Rëyra:BAAALgAFFAIJAgAAAA==.',
Sa='Salene:BAAALgAFFAEJAQAAAA==.Sanandume:BAAALgADCgEJAQAAAA==.Sanctess:BAAALgAECggJDgAAAA==.Sankai:BAAALgAECgEJAQABLgAECgYJDgADAAAAAA==.Saraelle:BAAALgAECgEJAgAAAA==.Sarlas:BAAALgADCgQJBAAAAA==.Sarumanpally:BAAALgAECgYJBwAAAA==.Saruquan:BAAALgAECgkJCQAAAA==.Sayomi:BAAALgADCgcJEwAAAA==.',
Se='Secretjuicy:BAAALgAECgYJCQAAAA==.Senseijundra:BAAALgAECgQJCAAAAA==.Sentinaal:BAAALgADCgcJBwAAAA==.',
Sh='Shabadu:BAAALgADCgQJBAAAAA==.Shadyandi:BAAALgADCgcJCAAAAA==.Shamanhack:BAAALgAFFAIJAwAAAA==.Shan:BAAALgADCgYJBgAAAA==.Sharazad:BAAALgAECggJCQAAAA==.Sheda:BAAALgAECgQJBAAAAA==.Shedia:BAAALgAECgEJAQAAAA==.Shmoove:BAEALgAECgUJBgAAAA==.Shmooves:BAEALgAECgQJBAABLgAECgUJBgADAAAAAA==.Shoukei:BAAALgADCgIJAwAAAA==.',
Si='Sianna:BAAALgADCgYJBgAAAA==.Sieya:BAAALgADCgQJBAAAAA==.Siinful:BAAALgAECgEJAQAAAA==.Simbruh:BAAALgADCgMJAwAAAA==.Simpari:BAABLgAFFH8FAAIGAAIJ4wWyTwCBAAAGAAIJ4wWyTwCBAAABLgAFFAUJGwAFAB4QAA==.Sinarria:BAAALgAECgEJAQAAAA==.Sithra:BAAALgADCgEJAQAAAA==.',
Sk='Skeemer:BAAALgAECgUJBQAAAA==.Skeetro:BAAALgAECgEJAQAAAA==.Skips:BAAALgAECgQJCQAAAA==.Skullace:BAABLgAECn8qAAIBAAkJuw9GCgChAQABAAkJuw9GCgChAQAAAA==.Skullhead:BAAALgADCgEJAQAAAA==.Skybreaker:BAAALgAECgkJCAAAAA==.Skylette:BAAALgAECgYJBwAAAA==.',
Sm='Smashurfacen:BAAALgADCgcJFAAAAA==.',
Sn='Snitbit:BAAALgADCgkJGgAAAA==.Sno:BAAALgADCgEJAQABLgAECgUJBwADAAAAAA==.Snoopingas:BAAALgAECgEJAQAAAA==.Snpcrklpopu:BAAALgADCgYJCAAAAA==.',
So='Solarana:BAAALgAECgkJCQAAAA==.Sortiebatoru:BAAALgAECgIJAwAAAA==.Sotzi:BAAALgADCggJEQAAAA==.Souldune:BAAALgAECgYJBgAAAA==.',
Sp='Sparkplugg:BAAALgAECgEJAQAAAA==.',
Sr='Srfreaky:BAAALgAECgUJEAAAAA==.',
St='Sterlìng:BAAALgAECgUJCQAAAA==.Stevejabbs:BAABLgAECn8iAAMJAAYJgSQWAgAnAgAJAAYJgSQWAgAnAgAKAAMJ5SAEOQAYAQAAAA==.Stormcunning:BAABLgAECn8WAAIlAAYJCAxiTAAWAQAlAAYJCAxiTAAWAQAAAA==.Stormfire:BAAALgADCgcJBwAAAA==.Stormßringer:BAABLgAECn8UAAIlAAgJERDXMwCJAQAlAAgJERDXMwCJAQAAAA==.Stownr:BAAALgAECgYJBgAAAA==.Strip:BAAALgADCgUJCAAAAA==.Strongclaw:BAAALgADCgUJBQAAAA==.Stumpyborg:BAABLgAECn8VAAQBAAcJaAY9MgBVAAAbAAYJNgSn3gCdAAABAAIJMws9MgBVAAAmAAEJhAcZQwArAAABLgAECgkJFwAHAN0LAA==.Stónéhëárt:BAAALgADCgYJBwABLgAECgkJEQADAAAAAA==.',
Su='Subdue:BAAALgADCgQJBAAAAA==.Subverse:BAAALgAECgQJBAAAAA==.Sukimyheelz:BAAALgAECgQJBAAAAA==.Sundance:BAAALgAECgcJDgAAAA==.Sune:BAABLgAECn8gAAMMAAYJxgvZRwDwAAAMAAYJxgvZRwDwAAAgAAEJNwk2ggAqAAAAAA==.Supplicant:BAAALgADCgQJBwAAAA==.',
Sv='Svellulfr:BAAALgAECgEJAQAAAA==.Svuca:BAAALgADCgcJBwAAAA==.',
Sy='Sydneyweenie:BAAALgADCgcJCAAAAA==.Syldi:BAAALgAECgEJAQABLgAECgcJIwAUALYZAA==.Sythis:BAAALgAECgIJAwAAAA==.',
['Sä']='Sästa:BAAALgADCgkJCQAAAA==.',
['Sö']='Sörren:BAABLgAECn8kAAImAAYJqgb4BACjAAAmAAYJqgb4BACjAAAAAA==.',
Ta='Tacosdeasada:BAAALgAECgEJAQAAAA==.Taitertot:BAAALgADCgQJBQAAAA==.Tanelórn:BAAALgAECgQJBQAAAA==.Tanlon:BAAALgAECggJEgAAAA==.Taykorra:BAAALgADCggJDQAAAA==.',
Te='Telandril:BAABLgAECn8vAAIPAAkJvxH4MwDNAQAPAAkJvxH4MwDNAQAAAA==.Telphin:BAAALgAECgYJDAAAAA==.Tempestira:BAAALgAECgEJAgAAAA==.Tensuken:BAABLgAECn8ZAAINAAYJpBidsAAeAQANAAYJpBidsAAeAQAAAA==.Teylonna:BAAALgAECgEJAQAAAA==.',
Th='Thadgun:BAAALgADCgkJFQAAAA==.Thadium:BAAALgAECgMJAwAAAA==.Thalgan:BAAALgAECgEJAQAAAA==.Thalyn:BAAALgAECgEJAQAAAA==.Thecword:BAAALgADCgYJBgAAAA==.Themedic:BAABLgAECn8cAAMWAAcJyBRuDADaAAAWAAcJyBRuDADaAAAlAAEJ6gFuxAAXAAAAAA==.Theremar:BAAALgAECgMJAwAAAA==.Thergothon:BAAALgAECgEJAQABLgAECgMJAwADAAAAAA==.Thisisdrexx:BAAALgAECgIJAwAAAA==.Thorwrath:BAAALgADCgEJAgAAAA==.Thrazoro:BAAALgAECgQJBAAAAA==.Thrazzoro:BAAALgAECgYJEwAAAA==.Thrægg:BAAALgAECgYJCAABLgAECgYJIgAJAIEkAA==.',
Ti='Tiarl:BAABLgAECn81AAIUAAkJHRehEQBUAgAUAAkJHRehEQBUAgAAAA==.Tiia:BAAALgADCgIJAgAAAA==.Timex:BAABLgAECn8XAAMjAAYJRCD5DgDrAQAjAAYJRCD5DgDrAQAiAAEJUhdnjgA+AAAAAA==.Tinydots:BAAALgAECgIJAgAAAA==.Tinysitril:BAAALgAECgYJCQABLgAFFAQJCgAYAJ0NAA==.Tinysohei:BAAALgAECgQJBAAAAA==.Titañick:BAAALgAECgEJAwAAAA==.',
To='Tom:BAABLgAECn8aAAMiAAYJLgvvVgDWAAAiAAYJLgvvVgDWAAAjAAEJZQhLJwAvAAAAAA==.Toosxyfohair:BAABLgAECn8dAAIWAAgJ9xVpLwD4AQAWAAgJ9xVpLwD4AQAAAA==.',
Tr='Trainwrekk:BAAALgADCgYJBgAAAA==.Tranqar:BAAALgAECgQJBgAAAA==.Tresg:BAAALgAECgYJCQAAAA==.Trissandra:BAAALgAECgEJAQAAAA==.Trolltoll:BAAALgADCgEJAwAAAA==.Trüth:BAAALgADCggJEAAAAA==.',
Tw='Twentytwo:BAAALgAECgEJAQAAAA==.Twylidan:BAEALgAECgkJCgABLgAFFAQJDAAiAOkeAA==.',
Ty='Tyrannt:BAAALgAECgEJAQAAAA==.Tyrannus:BAAALgADCgYJBgAAAA==.Tyregar:BAAALgAECgEJAQAAAA==.Tyrànda:BAAALgAECgQJBgAAAA==.Tyzy:BAAALgAECgEJAgAAAA==.',
['Tö']='Tötém:BAAALgAECgEJAQAAAA==.',
Ul='Ulanhi:BAABLgAECn8VAAIdAAUJzh31EACdAQAdAAUJzh31EACdAQAAAA==.',
Un='Undeadjelly:BAAALgAECgYJEwAAAA==.Unholy:BAAALgAECgYJDwAAAA==.',
Ur='Urkzul:BAAALgADCgMJAwAAAA==.Ursoth:BAAALgADCgUJCgAAAA==.',
Ut='Uthèrsmight:BAAALgAECgYJBgAAAA==.Uti:BAAALgADCgUJBQAAAA==.',
Uu='Uubs:BAAALgADCgEJAQABLgAFFAMJCgANAJoSAA==.',
Va='Valakk:BAAALgAECgUJCAAAAA==.Vallak:BAAALgADCgIJBAAAAA==.Valsitril:BAAALgAECgYJEAABLgAFFAQJCgAYAJ0NAA==.Valthaczar:BAAALgAECgMJBgAAAA==.Vanara:BAAALgAECgEJAgAAAA==.Varadun:BAAALgAFFAIJAwAAAA==.Varrosh:BAAALgADCgYJBgAAAA==.Vathan:BAAALgAECgQJBQAAAA==.',
Ve='Velmora:BAAALgAECgkJCQAAAA==.Velsetin:BAABLgAECn8dAAIFAAcJTBsyTABSAgAFAAcJTBsyTABSAgABLgAFFAMJBQAVAMcUAA==.Verathina:BAAALgADCgEJAgAAAA==.Versed:BAAALgADCgUJBQABLgAECgQJBAADAAAAAA==.Veryspooky:BAABLgAECn8aAAIbAAgJNhkHOAD5AQAbAAgJNhkHOAD5AQAAAA==.Vexian:BAABLgAECn8aAAMlAAkJBxwbDwB+AgAlAAkJBxwbDwB+AgAWAAEJ3B/FtwBcAAAAAA==.',
Vf='Vfl:BAAALgADCgcJBwAAAA==.',
Vi='Vicas:BAAALgAECgcJEgAAAA==.',
Vl='Vladdek:BAAALgAFFAEJAwAAAA==.Vladdok:BAAALgAECgUJBQAAAA==.Vladok:BAAALgAECgQJCwAAAA==.Vladokk:BAAALgAECgMJAwAAAA==.',
Vo='Voidofdeath:BAAALgADCgQJBAAAAA==.Voidshiekah:BAAALgADCgEJAQAAAA==.Vorteia:BAAALgADCgYJBgAAAA==.',
['Vé']='Véngéánçé:BAAALgAECgMJBAAAAA==.',
Wa='Wald:BAAALgAECgYJEAAAAA==.Warmongerr:BAAALgADCgIJAgAAAA==.Waruh:BAAALgADCgcJCQAAAA==.',
We='Webgar:BAAALgAECgEJAQAAAA==.Webrune:BAAALgAECgMJAwAAAA==.',
Wh='Whisperlia:BAAALgAECgQJBwAAAA==.Whisperwindd:BAAALgAECgYJBwAAAA==.White:BAABLgAFFH8GAAMmAAMJYg71BQCPAAAmAAIJRgz1BQCPAAAbAAEJmhLyRwBMAAAAAA==.Whitetoothe:BAABLgAECn84AAICAAcJxRadVgCgAQACAAcJxRadVgCgAQAAAA==.',
Wi='Witemandown:BAAALgADCgcJCAAAAA==.Witherbear:BAAALgAECgEJAQAAAA==.Witherhoard:BAAALgADCgEJAQAAAA==.Wizzy:BAAALgADCgEJAQAAAA==.',
Wo='Workin:BAAALgADCgEJAQABLgAECggJIgAPAEIXAA==.',
['Wå']='Wånheda:BAAALgAECggJEwAAAA==.',
Xa='Xaniana:BAAALgAECgkJEAAAAA==.Xaosin:BAAALgADCgUJBQAAAA==.',
Xe='Xenzak:BAAALgAECgEJAQAAAA==.Xephir:BAAALgADCgMJAwAAAA==.Xerxës:BAAALgAECgEJAQAAAA==.',
Xl='Xl:BAAALgAECgQJCwAAAA==.',
Xo='Xoito:BAAALgAECgEJAQABLgAECgcJBQADAAAAAA==.Xotiko:BAAALgAECgYJDAAAAA==.',
Xu='Xubris:BAAALgADCgYJCQAAAA==.',
['Xâ']='Xâxâs:BAAALgAECgMJAwABLgAECggJGwAiAHQFAA==.',
Ya='Yaerin:BAACLgAFFH8ZAAIgAAQJcCMSGwCLAQAgAAQJcCMSGwCLAQAuAAQKfyQAAiAACQkAIvMDAFsDACAACQkAIvMDAFsDAAAA.',
Yu='Yunarä:BAAALgAECgYJCAAAAA==.Yuukon:BAABLgAECn8bAAQTAAgJtxfwHABxAQATAAgJtxfwHABxAQAGAAQJ5gOZOQFkAAAIAAEJDwgrGAAvAAAAAA==.',
Za='Zakuul:BAAALgADCgQJBAAAAA==.Zalezaar:BAAALgAECgIJAgAAAA==.Zangetsu:BAAALgAECgcJBwAAAA==.Zarusthra:BAAALgAECgEJAQAAAA==.Zaxie:BAABLgAECn8/AAISAAkJrh2DAQBWAgASAAkJrh2DAQBWAgAAAA==.',
Ze='Zenwu:BAAALgADCgkJGwAAAA==.Zephrylia:BAAALgAECgQJBQAAAA==.Zerama:BAAALgAECgUJBQAAAA==.',
Zh='Zheratul:BAAALgAECgEJAQAAAA==.Zhirl:BAAALgAECgkJCQAAAA==.Zhivet:BAAALgAECgYJBwAAAA==.',
Zi='Zilphia:BAABLgAECn8UAAIFAAkJfAcjHwB/AAAFAAkJfAcjHwB/AAAAAA==.',
Zu='Zuriel:BAAALgAECgIJAgAAAA==.',
Zy='Zyku:BAAALgAECgEJAQAAAA==.Zylphie:BAAALgADCgcJBwAAAA==.',
['Àm']='Àmagezing:BAAALgAFFAIJAgABLgAFFAYJGwANACweAA==.',
['Åj']='Åj:BAAALgADCgcJBwAAAA==.',
['Åp']='Åpexx:BAABLgAECn8cAAMSAAYJKAZxFACOAAASAAYJCAZxFACOAAAYAAEJzAYcfQAjAAAAAA==.',
['Çw']='Çwÿbàbý:BAAALgAECgYJDQAAAA==.',
['Ór']='Órión:BAABLgAECn8VAAICAAYJ1BLuoQD+AAACAAYJ1BLuoQD+AAAAAA==.',
['Ös']='Östara:BAABLgAECn8iAAIPAAgJQhdHLQDyAQAPAAgJQhdHLQDyAQAAAA==.',
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
