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

local lookup = {'Monk-Brewmaster','Priest-Discipline','Warrior-Protection','Paladin-Retribution','Shaman-Restoration','Mage-Frost','Unknown-Unknown','Hunter-Survival','Evoker-Augmentation','DemonHunter-Devourer','DemonHunter-Vengeance','Evoker-Devastation','Hunter-BeastMastery','Druid-Feral','Warlock-Demonology','Shaman-Elemental','Shaman-Enhancement','Paladin-Holy','Druid-Guardian','Druid-Restoration','Priest-Shadow','DeathKnight-Unholy','Warlock-Destruction','Hunter-Marksmanship','Monk-Windwalker','Monk-Mistweaver','Druid-Balance','Paladin-Protection','Warrior-Fury','DeathKnight-Blood','Evoker-Preservation','Warrior-Arms','DeathKnight-Frost','Warlock-Affliction','Rogue-Subtlety','Rogue-Assassination','Mage-Fire','Priest-Holy','Mage-Arcane','DemonHunter-Havoc',}
local provider = {region='US',realm='Antonidas',name='US',type='weekly',zone=46,date='2026-05-23',data={Aa='Aalst:BAABLgAECn8aAAIBAAcJIgnhOAD7AAABAAcJIgnhOAD7AAAAAA==.',
Ac='Achillesheal:BAABLgAECn8ZAAICAAYJoR8SFAAMAgACAAYJoR8SFAAMAgAAAA==.Acidicwrath:BAAALgADCgUJBQAAAA==.Acnologias:BAAALgAECgEJAQABLgAECgkJOQADABAcAA==.Acshec:BAAALgADCgYJDgABLgAECgcJJAAEABcbAA==.Acuna:BAAALgAECgcJCQAAAA==.',
Ad='Aderna:BAAALgADCgMJBAAAAA==.Adoryn:BAEBLgAECn86AAIBAAkJdxClGQC5AQABAAkJdxClGQC5AQAAAA==.',
Ae='Aervyper:BAAALgADCgIJAwAAAA==.Aessan:BAAALgAECgEJAQABLgAECgcJJAAFAP4NAA==.',
Ag='Aggrenox:BAABLgAECn8gAAIEAAYJ5QlhrwAlAQAEAAYJ5QlhrwAlAQAAAA==.',
Ai='Aisathya:BAABLgAECn8fAAIGAAgJPCNCGACtAgAGAAgJPCNCGACtAgAAAA==.',
Ak='Akiza:BAAALgAECgkJDwAAAA==.Akonorix:BAAALgADCgUJCAAAAA==.',
Al='Alaelis:BAAALgAECgYJBgAAAA==.Albina:BAAALgAECgUJCAAAAA==.Aldelvir:BAAALgAECgcJDQABLgAECgkJBQAHAAAAAA==.Alottarage:BAAALgADCgcJCQAAAA==.Alunantre:BAABLgAECn8aAAIIAAkJ6BQ4FgDUAQAIAAkJ6BQ4FgDUAQAAAA==.Alzhimers:BAAALgAECggJEgAAAA==.',
Am='Amberscale:BAACLgAFFH8IAAIJAAMJ+RaMLQDfAAAJAAMJ+RaMLQDfAAAuAAQKfygAAgkACAlGHT0RADsCAAkACAlGHT0RADsCAAAA.Amyrrin:BAABLgAECn8UAAIEAAgJlhEGcwBoAQAEAAgJlhEGcwBoAQAAAA==.',
An='Ancientiur:BAABLgAECn8dAAMKAAkJdBtvLwDpAQAKAAkJUhlvLwDpAQALAAMJ+RIMIABsAAAAAA==.Andormu:BAAALgADCgYJBQAAAA==.Andracca:BAABLgAECn8aAAMJAAgJVxP1JACUAQAJAAgJSBL1JACUAQAMAAQJnxVzDwDxAAAAAA==.Angrulus:BAABLgAECn8zAAINAAkJLRm/HwA/AgANAAkJLRm/HwA/AgAAAA==.Animal:BAAALgAECgIJAgAAAA==.Animlshiftr:BAABLgAECn8jAAIOAAgJrg3tEgBTAQAOAAgJrg3tEgBTAQAAAA==.',
Ap='Apollo:BAABLgAECn8jAAIPAAgJLgmXawBOAQAPAAgJLgmXawBOAQAAAA==.',
Ar='Aradunn:BAACLgAFFH8TAAIFAAQJvSRyDgCqAQAFAAQJvSRyDgCqAQAuAAQKfyUABAUACQk3IvsGAAQDAAUACQk3IvsGAAQDABAAAwkkHc9CAPgAABEAAgmeI3YmAGUAAAAA.Araedis:BAABLgAECn81AAIIAAkJ/xACEAAWAgAIAAkJ/xACEAAWAgAAAA==.Araelle:BAAALgAECgEJAQAAAA==.Archangel:BAAALgAECgYJCwAAAA==.Arrill:BAEALgAECgMJAwABLgAECggJGwADAP0JAA==.Artheren:BAAALgAECgQJBgAAAA==.Aryllyn:BAAALgADCgYJDQAAAA==.',
As='Ashvehtta:BAAALgAECggJEAAAAA==.Assaelysia:BAAALgAECgIJAgAAAA==.Asstormrage:BAAALgADCgUJBQAAAA==.Asti:BAAALgAECgYJDQAAAA==.Astralon:BAAALgAECgIJAwAAAA==.',
At='Atharion:BAABLgAECn8jAAMSAAgJpR63DACfAgASAAgJpR63DACfAgAEAAMJZAwmDAF/AAAAAA==.Atheus:BAAALgADCgEJAQAAAA==.',
Av='Avanda:BAAALgAECgEJBQAAAA==.Avrassa:BAAALgADCgMJAwAAAA==.',
Aw='Awperprime:BAABLgAECn8iAAIRAAgJdxZLDAC3AQARAAgJdxZLDAC3AQAAAA==.',
Ay='Ayhanui:BAAALgAECgEJAgAAAA==.',
Az='Azaléa:BAAALgADCgcJBwAAAA==.Azrathalos:BAAALgAFFAEJAgAAAA==.Azémstraza:BAAALgAECgYJDAAAAA==.',
Ba='Bained:BAAALgADCgcJBwAAAA==.Baldric:BAABLgAECn8lAAINAAgJ8BZZLwD0AQANAAgJ8BZZLwD0AQAAAA==.Balinor:BAABLgAECn8ZAAISAAcJLQ5KNABXAQASAAcJLQ5KNABXAQABLgAECgkJMQADAJ4dAA==.',
Be='Bearett:BAABLgAECn8qAAITAAkJTyKzAQAVAwATAAkJTyKzAQAVAwAAAA==.Beefcakezear:BAAALgADCgQJBAAAAA==.Belyfrost:BAAALgAFFAEJAQAAAA==.Belylight:BAAALgAECgkJDwAAAA==.Belymoon:BAAALgAECgkJCQABLgAECgkJDwAHAAAAAA==.Bernd:BAABLgAECn8iAAITAAgJOQ1OHwAPAQATAAgJOQ1OHwAPAQAAAA==.Beörn:BAABLgAECn8pAAIUAAgJ9yKaBwAjAwAUAAgJ9yKaBwAjAwAAAA==.',
Bl='Blackbeard:BAAALgAECgEJAQABLgAECgkJMQADAJ4dAA==.Blackgrinn:BAABLgAECn8iAAMCAAcJLRCMJgBsAQACAAcJLRCMJgBsAQAVAAcJRwaqOwD6AAAAAA==.Blackkgrin:BAAALgADCgQJBwAAAA==.Blasphemous:BAABLgAECn8dAAIWAAcJgBRBcwBYAQAWAAcJgBRBcwBYAQAAAA==.Blasé:BAABLgAECn8tAAMPAAgJESC+HABeAgAPAAgJESC+HABeAgAXAAEJAACjXABZAAABLgAFFAMJAwAHAAAAAA==.Blazéoné:BAAALgAECgMJAwAAAA==.Blessin:BAAALgAECgcJCgAAAA==.',
Bo='Bobo:BAAALgAECgUJEQAAAA==.Bobrossx:BAACLgAFFH8FAAMYAAIJ7xKHHQCgAAAYAAIJ7xKHHQCgAAANAAIJNQj5ZQCFAAAuAAQKfywABBgACAmZIZcNANgCABgACAkUHpcNANgCAAgABwnXHasXAMUBAA0AAgl9HtG5AJAAAAAA.Bobsmonk:BAAALgADCgEJAQAAAA==.Bomi:BAAALgADCgQJBAAAAA==.Boostéd:BAABLgAECn8XAAIWAAcJdR3VSAAZAgAWAAcJdR3VSAAZAgAAAA==.Boostëd:BAAALgAECgYJBwABLgAECgcJFwAWAHUdAA==.',
Br='Brakevilt:BAAALgADCgQJBAAAAA==.Brattyone:BAAALgADCgcJBwAAAA==.Breadcrums:BAAALgADCgMJAwAAAA==.Bruche:BAABLgAECn8sAAIWAAkJVR2OHQB0AgAWAAkJVR2OHQB0AgAAAA==.Brujaah:BAAALgAECgYJBgABLgAECgkJOgAHAAAAAQ==.Brynthadia:BAAALgAECgYJCAAAAA==.Brzrker:BAAALgADCgYJDAAAAA==.',
Bu='Bubagumps:BAAALgAECgEJAQAAAA==.',
Bw='Bwca:BAACLgAFFH8HAAINAAMJ9A5uRgDcAAANAAMJ9A5uRgDcAAAuAAQKfxQAAg0ABQkjHOtLAJEBAA0ABQkjHOtLAJEBAAEuAAUUAwkMAAUAFQYA.',
Ca='Caine:BAABLgAECn8xAAIDAAkJnh1tCABQAgADAAkJnh1tCABQAgAAAA==.Cakébob:BAAALgADCgQJBQAAAA==.Calmdown:BAAALgADCgYJBwAAAA==.Carraa:BAAALgADCgYJCgABLgAECgcJJAAFAP4NAA==.Casey:BAABLgAECn8WAAIEAAYJEwTS4AC1AAAEAAYJEwTS4AC1AAAAAA==.Castyblasty:BAAALgAECgEJAQAAAA==.Cataaria:BAABLgAECn8kAAIFAAcJ/g2dTgBBAQAFAAcJ/g2dTgBBAQAAAA==.',
Ce='Cellina:BAABLgAECn8YAAIZAAYJmBJfMQAXAQAZAAYJmBJfMQAXAQAAAA==.Cerathal:BAAALgADCgIJAgAAAA==.Ceriumz:BAAALgAECgYJCgABLgAECgkJOQADABAcAA==.',
Ch='Chaniqua:BAAALgADCgQJBQAAAA==.Chiman:BAABLgAECn8UAAMaAAYJbBGnOAA4AQAaAAYJbBGnOAA4AQAZAAUJZgu0RwC3AAAAAA==.Chronophage:BAAALgAECgUJBQAAAA==.Chûd:BAEALgAECgUJBQAAAA==.',
Ci='Ciders:BAAALgAECgEJAQABLgAECgYJGgAIAL8SAA==.',
Cl='Clasastrasza:BAAALgAECgUJBwABLgAFFAMJDQAUANEeAA==.Classá:BAACLgAFFH8NAAMUAAMJ0R4iIwATAQAUAAMJ0R4iIwATAQAbAAMJzhVMIwDbAAAuAAQKf0AABBsACQm8H+kMAGMCABsABwmgJOkMAGMCABQABwmhIMlGAIcBABMAAQmYF15MAEEAAAAA.Clawz:BAAALgAFFAIJAgABLgAFFAMJBgAEAMMXAA==.',
Co='Codedd:BAACLgAFFH8FAAIUAAIJYwYRSwByAAAUAAIJYwYRSwByAAAuAAQKfxkAAhQABwl5EOdGAFABABQABwl5EOdGAFABAAAA.Commit:BAAALgAECggJDgAAAA==.Comradeprime:BAAALgAECgQJCQAAAA==.Corlys:BAABLgAECn8nAAMEAAgJ4SBBKgA2AgAEAAgJoB5BKgA2AgAcAAYJgB3IDgCpAQABLgAECgkJGAAGAOMKAA==.Covi:BAAALgADCgYJBQAAAA==.',
Cr='Crispìn:BAAALgAECgYJEAAAAA==.Crossbones:BAAALgAECgQJBwAAAA==.Crue:BAAALgAECggJEQAAAA==.',
Cu='Curthar:BAACLgAFFH8GAAIEAAMJwxf6RwDyAAAEAAMJwxf6RwDyAAAuAAQKfyAAAxwACQkUJYwAAFsDABwACQkUJYwAAFsDAAQABgmgHodmAIIBAAAA.',
Cy='Cyguy:BAAALgAECgEJAQAAAA==.Cyndee:BAABLgAECn81AAIdAAkJkBViFQAgAgAdAAkJkBViFQAgAgAAAA==.Cynnafrost:BAAALgAECgEJAQAAAA==.Cytenk:BAAALgADCgYJBgAAAA==.',
Da='Dadda:BAABLgAECn80AAIYAAkJzB9WAgC0AgAYAAkJzB9WAgC0AgAAAA==.Dallas:BAAALgADCgcJBwAAAA==.Damascus:BAAALgAECgYJCwABLgAECggJJQANAPAWAA==.Dankmonk:BAABLgAECn8lAAIBAAcJbRVBIQB/AQABAAcJbRVBIQB/AQAAAA==.Darcnis:BAAALgADCgkJGwAAAA==.Darielea:BAAALgADCgIJAgAAAA==.Darkfury:BAABLgAECn80AAIKAAkJiAmhVABlAQAKAAkJiAmhVABlAQAAAA==.Darklasminth:BAAALgAFFAIJAgAAAA==.Darkschi:BAAALgAECgQJBAAAAA==.Darthwang:BAABLgAECn8fAAIPAAYJ6BjsWgC3AQAPAAYJ6BjsWgC3AQAAAA==.Darthwing:BAAALgAECgMJAwABLgAECgYJHwAPAOgYAA==.Dartos:BAABLgAECn86AAIWAAkJ4iQfBABOAwAWAAkJ4iQfBABOAwAAAA==.',
De='Deadlysmash:BAAALgADCgMJAwAAAA==.Deathratio:BAAALgADCgcJBwAAAA==.Deathsbff:BAAALgADCgEJAQABLgAFFAYJFwAGANsZAA==.Deathsend:BAAALgAECggJCAAAAA==.Debluddk:BAABLgAECn8bAAIeAAkJPxO5EADPAQAeAAkJPxO5EADPAQAAAA==.Deep:BAAALgAECgMJAwABLgAECggJJAAaACghAA==.Deepfister:BAABLgAECn8kAAIaAAgJKCFfCgC/AgAaAAgJKCFfCgC/AgAAAA==.Deeplydivine:BAAALgAECgIJAgABLgAECggJJAAaACghAA==.Demone:BAAALgADCgMJAwAAAA==.',
Di='Dic:BAAALgAECgcJCgAAAA==.Diluvium:BAABLgAECn8iAAIEAAgJ9hK4XgCUAQAEAAgJ9hK4XgCUAQAAAA==.Discodank:BAAALgAECgMJBAAAAA==.',
Dj='Djpleasant:BAACLgAFFH8QAAIGAAQJIxLhRAA9AQAGAAQJIxLhRAA9AQAuAAQKfzEAAgYACQmyHYsYAKwCAAYACQmyHYsYAKwCAAAA.',
Dk='Dktelmtwo:BAAALgAECgUJBQAAAA==.',
Do='Doneisha:BAAALgAECgQJCQAAAA==.Dontcare:BAAALgAFFAQJBAAAAA==.Downhammer:BAAALgAECgkJBQAAAA==.',
Dr='Drakamar:BAABLgAECn8yAAQMAAkJAwNIEgDCAAAMAAgJ6QJIEgDCAAAJAAkJwQGzXACXAAAfAAYJMAI8KAB9AAAAAA==.Dranith:BAAALgAECgQJBAAAAA==.Dronos:BAABLgAECn8jAAIbAAgJMyE+CQCbAgAbAAgJMyE+CQCbAgAAAA==.',
Du='Dunzledorf:BAAALgAECgcJBwAAAA==.',
Dy='Dynammes:BAABLgAECn8hAAIGAAcJCxjdXQCpAQAGAAcJCxjdXQCpAQABLgAECgkJIgAJAIYSAA==.',
Ea='Eaglej:BAAALgAECgkJCAAAAA==.Eatmorpizza:BAAALgAECgMJBQAAAA==.',
Eb='Ebore:BAAALgADCggJDQAAAA==.',
Ee='Eegorn:BAAALgAECgYJCgAAAA==.Eegroll:BAACLgAFFH8PAAIBAAQJcBr2FwA0AQABAAQJcBr2FwA0AQAuAAQKfxgAAwEACAmlHLoZALkBAAEABQm9H7oZALkBABkABwkpF+kjALcBAAAA.',
Eg='Egraw:BAAALgAECgQJBAAAAA==.',
El='Elementals:BAAALgAECgkJEwAAAA==.Elixera:BAAALgAECgEJAQAAAA==.Elsä:BAAALgAECgUJAQAAAA==.Elémental:BAAALgADCggJDQAAAA==.',
Em='Emilwhaury:BAAALgADCgIJAgAAAA==.',
Ep='Epia:BAABLgAECn8fAAIZAAgJ/wvQKgA4AQAZAAgJ/wvQKgA4AQAAAA==.',
Er='Eriena:BAAALgAECgYJEQAAAA==.',
Es='Essaila:BAABLgAECn8qAAIOAAkJpQzgDgCSAQAOAAkJpQzgDgCSAQAAAA==.',
Et='Etheo:BAAALgAECgEJAQAAAA==.Etherwalker:BAABLgAECn8kAAMdAAgJ4CS1CAC3AgAdAAgJTyS1CAC3AgAgAAMJcB/SMQDOAAAAAA==.',
Ev='Evocati:BAABLgAECn8YAAMhAAYJ2xeWDgA/AQAhAAYJ3hWWDgA/AQAWAAYJGRdakAAfAQABLgAFFAUJDQAEABYaAA==.Evoka:BAABLgAECn8lAAMMAAgJjR7yDAAMAgAMAAcJVx/yDAAMAgAJAAYJWRvFKgBwAQABLgAECgkJGwAeAD8TAA==.',
Ex='Excision:BAABLgAECn8eAAMJAAgJWA7MPAAQAQAMAAcJcw2yHgA5AQAJAAcJ1wvMPAAQAQAAAA==.Exmachina:BAAALgADCgYJBgAAAA==.',
Ez='Ezindrozath:BAABLgAECn8mAAQPAAgJahZvRAC2AQAPAAgJrRVvRAC2AQAiAAQJcBYlEQAbAQAXAAEJ7wVOeQAqAAAAAA==.',
Fa='Fahbio:BAABLgAECn8dAAIcAAcJuQFIMAB3AAAcAAcJuQFIMAB3AAAAAA==.Fataliny:BAAALgADCgUJCAAAAA==.Fatallock:BAABLgAECn8sAAMPAAcJSxHEYABpAQAPAAcJSxHEYABpAQAiAAEJaQjUMAA0AAAAAA==.Fatlife:BAAALgADCgYJBgAAAA==.',
Fi='Fishdish:BAAALgAECgIJAgAAAA==.Fistsmither:BAAALgAECgYJCAABLgAECgcJHAAjAKITAA==.Fivevolts:BAABLgAECn8kAAIkAAgJFyJdAgCTAgAkAAgJFyJdAgCTAgAAAA==.',
Fl='Flailuid:BAAALgAECgQJDQAAAA==.Flimfam:BAAALgAECgEJAQAAAA==.',
Fo='Forkin:BAAALgADCgIJAgAAAA==.Forthstryke:BAAALgAECgIJBgAAAA==.Four:BAAALgADCgUJBQAAAA==.Fozzi:BAAALgAECgYJBwAAAA==.',
Fr='Freddyg:BAAALgADCgMJBAAAAA==.Fridaychill:BAACLgAFFH8KAAIZAAQJxRhKDAA4AQAZAAQJxRhKDAA4AQAuAAQKfzQAAhkACAm5Io4IAJkCABkACAm5Io4IAJkCAAAA.Fries:BAEALgAECgEJAQABLgAFFAQJBwAPAKYPAA==.Frostdeeps:BAAALgAECgcJEwAAAA==.Frozarke:BAABLgAECn8nAAIJAAgJ9A0zMABOAQAJAAgJ9A0zMABOAQAAAA==.',
Fu='Fudd:BAABLgAECn8hAAINAAcJnRo7OwDHAQANAAcJnRo7OwDHAQAAAA==.Fupa:BAABLgAECn8dAAINAAYJKQ0mfAAYAQANAAYJKQ0mfAAYAQAAAA==.',
Ga='Gaiaslieg:BAAALgADCgMJAwAAAA==.Galand:BAAALgAECgYJBgAAAA==.Galathynius:BAAALgADCgUJBQAAAA==.Galeine:BAAALgADCgMJAwAAAA==.Gangplank:BAAALgADCgMJAwAAAA==.Garres:BAABLgAECn8cAAIOAAcJuh+bCQD2AQAOAAcJuh+bCQD2AQAAAA==.',
Ge='Genius:BAABLgAECn8bAAIgAAcJUBvaEgCiAQAgAAcJUBvaEgCiAQAAAA==.Gennosuke:BAAALgADCgcJBQAAAA==.',
Gh='Ghostkillaz:BAAALgADCgkJFwAAAA==.Ghostxkillaz:BAAALgADCgMJAwAAAA==.',
Gi='Gibley:BAABLgAECn8VAAIEAAgJ0BjlfgB8AQAEAAgJ0BjlfgB8AQAAAA==.',
Gl='Gladorf:BAAALgADCgYJBgAAAA==.',
Gn='Gnazgul:BAAALgAECgMJBAAAAA==.Gnomad:BAABLgAECn8lAAIGAAcJwwPjwwDmAAAGAAcJwwPjwwDmAAAAAA==.',
Go='Goat:BAAALgAECgYJCQAAAA==.Gouge:BAAALgAECgkJOgAAAQ==.',
Gr='Griffynshu:BAABLgAECn8lAAIUAAkJlBtaEACvAgAUAAkJlBtaEACvAgAAAA==.Griz:BAAALgAECgYJBgAAAA==.Grizzlyburr:BAAALgAECgcJDQABLgAFFAMJBgABAJ8OAA==.Grunewald:BAABLgAECn9JAAINAAgJjwm+WQBpAQANAAgJjwm+WQBpAQAAAA==.',
Gu='Guinn:BAAALgADCgIJAgABLgAECggJJwAJAPQNAA==.Gula:BAABLgAECn8hAAMiAAkJPxU/CQCxAQAPAAkJKBR3QgC8AQAiAAYJHRc/CQCxAQAAAA==.Guldanshower:BAAALgADCgUJBQAAAA==.Gunhild:BAAALgAECgIJAgAAAA==.Gutdiver:BAAALgADCgUJBQAAAA==.',
Ha='Handiboyswag:BAACLgAFFH8RAAICAAQJAx7MFgBfAQACAAQJAx7MFgBfAQAuAAQKfxgAAxUABwm4E5QgANQBABUABwm4E5QgANQBAAIABAnJIhYwAB8BAAAA.Hando:BAAALgAECgYJCAAAAA==.Hattock:BAAALgADCgcJFQAAAA==.Hayate:BAAALgAECgUJBQAAAA==.',
He='Heavyshlump:BAACLgAFFH8GAAIBAAMJnw6bLgDOAAABAAMJnw6bLgDOAAAuAAQKfx4AAgEACQnEFDAQABwCAAEACQnEFDAQABwCAAAA.Hehateme:BAAALgAECgIJAgAAAA==.Hehexd:BAABLgAECn8pAAIjAAgJARvUEwB3AgAjAAgJARvUEwB3AgAAAA==.Heimdall:BAABLgAECn8aAAISAAgJxxw6EABzAgASAAgJxxw6EABzAgAAAA==.Hellavva:BAAALgAECgMJAwAAAA==.Hench:BAAALgAECgYJBgAAAA==.Henchling:BAABLgAECn84AAMFAAkJGyApCQDkAgAFAAkJGyApCQDkAgAQAAkJaRLcHQDGAQAAAA==.Henchragon:BAAALgADCgUJBQAAAA==.',
Hi='Hissteria:BAAALgAECgIJAwAAAA==.',
Hn='Hngyhngyloko:BAABLgAECn8ZAAIGAAcJzxt5bQD6AQAGAAcJzxt5bQD6AQABLgAFFAMJCAAJAOYUAA==.',
Ho='Hoerified:BAAALgADCgEJAQABLgAECggJKQAjAAEbAA==.Holexios:BAAALgAECgQJCQABLgAECgYJFAAaAGwRAA==.Holybonks:BAAALgADCgcJBwAAAA==.Holycanoli:BAAALgAECgEJAgAAAA==.Holycrusade:BAAALgAECgUJCgAAAA==.Horine:BAABLgAECn8dAAINAAYJtw6NeAAfAQANAAYJtw6NeAAfAQAAAA==.Hotsteve:BAAALgAECgQJBwAAAA==.',
Hu='Huntër:BAAALgAECgQJBQAAAA==.Huruk:BAAALgAECgIJAgAAAA==.',
Ic='Icieblade:BAAALgAECgkJEQAAAA==.Icyscorcher:BAABLgAECn8gAAMGAAgJgxRdVADCAQAGAAgJgxRdVADCAQAlAAMJpwOyCwB3AAABLgAECgkJOQADABAcAA==.',
Ik='Ikairi:BAAALgAECgEJAQAAAA==.',
Il='Illidankness:BAAALgAECgQJBAAAAA==.Illidoran:BAAALgAECgMJAwABLgAECgYJHQAmAFYWAA==.',
Im='Immeira:BAABLgAECn8XAAIFAAYJIwodZAD3AAAFAAYJIwodZAD3AAAAAA==.',
In='Intense:BAAALgAECgcJAwAAAA==.',
Ja='Jackheals:BAACLgAFFH8MAAIUAAMJoxUULADlAAAUAAMJoxUULADlAAAuAAQKfzAAAxQACAmVIdkJAP8CABQACAmVIdkJAP8CABsAAQnZAdqPABsAAAAA.Jaehaerys:BAAALgAECgQJCAABLgAECgkJGAAGAOMKAA==.',
Jb='Jblackly:BAAALgAECgYJCQAAAA==.',
Jf='Jfreeman:BAAALgADCgYJBwAAAA==.',
Ji='Jimzdrood:BAAALgAECgEJAQAAAA==.Jinbeyblade:BAAALgAECgMJAwABLgAECgkJJgANAEUhAA==.Jinphoenix:BAABLgAECn8mAAMNAAkJRSEkCQDuAgANAAkJRSEkCQDuAgAYAAQJkAeMXwDDAAAAAA==.Jitb:BAAALgADCgYJBwABLgAFFAUJDAAaAI8MAA==.',
Jo='Jobin:BAACLgAFFH8NAAIWAAMJ4BKSdwDhAAAWAAMJ4BKSdwDhAAAuAAQKfxkAAhYACAn5G0twAKgBABYACAn5G0twAKgBAAAA.Journei:BAAALgAECgcJEwAAAA==.',
Ju='Judging:BAABLgAECn8oAAMSAAgJqxVLHgDpAQASAAgJqxVLHgDpAQAEAAIJHSX40ADMAAAAAA==.Junkhead:BAAALgAECgEJAQAAAA==.',
Ka='Kaethe:BAAALgAECgYJBgAAAA==.Kaiduo:BAAALgADCgEJAQAAAA==.Kaitos:BAAALgAFFAIJBAABLgAFFAMJBgAEAMMXAA==.Kalmas:BAABLgAFFH8LAAIbAAMJmwcPKAC7AAAbAAMJmwcPKAC7AAAAAA==.',
Ke='Kegz:BAAALgADCggJCAABLgAECgkJKgACANAcAA==.Kelendrian:BAAALgAECgUJBQAAAA==.Kellayna:BAABLgAECn8XAAIEAAgJdAV5oAAVAQAEAAgJdAV5oAAVAQAAAA==.Kennyx:BAAALgAECgMJAwAAAA==.Kerine:BAAALgAECgMJBAAAAA==.Keylö:BAAALgADCgUJBwAAAA==.Kezix:BAABLgAECn8eAAIPAAkJlA76QQC+AQAPAAkJlA76QQC+AQAAAA==.',
Kh='Kharigosa:BAAALgAECgEJAQABLgAECggJFgASAH8ZAA==.',
Ki='Kigerstorm:BAAALgADCgEJAQAAAA==.Kimeltoe:BAAALgADCgIJAgAAAA==.Kimigosa:BAABLgAECn8nAAQJAAgJfhGoIwChAQAJAAgJvA+oIwChAQAMAAIJ7guiIAA0AAAfAAEJwQF4TgAiAAAAAA==.Kimpachi:BAAALgAECgEJAQABLgAECggJJwAJAH4RAA==.',
Kl='Klerik:BAACLgAFFH8VAAIPAAUJqBWoOQAxAQAPAAUJqBWoOQAxAQAuAAQKfykABA8ACQkaH9sXAHwCAA8ACQmyHdsXAHwCABcAAgkpEmxMAIgAACIAAQlxJFcoAFAAAAAA.',
Kn='Kníghtmare:BAAALgAECgYJDwAAAA==.',
Ko='Kolesnikov:BAAALgAECgUJCAAAAA==.Koragg:BAACLgAFFH8bAAIeAAUJiiFdCgB4AQAeAAUJiiFdCgB4AQAuAAQKfzwAAh4ACQnIJIwCAA4DAB4ACQnIJIwCAA4DAAAA.Kore:BAABLgAECn8fAAIUAAYJZBbKQABrAQAUAAYJZBbKQABrAQAAAA==.Korrag:BAAALgAECgQJBgAAAA==.Kozarke:BAABLgAECn8oAAIMAAgJXxSgBgC6AQAMAAgJXxSgBgC6AQAAAA==.',
Kp='Kpop:BAABLgAECn8bAAILAAkJfxktBwAWAgALAAkJfxktBwAWAgABLgAFFAMJBgABAJ8OAA==.',
Kr='Krissia:BAABLgAECn8iAAIWAAkJhhhAQwDXAQAWAAkJhhhAQwDXAQAAAA==.',
Ku='Kumadbear:BAAALgADCgEJAQAAAA==.',
Ky='Kyntaliia:BAAALgAECgQJBAAAAA==.',
['Kí']='Kítsuñe:BAAALgAECgMJAwAAAA==.',
['Kî']='Kîn:BAABLgAECn8gAAIKAAcJxhSFVwBdAQAKAAcJxhSFVwBdAQAAAA==.',
La='Ladriana:BAAALgADCgEJAgAAAA==.Laisera:BAABLgAECn8zAAMmAAkJmRBHHwClAQAmAAkJmRBHHwClAQAVAAEJdQbtdwApAAAAAA==.Lalipop:BAABLgAECn8zAAImAAkJbBb4DgBRAgAmAAkJbBb4DgBRAgAAAA==.Landroval:BAABLgAECn8jAAIJAAgJLxpGFgAGAgAJAAgJLxpGFgAGAgAAAA==.Lauma:BAACLgAFFH8MAAIFAAMJFQYIQgCqAAAFAAMJFQYIQgCqAAAuAAQKfxUAAgUABwmwEs49AIUBAAUABwmwEs49AIUBAAAA.Lawson:BAABLgAECn81AAIWAAkJZhw+GwCBAgAWAAkJZhw+GwCBAgAAAA==.',
Le='Lelora:BAAALgAECgUJCQAAAA==.Lenthaden:BAABLgAECn86AAMPAAkJOBhhJgAqAgAPAAkJDBZhJgAqAgAXAAYJqxNeJQAyAQAAAA==.Lexusis:BAAALgADCgIJAgAAAA==.',
Li='Lightsmasher:BAAALgAECgEJAQAAAA==.Lihaeh:BAAALgADCgEJAQAAAA==.Lilflame:BAAALgAECgMJAwAAAA==.Lio:BAAALgAECgYJDgAAAA==.Lissetteliz:BAAALgAECgQJBQAAAA==.Livdangerous:BAAALgADCgUJBQAAAA==.',
Lo='Lomax:BAAALgAECgEJAQAAAA==.Longlegs:BAAALgADCgYJBgAAAA==.',
Lu='Lumawig:BAAALgAECgUJDQAAAA==.Lumillras:BAAALgADCgYJCgAAAA==.Lunchdk:BAACLgAFFH8NAAMeAAMJOhebDgCAAAAWAAIJJR78kwCkAAAeAAIJBwybDgCAAAAuAAQKfykAAxYACQlzH7URAMECABYACAlXI7URAMECAB4ACAlzF2gVALwBAAAA.',
Ly='Lyreth:BAABLgAECn8pAAIbAAkJJRAaHgCpAQAbAAkJJRAaHgCpAQAAAA==.',
Ma='Madax:BAABLgAECn86AAMdAAkJxiGwCAC3AgAdAAkJGCGwCAC3AgADAAkJTxyoBQCYAgABLgAECgkJIgAJAIYSAA==.Mageymutt:BAACLgAFFH8XAAIGAAYJ2xlbDAC7AQAGAAYJ2xlbDAC7AQAuAAQKfyUAAwYACAmNIKElANwCAAYACAmNIKElANwCACcAAwkmCx8UAIQAAAAA.Maggidabeast:BAABLgAECn8gAAIGAAgJHgSkqQARAQAGAAgJHgSkqQARAQAAAA==.Magnion:BAAALgAECgEJAQAAAA==.Maison:BAAALgAECgQJBQAAAA==.Malase:BAAALgADCgUJAwAAAA==.Maloch:BAAALgADCgUJBQAAAA==.',
Me='Meaculpa:BAAALgADCgUJCgAAAA==.Megamilk:BAACLgAFFH8JAAIhAAQJQQe7CwDyAAAhAAQJQQe7CwDyAAAuAAQKfzEAAiEACQmqGjAGAAUCACEACQmqGjAGAAUCAAAA.Mekri:BAAALgADCgYJBgABLgAECgcJJAAEABcbAA==.Melledreaux:BAAALgADCgMJAwAAAA==.Metrolinea:BAACLgAFFH8JAAIGAAQJZg8tVQAbAQAGAAQJZg8tVQAbAQAuAAQKfzMAAgYACQm8HoEZAKYCAAYACQm8HoEZAKYCAAAA.',
Mi='Micalknight:BAAALgAECgIJAQAAAA==.Milliy:BAAALgAECgQJBwAAAA==.Minervá:BAAALgADCgMJAwABLgAFFAMJDQAUANEeAA==.Missbehaving:BAABLgAECn8hAAMmAAcJjRSKKQBXAQAmAAcJjRSKKQBXAQAVAAEJQQdYdgArAAAAAA==.',
Mo='Morefire:BAAALgAECgQJCQABLgAECgkJEwAHAAAAAA==.Mosmos:BAAALgADCgkJFQAAAA==.',
Mu='Muddslinger:BAABLgAECn8XAAIdAAgJJAvUNABQAQAdAAgJJAvUNABQAQAAAA==.Mumra:BAABLgAECn8sAAQmAAgJfwRsNAAOAQAmAAgJfwRsNAAOAQACAAYJdgFaPwC0AAAVAAEJAADbgQAAAAAAAA==.',
My='Mystblade:BAAALgAECgIJAgAAAA==.Mystlord:BAAALgAECgQJBAAAAA==.',
Na='Nadatank:BAAALgADCgQJBAAAAA==.Nalesean:BAAALgAECgIJAwAAAA==.Nanaki:BAABLgAECn8iAAIfAAkJKyDzBgDQAgAfAAkJKyDzBgDQAgAAAA==.Nannette:BAAALgAECgYJEgAAAA==.Nappe:BAAALgAECgEJAQABLgAECggJHAAEABskAA==.Narag:BAABLgAECn8xAAINAAkJDxkSGQBnAgANAAkJDxkSGQBnAgAAAA==.Nazfu:BAAALgAECgEJAgAAAA==.Nazg:BAAALgADCgQJAgAAAA==.',
Ne='Nerfertari:BAAALgAECgEJBQAAAA==.Netanyahoo:BAAALgAFFAIJAgAAAA==.Neva:BAAALgAECgIJAgAAAA==.Newport:BAABLgAECn8mAAMFAAgJSh94EACiAgAFAAgJSh94EACiAgAQAAIJmAhyeQBNAAAAAA==.',
Ni='Ninex:BAABLgAECn8cAAISAAgJTR/RGABMAgASAAgJTR/RGABMAgAAAA==.Ninisina:BAABLgAECn8xAAMFAAcJBSEQFAB+AgAFAAcJBSEQFAB+AgARAAEJ7wOHLgAsAAAAAA==.Nithén:BAAALgADCgYJDQAAAA==.',
No='Nonaleeta:BAAALgAECgQJCAAAAA==.Notafurry:BAAALgADCgcJCQAAAA==.Novaa:BAAALgAECgcJAgAAAA==.Nowhere:BAAALgAECgUJBQABLgAECgcJHAAjAKITAA==.Nowon:BAABLgAECn8ZAAMoAAYJHRKoJwACAQAoAAYJHRKoJwACAQALAAEJpwg6MQAcAAAAAA==.',
Nu='Nudream:BAABLgAECn8bAAISAAkJpAOpOQA6AQASAAkJpAOpOQA6AQAAAA==.',
Ny='Nybors:BAAALgADCgcJCwAAAA==.',
['Nö']='Nörse:BAABLgAECn8aAAMbAAYJDhB5QADaAAAbAAYJCA95QADaAAAOAAEJpBeWNgBHAAAAAA==.',
Ol='Olakua:BAAALgAECgMJAwAAAA==.Oldjerry:BAABLgAECn8cAAIjAAcJohNIHwBwAQAjAAcJohNIHwBwAQAAAA==.Oliaa:BAAALgADCgYJCAAAAA==.',
Op='Opalyte:BAABLgAECn8gAAImAAcJ1A1fMgAaAQAmAAcJ1A1fMgAaAQAAAA==.',
Or='Orichalcum:BAABLgAECn8hAAIaAAgJaBwcEQBiAgAaAAgJaBwcEQBiAgAAAA==.Orphiee:BAAALgAECgUJDQAAAA==.',
Os='Oslagsi:BAAALgADCgcJDgAAAA==.Osyriss:BAAALgADCgUJBgAAAA==.',
Ot='Othril:BAAALgAECgEJAQAAAA==.',
Ou='Outis:BAAALgAFFAMJBQAAAQ==.',
Pa='Pakoros:BAABLgAECn8tAAMFAAkJKBi3FQBvAgAFAAkJKBi3FQBvAgAQAAQJBwp7agCZAAAAAA==.Palibuddy:BAAALgAECgMJAwAAAA==.Pallyfreak:BAAALgAECgQJCQAAAA==.',
Pe='Peachy:BAAALgAECgEJAgABLgAECggJKAAFAKgVAA==.Penderin:BAAALgAECgkJBQAAAA==.Penilock:BAAALgADCgIJAgAAAA==.Pensham:BAAALgAECgEJAgABLgAECgkJBQAHAAAAAA==.Perlindree:BAABLgAECn8tAAINAAgJDwgbYwBSAQANAAgJDwgbYwBSAQAAAA==.',
Pg='Pgorlelgy:BAABLgAECn8sAAINAAkJ/hYFJQAjAgANAAkJ/hYFJQAjAgAAAA==.',
Ph='Phira:BAAALgADCgEJAQAAAA==.Phoenix:BAAALgADCgIJAgAAAA==.Physgun:BAAALgADCgYJDgAAAA==.',
Pi='Pillows:BAAALgADCgYJBgAAAA==.',
Pl='Platious:BAABLgAECn8kAAIEAAcJVhFDgwBIAQAEAAcJVhFDgwBIAQAAAA==.',
Po='Pony:BAAALgADCgUJBQABLgADCgUJCgAHAAAAAA==.Poodin:BAAALgADCgIJAgAAAA==.Pookaboo:BAABLgAECn8VAAIPAAcJCwLvywCYAAAPAAcJCwLvywCYAAAAAA==.Poppers:BAAALgADCgYJBgAAAA==.',
Pr='Preacharond:BAACLgAFFH8OAAIVAAQJPRHjEgA0AQAVAAQJPRHjEgA0AQAuAAQKf0gAAhUACQkeINYFANoCABUACQkeINYFANoCAAAA.Promir:BAAALgAECgcJDQAAAA==.',
Pu='Purdie:BAAALgAECgQJBAABLgAECgcJJAAFAP4NAA==.',
Qe='Qeesa:BAAALgAECgEJAQAAAA==.',
Qi='Qiryana:BAAALgADCgIJAgAAAA==.',
Ra='Raeliene:BAABLgAECn8kAAIEAAkJKB1uGQCNAgAEAAkJKB1uGQCNAgAAAA==.Rafikie:BAAALgAECgEJAQAAAA==.Ratchet:BAAALgADCgMJAwAAAA==.Rawmeat:BAABLgAECn86AAICAAkJxBwtCQC4AgACAAkJxBwtCQC4AgAAAA==.Razillar:BAAALgAECgEJAQAAAA==.',
Re='Rebelpatriot:BAAALgADCgYJCQAAAA==.Relaxnerdlol:BAAALgAECgEJBAAAAA==.Reldwick:BAAALgADCgYJBwAAAA==.Renew:BAABLgAECn8eAAMmAAkJHB5fBwDVAgAmAAkJHB5fBwDVAgAVAAcJIBMCJgBzAQAAAA==.Renix:BAACLgAFFH8OAAIQAAQJEhlzFQA0AQAQAAQJEhlzFQA0AQAuAAQKfzIAAxAACQlmH18KAJYCABAACQlmH18KAJYCABEAAQl1CxYtADIAAAAA.Reno:BAAALgAECgMJAwAAAA==.Revery:BAAALgADCgIJAgAAAA==.',
Rh='Rhadgar:BAAALgADCgcJCQAAAA==.',
Ri='Ripmyname:BAAALgAECgYJBgAAAA==.Riverah:BAAALgAECgQJCAAAAA==.Rivulet:BAAALgAECgUJDAAAAA==.',
Ro='Roombaa:BAAALgADCgQJAgAAAA==.Royfenix:BAABLgAECn8dAAMmAAYJVhYLJQB4AQAmAAYJVhYLJQB4AQACAAMJ4QJaVABhAAAAAA==.',
Ru='Rukaillin:BAAALgAECgYJBwAAAA==.',
Ry='Ryukaii:BAAALgAECgYJBwAAAA==.Ryyah:BAABLgAECn81AAMSAAgJjBhZFgAxAgASAAgJjBhZFgAxAgAEAAQJLQMvEwFsAAAAAA==.',
['Rè']='Rèck:BAAALgAECgUJCAAAAA==.',
['Ré']='Rébecca:BAAALgAECgMJAwABLgAECgkJKQAeAOUMAA==.',
['Rì']='Rìsen:BAAALgADCgYJBgAAAA==.',
['Rú']='Rústy:BAAALgAFFAIJAwAAAA==.',
Sa='Saetyl:BAABLgAECn8hAAIbAAcJoAOoSwCsAAAbAAcJoAOoSwCsAAAAAA==.Saga:BAAALgADCgEJAQAAAA==.Salvynus:BAAALgAECgUJBQAAAA==.Samhainn:BAAALgADCgIJAQABLgADCgYJBQAHAAAAAA==.Saphirè:BAAALgAECgUJAQAAAA==.',
Sc='Scrungle:BAAALgADCgYJCwAAAA==.',
Se='Seabiscuìt:BAAALgAECgIJAgAAAA==.Seanthaniel:BAEALgAECgEJAQABLgAFFAYJHgAeAKMSAA==.Seifslam:BAAALgADCgQJBAABLgAECgEJAQAHAAAAAA==.Seifura:BAAALgAECgEJAQAAAA==.Semi:BAAALgAECgQJBQABLgAECgkJIAASAGEdAA==.Semii:BAAALgAECgIJAgAAAA==.Serkesul:BAABLgAECn8pAAIVAAgJQSSiBgDLAgAVAAgJQSSiBgDLAgAAAA==.Sevinas:BAABLgAECn8dAAIRAAYJSg/SFwAFAQARAAYJSg/SFwAFAQAAAA==.',
Sf='Sfogliatella:BAAALgAECgEJAQAAAA==.',
Sh='Shaftstop:BAAALgADCgkJCQABLgAECgUJBQAHAAAAAA==.Shamallamá:BAAALgADCgkJCgABLgAECggJLQANABUiAA==.Shamthis:BAABLgAECn8VAAIQAAkJmgVWOAAmAQAQAAkJmgVWOAAmAQAAAA==.Shamwoww:BAAALgAFFAMJBAABLgAFFAQJDgAVAD0RAA==.Shamyou:BAABLgAECn8UAAMFAAkJ1xnQGwA6AgAFAAkJ1xnQGwA6AgAQAAYJKRreLwBTAQAAAA==.Shealie:BAAALgADCgMJAwABLgAECgkJLwAjAFYdAA==.Shiftymynx:BAAALgADCgEJAQAAAA==.Shlumpa:BAABLgAECn8ZAAIFAAcJQBrHJgD4AQAFAAcJQBrHJgD4AQABLgAFFAMJBgABAJ8OAA==.Shlumpdragon:BAAALgAECgMJAwABLgAFFAMJBgABAJ8OAA==.Shlumpydk:BAAALgAFFAEJAgAAAA==.Shokcz:BAAALgAECgQJBQAAAA==.Shomba:BAAALgAECgYJBgAAAA==.Shotsfired:BAAALgAECgYJCgAAAA==.Shámjackson:BAACLgAFFH8TAAIFAAUJRyapBAAsAgAFAAUJRyapBAAsAgAuAAQKfy4AAgUACQkMJmADAGUDAAUACQkMJmADAGUDAAAA.',
Si='Silvey:BAABLgAECn8nAAIKAAgJYSE8EgCUAgAKAAgJYSE8EgCUAgAAAA==.Sindricil:BAAALgADCggJDAAAAA==.',
Sk='Skar:BAAALgADCggJCQAAAA==.Skeletorque:BAABLgAECn8UAAMWAAgJTBBnfwA/AQAWAAgJTBBnfwA/AQAeAAEJXA2nSwAfAAAAAA==.Skully:BAAALgAECgEJAQAAAA==.Skyylorne:BAAALgAECgYJDQAAAA==.',
Sl='Slipnslide:BAAALgADCgYJBgABLgAECgkJOgACAMQcAA==.',
Sm='Smallwdruid:BAAALgAECgYJBgAAAA==.Smashlock:BAAALgADCgUJCAAAAA==.Smellydruid:BAAALgADCgEJAQAAAA==.Smitesword:BAAALgADCgYJDAAAAA==.',
Sn='Snow:BAAALgAECgYJBgABLgAECgkJIgAfACsgAA==.Snowfawn:BAABLgAECn8fAAINAAcJcRBjVQB1AQANAAcJcRBjVQB1AQABLgAFFAIJAgAHAAAAAA==.Snusnurae:BAAALgAECgYJDAAAAA==.',
So='Sodapoppin:BAAALgADCgcJBwAAAA==.Somay:BAAALgAECgQJBwAAAA==.Soryn:BAAALgADCgUJBQAAAA==.Sovirus:BAAALgAECgQJBAABLgAECgkJIgAfACsgAA==.',
Sp='Spanana:BAABLgAFFH8MAAIWAAQJThK3FQBNAQAWAAQJThK3FQBNAQAAAA==.Specialist:BAAALgAFFAIJAwAAAA==.Spicychopz:BAACLgAFFH8YAAIGAAgJeSOhAgDEAgAGAAgJeSOhAgDEAgAuAAQKfxcAAgYACAnbIRUdAAEDAAYACAnbIRUdAAEDAAAA.Spiketickevi:BAAALgAECggJCAAAAA==.Splishsplásh:BAABLgAECn8dAAIFAAYJXh//IQAVAgAFAAYJXh//IQAVAgAAAA==.Sprattyboii:BAAALgAFFAEJAQAAAA==.Sprucelock:BAAALgADCgIJAgAAAA==.',
Ss='Sscarlet:BAABLgAECn8WAAIGAAkJiAUCfABjAQAGAAkJiAUCfABjAQAAAA==.',
St='Staltis:BAAALgAECgMJBAABLgAECggJJwAJAPQNAA==.Starrling:BAAALgAECggJDgAAAA==.Starzia:BAABLgAECn8oAAICAAgJegdYKgBSAQACAAgJegdYKgBSAQAAAA==.Stupidtree:BAACLgAFFH8LAAIUAAQJUBoiGwBJAQAUAAQJUBoiGwBJAQAuAAQKfxwAAhQABwnMI7IRAKECABQABwnMI7IRAKECAAAA.',
Su='Sudzyjr:BAAALgADCgUJBQAAAA==.Sunk:BAABLgAECn8oAAIPAAgJdRqHKgAXAgAPAAgJdRqHKgAXAgAAAA==.',
Sw='Swagg:BAAALgAECgEJAQAAAA==.Swanho:BAAALgAECgIJBQABLgAECgMJBQAHAAAAAA==.Swiftblossom:BAAALgAECgEJAQAAAA==.',
Sy='Sylvanex:BAAALgAECgUJEgAAAA==.',
['Sê']='Sêrënîty:BAAALgADCgEJAQABLgAFFAEJAwAHAAAAAA==.',
Ta='Taffbones:BAAALgAECgYJCgAAAA==.Tahla:BAAALgADCgIJAgAAAA==.Talanot:BAAALgAECgUJCwABLgAECgYJFAAaAGwRAA==.Talarus:BAAALgAECggJEQAAAA==.Talurana:BAAALgAECgEJAgAAAA==.Tanadria:BAABLgAECn8jAAIjAAkJDwxqFgDCAQAjAAkJDwxqFgDCAQAAAA==.Tangerene:BAACLgAFFH8HAAICAAMJbAG5KgCiAAACAAMJbAG5KgCiAAAuAAQKfxwAAwIACAnABwYuAC4BAAIABwmqCAYuAC4BACYABgkUAhteALoAAAAA.Tapioca:BAACLgAFFH8MAAINAAQJVSCEFQBqAQANAAQJVSCEFQBqAQAuAAQKfy0AAg0ACQmYIVoHAAEDAA0ACQmYIVoHAAEDAAAA.Tashyr:BAAALgAECgMJAwAAAA==.',
Tc='Tchort:BAAALgAECgQJBAABLgAFFAYJFwAGANsZAA==.',
Te='Telemachus:BAAALgAECgEJAQAAAA==.Telm:BAABLgAECn8kAAMEAAcJFxvwWACiAQAEAAcJcxnwWACiAQAcAAcJShp+EwBlAQAAAA==.Tentilious:BAAALgADCgkJDAAAAA==.',
Th='Thadeusputz:BAAALgAECgEJAQAAAA==.Thaÿne:BAAALgAECgcJEAAAAA==.Thebestpally:BAACLgAFFH8HAAMEAAMJGw40UgDdAAAEAAMJAg00UgDdAAAcAAEJxwUqFAAqAAAuAAQKfz4AAxwACQleHBoEAJ0CABwACQleHBoEAJ0CAAQABQmNDQXlAMQAAAAA.Thenemisis:BAAALgADCgcJDwAAAA==.Thiccidàn:BAAALgADCgEJAgAAAA==.Thund:BAAALgAECgQJBwAAAA==.',
Ti='Tianielan:BAABLgAECn8ZAAMSAAgJISArFQA8AgASAAgJISArFQA8AgAEAAEJJQ59QgEzAAAAAA==.Tidds:BAABLgAECn8nAAMPAAcJKQtAeAAzAQAPAAcJKQtAeAAzAQAiAAIJYgixKABPAAAAAA==.',
To='To:BAAALgAECgYJBgAAAA==.Toolgunx:BAAALgAECgQJBQAAAA==.Totemdown:BAACLgAFFH8aAAIFAAcJDh8tAQCeAgAFAAcJDh8tAQCeAgAuAAQKfyMAAgUACQm1I0sEAE0DAAUACQm1I0sEAE0DAAAA.',
Tr='Tralth:BAAALgAECgIJAgAAAA==.Trazarath:BAACLgAFFH8PAAMJAAUJ9wkeKAD9AAAJAAQJ9wkeKAD9AAAMAAEJAACFDwAAAAAuAAQKfysAAwkACQknFd4WAB8CAAkACQknFd4WAB8CAAwAAwkmBKczAHcAAAAA.Triggaman:BAAALgADCgUJBQABLgAECgcJJAAEABcbAA==.Trunndle:BAAALgADCgUJBQAAAA==.',
Ts='Tsuul:BAAALgAECgQJCwAAAA==.',
Tu='Turbolover:BAAALgAECgEJAQAAAA==.',
['Tã']='Tãpioca:BAAALgAECgQJCgABLgAFFAQJDAANAFUgAA==.',
Uj='Ujio:BAABLgAECn8XAAMSAAYJzBmxKgCTAQASAAYJzBmxKgCTAQAEAAMJpwcxAgGFAAABLgAECggJGgAFAI0TAA==.',
Un='Unify:BAAALgADCgMJBAAAAA==.Untiler:BAAALgADCgUJBQAAAA==.',
Us='Usdaprime:BAAALgAECgIJAwAAAA==.Usopp:BAAALgADCgYJBgAAAA==.',
Uu='Uuyd:BAAALgAFFAEJAgABLgAFFAMJBQAHAAAAAQ==.',
Va='Vaden:BAAALgAECgIJAgABLgAECgYJGgAIAL8SAA==.Vaelthys:BAAALgAECgYJDwABLgAECggJJgAPAGoWAA==.Valedarrin:BAAALgADCgEJAQAAAA==.Valefyre:BAAALgADCgcJBwAAAA==.Valenstrasz:BAABLgAECn8iAAMJAAkJhhIyHwDJAQAJAAgJEhMyHwDJAQAMAAQJ+g5RFQCUAAAAAA==.Valetherin:BAAALgADCgkJCQAAAA==.Valkaron:BAAALgADCgYJBgABLgAFFAMJCQAEALgUAA==.Vanaheim:BAAALgAECggJDQAAAA==.Vance:BAABLgAECn8WAAIEAAYJug21pAAOAQAEAAYJug21pAAOAQAAAA==.Vanitha:BAAALgADCggJBgAAAA==.Vanysh:BAAALgAECgMJAwAAAA==.Varala:BAAALgAECgMJAwAAAA==.',
Ve='Vel:BAACLgAFFH8UAAMWAAYJIyH9EwDIAQAWAAYJIyH9EwDIAQAeAAEJAADMSAAAAAAuAAQKf0AAAhYACAkSJqAKAEcDABYACAkSJqAKAEcDAAAA.Velandis:BAAALgADCgcJBwAAAA==.Velenari:BAAALgAECgEJAQABLgAECgkJKgACANAcAA==.Vellea:BAAALgAECgYJDgABLgAECgYJFAAaAGwRAA==.Velwar:BAAALgAECgcJBgABLgAFFAYJFAAWACMhAA==.Velýth:BAAALgAECgUJDAABLgAFFAYJFAAWACMhAA==.Venmeumshna:BAAALgADCgYJBgAAAA==.Veritas:BAAALgAECgYJCwAAAA==.Vexxius:BAACLgAFFH8FAAIIAAIJfRhtHQCnAAAIAAIJfRhtHQCnAAAuAAQKfxwABAgACQkJGT0OACoCAAgACQn8FD0OACoCABgABwkxFNwRABcBAA0AAQkgD7r4ADgAAAAA.',
Vi='Viero:BAAALgAECgcJBwAAAA==.',
Vo='Vorathis:BAAALgAECgYJDAABLgAFFAQJEwAFAL0kAA==.',
Vy='Vylana:BAAALgAECgYJDAABLgAFFAEJAwAHAAAAAA==.',
['Và']='Vàlkyrie:BAACLgAFFH8JAAIEAAMJuBT/SQDuAAAEAAMJuBT/SQDuAAAuAAQKfyIAAgQACQkCHnEiAKACAAQACQkCHnEiAKACAAAA.',
Wa='Wack:BAAALgAFFAEJAQAAAA==.Wanderfoot:BAABLgAECn8aAAIIAAYJvxKHJQBPAQAIAAYJvxKHJQBPAQAAAA==.Wangtulo:BAAALgADCgIJAgAAAA==.Warienta:BAAALgAECgMJAwAAAA==.Warity:BAABLgAECn8qAAIPAAgJRhLoTACdAQAPAAgJRhLoTACdAQAAAA==.Warnarse:BAAALgADCgUJBQAAAA==.Warrill:BAEBLgAECn8bAAIDAAgJ/QknIwAlAQADAAgJ/QknIwAlAQAAAA==.Wavestabe:BAABLgAECn83AAIOAAgJ1hgxCQABAgAOAAgJ1hgxCQABAgABLgAECgkJBQAHAAAAAA==.',
Wo='Wobblart:BAAALgAECgQJBgABLgAECgkJBQAHAAAAAA==.',
Wr='Wreck:BAABLgAECn8pAAIPAAgJ0A6PWwB2AQAPAAgJ0A6PWwB2AQAAAA==.',
Xe='Xeevala:BAAALgAECgYJEAAAAA==.Xerxseize:BAAALgAECgEJAQAAAA==.',
['Xì']='Xìon:BAAALgAECgcJDAAAAA==.',
Ya='Yayrri:BAABLgAECn8oAAIQAAgJORGyKgBwAQAQAAgJORGyKgBwAQAAAA==.',
Yo='Youngjedi:BAAALgAECgUJBQAAAA==.',
Yu='Yurî:BAAALgAECgQJCQAAAA==.',
Za='Zahne:BAAALgAECgMJAwABLgAECgkJIQAPAEggAA==.Zatarra:BAAALgAECgEJAQAAAA==.Zathamax:BAABLgAECn8VAAIGAAgJaQM9twD6AAAGAAgJaQM9twD6AAAAAA==.Zavya:BAAALgADCgEJAQABLgAECgcJHAABAFgKAA==.',
Ze='Zeldei:BAAALgADCgEJAQAAAA==.Zextron:BAABLgAECn8sAAIoAAgJWRJvGACHAQAoAAgJWRJvGACHAQAAAA==.',
Zi='Ziaya:BAABLgAECn8cAAIBAAcJWAqmOwDuAAABAAcJWAqmOwDuAAAAAA==.Zin:BAAALgADCgQJBAAAAA==.',
Zo='Zolaeus:BAAALgAECgUJDQABLgAECgYJFAAaAGwRAA==.Zorbaks:BAAALgAECgQJBAAAAA==.',
Zu='Zuboo:BAABLgAECn8oAAIoAAgJ6weiIwAfAQAoAAgJ6weiIwAfAQAAAA==.',
['Zö']='Zöey:BAAALgADCgQJBQAAAA==.',
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
