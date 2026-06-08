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

local lookup = {'Mage-Frost','Warlock-Destruction','Druid-Balance','Warlock-Demonology','Warlock-Affliction','DemonHunter-Devourer','Monk-Windwalker','DeathKnight-Unholy','DeathKnight-Blood','Warrior-Protection','Priest-Holy','Paladin-Retribution','Warrior-Fury','Warrior-Arms','Shaman-Enhancement','Paladin-Protection','Shaman-Elemental','Evoker-Preservation','DemonHunter-Vengeance','Monk-Mistweaver','Evoker-Augmentation','Evoker-Devastation','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Guardian','Unknown-Unknown','Shaman-Restoration','Paladin-Holy','Druid-Restoration','Priest-Shadow','Monk-Brewmaster','Druid-Feral','DeathKnight-Frost','Hunter-Survival','Rogue-Subtlety','Rogue-Outlaw','DemonHunter-Havoc','Priest-Discipline','Rogue-Assassination',}
local provider = {region='US',realm="Vek'nilash",name='US',type='weekly',zone=46,date='2026-06-07',data={Ab='Abomination:BAAALgADCgMJAwAAAA==.',
Ad='Adune:BAAALgAECgQJBQAAAA==.',
Ae='Aeidail:BAACLgAFFH8dAAIBAAcJTRjEHwDqAQABAAcJTRjEHwDqAQAuAAQKfyoAAgEACAnUI0McAAUDAAEACAnUI0McAAUDAAAA.Aelaria:BAAALgADCgMJAwAAAA==.Aeviria:BAABLgAECn8oAAICAAgJtRWwBwDKAQACAAgJtRWwBwDKAQAAAA==.',
Ag='Agraceful:BAACLgAFFH8LAAIDAAMJEAdqMwCeAAADAAMJEAdqMwCeAAAuAAQKfx8AAgMACQm8El0dANIBAAMACQm8El0dANIBAAAA.',
Ai='Ailee:BAAALgAECgYJDAAAAA==.Aios:BAAALgADCgcJCQAAAA==.Aiza:BAACLgAFFH8LAAIEAAMJeAR8gwCvAAAEAAMJeAR8gwCvAAAuAAQKfy4AAwQACQnqE1ZDAMsBAAQACQnqE1ZDAMsBAAUAAQkAAPQ3AB0AAAAA.',
Al='Alaber:BAAALgAECgUJBQAAAA==.Aldanil:BAAALgADCgMJAwAAAA==.Allarria:BAAALgADCgYJBwABLgAECgkJJgAGAFogAA==.',
Am='Ampersand:BAAALgAECgMJBQAAAA==.',
An='Animalfriend:BAAALgAECgIJBAAAAA==.Anklesmasher:BAABLgAECn8UAAIHAAcJ/A5oOAAVAQAHAAcJ/A5oOAAVAQAAAA==.Antonidus:BAAALgAECgUJBwAAAA==.Anyah:BAAALgAECggJEgAAAA==.',
Ap='Apolloo:BAAALgADCgMJAwAAAA==.',
Aq='Aquadora:BAAALgAECgEJAQAAAA==.',
Ar='Arfaz:BAABLgAECn8sAAMIAAgJbBrSPwD+AQAIAAgJMRnSPwD+AQAJAAYJWArlNQC1AAAAAA==.Armbrost:BAAALgAECgYJCgAAAA==.Artimås:BAAALgADCgcJCAAAAA==.Arwynne:BAAALgADCgMJAwAAAA==.Arçano:BAAALgAECgEJAQABLgAECgkJGQAKADkTAA==.',
As='Ascension:BAAALgADCgcJBgABLgAECgkJPgAEAJ8kAA==.Astrastar:BAABLgAECn8bAAMEAAYJ0wKV2wCaAAAEAAYJ0wKV2wCaAAACAAEJcgDDgAAOAAAAAA==.',
Au='Auralyn:BAAALgADCgMJBQAAAA==.Aurius:BAAALgAECgcJAgAAAA==.',
Av='Avarin:BAAALgADCgEJAQAAAA==.',
Ay='Aymont:BAAALgAECgQJBQAAAA==.',
Ba='Baerd:BAABLgAECn8aAAILAAcJZhMAKgBsAQALAAcJZhMAKgBsAQAAAA==.Baji:BAAALgAECgkJBwAAAA==.Barlz:BAAALgAECgEJAQAAAA==.',
Be='Beanpaste:BAAALgAECgcJAQABLgAFFAMJDgAIAMwYAA==.Beanutbutter:BAAALgADCgIJAgABLgAFFAMJDgAIAMwYAA==.Beaty:BAAALgAECgIJAgAAAA==.Bebby:BAABLgAECn8XAAMJAAcJRALMQwBzAAAJAAYJGwLMQwBzAAAIAAIJaQKlZAExAAAAAA==.Belonara:BAAALgAECgEJAQAAAA==.Belwolf:BAAALgAECgUJEAAAAA==.Bergstrom:BAABLgAECn80AAIMAAkJuhmzLQBAAgAMAAkJuhmzLQBAAgAAAA==.Bethanymarie:BAAALgAECgEJAQAAAA==.Betrayer:BAAALgADCgQJAwABLgAECgkJPgAEAJ8kAA==.',
Bi='Biancaneve:BAAALgAFFAEJAQAAAA==.Bighero:BAACLgAFFH8OAAIGAAMJSQtuYQC8AAAGAAMJSQtuYQC8AAAuAAQKfx4AAgYACQk9EVlvAFYBAAYACQk9EVlvAFYBAAAA.Bigmike:BAAALgAECgEJAgAAAA==.',
Bl='Blakkjezus:BAAALgAECgcJDQAAAA==.Blessednugie:BAAALgAECgcJDgAAAA==.Blitzbolts:BAAALgAECgEJAgAAAA==.Bludo:BAACLgAFFH8QAAMNAAYJNBJEIAAlAQANAAUJHRVEIAAlAQAOAAMJpAygJQDEAAAuAAQKfx4AAw0ACQl6IWgZAIACAA0ACAk5GWgZAIACAA4ABgl9HFMYADYBAAAA.',
Bo='Boe:BAABLgAECn8mAAIPAAkJyglwEgCCAQAPAAkJyglwEgCCAQAAAA==.Bomba:BAAALgAECgQJBQAAAA==.Bombacløt:BAABLgAECn8vAAMEAAkJAxB3QwDLAQAEAAkJhg93QwDLAQACAAcJbg5MEwALAQAAAA==.Bowdirte:BAAALgAECgUJBwAAAA==.',
Br='Brastin:BAABLgAECn86AAIQAAkJkyIBAgAWAwAQAAkJkyIBAgAWAwABLgAFFAUJEgARAIQMAA==.Brenell:BAACLgAFFH8IAAIBAAMJgRIqggDPAAABAAMJgRIqggDPAAAuAAQKfzoAAgEACQmwIQcQAPYCAAEACQmwIQcQAPYCAAAA.',
Bu='Bu:BAAALgAECgYJDQABLgAECgYJGwASALgdAA==.Bubblehearth:BAAALgAECgYJCQABLgAECgkJKwAGAHwaAA==.Buffet:BAABLgAECn8VAAIBAAYJtw5NsgAbAQABAAYJtw5NsgAbAQABLgAECgkJKwAGAHwaAA==.Buhlitz:BAAALgAECgEJAgAAAA==.Butterbean:BAAALgADCgMJBQAAAA==.',
By='Bynis:BAABLgAECn8gAAIGAAkJDRVdRQCsAQAGAAkJDRVdRQCsAQAAAA==.',
Ca='Cabëla:BAAALgADCgUJBQAAAA==.Cactusjack:BAAALgADCgUJBQAAAA==.Cadorex:BAAALgADCgEJAQAAAA==.Caffeinefree:BAAALgADCggJBwAAAA==.Calacolinda:BAAALgAECgQJBgAAAA==.Calamari:BAAALgAECgEJAQAAAA==.Cavakworm:BAAALgADCgEJAQAAAA==.Caylin:BAAALgADCgUJBgAAAA==.Cayusedemon:BAAALgADCgEJAQAAAA==.Cayusemage:BAAALgADCgkJDwAAAA==.',
Ce='Ceridwyn:BAAALgAECgEJAQAAAA==.',
Ch='Chariscrushr:BAAALgAECgQJCAABLgAFFAgJGgAHAG4YAA==.Chen:BAAALgADCgIJAgAAAA==.Choal:BAAALgAECgEJAQAAAA==.Chokaho:BAAALgAECgMJAwAAAA==.',
Ci='Cinnamongirl:BAAALgAECgcJEgAAAA==.',
Co='Corahin:BAABLgAECn8bAAIRAAYJGxASRAA5AQARAAYJGxASRAA5AQAAAA==.Corious:BAAALgAECgQJCQAAAA==.Cosmos:BAAALgAECgYJDQAAAA==.Cougarhunter:BAAALgAECgkJEAAAAA==.',
Cr='Crixux:BAAALgADCgMJAQAAAA==.Crokus:BAAALgADCggJCAAAAA==.',
Cu='Cuecumba:BAABLgAECn8uAAITAAkJICZdAABeAwATAAkJICZdAABeAwAAAA==.',
Da='Daemonerror:BAAALgAECgUJBQABLgAECggJQAAUAKUjAA==.Dalren:BAACLgAFFH8YAAMVAAYJah5eFQChAQAVAAUJah5eFQChAQAWAAIJuwNtCwBLAAAuAAQKf0YAAxUACQnIJd4BAGIDABUACQnIJd4BAGIDABYABgnyIEMMABcCAAAA.Dalryn:BAAALgAECgYJDQABLgAFFAYJGAAVAGoeAA==.Dalvix:BAAALgADCgEJAQABLgAECgkJJgAGAFogAA==.Damocles:BAABLgAECn8YAAIBAAYJlwxevwAHAQABAAYJlwxevwAHAQAAAA==.Danazel:BAAALgADCgMJBQAAAA==.Dartagnan:BAACLgAFFH8MAAIXAAMJVhwJSgAEAQAXAAMJVhwJSgAEAQAuAAQKfyUAAxcACQnLHbhDAMwBABcABwkLH7hDAMwBABgABgn3FD8aANEAAAAA.Darthmaul:BAABLgAECn8wAAIDAAkJyhHqHQDNAQADAAkJyhHqHQDNAQAAAA==.',
De='Deay:BAAALgADCgQJAQAAAA==.Delexa:BAAALgADCgkJQAAAAA==.Demonicnugie:BAAALgADCgEJAQAAAA==.Dendiian:BAABLgAECn8UAAIZAAYJXxVuJAAdAQAZAAYJXxVuJAAdAQAAAA==.',
Di='Didipullthat:BAAALgADCgYJFwABLgAECgkJKwAGAHwaAA==.Diem:BAABLgAECn8dAAIXAAgJyw1rQQCqAQAXAAgJyw1rQQCqAQAAAA==.Dirtydotss:BAABLgAECn8VAAMFAAcJFwfXEgD/AAAFAAYJYQbXEgD/AAAEAAYJ5wQgxgC8AAAAAA==.Divigitives:BAAALgAECgQJBAAAAA==.',
Do='Docrivan:BAAALgAECgYJCwAAAA==.Docsassist:BAAALgAECgMJAwABLgAECgYJCwAaAAAAAA==.Doregit:BAABLgAECn8zAAINAAkJaR7PCgCyAgANAAkJaR7PCgCyAgAAAA==.Dowedoes:BAABLgAECn89AAIMAAkJghccMwAqAgAMAAkJghccMwAqAgAAAA==.',
Dr='Drachula:BAABLgAECn8aAAIbAAYJTRahSACAAQAbAAYJTRahSACAAQAAAA==.Dracultra:BAAALgAECgUJBwABLgAECgkJIAAcAF0fAA==.Drakcheese:BAAALgADCgUJBQAAAA==.Dreolan:BAABLgAECn9BAAIdAAkJ0xUsIQA2AgAdAAkJ0xUsIQA2AgAAAA==.Drynnai:BAAALgADCgEJAgAAAA==.',
Dy='Dyala:BAACLgAFFH8NAAMdAAMJjg85PgCyAAAdAAMJjg85PgCyAAADAAMJMwTpNQCOAAAuAAQKfyEAAx0ACQkDEuxiAAMBAB0ACQkDEuxiAAMBAAMAAwmBDiRcAJcAAAAA.',
['Dö']='Dönövan:BAABLgAECn8vAAIMAAkJnBNRQgD2AQAMAAkJnBNRQgD2AQAAAA==.',
El='Elastwo:BAAALgADCgcJEgAAAA==.Eloise:BAAALgAECgcJEwAAAA==.Elvenbane:BAABLgAECn8mAAIeAAkJrRPYGgDoAQAeAAkJrRPYGgDoAQAAAA==.',
Em='Emily:BAAALgAECgYJDAAAAA==.Emry:BAAALgADCgYJBgABLgAECgcJHQAUADkPAA==.',
En='Enable:BAEBLgAECn8gAAIfAAkJVRyrCQCRAgAfAAkJVRyrCQCRAgABLgAECggJNAAQAE8iAA==.',
Ep='Epictool:BAAALgAECggJCwAAAA==.',
Et='Ethereal:BAAALgAECgEJAQAAAA==.',
Ex='Extrathick:BAAALgAECgMJAwAAAA==.',
Fa='Fabel:BAEBLgAECn80AAIQAAgJTyLJBgBrAgAQAAgJTyLJBgBrAgAAAA==.Falahad:BAAALgAECgEJAQABLgAFFAMJDAADAD4OAA==.Faltree:BAACLgAFFH8MAAMDAAMJPg6kLwCxAAADAAMJPg6kLwCxAAAdAAIJ6RNhTgB9AAAuAAQKfx8ABB0ACAmwGP5TAFcBAB0ABglPGP5TAFcBAAMACAkOFyUwAFEBACAAAQnfAUo6AB8AAAAA.Fathershale:BAAALgADCggJFwAAAA==.',
Fi='Firelord:BAAALgADCgEJAQAAAA==.',
Fo='Foulcor:BAABLgAECn8dAAMcAAkJ7B5SFgBPAgAcAAgJlB5SFgBPAgAMAAcJRhHHkABGAQAAAA==.',
Fr='Freakadeek:BAABLgAECn8VAAQhAAkJaw3zHgDGAAAIAAUJ0AjmywDlAAAhAAMJnhfzHgDGAAAJAAYJgwSlSgBaAAAAAA==.Freâkadeek:BAAALgAECgIJAwABLgAECgkJFQAhAGsNAA==.Freäk:BAAALgADCgMJAwABLgAECgkJFQAhAGsNAA==.Frieren:BAABLgAECn89AAIBAAkJ6xWxPAAiAgABAAkJ6xWxPAAiAgAAAA==.Frink:BAAALgAECgEJAQABLgAECgkJPQAiAOEkAA==.Frostlord:BAAALgAECgIJAgAAAA==.',
Fu='Fundetected:BAAALgAFFAIJAgABLgAECgkJKwAGAHwaAA==.Furyofthenug:BAAALgADCgcJCgAAAA==.',
Ga='Gabbyo:BAABLgAECn8iAAIdAAcJkQfWbADlAAAdAAcJkQfWbADlAAAAAA==.Galadorn:BAABLgAECn8mAAIGAAkJWiDBDgDFAgAGAAkJWiDBDgDFAgAAAA==.Gallgamesh:BAAALgADCgIJAgAAAA==.Garfall:BAAALgAECgcJDgAAAA==.Garga:BAAALgADCgMJBAABLgAECgQJBAAaAAAAAA==.',
Ge='Geirvaldr:BAAALgAECgYJBgAAAA==.Gerdash:BAAALgAECgMJBAAAAA==.Gerred:BAACLgAFFH8FAAIOAAMJkBPkHwDhAAAOAAMJkBPkHwDhAAAuAAQKfxwAAw4ABwm+GgYTAMIBAA4ABwkNGgYTAMIBAA0ABAlFFNBgAMoAAAAA.',
Gh='Ghallow:BAABLgAECn8aAAIPAAcJUBiSDQDLAQAPAAcJUBiSDQDLAQAAAA==.Ghosty:BAACLgAFFH8JAAIjAAQJOxWMHQAlAQAjAAQJOxWMHQAlAQAuAAQKfyoAAiMABwlQIBoTAAECACMABwlQIBoTAAECAAAA.',
Gi='Gimp:BAAALgAECgEJAgAAAA==.',
Gl='Gladur:BAABLgAFFH8GAAMHAAYJyAwxHADoAAAHAAUJtwwxHADoAAAUAAEJmQH5WQAxAAABLgAFFAcJHQABAE0YAA==.',
Go='Goldenflame:BAAALgAECgUJBwAAAA==.Goldenlily:BAAALgAECgYJEgAAAA==.Goldenmunc:BAABLgAECn8tAAIBAAkJNxdpMwBFAgABAAkJNxdpMwBFAgAAAA==.Goldenone:BAAALgAECgQJBQAAAA==.Goldenpants:BAABLgAECn8nAAINAAkJjxMnIADqAQANAAkJjxMnIADqAQAAAA==.',
Gr='Grievous:BAABLgAECn89AAITAAkJOyWaAABMAwATAAkJOyWaAABMAwAAAA==.',
['Gû']='Gûrth:BAAALgADCgcJBwAAAA==.',
Ha='Hailmary:BAABLgAECn8oAAILAAkJEiVSAQCrAwALAAkJEiVSAQCrAwAAAA==.Halcrux:BAAALgAECgIJAgAAAA==.Halvard:BAAALgADCgMJBQAAAA==.Harusen:BAABLgAECn8cAAIkAAkJFR8nAgClAgAkAAkJFR8nAgClAgAAAA==.',
He='Healaga:BAAALgAECgYJBgABLgAECggJLAAIAGwaAA==.',
Hi='Hildalsind:BAAALgADCgkJCQABLgAFFAMJCQABAIMdAA==.',
Ho='Homestar:BAAALgADCgEJAQAAAA==.Hooll:BAAALgAECgIJAgAAAA==.Hornreaper:BAABLgAECn8bAAIVAAYJ5hfvJACVAQAVAAYJ5hfvJACVAQAAAA==.Hotshot:BAAALgAECgMJAwAAAA==.',
Hu='Hubbabubbajr:BAAALgAECgMJAwABLgAECgkJMwAdAIIbAA==.Hubert:BAAALgADCgEJAgAAAA==.Hurin:BAAALgAECgcJDgAAAA==.Huur:BAAALgAECgEJAQABLgAECgEJAQAaAAAAAA==.',
Hy='Hyetta:BAAALgAECgQJBgABLgAECgkJHAAkABUfAA==.Hyir:BAAALgADCgYJBwABLgAFFAQJFAAHAJUdAA==.',
Il='Ilavengu:BAAALgAECgIJAgABLgAFFAQJFgAbADEmAA==.Illiya:BAAALgAECgUJEAAAAA==.',
Ir='Irôn:BAAALgAECgEJAQAAAA==.',
Iu='Iutara:BAAALgAECgYJDAAAAA==.',
Ja='Jaalein:BAAALgADCgcJDgAAAA==.Jayonor:BAABLgAECn80AAQRAAkJthW3GAARAgARAAkJthW3GAARAgAPAAYJ9we4GgAeAQAbAAcJ5AZZbAAJAQAAAA==.',
Je='Jek:BAAALgAECgUJBQAAAA==.',
Jo='Joryu:BAAALgADCgIJAwAAAA==.',
Ju='Juicycucci:BAAALgAECgcJEgABLgAECgkJKwAGAHwaAA==.',
Ka='Kaevrielle:BAECLgAFFH8FAAITAAMJfBW9BwDIAAATAAMJfBW9BwDIAAAuAAQKfx4AAxMACQmOG/kGAAwCABMACQmOG/kGAAwCACUAAQlWCmNwACcAAAAA.Kaison:BAABLgAECn8XAAMeAAkJEQiuLQBkAQAeAAkJEQiuLQBkAQAmAAcJBAuGMQBKAQABLgAECgkJIAAGAA0VAA==.Kaladîn:BAAALgAECgMJAwABLgAFFAcJHQABAE0YAA==.Kalii:BAAALgADCgQJBAAAAA==.Kamel:BAAALgADCgYJBgAAAA==.Karwin:BAABLgAECn8ZAAIBAAcJhhQ0hwBkAQABAAcJhhQ0hwBkAQAAAA==.Katakuri:BAAALgAECgEJAgAAAA==.',
Ke='Keeper:BAAALgAECgYJCAABLgAECgkJUQAMAPwkAA==.Keeperodark:BAAALgAECggJEQABLgAECgkJUQAMAPwkAA==.Keeperolight:BAABLgAECn9RAAMMAAkJ/CQtBQBGAwAMAAkJ/CQtBQBGAwAcAAEJgRgUkABAAAAAAA==.Kemanorel:BAAALgADCgcJDgABLgAECgkJJgAeAK0TAA==.',
Ki='Kianth:BAAALgADCgkJEgAAAA==.Killkat:BAABLgAECn8uAAIBAAkJgxiUMgBIAgABAAkJgxiUMgBIAgAAAA==.',
Ko='Kodera:BAABLgAECn8bAAMSAAYJuB1cDQD1AQASAAYJuB1cDQD1AQAWAAQJNxshDgAhAQAAAA==.Koojo:BAAALgAECgcJCAAAAA==.Kovae:BAAALgADCgEJAQAAAA==.',
Kr='Kraken:BAAALgADCgUJBQAAAA==.',
Ku='Kusheddruid:BAAALgADCgMJBQAAAA==.',
Ky='Kyaritin:BAAALgAECgMJAwABLgAECgYJCgAaAAAAAA==.Kyokei:BAAALgAECgEJAQAAAA==.',
La='Laiho:BAAALgADCgUJCAAAAA==.Lans:BAAALgAFFAEJAgAAAA==.Larew:BAACLgAFFH8FAAIMAAMJbgeJcgC7AAAMAAMJbgeJcgC7AAAuAAQKfy4AAgwACAnuGZE3ABkCAAwACAnuGZE3ABkCAAAA.Lazytemplar:BAAALgADCgMJAwABLgAECgYJCQAaAAAAAA==.',
Le='Lealla:BAABLgAECn89AAIDAAkJlCLUBAAKAwADAAkJlCLUBAAKAwAAAA==.Lechevalier:BAAALgAFFAEJAQABLgAECgkJKwAGAHwaAA==.Leodin:BAAALgAECgEJAgAAAA==.Leorus:BAAALgAECgIJAgAAAA==.Lethhunt:BAACLgAFFH8SAAMYAAYJPQ2IEwAfAQAYAAYJ9QqIEwAfAQAXAAIJWw4MGgCeAAAuAAQKfy4AAxgACQncHggGAC4CABgACQlgHggGAC4CABcAAgk+JFKHANIAAAAA.',
Li='Lilmistfox:BAAALgAECgUJBwABLgAFFAQJFgAbADEmAA==.Lioh:BAAALgAECgQJBAAAAA==.Lizardgang:BAAALgAECgYJEwAAAA==.',
Lo='Loganshu:BAAALgAECgcJCwAAAA==.Lokan:BAACLgAFFH8OAAMiAAMJWRm4GgDpAAAiAAMJWRm4GgDpAAAXAAEJwgjjlwBFAAAuAAQKfyoAAiIACQnMHPkIAIoCACIACQnMHPkIAIoCAAAA.Lots:BAACLgAFFH8OAAIEAAMJhhuQXgD8AAAEAAMJhhuQXgD8AAAuAAQKfycAAwQACQktIigoADUCAAQACAliIigoADUCAAIABAngHkcsAA0BAAAA.',
Lu='Ludacast:BAAALgADCgIJAgAAAA==.Ludafists:BAAALgADCgcJDAAAAA==.Ludakris:BAABLgAECn8eAAIQAAkJfxiPCgAVAgAQAAkJfxiPCgAVAgAAAA==.Lumanoth:BAAALgAECgYJBgAAAA==.',
Ly='Lyna:BAABLgAECn8gAAIbAAkJpROTPACwAQAbAAkJpROTPACwAQAAAA==.Lynaya:BAAALgADCgIJAgAAAA==.',
['Lí']='Líonheart:BAABLgAECn8cAAMcAAYJ+BmoRAAkAQAcAAYJ+BmoRAAkAQAMAAYJFgs3yQDxAAAAAA==.',
['Lî']='Lîghtless:BAACLgAFFH8PAAIBAAYJBhqgGABoAQABAAYJBhqgGABoAQAuAAQKfxcAAgEACAmfJUchAO4CAAEACAmfJUchAO4CAAAA.',
['Lú']='Lúckally:BAAALgADCgQJBAABLgAECgYJCgAaAAAAAA==.Lúckÿ:BAAALgAECgYJCgAAAA==.',
Ma='Magetheo:BAAALgADCgIJAgAAAA==.Magicpanda:BAAALgAECgQJBwAAAA==.Mahina:BAAALgAECgIJAgAAAA==.Malik:BAAALgADCgIJAgAAAA==.Marcille:BAABLgAECn8nAAIBAAgJ2RP/cACTAQABAAgJ2RP/cACTAQAAAA==.Masyledian:BAAALgAECgIJAgAAAA==.Mathor:BAAALgAECgEJAgAAAA==.Mavrbg:BAAALgAECgQJBQAAAA==.Mayhaps:BAABLgAECn9EAAMXAAkJFRtFJABHAgAXAAkJFRtFJABHAgAYAAEJZACpmgAYAAAAAA==.',
Mc='Mcbain:BAABLgAECn89AAIiAAkJ4SSWAQBEAwAiAAkJ4SSWAQBEAwAAAA==.',
Me='Melinia:BAAALgAECgEJAQABLgAECgEJAgAaAAAAAA==.Melrine:BAAALgADCgMJAwAAAA==.Mentaltitty:BAABLgAECn8gAAIBAAkJgxIuRwAAAgABAAkJgxIuRwAAAgAAAA==.Meret:BAAALgADCgMJBQAAAA==.',
Mi='Minerwor:BAAALgAECgUJCQAAAA==.Mirrayla:BAAALgADCgYJBgAAAA==.Misty:BAAALgADCgYJBgAAAA==.',
Mm='Mmisty:BAABLgAECn9CAAIDAAkJghlsDgBsAgADAAkJghlsDgBsAgAAAA==.',
Mo='Moarthretplz:BAAALgAECgUJCQABLgAFFAQJFgAbADEmAA==.Mohji:BAAALgAFFAEJAQABLgAFFAcJGgAmAOwUAA==.Moldynuggets:BAAALgADCgYJBgAAAA==.Momometaru:BAABLgAECn8kAAQEAAkJgRYSPgDdAQAEAAkJfhMSPgDdAQACAAUJNhRyJgAsAQAFAAMJzxoSJACNAAAAAA==.Monsterbee:BAABLgAECn9IAAIEAAkJkxMHMwAHAgAEAAkJkxMHMwAHAgAAAA==.',
Mu='Mustypizza:BAABLgAECn8uAAICAAkJihhSBAAwAgACAAkJihhSBAAwAgAAAA==.',
Mx='Mxicancowboy:BAAALgADCgEJAgAAAA==.',
My='Mystery:BAABLgAECn89AAMSAAkJNiCeAgA2AwASAAkJNiCeAgA2AwAWAAUJXhEnDwAPAQAAAA==.',
['Mê']='Mêøwzêr:BAAALgAECggJEwAAAA==.',
['Mÿ']='Mÿst:BAAALgAECgMJBAAAAA==.',
Na='Nak:BAAALgAECgYJBgAAAA==.Narashi:BAAALgAECgQJCAAAAA==.Naril:BAAALgADCgUJBQAAAA==.Nats:BAABLgAECn8kAAIbAAgJSxGwOACfAQAbAAgJSxGwOACfAQAAAA==.',
Ne='Neameny:BAABLgAECn89AAIXAAkJGBO/NgD4AQAXAAkJGBO/NgD4AQAAAA==.',
Ni='Nianji:BAAALgADCgYJDgAAAA==.Nightstar:BAAALgADCgMJAwAAAA==.Nightworld:BAAALgADCgcJDgAAAA==.',
No='Noctum:BAAALgAECgUJBQAAAA==.Nordicpally:BAAALgADCgQJBAAAAA==.Notgim:BAAALgADCggJCAAAAA==.',
Nu='Nualrossan:BAAALgADCgYJCAAAAA==.Nubrac:BAAALgAECgkJEwAAAA==.',
Ny='Nylux:BAAALgAECgYJDwAAAA==.',
Ob='Oblivion:BAABLgAECn8+AAMEAAkJnyT2BQAqAwAEAAkJnyT2BQAqAwACAAEJAABRXQBXAAAAAA==.',
Oo='Oostren:BAAALgAECgEJAgAAAA==.',
Or='Orsyp:BAAALgADCgkJGgAAAA==.',
Pa='Palockie:BAAALgADCgEJAQAAAA==.Pandas:BAABLgAECn8hAAIRAAkJAhFAJQCyAQARAAkJAhFAJQCyAQAAAA==.Partyrocker:BAABLgAECn8XAAIiAAcJag4KKQBUAQAiAAcJag4KKQBUAQABLgAECgkJFQAhAGsNAA==.',
Pi='Pixae:BAACLgAFFH8OAAISAAMJjwfpIACOAAASAAMJjwfpIACOAAAuAAQKfyEAAhIACAm5CgsYAEoBABIACAm5CgsYAEoBAAAA.Pixiechaos:BAAALgAECgQJCAAAAA==.',
Po='Poliahu:BAABLgAECn8XAAIXAAYJvQyXiwAdAQAXAAYJvQyXiwAdAQAAAA==.Porthoss:BAAALgADCggJDwAAAA==.Powerplant:BAACLgAFFH8VAAIXAAYJaiH3FACeAQAXAAYJaiH3FACeAQAuAAQKfyYAAhcACQkgJCgIAA4DABcACQkgJCgIAA4DAAAA.Poyoram:BAAALgADCgEJAQAAAA==.',
Py='Pyralys:BAABLgAECn85AAMLAAkJGBG+GgDmAQALAAkJGBG+GgDmAQAeAAMJqQIvgAAyAAAAAA==.',
Qu='Quizac:BAAALgADCgMJBQAAAA==.',
Ra='Ragemonk:BAAALgAECgUJDgABLgAECgYJCQAaAAAAAA==.Ragetality:BAAALgAECgYJCQAAAA==.Rakthera:BAAALgADCgcJBwAAAA==.Ramaria:BAAALgADCgkJCQABLgAECgkJJgAGAFogAA==.Raserei:BAABLgAFFH8FAAINAAMJIhccKwDzAAANAAMJIhccKwDzAAAAAA==.Rasputain:BAAALgADCgYJCgAAAA==.Rasputein:BAAALgADCgcJBwAAAA==.Rattelyr:BAAALgAECgYJDQAAAA==.Ravara:BAAALgADCgYJBgABLgAECgkJJgAGAFogAA==.Razgaurd:BAAALgAECgMJAwAAAA==.',
Re='Regice:BAAALgAECgcJBwABLgAFFAMJCQAJAIEYAA==.Regicee:BAACLgAFFH8JAAIJAAMJgRhSHQDrAAAJAAMJgRhSHQDrAAAuAAQKfzwAAwkACQmEIvoDAPQCAAkACQmEIvoDAPQCAAgABAm3CHUNAY0AAAAA.Retam:BAAALgAECgYJBwAAAA==.Revakos:BAAALgADCgMJAwAAAA==.',
Rh='Rhysandra:BAAALgAECgQJCQAAAA==.',
Ri='Ribble:BAAALgADCgMJAwAAAA==.Riffraff:BAAALgAECgcJBAAAAA==.Ripcord:BAAALgAECgUJCAAAAA==.Ripem:BAAALgADCgYJBgAAAA==.Ripperoni:BAAALgAECgYJBwAAAA==.Rizek:BAAALgAECgUJBgABLgAECgcJHQAUADkPAA==.Rizzx:BAAALgAECgEJAQAAAA==.',
Ro='Rockdyou:BAABLgAECn8nAAIIAAkJ+R5MIQB8AgAIAAkJ+R5MIQB8AgAAAA==.Roglef:BAAALgAECgQJCQAAAA==.Rotlobster:BAABLgAECn8aAAIFAAkJAB6/AQDJAgAFAAkJAB6/AQDJAgAAAA==.Roxxy:BAAALgAECgQJBAAAAA==.',
Ru='Rundvelt:BAACLgAFFH8OAAIQAAMJeA0EDQCcAAAQAAMJeA0EDQCcAAAuAAQKfyIAAhAACQlSEd8TAIMBABAACQlSEd8TAIMBAAAA.',
Sa='Sage:BAAALgADCgcJCAAAAA==.Sandwich:BAAALgAECgcJCAAAAA==.Saphíra:BAAALgAFFAIJAQABLgAFFAcJHQABAE0YAA==.Sapkick:BAAALgAECgQJBwAAAA==.',
Se='Serdragon:BAAALgADCgQJBAAAAA==.Servoid:BAAALgAECgUJCQAAAA==.',
Sh='Shando:BAAALgAECgEJAQAAAA==.Shiftstyle:BAEALgAECgEJAQAAAA==.Shtanky:BAACLgAFFH8MAAIKAAMJaBGVGwCtAAAKAAMJaBGVGwCtAAAuAAQKfyIAAgoACQnhDh8XAH4BAAoACQnhDh8XAH4BAAAA.',
Si='Silentsocks:BAAALgAECgUJDAAAAA==.Sixsixsix:BAAALgAECgcJCgABLgAFFAIJCAAIANMeAA==.',
Sk='Skoogz:BAAALgAECgkJEwAAAA==.',
So='Soggyy:BAAALgADCgYJCwAAAA==.Solar:BAABLgAECn8VAAQHAAcJyRkxLwBtAQAHAAYJCxYxLwBtAQAfAAYJrhzoOABmAQAUAAEJUwLrxAAaAAAAAA==.Soulfulgingr:BAAALgAECgYJEAAAAA==.',
St='Starlagosa:BAAALgADCgYJCQAAAA==.Sturm:BAAALgAECgMJAwAAAA==.Styx:BAAALgAECgMJAwAAAA==.',
Su='Sunbake:BAAALgAECgUJDAAAAA==.',
Sw='Sweetbbyraze:BAACLgAFFH8YAAMVAAUJwx2dHABfAQAVAAUJFh2dHABfAQAWAAMJmRYACACnAAAuAAQKfyYAAxYACAkpIVIGAJACABYABwm8IVIGAJACABUAAwnyHH1mAJkAAAAA.',
Sy='Sylaena:BAABLgAECn8oAAIYAAgJVQomEwAfAQAYAAgJVQomEwAfAQAAAA==.Sylvrstorm:BAAALgAECgcJCwAAAA==.',
['Së']='Sërënity:BAAALgAECgUJDAAAAA==.',
['Sí']='Sín:BAAALgAECgcJDAABLgAFFAIJCAAIANMeAA==.',
Ta='Talipally:BAACLgAFFH8HAAIMAAMJ7QitbwDCAAAMAAMJ7QitbwDCAAAuAAQKfxwAAgwACQkyEGxzAH0BAAwACQkyEGxzAH0BAAAA.Talishammy:BAAALgAECgMJAwABLgAFFAMJBwAMAO0IAA==.Taliwhacker:BAAALgAFFAEJAQABLgAFFAMJBwAMAO0IAA==.Talonleafgrd:BAAALgAECgEJAQAAAA==.Tanaka:BAABLgAECn8gAAIIAAgJgBNyVQC+AQAIAAgJgBNyVQC+AQAAAA==.Tanisong:BAAALgAECgQJCwAAAA==.Tassadar:BAAALgAECgUJCAAAAA==.',
Te='Teldo:BAAALgADCgMJBQAAAA==.Tepeyollotl:BAAALgADCgEJAQAAAA==.Terayus:BAAALgADCgcJDAAAAA==.Teyliah:BAAALgADCgMJAwAAAA==.',
Tf='Tf:BAAALgAECgYJBgABLgAFFAIJCAAIANMeAA==.',
Th='Thekingpunch:BAABLgAECn9AAAMUAAgJpSMPBwAiAwAUAAgJpSMPBwAiAwAHAAEJahYkhwBCAAAAAA==.Thenle:BAAALgADCggJDgAAAA==.Thline:BAAALgADCgMJBQAAAA==.Thunderblitz:BAABLgAECn8rAAIcAAkJdgnxMACLAQAcAAkJdgnxMACLAQAAAA==.Thurmus:BAAALgADCgkJQAAAAA==.',
Ti='Tillwar:BAABLgAECn87AAINAAkJKh10DwB5AgANAAkJKh10DwB5AgAAAA==.Tinymonk:BAAALgADCgkJEgAAAA==.',
To='Tofu:BAACLgAFFH8FAAIIAAMJ5ReWhwDpAAAIAAMJ5ReWhwDpAAAuAAQKfz0AAwgACQmUHS8WALsCAAgACQmUHS8WALsCAAkABgmCF5YeAFYBAAAA.Tokanya:BAAALgAECgEJAQAAAA==.Tortillachip:BAAALgAECgEJAgAAAA==.Toxidot:BAAALgAECgEJAQAAAA==.',
Tr='Treibh:BAABLgAECn8qAAIdAAkJCxiiFgCKAgAdAAkJCxiiFgCKAgAAAA==.Trelephant:BAAALgAECgMJBQAAAA==.Trulydps:BAABLgAECn8sAAIXAAkJ1hP8KwAkAgAXAAkJ1hP8KwAkAgAAAA==.Trulyog:BAAALgAECgQJBAAAAA==.',
Tu='Tubbsmcgee:BAACLgAFFH8YAAIbAAYJ6x/DBQBKAgAbAAYJ6x/DBQBKAgAuAAQKfyUAAhsACQkrJLgHAPkCABsACQkrJLgHAPkCAAEuAAUUBgkYABsA6x8A.Tukkit:BAAALgAECgYJDgAAAA==.',
Tw='Twistedshot:BAAALgADCggJCAAAAA==.Twizzler:BAABLgAECn9IAAIBAAkJTwYfhwBkAQABAAkJTwYfhwBkAQAAAA==.',
Ty='Tyraniik:BAAALgADCgYJCAAAAA==.',
['Të']='Tërris:BAABLgAECn8bAAIJAAgJ7hHHHgBUAQAJAAgJ7hHHHgBUAQAAAA==.',
['Tî']='Tîlldeath:BAAALgAECgUJBwAAAA==.',
Uj='Uji:BAAALgADCgEJAQAAAA==.',
Ur='Urowndad:BAAALgAECgUJBQABLgAECggJFgAMAL0TAA==.Urownmother:BAAALgADCgUJBQABLgAECggJFgAMAL0TAA==.',
Va='Vaellian:BAAALgAECgYJDAAAAA==.Vallez:BAECLgAFFH8RAAMcAAMJoh+HIQAJAQAcAAMJoh+HIQAJAQAMAAIJKwNEmgBxAAAuAAQKfygAAxwACQmqHQ0RAIUCABwACQmqHQ0RAIUCAAwAAgnbCa9FATIAAAAA.Vanillaghost:BAAALgADCgIJAQAAAA==.Varnusshadow:BAAALgAECgEJAQAAAA==.',
Ve='Vearik:BAAALgAECgIJAgAAAA==.Velladoree:BAABLgAECn8bAAIUAAgJrQcEWwDuAAAUAAgJrQcEWwDuAAAAAA==.Vendaryn:BAAALgADCggJCAAAAA==.Vexahlia:BAAALgADCgMJAwAAAA==.',
Vg='Vgurlpally:BAAALgADCgYJBgAAAA==.',
Vy='Vynlorlan:BAAALgADCgMJAwABLgAECgMJBAAaAAAAAA==.',
Wa='Waveygravee:BAAALgAECgIJAwAAAA==.Wavygraivy:BAABLgAECn8YAAIbAAYJ2BWLSACAAQAbAAYJ2BWLSACAAQAAAA==.',
We='Wedragon:BAAALgAECgQJDgAAAA==.',
Wh='Wheelchair:BAACLgAFFH8LAAIIAAQJOxscZAAnAQAIAAQJOxscZAAnAQAuAAQKfxwAAggACAkSJF0SAA4DAAgACAkSJF0SAA4DAAAA.',
Wo='Woofwoof:BAAALgAFFAIJAgAAAA==.',
Wu='Wullemage:BAAALgADCgcJEwABLgAFFAYJHgAjAGkcAA==.',
['Wå']='Wåsp:BAABLgAECn86AAIGAAkJHg8iTwCNAQAGAAkJHg8iTwCNAQAAAA==.',
Xb='Xb:BAAALgAECgcJBQAAAA==.',
Xh='Xhexana:BAABLgAECn84AAIbAAkJTRc+GwBmAgAbAAkJTRc+GwBmAgABLgAECgkJPQAXABgTAA==.',
Xi='Xiaopo:BAAALgAECgEJAQABLgAFFAQJFgAbADEmAA==.',
Xr='Xrael:BAAALgAECgEJAQABLgAFFAMJEAAHACMiAA==.Xrayl:BAACLgAFFH8QAAMHAAMJIyKlEQAoAQAHAAMJIyKlEQAoAQAfAAMJxAz6NwC8AAAuAAQKfyMAAwcACQnoIAYNAGsCAAcACAmrIQYNAGsCAB8AAQmOG/N9AE8AAAAA.',
Xz='Xzerocool:BAABLgAECn8WAAQMAAgJvRNzggBgAQAMAAgJvRNzggBgAQAQAAIJshO+OQBqAAAcAAEJmQNKmAAiAAAAAA==.',
Ya='Yannii:BAAALgADCgcJDgAAAA==.',
Ye='Yenko:BAAALgADCgIJAgAAAA==.',
Yo='Yolo:BAAALgADCgcJCwAAAA==.Yoshikazu:BAAALgAECgYJCAAAAA==.Yoyoboy:BAAALgADCgEJAQAAAA==.',
Za='Zaarah:BAAALgAECgMJAwAAAA==.',
Ze='Zellek:BAAALgADCgEJAQAAAA==.Zendezoth:BAABLgAECn8jAAIWAAkJpRliAwBcAgAWAAkJpRliAwBcAgAAAA==.Zephik:BAAALgADCgEJAQAAAA==.Zerofrost:BAABLgAECn8qAAIBAAkJahjrNwAzAgABAAkJahjrNwAzAgAAAA==.Zevra:BAAALgADCgMJAwAAAA==.',
Zh='Zhiva:BAABLgAECn8sAAIDAAgJIQvzNQAyAQADAAgJIQvzNQAyAQAAAA==.',
Zu='Zul:BAACLgAFFH8WAAIjAAMJXiMZHwAZAQAjAAMJXiMZHwAZAQAuAAQKfzEAAyMACAkFJAsMANcCACMACAkFJAsMANcCACcAAQnLAkMiACQAAAAA.',
Zy='Zykoz:BAABLgAECn8uAAIjAAkJpCEBBAD3AgAjAAkJpCEBBAD3AgAAAA==.',
['Ða']='Ðamned:BAABLgAECn8YAAIRAAYJ8hvELgCnAQARAAYJ8hvELgCnAQABLgAFFAIJCAAIANMeAA==.',
['Ÿo']='Ÿoshi:BAABLgAECn8bAAIXAAgJhQ/8TQB/AQAXAAgJhQ/8TQB/AQAAAA==.',
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
