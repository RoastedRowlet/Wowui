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

local lookup = {'Rogue-Outlaw','Warrior-Fury','Monk-Mistweaver','Monk-Windwalker','Druid-Balance','Evoker-Devastation','Unknown-Unknown','DemonHunter-Havoc','Shaman-Enhancement','Hunter-BeastMastery','Evoker-Preservation','Paladin-Protection','Paladin-Retribution','Shaman-Elemental','Shaman-Restoration','DeathKnight-Frost','Monk-Brewmaster','Druid-Guardian','Druid-Restoration','DeathKnight-Blood','Paladin-Holy','Druid-Feral','Mage-Arcane','Mage-Frost','DeathKnight-Unholy','Priest-Holy','Priest-Shadow','Warlock-Demonology','DemonHunter-Devourer','Rogue-Subtlety','Warlock-Affliction','Warlock-Destruction','Warrior-Protection','Evoker-Augmentation','Warrior-Arms','Hunter-Marksmanship','Hunter-Survival','Priest-Discipline','DemonHunter-Vengeance',}
local provider = {region='US',realm='Misha',name='US',type='weekly',zone=46,date='2026-06-06',data={Ac='Acidburn:BAABLgAECn8WAAIBAAcJ0BroAwDvAQABAAcJ0BroAwDvAQAAAA==.',
Ae='Aea:BAAALgAECgIJBgAAAA==.Aevie:BAAALgAECgYJEgAAAA==.',
Af='Afterlìfe:BAAALgAECgcJEQAAAA==.',
Ai='Ailis:BAAALgADCgQJBAAAAA==.',
Al='Alendria:BAAALgADCgYJBgAAAA==.Alizë:BAAALgADCgQJAwAAAA==.Alluna:BAAALgADCgEJAQAAAA==.Alorillan:BAAALgAECgcJEQAAAA==.Altabrew:BAAALgAECgQJBAAAAA==.Altair:BAAALgAECgUJDwABLgAECgkJIQACABMhAA==.',
An='Andelynn:BAAALgAECgIJAgAAAA==.',
Ap='Applejuic:BAACLgAFFH8FAAIDAAMJtgqVPACRAAADAAMJtgqVPACRAAAuAAQKfxQAAwMACQlKFkoZADsCAAMACQlKFkoZADsCAAQAAQk1EFCYAC0AAAAA.Appless:BAAALgAECgQJBwAAAA==.',
Ar='Araylia:BAABLgAECn8fAAIFAAkJjAz4NAA1AQAFAAkJjAz4NAA1AQAAAA==.Aridella:BAABLgAECn8VAAIGAAYJRA5mEwDIAAAGAAYJRA5mEwDIAAAAAA==.Ariellaa:BAAALgAECgYJBgAAAA==.',
As='Ashaly:BAAALgADCgUJBQAAAA==.Ashlei:BAAALgAECgQJCAAAAA==.',
At='Atomseve:BAAALgADCgQJBAABLgAECggJEwAHAAAAAA==.',
Au='Aurafarmer:BAAALgADCgEJAQAAAA==.Autopsia:BAAALgADCgYJBgABLgAECgkJOQAIANQYAA==.Autumn:BAAALgADCgUJBwAAAA==.',
Av='Avalorne:BAAALgAECgMJAwABLgAECgkJIQACABMhAA==.Avena:BAAALgADCgEJAgAAAA==.',
Az='Azaizel:BAAALgAECgYJCwAAAA==.Azusie:BAABLgAECn81AAIJAAkJehcuCQAfAgAJAAkJehcuCQAfAgAAAA==.',
Ba='Baddate:BAABLgAECn8eAAIKAAcJQQ+AaQBjAQAKAAcJQQ+AaQBjAQAAAA==.Baddragøn:BAABLgAECn84AAMLAAkJBRYHDQD6AQALAAgJ0xUHDQD6AQAGAAgJxg9OCQCIAQAAAA==.Balthaas:BAABLgAECn82AAMMAAkJyhgZCgAeAgAMAAkJyhgZCgAeAgANAAEJewdjUQErAAAAAA==.Bangen:BAAALgAECgcJDwAAAA==.Bastria:BAAALgAECgYJDAAAAA==.Baulters:BAAALgAECgUJBwAAAA==.',
Be='Beenn:BAAALgAECgYJBgAAAA==.',
Bh='Bharko:BAAALgADCgcJCgABLgAFFAYJDgAKADodAA==.',
Bi='Billyblastin:BAAALgADCgMJAwABLgAECgkJJQAOAFgZAA==.Billywitchdr:BAABLgAECn8lAAMOAAkJWBnLFwAXAgAOAAkJWBnLFwAXAgAPAAEJFgaTzwArAAAAAA==.Biocryo:BAAALgADCgYJBgABLgAECggJEAAHAAAAAA==.',
Bl='Blazingpanda:BAAALgAECgMJBAAAAA==.Blizeatsass:BAAALgADCgMJAwAAAA==.Bluedomino:BAAALgAECgMJCAAAAA==.Bluetoykawi:BAABLgAECn8zAAIQAAgJKxZHCwC0AQAQAAgJKxZHCwC0AQAAAA==.',
Bo='Boats:BAAALgADCgIJAgAAAA==.Boltspark:BAAALgADCgMJAwAAAA==.Borgo:BAAALgAECgYJBgAAAA==.Bowlenciaga:BAABLgAECn8WAAIKAAcJLQlMfAA5AQAKAAcJLQlMfAA5AQAAAA==.Bozilla:BAAALgADCgMJAwAAAA==.',
Br='Braelia:BAAALgADCgcJCAAAAA==.Brainfart:BAAALgADCgUJBQABLgAECggJGwAKABcWAA==.Breloom:BAAALgADCgEJAQAAAA==.Bruithis:BAAALgADCgIJAgAAAA==.',
Bu='Burdan:BAAALgADCgQJBAAAAA==.Buttermebuns:BAAALgADCgcJCAAAAA==.',
Ca='Cariandria:BAAALgAECgUJBgAAAA==.',
Cc='Cc:BAAALgAECgEJAgAAAA==.',
Ch='Chahaein:BAAALgAECgYJDwAAAA==.Charbaby:BAAALgAFFAMJAwABLgAFFAUJFwARABYfAA==.Charhartt:BAACLgAFFH8FAAISAAMJJw9xHACZAAASAAMJJw9xHACZAAAuAAQKfxUAAxIABgljFy0eAEkBABIABgljFy0eAEkBABMAAQlXB8zhACMAAAEuAAUUBQkXABEAFh8A.Charita:BAAALgAECgMJBAABLgAFFAUJFwARABYfAA==.Charizard:BAAALgAECgEJAQABLgAFFAUJFwARABYfAA==.Charming:BAACLgAFFH8XAAIRAAUJFh8xGABQAQARAAUJFh8xGABQAQAuAAQKfyAAAhEACAnXGcUcAB0CABEACAnXGcUcAB0CAAAA.Charmonic:BAAALgAECgQJBwABLgAFFAUJFwARABYfAA==.Chelseah:BAAALgAECgYJEAABLgAECgcJDwAHAAAAAA==.',
Ci='Cinderlight:BAAALgAECgEJAQAAAA==.',
Cl='Clanker:BAAALgAECgkJEgAAAA==.Clémentine:BAAALgAECgEJAQAAAA==.',
Co='Coldknight:BAABLgAECn8eAAMQAAcJjQJRJgCHAAAQAAcJWAJRJgCHAAAUAAUJ6AFTSwBWAAAAAA==.Conien:BAAALgADCgQJBAAAAA==.Conifer:BAABLgAECn8WAAITAAcJEhoMKQABAgATAAcJEhoMKQABAgAAAA==.Coniption:BAAALgADCgEJAQAAAA==.Contrlurself:BAAALgAECgYJBgABLgAECgkJJAAFAF4VAA==.Copium:BAAALgAECgQJBwAAAA==.Cornpop:BAAALgAECgYJCgAAAA==.Cowret:BAABLgAECn9BAAMVAAkJ0yFiAgB+AwAVAAkJ0yFiAgB+AwANAAEJAAAzwAEAAAAAAA==.',
Cr='Crystalwolf:BAABLgAECn8VAAIWAAYJiwXsKwCkAAAWAAYJiwXsKwCkAAAAAA==.',
Cu='Curze:BAAALgAECgMJAwAAAA==.',
Cy='Cyonna:BAAALgADCgQJBAAAAA==.',
Da='Darc:BAABLgAECn8XAAICAAQJXCXUPgCpAQACAAQJXCXUPgCpAQAAAA==.Darkfoxgrime:BAAALgAECgkJCQABLgAECgkJJAAEAHkQAA==.Darkjager:BAABLgAECn8rAAIKAAkJHR6bKgAoAgAKAAkJHR6bKgAoAgAAAA==.Darkways:BAAALgAECgcJAQAAAA==.Darlah:BAABLgAECn8hAAIXAAgJqxJBBACtAQAXAAgJqxJBBACtAQAAAA==.Darnalin:BAAALgAECgEJAgABLgAECgkJOQAIANQYAA==.Dayva:BAAALgAECgQJBgAAAA==.Dayyva:BAAALgAECgQJDgAAAA==.',
De='Deadcobra:BAABLgAECn8pAAIYAAkJrASLnwA3AQAYAAkJrASLnwA3AQAAAA==.Deathbean:BAAALgADCgQJBAABLgAECgUJDwAHAAAAAA==.Debtknight:BAABLgAECn84AAIZAAkJ6h/kFADCAgAZAAkJ6h/kFADCAgAAAA==.Deelo:BAAALgAECgEJAQAAAA==.Dehumidifier:BAABLgAECn8oAAMaAAkJlx5qEABWAgAaAAkJlx5qEABWAgAbAAkJQw0/JACfAQAAAA==.Deltria:BAAALgAECgcJEQAAAA==.Demonrot:BAABLgAECn8WAAIcAAgJZAvlcABUAQAcAAgJZAvlcABUAQAAAA==.Dervin:BAAALgADCgQJBAABLgAECggJCAAHAAAAAA==.Deviltank:BAAALgADCgYJDAAAAA==.Devohsup:BAABLgAECn8dAAIdAAgJlB8xHgBVAgAdAAgJlB8xHgBVAgAAAA==.Devussi:BAABLgAECn8mAAIdAAkJyBR/RQCrAQAdAAkJyBR/RQCrAQABLgAECgUJBQAHAAAAAA==.',
Di='Dienva:BAAALgAECgUJBQAAAA==.Digmyearth:BAAALgAECgMJAwAAAA==.Dilea:BAAALgAECgUJBQAAAA==.',
Dk='Dksakp:BAAALgADCgkJGAAAAA==.',
Do='Dominateelf:BAAALgADCgQJBAABLgAECgMJBAAHAAAAAA==.Dotero:BAAALgAECgUJDAAAAA==.',
Dr='Dracreina:BAABLgAECn8oAAMGAAgJmxOUBwC1AQAGAAgJmxOUBwC1AQALAAEJQQbePQAlAAAAAA==.Dreouss:BAAALgAECgQJBgAAAA==.Driver:BAEALgAFFAIJAwABLgAFFAUJDwAcALYLAA==.',
Du='Dumeslayer:BAAALgADCgcJCQAAAA==.Durzoe:BAABLgAECn8WAAIeAAcJlwoFOQBNAQAeAAcJlwoFOQBNAQAAAA==.',
Dv='Dvsmage:BAAALgAECgUJDwAAAA==.',
Eg='Egaik:BAAALgAECgYJBgAAAA==.',
El='Elarred:BAAALgADCgkJFAAAAA==.Elfkr:BAAALgAECgkJAwAAAA==.Elissauna:BAABLgAECn8VAAIYAAkJ/RK5QAAUAgAYAAkJ/RK5QAAUAgAAAA==.Elylea:BAABLgAECn8fAAICAAgJvRohHQD/AQACAAgJvRohHQD/AQAAAA==.',
En='Enorme:BAAALgADCgQJBAAAAA==.',
Eu='Eunice:BAAALgADCgIJAgAAAA==.',
Ez='Ezili:BAAALgAECgEJAQAAAA==.',
Fa='Failure:BAAALgAECgIJAwAAAA==.Falabala:BAAALgAECgQJBAAAAA==.Fanghür:BAAALgADCgcJDgAAAA==.',
Fe='Feeloow:BAAALgADCgcJCwAAAA==.Felhound:BAAALgAECgcJDgAAAA==.Felussi:BAAALgAECgUJBQAAAA==.Feorahir:BAAALgAECgQJBAAAAA==.Fermitorok:BAAALgADCgEJAQAAAA==.',
Ff='Ff:BAAALgAECgQJBAAAAA==.',
Fi='Finhead:BAABLgAECn8zAAIKAAkJXQ7qRwC+AQAKAAkJXQ7qRwC+AQAAAA==.Fionna:BAAALgAECgcJDAAAAA==.Firereina:BAAALgADCggJGQABLgAECggJKAAGAJsTAA==.Fishbone:BAAALgAECgMJAwAAAA==.',
Fl='Fleurminator:BAABLgAECn8gAAICAAkJBxE6LQCWAQACAAkJBxE6LQCWAQAAAA==.Fluffybaby:BAAALgADCgMJAwAAAA==.',
Fo='Fondadix:BAABLgAECn8lAAIUAAkJpyEbCQB6AgAUAAkJpyEbCQB6AgAAAA==.',
Fr='Frieia:BAABLgAECn8cAAITAAgJ3wcSYQAIAQATAAgJ3wcSYQAIAQAAAA==.Frostiilocks:BAAALgAECggJCQAAAA==.Frostitutte:BAAALgAECgYJEQAAAA==.',
Fu='Fuze:BAAALgAECgYJCwAAAA==.',
Ga='Galakrosh:BAACLgAFFH8HAAMfAAMJASGBDACnAAAcAAMJASEVaQDgAAAfAAIJ9B+BDACnAAAuAAQKfyoABB8ACAkYJOYEADQCABwACAlwHT4XAMkCAB8ACAlpIuYEADQCACAAAQkAAIFjAEgAAAAA.Galarína:BAABLgAECn83AAMDAAkJFCKRCwDPAgADAAgJqSGRCwDPAgAEAAkJ8R01CwCGAgAAAA==.Gandora:BAABLgAECn8gAAMZAAkJwxZGSQDfAQAZAAkJwxZGSQDfAQAQAAEJ/wObOwAlAAAAAA==.Gardrius:BAAALgADCgEJAQAAAA==.',
Ge='Gene:BAAALgADCgcJBwAAAA==.Gentonord:BAABLgAECn8cAAMCAAgJJhoDQQChAQACAAgJBRcDQQChAQAhAAYJXBdrIAA9AQAAAA==.',
Gi='Gingerports:BAAALgADCgEJAQAAAA==.',
Gk='Gkmc:BAABLgAFFH8GAAIZAAYJ3gbDRQBWAQAZAAYJ3gbDRQBWAQABLgAFFAgJKAAYANAjAA==.',
Gl='Glomps:BAAALgAFFAMJAwABLgAFFAUJBgAiAFkEAA==.',
Go='Gonaldduck:BAAALgAECgYJBgAAAA==.',
Gr='Greasemunkey:BAABLgAECn8tAAIWAAgJNxIoEQCUAQAWAAgJNxIoEQCUAQAAAA==.Greentea:BAAALgADCggJCwAAAA==.Griiv:BAACLgAFFH8FAAINAAIJBB01fgCZAAANAAIJBB01fgCZAAAuAAQKfyMAAg0ACAnNISEWAOQCAA0ACAnNISEWAOQCAAAA.Grislytotem:BAAALgADCgYJCAAAAQ==.',
Ha='Hakunamatata:BAAALgAECgUJBwAAAA==.Hamburger:BAABLgAECn8ZAAIbAAcJWxUuKgB4AQAbAAcJWxUuKgB4AQAAAA==.Hammerhard:BAAALgADCgYJCgAAAA==.Hampter:BAAALgAECgYJCQABLgAECgkJJQAbAMgaAA==.Hanita:BAAALgAECgEJAgAAAA==.Haymáker:BAAALgADCgIJAgAAAA==.',
He='Heights:BAAALgAECgUJDgAAAA==.Heliosan:BAAALgAECgEJBAAAAA==.Heyu:BAAALgAECgUJCAABLgAECggJGwAKABcWAA==.',
Hi='Himoe:BAAALgADCgcJDgAAAA==.',
Ho='Holybean:BAAALgADCgkJGAABLgAECgUJDwAHAAAAAA==.Holyhench:BAAALgAECgUJBQAAAA==.Honkeykong:BAAALgADCgIJAgAAAA==.Hoochix:BAAALgAECgQJCQAAAA==.',
Hr='Hrsho:BAAALgADCgQJBAAAAA==.Hrshoo:BAAALgAFFAIJAgAAAA==.',
Hu='Humzashaind:BAABLgAECn8dAAMjAAgJOhFFOADYAAACAAcJ4gwcUAD/AAAjAAYJeA9FOADYAAAAAA==.Huntinrabits:BAAALgADCgIJAgAAAA==.Huntt:BAAALgAECgEJAQAAAA==.Huzzyy:BAAALgAECggJCgABLgAECgkJHwAVAN0bAA==.',
Hy='Hyphira:BAAALgAECgQJCgABLgAECgUJDQAHAAAAAA==.',
In='Inferbloom:BAAALgAECggJCAABLgAFFAQJDwAHAAAAAA==.Infernum:BAAALgAFFAQJDwAAAQ==.Insomnia:BAAALgAECgUJBQAAAA==.',
Ir='Irayvia:BAAALgADCgIJAgAAAA==.',
Ja='Jackyvoker:BAABLgAECn8qAAMLAAkJfCLJAQBrAwALAAkJfCLJAQBrAwAGAAMJqRmCJwDlAAAAAA==.Jaezzon:BAAALgADCgQJBwAAAA==.Janessah:BAAALgADCgEJAQAAAA==.',
Je='Jeannaah:BAAALgAECgQJBAABLgAECgcJDwAHAAAAAA==.Jetaime:BAAALgAECgUJBQAAAA==.',
Jh='Jharia:BAAALgADCgMJAgAAAA==.',
Ji='Jinksey:BAAALgAECgcJDQABLgAECgcJEQAdABETAA==.',
Jo='Johndoom:BAAALgAECgYJDgAAAA==.Johnfist:BAAALgAECgEJBAAAAA==.Johngrippy:BAAALgAECgEJAwAAAA==.Johnrend:BAAALgAECgEJAQAAAA==.',
Ju='Juicybottoms:BAAALgADCgMJAgAAAA==.',
Ka='Kairstia:BAAALgAECgMJAwABLgAECggJKAAGAJsTAA==.Kalidormi:BAAALgAECgUJCQAAAA==.Kalzious:BAAALgADCgkJHAAAAA==.Kamikaze:BAAALgAECgcJBQAAAA==.Kayelalynn:BAABLgAECn8kAAMFAAkJXhWCGgDqAQAFAAkJXhWCGgDqAQATAAMJNgEowgBDAAAAAA==.',
Kd='Kd:BAAALgAECgEJAgAAAA==.',
Ke='Kegpaw:BAAALgAFFAEJAQAAAA==.Keiri:BAAALgADCgYJBgAAAA==.Kelana:BAABLgAECn8lAAIRAAkJxB9LCACmAgARAAkJxB9LCACmAgAAAA==.Kendô:BAAALgAECgcJDAAAAA==.Ketdealer:BAAALgAECgcJDQAAAA==.Ketzendk:BAAALgAECgYJBQAAAA==.Keyahi:BAACLgAFFH8RAAIdAAUJ+RmrNQA4AQAdAAUJ+RmrNQA4AQAuAAQKfx0AAh0ACQk0HDohAEMCAB0ACQk0HDohAEMCAAEuAAQKAQkBAAcAAAAA.',
Kh='Khaean:BAAALgADCgkJCQAAAA==.Khety:BAAALgAECgQJBAAAAA==.',
Ki='Kickandpunch:BAAALgAECgYJDgAAAA==.Kicsi:BAAALgAECgIJAwAAAA==.Kilan:BAABLgAECn8gAAMNAAgJXRRkdwB0AQANAAcJjhNkdwB0AQAMAAIJNBgDNACFAAAAAA==.Killinrage:BAAALgAECgYJDgAAAA==.Kissofpaine:BAAALgADCgIJAgAAAA==.Kitsuney:BAAALgADCgMJAwAAAA==.Kizaru:BAAALgAECgcJCAAAAA==.',
Ko='Korz:BAAALgADCgcJBwABLgAECgcJFQAYAOEXAA==.',
Kp='Kpop:BAAALgAECgEJAQAAAA==.',
Kr='Krutree:BAAALgAECgcJCQAAAA==.Krynj:BAAALgAFFAEJAwAAAA==.',
Ku='Kumokiri:BAAALgAECgIJAgAAAA==.Kuromu:BAAALgAFFAIJBAAAAA==.Kurzzon:BAAALgADCgMJAwAAAA==.',
Ky='Kyleata:BAABLgAECn85AAIKAAgJIR41LAAhAgAKAAgJIR41LAAhAgAAAA==.Kyleigh:BAAALgAECgQJBQABLgAECgcJDwAHAAAAAA==.Kyokin:BAABLgAECn82AAMNAAkJ+BQJQgD2AQANAAgJOBcJQgD2AQAMAAgJ8AYPMACaAAAAAA==.Kyzula:BAABLgAECn8mAAIPAAcJTBY/NgDKAQAPAAcJTBY/NgDKAQAAAA==.',
['Kê']='Kêndo:BAAALgAECgEJAgAAAA==.',
La='Lace:BAAALgADCgMJAwAAAA==.Launam:BAAALgAECgEJAQAAAA==.Laytone:BAAALgADCgYJBwAAAA==.',
Le='Legcurl:BAAALgAECgEJAwAAAA==.Lepotko:BAAALgAECgQJBAAAAA==.',
Li='Lightbear:BAAALgADCgMJBQAAAA==.Lilchub:BAAALgAECgIJAwAAAA==.Lilylocks:BAAALgAECgcJCQAAAA==.Lilyrocks:BAAALgAECgUJCQAAAA==.Literallad:BAAALgADCgcJBgAAAA==.Littlelo:BAAALgAECgYJDAAAAA==.',
Ll='Llortdnaz:BAAALgADCgEJAgAAAA==.',
Lo='Lockology:BAAALgAFFAEJAQAAAA==.Lokarg:BAAALgADCgIJAgAAAA==.Loudcry:BAACLgAFFH8IAAIXAAQJJxQBAQA4AQAXAAQJJxQBAQA4AQAuAAQKfzMAAxcACQlvHrQBAKkCABcACAkAIbQBAKkCABgAAwm0EOXxALgAAAEuAAUUBQkLAAIAmxwA.',
Lu='Lunaeria:BAAALgADCggJCAAAAA==.',
Ly='Lyanah:BAACLgAFFH8cAAITAAUJXgljJwAZAQATAAUJXgljJwAZAQAuAAQKfywAAhMACQm3FvkiACgCABMACQm3FvkiACgCAAAA.Lydia:BAAALgADCgQJBAAAAA==.Lyniah:BAAALgAECgQJBQAAAA==.',
Ma='Machete:BAAALgAECgQJCQAAAA==.Maelius:BAABLgAECn8yAAIVAAkJRhvxDAC3AgAVAAkJRhvxDAC3AgAAAA==.Maggrus:BAABLgAECn8bAAIKAAgJFxZ8UACkAQAKAAgJFxZ8UACkAQAAAA==.Malavel:BAAALgADCggJCAAAAA==.Malically:BAABLgAECn8gAAMkAAkJaRCREQA1AQAkAAgJghGREQA1AQAKAAYJ7QuVjAAZAQAAAA==.Manshoon:BAAALgADCgcJCwAAAA==.Marlory:BAAALgADCgUJBQAAAA==.Math:BAAALgAFFAEJAQABLgAFFAYJCwAiAAYPAA==.Matheney:BAABLgAFFH8QAAISAAcJCA6KBACnAQASAAcJCA6KBACnAQABLgAFFAYJCwAiAAYPAA==.Maxnem:BAAALgADCggJCAABLgAECggJHwAFADMPAA==.',
Mc='Mcrib:BAAALgADCggJBQAAAA==.Mctubby:BAAALgADCgUJBQABLgADCgUJBgAHAAAAAA==.Mctubmonk:BAAALgADCgUJBgAAAA==.',
Me='Meatpopsicle:BAAALgADCgEJAQAAAA==.Meigz:BAAALgAECgQJCwAAAA==.Melicious:BAAALgAECgQJBAAAAA==.Melidin:BAAALgAECgkJEgAAAA==.Melinda:BAAALgAFFAEJAQAAAA==.Melindorei:BAAALgAECgEJAgAAAA==.Melledrus:BAAALgAECgEJAQAAAA==.Mememo:BAAALgAECgMJAwAAAA==.Menöpaws:BAEALgAFFAMJAwAAAA==.Merithrá:BAAALgAECgMJAwAAAA==.',
Mi='Mikaeljayfox:BAAALgAECgcJDwAAAQ==.Mikros:BAAALgAECgMJAwAAAA==.Milenzha:BAABLgAECn8kAAIKAAgJNBZMQwDMAQAKAAgJNBZMQwDMAQAAAA==.Milkymaiden:BAAALgADCgMJBQABLgADCgYJCQAHAAAAAA==.Mimachote:BAABLgAECn8VAAISAAkJMg4HGgBsAQASAAkJMg4HGgBsAQAAAA==.',
Mo='Monetta:BAAALgADCgIJAgAAAA==.Monk:BAAALgAECggJEAAAAA==.Moonblood:BAAALgADCggJEAAAAA==.Moonfighter:BAAALgAECgEJAgAAAA==.Moontann:BAAALgADCgkJIAAAAA==.Morcombe:BAAALgAECgEJAQAAAA==.Moreia:BAAALgADCgcJBwAAAA==.Motown:BAAALgAECgYJCwAAAA==.Mousse:BAAALgAECgYJEgAAAA==.',
Mu='Murdalok:BAABLgAECn8ZAAITAAgJshWdNQDSAQATAAgJshWdNQDSAQAAAA==.',
My='Mysharona:BAAALgAECgEJAQAAAA==.Mystahmurdah:BAAALgADCgQJBwABLgAECgcJFQAlAM4TAA==.Mysterioñ:BAAALgAECgQJDQAAAA==.',
['Má']='Mákla:BAAALgAECgMJAwAAAA==.',
['Mâ']='Mâstermînd:BAAALgAECgUJDgAAAA==.',
Na='Nahte:BAAALgADCgYJCQAAAA==.Naiana:BAAALgADCgMJAwAAAA==.Nasine:BAAALgAECgYJCAABLgAECgkJGgAOAO0dAA==.Natstryker:BAABLgAECn9AAAQRAAkJGyZ7AAB7AwARAAkJGyZ7AAB7AwAEAAgJ8CJMFQBCAgADAAcJMRF9PgBbAQAAAA==.Naturemyth:BAAALgAFFAEJAwAAAA==.Nazu:BAAALgADCgUJCgAAAA==.',
Ne='Neeró:BAABLgAECn8iAAMdAAYJphXrdgAmAQAdAAYJphXrdgAmAQAIAAEJtxSXXwA+AAAAAA==.Nelthon:BAAALgADCgYJBgAAAA==.',
Ni='Nishastraza:BAAALgAECgEJAwABLgAECgcJDwAHAAAAAA==.',
No='Nonaha:BAAALgADCgkJEQAAAA==.Notsoda:BAAALgAECgQJCQAAAA==.',
Nu='Nuciferas:BAAALgADCgUJBQAAAA==.',
Oa='Oaf:BAAALgAECgYJBgAAAA==.',
Om='Omcmoneyshot:BAAALgADCgEJAQAAAA==.',
Oo='Oolong:BAAALgAECgQJBQAAAA==.',
Or='Organa:BAABLgAECn8jAAICAAgJoApbOwBQAQACAAgJoApbOwBQAQAAAA==.',
Ou='Outofthedark:BAAALgAECgIJAgAAAA==.',
Pa='Pakkan:BAAALgAECgEJAQAAAA==.Pallyqb:BAAALgADCgEJAQAAAA==.Pandariam:BAAALgAECgYJCgAAAA==.Pauladeenx:BAAALgAECgIJAwABLgAECgUJDgAHAAAAAA==.',
Pe='Petal:BAAALgAECgYJBwABLgAECggJEAAHAAAAAA==.',
Pl='Playwitwe:BAAALgAECgQJBwAAAA==.Plowmcballs:BAABLgAECn8ZAAINAAYJtxIzfgB+AQANAAYJtxIzfgB+AQAAAA==.Plugley:BAABLgAECn8dAAMYAAkJqBguOAAxAgAYAAkJqBguOAAxAgAXAAEJARSGHAA6AAAAAA==.',
Po='Polaris:BAAALgAECgEJAQAAAA==.Poober:BAABLgAECn8fAAMaAAkJbx9zCwCjAgAaAAgJeCFzCwCjAgAmAAIJixX6VQCSAAAAAA==.Potooòooóoo:BAABLgAECn8dAAIQAAcJVhj2EwAwAQAQAAcJVhj2EwAwAQAAAA==.',
Pr='Pren:BAAALgAFFAEJAQAAAA==.Privet:BAAALgAECgEJAwAAAA==.',
Pu='Purebeef:BAAALgAECgIJAgAAAA==.',
Py='Pygos:BAABLgAECn8ZAAInAAgJ5BiJBwANAgAnAAgJ5BiJBwANAgAAAA==.',
['Pë']='Përdü:BAAALgAECgcJEQAAAA==.',
Qu='Quigglay:BAAALgAECgYJBgAAAA==.',
Ra='Raegnarok:BAABLgAECn8hAAIVAAgJ/hNJIQDuAQAVAAgJ/hNJIQDuAQAAAA==.Raelessa:BAAALgAECgQJCQABLgAECgcJDwAHAAAAAA==.Raigeki:BAAALgADCgQJBQAAAA==.Ralf:BAAALgAECgEJAQAAAA==.Ralphie:BAAALgAECgIJAgAAAA==.Ratapew:BAABLgAECn8UAAIdAAcJchWsYwBUAQAdAAcJchWsYwBUAQAAAA==.Ratheen:BAABLgAECn8dAAINAAgJtA5dkgBCAQANAAgJtA5dkgBCAQAAAA==.Raytar:BAABLgAECn8gAAMFAAkJNB82DwBhAgAFAAgJPyA2DwBhAgATAAMJ9RsBmwCWAAAAAA==.',
Re='Rekkirin:BAAALgAECgUJBQABLgAECgkJOAALAAUWAA==.Relyk:BAAALgADCgUJBQAAAA==.',
Ri='Riyo:BAAALgAFFAIJAwAAAA==.',
Ro='Roachie:BAAALgAECgYJDgAAAA==.Rockandstone:BAAALgADCgEJAQAAAA==.Roesira:BAAALgAECgEJAQAAAA==.Rogun:BAAALgAECgkJAQAAAA==.Ros:BAAALgAECgMJBAAAAA==.',
Ru='Rug:BAAALgADCgYJBgAAAA==.Rustybray:BAABLgAECn81AAIOAAkJhgfEPgApAQAOAAkJhgfEPgApAQAAAA==.Ruu:BAAALgAECgkJBQABLgAFFAQJDgAlAAQRAA==.',
Ry='Ryvulz:BAABLgAECn8eAAIbAAgJHRWsGAAcAgAbAAgJHRWsGAAcAgAAAA==.',
Sa='Salomicum:BAAALgADCgEJAQAAAA==.Sappollo:BAAALgADCgMJAwAAAA==.Sarabi:BAABLgAECn8jAAIDAAgJlBUqJADqAQADAAgJlBUqJADqAQAAAA==.Sarena:BAAALgADCgMJAwAAAA==.Sarkoth:BAAALgADCgEJAQAAAA==.',
Sc='Schnee:BAAALgADCgYJCgAAAA==.Schutzhund:BAAALgAECgMJAgAAAA==.Scrapster:BAAALgAECgUJCwAAAA==.',
Se='Seifer:BAAALgADCgEJAQAAAA==.Sekha:BAAALgAECgQJBgABLgAECggJIQAFAOoXAA==.Serbero:BAAALgAECgEJAQAAAA==.Seshiro:BAAALgAECgQJBAABLgAECgkJNQAMANkjAA==.',
Sh='Shadoweave:BAACLgAFFH8aAAMaAAUJ9BfJDQBZAQAaAAUJ9BfJDQBZAQAbAAIJSA3PKwCGAAAuAAQKfxkAAhoACQkoGCYSAEECABoACQkoGCYSAEECAAAA.Shalalia:BAABLgAECn8ZAAIKAAcJNw4sbABcAQAKAAcJNw4sbABcAQAAAA==.Shambean:BAAALgADCgEJAQABLgAECgUJDwAHAAAAAA==.Shammywitch:BAAALgAFFAEJAQABLgAECgMJCQAHAAAAAA==.Shentsu:BAABLgAECn8YAAIDAAkJ0CD7BQD/AgADAAkJ0CD7BQD/AgAAAA==.Shhanks:BAAALgAECgEJAQAAAA==.Shinmen:BAAALgADCgkJCQAAAA==.Shinsha:BAAALgADCgIJAwAAAA==.Shnizelnazee:BAABLgAECn8WAAINAAgJDwxuqQAdAQANAAgJDwxuqQAdAQAAAA==.Shortonheals:BAAALgAECgMJAwAAAA==.',
Si='Siege:BAAALgAECgUJBQAAAA==.Silie:BAAALgADCgEJAQAAAA==.Silik:BAAALgADCgcJBwAAAA==.Simpforsale:BAAALgAECgYJCQAAAA==.',
Sk='Skybladee:BAAALgAECgIJAgAAAA==.',
Sm='Smokeyb:BAACLgAFFH8GAAINAAIJkQqujgCCAAANAAIJkQqujgCCAAAuAAQKfywAAg0ACAlrFvFSAMYBAA0ACAlrFvFSAMYBAAAA.',
Sn='Sneevie:BAAALgAECggJCgAAAA==.Snorehees:BAABLgAECn8sAAMKAAkJwQ8QRwDAAQAKAAkJwQ8QRwDAAQAkAAQJMwLYMwBEAAAAAA==.',
So='Songarrow:BAAALgAECgYJBgAAAA==.Songstar:BAABLgAECn8qAAIKAAkJaiNdDgDUAgAKAAkJaiNdDgDUAgAAAA==.Soullraven:BAAALgADCgkJMAAAAA==.',
Sp='Spy:BAAALgAECgEJBQAAAA==.',
Sq='Squingledorf:BAAALgAECgMJAwAAAA==.',
St='Staavon:BAABLgAECn8jAAIYAAgJBQh2lgBGAQAYAAgJBQh2lgBGAQAAAA==.Stacy:BAAALgAECgEJAQABLgAECgQJCAAHAAAAAA==.Stalvis:BAAALgADCgUJBQAAAA==.Starblaze:BAAALgAECgYJCQAAAA==.Starseek:BAABLgAECn8VAAInAAcJLhDLEABDAQAnAAcJLhDLEABDAQAAAA==.Steelboats:BAAALgADCgkJGQAAAA==.',
Su='Sugarbow:BAAALgADCgMJAwAAAA==.Sugarhoof:BAAALgAECgMJAwAAAA==.Sugarlick:BAABLgAECn8jAAIUAAgJPRsBFgCvAQAUAAgJPRsBFgCvAQAAAA==.Sugarpop:BAACLgAFFH8GAAIVAAMJNw37MACkAAAVAAMJNw37MACkAAAuAAQKfygAAhUACQnXHIISAH4CABUACQnXHIISAH4CAAEuAAUUBAkKAA8ApBsA.Sunraku:BAAALgAECgIJAwAAAA==.Suplazindh:BAAALgAFFAIJAgABLgAFFAkJPQAQAJIhAA==.',
Sw='Swethort:BAAALgADCgcJBgAAAA==.',
Sy='Synman:BAAALgADCgYJBgAAAA==.Syntheria:BAAALgADCgcJCQAAAA==.Syrebriel:BAABLgAECn8VAAImAAcJCxEBJABzAQAmAAcJCxEBJABzAQAAAA==.',
['Sí']='Sílíbrítí:BAAALgAECgYJDQABLgAFFAMJBwADAIIIAA==.',
Ta='Taediah:BAAALgAECgcJDQAAAA==.Tamius:BAAALgADCgEJAQAAAA==.Tanthanalas:BAAALgAECgEJAQAAAA==.',
Th='Thefalsehope:BAAALgADCgcJBwAAAA==.Theoutcast:BAAALgAECgQJDgAAAA==.Thesarius:BAABLgAECn8ZAAIhAAgJXxmXDQAxAgAhAAgJXxmXDQAxAgAAAA==.Thortor:BAAALgADCgIJAgABLgADCggJEAAHAAAAAA==.Thumbzie:BAAALgADCgEJAQAAAA==.',
Ti='Tiestto:BAAALgAECgcJDgAAAA==.Tinkermid:BAAALgADCgEJAQAAAA==.Tinymeatgang:BAAALgADCggJCQAAAA==.',
To='Tobalwl:BAAALgADCgUJBQAAAA==.Tockley:BAABLgAECn8hAAIYAAgJQwZV4QAyAQAYAAgJQwZV4QAyAQAAAA==.Toetagger:BAABLgAECn8YAAIZAAgJaA0mrQAPAQAZAAgJaA0mrQAPAQAAAA==.Tofino:BAAALgAECgcJDgAAAA==.Tohner:BAAALgADCgMJAwAAAA==.Tolidron:BAAALgADCgEJAQAAAA==.Tonimâster:BAAALgAFFAEJAQAAAA==.Tonydmaster:BAAALgAECgEJAQAAAA==.Toyotama:BAAALgAECgUJDQAAAA==.',
Tr='Trashiepanda:BAAALgAECgUJDgAAAA==.Trenbologna:BAAALgAECgEJAQAAAA==.Tristah:BAAALgAECgUJDwABLgAECgcJDwAHAAAAAA==.Trzlawd:BAAALgADCgEJAQAAAA==.',
Ty='Tyindron:BAAALgAECgYJBwAAAA==.Tyrrial:BAABLgAECn8uAAINAAgJbRckTwDQAQANAAgJbRckTwDQAQAAAA==.Tyshus:BAAALgAECgYJDQAAAA==.',
Ud='Udntknwme:BAAALgAFFAIJAwAAAA==.',
Un='Unbral:BAAALgADCgEJAQAAAA==.Unicood:BAAALgADCgYJBgAAAA==.Unlockbot:BAAALgADCgEJAwABLgAECgcJDwAHAAAAAA==.Unwholey:BAAALgAECggJCAAAAA==.',
Ut='Uthgardt:BAAALgAECgYJBgABLgAECgYJCwAHAAAAAA==.',
Va='Valarion:BAABLgAECn8mAAIjAAgJ4RLNFQCkAQAjAAgJ4RLNFQCkAQAAAA==.Valcaryn:BAAALgADCgYJBgAAAA==.Validimus:BAABLgAECn8aAAMNAAgJnQdZqgAbAQANAAgJ8AZZqgAbAQAMAAIJ+QXdSAA6AAAAAA==.Valinis:BAAALgAECgQJBAAAAA==.Valinius:BAAALgADCgYJCQAAAA==.Valorían:BAABLgAECn9AAAQhAAkJayTJAQAzAwAhAAkJiSPJAQAzAwACAAkJ+iGLCgC0AgAjAAIJAiBDQAC5AAAAAA==.Valtaa:BAAALgADCgUJBwAAAA==.Vanza:BAAALgADCgEJAQAAAA==.Varthayn:BAABLgAECn9DAAIYAAkJ4iBeGADBAgAYAAkJ4iBeGADBAgAAAA==.',
Ve='Vecna:BAAALgAECgMJAwABLgAECgYJCAAHAAAAAA==.Velandriel:BAAALgADCgkJCwABLgAECgkJOQAIANQYAA==.Vengfuhl:BAAALgAECgQJAwAAAA==.Verra:BAAALgAECgEJAQAAAA==.Vet:BAAALgAECgEJAQAAAA==.',
Vo='Voidwa:BAAALgAECgYJDgAAAA==.Volbain:BAABLgAECn8tAAQIAAgJmhsTEAAWAgAIAAgJmhsTEAAWAgAnAAMJ5BG+HQCgAAAdAAEJ0wKeJwEcAAAAAA==.Volklin:BAABLgAECn8pAAMlAAkJqhSmIACTAQAlAAkJow6mIACTAQAKAAcJaRTeTQB/AQAAAA==.Voltagex:BAABLgAECn8dAAIdAAcJfRwUUgCEAQAdAAcJfRwUUgCEAQAAAA==.',
Vu='Vulpsinculta:BAABLgAECn8kAAIcAAgJ6RQ9RwDAAQAcAAgJ6RQ9RwDAAQAAAA==.',
['Vï']='Vïrùs:BAABLgAECn8jAAIFAAcJeg1aPABDAQAFAAcJeg1aPABDAQAAAA==.',
Wa='Wanda:BAAALgAECgYJBgAAAA==.',
Wi='Wichita:BAABLgAECn80AAMZAAkJsA+zXACpAQAZAAgJEhGzXACpAQAUAAEJBQavXwAgAAAAAA==.Wildkitty:BAAALgAFFAEJAQAAAA==.',
Wo='Wolfyze:BAAALgADCgEJAQAAAA==.',
Wr='Wrâth:BAAALgAECgEJAgAAAA==.',
Wt='Wtfartemis:BAAALgAECgQJBAAAAA==.Wtfguën:BAABLgAECn8pAAISAAgJ7gvVJwAFAQASAAgJ7gvVJwAFAQAAAA==.Wtftäzmikell:BAAALgADCgYJCQABLgAECggJKQASAO4LAA==.',
Wu='Wutäng:BAAALgADCgYJCgAAAA==.',
Xe='Xera:BAAALgADCgYJBgAAAA==.',
Xo='Xondra:BAAALgAECgYJDQAAAA==.',
Xr='Xravo:BAAALgADCgkJCQAAAA==.',
Xz='Xzairi:BAABLgAECn8hAAIFAAgJ6hfnIgCkAQAFAAgJ6hfnIgCkAQAAAA==.',
Ya='Yarria:BAAALgADCgIJAgAAAA==.',
Yi='Yinh:BAAALgADCgcJDAAAAA==.',
Yo='Yoiki:BAAALgAECgEJAQABLgAECgEJAQAHAAAAAA==.',
Yu='Yuck:BAAALgAECgIJBAAAAA==.',
Yy='Yy:BAAALgAECgUJDAAAAA==.',
Ze='Zeuzco:BAAALgAECgkJEQAAAA==.',
Zo='Zorell:BAAALgAECgYJDAAAAA==.Zovaal:BAAALgADCgYJBgAAAA==.',
['Ál']='Áltá:BAABLgAECn8uAAMcAAkJURkSJABKAgAcAAkJURkSJABKAgAgAAIJNwwiMABUAAAAAA==.',
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
