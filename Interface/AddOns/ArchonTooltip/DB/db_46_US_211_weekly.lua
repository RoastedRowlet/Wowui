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
local provider = {region='US',realm='Terenas',name='US',type='weekly',zone=46,date='2026-05-31',data={Ac='Achooe:BAABLgAECn8tAAMBAAkJsQqRGQA1AQABAAkJsQqRGQA1AQACAAEJJgK9pQEYAAAAAA==.',
Ad='Ado:BAAALgAECgEJAQAAAA==.Adrel:BAAALgAECgQJBgAAAA==.Adversity:BAABLgAECn8jAAIDAAgJNiQwCAAnAwADAAgJNiQwCAAnAwAAAA==.',
Ae='Aegeus:BAABLgAECn8WAAMEAAgJCxw5DQCPAgAEAAgJ3Bo5DQCPAgAFAAYJGhHYiQAQAQAAAA==.Aelchad:BAAALgAECgMJAwAAAA==.Aevintz:BAABLgAECn87AAQGAAkJ5hpEBwCfAgAGAAkJ5hpEBwCfAgAHAAUJtQbFWwDUAAAIAAUJBAbOlwCmAAAAAA==.',
Af='Afterburnner:BAAALgAECgMJAwAAAA==.',
Ag='Agatha:BAABLgAECn8oAAIJAAkJQBD4VwC+AQAJAAkJQBD4VwC+AQAAAA==.Agathorz:BAAALgAECgEJAgAAAA==.',
Ai='Aidon:BAAALgADCgEJAQAAAA==.Ainzina:BAAALgADCgUJBQAAAA==.Aio:BAAALgAECgYJDAABLgAECgYJFQAKACcVAA==.',
Ak='Akiras:BAAALgADCggJCwAAAA==.',
Al='Alarielle:BAAALgADCgYJBgABLgAECgkJIAALAL0bAA==.Alexeika:BAAALgAECgEJAQAAAA==.Alistarz:BAACLgAFFH8FAAIDAAMJ5hnTJwD1AAADAAMJ5hnTJwD1AAAuAAQKfzcAAwMACQnlJJ0CADwDAAMACQnlJJ0CADwDAAwABgn0EDsqAA4BAAAA.Allei:BAAALgAECgYJCQABLgAFFAQJCgANAAEGAA==.Alyndrya:BAABLgAECn8jAAMEAAkJOhaTEAABAgAEAAkJOhaTEAABAgAFAAYJxxGbfQALAQAAAA==.Alyndrys:BAABLgAECn8iAAIOAAcJmhPgEwBfAQAOAAcJmhPgEwBfAQAAAA==.',
Am='Amelialynne:BAABLgAECn83AAIFAAkJNRP5MwDhAQAFAAkJNRP5MwDhAQAAAA==.Amithralia:BAABLgAECn8pAAINAAkJ1B4rCgAJAwANAAkJ1B4rCgAJAwAAAA==.Amock:BAAALgADCggJDwAAAA==.',
An='Anaraith:BAAALgADCgQJBAAAAA==.Anejo:BAABLgAECn8UAAIPAAYJ0SIeGgDKAQAPAAYJ0SIeGgDKAQAAAA==.Anhinga:BAAALgAECgIJAgAAAA==.Anilex:BAAALgAECgQJBAAAAA==.Anzarna:BAABLgAECn8VAAIQAAgJjxbdPADcAQAQAAgJjxbdPADcAQAAAA==.',
Ao='Aodwarf:BAAALgAECgEJAQABLgAFFAgJJgANAOYcAA==.Aohikari:BAAALgADCgYJCgABLgAFFAgJJgANAOYcAA==.Aokuma:BAACLgAFFH8mAAINAAgJ5hyjAQAZAwANAAgJ5hyjAQAZAwAuAAQKfywAAw0ACQlPJHEGAEQDAA0ACQlPJHEGAEQDABEABAlSIRJIAAwBAAAA.',
Ap='Apex:BAAALgAECgEJAQAAAA==.Aprigity:BAABLgAECn8mAAISAAgJug5UCQCZAQASAAgJug5UCQCZAQAAAA==.',
Aq='Aquaten:BAABLgAECn8ZAAIGAAcJARHgIQCBAQAGAAcJARHgIQCBAQAAAA==.',
Ar='Aramac:BAAALgAECgEJAwAAAA==.Arashinigon:BAABLgAECn8ZAAMNAAkJhRBWZQD1AAANAAgJJg5WZQD1AAARAAYJIBaRSADPAAAAAA==.Arcafrost:BAAALgAECgkJAQAAAA==.Arceus:BAAALgAECgQJCQAAAA==.Archaon:BAABLgAECn8jAAMQAAgJmw2PYQBzAQAQAAgJmw2PYQBzAQATAAEJAABiTAAAAAAAAA==.Argoroth:BAABLgAECn8VAAICAAYJeRnjcACaAQACAAYJeRnjcACaAQAAAA==.Ariandise:BAAALgAECgMJAwABLgAECgcJEwAUAAAAAA==.Arick:BAABLgAECn8VAAICAAgJYRpsTwDzAQACAAgJYRpsTwDzAQAAAA==.Ark:BAABLgAECn9FAAMVAAkJpib/AQBrAwAVAAkJpib/AQBrAwAWAAYJIyUfHADqAQAAAA==.',
As='Asic:BAAALgADCgIJAgAAAA==.Asmodias:BAAALgAECgkJEQAAAA==.Asmódeus:BAABLgAECn8cAAQXAAgJoQ73DQBTAQAXAAYJWw73DQBTAQAQAAgJCgqzcgBLAQATAAQJYQ1RPgC7AAAAAA==.Asroldal:BAAALgADCgcJBwAAAA==.Asymptomatic:BAAALgAECgYJEQAAAA==.',
At='Atanker:BAAALgADCgMJBAAAAA==.',
Av='Avarak:BAAALgADCgcJDAAAAA==.',
Aw='Awenina:BAAALgADCgkJCQAAAA==.',
Ax='Axon:BAABLgAECn8pAAIJAAkJcBbQMgA3AgAJAAkJcBbQMgA3AgAAAA==.',
['Aì']='Aìo:BAABLgAECn8VAAMKAAYJJxXeMAA6AQAKAAYJJxXeMAA6AQAYAAQJvBbcPQDvAAAAAA==.',
Ba='Baaku:BAAALgADCgQJBgAAAA==.Babyfists:BAAALgAECgcJCQABLgAECgkJEgAJAHQVAA==.Baelhay:BAABLgAECn8ZAAIZAAcJUAL1MgCbAAAZAAcJUAL1MgCbAAAAAA==.Baelthas:BAAALgADCgcJBwAAAA==.Bats:BAAALgAECgEJAQAAAA==.',
Be='Beanor:BAAALgAECgYJDAAAAA==.Beet:BAAALgADCgcJBwAAAA==.Belitha:BAACLgAFFH8HAAIFAAMJ2h4iPwARAQAFAAMJ2h4iPwARAQAuAAQKfy0AAgUACQlKIAsTAOgCAAUACQlKIAsTAOgCAAAA.Belmaris:BAABLgAECn8vAAISAAkJ7RwcAgC0AgASAAkJ7RwcAgC0AgAAAA==.Benbreathing:BAAALgAECgUJCQAAAA==.Beng:BAAALgAECgMJBQAAAA==.Berketta:BAAALgAECgYJDwAAAA==.Besttros:BAAALgAECgEJAQAAAA==.',
Bi='Bigbadjohn:BAAALgADCgMJBAAAAA==.Bigcupcakes:BAABLgAECn8eAAIaAAcJvQsUjgA2AQAaAAcJvQsUjgA2AQAAAA==.Bigdaddykong:BAAALgADCggJCAAAAA==.Bigdruid:BAABLgAECn8aAAINAAkJkxKXJgAIAgANAAkJkxKXJgAIAgAAAA==.Bill:BAAALgAECgEJAQAAAA==.Bimbosuzi:BAABLgAECn8UAAIEAAcJvAhjLQD3AAAEAAcJvAhjLQD3AAAAAA==.Binghealing:BAAALgAECgYJCgAAAA==.Bird:BAAALgAECgIJAgAAAA==.',
Bl='Blasteyes:BAABLgAECn8xAAIbAAgJIh3tBABMAgAbAAgJIh3tBABMAgAAAA==.Blegh:BAACLgAFFH8JAAMcAAMJ7BUGNgDPAAAcAAMJ7BUGNgDPAAAdAAEJxgpyDABLAAAuAAQKfyMAAx0ACQnCHqcKADECAB0ABwnHHqcKADECABwABwl/GygfAMoBAAAA.Blueflu:BAAALgADCgMJAwAAAA==.Bluegrass:BAABLgAECn9EAAIOAAkJOCMOAQA/AwAOAAkJOCMOAQA/AwAAAA==.',
Bo='Bondï:BAABLgAECn8fAAMeAAgJxAnuRABkAQAeAAgJxAnuRABkAQACAAYJpQq8sAAiAQAAAA==.Boogey:BAAALgADCgMJAwAAAA==.Booshybrow:BAAALgAFFAEJAQAAAA==.Bootyweaver:BAAALgAECgYJCgAAAA==.Borc:BAAALgAECgYJCgAAAA==.Borik:BAABLgAECn8gAAMLAAkJvRv1HQASAgALAAkJvRv1HQASAgAPAAUJdxieOQAFAQAAAA==.Bosco:BAAALgAECgMJBQAAAA==.Botis:BAAALgAECgUJBAABLgAECgMJAwAUAAAAAA==.',
Br='Brighteye:BAAALgAECggJEgAAAA==.Brittany:BAAALgAECgYJDQAAAA==.Brothergrim:BAAALgADCgEJAQAAAA==.',
Bu='Buckme:BAACLgAFFH8JAAIIAAQJgAxXPAAYAQAIAAQJgAxXPAAYAQAuAAQKfxcAAggACAmpEspHALQBAAgACAmpEspHALQBAAAA.Buggers:BAAALgAECgIJAgAAAA==.Bungalator:BAAALgAECgQJBQAAAA==.Bunnygirl:BAABLgAFFH8IAAIJAAYJUxfuPgBQAQAJAAYJUxfuPgBQAQABLgAFFAcJGwAfACgeAA==.Bustedhoof:BAAALgADCgMJAwAAAA==.',
Ca='Caiphage:BAABLgAECn8bAAIFAAgJ1xmUTADCAQAFAAgJ1xmUTADCAQAAAA==.Caladelm:BAAALgAECgcJEAAAAA==.Caleria:BAAALgADCgYJBgAAAA==.Caralhan:BAABLgAECn8gAAIaAAgJAg0acAByAQAaAAgJAg0acAByAQAAAA==.Carlarae:BAABLgAECn8UAAIJAAYJOQT67wCjAAAJAAYJOQT67wCjAAAAAA==.Castelo:BAAALgAECgUJEgAAAA==.',
Ce='Cedra:BAACLgAFFH8OAAIJAAQJih0NOwBbAQAJAAQJih0NOwBbAQAuAAQKfxwAAgkACQksIYIQAOYCAAkACQksIYIQAOYCAAAA.Cegeo:BAABLgAECn8/AAITAAkJ/hhvAwBHAgATAAkJ/hhvAwBHAgAAAA==.',
Ch='Chaindk:BAAALgAECgQJCQAAAA==.Chaningtotem:BAAALgAECgIJAwAAAA==.Chapo:BAAALgADCgcJBwAAAA==.Cheepdeeps:BAABLgAECn9LAAMDAAkJkyOWBQD3AgADAAkJkyOWBQD3AgAMAAEJ0g7HagAxAAAAAA==.Chocoworm:BAAALgADCgkJCwAAAA==.Chokez:BAAALgADCgMJAwAAAA==.Chudmaster:BAAALgAECgEJAgAAAA==.Chupathingyy:BAACLgAFFH8FAAIQAAIJ/hKEggCcAAAQAAIJ/hKEggCcAAAuAAQKfyMAAxAABwncH3IuABQCABAABwncH3IuABQCABcABAlIGPISAP0AAAAA.Chìpotle:BAAALgAECgEJAQAAAA==.',
Ci='Ciennajewel:BAAALgAECggJEAAAAA==.Cirdle:BAABLgAECn8iAAMIAAgJNQ7OUQCXAQAIAAgJNQ7OUQCXAQAHAAMJIwbaJwBoAAAAAA==.Cirona:BAABLgAECn8dAAINAAYJeyF6HwA5AgANAAYJeyF6HwA5AgAAAA==.',
Cl='Clausewitz:BAABLgAECn8ZAAIZAAkJ7gpbGwBHAQAZAAkJ7gpbGwBHAQAAAA==.Cloroxx:BAAALgAECgYJBwAAAA==.',
Co='Cobalt:BAACLgAFFH8EAAIQAAIJ0BKWhwCUAAAQAAIJ0BKWhwCUAAAuAAQKfyAAAhAACQk+HB4fAF0CABAACQk+HB4fAF0CAAAA.Coldsteel:BAAALgADCgEJAQABLgADCgcJBwAUAAAAAA==.Colphere:BAAALgADCgkJDgAAAA==.Coolkid:BAAALgAECgQJCQAAAA==.Corsic:BAAALgADCgUJBQAAAA==.',
Cr='Crazynlazy:BAABLgAECn8hAAIWAAgJ7gK+UgDUAAAWAAgJ7gK+UgDUAAAAAA==.Creamyweamy:BAABLgAECn8cAAIgAAgJQxN5IQCkAQAgAAgJQxN5IQCkAQAAAA==.Creemy:BAAALgADCgQJAQAAAA==.Critsmcgee:BAABLgAECn8hAAMJAAcJQA31mgArAQAJAAcJQA31mgArAQAhAAEJ6wGvIQAmAAAAAA==.Crucifixea:BAAALgAECgEJAwAAAA==.Cruxsader:BAAALgAECgQJBQAAAA==.Cruzmaster:BAABLgAECn8eAAMWAAkJ6BTeGQD9AQAWAAkJ6BTeGQD9AQAiAAQJqAsCHwDgAAAAAA==.Cryokai:BAAALgAECgIJAgAAAA==.Cryoluxis:BAAALgADCgUJBQAAAA==.Crystyl:BAABLgAECn8iAAIJAAgJMwfOnwAiAQAJAAgJMwfOnwAiAQAAAA==.',
Cu='Cuddly:BAABLgAFFH8RAAIjAAYJ0xthDADyAQAjAAYJ0xthDADyAQABLgAFFAkJKgAYAIkfAA==.Cupp:BAAALgAECgcJEgAAAA==.Cute:BAAALgAFFAEJAQABLgAFFAgJIwAYAAIeAA==.',
Da='Daamass:BAAALgAECgEJAQAAAA==.Daddy:BAACLgAFFH8fAAIjAAcJ6yS9AgDOAgAjAAcJ6yS9AgDOAgAuAAQKf4wAAiMACQmzJgwAAAkEACMACQmzJgwAAAkEAAAA.Daddydonut:BAAALgADCgYJBgABLgAECgEJAQAUAAAAAA==.Daggonet:BAABLgAECn8VAAIaAAgJMxxOIwBmAgAaAAgJMxxOIwBmAgAAAA==.Dalrin:BAABLgAECn8XAAMiAAYJ7A+uFQBiAQAiAAYJ7A+uFQBiAQAWAAQJzAfqZwCjAAAAAA==.Darayia:BAAALgAECgEJAgAAAA==.Darkcarnival:BAABLgAECn8vAAIQAAkJQBqIHABsAgAQAAkJQBqIHABsAgAAAA==.Darkdew:BAAALgADCgUJBQAAAA==.Darkimp:BAAALgAECgEJAQAAAA==.Darkknightx:BAACLgAFFH8HAAIDAAQJgAoRIwAQAQADAAQJgAoRIwAQAQAuAAQKfyEAAgMACQmJF0wsAAMCAAMACQmJF0wsAAMCAAAA.Darkphoenixx:BAAALgAECgYJCAAAAA==.Darthnyte:BAAALgAECgQJBQABLgAECgcJGAAVAJ8QAA==.Darthraider:BAABLgAECn8XAAIaAAcJ9A0nuQDzAAAaAAcJ9A0nuQDzAAAAAA==.Dasnotgood:BAABLgAECn8UAAMOAAcJuh3bDADKAQAOAAYJUB/bDADKAQAkAAUJARWOFAAoAQAAAA==.Datoneshammy:BAABLgAECn8WAAQWAAgJxweMQgAQAQAWAAgJxweMQgAQAQAVAAEJowGnqgAhAAAiAAEJeAEbPQAeAAAAAA==.Davrøs:BAAALgAECgQJCQAAAA==.',
Db='Dbagjohnsonn:BAAALgADCgIJAgAAAA==.Dbheals:BAAALgADCgMJAwAAAA==.',
De='Deathspeaker:BAAALgADCgEJAQABLgAECggJIQAfABMTAA==.Deeman:BAAALgAECgcJDQAAAA==.Deemon:BAABLgAECn8ZAAIFAAkJyhQ4MgDoAQAFAAkJyhQ4MgDoAQAAAA==.Dehaka:BAAALgAECgMJBAAAAA==.Dejavu:BAAALgADCgEJAQAAAA==.Delathatha:BAAALgADCgIJAwAAAA==.Delphiarrow:BAAALgADCgIJAgAAAA==.Demiish:BAABLgAECn8WAAITAAcJZRIbDgBEAQATAAcJZRIbDgBEAQAAAA==.Dendreon:BAAALgADCgUJCAAAAA==.Denedin:BAAALgAECggJEQAAAA==.Denevien:BAABLgAECn8pAAMgAAgJ+xEcJACPAQAgAAgJ+xEcJACPAQAKAAcJlhD8LgBFAQAAAA==.Denidan:BAAALgAECgIJAgAAAA==.Dertus:BAABLgAECn8iAAIRAAkJAhW1GQDmAQARAAkJAhW1GQDmAQAAAA==.Desdemona:BAABLgAECn8iAAIBAAgJ3SBnBwBTAgABAAgJ3SBnBwBTAgAAAA==.Dethiaris:BAAALgAECgEJAgAAAA==.Dethon:BAAALgADCgcJBwAAAA==.Devourment:BAACLgAFFH8HAAIIAAQJuQzpOAAhAQAIAAQJuQzpOAAhAQAuAAQKfxoAAwgACQlrGmEXAIYCAAgACQlrGmEXAIYCAAcAAglsAyxAABwAAAAA.',
Di='Dianimal:BAABLgAECn8iAAIRAAgJqAdROgAPAQARAAgJqAdROgAPAQAAAA==.Dings:BAAALgADCggJFAAAAA==.Dinodan:BAAALgAECgEJAQABLgAECgYJEAAUAAAAAA==.Discnips:BAAALgAECgMJAwAAAA==.Distroya:BAABLgAECn8mAAMeAAgJbiTVBAA3AwAeAAgJbiTVBAA3AwACAAgJwiGoGgCNAgAAAA==.',
Dk='Dklel:BAACLgAFFH8QAAIaAAUJ0CHdOQBhAQAaAAUJ0CHdOQBhAQAuAAQKf0AAAhoACQl4JoIFAEUDABoACQl4JoIFAEUDAAAA.',
Do='Dojacat:BAAALgADCgkJEAAAAA==.Donuts:BAAALgAECgEJAQAAAA==.Doomace:BAABLgAECn8mAAMCAAkJCRZwPwAoAgACAAkJCRZwPwAoAgABAAQJfAHhQwBAAAAAAA==.Doomfeather:BAAALgAECgQJBgAAAA==.Dorigog:BAABLgAECn8oAAICAAkJIBJkaQCDAQACAAkJIBJkaQCDAQAAAA==.',
Dr='Draaka:BAAALgADCgYJBgAAAA==.Dragee:BAAALgAECgEJBAABLgAECgkJGQAFAMoUAA==.Dragon:BAAALgAECgkJEAAAAA==.Dragonpunch:BAABLgAECn8qAAIjAAkJ6xnnGgAdAgAjAAkJ6xnnGgAdAgAAAA==.Driftyshaman:BAABLgAECn8eAAIWAAcJxgkCSQD2AAAWAAcJxgkCSQD2AAAAAA==.Drusilia:BAAALgAECgQJBwAAAA==.Dræghoule:BAABLgAECn8XAAIaAAgJVQgJhgBEAQAaAAgJVQgJhgBEAQAAAA==.',
Dt='Dtrouble:BAAALgADCgEJAQAAAA==.',
Dw='Dworflundgrn:BAABLgAECn8sAAIiAAkJoA2iDgCrAQAiAAkJoA2iDgCrAQAAAA==.',
Dy='Dyamï:BAABLgAECn8wAAIjAAkJdh2gBwAKAwAjAAkJdh2gBwAKAwAAAA==.Dydimus:BAAALgAECgYJDAAAAA==.Dysko:BAAALgAECgYJEgAAAA==.',
Eg='Eglosira:BAABLgAECn8VAAIJAAcJYAYhvwDvAAAJAAcJYAYhvwDvAAAAAA==.',
El='Elbuhero:BAAALgAFFAEJAQAAAA==.Eldiablo:BAAALgADCgIJAgAAAA==.Electric:BAABLgAECn8hAAIWAAgJXAoEPgAiAQAWAAgJXAoEPgAiAQAAAA==.Elementstone:BAAALgADCgQJAwAAAA==.Eleven:BAAALgAECgYJDAAAAA==.Ellä:BAAALgAECgYJCQAAAA==.Elrythe:BAACLgAFFH8LAAIIAAQJqg7GPgARAQAIAAQJqg7GPgARAQAuAAQKfzgAAggACQmGIjQHABUDAAgACQmGIjQHABUDAAAA.Elviric:BAAALgADCgMJAwAAAA==.',
Er='Eratar:BAAALgAECggJDAAAAA==.Erazan:BAAALgADCgEJAQAAAA==.Erzulie:BAAALgADCgUJBQAAAA==.',
Et='Ethepally:BAAALgADCgUJBQAAAA==.Ethepriest:BAAALgAECgMJBAAAAA==.',
Ev='Evilmorana:BAAALgAECgMJBgAAAA==.',
Fa='Fallyynn:BAAALgAECgYJEQAAAA==.Fatalii:BAAALgAECgEJAQABLgAECgkJEgAJAHQVAA==.Fayelar:BAAALgAECgEJAQAAAA==.',
Fe='Fegyhr:BAABLgAECn8UAAINAAcJvhEJQACBAQANAAcJvhEJQACBAQAAAA==.Felebash:BAAALgAECgUJDwAAAA==.',
Fi='Fistdaddy:BAAALgAFFAEJAQAAAA==.',
Fl='Floofies:BAACLgAFFH8bAAIiAAYJZyGdAQDFAQAiAAYJZyGdAQDFAQAuAAQKfyMAAiIACQnjJbUDAO8CACIACQnjJbUDAO8CAAAA.Floofndoom:BAAALgAECgQJBAABLgAFFAYJGwAiAGchAA==.Floofyfu:BAAALgAECgYJCgABLgAFFAYJGwAiAGchAA==.',
Fr='Fredrickk:BAAALgAECgcJEwAAAA==.Fro:BAAALgADCgIJAgAAAA==.Fronobulax:BAAALgADCgYJBgAAAA==.Frostbane:BAAALgADCgEJAQAAAA==.',
Fu='Furpocalypse:BAAALgAECgQJBAAAAA==.Furrylight:BAAALgAECgQJBgABLgAFFAUJEgAVAGUYAA==.Furryphase:BAACLgAFFH8SAAIVAAUJZRhYGwBmAQAVAAUJZRhYGwBmAQAuAAQKfyQAAxUACQnxHAwNALUCABUACQnxHAwNALUCABYABAlyCSByAHYAAAAA.Fuzzington:BAAALgAECgQJBgABLgAFFAYJGwAiAGchAA==.Fuzzydunlop:BAAALgAECgYJDgAAAA==.',
Fz='Fzoul:BAAALgAECgEJAQABLgAECgkJAgAUAAAAAA==.',
['Fï']='Fïddlestïcks:BAAALgAECgYJBgAAAA==.',
Ga='Gaawdshammit:BAAALgAECgYJCwAAAA==.Gallin:BAAALgAECgIJBAAAAA==.Gauldangit:BAAALgAECggJDAAAAA==.',
Ge='Geremiah:BAAALgAECgIJAgAAAA==.',
Gh='Ghosted:BAAALgAECgYJCgAAAA==.',
Gl='Glaur:BAABLgAECn83AAIVAAkJth7dEACyAgAVAAkJth7dEACyAgAAAA==.',
Go='Goatjira:BAAALgAECgMJBAAAAA==.',
Gr='Grandmaster:BAAALgADCgEJAgAAAA==.Gransreaper:BAAALgAECgcJCwAAAA==.Grimgor:BAAALgADCgEJAQABLgAECgkJGgAlAGAgAA==.Gripisrdy:BAABLgAECn8vAAMaAAkJyR9+EQDRAgAaAAkJyR9+EQDRAgAmAAMJgRilMADFAAAAAA==.',
Gu='Guldon:BAAALgAECgQJBAAAAA==.Gunslingr:BAABLgAECn8hAAMnAAkJkyIHAQD2AgAnAAkJkyIHAQD2AgAoAAEJugwNXgA7AAAAAA==.Gusmccrae:BAAALgAECgkJCwAAAA==.Guìdo:BAABLgAECn8YAAIVAAcJnxCNSQBuAQAVAAcJnxCNSQBuAQAAAA==.',
Gy='Gyluun:BAAALgADCgEJAQAAAA==.',
Ha='Haggrd:BAABLgAECn8VAAICAAgJdR6AJgBSAgACAAgJdR6AJgBSAgAAAA==.Hairyjolene:BAABLgAECn8ZAAIIAAcJKQ9VdABBAQAIAAcJKQ9VdABBAQAAAA==.Halrix:BAAALgAECgYJBgAAAA==.Hammetrick:BAAALgADCgYJCQABLgAFFAMJBQAUAAAAAA==.Handsome:BAAALgAECgYJCAAAAA==.Hardware:BAAALgADCgcJCgAAAA==.Harry:BAABLgAECn8gAAIQAAcJGh+rJQB8AgAQAAcJGh+rJQB8AgAAAA==.Harthvader:BAAALgADCgcJCgAAAA==.',
He='Heartshot:BAAALgAECgYJBwAAAA==.Heelios:BAAALgADCgcJBwAAAA==.Helamad:BAAALgAECgYJEAAAAA==.Helmshammer:BAAALgAECgYJEgAAAA==.Hexwhisper:BAAALgAECgIJAgAAAA==.Heycarlos:BAAALgAFFAMJAwAAAA==.',
Hi='Hikaridh:BAABLgAFFH8DAAIFAAEJvxNvhQBFAAAFAAEJvxNvhQBFAAABLgAFFAgJJgANAOYcAA==.Hikarimonk:BAABLgAFFH8IAAIjAAUJTg5NHgAtAQAjAAUJTg5NHgAtAQABLgAFFAgJJgANAOYcAA==.Hikaripala:BAAALgAECgEJAQABLgAFFAgJJgANAOYcAA==.',
Ho='Holyarceus:BAAALgADCgQJBAABLgAECgQJCQAUAAAAAA==.Holyblimblam:BAAALgAECgYJEAAAAA==.Honeypieheal:BAAALgAECgEJAQAAAA==.Hosemachine:BAABLgAECn8nAAMaAAgJBB5zPgD3AQAaAAgJmB1zPgD3AQAmAAcJ2BWmHQBcAQAAAA==.Hotpants:BAABLgAECn8iAAIKAAYJNA1uPwDwAAAKAAYJNA1uPwDwAAAAAA==.',
Hu='Huez:BAAALgAECgIJAgAAAA==.Hulksmasher:BAAALgAECgQJCgAAAA==.Huntkiid:BAAALgADCgYJCwAAAA==.',
Hy='Hyman:BAAALgADCgMJAwAAAA==.',
['Hè']='Hèrifury:BAAALgAECgQJBQAAAA==.',
Ic='Icerunner:BAAALgADCgYJDwAAAA==.Icyjackets:BAABLgAECn8ZAAMaAAcJJw18kgAvAQAaAAcJJw18kgAvAQAmAAQJpAUtQAB2AAAAAA==.',
Id='Idamiani:BAAALgADCgMJAwAAAA==.Idouna:BAAALgADCgQJBAAAAA==.Idris:BAAALgAECgEJAQAAAA==.',
In='Inanis:BAAALgAECggJEgAAAA==.Inside:BAAALgAECgEJAgAAAA==.Invictive:BAAALgAECgMJBgAAAA==.',
Io='Iorune:BAAALgADCgYJBgAAAA==.',
Ja='Jadienne:BAABLgAECn8VAAIIAAkJlA/SRwC0AQAIAAkJlA/SRwC0AQAAAA==.Jameson:BAABLgAECn8oAAIDAAgJBRe6IQDSAQADAAgJBRe6IQDSAQAAAA==.Jamiel:BAAALgAECgEJAQAAAA==.Jasmind:BAABLgAECn85AAMNAAgJHg7sQQB5AQANAAgJHg7sQQB5AQARAAEJLApdiAAnAAAAAA==.',
Je='Jeetli:BAAALgAECgQJBQABLgAECgYJFQAKACcVAA==.Jellydonut:BAAALgADCgYJCgABLgAECgEJAQAUAAAAAA==.Jelula:BAAALgADCgYJBgAAAA==.Jemmi:BAABLgAECn8UAAIWAAYJfg6nUADaAAAWAAYJfg6nUADaAAAAAA==.Jessicà:BAAALgAECgEJAQAAAA==.Jethro:BAAALgADCgUJBQAAAA==.',
Ji='Jimmy:BAAALgAECgEJAQAAAA==.Jinxz:BAAALgAECgYJEgAAAA==.Jinzaa:BAABLgAECn8bAAMVAAYJIhYRNgCrAQAVAAYJIhYRNgCrAQAWAAUJbxJ2VADOAAAAAA==.Jiwà:BAABLgAFFH8FAAIVAAUJMQJtNADyAAAVAAUJMQJtNADyAAABLgAFFAUJEgAKAPkKAA==.Jiwâ:BAACLgAFFH8SAAIKAAUJ+QrDGQADAQAKAAUJ+QrDGQADAQAuAAQKfzkAAgoACQlGHioLAIICAAoACQlGHioLAIICAAAA.',
Jo='Joesph:BAAALgAECgcJCgAAAA==.Jollibee:BAAALgAECgcJAQAAAA==.Jordinary:BAAALgAECgcJCgAAAA==.Joshjb:BAAALgAECggJEwAAAA==.Joss:BAAALgAFFAEJAgAAAA==.',
Ka='Kadan:BAAALgAECgYJCwABLgAFFAMJBwAFANoeAA==.Kahless:BAAALgADCgQJCQAAAA==.Kaibab:BAAALgADCgEJAgAAAA==.Kainani:BAAALgADCgQJBAAAAA==.Kakwaa:BAABLgAECn8gAAIDAAkJMAe+PwAyAQADAAkJMAe+PwAyAQAAAA==.Kaliyah:BAAALgADCgYJBgAAAA==.Katoosh:BAAALgADCgUJBQAAAA==.Kattrin:BAAALgADCgkJFgAAAA==.Kavorkyan:BAAALgAECgcJBwAAAA==.',
Ke='Keladia:BAAALgAECgEJAQAAAA==.Kema:BAAALgADCgMJBgAAAA==.Keyadistor:BAABLgAECn8aAAMlAAkJYCD0DgBXAQAaAAYJ7hpDXQDbAQAlAAcJyB/0DgBXAQAAAA==.',
Kh='Khamûl:BAAALgAECgMJBAAAAA==.Khazabrew:BAABLgAECn9BAAILAAkJ/x14BwCuAgALAAkJ/x14BwCuAgAAAA==.',
Ki='Kiamara:BAABLgAECn8aAAIQAAgJxAe0fwAwAQAQAAgJxAe0fwAwAQAAAA==.Kinderlin:BAABLgAECn8hAAICAAYJtxTamwAkAQACAAYJtxTamwAkAQAAAA==.Kipo:BAAALgAECgcJCAAAAA==.Kiralana:BAAALgAECgEJAQAAAA==.Kirb:BAAALgAECgMJAwAAAA==.',
Ko='Kookeez:BAAALgAECgYJCAAAAA==.Kookies:BAAALgAECgcJDwAAAA==.',
Kr='Krelix:BAABLgAECn8XAAINAAcJbha/NAC3AQANAAcJbha/NAC3AQAAAA==.Kriest:BAAALgADCgQJBAAAAA==.',
Ku='Kusanagï:BAAALgADCgMJAwAAAA==.',
La='Lancaban:BAAALgAECgYJDgAAAQ==.',
Le='Legolost:BAABLgAECn8YAAQdAAgJfRaSDwDiAQAdAAYJNhmSDwDiAQAcAAMJfRSEQgDYAAAfAAQJlQqNMwDSAAAAAA==.Lesbohorde:BAAALgADCgEJAQAAAA==.',
Li='Light:BAAALgAECgUJBQAAAA==.Lightofevil:BAAALgADCgUJBQAAAA==.Limpwurt:BAAALgAECgIJBAAAAA==.Linh:BAAALgADCgMJAwAAAA==.Lista:BAAALgAECgUJBQABLgAECgkJQAAPAGclAA==.',
Lo='Loadedtater:BAABLgAECn9AAAQGAAkJpyUAAQBZAwAGAAkJDiUAAQBZAwAIAAgJlyYWCgD0AgAHAAUJ3CX2JgDyAQAAAA==.Locked:BAAALgAECgUJBQAAAA==.Lockedin:BAAALgAECgMJAwAAAA==.Loralynn:BAACLgAFFH8KAAINAAQJAQYlNADQAAANAAQJAQYlNADQAAAuAAQKfxQAAg0ABwn7FHA0ALgBAA0ABwn7FHA0ALgBAAAA.Lorianne:BAACLgAFFH8HAAIVAAIJwRUaVwB9AAAVAAIJwRUaVwB9AAAuAAQKfygAAxUACAmvGGQpAOkBABUACAmvGGQpAOkBABYABQmxC7tWAOoAAAEuAAUUBAkKAA0AAQYA.Lorri:BAAALgADCgQJBQABLgAFFAQJCgANAAEGAA==.',
Lu='Lucianas:BAAALgAECggJEQAAAA==.Lunchböx:BAAALgAECgMJBgAAAA==.Lunico:BAAALgADCgEJAgAAAA==.Luthoros:BAAALgADCggJCwAAAA==.',
Ly='Lysi:BAABLgAECn8ZAAIIAAcJzRSzVACPAQAIAAcJzRSzVACPAQAAAA==.Lythalia:BAAALgADCgMJAwAAAA==.',
Ma='Macsena:BAAALgADCgEJAgAAAA==.Madaea:BAABLgAECn8zAAIjAAkJqh9aCQDnAgAjAAkJqh9aCQDnAgAAAA==.Madrashai:BAAALgAECgUJCgAAAA==.Magepuppy:BAABLgAECn83AAIJAAkJBhu7IwB5AgAJAAkJBhu7IwB5AgABLgAFFAQJDwAGAB8bAA==.Mahai:BAAALgADCgcJBAAAAA==.Mak:BAABLgAECn8UAAIgAAcJURu0GQDoAQAgAAcJURu0GQDoAQABLgAECggJGAAIAFMdAA==.Makavali:BAAALgAECgQJBQABLgAECggJGAAIAFMdAA==.Makdaddy:BAABLgAECn8YAAIIAAgJUx13JAA7AgAIAAgJUx13JAA7AgAAAA==.Malzeth:BAAALgAECgYJBgAAAA==.Marrilyn:BAAALgAFFAEJAQABLgAFFAcJCwAQAMQaAA==.Marrina:BAAALgADCgMJBgAAAA==.Matagi:BAABLgAECn8sAAIIAAkJzyB+CQD7AgAIAAkJzyB+CQD7AgAAAA==.Mate:BAAALgAECgMJAwAAAA==.Maw:BAAALgAECgMJAwAAAA==.',
Me='Mechamage:BAAALgAECgEJAgAAAA==.Meeseks:BAAALgAECgcJBwAAAA==.Melbeast:BAABLgAECn8YAAIIAAcJqBuqSQCvAQAIAAcJqBuqSQCvAQAAAA==.Melorea:BAAALgAECgMJBQAAAA==.Merdin:BAABLgAECn8cAAMJAAkJTxDyUgDMAQAJAAkJNhDyUgDMAQAhAAEJpwwYIAAvAAAAAA==.Methmartion:BAABLgAECn8ZAAMTAAcJCgk5GADPAAATAAcJCgk5GADPAAAQAAEJgQPzKAEpAAAAAA==.Metricdotem:BAAALgADCgEJAQAAAA==.Metricgg:BAAALgADCgEJAQAAAA==.',
Mi='Mightletudie:BAAALgADCgkJEAAAAA==.Mignon:BAAALgAECgMJAwAAAA==.Mikewai:BAABLgAECn8XAAIFAAgJgQ9uUgCtAQAFAAgJgQ9uUgCtAQAAAA==.Miloughah:BAAALgAECgkJBQAAAA==.Misaki:BAAALgADCgMJAwAAAA==.Mish:BAAALgAECgYJBgAAAA==.Missiah:BAABLgAECn81AAIBAAkJNwRXIwDgAAABAAkJNwRXIwDgAAAAAA==.Mitzalia:BAAALgAECgIJAgAAAA==.Mitzki:BAAALgADCgUJBQAAAA==.',
Mo='Moirane:BAAALgAECgUJCQAAAA==.Moistwhispa:BAAALgAECgIJAgABLgAECgkJHQARAO4WAA==.Molfise:BAABLgAECn8iAAMLAAgJHRTiIgCDAQALAAgJKxLiIgCDAQAPAAQJpRHfRwD1AAAAAA==.Monastary:BAAALgADCgUJCgAAAA==.Mongfirrmel:BAAALgADCgUJBgAAAA==.Moonfell:BAABLgAECn8/AAIgAAkJ4B9IBQAWAwAgAAkJ4B9IBQAWAwAAAA==.Moonlight:BAAALgAECgQJBAAAAA==.Moonlilly:BAABLgAECn8ZAAIMAAgJiwX5MwDeAAAMAAgJiwX5MwDeAAAAAA==.Mopp:BAAALgAECgQJBQAAAA==.Morganthe:BAAALgAECgQJBAAAAA==.Morin:BAAALgAECgEJAQAAAA==.',
Mu='Musubi:BAAALgADCgEJAQABLgAECgkJEAAUAAAAAA==.',
Mx='Mxtemlen:BAAALgAECggJCgABLgAECgkJIAAeAEYMAA==.',
My='Mylilhunter:BAAALgAECgYJDwAAAA==.Mysticalmoo:BAAALgADCggJEAAAAA==.Mysticrainne:BAAALgADCgYJBgAAAA==.Mythdar:BAAALgAECgcJDgABLgAECgkJKgAjAOsZAA==.Myttus:BAAALgADCgMJAwABLgAECgYJFAACAD4IAA==.',
['Mê']='Mêrlin:BAABLgAECn8dAAIJAAgJBgburQALAQAJAAgJBgburQALAQAAAA==.',
Na='Nachtelf:BAABLgAECn9MAAIIAAkJwiE1CAAJAwAIAAkJwiE1CAAJAwAAAA==.Nadeshiko:BAAALgADCgYJBgAAAA==.Nakamei:BAAALgAECgUJCgAAAA==.Nakirah:BAAALgAECgEJAQAAAA==.Nannydo:BAAALgADCgkJCQABLgAECggJEgAUAAAAAA==.Nannysham:BAAALgAECggJEgAAAA==.Naomí:BAABLgAECn8cAAIQAAYJ0wymkgAzAQAQAAYJ0wymkgAzAQAAAA==.Natadawn:BAAALgAECgQJBAAAAA==.Natalone:BAABLgAECn9FAAIJAAkJjCOtCAAkAwAJAAkJjCOtCAAkAwAAAA==.Natherel:BAABLgAECn8VAAMMAAcJ1gTFOgDCAAAMAAcJ1gTFOgDCAAADAAUJ5gNQcgCBAAAAAA==.Natrhatr:BAAALgADCgYJCwAAAA==.Naughty:BAACLgAFFH8OAAMfAAUJ8AuuFgANAQAfAAQJKg2uFgANAQAcAAQJgAoAPgCyAAAuAAQKfxwAAx8ACAnZFDENAO4BAB8ABwnWFjENAO4BABwABwm5GIYkAKABAAEuAAUUCAkjABgAAh4A.',
Ne='Newander:BAABLgAECn80AAINAAkJaRNpKgDxAQANAAkJaRNpKgDxAQAAAA==.Nezat:BAAALgADCgEJAQAAAA==.',
Ni='Nightofmares:BAAALgAECgcJDQAAAA==.Nirra:BAAALgAECgMJBgAAAA==.',
No='Nonphatmilk:BAAALgAECgUJCwAAAA==.Noots:BAAALgADCgcJBwAAAA==.Notoriginal:BAABLgAECn8tAAMaAAkJmxIRSQDWAQAaAAkJmxIRSQDWAQAmAAEJGxJ6RQAyAAAAAA==.',
Nu='Nuked:BAABLgAECn8dAAIJAAgJCR9gRQD1AQAJAAgJCR9gRQD1AQAAAA==.',
Og='Ograskygazer:BAABLgAECn8VAAINAAcJdAWscwDKAAANAAcJdAWscwDKAAAAAA==.',
Om='Omee:BAABLgAECn8gAAMEAAkJ2xaYFADMAQAEAAgJkxmYFADMAQAFAAYJ+QsjgQADAQAAAA==.Omy:BAABLgAECn8sAAIJAAcJbg3XkQA7AQAJAAcJbg3XkQA7AQAAAA==.',
Op='Ophela:BAAALgAECgMJBAAAAA==.',
Or='Orakio:BAAALgAFFAEJAgABLgAFFAQJDQAJAOgSAA==.Oralena:BAABLgAECn8ZAAIIAAcJvAUClwD6AAAIAAcJvAUClwD6AAAAAA==.Orioncheats:BAABLgAECn82AAIaAAkJshoMMAAtAgAaAAkJshoMMAAtAgAAAA==.',
Ov='Overpwerd:BAAALgADCgEJAQAAAA==.',
Ow='Owo:BAAALgADCgUJBQABLgAECgMJAwAUAAAAAA==.',
Ox='Oxygën:BAABLgAECn8aAAIJAAYJ+gXA3ADAAAAJAAYJ+gXA3ADAAAAAAA==.',
Pa='Paladingbat:BAACLgAFFH8JAAIeAAQJiRgMGQBDAQAeAAQJiRgMGQBDAQAuAAQKfxwAAh4ACAnfIqkGABIDAB4ACAnfIqkGABIDAAAA.Pallygoboom:BAAALgADCgUJBQABLgAECgYJEQAUAAAAAA==.Palomita:BAAALgADCgMJBgAAAA==.Paspir:BAAALgAECgMJAwAAAA==.Paull:BAAALgAECgcJEwAAAA==.',
Pe='Ped:BAABLgAECn8+AAMPAAkJ9R7KBwC5AgAPAAkJ9R7KBwC5AgAjAAEJ2AHbdgAXAAAAAA==.Peon:BAAALgAECgcJDwAAAA==.',
Ph='Pharune:BAABLgAECn8vAAIkAAkJFRIxEgCsAQAkAAkJFRIxEgCsAQAAAA==.Philosofist:BAAALgAECgUJDAAAAA==.Phredrick:BAABLgAECn8jAAIJAAgJjhc8SwDkAQAJAAgJjhc8SwDkAQAAAA==.',
Pi='Pickleboa:BAAALgAECgUJDgABLgAFFAMJBgAWAGIYAA==.Picklebob:BAAALgAECggJBwABLgAFFAMJBgAWAGIYAA==.Pickleboe:BAAALgAECgUJBQABLgAFFAMJBgAWAGIYAA==.Picklebosh:BAABLgAFFH8GAAIWAAMJYhj2JwDcAAAWAAMJYhj2JwDcAAAAAA==.Piemanninty:BAAALgADCgcJCQAAAA==.Pirellipaws:BAAALgADCgkJEAAAAA==.',
Pl='Plandemic:BAAALgAECgQJBwAAAA==.Pluto:BAAALgADCgEJAQAAAA==.',
Po='Pockithealz:BAAALgAECgYJCAABLgAECgkJEgAJAHQVAA==.Ponky:BAABLgAECn8cAAIKAAkJKhHOJQB/AQAKAAkJKhHOJQB/AQAAAA==.Porfir:BAAALgADCgUJBQAAAA==.Porrigar:BAAALgAECgEJAgAAAA==.Pounce:BAAALgAECgcJCwAAAA==.Pounces:BAABLgAFFH8KAAINAAMJghRiOAC+AAANAAMJghRiOAC+AAABLgAFFAkJKgAYAIkfAA==.',
Pr='Precious:BAACLgAFFH8aAAIYAAcJ8xMlCwApAgAYAAcJ8xMlCwApAgAuAAQKf0EABBgACQkjJBUDAGQDABgACQkjJBUDAGQDACAABglwDxs2AGQBAAoABAkvE+NLALsAAAEuAAUUCAkjABgAAh4A.',
['Pä']='Pängari:BAAALgAECgEJAQABLgAECgkJKAAZAPELAA==.',
Qu='Quattro:BAABLgAECn8WAAIdAAkJXgsYDwAJAQAdAAkJXgsYDwAJAQAAAA==.Quell:BAAALgADCgcJBwAAAA==.',
Ra='Racecar:BAABLgAECn81AAMDAAgJDxzFFwAeAgADAAgJ8RvFFwAeAgAMAAEJihVRZQA7AAAAAA==.Rageoverwelm:BAAALgADCgEJAQAAAA==.Raivyn:BAABLgAECn8cAAIPAAgJQxyzEAAuAgAPAAgJQxyzEAAuAgABLgAECgkJNAANAGkTAA==.Rajantu:BAAALgADCgYJCgAAAA==.Ratava:BAAALgAECgMJAwAAAA==.Raylaira:BAABLgAECn8iAAIgAAgJuQ2wJwB1AQAgAAgJuQ2wJwB1AQAAAA==.Raziel:BAAALgADCgMJAwAAAA==.',
Re='Redbeard:BAAALgAECgEJAQAAAA==.Rehum:BAABLgAECn8UAAICAAYJPghi4gC9AAACAAYJPghi4gC9AAAAAA==.Remagtrepxe:BAAALgADCgMJBQABLgAECgcJHgAWAMYJAA==.Remodify:BAAALgAECgIJAwAAAA==.Rengery:BAAALgAECgcJBwAAAA==.Reposado:BAAALgAECgUJCQAAAA==.Retbull:BAAALgADCgQJBwAAAA==.Retrall:BAAALgAECgcJCgAAAA==.Revelare:BAABLgAECn8sAAMiAAkJgRAFEgB3AQAiAAcJdhMFEgB3AQAVAAYJ3gc/ggC7AAAAAA==.Revèndreth:BAAALgAECgEJAQAAAA==.Rexbi:BAABLgAECn8bAAIFAAcJGhd+PQD+AQAFAAcJGhd+PQD+AQAAAA==.Rexbie:BAAALgAECgMJBQAAAA==.',
Rh='Rhylee:BAAALgAECgMJAwAAAA==.Rhytchus:BAAALgAECgQJCQAAAA==.',
Ri='Rianne:BAABLgAECn9CAAIKAAkJGRJZGgDZAQAKAAkJGRJZGgDZAQAAAA==.Risenbooty:BAAALgADCgMJAwAAAA==.Risk:BAAALgADCgUJBQAAAA==.',
Ro='Robberttrest:BAABLgAECn8XAAIIAAYJlwshcAAXAQAIAAYJlwshcAAXAQAAAA==.Rockyevoker:BAAALgADCgQJBAAAAA==.Rockyhunterr:BAABLgAECn8dAAMaAAkJERsNOgAGAgAaAAkJ5xoNOgAGAgAlAAYJrhWxCABaAQAAAA==.Rockywarlock:BAAALgAECgUJBQAAAA==.Rolemartyr:BAAALgAECgYJDQAAAA==.Rooth:BAABLgAECn8eAAIdAAgJlg6MCQB6AQAdAAgJlg6MCQB6AQAAAA==.Roryn:BAACLgAFFH8IAAICAAMJoRQGVwDiAAACAAMJoRQGVwDiAAAuAAQKf0gAAgIACQm0JYwDAFUDAAIACQm0JYwDAFUDAAAA.Rowdan:BAAALgAECgEJAQAAAA==.Rozimi:BAAALgAECgEJAQAAAA==.',
Ru='Rubadubchub:BAAALgADCgYJCQAAAA==.Rubï:BAAALgAFFAIJBAAAAA==.Rugi:BAAALgAECgEJAQABLgAFFAcJLgANAFokAA==.Rugiia:BAACLgAFFH8uAAINAAcJWiRMAgDvAgANAAcJWiRMAgDvAgAuAAQKf0YAAw0ACQmWJkEAAOMDAA0ACQmWJkEAAOMDAA4ABAlfJdAXADEBAAAA.Rugiian:BAABLgAFFH8FAAIjAAMJ+xKRLADFAAAjAAMJ+xKRLADFAAABLgAFFAcJLgANAFokAA==.Rumint:BAAALgADCgEJAQAAAA==.',
Ry='Ryleth:BAAALgADCgYJBgAAAA==.Rylonk:BAABLgAECn8aAAIQAAkJjQmHWgCEAQAQAAkJjQmHWgCEAQAAAA==.Ryuka:BAABLgAECn8aAAIkAAkJIAnhJAAIAQAkAAkJIAnhJAAIAQAAAA==.',
Sa='Sabeli:BAAALgAECggJCAAAAA==.Sabindeus:BAAALgAECgkJAQAAAA==.Samyria:BAAALgAECgYJEwAAAA==.Sandwich:BAAALgAECgUJBwAAAA==.Sanguinius:BAAALgADCgMJAwAAAA==.Satyaru:BAABLgAECn8lAAQjAAgJiQyXPgBEAQAjAAgJiQyXPgBEAQAPAAcJlg4aNQAbAQALAAEJgAH5mQAYAAAAAA==.Saucy:BAAALgAECgYJDwAAAA==.',
Sc='Scarletnight:BAAALgADCgMJAwABLgADCgcJCwAUAAAAAA==.Scrubsauce:BAAALgAECgEJBAAAAA==.',
Se='Sedona:BAAALgADCgYJBwAAAA==.Selarra:BAABLgAECn8lAAIgAAgJ8BPbIgCZAQAgAAgJ8BPbIgCZAQAAAA==.Seric:BAABLgAECn8oAAMZAAkJ8QuoGQBYAQAZAAkJ8QuoGQBYAQADAAQJugSkewBlAAAAAA==.Sesethi:BAAALgAECgMJAwABLgAECgcJGgAXAM0bAA==.',
Sh='Shadowdancèr:BAABLgAECn8ZAAMKAAgJWhVlHQC+AQAKAAgJWhVlHQC+AQAYAAMJ+RHCSQCzAAAAAA==.Shadowlocke:BAAALgAECgEJAQAAAA==.Shadowyisis:BAAALgAECgcJCgAAAA==.Shammitjanet:BAAALgAECgUJBQAAAA==.Shamoochies:BAAALgAECgEJAQAAAA==.Shamquen:BAAALgAECgkJCwAAAA==.Shanair:BAACLgAFFH8PAAIGAAQJHxupDABTAQAGAAQJHxupDABTAQAuAAQKfz8AAwYACQnQI98BAC0DAAYACQm3I98BAC0DAAcABwnWHTkbAE8CAAAA.Shirizani:BAAALgAECgQJBAABLgAFFAQJFQABAIgPAA==.Shrimpy:BAAALgAECgQJCAAAAA==.Shuaiguy:BAAALgAECgEJBQAAAA==.',
Si='Sibala:BAAALgADCgQJBAAAAA==.Sinarel:BAAALgAECgQJBQAAAA==.',
Sk='Skimmilk:BAAALgAECgMJBAABLgAFFAUJFAAZAEoYAA==.Skybox:BAAALgAECgQJBAAAAA==.Skyboxer:BAAALgAECgQJDAAAAA==.Skye:BAABLgAECn8XAAMYAAYJvhFAMAAeAQAYAAUJiBBAMAAeAQAgAAUJfQ+zTQCRAAAAAA==.',
Sl='Slambamwhoo:BAAALgAECgkJDgAAAA==.Slingspell:BAAALgAECgMJBQAAAA==.Slippin:BAAALgADCggJFQAAAA==.Slythenole:BAAALgAECgkJBAAAAA==.',
Sm='Smartfood:BAAALgADCgMJAwAAAA==.Smoochybooty:BAABLgAECn8uAAIJAAkJrhGBRwDvAQAJAAkJrhGBRwDvAQAAAA==.',
Sn='Sneakydeaky:BAAALgAECggJCAAAAA==.',
So='Soggyiguana:BAAALgADCgUJBgAAAA==.Solnar:BAABLgAECn8gAAQeAAkJRgyOKwChAQAeAAkJRgyOKwChAQABAAYJQBPgJgDGAAACAAEJYBb3YAE6AAAAAA==.',
Sp='Sparkee:BAAALgADCgcJCwAAAA==.Spinandkick:BAAALgAECgEJAQAAAA==.Spiritality:BAAALgADCgMJAwABLgAECgQJBAAUAAAAAA==.Splashdaddy:BAACLgAFFH8MAAIVAAMJFiU+IwA5AQAVAAMJFiU+IwA5AQAuAAQKfyQAAhUACQlGJC4GADsDABUACQlGJC4GADsDAAEuAAUUAQkBABQAAAAA.Spudspinner:BAAALgAECgEJAQAAAA==.',
Sq='Squog:BAAALgADCgIJAgAAAA==.',
Sr='Srìracha:BAAALgAECgUJCgAAAA==.',
St='Staks:BAAALgAECgEJAQAAAA==.Starii:BAABLgAECn8iAAIVAAgJQwecXwAhAQAVAAgJQwecXwAhAQAAAA==.Stas:BAAALgADCgYJCwAAAA==.Stevelock:BAAALgADCggJDgAAAA==.Storagetec:BAAALgADCgkJEQAAAA==.Striga:BAAALgAECgUJBwAAAA==.',
Su='Suffer:BAAALgAECgQJCAAAAA==.Sunless:BAAALgAECgIJAwAAAA==.',
Sy='Sygma:BAAALgADCgMJAwAAAA==.Sylvancura:BAAALgAECgIJAwAAAA==.Sylvenna:BAAALgAECgYJCgAAAA==.Synestra:BAABLgAECn8jAAIkAAgJCCEcBgCFAgAkAAgJCCEcBgCFAgAAAA==.',
Ta='Taea:BAAALgAECgMJBAABLgAECgYJHQANAHshAA==.Taeus:BAACLgAFFH8NAAIJAAQJ6BISSwA4AQAJAAQJ6BISSwA4AQAuAAQKfxcAAgkACAkVGOBeAB4CAAkACAkVGOBeAB4CAAAA.Taintedkoma:BAAALgAECgcJCAABLgAECgcJGQATAAoJAA==.Taladiir:BAAALgAECgQJCAAAAA==.Talasa:BAAALgADCgMJAwAAAA==.Taliaz:BAAALgADCgIJAgAAAA==.Tapp:BAAALgADCgcJBwAAAA==.Tastycles:BAAALgAECgYJEgAAAA==.Taterstorm:BAAALgAECgMJAwAAAA==.Taurenator:BAABLgAECn8jAAIZAAkJoiEKCAClAgAZAAkJoiEKCAClAgAAAA==.Tayblr:BAABLgAECn8rAAIIAAYJOALbywCNAAAIAAYJOALbywCNAAAAAA==.',
Te='Telese:BAAALgADCgEJAQAAAA==.Telkhar:BAAALgAFFAEJAQAAAA==.Temajin:BAABLgAECn8YAAMeAAYJrgvgRQATAQAeAAYJrgvgRQATAQACAAIJvwsMfwEsAAAAAA==.Temple:BAAALgADCgQJBgAAAA==.Teomcdoul:BAAALgADCgUJBQAAAA==.Teranidas:BAAALgADCgYJCgAAAA==.Teratrendera:BAABLgAECn8XAAMfAAcJkCH7BwBkAgAfAAcJkCH7BwBkAgAcAAEJCg+NZAAtAAAAAA==.Teron:BAAALgAECgEJAQAAAA==.Terrathkar:BAAALgAECgIJAgAAAA==.',
Th='Thavis:BAABLgAECn8WAAMQAAcJEA+DjQAXAQAQAAcJQgyDjQAXAQATAAEJChZ5NABAAAAAAA==.Themyscira:BAAALgAECgIJAgAAAA==.Theonorf:BAABLgAECn88AAIIAAgJICKHDwDCAgAIAAgJICKHDwDCAgAAAA==.Thetimelord:BAAALgAECgUJBwAAAA==.Thewarrior:BAAALgAECggJEQAAAA==.Thypriest:BAAALgAECgYJEwAAAA==.',
Ti='Tick:BAAALgAECgEJAQAAAA==.Tidus:BAAALgAECgQJBAAAAA==.Tik:BAAALgADCgEJAQAAAA==.Tilted:BAABLgAECn8mAAICAAgJVhXNSwD/AQACAAgJVhXNSwD/AQAAAA==.Tirus:BAAALgADCgQJBQAAAA==.',
To='Tobi:BAAALgADCgUJBQAAAA==.Toblakài:BAAALgAECgYJBQABLgAECgkJHgAWAFQVAA==.Torrey:BAABLgAECn85AAIbAAkJYBC8CwCGAQAbAAkJYBC8CwCGAQAAAA==.',
Tr='Tradd:BAACLgAFFH8HAAIYAAMJ0xlxIgAJAQAYAAMJ0xlxIgAJAQAuAAQKfyEAAhgACQmLHjEIANoCABgACQmLHjEIANoCAAAA.Trigg:BAAALgAECgUJBQABLgAFFAMJBwAFANoeAA==.Tristyana:BAABLgAECn9IAAIIAAkJYh23FACYAgAIAAkJYh23FACYAgAAAA==.Trossard:BAAALgADCgEJAQAAAA==.',
Ts='Tsunâde:BAABLgAECn9AAAQPAAkJZyVAAgBAAwAPAAkJZyVAAgBAAwAjAAcJgxZEIwCZAQALAAcJhBHNKQBVAQAAAA==.',
Tw='Twinkletoe:BAAALgAECgQJBAABLgAECgkJQAAPAGclAA==.',
Ty='Tylurien:BAABLgAECn8pAAIeAAkJkyBLBgAZAwAeAAkJkyBLBgAZAwAAAA==.',
['Të']='Tëmpest:BAAALgAECgYJBwAAAA==.',
Ul='Ulangi:BAAALgADCgMJBQAAAA==.',
Un='Untouchablez:BAAALgADCgYJBgAAAA==.',
Ur='Urbanprey:BAABLgAECn8qAAITAAgJxAypDgA8AQATAAgJxAypDgA8AQAAAA==.Urimar:BAAALgADCgkJDQAAAA==.',
Va='Valeris:BAAALgAECgYJBgAAAA==.Valkoinen:BAABLgAECn9OAAIfAAYJTA9gGgAhAQAfAAYJTA9gGgAhAQAAAA==.Valora:BAABLgAECn9LAAQYAAkJZB1EDQB9AgAYAAkJ8RpEDQB9AgAgAAcJYx04HgC9AQAKAAMJrBaDQADrAAAAAA==.Valoria:BAAALgAECgQJDQAAAA==.Vanille:BAABLgAECn8VAAINAAcJNAYYeQC8AAANAAcJNAYYeQC8AAAAAA==.Vargen:BAABLgAECn8bAAIoAAcJMRg/HwCDAQAoAAcJMRg/HwCDAQAAAA==.Varonika:BAAALgAECgUJEgAAAA==.Vayla:BAABLgAECn8zAAIZAAkJ3huJBwB1AgAZAAkJ3huJBwB1AgAAAA==.',
Ve='Vee:BAAALgAECgEJBAABLgAECgkJGQAFAMoUAA==.Veld:BAAALgAECggJBgAAAA==.Velura:BAAALgAECgYJBgAAAA==.Vengmachine:BAAALgADCgcJCwABLgAECggJJwAaAAQeAA==.Venøm:BAAALgADCgUJBQAAAA==.Vessimyre:BAAALgAECgIJBQAAAA==.',
Vi='Vicunaward:BAAALgAECgUJBQAAAA==.Violet:BAABLgAECn8qAAICAAgJZQveiwA/AQACAAgJZQveiwA/AQAAAA==.',
Vo='Voidofdeath:BAAALgAECgYJEAAAAA==.',
Vr='Vryn:BAAALgADCgEJAQAAAA==.',
Vu='Vula:BAABLgAECn8+AAINAAkJTAMYZQD1AAANAAkJTAMYZQD1AAAAAA==.',
['Vè']='Vèngeance:BAAALgAECgIJAgAAAA==.',
Wa='Wagubagu:BAAALgAECgQJBAAAAA==.Wamdus:BAACLgAFFH8GAAIJAAMJjwy3dgDVAAAJAAMJjwy3dgDVAAAuAAQKfyoAAgkACQk+H60ZAKsCAAkACQk+H60ZAKsCAAAA.Wargrimm:BAABLgAECn8uAAIWAAkJyR5vCQC1AgAWAAkJyR5vCQC1AgAAAA==.Warriovix:BAAALgAECgUJDAAAAA==.Warwizard:BAACLgAFFH8UAAIeAAQJISYNEACgAQAeAAQJISYNEACgAQAuAAQKf14AAx4ACQmfJhIAAPgDAB4ACQmfJhIAAPgDAAIACAkZIF8fAHUCAAAA.',
We='Webin:BAAALgAECgEJBgAAAA==.',
Wh='Whatshisface:BAABLgAECn8bAAIPAAgJRR+EEQBtAgAPAAgJRR+EEQBtAgAAAA==.Whiisp:BAAALgAECgYJCAABLgAECgkJHQARAO4WAA==.Whiisper:BAAALgAECgYJBgABLgAECgkJHQARAO4WAA==.Whispaknight:BAAALgAECgUJBgABLgAECgkJHQARAO4WAA==.Whisperwiind:BAAALgAECgMJAwABLgAECgkJHQARAO4WAA==.Whisperz:BAAALgAECgIJAgABLgAECgkJHQARAO4WAA==.Whizpa:BAABLgAECn8dAAIRAAkJ7ha6FAAWAgARAAkJ7ha6FAAWAgAAAA==.Whizper:BAAALgAECgEJAQABLgAECgkJHQARAO4WAA==.',
Wi='Wickerchickn:BAABLgAECn8ZAAIkAAkJThRpEwCfAQAkAAkJThRpEwCfAQAAAA==.Wiisper:BAAALgADCgYJBgABLgAECgkJHQARAO4WAA==.Wilshammy:BAAALgAECgMJAwAAAA==.Wispy:BAAALgAECgcJEwAAAA==.Wizzelyfink:BAAALgAECgYJBgAAAA==.Wizzy:BAAALgAECgQJDQAAAA==.',
Wo='Wonkyponky:BAAALgAECgEJAQAAAA==.',
Wr='Wrathbarrage:BAAALgAECgkJEwAAAA==.Wrathbourne:BAAALgAECgYJDQABLgAECgkJEwAUAAAAAA==.Wrathchoi:BAAALgAECgYJCwAAAA==.Wrathstorm:BAAALgAECgEJAwABLgAECgkJEwAUAAAAAA==.',
Xb='Xbonez:BAAALgAECgQJBgAAAA==.',
Xe='Xenather:BAAALgAECgMJAwAAAA==.Xerilynn:BAAALgAECgUJDAAAAA==.',
Xi='Xiangfei:BAABLgAECn8nAAMIAAgJux6SMwDhAQAIAAgJzRySMwDhAQAGAAYJxB/5GwCwAQAAAA==.Xilo:BAAALgAECgkJEAAAAA==.',
Xy='Xyloto:BAAALgAECgEJAQABLgAECgYJDQAUAAAAAA==.',
['Xè']='Xèrlyn:BAAALgAECgMJBQAAAA==.',
Ya='Yazlura:BAAALgADCgMJAwAAAA==.',
Ye='Yesimamonk:BAAALgADCgEJAQAAAA==.Yezgraine:BAAALgAECgcJCAAAAA==.',
Yo='Youmightlive:BAAALgAECgUJEwAAAA==.',
Yz='Yzaak:BAAALgAECgEJAQAAAA==.',
Za='Zahona:BAAALgADCgYJCQAAAA==.Zaknefein:BAAALgADCgMJAwAAAA==.',
Ze='Zeddiccus:BAABLgAECn8aAAIJAAkJjRsNMABCAgAJAAkJjRsNMABCAgAAAA==.',
Zi='Ziden:BAAALgAECgYJBgAAAA==.Zidon:BAAALgAECgIJAwAAAA==.Zigral:BAAALgADCgUJBQABLgAECgQJDQAUAAAAAA==.Zirfireballs:BAAALgAECgIJAgAAAA==.Zixgal:BAAALgAECgQJDQAAAA==.',
Zo='Zonzmik:BAAALgADCgcJGAAAAA==.Zorvoth:BAAALgAECgcJDQAAAA==.',
Zu='Zurazaee:BAABLgAECn8ZAAIgAAcJZBQxJACPAQAgAAcJZBQxJACPAQAAAA==.',
['Zî']='Zîth:BAAALgADCgkJCQAAAA==.',
['År']='Årtêmis:BAAALgAECgkJEgAAAA==.',
['Él']='Élle:BAAALgAECgMJBgAAAA==.',
['Ér']='Éric:BAABLgAECn9LAAIkAAkJIhqNBwBhAgAkAAkJIhqNBwBhAgAAAA==.',
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
