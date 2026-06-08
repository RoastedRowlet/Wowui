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

local lookup = {'Shaman-Restoration','Warrior-Protection','Warrior-Fury','Mage-Frost','Shaman-Enhancement','Paladin-Retribution','Warlock-Demonology','Priest-Shadow','DemonHunter-Devourer','Druid-Restoration','Priest-Holy','Warrior-Arms','Warlock-Destruction','DeathKnight-Frost','Unknown-Unknown','DeathKnight-Unholy','Paladin-Holy','Druid-Balance','Shaman-Elemental','Evoker-Devastation','Evoker-Augmentation','Monk-Windwalker','Hunter-Marksmanship','DemonHunter-Havoc','Paladin-Protection','Priest-Discipline','Hunter-BeastMastery','DemonHunter-Vengeance','Warlock-Affliction','Monk-Brewmaster','Monk-Mistweaver','Hunter-Survival','DeathKnight-Blood','Rogue-Subtlety','Evoker-Preservation','Druid-Feral','Druid-Guardian',}
local provider = {region='US',realm='Archimonde',name='US',type='weekly',zone=46,date='2026-06-06',data={Aa='Aanaleaa:BAABLgAECn8XAAIBAAkJFwqBUwBXAQABAAkJFwqBUwBXAQAAAA==.',
Ab='Abelram:BAAALgADCgUJBQAAAA==.',
Ad='Ad:BAABLgAECn8vAAMCAAkJTCFQAwD7AgACAAkJTCFQAwD7AgADAAUJ+Qo4YwDAAAABLgAFFAQJBgAEAHcPAA==.Adellon:BAABLgAFFH8KAAIFAAQJZhVvBwA0AQAFAAQJZhVvBwA0AQAAAA==.Adhar:BAAALgAECgEJAgAAAA==.Adrielle:BAABLgAECn8gAAIGAAYJXht3mQA2AQAGAAYJXht3mQA2AQAAAA==.',
Ae='Aeiox:BAAALgADCgMJAwAAAA==.Aevelman:BAABLgAECn8zAAIHAAkJER2PEgCyAgAHAAkJER2PEgCyAgAAAA==.',
Af='Affinty:BAAALgAECgQJBAABLgAFFAcJFgAIAHkbAA==.',
Ag='Ag:BAAALgAECgQJBQAAAA==.',
Ai='Airphobic:BAABLgAECn8UAAIBAAUJPBunSQB7AQABAAUJPBunSQB7AQAAAA==.',
Ak='Akakage:BAAALgAECgEJAQABLgAECggJGQAJACoXAA==.Akakaji:BAABLgAECn8ZAAIJAAgJKheKOgDRAQAJAAgJKheKOgDRAQAAAA==.Akutoku:BAAALgADCgcJDAAAAA==.',
Al='Aland:BAAALgADCggJEgAAAA==.Alea:BAABLgAECn8cAAIKAAgJMxxsFACSAgAKAAgJMxxsFACSAgAAAA==.Almodiir:BAAALgADCgUJCQAAAA==.Almoraz:BAAALgAECgUJBQAAAA==.',
An='Anachron:BAAALgADCgIJAgAAAA==.Anaki:BAAALgADCgcJDwAAAA==.Annakkin:BAAALgAECgYJCwAAAA==.Anomander:BAABLgAECn8hAAIJAAYJWAzwnADaAAAJAAYJWAzwnADaAAAAAA==.Anonymoose:BAAALgADCgQJBAAAAA==.',
Ao='Aol:BAAALgADCgUJBQAAAA==.',
Ar='Ar:BAABLgAECn8XAAILAAcJfBBrMAA+AQALAAcJfBBrMAA+AQABLgAFFAQJBgAEAHcPAA==.Aratar:BAAALgAECgMJAwAAAA==.Arbiter:BAAALgAECgUJCQAAAA==.Archon:BAACLgAFFH8FAAMMAAMJOxpgKwCZAAAMAAIJhBlgKwCZAAADAAEJqRuDSABPAAAuAAQKfx4AAwMACAkwHlcWADYCAAMACAkwHlcWADYCAAwABAnJFXw/ALwAAAAA.Argig:BAAALgADCgcJCAAAAA==.Arienca:BAABLgAECn85AAMNAAkJchBHFgCYAQANAAgJnhBHFgCYAQAHAAkJaAtlVwCSAQAAAA==.Arwenn:BAAALgAECgEJAQAAAA==.',
As='Aspir:BAEALgAECggJCAABLgAFFAYJFwAOAMEZAA==.Asu:BAABLgAECn8bAAIKAAcJnQ81WwAcAQAKAAcJnQ81WwAcAQAAAA==.',
At='At:BAACLgAFFH8GAAIEAAQJdw83WAAuAQAEAAQJdw83WAAuAQAuAAQKfxkAAgQABgnKFROoAIkBAAQABgnKFROoAIkBAAAA.',
Au='Aubrey:BAACLgAFFH8NAAIKAAYJpQWzJwAXAQAKAAYJpQWzJwAXAQAuAAQKfxQAAgoACQlyCqVSAFwBAAoACQlyCqVSAFwBAAAA.Auddio:BAAALgAECgkJAgAAAA==.',
Av='Avengion:BAABLgAECn8VAAIOAAcJ8AlUFwANAQAOAAcJ8AlUFwANAQAAAA==.',
Ba='Balthromaw:BAAALgADCggJDQAAAA==.Barbato:BAAALgADCgYJCQAAAA==.Barbie:BAAALgADCgYJBgAAAA==.',
Be='Beararms:BAAALgADCgcJCAAAAA==.Beav:BAAALgAECgYJBwABLgAFFAYJFQAKAOoaAA==.Beefkeeper:BAAALgAECgIJAwAAAA==.Beldent:BAAALgAECgQJBwAAAA==.Bernard:BAAALgAECgUJBgAAAA==.',
Bl='Blazegrave:BAAALgAECgUJCAABLgAECgkJOgAEAHUSAA==.Blazeofglory:BAAALgADCgUJBQABLgAECgcJDwAPAAAAAA==.Blazerunner:BAABLgAECn86AAIEAAkJdRKqSgD1AQAEAAkJdRKqSgD1AQAAAA==.Blazesmasher:BAAALgAECgkJCQABLgAECgkJOgAEAHUSAA==.Blitzkreig:BAABLgAECn8bAAIQAAkJGRg0LgA+AgAQAAkJGRg0LgA+AgAAAA==.Bluefoot:BAABLgAECn8fAAIBAAYJ/AgldgDrAAABAAYJ/AgldgDrAAAAAA==.Blured:BAABLgAECn88AAIJAAkJOSRoBQArAwAJAAkJOSRoBQArAwAAAA==.',
Bo='Booty:BAABLgAECn8oAAICAAkJvCKMBQDhAgACAAkJvCKMBQDhAgAAAA==.',
Br='Brightblayde:BAABLgAECn8gAAIGAAgJFRI6ZACcAQAGAAgJFRI6ZACcAQAAAA==.Brynhildre:BAABLgAECn8UAAIRAAcJfgtURABmAQARAAcJfgtURABmAQABLgAFFAYJDQAKAKUFAA==.',
Bu='Buum:BAABLgAECn8XAAICAAkJghaIDAAXAgACAAkJghaIDAAXAgAAAA==.',
By='Byane:BAAALgADCgYJBgAAAA==.',
['Bä']='Bämba:BAAALgAECgMJAwABLgAECggJIwAEAGAMAA==.',
Ca='Cachelyn:BAAALgAECgYJBwAAAA==.Cali:BAACLgAFFH8hAAIJAAgJABwKCgBSAgAJAAgJABwKCgBSAgAuAAQKfy0AAgkACAmkIeQSAOgCAAkACAmkIeQSAOgCAAAA.Cantouchthes:BAABLgAECn8UAAIEAAgJZB5FQQASAgAEAAgJZB5FQQASAgAAAA==.Captnage:BAAALgADCggJCAAAAA==.Carafe:BAAALgAECgQJBAAAAA==.',
Ce='Cederred:BAAALgAECgUJBQABLgAECggJCgAPAAAAAA==.Cedertree:BAAALgADCgcJBwABLgAECggJCgAPAAAAAA==.Celline:BAAALgADCgEJAQAAAA==.Cephus:BAABLgAFFH8NAAIKAAYJjBbcEwC2AQAKAAYJjBbcEwC2AQAAAA==.Cerafina:BAAALgADCgEJAQAAAA==.',
Ch='Chayse:BAAALgAFFAIJAwABLgAFFAYJDQAKAKUFAA==.Choom:BAABLgAECn8fAAMKAAkJuhUONgDQAQAKAAkJuhUONgDQAQASAAYJjRPrLgCOAQAAAA==.Chorizo:BAAALgADCgEJAQAAAA==.Christhina:BAAALgADCgQJBAAAAA==.Chronocide:BAACLgAFFH8OAAITAAQJqB3gFQBWAQATAAQJqB3gFQBWAQAuAAQKfyoAAhMACQnbHxEQAKkCABMACQnbHxEQAKkCAAAA.Chronophasia:BAABLgAECn8XAAIGAAgJPiDBHACOAgAGAAgJPiDBHACOAgAAAA==.Chroños:BAABLgAECn8UAAMUAAcJEA/6EgDOAAAVAAcJ6g18QwAQAQAUAAQJZw76EgDOAAAAAA==.Chumléé:BAAALgADCgQJBAAAAA==.Chérry:BAACLgAFFH8cAAIJAAcJmBg5FwDVAQAJAAcJmBg5FwDVAQAuAAQKfx8AAgkACQlsIowQAPoCAAkACQlsIowQAPoCAAAA.',
Cl='Climpwimp:BAAALgAECgEJAQAAAA==.Cluntasaur:BAAALgAECgUJBgAAAA==.',
Co='Connerr:BAABLgAECn8aAAIKAAgJtBqsLQDmAQAKAAgJtBqsLQDmAQAAAA==.Cowage:BAAALgAECgQJCQAAAA==.',
Cr='Crisse:BAAALgAECgUJCgAAAA==.Croh:BAABLgAECn8aAAMQAAgJpBNfVAD0AQAQAAgJpBNfVAD0AQAOAAQJawb3DwCcAAAAAA==.Crucks:BAAALgADCgQJBAAAAA==.Cruknar:BAAALgAFFAMJBAAAAA==.',
Cu='Curita:BAAALgADCgEJAQAAAA==.',
Cy='Cynestra:BAABLgAECn8XAAIRAAkJHROYGwAcAgARAAkJHROYGwAcAgAAAA==.Cytheris:BAAALgAECgEJAQABLgAECggJGgAKALQaAA==.',
Da='Daddio:BAEALgADCgIJAwABLgADCgcJBwAPAAAAAA==.Dadudadu:BAACLgAFFH8YAAIGAAgJ+AxuEgCxAQAGAAgJ+AxuEgCxAQAuAAQKfzQAAgYACQkZIHoWAOICAAYACQkZIHoWAOICAAAA.Daffo:BAAALgAECgIJAQAAAA==.Daftmonk:BAACLgAFFH8hAAIWAAcJ8yGDAQBjAgAWAAcJ8yGDAQBjAgAuAAQKfywAAhYACQmSJbECAG8DABYACQmSJbECAG8DAAAA.Daitanfuteki:BAAALgADCgEJAQABLgAFFAQJCAAXAOcVAA==.Dalan:BAAALgAECgEJAQAAAA==.Darkfyre:BAAALgADCgEJAgAAAA==.Darks:BAAALgAECgIJAgAAAA==.Darkwingfish:BAABLgAECn8pAAIJAAkJrRRFQwCyAQAJAAkJrRRFQwCyAQAAAA==.Dartran:BAAALgADCgIJBwAAAA==.Dasarus:BAABLgAECn8VAAMYAAgJORlyFADdAQAYAAcJGhtyFADdAQAJAAYJWw/IigD9AAAAAA==.Dayman:BAABLgAECn8UAAMZAAcJgwKQMQCSAAAZAAcJXAKQMQCSAAAGAAYJ0gFlNgFmAAAAAA==.',
De='Deadmedic:BAAALgAECggJEQABLgAECgcJJAAaAKcRAA==.Decày:BAAALgAECgcJEAAAAA==.Demoteck:BAAALgAECgQJBgAAAA==.Deredris:BAAALgAECgEJAQAAAA==.Deth:BAAALgAECgIJAgABLgAECgMJDAAPAAAAAA==.Dethblow:BAAALgAECgMJDAAAAA==.',
Di='Disconnects:BAAALgADCgUJBQAAAA==.Dium:BAAALgAECgEJAQAAAA==.Diwa:BAACLgAFFH8FAAIBAAUJ5QGONwDtAAABAAUJ5QGONwDtAAAuAAQKfxkAAwEACQn8BttmABcBAAEACQn8BttmABcBABMABglJB+BRAP8AAAAA.',
Dk='Dklot:BAACLgAFFH8GAAIQAAQJegp4cwANAQAQAAQJegp4cwANAQAuAAQKfxgAAxAABwlZHMJyAHYBABAABwlZHMJyAHYBAA4AAQn1DIg2ADAAAAAA.',
Dr='Dracthfear:BAAALgAECgEJAQABLgAFFAUJFQAHAFUlAA==.Dragolot:BAAALgADCgQJBAABLgAFFAQJBgAQAHoKAA==.Draken:BAAALgAECgEJAQAAAA==.Draviin:BAABLgAECn8wAAIbAAkJ9x3nHQBnAgAbAAkJ9x3nHQBnAgAAAA==.',
Du='Duckcheese:BAAALgADCgEJAQAAAA==.Dunkyn:BAAALgAECgMJBgAAAA==.Durzoblint:BAAALgAECgUJCAAAAA==.',
Dy='Dyemon:BAAALgADCgIJAgAAAA==.',
['Dé']='Déad:BAAALgADCgcJDAAAAA==.',
El='Elementz:BAAALgAECgIJAgAAAA==.Elerae:BAABLgAECn8nAAIGAAkJ+hthFgDjAgAGAAkJ+hthFgDjAgAAAA==.Eleshkigal:BAABLgAECn8oAAMJAAkJ1yaKAwCTAwAJAAkJ1yaKAwCTAwAcAAQJiBoLEQAtAQAAAA==.',
En='Enkeke:BAABLgAECn85AAIQAAkJTR2MJgBgAgAQAAkJTR2MJgBgAgAAAA==.',
Er='Eresanna:BAABLgAFFH8LAAIEAAQJKwv5YAAeAQAEAAQJKwv5YAAeAQAAAA==.Ereshkigal:BAAALgAECgUJBgAAAA==.',
Es='Esdeath:BAAALgAECgQJCAABLgAFFAYJCgAYAOMQAA==.Estus:BAABLgAECn8VAAMRAAgJNhfdKAC7AQARAAgJNhfdKAC7AQAGAAIJ1gmeawE9AAAAAA==.',
Ex='Extremefear:BAABLgAECn81AAMNAAkJ/hZ3EwAIAQAHAAUJwBScbwBWAQANAAYJ8RV3EwAIAQAAAA==.',
Fa='Fatima:BAAALgAECgIJAwAAAA==.',
Fe='Fearious:BAACLgAFFH8VAAMHAAUJVSXiJwCIAQAHAAUJxiTiJwCIAQAdAAEJYSZ3EwBlAAAuAAQKfyYABAcACAlBJuEsAB8CAAcABwk3JOEsAB8CAA0AAwl7JXsXANwAAB0AAQncI+ooAGoAAAAA.Felphetamine:BAAALgADCggJCAAAAA==.Fenrisfangs:BAABLgAECn8VAAIbAAkJSA6/TQCtAQAbAAkJSA6/TQCtAQAAAA==.Fenrisul:BAAALgAECgUJBQAAAA==.Feralshunter:BAACLgAFFH8IAAIXAAQJ5xWBFAAOAQAXAAQJ5xWBFAAOAQAuAAQKfzIAAhcACQkAIZcQALcCABcACQkAIZcQALcCAAAA.Feroond:BAAALgADCgQJBAAAAA==.',
Fi='Fingeritout:BAAALgADCgIJAgAAAA==.Firefly:BAAALgAECgMJAwAAAA==.',
Fl='Florea:BAAALgADCggJDAAAAA==.',
Fo='Forfoxsake:BAABLgAECn8kAAIeAAgJmR/bEAArAgAeAAgJmR/bEAArAgAAAA==.',
Fr='Frogteeth:BAAALgADCgUJBQAAAA==.',
Fu='Furibeav:BAABLgAFFH8VAAIKAAYJ6hp6DwDuAQAKAAYJ6hp6DwDuAQAAAA==.Furrów:BAAALgAECgUJBgAAAA==.',
['Fû']='Fûrrow:BAAALgAECgcJEAAAAA==.',
Ga='Gallindral:BAABLgAECn88AAIJAAkJah36EwCYAgAJAAkJah36EwCYAgAAAA==.Garanda:BAAALgAECgQJBQAAAA==.Gargantuan:BAAALgADCgMJAwAAAA==.Garreth:BAAALgAECgMJAwAAAA==.Gatito:BAAALgAECgEJAQABLgAECgIJAgAPAAAAAA==.Gauthus:BAAALgAECgkJCQAAAA==.',
Ge='Genericnpc:BAABLgAECn8aAAQMAAgJBQ2yLAANAQAMAAgJkAmyLAANAQADAAYJWg0lUAD/AAACAAEJfxMpTQA4AAAAAA==.Geobrando:BAABLgAECn84AAMBAAkJTiBtCwDHAgABAAkJTiBtCwDHAgATAAYJmQ9WYwCrAAABLgAFFAIJAgAPAAAAAA==.',
Gg='Ggbrews:BAACLgAFFH8jAAIGAAYJsyI1CwD4AQAGAAYJsyI1CwD4AQAuAAQKf5gABAYACQlyJu4BAHUDAAYACQlyJu4BAHUDABEACAlYHO0PAJACABkABwm5CP4mANAAAAAA.',
Gh='Ghostblaze:BAAALgAECgUJDAABLgAECgkJOgAEAHUSAA==.',
Gi='Gier:BAAALgADCgUJBQAAAA==.Gino:BAAALgADCgEJAQAAAA==.',
Gl='Glacious:BAAALgADCgEJAQAAAA==.Glasswings:BAAALgAECgIJAgAAAA==.',
Gn='Gnosh:BAABLgAECn8aAAISAAkJbxQOGAABAgASAAkJbxQOGAABAgAAAA==.Gnova:BAABLgAECn8jAAIEAAYJfSHTXgC9AQAEAAYJfSHTXgC9AQAAAA==.',
Go='Gorian:BAAALgAECgcJCAAAAA==.',
Gr='Gregorz:BAAALgADCgEJAQAAAA==.Grish:BAAALgAECgEJAQAAAA==.',
Gu='Guidosarduci:BAABLgAECn8iAAIBAAgJhhdgHAA2AgABAAgJhhdgHAA2AgAAAA==.',
Ha='Hairia:BAAALgADCgUJBQAAAA==.Halen:BAAALgADCgcJBwABLgAFFAgJIQAJAAAcAA==.Hardone:BAAALgAECggJCwAAAA==.Harle:BAABLgAECn8bAAIEAAkJmhejLQBcAgAEAAkJmhejLQBcAgAAAA==.Hatari:BAAALgAECgMJAwAAAA==.',
He='Hektate:BAABLgAECn8WAAIEAAcJXQu3qQAmAQAEAAcJXQu3qQAmAQABLgAFFAgJGAAGAPgMAA==.Henryjones:BAAALgADCgEJAQAAAA==.',
Hi='Hikari:BAABLgAECn8WAAIGAAgJZiG5JwBZAgAGAAgJZiG5JwBZAgABLgAFFAYJKAATAEcfAA==.Hilkesad:BAAALgAECgQJBAAAAA==.Hizo:BAAALgADCgUJBQAAAA==.',
Ho='Holybeave:BAABLgAECn8eAAMLAAkJNB3/DACFAgAaAAkJaBi5CQCfAgALAAgJqx7/DACFAgABLgAFFAYJFQAKAOoaAA==.Holyshortguy:BAAALgAECgYJDgABLgAFFAMJBwAfADMMAA==.Hoofer:BAAALgAECgYJDgAAAA==.',
Hu='Hunkomeat:BAABLgAECn8XAAIDAAgJLhzkLAAAAgADAAgJLhzkLAAAAgAAAA==.',
['Hë']='Hënry:BAAALgAECgEJAQAAAA==.',
Ic='Icelmo:BAABLgAFFH8NAAIDAAQJYxVbHQAuAQADAAQJYxVbHQAuAQAAAA==.',
Ih='Ihotyou:BAAALgADCgQJBwAAAA==.',
Il='Ilikeitrough:BAAALgADCgMJAwAAAA==.',
In='Inai:BAAALgADCgcJDAABLgAFFAYJCgAYAOMQAA==.Invizww:BAAALgAECgQJBQAAAA==.',
Ir='Ircapslock:BAAALgAECgYJCwAAAA==.',
Iv='Ivorypal:BAABLgAECn8gAAIRAAgJqR/dEACLAgARAAgJqR/dEACLAgAAAA==.',
Ja='Jacksock:BAAALgADCgEJAQAAAA==.Jamzz:BAAALgAECgEJAQABLgAFFAcJGAAXANgOAA==.Jaromir:BAAALgADCgcJBwAAAA==.Jaskow:BAABLgAECn8uAAIKAAkJjiByBwA5AwAKAAkJjiByBwA5AwAAAA==.Jaymick:BAABLgAECn8aAAMgAAkJYhF/IQCMAQAgAAcJEQ5/IQCMAQAbAAcJjRI8ZgBqAQAAAA==.',
Jb='Jbizzler:BAAALgAECgcJBgAAAA==.',
Jc='Jcrypt:BAAALgAECgcJAgAAAA==.',
Je='Jennika:BAABLgAFFH8GAAIgAAMJjwdYHwDJAAAgAAMJjwdYHwDJAAAAAA==.Jernau:BAAALgAECgEJAQAAAA==.Jessortess:BAAALgAECgQJBwAAAA==.',
Jo='Johnwicksdog:BAAALgAECggJEQAAAA==.Jorbies:BAAALgAECgYJCQABLgAFFAcJFgAIAHkbAA==.Jorls:BAACLgAFFH8WAAMIAAcJeRtMAgDeAQAIAAcJeRtMAgDeAQAaAAEJWAEnGwBDAAAuAAQKfxsABAgACQkFHlMIAP8CAAgACQkFHlMIAP8CABoABAnSCc08AMQAAAsAAglAAgl2AFEAAAAA.',
Ju='Junatooka:BAAALgAECgIJAgAAAA==.Jusdatip:BAAALgAECgUJDQAAAA==.',
Ka='Kaelthazed:BAAALgADCgEJAQABLgAECgkJRAAHAAMiAA==.Kalfu:BAABLgAECn8XAAMbAAgJ0B0rOADyAQAbAAgJ0B0rOADyAQAXAAYJoBUDOgB5AQAAAA==.Kameshoga:BAAALgAECgIJAgAAAA==.Kammwin:BAAALgAECgYJEwAAAA==.Karten:BAAALgAECgUJCQAAAA==.Kaylea:BAAALgADCgIJAgAAAA==.',
Ke='Kellandria:BAAALgADCgcJEgAAAA==.',
Ki='Kieraleah:BAAALgAECgcJBwAAAA==.Kittêh:BAAALgAECgEJAQAAAA==.',
Kn='Knathor:BAAALgAECgQJBQABLgAECgcJDgAPAAAAAA==.',
Ko='Korec:BAAALgAECgcJDgAAAA==.',
Kr='Krasis:BAABLgAECn8XAAIGAAkJvhrLWADYAQAGAAkJvhrLWADYAQAAAA==.Krazermonk:BAACLgAFFH8MAAIWAAQJDRq8DgA+AQAWAAQJDRq8DgA+AQAuAAQKfygAAhYACQmlHsQNAGACABYACQmlHsQNAGACAAAA.Krispinwah:BAAALgAFFAIJAgAAAA==.Kristysavage:BAABLgAECn8qAAIbAAkJYiMYBwAeAwAbAAkJYiMYBwAeAwAAAA==.Kroflavinof:BAAALgAECgUJCQAAAA==.',
Ku='Kurosakí:BAAALgAECgEJAQAAAA==.',
Ky='Kyle:BAAALgAECgEJAQAAAA==.',
La='Lanc:BAAALgAECgQJCQAAAA==.Lappytopdog:BAAALgAECgcJCwAAAA==.Larradin:BAAALgADCggJEAAAAA==.Lawnchair:BAAALgAECggJCQAAAA==.',
Le='Lealta:BAAALgAFFAEJAgAAAA==.Leonus:BAAALgAECgQJCQAAAA==.Leviathahn:BAAALgAECgEJAgAAAA==.',
Lh='Lhegholhaz:BAAALgADCgIJAgAAAA==.',
Li='Lichdawg:BAACLgAFFH8WAAMOAAYJChH4BQByAQAOAAUJChH4BQByAQAhAAEJAABcVwAAAAAuAAQKfxQAAg4ACAnSE2YNAI4BAA4ACAnSE2YNAI4BAAAA.Lilzayna:BAAALgAECgEJAQABLgAECgUJBgAPAAAAAA==.Linthori:BAEALgADCgMJAwABLgAECgcJDQAPAAAAAA==.Lithlia:BAAALgADCgcJBwAAAA==.Livvela:BAABLgAECn8kAAIiAAkJsRViFQDnAQAiAAkJsRViFQDnAQAAAA==.',
Ll='Llas:BAAALgADCgIJAgAAAA==.',
Lo='Lockdawg:BAACLgAFFH8XAAIHAAYJ7hCwMgBkAQAHAAYJ7hCwMgBkAQAuAAQKfyYAAwcACAmFHRImAHoCAAcACAmFHRImAHoCAA0AAQnWFc1sADoAAAAA.Lockedin:BAAALgAECgkJEgAAAA==.Lonne:BAAALgAECgYJDgABLgAFFAIJBAAPAAAAAA==.Lover:BAABLgAECn8rAAILAAkJuR6iCwCfAgALAAkJuR6iCwCfAgAAAA==.',
Lu='Lubu:BAACLgAFFH8KAAIYAAYJ4xCsBwBxAQAYAAYJ4xCsBwBxAQAuAAQKfxoAAhgACQn+H78EAPACABgACQn+H78EAPACAAAA.Lucianis:BAAALgADCgQJBwAAAA==.Luckycharmz:BAAALgAECgQJCQABLgAECgcJJAAaAKcRAA==.Luckywar:BAAALgADCgYJBgAAAA==.Luell:BAAALgAECgcJDwAAAA==.Luev:BAAALgAECgYJCAAAAA==.Lumiette:BAABLgAECn8WAAMCAAcJ2RqXEADSAQACAAcJ2RqXEADSAQADAAMJFAvChQCoAAAAAA==.',
Ly='Lynai:BAABLgAECn8XAAIEAAcJ1g8/hgBkAQAEAAcJ1g8/hgBkAQAAAA==.',
['Lá']='Lándwhale:BAACLgAFFH8XAAIiAAQJxSP3DwB7AQAiAAQJxSP3DwB7AQAuAAQKfy4AAiIACQmTJM0DAPwCACIACQmTJM0DAPwCAAAA.',
['Lö']='Löver:BAAALgAECgcJDQAAAA==.',
Ma='Mabil:BAABLgAECn8UAAQHAAcJRhJalAAOAQAHAAYJew1alAAOAQAdAAQJXRWcGAC2AAANAAIJNAx8PgArAAAAAA==.Macktimus:BAABLgAECn8fAAINAAkJGBjVBAAfAgANAAkJGBjVBAAfAgAAAA==.Mage:BAAALgAFFAEJAgAAAA==.Magictonyp:BAAALgAECgUJBwAAAA==.Magicznstuff:BAAALgAECgEJAQABLgAECgMJBgAPAAAAAA==.Magna:BAABLgAECn8lAAIDAAkJYRILJgDAAQADAAkJYRILJgDAAQAAAA==.Magnusbane:BAAALgADCgMJAwAAAA==.Makili:BAABLgAFFH8PAAIEAAQJxRRaTgA+AQAEAAQJxRRaTgA+AQAAAA==.Maladrix:BAAALgAECgQJDQAAAA==.Mauê:BAAALgADCgEJAQABLgAECgIJAgAPAAAAAA==.',
Mc='Mchealer:BAAALgADCgYJCwAAAA==.Mchunter:BAAALgAECgMJAwAAAA==.Mcshadow:BAAALgADCgIJAgAAAA==.',
Me='Menphina:BAAALgAECgIJAgAAAA==.Merigold:BAAALgAECgEJAQABLgAECgQJBAAPAAAAAA==.',
Mi='Minnow:BAAALgAECgYJDgAAAA==.Mintchip:BAABLgAECn8QAAIJAAcJ3RfcRwCjAQAJAAcJ3RfcRwCjAQAAAA==.',
Mo='Monk:BAAALgAECgEJAQAAAA==.Monza:BAAALgADCgEJAQABLgAECgkJKAAEAOsWAA==.Moontini:BAAALgADCgYJBgABLgAECgQJDQAPAAAAAA==.Mordryn:BAAALgADCgcJBwAAAA==.',
My='Mysternia:BAABLgAECn8VAAILAAgJ2w4lMQA5AQALAAgJ2w4lMQA5AQAAAA==.Myyagie:BAAALgADCgcJEQAAAA==.',
Na='Nalthexon:BAABLgAECn8qAAMfAAgJ2wtFMQAzAQAfAAgJ2wtFMQAzAQAWAAEJXQbGogAmAAABLgAFFAMJBgAKAHUGAA==.Natureborne:BAAALgAECgYJCQAAAA==.',
Ne='Nedrud:BAAALgADCgUJCAAAAA==.Nelson:BAEALgAECgYJCAABLgAECgkJLQAEAFEeAA==.Nenno:BAAALgADCgEJAQAAAA==.Netzhul:BAAALgAFFAEJAQAAAA==.',
Ni='Night:BAAALgAECgcJEQAAAA==.Nikalos:BAAALgAECgYJDQAAAA==.Nikole:BAAALgAECgMJAwAAAA==.',
No='Noon:BAAALgADCgUJBQABLgAECggJFQARADYXAA==.Notorckrag:BAABLgAECn84AAIeAAkJEyO3AwALAwAeAAkJEyO3AwALAwAAAA==.Nozomi:BAAALgAECgUJBwAAAA==.',
Nu='Nut:BAAALgADCgQJBAAAAA==.',
['Nê']='Nêz:BAAALgAECgUJCAAAAA==.',
Oa='Oathbringer:BAAALgAECgQJBAAAAA==.',
Ob='Oblivionz:BAAALgAECgMJAwAAAA==.',
Oc='Ocho:BAAALgADCgYJCQAAAA==.',
Of='Offbrandcleo:BAAALgAECgkJBgAAAA==.',
Ok='Okibi:BAAALgAECgMJBQABLgAFFAYJCgAYAOMQAA==.',
Ol='Oldrecipe:BAABLgAFFH8JAAIRAAQJXBBHJADyAAARAAQJXBBHJADyAAAAAA==.Oliange:BAABLgAECn8jAAIEAAgJYAwGhQBnAQAEAAgJYAwGhQBnAQAAAA==.',
Or='Ori:BAEALgADCgcJCwABLgAECgcJDQAPAAAAAA==.Originalgank:BAACLgAFFH8HAAIEAAMJIh3CaAAKAQAEAAMJIh3CaAAKAQAuAAQKfx4AAgQACAmXJHARAOwCAAQACAmXJHARAOwCAAAA.',
Pa='Papanell:BAAALgADCgYJCQAAAA==.',
Pe='Peachcobbler:BAAALgAECggJDgAAAA==.Perc:BAAALgAECgcJDAAAAA==.',
Ph='Philsner:BAEALgAECgcJDQAAAA==.Phink:BAAALgAECgQJCgAAAA==.',
Pi='Pinkk:BAABLgAECn8WAAIbAAkJ/xxKFwCPAgAbAAkJ/xxKFwCPAgAAAA==.',
Pl='Plushie:BAABLgAECn8hAAIIAAgJ7gmPLwBZAQAIAAgJ7gmPLwBZAQAAAA==.',
Po='Pong:BAABLgAECn8VAAMFAAgJ2BktDQDRAQAFAAcJeRktDQDRAQABAAEJ6xKqxAA6AAABLgAECggJKgAjAC4SAA==.Pooqy:BAACLgAFFH8QAAMQAAUJ4SSXLQCTAQAQAAQJ4SSXLQCTAQAhAAEJAAA5QgAAAAAuAAQKfxYAAhAACAlWIrskAKsCABAACAlWIrskAKsCAAAA.Porcel:BAAALgADCgcJCwAAAA==.Potatoteng:BAAALgAFFAEJAwABLgAFFAYJDgAGAN8VAA==.',
Pr='Pritej:BAAALgAECgYJCgABLgAFFAIJBAAPAAAAAA==.Proto:BAAALgAECgcJDAAAAA==.',
Pu='Puck:BAAALgAECgIJCAABLgAFFAYJCgAYAOMQAA==.',
Py='Pyraleus:BAAALgADCgQJBAAAAA==.',
Qm='Qmpell:BAAALgADCgYJBgAAAA==.',
Qu='Quickchicken:BAAALgAECgEJAgAAAA==.',
Ra='Ragel:BAABLgAECn80AAISAAkJ9yCJBQD5AgASAAkJ9yCJBQD5AgAAAA==.Rainesage:BAABLgAECn8xAAMIAAkJShyJDACDAgAIAAkJShyJDACDAgALAAEJxweBcgAiAAAAAA==.Ralphel:BAABLgAECn8lAAIGAAgJ/gYopwAgAQAGAAgJ/gYopwAgAQAAAA==.Rasmon:BAAALgAECggJCAAAAA==.Rasu:BAAALgADCgcJBwABLgAECggJGgAjALUMAA==.Ravendark:BAAALgAECgEJAQAAAA==.Rayozap:BAAALgAECgUJBgAAAA==.',
Re='Redeye:BAAALgADCgMJAwAAAA==.Relock:BAAALgAECgMJAwABLgAECggJGgAKALQaAA==.',
Rh='Rhondaa:BAAALgAECgYJEQAAAA==.Rhubarb:BAABLgAECn8/AAMMAAkJjiYFAQBhAwAMAAgJIiYFAQBhAwADAAgJoyRYDACdAgAAAA==.',
Ri='Riptidepods:BAAALgAECgEJAQAAAA==.Riyci:BAAALgAECgEJAQAAAA==.',
Ro='Rohiem:BAACLgAFFH8FAAIDAAQJ/AV3NwC5AAADAAQJ/AV3NwC5AAAuAAQKfzUAAgMACQmkGM8XACkCAAMACQmkGM8XACkCAAAA.',
Ry='Ryan:BAABLgAECn8eAAIGAAkJZR4ZHADBAgAGAAkJZR4ZHADBAgAAAA==.Rylorthas:BAACLgAFFH8fAAILAAcJdhNABwDDAQALAAcJdhNABwDDAQAuAAQKfy0AAgsACQl8HMsSAEoCAAsACQl8HMsSAEoCAAAA.Rylosh:BAAALgAFFAEJAQABLgAFFAcJHwALAHYTAA==.',
['Rî']='Rîkku:BAAALgADCgUJCAAAAA==.',
Sa='Sabot:BAABLgAECn8aAAMkAAkJYxlEBwBWAgAkAAkJYxlEBwBWAgAlAAQJmwr8RQB5AAAAAA==.Sabrook:BAAALgADCggJCAAAAA==.Salazar:BAAALgAECgEJAwAAAA==.Sam:BAAALgAECgUJBAAAAA==.Satisfied:BAABLgAECn8VAAILAAUJRhxlJgCEAQALAAUJRhxlJgCEAQAAAA==.',
Sc='Scottmonk:BAAALgAECgIJBQAAAA==.Scottpaladin:BAAALgAECgEJAQABLgAECgIJBQAPAAAAAA==.',
Se='Sentaí:BAAALgAECgIJBAAAAA==.',
Sh='Shamerica:BAACLgAFFH8bAAMFAAgJZxztAAAjAgAFAAcJWiDtAAAjAgATAAIJSg2JOgCMAAAuAAQKfz4AAwUACQkyJGABAB8DAAUACQn2ImABAB8DABMACAnNIwMIANICAAAA.Shizuku:BAAALgADCgUJBQAAAA==.Shmooythefox:BAABLgAECn8lAAIbAAcJfCHwMQAJAgAbAAcJfCHwMQAJAgAAAA==.Shokan:BAAALgADCgQJBAAAAA==.Shortleedin:BAAALgAECgIJAQAAAA==.Shòckwave:BAAALgADCgQJBAAAAA==.',
Si='Sinrex:BAAALgADCgIJAgAAAA==.Sixstar:BAAALgADCgEJAQAAAA==.',
Sk='Skrt:BAAALgAECgMJAwAAAA==.Skyleax:BAACLgAFFH8KAAMQAAQJdg1ZcAATAQAQAAQJdg1ZcAATAQAOAAEJwAJXJgA1AAAuAAQKfxgABBAACQkSIEYuAH8CABAACQnoHEYuAH8CAA4ABAkVHkUMAPAAACEAAQn7D0ZLACAAAAAA.',
Sl='Slagothor:BAABLgAECn8VAAIQAAkJywRnmQBNAQAQAAkJywRnmQBNAQAAAA==.Slanesh:BAAALgAECgcJCwABLgAECgcJEAAJAN0XAA==.Sleaze:BAAALgADCgEJAQAAAA==.Sleazus:BAAALgAECgMJAwAAAA==.',
Sm='Smeesha:BAABLgAECn8fAAQjAAgJwhW3DwDIAQAjAAcJgxa3DwDIAQAUAAYJRQcGJgDzAAAVAAYJ1wahRgDBAAAAAA==.',
Sn='Snaxwell:BAAALgADCgEJAQAAAA==.',
So='Somin:BAAALgAECgMJBAAAAA==.',
Sp='Specialedz:BAAALgADCgIJAgAAAA==.Spekaleks:BAAALgADCgUJBwAAAA==.',
Sq='Squitwurt:BAAALgADCgYJBgAAAA==.',
St='Starbux:BAAALgAECgMJBAAAAA==.Starbúcks:BAAALgAECgIJAwABLgAECgcJJAAaAKcRAA==.Steppers:BAAALgAECgUJAgAAAA==.Straamm:BAAALgADCgMJAwAAAA==.',
Su='Sugarr:BAAALgADCgMJAwAAAA==.Sunfish:BAAALgAECgYJCgAAAA==.',
Sv='Svelana:BAABLgAECn8lAAMWAAgJjSJ+DQBkAgAWAAgJjSJ+DQBkAgAfAAEJCgu6sgAlAAAAAA==.',
Sy='Syb:BAABLgAECn8bAAQVAAkJZxdrGAAMAgAVAAkJlhVrGAAMAgAUAAQJ4hlZEQDnAAAjAAEJFwU3SwArAAAAAA==.Sylphrena:BAACLgAFFH8OAAIIAAUJvRtbFAAuAQAIAAUJvRtbFAAuAQAuAAQKfykAAggACQnSIh8GAOwCAAgACQnSIh8GAOwCAAAA.Syssana:BAAALgAECgIJBgAAAA==.',
Ta='Tadaa:BAAALgADCgIJAgAAAA==.Tamerlein:BAAALgAECgMJBQAAAA==.Tamioka:BAAALgAECgYJCAAAAA==.Tanookii:BAAALgAECgYJEwAAAA==.',
Te='Telafar:BAAALgAECgkJAwAAAA==.',
Th='Theinsider:BAABLgAECn9EAAMHAAkJAyIGDQDfAgAHAAkJAyIGDQDfAgANAAUJkA+nKwARAQAAAA==.Thenezath:BAAALgAECgUJBQAAAA==.Theoutsider:BAAALgAECgYJCAABLgAECgkJRAAHAAMiAA==.Thunrus:BAAALgADCgYJBgAAAA==.',
Ti='Tibbles:BAAALgAECgcJCAAAAA==.Tigerbait:BAAALgAECgYJEQAAAA==.Tindril:BAAALgAECgYJBwAAAA==.Tinymo:BAAALgAECgMJAwAAAA==.',
To='Toji:BAABLgAECn8WAAIIAAcJ+hgqIAC8AQAIAAcJ+hgqIAC8AQABLgAFFAYJKAATAEcfAA==.Tomatoteng:BAACLgAFFH8OAAIGAAYJ3xUtHACAAQAGAAYJ3xUtHACAAQAuAAQKfyAAAgYACQmPJH4DAJsDAAYACQmPJH4DAJsDAAAA.Totegoat:BAAALgADCgEJAQAAAA==.Totemmalotes:BAAALgADCgcJBwAAAA==.Totemofbear:BAABLgAECn8iAAIkAAkJAhU6CgANAgAkAAkJAhU6CgANAgAAAA==.',
Tr='Trandis:BAAALgADCgMJBAABLgAECgkJKAAJANcmAA==.Tranza:BAABLgAECn8cAAQgAAgJOw3wIQCJAQAgAAgJcgrwIQCJAQAbAAYJXwvhfgDrAAAXAAYJzAZBWADlAAAAAA==.Treesus:BAAALgADCgcJBwABLgAECgkJKAACALwiAA==.Trinshunter:BAABLgAECn82AAQbAAkJCxriHwBdAgAbAAkJCxriHwBdAgAgAAEJ6gnELwA0AAAXAAEJ4gEnmgAZAAABLgAFFAYJFAAGAEgMAA==.',
Tx='Tx:BAACLgAFFH8oAAITAAYJRx9BEACMAQATAAYJRx9BEACMAQAuAAQKfywAAhMACAmNIUcQAKcCABMACAmNIUcQAKcCAAAA.',
Ty='Tyedye:BAAALgAECgEJAQAAAA==.',
['Tí']='Tíbs:BAAALgAECgYJCwAAAA==.',
Un='Unbound:BAAALgADCgcJEgAAAA==.Unclegoon:BAAALgAECgEJAQAAAA==.Unholygirl:BAAALgAECgEJAQAAAA==.',
Ut='Utterchaos:BAAALgAECgUJDwAAAA==.',
Va='Vandrina:BAAALgAFFAIJAgAAAA==.Vanthion:BAAALgAECgYJCQAAAA==.Vaporeon:BAAALgAECgEJAQAAAA==.',
Vi='Victreebel:BAAALgAECgcJEQAAAA==.',
Vo='Volg:BAAALgAECgQJBAAAAA==.',
We='Wekko:BAAALgADCgUJBQAAAA==.Wendys:BAABLgAECn8oAAIEAAkJ6xbMUgA/AgAEAAkJ6xbMUgA/AgAAAA==.Wetheals:BAAALgAECgMJBgAAAA==.',
Wh='Whitemonster:BAAALgADCggJDQAAAA==.',
Wi='Wickedhunter:BAAALgADCgYJBgAAAA==.Wimpykid:BAAALgADCggJCAAAAA==.Winar:BAABLgAECn8hAAIEAAgJAhAuewB7AQAEAAgJAhAuewB7AQAAAA==.',
Wo='Worgnfreeman:BAABLgAECn8VAAMQAAcJ0gk6qAAWAQAQAAcJ+wg6qAAWAQAOAAcJIQZDHgDIAAAAAA==.',
Wr='Wraithsdaddy:BAAALgADCgEJAQAAAA==.',
Wt='Wtfdrood:BAAALgAECgQJCQABLgAFFAMJBwAfADMMAA==.Wtfmate:BAAALgADCgYJCQABLgAFFAMJBwAfADMMAA==.Wtfmonk:BAACLgAFFH8HAAIfAAMJMwxLOQCdAAAfAAMJMwxLOQCdAAAuAAQKfygAAh8ACQn+HJILAM8CAB8ACQn+HJILAM8CAAAA.',
Xa='Xaioli:BAABLgAECn8gAAMHAAkJaSV0CAA9AwAHAAkJaSV0CAA9AwANAAIJwyF/RQCgAAAAAA==.',
Xe='Xemu:BAAALgADCgUJBQAAAA==.Xethani:BAABLgAECn8bAAIcAAkJbhF5CQDEAQAcAAkJbhF5CQDEAQAAAA==.',
Xo='Xorcopressor:BAAALgAECgIJAgAAAA==.',
Xs='Xsaber:BAAALgAECgQJBgAAAA==.',
Ya='Yazmo:BAACLgAFFH8PAAIIAAUJMCSYCwCLAQAIAAUJMCSYCwCLAQAuAAQKfzcAAggACAmwI/sKAJkCAAgACAmwI/sKAJkCAAEuAAUUAwkEAA8AAAAA.',
Yu='Yuuky:BAACLgAFFH8VAAIKAAUJuhJUHgBXAQAKAAUJuhJUHgBXAQAuAAQKfzMAAwoACQl2G6AVAJECAAoACQl2G6AVAJECACUABwkjCeYzAMQAAAAA.',
Za='Zalmo:BAAALgAECgEJAQABLgAECgkJHwAUAJkUAA==.Zarivia:BAAALgADCgMJAwAAAA==.Zartaz:BAABLgAECn8aAAMjAAgJtQyXHAChAQAjAAgJtQyXHAChAQAUAAEJWgdNKAAmAAAAAA==.',
Zb='Zbonez:BAAALgAECgcJDgAAAA==.',
Ze='Zendrov:BAABLgAECn8iAAIVAAgJqwUGUwDXAAAVAAgJqwUGUwDXAAAAAA==.Zenpai:BAAALgAECgEJBgAAAA==.',
Zi='Ziillah:BAAALgAECgIJAgAAAA==.Zinogre:BAABLgAECn8zAAIFAAkJqRUpCgALAgAFAAkJqRUpCgALAgAAAA==.',
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
