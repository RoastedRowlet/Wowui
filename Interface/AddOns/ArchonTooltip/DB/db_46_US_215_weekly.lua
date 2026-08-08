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
local provider = {region='US',realm='TheScryers',name='US',type='weekly',zone=46,date='2026-08-04',data={Ad='Addi:BAAALgAFFAQJBAAAAA==.Addykikora:BAAALgADCgkJCQABLgAECgkJOAABAMEXAA==.Adillysse:BAAALgADCgkJCQABLgAECgkJOAABAMEXAA==.',
Ae='Aelin:BAAALgAECgYJBwAAAA==.Aeonmoksha:BAAALgAFFAEJAQAAAA==.',
Ai='Airo:BAABLgAECn9EAAICAAkJ1RrJDABaAgACAAkJ1RrJDABaAgAAAA==.',
Ak='Akani:BAAALgADCgQJBAAAAA==.Akaris:BAABLgAECn8jAAIDAAkJhAbgUADrAAADAAkJhAbgUADrAAAAAA==.',
Al='Alainea:BAABLgAECn83AAIEAAkJ0xGoBQCTAQAEAAkJ0xGoBQCTAQAAAA==.Alispia:BAAALgAECgQJBAAAAA==.',
Am='Amaterasu:BAABLgAFFH8RAAMFAAUJwhwOAwAwAQAFAAUJwhwOAwAwAQAGAAMJViCrJwDlAAABLgAFFAUJEQAFAMIcAA==.Ambre:BAAALgAECgkJEQAAAA==.Amerdro:BAAALgAECgQJCQAAAA==.Amoreesa:BAAALgAECgQJBAAAAA==.',
An='Andross:BAAALgAECgYJBwABLgAECgkJLgABACkOAA==.Angrytestie:BAAALgAECgUJBQAAAA==.Anomaly:BAACLgAFFH8GAAIHAAMJ0CK2GgD7AAAHAAMJ0CK2GgD7AAAuAAQKfywAAwcACAkmIksGAKACAAcACAkmIksGAKACAAgAAgl2Dja5AFAAAAEuAAUUBAkNAAEA3BwA.Antler:BAAALgADCggJCAAAAA==.',
Ar='Ara:BAABLgAFFH8VAAIJAAgJoR4dDgAqAgAJAAgJoR4dDgAqAgAAAA==.',
As='Asylum:BAAALgADCgcJDQAAAA==.',
Au='Aura:BAABLgAECn82AAIGAAkJ9yM/AACjAwAGAAkJ9yM/AACjAwAAAA==.',
Ax='Axl:BAABLgAECn8vAAMKAAkJ7g4NFQABAQAKAAkJ7g4NFQABAQALAAEJ8QF2GgAhAAAAAA==.',
Ay='Aylíth:BAABLgAFFH8nAAIMAAkJEh2BAgBkAgAMAAkJEh2BAgBkAgABLgAFFAUJEQAFAMIcAA==.',
Ba='Bacon:BAAALgADCgkJCQAAAA==.Bahdeeps:BAAALgAECgcJEAAAAA==.Bahheals:BAABLgAECn8uAAMNAAgJbwtECwDyAAANAAgJbwtECwDyAAAOAAUJhQEqPQBlAAAAAA==.Banjoo:BAACLgAFFH8PAAINAAMJLhvwFgC5AAANAAMJLhvwFgC5AAAuAAQKf0cAAw0ACQlQIQ4LAA0DAA0ACQlQIQ4LAA0DAA8ABgkqGEcJACEBAAAA.Baruk:BAACLgAFFH8PAAIQAAMJ1xRySADMAAAQAAMJ1xRySADMAAAuAAQKfyYAAhAACQlIE5I+ALQBABAACQlIE5I+ALQBAAAA.',
Be='Beauzericka:BAAALgADCgEJAQAAAA==.Beeswax:BAAALgADCgkJCQAAAA==.Benny:BAAALgAECgcJEQABLgAECgkJUwARAMckAA==.',
Bi='Bigçhungi:BAABLgAECn8qAAQSAAkJ0h2qCQBTAgASAAkJmhqqCQBTAgATAAcJlxdYOgBdAQAMAAIJAQAMZAABAAABLgAFFAgJHQAKADkfAA==.',
Bl='Blitzen:BAABLgAECn8rAAMUAAkJ3BqLBAAsAgAUAAkJ3BqLBAAsAgAVAAYJYgq9IADuAAAAAA==.',
Bo='Borealiss:BAAALgAECgkJCgABLgAECgkJKwAUANwaAA==.',
Br='Break:BAABLgAFFH8FAAIWAAUJOA5CJAD6AAAWAAUJOA5CJAD6AAABLgAFFAkJRgAWAOQlAA==.Brewjigsaw:BAAALgADCgcJCgAAAA==.',
Bu='Buffsubordie:BAAALgAFFAEJAQAAAA==.Burd:BAAALgADCgkJCQAAAA==.Bustapustule:BAAALgAFFAIJBAAAAA==.',
Bw='Bwonsamdi:BAABLgAECn9HAAIEAAgJhCATDwC2AgAEAAgJhCATDwC2AgAAAA==.',
['Bâ']='Bârks:BAABLgAECn89AAMRAAkJiSB8BQAjAwARAAkJiSB8BQAjAwAXAAEJHhKCgwA3AAAAAA==.',
['Bû']='Bûrd:BAAALgADCgkJGwAAAA==.',
Ca='Caarij:BAAALgADCgkJEQAAAA==.Callia:BAABLgAECn8cAAIWAAkJbA5OXwCyAQAWAAkJbA5OXwCyAQAAAA==.Camazotz:BAAALgADCgUJBQAAAA==.Cardkun:BAAALgADCgIJAgAAAA==.Carp:BAABLgAECn8gAAIYAAYJ4gq/QwCYAAAYAAYJ4gq/QwCYAAAAAA==.',
Ce='Celorana:BAAALgAFFAIJAgAAAA==.Celyna:BAAALgAECgMJAQAAAA==.Cerseii:BAAALgADCgUJBQAAAA==.',
Ch='Chargerkun:BAAALgAECgMJCwAAAA==.Chayda:BAAALgADCgEJAQAAAA==.Choleena:BAABLgAECn89AAIQAAkJhBiEGACFAgAQAAkJhBiEGACFAgAAAA==.',
Ci='Cindress:BAAALgADCgEJAQAAAA==.',
Co='Combat:BAABLgAECn8UAAIKAAgJtQ81hABbAQAKAAgJtQ81hABbAQAAAA==.Conall:BAAALgAECgEJAQAAAA==.Coojotwo:BAABLgAECn8WAAIIAAYJCwdRrADqAAAIAAYJCwdRrADqAAAAAA==.',
Cr='Crewd:BAAALgADCgEJAQAAAA==.Crimzon:BAAALgAECgEJAQAAAA==.Cryndle:BAAALgAECgYJCgAAAA==.',
Da='Dangerfloof:BAAALgADCgUJDAAAAA==.Dangerwithin:BAACLgAFFH8oAAMZAAkJxyRkAAA7AgAZAAkJxyRkAAA7AgAJAAEJrh2gWQBOAAAuAAQKfyYAAhkACQnKJjMAAPsDABkACQnKJjMAAPsDAAEuAAUUBQkRAAUAwhwA.Danklazercat:BAAALgADCgcJDgABLgAFFAgJHQAKADkfAA==.Darius:BAABLgAFFH8IAAIaAAMJkA91LQCSAAAaAAMJkA91LQCSAAAAAA==.Dastinor:BAAALgAECgUJBQAAAA==.Dastraz:BAABLgAECn8UAAQUAAgJ9wfHFQC3AAAUAAUJpQbHFQC3AAAVAAUJGBRDKgCZAAADAAUJbwWPUgB+AAAAAA==.',
De='Decay:BAAALgAECgkJBgAAAA==.Deebz:BAABLgAECn83AAQHAAkJGhjODgA/AgAHAAkJVBTODgA/AgAIAAcJ/BYqbQBnAQAbAAYJQxgWFAAgAQAAAA==.Deephaven:BAAALgAECgEJAQABLgAECgcJEgAcAAAAAA==.Dena:BAAALgAECgEJAQAAAA==.Dethenor:BAAALgAECgQJBgAAAA==.Deux:BAAALgADCgIJAgAAAA==.Devkra:BAAALgAECgYJDwAAAA==.Deylirissa:BAAALgADCgYJBgAAAA==.',
Dh='Dharma:BAAALgAECgEJAQAAAA==.',
Dm='Dmgabsorb:BAAALgADCgIJAgAAAA==.',
Do='Doge:BAAALgAECggJDQAAAA==.',
Dr='Dragoneux:BAAALgAFFAMJBgAAAQ==.Drakona:BAAALgAECgQJCAAAAA==.',
Du='Dudemachine:BAAALgADCgUJBQABLgADCgkJEwAcAAAAAA==.',
['Dè']='Dèèbz:BAAALgADCgQJBgAAAA==.',
['Dö']='Dörf:BAAALgADCgkJDAAAAA==.',
Ed='Eddison:BAAALgAECgYJBgAAAA==.',
El='Elementhor:BAAALgAECgIJAwAAAA==.',
En='Enchanted:BAACLgAFFH8UAAMKAAQJoBdhXwA2AQAKAAQJoBdhXwA2AQAaAAEJsRA2QAAwAAAuAAQKfyAAAxoACQnjGOoYAJoBABoACQmXFOoYAJoBAAoABwldGE17AG0BAAAA.Ender:BAAALgAECgcJDQAAAA==.Enháncement:BAAALgAECgcJBwAAAA==.Enid:BAACLgAFFH8oAAIaAAgJMSYKAAAFAwAaAAgJMSYKAAAFAwAuAAQKfxwAAhoACAmxJlkBAH4DABoACAmxJlkBAH4DAAAA.',
Es='Eskanor:BAAALgADCgQJBgAAAA==.',
Et='Eternalwrath:BAABLgAECn8tAAMKAAkJRBV7NAAtAgAKAAkJRBV7NAAtAgALAAUJUgu4HgDXAAAAAA==.',
Eu='Eublar:BAAALgAECgEJAQAAAA==.',
Ey='Eyemage:BAAALgADCgQJBAAAAA==.',
Fa='Falzemphx:BAAALgAECgcJDgAAAA==.Farbringer:BAAALgAECgUJBwABLgAECggJFAAUAPcHAA==.Fayanna:BAAALgADCgEJAQAAAA==.',
Fe='Felicitee:BAAALgAECgMJAwAAAA==.Felmary:BAAALgAECgYJBwAAAA==.',
Fi='Firelight:BAAALgADCgkJGgAAAA==.',
Fo='Foxxylady:BAACLgAFFH8HAAIIAAIJdxUWfgCbAAAIAAIJdxUWfgCbAAAuAAQKfzUAAggACQkXJAYDAMQCAAgACQkXJAYDAMQCAAAA.',
Fr='Freyja:BAABLgAECn8YAAIPAAcJGRHuCgAAAQAPAAcJGRHuCgAAAQAAAA==.',
Fu='Furbees:BAAALgAECgYJEgAAAA==.',
Ge='Geenon:BAAALgAECggJEQAAAA==.Gephen:BAAALgADCgUJBQAAAA==.',
Go='Gobrielle:BAAALgADCgkJCQAAAA==.',
Gr='Grakdeez:BAAALgAECgcJDAABLgAECgkJEwAcAAAAAA==.Grakfist:BAAALgAECgkJEwAAAA==.Graknar:BAAALgAECggJEQABLgAECgkJEwAcAAAAAA==.Graubard:BAABLgAECn8UAAIWAAYJ6Q2BHgDfAAAWAAYJ6Q2BHgDfAAAAAA==.Gravec:BAAALgADCgEJAQAAAA==.Greenspell:BAAALgAECgEJAQAAAA==.Grimswhisper:BAAALgAECgYJDQAAAA==.Gritchen:BAABLgAECn8gAAMRAAcJwRqBGgD2AQARAAcJwRqBGgD2AQAXAAMJNAKbjgAsAAAAAA==.Growler:BAAALgAECgcJEQAAAA==.Grynsel:BAABLgAECn88AAIIAAkJSRfCJQBLAgAIAAkJSRfCJQBLAgAAAA==.',
Gu='Gudeath:BAAALgAECgYJCwAAAA==.',
Ha='Harlynne:BAABLgAECn8XAAIBAAgJ4AtjDAAvAQABAAgJ4AtjDAAvAQAAAA==.Harukav:BAAALgAECgIJAgAAAA==.Hatyrr:BAAALgAECgEJAQAAAA==.',
He='Hemmuc:BAAALgAECgYJBgABLgAECgkJKwAUANwaAA==.Hexabi:BAAALgAECgIJAgAAAA==.Hexed:BAAALgAECgEJAQAAAA==.',
Ho='Holios:BAAALgADCgYJBgABLgAFFAQJCQAXANkCAA==.',
Hu='Huntwix:BAAALgADCgYJBgAAAA==.',
Hw='Hwa:BAAALgAECgYJDQAAAA==.',
Id='Idontknow:BAACLgAFFH8JAAIXAAQJ2QKAJgDGAAAXAAQJ2QKAJgDGAAAuAAQKfy4AAhcACAm1DzktAG4BABcACAm1DzktAG4BAAAA.',
Ii='Iilia:BAAALgAECgQJBQABLgAFFAQJEQAQANAUAA==.',
In='Ineedmana:BAAALgADCgEJAQAAAA==.Inwe:BAABLgAECn8qAAMOAAkJSAsICAC7AAAOAAkJSAsICAC7AAANAAUJtAMhoQBuAAAAAA==.',
Je='Jeemana:BAAALgADCgYJBgAAAA==.Jellycannon:BAAALgAECgYJBgABLgAFFAkJQwACAFAkAA==.Jesmarie:BAAALgAECgEJAQAAAA==.',
Jh='Jhintoki:BAAALgADCgkJCQAAAA==.',
Ji='Jiraca:BAAALgADCgEJAQAAAA==.',
Jo='Johnnydodge:BAABLgAECn9VAAMTAAkJcBPiBQCLAQATAAkJcBPiBQCLAQAMAAMJHQcOCwCOAAAAAA==.Jordon:BAAALgAECgQJCgAAAA==.Joridan:BAAALgAECgcJCgAAAA==.Joyride:BAABLgAECn89AAMFAAkJ2hvEBgB3AgAFAAkJ2hvEBgB3AgAWAAEJ5A4kRAEyAAAAAA==.',
Ju='Juiceboxx:BAAALgAECgcJAQAAAA==.Jujuwing:BAABLgAECn8eAAIDAAgJrRIzLQCHAQADAAgJrRIzLQCHAQAAAA==.Julius:BAAALgADCgkJCQABLgAECgkJNgAGAPcjAA==.',
['Jù']='Jùde:BAABLgAECn8bAAQKAAYJ4wryJgCXAAAKAAYJQAfyJgCXAAAaAAQJ5wnrFQBBAAALAAEJ9gInGgAkAAAAAA==.',
Ka='Kaidastraza:BAAALgADCgcJDwAAAA==.Kaliel:BAAALgAECgQJBAAAAA==.Kalthas:BAAALgAECgEJAQAAAA==.Kanrethad:BAABLgAECn8UAAMBAAkJWyOoCwDxAgABAAkJWyOoCwDxAgAdAAEJAADMSAAAAAAAAA==.',
Ke='Kelandros:BAAALgAECgQJBAABLgAECgkJUwARAMckAA==.Kerrygan:BAABLgAECn8rAAIeAAkJIw8yGwClAQAeAAkJIw8yGwClAQAAAA==.',
Kh='Khaed:BAABLgAECn8ZAAIfAAkJHRHpEQCYAQAfAAkJHRHpEQCYAQAAAA==.',
Ki='Kicat:BAAALgAECgQJBAAAAA==.Killà:BAAALgAECgUJBQAAAA==.Kilmister:BAAALgADCgkJFwABLgAECgYJFAAWAOkNAA==.Kinara:BAAALgAECgIJAgAAAA==.',
Ko='Korthank:BAACLgAFFH8UAAIfAAQJFSHIAwCVAQAfAAQJFSHIAwCVAQAuAAQKfx0AAx8ACQlAIxwMAPEBAB8ACQlAIxwMAPEBABAAAgnxEDTXADIAAAAA.Koruka:BAAALgADCgcJCAAAAA==.Koyanskaya:BAAALgAECgYJDQAAAA==.Kozatri:BAAALgADCgcJEwAAAA==.',
Kr='Krentead:BAAALgADCgYJBgAAAA==.Krillin:BAAALgADCgMJAwAAAA==.',
Kw='Kwissy:BAABLgAECn9QAAIIAAkJEQ73DgB2AQAIAAkJEQ73DgB2AQAAAA==.',
La='Labellanotte:BAABLgAECn80AAMNAAkJXgX8agDzAAANAAkJXgX8agDzAAAOAAcJJwd8LgCqAAAAAA==.Lamastrasz:BAAALgAECgEJAQAAAA==.Landao:BAAALgAECgUJBgAAAA==.Lateron:BAAALgADCgYJBgAAAA==.Laturalus:BAAALgAECgUJBQAAAA==.Layssa:BAACLgAFFH8OAAIPAAMJzxZ/LQDSAAAPAAMJzxZ/LQDSAAAuAAQKfyEAAw8ACQnzGHETADkCAA8ACQnzGHETADkCAA0ABQneCFCDANEAAAAA.',
Li='Lightarrow:BAAALgAECgcJBwAAAA==.Liliania:BAABLgAECn8fAAMgAAkJlA+7CgCXAQAgAAkJlA+7CgCXAQABAAIJkgERMwEaAAAAAA==.Limper:BAAALgADCgkJGwAAAA==.Lizuket:BAAALgADCgYJCwAAAA==.',
Lo='Loveles:BAAALgADCgUJBQAAAA==.',
Lu='Lucry:BAAALgADCgkJDgAAAA==.Lucyford:BAABLgAECn85AAMGAAkJBh+SDQC6AgAGAAgJSiGSDQC6AgAWAAcJjBgWeAB+AQAAAA==.Lunafloof:BAABLgAECn8iAAMhAAgJ0R3/NwA4AgAhAAgJ0R3/NwA4AgAiAAEJORJEEwA6AAAAAA==.Lunafox:BAAALgAECgEJAQABLgAECgcJDAAcAAAAAA==.Lunaiya:BAAALgAECgUJDQAAAA==.Lunarfang:BAAALgAECgEJAQABLgAECgcJDAAcAAAAAA==.Lunarosa:BAAALgADCgkJCQABLgAECgcJDAAcAAAAAA==.Lunatic:BAAALgAECgcJDAAAAA==.Luvox:BAAALgAFFAEJAgAAAA==.',
Ly='Lyraali:BAABLgAECn8lAAIIAAkJvRZQKQA5AgAIAAkJvRZQKQA5AgAAAA==.',
Ma='Magemode:BAACLgAFFH8GAAIhAAYJAhsAGACvAQAhAAYJAhsAGACvAQAuAAQKfxwAAiEABgnIIeNOAEoCACEABgnIIeNOAEoCAAAA.Maomaow:BAAALgAECgUJCQAAAA==.Mara:BAAALgAECgcJDgAAAA==.Martyrion:BAAALgAECgEJAQAAAA==.Mavramaria:BAAALgADCgYJCgAAAA==.',
Me='Melzemphx:BAABLgAECn8cAAMZAAgJege7QAD9AAAZAAgJege7QAD9AAAJAAUJrAPbjwB6AAAAAA==.',
Mi='Mikeberetta:BAAALgAECgQJBgAAAA==.Miniz:BAAALgAECgEJAQAAAA==.Minlea:BAAALgAECgUJCwAAAA==.Mishacal:BAAALgADCgUJBQAAAA==.Misirlou:BAAALgAECgYJDAABLgAECgkJKwAUANwaAA==.Mizchivf:BAAALgADCgQJBgAAAA==.',
Mo='Mogal:BAAALgADCgEJAQAAAA==.Moktezuma:BAAALgAECgQJBAAAAA==.Moosifer:BAAALgAECgMJBQABLgAECgkJOAABAMEXAA==.Morodos:BAAALgADCgkJFAAAAA==.',
Mu='Murtaugh:BAAALgAECggJDgAAAA==.Mutekii:BAABLgAECn8hAAIjAAgJcBE2ZABfAQAjAAgJcBE2ZABfAQAAAA==.',
Na='Natrel:BAABLgAECn8eAAMQAAYJRx6oLgD8AQAQAAYJRx6oLgD8AQAEAAYJ/QZ0ZQC1AAAAAA==.',
Ne='Neema:BAAALgAECgEJAwAAAA==.Neiru:BAAALgADCgkJGwAAAA==.Nek:BAAALgADCgcJDQAAAA==.Nemmael:BAAALgADCgcJDwAAAA==.',
No='Noctogero:BAAALgADCggJDAABLgAECggJLwAPAN0RAA==.Nosibm:BAAALgADCgkJJwAAAA==.Notabutt:BAAALgADCgYJBgAAAA==.',
Ny='Nyfaria:BAEALgAECgQJBAABLgAFFAUJKQAkAIodAA==.Nyxes:BAAALgADCgMJAwAAAA==.',
['Nê']='Nêo:BAAALgADCgcJBwAAAA==.',
Oc='Octane:BAAALgAECgEJAQABLgAECgcJDwAcAAAAAA==.Octozm:BAABLgAFFH8JAAIhAAIJVSUTMwDRAAAhAAIJVSUTMwDRAAAAAA==.',
Ol='Olympi:BAAALgAECgIJBAAAAA==.',
Oo='Oopsie:BAAALgAECgIJAgAAAA==.Oopzies:BAAALgAECgIJAgAAAA==.',
Or='Oreofrosting:BAAALgADCgkJEwAAAA==.',
Ox='Oxana:BAAALgADCggJCAAAAA==.',
Pa='Padraigah:BAAALgAECgYJBgAAAA==.Palmstrike:BAAALgAECgEJAQAAAA==.Pañdø:BAAALgADCgMJAwAAAA==.',
Pe='Penderrin:BAAALgAECgYJDQAAAA==.Perseffonee:BAAALgAECgkJEAAAAA==.',
Pi='Pidia:BAAALgADCgUJCAAAAA==.Pippa:BAABLgAFFH8IAAIMAAQJCQg/DwC5AAAMAAQJCQg/DwC5AAABLgAFFAkJMwAaANAcAA==.',
Po='Popes:BAACLgAFFH8JAAMIAAQJeA72WQDxAAAIAAQJGAj2WQDxAAAbAAIJ5hEDHQCiAAAuAAQKfxgAAxsACQldG3kfACoCABsACAkZHXkfACoCAAgAAgnGE0DmAIIAAAAA.Popper:BAAALgADCgkJCwAAAA==.',
Pr='Preservation:BAACLgAFFH8HAAIDAAQJ4RpdKAApAQADAAQJ4RpdKAApAQAuAAQKfxsAAgMABwkSISQWACgCAAMABwkSISQWACgCAAAA.Pruina:BAAALgADCgEJAQAAAA==.Préy:BAAALgADCgMJAwAAAA==.',
Pu='Pub:BAABLgAECn8bAAIjAAkJCBpcCgBOAQAjAAkJCBpcCgBOAQAAAA==.',
Py='Pyrø:BAAALgAECgUJCgAAAA==.Pyzemphx:BAAALgAECgEJAwAAAA==.',
Ra='Radhika:BAAALgAECgIJAwAAAA==.Raelos:BAABLgAECn8cAAMhAAkJoRtPVADgAQAhAAYJLBtPVADgAQAiAAUJ7RkvBQBwAQAAAA==.Ragebait:BAABLgAECn89AAIWAAkJ6h02FwC4AgAWAAkJ6h02FwC4AgAAAA==.Raiha:BAAALgAECgQJBAAAAA==.Ranikina:BAABLgAECn80AAINAAkJyBJkBQCmAQANAAkJyBJkBQCmAQAAAA==.Raynor:BAAALgAECgUJBQAAAA==.',
Re='Regasus:BAABLgAECn8hAAIEAAkJeRPqIADdAQAEAAkJeRPqIADdAQAAAA==.Rendorai:BAAALgADCgIJAQAAAA==.Revolt:BAACLgAFFH8HAAIXAAMJugkjKQC2AAAXAAMJugkjKQC2AAAuAAQKfy8AAhcACQkCH1YLAJoCABcACQkCH1YLAJoCAAAA.Reïna:BAABLgAECn8rAAIgAAkJjA9jAwBOAQAgAAkJjA9jAwBOAQAAAA==.',
Rh='Rheía:BAABLgAFFH8JAAIYAAYJvBp/BgCRAQAYAAYJvBp/BgCRAQABLgAFFAUJEQAFAMIcAA==.',
Ro='Rock:BAAALgADCgQJBAAAAA==.Roükai:BAAALgAECgQJBQAAAA==.',
Ry='Ryuruko:BAAALgAECgYJBgAAAA==.',
Sa='Sahariel:BAABLgAECn9TAAMRAAkJxyTcAgBrAwARAAkJxyTcAgBrAwAXAAcJwRPhNABFAQAAAA==.Savvy:BAAALgAFFAEJAgAAAA==.',
Sc='Schwartpheil:BAAALgAECgcJEQAAAA==.Schwartzbann:BAAALgADCgcJCgABLgAECgcJEQAcAAAAAA==.Scilla:BAAALgADCgEJAQABLgAECgYJFAAWAOkNAA==.Scumbaggro:BAAALgAECgQJBAAAAA==.',
Se='Seff:BAAALgAECgEJAQABLgAECgkJEAAcAAAAAA==.Selieda:BAABLgAFFH8IAAIBAAQJhwiXKQDnAAABAAQJhwiXKQDnAAAAAA==.',
Sh='Shadereaver:BAAALgADCgkJIQAAAA==.Shadowballz:BAAALgAECggJEgAAAA==.Shadowwing:BAAALgAECgMJBwAAAA==.Shakara:BAAALgAECgEJAQAAAA==.Shamnorris:BAAALgADCgQJBAAAAA==.Shardemma:BAAALgAECgYJEgAAAA==.Shelfy:BAAALgAECgQJDwAAAA==.Shimmerly:BAAALgAECgcJDwAAAA==.Shocktop:BAAALgAECgEJAwAAAA==.Shreddedbeef:BAAALgADCgcJBwAAAA==.Shytningbolt:BAAALgADCgMJAgAAAA==.Shælyn:BAAALgAECgMJBgAAAA==.',
Si='Silent:BAAALgAECgcJBwAAAA==.Sintara:BAAALgAFFAEJAQAAAA==.',
Sk='Skitzo:BAAALgADCgkJFgAAAA==.',
Sp='Spacelord:BAAALgADCgUJBQAAAA==.Spinetaker:BAABLgAECn8zAAIZAAgJGSKpCwCHAgAZAAgJGSKpCwCHAgABLgAFFAgJHQAKADkfAA==.Spyder:BAAALgADCgQJBAAAAA==.',
St='Stolensouls:BAABLgAECn8zAAMgAAkJxhC7AgB4AQAgAAkJxhC7AgB4AQABAAIJHAJrZQEaAAAAAA==.Strawkun:BAAALgAECgIJAwAAAA==.',
Su='Sunaris:BAAALgADCgUJBQABLgAECggJLwAPAN0RAA==.Suneater:BAAALgAECggJDQAAAA==.',
Sy='Syd:BAAALgADCggJCgAAAA==.',
['Sç']='Sçruffy:BAACLgAFFH8dAAMKAAgJOR+DGQAXAgAKAAcJ3B2DGQAXAgAaAAMJERcJFwCdAAAuAAQKf0oAAxoACQmpJtUAAGMDAAoACQmBJgsFAIMDABoACQmxJdUAAGMDAAAA.',
Ta='Taeva:BAAALgAECgEJAQAAAA==.Tahtiania:BAAALgAECgYJBgAAAA==.Talas:BAAALgADCgEJAQAAAA==.Taliesin:BAAALgADCgUJBQAAAA==.Taroman:BAAALgAECgkJAgAAAA==.',
Te='Teldryn:BAACLgAFFH8gAAITAAUJnx7wFgBZAQATAAUJnx7wFgBZAQAuAAQKfyYAAxMACQkeJEwHADMDABMACQkeJEwHADMDABIAAQneGNc5AEkAAAAA.Telios:BAAALgAECgQJBQAAAA==.',
Th='Thaer:BAAALgADCgYJDAAAAA==.Thorendire:BAABLgAECn86AAIeAAkJiRJGFgDXAQAeAAkJiRJGFgDXAQAAAA==.Thundoor:BAAALgADCgkJEgAAAA==.',
Ti='Tiniri:BAAALgADCgkJEgAAAA==.Tirnz:BAABLgAECn83AAILAAkJKQ6OEABuAQALAAkJKQ6OEABuAQAAAA==.',
Tl='Tlachtga:BAAALgAECgMJAwAAAA==.',
To='Tohotstotrot:BAAALgADCgQJBAABLgAECgMJAwAcAAAAAA==.Torlana:BAAALgAECgQJBAAAAA==.',
Tr='Trafaros:BAAALgADCgMJAwAAAA==.Trilldh:BAAALgAECgcJBQAAAA==.Trixielou:BAAALgAECggJEgAAAA==.',
Tt='Ttattoo:BAEBLgAECn8YAAMkAAYJ5QcwUADBAAAkAAYJ5QcwUADBAAAZAAEJqALpwAAXAAABLgAECgkJGAAKADgPAA==.Ttattooz:BAEBLgAECn8YAAIKAAkJOA8PTQDbAQAKAAkJOA8PTQDbAQAAAA==.',
Ty='Tyramonde:BAAALgAECgYJCQAAAA==.',
Ub='Ubonrebu:BAAALgAFFAEJAQAAAA==.',
Ud='Udb:BAAALgAFFAEJAgABLgAFFAMJDgACAPsgAA==.',
Va='Vaelestrix:BAACLgAFFH9DAAQCAAkJUCRhAABWAwACAAkJUCRhAABWAwAlAAMJDByfCADzAAAmAAEJUQcsBgBdAAAuAAQKf0QAAwIACQn4JW4AAOUDAAIACQn4JW4AAOUDACYAAQnuJS8eAGsAAAAA.Vain:BAAALgAECgIJAgAAAA==.Valamaldoran:BAAALgADCgkJCQAAAA==.Valholla:BAAALgADCgMJAwAAAA==.Vashtanerada:BAAALgADCgYJCgAAAA==.',
Ve='Veilish:BAAALgADCgYJCQAAAA==.Velind:BAAALgAECggJCQAAAA==.',
Vo='Voiddøøde:BAAALgAECgUJBQAAAA==.Voidsocket:BAAALgAECgcJBgAAAA==.Voidtoes:BAAALgAECgQJBAAAAA==.',
Vu='Vulpvs:BAAALgAECgEJAQAAAA==.',
Vv='Vvlpvs:BAAALgADCgQJBAAAAA==.',
Vy='Vyral:BAAALgAFFAEJAQAAAA==.',
Wa='Warherald:BAABLgAECn8lAAQMAAgJshFdHwA4AQAMAAgJshFdHwA4AQASAAUJtAc5UwCJAAATAAMJAwWPigBdAAAAAA==.Wasntme:BAAALgADCgYJCgABLgAFFAQJCQAXANkCAA==.',
We='Wednesday:BAACLgAFFH8zAAIaAAkJ0BxLAgCtAgAaAAkJ0BxLAgCtAgAuAAQKfywAAhoACAnwJBEHAKsCABoACAnwJBEHAKsCAAAA.',
Wh='Whoops:BAAALgADCgcJBwAAAA==.',
Wu='Wuxi:BAAALgAECgcJCgABLgAFFAQJFAAfABUhAA==.',
Wy='Wyldefyre:BAAALgADCggJCAAAAA==.',
['Wø']='Wøøds:BAAALgAECgQJBwAAAA==.',
Xa='Xalaria:BAAALgAECgYJDAAAAA==.Xandril:BAAALgAECgMJAgABLgAECggJFAAUAPcHAA==.',
Xi='Xirek:BAABLgAECn89AAIMAAkJZhEzEwC6AQAMAAkJZhEzEwC6AQAAAA==.',
Yr='Yreasak:BAABLgAECn8uAAMBAAkJKQ5uSgC7AQABAAkJJQ5uSgC7AQAdAAMJFwj8GgCeAAAAAA==.Yrigore:BAAALgAECgEJAQABLgAECgkJLgABACkOAA==.Yrisan:BAAALgAECgUJBQABLgAECgkJLgABACkOAA==.Yrivonn:BAAALgADCgYJBgABLgAECgkJLgABACkOAA==.',
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
