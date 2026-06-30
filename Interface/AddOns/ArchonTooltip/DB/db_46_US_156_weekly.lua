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

local lookup = {'Rogue-Outlaw','Priest-Holy','Priest-Discipline','Warrior-Fury','Monk-Mistweaver','Monk-Windwalker','Druid-Balance','Evoker-Devastation','Unknown-Unknown','DemonHunter-Havoc','Shaman-Enhancement','Hunter-BeastMastery','Evoker-Preservation','Paladin-Protection','Paladin-Retribution','Shaman-Elemental','Shaman-Restoration','DeathKnight-Frost','Monk-Brewmaster','Druid-Guardian','Druid-Restoration','DeathKnight-Blood','Paladin-Holy','Druid-Feral','Mage-Arcane','Mage-Frost','DeathKnight-Unholy','Priest-Shadow','Warlock-Demonology','DemonHunter-Devourer','Rogue-Subtlety','Warlock-Affliction','Warlock-Destruction','Warrior-Protection','Evoker-Augmentation','Warrior-Arms','Hunter-Marksmanship','Hunter-Survival','DemonHunter-Vengeance',}
local provider = {region='US',realm='Misha',name='US',type='weekly',zone=46,date='2026-06-27',data={Ac='Acidburn:BAABLgAECn8WAAIBAAcJ0BroAwDvAQABAAcJ0BroAwDvAQAAAA==.',
Ae='Aea:BAAALgAECgIJCQAAAA==.Aevie:BAABLgAECn8WAAMCAAYJdRCINQAtAQACAAYJdRCINQAtAQADAAMJqgsWXgCGAAAAAA==.Aevië:BAAALgAECgYJCgAAAA==.',
Af='Afterlìfe:BAAALgAECgkJEwAAAA==.',
Ai='Ailis:BAAALgADCgQJBAAAAA==.Aimhere:BAAALgAECgEJAQAAAA==.',
Al='Alendria:BAAALgADCgYJBgAAAA==.Alizë:BAAALgADCgQJAwAAAA==.Alluna:BAAALgADCgEJAQAAAA==.Alorillan:BAAALgAECgkJEwAAAA==.Altabrew:BAAALgAECgQJBAAAAA==.Altair:BAAALgAECgUJDwABLgAECgkJIQAEABMhAA==.',
An='Andelynn:BAAALgAECgIJAgAAAA==.',
Ap='Applejuic:BAACLgAFFH8KAAIFAAMJtgr+GAB0AAAFAAMJtgr+GAB0AAAuAAQKfxQAAwUACQlKFlYbAD0CAAUACQlKFlYbAD0CAAYAAQk1EKWiAC0AAAAA.Appless:BAAALgAECgQJBwAAAA==.',
Ar='Araylia:BAABLgAECn8hAAIHAAkJgw3MNABFAQAHAAkJgw3MNABFAQAAAA==.Aridella:BAABLgAECn8VAAIIAAYJRA5LFADIAAAIAAYJRA5LFADIAAAAAA==.Ariellaa:BAAALgAECgYJBgAAAA==.Artamayis:BAAALgAECgYJCgAAAA==.',
As='Ashaly:BAAALgADCgUJBQAAAA==.Ashlei:BAAALgAECgQJCAAAAA==.',
At='Atomseve:BAAALgADCgQJBAABLgAECggJEwAJAAAAAA==.',
Au='Aurafarmer:BAAALgADCgEJAQAAAA==.Autopsia:BAAALgADCgYJBgABLgAECgkJOwAKAF8ZAA==.Autumn:BAAALgAECgMJAwAAAA==.',
Av='Avalorne:BAAALgAECgMJAwABLgAECgkJIQAEABMhAA==.Avena:BAAALgADCgEJAwAAAA==.',
Az='Azaizel:BAAALgAECgYJCwAAAA==.Azusie:BAABLgAECn9AAAILAAkJ3BjLAAC4AQALAAkJ3BjLAAC4AQAAAA==.',
Ba='Baddate:BAABLgAECn8pAAIMAAcJrxClbABoAQAMAAcJrxClbABoAQAAAA==.Baddragøn:BAABLgAECn84AAMNAAkJBRZ6DQD4AQANAAgJ0xV6DQD4AQAIAAgJxg/QCQCHAQAAAA==.Balthaas:BAABLgAECn9FAAMOAAkJvRmcAAAXAgAOAAkJvRmcAAAXAgAPAAEJewdjUQErAAAAAA==.Bangen:BAAALgAECgcJDwAAAA==.Bastria:BAAALgAECgYJDAAAAA==.Baulters:BAAALgAECgYJCAAAAA==.',
Be='Beenn:BAAALgAECgYJBgAAAA==.Benrent:BAAALgADCgEJAQABLgAECgYJBgAJAAAAAA==.',
Bh='Bharko:BAAALgADCgcJCgABLgAFFAcJEAAMABkZAA==.',
Bi='Billyblastin:BAAALgAECgMJAwABLgAECgkJJQAQAFgZAA==.Billywitchdr:BAABLgAECn8lAAMQAAkJWBl5GQAWAgAQAAkJWBl5GQAWAgARAAEJFgbf3AArAAAAAA==.Biocryo:BAAALgADCgYJBgABLgAECggJEAAJAAAAAA==.',
Bl='Blazingpanda:BAAALgAECgMJBAAAAA==.Blizeatsass:BAAALgADCgMJAwAAAA==.Bluedomino:BAAALgAECgMJCAAAAA==.Bluetoykawi:BAACLgAFFH8JAAISAAQJXgSpFQDcAAASAAQJXgSpFQDcAAAuAAQKfz4AAhIACQloFVkIAAkCABIACQloFVkIAAkCAAAA.',
Bo='Boats:BAAALgADCgIJAgAAAA==.Boltspark:BAAALgADCgMJAwAAAA==.Borgo:BAAALgAECgYJBgAAAA==.Bowlenciaga:BAABLgAECn8gAAIMAAgJyQqRZgB3AQAMAAgJyQqRZgB3AQAAAA==.Bozilla:BAAALgADCgMJAwAAAA==.',
Br='Braelia:BAAALgADCgcJCAAAAA==.Brainfart:BAAALgADCgUJBQABLgAECggJGwAMABcWAA==.Breloom:BAAALgADCgEJAQAAAA==.Bruithis:BAAALgADCgIJAgAAAA==.',
Bu='Burdan:BAAALgADCgQJBAAAAA==.Buttermebuns:BAAALgADCgcJCAAAAA==.Buttfish:BAAALgAECgIJAgABLgAECgYJCwAJAAAAAA==.',
Ca='Cariandria:BAAALgAECgUJBgAAAA==.',
Cc='Cc:BAAALgAECgEJAgAAAA==.',
Ch='Chahaein:BAAALgAECgYJDwAAAA==.Charbaby:BAAALgAFFAMJAwABLgAFFAYJGAATAEYZAA==.Charhartt:BAACLgAFFH8FAAIUAAMJJw+IIgCSAAAUAAMJJw+IIgCSAAAuAAQKfxUAAxQABgljF7kgAEkBABQABgljF7kgAEkBABUAAQlXB5LpACMAAAEuAAUUBgkYABMARhkA.Charita:BAAALgAECgMJBAABLgAFFAYJGAATAEYZAA==.Charitard:BAAALgAECgEJAQABLgAFFAYJGAATAEYZAA==.Charizard:BAAALgAECgEJAQABLgAFFAYJGAATAEYZAA==.Charming:BAACLgAFFH8YAAITAAYJRhm/GwBJAQATAAYJRhm/GwBJAQAuAAQKfyIAAhMACQmkG4oaANEBABMACQmkG4oaANEBAAAA.Charmonic:BAAALgAFFAIJAgABLgAFFAYJGAATAEYZAA==.Chelseah:BAAALgAECgYJEAABLgAECgcJDwAJAAAAAA==.Christinè:BAAALgAECgUJBQAAAA==.',
Ci='Cidearthen:BAAALgADCgEJAQAAAA==.Cinderlight:BAAALgAECgEJAQAAAA==.',
Cl='Clanker:BAAALgAECgkJEgAAAA==.Clémentine:BAAALgAECgEJAgAAAA==.',
Co='Coldknight:BAABLgAECn8lAAMWAAcJzwK1BwBZAAASAAcJWAI2KgCDAAAWAAUJewK1BwBZAAAAAA==.Conien:BAAALgADCgQJBAAAAA==.Conifer:BAABLgAECn8dAAIVAAcJcBuzAQDgAQAVAAcJcBuzAQDgAQAAAA==.Coniption:BAAALgADCgEJAQAAAA==.Contrlurself:BAAALgAECggJEgABLgAECgkJKwAHALsXAA==.Copium:BAAALgAECgQJBwAAAA==.Cornpop:BAABLgAECn8ZAAIFAAYJuxHQBgAXAQAFAAYJuxHQBgAXAQAAAA==.Cowret:BAABLgAECn9DAAMXAAkJdCQ5AQC0AwAXAAkJdCQ5AQC0AwAPAAEJAAAL2gEAAAAAAA==.',
Cr='Crystalwolf:BAABLgAECn8VAAIYAAYJiwXVLwCjAAAYAAYJiwXVLwCjAAAAAA==.',
Cu='Curze:BAAALgAECgMJAwAAAA==.',
Cy='Cyonna:BAAALgADCgQJBAAAAA==.',
Da='Darc:BAACLgAFFH8FAAIEAAMJHiTQNgDXAAAEAAMJHiTQNgDXAAAuAAQKfxgAAgQABAldJdQ+AKkBAAQABAldJdQ+AKkBAAAA.Darkfoxgrime:BAAALgAECgkJDQABLgAECgkJMwAGAK0QAA==.Darkjager:BAABLgAECn8rAAIMAAkJHR5jLwAfAgAMAAkJHR5jLwAfAgAAAA==.Darkways:BAAALgAECgcJAQAAAA==.Darlah:BAABLgAECn8sAAIZAAkJIBahAgAgAgAZAAkJIBahAgAgAgAAAA==.Darnalin:BAAALgAECgEJAgABLgAECgkJOwAKAF8ZAA==.Dayva:BAAALgAECgQJBgAAAA==.Dayyva:BAAALgAECgQJDgAAAA==.',
De='Deadcobra:BAABLgAECn8qAAIaAAkJwgTwpwAuAQAaAAkJwgTwpwAuAQAAAA==.Deathbean:BAAALgADCgQJBAABLgAECgUJDwAJAAAAAA==.Debtknight:BAABLgAECn84AAIbAAkJ6h8IFwC8AgAbAAkJ6h8IFwC8AgAAAA==.Deelo:BAAALgAECgYJEAAAAA==.Dehumidifier:BAABLgAECn87AAMCAAkJ+B/DAABWAgACAAkJ+B/DAABWAgAcAAkJQw3RJwCQAQAAAA==.Deltria:BAAALgAECgkJEwAAAA==.Demonrot:BAABLgAECn8YAAIdAAkJ6QoGeABJAQAdAAkJ6QoGeABJAQAAAA==.Dervin:BAAALgAECgQJBAABLgAECggJCAAJAAAAAA==.Deviltank:BAAALgADCgYJDAAAAA==.Devohsup:BAABLgAECn8dAAIeAAgJlB//HwBVAgAeAAgJlB//HwBVAgAAAA==.Devussi:BAABLgAECn8mAAIeAAkJyBTbSACsAQAeAAkJyBTbSACsAQABLgAECggJEQAJAAAAAA==.',
Di='Diefenbaker:BAAALgADCgEJAQAAAA==.Dienva:BAAALgAECgUJBQAAAA==.Digmyearth:BAAALgAECgUJCAAAAA==.Dilea:BAAALgAECggJCQAAAA==.Discoffee:BAAALgADCgYJBgABLgADCgcJEAAJAAAAAA==.',
Dk='Dksakp:BAAALgADCgkJGAAAAA==.',
Do='Dominateelf:BAAALgADCgQJBAABLgAECgMJBAAJAAAAAA==.Dotero:BAABLgAECn8UAAIXAAcJ5hHVAgBWAQAXAAcJ5hHVAgBWAQAAAA==.',
Dr='Dracreina:BAABLgAECn8oAAMIAAgJmxMYCACyAQAIAAgJmxMYCACyAQANAAEJQQaFQAAlAAAAAA==.Dreouss:BAAALgAECgQJBgAAAA==.Driver:BAEALgAFFAIJAwABLgAFFAUJEAAdALYLAA==.',
Du='Dumeslayer:BAAALgADCgcJCQAAAA==.Durzoe:BAABLgAECn8WAAIfAAcJlwoFOQBNAQAfAAcJlwoFOQBNAQAAAA==.',
Dv='Dvsmage:BAAALgAECgUJDwAAAA==.',
Eg='Egaik:BAAALgAECgcJBwAAAA==.',
El='Elarred:BAAALgADCgkJFAAAAA==.Elfkr:BAAALgAECgkJBgAAAA==.Elissauna:BAABLgAECn8VAAIaAAkJ/RK/RQAKAgAaAAkJ/RK/RQAKAgAAAA==.Elylea:BAABLgAECn8hAAIEAAgJChxNHwD0AQAEAAgJChxNHwD0AQAAAA==.',
En='Enorme:BAAALgADCgQJBAAAAA==.',
Eu='Eunice:BAAALgADCgIJAgAAAA==.',
Ex='Exhumator:BAAALgAECgEJAQAAAA==.',
Ez='Ezili:BAAALgAECgEJAQAAAA==.',
Fa='Failure:BAAALgAECgIJAwAAAA==.Falabala:BAABLgAECn8aAAIVAAYJHxy9AQDdAQAVAAYJHxy9AQDdAQAAAA==.Fanghür:BAAALgADCgcJDgAAAA==.',
Fe='Feeloow:BAAALgADCgcJCwAAAA==.Felhound:BAAALgAECgkJEAAAAA==.Felussi:BAAALgAECggJEQAAAA==.Feorahir:BAAALgAECgQJBQAAAA==.Fermitorok:BAAALgADCgEJAQAAAA==.',
Ff='Ff:BAAALgAECgQJBAAAAA==.',
Fi='Finnster:BAABLgAECn80AAIMAAkJXQ6FTgC3AQAMAAkJXQ6FTgC3AQAAAA==.Fionna:BAAALgAECgcJDAAAAA==.Firereina:BAAALgADCggJGQABLgAECggJKAAIAJsTAA==.',
Fl='Fleurminator:BAABLgAECn8nAAIEAAkJBxF+AwA8AQAEAAkJBxF+AwA8AQAAAA==.Fluffybaby:BAAALgADCgMJAwAAAA==.',
Fo='Fondadix:BAABLgAECn8lAAIWAAkJpyEICgByAgAWAAkJpyEICgByAgAAAA==.',
Fr='Frieia:BAABLgAECn8cAAIVAAgJ3weTZAAHAQAVAAgJ3weTZAAHAQAAAA==.Frostiilocks:BAAALgAECggJCQAAAA==.Frostitutte:BAAALgAECgYJEQAAAA==.Frozenjade:BAAALgAECgMJBQAAAA==.Fryértuck:BAAALgAECgYJCAABLgAECgQJCwAJAAAAAA==.',
Fu='Fuze:BAABLgAECn8UAAIbAAYJWxDNCwDUAAAbAAYJWxDNCwDUAAAAAA==.',
Ga='Galakrosh:BAACLgAFFH8HAAMgAAMJASHFDgCdAAAdAAMJASFbcgDcAAAgAAIJ9B/FDgCdAAAuAAQKfyoABCAACAkYJIUFADACAB0ACAlwHT4XAMkCACAACAlpIoUFADACACEAAQkAAIFjAEgAAAAA.Galarína:BAABLgAECn9CAAMFAAkJFCKoDADPAgAFAAgJqSGoDADPAgAGAAkJgB7NAAAPAgAAAA==.Gandora:BAABLgAECn8gAAMbAAkJwxawTwDUAQAbAAkJwxawTwDUAQASAAEJ/wNkQgAiAAAAAA==.Gardrius:BAAALgADCgEJAQAAAA==.',
Ge='Gene:BAAALgADCgcJBwAAAA==.Gentonord:BAABLgAECn8cAAMEAAgJJhoDQQChAQAEAAgJBRcDQQChAQAiAAYJXBdrIAA9AQAAAA==.',
Gi='Gingerports:BAAALgADCgEJAQAAAA==.',
Gk='Gkmc:BAABLgAFFH8YAAIbAAcJYyUQAgCkAgAbAAcJYyUQAgCkAgABLgAFFAgJKgAaANEkAA==.',
Gl='Glomps:BAAALgAFFAMJAwABLgAFFAUJBgAjAFkEAA==.',
Go='Gonaldduck:BAAALgAECgYJBgAAAA==.',
Gr='Greasemunkey:BAABLgAECn82AAIYAAkJOxe6AADLAQAYAAkJOxe6AADLAQAAAA==.Greentea:BAAALgADCggJCwAAAA==.Griiv:BAACLgAFFH8FAAIPAAIJBB0LjgCWAAAPAAIJBB0LjgCWAAAuAAQKfyMAAg8ACAnNISEWAOQCAA8ACAnNISEWAOQCAAAA.Grislytotem:BAAALgADCgYJCAAAAQ==.Grislywolf:BAAALgAECgUJBQAAAA==.',
Ha='Hakunamatata:BAAALgAECgUJBwAAAA==.Hamburger:BAABLgAECn8ZAAIcAAcJWxVmLAByAQAcAAcJWxVmLAByAQAAAA==.Hammerhard:BAAALgADCgcJDgAAAA==.Hampter:BAAALgAECgYJCQABLgAECgkJJQAcAMgaAA==.Hanita:BAAALgAECgEJAgAAAA==.Haymáker:BAAALgADCgIJAgAAAA==.',
He='Heights:BAAALgAECgUJDgAAAA==.Heliosan:BAAALgAECgEJBAAAAA==.Heyu:BAAALgAECgUJCAABLgAECggJGwAMABcWAA==.',
Hi='Himoe:BAAALgADCgcJDgAAAA==.',
Ho='Holybean:BAAALgADCgkJGAABLgAECgUJDwAJAAAAAA==.Holyhench:BAAALgAECgUJBQAAAA==.Honkeykong:BAAALgADCgIJAgAAAA==.Hoochix:BAAALgAECgQJCQAAAA==.',
Hr='Hrsho:BAAALgADCgQJBAAAAA==.Hrshoo:BAAALgAFFAIJBAAAAA==.',
Hu='Humzashaind:BAABLgAECn8fAAMkAAgJtRHUPADSAAAEAAcJyQ3GUQADAQAkAAYJeA/UPADSAAAAAA==.Huntinrabits:BAAALgADCgIJAgAAAA==.Huntt:BAAALgAECgEJAQAAAA==.Huzzyy:BAAALgAECggJDAABLgAECgkJHwAXAN0bAA==.',
Hy='Hyphira:BAAALgAECgQJCgABLgAECgUJDQAJAAAAAA==.',
Il='Illumi:BAAALgAFFAIJAwABLgAFFAgJKgAbAF8bAA==.',
In='Inferbloom:BAAALgAECggJCAABLgAFFAQJDwAJAAAAAA==.Infernum:BAAALgAFFAQJDwAAAQ==.Insomnia:BAAALgAECgUJBQAAAA==.',
Ir='Irayvia:BAAALgADCgIJAgAAAA==.',
Ja='Jackyvoker:BAABLgAECn8qAAMNAAkJfCLrAQBnAwANAAkJfCLrAQBnAwAIAAMJqRmCJwDlAAAAAA==.Jaezzon:BAAALgADCgQJBwAAAA==.Janessah:BAAALgAECgMJAwAAAA==.',
Je='Jeannaah:BAAALgAECgQJBAABLgAECgcJDwAJAAAAAA==.Jetaime:BAAALgAECgUJBQAAAA==.',
Jh='Jharia:BAAALgADCgMJAgAAAA==.',
Ji='Jinksey:BAAALgAECgcJDQABLgAECgcJEQAeABETAA==.',
Jo='Johndoom:BAAALgAECgYJDgAAAA==.Johnfist:BAAALgAECgEJBAAAAA==.Johngrippy:BAAALgAECgEJAwAAAA==.Johnrend:BAAALgAECgEJAQAAAA==.',
Ju='Juicybottoms:BAAALgADCgMJAgAAAA==.',
Ka='Kairstia:BAAALgAECgYJDQABLgAECggJKAAIAJsTAA==.Kalidormi:BAAALgAECgYJCgAAAA==.Kalzious:BAAALgADCgkJHAAAAA==.Kamikaze:BAAALgAECgcJBQAAAA==.Kayelalynn:BAABLgAECn8rAAMHAAkJuxeIFwARAgAHAAkJuxeIFwARAgAVAAMJNgEowgBDAAAAAA==.',
Kd='Kd:BAAALgAECgEJAgAAAA==.',
Ke='Kegpaw:BAAALgAFFAEJAQAAAA==.Keiri:BAAALgADCgYJBgAAAA==.Kelana:BAABLgAECn8lAAITAAkJxB/zCACjAgATAAkJxB/zCACjAgAAAA==.Kendô:BAAALgAECgcJDAAAAA==.Ketdealer:BAAALgAECgcJDQAAAA==.Ketzendk:BAAALgAECgYJBQAAAA==.Keyahi:BAACLgAFFH8cAAIeAAYJRBv5JwCKAQAeAAYJRBv5JwCKAQAuAAQKfx0AAh4ACQk0HOsiAEUCAB4ACQk0HOsiAEUCAAEuAAQKAQkBAAkAAAAA.',
Kh='Khaean:BAAALgAECgMJAwAAAA==.Khasumi:BAAALgADCgMJAwAAAA==.Khety:BAAALgAECgQJBAAAAA==.',
Ki='Kickandpunch:BAAALgAECgYJDgAAAA==.Kicsi:BAAALgAECgIJAwAAAA==.Kilan:BAABLgAECn8iAAMPAAgJXRQAaQCdAQAPAAgJeBIAaQCdAQAOAAIJNBjwNgCEAAAAAA==.Killinrage:BAAALgAECgYJDgAAAA==.Kissofpaine:BAAALgADCgIJAgAAAA==.Kitsuney:BAAALgADCgMJAwAAAA==.Kizaru:BAAALgAECgcJCAAAAA==.',
Ko='Korz:BAAALgADCgcJBwABLgAECgcJFQAaAOEXAA==.',
Kp='Kpop:BAAALgAECgEJAQAAAA==.',
Kr='Krutree:BAAALgAECgcJCQAAAA==.Krynj:BAAALgAFFAEJAwAAAA==.Krònk:BAAALgAECgEJAQABLgAECgQJCwAJAAAAAA==.',
Ku='Kumokiri:BAAALgAECgIJAgAAAA==.Kuromu:BAABLgAFFH8HAAIbAAMJOxZulgDgAAAbAAMJOxZulgDgAAAAAA==.Kurzzon:BAAALgADCgMJAwAAAA==.',
Kv='Kvothepally:BAAALgAECgEJAQAAAA==.',
Ky='Kyleata:BAACLgAFFH8FAAIMAAMJlgsoaADVAAAMAAMJlgsoaADVAAAuAAQKfzoAAgwACAk/HvgrAC0CAAwACAk/HvgrAC0CAAAA.Kyleigh:BAAALgAECgQJBQABLgAECgcJDwAJAAAAAA==.Kyokin:BAACLgAFFH8JAAIPAAIJnxJdkgCOAAAPAAIJnxJdkgCOAAAuAAQKf0UAAw8ACQnKFoo+AAsCAA8ACAlMGYo+AAsCAA4ACAmNCcUDALgAAAAA.Kyzula:BAABLgAECn80AAIRAAcJBRmPLgD8AQARAAcJBRmPLgD8AQAAAA==.',
['Kê']='Kêndo:BAAALgAECgEJAwABLgAECgcJDAAJAAAAAA==.',
La='Lace:BAAALgADCgMJAwAAAA==.Launam:BAAALgAECgMJBAAAAA==.Laytone:BAAALgADCgYJBwAAAA==.',
Le='Legcurl:BAAALgAECgEJAwAAAA==.Leilanirane:BAAALgADCgEJAQAAAA==.Lepotko:BAAALgAECgQJBAAAAA==.',
Li='Lightbear:BAAALgAECgMJAwAAAA==.Lilchub:BAAALgAECgIJAwAAAA==.Lilylocks:BAAALgAECgcJCQAAAA==.Lilyrocks:BAAALgAECgUJCQAAAA==.Literallad:BAAALgADCgcJBgAAAA==.Littlelo:BAAALgAECgYJEgAAAA==.',
Ll='Llortdnaz:BAAALgADCgEJAgAAAA==.',
Lo='Lockology:BAAALgAFFAEJAQAAAA==.Lokarg:BAAALgADCgIJAgAAAA==.Loudcry:BAACLgAFFH8KAAIZAAUJ9hDMAAB1AQAZAAUJ9hDMAAB1AQAuAAQKfzMAAxkACQlvHrQBAKkCABkACAkAIbQBAKkCABoAAwm0EDf6ALUAAAAA.',
Lu='Lunaeria:BAAALgADCggJCAAAAA==.',
Ly='Lyanah:BAACLgAFFH8gAAIVAAYJ9wkqLQAAAQAVAAYJ9wkqLQAAAQAuAAQKfywAAhUACQm3FlwkACgCABUACQm3FlwkACgCAAAA.Lydia:BAAALgAECgQJAgAAAA==.Lyniah:BAAALgAECgQJBQAAAA==.Lyriell:BAAALgAECgEJAQAAAA==.',
Ma='Machete:BAAALgAECgQJCQAAAA==.Maelius:BAABLgAECn9FAAMXAAkJTBsWAQAJAgAXAAkJTBsWAQAJAgAOAAQJqQNUOgBzAAAAAA==.Maggrus:BAABLgAECn8bAAIMAAgJFxYZWACcAQAMAAgJFxYZWACcAQAAAA==.Malavel:BAAALgADCggJCAAAAA==.Malically:BAACLgAFFH8FAAMMAAMJjhRVXQDqAAAMAAMJjhRVXQDqAAAlAAEJYwTiOwAzAAAuAAQKfyAAAyUACQlpELsSADIBACUACAmCEbsSADIBAAwABgntC/iUABYBAAAA.Manshoon:BAAALgADCgcJCwAAAA==.Marlory:BAAALgADCgUJBQAAAA==.Masinko:BAAALgADCgEJAQAAAA==.Math:BAEALgAFFAEJAQABLgAFFAYJCwAjAAYPAA==.Matheney:BAEBLgAFFH8RAAIUAAgJnAxHBgCWAQAUAAgJnAxHBgCWAQABLgAFFAYJCwAjAAYPAA==.Matsuzo:BAAALgAECgEJAgAAAA==.Maxnem:BAAALgADCggJCAABLgAECggJHwAHADMPAA==.',
Mc='Mcrib:BAAALgADCggJBQAAAA==.Mctubby:BAAALgADCgUJBQABLgADCgUJBgAJAAAAAA==.Mctubmonk:BAAALgADCgUJBgAAAA==.',
Me='Meatpopsicle:BAAALgADCgEJAQAAAA==.Meigz:BAAALgAECgYJDwAAAA==.Melicious:BAAALgAECgQJBAAAAA==.Melidin:BAAALgAECgkJEgAAAA==.Melinda:BAAALgAFFAIJAwAAAA==.Melindorei:BAAALgAECgEJAgAAAA==.Melledrus:BAAALgAECgEJAQAAAA==.Mememo:BAAALgAECgMJAwAAAA==.Menöpaws:BAEALgAFFAMJAwAAAA==.Merithrá:BAAALgAECgMJAwAAAA==.',
Mi='Mikaeljayfox:BAAALgAECgcJDwAAAQ==.Mikros:BAAALgAECgQJBgAAAA==.Milenzha:BAABLgAECn8nAAIMAAgJpBYwSQDGAQAMAAgJpBYwSQDGAQAAAA==.Milkymaiden:BAAALgADCgMJBQABLgADCgYJCQAJAAAAAA==.Mimachote:BAABLgAECn8XAAIUAAkJ+hA9HABsAQAUAAkJ+hA9HABsAQAAAA==.',
Mo='Monetta:BAAALgADCgIJAgAAAA==.Monk:BAAALgAECggJEAAAAA==.Moonblood:BAAALgADCggJEAAAAA==.Moonfighter:BAAALgAECgEJAgAAAA==.Moontann:BAAALgAECgkJAQAAAA==.Morcombe:BAAALgAECgEJAQAAAA==.Moreia:BAAALgAECgMJAwAAAA==.Motown:BAAALgAECgYJCwAAAA==.Mousse:BAABLgAECn8WAAIPAAYJ1gV0FgB8AAAPAAYJ1gV0FgB8AAAAAA==.',
Mu='Murdalok:BAABLgAECn8ZAAIVAAgJshWdNQDSAQAVAAgJshWdNQDSAQAAAA==.Murdergodx:BAAALgAECgYJCwAAAA==.',
My='Myndy:BAAALgADCgYJCgAAAA==.Mysharona:BAAALgAECgEJAQAAAA==.Mystahmurdah:BAAALgAECgEJAwABLgAECgcJFgAmAM4TAA==.Mysterioñ:BAAALgAECgQJDQAAAA==.',
Mz='Mzbiscuit:BAAALgAECgEJAQABLgAECgMJAwAJAAAAAA==.',
['Má']='Mákla:BAAALgAECgMJAwAAAA==.',
['Mâ']='Mâstermînd:BAAALgAECgUJDgAAAA==.',
Na='Nahte:BAAALgADCgYJCQAAAA==.Naiana:BAAALgADCgMJAwAAAA==.Nasine:BAAALgAECgYJCAABLgAECgkJHAAQAPYdAA==.Natstryker:BAABLgAECn9MAAQTAAkJ4SYjAACUAwATAAkJ4SYjAACUAwAGAAgJ8CJMFQBCAgAFAAcJMRHYQwBdAQAAAA==.Naturemyth:BAAALgAFFAEJAwAAAA==.Nazu:BAAALgADCgUJCgAAAA==.',
Ne='Neeró:BAABLgAECn8iAAMeAAYJphVRfAAnAQAeAAYJphVRfAAnAQAKAAEJtxS5ZwA+AAAAAA==.Nelthon:BAAALgADCgYJBgAAAA==.',
Ni='Nishastraza:BAAALgAECgEJAwABLgAECgcJDwAJAAAAAA==.',
No='Nonaha:BAAALgADCgkJEQAAAA==.Notsoda:BAAALgAECgQJCQAAAA==.',
Nu='Nuciferas:BAAALgAECggJDgAAAA==.',
Oa='Oaf:BAAALgAECgYJBgAAAA==.',
Om='Omcmoneyshot:BAAALgAECgUJBQAAAA==.',
Oo='Oolong:BAAALgAECgQJBQAAAA==.',
Or='Ordomalleus:BAAALgADCgEJAQABLgAECgEJAQAJAAAAAA==.Organa:BAABLgAECn8jAAIEAAgJoAqUPwBGAQAEAAgJoAqUPwBGAQAAAA==.',
Ou='Outofthedark:BAAALgAECgIJAgAAAA==.',
Pa='Pakkan:BAAALgAECgEJAQAAAA==.Pallyqb:BAAALgADCgEJAQAAAA==.Palyomie:BAAALgAECgMJBAAAAA==.Pandariam:BAAALgAECgYJEgAAAA==.Pauladeenx:BAAALgAECgIJAwABLgAECgUJDgAJAAAAAA==.',
Pe='Petal:BAAALgAECgYJBwABLgAECggJEAAJAAAAAA==.',
Ph='Pho:BAAALgAECgEJAQAAAA==.',
Pl='Playwitwe:BAAALgAECgUJCAAAAA==.Plowmcballs:BAABLgAECn8ZAAIPAAYJtxIzfgB+AQAPAAYJtxIzfgB+AQAAAA==.Plugley:BAABLgAECn8dAAMaAAkJqBjeOwAqAgAaAAkJqBjeOwAqAgAZAAEJARSGHAA6AAAAAA==.',
Po='Polaris:BAAALgAECgEJAQAAAA==.Poober:BAABLgAECn8hAAMCAAkJbx97DACfAgACAAgJeCF7DACfAgADAAQJNBmUNgA5AQAAAA==.Potooòooóoo:BAABLgAECn8dAAISAAcJVhitFQAsAQASAAcJVhitFQAsAQAAAA==.',
Pr='Pren:BAAALgAFFAEJAQAAAA==.Privet:BAAALgAECgEJAwAAAA==.',
Pu='Purebeef:BAAALgAECgIJAgAAAA==.',
Py='Pygos:BAABLgAECn8ZAAInAAgJ5BiJBwANAgAnAAgJ5BiJBwANAgAAAA==.',
['Pë']='Përdü:BAAALgAECgkJEwAAAA==.',
Qu='Quigglay:BAAALgAECgYJBgAAAA==.',
Ra='Raegnarok:BAABLgAECn8hAAIXAAgJ/RMPIwDsAQAXAAgJ/RMPIwDsAQAAAA==.Raelessa:BAAALgAECgQJCQABLgAECgcJDwAJAAAAAA==.Raigeki:BAAALgADCgQJBQAAAA==.Ralf:BAAALgAECgEJAQAAAA==.Ralphie:BAAALgAECgIJAgAAAA==.Ratapew:BAABLgAECn8WAAIeAAkJEhSrVACIAQAeAAkJEhSrVACIAQAAAA==.Ratheen:BAABLgAECn8eAAIPAAgJtA55nAA9AQAPAAgJtA55nAA9AQAAAA==.Raytar:BAABLgAECn8hAAMHAAkJbh9ADwBrAgAHAAgJgiBADwBrAgAVAAMJ9RsBmwCWAAAAAA==.',
Re='Rekkirin:BAAALgAECgUJBQABLgAECgkJOAANAAUWAA==.Relyk:BAAALgADCgUJBQAAAA==.',
Ri='Riyo:BAAALgAFFAIJAwAAAA==.',
Ro='Roachie:BAAALgAECgYJDgAAAA==.Rockandstone:BAAALgADCgEJAQAAAA==.Roesira:BAAALgAECgEJAQAAAA==.Rogun:BAAALgAECgkJAQAAAA==.Ros:BAAALgAECgMJBAAAAA==.',
Ru='Rug:BAAALgADCgYJBgAAAA==.Rustybray:BAABLgAECn81AAIQAAkJhgfyQgAnAQAQAAkJhgfyQgAnAQAAAA==.Ruu:BAAALgAECgkJBQABLgAFFAQJEgAmAPkSAA==.',
Ry='Ryvulz:BAABLgAECn8eAAIcAAgJHRWsGAAcAgAcAAgJHRWsGAAcAgAAAA==.',
Sa='Salomicum:BAAALgADCgEJAQAAAA==.Sappollo:BAAALgADCgMJAwAAAA==.Sarabi:BAABLgAECn8rAAIFAAgJIBcrJwDuAQAFAAgJIBcrJwDuAQAAAA==.Sarena:BAAALgADCgMJAwAAAA==.Sarkoth:BAAALgADCgEJAQAAAA==.',
Sc='Schnee:BAAALgADCgYJCgAAAA==.Schutzhund:BAAALgAECgMJAgAAAA==.Scrapster:BAAALgAFFAEJAQAAAA==.',
Se='Seifer:BAAALgADCgEJAQAAAA==.Sekha:BAAALgAECgQJBgABLgAECggJIQAHAOoXAA==.Serbero:BAAALgAECgEJAQAAAA==.Serelia:BAABLgAFFH8JAAIFAAMJJhW1EwCsAAAFAAMJJhW1EwCsAAAAAA==.Seshiro:BAAALgAECgQJBAABLgAECgkJNQAOANkjAA==.',
Sh='Shadoweave:BAACLgAFFH8mAAMCAAcJ7BQ3BQDxAAACAAcJ7BQ3BQDxAAAcAAUJLRRGCADZAAAuAAQKfxkAAgIACQkoGJQTAD0CAAIACQkoGJQTAD0CAAEuAAUUCQk9AAwAERgA.Shalalia:BAABLgAECn8lAAIMAAcJNw5UdABXAQAMAAcJNw5UdABXAQAAAA==.Shambean:BAAALgADCgEJAQABLgAECgUJDwAJAAAAAA==.Shammywitch:BAAALgAFFAIJAwABLgAECgQJCwAJAAAAAA==.Shehgu:BAAALgADCgMJAwAAAA==.Shentsu:BAABLgAECn8YAAIFAAkJ0CD7BQD/AgAFAAkJ0CD7BQD/AgAAAA==.Shhanks:BAAALgAECgEJAQAAAA==.Shinmen:BAAALgADCgkJCQAAAA==.Shinsha:BAAALgADCgIJAwAAAA==.Shnizelnazee:BAABLgAECn8aAAIPAAgJQw44CwDzAAAPAAgJQw44CwDzAAAAAA==.Shortonheals:BAAALgAECgMJAwAAAA==.',
Si='Siege:BAAALgAECgUJBQAAAA==.Silie:BAAALgADCgEJAQAAAA==.Silik:BAAALgADCgcJBwAAAA==.Simpforsale:BAAALgAECgYJCQAAAA==.',
Sk='Skybladee:BAAALgAECgIJAgAAAA==.',
Sm='Smokeyb:BAACLgAFFH8JAAIPAAMJ+AnueADDAAAPAAMJ+AnueADDAAAuAAQKfywAAg8ACAlrFpBYAMIBAA8ACAlrFpBYAMIBAAAA.',
Sn='Sneevie:BAAALgAECggJCgAAAA==.Snorehees:BAABLgAECn8uAAMMAAkJ7w9ITQC6AQAMAAkJ7w9ITQC6AQAlAAQJMwKZNgBEAAAAAA==.',
So='Songarrow:BAAALgAECgYJBgAAAA==.Songstar:BAABLgAECn88AAIMAAkJ+SNcAQCmAgAMAAkJ+SNcAQCmAgAAAA==.Soullraven:BAAALgADCgkJNQAAAA==.',
Sp='Spy:BAAALgAECgEJBQAAAA==.',
Sq='Squingledorf:BAAALgAECgMJAwAAAA==.',
St='Staavon:BAABLgAECn8nAAIaAAgJ8QmQkQBVAQAaAAgJ8QmQkQBVAQAAAA==.Stacy:BAAALgAECgEJAQABLgAECgQJCAAJAAAAAA==.Stalvis:BAAALgADCgUJBQAAAA==.Starblaze:BAAALgAECgcJDQAAAA==.Starseek:BAABLgAECn8VAAInAAcJLhDLEABDAQAnAAcJLhDLEABDAQAAAA==.Steelboats:BAAALgADCgkJGQAAAA==.',
Su='Sugarbow:BAAALgAECgEJAQAAAA==.Sugarhoof:BAABLgAECn8VAAIMAAcJcQmtDADtAAAMAAcJcQmtDADtAAAAAA==.Sugarlick:BAABLgAECn8kAAIWAAgJPRvYFwCmAQAWAAgJPRvYFwCmAQAAAA==.Sugarpop:BAACLgAFFH8GAAIXAAMJNw3bNQCXAAAXAAMJNw3bNQCXAAAuAAQKfygAAhcACQnXHIISAH4CABcACQnXHIISAH4CAAEuAAUUBAkVABEADSAA.Sugarsrage:BAAALgADCgUJBQAAAA==.Sunraku:BAAALgAECgIJAwAAAA==.Suplazindh:BAAALgAFFAIJAgABLgAFFAkJUAAbAKgjAA==.',
Sw='Swethort:BAAALgADCgcJBgAAAA==.',
Sy='Synman:BAAALgADCgYJBgAAAA==.Syntheria:BAAALgADCgcJDAAAAA==.Syrebriel:BAABLgAECn8VAAIDAAcJCxEBJABzAQADAAcJCxEBJABzAQAAAA==.',
['Sí']='Sílíbrítí:BAAALgAECgYJDQABLgAFFAMJDAAFAIINAA==.',
Ta='Taediah:BAAALgAFFAEJAQAAAA==.Tamius:BAAALgADCgEJAQAAAA==.Tanthanalas:BAAALgAECgQJBAAAAA==.',
Th='Thefalsehope:BAAALgADCgcJBwAAAA==.Theoutcast:BAAALgAECgQJDgAAAA==.Thesarius:BAABLgAECn8ZAAIiAAgJXxmXDQAxAgAiAAgJXxmXDQAxAgAAAA==.Thortor:BAAALgADCgIJAgABLgADCggJEAAJAAAAAA==.Thumbies:BAAALgAECgMJAwAAAA==.Thumbzie:BAAALgAECgMJAwAAAA==.',
Ti='Tiestto:BAAALgAECgcJDgAAAA==.Tinkermid:BAAALgADCgEJAQAAAA==.Tinymeatgang:BAAALgADCggJCQAAAA==.',
To='Tobalwl:BAAALgADCgUJBQAAAA==.Tockley:BAABLgAECn8kAAIaAAgJYQiwFACPAAAaAAgJYQiwFACPAAAAAA==.Toetagger:BAABLgAECn8eAAIbAAgJ4A/YbgCHAQAbAAgJ4A/YbgCHAQAAAA==.Tofino:BAAALgAECggJDwAAAA==.Tohner:BAAALgADCgMJAwAAAA==.Tolidron:BAAALgADCgEJAQAAAA==.Tonimâster:BAAALgAFFAEJAQAAAA==.Tonydmaster:BAAALgAECgEJAQAAAA==.Toyotama:BAAALgAECgUJDQAAAA==.',
Tr='Trashiepanda:BAABLgAECn8VAAMSAAYJ6QgZHwDUAAASAAYJIggZHwDUAAAbAAUJAwfIAgGoAAAAAA==.Trenbologna:BAAALgAECgEJAQAAAA==.Tristah:BAAALgAECgUJDwABLgAECgcJDwAJAAAAAA==.Truefaith:BAAALgAECgEJAQAAAA==.Trzlawd:BAAALgADCgEJAQAAAA==.',
Ty='Tyindron:BAAALgAECgYJBwAAAA==.Tyrrial:BAABLgAECn8zAAIPAAkJABcPUgDTAQAPAAkJABcPUgDTAQAAAA==.Tyshus:BAAALgAECgYJDQAAAA==.',
Ud='Udntknwme:BAAALgAFFAIJAwAAAA==.',
Un='Unbral:BAAALgADCgEJAQAAAA==.Unicood:BAAALgADCgYJBgAAAA==.Unlockbot:BAAALgADCgEJAwABLgAECgcJDwAJAAAAAA==.Unnicron:BAAALgAECgMJAwAAAA==.Unwholey:BAAALgAECggJCAAAAA==.',
Us='Ussile:BAAALgAECgEJAQAAAA==.',
Ut='Uthgardt:BAAALgAECgYJBgABLgAECgYJCwAJAAAAAA==.',
Va='Valarion:BAABLgAECn8nAAIkAAgJ4RIjFwCiAQAkAAgJ4RIjFwCiAQAAAA==.Valcaryn:BAAALgADCgYJBgAAAA==.Validimus:BAABLgAECn8cAAMPAAgJIQgNtQAYAQAPAAgJdAcNtQAYAQAOAAIJ+QXGTAA6AAAAAA==.Valinis:BAAALgAECgQJBAAAAA==.Valinius:BAAALgADCgYJCQAAAA==.Valorían:BAABLgAECn9MAAQiAAkJjyXYAABmAwAiAAkJjyXYAABmAwAEAAkJYyK0CwCsAgAkAAIJAiAYRAC4AAAAAA==.Valtaa:BAAALgADCgUJBwAAAA==.Vanza:BAAALgADCgEJAQAAAA==.Varthayn:BAABLgAECn9DAAIaAAkJ4iCBGgC7AgAaAAkJ4iCBGgC7AgAAAA==.',
Ve='Vecna:BAAALgAECgMJAwABLgAECgYJCAAJAAAAAA==.Velandriel:BAAALgADCgkJCwABLgAECgkJOwAKAF8ZAA==.Vengfuhl:BAAALgAECgQJAwAAAA==.Verra:BAAALgAECgEJAQAAAA==.Vet:BAAALgAECgEJAQAAAA==.',
Vo='Voidwa:BAAALgAECggJEgAAAA==.Volbain:BAABLgAECn83AAQKAAgJqR2fAQCcAQAKAAgJqR2fAQCcAQAnAAMJARTEAgCPAAAeAAEJ0wKQOAEcAAAAAA==.Volklin:BAABLgAECn8pAAMmAAkJqhTsIQCNAQAmAAkJow7sIQCNAQAMAAcJaRTeTQB/AQAAAA==.Voltagex:BAABLgAECn8dAAIeAAcJfRyAVgCDAQAeAAcJfRyAVgCDAQAAAA==.',
Vu='Vulpsinculta:BAABLgAECn8kAAIdAAgJ6RRSSwC4AQAdAAgJ6RRSSwC4AQAAAA==.',
['Vï']='Vïrùs:BAABLgAECn8sAAIHAAcJ/g+GAwAfAQAHAAcJ/g+GAwAfAQAAAA==.',
Wa='Wanda:BAAALgAECgYJBgAAAA==.',
Wi='Wichita:BAABLgAECn80AAMbAAkJsA9PZACfAQAbAAgJEhFPZACfAQAWAAEJBQZdZgAdAAAAAA==.Wildkitty:BAAALgAFFAEJAQAAAA==.',
Wo='Wolfyze:BAAALgADCgEJAQAAAA==.',
Wr='Wrâth:BAAALgAECgEJAwAAAA==.',
Wt='Wtfamaterasu:BAAALgAECgYJCwAAAA==.Wtfguën:BAABLgAECn8sAAIUAAgJkw0PBgCeAAAUAAgJkw0PBgCeAAAAAA==.Wtftäzmikell:BAAALgADCgYJCQABLgAECggJLAAUAJMNAA==.',
Wu='Wutäng:BAAALgADCgYJCgAAAA==.',
Xe='Xera:BAAALgADCgYJBgAAAA==.',
Xo='Xondra:BAAALgAECgYJDQAAAA==.',
Xr='Xravo:BAAALgADCgkJCQAAAA==.',
Xz='Xzairi:BAABLgAECn8hAAIHAAgJ6hf/JACjAQAHAAgJ6hf/JACjAQAAAA==.',
Ya='Yarria:BAAALgADCgIJAgAAAA==.',
Yi='Yinh:BAAALgADCgcJDAAAAA==.',
Yo='Yoiki:BAAALgAECgEJAQABLgAECgEJAQAJAAAAAA==.',
Yu='Yuck:BAAALgAECgIJBAAAAA==.',
Yy='Yy:BAAALgAECgUJDAAAAA==.',
Ze='Zeuzco:BAAALgAECgkJEQAAAA==.',
Zo='Zorell:BAAALgAECgYJDQAAAA==.Zovaal:BAAALgAECgUJCAAAAA==.',
['Ál']='Áltá:BAABLgAECn8uAAMdAAkJURncJgBCAgAdAAkJURncJgBCAgAhAAIJNwyKMwBSAAAAAA==.',
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
