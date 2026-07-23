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

local lookup = {'Paladin-Holy','Rogue-Subtlety','Rogue-Outlaw','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-BeastMastery','Paladin-Protection','Paladin-Retribution','DeathKnight-Unholy','Mage-Frost','Hunter-Marksmanship','Warlock-Demonology','Shaman-Restoration','Warrior-Protection','Unknown-Unknown','Warrior-Fury','Warrior-Arms','Shaman-Enhancement','Rogue-Assassination','Hunter-Survival','Monk-Windwalker','Monk-Brewmaster','Druid-Balance','Druid-Restoration','DeathKnight-Frost','Warlock-Affliction','Druid-Guardian','Druid-Feral','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Blood','Priest-Holy','Priest-Shadow','Mage-Arcane','Priest-Discipline','Warlock-Destruction','Shaman-Elemental','DemonHunter-Vengeance','Evoker-Preservation','Monk-Mistweaver',}
local provider = {region='US',realm='Nathrezim',name='US',type='weekly',zone=46,date='2026-07-19',data={Ab='Abysm:BAAALgADCgkJDwAAAA==.',
Ac='Achillios:BAAALgADCgMJAwABLgAFFAQJBwABAI8ZAA==.',
Ad='Adorabull:BAAALgAFFAEJAQAAAA==.',
Ae='Aemun:BAACLgAFFH8LAAICAAMJcxOpJwDrAAACAAMJcxOpJwDrAAAuAAQKf1UAAwIACQl4HtQBAPUBAAIACQl4HtQBAPUBAAMABgmUCbAIAPYAAAAA.',
Ag='Aggfu:BAAALgADCgYJBgAAAA==.',
Ai='Ainek:BAAALgADCgEJAQAAAA==.',
Ak='Akeeli:BAAALgADCgQJBAAAAA==.Akelita:BAABLgAECn8hAAMEAAYJrxiMJQBNAQAEAAYJrxiMJQBNAQAFAAUJcAgWzQCXAAAAAA==.',
Al='Alailea:BAABLgAECn9DAAIGAAkJMxQVPgDpAQAGAAkJMxQVPgDpAQAAAA==.Aloepaw:BAAALgAECgEJAQAAAA==.Alragnar:BAAALgAECgIJAgAAAA==.Alwysafkable:BAABLgAFFH8HAAIHAAMJzBiZBwCGAAAHAAMJzBiZBwCGAAAAAA==.',
Am='Amageadin:BAAALgADCgkJCQAAAA==.Amazadin:BAACLgAFFH8HAAIBAAQJjxkLJwDqAAABAAQJjxkLJwDqAAAuAAQKfxkAAwEACAkpHO8bADUCAAEACAkpHO8bADUCAAgAAgncEvw0AXkAAAAA.Amazashock:BAAALgAECgUJDQABLgAFFAQJBwABAI8ZAA==.',
An='Andiwin:BAABLgAECn8ZAAIJAAgJ9Q90agCRAQAJAAgJ9Q90agCRAQAAAA==.Andurthil:BAABLgAECn8oAAIKAAgJUw1GjwBZAQAKAAgJUw1GjwBZAQAAAA==.Anzul:BAAALgAECgUJBgAAAA==.',
Ar='Archive:BAAALgAECgkJCwAAAA==.Artistic:BAABLgAECn8cAAIGAAgJeBlyQQDeAQAGAAgJeBlyQQDeAQAAAA==.Arubion:BAABLgAECn8ZAAIIAAgJSxGjYQCtAQAIAAgJSxGjYQCtAQAAAA==.Arylanna:BAAALgAECgYJDQAAAA==.',
As='Asure:BAABLgAECn8tAAMGAAkJ/heRKgAzAgAGAAkJ/heRKgAzAgALAAYJTgfdTwAPAQAAAA==.',
Au='Augusteen:BAAALgAECgIJAgAAAA==.',
Az='Azerith:BAAALgAECgYJDwAAAA==.',
Ba='Badmorda:BAAALgADCgEJAQAAAA==.',
Be='Bearforceone:BAAALgADCgMJAwAAAA==.Berret:BAAALgADCgkJEQAAAA==.',
Bi='Bipolar:BAAALgADCgEJAQAAAA==.',
Bl='Blackheart:BAABLgAECn8bAAIMAAgJnBjCLQBWAgAMAAgJnBjCLQBWAgAAAA==.Blodreina:BAAALgADCgUJCQAAAA==.Bloodarchon:BAABLgAECn8rAAMIAAkJYBYBNwAlAgAIAAkJYBYBNwAlAgAHAAYJnQkUMQCiAAAAAA==.Bloodtemplar:BAABLgAECn81AAIIAAkJ2Bq6JAByAgAIAAkJ2Bq6JAByAgAAAA==.',
Bo='Bombs:BAABLgAECn8UAAIKAAQJhRHA0gDuAAAKAAQJhRHA0gDuAAABLgAFFAgJIwANAPMWAA==.Bonesy:BAAALgAECgYJBgAAAA==.Bottomstop:BAAALgADCgEJAQAAAA==.Bouren:BAAALgAECgEJAQAAAA==.',
Br='Brassmönke:BAAALgAECgkJDgABLgAECgkJWwAOAIkmAA==.Bravia:BAAALgADCgUJBwAAAA==.Brewdogg:BAAALgADCgcJBwAAAA==.Brokasa:BAAALgADCgIJAgAAAA==.Brutalitops:BAAALgADCgMJAwAAAA==.Brutusdabull:BAAALgAECgYJBgAAAA==.Brônze:BAAALgADCgQJBAAAAA==.',
Bu='Burdomew:BAAALgADCgEJAQAAAA==.',
Ca='Cadbury:BAAALgADCgIJAgABLgAECgUJCAAPAAAAAA==.Canan:BAAALgAECgUJBgAAAA==.Canansbrew:BAAALgAECgEJAQAAAA==.Canestoast:BAAALgAECgEJAQAAAA==.Casmina:BAABLgAECn8WAAIQAAkJ7xlRIQBJAgAQAAkJ7xlRIQBJAgAAAA==.Castiell:BAAALgADCgUJBgAAAA==.Catalystic:BAAALgADCgEJAQAAAA==.Catd:BAAALgAECgIJBAAAAA==.',
Ce='Celum:BAABLgAECn8eAAIJAAcJnwcOvQACAQAJAAcJnwcOvQACAQAAAA==.Ceola:BAABLgAECn8yAAMRAAcJLxCDNAD0AAARAAYJGg6DNAD0AAAOAAcJSw3WBwCtAAAAAA==.',
Ch='Chamming:BAAALgADCgIJAgAAAA==.Chaquén:BAACLgAFFH8JAAISAAMJ4RZoDgDZAAASAAMJ4RZoDgDZAAAuAAQKfyIAAhIACQn6GdUHAEwCABIACQn6GdUHAEwCAAAA.Charizard:BAAALgAECgEJAQAAAA==.Charmander:BAABLgAECn8fAAQTAAYJshfzCgCAAQATAAYJshfzCgCAAQACAAQJUgl9SACWAAADAAMJ2wRAGwB0AAAAAA==.Chaw:BAACLgAFFH8bAAMUAAgJmh3HAQBDAgAUAAgJXhjHAQBDAgAGAAEJcCamIQBdAAAuAAQKfzIABBQACQnuJPcDAPICABQACQnsJPcDAPICAAsABwnWHy0iABQCAAYABAk3I1BIAJEBAAAA.Chenkenichi:BAACLgAFFH8JAAIVAAMJhgYVLQCWAAAVAAMJhgYVLQCWAAAuAAQKfzIAAxUACQmsDwsFADIBABUACQmsDwsFADIBABYABQkoAqtoAJ8AAAAA.Chergar:BAACLgAFFH8RAAIOAAYJMhfkCQD9AAAOAAYJMhfkCQD9AAAuAAQKfx4AAg4ACQkVIkwFAOkCAA4ACQkVIkwFAOkCAAAA.Chibari:BAAALgAECgYJBgAAAA==.Chskie:BAAALgADCgUJBQAAAA==.Chsky:BAAALgADCgUJBQAAAA==.Chuiyi:BAAALgAECgEJAgAAAA==.',
Ci='Cinny:BAABLgAECn9GAAIGAAkJchyPGwCAAgAGAAkJchyPGwCAAgAAAA==.Cinnyrolls:BAABLgAECn8XAAMXAAgJ/xvyGwDqAQAXAAgJ/xvyGwDqAQAYAAQJtBBhhwDHAAAAAA==.Cityairlines:BAABLgAECn8nAAIZAAkJuRSUDACuAQAZAAkJuRSUDACuAQAAAA==.',
Cl='Clare:BAAALgAECgYJCQAAAA==.',
Cm='Cmoneyy:BAAALgAECgYJCAAAAA==.',
Co='Cogrolls:BAAALgAECggJCQAAAA==.Cooldukenuke:BAACLgAFFH8KAAIBAAMJqRf4DwDaAAABAAMJqRf4DwDaAAAuAAQKfycAAgEACQmjHDoTAHkCAAEACQmjHDoTAHkCAAAA.',
Cr='Creepychalk:BAABLgAECn8mAAMaAAgJ3w8TAgB4AQAaAAgJ3w8TAgB4AQAMAAEJsAHZZAEcAAAAAA==.Criticize:BAABLgAECn8nAAIIAAgJ1gw/oAA3AQAIAAgJ1gw/oAA3AQAAAA==.',
Cs='Csor:BAAALgAECgMJAwAAAA==.Csorb:BAABLgAECn8xAAMbAAkJ8SDtBADEAgAbAAkJviDtBADEAgAcAAEJySV5OwBrAAAAAA==.Csoren:BAAALgAECgEJAQAAAA==.Csoro:BAAALgADCggJCAAAAA==.',
Cu='Cultivation:BAAALgAECgUJCAAAAA==.Cursedcanfly:BAACLgAFFH8YAAIdAAcJ6By1DwAIAgAdAAcJ6By1DwAIAgAuAAQKfzMAAx0ACQnjJWYCAFYDAB0ACQnjJWYCAFYDAB4ABQnaFG8iABcBAAAA.',
Cw='Cw:BAAALgAECgEJAQAAAA==.',
De='Deagua:BAAALgAECgQJBAABLgAFFAgJFwAMAFULAA==.Deathdogg:BAACLgAFFH8VAAMJAAUJxxm5ZwApAQAJAAQJxxm5ZwApAQAfAAEJAACyVwAAAAAuAAQKfykAAgkACQlPIL41ACgCAAkACQlPIL41ACgCAAAA.Dejavu:BAACLgAFFH8cAAIWAAcJBxSiFwBlAQAWAAcJBxSiFwBlAQAuAAQKfykAAhYACQlAHTMbAMsBABYACQlAHTMbAMsBAAAA.Demivoi:BAAALgAECgYJBwAAAA==.Demona:BAAALgAECgEJAQAAAA==.Deppthcharge:BAAALgAECgYJDwAAAA==.Desdemona:BAAALgAECgcJDAAAAA==.Devimon:BAAALgADCgEJAQAAAA==.Devoi:BAAALgADCgEJAQAAAA==.',
Di='Dismonk:BAAALgAECgIJAgAAAA==.Distotem:BAAALgAECgEJAQABLgAECgIJAgAPAAAAAA==.',
Do='Donrain:BAAALgAECgQJBAAAAA==.Dooghammer:BAABLgAECn8ZAAISAAkJQxrzCQAcAgASAAkJQxrzCQAcAgAAAA==.',
Dr='Dragussy:BAAALgADCgcJDQABLgAECgkJWwAOAIkmAA==.Drakkana:BAAALgADCgYJBgAAAA==.',
Du='Dunkhan:BAAALgAECgEJAQABLgAECgYJDAAPAAAAAA==.Duplexity:BAABLgAECn9bAAMOAAkJiSZTAACDAwAOAAkJiSZTAACDAwAQAAEJuCFmhwBkAAAAAA==.',
Dw='Dwalin:BAAALgAECgMJCQABLgAECgkJGQASAEMaAA==.',
Ea='Eatmoorchikn:BAAALgAECgcJDAAAAA==.',
Ec='Ecko:BAAALgAECgEJAQAAAA==.',
Ed='Edolah:BAAALgAECgEJAQAAAA==.',
Eg='Egohakai:BAACLgAFFH8RAAIIAAUJrx1gQAAqAQAIAAUJrx1gQAAqAQAuAAQKfzAAAggACQkUJbkIACQDAAgACQkUJbkIACQDAAAA.',
El='Eloi:BAABLgAECn8WAAMgAAgJbyCrCQDNAgAgAAgJbyCrCQDNAgAhAAEJUhNbgQA6AAABLgAECgkJMwAYAEsdAA==.',
Em='Emieretta:BAABLgAECn88AAIJAAkJXRgMNgAmAgAJAAkJXRgMNgAmAgAAAA==.',
Eq='Eqdk:BAABLgAECn8hAAIJAAkJoxTdRwDqAQAJAAkJoxTdRwDqAQAAAA==.',
Er='Erret:BAACLgAFFH8UAAIKAAUJxhd5XwAiAQAKAAUJxhd5XwAiAQAuAAQKfzIAAwoACQlwI1EMABYDAAoACQlwI1EMABYDACIAAQngGVQUAEkAAAAA.',
Et='Ethaka:BAAALgAFFAIJAgAAAA==.',
Ey='Eyrie:BAAALgADCgYJBgAAAA==.',
Ez='Ezinder:BAABLgAECn8lAAIeAAcJfgpfAgDuAAAeAAcJfgpfAgDuAAAAAA==.',
Fa='Fabius:BAAALgADCgYJBgAAAA==.Faemos:BAAALgAECgkJCAAAAA==.Faience:BAABLgAECn8nAAIZAAkJMARXHgDaAAAZAAkJMARXHgDaAAAAAA==.Falorina:BAABLgAECn83AAMEAAkJbSRWAgBCAwAEAAkJbSRWAgBCAwAFAAEJAwXh6wAnAAAAAA==.Fathernature:BAACLgAFFH8JAAIXAAQJphB8JAAEAQAXAAQJphB8JAAEAQAuAAQKfx0AAxcACQknGd4oALgBABcACQknGd4oALgBABwAAQl5Bfw4ACUAAAAA.Fauna:BAAALgADCgMJAwAAAA==.Fazeup:BAAALgAECgcJBgAAAA==.',
Fe='Feldra:BAABLgAECn9IAAIFAAkJkiLYBgAfAwAFAAkJkiLYBgAfAwAAAA==.Felfaith:BAAALgAECgIJAgAAAA==.Fester:BAAALgADCgUJBQABLgAECgkJJgAMAJ0WAA==.',
Fi='Fightforbeer:BAAALgAECgEJAQAAAA==.Finnin:BAABLgAECn8jAAMQAAkJCSR3CwCwAgAQAAkJCSR3CwCwAgARAAEJ0gZ8SAAkAAAAAA==.',
Fl='Floptina:BAAALgAECgUJBQABLgAECgkJKwAVABsdAA==.',
Fo='Food:BAABLgAECn8mAAIGAAkJoRgrIQA/AgAGAAkJoRgrIQA/AgAAAA==.Formidabull:BAAALgAECgEJAQABLgAFFAEJAQAPAAAAAA==.Foxdiez:BAAALgAECggJEQAAAA==.',
Fr='Fredde:BAAALgAECgEJAgAAAA==.Freidafondle:BAAALgAECgYJEgAAAA==.Frostbite:BAAALgAECgcJCwAAAA==.Frozenfaith:BAABLgAECn8mAAMjAAkJUwuxMABaAQAjAAgJ1guxMABaAQAgAAMJMgQEZQBNAAAAAA==.',
Ft='Fthemeta:BAAALgADCgIJAgAAAA==.',
Fu='Fulci:BAAALgADCgUJBQAAAA==.Furioushealz:BAABLgAECn8nAAIIAAkJpxn/PgAKAgAIAAkJpxn/PgAKAgAAAA==.Furiouswind:BAAALgADCgEJAQAAAA==.',
Ga='Gardrius:BAAALgADCgYJBwAAAA==.',
Ge='Gerrad:BAAALgAECgUJBQAAAA==.',
Gh='Ghettomike:BAABLgAECn8pAAIJAAkJAB53NQApAgAJAAkJAB53NQApAgAAAA==.Ghoulbane:BAAALgADCgYJCgAAAA==.',
Gi='Gibbits:BAAALgAECgcJCQAAAA==.Giranimo:BAABLgAECn8vAAIGAAkJoRQ0MAAbAgAGAAkJoRQ0MAAbAgAAAA==.',
Gl='Glabados:BAAALgAECgIJAwABLgAECgkJJwAWADciAA==.Glossy:BAACLgAFFH8gAAMCAAcJch7YBwAsAgACAAcJch7YBwAsAgADAAMJ4hDBDACUAAAuAAQKfzIABAIACQmEJrkBAFMDAAIACQmEJrkBAFMDABMAAgkNHzAUALsAAAMAAgmEIaYVALgAAAAA.Glossycumbus:BAAALgADCgYJBgABLgAFFAcJIAACAHIeAA==.Glossydh:BAAALgAECgYJBgABLgAFFAcJIAACAHIeAA==.Glossydk:BAAALgAFFAEJAgABLgAFFAcJIAACAHIeAA==.Glossylock:BAAALgADCgcJDQABLgAFFAcJIAACAHIeAA==.',
Go='Golbigold:BAAALgAECgEJAQAAAA==.Goopy:BAAALgAECgMJAwABLgAECgYJBgAPAAAAAA==.Gorl:BAAALgAECgEJAQAAAA==.',
Gr='Grayhoff:BAABLgAECn8cAAIQAAkJkAsYMQCIAQAQAAkJkAsYMQCIAQAAAA==.Greathoof:BAAALgADCgMJAwAAAA==.Grewsom:BAACLgAFFH8XAAIIAAUJvhyhFQC+AQAIAAUJvhyhFQC+AQAuAAQKfy4AAwgACQlIJWMJAEYDAAgACQlIJWMJAEYDAAcABQnzIOAWAGoBAAAA.',
Gu='Gulmok:BAAALgADCgUJBQAAAA==.Guwugga:BAABLgAECn8eAAIkAAcJXBDFEQAsAQAkAAcJXBDFEQAsAQAAAA==.',
Ha='Halîk:BAABLgAECn8XAAIBAAkJvhwJLADXAQABAAkJvhwJLADXAQAAAA==.Haraka:BAAALgAECgMJBAAAAA==.Hardheaded:BAAALgAECgQJBQAAAA==.Harmshock:BAABLgAECn89AAISAAkJhCTBAgDpAgASAAkJhCTBAgDpAgAAAA==.Hathina:BAACLgAFFH8UAAMQAAcJSh4SCgC/AQAQAAYJcyISCgC/AQARAAEJfAmFQABIAAAuAAQKfzMAAxAACQnTJlYBAG8DABAACQnTJlYBAG8DABEAAwmCHykeAP4AAAAA.',
He='Heket:BAABLgAECn86AAMIAAgJtwgqswAaAQAIAAgJtwgqswAaAQABAAUJ0wdgCwCxAAAAAA==.Hektric:BAAALgAECgMJAwAAAA==.Helpinghandz:BAAALgAECgYJBgAAAA==.',
Hi='Highdra:BAAALgAECgYJEwAAAA==.Hill:BAABLgAECn8oAAIGAAkJhR/7FgCAAgAGAAkJhR/7FgCAAgAAAA==.Hive:BAABLgAECn8wAAIQAAkJThjBFQBBAgAQAAkJThjBFQBBAgAAAA==.',
Ho='Holygem:BAAALgAECgYJCgAAAA==.Holypower:BAAALgADCgcJDQAAAA==.Hotdogwater:BAABLgAECn8nAAMNAAgJdyPmCgAJAwANAAgJdyPmCgAJAwAlAAQJ5gmkfAB6AAAAAA==.',
Hu='Hunttres:BAAALgAECgUJBQAAAA==.Husentar:BAABLgAECn87AAIKAAkJ8CCOFQDYAgAKAAkJ8CCOFQDYAgAAAA==.Huuhablo:BAABLgAECn9AAAIFAAkJjRzsGAB/AgAFAAkJjRzsGAB/AgAAAA==.',
Ic='Icaron:BAAALgAECgcJDwAAAA==.',
Ig='Igothots:BAAALgAECgUJCgAAAA==.',
Il='Illuminottey:BAABLgAECn8UAAIIAAkJmQ+RlQBJAQAIAAkJmQ+RlQBJAQAAAA==.',
In='Inferium:BAAALgADCgYJBgABLgAFFAQJDwAPAAAAAA==.Infernom:BAAALgADCgMJAwABLgAFFAQJDwAPAAAAAA==.Insatiabull:BAABLgAECn8hAAMFAAkJqx2+EgDqAgAFAAgJ7x6+EgDqAgAEAAEJyxSgZQBCAAABLgAFFAEJAQAPAAAAAA==.',
Io='Iolchsk:BAAALgAECgQJDAAAAA==.',
Is='Ishaa:BAAALgAECgYJCgAAAA==.',
Ja='Jacksof:BAABLgAECn8UAAMhAAYJ7gUDXwCcAAAhAAYJ7gUDXwCcAAAjAAQJOQTdbABSAAAAAA==.Jackstands:BAABLgAECn9WAAMNAAkJmSH+BgBAAwANAAkJmSH+BgBAAwASAAgJgAUoHQAUAQAAAA==.Jagerin:BAAALgAECgYJCwABLgAECgkJJwAWADciAA==.January:BAAALgAFFAMJBAABLgAFFAUJEQAGABoVAA==.',
Je='Jeromy:BAAALgAECgEJAQAAAA==.Jesse:BAAALgADCgIJAgAAAA==.',
Ji='Jiffi:BAABLgAECn8ZAAImAAgJyRrwBQA8AgAmAAgJyRrwBQA8AgAAAA==.Jinksy:BAAALgAECgcJEQAAAA==.',
Jm='Jme:BAAALgAECgcJCQAAAA==.',
Jr='Jredz:BAAALgADCgEJAQAAAA==.',
Ju='Juanwick:BAAALgADCgQJBAAAAA==.Jubag:BAAALgADCgIJAgAAAA==.Julianus:BAAALgAECgIJAgAAAA==.Jumpercables:BAAALgAECgEJBAAAAA==.Junn:BAABLgAECn8nAAIlAAkJmBPVJgC1AQAlAAkJmBPVJgC1AQAAAA==.Justiciar:BAAALgAECgEJAQAAAA==.',
['Já']='Jánuary:BAAALgAECgUJBQAAAA==.',
Ka='Kahayman:BAACLgAFFH8dAAIKAAQJJRXFIwAxAQAKAAQJJRXFIwAxAQAuAAQKfzIAAgoACQnBGf8sAGUCAAoACQnBGf8sAGUCAAAA.Kamacha:BAAALgAECgMJBgAAAA==.Kamaldren:BAAALgAECgMJAwAAAA==.Karellen:BAABLgAECn8UAAMeAAgJTgyFCwBdAQAeAAgJTgyFCwBdAQAdAAUJlAT9cwCAAAAAAA==.Kathren:BAAALgAECgYJBwAAAA==.',
Kh='Khathani:BAABLgAECn8fAAMGAAkJoBb/EgAjAQAGAAkJoBb/EgAjAQALAAQJHQtjIQCmAAAAAA==.',
Ki='Kieran:BAAALgAECgMJAwAAAA==.Kirara:BAAALgAECgQJBAAAAA==.',
Kn='Knobgoblinn:BAAALgAECgQJBAAAAA==.',
Ko='Komojo:BAABLgAECn8rAAIIAAgJURHwdgCAAQAIAAgJURHwdgCAAQAAAA==.Koriggan:BAACLgAFFH8GAAIUAAMJrQ8pHwDcAAAUAAMJrQ8pHwDcAAAuAAQKfzUABBQACQnrErsTAAgCABQACQnrErsTAAgCAAYABgkqEHpVAGgBAAsAAQnpAGWbABQAAAAA.',
Kr='Krazzikz:BAAALgADCgYJBgAAAA==.Krea:BAABLgAECn84AAIHAAkJWyKVAgAEAwAHAAkJWyKVAgAEAwAAAA==.Krixx:BAAALgADCgEJAQAAAA==.Kroval:BAAALgAECgUJBgAAAA==.Krystagosa:BAABLgAECn85AAQnAAkJiRYaCQBYAgAnAAkJiRYaCQBYAgAdAAYJJg/OTgDyAAAeAAMJVArEGQCFAAAAAA==.',
Ku='Kuriuh:BAABLgAECn8mAAIMAAkJnRYUPADrAQAMAAkJnRYUPADrAQAAAA==.Kurtcobainn:BAAALgADCgkJCQAAAA==.',
Ky='Kyllea:BAAALgAECgcJBwABLgAECgkJEgAPAAAAAA==.',
La='Lang:BAABLgAECn87AAImAAkJ1x3ZAwCUAgAmAAkJ1x3ZAwCUAgAAAA==.Laveaux:BAAALgAECgEJAQAAAA==.',
Le='Legionslamm:BAAALgADCgUJBQAAAA==.Leonldas:BAAALgADCgEJAQAAAA==.',
Li='Lightsfaith:BAAALgADCgYJBgABLgAECgkJJgAjAFMLAA==.',
Lo='Lodix:BAAALgAFFAIJBAAAAA==.Loopey:BAAALgAECgcJEAABLgAFFAcJHAAWAAcUAA==.Lorethil:BAAALgAECgYJDAAAAA==.',
Lu='Luceriss:BAABLgAECn8gAAICAAkJJg/HGwC5AQACAAkJJg/HGwC5AQAAAA==.Luminous:BAAALgADCgcJCAABLgAECgkJJgAMAJ0WAA==.',
Ma='Maeroth:BAAALgADCgUJBQABLgAFFAgJFwAMAFULAA==.Magicboi:BAABLgAECn8aAAIKAAgJmQ4yfACAAQAKAAgJmQ4yfACAAQAAAA==.Magwar:BAACLgAFFH8SAAIQAAcJUxWXCADXAQAQAAcJUxWXCADXAQAuAAQKfzEAAhAACQlXIT8JAM4CABAACQlXIT8JAM4CAAAA.Maike:BAABLgAECn85AAMCAAkJohnuDwAvAgACAAkJIxTuDwAvAgATAAgJQBSrCAC+AQAAAA==.Marcelyne:BAAALgAECgYJCAABLgAECgkJJAAMAPYTAA==.Marothius:BAACLgAFFH8XAAQMAAgJVQtVKQChAQAMAAcJbgpVKQChAQAkAAEJvxAUFABWAAAaAAEJ3AL/LQA2AAAuAAQKfzMABAwACQlhHlokAE4CAAwACQlQHFokAE4CACQABgmMHBAXAJEBABoAAgnLGnAiAK4AAAAA.Martaug:BAACLgAFFH8FAAINAAIJsx0sVQCmAAANAAIJsx0sVQCmAAAuAAQKfyUAAg0ACQknH9QSALYCAA0ACQknH9QSALYCAAAA.Marune:BAAALgAECgkJDwAAAA==.Maurice:BAAALgADCgYJCwAAAA==.Maverage:BAABLgAECn84AAMQAAkJDCKeBwDlAgAQAAkJDCKeBwDlAgARAAYJ6xPsKwAcAQAAAA==.Mawg:BAAALgAECgYJBwAAAA==.Mayfair:BAABLgAECn8mAAMNAAkJpxRXLwD4AQANAAkJpxRXLwD4AQAlAAcJOBNSQwAmAQAAAA==.Mayia:BAAALgAECgcJBwAAAA==.',
Mb='Mbarnes:BAAALgAECgQJBwAAAA==.',
Me='Meaculpa:BAAALgAECgQJBAAAAA==.Melee:BAACLgAFFH9OAAIIAAkJaSZhAABgAwAIAAkJaSZhAABgAwAuAAQKfxYAAggACQmZJj0CALoDAAgACQmZJj0CALoDAAAA.',
Mi='Midnightfear:BAAALgADCgcJBwAAAA==.Mikeyy:BAAALgADCgMJAwAAAA==.Mimoza:BAAALgAECgYJCgAAAA==.Minibeer:BAAALgAECgYJEgAAAA==.Minimee:BAAALgAECgYJCwAAAA==.Miquella:BAACLgAFFH8IAAMEAAMJpgyiDQC5AAAEAAMJpgyiDQC5AAAFAAIJzgPqlABQAAAuAAQKfxcAAwQACQliGLgUAOsBAAQACAmWF7gUAOsBAAUAAgnsEEUdAHgAAAAA.Misohotramen:BAACLgAFFH8UAAIFAAUJQxsLPQAyAQAFAAUJQxsLPQAyAQAuAAQKfyQAAgUACQnQILUzACsCAAUACQnQILUzACsCAAAA.',
Mo='Moist:BAABLgAECn87AAIbAAkJaCM4AgAhAwAbAAkJaCM4AgAhAwAAAA==.Monkstrosity:BAAALgAFFAIJAwAAAA==.Moonlock:BAAALgADCgYJCgAAAA==.Moor:BAABLgAECn8aAAIiAAkJrwaoBwAvAQAiAAkJrwaoBwAvAQAAAA==.Mordakka:BAAALgAECgYJCQAAAA==.Morior:BAABLgAECn8+AAMMAAkJSht4IgBYAgAMAAkJSht4IgBYAgAkAAIJMBi0UQB5AAAAAA==.Motgustus:BAAALgAFFAEJAQAAAA==.',
Mu='Muirfire:BAAALgAECgUJBQAAAA==.Murrda:BAACLgAFFH8FAAIMAAIJ3BK1mQCRAAAMAAIJ3BK1mQCRAAAuAAQKfzcAAwwACQmpId0MAOYCAAwACQmpId0MAOYCABoAAQnTE+A5AEEAAAAA.Musk:BAAALgAECgIJBQABLgAECggJLwAKAOAWAA==.Muskrattsam:BAABLgAECn8vAAIKAAgJ4Ba3SAABAgAKAAgJ4Ba3SAABAgAAAA==.',
My='Myravia:BAABLgAECn8WAAIKAAcJrxAwkQCxAQAKAAcJrxAwkQCxAQAAAA==.Myrokos:BAABLgAECn9RAAIIAAkJ+SJJCgAVAwAIAAkJ+SJJCgAVAwAAAA==.Mysthicc:BAAALgADCgIJAgAAAA==.',
['Mó']='Mónónoke:BAAALgADCgMJAwAAAA==.',
['Mö']='Möokss:BAAALgADCgQJAgAAAA==.',
Na='Nailo:BAABLgAECn9WAAIbAAkJeBQfEADnAQAbAAkJeBQfEADnAQAAAA==.Nails:BAAALgAECgQJBgAAAA==.Nathanos:BAAALgAECggJCwAAAA==.',
Ne='Nepetala:BAAALgAECgYJBgABLgAFFAgJDwAdAIMOAA==.Nezar:BAAALgAFFAEJAwABLgAFFAEJBQAmAFcYAA==.',
Nh='Nhat:BAAALgAECgMJAwAAAA==.',
Ni='Niaah:BAAALgADCgYJAQABLgAECgkJFwABAL4cAA==.Niddy:BAACLgAFFH8VAAIKAAQJCBiYIABGAQAKAAQJCBiYIABGAQAuAAQKf04AAgoACQkbHKYnAHwCAAoACQkbHKYnAHwCAAAA.Nightshanda:BAAALgAECgMJBQABLgAECgkJEgAPAAAAAA==.Nisardela:BAAALgADCgMJAwAAAA==.',
No='Nobudy:BAACLgAFFH8gAAMhAAgJyRwIBQAzAgAhAAgJyRwIBQAzAgAjAAQJzAKiMADPAAAuAAQKfzEABCEACQm6JEgEABUDACEACQm6JEgEABUDACAABgnIFcYuAIgBACMAAgnNBOJZAC4AAAAA.Noel:BAABLgAECn86AAIgAAkJsBxTAQCcAgAgAAkJsBxTAQCcAgAAAA==.Nomsayin:BAACLgAFFH8GAAIMAAMJHQumiwCuAAAMAAMJHQumiwCuAAAuAAQKfzAAAgwACQkuGRYzAEACAAwACQkuGRYzAEACAAAA.Nonospot:BAABLgAECn8sAAMhAAkJmhfHEwAxAgAhAAkJmhfHEwAxAgAjAAEJvANJWgAuAAAAAA==.Noobuddy:BAAALgAECgUJCgABLgAFFAgJIAAhAMkcAA==.Noraboo:BAABLgAECn8jAAMiAAgJQRqjBAD7AQAiAAYJbxyjBAD7AQAKAAgJmRjUYQC8AQABLgAECgkJKwAVABsdAA==.Norannestra:BAAALgAECgYJDQAAAA==.Novalicious:BAAALgAECgEJAQAAAA==.Novasera:BAAALgAECgcJCAAAAA==.',
Nu='Nubmuffin:BAAALgADCgUJBQAAAA==.',
Nv='Nvied:BAABLgAECn8cAAMMAAkJpRTYRQDJAQAMAAgJpRTYRQDJAQAkAAEJAAD5cwAxAAAAAA==.',
Ny='Nyctt:BAABLgAECn8YAAMCAAkJ8BlNGQA6AgACAAkJUhhNGQA6AgATAAIJ5xdoFgCSAAAAAA==.Nystra:BAABLgAECn8WAAIMAAkJAhhzJgBEAgAMAAkJAhhzJgBEAgAAAA==.Nyzstra:BAABLgAECn8wAAIKAAkJXiLKGQC/AgAKAAkJXiLKGQC/AgAAAA==.',
['Nê']='Nêwt:BAACLgAFFH8SAAIKAAQJgg40OgDFAAAKAAQJgg40OgDFAAAuAAQKf0QAAgoACQkEICUHANIBAAoACQkEICUHANIBAAAA.',
['Nì']='Nìrvana:BAAALgAECgQJCwAAAA==.',
['Nú']='Núbmuffin:BAAALgAECgEJAgAAAA==.',
On='Onlybeams:BAABLgAECn8fAAIFAAkJQBsqIQBOAgAFAAkJQBsqIQBOAgAAAA==.',
Or='Orphu:BAAALgAECgEJAQAAAA==.',
Pa='Pallyplexity:BAAALgAFFAEJAQABLgAECgkJWwAOAIkmAA==.Palmiste:BAAALgAECgQJBgAAAA==.Pandad:BAAALgADCgEJAQABLgAECgkJIQAWADYYAA==.Pangoplexity:BAAALgADCgIJAgAAAA==.Parahsalin:BAAALgAECgEJAQABLgAECgYJEgAPAAAAAA==.Partyhard:BAAALgAECgEJAQAAAA==.Pastryblust:BAABLgAFFH8NAAIlAAgJUhJgDwAWAQAlAAgJUhJgDwAWAQAAAA==.Pastrydragon:BAACLgAFFH8LAAMdAAQJORbhEAD7AAAdAAQJORbhEAD7AAAeAAEJJxkoDQBLAAAuAAQKfzAAAx0ACAmrINUKAMgCAB0ACAmSHtUKAMgCAB4ABglYI5ULACICAAEuAAUUCAkNACUAUhIA.',
Ph='Phaeliea:BAAALgAECgUJBQAAAA==.',
Pi='Pistachio:BAABLgAECn8bAAIEAAYJOA4sNQDpAAAEAAYJOA4sNQDpAAAAAA==.Pitviper:BAABLgAECn8mAAITAAkJ4x7MAwBqAgATAAkJ4x7MAwBqAgAAAA==.',
Po='Pocketrokit:BAAALgAECgkJDAAAAA==.Pogaca:BAAALgAECgcJDgABLgAECggJFwAXAP8bAA==.Portabull:BAAALgADCgcJBwABLgAFFAEJAQAPAAAAAA==.Possess:BAABLgAECn8mAAIMAAcJVx3aRgDFAQAMAAcJVx3aRgDFAQAAAA==.Pownora:BAABLgAECn8rAAMVAAkJGx2wCwCHAgAVAAkJGx2wCwCHAgAoAAIJ/Q1YvAAxAAAAAA==.',
Ps='Psarchasm:BAABLgAECn8wAAIQAAkJlg06LgCYAQAQAAkJlg06LgCYAQAAAA==.',
Pu='Puck:BAAALgAECgEJAgAAAA==.Puffnstuff:BAAALgAECgUJBQAAAA==.Pugstar:BAAALgAECgMJAwAAAA==.',
Qe='Qel:BAAALgADCgYJCQAAAA==.',
Ra='Rai:BAABLgAECn87AAIGAAkJzSRiBgAuAwAGAAkJzSRiBgAuAwAAAA==.Rancidbeef:BAAALgAECgMJAwAAAA==.Rapha:BAABLgAECn8nAAIWAAkJNyJ9BQDpAgAWAAkJNyJ9BQDpAgAAAA==.Rayyzer:BAABLgAECn8eAAMCAAkJqCHmDABYAgACAAkJqCHmDABYAgATAAIJtBhsGgCWAAAAAA==.Razzu:BAAALgAECgMJAwABLgAFFAMJCgAUAPEXAA==.',
Re='Realrogue:BAAALgAECgYJCwABLgAECgkJWwAOAIkmAA==.Realtree:BAAALgAFFAMJBAAAAA==.Rema:BAAALgADCgQJBAAAAA==.Reyna:BAAALgADCgUJBQAAAA==.',
Ri='Riddles:BAACLgAFFH8FAAIbAAIJPQ1DGwBZAAAbAAIJPQ1DGwBZAAAuAAQKfx4AAxsACAnMHc0JAE0CABsACAnMHc0JAE0CABgAAQkWI4S1AFoAAAAA.Rincewind:BAAALgAECgEJAQAAAA==.',
Ro='Rossabella:BAABLgAECn9FAAMgAAkJahuRCwCtAgAgAAkJahuRCwCtAgAjAAgJ0w7HGwC4AQAAAA==.Rot:BAABLgAECn8nAAIfAAkJCSb1AgAWAwAfAAkJCSb1AgAWAwAAAA==.',
Ru='Rude:BAAALgAECgYJBgABLgAFFAcJFAAQAEoeAA==.Ruzala:BAAALgADCgEJAQAAAA==.',
Sa='Samsonn:BAAALgADCgQJBAAAAA==.Sanctity:BAAALgADCgYJCgAAAA==.Santino:BAACLgAFFH8PAAMYAAMJPQjiTACLAAAYAAMJPQjiTACLAAAbAAMJjgkOGwBaAAAuAAQKfx4AAhgACAlhGdIeAFACABgACAlhGdIeAFACAAEuAAUUBAkdAAoAJRUA.Saphlocket:BAAALgAECgYJEgAAAA==.Sathin:BAABLgAECn8yAAIFAAkJmwpbYQBmAQAFAAkJmwpbYQBmAQAAAA==.',
Sc='Scher:BAAALgADCgkJCwAAAA==.Scrungus:BAAALgADCgYJBgAAAA==.Scufalufagus:BAAALgAECgUJBQABLgAFFAgJFwAMAFULAA==.',
Se='Seetick:BAAALgAECgIJBAAAAA==.Sefekat:BAAALgAECgEJAQABLgAECgkJHwAFAEAbAA==.September:BAAALgAECgIJAgABLgAFFAUJEQAGABoVAA==.Sevatar:BAABLgAECn8nAAIEAAkJUg23HwB8AQAEAAkJUg23HwB8AQAAAA==.',
Sf='Sfcwarner:BAAALgAECgEJAgAAAA==.',
Sg='Sgtwarner:BAAALgAECgYJCwAAAA==.',
Sh='Shampooyou:BAABLgAECn83AAINAAgJtRG7PgCzAQANAAgJtRG7PgCzAQAAAA==.Shockakhan:BAAALgAECgkJDgAAAA==.Shocknstone:BAAALgADCgcJBwABLgAECgkJWwAOAIkmAA==.',
Si='Silentmamba:BAAALgAECgEJAQAAAA==.Sinistra:BAABLgAECn8ZAAMjAAgJ+g4sKQCKAQAjAAgJ+g4sKQCKAQAhAAIJyQ5THwAyAAAAAA==.',
Sk='Skelecopter:BAAALgADCgMJAwAAAA==.',
Sl='Slapshot:BAAALgAECggJCwABLgAECggJFwAXAP8bAA==.',
Sn='Snowflake:BAAALgADCgcJBwAAAA==.',
Sp='Spellsteal:BAABLgAECn8lAAIKAAkJuxiLOAA2AgAKAAkJuxiLOAA2AgABLgAFFAYJFgAOAOkLAA==.Spicynudz:BAAALgAECgEJAQAAAA==.Spring:BAACLgAFFH8RAAMGAAUJGhV6RAAkAQAGAAUJGhV6RAAkAQALAAEJpAAJLgA2AAAuAAQKfyUAAwYACQlfHQYwABwCAAYACQkjHQYwABwCAAsABgnTC/ZMAB0BAAAA.',
Ss='Ssgwarner:BAAALgAECgEJAQAAAA==.',
St='Stardel:BAAALgAECgYJDQAAAA==.Sting:BAABLgAECn8pAAIGAAgJ/xF4DQBkAQAGAAgJ/xF4DQBkAQAAAA==.Stormclaw:BAABLgAECn8zAAMYAAkJSx2fEQDDAgAYAAkJSx2fEQDDAgAXAAEJkBwqeQBUAAAAAA==.Stormcrash:BAAALgADCgYJBgABLgAECgkJJgAMAJ0WAA==.Stregoica:BAAALgADCgcJDgABLgAFFAgJFwAMAFULAA==.',
Su='Suhfering:BAAALgADCgYJBgABLgAECgkJHwAFAEAbAA==.Superbeef:BAAALgAECgEJAgAAAA==.Sushiiez:BAAALgADCgMJAwAAAA==.Suwo:BAAALgADCgIJAQAAAA==.',
Sy='Sychopath:BAAALgAECgYJEAAAAA==.Sykadelik:BAAALgAECgMJAwAAAA==.Syngoma:BAAALgADCgIJAgAAAA==.',
Ta='Tallron:BAACLgAFFH8eAAIYAAgJSRmgBwCFAgAYAAgJSRmgBwCFAgAuAAQKfy4AAxgACQmaJLcJAPcCABgACQmaJLcJAPcCABcABQmPFRlCAAUBAAAA.Tallsera:BAAALgADCgcJDQABLgAFFAgJHgAYAEkZAA==.Tallyfan:BAAALgADCgcJEwAAAA==.Tamedsloth:BAAALgAECgYJBgAAAA==.Tandraella:BAAALgAECgQJBQABLgAFFAQJBwABAI8ZAA==.Tanerella:BAAALgAECgEJAQAAAA==.Tanthalos:BAAALgAECgcJCQAAAA==.Taroquin:BAAALgADCgkJCgAAAA==.',
Te='Ternay:BAAALgADCgIJAQAAAA==.Teskhamen:BAAALgAFFAIJAwAAAA==.Tetamesh:BAAALgADCgQJBAAAAA==.',
Th='Theory:BAAALgAECgIJAgAAAA==.Theskabandit:BAAALgADCgcJEQAAAA==.Thrustruggle:BAAALgAECgMJAwAAAA==.',
Ti='Tiamot:BAAALgADCgUJCAAAAA==.Tinynutz:BAAALgAECgMJBAAAAA==.',
To='Toby:BAAALgAECgYJBgAAAA==.Tojikitoushi:BAACLgAFFH8HAAISAAMJJQ96CwB9AAASAAMJJQ96CwB9AAAuAAQKfzgAAhIACQnpIGkDANECABIACQnpIGkDANECAAAA.Tombs:BAAALgAFFAIJAgAAAA==.Tonsonger:BAAALgAECgUJCAAAAA==.Totenhammer:BAAALgAECgQJCwAAAA==.Totenplage:BAAALgAECgQJBAAAAA==.',
Tr='Trid:BAAALgAECggJCAAAAA==.Tristex:BAAALgAECgUJBQABLgAECggJFwAXAP8bAA==.',
Tu='Tuha:BAAALgAFFAIJAgAAAA==.',
Tw='Twergstronk:BAAALgADCgEJAQAAAA==.',
Ty='Tyrian:BAAALgAECgEJAQAAAA==.Tyrolia:BAAALgAECgMJAwAAAA==.',
Um='Umibozu:BAAALgAECgIJAgAAAA==.',
Un='Unoocho:BAAALgADCggJCAAAAA==.',
Ur='Urchak:BAAALgAECgYJBgAAAA==.',
Va='Valliya:BAABLgAFFH8IAAIIAAMJbwOvhgCmAAAIAAMJbwOvhgCmAAAAAA==.',
Ve='Velratha:BAABLgAECn8UAAIaAAgJtQ80DAB2AQAaAAgJtQ80DAB2AQAAAA==.Vesfu:BAAALgADCgEJAQAAAA==.Vesi:BAAALgADCgcJCgAAAA==.Vextt:BAABLgAECn8eAAMhAAgJDRjAKgB9AQAhAAcJRxvAKgB9AQAgAAIJeBiMawA7AAAAAA==.',
Vi='Vicsta:BAAALgAECgcJCgAAAA==.',
Vo='Voidrend:BAAALgAECgQJBwAAAA==.Voidwarner:BAAALgAECgQJBgAAAA==.Volight:BAAALgADCgYJCQAAAA==.Volke:BAABLgAECn8nAAIoAAkJMxbeHgAjAgAoAAkJMxbeHgAjAgAAAA==.Volmnk:BAAALgAECgUJDAAAAA==.Volq:BAAALgAECgEJAQAAAA==.Voltarix:BAAALgAECgYJCQAAAA==.Voodoopriest:BAABLgAECn8YAAIMAAcJMwRDpAAQAQAMAAcJMwRDpAAQAQAAAA==.Voyria:BAABLgAECn8xAAQYAAkJVwhKcADjAAAYAAgJ9QRKcADjAAAXAAYJiQWhVwCzAAAcAAIJwQLiVQAuAAAAAA==.',
Vs='Vs:BAAALgAECgYJBgAAAA==.',
Vy='Vynlenn:BAAALgADCgMJAwAAAA==.Vyskaar:BAAALgAECgEJAQAAAA==.Vyskar:BAAALgAECgUJDgAAAA==.Vyskary:BAAALgAECgEJBQAAAA==.',
Wa='Warm:BAACLgAFFH8ZAAIVAAgJsxpvAgBGAgAVAAgJsxpvAgBGAgAuAAQKfycAAhUACQkTImsIAPMCABUACQkTImsIAPMCAAAA.Warmlight:BAAALgAECgYJDAAAAA==.',
We='Weewu:BAAALgAECgQJBAABLgAECgYJBgAPAAAAAA==.Weeziveli:BAAALgAECgQJDQAAAA==.Weledish:BAACLgAFFH8mAAIKAAUJoSC2HgBTAQAKAAUJoSC2HgBTAQAuAAQKfy8AAgoACQnLHHAwAFcCAAoACQnLHHAwAFcCAAAA.Weleron:BAAALgAFFAIJAgAAAA==.',
Wh='Whystler:BAAALgAECgIJAgAAAA==.',
Wi='Wienercat:BAABLgAECn8hAAIYAAcJ6STyDgDeAgAYAAcJ6STyDgDeAgABLgAECggJJwANAHcjAA==.Wimol:BAAALgAECgYJDAABLgAECgkJKwAVABsdAA==.Windmacedu:BAAALgAECgYJCgAAAA==.',
Wo='Wowdra:BAABLgAECn8VAAIKAAcJrRIbDQBaAQAKAAcJrRIbDQBaAQAAAA==.',
Xt='Xtreeme:BAAALgAECgIJAgAAAA==.',
Ya='Yael:BAABLgAECn80AAIFAAkJeB7HGgB0AgAFAAkJeB7HGgB0AgAAAA==.Yama:BAAALgAECgcJEAAAAA==.',
Za='Zamrazac:BAAALgAECgUJCAABLgAECgkJMwAYAEsdAA==.Zarewien:BAABLgAECn8uAAIgAAkJ6AovLABoAQAgAAkJ6AovLABoAQAAAA==.',
Ze='Zeddicus:BAAALgAECgMJAwAAAA==.',
Zi='Ziddles:BAABLgAECn8cAAIUAAkJGxvZEwAGAgAUAAkJGxvZEwAGAgAAAA==.',
Zo='Zomgdk:BAAALgAECgEJAgABLgAECgkJRQAWAPsfAA==.Zomgmonk:BAABLgAECn9FAAIWAAkJ+x9ABQDtAgAWAAkJ+x9ABQDtAgAAAA==.Zomgzilla:BAAALgAECggJAQABLgAECgkJRQAWAPsfAA==.Zorep:BAAALgAECgEJAQAAAA==.Zorien:BAAALgAECgQJBAAAAA==.',
Zu='Zuraq:BAAALgAECgEJBgAAAA==.Zurisdad:BAABLgAECn83AAIWAAkJ8B7iBwC2AgAWAAkJ8B7iBwC2AgABLgAFFAUJFAAKAMYXAA==.Zurishmi:BAACLgAFFH8cAAINAAUJ/h5lBQB3AQANAAUJ/h5lBQB3AQAuAAQKfzMAAg0ACQk6JpcBALgDAA0ACQk6JpcBALgDAAAA.',
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
