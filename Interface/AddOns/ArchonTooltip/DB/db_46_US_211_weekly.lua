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

local lookup = {'Paladin-Protection','Paladin-Retribution','Warrior-Fury','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-Survival','Hunter-Marksmanship','Hunter-BeastMastery','Mage-Frost','Priest-Shadow','Monk-Brewmaster','Warrior-Arms','Druid-Restoration','Druid-Feral','Monk-Windwalker','Warlock-Demonology','Druid-Balance','Rogue-Assassination','Warlock-Destruction','Unknown-Unknown','Shaman-Restoration','Shaman-Elemental','Warlock-Affliction','Priest-Discipline','Warrior-Protection','DeathKnight-Unholy','DemonHunter-Vengeance','Evoker-Augmentation','Evoker-Devastation','Paladin-Holy','Evoker-Preservation','Priest-Holy','Mage-Arcane','Shaman-Enhancement','Monk-Mistweaver','Druid-Guardian','DeathKnight-Frost','DeathKnight-Blood','Rogue-Outlaw','Rogue-Subtlety',}
local provider = {region='US',realm='Terenas',name='US',type='weekly',zone=46,date='2026-05-24',data={Ac='Achooe:BAABLgAECn8lAAMBAAgJngUJJgC5AAABAAgJbAUJJgC5AAACAAEJJgJtiwEYAAAAAA==.',
Ad='Adrel:BAAALgAECgQJBgAAAA==.Adversity:BAABLgAECn8jAAIDAAgJNiQwCAAnAwADAAgJNiQwCAAnAwAAAA==.',
Ae='Aegeus:BAABLgAECn8WAAMEAAgJCxw5DQCPAgAEAAgJ3Bo5DQCPAgAFAAYJGhHYiQAQAQAAAA==.Aelchad:BAAALgAECgMJAwAAAA==.Aevintz:BAABLgAECn8zAAQGAAkJWhXpDAA9AgAGAAkJWhXpDAA9AgAHAAUJtQbFWwDUAAAIAAUJBAbOlwCmAAAAAA==.',
Af='Afterburnner:BAAALgAECgMJAwAAAA==.',
Ag='Agatha:BAABLgAECn8oAAIJAAkJQBAbTQDaAQAJAAkJQBAbTQDaAQAAAA==.Agathorz:BAAALgAECgEJAgAAAA==.',
Ai='Aidon:BAAALgADCgEJAQAAAA==.Ainzina:BAAALgADCgUJBQAAAA==.Aio:BAAALgAECgYJDAABLgAECgYJFQAKACcVAA==.',
Ak='Akiras:BAAALgADCggJCwAAAA==.',
Al='Alarielle:BAAALgADCgYJBgABLgAECgkJIAALAL0bAA==.Alexeika:BAAALgAECgEJAQAAAA==.Alistarz:BAABLgAECn82AAMDAAkJ5ST1AQBFAwADAAkJ5ST1AQBFAwAMAAYJ9BAzJQAWAQAAAA==.Allei:BAAALgAECgYJCQABLgAFFAMJBwANAOYGAA==.Alyndrya:BAABLgAECn8dAAMEAAkJtxS4EADsAQAEAAkJtxS4EADsAQAFAAYJjRBAgQD3AAAAAA==.Alyndrys:BAABLgAECn8iAAIOAAcJmhOrEQBrAQAOAAcJmhOrEQBrAQAAAA==.',
Am='Amelialynne:BAABLgAECn82AAIFAAkJNRPTLwDqAQAFAAkJNRPTLwDqAQAAAA==.Amithralia:BAABLgAECn8pAAINAAkJ1B5ACQAKAwANAAkJ1B5ACQAKAwAAAA==.Amock:BAAALgADCggJDwAAAA==.',
An='Anaraith:BAAALgADCgQJBAAAAA==.Anejo:BAABLgAECn8UAAIPAAYJ0SLkFwDNAQAPAAYJ0SLkFwDNAQAAAA==.Anhinga:BAAALgAECgIJAgAAAA==.Anilex:BAAALgAECgQJBAAAAA==.Anzarna:BAABLgAECn8VAAIQAAgJjxZ6NwDlAQAQAAgJjxZ6NwDlAQAAAA==.',
Ao='Aodwarf:BAAALgAECgEJAQABLgAFFAgJIgANAEscAA==.Aohikari:BAAALgADCgYJCgABLgAFFAgJIgANAEscAA==.Aokuma:BAACLgAFFH8iAAINAAgJSxwlAQATAwANAAgJSxwlAQATAwAuAAQKfywAAw0ACQlPJLkFAEUDAA0ACQlPJLkFAEUDABEABAlSIRJIAAwBAAAA.',
Ap='Apex:BAAALgAECgEJAQAAAA==.Aprigity:BAABLgAECn8ZAAISAAgJFgZODQA2AQASAAgJFgZODQA2AQAAAA==.',
Aq='Aquaten:BAABLgAECn8ZAAIGAAcJARF2HwCEAQAGAAcJARF2HwCEAQAAAA==.',
Ar='Aramac:BAAALgAECgEJAwAAAA==.Arashinigon:BAABLgAECn8ZAAMNAAkJhRD2YAD1AAANAAgJJg72YAD1AAARAAYJIBaTQwDQAAAAAA==.Arcafrost:BAAALgAECgkJAQAAAA==.Arceus:BAAALgAECgQJBgAAAA==.Archaon:BAABLgAECn8gAAMQAAYJGQ8piQAVAQAQAAYJGQ8piQAVAQATAAEJAADuRwAAAAAAAA==.Argoroth:BAABLgAECn8VAAICAAYJeRnjcACaAQACAAYJeRnjcACaAQAAAA==.Ariandise:BAAALgAECgMJAwABLgAECgYJDAAUAAAAAA==.Arick:BAABLgAECn8VAAICAAgJYRpsTwDzAQACAAgJYRpsTwDzAQAAAA==.Ark:BAABLgAECn9DAAMVAAkJpib/AQBrAwAVAAkJpib/AQBrAwAWAAYJIyWbGQDsAQAAAA==.',
As='Asic:BAAALgADCgIJAgAAAA==.Asmodias:BAAALgAECgYJDAAAAA==.Asmódeus:BAABLgAECn8cAAQXAAgJoQ73DQBTAQAXAAYJWw73DQBTAQAQAAgJCgo8awBRAQATAAQJYQ1RPgC7AAAAAA==.Asroldal:BAAALgADCgcJBwAAAA==.Asymptomatic:BAAALgAECgYJEQAAAA==.',
Av='Avarak:BAAALgADCgcJDAAAAA==.',
Aw='Awenina:BAAALgADCgkJCQAAAA==.',
Ax='Axon:BAABLgAECn8gAAIJAAgJERFuXwCnAQAJAAgJERFuXwCnAQAAAA==.',
['Aì']='Aìo:BAABLgAECn8VAAMKAAYJJxXGLQBEAQAKAAYJJxXGLQBEAQAYAAQJvBZ4OgD2AAAAAA==.',
Ba='Baaku:BAAALgADCgQJBgAAAA==.Babyfists:BAAALgAECgcJCQABLgAECggJEgAUAAAAAA==.Baelhay:BAABLgAECn8ZAAIZAAcJUAJPLwCgAAAZAAcJUAJPLwCgAAAAAA==.Baelthas:BAAALgADCgEJAQAAAA==.Bats:BAAALgAECgEJAQAAAA==.',
Be='Beanor:BAAALgAECgYJDAAAAA==.Beet:BAAALgADCgcJBwAAAA==.Belitha:BAABLgAECn8rAAIFAAkJMSALEwDoAgAFAAkJMSALEwDoAgAAAA==.Belmaris:BAABLgAECn8nAAISAAgJPBl1BQAFAgASAAgJPBl1BQAFAgAAAA==.Benbreathing:BAAALgAECgUJCQAAAA==.Beng:BAAALgAECgMJBQAAAA==.Berketta:BAAALgAECgYJDwAAAA==.Besttros:BAAALgAECgEJAQAAAA==.',
Bi='Bigbadjohn:BAAALgADCgMJBAAAAA==.Bigcupcakes:BAABLgAECn8aAAIaAAcJqAmEkAAiAQAaAAcJqAmEkAAiAQAAAA==.Bigdaddykong:BAAALgADCggJCAAAAA==.Bigdruid:BAABLgAECn8YAAINAAkJLRHGJwDyAQANAAkJLRHGJwDyAQAAAA==.Bill:BAAALgAECgEJAQAAAA==.Bimbosuzi:BAABLgAECn8UAAIEAAcJvAh2KQD5AAAEAAcJvAh2KQD5AAAAAA==.Binghealing:BAAALgAECgYJCgAAAA==.Bird:BAAALgAECgIJAgAAAA==.',
Bl='Blasteyes:BAABLgAECn8qAAIbAAgJwBzIBABGAgAbAAgJwBzIBABGAgAAAA==.Blegh:BAACLgAFFH8GAAMcAAMJ7BWuLwDYAAAcAAMJ7BWuLwDYAAAdAAEJEAVoDABDAAAuAAQKfyEAAx0ACAkvHqcKADECAB0ABwk2HacKADECABwABgkgGygfAMoBAAAA.Blueflu:BAAALgADCgMJAwAAAA==.Bluegrass:BAABLgAECn88AAIOAAkJqCJMAQAhAwAOAAkJqCJMAQAhAwAAAA==.',
Bo='Bondï:BAABLgAECn8fAAMeAAgJxAnuRABkAQAeAAgJxAnuRABkAQACAAYJpQq8sAAiAQAAAA==.Boogey:BAAALgADCgMJAwAAAA==.Booshybrow:BAAALgADCgEJAQAAAA==.Bootyweaver:BAAALgAECgYJCgAAAA==.Borc:BAAALgAECgYJCgAAAA==.Borik:BAABLgAECn8gAAMLAAkJvRv1HQASAgALAAkJvRv1HQASAgAPAAUJdxhwNQAGAQAAAA==.Bosco:BAAALgAECgMJBQAAAA==.Botis:BAAALgAECgUJBAABLgAECgMJAwAUAAAAAA==.',
Br='Brighteye:BAAALgAECggJEgAAAA==.Brittany:BAAALgAECgYJDQAAAA==.Brothergrim:BAAALgADCgEJAQAAAA==.',
Bu='Buckme:BAACLgAFFH8FAAIIAAMJFwqKSgDWAAAIAAMJFwqKSgDWAAAuAAQKfxcAAggACAmpEqtBALMBAAgACAmpEqtBALMBAAAA.Buggers:BAAALgAECgIJAgAAAA==.Bungalator:BAAALgAECgQJBQAAAA==.Bunnygirl:BAABLgAFFH8IAAIJAAYJUxcBNgBZAQAJAAYJUxcBNgBZAQABLgAFFAcJGAAfABkeAA==.Bustedhoof:BAAALgADCgMJAwAAAA==.',
Ca='Caiphage:BAABLgAECn8aAAIFAAgJOxiUTADCAQAFAAgJOxiUTADCAQAAAA==.Caladelm:BAAALgAECgYJDwAAAA==.Caleria:BAAALgADCgYJBgAAAA==.Caralhan:BAABLgAECn8aAAIaAAcJpguZjwAkAQAaAAcJpguZjwAkAQAAAA==.Carlarae:BAABLgAECn8UAAIJAAYJOQRX3wC7AAAJAAYJOQRX3wC7AAAAAA==.Castelo:BAAALgAECgUJEgAAAA==.',
Ce='Cedra:BAACLgAFFH8NAAIJAAQJih1DMQBlAQAJAAQJih1DMQBlAQAuAAQKfxsAAgkACAnwIB4fAIoCAAkACAnwIB4fAIoCAAAA.Cegeo:BAABLgAECn8+AAITAAkJ/hj0AgBQAgATAAkJ/hj0AgBQAgAAAA==.',
Ch='Chaindk:BAAALgAECgQJCQAAAA==.Chaningtotem:BAAALgAECgIJAwAAAA==.Chapo:BAAALgADCgcJBwAAAA==.Cheepdeeps:BAABLgAECn9DAAMDAAkJkyOhBAD/AgADAAkJkyOhBAD/AgAMAAEJ0g6OYQAxAAAAAA==.Chocoworm:BAAALgADCgkJCwAAAA==.Chokez:BAAALgADCgMJAwAAAA==.Chudmaster:BAAALgAECgEJAgAAAA==.Chupathingyy:BAABLgAECn8jAAMQAAcJ3B8UKwAXAgAQAAcJ3B8UKwAXAgAXAAQJSBjyEgD9AAAAAA==.',
Ci='Ciennajewel:BAAALgAECggJDAAAAA==.Cirdle:BAABLgAECn8UAAMIAAcJ7wuMZwAxAQAIAAcJvgqMZwAxAQAHAAMJIwaaJQBoAAAAAA==.Cirona:BAABLgAECn8dAAINAAYJeyFOHQA6AgANAAYJeyFOHQA6AgAAAA==.',
Cl='Clausewitz:BAABLgAECn8UAAIZAAgJCwo+HwARAQAZAAgJCwo+HwARAQAAAA==.Cloroxx:BAAALgAECgYJBwAAAA==.',
Co='Cobalt:BAABLgAECn8gAAIQAAkJPhxPHABjAgAQAAkJPhxPHABjAgAAAA==.Coldsteel:BAAALgADCgEJAQABLgADCgcJBwAUAAAAAA==.Colphere:BAAALgADCgkJDgAAAA==.Coolkid:BAAALgAECgQJCQAAAA==.Corsic:BAAALgADCgUJBQAAAA==.',
Cr='Crazynlazy:BAABLgAECn8hAAIWAAgJ7gK9TADVAAAWAAgJ7gK9TADVAAAAAA==.Creamyweamy:BAABLgAECn8YAAIgAAcJFBWKIgCOAQAgAAcJFBWKIgCOAQAAAA==.Creemy:BAAALgADCgQJAQAAAA==.Critsmcgee:BAABLgAECn8hAAMJAAcJQA13kQA8AQAJAAcJQA13kQA8AQAhAAEJ6wGvIQAmAAAAAA==.Crucifixea:BAAALgAECgEJAgAAAA==.Cruxsader:BAAALgAECgQJBAAAAA==.Cruzmaster:BAABLgAECn8cAAMWAAkJPhTIGAD0AQAWAAkJPhTIGAD0AQAiAAQJqAsCHwDgAAAAAA==.Cryokai:BAAALgAECgIJAgAAAA==.Cryoluxis:BAAALgADCgUJBQAAAA==.Crystyl:BAABLgAECn8cAAIJAAgJHgV9ngAmAQAJAAgJHgV9ngAmAQAAAA==.',
Cu='Cuddly:BAABLgAFFH8JAAIjAAYJGRYUDgC6AQAjAAYJGRYUDgC6AQABLgAFFAgJIwAYAGAfAA==.Cupp:BAAALgAECgcJEgAAAA==.Cute:BAAALgAECgYJCAABLgAFFAgJHQAYAAUYAA==.',
Da='Daamass:BAAALgADCgMJAwAAAA==.Daddy:BAACLgAFFH8fAAIjAAcJ6yS1AQDgAgAjAAcJ6yS1AQDgAgAuAAQKf4wAAiMACQmzJgwAAAkEACMACQmzJgwAAAkEAAAA.Daddydonut:BAAALgADCgYJBgABLgAECgEJAQAUAAAAAA==.Daggonet:BAAALgAFFAEJAgAAAA==.Dalrin:BAABLgAECn8XAAMiAAYJ7A+uFQBiAQAiAAYJ7A+uFQBiAQAWAAQJzAfqZwCjAAAAAA==.Darayia:BAAALgAECgEJAgAAAA==.Darkcarnival:BAABLgAECn8nAAIQAAgJ0RtWLQAOAgAQAAgJ0RtWLQAOAgAAAA==.Darkdew:BAAALgADCgUJBQAAAA==.Darkimp:BAAALgAECgEJAQAAAA==.Darkknightx:BAABLgAECn8hAAIDAAkJiRdMLAADAgADAAkJiRdMLAADAgAAAA==.Darkphoenixx:BAAALgAECgYJCAAAAA==.Darthnyte:BAAALgAECgEJAQABLgAECgcJFQAVAJ8QAA==.Darthraider:BAAALgAECgcJEgAAAA==.Dasnotgood:BAABLgAECn8UAAMOAAcJuh2nCwDPAQAOAAYJUB+nCwDPAQAkAAUJARWOFAAoAQAAAA==.Datoneshammy:BAABLgAECn8VAAQWAAgJxwenPQARAQAWAAgJxwenPQARAQAVAAEJowGnqgAhAAAiAAEJeAH2NQAeAAAAAA==.Davrøs:BAAALgAECgIJBgAAAA==.',
Db='Dbagjohnsonn:BAAALgADCgIJAgAAAA==.Dbheals:BAAALgADCgMJAwAAAA==.',
De='Deeman:BAAALgAECgcJDQAAAA==.Deemon:BAABLgAECn8XAAIFAAkJwRNxLwDrAQAFAAkJwRNxLwDrAQAAAA==.Dehaka:BAAALgAECgMJBAAAAA==.Dejavu:BAAALgADCgEJAQAAAA==.Delathatha:BAAALgADCgIJAwAAAA==.Delphiarrow:BAAALgADCgIJAgAAAA==.Demiish:BAAALgAECgcJEgAAAA==.Dendreon:BAAALgADCgUJBQAAAA==.Denedin:BAAALgAECggJEQAAAA==.Denevien:BAABLgAECn8kAAMgAAgJ+xGbIQCVAQAgAAgJ+xGbIQCVAQAKAAYJ2AtCPAD6AAAAAA==.Denidan:BAAALgAECgIJAgAAAA==.Dertus:BAABLgAECn8eAAIRAAgJdxVUHwCiAQARAAgJdxVUHwCiAQAAAA==.Desdemona:BAABLgAECn8cAAIBAAgJyx+ABwA7AgABAAgJyx+ABwA7AgAAAA==.Dethiaris:BAAALgAECgEJAQAAAA==.Dethon:BAAALgADCgcJBwAAAA==.Devourment:BAABLgAFFH8FAAIIAAQJIAYtOwAAAQAIAAQJIAYtOwAAAQAAAA==.',
Di='Dianimal:BAABLgAECn8iAAIRAAgJqAc5NgAPAQARAAgJqAc5NgAPAQAAAA==.Dings:BAAALgADCggJFAAAAA==.Dinodan:BAAALgAECgEJAQABLgAECgYJEAAUAAAAAA==.Discnips:BAAALgAECgMJAwAAAA==.Distroya:BAABLgAECn8gAAMeAAgJwiL/CwCrAgAeAAcJoiL/CwCrAgACAAgJwiHcFwCXAgAAAA==.',
Dk='Dklel:BAACLgAFFH8QAAIaAAUJ0CHSLQBuAQAaAAUJ0CHSLQBuAQAuAAQKf0AAAhoACQl4JngEAEoDABoACQl4JngEAEoDAAAA.',
Do='Dojacat:BAAALgADCgkJEAAAAA==.Donuts:BAAALgAECgEJAQAAAA==.Doomace:BAABLgAECn8mAAMCAAkJCRZDRwDTAQACAAkJCRZDRwDTAQABAAQJfAEOPwBAAAAAAA==.Doomfeather:BAAALgAECgQJBgAAAA==.Dorigog:BAABLgAECn8oAAICAAkJIBLcWAClAQACAAkJIBLcWAClAQAAAA==.',
Dr='Dragee:BAAALgAECgEJBAABLgAECgkJFwAFAMETAA==.Dragon:BAAALgAECgkJEAAAAA==.Dragonpunch:BAABLgAECn8qAAIjAAkJ6xkuGAAeAgAjAAkJ6xkuGAAeAgAAAA==.Driftyshaman:BAABLgAECn8YAAIWAAcJxgm5QwD4AAAWAAcJxgm5QwD4AAAAAA==.Drusilia:BAAALgAECgQJBwAAAA==.Dræghoule:BAAALgAECggJEQAAAA==.',
Dt='Dtrouble:BAAALgADCgEJAQAAAA==.',
Dw='Dworflundgrn:BAABLgAECn8sAAIiAAkJoA0eDQCsAQAiAAkJoA0eDQCsAQAAAA==.',
Dy='Dyamï:BAABLgAECn8nAAIjAAgJ+Rn8FAA7AgAjAAgJ+Rn8FAA7AgAAAA==.Dydimus:BAAALgAECgYJDAAAAA==.Dysko:BAAALgAECgYJEgAAAA==.',
Eg='Eglosira:BAAALgAECgYJEwAAAA==.',
El='Elbuhero:BAAALgAFFAEJAQAAAA==.Eldiablo:BAAALgADCgIJAgAAAA==.Electric:BAABLgAECn8eAAIWAAYJHAxCSwDaAAAWAAYJHAxCSwDaAAAAAA==.Elementstone:BAAALgADCgQJAwAAAA==.Eleven:BAAALgAECgQJBQAAAA==.Ellä:BAAALgAECgYJCQAAAA==.Elrythe:BAACLgAFFH8KAAIIAAMJ9xKUQgDqAAAIAAMJ9xKUQgDqAAAuAAQKfzgAAggACQmGIo4FABwDAAgACQmGIo4FABwDAAAA.Elviric:BAAALgADCgMJAwAAAA==.',
Er='Eratar:BAAALgAECggJDAAAAA==.Erazan:BAAALgADCgEJAQAAAA==.Erzulie:BAAALgADCgUJBQAAAA==.',
Et='Ethepally:BAAALgADCgUJBQAAAA==.Ethepriest:BAAALgAECgMJBAAAAA==.',
Ev='Evilmorana:BAAALgAECgMJAwAAAA==.',
Fa='Fallyynn:BAAALgAECgYJEQAAAA==.Fatalii:BAAALgAECgEJAQABLgAECggJEgAUAAAAAA==.Fayelar:BAAALgAECgEJAQAAAA==.',
Fe='Fegyhr:BAABLgAECn8UAAINAAcJvhHCPACBAQANAAcJvhHCPACBAQAAAA==.Felebash:BAAALgAECgUJDwAAAA==.',
Fi='Fistdaddy:BAAALgAFFAEJAQAAAA==.',
Fl='Floofies:BAACLgAFFH8bAAIiAAYJZyEUAQDLAQAiAAYJZyEUAQDLAQAuAAQKfyMAAiIACQnjJbUDAO8CACIACQnjJbUDAO8CAAAA.Floofndoom:BAAALgAECgQJBAABLgAFFAYJGwAiAGchAA==.Floofyfu:BAAALgAECgYJCgABLgAFFAYJGwAiAGchAA==.',
Fr='Fredrickk:BAAALgAECgYJDAAAAA==.Fro:BAAALgADCgIJAgAAAA==.Fronobulax:BAAALgADCgYJBgAAAA==.Frostbane:BAAALgADCgEJAQAAAA==.',
Fu='Furpocalypse:BAAALgAECgQJBAAAAA==.Furrylight:BAAALgAECgQJBgABLgAFFAUJEgAVAGUYAA==.Furryphase:BAACLgAFFH8SAAIVAAUJZRheFgBwAQAVAAUJZRheFgBwAQAuAAQKfyQAAxUACQnxHAwNALUCABUACQnxHAwNALUCABYABAlyCUxqAHYAAAAA.Fuzzington:BAAALgAECgQJBgABLgAFFAYJGwAiAGchAA==.Fuzzydunlop:BAAALgAECgYJDgAAAA==.',
['Fï']='Fïddlestïcks:BAAALgAECgYJBgAAAA==.',
Ga='Gaawdshammit:BAAALgAECgYJCwAAAA==.Gallin:BAAALgAECgIJBAAAAA==.Gauldangit:BAAALgAECggJDAAAAA==.',
Ge='Geremiah:BAAALgAECgIJAgAAAA==.',
Gh='Ghosted:BAAALgAECgYJCgAAAA==.',
Gl='Glaur:BAABLgAECn8wAAIVAAkJth63DgC3AgAVAAkJth63DgC3AgAAAA==.',
Go='Goatjira:BAAALgAECgEJAQAAAA==.',
Gr='Grandmaster:BAAALgADCgEJAgAAAA==.Gransreaper:BAAALgAECgcJCwAAAA==.Grimgor:BAAALgADCgEJAQABLgAECgkJGgAlAGAgAA==.Gripisrdy:BAABLgAECn8nAAMaAAgJWR4sLgAmAgAaAAgJWR4sLgAmAgAmAAMJgRjbLADIAAAAAA==.',
Gu='Guldon:BAAALgAECgQJBAAAAA==.Gunslingr:BAABLgAECn8hAAMnAAkJkyLoAAD7AgAnAAkJkyLoAAD7AgAoAAEJugwNXgA7AAAAAA==.Gusmccrae:BAAALgAECgMJAwAAAA==.Guìdo:BAABLgAECn8VAAIVAAcJnxCNQwBxAQAVAAcJnxCNQwBxAQAAAA==.',
Gy='Gyluun:BAAALgADCgEJAQAAAA==.',
Ha='Haggrd:BAAALgAECggJEQAAAA==.Hairyjolene:BAABLgAECn8ZAAIIAAcJKQ/0aQBDAQAIAAcJKQ/0aQBDAQAAAA==.Halrix:BAAALgAECgYJBgAAAA==.Hammetrick:BAAALgADCgYJCQABLgAFFAIJAgAUAAAAAA==.Handsome:BAAALgAECgEJAgAAAA==.Hardware:BAAALgADCgcJCgAAAA==.Harry:BAABLgAECn8gAAIQAAcJGh+rJQB8AgAQAAcJGh+rJQB8AgAAAA==.Harthvader:BAAALgADCgcJCgAAAA==.',
He='Heartshot:BAAALgAECgYJBwAAAA==.Heelios:BAAALgADCgcJBwAAAA==.Helamad:BAAALgAECgYJEAAAAA==.Helmshammer:BAAALgAECgYJEQAAAA==.Hexwhisper:BAAALgAECgIJAgAAAA==.Heycarlos:BAAALgAECgYJEQAAAA==.',
Hi='Hikaridh:BAABLgAFFH8DAAIFAAEJvxNNeQBLAAAFAAEJvxNNeQBLAAABLgAFFAgJIgANAEscAA==.Hikarimonk:BAAALgAFFAIJAwABLgAFFAgJIgANAEscAA==.Hikaripala:BAAALgAECgEJAQABLgAFFAgJIgANAEscAA==.',
Ho='Holyarceus:BAAALgADCgQJBAABLgAECgQJBgAUAAAAAA==.Holyblimblam:BAAALgAECgYJEAAAAA==.Honeypieheal:BAAALgAECgEJAQAAAA==.Hosemachine:BAABLgAECn8nAAMaAAgJBB7VOAD8AQAaAAgJmB3VOAD8AQAmAAcJ2BWmHQBcAQAAAA==.Hotpants:BAABLgAECn8iAAIKAAYJNA0jOgAEAQAKAAYJNA0jOgAEAQAAAA==.',
Hu='Huez:BAAALgAECgIJAgAAAA==.Hulksmasher:BAAALgAECgQJCgAAAA==.Huntkiid:BAAALgADCgYJCwAAAA==.',
Hy='Hyman:BAAALgADCgMJAwAAAA==.',
['Hè']='Hèrifury:BAAALgAECgQJBQAAAA==.',
Ic='Icerunner:BAAALgADCgYJDwAAAA==.Icyjackets:BAABLgAECn8ZAAMaAAcJJw0oiAAyAQAaAAcJJw0oiAAyAQAmAAQJpAWJOwB3AAAAAA==.',
Id='Idamiani:BAAALgADCgMJAwAAAA==.Idouna:BAAALgADCgQJBAAAAA==.Idris:BAAALgAECgEJAQAAAA==.',
In='Inanis:BAAALgAECggJEgAAAA==.Inside:BAAALgAECgEJAgAAAA==.Invictive:BAAALgAECgMJAwAAAA==.',
Io='Iorune:BAAALgADCgYJBgAAAA==.',
Ja='Jadienne:BAABLgAECn8VAAIIAAkJlA8CQgCyAQAIAAkJlA8CQgCyAQAAAA==.Jameson:BAABLgAECn8oAAIDAAgJBReFHgDZAQADAAgJBReFHgDZAQAAAA==.Jamiel:BAAALgAECgEJAQAAAA==.Jasmind:BAABLgAECn8yAAMNAAgJHg7iPgB3AQANAAgJHg7iPgB3AQARAAEJLApdiAAnAAAAAA==.',
Je='Jeetli:BAAALgAECgQJBQABLgAECgYJFQAKACcVAA==.Jellydonut:BAAALgADCgYJCgABLgAECgEJAQAUAAAAAA==.Jelula:BAAALgADCgYJBgAAAA==.Jemmi:BAABLgAECn8UAAIWAAYJfg4oSwDbAAAWAAYJfg4oSwDbAAAAAA==.Jessicà:BAAALgAECgEJAQAAAA==.Jethro:BAAALgADCgUJBQAAAA==.',
Ji='Jimmy:BAAALgAECgEJAQAAAA==.Jinxz:BAAALgAECgYJEgAAAA==.Jinzaa:BAABLgAECn8aAAMVAAYJIhYRNgCrAQAVAAYJIhYRNgCrAQAWAAUJbxKQTgDPAAAAAA==.Jiwà:BAAALgAFFAMJAwABLgAFFAUJEgAKAPkKAA==.Jiwâ:BAACLgAFFH8SAAIKAAUJ+QooFgAcAQAKAAUJ+QooFgAcAQAuAAQKfzkAAgoACQlGHt4JAJECAAoACQlGHt4JAJECAAAA.',
Jo='Joesph:BAAALgAECgcJCgAAAA==.Jollibee:BAAALgAECgcJAQAAAA==.Jordinary:BAAALgAECgcJCgAAAA==.Joshjb:BAAALgAECgcJEQAAAA==.Joss:BAAALgAFFAEJAQAAAA==.',
Ka='Kadan:BAAALgAECgYJBgABLgAECgkJKwAFADEgAA==.Kahless:BAAALgADCgMJBgAAAA==.Kaibab:BAAALgADCgEJAQAAAA==.Kainani:BAAALgADCgQJBAAAAA==.Kakwaa:BAABLgAECn8fAAIDAAgJQAdkRQAKAQADAAgJQAdkRQAKAQAAAA==.Katoosh:BAAALgADCgUJBQAAAA==.Kattrin:BAAALgADCgkJFgAAAA==.Kavorkyan:BAAALgAECgcJBwAAAA==.',
Ke='Keladia:BAAALgAECgEJAQAAAA==.Kema:BAAALgADCgMJBgAAAA==.Keyadistor:BAABLgAECn8aAAMlAAkJYCA+DQBcAQAaAAYJ7hpDXQDbAQAlAAcJyB8+DQBcAQAAAA==.',
Kh='Khamûl:BAAALgAECgMJBAAAAA==.Khazabrew:BAABLgAECn85AAILAAkJmh1RBwCkAgALAAkJmh1RBwCkAgAAAA==.',
Ki='Kiamara:BAABLgAECn8UAAIQAAcJbAdylAAAAQAQAAcJbAdylAAAAQAAAA==.Kinderlin:BAABLgAECn8dAAICAAYJLBKRsAD+AAACAAYJLBKRsAD+AAAAAA==.Kipo:BAAALgAECgYJBgAAAA==.Kiralana:BAAALgAECgEJAQAAAA==.Kirb:BAAALgAECgMJAwAAAA==.',
Ko='Kookeez:BAAALgAECgYJCAAAAA==.Kookies:BAAALgAECgcJDwAAAA==.',
Kr='Krelix:BAABLgAECn8XAAINAAcJbhYfMgC2AQANAAcJbhYfMgC2AQAAAA==.Kriest:BAAALgADCgQJBAAAAA==.',
Ku='Kusanagï:BAAALgADCgMJAwAAAA==.',
La='Lancaban:BAAALgAECgYJDgAAAQ==.',
Le='Legolost:BAABLgAECn8YAAQdAAgJfRaSDwDiAQAdAAYJNhmSDwDiAQAcAAMJfRSEQgDYAAAfAAQJlQqNMwDSAAAAAA==.Lesbohorde:BAAALgADCgEJAQAAAA==.',
Li='Light:BAAALgAECgUJBQAAAA==.Lightofevil:BAAALgADCgUJBQAAAA==.Limpwurt:BAAALgAECgIJBAAAAA==.Linh:BAAALgADCgMJAwAAAA==.',
Lo='Loadedtater:BAABLgAECn85AAQGAAkJpyUvAQBGAwAGAAkJviQvAQBGAwAIAAgJkCZMCQDtAgAHAAUJ3CX2JgDyAQAAAA==.Locked:BAAALgAECgUJBQAAAA==.Lockedin:BAAALgAECgMJAwAAAA==.Loralynn:BAABLgAFFH8HAAINAAMJ5gZXOwCpAAANAAMJ5gZXOwCpAAAAAA==.Lorianne:BAACLgAFFH8GAAIVAAIJ+hEOTQCCAAAVAAIJ+hEOTQCCAAAuAAQKfygAAxUACAmvGGQpAOkBABUACAmvGGQpAOkBABYABQmxC7tWAOoAAAEuAAUUAwkHAA0A5gYA.Lorri:BAAALgADCgQJBQABLgAFFAMJBwANAOYGAA==.',
Lu='Lucianas:BAAALgAECgcJDwAAAA==.Lunchböx:BAAALgAECgMJBgAAAA==.Lunico:BAAALgADCgEJAgAAAA==.Luthoros:BAAALgADCggJCwAAAA==.',
Ly='Lysi:BAABLgAECn8ZAAIIAAcJzRSYSwCTAQAIAAcJzRSYSwCTAQAAAA==.Lythalia:BAAALgADCgMJAwAAAA==.',
Ma='Macsena:BAAALgADCgEJAgAAAA==.Madaea:BAABLgAECn8zAAIjAAkJqh9SCADoAgAjAAkJqh9SCADoAgAAAA==.Madrashai:BAAALgAECgUJCgAAAA==.Magepuppy:BAABLgAECn83AAIJAAkJBhsyIACFAgAJAAkJBhsyIACFAgABLgAFFAQJDwAGAB8bAA==.Mahai:BAAALgADCgcJBAAAAA==.Mak:BAABLgAECn8UAAIgAAcJURuOFwDtAQAgAAcJURuOFwDtAQABLgAECggJGAAIAFMdAA==.Makavali:BAAALgAECgQJBQABLgAECggJGAAIAFMdAA==.Makdaddy:BAABLgAECn8YAAIIAAgJUx3CHgBEAgAIAAgJUx3CHgBEAgAAAA==.Malzeth:BAAALgAECgEJAQAAAA==.Marrilyn:BAAALgAFFAEJAQABLgAFFAcJCgAQAMQaAA==.Marrina:BAAALgADCgMJBgAAAA==.Matagi:BAABLgAECn8hAAIIAAkJBx3XEwCKAgAIAAkJBx3XEwCKAgAAAA==.Mate:BAAALgADCgkJHQAAAA==.Maw:BAAALgAECgMJAwAAAA==.',
Me='Mechamage:BAAALgAECgEJAgAAAA==.Meeseks:BAAALgAECgcJBwAAAA==.Melbeast:BAABLgAECn8WAAIIAAYJixv4ZgBKAQAIAAYJixv4ZgBKAQAAAA==.Melorea:BAAALgAECgMJBQAAAA==.Merdin:BAABLgAECn8cAAMJAAkJTxDGSwDfAQAJAAkJNhDGSwDfAQAhAAEJpwwYIAAvAAAAAA==.Methmartion:BAABLgAECn8ZAAMTAAcJCglOFgDRAAATAAcJCglOFgDRAAAQAAEJgQPzKAEpAAAAAA==.Metricdotem:BAAALgADCgEJAQAAAA==.Metricgg:BAAALgADCgEJAQAAAA==.',
Mi='Mightletudie:BAAALgADCgkJCQAAAA==.Mikewai:BAABLgAECn8XAAIFAAgJgQ9uUgCtAQAFAAgJgQ9uUgCtAQAAAA==.Miloughah:BAAALgAECgkJBQAAAA==.Misaki:BAAALgADCgMJAwAAAA==.Mish:BAAALgAECgYJBgAAAA==.Missiah:BAABLgAECn8zAAIBAAkJNwTIIADhAAABAAkJNwTIIADhAAAAAA==.Mitzalia:BAAALgAECgIJAgAAAA==.Mitzki:BAAALgADCgUJBQAAAA==.',
Mo='Moirane:BAAALgAECgIJBAAAAA==.Moistwhispa:BAAALgAECgIJAgABLgAECgkJHQARAO4WAA==.Molfise:BAABLgAECn8fAAMLAAYJOhUSNAATAQALAAYJgRISNAATAQAPAAQJpRHfRwD1AAAAAA==.Monastary:BAAALgADCgUJCgAAAA==.Mongfirrmel:BAAALgADCgUJBgAAAA==.Moonfell:BAABLgAECn89AAIgAAkJNR69BQAAAwAgAAkJNR69BQAAAwAAAA==.Moonlight:BAAALgAECgQJBAAAAA==.Moonlilly:BAAALgAECgYJEwAAAA==.Mopp:BAAALgAECgQJBQAAAA==.Morganthe:BAAALgAECgQJBAAAAA==.Morin:BAAALgAECgEJAQAAAA==.',
Mu='Musubi:BAAALgADCgEJAQABLgAECgkJEAAUAAAAAA==.',
Mx='Mxtemlen:BAAALgAECggJCgABLgAECggJHwAeADkNAA==.',
My='Mylilhunter:BAAALgAECgYJDwAAAA==.Mysticalmoo:BAAALgADCggJEAAAAA==.Mysticrainne:BAAALgADCgYJBgAAAA==.Mythdar:BAAALgAECgcJDgABLgAECgkJKgAjAOsZAA==.Myttus:BAAALgADCgMJAwABLgAECgYJFAACAD4IAA==.',
['Mê']='Mêrlin:BAABLgAECn8dAAIJAAgJBgZlmwArAQAJAAgJBgZlmwArAQAAAA==.',
Na='Nachtelf:BAABLgAECn9EAAIIAAkJiiEGCAD7AgAIAAkJiiEGCAD7AgAAAA==.Nadeshiko:BAAALgADCgYJBgAAAA==.Nakamei:BAAALgAECgUJCgAAAA==.Nakirah:BAAALgAECgEJAQAAAA==.Nannysham:BAAALgAECggJDgAAAA==.Naomí:BAABLgAECn8cAAIQAAYJ0wymkgAzAQAQAAYJ0wymkgAzAQAAAA==.Natadawn:BAAALgAECgQJBAAAAA==.Natalone:BAABLgAECn89AAIJAAkJcyMyCAAoAwAJAAkJcyMyCAAoAwAAAA==.Natherel:BAABLgAECn8VAAMMAAcJ1gRzNADIAAAMAAcJ1gRzNADIAAADAAUJ5gPnagCCAAAAAA==.Natrhatr:BAAALgADCgYJCwAAAA==.Naughty:BAACLgAFFH8FAAMcAAUJywndNwC3AAAcAAQJigndNwC3AAAfAAEJtAC9JwAwAAAuAAQKfxsAAx8ACAkfFC4NAN0BAB8ABwkCFi4NAN0BABwABwm5GAMiAKoBAAEuAAUUCAkdABgABRgA.',
Ne='Newander:BAABLgAECn8zAAINAAkJaRMGKADxAQANAAkJaRMGKADxAQAAAA==.Nezat:BAAALgADCgEJAQAAAA==.',
Ni='Nightofmares:BAAALgAECgcJDAAAAA==.Nirra:BAAALgAECgMJAwAAAA==.',
No='Nonphatmilk:BAAALgAECgQJCQAAAA==.Noots:BAAALgADCgcJBwAAAA==.Notoriginal:BAABLgAECn8tAAMaAAkJmxI4QwDaAQAaAAkJmxI4QwDaAQAmAAEJGxJ6RQAyAAAAAA==.',
Nu='Nuked:BAABLgAECn8dAAIJAAgJCR88QAACAgAJAAgJCR88QAACAgAAAA==.',
Og='Ograskygazer:BAABLgAECn8VAAINAAcJdAWBbgDLAAANAAcJdAWBbgDLAAAAAA==.',
Om='Omee:BAABLgAECn8eAAMEAAkJ2xZmEgDSAQAEAAgJkxlmEgDSAQAFAAYJ5goofAADAQAAAA==.Omy:BAABLgAECn8oAAIJAAcJcgwNiQBLAQAJAAcJcgwNiQBLAQAAAA==.',
Op='Ophela:BAAALgAECgMJBAAAAA==.',
Or='Orakio:BAAALgAFFAEJAgABLgAFFAQJCQAJAAIPAA==.Oralena:BAABLgAECn8ZAAIIAAcJvAV0iwD6AAAIAAcJvAV0iwD6AAAAAA==.Orioncheats:BAABLgAECn8zAAIaAAkJfxqtLAAtAgAaAAkJfxqtLAAtAgAAAA==.',
Ov='Overpwerd:BAAALgADCgEJAQAAAA==.',
Ow='Owo:BAAALgADCgUJBQABLgAECgMJAwAUAAAAAA==.',
Ox='Oxygën:BAAALgAECgUJDgAAAA==.',
Pa='Paladingbat:BAACLgAFFH8FAAIeAAMJDB0yHgADAQAeAAMJDB0yHgADAQAuAAQKfxwAAh4ACAnfIsMFABYDAB4ACAnfIsMFABYDAAAA.Pallygoboom:BAAALgADCgUJBQABLgAECgYJEQAUAAAAAA==.Palomita:BAAALgADCgMJBgAAAA==.Paspir:BAAALgAECgMJAwAAAA==.Paull:BAAALgAECgYJEQAAAA==.',
Pe='Ped:BAABLgAECn82AAMPAAkJzB22CACXAgAPAAkJzB22CACXAgAjAAEJ2AHbdgAXAAAAAA==.Peon:BAAALgAECgYJDgAAAA==.',
Ph='Pharune:BAABLgAECn8nAAIkAAgJYBG7FwBXAQAkAAgJYBG7FwBXAQAAAA==.Philosofist:BAAALgAECgUJDAAAAA==.Phredrick:BAABLgAECn8bAAIJAAcJGRVQcAB/AQAJAAcJGRVQcAB/AQAAAA==.',
Pi='Pickleboa:BAAALgAECgUJDgABLgAFFAMJAwAUAAAAAA==.Picklebob:BAAALgAECggJBwABLgAFFAMJAwAUAAAAAA==.Pickleboe:BAAALgAECgUJBQABLgAFFAMJAwAUAAAAAA==.Picklebosh:BAAALgAFFAMJAwAAAA==.Piemanninty:BAAALgADCgcJCQAAAA==.Pirellipaws:BAAALgADCgkJEAAAAA==.',
Pl='Plandemic:BAAALgAECgQJBwAAAA==.Pluto:BAAALgADCgEJAQAAAA==.',
Po='Pockithealz:BAAALgAECgMJBAABLgAECggJEgAUAAAAAA==.Ponky:BAABLgAECn8cAAIKAAkJKhG0IQCTAQAKAAkJKhG0IQCTAQAAAA==.Porfir:BAAALgADCgUJBQAAAA==.Porrigar:BAAALgAECgEJAgAAAA==.Pounce:BAAALgAECgcJCwAAAA==.Pounces:BAABLgAFFH8IAAINAAMJghRDMgDKAAANAAMJghRDMgDKAAABLgAFFAgJIwAYAGAfAA==.',
Pr='Precious:BAACLgAFFH8WAAIYAAcJCRKaCQAkAgAYAAcJCRKaCQAkAgAuAAQKf0EABBgACQkjJJcCAHMDABgACQkjJJcCAHMDACAABglwDxs2AGQBAAoABAkvEwpKALsAAAEuAAUUCAkdABgABRgA.',
['Pä']='Pängari:BAAALgAECgEJAQABLgAECgkJKAAZAPELAA==.',
Qu='Quattro:BAABLgAECn8WAAIdAAkJXgvwDQARAQAdAAkJXgvwDQARAQAAAA==.Quell:BAAALgADCgcJBwAAAA==.',
Ra='Racecar:BAABLgAECn8uAAMDAAgJSRscIADNAQADAAgJLBscIADNAQAMAAEJihVOXAA7AAAAAA==.Rageoverwelm:BAAALgADCgEJAQAAAA==.Raivyn:BAABLgAECn8XAAIPAAgJqBcMFwDWAQAPAAgJqBcMFwDWAQABLgAECgkJMwANAGkTAA==.Rajantu:BAAALgADCgYJCgAAAA==.Ratava:BAAALgAECgMJAwAAAA==.Raylaira:BAABLgAECn8cAAIgAAgJZwvfKQBWAQAgAAgJZwvfKQBWAQAAAA==.',
Re='Rehum:BAABLgAECn8UAAICAAYJPghIzgDTAAACAAYJPghIzgDTAAAAAA==.Remagtrepxe:BAAALgADCgMJBQABLgAECgcJGAAWAMYJAA==.Remodify:BAAALgAECgIJAwAAAA==.Rengery:BAAALgAECgcJBwAAAA==.Reposado:BAAALgAECgUJCQAAAA==.Retbull:BAAALgADCgQJBwAAAA==.Retrall:BAAALgAECgcJCgAAAA==.Revelare:BAABLgAECn8kAAMiAAgJug38EwA9AQAiAAcJXQ/8EwA9AQAVAAUJzwXIdgC2AAAAAA==.Revèndreth:BAAALgAECgEJAQAAAA==.Rexbi:BAABLgAECn8bAAIFAAcJGhd+PQD+AQAFAAcJGhd+PQD+AQAAAA==.Rexbie:BAAALgAECgMJBQAAAA==.',
Rh='Rhylee:BAAALgAECgIJAgAAAA==.Rhytchus:BAAALgAECgQJCQAAAA==.',
Ri='Rianne:BAABLgAECn85AAIKAAkJwRF3GADgAQAKAAkJwRF3GADgAQAAAA==.Risenbooty:BAAALgADCgMJAwAAAA==.Risk:BAAALgADCgUJBQAAAA==.',
Ro='Robberttrest:BAAALgAECgYJEwAAAA==.Rockyevoker:BAAALgADCgQJBAAAAA==.Rockyhunterr:BAABLgAECn8dAAMaAAkJERv0NAAKAgAaAAkJ5xr0NAAKAgAlAAYJrhWxCABaAQAAAA==.Rolemartyr:BAAALgAECgYJDQAAAA==.Rooth:BAABLgAECn8bAAIdAAYJSRB8DQAZAQAdAAYJSRB8DQAZAQAAAA==.Roryn:BAACLgAFFH8FAAICAAIJQBHdbACaAAACAAIJQBHdbACaAAAuAAQKf0cAAgIACQm0Ja8CAGIDAAIACQm0Ja8CAGIDAAAA.Rowdan:BAAALgAECgEJAQAAAA==.Rozimi:BAAALgAECgEJAQAAAA==.',
Ru='Rubadubchub:BAAALgADCgYJCQAAAA==.Rubï:BAAALgAFFAIJAgAAAA==.Rugi:BAAALgAECgEJAQABLgAFFAcJKQANAB0kAA==.Rugiia:BAACLgAFFH8pAAINAAcJHSSxAQDsAgANAAcJHSSxAQDsAgAuAAQKfz4AAw0ACQmWJkEAAOMDAA0ACQmWJkEAAOMDAA4ABAlfJeAVADUBAAAA.Rugiian:BAABLgAFFH8FAAIjAAMJ+xIfJgDLAAAjAAMJ+xIfJgDLAAABLgAFFAcJKQANAB0kAA==.Rumint:BAAALgADCgEJAQAAAA==.',
Ry='Ryleth:BAAALgADCgYJBgAAAA==.Rylonk:BAABLgAECn8ZAAIQAAgJngkebABPAQAQAAgJngkebABPAQAAAA==.Ryuka:BAABLgAECn8aAAIkAAkJIAlrIAAKAQAkAAkJIAlrIAAKAQAAAA==.',
Sa='Sabeli:BAAALgAECggJCAAAAA==.Sabindeus:BAAALgAECgkJAQAAAA==.Samyria:BAAALgAECgYJDQAAAA==.Sandwich:BAAALgAECgUJBwAAAA==.Sanguinius:BAAALgADCgMJAwAAAA==.Satyaru:BAABLgAECn8lAAQjAAgJiQwwNwBHAQAjAAgJiQwwNwBHAQAPAAcJlg7HMAAeAQALAAEJgAH5mQAYAAAAAA==.Saucy:BAAALgAECgYJDwAAAA==.',
Sc='Scarletnight:BAAALgADCgMJAwABLgADCgcJCwAUAAAAAA==.Scrubsauce:BAAALgAECgEJBAAAAA==.',
Se='Sedona:BAAALgADCgYJBwAAAA==.Selarra:BAABLgAECn8jAAIgAAgJ8BMLIAChAQAgAAgJ8BMLIAChAQAAAA==.Seric:BAABLgAECn8oAAMZAAkJ8QtEFwBjAQAZAAkJ8QtEFwBjAQADAAQJugQ3cwBmAAAAAA==.Sesethi:BAAALgAECgMJAwABLgAECgcJGgAXAM0bAA==.',
Sh='Shadowdancèr:BAABLgAECn8WAAMKAAYJvhSRLwA6AQAKAAYJvhSRLwA6AQAYAAMJ+RENRQC5AAAAAA==.Shadowlocke:BAAALgADCggJDwAAAA==.Shadowvein:BAAALgADCgEJAQABLgAECgcJGgAfAL8QAA==.Shadowyisis:BAAALgAECgMJAwAAAA==.Shammitjanet:BAAALgAECgUJBQAAAA==.Shamquen:BAAALgAECgkJCwAAAA==.Shanair:BAACLgAFFH8PAAIGAAQJHxshCgBbAQAGAAQJHxshCgBbAQAuAAQKfz4AAwYACQmkI68BACkDAAYACQmMI68BACkDAAcABwnWHTkbAE8CAAAA.Shirizani:BAAALgAECgQJBAABLgAFFAQJEQABAKsIAA==.Shrimpy:BAAALgAECgQJCAAAAA==.Shuaiguy:BAAALgAECgEJBQAAAA==.',
Si='Sibala:BAAALgADCgQJBAAAAA==.Sinarel:BAAALgAECgQJBQAAAA==.',
Sk='Skimmilk:BAAALgAECgMJBAABLgAFFAUJDwAZAEoYAA==.Skybox:BAAALgADCgcJBgAAAA==.Skyboxer:BAAALgAECgQJDAAAAA==.Skye:BAABLgAECn8XAAMYAAYJvhFAMAAeAQAYAAUJiBBAMAAeAQAgAAUJfQ/XSQCTAAAAAA==.',
Sl='Slambamwhoo:BAAALgAECgkJDgAAAA==.Slingspell:BAAALgAECgMJBQAAAA==.Slippin:BAAALgADCggJFQAAAA==.Slythenole:BAAALgAECgQJBAAAAA==.',
Sm='Smartfood:BAAALgADCgMJAwAAAA==.Smoochybooty:BAABLgAECn8uAAIJAAkJrhH6QQD9AQAJAAkJrhH6QQD9AQAAAA==.',
Sn='Sneakydeaky:BAAALgAECggJCAAAAA==.',
So='Soggyiguana:BAAALgADCgUJBgAAAA==.Solnar:BAABLgAECn8fAAQeAAgJOQ0+MAB0AQAeAAgJOQ0+MAB0AQABAAYJQBMKJADHAAACAAEJYBZhTAE6AAAAAA==.',
Sp='Sparkee:BAAALgADCgcJCwAAAA==.Spinandkick:BAAALgAECgEJAQAAAA==.Spiritality:BAAALgADCgMJAwABLgAECgQJBAAUAAAAAA==.Splashdaddy:BAACLgAFFH8JAAIVAAMJFiUIHgA+AQAVAAMJFiUIHgA+AQAuAAQKfyQAAhUACQlGJA4FAEADABUACQlGJA4FAEADAAEuAAUUAQkBABQAAAAA.Spudspinner:BAAALgAECgEJAQAAAA==.',
Sq='Squog:BAAALgADCgIJAgAAAA==.',
Sr='Srìracha:BAAALgAECgUJCgAAAA==.',
St='Staks:BAAALgAECgEJAQAAAA==.Starii:BAABLgAECn8cAAIVAAgJqwa+WgAbAQAVAAgJqwa+WgAbAQAAAA==.Stas:BAAALgADCgYJCwAAAA==.Stevelock:BAAALgADCggJDgAAAA==.Storagetec:BAAALgADCgkJEQAAAA==.Striga:BAAALgADCgQJBAAAAA==.',
Su='Suffer:BAAALgAECgQJCAAAAA==.Sunless:BAAALgAECgEJAQAAAA==.',
Sy='Sygma:BAAALgADCgMJAwAAAA==.Sylvancura:BAAALgAECgIJAwAAAA==.Sylvenna:BAAALgAECgYJCgAAAA==.Synestra:BAABLgAECn8gAAIkAAYJPCL3DADcAQAkAAYJPCL3DADcAQAAAA==.',
Ta='Taea:BAAALgAECgEJAQABLgAECgYJHQANAHshAA==.Taeus:BAACLgAFFH8JAAIJAAQJAg/dTgAuAQAJAAQJAg/dTgAuAQAuAAQKfxcAAgkACAkVGOBeAB4CAAkACAkVGOBeAB4CAAAA.Taintedkoma:BAAALgAECgcJCAABLgAECgcJGQATAAoJAA==.Taladiir:BAAALgAECgQJCAAAAA==.Talasa:BAAALgADCgMJAwAAAA==.Taliaz:BAAALgADCgIJAgAAAA==.Tapp:BAAALgADCgcJBwAAAA==.Tastycles:BAAALgAECgYJDQAAAA==.Taterstorm:BAAALgAECgMJAwAAAA==.Taurenator:BAABLgAECn8jAAIZAAkJoiEKCAClAgAZAAkJoiEKCAClAgAAAA==.Tayblr:BAABLgAECn8fAAIIAAYJAAKSwACFAAAIAAYJAAKSwACFAAAAAA==.',
Te='Telese:BAAALgADCgEJAQAAAA==.Telkhar:BAAALgAFFAEJAQAAAA==.Temajin:BAABLgAECn8UAAMeAAYJUApZRAAJAQAeAAYJUApZRAAJAQACAAIJvwvCdAEsAAAAAA==.Temple:BAAALgADCgQJBgAAAA==.Teomcdoul:BAAALgADCgUJBQAAAA==.Teranidas:BAAALgADCgYJCgAAAA==.Teratrendera:BAABLgAECn8XAAMfAAcJkCFgBwBlAgAfAAcJkCFgBwBlAgAcAAEJCg+NZAAtAAAAAA==.Teron:BAAALgAECgEJAQAAAA==.Terrathkar:BAAALgAECgIJAgAAAA==.',
Th='Thavis:BAABLgAECn8UAAMQAAcJEA9VhQAdAQAQAAcJQgxVhQAdAQATAAEJChbyMABCAAAAAA==.Themyscira:BAAALgAECgIJAgAAAA==.Theonorf:BAABLgAECn87AAIIAAgJpSFRDgC5AgAIAAgJpSFRDgC5AgAAAA==.Thetimelord:BAAALgAECgUJBgAAAA==.Thewarrior:BAAALgAECgcJDgAAAA==.Thypriest:BAAALgAECgYJEwAAAA==.',
Ti='Tick:BAAALgAECgEJAQAAAA==.Tidus:BAAALgAECgQJBAAAAA==.Tik:BAAALgADCgEJAQAAAA==.Tilted:BAABLgAECn8lAAICAAgJVhXNSwD/AQACAAgJVhXNSwD/AQAAAA==.Tirus:BAAALgADCgQJBQAAAA==.',
To='Tobi:BAAALgADCgUJBQAAAA==.Toblakài:BAAALgAECgYJBQAAAA==.Torrey:BAABLgAECn8xAAIbAAkJYBC+CgCLAQAbAAkJYBC+CgCLAQAAAA==.',
Tr='Tradd:BAABLgAECn8hAAIYAAkJix48BwDkAgAYAAkJix48BwDkAgAAAA==.Trigg:BAAALgAECgUJBQABLgAECgkJKwAFADEgAA==.Tristyana:BAABLgAECn9AAAIIAAkJYh1dEQCeAgAIAAkJYh1dEQCeAgAAAA==.Trossard:BAAALgADCgEJAQAAAA==.',
Ts='Tsunâde:BAABLgAECn8/AAQPAAkJZCUMAgBAAwAPAAkJZCUMAgBAAwAjAAcJgxZEIwCZAQALAAcJhBF/JwBYAQAAAA==.',
Tw='Twinkletoe:BAAALgAECgQJBAABLgAECgkJPwAPAGQlAA==.',
Ty='Tylurien:BAABLgAECn8nAAIeAAgJoiJyCADgAgAeAAgJoiJyCADgAgAAAA==.',
['Të']='Tëmpest:BAAALgAECgYJBwAAAA==.',
Ul='Ulangi:BAAALgADCgMJBQAAAA==.',
Un='Untouchablez:BAAALgADCgYJBgAAAA==.',
Ur='Urbanprey:BAABLgAECn8jAAITAAgJNgoXDwAkAQATAAgJNgoXDwAkAQAAAA==.Urimar:BAAALgADCgkJDQAAAA==.',
Va='Valkoinen:BAABLgAECn8+AAIfAAYJJA82GQAfAQAfAAYJJA82GQAfAQAAAA==.Valora:BAABLgAECn9DAAQYAAkJZB3vCwCHAgAYAAkJ8RrvCwCHAgAgAAcJYx3RGwDEAQAKAAIJoA+CWAB6AAAAAA==.Valoria:BAAALgAECgQJDQAAAA==.Vanille:BAABLgAECn8VAAINAAcJNAavcwC9AAANAAcJNAavcwC9AAAAAA==.Vargen:BAABLgAECn8ZAAIoAAcJmRf4HgB1AQAoAAcJmRf4HgB1AQAAAA==.Varonika:BAAALgAECgUJEgAAAA==.Vayla:BAABLgAECn8zAAIZAAkJ3ht6BgCDAgAZAAkJ3ht6BgCDAgAAAA==.',
Ve='Vee:BAAALgAECgEJAwABLgAECgkJFwAFAMETAA==.Veld:BAAALgAECggJBgAAAA==.Velura:BAAALgAECgYJBgAAAA==.Vengmachine:BAAALgADCgcJCwABLgAECggJJwAaAAQeAA==.Venøm:BAAALgADCgUJBQAAAA==.Vessimyre:BAAALgAECgIJBQAAAA==.',
Vi='Vicunaward:BAAALgAECgUJBQAAAA==.Violet:BAABLgAECn8kAAICAAYJ1QsqtAD5AAACAAYJ1QsqtAD5AAAAAA==.',
Vo='Voidofdeath:BAAALgAECgUJDAAAAA==.',
Vr='Vryn:BAAALgADCgEJAQAAAA==.',
Vu='Vula:BAABLgAECn84AAINAAkJQAOgYAD2AAANAAkJQAOgYAD2AAAAAA==.',
['Vè']='Vèngeance:BAAALgAECgIJAgAAAA==.',
Wa='Wagubagu:BAAALgAECgQJBAAAAA==.Wamdus:BAACLgAFFH8GAAIJAAMJjwyoawDiAAAJAAMJjwyoawDiAAAuAAQKfyoAAgkACQk+H6IWALgCAAkACQk+H6IWALgCAAAA.Wargrimm:BAABLgAECn8mAAIWAAgJNB6dEABJAgAWAAgJNB6dEABJAgAAAA==.Warriovix:BAAALgAECgUJDAAAAA==.Warwizard:BAACLgAFFH8UAAIeAAQJISZODQCnAQAeAAQJISZODQCnAQAuAAQKf1YAAx4ACQmfJhIAAPgDAB4ACQmfJhIAAPgDAAIABwkJIBQxABwCAAAA.',
We='Webin:BAAALgAECgEJBgAAAA==.',
Wh='Whatshisface:BAABLgAECn8bAAIPAAgJRR+EEQBtAgAPAAgJRR+EEQBtAgAAAA==.Whiisp:BAAALgAECgYJCAABLgAECgkJHQARAO4WAA==.Whiisper:BAAALgAECgYJBgABLgAECgkJHQARAO4WAA==.Whispaknight:BAAALgAECgUJBgABLgAECgkJHQARAO4WAA==.Whisperwiind:BAAALgAECgMJAwABLgAECgkJHQARAO4WAA==.Whisperz:BAAALgAECgIJAgABLgAECgkJHQARAO4WAA==.Whizpa:BAABLgAECn8dAAIRAAkJ7haCEgAdAgARAAkJ7haCEgAdAgAAAA==.Whizper:BAAALgAECgEJAQABLgAECgkJHQARAO4WAA==.',
Wi='Wickerchickn:BAABLgAECn8YAAIkAAgJfBQWFgBoAQAkAAgJfBQWFgBoAQAAAA==.Wiisper:BAAALgADCgYJBgABLgAECgkJHQARAO4WAA==.Wilshammy:BAAALgADCgkJEAAAAA==.Wispy:BAAALgAECgYJDAAAAA==.Wizzelyfink:BAAALgAECgYJBgAAAA==.Wizzy:BAAALgAECgQJDQAAAA==.',
Wo='Wonkyponky:BAAALgAECgEJAQAAAA==.',
Wr='Wrathbarrage:BAAALgAECgkJEwAAAA==.Wrathbourne:BAAALgAECgYJDQABLgAECgkJEwAUAAAAAA==.Wrathchoi:BAAALgAECgYJCwAAAA==.Wrathstorm:BAAALgAECgEJAwABLgAECgkJEwAUAAAAAA==.',
Xb='Xbonez:BAAALgAECgQJBgAAAA==.',
Xe='Xenather:BAAALgAECgMJAwAAAA==.Xerilynn:BAAALgAECgUJDAAAAA==.',
Xi='Xiangfei:BAABLgAECn8iAAMIAAgJRB6SMwDhAQAIAAgJhBySMwDhAQAGAAYJhR/zGgCqAQAAAA==.Xilo:BAAALgAECgkJEAAAAA==.',
Xy='Xyloto:BAAALgAECgEJAQABLgAECgYJDQAUAAAAAA==.',
['Xè']='Xèrlyn:BAAALgAECgMJBQAAAA==.',
Ya='Yazlura:BAAALgADCgMJAwAAAA==.',
Ye='Yesimamonk:BAAALgADCgEJAQAAAA==.Yezgraine:BAAALgAECgcJCAAAAA==.',
Yo='Youmightlive:BAAALgAECgUJEAAAAA==.',
Yz='Yzaak:BAAALgAECgEJAQAAAA==.',
Za='Zahona:BAAALgADCgYJCQAAAA==.Zaknefein:BAAALgADCgMJAwAAAA==.',
Ze='Zeddiccus:BAABLgAECn8YAAIJAAkJhBkeLgBFAgAJAAkJhBkeLgBFAgAAAA==.',
Zi='Ziden:BAAALgAECgYJBgAAAA==.Zidon:BAAALgAECgIJAwAAAA==.Zigral:BAAALgADCgUJBQABLgAECgQJDQAUAAAAAA==.Zirfireballs:BAAALgAECgIJAgAAAA==.Zixgal:BAAALgAECgQJDQAAAA==.',
Zo='Zonzmik:BAAALgADCgcJGAAAAA==.Zorvoth:BAAALgAECgcJBwAAAA==.',
Zu='Zurazaee:BAABLgAECn8ZAAIgAAcJZBR4IQCWAQAgAAcJZBR4IQCWAQAAAA==.',
['År']='Årtêmis:BAAALgAECggJEAAAAA==.',
['Él']='Élle:BAAALgAECgMJBQAAAA==.',
['Ér']='Éric:BAABLgAECn9DAAIkAAkJ7hmdBgBiAgAkAAkJ7hmdBgBiAgAAAA==.',
['Ïr']='Ïridescent:BAAALgAECgQJBAAAAA==.',
['Ði']='Ðiabloist:BAAALgADCgMJAwAAAA==.',
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
