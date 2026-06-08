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

local lookup = {'Paladin-Holy','DemonHunter-Devourer','Rogue-Subtlety','Rogue-Outlaw','DemonHunter-Havoc','Hunter-BeastMastery','Paladin-Retribution','DeathKnight-Unholy','Mage-Frost','Hunter-Marksmanship','Warlock-Demonology','Paladin-Protection','Druid-Restoration','Unknown-Unknown','Warrior-Fury','Warrior-Protection','Shaman-Enhancement','Rogue-Assassination','Hunter-Survival','Monk-Windwalker','Monk-Brewmaster','Druid-Balance','DeathKnight-Frost','Warlock-Affliction','Druid-Guardian','Druid-Feral','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Blood','Priest-Holy','Priest-Shadow','Mage-Arcane','Warrior-Arms','Priest-Discipline','Warlock-Destruction','Shaman-Restoration','Shaman-Elemental','DemonHunter-Vengeance','Evoker-Preservation','Monk-Mistweaver',}
local provider = {region='US',realm='Nathrezim',name='US',type='weekly',zone=46,date='2026-06-06',data={Ab='Abysm:BAAALgADCgkJDwAAAA==.',
Ac='Achillios:BAAALgADCgMJAwABLgAFFAQJBgABAFUTAA==.',
Ad='Adorabull:BAAALgAECgQJBgABLgAECgkJIQACAKsdAA==.',
Ae='Aemun:BAABLgAECn9EAAMDAAkJrR2TCACSAgADAAkJrR2TCACSAgAEAAYJlAmwCAD2AAAAAA==.',
Ag='Aggfu:BAAALgADCgYJBgAAAA==.',
Ak='Akeeli:BAAALgADCgQJBAAAAA==.Akelita:BAABLgAECn8hAAMFAAYJrxjTIgBOAQAFAAYJrxjTIgBOAQACAAUJcAjnwgCXAAAAAA==.',
Al='Alailea:BAABLgAECn9DAAIGAAkJMxSaOADxAQAGAAkJMxSaOADxAQAAAA==.Aloepaw:BAAALgAECgEJAQAAAA==.Alragnar:BAAALgAECgIJAgAAAA==.Alwysafkable:BAAALgAFFAIJAgAAAA==.',
Am='Amageadin:BAAALgADCgkJCQAAAA==.Amazadin:BAACLgAFFH8GAAIBAAQJVRM+IwD6AAABAAQJVRM+IwD6AAAuAAQKfxkAAwEACAkpHO8bADUCAAEACAkpHO8bADUCAAcAAgncEkclAXsAAAAA.Amazashock:BAAALgAECgUJDQABLgAFFAQJBgABAFUTAA==.',
An='Andiwin:BAABLgAECn8ZAAIIAAgJ9Q8JYgCcAQAIAAgJ9Q8JYgCcAQAAAA==.Andurthil:BAABLgAECn8oAAIJAAgJUw0rhwBjAQAJAAgJUw0rhwBjAQAAAA==.Anzul:BAAALgAECgUJBgAAAA==.',
Ar='Archive:BAAALgAECgkJCwAAAA==.Artistic:BAABLgAECn8cAAIGAAgJeBm3OwDlAQAGAAgJeBm3OwDlAQAAAA==.Arubion:BAAALgAECggJEwAAAA==.Arylanna:BAAALgAECgYJDQAAAA==.',
As='Asure:BAABLgAECn8tAAMGAAkJ/heEJgA7AgAGAAkJ/heEJgA7AgAKAAYJTgfdTwAPAQAAAA==.',
Az='Azerith:BAAALgAECgYJDwAAAA==.',
Ba='Badmorda:BAAALgADCgEJAQAAAA==.',
Be='Bearforceone:BAAALgADCgMJAwAAAA==.',
Bi='Bipolar:BAAALgADCgEJAQAAAA==.',
Bl='Blackheart:BAABLgAECn8bAAILAAgJnBjCLQBWAgALAAgJnBjCLQBWAgAAAA==.Blodreina:BAAALgADCgUJCQAAAA==.Bloodarchon:BAABLgAECn8fAAMHAAgJ0hTNYgCgAQAHAAgJ0hTNYgCgAQAMAAYJnQmpLgCiAAAAAA==.Bloodtemplar:BAABLgAECn8nAAIHAAgJrhZBTwDPAQAHAAgJrhZBTwDPAQAAAA==.',
Bo='Bombs:BAAALgAECgQJEAABLgAFFAQJBwANAMsKAA==.Bonesy:BAAALgAECgYJBgAAAA==.Bouren:BAAALgAECgEJAQAAAA==.',
Br='Bravia:BAAALgADCgUJBwAAAA==.Brewdogg:BAAALgADCgcJBwAAAA==.Brutalitops:BAAALgADCgMJAwAAAA==.Brutusdabull:BAAALgAECgYJBgAAAA==.Brônze:BAAALgADCgQJBAAAAA==.',
Bu='Burdomew:BAAALgADCgEJAQAAAA==.',
Ca='Cadbury:BAAALgADCgIJAgABLgAECgUJCAAOAAAAAA==.Canan:BAAALgAECgUJBgAAAA==.Canansbrew:BAAALgAECgEJAQAAAA==.Canestoast:BAAALgAECgEJAQAAAA==.Casmina:BAABLgAECn8WAAIPAAkJ7xlRIQBJAgAPAAkJ7xlRIQBJAgAAAA==.Castiell:BAAALgADCgUJBgAAAA==.Catalystic:BAAALgADCgEJAQAAAA==.Catd:BAAALgAECgEJAgAAAA==.',
Ce='Celum:BAABLgAECn8eAAIIAAcJnwfGsQAIAQAIAAcJnwfGsQAIAQAAAA==.Ceola:BAABLgAECn8XAAIQAAcJSAcFKwDSAAAQAAcJSAcFKwDSAAAAAA==.',
Ch='Chamming:BAAALgADCgIJAgAAAA==.Chaquén:BAACLgAFFH8GAAIRAAIJ5RSWEACYAAARAAIJ5RSWEACYAAAuAAQKfyEAAhEACQnXGPQHADoCABEACQnXGPQHADoCAAAA.Charizard:BAAALgAECgEJAQAAAA==.Charmander:BAABLgAECn8fAAQSAAYJshfzCgCAAQASAAYJshfzCgCAAQADAAQJUglpRACWAAAEAAMJ2wSrGQB2AAAAAA==.Chaw:BAACLgAFFH8ZAAMTAAcJ3h99AgD3AQATAAcJwxl9AgD3AQAGAAEJcCamIQBdAAAuAAQKfzIABBMACQnuJIgDAPoCABMACQnsJIgDAPoCAAoABwnWHy0iABQCAAYABAk3I1BIAJEBAAAA.Chenkenichi:BAABLgAECn8kAAMUAAkJsAiFLwA9AQAUAAkJsAiFLwA9AQAVAAUJKAKraACfAAAAAA==.Chergar:BAACLgAFFH8MAAIQAAUJkhsHEQASAQAQAAUJkhsHEQASAQAuAAQKfx4AAhAACQkVIkwFAOkCABAACQkVIkwFAOkCAAAA.Chskie:BAAALgADCgUJBQAAAA==.Chsky:BAAALgADCgUJBQAAAA==.Chuiyi:BAAALgAECgEJAgAAAA==.',
Ci='Cinny:BAABLgAECn9BAAIGAAkJvRqKHgBkAgAGAAkJvRqKHgBkAgAAAA==.Cinnyrolls:BAABLgAECn8XAAMWAAgJ/xt6GgDqAQAWAAgJ/xt6GgDqAQANAAQJtBBhhwDHAAAAAA==.Cityairlines:BAABLgAECn8nAAIXAAkJuRTcCgC8AQAXAAkJuRTcCgC8AQAAAA==.',
Cl='Clare:BAAALgAECgYJCQAAAA==.',
Cm='Cmoneyy:BAAALgAECgYJBQAAAA==.',
Co='Cogrolls:BAAALgAECggJCQAAAA==.Cooldukenuke:BAACLgAFFH8KAAIBAAMJqRf4DwDaAAABAAMJqRf4DwDaAAAuAAQKfycAAgEACQmjHDoTAHkCAAEACQmjHDoTAHkCAAAA.',
Cr='Creepychalk:BAABLgAECn8WAAMYAAcJ4QvEEwAgAQAYAAcJ4QvEEwAgAQALAAEJsAGsVQEcAAAAAA==.Criticize:BAABLgAECn8nAAIHAAgJ1gz/lQA8AQAHAAgJ1gz/lQA8AQAAAA==.',
Cs='Csor:BAAALgAECgMJAwAAAA==.Csorb:BAABLgAECn8xAAMZAAkJ8SBtBADGAgAZAAkJviBtBADGAgAaAAEJySWDNgBrAAAAAA==.Csoren:BAAALgAECgEJAQAAAA==.Csoro:BAAALgADCggJCAAAAA==.',
Cu='Cultivation:BAAALgAECgUJCAAAAA==.Cursedcanfly:BAACLgAFFH8YAAIbAAcJ6Bw3DAAUAgAbAAcJ6Bw3DAAUAgAuAAQKfzMAAxsACQnjJT0CAFkDABsACQnjJT0CAFkDABwABQnaFG8iABcBAAAA.',
Cw='Cw:BAAALgAECgEJAQAAAA==.',
De='Deathdogg:BAACLgAFFH8VAAMIAAUJxxnSWAA1AQAIAAQJxxnSWAA1AQAdAAEJAACiTgAAAAAuAAQKfykAAggACQlPIIIxADACAAgACQlPIIIxADACAAAA.Dejavu:BAACLgAFFH8aAAIVAAYJrBNkFABqAQAVAAYJrBNkFABqAQAuAAQKfykAAhUACQlAHesZAM4BABUACQlAHesZAM4BAAAA.Demivoi:BAAALgAECgYJBwAAAA==.Demona:BAAALgAECgEJAQAAAA==.Deppthcharge:BAAALgAECgYJDwAAAA==.Desdemona:BAAALgAECgYJCgAAAA==.Devimon:BAAALgADCgEJAQAAAA==.Devoi:BAAALgADCgEJAQAAAA==.',
Di='Dismonk:BAAALgAECgEJAQAAAA==.',
Do='Donrain:BAAALgAECgQJBAAAAA==.Dooghammer:BAABLgAECn8ZAAIRAAkJQxofCQAgAgARAAkJQxofCQAgAgAAAA==.',
Dr='Dragussy:BAAALgADCgcJDQABLgAECgkJRwAQAFUmAA==.',
Du='Dunkhan:BAAALgAECgEJAQABLgAECgYJDAAOAAAAAA==.Duplexity:BAABLgAECn9HAAMQAAkJVSZuAAB5AwAQAAkJVSZuAAB5AwAPAAEJuCH7gABkAAAAAA==.',
Dw='Dwalin:BAAALgAECgMJCAABLgAECgkJGQARAEMaAA==.',
Ea='Eatmoorchikn:BAAALgAECgcJCgAAAA==.',
Ec='Ecko:BAAALgAECgEJAQAAAA==.',
Ed='Edolah:BAAALgAECgEJAQAAAA==.',
Eg='Egohakai:BAACLgAFFH8RAAIHAAUJrx2vNgAvAQAHAAUJrx2vNgAvAQAuAAQKfzAAAgcACQkUJa8HACcDAAcACQkUJa8HACcDAAAA.',
El='Eloi:BAABLgAECn8WAAMeAAgJbyDRCADRAgAeAAgJbyDRCADRAgAfAAEJUhOqeQA6AAABLgAECgkJMwANAEsdAA==.',
Em='Emieretta:BAABLgAECn85AAIIAAkJGRjENAAjAgAIAAkJGRjENAAjAgAAAA==.',
Eq='Eqdk:BAABLgAECn8hAAIIAAkJoxSPQgDzAQAIAAkJoxSPQgDzAQAAAA==.',
Er='Erret:BAACLgAFFH8UAAIJAAUJxhciVgAxAQAJAAUJxhciVgAxAQAuAAQKfzIAAwkACQlwI90KAB0DAAkACQlwI90KAB0DACAAAQngGTsSAEgAAAAA.',
Ey='Eyrie:BAAALgADCgYJBgAAAA==.',
Ez='Ezinder:BAABLgAECn8ZAAIcAAcJowSjEwDFAAAcAAcJowSjEwDFAAAAAA==.',
Fa='Fabius:BAAALgADCgYJBgAAAA==.Faemos:BAAALgAECgkJCAAAAA==.Faience:BAABLgAECn8lAAIXAAkJIQQpHADbAAAXAAkJIQQpHADbAAAAAA==.Falorina:BAABLgAECn8xAAMFAAkJsSMVAgBAAwAFAAkJsSMVAgBAAwACAAEJAwXh6wAnAAAAAA==.Fathernature:BAACLgAFFH8IAAIWAAQJAA49IwD5AAAWAAQJAA49IwD5AAAuAAQKfx0AAxYACQknGd4oALgBABYACQknGd4oALgBABoAAQl5Bfw4ACUAAAAA.Fauna:BAAALgADCgMJAwAAAA==.Fazeup:BAAALgAECgcJBgAAAA==.',
Fe='Feldra:BAABLgAECn86AAICAAkJTCHnBwAJAwACAAkJTCHnBwAJAwAAAA==.Felfaith:BAAALgAECgIJAgAAAA==.Fester:BAAALgADCgUJBQABLgAECgkJJgALAJ0WAA==.',
Fi='Fightforbeer:BAAALgAECgEJAQAAAA==.Finnin:BAABLgAECn8jAAMPAAkJCSRTCgC3AgAPAAkJCSRTCgC3AgAhAAEJ0gZ8SAAkAAAAAA==.',
Fo='Food:BAABLgAECn8mAAIGAAkJoRgrIQA/AgAGAAkJoRgrIQA/AgAAAA==.Formidabull:BAAALgAECgEJAQABLgAECgkJIQACAKsdAA==.Foxdiez:BAAALgAECggJEQAAAA==.',
Fr='Fredde:BAAALgADCgEJAQAAAA==.Freidafondle:BAAALgAECgYJEgAAAA==.Frostbite:BAAALgAECgcJCgAAAA==.Frozenfaith:BAABLgAECn8mAAMiAAkJUwurLABlAQAiAAgJ1gurLABlAQAeAAMJMgRxYABNAAAAAA==.',
Ft='Fthemeta:BAAALgADCgIJAgAAAA==.',
Fu='Furioushealz:BAABLgAECn8nAAIHAAkJpxnAOgANAgAHAAkJpxnAOgANAgAAAA==.Furiouswind:BAAALgADCgEJAQAAAA==.',
Ga='Gardrius:BAAALgADCgYJBwAAAA==.',
Gh='Ghettomike:BAABLgAECn8pAAIIAAkJAB41MgAuAgAIAAkJAB41MgAuAgAAAA==.Ghoulbane:BAAALgADCgYJCgAAAA==.',
Gi='Gibbits:BAAALgAECgcJCQAAAA==.Giranimo:BAABLgAECn8hAAIGAAgJ0BIMTwCpAQAGAAgJ0BIMTwCpAQAAAA==.',
Gl='Glabados:BAAALgAECgIJAwABLgAECgkJJwAVADciAA==.Glossy:BAACLgAFFH8eAAMDAAYJlSF+CQDcAQADAAYJlSF+CQDcAQAEAAMJ4hBgCwCWAAAuAAQKfzIABAMACQmEJn0BAFYDAAMACQmEJn0BAFYDABIAAgkNHzAUALsAAAQAAgmEIakUALcAAAAA.Glossycumbus:BAAALgADCgYJBgABLgAFFAYJHgADAJUhAA==.Glossydh:BAAALgAECgYJBgABLgAFFAYJHgADAJUhAA==.Glossydk:BAAALgAECgQJBQABLgAFFAYJHgADAJUhAA==.Glossylock:BAAALgADCgcJDQABLgAFFAYJHgADAJUhAA==.',
Go='Golbigold:BAAALgAECgEJAQAAAA==.Goopy:BAAALgAECgMJAwABLgAECgYJBgAOAAAAAA==.Gorl:BAAALgAECgEJAQAAAA==.',
Gr='Grayhoff:BAABLgAECn8cAAIPAAkJkAtJLQCVAQAPAAkJkAtJLQCVAQAAAA==.Greatclaw:BAAALgADCgMJAwAAAA==.Grewsom:BAACLgAFFH8WAAIHAAQJNyJtGwCDAQAHAAQJNyJtGwCDAQAuAAQKfywAAwcACAniJWMJAEYDAAcACAniJWMJAEYDAAwABQnzIKgVAGwBAAAA.',
Gu='Gulmok:BAAALgADCgUJBQAAAA==.Guwugga:BAABLgAECn8eAAIjAAcJXBBOEAAwAQAjAAcJXBBOEAAwAQAAAA==.',
Ha='Halîk:BAABLgAECn8XAAIBAAkJvhwJLADXAQABAAkJvhwJLADXAQAAAA==.Haraka:BAAALgAECgMJBAAAAA==.Harmshock:BAABLgAECn89AAIRAAkJhCRpAgDvAgARAAkJhCRpAgDvAgAAAA==.Hathina:BAACLgAFFH8UAAMPAAcJSh6YBwDEAQAPAAYJcyKYBwDEAQAhAAEJfAmCOABLAAAuAAQKfzMAAw8ACQnTJgsBAHUDAA8ACQnTJgsBAHUDACEAAwmCHykeAP4AAAAA.',
He='Heket:BAABLgAECn8wAAIHAAgJtwjaqAAeAQAHAAgJtwjaqAAeAQAAAA==.Hektric:BAAALgAECgMJAwAAAA==.Helpinghandz:BAAALgAECgYJBgABLgAFFAUJFgAPAFgZAA==.',
Hi='Highdra:BAAALgAECgYJEwAAAA==.Hill:BAABLgAECn8oAAIGAAkJhR/7FgCAAgAGAAkJhR/7FgCAAgAAAA==.Hive:BAABLgAECn8wAAIPAAkJThjcEwBMAgAPAAkJThjcEwBMAgAAAA==.',
Ho='Holygem:BAAALgAECgYJCgAAAA==.Holypower:BAAALgADCgcJDQAAAA==.Hotdogwater:BAABLgAECn8nAAMkAAgJdyPHCQAMAwAkAAgJdyPHCQAMAwAlAAQJ5gkgdQB7AAAAAA==.',
Hu='Husentar:BAABLgAECn87AAIJAAkJ8CDIEwDdAgAJAAkJ8CDIEwDdAgAAAA==.Huuhablo:BAABLgAECn9AAAICAAkJjRx1FwB/AgACAAkJjRx1FwB/AgAAAA==.',
Ic='Icaron:BAAALgAECgcJDwAAAA==.',
Ig='Igothots:BAAALgAECgUJCgAAAA==.',
Il='Illuminottey:BAABLgAECn8UAAIHAAkJmQ9ujQBLAQAHAAkJmQ9ujQBLAQAAAA==.',
In='Inferium:BAAALgADCgYJBgABLgAFFAQJDwAOAAAAAA==.Infernom:BAAALgADCgMJAwABLgAFFAQJDwAOAAAAAA==.Insatiabull:BAABLgAECn8hAAMCAAkJqx2+EgDqAgACAAgJ7x6+EgDqAgAFAAEJyxTUXQBCAAAAAA==.',
Io='Iolchsk:BAAALgAECgQJDAAAAA==.',
Is='Ishaa:BAAALgAECgYJCAAAAA==.',
Ja='Jacksof:BAABLgAECn8UAAMfAAYJ7gUKWQCjAAAfAAYJ7gUKWQCjAAAiAAQJOQQSZQBUAAAAAA==.Jackstands:BAABLgAECn9RAAMkAAkJmSFDBgBCAwAkAAkJmSFDBgBCAwARAAgJgAXLGgAaAQAAAA==.Jagerin:BAAALgAECgYJCwABLgAECgkJJwAVADciAA==.January:BAAALgAECgYJBgABLgAFFAUJEQAGABoVAA==.Jasmyne:BAAALgADCgYJBgAAAA==.',
Je='Jeromy:BAAALgAECgEJAQAAAA==.Jesse:BAAALgADCgIJAgAAAA==.',
Ji='Jiffi:BAABLgAECn8ZAAImAAgJyRrwBQA8AgAmAAgJyRrwBQA8AgAAAA==.Jinksy:BAAALgAECgYJDgAAAA==.',
Jm='Jme:BAAALgAECgcJCQAAAA==.',
Jr='Jredz:BAAALgADCgEJAQAAAA==.',
Ju='Jubag:BAAALgADCgIJAgAAAA==.Jumpercables:BAAALgAECgEJBAAAAA==.Junn:BAABLgAECn8nAAIlAAkJmBOMJAC1AQAlAAkJmBOMJAC1AQAAAA==.Justiciar:BAAALgAECgEJAQAAAA==.',
['Já']='Jánuary:BAAALgAECgUJBQAAAA==.',
Ka='Kahayman:BAACLgAFFH8NAAIJAAMJqwpRfgDVAAAJAAMJqwpRfgDVAAAuAAQKfzEAAgkACQmDGRMqAGsCAAkACQmDGRMqAGsCAAAA.Kamacha:BAAALgAECgMJBAAAAA==.Karellen:BAABLgAECn8UAAMcAAgJTgzeCgBfAQAcAAgJTgzeCgBfAQAbAAUJlAS5bQCDAAAAAA==.Kathren:BAAALgAECgYJBwAAAA==.',
Kh='Khathani:BAABLgAECn8WAAMGAAYJFRsJVACaAQAGAAYJFRsJVACaAQAKAAQJHQuiHwCmAAAAAA==.',
Ki='Kieran:BAAALgAECgMJAwAAAA==.Kirara:BAAALgAECgMJAwAAAA==.',
Kn='Knobgoblinn:BAAALgAECgQJBAAAAA==.',
Ko='Komojo:BAABLgAECn8rAAIHAAgJURF6bwCEAQAHAAgJURF6bwCEAQAAAA==.Koriggan:BAABLgAECn8yAAQTAAkJZhKQEgAQAgATAAkJZhKQEgAQAgAGAAYJKhB6VQBoAQAKAAEJ6QBlmwAUAAAAAA==.',
Kr='Krea:BAABLgAECn80AAIMAAkJWyJGAgAIAwAMAAkJWyJGAgAIAwAAAA==.Krixx:BAAALgADCgEJAQAAAA==.Krystagosa:BAABLgAECn85AAQnAAkJiRa/CABZAgAnAAkJiRa/CABZAgAbAAYJJg/3SQD4AAAcAAMJVApMGACJAAAAAA==.',
Ku='Kuriuh:BAABLgAECn8mAAILAAkJnRaGOADyAQALAAkJnRaGOADyAQAAAA==.Kurtcobainn:BAAALgADCgkJCQAAAA==.',
La='Lang:BAABLgAECn87AAImAAkJ1x2EAwCVAgAmAAkJ1x2EAwCVAgAAAA==.',
Le='Legionslamm:BAAALgADCgUJBQAAAA==.Leonldas:BAAALgADCgEJAQAAAA==.',
Li='Lightsfaith:BAAALgADCgYJBgABLgAECgkJJgAiAFMLAA==.',
Lo='Lodix:BAAALgAFFAIJBAAAAA==.Loopey:BAAALgAECgcJEAABLgAFFAYJGgAVAKwTAA==.Lorethil:BAAALgAECgYJDAAAAA==.',
Lu='Luceriss:BAABLgAECn8fAAIDAAkJtA4DGgC6AQADAAkJtA4DGgC6AQAAAA==.Luminous:BAAALgADCgcJCAABLgAECgkJJgALAJ0WAA==.',
Ma='Maeroth:BAAALgADCgUJBQABLgAFFAcJFQALAO8MAA==.Magicboi:BAABLgAECn8XAAIJAAcJTQ9blwBFAQAJAAcJTQ9blwBFAQAAAA==.Magwar:BAACLgAFFH8QAAIPAAYJrxZ4DgB/AQAPAAYJrxZ4DgB/AQAuAAQKfzEAAg8ACQlXIS8IANYCAA8ACQlXIS8IANYCAAAA.Maike:BAABLgAECn8rAAMSAAgJNxZOCAC/AQASAAgJQBROCAC/AQADAAQJNBKFNAD0AAAAAA==.Marcelyne:BAAALgAECgYJCAABLgAECgkJJAALAPYTAA==.Marothius:BAACLgAFFH8VAAQLAAcJ7wxOMgBlAQALAAYJLAxOMgBlAQAjAAEJvxAUFABWAAAYAAEJ3AJZKQA3AAAuAAQKfzMABAsACQlhHlIiAFMCAAsACQlQHFIiAFMCACMABgmMHBAXAJEBABgAAgnLGokfALAAAAAA.Martaug:BAABLgAECn8hAAIkAAkJJx9+EQC3AgAkAAkJJx9+EQC3AgAAAA==.Marune:BAAALgAECgkJDwAAAA==.Maurice:BAAALgADCgYJCwAAAA==.Maverage:BAABLgAECn84AAMPAAkJDCKmBgDsAgAPAAkJDCKmBgDsAgAhAAYJ6xOAKAAiAQAAAA==.Mawg:BAAALgAECgYJBwAAAA==.Mayfair:BAABLgAECn8bAAMkAAYJ2Bf1QACcAQAkAAYJ2Bf1QACcAQAlAAYJuQYFYQCxAAAAAA==.',
Mb='Mbarnes:BAAALgAECgQJBwAAAA==.',
Me='Melee:BAACLgAFFH8zAAIHAAkJJSU0AABfAwAHAAkJJSU0AABfAwAuAAQKfxYAAgcACQmZJj0CALoDAAcACQmZJj0CALoDAAAA.',
Mi='Midnightfear:BAAALgADCgcJBwAAAA==.Mikeyy:BAAALgADCgMJAwAAAA==.Mimoza:BAAALgAECgYJCgAAAA==.Minibeer:BAAALgAECgYJEgAAAA==.Minimee:BAAALgAECgYJCgAAAA==.Miquella:BAAALgAECgcJEQAAAA==.Misohotramen:BAACLgAFFH8UAAICAAUJQxtGNAA9AQACAAUJQxtGNAA9AQAuAAQKfyQAAgIACQnQILUzACsCAAIACQnQILUzACsCAAAA.',
Mo='Moist:BAABLgAECn87AAIZAAkJaCPyAQAjAwAZAAkJaCPyAQAjAwAAAA==.Monkstrosity:BAAALgAECgMJAwAAAA==.Moonlock:BAAALgADCgYJCgAAAA==.Moor:BAABLgAECn8aAAIgAAkJrwYFBwA2AQAgAAkJrwYFBwA2AQAAAA==.Mordakka:BAAALgAECgYJCQAAAA==.Morior:BAABLgAECn85AAMLAAkJShswJwA7AgALAAkJShswJwA7AgAjAAIJMBi0UQB5AAAAAA==.Motgustus:BAAALgAFFAEJAQAAAA==.',
Mu='Muirfire:BAAALgADCgYJBgAAAA==.Murrda:BAABLgAECn83AAMLAAkJqSGXCwDsAgALAAkJqSGXCwDsAgAYAAEJ0xM+NQBBAAAAAA==.Musk:BAAALgAECgIJBQABLgAECggJLwAJAOAWAA==.Muskrattsam:BAABLgAECn8vAAIJAAgJ4BZlRQAFAgAJAAgJ4BZlRQAFAgAAAA==.',
My='Myravia:BAABLgAECn8WAAIJAAcJrxAwkQCxAQAJAAcJrxAwkQCxAQAAAA==.Myrokos:BAABLgAECn9RAAIHAAkJ+SLnCAAaAwAHAAkJ+SLnCAAaAwAAAA==.',
['Mó']='Mónónoke:BAAALgADCgMJAwAAAA==.',
['Mö']='Möokss:BAAALgADCgQJAgAAAA==.',
Na='Nailo:BAABLgAECn9RAAIZAAkJYBPGEADMAQAZAAkJYBPGEADMAQAAAA==.Nails:BAAALgAECgQJBgAAAA==.Nathanos:BAAALgAECggJCwAAAA==.',
Ne='Nepetala:BAAALgAECgYJBgABLgAFFAYJDAAbAOEQAA==.Nezar:BAAALgAFFAEJAwABLgAFFAEJBQAmAFcYAA==.',
Nh='Nhat:BAAALgAECgMJAwAAAA==.',
Ni='Niaah:BAAALgADCgYJAQABLgAECgkJFwABAL4cAA==.Niddy:BAABLgAECn8/AAIJAAkJzxeVMwBDAgAJAAkJzxeVMwBDAgAAAA==.Nisardela:BAAALgADCgMJAwAAAA==.',
No='Nobudy:BAACLgAFFH8eAAMfAAcJ6BvJBwDSAQAfAAcJ6BvJBwDSAQAiAAQJzAJWKwDTAAAuAAQKfzEABB8ACQm6JM8DAB0DAB8ACQm6JM8DAB0DAB4ABgnIFcYuAIgBACIAAgnNBOJZAC4AAAAA.Noel:BAABLgAECn8lAAIeAAcJ1RhaHADWAQAeAAcJ1RhaHADWAQAAAA==.Nomsayin:BAACLgAFFH8GAAILAAMJHQuHgQCxAAALAAMJHQuHgQCxAAAuAAQKfzAAAgsACQkuGRYzAEACAAsACQkuGRYzAEACAAAA.Nonospot:BAABLgAECn8sAAMfAAkJmhc2EgA7AgAfAAkJmhc2EgA7AgAiAAEJvANJWgAuAAAAAA==.Noobuddy:BAAALgAECgUJCgABLgAFFAcJHgAfAOgbAA==.Noraboo:BAABLgAECn8jAAMgAAgJQRqjBAD7AQAgAAYJbxyjBAD7AQAJAAgJmRg9XgC+AQABLgAECgkJKwAUABsdAA==.Norannestra:BAAALgAECgYJDQAAAA==.Novalicious:BAAALgADCgIJAgAAAA==.Novasera:BAAALgAECgcJCAAAAA==.',
Nu='Nubmuffin:BAAALgADCgUJBQAAAA==.',
Nv='Nvied:BAABLgAECn8cAAMLAAkJpRTDQQDRAQALAAgJpRTDQQDRAQAjAAEJAAD5cwAxAAAAAA==.',
Ny='Nyctt:BAABLgAECn8YAAMDAAkJ8BlNGQA6AgADAAkJUhhNGQA6AgASAAIJ5xdoFgCSAAAAAA==.Nystra:BAABLgAECn8WAAILAAkJAhh2JABIAgALAAkJAhh2JABIAgAAAA==.Nyzstra:BAABLgAECn8wAAIJAAkJXiK0FwDEAgAJAAkJXiK0FwDEAgAAAA==.',
['Nê']='Nêwt:BAACLgAFFH8PAAIJAAMJaBG0dQDlAAAJAAMJaBG0dQDlAAAuAAQKfz4AAgkACQn/HAopAG8CAAkACQn/HAopAG8CAAAA.',
['Nì']='Nìrvana:BAAALgAECgQJCwAAAA==.',
['Nú']='Núbmuffin:BAAALgAECgEJAgAAAA==.',
On='Onlybeams:BAABLgAECn8fAAICAAkJQBtUHwBOAgACAAkJQBtUHwBOAgAAAA==.',
Or='Orphu:BAAALgAECgEJAQAAAA==.',
Pa='Pallyplexity:BAAALgAECgYJBgABLgAECgkJRwAQAFUmAA==.Palmiste:BAAALgAECgQJBgAAAA==.Pangoplexity:BAAALgADCgIJAgAAAA==.Parahsalin:BAAALgAECgEJAQABLgAECgYJEgAOAAAAAA==.Partyhard:BAAALgADCgkJGwAAAA==.Pastryblust:BAABLgAFFH8IAAIlAAUJARY8HAAmAQAlAAUJARY8HAAmAQAAAA==.Pastrydragon:BAACLgAFFH8LAAMbAAQJORa6LAACAQAbAAQJORa6LAACAQAcAAEJJxl2CwBQAAAuAAQKfy4AAxsACAmrINUKAMgCABsACAmSHtUKAMgCABwABglYI5ULACICAAEuAAUUBQkIACUAARYA.',
Ph='Phaeliea:BAAALgAECgUJBQAAAA==.',
Pi='Pistachio:BAABLgAECn8bAAIFAAYJOA5jMQDrAAAFAAYJOA5jMQDrAAAAAA==.Pitviper:BAABLgAECn8mAAISAAkJ4x6QAwBrAgASAAkJ4x6QAwBrAgAAAA==.',
Po='Pocketrokit:BAAALgAECgkJDAAAAA==.Pogaca:BAAALgAECgcJDgABLgAECggJFwAWAP8bAA==.Portabull:BAAALgADCgcJBwABLgAECgkJIQACAKsdAA==.Possess:BAABLgAECn8mAAILAAcJVx3KRADHAQALAAcJVx3KRADHAQAAAA==.Pownora:BAABLgAECn8rAAMUAAkJGx2mCgCOAgAUAAkJGx2mCgCOAgAoAAIJ/Q3iqQAxAAAAAA==.',
Ps='Psarchasm:BAABLgAECn8wAAIPAAkJlg2OKgClAQAPAAkJlg2OKgClAQAAAA==.',
Pu='Puck:BAAALgAECgEJAgAAAA==.Puffnstuff:BAAALgAECgMJAwAAAA==.Pugstar:BAAALgAECgMJAwAAAA==.',
Qe='Qel:BAAALgADCgYJCQAAAA==.',
Ra='Rai:BAABLgAECn87AAIGAAkJzSRFBQA1AwAGAAkJzSRFBQA1AwAAAA==.Rancidbeef:BAAALgAECgMJAwAAAA==.Rapha:BAABLgAECn8nAAIVAAkJNyIBBQDsAgAVAAkJNyIBBQDsAgAAAA==.Rayyzer:BAABLgAECn8dAAMDAAkJqCHBCwBcAgADAAkJqCHBCwBcAgASAAEJohbyIQBIAAAAAA==.',
Re='Realrogue:BAAALgAECgYJCwABLgAECgkJRwAQAFUmAA==.Rema:BAAALgADCgQJBAAAAA==.Reyna:BAAALgADCgUJBQAAAA==.',
Ri='Riddles:BAABLgAECn8eAAMZAAgJzB3iCABOAgAZAAgJzB3iCABOAgANAAEJFiOEtQBaAAAAAA==.Rincewind:BAAALgAECgEJAQAAAA==.',
Ro='Rossabella:BAABLgAECn9FAAMeAAkJahuKCgCxAgAeAAkJahuKCgCxAgAiAAgJ0w7HGwC4AQAAAA==.Rot:BAABLgAECn8nAAIdAAkJCSakAgAeAwAdAAkJCSakAgAeAwAAAA==.',
Ru='Rude:BAAALgAECgYJBgABLgAFFAcJFAAPAEoeAA==.Ruzala:BAAALgADCgEJAQAAAA==.',
Sa='Samsonn:BAAALgADCgQJBAAAAA==.Sanctity:BAAALgADCgYJCgAAAA==.Santino:BAACLgAFFH8HAAINAAMJNQgURgCYAAANAAMJNQgURgCYAAAuAAQKfx4AAg0ACAlhGTsdAFICAA0ACAlhGTsdAFICAAEuAAUUAwkNAAkAqwoA.Saphlocket:BAAALgAECgYJEgAAAA==.Sathin:BAABLgAECn8yAAICAAkJmwroXABlAQACAAkJmwroXABlAQAAAA==.',
Sc='Scher:BAAALgADCgkJCwAAAA==.Scufalufagus:BAAALgAECgUJBQABLgAFFAcJFQALAO8MAA==.',
Se='Seetick:BAAALgAECgIJBAAAAA==.Sefekat:BAAALgAECgEJAQABLgAECgkJHwACAEAbAA==.September:BAAALgAECgIJAgABLgAFFAUJEQAGABoVAA==.Sevatar:BAABLgAECn8nAAIFAAkJUg1jHQB/AQAFAAkJUg1jHQB/AQAAAA==.',
Sf='Sfcwarner:BAAALgAECgEJAQAAAA==.',
Sg='Sgtwarner:BAAALgAECgEJAgAAAA==.',
Sh='Shampooyou:BAABLgAECn8tAAIkAAgJwQiDWwA6AQAkAAgJwQiDWwA6AQAAAA==.Shockakhan:BAAALgAECggJDgAAAA==.Shocknstone:BAAALgADCgcJBwABLgAECgkJRwAQAFUmAA==.',
Si='Silentmamba:BAAALgAECgEJAQAAAA==.Sinistra:BAAALgAECgcJEQAAAA==.',
Sk='Skelecopter:BAAALgADCgMJAwAAAA==.',
Sl='Slapshot:BAAALgAECggJCwABLgAECggJFwAWAP8bAA==.',
Sn='Snowflake:BAAALgADCgcJBwAAAA==.',
Sp='Spellsteal:BAABLgAECn8lAAIJAAkJuxh6NQA8AgAJAAkJuxh6NQA8AgABLgAFFAQJDwAQAEANAA==.Spicynudz:BAAALgAECgEJAQAAAA==.Spring:BAACLgAFFH8RAAMGAAUJGhXpOQAuAQAGAAUJGhXpOQAuAQAKAAEJpAAJLgA2AAAuAAQKfyUAAwYACQlfHaMrACQCAAYACQkjHaMrACQCAAoABgnTC/ZMAB0BAAAA.',
Ss='Ssgwarner:BAAALgAECgEJAQAAAA==.',
St='Stardel:BAAALgAECgYJDQABLgAFFAcJHQADABkkAA==.Sting:BAABLgAECn8ZAAIGAAcJ8wxFcABUAQAGAAcJ8wxFcABUAQAAAA==.Stormclaw:BAABLgAECn8zAAMNAAkJSx25EADDAgANAAkJSx25EADDAgAWAAEJkBzvcgBUAAAAAA==.Stormcrash:BAAALgADCgYJBgABLgAECgkJJgALAJ0WAA==.Stregoica:BAAALgADCgcJDgABLgAFFAcJFQALAO8MAA==.',
Su='Suhfering:BAAALgADCgYJBgABLgAECgkJHwACAEAbAA==.Superbeef:BAAALgAECgEJAQAAAA==.Sushiiez:BAAALgADCgMJAwAAAA==.Suwo:BAAALgADCgIJAQAAAA==.',
Sy='Sychopath:BAAALgAECgMJBAAAAA==.Sykadelik:BAAALgAECgMJAwAAAA==.Syngoma:BAAALgADCgIJAgAAAA==.',
Ta='Tallron:BAACLgAFFH8cAAINAAcJ6Bj9CQA7AgANAAcJ6Bj9CQA7AgAuAAQKfy4AAw0ACQmaJLcJAPcCAA0ACQmaJLcJAPcCABYABQmPFa8+AAUBAAAA.Tallsera:BAAALgADCgcJDQABLgAFFAcJHAANAOgYAA==.Tallyfan:BAAALgADCgcJEwAAAA==.Tamedsloth:BAAALgAECgYJBgAAAA==.Tandraella:BAAALgAECgQJBQABLgAFFAQJBgABAFUTAA==.Tanthalos:BAAALgADCgIJAgAAAA==.Taroquin:BAAALgADCgkJCgAAAA==.',
Te='Ternay:BAAALgADCgIJAQAAAA==.Teskhamen:BAAALgAECgcJEQAAAA==.Tetamesh:BAAALgADCgQJBAAAAA==.',
Th='Theskabandit:BAAALgADCgcJEQAAAA==.Thrustruggle:BAAALgAECgMJAwAAAA==.',
Ti='Tiamot:BAAALgADCgUJCAAAAA==.',
To='Tojikitoushi:BAABLgAECn84AAIRAAkJ6SD9AgDWAgARAAkJ6SD9AgDWAgAAAA==.Tombs:BAAALgAECgYJCQAAAA==.Tonsonger:BAAALgAECgUJCAAAAA==.Totenhammer:BAAALgAECgQJCwAAAA==.Totenplage:BAAALgAECgQJBAAAAA==.',
Tr='Trid:BAAALgAECggJCAAAAA==.Tristex:BAAALgAECgUJBQABLgAECggJFwAWAP8bAA==.',
Tu='Tuha:BAAALgAFFAIJAgAAAA==.',
Tw='Twergstronk:BAAALgADCgEJAQAAAA==.',
Ty='Tyrolia:BAAALgAECgMJAwAAAA==.',
Um='Umibozu:BAAALgAECgIJAgAAAA==.',
Ur='Urchak:BAAALgAECgYJBgAAAA==.',
Va='Valliya:BAABLgAFFH8FAAIHAAMJTQNXeACoAAAHAAMJTQNXeACoAAAAAA==.',
Ve='Velratha:BAABLgAECn8UAAIYAAgJtQ80DAB2AQAYAAgJtQ80DAB2AQAAAA==.Vesfu:BAAALgADCgEJAQAAAA==.Vesi:BAAALgADCgcJCgAAAA==.Vextt:BAABLgAECn8eAAMfAAgJDRgwKACFAQAfAAcJRxswKACFAQAeAAIJeBhMZgA8AAAAAA==.',
Vi='Vicsta:BAAALgAECgYJBwAAAA==.',
Vo='Voidrend:BAAALgAECgQJBwAAAA==.Voidwarner:BAAALgAECgMJAwAAAA==.Volight:BAAALgADCgYJCQAAAA==.Volke:BAABLgAECn8nAAIoAAkJMxZ2HAAgAgAoAAkJMxZ2HAAgAgAAAA==.Volq:BAAALgAECgEJAQAAAA==.Voltarix:BAAALgAECgYJCQAAAA==.Voodoopriest:BAABLgAECn8YAAILAAcJMwRDpAAQAQALAAcJMwRDpAAQAQAAAA==.Voyria:BAABLgAECn8xAAQNAAkJVwhqbADlAAANAAgJ9QRqbADlAAAWAAYJiQU0UgC2AAAaAAIJwQJuTQAvAAAAAA==.',
Vs='Vs:BAAALgAECgYJBgAAAA==.',
Vy='Vynlenn:BAAALgADCgMJAwAAAA==.Vyskaar:BAAALgADCgEJAQAAAA==.Vyskar:BAAALgAECgUJBQAAAA==.Vyskary:BAAALgAECgEJAgAAAA==.',
Wa='Warm:BAACLgAFFH8XAAIUAAcJIxpVAwD3AQAUAAcJIxpVAwD3AQAuAAQKfycAAhQACQkTImsIAPMCABQACQkTImsIAPMCAAAA.Warmlight:BAAALgAECgYJDAAAAA==.',
We='Weewu:BAAALgAECgQJBAABLgAECgYJBgAOAAAAAA==.Weeziveli:BAAALgAECgQJDQAAAA==.Weledish:BAACLgAFFH8XAAIJAAQJBRznPQBlAQAJAAQJBRznPQBlAQAuAAQKfyoAAgkACQnsGis7ACYCAAkACQnsGis7ACYCAAAA.Weleron:BAAALgAECgQJBAAAAA==.',
Wh='Whystler:BAAALgAECgIJAgAAAA==.',
Wi='Wienercat:BAABLgAECn8hAAINAAcJ6SQXDgDfAgANAAcJ6SQXDgDfAgABLgAECggJJwAkAHcjAA==.Wimol:BAAALgAECgYJBgABLgAECgkJKwAUABsdAA==.Windmacedu:BAAALgAECgYJCgAAAA==.',
Xt='Xtreeme:BAAALgAECgIJAgAAAA==.',
Ya='Yael:BAABLgAECn80AAICAAkJeB5VGQBzAgACAAkJeB5VGQBzAgAAAA==.Yama:BAAALgAECgcJEAAAAA==.',
Za='Zamrazac:BAAALgAECgUJCAABLgAECgkJMwANAEsdAA==.Zarewien:BAABLgAECn8uAAIeAAkJ6AoqKgBpAQAeAAkJ6AoqKgBpAQAAAA==.',
Ze='Zeddicus:BAAALgAECgMJAwAAAA==.',
Zi='Ziddles:BAABLgAECn8UAAITAAcJvBs2DwDSAQATAAcJvBs2DwDSAQAAAA==.',
Zo='Zomgdk:BAAALgAECgEJAgABLgAECgkJQAAVAKkeAA==.Zomgmonk:BAABLgAECn9AAAIVAAkJqR6pBgDHAgAVAAkJqR6pBgDHAgAAAA==.Zomgzilla:BAAALgAECggJAQABLgAECgkJQAAVAKkeAA==.Zorep:BAAALgAECgEJAQAAAA==.Zorien:BAAALgAECgQJBAAAAA==.',
Zu='Zuraq:BAAALgAECgEJBgAAAA==.Zurisdad:BAABLgAECn83AAIVAAkJ8B5JBwC5AgAVAAkJ8B5JBwC5AgABLgAFFAUJFAAJAMYXAA==.Zurishmi:BAACLgAFFH8cAAIkAAUJ/h5lBQB3AQAkAAUJ/h5lBQB3AQAuAAQKfzMAAiQACQk6JlEBALoDACQACQk6JlEBALoDAAAA.',
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
