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

local lookup = {'Rogue-Outlaw','Warrior-Fury','Monk-Mistweaver','Monk-Windwalker','Druid-Balance','Unknown-Unknown','Shaman-Enhancement','Evoker-Preservation','Evoker-Devastation','Hunter-BeastMastery','Shaman-Elemental','Shaman-Restoration','DeathKnight-Frost','Monk-Brewmaster','DeathKnight-Blood','Paladin-Holy','Paladin-Retribution','Druid-Feral','Mage-Frost','DeathKnight-Unholy','Priest-Holy','Priest-Shadow','DemonHunter-Devourer','Rogue-Subtlety','Druid-Restoration','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Warrior-Protection','Evoker-Augmentation','Paladin-Protection','Mage-Arcane','Hunter-Marksmanship','Druid-Guardian','DemonHunter-Vengeance','Hunter-Survival','Priest-Discipline','Warrior-Arms','DemonHunter-Havoc',}
local provider = {region='US',realm='Misha',name='US',type='weekly',zone=46,date='2026-05-16',data={Ac='Acidburn:BAABLgAECn8WAAIBAAcJ0BroAwDvAQABAAcJ0BroAwDvAQAAAA==.',
Ae='Aea:BAAALgAECgEJAQAAAA==.Aevie:BAAALgAECgQJAwAAAA==.',
Af='Afterlìfe:BAAALgAECgUJCwAAAA==.',
Ai='Ailis:BAAALgADCgQJBAAAAA==.',
Al='Alendria:BAAALgADCgYJBgAAAA==.Alizë:BAAALgADCgQJAwAAAA==.Alorillan:BAAALgAECgUJCwAAAA==.Altair:BAAALgAECgUJCwABLgAECgkJIAACABMhAA==.',
An='Andelynn:BAAALgAECgIJAgAAAA==.',
Ap='Applejuic:BAABLgAECn8UAAMDAAkJShYsEAA6AgADAAkJShYsEAA6AgAEAAEJNRBNcQAxAAAAAA==.Appless:BAAALgAECgQJBwAAAA==.',
Ar='Araylia:BAABLgAECn8fAAIFAAkJjAwWJwA5AQAFAAkJjAwWJwA5AQAAAA==.Aridella:BAAALgAECgYJDQAAAA==.Ariellaa:BAAALgAECgYJBgAAAA==.',
As='Ashaly:BAAALgADCgUJBQAAAA==.Ashlei:BAAALgAECgQJCAAAAA==.',
At='Atomseve:BAAALgADCgQJBAABLgAECggJEwAGAAAAAA==.',
Au='Aurafarmer:BAAALgADCgEJAQAAAA==.Autumn:BAAALgADCgUJBwAAAA==.',
Av='Avalorne:BAAALgAECgMJAwABLgAECgkJIAACABMhAA==.Avena:BAAALgADCgEJAgAAAA==.',
Az='Azaizel:BAAALgAECgUJCgABLgAECgYJBgAGAAAAAA==.Azusie:BAABLgAECn8sAAIHAAgJVhg4CADfAQAHAAgJVhg4CADfAQAAAA==.',
Ba='Baddate:BAAALgAECgcJDwAAAA==.Baddragøn:BAABLgAECn8zAAMIAAkJBRbHCQD+AQAIAAgJ0xXHCQD+AQAJAAcJBQwiCwAhAQAAAA==.Bangen:BAAALgAECgYJDgAAAA==.Bastria:BAAALgAECgYJDAAAAA==.Baulters:BAAALgADCgYJBgAAAA==.',
Be='Beenn:BAAALgAECgYJBgAAAA==.',
Bh='Bharko:BAAALgADCgcJCgABLgAFFAUJDQAKAKMeAA==.',
Bi='Billyblastin:BAAALgADCgMJAwABLgAECgkJIAALAJwYAA==.Billywitchdr:BAABLgAECn8gAAMLAAkJnBhMGADNAQALAAgJ0BhMGADNAQAMAAEJFgbtnAArAAAAAA==.Biocryo:BAAALgADCgYJBgABLgAECggJEAAGAAAAAA==.',
Bl='Blizeatsass:BAAALgADCgMJAwAAAA==.Bluedomino:BAAALgAECgMJCAAAAA==.Bluetoykawi:BAABLgAECn8qAAINAAgJyRODBQDiAQANAAgJyRODBQDiAQAAAA==.',
Bo='Boats:BAAALgADCgIJAgAAAA==.Boltspark:BAAALgADCgIJAgAAAA==.Borgo:BAAALgAECgYJBgAAAA==.Bowlenciaga:BAAALgAECgYJDwAAAA==.Bozilla:BAAALgADCgMJAwAAAA==.',
Br='Braelia:BAAALgADCgcJCAAAAA==.Brainfart:BAAALgADCgUJBQABLgAECggJGQAKABcWAA==.Breloom:BAAALgADCgEJAQAAAA==.',
Bu='Burdan:BAAALgADCgQJBAAAAA==.Buttermebuns:BAAALgADCgcJCAAAAA==.',
Ca='Cariandria:BAAALgAECgUJBQAAAA==.',
Ch='Chahaein:BAAALgAECgYJDwAAAA==.Charbaby:BAAALgAECgYJDgABLgAFFAQJDgAOABYfAA==.Charhartt:BAAALgAECgYJDAABLgAFFAQJDgAOABYfAA==.Charita:BAAALgAECgIJAgABLgAFFAQJDgAOABYfAA==.Charizard:BAAALgAECgEJAQABLgAFFAQJDgAOABYfAA==.Charming:BAACLgAFFH8OAAIOAAQJFh/ODABnAQAOAAQJFh/ODABnAQAuAAQKfyAAAg4ACAnXGcUcAB0CAA4ACAnXGcUcAB0CAAAA.Charmonic:BAAALgAECgIJAgABLgAFFAQJDgAOABYfAA==.Chelseah:BAAALgAECgYJEAABLgAECgYJDgAGAAAAAA==.',
Ci='Cinderlight:BAAALgAECgEJAQAAAA==.',
Cl='Clanker:BAAALgAECgkJEgAAAA==.',
Co='Coldknight:BAABLgAECn8bAAMNAAcJiQJjFwCOAAANAAcJWAJjFwCOAAAPAAUJnwFbOwBTAAAAAA==.Conien:BAAALgADCgQJBAAAAA==.Conifer:BAAALgAECgcJEAAAAA==.Coniption:BAAALgADCgEJAQAAAA==.Contrlurself:BAAALgADCgkJCQABLgAECgkJJAAFAF4VAA==.Copium:BAAALgAECgQJBAAAAA==.Cornpop:BAAALgAECgIJAgAAAA==.Cowret:BAABLgAECn8xAAMQAAkJmR7+AwAkAwAQAAkJmR7+AwAkAwARAAEJAACmXQEAAAAAAA==.',
Cr='Crystalwolf:BAABLgAECn8UAAISAAYJDAXIHQCyAAASAAYJDAXIHQCyAAAAAA==.',
Cu='Curze:BAAALgAECgMJAwAAAA==.',
Cy='Cyonna:BAAALgADCgQJBAAAAA==.',
Da='Darc:BAABLgAECn8UAAICAAQJXCXUPgCpAQACAAQJXCXUPgCpAQAAAA==.Darkfoxgrime:BAAALgADCgkJCQABLgAECgkJJAAEAHgQAA==.Darkjager:BAABLgAECn8rAAIKAAkJHR6BGABHAgAKAAkJHR6BGABHAgAAAA==.Darkways:BAAALgADCgMJAwAAAA==.Darlah:BAAALgAECgcJDQAAAA==.Dayva:BAAALgAECgQJBgAAAA==.Dayyva:BAAALgAECgQJDgAAAA==.',
De='Deadcobra:BAABLgAECn8YAAITAAkJCQSfjgAgAQATAAkJCQSfjgAgAQAAAA==.Deathbean:BAAALgADCgQJBAABLgAECgUJDwAGAAAAAA==.Debtknight:BAABLgAECn8vAAIUAAgJER8zIABEAgAUAAgJER8zIABEAgAAAA==.Deelo:BAAALgAECgEJAQAAAA==.Dehumidifier:BAABLgAECn8oAAMVAAkJlx6HCgBzAgAVAAkJlx6HCgBzAgAWAAkJRA3YGQCjAQAAAA==.Deltria:BAAALgAECgUJCwAAAA==.Demondad:BAAALgADCgQJBAAAAA==.Demonrot:BAAALgAECgYJEAAAAA==.Dervin:BAAALgADCgQJBAABLgAECgYJFgAQANwgAA==.Deviltank:BAAALgADCgYJDAAAAA==.Devohsup:BAABLgAECn8dAAIXAAgJkx8kFABgAgAXAAgJkx8kFABgAgAAAA==.Devussi:BAABLgAECn8mAAIXAAkJyBRDMwCuAQAXAAkJyBRDMwCuAQABLgADCgkJCQAGAAAAAA==.',
Di='Dienva:BAAALgAECgUJBQAAAA==.Digmyearth:BAAALgADCgcJBwAAAA==.Dilea:BAAALgAECgUJBQAAAA==.',
Dk='Dksakp:BAAALgADCgkJDQAAAA==.',
Do='Dominateelf:BAAALgADCgQJBAAAAA==.Dotero:BAAALgAECgQJBgAAAA==.',
Dr='Dracreina:BAABLgAECn8eAAMJAAYJJhWmCQBBAQAJAAYJJhWmCQBBAQAIAAEJQQZsMgAmAAAAAA==.Dreouss:BAAALgAECgQJBgAAAA==.',
Du='Dumeslayer:BAAALgADCgcJCQAAAA==.Durzoe:BAABLgAECn8UAAIYAAYJlwsFOQBNAQAYAAYJlwsFOQBNAQAAAA==.',
Dv='Dvsmage:BAAALgAECgUJDwAAAA==.',
Eg='Egaik:BAAALgAECgMJAwAAAA==.',
El='Elarred:BAAALgADCgkJFAAAAA==.Elissauna:BAAALgAECgIJBQAAAA==.Elylea:BAABLgAECn8eAAICAAgJ8RjGFwDjAQACAAgJ8RjGFwDjAQAAAA==.',
En='Enorme:BAAALgADCgQJBAAAAA==.',
Ez='Ezili:BAAALgAECgEJAQAAAA==.',
Fa='Failure:BAAALgAECgIJAwAAAA==.Falabala:BAAALgADCgcJFQAAAA==.Fanghür:BAAALgADCgcJDgAAAA==.',
Fe='Feeloow:BAAALgADCgcJCwAAAA==.Felhound:BAAALgAECgQJCgAAAA==.Felussi:BAAALgADCgkJCQAAAA==.Feorahir:BAAALgAECgQJBAAAAA==.Fermitorok:BAAALgADCgEJAQAAAA==.',
Ff='Ff:BAAALgAECgQJBAAAAA==.',
Fi='Finhead:BAABLgAECn8qAAIKAAgJ3Q4VQwCAAQAKAAgJ3Q4VQwCAAQAAAA==.Fionna:BAAALgAECgUJBQAAAA==.Firereina:BAAALgADCgcJFQABLgAECgYJHgAJACYVAA==.',
Fl='Fleurminator:BAABLgAECn8gAAICAAkJBxFsIACeAQACAAkJBxFsIACeAQAAAA==.Fluffybaby:BAAALgADCgMJAwAAAA==.',
Fo='Fondadix:BAABLgAECn8gAAIPAAkJpyH7BAChAgAPAAkJpyH7BAChAgAAAA==.',
Fr='Frieia:BAABLgAECn8ZAAIZAAYJfAklXADdAAAZAAYJfAklXADdAAAAAA==.Frostiilocks:BAAALgAECggJCQAAAA==.Frostitutte:BAAALgAECgYJEQAAAA==.',
Fu='Fuze:BAAALgADCgkJCQAAAA==.',
Ga='Galakrosh:BAACLgAFFH8HAAMaAAMJASEsBQCzAAAbAAMJASHURgD1AAAaAAIJ9B8sBQCzAAAuAAQKfyoABBoACAkXJE8CAFQCABsACAlwHT4XAMkCABoACAlpIk8CAFQCABwAAQkAAIFjAEgAAAAA.Galarína:BAABLgAECn8sAAMEAAkJ6h0LBwCVAgAEAAkJ6h0LBwCVAgADAAgJviCbEAA1AgAAAA==.Gandora:BAABLgAECn8gAAMUAAkJvBbUMwDpAQAUAAkJvBbUMwDpAQANAAEJ/wOGJAApAAAAAA==.Gardrius:BAAALgADCgEJAQAAAA==.',
Ge='Gene:BAAALgADCgcJBwAAAA==.Gentonord:BAABLgAECn8cAAMCAAgJIBogLgBJAQACAAgJABcgLgBJAQAdAAYJXBdrIAA9AQAAAA==.',
Gi='Gingerports:BAAALgADCgEJAQAAAA==.',
Gl='Glomps:BAAALgAECgUJCQABLgAFFAUJBQAeAFkEAA==.',
Go='Gonaldduck:BAAALgADCgMJAwAAAA==.',
Gr='Greasemunkey:BAABLgAECn8aAAISAAYJtxAvFQBiAQASAAYJtxAvFQBiAQAAAA==.Greentea:BAAALgADCggJCwAAAA==.Griiv:BAABLgAECn8jAAIRAAgJzSEhFgDkAgARAAgJzSEhFgDkAgAAAA==.Grislytotem:BAAALgADCgYJCAAAAQ==.',
Ha='Hakunamatata:BAAALgAECgIJAwAAAA==.Hamburger:BAABLgAECn8ZAAIWAAcJWxXhHQCAAQAWAAcJWxXhHQCAAQAAAA==.Hammerhard:BAAALgADCgQJBAAAAA==.Hampter:BAAALgAECgYJCQABLgAECgkJJQAWAMgaAA==.Haymáker:BAAALgADCgIJAgAAAA==.',
He='Heights:BAAALgAECgUJDgAAAA==.Heliosan:BAAALgAECgEJAQAAAA==.Heyu:BAAALgAECgMJAwABLgAECggJGQAKABcWAA==.',
Hi='Himoe:BAAALgADCgYJBgAAAA==.',
Ho='Holybean:BAAALgADCgcJEwABLgAECgUJDwAGAAAAAA==.Holyhench:BAAALgAECgUJBQAAAA==.Honkeykong:BAAALgADCgIJAgAAAA==.Hoochix:BAAALgAECgQJCQAAAA==.',
Hr='Hrsho:BAAALgADCgQJBAAAAA==.Hrshoo:BAAALgADCgEJAQAAAA==.',
Hu='Humzashaind:BAAALgAECgYJDgAAAA==.Huntinrabits:BAAALgADCgIJAgAAAA==.Huntt:BAAALgADCgcJBwAAAA==.Huzzyy:BAAALgAECgIJAgABLgAECgkJHgAQAOMaAA==.',
Hy='Hyphira:BAAALgAECgQJCgABLgAECgUJDQAGAAAAAA==.',
In='Inferbloom:BAAALgAECggJCAABLgAFFAQJCwAGAAAAAA==.Infernum:BAAALgAFFAQJCwAAAQ==.Insomnia:BAAALgAECgUJBQAAAA==.',
Ir='Irayvia:BAAALgADCgIJAgAAAA==.',
Ja='Jackyvoker:BAABLgAECn8qAAMIAAkJeyIVAQB3AwAIAAkJeyIVAQB3AwAJAAMJqRmCJwDlAAAAAA==.Jaezzon:BAAALgADCgQJBwAAAA==.',
Je='Jeannaah:BAAALgAECgQJBAABLgAECgYJDgAGAAAAAA==.Jetaime:BAAALgADCgUJBQAAAA==.',
Jh='Jharia:BAAALgADCgMJAgAAAA==.',
Ji='Jinksey:BAAALgAECgcJDQABLgAECgcJEQAXAA8TAA==.',
Jo='Johndoom:BAAALgAECgYJDgAAAA==.Johnfist:BAAALgAECgEJBAAAAA==.Johngrippy:BAAALgAECgEJAwAAAA==.Johnrend:BAAALgAECgEJAQAAAA==.',
Ju='Juicybottoms:BAAALgADCgMJAgAAAA==.',
Ka='Kalidormi:BAAALgAECgUJCQAAAA==.Kalzious:BAAALgADCgkJHAAAAA==.Kamikaze:BAAALgAECgcJBQAAAA==.Kayelalynn:BAABLgAECn8kAAMFAAkJXhWQEgDuAQAFAAkJXhWQEgDuAQAZAAMJNgEowgBDAAAAAA==.',
Kd='Kd:BAAALgADCgMJAwAAAA==.',
Ke='Keiri:BAAALgADCgYJBgAAAA==.Kelana:BAABLgAECn8lAAIOAAkJwh82BQC4AgAOAAkJwh82BQC4AgAAAA==.Kendô:BAAALgADCgYJBgAAAA==.Ketdealer:BAAALgAECgcJBwAAAA==.Ketzendk:BAAALgAECgYJBQAAAA==.Keyahi:BAACLgAFFH8LAAIXAAQJkBmeHQBSAQAXAAQJkBmeHQBSAQAuAAQKfx0AAhcACQklHEYWAFECABcACQklHEYWAFECAAEuAAQKAQkBAAYAAAAA.',
Kh='Khety:BAAALgAECgQJBAAAAA==.',
Ki='Kickandpunch:BAAALgAECgYJDgAAAA==.Kicsi:BAAALgAECgIJAwAAAA==.Kilan:BAABLgAECn8XAAMRAAYJFhNqnQDvAAARAAUJ1xJqnQDvAAAfAAEJEhTUNwA7AAAAAA==.Killinrage:BAAALgAECgYJDgAAAA==.Kissofpaine:BAAALgADCgIJAgAAAA==.Kitsuney:BAAALgADCgMJAwAAAA==.Kizaru:BAAALgAECgcJCAAAAA==.',
Ko='Korz:BAAALgADCgcJBwABLgAECgcJFQATAOEXAA==.',
Kp='Kpop:BAAALgAECgEJAQAAAA==.',
Kr='Krynj:BAAALgAFFAEJAwAAAA==.',
Ku='Kumokiri:BAAALgAECgIJAgAAAA==.Kurzzon:BAAALgADCgMJAwAAAA==.',
Ky='Kyleata:BAABLgAECn8pAAIKAAgJAR49GwA0AgAKAAgJAR49GwA0AgAAAA==.Kyleigh:BAAALgAECgQJBQABLgAECgYJDgAGAAAAAA==.Kyokin:BAABLgAECn8fAAMRAAgJTQuJjQALAQARAAYJaQ+JjQALAQAfAAcJbwIkNAB4AAAAAA==.Kyzula:BAAALgAECgYJEwAAAA==.',
La='Lace:BAAALgADCgMJAwAAAA==.Laytone:BAAALgADCgYJBwAAAA==.',
Le='Legcurl:BAAALgAECgEJAwAAAA==.Lepotko:BAAALgAECgQJBAAAAA==.',
Li='Lightbear:BAAALgADCgMJBQAAAA==.Lilylocks:BAAALgAECgYJCAAAAA==.Lilyrocks:BAAALgAECgUJCQAAAA==.Literallad:BAAALgADCgcJBgAAAA==.Littlelo:BAAALgAECgUJBgAAAA==.',
Lo='Lockology:BAAALgAECgIJBAAAAA==.Lokarg:BAAALgADCgIJAgAAAA==.Loudcry:BAABLgAECn8oAAMgAAkJIBy0AQCpAgAgAAgJXR60AQCpAgATAAMJtBCaxQC/AAABLgAFFAUJCgACACIYAA==.',
Lu='Lunaeria:BAAALgADCggJCAAAAA==.',
Ly='Lyanah:BAACLgAFFH8QAAIZAAQJUQcfJQDpAAAZAAQJUQcfJQDpAAAuAAQKfyYAAhkACQl0FHswAOkBABkACQl0FHswAOkBAAAA.Lyniah:BAAALgAECgQJBQAAAA==.',
Ma='Machete:BAAALgAECgQJAwAAAA==.Maelius:BAABLgAECn8pAAIQAAkJ3xjpIgAIAgAQAAkJ3xjpIgAIAgAAAA==.Maggrus:BAABLgAECn8ZAAIKAAgJFxZqMwC8AQAKAAgJFxZqMwC8AQAAAA==.Malavel:BAAALgADCggJCAAAAA==.Malically:BAABLgAECn8aAAIhAAgJghH5DABFAQAhAAgJghH5DABFAQAAAA==.Manshoon:BAAALgADCgcJCwAAAA==.Marlory:BAAALgADCgUJBQAAAA==.Math:BAAALgAECggJCAABLgAFFAQJBQAeAEQKAA==.Matheney:BAABLgAFFH8OAAIiAAYJuw/NAgCBAQAiAAYJuw/NAgCBAQABLgAFFAQJBQAeAEQKAA==.Maxnem:BAAALgADCggJCAABLgAECggJHwAFADMPAA==.',
Mc='Mcrib:BAAALgADCggJBQAAAA==.Mctubby:BAAALgADCgEJAQABLgADCgUJBgAGAAAAAA==.Mctubmonk:BAAALgADCgUJBgAAAA==.',
Me='Meatpopsicle:BAAALgADCgEJAQAAAA==.Meigz:BAAALgAECgQJCAAAAA==.Melidin:BAAALgAECggJEAAAAA==.Melinda:BAAALgAFFAEJAQAAAA==.Melindorei:BAAALgAECgEJAgAAAA==.Melledrus:BAAALgAECgEJAQAAAA==.Mememo:BAAALgAECgMJAwAAAA==.Menöpaws:BAEALgAFFAMJAwAAAA==.Merithrá:BAAALgAECgMJAwAAAA==.',
Mi='Mikaeljayfox:BAAALgAECgcJDwAAAQ==.Mikros:BAAALgAECgMJAwAAAA==.Milenzha:BAABLgAECn8cAAIKAAcJRhWqPwCNAQAKAAcJRhWqPwCNAQAAAA==.Milkymaiden:BAAALgADCgMJAwAAAA==.Mimachote:BAAALgAECgEJAQAAAA==.',
Mo='Monetta:BAAALgADCgIJAgAAAA==.Monk:BAAALgAECggJEAAAAA==.Moonblood:BAAALgADCggJEAAAAA==.Moonfighter:BAAALgAECgEJAgAAAA==.Moontann:BAAALgADCggJCAAAAA==.Morcombe:BAAALgAECgEJAQAAAA==.Moreia:BAAALgADCgcJBwAAAA==.Motown:BAAALgAECgYJCwAAAA==.Mousse:BAAALgAECgYJDwAAAA==.',
Mu='Murdalok:BAABLgAECn8ZAAIZAAgJshWdNQDSAQAZAAgJshWdNQDSAQAAAA==.',
My='Mysharona:BAAALgAECgEJAQAAAA==.Mystahmurdah:BAAALgADCgQJBwABLgAECgYJDQAGAAAAAA==.Mysterioñ:BAAALgAECgQJDQAAAA==.',
['Má']='Mákla:BAAALgAECgMJAwAAAA==.',
['Mâ']='Mâstermînd:BAAALgAECgUJDgAAAA==.',
Na='Nahte:BAAALgADCgMJAwABLgADCgMJAwAGAAAAAA==.Nasine:BAAALgAECgYJCAABLgAECggJFwALAJAeAA==.Natstryker:BAABLgAECn8uAAQOAAkJoyQvAQBDAwAOAAkJoyQvAQBDAwAEAAYJiiJMFQBCAgADAAcJMRF2KABaAQAAAA==.Naturemyth:BAAALgAFFAEJAwAAAA==.Nazu:BAAALgADCgUJCgAAAA==.',
Ne='Neeró:BAABLgAECn8gAAIXAAYJphUVWAAtAQAXAAYJphUVWAAtAQAAAA==.Nelthon:BAAALgADCgYJBgAAAA==.',
Ni='Nishastraza:BAAALgAECgEJAwABLgAECgYJDgAGAAAAAA==.',
No='Nonaha:BAAALgADCgkJEQAAAA==.Notsoda:BAAALgAECgQJCQAAAA==.',
Oa='Oaf:BAAALgAECgYJBgAAAA==.',
Oo='Oolong:BAAALgAECgQJBAAAAA==.',
Or='Organa:BAABLgAECn8YAAICAAYJ/ArAPgD4AAACAAYJ/ArAPgD4AAAAAA==.',
Ou='Outofthedark:BAAALgAECgIJAgAAAA==.',
Pa='Pakkan:BAAALgAECgEJAQAAAA==.Pallyqb:BAAALgADCgEJAQAAAA==.Pauladeenx:BAAALgAECgIJAwABLgAECgUJDgAGAAAAAA==.',
Pe='Petal:BAAALgAECgYJBwABLgAECggJEAAGAAAAAA==.',
Pl='Playwitwe:BAAALgAECgMJAwAAAA==.Plowmcballs:BAABLgAECn8ZAAIRAAYJtxIzfgB+AQARAAYJtxIzfgB+AQAAAA==.Plugley:BAABLgAECn8ZAAMTAAgJBRquOgDtAQATAAgJBRquOgDtAQAgAAEJARSGHAA6AAAAAA==.',
Po='Polaris:BAAALgAECgEJAQAAAA==.Poober:BAABLgAECn8aAAIVAAgJeCHbBgDCAgAVAAgJeCHbBgDCAgAAAA==.Potooòooóoo:BAABLgAECn8dAAINAAcJVhhbCwBCAQANAAcJVhhbCwBCAQAAAA==.',
Pr='Pren:BAAALgAFFAEJAQAAAA==.Privet:BAAALgAECgEJAgAAAA==.',
Pu='Purebeef:BAAALgAECgIJAgAAAA==.',
Py='Pygos:BAABLgAECn8ZAAIjAAgJ5BiJBwANAgAjAAgJ5BiJBwANAgAAAA==.',
['Pë']='Përdü:BAAALgAECgUJCwAAAA==.',
Qu='Quigglay:BAAALgAECgYJBgAAAA==.',
Ra='Raegnarok:BAAALgAECgYJCwAAAA==.Raelessa:BAAALgAECgQJCQABLgAECgYJDgAGAAAAAA==.Raigeki:BAAALgADCgQJBQAAAA==.Ralf:BAAALgAECgEJAQAAAA==.Ralphie:BAAALgAECgIJAgAAAA==.Ratapew:BAAALgAECgUJDAAAAA==.Ratheen:BAABLgAECn8dAAIRAAgJtA7AaQBQAQARAAgJtA7AaQBQAQAAAA==.Raytar:BAABLgAECn8fAAMFAAkJ2B6qCQBvAgAFAAgJ2B+qCQBvAgAZAAMJ9BsBmwCWAAAAAA==.',
Re='Rekkirin:BAAALgAECgUJBQABLgAECgkJMwAIAAUWAA==.Relyk:BAAALgADCgUJBQAAAA==.',
Ri='Riyo:BAAALgADCgMJAQABLgAECgcJGQAOAHgXAA==.',
Ro='Roachie:BAAALgAECgYJDgAAAA==.Rockandstone:BAAALgADCgEJAQAAAA==.Roesira:BAAALgAECgEJAQAAAA==.Rogun:BAAALgAECgkJAQAAAA==.Ros:BAAALgAECgMJBAAAAA==.',
Ru='Rug:BAAALgADCgYJBgAAAA==.Rustybray:BAABLgAECn8wAAILAAkJBAdWMAAkAQALAAkJBAdWMAAkAQAAAA==.Ruu:BAAALgAECgkJBQABLgAFFAQJDgAkAAQRAA==.',
Ry='Ryvulz:BAABLgAECn8eAAIWAAgJHRWsGAAcAgAWAAgJHRWsGAAcAgAAAA==.',
Sa='Salomicum:BAAALgADCgEJAQAAAA==.Sappollo:BAAALgADCgMJAwAAAA==.Sarabi:BAABLgAECn8ZAAIDAAYJtBfEIQCMAQADAAYJtBfEIQCMAQAAAA==.Sarena:BAAALgADCgMJAwAAAA==.Sarkoth:BAAALgADCgEJAQAAAA==.',
Sc='Schnee:BAAALgADCgYJCgAAAA==.Scrapster:BAAALgAECgUJCgAAAA==.',
Se='Seifer:BAAALgADCgEJAQAAAA==.Sekha:BAAALgAECgQJBgABLgAECgcJHgAFAGYWAA==.Seshiro:BAAALgAECgQJBAABLgAECgkJLAAfAHkjAA==.',
Sh='Shadoweave:BAACLgAFFH8NAAMVAAQJoxTXDAAhAQAVAAQJoxTXDAAhAQAWAAIJ+wRgIQCDAAAuAAQKfxgAAhUACQmkFuENAD4CABUACQmkFuENAD4CAAEuAAUUCAkiAAoA5hMA.Shalalia:BAAALgAECgUJCQAAAA==.Shambean:BAAALgADCgEJAQABLgAECgUJDwAGAAAAAA==.Shentsu:BAABLgAECn8YAAIDAAkJ0CD7BQD/AgADAAkJ0CD7BQD/AgAAAA==.Shhanks:BAAALgADCgUJBQAAAA==.Shinmen:BAAALgADCgkJCQAAAA==.Shinsha:BAAALgADCgIJAwAAAA==.Shnizelnazee:BAABLgAECn8WAAIRAAgJDwzLfAApAQARAAgJDwzLfAApAQAAAA==.',
Si='Siege:BAAALgAECgUJBQAAAA==.Silie:BAAALgADCgEJAQAAAA==.Silik:BAAALgADCgcJBwAAAA==.Simpforsale:BAAALgAECgYJCQAAAA==.',
Sk='Skybladee:BAAALgADCgcJDgAAAA==.',
Sm='Smokeyb:BAABLgAECn8hAAIRAAcJbxjmSACjAQARAAcJbxjmSACjAQAAAA==.',
Sn='Sneevie:BAAALgAECggJCgAAAA==.Snorehees:BAABLgAECn8kAAMKAAgJmA1gNwDRAQAKAAgJmA1gNwDRAQAhAAQJMwK4KABIAAAAAA==.',
So='Songarrow:BAAALgADCgkJCQAAAA==.Songstar:BAABLgAECn8nAAIKAAkJYyMNBgD9AgAKAAkJYyMNBgD9AgAAAA==.Soullraven:BAAALgADCgkJLgAAAA==.',
Sp='Spy:BAAALgAECgEJBQAAAA==.',
Sq='Squingledorf:BAAALgAECgMJAwAAAA==.',
St='Staavon:BAABLgAECn8aAAITAAcJqwfbkAAcAQATAAcJqwfbkAAcAQAAAA==.Stacy:BAAALgAECgEJAQABLgAECgQJCAAGAAAAAA==.Starblaze:BAAALgAECgYJCAAAAA==.Starseek:BAABLgAECn8UAAIjAAcJLhDLEABDAQAjAAcJLhDLEABDAQAAAA==.Steelboats:BAAALgADCgkJGQAAAA==.',
Su='Sugarbow:BAAALgADCgMJAwAAAA==.Sugarlick:BAABLgAECn8bAAIPAAYJ2B1kEQD1AQAPAAYJ2B1kEQD1AQAAAA==.Sugarpop:BAACLgAFFH8GAAIQAAMJNw0aIgDDAAAQAAMJNw0aIgDDAAAuAAQKfygAAhAACQnXHIISAH4CABAACQnXHIISAH4CAAAA.Sunraku:BAAALgAECgIJAwAAAA==.Suplazindh:BAAALgAFFAIJAgABLgAFFAkJLAAUALEdAA==.',
Sw='Swethort:BAAALgADCgcJBgAAAA==.',
Sy='Synman:BAAALgADCgYJBgAAAA==.Syntheria:BAAALgADCgcJCQAAAA==.Syrebriel:BAABLgAECn8VAAIlAAcJCxEBJABzAQAlAAcJCxEBJABzAQAAAA==.',
['Sí']='Sílíbrítí:BAAALgAECgYJDQABLgAECggJGgADAPwWAA==.',
Ta='Taediah:BAAALgAECgQJBgAAAA==.Tamius:BAAALgADCgEJAQAAAA==.Tanthanalas:BAAALgAECgEJAQAAAA==.',
Th='Thefalsehope:BAAALgADCgcJBwAAAA==.Theoutcast:BAAALgAECgEJAQAAAA==.Thesarius:BAABLgAECn8ZAAIdAAgJXxmXDQAxAgAdAAgJXxmXDQAxAgAAAA==.Thortor:BAAALgADCgIJAgABLgADCggJEAAGAAAAAA==.',
Ti='Tiestto:BAAALgAECgcJDgAAAA==.Tinkermid:BAAALgADCgEJAQAAAA==.',
To='Tobalwl:BAAALgADCgUJBQAAAA==.Tockley:BAABLgAECn8hAAITAAgJQwbwqwDsAAATAAgJQwbwqwDsAAAAAA==.Toetagger:BAABLgAECn8VAAIUAAYJaw4yngBEAQAUAAYJaw4yngBEAQAAAA==.Tofino:BAAALgAECgUJCAAAAA==.Tohner:BAAALgADCgMJAwAAAA==.Tolidron:BAAALgADCgEJAQAAAA==.Tonimâster:BAAALgAECgMJBgAAAA==.Toyotama:BAAALgAECgUJDQAAAA==.',
Tr='Trenbologna:BAAALgAECgEJAQAAAA==.Tristah:BAAALgAECgUJDwABLgAECgYJDgAGAAAAAA==.Trzlawd:BAAALgADCgEJAQAAAA==.',
Ty='Tyindron:BAAALgAECgYJBwAAAA==.Tyrrial:BAABLgAECn8dAAIRAAcJyBjiRgCpAQARAAcJyBjiRgCpAQAAAA==.Tyshus:BAAALgAECgYJDAAAAA==.',
Ud='Udntknwme:BAAALgAFFAIJAwAAAA==.',
Un='Unbral:BAAALgADCgEJAQAAAA==.Unicood:BAAALgADCgYJBgAAAA==.Unlockbot:BAAALgADCgEJAwABLgAECgcJDwAGAAAAAA==.',
Ut='Uthgardt:BAAALgAECgYJBgAAAA==.',
Va='Valarion:BAABLgAECn8fAAImAAcJ9BBfFgBNAQAmAAcJ9BBfFgBNAQAAAA==.Valcaryn:BAAALgADCgYJBgAAAA==.Validimus:BAAALgAECgcJCwAAAA==.Valinis:BAAALgAECgQJBAAAAA==.Valinius:BAAALgADCgYJCQAAAA==.Valorían:BAABLgAECn8uAAMCAAkJwiLiBADbAgACAAkJ+CHiBADbAgAdAAQJKRvMJgCyAAAAAA==.Valtaa:BAAALgADCgQJBQAAAA==.Vanza:BAAALgADCgEJAQAAAA==.Varthayn:BAABLgAECn8+AAITAAkJ1yAfDgDXAgATAAkJ1yAfDgDXAgAAAA==.',
Ve='Vecna:BAAALgAECgMJAwABLgAECgYJEAAGAAAAAA==.Velandriel:BAAALgADCgkJCwABLgAECggJNgAnAF8YAA==.Verra:BAAALgAECgEJAQAAAA==.',
Vo='Voidwa:BAAALgAECgYJCAAAAA==.Volbain:BAABLgAECn8fAAMnAAYJihumFgBqAQAnAAYJihumFgBqAQAXAAEJ0wLU7gAcAAAAAA==.Volklin:BAABLgAECn8bAAMKAAcJaRTeTQB/AQAKAAcJaRTeTQB/AQAkAAMJBAZkJwB+AAAAAA==.Voltagex:BAABLgAECn8dAAIXAAcJfRwGOwCOAQAXAAcJfRwGOwCOAQAAAA==.',
Vu='Vulpsinculta:BAABLgAECn8aAAIbAAYJuxJ/bwAfAQAbAAYJuxJ/bwAfAQAAAA==.',
['Vï']='Vïrùs:BAABLgAECn8jAAIFAAcJeg1aPABDAQAFAAcJeg1aPABDAQAAAA==.',
Wa='Wanda:BAAALgAECgYJBgAAAA==.',
Wi='Wichita:BAABLgAECn8vAAMUAAkJOw8kRgCpAQAUAAgJjBAkRgCpAQAPAAEJBQYsSQAiAAAAAA==.Wildkitty:BAAALgAECgYJCAAAAA==.',
Wo='Wolfyze:BAAALgADCgEJAQAAAA==.',
Wt='Wtfguën:BAABLgAECn8cAAIiAAYJdQxEIgC5AAAiAAYJdQxEIgC5AAAAAA==.Wtftäzmikell:BAAALgADCgYJCQABLgAECgYJHAAiAHUMAA==.',
Wu='Wutäng:BAAALgADCgYJCgAAAA==.',
Xe='Xera:BAAALgADCgYJBgAAAA==.',
Xo='Xondra:BAAALgADCgEJAQAAAA==.',
Xr='Xravo:BAAALgADCgkJCQAAAA==.',
Xz='Xzairi:BAABLgAECn8eAAIFAAcJZhZhJgDKAQAFAAcJZhZhJgDKAQAAAA==.',
Ya='Yarria:BAAALgADCgIJAgAAAA==.',
Yi='Yinh:BAAALgADCgcJDAAAAA==.',
Yu='Yuck:BAAALgAECgIJBAAAAA==.',
Yy='Yy:BAAALgAECgUJDAAAAA==.',
Ze='Zeuzco:BAAALgAECgkJDwAAAA==.',
Zo='Zorell:BAAALgADCgMJAwAAAA==.Zovaal:BAAALgADCgYJBgAAAA==.',
['Ál']='Áltá:BAABLgAECn8oAAMbAAkJhxioGQBQAgAbAAkJhxioGQBQAgAcAAIJNwz1IwBbAAAAAA==.',
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
