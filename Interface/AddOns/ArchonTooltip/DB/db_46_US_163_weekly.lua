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

local lookup = {'Paladin-Holy','DemonHunter-Devourer','Rogue-Subtlety','Rogue-Outlaw','DemonHunter-Havoc','Hunter-BeastMastery','Paladin-Retribution','DeathKnight-Unholy','Mage-Frost','Hunter-Marksmanship','Warlock-Demonology','Paladin-Protection','Druid-Restoration','Unknown-Unknown','Warrior-Fury','Warrior-Protection','Warrior-Arms','Shaman-Enhancement','Rogue-Assassination','Hunter-Survival','Monk-Windwalker','Monk-Brewmaster','Druid-Balance','DeathKnight-Frost','Warlock-Affliction','Druid-Guardian','Druid-Feral','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Blood','Priest-Holy','Priest-Shadow','Mage-Arcane','Priest-Discipline','Warlock-Destruction','Shaman-Restoration','Shaman-Elemental','DemonHunter-Vengeance','Evoker-Preservation','Monk-Mistweaver',}
local provider = {region='US',realm='Nathrezim',name='US',type='weekly',zone=46,date='2026-06-13',data={Ab='Abysm:BAAALgADCgkJDwAAAA==.',
Ac='Achillios:BAAALgADCgMJAwABLgAFFAQJBgABAFUTAA==.',
Ad='Adorabull:BAAALgAECgQJBgABLgAECgkJIQACAKsdAA==.',
Ae='Aemun:BAACLgAFFH8HAAIDAAMJcxO9JgDqAAADAAMJcxO9JgDqAAAuAAQKf0YAAwMACQnrHeoHAKcCAAMACQnrHeoHAKcCAAQABgmUCbAIAPYAAAAA.',
Ag='Aggfu:BAAALgADCgYJBgAAAA==.',
Ak='Akeeli:BAAALgADCgQJBAAAAA==.Akelita:BAABLgAECn8hAAMFAAYJrxjBJABNAQAFAAYJrxjBJABNAQACAAUJcAjvyQCXAAAAAA==.',
Al='Alailea:BAABLgAECn9DAAIGAAkJMxS/PADpAQAGAAkJMxS/PADpAQAAAA==.Aloepaw:BAAALgAECgEJAQAAAA==.Alragnar:BAAALgAECgIJAgAAAA==.Alwysafkable:BAAALgAFFAIJBAAAAA==.',
Am='Amageadin:BAAALgADCgkJCQAAAA==.Amazadin:BAACLgAFFH8GAAIBAAQJVRMeJgDqAAABAAQJVRMeJgDqAAAuAAQKfxkAAwEACAkpHO8bADUCAAEACAkpHO8bADUCAAcAAgncElQwAXkAAAAA.Amazashock:BAAALgAECgUJDQABLgAFFAQJBgABAFUTAA==.',
An='Andiwin:BAABLgAECn8ZAAIIAAgJ9Q8TaACUAQAIAAgJ9Q8TaACUAQAAAA==.Andurthil:BAABLgAECn8oAAIJAAgJUw0OjQBaAQAJAAgJUw0OjQBaAQAAAA==.Anzul:BAAALgAECgUJBgAAAA==.',
Ar='Archive:BAAALgAECgkJCwAAAA==.Artistic:BAABLgAECn8cAAIGAAgJeBntPwDeAQAGAAgJeBntPwDeAQAAAA==.Arubion:BAABLgAECn8ZAAIHAAgJSxEvYACuAQAHAAgJSxEvYACuAQAAAA==.Arylanna:BAAALgAECgYJDQAAAA==.',
As='Asure:BAABLgAECn8tAAMGAAkJ/hdvKQA0AgAGAAkJ/hdvKQA0AgAKAAYJTgfdTwAPAQAAAA==.',
Az='Azerith:BAAALgAECgYJDwAAAA==.',
Ba='Badmorda:BAAALgADCgEJAQAAAA==.',
Be='Bearforceone:BAAALgADCgMJAwAAAA==.',
Bi='Bipolar:BAAALgADCgEJAQAAAA==.',
Bl='Blackheart:BAABLgAECn8bAAILAAgJnBjCLQBWAgALAAgJnBjCLQBWAgAAAA==.Blodreina:BAAALgADCgUJCQAAAA==.Bloodarchon:BAABLgAECn8jAAMHAAkJxhURQgD+AQAHAAkJxhURQgD+AQAMAAYJnQlhMACiAAAAAA==.Bloodtemplar:BAABLgAECn8sAAIHAAkJNho+JwBkAgAHAAkJNho+JwBkAgAAAA==.',
Bo='Bombs:BAAALgAECgQJEgABLgAFFAQJBwANAMsKAA==.Bonesy:BAAALgAECgYJBgAAAA==.Bouren:BAAALgAECgEJAQAAAA==.',
Br='Bravia:BAAALgADCgUJBwAAAA==.Brewdogg:BAAALgADCgcJBwAAAA==.Brokasa:BAAALgADCgIJAgAAAA==.Brutalitops:BAAALgADCgMJAwAAAA==.Brutusdabull:BAAALgAECgYJBgAAAA==.Brônze:BAAALgADCgQJBAAAAA==.',
Bu='Burdomew:BAAALgADCgEJAQAAAA==.',
Ca='Cadbury:BAAALgADCgIJAgABLgAECgUJCAAOAAAAAA==.Canan:BAAALgAECgUJBgAAAA==.Canansbrew:BAAALgAECgEJAQAAAA==.Canestoast:BAAALgAECgEJAQAAAA==.Casmina:BAABLgAECn8WAAIPAAkJ7xlRIQBJAgAPAAkJ7xlRIQBJAgAAAA==.Castiell:BAAALgADCgUJBgAAAA==.Catalystic:BAAALgADCgEJAQAAAA==.Catd:BAAALgAECgEJAgAAAA==.',
Ce='Celum:BAABLgAECn8eAAIIAAcJnwceuQAEAQAIAAcJnwceuQAEAQAAAA==.Ceola:BAABLgAECn8eAAMQAAcJhA0pJgD9AAAQAAcJSwwpJgD9AAARAAEJ/AsUegAtAAAAAA==.',
Ch='Chamming:BAAALgADCgIJAgAAAA==.Chaquén:BAACLgAFFH8IAAISAAMJVBS3DQDfAAASAAMJVBS3DQDfAAAuAAQKfyIAAhIACQn6GaMHAEwCABIACQn6GaMHAEwCAAAA.Charizard:BAAALgAECgEJAQAAAA==.Charmander:BAABLgAECn8fAAQTAAYJshfzCgCAAQATAAYJshfzCgCAAQADAAQJUgkyRwCWAAAEAAMJ2wS2GgB2AAAAAA==.Chaw:BAACLgAFFH8aAAMUAAgJmh2aAQBEAgAUAAgJXhiaAQBEAgAGAAEJcCamIQBdAAAuAAQKfzIABBQACQnuJNYDAPUCABQACQnsJNYDAPUCAAoABwnWHy0iABQCAAYABAk3I1BIAJEBAAAA.Chenkenichi:BAACLgAFFH8GAAIVAAMJTgaoKwCWAAAVAAMJTgaoKwCWAAAuAAQKfyoAAxUACQn/CcMtAFABABUACQn/CcMtAFABABYABQkoAqtoAJ8AAAAA.Chergar:BAACLgAFFH8MAAIQAAUJkhsSEwAGAQAQAAUJkhsSEwAGAQAuAAQKfx4AAhAACQkVIkwFAOkCABAACQkVIkwFAOkCAAAA.Chskie:BAAALgADCgUJBQAAAA==.Chsky:BAAALgADCgUJBQAAAA==.Chuiyi:BAAALgAECgEJAgAAAA==.',
Ci='Cinny:BAABLgAECn9GAAIGAAkJchyXGgCBAgAGAAkJchyXGgCBAgAAAA==.Cinnyrolls:BAABLgAECn8XAAMXAAgJ/xuoGwDpAQAXAAgJ/xuoGwDpAQANAAQJtBBhhwDHAAAAAA==.Cityairlines:BAABLgAECn8nAAIYAAkJuRTZCwC3AQAYAAkJuRTZCwC3AQAAAA==.',
Cl='Clare:BAAALgAECgYJCQAAAA==.',
Cm='Cmoneyy:BAAALgAECgYJBQAAAA==.',
Co='Cogrolls:BAAALgAECggJCQAAAA==.Cooldukenuke:BAACLgAFFH8KAAIBAAMJqRf4DwDaAAABAAMJqRf4DwDaAAAuAAQKfycAAgEACQmjHDoTAHkCAAEACQmjHDoTAHkCAAAA.',
Cr='Creepychalk:BAABLgAECn8WAAMZAAcJ4QsMFQAfAQAZAAcJ4QsMFQAfAQALAAEJsAEsYAEcAAAAAA==.Criticize:BAABLgAECn8nAAIHAAgJ1gy/nAA6AQAHAAgJ1gy/nAA6AQAAAA==.',
Cs='Csor:BAAALgAECgMJAwAAAA==.Csorb:BAABLgAECn8xAAMaAAkJ8SDDBADEAgAaAAkJviDDBADEAgAbAAEJySXcOQBrAAAAAA==.Csoren:BAAALgAECgEJAQAAAA==.Csoro:BAAALgADCggJCAAAAA==.',
Cu='Cultivation:BAAALgAECgUJCAAAAA==.Cursedcanfly:BAACLgAFFH8YAAIcAAcJ6BykDgALAgAcAAcJ6BykDgALAgAuAAQKfzMAAxwACQnjJVwCAFcDABwACQnjJVwCAFcDAB0ABQnaFG8iABcBAAAA.',
Cw='Cw:BAAALgAECgEJAQAAAA==.',
De='Deathdogg:BAACLgAFFH8VAAMIAAUJxxmyYwAtAQAIAAQJxxmyYwAtAQAeAAEJAACmVAAAAAAuAAQKfykAAggACQlPII80ACoCAAgACQlPII80ACoCAAAA.Dejavu:BAACLgAFFH8aAAIWAAYJrBO0FgBlAQAWAAYJrBO0FgBlAQAuAAQKfykAAhYACQlAHeIaAMwBABYACQlAHeIaAMwBAAAA.Demivoi:BAAALgAECgYJBwAAAA==.Demona:BAAALgAECgEJAQAAAA==.Deppthcharge:BAAALgAECgYJDwAAAA==.Desdemona:BAAALgAECgcJDAAAAA==.Devimon:BAAALgADCgEJAQAAAA==.Devoi:BAAALgADCgEJAQAAAA==.',
Di='Dismonk:BAAALgAECgIJAgAAAA==.',
Do='Donrain:BAAALgAECgQJBAAAAA==.Dooghammer:BAABLgAECn8ZAAISAAkJQxqvCQAdAgASAAkJQxqvCQAdAgAAAA==.',
Dr='Dragussy:BAAALgADCgcJDQABLgAECgkJUAAQAIImAA==.Drakkana:BAAALgADCgYJBgAAAA==.',
Du='Dunkhan:BAAALgAECgEJAQABLgAECgYJDAAOAAAAAA==.Duplexity:BAABLgAECn9QAAMQAAkJgiZKAACEAwAQAAkJgiZKAACEAwAPAAEJuCHthQBkAAAAAA==.',
Dw='Dwalin:BAAALgAECgMJCAABLgAECgkJGQASAEMaAA==.',
Ea='Eatmoorchikn:BAAALgAECgcJDAAAAA==.',
Ec='Ecko:BAAALgAECgEJAQAAAA==.',
Ed='Edolah:BAAALgAECgEJAQAAAA==.',
Eg='Egohakai:BAACLgAFFH8RAAIHAAUJrx2UPQAqAQAHAAUJrx2UPQAqAQAuAAQKfzAAAgcACQkUJXUIACUDAAcACQkUJXUIACUDAAAA.',
El='Eloi:BAABLgAECn8WAAMfAAgJbyB0CQDOAgAfAAgJbyB0CQDOAgAgAAEJUhP/fgA6AAABLgAECgkJMwANAEsdAA==.',
Em='Emieretta:BAABLgAECn88AAIIAAkJXRhNNQAnAgAIAAkJXRhNNQAnAgAAAA==.',
Eq='Eqdk:BAABLgAECn8hAAIIAAkJoxQxRgDtAQAIAAkJoxQxRgDtAQAAAA==.',
Er='Erret:BAACLgAFFH8UAAIJAAUJxhevXAAxAQAJAAUJxhevXAAxAQAuAAQKfzIAAwkACQlwI+cLABcDAAkACQlwI+cLABcDACEAAQngGZkTAEkAAAAA.',
Ey='Eyrie:BAAALgADCgYJBgAAAA==.',
Ez='Ezinder:BAABLgAECn8eAAIdAAcJDgZvEgDfAAAdAAcJDgZvEgDfAAAAAA==.',
Fa='Fabius:BAAALgADCgYJBgAAAA==.Faemos:BAAALgAECgkJCAAAAA==.Faience:BAABLgAECn8nAAIYAAkJMARdHQDeAAAYAAkJMARdHQDeAAAAAA==.Falorina:BAABLgAECn8xAAMFAAkJsSNlAgA9AwAFAAkJsSNlAgA9AwACAAEJAwXh6wAnAAAAAA==.Fathernature:BAACLgAFFH8JAAIXAAQJphBcIwAFAQAXAAQJphBcIwAFAQAuAAQKfx0AAxcACQknGd4oALgBABcACQknGd4oALgBABsAAQl5Bfw4ACUAAAAA.Fauna:BAAALgADCgMJAwAAAA==.Fazeup:BAAALgAECgcJBgAAAA==.',
Fe='Feldra:BAABLgAECn9EAAICAAkJQiKYBgAgAwACAAkJQiKYBgAgAwAAAA==.Felfaith:BAAALgAECgIJAgAAAA==.Fester:BAAALgADCgUJBQABLgAECgkJJgALAJ0WAA==.',
Fi='Fightforbeer:BAAALgAECgEJAQAAAA==.Finnin:BAABLgAECn8jAAMPAAkJCSQ6CwCyAgAPAAkJCSQ6CwCyAgARAAEJ0gZ8SAAkAAAAAA==.',
Fo='Food:BAABLgAECn8mAAIGAAkJoRgrIQA/AgAGAAkJoRgrIQA/AgAAAA==.Formidabull:BAAALgAECgEJAQABLgAECgkJIQACAKsdAA==.Foxdiez:BAAALgAECggJEQAAAA==.',
Fr='Fredde:BAAALgADCgEJAQAAAA==.Freidafondle:BAAALgAECgYJEgAAAA==.Frostbite:BAAALgAECgcJCwAAAA==.Frozenfaith:BAABLgAECn8mAAMiAAkJUwsDLwBiAQAiAAgJ1gsDLwBiAQAfAAMJMgSAYwBNAAAAAA==.',
Ft='Fthemeta:BAAALgADCgIJAgAAAA==.',
Fu='Fulci:BAAALgADCgUJBQAAAA==.Furioushealz:BAABLgAECn8nAAIHAAkJpxkIPgALAgAHAAkJpxkIPgALAgAAAA==.Furiouswind:BAAALgADCgEJAQAAAA==.',
Ga='Gardrius:BAAALgADCgYJBwAAAA==.',
Gh='Ghettomike:BAABLgAECn8pAAIIAAkJAB6LNAAqAgAIAAkJAB6LNAAqAgAAAA==.Ghoulbane:BAAALgADCgYJCgAAAA==.',
Gi='Gibbits:BAAALgAECgcJCQAAAA==.Giranimo:BAABLgAECn8mAAIGAAkJKRMXOgDyAQAGAAkJKRMXOgDyAQAAAA==.',
Gl='Glabados:BAAALgAECgIJAwABLgAECgkJJwAWADciAA==.Glossy:BAACLgAFFH8fAAMDAAcJch4MBwAuAgADAAcJch4MBwAuAgAEAAMJ4hBGDACUAAAuAAQKfzIABAMACQmEJqoBAFQDAAMACQmEJqoBAFQDABMAAgkNHzAUALsAAAQAAgmEIXsVALcAAAAA.Glossycumbus:BAAALgADCgYJBgABLgAFFAcJHwADAHIeAA==.Glossydh:BAAALgAECgYJBgABLgAFFAcJHwADAHIeAA==.Glossydk:BAAALgAECgQJBQABLgAFFAcJHwADAHIeAA==.Glossylock:BAAALgADCgcJDQABLgAFFAcJHwADAHIeAA==.',
Go='Golbigold:BAAALgAECgEJAQAAAA==.Goopy:BAAALgAECgMJAwABLgAECgYJBgAOAAAAAA==.Gorl:BAAALgAECgEJAQAAAA==.',
Gr='Grayhoff:BAABLgAECn8cAAIPAAkJkAufLwCPAQAPAAkJkAufLwCPAQAAAA==.Greathoof:BAAALgADCgMJAwAAAA==.Grewsom:BAACLgAFFH8XAAIHAAUJvhybEwDAAQAHAAUJvhybEwDAAQAuAAQKfywAAwcACAniJWMJAEYDAAcACAniJWMJAEYDAAwABQnzIJoWAGsBAAAA.',
Gu='Gulmok:BAAALgADCgUJBQAAAA==.Guwugga:BAABLgAECn8eAAIjAAcJXBBMEQAtAQAjAAcJXBBMEQAtAQAAAA==.',
Ha='Halîk:BAABLgAECn8XAAIBAAkJvhwJLADXAQABAAkJvhwJLADXAQAAAA==.Haraka:BAAALgAECgMJBAAAAA==.Harmshock:BAABLgAECn89AAISAAkJhCSsAgDqAgASAAkJhCSsAgDqAgAAAA==.Hathina:BAACLgAFFH8UAAMPAAcJSh5tCQDAAQAPAAYJcyJtCQDAAQARAAEJfAk0PgBIAAAuAAQKfzMAAw8ACQnTJkEBAHEDAA8ACQnTJkEBAHEDABEAAwmCHykeAP4AAAAA.',
He='Heket:BAABLgAECn8wAAIHAAgJtwjerwAcAQAHAAgJtwjerwAcAQAAAA==.Hektric:BAAALgAECgMJAwAAAA==.Helpinghandz:BAAALgAECgYJBgABLgAFFAYJFwAPAKEZAA==.',
Hi='Highdra:BAAALgAECgYJEwAAAA==.Hill:BAABLgAECn8oAAIGAAkJhR/7FgCAAgAGAAkJhR/7FgCAAgAAAA==.Hive:BAABLgAECn8wAAIPAAkJThhbFQBEAgAPAAkJThhbFQBEAgAAAA==.',
Ho='Holygem:BAAALgAECgYJCgAAAA==.Holypower:BAAALgADCgcJDQAAAA==.Hotdogwater:BAABLgAECn8nAAMkAAgJdyOGCgAKAwAkAAgJdyOGCgAKAwAlAAQJ5gk/egB7AAAAAA==.',
Hu='Husentar:BAABLgAECn87AAIJAAkJ8CADFQDYAgAJAAkJ8CADFQDYAgAAAA==.Huuhablo:BAABLgAECn9AAAICAAkJjRyFGAB/AgACAAkJjRyFGAB/AgAAAA==.',
Ic='Icaron:BAAALgAECgcJDwAAAA==.',
Ig='Igothots:BAAALgAECgUJCgAAAA==.',
Il='Illuminottey:BAABLgAECn8UAAIHAAkJmQ/XkwBJAQAHAAkJmQ/XkwBJAQAAAA==.',
In='Inferium:BAAALgADCgYJBgABLgAFFAQJDwAOAAAAAA==.Infernom:BAAALgADCgMJAwABLgAFFAQJDwAOAAAAAA==.Insatiabull:BAABLgAECn8hAAMCAAkJqx2+EgDqAgACAAgJ7x6+EgDqAgAFAAEJyxQmYwBCAAAAAA==.',
Io='Iolchsk:BAAALgAECgQJDAAAAA==.',
Is='Ishaa:BAAALgAECgYJCAAAAA==.',
Ja='Jacksof:BAABLgAECn8UAAMgAAYJ7gUrXQCeAAAgAAYJ7gUrXQCeAAAiAAQJOQS3agBSAAAAAA==.Jackstands:BAABLgAECn9WAAMkAAkJmSHMBgBAAwAkAAkJmSHMBgBAAwASAAgJgAWCHAAUAQAAAA==.Jagerin:BAAALgAECgYJCwABLgAECgkJJwAWADciAA==.January:BAAALgAECgYJCAABLgAFFAUJEQAGABoVAA==.Jasmyne:BAAALgADCgYJBgAAAA==.',
Je='Jeromy:BAAALgAECgEJAQAAAA==.Jesse:BAAALgADCgIJAgAAAA==.',
Ji='Jiffi:BAABLgAECn8ZAAImAAgJyRrwBQA8AgAmAAgJyRrwBQA8AgAAAA==.Jinksy:BAAALgAECgYJDwAAAA==.',
Jm='Jme:BAAALgAECgcJCQAAAA==.',
Jr='Jredz:BAAALgADCgEJAQAAAA==.',
Ju='Juanwick:BAAALgADCgQJBAAAAA==.Jubag:BAAALgADCgIJAgAAAA==.Jumpercables:BAAALgAECgEJBAAAAA==.Junn:BAABLgAECn8nAAIlAAkJmBM1JgC1AQAlAAkJmBM1JgC1AQAAAA==.Justiciar:BAAALgAECgEJAQAAAA==.',
['Já']='Jánuary:BAAALgAECgUJBQAAAA==.',
Ka='Kahayman:BAACLgAFFH8PAAIJAAMJlA50fwDfAAAJAAMJlA50fwDfAAAuAAQKfzEAAgkACQmDGSEsAGYCAAkACQmDGSEsAGYCAAAA.Kamacha:BAAALgAECgMJBQAAAA==.Kamaldren:BAAALgADCgEJAQAAAA==.Karellen:BAABLgAECn8UAAMdAAgJTgxkCwBcAQAdAAgJTgxkCwBcAQAcAAUJlAQfcgCAAAAAAA==.Kathren:BAAALgAECgYJBwAAAA==.',
Kh='Khathani:BAABLgAECn8YAAMGAAYJTxxEVQCfAQAGAAYJTxxEVQCfAQAKAAQJHQvZIACmAAAAAA==.',
Ki='Kieran:BAAALgAECgMJAwAAAA==.Kirara:BAAALgAECgMJAwAAAA==.',
Kn='Knobgoblinn:BAAALgAECgQJBAAAAA==.',
Ko='Komojo:BAABLgAECn8rAAIHAAgJUREvdQCBAQAHAAgJUREvdQCBAQAAAA==.Koriggan:BAABLgAECn8yAAQUAAkJZhKTEwAKAgAUAAkJZhKTEwAKAgAGAAYJKhB6VQBoAQAKAAEJ6QBlmwAUAAAAAA==.',
Kr='Krea:BAABLgAECn80AAIMAAkJWyKAAgAFAwAMAAkJWyKAAgAFAwAAAA==.Krixx:BAAALgADCgEJAQAAAA==.Kroval:BAAALgAECgUJBQAAAA==.Krystagosa:BAABLgAECn85AAQnAAkJiRb/CABXAgAnAAkJiRb/CABXAgAcAAYJJg/xTAD1AAAdAAMJVApbGQCFAAAAAA==.',
Ku='Kuriuh:BAABLgAECn8mAAILAAkJnRZsOgDvAQALAAkJnRZsOgDvAQAAAA==.Kurtcobainn:BAAALgADCgkJCQAAAA==.',
La='Lang:BAABLgAECn87AAImAAkJ1x3KAwCUAgAmAAkJ1x3KAwCUAgAAAA==.',
Le='Legionslamm:BAAALgADCgUJBQAAAA==.Leonldas:BAAALgADCgEJAQAAAA==.',
Li='Lightsfaith:BAAALgADCgYJBgABLgAECgkJJgAiAFMLAA==.',
Lo='Lodix:BAAALgAFFAIJBAAAAA==.Loopey:BAAALgAECgcJEAABLgAFFAYJGgAWAKwTAA==.Lorethil:BAAALgAECgYJDAAAAA==.',
Lu='Luceriss:BAABLgAECn8fAAIDAAkJtA4qGwC6AQADAAkJtA4qGwC6AQAAAA==.Luminous:BAAALgADCgcJCAABLgAECgkJJgALAJ0WAA==.',
Ma='Maeroth:BAAALgADCgUJBQABLgAFFAgJFgALAFULAA==.Magicboi:BAABLgAECn8YAAIJAAcJTQ/WnQA7AQAJAAcJTQ/WnQA7AQAAAA==.Magwar:BAACLgAFFH8RAAIPAAcJUxU3CADUAQAPAAcJUxU3CADUAQAuAAQKfzEAAg8ACQlXIf4IANECAA8ACQlXIf4IANECAAAA.Maike:BAABLgAECn8wAAMTAAkJrxeSCAC9AQATAAgJQBSSCAC9AQADAAUJtxXtIwBxAQAAAA==.Marcelyne:BAAALgAECgYJCAABLgAECgkJJAALAPYTAA==.Marothius:BAACLgAFFH8WAAQLAAgJVQu7JgChAQALAAcJbgq7JgChAQAjAAEJvxAUFABWAAAZAAEJ3AKsLAA2AAAuAAQKfzMABAsACQlhHrsjAE8CAAsACQlQHLsjAE8CACMABgmMHBAXAJEBABkAAgnLGn4hAK8AAAAA.Martaug:BAABLgAECn8lAAIkAAkJJx9tEgC3AgAkAAkJJx9tEgC3AgAAAA==.Marune:BAAALgAECgkJDwAAAA==.Maurice:BAAALgADCgYJCwAAAA==.Maverage:BAABLgAECn84AAMPAAkJDCJoBwDnAgAPAAkJDCJoBwDnAgARAAYJ6xP1KgAcAQAAAA==.Mawg:BAAALgAECgYJBwAAAA==.Mayfair:BAABLgAECn8iAAMkAAcJORUgOgDCAQAkAAcJORUgOgDCAQAlAAYJ/BI6QgAmAQAAAA==.Mayia:BAAALgAECgcJBwAAAA==.',
Mb='Mbarnes:BAAALgAECgQJBwAAAA==.',
Me='Melee:BAACLgAFFH87AAIHAAkJKiVQAABiAwAHAAkJKiVQAABiAwAuAAQKfxYAAgcACQmZJj0CALoDAAcACQmZJj0CALoDAAAA.',
Mi='Midnightfear:BAAALgADCgcJBwAAAA==.Mikeyy:BAAALgADCgMJAwAAAA==.Mimoza:BAAALgAECgYJCgAAAA==.Minibeer:BAAALgAECgYJEgAAAA==.Minimee:BAAALgAECgYJCgAAAA==.Miquella:BAAALgAECggJEwAAAA==.Misohotramen:BAACLgAFFH8UAAICAAUJQxuAOgA0AQACAAUJQxuAOgA0AQAuAAQKfyQAAgIACQnQILUzACsCAAIACQnQILUzACsCAAAA.',
Mo='Moist:BAABLgAECn87AAIaAAkJaCMfAgAhAwAaAAkJaCMfAgAhAwAAAA==.Monkstrosity:BAAALgAECgMJAwAAAA==.Moonlock:BAAALgADCgYJCgAAAA==.Moor:BAABLgAECn8aAAIhAAkJrwZ6BwAwAQAhAAkJrwZ6BwAwAQAAAA==.Mordakka:BAAALgAECgYJCQAAAA==.Morior:BAABLgAECn8+AAMLAAkJShvlIQBZAgALAAkJShvlIQBZAgAjAAIJMBi0UQB5AAAAAA==.Motgustus:BAAALgAFFAEJAQAAAA==.',
Mu='Muirfire:BAAALgADCgYJBgAAAA==.Murrda:BAACLgAFFH8FAAILAAIJ3BJ7lgCRAAALAAIJ3BJ7lgCRAAAuAAQKfzcAAwsACQmpIXkMAOgCAAsACQmpIXkMAOgCABkAAQnTE244AEEAAAAA.Musk:BAAALgAECgIJBQABLgAECggJLwAJAOAWAA==.Muskrattsam:BAABLgAECn8vAAIJAAgJ4BaBRwACAgAJAAgJ4BaBRwACAgAAAA==.',
My='Myravia:BAABLgAECn8WAAIJAAcJrxAwkQCxAQAJAAcJrxAwkQCxAQAAAA==.Myrokos:BAABLgAECn9RAAIHAAkJ+SLlCQAXAwAHAAkJ+SLlCQAXAwAAAA==.',
['Mó']='Mónónoke:BAAALgADCgMJAwAAAA==.',
['Mö']='Möokss:BAAALgADCgQJAgAAAA==.',
Na='Nailo:BAABLgAECn9WAAIaAAkJeBS3DwDmAQAaAAkJeBS3DwDmAQAAAA==.Nails:BAAALgAECgQJBgAAAA==.Nathanos:BAAALgAECggJCwAAAA==.',
Ne='Nepetala:BAAALgAECgYJBgABLgAFFAYJDAAcAOEQAA==.Nezar:BAAALgAFFAEJAwABLgAFFAEJBQAmAFcYAA==.',
Nh='Nhat:BAAALgAECgMJAwAAAA==.',
Ni='Niaah:BAAALgADCgYJAQABLgAECgkJFwABAL4cAA==.Niddy:BAACLgAFFH8GAAIJAAMJtRB5fADlAAAJAAMJtRB5fADlAAAuAAQKf0EAAgkACQlEGBAzAEoCAAkACQlEGBAzAEoCAAAA.Nisardela:BAAALgADCgMJAwAAAA==.',
No='Nobudy:BAACLgAFFH8fAAMgAAgJyRyjBAAzAgAgAAgJyRyjBAAzAgAiAAQJzAIHLwDQAAAuAAQKfzEABCAACQm6JCsEABgDACAACQm6JCsEABgDAB8ABgnIFcYuAIgBACIAAgnNBOJZAC4AAAAA.Noel:BAABLgAECn8rAAIfAAcJ1Ri3HQDTAQAfAAcJ1Ri3HQDTAQAAAA==.Nomsayin:BAACLgAFFH8GAAILAAMJHQvUiACuAAALAAMJHQvUiACuAAAuAAQKfzAAAgsACQkuGRYzAEACAAsACQkuGRYzAEACAAAA.Nonospot:BAABLgAECn8sAAMgAAkJmhceEwA4AgAgAAkJmhceEwA4AgAiAAEJvANJWgAuAAAAAA==.Noobuddy:BAAALgAECgUJCgABLgAFFAgJHwAgAMkcAA==.Noraboo:BAABLgAECn8jAAMhAAgJQRqjBAD7AQAhAAYJbxyjBAD7AQAJAAgJmRh4YAC8AQABLgAECgkJKwAVABsdAA==.Norannestra:BAAALgAECgYJDQAAAA==.Novalicious:BAAALgADCgIJAgAAAA==.Novasera:BAAALgAECgcJCAAAAA==.',
Nu='Nubmuffin:BAAALgADCgUJBQAAAA==.',
Nv='Nvied:BAABLgAECn8cAAMLAAkJpRQfRADNAQALAAgJpRQfRADNAQAjAAEJAAD5cwAxAAAAAA==.',
Ny='Nyctt:BAABLgAECn8YAAMDAAkJ8BlNGQA6AgADAAkJUhhNGQA6AgATAAIJ5xdoFgCSAAAAAA==.Nystra:BAABLgAECn8WAAILAAkJAhjjJQBFAgALAAkJAhjjJQBFAgAAAA==.Nyzstra:BAABLgAECn8wAAIJAAkJXiIvGQDAAgAJAAkJXiIvGQDAAgAAAA==.',
['Nê']='Nêwt:BAACLgAFFH8PAAIJAAMJaBGifADkAAAJAAMJaBGifADkAAAuAAQKfz4AAgkACQn/HPEqAGwCAAkACQn/HPEqAGwCAAAA.',
['Nì']='Nìrvana:BAAALgAECgQJCwAAAA==.',
['Nú']='Núbmuffin:BAAALgAECgEJAgAAAA==.',
On='Onlybeams:BAABLgAECn8fAAICAAkJQBuqIABOAgACAAkJQBuqIABOAgAAAA==.',
Or='Orphu:BAAALgAECgEJAQAAAA==.',
Pa='Pallyplexity:BAAALgAECgYJBgABLgAECgkJUAAQAIImAA==.Palmiste:BAAALgAECgQJBgAAAA==.Pangoplexity:BAAALgADCgIJAgAAAA==.Parahsalin:BAAALgAECgEJAQABLgAECgYJEgAOAAAAAA==.Partyhard:BAAALgADCgkJGwAAAA==.Pastryblust:BAABLgAFFH8IAAIlAAUJARY3HwAeAQAlAAUJARY3HwAeAQAAAA==.Pastrydragon:BAACLgAFFH8LAAMcAAQJORbhEAD7AAAcAAQJORbhEAD7AAAdAAEJJxnDDABLAAAuAAQKfzAAAxwACAmrINUKAMgCABwACAmSHtUKAMgCAB0ABglYI5ULACICAAEuAAUUBQkIACUAARYA.',
Ph='Phaeliea:BAAALgAECgUJBQAAAA==.',
Pi='Pistachio:BAABLgAECn8bAAIFAAYJOA4DNADrAAAFAAYJOA4DNADrAAAAAA==.Pitviper:BAABLgAECn8mAAITAAkJ4x7AAwBqAgATAAkJ4x7AAwBqAgAAAA==.',
Po='Pocketrokit:BAAALgAECgkJDAAAAA==.Pogaca:BAAALgAECgcJDgABLgAECggJFwAXAP8bAA==.Portabull:BAAALgADCgcJBwABLgAECgkJIQACAKsdAA==.Possess:BAABLgAECn8mAAILAAcJVx0yRgDGAQALAAcJVx0yRgDGAQAAAA==.Pownora:BAABLgAECn8rAAMVAAkJGx10CwCIAgAVAAkJGx10CwCIAgAoAAIJ/Q00tgAxAAAAAA==.',
Ps='Psarchasm:BAABLgAECn8wAAIPAAkJlg3CLACfAQAPAAkJlg3CLACfAQAAAA==.',
Pu='Puck:BAAALgAECgEJAgAAAA==.Puffnstuff:BAAALgAECgUJBQAAAA==.Pugstar:BAAALgAECgMJAwAAAA==.',
Qe='Qel:BAAALgADCgYJCQAAAA==.',
Ra='Rai:BAABLgAECn87AAIGAAkJzSQLBgAwAwAGAAkJzSQLBgAwAwAAAA==.Rancidbeef:BAAALgAECgMJAwAAAA==.Rapha:BAABLgAECn8nAAIWAAkJNyJUBQDpAgAWAAkJNyJUBQDpAgAAAA==.Rayyzer:BAABLgAECn8eAAMDAAkJqCGMDABaAgADAAkJqCGMDABaAgATAAIJtBgTGgCWAAAAAA==.',
Re='Realrogue:BAAALgAECgYJCwABLgAECgkJUAAQAIImAA==.Rema:BAAALgADCgQJBAAAAA==.Reyna:BAAALgADCgUJBQAAAA==.',
Ri='Riddles:BAABLgAECn8eAAMaAAgJzB2WCQBNAgAaAAgJzB2WCQBNAgANAAEJFiOEtQBaAAAAAA==.Rincewind:BAAALgAECgEJAQAAAA==.',
Ro='Rossabella:BAABLgAECn9FAAMfAAkJahtYCwCuAgAfAAkJahtYCwCuAgAiAAgJ0w7HGwC4AQAAAA==.Rot:BAABLgAECn8nAAIeAAkJCSbcAgAYAwAeAAkJCSbcAgAYAwAAAA==.',
Ru='Rude:BAAALgAECgYJBgABLgAFFAcJFAAPAEoeAA==.Ruzala:BAAALgADCgEJAQAAAA==.',
Sa='Samsonn:BAAALgADCgQJBAAAAA==.Sanctity:BAAALgADCgYJCgAAAA==.Santino:BAACLgAFFH8KAAINAAMJPQg0SwCLAAANAAMJPQg0SwCLAAAuAAQKfx4AAg0ACAlhGVMeAFECAA0ACAlhGVMeAFECAAEuAAUUAwkPAAkAlA4A.Saphlocket:BAAALgAECgYJEgAAAA==.Sathin:BAABLgAECn8yAAICAAkJmwrtXwBmAQACAAkJmwrtXwBmAQAAAA==.',
Sc='Scher:BAAALgADCgkJCwAAAA==.Scufalufagus:BAAALgAECgUJBQABLgAFFAgJFgALAFULAA==.',
Se='Seetick:BAAALgAECgIJBAAAAA==.Sefekat:BAAALgAECgEJAQABLgAECgkJHwACAEAbAA==.September:BAAALgAECgIJAgABLgAFFAUJEQAGABoVAA==.Sevatar:BAABLgAECn8nAAIFAAkJUg35HgB+AQAFAAkJUg35HgB+AQAAAA==.',
Sf='Sfcwarner:BAAALgAECgEJAQAAAA==.',
Sg='Sgtwarner:BAAALgAECgEJAgAAAA==.',
Sh='Shampooyou:BAABLgAECn8tAAIkAAgJwQh0XwA4AQAkAAgJwQh0XwA4AQAAAA==.Shockakhan:BAAALgAECggJDgAAAA==.Shocknstone:BAAALgADCgcJBwABLgAECgkJUAAQAIImAA==.',
Si='Silentmamba:BAAALgAECgEJAQAAAA==.Sinistra:BAAALgAECggJEwAAAA==.',
Sk='Skelecopter:BAAALgADCgMJAwAAAA==.',
Sl='Slapshot:BAAALgAECggJCwABLgAECggJFwAXAP8bAA==.',
Sn='Snowflake:BAAALgADCgcJBwAAAA==.',
Sp='Spellsteal:BAABLgAECn8lAAIJAAkJuxiUNwA3AgAJAAkJuxiUNwA3AgABLgAFFAQJEQAQAKAOAA==.Spicynudz:BAAALgAECgEJAQAAAA==.Spring:BAACLgAFFH8RAAMGAAUJGhVjQQAkAQAGAAUJGhVjQQAkAQAKAAEJpAAJLgA2AAAuAAQKfyUAAwYACQlfHdwuAB0CAAYACQkjHdwuAB0CAAoABgnTC/ZMAB0BAAAA.',
Ss='Ssgwarner:BAAALgAECgEJAQAAAA==.',
St='Stardel:BAAALgAECgYJDQABLgAFFAcJHQADABkkAA==.Sting:BAABLgAECn8cAAIGAAcJrQ+DbgBfAQAGAAcJrQ+DbgBfAQAAAA==.Stormclaw:BAABLgAECn8zAAMNAAkJSx1cEQDDAgANAAkJSx1cEQDDAgAXAAEJkBwadwBUAAAAAA==.Stormcrash:BAAALgADCgYJBgABLgAECgkJJgALAJ0WAA==.Stregoica:BAAALgADCgcJDgABLgAFFAgJFgALAFULAA==.',
Su='Suhfering:BAAALgADCgYJBgABLgAECgkJHwACAEAbAA==.Superbeef:BAAALgAECgEJAQAAAA==.Sushiiez:BAAALgADCgMJAwAAAA==.Suwo:BAAALgADCgIJAQAAAA==.',
Sy='Sychopath:BAAALgAECgQJCAAAAA==.Sykadelik:BAAALgAECgMJAwAAAA==.Syngoma:BAAALgADCgIJAgAAAA==.',
Ta='Tallron:BAACLgAFFH8dAAINAAgJBBleBwB+AgANAAgJBBleBwB+AgAuAAQKfy4AAw0ACQmaJLcJAPcCAA0ACQmaJLcJAPcCABcABQmPFSRBAAUBAAAA.Tallsera:BAAALgADCgcJDQABLgAFFAgJHQANAAQZAA==.Tallyfan:BAAALgADCgcJEwAAAA==.Tamedsloth:BAAALgAECgYJBgAAAA==.Tandraella:BAAALgAECgQJBQABLgAFFAQJBgABAFUTAA==.Tanthalos:BAAALgAECgUJBQAAAA==.Taroquin:BAAALgADCgkJCgAAAA==.',
Te='Ternay:BAAALgADCgIJAQAAAA==.Teskhamen:BAAALgAFFAEJAQAAAA==.Tetamesh:BAAALgADCgQJBAAAAA==.',
Th='Theskabandit:BAAALgADCgcJEQAAAA==.Thrustruggle:BAAALgAECgMJAwAAAA==.',
Ti='Tiamot:BAAALgADCgUJCAAAAA==.',
To='Toby:BAAALgAECgYJBgAAAA==.Tojikitoushi:BAACLgAFFH8FAAISAAMJyQ4tDwDNAAASAAMJyQ4tDwDNAAAuAAQKfzgAAhIACQnpIE4DANICABIACQnpIE4DANICAAAA.Tombs:BAAALgAECgYJCQAAAA==.Tonsonger:BAAALgAECgUJCAAAAA==.Totenhammer:BAAALgAECgQJCwAAAA==.Totenplage:BAAALgAECgQJBAAAAA==.',
Tr='Trid:BAAALgAECggJCAAAAA==.Tristex:BAAALgAECgUJBQABLgAECggJFwAXAP8bAA==.',
Tu='Tuha:BAAALgAFFAIJAgAAAA==.',
Tw='Twergstronk:BAAALgADCgEJAQAAAA==.',
Ty='Tyrolia:BAAALgAECgMJAwAAAA==.',
Um='Umibozu:BAAALgAECgIJAgAAAA==.',
Ur='Urchak:BAAALgAECgYJBgAAAA==.',
Va='Valliya:BAABLgAFFH8IAAIHAAMJbwNaggCmAAAHAAMJbwNaggCmAAAAAA==.',
Ve='Velratha:BAABLgAECn8UAAIZAAgJtQ80DAB2AQAZAAgJtQ80DAB2AQAAAA==.Vesfu:BAAALgADCgEJAQAAAA==.Vesi:BAAALgADCgcJCgAAAA==.Vextt:BAABLgAECn8eAAMgAAgJDRg1KgB/AQAgAAcJRxs1KgB/AQAfAAIJeBjRaQA8AAAAAA==.',
Vi='Vicsta:BAAALgAECgcJCgAAAA==.',
Vo='Voidrend:BAAALgAECgQJBwAAAA==.Voidwarner:BAAALgAECgMJAwAAAA==.Volight:BAAALgADCgYJCQAAAA==.Volke:BAABLgAECn8nAAIoAAkJMxYsHgAiAgAoAAkJMxYsHgAiAgAAAA==.Volmnk:BAAALgAECgUJCwAAAA==.Volq:BAAALgAECgEJAQAAAA==.Voltarix:BAAALgAECgYJCQAAAA==.Voodoopriest:BAABLgAECn8YAAILAAcJMwRDpAAQAQALAAcJMwRDpAAQAQAAAA==.Voyria:BAABLgAECn8xAAQNAAkJVwgxbwDkAAANAAgJ9QQxbwDkAAAXAAYJiQU/VQC2AAAbAAIJwQI6UwAuAAAAAA==.',
Vs='Vs:BAAALgAECgYJBgAAAA==.',
Vy='Vynlenn:BAAALgADCgMJAwAAAA==.Vyskaar:BAAALgADCgEJAQAAAA==.Vyskar:BAAALgAECgUJCQAAAA==.Vyskary:BAAALgAECgEJAgAAAA==.',
Wa='Warm:BAACLgAFFH8YAAIVAAgJsxo7AgBJAgAVAAgJsxo7AgBJAgAuAAQKfycAAhUACQkTImsIAPMCABUACQkTImsIAPMCAAAA.Warmlight:BAAALgAECgYJDAAAAA==.',
We='Weewu:BAAALgAECgQJBAABLgAECgYJBgAOAAAAAA==.Weeziveli:BAAALgAECgQJDQAAAA==.Weledish:BAACLgAFFH8bAAIJAAQJgx6CQABvAQAJAAQJgx6CQABvAQAuAAQKfywAAgkACQmuG5gvAFgCAAkACQmuG5gvAFgCAAAA.Weleron:BAAALgAECgUJBQAAAA==.',
Wh='Whystler:BAAALgAECgIJAgAAAA==.',
Wi='Wienercat:BAABLgAECn8hAAINAAcJ6SS0DgDeAgANAAcJ6SS0DgDeAgABLgAECggJJwAkAHcjAA==.Wimol:BAAALgAECgYJBgABLgAECgkJKwAVABsdAA==.Windmacedu:BAAALgAECgYJCgAAAA==.',
Xt='Xtreeme:BAAALgAECgIJAgAAAA==.',
Ya='Yael:BAABLgAECn80AAICAAkJeB5mGgBzAgACAAkJeB5mGgBzAgAAAA==.Yama:BAAALgAECgcJEAAAAA==.',
Za='Zamrazac:BAAALgAECgUJCAABLgAECgkJMwANAEsdAA==.Zarewien:BAABLgAECn8uAAIfAAkJ6AqCKwBoAQAfAAkJ6AqCKwBoAQAAAA==.',
Ze='Zeddicus:BAAALgAECgMJAwAAAA==.',
Zi='Ziddles:BAABLgAECn8aAAIUAAgJ+hvSEwAHAgAUAAgJ+hvSEwAHAgAAAA==.',
Zo='Zomgdk:BAAALgAECgEJAgABLgAECgkJRQAWAPsfAA==.Zomgmonk:BAABLgAECn9FAAIWAAkJ+x8WBQDuAgAWAAkJ+x8WBQDuAgAAAA==.Zomgzilla:BAAALgAECggJAQABLgAECgkJRQAWAPsfAA==.Zorep:BAAALgAECgEJAQAAAA==.Zorien:BAAALgAECgQJBAAAAA==.',
Zu='Zuraq:BAAALgAECgEJBgAAAA==.Zurisdad:BAABLgAECn83AAIWAAkJ8B69BwC3AgAWAAkJ8B69BwC3AgABLgAFFAUJFAAJAMYXAA==.Zurishmi:BAACLgAFFH8cAAIkAAUJ/h5lBQB3AQAkAAUJ/h5lBQB3AQAuAAQKfzMAAiQACQk6JoIBALkDACQACQk6JoIBALkDAAAA.',
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
