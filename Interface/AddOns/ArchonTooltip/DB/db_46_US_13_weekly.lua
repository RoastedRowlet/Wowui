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

local lookup = {'Monk-Brewmaster','Priest-Discipline','Warrior-Protection','Paladin-Retribution','Shaman-Restoration','Mage-Frost','Druid-Feral','Hunter-Survival','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','DemonHunter-Devourer','DemonHunter-Vengeance','Hunter-BeastMastery','Warlock-Demonology','Shaman-Elemental','Shaman-Enhancement','DeathKnight-Unholy','Paladin-Holy','Paladin-Protection','Druid-Guardian','Unknown-Unknown','Druid-Restoration','Priest-Shadow','Warlock-Destruction','Warlock-Affliction','Hunter-Marksmanship','Monk-Windwalker','Monk-Mistweaver','Druid-Balance','Warrior-Fury','DeathKnight-Blood','Warrior-Arms','DeathKnight-Frost','Rogue-Subtlety','Rogue-Assassination','Mage-Fire','Priest-Holy','Mage-Arcane','DemonHunter-Havoc',}
local provider = {region='US',realm='Antonidas',name='US',type='weekly',zone=46,date='2026-06-06',data={Aa='Aalst:BAABLgAECn8jAAIBAAgJxQkvMgAwAQABAAgJxQkvMgAwAQAAAA==.',
Ac='Achillesheal:BAABLgAECn8ZAAICAAYJoR8SFAAMAgACAAYJoR8SFAAMAgAAAA==.Acidicwrath:BAAALgADCgUJBQAAAA==.Acnologias:BAAALgAECgEJAQABLgAFFAMJBgADACYVAA==.Acshec:BAAALgADCgYJDgABLgAECgcJJAAEABcbAA==.Acuna:BAAALgAECgcJCQAAAA==.',
Ad='Aderna:BAAALgADCgMJBAAAAA==.Adoryn:BAEBLgAECn9CAAIBAAkJ7BCAGwDBAQABAAkJ7BCAGwDBAQAAAA==.',
Ae='Aervyper:BAAALgADCgIJAwAAAA==.Aessan:BAAALgAECgEJAQABLgAECggJJwAFAP4MAA==.',
Ag='Aggrenox:BAABLgAECn8gAAIEAAYJ5QlhrwAlAQAEAAYJ5QlhrwAlAQAAAA==.',
Ai='Aisathya:BAABLgAECn8iAAIGAAkJ0COkCQApAwAGAAkJ0COkCQApAwAAAA==.',
Ak='Akiza:BAAALgAECgkJDwAAAA==.Akonorix:BAAALgADCgUJCAAAAA==.',
Al='Alaelis:BAAALgAECgYJCAAAAA==.Albina:BAAALgAECgUJDwAAAA==.Aldelvir:BAABLgAECn8VAAIGAAgJAwUBsQAcAQAGAAgJAwUBsQAcAQABLgAECgkJPAAHAD4aAA==.Alottarage:BAAALgADCgcJCQAAAA==.Alunantre:BAABLgAECn8aAAIIAAkJ6BTKGQDMAQAIAAkJ6BTKGQDMAQAAAA==.Alzhimers:BAAALgAECggJEwAAAA==.',
Am='Amberscale:BAACLgAFFH8PAAIJAAQJWhfjJgAbAQAJAAQJWhfjJgAbAQAuAAQKfy4ABAkACQkxHDINAIQCAAkACQkxHDINAIQCAAoAAwlfHasPAAUBAAsAAQm3FUs2AEEAAAAA.Amyrrin:BAABLgAECn8cAAIEAAgJ3hKxdAB5AQAEAAgJ3hKxdAB5AQAAAA==.',
An='Ancientiur:BAABLgAECn8dAAMMAAkJdBtRNgDhAQAMAAkJUhlRNgDhAQANAAMJ+RJuJABrAAAAAA==.Andormu:BAAALgADCgYJBQAAAA==.Andracca:BAABLgAECn8aAAMJAAgJVxPgKQCQAQAJAAgJSBLgKQCQAQAKAAQJnxUxEQDpAAAAAA==.Angrulus:BAABLgAECn89AAIOAAkJMiEHCAAUAwAOAAkJMiEHCAAUAwAAAA==.Animal:BAAALgAECgQJBQAAAA==.Animlshiftr:BAABLgAECn8jAAIHAAgJrg23FgBMAQAHAAgJrg23FgBMAQAAAA==.',
Ap='Apollo:BAABLgAECn8wAAIPAAgJ+guqaQBlAQAPAAgJ+guqaQBlAQAAAA==.',
Ar='Aradunn:BAACLgAFFH8cAAIFAAUJ5CRZCQAQAgAFAAUJ5CRZCQAQAgAuAAQKfyYABAUACQk3IvsGAAQDAAUACQk3IvsGAAQDABAAAwkkHXtLAPYAABEAAgmeI08vAGMAAAAA.Araedis:BAABLgAECn89AAIIAAkJ/xCFEgARAgAIAAkJ/xCFEgARAgAAAA==.Araelle:BAAALgAECgEJAQAAAA==.Archangel:BAAALgAECgYJCwAAAA==.Arrill:BAEALgAECgMJAwABLgAECggJGwADAP0JAA==.Artheren:BAAALgAECgQJBgAAAA==.Aryllyn:BAAALgADCgYJDgAAAA==.',
As='Ashvehtta:BAABLgAECn8XAAISAAgJ2gnPgABZAQASAAgJ2gnPgABZAQAAAA==.Assaelysia:BAAALgAECgIJAgAAAA==.Asstormrage:BAAALgADCgUJBQAAAA==.Asti:BAAALgAECgcJDgAAAA==.Astralon:BAAALgAECgIJAwAAAA==.',
At='Atharion:BAABLgAECn8mAAMTAAkJch0kDwCaAgATAAgJpR4kDwCaAgAEAAYJjhZaqgAbAQAAAA==.Atheus:BAAALgADCgEJAgAAAA==.',
Av='Avanda:BAAALgAECgEJBQAAAA==.Avaria:BAAALgAECgIJAgAAAA==.Avrassa:BAAALgADCgMJAwAAAA==.',
Aw='Awperprime:BAABLgAECn8tAAIRAAkJ/ReUBwBFAgARAAkJ/ReUBwBFAgAAAA==.',
Ay='Ayhanui:BAAALgAECgEJAgAAAA==.',
Az='Azaléa:BAAALgADCgcJBwAAAA==.Azrathalos:BAABLgAECn8bAAQTAAcJmg7HQgAsAQATAAYJOQ3HQgAsAQAEAAUJEAWADwGXAAAUAAEJkwO2UQAkAAAAAA==.Azémstraza:BAAALgAECgYJDAAAAA==.',
Ba='Bained:BAAALgADCgcJBwAAAA==.Baldric:BAABLgAECn8nAAIOAAgJ8BZZLwD0AQAOAAgJ8BZZLwD0AQAAAA==.Balinor:BAABLgAECn8dAAITAAcJLQ5eOgBUAQATAAcJLQ5eOgBUAQABLgAECgkJMQADAJ4dAA==.Bank:BAAALgADCgcJBwAAAA==.',
Be='Bearett:BAABLgAECn88AAIVAAkJRiPmAQAlAwAVAAkJRiPmAQAlAwAAAA==.Beefcakezear:BAAALgADCgQJBAAAAA==.Belyfrost:BAABLgAFFH8FAAIGAAMJHAKCjgCiAAAGAAMJHAKCjgCiAAAAAA==.Belylight:BAAALgAECgkJEAABLgAFFAIJAgAWAAAAAA==.Belymoon:BAAALgAFFAIJAgAAAA==.Beriotyr:BAAALgADCgQJAwAAAA==.Bernd:BAABLgAECn8nAAIVAAkJ6QsFIwAkAQAVAAkJ6QsFIwAkAQAAAA==.Beörn:BAABLgAECn8wAAIXAAgJsCRgBgBKAwAXAAgJsCRgBgBKAwAAAA==.',
Bi='Bigsniffy:BAAALgADCgQJBAAAAA==.',
Bl='Blackbeard:BAAALgAECgEJAQABLgAECgkJMQADAJ4dAA==.Blackgrinn:BAABLgAECn8jAAMCAAgJJw9JJQCYAQACAAgJJw9JJQCYAQAYAAcJRwaiRAD0AAAAAA==.Blackkgrin:BAAALgADCgQJBwAAAA==.Blasphemous:BAABLgAECn8dAAISAAcJgBRMgwBUAQASAAcJgBRMgwBUAQAAAA==.Blasé:BAABLgAECn8yAAQPAAgJESDcHwBfAgAPAAgJESDcHwBfAgAZAAEJAACjXABZAAAaAAEJghKWNQBAAAABLgAFFAMJBAAWAAAAAA==.Blazéoné:BAAALgAECgUJBgAAAA==.Blessin:BAAALgAECgcJCgAAAA==.',
Bo='Bobo:BAAALgAECgUJEQAAAA==.Bobrossx:BAACLgAFFH8FAAMbAAIJ7xKHHQCgAAAbAAIJ7xKHHQCgAAAOAAIJNQhxgQCAAAAuAAQKfywABBsACAmZIZcNANgCABsACAkUHpcNANgCAAgABwnXHXMbAL0BAA4AAgl9HnLWAIkAAAAA.Bobsmonk:BAAALgADCgEJAQAAAA==.Bomi:BAAALgADCgQJBAAAAA==.Boostéd:BAABLgAECn8XAAISAAcJdR3VSAAZAgASAAcJdR3VSAAZAgAAAA==.Boostëd:BAAALgAECgYJBwABLgAECgcJFwASAHUdAA==.Bowyoncè:BAAALgAECggJCgABLgAECggJJwAJAH4RAA==.',
Br='Brakevilt:BAAALgAECgcJBwAAAA==.Brattyone:BAAALgADCgcJBwAAAA==.Breadcrums:BAAALgADCgMJAwAAAA==.Brewagool:BAAALgAECgMJAwAAAA==.Bruche:BAABLgAECn8uAAISAAkJLh8mHQCQAgASAAkJLh8mHQCQAgAAAA==.Brujaah:BAAALgAECgYJBgABLgAECgkJOgAWAAAAAQ==.Brynhilldr:BAAALgAECgEJAQAAAA==.Brynthadia:BAAALgAECgYJCAAAAA==.Brzrker:BAAALgADCgYJDAAAAA==.',
Bu='Bubagumps:BAAALgAECgEJAQAAAA==.',
Bw='Bwca:BAACLgAFFH8HAAIOAAMJ9A68XADXAAAOAAMJ9A68XADXAAAuAAQKfxQAAg4ABQkjHLxbAIUBAA4ABQkjHLxbAIUBAAEuAAUUAwkMAAUAFQYA.',
Ca='Caine:BAABLgAECn8xAAIDAAkJnh3HCgA4AgADAAkJnh3HCgA4AgAAAA==.Cakébob:BAAALgADCgQJBQAAAA==.Calmdown:BAAALgADCgYJBwAAAA==.Carraa:BAAALgADCgYJCgABLgAECggJJwAFAP4MAA==.Casey:BAABLgAECn8iAAIEAAYJnAaP4gDOAAAEAAYJnAaP4gDOAAAAAA==.Castyblasty:BAAALgAECgEJAQAAAA==.Cataaria:BAABLgAECn8nAAIFAAgJ/gx0TwBlAQAFAAgJ/gx0TwBlAQAAAA==.',
Ce='Cellina:BAABLgAECn8kAAMcAAgJoxEIJgB4AQAcAAgJoxEIJgB4AQABAAYJGQa5UAC4AAAAAA==.Cerathal:BAAALgADCgIJAgAAAA==.Ceriumz:BAAALgAECgYJCwABLgAFFAMJBgADACYVAA==.',
Cf='Cfourtylock:BAABLgAECn8oAAQPAAkJfBfZTQCsAQAPAAgJrRXZTQCsAQAaAAYJcRUlEQAbAQAZAAEJ7wVOeQAqAAAAAA==.',
Ch='Chaniqua:BAAALgADCgQJBQAAAA==.Chiman:BAABLgAECn8UAAMdAAYJbBF2RgA4AQAdAAYJbBF2RgA4AQAcAAUJZguYUgCyAAAAAA==.Chronophage:BAAALgAECgUJBQAAAA==.Chûd:BAEALgAECgUJBQAAAA==.',
Ci='Ciders:BAAALgAECgEJAQABLgAECgcJIAAIAGsWAA==.',
Cl='Clasastrasza:BAAALgAECgUJCgABLgAFFAQJDwAXAMsaAA==.Classá:BAACLgAFFH8PAAMXAAQJyxriHwBLAQAXAAQJyxriHwBLAQAeAAMJzhVdLADAAAAuAAQKf0UABB4ACQmLIngHANQCAB4ACAmuJHgHANQCABcABwmhIMlGAIcBABUAAQmYF5JhAD4AAAAA.Clawz:BAABLgAFFH8FAAIHAAIJsBa5EQCQAAAHAAIJsBa5EQCQAAABLgAFFAMJCQAEAD0eAA==.',
Co='Codedd:BAACLgAFFH8GAAIXAAIJYwaVWABkAAAXAAIJYwaVWABkAAAuAAQKfxkAAhcABwl5EAZNAFABABcABwl5EAZNAFABAAAA.Commit:BAAALgAECggJDgAAAA==.Comradeprime:BAAALgAECgUJDQAAAA==.Corlys:BAABLgAECn8sAAMEAAkJDCKGFQC4AgAEAAkJ/yCGFQC4AgAUAAYJgB1QEQCjAQABLgAECgkJJwAGAC0TAA==.Covi:BAAALgADCgkJDAAAAA==.',
Cr='Crismonguard:BAAALgAECgcJBwAAAA==.Crispìn:BAAALgAECgYJEAAAAA==.Crossbones:BAAALgAECgQJCQAAAA==.Crue:BAABLgAECn8dAAIXAAgJBgz+TABRAQAXAAgJBgz+TABRAQAAAA==.',
Cu='Curthar:BAACLgAFFH8JAAIEAAMJPR6gVwDsAAAEAAMJPR6gVwDsAAAuAAQKfyAAAxQACQkUJcwAAFYDABQACQkUJcwAAFYDAAQABgmgHiJ2AHcBAAAA.',
Cy='Cyguy:BAAALgAECgEJAQAAAA==.Cyndee:BAABLgAECn8/AAIfAAkJmxf/EgBUAgAfAAkJmxf/EgBUAgAAAA==.Cynnafrost:BAAALgAECgMJBAAAAA==.Cytenk:BAAALgADCgYJBgAAAA==.',
Da='Dadda:BAABLgAECn89AAIbAAkJKSA/AgDNAgAbAAkJKSA/AgDNAgAAAA==.Dallas:BAAALgADCgcJBwAAAA==.Damascus:BAAALgAECgYJCwABLgAECggJJwAOAPAWAA==.Dankmonk:BAABLgAECn8uAAIBAAgJUhbDGgDHAQABAAgJUhbDGgDHAQAAAA==.Darcnis:BAAALgADCgkJGwAAAA==.Darielea:BAAALgADCgIJAgAAAA==.Darkfury:BAABLgAECn84AAIMAAkJiAnFYgBWAQAMAAkJiAnFYgBWAQAAAA==.Darklasminth:BAAALgAFFAIJAgAAAA==.Darkschi:BAAALgAECgQJCAAAAA==.Darthwang:BAABLgAECn8fAAIPAAYJ6BjsWgC3AQAPAAYJ6BjsWgC3AQAAAA==.Darthwing:BAAALgAECgMJAwABLgAECgYJHwAPAOgYAA==.Dartos:BAACLgAFFH8HAAISAAIJbiOCnADNAAASAAIJbiOCnADNAAAuAAQKf0kAAhIACQkoJeEEAFIDABIACQkoJeEEAFIDAAAA.',
De='Deadlysmash:BAAALgADCgMJAwAAAA==.Deathratio:BAAALgADCgcJBwAAAA==.Deathsbff:BAAALgADCgEJAQABLgAFFAcJGAAGAO0WAA==.Deathsend:BAAALgAECggJCAAAAA==.Debluddk:BAABLgAECn8tAAIgAAkJIyHDAwD6AgAgAAkJIyHDAwD6AgAAAA==.Deep:BAAALgAECgMJAwABLgAECgkJJQAdALMgAA==.Deepfister:BAABLgAECn8lAAIdAAkJsyDSBwASAwAdAAkJsyDSBwASAwAAAA==.Deeplydivine:BAAALgAECgIJAgABLgAECgkJJQAdALMgAA==.Demone:BAAALgADCgMJAwAAAA==.',
Di='Dic:BAAALgAECgcJCgAAAA==.Diluvium:BAABLgAECn8oAAIEAAkJNRKKUADMAQAEAAkJNRKKUADMAQAAAA==.Discodank:BAAALgAECgMJBAAAAA==.',
Dj='Djpleasant:BAACLgAFFH8SAAIGAAUJIxI4WAAuAQAGAAUJIxI4WAAuAQAuAAQKfzUAAgYACQnCHWwdAKUCAAYACQnCHWwdAKUCAAAA.',
Dk='Dktelmtwo:BAAALgAECggJEQAAAA==.',
Do='Doneisha:BAAALgAECgQJCQAAAA==.Dontcare:BAABLgAFFH8MAAMIAAUJWBOeEgAoAQAIAAQJdQ+eEgAoAQAOAAQJ5BOJXADXAAAAAA==.Downhammer:BAAALgAECgkJBQAAAA==.',
Dr='Drakamar:BAABLgAECn86AAQKAAkJFQOCFAC7AAAJAAkJZwLWWQDAAAAKAAgJ8gKCFAC7AAALAAYJMAIWLAB8AAAAAA==.Dranith:BAAALgAECgQJBAAAAA==.Dronos:BAACLgAFFH8IAAIeAAMJwhXuKgDJAAAeAAMJwhXuKgDJAAAuAAQKfzIAAh4ACQmBI70CAD8DAB4ACQmBI70CAD8DAAAA.',
Du='Dunzledorf:BAAALgAECgcJBwAAAA==.',
Dy='Dynammes:BAABLgAECn8jAAIGAAgJxhgbRwAAAgAGAAgJxhgbRwAAAgABLgAFFAIJBQAKANoHAA==.',
Ea='Eaglej:BAAALgAECgkJCAAAAA==.Eatmorpizza:BAAALgAECgQJDAAAAA==.',
Eb='Ebore:BAAALgADCggJDQAAAA==.',
Ee='Eegorn:BAAALgAECgYJCgAAAA==.Eegroll:BAACLgAFFH8TAAIBAAQJcBrbHQAtAQABAAQJcBrbHQAtAQAuAAQKfxgAAwEACAmlHC4dALMBABwABwkpF+kjALcBAAEABQm9Hy4dALMBAAAA.',
Eg='Egraw:BAAALgAECgQJBAAAAA==.',
El='Elementals:BAAALgAECgkJEwAAAA==.Elixera:BAAALgAECgEJAQAAAA==.Elsä:BAAALgAECgUJAQAAAA==.Elémental:BAAALgAECggJCAAAAA==.',
Em='Emilwhaury:BAAALgAECgQJBAAAAA==.',
Ep='Epia:BAABLgAECn8jAAMcAAgJyw+PLgBDAQAcAAgJwQ2PLgBDAQABAAMJUBPMUgCxAAAAAA==.',
Er='Eriena:BAAALgAECgYJEQAAAA==.',
Es='Esbjorn:BAAALgAECgEJAgAAAA==.Essaila:BAABLgAECn88AAIHAAkJXxBODwCvAQAHAAkJXxBODwCvAQAAAA==.',
Et='Etheo:BAAALgAECgEJAQAAAA==.Etherwalker:BAABLgAECn8mAAMfAAkJPyQ8CwCrAgAfAAgJTyQ8CwCrAgAhAAQJix/dJgAqAQAAAA==.',
Ev='Evocati:BAACLgAFFH8FAAISAAMJiRTTiQDjAAASAAMJiRTTiQDjAAAuAAQKfxgAAyIABgnbFxcSAEQBACIABgneFRcSAEQBABIABgkZF1+iAB8BAAEuAAUUBgkOAAQAexYA.Evoka:BAABLgAECn8lAAMKAAgJjR7yDAAMAgAKAAcJVx/yDAAMAgAJAAYJWRtAMABsAQABLgAECgkJLQAgACMhAA==.',
Ex='Excision:BAABLgAECn8pAAMJAAgJyA51QgAUAQAKAAcJcw2yHgA5AQAJAAcJIQ11QgAUAQAAAA==.Exmachina:BAAALgADCgYJBgAAAA==.',
Fa='Fahbio:BAABLgAECn8hAAIUAAcJ2AE4NQB/AAAUAAcJ2AE4NQB/AAAAAA==.Fataliny:BAAALgADCgUJCAAAAA==.Fatallock:BAABLgAECn82AAMPAAgJaRJ4UQCiAQAPAAgJaRJ4UQCiAQAaAAEJaQipOgAzAAAAAA==.Fatlife:BAAALgAECgMJAwAAAA==.',
Fi='Fishdish:BAAALgAECgIJAgAAAA==.Fistsmither:BAAALgAECgYJCAABLgAECgkJJAAjAPwTAA==.Fivevolts:BAABLgAECn8pAAIkAAkJDCTLAAAuAwAkAAkJDCTLAAAuAwAAAA==.',
Fl='Fladon:BAAALgADCgEJAQAAAA==.Flailuid:BAAALgAECgQJDQAAAA==.Flimfam:BAAALgAECgEJAQAAAA==.',
Fo='Forkin:BAAALgADCgIJAgAAAA==.Forthstryke:BAAALgAECgIJBwAAAA==.Four:BAAALgADCgUJBQAAAA==.Fozzi:BAAALgAECgYJCwAAAA==.',
Fr='Freddyg:BAAALgADCgMJBAAAAA==.Fridaychill:BAACLgAFFH8NAAIcAAQJohsSDgBDAQAcAAQJohsSDgBDAQAuAAQKfzQAAhwACAm5Io4KAJACABwACAm5Io4KAJACAAAA.Fries:BAEALgAECgEJAQABLgAFFAQJBwAPAKYPAA==.Frostdeeps:BAAALgAECgcJEwAAAA==.Frozarke:BAABLgAECn8tAAIJAAgJng+WMwBaAQAJAAgJng+WMwBaAQAAAA==.',
Fu='Fudd:BAABLgAECn8nAAIOAAgJoBu/KAAxAgAOAAgJoBu/KAAxAgAAAA==.Funk:BAAALgAECgEJAQABLgAECgQJBQAWAAAAAA==.Fupa:BAABLgAECn8pAAIOAAgJ+AyPXgB+AQAOAAgJ+AyPXgB+AQAAAA==.',
Ga='Gaiaslieg:BAAALgAECgEJAQAAAA==.Galand:BAAALgAECgYJBgAAAA==.Galathynius:BAAALgADCgUJBQAAAA==.Galeine:BAAALgADCgMJAwAAAA==.Gangplank:BAAALgADCgMJAwAAAA==.Garres:BAABLgAECn8cAAIHAAcJuh+rCwDtAQAHAAcJuh+rCwDtAQAAAA==.',
Ge='Genius:BAABLgAECn8bAAIhAAcJUBveFgCaAQAhAAcJUBveFgCaAQAAAA==.Gennosuke:BAAALgADCgcJBQAAAA==.',
Gh='Ghostkillaz:BAAALgADCgkJFwAAAA==.Ghostxkillaz:BAAALgADCgMJAwAAAA==.',
Gi='Gibley:BAABLgAECn8VAAIEAAgJ0BjlfgB8AQAEAAgJ0BjlfgB8AQAAAA==.',
Gl='Gladorf:BAAALgADCgYJBgAAAA==.',
Gn='Gnazgul:BAAALgAECggJDgAAAA==.Gnomad:BAABLgAECn8lAAIGAAcJwwNj2ADgAAAGAAcJwwNj2ADgAAAAAA==.Gnomie:BAAALgAECgMJBAAAAA==.',
Go='Goat:BAAALgAECgYJDwAAAA==.Gouge:BAAALgAECgkJOgAAAQ==.',
Gr='Gravess:BAAALgAFFAIJAgAAAA==.Griffynshu:BAABLgAECn8nAAIXAAkJlBvkEgCsAgAXAAkJlBvkEgCsAgAAAA==.Griz:BAAALgAECgYJCwAAAA==.Grizzlyburr:BAABLgAECn8UAAIVAAcJjxKYIQAuAQAVAAcJjxKYIQAuAQABLgAFFAQJCAABANEOAA==.Grunewald:BAABLgAECn9eAAIOAAgJoxCRUACkAQAOAAgJoxCRUACkAQAAAA==.',
Gu='Guinn:BAAALgADCgIJAgABLgAECggJLQAJAJ4PAA==.Gula:BAABLgAECn8hAAMaAAkJPxU/CQCxAQAaAAYJHRc/CQCxAQAPAAkJKBRhTQCuAQAAAA==.Guldanshower:BAAALgADCgUJBQAAAA==.Gunhild:BAAALgAECgIJAgAAAA==.Gutdiver:BAAALgADCgUJBQAAAA==.',
Ha='Handiboyswag:BAACLgAFFH8aAAICAAUJhiG+EQDdAQACAAUJhiG+EQDdAQAuAAQKfxkAAxgABwm4E5QgANQBABgABwm4E5QgANQBAAIABAnJIhYwAB8BAAAA.Hando:BAAALgAECgYJCAAAAA==.Hattock:BAAALgADCgcJFQAAAA==.Hayate:BAAALgAECgUJBQAAAA==.',
He='Heavyshlump:BAACLgAFFH8IAAIBAAQJ0Q4YJwADAQABAAQJ0Q4YJwADAQAuAAQKfyAAAgEACQlbFUwRACUCAAEACQlbFUwRACUCAAAA.Hehateme:BAAALgAECgIJAgAAAA==.Hehexd:BAABLgAECn8pAAIjAAgJARvUEwB3AgAjAAgJARvUEwB3AgAAAA==.Heimdall:BAACLgAFFH8GAAITAAMJZgh3MQChAAATAAMJZgh3MQChAAAuAAQKfyAAAhMACAmOH8oLAMYCABMACAmOH8oLAMYCAAAA.Hellavva:BAAALgAECgMJAwAAAA==.Hellzwar:BAAALgADCgUJBgAAAA==.Hench:BAAALgAECgYJBgAAAA==.Henchling:BAABLgAECn86AAMFAAkJGyApCQDkAgAFAAkJGyApCQDkAgAQAAkJaRIXIwC/AQAAAA==.Henchragon:BAAALgADCgUJBQAAAA==.',
Hi='Hissteria:BAAALgAECgIJAwAAAA==.',
Hn='Hngyhngyloko:BAABLgAECn8ZAAIGAAcJzxt5bQD6AQAGAAcJzxt5bQD6AQABLgAFFAMJCAAJAOYUAA==.',
Ho='Hoerified:BAAALgADCgEJAQABLgAECggJKQAjAAEbAA==.Holexios:BAAALgAECgQJCQABLgAECgYJFAAdAGwRAA==.Holybonks:BAAALgADCgcJBwAAAA==.Holycanoli:BAAALgAECgEJAgAAAA==.Holycrusade:BAAALgAECgUJCgAAAA==.Horine:BAABLgAECn8pAAIOAAgJEw+5VwCQAQAOAAgJEw+5VwCQAQAAAA==.Hotsteve:BAAALgAECgQJBwAAAA==.',
Hu='Huntër:BAAALgAECgQJBQAAAA==.Huruk:BAAALgAECgIJAgAAAA==.',
Hy='Hydranis:BAAALgADCgUJBQAAAA==.',
Ic='Icieblade:BAAALgAECgkJEQAAAA==.Icyscorcher:BAABLgAECn8kAAMGAAgJihR0WQDLAQAGAAgJihR0WQDLAQAlAAMJpwOyCwB3AAABLgAFFAMJBgADACYVAA==.',
Id='Idroptotems:BAAALgADCgMJAwABLgAECgcJJAAEABcbAA==.',
Ik='Ikairi:BAAALgAECgEJAQAAAA==.',
Il='Illidankness:BAAALgAECgQJBAAAAA==.Illidoran:BAAALgAECgUJCAABLgAFFAMJCAAYACsKAA==.',
Im='Immeira:BAABLgAECn8XAAIFAAYJIwrzcQD2AAAFAAYJIwrzcQD2AAAAAA==.Immkicky:BAAALgADCgEJAQAAAA==.',
In='Intense:BAAALgAECgcJAwAAAA==.',
Ja='Jackheals:BAACLgAFFH8QAAIXAAMJgB5vKQANAQAXAAMJgB5vKQANAQAuAAQKfzMAAxcACAnkIcoKAAcDABcACAnkIcoKAAcDAB4AAQnZAdqPABsAAAAA.Jacktides:BAAALgADCgIJAgABLgAFFAMJEAAXAIAeAA==.Jaehaerys:BAAALgAECgQJCAABLgAECgkJJwAGAC0TAA==.Jagseer:BAAALgAECgQJBAABLgAECgkJKgACANAcAA==.',
Jb='Jblackly:BAAALgAECgYJCQAAAA==.',
Jf='Jfreeman:BAAALgADCgYJBwAAAA==.',
Ji='Jimzdrood:BAAALgAECgEJAQAAAA==.Jinbeyblade:BAAALgAECgMJAwABLgAFFAMJCwAOAG0iAA==.Jinphoenix:BAACLgAFFH8LAAIOAAMJbSJEOgAuAQAOAAMJbSJEOgAuAQAuAAQKfycAAw4ACQlrIWALAO8CAA4ACQlrIWALAO8CABsABAmQB4xfAMMAAAAA.Jitb:BAAALgADCgYJBwABLgAFFAYJDwAdAO4NAA==.',
Jo='Jobin:BAACLgAFFH8PAAMSAAMJ4BKzlgDUAAASAAMJ4BKzlgDUAAAiAAEJSAFBJwAwAAAuAAQKfxkAAhIACAn5G0twAKgBABIACAn5G0twAKgBAAAA.Joldada:BAAALgAECgkJCAAAAA==.Journei:BAABLgAECn8kAAIFAAgJUhLdMwDVAQAFAAgJUhLdMwDVAQAAAA==.',
Ju='Judging:BAABLgAECn8tAAMTAAkJDRfbFgBIAgATAAkJDRfbFgBIAgAEAAIJHSVu5wDHAAAAAA==.Junkhead:BAAALgAECgIJAwAAAA==.',
Ka='Kaethe:BAAALgAECgYJBgAAAA==.Kaiduo:BAAALgADCgEJAQAAAA==.Kaitos:BAAALgAFFAIJBAABLgAFFAMJCQAEAD0eAA==.Kalmas:BAABLgAFFH8MAAIeAAMJHAgKMgCiAAAeAAMJHAgKMgCiAAAAAA==.Kateana:BAAALgAECgYJBgAAAA==.',
Ke='Kegz:BAAALgADCggJCAABLgAECgkJKgACANAcAA==.Kelendrian:BAAALgAECgUJBQAAAA==.Kellayna:BAABLgAECn8oAAIEAAkJKwdSjQBLAQAEAAkJKwdSjQBLAQAAAA==.Kennyx:BAAALgAECgMJAwAAAA==.Kerine:BAAALgAECgMJBAAAAA==.Keylö:BAAALgAECgYJCAAAAA==.Kezix:BAABLgAECn8eAAIPAAkJlA72TACvAQAPAAkJlA72TACvAQAAAA==.',
Kh='Kharigosa:BAAALgAECgEJAQABLgAECggJFgATAH8ZAA==.',
Ki='Kigerstorm:BAAALgADCgEJAQAAAA==.Kimeltoe:BAAALgADCgIJAgAAAA==.Kimigosa:BAABLgAECn8nAAQJAAgJfhGoIwChAQAJAAgJvA+oIwChAQAKAAIJ7gsfJQAyAAALAAEJwQF4TgAiAAAAAA==.Kimpachi:BAAALgAECgcJCAABLgAECggJJwAJAH4RAA==.',
Kl='Klerik:BAACLgAFFH8VAAIPAAUJqBW7SgAkAQAPAAUJqBW7SgAkAQAuAAQKfykABA8ACQkaHxAdAHACAA8ACQmyHRAdAHACABkAAgkpEmxMAIgAABoAAQlxJP4wAE4AAAAA.',
Kn='Kníghtmare:BAAALgAECgYJDwAAAA==.',
Ko='Kolesnikov:BAAALgAECgUJCAAAAA==.Koragg:BAACLgAFFH8mAAIgAAYJ8yAnCQDPAQAgAAYJ8yAnCQDPAQAuAAQKfz4AAiAACQnwJWQCACUDACAACQnwJWQCACUDAAAA.Kore:BAABLgAECn8jAAIXAAYJZBZfRgBsAQAXAAYJZBZfRgBsAQAAAA==.Korrag:BAAALgAECgUJCgAAAA==.Kozarke:BAABLgAECn8tAAIKAAkJxBbPBAAUAgAKAAkJxBbPBAAUAgAAAA==.',
Kp='Kpop:BAABLgAECn8bAAINAAkJfxktBwAWAgANAAkJfxktBwAWAgABLgAFFAQJCAABANEOAA==.',
Kr='Krissia:BAABLgAECn8iAAISAAkJhhi1TQDSAQASAAkJhhi1TQDSAQAAAA==.',
Ku='Kumadbear:BAAALgADCgEJAQAAAA==.',
Ky='Kyntaliia:BAAALgAECgQJBAAAAA==.',
['Kí']='Kítsuñe:BAAALgAECgMJAwAAAA==.',
['Kî']='Kîn:BAABLgAECn8mAAIMAAgJrhQIRACvAQAMAAgJrhQIRACvAQAAAA==.',
La='Ladriana:BAAALgADCgEJAgAAAA==.Laisera:BAABLgAECn8zAAMmAAkJmRD8JACOAQAmAAkJmRD8JACOAQAYAAEJdQYriQApAAAAAA==.Lalipop:BAABLgAECn85AAImAAkJ2RfgDwBdAgAmAAkJ2RfgDwBdAgAAAA==.Landroval:BAABLgAECn8oAAIJAAkJKRntEABXAgAJAAkJKRntEABXAgAAAA==.Lauma:BAACLgAFFH8MAAIFAAMJFQakVgCOAAAFAAMJFQakVgCOAAAuAAQKfxUAAgUABwmwEvZHAIEBAAUABwmwEvZHAIEBAAAA.Lawson:BAABLgAECn85AAISAAkJYxyHHQCOAgASAAkJYxyHHQCOAgAAAA==.',
Le='Lelora:BAAALgAECgUJCQAAAA==.Lenthaden:BAABLgAECn86AAMPAAkJOBhqLQAdAgAPAAkJDBZqLQAdAgAZAAYJqxNeJQAyAQAAAA==.Lexusis:BAAALgADCgIJAgAAAA==.',
Li='Lightsmasher:BAAALgAECgEJAQAAAA==.Lihaeh:BAAALgADCgEJAQAAAA==.Lildipper:BAAALgAECgcJDAABLgAFFAQJCAABANEOAA==.Lio:BAAALgAECgYJDgAAAA==.Lissetteliz:BAAALgAECgQJBQAAAA==.Livdangerous:BAAALgADCgUJBQAAAA==.',
Lo='Lomax:BAAALgAECgEJAQAAAA==.Longlegs:BAAALgADCgYJBgAAAA==.',
Lu='Lumawig:BAAALgAECgUJDQAAAA==.Lumillras:BAAALgADCgYJCgAAAA==.Lunchdk:BAACLgAFFH8NAAMgAAMJOhebDgCAAAASAAIJJR5ztwCcAAAgAAIJBwybDgCAAAAuAAQKfysAAxIACQmOH2AUAMUCABIACAl2I2AUAMUCACAACAlzF2gVALwBAAAA.',
Ly='Lyreth:BAABLgAECn8pAAIeAAkJJRAhIwCiAQAeAAkJJRAhIwCiAQAAAA==.',
Ma='Madax:BAABLgAECn9CAAMDAAkJ4iJeAwD5AgADAAkJQSFeAwD5AgAfAAkJGCHACwClAgABLgAFFAIJBQAKANoHAA==.Mageymutt:BAACLgAFFH8YAAIGAAcJ7RZbDAC7AQAGAAcJ7RZbDAC7AQAuAAQKfyUAAwYACAmNIKElANwCAAYACAmNIKElANwCACcAAwkmCx8UAIQAAAAA.Maggidabeast:BAABLgAECn8vAAIGAAgJKQhLlABKAQAGAAgJKQhLlABKAQAAAA==.Magnion:BAAALgAECgEJAQAAAA==.Maison:BAAALgAECgQJCQAAAA==.Malase:BAAALgADCgUJAwAAAA==.Maloch:BAAALgADCgUJBQAAAA==.',
Me='Meaculpa:BAAALgADCgUJCgAAAA==.Megamilk:BAACLgAFFH8PAAIiAAQJNg/PDAAbAQAiAAQJNg/PDAAbAQAuAAQKfzoAAiIACQkTG8AFAEUCACIACQkTG8AFAEUCAAAA.Mekri:BAAALgADCgYJBwABLgAECgcJJAAEABcbAA==.Melledreaux:BAAALgADCgMJAwAAAA==.Metrolinea:BAACLgAFFH8SAAIGAAUJVRhjSQBHAQAGAAUJVRhjSQBHAQAuAAQKfzkAAgYACQkqHwETAOICAAYACQkqHwETAOICAAAA.',
Mi='Micalknight:BAAALgAECgIJAQAAAA==.Milliy:BAAALgAECgQJBwAAAA==.Minervá:BAAALgADCgMJAwABLgAFFAQJDwAXAMsaAA==.Missbehaving:BAABLgAECn8hAAMmAAcJjRRbLgBLAQAmAAcJjRRbLgBLAQAYAAEJQQfCiAApAAAAAA==.',
Mo='Monkdluffy:BAAALgADCgEJAQAAAA==.Morefire:BAAALgAECgQJCgABLgAECgkJEwAWAAAAAA==.Mosmos:BAAALgADCgkJFQAAAA==.',
Mu='Muddslinger:BAABLgAECn8ZAAIfAAgJJAtAPABMAQAfAAgJJAtAPABMAQAAAA==.Mumra:BAABLgAECn84AAQmAAgJkwn7MQA0AQAmAAgJkwn7MQA0AQACAAYJdgFaPwC0AAAYAAEJAAAmlgAAAAAAAA==.',
My='Mystblade:BAAALgAECgQJBAAAAA==.Mystlord:BAAALgAECgQJBAAAAA==.',
Na='Nadatank:BAAALgADCgQJBAAAAA==.Nalesean:BAAALgAECgYJDwAAAA==.Nanaki:BAABLgAECn8iAAILAAkJKyDzBgDQAgALAAkJKyDzBgDQAgAAAA==.Nannette:BAABLgAECn8UAAIEAAcJKQMy+gCwAAAEAAcJKQMy+gCwAAAAAA==.Nappe:BAAALgAECgEJAQABLgAECgkJHwAEAIElAA==.Narag:BAABLgAECn85AAIOAAkJuBpsGwB1AgAOAAkJuBpsGwB1AgAAAA==.Nazfu:BAAALgAECgEJAgAAAA==.Nazg:BAAALgADCgQJAgAAAA==.',
Ne='Needle:BAAALgADCgEJAQAAAA==.Nerfertari:BAAALgAECgEJBQAAAA==.Netanyahoo:BAAALgAFFAIJAgAAAA==.Neva:BAAALgAECgIJAgAAAA==.Newport:BAABLgAECn8yAAMFAAgJzR/WDwDHAgAFAAgJzR/WDwDHAgAQAAIJmAhkigBNAAAAAA==.',
Ni='Ninex:BAABLgAECn8cAAITAAgJTR/RGABMAgATAAgJTR/RGABMAgAAAA==.Ninisina:BAABLgAECn89AAMFAAgJnB8xEQC6AgAFAAgJnB8xEQC6AgARAAEJ7wOHLgAsAAAAAA==.Nithén:BAAALgADCgYJDQAAAA==.',
No='Noghalote:BAAALgADCgQJBAAAAA==.Nonaleeta:BAAALgAECgQJCAAAAA==.Notafurry:BAAALgADCgcJCQAAAA==.Novaa:BAAALgAECgcJBgAAAA==.Nowhere:BAAALgAECgUJBQABLgAECgkJJAAjAPwTAA==.Nowon:BAABLgAECn8gAAMoAAcJOBYzHQCBAQAoAAcJOBYzHQCBAQANAAEJpwh8OAAcAAABLgAECgkJAQAWAAAAAA==.',
Nu='Nudream:BAABLgAECn8eAAITAAkJyQPvPgA9AQATAAkJyQPvPgA9AQAAAA==.',
Ny='Nybors:BAAALgADCgcJCwAAAA==.',
['Nö']='Nörse:BAABLgAECn8aAAMeAAYJDhDqSADZAAAeAAYJCA/qSADZAAAHAAEJpBc3QwBFAAAAAA==.',
Ol='Olakua:BAAALgAECgMJAwAAAA==.Oldjerry:BAABLgAECn8kAAIjAAkJ/BPZEAAYAgAjAAkJ/BPZEAAYAgAAAA==.Oliaa:BAAALgADCgYJCAAAAA==.',
Oo='Oomdeath:BAAALgAECgYJBgAAAA==.',
Op='Opalyte:BAABLgAECn8mAAImAAgJCg17MQA3AQAmAAgJCg17MQA3AQAAAA==.',
Or='Orichalcum:BAABLgAECn8oAAIdAAgJth5WDQC2AgAdAAgJth5WDQC2AgAAAA==.Orphiee:BAABLgAECn8dAAIOAAYJfQF96ABpAAAOAAYJfQF96ABpAAAAAA==.',
Os='Oslagsi:BAAALgADCgcJDgAAAA==.Osyriss:BAAALgADCgUJBgAAAA==.',
Ot='Othril:BAAALgAECgEJAQAAAA==.',
Ou='Outis:BAAALgAFFAMJBgAAAQ==.',
Pa='Pacts:BAAALgADCgYJBgAAAA==.Pakoros:BAABLgAECn8/AAMFAAkJch2MDADqAgAFAAkJch2MDADqAgAQAAQJBwp7agCZAAAAAA==.Palibuddy:BAAALgAECgMJAwAAAA==.Pallyfreak:BAAALgAECgYJCwAAAA==.',
Pe='Peachy:BAAALgAECgQJBAABLgAECgkJLQAFADQXAA==.Penderin:BAAALgAECgkJEgABLgAECgkJPAAHAD4aAA==.Penilock:BAAALgADCgIJAgAAAA==.Pensham:BAAALgAECgEJAwABLgAECgkJPAAHAD4aAA==.Perlindree:BAABLgAECn86AAIOAAgJSQgIawBfAQAOAAgJSQgIawBfAQAAAA==.',
Pg='Pgorlelgy:BAABLgAECn8sAAIOAAkJ/hYBLgAZAgAOAAkJ/hYBLgAZAgAAAA==.',
Ph='Phira:BAAALgADCgEJAQAAAA==.Phoenix:BAAALgADCgIJAgAAAA==.Physgun:BAAALgADCgYJDgAAAA==.',
Pi='Pillows:BAAALgADCgYJBgAAAA==.',
Pl='Platious:BAABLgAECn8qAAIEAAcJ/BSceABxAQAEAAcJ/BSceABxAQAAAA==.',
Po='Pony:BAAALgADCgUJBQABLgADCgUJCgAWAAAAAA==.Poodin:BAAALgADCgIJAgAAAA==.Pookaboo:BAABLgAECn8WAAIPAAgJNwJczgCuAAAPAAgJNwJczgCuAAAAAA==.Poppers:BAAALgADCggJDQAAAA==.',
Pr='Preacharond:BAACLgAFFH8TAAIYAAUJSxWYFQAmAQAYAAUJSxWYFQAmAQAuAAQKf1EAAhgACQnmIOcEAAQDABgACQnmIOcEAAQDAAAA.Promir:BAAALgAECgcJDgAAAA==.',
Pu='Purdie:BAAALgAECgcJDQABLgAECggJJwAFAP4MAA==.',
Qe='Qeesa:BAAALgAECgIJAwAAAA==.',
Qi='Qiryana:BAAALgADCgIJAgAAAA==.',
Ra='Raeliene:BAACLgAFFH8GAAIEAAMJ/h4FSAAPAQAEAAMJ/h4FSAAPAQAuAAQKfyQAAgQACQkoHW4gAHwCAAQACQkoHW4gAHwCAAAA.Rafikie:BAAALgAECgIJAwAAAA==.Ratchet:BAAALgADCgMJAwAAAA==.Rawmeat:BAABLgAECn8+AAICAAkJ0h0oCQDWAgACAAkJ0h0oCQDWAgAAAA==.Razillar:BAAALgAECgEJAQAAAA==.',
Re='Rebelpatriot:BAAALgADCgYJCQAAAA==.Redbearrd:BAAALgADCgkJCQABLgAECgkJJwAGAC0TAA==.Relaxnerdlol:BAAALgAECgEJBAAAAA==.Reldwick:BAAALgADCgYJBwAAAA==.Renew:BAABLgAECn8qAAMmAAkJHB53CQDEAgAmAAkJHB53CQDEAgAYAAkJTxZeFAAkAgAAAA==.Renix:BAACLgAFFH8SAAIQAAQJCRnOHQAdAQAQAAQJCRnOHQAdAQAuAAQKfzIAAxAACQlmH9IMAI4CABAACQlmH9IMAI4CABEAAQl1CxYtADIAAAAA.Reno:BAAALgAECgMJAwAAAA==.Revery:BAAALgADCgIJAgAAAA==.',
Rh='Rhadgar:BAAALgADCgcJCQAAAA==.',
Ri='Ripmyname:BAAALgAECgYJBgAAAA==.Riverah:BAAALgAECgQJCAAAAA==.Rivulet:BAAALgAECgUJDAAAAA==.',
Ro='Roombaa:BAAALgADCgQJAgAAAA==.Royfenix:BAACLgAFFH8IAAMYAAMJKwoyMABsAAAYAAIJ8wMyMABsAAAmAAEJdhHrMgAzAAAuAAQKfyQABCYABgnZGVghAKsBACYABgnZGVghAKsBABgAAwklDddZAKAAAAIAAwnhAnFhAF8AAAAA.',
Ru='Rukaillin:BAAALgAECgYJBwAAAA==.',
Ry='Ryukaii:BAAALgAECgYJCAAAAA==.Ryyah:BAABLgAECn88AAMTAAgJjBjzGQAqAgATAAgJjBjzGQAqAgAEAAQJLQOONwFlAAAAAA==.',
['Rè']='Rèck:BAAALgAECgUJCAAAAA==.',
['Ré']='Rébecca:BAAALgAECgMJAwABLgAECgkJKQAgAOUMAA==.',
['Rì']='Rìsen:BAAALgADCgYJBgAAAA==.',
['Rú']='Rústy:BAAALgAFFAIJAwAAAA==.',
Sa='Sabris:BAAALgAECgMJAwAAAA==.Saetyl:BAABLgAECn8jAAIeAAgJlwPTTgDCAAAeAAgJlwPTTgDCAAAAAA==.Saga:BAAALgADCgEJAQAAAA==.Salvynus:BAAALgAECgUJBQAAAA==.Samhainn:BAAALgADCgIJAQABLgADCgYJBQAWAAAAAA==.Sanctity:BAAALgAECgMJAwAAAA==.Saphirè:BAAALgAECgUJAQAAAA==.',
Sc='Scrungle:BAAALgADCgYJCwAAAA==.',
Se='Seabiscuìt:BAAALgAECgIJAgAAAA==.Seanthaniel:BAEALgAECgYJBwABLgAFFAcJJgAgAEMRAA==.Seifslam:BAAALgADCgQJBAABLgAECgEJAQAWAAAAAA==.Seifura:BAAALgAECgEJAQAAAA==.Semi:BAAALgAECgQJBQABLgAECggJDQAWAAAAAA==.Semii:BAAALgAECgIJAgAAAA==.Serkerune:BAAALgAECgEJAgAAAA==.Serkesul:BAABLgAECn8sAAIYAAkJaST/AgAyAwAYAAkJaST/AgAyAwAAAA==.Sevinas:BAABLgAECn8pAAIRAAgJnw4wEwB2AQARAAgJnw4wEwB2AQAAAA==.',
Sf='Sfogliatella:BAAALgAECgEJAQAAAA==.',
Sh='Shaftstop:BAAALgADCgkJCQABLgAECgUJBQAWAAAAAA==.Shamallamá:BAAALgADCgkJCgABLgAECgkJMAAOADciAA==.Shamthis:BAABLgAECn8jAAIQAAkJERD/JwCfAQAQAAkJERD/JwCfAQAAAA==.Shamwoww:BAACLgAFFH8GAAIQAAMJURAjMADBAAAQAAMJURAjMADBAAAuAAQKfyEAAhAACAkOHtgRAFYCABAACAkOHtgRAFYCAAEuAAUUBQkTABgASxUA.Shamyou:BAABLgAECn8UAAMFAAkJ1xnQGwA6AgAFAAkJ1xnQGwA6AgAQAAYJKRqeNgBPAQAAAA==.Shealie:BAAALgADCgMJAwABLgAECgkJNwAjAI8dAA==.Shelly:BAAALgAECggJDQAAAA==.Shiftymynx:BAAALgADCgEJAQAAAA==.Shlumpa:BAABLgAECn8dAAIFAAkJZxu1EgCsAgAFAAkJZxu1EgCsAgABLgAFFAQJCAABANEOAA==.Shlumpdragon:BAAALgAECgMJAwABLgAFFAQJCAABANEOAA==.Shlumpydk:BAABLgAFFH8HAAMgAAQJHAQrJgCtAAAgAAQJDwQrJgCtAAASAAEJoQG6DAEvAAAAAA==.Shokcz:BAAALgAECgQJBgAAAA==.Shomba:BAAALgAECgYJBgAAAA==.Shotsfired:BAAALgAECgYJCgAAAA==.Shámjackson:BAACLgAFFH8YAAIFAAYJyiSwAwB0AgAFAAYJyiSwAwB0AgAuAAQKfy4AAgUACQkMJjQDAEcDAAUACQkMJjQDAEcDAAAA.',
Si='Silvey:BAABLgAECn8sAAIMAAkJjiGyCQD2AgAMAAkJjiGyCQD2AgAAAA==.Sindricil:BAAALgADCggJDAAAAA==.',
Sk='Skar:BAAALgADCggJCQAAAA==.Skeletorque:BAABLgAECn8XAAMSAAkJ3BCeZACWAQASAAkJ3BCeZACWAQAgAAEJXA2nSwAfAAAAAA==.Skully:BAAALgAECgEJAQAAAA==.Skyylorne:BAABLgAECn8cAAIHAAcJDxDQGAA3AQAHAAcJDxDQGAA3AQAAAA==.',
Sl='Slipnslide:BAAALgAECgQJBAABLgAECgkJPgACANIdAA==.',
Sm='Smallwdruid:BAAALgAECgYJBgAAAA==.Smashlock:BAAALgADCgUJCAAAAA==.Smellydruid:BAAALgADCgEJAQAAAA==.Smitesword:BAAALgADCgYJDAAAAA==.',
Sn='Snow:BAAALgAECgYJBgABLgAECgkJIgALACsgAA==.Snowfawn:BAABLgAECn8mAAIOAAcJzRpvPwDZAQAOAAcJzRpvPwDZAQABLgAFFAIJBAAWAAAAAA==.Snusnurae:BAAALgAECgcJEgAAAA==.',
So='Sodapoppin:BAAALgADCgcJBwAAAA==.Solas:BAAALgADCgQJBQAAAA==.Somay:BAAALgAECgQJBwAAAA==.Soryn:BAAALgADCgUJBQAAAA==.Sovirus:BAAALgAECgQJBAABLgAECgkJIgALACsgAA==.',
Sp='Spanana:BAABLgAFFH8MAAISAAQJThK3FQBNAQASAAQJThK3FQBNAQAAAA==.Sparevolts:BAAALgAECgEJAQAAAA==.Specialist:BAAALgAFFAIJAwAAAA==.Spicychopz:BAACLgAFFH8ZAAIGAAgJeSPsBgCpAgAGAAgJeSPsBgCpAgAuAAQKfxcAAgYACAnbIRUdAAEDAAYACAnbIRUdAAEDAAAA.Spiketickevi:BAAALgAECggJCAAAAA==.Splishsplásh:BAABLgAECn8pAAIFAAgJEh+KEADAAgAFAAgJEh+KEADAAgAAAA==.Sprattyboii:BAAALgAFFAIJAwAAAA==.Sprucelock:BAAALgADCgIJAgAAAA==.',
Ss='Sscarlet:BAABLgAECn8gAAIGAAkJCQkAcACUAQAGAAkJCQkAcACUAQAAAA==.',
St='Staltis:BAAALgAECgYJBwABLgAECggJLQAJAJ4PAA==.Starrling:BAABLgAECn8WAAIeAAgJNhQuIgCqAQAeAAgJNhQuIgCqAQAAAA==.Starzia:BAABLgAECn8wAAICAAgJ9QfWMABLAQACAAgJ9QfWMABLAQAAAA==.Stupidtree:BAACLgAFFH8QAAIXAAQJTx2yHwBMAQAXAAQJTx2yHwBMAQAuAAQKfxwAAhcABwnMI1cUAJ8CABcABwnMI1cUAJ8CAAAA.',
Su='Sudzyjr:BAAALgADCgUJBQAAAA==.Sunk:BAABLgAECn8tAAIPAAkJJRynHAByAgAPAAkJJRynHAByAgAAAA==.',
Sw='Swagg:BAAALgAECgEJAQAAAA==.Swanho:BAAALgAECgIJBQABLgAECgcJCAAWAAAAAA==.Swiftblossom:BAAALgAECgMJBAAAAA==.',
Sy='Sylvanex:BAABLgAECn8gAAIOAAcJVhq4PADiAQAOAAcJVhq4PADiAQAAAA==.',
['Sê']='Sêrënîty:BAAALgAECgQJBAABLgAFFAUJDwAEAGETAA==.',
['Sô']='Sông:BAAALgAECgUJBgAAAA==.',
Ta='Taestra:BAAALgAECgMJAwAAAA==.Taffbones:BAAALgAECgYJCgAAAA==.Tahla:BAAALgADCgIJAgAAAA==.Talanot:BAAALgAECgUJCwABLgAECgYJFAAdAGwRAA==.Talarus:BAAALgAECggJEQAAAA==.Talurana:BAAALgAECgEJAgAAAA==.Tanadria:BAABLgAECn8kAAIjAAkJCwymGgC0AQAjAAkJCwymGgC0AQAAAA==.Tangerene:BAACLgAFFH8HAAICAAMJbAH/NQCOAAACAAMJbAH/NQCOAAAuAAQKfyAAAwIACQnECls0ADgBAAIACAnxC1s0ADgBACYABgkUAhteALoAAAAA.Tapioca:BAACLgAFFH8PAAIOAAQJ1iDSIABrAQAOAAQJ1iDSIABrAQAuAAQKfzIAAg4ACQkHI44HABkDAA4ACQkHI44HABkDAAAA.Tashyr:BAAALgAECgMJBAAAAA==.',
Tc='Tchort:BAAALgAECgQJBAABLgAFFAcJGAAGAO0WAA==.',
Te='Telemachus:BAAALgAECgEJAQAAAA==.Telm:BAABLgAECn8kAAMEAAcJFxvfZwCUAQAEAAcJcxnfZwCUAQAUAAcJShrDFgBfAQAAAA==.Tentilious:BAAALgAECgQJBQAAAA==.',
Th='Thadeusputz:BAAALgAECgEJAQAAAA==.Thaÿne:BAABLgAECn8WAAIfAAkJiA7pKQCpAQAfAAkJiA7pKQCpAQAAAA==.Thebestpally:BAACLgAFFH8LAAMEAAMJtBOhawDHAAAEAAMJAg2hawDHAAAUAAEJkRYyFQBCAAAuAAQKf0QAAxQACQleHDgFAJQCABQACQleHDgFAJQCAAQABQmNDQXlAMQAAAAA.Thenemisis:BAAALgADCgcJDwAAAA==.Thiccidàn:BAAALgADCgEJAgAAAA==.Thund:BAAALgAECgQJBwAAAA==.',
Ti='Tianielan:BAABLgAECn8aAAMTAAkJGh/iEQB7AgATAAkJGh/iEQB7AgAEAAEJJQ59QgEzAAAAAA==.Tidds:BAABLgAECn8wAAMPAAgJegp+bgBZAQAPAAgJegp+bgBZAQAaAAYJigg0GgDbAAAAAA==.Tinyfloof:BAAALgADCgUJAQAAAA==.',
To='To:BAAALgAECggJDgAAAA==.Toolgunx:BAAALgAECgQJBQAAAA==.Totemdown:BAACLgAFFH8aAAIFAAcJDh9fAwB+AgAFAAcJDh9fAwB+AgAuAAQKfyMAAgUACQm1I+wFAEgDAAUACQm1I+wFAEgDAAAA.',
Tr='Tralth:BAAALgAECgIJAgAAAA==.Trazarath:BAACLgAFFH8YAAMJAAUJ1gthMQDyAAAJAAUJ1gthMQDyAAAKAAIJSAaNDgA/AAAuAAQKfysAAwkACQknFd4WAB8CAAkACQknFd4WAB8CAAoAAwkmBKczAHcAAAAA.Triggaman:BAAALgADCgUJBQABLgAECgcJJAAEABcbAA==.Trunndle:BAAALgADCgUJBQAAAA==.',
Ts='Tsuul:BAAALgAECgQJCwAAAA==.',
Tu='Turbolover:BAAALgAECgEJAQAAAA==.',
Ty='Tylenstus:BAAALgAECgEJAQAAAA==.',
['Tã']='Tãpioca:BAAALgAECgQJDQABLgAFFAQJDwAOANYgAA==.',
Uj='Ujio:BAABLgAECn8ZAAMTAAcJSRgyKAC/AQATAAcJSRgyKAC/AQAEAAMJpwf7IwF8AAABLgAECggJJAAFAGUWAA==.',
Un='Unholyferret:BAAALgADCgIJAgAAAA==.Unify:BAAALgADCgMJBAAAAA==.Untiler:BAAALgADCgUJBQAAAA==.',
Us='Usdaprime:BAAALgAECgIJAwABLgAECgkJFwASANwQAA==.Usopp:BAAALgADCgYJBgAAAA==.',
Uu='Uuyd:BAAALgAFFAIJBAABLgAFFAMJBgAWAAAAAQ==.',
Va='Vaden:BAAALgAECgIJAgABLgAECgcJIAAIAGsWAA==.Vaelthys:BAABLgAECn8eAAIYAAkJ8hj6DQBwAgAYAAkJ8hj6DQBwAgABLgAECgkJKAAPAHwXAA==.Valedarrin:BAAALgADCgEJAQAAAA==.Valefyre:BAAALgADCgcJBwAAAA==.Valenstrasz:BAACLgAFFH8FAAMKAAIJ2gerCQB9AAAKAAIJlQarCQB9AAAJAAIJtQb/UQBxAAAuAAQKfyIAAwkACQmGEjIfAMkBAAkACAkSEzIfAMkBAAoABAn6DjsYAIoAAAAA.Valetherin:BAAALgADCgkJCQAAAA==.Valkaron:BAAALgADCgYJBgABLgAFFAQJDwAEAIMUAA==.Vanaheim:BAAALgAECgkJEwAAAA==.Vance:BAABLgAECn8WAAIEAAYJug0GvwD9AAAEAAYJug0GvwD9AAAAAA==.Vanitha:BAAALgADCggJBgAAAA==.Vanysh:BAAALgAECgMJAwAAAA==.Varala:BAAALgAECgUJCAAAAA==.',
Ve='Vel:BAACLgAFFH8WAAMSAAgJxRvVCwBaAgASAAgJxRvVCwBaAgAgAAEJAAClWgAAAAAuAAQKf0cAAhIACAlRJqAKAEcDABIACAlRJqAKAEcDAAAA.Velandis:BAAALgADCgcJBwAAAA==.Velenari:BAAALgAECgEJAQABLgAECgkJKgACANAcAA==.Vellea:BAAALgAECgYJDgABLgAECgYJFAAdAGwRAA==.Velwar:BAAALgAECgcJCQABLgAFFAgJFgASAMUbAA==.Velýth:BAAALgAECgUJDAABLgAFFAgJFgASAMUbAA==.Venmeumshna:BAAALgAECgQJBAAAAA==.Veritas:BAAALgAECgYJDQAAAA==.Vexxius:BAACLgAFFH8FAAIIAAIJfRiWIwCfAAAIAAIJfRiWIwCfAAAuAAQKfxwABAgACQkJGfUQACECAAgACQn8FPUQACECABsABwkxFIYUAA0BAA4AAQkgD7cdATgAAAAA.',
Vi='Viero:BAAALgAECggJCAAAAA==.',
Vo='Vorathis:BAAALgAECgYJDAABLgAFFAUJHAAFAOQkAA==.',
Vy='Vylana:BAAALgAECgYJDAABLgAFFAUJDwAEAGETAA==.',
['Và']='Vàlkyrie:BAACLgAFFH8PAAIEAAQJgxRnPAAjAQAEAAQJgxRnPAAjAQAuAAQKfyIAAgQACQkCHnEiAKACAAQACQkCHnEiAKACAAAA.',
Wa='Wack:BAAALgAFFAEJAQAAAA==.Wanderfoot:BAABLgAECn8gAAIIAAcJaxbQHACxAQAIAAcJaxbQHACxAQAAAA==.Wangtulo:BAAALgADCgIJAgAAAA==.Warienta:BAAALgAECgMJAwAAAA==.Warity:BAABLgAECn86AAIPAAgJFxtbKAA0AgAPAAgJFxtbKAA0AgAAAA==.Warnarse:BAAALgADCgUJBQAAAA==.Warrill:BAEBLgAECn8bAAIDAAgJ/QknIwAlAQADAAgJ/QknIwAlAQAAAA==.Wavestabe:BAABLgAECn88AAIHAAkJPhrRBgBlAgAHAAkJPhrRBgBlAgAAAA==.',
Wo='Wobblart:BAAALgAECgQJBgABLgAECgkJPAAHAD4aAA==.',
Wr='Wreck:BAACLgAFFH8HAAMPAAMJvwHarQBdAAAPAAIJJwLarQBdAAAaAAEJ7wB+KgAnAAAuAAQKfy0AAg8ACAn1Dg5mAG0BAA8ACAn1Dg5mAG0BAAAA.',
Xe='Xeevala:BAAALgAECgYJEAAAAA==.Xerxseize:BAAALgAECgEJAQAAAA==.',
Xo='Xomby:BAAALgAECgUJBQAAAA==.',
['Xì']='Xìon:BAABLgAECn8WAAMSAAkJohrlHgCHAgASAAkJohrlHgCHAgAiAAEJRwrsOQApAAAAAA==.',
Ya='Yayrri:BAABLgAECn8tAAIQAAkJixFAJQCwAQAQAAkJixFAJQCwAQAAAA==.',
Ye='Yersipestis:BAAALgADCgYJBgAAAA==.',
Yo='Youngjedi:BAAALgAECgUJBQAAAA==.',
Yu='Yungstabby:BAAALgAECgUJBQABLgAECgcJGAAOANMZAA==.Yurî:BAAALgAECgQJCQAAAA==.',
Za='Zahne:BAAALgAECgMJAwABLgAFFAUJBgAaAMEbAA==.Zatarra:BAAALgAECgIJBAAAAA==.Zathamax:BAABLgAECn8VAAIGAAgJaQOrygD0AAAGAAgJaQOrygD0AAAAAA==.Zavya:BAAALgAECgUJBAABLgAECggJHgABAHYJAA==.',
Ze='Zeldei:BAAALgADCgEJAQAAAA==.Zextron:BAABLgAECn8tAAIoAAkJzxGIFwC4AQAoAAkJzxGIFwC4AQAAAA==.',
Zi='Ziaya:BAABLgAECn8eAAIBAAgJdgndOAARAQABAAgJdgndOAARAQAAAA==.Zin:BAAALgADCgQJBAAAAA==.',
Zo='Zolaeus:BAAALgAECgUJDQABLgAECgYJFAAdAGwRAA==.Zorbaks:BAAALgAECgQJBAAAAA==.',
Zu='Zuboo:BAABLgAECn8wAAIoAAgJvQhOKQAfAQAoAAgJvQhOKQAfAQAAAA==.',
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
