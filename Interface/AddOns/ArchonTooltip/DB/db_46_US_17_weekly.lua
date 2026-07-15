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

local lookup = {'Shaman-Restoration','Warrior-Protection','Warrior-Fury','Mage-Frost','Shaman-Enhancement','Paladin-Retribution','Warlock-Demonology','Priest-Shadow','DemonHunter-Devourer','Druid-Restoration','Priest-Holy','Warrior-Arms','Warlock-Destruction','DeathKnight-Frost','Druid-Guardian','Warlock-Affliction','DeathKnight-Unholy','Paladin-Holy','Unknown-Unknown','Druid-Balance','Shaman-Elemental','Paladin-Protection','Evoker-Devastation','Evoker-Augmentation','Hunter-Survival','Monk-Windwalker','Hunter-Marksmanship','DemonHunter-Havoc','Hunter-BeastMastery','DemonHunter-Vengeance','Monk-Brewmaster','Priest-Discipline','Monk-Mistweaver','DeathKnight-Blood','Rogue-Subtlety','Evoker-Preservation','Druid-Feral','Mage-Fire',}
local provider = {region='US',realm='Archimonde',name='US',type='weekly',zone=46,date='2026-07-12',data={Aa='Aanaleaa:BAABLgAECn8XAAIBAAkJFwqMWABVAQABAAkJFwqMWABVAQAAAA==.',
Ab='Abelram:BAAALgADCgUJBQAAAA==.',
Ad='Ad:BAABLgAECn8wAAMCAAkJTCHHAwD0AgACAAkJTCHHAwD0AgADAAUJ+QpiaAC9AAABLgAFFAQJBgAEAHcPAA==.Adellon:BAABLgAFFH8NAAIFAAUJ9heVBwA+AQAFAAUJ9heVBwA+AQAAAA==.Adhar:BAAALgAECgQJBwAAAA==.Adrielle:BAABLgAECn8vAAIGAAgJnhbvBwCdAQAGAAgJnhbvBwCdAQAAAA==.',
Ae='Aeiox:BAAALgADCgMJAwAAAA==.Aevelman:BAABLgAECn9LAAIHAAkJDyCCAQDAAgAHAAkJDyCCAQDAAgAAAA==.',
Af='Affinty:BAAALgAECgQJBAABLgAFFAcJFgAIAHkbAA==.',
Ag='Ag:BAAALgAFFAEJAQAAAA==.',
Ai='Airphobic:BAABLgAECn8VAAIBAAUJPBvRTQB6AQABAAUJPBvRTQB6AQAAAA==.',
Ak='Akakage:BAAALgAECgEJAQABLgAECggJGQAJACoXAA==.Akakaji:BAABLgAECn8ZAAIJAAgJKhe9PQDRAQAJAAgJKhe9PQDRAQAAAA==.Akutoku:BAAALgADCgcJDAAAAA==.',
Al='Aland:BAAALgADCggJEgAAAA==.Alea:BAABLgAECn8cAAIKAAgJMxxsFACSAgAKAAgJMxxsFACSAgAAAA==.Almodiir:BAAALgADCgUJCQAAAA==.Almoraz:BAAALgAECgUJBQAAAA==.',
An='Anachron:BAAALgADCgIJAgAAAA==.Anaki:BAAALgAECgIJAgAAAA==.Annakkin:BAAALgAECgYJDgAAAA==.Anomander:BAABLgAECn8jAAIJAAYJtQzgogDeAAAJAAYJtQzgogDeAAAAAA==.Anonymoose:BAAALgADCgQJBAAAAA==.',
Ao='Aol:BAAALgADCgUJBQAAAA==.',
Ar='Ar:BAABLgAECn8XAAILAAcJfBDSMgA+AQALAAcJfBDSMgA+AQABLgAFFAQJBgAEAHcPAA==.Aratar:BAAALgAECgMJAwAAAA==.Arbiter:BAAALgAECgUJCQAAAA==.Archon:BAACLgAFFH8FAAMMAAMJOxqaMQCXAAAMAAIJhBmaMQCXAAADAAEJqRviTwBNAAAuAAQKfx4AAwMACAkwHpoXADECAAMACAkwHpoXADECAAwABAnJFfRCALwAAAAA.Argig:BAAALgAFFAEJAQAAAA==.Arienca:BAABLgAECn85AAMNAAkJchBHFgCYAQANAAgJnhBHFgCYAQAHAAkJaAuiXQCGAQAAAA==.Arwenn:BAAALgAECgEJAgAAAA==.',
As='Aspir:BAEALgAECggJCAABLgAFFAgJGQAOAIATAA==.Asu:BAABLgAECn8tAAMKAAkJ4RPcJgAZAgAKAAkJ4RPcJgAZAgAPAAcJNQg8CQCzAAAAAA==.',
At='At:BAACLgAFFH8GAAIEAAQJdw9/YQAfAQAEAAQJdw9/YQAfAQAuAAQKfxkAAgQABgnKFROoAIkBAAQABgnKFROoAIkBAAAA.',
Au='Aubrey:BAACLgAFFH8NAAIKAAYJpQW2LAACAQAKAAYJpQW2LAACAQAuAAQKfxQAAgoACQlyCqVSAFwBAAoACQlyCqVSAFwBAAAA.',
Av='Avengion:BAABLgAECn8VAAIOAAcJ8wmiGQAFAQAOAAcJ8wmiGQAFAQAAAA==.',
Ba='Baeblade:BAAALgADCgEJAQAAAA==.Balthromaw:BAAALgADCggJDQAAAA==.Barbato:BAAALgADCgYJCQAAAA==.Barbie:BAAALgADCgYJBgAAAA==.',
Be='Beararms:BAAALgADCgcJCAAAAA==.Beav:BAAALgAECgYJBwABLgAFFAYJFQAKAOoaAA==.Beefkeeper:BAAALgAFFAIJAgAAAA==.Beldent:BAAALgAECgQJBwAAAA==.Belöved:BAAALgAECgUJCAABLgAECgkJOgALAPMhAA==.Benelli:BAAALgAECgEJAQAAAA==.Bernard:BAAALgAECgUJBwAAAA==.',
Bi='Bitey:BAAALgAFFAQJBAABLgAFFAgJGAAQACIVAA==.',
Bl='Blazegrave:BAABLgAECn8sAAIRAAkJXhiGAwA7AgARAAkJXhiGAwA7AgABLgAECgkJXgAEAMsZAA==.Blazeofglory:BAAALgADCgUJBQABLgAECgkJLQARANMJAA==.Blazerager:BAAALgADCgYJEAABLgAECgkJXgAEAMsZAA==.Blazerunner:BAABLgAECn9eAAIEAAkJyxn7AwA8AgAEAAkJyxn7AwA8AgAAAA==.Blazesmasher:BAAALgAECgkJCgABLgAECgkJXgAEAMsZAA==.Blitzkreig:BAABLgAECn8bAAIRAAkJGRjkMQA3AgARAAkJGRjkMQA3AgAAAA==.Bluefoot:BAABLgAECn8fAAIBAAYJ/AhzfADqAAABAAYJ/AhzfADqAAAAAA==.Blured:BAACLgAFFH8MAAIJAAMJ2hm7HwDvAAAJAAMJ2hm7HwDvAAAuAAQKf0wAAgkACQlwJPsDAEcDAAkACQlwJPsDAEcDAAAA.',
Bo='Booty:BAABLgAECn8oAAICAAkJvCKMBQDhAgACAAkJvCKMBQDhAgAAAA==.',
Br='Brightblayde:BAABLgAECn8gAAIGAAgJEhJDagCaAQAGAAgJEhJDagCaAQAAAA==.Brynhildre:BAABLgAECn8UAAISAAcJfgtURABmAQASAAcJfgtURABmAQABLgAFFAYJDQAKAKUFAA==.',
Bu='Buum:BAABLgAECn8XAAICAAkJghaLDQASAgACAAkJghaLDQASAgAAAA==.',
By='Byane:BAAALgADCgYJBgAAAA==.',
['Bä']='Bämba:BAAALgAECgMJAwABLgAECgkJKwAEABoQAA==.',
Ca='Cachelyn:BAAALgAECgYJEgAAAA==.Calerus:BAAALgADCgkJCQAAAA==.Cali:BAACLgAFFH8hAAIJAAgJABxODwA8AgAJAAgJABxODwA8AgAuAAQKfy4AAgkACAmkIeQSAOgCAAkACAmkIeQSAOgCAAAA.Cantouchthes:BAABLgAECn8UAAIEAAgJZB7ERAANAgAEAAgJZB7ERAANAgAAAA==.Captnage:BAAALgADCggJCAAAAA==.Carafe:BAAALgAECgUJDAAAAA==.',
Ce='Cederred:BAAALgAECgUJBQABLgAECggJCgATAAAAAA==.Cedertree:BAAALgADCgcJBwABLgAECggJCgATAAAAAA==.Celline:BAAALgADCgEJAQAAAA==.Cephus:BAABLgAFFH8QAAIKAAcJPBRAEQDtAQAKAAcJPBRAEQDtAQAAAA==.Cerafina:BAAALgADCgEJAQAAAA==.',
Ch='Chayse:BAAALgAFFAMJBAABLgAFFAYJDQAKAKUFAA==.Choom:BAABLgAECn8fAAMKAAkJuhUONgDQAQAKAAkJuhUONgDQAQAUAAYJjRPrLgCOAQAAAA==.Chorizo:BAAALgADCgEJAQAAAA==.Christhina:BAAALgADCgQJBAAAAA==.Chronoclasm:BAACLgAFFH8RAAIVAAQJmB1qGgBIAQAVAAQJmB1qGgBIAQAuAAQKfyoAAhUACQnbHxEQAKkCABUACQnbHxEQAKkCAAAA.Chronophasia:BAABLgAECn8jAAMGAAgJHSFIHQCWAgAGAAgJFSFIHQCWAgAWAAQJfBtoJADyAAAAAA==.Chroños:BAABLgAECn8UAAMXAAcJEA85FADKAAAYAAcJ6g0BSAALAQAXAAQJZw45FADKAAAAAA==.Chumléé:BAAALgADCgQJBAAAAA==.Chérry:BAACLgAFFH8jAAIJAAgJVhpaEAAxAgAJAAgJVhpaEAAxAgAuAAQKfyAAAgkACQlsIowQAPoCAAkACQlsIowQAPoCAAAA.',
Ci='Ciri:BAAALgAFFAIJAwAAAA==.',
Cl='Climpwimp:BAAALgAECgIJAgAAAA==.Cluntasaur:BAAALgAECgUJBgABLgAFFAIJAwATAAAAAA==.',
Co='Connerr:BAABLgAECn8aAAIKAAgJtBorLwDnAQAKAAgJtBorLwDnAQAAAA==.Contendor:BAAALgAECgkJCQAAAA==.Cowage:BAAALgAECgQJCQAAAA==.',
Cr='Crisse:BAAALgAECgUJCgAAAA==.Croh:BAABLgAECn8aAAMRAAgJpBNfVAD0AQARAAgJpBNfVAD0AQAOAAQJawb3DwCcAAAAAA==.Crucks:BAAALgADCgQJBAAAAA==.Cruknar:BAABLgAFFH8KAAIZAAUJ5xQnBABJAQAZAAUJ5xQnBABJAQAAAA==.',
Cu='Curita:BAAALgADCgEJAQAAAA==.',
Cy='Cynestra:BAABLgAECn8XAAISAAkJHRMQHQAbAgASAAkJHRMQHQAbAgAAAA==.Cytheris:BAAALgAECgEJAQABLgAECggJGgAKALQaAA==.',
Da='Daddio:BAEALgAECgQJBAABLgADCgcJBwATAAAAAA==.Dadudadu:BAACLgAFFH8nAAIGAAgJ6hC+DwDyAQAGAAgJ6hC+DwDyAQAuAAQKfzQAAgYACQkZIHoWAOICAAYACQkZIHoWAOICAAAA.Daffo:BAAALgAECgIJAQAAAA==.Daftmonk:BAACLgAFFH8mAAIaAAgJmSCcAQB6AgAaAAgJmSCcAQB6AgAuAAQKfywAAhoACQmSJbECAG8DABoACQmSJbECAG8DAAAA.Daitanfuteki:BAAALgADCgEJAQABLgAFFAQJCAAbAOcVAA==.Dalan:BAAALgAECgEJAQAAAA==.Darkfyre:BAAALgADCgEJAgAAAA==.Darks:BAAALgAECgIJAgAAAA==.Darkwingfish:BAABLgAECn8pAAIJAAkJrRSlRgCzAQAJAAkJrRSlRgCzAQAAAA==.Darmonevil:BAAALgADCgEJAQAAAA==.Dartran:BAAALgADCgIJBwAAAA==.Dasarus:BAABLgAECn8ZAAMcAAgJsxprEAAhAgAcAAgJsxprEAAhAgAJAAYJWw9EkQD+AAAAAA==.Dayman:BAABLgAECn8UAAMWAAcJgwIdNACSAAAWAAcJXAIdNACSAAAGAAYJ0gFTSAFkAAAAAA==.',
De='Decày:BAAALgAECgcJEAAAAA==.Defknight:BAAALgADCgcJBwAAAA==.Demoteck:BAAALgAECgQJBgAAAA==.Demy:BAAALgADCgYJBgAAAA==.Deredris:BAAALgAECgEJAQAAAA==.Deth:BAAALgAECgIJAgABLgAECgMJDAATAAAAAA==.Dethblow:BAAALgAECgMJDAAAAA==.',
Di='Disconnects:BAAALgADCgUJBQAAAA==.Dium:BAAALgAECgEJAQAAAA==.Diwa:BAACLgAFFH8FAAIBAAUJ5QG+PgDpAAABAAUJ5QG+PgDpAAAuAAQKfxkAAwEACQn8BthsABUBAAEACQn8BthsABUBABUABglJB+BRAP8AAAAA.',
Dk='Dklot:BAACLgAFFH8LAAIRAAUJIxOFcAAeAQARAAUJIxOFcAAeAQAuAAQKfxgAAxEABwlZHI53AHUBABEABwlZHI53AHUBAA4AAQn1DK48AC0AAAAA.',
Dr='Dracthfear:BAAALgAECgYJBwABLgAFFAgJHQAHAMYfAA==.Dragolot:BAAALgADCgQJBAABLgAFFAUJCwARACMTAA==.Draken:BAAALgAECgEJAQAAAA==.Draviin:BAABLgAECn8xAAIdAAkJ9x0hIQBiAgAdAAkJ9x0hIQBiAgAAAA==.',
Du='Duckcheese:BAAALgADCgEJAQAAAA==.Dunkyn:BAAALgAECgMJBgAAAA==.Durzoblint:BAAALgAECgUJCAAAAA==.',
Dy='Dyemon:BAAALgADCgIJAgAAAA==.',
['Dé']='Déad:BAAALgADCgcJDAAAAA==.',
El='Elementz:BAAALgAECgIJAgAAAA==.Elerae:BAABLgAECn8nAAIGAAkJ+hthFgDjAgAGAAkJ+hthFgDjAgAAAA==.Eleshkigal:BAABLgAECn8oAAMJAAkJ1yaKAwCTAwAJAAkJ1yaKAwCTAwAeAAQJiBoiEgAsAQAAAA==.',
En='Enkeke:BAACLgAFFH8NAAIRAAMJphEKOADbAAARAAMJphEKOADbAAAuAAQKfz8AAhEACQkOHsElAG0CABEACQkOHsElAG0CAAAA.',
Er='Eresanna:BAABLgAFFH8PAAIEAAQJpQyeZwAUAQAEAAQJpQyeZwAUAQAAAA==.Ereshkigal:BAAALgAECgUJBgAAAA==.',
Es='Esdeath:BAAALgAECgQJCAABLgAFFAcJEQAcAFIRAA==.Estus:BAABLgAECn8VAAMSAAgJNhfbKgC5AQASAAgJNhfbKgC5AQAGAAIJ1gmSfwE9AAAAAA==.',
Ex='Extremefear:BAABLgAECn84AAMNAAkJbBe/FAAHAQAHAAUJbxUrdQBPAQANAAYJ8RW/FAAHAQAAAA==.',
Fa='Fatima:BAAALgAECgIJAwAAAA==.',
Fe='Fearious:BAACLgAFFH8dAAQHAAgJxh/LKgCbAQAHAAcJQSPLKgCbAQAQAAIJYSZZEwBwAAANAAEJpghBDQBMAAAuAAQKfyYABAcACAlBJkYvABsCAAcABwk3JEYvABsCAA0AAwl7JTUZANkAABAAAQncI6wsAGkAAAAA.Felphetamine:BAAALgADCggJCAAAAA==.Fenrisfangs:BAABLgAECn8VAAIdAAkJSA6jVACmAQAdAAkJSA6jVACmAQAAAA==.Fenrisul:BAAALgAECgUJBQAAAA==.Feralshunter:BAACLgAFFH8IAAIbAAQJ5xWhFwD9AAAbAAQJ5xWhFwD9AAAuAAQKfzIAAhsACQkAIZcQALcCABsACQkAIZcQALcCAAAA.Feroond:BAAALgADCgQJBAAAAA==.',
Fi='Fingeritout:BAAALgADCgIJAgAAAA==.Firefly:BAAALgAECgMJAwAAAA==.',
Fl='Florea:BAAALgADCggJDAAAAA==.',
Fo='Fodurzind:BAAALgAECgEJAQAAAA==.Forfoxsake:BAABLgAECn8kAAIfAAgJmR/nEQAoAgAfAAgJmR/nEQAoAgAAAA==.',
Fr='Frogteeth:BAAALgADCgUJBQAAAA==.',
Fu='Furibeav:BAABLgAFFH8VAAIKAAYJ6hpnEgDfAQAKAAYJ6hpnEgDfAQAAAA==.Furrow:BAAALgAECgQJBAAAAA==.Furrów:BAAALgAECgUJBwAAAA==.',
['Fû']='Fûrrow:BAAALgAECgcJEAAAAA==.',
Ga='Gallindral:BAABLgAECn9DAAIJAAkJFB5RFQCYAgAJAAkJFB5RFQCYAgAAAA==.Garanda:BAAALgAECgQJBQAAAA==.Gargantuan:BAAALgADCgMJAwAAAA==.Garreth:BAAALgAECgUJBQAAAA==.Gatito:BAAALgAECgEJAQABLgAECgIJAgATAAAAAA==.Gauthus:BAAALgAECgkJCgAAAA==.',
Ge='Genericnpc:BAABLgAECn8eAAQMAAgJvA+rIwBHAQAMAAgJ7QyrIwBHAQADAAYJVw0hVgD1AAACAAEJfxOeUQA3AAAAAA==.Geobrando:BAACLgAFFH8JAAMBAAMJbBe7GwDJAAABAAMJbBe7GwDJAAAVAAEJzQ1jVQA+AAAuAAQKfz4AAwEACQlOIG0LAMcCAAEACQlOIG0LAMcCABUABgm8HaknAK8BAAAA.',
Gg='Ggbrews:BAACLgAFFH8xAAIGAAgJKh2RBgDjAQAGAAgJKh2RBgDjAQAuAAQKf7UABAYACQlyJqUBAH8DAAYACQlyJqUBAH8DABIACAn5HQoNAMACABYABwm6DNEHAJ4AAAAA.',
Gh='Ghostblaze:BAAALgAECgUJDgABLgAECgkJXgAEAMsZAA==.',
Gi='Gier:BAAALgADCgUJBQAAAA==.Gino:BAAALgADCgEJAQAAAA==.',
Gl='Glacialwrait:BAAALgAECgIJBAAAAA==.Glacious:BAAALgADCgEJAQAAAA==.Glasswings:BAAALgAECgIJAgAAAA==.',
Gn='Gnosh:BAABLgAECn8aAAIUAAkJbxT0GQD8AQAUAAkJbxT0GQD8AQAAAA==.Gnova:BAABLgAECn8jAAIEAAYJfSG9YgC5AQAEAAYJfSG9YgC5AQAAAA==.',
Go='Gorian:BAAALgAECgcJCAAAAA==.',
Gr='Gregorz:BAAALgADCgEJAQAAAA==.Grish:BAAALgAECgEJAQAAAA==.',
Gu='Guidosarduci:BAABLgAECn8iAAIBAAgJhhdgHAA2AgABAAgJhhdgHAA2AgAAAA==.',
Ha='Hairia:BAAALgADCgUJBQAAAA==.Halen:BAAALgADCgcJBwABLgAFFAgJIQAJAAAcAA==.Hardone:BAAALgAECggJDwAAAA==.Harle:BAABLgAECn8bAAIEAAkJmheMMABXAgAEAAkJmheMMABXAgAAAA==.Hatari:BAAALgAECgMJAwAAAA==.',
He='Hektate:BAABLgAECn8WAAIEAAcJXQvbsgAdAQAEAAcJXQvbsgAdAQABLgAFFAgJJwAGAOoQAA==.Henryjones:BAAALgADCgEJAQAAAA==.',
Hi='Hikari:BAABLgAECn8WAAIGAAgJZiEkKwBUAgAGAAgJZiEkKwBUAgABLgAFFAcJMwAVAFseAA==.Hilkesad:BAAALgAECgQJBAAAAA==.Hizo:BAAALgADCgUJBQAAAA==.',
Ho='Holybeave:BAABLgAECn8eAAMLAAkJNB3/DACFAgAgAAkJaBi5CQCfAgALAAgJqx7/DACFAgABLgAFFAYJFQAKAOoaAA==.Holyshortguy:BAAALgAECgYJDwABLgAFFAYJDwAhADgOAA==.Hoofer:BAAALgAECgYJDgAAAA==.',
Hu='Hunkomeat:BAABLgAECn8XAAIDAAgJLhzkLAAAAgADAAgJLhzkLAAAAgAAAA==.',
['Hë']='Hënry:BAAALgAECgEJAQAAAA==.',
Ic='Icelmo:BAABLgAFFH8PAAIDAAUJIhX9GQBKAQADAAUJIhX9GQBKAQAAAA==.',
Ih='Ihotyou:BAAALgADCgQJBwAAAA==.',
Ik='Ikeyni:BAAALgAECgEJAQAAAA==.',
Il='Ilikeitrough:BAAALgAECgUJBQAAAA==.',
Im='Impact:BAAALgAECgYJBwABLgAFFAcJMwAVAFseAA==.',
In='Inai:BAAALgADCgcJDAABLgAFFAcJEQAcAFIRAA==.Invizww:BAAALgAECgQJBQAAAA==.',
Ir='Ircapslock:BAAALgAECgYJDgAAAA==.',
Iv='Ivorypal:BAABLgAECn8gAAISAAgJqR/dEACLAgASAAgJqR/dEACLAgAAAA==.',
Ja='Jacksock:BAAALgADCgEJAQAAAA==.Jamzz:BAAALgAECgQJBQABLgAFFAgJIAAbAMsQAA==.Jaromir:BAAALgADCgcJBwAAAA==.Jaskow:BAABLgAECn8uAAIKAAkJjiD/BwA4AwAKAAkJjiD/BwA4AwAAAA==.Jaymick:BAABLgAECn8aAAMdAAkJYhEVbgBlAQAZAAcJEQ6aIwCBAQAdAAcJjRIVbgBlAQAAAA==.',
Jb='Jbizzler:BAAALgAECgcJBgAAAA==.',
Jc='Jcrypt:BAAALgAECgcJAgAAAA==.',
Je='Jennika:BAABLgAFFH8GAAIZAAMJjwcvIgDIAAAZAAMJjwcvIgDIAAAAAA==.Jernau:BAAALgAECgEJAQAAAA==.Jessortess:BAAALgAECgQJBwAAAA==.',
Jo='Johnwicksdog:BAAALgAECggJEQAAAA==.Jorbies:BAAALgAECgYJCQABLgAFFAcJFgAIAHkbAA==.Jorls:BAACLgAFFH8WAAMIAAcJeRtMAgDeAQAIAAcJeRtMAgDeAQAgAAEJWAEnGwBDAAAuAAQKfxsABAgACQkFHlMIAP8CAAgACQkFHlMIAP8CACAABAnSCc08AMQAAAsAAglAAgl2AFEAAAAA.',
Ju='Junatooka:BAAALgAECgIJAgAAAA==.Jusdatip:BAAALgAECgUJDQAAAA==.',
Ka='Kaelthazed:BAAALgADCgEJAQABLgAFFAMJCgAHAB8WAA==.Kalfu:BAABLgAECn8XAAMdAAgJ0B1jPQDrAQAdAAgJ0B1jPQDrAQAbAAYJoBUDOgB5AQAAAA==.Kameshoga:BAAALgAECgIJAgAAAA==.Kammwin:BAAALgAECgYJEwAAAA==.Karten:BAAALgAECgcJEQAAAA==.Kaylea:BAAALgADCgIJAgAAAA==.',
Ke='Kellandria:BAAALgADCgcJFgAAAA==.',
Ki='Kieraleah:BAAALgAECgcJBwAAAA==.Killjoyss:BAAALgAFFAIJAwAAAA==.Kittêh:BAAALgAECgEJAQAAAA==.',
Kn='Knathor:BAAALgAECgQJBgABLgAECgcJDgATAAAAAA==.',
Ko='Korec:BAAALgAECgcJDgAAAA==.',
Kr='Krag:BAAALgAFFAEJAQABLgAFFAMJCAAfAPoUAA==.Krasis:BAABLgAECn8XAAIGAAkJvhrLWADYAQAGAAkJvhrLWADYAQAAAA==.Krazermonk:BAACLgAFFH8PAAIaAAUJmxoBEAA9AQAaAAUJmxoBEAA9AQAuAAQKfygAAhoACQmlHrMOAF4CABoACQmlHrMOAF4CAAAA.Krispinwah:BAACLgAFFH8HAAIRAAMJWRgESwCnAAARAAMJWRgESwCnAAAuAAQKfxoAAhEACQleHpsPAO8CABEACQleHpsPAO8CAAEuAAUUAwkJAAEAbBcA.Kristysavage:BAACLgAFFH8KAAIdAAMJaB7jHwAEAQAdAAMJaB7jHwAEAQAuAAQKfysAAh0ACQliI3oIABYDAB0ACQliI3oIABYDAAAA.Kroflavinof:BAAALgAECgUJCgAAAA==.',
Ku='Kurosakí:BAAALgAECgEJAQAAAA==.',
Ky='Kyle:BAAALgAECgIJAgABLgAFFAQJEgAGAFweAA==.',
La='Lagoon:BAAALgADCgEJAgAAAA==.Lanc:BAAALgAECgQJCQAAAA==.Lappytopdog:BAAALgAECgcJDAAAAA==.Larradin:BAAALgADCggJEAAAAA==.Lawnchair:BAAALgAECggJDAAAAA==.',
Le='Lealta:BAAALgAFFAEJAgABLgAFFAgJIwAgANofAA==.Leonus:BAAALgAECgQJCQAAAA==.Leviathahn:BAAALgAECgEJAgAAAA==.',
Lh='Lhegholhaz:BAAALgADCgIJAgAAAA==.',
Li='Lichdawg:BAACLgAFFH8ZAAMOAAYJ1RGLBwB1AQAOAAUJ1RGLBwB1AQAiAAEJAAAFYQAAAAAuAAQKfxQAAg4ACAnSE9sOAIcBAA4ACAnSE9sOAIcBAAAA.Lilzayna:BAAALgAECgEJAQABLgAFFAIJAwATAAAAAA==.Lindianda:BAAALgAECgYJBgAAAA==.Linthori:BAEALgADCgMJAwABLgAECgcJDQATAAAAAA==.Lirrin:BAAALgAECgIJAgAAAA==.Lithlia:BAAALgADCggJDQAAAA==.Livvela:BAABLgAECn8mAAIjAAkJsRX0FgDlAQAjAAkJsRX0FgDlAQAAAA==.',
Ll='Llas:BAAALgADCgIJAgAAAA==.',
Lo='Lockdawg:BAACLgAFFH8lAAIHAAcJLBqrDQCmAQAHAAcJLBqrDQCmAQAuAAQKfyYAAwcACAmFHRImAHoCAAcACAmFHRImAHoCAA0AAQnWFc1sADoAAAAA.Lockedin:BAAALgAECgkJEgAAAA==.Lonne:BAAALgAECgYJDgABLgAFFAIJBAATAAAAAA==.Lover:BAABLgAECn86AAILAAkJ8yGwDACbAgALAAkJ8yGwDACbAgAAAA==.',
Lu='Lubu:BAACLgAFFH8RAAIcAAcJUhFyCQBxAQAcAAcJUhFyCQBxAQAuAAQKfxoAAhwACQn+H2AFAOsCABwACQn+H2AFAOsCAAAA.Lucianis:BAAALgADCgQJBwAAAA==.Luckycharmz:BAAALgAECgQJCQABLgAFFAIJCgAgALIHAA==.Luckywar:BAAALgADCgYJBgAAAA==.Luell:BAAALgAECgcJDwAAAA==.Luev:BAAALgAECgYJCAAAAA==.Lumiette:BAABLgAECn8WAAMCAAcJ2RrDEQDOAQACAAcJ2RrDEQDOAQADAAMJFAvChQCoAAAAAA==.',
Ly='Lynai:BAABLgAECn8dAAIEAAkJPxLFcQCWAQAEAAkJPxLFcQCWAQAAAA==.',
['Lá']='Lándwhale:BAACLgAFFH8YAAIjAAQJxSNsEwBxAQAjAAQJxSNsEwBxAQAuAAQKfy4AAiMACQmTJFoEAPgCACMACQmTJFoEAPgCAAAA.',
['Lö']='Löver:BAAALgAECgcJDQABLgAECgkJOgALAPMhAA==.',
Ma='Mabil:BAABLgAECn8UAAQHAAcJRhJ1mgAIAQAHAAYJew11mgAIAQAQAAQJXRWcGAC2AAANAAIJNAydQgAoAAAAAA==.Macktimus:BAABLgAECn8gAAINAAkJYBhQBQAdAgANAAkJYBhQBQAdAgAAAA==.Madeinchina:BAAALgADCgEJAQAAAA==.Mage:BAAALgAFFAEJAgAAAA==.Magictonyp:BAABLgAECn8UAAIEAAUJ/Qe39wC5AAAEAAUJ/Qe39wC5AAAAAA==.Magicznstuff:BAAALgAECgEJAQABLgAECgMJBgATAAAAAA==.Magna:BAABLgAECn8lAAIDAAkJYRIuKQC0AQADAAkJYRIuKQC0AQAAAA==.Magnusbane:BAAALgAECgUJBQAAAA==.Makili:BAABLgAFFH8cAAIEAAYJthgKFwB4AQAEAAYJthgKFwB4AQAAAA==.Maladrix:BAAALgAECgQJDQAAAA==.Mauê:BAAALgADCgEJAQABLgAECgIJAgATAAAAAA==.',
Mc='Mchealer:BAAALgAECgUJCgAAAA==.Mchunter:BAAALgAECgMJAwAAAA==.Mcshadow:BAAALgADCgIJAgAAAA==.',
Me='Menphina:BAAALgAECgIJAgABLgAECgkJOgALAPMhAA==.Merigold:BAAALgAECgEJAQABLgAECgQJBAATAAAAAA==.Merlynin:BAAALgAECgEJAQABLgAECgkJMQAdAPcdAA==.',
Mi='Mickallv:BAAALgADCgMJAwAAAA==.Midevilz:BAAALgAECgQJBAAAAA==.Minnow:BAAALgAECgYJDgAAAA==.Mintchip:BAABLgAECn8QAAIJAAcJ3RdQSwCkAQAJAAcJ3RdQSwCkAQAAAA==.',
Mo='Monk:BAAALgAECgEJAQAAAA==.Monza:BAAALgADCgEJAQABLgAECgkJKAAEAOsWAA==.Moontini:BAAALgADCgcJBwABLgAECgQJDQATAAAAAA==.Mordryn:BAAALgADCgcJBwAAAA==.',
Mu='Murad:BAABLgAFFH8JAAIRAAQJsxCbJAAiAQARAAQJsxCbJAAiAQAAAA==.',
My='Mysternia:BAABLgAECn8VAAILAAgJ2w7EMwA3AQALAAgJ2w7EMwA3AQAAAA==.Myyagie:BAAALgADCgcJEQAAAA==.',
Na='Nalthexon:BAABLgAECn8qAAMhAAgJ2wtFMQAzAQAhAAgJ2wtFMQAzAQAaAAEJXQaerQAmAAABLgAFFAMJBgAKAHUGAA==.Natureborne:BAAALgAECgYJCQAAAA==.',
Ne='Nedrud:BAAALgADCgUJCAAAAA==.Nelson:BAEALgAECgYJCAABLgAECgkJLQAEAFEeAA==.Nenno:BAAALgADCgEJAQAAAA==.Netzhul:BAAALgAFFAEJAQAAAA==.',
Ni='Night:BAAALgAECgcJEQAAAA==.Nikalos:BAAALgAECgYJDQAAAA==.Nikole:BAAALgAECgMJAwAAAA==.',
No='Noon:BAAALgADCgUJBQABLgAECggJFQASADYXAA==.Notorckrag:BAACLgAFFH8IAAIfAAMJ+hQ3DQDWAAAfAAMJ+hQ3DQDWAAAuAAQKf0AAAh8ACQmSIx4DACIDAB8ACQmSIx4DACIDAAAA.Nozomi:BAABLgAECn8YAAIJAAkJ0QYJFACwAAAJAAkJ0QYJFACwAAAAAA==.',
Nu='Nut:BAAALgADCgQJBAAAAA==.',
['Nê']='Nêz:BAAALgAECgUJCAAAAA==.',
Oa='Oathbringer:BAAALgAECgQJBAAAAA==.',
Ob='Oblivionz:BAAALgAECgMJAwAAAA==.',
Oc='Ocho:BAAALgADCgYJCQAAAA==.',
Of='Offbrandcleo:BAAALgAECgkJBgAAAA==.',
Ok='Okibi:BAAALgAECgMJBQABLgAFFAcJEQAcAFIRAA==.',
Ol='Oldrecipe:BAABLgAFFH8NAAISAAUJ5RfVIwACAQASAAUJ5RfVIwACAQAAAA==.Oliange:BAABLgAECn8rAAIEAAgJGhAFcgCWAQAEAAgJGhAFcgCWAQAAAA==.',
Or='Ori:BAEALgADCgcJCwABLgAECgcJDQATAAAAAA==.Originalgank:BAACLgAFFH8VAAIEAAUJgB0CRwBXAQAEAAUJgB0CRwBXAQAuAAQKfyYAAgQACQkHJNcGAEkDAAQACQkHJNcGAEkDAAAA.',
Oz='Ozzi:BAAALgAECgMJAwAAAA==.',
Pa='Papanell:BAAALgADCgYJCQAAAA==.',
Pe='Peachcobbler:BAAALgAECggJDgAAAA==.Perc:BAAALgAECgcJEAAAAA==.',
Ph='Philsner:BAEALgAECgcJDQAAAA==.Phink:BAAALgAECgQJCgAAAA==.',
Pi='Pinkk:BAABLgAECn8XAAIdAAkJ/xxXGgCHAgAdAAkJ/xxXGgCHAgAAAA==.',
Pl='Plushie:BAABLgAECn8nAAIIAAgJugt3MABcAQAIAAgJugt3MABcAQAAAA==.',
Po='Pong:BAABLgAECn8YAAMFAAgJ3xl6DgDJAQAFAAcJgRl6DgDJAQABAAIJdhX1IwBFAAABLgAFFAIJCAAYAM8HAA==.Pooqy:BAACLgAFFH8QAAMRAAUJ4SRFOQCJAQARAAQJ4SRFOQCJAQAiAAEJAAC3SQAAAAAuAAQKfxYAAhEACAlWIrskAKsCABEACAlWIrskAKsCAAAA.Porcel:BAAALgADCgcJCwAAAA==.Potatoteng:BAABLgAFFH8KAAIOAAUJ1AsKBgAcAQAOAAUJ1AsKBgAcAQABLgAFFAcJDwAGAOEUAA==.Pozidrive:BAAALgAECgIJAgAAAA==.',
Pr='Pritej:BAAALgAECgYJCgABLgAFFAIJBAATAAAAAA==.Proto:BAAALgAECgcJDAAAAA==.',
Pu='Puck:BAAALgAFFAIJAwABLgAFFAcJEQAcAFIRAA==.Pulu:BAAALgAFFAEJAQABLgAFFAMJBgAIALgUAA==.',
Py='Pyraleus:BAAALgADCgQJBAAAAA==.',
Qm='Qmpell:BAAALgADCgYJBgAAAA==.',
Qu='Quickchicken:BAAALgAECgIJBgAAAA==.',
Ra='Ragel:BAACLgAFFH8FAAIUAAIJjxvXNgCiAAAUAAIJjxvXNgCiAAAuAAQKfzgAAhQACQn3IA8GAPcCABQACQn3IA8GAPcCAAAA.Rahor:BAAALgAECgEJAQAAAA==.Rainesage:BAABLgAECn80AAMIAAkJlB1qDQB9AgAIAAkJlB1qDQB9AgALAAEJxwcneAAiAAAAAA==.Ralphel:BAABLgAECn8qAAIGAAgJMwcJsAAfAQAGAAgJMwcJsAAfAQAAAA==.Rasmon:BAAALgAECggJCAAAAA==.Rasu:BAAALgADCgcJBwABLgAECggJGgAkALUMAA==.Ravendark:BAAALgAECgEJAQAAAA==.Rayozap:BAAALgAECgUJBgAAAA==.',
Re='Redeye:BAAALgADCgMJAwAAAA==.Relock:BAAALgAECgMJAwABLgAECggJGgAKALQaAA==.',
Rh='Rhondaa:BAAALgAECgYJEQAAAA==.Rhubarb:BAABLgAECn8/AAMMAAkJjiZFAQBcAwAMAAgJIiZFAQBcAwADAAgJoyRkDQCXAgAAAA==.',
Ri='Ripley:BAAALgAFFAEJAQAAAA==.Riptidepods:BAAALgAECgEJAQAAAA==.Riyci:BAAALgAECgEJAQAAAA==.',
Ro='Rohiem:BAACLgAFFH8IAAIDAAUJTwhLIQB6AAADAAUJTwhLIQB6AAAuAAQKfzgAAgMACQl0GscZACACAAMACQl0GscZACACAAAA.',
Ry='Ryan:BAABLgAECn8eAAIGAAkJZR4ZHADBAgAGAAkJZR4ZHADBAgAAAA==.Rylorthas:BAACLgAFFH8gAAMLAAcJdhNfCQC3AQALAAcJdhNfCQC3AQAgAAEJ5wQULQAsAAAuAAQKfy0AAgsACQl8HMsSAEoCAAsACQl8HMsSAEoCAAAA.Rylosh:BAAALgAFFAEJAQABLgAFFAcJIAALAHYTAA==.',
['Rî']='Rîkku:BAAALgADCgkJGQAAAA==.',
Sa='Sabot:BAABLgAECn8bAAMlAAkJVRvdBwBWAgAlAAkJVRvdBwBWAgAPAAQJmwpgTAB5AAAAAA==.Sabrook:BAAALgADCggJCAAAAA==.Salazar:BAAALgAECgEJAwAAAA==.Sam:BAAALgAECgUJBAAAAA==.Sandalhat:BAAALgAECgEJAQAAAA==.Sanll:BAAALgAECgcJBwAAAA==.Satisfied:BAABLgAECn8VAAILAAUJRhyNKACCAQALAAUJRhyNKACCAQAAAA==.',
Sc='Scottmonk:BAAALgAECgIJBQAAAA==.Scottpaladin:BAAALgAECgEJAQABLgAECgIJBQATAAAAAA==.',
Se='Seath:BAAALgAECggJEQABLgAFFAMJCgAHAB8WAA==.Sentaí:BAAALgAECgIJBAAAAA==.',
Sh='Shamantics:BAAALgAECgIJAwABLgAFFAgJHQAHAMYfAA==.Shamerica:BAACLgAFFH8bAAMFAAgJZxxcAQAXAgAFAAcJWiBcAQAXAgAVAAIJSg3jQACIAAAuAAQKfz4AAwUACQkyJKABABkDAAUACQn2IqABABkDABUACAnNI9QIANACAAAA.Shizuku:BAAALgADCgUJBQAAAA==.Shmooythefox:BAABLgAECn8lAAIdAAcJfCG3NgADAgAdAAcJfCG3NgADAgAAAA==.Shokan:BAAALgADCgQJBAAAAA==.Shortleedin:BAAALgAECgIJAQAAAA==.Shòckwave:BAAALgADCgQJBAAAAA==.',
Si='Sinrex:BAAALgADCgUJBwAAAA==.Sixstar:BAAALgADCgEJAQAAAA==.',
Sk='Skeetcream:BAAALgAECgIJAgABLgAECgUJBwATAAAAAA==.Skrt:BAAALgAECgMJAwAAAA==.Skyleax:BAACLgAFFH8KAAMRAAQJdg05fgAKAQARAAQJdg05fgAKAQAOAAEJwAL4LAA1AAAuAAQKfxgABBEACQkSIEYuAH8CABEACQnoHEYuAH8CAA4ABAkVHkUMAPAAACIAAQn7D0ZLACAAAAAA.',
Sl='Slagothor:BAABLgAECn8VAAIRAAkJywRnmQBNAQARAAkJywRnmQBNAQAAAA==.Slanesh:BAAALgAECgcJDwABLgAECgcJEAAJAN0XAA==.Sleaze:BAAALgADCgEJAQAAAA==.Sleazus:BAAALgAECgMJAwAAAA==.',
Sm='Smeesha:BAABLgAECn8nAAQkAAgJ3RgAEADLAQAkAAcJDxoAEADLAQAXAAYJRQcGJgDzAAAYAAYJyAehRgDBAAAAAA==.',
Sn='Snaxwell:BAAALgADCgEJAQAAAA==.',
So='Somin:BAAALgAECgMJBAAAAA==.',
Sp='Specialedz:BAAALgADCgUJBwAAAA==.Spekaleks:BAAALgADCgUJBwAAAA==.Spiritbox:BAAALgAECgYJBgAAAA==.',
Sq='Squitwurt:BAAALgADCgYJBgAAAA==.',
St='Starbux:BAABLgAECn8aAAMWAAgJ/g9mFwBlAQAWAAgJ/g9mFwBlAQASAAEJewNqnQAjAAAAAA==.Starbúcks:BAAALgAECgIJAwABLgAFFAIJCgAgALIHAA==.Steppers:BAAALgAECgUJAgAAAA==.Straamm:BAAALgADCgMJAwAAAA==.',
Su='Sugarr:BAAALgAECgEJAQAAAA==.Sunfish:BAAALgAECgYJCgAAAA==.',
Sv='Svelana:BAABLgAECn8lAAMaAAgJjSJ6DgBhAgAaAAgJjSJ6DgBhAgAhAAEJCgthxgAlAAAAAA==.',
Sy='Syb:BAABLgAECn8bAAQYAAkJZxdLGgAEAgAYAAkJlhVLGgAEAgAXAAQJ4hlAEgDmAAAkAAEJFwU3SwArAAAAAA==.Sylphrena:BAACLgAFFH8TAAIIAAUJgyAAEABtAQAIAAUJgyAAEABtAQAuAAQKfykAAggACQnSIscGAOUCAAgACQnSIscGAOUCAAAA.Syssana:BAAALgAECgIJBgAAAA==.',
Ta='Tadaa:BAAALgADCgIJAgAAAA==.Tamerlein:BAAALgAECgMJBQAAAA==.Tamioka:BAAALgAECgYJCAAAAA==.Tanookii:BAAALgAECgYJEwAAAA==.',
Th='Theinsider:BAACLgAFFH8KAAIHAAMJHxa9JQDTAAAHAAMJHxa9JQDTAAAuAAQKf0QAAwcACQkDImUOANoCAAcACQkDImUOANoCAA0ABQmQD6crABEBAAAA.Thenezath:BAAALgAECgYJCQAAAA==.Theoutsider:BAABLgAFFH8GAAIRAAMJxxCoOADZAAARAAMJxxCoOADZAAABLgAFFAMJCgAHAB8WAA==.Thunrus:BAAALgADCgYJBgAAAA==.',
Ti='Tibbles:BAAALgAECgcJCAAAAA==.Tigerbait:BAABLgAECn8WAAImAAYJOhFHAQAPAQAmAAYJOhFHAQAPAQAAAA==.Tindril:BAAALgAECgYJBwAAAA==.Tinymo:BAAALgAECgMJAwAAAA==.',
To='Toeknees:BAAALgAECgIJAwAAAA==.Toji:BAABLgAECn8WAAIIAAcJ+hj7IQC3AQAIAAcJ+hj7IQC3AQABLgAFFAcJMwAVAFseAA==.Tomatoteng:BAACLgAFFH8PAAIGAAcJ4RTGEwDMAQAGAAcJ4RTGEwDMAQAuAAQKfyAAAgYACQmPJH4DAJsDAAYACQmPJH4DAJsDAAAA.Totegoat:BAAALgADCgEJAQAAAA==.Totemmalotes:BAAALgADCgcJBwAAAA==.Totemofbear:BAABLgAECn8oAAIlAAkJFhYvCgAeAgAlAAkJFhYvCgAeAgAAAA==.',
Tr='Trandis:BAAALgADCgMJBAABLgAECgkJKAAJANcmAA==.Tranza:BAABLgAECn8cAAQZAAgJOw3ZIwB/AQAZAAgJcgrZIwB/AQAdAAYJXwvhfgDrAAAbAAYJzAZBWADlAAAAAA==.Treesus:BAAALgADCgcJBwABLgAECgkJKAACALwiAA==.Trinshunter:BAABLgAECn9BAAQdAAkJGB2oFACtAgAdAAkJGB2oFACtAgAZAAEJ6gnELwA0AAAbAAEJ4gEnmgAZAAABLgAFFAcJHQAGACEQAA==.',
Tx='Tx:BAACLgAFFH8zAAIVAAcJWx7KBwCWAQAVAAcJWx7KBwCWAQAuAAQKfywAAhUACAmNIUcQAKcCABUACAmNIUcQAKcCAAAA.',
Ty='Tyedye:BAAALgAECgEJAQAAAA==.',
['Tí']='Tíbs:BAAALgAECgYJCwAAAA==.',
Un='Unbound:BAAALgADCgcJEgAAAA==.Unclegoon:BAAALgAECgEJAQAAAA==.Unholygirl:BAAALgAECgEJAQAAAA==.',
Ut='Utterchaos:BAAALgAECgUJDwAAAA==.',
Va='Vandrina:BAACLgAFFH8OAAICAAMJUATZEACBAAACAAMJUATZEACBAAAuAAQKfxgAAgIACQncBvEhACABAAIACQncBvEhACABAAAA.Vanthion:BAAALgAECgYJCQAAAA==.Vaporeon:BAAALgAECgEJAQAAAA==.',
Ve='Vekris:BAAALgAECgEJAQAAAA==.',
Vi='Victreebel:BAAALgAECgcJEQAAAA==.',
Vo='Volg:BAAALgAECgQJBAAAAA==.',
We='Wekko:BAAALgADCgUJBQAAAA==.Wendys:BAABLgAECn8oAAIEAAkJ6xbMUgA/AgAEAAkJ6xbMUgA/AgAAAA==.Wetheals:BAAALgAECgMJBgAAAA==.',
Wh='Whitemonster:BAAALgADCggJDQAAAA==.',
Wi='Wickedhunter:BAAALgADCgYJBgAAAA==.Wimpykid:BAAALgADCggJCAAAAA==.Winar:BAABLgAECn8hAAIEAAgJAhCMgwBwAQAEAAgJAhCMgwBwAQAAAA==.',
Wo='Worgnfreeman:BAACLgAFFH8HAAIOAAcJ+gHyCADeAAAOAAcJ+gHyCADeAAAuAAQKfxoAAw4ABwnPC/AGAJYAABEABwn7CO+zAA4BAA4ABwmFCvAGAJYAAAAA.',
Wr='Wraithsdaddy:BAAALgADCgEJAQAAAA==.',
Wt='Wtfdrood:BAAALgAECgQJCQABLgAFFAYJDwAhADgOAA==.Wtfmate:BAAALgAECgIJAgABLgAFFAYJDwAhADgOAA==.Wtfmonk:BAACLgAFFH8PAAIhAAYJOA42LAAQAQAhAAYJOA42LAAQAQAuAAQKfygAAiEACQn+HIcMANECACEACQn+HIcMANECAAAA.',
Xa='Xaioli:BAABLgAECn8gAAMHAAkJaSV0CAA9AwAHAAkJaSV0CAA9AwANAAIJwyF/RQCgAAAAAA==.',
Xe='Xemu:BAAALgADCgUJBQAAAA==.Xethani:BAABLgAECn8bAAIeAAkJbhEiCgDDAQAeAAkJbhEiCgDDAQAAAA==.',
Xo='Xorcopressor:BAAALgAECgIJAgAAAA==.',
Xs='Xsaber:BAAALgAECgQJBgAAAA==.',
Ya='Yazmo:BAACLgAFFH8UAAIIAAcJwSMNCADsAQAIAAcJwSMNCADsAQAuAAQKfzcAAggACAmwI70LAJMCAAgACAmwI70LAJMCAAEuAAUUBQkKABkA5xQA.',
Yu='Yuuky:BAACLgAFFH8XAAIKAAYJfhFqIwA+AQAKAAYJfhFqIwA+AQAuAAQKfzoABAoACQlNHbUWAJICAAoACQlNHbUWAJICAA8ABwkjCak4AMQAACUAAQnbGpVGAE4AAAAA.',
Za='Zalmo:BAAALgAECgEJAQABLgAECgkJHwAXAJkUAA==.Zarivia:BAAALgADCgMJAwAAAA==.Zartaz:BAABLgAECn8aAAMkAAgJtQyXHAChAQAkAAgJtQyXHAChAQAXAAEJWgc9KgAmAAAAAA==.',
Zb='Zbonez:BAABLgAECn8VAAIEAAkJtgjBrQAlAQAEAAkJtgjBrQAlAQAAAA==.',
Ze='Zendrov:BAABLgAECn8iAAIYAAgJqwViWADRAAAYAAgJqwViWADRAAAAAA==.Zenpai:BAAALgAECgEJBgAAAA==.',
Zi='Ziillah:BAAALgAECgIJAgAAAA==.Zinogre:BAABLgAECn8zAAIFAAkJqRUOCwAGAgAFAAkJqRUOCwAGAgAAAA==.',
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
