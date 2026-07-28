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

local lookup = {'Shaman-Restoration','Warrior-Protection','Warrior-Fury','Mage-Frost','Shaman-Enhancement','Paladin-Retribution','Warlock-Demonology','Priest-Shadow','DemonHunter-Devourer','Druid-Restoration','Priest-Holy','Warrior-Arms','Warlock-Destruction','DemonHunter-Havoc','DeathKnight-Frost','Druid-Balance','Druid-Guardian','Warlock-Affliction','DeathKnight-Unholy','Mage-Arcane','Paladin-Holy','Unknown-Unknown','Hunter-BeastMastery','Shaman-Elemental','Paladin-Protection','Evoker-Devastation','Evoker-Augmentation','Hunter-Survival','Monk-Windwalker','Hunter-Marksmanship','DemonHunter-Vengeance','Monk-Brewmaster','Priest-Discipline','Monk-Mistweaver','DeathKnight-Blood','Rogue-Subtlety','Evoker-Preservation','Druid-Feral','Mage-Fire',}
local provider = {region='US',realm='Archimonde',name='US',type='weekly',zone=46,date='2026-07-28',data={Aa='Aanaleaa:BAABLgAECn8XAAIBAAkJFwqMWABVAQABAAkJFwqMWABVAQAAAA==.',
Ab='Abelram:BAAALgADCgUJBQAAAA==.',
Ad='Ad:BAABLgAECn8wAAMCAAkJTCHHAwD0AgACAAkJTCHHAwD0AgADAAUJ+QpiaAC9AAABLgAFFAQJBgAEAHcPAA==.Adellon:BAABLgAFFH8NAAIFAAUJ9heVBwA+AQAFAAUJ9heVBwA+AQAAAA==.Adhar:BAAALgAECgQJBwAAAA==.Adrielle:BAABLgAECn8vAAIGAAgJnhbNCgCaAQAGAAgJnhbNCgCaAQAAAA==.',
Ae='Aeiox:BAAALgADCgMJAwAAAA==.Aevelman:BAABLgAECn9OAAIHAAkJqSDUAQDMAgAHAAkJqSDUAQDMAgAAAA==.',
Af='Affinty:BAAALgAECgQJBAABLgAFFAcJFgAIAHkbAA==.',
Ag='Ag:BAAALgAFFAEJAgAAAA==.',
Ai='Airphobic:BAABLgAECn8VAAIBAAUJPBvRTQB6AQABAAUJPBvRTQB6AQAAAA==.',
Ak='Akakage:BAAALgAECgEJAQABLgAECggJGQAJACoXAA==.Akakaji:BAABLgAECn8ZAAIJAAgJKhe9PQDRAQAJAAgJKhe9PQDRAQAAAA==.Akutoku:BAAALgADCgcJDAAAAA==.',
Al='Aland:BAAALgADCggJEgAAAA==.Alea:BAABLgAECn8cAAIKAAgJMxxsFACSAgAKAAgJMxxsFACSAgAAAA==.Almodiir:BAAALgADCgUJCQAAAA==.Almoraz:BAAALgAECgUJBQAAAA==.',
An='Anachron:BAAALgADCgIJAgAAAA==.Anaki:BAAALgAECgIJAgAAAA==.Annakkin:BAAALgAECgYJDgAAAA==.Anomander:BAABLgAECn8jAAIJAAYJtQzgogDeAAAJAAYJtQzgogDeAAAAAA==.Anonymoose:BAAALgADCgQJBAAAAA==.',
Ao='Aol:BAAALgADCgUJBQAAAA==.',
Ar='Ar:BAABLgAECn8XAAILAAcJfBDSMgA+AQALAAcJfBDSMgA+AQABLgAFFAQJBgAEAHcPAA==.Aratar:BAAALgAECgMJAwAAAA==.Arbiter:BAAALgAECgUJCQAAAA==.Archon:BAACLgAFFH8FAAMMAAMJOxqaMQCXAAAMAAIJhBmaMQCXAAADAAEJqRviTwBNAAAuAAQKfx4AAwMACAkwHpoXADECAAMACAkwHpoXADECAAwABAnJFfRCALwAAAAA.Argig:BAAALgAFFAEJAQAAAA==.Arienca:BAABLgAECn85AAMNAAkJchBHFgCYAQANAAgJnhBHFgCYAQAHAAkJaAuiXQCGAQAAAA==.Arrogance:BAAALgAECgQJBgABLgAFFAcJEQAOAFIRAA==.Arwenn:BAAALgAECgEJAgAAAA==.',
As='Aspir:BAEALgAECggJCAABLgAFFAgJGQAPAIATAA==.Asu:BAABLgAECn80AAQKAAkJ4RPcJgAZAgAKAAkJ4RPcJgAZAgAQAAcJrRBABwA6AQARAAcJNQjsCwCuAAAAAA==.',
At='At:BAACLgAFFH8GAAIEAAQJdw9/YQAfAQAEAAQJdw9/YQAfAQAuAAQKfxkAAgQABgnKFROoAIkBAAQABgnKFROoAIkBAAAA.',
Au='Aubrey:BAACLgAFFH8NAAIKAAYJpQW2LAACAQAKAAYJpQW2LAACAQAuAAQKfxQAAgoACQlyCqVSAFwBAAoACQlyCqVSAFwBAAAA.',
Av='Avengion:BAABLgAECn8VAAIPAAcJ8wmiGQAFAQAPAAcJ8wmiGQAFAQAAAA==.',
Ba='Baeblade:BAAALgADCgEJAQAAAA==.Balthromaw:BAAALgADCggJDQAAAA==.Barbato:BAAALgADCgYJCQAAAA==.Barbie:BAAALgADCgYJBgAAAA==.',
Be='Beararms:BAAALgADCgcJCAAAAA==.Beav:BAAALgAECgYJBwABLgAFFAYJFQAKAOoaAA==.Beefkeeper:BAAALgAFFAIJAgAAAA==.Beldent:BAAALgAECgQJBwAAAA==.Belöved:BAAALgAECgUJCAABLgAECgkJOgALAPMhAA==.Benelli:BAAALgAECgEJAQAAAA==.Bernard:BAAALgAECgUJBwAAAA==.',
Bi='Bitey:BAAALgAFFAQJBAABLgAFFAgJGAASACIVAA==.',
Bl='Blazegrave:BAABLgAECn89AAITAAkJiR0TAwCyAgATAAkJiR0TAwCyAgABLgAECgkJagAEAA4cAA==.Blazeofglory:BAAALgADCgUJBQABLgAECgkJFwALADwUAA==.Blazerager:BAAALgAECgMJAwABLgAECgkJagAEAA4cAA==.Blazerunner:BAABLgAECn9qAAMEAAkJDhwIBACGAgAEAAkJDhwIBACGAgAUAAEJ7xEvCwA1AAAAAA==.Blazesmasher:BAAALgAECgkJCwABLgAECgkJagAEAA4cAA==.Blitzkreig:BAABLgAECn8bAAITAAkJGRjkMQA3AgATAAkJGRjkMQA3AgAAAA==.Bluefoot:BAABLgAECn8fAAIBAAYJ/AhzfADqAAABAAYJ/AhzfADqAAAAAA==.Blured:BAACLgAFFH8MAAIJAAMJ2hnHJQDmAAAJAAMJ2hnHJQDmAAAuAAQKf0wAAgkACQlwJPsDAEcDAAkACQlwJPsDAEcDAAAA.',
Bo='Booty:BAABLgAECn8oAAICAAkJvCKMBQDhAgACAAkJvCKMBQDhAgAAAA==.',
Br='Brightblayde:BAABLgAECn8gAAIGAAgJEhJDagCaAQAGAAgJEhJDagCaAQAAAA==.Brynhildre:BAABLgAECn8UAAIVAAcJfgtURABmAQAVAAcJfgtURABmAQABLgAFFAYJDQAKAKUFAA==.',
Bu='Buum:BAABLgAECn8XAAICAAkJghaLDQASAgACAAkJghaLDQASAgAAAA==.',
By='Byane:BAAALgADCgYJBgAAAA==.',
['Bä']='Bämba:BAAALgAECgMJAwABLgAECgkJKwAEABoQAA==.',
Ca='Cachelyn:BAAALgAECgYJEgAAAA==.Calerus:BAAALgADCgkJCQAAAA==.Cali:BAACLgAFFH8oAAIJAAkJxxtODwA8AgAJAAkJxxtODwA8AgAuAAQKfy4AAgkACAmkIeQSAOgCAAkACAmkIeQSAOgCAAAA.Cantouchthes:BAABLgAECn8UAAIEAAgJZB7ERAANAgAEAAgJZB7ERAANAgAAAA==.Captnage:BAAALgADCggJCAAAAA==.Carafe:BAAALgAECgUJDAABLgAECgkJBgAWAAAAAA==.',
Ce='Cederred:BAAALgAECgUJBQABLgAECggJCgAWAAAAAA==.Cedertree:BAAALgADCgcJBwABLgAECggJCgAWAAAAAA==.Celline:BAAALgADCgEJAQAAAA==.Cephus:BAABLgAFFH8QAAIKAAcJPBRAEQDtAQAKAAcJPBRAEQDtAQAAAA==.Cerafina:BAAALgADCgEJAQAAAA==.',
Ch='Chayse:BAABLgAFFH8FAAIXAAQJZAg/XADsAAAXAAQJZAg/XADsAAABLgAFFAYJDQAKAKUFAA==.Choom:BAABLgAECn8fAAMKAAkJuhUONgDQAQAKAAkJuhUONgDQAQAQAAYJjRPrLgCOAQAAAA==.Chorizo:BAAALgADCgEJAQAAAA==.Christhina:BAAALgADCgQJBAAAAA==.Chronocide:BAACLgAFFH8SAAIYAAQJmB1qGgBIAQAYAAQJmB1qGgBIAQAuAAQKfyoAAhgACQnbHxEQAKkCABgACQnbHxEQAKkCAAAA.Chronophasia:BAABLgAECn8jAAMGAAgJHSFIHQCWAgAGAAgJFSFIHQCWAgAZAAQJfBtoJADyAAAAAA==.Chroños:BAABLgAECn8UAAMaAAcJEA85FADKAAAbAAcJ6g0BSAALAQAaAAQJZw45FADKAAAAAA==.Chumléé:BAAALgADCgQJBAAAAA==.Chérry:BAACLgAFFH8jAAIJAAgJVhpaEAAxAgAJAAgJVhpaEAAxAgAuAAQKfyAAAgkACQlsIowQAPoCAAkACQlsIowQAPoCAAAA.',
Ci='Ciri:BAAALgAFFAIJAwAAAA==.',
Cl='Climpwimp:BAAALgAECgIJAgAAAA==.Cluntasaur:BAAALgAECgUJBgABLgAFFAIJAwAWAAAAAA==.',
Co='Connerr:BAABLgAECn8aAAIKAAgJtBorLwDnAQAKAAgJtBorLwDnAQAAAA==.Contendor:BAAALgAECgkJCQAAAA==.Cowage:BAAALgAECgQJCQAAAA==.',
Cr='Crisse:BAAALgAECgUJCgAAAA==.Croh:BAABLgAECn8aAAMTAAgJpBNfVAD0AQATAAgJpBNfVAD0AQAPAAQJawb3DwCcAAAAAA==.Crucks:BAAALgADCgQJBAAAAA==.Cruknar:BAABLgAFFH8KAAIcAAUJ5xS0BQA7AQAcAAUJ5xS0BQA7AQAAAA==.',
Cu='Curita:BAAALgADCgEJAQAAAA==.',
Cy='Cynestra:BAABLgAECn8XAAIVAAkJHRMQHQAbAgAVAAkJHRMQHQAbAgAAAA==.Cytheris:BAAALgAECgEJAQABLgAECggJGgAKALQaAA==.',
Da='Daddio:BAEALgAECgQJBAABLgADCgcJBwAWAAAAAA==.Dadudadu:BAACLgAFFH8nAAIGAAgJ6hC+DwDyAQAGAAgJ6hC+DwDyAQAuAAQKfzQAAgYACQkZIHoWAOICAAYACQkZIHoWAOICAAAA.Daffo:BAAALgAECgIJAQAAAA==.Daftmonk:BAACLgAFFH8mAAIdAAgJmSCcAQB6AgAdAAgJmSCcAQB6AgAuAAQKfywAAh0ACQmSJbECAG8DAB0ACQmSJbECAG8DAAAA.Daitanfuteki:BAAALgADCgEJAQABLgAFFAQJCAAeAOcVAA==.Dalan:BAAALgAECgEJAQAAAA==.Darkfyre:BAAALgADCgEJAgAAAA==.Darks:BAAALgAECgIJAgAAAA==.Darkwingfish:BAABLgAECn8pAAIJAAkJrRSlRgCzAQAJAAkJrRSlRgCzAQAAAA==.Darmonevil:BAAALgADCgEJAQAAAA==.Dartran:BAAALgADCgIJBwAAAA==.Dasarus:BAABLgAECn8ZAAMOAAgJsxprEAAhAgAOAAgJsxprEAAhAgAJAAYJWw9EkQD+AAAAAA==.Dayman:BAABLgAECn8UAAMZAAcJgwIdNACSAAAZAAcJXAIdNACSAAAGAAYJ0gFTSAFkAAAAAA==.',
De='Decày:BAAALgAECgcJEAAAAA==.Defknight:BAAALgADCgcJBwAAAA==.Demoteck:BAAALgAECgQJBgAAAA==.Demy:BAAALgADCgYJBgAAAA==.Deredris:BAAALgAECgEJAQAAAA==.Deth:BAAALgAECgIJAgABLgAECgMJDAAWAAAAAA==.Dethblow:BAAALgAECgMJDAAAAA==.',
Di='Disconnects:BAAALgADCgUJBQAAAA==.Dium:BAAALgAECgEJAQAAAA==.Diwa:BAACLgAFFH8FAAIBAAUJ5QG+PgDpAAABAAUJ5QG+PgDpAAAuAAQKfxkAAwEACQn8BthsABUBAAEACQn8BthsABUBABgABglJB+BRAP8AAAAA.',
Dk='Dklot:BAACLgAFFH8MAAITAAUJJBSFcAAeAQATAAUJJBSFcAAeAQAuAAQKfxgAAxMABwlZHI53AHUBABMABwlZHI53AHUBAA8AAQn1DK48AC0AAAAA.',
Dr='Dracthfear:BAAALgAECgYJBwABLgAFFAgJIQAHAB8gAA==.Dragolot:BAAALgADCgQJBAABLgAFFAUJDAATACQUAA==.Draken:BAAALgAECgEJAQAAAA==.Draviin:BAABLgAECn8xAAIXAAkJ9x0hIQBiAgAXAAkJ9x0hIQBiAgAAAA==.',
Du='Duckcheese:BAAALgADCgEJAQAAAA==.Dunkyn:BAABLgAFFH8JAAIPAAYJshbkAwChAQAPAAYJshbkAwChAQAAAA==.Durzoblint:BAAALgAECgUJCAAAAA==.',
Dy='Dyemon:BAAALgADCgIJAgAAAA==.',
['Dé']='Déad:BAAALgADCgcJDAAAAA==.',
El='Elementz:BAAALgAECgIJAgAAAA==.Elerae:BAABLgAECn8nAAIGAAkJ+hthFgDjAgAGAAkJ+hthFgDjAgAAAA==.Eleshkigal:BAABLgAECn8oAAMJAAkJ1yaKAwCTAwAJAAkJ1yaKAwCTAwAfAAQJiBoiEgAsAQAAAA==.',
En='Enkeke:BAACLgAFFH8NAAITAAMJphHARQDJAAATAAMJphHARQDJAAAuAAQKfz4AAhMACQlNHcElAG0CABMACQlNHcElAG0CAAAA.',
Er='Eresanna:BAABLgAFFH8PAAIEAAQJpQyeZwAUAQAEAAQJpQyeZwAUAQAAAA==.Ereshkigal:BAAALgAECgUJBgAAAA==.',
Es='Esdeath:BAAALgAFFAEJAQABLgAFFAcJEQAOAFIRAA==.Estus:BAABLgAECn8VAAMVAAgJNhfbKgC5AQAVAAgJNhfbKgC5AQAGAAIJ1gmSfwE9AAAAAA==.',
Ex='Extremefear:BAABLgAECn84AAMNAAkJbBe/FAAHAQAHAAUJbxUrdQBPAQANAAYJ8RW/FAAHAQAAAA==.',
Fa='Fatima:BAAALgAECgIJAwAAAA==.',
Fe='Fearious:BAACLgAFFH8hAAQHAAgJHyDyEgCPAQAHAAcJqSPyEgCPAQASAAIJYSZZEwBwAAANAAEJpgjmDwBMAAAuAAQKfyYABAcACAlBJkYvABsCAAcABwk3JEYvABsCAA0AAwl7JTUZANkAABIAAQncI6wsAGkAAAAA.Felphetamine:BAAALgADCggJCAAAAA==.Fenrisfangs:BAABLgAECn8VAAIXAAkJSA6jVACmAQAXAAkJSA6jVACmAQAAAA==.Fenrisul:BAAALgAECgUJBQAAAA==.Feralshunter:BAACLgAFFH8IAAIeAAQJ5xWhFwD9AAAeAAQJ5xWhFwD9AAAuAAQKfzIAAh4ACQkAIZcQALcCAB4ACQkAIZcQALcCAAAA.Feroond:BAAALgADCgQJBAAAAA==.',
Fi='Fingeritout:BAAALgADCgIJAgAAAA==.Firefly:BAAALgAECgMJAwAAAA==.',
Fl='Florea:BAAALgADCggJDAAAAA==.',
Fo='Fodurzind:BAAALgAECgEJAQAAAA==.Forfoxsake:BAABLgAECn8kAAIgAAgJmR/nEQAoAgAgAAgJmR/nEQAoAgAAAA==.',
Fr='Frogteeth:BAAALgADCgUJBQAAAA==.',
Fu='Furibeav:BAABLgAFFH8VAAIKAAYJ6hpnEgDfAQAKAAYJ6hpnEgDfAQAAAA==.Furrow:BAAALgAECgQJBAAAAA==.Furrów:BAAALgAECgUJBwAAAA==.',
['Fû']='Fûrrow:BAAALgAECgcJEAAAAA==.',
Ga='Gallindral:BAABLgAECn9DAAIJAAkJFB5RFQCYAgAJAAkJFB5RFQCYAgAAAA==.Garanda:BAAALgAECgQJBQAAAA==.Gargantuan:BAAALgADCgMJAwAAAA==.Garreth:BAAALgAECgUJBQAAAA==.Gatito:BAAALgAECgEJAQABLgAECgIJAgAWAAAAAA==.Gauthus:BAAALgAECgkJCgAAAA==.',
Ge='Genericnpc:BAABLgAECn8eAAQMAAgJvA+rIwBHAQAMAAgJ7QyrIwBHAQADAAYJVw0hVgD1AAACAAEJfxOeUQA3AAAAAA==.Geobrando:BAACLgAFFH8JAAMBAAMJbBdDIwC7AAABAAMJbBdDIwC7AAAYAAEJzQ1jVQA+AAAuAAQKfz4AAwEACQlOIG0LAMcCAAEACQlOIG0LAMcCABgABgm8HaknAK8BAAAA.',
Gg='Ggbrews:BAACLgAFFH8xAAIGAAgJKh2cDAAVAgAGAAgJKh2cDAAVAgAuAAQKf7gABAYACQlyJqUBAH8DAAYACQlyJqUBAH8DABUACAn5HQoNAMACABkABwm6DIoKAJwAAAAA.',
Gh='Ghostblaze:BAAALgAECgUJDwABLgAECgkJagAEAA4cAA==.',
Gi='Gier:BAAALgADCgUJBQAAAA==.Gino:BAAALgADCgEJAQAAAA==.',
Gl='Glacialwrait:BAAALgAECgIJBAAAAA==.Glacious:BAAALgADCgEJAQAAAA==.Glasswings:BAAALgAECgIJAgAAAA==.',
Gn='Gnosh:BAABLgAECn8aAAIQAAkJbxT0GQD8AQAQAAkJbxT0GQD8AQAAAA==.Gnova:BAABLgAECn8jAAIEAAYJfSG9YgC5AQAEAAYJfSG9YgC5AQAAAA==.',
Go='Gorian:BAAALgAECgcJCAAAAA==.',
Gr='Gregorz:BAAALgADCgEJAQAAAA==.Grish:BAAALgAECgEJAQAAAA==.',
Gu='Guidosarduci:BAABLgAECn8zAAIBAAgJjxt9BgDWAQABAAgJjxt9BgDWAQAAAA==.',
Ha='Hairia:BAAALgADCgUJBQAAAA==.Halen:BAAALgADCgkJEAABLgAFFAkJKAAJAMcbAA==.Hardone:BAAALgAECggJDwAAAA==.Harle:BAABLgAECn8bAAIEAAkJmheMMABXAgAEAAkJmheMMABXAgAAAA==.Hatari:BAAALgAECgMJAwAAAA==.',
He='Hektate:BAABLgAECn8WAAIEAAcJXQvbsgAdAQAEAAcJXQvbsgAdAQABLgAFFAgJJwAGAOoQAA==.Henryjones:BAAALgADCgEJAQAAAA==.',
Hi='Hikari:BAACLgAFFH8FAAIGAAMJNBwXlwCIAAAGAAMJNBwXlwCIAAAuAAQKfx0AAgYACAleI0oJALoBAAYACAleI0oJALoBAAEuAAUUBwkzABgAWx4A.Hilkesad:BAAALgAECgQJBAAAAA==.Hizo:BAAALgADCgUJBQAAAA==.',
Ho='Holybeave:BAABLgAECn8eAAMLAAkJNB3/DACFAgAhAAkJaBi5CQCfAgALAAgJqx7/DACFAgABLgAFFAYJFQAKAOoaAA==.Holyshortguy:BAAALgAECgYJEAABLgAFFAcJEgAiACANAA==.Hoofer:BAAALgAECgYJDgAAAA==.',
Hu='Hunkomeat:BAABLgAECn8XAAIDAAgJLhzkLAAAAgADAAgJLhzkLAAAAgAAAA==.',
['Hë']='Hënry:BAAALgAECgEJAQAAAA==.',
Ic='Icelmo:BAABLgAFFH8PAAIDAAUJIhX9GQBKAQADAAUJIhX9GQBKAQAAAA==.',
Ih='Ihotyou:BAAALgADCgQJBwAAAA==.',
Ik='Ikeyni:BAAALgAECgEJAQAAAA==.',
Il='Ilikeitrough:BAAALgAECgYJCgAAAA==.',
Im='Impact:BAAALgAECgYJBwABLgAFFAcJMwAYAFseAA==.',
In='Inai:BAAALgADCgcJDAABLgAFFAcJEQAOAFIRAA==.Invizww:BAAALgAECgQJBQAAAA==.',
Ir='Ircapslock:BAAALgAECgYJDgAAAA==.',
Iv='Ivorypal:BAABLgAECn8gAAIVAAgJqR/dEACLAgAVAAgJqR/dEACLAgAAAA==.',
Ja='Jackfrost:BAAALgAECgMJAQAAAA==.Jacksock:BAAALgADCgEJAQAAAA==.Jamzz:BAAALgAECgQJBQABLgAFFAgJIQAeAMsQAA==.Jaromir:BAAALgADCgcJBwAAAA==.Jaskow:BAABLgAECn8uAAIKAAkJjiD/BwA4AwAKAAkJjiD/BwA4AwAAAA==.Jaymick:BAABLgAECn8aAAMXAAkJYhEVbgBlAQAcAAcJEQ6aIwCBAQAXAAcJjRIVbgBlAQAAAA==.',
Jb='Jbizzler:BAAALgAECgcJBgAAAA==.',
Jc='Jcrypt:BAAALgAECgcJAgAAAA==.',
Je='Jennika:BAABLgAFFH8GAAIcAAMJjwcvIgDIAAAcAAMJjwcvIgDIAAAAAA==.Jernau:BAAALgAECgEJAQAAAA==.Jessortess:BAAALgAECgQJBwAAAA==.',
Jo='Johnwicksdog:BAAALgAECggJEQAAAA==.Jorbies:BAAALgAECgYJCQABLgAFFAcJFgAIAHkbAA==.Jorls:BAACLgAFFH8WAAMIAAcJeRtMAgDeAQAIAAcJeRtMAgDeAQAhAAEJWAEnGwBDAAAuAAQKfxsABAgACQkFHlMIAP8CAAgACQkFHlMIAP8CACEABAnSCc08AMQAAAsAAglAAgl2AFEAAAAA.',
Ju='Junatooka:BAAALgAECgIJAgAAAA==.Jusdatip:BAAALgAECgUJDwAAAA==.',
Ka='Kaelthazed:BAAALgADCgEJAQABLgAFFAMJCgAHAB8WAA==.Kalfu:BAABLgAECn8XAAMXAAgJ0B1jPQDrAQAXAAgJ0B1jPQDrAQAeAAYJoBUDOgB5AQAAAA==.Kameshoga:BAAALgAECgIJAgAAAA==.Kammwin:BAAALgAECgYJEwAAAA==.Karten:BAAALgAECgcJEQAAAA==.Kaylea:BAAALgADCgIJAgAAAA==.',
Ke='Kellandria:BAAALgADCgcJFgAAAA==.',
Ki='Kieraleah:BAAALgAECgcJBwAAAA==.Killjoyss:BAAALgAFFAIJAwAAAA==.Kittêh:BAAALgAECgEJAQAAAA==.',
Kn='Knathor:BAAALgAECgQJBgABLgAECgcJDgAWAAAAAA==.',
Ko='Korec:BAAALgAECgcJDgAAAA==.',
Kr='Krag:BAAALgAFFAEJAQABLgAFFAMJCAAgAPoUAA==.Krasis:BAABLgAECn8XAAIGAAkJvhrLWADYAQAGAAkJvhrLWADYAQAAAA==.Krazermonk:BAACLgAFFH8PAAIdAAUJmxoBEAA9AQAdAAUJmxoBEAA9AQAuAAQKfygAAh0ACQmlHrMOAF4CAB0ACQmlHrMOAF4CAAAA.Kriplethreat:BAAALgADCgMJAwAAAA==.Krispinwah:BAACLgAFFH8HAAITAAMJWRiDXACWAAATAAMJWRiDXACWAAAuAAQKfxoAAhMACQleHpsPAO8CABMACQleHpsPAO8CAAEuAAUUAwkJAAEAbBcA.Kristysavage:BAACLgAFFH8KAAIXAAMJaB6wKAD3AAAXAAMJaB6wKAD3AAAuAAQKfysAAhcACQliI3oIABYDABcACQliI3oIABYDAAAA.Kroflavinof:BAAALgAECgUJCgAAAA==.',
Ku='Kurosakí:BAAALgAECgEJAQAAAA==.',
Ky='Kyle:BAAALgAECgIJAgABLgAFFAQJGgAGAHYjAA==.',
La='Lagoon:BAAALgAECgIJAwAAAA==.Lanc:BAAALgAECgQJCQAAAA==.Lappytopdog:BAAALgAECgcJDAAAAA==.Larradin:BAAALgADCggJEAAAAA==.Lawnchair:BAAALgAECggJDgAAAA==.',
Le='Lealta:BAAALgAFFAEJAgABLgAFFAgJIwAhANofAA==.Leonus:BAAALgAECgQJCQAAAA==.Leviathahn:BAAALgAECgEJAgAAAA==.',
Lh='Lhegholhaz:BAAALgADCgIJAgAAAA==.',
Li='Lichdawg:BAACLgAFFH8aAAMPAAcJEBCLBwB1AQAPAAYJEBCLBwB1AQAjAAEJAAAFYQAAAAAuAAQKfxQAAg8ACAnSE9sOAIcBAA8ACAnSE9sOAIcBAAAA.Lilzayna:BAAALgAECgEJAQABLgAFFAIJAwAWAAAAAA==.Lindianda:BAAALgAECgYJBgAAAA==.Linthori:BAEALgADCgMJAwABLgAECgcJDQAWAAAAAA==.Lirrin:BAAALgAECgIJAgAAAA==.Lithlia:BAAALgADCggJDQAAAA==.Livvela:BAABLgAECn8rAAIkAAkJDhb0FgDlAQAkAAkJDhb0FgDlAQAAAA==.',
Ll='Llas:BAAALgADCgIJAgAAAA==.',
Lo='Lockdawg:BAACLgAFFH8lAAIHAAcJLBrcEgCRAQAHAAcJLBrcEgCRAQAuAAQKfyYAAwcACAmFHRImAHoCAAcACAmFHRImAHoCAA0AAQnWFc1sADoAAAAA.Lockedin:BAAALgAECgkJEgAAAA==.Lonne:BAAALgAECgYJDgABLgAFFAIJBAAWAAAAAA==.Lover:BAABLgAECn86AAILAAkJ8yGwDACbAgALAAkJ8yGwDACbAgAAAA==.',
Lu='Lubu:BAACLgAFFH8RAAIOAAcJUhFyCQBxAQAOAAcJUhFyCQBxAQAuAAQKfxoAAg4ACQn+H2AFAOsCAA4ACQn+H2AFAOsCAAAA.Lucianis:BAAALgADCgQJBwAAAA==.Luckycharmz:BAAALgAECgQJCQABLgAFFAIJDwAhAJUJAA==.Luckywar:BAAALgADCgYJBgAAAA==.Luell:BAAALgAECgcJDwAAAA==.Luev:BAAALgAECgYJCAAAAA==.Lumiette:BAABLgAECn8WAAMCAAcJ2RrDEQDOAQACAAcJ2RrDEQDOAQADAAMJFAvChQCoAAAAAA==.',
Ly='Lynai:BAABLgAECn8dAAIEAAkJPxLFcQCWAQAEAAkJPxLFcQCWAQAAAA==.',
['Lá']='Lándwhale:BAACLgAFFH8YAAIkAAQJxSNsEwBxAQAkAAQJxSNsEwBxAQAuAAQKfy4AAiQACQmTJFoEAPgCACQACQmTJFoEAPgCAAAA.',
['Lö']='Löver:BAAALgAECgcJDQABLgAECgkJOgALAPMhAA==.',
Ma='Mabil:BAABLgAECn8UAAQHAAcJRhJ1mgAIAQAHAAYJew11mgAIAQASAAQJXRWcGAC2AAANAAIJNAydQgAoAAAAAA==.Macktimus:BAABLgAECn8gAAINAAkJYBhQBQAdAgANAAkJYBhQBQAdAgAAAA==.Madeinchina:BAAALgADCgEJAQAAAA==.Mage:BAAALgAFFAEJAgAAAA==.Magictonyp:BAABLgAECn8UAAIEAAUJ/Qe39wC5AAAEAAUJ/Qe39wC5AAAAAA==.Magicznstuff:BAAALgAECgQJBQABLgAFFAYJCQAPALIWAA==.Magna:BAABLgAECn8lAAIDAAkJYRIuKQC0AQADAAkJYRIuKQC0AQAAAA==.Magnusbane:BAAALgAECgYJCQAAAA==.Makili:BAABLgAFFH8dAAIEAAYJthhhHgBsAQAEAAYJthhhHgBsAQAAAA==.Maladrix:BAAALgAECgQJDQAAAA==.Marltonder:BAAALgADCgIJAgAAAA==.Mauê:BAAALgADCgEJAQABLgAECgIJAgAWAAAAAA==.',
Mc='Mcfire:BAAALgADCgIJAgAAAA==.Mchealer:BAAALgAECgUJCgAAAA==.Mchunter:BAAALgAECgMJAwAAAA==.Mcshadow:BAAALgADCgIJAgAAAA==.',
Me='Melotte:BAAALgAECgkJBgAAAA==.Menphina:BAAALgAECgIJAgABLgAECgkJOgALAPMhAA==.Merigold:BAAALgAECgEJAQABLgAECgQJBAAWAAAAAA==.Merlynin:BAAALgAECgEJAQABLgAECgkJMQAXAPcdAA==.',
Mi='Mickallv:BAAALgAECgMJBQAAAA==.Midevilz:BAAALgAECgQJBAAAAA==.Minnow:BAAALgAECgYJDgAAAA==.Mintchip:BAABLgAECn8QAAIJAAcJ3RdQSwCkAQAJAAcJ3RdQSwCkAQAAAA==.',
Mo='Monk:BAAALgAECgEJAQAAAA==.Monza:BAAALgADCgEJAQABLgAECgkJKAAEAOsWAA==.Moontini:BAAALgADCgcJBwABLgAECgQJDQAWAAAAAA==.Mordryn:BAAALgADCgcJBwAAAA==.',
Mu='Murad:BAABLgAFFH8JAAITAAQJsxAALwANAQATAAQJsxAALwANAQAAAA==.',
My='Mysternia:BAABLgAECn8VAAILAAgJ2w7EMwA3AQALAAgJ2w7EMwA3AQAAAA==.Myyagie:BAAALgADCgcJEQAAAA==.',
Na='Nalthexon:BAABLgAECn8qAAMiAAgJ2wtFMQAzAQAiAAgJ2wtFMQAzAQAdAAEJXQaerQAmAAABLgAFFAMJBgAKAHUGAA==.Natureborne:BAAALgAECgYJCQAAAA==.',
Ne='Nedrud:BAAALgADCgUJCAAAAA==.Nelson:BAEALgAECgYJCAABLgAECgkJLQAEAFEeAA==.Nenno:BAAALgADCgEJAQAAAA==.Netzhul:BAAALgAFFAEJAQAAAA==.',
Ni='Night:BAAALgAECgcJEQAAAA==.Nikalos:BAAALgAECgYJDQAAAA==.Nikole:BAAALgAECgMJAwAAAA==.',
No='Noon:BAAALgADCgUJBQABLgAECggJFQAVADYXAA==.Notorckrag:BAACLgAFFH8IAAIgAAMJ+hTaDwDNAAAgAAMJ+hTaDwDNAAAuAAQKf0AAAiAACQmSIx4DACIDACAACQmSIx4DACIDAAAA.Nozomi:BAABLgAECn8YAAIJAAkJ0QZwGgCjAAAJAAkJ0QZwGgCjAAAAAA==.',
Nu='Nut:BAAALgADCgQJBAAAAA==.',
['Nê']='Nêz:BAAALgAECgUJCAAAAA==.',
Oa='Oathbringer:BAAALgAECgQJBAAAAA==.',
Ob='Oblivionz:BAAALgAECgMJAwAAAA==.',
Oc='Ocho:BAAALgADCgYJCQAAAA==.',
Of='Offbrandcleo:BAAALgAECgkJBgAAAA==.',
Ok='Okibi:BAAALgAECgMJBQABLgAFFAcJEQAOAFIRAA==.',
Ol='Oldrecipe:BAABLgAFFH8NAAIVAAUJ5RfVIwACAQAVAAUJ5RfVIwACAQAAAA==.Oliange:BAABLgAECn8rAAIEAAgJGhAFcgCWAQAEAAgJGhAFcgCWAQAAAA==.',
Or='Ori:BAEALgADCgcJCwABLgAECgcJDQAWAAAAAA==.Originalgank:BAACLgAFFH8VAAIEAAUJgB0CRwBXAQAEAAUJgB0CRwBXAQAuAAQKfyYAAgQACQkHJNcGAEkDAAQACQkHJNcGAEkDAAAA.',
Oz='Ozzi:BAAALgAECgMJAwAAAA==.',
Pa='Papanell:BAAALgADCgYJCQAAAA==.',
Pe='Peachcobbler:BAAALgAECggJDgAAAA==.Perc:BAAALgAECgcJEAAAAA==.',
Ph='Philsner:BAEALgAECgcJDQAAAA==.Phink:BAAALgAECgQJCgAAAA==.',
Pi='Pinkk:BAABLgAECn8XAAIXAAkJ/xxXGgCHAgAXAAkJ/xxXGgCHAgAAAA==.',
Pl='Plushie:BAABLgAECn8nAAIIAAgJugt3MABcAQAIAAgJugt3MABcAQAAAA==.',
Po='Pong:BAABLgAECn8YAAMFAAgJ3xl6DgDJAQAFAAcJgRl6DgDJAQABAAIJdhUvLQBEAAABLgAFFAIJCAAbAM8HAA==.Pooqy:BAACLgAFFH8QAAMTAAUJ4SRFOQCJAQATAAQJ4SRFOQCJAQAjAAEJAAC3SQAAAAAuAAQKfxYAAhMACAlWIrskAKsCABMACAlWIrskAKsCAAAA.Porcel:BAAALgADCgcJCwAAAA==.Potatoteng:BAABLgAFFH8KAAIPAAUJ1AtRCAAOAQAPAAUJ1AtRCAAOAQABLgAFFAcJDwAGAOEUAA==.Pozidrive:BAAALgAECgIJAgAAAA==.',
Pr='Pritej:BAAALgAECgYJCgABLgAFFAIJBAAWAAAAAA==.Proto:BAAALgAECgcJDAAAAA==.',
Pu='Puck:BAAALgAFFAIJAwABLgAFFAcJEQAOAFIRAA==.Pulu:BAAALgAFFAEJAQABLgAFFAMJBgAIALgUAA==.',
Py='Pyraleus:BAAALgADCgQJBAAAAA==.',
Qm='Qmpell:BAAALgADCgYJBgAAAA==.',
Qu='Quickchicken:BAAALgAECgIJBgAAAA==.',
Ra='Ragel:BAACLgAFFH8FAAIQAAIJjxvXNgCiAAAQAAIJjxvXNgCiAAAuAAQKfzgAAhAACQn3IA8GAPcCABAACQn3IA8GAPcCAAAA.Rahor:BAAALgAECgEJAQAAAA==.Rainesage:BAABLgAECn80AAMIAAkJlB1qDQB9AgAIAAkJlB1qDQB9AgALAAEJxwcneAAiAAAAAA==.Ralphel:BAABLgAECn8qAAIGAAgJMwcJsAAfAQAGAAgJMwcJsAAfAQAAAA==.Rasmon:BAAALgAECggJCAAAAA==.Rasu:BAAALgADCgcJBwABLgAECggJGgAlALUMAA==.Ravendark:BAAALgAECgEJAQAAAA==.Rayozap:BAAALgAECgUJBgAAAA==.',
Re='Redeye:BAAALgADCgMJAwAAAA==.Relock:BAAALgAECgMJAwABLgAECggJGgAKALQaAA==.',
Rh='Rhondaa:BAAALgAECgYJEQAAAA==.Rhubarb:BAABLgAECn8/AAMMAAkJjiZFAQBcAwAMAAgJIiZFAQBcAwADAAgJoyRkDQCXAgAAAA==.',
Ri='Ripley:BAAALgAFFAEJAQAAAA==.Riptidepods:BAAALgAECgEJAQAAAA==.Riyci:BAAALgAECgEJAQAAAA==.',
Ro='Rohiem:BAACLgAFFH8IAAIDAAUJTwh2KAByAAADAAUJTwh2KAByAAAuAAQKfz0AAgMACQmjHXMEAK8BAAMACQmjHXMEAK8BAAAA.',
Ry='Ryan:BAABLgAECn8eAAIGAAkJZR4ZHADBAgAGAAkJZR4ZHADBAgAAAA==.Rylorthas:BAACLgAFFH8gAAMLAAcJdhNfCQC3AQALAAcJdhNfCQC3AQAhAAEJ5wQUMwAsAAAuAAQKfy0AAgsACQl8HMsSAEoCAAsACQl8HMsSAEoCAAAA.Rylosh:BAAALgAFFAEJAQABLgAFFAcJIAALAHYTAA==.',
['Rî']='Rîkku:BAAALgADCgkJGQAAAA==.',
Sa='Sabot:BAABLgAECn8bAAMmAAkJVRvdBwBWAgAmAAkJVRvdBwBWAgARAAQJmwpgTAB5AAAAAA==.Sabrook:BAAALgADCggJCAAAAA==.Salazar:BAAALgAECgEJAwAAAA==.Sam:BAAALgAECgUJBAAAAA==.Sandalhat:BAAALgAECgEJAgAAAA==.Sanll:BAAALgAECgcJCAAAAA==.Satisfied:BAABLgAECn8VAAILAAUJRhyNKACCAQALAAUJRhyNKACCAQAAAA==.',
Sc='Scottmonk:BAAALgAECgIJBQAAAA==.Scottpaladin:BAAALgAECgEJAQABLgAECgIJBQAWAAAAAA==.',
Se='Seath:BAAALgAECggJEQABLgAFFAMJCgAHAB8WAA==.Sentaí:BAAALgAECgIJBAAAAA==.',
Sh='Shamantics:BAAALgAECgIJAwABLgAFFAgJIQAHAB8gAA==.Shamerica:BAACLgAFFH8cAAMFAAkJzBxcAQAXAgAFAAcJWiBcAQAXAgAYAAMJYBO0KABjAAAuAAQKfz4AAwUACQkyJKABABkDAAUACQn2IqABABkDABgACAnNI9QIANACAAAA.Shizuku:BAAALgADCgUJBQAAAA==.Shmooythefox:BAABLgAECn8lAAIXAAcJfCG3NgADAgAXAAcJfCG3NgADAgAAAA==.Shokan:BAAALgADCgQJBAAAAA==.Shortleedin:BAAALgAECgIJAQAAAA==.Shòckwave:BAAALgADCgQJBAAAAA==.',
Si='Sinrex:BAAALgADCgUJBwAAAA==.Sixstar:BAAALgADCgEJAQAAAA==.',
Sk='Skeetcream:BAAALgAECgIJAgABLgAECgUJBwAWAAAAAA==.Skrt:BAAALgAECgMJAwAAAA==.Skyleax:BAACLgAFFH8KAAMTAAQJdg05fgAKAQATAAQJdg05fgAKAQAPAAEJwAL4LAA1AAAuAAQKfxgABBMACQkSIEYuAH8CABMACQnoHEYuAH8CAA8ABAkVHkUMAPAAACMAAQn7D0ZLACAAAAAA.',
Sl='Slagothor:BAABLgAECn8VAAITAAkJywRnmQBNAQATAAkJywRnmQBNAQAAAA==.Slanesh:BAAALgAECgcJDwABLgAECgcJEAAJAN0XAA==.Sleaze:BAAALgADCgEJAQAAAA==.Sleazus:BAAALgAECgMJAwAAAA==.',
Sm='Smeesha:BAABLgAECn8nAAQlAAgJ3RgAEADLAQAlAAcJDxoAEADLAQAaAAYJRQcGJgDzAAAbAAYJyAehRgDBAAAAAA==.',
Sn='Snaxwell:BAAALgADCgEJAQAAAA==.',
So='Somin:BAAALgAECgMJBAAAAA==.',
Sp='Specialedz:BAAALgADCgUJBwAAAA==.Spekaleks:BAAALgADCgUJBwAAAA==.Spiritbox:BAAALgAECgYJBgAAAA==.',
Sq='Squitwurt:BAAALgADCgYJBgAAAA==.',
St='Starbae:BAAALgAECgMJBAABLgAFFAIJDwAhAJUJAA==.Starbux:BAABLgAECn8dAAMZAAgJchBmFwBlAQAZAAgJchBmFwBlAQAVAAEJewNqnQAjAAABLgAFFAIJDwAhAJUJAA==.Starbuxx:BAAALgAECgUJCQABLgAFFAIJDwAhAJUJAA==.Starbúcks:BAAALgAECgIJAwABLgAFFAIJDwAhAJUJAA==.Steppers:BAAALgAECgUJAgAAAA==.Straamm:BAAALgADCgMJAwAAAA==.',
Su='Sugarr:BAAALgAECgEJAQAAAA==.Sunfish:BAAALgAECgYJCgAAAA==.',
Sv='Svelana:BAABLgAECn8lAAMdAAgJjSJ6DgBhAgAdAAgJjSJ6DgBhAgAiAAEJCgthxgAlAAAAAA==.',
Sy='Syb:BAABLgAECn8bAAQbAAkJZxdLGgAEAgAbAAkJlhVLGgAEAgAaAAQJ4hlAEgDmAAAlAAEJFwU3SwArAAAAAA==.Sylphrena:BAACLgAFFH8TAAIIAAUJgyAAEABtAQAIAAUJgyAAEABtAQAuAAQKfykAAggACQnSIscGAOUCAAgACQnSIscGAOUCAAAA.Syssana:BAAALgAECgIJBgAAAA==.',
Ta='Tadaa:BAAALgADCgIJAgAAAA==.Tamerlein:BAAALgAECgMJBQAAAA==.Tamioka:BAAALgAECgYJCAAAAA==.Tanookii:BAAALgAECgYJEwAAAA==.',
Th='Theinsider:BAACLgAFFH8KAAIHAAMJHxYXLgDLAAAHAAMJHxYXLgDLAAAuAAQKf0QAAwcACQkDImUOANoCAAcACQkDImUOANoCAA0ABQmQD6crABEBAAAA.Thenezath:BAAALgAECgYJCQAAAA==.Theoutsider:BAABLgAFFH8GAAITAAMJxxDHRgDGAAATAAMJxxDHRgDGAAABLgAFFAMJCgAHAB8WAA==.Thunrus:BAAALgADCgYJBgAAAA==.',
Ti='Tibbles:BAAALgAECgcJCAAAAA==.Tigerbait:BAABLgAECn8WAAInAAYJOhGsAQAOAQAnAAYJOhGsAQAOAQAAAA==.Tindril:BAAALgAECgYJBwAAAA==.Tinymo:BAAALgAECgMJAwAAAA==.',
To='Toeknees:BAAALgAECgIJAwAAAA==.Toekneess:BAAALgAECgEJAQABLgAECgIJAwAWAAAAAA==.Toekneezz:BAAALgAECgEJAgABLgAECgIJAwAWAAAAAA==.Toji:BAABLgAECn8WAAIIAAcJ+hj7IQC3AQAIAAcJ+hj7IQC3AQABLgAFFAcJMwAYAFseAA==.Tomatoteng:BAACLgAFFH8PAAIGAAcJ4RTGEwDMAQAGAAcJ4RTGEwDMAQAuAAQKfyAAAgYACQmPJH4DAJsDAAYACQmPJH4DAJsDAAAA.Totegoat:BAAALgADCgEJAQAAAA==.Totemmalotes:BAAALgADCgcJBwAAAA==.Totemofbear:BAABLgAECn8oAAImAAkJFhYvCgAeAgAmAAkJFhYvCgAeAgAAAA==.',
Tr='Trandis:BAAALgADCgMJBAABLgAECgkJKAAJANcmAA==.Tranza:BAABLgAECn8cAAQcAAgJOw3ZIwB/AQAcAAgJcgrZIwB/AQAXAAYJXwvhfgDrAAAeAAYJzAZBWADlAAAAAA==.Treesus:BAAALgADCgcJBwABLgAECgkJKAACALwiAA==.Trinshunter:BAABLgAECn9BAAQXAAkJGB2oFACtAgAXAAkJGB2oFACtAgAcAAEJ6gnELwA0AAAeAAEJ4gEnmgAZAAABLgAFFAcJHQAGACEQAA==.',
Tx='Tx:BAACLgAFFH8zAAIYAAcJWx5lEACpAQAYAAcJWx5lEACpAQAuAAQKfywAAhgACAmNIUcQAKcCABgACAmNIUcQAKcCAAAA.',
Ty='Tyedye:BAAALgAECgEJAQAAAA==.',
['Tí']='Tíbs:BAAALgAECgYJCwAAAA==.',
Un='Unbound:BAAALgADCgcJEgAAAA==.Unclegoon:BAAALgAECgYJBgAAAA==.Unholygirl:BAAALgAECgEJAQAAAA==.',
Ut='Utterchaos:BAAALgAECgUJEQAAAA==.',
Va='Vandrina:BAACLgAFFH8OAAICAAMJUASXFAB5AAACAAMJUASXFAB5AAAuAAQKfxgAAgIACQncBvEhACABAAIACQncBvEhACABAAAA.Vanthion:BAAALgAECgYJCQAAAA==.Vaporeon:BAAALgAECgEJAQAAAA==.',
Ve='Vekris:BAAALgAECgEJAgAAAA==.',
Vi='Victreebel:BAAALgAECgcJEQAAAA==.',
Vo='Volg:BAAALgAECgQJBAAAAA==.',
['Vü']='Vüdû:BAAALgAECgEJAQABLgAFFAcJEgAiACANAA==.',
We='Wekko:BAAALgADCgUJBQAAAA==.Wendys:BAABLgAECn8oAAIEAAkJ6xbMUgA/AgAEAAkJ6xbMUgA/AgAAAA==.Wetheals:BAAALgAECgMJBgAAAA==.',
Wh='Whitemonster:BAAALgADCggJDQAAAA==.',
Wi='Wickedhunter:BAAALgADCgYJBgAAAA==.Wimpykid:BAAALgADCggJCAAAAA==.Winar:BAABLgAECn8hAAIEAAgJAhCMgwBwAQAEAAgJAhCMgwBwAQAAAA==.',
Wo='Wongfaihong:BAAALgAECgEJAQAAAA==.Worgnfreeman:BAACLgAFFH8HAAIPAAcJ+gGZCwDWAAAPAAcJ+gGZCwDWAAAuAAQKfxoAAw8ABwnPC3sJAJYAABMABwn7CO+zAA4BAA8ABwmFCnsJAJYAAAAA.',
Wr='Wraithsdaddy:BAAALgADCgEJAQAAAA==.',
Wt='Wtfdrood:BAAALgAECgQJCQABLgAFFAcJEgAiACANAA==.Wtfmate:BAAALgAECgIJAgABLgAFFAcJEgAiACANAA==.Wtfmonk:BAACLgAFFH8SAAIiAAcJIA02LAAQAQAiAAcJIA02LAAQAQAuAAQKfygAAiIACQn+HIcMANECACIACQn+HIcMANECAAAA.',
Xa='Xaioli:BAABLgAECn8gAAMHAAkJaSV0CAA9AwAHAAkJaSV0CAA9AwANAAIJwyF/RQCgAAAAAA==.',
Xe='Xemu:BAAALgADCgUJBQAAAA==.Xethani:BAABLgAECn8bAAIfAAkJbhEiCgDDAQAfAAkJbhEiCgDDAQAAAA==.',
Xo='Xorcopressor:BAAALgAECgIJAgAAAA==.',
Xs='Xsaber:BAAALgAECgQJBwAAAA==.',
Ya='Yazmo:BAACLgAFFH8UAAIIAAcJwSMNCADsAQAIAAcJwSMNCADsAQAuAAQKfzcAAggACAmwI70LAJMCAAgACAmwI70LAJMCAAEuAAUUBQkKABwA5xQA.',
Yu='Yuuky:BAACLgAFFH8XAAIKAAYJfhFqIwA+AQAKAAYJfhFqIwA+AQAuAAQKfzoABAoACQlNHbUWAJICAAoACQlNHbUWAJICABEABwkjCak4AMQAACYAAQnbGpVGAE4AAAAA.',
Za='Zalmo:BAAALgAECgEJAQABLgAECgkJHwAaAJkUAA==.Zarivia:BAAALgADCgMJAwAAAA==.Zartaz:BAABLgAECn8aAAMlAAgJtQyXHAChAQAlAAgJtQyXHAChAQAaAAEJWgc9KgAmAAAAAA==.',
Zb='Zbonez:BAABLgAECn8VAAIEAAkJtgjBrQAlAQAEAAkJtgjBrQAlAQAAAA==.',
Ze='Zendrov:BAABLgAECn8iAAIbAAgJqwViWADRAAAbAAgJqwViWADRAAAAAA==.Zenpai:BAAALgAECgEJBgAAAA==.',
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
