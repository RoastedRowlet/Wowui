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

local lookup = {'Monk-Brewmaster','Priest-Discipline','Mage-Frost','Paladin-Retribution','Shaman-Restoration','Druid-Feral','Hunter-Survival','Warrior-Fury','Hunter-BeastMastery','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','DemonHunter-Devourer','DemonHunter-Vengeance','Warlock-Demonology','Shaman-Elemental','Shaman-Enhancement','Warrior-Protection','DeathKnight-Unholy','Paladin-Holy','Paladin-Protection','Druid-Guardian','Unknown-Unknown','Druid-Restoration','Priest-Shadow','Warlock-Destruction','Warlock-Affliction','Hunter-Marksmanship','Monk-Windwalker','Monk-Mistweaver','Druid-Balance','DeathKnight-Blood','Warrior-Arms','DeathKnight-Frost','Rogue-Subtlety','Rogue-Assassination','Mage-Fire','Priest-Holy','Mage-Arcane','DemonHunter-Havoc',}
local provider = {region='US',realm='Antonidas',name='US',type='weekly',zone=46,date='2026-06-20',data={Aa='Aalst:BAABLgAECn8qAAIBAAkJMwpmKABuAQABAAkJMwpmKABuAQAAAA==.',
Ac='Achillesheal:BAABLgAECn8ZAAICAAYJoR8SFAAMAgACAAYJoR8SFAAMAgAAAA==.Acidicwrath:BAAALgADCgUJBQAAAA==.Acnologias:BAAALgAECgEJAQABLgAECggJJAADAIoUAA==.Acshec:BAAALgADCgYJDgABLgAECgcJJAAEABcbAA==.Acuna:BAAALgAECgcJCQAAAA==.',
Ad='Aderna:BAAALgADCgMJBAAAAA==.Adoryn:BAEBLgAECn9DAAIBAAkJ6RCdHADAAQABAAkJ6RCdHADAAQAAAA==.',
Ae='Aervyper:BAAALgADCgIJAwAAAA==.Aessan:BAAALgAECgEJAQABLgAECgkJLgAFAGQNAA==.',
Ag='Aggrenox:BAABLgAECn8iAAIEAAgJgAjHtwAUAQAEAAgJgAjHtwAUAQAAAA==.',
Ai='Aisathya:BAABLgAECn8iAAIDAAkJ0CPQCgAjAwADAAkJ0CPQCgAjAwAAAA==.',
Ak='Akiza:BAAALgAECgkJDwAAAA==.Akonorix:BAAALgADCgUJCAAAAA==.',
Al='Alaelis:BAAALgAECgYJCAAAAA==.Albina:BAAALgAECgUJEwAAAA==.Aldelvir:BAABLgAECn8VAAIDAAgJAwU1uQAUAQADAAgJAwU1uQAUAQABLgAECgkJPAAGAD4aAA==.Alottarage:BAAALgADCgcJCQAAAA==.Alunantre:BAABLgAECn8aAAIHAAkJ6BQ5GwDEAQAHAAkJ6BQ5GwDEAQAAAA==.Alzhimers:BAABLgAECn8UAAIIAAgJLhNTLgCXAQAIAAgJLhNTLgCXAQAAAA==.',
Am='Amberfox:BAABLgAFFH8FAAIJAAQJAQ72AwAxAQAJAAQJAQ72AwAxAQAAAA==.Amberscale:BAACLgAFFH8TAAIKAAQJfRjfKQAhAQAKAAQJfRjfKQAhAQAuAAQKfy4ABAoACQkxHL0NAIQCAAoACQkxHL0NAIQCAAsAAwlfHXoQAAMBAAwAAQm3FYo4AEIAAAAA.Amuela:BAAALgADCgYJBgAAAA==.Amyrrin:BAABLgAECn8cAAIEAAgJ3RISfAB2AQAEAAgJ3RISfAB2AQAAAA==.',
An='Ancientiur:BAABLgAECn8dAAMNAAkJdBtZOQDhAQANAAkJUhlZOQDhAQAOAAMJ+RLCJgBrAAAAAA==.Andazaren:BAAALgAECgcJBwAAAA==.Andormu:BAAALgADCgYJBQAAAA==.Andracca:BAABLgAECn8aAAMKAAgJVxNpLACLAQAKAAgJSBJpLACLAQALAAQJnxUjEgDoAAAAAA==.Angrulus:BAABLgAECn9CAAIJAAkJMiF8CQANAwAJAAkJMiF8CQANAwAAAA==.Animal:BAAALgAECgQJCQAAAA==.Animlshiftr:BAABLgAECn8jAAIGAAgJrg22GABKAQAGAAgJrg22GABKAQAAAA==.',
Ap='Apollo:BAABLgAECn82AAIPAAkJMwwAAgAeAQAPAAkJMwwAAgAeAQAAAA==.',
Ar='Aradunn:BAACLgAFFH8cAAIFAAUJ5CT8DAAKAgAFAAUJ5CT8DAAKAgAuAAQKfyYABAUACQk3IvsGAAQDAAUACQk3IvsGAAQDABAAAwkkHVdQAPYAABEAAgmeI8UzAGEAAAAA.Araedis:BAABLgAECn89AAIHAAkJ/xAxFAADAgAHAAkJ/xAxFAADAgAAAA==.Araelle:BAAALgAECgEJAQAAAA==.Archangel:BAAALgAECgYJCwAAAA==.Arrill:BAEALgAECgMJAwABLgAECggJGwASAP0JAA==.Artheren:BAAALgAECgQJBgAAAA==.Aryllyn:BAAALgADCgcJFAAAAA==.',
As='Ashvehtta:BAABLgAECn8bAAITAAkJ5Qy7WAC7AQATAAkJ5Qy7WAC7AQAAAA==.Assaelysia:BAAALgAECgIJAgAAAA==.Asstormrage:BAAALgADCgUJBQAAAA==.Asti:BAAALgAECgcJDgAAAA==.Astralon:BAAALgAECgIJAwAAAA==.',
At='Atharion:BAABLgAECn8mAAMUAAkJch0oEACXAgAUAAgJpR4oEACXAgAEAAYJjhY3tAAZAQAAAA==.Atheus:BAAALgADCgEJAgAAAA==.',
Av='Avanda:BAAALgAECgEJBQAAAA==.Avaria:BAAALgAECgIJAgAAAA==.Avrassa:BAAALgADCgMJAwAAAA==.',
Aw='Awperprime:BAABLgAECn8tAAIRAAkJ/Rd3CAA9AgARAAkJ/Rd3CAA9AgAAAA==.',
Ay='Ayhanui:BAAALgAECgEJAgAAAA==.',
Az='Azrathalos:BAABLgAECn8eAAQUAAcJLBThNwBuAQAUAAYJuhPhNwBuAQAEAAUJEAUXHwGUAAAVAAEJkwM5VgAkAAAAAA==.Azémstraza:BAAALgAECgYJDAAAAA==.',
Ba='Bained:BAAALgADCgcJBwAAAA==.Baldric:BAABLgAECn8vAAIJAAgJRB28KAA8AgAJAAgJRB28KAA8AgAAAA==.Balinor:BAABLgAECn8dAAIUAAcJLQ7YPABTAQAUAAcJLQ7YPABTAQABLgAECgkJMQASAJ4dAA==.Bank:BAAALgADCgcJBwAAAA==.',
Be='Bearett:BAABLgAECn9NAAIWAAkJTSMrAgAjAwAWAAkJTSMrAgAjAwAAAA==.Beefcakezear:BAAALgADCgQJBAAAAA==.Belyfrost:BAACLgAFFH8IAAIDAAMJUAcqjADBAAADAAMJUAcqjADBAAAuAAQKfxQAAgMACQmFDIB+AHsBAAMACQmFDIB+AHsBAAAA.Belylight:BAAALgAECgkJEAABLgAFFAIJBAAXAAAAAA==.Belymoon:BAAALgAFFAIJBAAAAA==.Belyreaper:BAAALgAECgUJBgABLgAFFAIJBAAXAAAAAA==.Bennz:BAAALgAECgYJBgAAAA==.Beriotyr:BAAALgADCgQJAwAAAA==.Bernd:BAABLgAECn8nAAIWAAkJ6Qv6JQAkAQAWAAkJ6Qv6JQAkAQAAAA==.Beörn:BAABLgAECn8zAAIYAAkJkyP8AgCZAwAYAAkJkyP8AgCZAwAAAA==.',
Bi='Biggiy:BAAALgAECgEJAQAAAA==.Bigsniffy:BAAALgADCgQJBAAAAA==.Birgir:BAAALgAECgUJBQAAAA==.',
Bl='Blackbeard:BAAALgAECgEJAQABLgAECgkJMQASAJ4dAA==.Blackgrinn:BAABLgAECn8jAAMCAAgJJw+6KACNAQACAAgJJw+6KACNAQAZAAcJRwauSQDpAAAAAA==.Blackkgrin:BAAALgADCgQJCgAAAA==.Blasphemous:BAABLgAECn8dAAITAAcJgBQ8jABMAQATAAcJgBQ8jABMAQAAAA==.Blasé:BAABLgAECn8yAAQPAAgJESAUIgBZAgAPAAgJESAUIgBZAgAaAAEJAACjXABZAAAbAAEJghI/OgBAAAABLgAFFAMJBAAXAAAAAA==.Blazéoné:BAAALgAECgUJBgAAAA==.Blessin:BAAALgAECgcJCgAAAA==.',
Bo='Bobo:BAAALgAECgUJEQAAAA==.Bobrossx:BAACLgAFFH8FAAMcAAIJ7xKHHQCgAAAcAAIJ7xKHHQCgAAAJAAIJNQhtkQB8AAAuAAQKfywABBwACAmZIZcNANgCABwACAkUHpcNANgCAAcABwnXHVcdALEBAAkAAgl9HknkAIYAAAAA.Bobsmonk:BAAALgADCgEJAQAAAA==.Bomi:BAAALgADCgQJBAAAAA==.Boostéd:BAABLgAECn8XAAITAAcJdR3VSAAZAgATAAcJdR3VSAAZAgAAAA==.Boostëd:BAAALgAECgYJBwABLgAECgcJFwATAHUdAA==.Bowyoncè:BAAALgAFFAMJAwAAAA==.',
Br='Brakevilt:BAAALgAECgcJBwAAAA==.Brattyone:BAAALgADCgcJBwAAAA==.Breadcrums:BAAALgADCgMJAwAAAA==.Brewagool:BAAALgAECgMJAwAAAA==.Bruche:BAABLgAECn8vAAITAAkJLh+PHwCLAgATAAkJLh+PHwCLAgAAAA==.Brujaah:BAAALgAECgYJBgABLgAECgkJOgAXAAAAAQ==.Brynhilldr:BAAALgAECgEJAQAAAA==.Brynthadia:BAAALgAECgYJCAAAAA==.Brzrker:BAAALgADCgYJDAAAAA==.',
Bu='Bubagumps:BAAALgAECgEJAQAAAA==.Burkaeus:BAAALgAECgEJAQAAAA==.',
Bw='Bwca:BAACLgAFFH8HAAIJAAMJ9A6baQDSAAAJAAMJ9A6baQDSAAAuAAQKfxQAAgkABQkjHIFiAIEBAAkABQkjHIFiAIEBAAEuAAUUAwkPAAUABAgA.',
Ca='Caine:BAABLgAECn8xAAISAAkJnh28CwAxAgASAAkJnh28CwAxAgAAAA==.Cakébob:BAAALgADCgQJBQAAAA==.Calmdown:BAAALgADCgYJBwAAAA==.Carraa:BAAALgADCgYJCgABLgAECgkJLgAFAGQNAA==.Casey:BAABLgAECn8uAAIEAAgJZgaJvQAMAQAEAAgJZgaJvQAMAQAAAA==.Castyblasty:BAAALgAECgEJAQAAAA==.Cataaria:BAABLgAECn8uAAIFAAkJZA3TAQA9AQAFAAkJZA3TAQA9AQAAAA==.',
Ce='Cellina:BAABLgAECn8oAAMdAAkJWBEoKQByAQAdAAkJWBEoKQByAQABAAYJHwa/UwC2AAAAAA==.Cerathal:BAAALgADCgIJAgAAAA==.Ceriumz:BAAALgAECgYJCwABLgAECggJJAADAIoUAA==.',
Cf='Cfourtylock:BAABLgAECn8oAAQPAAkJfBdhUQCnAQAPAAgJrRVhUQCnAQAbAAYJcRUlEQAbAQAaAAEJ7wVOeQAqAAAAAA==.',
Ch='Chaniqua:BAAALgADCgQJBQAAAA==.Chiman:BAABLgAECn8VAAMeAAYJihHoTAA5AQAeAAYJihHoTAA5AQAdAAUJZgvVVwCwAAAAAA==.Chronophage:BAAALgAECgUJBQAAAA==.Chûd:BAEALgAECgUJBQAAAA==.',
Ci='Ciders:BAAALgAECgEJAQABLgAECgkJIgAHABoWAA==.',
Cl='Clasastrasza:BAAALgAECgUJCgABLgAFFAQJDwAYAMsaAA==.Classá:BAACLgAFFH8PAAMYAAQJyxquIwA8AQAYAAQJyxquIwA8AQAfAAMJzhU2MQC9AAAuAAQKf0oABB8ACQm2IskHANoCAB8ACAnfJMkHANoCABgABwmhIMlGAIcBABYAAQmYFxpsAD4AAAAA.Clawz:BAABLgAFFH8GAAIGAAIJih2QEQCuAAAGAAIJih2QEQCuAAABLgAFFAMJCQAEAD0eAA==.',
Co='Codedd:BAACLgAFFH8GAAIYAAIJYwbHXgBeAAAYAAIJYwbHXgBeAAAuAAQKfxoAAhgABwl5EJJPAFEBABgABwl5EJJPAFEBAAAA.Commit:BAAALgAECggJDgAAAA==.Comradeprime:BAAALgAECgUJDwAAAA==.Corlys:BAABLgAECn8sAAMEAAkJDCLtFwCzAgAEAAkJ/yDtFwCzAgAVAAYJgB1eEgChAQABLgAFFAIJBQADAG0DAA==.Covi:BAAALgAECgEJAQAAAA==.',
Cr='Crismonguard:BAAALgAECgcJBwAAAA==.Crispìn:BAABLgAECn8WAAIJAAcJswY7qwDsAAAJAAcJswY7qwDsAAAAAA==.Crossbones:BAAALgAECgQJDQAAAA==.Crue:BAABLgAECn8oAAIYAAgJQw8yAQBGAQAYAAgJQw8yAQBGAQAAAA==.',
Cu='Curthar:BAACLgAFFH8JAAIEAAMJPR67ZADlAAAEAAMJPR67ZADlAAAuAAQKfyAAAxUACQkUJfkAAFMDABUACQkUJfkAAFMDAAQABgmgHkh9AHQBAAAA.',
Cy='Cyguy:BAAALgAECgEJAQAAAA==.Cynboom:BAAALgAECgkJAQAAAA==.Cyndee:BAABLgAECn9EAAIIAAkJpBj7AABkAQAIAAkJpBj7AABkAQAAAA==.Cynnafrost:BAAALgAECgQJBgAAAA==.Cytenk:BAAALgADCgYJBgAAAA==.',
Da='Dadda:BAABLgAECn9NAAIcAAkJniHfAQDtAgAcAAkJniHfAQDtAgAAAA==.Dallas:BAAALgADCgcJBwAAAA==.Damascus:BAAALgAECgYJCwABLgAECggJLwAJAEQdAA==.Dankmonk:BAABLgAECn8yAAIBAAgJUhb7GwDFAQABAAgJUhb7GwDFAQAAAA==.Darcnis:BAAALgADCgkJGwAAAA==.Darielea:BAAALgADCgIJAgAAAA==.Darkfury:BAABLgAECn85AAINAAkJrwmrZgBZAQANAAkJrwmrZgBZAQAAAA==.Darklasminth:BAAALgAFFAIJAgAAAA==.Darkschi:BAAALgAECgQJCAAAAA==.Darthwang:BAABLgAECn8fAAIPAAYJ6BjsWgC3AQAPAAYJ6BjsWgC3AQAAAA==.Darthwing:BAAALgAECgMJAwABLgAECgYJHwAPAOgYAA==.Dartos:BAACLgAFFH8JAAITAAIJbiMnrgDFAAATAAIJbiMnrgDFAAAuAAQKf1AAAhMACQl6JTIDAGwDABMACQl6JTIDAGwDAAAA.',
De='Deadlysmash:BAAALgADCgMJAwAAAA==.Deathratio:BAAALgADCgcJBwAAAA==.Deathsbff:BAAALgADCgEJAQABLgAFFAgJGQADAHMUAA==.Deathsend:BAAALgAECggJCAAAAA==.Debluddk:BAABLgAECn8tAAIgAAkJIyFDBADyAgAgAAkJIyFDBADyAgAAAA==.Deep:BAAALgAECgQJBAABLgAECgkJJQAeALMgAA==.Deepfister:BAABLgAECn8lAAIeAAkJsyCQCAASAwAeAAkJsyCQCAASAwAAAA==.Deeplydivine:BAAALgAECgIJAgABLgAECgkJJQAeALMgAA==.Demone:BAAALgADCgMJAwAAAA==.',
Di='Dic:BAAALgAECgcJCgAAAA==.Dillpickle:BAAALgADCgcJBwAAAA==.Diluvium:BAABLgAECn8oAAIEAAkJNRJtVgDIAQAEAAkJNRJtVgDIAQAAAA==.Discodank:BAAALgAECgMJBAAAAA==.',
Dj='Djpleasant:BAACLgAFFH8YAAIDAAUJIxL2XwAhAQADAAUJIxL2XwAhAQAuAAQKfzUAAgMACQnCHfAfAJ8CAAMACQnCHfAfAJ8CAAAA.',
Dk='Dktelmtwo:BAABLgAECn8fAAIgAAkJZR4FBwCtAgAgAAkJZR4FBwCtAgAAAA==.',
Do='Doneisha:BAAALgAECgQJCQAAAA==.Dontcare:BAABLgAFFH8QAAMHAAUJZhWuAQD2AAAHAAUJ5xGuAQD2AAAJAAQJ5BMFbADMAAAAAA==.Downhammer:BAAALgAECgkJBQAAAA==.',
Dr='Dractelm:BAAALgADCgEJAQABLgAECgcJJAAEABcbAA==.Drakamar:BAABLgAECn87AAQLAAkJQAOwFQC4AAAKAAkJkgI9XwC8AAALAAgJ8gKwFQC4AAAMAAYJMAIELgB6AAAAAA==.Dranith:BAAALgAECgQJBAAAAA==.Dronos:BAACLgAFFH8LAAIfAAMJhBf1LQDPAAAfAAMJhBf1LQDPAAAuAAQKf0AAAh8ACQkvJFsCAFADAB8ACQkvJFsCAFADAAAA.',
Du='Dunzledorf:BAAALgAECgcJBwAAAA==.',
Dy='Dynammes:BAABLgAECn8jAAIDAAgJxhg5SgD8AQADAAgJxhg5SgD8AQABLgAFFAQJBwAIABMgAA==.',
Ea='Eaglej:BAAALgAECgkJCAAAAA==.Eatmorpizza:BAAALgAECgUJEAAAAA==.',
Eb='Ebore:BAAALgADCggJDQAAAA==.',
Ee='Eegorn:BAAALgAECgYJCgAAAA==.Eegroll:BAACLgAFFH8VAAIBAAYJ+hvlEgCMAQABAAYJ+hvlEgCMAQAuAAQKfxgAAwEACAmlHKceALEBAB0ABwkpF+kjALcBAAEABQm9H6ceALEBAAAA.',
Eg='Egraw:BAAALgAECgQJBAAAAA==.',
El='Elementals:BAABLgAECn8UAAIQAAYJlhiQNgBfAQAQAAYJlhiQNgBfAQAAAA==.Elixera:BAAALgAECgEJAQAAAA==.Elsä:BAAALgAECgUJAQAAAA==.Elémental:BAAALgAECgkJEQAAAA==.',
Em='Emilwhaury:BAAALgAECgYJDwAAAA==.',
Ep='Epia:BAABLgAECn8lAAMdAAgJyw+9MQA/AQAdAAgJwQ29MQA/AQABAAMJUBN1VQCxAAAAAA==.',
Er='Eriena:BAAALgAECgYJEQAAAA==.',
Es='Esbjorn:BAAALgAECgEJAgAAAA==.Essaila:BAABLgAECn9BAAIGAAkJihEADwDFAQAGAAkJihEADwDFAQAAAA==.',
Et='Etheo:BAAALgAECgEJAQAAAA==.Etherwalker:BAABLgAECn8mAAMIAAkJPyRFDAClAgAIAAgJTyRFDAClAgAhAAQJix9LKQAoAQAAAA==.',
Ev='Evocati:BAACLgAFFH8HAAITAAMJjxgkjQDwAAATAAMJjxgkjQDwAAAuAAQKfxgAAyIABgnbF8ETAEABACIABgneFcETAEABABMABgkZF46sABkBAAEuAAUUBwkQAAQAkBYA.Evoka:BAABLgAECn8lAAMLAAgJjR7yDAAMAgALAAcJVx/yDAAMAgAKAAYJWRuPMgBqAQABLgAECgkJLQAgACMhAA==.',
Ex='Excision:BAABLgAECn8qAAMKAAgJyA4ORwAOAQALAAcJcw2yHgA5AQAKAAcJIQ0ORwAOAQAAAA==.Exmachina:BAAALgADCgYJBgAAAA==.',
Fa='Fahbio:BAABLgAECn8jAAIVAAgJcQJDLwCrAAAVAAgJcQJDLwCrAAAAAA==.Fataliny:BAAALgADCgUJCAAAAA==.Fatallock:BAACLgAFFH8HAAIPAAMJ9wQnjACtAAAPAAMJ9wQnjACtAAAuAAQKf0AAAw8ACQlxEyA6APIBAA8ACQlxEyA6APIBABsAAQlpCL4/ADMAAAAA.Fatlife:BAAALgAECgMJAwAAAA==.',
Fi='Fishdish:BAAALgAECgIJAgAAAA==.Fistsmither:BAAALgAECgYJCAABLgAECgkJJAAjAPwTAA==.Fivevolts:BAABLgAECn8pAAIkAAkJDCTpAAAsAwAkAAkJDCTpAAAsAwAAAA==.',
Fl='Fladon:BAAALgADCgEJAQAAAA==.Flailuid:BAAALgAECgQJDgAAAA==.Flimfam:BAAALgAECgEJAQAAAA==.',
Fo='Forkin:BAAALgADCgIJAgAAAA==.Forthstryke:BAAALgAECgIJBwAAAA==.Four:BAAALgADCgUJBQAAAA==.Fozzi:BAAALgAECgYJCwAAAA==.',
Fr='Freddyg:BAAALgADCgMJBAAAAA==.Fridaychill:BAACLgAFFH8OAAIdAAQJvhwXDgBOAQAdAAQJvhwXDgBOAQAuAAQKfzQAAh0ACAm5ImgLAI0CAB0ACAm5ImgLAI0CAAAA.Fries:BAEALgAECgEJAQABLgAFFAUJCgARAP8eAA==.Frostdeeps:BAAALgAECgcJEwAAAA==.Frozarke:BAABLgAECn8tAAIKAAgJng+JNgBWAQAKAAgJng+JNgBWAQABLgAECgkJEAAXAAAAAA==.',
Fu='Fudd:BAABLgAECn8pAAIJAAkJHRr3HQByAgAJAAkJHRr3HQByAgAAAA==.Funk:BAAALgAECgIJAwABLgAECgQJCQAXAAAAAA==.Fupa:BAABLgAECn8tAAIJAAkJsQxhZgB3AQAJAAkJsQxhZgB3AQAAAA==.',
Ga='Gaiaslieg:BAAALgAECgEJAQAAAA==.Galand:BAAALgAECgYJBgAAAA==.Galathynius:BAAALgADCgUJBQAAAA==.Galeine:BAAALgADCgMJAwAAAA==.Gangplank:BAAALgADCgMJAwAAAA==.Garres:BAABLgAECn8dAAMGAAcJuh+1DADrAQAGAAcJuh+1DADrAQAWAAEJXQpSCAAhAAAAAA==.',
Ge='Genius:BAABLgAECn8bAAIhAAcJUBs1GACZAQAhAAcJUBs1GACZAQAAAA==.Gennosuke:BAAALgADCgcJBQAAAA==.',
Gh='Gherkin:BAAALgADCgEJAQAAAA==.Ghostkillaz:BAAALgADCgkJFwAAAA==.Ghostxkillaz:BAAALgADCgMJAwAAAA==.',
Gi='Gibley:BAABLgAECn8XAAIEAAgJ0BjlfgB8AQAEAAgJ0BjlfgB8AQAAAA==.',
Gl='Gladorf:BAAALgADCgYJBgAAAA==.',
Gn='Gnazgul:BAAALgAECggJEgAAAA==.Gnomad:BAABLgAECn8lAAIDAAcJwwPE4QDYAAADAAcJwwPE4QDYAAAAAA==.Gnomie:BAAALgAFFAEJAgAAAA==.Gnomio:BAAALgAFFAEJAgAAAA==.',
Go='Goat:BAAALgAECgYJDwAAAA==.Gouge:BAAALgAECgkJOgAAAQ==.',
Gr='Gravess:BAAALgAFFAIJAgAAAA==.Griffynshu:BAABLgAECn8oAAIYAAkJlBvVEwCtAgAYAAkJlBvVEwCtAgAAAA==.Griz:BAAALgAECgcJEgAAAA==.Grizzlyburr:BAABLgAECn8UAAIWAAcJjxJMJAAuAQAWAAcJjxJMJAAuAQABLgAFFAUJCQAFAPgbAA==.Grunewald:BAABLgAECn9nAAIJAAkJxw+bQQDdAQAJAAkJxw+bQQDdAQAAAA==.',
Gu='Guinn:BAAALgADCgIJAgABLgAECgkJEAAXAAAAAA==.Gula:BAABLgAECn8hAAMbAAkJPxU/CQCxAQAbAAYJHRc/CQCxAQAPAAkJKBS9UwChAQAAAA==.Guldanshower:BAAALgADCgUJBQAAAA==.Gunhild:BAAALgAECgIJAgAAAA==.Gutdiver:BAAALgADCgUJBQAAAA==.',
Ha='Handiboyswag:BAACLgAFFH8eAAICAAUJjCEcAgBvAQACAAUJjCEcAgBvAQAuAAQKfxkAAxkABwm4E5QgANQBABkABwm4E5QgANQBAAIABAnJIhYwAB8BAAAA.Hando:BAAALgAECgYJCAAAAA==.Hattock:BAAALgADCgcJFQAAAA==.Hayate:BAAALgAECgUJBQAAAA==.',
He='Heavyshlump:BAACLgAFFH8IAAIBAAQJ0Q52KgD/AAABAAQJ0Q52KgD/AAAuAAQKfyEAAgEACQnOFVcSACICAAEACQnOFVcSACICAAEuAAUUBQkJAAUA+BsA.Hehateme:BAAALgAECgIJAgAAAA==.Hehexd:BAABLgAECn8pAAIjAAgJARvUEwB3AgAjAAgJARvUEwB3AgAAAA==.Heimdall:BAACLgAFFH8HAAIUAAMJgw3FMQCsAAAUAAMJgw3FMQCsAAAuAAQKfyEAAhQACAmOH8gMAMMCABQACAmOH8gMAMMCAAAA.Hellavva:BAAALgAECgMJAwAAAA==.Hellzwar:BAAALgADCgUJBgAAAA==.Hench:BAAALgAECgYJBgAAAA==.Henchling:BAABLgAECn9FAAMFAAkJGyApCQDkAgAFAAkJGyApCQDkAgAQAAkJaRJtJQC+AQAAAA==.Henchragon:BAAALgADCgUJBQAAAA==.',
Hi='Hissteria:BAAALgAECgIJAwAAAA==.',
Hn='Hngyhngyloko:BAABLgAECn8ZAAIDAAcJzxt5bQD6AQADAAcJzxt5bQD6AQABLgAFFAMJCAAKAOYUAA==.',
Ho='Hoerified:BAAALgADCgEJAQABLgAECggJKQAjAAEbAA==.Holexios:BAAALgAECgQJCQABLgAECgYJFQAeAIoRAA==.Holybonks:BAAALgADCgcJBwAAAA==.Holycanoli:BAAALgAECgEJAgAAAA==.Holycrusade:BAAALgAECgUJCgAAAA==.Horine:BAABLgAECn8rAAIJAAgJEw9jXwCJAQAJAAgJEw9jXwCJAQAAAA==.Hotsteve:BAAALgAECgQJBwAAAA==.',
Hu='Huntrix:BAAALgAECgIJAgAAAA==.Huntër:BAAALgAECgQJBQAAAA==.Huruk:BAAALgAECgIJAgAAAA==.',
Hy='Hydranis:BAAALgADCgUJBQAAAA==.',
Ic='Icieblade:BAAALgAECgkJEQAAAA==.Icyscorcher:BAABLgAECn8kAAMDAAgJihTIXQDFAQADAAgJihTIXQDFAQAlAAMJpwOyCwB3AAAAAA==.',
Id='Idroptotems:BAAALgADCgMJAwABLgAECgcJJAAEABcbAA==.',
Ik='Ikairi:BAAALgAECgEJAQAAAA==.',
Il='Illidankness:BAAALgAECgQJBAAAAA==.Illidoran:BAAALgAECgYJDQABLgAFFAQJFQADALQbAA==.',
Im='Imdatank:BAAALgADCgYJCAABLgAECggJHwAEAKQSAA==.Immeira:BAABLgAECn8fAAIFAAcJNA+6UABvAQAFAAcJNA+6UABvAQAAAA==.Immkicky:BAAALgADCgEJAQAAAA==.',
In='Intense:BAAALgAECgcJAwAAAA==.',
Ja='Jackcsi:BAAALgAECggJCgABLgAFFAMJEAAYAHseAA==.Jackheals:BAACLgAFFH8QAAIYAAMJex69KwAIAQAYAAMJex69KwAIAQAuAAQKfzUAAxgACAnLIh0KABoDABgACAnLIh0KABoDAB8AAQnZAdqPABsAAAAA.Jackiix:BAAALgADCgcJBwAAAA==.Jacktides:BAAALgADCgQJBQABLgAFFAMJEAAYAHseAA==.Jaehaerys:BAAALgAECgQJCAABLgAFFAIJBQADAG0DAA==.Jagseer:BAAALgAECgQJBAABLgAECgkJMAACAPUcAA==.',
Jb='Jblackly:BAAALgAECgYJCQAAAA==.',
Jc='Jcdhizzle:BAAALgAECgEJAQAAAA==.',
Jf='Jfreeman:BAAALgADCgYJBwAAAA==.',
Ji='Jimzdrood:BAAALgAECgEJAQAAAA==.Jinbeyblade:BAAALgAECgMJAwABLgAFFAMJEAAJAG0iAA==.Jinphoenix:BAACLgAFFH8QAAIJAAMJbSJcRAAlAQAJAAMJbSJcRAAlAQAuAAQKfycAAwkACQlrIUENAOgCAAkACQlrIUENAOgCABwABAmQB4xfAMMAAAAA.Jitb:BAAALgADCgYJBwABLgAFFAcJEQAeAJYMAA==.',
Jo='Jobin:BAACLgAFFH8PAAMTAAMJ4BI5qADMAAATAAMJ4BI5qADMAAAiAAEJSAEELgAwAAAuAAQKfxkAAhMACAn5G0twAKgBABMACAn5G0twAKgBAAAA.Joldada:BAAALgAECgkJCAAAAA==.Journei:BAABLgAECn82AAIFAAkJWBbFAADjAQAFAAkJWBbFAADjAQAAAA==.',
Ju='Juanito:BAAALgAECgYJCAAAAA==.Judging:BAABLgAECn8tAAMUAAkJDRdCGABGAgAUAAkJDRdCGABGAgAEAAIJHSWJ8wDGAAAAAA==.Junkhead:BAAALgAECgUJBwAAAA==.',
Ka='Kaethe:BAAALgAECgYJBgAAAA==.Kaiduo:BAAALgADCgEJAQAAAA==.Kaitos:BAAALgAFFAIJBAABLgAFFAMJCQAEAD0eAA==.Kalmas:BAABLgAFFH8MAAIfAAMJHAj4NgCiAAAfAAMJHAj4NgCiAAAAAA==.Kateana:BAAALgAECgcJEwAAAA==.',
Ke='Kegz:BAAALgADCggJCAABLgAECgkJMAACAPUcAA==.Kelendrian:BAAALgAECgUJBQAAAA==.Kellayna:BAABLgAECn8xAAIEAAkJIQlJBQDJAAAEAAkJIQlJBQDJAAAAAA==.Kennyx:BAAALgAECgMJAwAAAA==.Kerine:BAAALgAECgMJBAAAAA==.Ketchup:BAAALgADCgIJAwAAAA==.Keylö:BAAALgAFFAEJAQAAAA==.Kezix:BAABLgAECn8eAAIPAAkJlA40UwCiAQAPAAkJlA40UwCiAQAAAA==.',
Kh='Kharigosa:BAAALgAECgEJAQABLgAECggJFgAUAH8ZAA==.',
Ki='Kigerstorm:BAAALgADCgEJAQAAAA==.Kimeltoe:BAAALgADCgIJAgAAAA==.Kimigosa:BAABLgAECn8nAAQKAAgJfhGoIwChAQAKAAgJvA+oIwChAQALAAIJ7gt4JgAyAAAMAAEJwQF4TgAiAAABLgAFFAMJAwAXAAAAAA==.Kimpachi:BAAALgAECgcJCAABLgAFFAMJAwAXAAAAAA==.',
Kl='Klerik:BAACLgAFFH8WAAIPAAYJoBISUwAgAQAPAAYJoBISUwAgAQAuAAQKfykABA8ACQkaH5wfAGcCAA8ACQmyHZwfAGcCABoAAgkpEmxMAIgAABsAAQlxJE41AE4AAAAA.',
Kn='Kníghtmare:BAAALgAECgYJDwAAAA==.',
Ko='Kolesnikov:BAAALgAECgUJCAAAAA==.Koragg:BAACLgAFFH8wAAIgAAYJ8yAvCwDLAQAgAAYJ8yAvCwDLAQAuAAQKfz4AAiAACQnwJbgCAB0DACAACQnwJbgCAB0DAAAA.Kore:BAABLgAECn8jAAIYAAYJZBaLSABtAQAYAAYJZBaLSABtAQAAAA==.Korrag:BAAALgAECgUJCgAAAA==.Kozarke:BAABLgAECn8tAAILAAkJxBYwBQASAgALAAkJxBYwBQASAgAAAA==.',
Kp='Kpop:BAABLgAECn8hAAMOAAkJ3Rn8BwD6AQAOAAkJ3Rn8BwD6AQANAAEJbg4nHgEsAAABLgAFFAUJCQAFAPgbAA==.',
Kr='Krissia:BAABLgAECn8iAAITAAkJhhh9UgDMAQATAAkJhhh9UgDMAQAAAA==.',
Ku='Kumadbear:BAAALgADCgEJAQAAAA==.',
Ky='Kyntaliia:BAAALgAECgQJBAAAAA==.',
['Kí']='Kítsuñe:BAAALgAECgMJAwAAAA==.',
['Kî']='Kîn:BAABLgAECn8oAAINAAkJihSDNAD0AQANAAkJihSDNAD0AQAAAA==.',
La='Ladriana:BAAALgADCgEJAgAAAA==.Laisera:BAABLgAECn8zAAMmAAkJmRAIJwCNAQAmAAkJmRAIJwCNAQAZAAEJdQadlAAmAAAAAA==.Lalipop:BAABLgAECn87AAImAAkJBRrkDQCIAgAmAAkJBRrkDQCIAgAAAA==.Landroval:BAABLgAECn8oAAIKAAkJKRnWEQBVAgAKAAkJKRnWEQBVAgAAAA==.Lauma:BAACLgAFFH8PAAIFAAMJBAhRYACKAAAFAAMJBAhRYACKAAAuAAQKfxUAAgUABwmwEqVMAH4BAAUABwmwEqVMAH4BAAAA.Lawson:BAABLgAECn86AAITAAkJYxxoIACHAgATAAkJYxxoIACHAgAAAA==.',
Le='Lelora:BAAALgAECgUJCQAAAA==.Lenthaden:BAABLgAECn86AAMPAAkJOBiqMQASAgAPAAkJDBaqMQASAgAaAAYJqxNeJQAyAQAAAA==.Lexusis:BAAALgADCgIJAgAAAA==.',
Li='Lightsmasher:BAAALgAECgEJAQAAAA==.Lihaeh:BAAALgADCgEJAQAAAA==.Lildipper:BAAALgAECgcJDQABLgAFFAUJCQAFAPgbAA==.Lio:BAABLgAECn8UAAITAAYJtAkcvgAAAQATAAYJtAkcvgAAAQAAAA==.Lissetteliz:BAAALgAECgQJBQAAAA==.Livdangerous:BAAALgADCgUJBQAAAA==.',
Lo='Locks:BAAALgAECgEJAQAAAA==.Lomax:BAAALgAECgEJAQAAAA==.Longlegs:BAAALgADCgYJBgAAAA==.',
Lu='Lumawig:BAAALgAECgUJDQAAAA==.Lumillras:BAAALgADCgYJCgAAAA==.Lunchdk:BAACLgAFFH8NAAMgAAMJOhebDgCAAAATAAIJJR4EzQCVAAAgAAIJBwybDgCAAAAuAAQKfysAAxMACQmOH20WAMACABMACAl2I20WAMACACAACAlzF2gVALwBAAAA.',
Ly='Lyreth:BAABLgAECn8pAAIfAAkJJRCpJQCfAQAfAAkJJRCpJQCfAQAAAA==.',
Ma='Madax:BAACLgAFFH8HAAIIAAQJEyAiEQB9AQAIAAQJEyAiEQB9AQAuAAQKf0UAAxIACQm+Iz8DAAUDABIACQnMIT8DAAUDAAgACQlnISwLALQCAAAA.Mageymutt:BAACLgAFFH8ZAAIDAAgJcxRbDAC7AQADAAgJcxRbDAC7AQAuAAQKfyUAAwMACAmNIKElANwCAAMACAmNIKElANwCACcAAwkmCx8UAIQAAAAA.Maggidabeast:BAABLgAECn8vAAIDAAgJKQixnABBAQADAAgJKQixnABBAQAAAA==.Magnion:BAAALgAECgEJAQAAAA==.Maison:BAAALgAECgQJCQAAAA==.Malase:BAAALgADCgUJAwAAAA==.Maloch:BAAALgADCgUJBQAAAA==.',
Me='Meaculpa:BAAALgADCgUJCgAAAA==.Megamilk:BAACLgAFFH8TAAIiAAUJaQ+LDwAcAQAiAAUJaQ+LDwAcAQAuAAQKfz0AAiIACQkfG2MGAEECACIACQkfG2MGAEECAAAA.Mekri:BAAALgADCgYJBwABLgAECgcJJAAEABcbAA==.Melledreaux:BAAALgADCgMJAwAAAA==.Metrolinea:BAACLgAFFH8aAAIDAAUJKB5TCAD5AAADAAUJKB5TCAD5AAAuAAQKfzkAAgMACQkqH+8UANwCAAMACQkqH+8UANwCAAAA.',
Mi='Micalknight:BAAALgAECgIJAQAAAA==.Milliy:BAAALgAECgQJBwAAAA==.Minamel:BAAALgADCgMJAwABLgAECgcJJAAEABcbAA==.Minervá:BAAALgAECgMJAwABLgAFFAQJDwAYAMsaAA==.Missbehaving:BAABLgAECn8rAAMmAAkJnRDCMABKAQAmAAcJjRTCMABKAQAZAAkJNQZpPwATAQAAAA==.',
Mo='Monkdluffy:BAAALgADCgEJAQAAAA==.Morefire:BAAALgAECgQJCgABLgAECgkJFAAQAJYYAA==.Morrk:BAAALgADCgIJAgAAAA==.Mosmos:BAAALgADCgkJFQAAAA==.',
Mu='Muddslinger:BAABLgAECn8bAAIIAAkJpQswMgCDAQAIAAkJpQswMgCDAQAAAA==.Mumra:BAABLgAECn9AAAQmAAgJ2wpNMgBBAQAmAAgJ2wpNMgBBAQACAAYJdgFaPwC0AAAZAAEJAACvoAAAAAAAAA==.',
My='Mystblade:BAAALgAECgQJBAAAAA==.Mystlord:BAAALgAECgQJBAAAAA==.',
Na='Nadatank:BAAALgADCgQJBAAAAA==.Nalesean:BAAALgAECggJEQAAAA==.Nanaki:BAABLgAECn8iAAIMAAkJKyDzBgDQAgAMAAkJKyDzBgDQAgAAAA==.Nannette:BAABLgAECn8UAAIEAAcJKQO7BwGvAAAEAAcJKQO7BwGvAAAAAA==.Nappe:BAAALgAECgEJAQABLgAECgkJHwAEAIElAA==.Narag:BAABLgAECn86AAIJAAkJtxqOHgBvAgAJAAkJtxqOHgBvAgAAAA==.Nazfu:BAAALgAECgEJAgAAAA==.Nazg:BAAALgADCgQJAgAAAA==.',
Ne='Needle:BAAALgADCgYJBwAAAA==.Nerfertari:BAAALgAECgEJBQAAAA==.Netanyahoo:BAAALgAFFAIJAgAAAA==.Neva:BAAALgAECgIJAgAAAA==.Newport:BAABLgAECn85AAMFAAgJ9x/IEADJAgAFAAgJ9x/IEADJAgAQAAIJmAgElABMAAAAAA==.',
Ni='Ninex:BAABLgAECn8cAAIUAAgJTR/RGABMAgAUAAgJTR/RGABMAgAAAA==.Ninisina:BAABLgAECn9DAAMFAAgJnB+0EgC3AgAFAAgJnB+0EgC3AgARAAEJ7wOHLgAsAAAAAA==.Nithén:BAAALgADCgYJDQAAAA==.',
No='Noghalote:BAAALgADCgQJBAAAAA==.Nonaleeta:BAAALgAECgQJCAAAAA==.Notafurry:BAAALgADCgcJCQAAAA==.Novaa:BAAALgAECgcJBgAAAA==.Nowhere:BAAALgAECgUJBQABLgAECgkJJAAjAPwTAA==.Nowon:BAABLgAECn8nAAMoAAcJgxZRHgCJAQAoAAcJgxZRHgCJAQAOAAEJpwhgPAAcAAABLgAECgkJBAAXAAAAAA==.',
Nu='Nudream:BAABLgAECn8iAAIUAAkJWASvPwBFAQAUAAkJWASvPwBFAQAAAA==.',
Ny='Nybors:BAAALgADCgcJCwAAAA==.',
['Nö']='Nörse:BAABLgAECn8aAAMfAAYJDhDtTADYAAAfAAYJCA/tTADYAAAGAAEJpBf1SQBGAAAAAA==.',
Ol='Olakua:BAAALgAECgMJAwAAAA==.Oldjerry:BAABLgAECn8kAAIjAAkJ/BM7EgAVAgAjAAkJ/BM7EgAVAgAAAA==.Oliaa:BAAALgADCgYJCAAAAA==.',
Oo='Oomdeath:BAAALgAECgYJBgAAAA==.',
Op='Opalyte:BAABLgAECn8qAAMmAAkJqAwNLQBjAQAmAAkJqAwNLQBjAQAZAAIJogQgfABGAAAAAA==.',
Or='Orichalcum:BAABLgAECn8oAAIeAAgJth6PDgC3AgAeAAgJth6PDgC3AgAAAA==.Orphiee:BAABLgAECn8kAAIJAAYJnwGe8ABwAAAJAAYJnwGe8ABwAAAAAA==.',
Os='Oslagsi:BAAALgADCgcJDgAAAA==.Osyriss:BAAALgADCgUJBgAAAA==.',
Ot='Othril:BAAALgAECgQJBQAAAA==.',
Ou='Outis:BAAALgAFFAMJBwABLgAFFAMJCAAXAAAAAQ==.',
Pa='Pacts:BAAALgAECgEJAQAAAA==.Pakoros:BAABLgAECn9HAAMFAAkJch28DQDoAgAFAAkJch28DQDoAgAQAAQJBwp7agCZAAAAAA==.Palibuddy:BAAALgAECgMJAwAAAA==.Pallyfreak:BAAALgAECgYJCwAAAA==.',
Pe='Peachy:BAAALgAECgQJBAABLgAECgkJLQAFADQXAA==.Penderin:BAABLgAECn8VAAIJAAgJnxhCBAD4AAAJAAgJnxhCBAD4AAABLgAECgkJPAAGAD4aAA==.Penilock:BAAALgADCgIJAgAAAA==.Pensham:BAAALgAECgEJAwABLgAECgkJPAAGAD4aAA==.Perlindree:BAABLgAECn9GAAIJAAkJ4wkGAwA7AQAJAAkJ4wkGAwA7AQAAAA==.',
Pg='Pgorlelgy:BAACLgAFFH8JAAIJAAMJdRSaWwDtAAAJAAMJdRSaWwDtAAAuAAQKfywAAgkACQn+FlMyABMCAAkACQn+FlMyABMCAAAA.',
Ph='Phira:BAAALgADCgEJAQAAAA==.Phoenix:BAAALgADCgIJAgAAAA==.Physgun:BAAALgADCgYJDgAAAA==.',
Pi='Pillows:BAAALgADCgYJBgAAAA==.',
Pl='Platious:BAABLgAECn83AAIEAAkJmRZURgDzAQAEAAkJmRZURgDzAQAAAA==.',
Po='Pony:BAAALgADCgUJBQABLgADCgUJCgAXAAAAAA==.Poodin:BAAALgADCgIJAgAAAA==.Pookaboo:BAABLgAECn8WAAIPAAgJNwI11wCoAAAPAAgJNwI11wCoAAAAAA==.Poppers:BAAALgADCggJDQAAAA==.',
Pr='Preacharoùnd:BAACLgAFFH8ZAAIZAAYJQRQZDwB2AQAZAAYJQRQZDwB2AQAuAAQKf1gAAhkACQkLIg8EABwDABkACQkLIg8EABwDAAEuAAUUBgkZABkAQRQA.Promir:BAAALgAECgcJDgAAAA==.',
Pu='Purdie:BAABLgAECn8UAAIYAAkJHQwKRgB4AQAYAAkJHQwKRgB4AQABLgAECgkJLgAFAGQNAA==.Purdieturtle:BAAALgADCgkJCQAAAA==.',
Qe='Qeesa:BAAALgAECgIJAwAAAA==.',
Qi='Qiryana:BAAALgADCgIJAgAAAA==.',
Ra='Raeliene:BAACLgAFFH8JAAIEAAMJjB9PUQANAQAEAAMJjB9PUQANAQAuAAQKfyQAAgQACQkoHXwjAHcCAAQACQkoHXwjAHcCAAAA.Rafikie:BAAALgAECgIJAwAAAA==.Ratchet:BAAALgADCgMJAwAAAA==.Rawmeat:BAABLgAECn8/AAICAAkJ0h3nCQDTAgACAAkJ0h3nCQDTAgAAAA==.Razillar:BAAALgAECgEJAQAAAA==.',
Re='Rebelpatriot:BAAALgADCgYJCQAAAA==.Redbearrd:BAAALgADCgkJCQABLgAFFAIJBQADAG0DAA==.Relaxnerdlol:BAAALgAECgEJBAAAAA==.Reldwick:BAAALgADCgYJBwAAAA==.Renew:BAABLgAECn8yAAMmAAkJHB5yCgDAAgAmAAkJHB5yCgDAAgAZAAkJNxcUFQAkAgAAAA==.Renix:BAACLgAFFH8SAAIQAAQJCRkYIgATAQAQAAQJCRkYIgATAQAuAAQKfzIAAxAACQlmH/cNAIwCABAACQlmH/cNAIwCABEAAQl1CxYtADIAAAAA.Reno:BAAALgAECgMJAwAAAA==.Revery:BAAALgADCgIJAgAAAA==.',
Rh='Rhadgar:BAAALgADCgcJCQAAAA==.',
Ri='Ripmyname:BAAALgAECgYJBwAAAA==.Riverah:BAAALgAECgQJCAAAAA==.Rivulet:BAAALgAECgUJDAAAAA==.',
Ro='Roombaa:BAAALgADCgQJAgAAAA==.Royfenix:BAACLgAFFH8OAAMmAAMJOBAdKACEAAAmAAIJ5RQdKACEAAAZAAIJ8wMVNQBsAAAuAAQKfy4ABCYABwleG9UWABkCACYABwleG9UWABkCABkABAnmD7NMANwAAAIAAwnhAiVqAFkAAAEuAAUUBAkVAAMAtBsA.',
Ru='Rukaillin:BAAALgAECgYJBwAAAA==.',
Ry='Ryukaii:BAAALgAECgYJCAAAAA==.Ryyah:BAABLgAECn88AAMUAAgJjBh3GwAoAgAUAAgJjBh3GwAoAgAEAAQJLQO6RwFlAAAAAA==.',
['Rè']='Rèck:BAAALgAECgUJCAAAAA==.',
['Ré']='Rébecca:BAAALgAECgMJAwABLgAFFAMJBgAgAKwNAA==.',
['Rì']='Rìsen:BAAALgADCgYJBgAAAA==.',
['Rú']='Rústy:BAAALgAFFAIJAwAAAA==.',
Sa='Sabris:BAAALgAECgQJBAAAAA==.Saetyl:BAABLgAECn8nAAIfAAgJJgSfAwBrAAAfAAgJJgSfAwBrAAAAAA==.Saga:BAAALgADCgEJAQAAAA==.Salvynus:BAAALgAECgUJBQAAAA==.Samhainn:BAAALgADCgIJAQABLgADCgYJBQAXAAAAAA==.Sanctity:BAAALgAECgMJAwAAAA==.Saphirè:BAAALgAECgUJAQAAAA==.',
Sc='Scrungle:BAAALgADCgYJCwAAAA==.',
Se='Seabiscuìt:BAAALgAECgIJAgAAAA==.Seanthaniel:BAEALgAFFAEJAQABLgAFFAgJJwAgAMMPAA==.Seifslam:BAAALgADCgQJBAABLgAECgEJAQAXAAAAAA==.Seifura:BAAALgAECgEJAQAAAA==.Semi:BAAALgAECgYJDQABLgAFFAQJCAAUAJgaAA==.Semii:BAAALgAECgIJAgAAAA==.Serkerune:BAAALgAECgEJAgAAAA==.Serkesul:BAABLgAECn8sAAIZAAkJaSRnAwAqAwAZAAkJaSRnAwAqAwAAAA==.Sevinas:BAABLgAECn8tAAIRAAkJ3A6vFABxAQARAAkJ3A6vFABxAQAAAA==.',
Sf='Sfogliatella:BAAALgAECgEJAQAAAA==.',
Sh='Shaftstop:BAAALgADCgkJCQABLgAECgUJBQAXAAAAAA==.Shamallamá:BAAALgADCgkJCgABLgAECgkJMAAJADciAA==.Shamthis:BAABLgAECn8jAAIQAAkJERCjKgCdAQAQAAkJERCjKgCdAQAAAA==.Shamwoww:BAACLgAFFH8GAAIQAAMJURA7NgC1AAAQAAMJURA7NgC1AAAuAAQKfyQAAhAACAncHqcRAGMCABAACAncHqcRAGMCAAEuAAUUBgkZABkAQRQA.Shamyou:BAABLgAECn8UAAMFAAkJ1xnQGwA6AgAFAAkJ1xnQGwA6AgAQAAYJKRoQOgBOAQAAAA==.Shealie:BAAALgADCgMJAwABLgAECgkJOgAjAI8dAA==.Shelly:BAAALgAECggJDwAAAA==.Shiftymynx:BAAALgADCgEJAQAAAA==.Shlumpa:BAACLgAFFH8JAAIFAAUJ+Bs+GQCdAQAFAAUJ+Bs+GQCdAQAuAAQKfx8AAgUACQlnGx8UAKsCAAUACQlnGx8UAKsCAAAA.Shlumpdragon:BAAALgAECgMJAwABLgAFFAUJCQAFAPgbAA==.Shlumpydk:BAABLgAFFH8HAAMgAAQJHAQMKwChAAAgAAQJDwQMKwChAAATAAEJoQHRJwEsAAAAAA==.Shokcz:BAAALgAECgQJBwAAAA==.Shomba:BAAALgAECgYJBgAAAA==.Shotsfired:BAAALgAECgYJCgAAAA==.Shámjackson:BAACLgAFFH8ZAAIFAAcJfySzBQBsAgAFAAcJfySzBQBsAgAuAAQKfy4AAgUACQkMJjQDAEcDAAUACQkMJjQDAEcDAAAA.',
Si='Silvey:BAABLgAECn8sAAINAAkJjiGWCgD1AgANAAkJjiGWCgD1AgAAAA==.Sindricil:BAAALgADCggJDAAAAA==.',
Sk='Skar:BAAALgADCggJCQAAAA==.Skeletorque:BAACLgAFFH8FAAMgAAIJ/AP1CAApAAATAAIJRwIZAgFmAAAgAAEJJAb1CAApAAAuAAQKfxcAAxMACQncEJ5qAJABABMACQncEJ5qAJABACAAAQlcDadLAB8AAAAA.Skully:BAAALgAECgEJAQAAAA==.Skyylorne:BAABLgAECn8kAAIGAAcJ7hMCFgBpAQAGAAcJ7hMCFgBpAQAAAA==.',
Sl='Slipnslide:BAAALgAECgQJBAABLgAECgkJPwACANIdAA==.',
Sm='Smallwdruid:BAAALgAECgYJBgAAAA==.Smashlock:BAAALgADCgUJCAAAAA==.Smellydruid:BAAALgADCgEJAQAAAA==.Smitesword:BAAALgADCgYJDAAAAA==.',
Sn='Snow:BAAALgAECgYJBgABLgAECgkJIgAMACsgAA==.Snowfawn:BAABLgAECn8qAAIJAAgJyBo7RQDSAQAJAAgJyBo7RQDSAQABLgAFFAIJBAAXAAAAAA==.Snusnurae:BAAALgAECgcJEgAAAA==.',
So='Sodapoppin:BAAALgADCgcJBwAAAA==.Solas:BAAALgADCgQJBQAAAA==.Somay:BAAALgAECgQJBwAAAA==.Soryn:BAAALgADCgUJBQAAAA==.Sovirus:BAAALgAECgQJBAABLgAECgkJIgAMACsgAA==.',
Sp='Spanana:BAABLgAFFH8MAAITAAQJThK3FQBNAQATAAQJThK3FQBNAQAAAA==.Sparevolts:BAAALgAECgEJAQAAAA==.Specialist:BAAALgAFFAIJAwABLgAFFAUJEAAHAGYVAA==.Spicychopz:BAACLgAFFH8aAAIDAAkJYCHqCwCQAgADAAkJYCHqCwCQAgAuAAQKfxcAAgMACAnbIRUdAAEDAAMACAnbIRUdAAEDAAAA.Spiketickevi:BAAALgAECggJCAAAAA==.Splishsplásh:BAABLgAECn8tAAIFAAkJOx8VEgC9AgAFAAkJOx8VEgC9AgAAAA==.Sprattyboii:BAAALgAFFAIJAwAAAA==.Sprucelock:BAAALgADCgIJAgAAAA==.',
Ss='Sscarlet:BAABLgAECn8pAAIDAAkJAQySBQDKAAADAAkJAQySBQDKAAAAAA==.',
St='Staltis:BAAALgAECgkJEAAAAA==.Starrling:BAABLgAECn8WAAIfAAgJNhT8IwCqAQAfAAgJNhT8IwCqAQAAAA==.Starzia:BAABLgAECn8xAAICAAkJgAeaLgBmAQACAAkJgAeaLgBmAQAAAA==.Stupidtree:BAACLgAFFH8TAAIYAAUJKR2HGACaAQAYAAUJKR2HGACaAQAuAAQKfxwAAhgABwnMI3IVAJ4CABgABwnMI3IVAJ4CAAAA.',
Su='Sudzyjr:BAAALgADCgUJBQAAAA==.Sunk:BAABLgAECn8tAAIPAAkJJRx0HgBuAgAPAAkJJRx0HgBuAgAAAA==.',
Sw='Swagg:BAAALgAECgEJAQAAAA==.Swanho:BAAALgAECgIJBQABLgAECgcJCQAXAAAAAA==.Swiftblossom:BAAALgAECgQJBwAAAA==.',
Sy='Sylvanex:BAABLgAECn8iAAIJAAcJVho8QQDeAQAJAAcJVho8QQDeAQAAAA==.',
['Sê']='Sêrënîty:BAAALgAFFAEJAQABLgAFFAYJEAAEAGETAA==.',
['Sô']='Sông:BAAALgAECgUJDQAAAA==.',
Ta='Taestra:BAAALgAECgMJAwAAAA==.Taffbones:BAAALgAECgYJCgAAAA==.Tahla:BAAALgADCgIJAgAAAA==.Talanot:BAAALgAECgUJCwABLgAECgYJFQAeAIoRAA==.Talarus:BAAALgAECggJEQAAAA==.Talurana:BAAALgAECgEJAgAAAA==.Tanadria:BAABLgAECn8kAAIjAAkJCwx1HACyAQAjAAkJCwx1HACyAQAAAA==.Tangerene:BAACLgAFFH8HAAICAAMJbAETPACMAAACAAMJbAETPACMAAAuAAQKfyEAAwIACQkUDFgzAEsBAAIACAlrDVgzAEsBACYABgkUAhteALoAAAAA.Tapioca:BAACLgAFFH8PAAIJAAQJ1iC1KgBeAQAJAAQJ1iC1KgBeAQAuAAQKfzkAAgkACQk0I9wGACkDAAkACQk0I9wGACkDAAAA.',
Tc='Tchort:BAAALgAECgQJBAABLgAFFAgJGQADAHMUAA==.',
Te='Telemachus:BAAALgAECgEJAQAAAA==.Telm:BAABLgAECn8kAAMEAAcJFxuTbgCRAQAEAAcJcxmTbgCRAQAVAAcJShoVGABeAQAAAA==.Tentilious:BAAALgAECgQJBgAAAA==.',
Th='Thadeusputz:BAAALgAECgEJAQAAAA==.Thaÿne:BAABLgAECn8WAAIIAAkJiA4OLQCeAQAIAAkJiA4OLQCeAQAAAA==.Thebestpally:BAACLgAFFH8LAAMEAAMJtBOPeADEAAAEAAMJAg2PeADEAAAVAAEJkRZuFwA/AAAuAAQKf0YAAxUACQlgHMIFAJECABUACQlgHMIFAJECAAQABQmNDQXlAMQAAAAA.Thenemisis:BAAALgADCgcJDwAAAA==.Thiccidàn:BAAALgADCgEJAgAAAA==.Thund:BAAALgAECgQJBwAAAA==.',
Ti='Tianielan:BAABLgAECn8aAAMUAAkJGh8OEwB4AgAUAAkJGh8OEwB4AgAEAAEJJQ59QgEzAAAAAA==.Tidds:BAABLgAECn8+AAMPAAkJUw/VAQAtAQAPAAkJUw/VAQAtAQAbAAYJigi2HADZAAAAAA==.Tinyfloof:BAAALgADCgcJCwAAAA==.',
To='To:BAAALgAECggJDgAAAA==.Tobikins:BAAALgADCgIJAgAAAA==.Toolgunx:BAAALgAECgQJBQAAAA==.Totemdown:BAACLgAFFH8bAAIFAAgJBx4/BQB2AgAFAAgJBx4/BQB2AgAuAAQKfyMAAgUACQm1I6cGAEYDAAUACQm1I6cGAEYDAAAA.',
Tr='Tralth:BAAALgAECgIJAgAAAA==.Trazarath:BAACLgAFFH8YAAMKAAUJ1gv7NwDlAAAKAAUJ1gv7NwDlAAALAAIJSAayDwA+AAAuAAQKfysAAwoACQknFd4WAB8CAAoACQknFd4WAB8CAAsAAwkmBKczAHcAAAAA.Triage:BAAALgADCgYJBwAAAA==.Triggaman:BAAALgADCgYJCAABLgAECgcJJAAEABcbAA==.Trollner:BAAALgAECgEJAgAAAA==.Trunndle:BAAALgADCgUJBQAAAA==.',
Ts='Tsuul:BAAALgAECgQJCwAAAA==.',
Tu='Turbolover:BAAALgAECgEJAQAAAA==.',
Tw='Twirl:BAAALgADCgEJAQAAAA==.',
Ty='Tylenstus:BAAALgAECgEJAQAAAA==.',
['Tã']='Tãpioca:BAAALgAECgQJDQABLgAFFAQJDwAJANYgAA==.',
Uj='Ujio:BAABLgAECn8ZAAMUAAcJSRgKKgC+AQAUAAcJSRgKKgC+AQAEAAMJpwewMgF8AAABLgAECgkJLwAFANoYAA==.',
Un='Unholyferret:BAAALgADCgIJAgAAAA==.Unify:BAAALgADCgMJBAAAAA==.Untiler:BAAALgADCgUJBQAAAA==.',
Us='Usdaprime:BAAALgAECgIJAwABLgAFFAIJBQAgAPwDAA==.Usopp:BAAALgADCgYJBgAAAA==.',
Uu='Uuyd:BAAALgAFFAMJCAAAAQ==.',
Va='Vaden:BAAALgAECgIJAgABLgAECgkJIgAHABoWAA==.Vaelthys:BAABLgAECn8eAAIZAAkJ8hgTDwBoAgAZAAkJ8hgTDwBoAgABLgAECgkJKAAPAHwXAA==.Valedarrin:BAAALgADCgEJAQAAAA==.Valefyre:BAAALgADCgcJBwAAAA==.Valenstrasz:BAACLgAFFH8FAAMLAAIJ2geyCgB5AAALAAIJlQayCgB5AAAKAAIJtQYcWABtAAAuAAQKfyIAAwoACQmGEjIfAMkBAAoACAkSEzIfAMkBAAsABAn6DncZAIkAAAEuAAUUBAkHAAgAEyAA.Valetherin:BAAALgADCgkJCQAAAA==.Valkaron:BAAALgADCgYJBgABLgAFFAUJFwAEAIwaAA==.Vanaheim:BAAALgAECgkJEwAAAA==.Vance:BAABLgAECn8WAAIEAAYJug0SygD7AAAEAAYJug0SygD7AAAAAA==.Vanitha:BAAALgADCggJBgAAAA==.Vanysh:BAAALgAECgMJAwAAAA==.Varala:BAAALgAECgYJEQAAAA==.',
Ve='Vel:BAACLgAFFH8YAAMTAAgJxRvGDwBfAgATAAgJxRvGDwBfAgAgAAEJAACNZAAAAAAuAAQKf1EAAxMACAlkJmcMAAkDABMACAlkJmcMAAkDACIAAwmCIe4VACoBAAAA.Velandis:BAAALgADCgcJBwAAAA==.Velenari:BAAALgAECgEJAQABLgAECgkJMAACAPUcAA==.Vellea:BAAALgAECgYJDgABLgAECgYJFQAeAIoRAA==.Velwar:BAAALgAECgcJCQABLgAFFAgJGAATAMUbAA==.Velýth:BAAALgAECgUJDAABLgAFFAgJGAATAMUbAA==.Venmeumshna:BAAALgAECgQJBQAAAA==.Veritas:BAAALgAECgYJEwAAAA==.Veskara:BAAALgAECgUJBQAAAA==.Vexxius:BAACLgAFFH8FAAIHAAIJfRiTJgCeAAAHAAIJfRiTJgCeAAAuAAQKfxwABAcACQkJGWwSABUCAAcACQn8FGwSABUCABwABwkxFNcVAAoBAAkAAQkgDz0yATYAAAAA.',
Vi='Viella:BAAALgAECgQJBAAAAA==.Viero:BAAALgAECggJCAAAAA==.',
Vo='Vorathis:BAAALgAECgYJDAABLgAFFAUJHAAFAOQkAA==.',
Vy='Vylana:BAAALgAECgYJDAABLgAFFAYJEAAEAGETAA==.',
['Và']='Vàlkyrie:BAACLgAFFH8XAAIEAAUJjBrkBQDmAAAEAAUJjBrkBQDmAAAuAAQKfyIAAgQACQkCHnEiAKACAAQACQkCHnEiAKACAAAA.',
Wa='Wack:BAAALgAFFAEJAQAAAA==.Wanderfoot:BAABLgAECn8iAAIHAAkJGhZpDwA4AgAHAAkJGhZpDwA4AgAAAA==.Wangtulo:BAAALgADCgIJAgAAAA==.Warienta:BAAALgAECgMJAwAAAA==.Warity:BAABLgAECn9DAAIPAAkJoBv+FwCUAgAPAAkJoBv+FwCUAgAAAA==.Warnarse:BAAALgADCgUJBQAAAA==.Warrill:BAEBLgAECn8bAAISAAgJ/QknIwAlAQASAAgJ/QknIwAlAQAAAA==.Wavestabe:BAABLgAECn88AAIGAAkJPhppBwBkAgAGAAkJPhppBwBkAgAAAA==.',
Wo='Wobblart:BAAALgAECgQJBgABLgAECgkJPAAGAD4aAA==.',
Wr='Wreck:BAACLgAFFH8OAAMbAAQJtAWPCQDiAAAbAAQJtAWPCQDiAAAPAAIJKAKNugBaAAAuAAQKfy0AAg8ACAn1DrtsAGIBAA8ACAn1DrtsAGIBAAAA.',
Xe='Xeevala:BAAALgAECgYJEAAAAA==.Xerxseize:BAAALgAECgEJAQAAAA==.',
Xo='Xomby:BAAALgAECgYJBgAAAA==.',
['Xì']='Xìon:BAABLgAECn8kAAMTAAkJpx7KAAAJAgATAAkJpx7KAAAJAgAiAAEJRwqLPwAoAAAAAA==.',
Ya='Yayrri:BAABLgAECn8tAAIQAAkJixG4JwCvAQAQAAkJixG4JwCvAQAAAA==.',
Ye='Yersipestis:BAAALgADCgYJBgAAAA==.',
Yo='Youngjedi:BAAALgAECgUJBQAAAA==.',
Yu='Yungstabby:BAAALgAECgUJBQABLgAECgcJHgAJANMZAA==.Yurî:BAAALgAECgQJCQAAAA==.',
Za='Zahne:BAAALgAECgMJAwABLgAFFAUJBgAbAMEbAA==.Zatarra:BAAALgAECgIJBAAAAA==.Zathamax:BAABLgAECn8VAAIDAAgJaQNt0wDtAAADAAgJaQNt0wDtAAAAAA==.Zavya:BAAALgAECgUJBAABLgAECgkJIAABAJUIAA==.',
Ze='Zeldei:BAAALgADCgEJAQAAAA==.Zextron:BAABLgAECn80AAIoAAkJURORAACQAQAoAAkJURORAACQAQAAAA==.',
Zi='Ziaya:BAABLgAECn8gAAIBAAkJlQi2MAA/AQABAAkJlQi2MAA/AQAAAA==.Zin:BAAALgADCgQJBAAAAA==.',
Zo='Zolaeus:BAAALgAECgUJDQABLgAECgYJFQAeAIoRAA==.Zorbaks:BAAALgAECgQJBAAAAA==.',
Zu='Zuboo:BAABLgAECn8xAAIoAAkJlwh+JgBFAQAoAAkJlwh+JgBFAQAAAA==.',
['Zö']='Zöey:BAAALgADCggJCwAAAA==.',
['Él']='Élwë:BAAALgADCgUJBQAAAA==.',
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
