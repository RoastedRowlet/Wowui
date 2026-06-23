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
local provider = {region='US',realm='TheScryers',name='US',type='weekly',zone=46,date='2026-06-21',data={Ad='Addi:BAAALgAFFAQJBAAAAA==.Addykikora:BAAALgADCgkJCQABLgAECggJKwABAPYVAA==.Adillysse:BAAALgADCgkJCQABLgAECggJKwABAPYVAA==.',
Ae='Aelin:BAAALgAECgYJBwAAAA==.Aeonmoksha:BAAALgAFFAEJAQAAAA==.',
Ai='Airo:BAABLgAECn9CAAICAAkJUxrIDABaAgACAAkJUxrIDABaAgAAAA==.',
Ak='Akani:BAAALgADCgQJBAAAAA==.Akaris:BAABLgAECn8jAAIDAAkJewbhUADrAAADAAkJewbhUADrAAAAAA==.',
Al='Alainea:BAABLgAECn83AAIEAAkJ8RHhAACiAQAEAAkJ8RHhAACiAQAAAA==.Alispia:BAAALgAECgQJBAAAAA==.',
Am='Amaterasu:BAABLgAFFH8MAAIFAAMJViCsJwDlAAAFAAMJViCsJwDlAAABLgAFFAMJDAAFAFYgAA==.Ambre:BAAALgAECgkJEQAAAA==.Amerdro:BAAALgAECgQJCQAAAA==.Amoreesa:BAAALgAECgQJBAAAAA==.',
An='Andross:BAAALgAECgYJBwABLgAECgkJLgABACkOAA==.Angrytestie:BAAALgAECgUJBQAAAA==.Anomaly:BAACLgAFFH8GAAIGAAMJ0CK2GgD7AAAGAAMJ0CK2GgD7AAAuAAQKfywAAwYACAkmIksGAKACAAYACAkmIksGAKACAAcAAgl2Dja5AFAAAAEuAAUUBAkKAAEAExYA.Anthousai:BAAALgADCgQJBAAAAA==.',
Ar='Ara:BAABLgAFFH8TAAIIAAcJTx4eDgAqAgAIAAcJTx4eDgAqAgAAAA==.',
As='Asylum:BAAALgADCgcJDQAAAA==.',
Au='Aura:BAABLgAECn8dAAIFAAkJ1R+bBgAjAwAFAAkJ1R+bBgAjAwAAAA==.',
Ax='Axl:BAABLgAECn8rAAMJAAkJQg61cwB8AQAJAAkJQg61cwB8AQAKAAEJ8QF2GgAhAAAAAA==.',
Ay='Aylíth:BAABLgAFFH8GAAILAAUJLRqmEgASAQALAAUJLRqmEgASAQABLgAFFAMJDAAFAFYgAA==.',
Ba='Bacon:BAAALgADCgkJCQAAAA==.Bahdeeps:BAAALgAECgcJEAAAAA==.Bahheals:BAABLgAECn8mAAMMAAcJ4QiLbQDsAAAMAAcJ4QiLbQDsAAANAAUJhQEqPQBlAAAAAA==.Banjoo:BAACLgAFFH8JAAIMAAMJjhRhOADLAAAMAAMJjhRhOADLAAAuAAQKfzkAAwwACQlUHg4LAA0DAAwACQlUHg4LAA0DAA4ABQmrEWtLAN4AAAAA.Baruk:BAACLgAFFH8LAAIPAAMJFRRxSADMAAAPAAMJFRRxSADMAAAuAAQKfyYAAg8ACQlIE48+ALQBAA8ACQlIE48+ALQBAAAA.',
Be='Beauzericka:BAAALgADCgEJAQAAAA==.Beeswax:BAAALgADCgkJCQAAAA==.Benny:BAAALgAECgUJBQABLgAECgkJQgAQADwjAA==.',
Bi='Bigçhungi:BAABLgAECn8qAAQRAAkJ0h2rCQBTAgARAAkJmhqrCQBTAgASAAcJlxdXOgBdAQALAAIJAQAJZAABAAABLgAFFAcJGgAJAGAgAA==.',
Bl='Blitzen:BAABLgAECn8rAAMTAAkJ3BqLBAAsAgATAAkJ3BqLBAAsAgAUAAYJYgq8IADuAAAAAA==.',
Bo='Borealiss:BAAALgAECgkJCgABLgAECgkJKwATANwaAA==.',
Br='Brewjigsaw:BAAALgADCgcJCgAAAA==.',
Bu='Buffsubordie:BAAALgAFFAEJAQAAAA==.Bustapustule:BAAALgAFFAIJBAAAAA==.',
Bw='Bwonsamdi:BAABLgAECn9FAAIEAAgJhCATDwC2AgAEAAgJhCATDwC2AgAAAA==.',
['Bâ']='Bârks:BAABLgAECn85AAMQAAkJfCB9BQAjAwAQAAkJfCB9BQAjAwAVAAEJHhJ9gwA3AAAAAA==.',
['Bû']='Bûrd:BAAALgADCgkJGwAAAA==.',
Ca='Caarij:BAAALgADCgkJCQAAAA==.Callia:BAABLgAECn8cAAIWAAkJbA5PXwCyAQAWAAkJbA5PXwCyAQAAAA==.Camazotz:BAAALgADCgUJBQAAAA==.Cardkun:BAAALgADCgIJAgAAAA==.Carp:BAABLgAECn8gAAIXAAYJ4gq/QwCYAAAXAAYJ4gq/QwCYAAAAAA==.',
Ce='Celyna:BAAALgAECgMJAQAAAA==.Cerseii:BAAALgADCgUJBQAAAA==.',
Ch='Chargerkun:BAAALgAECgMJCwAAAA==.Chayda:BAAALgADCgEJAQAAAA==.Choleena:BAABLgAECn85AAIPAAkJSxiBGACFAgAPAAkJSxiBGACFAgAAAA==.',
Ci='Cindress:BAAALgADCgEJAQAAAA==.',
Co='Combat:BAABLgAECn8UAAIJAAgJtQ80hABbAQAJAAgJtQ80hABbAQAAAA==.Coojotwo:BAAALgAECgYJEQAAAA==.',
Cr='Crewd:BAAALgADCgEJAQAAAA==.Crimzon:BAAALgAECgEJAQAAAA==.Cryndle:BAAALgAECgYJBgAAAA==.',
Da='Dangerfloof:BAAALgADCgUJDAAAAA==.Dangerwithin:BAACLgAFFH8oAAMYAAkJOSVkAAA7AgAYAAkJOSVkAAA7AgAIAAEJrh2bWQBOAAAuAAQKfyYAAhgACQnKJjMAAPsDABgACQnKJjMAAPsDAAEuAAUUAwkMAAUAViAA.Danklazercat:BAAALgADCgcJDgABLgAFFAcJGgAJAGAgAA==.Darius:BAABLgAFFH8IAAIZAAMJkA91LQCSAAAZAAMJkA91LQCSAAAAAA==.Dastinor:BAAALgAECgUJBQAAAA==.Dastraz:BAABLgAECn8UAAQTAAgJ9wfHFQC3AAATAAUJpQbHFQC3AAAUAAUJGBRDKgCZAAADAAUJbwWPUgB+AAAAAA==.',
De='Decay:BAAALgAECgkJBgAAAA==.Deebz:BAABLgAECn81AAQGAAkJGhjQDgA/AgAGAAkJVBTQDgA/AgAHAAcJ/BYvbQBnAQAaAAYJQxgWFAAgAQAAAA==.Deephaven:BAAALgAECgEJAQABLgAECgcJEgAbAAAAAA==.Dena:BAAALgAECgEJAQAAAA==.Dethenor:BAAALgAECgEJAQAAAA==.Devkra:BAAALgAECgMJBgAAAA==.Deylirissa:BAAALgADCgYJBgAAAA==.',
Dm='Dmgabsorb:BAAALgADCgIJAgAAAA==.',
Do='Doge:BAAALgAECggJDAAAAA==.',
Dr='Dragoneux:BAAALgAFFAMJBgAAAQ==.Drakona:BAAALgAECgQJBAAAAA==.',
Du='Dudemachine:BAAALgADCgUJBQABLgADCgkJEwAbAAAAAA==.',
['Dè']='Dèèbz:BAAALgADCgQJBgAAAA==.',
['Dö']='Dörf:BAAALgADCgMJAwAAAA==.',
Ed='Eddison:BAAALgADCgkJDwAAAA==.',
El='Elementhor:BAAALgAECgIJAwAAAA==.',
En='Enchanted:BAACLgAFFH8NAAMJAAQJcRZhXwA2AQAJAAQJcRZhXwA2AQAZAAEJsRA0QAAwAAAuAAQKfyAAAxkACQnjGOoYAJoBABkACQmXFOoYAJoBAAkABwldGEp7AG0BAAAA.Ender:BAAALgAECgcJCwAAAA==.Enid:BAACLgAFFH8oAAIZAAgJMSYKAAAFAwAZAAgJMSYKAAAFAwAuAAQKfxwAAhkACAmxJlkBAH4DABkACAmxJlkBAH4DAAAA.',
Es='Eskanor:BAAALgADCgQJBgAAAA==.',
Et='Eternalwrath:BAABLgAECn8qAAMJAAkJBhV7NAAtAgAJAAkJBhV7NAAtAgAKAAUJUgu5HgDXAAAAAA==.',
Eu='Eublar:BAAALgAECgEJAQAAAA==.',
Ey='Eyemage:BAAALgADCgQJBAAAAA==.',
Fa='Falzemphx:BAAALgAECgYJDQAAAA==.Farbringer:BAAALgAECgUJBgABLgAECggJFAATAPcHAA==.Fayanna:BAAALgADCgEJAQAAAA==.',
Fe='Felicitee:BAAALgAECgMJAwAAAA==.',
Fi='Firelight:BAAALgADCgkJCQAAAA==.',
Fo='Foxxylady:BAACLgAFFH8HAAIHAAIJdxUUfgCbAAAHAAIJdxUUfgCbAAAuAAQKfyoAAgcABwnBIv4jAFMCAAcABwnBIv4jAFMCAAAA.',
Fr='Freyja:BAAALgAECgcJEgAAAA==.',
Fu='Furbees:BAAALgAECgYJEgAAAA==.',
Ge='Geenon:BAAALgAECgYJDwAAAA==.Gephen:BAAALgADCgUJBQAAAA==.',
Gr='Grakdeez:BAAALgAECgcJDAABLgAECgkJEwAbAAAAAA==.Grakfist:BAAALgAECgkJEwAAAA==.Graknar:BAAALgAECggJEQABLgAECgkJEwAbAAAAAA==.Graubard:BAAALgAECgQJBgAAAA==.Gravec:BAAALgADCgEJAQAAAA==.Grimswhisper:BAAALgAECgYJDQAAAA==.Gritchen:BAABLgAECn8gAAMQAAcJwRp/GgD2AQAQAAcJwRp/GgD2AQAVAAMJNAKWjgAsAAAAAA==.Growler:BAAALgAECgcJEQAAAA==.Grynsel:BAABLgAECn84AAIHAAkJQRfDJQBLAgAHAAkJQRfDJQBLAgAAAA==.',
Gu='Gudeath:BAAALgAECgUJCgAAAA==.',
Ha='Harlynne:BAAALgADCgkJCQAAAA==.Harukav:BAAALgAECgIJAgAAAA==.',
He='Hemmuc:BAAALgAECgYJBgABLgAECgkJKwATANwaAA==.Hexabi:BAAALgAECgIJAgAAAA==.Hexed:BAAALgAECgEJAQAAAA==.',
Ho='Holios:BAAALgADCgYJBgABLgAFFAQJCQAVANkCAA==.',
Hu='Huntwix:BAAALgADCgYJBgAAAA==.',
Hw='Hwa:BAAALgAECgEJAwAAAA==.',
Id='Idontknow:BAACLgAFFH8JAAIVAAQJ2QJ+JgDGAAAVAAQJ2QJ+JgDGAAAuAAQKfy4AAhUACAm1DzYtAG4BABUACAm1DzYtAG4BAAAA.',
Ii='Iilia:BAAALgAECgQJBQABLgAFFAQJEAAPAMMTAA==.',
In='Inwe:BAABLgAECn8lAAMNAAgJkAkoIgD4AAANAAgJkAkoIgD4AAAMAAUJtAMioQBuAAAAAA==.',
Je='Jeemana:BAAALgADCgYJBgAAAA==.',
Jh='Jhintoki:BAAALgADCgkJCQAAAA==.',
Jo='Johnnydodge:BAABLgAECn9IAAMSAAkJLxHtAQAeAQASAAkJLxHtAQAeAQALAAMJtgc0AgCaAAAAAA==.Jordon:BAAALgAECgQJCQAAAA==.Joyride:BAABLgAECn85AAMcAAkJmhvEBgB3AgAcAAkJmhvEBgB3AgAWAAEJ5A4kRAEyAAAAAA==.',
Ju='Jujuwing:BAABLgAECn8cAAIDAAgJrRIzLQCHAQADAAgJrRIzLQCHAQAAAA==.',
['Jù']='Jùde:BAABLgAECn8XAAQJAAYJognJCQB9AAAJAAYJ/wXJCQB9AAAZAAIJWwvCTwBVAAAKAAEJ9gInGgAkAAAAAA==.',
Ka='Kaidastraza:BAAALgADCgcJDwAAAA==.Kaliel:BAAALgAECgQJBAAAAA==.Kalthas:BAAALgAECgEJAQAAAA==.Kanrethad:BAABLgAECn8UAAMBAAkJWyOoCwDxAgABAAkJWyOoCwDxAgAdAAEJAADMSAAAAAAAAA==.',
Ke='Kelandros:BAAALgAECgQJBAAAAA==.Kerrygan:BAABLgAECn8rAAIeAAkJIw8zGwClAQAeAAkJIw8zGwClAQAAAA==.',
Kh='Khaed:BAABLgAECn8ZAAIfAAkJHRHpEQCYAQAfAAkJHRHpEQCYAQAAAA==.',
Ki='Kicat:BAAALgAECgIJAgAAAA==.Killà:BAAALgAECgUJBQAAAA==.Kilmister:BAAALgADCgkJFwABLgAECgQJBgAbAAAAAA==.Kinara:BAAALgAECgIJAgAAAA==.',
Ko='Korthank:BAACLgAFFH8QAAIfAAQJFSHIAwCVAQAfAAQJFSHIAwCVAQAuAAQKfx0AAx8ACQlAIxwMAPEBAB8ACQlAIxwMAPEBAA8AAgnxEDPXADIAAAAA.Koruka:BAAALgADCgcJCAAAAA==.Koyanskaya:BAAALgAECgUJCwAAAA==.Kozatri:BAAALgADCgcJEwAAAA==.',
Kr='Krentead:BAAALgADCgYJBgAAAA==.Krillin:BAAALgADCgMJAwAAAA==.',
Kw='Kwissy:BAABLgAECn89AAIHAAkJPA1rBwDMAAAHAAkJPA1rBwDMAAAAAA==.',
La='Labellanotte:BAABLgAECn8xAAMMAAkJTwX/agDzAAAMAAkJTwX/agDzAAANAAYJjQd8LgCqAAAAAA==.Lamastrasz:BAAALgAECgEJAQAAAA==.Landao:BAAALgAECgQJBQAAAA==.Lateron:BAAALgADCgYJBgAAAA==.Laturalus:BAAALgADCgUJBQAAAA==.Layssa:BAACLgAFFH8MAAIOAAMJzxZ+LQDSAAAOAAMJzxZ+LQDSAAAuAAQKfyEAAw4ACQnzGHATADkCAA4ACQnzGHATADkCAAwABQneCFCDANEAAAAA.',
Li='Lightarrow:BAAALgAECgcJBwAAAA==.Liliania:BAABLgAECn8fAAMgAAkJlA+7CgCXAQAgAAkJlA+7CgCXAQABAAIJkgERMwEaAAAAAA==.Limper:BAAALgADCgkJEgAAAA==.Lizuket:BAAALgADCgYJCwAAAA==.',
Lo='Loveles:BAAALgADCgUJBQAAAA==.',
Lu='Lucry:BAAALgADCgkJDgAAAA==.Lucyford:BAABLgAECn81AAMFAAkJCR+SDQC6AgAFAAgJTSGSDQC6AgAWAAcJGhgWeAB+AQAAAA==.Lunafloof:BAABLgAECn8iAAMhAAgJ0R0BOAA4AgAhAAgJ0R0BOAA4AgAiAAEJORJEEwA6AAAAAA==.Lunafox:BAAALgAECgEJAQABLgAECgYJCAAbAAAAAA==.Lunaiya:BAAALgAECgUJDQAAAA==.Lunarfang:BAAALgAECgEJAQABLgAECgYJCAAbAAAAAA==.Lunarosa:BAAALgADCgkJCQABLgAECgYJCAAbAAAAAA==.Lunatic:BAAALgAECgYJCAAAAA==.',
Ly='Lyraali:BAABLgAECn8hAAIHAAkJLxZSKQA5AgAHAAkJLxZSKQA5AgAAAA==.',
Ma='Magemode:BAABLgAECn8bAAIhAAYJyCHjTgBKAgAhAAYJyCHjTgBKAgAAAA==.Maomaow:BAAALgAECgEJAgAAAA==.Mara:BAAALgAECgEJAwAAAA==.Mavramaria:BAAALgADCgYJCgAAAA==.',
Me='Melzemphx:BAABLgAECn8cAAMYAAgJege7QAD9AAAYAAgJege7QAD9AAAIAAUJrAPYjwB6AAAAAA==.',
Mi='Mikeberetta:BAAALgAECgQJBAAAAA==.Miniz:BAAALgADCgcJBwAAAA==.Minlea:BAAALgAECgEJAwAAAA==.Misirlou:BAAALgAECgYJDAABLgAECgkJKwATANwaAA==.Mizchivf:BAAALgADCgQJBgAAAA==.',
Mo='Mogal:BAAALgADCgEJAQAAAA==.Moktezuma:BAAALgAECgQJBAAAAA==.Moosifer:BAAALgAECgEJAgABLgAECggJKwABAPYVAA==.Morodos:BAAALgADCgkJFAAAAA==.',
Mu='Murtaugh:BAAALgAECgQJBgAAAA==.Mutekii:BAABLgAECn8hAAIjAAgJcBE8BADZAAAjAAgJcBE8BADZAAAAAA==.',
Na='Natrel:BAABLgAECn8eAAMPAAYJRx6mLgD8AQAPAAYJRx6mLgD8AQAEAAYJ/QZxZQC1AAAAAA==.',
Ne='Neema:BAAALgAECgEJAwAAAA==.Neiru:BAAALgADCgkJGwAAAA==.Nemmael:BAAALgADCgcJDwAAAA==.',
No='Noctogero:BAAALgADCggJDAABLgAECggJLwAOAN0RAA==.Nosibm:BAAALgADCgkJGwAAAA==.Notabutt:BAAALgADCgYJBgAAAA==.',
Ny='Nyfaria:BAEALgAECgQJBAABLgAFFAUJJgAkAMIcAA==.Nyxes:BAAALgADCgMJAwAAAA==.',
['Nê']='Nêo:BAAALgADCgcJBwAAAA==.',
Oc='Octane:BAAALgAECgEJAQABLgAECgcJCgAbAAAAAA==.Octozm:BAABLgAFFH8JAAIhAAIJVSUTMwDRAAAhAAIJVSUTMwDRAAAAAA==.',
Ol='Olympi:BAAALgAECgEJAgAAAA==.',
Oo='Oopsie:BAAALgADCgEJAQAAAA==.',
Or='Oreofrosting:BAAALgADCgkJEwAAAA==.',
Pa='Padraigah:BAAALgAECgYJBgAAAA==.Palmstrike:BAAALgAECgEJAQAAAA==.Pañdø:BAAALgADCgMJAwAAAA==.',
Pe='Penderrin:BAAALgAECgEJAwAAAA==.Perseffonee:BAAALgAECggJCgAAAA==.',
Pi='Pidia:BAAALgADCgUJCAAAAA==.',
Po='Popes:BAACLgAFFH8JAAMHAAQJeA7xWQDxAAAHAAQJGAjxWQDxAAAaAAIJ5hEDHQCiAAAuAAQKfxgAAxoACQldG3kfACoCABoACAkZHXkfACoCAAcAAgnGEznmAIIAAAAA.Popper:BAAALgADCgkJCwAAAA==.',
Pr='Preservation:BAACLgAFFH8HAAIDAAQJ4RpcKAApAQADAAQJ4RpcKAApAQAuAAQKfxsAAgMABwkSISUWACgCAAMABwkSISUWACgCAAAA.Prey:BAAALgADCgMJAwAAAA==.Pruina:BAAALgADCgEJAQAAAA==.',
Pu='Pub:BAABLgAECn8VAAIjAAYJRBsZUQCyAQAjAAYJRBsZUQCyAQAAAA==.',
Py='Pyrø:BAAALgAECgUJCgAAAA==.',
Ra='Radhika:BAAALgAECgIJAwAAAA==.Raelos:BAABLgAECn8cAAMhAAkJoRukBAAVAQAiAAUJ7RkvBQBwAQAhAAYJLBukBAAVAQAAAA==.Ragebait:BAABLgAECn85AAIWAAkJuB02FwC4AgAWAAkJuB02FwC4AgAAAA==.Raiha:BAAALgAECgQJBAAAAA==.Ranikina:BAABLgAECn8mAAIMAAgJ8REVOgCtAQAMAAgJ8REVOgCtAQAAAA==.Raynor:BAAALgADCgIJAgAAAA==.',
Re='Regasus:BAABLgAECn8gAAIEAAkJeRPqIADdAQAEAAkJeRPqIADdAQAAAA==.Rendorai:BAAALgADCgIJAQAAAA==.Revolt:BAACLgAFFH8HAAIVAAMJugkhKQC2AAAVAAMJugkhKQC2AAAuAAQKfy8AAhUACQkCH1cLAJoCABUACQkCH1cLAJoCAAAA.Reïna:BAABLgAECn8iAAIgAAgJ1g6PEQAuAQAgAAgJ1g6PEQAuAQAAAA==.',
Rh='Rheía:BAABLgAFFH8GAAIXAAYJcxl/BgCRAQAXAAYJcxl/BgCRAQABLgAFFAMJDAAFAFYgAA==.',
Ro='Roükai:BAAALgAECgQJBQAAAA==.',
Ry='Ryuruko:BAAALgAECgYJBgAAAA==.',
Sa='Sahariel:BAABLgAECn9CAAMQAAkJPCPdAgBrAwAQAAkJPCPdAgBrAwAVAAcJwRPgNABEAQAAAA==.Savvy:BAAALgAECgYJBgAAAA==.',
Sc='Schwartpheil:BAAALgAECgcJEQAAAA==.Schwartzbann:BAAALgADCgcJCgABLgAECgcJEQAbAAAAAA==.Scilla:BAAALgADCgEJAQABLgAECgQJBgAbAAAAAA==.',
Se='Selieda:BAAALgAFFAMJAwAAAA==.',
Sh='Shadowballz:BAAALgAECggJEgAAAA==.Shadowwing:BAAALgAECgMJBwAAAA==.Shamnorris:BAAALgADCgQJBAAAAA==.Shardemma:BAAALgADCgkJLgAAAA==.Shelfy:BAAALgAECgQJDwAAAA==.Shimmerly:BAAALgAECgcJCgAAAA==.Shocktop:BAAALgAECgEJAQAAAA==.Shreddedbeef:BAAALgADCgcJBwAAAA==.Shytningbolt:BAAALgADCgMJAgAAAA==.Shælyn:BAAALgAECgMJBgAAAA==.',
Si='Sintara:BAAALgAECgEJAQAAAA==.',
Sk='Skitzo:BAAALgADCgkJFgAAAA==.',
Sp='Spinetaker:BAABLgAECn8zAAIYAAgJGSKpCwCHAgAYAAgJGSKpCwCHAgABLgAFFAcJGgAJAGAgAA==.Spyder:BAAALgADCgQJBAAAAA==.',
St='Stolensouls:BAABLgAECn8qAAMgAAgJBw8WEgAnAQAgAAgJBw8WEgAnAQABAAIJHAJqZQEaAAAAAA==.Strawkun:BAAALgAECgIJAwAAAA==.',
Su='Sunaris:BAAALgADCgUJBQABLgAECggJLwAOAN0RAA==.Suneater:BAAALgAECggJDQAAAA==.',
['Sç']='Sçruffy:BAACLgAFFH8aAAMJAAcJYCCIGQAXAgAJAAYJYCCIGQAXAgAZAAEJAAB4EwBXAAAuAAQKf0oAAxkACQmpJtUAAGMDAAkACQmBJgsFAIMDABkACQmxJdUAAGMDAAAA.',
Ta='Taeva:BAAALgAECgEJAQAAAA==.Tahtiania:BAAALgADCggJDQAAAA==.Talas:BAAALgADCgEJAQAAAA==.Taliesin:BAAALgADCgUJBQAAAA==.',
Te='Teldryn:BAACLgAFFH8fAAISAAUJnx7wFgBZAQASAAUJnx7wFgBZAQAuAAQKfyYAAxIACQkeJEwHADMDABIACQkeJEwHADMDABEAAQneGNc5AEkAAAAA.Telios:BAAALgAECgQJBQAAAA==.',
Th='Thaer:BAAALgADCgYJDAAAAA==.Thorendire:BAABLgAECn86AAIeAAkJiRJHFgDXAQAeAAkJiRJHFgDXAQAAAA==.Thundoor:BAAALgADCgkJCQAAAA==.',
Ti='Tirnz:BAABLgAECn8vAAIKAAkJ3QuOEABuAQAKAAkJ3QuOEABuAQAAAA==.',
To='Tohotstotrot:BAAALgADCgQJBAABLgADCgcJBwAbAAAAAA==.Torlana:BAAALgAECgQJBAAAAA==.',
Tr='Trafaros:BAAALgADCgMJAwAAAA==.Trilldh:BAAALgAECgcJBQAAAA==.Trixielou:BAAALgAECggJEgAAAA==.',
Tt='Ttattoo:BAEBLgAECn8YAAMkAAYJ5QcwUADBAAAkAAYJ5QcwUADBAAAYAAEJqALmwAAXAAABLgAECgkJGAAJACUPAA==.Ttattooz:BAEBLgAECn8YAAIJAAkJJQ8LTQDbAQAJAAkJJQ8LTQDbAQAAAA==.',
Ty='Tyramonde:BAAALgAECgYJCQAAAA==.',
Ub='Ubonrebu:BAAALgAFFAEJAQAAAA==.',
Va='Vaelestrix:BAACLgAFFH8hAAQCAAgJ/x04BQBrAgACAAcJxiE4BQBrAgAlAAMJDByfCADzAAAmAAEJUQcsBgBdAAAuAAQKf0QAAwIACQn4JW4AAOUDAAIACQn4JW4AAOUDACYAAQnuJS0eAGsAAAAA.Valamaldoran:BAAALgADCgkJCQAAAA==.Valholla:BAAALgADCgMJAwAAAA==.Vashtanerada:BAAALgADCgYJCgAAAA==.',
Ve='Veilish:BAAALgADCgYJCQAAAA==.',
Vo='Voiddøøde:BAAALgAECgUJBQAAAA==.Voidsocket:BAAALgAECgcJBgAAAA==.Voidtoes:BAAALgAECgQJBAAAAA==.',
Vu='Vulpvs:BAAALgADCgcJCwAAAA==.',
Vv='Vvlpvs:BAAALgADCgQJBAAAAA==.',
Vy='Vyral:BAAALgAFFAEJAQAAAA==.',
Wa='Warherald:BAABLgAECn8iAAQLAAgJ9Q9dHwA4AQALAAgJ9Q9dHwA4AQARAAUJtAc3UwCJAAASAAMJAwWMigBdAAAAAA==.Wasntme:BAAALgADCgYJCgABLgAFFAQJCQAVANkCAA==.',
We='Wednesday:BAACLgAFFH8nAAIZAAkJ8htQAgCtAgAZAAkJ8htQAgCtAgAuAAQKfywAAhkACAnwJBQHAKsCABkACAnwJBQHAKsCAAAA.',
Wh='Whoops:BAAALgADCgcJBwAAAA==.',
Wu='Wuxi:BAAALgAECgcJCgABLgAFFAQJEAAfABUhAA==.',
Wy='Wyldefyre:BAAALgADCggJCAAAAA==.',
['Wø']='Wøøds:BAAALgAECgQJBgAAAA==.',
Xa='Xalaria:BAAALgAECgYJDAAAAA==.Xandril:BAAALgAECgIJAgABLgAECggJFAATAPcHAA==.',
Xi='Xirek:BAABLgAECn85AAILAAkJZhEzEwC6AQALAAkJZhEzEwC6AQAAAA==.',
Yr='Yreasak:BAABLgAECn8uAAMBAAkJKQ5uSgC7AQABAAkJJQ5uSgC7AQAdAAMJFwj8GgCeAAAAAA==.Yrisan:BAAALgAECgUJBQABLgAECgkJLgABACkOAA==.',
Ys='Yseulde:BAAALgAECgcJDAABLgAECgkJLgABACkOAA==.',
Za='Zallice:BAAALgAECgEJAQAAAA==.',
Zi='Zindroz:BAAALgADCgQJBAAAAA==.',
Zo='Zonako:BAAALgAECgcJEgAAAA==.Zoogranby:BAAALgADCgYJBgAAAA==.',
Zu='Zurâ:BAABLgAECn86AAIZAAkJ/AgGJQArAQAZAAkJ/AgGJQArAQAAAA==.',
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
