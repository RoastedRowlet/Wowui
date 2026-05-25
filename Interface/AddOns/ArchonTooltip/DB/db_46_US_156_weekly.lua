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

local lookup = {'Rogue-Outlaw','Warrior-Fury','Monk-Mistweaver','Monk-Windwalker','Druid-Balance','Evoker-Devastation','Unknown-Unknown','Shaman-Enhancement','Evoker-Preservation','Hunter-BeastMastery','Shaman-Elemental','Shaman-Restoration','DeathKnight-Frost','Monk-Brewmaster','DeathKnight-Blood','Druid-Restoration','Paladin-Holy','Paladin-Retribution','Druid-Feral','Mage-Frost','DeathKnight-Unholy','Priest-Holy','Priest-Shadow','DemonHunter-Devourer','Warlock-Demonology','Rogue-Subtlety','Warlock-Affliction','Warlock-Destruction','Warrior-Protection','Evoker-Augmentation','Paladin-Protection','Mage-Arcane','Hunter-Marksmanship','Druid-Guardian','DemonHunter-Vengeance','Hunter-Survival','Priest-Discipline','Warrior-Arms','DemonHunter-Havoc',}
local provider = {region='US',realm='Misha',name='US',type='weekly',zone=46,date='2026-05-23',data={Ac='Acidburn:BAABLgAECn8WAAIBAAcJ0BroAwDvAQABAAcJ0BroAwDvAQAAAA==.',
Ae='Aea:BAAALgAECgEJAwAAAA==.Aevie:BAAALgAECgYJCwAAAA==.',
Af='Afterlìfe:BAAALgAECgUJCwAAAA==.',
Ai='Ailis:BAAALgADCgQJBAAAAA==.',
Al='Alendria:BAAALgADCgYJBgAAAA==.Alizë:BAAALgADCgQJAwAAAA==.Alorillan:BAAALgAECgUJCwAAAA==.Altair:BAAALgAECgUJDwABLgAECgkJIQACABMhAA==.',
An='Andelynn:BAAALgAECgIJAgAAAA==.',
Ap='Applejuic:BAABLgAECn8UAAMDAAkJShbTFAA5AgADAAkJShbTFAA5AgAEAAEJNRCggwAvAAAAAA==.Appless:BAAALgAECgQJBwAAAA==.',
Ar='Araylia:BAABLgAECn8fAAIFAAkJjAz+LQA6AQAFAAkJjAz+LQA6AQAAAA==.Aridella:BAABLgAECn8VAAIGAAYJRA4QEQDWAAAGAAYJRA4QEQDWAAAAAA==.Ariellaa:BAAALgAECgYJBgAAAA==.',
As='Ashaly:BAAALgADCgUJBQAAAA==.Ashlei:BAAALgAECgQJCAAAAA==.',
At='Atomseve:BAAALgADCgQJBAABLgAECggJEwAHAAAAAA==.',
Au='Aurafarmer:BAAALgADCgEJAQAAAA==.Autumn:BAAALgADCgUJBwAAAA==.',
Av='Avalorne:BAAALgAECgMJAwABLgAECgkJIQACABMhAA==.Avena:BAAALgADCgEJAgAAAA==.',
Az='Azaizel:BAAALgAECgUJCgABLgAECgYJBgAHAAAAAA==.Azusie:BAABLgAECn80AAIIAAgJ+xgxCgDhAQAIAAgJ+xgxCgDhAQAAAA==.',
Ba='Baddate:BAAALgAECgcJEgAAAA==.Baddragøn:BAABLgAECn82AAMJAAkJBRanCwD5AQAJAAgJ0xWnCwD5AQAGAAgJxg+PBwChAQAAAA==.Bangen:BAAALgAECgYJDgAAAA==.Bastria:BAAALgAECgYJDAAAAA==.Baulters:BAAALgAECgQJBgAAAA==.',
Be='Beenn:BAAALgAECgYJBgAAAA==.',
Bh='Bharko:BAAALgADCgcJCgABLgAFFAYJDgAKADodAA==.',
Bi='Billyblastin:BAAALgADCgMJAwABLgAECgkJJQALAFgZAA==.Billywitchdr:BAABLgAECn8lAAMLAAkJWBkCFAAfAgALAAkJWBkCFAAfAgAMAAEJFgYrtQArAAAAAA==.Biocryo:BAAALgADCgYJBgABLgAECggJEAAHAAAAAA==.',
Bl='Blazingpanda:BAAALgAECgIJAwAAAA==.Blizeatsass:BAAALgADCgMJAwAAAA==.Bluedomino:BAAALgAECgMJCAAAAA==.Bluetoykawi:BAABLgAECn8yAAINAAgJKxbGCAC4AQANAAgJKxbGCAC4AQAAAA==.',
Bo='Boats:BAAALgADCgIJAgAAAA==.Boltspark:BAAALgADCgMJAwAAAA==.Borgo:BAAALgAECgYJBgAAAA==.Bowlenciaga:BAAALgAECgYJDwAAAA==.Bozilla:BAAALgADCgMJAwAAAA==.',
Br='Braelia:BAAALgADCgcJCAAAAA==.Brainfart:BAAALgADCgUJBQABLgAECggJGwAKABcWAA==.Breloom:BAAALgADCgEJAQAAAA==.Bruithis:BAAALgADCgIJAgAAAA==.',
Bu='Burdan:BAAALgADCgQJBAAAAA==.Buttermebuns:BAAALgADCgcJCAAAAA==.',
Ca='Cariandria:BAAALgAECgUJBgAAAA==.',
Cc='Cc:BAAALgAECgEJAgAAAA==.',
Ch='Chahaein:BAAALgAECgYJDwAAAA==.Charbaby:BAAALgAECgYJDgABLgAFFAUJEgAOABYfAA==.Charhartt:BAAALgAECgYJEAABLgAFFAUJEgAOABYfAA==.Charita:BAAALgAECgIJAgABLgAFFAUJEgAOABYfAA==.Charizard:BAAALgAECgEJAQABLgAFFAUJEgAOABYfAA==.Charming:BAACLgAFFH8SAAIOAAUJFh+cEQBcAQAOAAUJFh+cEQBcAQAuAAQKfyAAAg4ACAnXGcUcAB0CAA4ACAnXGcUcAB0CAAAA.Charmonic:BAAALgAECgQJBwABLgAFFAUJEgAOABYfAA==.Chelseah:BAAALgAECgYJEAABLgAECgYJDgAHAAAAAA==.',
Ci='Cinderlight:BAAALgAECgEJAQAAAA==.',
Cl='Clanker:BAAALgAECgkJEgAAAA==.',
Co='Coldknight:BAABLgAECn8bAAMNAAcJiQLJHgCEAAANAAcJWALJHgCEAAAPAAUJnwFKRABPAAAAAA==.Conien:BAAALgADCgQJBAAAAA==.Conifer:BAABLgAECn8WAAIQAAcJEhr0JAACAgAQAAcJEhr0JAACAgAAAA==.Coniption:BAAALgADCgEJAQAAAA==.Contrlurself:BAAALgAECgYJBgABLgAECgkJJAAFAF4VAA==.Copium:BAAALgAECgQJBwAAAA==.Cornpop:BAAALgAECgIJAgAAAA==.Cowret:BAABLgAECn85AAMRAAkJ0iCoAgBkAwARAAkJ0iCoAgBkAwASAAEJAAALjAEAAAAAAA==.',
Cr='Crystalwolf:BAABLgAECn8UAAITAAYJDAVkJACsAAATAAYJDAVkJACsAAAAAA==.',
Cu='Curze:BAAALgAECgMJAwAAAA==.',
Cy='Cyonna:BAAALgADCgQJBAAAAA==.',
Da='Darc:BAABLgAECn8VAAICAAQJXCXUPgCpAQACAAQJXCXUPgCpAQAAAA==.Darkfoxgrime:BAAALgAECgkJCQABLgAECgkJJAAEAHkQAA==.Darkjager:BAABLgAECn8rAAIKAAkJHR4iIgAyAgAKAAkJHR4iIgAyAgAAAA==.Darkways:BAAALgADCgMJAwAAAA==.Darlah:BAAALgAECgcJEAAAAA==.Darnalin:BAAALgAECgEJAgAAAA==.Dayva:BAAALgAECgQJBgAAAA==.Dayyva:BAAALgAECgQJDgAAAA==.',
De='Deadcobra:BAABLgAECn8YAAIUAAkJCQR6oAAgAQAUAAkJCQR6oAAgAQAAAA==.Deathbean:BAAALgADCgQJBAABLgAECgUJDwAHAAAAAA==.Debtknight:BAABLgAECn84AAIVAAkJ6h8VEADMAgAVAAkJ6h8VEADMAgAAAA==.Deelo:BAAALgAECgEJAQAAAA==.Dehumidifier:BAABLgAECn8oAAMWAAkJlx6GDQBmAgAWAAkJlx6GDQBmAgAXAAkJQw2lHgCoAQAAAA==.Deltria:BAAALgAECgUJCwAAAA==.Demonrot:BAAALgAECgcJEwAAAA==.Dervin:BAAALgADCgQJBAABLgAECgcJGAARAK4gAA==.Deviltank:BAAALgADCgYJDAAAAA==.Devohsup:BAABLgAECn8dAAIYAAgJlB/nGQBcAgAYAAgJlB/nGQBcAgAAAA==.Devussi:BAABLgAECn8mAAIYAAkJyBQIPAC2AQAYAAkJyBQIPAC2AQABLgAECgUJBQAHAAAAAA==.',
Di='Dienva:BAAALgAECgUJBQAAAA==.Digmyearth:BAAALgADCgcJBwAAAA==.Dilea:BAAALgAECgUJBQAAAA==.',
Dk='Dksakp:BAAALgADCgkJGAAAAA==.',
Do='Dominateelf:BAAALgADCgQJBAABLgAECgIJAwAHAAAAAA==.Dotero:BAAALgAECgQJBgAAAA==.',
Dr='Dracreina:BAABLgAECn8kAAMGAAYJTRabCgBQAQAGAAYJTRabCgBQAQAJAAEJQQbkNwAmAAAAAA==.Dreouss:BAAALgAECgQJBgAAAA==.Driver:BAEALgAFFAIJAgABLgAFFAQJCgAZANAMAA==.',
Du='Dumeslayer:BAAALgADCgcJCQAAAA==.Durzoe:BAABLgAECn8VAAIaAAYJlwsFOQBNAQAaAAYJlwsFOQBNAQAAAA==.',
Dv='Dvsmage:BAAALgAECgUJDwAAAA==.',
Eg='Egaik:BAAALgAECgUJAwAAAA==.',
El='Elarred:BAAALgADCgkJFAAAAA==.Elissauna:BAAALgAECgcJDAAAAA==.Elylea:BAABLgAECn8eAAICAAgJ8hgcHgDaAQACAAgJ8hgcHgDaAQAAAA==.',
En='Enorme:BAAALgADCgQJBAAAAA==.',
Ez='Ezili:BAAALgAECgEJAQAAAA==.',
Fa='Failure:BAAALgAECgIJAwAAAA==.Falabala:BAAALgADCgcJHAAAAA==.Fanghür:BAAALgADCgcJDgAAAA==.',
Fe='Feeloow:BAAALgADCgcJCwAAAA==.Felhound:BAAALgAECgQJCgAAAA==.Felussi:BAAALgAECgUJBQAAAA==.Feorahir:BAAALgAECgQJBAAAAA==.Fermitorok:BAAALgADCgEJAQAAAA==.',
Ff='Ff:BAAALgAECgQJBAAAAA==.',
Fi='Finhead:BAABLgAECn8zAAIKAAkJXQ6TPADDAQAKAAkJXQ6TPADDAQAAAA==.Fionna:BAAALgAECgcJDAAAAA==.Firereina:BAAALgADCggJGQABLgAECgYJJAAGAE0WAA==.Fishbone:BAAALgADCgQJBAAAAA==.',
Fl='Fleurminator:BAABLgAECn8gAAICAAkJBxH+JgCdAQACAAkJBxH+JgCdAQAAAA==.Fluffybaby:BAAALgADCgMJAwAAAA==.',
Fo='Fondadix:BAABLgAECn8lAAIPAAkJpyETBwCIAgAPAAkJpyETBwCIAgAAAA==.',
Fr='Frieia:BAABLgAECn8ZAAIQAAYJfAk3ZwDeAAAQAAYJfAk3ZwDeAAAAAA==.Frostiilocks:BAAALgAECggJCQAAAA==.Frostitutte:BAAALgAECgYJEQAAAA==.',
Fu='Fuze:BAAALgAECgEJAgAAAA==.',
Ga='Galakrosh:BAACLgAFFH8HAAMbAAMJASHhBwCsAAAZAAMJASFYVgDsAAAbAAIJ9B/hBwCsAAAuAAQKfyoABBsACAkYJJ0DAEECABkACAlwHT4XAMkCABsACAlpIp0DAEECABwAAQkAAIFjAEgAAAAA.Galarína:BAABLgAECn80AAMDAAkJFCJGCQDSAgADAAgJqSFGCQDSAgAEAAkJ8R2ZCQCGAgAAAA==.Gandora:BAABLgAECn8gAAMVAAkJwxZNPwDjAQAVAAkJwxZNPwDjAQANAAEJ/wObLgAnAAAAAA==.Gardrius:BAAALgADCgEJAQAAAA==.',
Ge='Gene:BAAALgADCgcJBwAAAA==.Gentonord:BAABLgAECn8cAAMCAAgJJhrrNwBBAQACAAgJBRfrNwBBAQAdAAYJXBdrIAA9AQAAAA==.',
Gi='Gingerports:BAAALgADCgEJAQAAAA==.',
Gl='Glomps:BAAALgAFFAMJAwABLgAFFAUJBgAeAFkEAA==.',
Go='Gonaldduck:BAAALgAECgUJBQAAAA==.',
Gr='Greasemunkey:BAABLgAECn8jAAITAAgJtw9kEgBbAQATAAgJtw9kEgBbAQAAAA==.Greentea:BAAALgADCggJCwAAAA==.Griiv:BAACLgAFFH8FAAISAAIJBB12YQCoAAASAAIJBB12YQCoAAAuAAQKfyMAAhIACAnNISEWAOQCABIACAnNISEWAOQCAAAA.Grislytotem:BAAALgADCgYJCAAAAQ==.',
Ha='Hakunamatata:BAAALgAECgIJAwAAAA==.Hamburger:BAABLgAECn8ZAAIXAAcJWxUaJACAAQAXAAcJWxUaJACAAQAAAA==.Hammerhard:BAAALgADCgYJCgAAAA==.Hampter:BAAALgAECgYJCQABLgAECgkJJQAXAMgaAA==.Haymáker:BAAALgADCgIJAgAAAA==.',
He='Heights:BAAALgAECgUJDgAAAA==.Heliosan:BAAALgAECgEJAQAAAA==.Heyu:BAAALgAECgUJCAABLgAECggJGwAKABcWAA==.',
Hi='Himoe:BAAALgADCgcJDQAAAA==.',
Ho='Holybean:BAAALgADCgkJGAABLgAECgUJDwAHAAAAAA==.Holyhench:BAAALgAECgUJBQAAAA==.Honkeykong:BAAALgADCgIJAgAAAA==.Hoochix:BAAALgAECgQJCQAAAA==.',
Hr='Hrsho:BAAALgADCgQJBAAAAA==.Hrshoo:BAAALgADCgEJAQAAAA==.',
Hu='Humzashaind:BAAALgAECgYJDwAAAA==.Huntinrabits:BAAALgADCgIJAgAAAA==.Huntt:BAAALgAECgEJAQAAAA==.Huzzyy:BAAALgAECggJCgABLgAECgkJHwARAN0bAA==.',
Hy='Hyphira:BAAALgAECgQJCgABLgAECgUJDQAHAAAAAA==.',
In='Inferbloom:BAAALgAECggJCAABLgAFFAQJDwAHAAAAAA==.Infernum:BAAALgAFFAQJDwAAAQ==.Insomnia:BAAALgAECgUJBQAAAA==.',
Ir='Irayvia:BAAALgADCgIJAgAAAA==.',
Ja='Jackyvoker:BAABLgAECn8qAAMJAAkJfCJwAQBvAwAJAAkJfCJwAQBvAwAGAAMJqRmCJwDlAAAAAA==.Jaezzon:BAAALgADCgQJBwAAAA==.Janessah:BAAALgADCgEJAQAAAA==.',
Je='Jeannaah:BAAALgAECgQJBAABLgAECgYJDgAHAAAAAA==.Jetaime:BAAALgAECgUJBQAAAA==.',
Jh='Jharia:BAAALgADCgMJAgAAAA==.',
Ji='Jinksey:BAAALgAECgcJDQABLgAECgcJEQAYABETAA==.',
Jo='Johndoom:BAAALgAECgYJDgAAAA==.Johnfist:BAAALgAECgEJBAAAAA==.Johngrippy:BAAALgAECgEJAwAAAA==.Johnrend:BAAALgAECgEJAQAAAA==.',
Ju='Juicybottoms:BAAALgADCgMJAgAAAA==.',
Ka='Kairstia:BAAALgADCgcJBwABLgAECgYJJAAGAE0WAA==.Kalidormi:BAAALgAECgUJCQAAAA==.Kalzious:BAAALgADCgkJHAAAAA==.Kamikaze:BAAALgAECgcJBQAAAA==.Kayelalynn:BAABLgAECn8kAAMFAAkJXhVWFgDyAQAFAAkJXhVWFgDyAQAQAAMJNgEowgBDAAAAAA==.',
Kd='Kd:BAAALgAECgEJAQAAAA==.',
Ke='Keiri:BAAALgADCgYJBgAAAA==.Kelana:BAABLgAECn8lAAIOAAkJxB/DBgCvAgAOAAkJxB/DBgCvAgAAAA==.Kendô:BAAALgADCgYJCwAAAA==.Ketdealer:BAAALgAECgcJBwAAAA==.Ketzendk:BAAALgAECgYJBQAAAA==.Keyahi:BAACLgAFFH8PAAIYAAQJ+RkPJwBKAQAYAAQJ+RkPJwBKAQAuAAQKfx0AAhgACQk0HNkbAFACABgACQk0HNkbAFACAAEuAAQKAQkBAAcAAAAA.',
Kh='Khety:BAAALgAECgQJBAAAAA==.',
Ki='Kickandpunch:BAAALgAECgYJDgAAAA==.Kicsi:BAAALgAECgIJAwAAAA==.Kilan:BAABLgAECn8dAAMSAAYJ/xbQpwAJAQASAAUJTRTQpwAJAQAfAAIJNBilLQCHAAAAAA==.Killinrage:BAAALgAECgYJDgAAAA==.Kissofpaine:BAAALgADCgIJAgAAAA==.Kitsuney:BAAALgADCgMJAwAAAA==.Kizaru:BAAALgAECgcJCAAAAA==.',
Ko='Korz:BAAALgADCgcJBwABLgAECgcJFQAUAOEXAA==.',
Kp='Kpop:BAAALgAECgEJAQAAAA==.',
Kr='Krynj:BAAALgAFFAEJAwAAAA==.',
Ku='Kumokiri:BAAALgAECgIJAgAAAA==.Kuromu:BAAALgAECgIJBAAAAA==.Kurzzon:BAAALgADCgMJAwAAAA==.',
Ky='Kyleata:BAABLgAECn8xAAIKAAgJIR4AIgAzAgAKAAgJIR4AIgAzAgAAAA==.Kyleigh:BAAALgAECgQJBQABLgAECgYJDgAHAAAAAA==.Kyokin:BAABLgAECn8oAAMSAAgJjQ93ggBJAQASAAcJihB3ggBJAQAfAAgJ/wWJLACOAAAAAA==.Kyzula:BAABLgAECn8ZAAIMAAYJtBSTRgBhAQAMAAYJtBSTRgBhAQAAAA==.',
La='Lace:BAAALgADCgMJAwAAAA==.Laytone:BAAALgADCgYJBwAAAA==.',
Le='Legcurl:BAAALgAECgEJAwAAAA==.Lepotko:BAAALgAECgQJBAAAAA==.',
Li='Lightbear:BAAALgADCgMJBQAAAA==.Lilchub:BAAALgAECgEJAgAAAA==.Lilylocks:BAAALgAECgYJCAAAAA==.Lilyrocks:BAAALgAECgUJCQAAAA==.Literallad:BAAALgADCgcJBgAAAA==.Littlelo:BAAALgAECgYJBwAAAA==.',
Lo='Lockology:BAAALgAECgIJBAAAAA==.Lokarg:BAAALgADCgIJAgAAAA==.Loudcry:BAACLgAFFH8FAAIgAAMJChJLAQDeAAAgAAMJChJLAQDeAAAuAAQKfy4AAyAACQlnHbQBAKkCACAACAnSH7QBAKkCABQAAwm0EArdALwAAAEuAAUUBQkLAAIAmxwA.',
Lu='Lunaeria:BAAALgADCggJCAAAAA==.',
Ly='Lyanah:BAACLgAFFH8TAAIQAAQJpQfaKwDmAAAQAAQJpQfaKwDmAAAuAAQKfyYAAhAACQl0FHswAOkBABAACQl0FHswAOkBAAAA.Lydia:BAAALgADCgQJBAAAAA==.Lyniah:BAAALgAECgQJBQAAAA==.',
Ma='Machete:BAAALgAECgQJBgAAAA==.Maelius:BAABLgAECn8yAAIRAAkJRhtnCgDBAgARAAkJRhtnCgDBAgAAAA==.Maggrus:BAABLgAECn8bAAIKAAgJFxaDQgCvAQAKAAgJFxaDQgCvAQAAAA==.Malavel:BAAALgADCggJCAAAAA==.Malically:BAABLgAECn8gAAMhAAkJaRAnDwBBAQAhAAgJghEnDwBBAQAKAAYJ7Qt6eAAfAQAAAA==.Manshoon:BAAALgADCgcJCwAAAA==.Marlory:BAAALgADCgUJBQAAAA==.Math:BAAALgAECggJCAABLgAFFAYJCwAeAAYPAA==.Matheney:BAABLgAFFH8QAAIiAAcJCA53AgC6AQAiAAcJCA53AgC6AQABLgAFFAYJCwAeAAYPAA==.Maxnem:BAAALgADCggJCAABLgAECggJHwAFADMPAA==.',
Mc='Mcrib:BAAALgADCggJBQAAAA==.Mctubby:BAAALgADCgUJBQABLgADCgUJBgAHAAAAAA==.Mctubmonk:BAAALgADCgUJBgAAAA==.',
Me='Meatpopsicle:BAAALgADCgEJAQAAAA==.Meigz:BAAALgAECgQJCAAAAA==.Melidin:BAAALgAECgkJEgAAAA==.Melinda:BAAALgAFFAEJAQAAAA==.Melindorei:BAAALgAECgEJAgAAAA==.Melledrus:BAAALgAECgEJAQAAAA==.Mememo:BAAALgAECgMJAwAAAA==.Menöpaws:BAEALgAFFAMJAwAAAA==.Merithrá:BAAALgAECgMJAwAAAA==.',
Mi='Mikaeljayfox:BAAALgAECgcJDwAAAQ==.Mikros:BAAALgAECgMJAwAAAA==.Milenzha:BAABLgAECn8kAAIKAAgJNBarNgDYAQAKAAgJNBarNgDYAQAAAA==.Milkymaiden:BAAALgADCgMJAwABLgADCgYJCQAHAAAAAA==.Mimachote:BAAALgAECgcJDgAAAA==.',
Mo='Monetta:BAAALgADCgIJAgAAAA==.Monk:BAAALgAECggJEAAAAA==.Moonblood:BAAALgADCggJEAAAAA==.Moonfighter:BAAALgAECgEJAgAAAA==.Moontann:BAAALgADCgkJEQAAAA==.Morcombe:BAAALgAECgEJAQAAAA==.Moreia:BAAALgADCgcJBwAAAA==.Motown:BAAALgAECgYJCwAAAA==.Mousse:BAAALgAECgYJEAAAAA==.',
Mu='Murdalok:BAABLgAECn8ZAAIQAAgJshWdNQDSAQAQAAgJshWdNQDSAQAAAA==.',
My='Mysharona:BAAALgAECgEJAQAAAA==.Mystahmurdah:BAAALgADCgQJBwABLgAECgYJDgAHAAAAAA==.Mysterioñ:BAAALgAECgQJDQAAAA==.',
['Má']='Mákla:BAAALgAECgMJAwAAAA==.',
['Mâ']='Mâstermînd:BAAALgAECgUJDgAAAA==.',
Na='Nahte:BAAALgADCgYJCQAAAA==.Naiana:BAAALgADCgIJAgAAAA==.Nasine:BAAALgAECgYJCAABLgAECggJGAALAJEeAA==.Natstryker:BAABLgAECn8zAAQOAAkJGCUeAQBXAwAOAAkJGCUeAQBXAwAEAAYJiiJMFQBCAgADAAcJMRFuMgBbAQAAAA==.Naturemyth:BAAALgAFFAEJAwAAAA==.Nazu:BAAALgADCgUJCgAAAA==.',
Ne='Neeró:BAABLgAECn8gAAIYAAYJphUzawAnAQAYAAYJphUzawAnAQAAAA==.Nelthon:BAAALgADCgYJBgAAAA==.',
Ni='Nishastraza:BAAALgAECgEJAwABLgAECgYJDgAHAAAAAA==.',
No='Nonaha:BAAALgADCgkJEQAAAA==.Notsoda:BAAALgAECgQJCQAAAA==.',
Oa='Oaf:BAAALgAECgYJBgAAAA==.',
Oo='Oolong:BAAALgAECgQJBAAAAA==.',
Or='Organa:BAABLgAECn8eAAICAAYJ+gsvRwD/AAACAAYJ+gsvRwD/AAAAAA==.',
Ou='Outofthedark:BAAALgAECgIJAgAAAA==.',
Pa='Pakkan:BAAALgAECgEJAQAAAA==.Pallyqb:BAAALgADCgEJAQAAAA==.Pauladeenx:BAAALgAECgIJAwABLgAECgUJDgAHAAAAAA==.',
Pe='Petal:BAAALgAECgYJBwABLgAECggJEAAHAAAAAA==.',
Pl='Playwitwe:BAAALgAECgMJAwAAAA==.Plowmcballs:BAABLgAECn8ZAAISAAYJtxIzfgB+AQASAAYJtxIzfgB+AQAAAA==.Plugley:BAABLgAECn8bAAMUAAgJ7RqjQgD4AQAUAAgJ7RqjQgD4AQAgAAEJARSGHAA6AAAAAA==.',
Po='Polaris:BAAALgAECgEJAQAAAA==.Poober:BAABLgAECn8cAAIWAAgJeCEYCQC0AgAWAAgJeCEYCQC0AgAAAA==.Potooòooóoo:BAABLgAECn8dAAINAAcJVhhhDwA0AQANAAcJVhhhDwA0AQAAAA==.',
Pr='Pren:BAAALgAFFAEJAQAAAA==.Privet:BAAALgAECgEJAwAAAA==.',
Pu='Purebeef:BAAALgAECgIJAgAAAA==.',
Py='Pygos:BAABLgAECn8ZAAIjAAgJ5BiJBwANAgAjAAgJ5BiJBwANAgAAAA==.',
['Pë']='Përdü:BAAALgAECgUJCwAAAA==.',
Qu='Quigglay:BAAALgAECgYJBgAAAA==.',
Ra='Raegnarok:BAAALgAECgcJEgAAAA==.Raelessa:BAAALgAECgQJCQABLgAECgYJDgAHAAAAAA==.Raigeki:BAAALgADCgQJBQAAAA==.Ralf:BAAALgAECgEJAQAAAA==.Ralphie:BAAALgAECgIJAgAAAA==.Ratapew:BAAALgAECgUJDAAAAA==.Ratheen:BAABLgAECn8dAAISAAgJtA6vfABUAQASAAgJtA6vfABUAQAAAA==.Raytar:BAABLgAECn8fAAMFAAkJ2R7fDABjAgAFAAgJ2B/fDABjAgAQAAMJ9RsBmwCWAAAAAA==.',
Re='Rekkirin:BAAALgAECgUJBQABLgAECgkJNgAJAAUWAA==.Relyk:BAAALgADCgUJBQAAAA==.',
Ri='Riyo:BAAALgAECgEJAgABLgAECgcJGQAOAHgXAA==.',
Ro='Roachie:BAAALgAECgYJDgAAAA==.Rockandstone:BAAALgADCgEJAQAAAA==.Roesira:BAAALgAECgEJAQAAAA==.Rogun:BAAALgAECgkJAQAAAA==.Ros:BAAALgAECgMJBAAAAA==.',
Ru='Rug:BAAALgADCgYJBgAAAA==.Rustybray:BAABLgAECn8zAAILAAkJawc2NgAwAQALAAkJawc2NgAwAQAAAA==.Ruu:BAAALgAECgkJBQABLgAFFAQJDgAkAAQRAA==.',
Ry='Ryvulz:BAABLgAECn8eAAIXAAgJHRWsGAAcAgAXAAgJHRWsGAAcAgAAAA==.',
Sa='Salomicum:BAAALgADCgEJAQAAAA==.Sappollo:BAAALgADCgMJAwAAAA==.Sarabi:BAABLgAECn8fAAIDAAYJtBcNKgCOAQADAAYJtBcNKgCOAQAAAA==.Sarena:BAAALgADCgMJAwAAAA==.Sarkoth:BAAALgADCgEJAQAAAA==.',
Sc='Schnee:BAAALgADCgYJCgAAAA==.Scrapster:BAAALgAECgUJCgAAAA==.',
Se='Seifer:BAAALgADCgEJAQAAAA==.Sekha:BAAALgAECgQJBgABLgAECggJIAAFALwWAA==.Seshiro:BAAALgAECgQJBAABLgAECgkJMgAfANkjAA==.',
Sh='Shadoweave:BAACLgAFFH8QAAMWAAQJSxg/DwAnAQAWAAQJSxg/DwAnAQAXAAIJ+wRMJwB9AAAuAAQKfxkAAhYACQkoGB4PAE8CABYACQkoGB4PAE8CAAEuAAUUCAknAAoA4xcA.Shalalia:BAAALgAECgcJEAAAAA==.Shambean:BAAALgADCgEJAQABLgAECgUJDwAHAAAAAA==.Shammywitch:BAAALgAECgMJAwABLgAECgMJCQAHAAAAAA==.Shentsu:BAABLgAECn8YAAIDAAkJ0CD7BQD/AgADAAkJ0CD7BQD/AgAAAA==.Shhanks:BAAALgAECgEJAQAAAA==.Shinmen:BAAALgADCgkJCQAAAA==.Shinsha:BAAALgADCgIJAwAAAA==.Shnizelnazee:BAABLgAECn8WAAISAAgJDwxxkAAxAQASAAgJDwxxkAAxAQAAAA==.Shortonheals:BAAALgAECgMJAwAAAA==.',
Si='Siege:BAAALgAECgUJBQAAAA==.Silie:BAAALgADCgEJAQAAAA==.Silik:BAAALgADCgcJBwAAAA==.Simpforsale:BAAALgAECgYJCQAAAA==.',
Sk='Skybladee:BAAALgADCgcJDgAAAA==.',
Sm='Smokeyb:BAABLgAECn8qAAISAAcJChkJVQCsAQASAAcJChkJVQCsAQAAAA==.',
Sn='Sneevie:BAAALgAECggJCgAAAA==.Snorehees:BAABLgAECn8nAAMKAAkJ2w2oQQCxAQAKAAkJ2w2oQQCxAQAhAAQJMwKgLQBHAAAAAA==.',
So='Songarrow:BAAALgAECgYJBgAAAA==.Songstar:BAABLgAECn8qAAIKAAkJaiPTCQDnAgAKAAkJaiPTCQDnAgAAAA==.Soullraven:BAAALgADCgkJMAAAAA==.',
Sp='Spy:BAAALgAECgEJBQAAAA==.',
Sq='Squingledorf:BAAALgAECgMJAwAAAA==.',
St='Staavon:BAABLgAECn8gAAIUAAcJAwgOowAcAQAUAAcJAwgOowAcAQAAAA==.Stacy:BAAALgAECgEJAQABLgAECgQJCAAHAAAAAA==.Starblaze:BAAALgAECgYJCAAAAA==.Starseek:BAABLgAECn8UAAIjAAcJLhDLEABDAQAjAAcJLhDLEABDAQAAAA==.Steelboats:BAAALgADCgkJGQAAAA==.',
Su='Sugarbow:BAAALgADCgMJAwAAAA==.Sugarlick:BAABLgAECn8jAAIPAAgJPRtHEgC7AQAPAAgJPRtHEgC7AQAAAA==.Sugarpop:BAACLgAFFH8GAAIRAAMJNw23KAC1AAARAAMJNw23KAC1AAAuAAQKfygAAhEACQnXHIISAH4CABEACQnXHIISAH4CAAAA.Sunraku:BAAALgAECgIJAwAAAA==.Suplazindh:BAAALgAFFAIJAgABLgAFFAkJMgAVAOceAA==.',
Sw='Swethort:BAAALgADCgcJBgAAAA==.',
Sy='Synman:BAAALgADCgYJBgAAAA==.Syntheria:BAAALgADCgcJCQAAAA==.Syrebriel:BAABLgAECn8VAAIlAAcJCxEBJABzAQAlAAcJCxEBJABzAQAAAA==.',
['Sí']='Sílíbrítí:BAAALgAECgYJDQABLgAECggJGgADAPsWAA==.',
Ta='Taediah:BAAALgAECgcJDQAAAA==.Tamius:BAAALgADCgEJAQAAAA==.Tanthanalas:BAAALgAECgEJAQAAAA==.',
Th='Thefalsehope:BAAALgADCgcJBwAAAA==.Theoutcast:BAAALgAECgQJBQAAAA==.Thesarius:BAABLgAECn8ZAAIdAAgJXxmXDQAxAgAdAAgJXxmXDQAxAgAAAA==.Thortor:BAAALgADCgIJAgABLgADCggJEAAHAAAAAA==.',
Ti='Tiestto:BAAALgAECgcJDgAAAA==.Tinkermid:BAAALgADCgEJAQAAAA==.Tinymeatgang:BAAALgADCggJCQAAAA==.',
To='Tobalwl:BAAALgADCgUJBQAAAA==.Tockley:BAABLgAECn8hAAIUAAgJQwZNwwDnAAAUAAgJQwZNwwDnAAAAAA==.Toetagger:BAABLgAECn8VAAIVAAYJaw4yngBEAQAVAAYJaw4yngBEAQAAAA==.Tofino:BAAALgAECgUJCAAAAA==.Tohner:BAAALgADCgMJAwAAAA==.Tolidron:BAAALgADCgEJAQAAAA==.Tonimâster:BAAALgAECgcJCwAAAA==.Tonydmaster:BAAALgAECgEJAQAAAA==.Toyotama:BAAALgAECgUJDQAAAA==.',
Tr='Trenbologna:BAAALgAECgEJAQAAAA==.Tristah:BAAALgAECgUJDwABLgAECgYJDgAHAAAAAA==.Trzlawd:BAAALgADCgEJAQAAAA==.',
Ty='Tyindron:BAAALgAECgYJBwAAAA==.Tyrrial:BAABLgAECn8lAAISAAcJyBgMWgCfAQASAAcJyBgMWgCfAQAAAA==.Tyshus:BAAALgAECgYJDAAAAA==.',
Ud='Udntknwme:BAAALgAFFAIJAwAAAA==.',
Un='Unbral:BAAALgADCgEJAQAAAA==.Unicood:BAAALgADCgYJBgAAAA==.Unlockbot:BAAALgADCgEJAwABLgAECgcJDwAHAAAAAA==.',
Ut='Uthgardt:BAAALgAECgYJBgAAAA==.',
Va='Valarion:BAABLgAECn8kAAImAAcJoBIHGQBoAQAmAAcJoBIHGQBoAQAAAA==.Valcaryn:BAAALgADCgYJBgAAAA==.Validimus:BAAALgAECgcJCwAAAA==.Valinis:BAAALgAECgQJBAAAAA==.Valinius:BAAALgADCgYJCQAAAA==.Valorían:BAABLgAECn8zAAMCAAkJsSMWCADAAgACAAkJ+iEWCADAAgAdAAUJ9yP9CwAGAgAAAA==.Valtaa:BAAALgADCgUJBgAAAA==.Vanza:BAAALgADCgEJAQAAAA==.Varthayn:BAABLgAECn9BAAIUAAkJ4iBPEwDMAgAUAAkJ4iBPEwDMAgAAAA==.',
Ve='Vecna:BAAALgAECgMJAwABLgAECgYJCAAHAAAAAA==.Velandriel:BAAALgADCgkJCwABLgAECgEJAgAHAAAAAA==.Vengfuhl:BAAALgAECgQJAwAAAA==.Verra:BAAALgAECgEJAQAAAA==.Vet:BAAALgAECgEJAQAAAA==.',
Vo='Voidwa:BAAALgAECgYJDgAAAA==.Volbain:BAABLgAECn8lAAMnAAYJGxzJGACEAQAnAAYJGxzJGACEAQAYAAEJ0wLnCQEcAAAAAA==.Volklin:BAABLgAECn8iAAMKAAkJ4BHeTQB/AQAKAAcJaRTeTQB/AQAkAAkJUggnJQBTAQAAAA==.Voltagex:BAABLgAECn8dAAIYAAcJfRzKSACKAQAYAAcJfRzKSACKAQAAAA==.',
Vu='Vulpsinculta:BAABLgAECn8gAAIZAAYJeheAaQBTAQAZAAYJeheAaQBTAQAAAA==.',
['Vï']='Vïrùs:BAABLgAECn8jAAIFAAcJeg1aPABDAQAFAAcJeg1aPABDAQAAAA==.',
Wa='Wanda:BAAALgAECgYJBgAAAA==.',
Wi='Wichita:BAABLgAECn8yAAMVAAkJsA/QUACtAQAVAAgJEhHQUACtAQAPAAEJBQaIUwAgAAAAAA==.Wildkitty:BAAALgAECgYJCAAAAA==.',
Wo='Wolfyze:BAAALgADCgEJAQAAAA==.',
Wr='Wrâth:BAAALgAECgEJAQAAAA==.',
Wt='Wtfguën:BAABLgAECn8iAAIiAAYJzgzLKgDAAAAiAAYJzgzLKgDAAAAAAA==.Wtfstormy:BAAALgADCgkJDAABLgAECgYJIgAiAM4MAA==.Wtftäzmikell:BAAALgADCgYJCQABLgAECgYJIgAiAM4MAA==.',
Wu='Wutäng:BAAALgADCgYJCgAAAA==.',
Xe='Xera:BAAALgADCgYJBgAAAA==.',
Xo='Xondra:BAAALgAECgYJDQAAAA==.',
Xr='Xravo:BAAALgADCgkJCQAAAA==.',
Xz='Xzairi:BAABLgAECn8gAAIFAAgJvBaCHwCeAQAFAAgJvBaCHwCeAQAAAA==.',
Ya='Yarria:BAAALgADCgIJAgAAAA==.',
Yi='Yinh:BAAALgADCgcJDAAAAA==.',
Yo='Yoiki:BAAALgAECgEJAQABLgAECgEJAQAHAAAAAA==.',
Yu='Yuck:BAAALgAECgIJBAAAAA==.',
Yy='Yy:BAAALgAECgUJDAAAAA==.',
Ze='Zeuzco:BAAALgAECgkJEAAAAA==.',
Zo='Zorell:BAAALgAECgEJAQAAAA==.Zovaal:BAAALgADCgYJBgAAAA==.',
['Ál']='Áltá:BAABLgAECn8tAAMZAAkJ5RigHwBOAgAZAAkJ5RigHwBOAgAcAAIJNwyqKQBZAAAAAA==.',
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
