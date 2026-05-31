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

local lookup = {'Warrior-Protection','Warrior-Fury','Mage-Frost','Shaman-Enhancement','Paladin-Retribution','Warlock-Demonology','Priest-Shadow','Shaman-Restoration','DemonHunter-Devourer','Druid-Restoration','Priest-Holy','Warrior-Arms','Warlock-Destruction','DeathKnight-Frost','Unknown-Unknown','DeathKnight-Unholy','Paladin-Holy','Druid-Balance','Shaman-Elemental','Evoker-Devastation','Evoker-Augmentation','Monk-Windwalker','Hunter-Marksmanship','Paladin-Protection','Priest-Discipline','Hunter-BeastMastery','DemonHunter-Vengeance','DemonHunter-Havoc','Warlock-Affliction','Monk-Brewmaster','Monk-Mistweaver','DeathKnight-Blood','Rogue-Subtlety','Evoker-Preservation','Druid-Feral','Hunter-Survival','Druid-Guardian',}
local provider = {region='US',realm='Archimonde',name='US',type='weekly',zone=46,date='2026-05-30',data={Aa='Aanaleaa:BAAALgAECgcJEAAAAA==.',
Ab='Abelram:BAAALgADCgUJBQAAAA==.',
Ad='Ad:BAABLgAECn8pAAMBAAkJSyHmAgABAwABAAkJSyHmAgABAwACAAUJ+QprXgDAAAABLgAECgYJGQADAMoVAA==.Adellon:BAABLgAFFH8JAAIEAAMJ6RfFCQD1AAAEAAMJ6RfFCQD1AAAAAA==.Adhar:BAAALgAECgEJAgAAAA==.Adrielle:BAABLgAECn8gAAIFAAYJYBtDlQAuAQAFAAYJYBtDlQAuAQAAAA==.',
Ae='Aeiox:BAAALgADCgMJAwAAAA==.Aevelman:BAABLgAECn8zAAIGAAkJFB0CEQC3AgAGAAkJFB0CEQC3AgAAAA==.',
Af='Affinty:BAAALgAECgQJBAABLgAFFAcJFgAHAHkbAA==.',
Ag='Ag:BAAALgAECgQJBQAAAA==.',
Ai='Airphobic:BAABLgAECn8UAAIIAAUJPBuCRQB8AQAIAAUJPBuCRQB8AQAAAA==.',
Ak='Akakage:BAAALgAECgEJAQABLgAECggJGQAJACoXAA==.Akakaji:BAABLgAECn8ZAAIJAAgJKhfHNgDUAQAJAAgJKhfHNgDUAQAAAA==.Akutoku:BAAALgADCgcJDAAAAA==.',
Al='Aland:BAAALgADCggJEgAAAA==.Alea:BAABLgAECn8cAAIKAAgJMxxsFACSAgAKAAgJMxxsFACSAgAAAA==.Almodiir:BAAALgADCgUJCQAAAA==.Almoraz:BAAALgAECgUJBQAAAA==.',
An='Anachron:BAAALgADCgIJAgAAAA==.Anaki:BAAALgADCgcJDwAAAA==.Annakkin:BAAALgAECgQJBQAAAA==.Anomander:BAABLgAECn8gAAIJAAYJWAwfmQDQAAAJAAYJWAwfmQDQAAAAAA==.Anonymoose:BAAALgADCgQJBAAAAA==.',
Ao='Aol:BAAALgADCgUJBQAAAA==.',
Ar='Ar:BAABLgAECn8VAAILAAcJfBCfLQBIAQALAAcJfBCfLQBIAQABLgAECgYJGQADAMoVAA==.Arbiter:BAAALgAECgUJCQAAAA==.Archon:BAACLgAFFH8FAAMMAAMJOxrBJQCdAAAMAAIJhBnBJQCdAAACAAEJqRtiQgBTAAAuAAQKfx4AAwIACAkwHmoUADoCAAIACAkwHmoUADoCAAwABAnJFT07AL0AAAAA.Argig:BAAALgADCgcJCAAAAA==.Arienca:BAABLgAECn85AAMNAAkJchBHFgCYAQAGAAkJaAuUUgCYAQANAAgJnhBHFgCYAQAAAA==.Arwenn:BAAALgAECgEJAQAAAA==.',
As='Aspir:BAEALgAECggJCAABLgAFFAYJFwAOAMEZAA==.Asu:BAABLgAECn8ZAAIKAAYJmg/OVwAfAQAKAAYJmg/OVwAfAQAAAA==.',
At='At:BAABLgAECn8ZAAIDAAYJyhUTqACJAQADAAYJyhUTqACJAQAAAA==.',
Au='Aubrey:BAACLgAFFH8NAAIKAAYJpQVPIwAlAQAKAAYJpQVPIwAlAQAuAAQKfxQAAgoACQlyCqVSAFwBAAoACQlyCqVSAFwBAAAA.',
Av='Avengion:BAAALgAECgcJEAAAAA==.',
Ba='Balthromaw:BAAALgADCggJDQAAAA==.Barbato:BAAALgADCgYJCQAAAA==.Barbie:BAAALgADCgYJBgAAAA==.',
Be='Beararms:BAAALgADCgcJCAAAAA==.Beav:BAAALgAECgYJBwABLgAFFAYJFQAKAOoaAA==.Beldent:BAAALgAECgQJBwAAAA==.',
Bl='Blazegrave:BAAALgAECgUJCAABLgAECgkJMQADAJsRAA==.Blazeofglory:BAAALgADCgUJBQABLgAECgYJCQAPAAAAAA==.Blazerunner:BAABLgAECn8xAAIDAAkJmxHPSADpAQADAAkJmxHPSADpAQAAAA==.Blazesmasher:BAAALgAECgkJCQABLgAECgkJMQADAJsRAA==.Blitzkreig:BAABLgAECn8UAAIQAAcJSRgDXQCdAQAQAAcJSRgDXQCdAQAAAA==.Bluefoot:BAABLgAECn8fAAIIAAYJ/AhLcADrAAAIAAYJ/AhLcADrAAAAAA==.Blured:BAABLgAECn88AAIJAAkJOSTiBAArAwAJAAkJOSTiBAArAwAAAA==.',
Bo='Booty:BAABLgAECn8oAAIBAAkJvCKMBQDhAgABAAkJvCKMBQDhAgAAAA==.',
Br='Brightblayde:BAABLgAECn8ZAAIFAAgJNQ9yegBeAQAFAAgJNQ9yegBeAQAAAA==.Brynhildre:BAABLgAECn8UAAIRAAcJfgtURABmAQARAAcJfgtURABmAQABLgAFFAYJDQAKAKUFAA==.',
Bu='Buum:BAAALgAECgcJEAAAAA==.',
By='Byane:BAAALgADCgYJBgAAAA==.',
['Bä']='Bämba:BAAALgAECgMJAwABLgAECggJHgADAOgLAA==.',
Ca='Cachelyn:BAAALgAECgYJBwAAAA==.Cali:BAACLgAFFH8hAAIJAAgJABz7BgBfAgAJAAgJABz7BgBfAgAuAAQKfywAAgkACAmkIeQSAOgCAAkACAmkIeQSAOgCAAAA.Cantouchthes:BAABLgAECn8UAAIDAAgJZB77PgAJAgADAAgJZB77PgAJAgAAAA==.Captnage:BAAALgADCggJCAAAAA==.',
Ce='Cederred:BAAALgAECgUJBQABLgAECggJCgAPAAAAAA==.Cedertree:BAAALgADCgcJBwABLgAECggJCgAPAAAAAA==.Celline:BAAALgADCgEJAQAAAA==.Cephus:BAABLgAFFH8NAAIKAAYJjBaOEADEAQAKAAYJjBaOEADEAQAAAA==.Cerafina:BAAALgADCgEJAQAAAA==.',
Ch='Chayse:BAAALgAFFAEJAQABLgAFFAYJDQAKAKUFAA==.Choom:BAABLgAECn8fAAMKAAkJuhUONgDQAQAKAAkJuhUONgDQAQASAAYJjRPrLgCOAQAAAA==.Chorizo:BAAALgADCgEJAQAAAA==.Christhina:BAAALgADCgQJBAAAAA==.Chronocide:BAACLgAFFH8HAAITAAMJxRs+IwD1AAATAAMJxRs+IwD1AAAuAAQKfyoAAhMACQnbHxEQAKkCABMACQnbHxEQAKkCAAAA.Chronophasia:BAAALgAECggJEAAAAA==.Chroños:BAABLgAECn8UAAMUAAcJEA8fEgDVAAAVAAcJ6g2qQAAGAQAUAAQJZw4fEgDVAAAAAA==.Chumléé:BAAALgADCgQJBAAAAA==.Chérry:BAACLgAFFH8aAAIJAAYJJhvuHACTAQAJAAYJJhvuHACTAQAuAAQKfx8AAgkACQlsIowQAPoCAAkACQlsIowQAPoCAAAA.',
Cl='Climpwimp:BAAALgAECgEJAQAAAA==.Cluntasaur:BAAALgAECgUJBgAAAA==.',
Co='Connerr:BAABLgAECn8aAAIKAAgJtBogLADmAQAKAAgJtBogLADmAQAAAA==.Cowage:BAAALgAECgQJCQAAAA==.',
Cr='Crisse:BAAALgAECgUJCgAAAA==.Croh:BAABLgAECn8aAAMQAAgJpBNfVAD0AQAQAAgJpBNfVAD0AQAOAAQJawb3DwCcAAAAAA==.Crucks:BAAALgADCgQJBAAAAA==.Cruknar:BAAALgAFFAMJBAAAAA==.',
Cu='Curita:BAAALgADCgEJAQAAAA==.',
Cy='Cynestra:BAAALgAECgcJEAAAAA==.',
Da='Dadudadu:BAACLgAFFH8XAAIFAAcJLg74GQB6AQAFAAcJLg74GQB6AQAuAAQKfzQAAgUACQkZIHoWAOICAAUACQkZIHoWAOICAAAA.Daffo:BAAALgAECgIJAQAAAA==.Daftmonk:BAACLgAFFH8fAAIWAAYJVyUMAgAWAgAWAAYJVyUMAgAWAgAuAAQKfywAAhYACQmSJbECAG8DABYACQmSJbECAG8DAAAA.Daitanfuteki:BAAALgADCgEJAQABLgAFFAQJCAAXAOcVAA==.Dalan:BAAALgAECgEJAQAAAA==.Darkfyre:BAAALgADCgEJAgAAAA==.Darks:BAAALgAECgIJAgAAAA==.Darkwingfish:BAABLgAECn8pAAIJAAkJrRRLPwC0AQAJAAkJrRRLPwC0AQAAAA==.Dartran:BAAALgADCgIJBwAAAA==.Dasarus:BAAALgAECgYJEgAAAA==.Dayman:BAABLgAECn8UAAMYAAcJgwKzLgCUAAAYAAcJXAKzLgCUAAAFAAYJ0gE9LQFgAAAAAA==.',
De='Deadmedic:BAAALgAECgUJCQABLgAECgcJJAAZAKcRAA==.Decày:BAAALgAECgcJEAAAAA==.Demoteck:BAAALgAECgQJBgAAAA==.Deredris:BAAALgAECgEJAQAAAA==.Deth:BAAALgAECgIJAgABLgAECgMJDAAPAAAAAA==.Dethblow:BAAALgAECgMJDAAAAA==.',
Di='Disconnects:BAAALgADCgUJBQAAAA==.Dium:BAAALgAECgEJAQAAAA==.Diwa:BAACLgAFFH8FAAIIAAUJ5QEOMAD/AAAIAAUJ5QEOMAD/AAAuAAQKfxkAAwgACQn8Bo5hABkBAAgACQn8Bo5hABkBABMABglJB+BRAP8AAAAA.',
Dk='Dklot:BAACLgAFFH8FAAIQAAMJWghLlwC/AAAQAAMJWghLlwC/AAAuAAQKfxgAAxAABwlZHLtsAHcBABAABwlZHLtsAHcBAA4AAQn1DN81ACQAAAAA.',
Dr='Dragolot:BAAALgADCgQJBAABLgAFFAMJBQAQAFoIAA==.Draken:BAAALgAECgEJAQAAAA==.Draviin:BAABLgAECn8wAAIaAAkJ9x34GgBuAgAaAAkJ9x34GgBuAgAAAA==.',
Du='Duckcheese:BAAALgADCgEJAQAAAA==.Dunkyn:BAAALgAECgMJBgAAAA==.Durzoblint:BAAALgAECgUJCAAAAA==.',
Dy='Dyemon:BAAALgADCgIJAgAAAA==.',
['Dé']='Déad:BAAALgADCgcJDAAAAA==.',
El='Elementz:BAAALgAECgIJAgAAAA==.Elerae:BAABLgAECn8nAAIFAAkJ+hthFgDjAgAFAAkJ+hthFgDjAgAAAA==.Eleshkigal:BAABLgAECn8oAAMJAAkJ1yaKAwCTAwAJAAkJ1yaKAwCTAwAbAAQJiBo2EAAuAQAAAA==.',
En='Enkeke:BAABLgAECn85AAIQAAkJTR3CIwBiAgAQAAkJTR3CIwBiAgAAAA==.',
Er='Eresanna:BAABLgAFFH8JAAIDAAQJnwm1WwAbAQADAAQJnwm1WwAbAQAAAA==.Ereshkigal:BAAALgAECgUJBgAAAA==.',
Es='Esdeath:BAAALgAECgQJCAABLgAFFAYJCgAcAOMQAA==.Estus:BAABLgAECn8VAAMRAAgJNhefJgC/AQARAAgJNhefJgC/AQAFAAIJ1gkPWgE9AAAAAA==.',
Ex='Extremefear:BAABLgAECn8vAAMNAAkJFhZgEgAJAQAGAAUJTRNRcwBIAQANAAYJ8RVgEgAJAQAAAA==.',
Fa='Fatima:BAAALgAECgIJAwAAAA==.',
Fe='Fearious:BAACLgAFFH8TAAMGAAUJVSVKIQCPAQAGAAUJxiRKIQCPAQAdAAEJYSYtEABoAAAuAAQKfyYABAYACAlBJpgqACICAAYABwk3JJgqACICAA0AAwl7JRYWAN0AAB0AAQncI/8lAGsAAAAA.Felphetamine:BAAALgADCggJCAAAAA==.Fenrisfangs:BAABLgAECn8VAAIaAAkJSA46SACxAQAaAAkJSA46SACxAQAAAA==.Fenrisul:BAAALgAECgUJBQAAAA==.Feralshunter:BAACLgAFFH8IAAIXAAQJ5xUmEgAQAQAXAAQJ5xUmEgAQAQAuAAQKfzIAAhcACQkAIZcQALcCABcACQkAIZcQALcCAAAA.Feroond:BAAALgADCgQJBAAAAA==.',
Fi='Fingeritout:BAAALgADCgIJAgAAAA==.Firefly:BAAALgAECgMJAwAAAA==.',
Fl='Florea:BAAALgADCggJDAAAAA==.',
Fo='Forfoxsake:BAABLgAECn8kAAIeAAgJmR/3DwAtAgAeAAgJmR/3DwAtAgAAAA==.',
Fr='Frogteeth:BAAALgADCgUJBQAAAA==.',
Fu='Furibeav:BAABLgAFFH8VAAIKAAYJ6hoADQD1AQAKAAYJ6hoADQD1AQAAAA==.Furrów:BAAALgAECgEJAQAAAA==.',
['Fû']='Fûrrow:BAAALgAECgYJDAAAAA==.',
Ga='Gallindral:BAABLgAECn88AAIJAAkJah1nEgCbAgAJAAkJah1nEgCbAgAAAA==.Garanda:BAAALgAECgQJBQAAAA==.Gatito:BAAALgAECgEJAQABLgAECgIJAgAPAAAAAA==.Gauthus:BAAALgAECgkJCQAAAA==.',
Ge='Genericnpc:BAABLgAECn8VAAQMAAcJTgvKPAC3AAACAAYJaAlHWgDOAAAMAAYJtAjKPAC3AAABAAEJihNuSQA5AAAAAA==.Geobrando:BAABLgAECn84AAMIAAkJTiBtCwDHAgAIAAkJTiBtCwDHAgATAAYJmQ9zXQCwAAAAAA==.',
Gg='Ggbrews:BAACLgAFFH8fAAIFAAYJsyKHCQDzAQAFAAYJsyKHCQDzAQAuAAQKf5EABAUACQlUJlYCAGYDAAUACQlUJlYCAGYDABEACAkgG5wSAGcCABgABwm5CJ8kANQAAAAA.',
Gh='Ghostblaze:BAAALgAECgUJDAABLgAECgkJMQADAJsRAA==.',
Gi='Gier:BAAALgADCgUJBQAAAA==.Gino:BAAALgADCgEJAQAAAA==.',
Gl='Glacious:BAAALgADCgEJAQAAAA==.Glasswings:BAAALgAECgIJAgAAAA==.',
Gn='Gnosh:BAAALgAECgcJEwAAAA==.Gnova:BAABLgAECn8jAAIDAAYJfSGRWQC4AQADAAYJfSGRWQC4AQAAAA==.',
Go='Gorian:BAAALgAECgcJCAAAAA==.',
Gr='Gregorz:BAAALgADCgEJAQAAAA==.Grish:BAAALgAECgEJAQAAAA==.',
Gu='Guidosarduci:BAABLgAECn8iAAIIAAgJhhdgHAA2AgAIAAgJhhdgHAA2AgAAAA==.',
Ha='Hairia:BAAALgADCgUJBQAAAA==.Halen:BAAALgADCgcJBwABLgAFFAgJIQAJAAAcAA==.Hardone:BAAALgAECgUJBQAAAA==.Harle:BAABLgAECn8UAAIDAAcJGhO7dAB1AQADAAcJGhO7dAB1AQAAAA==.Hatari:BAAALgAECgMJAwAAAA==.',
He='Hektate:BAABLgAECn8WAAIDAAcJXQu4pwATAQADAAcJXQu4pwATAQABLgAFFAcJFwAFAC4OAA==.Henryjones:BAAALgADCgEJAQAAAA==.',
Hi='Hikari:BAABLgAECn8WAAIFAAgJZiE7JABbAgAFAAgJZiE7JABbAgABLgAFFAYJKAATAEcfAA==.Hilkesad:BAAALgAECgQJBAAAAA==.Hizo:BAAALgADCgUJBQAAAA==.',
Ho='Holybeave:BAABLgAECn8eAAMLAAkJNB3/DACFAgAZAAkJaBi5CQCfAgALAAgJqx7/DACFAgABLgAFFAYJFQAKAOoaAA==.Holyshortguy:BAAALgAECgYJCgABLgAFFAMJBgAfAIoLAA==.Hoofer:BAAALgAECgYJDgAAAA==.',
Hu='Hunkomeat:BAABLgAECn8XAAICAAgJLhzkLAAAAgACAAgJLhzkLAAAAgAAAA==.',
['Hë']='Hënry:BAAALgAECgEJAQAAAA==.',
Ic='Icelmo:BAABLgAFFH8MAAICAAQJYxWuGQA2AQACAAQJYxWuGQA2AQAAAA==.',
Ih='Ihotyou:BAAALgADCgQJBwAAAA==.',
Il='Ilikeitrough:BAAALgADCgMJAwAAAA==.',
In='Inai:BAAALgADCgcJDAABLgAFFAYJCgAcAOMQAA==.Invizww:BAAALgAECgQJBQAAAA==.',
Ir='Ircapslock:BAAALgAECgYJCwAAAA==.',
Iv='Ivorypal:BAABLgAECn8gAAIRAAgJqR/dEACLAgARAAgJqR/dEACLAgAAAA==.',
Ja='Jacksock:BAAALgADCgEJAQAAAA==.Jamzz:BAAALgADCgYJFgABLgAFFAYJFgAXAL0RAA==.Jaromir:BAAALgADCgcJBwAAAA==.Jaskow:BAABLgAECn8uAAIKAAkJjiAEBwA6AwAKAAkJjiAEBwA6AwAAAA==.Jaymick:BAAALgAECgcJEwAAAA==.',
Jb='Jbizzler:BAAALgAECgcJBgAAAA==.',
Jc='Jcrypt:BAAALgAECgcJAgAAAA==.',
Je='Jennika:BAAALgAFFAIJAwAAAA==.Jernau:BAAALgAECgEJAQAAAA==.Jessortess:BAAALgAECgQJBwAAAA==.',
Jo='Johnwicksdog:BAAALgAECggJEQAAAA==.Jorbies:BAAALgAECgYJCQABLgAFFAcJFgAHAHkbAA==.Jorls:BAACLgAFFH8WAAMHAAcJeRtMAgDeAQAHAAcJeRtMAgDeAQAZAAEJWAEnGwBDAAAuAAQKfxsABAcACQkFHlMIAP8CAAcACQkFHlMIAP8CABkABAnSCc08AMQAAAsAAglAAgl2AFEAAAAA.',
Ju='Junatooka:BAAALgAECgIJAgAAAA==.Jusdatip:BAAALgAECgUJDQAAAA==.',
Ka='Kaelthazed:BAAALgADCgEJAQABLgAECgkJRAAGAAMiAA==.Kalfu:BAABLgAECn8XAAMaAAgJ0B0wMwD5AQAaAAgJ0B0wMwD5AQAXAAYJoBUDOgB5AQAAAA==.Kameshoga:BAAALgAECgIJAgAAAA==.Kammwin:BAAALgAECgYJEwAAAA==.Karten:BAAALgAECgQJBwAAAA==.Kaylea:BAAALgADCgIJAgAAAA==.',
Ke='Kellandria:BAAALgADCgcJEgAAAA==.',
Ki='Kieraleah:BAAALgAECgcJBwAAAA==.Kittêh:BAAALgAECgEJAQAAAA==.',
Kn='Knathor:BAAALgAECgQJBQABLgAECgcJDgAPAAAAAA==.',
Ko='Korec:BAAALgAECgcJDgAAAA==.',
Kr='Krasis:BAABLgAECn8XAAIFAAkJvhrLWADYAQAFAAkJvhrLWADYAQAAAA==.Krazermonk:BAACLgAFFH8LAAIWAAMJQBxNFgD+AAAWAAMJQBxNFgD+AAAuAAQKfygAAhYACQmlHrYMAGUCABYACQmlHrYMAGUCAAAA.Krispinwah:BAAALgAECgkJEAABLgAECgkJOAAIAE4gAA==.Kristysavage:BAABLgAECn8qAAIaAAkJYiPeBQAlAwAaAAkJYiPeBQAlAwAAAA==.Kroflavinof:BAAALgAECgUJBgAAAA==.',
Ku='Kurosakí:BAAALgAECgEJAQAAAA==.',
La='Lanc:BAAALgAECgQJCQAAAA==.Lappytopdog:BAAALgAECgEJAQAAAA==.Larradin:BAAALgADCggJEAAAAA==.Lawnchair:BAAALgAECggJCQAAAA==.',
Le='Lealta:BAAALgAFFAEJAQAAAA==.Leonus:BAAALgAECgQJCQAAAA==.Leviathahn:BAAALgAECgEJAgAAAA==.',
Lh='Lhegholhaz:BAAALgADCgIJAgAAAA==.',
Li='Lichdawg:BAACLgAFFH8WAAMOAAYJChFfBAB+AQAOAAUJChFfBAB+AQAgAAEJAABcTwAAAAAuAAQKfxQAAg4ACAnSEzMMAIUBAA4ACAnSEzMMAIUBAAAA.Lilzayna:BAAALgAECgEJAQABLgAECgUJBgAPAAAAAA==.Linthori:BAEALgADCgMJAwABLgAECgcJDQAPAAAAAA==.Lithlia:BAAALgADCgcJBwAAAA==.Livvela:BAABLgAECn8kAAIhAAkJsRXiEwDsAQAhAAkJsRXiEwDsAQAAAA==.',
Ll='Llas:BAAALgADCgIJAgAAAA==.',
Lo='Lockdawg:BAACLgAFFH8XAAIGAAYJ7hCCKgBvAQAGAAYJ7hCCKgBvAQAuAAQKfyYAAwYACAmFHRImAHoCAAYACAmFHRImAHoCAA0AAQnWFc1sADoAAAAA.Lockedin:BAAALgAECgkJEgAAAA==.Lonne:BAAALgAECgYJDgABLgAFFAIJBAAPAAAAAA==.Lover:BAABLgAECn8jAAILAAkJNR6/CgCkAgALAAkJNR6/CgCkAgAAAA==.',
Lu='Lubu:BAACLgAFFH8KAAIcAAYJ4xAkBgB3AQAcAAYJ4xAkBgB3AQAuAAQKfxoAAhwACQn+HxEEAPYCABwACQn+HxEEAPYCAAAA.Lucianis:BAAALgADCgQJBwAAAA==.Luckycharmz:BAAALgAECgQJCQABLgAECgcJJAAZAKcRAA==.Luckywar:BAAALgADCgYJBgAAAA==.Luell:BAAALgAECgcJDwAAAA==.Luev:BAAALgAECgYJCAAAAA==.Lumiette:BAAALgAECgcJCwAAAA==.',
Ly='Lynai:BAAALgAECgYJEgAAAA==.',
['Lá']='Lándwhale:BAACLgAFFH8UAAIhAAQJxSOuDQB9AQAhAAQJxSOuDQB9AQAuAAQKfy4AAiEACQmTJGoDAAEDACEACQmTJGoDAAEDAAAA.',
['Lö']='Löver:BAAALgAECgcJBwAAAA==.',
Ma='Mabil:BAABLgAECn8UAAQGAAcJRhIRjwATAQAGAAYJew0RjwATAQAdAAQJXRWcGAC2AAANAAIJNAx8OwArAAAAAA==.Macktimus:BAABLgAECn8fAAINAAkJGBhYBAAkAgANAAkJGBhYBAAkAgAAAA==.Mage:BAAALgAFFAEJAgAAAA==.Magictonyp:BAAALgAECgQJBgAAAA==.Magicznstuff:BAAALgAECgEJAQABLgAECgMJBgAPAAAAAA==.Magna:BAABLgAECn8lAAICAAkJYRLlIwDAAQACAAkJYRLlIwDAAQAAAA==.Magnusbane:BAAALgADCgMJAwAAAA==.Makili:BAABLgAFFH8LAAIDAAQJKQ7OUgAsAQADAAQJKQ7OUgAsAQAAAA==.Maladrix:BAAALgAECgQJDQAAAA==.Mauê:BAAALgADCgEJAQABLgAECgIJAgAPAAAAAA==.',
Mc='Mchealer:BAAALgADCgUJBQAAAA==.Mchunter:BAAALgAECgMJAwAAAA==.Mcshadow:BAAALgADCgIJAgAAAA==.',
Me='Menphina:BAAALgAECgIJAgAAAA==.Merigold:BAAALgAECgEJAQABLgAECgQJBAAPAAAAAA==.',
Mi='Minnow:BAAALgAECgYJDgAAAA==.Mintchip:BAABLgAECn8QAAIJAAcJ3Rd3RACjAQAJAAcJ3Rd3RACjAQAAAA==.',
Mo='Monk:BAAALgAECgEJAQAAAA==.Monza:BAAALgADCgEJAQABLgAECgkJKAADAOsWAA==.Moontini:BAAALgADCgYJBgABLgAECgQJDQAPAAAAAA==.Mordryn:BAAALgADCgcJBwAAAA==.',
My='Mysternia:BAAALgAECgYJDgAAAA==.Myyagie:BAAALgADCgcJEQAAAA==.',
Na='Nalthexon:BAABLgAECn8qAAMfAAgJ2wtFMQAzAQAfAAgJ2wtFMQAzAQAWAAEJXQZnnAAoAAABLgAFFAMJBgAKAHUGAA==.Natureborne:BAAALgAECgYJCQAAAA==.',
Ne='Nedrud:BAAALgADCgUJCAAAAA==.Nelson:BAEALgAECgYJBgAAAA==.Nenno:BAAALgADCgEJAQAAAA==.Netzhul:BAAALgAFFAEJAQAAAA==.',
Ni='Night:BAAALgAECgcJEQAAAA==.Nikalos:BAAALgAECgYJDQAAAA==.Nikole:BAAALgAECgMJAwAAAA==.',
No='Noon:BAAALgADCgUJBQABLgAECggJFQARADYXAA==.Notorckrag:BAABLgAECn84AAIeAAkJEyNeAwAOAwAeAAkJEyNeAwAOAwAAAA==.Nozomi:BAAALgAECgUJBwAAAA==.',
Nu='Nut:BAAALgADCgQJBAAAAA==.',
['Nê']='Nêz:BAAALgAECgUJCAAAAA==.',
Oa='Oathbringer:BAAALgAECgQJBAAAAA==.',
Ob='Oblivionz:BAAALgAECgMJAwAAAA==.',
Oc='Ocho:BAAALgADCgYJCQAAAA==.',
Of='Offbrandcleo:BAAALgAECgkJBgAAAA==.',
Ok='Okibi:BAAALgAECgMJBQABLgAFFAYJCgAcAOMQAA==.',
Ol='Oldrecipe:BAABLgAFFH8IAAIRAAMJARRNKgC+AAARAAMJARRNKgC+AAAAAA==.Oliange:BAABLgAECn8eAAIDAAgJ6As8iABMAQADAAgJ6As8iABMAQAAAA==.',
Or='Ori:BAEALgADCgcJCwABLgAECgcJDQAPAAAAAA==.Originalgank:BAABLgAECn8WAAIDAAgJUyOCFADJAgADAAgJUyOCFADJAgAAAA==.',
Pa='Papanell:BAAALgADCgYJCQAAAA==.',
Pe='Peachcobbler:BAAALgAECggJDgAAAA==.Perc:BAAALgAECgcJCwAAAA==.',
Ph='Philsner:BAEALgAECgcJDQAAAA==.Phink:BAAALgAECgQJCgAAAA==.',
Pi='Pinkk:BAABLgAECn8WAAIaAAkJAR2eFACXAgAaAAkJAR2eFACXAgAAAA==.',
Pl='Plushie:BAABLgAECn8hAAIHAAgJ7glSLgBHAQAHAAgJ7glSLgBHAQAAAA==.',
Po='Pong:BAAALgAFFAEJAQAAAA==.Pooqy:BAACLgAFFH8QAAMQAAUJ4SRpJACaAQAQAAQJ4SRpJACaAQAgAAEJAAA0PAAAAAAuAAQKfxYAAhAACAlWIrskAKsCABAACAlWIrskAKsCAAAA.Porcel:BAAALgADCgcJCwAAAA==.Potatoteng:BAAALgAFFAEJAgABLgAFFAYJDgAFAN8VAA==.',
Pr='Pritej:BAAALgAECgYJCgABLgAFFAIJBAAPAAAAAA==.Proto:BAAALgAECgcJDAAAAA==.',
Pu='Puck:BAAALgAECgIJCAABLgAFFAYJCgAcAOMQAA==.',
Py='Pyraleus:BAAALgADCgQJBAAAAA==.',
Qu='Quickchicken:BAAALgAECgEJAQAAAA==.',
Ra='Ragel:BAABLgAECn8wAAISAAkJ8x9SBgDiAgASAAkJ8x9SBgDiAgAAAA==.Rainesage:BAABLgAECn8rAAMHAAkJgxp+DgBUAgAHAAkJgxp+DgBUAgALAAEJxwfSbAAnAAAAAA==.Ralphel:BAABLgAECn8kAAIFAAcJ4wYnvQDvAAAFAAcJ4wYnvQDvAAAAAA==.Rasu:BAAALgADCgcJBwABLgAECggJGgAiALUMAA==.Ravendark:BAAALgAECgEJAQAAAA==.Rayozap:BAAALgAECgUJBgAAAA==.',
Re='Redeye:BAAALgADCgMJAwAAAA==.Relock:BAAALgAECgMJAwABLgAECggJGgAKALQaAA==.',
Rh='Rhondaa:BAAALgAECgYJEQAAAA==.Rhubarb:BAABLgAECn8/AAMMAAkJjibZAABlAwAMAAgJIibZAABlAwACAAgJoyQTCwChAgAAAA==.',
Ri='Riyci:BAAALgAECgEJAQAAAA==.',
Ro='Rohiem:BAABLgAECn81AAICAAkJpBjvFQArAgACAAkJpBjvFQArAgAAAA==.',
Ry='Ryan:BAABLgAECn8eAAIFAAkJZR4ZHADBAgAFAAkJZR4ZHADBAgAAAA==.Rylorthas:BAACLgAFFH8dAAILAAYJThasCACTAQALAAYJThasCACTAQAuAAQKfy0AAgsACQl8HMsSAEoCAAsACQl8HMsSAEoCAAAA.Rylosh:BAAALgADCgYJBgABLgAFFAYJHQALAE4WAA==.',
['Rî']='Rîkku:BAAALgADCgUJBQAAAA==.',
Sa='Sabot:BAAALgAECgcJEwAAAA==.Sabrook:BAAALgADCggJCAAAAA==.Salazar:BAAALgAECgEJAwAAAA==.Sam:BAAALgAECgUJBAAAAA==.Satisfied:BAAALgAECgQJEQAAAA==.',
Sc='Scottmonk:BAAALgAECgIJBQAAAA==.Scottpaladin:BAAALgAECgEJAQABLgAECgIJBQAPAAAAAA==.',
Se='Sentaí:BAAALgAECgIJBAAAAA==.',
Sh='Shamerica:BAACLgAFFH8XAAIEAAcJWiCrAAAsAgAEAAcJWiCrAAAsAgAuAAQKfz4AAwQACQkyJDMBACIDAAQACQn2IjMBACIDABMACAnNI1IHANYCAAAA.Shizuku:BAAALgADCgUJBQAAAA==.Shmooythefox:BAABLgAECn8lAAIaAAcJfCF5LQAQAgAaAAcJfCF5LQAQAgAAAA==.Shokan:BAAALgADCgQJBAAAAA==.Shortleedin:BAAALgAECgIJAQAAAA==.Shòckwave:BAAALgADCgQJBAAAAA==.',
Si='Sinrex:BAAALgADCgIJAgAAAA==.Sixstar:BAAALgADCgEJAQAAAA==.',
Sk='Skrt:BAAALgAECgMJAwAAAA==.Skyleax:BAACLgAFFH8KAAMQAAQJdg0tZQAUAQAQAAQJdg0tZQAUAQAOAAEJwAK4IQA1AAAuAAQKfxgABBAACQkSIEYuAH8CABAACQnoHEYuAH8CAA4ABAkVHkUMAPAAACAAAQn7D0ZLACAAAAAA.',
Sl='Slagothor:BAABLgAECn8VAAIQAAkJywRnmQBNAQAQAAkJywRnmQBNAQAAAA==.Slanesh:BAAALgAECgcJCwABLgAECgcJEAAJAN0XAA==.Sleaze:BAAALgADCgEJAQAAAA==.Sleazus:BAAALgAECgMJAwAAAA==.',
Sm='Smeesha:BAABLgAECn8fAAQiAAgJwhUJDwDJAQAiAAcJgxYJDwDJAQAUAAYJRQcGJgDzAAAVAAYJ1wahRgDBAAAAAA==.',
Sn='Snaxwell:BAAALgADCgEJAQAAAA==.',
So='Somin:BAAALgAECgMJBAAAAA==.',
Sp='Specialedz:BAAALgADCgIJAgAAAA==.Spekaleks:BAAALgADCgUJBwAAAA==.',
Sq='Squitwurt:BAAALgADCgYJBgAAAA==.',
St='Starbux:BAAALgAECgMJBAAAAA==.Starbúcks:BAAALgAECgIJAwABLgAECgcJJAAZAKcRAA==.Steppers:BAAALgAECgUJAgAAAA==.Straamm:BAAALgADCgMJAwAAAA==.',
Su='Sugarr:BAAALgADCgMJAwAAAA==.Sunfish:BAAALgAECgYJCgAAAA==.',
Sv='Svelana:BAABLgAECn8lAAMWAAgJjSJ8DABoAgAWAAgJjSJ8DABoAgAfAAEJCgtcowAlAAAAAA==.',
Sy='Syb:BAABLgAECn8UAAMVAAcJQBVgKgB6AQAVAAcJQBVgKgB6AQAiAAEJFwU3SwArAAAAAA==.Sylphrena:BAACLgAFFH8OAAIHAAUJvRs+EQBDAQAHAAUJvRs+EQBDAQAuAAQKfykAAgcACQnSInYFAOYCAAcACQnSInYFAOYCAAAA.Syssana:BAAALgAECgIJBgAAAA==.',
Ta='Tadaa:BAAALgADCgIJAgAAAA==.Tamerlein:BAAALgAECgMJBQAAAA==.Tamioka:BAAALgAECgYJCAAAAA==.Tanookii:BAAALgAECgYJEwAAAA==.',
Te='Telafar:BAAALgAECgkJAwAAAA==.',
Th='Theinsider:BAABLgAECn9EAAMGAAkJAyK8CwDkAgAGAAkJAyK8CwDkAgANAAUJkA+nKwARAQAAAA==.Thenezath:BAAALgAECgUJBQAAAA==.Theoutsider:BAAALgAECgYJCAABLgAECgkJRAAGAAMiAA==.Thunrus:BAAALgADCgYJBgAAAA==.',
Ti='Tibbles:BAAALgAECgcJCAAAAA==.Tigerbait:BAAALgAECgYJEQAAAA==.Tindril:BAAALgAECgYJBwAAAA==.Tinymo:BAAALgAECgMJAwAAAA==.',
To='Toji:BAABLgAECn8WAAIHAAcJ+hgRHgC2AQAHAAcJ+hgRHgC2AQABLgAFFAYJKAATAEcfAA==.Tomatoteng:BAACLgAFFH8OAAIFAAYJ3xXQFQCLAQAFAAYJ3xXQFQCLAQAuAAQKfyAAAgUACQmPJH4DAJsDAAUACQmPJH4DAJsDAAAA.Totegoat:BAAALgADCgEJAQAAAA==.Totemmalotes:BAAALgADCgcJBwAAAA==.Totemofbear:BAABLgAECn8bAAIjAAkJzhDXDQC1AQAjAAkJzhDXDQC1AQAAAA==.',
Tr='Trandis:BAAALgADCgMJBAABLgAECgkJKAAJANcmAA==.Tranza:BAABLgAECn8cAAQkAAgJOw18IACKAQAkAAgJcgp8IACKAQAaAAYJXwvhfgDrAAAXAAYJzAZBWADlAAAAAA==.Treesus:BAAALgADCgcJBwABLgAECgkJKAABALwiAA==.Trinshunter:BAABLgAECn8pAAQaAAkJ3Bf8KQAfAgAaAAkJ3Bf8KQAfAgAkAAEJ6gnELwA0AAAXAAEJ4gEnmgAZAAABLgAFFAUJEgAFAPcNAA==.',
Tx='Tx:BAACLgAFFH8oAAITAAYJRx+hDACbAQATAAYJRx+hDACbAQAuAAQKfywAAhMACAmNIUcQAKcCABMACAmNIUcQAKcCAAAA.',
Ty='Tyedye:BAAALgAECgEJAQAAAA==.',
['Tí']='Tíbs:BAAALgAECgYJCwAAAA==.',
Un='Unbound:BAAALgADCgcJEgAAAA==.Unholygirl:BAAALgAECgEJAQAAAA==.',
Ut='Utterchaos:BAAALgAECgUJDwAAAA==.',
Va='Vandrina:BAAALgAECgkJEAAAAA==.Vaporeon:BAAALgAECgEJAQAAAA==.',
Vi='Victreebel:BAAALgAECgcJEQAAAA==.',
Vo='Volg:BAAALgAECgQJBAAAAA==.',
We='Wekko:BAAALgADCgUJBQAAAA==.Wendys:BAABLgAECn8oAAIDAAkJ6xbMUgA/AgADAAkJ6xbMUgA/AgAAAA==.Wetheals:BAAALgAECgMJBgAAAA==.',
Wh='Whitemonster:BAAALgADCggJDQAAAA==.',
Wi='Wickedhunter:BAAALgADCgYJBgAAAA==.Wimpykid:BAAALgADCggJCAAAAA==.Winar:BAABLgAECn8hAAIDAAgJAhBzdQB0AQADAAgJAhBzdQB0AQAAAA==.',
Wo='Worgnfreeman:BAABLgAECn8VAAMQAAcJ0gkWoAAWAQAQAAcJ+wgWoAAWAQAOAAcJIQbDHAC1AAAAAA==.',
Wr='Wraithsdaddy:BAAALgADCgEJAQAAAA==.',
Wt='Wtfdrood:BAAALgAECgQJCQABLgAFFAMJBgAfAIoLAA==.Wtfmate:BAAALgADCgYJCQABLgAFFAMJBgAfAIoLAA==.Wtfmonk:BAACLgAFFH8GAAIfAAMJigthMwCaAAAfAAMJigthMwCaAAAuAAQKfygAAh8ACQn+HKEKAM4CAB8ACQn+HKEKAM4CAAAA.',
Xa='Xaioli:BAABLgAECn8gAAMGAAkJaSV0CAA9AwAGAAkJaSV0CAA9AwANAAIJwyF/RQCgAAAAAA==.',
Xe='Xemu:BAAALgADCgUJBQAAAA==.Xethani:BAABLgAECn8UAAIbAAcJkhHdDQBZAQAbAAcJkhHdDQBZAQAAAA==.',
Xo='Xorcopressor:BAAALgAECgIJAgAAAA==.',
Xs='Xsaber:BAAALgAECgIJAgAAAA==.',
Ya='Yazmo:BAACLgAFFH8PAAIHAAUJMCS6CQCXAQAHAAUJMCS6CQCXAQAuAAQKfzcAAgcACAmwIxQKAJMCAAcACAmwIxQKAJMCAAEuAAUUAwkEAA8AAAAA.',
Yu='Yuuky:BAACLgAFFH8TAAIKAAQJ1RLnJQAWAQAKAAQJ1RLnJQAWAQAuAAQKfzMAAwoACQl2G5AUAJICAAoACQl2G5AUAJICACUABwkqCWcvAMcAAAAA.',
Za='Zarivia:BAAALgADCgMJAwAAAA==.Zartaz:BAABLgAECn8aAAMiAAgJtQyXHAChAQAiAAgJtQyXHAChAQAUAAEJWgcHJgAoAAAAAA==.',
Zb='Zbonez:BAAALgAECgUJBgAAAA==.',
Ze='Zendrov:BAABLgAECn8iAAIVAAgJqwVgUQDDAAAVAAgJqwVgUQDDAAAAAA==.Zenpai:BAAALgAECgEJBgAAAA==.',
Zi='Ziillah:BAAALgAECgIJAgAAAA==.Zinogre:BAABLgAECn8zAAIEAAkJqRVLCQAQAgAEAAkJqRVLCQAQAgAAAA==.',
['Äp']='Äpollo:BAAALgAECgMJBwAAAA==.',
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
