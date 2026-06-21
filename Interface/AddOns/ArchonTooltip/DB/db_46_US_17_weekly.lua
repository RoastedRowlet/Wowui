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

local lookup = {'Shaman-Restoration','Warrior-Protection','Warrior-Fury','Mage-Frost','Shaman-Enhancement','Paladin-Retribution','Warlock-Demonology','Priest-Shadow','DemonHunter-Devourer','Druid-Restoration','Priest-Holy','Warrior-Arms','Warlock-Destruction','DeathKnight-Frost','Warlock-Affliction','DeathKnight-Unholy','Paladin-Holy','Unknown-Unknown','Druid-Balance','Shaman-Elemental','Paladin-Protection','Evoker-Devastation','Evoker-Augmentation','Hunter-Survival','Monk-Windwalker','Hunter-Marksmanship','DemonHunter-Havoc','Hunter-BeastMastery','DemonHunter-Vengeance','Monk-Brewmaster','Priest-Discipline','Monk-Mistweaver','DeathKnight-Blood','Rogue-Subtlety','Evoker-Preservation','Druid-Feral','Druid-Guardian',}
local provider = {region='US',realm='Archimonde',name='US',type='weekly',zone=46,date='2026-06-20',data={Aa='Aanaleaa:BAABLgAECn8XAAIBAAkJFwqHWABVAQABAAkJFwqHWABVAQAAAA==.',
Ab='Abelram:BAAALgADCgUJBQAAAA==.',
Ad='Ad:BAABLgAECn8wAAMCAAkJTCHIAwD0AgACAAkJTCHIAwD0AgADAAUJ+QpeaAC9AAABLgAFFAQJBgAEAHcPAA==.Adellon:BAABLgAFFH8MAAIFAAQJ9heWBwA+AQAFAAQJ9heWBwA+AQAAAA==.Adhar:BAAALgAECgQJBwAAAA==.Adrielle:BAABLgAECn8kAAIGAAYJXhv8kABQAQAGAAYJXhv8kABQAQAAAA==.',
Ae='Aeiox:BAAALgADCgMJAwAAAA==.Aevelman:BAABLgAECn89AAIHAAkJXR9tAABgAgAHAAkJXR9tAABgAgAAAA==.',
Af='Affinty:BAAALgAECgQJBAABLgAFFAcJFgAIAHkbAA==.',
Ag='Ag:BAAALgAFFAEJAQAAAA==.',
Ai='Airphobic:BAABLgAECn8UAAIBAAUJPBvMTQB6AQABAAUJPBvMTQB6AQAAAA==.',
Ak='Akakage:BAAALgAECgEJAQABLgAECggJGQAJACoXAA==.Akakaji:BAABLgAECn8ZAAIJAAgJKhe6PQDRAQAJAAgJKhe6PQDRAQAAAA==.Akutoku:BAAALgADCgcJDAAAAA==.',
Al='Aland:BAAALgADCggJEgAAAA==.Alea:BAABLgAECn8cAAIKAAgJMxxsFACSAgAKAAgJMxxsFACSAgAAAA==.Almodiir:BAAALgADCgUJCQAAAA==.Almoraz:BAAALgAECgUJBQAAAA==.',
An='Anachron:BAAALgADCgIJAgAAAA==.Anaki:BAAALgAECgIJAgAAAA==.Annakkin:BAAALgAECgYJDAAAAA==.Anomander:BAABLgAECn8jAAIJAAYJtQzhogDeAAAJAAYJtQzhogDeAAAAAA==.Anonymoose:BAAALgADCgQJBAAAAA==.',
Ao='Aol:BAAALgADCgUJBQAAAA==.',
Ar='Ar:BAABLgAECn8XAAILAAcJfBDOMgA+AQALAAcJfBDOMgA+AQABLgAFFAQJBgAEAHcPAA==.Aratar:BAAALgAECgMJAwAAAA==.Arbiter:BAAALgAECgUJCQAAAA==.Archon:BAACLgAFFH8FAAMMAAMJOxqeMQCXAAAMAAIJhBmeMQCXAAADAAEJqRveTwBNAAAuAAQKfx4AAwMACAkwHpoXADECAAMACAkwHpoXADECAAwABAnJFfNCALwAAAAA.Argig:BAAALgAECgUJBQAAAA==.Arienca:BAABLgAECn85AAMNAAkJchBHFgCYAQANAAgJnhBHFgCYAQAHAAkJaAujXQCGAQAAAA==.Arwenn:BAAALgAECgEJAQAAAA==.',
As='Aspir:BAEALgAECggJCAABLgAFFAcJGAAOABwWAA==.Asu:BAABLgAECn8gAAIKAAkJ4RPeJgAZAgAKAAkJ4RPeJgAZAgAAAA==.',
At='At:BAACLgAFFH8GAAIEAAQJdw+aYQAfAQAEAAQJdw+aYQAfAQAuAAQKfxkAAgQABgnKFROoAIkBAAQABgnKFROoAIkBAAAA.',
Au='Aubrey:BAACLgAFFH8NAAIKAAYJpQW+LAACAQAKAAYJpQW+LAACAQAuAAQKfxQAAgoACQlyCqVSAFwBAAoACQlyCqVSAFwBAAAA.Auddio:BAAALgAECgkJAgAAAA==.',
Av='Avengion:BAABLgAECn8VAAIOAAcJ8wmiGQAFAQAOAAcJ8wmiGQAFAQAAAA==.',
Ba='Balthromaw:BAAALgADCggJDQAAAA==.Barbato:BAAALgADCgYJCQAAAA==.Barbie:BAAALgADCgYJBgAAAA==.',
Be='Beararms:BAAALgADCgcJCAAAAA==.Beav:BAAALgAECgYJBwABLgAFFAYJFQAKAOoaAA==.Beefkeeper:BAAALgAFFAIJAgAAAA==.Beldent:BAAALgAECgQJBwAAAA==.Belöved:BAAALgAECgQJBAAAAA==.Benelli:BAAALgAECgEJAQAAAA==.Bernard:BAAALgAECgUJBwAAAA==.',
Bi='Bitey:BAAALgAFFAQJBAABLgAFFAgJGAAPACIVAA==.',
Bl='Blazegrave:BAABLgAECn8XAAIQAAgJ/heRQgD7AQAQAAgJ/heRQgD7AQABLgAECgkJTAAEAN0WAA==.Blazeofglory:BAAALgADCgUJBQABLgAECggJJQAQAKcHAA==.Blazerager:BAAALgADCgYJBgABLgAECgkJTAAEAN0WAA==.Blazerunner:BAABLgAECn9MAAIEAAkJ3RZ2NwA7AgAEAAkJ3RZ2NwA7AgAAAA==.Blazesmasher:BAAALgAECgkJCgABLgAECgkJTAAEAN0WAA==.Blitzkreig:BAABLgAECn8bAAIQAAkJGRjiMQA3AgAQAAkJGRjiMQA3AgAAAA==.Bluefoot:BAABLgAECn8fAAIBAAYJ/AhrfADqAAABAAYJ/AhrfADqAAAAAA==.Blured:BAACLgAFFH8FAAIJAAMJCA2LCwCGAAAJAAMJCA2LCwCGAAAuAAQKf0wAAgkACQlwJPsDAEcDAAkACQlwJPsDAEcDAAAA.',
Bo='Booty:BAABLgAECn8oAAICAAkJvCKMBQDhAgACAAkJvCKMBQDhAgAAAA==.',
Br='Brightblayde:BAABLgAECn8gAAIGAAgJEhJGagCaAQAGAAgJEhJGagCaAQAAAA==.Brynhildre:BAABLgAECn8UAAIRAAcJfgtURABmAQARAAcJfgtURABmAQABLgAFFAYJDQAKAKUFAA==.',
Bu='Buum:BAABLgAECn8XAAICAAkJghaMDQASAgACAAkJghaMDQASAgAAAA==.',
By='Byane:BAAALgADCgYJBgAAAA==.',
['Bä']='Bämba:BAAALgAECgMJAwABLgAECgkJKwAEABoQAA==.',
Ca='Cachelyn:BAAALgAECgYJCwAAAA==.Cali:BAACLgAFFH8hAAIJAAgJABxYDwA8AgAJAAgJABxYDwA8AgAuAAQKfy0AAgkACAmkIeQSAOgCAAkACAmkIeQSAOgCAAAA.Cantouchthes:BAABLgAECn8UAAIEAAgJZB7HRAANAgAEAAgJZB7HRAANAgAAAA==.Captnage:BAAALgADCggJCAAAAA==.Carafe:BAAALgAECgUJDAAAAA==.',
Ce='Cederred:BAAALgAECgUJBQABLgAECggJCgASAAAAAA==.Cedertree:BAAALgADCgcJBwABLgAECggJCgASAAAAAA==.Celline:BAAALgADCgEJAQAAAA==.Cephus:BAABLgAFFH8QAAIKAAcJPBRDEQDtAQAKAAcJPBRDEQDtAQAAAA==.Cerafina:BAAALgADCgEJAQAAAA==.',
Ch='Chayse:BAAALgAFFAMJBAABLgAFFAYJDQAKAKUFAA==.Choom:BAABLgAECn8fAAMKAAkJuhUONgDQAQAKAAkJuhUONgDQAQATAAYJjRPrLgCOAQAAAA==.Chorizo:BAAALgADCgEJAQAAAA==.Christhina:BAAALgADCgQJBAAAAA==.Chronocide:BAACLgAFFH8PAAIUAAQJmB1sGgBIAQAUAAQJmB1sGgBIAQAuAAQKfyoAAhQACQnbHxEQAKkCABQACQnbHxEQAKkCAAAA.Chronophasia:BAABLgAECn8fAAMGAAgJ2CBHHQCWAgAGAAgJ0SBHHQCWAgAVAAQJfBtpJADyAAAAAA==.Chroños:BAABLgAECn8UAAMWAAcJEA86FADKAAAXAAcJ6g3+RwALAQAWAAQJZw46FADKAAAAAA==.Chumléé:BAAALgADCgQJBAAAAA==.Chérry:BAACLgAFFH8hAAIJAAcJAR1jEAAxAgAJAAcJAR1jEAAxAgAuAAQKfyAAAgkACQlsIowQAPoCAAkACQlsIowQAPoCAAAA.',
Ci='Ciri:BAAALgAFFAIJAwAAAA==.',
Cl='Climpwimp:BAAALgAECgIJAgAAAA==.Cluntasaur:BAAALgAECgUJBgAAAA==.',
Co='Connerr:BAABLgAECn8aAAIKAAgJtBotLwDnAQAKAAgJtBotLwDnAQAAAA==.Contendor:BAAALgAECgkJCQAAAA==.Cowage:BAAALgAECgQJCQAAAA==.',
Cr='Crisse:BAAALgAECgUJCgAAAA==.Croh:BAABLgAECn8aAAMQAAgJpBNfVAD0AQAQAAgJpBNfVAD0AQAOAAQJawb3DwCcAAAAAA==.Crucks:BAAALgADCgQJBAAAAA==.Cruknar:BAABLgAFFH8GAAIYAAMJ/xVwHADtAAAYAAMJ/xVwHADtAAAAAA==.',
Cu='Curita:BAAALgADCgEJAQAAAA==.',
Cy='Cynestra:BAABLgAECn8XAAIRAAkJHRMQHQAbAgARAAkJHRMQHQAbAgAAAA==.Cytheris:BAAALgAECgEJAQABLgAECggJGgAKALQaAA==.',
Da='Daddio:BAEALgADCgIJAwABLgADCgcJBwASAAAAAA==.Dadudadu:BAACLgAFFH8iAAIGAAgJFRDNDwDyAQAGAAgJFRDNDwDyAQAuAAQKfzQAAgYACQkZIHoWAOICAAYACQkZIHoWAOICAAAA.Daffo:BAAALgAECgIJAQAAAA==.Daftmonk:BAACLgAFFH8lAAIZAAcJZyKcAQB6AgAZAAcJZyKcAQB6AgAuAAQKfywAAhkACQmSJbECAG8DABkACQmSJbECAG8DAAAA.Daitanfuteki:BAAALgADCgEJAQABLgAFFAQJCAAaAOcVAA==.Dalan:BAAALgAECgEJAQAAAA==.Darkfyre:BAAALgADCgEJAgAAAA==.Darks:BAAALgAECgIJAgAAAA==.Darkwingfish:BAABLgAECn8pAAIJAAkJrRSkRgCzAQAJAAkJrRSkRgCzAQAAAA==.Darmonevil:BAAALgADCgEJAQAAAA==.Dartran:BAAALgADCgIJBwAAAA==.Dasarus:BAABLgAECn8ZAAMbAAgJsxptEAAhAgAbAAgJsxptEAAhAgAJAAYJWw9BkQD+AAAAAA==.Dayman:BAABLgAECn8UAAMVAAcJgwIcNACSAAAVAAcJXAIcNACSAAAGAAYJ0gFLSAFkAAAAAA==.',
De='Decày:BAAALgAECgcJEAAAAA==.Demoteck:BAAALgAECgQJBgAAAA==.Demy:BAAALgADCgYJBgAAAA==.Deredris:BAAALgAECgEJAQAAAA==.Deth:BAAALgAECgIJAgABLgAECgMJDAASAAAAAA==.Dethblow:BAAALgAECgMJDAAAAA==.',
Di='Disconnects:BAAALgADCgUJBQAAAA==.Dium:BAAALgAECgEJAQAAAA==.Diwa:BAACLgAFFH8FAAIBAAUJ5QG7PgDpAAABAAUJ5QG7PgDpAAAuAAQKfxkAAwEACQn8BtJsABUBAAEACQn8BtJsABUBABQABglJB+BRAP8AAAAA.',
Dk='Dklot:BAACLgAFFH8IAAIQAAQJXA6ccAAdAQAQAAQJXA6ccAAdAQAuAAQKfxgAAxAABwlZHIt3AHUBABAABwlZHIt3AHUBAA4AAQn1DK48AC0AAAAA.',
Dr='Dracthfear:BAAALgAECgYJBwABLgAFFAUJGQAHAH4lAA==.Dragolot:BAAALgADCgQJBAABLgAFFAQJCAAQAFwOAA==.Draken:BAAALgAECgEJAQAAAA==.Draviin:BAABLgAECn8wAAIcAAkJ9x0hIQBiAgAcAAkJ9x0hIQBiAgAAAA==.',
Du='Duckcheese:BAAALgADCgEJAQAAAA==.Dunkyn:BAAALgAECgMJBgAAAA==.Durzoblint:BAAALgAECgUJCAAAAA==.',
Dy='Dyemon:BAAALgADCgIJAgAAAA==.',
['Dé']='Déad:BAAALgADCgcJDAAAAA==.',
El='Elementz:BAAALgAECgIJAgAAAA==.Elerae:BAABLgAECn8nAAIGAAkJ+hthFgDjAgAGAAkJ+hthFgDjAgAAAA==.Eleshkigal:BAABLgAECn8oAAMJAAkJ1yaKAwCTAwAJAAkJ1yaKAwCTAwAdAAQJiBoiEgAsAQAAAA==.',
En='Enkeke:BAACLgAFFH8FAAIQAAMJCQv1DwCNAAAQAAMJCQv1DwCNAAAuAAQKfzwAAhAACQlNHcElAG0CABAACQlNHcElAG0CAAAA.',
Er='Eresanna:BAABLgAFFH8OAAIEAAQJpQy5ZwAUAQAEAAQJpQy5ZwAUAQAAAA==.Ereshkigal:BAAALgAECgUJBgAAAA==.',
Es='Esdeath:BAAALgAECgQJCAABLgAFFAYJDwAbAEUTAA==.Estus:BAABLgAECn8VAAMRAAgJNhfYKgC5AQARAAgJNhfYKgC5AQAGAAIJ1gmPfwE9AAAAAA==.',
Ex='Extremefear:BAABLgAECn81AAMNAAkJ/hbAFAAHAQAHAAUJwBQodQBPAQANAAYJ8RXAFAAHAQAAAA==.',
Fa='Fatima:BAAALgAECgIJAwAAAA==.',
Fe='Fearious:BAACLgAFFH8ZAAMHAAUJfiX0KgCbAQAHAAUJ7yT0KgCbAQAPAAIJYSZXEwBwAAAuAAQKfyYABAcACAlBJkYvABsCAAcABwk3JEYvABsCAA0AAwl7JTQZANkAAA8AAQncI6ssAGkAAAAA.Felphetamine:BAAALgADCggJCAAAAA==.Fenrisfangs:BAABLgAECn8VAAIcAAkJSA6kVACmAQAcAAkJSA6kVACmAQAAAA==.Fenrisul:BAAALgAECgUJBQAAAA==.Feralshunter:BAACLgAFFH8IAAIaAAQJ5xWvFwD9AAAaAAQJ5xWvFwD9AAAuAAQKfzIAAhoACQkAIZcQALcCABoACQkAIZcQALcCAAAA.Feroond:BAAALgADCgQJBAAAAA==.',
Fi='Fingeritout:BAAALgADCgIJAgAAAA==.Firefly:BAAALgAECgMJAwAAAA==.',
Fl='Florea:BAAALgADCggJDAAAAA==.',
Fo='Fodurzind:BAAALgAECgEJAQAAAA==.Forfoxsake:BAABLgAECn8kAAIeAAgJmR/qEQAoAgAeAAgJmR/qEQAoAgAAAA==.',
Fr='Frogteeth:BAAALgADCgUJBQAAAA==.',
Fu='Furibeav:BAABLgAFFH8VAAIKAAYJ6hpsEgDfAQAKAAYJ6hpsEgDfAQAAAA==.Furrów:BAAALgAECgUJBwAAAA==.',
['Fû']='Fûrrow:BAAALgAECgcJEAAAAA==.',
Ga='Gallindral:BAABLgAECn88AAIJAAkJah1TFQCYAgAJAAkJah1TFQCYAgAAAA==.Garanda:BAAALgAECgQJBQAAAA==.Gargantuan:BAAALgADCgMJAwAAAA==.Garreth:BAAALgAECgMJAwAAAA==.Gatito:BAAALgAECgEJAQABLgAECgIJAgASAAAAAA==.Gauthus:BAAALgAECgkJCgAAAA==.',
Ge='Genericnpc:BAABLgAECn8eAAQMAAgJvA+qIwBHAQAMAAgJ7QyqIwBHAQADAAYJVw0cVgD1AAACAAEJfxOaUQA3AAAAAA==.Geobrando:BAABLgAECn8+AAMBAAkJTiBtCwDHAgABAAkJTiBtCwDHAgAUAAYJvB2qJwCvAQABLgAFFAIJBQAQAPQXAA==.',
Gg='Ggbrews:BAACLgAFFH8pAAIGAAYJiySsDAAVAgAGAAYJiySsDAAVAgAuAAQKf6MABAYACQlyJqUBAH8DAAYACQlyJqUBAH8DABEACAn5HQoNAMACABUABwm5CPooANAAAAAA.',
Gh='Ghostblaze:BAAALgAECgUJDAABLgAECgkJTAAEAN0WAA==.',
Gi='Gier:BAAALgADCgUJBQAAAA==.Gino:BAAALgADCgEJAQAAAA==.',
Gl='Glacialwrait:BAAALgAECgEJAQAAAA==.Glacious:BAAALgADCgEJAQAAAA==.Glasswings:BAAALgAECgIJAgAAAA==.',
Gn='Gnosh:BAABLgAECn8aAAITAAkJbxTyGQD8AQATAAkJbxTyGQD8AQAAAA==.Gnova:BAABLgAECn8jAAIEAAYJfSG+YgC5AQAEAAYJfSG+YgC5AQAAAA==.',
Go='Gorian:BAAALgAECgcJCAAAAA==.',
Gr='Gregorz:BAAALgADCgEJAQAAAA==.Grish:BAAALgAECgEJAQAAAA==.',
Gu='Guidosarduci:BAABLgAECn8iAAIBAAgJhhdgHAA2AgABAAgJhhdgHAA2AgAAAA==.',
Ha='Hairia:BAAALgADCgUJBQAAAA==.Halen:BAAALgADCgcJBwABLgAFFAgJIQAJAAAcAA==.Hardone:BAAALgAECggJDwAAAA==.Harle:BAABLgAECn8bAAIEAAkJmhePMABXAgAEAAkJmhePMABXAgAAAA==.Hatari:BAAALgAECgMJAwAAAA==.',
He='Hektate:BAABLgAECn8WAAIEAAcJXQvVsgAdAQAEAAcJXQvVsgAdAQABLgAFFAgJIgAGABUQAA==.Henryjones:BAAALgADCgEJAQAAAA==.',
Hi='Hikari:BAABLgAECn8WAAIGAAgJZiEnKwBUAgAGAAgJZiEnKwBUAgABLgAFFAYJKQAUAFIhAA==.Hilkesad:BAAALgAECgQJBAAAAA==.Hizo:BAAALgADCgUJBQAAAA==.',
Ho='Holybeave:BAABLgAECn8eAAMLAAkJNB3/DACFAgAfAAkJaBi5CQCfAgALAAgJqx7/DACFAgABLgAFFAYJFQAKAOoaAA==.Holyshortguy:BAAALgAECgYJDgABLgAFFAYJDQAgACsOAA==.Hoofer:BAAALgAECgYJDgAAAA==.',
Hu='Hunkomeat:BAABLgAECn8XAAIDAAgJLhzkLAAAAgADAAgJLhzkLAAAAgAAAA==.',
['Hë']='Hënry:BAAALgAECgEJAQAAAA==.',
Ic='Icelmo:BAABLgAFFH8OAAIDAAQJ7BcIGgBKAQADAAQJ7BcIGgBKAQAAAA==.',
Ih='Ihotyou:BAAALgADCgQJBwAAAA==.',
Il='Ilikeitrough:BAAALgAECgUJBQAAAA==.',
In='Inai:BAAALgADCgcJDAABLgAFFAYJDwAbAEUTAA==.Invizww:BAAALgAECgQJBQAAAA==.',
Ir='Ircapslock:BAAALgAECgYJCwAAAA==.',
Iv='Ivorypal:BAABLgAECn8gAAIRAAgJqR/dEACLAgARAAgJqR/dEACLAgAAAA==.',
Ja='Jacksock:BAAALgADCgEJAQAAAA==.Jamzz:BAAALgAECgQJBQABLgAFFAcJHQAaAE0SAA==.Jaromir:BAAALgADCgcJBwAAAA==.Jaskow:BAABLgAECn8uAAIKAAkJjiD/BwA4AwAKAAkJjiD/BwA4AwAAAA==.Jaymick:BAABLgAECn8aAAMcAAkJYhEZbgBlAQAYAAcJEQ6ZIwCBAQAcAAcJjRIZbgBlAQAAAA==.',
Jb='Jbizzler:BAAALgAECgcJBgAAAA==.',
Jc='Jcrypt:BAAALgAECgcJAgAAAA==.',
Je='Jennika:BAABLgAFFH8GAAIYAAMJjwcuIgDIAAAYAAMJjwcuIgDIAAAAAA==.Jernau:BAAALgAECgEJAQAAAA==.Jessortess:BAAALgAECgQJBwAAAA==.',
Jo='Johnwicksdog:BAAALgAECggJEQAAAA==.Jorbies:BAAALgAECgYJCQABLgAFFAcJFgAIAHkbAA==.Jorls:BAACLgAFFH8WAAMIAAcJeRtMAgDeAQAIAAcJeRtMAgDeAQAfAAEJWAEnGwBDAAAuAAQKfxsABAgACQkFHlMIAP8CAAgACQkFHlMIAP8CAB8ABAnSCc08AMQAAAsAAglAAgl2AFEAAAAA.',
Ju='Junatooka:BAAALgAECgIJAgAAAA==.Jusdatip:BAAALgAECgUJDQAAAA==.',
Ka='Kaelthazed:BAAALgADCgEJAQABLgAFFAMJCAAHAFkVAA==.Kalfu:BAABLgAECn8XAAMcAAgJ0B1jPQDrAQAcAAgJ0B1jPQDrAQAaAAYJoBUDOgB5AQAAAA==.Kameshoga:BAAALgAECgIJAgAAAA==.Kammwin:BAAALgAECgYJEwAAAA==.Karten:BAAALgAECgYJDgAAAA==.Kaylea:BAAALgADCgIJAgAAAA==.',
Ke='Kellandria:BAAALgADCgcJEgAAAA==.',
Ki='Kieraleah:BAAALgAECgcJBwAAAA==.Killjoyss:BAAALgAECgMJBAABLgAECgUJBgASAAAAAA==.Kittêh:BAAALgAECgEJAQAAAA==.',
Kn='Knathor:BAAALgAECgQJBgABLgAECgcJDgASAAAAAA==.',
Ko='Korec:BAAALgAECgcJDgAAAA==.',
Kr='Krasis:BAABLgAECn8XAAIGAAkJvhrLWADYAQAGAAkJvhrLWADYAQAAAA==.Krazermonk:BAACLgAFFH8OAAIZAAQJmxoBEAA9AQAZAAQJmxoBEAA9AQAuAAQKfygAAhkACQmlHrMOAF4CABkACQmlHrMOAF4CAAAA.Krispinwah:BAACLgAFFH8FAAIQAAIJ9BcqGABYAAAQAAIJ9BcqGABYAAAuAAQKfxoAAhAACQleHpoPAO8CABAACQleHpoPAO8CAAAA.Kristysavage:BAACLgAFFH8FAAIcAAMJ1hfmWQDxAAAcAAMJ1hfmWQDxAAAuAAQKfysAAhwACQliI3wIABYDABwACQliI3wIABYDAAAA.Kroflavinof:BAAALgAECgUJCQAAAA==.',
Ku='Kurosakí:BAAALgAECgEJAQAAAA==.',
Ky='Kyle:BAAALgAECgIJAgABLgAFFAQJDwAGAFweAA==.',
La='Lanc:BAAALgAECgQJCQAAAA==.Lappytopdog:BAAALgAECgcJDAAAAA==.Larradin:BAAALgADCggJEAAAAA==.Lawnchair:BAAALgAECggJDAAAAA==.',
Le='Lealta:BAAALgAFFAEJAgABLgAFFAgJIwAfANofAA==.Leonus:BAAALgAECgQJCQAAAA==.Leviathahn:BAAALgAECgEJAgAAAA==.',
Lh='Lhegholhaz:BAAALgADCgIJAgAAAA==.',
Li='Lichdawg:BAACLgAFFH8XAAMOAAYJ1RGNBwB1AQAOAAUJ1RGNBwB1AQAhAAEJAAAHYQAAAAAuAAQKfxQAAg4ACAnSE9sOAIcBAA4ACAnSE9sOAIcBAAAA.Lilzayna:BAAALgAECgEJAQABLgAECgUJBgASAAAAAA==.Linthori:BAEALgADCgMJAwABLgAECgcJDQASAAAAAA==.Lirrin:BAAALgAECgEJAQAAAA==.Lithlia:BAAALgADCgcJBwAAAA==.Livvela:BAABLgAECn8kAAIiAAkJsRXzFgDlAQAiAAkJsRXzFgDlAQAAAA==.',
Ll='Llas:BAAALgADCgIJAgAAAA==.',
Lo='Lockdawg:BAACLgAFFH8aAAIHAAYJ6h2WJQC0AQAHAAYJ6h2WJQC0AQAuAAQKfyYAAwcACAmFHRImAHoCAAcACAmFHRImAHoCAA0AAQnWFc1sADoAAAAA.Lockedin:BAAALgAECgkJEgAAAA==.Lonne:BAAALgAECgYJDgABLgAFFAIJBAASAAAAAA==.Lover:BAABLgAECn8wAAILAAkJqSCwDACbAgALAAkJqSCwDACbAgAAAA==.',
Lu='Lubu:BAACLgAFFH8PAAIbAAYJRRNxCQBxAQAbAAYJRRNxCQBxAQAuAAQKfxoAAhsACQn+H2AFAOsCABsACQn+H2AFAOsCAAAA.Lucianis:BAAALgADCgQJBwAAAA==.Luckycharmz:BAAALgAECgQJCQABLgAFFAIJBQAfABoEAA==.Luckywar:BAAALgADCgYJBgAAAA==.Luell:BAAALgAECgcJDwAAAA==.Luev:BAAALgAECgYJCAAAAA==.Lumiette:BAABLgAECn8WAAMCAAcJ2RrEEQDOAQACAAcJ2RrEEQDOAQADAAMJFAvChQCoAAAAAA==.',
Ly='Lynai:BAABLgAECn8cAAIEAAkJPxK/BQDGAAAEAAkJPxK/BQDGAAAAAA==.',
['Lá']='Lándwhale:BAACLgAFFH8YAAIiAAQJxSNxEwBxAQAiAAQJxSNxEwBxAQAuAAQKfy4AAiIACQmTJFoEAPgCACIACQmTJFoEAPgCAAAA.',
['Lö']='Löver:BAAALgAECgcJDQAAAA==.',
Ma='Mabil:BAABLgAECn8UAAQHAAcJRhJwmgAIAQAHAAYJew1wmgAIAQAPAAQJXRWcGAC2AAANAAIJNAycQgAoAAAAAA==.Macktimus:BAABLgAECn8gAAINAAkJYBhQBQAdAgANAAkJYBhQBQAdAgAAAA==.Madeinchina:BAAALgADCgEJAQAAAA==.Mage:BAAALgAFFAEJAgAAAA==.Magictonyp:BAABLgAECn8UAAIEAAUJ/Qey9wC5AAAEAAUJ/Qey9wC5AAAAAA==.Magicznstuff:BAAALgAECgEJAQABLgAECgMJBgASAAAAAA==.Magna:BAABLgAECn8lAAIDAAkJYRIuKQC0AQADAAkJYRIuKQC0AQAAAA==.Magnusbane:BAAALgAECgUJBQAAAA==.Makili:BAABLgAFFH8VAAIEAAUJXxggWAAtAQAEAAUJXxggWAAtAQAAAA==.Maladrix:BAAALgAECgQJDQAAAA==.Mauê:BAAALgADCgEJAQABLgAECgIJAgASAAAAAA==.',
Mc='Mchealer:BAAALgAECgQJBgAAAA==.Mchunter:BAAALgAECgMJAwAAAA==.Mcshadow:BAAALgADCgIJAgAAAA==.',
Me='Menphina:BAAALgAECgIJAgAAAA==.Merigold:BAAALgAECgEJAQABLgAECgQJBAASAAAAAA==.',
Mi='Minnow:BAAALgAECgYJDgAAAA==.Mintchip:BAABLgAECn8QAAIJAAcJ3RdTSwCkAQAJAAcJ3RdTSwCkAQAAAA==.',
Mo='Monk:BAAALgAECgEJAQAAAA==.Monza:BAAALgADCgEJAQABLgAECgkJKAAEAOsWAA==.Moontini:BAAALgADCgYJBgABLgAECgQJDQASAAAAAA==.Mordryn:BAAALgADCgcJBwAAAA==.',
Mu='Murad:BAAALgAFFAMJAwAAAA==.',
My='Mysternia:BAABLgAECn8VAAILAAgJ2w6/MwA3AQALAAgJ2w6/MwA3AQAAAA==.Myyagie:BAAALgADCgcJEQAAAA==.',
Na='Nalthexon:BAABLgAECn8qAAMgAAgJ2wtFMQAzAQAgAAgJ2wtFMQAzAQAZAAEJXQacrQAmAAABLgAFFAMJBgAKAHUGAA==.Natureborne:BAAALgAECgYJCQAAAA==.',
Ne='Nedrud:BAAALgADCgUJCAAAAA==.Nelson:BAEALgAECgYJCAABLgAECgkJLQAEAFEeAA==.Nenno:BAAALgADCgEJAQAAAA==.Netzhul:BAAALgAFFAEJAQAAAA==.',
Ni='Night:BAAALgAECgcJEQAAAA==.Nikalos:BAAALgAECgYJDQAAAA==.Nikole:BAAALgAECgMJAwAAAA==.',
No='Noon:BAAALgADCgUJBQABLgAECggJFQARADYXAA==.Notorckrag:BAABLgAECn9AAAIeAAkJkiMeAwAiAwAeAAkJkiMeAwAiAwAAAA==.Nozomi:BAABLgAECn8VAAIJAAkJdwYamQDvAAAJAAkJdwYamQDvAAAAAA==.',
Nu='Nut:BAAALgADCgQJBAAAAA==.',
['Nê']='Nêz:BAAALgAECgUJCAAAAA==.',
Oa='Oathbringer:BAAALgAECgQJBAAAAA==.',
Ob='Oblivionz:BAAALgAECgMJAwAAAA==.',
Oc='Ocho:BAAALgADCgYJCQAAAA==.',
Of='Offbrandcleo:BAAALgAECgkJBgAAAA==.',
Ok='Okibi:BAAALgAECgMJBQABLgAFFAYJDwAbAEUTAA==.',
Ol='Oldrecipe:BAABLgAFFH8LAAIRAAQJNRXaIwACAQARAAQJNRXaIwACAQAAAA==.Oliange:BAABLgAECn8rAAIEAAgJGhADcgCWAQAEAAgJGhADcgCWAQAAAA==.',
Or='Ori:BAEALgADCgcJCwABLgAECgcJDQASAAAAAA==.Originalgank:BAACLgAFFH8OAAIEAAQJgB02CAD7AAAEAAQJgB02CAD7AAAuAAQKfyYAAgQACQkHJNgGAEkDAAQACQkHJNgGAEkDAAAA.',
Oz='Ozzi:BAAALgAECgMJAwAAAA==.',
Pa='Papanell:BAAALgADCgYJCQAAAA==.',
Pe='Peachcobbler:BAAALgAECggJDgAAAA==.Perc:BAAALgAECgcJEAAAAA==.',
Ph='Philsner:BAEALgAECgcJDQAAAA==.Phink:BAAALgAECgQJCgAAAA==.',
Pi='Pinkk:BAABLgAECn8WAAIcAAkJ/xxYGgCHAgAcAAkJ/xxYGgCHAgAAAA==.',
Pl='Plushie:BAABLgAECn8nAAIIAAgJugt0MABcAQAIAAgJugt0MABcAQAAAA==.',
Po='Pong:BAABLgAECn8VAAMFAAgJ2Bl7DgDJAQAFAAcJeRl7DgDJAQABAAEJ6xJf0AA7AAAAAA==.Pooqy:BAACLgAFFH8QAAMQAAUJ4SRSOQCJAQAQAAQJ4SRSOQCJAQAhAAEJAAC6SQAAAAAuAAQKfxYAAhAACAlWIrskAKsCABAACAlWIrskAKsCAAAA.Porcel:BAAALgADCgcJCwAAAA==.Potatoteng:BAABLgAFFH8HAAIOAAQJ/QXJAQDTAAAOAAQJ/QXJAQDTAAABLgAFFAcJDwAGAOEUAA==.',
Pr='Pritej:BAAALgAECgYJCgABLgAFFAIJBAASAAAAAA==.Proto:BAAALgAECgcJDAAAAA==.',
Pu='Puck:BAAALgAECgIJCAABLgAFFAYJDwAbAEUTAA==.',
Py='Pyraleus:BAAALgADCgQJBAAAAA==.',
Qm='Qmpell:BAAALgADCgYJBgAAAA==.',
Qu='Quickchicken:BAAALgAECgEJAgAAAA==.',
Ra='Ragel:BAACLgAFFH8FAAITAAIJjxvdNgCiAAATAAIJjxvdNgCiAAAuAAQKfzcAAhMACQn3IA8GAPcCABMACQn3IA8GAPcCAAAA.Rainesage:BAABLgAECn8xAAMIAAkJShxrDQB9AgAIAAkJShxrDQB9AgALAAEJxwcgeAAiAAAAAA==.Ralphel:BAABLgAECn8pAAIGAAgJMwcKsAAfAQAGAAgJMwcKsAAfAQAAAA==.Rasmon:BAAALgAECggJCAAAAA==.Rasu:BAAALgADCgcJBwABLgAECggJGgAjALUMAA==.Ravendark:BAAALgAECgEJAQAAAA==.Rayozap:BAAALgAECgUJBgAAAA==.',
Re='Redeye:BAAALgADCgMJAwAAAA==.Relock:BAAALgAECgMJAwABLgAECggJGgAKALQaAA==.',
Rh='Rhondaa:BAAALgAECgYJEQAAAA==.Rhubarb:BAABLgAECn8/AAMMAAkJjiZFAQBcAwAMAAgJIiZFAQBcAwADAAgJoyRiDQCXAgAAAA==.',
Ri='Ripley:BAAALgAFFAEJAQAAAA==.Riptidepods:BAAALgAECgEJAQAAAA==.Riyci:BAAALgAECgEJAQAAAA==.',
Ro='Rohiem:BAACLgAFFH8GAAIDAAQJRAbfPAC7AAADAAQJRAbfPAC7AAAuAAQKfzUAAgMACQmkGMcZACACAAMACQmkGMcZACACAAAA.',
Ry='Ryan:BAABLgAECn8eAAIGAAkJZR4ZHADBAgAGAAkJZR4ZHADBAgAAAA==.Rylorthas:BAACLgAFFH8fAAILAAcJdhNeCQC3AQALAAcJdhNeCQC3AQAuAAQKfy0AAgsACQl8HMsSAEoCAAsACQl8HMsSAEoCAAAA.Rylosh:BAAALgAFFAEJAQABLgAFFAcJHwALAHYTAA==.',
['Rî']='Rîkku:BAAALgADCggJEAAAAA==.',
Sa='Sabot:BAABLgAECn8aAAMkAAkJYxndBwBWAgAkAAkJYxndBwBWAgAlAAQJmwpdTAB5AAAAAA==.Sabrook:BAAALgADCggJCAAAAA==.Salazar:BAAALgAECgEJAwAAAA==.Sam:BAAALgAECgUJBAAAAA==.Satisfied:BAABLgAECn8VAAILAAUJRhyIKACCAQALAAUJRhyIKACCAQAAAA==.',
Sc='Scottmonk:BAAALgAECgIJBQAAAA==.Scottpaladin:BAAALgAECgEJAQABLgAECgIJBQASAAAAAA==.',
Se='Seath:BAAALgAECggJEAABLgAFFAMJCAAHAFkVAA==.Sentaí:BAAALgAECgIJBAAAAA==.',
Sh='Shamantics:BAAALgAECgIJAwABLgAFFAUJGQAHAH4lAA==.Shamerica:BAACLgAFFH8bAAMFAAgJZxxdAQAXAgAFAAcJWiBdAQAXAgAUAAIJSg3nQACIAAAuAAQKfz4AAwUACQkyJKEBABkDAAUACQn2IqEBABkDABQACAnNI9QIANACAAAA.Shizuku:BAAALgADCgUJBQAAAA==.Shmooythefox:BAABLgAECn8lAAIcAAcJfCG4NgADAgAcAAcJfCG4NgADAgAAAA==.Shokan:BAAALgADCgQJBAAAAA==.Shortleedin:BAAALgAECgIJAQAAAA==.Shòckwave:BAAALgADCgQJBAAAAA==.',
Si='Sinrex:BAAALgADCgUJBwAAAA==.Sixstar:BAAALgADCgEJAQAAAA==.',
Sk='Skrt:BAAALgAECgMJAwAAAA==.Skyleax:BAACLgAFFH8KAAMQAAQJdg0+fgAKAQAQAAQJdg0+fgAKAQAOAAEJwAL6LAA1AAAuAAQKfxgABBAACQkSIEYuAH8CABAACQnoHEYuAH8CAA4ABAkVHkUMAPAAACEAAQn7D0ZLACAAAAAA.',
Sl='Slagothor:BAABLgAECn8VAAIQAAkJywRnmQBNAQAQAAkJywRnmQBNAQAAAA==.Slanesh:BAAALgAECgcJDwABLgAECgcJEAAJAN0XAA==.Sleaze:BAAALgADCgEJAQAAAA==.Sleazus:BAAALgAECgMJAwAAAA==.',
Sm='Smeesha:BAABLgAECn8iAAQjAAgJ0RUBEADLAQAjAAcJlBYBEADLAQAWAAYJRQcGJgDzAAAXAAYJ1wahRgDBAAAAAA==.',
Sn='Snaxwell:BAAALgADCgEJAQAAAA==.',
So='Somin:BAAALgAECgMJBAAAAA==.',
Sp='Specialedz:BAAALgADCgUJBwAAAA==.Spekaleks:BAAALgADCgUJBwAAAA==.',
Sq='Squitwurt:BAAALgADCgYJBgAAAA==.',
St='Starbux:BAABLgAECn8UAAMVAAgJ/g9mFwBlAQAVAAgJ/g9mFwBlAQARAAEJewNtnQAjAAAAAA==.Starbúcks:BAAALgAECgIJAwABLgAFFAIJBQAfABoEAA==.Steppers:BAAALgAECgUJAgAAAA==.Straamm:BAAALgADCgMJAwAAAA==.',
Su='Sugarr:BAAALgADCgMJAwAAAA==.Sunfish:BAAALgAECgYJCgAAAA==.',
Sv='Svelana:BAABLgAECn8lAAMZAAgJjSJ6DgBhAgAZAAgJjSJ6DgBhAgAgAAEJCgthxgAlAAAAAA==.',
Sy='Syb:BAABLgAECn8bAAQXAAkJZxdMGgAEAgAXAAkJlhVMGgAEAgAWAAQJ4hk/EgDmAAAjAAEJFwU3SwArAAAAAA==.Sylphrena:BAACLgAFFH8TAAIIAAUJgyAAEABtAQAIAAUJgyAAEABtAQAuAAQKfykAAggACQnSIscGAOUCAAgACQnSIscGAOUCAAAA.Syssana:BAAALgAECgIJBgAAAA==.',
Ta='Tadaa:BAAALgADCgIJAgAAAA==.Tamerlein:BAAALgAECgMJBQAAAA==.Tamioka:BAAALgAECgYJCAAAAA==.Tanookii:BAAALgAECgYJEwAAAA==.',
Te='Telafar:BAAALgAECgkJAwAAAA==.',
Th='Theinsider:BAACLgAFFH8IAAIHAAMJWRXDCgCfAAAHAAMJWRXDCgCfAAAuAAQKf0QAAwcACQkDImUOANoCAAcACQkDImUOANoCAA0ABQmQD6crABEBAAAA.Thenezath:BAAALgAECgYJCQAAAA==.Theoutsider:BAAALgAFFAEJAQABLgAFFAMJCAAHAFkVAA==.Thunrus:BAAALgADCgYJBgAAAA==.',
Ti='Tibbles:BAAALgAECgcJCAAAAA==.Tigerbait:BAAALgAECgYJEQAAAA==.Tindril:BAAALgAECgYJBwAAAA==.Tinymo:BAAALgAECgMJAwAAAA==.',
To='Toji:BAABLgAECn8WAAIIAAcJ+hj6IQC3AQAIAAcJ+hj6IQC3AQABLgAFFAYJKQAUAFIhAA==.Tomatoteng:BAACLgAFFH8PAAIGAAcJ4RTYEwDMAQAGAAcJ4RTYEwDMAQAuAAQKfyAAAgYACQmPJH4DAJsDAAYACQmPJH4DAJsDAAAA.Totegoat:BAAALgADCgEJAQAAAA==.Totemmalotes:BAAALgADCgcJBwAAAA==.Totemofbear:BAABLgAECn8oAAIkAAkJFhYuCgAeAgAkAAkJFhYuCgAeAgAAAA==.',
Tr='Trandis:BAAALgADCgMJBAABLgAECgkJKAAJANcmAA==.Tranza:BAABLgAECn8cAAQYAAgJOw3YIwB/AQAYAAgJcgrYIwB/AQAcAAYJXwvhfgDrAAAaAAYJzAZBWADlAAAAAA==.Treesus:BAAALgADCgcJBwABLgAECgkJKAACALwiAA==.Trinshunter:BAABLgAECn9BAAQcAAkJGB2qFACtAgAcAAkJGB2qFACtAgAYAAEJ6gnELwA0AAAaAAEJ4gEnmgAZAAABLgAFFAYJGAAGAPoMAA==.',
Tx='Tx:BAACLgAFFH8pAAIUAAYJUiFlEACpAQAUAAYJUiFlEACpAQAuAAQKfywAAhQACAmNIUcQAKcCABQACAmNIUcQAKcCAAAA.',
Ty='Tyedye:BAAALgAECgEJAQAAAA==.',
['Tí']='Tíbs:BAAALgAECgYJCwAAAA==.',
Un='Unbound:BAAALgADCgcJEgAAAA==.Unclegoon:BAAALgAECgEJAQAAAA==.Unholygirl:BAAALgAECgEJAQAAAA==.',
Ut='Utterchaos:BAAALgAECgUJDwAAAA==.',
Va='Vandrina:BAACLgAFFH8HAAICAAMJmQEKBQBKAAACAAMJmQEKBQBKAAAuAAQKfxgAAgIACQncBvAhACABAAIACQncBvAhACABAAAA.Vanthion:BAAALgAECgYJCQAAAA==.Vaporeon:BAAALgAECgEJAQAAAA==.',
Vi='Victreebel:BAAALgAECgcJEQAAAA==.',
Vo='Volg:BAAALgAECgQJBAAAAA==.',
We='Wekko:BAAALgADCgUJBQAAAA==.Wendys:BAABLgAECn8oAAIEAAkJ6xbMUgA/AgAEAAkJ6xbMUgA/AgAAAA==.Wetheals:BAAALgAECgMJBgAAAA==.',
Wh='Whitemonster:BAAALgADCggJDQAAAA==.',
Wi='Wickedhunter:BAAALgADCgYJBgAAAA==.Wimpykid:BAAALgADCggJCAAAAA==.Winar:BAABLgAECn8hAAIEAAgJAhCKgwBwAQAEAAgJAhCKgwBwAQAAAA==.',
Wo='Worgnfreeman:BAABLgAECn8VAAMQAAcJ0gnrswAOAQAQAAcJ+wjrswAOAQAOAAcJIQaRIQDCAAAAAA==.',
Wr='Wraithsdaddy:BAAALgADCgEJAQAAAA==.',
Wt='Wtfdrood:BAAALgAECgQJCQABLgAFFAYJDQAgACsOAA==.Wtfmate:BAAALgAECgIJAgABLgAFFAYJDQAgACsOAA==.Wtfmonk:BAACLgAFFH8NAAIgAAYJKw4yLAAQAQAgAAYJKw4yLAAQAQAuAAQKfygAAiAACQn+HIgMANECACAACQn+HIgMANECAAAA.',
Xa='Xaioli:BAABLgAECn8gAAMHAAkJaSV0CAA9AwAHAAkJaSV0CAA9AwANAAIJwyF/RQCgAAAAAA==.',
Xe='Xemu:BAAALgADCgUJBQAAAA==.Xethani:BAABLgAECn8bAAIdAAkJbhEjCgDDAQAdAAkJbhEjCgDDAQAAAA==.',
Xo='Xorcopressor:BAAALgAECgIJAgAAAA==.',
Xs='Xsaber:BAAALgAECgQJBgAAAA==.',
Ya='Yazmo:BAACLgAFFH8UAAIIAAcJwSMNCADsAQAIAAcJwSMNCADsAQAuAAQKfzcAAggACAmwI70LAJMCAAgACAmwI70LAJMCAAEuAAUUAwkGABgA/xUA.',
Yu='Yuuky:BAACLgAFFH8WAAIKAAYJfhFxIwA+AQAKAAYJfhFxIwA+AQAuAAQKfzQABAoACQl2G7QWAJICAAoACQl2G7QWAJICACUABwkjCaY4AMQAACQAAQnbGpRGAE4AAAAA.',
Za='Zalmo:BAAALgAECgEJAQABLgAECgkJHwAWAJkUAA==.Zarivia:BAAALgADCgMJAwAAAA==.Zartaz:BAABLgAECn8aAAMjAAgJtQyXHAChAQAjAAgJtQyXHAChAQAWAAEJWgc9KgAmAAAAAA==.',
Zb='Zbonez:BAAALgAECggJEwAAAA==.',
Ze='Zendrov:BAABLgAECn8iAAIXAAgJqwVjWADRAAAXAAgJqwVjWADRAAAAAA==.Zenpai:BAAALgAECgEJBgAAAA==.',
Zi='Ziillah:BAAALgAECgIJAgAAAA==.Zinogre:BAABLgAECn8zAAIFAAkJqRUNCwAGAgAFAAkJqRUNCwAGAgAAAA==.',
['Äp']='Äpollo:BAAALgAECgMJCgAAAA==.',
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
