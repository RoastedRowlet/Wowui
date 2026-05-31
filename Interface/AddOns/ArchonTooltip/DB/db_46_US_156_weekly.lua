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

local lookup = {'Rogue-Outlaw','Warrior-Fury','Monk-Mistweaver','Monk-Windwalker','Druid-Balance','Evoker-Devastation','Unknown-Unknown','DemonHunter-Havoc','Shaman-Enhancement','Hunter-BeastMastery','Evoker-Preservation','Paladin-Protection','Paladin-Retribution','Shaman-Elemental','Shaman-Restoration','DeathKnight-Frost','Monk-Brewmaster','Druid-Guardian','Druid-Restoration','DeathKnight-Blood','Paladin-Holy','Druid-Feral','Mage-Arcane','Mage-Frost','DeathKnight-Unholy','Priest-Holy','Priest-Shadow','Warlock-Demonology','DemonHunter-Devourer','Rogue-Subtlety','Warlock-Affliction','Warlock-Destruction','Warrior-Protection','Evoker-Augmentation','Warrior-Arms','Hunter-Marksmanship','Priest-Discipline','DemonHunter-Vengeance','Hunter-Survival',}
local provider = {region='US',realm='Misha',name='US',type='weekly',zone=46,date='2026-05-30',data={Ac='Acidburn:BAABLgAECn8WAAIBAAcJ0BroAwDvAQABAAcJ0BroAwDvAQAAAA==.',
Ae='Aea:BAAALgAECgIJBAAAAA==.Aevie:BAAALgAECgYJDwAAAA==.',
Af='Afterlìfe:BAAALgAECgYJDQAAAA==.',
Ai='Ailis:BAAALgADCgQJBAAAAA==.',
Al='Alendria:BAAALgADCgYJBgAAAA==.Alizë:BAAALgADCgQJAwAAAA==.Alorillan:BAAALgAECgYJDQAAAA==.Altabrew:BAAALgAECgQJBAAAAA==.Altair:BAAALgAECgUJDwABLgAECgkJIQACABMhAA==.',
An='Andelynn:BAAALgAECgIJAgAAAA==.',
Ap='Applejuic:BAABLgAECn8UAAMDAAkJShY4FwA6AgADAAkJShY4FwA6AgAEAAEJNRCCjwAvAAAAAA==.Appless:BAAALgAECgQJBwAAAA==.',
Ar='Araylia:BAABLgAECn8fAAIFAAkJjAzmMQA5AQAFAAkJjAzmMQA5AQAAAA==.Aridella:BAABLgAECn8VAAIGAAYJRA5GEgDSAAAGAAYJRA5GEgDSAAAAAA==.Ariellaa:BAAALgAECgYJBgAAAA==.',
As='Ashaly:BAAALgADCgUJBQAAAA==.Ashlei:BAAALgAECgQJCAAAAA==.',
At='Atomseve:BAAALgADCgQJBAABLgAECggJEwAHAAAAAA==.',
Au='Aurafarmer:BAAALgADCgEJAQAAAA==.Autopsia:BAAALgADCgYJBgABLgAECgkJOQAIANQYAA==.Autumn:BAAALgADCgUJBwAAAA==.',
Av='Avalorne:BAAALgAECgMJAwABLgAECgkJIQACABMhAA==.Avena:BAAALgADCgEJAgAAAA==.',
Az='Azaizel:BAAALgAECgYJCwAAAA==.Azusie:BAABLgAECn81AAIJAAkJehdrCAAkAgAJAAkJehdrCAAkAgAAAA==.',
Ba='Baddate:BAABLgAECn8ZAAIKAAcJhA0laABbAQAKAAcJhA0laABbAQAAAA==.Baddragøn:BAABLgAECn84AAMLAAkJBRaYDAD5AQALAAgJ0xWYDAD5AQAGAAgJxg+aCACTAQAAAA==.Balthaas:BAABLgAECn82AAMMAAkJyhgqCQAkAgAMAAkJyhgqCQAkAgANAAEJewdjUQErAAAAAA==.Bangen:BAAALgAECgcJDwAAAA==.Bastria:BAAALgAECgYJDAAAAA==.Baulters:BAAALgAECgQJBgAAAA==.',
Be='Beenn:BAAALgAECgYJBgAAAA==.',
Bh='Bharko:BAAALgADCgcJCgABLgAFFAYJDgAKADodAA==.',
Bi='Billyblastin:BAAALgADCgMJAwABLgAECgkJJQAOAFgZAA==.Billywitchdr:BAABLgAECn8lAAMOAAkJWBk0FgAbAgAOAAkJWBk0FgAbAgAPAAEJFgaixAArAAAAAA==.Biocryo:BAAALgADCgYJBgABLgAECggJEAAHAAAAAA==.',
Bl='Blazingpanda:BAAALgAECgMJBAAAAA==.Blizeatsass:BAAALgADCgMJAwAAAA==.Bluedomino:BAAALgAECgMJCAAAAA==.Bluetoykawi:BAABLgAECn8zAAIQAAgJKxYhCgCwAQAQAAgJKxYhCgCwAQAAAA==.',
Bo='Boats:BAAALgADCgIJAgAAAA==.Boltspark:BAAALgADCgMJAwAAAA==.Borgo:BAAALgAECgYJBgAAAA==.Bowlenciaga:BAABLgAECn8UAAIKAAYJlghAkQACAQAKAAYJlghAkQACAQAAAA==.Bozilla:BAAALgADCgMJAwAAAA==.',
Br='Braelia:BAAALgADCgcJCAAAAA==.Brainfart:BAAALgADCgUJBQABLgAECggJGwAKABcWAA==.Breloom:BAAALgADCgEJAQAAAA==.Bruithis:BAAALgADCgIJAgAAAA==.',
Bu='Burdan:BAAALgADCgQJBAAAAA==.Buttermebuns:BAAALgADCgcJCAAAAA==.',
Ca='Cariandria:BAAALgAECgUJBgAAAA==.',
Cc='Cc:BAAALgAECgEJAgAAAA==.',
Ch='Chahaein:BAAALgAECgYJDwAAAA==.Charbaby:BAAALgAECgYJEwABLgAFFAUJFgARABYfAA==.Charhartt:BAABLgAECn8VAAMSAAYJYxerGwBLAQASAAYJYxerGwBLAQATAAEJVwfa2gAjAAABLgAFFAUJFgARABYfAA==.Charita:BAAALgAECgMJBAABLgAFFAUJFgARABYfAA==.Charizard:BAAALgAECgEJAQABLgAFFAUJFgARABYfAA==.Charming:BAACLgAFFH8WAAIRAAUJFh/5FABWAQARAAUJFh/5FABWAQAuAAQKfyAAAhEACAnXGcUcAB0CABEACAnXGcUcAB0CAAAA.Charmonic:BAAALgAECgQJBwABLgAFFAUJFgARABYfAA==.Chelseah:BAAALgAECgYJEAABLgAECgcJDwAHAAAAAA==.',
Ci='Cinderlight:BAAALgAECgEJAQAAAA==.',
Cl='Clanker:BAAALgAECgkJEgAAAA==.',
Co='Coldknight:BAABLgAECn8eAAMQAAcJjQJ7IwB4AAAQAAcJWAJ7IwB4AAAUAAUJ6AE6RwBYAAAAAA==.Conien:BAAALgADCgQJBAAAAA==.Conifer:BAABLgAECn8WAAITAAcJEhpWJwACAgATAAcJEhpWJwACAgAAAA==.Coniption:BAAALgADCgEJAQAAAA==.Contrlurself:BAAALgAECgYJBgABLgAECgkJJAAFAF4VAA==.Copium:BAAALgAECgQJBwAAAA==.Cornpop:BAAALgAECgYJCAAAAA==.Cowret:BAABLgAECn9AAAMVAAkJkyEmAgB/AwAVAAkJkyEmAgB/AwANAAEJAABZqgEAAAAAAA==.',
Cr='Crystalwolf:BAABLgAECn8VAAIWAAYJiwXAKAClAAAWAAYJiwXAKAClAAAAAA==.',
Cu='Curze:BAAALgAECgMJAwAAAA==.',
Cy='Cyonna:BAAALgADCgQJBAAAAA==.',
Da='Darc:BAABLgAECn8WAAICAAQJXCXUPgCpAQACAAQJXCXUPgCpAQAAAA==.Darkfoxgrime:BAAALgAECgkJCQABLgAECgkJJAAEAHkQAA==.Darkjager:BAABLgAECn8rAAIKAAkJHR6lJgAvAgAKAAkJHR6lJgAvAgAAAA==.Darkways:BAAALgAECgcJAQAAAA==.Darlah:BAABLgAECn8WAAIXAAcJTRD0BQBQAQAXAAcJTRD0BQBQAQAAAA==.Darnalin:BAAALgAECgEJAgABLgAECgkJOQAIANQYAA==.Dayva:BAAALgAECgQJBgAAAA==.Dayyva:BAAALgAECgQJDgAAAA==.',
De='Deadcobra:BAABLgAECn8hAAIYAAkJegQEoAAgAQAYAAkJegQEoAAgAQAAAA==.Deathbean:BAAALgADCgQJBAABLgAECgUJDwAHAAAAAA==.Debtknight:BAABLgAECn84AAIZAAkJ6h/PEgDGAgAZAAkJ6h/PEgDGAgAAAA==.Deelo:BAAALgAECgEJAQAAAA==.Dehumidifier:BAABLgAECn8oAAMaAAkJlx4zDwBdAgAaAAkJlx4zDwBdAgAbAAkJQw32IQCYAQAAAA==.Deltria:BAAALgAECgYJDQAAAA==.Demonrot:BAABLgAECn8VAAIcAAgJSwsObABYAQAcAAgJSwsObABYAQAAAA==.Dervin:BAAALgADCgQJBAABLgAECggJCAAHAAAAAA==.Deviltank:BAAALgADCgYJDAAAAA==.Devohsup:BAABLgAECn8dAAIdAAgJlB+NHABVAgAdAAgJlB+NHABVAgAAAA==.Devussi:BAABLgAECn8mAAIdAAkJyBQfQQCuAQAdAAkJyBQfQQCuAQABLgAECgUJBQAHAAAAAA==.',
Di='Dienva:BAAALgAECgUJBQAAAA==.Digmyearth:BAAALgAECgMJAwAAAA==.Dilea:BAAALgAECgUJBQAAAA==.',
Dk='Dksakp:BAAALgADCgkJGAAAAA==.',
Do='Dominateelf:BAAALgADCgQJBAABLgAECgMJBAAHAAAAAA==.Dotero:BAAALgAECgUJDAAAAA==.',
Dr='Dracreina:BAABLgAECn8lAAMGAAYJTRZDCwBPAQAGAAYJTRZDCwBPAQALAAEJQQYIOwAmAAAAAA==.Dreouss:BAAALgAECgQJBgAAAA==.Driver:BAEALgAFFAIJAwABLgAFFAUJDwAcALYLAA==.',
Du='Dumeslayer:BAAALgADCgcJCQAAAA==.Durzoe:BAABLgAECn8WAAIeAAcJlwoFOQBNAQAeAAcJlwoFOQBNAQAAAA==.',
Dv='Dvsmage:BAAALgAECgUJDwAAAA==.',
Eg='Egaik:BAAALgAECgYJBQAAAA==.',
El='Elarred:BAAALgADCgkJFAAAAA==.Elfkr:BAAALgAECgkJAgAAAA==.Elissauna:BAAALgAECggJEwAAAA==.Elylea:BAABLgAECn8fAAICAAgJvRoRGwABAgACAAgJvRoRGwABAgAAAA==.',
En='Enorme:BAAALgADCgQJBAAAAA==.',
Eu='Eunice:BAAALgADCgIJAgAAAA==.',
Ez='Ezili:BAAALgAECgEJAQAAAA==.',
Fa='Failure:BAAALgAECgIJAwAAAA==.Falabala:BAAALgAECgMJAwAAAA==.Fanghür:BAAALgADCgcJDgAAAA==.',
Fe='Feeloow:BAAALgADCgcJCwAAAA==.Felhound:BAAALgAECgUJDAAAAA==.Felussi:BAAALgAECgUJBQAAAA==.Feorahir:BAAALgAECgQJBAAAAA==.Fermitorok:BAAALgADCgEJAQAAAA==.',
Ff='Ff:BAAALgAECgQJBAAAAA==.',
Fi='Finhead:BAABLgAECn8zAAIKAAkJXQ6mQgDCAQAKAAkJXQ6mQgDCAQAAAA==.Fionna:BAAALgAECgcJDAAAAA==.Firereina:BAAALgADCggJGQABLgAECgYJJQAGAE0WAA==.Fishbone:BAAALgAECgMJAwAAAA==.',
Fl='Fleurminator:BAABLgAECn8gAAICAAkJBxHsKgCWAQACAAkJBxHsKgCWAQAAAA==.Fluffybaby:BAAALgADCgMJAwAAAA==.',
Fo='Fondadix:BAABLgAECn8lAAIUAAkJpyE9CACAAgAUAAkJpyE9CACAAgAAAA==.',
Fr='Frieia:BAABLgAECn8ZAAITAAYJfAkKbADeAAATAAYJfAkKbADeAAAAAA==.Frostiilocks:BAAALgAECggJCQAAAA==.Frostitutte:BAAALgAECgYJEQAAAA==.',
Fu='Fuze:BAAALgAECgEJAgAAAA==.',
Ga='Galakrosh:BAACLgAFFH8HAAMfAAMJASFoCgCpAAAcAAMJASHtXwDqAAAfAAIJ9B9oCgCpAAAuAAQKfyoABB8ACAkYJFAEADcCABwACAlwHT4XAMkCAB8ACAlpIlAEADcCACAAAQkAAIFjAEgAAAAA.Galarína:BAABLgAECn83AAMDAAkJFCKMCgDQAgADAAgJqSGMCgDQAgAEAAkJ8R1ECgCLAgAAAA==.Gandora:BAABLgAECn8gAAMZAAkJwxZhRQDfAQAZAAkJwxZhRQDfAQAQAAEJ/wMONQAmAAAAAA==.Gardrius:BAAALgADCgEJAQAAAA==.',
Ge='Gene:BAAALgADCgcJBwAAAA==.Gentonord:BAABLgAECn8cAAMCAAgJJhoDQQChAQACAAgJBRcDQQChAQAhAAYJXBdrIAA9AQAAAA==.',
Gi='Gingerports:BAAALgADCgEJAQAAAA==.',
Gl='Glomps:BAAALgAFFAMJAwABLgAFFAUJBgAiAFkEAA==.',
Go='Gobruxinha:BAAALgADCgIJAQAAAA==.Gonaldduck:BAAALgAECgUJBQAAAA==.',
Gr='Greasemunkey:BAABLgAECn8mAAIWAAgJvg+QEwBgAQAWAAgJvg+QEwBgAQAAAA==.Greentea:BAAALgADCggJCwAAAA==.Griiv:BAACLgAFFH8FAAINAAIJBB0+cQCcAAANAAIJBB0+cQCcAAAuAAQKfyMAAg0ACAnNISEWAOQCAA0ACAnNISEWAOQCAAAA.Grislytotem:BAAALgADCgYJCAAAAQ==.',
Ha='Hakunamatata:BAAALgAECgUJBwAAAA==.Hamburger:BAABLgAECn8ZAAIbAAcJWxVMJwByAQAbAAcJWxVMJwByAQAAAA==.Hammerhard:BAAALgADCgYJCgAAAA==.Hampter:BAAALgAECgYJCQABLgAECgkJJQAbAMgaAA==.Hanita:BAAALgAECgEJAgAAAA==.Haymáker:BAAALgADCgIJAgAAAA==.',
He='Heights:BAAALgAECgUJDgAAAA==.Heliosan:BAAALgAECgEJAwAAAA==.Heyu:BAAALgAECgUJCAABLgAECggJGwAKABcWAA==.',
Hi='Himoe:BAAALgADCgcJDgAAAA==.',
Ho='Holybean:BAAALgADCgkJGAABLgAECgUJDwAHAAAAAA==.Holyhench:BAAALgAECgUJBQAAAA==.Honkeykong:BAAALgADCgIJAgAAAA==.Hoochix:BAAALgAECgQJCQAAAA==.',
Hr='Hrsho:BAAALgADCgQJBAAAAA==.Hrshoo:BAAALgADCgEJAQAAAA==.',
Hu='Humzashaind:BAABLgAECn8VAAMjAAcJ+A3gKgCcAAACAAUJ5wziZQCnAAAjAAUJbQ3gKgCcAAAAAA==.Huntinrabits:BAAALgADCgIJAgAAAA==.Huntt:BAAALgAECgEJAQAAAA==.Huzzyy:BAAALgAECggJCgABLgAECgkJHwAVAN0bAA==.',
Hy='Hyphira:BAAALgAECgQJCgABLgAECgUJDQAHAAAAAA==.',
In='Inferbloom:BAAALgAECggJCAABLgAFFAQJDwAHAAAAAA==.Infernum:BAAALgAFFAQJDwAAAQ==.Insomnia:BAAALgAECgUJBQAAAA==.',
Ir='Irayvia:BAAALgADCgIJAgAAAA==.',
Ja='Jackyvoker:BAABLgAECn8qAAMLAAkJfCKwAQBsAwALAAkJfCKwAQBsAwAGAAMJqRmCJwDlAAAAAA==.Jaezzon:BAAALgADCgQJBwAAAA==.Janessah:BAAALgADCgEJAQAAAA==.',
Je='Jeannaah:BAAALgAECgQJBAABLgAECgcJDwAHAAAAAA==.Jetaime:BAAALgAECgUJBQAAAA==.',
Jh='Jharia:BAAALgADCgMJAgAAAA==.',
Ji='Jinksey:BAAALgAECgcJDQABLgAECgcJEQAdABETAA==.',
Jo='Johndoom:BAAALgAECgYJDgAAAA==.Johnfist:BAAALgAECgEJBAAAAA==.Johngrippy:BAAALgAECgEJAwAAAA==.Johnrend:BAAALgAECgEJAQAAAA==.',
Ju='Juicybottoms:BAAALgADCgMJAgAAAA==.',
Ka='Kairstia:BAAALgAECgMJAwABLgAECgYJJQAGAE0WAA==.Kalidormi:BAAALgAECgUJCQAAAA==.Kalzious:BAAALgADCgkJHAAAAA==.Kamikaze:BAAALgAECgcJBQAAAA==.Kayelalynn:BAABLgAECn8kAAMFAAkJXhWuGADvAQAFAAkJXhWuGADvAQATAAMJNgEowgBDAAAAAA==.',
Kd='Kd:BAAALgAECgEJAgAAAA==.',
Ke='Kegpaw:BAAALgAFFAEJAQAAAA==.Keiri:BAAALgADCgYJBgAAAA==.Kelana:BAABLgAECn8lAAIRAAkJxB+eBwCpAgARAAkJxB+eBwCpAgAAAA==.Kendô:BAAALgAECgYJCgAAAA==.Ketdealer:BAAALgAECgcJDQAAAA==.Ketzendk:BAAALgAECgYJBQAAAA==.Keyahi:BAACLgAFFH8RAAIdAAUJ+Rn9LgA/AQAdAAUJ+Rn9LgA/AQAuAAQKfx0AAh0ACQk0HD4fAEUCAB0ACQk0HD4fAEUCAAEuAAQKAQkBAAcAAAAA.',
Kh='Khaean:BAAALgADCgkJCQAAAA==.Khety:BAAALgAECgQJBAAAAA==.',
Ki='Kickandpunch:BAAALgAECgYJDgAAAA==.Kicsi:BAAALgAECgIJAwAAAA==.Kilan:BAABLgAECn8dAAMNAAYJ/xZYtAD8AAANAAUJTRRYtAD8AAAMAAIJNBhsMQCGAAAAAA==.Killinrage:BAAALgAECgYJDgAAAA==.Kissofpaine:BAAALgADCgIJAgAAAA==.Kitsuney:BAAALgADCgMJAwAAAA==.Kizaru:BAAALgAECgcJCAAAAA==.',
Ko='Korz:BAAALgADCgcJBwABLgAECgcJFQAYAOEXAA==.',
Kp='Kpop:BAAALgAECgEJAQAAAA==.',
Kr='Krutree:BAAALgAECgcJBwAAAA==.Krynj:BAAALgAFFAEJAwAAAA==.',
Ku='Kumokiri:BAAALgAECgIJAgAAAA==.Kuromu:BAAALgAFFAIJAgAAAA==.Kurzzon:BAAALgADCgMJAwAAAA==.',
Ky='Kyleata:BAABLgAECn85AAIKAAgJIR4MKAAoAgAKAAgJIR4MKAAoAgAAAA==.Kyleigh:BAAALgAECgQJBQABLgAECgcJDwAHAAAAAA==.Kyokin:BAABLgAECn8zAAMNAAgJZhXyVACzAQANAAcJUxjyVACzAQAMAAgJ/wUrMACMAAAAAA==.Kyzula:BAABLgAECn8fAAIPAAYJtBQHTQBfAQAPAAYJtBQHTQBfAQAAAA==.',
['Kê']='Kêndo:BAAALgADCgQJBAAAAA==.',
La='Lace:BAAALgADCgMJAwAAAA==.Launam:BAAALgAECgEJAQAAAA==.Laytone:BAAALgADCgYJBwAAAA==.',
Le='Legcurl:BAAALgAECgEJAwAAAA==.Lepotko:BAAALgAECgQJBAAAAA==.',
Li='Lightbear:BAAALgADCgMJBQAAAA==.Lilchub:BAAALgAECgIJAwAAAA==.Lilylocks:BAAALgAECgcJCQAAAA==.Lilyrocks:BAAALgAECgUJCQAAAA==.Literallad:BAAALgADCgcJBgAAAA==.Littlelo:BAAALgAECgYJDAAAAA==.',
Lo='Lockology:BAAALgAFFAEJAQAAAA==.Lokarg:BAAALgADCgIJAgAAAA==.Loudcry:BAACLgAFFH8HAAIXAAQJYhHbAAA3AQAXAAQJYhHbAAA3AQAuAAQKfzMAAxcACQlvHrQBAKkCABcACAkAIbQBAKkCABgAAwm0ELvfALkAAAEuAAUUBQkLAAIAmxwA.',
Lu='Lunaeria:BAAALgADCggJCAAAAA==.',
Ly='Lyanah:BAACLgAFFH8WAAITAAQJoAh+MADfAAATAAQJoAh+MADfAAAuAAQKfywAAhMACQm3FmwhACkCABMACQm3FmwhACkCAAAA.Lydia:BAAALgADCgQJBAAAAA==.Lyniah:BAAALgAECgQJBQAAAA==.',
Ma='Machete:BAAALgAECgQJBgAAAA==.Maelius:BAABLgAECn8yAAIVAAkJRhvXCwC8AgAVAAkJRhvXCwC8AgAAAA==.Maggrus:BAABLgAECn8bAAIKAAgJFxZlSgCqAQAKAAgJFxZlSgCqAQAAAA==.Malavel:BAAALgADCggJCAAAAA==.Malically:BAABLgAECn8gAAMkAAkJaRBCEAA+AQAkAAgJghFCEAA+AQAKAAYJ7QuhhQAaAQAAAA==.Manshoon:BAAALgADCgcJCwAAAA==.Marlory:BAAALgADCgUJBQAAAA==.Math:BAAALgAECggJCAABLgAFFAYJCwAiAAYPAA==.Matheney:BAABLgAFFH8QAAISAAcJCA5wAwCyAQASAAcJCA5wAwCyAQABLgAFFAYJCwAiAAYPAA==.Maxnem:BAAALgADCggJCAABLgAECggJHwAFADMPAA==.',
Mc='Mcrib:BAAALgADCggJBQAAAA==.Mctubby:BAAALgADCgUJBQABLgADCgUJBgAHAAAAAA==.Mctubmonk:BAAALgADCgUJBgAAAA==.',
Me='Meatpopsicle:BAAALgADCgEJAQAAAA==.Meigz:BAAALgAECgQJCwAAAA==.Melicious:BAAALgAECgQJBAAAAA==.Melidin:BAAALgAECgkJEgAAAA==.Melinda:BAAALgAFFAEJAQAAAA==.Melindorei:BAAALgAECgEJAgAAAA==.Melledrus:BAAALgAECgEJAQAAAA==.Mememo:BAAALgAECgMJAwAAAA==.Menöpaws:BAEALgAFFAMJAwAAAA==.Merithrá:BAAALgAECgMJAwAAAA==.',
Mi='Mikaeljayfox:BAAALgAECgcJDwAAAQ==.Mikros:BAAALgAECgMJAwAAAA==.Milenzha:BAABLgAECn8kAAIKAAgJNBYdPgDRAQAKAAgJNBYdPgDRAQAAAA==.Milkymaiden:BAAALgADCgMJBAABLgADCgYJCQAHAAAAAA==.Mimachote:BAABLgAECn8VAAISAAkJMg5MFwByAQASAAkJMg5MFwByAQAAAA==.',
Mo='Monetta:BAAALgADCgIJAgAAAA==.Monk:BAAALgAECggJEAAAAA==.Moonblood:BAAALgADCggJEAAAAA==.Moonfighter:BAAALgAECgEJAgAAAA==.Moontann:BAAALgADCgkJIAAAAA==.Morcombe:BAAALgAECgEJAQAAAA==.Moreia:BAAALgADCgcJBwAAAA==.Motown:BAAALgAECgYJCwAAAA==.Mousse:BAAALgAECgYJEgAAAA==.',
Mu='Murdalok:BAABLgAECn8ZAAITAAgJshWdNQDSAQATAAgJshWdNQDSAQAAAA==.',
My='Mysharona:BAAALgAECgEJAQAAAA==.Mystahmurdah:BAAALgADCgQJBwABLgAECgcJEwAHAAAAAA==.Mysterioñ:BAAALgAECgQJDQAAAA==.',
['Má']='Mákla:BAAALgAECgMJAwAAAA==.',
['Mâ']='Mâstermînd:BAAALgAECgUJDgAAAA==.',
Na='Nahte:BAAALgADCgYJCQAAAA==.Naiana:BAAALgADCgMJAwAAAA==.Nasine:BAAALgAECgYJCAABLgAECgkJGgAOAO0dAA==.Natstryker:BAABLgAECn83AAQRAAkJXSVXAQBTAwARAAkJGCVXAQBTAwAEAAgJ8CJMFQBCAgADAAcJMRFMOQBaAQAAAA==.Naturemyth:BAAALgAFFAEJAwAAAA==.Nazu:BAAALgADCgUJCgAAAA==.',
Ne='Neeró:BAABLgAECn8iAAMdAAYJphV5cQAkAQAdAAYJphV5cQAkAQAIAAEJtxQLWQA+AAAAAA==.Nelthon:BAAALgADCgYJBgAAAA==.',
Ni='Nishastraza:BAAALgAECgEJAwABLgAECgcJDwAHAAAAAA==.',
No='Nonaha:BAAALgADCgkJEQAAAA==.Notsoda:BAAALgAECgQJCQAAAA==.',
Oa='Oaf:BAAALgAECgYJBgAAAA==.',
Oo='Oolong:BAAALgAECgQJBQAAAA==.',
Or='Organa:BAABLgAECn8fAAICAAYJ+gu7TAD9AAACAAYJ+gu7TAD9AAAAAA==.',
Ou='Outofthedark:BAAALgAECgIJAgAAAA==.',
Pa='Pakkan:BAAALgAECgEJAQAAAA==.Pallyqb:BAAALgADCgEJAQAAAA==.Pandariam:BAAALgADCgYJBgAAAA==.Pauladeenx:BAAALgAECgIJAwABLgAECgUJDgAHAAAAAA==.',
Pe='Petal:BAAALgAECgYJBwABLgAECggJEAAHAAAAAA==.',
Pl='Playwitwe:BAAALgAECgMJAwAAAA==.Plowmcballs:BAABLgAECn8ZAAINAAYJtxIzfgB+AQANAAYJtxIzfgB+AQAAAA==.Plugley:BAABLgAECn8dAAMYAAkJqBjWNgAmAgAYAAkJqBjWNgAmAgAXAAEJARSGHAA6AAAAAA==.',
Po='Polaris:BAAALgAECgEJAQAAAA==.Poober:BAABLgAECn8dAAMaAAkJbx9tCgCrAgAaAAgJeCFtCgCrAgAlAAEJKA/0YwBCAAAAAA==.Potooòooóoo:BAABLgAECn8dAAIQAAcJVhikEQAsAQAQAAcJVhikEQAsAQAAAA==.',
Pr='Pren:BAAALgAFFAEJAQAAAA==.Privet:BAAALgAECgEJAwAAAA==.',
Pu='Purebeef:BAAALgAECgIJAgAAAA==.',
Py='Pygos:BAABLgAECn8ZAAImAAgJ5BiJBwANAgAmAAgJ5BiJBwANAgAAAA==.',
['Pë']='Përdü:BAAALgAECgYJDQAAAA==.',
Qu='Quigglay:BAAALgAECgYJBgAAAA==.',
Ra='Raegnarok:BAABLgAECn8dAAIVAAgJaBOfIQDhAQAVAAgJaBOfIQDhAQAAAA==.Raelessa:BAAALgAECgQJCQABLgAECgcJDwAHAAAAAA==.Raigeki:BAAALgADCgQJBQAAAA==.Ralf:BAAALgAECgEJAQAAAA==.Ralphie:BAAALgAECgIJAgAAAA==.Ratapew:BAAALgAECgcJEAAAAA==.Ratheen:BAABLgAECn8dAAINAAgJtA7oiABDAQANAAgJtA7oiABDAQAAAA==.Raytar:BAABLgAECn8gAAMFAAkJNB8kDgBjAgAFAAgJPyAkDgBjAgATAAMJ9RsBmwCWAAAAAA==.',
Re='Rekkirin:BAAALgAECgUJBQABLgAECgkJOAALAAUWAA==.Relyk:BAAALgADCgUJBQAAAA==.',
Ri='Riyo:BAAALgAFFAIJAwAAAA==.',
Ro='Roachie:BAAALgAECgYJDgAAAA==.Rockandstone:BAAALgADCgEJAQAAAA==.Roesira:BAAALgAECgEJAQAAAA==.Rogun:BAAALgAECgkJAQAAAA==.Ros:BAAALgAECgMJBAAAAA==.',
Ru='Rug:BAAALgADCgYJBgAAAA==.Rustybray:BAABLgAECn81AAIOAAkJhgeFOgAwAQAOAAkJhgeFOgAwAQAAAA==.Ruu:BAAALgAECgkJBQABLgAFFAQJDgAnAAQRAA==.',
Ry='Ryvulz:BAABLgAECn8eAAIbAAgJHRWsGAAcAgAbAAgJHRWsGAAcAgAAAA==.',
Sa='Salomicum:BAAALgADCgEJAQAAAA==.Sappollo:BAAALgADCgMJAwAAAA==.Sarabi:BAABLgAECn8gAAIDAAYJtBeFLwCPAQADAAYJtBeFLwCPAQAAAA==.Sarena:BAAALgADCgMJAwAAAA==.Sarkoth:BAAALgADCgEJAQAAAA==.',
Sc='Schnee:BAAALgADCgYJCgAAAA==.Scrapster:BAAALgAECgUJCwAAAA==.',
Se='Seifer:BAAALgADCgEJAQAAAA==.Sekha:BAAALgAECgQJBgABLgAECggJIQAFAOoXAA==.Serbero:BAAALgAECgEJAQAAAA==.Seshiro:BAAALgAECgQJBAABLgAECgkJMgAMANkjAA==.',
Sh='Shadoweave:BAACLgAFFH8VAAMaAAUJjhTfDABWAQAaAAUJjhTfDABWAQAbAAIJ+wRkKwB4AAAuAAQKfxkAAhoACQkoGNIQAEcCABoACQkoGNIQAEcCAAEuAAUUCAknAAoA4xcA.Shalalia:BAABLgAECn8YAAIKAAcJNw4TZQBhAQAKAAcJNw4TZQBhAQAAAA==.Shambean:BAAALgADCgEJAQABLgAECgUJDwAHAAAAAA==.Shammywitch:BAAALgAECgQJBQABLgAECgMJCQAHAAAAAA==.Shentsu:BAABLgAECn8YAAIDAAkJ0CD7BQD/AgADAAkJ0CD7BQD/AgAAAA==.Shhanks:BAAALgAECgEJAQAAAA==.Shinmen:BAAALgADCgkJCQAAAA==.Shinsha:BAAALgADCgIJAwAAAA==.Shnizelnazee:BAABLgAECn8WAAINAAgJDww7pAAVAQANAAgJDww7pAAVAQAAAA==.Shortonheals:BAAALgAECgMJAwAAAA==.',
Si='Siege:BAAALgAECgUJBQAAAA==.Silie:BAAALgADCgEJAQAAAA==.Silik:BAAALgADCgcJBwAAAA==.Simpforsale:BAAALgAECgYJCQAAAA==.',
Sk='Skybladee:BAAALgADCgcJDgAAAA==.',
Sm='Smokeyb:BAACLgAFFH8GAAINAAIJkQqEgACHAAANAAIJkQqEgACHAAAuAAQKfysAAg0ACAlrFgdNAMcBAA0ACAlrFgdNAMcBAAAA.',
Sn='Sneevie:BAAALgAECggJCgAAAA==.Snorehees:BAABLgAECn8oAAMKAAkJwQ9AQgDDAQAKAAkJwQ9AQgDDAQAkAAQJMwJ2MABHAAAAAA==.',
So='Songarrow:BAAALgAECgYJBgAAAA==.Songstar:BAABLgAECn8qAAIKAAkJaiNtDADcAgAKAAkJaiNtDADcAgAAAA==.Soullraven:BAAALgADCgkJMAAAAA==.',
Sp='Spy:BAAALgAECgEJBQAAAA==.',
Sq='Squingledorf:BAAALgAECgMJAwAAAA==.',
St='Staavon:BAABLgAECn8iAAIYAAgJBQiYkwA2AQAYAAgJBQiYkwA2AQAAAA==.Stacy:BAAALgAECgEJAQABLgAECgQJCAAHAAAAAA==.Starblaze:BAAALgAECgYJCQAAAA==.Starseek:BAABLgAECn8VAAImAAcJLhDLEABDAQAmAAcJLhDLEABDAQAAAA==.Steelboats:BAAALgADCgkJGQAAAA==.',
Su='Sugarbow:BAAALgADCgMJAwAAAA==.Sugarlick:BAABLgAECn8jAAIUAAgJPRtfFACzAQAUAAgJPRtfFACzAQAAAA==.Sugarpop:BAACLgAFFH8GAAIVAAMJNw1wLQCtAAAVAAMJNw1wLQCtAAAuAAQKfygAAhUACQnXHIISAH4CABUACQnXHIISAH4CAAEuAAUUBAkGAA8AOBUA.Sunraku:BAAALgAECgIJAwAAAA==.Suplazindh:BAAALgAFFAIJAgABLgAFFAkJNAAZAOceAA==.',
Sw='Swethort:BAAALgADCgcJBgAAAA==.',
Sy='Synman:BAAALgADCgYJBgAAAA==.Syntheria:BAAALgADCgcJCQAAAA==.Syrebriel:BAABLgAECn8VAAIlAAcJCxEBJABzAQAlAAcJCxEBJABzAQAAAA==.',
['Sí']='Sílíbrítí:BAAALgAECgYJDQABLgAECggJGgADAPsWAA==.',
Ta='Taediah:BAAALgAECgcJDQAAAA==.Tamius:BAAALgADCgEJAQAAAA==.Tanthanalas:BAAALgAECgEJAQAAAA==.',
Th='Thefalsehope:BAAALgADCgcJBwAAAA==.Theoutcast:BAAALgAECgQJCAAAAA==.Thesarius:BAABLgAECn8ZAAIhAAgJXxmXDQAxAgAhAAgJXxmXDQAxAgAAAA==.Thortor:BAAALgADCgIJAgABLgADCggJEAAHAAAAAA==.',
Ti='Tiestto:BAAALgAECgcJDgAAAA==.Tinkermid:BAAALgADCgEJAQAAAA==.Tinymeatgang:BAAALgADCggJCQAAAA==.',
To='Tobalwl:BAAALgADCgUJBQAAAA==.Tockley:BAABLgAECn8hAAIYAAgJQwZV4QAyAQAYAAgJQwZV4QAyAQAAAA==.Toetagger:BAABLgAECn8WAAIZAAcJUA0yngBEAQAZAAcJUA0yngBEAQAAAA==.Tofino:BAAALgAECgYJCgAAAA==.Tohner:BAAALgADCgMJAwAAAA==.Tolidron:BAAALgADCgEJAQAAAA==.Tonimâster:BAAALgAFFAEJAQAAAA==.Tonydmaster:BAAALgAECgEJAQAAAA==.Toyotama:BAAALgAECgUJDQAAAA==.',
Tr='Trashiepanda:BAAALgAECgUJCQAAAA==.Trenbologna:BAAALgAECgEJAQAAAA==.Tristah:BAAALgAECgUJDwABLgAECgcJDwAHAAAAAA==.Trzlawd:BAAALgADCgEJAQAAAA==.',
Ty='Tyindron:BAAALgAECgYJBwAAAA==.Tyrrial:BAABLgAECn8nAAINAAgJbRf2TQDFAQANAAgJbRf2TQDFAQAAAA==.Tyshus:BAAALgAECgYJDAAAAA==.',
Ud='Udntknwme:BAAALgAFFAIJAwAAAA==.',
Un='Unbral:BAAALgADCgEJAQAAAA==.Unicood:BAAALgADCgYJBgAAAA==.Unlockbot:BAAALgADCgEJAwABLgAECgcJDwAHAAAAAA==.Unwholey:BAAALgAECggJCAAAAA==.',
Ut='Uthgardt:BAAALgAECgYJBgABLgAECgYJCwAHAAAAAA==.',
Va='Valarion:BAABLgAECn8lAAIjAAcJZhPWGwBjAQAjAAcJZhPWGwBjAQAAAA==.Valcaryn:BAAALgADCgYJBgAAAA==.Validimus:BAABLgAECn8aAAMNAAgJnQe6pAAVAQANAAgJ8Aa6pAAVAQAMAAIJ+QU5RQA6AAAAAA==.Valinis:BAAALgAECgQJBAAAAA==.Valinius:BAAALgADCgYJCQAAAA==.Valorían:BAABLgAECn83AAQCAAkJsSNWCQC5AgACAAkJ+iFWCQC5AgAhAAUJ9yNPDQD/AQAjAAIJAiD3OwC6AAAAAA==.Valtaa:BAAALgADCgUJBgAAAA==.Vanza:BAAALgADCgEJAQAAAA==.Varthayn:BAABLgAECn9DAAIYAAkJ4iBkFgC9AgAYAAkJ4iBkFgC9AgAAAA==.',
Ve='Vecna:BAAALgAECgMJAwABLgAECgYJCAAHAAAAAA==.Velandriel:BAAALgADCgkJCwABLgAECgkJOQAIANQYAA==.Vengfuhl:BAAALgAECgQJAwAAAA==.Verra:BAAALgAECgEJAQAAAA==.Vet:BAAALgAECgEJAQAAAA==.',
Vo='Voidwa:BAAALgAECgYJDgAAAA==.Volbain:BAABLgAECn8qAAQIAAcJLhzUEwDSAQAIAAcJLhzUEwDSAQAmAAMJ5BEyHACgAAAdAAEJ0wKDGQEcAAAAAA==.Volklin:BAABLgAECn8pAAMnAAkJqhQBHwCWAQAnAAkJow4BHwCWAQAKAAcJaRTeTQB/AQAAAA==.Voltagex:BAABLgAECn8dAAIdAAcJfRxITgCDAQAdAAcJfRxITgCDAQAAAA==.',
Vu='Vulpsinculta:BAABLgAECn8hAAIcAAYJnxcibQBWAQAcAAYJnxcibQBWAQAAAA==.',
['Vï']='Vïrùs:BAABLgAECn8jAAIFAAcJeg1aPABDAQAFAAcJeg1aPABDAQAAAA==.',
Wa='Wanda:BAAALgAECgYJBgAAAA==.',
Wi='Wichita:BAABLgAECn80AAMZAAkJsA8JWACqAQAZAAgJEhEJWACqAQAUAAEJBQaaWgAgAAAAAA==.Wildkitty:BAAALgAFFAEJAQAAAA==.',
Wo='Wolfyze:BAAALgADCgEJAQAAAA==.',
Wr='Wrâth:BAAALgAECgEJAQAAAA==.',
Wt='Wtfartemis:BAAALgAECgQJBAAAAA==.Wtfguën:BAABLgAECn8mAAISAAYJzgxIMQC9AAASAAYJzgxIMQC9AAAAAA==.Wtftäzmikell:BAAALgADCgYJCQABLgAECgYJJgASAM4MAA==.',
Wu='Wutäng:BAAALgADCgYJCgAAAA==.',
Xe='Xera:BAAALgADCgYJBgAAAA==.',
Xo='Xondra:BAAALgAECgYJDQAAAA==.',
Xr='Xravo:BAAALgADCgkJCQAAAA==.',
Xz='Xzairi:BAABLgAECn8hAAIFAAgJ6hf9IACmAQAFAAgJ6hf9IACmAQAAAA==.',
Ya='Yarria:BAAALgADCgIJAgAAAA==.',
Yi='Yinh:BAAALgADCgcJDAAAAA==.',
Yo='Yoiki:BAAALgAECgEJAQABLgAECgEJAQAHAAAAAA==.',
Yu='Yuck:BAAALgAECgIJBAAAAA==.',
Yy='Yy:BAAALgAECgUJDAAAAA==.',
Ze='Zeuzco:BAAALgAECgkJEQAAAA==.',
Zo='Zorell:BAAALgAECgYJDAAAAA==.Zovaal:BAAALgADCgYJBgAAAA==.',
['Ál']='Áltá:BAABLgAECn8tAAMcAAkJ5RghIwBHAgAcAAkJ5RghIwBHAgAgAAIJNwwaLQBWAAAAAA==.',
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
