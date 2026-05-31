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

local lookup = {'Paladin-Holy','DemonHunter-Devourer','Rogue-Subtlety','Rogue-Outlaw','DemonHunter-Havoc','Hunter-BeastMastery','Paladin-Retribution','DeathKnight-Unholy','Mage-Frost','Hunter-Marksmanship','Warlock-Demonology','Paladin-Protection','Druid-Restoration','Unknown-Unknown','Warrior-Fury','Shaman-Enhancement','Rogue-Assassination','Hunter-Survival','Monk-Windwalker','Monk-Brewmaster','Warrior-Protection','Druid-Balance','DeathKnight-Frost','Druid-Guardian','Druid-Feral','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Blood','Priest-Holy','Mage-Arcane','Warrior-Arms','Priest-Discipline','Warlock-Destruction','Shaman-Restoration','Shaman-Elemental','Priest-Shadow','DemonHunter-Vengeance','Evoker-Preservation','Warlock-Affliction','Monk-Mistweaver',}
local provider = {region='US',realm='Nathrezim',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Abysm:BAAALgADCgkJDwAAAA==.',
Ac='Achillios:BAAALgADCgMJAwABLgAFFAQJBgABAFUTAA==.',
Ad='Adorabull:BAAALgAECgQJBgABLgAECgkJIQACAKsdAA==.',
Ae='Aemun:BAABLgAECn8/AAMDAAkJShzECACDAgADAAkJShzECACDAgAEAAYJlAmwCAD2AAAAAA==.',
Ag='Aggfu:BAAALgADCgYJBgAAAA==.',
Ak='Akeeli:BAAALgADCgQJBAAAAA==.Akelita:BAABLgAECn8hAAMFAAYJrxhXIABRAQAFAAYJrxhXIABRAQACAAUJcAjUvQCMAAAAAA==.',
Al='Alailea:BAABLgAECn89AAIGAAkJKxQmNQDxAQAGAAkJKxQmNQDxAQAAAA==.Alragnar:BAAALgAECgIJAgAAAA==.Alwysafkable:BAAALgAFFAEJAQAAAA==.',
Am='Amageadin:BAAALgADCgkJCQAAAA==.Amazadin:BAACLgAFFH8GAAIBAAQJVRMlIAAGAQABAAQJVRMlIAAGAQAuAAQKfxkAAwEACAkpHO8bADUCAAEACAkpHO8bADUCAAcAAgncEkMTAX4AAAAA.Amazashock:BAAALgAECgUJDQABLgAFFAQJBgABAFUTAA==.',
An='Andiwin:BAABLgAECn8ZAAIIAAgJ9Q85XQCcAQAIAAgJ9Q85XQCcAQAAAA==.Andurthil:BAABLgAECn8oAAIJAAgJUw00hABUAQAJAAgJUw00hABUAQAAAA==.Anzul:BAAALgAECgUJBgAAAA==.',
Ar='Archive:BAAALgAECgkJCwAAAA==.Artistic:BAABLgAECn8cAAIGAAgJeBlmNgDsAQAGAAgJeBlmNgDsAQAAAA==.Arubion:BAAALgAECggJDAAAAA==.Arylanna:BAAALgAECgYJDQAAAA==.',
As='Asure:BAABLgAECn8tAAMGAAkJ/hf9IgBBAgAGAAkJ/hf9IgBBAgAKAAYJTgfdTwAPAQAAAA==.',
Az='Azerith:BAAALgAECgYJDwAAAA==.',
Ba='Badmorda:BAAALgADCgEJAQAAAA==.',
Be='Bearforceone:BAAALgADCgMJAwAAAA==.',
Bi='Bipolar:BAAALgADCgEJAQAAAA==.',
Bl='Blackheart:BAABLgAECn8bAAILAAgJnBjCLQBWAgALAAgJnBjCLQBWAgAAAA==.Blodreina:BAAALgADCgUJCQAAAA==.Bloodarchon:BAABLgAECn8dAAMHAAgJUBRiZwCHAQAHAAgJUBRiZwCHAQAMAAYJnQlJLACiAAAAAA==.Bloodtemplar:BAABLgAECn8kAAIHAAgJhhXXTgDDAQAHAAgJhhXXTgDDAQAAAA==.',
Bo='Bombs:BAAALgAECgQJEAABLgAFFAQJBQANAD4FAA==.Bonesy:BAAALgAECgYJBgAAAA==.Bouren:BAAALgAECgEJAQAAAA==.',
Br='Bravia:BAAALgADCgUJBwAAAA==.Brewdogg:BAAALgADCgcJBwAAAA==.Brutalitops:BAAALgADCgMJAwAAAA==.Brutusdabull:BAAALgAECgYJBgAAAA==.Brônze:BAAALgADCgQJBAAAAA==.',
Bu='Burdomew:BAAALgADCgEJAQAAAA==.',
Ca='Cadbury:BAAALgADCgIJAgABLgAECgUJCAAOAAAAAA==.Canan:BAAALgAECgUJBgAAAA==.Canestoast:BAAALgAECgEJAQAAAA==.Casmina:BAABLgAECn8WAAIPAAkJ7xlRIQBJAgAPAAkJ7xlRIQBJAgAAAA==.Castiell:BAAALgADCgUJBgAAAA==.Catalystic:BAAALgADCgEJAQAAAA==.Catd:BAAALgAECgEJAQAAAA==.',
Ce='Celum:BAABLgAECn8cAAIIAAYJcQgEvQDqAAAIAAYJcQgEvQDqAAAAAA==.Ceola:BAAALgAECgQJEAAAAA==.',
Ch='Chamming:BAAALgADCgIJAgAAAA==.Chaquén:BAABLgAECn8fAAIQAAkJ3Bd4CAAiAgAQAAkJ3Bd4CAAiAgAAAA==.Charizard:BAAALgAECgEJAQAAAA==.Charmander:BAABLgAECn8fAAQRAAYJshfzCgCAAQARAAYJshfzCgCAAQADAAQJUgnvQACYAAAEAAMJ2wRFGAB2AAAAAA==.Chaw:BAACLgAFFH8ZAAMSAAcJ3h+7AQAMAgASAAcJwxm7AQAMAgAGAAEJcCamIQBdAAAuAAQKfzIABBIACQnuJDUDAP4CABIACQnsJDUDAP4CAAoABwnWHy0iABQCAAYABAk3I1BIAJEBAAAA.Chenkenichi:BAABLgAECn8dAAMTAAkJPwf/LwAwAQATAAkJPwf/LwAwAQAUAAUJKAKraACfAAAAAA==.Chergar:BAACLgAFFH8MAAIVAAUJkhvTDgAjAQAVAAUJkhvTDgAjAQAuAAQKfx4AAhUACQkVIkwFAOkCABUACQkVIkwFAOkCAAAA.Chskie:BAAALgADCgUJBQAAAA==.Chsky:BAAALgADCgUJBQAAAA==.Chuiyi:BAAALgAECgEJAgAAAA==.',
Ci='Cinny:BAABLgAECn9BAAIGAAkJvRrBGwBpAgAGAAkJvRrBGwBpAgAAAA==.Cinnyrolls:BAABLgAECn8XAAMWAAgJ/xsbGQDrAQAWAAgJ/xsbGQDrAQANAAQJtBBhhwDHAAAAAA==.Cityairlines:BAABLgAECn8nAAIXAAkJuRQyCgCvAQAXAAkJuRQyCgCvAQAAAA==.',
Cl='Clare:BAAALgAECgYJCQAAAA==.',
Cm='Cmoneyy:BAAALgAECgQJBQAAAA==.',
Co='Cogrolls:BAAALgAECggJCAAAAA==.Cooldukenuke:BAACLgAFFH8KAAIBAAMJqRf4DwDaAAABAAMJqRf4DwDaAAAuAAQKfycAAgEACQmjHDoTAHkCAAEACQmjHDoTAHkCAAAA.',
Cr='Creepychalk:BAAALgAECgYJEQAAAA==.Criticize:BAABLgAECn8nAAIHAAgJ1gx0jAA9AQAHAAgJ1gx0jAA9AQAAAA==.',
Cs='Csor:BAAALgAECgMJAwAAAA==.Csorb:BAABLgAECn8xAAMYAAkJ8SD2AwDJAgAYAAkJviD2AwDJAgAZAAEJySUqMgBrAAAAAA==.Csoren:BAAALgAECgEJAQAAAA==.Csoro:BAAALgADCggJCAAAAA==.',
Cu='Cultivation:BAAALgAECgUJCAAAAA==.Cursedcanfly:BAACLgAFFH8YAAIaAAcJ6ByLCQAgAgAaAAcJ6ByLCQAgAgAuAAQKfzMAAxoACQnjJfcBAFEDABoACQnjJfcBAFEDABsABQnaFG8iABcBAAAA.',
Cw='Cw:BAAALgAECgEJAQAAAA==.',
De='Deathdogg:BAACLgAFFH8VAAMIAAUJxxlyTAA6AQAIAAQJxxlyTAA6AQAcAAEJAAB1RwAAAAAuAAQKfykAAggACQlPICguADMCAAgACQlPICguADMCAAAA.Dejavu:BAACLgAFFH8YAAIUAAUJRhSpHAAoAQAUAAUJRhSpHAAoAQAuAAQKfykAAhQACQlAHY4YANEBABQACQlAHY4YANEBAAAA.Demivoi:BAAALgAECgYJBwAAAA==.Demona:BAAALgAECgEJAQAAAA==.Deppthcharge:BAAALgAECgYJDwAAAA==.Desdemona:BAAALgAECgYJCgAAAA==.Devimon:BAAALgADCgEJAQAAAA==.Devoi:BAAALgADCgEJAQAAAA==.',
Do='Donrain:BAAALgAECgQJBAAAAA==.Dooghammer:BAABLgAECn8ZAAIQAAkJQxpWCAAmAgAQAAkJQxpWCAAmAgAAAA==.',
Dr='Dragussy:BAAALgADCgcJDQABLgAECgkJPgAVAFUmAA==.',
Du='Dunkhan:BAAALgAECgEJAQABLgAECgYJDAAOAAAAAA==.Duplexity:BAABLgAECn8+AAIVAAkJVSZOAAB9AwAVAAkJVSZOAAB9AwAAAA==.',
Dw='Dwalin:BAAALgAECgMJCAABLgAECgkJGQAQAEMaAA==.',
Ea='Eatmoorchikn:BAAALgAECgUJBQAAAA==.',
Ec='Ecko:BAAALgAECgEJAQAAAA==.',
Ed='Edolah:BAAALgAECgEJAQAAAA==.',
Eg='Egohakai:BAACLgAFFH8RAAIHAAUJrx07LQA7AQAHAAUJrx07LQA7AQAuAAQKfzAAAgcACQkUJYoGACkDAAcACQkUJYoGACkDAAAA.',
El='Eloi:BAABLgAECn8VAAIdAAgJbyANCADYAgAdAAgJbyANCADYAgABLgAECgkJLgANAH8cAA==.',
Em='Emieretta:BAABLgAECn81AAIIAAkJ6hUaPgD3AQAIAAkJ6hUaPgD3AQAAAA==.',
Eq='Eqdk:BAABLgAECn8aAAIIAAkJ8RKQSwDNAQAIAAkJ8RKQSwDNAQAAAA==.',
Er='Erret:BAACLgAFFH8SAAIJAAUJxhd1UAAwAQAJAAUJxhd1UAAwAQAuAAQKfzIAAwkACQlwI8gJABgDAAkACQlwI8gJABgDAB4AAQngGdkQAEgAAAAA.',
Ey='Eyrie:BAAALgADCgYJBgAAAA==.',
Ez='Ezinder:BAAALgAECgcJEwAAAA==.',
Fa='Fabius:BAAALgADCgYJBgAAAA==.Faemos:BAAALgAECgkJBgAAAA==.Faience:BAABLgAECn8lAAIXAAkJIQQIGwDEAAAXAAkJIQQIGwDEAAAAAA==.Falorina:BAABLgAECn8nAAMFAAgJ9CEpCACRAgAFAAgJ9CEpCACRAgACAAEJAwXh6wAnAAAAAA==.Fathernature:BAACLgAFFH8FAAIWAAMJAw6fKgCzAAAWAAMJAw6fKgCzAAAuAAQKfx0AAxYACQknGd4oALgBABYACQknGd4oALgBABkAAQl5Bfw4ACUAAAAA.Fauna:BAAALgADCgMJAwAAAA==.Fazeup:BAAALgAECgcJBgAAAA==.',
Fe='Feldra:BAABLgAECn8xAAICAAkJrCA9DADTAgACAAkJrCA9DADTAgAAAA==.Felfaith:BAAALgAECgIJAgAAAA==.Fester:BAAALgADCgUJBQABLgAECgkJJgALAJ0WAA==.',
Fi='Fightforbeer:BAAALgAECgEJAQAAAA==.Finnin:BAABLgAECn8jAAMPAAkJCSQPCQC9AgAPAAkJCSQPCQC9AgAfAAEJ0gZ8SAAkAAAAAA==.',
Fo='Food:BAABLgAECn8mAAIGAAkJoRgrIQA/AgAGAAkJoRgrIQA/AgAAAA==.Formidabull:BAAALgAECgEJAQABLgAECgkJIQACAKsdAA==.Foxdiez:BAAALgAECggJEQAAAA==.',
Fr='Fredde:BAAALgADCgEJAQAAAA==.Freidafondle:BAAALgAECgYJEgAAAA==.Frostbite:BAAALgAECgcJCQAAAA==.Frozenfaith:BAABLgAECn8mAAMgAAkJUwtGKgBeAQAgAAgJ1gtGKgBeAQAdAAMJMgSHXABPAAAAAA==.',
Ft='Fthemeta:BAAALgADCgIJAgAAAA==.',
Fu='Furioushealz:BAABLgAECn8nAAIHAAkJpxneNQARAgAHAAkJpxneNQARAgAAAA==.Furiouswind:BAAALgADCgEJAQAAAA==.',
Ga='Gardrius:BAAALgADCgYJBwAAAA==.',
Gh='Ghettomike:BAABLgAECn8pAAIIAAkJAB4NLwAvAgAIAAkJAB4NLwAvAgAAAA==.Ghoulbane:BAAALgADCgYJCgAAAA==.',
Gi='Gibbits:BAAALgAECgcJCQAAAA==.Giranimo:BAABLgAECn8fAAIGAAgJghJvSgCqAQAGAAgJghJvSgCqAQAAAA==.',
Gl='Glabados:BAAALgAECgIJAwABLgAECgkJJwAUADciAA==.Glossy:BAACLgAFFH8eAAMDAAYJlSE5BwDoAQADAAYJlSE5BwDoAQAEAAMJ4hBJCgCWAAAuAAQKfzIABAMACQmEJkUBAFsDAAMACQmEJkUBAFsDABEAAgkNHzAUALsAAAQAAgmEIX4TALgAAAAA.Glossycumbus:BAAALgADCgYJBgABLgAFFAYJHgADAJUhAA==.Glossydh:BAAALgAECgYJBgABLgAFFAYJHgADAJUhAA==.Glossydk:BAAALgAECgQJBQABLgAFFAYJHgADAJUhAA==.Glossylock:BAAALgADCgcJDQABLgAFFAYJHgADAJUhAA==.',
Go='Golbigold:BAAALgAECgEJAQAAAA==.Goopy:BAAALgAECgMJAwAAAA==.',
Gr='Grayhoff:BAABLgAECn8cAAIPAAkJkAv5KgCVAQAPAAkJkAv5KgCVAQAAAA==.Greatclaw:BAAALgADCgMJAwAAAA==.Grewsom:BAACLgAFFH8VAAIHAAQJNyJ2FQCNAQAHAAQJNyJ2FQCNAQAuAAQKfywAAwcACAniJWMJAEYDAAcACAniJWMJAEYDAAwABQnzIGIUAG4BAAAA.',
Gu='Gulmok:BAAALgADCgUJBQAAAA==.Guwugga:BAABLgAECn8cAAIhAAYJ4hJyEQAUAQAhAAYJ4hJyEQAUAQAAAA==.',
Ha='Halîk:BAABLgAECn8XAAIBAAkJvhwJLADXAQABAAkJvhwJLADXAQAAAA==.Haraka:BAAALgAECgMJBAAAAA==.Harmshock:BAABLgAECn89AAIQAAkJhCQcAgDyAgAQAAkJhCQcAgDyAgAAAA==.Hathina:BAACLgAFFH8UAAMPAAcJSh6lBQDMAQAPAAYJcyKlBQDMAQAfAAEJfAlPMgBMAAAuAAQKfzMAAw8ACQnTJs4AAHcDAA8ACQnTJs4AAHcDAB8AAwmCHykeAP4AAAAA.',
He='Heket:BAABLgAECn8qAAIHAAgJmAesrQAGAQAHAAgJmAesrQAGAQAAAA==.Hektric:BAAALgAECgMJAwAAAA==.Helpinghandz:BAAALgAECgYJBgABLgAFFAUJFgAPAFgZAA==.',
Hi='Highdra:BAAALgAECgYJDgAAAA==.Hill:BAABLgAECn8oAAIGAAkJhR/7FgCAAgAGAAkJhR/7FgCAAgAAAA==.Hive:BAABLgAECn8vAAIPAAkJThgwEgBPAgAPAAkJThgwEgBPAgAAAA==.',
Ho='Holygem:BAAALgAECgYJCgAAAA==.Holypower:BAAALgADCgcJDQAAAA==.Hotdogwater:BAABLgAECn8nAAMiAAgJdyPECAAPAwAiAAgJdyPECAAPAwAjAAQJ5gn0bQB/AAAAAA==.',
Hu='Husentar:BAABLgAECn85AAIJAAkJ8CD7EQDaAgAJAAkJ8CD7EQDaAgAAAA==.Huuhablo:BAABLgAECn9AAAICAAkJjRzLFQCBAgACAAkJjRzLFQCBAgAAAA==.',
Ic='Icaron:BAAALgAECgcJDgAAAA==.',
Ig='Igothots:BAAALgAECgUJCgAAAA==.',
Il='Illuminottey:BAABLgAECn8UAAIHAAkJmQ87hQBKAQAHAAkJmQ87hQBKAQAAAA==.',
In='Inferium:BAAALgADCgYJBgABLgAFFAQJDwAOAAAAAA==.Infernom:BAAALgADCgMJAwABLgAFFAQJDwAOAAAAAA==.Insatiabull:BAABLgAECn8hAAMCAAkJqx2+EgDqAgACAAgJ7x6+EgDqAgAFAAEJyxShVwBCAAAAAA==.',
Io='Iolchsk:BAAALgAECgQJDAAAAA==.',
Is='Ishaa:BAAALgAECgYJCAAAAA==.',
Ja='Jacksof:BAABLgAECn8UAAMkAAYJ7gVxVwCKAAAkAAYJ7gVxVwCKAAAgAAQJOQQCXgBVAAAAAA==.Jackstands:BAABLgAECn9IAAMiAAkJmSGZBQBFAwAiAAkJmSGZBQBFAwAQAAgJgAXGGAAaAQAAAA==.Jagerin:BAAALgAECgYJCwABLgAECgkJJwAUADciAA==.January:BAAALgAECgYJBgABLgAFFAUJEQAGABoVAA==.Jasmyne:BAAALgADCgYJBgAAAA==.',
Je='Jeromy:BAAALgAECgEJAQAAAA==.Jesse:BAAALgADCgIJAgAAAA==.',
Ji='Jiffi:BAABLgAECn8ZAAIlAAgJyRrwBQA8AgAlAAgJyRrwBQA8AgAAAA==.Jinksy:BAAALgAECgUJDQAAAA==.',
Jm='Jme:BAAALgAECgcJCQAAAA==.',
Jr='Jredz:BAAALgADCgEJAQAAAA==.',
Ju='Jubag:BAAALgADCgIJAgAAAA==.Jumpercables:BAAALgAECgEJBAAAAA==.Junn:BAABLgAECn8nAAIjAAkJmBO8IQC9AQAjAAkJmBO8IQC9AQAAAA==.',
['Já']='Jánuary:BAAALgAECgUJBQAAAA==.',
Ka='Kahayman:BAACLgAFFH8MAAIJAAMJsggDeADSAAAJAAMJsggDeADSAAAuAAQKfzEAAgkACQmDGSAnAGgCAAkACQmDGSAnAGgCAAAA.Karellen:BAABLgAECn8UAAMbAAgJTgwtCgBpAQAbAAgJTgwtCgBpAQAaAAUJlAS9aQByAAAAAA==.Kathren:BAAALgAECgYJBgAAAA==.',
Kh='Khathani:BAAALgAECgUJDgAAAA==.',
Ki='Kieran:BAAALgAECgMJAwAAAA==.Kirara:BAAALgAECgMJAwAAAA==.',
Kn='Knobgoblinn:BAAALgAECgQJBAAAAA==.',
Ko='Komojo:BAABLgAECn8lAAIHAAgJXRCOcwBtAQAHAAgJXRCOcwBtAQAAAA==.Koriggan:BAABLgAECn8uAAQSAAkJoRHTEQAPAgASAAkJoRHTEQAPAgAGAAYJKhB6VQBoAQAKAAEJ6QBlmwAUAAAAAA==.',
Kr='Krea:BAABLgAECn8wAAIMAAkJECJdAgD6AgAMAAkJECJdAgD6AgAAAA==.Krixx:BAAALgADCgEJAQAAAA==.Krystagosa:BAABLgAECn83AAQmAAkJ1RSwCQA5AgAmAAkJ1RSwCQA5AgAaAAYJJg94RgDtAAAbAAMJVApQFwCLAAAAAA==.',
Ku='Kuriuh:BAABLgAECn8mAAILAAkJnRbKNAD5AQALAAkJnRbKNAD5AQAAAA==.Kurtcobainn:BAAALgADCgkJCQAAAA==.',
La='Lang:BAABLgAECn85AAIlAAkJSB1SAwCTAgAlAAkJSB1SAwCTAgAAAA==.',
Le='Legionslamm:BAAALgADCgUJBQAAAA==.Leonldas:BAAALgADCgEJAQAAAA==.',
Li='Lightsfaith:BAAALgADCgYJBgABLgAECgkJJgAgAFMLAA==.',
Lo='Lodix:BAAALgAFFAIJAwAAAA==.Loopey:BAAALgAECgcJEAABLgAFFAUJGAAUAEYUAA==.Lorethil:BAAALgAECgYJDAAAAA==.',
Lu='Luceriss:BAABLgAECn8fAAIDAAkJtA5MGAC/AQADAAkJtA5MGAC/AQAAAA==.Luminous:BAAALgADCgcJCAABLgAECgkJJgALAJ0WAA==.',
Ma='Maeroth:BAAALgADCgUJBQABLgAFFAcJFQALAO8MAA==.Magicboi:BAABLgAECn8WAAIJAAYJsw+fsAAFAQAJAAYJsw+fsAAFAQAAAA==.Magwar:BAACLgAFFH8QAAIPAAYJrxZJCwCJAQAPAAYJrxZJCwCJAQAuAAQKfzEAAg8ACQlXIUEHANoCAA8ACQlXIUEHANoCAAAA.Maike:BAABLgAECn8oAAMRAAgJfRWyBwDFAQARAAgJQBSyBwDFAQADAAQJ0RAxMwDvAAAAAA==.Marcelyne:BAAALgAECgYJCAABLgAECgkJJAALAPYTAA==.Marothius:BAACLgAFFH8VAAQLAAcJ7wzzKQBxAQALAAYJLAzzKQBxAQAhAAEJvxAUFABWAAAnAAEJ3AJmJAA5AAAuAAQKfzMABAsACQlhHhYgAFcCAAsACQlQHBYgAFcCACEABgmMHBAXAJEBACcAAgnLGrscALYAAAAA.Martaug:BAABLgAECn8hAAIiAAkJJx/uDwC6AgAiAAkJJx/uDwC6AgAAAA==.Marune:BAAALgAECgkJDwAAAA==.Maurice:BAAALgADCgYJCwAAAA==.Maverage:BAABLgAECn82AAMPAAkJDCLIBQDxAgAPAAkJDCLIBQDxAgAfAAYJ6xPWJQAjAQAAAA==.Mawg:BAAALgAECgYJBwAAAA==.Mayfair:BAABLgAECn8WAAMiAAYJ4hMOTgBbAQAiAAYJ4hMOTgBbAQAjAAYJuQZCWwC2AAAAAA==.',
Mb='Mbarnes:BAAALgAECgQJBwAAAA==.',
Me='Melee:BAACLgAFFH8rAAIHAAkJbyMkAAD2AgAHAAkJbyMkAAD2AgAuAAQKfxYAAgcACQmZJj0CALoDAAcACQmZJj0CALoDAAAA.',
Mi='Midnightfear:BAAALgADCgcJBwAAAA==.Mikeyy:BAAALgADCgMJAwAAAA==.Mimoza:BAAALgAECgYJCgAAAA==.Minibeer:BAAALgAECgYJEgAAAA==.Minimee:BAAALgAECgYJCAAAAA==.Miquella:BAAALgAECgYJDAAAAA==.Misohotramen:BAACLgAFFH8UAAICAAUJQxs6LABJAQACAAUJQxs6LABJAQAuAAQKfyQAAgIACQnQILUzACsCAAIACQnQILUzACsCAAAA.',
Mo='Moist:BAABLgAECn85AAIYAAkJXSO1AQAlAwAYAAkJXSO1AQAlAwAAAA==.Monkstrosity:BAAALgAECgMJAwAAAA==.Moofish:BAAALgAECgYJAwAAAA==.Moonlock:BAAALgADCgYJCgAAAA==.Moor:BAABLgAECn8aAAIeAAkJrwZsBgA/AQAeAAkJrwZsBgA/AQAAAA==.Mordakka:BAAALgAECgYJCQAAAA==.Morior:BAABLgAECn8wAAMLAAkJShuiKgAiAgALAAgJShuiKgAiAgAhAAIJMBi0UQB5AAAAAA==.Motgustus:BAAALgAFFAEJAQAAAA==.',
Mu='Muirfire:BAAALgADCgYJBgAAAA==.Murrda:BAABLgAECn81AAMLAAkJWyFtCwDoAgALAAkJWyFtCwDoAgAnAAEJ0xOOMQBBAAAAAA==.Musk:BAAALgAECgIJBAABLgAECggJKQAJADwVAA==.Muskrattsam:BAABLgAECn8pAAIJAAgJPBUdTgDZAQAJAAgJPBUdTgDZAQAAAA==.',
My='Myravia:BAABLgAECn8WAAIJAAcJrxAwkQCxAQAJAAcJrxAwkQCxAQAAAA==.Myrokos:BAABLgAECn9IAAIHAAkJ+SKlBwAcAwAHAAkJ+SKlBwAcAwAAAA==.',
['Mó']='Mónónoke:BAAALgADCgMJAwAAAA==.',
['Mö']='Möokss:BAAALgADCgQJAgAAAA==.',
Na='Nailo:BAABLgAECn9IAAIYAAkJShMLDwDTAQAYAAkJShMLDwDTAQAAAA==.Nails:BAAALgAECgQJBgAAAA==.Nathanos:BAAALgAECggJCwAAAA==.',
Ne='Nezar:BAAALgAFFAEJAwABLgAFFAEJBQAlAFcYAA==.',
Nh='Nhat:BAAALgAECgMJAwAAAA==.',
Ni='Niaah:BAAALgADCgYJAQABLgAECgkJFwABAL4cAA==.Niddy:BAABLgAECn87AAIJAAkJzxdkMABAAgAJAAkJzxdkMABAAgAAAA==.Nisardela:BAAALgADCgMJAwAAAA==.',
No='Nobudy:BAACLgAFFH8eAAMkAAcJ6BvIBQDkAQAkAAcJ6BvIBQDkAQAgAAQJzALuJgDcAAAuAAQKfzEABCQACQm6JF8DABYDACQACQm6JF8DABYDAB0ABgnIFcYuAIgBACAAAgnNBOJZAC4AAAAA.Noel:BAABLgAECn8eAAIdAAYJBxp0IgCZAQAdAAYJBxp0IgCZAQAAAA==.Nomsayin:BAACLgAFFH8GAAILAAMJHQvcdwC5AAALAAMJHQvcdwC5AAAuAAQKfzAAAgsACQkuGRYzAEACAAsACQkuGRYzAEACAAAA.Nonospot:BAABLgAECn8sAAMkAAkJmhfXEAA1AgAkAAkJmhfXEAA1AgAgAAEJvANJWgAuAAAAAA==.Noobuddy:BAAALgAECgUJCgABLgAFFAcJHgAkAOgbAA==.Noraboo:BAABLgAECn8jAAMeAAgJQRqjBAD7AQAeAAYJbxyjBAD7AQAJAAgJmRjpWAC6AQABLgAECgkJJwATAJscAA==.Norannestra:BAAALgAECgYJDQAAAA==.Novalicious:BAAALgADCgIJAgAAAA==.Novasera:BAAALgAECgcJCAAAAA==.',
Nu='Nubmuffin:BAAALgADCgUJBQAAAA==.',
Nv='Nvied:BAABLgAECn8cAAMLAAkJpRT1PQDXAQALAAgJpRT1PQDXAQAhAAEJAAD5cwAxAAAAAA==.',
Ny='Nyctt:BAABLgAECn8YAAMDAAkJ8BlNGQA6AgADAAkJUhhNGQA6AgARAAIJ5xdoFgCSAAAAAA==.Nystra:BAAALgAECggJDwAAAA==.Nyzstra:BAABLgAECn8wAAIJAAkJXiLEFQDBAgAJAAkJXiLEFQDBAgAAAA==.',
['Nê']='Nêwt:BAACLgAFFH8MAAIJAAMJPhG9bQDmAAAJAAMJPhG9bQDmAAAuAAQKfz4AAgkACQn/HAkmAG0CAAkACQn/HAkmAG0CAAAA.',
['Nì']='Nìrvana:BAAALgAECgQJCwAAAA==.',
On='Onlybeams:BAABLgAECn8fAAICAAkJQBvvHABSAgACAAkJQBvvHABSAgAAAA==.',
Or='Orphu:BAAALgAECgEJAQAAAA==.',
Pa='Pallyplexity:BAAALgAECgYJBgABLgAECgkJPgAVAFUmAA==.Palmiste:BAAALgAECgQJBgAAAA==.Pangoplexity:BAAALgADCgIJAgAAAA==.Parahsalin:BAAALgAECgEJAQABLgAECgYJEgAOAAAAAA==.Partyhard:BAAALgADCgkJGwAAAA==.Pastryblust:BAABLgAFFH8IAAIjAAUJARa7GAAsAQAjAAUJARa7GAAsAQAAAA==.Pastrydragon:BAACLgAFFH8LAAMaAAQJORZ9JwAIAQAaAAQJORZ9JwAIAQAbAAEJJxmBCgBVAAAuAAQKfy4AAxoACAmrINUKAMgCABoACAmSHtUKAMgCABsABglYI5ULACICAAEuAAUUBQkIACMAARYA.',
Ph='Phaeliea:BAAALgAECgUJBQAAAA==.',
Pi='Pistachio:BAABLgAECn8bAAIFAAYJOA4HLgDvAAAFAAYJOA4HLgDvAAAAAA==.Pitviper:BAABLgAECn8mAAIRAAkJ4x5GAwBvAgARAAkJ4x5GAwBvAgAAAA==.',
Po='Pocketrokit:BAAALgAECgkJDAAAAA==.Pogaca:BAAALgAECgcJDgABLgAECggJFwAWAP8bAA==.Portabull:BAAALgADCgcJBwABLgAECgkJIQACAKsdAA==.Possess:BAABLgAECn8lAAILAAcJ9BwURwC6AQALAAcJ9BwURwC6AQAAAA==.Pownora:BAABLgAECn8nAAMTAAkJmxx8CgCHAgATAAkJmxx8CgCHAgAoAAIJ/Q03mwAxAAAAAA==.',
Ps='Psarchasm:BAABLgAECn8wAAIPAAkJlg1RKAClAQAPAAkJlg1RKAClAQAAAA==.',
Pu='Puck:BAAALgAECgEJAgAAAA==.Puffnstuff:BAAALgAECgMJAwAAAA==.Pugstar:BAAALgAECgMJAwAAAA==.',
Qe='Qel:BAAALgADCgYJCQAAAA==.',
Ra='Rai:BAABLgAECn85AAIGAAkJzSSOBAA5AwAGAAkJzSSOBAA5AwAAAA==.Rancidbeef:BAAALgAECgMJAwAAAA==.Rapha:BAABLgAECn8nAAIUAAkJNyKWBADvAgAUAAkJNyKWBADvAgAAAA==.Rayyzer:BAABLgAECn8cAAIDAAkJqCGrCgBjAgADAAkJqCGrCgBjAgAAAA==.',
Re='Realrogue:BAAALgAECgYJBgABLgAECgkJPgAVAFUmAA==.Rema:BAAALgADCgQJBAAAAA==.Reyna:BAAALgADCgUJBQAAAA==.',
Ri='Riddles:BAABLgAECn8YAAMYAAgJhBplCwAMAgAYAAgJhBplCwAMAgANAAEJFiOEtQBaAAAAAA==.Rincewind:BAAALgAECgEJAQAAAA==.',
Ro='Rossabella:BAABLgAECn9FAAMdAAkJahuUCQC5AgAdAAkJahuUCQC5AgAgAAgJ0w7HGwC4AQAAAA==.Rot:BAABLgAECn8nAAIcAAkJCSZFAgAjAwAcAAkJCSZFAgAjAwAAAA==.',
Ru='Rude:BAAALgAECgYJBgABLgAFFAcJFAAPAEoeAA==.Ruzala:BAAALgADCgEJAQAAAA==.',
Sa='Samsonn:BAAALgADCgQJBAAAAA==.Sanctity:BAAALgADCgYJCgAAAA==.Santino:BAABLgAECn8eAAINAAgJYRnLGwBTAgANAAgJYRnLGwBTAgABLgAFFAMJDAAJALIIAA==.Saphlocket:BAAALgAECgYJEgAAAA==.Sathin:BAABLgAECn8wAAICAAkJmAp1WQBiAQACAAkJmAp1WQBiAQAAAA==.',
Sc='Scher:BAAALgADCgkJCwAAAA==.Scufalufagus:BAAALgAECgUJBQABLgAFFAcJFQALAO8MAA==.',
Se='Seetick:BAAALgAECgIJBAAAAA==.Sefekat:BAAALgAECgEJAQABLgAECgkJHwACAEAbAA==.September:BAAALgAECgIJAgABLgAFFAUJEQAGABoVAA==.Sevatar:BAABLgAECn8eAAIFAAgJhAw5IgBCAQAFAAgJhAw5IgBCAQAAAA==.',
Sf='Sfcwarner:BAAALgAECgEJAQAAAA==.',
Sg='Sgtwarner:BAAALgAECgEJAQAAAA==.',
Sh='Shampooyou:BAABLgAECn8pAAIiAAgJWgg0WAA2AQAiAAgJWgg0WAA2AQAAAA==.Shockakhan:BAAALgAECggJDgAAAA==.Shocknstone:BAAALgADCgcJBwABLgAECgkJPgAVAFUmAA==.',
Si='Silentmamba:BAAALgAECgEJAQAAAA==.Sinistra:BAAALgAECgcJEAAAAA==.',
Sk='Skelecopter:BAAALgADCgMJAwAAAA==.',
Sl='Slapshot:BAAALgAECggJCwABLgAECggJFwAWAP8bAA==.',
Sn='Snowflake:BAAALgADCgcJBwAAAA==.',
Sp='Spellsteal:BAABLgAECn8lAAIJAAkJuxhPMgA4AgAJAAkJuxhPMgA4AgABLgAFFAQJCwAVAK0LAA==.Spicynudz:BAAALgAECgEJAQAAAA==.Spring:BAACLgAFFH8RAAMGAAUJGhV9MQAyAQAGAAUJGhV9MQAyAQAKAAEJpAAJLgA2AAAuAAQKfyUAAwYACQlfHeUnACkCAAYACQkjHeUnACkCAAoABgnTC/ZMAB0BAAAA.',
Ss='Ssgwarner:BAAALgAECgEJAQAAAA==.',
St='Stardel:BAAALgAECgYJDQABLgAFFAcJGQADAJYjAA==.Sting:BAABLgAECn8WAAIGAAcJhguMbQBOAQAGAAcJhguMbQBOAQAAAA==.Stormclaw:BAABLgAECn8uAAINAAkJfxyrEAC5AgANAAkJfxyrEAC5AgAAAA==.Stormcrash:BAAALgADCgYJBgABLgAECgkJJgALAJ0WAA==.Stregoica:BAAALgADCgcJDgABLgAFFAcJFQALAO8MAA==.',
Su='Suhfering:BAAALgADCgYJBgABLgAECgkJHwACAEAbAA==.Superbeef:BAAALgADCgYJBgAAAA==.Sushiiez:BAAALgADCgMJAwAAAA==.Suwo:BAAALgADCgIJAQAAAA==.',
Sy='Sychopath:BAAALgAECgMJBAAAAA==.Sykadelik:BAAALgAECgMJAwAAAA==.Syngoma:BAAALgADCgIJAgAAAA==.',
Ta='Tallron:BAACLgAFFH8cAAINAAcJ6BgYCABCAgANAAcJ6BgYCABCAgAuAAQKfy4AAw0ACQmaJLcJAPcCAA0ACQmaJLcJAPcCABYABQmPFcM7AAYBAAAA.Tallsera:BAAALgADCgcJDQABLgAFFAcJHAANAOgYAA==.Tallyfan:BAAALgADCgcJEwAAAA==.Tamedsloth:BAAALgAECgQJBAABLgAECgQJBAAOAAAAAA==.Tandraella:BAAALgAECgQJBQABLgAFFAQJBgABAFUTAA==.Taroquin:BAAALgADCgkJCgAAAA==.',
Te='Ternay:BAAALgADCgIJAQAAAA==.Teskhamen:BAAALgAECgcJDAAAAA==.Tetamesh:BAAALgADCgQJBAAAAA==.',
Th='Theskabandit:BAAALgADCgcJEQAAAA==.Thrustruggle:BAAALgADCgEJAQAAAA==.',
Ti='Tiamot:BAAALgADCgUJCAAAAA==.',
To='Tojikitoushi:BAABLgAECn8wAAIQAAkJkSAsAwDCAgAQAAkJkSAsAwDCAgAAAA==.Tombs:BAAALgAECgYJCAAAAA==.Tonsonger:BAAALgAECgQJBAAAAA==.Totenhammer:BAAALgAECgQJCwAAAA==.Totenplage:BAAALgAECgQJBAAAAA==.',
Tr='Trid:BAAALgAECggJCAAAAA==.Tristex:BAAALgAECgUJBQABLgAECggJFwAWAP8bAA==.',
Tu='Tuha:BAAALgAFFAIJAgAAAA==.',
Tw='Twergstronk:BAAALgADCgEJAQAAAA==.',
Ty='Tyrolia:BAAALgAECgMJAwAAAA==.',
Um='Umibozu:BAAALgAECgIJAgAAAA==.',
Ur='Urchak:BAAALgAECgYJBgAAAA==.',
Va='Valliya:BAAALgAFFAIJAgAAAA==.',
Ve='Velratha:BAABLgAECn8UAAInAAgJtQ80DAB2AQAnAAgJtQ80DAB2AQAAAA==.Vesfu:BAAALgADCgEJAQAAAA==.Vesi:BAAALgADCgcJCgAAAA==.Vextt:BAABLgAECn8eAAMkAAgJDRgJJgB7AQAkAAcJRxsJJgB7AQAdAAIJeBhPYgA+AAAAAA==.',
Vi='Vicsta:BAAALgAECgYJBwAAAA==.',
Vo='Voidrend:BAAALgAECgQJBwAAAA==.Voidwarner:BAAALgAECgEJAQAAAA==.Volight:BAAALgADCgYJCQAAAA==.Volke:BAABLgAECn8nAAIoAAkJMxYoGgAgAgAoAAkJMxYoGgAgAgAAAA==.Volq:BAAALgAECgEJAQAAAA==.Voltarix:BAAALgAECgYJCQAAAA==.Voodoopriest:BAABLgAECn8YAAILAAcJMwRDpAAQAQALAAcJMwRDpAAQAQAAAA==.Voyria:BAABLgAECn8vAAQNAAkJgQdTaADpAAANAAgJ9QRTaADpAAAWAAUJIQX+WACSAAAZAAIJwQKbRgAvAAAAAA==.',
Vs='Vs:BAAALgAECgYJBgAAAA==.',
Vy='Vynlenn:BAAALgADCgMJAwAAAA==.Vyskaar:BAAALgADCgEJAQAAAA==.Vyskar:BAAALgAECgUJBQAAAA==.Vyskary:BAAALgAECgEJAQAAAA==.',
Wa='Warm:BAACLgAFFH8XAAITAAcJIxp5AgD+AQATAAcJIxp5AgD+AQAuAAQKfycAAhMACQkTImsIAPMCABMACQkTImsIAPMCAAAA.Warmlight:BAAALgAECgYJDAAAAA==.',
We='Weewu:BAAALgAECgQJBAAAAA==.Weeziveli:BAAALgAECgQJDQAAAA==.Weledish:BAACLgAFFH8TAAIJAAMJNR+KXAAZAQAJAAMJNR+KXAAZAQAuAAQKfyoAAgkACQnsGkA3ACQCAAkACQnsGkA3ACQCAAAA.Weleron:BAAALgAECgQJBAAAAA==.',
Wh='Whystler:BAAALgAECgIJAgAAAA==.',
Wi='Wienercat:BAABLgAECn8hAAINAAcJ6SQvDQDhAgANAAcJ6SQvDQDhAgABLgAECggJJwAiAHcjAA==.Windmacedu:BAAALgAECgYJCgAAAA==.',
Xt='Xtreeme:BAAALgAECgIJAgAAAA==.',
Ya='Yael:BAABLgAECn8yAAICAAkJeB6oFwBzAgACAAkJeB6oFwBzAgAAAA==.Yama:BAAALgAECgcJBwAAAA==.',
Za='Zamrazac:BAAALgAECgUJBQABLgAECgkJLgANAH8cAA==.Zarewien:BAABLgAECn8uAAIdAAkJ6ArIJwByAQAdAAkJ6ArIJwByAQAAAA==.',
Ze='Zeddicus:BAAALgAECgMJAwAAAA==.',
Zi='Ziddles:BAABLgAECn8UAAISAAcJvBs2DwDSAQASAAcJvBs2DwDSAQAAAA==.',
Zo='Zomgdk:BAAALgAECgEJAgABLgAECggJNwAUAFYfAA==.Zomgmonk:BAABLgAECn83AAIUAAgJVh/rDQBGAgAUAAgJVh/rDQBGAgAAAA==.Zomgzilla:BAAALgAECggJAQABLgAECggJNwAUAFYfAA==.Zorep:BAAALgAECgEJAQAAAA==.Zorien:BAAALgAECgQJBAAAAA==.',
Zu='Zuraq:BAAALgAECgEJBgAAAA==.Zurisdad:BAABLgAECn83AAIUAAkJ8B66BgC8AgAUAAkJ8B66BgC8AgABLgAFFAUJEgAJAMYXAA==.Zurishmi:BAACLgAFFH8cAAIiAAUJ/h5lBQB3AQAiAAUJ/h5lBQB3AQAuAAQKfzMAAiIACQk6JgsBAL0DACIACQk6JgsBAL0DAAAA.',
['Äm']='Ämäteräsu:BAAALgAECggJEgAAAA==.',
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
