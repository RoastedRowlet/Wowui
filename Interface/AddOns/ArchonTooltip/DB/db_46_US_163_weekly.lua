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

local lookup = {'Paladin-Holy','DemonHunter-Devourer','Rogue-Subtlety','Rogue-Outlaw','DemonHunter-Havoc','Hunter-BeastMastery','Paladin-Retribution','DeathKnight-Unholy','Mage-Frost','Hunter-Marksmanship','Warlock-Demonology','Paladin-Protection','Shaman-Restoration','Unknown-Unknown','Warrior-Fury','Shaman-Enhancement','Rogue-Assassination','Hunter-Survival','Monk-Windwalker','Monk-Brewmaster','Warrior-Protection','Druid-Balance','Druid-Restoration','DeathKnight-Frost','Druid-Guardian','Druid-Feral','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Blood','Priest-Holy','Mage-Arcane','Warrior-Arms','Priest-Discipline','Warlock-Destruction','Shaman-Elemental','Priest-Shadow','DemonHunter-Vengeance','Evoker-Preservation','Warlock-Affliction','Monk-Mistweaver',}
local provider = {region='US',realm='Nathrezim',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Abysm:BAAALgADCgkJDwAAAA==.',
Ac='Achillios:BAAALgADCgMJAwABLgAFFAQJBgABAFUTAA==.',
Ad='Adorabull:BAAALgAECgQJBgABLgAECgkJIQACAKsdAA==.',
Ae='Aemun:BAABLgAECn82AAMDAAkJiRuTCQBpAgADAAkJiRuTCQBpAgAEAAYJlAmwCAD2AAAAAA==.',
Ag='Aggfu:BAAALgADCgYJBgAAAA==.',
Ak='Akeeli:BAAALgADCgQJBAAAAA==.Akelita:BAABLgAECn8cAAIFAAYJrxhHHQBVAQAFAAYJrxhHHQBVAQAAAA==.',
Al='Alailea:BAABLgAECn80AAIGAAkJHhQUMQDuAQAGAAkJHhQUMQDuAQAAAA==.Alragnar:BAAALgAECgEJAQAAAA==.Alwysafkable:BAAALgAECgUJBQAAAA==.',
Am='Amageadin:BAAALgADCgkJCQAAAA==.Amazadin:BAACLgAFFH8GAAIBAAQJVRO/GwAQAQABAAQJVRO/GwAQAQAuAAQKfxgAAwEACAkpHO8bADUCAAEACAkpHO8bADUCAAcAAQm4HxsnAVkAAAAA.Amazashock:BAAALgAECgUJDQABLgAFFAQJBgABAFUTAA==.',
An='Andiwin:BAABLgAECn8XAAIIAAgJOw0fZAB8AQAIAAgJOw0fZAB8AQAAAA==.Andurthil:BAABLgAECn8kAAIJAAgJxwy8egBmAQAJAAgJxwy8egBmAQAAAA==.Anzul:BAAALgAECgUJBgAAAA==.',
Ar='Archive:BAAALgAECgkJCwAAAA==.Artistic:BAABLgAECn8cAAIGAAgJeBmRMADwAQAGAAgJeBmRMADwAQAAAA==.Arylanna:BAAALgAECgYJDQAAAA==.',
As='Asure:BAABLgAECn8tAAMGAAkJ/hd3HgBFAgAGAAkJ/hd3HgBFAgAKAAYJTgfdTwAPAQAAAA==.',
Az='Azerith:BAAALgAECgYJDgAAAA==.',
Ba='Badmorda:BAAALgADCgEJAQAAAA==.',
Be='Bearforceone:BAAALgADCgMJAwAAAA==.',
Bi='Bipolar:BAAALgADCgEJAQAAAA==.',
Bl='Blackheart:BAABLgAECn8bAAILAAgJnBjCLQBWAgALAAgJnBjCLQBWAgAAAA==.Blodreina:BAAALgADCgUJCQAAAA==.Bloodarchon:BAABLgAECn8dAAMHAAgJUBR/WgCeAQAHAAgJUBR/WgCeAQAMAAYJnQkGKQCjAAAAAA==.Bloodtemplar:BAABLgAECn8kAAIHAAgJhhVHRwDRAQAHAAgJhhVHRwDRAQAAAA==.',
Bo='Bombs:BAAALgAECgQJEAABLgAFFAQJGgANAKAeAA==.Bonesy:BAAALgAECgYJBgAAAA==.Bouren:BAAALgAECgEJAQAAAA==.',
Br='Bravia:BAAALgADCgUJBwAAAA==.Brewdogg:BAAALgADCgcJBwAAAA==.Brutalitops:BAAALgADCgMJAwAAAA==.Brutusdabull:BAAALgAECgYJBgAAAA==.Brônze:BAAALgADCgQJBAAAAA==.',
Bu='Burdomew:BAAALgADCgEJAQAAAA==.',
Ca='Cadbury:BAAALgADCgIJAgABLgAECgUJCAAOAAAAAA==.Canan:BAAALgAECgUJBQAAAA==.Canestoast:BAAALgAECgEJAQAAAA==.Casmina:BAABLgAECn8WAAIPAAkJ7xlRIQBJAgAPAAkJ7xlRIQBJAgAAAA==.Castiell:BAAALgADCgUJBgAAAA==.Catalystic:BAAALgADCgEJAQAAAA==.Catd:BAAALgADCgEJAQAAAA==.',
Ce='Celum:BAABLgAECn8cAAIIAAYJcQgLsADqAAAIAAYJcQgLsADqAAAAAA==.Ceola:BAAALgAECgQJDAAAAA==.',
Ch='Chamming:BAAALgADCgIJAgAAAA==.Chaquén:BAABLgAECn8dAAIQAAkJhxfQBwAcAgAQAAkJhxfQBwAcAgAAAA==.Charizard:BAAALgAECgEJAQAAAA==.Charmander:BAABLgAECn8fAAQRAAYJshfzCgCAAQARAAYJshfzCgCAAQADAAQJUglmPACaAAAEAAMJ2wRJFgB2AAAAAA==.Chaw:BAACLgAFFH8XAAMSAAYJvyKvAgDAAQASAAYJbBuvAgDAAQAGAAEJcCamIQBdAAAuAAQKfzIABBIACQnuJK4CAAQDABIACQnsJK4CAAQDAAoABwnWHy0iABQCAAYABAk3I1BIAJEBAAAA.Chenkenichi:BAABLgAECn8ZAAMTAAkJvQYgLQAtAQATAAkJvQYgLQAtAQAUAAUJKAKraACfAAAAAA==.Chergar:BAACLgAFFH8MAAIVAAUJkhvFCwA3AQAVAAUJkhvFCwA3AQAuAAQKfxwAAhUACAnmIUwFAOkCABUACAnmIUwFAOkCAAAA.Chskie:BAAALgADCgUJBQAAAA==.Chsky:BAAALgADCgUJBQAAAA==.Chuiyi:BAAALgAECgEJAgAAAA==.',
Ci='Cinny:BAABLgAECn9BAAIGAAkJvRpCFwByAgAGAAkJvRpCFwByAgAAAA==.Cinnyrolls:BAABLgAECn8XAAMWAAgJ/xvaFgDtAQAWAAgJ/xvaFgDtAQAXAAQJtBBhhwDHAAAAAA==.Cityairlines:BAABLgAECn8nAAIYAAkJuRScCAC7AQAYAAkJuRScCAC7AQAAAA==.',
Cl='Clare:BAAALgAECgYJCQAAAA==.',
Cm='Cmoneyy:BAAALgAECgQJBQAAAA==.',
Co='Cogrolls:BAAALgADCgIJAgAAAA==.Cooldukenuke:BAACLgAFFH8KAAIBAAMJqRf4DwDaAAABAAMJqRf4DwDaAAAuAAQKfycAAgEACQmjHDoTAHkCAAEACQmjHDoTAHkCAAAA.',
Cr='Creepychalk:BAAALgAECgUJDAAAAA==.Criticize:BAABLgAECn8nAAIHAAgJ1gyWfQBTAQAHAAgJ1gyWfQBTAQAAAA==.',
Cs='Csor:BAAALgAECgMJAwAAAA==.Csorb:BAABLgAECn8xAAMZAAkJ8SBgAwDMAgAZAAkJviBgAwDMAgAaAAEJySUsLQBtAAAAAA==.Csoren:BAAALgAECgEJAQAAAA==.Csoro:BAAALgADCggJCAAAAA==.',
Cu='Cultivation:BAAALgAECgUJCAAAAA==.Cursedcanfly:BAACLgAFFH8WAAIbAAYJOR6nDADBAQAbAAYJOR6nDADBAQAuAAQKfzMAAxsACQnjJbYBAGADABsACQnjJbYBAGADABwABQnaFG8iABcBAAAA.',
Cw='Cw:BAAALgAECgEJAQAAAA==.',
De='Deathdogg:BAACLgAFFH8UAAMIAAUJxxlhPQBJAQAIAAQJxxlhPQBJAQAdAAEJAADfPgAAAAAuAAQKfykAAggACQlPIHopADgCAAgACQlPIHopADgCAAAA.Dejavu:BAACLgAFFH8XAAIUAAUJBhEOIAAPAQAUAAUJBhEOIAAPAQAuAAQKfycAAhQACAkgHZgaAC8CABQACAkgHZgaAC8CAAAA.Demivoi:BAAALgAECgYJBwAAAA==.Demona:BAAALgAECgEJAQAAAA==.Deppthcharge:BAAALgAECgYJDwAAAA==.Desdemona:BAAALgAECgUJCQAAAA==.Devimon:BAAALgADCgEJAQAAAA==.Devoi:BAAALgADCgEJAQAAAA==.',
Do='Donrain:BAAALgAECgQJBAAAAA==.Dooghammer:BAABLgAECn8ZAAIQAAkJQxpEBwAqAgAQAAkJQxpEBwAqAgAAAA==.',
Dr='Dragussy:BAAALgADCgcJDQABLgAECgkJNQAVABsmAA==.',
Du='Dunkhan:BAAALgAECgEJAQABLgAECgYJCgAOAAAAAA==.Duplexity:BAABLgAECn81AAIVAAkJGyakAABlAwAVAAkJGyakAABlAwAAAA==.',
Dw='Dwalin:BAAALgAECgMJCAABLgAECgkJGQAQAEMaAA==.',
Ec='Ecko:BAAALgAECgEJAQAAAA==.',
Ed='Edolah:BAAALgAECgEJAQAAAA==.',
Eg='Egohakai:BAACLgAFFH8RAAIHAAUJrx0OJABJAQAHAAUJrx0OJABJAQAuAAQKfzAAAgcACQkUJVEFADYDAAcACQkUJVEFADYDAAAA.',
El='Eloi:BAABLgAECn8VAAIeAAgJbyD9BgDgAgAeAAgJbyD9BgDgAgABLgAECgkJKQAXACccAA==.',
Em='Emieretta:BAABLgAECn80AAIIAAkJ6hWUOAD7AQAIAAkJ6hWUOAD7AQAAAA==.',
Eq='Eqdk:BAABLgAECn8aAAIIAAkJ8RI8RQDQAQAIAAkJ8RI8RQDQAQAAAA==.',
Er='Erret:BAACLgAFFH8SAAIJAAUJxheFRQA7AQAJAAUJxheFRQA7AQAuAAQKfzIAAwkACQlwI0kIACYDAAkACQlwI0kIACYDAB8AAQngGW0PAEoAAAAA.',
Ey='Eyrie:BAAALgADCgYJBgAAAA==.',
Ez='Ezinder:BAAALgAECgYJDAAAAA==.',
Fa='Fabius:BAAALgADCgYJBgAAAA==.Faemos:BAAALgAECgkJBgAAAA==.Faience:BAABLgAECn8gAAIYAAgJfQOQGgCvAAAYAAgJfQOQGgCvAAAAAA==.Falorina:BAABLgAECn8nAAMFAAgJ9CEVBwCYAgAFAAgJ9CEVBwCYAgACAAEJAwXh6wAnAAAAAA==.Fathernature:BAABLgAECn8dAAMWAAkJJxneKAC4AQAWAAkJJxneKAC4AQAaAAEJeQX8OAAlAAAAAA==.Fauna:BAAALgADCgMJAwAAAA==.Fazeup:BAAALgAECgcJBgAAAA==.',
Fe='Feldra:BAABLgAECn8oAAICAAkJEB0rGgBaAgACAAkJEB0rGgBaAgAAAA==.Felfaith:BAAALgAECgIJAgAAAA==.Fester:BAAALgADCgUJBQABLgAECgkJJgALAJ0WAA==.',
Fi='Fightforbeer:BAAALgAECgEJAQAAAA==.Finnin:BAABLgAECn8jAAMPAAkJCSSMBwDJAgAPAAkJCSSMBwDJAgAgAAEJ0gZ8SAAkAAAAAA==.',
Fo='Food:BAABLgAECn8mAAIGAAkJoRgrIQA/AgAGAAkJoRgrIQA/AgAAAA==.Formidabull:BAAALgAECgEJAQABLgAECgkJIQACAKsdAA==.Foxdiez:BAAALgAECggJEQAAAA==.',
Fr='Freidafondle:BAAALgAECgUJDAAAAA==.Frostbite:BAAALgAECgcJCAAAAA==.Frozenfaith:BAABLgAECn8mAAMhAAkJUwvDJQByAQAhAAgJ1gvDJQByAQAeAAMJMgTnVwBPAAAAAA==.',
Ft='Fthemeta:BAAALgADCgIJAgAAAA==.',
Fu='Furioushealz:BAABLgAECn8nAAIHAAkJpxnlLgAjAgAHAAkJpxnlLgAjAgAAAA==.Furiouswind:BAAALgADCgEJAQAAAA==.',
Ga='Gardrius:BAAALgADCgYJBwAAAA==.',
Gh='Ghettomike:BAABLgAECn8pAAIIAAkJAB6AKgAzAgAIAAkJAB6AKgAzAgAAAA==.Ghoulbane:BAAALgADCgYJCgAAAA==.',
Gi='Gibbits:BAAALgAECgcJCAAAAA==.Giranimo:BAABLgAECn8fAAIGAAgJghIYQwCtAQAGAAgJghIYQwCtAQAAAA==.',
Gl='Glabados:BAAALgAECgIJAwABLgAECgkJJwAUADciAA==.Glossy:BAACLgAFFH8cAAMDAAUJfiUGCQCcAQADAAUJfiUGCQCcAQAEAAMJ4hDcCACcAAAuAAQKfzIABAMACQmEJv4AAGEDAAMACQmEJv4AAGEDAAQAAgmEIZERAL4AABEAAgkNHzAUALsAAAAA.Glossycumbus:BAAALgADCgYJBgABLgAFFAUJHAADAH4lAA==.Glossydh:BAAALgAECgYJBgABLgAFFAUJHAADAH4lAA==.Glossydk:BAAALgAECgQJBQABLgAFFAUJHAADAH4lAA==.Glossylock:BAAALgADCgcJDQABLgAFFAUJHAADAH4lAA==.',
Go='Golbigold:BAAALgAECgEJAQAAAA==.Goopy:BAAALgAECgMJAwAAAA==.',
Gr='Grayhoff:BAABLgAECn8cAAIPAAkJkAvdJgCeAQAPAAkJkAvdJgCeAQAAAA==.Greatclaw:BAAALgADCgMJAwAAAA==.Grewsom:BAACLgAFFH8RAAIHAAQJNyLgEwCFAQAHAAQJNyLgEwCFAQAuAAQKfywAAwcACAniJWMJAEYDAAcACAniJWMJAEYDAAwABQnzIK4SAHABAAAA.',
Gu='Gulmok:BAAALgADCgUJBQAAAA==.Guwugga:BAABLgAECn8cAAIiAAYJ4hJ0DwAdAQAiAAYJ4hJ0DwAdAQAAAA==.',
Ha='Halîk:BAABLgAECn8XAAIBAAkJvhwJLADXAQABAAkJvhwJLADXAQAAAA==.Haraka:BAAALgAECgMJBAAAAA==.Harmshock:BAABLgAECn89AAIQAAkJhCS8AQD4AgAQAAkJhCS8AQD4AgAAAA==.Hathina:BAACLgAFFH8SAAMPAAYJfB6hDgBcAQAPAAUJvCOhDgBcAQAgAAEJfAmNKgBNAAAuAAQKfzMAAw8ACQnTJp4AAHsDAA8ACQnTJp4AAHsDACAAAwmCHykeAP4AAAAA.',
He='Heket:BAABLgAECn8qAAIHAAgJmAdrmQAhAQAHAAgJmAdrmQAhAQAAAA==.Hektric:BAAALgAECgMJAwAAAA==.Helpinghandz:BAAALgAECgYJBgABLgAFFAQJEQAPAIIVAA==.',
Hi='Highdra:BAAALgAECgQJBAAAAA==.Hill:BAABLgAECn8nAAIGAAkJhR/7FgCAAgAGAAkJhR/7FgCAAgAAAA==.Hive:BAABLgAECn8uAAIPAAkJThibDwBbAgAPAAkJThibDwBbAgAAAA==.',
Ho='Holygem:BAAALgAECgYJCgAAAA==.Holypower:BAAALgADCgcJDQAAAA==.Hotdogwater:BAABLgAECn8nAAMNAAgJdyNZBwAUAwANAAgJdyNZBwAUAwAjAAQJ5gkoZgB/AAAAAA==.',
Hu='Husentar:BAABLgAECn85AAIJAAkJ8CBUDwDoAgAJAAkJ8CBUDwDoAgAAAA==.Huuhablo:BAABLgAECn9AAAICAAkJjRyLEwCJAgACAAkJjRyLEwCJAgAAAA==.',
Ic='Icaron:BAAALgAECgcJDQAAAA==.',
Ig='Igothots:BAAALgAECgUJCgAAAA==.',
Il='Illuminottey:BAAALgAECgkJEwAAAA==.',
In='Inferium:BAAALgADCgYJBgABLgAFFAQJDwAOAAAAAA==.Infernom:BAAALgADCgMJAwABLgAFFAQJDwAOAAAAAA==.Insatiabull:BAABLgAECn8hAAMCAAkJqx2+EgDqAgACAAgJ7x6+EgDqAgAFAAEJyxShTwBDAAAAAA==.',
Io='Iolchsk:BAAALgAECgQJDAAAAA==.',
Is='Ishaa:BAAALgAECgYJBwAAAA==.',
Ja='Jacksof:BAABLgAECn8UAAMkAAYJ7gWhTQCoAAAkAAYJ7gWhTQCoAAAhAAQJOQRFVgBaAAAAAA==.Jackstands:BAABLgAECn9CAAMNAAkJFCG+BgAeAwANAAkJFCG+BgAeAwAQAAgJgAUfFgAaAQAAAA==.Jagerin:BAAALgAECgYJCwABLgAECgkJJwAUADciAA==.January:BAAALgAECgYJBgABLgAFFAUJEAAGAFIUAA==.Jasmyne:BAAALgADCgYJBgAAAA==.',
Je='Jeromy:BAAALgAECgEJAQAAAA==.Jesse:BAAALgADCgIJAgAAAA==.',
Ji='Jiffi:BAABLgAECn8ZAAIlAAgJyRrwBQA8AgAlAAgJyRrwBQA8AgAAAA==.Jinksy:BAAALgAECgUJDQAAAA==.',
Jm='Jme:BAAALgAECgcJCQAAAA==.',
Jr='Jredz:BAAALgADCgEJAQAAAA==.',
Ju='Jubag:BAAALgADCgIJAgAAAA==.Jumpercables:BAAALgAECgEJBAAAAA==.Junn:BAABLgAECn8nAAIjAAkJmBOkHgDAAQAjAAkJmBOkHgDAAQAAAA==.',
['Já']='Jánuary:BAAALgAECgUJBQAAAA==.',
Ka='Kahayman:BAACLgAFFH8FAAIJAAIJnweDiACUAAAJAAIJnweDiACUAAAuAAQKfzAAAgkACQmDGS0jAHUCAAkACQmDGS0jAHUCAAAA.Karellen:BAAALgAECggJDgAAAA==.Kathren:BAAALgAECgYJBgAAAA==.',
Kh='Khathani:BAAALgAECgQJCgAAAA==.',
Ki='Kieran:BAAALgADCgcJBwAAAA==.Kirara:BAAALgADCgUJBQAAAA==.',
Kn='Knobgoblinn:BAAALgAECgQJBAAAAA==.',
Ko='Komojo:BAABLgAECn8lAAIHAAgJXRCYaAB+AQAHAAgJXRCYaAB+AQAAAA==.Koriggan:BAABLgAECn8pAAQSAAgJ0RGMFwDHAQASAAgJ0RGMFwDHAQAGAAYJKhB6VQBoAQAKAAEJ6QBlmwAUAAAAAA==.',
Kr='Krea:BAABLgAECn8rAAIMAAgJoyLZAwCkAgAMAAgJoyLZAwCkAgAAAA==.Krixx:BAAALgADCgEJAQAAAA==.Krystagosa:BAABLgAECn83AAQmAAkJ1RS2CABAAgAmAAkJ1RS2CABAAgAbAAYJJg+HQQD8AAAcAAMJVAqpFQCPAAAAAA==.',
Ku='Kuriuh:BAABLgAECn8mAAILAAkJnRYyMAD/AQALAAkJnRYyMAD/AQAAAA==.Kurtcobainn:BAAALgADCgkJCQAAAA==.',
La='Lang:BAABLgAECn85AAIlAAkJSB3WAgCcAgAlAAkJSB3WAgCcAgAAAA==.',
Le='Legionslamm:BAAALgADCgUJBQAAAA==.Leonldas:BAAALgADCgEJAQAAAA==.',
Li='Lightsfaith:BAAALgADCgYJBgABLgAECgkJJgAhAFMLAA==.',
Lo='Lodix:BAAALgAECgEJAgAAAA==.Loopey:BAAALgAECgcJEAABLgAFFAUJFwAUAAYRAA==.Lorethil:BAAALgAECgYJCQAAAA==.',
Lu='Luceriss:BAABLgAECn8fAAIDAAkJtA7bFQDIAQADAAkJtA7bFQDIAQAAAA==.Luminous:BAAALgADCgcJCAABLgAECgkJJgALAJ0WAA==.',
Ma='Maeroth:BAAALgADCgUJBQABLgAFFAYJEwALAJ4MAA==.Magicboi:BAABLgAECn8WAAIJAAYJsw/CpQAXAQAJAAYJsw/CpQAXAQAAAA==.Magwar:BAACLgAFFH8QAAIPAAYJrxZKCACPAQAPAAYJrxZKCACPAQAuAAQKfzEAAg8ACQlXIeMFAOgCAA8ACQlXIeMFAOgCAAAA.Maike:BAABLgAECn8kAAIRAAgJQBT5BgDMAQARAAgJQBT5BgDMAQAAAA==.Marcelyne:BAAALgAECgYJCAABLgAECgkJIgALAOYTAA==.Marothius:BAACLgAFFH8TAAQLAAYJngzePwAlAQALAAUJlQvePwAlAQAiAAEJvxAUFABWAAAnAAEJ3AI/HgA5AAAuAAQKfzMABAsACQlhHvMcAF0CAAsACQlQHPMcAF0CACIABgmMHBAXAJEBACcAAgnLGskZALYAAAAA.Martaug:BAABLgAECn8hAAINAAkJJx/TDQC+AgANAAkJJx/TDQC+AgAAAA==.Marune:BAAALgAECgkJDwAAAA==.Maurice:BAAALgADCgYJCwAAAA==.Maverage:BAABLgAECn82AAMPAAkJDCLEBAD8AgAPAAkJDCLEBAD8AgAgAAYJ6xNBIgAkAQAAAA==.Mawg:BAAALgAECgYJBwAAAA==.Mayfair:BAABLgAECn8VAAMNAAYJ4hMfSABbAQANAAYJ4hMfSABbAQAjAAYJuQbAVAC2AAAAAA==.',
Mb='Mbarnes:BAAALgAECgQJBwAAAA==.',
Me='Melee:BAACLgAFFH8rAAIHAAkJbyMkAAD2AgAHAAkJbyMkAAD2AgAuAAQKfxQAAgcACQmZJj0CALoDAAcACQmZJj0CALoDAAAA.',
Mi='Midnightfear:BAAALgADCgcJBwAAAA==.Mikeyy:BAAALgADCgMJAwAAAA==.Mimoza:BAAALgAECgYJCgAAAA==.Minibeer:BAAALgAECgYJEgAAAA==.Minimee:BAAALgAECgEJAQAAAA==.Miquella:BAAALgAECgYJDAAAAA==.Misohotramen:BAACLgAFFH8TAAICAAUJQxuoIwBYAQACAAUJQxuoIwBYAQAuAAQKfyQAAgIACQnQILUzACsCAAIACQnQILUzACsCAAAA.',
Mo='Moist:BAABLgAECn85AAIZAAkJXSNqAQAnAwAZAAkJXSNqAQAnAwAAAA==.Monkstrosity:BAAALgAECgMJAwAAAA==.Moofish:BAAALgAECgYJAwAAAA==.Moonlock:BAAALgADCgYJCgAAAA==.Moor:BAABLgAECn8aAAIfAAkJrwbFBQBIAQAfAAkJrwbFBQBIAQAAAA==.Mordakka:BAAALgAECgYJCQAAAA==.Morior:BAABLgAECn8wAAMLAAkJShtRJgAqAgALAAgJShtRJgAqAgAiAAIJMBi0UQB5AAAAAA==.Motgustus:BAAALgAECgYJDgAAAA==.',
Mu='Muirfire:BAAALgADCgYJBgAAAA==.Murrda:BAABLgAECn81AAMLAAkJWyHUCQDuAgALAAkJWyHUCQDuAgAnAAEJ0xN+KwBEAAAAAA==.Musk:BAAALgAECgIJAwABLgAECggJJAAJAOATAA==.Muskrattsam:BAABLgAECn8kAAIJAAgJ4BMRVgC9AQAJAAgJ4BMRVgC9AQAAAA==.',
My='Myravia:BAABLgAECn8WAAIJAAcJrxAwkQCxAQAJAAcJrxAwkQCxAQAAAA==.Myrokos:BAABLgAECn9CAAIHAAkJIyLzCAAJAwAHAAkJIyLzCAAJAwAAAA==.',
['Mó']='Mónónoke:BAAALgADCgMJAwAAAA==.',
['Mö']='Möokss:BAAALgADCgQJAgAAAA==.',
Na='Nailo:BAABLgAECn9CAAIZAAkJkBG9EAChAQAZAAkJkBG9EAChAQAAAA==.Nails:BAAALgAECgQJBgAAAA==.Nathanos:BAAALgAECggJCwAAAA==.',
Ne='Nezar:BAAALgAFFAEJAwABLgAFFAEJBQAlAFcYAA==.',
Nh='Nhat:BAAALgAECgMJAwAAAA==.',
Ni='Niaah:BAAALgADCgYJAQABLgAECgkJFwABAL4cAA==.Niddy:BAABLgAECn8yAAIJAAkJPRZ1MgAxAgAJAAkJPRZ1MgAxAgAAAA==.Nisardela:BAAALgADCgMJAwAAAA==.',
No='Nobudy:BAACLgAFFH8cAAMkAAYJGSFRBgC7AQAkAAYJGSFRBgC7AQAhAAQJzAIrIgDsAAAuAAQKfzEABCQACQm6JNECACYDACQACQm6JNECACYDAB4ABgnIFcYuAIgBACEAAgnNBOJZAC4AAAAA.Noel:BAABLgAECn8YAAIeAAYJBxrsHwCgAQAeAAYJBxrsHwCgAQAAAA==.Nomsayin:BAACLgAFFH8GAAILAAMJHQvlbAC6AAALAAMJHQvlbAC6AAAuAAQKfzAAAgsACQkuGRYzAEACAAsACQkuGRYzAEACAAAA.Nonospot:BAABLgAECn8sAAMkAAkJmhcVDwBDAgAkAAkJmhcVDwBDAgAhAAEJvANJWgAuAAAAAA==.Noobuddy:BAAALgAECgUJCgABLgAFFAYJHAAkABkhAA==.Noraboo:BAABLgAECn8jAAMfAAgJQRqjBAD7AQAfAAYJbxyjBAD7AQAJAAgJmRhKUwDGAQAAAA==.Norannestra:BAAALgAECgYJDQAAAA==.Novalicious:BAAALgADCgIJAgAAAA==.Novasera:BAAALgAECgcJCAAAAA==.',
Nu='Nubmuffin:BAAALgADCgUJBQAAAA==.',
Nv='Nvied:BAABLgAECn8cAAMLAAkJpRQsOADgAQALAAgJpRQsOADgAQAiAAEJAAD5cwAxAAAAAA==.',
Ny='Nyctt:BAABLgAECn8YAAMDAAkJ8BlNGQA6AgADAAkJUhhNGQA6AgARAAIJ5xdoFgCSAAAAAA==.Nystra:BAAALgAECggJDwAAAA==.Nyzstra:BAABLgAECn8wAAIJAAkJXiLnEgDPAgAJAAkJXiLnEgDPAgAAAA==.',
['Nê']='Nêwt:BAACLgAFFH8JAAIJAAMJdwhQbQDaAAAJAAMJdwhQbQDaAAAuAAQKfzsAAgkACQm2GtIlAGgCAAkACQm2GtIlAGgCAAAA.',
['Nì']='Nìrvana:BAAALgAECgQJCwAAAA==.',
On='Onlybeams:BAABLgAECn8fAAICAAkJQBuyGQBdAgACAAkJQBuyGQBdAgAAAA==.',
Or='Orphu:BAAALgAECgEJAQAAAA==.',
Pa='Pallyplexity:BAAALgAECgYJBgABLgAECgkJNQAVABsmAA==.Palmiste:BAAALgAECgQJBgAAAA==.Pangoplexity:BAAALgADCgIJAgAAAA==.Parahsalin:BAAALgAECgEJAQABLgAECgUJDAAOAAAAAA==.Partyhard:BAAALgADCgYJCwAAAA==.Pastryblust:BAAALgAFFAMJAwABLgAFFAQJCwAbADkWAA==.Pastrydragon:BAACLgAFFH8LAAMbAAQJORZyIQAWAQAbAAQJORZyIQAWAQAcAAEJJxluCQBWAAAuAAQKfy4AAxsACAmrINUKAMgCABsACAmSHtUKAMgCABwABglYI5ULACICAAAA.',
Pi='Pistachio:BAABLgAECn8bAAIFAAYJOA7GKQD0AAAFAAYJOA7GKQD0AAAAAA==.Pitviper:BAABLgAECn8mAAIRAAkJ4x7FAgB4AgARAAkJ4x7FAgB4AgAAAA==.',
Po='Pocketrokit:BAAALgAECgkJDAAAAA==.Pogaca:BAAALgAECgcJDgABLgAECggJFwAWAP8bAA==.Portabull:BAAALgADCgcJBwABLgAECgkJIQACAKsdAA==.Possess:BAABLgAECn8lAAILAAcJ9BxVQgC9AQALAAcJ9BxVQgC9AQAAAA==.Pownora:BAABLgAECn8iAAMTAAgJThwWEAAkAgATAAgJThwWEAAkAgAoAAIJ/Q3zhwAwAAABLgAECggJIwAfAEEaAA==.',
Ps='Psarchasm:BAABLgAECn8tAAIPAAkJjg2OJACsAQAPAAkJjg2OJACsAQAAAA==.',
Pu='Puck:BAAALgAECgEJAgAAAA==.Pugstar:BAAALgAECgMJAwAAAA==.',
Qe='Qel:BAAALgADCgYJCQAAAA==.',
Ra='Rai:BAABLgAECn85AAIGAAkJzSRjAwBBAwAGAAkJzSRjAwBBAwAAAA==.Rancidbeef:BAAALgAECgMJAwAAAA==.Rapha:BAABLgAECn8nAAIUAAkJNyLkAwD0AgAUAAkJNyLkAwD0AgAAAA==.Rayyzer:BAABLgAECn8cAAIDAAkJqCEYCQBwAgADAAkJqCEYCQBwAgAAAA==.',
Re='Rema:BAAALgADCgQJBAAAAA==.Reyna:BAAALgADCgUJBQAAAA==.',
Ri='Riddles:BAABLgAECn8YAAMZAAgJhBrOCQAQAgAZAAgJhBrOCQAQAgAXAAEJFiOEtQBaAAAAAA==.Rincewind:BAAALgAECgEJAQAAAA==.',
Ro='Rossabella:BAABLgAECn8/AAMeAAkJTxrpCQClAgAeAAkJTxrpCQClAgAhAAgJ0w7HGwC4AQAAAA==.Rot:BAABLgAECn8nAAIdAAkJCSbIAQAqAwAdAAkJCSbIAQAqAwAAAA==.',
Ru='Rude:BAAALgAECgYJBgABLgAFFAYJEgAPAHweAA==.Ruzala:BAAALgADCgEJAQAAAA==.',
Sa='Samsonn:BAAALgADCgQJBAAAAA==.Sanctity:BAAALgADCgYJCgAAAA==.Santino:BAABLgAECn8eAAIXAAgJYRnDGQBUAgAXAAgJYRnDGQBUAgABLgAFFAIJBQAJAJ8HAA==.Saphlocket:BAAALgAECgYJEgAAAA==.Sathin:BAABLgAECn8wAAICAAkJmApfTwB1AQACAAkJmApfTwB1AQAAAA==.',
Sc='Scher:BAAALgADCgkJCwAAAA==.Scufalufagus:BAAALgAECgUJBQABLgAFFAYJEwALAJ4MAA==.',
Se='Seetick:BAAALgAECgIJBAAAAA==.Sefekat:BAAALgAECgEJAQABLgAECgkJHwACAEAbAA==.September:BAAALgAECgIJAgABLgAFFAUJEAAGAFIUAA==.Sevatar:BAABLgAECn8dAAIFAAgJggybHgBJAQAFAAgJggybHgBJAQAAAA==.',
Sf='Sfcwarner:BAAALgAECgEJAQAAAA==.',
Sg='Sgtwarner:BAAALgADCgYJBgAAAA==.',
Sh='Shampooyou:BAABLgAECn8kAAINAAcJsggiXQANAQANAAcJsggiXQANAQAAAA==.Shockakhan:BAAALgAECggJDQAAAA==.Shocknstone:BAAALgADCgcJBwABLgAECgkJNQAVABsmAA==.',
Si='Silentmamba:BAAALgAECgEJAQAAAA==.Sinistra:BAAALgAECgcJEAAAAA==.',
Sk='Skelecopter:BAAALgADCgMJAwAAAA==.',
Sl='Slapshot:BAAALgAECgYJBwABLgAECggJFwAWAP8bAA==.',
Sn='Snowflake:BAAALgADCgcJBwAAAA==.',
Sp='Spellsteal:BAABLgAECn8lAAIJAAkJuxhYLQBGAgAJAAkJuxhYLQBGAgABLgAFFAQJBwAVAA4IAA==.Spicynudz:BAAALgAECgEJAQAAAA==.Spring:BAACLgAFFH8QAAMGAAUJUhRvKwAsAQAGAAUJUhRvKwAsAQAKAAEJpAAJLgA2AAAuAAQKfyUAAwYACQlfHf4iAC0CAAYACQkjHf4iAC0CAAoABgnTC/ZMAB0BAAAA.',
Ss='Ssgwarner:BAAALgAECgEJAQAAAA==.',
St='Stardel:BAAALgAECgYJDQABLgAFFAYJFwADADQlAA==.Sting:BAAALgAECgcJDQAAAA==.Stormclaw:BAABLgAECn8pAAIXAAkJJxxgDwC5AgAXAAkJJxxgDwC5AgAAAA==.Stormcrash:BAAALgADCgYJBgABLgAECgkJJgALAJ0WAA==.Stregoica:BAAALgADCgcJDgABLgAFFAYJEwALAJ4MAA==.',
Su='Suhfering:BAAALgADCgYJBgABLgAECgkJHwACAEAbAA==.Sushiiez:BAAALgADCgMJAwAAAA==.Suwo:BAAALgADCgIJAQAAAA==.',
Sy='Sykadelik:BAAALgAECgMJAwAAAA==.Syngoma:BAAALgADCgIJAgAAAA==.',
Ta='Tallron:BAACLgAFFH8aAAIXAAYJQBoNCwDtAQAXAAYJQBoNCwDtAQAuAAQKfy4AAxcACQmaJLcJAPcCABcACQmaJLcJAPcCABYABQmPFSw3AAYBAAAA.Tallsera:BAAALgADCgcJDQABLgAFFAYJGgAXAEAaAA==.Tallyfan:BAAALgADCgcJEwAAAA==.Tamedsloth:BAAALgAECgQJBAABLgAECgQJBAAOAAAAAA==.Tandraella:BAAALgAECgQJBQABLgAFFAQJBgABAFUTAA==.Taroquin:BAAALgADCgkJCgAAAA==.',
Te='Ternay:BAAALgADCgIJAQAAAA==.Teskhamen:BAAALgAECgcJDAAAAA==.Tetamesh:BAAALgADCgQJBAAAAA==.',
Th='Theskabandit:BAAALgADCgcJEQAAAA==.Thrustruggle:BAAALgADCgEJAQAAAA==.',
Ti='Tiamot:BAAALgADCgUJCAAAAA==.',
To='Tojikitoushi:BAABLgAECn8wAAIQAAkJkSC4AgDHAgAQAAkJkSC4AgDHAgAAAA==.Tombs:BAAALgAECgYJCAAAAA==.Tonsonger:BAAALgAECgQJBAAAAA==.Totenhammer:BAAALgAECgQJCwAAAA==.Totenplage:BAAALgAECgQJBAAAAA==.',
Tr='Trid:BAAALgAECggJCAAAAA==.Tristex:BAAALgAECgUJBQABLgAECggJFwAWAP8bAA==.',
Tu='Tuha:BAAALgAFFAIJAgAAAA==.',
Tw='Twergstronk:BAAALgADCgEJAQAAAA==.',
Ty='Tyrolia:BAAALgAECgMJAwAAAA==.',
Um='Umibozu:BAAALgAECgIJAgAAAA==.',
Va='Valliya:BAAALgAECgYJCgAAAA==.',
Ve='Velratha:BAABLgAECn8UAAInAAgJtQ80DAB2AQAnAAgJtQ80DAB2AQAAAA==.Vesfu:BAAALgADCgEJAQAAAA==.Vesi:BAAALgADCgcJCgAAAA==.Vextt:BAABLgAECn8eAAMkAAgJDRh7IgCLAQAkAAcJRxt7IgCLAQAeAAIJeBjLXAA/AAAAAA==.',
Vi='Vicsta:BAAALgAECgYJBwAAAA==.',
Vo='Voidrend:BAAALgAECgQJBwAAAA==.Volight:BAAALgADCgYJCQAAAA==.Volke:BAABLgAECn8nAAIoAAkJMxZ+FwAfAgAoAAkJMxZ+FwAfAgAAAA==.Volq:BAAALgAECgEJAQAAAA==.Voltarix:BAAALgAECgQJBAAAAA==.Voodoopriest:BAABLgAECn8YAAILAAcJMwRDpAAQAQALAAcJMwRDpAAQAQAAAA==.Voyria:BAABLgAECn8vAAQXAAkJgQdPYwDqAAAXAAgJ9QRPYwDqAAAWAAUJIQWbUgCTAAAaAAIJwQJNPQAzAAAAAA==.',
Vs='Vs:BAAALgAECgYJBgAAAA==.',
Vy='Vynlenn:BAAALgADCgMJAwAAAA==.Vyskaar:BAAALgADCgEJAQAAAA==.Vyskar:BAAALgAECgUJBQAAAA==.',
Wa='Warm:BAACLgAFFH8VAAITAAYJWhuCBACeAQATAAYJWhuCBACeAQAuAAQKfycAAhMACQkTImsIAPMCABMACQkTImsIAPMCAAAA.Warmlight:BAAALgAECgYJDAAAAA==.',
We='Weewu:BAAALgAECgQJBAAAAA==.Weeziveli:BAAALgAECgQJDQAAAA==.Weledish:BAACLgAFFH8QAAIJAAMJ8hukVwATAQAJAAMJ8hukVwATAQAuAAQKfyoAAgkACQnsGo0yADACAAkACQnsGo0yADACAAAA.Weleron:BAAALgAECgQJBAAAAA==.',
Wi='Wienercat:BAABLgAECn8hAAIXAAcJ6SQVDADhAgAXAAcJ6SQVDADhAgABLgAECggJJwANAHcjAA==.Windmacedu:BAAALgAECgYJCgAAAA==.',
Xt='Xtreeme:BAAALgAECgIJAgAAAA==.',
Ya='Yael:BAABLgAECn8yAAICAAkJeB5VFQB8AgACAAkJeB5VFQB8AgAAAA==.',
Za='Zarewien:BAABLgAECn8uAAIeAAkJ6AqFJAB8AQAeAAkJ6AqFJAB8AQAAAA==.',
Ze='Zeddicus:BAAALgAECgMJAwAAAA==.',
Zi='Ziddles:BAAALgAECgcJEgAAAA==.',
Zo='Zomgdk:BAAALgAECgEJAgABLgAECggJNwAUAFYfAA==.Zomgmonk:BAABLgAECn83AAIUAAgJVh/GDABKAgAUAAgJVh/GDABKAgAAAA==.Zomgzilla:BAAALgAECggJAQABLgAECggJNwAUAFYfAA==.',
Zu='Zuraq:BAAALgAECgEJBQAAAA==.Zurisdad:BAABLgAECn80AAIUAAkJPh62BgCwAgAUAAkJPh62BgCwAgABLgAFFAUJEgAJAMYXAA==.Zurishmi:BAACLgAFFH8cAAINAAUJ/h5lBQB3AQANAAUJ/h5lBQB3AQAuAAQKfzMAAg0ACQk6JssAAMADAA0ACQk6JssAAMADAAAA.',
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
