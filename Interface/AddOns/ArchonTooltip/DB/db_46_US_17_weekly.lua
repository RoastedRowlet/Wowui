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

local lookup = {'Shaman-Restoration','Warrior-Protection','Warrior-Fury','Mage-Frost','Shaman-Enhancement','Paladin-Retribution','Warlock-Demonology','Priest-Shadow','DemonHunter-Devourer','Druid-Restoration','Priest-Holy','Warrior-Arms','Warlock-Destruction','DeathKnight-Frost','Warlock-Affliction','DeathKnight-Unholy','Paladin-Holy','Unknown-Unknown','Druid-Balance','Shaman-Elemental','Evoker-Augmentation','Evoker-Devastation','Monk-Windwalker','Hunter-Marksmanship','DemonHunter-Havoc','Paladin-Protection','Priest-Discipline','Hunter-BeastMastery','DemonHunter-Vengeance','Monk-Brewmaster','Monk-Mistweaver','Hunter-Survival','DeathKnight-Blood','Rogue-Subtlety','Evoker-Preservation','Druid-Feral','Druid-Guardian',}
local provider = {region='US',realm='Archimonde',name='US',type='weekly',zone=46,date='2026-06-13',data={Aa='Aanaleaa:BAABLgAECn8XAAIBAAkJFwoeVwBVAQABAAkJFwoeVwBVAQAAAA==.',
Ab='Abelram:BAAALgADCgUJBQAAAA==.',
Ad='Ad:BAABLgAECn8vAAMCAAkJTCGyAwD2AgACAAkJTCGyAwD2AgADAAUJ+QoUZwC/AAABLgAFFAQJBgAEAHcPAA==.Adellon:BAABLgAFFH8LAAIFAAQJ9hcABwBEAQAFAAQJ9hcABwBEAQAAAA==.Adhar:BAAALgAECgQJBgAAAA==.Adrielle:BAABLgAECn8kAAIGAAYJXhvejgBRAQAGAAYJXhvejgBRAQAAAA==.',
Ae='Aeiox:BAAALgADCgMJAwAAAA==.Aevelman:BAABLgAECn81AAIHAAkJXh3nEgC0AgAHAAkJXh3nEgC0AgAAAA==.',
Af='Affinty:BAAALgAECgQJBAABLgAFFAcJFgAIAHkbAA==.',
Ag='Ag:BAAALgAECgQJBQAAAA==.',
Ai='Airphobic:BAABLgAECn8UAAIBAAUJPBuUTAB6AQABAAUJPBuUTAB6AQAAAA==.',
Ak='Akakage:BAAALgAECgEJAQABLgAECggJGQAJACoXAA==.Akakaji:BAABLgAECn8ZAAIJAAgJKhfYPADRAQAJAAgJKhfYPADRAQAAAA==.Akutoku:BAAALgADCgcJDAAAAA==.',
Al='Aland:BAAALgADCggJEgAAAA==.Alea:BAABLgAECn8cAAIKAAgJMxxsFACSAgAKAAgJMxxsFACSAgAAAA==.Almodiir:BAAALgADCgUJCQAAAA==.Almoraz:BAAALgAECgUJBQAAAA==.',
An='Anachron:BAAALgADCgIJAgAAAA==.Anaki:BAAALgADCgcJDwAAAA==.Annakkin:BAAALgAECgYJDAAAAA==.Anomander:BAABLgAECn8jAAIJAAYJtQyAoADeAAAJAAYJtQyAoADeAAAAAA==.Anonymoose:BAAALgADCgQJBAAAAA==.',
Ao='Aol:BAAALgADCgUJBQAAAA==.',
Ar='Ar:BAABLgAECn8XAAILAAcJfBADMgA+AQALAAcJfBADMgA+AQABLgAFFAQJBgAEAHcPAA==.Aratar:BAAALgAECgMJAwAAAA==.Arbiter:BAAALgAECgUJCQAAAA==.Archon:BAACLgAFFH8FAAMMAAMJOxrKLwCYAAAMAAIJhBnKLwCYAAADAAEJqRt9TQBOAAAuAAQKfx4AAwMACAkwHkEXADMCAAMACAkwHkEXADMCAAwABAnJFWxBALwAAAAA.Argig:BAAALgADCgkJCwAAAA==.Arienca:BAABLgAECn85AAMNAAkJchBHFgCYAQANAAgJnhBHFgCYAQAHAAkJaAu0WwCKAQAAAA==.Arwenn:BAAALgAECgEJAQAAAA==.',
As='Aspir:BAEALgAECggJCAABLgAFFAYJFwAOAMEZAA==.Asu:BAABLgAECn8eAAIKAAgJ+RNNMADfAQAKAAgJ+RNNMADfAQAAAA==.',
At='At:BAACLgAFFH8GAAIEAAQJdw/EXgAuAQAEAAQJdw/EXgAuAQAuAAQKfxkAAgQABgnKFROoAIkBAAQABgnKFROoAIkBAAAA.',
Au='Aubrey:BAACLgAFFH8NAAIKAAYJpQVWKwAEAQAKAAYJpQVWKwAEAQAuAAQKfxQAAgoACQlyCqVSAFwBAAoACQlyCqVSAFwBAAAA.Auddio:BAAALgAECgkJAgAAAA==.',
Av='Avengion:BAABLgAECn8VAAIOAAcJ8wnMGAAKAQAOAAcJ8wnMGAAKAQAAAA==.',
Ba='Balthromaw:BAAALgADCggJDQAAAA==.Barbato:BAAALgADCgYJCQAAAA==.Barbie:BAAALgADCgYJBgAAAA==.',
Be='Beararms:BAAALgADCgcJCAAAAA==.Beav:BAAALgAECgYJBwABLgAFFAYJFQAKAOoaAA==.Beefkeeper:BAAALgAFFAIJAgAAAA==.Beldent:BAAALgAECgQJBwAAAA==.Bernard:BAAALgAECgUJBgAAAA==.',
Bi='Bitey:BAAALgAFFAQJBAABLgAFFAgJGAAPACIVAA==.',
Bl='Blazegrave:BAAALgAECgcJEAABLgAECgkJQwAEAHkUAA==.Blazeofglory:BAAALgADCgUJBQABLgAECggJJAAQAKcHAA==.Blazerunner:BAABLgAECn9DAAIEAAkJeRT2QwANAgAEAAkJeRT2QwANAgAAAA==.Blazesmasher:BAAALgAECgkJCQABLgAECgkJQwAEAHkUAA==.Blitzkreig:BAABLgAECn8bAAIQAAkJGRj4MAA4AgAQAAkJGRj4MAA4AgAAAA==.Bluefoot:BAABLgAECn8fAAIBAAYJ/AhoegDqAAABAAYJ/AhoegDqAAAAAA==.Blured:BAABLgAECn9EAAIJAAkJPCRwBQAvAwAJAAkJPCRwBQAvAwAAAA==.',
Bo='Booty:BAABLgAECn8oAAICAAkJvCKMBQDhAgACAAkJvCKMBQDhAgAAAA==.',
Br='Brightblayde:BAABLgAECn8gAAIGAAgJEhLZaACbAQAGAAgJEhLZaACbAQAAAA==.Brynhildre:BAABLgAECn8UAAIRAAcJfgtURABmAQARAAcJfgtURABmAQABLgAFFAYJDQAKAKUFAA==.',
Bu='Buum:BAABLgAECn8XAAICAAkJghY9DQATAgACAAkJghY9DQATAgAAAA==.',
By='Byane:BAAALgADCgYJBgAAAA==.',
['Bä']='Bämba:BAAALgAECgMJAwABLgAECggJKgAEAMsPAA==.',
Ca='Cachelyn:BAAALgAECgYJCAAAAA==.Cali:BAACLgAFFH8hAAIJAAgJAByRDQBBAgAJAAgJAByRDQBBAgAuAAQKfy0AAgkACAmkIeQSAOgCAAkACAmkIeQSAOgCAAAA.Cantouchthes:BAABLgAECn8UAAIEAAgJZB7PQwANAgAEAAgJZB7PQwANAgAAAA==.Captnage:BAAALgADCggJCAAAAA==.Carafe:BAAALgAECgUJCQAAAA==.',
Ce='Cederred:BAAALgAECgUJBQABLgAECggJCgASAAAAAA==.Cedertree:BAAALgADCgcJBwABLgAECggJCgASAAAAAA==.Celline:BAAALgADCgEJAQAAAA==.Cephus:BAABLgAFFH8PAAIKAAcJPBRkEADuAQAKAAcJPBRkEADuAQAAAA==.Cerafina:BAAALgADCgEJAQAAAA==.',
Ch='Chayse:BAAALgAFFAIJAwABLgAFFAYJDQAKAKUFAA==.Choom:BAABLgAECn8fAAMKAAkJuhUONgDQAQAKAAkJuhUONgDQAQATAAYJjRPrLgCOAQAAAA==.Chorizo:BAAALgADCgEJAQAAAA==.Christhina:BAAALgADCgQJBAAAAA==.Chronocide:BAACLgAFFH8OAAIUAAQJmB33GABLAQAUAAQJmB33GABLAQAuAAQKfyoAAhQACQnbHxEQAKkCABQACQnbHxEQAKkCAAAA.Chronophasia:BAABLgAECn8XAAIGAAgJPiACHwCLAgAGAAgJPiACHwCLAgAAAA==.Chroños:BAABLgAECn8UAAMVAAcJEA9ORgANAQAVAAcJ6g1ORgANAQAWAAQJZw7jEwDKAAAAAA==.Chumléé:BAAALgADCgQJBAAAAA==.Chérry:BAACLgAFFH8hAAIJAAcJAR3CDgAzAgAJAAcJAR3CDgAzAgAuAAQKfx8AAgkACQlsIowQAPoCAAkACQlsIowQAPoCAAAA.',
Ci='Ciri:BAAALgAFFAEJAQAAAA==.',
Cl='Climpwimp:BAAALgAECgEJAQAAAA==.Cluntasaur:BAAALgAECgUJBgAAAA==.',
Co='Connerr:BAABLgAECn8aAAIKAAgJtBraLgDnAQAKAAgJtBraLgDnAQAAAA==.Cowage:BAAALgAECgQJCQAAAA==.',
Cr='Crisse:BAAALgAECgUJCgAAAA==.Croh:BAABLgAECn8aAAMQAAgJpBNfVAD0AQAQAAgJpBNfVAD0AQAOAAQJawb3DwCcAAAAAA==.Crucks:BAAALgADCgQJBAAAAA==.Cruknar:BAAALgAFFAMJBAAAAA==.',
Cu='Curita:BAAALgADCgEJAQAAAA==.',
Cy='Cynestra:BAABLgAECn8XAAIRAAkJHRO1HAAbAgARAAkJHRO1HAAbAgAAAA==.Cytheris:BAAALgAECgEJAQABLgAECggJGgAKALQaAA==.',
Da='Daddio:BAEALgADCgIJAwABLgADCgcJBwASAAAAAA==.Dadudadu:BAACLgAFFH8fAAIGAAgJtg5NDgDzAQAGAAgJtg5NDgDzAQAuAAQKfzQAAgYACQkZIHoWAOICAAYACQkZIHoWAOICAAAA.Daffo:BAAALgAECgIJAQAAAA==.Daftmonk:BAACLgAFFH8lAAIXAAcJZyJ1AQB+AgAXAAcJZyJ1AQB+AgAuAAQKfywAAhcACQmSJbECAG8DABcACQmSJbECAG8DAAAA.Daitanfuteki:BAAALgADCgEJAQABLgAFFAQJCAAYAOcVAA==.Dalan:BAAALgAECgEJAQAAAA==.Darkfyre:BAAALgADCgEJAgAAAA==.Darks:BAAALgAECgIJAgAAAA==.Darkwingfish:BAABLgAECn8pAAIJAAkJrRSnRQCyAQAJAAkJrRSnRQCyAQAAAA==.Darmonevil:BAAALgADCgEJAQAAAA==.Dartran:BAAALgADCgIJBwAAAA==.Dasarus:BAABLgAECn8ZAAMZAAgJsxoYEAAiAgAZAAgJsxoYEAAiAgAJAAYJWw9QjwD9AAAAAA==.Dayman:BAABLgAECn8UAAMaAAcJgwJUMwCSAAAaAAcJXAJUMwCSAAAGAAYJ0gF5QQFmAAAAAA==.',
De='Deadmedic:BAAALgAFFAEJAQABLgAECgcJKAAbAKcRAA==.Decày:BAAALgAECgcJEAAAAA==.Demoteck:BAAALgAECgQJBgAAAA==.Demy:BAAALgADCgYJBgAAAA==.Deredris:BAAALgAECgEJAQAAAA==.Deth:BAAALgAECgIJAgABLgAECgMJDAASAAAAAA==.Dethblow:BAAALgAECgMJDAAAAA==.',
Di='Disconnects:BAAALgADCgUJBQAAAA==.Dium:BAAALgAECgEJAQAAAA==.Diwa:BAACLgAFFH8FAAIBAAUJ5QHIPADpAAABAAUJ5QHIPADpAAAuAAQKfxkAAwEACQn8BhNrABUBAAEACQn8BhNrABUBABQABglJB+BRAP8AAAAA.',
Dk='Dklot:BAACLgAFFH8HAAIQAAQJXA7ObAAhAQAQAAQJXA7ObAAhAQAuAAQKfxgAAxAABwlZHC12AHUBABAABwlZHC12AHUBAA4AAQn1DMo6AC4AAAAA.',
Dr='Dracthfear:BAAALgAECgYJBgABLgAFFAUJGQAHAH4lAA==.Dragolot:BAAALgADCgQJBAABLgAFFAQJBwAQAFwOAA==.Draken:BAAALgAECgEJAQAAAA==.Draviin:BAABLgAECn8wAAIcAAkJ9x0qIABjAgAcAAkJ9x0qIABjAgAAAA==.',
Du='Duckcheese:BAAALgADCgEJAQAAAA==.Dunkyn:BAAALgAECgMJBgAAAA==.Durzoblint:BAAALgAECgUJCAAAAA==.',
Dy='Dyemon:BAAALgADCgIJAgAAAA==.',
['Dé']='Déad:BAAALgADCgcJDAAAAA==.',
El='Elementz:BAAALgAECgIJAgAAAA==.Elerae:BAABLgAECn8nAAIGAAkJ+hthFgDjAgAGAAkJ+hthFgDjAgAAAA==.Eleshkigal:BAABLgAECn8oAAMJAAkJ1yaKAwCTAwAJAAkJ1yaKAwCTAwAdAAQJiBrXEQAsAQAAAA==.',
En='Enkeke:BAABLgAECn85AAIQAAkJTR23KABcAgAQAAkJTR23KABcAgAAAA==.',
Er='Eresanna:BAABLgAFFH8OAAIEAAQJpQzVZAAjAQAEAAQJpQzVZAAjAQAAAA==.Ereshkigal:BAAALgAECgUJBgAAAA==.',
Es='Esdeath:BAAALgAECgQJCAABLgAFFAYJDgAZAEATAA==.Estus:BAABLgAECn8VAAMRAAgJNhdKKgC6AQARAAgJNhdKKgC6AQAGAAIJ1gkMeQE9AAAAAA==.',
Ex='Extremefear:BAABLgAECn81AAMNAAkJ/hZIFAAIAQAHAAUJwBRMdABQAQANAAYJ8RVIFAAIAQAAAA==.',
Fa='Fatima:BAAALgAECgIJAwAAAA==.',
Fe='Fearious:BAACLgAFFH8ZAAMHAAUJfiW9JwCdAQAHAAUJ7yS9JwCdAQAPAAIJYSaMEgBxAAAuAAQKfyYABAcACAlBJn4uAB0CAAcABwk3JH4uAB0CAA0AAwl7JaIYANoAAA8AAQncI4ErAGkAAAAA.Felphetamine:BAAALgADCggJCAAAAA==.Fenrisfangs:BAABLgAECn8VAAIcAAkJSA7+UgCmAQAcAAkJSA7+UgCmAQAAAA==.Fenrisul:BAAALgAECgUJBQAAAA==.Feralshunter:BAACLgAFFH8IAAIYAAQJ5xXbFgADAQAYAAQJ5xXbFgADAQAuAAQKfzIAAhgACQkAIZcQALcCABgACQkAIZcQALcCAAAA.Feroond:BAAALgADCgQJBAAAAA==.',
Fi='Fingeritout:BAAALgADCgIJAgAAAA==.Firefly:BAAALgAECgMJAwAAAA==.',
Fl='Florea:BAAALgADCggJDAAAAA==.',
Fo='Fodurzind:BAAALgAECgEJAQAAAA==.Forfoxsake:BAABLgAECn8kAAIeAAgJmR+oEQAoAgAeAAgJmR+oEQAoAgAAAA==.',
Fr='Frogteeth:BAAALgADCgUJBQAAAA==.',
Fu='Furibeav:BAABLgAFFH8VAAIKAAYJ6hpXEQDiAQAKAAYJ6hpXEQDiAQAAAA==.Furrów:BAAALgAECgUJBwAAAA==.',
['Fû']='Fûrrow:BAAALgAECgcJEAAAAA==.',
Ga='Gallindral:BAABLgAECn88AAIJAAkJah34FACYAgAJAAkJah34FACYAgAAAA==.Garanda:BAAALgAECgQJBQAAAA==.Gargantuan:BAAALgADCgMJAwAAAA==.Garreth:BAAALgAECgMJAwAAAA==.Gatito:BAAALgAECgEJAQABLgAECgIJAgASAAAAAA==.Gauthus:BAAALgAECgkJCgAAAA==.',
Ge='Genericnpc:BAABLgAECn8eAAQMAAgJvA/EIgBIAQAMAAgJ7QzEIgBIAQADAAYJVw0cVAD6AAACAAEJfxMxUAA3AAAAAA==.Geobrando:BAABLgAECn8+AAMBAAkJTiBtCwDHAgABAAkJTiBtCwDHAgAUAAYJvB39JgCwAQABLgAFFAIJBAASAAAAAA==.',
Gg='Ggbrews:BAACLgAFFH8oAAIGAAYJriPmDAADAgAGAAYJriPmDAADAgAuAAQKf6AABAYACQlyJnwBAIADAAYACQlyJnwBAIADABEACAlYHMIQAI4CABoABwm5CGsoANAAAAAA.',
Gh='Ghostblaze:BAAALgAECgUJDAABLgAECgkJQwAEAHkUAA==.',
Gi='Gier:BAAALgADCgUJBQAAAA==.Gino:BAAALgADCgEJAQAAAA==.',
Gl='Glacialwrait:BAAALgAECgEJAQAAAA==.Glacious:BAAALgADCgEJAQAAAA==.Glasswings:BAAALgAECgIJAgAAAA==.',
Gn='Gnosh:BAABLgAECn8aAAITAAkJbxQ6GQD/AQATAAkJbxQ6GQD/AQAAAA==.Gnova:BAABLgAECn8jAAIEAAYJfSFSYQC5AQAEAAYJfSFSYQC5AQAAAA==.',
Go='Gorian:BAAALgAECgcJCAAAAA==.',
Gr='Gregorz:BAAALgADCgEJAQAAAA==.Grish:BAAALgAECgEJAQAAAA==.',
Gu='Guidosarduci:BAABLgAECn8iAAIBAAgJhhdgHAA2AgABAAgJhhdgHAA2AgAAAA==.',
Ha='Hairia:BAAALgADCgUJBQAAAA==.Halen:BAAALgADCgcJBwABLgAFFAgJIQAJAAAcAA==.Hardone:BAAALgAECggJDwAAAA==.Harle:BAABLgAECn8bAAIEAAkJmhe0LwBYAgAEAAkJmhe0LwBYAgAAAA==.Hatari:BAAALgAECgMJAwAAAA==.',
He='Hektate:BAABLgAECn8WAAIEAAcJXQu5sAAdAQAEAAcJXQu5sAAdAQABLgAFFAgJHwAGALYOAA==.Henryjones:BAAALgADCgEJAQAAAA==.',
Hi='Hikari:BAABLgAECn8WAAIGAAgJZiFRKgBWAgAGAAgJZiFRKgBWAgABLgAFFAYJKAAUAEcfAA==.Hilkesad:BAAALgAECgQJBAAAAA==.Hizo:BAAALgADCgUJBQAAAA==.',
Ho='Holybeave:BAABLgAECn8eAAMLAAkJNB3/DACFAgAbAAkJaBi5CQCfAgALAAgJqx7/DACFAgABLgAFFAYJFQAKAOoaAA==.Holyshortguy:BAAALgAECgYJDgABLgAFFAUJDAAfAOYNAA==.Hoofer:BAAALgAECgYJDgAAAA==.',
Hu='Hunkomeat:BAABLgAECn8XAAIDAAgJLhzkLAAAAgADAAgJLhzkLAAAAgAAAA==.',
['Hë']='Hënry:BAAALgAECgEJAQAAAA==.',
Ic='Icelmo:BAABLgAFFH8OAAIDAAQJ7BfNGABLAQADAAQJ7BfNGABLAQAAAA==.',
Ih='Ihotyou:BAAALgADCgQJBwAAAA==.',
Il='Ilikeitrough:BAAALgADCgUJBgAAAA==.',
In='Inai:BAAALgADCgcJDAABLgAFFAYJDgAZAEATAA==.Invizww:BAAALgAECgQJBQAAAA==.',
Ir='Ircapslock:BAAALgAECgYJCwAAAA==.',
Iv='Ivorypal:BAABLgAECn8gAAIRAAgJqR/dEACLAgARAAgJqR/dEACLAgAAAA==.',
Ja='Jacksock:BAAALgADCgEJAQAAAA==.Jamzz:BAAALgAECgQJBQABLgAFFAcJHQAYAE0SAA==.Jaromir:BAAALgADCgcJBwAAAA==.Jaskow:BAABLgAECn8uAAIKAAkJjiDQBwA5AwAKAAkJjiDQBwA5AwAAAA==.Jaymick:BAABLgAECn8aAAMgAAkJYhH3IgCGAQAgAAcJEQ73IgCGAQAcAAcJjRLMawBlAQAAAA==.',
Jb='Jbizzler:BAAALgAECgcJBgAAAA==.',
Jc='Jcrypt:BAAALgAECgcJAgAAAA==.',
Je='Jennika:BAABLgAFFH8GAAIgAAMJjwdkIQDIAAAgAAMJjwdkIQDIAAAAAA==.Jernau:BAAALgAECgEJAQAAAA==.Jessortess:BAAALgAECgQJBwAAAA==.',
Jo='Johnwicksdog:BAAALgAECggJEQAAAA==.Jorbies:BAAALgAECgYJCQABLgAFFAcJFgAIAHkbAA==.Jorls:BAACLgAFFH8WAAMIAAcJeRtMAgDeAQAIAAcJeRtMAgDeAQAbAAEJWAEnGwBDAAAuAAQKfxsABAgACQkFHlMIAP8CAAgACQkFHlMIAP8CABsABAnSCc08AMQAAAsAAglAAgl2AFEAAAAA.',
Ju='Junatooka:BAAALgAECgIJAgAAAA==.Jusdatip:BAAALgAECgUJDQAAAA==.',
Ka='Kaelthazed:BAAALgADCgEJAQABLgAFFAMJBgAHAM0UAA==.Kalfu:BAABLgAECn8XAAMcAAgJ0B3gOwDsAQAcAAgJ0B3gOwDsAQAYAAYJoBUDOgB5AQAAAA==.Kameshoga:BAAALgAECgIJAgAAAA==.Kammwin:BAAALgAECgYJEwAAAA==.Karten:BAAALgAECgYJDgAAAA==.Kaylea:BAAALgADCgIJAgAAAA==.',
Ke='Kellandria:BAAALgADCgcJEgAAAA==.',
Ki='Kieraleah:BAAALgAECgcJBwAAAA==.Killjoyss:BAAALgAECgMJAwABLgAECgUJBgASAAAAAA==.Kittêh:BAAALgAECgEJAQAAAA==.',
Kn='Knathor:BAAALgAECgQJBQABLgAECgcJDgASAAAAAA==.',
Ko='Korec:BAAALgAECgcJDgAAAA==.',
Kr='Krasis:BAABLgAECn8XAAIGAAkJvhrLWADYAQAGAAkJvhrLWADYAQAAAA==.Krazermonk:BAACLgAFFH8NAAIXAAQJmxpNDwA+AQAXAAQJmxpNDwA+AQAuAAQKfygAAhcACQmlHnEOAF4CABcACQmlHnEOAF4CAAAA.Krispinwah:BAAALgAFFAIJBAAAAA==.Kristysavage:BAABLgAECn8qAAIcAAkJYiMMCAAYAwAcAAkJYiMMCAAYAwAAAA==.Kroflavinof:BAAALgAECgUJCQAAAA==.',
Ku='Kurosakí:BAAALgAECgEJAQAAAA==.',
Ky='Kyle:BAAALgAECgIJAgABLgAFFAQJDwAGAGMeAA==.',
La='Lanc:BAAALgAECgQJCQAAAA==.Lappytopdog:BAAALgAECgcJDAAAAA==.Larradin:BAAALgADCggJEAAAAA==.Lawnchair:BAAALgAECggJCQAAAA==.',
Le='Lealta:BAAALgAFFAEJAgAAAA==.Leonus:BAAALgAECgQJCQAAAA==.Leviathahn:BAAALgAECgEJAgAAAA==.',
Lh='Lhegholhaz:BAAALgADCgIJAgAAAA==.',
Li='Lichdawg:BAACLgAFFH8WAAMOAAYJChFMBwBwAQAOAAUJChFMBwBwAQAhAAEJAADPXQAAAAAuAAQKfxQAAg4ACAnSE2UOAIwBAA4ACAnSE2UOAIwBAAAA.Lilzayna:BAAALgAECgEJAQABLgAECgUJBgASAAAAAA==.Linthori:BAEALgADCgMJAwABLgAECgcJDQASAAAAAA==.Lirrin:BAAALgAECgEJAQAAAA==.Lithlia:BAAALgADCgcJBwAAAA==.Livvela:BAABLgAECn8kAAIiAAkJsRVpFgDnAQAiAAkJsRVpFgDnAQAAAA==.',
Ll='Llas:BAAALgADCgIJAgAAAA==.',
Lo='Lockdawg:BAACLgAFFH8ZAAIHAAYJeRqrIgC1AQAHAAYJeRqrIgC1AQAuAAQKfyYAAwcACAmFHRImAHoCAAcACAmFHRImAHoCAA0AAQnWFc1sADoAAAAA.Lockedin:BAAALgAECgkJEgAAAA==.Lonne:BAAALgAECgYJDgABLgAFFAIJBAASAAAAAA==.Lover:BAABLgAECn8rAAILAAkJuR5xDACcAgALAAkJuR5xDACcAgAAAA==.',
Lu='Lubu:BAACLgAFFH8OAAIZAAYJQBOUCAB3AQAZAAYJQBOUCAB3AQAuAAQKfxoAAhkACQn+HzUFAO0CABkACQn+HzUFAO0CAAAA.Lucianis:BAAALgADCgQJBwAAAA==.Luckycharmz:BAAALgAECgQJCQABLgAECgcJKAAbAKcRAA==.Luckywar:BAAALgADCgYJBgAAAA==.Luell:BAAALgAECgcJDwAAAA==.Luev:BAAALgAECgYJCAAAAA==.Lumiette:BAABLgAECn8WAAMCAAcJ2Rp1EQDPAQACAAcJ2Rp1EQDPAQADAAMJFAvChQCoAAAAAA==.',
Ly='Lynai:BAABLgAECn8YAAIEAAgJORDtbwCXAQAEAAgJORDtbwCXAQAAAA==.',
['Lá']='Lándwhale:BAACLgAFFH8XAAIiAAQJxSNvEgBzAQAiAAQJxSNvEgBzAQAuAAQKfy4AAiIACQmTJDMEAPoCACIACQmTJDMEAPoCAAAA.',
['Lö']='Löver:BAAALgAECgcJDQAAAA==.',
Ma='Mabil:BAABLgAECn8UAAQHAAcJRhIomAAMAQAHAAYJew0omAAMAQAPAAQJXRWcGAC2AAANAAIJNAz6QAApAAAAAA==.Macktimus:BAABLgAECn8gAAINAAkJYBgqBQAeAgANAAkJYBgqBQAeAgAAAA==.Mage:BAAALgAFFAEJAgAAAA==.Magictonyp:BAAALgAECgUJDwAAAA==.Magicznstuff:BAAALgAECgEJAQABLgAECgMJBgASAAAAAA==.Magna:BAABLgAECn8lAAIDAAkJYRIJKAC6AQADAAkJYRIJKAC6AQAAAA==.Magnusbane:BAAALgADCgUJBgAAAA==.Makili:BAABLgAFFH8SAAIEAAQJxRS9VAA9AQAEAAQJxRS9VAA9AQAAAA==.Maladrix:BAAALgAECgQJDQAAAA==.Mauê:BAAALgADCgEJAQABLgAECgIJAgASAAAAAA==.',
Mc='Mchealer:BAAALgADCgcJDAAAAA==.Mchunter:BAAALgAECgMJAwAAAA==.Mcshadow:BAAALgADCgIJAgAAAA==.',
Me='Menphina:BAAALgAECgIJAgAAAA==.Merigold:BAAALgAECgEJAQABLgAECgQJBAASAAAAAA==.',
Mi='Minnow:BAAALgAECgYJDgAAAA==.Mintchip:BAABLgAECn8QAAIJAAcJ3RdoSgCjAQAJAAcJ3RdoSgCjAQAAAA==.',
Mo='Monk:BAAALgAECgEJAQAAAA==.Monza:BAAALgADCgEJAQABLgAECgkJKAAEAOsWAA==.Moontini:BAAALgADCgYJBgABLgAECgQJDQASAAAAAA==.Mordryn:BAAALgADCgcJBwAAAA==.',
Mu='Muradroz:BAAALgAECgQJBAAAAA==.',
My='Mysternia:BAABLgAECn8VAAILAAgJ2w7tMgA3AQALAAgJ2w7tMgA3AQAAAA==.Myyagie:BAAALgADCgcJEQAAAA==.',
Na='Nalthexon:BAABLgAECn8qAAMfAAgJ2wtFMQAzAQAfAAgJ2wtFMQAzAQAXAAEJXQaLqgAmAAABLgAFFAMJBgAKAHUGAA==.Natureborne:BAAALgAECgYJCQAAAA==.',
Ne='Nedrud:BAAALgADCgUJCAAAAA==.Nelson:BAEALgAECgYJCAABLgAECgkJLQAEAFEeAA==.Nenno:BAAALgADCgEJAQAAAA==.Netzhul:BAAALgAFFAEJAQAAAA==.',
Ni='Night:BAAALgAECgcJEQAAAA==.Nikalos:BAAALgAECgYJDQAAAA==.Nikole:BAAALgAECgMJAwAAAA==.',
No='Noon:BAAALgADCgUJBQABLgAECggJFQARADYXAA==.Notorckrag:BAABLgAECn84AAIeAAkJEyP2AwAIAwAeAAkJEyP2AwAIAwAAAA==.Nozomi:BAAALgAECgcJEgAAAA==.',
Nu='Nut:BAAALgADCgQJBAAAAA==.',
['Nê']='Nêz:BAAALgAECgUJCAAAAA==.',
Oa='Oathbringer:BAAALgAECgQJBAAAAA==.',
Ob='Oblivionz:BAAALgAECgMJAwAAAA==.',
Oc='Ocho:BAAALgADCgYJCQAAAA==.',
Of='Offbrandcleo:BAAALgAECgkJBgAAAA==.',
Ok='Okibi:BAAALgAECgMJBQABLgAFFAYJDgAZAEATAA==.',
Ol='Oldrecipe:BAABLgAFFH8KAAIRAAQJCxTjIgACAQARAAQJCxTjIgACAQAAAA==.Oliange:BAABLgAECn8qAAIEAAgJyw/rcgCRAQAEAAgJyw/rcgCRAQAAAA==.',
Or='Ori:BAEALgADCgcJCwABLgAECgcJDQASAAAAAA==.Originalgank:BAACLgAFFH8LAAIEAAQJgB0TRABkAQAEAAQJgB0TRABkAQAuAAQKfyYAAgQACQkHJIUGAEsDAAQACQkHJIUGAEsDAAAA.',
Oz='Ozzi:BAAALgAECgIJAgAAAA==.',
Pa='Papanell:BAAALgADCgYJCQAAAA==.',
Pe='Peachcobbler:BAAALgAECggJDgAAAA==.Perc:BAAALgAECgcJEAAAAA==.',
Ph='Philsner:BAEALgAECgcJDQAAAA==.Phink:BAAALgAECgQJCgAAAA==.',
Pi='Pinkk:BAABLgAECn8WAAIcAAkJ/xxnGQCIAgAcAAkJ/xxnGQCIAgAAAA==.',
Pl='Plushie:BAABLgAECn8lAAIIAAgJugsuLwBhAQAIAAgJugsuLwBhAQAAAA==.',
Po='Pong:BAABLgAECn8VAAMFAAgJ2BkyDgDJAQAFAAcJeRkyDgDJAQABAAEJ6xLLzAA6AAABLgAECggJKgAjAC4SAA==.Pooqy:BAACLgAFFH8QAAMQAAUJ4SR+NQCMAQAQAAQJ4SR+NQCMAQAhAAEJAAAqRwAAAAAuAAQKfxYAAhAACAlWIrskAKsCABAACAlWIrskAKsCAAAA.Porcel:BAAALgADCgcJCwAAAA==.Potatoteng:BAAALgAFFAEJBAABLgAFFAcJDwAGAOEUAA==.',
Pr='Pritej:BAAALgAECgYJCgABLgAFFAIJBAASAAAAAA==.Proto:BAAALgAECgcJDAAAAA==.',
Pu='Puck:BAAALgAECgIJCAABLgAFFAYJDgAZAEATAA==.',
Py='Pyraleus:BAAALgADCgQJBAAAAA==.',
Qm='Qmpell:BAAALgADCgYJBgAAAA==.',
Qu='Quickchicken:BAAALgAECgEJAgAAAA==.',
Ra='Ragel:BAACLgAFFH8FAAITAAIJjxv9NACkAAATAAIJjxv9NACkAAAuAAQKfzQAAhMACQn3IPEFAPgCABMACQn3IPEFAPgCAAAA.Rainesage:BAABLgAECn8xAAMIAAkJShw3DQCAAgAIAAkJShw3DQCAAgALAAEJxwdRdgAiAAAAAA==.Ralphel:BAABLgAECn8pAAIGAAgJMwerrAAhAQAGAAgJMwerrAAhAQAAAA==.Rasmon:BAAALgAECggJCAAAAA==.Rasu:BAAALgADCgcJBwABLgAECggJGgAjALUMAA==.Ravendark:BAAALgAECgEJAQAAAA==.Rayozap:BAAALgAECgUJBgAAAA==.',
Re='Redeye:BAAALgADCgMJAwAAAA==.Relock:BAAALgAECgMJAwABLgAECggJGgAKALQaAA==.',
Rh='Rhondaa:BAAALgAECgYJEQAAAA==.Rhubarb:BAABLgAECn8/AAMMAAkJjiY3AQBdAwAMAAgJIiY3AQBdAwADAAgJoyQZDQCZAgAAAA==.',
Ri='Ripley:BAAALgAFFAEJAQAAAA==.Riptidepods:BAAALgAECgEJAQAAAA==.Riyci:BAAALgAECgEJAQAAAA==.',
Ro='Rohiem:BAACLgAFFH8GAAIDAAQJRAYdOwC7AAADAAQJRAYdOwC7AAAuAAQKfzUAAgMACQmkGGgZACECAAMACQmkGGgZACECAAAA.',
Ry='Ryan:BAABLgAECn8eAAIGAAkJZR4ZHADBAgAGAAkJZR4ZHADBAgAAAA==.Rylorthas:BAACLgAFFH8fAAILAAcJdhPICAC5AQALAAcJdhPICAC5AQAuAAQKfy0AAgsACQl8HMsSAEoCAAsACQl8HMsSAEoCAAAA.Rylosh:BAAALgAFFAEJAQABLgAFFAcJHwALAHYTAA==.',
['Rî']='Rîkku:BAAALgADCgUJCAAAAA==.',
Sa='Sabot:BAABLgAECn8aAAMkAAkJYxm+BwBUAgAkAAkJYxm+BwBUAgAlAAQJmwpoSgB5AAAAAA==.Sabrook:BAAALgADCggJCAAAAA==.Salazar:BAAALgAECgEJAwAAAA==.Sam:BAAALgAECgUJBAAAAA==.Satisfied:BAABLgAECn8VAAILAAUJRhzmJwCCAQALAAUJRhzmJwCCAQAAAA==.',
Sc='Scottmonk:BAAALgAECgIJBQAAAA==.Scottpaladin:BAAALgAECgEJAQABLgAECgIJBQASAAAAAA==.',
Se='Seath:BAAALgAECggJCAABLgAFFAMJBgAHAM0UAA==.Sentaí:BAAALgAECgIJBAAAAA==.',
Sh='Shamantics:BAAALgAECgIJAwABLgAFFAUJGQAHAH4lAA==.Shamerica:BAACLgAFFH8bAAMFAAgJZxw9AQAaAgAFAAcJWiA9AQAaAgAUAAIJSg3EPgCIAAAuAAQKfz4AAwUACQkyJJQBABoDAAUACQn2IpQBABoDABQACAnNI5gIANECAAAA.Shizuku:BAAALgADCgUJBQAAAA==.Shmooythefox:BAABLgAECn8lAAIcAAcJfCEmNQAEAgAcAAcJfCEmNQAEAgAAAA==.Shokan:BAAALgADCgQJBAAAAA==.Shortleedin:BAAALgAECgIJAQAAAA==.Shòckwave:BAAALgADCgQJBAAAAA==.',
Si='Sinrex:BAAALgADCgIJAgAAAA==.Sixstar:BAAALgADCgEJAQAAAA==.',
Sk='Skrt:BAAALgAECgMJAwAAAA==.Skyleax:BAACLgAFFH8KAAMQAAQJdg37eQAOAQAQAAQJdg37eQAOAQAOAAEJwALwKgA1AAAuAAQKfxgABBAACQkSIEYuAH8CABAACQnoHEYuAH8CAA4ABAkVHkUMAPAAACEAAQn7D0ZLACAAAAAA.',
Sl='Slagothor:BAABLgAECn8VAAIQAAkJywRnmQBNAQAQAAkJywRnmQBNAQAAAA==.Slanesh:BAAALgAECgcJDwABLgAECgcJEAAJAN0XAA==.Sleaze:BAAALgADCgEJAQAAAA==.Sleazus:BAAALgAECgMJAwAAAA==.',
Sm='Smeesha:BAABLgAECn8iAAQjAAgJ0RXIDwDLAQAjAAcJlBbIDwDLAQAWAAYJRQcGJgDzAAAVAAYJ1wahRgDBAAAAAA==.',
Sn='Snaxwell:BAAALgADCgEJAQAAAA==.',
So='Somin:BAAALgAECgMJBAAAAA==.',
Sp='Specialedz:BAAALgADCgUJBwAAAA==.Spekaleks:BAAALgADCgUJBwAAAA==.',
Sq='Squitwurt:BAAALgADCgYJBgAAAA==.',
St='Starbux:BAAALgAECgMJBAAAAA==.Starbúcks:BAAALgAECgIJAwABLgAECgcJKAAbAKcRAA==.Steppers:BAAALgAECgUJAgAAAA==.Straamm:BAAALgADCgMJAwAAAA==.',
Su='Sugarr:BAAALgADCgMJAwAAAA==.Sunfish:BAAALgAECgYJCgAAAA==.',
Sv='Svelana:BAABLgAECn8lAAMXAAgJjSIuDgBiAgAXAAgJjSIuDgBiAgAfAAEJCgvgvwAlAAAAAA==.',
Sy='Syb:BAABLgAECn8bAAQVAAkJZxe2GQAHAgAVAAkJlhW2GQAHAgAWAAQJ4hnwEQDmAAAjAAEJFwU3SwArAAAAAA==.Sylphrena:BAACLgAFFH8TAAIIAAUJgyApDwBvAQAIAAUJgyApDwBvAQAuAAQKfykAAggACQnSIqQGAOgCAAgACQnSIqQGAOgCAAAA.Syssana:BAAALgAECgIJBgAAAA==.',
Ta='Tadaa:BAAALgADCgIJAgAAAA==.Tamerlein:BAAALgAECgMJBQAAAA==.Tamioka:BAAALgAECgYJCAAAAA==.Tanookii:BAAALgAECgYJEwAAAA==.',
Te='Telafar:BAAALgAECgkJAwAAAA==.',
Th='Theinsider:BAACLgAFFH8GAAIHAAMJzRRkcADbAAAHAAMJzRRkcADbAAAuAAQKf0QAAwcACQkDIvINANsCAAcACQkDIvINANsCAA0ABQmQD6crABEBAAAA.Thenezath:BAAALgAECgYJCQAAAA==.Theoutsider:BAAALgAFFAEJAQABLgAFFAMJBgAHAM0UAA==.Thunrus:BAAALgADCgYJBgAAAA==.',
Ti='Tibbles:BAAALgAECgcJCAAAAA==.Tigerbait:BAAALgAECgYJEQAAAA==.Tindril:BAAALgAECgYJBwAAAA==.Tinymo:BAAALgAECgMJAwAAAA==.',
To='Toji:BAABLgAECn8WAAIIAAcJ+hhPIQC6AQAIAAcJ+hhPIQC6AQABLgAFFAYJKAAUAEcfAA==.Tomatoteng:BAACLgAFFH8PAAIGAAcJ4RQNEgDNAQAGAAcJ4RQNEgDNAQAuAAQKfyAAAgYACQmPJH4DAJsDAAYACQmPJH4DAJsDAAAA.Totegoat:BAAALgADCgEJAQAAAA==.Totemmalotes:BAAALgADCgcJBwAAAA==.Totemofbear:BAABLgAECn8oAAIkAAkJFhYDCgAdAgAkAAkJFhYDCgAdAgAAAA==.',
Tr='Trandis:BAAALgADCgMJBAABLgAECgkJKAAJANcmAA==.Tranza:BAABLgAECn8cAAQgAAgJOw1cIwCDAQAgAAgJcgpcIwCDAQAcAAYJXwvhfgDrAAAYAAYJzAZBWADlAAAAAA==.Treesus:BAAALgADCgcJBwABLgAECgkJKAACALwiAA==.Trinshunter:BAABLgAECn9BAAQcAAkJGB3rEwCvAgAcAAkJGB3rEwCvAgAgAAEJ6gnELwA0AAAYAAEJ4gEnmgAZAAABLgAFFAYJGAAGAPoMAA==.',
Tx='Tx:BAACLgAFFH8oAAIUAAYJRx8yEwB9AQAUAAYJRx8yEwB9AQAuAAQKfywAAhQACAmNIUcQAKcCABQACAmNIUcQAKcCAAAA.',
Ty='Tyedye:BAAALgAECgEJAQAAAA==.',
['Tí']='Tíbs:BAAALgAECgYJCwAAAA==.',
Un='Unbound:BAAALgADCgcJEgAAAA==.Unclegoon:BAAALgAECgEJAQAAAA==.Unholygirl:BAAALgAECgEJAQAAAA==.',
Ut='Utterchaos:BAAALgAECgUJDwAAAA==.',
Va='Vandrina:BAABLgAFFH8FAAICAAMJggHhJQBiAAACAAMJggHhJQBiAAAAAA==.Vanthion:BAAALgAECgYJCQAAAA==.Vaporeon:BAAALgAECgEJAQAAAA==.',
Vi='Victreebel:BAAALgAECgcJEQAAAA==.',
Vo='Volg:BAAALgAECgQJBAAAAA==.',
We='Wekko:BAAALgADCgUJBQAAAA==.Wendys:BAABLgAECn8oAAIEAAkJ6xbMUgA/AgAEAAkJ6xbMUgA/AgAAAA==.Wetheals:BAAALgAECgMJBgAAAA==.',
Wh='Whitemonster:BAAALgADCggJDQAAAA==.',
Wi='Wickedhunter:BAAALgADCgYJBgAAAA==.Wimpykid:BAAALgADCggJCAAAAA==.Winar:BAABLgAECn8hAAIEAAgJAhCYgQBxAQAEAAgJAhCYgQBxAQAAAA==.',
Wo='Worgnfreeman:BAABLgAECn8VAAMQAAcJ0gmksAAQAQAQAAcJ+wiksAAQAQAOAAcJIQZbIADGAAAAAA==.',
Wr='Wraithsdaddy:BAAALgADCgEJAQAAAA==.',
Wt='Wtfdrood:BAAALgAECgQJCQABLgAFFAUJDAAfAOYNAA==.Wtfmate:BAAALgAECgIJAgABLgAFFAUJDAAfAOYNAA==.Wtfmonk:BAACLgAFFH8MAAIfAAUJ5g0XKgAQAQAfAAUJ5g0XKgAQAQAuAAQKfygAAh8ACQn+HDgMANACAB8ACQn+HDgMANACAAAA.',
Xa='Xaioli:BAABLgAECn8gAAMHAAkJaSV0CAA9AwAHAAkJaSV0CAA9AwANAAIJwyF/RQCgAAAAAA==.',
Xe='Xemu:BAAALgADCgUJBQAAAA==.Xethani:BAABLgAECn8bAAIdAAkJbhH4CQDEAQAdAAkJbhH4CQDEAQAAAA==.',
Xo='Xorcopressor:BAAALgAECgIJAgAAAA==.',
Xs='Xsaber:BAAALgAECgQJBgAAAA==.',
Ya='Yazmo:BAACLgAFFH8RAAIIAAYJHiRqBwDwAQAIAAYJHiRqBwDwAQAuAAQKfzcAAggACAmwI5YLAJUCAAgACAmwI5YLAJUCAAEuAAUUAwkEABIAAAAA.',
Yu='Yuuky:BAACLgAFFH8VAAIKAAUJuhJaIgA+AQAKAAUJuhJaIgA+AQAuAAQKfzMAAwoACQl2G14WAJECAAoACQl2G14WAJECACUABwkjCUI3AMQAAAAA.',
Za='Zalmo:BAAALgAECgEJAQABLgAECgkJHwAWAJkUAA==.Zarivia:BAAALgADCgMJAwAAAA==.Zartaz:BAABLgAECn8aAAMjAAgJtQyXHAChAQAjAAgJtQyXHAChAQAWAAEJWgeQKQAmAAAAAA==.',
Zb='Zbonez:BAAALgAECggJEgAAAA==.',
Ze='Zendrov:BAABLgAECn8iAAIVAAgJqwULVgDUAAAVAAgJqwULVgDUAAAAAA==.Zenpai:BAAALgAECgEJBgAAAA==.',
Zi='Ziillah:BAAALgAECgIJAgAAAA==.Zinogre:BAABLgAECn8zAAIFAAkJqRXNCgAHAgAFAAkJqRXNCgAHAgAAAA==.',
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
