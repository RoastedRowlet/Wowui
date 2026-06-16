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
local provider = {region='US',realm='Misha',name='US',type='weekly',zone=46,date='2026-06-13',data={Ac='Acidburn:BAABLgAECn8WAAIBAAcJ0BroAwDvAQABAAcJ0BroAwDvAQAAAA==.',
Ae='Aea:BAAALgAECgIJCQAAAA==.Aevie:BAAALgAECgYJEgAAAA==.',
Af='Afterlìfe:BAAALgAECggJEgAAAA==.',
Ai='Ailis:BAAALgADCgQJBAAAAA==.',
Al='Alendria:BAAALgADCgYJBgAAAA==.Alizë:BAAALgADCgQJAwAAAA==.Alluna:BAAALgADCgEJAQAAAA==.Alorillan:BAAALgAECggJEgAAAA==.Altabrew:BAAALgAECgQJBAAAAA==.Altair:BAAALgAECgUJDwABLgAECgkJIQACABMhAA==.',
An='Andelynn:BAAALgAECgIJAgAAAA==.',
Ap='Applejuic:BAACLgAFFH8FAAIDAAMJtgrJQwCJAAADAAMJtgrJQwCJAAAuAAQKfxQAAwMACQlKFsMaADwCAAMACQlKFsMaADwCAAQAAQk1EH2fAC0AAAAA.Appless:BAAALgAECgQJBwAAAA==.',
Ar='Araylia:BAABLgAECn8hAAIFAAkJgw17MwBHAQAFAAkJgw17MwBHAQAAAA==.Aridella:BAABLgAECn8VAAIGAAYJRA74EwDIAAAGAAYJRA74EwDIAAAAAA==.Ariellaa:BAAALgAECgYJBgAAAA==.Artamayis:BAAALgAECgQJBAAAAA==.',
As='Ashaly:BAAALgADCgUJBQAAAA==.Ashlei:BAAALgAECgQJCAAAAA==.',
At='Atomseve:BAAALgADCgQJBAABLgAECggJEwAHAAAAAA==.',
Au='Aurafarmer:BAAALgADCgEJAQAAAA==.Autopsia:BAAALgADCgYJBgABLgAECgkJOQAIANQYAA==.Autumn:BAAALgADCgUJBwAAAA==.',
Av='Avalorne:BAAALgAECgMJAwABLgAECgkJIQACABMhAA==.Avena:BAAALgADCgEJAwAAAA==.',
Az='Azaizel:BAAALgAECgYJCwAAAA==.Azusie:BAABLgAECn81AAIJAAkJehe7CQAcAgAJAAkJehe7CQAcAgAAAA==.',
Ba='Baddate:BAABLgAECn8gAAIKAAcJ3A9ubQBhAQAKAAcJ3A9ubQBhAQAAAA==.Baddragøn:BAABLgAECn84AAMLAAkJBRZRDQD4AQALAAgJ0xVRDQD4AQAGAAgJxg+5CQCHAQAAAA==.Balthaas:BAABLgAECn82AAMMAAkJyhjDCgAaAgAMAAkJyhjDCgAaAgANAAEJewdjUQErAAAAAA==.Bangen:BAAALgAECgcJDwAAAA==.Bastria:BAAALgAECgYJDAAAAA==.Baulters:BAAALgAECgYJCAAAAA==.',
Be='Beenn:BAAALgAECgYJBgAAAA==.',
Bh='Bharko:BAAALgADCgcJCgABLgAFFAcJDwAKABkZAA==.',
Bi='Billyblastin:BAAALgAECgMJAwABLgAECgkJJQAOAFgZAA==.Billywitchdr:BAABLgAECn8lAAMOAAkJWBkeGQAWAgAOAAkJWBkeGQAWAgAPAAEJFga52AArAAAAAA==.Biocryo:BAAALgADCgYJBgABLgAECggJEAAHAAAAAA==.',
Bl='Blazingpanda:BAAALgAECgMJBAAAAA==.Blizeatsass:BAAALgADCgMJAwAAAA==.Bluedomino:BAAALgAECgMJCAAAAA==.Bluetoykawi:BAACLgAFFH8GAAIQAAQJUwSOFADcAAAQAAQJUwSOFADcAAAuAAQKfzsAAhAACAlcF2YKANQBABAACAlcF2YKANQBAAAA.',
Bo='Boats:BAAALgADCgIJAgAAAA==.Boltspark:BAAALgADCgMJAwAAAA==.Borgo:BAAALgAECgYJBgAAAA==.Bowlenciaga:BAABLgAECn8gAAIKAAgJyQqRZAB3AQAKAAgJyQqRZAB3AQAAAA==.Bozilla:BAAALgADCgMJAwAAAA==.',
Br='Braelia:BAAALgADCgcJCAAAAA==.Brainfart:BAAALgADCgUJBQABLgAECggJGwAKABcWAA==.Breloom:BAAALgADCgEJAQAAAA==.Bruithis:BAAALgADCgIJAgAAAA==.',
Bu='Burdan:BAAALgADCgQJBAAAAA==.Buttermebuns:BAAALgADCgcJCAAAAA==.',
Ca='Cariandria:BAAALgAECgUJBgAAAA==.',
Cc='Cc:BAAALgAECgEJAgAAAA==.',
Ch='Chahaein:BAAALgAECgYJDwAAAA==.Charbaby:BAAALgAFFAMJAwABLgAFFAUJFwARABYfAA==.Charhartt:BAACLgAFFH8FAAISAAMJJw9bIACXAAASAAMJJw9bIACXAAAuAAQKfxUAAxIABgljFwggAEgBABIABgljFwggAEgBABMAAQlXByPnACMAAAEuAAUUBQkXABEAFh8A.Charita:BAAALgAECgMJBAABLgAFFAUJFwARABYfAA==.Charizard:BAAALgAECgEJAQABLgAFFAUJFwARABYfAA==.Charming:BAACLgAFFH8XAAIRAAUJFh+iGgBLAQARAAUJFh+iGgBLAQAuAAQKfyIAAhEACQmkG0IaANEBABEACQmkG0IaANEBAAAA.Charmonic:BAAALgAFFAIJAgABLgAFFAUJFwARABYfAA==.Chelseah:BAAALgAECgYJEAABLgAECgcJDwAHAAAAAA==.',
Ci='Cinderlight:BAAALgAECgEJAQAAAA==.',
Cl='Clanker:BAAALgAECgkJEgAAAA==.Clémentine:BAAALgAECgEJAgAAAA==.',
Co='Coldknight:BAABLgAECn8eAAMQAAcJjQIBKQCFAAAQAAcJWAIBKQCFAAAUAAUJ6AHLTgBUAAAAAA==.Conien:BAAALgADCgQJBAAAAA==.Conifer:BAABLgAECn8WAAITAAcJEho0KgABAgATAAcJEho0KgABAgAAAA==.Coniption:BAAALgADCgEJAQAAAA==.Contrlurself:BAAALgAECgYJBgABLgAECgkJKAAFALsXAA==.Copium:BAAALgAECgQJBwAAAA==.Cornpop:BAAALgAECgYJEQAAAA==.Cowret:BAABLgAECn9DAAMVAAkJdCQpAQC1AwAVAAkJdCQpAQC1AwANAAEJAABe0QEAAAAAAA==.',
Cr='Crystalwolf:BAABLgAECn8VAAIWAAYJiwWmLgCjAAAWAAYJiwWmLgCjAAAAAA==.',
Cu='Curze:BAAALgAECgMJAwAAAA==.',
Cy='Cyonna:BAAALgADCgQJBAAAAA==.',
Da='Darc:BAABLgAECn8YAAICAAQJXSXUPgCpAQACAAQJXSXUPgCpAQAAAA==.Darkfoxgrime:BAAALgAECgkJDQABLgAECgkJJAAEAHkQAA==.Darkjager:BAABLgAECn8rAAIKAAkJHR5CLgAgAgAKAAkJHR5CLgAgAgAAAA==.Darkways:BAAALgAECgcJAQAAAA==.Darlah:BAABLgAECn8qAAIXAAkJzRSMAgAhAgAXAAkJzRSMAgAhAgAAAA==.Darnalin:BAAALgAECgEJAgABLgAECgkJOQAIANQYAA==.Dayva:BAAALgAECgQJBgAAAA==.Dayyva:BAAALgAECgQJDgAAAA==.',
De='Deadcobra:BAABLgAECn8pAAIYAAkJrASVpQAvAQAYAAkJrASVpQAvAQAAAA==.Deathbean:BAAALgADCgQJBAABLgAECgUJDwAHAAAAAA==.Debtknight:BAABLgAECn84AAIZAAkJ6h+JFgC9AgAZAAkJ6h+JFgC9AgAAAA==.Deelo:BAAALgAECgUJBgAAAA==.Dehumidifier:BAABLgAECn8sAAMaAAkJbR8LDwB0AgAaAAkJbR8LDwB0AgAbAAkJQw1gJgCXAQAAAA==.Deltria:BAAALgAECggJEgAAAA==.Demonrot:BAABLgAECn8XAAIcAAgJZAvZdQBNAQAcAAgJZAvZdQBNAQAAAA==.Dervin:BAAALgADCgQJBAABLgAECggJCAAHAAAAAA==.Deviltank:BAAALgADCgYJDAAAAA==.Devohsup:BAABLgAECn8dAAIdAAgJlB95HwBVAgAdAAgJlB95HwBVAgAAAA==.Devussi:BAABLgAECn8mAAIdAAkJyBTpRwCrAQAdAAkJyBTpRwCrAQABLgAECgUJBQAHAAAAAA==.',
Di='Dienva:BAAALgAECgUJBQAAAA==.Digmyearth:BAAALgAECgUJCAAAAA==.Dilea:BAAALgAECggJCQAAAA==.Discoffee:BAAALgADCgYJBgABLgADCgcJEAAHAAAAAA==.',
Dk='Dksakp:BAAALgADCgkJGAAAAA==.',
Do='Dominateelf:BAAALgADCgQJBAABLgAECgMJBAAHAAAAAA==.Dotero:BAAALgAECgUJDgAAAA==.',
Dr='Dracreina:BAABLgAECn8oAAMGAAgJmxP8BwCyAQAGAAgJmxP8BwCyAQALAAEJQQaoPwAlAAAAAA==.Dreouss:BAAALgAECgQJBgAAAA==.Driver:BAAALgAFFAIJAwABLgAFFAUJDwAcALYLAA==.',
Du='Dumeslayer:BAAALgADCgcJCQAAAA==.Durzoe:BAABLgAECn8WAAIeAAcJlwoFOQBNAQAeAAcJlwoFOQBNAQAAAA==.',
Dv='Dvsmage:BAAALgAECgUJDwAAAA==.',
Eg='Egaik:BAAALgAECgYJBgAAAA==.',
El='Elarred:BAAALgADCgkJFAAAAA==.Elfkr:BAAALgAECgkJBAAAAA==.Elissauna:BAABLgAECn8VAAIYAAkJ/RKfRAAKAgAYAAkJ/RKfRAAKAgAAAA==.Elylea:BAABLgAECn8fAAICAAgJvRqfHgD4AQACAAgJvRqfHgD4AQAAAA==.',
En='Enorme:BAAALgADCgQJBAAAAA==.',
Eu='Eunice:BAAALgADCgIJAgAAAA==.',
Ez='Ezili:BAAALgAECgEJAQAAAA==.',
Fa='Failure:BAAALgAECgIJAwAAAA==.Falabala:BAAALgAECgYJEAAAAA==.Fanghür:BAAALgADCgcJDgAAAA==.',
Fe='Feeloow:BAAALgADCgcJCwAAAA==.Felhound:BAAALgAECggJDwAAAA==.Felussi:BAAALgAECgUJBQAAAA==.Feorahir:BAAALgAECgQJBQAAAA==.Fermitorok:BAAALgADCgEJAQAAAA==.',
Ff='Ff:BAAALgAECgQJBAAAAA==.',
Fi='Finnster:BAABLgAECn8zAAIKAAkJXQ7oTAC3AQAKAAkJXQ7oTAC3AQAAAA==.Fionna:BAAALgAECgcJDAAAAA==.Firereina:BAAALgADCggJGQABLgAECggJKAAGAJsTAA==.',
Fl='Fleurminator:BAABLgAECn8gAAICAAkJBxGRLwCPAQACAAkJBxGRLwCPAQAAAA==.Fluffybaby:BAAALgADCgMJAwAAAA==.',
Fo='Fondadix:BAABLgAECn8lAAIUAAkJpyHRCQB1AgAUAAkJpyHRCQB1AgAAAA==.',
Fr='Frieia:BAABLgAECn8cAAITAAgJ3weUYwAHAQATAAgJ3weUYwAHAQAAAA==.Frostiilocks:BAAALgAECggJCQAAAA==.Frostitutte:BAAALgAECgYJEQAAAA==.Frozenjade:BAAALgAECgMJAwAAAA==.Fryértuck:BAAALgAECgEJAQABLgAECgQJCgAHAAAAAA==.',
Fu='Fuze:BAAALgAECgYJDAAAAA==.',
Ga='Galakrosh:BAACLgAFFH8HAAMfAAMJASE7DgCdAAAcAAMJASHgbwDcAAAfAAIJ9B87DgCdAAAuAAQKfyoABB8ACAkYJF8FADECABwACAlwHT4XAMkCAB8ACAlpIl8FADECACAAAQkAAIFjAEgAAAAA.Galarína:BAABLgAECn84AAMDAAkJFCJVDADPAgADAAgJqSFVDADPAgAEAAkJ8R3PCwCEAgAAAA==.Gandora:BAABLgAECn8gAAMZAAkJwxbQTQDXAQAZAAkJwxbQTQDXAQAQAAEJ/wPUPwAkAAAAAA==.Gardrius:BAAALgADCgEJAQAAAA==.',
Ge='Gene:BAAALgADCgcJBwAAAA==.Gentonord:BAABLgAECn8cAAMCAAgJJhoDQQChAQACAAgJBRcDQQChAQAhAAYJXBdrIAA9AQAAAA==.',
Gi='Gingerports:BAAALgADCgEJAQAAAA==.',
Gk='Gkmc:BAABLgAFFH8MAAIZAAYJ5yQpFAArAgAZAAYJ5yQpFAArAgABLgAFFAgJKAAYANAjAA==.',
Gl='Glomps:BAAALgAFFAMJAwABLgAFFAUJBgAiAFkEAA==.',
Go='Gonaldduck:BAAALgAECgYJBgAAAA==.',
Gr='Greasemunkey:BAABLgAECn8vAAIWAAkJCBUACwAIAgAWAAkJCBUACwAIAgAAAA==.Greentea:BAAALgADCggJCwAAAA==.Griiv:BAACLgAFFH8FAAINAAIJBB0yiQCWAAANAAIJBB0yiQCWAAAuAAQKfyMAAg0ACAnNISEWAOQCAA0ACAnNISEWAOQCAAAA.Grislytotem:BAAALgADCgYJCAAAAQ==.Grislywolf:BAAALgAECgUJBQAAAA==.',
Ha='Hakunamatata:BAAALgAECgUJBwAAAA==.Hamburger:BAABLgAECn8ZAAIbAAcJWxV8KwB2AQAbAAcJWxV8KwB2AQAAAA==.Hammerhard:BAAALgADCgcJDgAAAA==.Hampter:BAAALgAECgYJCQABLgAECgkJJQAbAMgaAA==.Hanita:BAAALgAECgEJAgAAAA==.Haymáker:BAAALgADCgIJAgAAAA==.',
He='Heights:BAAALgAECgUJDgAAAA==.Heliosan:BAAALgAECgEJBAAAAA==.Heyu:BAAALgAECgUJCAABLgAECggJGwAKABcWAA==.',
Hi='Himoe:BAAALgADCgcJDgAAAA==.',
Ho='Holybean:BAAALgADCgkJGAABLgAECgUJDwAHAAAAAA==.Holyhench:BAAALgAECgUJBQAAAA==.Honkeykong:BAAALgADCgIJAgAAAA==.Hoochix:BAAALgAECgQJCQAAAA==.',
Hr='Hrsho:BAAALgADCgQJBAAAAA==.Hrshoo:BAAALgAFFAIJAwAAAA==.',
Hu='Humzashaind:BAABLgAECn8fAAMjAAgJtRGLOwDSAAACAAcJyQ3EUAAFAQAjAAYJeA+LOwDSAAAAAA==.Huntinrabits:BAAALgADCgIJAgAAAA==.Huntt:BAAALgAECgEJAQAAAA==.Huzzyy:BAAALgAECggJDAABLgAECgkJHwAVAN0bAA==.',
Hy='Hyphira:BAAALgAECgQJCgABLgAECgUJDQAHAAAAAA==.',
In='Inferbloom:BAAALgAECggJCAABLgAFFAQJDwAHAAAAAA==.Infernum:BAAALgAFFAQJDwAAAQ==.Insomnia:BAAALgAECgUJBQAAAA==.',
Ir='Irayvia:BAAALgADCgIJAgAAAA==.',
Ja='Jackyvoker:BAABLgAECn8qAAMLAAkJfCLhAQBnAwALAAkJfCLhAQBnAwAGAAMJqRmCJwDlAAAAAA==.Jaezzon:BAAALgADCgQJBwAAAA==.Janessah:BAAALgADCgEJAQAAAA==.',
Je='Jeannaah:BAAALgAECgQJBAABLgAECgcJDwAHAAAAAA==.Jetaime:BAAALgAECgUJBQAAAA==.',
Jh='Jharia:BAAALgADCgMJAgAAAA==.',
Ji='Jinksey:BAAALgAECgcJDQABLgAECgcJEQAdABETAA==.',
Jo='Johndoom:BAAALgAECgYJDgAAAA==.Johnfist:BAAALgAECgEJBAAAAA==.Johngrippy:BAAALgAECgEJAwAAAA==.Johnrend:BAAALgAECgEJAQAAAA==.',
Ju='Juicybottoms:BAAALgADCgMJAgAAAA==.',
Ka='Kairstia:BAAALgAECgMJAwABLgAECggJKAAGAJsTAA==.Kalidormi:BAAALgAECgYJCgAAAA==.Kalzious:BAAALgADCgkJHAAAAA==.Kamikaze:BAAALgAECgcJBQAAAA==.Kayelalynn:BAABLgAECn8oAAMFAAkJuxfxFgAUAgAFAAkJuxfxFgAUAgATAAMJNgEowgBDAAAAAA==.',
Kd='Kd:BAAALgAECgEJAgAAAA==.',
Ke='Kegpaw:BAAALgAFFAEJAQAAAA==.Keiri:BAAALgADCgYJBgAAAA==.Kelana:BAABLgAECn8lAAIRAAkJxB/HCACkAgARAAkJxB/HCACkAgAAAA==.Kendô:BAAALgAECgcJDAAAAA==.Ketdealer:BAAALgAECgcJDQAAAA==.Ketzendk:BAAALgAECgYJBQAAAA==.Keyahi:BAACLgAFFH8XAAIdAAYJRBt+JQCNAQAdAAYJRBt+JQCNAQAuAAQKfx0AAh0ACQk0HHkiAEQCAB0ACQk0HHkiAEQCAAEuAAQKAQkBAAcAAAAA.',
Kh='Khaean:BAAALgADCgkJCQAAAA==.Khety:BAAALgAECgQJBAAAAA==.',
Ki='Kickandpunch:BAAALgAECgYJDgAAAA==.Kicsi:BAAALgAECgIJAwAAAA==.Kilan:BAABLgAECn8gAAMNAAgJXRQwfQBxAQANAAcJjhMwfQBxAQAMAAIJNBgeNgCEAAAAAA==.Killinrage:BAAALgAECgYJDgAAAA==.Kissofpaine:BAAALgADCgIJAgAAAA==.Kitsuney:BAAALgADCgMJAwAAAA==.Kizaru:BAAALgAECgcJCAAAAA==.',
Ko='Korz:BAAALgADCgcJBwABLgAECgcJFQAYAOEXAA==.',
Kp='Kpop:BAAALgAECgEJAQAAAA==.',
Kr='Krutree:BAAALgAECgcJCQAAAA==.Krynj:BAAALgAFFAEJAwAAAA==.',
Ku='Kumokiri:BAAALgAECgIJAgAAAA==.Kuromu:BAAALgAFFAIJBAAAAA==.Kurzzon:BAAALgADCgMJAwAAAA==.',
Ky='Kyleata:BAACLgAFFH8FAAIKAAMJlgvgYwDVAAAKAAMJlgvgYwDVAAAuAAQKfzoAAgoACAk/HrcqAC4CAAoACAk/HrcqAC4CAAAA.Kyleigh:BAAALgAECgQJBQABLgAECgcJDwAHAAAAAA==.Kyokin:BAACLgAFFH8FAAINAAIJnxJhjQCPAAANAAIJnxJhjQCPAAAuAAQKfzoAAw0ACQkiFnw9AA0CAA0ACAmMGHw9AA0CAAwACAnwBtQxAJkAAAAA.Kyzula:BAABLgAECn8tAAIPAAcJ5RbgNQDVAQAPAAcJ5RbgNQDVAQAAAA==.',
['Kê']='Kêndo:BAAALgAECgEJAwABLgAECgcJDAAHAAAAAA==.',
La='Lace:BAAALgADCgMJAwAAAA==.Launam:BAAALgAECgMJBAAAAA==.Laytone:BAAALgADCgYJBwAAAA==.',
Le='Legcurl:BAAALgAECgEJAwAAAA==.Lepotko:BAAALgAECgQJBAAAAA==.',
Li='Lightbear:BAAALgAECgMJAwAAAA==.Lilchub:BAAALgAECgIJAwAAAA==.Lilylocks:BAAALgAECgcJCQAAAA==.Lilyrocks:BAAALgAECgUJCQAAAA==.Literallad:BAAALgADCgcJBgAAAA==.Littlelo:BAAALgAECgYJEgAAAA==.',
Ll='Llortdnaz:BAAALgADCgEJAgAAAA==.',
Lo='Lockology:BAAALgAFFAEJAQAAAA==.Lokarg:BAAALgADCgIJAgAAAA==.Loudcry:BAACLgAFFH8KAAIXAAUJ9hDCAAB1AQAXAAUJ9hDCAAB1AQAuAAQKfzMAAxcACQlvHrQBAKkCABcACAkAIbQBAKkCABgAAwm0ECT3ALUAAAAA.',
Lu='Lunaeria:BAAALgADCggJCAAAAA==.',
Ly='Lyanah:BAACLgAFFH8eAAITAAUJ+gn8KwAAAQATAAUJ+gn8KwAAAQAuAAQKfywAAhMACQm3FgUkACgCABMACQm3FgUkACgCAAAA.Lydia:BAAALgAECgQJAQAAAA==.Lyniah:BAAALgAECgQJBQAAAA==.',
Ma='Machete:BAAALgAECgQJCQAAAA==.Maelius:BAABLgAECn82AAMVAAkJRhu3DQC1AgAVAAkJRhu3DQC1AgAMAAQJqQOMOQBzAAAAAA==.Maggrus:BAABLgAECn8bAAIKAAgJFxZkVgCcAQAKAAgJFxZkVgCcAQAAAA==.Malavel:BAAALgADCggJCAAAAA==.Malically:BAACLgAFFH8FAAMKAAMJjhQpWQDqAAAKAAMJjhQpWQDqAAAkAAEJYwQzOgAzAAAuAAQKfyAAAyQACQlpEHASADIBACQACAmCEXASADIBAAoABgntCw2SABYBAAAA.Manshoon:BAAALgADCgcJCwAAAA==.Marlory:BAAALgADCgUJBQAAAA==.Math:BAEALgAFFAEJAQABLgAFFAYJCwAiAAYPAA==.Matheney:BAEBLgAFFH8QAAISAAcJCA62BQCbAQASAAcJCA62BQCbAQABLgAFFAYJCwAiAAYPAA==.Matsuzo:BAAALgAECgEJAQAAAA==.Maxnem:BAAALgADCggJCAABLgAECggJHwAFADMPAA==.',
Mc='Mcrib:BAAALgADCggJBQAAAA==.Mctubby:BAAALgADCgUJBQABLgADCgUJBgAHAAAAAA==.Mctubmonk:BAAALgADCgUJBgAAAA==.',
Me='Meatpopsicle:BAAALgADCgEJAQAAAA==.Meigz:BAAALgAECgQJCwAAAA==.Melicious:BAAALgAECgQJBAAAAA==.Melidin:BAAALgAECgkJEgAAAA==.Melinda:BAAALgAFFAEJAQAAAA==.Melindorei:BAAALgAECgEJAgAAAA==.Melledrus:BAAALgAECgEJAQAAAA==.Mememo:BAAALgAECgMJAwAAAA==.Menöpaws:BAEALgAFFAMJAwAAAA==.Merithrá:BAAALgAECgMJAwAAAA==.',
Mi='Mikaeljayfox:BAAALgAECgcJDwAAAQ==.Mikros:BAAALgAECgQJBgAAAA==.Milenzha:BAABLgAECn8kAAIKAAgJNBZoRwDHAQAKAAgJNBZoRwDHAQAAAA==.Milkymaiden:BAAALgADCgMJBQABLgADCgYJCQAHAAAAAA==.Mimachote:BAABLgAECn8VAAISAAkJMg6NGwBsAQASAAkJMg6NGwBsAQAAAA==.',
Mo='Monetta:BAAALgADCgIJAgAAAA==.Monk:BAAALgAECggJEAAAAA==.Moonblood:BAAALgADCggJEAAAAA==.Moonfighter:BAAALgAECgEJAgAAAA==.Moontann:BAAALgAECgEJAQAAAA==.Morcombe:BAAALgAECgEJAQAAAA==.Moreia:BAAALgAECgMJAwAAAA==.Motown:BAAALgAECgYJCwAAAA==.Mousse:BAAALgAECgYJEgAAAA==.',
Mu='Murdalok:BAABLgAECn8ZAAITAAgJshWdNQDSAQATAAgJshWdNQDSAQAAAA==.Murdergodx:BAAALgAECgYJBgAAAA==.',
My='Mysharona:BAAALgAECgEJAQAAAA==.Mystahmurdah:BAAALgAECgEJAQABLgAECgcJFgAlAM4TAA==.Mysterioñ:BAAALgAECgQJDQAAAA==.',
['Má']='Mákla:BAAALgAECgMJAwAAAA==.',
['Mâ']='Mâstermînd:BAAALgAECgUJDgAAAA==.',
Na='Nahte:BAAALgADCgYJCQAAAA==.Naiana:BAAALgADCgMJAwAAAA==.Nasine:BAAALgAECgYJCAABLgAECgkJGwAOAPYdAA==.Natstryker:BAABLgAECn9JAAQRAAkJ4SYiAACUAwARAAkJ4SYiAACUAwAEAAgJ8CJMFQBCAgADAAcJMRFKQgBcAQAAAA==.Naturemyth:BAAALgAFFAEJAwAAAA==.Nazu:BAAALgADCgUJCgAAAA==.',
Ne='Neeró:BAABLgAECn8iAAMdAAYJphXOegAnAQAdAAYJphXOegAnAQAIAAEJtxQfZQA+AAAAAA==.Nelthon:BAAALgADCgYJBgAAAA==.',
Ni='Nishastraza:BAAALgAECgEJAwABLgAECgcJDwAHAAAAAA==.',
No='Nonaha:BAAALgADCgkJEQAAAA==.Notsoda:BAAALgAECgQJCQAAAA==.',
Nu='Nuciferas:BAAALgADCgUJBQAAAA==.',
Oa='Oaf:BAAALgAECgYJBgAAAA==.',
Om='Omcmoneyshot:BAAALgADCgEJAQAAAA==.',
Oo='Oolong:BAAALgAECgQJBQAAAA==.',
Or='Ordomalleus:BAAALgADCgEJAQAAAA==.Organa:BAABLgAECn8jAAICAAgJoArYPQBNAQACAAgJoArYPQBNAQAAAA==.',
Ou='Outofthedark:BAAALgAECgIJAgAAAA==.',
Pa='Pakkan:BAAALgAECgEJAQAAAA==.Pallyqb:BAAALgADCgEJAQAAAA==.Palyomie:BAAALgAECgEJAQAAAA==.Pandariam:BAAALgAECgYJCwAAAA==.Pauladeenx:BAAALgAECgIJAwABLgAECgUJDgAHAAAAAA==.',
Pe='Petal:BAAALgAECgYJBwABLgAECggJEAAHAAAAAA==.',
Pl='Playwitwe:BAAALgAECgUJCAAAAA==.Plowmcballs:BAABLgAECn8ZAAINAAYJtxIzfgB+AQANAAYJtxIzfgB+AQAAAA==.Plugley:BAABLgAECn8dAAMYAAkJqBjQOgArAgAYAAkJqBjQOgArAgAXAAEJARSGHAA6AAAAAA==.',
Po='Polaris:BAAALgAECgEJAQAAAA==.Poober:BAABLgAECn8hAAMaAAkJbx9ADACfAgAaAAgJeCFADACfAgAmAAQJNBlRNgA6AQAAAA==.Potooòooóoo:BAABLgAECn8dAAIQAAcJVhgtFQAuAQAQAAcJVhgtFQAuAQAAAA==.',
Pr='Pren:BAAALgAFFAEJAQAAAA==.Privet:BAAALgAECgEJAwAAAA==.',
Pu='Purebeef:BAAALgAECgIJAgAAAA==.',
Py='Pygos:BAABLgAECn8ZAAInAAgJ5BiJBwANAgAnAAgJ5BiJBwANAgAAAA==.',
['Pë']='Përdü:BAAALgAECggJEgAAAA==.',
Qu='Quigglay:BAAALgAECgYJBgAAAA==.',
Ra='Raegnarok:BAABLgAECn8hAAIVAAgJ/ROUIgDtAQAVAAgJ/ROUIgDtAQAAAA==.Raelessa:BAAALgAECgQJCQABLgAECgcJDwAHAAAAAA==.Raigeki:BAAALgADCgQJBQAAAA==.Ralf:BAAALgAECgEJAQAAAA==.Ralphie:BAAALgAECgIJAgAAAA==.Ratapew:BAABLgAECn8VAAIdAAgJzxSUUwCIAQAdAAgJzxSUUwCIAQAAAA==.Ratheen:BAABLgAECn8dAAINAAgJtA68mABAAQANAAgJtA68mABAAQAAAA==.Raytar:BAABLgAECn8gAAMFAAkJNB/6DwBgAgAFAAgJPyD6DwBgAgATAAMJ9RsBmwCWAAAAAA==.',
Re='Rekkirin:BAAALgAECgUJBQABLgAECgkJOAALAAUWAA==.Relyk:BAAALgADCgUJBQAAAA==.',
Ri='Riyo:BAAALgAFFAIJAwAAAA==.',
Ro='Roachie:BAAALgAECgYJDgAAAA==.Rockandstone:BAAALgADCgEJAQAAAA==.Roesira:BAAALgAECgEJAQAAAA==.Rogun:BAAALgAECgkJAQAAAA==.Ros:BAAALgAECgMJBAAAAA==.',
Ru='Rug:BAAALgADCgYJBgAAAA==.Rustybray:BAABLgAECn81AAIOAAkJhgeRQQApAQAOAAkJhgeRQQApAQAAAA==.Ruu:BAAALgAECgkJBQABLgAFFAQJDgAlAAQRAA==.',
Ry='Ryvulz:BAABLgAECn8eAAIbAAgJHRWsGAAcAgAbAAgJHRWsGAAcAgAAAA==.',
Sa='Salomicum:BAAALgADCgEJAQAAAA==.Sappollo:BAAALgADCgMJAwAAAA==.Sarabi:BAABLgAECn8nAAIDAAgJlBVJJgDtAQADAAgJlBVJJgDtAQAAAA==.Sarena:BAAALgADCgMJAwAAAA==.Sarkoth:BAAALgADCgEJAQAAAA==.',
Sc='Schnee:BAAALgADCgYJCgAAAA==.Schutzhund:BAAALgAECgMJAgAAAA==.Scrapster:BAAALgAECgUJDAAAAA==.',
Se='Seifer:BAAALgADCgEJAQAAAA==.Sekha:BAAALgAECgQJBgABLgAECggJIQAFAOoXAA==.Serbero:BAAALgAECgEJAQAAAA==.Serelia:BAABLgAFFH8GAAIDAAMJSBO+OgCwAAADAAMJSBO+OgCwAAAAAA==.Seshiro:BAAALgAECgQJBAABLgAECgkJNQAMANkjAA==.',
Sh='Shadoweave:BAACLgAFFH8bAAMaAAUJ9Bd0DwBUAQAaAAUJ9Bd0DwBUAQAbAAIJSA2yLgCGAAAuAAQKfxkAAhoACQkoGDkTAD4CABoACQkoGDkTAD4CAAEuAAUUCAkyAAoARhkA.Shalalia:BAABLgAECn8hAAIKAAcJNw4ecgBXAQAKAAcJNw4ecgBXAQAAAA==.Shambean:BAAALgADCgEJAQABLgAECgUJDwAHAAAAAA==.Shammywitch:BAAALgAFFAEJAQABLgAECgQJCgAHAAAAAA==.Shentsu:BAABLgAECn8YAAIDAAkJ0CD7BQD/AgADAAkJ0CD7BQD/AgAAAA==.Shhanks:BAAALgAECgEJAQAAAA==.Shinmen:BAAALgADCgkJCQAAAA==.Shinsha:BAAALgADCgIJAwAAAA==.Shnizelnazee:BAABLgAECn8WAAINAAgJDwyWsAAbAQANAAgJDwyWsAAbAQAAAA==.Shortonheals:BAAALgAECgMJAwAAAA==.',
Si='Siege:BAAALgAECgUJBQAAAA==.Silie:BAAALgADCgEJAQAAAA==.Silik:BAAALgADCgcJBwAAAA==.Simpforsale:BAAALgAECgYJCQAAAA==.',
Sk='Skybladee:BAAALgAECgIJAgAAAA==.',
Sm='Smokeyb:BAACLgAFFH8IAAINAAMJ+AkKdQDEAAANAAMJ+AkKdQDEAAAuAAQKfywAAg0ACAlrFj9XAMMBAA0ACAlrFj9XAMMBAAAA.',
Sn='Sneevie:BAAALgAECggJCgAAAA==.Snorehees:BAABLgAECn8sAAMKAAkJwQ/kSwC6AQAKAAkJwQ/kSwC6AQAkAAQJMwLUNQBEAAAAAA==.',
So='Songarrow:BAAALgAECgYJBgAAAA==.Songstar:BAABLgAECn8uAAIKAAkJaiO9DwDPAgAKAAkJaiO9DwDPAgAAAA==.Soullraven:BAAALgADCgkJNAAAAA==.',
Sp='Spy:BAAALgAECgEJBQAAAA==.',
Sq='Squingledorf:BAAALgAECgMJAwAAAA==.',
St='Staavon:BAABLgAECn8nAAIYAAgJ8QlsjwBVAQAYAAgJ8QlsjwBVAQAAAA==.Stacy:BAAALgAECgEJAQABLgAECgQJCAAHAAAAAA==.Stalvis:BAAALgADCgUJBQAAAA==.Starblaze:BAAALgAECgYJCgAAAA==.Starseek:BAABLgAECn8VAAInAAcJLhDLEABDAQAnAAcJLhDLEABDAQAAAA==.Steelboats:BAAALgADCgkJGQAAAA==.',
Su='Sugarbow:BAAALgADCgMJAwAAAA==.Sugarhoof:BAAALgAECgcJCgAAAA==.Sugarlick:BAABLgAECn8jAAIUAAgJPRtJFwCqAQAUAAgJPRtJFwCqAQAAAA==.Sugarpop:BAACLgAFFH8GAAIVAAMJNw2sNACXAAAVAAMJNw2sNACXAAAuAAQKfygAAhUACQnXHIISAH4CABUACQnXHIISAH4CAAEuAAUUBAkOAA8ApBsA.Sunraku:BAAALgAECgIJAwAAAA==.Suplazindh:BAAALgAFFAIJAgABLgAFFAkJQAAQAJIhAA==.',
Sw='Swethort:BAAALgADCgcJBgAAAA==.',
Sy='Synman:BAAALgADCgYJBgAAAA==.Syntheria:BAAALgADCgcJDAAAAA==.Syrebriel:BAABLgAECn8VAAImAAcJCxEBJABzAQAmAAcJCxEBJABzAQAAAA==.',
['Sí']='Sílíbrítí:BAAALgAECgYJDQABLgAFFAMJCgADAHgNAA==.',
Ta='Taediah:BAAALgAFFAEJAQAAAA==.Tamius:BAAALgADCgEJAQAAAA==.Tanthanalas:BAAALgAECgQJBAAAAA==.',
Th='Thefalsehope:BAAALgADCgcJBwAAAA==.Theoutcast:BAAALgAECgQJDgAAAA==.Thesarius:BAABLgAECn8ZAAIhAAgJXxmXDQAxAgAhAAgJXxmXDQAxAgAAAA==.Thortor:BAAALgADCgIJAgABLgADCggJEAAHAAAAAA==.Thumbzie:BAAALgAECgMJAwAAAA==.',
Ti='Tiestto:BAAALgAECgcJDgAAAA==.Tinkermid:BAAALgADCgEJAQAAAA==.Tinymeatgang:BAAALgADCggJCQAAAA==.',
To='Tobalwl:BAAALgADCgUJBQAAAA==.Tockley:BAABLgAECn8hAAIYAAgJQwbN3ADbAAAYAAgJQwbN3ADbAAAAAA==.Toetagger:BAABLgAECn8eAAIZAAgJ4A++bACJAQAZAAgJ4A++bACJAQAAAA==.Tofino:BAAALgAECggJDwAAAA==.Tohner:BAAALgADCgMJAwAAAA==.Tolidron:BAAALgADCgEJAQAAAA==.Tonimâster:BAAALgAFFAEJAQAAAA==.Tonydmaster:BAAALgAECgEJAQAAAA==.Toyotama:BAAALgAECgUJDQAAAA==.',
Tr='Trashiepanda:BAAALgAECgYJEwAAAA==.Trenbologna:BAAALgAECgEJAQAAAA==.Tristah:BAAALgAECgUJDwABLgAECgcJDwAHAAAAAA==.Trzlawd:BAAALgADCgEJAQAAAA==.',
Ty='Tyindron:BAAALgAECgYJBwAAAA==.Tyrrial:BAABLgAECn8yAAINAAgJbRflUADUAQANAAgJbRflUADUAQAAAA==.Tyshus:BAAALgAECgYJDQAAAA==.',
Ud='Udntknwme:BAAALgAFFAIJAwAAAA==.',
Un='Unbral:BAAALgADCgEJAQAAAA==.Unicood:BAAALgADCgYJBgAAAA==.Unlockbot:BAAALgADCgEJAwABLgAECgcJDwAHAAAAAA==.Unnicron:BAAALgAECgMJAwAAAA==.Unwholey:BAAALgAECggJCAAAAA==.',
Ut='Uthgardt:BAAALgAECgYJBgABLgAECgYJCwAHAAAAAA==.',
Va='Valarion:BAABLgAECn8mAAIjAAgJ4RKfFgCjAQAjAAgJ4RKfFgCjAQAAAA==.Valcaryn:BAAALgADCgYJBgAAAA==.Validimus:BAABLgAECn8aAAMNAAgJnQeZsQAaAQANAAgJ8AaZsQAaAQAMAAIJ+QWfSwA6AAAAAA==.Valinis:BAAALgAECgQJBAAAAA==.Valinius:BAAALgADCgYJCQAAAA==.Valorían:BAABLgAECn9JAAQhAAkJeCXMAABnAwAhAAkJeCXMAABnAwACAAkJ+iFzCwCuAgAjAAIJAiB7QgC5AAAAAA==.Valtaa:BAAALgADCgUJBwAAAA==.Vanza:BAAALgADCgEJAQAAAA==.Varthayn:BAABLgAECn9DAAIYAAkJ4iDiGQC8AgAYAAkJ4iDiGQC8AgAAAA==.',
Ve='Vecna:BAAALgAECgMJAwABLgAECgYJCAAHAAAAAA==.Velandriel:BAAALgADCgkJCwABLgAECgkJOQAIANQYAA==.Vengfuhl:BAAALgAECgQJAwAAAA==.Verra:BAAALgAECgEJAQAAAA==.Vet:BAAALgAECgEJAQAAAA==.',
Vo='Voidwa:BAAALgAECggJEgAAAA==.Volbain:BAABLgAECn8tAAQIAAgJmhsoEQAUAgAIAAgJmhsoEQAUAgAnAAMJ5BESHwCgAAAdAAEJ0wI1MwEcAAAAAA==.Volklin:BAABLgAECn8pAAMlAAkJqhTcIQCOAQAlAAkJow7cIQCOAQAKAAcJaRTeTQB/AQAAAA==.Voltagex:BAABLgAECn8dAAIdAAcJfRw/VQCDAQAdAAcJfRw/VQCDAQAAAA==.',
Vu='Vulpsinculta:BAABLgAECn8kAAIcAAgJ6RRBSgC7AQAcAAgJ6RRBSgC7AQAAAA==.',
['Vï']='Vïrùs:BAABLgAECn8jAAIFAAcJeg1aPABDAQAFAAcJeg1aPABDAQAAAA==.',
Wa='Wanda:BAAALgAECgYJBgAAAA==.',
Wi='Wichita:BAABLgAECn80AAMZAAkJsA/8YQCiAQAZAAgJEhH8YQCiAQAUAAEJBQbiYwAfAAAAAA==.Wildkitty:BAAALgAFFAEJAQAAAA==.',
Wo='Wolfyze:BAAALgADCgEJAQAAAA==.',
Wr='Wrâth:BAAALgAECgEJAgAAAA==.',
Wt='Wtfartemis:BAAALgAECgQJBAAAAA==.Wtfguën:BAABLgAECn8pAAISAAgJ7gsnKgAFAQASAAgJ7gsnKgAFAQAAAA==.Wtftäzmikell:BAAALgADCgYJCQABLgAECggJKQASAO4LAA==.',
Wu='Wutäng:BAAALgADCgYJCgAAAA==.',
Xe='Xera:BAAALgADCgYJBgAAAA==.',
Xo='Xondra:BAAALgAECgYJDQAAAA==.',
Xr='Xravo:BAAALgADCgkJCQAAAA==.',
Xz='Xzairi:BAABLgAECn8hAAIFAAgJ6hdmJACkAQAFAAgJ6hdmJACkAQAAAA==.',
Ya='Yarria:BAAALgADCgIJAgAAAA==.',
Yi='Yinh:BAAALgADCgcJDAAAAA==.',
Yo='Yoiki:BAAALgAECgEJAQABLgAECgEJAQAHAAAAAA==.',
Yu='Yuck:BAAALgAECgIJBAAAAA==.',
Yy='Yy:BAAALgAECgUJDAAAAA==.',
Ze='Zeuzco:BAAALgAECgkJEQAAAA==.',
Zo='Zorell:BAAALgAECgYJDQAAAA==.Zovaal:BAAALgAECgQJBAAAAA==.',
['Ál']='Áltá:BAABLgAECn8uAAMcAAkJURlBJgBDAgAcAAkJURlBJgBDAgAgAAIJNwyQMgBSAAAAAA==.',
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
