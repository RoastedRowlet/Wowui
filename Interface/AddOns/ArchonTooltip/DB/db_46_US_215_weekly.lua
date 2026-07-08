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

local lookup = {'Warlock-Demonology','Rogue-Subtlety','Evoker-Augmentation','Shaman-Elemental','Paladin-Protection','Paladin-Holy','Hunter-Survival','Hunter-BeastMastery','Monk-Mistweaver','DeathKnight-Unholy','DeathKnight-Frost','Warrior-Protection','Druid-Restoration','Druid-Feral','Druid-Balance','Shaman-Restoration','Priest-Holy','Warrior-Arms','Warrior-Fury','Evoker-Devastation','Evoker-Preservation','Paladin-Retribution','Priest-Shadow','Druid-Guardian','Monk-Windwalker','DeathKnight-Blood','Hunter-Marksmanship','Unknown-Unknown','Warlock-Affliction','DemonHunter-Havoc','Shaman-Enhancement','Warlock-Destruction','Mage-Frost','Mage-Fire','DemonHunter-Devourer','Monk-Brewmaster','Rogue-Outlaw','Rogue-Assassination',}
local provider = {region='US',realm='TheScryers',name='US',type='weekly',zone=46,date='2026-07-05',data={Ad='Addi:BAAALgAFFAQJBAAAAA==.Addykikora:BAAALgADCgkJCQABLgAECggJMQABABUWAA==.Adillysse:BAAALgADCgkJCQABLgAECggJMQABABUWAA==.',
Ae='Aelin:BAAALgAECgYJBwAAAA==.Aeonmoksha:BAAALgAFFAEJAQAAAA==.',
Ai='Airo:BAABLgAECn9DAAICAAkJ1RrJDABaAgACAAkJ1RrJDABaAgAAAA==.',
Ak='Akani:BAAALgADCgQJBAAAAA==.Akaris:BAABLgAECn8jAAIDAAkJhAbgUADrAAADAAkJhAbgUADrAAAAAA==.',
Al='Alainea:BAABLgAECn83AAIEAAkJ0xEQAwCQAQAEAAkJ0xEQAwCQAQAAAA==.Alispia:BAAALgAECgQJBAAAAA==.',
Am='Amaterasu:BAABLgAFFH8RAAMFAAUJwhwxAQBNAQAFAAUJwhwxAQBNAQAGAAMJViCrJwDlAAABLgAFFAUJEQAFAMIcAA==.Ambre:BAAALgAECgkJEQAAAA==.Amerdro:BAAALgAECgQJCQAAAA==.Amoreesa:BAAALgAECgQJBAAAAA==.',
An='Andross:BAAALgAECgYJBwABLgAECgkJLgABACkOAA==.Angrytestie:BAAALgAECgUJBQAAAA==.Anomaly:BAACLgAFFH8GAAIHAAMJ0CK2GgD7AAAHAAMJ0CK2GgD7AAAuAAQKfywAAwcACAkmIksGAKACAAcACAkmIksGAKACAAgAAgl2Dja5AFAAAAEuAAUUBAkNAAEA3BwA.Anthousai:BAAALgAECgMJBAAAAA==.Antler:BAAALgADCggJCAAAAA==.',
Ar='Ara:BAABLgAFFH8TAAIJAAcJTx4dDgAqAgAJAAcJTx4dDgAqAgAAAA==.',
As='Asylum:BAAALgADCgcJDQAAAA==.',
Au='Aura:BAABLgAECn8nAAIGAAkJ0yJHAAA5AwAGAAkJ0yJHAAA5AwAAAA==.',
Ax='Axl:BAABLgAECn8vAAMKAAkJ7g4eDAANAQAKAAkJ7g4eDAANAQALAAEJ8QF2GgAhAAAAAA==.',
Ay='Aylíth:BAABLgAFFH8NAAIMAAgJDhZJAwDBAQAMAAgJDhZJAwDBAQABLgAFFAUJEQAFAMIcAA==.',
Ba='Bacon:BAAALgADCgkJCQAAAA==.Bahdeeps:BAAALgAECgcJEAAAAA==.Bahheals:BAABLgAECn8mAAMNAAcJ4QiHbQDsAAANAAcJ4QiHbQDsAAAOAAUJhQEqPQBlAAAAAA==.Banjoo:BAACLgAFFH8MAAINAAMJ6xaBEgCiAAANAAMJ6xaBEgCiAAAuAAQKfzoAAw0ACQlUHg4LAA0DAA0ACQlUHg4LAA0DAA8ABQmrEW1LAN4AAAAA.Baruk:BAACLgAFFH8LAAIQAAMJFRRySADMAAAQAAMJFRRySADMAAAuAAQKfyYAAhAACQlIE5I+ALQBABAACQlIE5I+ALQBAAAA.',
Be='Beauzericka:BAAALgADCgEJAQAAAA==.Beeswax:BAAALgADCgkJCQAAAA==.Benny:BAAALgAECgUJCgABLgAECgkJSgARAO8jAA==.',
Bi='Bigçhungi:BAABLgAECn8qAAQSAAkJ0h2qCQBTAgASAAkJmhqqCQBTAgATAAcJlxdYOgBdAQAMAAIJAQAMZAABAAABLgAFFAcJGgAKAGAgAA==.',
Bl='Blitzen:BAABLgAECn8rAAMUAAkJ3BqLBAAsAgAUAAkJ3BqLBAAsAgAVAAYJYgq9IADuAAAAAA==.',
Bo='Borealiss:BAAALgAECgkJCgABLgAECgkJKwAUANwaAA==.',
Br='Break:BAABLgAFFH8FAAIWAAUJOA5tFgAHAQAWAAUJOA5tFgAHAQABLgAFFAkJLgAWAM4lAA==.Brewjigsaw:BAAALgADCgcJCgAAAA==.',
Bu='Buffsubordie:BAAALgAFFAEJAQAAAA==.Burd:BAAALgADCgkJCQAAAA==.Bustapustule:BAAALgAFFAIJBAAAAA==.',
Bw='Bwonsamdi:BAABLgAECn9FAAIEAAgJhCATDwC2AgAEAAgJhCATDwC2AgAAAA==.',
['Bâ']='Bârks:BAABLgAECn88AAMRAAkJiSB8BQAjAwARAAkJiSB8BQAjAwAXAAEJHhKCgwA3AAAAAA==.',
['Bû']='Bûrd:BAAALgADCgkJGwAAAA==.',
Ca='Caarij:BAAALgADCgkJEAAAAA==.Callia:BAABLgAECn8cAAIWAAkJbA5OXwCyAQAWAAkJbA5OXwCyAQAAAA==.Camazotz:BAAALgADCgUJBQAAAA==.Cardkun:BAAALgADCgIJAgAAAA==.Carp:BAABLgAECn8gAAIYAAYJ4gq/QwCYAAAYAAYJ4gq/QwCYAAAAAA==.',
Ce='Celyna:BAAALgAECgMJAQAAAA==.Cerseii:BAAALgADCgUJBQAAAA==.',
Ch='Chargerkun:BAAALgAECgMJCwAAAA==.Chayda:BAAALgADCgEJAQAAAA==.Choleena:BAABLgAECn88AAIQAAkJhBiEGACFAgAQAAkJhBiEGACFAgAAAA==.',
Ci='Cindress:BAAALgADCgEJAQAAAA==.',
Co='Combat:BAABLgAECn8UAAIKAAgJtQ81hABbAQAKAAgJtQ81hABbAQAAAA==.Coojotwo:BAABLgAECn8WAAIIAAYJCwcLIAB4AAAIAAYJCwcLIAB4AAAAAA==.',
Cr='Crewd:BAAALgADCgEJAQAAAA==.Crimzon:BAAALgAECgEJAQAAAA==.Cryndle:BAAALgAECgYJBwAAAA==.',
Da='Dangerfloof:BAAALgADCgUJDAAAAA==.Dangerwithin:BAACLgAFFH8oAAMZAAkJxyRkAAA7AgAZAAkJxyRkAAA7AgAJAAEJrh2gWQBOAAAuAAQKfyYAAhkACQnKJjMAAPsDABkACQnKJjMAAPsDAAEuAAUUBQkRAAUAwhwA.Danklazercat:BAAALgADCgcJDgABLgAFFAcJGgAKAGAgAA==.Darius:BAABLgAFFH8IAAIaAAMJkA91LQCSAAAaAAMJkA91LQCSAAAAAA==.Dastinor:BAAALgAECgUJBQAAAA==.Dastraz:BAABLgAECn8UAAQUAAgJ9wfHFQC3AAAUAAUJpQbHFQC3AAAVAAUJGBRDKgCZAAADAAUJbwWPUgB+AAAAAA==.',
De='Decay:BAAALgAECgkJBgAAAA==.Deebz:BAABLgAECn83AAQHAAkJGhjODgA/AgAHAAkJVBTODgA/AgAIAAcJ/BYqbQBnAQAbAAYJQxgWFAAgAQAAAA==.Deephaven:BAAALgAECgEJAQABLgAECgcJEgAcAAAAAA==.Dena:BAAALgAECgEJAQAAAA==.Dethenor:BAAALgAECgQJBgAAAA==.Devkra:BAAALgAECgMJBgAAAA==.Deylirissa:BAAALgADCgYJBgAAAA==.',
Dm='Dmgabsorb:BAAALgADCgIJAgAAAA==.',
Do='Doge:BAAALgAECggJDQAAAA==.',
Dr='Dragoneux:BAAALgAFFAMJBgAAAQ==.Drakona:BAAALgAECgQJBgAAAA==.',
Du='Dudemachine:BAAALgADCgUJBQABLgADCgkJEwAcAAAAAA==.',
['Dè']='Dèèbz:BAAALgADCgQJBgAAAA==.',
['Dö']='Dörf:BAAALgADCgMJAwAAAA==.',
Ed='Eddison:BAAALgADCgkJDwAAAA==.',
El='Elementhor:BAAALgAECgIJAwAAAA==.',
En='Enchanted:BAACLgAFFH8SAAMKAAQJcRZhXwA2AQAKAAQJcRZhXwA2AQAaAAEJsRA2QAAwAAAuAAQKfyAAAxoACQnjGOoYAJoBABoACQmXFOoYAJoBAAoABwldGE17AG0BAAAA.Ender:BAAALgAECgcJDQAAAA==.Enháncement:BAAALgAECgYJBgAAAA==.Enid:BAACLgAFFH8oAAIaAAgJMSYKAAAFAwAaAAgJMSYKAAAFAwAuAAQKfxwAAhoACAmxJlkBAH4DABoACAmxJlkBAH4DAAAA.',
Es='Eskanor:BAAALgADCgQJBgAAAA==.',
Et='Eternalwrath:BAABLgAECn8tAAMKAAkJRBV7NAAtAgAKAAkJRBV7NAAtAgALAAUJUgu4HgDXAAAAAA==.',
Eu='Eublar:BAAALgAECgEJAQAAAA==.',
Ey='Eyemage:BAAALgADCgQJBAAAAA==.',
Fa='Falzemphx:BAAALgAECgcJDgAAAA==.Farbringer:BAAALgAECgUJBwABLgAECggJFAAUAPcHAA==.Fayanna:BAAALgADCgEJAQAAAA==.',
Fe='Felicitee:BAAALgAECgMJAwAAAA==.',
Fi='Firelight:BAAALgADCgkJGgAAAA==.',
Fo='Foxxylady:BAACLgAFFH8HAAIIAAIJdxUWfgCbAAAIAAIJdxUWfgCbAAAuAAQKfzAAAggABwkhJHQEAPABAAgABwkhJHQEAPABAAAA.',
Fr='Freyja:BAABLgAECn8YAAIPAAcJGRFpBQASAQAPAAcJGRFpBQASAQAAAA==.',
Fu='Furbees:BAAALgAECgYJEgAAAA==.',
Ge='Geenon:BAAALgAECgcJEAAAAA==.Gephen:BAAALgADCgUJBQAAAA==.',
Go='Gobrielle:BAAALgADCgkJCQAAAA==.',
Gr='Grakdeez:BAAALgAECgcJDAABLgAECgkJEwAcAAAAAA==.Grakfist:BAAALgAECgkJEwAAAA==.Graknar:BAAALgAECggJEQABLgAECgkJEwAcAAAAAA==.Graubard:BAAALgAECgYJDgAAAA==.Gravec:BAAALgADCgEJAQAAAA==.Greenspell:BAAALgAECgEJAQAAAA==.Grimswhisper:BAAALgAECgYJDQAAAA==.Gritchen:BAABLgAECn8gAAMRAAcJwRqBGgD2AQARAAcJwRqBGgD2AQAXAAMJNAKbjgAsAAAAAA==.Growler:BAAALgAECgcJEQAAAA==.Grynsel:BAABLgAECn87AAIIAAkJQRfCJQBLAgAIAAkJQRfCJQBLAgAAAA==.',
Gu='Gudeath:BAAALgAECgYJCwAAAA==.',
Ha='Harlynne:BAAALgAECggJCAAAAA==.Harukav:BAAALgAECgIJAgAAAA==.',
He='Hemmuc:BAAALgAECgYJBgABLgAECgkJKwAUANwaAA==.Hexabi:BAAALgAECgIJAgAAAA==.Hexed:BAAALgAECgEJAQAAAA==.',
Ho='Holios:BAAALgADCgYJBgABLgAFFAQJCQAXANkCAA==.',
Hu='Huntwix:BAAALgADCgYJBgAAAA==.',
Hw='Hwa:BAAALgAECgYJCQAAAA==.',
Id='Idontknow:BAACLgAFFH8JAAIXAAQJ2QKAJgDGAAAXAAQJ2QKAJgDGAAAuAAQKfy4AAhcACAm1DzktAG4BABcACAm1DzktAG4BAAAA.',
Ii='Iilia:BAAALgAECgQJBQABLgAFFAQJEQAQANAUAA==.',
In='Inwe:BAABLgAECn8lAAMOAAgJkAkmIgD4AAAOAAgJkAkmIgD4AAANAAUJtAMhoQBuAAAAAA==.',
Je='Jeemana:BAAALgADCgYJBgAAAA==.',
Jh='Jhintoki:BAAALgADCgkJCQAAAA==.',
Jo='Johnnydodge:BAABLgAECn9VAAMTAAkJcBNGAwCLAQATAAkJcBNGAwCLAQAMAAMJHQcvBwCAAAAAAA==.Jordon:BAAALgAECgQJCQAAAA==.Joyride:BAABLgAECn88AAMFAAkJnxvEBgB3AgAFAAkJnxvEBgB3AgAWAAEJ5A4kRAEyAAAAAA==.',
Ju='Jujuwing:BAABLgAECn8cAAIDAAgJrRIzLQCHAQADAAgJrRIzLQCHAQAAAA==.',
['Jù']='Jùde:BAABLgAECn8YAAQKAAYJogkiGACcAAAKAAYJ/wUiGACcAAAaAAIJWwvETwBVAAALAAEJ9gInGgAkAAAAAA==.',
Ka='Kaidastraza:BAAALgADCgcJDwAAAA==.Kaliel:BAAALgAECgQJBAAAAA==.Kalthas:BAAALgAECgEJAQAAAA==.Kanrethad:BAABLgAECn8UAAMBAAkJWyOoCwDxAgABAAkJWyOoCwDxAgAdAAEJAADMSAAAAAAAAA==.',
Ke='Kelandros:BAAALgAECgQJBAAAAA==.Kerrygan:BAABLgAECn8rAAIeAAkJIw8yGwClAQAeAAkJIw8yGwClAQAAAA==.',
Kh='Khaed:BAABLgAECn8ZAAIfAAkJHRHpEQCYAQAfAAkJHRHpEQCYAQAAAA==.',
Ki='Kicat:BAAALgAECgIJAgAAAA==.Killà:BAAALgAECgUJBQAAAA==.Kilmister:BAAALgADCgkJFwABLgAECgYJDgAcAAAAAA==.Kinara:BAAALgAECgIJAgAAAA==.',
Ko='Korthank:BAACLgAFFH8UAAIfAAQJFSHIAwCVAQAfAAQJFSHIAwCVAQAuAAQKfx0AAx8ACQlAIxwMAPEBAB8ACQlAIxwMAPEBABAAAgnxEDTXADIAAAAA.Koruka:BAAALgADCgcJCAAAAA==.Koyanskaya:BAAALgAECgUJCwAAAA==.Kozatri:BAAALgADCgcJEwAAAA==.',
Kr='Krentead:BAAALgADCgYJBgAAAA==.Krillin:BAAALgADCgMJAwAAAA==.',
Kw='Kwissy:BAABLgAECn9GAAIIAAkJwQ2lCgBKAQAIAAkJwQ2lCgBKAQAAAA==.',
La='Labellanotte:BAABLgAECn80AAMNAAkJXgX8agDzAAANAAkJXgX8agDzAAAOAAcJJwd8LgCqAAAAAA==.Lamastrasz:BAAALgAECgEJAQAAAA==.Landao:BAAALgAECgUJBgAAAA==.Lateron:BAAALgADCgYJBgAAAA==.Laturalus:BAAALgADCgUJBQAAAA==.Layssa:BAACLgAFFH8NAAIPAAMJzxZ/LQDSAAAPAAMJzxZ/LQDSAAAuAAQKfyEAAw8ACQnzGHETADkCAA8ACQnzGHETADkCAA0ABQneCFCDANEAAAAA.',
Li='Lightarrow:BAAALgAECgcJBwAAAA==.Liliania:BAABLgAECn8fAAMgAAkJlA+7CgCXAQAgAAkJlA+7CgCXAQABAAIJkgERMwEaAAAAAA==.Limper:BAAALgADCgkJGwAAAA==.Lizuket:BAAALgADCgYJCwAAAA==.',
Lo='Loveles:BAAALgADCgUJBQAAAA==.',
Lu='Lucry:BAAALgADCgkJDgAAAA==.Lucyford:BAABLgAECn82AAMGAAkJBh+SDQC6AgAGAAgJSiGSDQC6AgAWAAcJjBgWeAB+AQAAAA==.Lunafloof:BAABLgAECn8iAAMhAAgJ0R3/NwA4AgAhAAgJ0R3/NwA4AgAiAAEJORJEEwA6AAAAAA==.Lunafox:BAAALgAECgEJAQABLgAECgcJCwAcAAAAAA==.Lunaiya:BAAALgAECgUJDQAAAA==.Lunarfang:BAAALgAECgEJAQABLgAECgcJCwAcAAAAAA==.Lunarosa:BAAALgADCgkJCQABLgAECgcJCwAcAAAAAA==.Lunatic:BAAALgAECgcJCwAAAA==.',
Ly='Lyraali:BAABLgAECn8kAAIIAAkJrhZQKQA5AgAIAAkJrhZQKQA5AgAAAA==.',
Ma='Magemode:BAABLgAECn8bAAIhAAYJyCHjTgBKAgAhAAYJyCHjTgBKAgAAAA==.Maomaow:BAAALgAECgEJAgAAAA==.Mara:BAAALgAECgcJDgAAAA==.Mavramaria:BAAALgADCgYJCgAAAA==.',
Me='Melzemphx:BAABLgAECn8cAAMZAAgJege7QAD9AAAZAAgJege7QAD9AAAJAAUJrAPbjwB6AAAAAA==.',
Mi='Mikeberetta:BAAALgAECgQJBgAAAA==.Miniz:BAAALgAECgEJAQAAAA==.Minlea:BAAALgAECgEJAwAAAA==.Misirlou:BAAALgAECgYJDAABLgAECgkJKwAUANwaAA==.Mizchivf:BAAALgADCgQJBgAAAA==.',
Mo='Mogal:BAAALgADCgEJAQAAAA==.Moktezuma:BAAALgAECgQJBAAAAA==.Moosifer:BAAALgAECgEJAgABLgAECggJMQABABUWAA==.Morodos:BAAALgADCgkJFAAAAA==.',
Mu='Murtaugh:BAAALgAECggJDgAAAA==.Mutekii:BAABLgAECn8hAAIjAAgJcBFGDQDWAAAjAAgJcBFGDQDWAAAAAA==.',
Na='Natrel:BAABLgAECn8eAAMQAAYJRx6oLgD8AQAQAAYJRx6oLgD8AQAEAAYJ/QZ0ZQC1AAAAAA==.',
Ne='Neema:BAAALgAECgEJAwAAAA==.Neiru:BAAALgADCgkJGwAAAA==.Nemmael:BAAALgADCgcJDwAAAA==.',
No='Noctogero:BAAALgADCggJDAABLgAECggJLwAPAN0RAA==.Nosibm:BAAALgADCgkJJAAAAA==.Notabutt:BAAALgADCgYJBgAAAA==.',
Ny='Nyfaria:BAEALgAECgQJBAABLgAFFAUJKQAkAIodAA==.Nyxes:BAAALgADCgMJAwAAAA==.',
['Nê']='Nêo:BAAALgADCgcJBwAAAA==.',
Oc='Octane:BAAALgAECgEJAQABLgAECgcJDwAcAAAAAA==.Octozm:BAABLgAFFH8JAAIhAAIJVSUTMwDRAAAhAAIJVSUTMwDRAAAAAA==.',
Ol='Olympi:BAAALgAECgEJAwAAAA==.',
Oo='Oopsie:BAAALgADCgEJAQAAAA==.Oopzies:BAAALgADCgkJCAAAAA==.',
Or='Oreofrosting:BAAALgADCgkJEwAAAA==.',
Pa='Padraigah:BAAALgAECgYJBgAAAA==.Palmstrike:BAAALgAECgEJAQAAAA==.Pañdø:BAAALgADCgMJAwAAAA==.',
Pe='Penderrin:BAAALgAECgEJAwAAAA==.Perseffonee:BAAALgAECggJCgAAAA==.',
Pi='Pidia:BAAALgADCgUJCAAAAA==.Pippa:BAAALgAFFAQJBAAAAA==.',
Po='Popes:BAACLgAFFH8JAAMIAAQJeA72WQDxAAAIAAQJGAj2WQDxAAAbAAIJ5hEDHQCiAAAuAAQKfxgAAxsACQldG3kfACoCABsACAkZHXkfACoCAAgAAgnGE0DmAIIAAAAA.Popper:BAAALgADCgkJCwAAAA==.',
Pr='Preservation:BAACLgAFFH8HAAIDAAQJ4RpdKAApAQADAAQJ4RpdKAApAQAuAAQKfxsAAgMABwkSISQWACgCAAMABwkSISQWACgCAAAA.Prey:BAAALgADCgMJAwAAAA==.Pruina:BAAALgADCgEJAQAAAA==.',
Pu='Pub:BAABLgAECn8bAAIjAAkJCBquBQBVAQAjAAkJCBquBQBVAQAAAA==.',
Py='Pyrø:BAAALgAECgUJCgAAAA==.',
Ra='Radhika:BAAALgAECgIJAwAAAA==.Raelos:BAABLgAECn8cAAMhAAkJoRtPVADgAQAhAAYJLBtPVADgAQAiAAUJ7RkvBQBwAQAAAA==.Ragebait:BAABLgAECn88AAIWAAkJ6h02FwC4AgAWAAkJ6h02FwC4AgAAAA==.Raiha:BAAALgAECgQJBAAAAA==.Ranikina:BAABLgAECn8sAAINAAgJ8RESOgCtAQANAAgJ8RESOgCtAQAAAA==.Raynor:BAAALgAECgUJBQAAAA==.',
Re='Regasus:BAABLgAECn8hAAIEAAkJeRPqIADdAQAEAAkJeRPqIADdAQAAAA==.Rendorai:BAAALgADCgIJAQAAAA==.Revolt:BAACLgAFFH8HAAIXAAMJugkjKQC2AAAXAAMJugkjKQC2AAAuAAQKfy8AAhcACQkCH1YLAJoCABcACQkCH1YLAJoCAAAA.Reïna:BAABLgAECn8oAAIgAAgJIBCPEQAuAQAgAAgJIBCPEQAuAQAAAA==.',
Rh='Rheía:BAABLgAFFH8IAAIYAAYJvBp/BgCRAQAYAAYJvBp/BgCRAQABLgAFFAUJEQAFAMIcAA==.',
Ro='Roükai:BAAALgAECgQJBQAAAA==.',
Ry='Ryuruko:BAAALgAECgYJBgAAAA==.',
Sa='Sahariel:BAABLgAECn9KAAMRAAkJ7yN8AAAHAwARAAkJ7yN8AAAHAwAXAAcJwRPhNABFAQAAAA==.Savvy:BAAALgAECgcJBwAAAA==.',
Sc='Schwartpheil:BAAALgAECgcJEQAAAA==.Schwartzbann:BAAALgADCgcJCgABLgAECgcJEQAcAAAAAA==.Scilla:BAAALgADCgEJAQABLgAECgYJDgAcAAAAAA==.',
Se='Selieda:BAABLgAFFH8FAAIBAAMJzAg4NgB6AAABAAMJzAg4NgB6AAAAAA==.',
Sh='Shadereaver:BAAALgADCgcJBwAAAA==.Shadowballz:BAAALgAECggJEgAAAA==.Shadowwing:BAAALgAECgMJBwAAAA==.Shamnorris:BAAALgADCgQJBAAAAA==.Shardemma:BAAALgADCgkJLwAAAA==.Shelfy:BAAALgAECgQJDwAAAA==.Shimmerly:BAAALgAECgcJDwAAAA==.Shocktop:BAAALgAECgEJAwAAAA==.Shreddedbeef:BAAALgADCgcJBwAAAA==.Shytningbolt:BAAALgADCgMJAgAAAA==.Shælyn:BAAALgAECgMJBgAAAA==.',
Si='Sintara:BAAALgAECgEJAQAAAA==.',
Sk='Skitzo:BAAALgADCgkJFgAAAA==.',
Sp='Spacelord:BAAALgADCgUJBQAAAA==.Spinetaker:BAABLgAECn8zAAIZAAgJGSKpCwCHAgAZAAgJGSKpCwCHAgABLgAFFAcJGgAKAGAgAA==.Spyder:BAAALgADCgQJBAAAAA==.',
St='Stolensouls:BAABLgAECn8wAAMgAAgJUQ8WEgAnAQAgAAgJUQ8WEgAnAQABAAIJHAJrZQEaAAAAAA==.Strawkun:BAAALgAECgIJAwAAAA==.',
Su='Sunaris:BAAALgADCgUJBQABLgAECggJLwAPAN0RAA==.Suneater:BAAALgAECggJDQAAAA==.',
['Sç']='Sçruffy:BAACLgAFFH8aAAMKAAcJYCCDGQAXAgAKAAYJYCCDGQAXAgAaAAEJAAB4EwBXAAAuAAQKf0oAAxoACQmpJtUAAGMDAAoACQmBJgsFAIMDABoACQmxJdUAAGMDAAAA.',
Ta='Taeva:BAAALgAECgEJAQAAAA==.Tahtiania:BAAALgADCggJDQAAAA==.Talas:BAAALgADCgEJAQAAAA==.Taliesin:BAAALgADCgUJBQAAAA==.',
Te='Teldryn:BAACLgAFFH8gAAITAAUJnx7wFgBZAQATAAUJnx7wFgBZAQAuAAQKfyYAAxMACQkeJEwHADMDABMACQkeJEwHADMDABIAAQneGNc5AEkAAAAA.Telios:BAAALgAECgQJBQAAAA==.',
Th='Thaer:BAAALgADCgYJDAAAAA==.Thorendire:BAABLgAECn86AAIeAAkJiRJGFgDXAQAeAAkJiRJGFgDXAQAAAA==.Thundoor:BAAALgADCgkJCQAAAA==.',
Ti='Tirnz:BAABLgAECn8vAAILAAkJ3QuOEABuAQALAAkJ3QuOEABuAQAAAA==.',
To='Tohotstotrot:BAAALgADCgQJBAABLgADCgcJBwAcAAAAAA==.Torlana:BAAALgAECgQJBAAAAA==.',
Tr='Trafaros:BAAALgADCgMJAwAAAA==.Trilldh:BAAALgAECgcJBQAAAA==.Trixielou:BAAALgAECggJEgAAAA==.',
Tt='Ttattoo:BAEBLgAECn8YAAMkAAYJ5QcwUADBAAAkAAYJ5QcwUADBAAAZAAEJqALpwAAXAAABLgAECgkJGAAKADgPAA==.Ttattooz:BAEBLgAECn8YAAIKAAkJOA8PTQDbAQAKAAkJOA8PTQDbAQAAAA==.',
Ty='Tyramonde:BAAALgAECgYJCQAAAA==.',
Ub='Ubonrebu:BAAALgAFFAEJAQAAAA==.',
Ud='Udb:BAAALgAFFAEJAgABLgAFFAMJBgACAN8fAA==.',
Va='Vaelestrix:BAACLgAFFH8mAAQCAAgJESA3BQBrAgACAAcJMSQ3BQBrAgAlAAMJDByfCADzAAAmAAEJUQcsBgBdAAAuAAQKf0QAAwIACQn4JW4AAOUDAAIACQn4JW4AAOUDACYAAQnuJS8eAGsAAAAA.Vain:BAAALgAECgIJAgAAAA==.Valamaldoran:BAAALgADCgkJCQAAAA==.Valholla:BAAALgADCgMJAwAAAA==.Vashtanerada:BAAALgADCgYJCgAAAA==.',
Ve='Veilish:BAAALgADCgYJCQAAAA==.',
Vo='Voiddøøde:BAAALgAECgUJBQAAAA==.Voidsocket:BAAALgAECgcJBgAAAA==.Voidtoes:BAAALgAECgQJBAAAAA==.',
Vu='Vulpvs:BAAALgAECgEJAQAAAA==.',
Vv='Vvlpvs:BAAALgADCgQJBAAAAA==.',
Vy='Vyral:BAAALgAFFAEJAQAAAA==.',
Wa='Warherald:BAABLgAECn8iAAQMAAgJ9Q9dHwA4AQAMAAgJ9Q9dHwA4AQASAAUJtAc5UwCJAAATAAMJAwWPigBdAAAAAA==.Wasntme:BAAALgADCgYJCgABLgAFFAQJCQAXANkCAA==.',
We='Wednesday:BAACLgAFFH8uAAIaAAkJyxxLAgCtAgAaAAkJyxxLAgCtAgAuAAQKfywAAhoACAnwJBEHAKsCABoACAnwJBEHAKsCAAAA.',
Wh='Whoops:BAAALgADCgcJBwAAAA==.',
Wu='Wuxi:BAAALgAECgcJCgABLgAFFAQJFAAfABUhAA==.',
Wy='Wyldefyre:BAAALgADCggJCAAAAA==.',
['Wø']='Wøøds:BAAALgAECgQJBwAAAA==.',
Xa='Xalaria:BAAALgAECgYJDAAAAA==.Xandril:BAAALgAECgMJAgABLgAECggJFAAUAPcHAA==.',
Xi='Xirek:BAABLgAECn88AAIMAAkJZhEzEwC6AQAMAAkJZhEzEwC6AQAAAA==.',
Yr='Yreasak:BAABLgAECn8uAAMBAAkJKQ5uSgC7AQABAAkJJQ5uSgC7AQAdAAMJFwj8GgCeAAAAAA==.Yrisan:BAAALgAECgUJBQABLgAECgkJLgABACkOAA==.',
Ys='Yseulde:BAAALgAECgcJDAABLgAECgkJLgABACkOAA==.',
Za='Zallice:BAAALgAECgEJAQAAAA==.',
Zi='Zindroz:BAAALgADCgUJBwAAAA==.',
Zo='Zonako:BAAALgAECgcJEgAAAA==.Zoogranby:BAAALgADCgYJBgAAAA==.',
Zu='Zurâ:BAABLgAECn8/AAIaAAkJCgkHJQArAQAaAAkJCgkHJQArAQAAAA==.',
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
