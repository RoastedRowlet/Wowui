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

local lookup = {'Paladin-Holy','DemonHunter-Devourer','Rogue-Subtlety','Rogue-Outlaw','DemonHunter-Havoc','Hunter-BeastMastery','Paladin-Protection','Paladin-Retribution','DeathKnight-Unholy','Mage-Frost','Hunter-Marksmanship','Warlock-Demonology','Priest-Discipline','Unknown-Unknown','Warrior-Fury','Warrior-Arms','Warrior-Protection','Shaman-Enhancement','Rogue-Assassination','Hunter-Survival','Monk-Windwalker','Monk-Brewmaster','Druid-Balance','Druid-Restoration','DeathKnight-Frost','Warlock-Affliction','Druid-Guardian','Druid-Feral','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Blood','Priest-Holy','Priest-Shadow','Mage-Arcane','Warlock-Destruction','Shaman-Restoration','Shaman-Elemental','DemonHunter-Vengeance','Evoker-Preservation','Monk-Mistweaver',}
local provider = {region='US',realm='Nathrezim',name='US',type='weekly',zone=46,date='2026-06-20',data={Ab='Abysm:BAAALgADCgkJDwAAAA==.',
Ac='Achillios:BAAALgADCgMJAwABLgAFFAQJBgABAFUTAA==.',
Ad='Adorabull:BAAALgAECgUJBwABLgAECgkJIQACAKsdAA==.',
Ae='Aemun:BAACLgAFFH8KAAIDAAMJcxOtJwDrAAADAAMJcxOtJwDrAAAuAAQKf00AAwMACQkzHg8IAKYCAAMACQkzHg8IAKYCAAQABgmUCbAIAPYAAAAA.',
Ag='Aggfu:BAAALgADCgYJBgAAAA==.',
Ai='Ainek:BAAALgADCgEJAQAAAA==.',
Ak='Akeeli:BAAALgADCgQJBAAAAA==.Akelita:BAABLgAECn8hAAMFAAYJrxiJJQBNAQAFAAYJrxiJJQBNAQACAAUJcAgUzQCXAAAAAA==.',
Al='Alailea:BAABLgAECn9DAAIGAAkJMxQXPgDpAQAGAAkJMxQXPgDpAQAAAA==.Aloepaw:BAAALgAECgEJAQAAAA==.Alragnar:BAAALgAECgIJAgAAAA==.Alwysafkable:BAABLgAFFH8HAAIHAAMJzBgAAQCbAAAHAAMJzBgAAQCbAAAAAA==.',
Am='Amageadin:BAAALgADCgkJCQAAAA==.Amazadin:BAACLgAFFH8GAAIBAAQJVRMPJwDqAAABAAQJVRMPJwDqAAAuAAQKfxkAAwEACAkpHO8bADUCAAEACAkpHO8bADUCAAgAAgncEvM0AXkAAAAA.Amazashock:BAAALgAECgUJDQABLgAFFAQJBgABAFUTAA==.',
An='Andiwin:BAABLgAECn8ZAAIJAAgJ9Q90agCRAQAJAAgJ9Q90agCRAQAAAA==.Andurthil:BAABLgAECn8oAAIKAAgJUw1CjwBZAQAKAAgJUw1CjwBZAQAAAA==.Anzul:BAAALgAECgUJBgAAAA==.',
Ar='Archive:BAAALgAECgkJCwAAAA==.Artistic:BAABLgAECn8cAAIGAAgJeBl2QQDeAQAGAAgJeBl2QQDeAQAAAA==.Arubion:BAABLgAECn8ZAAIIAAgJSxGjYQCtAQAIAAgJSxGjYQCtAQAAAA==.Arylanna:BAAALgAECgYJDQAAAA==.',
As='Asure:BAABLgAECn8tAAMGAAkJ/heTKgAzAgAGAAkJ/heTKgAzAgALAAYJTgfdTwAPAQAAAA==.',
Az='Azerith:BAAALgAECgYJDwAAAA==.',
Ba='Badmorda:BAAALgADCgEJAQAAAA==.',
Be='Bearforceone:BAAALgADCgMJAwAAAA==.',
Bi='Bipolar:BAAALgADCgEJAQAAAA==.',
Bl='Blackheart:BAABLgAECn8bAAIMAAgJnBjCLQBWAgAMAAgJnBjCLQBWAgAAAA==.Blodreina:BAAALgADCgUJCQAAAA==.Bloodarchon:BAABLgAECn8rAAMIAAkJYBYENwAlAgAIAAkJYBYENwAlAgAHAAYJnQkTMQCiAAAAAA==.Bloodtemplar:BAABLgAECn80AAIIAAkJyhq6JAByAgAIAAkJyhq6JAByAgAAAA==.',
Bo='Bombs:BAABLgAECn8UAAIKAAQJhRG60gDuAAAKAAQJhRG60gDuAAABLgAFFAQJBwANADEEAA==.Bonesy:BAAALgAECgYJBgAAAA==.Bouren:BAAALgAECgEJAQAAAA==.',
Br='Bravia:BAAALgADCgUJBwAAAA==.Brewdogg:BAAALgADCgcJBwAAAA==.Brokasa:BAAALgADCgIJAgAAAA==.Brutalitops:BAAALgADCgMJAwAAAA==.Brutusdabull:BAAALgAECgYJBgAAAA==.Brônze:BAAALgADCgQJBAAAAA==.',
Bu='Burdomew:BAAALgADCgEJAQAAAA==.',
Ca='Cadbury:BAAALgADCgIJAgABLgAECgUJCAAOAAAAAA==.Canan:BAAALgAECgUJBgAAAA==.Canansbrew:BAAALgAECgEJAQAAAA==.Canestoast:BAAALgAECgEJAQAAAA==.Casmina:BAABLgAECn8WAAIPAAkJ7xlRIQBJAgAPAAkJ7xlRIQBJAgAAAA==.Castiell:BAAALgADCgUJBgAAAA==.Catalystic:BAAALgADCgEJAQAAAA==.Catd:BAAALgAECgEJAwAAAA==.',
Ce='Celum:BAABLgAECn8eAAIJAAcJnwcJvQACAQAJAAcJnwcJvQACAQAAAA==.Ceola:BAABLgAECn8iAAMQAAcJ+Q+CNAD0AAARAAcJSwywJgD9AAAQAAUJVw6CNAD0AAAAAA==.',
Ch='Chamming:BAAALgADCgIJAgAAAA==.Chaquén:BAACLgAFFH8IAAISAAMJVBRqDgDZAAASAAMJVBRqDgDZAAAuAAQKfyIAAhIACQn6GdQHAEwCABIACQn6GdQHAEwCAAAA.Charizard:BAAALgAECgEJAQAAAA==.Charmander:BAABLgAECn8fAAQTAAYJshfzCgCAAQATAAYJshfzCgCAAQADAAQJUgl7SACWAAAEAAMJ2wRBGwB0AAAAAA==.Chaw:BAACLgAFFH8bAAMUAAgJmh3HAQBDAgAUAAgJXhjHAQBDAgAGAAEJcCamIQBdAAAuAAQKfzIABBQACQnuJPgDAPICABQACQnsJPgDAPICAAsABwnWHy0iABQCAAYABAk3I1BIAJEBAAAA.Chenkenichi:BAACLgAFFH8HAAIVAAMJhgYWLQCWAAAVAAMJhgYWLQCWAAAuAAQKfzEAAxUACQmsD9AAADgBABUACQmsD9AAADgBABYABQkoAqtoAJ8AAAAA.Chergar:BAACLgAFFH8MAAIRAAUJkhvaEwAEAQARAAUJkhvaEwAEAQAuAAQKfx4AAhEACQkVIkwFAOkCABEACQkVIkwFAOkCAAAA.Chskie:BAAALgADCgUJBQAAAA==.Chsky:BAAALgADCgUJBQAAAA==.Chuiyi:BAAALgAECgEJAgAAAA==.',
Ci='Cinny:BAABLgAECn9GAAIGAAkJchyQGwCAAgAGAAkJchyQGwCAAgAAAA==.Cinnyrolls:BAABLgAECn8XAAMXAAgJ/xvxGwDqAQAXAAgJ/xvxGwDqAQAYAAQJtBBhhwDHAAAAAA==.Cityairlines:BAABLgAECn8nAAIZAAkJuRSUDACuAQAZAAkJuRSUDACuAQAAAA==.',
Cl='Clare:BAAALgAECgYJCQAAAA==.',
Cm='Cmoneyy:BAAALgAECgYJBwAAAA==.',
Co='Cogrolls:BAAALgAECggJCQAAAA==.Cooldukenuke:BAACLgAFFH8KAAIBAAMJqRf4DwDaAAABAAMJqRf4DwDaAAAuAAQKfycAAgEACQmjHDoTAHkCAAEACQmjHDoTAHkCAAAA.',
Cr='Creepychalk:BAABLgAECn8eAAMaAAgJRA6+DgBwAQAaAAgJRA6+DgBwAQAMAAEJsAHZZAEcAAAAAA==.Criticize:BAABLgAECn8nAAIIAAgJ1gw/oAA3AQAIAAgJ1gw/oAA3AQAAAA==.',
Cs='Csor:BAAALgAECgMJAwAAAA==.Csorb:BAABLgAECn8xAAMbAAkJ8SDtBADEAgAbAAkJviDtBADEAgAcAAEJySV5OwBrAAAAAA==.Csoren:BAAALgAECgEJAQAAAA==.Csoro:BAAALgADCggJCAAAAA==.',
Cu='Cultivation:BAAALgAECgUJCAAAAA==.Cursedcanfly:BAACLgAFFH8YAAIdAAcJ6BzNDwAGAgAdAAcJ6BzNDwAGAgAuAAQKfzMAAx0ACQnjJWYCAFYDAB0ACQnjJWYCAFYDAB4ABQnaFG8iABcBAAAA.',
Cw='Cw:BAAALgAECgEJAQAAAA==.',
De='Deathdogg:BAACLgAFFH8VAAMJAAUJxxm6ZwApAQAJAAQJxxm6ZwApAQAfAAEJAACzVwAAAAAuAAQKfykAAgkACQlPIL01ACgCAAkACQlPIL01ACgCAAAA.Dejavu:BAACLgAFFH8aAAIWAAYJrBOtFwBlAQAWAAYJrBOtFwBlAQAuAAQKfykAAhYACQlAHTIbAMsBABYACQlAHTIbAMsBAAAA.Demivoi:BAAALgAECgYJBwAAAA==.Demona:BAAALgAECgEJAQAAAA==.Deppthcharge:BAAALgAECgYJDwAAAA==.Desdemona:BAAALgAECgcJDAAAAA==.Devimon:BAAALgADCgEJAQAAAA==.Devoi:BAAALgADCgEJAQAAAA==.',
Di='Dismonk:BAAALgAECgIJAgAAAA==.Distotem:BAAALgAECgEJAQABLgAECgIJAgAOAAAAAA==.',
Do='Donrain:BAAALgAECgQJBAAAAA==.Dooghammer:BAABLgAECn8ZAAISAAkJQxrzCQAcAgASAAkJQxrzCQAcAgAAAA==.',
Dr='Dragussy:BAAALgADCgcJDQABLgAECgkJUAARAIImAA==.Drakkana:BAAALgADCgYJBgAAAA==.',
Du='Dunkhan:BAAALgAECgEJAQABLgAECgYJDAAOAAAAAA==.Duplexity:BAABLgAECn9QAAMRAAkJgiZTAACDAwARAAkJgiZTAACDAwAPAAEJuCFhhwBkAAAAAA==.',
Dw='Dwalin:BAAALgAECgMJCQABLgAECgkJGQASAEMaAA==.',
Ea='Eatmoorchikn:BAAALgAECgcJDAAAAA==.',
Ec='Ecko:BAAALgAECgEJAQAAAA==.',
Ed='Edolah:BAAALgAECgEJAQAAAA==.',
Eg='Egohakai:BAACLgAFFH8RAAIIAAUJrx1oQAAqAQAIAAUJrx1oQAAqAQAuAAQKfzAAAggACQkUJbgIACQDAAgACQkUJbgIACQDAAAA.',
El='Eloi:BAABLgAECn8WAAMgAAgJbyCrCQDNAgAgAAgJbyCrCQDNAgAhAAEJUhNTgQA6AAABLgAECgkJMwAYAEsdAA==.',
Em='Emieretta:BAABLgAECn88AAIJAAkJXRgNNgAmAgAJAAkJXRgNNgAmAgAAAA==.',
Eq='Eqdk:BAABLgAECn8hAAIJAAkJoxTZRwDqAQAJAAkJoxTZRwDqAQAAAA==.',
Er='Erret:BAACLgAFFH8UAAIKAAUJxheUXwAiAQAKAAUJxheUXwAiAQAuAAQKfzIAAwoACQlwI1QMABYDAAoACQlwI1QMABYDACIAAQngGVMUAEkAAAAA.',
Ey='Eyrie:BAAALgADCgYJBgAAAA==.',
Ez='Ezinder:BAABLgAECn8lAAIeAAcJfgpbAAAIAQAeAAcJfgpbAAAIAQAAAA==.',
Fa='Fabius:BAAALgADCgYJBgAAAA==.Faemos:BAAALgAECgkJCAAAAA==.Faience:BAABLgAECn8nAAIZAAkJMARYHgDaAAAZAAkJMARYHgDaAAAAAA==.Falorina:BAABLgAECn8zAAMFAAkJ5iNYAgBCAwAFAAkJ5iNYAgBCAwACAAEJAwXh6wAnAAAAAA==.Fathernature:BAACLgAFFH8JAAIXAAQJphB/JAAEAQAXAAQJphB/JAAEAQAuAAQKfx0AAxcACQknGd4oALgBABcACQknGd4oALgBABwAAQl5Bfw4ACUAAAAA.Fauna:BAAALgADCgMJAwAAAA==.Fazeup:BAAALgAECgcJBgAAAA==.',
Fe='Feldra:BAABLgAECn9EAAICAAkJQiLZBgAfAwACAAkJQiLZBgAfAwAAAA==.Felfaith:BAAALgAECgIJAgAAAA==.Fester:BAAALgADCgUJBQABLgAECgkJJgAMAJ0WAA==.',
Fi='Fightforbeer:BAAALgAECgEJAQAAAA==.Finnin:BAABLgAECn8jAAMPAAkJCSR1CwCwAgAPAAkJCSR1CwCwAgAQAAEJ0gZ8SAAkAAAAAA==.',
Fo='Food:BAABLgAECn8mAAIGAAkJoRgrIQA/AgAGAAkJoRgrIQA/AgAAAA==.Formidabull:BAAALgAECgEJAQABLgAECgkJIQACAKsdAA==.Foxdiez:BAAALgAECggJEQAAAA==.',
Fr='Fredde:BAAALgAECgEJAQAAAA==.Freidafondle:BAAALgAECgYJEgAAAA==.Frostbite:BAAALgAECgcJCwAAAA==.Frozenfaith:BAABLgAECn8mAAMNAAkJUwuwMABaAQANAAgJ1guwMABaAQAgAAMJMgQBZQBNAAAAAA==.',
Ft='Fthemeta:BAAALgADCgIJAgAAAA==.',
Fu='Fulci:BAAALgADCgUJBQAAAA==.Furioushealz:BAABLgAECn8nAAIIAAkJpxkBPwAKAgAIAAkJpxkBPwAKAgAAAA==.Furiouswind:BAAALgADCgEJAQAAAA==.',
Ga='Gardrius:BAAALgADCgYJBwAAAA==.',
Gh='Ghettomike:BAABLgAECn8pAAIJAAkJAB51NQApAgAJAAkJAB51NQApAgAAAA==.Ghoulbane:BAAALgADCgYJCgAAAA==.',
Gi='Gibbits:BAAALgAECgcJCQAAAA==.Giranimo:BAABLgAECn8uAAIGAAkJoRQ1MAAbAgAGAAkJoRQ1MAAbAgAAAA==.',
Gl='Glabados:BAAALgAECgIJAwABLgAECgkJJwAWADciAA==.Glossy:BAACLgAFFH8gAAMDAAcJch7mBwArAgADAAcJch7mBwArAgAEAAMJ4hDCDACUAAAuAAQKfzIABAMACQmEJrkBAFMDAAMACQmEJrkBAFMDABMAAgkNHzAUALsAAAQAAgmEIaYVALgAAAAA.Glossycumbus:BAAALgADCgYJBgABLgAFFAcJIAADAHIeAA==.Glossydh:BAAALgAECgYJBgABLgAFFAcJIAADAHIeAA==.Glossydk:BAAALgAECgQJBQABLgAFFAcJIAADAHIeAA==.Glossylock:BAAALgADCgcJDQABLgAFFAcJIAADAHIeAA==.',
Go='Golbigold:BAAALgAECgEJAQAAAA==.Goopy:BAAALgAECgMJAwABLgAECgYJBgAOAAAAAA==.Gorl:BAAALgAECgEJAQAAAA==.',
Gr='Grayhoff:BAABLgAECn8cAAIPAAkJkAsYMQCIAQAPAAkJkAsYMQCIAQAAAA==.Greathoof:BAAALgADCgMJAwAAAA==.Grewsom:BAACLgAFFH8XAAIIAAUJvhyzFQC+AQAIAAUJvhyzFQC+AQAuAAQKfywAAwgACAniJWMJAEYDAAgACAniJWMJAEYDAAcABQnzIOAWAGoBAAAA.',
Gu='Gulmok:BAAALgADCgUJBQAAAA==.Guwugga:BAABLgAECn8eAAIjAAcJXBDFEQAsAQAjAAcJXBDFEQAsAQAAAA==.',
Ha='Halîk:BAABLgAECn8XAAIBAAkJvhwJLADXAQABAAkJvhwJLADXAQAAAA==.Haraka:BAAALgAECgMJBAAAAA==.Harmshock:BAABLgAECn89AAISAAkJhCTCAgDpAgASAAkJhCTCAgDpAgAAAA==.Hathina:BAACLgAFFH8UAAMPAAcJSh4eCgC/AQAPAAYJcyIeCgC/AQAQAAEJfAmIQABIAAAuAAQKfzMAAw8ACQnTJlYBAG8DAA8ACQnTJlYBAG8DABAAAwmCHykeAP4AAAAA.',
He='Heket:BAABLgAECn8wAAIIAAgJtwgqswAaAQAIAAgJtwgqswAaAQAAAA==.Hektric:BAAALgAECgMJAwAAAA==.Helpinghandz:BAAALgAECgYJBgABLgAFFAYJGAAPAKEZAA==.',
Hi='Highdra:BAAALgAECgYJEwAAAA==.Hill:BAABLgAECn8oAAIGAAkJhR/7FgCAAgAGAAkJhR/7FgCAAgAAAA==.Hive:BAABLgAECn8wAAIPAAkJThjBFQBBAgAPAAkJThjBFQBBAgAAAA==.',
Ho='Holygem:BAAALgAECgYJCgAAAA==.Holypower:BAAALgADCgcJDQAAAA==.Hotdogwater:BAABLgAECn8nAAMkAAgJdyPoCgAJAwAkAAgJdyPoCgAJAwAlAAQJ5gmkfAB6AAAAAA==.',
Hu='Husentar:BAABLgAECn87AAIKAAkJ8CCSFQDYAgAKAAkJ8CCSFQDYAgAAAA==.Huuhablo:BAABLgAECn9AAAICAAkJjRzuGAB/AgACAAkJjRzuGAB/AgAAAA==.',
Ic='Icaron:BAAALgAECgcJDwAAAA==.',
Ig='Igothots:BAAALgAECgUJCgAAAA==.',
Il='Illuminottey:BAABLgAECn8UAAIIAAkJmQ+UlQBJAQAIAAkJmQ+UlQBJAQAAAA==.',
In='Inferium:BAAALgADCgYJBgABLgAFFAQJDwAOAAAAAA==.Infernom:BAAALgADCgMJAwABLgAFFAQJDwAOAAAAAA==.Insatiabull:BAABLgAECn8hAAMCAAkJqx2+EgDqAgACAAgJ7x6+EgDqAgAFAAEJyxSbZQBCAAAAAA==.',
Io='Iolchsk:BAAALgAECgQJDAAAAA==.',
Is='Ishaa:BAAALgAECgYJCgAAAA==.',
Ja='Jacksof:BAABLgAECn8UAAMhAAYJ7gX5XgCcAAAhAAYJ7gX5XgCcAAANAAQJOQTcbABSAAAAAA==.Jackstands:BAABLgAECn9WAAMkAAkJmSEBBwBAAwAkAAkJmSEBBwBAAwASAAgJgAUnHQAUAQAAAA==.Jagerin:BAAALgAECgYJCwABLgAECgkJJwAWADciAA==.January:BAAALgAECgYJCAABLgAFFAUJEQAGABoVAA==.',
Je='Jeromy:BAAALgAECgEJAQAAAA==.Jesse:BAAALgADCgIJAgAAAA==.',
Ji='Jiffi:BAABLgAECn8ZAAImAAgJyRrwBQA8AgAmAAgJyRrwBQA8AgAAAA==.Jinksy:BAAALgAECgYJEAAAAA==.',
Jm='Jme:BAAALgAECgcJCQAAAA==.',
Jr='Jredz:BAAALgADCgEJAQAAAA==.',
Ju='Juanwick:BAAALgADCgQJBAAAAA==.Jubag:BAAALgADCgIJAgAAAA==.Jumpercables:BAAALgAECgEJBAAAAA==.Junn:BAABLgAECn8nAAIlAAkJmBPWJgC1AQAlAAkJmBPWJgC1AQAAAA==.Justiciar:BAAALgAECgEJAQAAAA==.',
['Já']='Jánuary:BAAALgAECgUJBQAAAA==.',
Ka='Kahayman:BAACLgAFFH8RAAIKAAMJGBGFfgDaAAAKAAMJGBGFfgDaAAAuAAQKfzIAAgoACQnBGQItAGUCAAoACQnBGQItAGUCAAAA.Kamacha:BAAALgAECgMJBgAAAA==.Kamaldren:BAAALgAECgEJAQAAAA==.Karellen:BAABLgAECn8UAAMeAAgJTgyFCwBdAQAeAAgJTgyFCwBdAQAdAAUJlAT8cwCAAAAAAA==.Kathren:BAAALgAECgYJBwAAAA==.',
Kh='Khathani:BAABLgAECn8ZAAMGAAYJTxxSVwCeAQAGAAYJTxxSVwCeAQALAAQJHQtjIQCmAAAAAA==.',
Ki='Kieran:BAAALgAECgMJAwAAAA==.Kirara:BAAALgAECgMJAwAAAA==.',
Kn='Knobgoblinn:BAAALgAECgQJBAAAAA==.',
Ko='Komojo:BAABLgAECn8rAAIIAAgJURHydgCAAQAIAAgJURHydgCAAQAAAA==.Koriggan:BAACLgAFFH8GAAIUAAMJrQ8pHwDcAAAUAAMJrQ8pHwDcAAAuAAQKfzUABBQACQnrEr0TAAgCABQACQnrEr0TAAgCAAYABgkqEHpVAGgBAAsAAQnpAGWbABQAAAAA.',
Kr='Krea:BAABLgAECn83AAIHAAkJWyKVAgAEAwAHAAkJWyKVAgAEAwAAAA==.Krixx:BAAALgADCgEJAQAAAA==.Kroval:BAAALgAECgUJBgAAAA==.Krystagosa:BAABLgAECn85AAQnAAkJiRYaCQBYAgAnAAkJiRYaCQBYAgAdAAYJJg/OTgDyAAAeAAMJVArEGQCFAAAAAA==.',
Ku='Kuriuh:BAABLgAECn8mAAIMAAkJnRYSPADrAQAMAAkJnRYSPADrAQAAAA==.Kurtcobainn:BAAALgADCgkJCQAAAA==.',
Ky='Kyllea:BAAALgADCgcJBwABLgAECggJDQAOAAAAAA==.',
La='Lang:BAABLgAECn87AAImAAkJ1x3ZAwCUAgAmAAkJ1x3ZAwCUAgAAAA==.',
Le='Legionslamm:BAAALgADCgUJBQAAAA==.Leonldas:BAAALgADCgEJAQAAAA==.',
Li='Lightsfaith:BAAALgADCgYJBgABLgAECgkJJgANAFMLAA==.',
Lo='Lodix:BAAALgAFFAIJBAAAAA==.Loopey:BAAALgAECgcJEAABLgAFFAYJGgAWAKwTAA==.Lorethil:BAAALgAECgYJDAAAAA==.',
Lu='Luceriss:BAABLgAECn8fAAIDAAkJtA7GGwC5AQADAAkJtA7GGwC5AQAAAA==.Luminous:BAAALgADCgcJCAABLgAECgkJJgAMAJ0WAA==.',
Ma='Maeroth:BAAALgADCgUJBQABLgAFFAgJFwAMAFULAA==.Magicboi:BAABLgAECn8aAAIKAAgJmQ40fACAAQAKAAgJmQ40fACAAQAAAA==.Magwar:BAACLgAFFH8SAAIPAAcJUxWkCADXAQAPAAcJUxWkCADXAQAuAAQKfzEAAg8ACQlXIT0JAM4CAA8ACQlXIT0JAM4CAAAA.Maike:BAABLgAECn84AAMDAAkJdxnuDwAvAgADAAkJ+BPuDwAvAgATAAgJQBSqCAC+AQAAAA==.Marcelyne:BAAALgAECgYJCAABLgAECgkJJAAMAPYTAA==.Marothius:BAACLgAFFH8XAAQMAAgJVQt9KQChAQAMAAcJbgp9KQChAQAjAAEJvxAUFABWAAAaAAEJ3AL8LQA2AAAuAAQKfzMABAwACQlhHlkkAE4CAAwACQlQHFkkAE4CACMABgmMHBAXAJEBABoAAgnLGnIiAK4AAAAA.Martaug:BAABLgAECn8lAAIkAAkJJx/UEgC2AgAkAAkJJx/UEgC2AgAAAA==.Marune:BAAALgAECgkJDwAAAA==.Maurice:BAAALgADCgYJCwAAAA==.Maverage:BAABLgAECn84AAMPAAkJDCKdBwDlAgAPAAkJDCKdBwDlAgAQAAYJ6xPrKwAcAQAAAA==.Mawg:BAAALgAECgYJBwAAAA==.Mayfair:BAABLgAECn8lAAMkAAkJmhVVLwD4AQAkAAgJ2RNVLwD4AQAlAAcJOBNQQwAmAQAAAA==.Mayia:BAAALgAECgcJBwAAAA==.',
Mb='Mbarnes:BAAALgAECgQJBwAAAA==.',
Me='Melee:BAACLgAFFH9CAAIIAAkJKiVhAABgAwAIAAkJKiVhAABgAwAuAAQKfxYAAggACQmZJj0CALoDAAgACQmZJj0CALoDAAAA.',
Mi='Midnightfear:BAAALgADCgcJBwAAAA==.Mikeyy:BAAALgADCgMJAwAAAA==.Mimoza:BAAALgAECgYJCgAAAA==.Minibeer:BAAALgAECgYJEgAAAA==.Minimee:BAAALgAECgYJCwAAAA==.Miquella:BAABLgAECn8VAAMFAAgJ9Ra5FADrAQAFAAgJ9Ra5FADrAQACAAEJ3wMcDgAjAAAAAA==.Misohotramen:BAACLgAFFH8UAAICAAUJQxsXPQAyAQACAAUJQxsXPQAyAQAuAAQKfyQAAgIACQnQILUzACsCAAIACQnQILUzACsCAAAA.',
Mo='Moist:BAABLgAECn87AAIbAAkJaCM4AgAhAwAbAAkJaCM4AgAhAwAAAA==.Monkstrosity:BAAALgAECgMJAwAAAA==.Moonlock:BAAALgADCgYJCgAAAA==.Moor:BAABLgAECn8aAAIiAAkJrwaoBwAvAQAiAAkJrwaoBwAvAQAAAA==.Mordakka:BAAALgAECgYJCQAAAA==.Morior:BAABLgAECn8+AAMMAAkJSht2IgBYAgAMAAkJSht2IgBYAgAjAAIJMBi0UQB5AAAAAA==.Motgustus:BAAALgAFFAEJAQAAAA==.',
Mu='Muirfire:BAAALgADCgYJBgAAAA==.Murrda:BAACLgAFFH8FAAIMAAIJ3BLJmQCRAAAMAAIJ3BLJmQCRAAAuAAQKfzcAAwwACQmpId0MAOYCAAwACQmpId0MAOYCABoAAQnTE+A5AEEAAAAA.Musk:BAAALgAECgIJBQABLgAECggJLwAKAOAWAA==.Muskrattsam:BAABLgAECn8vAAIKAAgJ4Ba6SAABAgAKAAgJ4Ba6SAABAgAAAA==.',
My='Myravia:BAABLgAECn8WAAIKAAcJrxAwkQCxAQAKAAcJrxAwkQCxAQAAAA==.Myrokos:BAABLgAECn9RAAIIAAkJ+SJICgAVAwAIAAkJ+SJICgAVAwAAAA==.Mysthicc:BAAALgADCgIJAgAAAA==.',
['Mó']='Mónónoke:BAAALgADCgMJAwAAAA==.',
['Mö']='Möokss:BAAALgADCgQJAgAAAA==.',
Na='Nailo:BAABLgAECn9WAAIbAAkJeBQgEADnAQAbAAkJeBQgEADnAQAAAA==.Nails:BAAALgAECgQJBgAAAA==.Nathanos:BAAALgAECggJCwAAAA==.',
Ne='Nepetala:BAAALgAECgYJBgABLgAFFAcJDQAdAJgOAA==.Nezar:BAAALgAFFAEJAwABLgAFFAEJBQAmAFcYAA==.',
Nh='Nhat:BAAALgAECgMJAwAAAA==.',
Ni='Niaah:BAAALgADCgYJAQABLgAECgkJFwABAL4cAA==.Niddy:BAACLgAFFH8GAAIKAAMJtRCOfwDYAAAKAAMJtRCOfwDYAAAuAAQKf0kAAgoACQnsGqknAHwCAAoACQnsGqknAHwCAAAA.Nisardela:BAAALgADCgMJAwAAAA==.',
No='Nobudy:BAACLgAFFH8gAAMhAAgJyRwJBQAzAgAhAAgJyRwJBQAzAgANAAQJzAKnMADPAAAuAAQKfzEABCEACQm6JEkEABUDACEACQm6JEkEABUDACAABgnIFcYuAIgBAA0AAgnNBOJZAC4AAAAA.Noel:BAABLgAECn8rAAIgAAcJ1RhQHgDSAQAgAAcJ1RhQHgDSAQAAAA==.Nomsayin:BAACLgAFFH8GAAIMAAMJHQu6iwCuAAAMAAMJHQu6iwCuAAAuAAQKfzAAAgwACQkuGRYzAEACAAwACQkuGRYzAEACAAAA.Nonospot:BAABLgAECn8sAAMhAAkJmhfIEwAxAgAhAAkJmhfIEwAxAgANAAEJvANJWgAuAAAAAA==.Noobuddy:BAAALgAECgUJCgABLgAFFAgJIAAhAMkcAA==.Noraboo:BAABLgAECn8jAAMiAAgJQRqjBAD7AQAiAAYJbxyjBAD7AQAKAAgJmRjUYQC8AQABLgAECgkJKwAVABsdAA==.Norannestra:BAAALgAECgYJDQAAAA==.Novalicious:BAAALgADCgIJAgAAAA==.Novasera:BAAALgAECgcJCAAAAA==.',
Nu='Nubmuffin:BAAALgADCgUJBQAAAA==.',
Nv='Nvied:BAABLgAECn8cAAMMAAkJpRTXRQDJAQAMAAgJpRTXRQDJAQAjAAEJAAD5cwAxAAAAAA==.',
Ny='Nyctt:BAABLgAECn8YAAMDAAkJ8BlNGQA6AgADAAkJUhhNGQA6AgATAAIJ5xdoFgCSAAAAAA==.Nystra:BAABLgAECn8WAAIMAAkJAhhyJgBEAgAMAAkJAhhyJgBEAgAAAA==.Nyzstra:BAABLgAECn8wAAIKAAkJXiLMGQC/AgAKAAkJXiLMGQC/AgAAAA==.',
['Nê']='Nêwt:BAACLgAFFH8SAAIKAAQJgg6FCQDfAAAKAAQJgg6FCQDfAAAuAAQKf0QAAgoACQkJIBIBAOQBAAoACQkJIBIBAOQBAAAA.',
['Nì']='Nìrvana:BAAALgAECgQJCwAAAA==.',
['Nú']='Núbmuffin:BAAALgAECgEJAgAAAA==.',
On='Onlybeams:BAABLgAECn8fAAICAAkJQBssIQBOAgACAAkJQBssIQBOAgAAAA==.',
Or='Orphu:BAAALgAECgEJAQAAAA==.',
Pa='Pallyplexity:BAAALgAFFAEJAQABLgAECgkJUAARAIImAA==.Palmiste:BAAALgAECgQJBgAAAA==.Pandad:BAAALgADCgEJAQABLgAECgkJFwAWABYUAA==.Pangoplexity:BAAALgADCgIJAgAAAA==.Parahsalin:BAAALgAECgEJAQABLgAECgYJEgAOAAAAAA==.Partyhard:BAAALgAECgEJAQAAAA==.Pastryblust:BAABLgAFFH8KAAIlAAYJLBSeIAAcAQAlAAYJLBSeIAAcAQAAAA==.Pastrydragon:BAACLgAFFH8LAAMdAAQJORbhEAD7AAAdAAQJORbhEAD7AAAeAAEJJxkqDQBLAAAuAAQKfzAAAx0ACAmrINUKAMgCAB0ACAmSHtUKAMgCAB4ABglYI5ULACICAAEuAAUUBgkKACUALBQA.',
Ph='Phaeliea:BAAALgAECgUJBQAAAA==.',
Pi='Pistachio:BAABLgAECn8bAAIFAAYJOA4rNQDpAAAFAAYJOA4rNQDpAAAAAA==.Pitviper:BAABLgAECn8mAAITAAkJ4x7MAwBqAgATAAkJ4x7MAwBqAgAAAA==.',
Po='Pocketrokit:BAAALgAECgkJDAAAAA==.Pogaca:BAAALgAECgcJDgABLgAECggJFwAXAP8bAA==.Portabull:BAAALgADCgcJBwABLgAECgkJIQACAKsdAA==.Possess:BAABLgAECn8mAAIMAAcJVx3YRgDFAQAMAAcJVx3YRgDFAQAAAA==.Pownora:BAABLgAECn8rAAMVAAkJGx2wCwCHAgAVAAkJGx2wCwCHAgAoAAIJ/Q1YvAAxAAAAAA==.',
Ps='Psarchasm:BAABLgAECn8wAAIPAAkJlg05LgCYAQAPAAkJlg05LgCYAQAAAA==.',
Pu='Puck:BAAALgAECgEJAgAAAA==.Puffnstuff:BAAALgAECgUJBQAAAA==.Pugstar:BAAALgAECgMJAwAAAA==.',
Qe='Qel:BAAALgADCgYJCQAAAA==.',
Ra='Rai:BAABLgAECn87AAIGAAkJzSRlBgAuAwAGAAkJzSRlBgAuAwAAAA==.Rancidbeef:BAAALgAECgMJAwAAAA==.Rapha:BAABLgAECn8nAAIWAAkJNyJ8BQDpAgAWAAkJNyJ8BQDpAgAAAA==.Rayyzer:BAABLgAECn8eAAMDAAkJqCHkDABYAgADAAkJqCHkDABYAgATAAIJtBhrGgCWAAAAAA==.',
Re='Realrogue:BAAALgAECgYJCwABLgAECgkJUAARAIImAA==.Realtree:BAAALgADCgMJAwAAAA==.Rema:BAAALgADCgQJBAAAAA==.Reyna:BAAALgADCgUJBQAAAA==.',
Ri='Riddles:BAABLgAECn8eAAMbAAgJzB3NCQBNAgAbAAgJzB3NCQBNAgAYAAEJFiOEtQBaAAAAAA==.Rincewind:BAAALgAECgEJAQAAAA==.',
Ro='Rossabella:BAABLgAECn9FAAMgAAkJahuQCwCtAgAgAAkJahuQCwCtAgANAAgJ0w7HGwC4AQAAAA==.Rot:BAABLgAECn8nAAIfAAkJCSb3AgAWAwAfAAkJCSb3AgAWAwAAAA==.',
Ru='Rude:BAAALgAECgYJBgABLgAFFAcJFAAPAEoeAA==.Ruzala:BAAALgADCgEJAQAAAA==.',
Sa='Samsonn:BAAALgADCgQJBAAAAA==.Sanctity:BAAALgADCgYJCgAAAA==.Santino:BAACLgAFFH8MAAMYAAMJPQjpTACLAAAYAAMJPQjpTACLAAAbAAEJ5AFuRgAgAAAuAAQKfx4AAhgACAlhGdUeAFACABgACAlhGdUeAFACAAEuAAUUAwkRAAoAGBEA.Saphlocket:BAAALgAECgYJEgAAAA==.Sathin:BAABLgAECn8yAAICAAkJmwpaYQBmAQACAAkJmwpaYQBmAQAAAA==.',
Sc='Scher:BAAALgADCgkJCwAAAA==.Scrungus:BAAALgADCgYJBgAAAA==.Scufalufagus:BAAALgAECgUJBQABLgAFFAgJFwAMAFULAA==.',
Se='Seetick:BAAALgAECgIJBAAAAA==.Sefekat:BAAALgAECgEJAQABLgAECgkJHwACAEAbAA==.September:BAAALgAECgIJAgABLgAFFAUJEQAGABoVAA==.Sevatar:BAABLgAECn8nAAIFAAkJUg21HwB8AQAFAAkJUg21HwB8AQAAAA==.',
Sf='Sfcwarner:BAAALgAECgEJAQAAAA==.',
Sg='Sgtwarner:BAAALgAECgEJAgAAAA==.',
Sh='Shampooyou:BAABLgAECn82AAIkAAgJSBG6PgCzAQAkAAgJSBG6PgCzAQAAAA==.Shockakhan:BAAALgAECgkJDgAAAA==.Shocknstone:BAAALgADCgcJBwABLgAECgkJUAARAIImAA==.',
Si='Silentmamba:BAAALgAECgEJAQAAAA==.Sinistra:BAAALgAECggJEwAAAA==.',
Sk='Skelecopter:BAAALgADCgMJAwAAAA==.',
Sl='Slapshot:BAAALgAECggJCwABLgAECggJFwAXAP8bAA==.',
Sn='Snowflake:BAAALgADCgcJBwAAAA==.',
Sp='Spellsteal:BAABLgAECn8lAAIKAAkJuxiPOAA2AgAKAAkJuxiPOAA2AgABLgAFFAUJDQAJAGIJAA==.Spicynudz:BAAALgAECgEJAQAAAA==.Spring:BAACLgAFFH8RAAMGAAUJGhWARAAkAQAGAAUJGhWARAAkAQALAAEJpAAJLgA2AAAuAAQKfyUAAwYACQlfHQwwABwCAAYACQkjHQwwABwCAAsABgnTC/ZMAB0BAAAA.',
Ss='Ssgwarner:BAAALgAECgEJAQAAAA==.',
St='Stardel:BAAALgAECgYJDQABLgAFFAgJHgADAIsjAA==.Sting:BAABLgAECn8fAAIGAAcJoxADbABpAQAGAAcJoxADbABpAQAAAA==.Stormclaw:BAABLgAECn8zAAMYAAkJSx2fEQDDAgAYAAkJSx2fEQDDAgAXAAEJkBwoeQBUAAAAAA==.Stormcrash:BAAALgADCgYJBgABLgAECgkJJgAMAJ0WAA==.Stregoica:BAAALgADCgcJDgABLgAFFAgJFwAMAFULAA==.',
Su='Suhfering:BAAALgADCgYJBgABLgAECgkJHwACAEAbAA==.Superbeef:BAAALgAECgEJAQAAAA==.Sushiiez:BAAALgADCgMJAwAAAA==.Suwo:BAAALgADCgIJAQAAAA==.',
Sy='Sychopath:BAAALgAECgQJCwAAAA==.Sykadelik:BAAALgAECgMJAwAAAA==.Syngoma:BAAALgADCgIJAgAAAA==.',
Ta='Tallron:BAACLgAFFH8eAAIYAAgJSRmkBwCFAgAYAAgJSRmkBwCFAgAuAAQKfy4AAxgACQmaJLcJAPcCABgACQmaJLcJAPcCABcABQmPFRRCAAUBAAAA.Tallsera:BAAALgADCgcJDQABLgAFFAgJHgAYAEkZAA==.Tallyfan:BAAALgADCgcJEwAAAA==.Tamedsloth:BAAALgAECgYJBgAAAA==.Tandraella:BAAALgAECgQJBQABLgAFFAQJBgABAFUTAA==.Tanthalos:BAAALgAECgUJBgAAAA==.Taroquin:BAAALgADCgkJCgAAAA==.',
Te='Ternay:BAAALgADCgIJAQAAAA==.Teskhamen:BAAALgAFFAIJAgAAAA==.Tetamesh:BAAALgADCgQJBAAAAA==.',
Th='Theskabandit:BAAALgADCgcJEQAAAA==.Thrustruggle:BAAALgAECgMJAwAAAA==.',
Ti='Tiamot:BAAALgADCgUJCAAAAA==.',
To='Toby:BAAALgAECgYJBgAAAA==.Tojikitoushi:BAACLgAFFH8FAAISAAMJyQ7rDwDHAAASAAMJyQ7rDwDHAAAuAAQKfzgAAhIACQnpIGoDANECABIACQnpIGoDANECAAAA.Tombs:BAAALgAECgcJCgAAAA==.Tonsonger:BAAALgAECgUJCAAAAA==.Totenhammer:BAAALgAECgQJCwAAAA==.Totenplage:BAAALgAECgQJBAAAAA==.',
Tr='Trid:BAAALgAECggJCAAAAA==.Tristex:BAAALgAECgUJBQABLgAECggJFwAXAP8bAA==.',
Tu='Tuha:BAAALgAFFAIJAgAAAA==.',
Tw='Twergstronk:BAAALgADCgEJAQAAAA==.',
Ty='Tyrolia:BAAALgAECgMJAwAAAA==.',
Um='Umibozu:BAAALgAECgIJAgAAAA==.',
Un='Unoocho:BAAALgADCgcJBwAAAA==.',
Ur='Urchak:BAAALgAECgYJBgAAAA==.',
Va='Valliya:BAABLgAFFH8IAAIIAAMJbwO3hgCmAAAIAAMJbwO3hgCmAAAAAA==.',
Ve='Velratha:BAABLgAECn8UAAIaAAgJtQ80DAB2AQAaAAgJtQ80DAB2AQAAAA==.Vesfu:BAAALgADCgEJAQAAAA==.Vesi:BAAALgADCgcJCgAAAA==.Vextt:BAABLgAECn8eAAMhAAgJDRi/KgB9AQAhAAcJRxu/KgB9AQAgAAIJeBiIawA7AAAAAA==.',
Vi='Vicsta:BAAALgAECgcJCgAAAA==.',
Vo='Voidrend:BAAALgAECgQJBwAAAA==.Voidwarner:BAAALgAECgMJAwAAAA==.Volight:BAAALgADCgYJCQAAAA==.Volke:BAABLgAECn8nAAIoAAkJMxbfHgAjAgAoAAkJMxbfHgAjAgAAAA==.Volmnk:BAAALgAECgUJDAAAAA==.Volq:BAAALgAECgEJAQAAAA==.Voltarix:BAAALgAECgYJCQAAAA==.Voodoopriest:BAABLgAECn8YAAIMAAcJMwRDpAAQAQAMAAcJMwRDpAAQAQAAAA==.Voyria:BAABLgAECn8xAAQYAAkJVwhMcADjAAAYAAgJ9QRMcADjAAAXAAYJiQWdVwCzAAAcAAIJwQLiVQAuAAAAAA==.',
Vs='Vs:BAAALgAECgYJBgAAAA==.',
Vy='Vynlenn:BAAALgADCgMJAwAAAA==.Vyskaar:BAAALgAECgEJAQAAAA==.Vyskar:BAAALgAECgUJCQAAAA==.Vyskary:BAAALgAECgEJAgAAAA==.',
Wa='Warm:BAACLgAFFH8ZAAIVAAgJsxpwAgBGAgAVAAgJsxpwAgBGAgAuAAQKfycAAhUACQkTImsIAPMCABUACQkTImsIAPMCAAAA.Warmlight:BAAALgAECgYJDAAAAA==.',
We='Weewu:BAAALgAECgQJBAABLgAECgYJBgAOAAAAAA==.Weeziveli:BAAALgAECgQJDQAAAA==.Weledish:BAACLgAFFH8bAAIKAAQJgx7rQwBhAQAKAAQJgx7rQwBhAQAuAAQKfywAAgoACQmvG3EwAFcCAAoACQmvG3EwAFcCAAAA.Weleron:BAAALgAFFAIJAgAAAA==.',
Wh='Whystler:BAAALgAECgIJAgAAAA==.',
Wi='Wienercat:BAABLgAECn8hAAIYAAcJ6STyDgDeAgAYAAcJ6STyDgDeAgABLgAECggJJwAkAHcjAA==.Wimol:BAAALgAECgYJBgABLgAECgkJKwAVABsdAA==.Windmacedu:BAAALgAECgYJCgAAAA==.',
Xt='Xtreeme:BAAALgAECgIJAgAAAA==.',
Ya='Yael:BAABLgAECn80AAICAAkJeB7JGgB0AgACAAkJeB7JGgB0AgAAAA==.Yama:BAAALgAECgcJEAAAAA==.',
Za='Zamrazac:BAAALgAECgUJCAABLgAECgkJMwAYAEsdAA==.Zarewien:BAABLgAECn8uAAIgAAkJ6AorLABoAQAgAAkJ6AorLABoAQAAAA==.',
Ze='Zeddicus:BAAALgAECgMJAwAAAA==.',
Zi='Ziddles:BAABLgAECn8bAAIUAAkJDxvcEwAGAgAUAAkJDxvcEwAGAgAAAA==.',
Zo='Zomgdk:BAAALgAECgEJAgABLgAECgkJRQAWAPsfAA==.Zomgmonk:BAABLgAECn9FAAIWAAkJ+x8/BQDtAgAWAAkJ+x8/BQDtAgAAAA==.Zomgzilla:BAAALgAECggJAQABLgAECgkJRQAWAPsfAA==.Zorep:BAAALgAECgEJAQAAAA==.Zorien:BAAALgAECgQJBAAAAA==.',
Zu='Zuraq:BAAALgAECgEJBgAAAA==.Zurisdad:BAABLgAECn83AAIWAAkJ8B7iBwC2AgAWAAkJ8B7iBwC2AgABLgAFFAUJFAAKAMYXAA==.Zurishmi:BAACLgAFFH8cAAIkAAUJ/h5lBQB3AQAkAAUJ/h5lBQB3AQAuAAQKfzMAAiQACQk6JpcBALgDACQACQk6JpcBALgDAAAA.',
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
