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

local lookup = {'Monk-Brewmaster','Priest-Discipline','Warrior-Protection','Paladin-Retribution','Shaman-Restoration','Mage-Frost','Druid-Feral','Hunter-Survival','Warrior-Fury','Hunter-BeastMastery','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','DemonHunter-Devourer','DemonHunter-Vengeance','Warlock-Demonology','Shaman-Elemental','Shaman-Enhancement','DeathKnight-Unholy','Paladin-Holy','Paladin-Protection','Druid-Guardian','Druid-Balance','Druid-Restoration','Priest-Shadow','Warlock-Destruction','Warlock-Affliction','Unknown-Unknown','DeathKnight-Blood','Hunter-Marksmanship','Monk-Windwalker','Monk-Mistweaver','Warrior-Arms','DeathKnight-Frost','Rogue-Subtlety','Rogue-Assassination','Mage-Fire','Priest-Holy','Mage-Arcane','DemonHunter-Havoc',}
local provider = {region='US',realm='Antonidas',name='US',type='weekly',zone=46,date='2026-07-05',data={Aa='Aalst:BAABLgAECn8qAAIBAAkJNQpqKABuAQABAAkJNQpqKABuAQAAAA==.',
Ac='Achillesheal:BAABLgAECn8ZAAICAAYJoR8SFAAMAgACAAYJoR8SFAAMAgAAAA==.Acidicwrath:BAAALgADCgUJBQAAAA==.Acnologias:BAAALgAECgEJAQABLgAFFAMJCAADACYVAA==.Acshec:BAAALgADCgYJDgABLgAECgcJJAAEABcbAA==.Acuna:BAAALgAECgcJCQAAAA==.',
Ad='Aderna:BAAALgADCgMJBAAAAA==.Adoryn:BAEBLgAECn9EAAIBAAkJ2hGfHADAAQABAAkJ2hGfHADAAQAAAA==.',
Ae='Aervyper:BAAALgADCgIJAwAAAA==.Aessan:BAAALgAECgEJAQABLgAECgkJLwAFAFsNAA==.',
Ag='Aggrenox:BAABLgAECn8jAAIEAAgJoQjHtwAUAQAEAAgJoQjHtwAUAQAAAA==.',
Ai='Aisathya:BAABLgAECn8iAAIGAAkJ0CPMCgAjAwAGAAkJ0CPMCgAjAwAAAA==.',
Ak='Akiza:BAAALgAECgkJDwAAAA==.Akonorix:BAAALgADCgUJCAAAAA==.',
Al='Alaelis:BAAALgAECgYJCAAAAA==.Albina:BAABLgAECn8UAAIFAAUJ/RVMXgBCAQAFAAUJ/RVMXgBCAQAAAA==.Aldelvir:BAABLgAECn8VAAIGAAgJAwU6uQAUAQAGAAgJAwU6uQAUAQABLgAECgkJPAAHAD4aAA==.Alottarage:BAAALgADCgcJCQAAAA==.Alunantre:BAABLgAECn8aAAIIAAkJ6BQ4GwDEAQAIAAkJ6BQ4GwDEAQAAAA==.Alzhimers:BAABLgAECn8UAAIJAAgJLhNTLgCXAQAJAAgJLhNTLgCXAQAAAA==.',
Am='Amberfox:BAABLgAFFH8FAAIKAAQJAQ6NFwAeAQAKAAQJAQ6NFwAeAQAAAA==.Amberscale:BAACLgAFFH8TAAILAAQJfRjdKQAhAQALAAQJfRjdKQAhAQAuAAQKfy4ABAsACQkxHLsNAIQCAAsACQkxHLsNAIQCAAwAAwlfHXoQAAMBAA0AAQm3FYg4AEIAAAAA.Amuela:BAAALgADCgYJCwAAAA==.Amyrrin:BAABLgAECn8cAAIEAAgJ3RIOfAB2AQAEAAgJ3RIOfAB2AQAAAA==.',
An='Ancientiur:BAABLgAECn8dAAMOAAkJdBtcOQDhAQAOAAkJUhlcOQDhAQAPAAMJ+RLEJgBrAAAAAA==.Andazaren:BAAALgAECgcJBwAAAA==.Andormu:BAAALgADCgYJBQAAAA==.Andracca:BAABLgAECn8aAAMLAAgJVxNqLACLAQALAAgJSBJqLACLAQAMAAQJnxUjEgDoAAAAAA==.Angrulus:BAABLgAECn9MAAIKAAkJHyJ5CQANAwAKAAkJHyJ5CQANAwAAAA==.Animal:BAAALgAECgYJEAAAAA==.Animlshiftr:BAABLgAECn8jAAIHAAgJrg24GABKAQAHAAgJrg24GABKAQAAAA==.Anzu:BAAALgAECgkJAQAAAA==.',
Ap='Apollo:BAABLgAECn84AAIQAAkJMAzfCAARAQAQAAkJMAzfCAARAQAAAA==.',
Ar='Aradunn:BAACLgAFFH8cAAIFAAUJ5CT9DAAKAgAFAAUJ5CT9DAAKAgAuAAQKfyYABAUACQk3IvsGAAQDAAUACQk3IvsGAAQDABEAAwkkHVpQAPYAABIAAgmeI8UzAGEAAAAA.Araedis:BAABLgAECn89AAIIAAkJ/xAuFAADAgAIAAkJ/xAuFAADAgAAAA==.Araelle:BAAALgAECgEJAQAAAA==.Archangel:BAAALgAECgYJCwAAAA==.Arrill:BAEALgAECgMJAwABLgAECggJGwADAP0JAA==.Artheren:BAAALgAECgQJBgAAAA==.Aryllyn:BAAALgADCgcJFAAAAA==.',
As='Ashvehtta:BAABLgAECn8dAAITAAkJDg2/WAC7AQATAAkJDg2/WAC7AQAAAA==.Assaelysia:BAAALgAECgIJAgAAAA==.Asstormrage:BAAALgADCgUJBQAAAA==.Asti:BAAALgAECgcJDgAAAA==.Astralon:BAAALgAECgIJAwAAAA==.',
At='Atharion:BAABLgAECn8mAAMUAAkJch0nEACXAgAUAAgJpR4nEACXAgAEAAYJjhY1tAAZAQAAAA==.Atheus:BAAALgADCgEJAgAAAA==.',
Au='Audio:BAAALgAECgYJBgABLgAECggJKgALAMgOAA==.',
Av='Avanda:BAAALgAECgEJBQAAAA==.Avaria:BAAALgAECgIJAgAAAA==.Avrassa:BAAALgADCgMJAwAAAA==.',
Aw='Awperprime:BAABLgAECn8tAAISAAkJ/Rd3CAA9AgASAAkJ/Rd3CAA9AgAAAA==.',
Ay='Ayhanui:BAAALgAECgEJAgAAAA==.',
Az='Azrathalos:BAABLgAECn8eAAQUAAcJLBTiNwBuAQAUAAYJuhPiNwBuAQAEAAUJEAUcHwGUAAAVAAEJkwM5VgAkAAAAAA==.Azémstraza:BAAALgAECgYJDAAAAA==.',
Ba='Bained:BAAALgADCgcJBwAAAA==.Baldric:BAABLgAECn8xAAIKAAgJ2x25KAA8AgAKAAgJ2x25KAA8AgAAAA==.Balinor:BAABLgAECn8dAAIUAAcJLQ7aPABTAQAUAAcJLQ7aPABTAQABLgAECgkJMgADAJ4dAA==.Bank:BAAALgADCgcJBwAAAA==.',
Be='Bearett:BAABLgAECn9YAAIWAAkJlCNnAAAGAwAWAAkJlCNnAAAGAwAAAA==.Beefcakezear:BAAALgADCgQJBAAAAA==.Belyfrost:BAACLgAFFH8IAAIGAAMJUAcPjADBAAAGAAMJUAcPjADBAAAuAAQKfxQAAgYACQmFDH9+AHsBAAYACQmFDH9+AHsBAAAA.Belylight:BAAALgAECgkJEAABLgAECgkJFAAXAA4SAA==.Belymoon:BAABLgAECn8UAAIXAAgJDhJVLgBoAQAXAAgJDhJVLgBoAQAAAA==.Belyreaper:BAAALgAECgcJCwABLgAECgkJFAAXAA4SAA==.Bennz:BAAALgAECgYJBgAAAA==.Beriotyr:BAAALgADCgQJAwAAAA==.Bernd:BAABLgAECn8nAAIWAAkJ6Qv5JQAkAQAWAAkJ6Qv5JQAkAQAAAA==.Beörn:BAABLgAECn8zAAIYAAkJkyP8AgCZAwAYAAkJkyP8AgCZAwAAAA==.',
Bi='Biggiy:BAAALgAECgEJAQAAAA==.Biglight:BAAALgAECgEJAQAAAA==.Bigsniffy:BAAALgADCgQJBAAAAA==.Birgir:BAAALgAECgUJBQAAAA==.',
Bl='Blackbeard:BAAALgAECgEJAQABLgAECgkJMgADAJ4dAA==.Blackgrinn:BAABLgAECn8lAAMCAAkJ3g27KACNAQACAAgJJw+7KACNAQAZAAgJJAeySQDpAAAAAA==.Blackkgrin:BAAALgADCgQJCgAAAA==.Blasphemous:BAABLgAECn8dAAITAAcJgBQ8jABMAQATAAcJgBQ8jABMAQAAAA==.Blasé:BAABLgAECn8yAAQQAAgJESAVIgBZAgAQAAgJESAVIgBZAgAaAAEJAACjXABZAAAbAAEJghI/OgBAAAABLgAFFAMJBAAcAAAAAA==.Blazéoné:BAAALgAECgUJBgAAAA==.Blessin:BAAALgAECgcJCgAAAA==.',
Bo='Boberto:BAEALgAECgUJBgABLgAFFAgJKAAdAMMPAA==.Bobo:BAAALgAECgUJEQAAAA==.Bobrossx:BAACLgAFFH8FAAMeAAIJ7xKHHQCgAAAeAAIJ7xKHHQCgAAAKAAIJNQhukQB8AAAuAAQKfywABB4ACAmZIZcNANgCAB4ACAkUHpcNANgCAAgABwnXHVUdALEBAAoAAgl9HlHkAIYAAAAA.Bobsmonk:BAAALgADCgEJAQAAAA==.Bomi:BAAALgADCgQJBAAAAA==.Boostéd:BAABLgAECn8XAAITAAcJdR3VSAAZAgATAAcJdR3VSAAZAgAAAA==.Boostëd:BAAALgAECgYJBwABLgAECgcJFwATAHUdAA==.Bowyoncè:BAAALgAFFAMJAwAAAA==.',
Br='Brakevilt:BAAALgAECgcJBwAAAA==.Brattyone:BAAALgADCgcJBwAAAA==.Breadcrums:BAAALgADCgMJAwAAAA==.Brewagool:BAAALgAECgMJAwAAAA==.Bruche:BAABLgAECn8vAAITAAkJLh+PHwCLAgATAAkJLh+PHwCLAgAAAA==.Brujaah:BAAALgAECgYJBgABLgAECgkJOgAcAAAAAQ==.Brynhilldr:BAAALgAECgEJAQAAAA==.Brynthadia:BAAALgAECgYJCAAAAA==.Brzrker:BAAALgADCgYJDAAAAA==.',
Bu='Bubagumps:BAAALgAECgEJAQAAAA==.Burkaeus:BAAALgAECgEJAQAAAA==.',
Bw='Bwca:BAACLgAFFH8HAAIKAAMJ9A6caQDSAAAKAAMJ9A6caQDSAAAuAAQKfxQAAgoABQkjHH9iAIEBAAoABQkjHH9iAIEBAAEuAAUUAwkRAAUAHAkA.',
Ca='Caine:BAABLgAECn8yAAIDAAkJnh28CwAxAgADAAkJnh28CwAxAgAAAA==.Cakébob:BAAALgADCgQJBQAAAA==.Calmdown:BAAALgADCgYJBwAAAA==.Carraa:BAAALgADCgYJCgABLgAECgkJLwAFAFsNAA==.Casey:BAABLgAECn8wAAIEAAkJcwaMvQAMAQAEAAkJcwaMvQAMAQAAAA==.Castyblasty:BAAALgAECgEJAQAAAA==.Cataaria:BAABLgAECn8vAAMFAAkJWw2HCQAVAQAFAAkJWw2HCQAVAQARAAEJ3QUmHwAPAAAAAA==.',
Ce='Cellina:BAABLgAECn8oAAMfAAkJTBEqKQByAQAfAAkJTBEqKQByAQABAAYJHwa/UwC2AAAAAA==.Cerathal:BAAALgADCgIJAgAAAA==.Ceriumz:BAAALgAECgYJCwABLgAFFAMJCAADACYVAA==.',
Cf='Cfourtylock:BAACLgAFFH8FAAMbAAMJKQ+FCgDTAAAbAAMJDA+FCgDTAAAQAAEJ0AtyTQBGAAAuAAQKfygABBAACQl8F2JRAKcBABAACAmtFWJRAKcBABsABglxFSURABsBABoAAQnvBU55ACoAAAAA.',
Ch='Chaniqua:BAAALgADCgQJBQAAAA==.Chiman:BAABLgAECn8VAAMgAAYJihHfSwA9AQAgAAYJihHfSwA9AQAfAAUJZgvWVwCwAAAAAA==.Chronophage:BAAALgAECgUJBQAAAA==.Chûd:BAEALgAECgUJBQAAAA==.',
Ci='Ciders:BAAALgAECgEJAQABLgAECgkJIgAIABoWAA==.',
Cl='Clasastrasza:BAAALgAECgUJCgABLgAFFAQJEgAYAMsaAA==.Classá:BAACLgAFFH8SAAMYAAQJyxqnIwA8AQAYAAQJyxqnIwA8AQAXAAQJQBzmDADqAAAuAAQKf0wABBcACQlPJMkHANoCABcACQlPJMkHANoCABgABwmhIMlGAIcBABYAAQmYFxtsAD4AAAAA.Clawz:BAABLgAFFH8GAAIHAAIJih2TEQCuAAAHAAIJih2TEQCuAAABLgAFFAMJCwAEAD0eAA==.',
Co='Codedd:BAACLgAFFH8GAAIYAAIJYwbEXgBeAAAYAAIJYwbEXgBeAAAuAAQKfxoAAhgABwl5EJBPAFEBABgABwl5EJBPAFEBAAAA.Commit:BAAALgAECggJDgAAAA==.Comradeprime:BAAALgAECgUJDwAAAA==.Corlys:BAABLgAECn8sAAMEAAkJDCLtFwCzAgAEAAkJ/yDtFwCzAgAVAAYJgB1eEgChAQABLgAFFAMJBwAGAJEFAA==.Covi:BAAALgAECgEJAQAAAA==.',
Cr='Crafted:BAAALgAECgEJAQABLgAECgkJFAARAJYYAA==.Crismonguard:BAAALgAECgcJBwAAAA==.Crispìn:BAABLgAECn8WAAIKAAcJswZAqwDsAAAKAAcJswZAqwDsAAAAAA==.Crossbones:BAAALgAECgQJDQAAAA==.Crue:BAABLgAECn8tAAIYAAgJcRG6AwB8AQAYAAgJcRG6AwB8AQAAAA==.',
Cu='Curthar:BAACLgAFFH8LAAIEAAMJPR6RLgCcAAAEAAMJPR6RLgCcAAAuAAQKfyAAAxUACQkUJfkAAFMDABUACQkUJfkAAFMDAAQABgmgHkR9AHQBAAAA.',
Cy='Cyguy:BAAALgAECgEJAQAAAA==.Cynboom:BAAALgAECgkJAQAAAA==.Cyndee:BAABLgAECn9JAAIJAAkJ3hhpFABNAgAJAAkJ3hhpFABNAgAAAA==.Cynnafrost:BAAALgAECgQJBgAAAA==.Cytenk:BAAALgADCgkJDwAAAA==.',
Da='Dadda:BAABLgAECn9TAAIeAAkJniHfAQDtAgAeAAkJniHfAQDtAgAAAA==.Daffnee:BAAALgADCgYJBwAAAA==.Daisynukes:BAAALgAECggJDQABLgAECgkJIwARABEQAA==.Dallas:BAAALgADCgcJBwAAAA==.Damascus:BAAALgAECgYJCwABLgAECggJMQAKANsdAA==.Dankmonk:BAABLgAECn82AAIBAAkJ9xX8GwDFAQABAAkJ9xX8GwDFAQAAAA==.Darcnis:BAAALgADCgkJGwAAAA==.Darielea:BAAALgADCgIJAgAAAA==.Darkfury:BAABLgAECn85AAIOAAkJrwmrZgBZAQAOAAkJrwmrZgBZAQAAAA==.Darkfüry:BAAALgADCgkJCQAAAA==.Darklasminth:BAAALgAFFAIJAgAAAA==.Darkschi:BAAALgAECgQJCQAAAA==.Darthwang:BAABLgAECn8fAAIQAAYJ6BjsWgC3AQAQAAYJ6BjsWgC3AQAAAA==.Darthwing:BAAALgAECgMJAwABLgAECgYJHwAQAOgYAA==.Dartos:BAACLgAFFH8KAAITAAIJbiMdrgDFAAATAAIJbiMdrgDFAAAuAAQKf1IAAhMACQl6JTIDAGwDABMACQl6JTIDAGwDAAAA.',
De='Deadlysmash:BAAALgADCgMJAwAAAA==.Deathratio:BAAALgADCgcJBwAAAA==.Deathsbff:BAAALgADCgEJAQABLgAFFAgJGQAGAHMUAA==.Deathsend:BAAALgAECggJCAAAAA==.Debluddk:BAABLgAECn8tAAIdAAkJIyFBBADyAgAdAAkJIyFBBADyAgABLgAFFAMJBQALABAMAA==.Deep:BAAALgAECgcJCQABLgAECgkJJQAgALMgAA==.Deepfister:BAABLgAECn8lAAIgAAkJsyCOCAASAwAgAAkJsyCOCAASAwAAAA==.Deeplydivine:BAAALgAECgIJAgABLgAECgkJJQAgALMgAA==.Demenic:BAAALgAECgkJAQAAAA==.Demone:BAAALgADCgMJAwAAAA==.',
Di='Dic:BAAALgAECgcJCgAAAA==.Dillpickle:BAAALgADCgcJBwAAAA==.Diluvium:BAABLgAECn8oAAIEAAkJNRJrVgDIAQAEAAkJNRJrVgDIAQAAAA==.Discodank:BAAALgAECgMJBAAAAA==.',
Dj='Djpleasant:BAACLgAFFH8ZAAIGAAYJ5g7bXwAhAQAGAAYJ5g7bXwAhAQAuAAQKfzgAAgYACQn+Hu8fAJ8CAAYACQn+Hu8fAJ8CAAAA.',
Dk='Dktelmtwo:BAABLgAECn8lAAIdAAkJgh4CBwCtAgAdAAkJgh4CBwCtAgAAAA==.',
Do='Doneisha:BAAALgAECgQJCQAAAA==.Dontcare:BAABLgAFFH8RAAMIAAYJVRdmAwBKAQAIAAYJiRRmAwBKAQAKAAQJ5BMDbADMAAAAAA==.Downhammer:BAAALgAECgkJBQAAAA==.',
Dr='Dractelm:BAAALgADCgEJAQABLgAECgcJJAAEABcbAA==.Drakamar:BAABLgAECn88AAQMAAkJYgOvFQC4AAALAAkJkgI+XwC8AAAMAAgJGgOvFQC4AAANAAYJMAIFLgB6AAAAAA==.Dranith:BAAALgAECgQJBAAAAA==.Dronos:BAACLgAFFH8RAAIXAAMJ+heyDgDMAAAXAAMJ+heyDgDMAAAuAAQKf0AAAhcACQkvJFsCAFADABcACQkvJFsCAFADAAAA.Drunkentank:BAAALgAECgEJAQAAAA==.',
Du='Dunzledorf:BAAALgAECgcJBwAAAA==.',
Dy='Dynammes:BAABLgAECn8jAAIGAAgJxhg1SgD8AQAGAAgJxhg1SgD8AQABLgAFFAQJCgAJABMgAA==.',
Ea='Eaglej:BAAALgAECgkJCAAAAA==.Eatmorpizza:BAAALgAECgYJEgAAAA==.',
Eb='Ebore:BAAALgADCggJDQAAAA==.',
Ee='Eegorn:BAAALgAECgYJCgAAAA==.Eegroll:BAACLgAFFH8WAAIBAAYJ+hvcEgCNAQABAAYJ+hvcEgCNAQAuAAQKfxgAAwEACAmlHKkeALEBAB8ABwkpF+kjALcBAAEABQm9H6keALEBAAAA.',
Eg='Egraw:BAAALgAECgQJBAAAAA==.',
El='Elementals:BAABLgAECn8UAAIRAAYJlhiSNgBfAQARAAYJlhiSNgBfAQAAAA==.Elixera:BAAALgAECgEJAQAAAA==.Elsä:BAAALgAECgUJAQAAAA==.Elémental:BAABLgAECn8dAAIRAAkJnhACBABdAQARAAkJnhACBABdAQAAAA==.',
Em='Emilwhaury:BAABLgAECn8XAAMEAAYJpg81EAD1AAAEAAYJpg81EAD1AAAUAAUJigTKbQB/AAAAAA==.',
Ep='Epia:BAABLgAECn8lAAMfAAgJyw++MQA/AQAfAAgJwQ2+MQA/AQABAAMJUBN1VQCxAAAAAA==.',
Er='Eriena:BAAALgAECgYJEQAAAA==.',
Es='Esbjorn:BAAALgAECgEJAgAAAA==.Essaila:BAABLgAECn9BAAIHAAkJihEBDwDFAQAHAAkJihEBDwDFAQAAAA==.',
Et='Etheo:BAAALgAECgEJAQAAAA==.Etherwalker:BAABLgAECn8mAAMJAAkJPyRGDAClAgAJAAgJTyRGDAClAgAhAAQJix9MKQAoAQAAAA==.',
Ev='Evocati:BAACLgAFFH8HAAITAAMJjxgejQDwAAATAAMJjxgejQDwAAAuAAQKfxgAAyIABgnbF8ETAEABACIABgneFcETAEABABMABgkZF5WsABkBAAEuAAUUBwkUAAQA/xcA.Evoka:BAACLgAFFH8FAAILAAMJEAwCIQBtAAALAAMJEAwCIQBtAAAuAAQKfyUAAwwACAmNHvIMAAwCAAwABwlXH/IMAAwCAAsABglZG5IyAGoBAAAA.',
Ex='Excision:BAABLgAECn8qAAMLAAgJyA4QRwAOAQAMAAcJcw2yHgA5AQALAAcJIQ0QRwAOAQAAAA==.Exmachina:BAAALgADCgYJBgAAAA==.',
Fa='Fahbio:BAABLgAECn8jAAIVAAgJcQJCLwCrAAAVAAgJcQJCLwCrAAAAAA==.Fataliny:BAAALgADCgUJCAAAAA==.Fatallock:BAACLgAFFH8HAAIQAAMJ9wQWjACtAAAQAAMJ9wQWjACtAAAuAAQKf0cAAxAACQn5FCI6APIBABAACQn5FCI6APIBABsAAQlpCLw/ADMAAAAA.Fatlife:BAAALgAECgMJAwAAAA==.',
Fi='Fishdish:BAAALgAECgIJAgAAAA==.Fistsmither:BAAALgAECgYJCQABLgAECgkJJAAjAPwTAA==.Fivevolts:BAABLgAECn8pAAIkAAkJDCTpAAAsAwAkAAkJDCTpAAAsAwAAAA==.',
Fl='Fladon:BAAALgADCgEJAQAAAA==.Flailuid:BAAALgAECgQJDgAAAA==.Flimfam:BAAALgAECgEJAQAAAA==.',
Fo='Foghorn:BAAALgADCgMJAwAAAA==.Forkin:BAAALgADCgIJAgAAAA==.Forthstryke:BAAALgAECgIJCAAAAA==.Four:BAAALgADCgUJBQAAAA==.Fozzi:BAAALgAECgYJCwAAAA==.',
Fr='Freddyg:BAAALgADCgMJBAAAAA==.Fridaychill:BAACLgAFFH8QAAIfAAUJUh4XDgBOAQAfAAUJUh4XDgBOAQAuAAQKfzQAAh8ACAm5ImgLAI0CAB8ACAm5ImgLAI0CAAAA.Fries:BAEALgAECgEJAQABLgAFFAUJCwASAE0fAA==.Frostdeeps:BAAALgAECgcJEwAAAA==.Frozarke:BAABLgAECn8wAAILAAkJPxKLNgBVAQALAAkJPxKLNgBVAQAAAA==.',
Fu='Fudd:BAABLgAECn8pAAIKAAkJHRr1HQByAgAKAAkJHRr1HQByAgAAAA==.Funk:BAAALgAECgIJBgABLgAECgYJEAAcAAAAAA==.Fupa:BAABLgAECn8tAAIKAAkJtQxeZgB3AQAKAAkJtQxeZgB3AQAAAA==.',
Ga='Gaiaslieg:BAAALgAECgEJAQAAAA==.Galand:BAAALgAECgYJBgAAAA==.Galathynius:BAAALgADCgUJBQAAAA==.Galeine:BAAALgADCgMJAwAAAA==.Gambitya:BAAALgAECgEJAQAAAA==.Gangplank:BAAALgADCgMJAwAAAA==.Garres:BAABLgAECn8gAAMHAAcJtiC1DADrAQAHAAcJtiC1DADrAQAWAAEJXQoPGgAgAAAAAA==.',
Ge='Genius:BAABLgAECn8bAAIhAAcJUBs2GACZAQAhAAcJUBs2GACZAQAAAA==.Gennosuke:BAAALgADCgcJBQAAAA==.',
Gh='Gherkin:BAAALgADCgEJAQAAAA==.Ghostkillaz:BAAALgADCgkJFwAAAA==.Ghostxkillaz:BAAALgADCgMJAwAAAA==.',
Gi='Gibley:BAABLgAECn8XAAIEAAgJ0BjlfgB8AQAEAAgJ0BjlfgB8AQAAAA==.',
Gl='Gladorf:BAAALgADCgYJBgAAAA==.',
Gn='Gnazgul:BAABLgAECn8XAAITAAkJLQ5/EADYAAATAAkJLQ5/EADYAAAAAA==.Gnomad:BAABLgAECn8lAAIGAAcJwwPI4QDYAAAGAAcJwwPI4QDYAAAAAA==.Gnomie:BAAALgAFFAEJBAAAAA==.Gnomio:BAAALgAFFAEJBAAAAA==.',
Go='Goat:BAAALgAECgYJDwAAAA==.Gouge:BAAALgAECgkJOgAAAQ==.',
Gr='Gravess:BAAALgAFFAIJAgAAAA==.Griffynshu:BAABLgAECn8pAAIYAAkJlBvVEwCtAgAYAAkJlBvVEwCtAgAAAA==.Griz:BAAALgAECgcJEgAAAA==.Grizzlyburr:BAABLgAECn8UAAIWAAcJjxJKJAAuAQAWAAcJjxJKJAAuAQABLgAFFAYJDQAFAM4YAA==.Grunewald:BAABLgAECn9nAAIKAAkJxw+YQQDdAQAKAAkJxw+YQQDdAQAAAA==.',
Gu='Guinn:BAAALgADCgIJAgABLgAECgkJMAALAD8SAA==.Gula:BAABLgAECn8hAAMbAAkJPxU/CQCxAQAbAAYJHRc/CQCxAQAQAAkJKBS+UwChAQAAAA==.Guldanshower:BAAALgADCgUJBQAAAA==.Gunhild:BAAALgAECgIJAgAAAA==.Gutdiver:BAAALgADCgUJBQAAAA==.',
Ha='Handiboyswag:BAACLgAFFH8lAAICAAYJvyDpBAAWAgACAAYJvyDpBAAWAgAuAAQKfxkAAxkABwm4E5QgANQBABkABwm4E5QgANQBAAIABAnJIhYwAB8BAAAA.Hando:BAAALgAECgYJCAAAAA==.Hattock:BAAALgADCgcJFQAAAA==.Hayate:BAAALgAECgUJBQAAAA==.',
He='Heathen:BAAALgAECgEJAgAAAA==.Heavyshlump:BAACLgAFFH8IAAIBAAQJ0Q5uKgD/AAABAAQJ0Q5uKgD/AAAuAAQKfyIAAgEACQl0FlgSACICAAEACQl0FlgSACICAAEuAAUUBgkNAAUAzhgA.Hehateme:BAAALgAECgIJAgAAAA==.Hehexd:BAABLgAECn8pAAIjAAgJARvUEwB3AgAjAAgJARvUEwB3AgAAAA==.Heimdall:BAACLgAFFH8IAAIUAAMJgw3GMQCsAAAUAAMJgw3GMQCsAAAuAAQKfyIAAhQACAmOH8gMAMMCABQACAmOH8gMAMMCAAAA.Hellavva:BAAALgAECgMJAwAAAA==.Hellzwar:BAAALgADCgUJBgAAAA==.Hench:BAAALgAECgYJBgAAAA==.Henchling:BAABLgAECn9OAAMFAAkJ5SKhAABDAwAFAAkJ5SKhAABDAwARAAkJaRJrJQC+AQAAAA==.Henchragon:BAAALgADCgUJBQAAAA==.',
Hi='Hissteria:BAAALgAECgIJAwAAAA==.',
Hn='Hngyhngyloko:BAABLgAECn8ZAAIGAAcJzxt5bQD6AQAGAAcJzxt5bQD6AQABLgAFFAMJCAALAOYUAA==.',
Ho='Hoerified:BAAALgADCgEJAQAAAA==.Holexios:BAAALgAECgQJCQABLgAECgYJFQAgAIoRAA==.Holybonks:BAAALgADCgcJBwAAAA==.Holycanoli:BAAALgAECgEJAgAAAA==.Holycrusade:BAAALgAECgUJCgAAAA==.Horine:BAABLgAECn8rAAIKAAgJEw9dXwCJAQAKAAgJEw9dXwCJAQAAAA==.Hotsteve:BAAALgAECgQJBwAAAA==.',
Hu='Huntrix:BAAALgAECgIJAgAAAA==.Huntër:BAAALgAECgQJBQAAAA==.Huruk:BAAALgAECgIJAgAAAA==.',
Hy='Hydranis:BAAALgADCgUJBQAAAA==.',
Ic='Icieblade:BAAALgAECgkJEQAAAA==.Icyscorcher:BAABLgAECn8kAAMGAAgJihTIXQDFAQAGAAgJihTIXQDFAQAlAAMJpwOyCwB3AAABLgAFFAMJCAADACYVAA==.',
Id='Idroptotems:BAAALgADCgMJAwABLgAECgcJJAAEABcbAA==.',
Ik='Ikairi:BAAALgAECgEJAQAAAA==.',
Il='Illidankness:BAAALgAECgQJBAAAAA==.Illidoran:BAAALgAECgYJDQABLgAFFAQJFwAGAPccAA==.',
Im='Imdatank:BAAALgADCgYJCAABLgAECggJHwAEAKQSAA==.Immeira:BAABLgAECn8iAAIFAAkJGhG/UABvAQAFAAkJGhG/UABvAQAAAA==.Immkicky:BAAALgADCgEJAQAAAA==.',
In='Intense:BAAALgAECgcJAwAAAA==.',
Ir='Ironmonger:BAAALgADCggJDQABLgAECgkJPQAjAI8dAA==.',
Ja='Jackcsi:BAAALgAECggJCgABLgAFFAMJEAAYAHseAA==.Jackheals:BAACLgAFFH8QAAIYAAMJex62KwAIAQAYAAMJex62KwAIAQAuAAQKfzUAAxgACAnLIh0KABoDABgACAnLIh0KABoDABcAAQnZAdqPABsAAAAA.Jackiix:BAAALgADCgcJBwAAAA==.Jacktides:BAAALgAFFAIJAgABLgAFFAMJEAAYAHseAA==.Jaehaerys:BAAALgAECgQJCAABLgAFFAMJBwAGAJEFAA==.Jagseer:BAAALgAECgQJBAABLgAECgkJMAACAPUcAA==.Jalthere:BAEALgADCgkJCQABLgAECgkJRAABANoRAA==.',
Jb='Jblackly:BAAALgAECgYJCQAAAA==.',
Jc='Jcdhizzle:BAAALgAECgEJAQAAAA==.',
Jf='Jfreeman:BAAALgADCgYJBwAAAA==.',
Ji='Jimzdrood:BAAALgAECgEJAQAAAA==.Jinbeyblade:BAAALgAECgMJAwABLgAFFAMJEAAKAG0iAA==.Jinphoenix:BAACLgAFFH8QAAIKAAMJbSJYRAAlAQAKAAMJbSJYRAAlAQAuAAQKfycAAwoACQlrIT4NAOgCAAoACQlrIT4NAOgCAB4ABAmQB4xfAMMAAAAA.Jitb:BAAALgADCgYJBwABLgAFFAcJFQAgAMEOAA==.',
Jo='Jobin:BAACLgAFFH8PAAMTAAMJ4BI0qADMAAATAAMJ4BI0qADMAAAiAAEJSAECLgAwAAAuAAQKfxkAAhMACAn5G0twAKgBABMACAn5G0twAKgBAAAA.Joldada:BAAALgAECgkJCAAAAA==.Journei:BAACLgAFFH8GAAIFAAIJTBSGJACGAAAFAAIJTBSGJACGAAAuAAQKfz8AAgUACQlYFmEDAOsBAAUACQlYFmEDAOsBAAAA.',
Ju='Juanito:BAAALgAECgYJCAAAAA==.Judging:BAABLgAECn8tAAMUAAkJDRc/GABGAgAUAAkJDRc/GABGAgAEAAIJHSWM8wDGAAAAAA==.Junkhead:BAAALgAECgUJCAAAAA==.',
Ka='Kaethe:BAAALgAECgYJBgAAAA==.Kaiduo:BAAALgADCgEJAQAAAA==.Kaitos:BAAALgAFFAIJBAABLgAFFAMJCwAEAD0eAA==.Kaleus:BAAALgAECgQJBwAAAA==.Kalmas:BAABLgAFFH8MAAIXAAMJHAj0NgCiAAAXAAMJHAj0NgCiAAAAAA==.Kateana:BAAALgAECgcJEwAAAA==.',
Ke='Kegz:BAAALgAECgcJDAABLgAECgkJMAACAPUcAA==.Kelendrian:BAAALgAECgUJBQAAAA==.Kellayna:BAABLgAECn8xAAIEAAkJIQkjFwC4AAAEAAkJIQkjFwC4AAAAAA==.Kennyx:BAAALgAECgMJAwAAAA==.Kerine:BAAALgAECgMJBAAAAA==.Ketchup:BAAALgADCgIJAwAAAA==.Keylö:BAAALgAFFAEJAgAAAA==.Kezix:BAABLgAECn8eAAIQAAkJlA41UwCiAQAQAAkJlA41UwCiAQAAAA==.',
Kh='Kharigosa:BAAALgAECgEJAQABLgAECggJFgAUAH8ZAA==.Khronic:BAAALgADCgMJAwABLgAECggJKgALAMgOAA==.',
Ki='Kigerstorm:BAAALgADCgEJAQAAAA==.Kimeltoe:BAAALgADCgIJAgAAAA==.Kimigosa:BAABLgAECn8nAAQLAAgJfhGoIwChAQALAAgJvA+oIwChAQAMAAIJ7gt4JgAyAAANAAEJwQF4TgAiAAABLgAFFAMJAwAcAAAAAA==.Kimpachi:BAAALgAECgcJCAABLgAFFAMJAwAcAAAAAA==.',
Kl='Klerik:BAACLgAFFH8WAAIQAAYJoBL4UgAgAQAQAAYJoBL4UgAgAQAuAAQKfykABBAACQkaH5wfAGcCABAACQmyHZwfAGcCABoAAgkpEmxMAIgAABsAAQlxJE41AE4AAAAA.',
Kn='Kníghtmare:BAAALgAECgYJDwAAAA==.',
Ko='Kolesnikov:BAAALgAECgUJCAAAAA==.Koragg:BAACLgAFFH8xAAIdAAcJbyElCwDLAQAdAAcJbyElCwDLAQAuAAQKfz4AAh0ACQnwJbcCAB0DAB0ACQnwJbcCAB0DAAAA.Kore:BAABLgAECn8jAAIYAAYJZBaHSABtAQAYAAYJZBaHSABtAQAAAA==.Korrag:BAAALgAECgUJDAAAAA==.Kozarke:BAABLgAECn8tAAIMAAkJxBYwBQASAgAMAAkJxBYwBQASAgAAAA==.',
Kp='Kpop:BAABLgAECn8iAAMPAAkJ3Rn7BwD6AQAPAAkJ3Rn7BwD6AQAOAAEJ/hYJIgBDAAABLgAFFAYJDQAFAM4YAA==.',
Kr='Krissia:BAABLgAECn8iAAITAAkJhhiEUgDMAQATAAkJhhiEUgDMAQAAAA==.',
Ku='Kumadbear:BAAALgADCgEJAQAAAA==.',
Ky='Kyntaliia:BAAALgAECgQJBAAAAA==.',
['Kí']='Kítsuñe:BAAALgAECgMJAwAAAA==.',
['Kî']='Kîn:BAABLgAECn8oAAIOAAkJihSBNAD0AQAOAAkJihSBNAD0AQAAAA==.',
La='Ladriana:BAAALgADCgEJAgAAAA==.Laisera:BAABLgAECn8zAAMmAAkJmRAMJwCNAQAmAAkJmRAMJwCNAQAZAAEJdQaklAAmAAAAAA==.Lalipop:BAABLgAECn87AAImAAkJBRrkDQCIAgAmAAkJBRrkDQCIAgAAAA==.Landroval:BAABLgAECn8oAAILAAkJKRnTEQBVAgALAAkJKRnTEQBVAgAAAA==.Lauma:BAACLgAFFH8RAAIFAAMJHAkwLwBcAAAFAAMJHAkwLwBcAAAuAAQKfxUAAgUABwmwEqlMAH4BAAUABwmwEqlMAH4BAAAA.Lawson:BAABLgAECn87AAITAAkJUh1nIACHAgATAAkJUh1nIACHAgAAAA==.',
Le='Lelora:BAAALgAECgUJCQAAAA==.Lenthaden:BAABLgAECn87AAMQAAkJgRiqMQASAgAQAAkJVRaqMQASAgAaAAYJqxNeJQAyAQAAAA==.Lexusis:BAAALgADCgIJAgAAAA==.',
Li='Lightsmasher:BAAALgAECgEJAQAAAA==.Lihaeh:BAAALgADCgEJAQAAAA==.Lildipper:BAAALgAECgcJDQABLgAFFAYJDQAFAM4YAA==.Lio:BAABLgAECn8XAAITAAcJWgxTDgDuAAATAAcJWgxTDgDuAAAAAA==.Lissetteliz:BAAALgAECgQJBQAAAA==.Livdangerous:BAAALgADCgUJBQAAAA==.',
Lo='Locks:BAAALgAECgEJAQAAAA==.Lomax:BAAALgAECgEJAQAAAA==.Longlegs:BAAALgADCgYJBgAAAA==.',
Lu='Lumawig:BAAALgAECgUJDQAAAA==.Lumillras:BAAALgADCgYJCgAAAA==.Lunchdk:BAACLgAFFH8NAAMdAAMJOhebDgCAAAATAAIJJR7/zACVAAAdAAIJBwybDgCAAAAuAAQKfysAAxMACQmOH20WAMACABMACAl2I20WAMACAB0ACAlzF2gVALwBAAAA.',
Ly='Lyreth:BAABLgAECn8pAAIXAAkJJRCsJQCfAQAXAAkJJRCsJQCfAQAAAA==.',
Ma='Madax:BAACLgAFFH8KAAIJAAQJEyAWEQB9AQAJAAQJEyAWEQB9AQAuAAQKf0YAAwMACQm+Iz8DAAUDAAMACQnMIT8DAAUDAAkACQlnIS8LALQCAAAA.Mageymutt:BAACLgAFFH8ZAAIGAAgJcxRbDAC7AQAGAAgJcxRbDAC7AQAuAAQKfyUAAwYACAmNIKElANwCAAYACAmNIKElANwCACcAAwkmCx8UAIQAAAAA.Maggidabeast:BAABLgAECn8vAAIGAAgJKQiznABBAQAGAAgJKQiznABBAQAAAA==.Magnion:BAAALgAECgEJAQAAAA==.Maison:BAAALgAECgQJCQAAAA==.Malase:BAAALgADCgUJAwAAAA==.Malisx:BAAALgADCgEJAQAAAA==.Maloch:BAAALgADCgUJBQAAAA==.',
Me='Meaculpa:BAAALgADCgUJCgAAAA==.Megamilk:BAACLgAFFH8TAAIiAAUJaQ+MDwAcAQAiAAUJaQ+MDwAcAQAuAAQKf0IAAiIACQlJG2QGAEECACIACQlJG2QGAEECAAAA.Mekri:BAAALgADCgYJBwABLgAECgcJJAAEABcbAA==.Melledreaux:BAAALgADCgMJAwAAAA==.Metrolinea:BAACLgAFFH8iAAIGAAUJKB7rGgA1AQAGAAUJKB7rGgA1AQAuAAQKfzkAAgYACQkqH+sUANwCAAYACQkqH+sUANwCAAAA.',
Mi='Micalknight:BAAALgAECgIJAQAAAA==.Milliy:BAAALgAECgQJBwAAAA==.Minamel:BAAALgADCgMJAwABLgAECgcJJAAEABcbAA==.Minervá:BAAALgAECgMJAwABLgAFFAQJEgAYAMsaAA==.Missbehaving:BAABLgAECn8rAAMmAAkJnRDHMABKAQAmAAcJjRTHMABKAQAZAAkJNQZuPwATAQAAAA==.',
Mo='Monkdluffy:BAAALgADCgEJAQAAAA==.Morefire:BAAALgAECgQJCgABLgAECgkJFAARAJYYAA==.Morrk:BAAALgADCgIJAgAAAA==.Mosmos:BAAALgAECgQJBAAAAA==.',
Mu='Muddslinger:BAABLgAECn8bAAIJAAkJpQsxMgCDAQAJAAkJpQsxMgCDAQAAAA==.Mumra:BAABLgAECn9FAAQmAAgJgQtSMgBBAQAmAAgJgQtSMgBBAQACAAYJdgFaPwC0AAAZAAEJAAC3oAAAAAAAAA==.',
My='Mystblade:BAAALgAECggJEQAAAA==.Mystlord:BAAALgAECgQJBAAAAA==.',
Na='Nadatank:BAAALgADCgQJBAAAAA==.Nalesean:BAAALgAECggJEwAAAA==.Nanaki:BAABLgAECn8iAAINAAkJKyDzBgDQAgANAAkJKyDzBgDQAgAAAA==.Nannette:BAABLgAECn8UAAIEAAcJKQO/BwGvAAAEAAcJKQO/BwGvAAAAAA==.Nappe:BAAALgAECgEJAQABLgAECgkJHwAEAIElAA==.Narag:BAABLgAECn86AAIKAAkJtxqMHgBvAgAKAAkJtxqMHgBvAgAAAA==.Naturesgrace:BAAALgADCgIJAgAAAA==.Nazfu:BAAALgAECgEJAgAAAA==.Nazg:BAAALgADCgQJAgAAAA==.',
Ne='Needle:BAAALgAECgYJCQAAAA==.Nephorma:BAAALgADCgIJAgAAAA==.Nerfertari:BAAALgAECgEJBQAAAA==.Netanyahoo:BAAALgAFFAIJAgAAAA==.Neva:BAAALgAECgIJAgAAAA==.Newport:BAABLgAECn9AAAMFAAgJ9x/HEADJAgAFAAgJ9x/HEADJAgARAAIJmAgClABMAAAAAA==.',
Ni='Ninex:BAABLgAECn8cAAIUAAgJTR/RGABMAgAUAAgJTR/RGABMAgAAAA==.Ninisina:BAABLgAECn9EAAMFAAgJzh+0EgC3AgAFAAgJzh+0EgC3AgASAAEJ7wOHLgAsAAAAAA==.Nithén:BAAALgADCgYJDQAAAA==.',
No='Noghalote:BAAALgADCgQJBAAAAA==.Nonaleeta:BAAALgAECgQJCAAAAA==.Notafurry:BAAALgADCgcJCQAAAA==.Novaa:BAAALgAECgcJBgAAAA==.Nowhere:BAAALgAECgUJBQABLgAECgkJJAAjAPwTAA==.Nowon:BAABLgAECn8qAAMoAAgJOhZRHgCJAQAoAAgJOhZRHgCJAQAPAAEJpwhjPAAcAAAAAA==.',
Nu='Nudream:BAABLgAECn8iAAIUAAkJWASyPwBFAQAUAAkJWASyPwBFAQAAAA==.',
Ny='Nybors:BAAALgADCgcJCwAAAA==.',
['Nö']='Nörse:BAABLgAECn8aAAMXAAYJDhDzTADYAAAXAAYJCA/zTADYAAAHAAEJpBf0SQBGAAAAAA==.',
Ol='Olakua:BAAALgAECgMJAwAAAA==.Oldjerry:BAABLgAECn8kAAIjAAkJ/BM8EgAVAgAjAAkJ/BM8EgAVAgAAAA==.Oliaa:BAAALgADCgYJCAAAAA==.',
Oo='Oomdeath:BAAALgAECgYJBgAAAA==.',
Op='Opalyte:BAABLgAECn8qAAMmAAkJqAwSLQBjAQAmAAkJqAwSLQBjAQAZAAIJogQnfABGAAAAAA==.',
Or='Orichalcum:BAABLgAECn8oAAIgAAgJth6MDgC3AgAgAAgJth6MDgC3AgAAAA==.Orphiee:BAABLgAECn8wAAIKAAYJxQGk8ABwAAAKAAYJxQGk8ABwAAAAAA==.',
Os='Oslagsi:BAAALgADCgcJDgAAAA==.Osyriss:BAAALgADCgUJBgAAAA==.',
Ot='Othril:BAAALgAECgQJCAAAAA==.',
Ou='Outis:BAAALgAFFAMJBwABLgAFFAMJDQAcAAAAAQ==.',
Pa='Pacts:BAAALgAECgEJAQAAAA==.Pakoros:BAABLgAECn9KAAMFAAkJmR28DQDoAgAFAAkJmR28DQDoAgARAAQJBwp7agCZAAAAAA==.Palibuddy:BAAALgAECgMJAwAAAA==.Pallyfreak:BAAALgAECgYJDAAAAA==.Panzer:BAAALgADCgkJCQAAAA==.',
Pe='Peachy:BAAALgAECgQJBAABLgAECgkJLQAFADQXAA==.Penderin:BAABLgAECn8VAAIKAAgJnRjNEQDuAAAKAAgJnRjNEQDuAAABLgAECgkJPAAHAD4aAA==.Penilock:BAAALgADCgIJAgAAAA==.Pensham:BAAALgAECgEJAwABLgAECgkJPAAHAD4aAA==.Perlindree:BAABLgAECn9IAAIKAAkJHgqjDAAuAQAKAAkJHgqjDAAuAQAAAA==.',
Pg='Pgorlelgy:BAACLgAFFH8LAAIKAAMJdRSZWwDtAAAKAAMJdRSZWwDtAAAuAAQKfywAAgoACQn+FlIyABMCAAoACQn+FlIyABMCAAAA.',
Ph='Phira:BAAALgADCgEJAQAAAA==.Phoenix:BAAALgADCgIJAgAAAA==.Physgun:BAAALgADCgYJDgAAAA==.',
Pi='Pillows:BAAALgADCgYJBgAAAA==.',
Pl='Platious:BAABLgAECn83AAIEAAkJmRZRRgDzAQAEAAkJmRZRRgDzAQAAAA==.',
Po='Pony:BAAALgADCgUJBQABLgADCgUJCgAcAAAAAA==.Poodin:BAAALgADCgIJAgAAAA==.Pookaboo:BAABLgAECn8WAAIQAAgJNwIz1wCoAAAQAAgJNwIz1wCoAAAAAA==.Poppers:BAAALgADCgkJDgAAAA==.',
Pr='Preacharoùnd:BAACLgAFFH8aAAIZAAYJQRQZDwB2AQAZAAYJQRQZDwB2AQAuAAQKf1sAAhkACQk4Ig4EABwDABkACQk4Ig4EABwDAAEuAAUUBgkaABkAQRQA.Promir:BAAALgAECgcJDgAAAA==.',
Pu='Purdie:BAABLgAECn8ZAAIYAAkJpgwHRgB4AQAYAAkJpgwHRgB4AQABLgAECgkJLwAFAFsNAA==.Purdieturtle:BAAALgADCgkJDQAAAA==.',
['Pì']='Pìke:BAAALgAECgEJAQAAAA==.',
Qe='Qeesa:BAAALgAECgIJBAAAAA==.',
Qi='Qiryana:BAAALgADCgIJAgAAAA==.',
Ra='Raeliene:BAACLgAFFH8JAAIEAAMJjB88UQANAQAEAAMJjB88UQANAQAuAAQKfyQAAgQACQkoHXwjAHcCAAQACQkoHXwjAHcCAAAA.Rafikie:BAAALgAECgIJAwAAAA==.Ratchet:BAAALgADCgMJAwAAAA==.Rawmeat:BAABLgAECn8/AAICAAkJ0h3nCQDTAgACAAkJ0h3nCQDTAgAAAA==.Razillar:BAAALgAECgEJAQAAAA==.',
Re='Rebelpatriot:BAAALgADCgYJCQAAAA==.Redbearrd:BAAALgADCgkJCQABLgAFFAMJBwAGAJEFAA==.Relaxnerdlol:BAAALgAECgEJBAAAAA==.Reldwick:BAAALgADCgYJBwAAAA==.Renew:BAABLgAECn84AAMmAAkJHB5yCgDAAgAmAAkJHB5yCgDAAgAZAAkJNhcUFQAkAgAAAA==.Renix:BAACLgAFFH8SAAIRAAQJCRkYIgATAQARAAQJCRkYIgATAQAuAAQKfzIAAxEACQlmH/cNAIwCABEACQlmH/cNAIwCABIAAQl1CxYtADIAAAAA.Reno:BAAALgAECgMJAwAAAA==.Revery:BAAALgADCgIJAgAAAA==.',
Rh='Rhadgar:BAAALgADCgcJCQAAAA==.',
Ri='Ripmyname:BAAALgAECgYJBwAAAA==.Riverah:BAAALgAECgQJCAAAAA==.Rivulet:BAAALgAECgUJDAAAAA==.',
Ro='Roombaa:BAAALgADCgQJAgAAAA==.Royfenix:BAACLgAFFH8PAAMmAAMJOBAeKACEAAAmAAIJ5RQeKACEAAAZAAIJ8wMXNQBsAAAuAAQKfzYABCYABwnqG9cWABkCACYABwnqG9cWABkCABkABgk9ErdMANwAAAIAAwnhAihqAFkAAAEuAAUUBAkXAAYA9xwA.',
Ru='Rukaillin:BAAALgAECgYJBwAAAA==.',
Ry='Ryukaii:BAAALgAECgYJCAAAAA==.Ryyah:BAABLgAECn88AAMUAAgJjBh0GwAoAgAUAAgJjBh0GwAoAgAEAAQJLQPERwFlAAAAAA==.',
['Rè']='Rèck:BAAALgAECgUJCAAAAA==.',
['Ré']='Rébecca:BAAALgAECgMJAwABLgAFFAMJBgAdAKwNAA==.',
['Rì']='Rìsen:BAAALgADCgYJBgAAAA==.',
['Rú']='Rústy:BAAALgAFFAIJAwAAAA==.',
Sa='Sabris:BAAALgAECgQJBAAAAA==.Saetyl:BAABLgAECn8pAAIXAAkJrQTGCQCgAAAXAAkJrQTGCQCgAAAAAA==.Saga:BAAALgADCgEJAQAAAA==.Salvynus:BAAALgAECgUJBQAAAA==.Samhainn:BAAALgADCgIJAQABLgADCgYJBQAcAAAAAA==.Sanctity:BAAALgAECgMJAwAAAA==.Saphirè:BAAALgAECgUJAQAAAA==.',
Sc='Scrungle:BAAALgADCgYJCwAAAA==.',
Se='Seabiscuìt:BAAALgAECgIJAgAAAA==.Seanthaniel:BAEALgAFFAEJAQABLgAFFAgJKAAdAMMPAA==.Seifslam:BAAALgADCgQJBAABLgAECgEJAQAcAAAAAA==.Seifura:BAAALgAECgEJAQAAAA==.Semi:BAAALgAFFAEJAQABLgAFFAQJCgAUAEcbAA==.Semii:BAAALgAECgIJAgAAAA==.Serkerune:BAAALgAECgEJAgAAAA==.Serkesul:BAABLgAECn8sAAIZAAkJaSRmAwAqAwAZAAkJaSRmAwAqAwAAAA==.Sevinas:BAABLgAECn8tAAISAAkJ2w6vFABxAQASAAkJ2w6vFABxAQAAAA==.',
Sf='Sfogliatella:BAAALgAECgEJAQAAAA==.',
Sh='Shaftstop:BAAALgADCgkJCQABLgAECgUJBQAcAAAAAA==.Shamallamá:BAAALgADCgkJCgABLgAECgkJMAAKADciAA==.Shamthis:BAABLgAECn8jAAIRAAkJERClKgCdAQARAAkJERClKgCdAQAAAA==.Shamwoww:BAACLgAFFH8GAAIRAAMJURA6NgC1AAARAAMJURA6NgC1AAAuAAQKfycAAhEACAncHqYRAGMCABEACAncHqYRAGMCAAEuAAUUBgkaABkAQRQA.Shamyou:BAABLgAECn8UAAMFAAkJ1xnQGwA6AgAFAAkJ1xnQGwA6AgARAAYJKRoSOgBOAQAAAA==.Shealie:BAAALgADCgMJAwABLgAECgkJPQAjAI8dAA==.Shelly:BAAALgAECggJDwAAAA==.Shiftymynx:BAAALgADCgEJAQAAAA==.Shlumpa:BAACLgAFFH8NAAIFAAYJzhhCGQCdAQAFAAYJzhhCGQCdAQAuAAQKfx8AAgUACQlnGx4UAKsCAAUACQlnGx4UAKsCAAAA.Shlumpdragon:BAAALgAECgMJAwABLgAFFAYJDQAFAM4YAA==.Shlumpydk:BAABLgAFFH8HAAMdAAQJHAQFKwChAAAdAAQJDwQFKwChAAATAAEJoQHKJwEsAAAAAA==.Shokcz:BAAALgAECgQJBwAAAA==.Shomba:BAAALgAECgYJBgAAAA==.Shotsfired:BAAALgAECgYJCgAAAA==.Shámjackson:BAACLgAFFH8fAAIFAAcJyyXhAACPAgAFAAcJyyXhAACPAgAuAAQKfy4AAgUACQkMJjQDAEcDAAUACQkMJjQDAEcDAAAA.',
Si='Silvey:BAABLgAECn8sAAIOAAkJjiGTCgD1AgAOAAkJjiGTCgD1AgAAAA==.Sindoraan:BAAALgADCgEJAgAAAA==.Sindricil:BAAALgADCggJDAAAAA==.',
Sk='Skar:BAAALgADCggJCQAAAA==.Skeletorque:BAACLgAFFH8FAAMdAAIJ/AP9HwAgAAATAAIJRwIVAgFmAAAdAAEJJAb9HwAgAAAuAAQKfxcAAxMACQncEJ9qAJABABMACQncEJ9qAJABAB0AAQlcDadLAB8AAAAA.Skully:BAAALgAECgEJAQAAAA==.Skyylorne:BAABLgAECn8wAAIHAAcJ1xd5AQCQAQAHAAcJ1xd5AQCQAQAAAA==.',
Sl='Slipnslide:BAAALgAECgQJBQABLgAECgkJPwACANIdAA==.',
Sm='Smallwdruid:BAAALgAECgYJBgAAAA==.Smashlock:BAAALgADCgUJCAAAAA==.Smellydruid:BAAALgADCgEJAQAAAA==.Smitesword:BAAALgADCgYJDAAAAA==.',
Sn='Snow:BAAALgAECgYJBgABLgAECgkJIgANACsgAA==.Snowfawn:BAABLgAECn81AAIKAAkJKBwCAwBHAgAKAAkJKBwCAwBHAgABLgAECgkJFAAKAD8dAA==.Snusnurae:BAAALgAECgcJEgAAAA==.',
So='Sodapoppin:BAAALgADCgcJBwAAAA==.Solas:BAAALgADCgQJBQAAAA==.Somay:BAAALgAECgQJBwAAAA==.Soryn:BAAALgADCgUJBQAAAA==.Sovirus:BAAALgAECgQJBAABLgAECgkJIgANACsgAA==.',
Sp='Spanana:BAABLgAFFH8MAAITAAQJThK3FQBNAQATAAQJThK3FQBNAQAAAA==.Sparevolts:BAAALgAECgEJAQAAAA==.Specialist:BAAALgAFFAIJAwABLgAFFAYJEQAIAFUXAA==.Spicychopz:BAACLgAFFH8aAAIGAAkJmSHhCwCQAgAGAAkJmSHhCwCQAgAuAAQKfxcAAgYACAnbIRUdAAEDAAYACAnbIRUdAAEDAAAA.Spiketickevi:BAAALgAECggJCAAAAA==.Splishsplásh:BAABLgAECn8tAAIFAAkJNx8VEgC9AgAFAAkJNx8VEgC9AgAAAA==.Sprattyboii:BAAALgAFFAIJBAAAAA==.Sprucelock:BAAALgADCgIJAgAAAA==.',
Ss='Sscarlet:BAABLgAECn8pAAIGAAkJAQwcaACsAQAGAAkJAQwcaACsAQAAAA==.',
St='Staltis:BAAALgAECgkJEQABLgAECgkJMAALAD8SAA==.Starrling:BAABLgAECn8dAAIXAAgJqhhNAgC4AQAXAAgJqhhNAgC4AQAAAA==.Starzia:BAABLgAECn8yAAICAAkJgAebLgBmAQACAAkJgAebLgBmAQAAAA==.Stupidtree:BAACLgAFFH8XAAIYAAUJQx2CGACaAQAYAAUJQx2CGACaAQAuAAQKfxwAAhgABwnMI3IVAJ4CABgABwnMI3IVAJ4CAAAA.',
Su='Sudzyjr:BAAALgADCgUJBQAAAA==.Sunk:BAABLgAECn8tAAIQAAkJJRx0HgBuAgAQAAkJJRx0HgBuAgAAAA==.',
Sw='Swagg:BAAALgAECgEJAQAAAA==.Swanho:BAAALgAECgIJBQABLgAECgcJCQAcAAAAAA==.Swiftblossom:BAAALgAECgQJBwAAAA==.',
Sy='Sylvanex:BAABLgAECn8jAAIKAAgJhBo5QQDeAQAKAAgJhBo5QQDeAQAAAA==.',
['Sê']='Sêrënîty:BAAALgAFFAEJAwABLgAFFAcJEQAEAJERAA==.',
['Sô']='Sông:BAAALgAECgYJEgAAAA==.',
Ta='Taestra:BAAALgAECgMJAwAAAA==.Taffbones:BAAALgAECgYJCgAAAA==.Tahla:BAAALgADCgIJAgAAAA==.Talanot:BAAALgAECgUJCwABLgAECgYJFQAgAIoRAA==.Talarus:BAAALgAECggJEgAAAA==.Talurana:BAAALgAECgEJAgAAAA==.Tanadria:BAABLgAECn8kAAIjAAkJCwx3HACyAQAjAAkJCwx3HACyAQAAAA==.Tangerene:BAACLgAFFH8HAAICAAMJbAEOPACMAAACAAMJbAEOPACMAAAuAAQKfyIAAwIACQkUDFkzAEsBAAIACAlrDVkzAEsBACYABgkUAhteALoAAAAA.Tapioca:BAACLgAFFH8SAAIKAAQJ1iCzKgBeAQAKAAQJ1iCzKgBeAQAuAAQKfzoAAgoACQk0I9kGACkDAAoACQk0I9kGACkDAAAA.',
Tc='Tchort:BAAALgAECgQJBAABLgAFFAgJGQAGAHMUAA==.',
Te='Telemachus:BAAALgAECgEJAQAAAA==.Telm:BAABLgAECn8kAAMEAAcJFxuNbgCRAQAEAAcJcxmNbgCRAQAVAAcJShoVGABeAQAAAA==.Tentilious:BAAALgAECgUJCQAAAA==.',
Th='Thadeusputz:BAAALgAECgEJAQAAAA==.Thaÿne:BAABLgAECn8WAAIJAAkJiA4PLQCeAQAJAAkJiA4PLQCeAQAAAA==.Thebestpally:BAACLgAFFH8LAAMEAAMJtBOFeADEAAAEAAMJAg2FeADEAAAVAAEJkRZuFwA/AAAuAAQKf0cAAxUACQlgHMIFAJECABUACQlgHMIFAJECAAQABQmNDQXlAMQAAAAA.Thenemisis:BAAALgADCgcJDwAAAA==.Thiccidàn:BAAALgADCgEJAgAAAA==.Thormier:BAAALgADCgIJAgAAAA==.Thund:BAAALgAECgQJBwAAAA==.',
Ti='Tianielan:BAABLgAECn8aAAMUAAkJGh8NEwB4AgAUAAkJGh8NEwB4AgAEAAEJJQ59QgEzAAAAAA==.Tidds:BAABLgAECn9HAAMQAAkJzw/uBACAAQAQAAkJzw/uBACAAQAbAAcJRQi1HADZAAAAAA==.Tinyfloof:BAAALgADCgcJCwAAAA==.',
To='To:BAAALgAECggJEgAAAA==.Tobikins:BAAALgADCgIJAgAAAA==.Toolgunx:BAAALgAECgQJBQAAAA==.Totemdown:BAACLgAFFH8hAAIFAAgJLyP+AACEAgAFAAgJLyP+AACEAgAuAAQKfyMAAgUACQm1I6UGAEYDAAUACQm1I6UGAEYDAAAA.',
Tr='Tralth:BAAALgAECgIJAgAAAA==.Trazarath:BAACLgAFFH8YAAMLAAUJ1gv7NwDlAAALAAUJ1gv7NwDlAAAMAAIJSAawDwA+AAAuAAQKfysAAwsACQknFd4WAB8CAAsACQknFd4WAB8CAAwAAwkmBKczAHcAAAAA.Triage:BAAALgAECgEJAwAAAA==.Triggaman:BAAALgADCgYJCAABLgAECgcJJAAEABcbAA==.Trollner:BAAALgAECgEJAgAAAA==.Trunndle:BAAALgADCgUJBQAAAA==.',
Ts='Tsuul:BAAALgAECgQJCwAAAA==.',
Tu='Turbolover:BAAALgAECgEJAQAAAA==.',
Tw='Twirl:BAAALgADCgEJAQAAAA==.',
Ty='Tylenstus:BAAALgAECgEJAQAAAA==.',
['Tã']='Tãpioca:BAAALgAECgQJDQABLgAFFAQJEgAKANYgAA==.',
Uj='Ujio:BAABLgAECn8ZAAMUAAcJSRgMKgC+AQAUAAcJSRgMKgC+AQAEAAMJpwe4MgF8AAABLgAECgkJMAAFAN0YAA==.',
Ul='Ultravisitor:BAAALgADCgIJAgAAAA==.',
Un='Unholyferret:BAAALgADCgIJAgAAAA==.Unify:BAAALgADCgMJBAAAAA==.Untiler:BAAALgADCgUJBQAAAA==.',
Us='Usdaprime:BAAALgAECgIJAwABLgAFFAIJBQAdAPwDAA==.Usopp:BAAALgADCgYJBgAAAA==.',
Uu='Uuyd:BAAALgAFFAMJDQAAAQ==.',
Va='Vaden:BAAALgAECgIJAgABLgAECgkJIgAIABoWAA==.Vaelthys:BAABLgAECn8eAAIZAAkJ8hgSDwBoAgAZAAkJ8hgSDwBoAgABLgAFFAMJBQAbACkPAA==.Valedarrin:BAAALgADCgEJAQAAAA==.Valefyre:BAAALgADCgcJBwAAAA==.Valenstrasz:BAACLgAFFH8FAAMMAAIJ2gewCgB5AAAMAAIJlQawCgB5AAALAAIJtQYfWABtAAAuAAQKfyIAAwsACQmGEjIfAMkBAAsACAkSEzIfAMkBAAwABAn6DncZAIkAAAEuAAUUBAkKAAkAEyAA.Valetherin:BAAALgADCgkJCQAAAA==.Valkaron:BAAALgADCgYJBgABLgAFFAYJGgAEAIwZAA==.Vanaheim:BAAALgAECgkJEwAAAA==.Vance:BAABLgAECn8WAAIEAAYJug0VygD7AAAEAAYJug0VygD7AAAAAA==.Vanitha:BAAALgADCggJBgAAAA==.Vanysh:BAAALgAECgMJAwAAAA==.Varala:BAAALgAECgYJEgAAAA==.',
Ve='Vel:BAACLgAFFH8aAAMTAAgJxRu8DwBgAgATAAgJxRu8DwBgAgAdAAEJAACJZAAAAAAuAAQKf1MAAxMACAlkJmgMAAkDABMACAlkJmgMAAkDACIAAwmCIe4VACoBAAAA.Velandis:BAAALgADCgcJBwAAAA==.Veldh:BAAALgAECggJAQABLgAFFAgJGgATAMUbAA==.Velenari:BAAALgAECgEJAQABLgAECgkJMAACAPUcAA==.Vellea:BAAALgAECgYJDgABLgAECgYJFQAgAIoRAA==.Velwar:BAAALgAECgcJCQABLgAFFAgJGgATAMUbAA==.Velýth:BAAALgAECgUJDAABLgAFFAgJGgATAMUbAA==.Venmeumshna:BAAALgAECgQJBQAAAA==.Veritas:BAABLgAECn8UAAIZAAYJVhFtOwAkAQAZAAYJVhFtOwAkAQAAAA==.Veskara:BAAALgAECgUJBQAAAA==.Vexxius:BAACLgAFFH8FAAIIAAIJfRiVJgCeAAAIAAIJfRiVJgCeAAAuAAQKfxwABAgACQkJGWoSABUCAAgACQn8FGoSABUCAB4ABwkxFNgVAAoBAAoAAQkgD0EyATYAAAAA.',
Vi='Viella:BAAALgAECgQJBAAAAA==.Viero:BAAALgAECggJCAAAAA==.',
Vo='Vorathis:BAAALgAECgYJDAABLgAFFAUJHAAFAOQkAA==.',
Vy='Vylana:BAAALgAECgYJDAABLgAFFAcJEQAEAJERAA==.',
['Và']='Vàlkyrie:BAACLgAFFH8aAAIEAAYJjBkxCwBnAQAEAAYJjBkxCwBnAQAuAAQKfyIAAgQACQkCHnEiAKACAAQACQkCHnEiAKACAAAA.',
['Vè']='Vèl:BAAALgAECgcJCgABLgAFFAgJGgATAMUbAA==.',
Wa='Wack:BAAALgAFFAEJAQAAAA==.Wanderfoot:BAABLgAECn8iAAIIAAkJGhZnDwA4AgAIAAkJGhZnDwA4AgAAAA==.Wangtulo:BAAALgADCgIJAgAAAA==.Warienta:BAAALgAECgMJAwAAAA==.Warity:BAABLgAECn9FAAIQAAkJ4Bv+FwCUAgAQAAkJ4Bv+FwCUAgAAAA==.Warnarse:BAAALgADCgUJBQAAAA==.Warrill:BAEBLgAECn8bAAIDAAgJ/QknIwAlAQADAAgJ/QknIwAlAQAAAA==.Wavestabe:BAABLgAECn88AAIHAAkJPhpqBwBkAgAHAAkJPhpqBwBkAgAAAA==.',
We='Welm:BAAALgADCgQJBAABLgAECgcJJAAEABcbAA==.',
Wo='Wobblart:BAAALgAECgQJBgABLgAECgkJPAAHAD4aAA==.',
Wr='Wreck:BAACLgAFFH8RAAMbAAQJtAWPCQDiAAAbAAQJtAWPCQDiAAAQAAIJKAKEugBaAAAuAAQKfy0AAhAACAn1DrxsAGIBABAACAn1DrxsAGIBAAAA.',
Xe='Xeevala:BAAALgAECgYJEAAAAA==.Xerxseize:BAAALgAECgEJAQAAAA==.',
Xo='Xomby:BAAALgAECgYJBgAAAA==.',
['Xì']='Xìon:BAABLgAECn8lAAMTAAkJpx7ZAwDzAQATAAkJpx7ZAwDzAQAiAAEJRwqLPwAoAAAAAA==.',
Ya='Yayrri:BAABLgAECn8tAAIRAAkJixG3JwCvAQARAAkJixG3JwCvAQAAAA==.',
Ye='Yersipestis:BAAALgAECgEJAQAAAA==.',
Yo='Youngjedi:BAAALgAECgUJBQAAAA==.',
Yu='Yungstabby:BAAALgAECgUJBQABLgAECgcJHgAKANMZAA==.Yurî:BAAALgAECgQJCQAAAA==.',
Za='Zahne:BAAALgAECgMJAwABLgAFFAUJBgAbAMEbAA==.Zatarra:BAAALgAECgQJBwAAAA==.Zathamax:BAABLgAECn8VAAIGAAgJaQN00wDtAAAGAAgJaQN00wDtAAAAAA==.Zavya:BAAALgAECgUJBAABLgAECgkJIAABAJUIAA==.Zazzu:BAAALgADCgIJAgAAAA==.',
Ze='Zeldei:BAAALgADCgEJAQAAAA==.Zephyrmars:BAAALgAECgIJAgAAAA==.Zextron:BAABLgAECn84AAIoAAkJVxMRAgDEAQAoAAkJVxMRAgDEAQAAAA==.',
Zi='Ziaya:BAABLgAECn8gAAIBAAkJlQi5MAA/AQABAAkJlQi5MAA/AQAAAA==.Zin:BAAALgADCgQJBAAAAA==.',
Zo='Zolaeus:BAAALgAECgUJDQABLgAECgYJFQAgAIoRAA==.Zorbaks:BAAALgAECgQJBAAAAA==.',
Zu='Zuboo:BAABLgAECn8yAAIoAAkJlwiBJgBFAQAoAAkJlwiBJgBFAQAAAA==.',
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
