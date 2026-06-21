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
local provider = {region='US',realm='Misha',name='US',type='weekly',zone=46,date='2026-06-20',data={Ac='Acidburn:BAABLgAECn8WAAIBAAcJ0BroAwDvAQABAAcJ0BroAwDvAQAAAA==.',
Ae='Aea:BAAALgAECgIJCQAAAA==.Aevie:BAABLgAECn8WAAMCAAYJdRCCNQAtAQACAAYJdRCCNQAtAQADAAMJqgsUXgCGAAAAAA==.',
Af='Afterlìfe:BAAALgAECggJEgAAAA==.',
Ai='Ailis:BAAALgADCgQJBAAAAA==.',
Al='Alendria:BAAALgADCgYJBgAAAA==.Alizë:BAAALgADCgQJAwAAAA==.Alluna:BAAALgADCgEJAQAAAA==.Alorillan:BAAALgAECggJEgAAAA==.Altabrew:BAAALgAECgQJBAAAAA==.Altair:BAAALgAECgUJDwABLgAECgkJIQAEABMhAA==.',
An='Andelynn:BAAALgAECgIJAgAAAA==.',
Ap='Applejuic:BAACLgAFFH8IAAIFAAMJtgqFCABpAAAFAAMJtgqFCABpAAAuAAQKfxQAAwUACQlKFlYbAD0CAAUACQlKFlYbAD0CAAYAAQk1EKGiAC4AAAAA.Appless:BAAALgAECgQJBwAAAA==.',
Ar='Araylia:BAABLgAECn8hAAIHAAkJgw3KNABFAQAHAAkJgw3KNABFAQAAAA==.Aridella:BAABLgAECn8VAAIIAAYJRA5MFADIAAAIAAYJRA5MFADIAAAAAA==.Ariellaa:BAAALgAECgYJBgAAAA==.Artamayis:BAAALgAECgYJCgAAAA==.',
As='Ashaly:BAAALgADCgUJBQAAAA==.Ashlei:BAAALgAECgQJCAAAAA==.',
At='Atomseve:BAAALgADCgQJBAABLgAECggJEwAJAAAAAA==.',
Au='Aurafarmer:BAAALgADCgEJAQAAAA==.Autopsia:BAAALgADCgYJBgABLgAECgkJOgAKANQYAA==.Autumn:BAAALgADCgUJBwAAAA==.',
Av='Avalorne:BAAALgAECgMJAwABLgAECgkJIQAEABMhAA==.Avena:BAAALgADCgEJAwAAAA==.',
Az='Azaizel:BAAALgAECgYJCwAAAA==.Azusie:BAABLgAECn88AAILAAkJ3BhUAACnAQALAAkJ3BhUAACnAQAAAA==.',
Ba='Baddate:BAABLgAECn8lAAIMAAcJrxCpbABoAQAMAAcJrxCpbABoAQAAAA==.Baddragøn:BAABLgAECn84AAMNAAkJBRZ7DQD4AQANAAgJ0xV7DQD4AQAIAAgJxg/QCQCHAQAAAA==.Balthaas:BAABLgAECn89AAMOAAkJyhh0AACZAQAOAAkJyhh0AACZAQAPAAEJewdjUQErAAAAAA==.Bangen:BAAALgAECgcJDwAAAA==.Bastria:BAAALgAECgYJDAAAAA==.Baulters:BAAALgAECgYJCAAAAA==.',
Be='Beenn:BAAALgAECgYJBgAAAA==.',
Bh='Bharko:BAAALgADCgcJCgABLgAFFAcJEAAMABkZAA==.',
Bi='Billyblastin:BAAALgAECgMJAwABLgAECgkJJQAQAFgZAA==.Billywitchdr:BAABLgAECn8lAAMQAAkJWBl6GQAWAgAQAAkJWBl6GQAWAgARAAEJFgbe3AArAAAAAA==.Biocryo:BAAALgADCgYJBgABLgAECggJEAAJAAAAAA==.',
Bl='Blazingpanda:BAAALgAECgMJBAAAAA==.Blizeatsass:BAAALgADCgMJAwAAAA==.Bluedomino:BAAALgAECgMJCAAAAA==.Bluetoykawi:BAACLgAFFH8HAAISAAQJUwSpFQDcAAASAAQJUwSpFQDcAAAuAAQKfz4AAhIACQloFVkIAAkCABIACQloFVkIAAkCAAAA.',
Bo='Boats:BAAALgADCgIJAgAAAA==.Boltspark:BAAALgADCgMJAwAAAA==.Borgo:BAAALgAECgYJBgAAAA==.Bowlenciaga:BAABLgAECn8gAAIMAAgJyQqUZgB3AQAMAAgJyQqUZgB3AQAAAA==.Bozilla:BAAALgADCgMJAwAAAA==.',
Br='Braelia:BAAALgADCgcJCAAAAA==.Brainfart:BAAALgADCgUJBQABLgAECggJGwAMABcWAA==.Breloom:BAAALgADCgEJAQAAAA==.Bruithis:BAAALgADCgIJAgAAAA==.',
Bu='Burdan:BAAALgADCgQJBAAAAA==.Buttermebuns:BAAALgADCgcJCAAAAA==.Buttfish:BAAALgAECgIJAgABLgAECgYJCwAJAAAAAA==.',
Ca='Cariandria:BAAALgAECgUJBgAAAA==.',
Cc='Cc:BAAALgAECgEJAgAAAA==.',
Ch='Chahaein:BAAALgAECgYJDwAAAA==.Charbaby:BAAALgAFFAMJAwABLgAFFAYJGAATAEYZAA==.Charhartt:BAACLgAFFH8FAAIUAAMJJw+DIgCSAAAUAAMJJw+DIgCSAAAuAAQKfxUAAxQABgljF7ogAEkBABQABgljF7ogAEkBABUAAQlXB5PpACMAAAEuAAUUBgkYABMARhkA.Charita:BAAALgAECgMJBAABLgAFFAYJGAATAEYZAA==.Charitard:BAAALgAECgEJAQABLgAFFAYJGAATAEYZAA==.Charizard:BAAALgAECgEJAQABLgAFFAYJGAATAEYZAA==.Charming:BAACLgAFFH8YAAITAAYJRhnKGwBJAQATAAYJRhnKGwBJAQAuAAQKfyIAAhMACQmkG4kaANEBABMACQmkG4kaANEBAAAA.Charmonic:BAAALgAFFAIJAgABLgAFFAYJGAATAEYZAA==.Chelseah:BAAALgAECgYJEAABLgAECgcJDwAJAAAAAA==.Christinè:BAAALgAECgUJBQAAAA==.',
Ci='Cidearthen:BAAALgADCgEJAQAAAA==.Cinderlight:BAAALgAECgEJAQAAAA==.',
Cl='Clanker:BAAALgAECgkJEgAAAA==.Clémentine:BAAALgAECgEJAgAAAA==.',
Co='Coldknight:BAABLgAECn8lAAMWAAcJzwIrAwBhAAASAAcJWAI2KgCDAAAWAAUJewIrAwBhAAAAAA==.Conien:BAAALgADCgQJBAAAAA==.Conifer:BAABLgAECn8YAAIVAAcJkBqRKgABAgAVAAcJkBqRKgABAgAAAA==.Coniption:BAAALgADCgEJAQAAAA==.Contrlurself:BAAALgAECgcJCgABLgAECgkJKwAHALsXAA==.Copium:BAAALgAECgQJBwAAAA==.Cornpop:BAAALgAECgYJEQAAAA==.Cowret:BAABLgAECn9DAAMXAAkJdCQ6AQC0AwAXAAkJdCQ6AQC0AwAPAAEJAAAJ2gEAAAAAAA==.',
Cr='Crystalwolf:BAABLgAECn8VAAIYAAYJiwXVLwCjAAAYAAYJiwXVLwCjAAAAAA==.',
Cu='Curze:BAAALgAECgMJAwAAAA==.',
Cy='Cyonna:BAAALgADCgQJBAAAAA==.',
Da='Darc:BAABLgAECn8YAAIEAAQJXSXUPgCpAQAEAAQJXSXUPgCpAQAAAA==.Darkfoxgrime:BAAALgAECgkJDQABLgAECgkJKwAGAKYQAA==.Darkjager:BAABLgAECn8rAAIMAAkJHR5lLwAfAgAMAAkJHR5lLwAfAgAAAA==.Darkways:BAAALgAECgcJAQAAAA==.Darlah:BAABLgAECn8sAAIZAAkJIBahAgAgAgAZAAkJIBahAgAgAgAAAA==.Darnalin:BAAALgAECgEJAgABLgAECgkJOgAKANQYAA==.Dayva:BAAALgAECgQJBgAAAA==.Dayyva:BAAALgAECgQJDgAAAA==.',
De='Deadcobra:BAABLgAECn8pAAIaAAkJrATtpwAuAQAaAAkJrATtpwAuAQAAAA==.Deathbean:BAAALgADCgQJBAABLgAECgUJDwAJAAAAAA==.Debtknight:BAABLgAECn84AAIbAAkJ6h8IFwC9AgAbAAkJ6h8IFwC9AgAAAA==.Deelo:BAAALgAECgYJCQAAAA==.Dehumidifier:BAABLgAECn8zAAMcAAkJQw3QJwCQAQAcAAkJQw3QJwCQAQACAAkJbR/fAAB5AQAAAA==.Deltria:BAAALgAECggJEgAAAA==.Demonrot:BAABLgAECn8XAAIdAAgJZAsFeABJAQAdAAgJZAsFeABJAQAAAA==.Dervin:BAAALgAECgQJBAABLgAECggJCAAJAAAAAA==.Deviltank:BAAALgADCgYJDAAAAA==.Devohsup:BAABLgAECn8dAAIeAAgJlB8BIABVAgAeAAgJlB8BIABVAgAAAA==.Devussi:BAABLgAECn8mAAIeAAkJyBTcSACsAQAeAAkJyBTcSACsAQABLgAECgcJDAAJAAAAAA==.',
Di='Dienva:BAAALgAECgUJBQAAAA==.Digmyearth:BAAALgAECgUJCAAAAA==.Dilea:BAAALgAECggJCQAAAA==.Discoffee:BAAALgADCgYJBgABLgADCgcJEAAJAAAAAA==.',
Dk='Dksakp:BAAALgADCgkJGAAAAA==.',
Do='Dominateelf:BAAALgADCgQJBAABLgAECgMJBAAJAAAAAA==.Dotero:BAABLgAECn8UAAIXAAcJ5hH9AABfAQAXAAcJ5hH9AABfAQAAAA==.',
Dr='Dracreina:BAABLgAECn8oAAMIAAgJmxMYCACyAQAIAAgJmxMYCACyAQANAAEJQQaGQAAlAAAAAA==.Dreouss:BAAALgAECgQJBgAAAA==.Driver:BAAALgAFFAIJAwABLgAFFAUJDwAdALYLAA==.',
Du='Dumeslayer:BAAALgADCgcJCQAAAA==.Durzoe:BAABLgAECn8WAAIfAAcJlwoFOQBNAQAfAAcJlwoFOQBNAQAAAA==.',
Dv='Dvsmage:BAAALgAECgUJDwAAAA==.',
Eg='Egaik:BAAALgAECgcJBwAAAA==.',
El='Elarred:BAAALgADCgkJFAAAAA==.Elfkr:BAAALgAECgkJBgAAAA==.Elissauna:BAABLgAECn8VAAIaAAkJ/RLCRQAKAgAaAAkJ/RLCRQAKAgAAAA==.Elylea:BAABLgAECn8gAAIEAAgJBBxNHwD0AQAEAAgJBBxNHwD0AQAAAA==.',
En='Enorme:BAAALgADCgQJBAAAAA==.',
Eu='Eunice:BAAALgADCgIJAgAAAA==.',
Ex='Exhumator:BAAALgAECgEJAQAAAA==.',
Ez='Ezili:BAAALgAECgEJAQAAAA==.',
Fa='Failure:BAAALgAECgIJAwAAAA==.Falabala:BAABLgAECn8WAAIVAAYJLhrGAACpAQAVAAYJLhrGAACpAQAAAA==.Fanghür:BAAALgADCgcJDgAAAA==.',
Fe='Feeloow:BAAALgADCgcJCwAAAA==.Felhound:BAAALgAECggJDwAAAA==.Felussi:BAAALgAECgcJDAAAAA==.Feorahir:BAAALgAECgQJBQAAAA==.Fermitorok:BAAALgADCgEJAQAAAA==.',
Ff='Ff:BAAALgAECgQJBAAAAA==.',
Fi='Finnster:BAABLgAECn80AAIMAAkJXQ6FTgC3AQAMAAkJXQ6FTgC3AQAAAA==.Fionna:BAAALgAECgcJDAAAAA==.Firereina:BAAALgADCggJGQABLgAECggJKAAIAJsTAA==.',
Fl='Fleurminator:BAABLgAECn8nAAIEAAkJBxE8AQA7AQAEAAkJBxE8AQA7AQAAAA==.Fluffybaby:BAAALgADCgMJAwAAAA==.',
Fo='Fondadix:BAABLgAECn8lAAIWAAkJpyEKCgByAgAWAAkJpyEKCgByAgAAAA==.',
Fr='Frieia:BAABLgAECn8cAAIVAAgJ3weXZAAHAQAVAAgJ3weXZAAHAQAAAA==.Frostiilocks:BAAALgAECggJCQAAAA==.Frostitutte:BAAALgAECgYJEQAAAA==.Frozenjade:BAAALgAECgMJBQAAAA==.Fryértuck:BAAALgAECgUJBgABLgAECgQJCgAJAAAAAA==.',
Fu='Fuze:BAAALgAECgYJDwAAAA==.',
Ga='Galakrosh:BAACLgAFFH8HAAMgAAMJASHFDgCdAAAdAAMJASFzcgDcAAAgAAIJ9B/FDgCdAAAuAAQKfyoABCAACAkYJIUFADACAB0ACAlwHT4XAMkCACAACAlpIoUFADACACEAAQkAAIFjAEgAAAAA.Galarína:BAABLgAECn8/AAMFAAkJFCKqDADPAgAFAAgJqSGqDADPAgAGAAkJgB5PAAARAgAAAA==.Gandora:BAABLgAECn8gAAMbAAkJwxarTwDUAQAbAAkJwxarTwDUAQASAAEJ/wNkQgAiAAAAAA==.Gardrius:BAAALgADCgEJAQAAAA==.',
Ge='Gene:BAAALgADCgcJBwAAAA==.Gentonord:BAABLgAECn8cAAMEAAgJJhoDQQChAQAEAAgJBRcDQQChAQAiAAYJXBdrIAA9AQAAAA==.',
Gi='Gingerports:BAAALgADCgEJAQAAAA==.',
Gk='Gkmc:BAABLgAFFH8TAAIbAAcJXyV1AACbAgAbAAcJXyV1AACbAgABLgAFFAgJKAAaANAjAA==.',
Gl='Glomps:BAAALgAFFAMJAwABLgAFFAUJBgAjAFkEAA==.',
Go='Gonaldduck:BAAALgAECgYJBgAAAA==.',
Gr='Greasemunkey:BAABLgAECn8wAAIYAAkJCBUuCwAKAgAYAAkJCBUuCwAKAgAAAA==.Greentea:BAAALgADCggJCwAAAA==.Griiv:BAACLgAFFH8FAAIPAAIJBB0QjgCWAAAPAAIJBB0QjgCWAAAuAAQKfyMAAg8ACAnNISEWAOQCAA8ACAnNISEWAOQCAAAA.Grislytotem:BAAALgADCgYJCAAAAQ==.Grislywolf:BAAALgAECgUJBQAAAA==.',
Ha='Hakunamatata:BAAALgAECgUJBwAAAA==.Hamburger:BAABLgAECn8ZAAIcAAcJWxVlLAByAQAcAAcJWxVlLAByAQAAAA==.Hammerhard:BAAALgADCgcJDgAAAA==.Hampter:BAAALgAECgYJCQABLgAECgkJJQAcAMgaAA==.Hanita:BAAALgAECgEJAgAAAA==.Haymáker:BAAALgADCgIJAgAAAA==.',
He='Heights:BAAALgAECgUJDgAAAA==.Heliosan:BAAALgAECgEJBAAAAA==.Heyu:BAAALgAECgUJCAABLgAECggJGwAMABcWAA==.',
Hi='Himoe:BAAALgADCgcJDgAAAA==.',
Ho='Holybean:BAAALgADCgkJGAABLgAECgUJDwAJAAAAAA==.Holyhench:BAAALgAECgUJBQAAAA==.Honkeykong:BAAALgADCgIJAgAAAA==.Hoochix:BAAALgAECgQJCQAAAA==.',
Hr='Hrsho:BAAALgADCgQJBAAAAA==.Hrshoo:BAAALgAFFAIJAwAAAA==.',
Hu='Humzashaind:BAABLgAECn8fAAMkAAgJtRHSPADSAAAEAAcJyQ3BUQADAQAkAAYJeA/SPADSAAAAAA==.Huntinrabits:BAAALgADCgIJAgAAAA==.Huntt:BAAALgAECgEJAQAAAA==.Huzzyy:BAAALgAECggJDAABLgAECgkJHwAXAN0bAA==.',
Hy='Hyphira:BAAALgAECgQJCgABLgAECgUJDQAJAAAAAA==.',
Il='Illumi:BAAALgAFFAIJAwABLgAFFAgJKQAbAF8bAA==.',
In='Inferbloom:BAAALgAECggJCAABLgAFFAQJDwAJAAAAAA==.Infernum:BAAALgAFFAQJDwAAAQ==.Insomnia:BAAALgAECgUJBQAAAA==.',
Ir='Irayvia:BAAALgADCgIJAgAAAA==.',
Ja='Jackyvoker:BAABLgAECn8qAAMNAAkJfCLrAQBnAwANAAkJfCLrAQBnAwAIAAMJqRmCJwDlAAAAAA==.Jaezzon:BAAALgADCgQJBwAAAA==.Janessah:BAAALgADCgEJAQAAAA==.',
Je='Jeannaah:BAAALgAECgQJBAABLgAECgcJDwAJAAAAAA==.Jetaime:BAAALgAECgUJBQAAAA==.',
Jh='Jharia:BAAALgADCgMJAgAAAA==.',
Ji='Jinksey:BAAALgAECgcJDQABLgAECgcJEQAeABETAA==.',
Jo='Johndoom:BAAALgAECgYJDgAAAA==.Johnfist:BAAALgAECgEJBAAAAA==.Johngrippy:BAAALgAECgEJAwAAAA==.Johnrend:BAAALgAECgEJAQAAAA==.',
Ju='Juicybottoms:BAAALgADCgMJAgAAAA==.',
Ka='Kairstia:BAAALgAECgYJCQABLgAECggJKAAIAJsTAA==.Kalidormi:BAAALgAECgYJCgAAAA==.Kalzious:BAAALgADCgkJHAAAAA==.Kamikaze:BAAALgAECgcJBQAAAA==.Kayelalynn:BAABLgAECn8rAAMHAAkJuxeGFwARAgAHAAkJuxeGFwARAgAVAAMJNgEowgBDAAAAAA==.',
Kd='Kd:BAAALgAECgEJAgAAAA==.',
Ke='Kegpaw:BAAALgAFFAEJAQAAAA==.Keiri:BAAALgADCgYJBgAAAA==.Kelana:BAABLgAECn8lAAITAAkJxB/zCACjAgATAAkJxB/zCACjAgAAAA==.Kendô:BAAALgAECgcJDAAAAA==.Ketdealer:BAAALgAECgcJDQAAAA==.Ketzendk:BAAALgAECgYJBQAAAA==.Keyahi:BAACLgAFFH8bAAIeAAYJRBsNKACKAQAeAAYJRBsNKACKAQAuAAQKfx0AAh4ACQk0HO0iAEUCAB4ACQk0HO0iAEUCAAEuAAQKAQkBAAkAAAAA.',
Kh='Khaean:BAAALgADCgkJCQAAAA==.Khasumi:BAAALgADCgMJAwAAAA==.Khety:BAAALgAECgQJBAAAAA==.',
Ki='Kickandpunch:BAAALgAECgYJDgAAAA==.Kicsi:BAAALgAECgIJAwAAAA==.Kilan:BAABLgAECn8iAAMPAAgJXRQBaQCdAQAPAAgJeBIBaQCdAQAOAAIJNBjtNgCEAAAAAA==.Killinrage:BAAALgAECgYJDgAAAA==.Kissofpaine:BAAALgADCgIJAgAAAA==.Kitsuney:BAAALgADCgMJAwAAAA==.Kizaru:BAAALgAECgcJCAAAAA==.',
Ko='Korz:BAAALgADCgcJBwABLgAECgcJFQAaAOEXAA==.',
Kp='Kpop:BAAALgAECgEJAQAAAA==.',
Kr='Krutree:BAAALgAECgcJCQAAAA==.Krynj:BAAALgAFFAEJAwAAAA==.',
Ku='Kumokiri:BAAALgAECgIJAgAAAA==.Kuromu:BAABLgAFFH8HAAIbAAMJOxZxlgDgAAAbAAMJOxZxlgDgAAAAAA==.Kurzzon:BAAALgADCgMJAwAAAA==.',
Ky='Kyleata:BAACLgAFFH8FAAIMAAMJlgsnaADVAAAMAAMJlgsnaADVAAAuAAQKfzoAAgwACAk/HvkrAC0CAAwACAk/HvkrAC0CAAAA.Kyleigh:BAAALgAECgQJBQABLgAECgcJDwAJAAAAAA==.Kyokin:BAACLgAFFH8HAAIPAAIJnxJhkgCOAAAPAAIJnxJhkgCOAAAuAAQKf0MAAw8ACQkiFow+AAsCAA8ACAmMGIw+AAsCAA4ACAmNCZQBALIAAAAA.Kyzula:BAABLgAECn80AAIRAAcJBRmNLgD8AQARAAcJBRmNLgD8AQAAAA==.',
['Kê']='Kêndo:BAAALgAECgEJAwABLgAECgcJDAAJAAAAAA==.',
La='Lace:BAAALgADCgMJAwAAAA==.Launam:BAAALgAECgMJBAAAAA==.Laytone:BAAALgADCgYJBwAAAA==.',
Le='Legcurl:BAAALgAECgEJAwAAAA==.Lepotko:BAAALgAECgQJBAAAAA==.',
Li='Lightbear:BAAALgAECgMJAwAAAA==.Lilchub:BAAALgAECgIJAwAAAA==.Lilylocks:BAAALgAECgcJCQAAAA==.Lilyrocks:BAAALgAECgUJCQAAAA==.Literallad:BAAALgADCgcJBgAAAA==.Littlelo:BAAALgAECgYJEgAAAA==.',
Ll='Llortdnaz:BAAALgADCgEJAgAAAA==.',
Lo='Lockology:BAAALgAFFAEJAQAAAA==.Lokarg:BAAALgADCgIJAgAAAA==.Loudcry:BAACLgAFFH8KAAIZAAUJ9hDOAAB1AQAZAAUJ9hDOAAB1AQAuAAQKfzMAAxkACQlvHrQBAKkCABkACAkAIbQBAKkCABoAAwm0EDL6ALUAAAAA.',
Lu='Lunaeria:BAAALgADCggJCAAAAA==.',
Ly='Lyanah:BAACLgAFFH8eAAIVAAUJ+gkyLQAAAQAVAAUJ+gkyLQAAAQAuAAQKfywAAhUACQm3Fl4kACgCABUACQm3Fl4kACgCAAAA.Lydia:BAAALgAECgQJAgAAAA==.Lyniah:BAAALgAECgQJBQAAAA==.',
Ma='Machete:BAAALgAECgQJCQAAAA==.Maelius:BAABLgAECn89AAMXAAkJRhv4DQC0AgAXAAkJRhv4DQC0AgAOAAQJqQNTOgBzAAAAAA==.Maggrus:BAABLgAECn8bAAIMAAgJFxYZWACcAQAMAAgJFxYZWACcAQAAAA==.Malavel:BAAALgADCggJCAAAAA==.Malically:BAACLgAFFH8FAAMMAAMJjhRWXQDqAAAMAAMJjhRWXQDqAAAlAAEJYwTpOwAzAAAuAAQKfyAAAyUACQlpELoSADIBACUACAmCEboSADIBAAwABgntC/iUABYBAAAA.Manshoon:BAAALgADCgcJCwAAAA==.Marlory:BAAALgADCgUJBQAAAA==.Math:BAEALgAFFAEJAQABLgAFFAYJCwAjAAYPAA==.Matheney:BAEBLgAFFH8QAAIUAAcJCA5HBgCWAQAUAAcJCA5HBgCWAQABLgAFFAYJCwAjAAYPAA==.Matsuzo:BAAALgAECgEJAgAAAA==.Maxnem:BAAALgADCggJCAABLgAECggJHwAHADMPAA==.',
Mc='Mcrib:BAAALgADCggJBQAAAA==.Mctubby:BAAALgADCgUJBQABLgADCgUJBgAJAAAAAA==.Mctubmonk:BAAALgADCgUJBgAAAA==.',
Me='Meatpopsicle:BAAALgADCgEJAQAAAA==.Meigz:BAAALgAECgYJDwAAAA==.Melicious:BAAALgAECgQJBAAAAA==.Melidin:BAAALgAECgkJEgAAAA==.Melinda:BAAALgAFFAEJAQAAAA==.Melindorei:BAAALgAECgEJAgAAAA==.Melledrus:BAAALgAECgEJAQAAAA==.Mememo:BAAALgAECgMJAwAAAA==.Menöpaws:BAEALgAFFAMJAwAAAA==.Merithrá:BAAALgAECgMJAwAAAA==.',
Mi='Mikaeljayfox:BAAALgAECgcJDwAAAQ==.Mikros:BAAALgAECgQJBgAAAA==.Milenzha:BAABLgAECn8nAAIMAAgJpBYtSQDGAQAMAAgJpBYtSQDGAQAAAA==.Milkymaiden:BAAALgADCgMJBQABLgADCgYJCQAJAAAAAA==.Mimachote:BAABLgAECn8WAAIUAAkJQw89HABsAQAUAAkJQw89HABsAQAAAA==.',
Mo='Monetta:BAAALgADCgIJAgAAAA==.Monk:BAAALgAECggJEAAAAA==.Moonblood:BAAALgADCggJEAAAAA==.Moonfighter:BAAALgAECgEJAgAAAA==.Moontann:BAAALgAECgkJAQAAAA==.Morcombe:BAAALgAECgEJAQAAAA==.Moreia:BAAALgAECgMJAwAAAA==.Motown:BAAALgAECgYJCwAAAA==.Mousse:BAABLgAECn8WAAIPAAYJ1gVjCAB/AAAPAAYJ1gVjCAB/AAAAAA==.',
Mu='Murdalok:BAABLgAECn8ZAAIVAAgJshWdNQDSAQAVAAgJshWdNQDSAQAAAA==.Murdergodx:BAAALgAECgYJCwAAAA==.',
My='Myndy:BAAALgADCgYJBgAAAA==.Mysharona:BAAALgAECgEJAQAAAA==.Mystahmurdah:BAAALgAECgEJAwABLgAECgcJFgAmAM4TAA==.Mysterioñ:BAAALgAECgQJDQAAAA==.',
['Má']='Mákla:BAAALgAECgMJAwAAAA==.',
['Mâ']='Mâstermînd:BAAALgAECgUJDgAAAA==.',
Na='Nahte:BAAALgADCgYJCQAAAA==.Naiana:BAAALgADCgMJAwAAAA==.Nasine:BAAALgAECgYJCAABLgAECgkJGwAQAPYdAA==.Natstryker:BAABLgAECn9MAAQTAAkJ4SYjAACUAwATAAkJ4SYjAACUAwAGAAgJ8CJMFQBCAgAFAAcJMRHZQwBdAQAAAA==.Naturemyth:BAAALgAFFAEJAwAAAA==.Nazu:BAAALgADCgUJCgAAAA==.',
Ne='Neeró:BAABLgAECn8iAAMeAAYJphVRfAAnAQAeAAYJphVRfAAnAQAKAAEJtxS2ZwA+AAAAAA==.Nelthon:BAAALgADCgYJBgAAAA==.',
Ni='Nishastraza:BAAALgAECgEJAwABLgAECgcJDwAJAAAAAA==.',
No='Nonaha:BAAALgADCgkJEQAAAA==.Notsoda:BAAALgAECgQJCQAAAA==.',
Nu='Nuciferas:BAAALgAECgQJBAAAAA==.',
Oa='Oaf:BAAALgAECgYJBgAAAA==.',
Om='Omcmoneyshot:BAAALgAECgUJBQAAAA==.',
Oo='Oolong:BAAALgAECgQJBQAAAA==.',
Or='Ordomalleus:BAAALgADCgEJAQABLgAECgEJAQAJAAAAAA==.Organa:BAABLgAECn8jAAIEAAgJoAqTPwBGAQAEAAgJoAqTPwBGAQAAAA==.',
Ou='Outofthedark:BAAALgAECgIJAgAAAA==.',
Pa='Pakkan:BAAALgAECgEJAQAAAA==.Pallyqb:BAAALgADCgEJAQAAAA==.Palyomie:BAAALgAECgIJAgAAAA==.Pandariam:BAAALgAECgYJEQAAAA==.Pauladeenx:BAAALgAECgIJAwABLgAECgUJDgAJAAAAAA==.',
Pe='Petal:BAAALgAECgYJBwABLgAECggJEAAJAAAAAA==.',
Ph='Pho:BAAALgAECgEJAQAAAA==.',
Pl='Playwitwe:BAAALgAECgUJCAAAAA==.Plowmcballs:BAABLgAECn8ZAAIPAAYJtxIzfgB+AQAPAAYJtxIzfgB+AQAAAA==.Plugley:BAABLgAECn8dAAMaAAkJqBjhOwAqAgAaAAkJqBjhOwAqAgAZAAEJARSGHAA6AAAAAA==.',
Po='Polaris:BAAALgAECgEJAQAAAA==.Poober:BAABLgAECn8hAAMCAAkJbx97DACfAgACAAgJeCF7DACfAgADAAQJNBmUNgA5AQAAAA==.Potooòooóoo:BAABLgAECn8dAAISAAcJVhitFQAsAQASAAcJVhitFQAsAQAAAA==.',
Pr='Pren:BAAALgAFFAEJAQAAAA==.Privet:BAAALgAECgEJAwAAAA==.',
Pu='Purebeef:BAAALgAECgIJAgAAAA==.',
Py='Pygos:BAABLgAECn8ZAAInAAgJ5BiJBwANAgAnAAgJ5BiJBwANAgAAAA==.',
['Pë']='Përdü:BAAALgAECggJEgAAAA==.',
Qu='Quigglay:BAAALgAECgYJBgAAAA==.',
Ra='Raegnarok:BAABLgAECn8hAAIXAAgJ/RMOIwDsAQAXAAgJ/RMOIwDsAQAAAA==.Raelessa:BAAALgAECgQJCQABLgAECgcJDwAJAAAAAA==.Raigeki:BAAALgADCgQJBQAAAA==.Ralf:BAAALgAECgEJAQAAAA==.Ralphie:BAAALgAECgIJAgAAAA==.Ratapew:BAABLgAECn8VAAIeAAgJzxSuVACIAQAeAAgJzxSuVACIAQAAAA==.Ratheen:BAABLgAECn8dAAIPAAgJtA58nAA9AQAPAAgJtA58nAA9AQAAAA==.Raytar:BAABLgAECn8hAAMHAAkJbh8+DwBrAgAHAAgJgiA+DwBrAgAVAAMJ9RsBmwCWAAAAAA==.',
Re='Rekkirin:BAAALgAECgUJBQABLgAECgkJOAANAAUWAA==.Relyk:BAAALgADCgUJBQAAAA==.',
Ri='Riyo:BAAALgAFFAIJAwAAAA==.',
Ro='Roachie:BAAALgAECgYJDgAAAA==.Rockandstone:BAAALgADCgEJAQAAAA==.Roesira:BAAALgAECgEJAQAAAA==.Rogun:BAAALgAECgkJAQAAAA==.Ros:BAAALgAECgMJBAAAAA==.',
Ru='Rug:BAAALgADCgYJBgAAAA==.Rustybray:BAABLgAECn81AAIQAAkJhgfxQgAnAQAQAAkJhgfxQgAnAQAAAA==.Ruu:BAAALgAECgkJBQABLgAFFAQJEgAmAPkSAA==.',
Ry='Ryvulz:BAABLgAECn8eAAIcAAgJHRWsGAAcAgAcAAgJHRWsGAAcAgAAAA==.',
Sa='Salomicum:BAAALgADCgEJAQAAAA==.Sappollo:BAAALgADCgMJAwAAAA==.Sarabi:BAABLgAECn8nAAIFAAgJlBUpJwDuAQAFAAgJlBUpJwDuAQAAAA==.Sarena:BAAALgADCgMJAwAAAA==.Sarkoth:BAAALgADCgEJAQAAAA==.',
Sc='Schnee:BAAALgADCgYJCgAAAA==.Schutzhund:BAAALgAECgMJAgAAAA==.Scrapster:BAAALgAECgUJDQAAAA==.',
Se='Seifer:BAAALgADCgEJAQAAAA==.Sekha:BAAALgAECgQJBgABLgAECggJIQAHAOoXAA==.Serbero:BAAALgAECgEJAQAAAA==.Serelia:BAABLgAFFH8HAAIFAAMJSBNePQCwAAAFAAMJSBNePQCwAAAAAA==.Seshiro:BAAALgAECgQJBAABLgAECgkJNQAOANkjAA==.',
Sh='Shadoweave:BAACLgAFFH8lAAMCAAcJ7hLMDwBXAQACAAcJ7hLMDwBXAQAcAAUJLRSnAgDeAAAuAAQKfxkAAgIACQkoGJQTAD0CAAIACQkoGJQTAD0CAAEuAAUUCAknABUApBIA.Shalalia:BAABLgAECn8hAAIMAAcJNw5YdABXAQAMAAcJNw5YdABXAQAAAA==.Shambean:BAAALgADCgEJAQABLgAECgUJDwAJAAAAAA==.Shammywitch:BAAALgAFFAIJAwABLgAECgQJCgAJAAAAAA==.Shentsu:BAABLgAECn8YAAIFAAkJ0CD7BQD/AgAFAAkJ0CD7BQD/AgAAAA==.Shhanks:BAAALgAECgEJAQAAAA==.Shinmen:BAAALgADCgkJCQAAAA==.Shinsha:BAAALgADCgIJAwAAAA==.Shnizelnazee:BAABLgAECn8WAAIPAAgJDww9tAAZAQAPAAgJDww9tAAZAQAAAA==.Shortonheals:BAAALgAECgMJAwAAAA==.',
Si='Siege:BAAALgAECgUJBQAAAA==.Silie:BAAALgADCgEJAQAAAA==.Silik:BAAALgADCgcJBwAAAA==.Simpforsale:BAAALgAECgYJCQAAAA==.',
Sk='Skybladee:BAAALgAECgIJAgAAAA==.',
Sm='Smokeyb:BAACLgAFFH8IAAIPAAMJ+An4eADDAAAPAAMJ+An4eADDAAAuAAQKfywAAg8ACAlrFpNYAMIBAA8ACAlrFpNYAMIBAAAA.',
Sn='Sneevie:BAAALgAECggJCgAAAA==.Snorehees:BAABLgAECn8uAAMMAAkJ7w9HTQC6AQAMAAkJ7w9HTQC6AQAlAAQJMwKcNgBEAAAAAA==.',
So='Songarrow:BAAALgAECgYJBgAAAA==.Songstar:BAABLgAECn80AAIMAAkJ+SNpEADNAgAMAAkJ+SNpEADNAgAAAA==.Soullraven:BAAALgADCgkJNAAAAA==.',
Sp='Spy:BAAALgAECgEJBQAAAA==.',
Sq='Squingledorf:BAAALgAECgMJAwAAAA==.',
St='Staavon:BAABLgAECn8nAAIaAAgJ8QmOkQBVAQAaAAgJ8QmOkQBVAQAAAA==.Stacy:BAAALgAECgEJAQABLgAECgQJCAAJAAAAAA==.Stalvis:BAAALgADCgUJBQAAAA==.Starblaze:BAAALgAECgcJDQAAAA==.Starseek:BAABLgAECn8VAAInAAcJLhDLEABDAQAnAAcJLhDLEABDAQAAAA==.Steelboats:BAAALgADCgkJGQAAAA==.',
Su='Sugarbow:BAAALgADCgMJAwAAAA==.Sugarhoof:BAAALgAECgcJCwAAAA==.Sugarlick:BAABLgAECn8jAAIWAAgJPRvXFwCmAQAWAAgJPRvXFwCmAQAAAA==.Sugarpop:BAACLgAFFH8GAAIXAAMJNw3aNQCXAAAXAAMJNw3aNQCXAAAuAAQKfygAAhcACQnXHIISAH4CABcACQnXHIISAH4CAAEuAAUUBAkSABEAhB8A.Sunraku:BAAALgAECgIJAwAAAA==.Suplazindh:BAAALgAFFAIJAgABLgAFFAkJSQAbAJIhAA==.',
Sw='Swethort:BAAALgADCgcJBgAAAA==.',
Sy='Synman:BAAALgADCgYJBgAAAA==.Syntheria:BAAALgADCgcJDAAAAA==.Syrebriel:BAABLgAECn8VAAIDAAcJCxEBJABzAQADAAcJCxEBJABzAQAAAA==.',
['Sí']='Sílíbrítí:BAAALgAECgYJDQABLgAFFAMJDAAFAIINAA==.',
Ta='Taediah:BAAALgAFFAEJAQAAAA==.Tamius:BAAALgADCgEJAQAAAA==.Tanthanalas:BAAALgAECgQJBAAAAA==.',
Th='Thefalsehope:BAAALgADCgcJBwAAAA==.Theoutcast:BAAALgAECgQJDgAAAA==.Thesarius:BAABLgAECn8ZAAIiAAgJXxmXDQAxAgAiAAgJXxmXDQAxAgAAAA==.Thortor:BAAALgADCgIJAgABLgADCggJEAAJAAAAAA==.Thumbies:BAAALgAECgEJAQAAAA==.Thumbzie:BAAALgAECgMJAwAAAA==.',
Ti='Tiestto:BAAALgAECgcJDgAAAA==.Tinkermid:BAAALgADCgEJAQAAAA==.Tinymeatgang:BAAALgADCggJCQAAAA==.',
To='Tobalwl:BAAALgADCgUJBQAAAA==.Tockley:BAABLgAECn8kAAIaAAgJYQjjBwCTAAAaAAgJYQjjBwCTAAAAAA==.Toetagger:BAABLgAECn8eAAIbAAgJ4A/abgCHAQAbAAgJ4A/abgCHAQAAAA==.Tofino:BAAALgAECggJDwAAAA==.Tohner:BAAALgADCgMJAwAAAA==.Tolidron:BAAALgADCgEJAQAAAA==.Tonimâster:BAAALgAFFAEJAQAAAA==.Tonydmaster:BAAALgAECgEJAQAAAA==.Toyotama:BAAALgAECgUJDQAAAA==.',
Tr='Trashiepanda:BAABLgAECn8UAAMSAAYJuQgaHwDUAAASAAYJIggaHwDUAAAbAAUJRga+AgGoAAAAAA==.Trenbologna:BAAALgAECgEJAQAAAA==.Tristah:BAAALgAECgUJDwABLgAECgcJDwAJAAAAAA==.Trzlawd:BAAALgADCgEJAQAAAA==.',
Ty='Tyindron:BAAALgAECgYJBwAAAA==.Tyrrial:BAABLgAECn8yAAIPAAgJbRcSUgDTAQAPAAgJbRcSUgDTAQAAAA==.Tyshus:BAAALgAECgYJDQAAAA==.',
Ud='Udntknwme:BAAALgAFFAIJAwAAAA==.',
Un='Unbral:BAAALgADCgEJAQAAAA==.Unicood:BAAALgADCgYJBgAAAA==.Unlockbot:BAAALgADCgEJAwABLgAECgcJDwAJAAAAAA==.Unnicron:BAAALgAECgMJAwAAAA==.Unwholey:BAAALgAECggJCAAAAA==.',
Ut='Uthgardt:BAAALgAECgYJBgABLgAECgYJCwAJAAAAAA==.',
Va='Valarion:BAABLgAECn8nAAIkAAgJ4RIiFwCiAQAkAAgJ4RIiFwCiAQAAAA==.Valcaryn:BAAALgADCgYJBgAAAA==.Validimus:BAABLgAECn8aAAMPAAgJnQcOtQAYAQAPAAgJ8AYOtQAYAQAOAAIJ+QXGTAA6AAAAAA==.Valinis:BAAALgAECgQJBAAAAA==.Valinius:BAAALgADCgYJCQAAAA==.Valorían:BAABLgAECn9MAAQiAAkJjyXYAABmAwAiAAkJjyXYAABmAwAEAAkJYyKzCwCsAgAkAAIJAiAWRAC4AAAAAA==.Valtaa:BAAALgADCgUJBwAAAA==.Vanza:BAAALgADCgEJAQAAAA==.Varthayn:BAABLgAECn9DAAIaAAkJ4iCCGgC7AgAaAAkJ4iCCGgC7AgAAAA==.',
Ve='Vecna:BAAALgAECgMJAwABLgAECgYJCAAJAAAAAA==.Velandriel:BAAALgADCgkJCwABLgAECgkJOgAKANQYAA==.Vengfuhl:BAAALgAECgQJAwAAAA==.Verra:BAAALgAECgEJAQAAAA==.Vet:BAAALgAECgEJAQAAAA==.',
Vo='Voidwa:BAAALgAECggJEgAAAA==.Volbain:BAABLgAECn8zAAQKAAgJqR2FAACdAQAKAAgJqR2FAACdAQAnAAMJ5BGlHwCgAAAeAAEJ0wKKOAEcAAAAAA==.Volklin:BAABLgAECn8pAAMmAAkJqhTsIQCNAQAmAAkJow7sIQCNAQAMAAcJaRTeTQB/AQAAAA==.Voltagex:BAABLgAECn8dAAIeAAcJfRyDVgCDAQAeAAcJfRyDVgCDAQAAAA==.',
Vu='Vulpsinculta:BAABLgAECn8kAAIdAAgJ6RRSSwC4AQAdAAgJ6RRSSwC4AQAAAA==.',
['Vï']='Vïrùs:BAABLgAECn8mAAIHAAcJeg1aPABDAQAHAAcJeg1aPABDAQAAAA==.',
Wa='Wanda:BAAALgAECgYJBgAAAA==.',
Wi='Wichita:BAABLgAECn80AAMbAAkJsA9NZACfAQAbAAgJEhFNZACfAQAWAAEJBQZdZgAdAAAAAA==.Wildkitty:BAAALgAFFAEJAQAAAA==.',
Wo='Wolfyze:BAAALgADCgEJAQAAAA==.',
Wr='Wrâth:BAAALgAECgEJAgAAAA==.',
Wt='Wtfamaterasu:BAAALgAECgYJCgAAAA==.Wtfguën:BAABLgAECn8pAAIUAAgJ7gstKwAFAQAUAAgJ7gstKwAFAQAAAA==.Wtftäzmikell:BAAALgADCgYJCQABLgAECggJKQAUAO4LAA==.',
Wu='Wutäng:BAAALgADCgYJCgAAAA==.',
Xe='Xera:BAAALgADCgYJBgAAAA==.',
Xo='Xondra:BAAALgAECgYJDQAAAA==.',
Xr='Xravo:BAAALgADCgkJCQAAAA==.',
Xz='Xzairi:BAABLgAECn8hAAIHAAgJ6hf8JACjAQAHAAgJ6hf8JACjAQAAAA==.',
Ya='Yarria:BAAALgADCgIJAgAAAA==.',
Yi='Yinh:BAAALgADCgcJDAAAAA==.',
Yo='Yoiki:BAAALgAECgEJAQABLgAECgEJAQAJAAAAAA==.',
Yu='Yuck:BAAALgAECgIJBAAAAA==.',
Yy='Yy:BAAALgAECgUJDAAAAA==.',
Ze='Zeuzco:BAAALgAECgkJEQAAAA==.',
Zo='Zorell:BAAALgAECgYJDQAAAA==.Zovaal:BAAALgAECgQJBAAAAA==.',
['Ál']='Áltá:BAABLgAECn8uAAMdAAkJURncJgBCAgAdAAkJURncJgBCAgAhAAIJNwyJMwBSAAAAAA==.',
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
