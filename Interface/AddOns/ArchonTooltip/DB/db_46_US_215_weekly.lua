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

local lookup = {'Warlock-Demonology','Rogue-Subtlety','Evoker-Augmentation','Shaman-Elemental','Paladin-Holy','Hunter-Survival','Hunter-BeastMastery','Monk-Mistweaver','DeathKnight-Unholy','DeathKnight-Frost','Warrior-Protection','Druid-Restoration','Druid-Feral','Druid-Balance','Shaman-Restoration','Priest-Holy','Warrior-Arms','Warrior-Fury','Evoker-Devastation','Evoker-Preservation','Priest-Shadow','Paladin-Retribution','Druid-Guardian','Monk-Windwalker','DeathKnight-Blood','Hunter-Marksmanship','Unknown-Unknown','Paladin-Protection','Warlock-Affliction','DemonHunter-Havoc','Shaman-Enhancement','Warlock-Destruction','Mage-Frost','Mage-Fire','DemonHunter-Devourer','Monk-Brewmaster','Rogue-Outlaw','Rogue-Assassination',}
local provider = {region='US',realm='TheScryers',name='US',type='weekly',zone=46,date='2026-06-28',data={Ad='Addi:BAAALgAFFAQJBAAAAA==.Addykikora:BAAALgADCgkJCQABLgAECggJMQABAA4WAA==.Adillysse:BAAALgADCgkJCQABLgAECggJMQABAA4WAA==.',
Ae='Aelin:BAAALgAECgYJBwAAAA==.Aeonmoksha:BAAALgAFFAEJAQAAAA==.',
Ai='Airo:BAABLgAECn9DAAICAAkJ1BrJDABaAgACAAkJ1BrJDABaAgAAAA==.',
Ak='Akani:BAAALgADCgQJBAAAAA==.Akaris:BAABLgAECn8jAAIDAAkJewbgUADrAAADAAkJewbgUADrAAAAAA==.',
Al='Alainea:BAABLgAECn83AAIEAAkJ8REEAgCdAQAEAAkJ8REEAgCdAQAAAA==.Alispia:BAAALgAECgQJBAAAAA==.',
Am='Amaterasu:BAABLgAFFH8MAAIFAAMJViCrJwDlAAAFAAMJViCrJwDlAAABLgAFFAMJDAAFAFYgAA==.Ambre:BAAALgAECgkJEQAAAA==.Amerdro:BAAALgAECgQJCQAAAA==.Amoreesa:BAAALgAECgQJBAAAAA==.',
An='Andross:BAAALgAECgYJBwABLgAECgkJLgABACkOAA==.Angrytestie:BAAALgAECgUJBQAAAA==.Anomaly:BAACLgAFFH8GAAIGAAMJ0CK2GgD7AAAGAAMJ0CK2GgD7AAAuAAQKfywAAwYACAkmIksGAKACAAYACAkmIksGAKACAAcAAgl2Dja5AFAAAAEuAAUUBAkKAAEAExYA.Anthousai:BAAALgAECgMJAwAAAA==.Antler:BAAALgADCggJCAAAAA==.',
Ar='Ara:BAABLgAFFH8TAAIIAAcJTx4dDgAqAgAIAAcJTx4dDgAqAgAAAA==.',
As='Asylum:BAAALgADCgcJDQAAAA==.',
Au='Aura:BAABLgAECn8mAAIFAAkJpCJYAADuAgAFAAkJpCJYAADuAgAAAA==.',
Ax='Axl:BAABLgAECn8rAAMJAAkJQg62cwB8AQAJAAkJQg62cwB8AQAKAAEJ8QF2GgAhAAAAAA==.',
Ay='Aylíth:BAABLgAFFH8LAAILAAYJOBiEBAAyAQALAAYJOBiEBAAyAQABLgAFFAMJDAAFAFYgAA==.',
Ba='Bacon:BAAALgADCgkJCQAAAA==.Bahdeeps:BAAALgAECgcJEAAAAA==.Bahheals:BAABLgAECn8mAAMMAAcJ4QiHbQDsAAAMAAcJ4QiHbQDsAAANAAUJhQEqPQBlAAAAAA==.Banjoo:BAACLgAFFH8LAAIMAAMJ6xZhOADLAAAMAAMJ6xZhOADLAAAuAAQKfzkAAwwACQlUHg4LAA0DAAwACQlUHg4LAA0DAA4ABQmrEW1LAN4AAAAA.Baruk:BAACLgAFFH8LAAIPAAMJFRRySADMAAAPAAMJFRRySADMAAAuAAQKfyYAAg8ACQlIE5I+ALQBAA8ACQlIE5I+ALQBAAAA.',
Be='Beauzericka:BAAALgADCgEJAQAAAA==.Beeswax:BAAALgADCgkJCQAAAA==.Benny:BAAALgAECgUJCgABLgAECgkJQgAQADwjAA==.',
Bi='Bigçhungi:BAABLgAECn8qAAQRAAkJ0h2qCQBTAgARAAkJmhqqCQBTAgASAAcJlxdYOgBdAQALAAIJAQAMZAABAAABLgAFFAcJGgAJAGAgAA==.',
Bl='Blitzen:BAABLgAECn8rAAMTAAkJ3BqLBAAsAgATAAkJ3BqLBAAsAgAUAAYJYgq9IADuAAAAAA==.',
Bo='Borealiss:BAAALgAECgkJCgABLgAECgkJKwATANwaAA==.',
Br='Brewjigsaw:BAAALgADCgcJCgAAAA==.',
Bu='Buffsubordie:BAAALgAFFAEJAQAAAA==.Burd:BAAALgADCgkJCQAAAA==.Bustapustule:BAAALgAFFAIJBAAAAA==.',
Bw='Bwonsamdi:BAABLgAECn9FAAIEAAgJhCATDwC2AgAEAAgJhCATDwC2AgAAAA==.',
['Bâ']='Bârks:BAABLgAECn87AAMQAAkJiSB8BQAjAwAQAAkJiSB8BQAjAwAVAAEJHhKCgwA3AAAAAA==.',
['Bû']='Bûrd:BAAALgADCgkJGwAAAA==.',
Ca='Caarij:BAAALgADCgkJCQAAAA==.Callia:BAABLgAECn8cAAIWAAkJbA5OXwCyAQAWAAkJbA5OXwCyAQAAAA==.Camazotz:BAAALgADCgUJBQAAAA==.Cardkun:BAAALgADCgIJAgAAAA==.Carp:BAABLgAECn8gAAIXAAYJ4gq/QwCYAAAXAAYJ4gq/QwCYAAAAAA==.',
Ce='Celyna:BAAALgAECgMJAQAAAA==.Cerseii:BAAALgADCgUJBQAAAA==.',
Ch='Chargerkun:BAAALgAECgMJCwAAAA==.Chayda:BAAALgADCgEJAQAAAA==.Choleena:BAABLgAECn87AAIPAAkJhBiEGACFAgAPAAkJhBiEGACFAgAAAA==.',
Ci='Cindress:BAAALgADCgEJAQAAAA==.',
Co='Combat:BAABLgAECn8UAAIJAAgJtQ81hABbAQAJAAgJtQ81hABbAQAAAA==.Coojotwo:BAABLgAECn8WAAIHAAYJCwexFwCBAAAHAAYJCwexFwCBAAAAAA==.',
Cr='Crewd:BAAALgADCgEJAQAAAA==.Crimzon:BAAALgAECgEJAQAAAA==.Cryndle:BAAALgAECgYJBgAAAA==.',
Da='Dangerfloof:BAAALgADCgUJDAAAAA==.Dangerwithin:BAACLgAFFH8oAAMYAAkJOSVkAAA7AgAYAAkJOSVkAAA7AgAIAAEJrh2gWQBOAAAuAAQKfyYAAhgACQnKJjMAAPsDABgACQnKJjMAAPsDAAEuAAUUAwkMAAUAViAA.Danklazercat:BAAALgADCgcJDgABLgAFFAcJGgAJAGAgAA==.Darius:BAABLgAFFH8IAAIZAAMJkA91LQCSAAAZAAMJkA91LQCSAAAAAA==.Dastinor:BAAALgAECgUJBQAAAA==.Dastraz:BAABLgAECn8UAAQTAAgJ9wfHFQC3AAATAAUJpQbHFQC3AAAUAAUJGBRDKgCZAAADAAUJbwWPUgB+AAAAAA==.',
De='Decay:BAAALgAECgkJBgAAAA==.Deebz:BAABLgAECn83AAQGAAkJGhjODgA/AgAGAAkJVBTODgA/AgAHAAcJ/BYqbQBnAQAaAAYJQxgWFAAgAQAAAA==.Deephaven:BAAALgAECgEJAQABLgAECgcJEgAbAAAAAA==.Dena:BAAALgAECgEJAQAAAA==.Dethenor:BAAALgAECgQJBgAAAA==.Devkra:BAAALgAECgMJBgAAAA==.Deylirissa:BAAALgADCgYJBgAAAA==.',
Dm='Dmgabsorb:BAAALgADCgIJAgAAAA==.',
Do='Doge:BAAALgAECggJDQAAAA==.',
Dr='Dragoneux:BAAALgAFFAMJBgAAAQ==.Drakona:BAAALgAECgQJBAAAAA==.',
Du='Dudemachine:BAAALgADCgUJBQABLgADCgkJEwAbAAAAAA==.',
['Dè']='Dèèbz:BAAALgADCgQJBgAAAA==.',
['Dö']='Dörf:BAAALgADCgMJAwAAAA==.',
Ed='Eddison:BAAALgADCgkJDwAAAA==.',
El='Elementhor:BAAALgAECgIJAwAAAA==.',
En='Enchanted:BAACLgAFFH8QAAMJAAQJcRZhXwA2AQAJAAQJcRZhXwA2AQAZAAEJsRA2QAAwAAAuAAQKfyAAAxkACQnjGOoYAJoBABkACQmXFOoYAJoBAAkABwldGE17AG0BAAAA.Ender:BAAALgAECgcJDQAAAA==.Enid:BAACLgAFFH8oAAIZAAgJMSYKAAAFAwAZAAgJMSYKAAAFAwAuAAQKfxwAAhkACAmxJlkBAH4DABkACAmxJlkBAH4DAAAA.',
Es='Eskanor:BAAALgADCgQJBgAAAA==.',
Et='Eternalwrath:BAABLgAECn8sAAMJAAkJBxV7NAAtAgAJAAkJBxV7NAAtAgAKAAUJUgu4HgDXAAAAAA==.',
Eu='Eublar:BAAALgAECgEJAQAAAA==.',
Ey='Eyemage:BAAALgADCgQJBAAAAA==.',
Fa='Falzemphx:BAAALgAECgYJDQAAAA==.Farbringer:BAAALgAECgUJBwABLgAECggJFAATAPcHAA==.Fayanna:BAAALgADCgEJAQAAAA==.',
Fe='Felicitee:BAAALgAECgMJAwAAAA==.',
Fi='Firelight:BAAALgADCgkJEQAAAA==.',
Fo='Foxxylady:BAACLgAFFH8HAAIHAAIJdxUWfgCbAAAHAAIJdxUWfgCbAAAuAAQKfzAAAgcABwkhJEADAPcBAAcABwkhJEADAPcBAAAA.',
Fr='Freyja:BAABLgAECn8YAAIOAAcJGRHvAwAXAQAOAAcJGRHvAwAXAQAAAA==.',
Fu='Furbees:BAAALgAECgYJEgAAAA==.',
Ge='Geenon:BAAALgAECgYJDwAAAA==.Gephen:BAAALgADCgUJBQAAAA==.',
Go='Gobrielle:BAAALgADCgkJCQAAAA==.',
Gr='Grakdeez:BAAALgAECgcJDAABLgAECgkJEwAbAAAAAA==.Grakfist:BAAALgAECgkJEwAAAA==.Graknar:BAAALgAECggJEQABLgAECgkJEwAbAAAAAA==.Graubard:BAAALgAECgQJBwAAAA==.Gravec:BAAALgADCgEJAQAAAA==.Grimswhisper:BAAALgAECgYJDQAAAA==.Gritchen:BAABLgAECn8gAAMQAAcJwRqBGgD2AQAQAAcJwRqBGgD2AQAVAAMJNAKbjgAsAAAAAA==.Growler:BAAALgAECgcJEQAAAA==.Grynsel:BAABLgAECn86AAIHAAkJQRfCJQBLAgAHAAkJQRfCJQBLAgAAAA==.',
Gu='Gudeath:BAAALgAECgYJCwAAAA==.',
Ha='Harlynne:BAAALgADCgkJCQAAAA==.Harukav:BAAALgAECgIJAgAAAA==.',
He='Hemmuc:BAAALgAECgYJBgABLgAECgkJKwATANwaAA==.Hexabi:BAAALgAECgIJAgAAAA==.Hexed:BAAALgAECgEJAQAAAA==.',
Ho='Holios:BAAALgADCgYJBgABLgAFFAQJCQAVANkCAA==.',
Hu='Huntwix:BAAALgADCgYJBgAAAA==.',
Hw='Hwa:BAAALgAECgYJCQAAAA==.',
Id='Idontknow:BAACLgAFFH8JAAIVAAQJ2QKAJgDGAAAVAAQJ2QKAJgDGAAAuAAQKfy4AAhUACAm1DzktAG4BABUACAm1DzktAG4BAAAA.',
Ii='Iilia:BAAALgAECgQJBQABLgAFFAQJEQAPANAUAA==.',
In='Inwe:BAABLgAECn8lAAMNAAgJkAkmIgD4AAANAAgJkAkmIgD4AAAMAAUJtAMhoQBuAAAAAA==.',
Je='Jeemana:BAAALgADCgYJBgAAAA==.',
Jh='Jhintoki:BAAALgADCgkJCQAAAA==.',
Jo='Johnnydodge:BAABLgAECn9PAAMSAAkJpRKAAgCFAQASAAkJpRKAAgCFAQALAAMJtgfQBACWAAAAAA==.Jordon:BAAALgAECgQJCQAAAA==.Joyride:BAABLgAECn87AAMcAAkJmhvEBgB3AgAcAAkJmhvEBgB3AgAWAAEJ5A4kRAEyAAAAAA==.',
Ju='Jujuwing:BAABLgAECn8cAAIDAAgJrRIzLQCHAQADAAgJrRIzLQCHAQAAAA==.',
['Jù']='Jùde:BAABLgAECn8YAAQJAAYJognxEQCfAAAJAAYJ/wXxEQCfAAAZAAIJWwvETwBVAAAKAAEJ9gInGgAkAAAAAA==.',
Ka='Kaidastraza:BAAALgADCgcJDwAAAA==.Kaliel:BAAALgAECgQJBAAAAA==.Kalthas:BAAALgAECgEJAQAAAA==.Kanrethad:BAABLgAECn8UAAMBAAkJWyOoCwDxAgABAAkJWyOoCwDxAgAdAAEJAADMSAAAAAAAAA==.',
Ke='Kelandros:BAAALgAECgQJBAAAAA==.Kerrygan:BAABLgAECn8rAAIeAAkJIw8yGwClAQAeAAkJIw8yGwClAQAAAA==.',
Kh='Khaed:BAABLgAECn8ZAAIfAAkJHRHpEQCYAQAfAAkJHRHpEQCYAQAAAA==.',
Ki='Kicat:BAAALgAECgIJAgAAAA==.Killà:BAAALgAECgUJBQAAAA==.Kilmister:BAAALgADCgkJFwABLgAECgQJBwAbAAAAAA==.Kinara:BAAALgAECgIJAgAAAA==.',
Ko='Korthank:BAACLgAFFH8QAAIfAAQJFSHIAwCVAQAfAAQJFSHIAwCVAQAuAAQKfx0AAx8ACQlAIxwMAPEBAB8ACQlAIxwMAPEBAA8AAgnxEDTXADIAAAAA.Koruka:BAAALgADCgcJCAAAAA==.Koyanskaya:BAAALgAECgUJCwAAAA==.Kozatri:BAAALgADCgcJEwAAAA==.',
Kr='Krentead:BAAALgADCgYJBgAAAA==.Krillin:BAAALgADCgMJAwAAAA==.',
Kw='Kwissy:BAABLgAECn9EAAIHAAkJwA0fCQA2AQAHAAkJwA0fCQA2AQAAAA==.',
La='Labellanotte:BAABLgAECn8zAAMMAAkJXgX8agDzAAAMAAkJXgX8agDzAAANAAcJJwd8LgCqAAAAAA==.Lamastrasz:BAAALgAECgEJAQAAAA==.Landao:BAAALgAECgUJBgAAAA==.Lateron:BAAALgADCgYJBgAAAA==.Laturalus:BAAALgADCgUJBQAAAA==.Layssa:BAACLgAFFH8NAAIOAAMJzxZ/LQDSAAAOAAMJzxZ/LQDSAAAuAAQKfyEAAw4ACQnzGHETADkCAA4ACQnzGHETADkCAAwABQneCFCDANEAAAAA.',
Li='Lightarrow:BAAALgAECgcJBwAAAA==.Liliania:BAABLgAECn8fAAMgAAkJlA+7CgCXAQAgAAkJlA+7CgCXAQABAAIJkgERMwEaAAAAAA==.Limper:BAAALgADCgkJGwAAAA==.Lizuket:BAAALgADCgYJCwAAAA==.',
Lo='Loveles:BAAALgADCgUJBQAAAA==.',
Lu='Lucry:BAAALgADCgkJDgAAAA==.Lucyford:BAABLgAECn81AAMFAAkJCR+SDQC6AgAFAAgJTSGSDQC6AgAWAAcJGhgWeAB+AQAAAA==.Lunafloof:BAABLgAECn8iAAMhAAgJ0R3/NwA4AgAhAAgJ0R3/NwA4AgAiAAEJORJEEwA6AAAAAA==.Lunafox:BAAALgAECgEJAQABLgAECgcJCgAbAAAAAA==.Lunaiya:BAAALgAECgUJDQAAAA==.Lunarfang:BAAALgAECgEJAQABLgAECgcJCgAbAAAAAA==.Lunarosa:BAAALgADCgkJCQABLgAECgcJCgAbAAAAAA==.Lunatic:BAAALgAECgcJCgAAAA==.',
Ly='Lyraali:BAABLgAECn8jAAIHAAkJrhZQKQA5AgAHAAkJrhZQKQA5AgAAAA==.',
Ma='Magemode:BAABLgAECn8bAAIhAAYJyCHjTgBKAgAhAAYJyCHjTgBKAgAAAA==.Maomaow:BAAALgAECgEJAgAAAA==.Mara:BAAALgAECgcJCQAAAA==.Mavramaria:BAAALgADCgYJCgAAAA==.',
Me='Melzemphx:BAABLgAECn8cAAMYAAgJege7QAD9AAAYAAgJege7QAD9AAAIAAUJrAPbjwB6AAAAAA==.',
Mi='Mikeberetta:BAAALgAECgQJBgAAAA==.Miniz:BAAALgAECgEJAQAAAA==.Minlea:BAAALgAECgEJAwAAAA==.Misirlou:BAAALgAECgYJDAABLgAECgkJKwATANwaAA==.Mizchivf:BAAALgADCgQJBgAAAA==.',
Mo='Mogal:BAAALgADCgEJAQAAAA==.Moktezuma:BAAALgAECgQJBAAAAA==.Moosifer:BAAALgAECgEJAgABLgAECggJMQABAA4WAA==.Morodos:BAAALgADCgkJFAAAAA==.',
Mu='Murtaugh:BAAALgAECgcJDQAAAA==.Mutekii:BAABLgAECn8hAAIjAAgJcBHZCQDYAAAjAAgJcBHZCQDYAAAAAA==.',
Na='Natrel:BAABLgAECn8eAAMPAAYJRx6oLgD8AQAPAAYJRx6oLgD8AQAEAAYJ/QZ0ZQC1AAAAAA==.',
Ne='Neema:BAAALgAECgEJAwAAAA==.Neiru:BAAALgADCgkJGwAAAA==.Nemmael:BAAALgADCgcJDwAAAA==.',
No='Noctogero:BAAALgADCggJDAABLgAECggJLwAOAN0RAA==.Nosibm:BAAALgADCgkJJAAAAA==.Notabutt:BAAALgADCgYJBgAAAA==.',
Ny='Nyfaria:BAEALgAECgQJBAABLgAFFAUJJgAkAMIcAA==.Nyxes:BAAALgADCgMJAwAAAA==.',
['Nê']='Nêo:BAAALgADCgcJBwAAAA==.',
Oc='Octane:BAAALgAECgEJAQABLgAECgcJDwAbAAAAAA==.Octozm:BAABLgAFFH8JAAIhAAIJVSUTMwDRAAAhAAIJVSUTMwDRAAAAAA==.',
Ol='Olympi:BAAALgAECgEJAwAAAA==.',
Oo='Oopsie:BAAALgADCgEJAQAAAA==.Oopzies:BAAALgADCgkJCAAAAA==.',
Or='Oreofrosting:BAAALgADCgkJEwAAAA==.',
Pa='Padraigah:BAAALgAECgYJBgAAAA==.Palmstrike:BAAALgAECgEJAQAAAA==.Pañdø:BAAALgADCgMJAwAAAA==.',
Pe='Penderrin:BAAALgAECgEJAwAAAA==.Perseffonee:BAAALgAECggJCgAAAA==.',
Pi='Pidia:BAAALgADCgUJCAAAAA==.',
Po='Popes:BAACLgAFFH8JAAMHAAQJeA72WQDxAAAHAAQJGAj2WQDxAAAaAAIJ5hEDHQCiAAAuAAQKfxgAAxoACQldG3kfACoCABoACAkZHXkfACoCAAcAAgnGE0DmAIIAAAAA.Popper:BAAALgADCgkJCwAAAA==.',
Pr='Preservation:BAACLgAFFH8HAAIDAAQJ4RpdKAApAQADAAQJ4RpdKAApAQAuAAQKfxsAAgMABwkSISQWACgCAAMABwkSISQWACgCAAAA.Prey:BAAALgADCgMJAwAAAA==.Pruina:BAAALgADCgEJAQAAAA==.',
Pu='Pub:BAABLgAECn8XAAIjAAYJRBsZUQCyAQAjAAYJRBsZUQCyAQAAAA==.',
Py='Pyrø:BAAALgAECgUJCgAAAA==.',
Ra='Radhika:BAAALgAECgIJAwAAAA==.Raelos:BAABLgAECn8cAAMhAAkJoRtPVADgAQAhAAYJLBtPVADgAQAiAAUJ7RkvBQBwAQAAAA==.Ragebait:BAABLgAECn87AAIWAAkJuB02FwC4AgAWAAkJuB02FwC4AgAAAA==.Raiha:BAAALgAECgQJBAAAAA==.Ranikina:BAABLgAECn8sAAIMAAgJ8RESOgCtAQAMAAgJ8RESOgCtAQAAAA==.Raynor:BAAALgAECgUJBQAAAA==.',
Re='Regasus:BAABLgAECn8hAAIEAAkJeRPqIADdAQAEAAkJeRPqIADdAQAAAA==.Rendorai:BAAALgADCgIJAQAAAA==.Revolt:BAACLgAFFH8HAAIVAAMJugkjKQC2AAAVAAMJugkjKQC2AAAuAAQKfy8AAhUACQkCH1YLAJoCABUACQkCH1YLAJoCAAAA.Reïna:BAABLgAECn8oAAIgAAgJIBCPEQAuAQAgAAgJIBCPEQAuAQAAAA==.',
Rh='Rheía:BAABLgAFFH8HAAIXAAYJWhp/BgCRAQAXAAYJWhp/BgCRAQABLgAFFAMJDAAFAFYgAA==.',
Ro='Roükai:BAAALgAECgQJBQAAAA==.',
Ry='Ryuruko:BAAALgAECgYJBgAAAA==.',
Sa='Sahariel:BAABLgAECn9CAAMQAAkJPCPcAgBrAwAQAAkJPCPcAgBrAwAVAAcJwRPhNABFAQAAAA==.Savvy:BAAALgAECgcJBwAAAA==.',
Sc='Schwartpheil:BAAALgAECgcJEQAAAA==.Schwartzbann:BAAALgADCgcJCgABLgAECgcJEQAbAAAAAA==.Scilla:BAAALgADCgEJAQABLgAECgQJBwAbAAAAAA==.',
Se='Selieda:BAABLgAFFH8FAAIBAAMJzAhHKQB9AAABAAMJzAhHKQB9AAAAAA==.',
Sh='Shadowballz:BAAALgAECggJEgAAAA==.Shadowwing:BAAALgAECgMJBwAAAA==.Shamnorris:BAAALgADCgQJBAAAAA==.Shardemma:BAAALgADCgkJLwAAAA==.Shelfy:BAAALgAECgQJDwAAAA==.Shimmerly:BAAALgAECgcJDwAAAA==.Shocktop:BAAALgAECgEJAgAAAA==.Shreddedbeef:BAAALgADCgcJBwAAAA==.Shytningbolt:BAAALgADCgMJAgAAAA==.Shælyn:BAAALgAECgMJBgAAAA==.',
Si='Sintara:BAAALgAECgEJAQAAAA==.',
Sk='Skitzo:BAAALgADCgkJFgAAAA==.',
Sp='Spacelord:BAAALgADCgUJBQAAAA==.Spinetaker:BAABLgAECn8zAAIYAAgJGSKpCwCHAgAYAAgJGSKpCwCHAgABLgAFFAcJGgAJAGAgAA==.Spyder:BAAALgADCgQJBAAAAA==.',
St='Stolensouls:BAABLgAECn8wAAMgAAgJUQ81AgD/AAAgAAgJUQ81AgD/AAABAAIJHAJrZQEaAAAAAA==.Strawkun:BAAALgAECgIJAwAAAA==.',
Su='Sunaris:BAAALgADCgUJBQABLgAECggJLwAOAN0RAA==.Suneater:BAAALgAECggJDQAAAA==.',
['Sç']='Sçruffy:BAACLgAFFH8aAAMJAAcJYCCDGQAXAgAJAAYJYCCDGQAXAgAZAAEJAAB4EwBXAAAuAAQKf0oAAxkACQmpJtUAAGMDAAkACQmBJgsFAIMDABkACQmxJdUAAGMDAAAA.',
Ta='Taeva:BAAALgAECgEJAQAAAA==.Tahtiania:BAAALgADCggJDQAAAA==.Talas:BAAALgADCgEJAQAAAA==.Taliesin:BAAALgADCgUJBQAAAA==.',
Te='Teldryn:BAACLgAFFH8fAAISAAUJnx7wFgBZAQASAAUJnx7wFgBZAQAuAAQKfyYAAxIACQkeJEwHADMDABIACQkeJEwHADMDABEAAQneGNc5AEkAAAAA.Telios:BAAALgAECgQJBQAAAA==.',
Th='Thaer:BAAALgADCgYJDAAAAA==.Thorendire:BAABLgAECn86AAIeAAkJiRJGFgDXAQAeAAkJiRJGFgDXAQAAAA==.Thundoor:BAAALgADCgkJCQAAAA==.',
Ti='Tirnz:BAABLgAECn8vAAIKAAkJ3QuOEABuAQAKAAkJ3QuOEABuAQAAAA==.',
To='Tohotstotrot:BAAALgADCgQJBAABLgADCgcJBwAbAAAAAA==.Torlana:BAAALgAECgQJBAAAAA==.',
Tr='Trafaros:BAAALgADCgMJAwAAAA==.Trilldh:BAAALgAECgcJBQAAAA==.Trixielou:BAAALgAECggJEgAAAA==.',
Tt='Ttattoo:BAEBLgAECn8YAAMkAAYJ5QcwUADBAAAkAAYJ5QcwUADBAAAYAAEJqALpwAAXAAABLgAECgkJGAAJACUPAA==.Ttattooz:BAEBLgAECn8YAAIJAAkJJQ8PTQDbAQAJAAkJJQ8PTQDbAQAAAA==.',
Ty='Tyramonde:BAAALgAECgYJCQAAAA==.',
Ub='Ubonrebu:BAAALgAFFAEJAQAAAA==.',
Ud='Udb:BAAALgAFFAEJAQABLgAFFAIJAwAbAAAAAA==.',
Va='Vaelestrix:BAACLgAFFH8mAAQCAAgJESBSAgAFAgACAAcJMSRSAgAFAgAlAAMJDByfCADzAAAmAAEJUQcsBgBdAAAuAAQKf0QAAwIACQn4JW4AAOUDAAIACQn4JW4AAOUDACYAAQnuJS8eAGsAAAAA.Vain:BAEALgAECgIJAgAAAA==.Valamaldoran:BAAALgADCgkJCQAAAA==.Valholla:BAAALgADCgMJAwAAAA==.Vashtanerada:BAAALgADCgYJCgAAAA==.',
Ve='Veilish:BAAALgADCgYJCQAAAA==.',
Vo='Voiddøøde:BAAALgAECgUJBQAAAA==.Voidsocket:BAAALgAECgcJBgAAAA==.Voidtoes:BAAALgAECgQJBAAAAA==.',
Vu='Vulpvs:BAAALgAECgEJAQAAAA==.',
Vv='Vvlpvs:BAAALgADCgQJBAAAAA==.',
Vy='Vyral:BAAALgAFFAEJAQAAAA==.',
Wa='Warherald:BAABLgAECn8iAAQLAAgJ9Q9dHwA4AQALAAgJ9Q9dHwA4AQARAAUJtAc5UwCJAAASAAMJAwWPigBdAAAAAA==.Wasntme:BAAALgADCgYJCgABLgAFFAQJCQAVANkCAA==.',
We='Wednesday:BAACLgAFFH8pAAIZAAkJWhxLAgCtAgAZAAkJWhxLAgCtAgAuAAQKfywAAhkACAnwJBEHAKsCABkACAnwJBEHAKsCAAAA.',
Wh='Whoops:BAAALgADCgcJBwAAAA==.',
Wu='Wuxi:BAAALgAECgcJCgABLgAFFAQJEAAfABUhAA==.',
Wy='Wyldefyre:BAAALgADCggJCAAAAA==.',
['Wø']='Wøøds:BAAALgAECgQJBgAAAA==.',
Xa='Xalaria:BAAALgAECgYJDAAAAA==.Xandril:BAAALgAECgIJAgABLgAECggJFAATAPcHAA==.',
Xi='Xirek:BAABLgAECn87AAILAAkJZhEzEwC6AQALAAkJZhEzEwC6AQAAAA==.',
Yr='Yreasak:BAABLgAECn8uAAMBAAkJKQ5uSgC7AQABAAkJJQ5uSgC7AQAdAAMJFwj8GgCeAAAAAA==.Yrisan:BAAALgAECgUJBQABLgAECgkJLgABACkOAA==.',
Ys='Yseulde:BAAALgAECgcJDAABLgAECgkJLgABACkOAA==.',
Za='Zallice:BAAALgAECgEJAQAAAA==.',
Zi='Zindroz:BAAALgADCgQJBAAAAA==.',
Zo='Zonako:BAAALgAECgcJEgAAAA==.Zoogranby:BAAALgADCgYJBgAAAA==.',
Zu='Zurâ:BAABLgAECn8/AAIZAAkJCgkHJQArAQAZAAkJCgkHJQArAQAAAA==.',
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
