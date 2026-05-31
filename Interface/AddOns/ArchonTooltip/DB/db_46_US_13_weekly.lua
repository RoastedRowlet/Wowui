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

local lookup = {'Monk-Brewmaster','Priest-Discipline','Warrior-Protection','Paladin-Retribution','Shaman-Restoration','Mage-Frost','Unknown-Unknown','Hunter-Survival','Evoker-Augmentation','Evoker-Preservation','DemonHunter-Devourer','DemonHunter-Vengeance','Evoker-Devastation','Hunter-BeastMastery','Druid-Feral','Warlock-Demonology','Shaman-Elemental','Shaman-Enhancement','DeathKnight-Unholy','Paladin-Holy','Paladin-Protection','Druid-Guardian','Druid-Restoration','Priest-Shadow','Warlock-Destruction','Warlock-Affliction','Hunter-Marksmanship','Monk-Windwalker','Monk-Mistweaver','Druid-Balance','Warrior-Fury','DeathKnight-Blood','Warrior-Arms','DeathKnight-Frost','Rogue-Subtlety','Rogue-Assassination','Mage-Fire','Priest-Holy','Mage-Arcane','DemonHunter-Havoc',}
local provider = {region='US',realm='Antonidas',name='US',type='weekly',zone=46,date='2026-05-30',data={Aa='Aalst:BAABLgAECn8fAAIBAAgJagkJMQAsAQABAAgJagkJMQAsAQAAAA==.',
Ac='Achillesheal:BAABLgAECn8ZAAICAAYJoR8SFAAMAgACAAYJoR8SFAAMAgAAAA==.Acidicwrath:BAAALgADCgUJBQAAAA==.Acnologias:BAAALgAECgEJAQABLgAECgkJRAADAOodAA==.Acshec:BAAALgADCgYJDgABLgAECgcJJAAEABcbAA==.Acuna:BAAALgAECgcJCQAAAA==.',
Ad='Aderna:BAAALgADCgMJBAAAAA==.Adoryn:BAEBLgAECn86AAIBAAkJdxDMGwC1AQABAAkJdxDMGwC1AQAAAA==.',
Ae='Aervyper:BAAALgADCgIJAwAAAA==.Aessan:BAAALgAECgEJAQABLgAECggJJwAFAP4MAA==.',
Ag='Aggrenox:BAABLgAECn8gAAIEAAYJ5QlhrwAlAQAEAAYJ5QlhrwAlAQAAAA==.',
Ai='Aisathya:BAABLgAECn8fAAIGAAgJPCOUGwCfAgAGAAgJPCOUGwCfAgAAAA==.',
Ak='Akiza:BAAALgAECgkJDwAAAA==.Akonorix:BAAALgADCgUJCAAAAA==.',
Al='Alaelis:BAAALgAECgYJCAAAAA==.Albina:BAAALgAECgUJDAAAAA==.Aldelvir:BAAALgAECggJDgABLgAECgkJCwAHAAAAAA==.Alottarage:BAAALgADCgcJCQAAAA==.Alunantre:BAABLgAECn8aAAIIAAkJ6BRXGADPAQAIAAkJ6BRXGADPAQAAAA==.Alzhimers:BAAALgAECggJEwAAAA==.',
Am='Amberscale:BAACLgAFFH8LAAIJAAMJBBnhMgDaAAAJAAMJBBnhMgDaAAAuAAQKfysAAwkACQkxHFkMAH0CAAkACQkxHFkMAH0CAAoAAQm3FT40AEEAAAAA.Amyrrin:BAABLgAECn8UAAIEAAgJlhEuhABMAQAEAAgJlhEuhABMAQAAAA==.',
An='Ancientiur:BAABLgAECn8dAAMLAAkJdBuXMgDlAQALAAkJUhmXMgDlAQAMAAMJ+RJuIgBrAAAAAA==.Andormu:BAAALgADCgYJBQAAAA==.Andracca:BAABLgAECn8aAAMJAAgJVxNVJwCMAQAJAAgJSBJVJwCMAQANAAQJnxWAEADvAAAAAA==.Angrulus:BAABLgAECn80AAIOAAkJLRlzJAA5AgAOAAkJLRlzJAA5AgAAAA==.Animal:BAAALgAECgIJAgAAAA==.Animlshiftr:BAABLgAECn8jAAIPAAgJrg37FABNAQAPAAgJrg37FABNAQAAAA==.',
Ap='Apollo:BAABLgAECn8qAAIQAAgJdgtLaQBfAQAQAAgJdgtLaQBfAQAAAA==.',
Ar='Aradunn:BAACLgAFFH8YAAIFAAUJ5CRMBwAYAgAFAAUJ5CRMBwAYAgAuAAQKfyYABAUACQk3IvsGAAQDAAUACQk3IvsGAAQDABEAAwkkHSNIAPcAABIAAgmeI3ArAGQAAAAA.Araedis:BAABLgAECn81AAIIAAkJ/xB8EQATAgAIAAkJ/xB8EQATAgAAAA==.Araelle:BAAALgAECgEJAQAAAA==.Archangel:BAAALgAECgYJCwAAAA==.Arrill:BAEALgAECgMJAwABLgAECggJGwADAP0JAA==.Artheren:BAAALgAECgQJBgAAAA==.Aryllyn:BAAALgADCgYJDgAAAA==.',
As='Ashvehtta:BAABLgAECn8XAAITAAgJ2gmaegBZAQATAAgJ2gmaegBZAQAAAA==.Assaelysia:BAAALgAECgIJAgAAAA==.Asstormrage:BAAALgADCgUJBQAAAA==.Asti:BAAALgAECgYJDQAAAA==.Astralon:BAAALgAECgIJAwAAAA==.',
At='Atharion:BAABLgAECn8mAAMUAAkJch0gDgCcAgAUAAgJpR4gDgCcAgAEAAYJjhZcngAeAQAAAA==.Atheus:BAAALgADCgEJAQAAAA==.',
Av='Avanda:BAAALgAECgEJBQAAAA==.Avrassa:BAAALgADCgMJAwAAAA==.',
Aw='Awperprime:BAABLgAECn8rAAISAAgJ1hmvCQAGAgASAAgJ1hmvCQAGAgAAAA==.',
Ay='Ayhanui:BAAALgAECgEJAgAAAA==.',
Az='Azaléa:BAAALgADCgcJBwAAAA==.Azrathalos:BAABLgAECn8bAAQUAAcJmg4HQAAtAQAUAAYJOQ0HQAAtAQAEAAUJEAWtBgGPAAAVAAEJkwOwTAAmAAAAAA==.Azémstraza:BAAALgAECgYJDAAAAA==.',
Ba='Bained:BAAALgADCgcJBwAAAA==.Baldric:BAABLgAECn8lAAIOAAgJ8BZZLwD0AQAOAAgJ8BZZLwD0AQAAAA==.Balinor:BAABLgAECn8dAAIUAAcJLQ78NwBVAQAUAAcJLQ78NwBVAQABLgAECgkJMQADAJ4dAA==.Bank:BAAALgADCgIJAgAAAA==.',
Be='Bearett:BAABLgAECn83AAIWAAkJRiOlAQApAwAWAAkJRiOlAQApAwAAAA==.Beefcakezear:BAAALgADCgQJBAAAAA==.Belyfrost:BAAALgAFFAIJAgAAAA==.Belylight:BAAALgAECgkJEAAAAA==.Belymoon:BAAALgAECgkJCQABLgAECgkJEAAHAAAAAA==.Bernd:BAABLgAECn8kAAIWAAgJOQ3WIwAMAQAWAAgJOQ3WIwAMAQAAAA==.Beörn:BAABLgAECn8uAAIXAAgJsCTzBQBMAwAXAAgJsCTzBQBMAwAAAA==.',
Bi='Bigsniffy:BAAALgADCgQJBAAAAA==.',
Bl='Blackbeard:BAAALgAECgEJAQABLgAECgkJMQADAJ4dAA==.Blackgrinn:BAABLgAECn8jAAMCAAgJJw+sIgCVAQACAAgJJw+sIgCVAQAYAAcJRwZuQwDbAAAAAA==.Blackkgrin:BAAALgADCgQJBwAAAA==.Blasphemous:BAABLgAECn8dAAITAAcJgBTCfABUAQATAAcJgBTCfABUAQAAAA==.Blasé:BAABLgAECn8yAAQQAAgJESDRHQBjAgAQAAgJESDRHQBjAgAZAAEJAACjXABZAAAaAAEJghLuMQBAAAABLgAFFAMJBAAHAAAAAA==.Blazéoné:BAAALgAECgUJBgAAAA==.Blessin:BAAALgAECgcJCgAAAA==.',
Bo='Bobo:BAAALgAECgUJEQAAAA==.Bobrossx:BAACLgAFFH8FAAMbAAIJ7xKHHQCgAAAbAAIJ7xKHHQCgAAAOAAIJNQh/dACEAAAuAAQKfywABBsACAmZIZcNANgCABsACAkUHpcNANgCAAgABwnXHRkaAL8BAA4AAgl9HpvKAIsAAAAA.Bobsmonk:BAAALgADCgEJAQAAAA==.Bomi:BAAALgADCgQJBAAAAA==.Boostéd:BAABLgAECn8XAAITAAcJdR3VSAAZAgATAAcJdR3VSAAZAgAAAA==.Boostëd:BAAALgAECgYJBwABLgAECgcJFwATAHUdAA==.',
Br='Brakevilt:BAAALgAECgcJBwAAAA==.Brattyone:BAAALgADCgcJBwAAAA==.Breadcrums:BAAALgADCgMJAwAAAA==.Bruche:BAABLgAECn8uAAITAAkJLh+cGgCTAgATAAkJLh+cGgCTAgAAAA==.Brujaah:BAAALgAECgYJBgABLgAECgkJOgAHAAAAAQ==.Brynthadia:BAAALgAECgYJCAAAAA==.Brzrker:BAAALgADCgYJDAAAAA==.',
Bu='Bubagumps:BAAALgAECgEJAQAAAA==.',
Bw='Bwca:BAACLgAFFH8HAAIOAAMJ9A5dUgDbAAAOAAMJ9A5dUgDbAAAuAAQKfxQAAg4ABQkjHORVAIkBAA4ABQkjHORVAIkBAAEuAAUUAwkMAAUAFQYA.',
Ca='Caine:BAABLgAECn8xAAIDAAkJnh3SCQBCAgADAAkJnh3SCQBCAgAAAA==.Cakébob:BAAALgADCgQJBQAAAA==.Calmdown:BAAALgADCgYJBwAAAA==.Carraa:BAAALgADCgYJCgABLgAECggJJwAFAP4MAA==.Casey:BAABLgAECn8cAAIEAAYJEAYB3wDAAAAEAAYJEAYB3wDAAAAAAA==.Castyblasty:BAAALgAECgEJAQAAAA==.Cataaria:BAABLgAECn8nAAIFAAgJ/gzwSgBmAQAFAAgJ/gzwSgBmAQAAAA==.',
Ce='Cellina:BAABLgAECn8iAAMcAAgJehAAJQB0AQAcAAgJehAAJQB0AQABAAYJGAbeTQC4AAAAAA==.Cerathal:BAAALgADCgIJAgAAAA==.Ceriumz:BAAALgAECgYJCwABLgAECgkJRAADAOodAA==.',
Cf='Cfourtylock:BAABLgAECn8oAAQQAAkJfBdUSgCwAQAQAAgJrRVUSgCwAQAaAAYJcRUlEQAbAQAZAAEJ7wVOeQAqAAAAAA==.',
Ch='Chaniqua:BAAALgADCgQJBQAAAA==.Chiman:BAABLgAECn8UAAMdAAYJbBF1QAA3AQAdAAYJbBF1QAA3AQAcAAUJZgssTgC1AAAAAA==.Chronophage:BAAALgAECgUJBQAAAA==.Chûd:BAEALgAECgUJBQAAAA==.',
Ci='Ciders:BAAALgAECgEJAQABLgAECgYJHgAIAPQTAA==.',
Cl='Clasastrasza:BAAALgAECgUJCgABLgAFFAMJDQAXANEeAA==.Classá:BAACLgAFFH8NAAMXAAMJ0R4EJwAPAQAXAAMJ0R4EJwAPAQAeAAMJzhUSKADEAAAuAAQKf0IABB4ACQljImoHAMwCAB4ACAmAJGoHAMwCABcABwmhIMlGAIcBABYAAQmYF8tYAEAAAAAA.Clawz:BAAALgAFFAIJBAABLgAFFAMJCQAEAD0eAA==.',
Co='Codedd:BAACLgAFFH8GAAIXAAIJYwaLUgBrAAAXAAIJYwaLUgBrAAAuAAQKfxkAAhcABwl5ELBKAFEBABcABwl5ELBKAFEBAAAA.Commit:BAAALgAECggJDgAAAA==.Comradeprime:BAAALgAECgQJCQAAAA==.Corlys:BAABLgAECn8pAAMEAAgJ4SBwMAAmAgAEAAgJoB5wMAAmAgAVAAYJgB0zEACmAQABLgAECgkJJQAGAF4SAA==.Covi:BAAALgADCggJCgAAAA==.',
Cr='Crismonguard:BAAALgAECgcJBwAAAA==.Crispìn:BAAALgAECgYJEAAAAA==.Crossbones:BAAALgAECgQJBwAAAA==.Crue:BAABLgAECn8YAAIXAAgJWAn7UwAtAQAXAAgJWAn7UwAtAQAAAA==.',
Cu='Curthar:BAACLgAFFH8JAAIEAAMJPR5MTAD3AAAEAAMJPR5MTAD3AAAuAAQKfyAAAxUACQkUJbUAAFgDABUACQkUJbUAAFgDAAQABgmgHmRuAHcBAAAA.',
Cy='Cyguy:BAAALgAECgEJAQAAAA==.Cyndee:BAABLgAECn82AAIfAAkJkBVyGAAWAgAfAAkJkBVyGAAWAgAAAA==.Cynnafrost:BAAALgAECgEJAQAAAA==.Cytenk:BAAALgADCgYJBgAAAA==.',
Da='Dadda:BAABLgAECn83AAIbAAkJ9B+hAgCuAgAbAAkJ9B+hAgCuAgAAAA==.Dallas:BAAALgADCgcJBwAAAA==.Damascus:BAAALgAECgYJCwABLgAECggJJQAOAPAWAA==.Dankmonk:BAABLgAECn8nAAIBAAgJEhYZGgDDAQABAAgJEhYZGgDDAQAAAA==.Darcnis:BAAALgADCgkJGwAAAA==.Darielea:BAAALgADCgIJAgAAAA==.Darkfury:BAABLgAECn80AAILAAkJiAmqXABaAQALAAkJiAmqXABaAQAAAA==.Darklasminth:BAAALgAFFAIJAgAAAA==.Darkschi:BAAALgAECgQJBAAAAA==.Darthwang:BAABLgAECn8fAAIQAAYJ6BjsWgC3AQAQAAYJ6BjsWgC3AQAAAA==.Darthwing:BAAALgAECgMJAwABLgAECgYJHwAQAOgYAA==.Dartos:BAACLgAFFH8GAAITAAIJjyEhlADFAAATAAIJjyEhlADFAAAuAAQKf0EAAhMACQnrJOUEAEwDABMACQnrJOUEAEwDAAAA.',
De='Deadlysmash:BAAALgADCgMJAwAAAA==.Deathratio:BAAALgADCgcJBwAAAA==.Deathsbff:BAAALgADCgEJAQABLgAFFAcJGAAGAO0WAA==.Deathsend:BAAALgAECggJCAAAAA==.Debluddk:BAABLgAECn8lAAIgAAkJdRtLCAB+AgAgAAkJdRtLCAB+AgAAAA==.Deep:BAAALgAECgMJAwABLgAECgkJJQAdALMgAA==.Deepfister:BAABLgAECn8lAAIdAAkJsyAWBwASAwAdAAkJsyAWBwASAwAAAA==.Deeplydivine:BAAALgAECgIJAgABLgAECgkJJQAdALMgAA==.Demone:BAAALgADCgMJAwAAAA==.',
Di='Dic:BAAALgAECgcJCgAAAA==.Diluvium:BAABLgAECn8kAAIEAAkJJBJXTwDBAQAEAAkJJBJXTwDBAQAAAA==.Discodank:BAAALgAECgMJBAAAAA==.',
Dj='Djpleasant:BAACLgAFFH8SAAIGAAUJIxJoTwAyAQAGAAUJIxJoTwAyAQAuAAQKfzIAAgYACQmyHYAbAKACAAYACQmyHYAbAKACAAAA.',
Dk='Dktelmtwo:BAAALgAECgcJCwAAAA==.',
Do='Doneisha:BAAALgAECgQJCQAAAA==.Dontcare:BAABLgAFFH8IAAMOAAUJHhDIUADfAAAOAAQJ5BPIUADfAAAIAAIJIAMuJwB+AAAAAA==.Downhammer:BAAALgAECgkJBQAAAA==.',
Dr='Drakamar:BAABLgAECn8yAAQNAAkJAwOCEwDAAAANAAgJ6QKCEwDAAAAJAAkJwQE1ZQCBAAAKAAYJMAJ1KgB9AAAAAA==.Dranith:BAAALgAECgQJBAAAAA==.Dronos:BAABLgAECn8yAAIeAAkJgSN+AgBCAwAeAAkJgSN+AgBCAwAAAA==.',
Du='Dunzledorf:BAAALgAECgcJBwAAAA==.',
Dy='Dynammes:BAABLgAECn8hAAIGAAcJCxh3ZQCZAQAGAAcJCxh3ZQCZAQABLgAFFAIJBQANANoHAA==.',
Ea='Eaglej:BAAALgAECgkJCAAAAA==.Eatmorpizza:BAAALgAECgQJCAAAAA==.',
Eb='Ebore:BAAALgADCggJDQAAAA==.',
Ee='Eegorn:BAAALgAECgYJCgAAAA==.Eegroll:BAACLgAFFH8PAAIBAAQJcBrcGwAsAQABAAQJcBrcGwAsAQAuAAQKfxgAAwEACAmlHNEbALUBABwABwkpF+kjALcBAAEABQm9H9EbALUBAAAA.',
Eg='Egraw:BAAALgAECgQJBAAAAA==.',
El='Elementals:BAAALgAECgkJEwAAAA==.Elixera:BAAALgAECgEJAQAAAA==.Elsä:BAAALgAECgUJAQAAAA==.Elémental:BAAALgAECggJCAAAAA==.',
Em='Emilwhaury:BAAALgAECgQJBAAAAA==.',
Ep='Epia:BAABLgAECn8jAAMcAAgJzQ9bKwBKAQAcAAgJwQ1bKwBKAQABAAMJVRPYTwCyAAAAAA==.',
Er='Eriena:BAAALgAECgYJEQAAAA==.',
Es='Esbjorn:BAAALgAECgEJAgAAAA==.Essaila:BAABLgAECn8yAAIPAAkJew46DwCfAQAPAAkJew46DwCfAQAAAA==.',
Et='Etheo:BAAALgAECgEJAQAAAA==.Etherwalker:BAABLgAECn8mAAMfAAkJQyQICgCvAgAfAAgJTyQICgCvAgAhAAQJkR/kIwAtAQAAAA==.',
Ev='Evocati:BAABLgAECn8YAAMiAAYJ2xeoEAA5AQAiAAYJ3hWoEAA5AQATAAYJGReumgAfAQABLgAFFAYJDgAEAHsWAA==.Evoka:BAABLgAECn8lAAMNAAgJjR7yDAAMAgANAAcJVx/yDAAMAgAJAAYJWRu4LQBmAQABLgAECgkJJQAgAHUbAA==.',
Ex='Excision:BAABLgAECn8kAAMNAAgJWA6yHgA5AQANAAcJcw2yHgA5AQAJAAcJ7wv9QQAAAQAAAA==.Exmachina:BAAALgADCgYJBgAAAA==.',
Fa='Fahbio:BAABLgAECn8hAAIVAAcJ2AGpMgB/AAAVAAcJ2AGpMgB/AAAAAA==.Fataliny:BAAALgADCgUJCAAAAA==.Fatallock:BAABLgAECn8uAAMQAAgJzBC3UgCYAQAQAAgJzBC3UgCYAQAaAAEJaQgbNwAzAAAAAA==.Fatlife:BAAALgADCgYJBgAAAA==.',
Fi='Fishdish:BAAALgAECgIJAgAAAA==.Fistsmither:BAAALgAECgYJCAABLgAECgcJIAAjABIUAA==.Fivevolts:BAABLgAECn8mAAIkAAgJoiJBAgCqAgAkAAgJoiJBAgCqAgAAAA==.',
Fl='Fladon:BAAALgADCgEJAQAAAA==.Flailuid:BAAALgAECgQJDQAAAA==.Flimfam:BAAALgAECgEJAQAAAA==.',
Fo='Forkin:BAAALgADCgIJAgAAAA==.Forthstryke:BAAALgAECgIJBgAAAA==.Four:BAAALgADCgUJBQAAAA==.Fozzi:BAAALgAECgYJCwAAAA==.',
Fr='Freddyg:BAAALgADCgMJBAAAAA==.Fridaychill:BAACLgAFFH8NAAIcAAQJohtvDABIAQAcAAQJohtvDABIAQAuAAQKfzQAAhwACAm5IqYJAJQCABwACAm5IqYJAJQCAAAA.Fries:BAEALgAECgEJAQABLgAFFAQJBwAQAKYPAA==.Frostdeeps:BAAALgAECgcJEwAAAA==.Frozarke:BAABLgAECn8nAAIJAAgJ9A0MNgA2AQAJAAgJ9A0MNgA2AQAAAA==.',
Fu='Fudd:BAABLgAECn8lAAIOAAcJnRrsQwC+AQAOAAcJnRrsQwC+AQAAAA==.Fupa:BAABLgAECn8nAAIOAAgJ0QzhWACBAQAOAAgJ0QzhWACBAQAAAA==.',
Ga='Gaiaslieg:BAAALgADCgMJAwAAAA==.Galand:BAAALgAECgYJBgAAAA==.Galathynius:BAAALgADCgUJBQAAAA==.Galeine:BAAALgADCgMJAwAAAA==.Gangplank:BAAALgADCgMJAwAAAA==.Garres:BAABLgAECn8cAAIPAAcJuh+4CgDwAQAPAAcJuh+4CgDwAQAAAA==.',
Ge='Genius:BAABLgAECn8bAAIhAAcJUBsvFQCcAQAhAAcJUBsvFQCcAQAAAA==.Gennosuke:BAAALgADCgcJBQAAAA==.',
Gh='Ghostkillaz:BAAALgADCgkJFwAAAA==.Ghostxkillaz:BAAALgADCgMJAwAAAA==.',
Gi='Gibley:BAABLgAECn8VAAIEAAgJ0BjlfgB8AQAEAAgJ0BjlfgB8AQAAAA==.',
Gl='Gladorf:BAAALgADCgYJBgAAAA==.',
Gn='Gnazgul:BAAALgAECgUJBgAAAA==.Gnomad:BAABLgAECn8lAAIGAAcJwwM01QDJAAAGAAcJwwM01QDJAAAAAA==.Gnomie:BAAALgAECgMJBAAAAA==.',
Go='Goat:BAAALgAECgYJDgAAAA==.Gouge:BAAALgAECgkJOgAAAQ==.',
Gr='Griffynshu:BAABLgAECn8lAAIXAAkJlBvsEQCtAgAXAAkJlBvsEQCtAgAAAA==.Griz:BAAALgAECgYJBgAAAA==.Grizzlyburr:BAABLgAECn8UAAIWAAcJjxLMHgAwAQAWAAcJjxLMHgAwAQABLgAFFAQJCAABANEOAA==.Grunewald:BAABLgAECn9YAAIOAAgJbA+qTQCgAQAOAAgJbA+qTQCgAQAAAA==.',
Gu='Guinn:BAAALgADCgIJAgABLgAECggJJwAJAPQNAA==.Gula:BAABLgAECn8hAAMaAAkJPxU/CQCxAQAQAAkJKBTRSAC0AQAaAAYJHRc/CQCxAQAAAA==.Guldanshower:BAAALgADCgUJBQAAAA==.Gunhild:BAAALgAECgIJAgAAAA==.Gutdiver:BAAALgADCgUJBQAAAA==.',
Ha='Handiboyswag:BAACLgAFFH8WAAICAAUJhiH7DgDoAQACAAUJhiH7DgDoAQAuAAQKfxkAAxgABwm4E5QgANQBABgABwm4E5QgANQBAAIABAnJIhYwAB8BAAAA.Hando:BAAALgAECgYJCAAAAA==.Hattock:BAAALgADCgcJFQAAAA==.Hayate:BAAALgAECgUJBQAAAA==.',
He='Heavyshlump:BAACLgAFFH8IAAIBAAQJ0Q7BIwAIAQABAAQJ0Q7BIwAIAQAuAAQKfyAAAgEACQlbFXIQACYCAAEACQlbFXIQACYCAAAA.Hehateme:BAAALgAECgIJAgAAAA==.Hehexd:BAABLgAECn8pAAIjAAgJARvUEwB3AgAjAAgJARvUEwB3AgAAAA==.Heimdall:BAACLgAFFH8GAAIUAAMJZgjhLQCqAAAUAAMJZgjhLQCqAAAuAAQKfxoAAhQACAnHHCESAG0CABQACAnHHCESAG0CAAAA.Hellavva:BAAALgAECgMJAwAAAA==.Hellzwar:BAAALgADCgUJBgAAAA==.Hench:BAAALgAECgYJBgAAAA==.Henchling:BAABLgAECn84AAMFAAkJGyApCQDkAgAFAAkJGyApCQDkAgARAAkJaRLfIADEAQAAAA==.Henchragon:BAAALgADCgUJBQAAAA==.',
Hi='Hissteria:BAAALgAECgIJAwAAAA==.',
Hn='Hngyhngyloko:BAABLgAECn8ZAAIGAAcJzxt5bQD6AQAGAAcJzxt5bQD6AQABLgAFFAMJCAAJAOYUAA==.',
Ho='Hoerified:BAAALgADCgEJAQABLgAECggJKQAjAAEbAA==.Holexios:BAAALgAECgQJCQABLgAECgYJFAAdAGwRAA==.Holybonks:BAAALgADCgcJBwAAAA==.Holycanoli:BAAALgAECgEJAgAAAA==.Holycrusade:BAAALgAECgUJCgAAAA==.Horine:BAABLgAECn8nAAIOAAgJmQ6XUwCPAQAOAAgJmQ6XUwCPAQAAAA==.Hotsteve:BAAALgAECgQJBwAAAA==.',
Hu='Huntër:BAAALgAECgQJBQAAAA==.Huruk:BAAALgAECgIJAgAAAA==.',
Hy='Hydranis:BAAALgADCgUJBQAAAA==.',
Ic='Icieblade:BAAALgAECgkJEQAAAA==.Icyscorcher:BAABLgAECn8iAAMGAAgJixQFXwCqAQAGAAgJixQFXwCqAQAlAAMJpwOyCwB3AAABLgAECgkJRAADAOodAA==.',
Ik='Ikairi:BAAALgAECgEJAQAAAA==.',
Il='Illidankness:BAAALgAECgQJBAAAAA==.Illidoran:BAAALgAECgUJBwABLgAFFAQJDAAGAJ4UAA==.',
Im='Immeira:BAABLgAECn8XAAIFAAYJIwp1bAD2AAAFAAYJIwp1bAD2AAAAAA==.',
In='Intense:BAAALgAECgcJAwAAAA==.',
Ja='Jackheals:BAACLgAFFH8NAAIXAAMJoxX5MQDYAAAXAAMJoxX5MQDYAAAuAAQKfzEAAxcACAnlIRMKAAkDABcACAnlIRMKAAkDAB4AAQnZAdqPABsAAAAA.Jaehaerys:BAAALgAECgQJCAABLgAECgkJJQAGAF4SAA==.Jagseer:BAAALgAECgQJBAABLgAECgkJKgACANAcAA==.',
Jb='Jblackly:BAAALgAECgYJCQAAAA==.',
Jf='Jfreeman:BAAALgADCgYJBwAAAA==.',
Ji='Jimzdrood:BAAALgAECgEJAQAAAA==.Jinbeyblade:BAAALgAECgMJAwABLgAFFAMJBwAOAOggAA==.Jinphoenix:BAACLgAFFH8HAAIOAAMJ6CDgOAAhAQAOAAMJ6CDgOAAhAQAuAAQKfycAAw4ACQlrIdAJAPUCAA4ACQlrIdAJAPUCABsABAmQB4xfAMMAAAAA.Jitb:BAAALgADCgYJBwABLgAFFAYJDgAdANANAA==.',
Jo='Jobin:BAACLgAFFH8PAAMTAAMJ4BKciADWAAATAAMJ4BKciADWAAAiAAEJSAHUIQA1AAAuAAQKfxkAAhMACAn5G0twAKgBABMACAn5G0twAKgBAAAA.Journei:BAABLgAECn8bAAIFAAgJXhHtNgC5AQAFAAgJXhHtNgC5AQAAAA==.',
Ju='Judging:BAABLgAECn8qAAMUAAgJIhabHwDwAQAUAAgJIhabHwDwAQAEAAIJHSWh2gDGAAAAAA==.Junkhead:BAAALgAECgIJAwAAAA==.',
Ka='Kaethe:BAAALgAECgYJBgAAAA==.Kaiduo:BAAALgADCgEJAQAAAA==.Kaitos:BAAALgAFFAIJBAABLgAFFAMJCQAEAD0eAA==.Kalmas:BAABLgAFFH8MAAIeAAMJHAjKLQCiAAAeAAMJHAjKLQCiAAAAAA==.',
Ke='Kegz:BAAALgADCggJCAABLgAECgkJKgACANAcAA==.Kelendrian:BAAALgAECgUJBQAAAA==.Kellayna:BAABLgAECn8fAAIEAAgJxgalpwAQAQAEAAgJxgalpwAQAQAAAA==.Kennyx:BAAALgAECgMJAwAAAA==.Kerine:BAAALgAECgMJBAAAAA==.Keylö:BAAALgAECgYJBgAAAA==.Kezix:BAABLgAECn8eAAIQAAkJlA5ESAC2AQAQAAkJlA5ESAC2AQAAAA==.',
Kh='Kharigosa:BAAALgAECgEJAQABLgAECggJFgAUAH8ZAA==.',
Ki='Kigerstorm:BAAALgADCgEJAQAAAA==.Kimeltoe:BAAALgADCgIJAgAAAA==.Kimigosa:BAABLgAECn8nAAQJAAgJfhGoIwChAQAJAAgJvA+oIwChAQANAAIJ7gvEIwAyAAAKAAEJwQF4TgAiAAAAAA==.Kimpachi:BAAALgAECgcJBwABLgAECggJJwAJAH4RAA==.',
Kl='Klerik:BAACLgAFFH8VAAIQAAUJqBVrQgAvAQAQAAUJqBVrQgAvAQAuAAQKfykABBAACQkaHwUbAHQCABAACQmyHQUbAHQCABkAAgkpEmxMAIgAABoAAQlxJJAtAE8AAAAA.',
Kn='Kníghtmare:BAAALgAECgYJDwAAAA==.',
Ko='Kolesnikov:BAAALgAECgUJCAAAAA==.Koragg:BAACLgAFFH8gAAIgAAUJiiHHDABwAQAgAAUJiiHHDABwAQAuAAQKfz4AAiAACQnwJRECACkDACAACQnwJRECACkDAAAA.Kore:BAABLgAECn8jAAIXAAYJZBYoRABsAQAXAAYJZBYoRABsAQAAAA==.Korrag:BAAALgAECgUJCAAAAA==.Kozarke:BAABLgAECn8qAAINAAgJfBXbBgDDAQANAAgJfBXbBgDDAQAAAA==.',
Kp='Kpop:BAABLgAECn8bAAIMAAkJfxktBwAWAgAMAAkJfxktBwAWAgABLgAFFAQJCAABANEOAA==.',
Kr='Krissia:BAABLgAECn8iAAITAAkJhhidSQDTAQATAAkJhhidSQDTAQAAAA==.',
Ku='Kumadbear:BAAALgADCgEJAQAAAA==.',
Ky='Kyntaliia:BAAALgAECgQJBAAAAA==.',
['Kí']='Kítsuñe:BAAALgAECgMJAwAAAA==.',
['Kî']='Kîn:BAABLgAECn8kAAILAAcJxhQdXQBYAQALAAcJxhQdXQBYAQAAAA==.',
La='Ladriana:BAAALgADCgEJAgAAAA==.Laisera:BAABLgAECn8zAAMmAAkJmRA5IgCbAQAmAAkJmRA5IgCbAQAYAAEJdQa0gAApAAAAAA==.Lalipop:BAABLgAECn83AAImAAkJbBa0EABJAgAmAAkJbBa0EABJAgAAAA==.Landroval:BAABLgAECn8lAAIJAAgJYRq9FwAAAgAJAAgJYRq9FwAAAgAAAA==.Lauma:BAACLgAFFH8MAAIFAAMJFQZTTACjAAAFAAMJFQZTTACjAAAuAAQKfxUAAgUABwmwEppDAIMBAAUABwmwEppDAIMBAAAA.Lawson:BAABLgAECn81AAITAAkJYxxbHwB5AgATAAkJYxxbHwB5AgAAAA==.',
Le='Lelora:BAAALgAECgUJCQAAAA==.Lenthaden:BAABLgAECn86AAMQAAkJOBjdKgAhAgAQAAkJDBbdKgAhAgAZAAYJqxNeJQAyAQAAAA==.Lexusis:BAAALgADCgIJAgAAAA==.',
Li='Lightsmasher:BAAALgAECgEJAQAAAA==.Lihaeh:BAAALgADCgEJAQAAAA==.Lildipper:BAAALgAECgYJCwABLgAFFAQJCAABANEOAA==.Lio:BAAALgAECgYJDgAAAA==.Lissetteliz:BAAALgAECgQJBQAAAA==.Livdangerous:BAAALgADCgUJBQAAAA==.',
Lo='Lomax:BAAALgAECgEJAQAAAA==.Longlegs:BAAALgADCgYJBgAAAA==.',
Lu='Lumawig:BAAALgAECgUJDQAAAA==.Lumillras:BAAALgADCgYJCgAAAA==.Lunchdk:BAACLgAFFH8NAAMgAAMJOhebDgCAAAATAAIJJR5hpgCfAAAgAAIJBwybDgCAAAAuAAQKfykAAxMACQlzH1oUALsCABMACAlXI1oUALsCACAACAlzF2gVALwBAAAA.',
Ly='Lyreth:BAABLgAECn8pAAIeAAkJJRDdIACnAQAeAAkJJRDdIACnAQAAAA==.',
Ma='Madax:BAABLgAECn86AAMfAAkJxiFoCgCrAgAfAAkJGCFoCgCrAgADAAkJTxynBgCKAgABLgAFFAIJBQANANoHAA==.Mageymutt:BAACLgAFFH8YAAIGAAcJ7RZbDAC7AQAGAAcJ7RZbDAC7AQAuAAQKfyUAAwYACAmNIKElANwCAAYACAmNIKElANwCACcAAwkmCx8UAIQAAAAA.Maggidabeast:BAABLgAECn8pAAIGAAgJ8QSgrAALAQAGAAgJ8QSgrAALAQAAAA==.Magnion:BAAALgAECgEJAQAAAA==.Maison:BAAALgAECgQJBQAAAA==.Malase:BAAALgADCgUJAwAAAA==.Maloch:BAAALgADCgUJBQAAAA==.',
Me='Meaculpa:BAAALgADCgUJCgAAAA==.Megamilk:BAACLgAFFH8LAAIiAAQJDQrbDAAHAQAiAAQJDQrbDAAHAQAuAAQKfzYAAiIACQkFGy8FAD8CACIACQkFGy8FAD8CAAAA.Mekri:BAAALgADCgYJBgABLgAECgcJJAAEABcbAA==.Melledreaux:BAAALgADCgMJAwAAAA==.Metrolinea:BAACLgAFFH8PAAIGAAUJXRGSUQAuAQAGAAUJXRGSUQAuAQAuAAQKfzkAAgYACQkqH1IRAN8CAAYACQkqH1IRAN8CAAAA.',
Mi='Micalknight:BAAALgAECgIJAQAAAA==.Milliy:BAAALgAECgQJBwAAAA==.Minervá:BAAALgADCgMJAwABLgAFFAMJDQAXANEeAA==.Missbehaving:BAABLgAECn8hAAMmAAcJjRSdLABPAQAmAAcJjRSdLABPAQAYAAEJQQemfwAqAAAAAA==.',
Mo='Monkdluffy:BAAALgADCgEJAQAAAA==.Morefire:BAAALgAECgQJCgABLgAECgkJEwAHAAAAAA==.Mosmos:BAAALgADCgkJFQAAAA==.',
Mu='Muddslinger:BAABLgAECn8ZAAIfAAgJJAs4OQBMAQAfAAgJJAs4OQBMAQAAAA==.Mumra:BAABLgAECn8yAAQmAAgJRQYSNQAXAQAmAAgJRQYSNQAXAQACAAYJdgFaPwC0AAAYAAEJAACOjQAAAAAAAA==.',
My='Mystblade:BAAALgAECgIJAgAAAA==.Mystlord:BAAALgAECgQJBAAAAA==.',
Na='Nadatank:BAAALgADCgQJBAAAAA==.Nalesean:BAAALgAECgYJCQAAAA==.Nanaki:BAABLgAECn8iAAIKAAkJKyDzBgDQAgAKAAkJKyDzBgDQAgAAAA==.Nannette:BAAALgAECgYJEgAAAA==.Nappe:BAAALgAECgEJAQABLgAECgkJHwAEAIElAA==.Narag:BAABLgAECn8xAAIOAAkJDxm6HQBeAgAOAAkJDxm6HQBeAgAAAA==.Nazfu:BAAALgAECgEJAgAAAA==.Nazg:BAAALgADCgQJAgAAAA==.',
Ne='Nerfertari:BAAALgAECgEJBQAAAA==.Netanyahoo:BAAALgAFFAIJAgAAAA==.Neva:BAAALgAECgIJAgAAAA==.Newport:BAABLgAECn8sAAMFAAgJbx9GEAC2AgAFAAgJbx9GEAC2AgARAAIJmAhjgwBNAAAAAA==.',
Ni='Ninex:BAABLgAECn8cAAIUAAgJTR/RGABMAgAUAAgJTR/RGABMAgAAAA==.Ninisina:BAABLgAECn84AAMFAAgJnB+qDwC9AgAFAAgJnB+qDwC9AgASAAEJ7wOHLgAsAAAAAA==.Nithén:BAAALgADCgYJDQAAAA==.',
No='Nonaleeta:BAAALgAECgQJCAAAAA==.Notafurry:BAAALgADCgcJCQAAAA==.Novaa:BAAALgAECgcJAwAAAA==.Nowhere:BAAALgAECgUJBQABLgAECgcJIAAjABIUAA==.Nowon:BAABLgAECn8dAAMoAAYJ1xO0JgAfAQAoAAYJ1xO0JgAfAQAMAAEJpwh2NQAcAAABLgAECgkJAQAHAAAAAA==.',
Nu='Nudream:BAABLgAECn8eAAIUAAkJyQMzPAA/AQAUAAkJyQMzPAA/AQAAAA==.',
Ny='Nybors:BAAALgADCgcJCwAAAA==.',
['Nö']='Nörse:BAABLgAECn8aAAMeAAYJDhBfRQDaAAAeAAYJCA9fRQDaAAAPAAEJpBd4PQBGAAAAAA==.',
Ol='Olakua:BAAALgAECgMJAwAAAA==.Oldjerry:BAABLgAECn8gAAIjAAcJEhSpHwB+AQAjAAcJEhSpHwB+AQAAAA==.Oliaa:BAAALgADCgYJCAAAAA==.',
Oo='Oomdeath:BAAALgADCgEJAQAAAA==.',
Op='Opalyte:BAABLgAECn8kAAImAAcJ1A08NgAQAQAmAAcJ1A08NgAQAQAAAA==.',
Or='Orichalcum:BAABLgAECn8oAAIdAAgJth43DAC3AgAdAAgJth43DAC3AgAAAA==.Orphiee:BAAALgAECgYJEQAAAA==.',
Os='Oslagsi:BAAALgADCgcJDgAAAA==.Osyriss:BAAALgADCgUJBgAAAA==.',
Ot='Othril:BAAALgAECgEJAQAAAA==.',
Ou='Outis:BAAALgAFFAMJBgAAAQ==.',
Pa='Pakoros:BAABLgAECn82AAMFAAkJch1RCwDtAgAFAAkJch1RCwDtAgARAAQJBwp7agCZAAAAAA==.Palibuddy:BAAALgAECgMJAwAAAA==.Pallyfreak:BAAALgAECgUJCgAAAA==.',
Pe='Peachy:BAAALgAECgQJBAABLgAECggJKgAFAKoWAA==.Penderin:BAAALgAECgkJCwAAAA==.Penilock:BAAALgADCgIJAgAAAA==.Pensham:BAAALgAECgEJAwABLgAECgkJCwAHAAAAAA==.Perlindree:BAABLgAECn80AAIOAAgJDwiTaQBXAQAOAAgJDwiTaQBXAQAAAA==.',
Pg='Pgorlelgy:BAABLgAECn8sAAIOAAkJ/hYoKgAeAgAOAAkJ/hYoKgAeAgAAAA==.',
Ph='Phira:BAAALgADCgEJAQAAAA==.Phoenix:BAAALgADCgIJAgAAAA==.Physgun:BAAALgADCgYJDgAAAA==.',
Pi='Pillows:BAAALgADCgYJBgAAAA==.',
Pl='Platious:BAABLgAECn8qAAIEAAcJ/BSucAByAQAEAAcJ/BSucAByAQAAAA==.',
Po='Pony:BAAALgADCgUJBQABLgADCgUJCgAHAAAAAA==.Poodin:BAAALgADCgIJAgAAAA==.Pookaboo:BAABLgAECn8VAAIQAAcJCwKZ1wCVAAAQAAcJCwKZ1wCVAAAAAA==.Poppers:BAAALgADCgYJCwAAAA==.',
Pr='Preacharond:BAACLgAFFH8RAAIYAAQJ5BTEEwAwAQAYAAQJ5BTEEwAwAQAuAAQKf0kAAhgACQkeINUGAMsCABgACQkeINUGAMsCAAAA.Promir:BAAALgAECgcJDgAAAA==.',
Pu='Purdie:BAAALgAECgQJBwABLgAECggJJwAFAP4MAA==.',
Qe='Qeesa:BAAALgAECgIJAwAAAA==.',
Qi='Qiryana:BAAALgADCgIJAgAAAA==.',
Ra='Raeliene:BAABLgAECn8kAAIEAAkJKB1IHQB+AgAEAAkJKB1IHQB+AgAAAA==.Rafikie:BAAALgAECgIJAwAAAA==.Ratchet:BAAALgADCgMJAwAAAA==.Rawmeat:BAABLgAECn86AAICAAkJxBxYCgCuAgACAAkJxBxYCgCuAgAAAA==.Razillar:BAAALgAECgEJAQAAAA==.',
Re='Rebelpatriot:BAAALgADCgYJCQAAAA==.Redbearrd:BAAALgADCgkJCQABLgAECgkJJQAGAF4SAA==.Relaxnerdlol:BAAALgAECgEJBAAAAA==.Reldwick:BAAALgADCgYJBwAAAA==.Renew:BAABLgAECn8mAAMmAAkJHB6eCADMAgAmAAkJHB6eCADMAgAYAAgJ1BWiGwDLAQAAAA==.Renix:BAACLgAFFH8SAAIRAAQJCRkOGgAjAQARAAQJCRkOGgAjAQAuAAQKfzIAAxEACQlmH78LAJMCABEACQlmH78LAJMCABIAAQl1CxYtADIAAAAA.Reno:BAAALgAECgMJAwAAAA==.Revery:BAAALgADCgIJAgAAAA==.',
Rh='Rhadgar:BAAALgADCgcJCQAAAA==.',
Ri='Ripmyname:BAAALgAECgYJBgAAAA==.Riverah:BAAALgAECgQJCAAAAA==.Rivulet:BAAALgAECgUJDAAAAA==.',
Ro='Roombaa:BAAALgADCgQJAgAAAA==.Royfenix:BAABLgAECn8kAAQmAAYJ2RlaHwCyAQAmAAYJ2RlaHwCyAQAYAAMJJQ18VwCKAAACAAMJ4QKmXwBPAAABLgAFFAQJDAAGAJ4UAA==.',
Ru='Rukaillin:BAAALgAECgYJBwAAAA==.',
Ry='Ryukaii:BAAALgAECgYJBwAAAA==.Ryyah:BAABLgAECn83AAMUAAgJjBiMGAAsAgAUAAgJjBiMGAAsAgAEAAQJLQOdLwFeAAAAAA==.',
['Rè']='Rèck:BAAALgAECgUJCAAAAA==.',
['Ré']='Rébecca:BAAALgAECgMJAwABLgAECgkJKQAgAOUMAA==.',
['Rì']='Rìsen:BAAALgADCgYJBgAAAA==.',
['Rú']='Rústy:BAAALgAFFAIJAwAAAA==.',
Sa='Sabris:BAAALgAECgMJAwAAAA==.Saetyl:BAABLgAECn8jAAIeAAgJlwMCSwDDAAAeAAgJlwMCSwDDAAAAAA==.Saga:BAAALgADCgEJAQAAAA==.Salvynus:BAAALgAECgUJBQAAAA==.Samhainn:BAAALgADCgIJAQABLgADCgYJBQAHAAAAAA==.Sanctity:BAAALgAECgMJAwAAAA==.Saphirè:BAAALgAECgUJAQAAAA==.',
Sc='Scrungle:BAAALgADCgYJCwAAAA==.',
Se='Seabiscuìt:BAAALgAECgIJAgAAAA==.Seanthaniel:BAEALgAECgYJBwABLgAFFAcJJAAgAIYQAA==.Seifslam:BAAALgADCgQJBAABLgAECgEJAQAHAAAAAA==.Seifura:BAAALgAECgEJAQAAAA==.Semi:BAAALgAECgQJBQABLgAECgkJKQAUAOohAA==.Semii:BAAALgAECgIJAgAAAA==.Serkerune:BAAALgAECgEJAQAAAA==.Serkesul:BAABLgAECn8qAAIYAAgJQSS4BwC8AgAYAAgJQSS4BwC8AgAAAA==.Sevinas:BAABLgAECn8nAAISAAgJ8g1BEgBxAQASAAgJ8g1BEgBxAQAAAA==.',
Sf='Sfogliatella:BAAALgAECgEJAQAAAA==.',
Sh='Shaftstop:BAAALgADCgkJCQABLgAECgUJBQAHAAAAAA==.Shamallamá:BAAALgADCgkJCgABLgAECggJLQAOABUiAA==.Shamthis:BAABLgAECn8dAAIRAAkJKw3BKwB9AQARAAkJKw3BKwB9AQAAAA==.Shamwoww:BAACLgAFFH8GAAIRAAMJURAdKwDGAAARAAMJURAdKwDGAAAuAAQKfyEAAhEACAkQHmsQAFoCABEACAkQHmsQAFoCAAEuAAUUBAkRABgA5BQA.Shamyou:BAABLgAECn8UAAMFAAkJ1xnQGwA6AgAFAAkJ1xnQGwA6AgARAAYJKRrTMwBRAQAAAA==.Shealie:BAAALgADCgMJAwABLgAECgkJNQAjAI8dAA==.Shelly:BAAALgAECgUJBQAAAA==.Shiftymynx:BAAALgADCgEJAQAAAA==.Shlumpa:BAABLgAECn8aAAIFAAgJnRv8GQBgAgAFAAgJnRv8GQBgAgABLgAFFAQJCAABANEOAA==.Shlumpdragon:BAAALgAECgMJAwABLgAFFAQJCAABANEOAA==.Shlumpydk:BAAALgAFFAIJBAAAAA==.Shokcz:BAAALgAECgQJBQAAAA==.Shomba:BAAALgAECgYJBgAAAA==.Shotsfired:BAAALgAECgYJCgAAAA==.Shámjackson:BAACLgAFFH8XAAIFAAUJRyZzBgAlAgAFAAUJRyZzBgAlAgAuAAQKfy4AAgUACQkMJg4EAGMDAAUACQkMJg4EAGMDAAAA.',
Si='Silvey:BAABLgAECn8pAAILAAgJwiEbEwCWAgALAAgJwiEbEwCWAgAAAA==.Sindricil:BAAALgADCggJDAAAAA==.',
Sk='Skar:BAAALgADCggJCQAAAA==.Skeletorque:BAABLgAECn8UAAMTAAgJTBA4igA7AQATAAgJTBA4igA7AQAgAAEJXA2nSwAfAAAAAA==.Skully:BAAALgAECgEJAQAAAA==.Skyylorne:BAABLgAECn8ZAAIPAAcJSQ8FGAAsAQAPAAcJSQ8FGAAsAQAAAA==.',
Sl='Slipnslide:BAAALgADCgYJBgABLgAECgkJOgACAMQcAA==.',
Sm='Smallwdruid:BAAALgAECgYJBgAAAA==.Smashlock:BAAALgADCgUJCAAAAA==.Smellydruid:BAAALgADCgEJAQAAAA==.Smitesword:BAAALgADCgYJDAAAAA==.',
Sn='Snow:BAAALgAECgYJBgABLgAECgkJIgAKACsgAA==.Snowfawn:BAABLgAECn8lAAIOAAcJFRk9QQDGAQAOAAcJFRk9QQDGAQABLgAECgkJKQAUANkRAA==.Snusnurae:BAAALgAECgYJEAAAAA==.',
So='Sodapoppin:BAAALgADCgcJBwAAAA==.Solas:BAAALgADCgQJBQAAAA==.Somay:BAAALgAECgQJBwAAAA==.Soryn:BAAALgADCgUJBQAAAA==.Sovirus:BAAALgAECgQJBAABLgAECgkJIgAKACsgAA==.',
Sp='Spanana:BAABLgAFFH8MAAITAAQJThK3FQBNAQATAAQJThK3FQBNAQAAAA==.Sparevolts:BAAALgAECgEJAQAAAA==.Specialist:BAAALgAFFAIJAwAAAA==.Spicychopz:BAACLgAFFH8YAAIGAAgJeSNpBACzAgAGAAgJeSNpBACzAgAuAAQKfxcAAgYACAnbIRUdAAEDAAYACAnbIRUdAAEDAAAA.Spiketickevi:BAAALgAECggJCAAAAA==.Splishsplásh:BAABLgAECn8nAAIFAAgJCh9JDwDAAgAFAAgJCh9JDwDAAgAAAA==.Sprattyboii:BAAALgAFFAEJAgAAAA==.Sprucelock:BAAALgADCgIJAgAAAA==.',
Ss='Sscarlet:BAABLgAECn8ZAAIGAAkJWAYTggBYAQAGAAkJWAYTggBYAQAAAA==.',
St='Staltis:BAAALgAECgMJBAABLgAECggJJwAJAPQNAA==.Starrling:BAABLgAECn8WAAIeAAgJNhRTIACsAQAeAAgJNhRTIACsAQAAAA==.Starzia:BAABLgAECn8oAAICAAgJegcmMAA4AQACAAgJegcmMAA4AQAAAA==.Stupidtree:BAACLgAFFH8PAAIXAAQJTx3iHABSAQAXAAQJTx3iHABSAQAuAAQKfxwAAhcABwnMIyUTAKECABcABwnMIyUTAKECAAAA.',
Su='Sudzyjr:BAAALgADCgUJBQAAAA==.Sunk:BAABLgAECn8qAAIQAAgJbBx8KQAnAgAQAAgJbBx8KQAnAgAAAA==.',
Sw='Swagg:BAAALgAECgEJAQAAAA==.Swanho:BAAALgAECgIJBQABLgAECgcJBwAHAAAAAA==.Swiftblossom:BAAALgAECgEJAQAAAA==.',
Sy='Sylvanex:BAABLgAECn8VAAIOAAYJyxlnWwB6AQAOAAYJyxlnWwB6AQAAAA==.',
['Sê']='Sêrënîty:BAAALgADCgEJAQABLgAFFAQJDgAEAN8SAA==.',
['Sô']='Sông:BAAALgAECgUJBQAAAA==.',
Ta='Taffbones:BAAALgAECgYJCgAAAA==.Tahla:BAAALgADCgIJAgAAAA==.Talanot:BAAALgAECgUJCwABLgAECgYJFAAdAGwRAA==.Talarus:BAAALgAECggJEQAAAA==.Talurana:BAAALgAECgEJAgAAAA==.Tanadria:BAABLgAECn8kAAIjAAkJCwzrGAC5AQAjAAkJCwzrGAC5AQAAAA==.Tangerene:BAACLgAFFH8HAAICAAMJbAGmMACUAAACAAMJbAGmMACUAAAuAAQKfx0AAwIACAkuCQYuAC4BAAIABwlMCgYuAC4BACYABgkUAhteALoAAAAA.Tapioca:BAACLgAFFH8PAAIOAAQJ1iDAGAB1AQAOAAQJ1iDAGAB1AQAuAAQKfzIAAg4ACQkHI0IGAB8DAA4ACQkHI0IGAB8DAAAA.Tashyr:BAAALgAECgMJBAAAAA==.',
Tc='Tchort:BAAALgAECgQJBAABLgAFFAcJGAAGAO0WAA==.',
Te='Telemachus:BAAALgAECgEJAQAAAA==.Telm:BAABLgAECn8kAAMEAAcJFxtgYACWAQAEAAcJcxlgYACWAQAVAAcJShpiFQBhAQAAAA==.Tentilious:BAAALgADCgkJEQAAAA==.',
Th='Thadeusputz:BAAALgAECgEJAQAAAA==.Thaÿne:BAAALgAECggJEgAAAA==.Thebestpally:BAACLgAFFH8LAAMEAAMJtBPkXwDPAAAEAAMJAg3kXwDPAAAVAAEJkRY6EwBDAAAuAAQKf0MAAxUACQleHKsEAJoCABUACQleHKsEAJoCAAQABQmNDQXlAMQAAAAA.Thenemisis:BAAALgADCgcJDwAAAA==.Thiccidàn:BAAALgADCgEJAgAAAA==.Thund:BAAALgAECgQJBwAAAA==.',
Ti='Tianielan:BAABLgAECn8ZAAMUAAgJISBEFwA4AgAUAAgJISBEFwA4AgAEAAEJJQ59QgEzAAAAAA==.Tidds:BAABLgAECn8qAAMQAAgJegpDaQBfAQAQAAgJegpDaQBfAQAaAAIJYgjjLQBOAAAAAA==.',
To='To:BAAALgAECgYJBgAAAA==.Toolgunx:BAAALgAECgQJBQAAAA==.Totemdown:BAACLgAFFH8aAAIFAAcJDh8fAgCPAgAFAAcJDh8fAgCPAgAuAAQKfyMAAgUACQm1I0cFAEoDAAUACQm1I0cFAEoDAAAA.',
Tr='Tralth:BAAALgAECgIJAgAAAA==.Trazarath:BAACLgAFFH8UAAMJAAUJzAubLAD1AAAJAAUJzAubLAD1AAANAAEJAAAUEQAAAAAuAAQKfysAAwkACQknFd4WAB8CAAkACQknFd4WAB8CAA0AAwkmBKczAHcAAAAA.Triggaman:BAAALgADCgUJBQABLgAECgcJJAAEABcbAA==.Trunndle:BAAALgADCgUJBQAAAA==.',
Ts='Tsuul:BAAALgAECgQJCwAAAA==.',
Tu='Turbolover:BAAALgAECgEJAQAAAA==.',
['Tã']='Tãpioca:BAAALgAECgQJCgABLgAFFAQJDwAOANYgAA==.',
Uj='Ujio:BAABLgAECn8XAAMUAAYJzBnrLQCQAQAUAAYJzBnrLQCQAQAEAAMJpwd/GQF1AAABLgAECggJIAAFAIYVAA==.',
Un='Unholyferret:BAAALgADCgIJAgAAAA==.Unify:BAAALgADCgMJBAAAAA==.Untiler:BAAALgADCgUJBQAAAA==.',
Us='Usdaprime:BAAALgAECgIJAwAAAA==.Usopp:BAAALgADCgYJBgAAAA==.',
Uu='Uuyd:BAAALgAFFAEJAgABLgAFFAMJBgAHAAAAAQ==.',
Va='Vaden:BAAALgAECgIJAgABLgAECgYJHgAIAPQTAA==.Vaelthys:BAABLgAECn8WAAIYAAcJWxOgJgB3AQAYAAcJWxOgJgB3AQABLgAECgkJKAAQAHwXAA==.Valedarrin:BAAALgADCgEJAQAAAA==.Valefyre:BAAALgADCgcJBwAAAA==.Valenstrasz:BAACLgAFFH8FAAMNAAIJ2gfkCACGAAANAAIJlQbkCACGAAAJAAIJtQZ0TABxAAAuAAQKfyIAAwkACQmGEjIfAMkBAAkACAkSEzIfAMkBAA0ABAn6DmgXAIoAAAAA.Valetherin:BAAALgADCgkJCQAAAA==.Valkaron:BAAALgADCgYJBgABLgAFFAMJCwAEAIoWAA==.Vanaheim:BAAALgAECgkJDgAAAA==.Vance:BAABLgAECn8WAAIEAAYJug2UtgD5AAAEAAYJug2UtgD5AAAAAA==.Vanitha:BAAALgADCggJBgAAAA==.Vanysh:BAAALgAECgMJAwAAAA==.Varala:BAAALgAECgMJAwAAAA==.',
Ve='Vel:BAACLgAFFH8VAAMTAAcJKByQEQACAgATAAcJKByQEQACAgAgAAEJAACLUgAAAAAuAAQKf0AAAhMACAkQJqAKAEcDABMACAkQJqAKAEcDAAAA.Velandis:BAAALgADCgcJBwAAAA==.Velenari:BAAALgAECgEJAQABLgAECgkJKgACANAcAA==.Vellea:BAAALgAECgYJDgABLgAECgYJFAAdAGwRAA==.Velwar:BAAALgAECgcJCQABLgAFFAcJFQATACgcAA==.Velýth:BAAALgAECgUJDAABLgAFFAcJFQATACgcAA==.Venmeumshna:BAAALgADCgYJBgAAAA==.Veritas:BAAALgAECgYJCwAAAA==.Vexxius:BAACLgAFFH8FAAIIAAIJfRiHIQCiAAAIAAIJfRiHIQCiAAAuAAQKfxwABAgACQkJGcwPACUCAAgACQn8FMwPACUCABsABwkxFAQTABYBAA4AAQkgD0kNATgAAAAA.',
Vi='Viero:BAAALgAECgcJBwAAAA==.',
Vo='Vorathis:BAAALgAECgYJDAABLgAFFAUJGAAFAOQkAA==.',
Vy='Vylana:BAAALgAECgYJDAABLgAFFAQJDgAEAN8SAA==.',
['Và']='Vàlkyrie:BAACLgAFFH8LAAIEAAMJihaBVADjAAAEAAMJihaBVADjAAAuAAQKfyIAAgQACQkCHnEiAKACAAQACQkCHnEiAKACAAAA.',
Wa='Wack:BAAALgAFFAEJAQAAAA==.Wanderfoot:BAABLgAECn8eAAIIAAYJ9BNFJwBUAQAIAAYJ9BNFJwBUAQAAAA==.Wangtulo:BAAALgADCgIJAgAAAA==.Warienta:BAAALgAECgMJAwAAAA==.Warity:BAABLgAECn8yAAIQAAgJyhY/PADdAQAQAAgJyhY/PADdAQAAAA==.Warnarse:BAAALgADCgUJBQAAAA==.Warrill:BAEBLgAECn8bAAIDAAgJ/QknIwAlAQADAAgJ/QknIwAlAQAAAA==.Wavestabe:BAABLgAECn86AAIPAAgJ5Bg9CgD8AQAPAAgJ5Bg9CgD8AQABLgAECgkJCwAHAAAAAA==.',
Wo='Wobblart:BAAALgAECgQJBgABLgAECgkJCwAHAAAAAA==.',
Wr='Wreck:BAACLgAFFH8FAAMaAAIJbwKAJQAoAAAQAAEJ7gP8twA9AAAaAAEJ7wCAJQAoAAAuAAQKfysAAhAACAn3DthgAHMBABAACAn3DthgAHMBAAAA.',
Xe='Xeevala:BAAALgAECgYJEAAAAA==.Xerxseize:BAAALgAECgEJAQAAAA==.',
Xo='Xomby:BAAALgAECgUJBQAAAA==.',
['Xì']='Xìon:BAAALgAECgkJEAAAAA==.',
Ya='Yayrri:BAABLgAECn8qAAIRAAgJqRGMLAB5AQARAAgJqRGMLAB5AQAAAA==.',
Ye='Yersipestis:BAAALgADCgYJBgAAAA==.',
Yo='Youngjedi:BAAALgAECgUJBQAAAA==.',
Yu='Yurî:BAAALgAECgQJCQAAAA==.',
Za='Zahne:BAAALgAECgMJAwAAAA==.Zatarra:BAAALgAECgIJBAAAAA==.Zathamax:BAABLgAECn8VAAIGAAgJaQPYxQDiAAAGAAgJaQPYxQDiAAAAAA==.Zavya:BAAALgADCgIJAgABLgAECgcJHAABAFgKAA==.',
Ze='Zeldei:BAAALgADCgEJAQAAAA==.Zextron:BAABLgAECn8tAAIoAAkJzxHIFQC7AQAoAAkJzxHIFQC7AQAAAA==.',
Zi='Ziaya:BAABLgAECn8cAAIBAAcJWAplPwDrAAABAAcJWAplPwDrAAAAAA==.Zin:BAAALgADCgQJBAAAAA==.',
Zo='Zolaeus:BAAALgAECgUJDQABLgAECgYJFAAdAGwRAA==.Zorbaks:BAAALgAECgQJBAAAAA==.',
Zu='Zuboo:BAABLgAECn8oAAIoAAgJ6wd0JwAZAQAoAAgJ6wd0JwAZAQAAAA==.',
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
