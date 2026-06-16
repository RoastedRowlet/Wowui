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

local lookup = {'Mage-Frost','Warlock-Destruction','Druid-Balance','Warlock-Demonology','Warlock-Affliction','DemonHunter-Devourer','Monk-Windwalker','DeathKnight-Unholy','DeathKnight-Blood','Warrior-Protection','Priest-Holy','Paladin-Retribution','Warrior-Fury','Warrior-Arms','Shaman-Enhancement','Paladin-Protection','Shaman-Elemental','Evoker-Preservation','DemonHunter-Vengeance','Monk-Mistweaver','Evoker-Augmentation','Evoker-Devastation','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Guardian','Unknown-Unknown','Shaman-Restoration','Paladin-Holy','Druid-Restoration','Priest-Shadow','Monk-Brewmaster','Druid-Feral','DeathKnight-Frost','Hunter-Survival','Rogue-Subtlety','Rogue-Outlaw','DemonHunter-Havoc','Priest-Discipline','Mage-Arcane','Mage-Fire','Rogue-Assassination',}
local provider = {region='US',realm="Vek'nilash",name='US',type='weekly',zone=46,date='2026-06-14',data={Ab='Abomination:BAAALgADCgMJAwAAAA==.',
Ad='Adune:BAAALgAECgQJBQAAAA==.',
Ae='Aeidail:BAACLgAFFH8dAAIBAAcJTRggJQDlAQABAAcJTRggJQDlAQAuAAQKfyoAAgEACAnUI0McAAUDAAEACAnUI0McAAUDAAAA.Aelaria:BAAALgADCgMJAwAAAA==.Aeviria:BAABLgAECn8oAAICAAgJtRVDCADHAQACAAgJtRVDCADHAQAAAA==.',
Ag='Agraceful:BAACLgAFFH8LAAIDAAMJEAfGNgCeAAADAAMJEAfGNgCeAAAuAAQKfx8AAgMACQm8EtoeAM4BAAMACQm8EtoeAM4BAAAA.',
Ai='Ailee:BAAALgAECgYJDAAAAA==.Aios:BAAALgAECgIJAgAAAA==.Aiza:BAACLgAFFH8MAAIEAAMJSQXriACwAAAEAAMJSQXriACwAAAuAAQKfzIAAwQACQkXFps4APcBAAQACQkXFps4APcBAAUAAQkAAMdHAAAAAAAA.',
Al='Alaber:BAAALgAECgUJCAAAAA==.Aldanil:BAAALgADCgMJAwAAAA==.Allarria:BAAALgADCgYJBwABLgAECgkJJgAGAFogAA==.',
Am='Ampersand:BAAALgAECgMJBQAAAA==.',
An='Animalfriend:BAAALgAECgIJBAAAAA==.Anklesmasher:BAABLgAECn8UAAIHAAcJ/A58OwARAQAHAAcJ/A58OwARAQAAAA==.Antonidus:BAAALgAECgUJCwAAAA==.Anyah:BAABLgAECn8YAAIDAAgJzwMFUwC/AAADAAgJzwMFUwC/AAAAAA==.',
Ap='Apolloo:BAAALgADCgMJAwAAAA==.',
Aq='Aquadora:BAAALgAECgEJAQAAAA==.',
Ar='Arfaz:BAABLgAECn8zAAMIAAgJNhsZQAABAgAIAAgJGBoZQAABAgAJAAYJWApKOACxAAAAAA==.Armbrost:BAAALgAECgYJCgAAAA==.Artimås:BAAALgADCgcJCAAAAA==.Arwynne:BAAALgADCgMJAwAAAA==.Arçano:BAAALgAECgEJAQABLgAECgkJGQAKADkTAA==.',
As='Ascension:BAAALgADCgcJBgABLgAECgkJPgAEAJ8kAA==.Astrastar:BAABLgAECn8bAAMEAAYJ0wKW4QCYAAAEAAYJ0wKW4QCYAAACAAEJcgDDgAAOAAAAAA==.',
Au='Auralyn:BAAALgADCgMJBQAAAA==.Aurius:BAAALgAECgcJAgAAAA==.',
Av='Avarin:BAAALgADCgEJAQAAAA==.',
Ay='Aymont:BAAALgAECgQJBQAAAA==.',
Ba='Baerd:BAABLgAECn8aAAILAAcJZhN2KwBqAQALAAcJZhN2KwBqAQAAAA==.Baji:BAAALgAECgkJBwAAAA==.Barlz:BAAALgAECgEJAQAAAA==.',
Be='Beanpaste:BAAALgAECgcJAQABLgAFFAMJEAAIAHcZAA==.Beanutbutter:BAAALgADCgIJAgABLgAFFAMJEAAIAHcZAA==.Beaty:BAAALgAECgIJAgAAAA==.Bebby:BAABLgAECn8cAAMJAAcJYgJFRgByAAAJAAYJPwJFRgByAAAIAAIJaQKicwEwAAAAAA==.Belonara:BAAALgAECgEJAQAAAA==.Belwolf:BAABLgAECn8UAAIIAAUJwAoX5QDMAAAIAAUJwAoX5QDMAAAAAA==.Bergstrom:BAABLgAECn80AAIMAAkJuhkuMAA+AgAMAAkJuhkuMAA+AgAAAA==.Bethanymarie:BAAALgAECgEJAQAAAA==.Betrayer:BAAALgADCgQJAwABLgAECgkJPgAEAJ8kAA==.',
Bi='Biancaneve:BAABLgAECn8XAAILAAcJUheCGwDpAQALAAcJUheCGwDpAQAAAA==.Bighero:BAACLgAFFH8QAAIGAAMJSQv/ZwC4AAAGAAMJSQv/ZwC4AAAuAAQKfyAAAgYACQk9EVlvAFYBAAYACQk9EVlvAFYBAAAA.Bigmike:BAAALgAECgEJAgAAAA==.',
Bl='Blakkjezus:BAAALgAECgcJCwAAAA==.Blessednugie:BAAALgAECgcJDgAAAA==.Blitzbolts:BAAALgAECgEJAgAAAA==.Bludo:BAACLgAFFH8QAAMNAAYJNBINIwAkAQANAAUJHRUNIwAkAQAOAAMJpAx4KQDCAAAuAAQKfx4AAw0ACQl6IWgZAIACAA0ACAk5GWgZAIACAA4ABgl9HFMYADYBAAAA.',
Bo='Boe:BAABLgAECn8mAAIPAAkJygmtEwB7AQAPAAkJygmtEwB7AQAAAA==.Bomba:BAAALgAECgUJCQAAAA==.Bombacløt:BAABLgAECn8wAAMEAAkJAxB9RQDJAQAEAAkJhg99RQDJAQACAAcJbg5XFAAIAQAAAA==.Bowdirte:BAAALgAECgUJBwAAAA==.',
Br='Brastin:BAABLgAECn86AAIQAAkJkyI0AgATAwAQAAkJkyI0AgATAwABLgAFFAUJEgARAIQMAA==.Brenell:BAACLgAFFH8IAAIBAAMJgRJuigDHAAABAAMJgRJuigDHAAAuAAQKfzoAAgEACQmwISoRAPICAAEACQmwISoRAPICAAAA.',
Bu='Bu:BAAALgAECgYJDQABLgAECgYJGwASALgdAA==.Bubblehearth:BAAALgAECgYJCQABLgAECgkJKwAGAHwaAA==.Buffet:BAABLgAECn8aAAIBAAYJ0BF3rAAlAQABAAYJ0BF3rAAlAQABLgAECgkJKwAGAHwaAA==.Buhlitz:BAAALgAECgEJAgAAAA==.Butterbean:BAAALgADCgMJBQAAAA==.',
By='Bynis:BAABLgAECn8gAAIGAAkJDRWXRwCtAQAGAAkJDRWXRwCtAQAAAA==.',
Ca='Cabëla:BAAALgADCgUJBQAAAA==.Cactusjack:BAAALgADCgUJBQAAAA==.Cadorex:BAAALgADCgEJAQAAAA==.Caffeinefree:BAAALgADCggJBwAAAA==.Calacolinda:BAAALgAECgQJBgAAAA==.Calamari:BAAALgAECgEJAQAAAA==.Cavakworm:BAAALgADCgEJAQAAAA==.Caylin:BAAALgADCgUJBgAAAA==.Cayusedemon:BAAALgADCgEJAQAAAA==.Cayusemage:BAAALgADCgkJFQAAAA==.Cayusevoid:BAAALgADCgcJBwAAAA==.',
Ce='Ceridwyn:BAAALgAECgQJBQAAAA==.',
Ch='Chariscrushr:BAAALgAECgQJCAABLgAFFAgJHgAHAAQZAA==.Chen:BAAALgADCgIJAgAAAA==.Choal:BAAALgAECgEJAQAAAA==.Chokaho:BAAALgAECgMJAwAAAA==.Chubberoni:BAAALgAECgUJBwAAAA==.',
Ci='Cinnamongirl:BAAALgAECgcJEgAAAA==.',
Co='Corahin:BAABLgAECn8bAAIRAAYJGxASRAA5AQARAAYJGxASRAA5AQAAAA==.Corious:BAAALgAECgQJCQAAAA==.Cosmos:BAAALgAECgYJDQAAAA==.Cougarhunter:BAAALgAECgkJEAAAAA==.',
Cr='Crixux:BAAALgADCgMJAQAAAA==.Crokus:BAAALgADCggJCAAAAA==.',
Cu='Cuecumba:BAABLgAECn8uAAITAAkJICZzAABcAwATAAkJICZzAABcAwAAAA==.',
Da='Daemonerror:BAAALgAECgUJBQABLgAECggJRQAUAKUjAA==.Dalren:BAACLgAFFH8YAAMVAAYJah7HGACYAQAVAAUJah7HGACYAQAWAAIJuwNtCwBLAAAuAAQKf0cAAxUACQnIJfkBAGIDABUACQnIJfkBAGIDABYABgnyIEMMABcCAAAA.Dalryn:BAAALgAECgYJDQABLgAFFAYJGAAVAGoeAA==.Dalvix:BAAALgADCgEJAQABLgAECgkJJgAGAFogAA==.Damocles:BAABLgAECn8YAAIBAAYJlwyOxgD9AAABAAYJlwyOxgD9AAAAAA==.Danazel:BAAALgADCgMJBQAAAA==.Dartagnan:BAACLgAFFH8OAAIXAAMJnhxYTgAJAQAXAAMJnhxYTgAJAQAuAAQKfycAAxcACQnLHQdIAMYBABcABwkLHwdIAMYBABgABgn3FEgbANEAAAAA.Darthmaul:BAABLgAECn8wAAIDAAkJyhF2HwDJAQADAAkJyhF2HwDJAQAAAA==.',
De='Deay:BAAALgADCgQJAQAAAA==.Delexa:BAAALgADCgkJQAAAAA==.Demonicnugie:BAAALgADCgEJAQAAAA==.Dendiian:BAABLgAECn8UAAIZAAYJXxWCJgAdAQAZAAYJXxWCJgAdAQAAAA==.',
Di='Didipullthat:BAAALgADCgYJFwABLgAECgkJKwAGAHwaAA==.Diem:BAABLgAECn8dAAIXAAgJyw1rQQCqAQAXAAgJyw1rQQCqAQAAAA==.Dirtydotss:BAABLgAECn8VAAMFAAcJFwfXEgD/AAAFAAYJYQbXEgD/AAAEAAYJ5wTsywC6AAAAAA==.Divigitives:BAAALgAECgQJBAAAAA==.',
Do='Docrivan:BAAALgAECgYJCwAAAA==.Docsassist:BAAALgAECgMJAwABLgAECgYJCwAaAAAAAA==.Doregit:BAABLgAECn8zAAINAAkJaR6iCwCtAgANAAkJaR6iCwCtAgAAAA==.Dowedoes:BAABLgAECn89AAIMAAkJghfxNQAnAgAMAAkJghfxNQAnAgAAAA==.',
Dr='Drachula:BAABLgAECn8bAAIbAAcJTRbxOgDAAQAbAAcJTRbxOgDAAQAAAA==.Dracultra:BAAALgAECgUJBwABLgAECgkJIAAcAF0fAA==.Drakcheese:BAAALgADCgUJBQAAAA==.Dreolan:BAABLgAECn9KAAIdAAkJJBg5FwCLAgAdAAkJJBg5FwCLAgAAAA==.Drynnai:BAAALgADCgEJAgAAAA==.',
Dy='Dyala:BAACLgAFFH8PAAMdAAMJjg8XQwCjAAAdAAMJjg8XQwCjAAADAAMJMwRwOQCOAAAuAAQKfyMAAx0ACQkDEgBmAAABAB0ACQkDEgBmAAABAAMABAkoDuZNANEAAAAA.',
['Dö']='Dönövan:BAABLgAECn8vAAIMAAkJnBNrRQD1AQAMAAkJnBNrRQD1AQAAAA==.',
El='Elastwo:BAAALgADCgcJEgAAAA==.Eloise:BAABLgAECn8ZAAILAAcJchAYLQBgAQALAAcJchAYLQBgAQAAAA==.Elvenbane:BAABLgAECn8nAAIeAAkJrRPQGwDmAQAeAAkJrRPQGwDmAQAAAA==.',
Em='Emily:BAAALgAECgYJDAAAAA==.Emry:BAAALgADCgYJBgABLgAECgcJHQAUADkPAA==.',
En='Enable:BAEBLgAECn8gAAIfAAkJVRw2CgCOAgAfAAkJVRw2CgCOAgABLgAECgkJNAAQAE8iAA==.',
Ep='Epictool:BAAALgAECggJCwAAAA==.',
Et='Ethereal:BAAALgAECgEJAQAAAA==.',
Ex='Extrathick:BAAALgAECgMJAwAAAA==.',
Fa='Fabel:BAEBLgAECn80AAIQAAgJTyI7BwBpAgAQAAgJTyI7BwBpAgAAAA==.Falahad:BAAALgAECgEJAQABLgAFFAMJDgADAD4OAA==.Faltree:BAACLgAFFH8OAAMDAAMJPg7OMgCxAAADAAMJPg7OMgCxAAAdAAIJuhUGUQB6AAAuAAQKfyEABB0ACQkeFf5TAFcBAB0ACAkrFP5TAFcBAAMACAkOF+IxAFEBACAAAQnfAUo6AB8AAAAA.Fathershale:BAAALgAECgMJAwAAAA==.',
Fi='Firelord:BAAALgADCgEJAQAAAA==.',
Fo='Foulcor:BAABLgAECn8dAAMcAAkJ7B5MFwBOAgAcAAgJlB5MFwBOAgAMAAcJRhFPlgBGAQAAAA==.',
Fr='Freakadeek:BAABLgAECn8VAAQhAAkJaw3xIADEAAAIAAUJ0Ajb1ADgAAAhAAMJnhfxIADEAAAJAAYJgwRnTQBZAAAAAA==.Freâkadeek:BAAALgAECgIJBAABLgAECgkJFQAhAGsNAA==.Freäk:BAAALgADCgMJAwABLgAECgkJFQAhAGsNAA==.Frieren:BAABLgAECn89AAIBAAkJ6xWcPgAfAgABAAkJ6xWcPgAfAgAAAA==.Frink:BAAALgAECgEJAQABLgAECgkJPQAiAOEkAA==.Frostlord:BAAALgAECgIJAgAAAA==.',
Fu='Fundetected:BAAALgAFFAIJAgABLgAECgkJKwAGAHwaAA==.Furyofthenug:BAAALgADCgcJCgAAAA==.Fuzzywuzzy:BAAALgAECgUJBQABLgAECgYJGwASALgdAA==.',
Ga='Gabbyo:BAABLgAECn8lAAIdAAkJ/AfqUwA+AQAdAAkJ/AfqUwA+AQAAAA==.Galadorn:BAABLgAECn8mAAIGAAkJWiCPDwDFAgAGAAkJWiCPDwDFAgAAAA==.Gallgamesh:BAAALgADCgIJAgAAAA==.Garfall:BAAALgAECgcJDgAAAA==.Garga:BAAALgADCgMJBAABLgAECgQJBAAaAAAAAA==.',
Ge='Geirvaldr:BAAALgAECgYJBgAAAA==.Gerdash:BAAALgAECgMJBAAAAA==.Gerred:BAACLgAFFH8GAAIOAAMJ6hTjIgDgAAAOAAMJ6hTjIgDgAAAuAAQKfx4AAw4ACAmZF4ESAM4BAA4ACAkBF4ESAM4BAA0ABAlFFC9kAMkAAAAA.',
Gh='Ghallow:BAABLgAECn8bAAIPAAgJahhqCgARAgAPAAgJahhqCgARAgAAAA==.Ghosty:BAACLgAFFH8JAAIjAAQJOxXWHwAhAQAjAAQJOxXWHwAhAQAuAAQKfyoAAiMABwlQICAUAAACACMABwlQICAUAAACAAAA.',
Gi='Gimp:BAAALgAECgEJAgAAAA==.',
Gl='Gladur:BAABLgAFFH8GAAMHAAYJyAxCHwDZAAAHAAUJtwxCHwDZAAAUAAEJmQEjYgAxAAABLgAFFAcJHQABAE0YAA==.',
Go='Goldenflame:BAAALgAECgUJBwAAAA==.Goldenlily:BAAALgAECgYJEgAAAA==.Goldenmunc:BAABLgAECn8tAAIBAAkJNxdbNQBBAgABAAkJNxdbNQBBAgAAAA==.Goldenone:BAAALgAECgQJBQAAAA==.Goldenpants:BAABLgAECn8nAAINAAkJjxPmIQDiAQANAAkJjxPmIQDiAQAAAA==.',
Gr='Grievous:BAABLgAECn89AAITAAkJOyWzAABLAwATAAkJOyWzAABLAwAAAA==.',
['Gû']='Gûrth:BAAALgADCgcJBwAAAA==.',
Ha='Hailmary:BAABLgAECn8oAAILAAkJEiV0AQCoAwALAAkJEiV0AQCoAwAAAA==.Halcrux:BAAALgAECgIJAgAAAA==.Halvard:BAAALgADCgMJBQAAAA==.Harusen:BAABLgAECn8cAAIkAAkJFR8/AgCmAgAkAAkJFR8/AgCmAgAAAA==.Havgnwltrav:BAAALgADCgcJBgAAAA==.',
He='Healaga:BAAALgAECgYJBgABLgAECggJMwAIADYbAA==.',
Hi='Hildalsind:BAAALgADCgkJCQABLgAFFAMJCQABAIMdAA==.',
Ho='Homestar:BAAALgADCgEJAQAAAA==.Hooll:BAAALgAECgIJAgAAAA==.Hornreaper:BAABLgAECn8bAAIVAAYJ5hfvJACVAQAVAAYJ5hfvJACVAQAAAA==.Hotshot:BAAALgAECgMJAwAAAA==.',
Hu='Hubbabubbajr:BAAALgAECgMJAwABLgAECgkJMwAdAIIbAA==.Hubert:BAAALgADCgEJAgAAAA==.Hurin:BAAALgAECgcJDgAAAA==.Huur:BAAALgAECgEJAQABLgAECgEJAQAaAAAAAA==.',
Hy='Hyetta:BAAALgAECgQJBgABLgAECgkJHAAkABUfAA==.Hyir:BAAALgADCgYJBwABLgAFFAQJGAAHAIUeAA==.',
Il='Ilavengu:BAAALgAECgIJAgABLgAFFAQJFgAbADEmAA==.Illiya:BAABLgAECn8UAAILAAUJ5QyOQwDZAAALAAUJ5QyOQwDZAAAAAA==.',
Ir='Irôn:BAAALgAECgEJAQAAAA==.',
Iu='Iutara:BAAALgAECgYJDAAAAA==.',
Ja='Jaalein:BAAALgADCgcJDgAAAA==.Jayonor:BAABLgAECn80AAQRAAkJthUIGgAPAgARAAkJthUIGgAPAgAPAAYJ9we4GgAeAQAbAAcJ5AYfcAAIAQAAAA==.',
Je='Jek:BAAALgAECgUJBQAAAA==.',
Jo='Joryu:BAAALgADCgIJAwAAAA==.',
Ju='Juicycucci:BAAALgAECgcJEgABLgAECgkJKwAGAHwaAA==.',
Ka='Kaevrielle:BAECLgAFFH8IAAITAAMJfBWPCADGAAATAAMJfBWPCADGAAAuAAQKfx4AAxMACQmOG1QHAAwCABMACQmOG1QHAAwCACUAAQlWCoV2ACcAAAAA.Kaison:BAABLgAECn8XAAMeAAkJEQgpMABdAQAeAAkJEQgpMABdAQAmAAcJBAsINABHAQABLgAECgkJIAAGAA0VAA==.Kaladîn:BAAALgAECgMJAwABLgAFFAcJHQABAE0YAA==.Kalii:BAAALgADCgQJBAAAAA==.Kamel:BAAALgADCgYJBgAAAA==.Kardin:BAAALgADCgEJAQAAAA==.Karwin:BAABLgAECn8bAAIBAAgJ/xQ7ZwCsAQABAAgJ/xQ7ZwCsAQAAAA==.Katakuri:BAAALgAECgEJAgAAAA==.',
Ke='Keeper:BAAALgAECgYJCwABLgAECgkJUwAMAFQlAA==.Keeperodark:BAAALgAECggJEgABLgAECgkJUwAMAFQlAA==.Keeperolight:BAABLgAECn9TAAMMAAkJVCW/BABSAwAMAAkJVCW/BABSAwAcAAEJgRgUkABAAAAAAA==.Kemanorel:BAAALgADCgcJDgABLgAECgkJJwAeAK0TAA==.',
Ki='Kianth:BAAALgADCgkJEgAAAA==.Killkat:BAABLgAECn8uAAIBAAkJgxjUNABDAgABAAkJgxjUNABDAgAAAA==.',
Ko='Kodera:BAABLgAECn8bAAMSAAYJuB21DQDyAQASAAYJuB21DQDyAQAWAAQJNxubDgAfAQAAAA==.Koojo:BAAALgAECgcJCAAAAA==.Kosma:BAAALgAECgYJBgAAAA==.Kovae:BAAALgADCgEJAQAAAA==.',
Kr='Kraken:BAAALgADCgUJBQAAAA==.',
Ku='Kusheddruid:BAAALgADCgMJBQAAAA==.',
Ky='Kyaritin:BAAALgAECgMJAwABLgAECgYJCgAaAAAAAA==.Kyokei:BAAALgAECgEJAQAAAA==.',
La='Laiho:BAAALgADCgUJCAAAAA==.Lans:BAABLgAECn8UAAQnAAkJIQ0hDQD4AAAnAAUJ2AkhDQD4AAABAAQJ1Q99ygD3AAAoAAQJAwkBCQDKAAAAAA==.Larew:BAACLgAFFH8FAAIMAAMJbgfvewC5AAAMAAMJbgfvewC5AAAuAAQKfy8AAgwACQnfGW8nAGUCAAwACQnfGW8nAGUCAAAA.Lazytemplar:BAAALgADCgMJAwABLgAECgYJCQAaAAAAAA==.',
Le='Lealla:BAABLgAECn89AAIDAAkJlCIkBQAIAwADAAkJlCIkBQAIAwAAAA==.Lechevalier:BAAALgAFFAEJAgABLgAECgkJKwAGAHwaAA==.Leodin:BAAALgAECgEJAgAAAA==.Leorus:BAAALgAECgIJAgAAAA==.Lethhunt:BAACLgAFFH8SAAMYAAYJPQ1nFQAUAQAYAAYJ9QpnFQAUAQAXAAIJWw4MGgCeAAAuAAQKfy4AAxgACQncHoAGACkCABgACQlgHoAGACkCABcAAgk+JFKHANIAAAAA.',
Li='Lilmistfox:BAAALgAECgUJBwABLgAFFAQJFgAbADEmAA==.Lioh:BAAALgAECgQJBAAAAA==.Lizardgang:BAAALgAECgYJEwAAAA==.',
Lo='Loganshu:BAAALgAECggJDAAAAA==.Lokan:BAACLgAFFH8QAAMiAAMJWRmeHADoAAAiAAMJWRmeHADoAAAXAAEJwgggpABFAAAuAAQKfywAAyIACQlHHk4IAJoCACIACQlHHk4IAJoCABcAAQn+ClgtATYAAAAA.Lots:BAACLgAFFH8QAAIEAAMJhht2ZQD3AAAEAAMJhht2ZQD3AAAuAAQKfycAAwQACQktItQpADMCAAQACAliItQpADMCAAIABAngHkcsAA0BAAAA.',
Lu='Ludacast:BAAALgADCgIJAgAAAA==.Ludafists:BAAALgADCgcJDAAAAA==.Ludakris:BAABLgAECn8eAAIQAAkJfxgoCwATAgAQAAkJfxgoCwATAgAAAA==.Lumanoth:BAAALgAECgYJBgAAAA==.',
Ly='Lyna:BAABLgAECn8gAAIbAAkJpRPqPgCvAQAbAAkJpRPqPgCvAQAAAA==.Lynaya:BAAALgADCgIJAgAAAA==.',
['Lí']='Líonheart:BAABLgAECn8dAAMcAAcJYBe6PQBNAQAcAAcJYBe6PQBNAQAMAAYJFgth0ADxAAAAAA==.',
['Lî']='Lîghtless:BAACLgAFFH8PAAIBAAYJBhqgGABoAQABAAYJBhqgGABoAQAuAAQKfxcAAgEACAmfJUchAO4CAAEACAmfJUchAO4CAAAA.',
['Lú']='Lúckally:BAAALgADCgQJBAABLgAECgYJCgAaAAAAAA==.Lúckÿ:BAAALgAECgYJCgAAAA==.',
Ma='Magetheo:BAAALgADCgIJAgAAAA==.Magicpanda:BAAALgAECgUJCwAAAA==.Mahina:BAAALgAECgIJAgAAAA==.Malik:BAAALgADCgIJAgAAAA==.Marcille:BAABLgAECn8nAAIBAAgJ2ROVdgCKAQABAAgJ2ROVdgCKAQAAAA==.Masyledian:BAAALgAECgIJAgAAAA==.Mathor:BAAALgAECgEJAgAAAA==.Mavrbg:BAAALgAECgQJBQAAAA==.Mayhaps:BAABLgAECn9EAAMXAAkJFRvPJgBCAgAXAAkJFRvPJgBCAgAYAAEJZACpmgAYAAAAAA==.',
Mc='Mcbain:BAABLgAECn89AAIiAAkJ4STIAQA/AwAiAAkJ4STIAQA/AwAAAA==.',
Me='Melinia:BAAALgAECgEJAQABLgAECgEJAgAaAAAAAA==.Melrine:BAAALgADCgMJAwAAAA==.Mentaltitty:BAABLgAECn8gAAIBAAkJgxLPSgD5AQABAAkJgxLPSgD5AQAAAA==.Meret:BAAALgADCgMJBQAAAA==.',
Mi='Minerwor:BAAALgAECgUJCQAAAA==.Mirrayla:BAAALgADCgYJBgAAAA==.Misty:BAAALgADCgYJBgAAAA==.',
Mm='Mmisty:BAABLgAECn9CAAIDAAkJghlZDwBnAgADAAkJghlZDwBnAgAAAA==.',
Mo='Moarthretplz:BAAALgAECgUJCQABLgAFFAQJFgAbADEmAA==.Mohji:BAAALgAFFAEJAQABLgAFFAcJGgAmAOwUAA==.Moldynuggets:BAAALgAECgEJAQAAAA==.Momometaru:BAABLgAECn8kAAQEAAkJgRYgQADcAQAEAAkJfhMgQADcAQACAAUJNhRyJgAsAQAFAAMJzxoxJgCMAAAAAA==.Monsterbee:BAABLgAECn9MAAIEAAkJ1BVxKwArAgAEAAkJ1BVxKwArAgAAAA==.',
Mu='Mustypizza:BAABLgAECn8uAAICAAkJihinBAAtAgACAAkJihinBAAtAgAAAA==.',
Mx='Mxicancowboy:BAAALgADCgEJAgAAAA==.',
My='Mystery:BAABLgAECn89AAMSAAkJNiC5AgAzAwASAAkJNiC5AgAzAwAWAAUJXhHWDwAKAQAAAA==.',
['Mê']='Mêøwzêr:BAAALgAECggJEwAAAA==.',
['Mÿ']='Mÿst:BAAALgAECgMJBAAAAA==.',
Na='Nak:BAAALgAECgYJBgAAAA==.Narashi:BAAALgAECgQJCAAAAA==.Naril:BAAALgADCgUJBQAAAA==.Nats:BAABLgAECn8kAAIbAAgJSxGwOACfAQAbAAgJSxGwOACfAQAAAA==.',
Ne='Neameny:BAABLgAECn89AAIXAAkJGBO7OgDxAQAXAAkJGBO7OgDxAQAAAA==.',
Ni='Nianji:BAAALgADCgYJDgAAAA==.Nightstar:BAAALgADCgMJAwAAAA==.Nightworld:BAAALgADCgcJDgAAAA==.',
No='Noctum:BAAALgAECgUJBQAAAA==.Nordicpally:BAAALgADCgQJBAAAAA==.Notbomba:BAAALgAECgEJAwAAAA==.Notgim:BAAALgADCggJCAAAAA==.',
Nu='Nualrossan:BAAALgADCgYJCAAAAA==.Nubrac:BAAALgAECgkJEwAAAA==.',
Ny='Nylux:BAAALgAECgYJDwAAAA==.',
Ob='Oblivion:BAABLgAECn8+AAMEAAkJnySNBgAnAwAEAAkJnySNBgAnAwACAAEJAABRXQBXAAAAAA==.',
Oo='Oostren:BAAALgAECgEJAgAAAA==.',
Or='Orsyp:BAAALgADCgkJGgAAAA==.',
Pa='Palockie:BAAALgADCgEJAQAAAA==.Pandas:BAABLgAECn8hAAIRAAkJAhH2JgCyAQARAAkJAhH2JgCyAQAAAA==.Partyrocker:BAABLgAECn8XAAIiAAcJag56KgBPAQAiAAcJag56KgBPAQABLgAECgkJFQAhAGsNAA==.',
Pi='Pixae:BAACLgAFFH8OAAISAAMJjwegIgCHAAASAAMJjwegIgCHAAAuAAQKfyEAAhIACAm5Cj0ZAD8BABIACAm5Cj0ZAD8BAAAA.Pixiechaos:BAAALgAECgQJCAAAAA==.',
Po='Poliahu:BAABLgAECn8XAAIXAAYJvQyAkgAXAQAXAAYJvQyAkgAXAQAAAA==.Porthoss:BAAALgADCggJDwAAAA==.Powerplant:BAACLgAFFH8XAAIXAAcJox+IDAD6AQAXAAcJox+IDAD6AQAuAAQKfyYAAhcACQkgJCgIAA4DABcACQkgJCgIAA4DAAAA.Poyoram:BAAALgADCgEJAQAAAA==.',
Pr='Pryi:BAAALgADCgcJBwABLgAFFAMJBwAMAO0IAA==.',
Py='Pyralys:BAABLgAECn85AAMLAAkJGBEWHADjAQALAAkJGBEWHADjAQAeAAMJqQKqhQAyAAAAAA==.',
Qu='Quizac:BAAALgADCgMJBQAAAA==.',
Ra='Ragemonk:BAAALgAECgUJDgABLgAECgYJCQAaAAAAAA==.Ragetality:BAAALgAECgYJCQAAAA==.Rakthera:BAAALgADCgcJBwAAAA==.Rallaster:BAAALgAECgYJBgABLgAECgkJJwAeAK0TAA==.Ramaria:BAAALgADCgkJCQABLgAECgkJJgAGAFogAA==.Raserei:BAABLgAFFH8IAAINAAMJIhfHLgDxAAANAAMJIhfHLgDxAAAAAA==.Rasputain:BAAALgADCgYJCgAAAA==.Rasputein:BAAALgADCgcJBwAAAA==.Rattelyr:BAAALgAECgYJDgAAAA==.Ravara:BAAALgADCgYJBgABLgAECgkJJgAGAFogAA==.Razgaurd:BAAALgAECgMJAwAAAA==.',
Re='Recolada:BAAALgAECgcJBwAAAA==.Regice:BAAALgAECgcJBwABLgAFFAQJDQAJAF4XAA==.Regicee:BAACLgAFFH8NAAIJAAQJXhd0GAAgAQAJAAQJXhd0GAAgAQAuAAQKf0MAAwkACQmEIk0EAPECAAkACQmEIk0EAPECAAgABAlJEHv7AK8AAAAA.Retam:BAAALgAECgcJDgAAAA==.Revakos:BAAALgADCgMJAwAAAA==.',
Rh='Rhysandra:BAAALgAECgQJCQAAAA==.',
Ri='Ribble:BAAALgADCgMJAwAAAA==.Riffraff:BAAALgAECgcJBAAAAA==.Rindou:BAAALgAECgkJBAAAAA==.Ripcord:BAAALgAECgUJCAAAAA==.Ripem:BAAALgADCgYJBgAAAA==.Ripperoni:BAAALgAECgcJDQAAAA==.Rizek:BAAALgAECgUJBgABLgAECgcJHQAUADkPAA==.Rizzx:BAAALgAECgEJAQAAAA==.',
Ro='Rockdyou:BAABLgAECn8nAAIIAAkJ+R66IwB1AgAIAAkJ+R66IwB1AgAAAA==.Roglef:BAAALgAECgQJCQAAAA==.Rotlobster:BAABLgAECn8aAAIFAAkJAB7nAQDGAgAFAAkJAB7nAQDGAgAAAA==.Roxxy:BAAALgAECgQJBAAAAA==.',
Ru='Rundvelt:BAACLgAFFH8QAAIQAAMJeA2gDgCSAAAQAAMJeA2gDgCSAAAuAAQKfyQAAhAACQlSEdYUAIABABAACQlSEdYUAIABAAAA.',
Sa='Sage:BAAALgADCgcJCAAAAA==.Sandwich:BAAALgAECgcJCAAAAA==.Saphíra:BAAALgAFFAIJAQABLgAFFAcJHQABAE0YAA==.Sapkick:BAAALgAECgQJBwAAAA==.',
Se='Serdragon:BAAALgADCgQJBAAAAA==.Servoid:BAAALgAECgUJCQAAAA==.',
Sh='Shando:BAAALgAECgEJAQAAAA==.Shiftstyle:BAEALgAECgEJAQAAAA==.Shtanky:BAACLgAFFH8OAAIKAAMJaBFuHQCmAAAKAAMJaBFuHQCmAAAuAAQKfyQAAgoACQnHD3YWAI8BAAoACQnHD3YWAI8BAAAA.',
Si='Silentsocks:BAAALgAECgUJDAAAAA==.Sixsixsix:BAAALgAECgcJCgABLgAFFAIJCAAIANMeAA==.',
Sk='Skoogz:BAABLgAECn8UAAMJAAYJbBS1JQAkAQAJAAYJCBS1JQAkAQAIAAQJ5A+C0gDjAAAAAA==.',
So='Soggyy:BAAALgADCgYJCwAAAA==.Solar:BAABLgAECn8VAAQHAAcJyRkxLwBtAQAHAAYJCxYxLwBtAQAfAAYJrhzoOABmAQAUAAEJUwLz0gAaAAAAAA==.Soulfulgingr:BAABLgAECn8XAAIRAAcJmgpLTQD9AAARAAcJmgpLTQD9AAAAAA==.',
St='Starlagosa:BAAALgADCgYJCQAAAA==.Sturm:BAAALgAECgMJAwAAAA==.Styx:BAAALgAECgMJAwAAAA==.',
Su='Sunbake:BAAALgAECgUJEQAAAA==.',
Sw='Sweetbbyraze:BAACLgAFFH8cAAMWAAUJLiGDBQAKAQAVAAUJFh0tIABXAQAWAAQJQCGDBQAKAQAuAAQKfyYAAxYACAkpIVIGAJACABYABwm8IVIGAJACABUAAwnyHCdqAJkAAAAA.',
Sy='Sylaena:BAABLgAECn8oAAIYAAgJVQrlEwAgAQAYAAgJVQrlEwAgAQAAAA==.Sylvrstorm:BAAALgAECgcJDQAAAA==.',
['Së']='Sërënity:BAAALgAECgUJEgAAAA==.',
['Sí']='Sín:BAAALgAECgcJDAABLgAFFAIJCAAIANMeAA==.',
Ta='Talipally:BAACLgAFFH8HAAIMAAMJ7QjneAC/AAAMAAMJ7QjneAC/AAAuAAQKfxwAAgwACQkyENZ3AH0BAAwACQkyENZ3AH0BAAAA.Talishammy:BAAALgAECgMJAwABLgAFFAMJBwAMAO0IAA==.Taliwhacker:BAAALgAFFAEJAQABLgAFFAMJBwAMAO0IAA==.Talonleafgrd:BAAALgAECgkJCgAAAA==.Tanaka:BAABLgAECn8gAAIIAAgJgBNSWQC4AQAIAAgJgBNSWQC4AQAAAA==.Tanisong:BAAALgAECgQJDAAAAA==.Tassadar:BAAALgAECgUJCAAAAA==.',
Te='Teldo:BAAALgADCgMJBQAAAA==.Tepeyollotl:BAAALgADCgEJAQAAAA==.Terayus:BAAALgADCgcJDAAAAA==.Teyliah:BAAALgADCgMJAwAAAA==.',
Tf='Tf:BAAALgAECgYJBgABLgAFFAIJCAAIANMeAA==.',
Th='Thekingpunch:BAABLgAECn9FAAMUAAgJpSOlBwAhAwAUAAgJpSOlBwAhAwAHAAEJahYgjQBCAAAAAA==.Thenle:BAAALgADCggJDgAAAA==.Thline:BAAALgADCgMJBQAAAA==.Thunderblitz:BAABLgAECn8rAAIcAAkJdglzMgCKAQAcAAkJdglzMgCKAQAAAA==.Thurmus:BAAALgADCgkJQAAAAA==.',
Ti='Tillwar:BAABLgAECn87AAINAAkJKh17EAB0AgANAAkJKh17EAB0AgAAAA==.Tinymonk:BAAALgAECgMJAwAAAA==.',
To='Tofu:BAACLgAFFH8IAAIIAAMJJxwMhAD8AAAIAAMJJxwMhAD8AAAuAAQKf0QAAwgACQlIHoUVAMUCAAgACQlIHoUVAMUCAAkABwmjFnEaAIkBAAAA.Tokanya:BAAALgAECgEJAQAAAA==.Tortillachip:BAAALgAECgEJAgAAAA==.Toxidot:BAAALgAECgEJAQAAAA==.',
Tr='Treibh:BAABLgAECn8qAAIdAAkJCxhhFwCJAgAdAAkJCxhhFwCJAgAAAA==.Trelephant:BAAALgAECgMJBQAAAA==.Trulydps:BAABLgAECn8tAAIXAAkJPhROLgAhAgAXAAkJPhROLgAhAgAAAA==.Trulyog:BAAALgAECgQJBAABLgAECgkJLQAXAD4UAA==.',
Tu='Tubbsmcgee:BAACLgAFFH8YAAIbAAYJ6x9TBwBGAgAbAAYJ6x9TBwBGAgAuAAQKfyUAAhsACQkrJLgHAPkCABsACQkrJLgHAPkCAAEuAAUUBgkYABsA6x8A.Tukkit:BAAALgAECgYJDgAAAA==.',
Tw='Twistedshot:BAAALgADCggJCAAAAA==.Twizzler:BAABLgAECn9RAAIBAAkJZQiafQB6AQABAAkJZQiafQB6AQAAAA==.',
Ty='Tyraniik:BAAALgADCgYJCAAAAA==.',
['Të']='Tërris:BAABLgAECn8cAAIJAAkJQBFRGgCKAQAJAAkJQBFRGgCKAQAAAA==.',
['Tî']='Tîlldeath:BAAALgAECgUJBwAAAA==.',
Uj='Uji:BAAALgADCgEJAQAAAA==.',
Ur='Urowndad:BAAALgAECgUJBQABLgAECggJFgAMAL0TAA==.Urownmother:BAAALgADCgUJBQABLgAECggJFgAMAL0TAA==.',
Va='Vaellian:BAAALgAECgYJDAAAAA==.Vallez:BAECLgAFFH8TAAMcAAMJoh/7IgADAQAcAAMJoh/7IgADAQAMAAMJ/g15cADNAAAuAAQKfyoAAxwACQmqHdQRAIQCABwACQmqHdQRAIQCAAwAAwmiDeBCAWYAAAAA.Vanillaghost:BAAALgADCgIJAQAAAA==.Varnusshadow:BAAALgAECgQJBAAAAA==.',
Ve='Vearik:BAAALgAECgQJBgAAAA==.Velladoree:BAABLgAECn8gAAIUAAgJiwlDWAALAQAUAAgJiwlDWAALAQAAAA==.Vendaryn:BAAALgADCggJCAAAAA==.Vexahlia:BAAALgADCgMJAwAAAA==.',
Vg='Vgurlpally:BAAALgADCgYJBgAAAA==.',
Vy='Vynlorlan:BAAALgADCgMJAwABLgAECgMJBAAaAAAAAA==.',
Wa='Walkindead:BAAALgAECgQJBgAAAA==.Waveygravee:BAAALgAECgIJAwAAAA==.Wavyghoul:BAAALgAECgEJAQAAAA==.Wavygraivy:BAABLgAECn8bAAIbAAYJ2BVKSwCAAQAbAAYJ2BVKSwCAAQAAAA==.',
We='Wedragon:BAAALgAECgQJDgAAAA==.',
Wh='Wheelchair:BAACLgAFFH8LAAIIAAQJOxtIbQAeAQAIAAQJOxtIbQAeAQAuAAQKfxwAAggACAkSJF0SAA4DAAgACAkSJF0SAA4DAAAA.',
Wo='Woofwoof:BAAALgAFFAIJAgAAAA==.',
Wu='Wullemage:BAAALgADCgcJEwABLgAFFAYJHgAjAGkcAA==.',
['Wå']='Wåsp:BAABLgAECn9HAAIGAAkJuQ9kTwCVAQAGAAkJuQ9kTwCVAQAAAA==.',
Xb='Xb:BAAALgAECgcJBQAAAA==.',
Xh='Xhexana:BAABLgAECn84AAIbAAkJTRebHABlAgAbAAkJTRebHABlAgABLgAECgkJPQAXABgTAA==.',
Xi='Xiaopo:BAAALgAECgEJAQABLgAFFAQJFgAbADEmAA==.',
Xr='Xrael:BAAALgAECgEJAQABLgAFFAMJEgAHACMiAA==.Xrayl:BAACLgAFFH8SAAMHAAMJIyL3EgAhAQAHAAMJIyL3EgAhAQAfAAMJxAyAOgC5AAAuAAQKfyUAAwcACQnoIJYNAGoCAAcACAmrIZYNAGoCAB8AAQmOG/N9AE8AAAAA.',
Xz='Xzerocool:BAABLgAECn8WAAQMAAgJvRNFhwBgAQAMAAgJvRNFhwBgAQAQAAIJshPMOwBqAAAcAAEJmQNgnAAiAAAAAA==.',
Ya='Yannii:BAAALgADCgcJDgAAAA==.',
Ye='Yenko:BAAALgADCgIJAgAAAA==.',
Yo='Yolo:BAAALgADCgcJCwAAAA==.Yoshikazu:BAAALgAECgYJCAAAAA==.Yoyoboy:BAAALgADCgEJAQAAAA==.',
Za='Zaarah:BAAALgAECgMJBgAAAA==.',
Ze='Zellek:BAAALgADCgEJAQAAAA==.Zendezoth:BAABLgAECn8jAAIWAAkJpRmNAwBZAgAWAAkJpRmNAwBZAgAAAA==.Zephik:BAAALgADCgEJAQAAAA==.Zerofrost:BAABLgAECn8qAAIBAAkJahjOOwAoAgABAAkJahjOOwAoAgAAAA==.Zerrìc:BAAALgADCgUJBQAAAA==.Zevra:BAAALgADCgMJAwAAAA==.',
Zh='Zhiva:BAABLgAECn8zAAIDAAgJoQz/NABAAQADAAgJoQz/NABAAQAAAA==.',
Zu='Zul:BAACLgAFFH8YAAIjAAMJXiPDIQARAQAjAAMJXiPDIQARAQAuAAQKfzMAAyMACQkwI88HAKoCACMACQkwI88HAKoCACkAAQnLAkMiACQAAAAA.',
Zy='Zykoz:BAABLgAECn8uAAIjAAkJpCF6BAD0AgAjAAkJpCF6BAD0AgAAAA==.',
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
