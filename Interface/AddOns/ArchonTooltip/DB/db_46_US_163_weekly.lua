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

local lookup = {'Paladin-Holy','Rogue-Subtlety','Rogue-Outlaw','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-BeastMastery','Paladin-Protection','Paladin-Retribution','DeathKnight-Unholy','Mage-Frost','Hunter-Marksmanship','Warlock-Demonology','Shaman-Restoration','Monk-Brewmaster','Warrior-Protection','Unknown-Unknown','Warrior-Fury','Warrior-Arms','Shaman-Enhancement','Rogue-Assassination','Hunter-Survival','Monk-Windwalker','Druid-Balance','Druid-Restoration','DeathKnight-Frost','Warlock-Affliction','Druid-Guardian','Druid-Feral','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Blood','Priest-Holy','Priest-Shadow','Mage-Arcane','Priest-Discipline','Warlock-Destruction','Shaman-Elemental','DemonHunter-Vengeance','Evoker-Preservation','Monk-Mistweaver',}
local provider = {region='US',realm='Nathrezim',name='US',type='weekly',zone=46,date='2026-08-18',data={Ab='Abysm:BAAALgADCgkJDwAAAA==.',
Ac='Achillios:BAAALgADCgMJAwABLgAFFAQJBwABAI8ZAA==.',
Ad='Adorabull:BAAALgAFFAEJAQAAAA==.',
Ae='Aemun:BAACLgAFFH8LAAICAAMJcxOpJwDrAAACAAMJcxOpJwDrAAAuAAQKf1UAAwIACQl4HhAIAKYCAAIACQl4HhAIAKYCAAMABgmUCbAIAPYAAAAA.',
Ag='Aggfu:BAAALgADCgYJBgAAAA==.',
Ai='Ainek:BAAALgADCgEJAQAAAA==.',
Ak='Akeeli:BAAALgADCgQJBAAAAA==.Akelita:BAABLgAECn8hAAMEAAYJrxiMJQBNAQAEAAYJrxiMJQBNAQAFAAUJcAgWzQCXAAAAAA==.',
Al='Alailea:BAABLgAECn9OAAIGAAkJPRccEwBPAQAGAAkJPRccEwBPAQAAAA==.Aloepaw:BAAALgAECggJDAAAAA==.Alragnar:BAAALgAECgIJAgAAAA==.Alwysafkable:BAABLgAFFH8HAAIHAAMJzBj1CQB7AAAHAAMJzBj1CQB7AAAAAA==.',
Am='Amageadin:BAAALgADCgkJCQAAAA==.Amazadin:BAACLgAFFH8HAAIBAAQJjxkLJwDqAAABAAQJjxkLJwDqAAAuAAQKfxkAAwEACAkpHO8bADUCAAEACAkpHO8bADUCAAgAAgncEvw0AXkAAAAA.Amazashock:BAAALgAECgUJDQABLgAFFAQJBwABAI8ZAA==.',
An='Andiwin:BAABLgAECn8ZAAIJAAgJ9Q90agCRAQAJAAgJ9Q90agCRAQAAAA==.Andurthil:BAABLgAECn8oAAIKAAgJUw1GjwBZAQAKAAgJUw1GjwBZAQAAAA==.Anzul:BAAALgAECgUJBgAAAA==.',
Ar='Archive:BAAALgAECgkJCwAAAA==.Artistic:BAABLgAECn8cAAIGAAgJeBlyQQDeAQAGAAgJeBlyQQDeAQAAAA==.Arubion:BAABLgAECn8ZAAIIAAgJSxGjYQCtAQAIAAgJSxGjYQCtAQAAAA==.Arylanna:BAAALgAECgYJDQAAAA==.',
As='Asure:BAABLgAECn8tAAMGAAkJ/heRKgAzAgAGAAkJ/heRKgAzAgALAAYJTgfdTwAPAQAAAA==.',
Au='Augusteen:BAAALgAECgUJBgAAAA==.',
Az='Azerith:BAAALgAECgYJDwAAAA==.',
Ba='Badmorda:BAAALgADCgEJAQAAAA==.',
Be='Bearforceone:BAAALgADCgMJAwAAAA==.Berret:BAAALgADCgkJEQAAAA==.',
Bi='Bipolar:BAAALgADCgEJAQAAAA==.',
Bl='Blackheart:BAABLgAECn8bAAIMAAgJnBjCLQBWAgAMAAgJnBjCLQBWAgAAAA==.Blodreina:BAAALgADCgUJCQAAAA==.Bloodarchon:BAABLgAECn8rAAMIAAkJYBYBNwAlAgAIAAkJYBYBNwAlAgAHAAYJnQkUMQCiAAAAAA==.Bloodtemplar:BAABLgAECn81AAIIAAkJ2Bq6JAByAgAIAAkJ2Bq6JAByAgAAAA==.',
Bo='Bombs:BAABLgAECn8UAAIKAAQJhRHA0gDuAAAKAAQJhRHA0gDuAAABLgAFFAkJJAANAFoYAA==.Bonesy:BAAALgAECgYJBgAAAA==.Bottomstop:BAAALgADCgEJAQAAAA==.Bouren:BAAALgAECgEJAQAAAA==.',
Br='Brassmönke:BAABLgAECn8XAAIOAAkJxSUxAABtAwAOAAkJxSUxAABtAwABLgAECgkJZAAPAIkmAA==.Bravia:BAAALgADCgUJBwAAAA==.Brewdogg:BAAALgADCgcJBwAAAA==.Brokasa:BAAALgADCgIJAgAAAA==.Brutalitops:BAAALgADCgMJAwAAAA==.Brutusdabull:BAAALgAECgYJBgAAAA==.Brônze:BAAALgADCgQJBAAAAA==.',
Bu='Burdomew:BAAALgADCgEJAQAAAA==.',
Ca='Cadbury:BAAALgADCgIJAgABLgAECgUJCAAQAAAAAA==.Canan:BAAALgAECgUJBgAAAA==.Canansbrew:BAAALgAECgEJAQAAAA==.Canestoast:BAAALgAECgEJAQAAAA==.Casmina:BAABLgAECn8WAAIRAAkJ7xlRIQBJAgARAAkJ7xlRIQBJAgAAAA==.Castiell:BAAALgADCgUJBgAAAA==.Catalystic:BAAALgADCgEJAQAAAA==.Catd:BAAALgAECgIJBAAAAA==.',
Ce='Celum:BAABLgAECn8eAAIJAAcJnwcOvQACAQAJAAcJnwcOvQACAQAAAA==.Ceola:BAABLgAECn8/AAMPAAcJKxGhBwDoAAASAAYJGg6DNAD0AAAPAAcJqQ6hBwDoAAAAAA==.',
Ch='Chamming:BAAALgADCgIJAgAAAA==.Chaquén:BAACLgAFFH8JAAITAAMJ4RZoDgDZAAATAAMJ4RZoDgDZAAAuAAQKfyIAAhMACQn6GdUHAEwCABMACQn6GdUHAEwCAAAA.Charizard:BAAALgAECgEJAQAAAA==.Charmander:BAABLgAECn8fAAQUAAYJshfzCgCAAQAUAAYJshfzCgCAAQACAAQJUgl9SACWAAADAAMJ2wRAGwB0AAAAAA==.Chaw:BAACLgAFFH8kAAMVAAkJEh/HAQBDAgAVAAgJ2RnHAQBDAgAGAAYJBiH+EwCFAQAuAAQKfzIABBUACQnuJPcDAPICABUACQnsJPcDAPICAAsABwnWHy0iABQCAAYABAk3I1BIAJEBAAAA.Chenkenichi:BAACLgAFFH8JAAIWAAMJhgYVLQCWAAAWAAMJhgYVLQCWAAAuAAQKfzIAAxYACQmsD8wGAC4BABYACQmsD8wGAC4BAA4ABQkoAqtoAJ8AAAAA.Chergar:BAACLgAFFH8RAAIPAAYJMhcBDAD0AAAPAAYJMhcBDAD0AAAuAAQKfx4AAg8ACQkVIkwFAOkCAA8ACQkVIkwFAOkCAAAA.Chibari:BAAALgAECgYJBgAAAA==.Chskie:BAAALgADCgUJBQAAAA==.Chsky:BAAALgADCgUJBQAAAA==.Chuiyi:BAAALgAECgEJAgAAAA==.',
Ci='Cinny:BAABLgAECn9GAAIGAAkJchyPGwCAAgAGAAkJchyPGwCAAgAAAA==.Cinnyrolls:BAABLgAECn8XAAMXAAgJ/xvyGwDqAQAXAAgJ/xvyGwDqAQAYAAQJtBBhhwDHAAAAAA==.Cityairlines:BAABLgAECn8nAAIZAAkJuRSUDACuAQAZAAkJuRSUDACuAQAAAA==.',
Cl='Clare:BAAALgAECgYJCQAAAA==.',
Cm='Cmoneyy:BAAALgAECgYJCAAAAA==.',
Co='Cogrolls:BAAALgAECggJCQABLgAFFAIJAgAQAAAAAA==.Cooldukenuke:BAACLgAFFH8KAAIBAAMJqRf4DwDaAAABAAMJqRf4DwDaAAAuAAQKfycAAgEACQmjHDoTAHkCAAEACQmjHDoTAHkCAAAA.',
Cr='Creepychalk:BAABLgAECn8mAAMaAAgJ3w/9AgBvAQAaAAgJ3w/9AgBvAQAMAAEJsAHZZAEcAAAAAA==.Criticize:BAABLgAECn8nAAIIAAgJ1gw/oAA3AQAIAAgJ1gw/oAA3AQAAAA==.',
Cs='Csor:BAAALgAECgMJAwAAAA==.Csorb:BAABLgAECn82AAMbAAkJ8SDtBADEAgAbAAkJviDtBADEAgAcAAEJySV5OwBrAAAAAA==.Csoren:BAAALgAECgEJAQAAAA==.Csoro:BAAALgADCggJCAAAAA==.',
Cu='Cultivation:BAAALgAECgUJCAAAAA==.Cursedcanfly:BAACLgAFFH8hAAIdAAkJDB3jBgA0AgAdAAkJDB3jBgA0AgAuAAQKfzMAAx0ACQnjJWYCAFYDAB0ACQnjJWYCAFYDAB4ABQnaFG8iABcBAAAA.',
Cw='Cw:BAAALgAECgEJAQAAAA==.',
De='Deagua:BAAALgAECgQJBAABLgAFFAkJHwAMAFEPAA==.Deathdogg:BAACLgAFFH8VAAMJAAUJxxm5ZwApAQAJAAQJxxm5ZwApAQAfAAEJAACyVwAAAAAuAAQKfykAAgkACQlPIL41ACgCAAkACQlPIL41ACgCAAAA.Dejavu:BAACLgAFFH8gAAIOAAgJQBO2BwB7AQAOAAgJQBO2BwB7AQAuAAQKfyoAAg4ACQm1HjMbAMsBAA4ACQm1HjMbAMsBAAAA.Demivoi:BAAALgAECgYJBwAAAA==.Demona:BAAALgAECgEJAQAAAA==.Deppthcharge:BAAALgAECgYJEgAAAA==.Desdemona:BAAALgAECgcJDAAAAA==.Devimon:BAAALgADCgEJAQAAAA==.Devoi:BAAALgADCgEJAQAAAA==.',
Di='Dismonk:BAAALgAECgIJAgAAAA==.Distotem:BAAALgAECgEJAQABLgAECgIJAgAQAAAAAA==.',
Do='Donrain:BAAALgAECgQJBAAAAA==.Dooghammer:BAABLgAECn8ZAAITAAkJQxrzCQAcAgATAAkJQxrzCQAcAgAAAA==.',
Dr='Dragussy:BAAALgADCgcJDQABLgAECgkJZAAPAIkmAA==.Drakkana:BAAALgADCgYJBgAAAA==.Drithmil:BAAALgAECgMJAwAAAA==.',
Du='Dunkhan:BAAALgAECgEJAQABLgAECgYJDAAQAAAAAA==.Duplexity:BAABLgAECn9kAAMPAAkJiSZTAACDAwAPAAkJiSZTAACDAwARAAEJuCFmhwBkAAAAAA==.',
Dw='Dwalin:BAAALgAECgMJCQABLgAECgkJGQATAEMaAA==.',
Ea='Eatmoorchikn:BAAALgAECgcJDAAAAA==.',
Ec='Ecko:BAAALgAECgEJAQAAAA==.',
Ed='Edolah:BAAALgAECgEJAQAAAA==.',
Eg='Egohakai:BAACLgAFFH8RAAIIAAUJrx1gQAAqAQAIAAUJrx1gQAAqAQAuAAQKfzAAAggACQkUJbkIACQDAAgACQkUJbkIACQDAAAA.',
El='Eloi:BAABLgAECn8WAAMgAAgJbyCrCQDNAgAgAAgJbyCrCQDNAgAhAAEJUhNbgQA6AAABLgAECgkJMwAYAEsdAA==.',
Em='Emieretta:BAABLgAECn88AAIJAAkJXRgMNgAmAgAJAAkJXRgMNgAmAgAAAA==.',
Eq='Eqdk:BAABLgAECn8hAAIJAAkJoxTdRwDqAQAJAAkJoxTdRwDqAQAAAA==.',
Er='Erret:BAACLgAFFH8UAAIKAAUJxhd5XwAiAQAKAAUJxhd5XwAiAQAuAAQKfzMAAwoACQlwI1EMABYDAAoACQlwI1EMABYDACIAAQngGVQUAEkAAAAA.',
Et='Ethaka:BAAALgAFFAIJAgAAAA==.',
Ey='Eyrie:BAAALgADCgYJBgAAAA==.',
Ez='Ezinder:BAABLgAECn8lAAIeAAcJfgpUAwDbAAAeAAcJfgpUAwDbAAAAAA==.',
Fa='Fabius:BAAALgADCgYJBgAAAA==.Faemos:BAAALgAECgkJCAAAAA==.Faience:BAABLgAECn8nAAIZAAkJMARXHgDaAAAZAAkJMARXHgDaAAAAAA==.Falorina:BAABLgAECn83AAMEAAkJbSRWAgBCAwAEAAkJbSRWAgBCAwAFAAEJAwXh6wAnAAAAAA==.Fathernature:BAACLgAFFH8JAAIXAAQJphB8JAAEAQAXAAQJphB8JAAEAQAuAAQKfx8AAxcACQkhHN4oALgBABcACQkhHN4oALgBABwAAQl5Bfw4ACUAAAAA.Fauna:BAAALgADCgMJAwAAAA==.Fazeup:BAAALgAECgcJBgAAAA==.',
Fe='Feldra:BAABLgAECn9cAAIFAAkJcSTBAABHAwAFAAkJcSTBAABHAwAAAA==.Felfaith:BAAALgAECgIJAgAAAA==.Fester:BAAALgADCgUJBQABLgAECgkJJgAMAJ0WAA==.',
Fi='Fightforbeer:BAAALgAECgEJAQAAAA==.Finnin:BAABLgAECn8jAAMRAAkJCSR3CwCwAgARAAkJCSR3CwCwAgASAAEJ0gZ8SAAkAAAAAA==.',
Fl='Floptina:BAAALgAECgUJBQABLgAECgkJKwAWABsdAA==.',
Fo='Food:BAABLgAECn8mAAIGAAkJoRgrIQA/AgAGAAkJoRgrIQA/AgAAAA==.Formidabull:BAAALgAECgEJAQABLgAFFAEJAQAQAAAAAA==.Foxdiez:BAAALgAECggJEQAAAA==.',
Fr='Fredde:BAAALgAECgEJAgAAAA==.Freidafondle:BAAALgAECgYJEgAAAA==.Frostbite:BAAALgAECgcJCwAAAA==.Frozenfaith:BAABLgAECn8mAAMjAAkJUwuxMABaAQAjAAgJ1guxMABaAQAgAAMJMgQEZQBNAAAAAA==.',
Ft='Fthemeta:BAAALgADCgIJAgAAAA==.',
Fu='Fulci:BAAALgADCgUJBQAAAA==.Furioushealz:BAABLgAECn8nAAIIAAkJpxn/PgAKAgAIAAkJpxn/PgAKAgAAAA==.Furiouswind:BAAALgADCgEJAQAAAA==.',
Ga='Gardrius:BAAALgADCgYJBwAAAA==.',
Ge='Gerrad:BAAALgAECgUJBQAAAA==.',
Gh='Ghettomike:BAABLgAECn8pAAIJAAkJAB53NQApAgAJAAkJAB53NQApAgAAAA==.Ghoulbane:BAAALgADCgYJCgAAAA==.',
Gi='Gibbits:BAAALgAECgcJCQAAAA==.Giranimo:BAABLgAECn8vAAIGAAkJoRQ0MAAbAgAGAAkJoRQ0MAAbAgAAAA==.',
Gl='Glabados:BAAALgAECgIJAwABLgAECgkJJwAOADciAA==.Glossy:BAACLgAFFH8pAAMCAAkJ6SG1AgCmAgACAAkJ6SG1AgCmAgADAAMJ4hDBDACUAAAuAAQKfzIABAIACQmEJrkBAFMDAAIACQmEJrkBAFMDABQAAgkNHzAUALsAAAMAAgmEIaYVALgAAAAA.Glossycumbus:BAAALgADCgYJBgABLgAFFAkJKQACAOkhAA==.Glossydh:BAAALgAECgYJBgABLgAFFAkJKQACAOkhAA==.Glossydk:BAAALgAFFAEJAgABLgAFFAkJKQACAOkhAA==.Glossylock:BAAALgADCgcJDQABLgAFFAkJKQACAOkhAA==.',
Go='Golbigold:BAAALgAECgEJAQAAAA==.Goopy:BAAALgAECgMJAwABLgAECgYJBgAQAAAAAA==.Gorl:BAAALgAECgEJAQAAAA==.',
Gr='Grayhoff:BAABLgAECn8cAAIRAAkJkAsYMQCIAQARAAkJkAsYMQCIAQAAAA==.Greathoof:BAAALgADCgMJAwAAAA==.Grewsom:BAACLgAFFH8XAAIIAAUJvhyhFQC+AQAIAAUJvhyhFQC+AQAuAAQKfy4AAwgACQlIJWMJAEYDAAgACQlIJWMJAEYDAAcABQnzIOAWAGoBAAAA.',
Gu='Gulmok:BAAALgADCgUJBQAAAA==.Guwugga:BAABLgAECn8eAAIkAAcJXBDFEQAsAQAkAAcJXBDFEQAsAQAAAA==.',
Ha='Halîk:BAABLgAECn8XAAIBAAkJvhwJLADXAQABAAkJvhwJLADXAQAAAA==.Haraka:BAAALgAECgMJBAAAAA==.Hardheaded:BAAALgAECgQJBQAAAA==.Harmshock:BAABLgAECn89AAITAAkJhCTBAgDpAgATAAkJhCTBAgDpAgAAAA==.Hathina:BAACLgAFFH8UAAMRAAcJSh4SCgC/AQARAAYJcyISCgC/AQASAAEJfAmFQABIAAAuAAQKfzMAAxEACQnTJlYBAG8DABEACQnTJlYBAG8DABIAAwmCHykeAP4AAAAA.',
He='Heket:BAABLgAECn86AAMIAAgJtwgqswAaAQAIAAgJtwgqswAaAQABAAUJ0wcjEACsAAAAAA==.Hektric:BAAALgAECgMJAwAAAA==.Helpinghandz:BAAALgAECgYJBgABLgAFFAYJGgARAKEZAA==.',
Hi='Highdra:BAAALgAECgYJEwAAAA==.Hill:BAABLgAECn8oAAIGAAkJhR/7FgCAAgAGAAkJhR/7FgCAAgAAAA==.Hive:BAABLgAECn8wAAIRAAkJThjBFQBBAgARAAkJThjBFQBBAgAAAA==.',
Ho='Holygem:BAAALgAECgYJCgAAAA==.Holypower:BAAALgADCgcJDQAAAA==.Hotdogwater:BAABLgAECn8nAAMNAAgJdyPmCgAJAwANAAgJdyPmCgAJAwAlAAQJ5gmkfAB6AAAAAA==.',
Hu='Hunttres:BAAALgAECgUJBQAAAA==.Husentar:BAABLgAECn87AAIKAAkJ8CCOFQDYAgAKAAkJ8CCOFQDYAgAAAA==.Huuhablo:BAABLgAECn9AAAIFAAkJjRzsGAB/AgAFAAkJjRzsGAB/AgAAAA==.',
Ic='Icaron:BAAALgAECgcJDwAAAA==.',
Ig='Igothots:BAAALgAECgUJCgAAAA==.',
Il='Illuminottey:BAABLgAECn8UAAIIAAkJmQ+RlQBJAQAIAAkJmQ+RlQBJAQAAAA==.',
In='Inferium:BAAALgADCgYJBgABLgAFFAQJDwAQAAAAAA==.Infernom:BAAALgADCgMJAwABLgAFFAQJDwAQAAAAAA==.Insatiabull:BAABLgAECn8hAAMFAAkJqx2+EgDqAgAFAAgJ7x6+EgDqAgAEAAEJyxSgZQBCAAABLgAFFAEJAQAQAAAAAA==.',
Io='Iolchsk:BAAALgAECgQJDAAAAA==.',
Is='Ishaa:BAAALgAECgYJDAAAAA==.',
Ja='Jacksof:BAABLgAECn8UAAMhAAYJ7gUDXwCcAAAhAAYJ7gUDXwCcAAAjAAQJOQTdbABSAAAAAA==.Jackstands:BAABLgAECn9WAAMNAAkJmSH+BgBAAwANAAkJmSH+BgBAAwATAAgJgAUoHQAUAQAAAA==.Jagerin:BAAALgAECgYJCwABLgAECgkJJwAOADciAA==.January:BAAALgAFFAMJBAABLgAFFAcJEwAGABgQAA==.',
Je='Jeromy:BAAALgAECgEJAQAAAA==.Jesse:BAAALgADCgIJAgAAAA==.',
Ji='Jiffi:BAABLgAECn8ZAAImAAgJyRrwBQA8AgAmAAgJyRrwBQA8AgAAAA==.Jinksy:BAAALgAECgcJEQAAAA==.',
Jm='Jme:BAAALgAECgcJCQAAAA==.',
Jr='Jredz:BAAALgADCgEJAQAAAA==.',
Ju='Juanwick:BAAALgADCgQJBAAAAA==.Jubag:BAAALgADCgIJAgAAAA==.Julianus:BAAALgAECgIJAgAAAA==.Jumpercables:BAAALgAECgEJBAAAAA==.Junn:BAABLgAECn8nAAIlAAkJmBPVJgC1AQAlAAkJmBPVJgC1AQAAAA==.Justiciar:BAAALgAECgEJAQAAAA==.',
['Já']='Jánuary:BAAALgAECgUJCAAAAA==.',
Ka='Kahayman:BAACLgAFFH8iAAIKAAQJJRX/KQAqAQAKAAQJJRX/KQAqAQAuAAQKfzIAAgoACQnBGf8sAGUCAAoACQnBGf8sAGUCAAAA.Kamacha:BAAALgAECgMJBgAAAA==.Kamaldren:BAAALgAECgMJAwAAAA==.Karellen:BAABLgAECn8UAAMeAAgJTgyFCwBdAQAeAAgJTgyFCwBdAQAdAAUJlAT9cwCAAAAAAA==.Kathren:BAAALgAECgYJBwAAAA==.',
Kh='Khathani:BAABLgAECn8fAAMGAAkJoBZjGgAPAQAGAAkJoBZjGgAPAQALAAQJHQtjIQCmAAAAAA==.',
Ki='Kieran:BAAALgAECgMJAwAAAA==.Kirara:BAAALgAECgQJBAAAAA==.',
Kn='Knobgoblinn:BAAALgAECgQJBAAAAA==.',
Ko='Komojo:BAABLgAECn8rAAIIAAgJURHwdgCAAQAIAAgJURHwdgCAAQAAAA==.Koriggan:BAACLgAFFH8GAAIVAAMJrQ8pHwDcAAAVAAMJrQ8pHwDcAAAuAAQKfzUABBUACQnrErsTAAgCABUACQnrErsTAAgCAAYABgkqEHpVAGgBAAsAAQnpAGWbABQAAAAA.',
Kr='Krazzikz:BAAALgADCgYJBgAAAA==.Krea:BAABLgAECn84AAIHAAkJWyKVAgAEAwAHAAkJWyKVAgAEAwAAAA==.Krixx:BAAALgADCgEJAQAAAA==.Kroval:BAAALgAECgUJBgAAAA==.Krystagosa:BAABLgAECn85AAQnAAkJiRYaCQBYAgAnAAkJiRYaCQBYAgAdAAYJJg/OTgDyAAAeAAMJVArEGQCFAAAAAA==.',
Ku='Kuriuh:BAABLgAECn8mAAIMAAkJnRYUPADrAQAMAAkJnRYUPADrAQAAAA==.Kurtcobainn:BAAALgADCgkJCQAAAA==.',
Ky='Kyllea:BAAALgAECgcJBwABLgAECgkJEgAQAAAAAA==.',
La='Lang:BAABLgAECn87AAImAAkJ1x3ZAwCUAgAmAAkJ1x3ZAwCUAgAAAA==.Lanoraloca:BAAALgAECgUJCQABLgAECgkJKwAWABsdAA==.Laveaux:BAAALgAECgEJAQAAAA==.',
Le='Legionslamm:BAAALgADCgUJBQAAAA==.Leonldas:BAAALgADCgEJAQAAAA==.',
Li='Lightsfaith:BAAALgADCgYJBgABLgAECgkJJgAjAFMLAA==.',
Lo='Lodix:BAAALgAFFAIJBAAAAA==.Loopey:BAAALgAECgcJEAABLgAFFAgJIAAOAEATAA==.Lorethil:BAAALgAECgYJDAAAAA==.',
Lu='Luceriss:BAABLgAECn8iAAICAAkJJg/HGwC5AQACAAkJJg/HGwC5AQAAAA==.Luminous:BAAALgADCgcJCAABLgAECgkJJgAMAJ0WAA==.',
Ma='Maeroth:BAAALgADCgUJBQABLgAFFAkJHwAMAFEPAA==.Magicboi:BAABLgAECn8aAAIKAAgJmQ4yfACAAQAKAAgJmQ4yfACAAQAAAA==.Magwar:BAACLgAFFH8XAAIRAAgJHxSXCADXAQARAAgJHxSXCADXAQAuAAQKfzEAAhEACQlXIT8JAM4CABEACQlXIT8JAM4CAAAA.Maike:BAABLgAECn85AAMCAAkJohnuDwAvAgACAAkJIxTuDwAvAgAUAAgJQBSrCAC+AQAAAA==.Marcelyne:BAAALgAECgYJCAABLgAECgkJJAAMAPYTAA==.Marothius:BAACLgAFFH8fAAQMAAkJUQ+YDQDoAQAMAAkJUQ+YDQDoAQAkAAEJvxAUFABWAAAaAAEJ3AL/LQA2AAAuAAQKfzMABAwACQlhHlokAE4CAAwACQlQHFokAE4CACQABgmMHBAXAJEBABoAAgnLGnAiAK4AAAAA.Martaug:BAACLgAFFH8FAAINAAIJsx0sVQCmAAANAAIJsx0sVQCmAAAuAAQKfyUAAg0ACQknH9QSALYCAA0ACQknH9QSALYCAAAA.Marune:BAAALgAECgkJDwAAAA==.Maurice:BAAALgADCgYJCwAAAA==.Maverage:BAABLgAECn84AAMRAAkJDCKeBwDlAgARAAkJDCKeBwDlAgASAAYJ6xPsKwAcAQAAAA==.Mawg:BAAALgAECgYJBwAAAA==.Mayfair:BAABLgAECn8mAAMNAAkJpxRXLwD4AQANAAkJpxRXLwD4AQAlAAcJOBNSQwAmAQAAAA==.Mayia:BAAALgAECgcJBwAAAA==.',
Mb='Mbarnes:BAAALgAECgQJBwAAAA==.',
Me='Meaculpa:BAAALgAECgQJBAAAAA==.Melee:BAACLgAFFH9OAAIIAAkJaSZhAABgAwAIAAkJaSZhAABgAwAuAAQKfxYAAggACQmZJj0CALoDAAgACQmZJj0CALoDAAAA.',
Mi='Midnightfear:BAAALgADCgcJBwAAAA==.Mikeyy:BAAALgADCgMJAwAAAA==.Mimoza:BAAALgAECgYJCgAAAA==.Minibeer:BAAALgAECgYJEgAAAA==.Minimee:BAAALgAECgYJCwAAAA==.Miquella:BAACLgAFFH8IAAMEAAMJpgyJEACxAAAEAAMJpgyJEACxAAAFAAIJzgPqlABQAAAuAAQKfxcAAwQACQliGLgUAOsBAAQACAmWF7gUAOsBAAUAAgnsENskAHMAAAAA.Misohotramen:BAACLgAFFH8UAAIFAAUJQxsLPQAyAQAFAAUJQxsLPQAyAQAuAAQKfyQAAgUACQnQILUzACsCAAUACQnQILUzACsCAAAA.',
Mo='Moist:BAABLgAECn87AAIbAAkJaCM4AgAhAwAbAAkJaCM4AgAhAwAAAA==.Monkstrosity:BAABLgAECn8WAAIWAAkJUxqqAQBqAgAWAAkJUxqqAQBqAgAAAA==.Mookks:BAAALgADCgMJAQAAAA==.Moonlock:BAAALgADCgYJCgAAAA==.Moor:BAABLgAECn8aAAIiAAkJrwaoBwAvAQAiAAkJrwaoBwAvAQAAAA==.Mordakka:BAAALgAECgYJCQAAAA==.Morior:BAABLgAECn8+AAMMAAkJSht4IgBYAgAMAAkJSht4IgBYAgAkAAIJMBi0UQB5AAAAAA==.Motgustus:BAAALgAFFAEJAQAAAA==.',
Mu='Muirfire:BAAALgAECgUJBQAAAA==.Murrda:BAACLgAFFH8FAAIMAAIJ3BK1mQCRAAAMAAIJ3BK1mQCRAAAuAAQKfzcAAwwACQmpId0MAOYCAAwACQmpId0MAOYCABoAAQnTE+A5AEEAAAAA.Musk:BAAALgAECgIJBQABLgAECggJLwAKAOAWAA==.Muskrattsam:BAABLgAECn8vAAIKAAgJ4Ba3SAABAgAKAAgJ4Ba3SAABAgAAAA==.',
My='Myravia:BAABLgAECn8WAAIKAAcJrxAwkQCxAQAKAAcJrxAwkQCxAQAAAA==.Myrokos:BAABLgAECn9RAAIIAAkJ+SJJCgAVAwAIAAkJ+SJJCgAVAwAAAA==.Mysthicc:BAAALgADCgIJAgAAAA==.',
['Mó']='Mónónoke:BAAALgADCgMJAwAAAA==.',
['Mö']='Möokss:BAAALgAECgEJAQAAAA==.',
Na='Nailo:BAABLgAECn9WAAIbAAkJeBQfEADnAQAbAAkJeBQfEADnAQAAAA==.Nails:BAAALgAECgQJBgAAAA==.Nathanos:BAAALgAECggJCwAAAA==.',
Ne='Nepetala:BAAALgAECgYJBgABLgAFFAgJFQAdAE8TAA==.Nezar:BAAALgAFFAEJAwABLgAFFAEJBQAmAFcYAA==.',
Nh='Nhat:BAAALgAECgMJAwAAAA==.',
Ni='Niaah:BAAALgADCgYJAQABLgAECgkJFwABAL4cAA==.Niddy:BAACLgAFFH8YAAIKAAQJ1BwoJABQAQAKAAQJ1BwoJABQAQAuAAQKf1IAAgoACQl9HX4HAA8CAAoACQl9HX4HAA8CAAAA.Nightshanda:BAAALgAECgMJBQABLgAECgkJEgAQAAAAAA==.Nisardela:BAAALgADCgMJAwAAAA==.',
No='Nobudy:BAACLgAFFH8pAAMhAAkJpx0IBQAzAgAhAAkJpx0IBQAzAgAjAAQJzAKiMADPAAAuAAQKfzEABCEACQm6JEgEABUDACEACQm6JEgEABUDACAABgnIFcYuAIgBACMAAgnNBOJZAC4AAAAA.Noel:BAABLgAECn8+AAIgAAkJxRyPAQC6AgAgAAkJxRyPAQC6AgAAAA==.Nohari:BAAALgAECgQJBAAAAA==.Nomsayin:BAACLgAFFH8GAAIMAAMJHQumiwCuAAAMAAMJHQumiwCuAAAuAAQKfzAAAgwACQkuGRYzAEACAAwACQkuGRYzAEACAAAA.Nonospot:BAABLgAECn8sAAMhAAkJmhfHEwAxAgAhAAkJmhfHEwAxAgAjAAEJvANJWgAuAAAAAA==.Noobuddy:BAAALgAECgUJCgABLgAFFAkJKQAhAKcdAA==.Noraboo:BAABLgAECn8jAAMiAAgJQRqjBAD7AQAiAAYJbxyjBAD7AQAKAAgJmRjUYQC8AQABLgAECgkJKwAWABsdAA==.Norannestra:BAAALgAECgYJDQAAAA==.Norganon:BAAALgAECgMJBAAAAA==.Novalicious:BAAALgAECgEJAQAAAA==.Novasera:BAAALgAECgcJCAAAAA==.',
Nu='Nubmuffin:BAAALgADCgUJBQAAAA==.',
Nv='Nvied:BAABLgAECn8cAAMMAAkJpRTYRQDJAQAMAAgJpRTYRQDJAQAkAAEJAAD5cwAxAAAAAA==.',
Ny='Nyctt:BAABLgAECn8YAAMCAAkJ8BlNGQA6AgACAAkJUhhNGQA6AgAUAAIJ5xdoFgCSAAAAAA==.Nystra:BAABLgAECn8WAAIMAAkJAhhzJgBEAgAMAAkJAhhzJgBEAgAAAA==.Nyzstra:BAABLgAECn8wAAIKAAkJXiLKGQC/AgAKAAkJXiLKGQC/AgAAAA==.',
['Nê']='Nêwt:BAACLgAFFH8SAAIKAAQJgg7iQQDBAAAKAAQJgg7iQQDBAAAuAAQKf0QAAgoACQkEIPoJAMkBAAoACQkEIPoJAMkBAAAA.',
['Nì']='Nìrvana:BAAALgAECgQJCwAAAA==.',
['Nú']='Núbmuffin:BAAALgAECgEJAgAAAA==.',
On='Onlybeams:BAABLgAECn8fAAIFAAkJQBsqIQBOAgAFAAkJQBsqIQBOAgAAAA==.',
Or='Oreo:BAAALgAECgEJAgAAAA==.Orphu:BAAALgAECgEJAQAAAA==.',
Pa='Pallyplexity:BAAALgAFFAEJAQABLgAECgkJZAAPAIkmAA==.Palmiste:BAAALgAECgQJBgAAAA==.Pandad:BAAALgADCgEJAQABLgAECgkJIQAOADYYAA==.Pangoplexity:BAAALgADCgIJAgAAAA==.Parahsalin:BAAALgAECgEJAQABLgAECgYJEgAQAAAAAA==.Partyhard:BAAALgAECgEJAQAAAA==.Pastryblust:BAABLgAFFH8NAAIlAAgJUhLtEwD/AAAlAAgJUhLtEwD/AAAAAA==.Pastrydragon:BAACLgAFFH8LAAMdAAQJORbhEAD7AAAdAAQJORbhEAD7AAAeAAEJJxkoDQBLAAAuAAQKfzAAAx0ACAmrINUKAMgCAB0ACAmSHtUKAMgCAB4ABglYI5ULACICAAEuAAUUCAkNACUAUhIA.',
Ph='Phaeliea:BAAALgAECgUJBQAAAA==.',
Pi='Pistachio:BAABLgAECn8cAAIEAAYJqBEsNQDpAAAEAAYJqBEsNQDpAAAAAA==.Pitviper:BAABLgAECn8mAAIUAAkJ4x7MAwBqAgAUAAkJ4x7MAwBqAgAAAA==.',
Po='Pocketrokit:BAAALgAECgkJDAAAAA==.Pogaca:BAAALgAECgcJDgABLgAECggJFwAXAP8bAA==.Portabull:BAAALgADCgcJBwABLgAFFAEJAQAQAAAAAA==.Possess:BAABLgAECn8mAAIMAAcJVx3aRgDFAQAMAAcJVx3aRgDFAQAAAA==.Pownora:BAABLgAECn8rAAMWAAkJGx2wCwCHAgAWAAkJGx2wCwCHAgAoAAIJ/Q1YvAAxAAAAAA==.',
Ps='Psarchasm:BAABLgAECn8wAAIRAAkJlg06LgCYAQARAAkJlg06LgCYAQAAAA==.',
Pu='Puck:BAAALgAECgEJAgAAAA==.Puffnstuff:BAAALgAECgUJBQAAAA==.Pugstar:BAAALgAECgMJAwAAAA==.',
Qe='Qel:BAAALgADCgYJCQAAAA==.',
Ra='Rai:BAABLgAECn87AAIGAAkJzSRiBgAuAwAGAAkJzSRiBgAuAwAAAA==.Rancidbeef:BAAALgAECgMJAwAAAA==.Rapha:BAABLgAECn8nAAIOAAkJNyJ9BQDpAgAOAAkJNyJ9BQDpAgAAAA==.Rayyzer:BAABLgAECn8eAAMCAAkJqCHmDABYAgACAAkJqCHmDABYAgAUAAIJtBhsGgCWAAAAAA==.Rayyzor:BAAALgAECgEJAQAAAA==.Razzu:BAABLgAFFH8FAAIRAAMJmRaoFwDhAAARAAMJmRaoFwDhAAABLgAFFAMJCgAVAPEXAA==.',
Re='Realrogue:BAAALgAECgYJCwABLgAECgkJZAAPAIkmAA==.Realtree:BAABLgAECn8UAAIJAAkJHBqoBABmAgAJAAkJHBqoBABmAgAAAA==.Rema:BAAALgADCgQJBAAAAA==.Reyna:BAAALgADCgUJBQAAAA==.',
Ri='Riddles:BAACLgAFFH8FAAIbAAIJPQ0XIQBRAAAbAAIJPQ0XIQBRAAAuAAQKfx4AAxsACAnMHc0JAE0CABsACAnMHc0JAE0CABgAAQkWI4S1AFoAAAAA.Rincewind:BAAALgAECgEJAQAAAA==.',
Ro='Rossabella:BAABLgAECn9FAAMgAAkJahuRCwCtAgAgAAkJahuRCwCtAgAjAAgJ0w7HGwC4AQAAAA==.Rot:BAABLgAECn8nAAIfAAkJCSb1AgAWAwAfAAkJCSb1AgAWAwAAAA==.',
Ru='Rude:BAAALgAECgYJBgABLgAFFAcJFAARAEoeAA==.Ruzala:BAAALgADCgEJAQAAAA==.',
Sa='Samsonn:BAAALgADCgQJBAAAAA==.Sanctity:BAAALgADCgYJCgAAAA==.Santino:BAACLgAFFH8SAAMYAAMJPQjiTACLAAAYAAMJPQjiTACLAAAbAAMJ9wr+FQB5AAAuAAQKfx4AAhgACAlhGdIeAFACABgACAlhGdIeAFACAAEuAAUUBAkiAAoAJRUA.Saphdruid:BAAALgAECgMJBAABLgAECgkJEgAQAAAAAA==.Sapherapal:BAAALgAECgkJEgAAAA==.Saphlocket:BAAALgAECgYJEgAAAA==.Saphmage:BAAALgAECgQJBAABLgAECgkJEgAQAAAAAA==.Sathin:BAABLgAECn8yAAIFAAkJmwpbYQBmAQAFAAkJmwpbYQBmAQAAAA==.',
Sc='Scher:BAAALgADCgkJCwAAAA==.Scrungus:BAAALgADCgYJBgAAAA==.Scufalufagus:BAAALgAECgUJBQABLgAFFAkJHwAMAFEPAA==.',
Se='Seetick:BAAALgAECgIJBAAAAA==.Sefekat:BAAALgAECgEJAQABLgAECgkJHwAFAEAbAA==.September:BAAALgAECgIJAgABLgAFFAcJEwAGABgQAA==.Sevatar:BAABLgAECn8nAAIEAAkJUg23HwB8AQAEAAkJUg23HwB8AQAAAA==.',
Sf='Sfcwarner:BAAALgAECgEJAgAAAA==.',
Sg='Sgtwarner:BAAALgAECgYJCwAAAA==.',
Sh='Shampooyou:BAABLgAECn88AAINAAgJOBKSEQAcAQANAAgJOBKSEQAcAQAAAA==.Shockakhan:BAAALgAECgkJDgAAAA==.Shocknstone:BAAALgADCgcJBwABLgAECgkJZAAPAIkmAA==.',
Si='Silentmamba:BAAALgAECgEJAQAAAA==.Sinistra:BAABLgAECn8ZAAMjAAgJ+g4sKQCKAQAjAAgJ+g4sKQCKAQAhAAIJyQ7uKQAuAAAAAA==.',
Sk='Skelecopter:BAAALgADCgMJAwAAAA==.',
Sl='Slapshot:BAAALgAECggJCwABLgAECggJFwAXAP8bAA==.Slashmoo:BAAALgAECgEJAgAAAA==.',
Sn='Snowflake:BAAALgADCgcJBwAAAA==.',
Sp='Spellsteal:BAABLgAECn8lAAIKAAkJuxiLOAA2AgAKAAkJuxiLOAA2AgABLgAFFAcJFwAPADcKAA==.Spicynudz:BAAALgAECgEJAQAAAA==.Spring:BAACLgAFFH8TAAMGAAcJGBB6RAAkAQAGAAcJGBB6RAAkAQALAAEJpAAJLgA2AAAuAAQKfyUAAwYACQlfHQYwABwCAAYACQkjHQYwABwCAAsABgnTC/ZMAB0BAAAA.',
Ss='Ssgwarner:BAAALgAECgEJAQAAAA==.',
St='Stardel:BAAALgAECgYJDQABLgAFFAgJJAACAIsjAA==.Sting:BAABLgAECn8pAAIGAAgJ/xG0EgBUAQAGAAgJ/xG0EgBUAQAAAA==.Stormclaw:BAABLgAECn8zAAMYAAkJSx2fEQDDAgAYAAkJSx2fEQDDAgAXAAEJkBwqeQBUAAAAAA==.Stormcrash:BAAALgADCgYJBgABLgAECgkJJgAMAJ0WAA==.Stregoica:BAAALgADCgcJDgABLgAFFAkJHwAMAFEPAA==.',
Su='Suhfering:BAAALgADCgYJBgABLgAECgkJHwAFAEAbAA==.Superbeef:BAAALgAECgEJAgAAAA==.Sushiiez:BAAALgADCgMJAwAAAA==.Suwo:BAAALgADCgIJAQAAAA==.',
Sy='Sychopath:BAAALgAECgYJEAAAAA==.Sykadelik:BAAALgAECgMJAwAAAA==.Syngoma:BAAALgADCgIJAgAAAA==.',
Ta='Tallron:BAACLgAFFH8nAAIYAAkJXxmgBwCFAgAYAAkJXxmgBwCFAgAuAAQKfy4AAxgACQmaJLcJAPcCABgACQmaJLcJAPcCABcABQmPFRlCAAUBAAAA.Tallsera:BAAALgADCgcJDQABLgAFFAkJJwAYAF8ZAA==.Tallyfan:BAAALgAECgIJAgAAAA==.Tamedsloth:BAAALgAECgYJBgAAAA==.Tandraella:BAAALgAECgQJBQABLgAFFAQJBwABAI8ZAA==.Tanerella:BAAALgAECgEJAQAAAA==.Tanthalos:BAAALgAECgcJCQAAAA==.Taroquin:BAAALgADCgkJCgAAAA==.',
Te='Ternay:BAAALgADCgIJAQAAAA==.Teskhamen:BAAALgAFFAIJBAAAAA==.Tetamesh:BAAALgADCgQJBAAAAA==.',
Th='Theory:BAAALgAECgIJAgAAAA==.Theskabandit:BAAALgADCgcJEQAAAA==.Thrustruggle:BAAALgAECgMJAwAAAA==.',
Ti='Tiamot:BAAALgADCgUJCAAAAA==.Tinynutz:BAAALgAECgMJBAAAAA==.',
To='Toby:BAAALgAECgYJBgAAAA==.Tojikitoushi:BAACLgAFFH8HAAITAAMJJQ/pDwDHAAATAAMJJQ/pDwDHAAAuAAQKfzgAAhMACQnpIGkDANECABMACQnpIGkDANECAAAA.Tombs:BAAALgAFFAIJAgAAAA==.Tonsonger:BAAALgAECgUJCAAAAA==.Totenhammer:BAAALgAECgQJCwAAAA==.Totenplage:BAAALgAECgQJBAAAAA==.',
Tr='Trid:BAAALgAECggJCAAAAA==.Trisolari:BAAALgAECgEJAQAAAA==.Tristex:BAAALgAECgUJBQABLgAECggJFwAXAP8bAA==.',
Tu='Tuha:BAAALgAFFAIJAgAAAA==.',
Tw='Twergstronk:BAAALgADCgEJAQAAAA==.',
Ty='Tyrian:BAAALgAECgEJAQAAAA==.Tyrolia:BAAALgAECgMJAwAAAA==.',
Um='Umibozu:BAAALgAECgIJAgAAAA==.',
Un='Unoocho:BAAALgADCggJCAAAAA==.',
Ur='Urchak:BAAALgAECgYJBgAAAA==.',
Va='Valliya:BAABLgAFFH8IAAIIAAMJbwOvhgCmAAAIAAMJbwOvhgCmAAAAAA==.',
Ve='Velratha:BAABLgAECn8UAAIaAAgJtQ80DAB2AQAaAAgJtQ80DAB2AQAAAA==.Vesfu:BAAALgADCgEJAQAAAA==.Vesi:BAAALgADCgcJCgAAAA==.Vextt:BAABLgAECn8eAAMhAAgJDRjAKgB9AQAhAAcJRxvAKgB9AQAgAAIJeBiMawA7AAABLgAFFAIJAgAQAAAAAA==.',
Vi='Vicsta:BAAALgAECggJCwAAAA==.',
Vo='Voidrend:BAAALgAECgQJBwAAAA==.Voidwarner:BAAALgAECgQJBgAAAA==.Volight:BAAALgADCgYJCQAAAA==.Volke:BAABLgAECn8nAAIoAAkJMxbeHgAjAgAoAAkJMxbeHgAjAgAAAA==.Volmnk:BAAALgAECgUJDAAAAA==.Volq:BAAALgAECgEJAQAAAA==.Voltarix:BAAALgAECgYJCQAAAA==.Voodoopriest:BAABLgAECn8YAAIMAAcJMwRDpAAQAQAMAAcJMwRDpAAQAQAAAA==.Voyria:BAABLgAECn8xAAQYAAkJVwhKcADjAAAYAAgJ9QRKcADjAAAXAAYJiQWhVwCzAAAcAAIJwQLiVQAuAAAAAA==.',
Vs='Vs:BAAALgAECgYJBgAAAA==.',
Vy='Vynlenn:BAAALgADCgMJAwAAAA==.Vyskaar:BAAALgAECgEJAgAAAA==.Vyskar:BAAALgAECgUJDgAAAA==.Vyskary:BAAALgAECgEJBQAAAA==.',
Wa='Warm:BAACLgAFFH8hAAIWAAkJuBpvAgBGAgAWAAkJuBpvAgBGAgAuAAQKfycAAhYACQkTImsIAPMCABYACQkTImsIAPMCAAAA.Warmlight:BAAALgAECgYJDAAAAA==.',
We='Weewu:BAAALgAECgQJBAABLgAECgYJBgAQAAAAAA==.Weeziveli:BAAALgAECgQJDQAAAA==.Weledish:BAACLgAFFH8qAAIKAAcJ3B4wEwDnAQAKAAcJ3B4wEwDnAQAuAAQKfzEAAgoACQleHXAwAFcCAAoACQleHXAwAFcCAAAA.Weleron:BAAALgAFFAIJAgAAAA==.',
Wh='Whystler:BAAALgAECgIJAgAAAA==.',
Wi='Wienercat:BAABLgAECn8hAAIYAAcJ6STyDgDeAgAYAAcJ6STyDgDeAgABLgAECggJJwANAHcjAA==.Wimol:BAAALgAECgYJDAABLgAECgkJKwAWABsdAA==.Windmacedu:BAAALgAECgYJCgAAAA==.',
Wo='Wowdra:BAABLgAECn8WAAIKAAcJrRKIEQBUAQAKAAcJrRKIEQBUAQAAAA==.',
Xt='Xtreeme:BAAALgAECgIJAgAAAA==.',
Ya='Yael:BAABLgAECn80AAIFAAkJeB7HGgB0AgAFAAkJeB7HGgB0AgAAAA==.Yama:BAAALgAECgcJEAAAAA==.',
Za='Zamrazac:BAAALgAECgUJCAABLgAECgkJMwAYAEsdAA==.Zarewien:BAABLgAECn8uAAIgAAkJ6AovLABoAQAgAAkJ6AovLABoAQAAAA==.',
Ze='Zeddicus:BAAALgAECgMJAwAAAA==.',
Zi='Ziddles:BAABLgAECn8cAAIVAAkJGxvZEwAGAgAVAAkJGxvZEwAGAgAAAA==.',
Zo='Zomgdk:BAAALgAECgEJAgABLgAECgkJRQAOAPsfAA==.Zomgmonk:BAABLgAECn9FAAIOAAkJ+x9ABQDtAgAOAAkJ+x9ABQDtAgAAAA==.Zomgzilla:BAAALgAECggJAQABLgAECgkJRQAOAPsfAA==.Zorep:BAAALgAECgEJAQAAAA==.Zorien:BAAALgAECgQJBAAAAA==.',
Zu='Zuraq:BAAALgAECgEJBgAAAA==.Zurisdad:BAABLgAECn83AAIOAAkJ8B7iBwC2AgAOAAkJ8B7iBwC2AgABLgAFFAUJFAAKAMYXAA==.Zurishmi:BAACLgAFFH8cAAINAAUJ/h5lBQB3AQANAAUJ/h5lBQB3AQAuAAQKfzMAAg0ACQk6JpcBALgDAA0ACQk6JpcBALgDAAAA.',
['Äm']='Ämäteräsu:BAAALgAECggJEgAAAA==.',
['Òr']='Òreo:BAAALgAECgQJBAABLgAFFAgJIAAOAEATAA==.',
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
