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

local lookup = {'DeathKnight-Unholy','Druid-Feral','Druid-Restoration','Mage-Frost','Mage-Arcane','Shaman-Elemental','Hunter-BeastMastery','Priest-Holy','DemonHunter-Havoc','DemonHunter-Vengeance','Shaman-Enhancement','Warrior-Arms','DeathKnight-Blood','Rogue-Assassination','Evoker-Preservation','Druid-Guardian','Monk-Brewmaster','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Unknown-Unknown','Shaman-Restoration','DemonHunter-Devourer','Druid-Balance','Hunter-Marksmanship','Monk-Windwalker','Paladin-Holy','Paladin-Retribution','Rogue-Subtlety','Evoker-Devastation','Rogue-Outlaw','DeathKnight-Frost','Priest-Shadow','Paladin-Protection','Warrior-Fury','Mage-Fire','Priest-Discipline','Evoker-Augmentation','Monk-Mistweaver','Warrior-Protection',}
local provider = {region='US',realm='Spirestone',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Abduon:BAAANQADCgcICwAAAA==.',
Ac='Aciddeath:BAAANQAECgEIAQABNQAFFAUIFQABAP8RAA==.',
Ad='Admaris:BAACNQAFFH8JAAMCAAIKbRFkAwCaAAACAAIKbRFkAwCaAAADAAIKMhq5DwCMAAA1AAQKfzsAAwMACgp1IPwMAP8CAAMACgp1IPwMAP8CAAIABwqQIdIJAKMCAAAA.',
Ae='Aelis:BAAANQABCgEIAQAAAA==.',
Ag='Agni:BAACNQAFFH8VAAMEAAgK/w9RAwDrAAAFAAUKwwuiJwBLAQAEAAMKOxRRAwDrAAA1AAQKfzMAAwUACgqSJDhLAOsCAAUACgqTIzhLAOsCAAQAAwrsIxAWAB8BAAAA.',
Ak='Akkadian:BAAANQADCggICwAAAA==.',
Al='Almight:BAAANQADCgcICgAAAA==.Alnasham:BAACNQAFFH8TAAIGAAcKcxkRBQCbAQAGAAcKcxkRBQCbAQA1AAQKfzIAAgYACgoTIoUUAE4DAAYACgoTIoUUAE4DAAAA.Alnava:BAAANQAECgcIDwAAAA==.Altria:BAAANQAECgIIAQAAAA==.Alvoka:BAABNQAECn8VAAIFAAcKLRbv0QDiAQAFAAcKLRbv0QDiAQAAAA==.',
Am='Amarillos:BAABNQAECn8fAAIHAAkKbxQqYwBPAgAHAAkKbxQqYwBPAgAAAA==.Amarillys:BAABNQAECn88AAIIAAoK4CDSDABrAwAIAAoK4CDSDABrAwAAAA==.Ammutseba:BAABNQAECn8oAAMJAAoK0hkaHAAaAgAJAAoKlxkaHAAaAgAKAAMK2hZFIgCwAAAAAA==.',
An='Anfall:BAACNQAFFH8WAAILAAYKHBLgAQAzAQALAAYKHBLgAQAzAQA1AAQKfzsAAgsACgoxIksIAPUCAAsACgoxIksIAPUCAAAA.Angermeier:BAABNQAECn9CAAIMAAoKLBUvSAAXAgAMAAoKLBUvSAAXAgAAAA==.Angers:BAAANQAECgIIAgABNQAECgoKQgAMACwVAA==.Angrylady:BAAANQAECgEIAQAAAA==.Anjuna:BAAANQADCgUIBQAAAA==.Anohru:BAAANQAECggIDQAAAA==.Anthos:BAAANQAECggIDQAAAA==.Antikreist:BAAANQADCgUIBQAAAA==.Anyawnka:BAAANQABCggIGgAAAA==.',
Ap='Aphotic:BAAANQAECgEIAQAAAA==.',
Ar='Arcady:BAAANQADCgYIBgAAAA==.Ards:BAAANQADCgIIAwAAAA==.Armanite:BAAANQAECgQIBQABNQAECgoKIQABAFobAA==.Arowin:BAAANQAECgcICAAAAA==.Arthaniis:BAABNQAECn8YAAIGAAcKKCESSwBKAgAGAAcKKCESSwBKAgAAAA==.',
As='Asystoli:BAABNQAECn8uAAMFAAoKtxY5eQCnAQAFAAkKyBc5eQCnAQAEAAIKQw/XOQA9AAAAAA==.',
At='Atheria:BAAANQADCgYICAAAAA==.Attackheli:BAAANQAECgQIDwAAAA==.',
Au='Audideath:BAAANQAECgUICQAAAA==.Auurdeath:BAAANQADCggIEwAAAA==.',
Av='Av:BAAANQADCgIIBQAAAA==.',
Aw='Aw:BAACNQAFFH8cAAIJAAcKLRyqAwBFAgAJAAcKLRyqAwBFAgA1AAQKfyoAAgkACgoKJvQFAJYDAAkACgoKJvQFAJYDAAAA.',
Ax='Ax:BAECNQAFFH8RAAMBAAcKdRasBwCeAQABAAYKdRasBwCeAQANAAEKAADZOQAfAAA1AAQKfywAAgEACgqJIx8VADgCAAEACgqJIx8VADgCAAAA.',
Az='Azzazinzblo:BAAANQADCgUIBQAAAA==.',
['Aÿ']='Aÿa:BAAANQAECgUIDgAAAA==.',
Ba='Baast:BAAANQADCgUIBQAAAA==.Bamph:BAAANQAECggIDQAAAA==.Bangbang:BAAANQAECgcIDwAAAA==.Batez:BAAANQAECgQIBAABNQAFFAcIEgAOAIUOAA==.',
Bd='Bdk:BAABNQAECn8UAAINAAkKuR2rGQDgAgANAAkKuR2rGQDgAgAAAA==.Bdog:BAAANQAECgEIAwAAAA==.',
Be='Beeatinu:BAAANQAECgMIAwAAAA==.Beers:BAAANQAECggIBwAAAA==.Beledros:BAABNQAECn8cAAIPAAkKVBP4FQBWAgAPAAkKVBP4FQBWAgAAAA==.Beni:BAABNQAECn9bAAMQAAoKBCTnAgBBAwAQAAoKBCTnAgBBAwACAAgKaxujCQAtAgAAAA==.Benson:BAABNQAECn8hAAIRAAkKoxwsCACuAgARAAkKoxwsCACuAgAAAA==.Bensonadin:BAAANQAECgYIBgAAAA==.Berd:BAAANQAECggIBgAAAA==.',
Bi='Bigwillybob:BAAANQADCgIIAgAAAA==.Billiegoat:BAAANQAECggIAgAAAA==.Bina:BAAANQAECgQIBQAAAA==.Birblock:BAACNQAFFH8gAAQSAAYK6iKNAgBqAgASAAYK6iKNAgBqAgATAAIKygE5EwB6AAAUAAEK/BkXCABiAAA1AAQKfyMABBIACQotJiYzALwCABIABwo1JiYzALwCABMABwq3GxUUAM8BABQAAQoAAFYpAEcAAAAA.',
Bo='Bobbo:BAAANQADCgYJBwAAAA==.',
Br='Brek:BAAANQAECgYIDAAAAA==.Brewtherguy:BAABNQAECn8iAAIRAAkKAB1oBwDGAgARAAkKAB1oBwDGAgAAAA==.Brother:BAAANQADCgIIAgAAAA==.Bruceshepard:BAAANQADCgQICQABNQAECgUIDQAVAAAAAA==.Brutebuffalo:BAABNQAECn8lAAMWAAkKqh2uIwDYAgAWAAkKqh2uIwDYAgAGAAUKQBH/rQA3AQAAAA==.Bruteflappy:BAAANQADCggICAABNQAECgkJJQAWAKodAA==.Brutetestify:BAAANQADCggICAABNQAECgkJJQAWAKodAA==.',
Bu='Bubbleboi:BAAANQADCgYICAAAAA==.Bubblebôy:BAAANQAECgIIAgAAAA==.Bublz:BAABNQAECn8eAAIIAAkKThWgaQDhAQAIAAkKThWgaQDhAQAAAA==.',
['Bâ']='Bâra:BAABNQAECn8eAAIBAAoKahqhJQCoAgABAAoKahqhJQCoAgAAAA==.',
Ca='Camdreya:BAAANQABCgEIAQAAAA==.Carnal:BAAANQADCgUIBQAAAA==.Castro:BAAANQAECgIIAgAAAA==.',
Ce='Cedren:BAACNQAFFH8MAAIJAAYKsQugDgAfAQAJAAYKsQugDgAfAQA1AAQKfzYAAwkACgpCHRAcABoCAAkACgpFHBAcABoCABcACAotE7srAOQBAAAA.Ceewhya:BAAANQAECgIIAQAAAA==.Celestika:BAAANQABCgIIAgAAAA==.Cerari:BAAANQAECgEJAQAAAA==.',
Ch='Chalix:BAAANQAECgIIBAAAAA==.Chama:BAABNQAECn8aAAIXAAkKpxI0JAAmAgAXAAkKpxI0JAAmAgAAAA==.Cheapheal:BAABNQAECn9GAAMQAAoKNCDzBABSAwAQAAoKNCDzBABSAwAYAAEKAAAtmwAAAAAAAA==.Cheapsnipe:BAABNQAECn8aAAMHAAoKhxaoOABZAgAHAAoKhxaoOABZAgAZAAUKFggaMwDLAAABNQAECgoKRgAQADQgAA==.Cheburashka:BAACNQAFFH8YAAIGAAcKxiKrBABIAgAGAAcKxiKrBABIAgA1AAQKfyIAAgYACgpbIakoAN8CAAYACgpbIakoAN8CAAAA.Chimerabob:BAAANQAECgMIBwAAAA==.Chispaa:BAAANQADCgEIAQAAAA==.Chopsuey:BAAANQAECggIBAAAAA==.Chunkymonkey:BAACNQAFFH8XAAIaAAcK0xa7BADwAQAaAAcK0xa7BADwAQA1AAQKf0QAAhoACgrYI2IDAD8DABoACgrYI2IDAD8DAAAA.',
Ci='Cidren:BAAANQAECgEIAQAAAA==.',
Cl='Clappncheeks:BAABNQAECn8hAAIHAAoK+BhkSQAqAgAHAAoK+BhkSQAqAgAAAA==.Claudefrollo:BAABNQAECn8qAAIYAAoKFgzjMgBcAQAYAAoKFgzjMgBcAQAAAA==.',
Cr='Crankyelf:BAAANQABCgEIAQAAAA==.Crimsa:BAABNQAECn9GAAIUAAoKDQYTDABlAQAUAAoKDQYTDABlAQAAAA==.Crimsonaxel:BAABNQAECn8qAAIGAAoK1xkRLgAOAgAGAAoK1xkRLgAOAgAAAA==.Cryogen:BAAANQAECgQJCAAAAA==.',
Cu='Cursewords:BAAANQADCgUIBQABNQAECgYIBgAVAAAAAA==.',
Da='Daemonproph:BAAANQADCgYIDAAAAA==.Dakini:BAABNQAECn85AAIbAAoKUh+7FwDqAgAbAAoKUh+7FwDqAgAAAA==.Dam:BAAANQADCgUIBQABNQAECgkJIAANABgXAA==.Dangerruss:BAAANQAECgYICQAAAA==.Darkspartan:BAAANQAECgYIBQAAAA==.Dashytash:BAABNQAECn86AAIKAAoK2h0YBACWAgAKAAoK2h0YBACWAgAAAA==.Dawnsoul:BAAANQAECgYIDQAAAA==.Daxos:BAAANQADCgcIDQAAAA==.',
De='Deadcowmeat:BAAANQAECggICAAAAA==.Deathschosen:BAAANQADCgQIBAAAAA==.Deiza:BAAANQAECgMIAQAAAA==.Demb:BAAANQAECgQIBwAAAA==.Demonicchoas:BAABNQAECn8yAAMTAAoKmx/MDAArAgASAAkKpx6tWwBEAgATAAcKfhzMDAArAgAAAA==.Denagorn:BAACNQAFFH8FAAIcAAQKaB2pDQAIAQAcAAQKaB2pDQAIAQA1AAQKf0IAAhwACgrNJB4RAIQDABwACgrNJB4RAIQDAAE1AAUUCAgxAAEA9x0A.Denaki:BAAANQAECgQIBAABNQAFFAgIMQABAPcdAA==.Denhunt:BAABNQAECn8lAAMHAAoKtCAHIgAPAwAHAAoKpyAHIgAPAwAZAAQKLRmPNADDAAABNQAFFAgIMQABAPcdAA==.Dentsama:BAAANQAECggICwABNQAFFAgIMQABAPcdAA==.Deplete:BAAANQADCgIJAgABNQAECgoKRgAYALgbAA==.Deutzfr:BAABNQAECn8YAAIKAAkKfxwZBwCfAgAKAAkKfxwZBwCfAgAAAA==.Devos:BAABNQAECn8YAAMGAAcKgBMrcgDKAQAGAAcKgBMrcgDKAQAWAAQKRQ6X1gC6AAABNQAFFAUICQAGAIcEAA==.',
Di='Dizzleman:BAAANQAECggICgAAAA==.',
Do='Dominant:BAABNQAECn8xAAMFAAoKESALWQDOAgAFAAoKESALWQDOAgAEAAEKAAA5SgAxAAAAAA==.',
Dp='Dpssos:BAAANQAECggIDgAAAA==.',
Dr='Draco:BAAANQADCgcIBwAAAA==.Drag:BAAANQADCgYICAAAAA==.Drbob:BAAANQADCgIIAgAAAA==.Dreadmar:BAAANQADCgYICAAAAA==.Drock:BAABNQAECn9CAAIXAAoKzCAqCABQAwAXAAoKzCAqCABQAwAAAA==.Druidgale:BAAANQAECgIIAwAAAA==.Drybonez:BAAANQAECgYICAAAAA==.Drygth:BAAANQADCgMIBgABNQAECgoKMQAdABEiAA==.Dräkarnoir:BAAANQADCggICAAAAA==.',
Dt='Dtb:BAACNQAFFH8XAAINAAYKZh8UCADgAQANAAYKZh8UCADgAQA1AAQKfzkAAg0ACgp4JeYEAKMDAA0ACgp4JeYEAKMDAAAA.',
Du='Dushimaya:BAABNQAECn8+AAIbAAoKAiSOBwCOAwAbAAoKAiSOBwCOAwAAAA==.',
Dv='Dvil:BAAANQAECgQIBQABNQAECgoKQgAXAMwgAA==.',
Dw='Dwyndi:BAAANQAECgYICAAAAA==.',
Ei='Eisador:BAABNQAECn8VAAIHAAcKWAtIqAC1AQAHAAcKWAtIqAC1AQAAAA==.',
El='Elsen:BAAANQAECgUIDQAAAA==.Elsha:BAABNQAECn8hAAIRAAkKtxtdCACmAgARAAkKtxtdCACmAgAAAA==.',
Em='Emp:BAAANQAECgUIBgAAAA==.',
Er='Erilee:BAAANQAECgYICgAAAA==.',
Ev='Evelira:BAABNQAFFH8TAAIIAAcKyBu+BwARAgAIAAcKyBu+BwARAgAAAA==.',
Ey='Eyja:BAAANQADCgEIAgAAAA==.',
Ez='Ezailas:BAAANQAECgQIBQAAAA==.Ezpzndaheezy:BAAANQAECgQIBAABNQAECgoKRwAeAKUZAA==.',
Fa='Fatherangus:BAAANQAECggICAAAAA==.Fathercoast:BAAANQAECgYICwAAAA==.',
Fe='Fearful:BAACNQAFFH8FAAIbAAMKYAJkGwC+AAAbAAMKYAJkGwC+AAA1AAQKfyIAAhsACQr5Ff5GAEoCABsACQr5Ff5GAEoCAAAA.Felstrider:BAAANQADCgUIBQAAAA==.Ferador:BAACNQAFFH8XAAMHAAYK9BaNEABUAQAHAAQKjRmNEABUAQAZAAUKDQ8gDwBMAQA1AAQKfykAAwcACgqVH+xDAJ8CAAcACgqVH+xDAJ8CABkABgq+Ero/AFUBAAAA.Feythe:BAACNQAFFH8zAAINAAoKlxIGAgBaAgANAAoKlxIGAgBaAgA1AAQKfxgAAg0ACgreFxQ5ACICAA0ACgreFxQ5ACICAAAA.',
Fi='Figgleslock:BAAANQADCgUIBQAAAA==.',
Fl='Flakester:BAABNQAECn8pAAIIAAcKLiPjMgBgAgAIAAcKLiPjMgBgAgAAAA==.Fleebly:BAABNQAECn8iAAIXAAoKiBnXGQCLAgAXAAoKiBnXGQCLAgAAAA==.',
Fn='Fndruid:BAAANQAECgIIAgAAAA==.',
Fo='Fourbees:BAABNQAECn8wAAIcAAoKFQ13iQCkAQAcAAoKFQ13iQCkAQAAAA==.',
Fu='Fursure:BAAANQAECgMIAwAAAA==.',
Ga='Garfal:BAAANQAECgIIAwAAAA==.Gather:BAAANQABCgQIBAABNQAECgoKVQAWAGUfAA==.Gaurhoth:BAAANQAECgQIBAABNQAECgQIBgAVAAAAAA==.',
Ge='Gerissa:BAAANQAECgEIAQAAAA==.',
Gi='Gilgamesh:BAAANQAECggIDQAAAA==.',
Go='Gorobob:BAAANQAECgIIBgAAAA==.',
Gr='Graygkl:BAAANQAECgUIDwAAAA==.Greshanwise:BAABNQAECn8nAAIDAAoKSgoELwBbAQADAAoKSgoELwBbAQAAAA==.Grimreaper:BAABNQAECn86AAIfAAoKjxmSBQCPAgAfAAoKjxmSBQCPAgAAAA==.Groag:BAABNQAECn8xAAMdAAoKESKbBQAtAwAdAAoKCyKbBQAtAwAOAAgKYxuJKgBBAgAAAA==.',
Ha='Haarp:BAABNQAECn8WAAIGAAkK6xjeWgBeAQAGAAkK6xjeWgBeAQAAAA==.Haelar:BAAANQAECgEIAQAAAA==.Hakü:BAAANQAECgcIBwAAAA==.Hammered:BAABNQAECn8gAAIcAAkKxiToHwDYAgAcAAkKxiToHwDYAgAAAA==.Haonao:BAAANQAECgQIBQAAAA==.Hardwire:BAAANQAECgEIAQAAAA==.',
He='Heartred:BAAANQADCgYIBgAAAA==.Heifer:BAACNQAFFH8FAAIYAAIKWw3nIQCEAAAYAAIKWw3nIQCEAAA1AAQKfyQAAhgACQrRIZcZAPsCABgACQrRIZcZAPsCAAAA.Hemophilia:BAABNQAECn81AAIBAAoKixKWHADsAQABAAoKixKWHADsAQAAAA==.Heydk:BAABNQAECn8YAAMgAAkKlRuZWgA/AQAgAAUKRhqZWgA/AQABAAYKHBtBfgAjAQAAAA==.Heydruid:BAAANQAECgcIDQABNQAECgkJGAAgAJUbAA==.',
Ho='Hollowshädix:BAAANQAECgEIAQAAAA==.Holyanxiety:BAAANQADCgYIBgAAAA==.Holydave:BAAANQAECgMIBAAAAA==.Holymentos:BAABNQAECn8oAAMhAAoKMRC9JQBAAQAhAAgK7Qu9JQBAAQAIAAcKeAQwygDDAAABNQAECgoKNAAiAAAVAA==.Hottsauce:BAABNQAECn8cAAILAAkKQBwwDQCbAgALAAkKQBwwDQCbAgAAAA==.Hottsaucefel:BAAANQAECgYIBgAAAA==.',
Hu='Hundard:BAAANQADCgIIAgAAAA==.Huntersmarc:BAAANQAECgIIBQAAAA==.Hushhides:BAABNQAECn8iAAMOAAoKEhOnDADzAQAdAAkK8g2CGAAYAgAOAAkKYBKnDADzAQAAAA==.Hushrage:BAAANQAECggICwABNQAECgoKIgAOABITAA==.Hushwing:BAAANQAECggICwABNQAECgoKIgAOABITAA==.',
Ia='Iamachick:BAAANQAECgEIAQAAAA==.',
Ib='Ibetrollinya:BAABNQAECn8YAAICAAoK6iOQAwD2AgACAAoK6iOQAwD2AgABNQAECgoKNQAjAEAmAA==.Iblisshaytan:BAACNQAFFH8GAAIJAAIKfwdDFQBvAAAJAAIKfwdDFQBvAAA1AAQKf00AAgkACgpKHa8WAFICAAkACgpKHa8WAFICAAE1AAUUBggKAB0AMgUA.Ibtrollin:BAAANQADCggIJQAAAA==.',
Ig='Ignacious:BAAANQAECgEIAQAAAA==.',
Il='Illumina:BAACNQAFFH8JAAIiAAUKQxa8BQDTAAAiAAUKQxa8BQDTAAA1AAQKfzEAAiIACQpgIpkIABQDACIACQpgIpkIABQDAAAA.',
Io='Ionissa:BAABNQAECn8wAAIHAAoKTx38LwDdAgAHAAoKTx38LwDdAgAAAA==.',
Ir='Ironbreaker:BAAANQAECgYIDgAAAA==.',
Is='Ischia:BAACNQAFFH8JAAMIAAQK5wgCGwATAQAIAAQK5wgCGwATAQAhAAEKbAEPGwA0AAA1AAQKf0cAAwgACQo0HPU2AIwCAAgACQo0HPU2AIwCACEAAgrUE55pAFsAAAAA.',
Ja='Jallypally:BAAANQADCgIIAgAAAA==.Jarl:BAAANQADCgYICwAAAA==.',
Jc='Jch:BAACNQAFFH8gAAIHAAgKzxxiAQCCAgAHAAgKzxxiAQCCAgA1AAQKfz8AAwcACgq0JbYJADcDAAcACgq0JbYJADcDABkAAQpkFhCGADgAAAAA.',
Je='Jeay:BAAANQAECgEJAQAAAA==.Jedijeed:BAACNQAFFH8TAAIaAAYKhByuAwCYAQAaAAYKhByuAwCYAQA1AAQKfz8AAhoACgreI0oGAGwDABoACgreI0oGAGwDAAAA.Jedikepjr:BAACNQAFFH8GAAIcAAMKZQmRGwDLAAAcAAMKZQmRGwDLAAA1AAQKfyQAAhwACgpdI+kkAMMCABwACgpdI+kkAMMCAAE1AAUUBggTABoAhBwA.Jenova:BAAANQADCgUIBwAAAA==.Jepage:BAABNQAECn9CAAQEAAoKuiBmAwC/AgAEAAoKuiBmAwC/AgAkAAcKXhk+AwB5AQAFAAYK7RPAHAFcAQAAAA==.Jess:BAAANQABCgIIAgAAAA==.',
Jo='Jolyne:BAAANQAECgcIBgAAAA==.Joyful:BAAANQAECgQIBAAAAA==.',
Jp='Jprottsoo:BAABNQAECn8gAAIYAAgKqh7oIgC4AgAYAAgKqh7oIgC4AgAAAA==.',
Ju='Jubei:BAABNQAECn8mAAIjAAoKMA7uDQDUAQAjAAoKMA7uDQDUAQAAAA==.',
Ka='Kagayaki:BAAANQAECggIEgAAAA==.Kalmya:BAABNQAECn8nAAMDAAgKpQ0YMACaAQADAAgKpQ0YMACaAQACAAEKAAAhRgAuAAAAAA==.Kalrath:BAAANQAECgIIAgABNQAECgoKIQABAFobAA==.Kartam:BAAANQADCggIEAAAAA==.Kasheek:BAAANQADCggICAAAAA==.',
Ke='Keizzer:BAAANQAECgcICwABNQAECgkJHQAIAPcbAA==.Keshisaru:BAAANQADCgQIBAAAAA==.',
Kh='Khazra:BAAANQAECgMIBgAAAA==.',
Ki='Kierràalexis:BAAANQADCgYIBgAAAA==.',
Kl='Klunder:BAABNQAECn84AAIWAAoKEyPiHQD1AgAWAAoKEyPiHQD1AgAAAA==.',
Ko='Korris:BAABNQAECn8wAAMHAAoKyiClMADaAgAHAAoKyiClMADaAgAZAAEK1wLwnAAiAAAAAA==.Kostik:BAAANQADCgUIBQAAAA==.',
Kr='Kridillis:BAABNQAECn8tAAIJAAoKFx6ZHAC1AgAJAAoKFx6ZHAC1AgAAAA==.',
Kt='Ktang:BAAANQAFFAEIAQAAAA==.',
Ky='Kybinc:BAAANQADCgQIBAAAAA==.',
['Kí']='Kírã:BAAANQABCgIIBAAAAA==.',
La='Lawls:BAAANQADCgQIBwAAAA==.Lazybigger:BAAANQAECgIIAgAAAA==.Lazycow:BAACNQAFFH8GAAIQAAMKxwlmBwBrAAAQAAMKxwlmBwBrAAA1AAQKf0AAAhAACgr1F5sTAOoBABAACgr1F5sTAOoBAAAA.Lazyfrost:BAABNQAECn8tAAIFAAoKQxCdmwBJAgAFAAoKQxCdmwBJAgAAAA==.',
Le='Lethò:BAABNQAECn8xAAMbAAoKFyO0CACDAwAbAAoKFyO0CACDAwAcAAcKRxmyswBTAQAAAA==.Lethô:BAAANQAECgYIDwAAAA==.Lethö:BAAANQAECgIIBQAAAA==.',
Li='Liesx:BAACNQAFFH8SAAMOAAcKhQ5JBQDfAQAOAAYKIw1JBQDfAQAdAAcKOAnWCQBZAQA1AAQKfywAAx0ACgrbIR8aAKMCAA4ACArtHrwUANUCAB0ACgq/HB8aAKMCAAAA.Lilzarthe:BAAANQAECgYIDgAAAA==.Lindsybowhan:BAAANQABCggIHQAAAA==.',
Lo='Loerasdh:BAABNQAECn8eAAIJAAgK3CVICgBeAwAJAAgK3CVICgBeAwAAAA==.Loko:BAACNQAFFH8TAAIYAAcK1hRhCQDpAQAYAAcK1hRhCQDpAQA1AAQKf0EAAhgACgr/JM4DAE8DABgACgr/JM4DAE8DAAAA.Looio:BAAANQADCgIIAgAAAA==.',
Lu='Lucien:BAAANQABCgQIBAAAAA==.Lumièrevide:BAAANQADCggICAAAAA==.Luxxus:BAABNQAECn8dAAIIAAkK9xtcKwC7AgAIAAkK9xtcKwC7AgAAAA==.',
Ly='Lyesx:BAABNQAECn8tAAMHAAoKWSBWFwA9AwAHAAoKWSBWFwA9AwAZAAMKpxSTVwDHAAABNQAFFAcIEgAOAIUOAA==.Lyndsy:BAAANQADCgUIBQAAAA==.Lyri:BAAANQADCgMIAwAAAA==.',
Ma='Macros:BAAANQAECgQICQAAAA==.Mageyousad:BAAANQADCgEIAgAAAA==.Makhtor:BAAANQAECgQIBQAAAA==.Mallaer:BAABNQAECn8tAAIIAAoKKiEyGgALAwAIAAoKKiEyGgALAwAAAA==.Malícíous:BAABNQAECn8wAAISAAkK/RL2dwD7AQASAAkK/RL2dwD7AQAAAA==.Mantakore:BAACNQAFFH8KAAIPAAUKlANMDQD0AAAPAAUKlANMDQD0AAA1AAQKfzYAAg8ACgooFuEVAFcCAA8ACgooFuEVAFcCAAAA.Marcdruid:BAAANQAECgUICQAAAA==.Maubles:BAAANQADCggICAABNQAFFAYIGAAiAFUOAA==.',
Mc='Mcdirk:BAAANQAECggICAAAAA==.',
Me='Menopaws:BAABNQAECn9RAAIQAAoKiCZ5AACPAwAQAAoKiCZ5AACPAwAAAA==.Merdoon:BAAANQADCgEIAQAAAA==.Merrtt:BAAANQAECgYIBgAAAA==.Mertrik:BAABNQAECn8eAAMWAAkKtiIODQBYAwAWAAkKtiIODQBYAwAGAAMKiBDZ7QC7AAAAAA==.',
Mi='Midk:BAAANQAECgIIAwAAAA==.Mikayy:BAACNQAFFH8RAAIdAAYKUSJaAwAGAgAdAAYKUSJaAwAGAgA1AAQKf0AAAh0ACgpzJv0AAMsDAB0ACgpzJv0AAMsDAAAA.Milenko:BAABNQAECn9JAAIJAAoKZCPbBgAcAwAJAAoKZCPbBgAcAwAAAA==.Milly:BAABNQAECn8XAAIcAAkK3hddfwC5AQAcAAkK3hddfwC5AQABNQAECgoKSQAJAGQjAA==.',
Mo='Molfsongal:BAAANQADCgIIAgAAAA==.Monstrous:BAACNQAFFH8YAAIMAAcKYhNsDQDbAQAMAAcKYhNsDQDbAQA1AAQKf0gAAgwACgo0IJQsAIACAAwACgo0IJQsAIACAAAA.Moocher:BAAANQAECgEIAQAAAA==.Mordecaii:BAAANQADCgYIDgAAAA==.Morgul:BAAANQAECgQIBgAAAA==.Morox:BAABNQAECn8bAAQDAAkKMRv7EQCPAgADAAgKDhz7EQCPAgACAAcKExj6EQCHAQAQAAUKKBf5KgBAAQABNQAFFAgIFQAEAP8PAA==.Mothman:BAAANQAECgUICgAAAA==.Moyana:BAAANQADCgEIAQAAAA==.',
Ms='Msbehaven:BAABNQAECn8vAAISAAgK8AZjngAHAQASAAgK8AZjngAHAQAAAA==.',
Mt='Mthafknfreez:BAABNQAECn8tAAIEAAoK1hpZBACXAgAEAAoK1hpZBACXAgABNQAFFAYICgAdADIFAA==.',
Mu='Muffìns:BAAANQAECgUIBgAAAA==.Musashi:BAABNQAECn8kAAIIAAgKKBosQQBmAgAIAAgKKBosQQBmAgAAAA==.',
My='Mynuturchin:BAABNQAECn8WAAMNAAcK2BZeQwDuAQANAAcK2BZeQwDuAQAgAAEKJApUswAsAAAAAA==.',
Na='Nagy:BAAANQAECgMIAwAAAA==.',
Ni='Night:BAABNQAECn8tAAIFAAkK5BLhtwAUAgAFAAkK5BLhtwAUAgAAAA==.Nightsecho:BAAANQAECgEIAQAAAA==.Nightshris:BAAANQAECgYIBwAAAA==.',
Nn='Nnyx:BAAANQABCgIIAgAAAA==.',
No='Notmehssos:BAAANQAECggIDAAAAA==.Notthechosen:BAABNQAECn8jAAQNAAoKyg/LJwCyAQANAAkKyg/LJwCyAQABAAUKqQunjADyAAAgAAYKEQzhbADTAAABNQAECgoKNgAMANoXAA==.',
Ny='Nymeriã:BAAANQAECgUICAAAAA==.',
Ob='Obzy:BAAANQAECgcIEwAAAA==.Obzz:BAAANQADCgEIAQABNQAECgcIEwAVAAAAAA==.',
Ok='Okamy:BAAANQAECgcIDAABNQAECgQIBQAVAAAAAA==.Oknelim:BAAANQADCggICAABNQAECgoKSQAJAGQjAA==.',
Ol='Olympicjeid:BAABNQAECn8dAAMZAAgK5ROcLgDXAQAZAAgK5ROcLgDXAQAHAAEKCQY7VwE7AAABNQAFFAYIEwAaAIQcAA==.',
Op='Opz:BAACNQAFFH8JAAMhAAMKmwyTCgDYAAAhAAMKmwyTCgDYAAAlAAEK0QcbAwA7AAA1AAQKfzsAAyEACgoXGvsZAH0CACEACgoXGvsZAH0CACUABgqbGN4HADQBAAAA.',
Or='Orghujon:BAAANQADCgMIAwAAAA==.',
Pa='Paladinfive:BAAANQAECgEIAgAAAA==.Parthos:BAAANQAECgQIDQAAAA==.Parts:BAAANQABCgEIAQABNQAECgoKMQAFABEgAA==.',
Pe='Pedro:BAABNQAECn8kAAIcAAkKigwnlgCLAQAcAAkKigwnlgCLAQAAAA==.Perry:BAAANQADCgIIAgAAAA==.',
Ph='Phenomenon:BAAANQAECgUICQABNQAECgkJIAAcAMYkAA==.',
Pi='Pittydafoo:BAAANQAECgIIAgAAAA==.',
Pk='Pkunkk:BAAANQAECgcICwAAAA==.',
Pl='Ploxis:BAACNQAFFH8ZAAIKAAcKPhbNAABRAQAKAAcKPhbNAABRAQA1AAQKfyEAAgoACgodG40HAIwCAAoACgodG40HAIwCAAAA.',
Po='Polskashaman:BAABNQAECn8jAAILAAkK9hDNFwDrAQALAAkK9hDNFwDrAQAAAA==.Pookiebonez:BAAANQADCgIIAgABNQAECgYICAAVAAAAAA==.',
Pr='Prea:BAABNQAECn8ZAAMWAAoK9BiDUQAgAgAWAAkKQBmDUQAgAgAGAAEKAAAQQgEtAAAAAA==.Premiumferal:BAABNQAECn8bAAMOAAkKECGiHQCTAgAOAAkKECGiHQCTAgAdAAUKxRj4MAA2AQAAAA==.Primecarry:BAACNQAFFH8WAAIbAAcKbxplBgAIAgAbAAcKbxplBgAIAgA1AAQKfycAAhsACgpNI88JAHoDABsACgpNI88JAHoDAAAA.Prine:BAABNQAECn8nAAIMAAoKgB6+KwANAwAMAAoKgB6+KwANAwABNQAFFAcIFgAbAG8aAA==.',
Pu='Puripuri:BAAANQAECgQIBAAAAA==.',
Qi='Qinkipa:BAAANQAECgEIAQAAAA==.',
Qo='Qovo:BAAANQABCggIDgAAAA==.',
Ra='Ragark:BAAANQADCgUIBQAAAA==.Raigko:BAABNQAECn9EAAIMAAoKDSWpCQCnAwAMAAoKDSWpCQCnAwAAAA==.Rainyday:BAABNQAECn8UAAIWAAYK9ApktwD+AAAWAAYK9ApktwD+AAAAAA==.Raiva:BAABNQAECn8iAAIXAAoKjhCOGADcAQAXAAoKjhCOGADcAQAAAA==.Raivek:BAAANQAECgIIAgAAAA==.Randenton:BAAANQADCgYICAAAAA==.Randezoth:BAAANQABCggIDQABNQADCgYICAAVAAAAAA==.Randomkiller:BAAANQADCgMIAwAAAA==.Rassputen:BAABNQAECn8wAAINAAoK8xS/RwDaAQANAAoK8xS/RwDaAQAAAA==.',
Re='Reck:BAAANQADCgEIAQAAAA==.Redjive:BAAANQAECggIAQAAAA==.Redonkulos:BAAANQADCgMIBAAAAA==.Reliri:BAAANQADCgYICgAAAA==.Renais:BAAANQAECgcIDgAAAA==.Rex:BAABNQAECn8gAAINAAkKGBfyMABNAgANAAkKGBfyMABNAgAAAA==.',
Ri='Rileyesco:BAAANQABCgUIBgAAAA==.Ripskylark:BAAANQAECgIIAwAAAA==.Risk:BAAANQABCgcIEwAAAA==.',
Rj='Rjtheamazin:BAAANQAECgEIAQAAAA==.',
Ro='Roguen:BAACNQAFFH8KAAIdAAYKMgWeCwACAQAdAAYKMgWeCwACAQA1AAQKf1MAAx0ACgqZGR8NAKMCAB0ACgqZGR8NAKMCAA4AAwqGCNKCAKkAAAAA.Romirin:BAAANQADCgQIBAAAAA==.Rotan:BAAANQADCgYICwAAAA==.Roulduke:BAABNQAECn9EAAIGAAoKBA0zRACsAQAGAAoKBA0zRACsAQAAAA==.',
['Rù']='Rùckús:BAABNQAECn8pAAIBAAgKQR/eLgB1AgABAAgKQR/eLgB1AgABNQAECgkJHgAGALEZAA==.',
Sa='Sacredmentos:BAABNQAECn80AAMiAAoKABVZJgCsAQAiAAoKABVZJgCsAQAcAAYKagpw6wD1AAAAAA==.Salaen:BAAANQAECggIAwAAAA==.Sammybeans:BAAANQAFFAIIAwAAAA==.Sapito:BAAANQADCgYICgAAAA==.Saulotsalubr:BAAANQADCgQIBAAAAA==.',
Sc='Scarecrow:BAAANQAECgEIAQABNQAECgoKSQAJAGQjAA==.',
Se='Seceron:BAAANQAECgUIDAAAAA==.Sekai:BAAANQAECgIIAgAAAA==.Sevyns:BAAANQAECgMIBgAAAA==.',
Sg='Sgtslappy:BAAANQADCgMIAwAAAA==.',
Sh='Shamminator:BAAANQAECgEIAQAAAA==.Shanarelle:BAAANQAECgYIEwAAAA==.Shasa:BAACNQAFFH8KAAIHAAQKyxglDwD/AAAHAAQKyxglDwD/AAA1AAQKfycAAgcACgozHrw1AMoCAAcACgozHrw1AMoCAAAA.Shatteredsky:BAABNQAECn8hAAMWAAkKER2AKwC1AgAWAAkKER2AKwC1AgAGAAEKqgOgRQErAAAAAA==.Shazik:BAABNQAECn9VAAIWAAoKZR/iCwBXAwAWAAoKZR/iCwBXAwAAAA==.Shazzik:BAAANQAECgYICgABNQAECgoKVQAWAGUfAA==.Sheroko:BAAANQAECgIICAAAAA==.Sheñanigans:BAABNQAECn8eAAIGAAkKsRnKLwAFAgAGAAkKsRnKLwAFAgAAAA==.Shilbalam:BAAANQAECgUIBQAAAA==.Shirohane:BAAANQAECgYICQAAAA==.Shmoopy:BAAANQAECgEIAQAAAA==.Shmoove:BAAANQADCgEIAQAAAA==.Shnkz:BAAANQAECgEIAQAAAA==.Shotzer:BAAANQADCgMIBgAAAA==.',
Si='Silzo:BAABNQAECn8hAAMNAAoKTB1REQCFAgANAAoKTB1REQCFAgABAAEKuQiAiwApAAABNQAECgoKIgAXAI4QAA==.Sirjames:BAAANQAECgEIAQAAAA==.',
Sk='Skelix:BAACNQAFFH8yAAIWAAkKUiDuAAASAwAWAAkKUiDuAAASAwA1AAQKfy8AAxYACQpLJmMFAJwDABYACQpLJmMFAJwDAAYAAwpVF6baAN8AAAAA.Skunkpaw:BAAANQADCgUIDwAAAA==.Skysong:BAACNQAFFH8VAAQeAAcKQB2SAQA1AQAeAAYKTh+SAQA1AQAmAAEKBxXHDABNAAAPAAEKeAUJGQA+AAA1AAQKfyYABB4ACgpJIYYJANkCAB4ACgpJIYYJANkCAA8AAwp/BaZBAJQAACYAAQrwI8MWAGgAAAAA.',
Sl='Slashedeye:BAABNQAECn9BAAIkAAkKFRSWAgASAgAkAAkKFRSWAgASAgAAAA==.Slimgucci:BAAANQADCggICAAAAA==.',
Sn='Snowfox:BAAANQADCgIIAgAAAA==.Snowynn:BAABNQAECn8gAAMQAAkKfhaFFAAdAgAQAAkKfhaFFAAdAgACAAMKxggGMgCDAAAAAA==.Snubby:BAABNQAECn8cAAMSAAkKtCJFOwCiAgASAAcKmyFFOwCiAgATAAIKcyVYOgDYAAAAAA==.',
So='Solheim:BAAANQABCgUIBQAAAA==.Sonari:BAAANQADCgYIBgAAAA==.',
Sp='Spankz:BAAANQAECgQICQAAAA==.Spathi:BAAANQAFFAIIAwAAAA==.Spicymeatbal:BAAANQABCggIEQAAAA==.',
St='Strathz:BAABNQAECn8iAAMSAAkKfRw0NQC1AgASAAkKMxk0NQC1AgATAAQKahyvKAA0AQAAAA==.Stregobor:BAAANQAECgYIBwABNQAECgoKMQAFABEgAA==.Striker:BAAANQAECgYIBQAAAA==.Strongish:BAAANQADCgUIBQAAAA==.',
Su='Summerset:BAAANQAECgIIAQAAAA==.Sunstrider:BAAANQADCgMIBgAAAA==.Superdonkey:BAAANQADCgYICwABNQAFFAcIFwAaANMWAA==.Sushi:BAAANQADCgIIAgAAAA==.Suva:BAAANQADCgYIBgAAAA==.',
Sy='Sylatis:BAAANQAECgYIDAABNQAFFAYIIAASAOoiAA==.Sylätis:BAAANQAECgMIAwABNQAFFAYIIAASAOoiAA==.',
['Sö']='Söultender:BAAANQADCgMIAwABNQAECgYIDQAVAAAAAA==.',
['Sø']='Sølidus:BAAANQAECgMIDgABNQAFFAcIEwAIAMgbAA==.',
Ta='Taintedhealz:BAAANQADCgEIAQAAAA==.Talys:BAACNQAFFH8eAAIPAAgKAxYcBAA8AgAPAAgKAxYcBAA8AgA1AAQKf0IAAg8ACgrnJCUBAMYDAA8ACgrnJCUBAMYDAAAA.Tankly:BAAANQADCgMIAwAAAA==.',
Te='Tehchosen:BAAANQADCggICAAAAA==.Terramor:BAAANQAECgIIAgAAAA==.Texicola:BAABNQAECn9KAAIEAAoKrh/RAgAvAwAEAAoKrh/RAgAvAwAAAA==.',
Th='Thabdeady:BAAANQAECgYIDQABNQAECgoKRwAeAKUZAA==.Thabk:BAABNQAECn9HAAQeAAoKpRmQBAB8AgAeAAoKpRmQBAB8AgAmAAgKnwt9DgBfAQAPAAYKCQs9LQA7AQAAAA==.Thaelorn:BAAANQADCgEIAQAAAA==.Thesyra:BAABNQAECn8rAAMmAAoK+QzgBwClAQAmAAoK+QzgBwClAQAPAAoKLQj/JwB3AQAAAA==.Thundercrash:BAAANQADCgUIBgAAAA==.Thunderjeed:BAAANQAECgcICgABNQAFFAYIEwAaAIQcAA==.Thurmond:BAABNQAECn8hAAMBAAoKWhtnOwA0AgABAAoKthZnOwA0AgANAAYKBBn9WQCLAQAAAA==.Thurmoons:BAABNQAECn8YAAMYAAoK6Ru2FABkAgAYAAoKzRm2FABkAgAQAAUKJB7cHgCoAQABNQAECgoKIQABAFobAA==.Thurmund:BAAANQADCgYIBgABNQAECgoKIQABAFobAA==.',
Ti='Tiamat:BAAANQADCggICAAAAA==.Tidalanxiety:BAAANQAECgQIBQAAAA==.Tigray:BAAANQADCgYIBgAAAA==.',
To='Toastay:BAAANQAECgQIDwAAAA==.Toastz:BAABNQAECn9HAAIHAAoKXiJuCwCCAwAHAAoKXiJuCwCCAwAAAA==.Toebeanz:BAAANQAECgUIDAAAAA==.Tokken:BAACNQAFFH8ZAAIMAAcKKBMcBwBPAgAMAAcKKBMcBwBPAgA1AAQKfzgAAgwACgoRIWc9ANMCAAwACgoRIWc9ANMCAAAA.Totemi:BAAANQADCgMIAwAAAA==.',
Tr='Treebeast:BAABNQAECn8WAAMGAAkKER+5LQDGAgAGAAkKER+5LQDGAgAWAAEKnQE3KAElAAAAAA==.Troile:BAAANQAECgcIEQAAAA==.Trojen:BAACNQAFFH8IAAIcAAQKVg72GQDYAAAcAAQKVg72GQDYAAA1AAQKfyAAAxwACQp2GpaDACECABwACApyGpaDACECABsACAoYC3J8AKQBAAAA.Trolladin:BAAANQADCgYICgABNQADCggIJQAVAAAAAA==.',
Tw='Twig:BAABNQAECn8nAAMYAAkKGhgyLAB5AgAYAAkKGhgyLAB5AgADAAQKLA+LSgC9AAAAAA==.',
Ty='Tyras:BAABNQAECn8YAAMRAAYKFhAbFgC2AAAaAAUKzQ2GRQDvAAARAAUKFhAbFgC2AAAAAA==.',
Tz='Tzarina:BAAANQABCgYIBgAAAA==.',
['Tâ']='Tâz:BAABNQAECn8yAAMWAAoKix/KKgC4AgAWAAoKix/KKgC4AgAGAAEKAAA0GwEAAAAAAA==.',
Ul='Ulanda:BAABNQAECn9NAAMCAAoKvxfCCgARAgAQAAkKNhQzEQBNAgACAAkKghbCCgARAgAAAA==.',
Um='Umasi:BAACNQAFFH8hAAIiAAgK1CROAAABAwAiAAgK1CROAAABAwA1AAQKfzUAAiIACgqdJrEBAL8DACIACgqdJrEBAL8DAAAA.',
Un='Underbogg:BAAANQADCgUIBQAAAA==.Unus:BAAANQAECgMIBwABNQAECgoKMQAFABEgAA==.',
Ut='Utastebad:BAAANQADCggIDAAAAA==.',
Va='Vagabundo:BAAANQAECgMIAwABNQAECgYICwAVAAAAAA==.Vail:BAAANQADCgUIBgAAAA==.Vainquish:BAAANQADCgEIAQAAAA==.Valamaldoran:BAAANQADCgUIBQAAAA==.Vanthil:BAAANQAECgIIAgAAAA==.Vaporize:BAAANQAECgIIAgAAAA==.',
Ve='Venandi:BAABNQAECn8UAAIFAAgKzAyB4ADIAQAFAAgKzAyB4ADIAQAAAA==.Vengened:BAABNQAECn82AAIMAAoK2hfcVwCEAgAMAAoK2hfcVwCEAgAAAA==.Verax:BAAANQAECgIIAgAAAA==.Verestrasz:BAAANQADCgIIBAAAAA==.',
Vg='Vgly:BAAANQAECgQIEAAAAA==.',
Vi='Vilous:BAABNQAECn81AAIjAAoKQCaHAADVAwAjAAoKQCaHAADVAwAAAA==.',
Vy='Vyisesham:BAABNQAECn81AAMGAAoKKxpNQAB0AgAGAAkKJRlNQAB0AgAWAAkKSBbZYAB+AQAAAA==.',
['Vý']='Výce:BAAANQAECgEIAQAAAA==.',
Wa='Wagtar:BAAANQADCgYICwABNQADCgQIBAAVAAAAAA==.Warzug:BAAANQADCgQIBAAAAA==.',
We='Wesjin:BAABNQAECn8kAAMnAAoKrROWFAAyAgAnAAoKrROWFAAyAgAaAAEKHQM/dgAiAAAAAA==.Wez:BAAANQAECgcICwAAAA==.',
Wh='Whiskee:BAACNQAFFH8JAAICAAMK8RmBAgCZAAACAAMK8RmBAgCZAAA1AAQKfygABAIACgqaIgMFADUDAAIACQqQIQMFADUDABAABwrzIHARAEoCABgAAQp2Ea1/ADsAAAAA.',
Wo='Wooglone:BAAANQAECgQJBAAAAA==.',
Wy='Wyndia:BAABNQAECn8aAAIFAAoK9RshZQC0AgAFAAoK9RshZQC0AgAAAA==.Wyndibear:BAAANQAECgMIAgAAAA==.',
Xa='Xanthos:BAAANQAECgEIAQABNQAECgQIBgAVAAAAAA==.',
Xb='Xbert:BAAANQADCgcIBwAAAA==.',
Xe='Xela:BAAANQAECgMICQABNQAECgoKMQAFABEgAA==.Xenophontes:BAABNQAECn8cAAMEAAoKNR+jGgAeAQAFAAkK8xzKtQAYAgAEAAUKFR2jGgAeAQABNQAFFAcIEwAIAMgbAA==.Xeris:BAAANQADCgEIAQAAAA==.',
Xi='Xihuang:BAABNQAECn9CAAIYAAoKMBlpGQAtAgAYAAoKMBlpGQAtAgABNQAFFAYICgAdADIFAA==.Xiia:BAAANQAECgQIBAAAAA==.',
Xo='Xouu:BAAANQAFFAUIBAABNQAFFAgIBgAWADoRAA==.',
Xx='Xxuu:BAAANQAFFAgIAgABNQAFFAgIBgAWADoRAA==.Xxuusham:BAACNQAFFH8GAAIWAAYKOhFoBwDkAQAWAAYKOhFoBwDkAQA1AAQKf0cAAhYACgrTJSICAMYDABYACgrTJSICAMYDAAAA.Xxuuspr:BAAANQAECggIAgABNQAFFAgIBgAWADoRAA==.',
Ya='Yaoguai:BAABNQAECn9GAAMYAAoKuBsRFgBTAgAYAAoKuBsRFgBTAgAQAAEKHwm6YAAzAAAAAA==.Yasei:BAAANQAECgQIBAAAAA==.Yawgmoth:BAABNQAECn8ZAAQUAAgKzgy/GgCuAAASAAgKwQndsQDcAAAUAAUKDA2/GgCuAAATAAEKFgQthAAmAAABNQAECgkJIQARALcbAA==.',
Za='Zakkha:BAAANQADCgMIAwABNQADCggIEwAVAAAAAA==.Zaleris:BAAANQAECgQIBQAAAA==.Zaryana:BAABNQAECn8ZAAIoAAkK2QP/IQDTAAAoAAkK2QP/IQDTAAAAAA==.',
Ze='Zephon:BAABNQAECn8hAAIHAAoKmQzzlQDcAQAHAAoKmQzzlQDcAQAAAA==.',
Zo='Zotiel:BAAANQAFFAQIBAABNQAFFAgIMQABAPcdAA==.',
Zy='Zynisch:BAAANQADCgcIEwAAAA==.',
['Ær']='Æris:BAAANQADCgMIAwAAAA==.',
['Ìr']='Ìroh:BAAANQADCgUIBgABNQAECgYIDQAVAAAAAA==.',
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
