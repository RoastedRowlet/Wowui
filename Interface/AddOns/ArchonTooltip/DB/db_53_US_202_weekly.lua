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

local lookup = {'DeathKnight-Unholy','Druid-Feral','Druid-Restoration','Mage-Frost','Mage-Arcane','Shaman-Elemental','Hunter-BeastMastery','Priest-Holy','DemonHunter-Havoc','DemonHunter-Vengeance','Shaman-Enhancement','Warrior-Arms','Warrior-Protection','DeathKnight-Blood','Rogue-Assassination','Evoker-Preservation','Druid-Guardian','Monk-Brewmaster','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Unknown-Unknown','Shaman-Restoration','DemonHunter-Devourer','Druid-Balance','Hunter-Marksmanship','Monk-Windwalker','Paladin-Holy','Paladin-Retribution','Hunter-Survival','Rogue-Subtlety','Evoker-Devastation','Rogue-Outlaw','DeathKnight-Frost','Priest-Shadow','Paladin-Protection','Warrior-Fury','Mage-Fire','Priest-Discipline','Evoker-Augmentation','Monk-Mistweaver',}
local provider = {region='US',realm='Spirestone',name='US',type='weekly',zone=53,date='2026-11-17',data={Ab='Abduon:BAAANQADCgcICwAAAA==.',
Ac='Aciddeath:BAAANQAECgEIAQABNQAFFAUIFQABAP8RAA==.',
Ad='Admaris:BAACNQAFFH8JAAMCAAIKbRFkAwCaAAACAAIKbRFkAwCaAAADAAIKMhpzEQCKAAA1AAQKfzsAAwMACgp1IPwMAP8CAAMACgp1IPwMAP8CAAIABwqQIdIJAKMCAAAA.',
Ae='Aelis:BAAANQABCgEIAQAAAA==.',
Ag='Agni:BAACNQAFFH8VAAMEAAgK/w9RAwDrAAAFAAUKwwuiJwBLAQAEAAMKOxRRAwDrAAA1AAQKfzUAAwUACgqSJDhLAOsCAAUACgqTIzhLAOsCAAQAAwrsI6YYABwBAAAA.',
Ak='Akkadian:BAAANQADCggICwAAAA==.',
Al='Almight:BAAANQADCgcICgAAAA==.Alnasham:BAACNQAFFH8UAAIGAAgK1Bc4BADrAQAGAAgK1Bc4BADrAQA1AAQKfzIAAgYACgoTIoUUAE4DAAYACgoTIoUUAE4DAAAA.Alnava:BAAANQAECgcIDwAAAA==.Altria:BAAANQAECgIIAQAAAA==.Alvoka:BAABNQAECn8VAAIFAAcKLRbv0QDiAQAFAAcKLRbv0QDiAQAAAA==.',
Am='Amarillos:BAABNQAECn8fAAIHAAkKbxQqYwBPAgAHAAkKbxQqYwBPAgAAAA==.Amarillys:BAABNQAECn88AAIIAAoK4CBHDwBhAwAIAAoK4CBHDwBhAwAAAA==.Ammutseba:BAABNQAECn8oAAMJAAoK0hmRHgAXAgAJAAoKlxmRHgAXAgAKAAMK2hZFIgCwAAAAAA==.',
An='Anfall:BAACNQAFFH8XAAILAAcK8Q6IAQBxAQALAAcK8Q6IAQBxAQA1AAQKfz0AAgsACgoxIksIAPUCAAsACgoxIksIAPUCAAAA.Angermeier:BAABNQAECn9GAAMMAAoKQBbbTAAZAgAMAAoKmxXbTAAZAgANAAEK/hySOgBVAAAAAA==.Angers:BAAANQAECgIIAgABNQAECgoKRgAMAEAWAA==.Angrylady:BAAANQAECgEIAQAAAA==.Anjuna:BAAANQADCgUIBQAAAA==.Anohru:BAAANQAECggIDQAAAA==.Ante:BAAANQADCgUIBQAAAA==.Anthos:BAAANQAECggIDQAAAA==.Antikreist:BAAANQADCgUIBQAAAA==.Anyawnka:BAAANQABCggIGgAAAA==.',
Ap='Aphotic:BAAANQAECgMIAQAAAA==.',
Ar='Arcady:BAAANQADCgYIBgAAAA==.Ards:BAAANQADCgIIAwAAAA==.Armanite:BAAANQAECgQIBQABNQAECgoKIQABAFobAA==.Arowin:BAAANQAECggIEAAAAA==.Arthaniis:BAABNQAECn8YAAIGAAcKKCESSwBKAgAGAAcKKCESSwBKAgAAAA==.',
As='Asystoli:BAABNQAECn8vAAMFAAoKtxYmgwCjAQAFAAkKyBcmgwCjAQAEAAIKQw+KPgA6AAAAAA==.',
At='Atheria:BAAANQADCgYICAAAAA==.Attackheli:BAAANQAECgQIDwAAAA==.',
Au='Audideath:BAAANQAECgUICQAAAA==.Auurdeath:BAAANQADCggIEwAAAA==.',
Av='Av:BAAANQADCgIIBQAAAA==.',
Aw='Aw:BAACNQAFFH8dAAIJAAgKlh2qAwBFAgAJAAgKlh2qAwBFAgA1AAQKfyoAAgkACgoKJvQFAJYDAAkACgoKJvQFAJYDAAAA.',
Ax='Ax:BAECNQAFFH8TAAMBAAgKbBOsBwCeAQABAAcKbBOsBwCeAQAOAAEKAADZOQAfAAA1AAQKfywAAgEACgqJIzIkALECAAEACgqJIzIkALECAAAA.',
Az='Azzazinzblo:BAAANQADCgUIBQAAAA==.',
['Aÿ']='Aÿa:BAAANQAECgUIDgAAAA==.',
Ba='Baast:BAAANQADCgUIBQAAAA==.Bamph:BAAANQAECggIDQAAAA==.Bangbang:BAAANQAECgcIDwAAAA==.Batez:BAAANQAECgQIBAABNQAFFAcIEgAPAIUOAA==.',
Bd='Bdk:BAABNQAECn8UAAIOAAkKuR2rGQDgAgAOAAkKuR2rGQDgAgAAAA==.Bdog:BAAANQAECgEIAwAAAA==.',
Be='Beeatinu:BAAANQAECgMIAwAAAA==.Beers:BAAANQAECggIBwAAAA==.Beledros:BAABNQAECn8cAAIQAAkKVBP4FQBWAgAQAAkKVBP4FQBWAgAAAA==.Beni:BAABNQAECn9bAAMRAAoKBCQiAwA/AwARAAoKBCQiAwA/AwACAAgKaxv/CgApAgAAAA==.Benson:BAABNQAECn8hAAISAAkKoxwsCACuAgASAAkKoxwsCACuAgAAAA==.Bensonadin:BAAANQAECgYIBgAAAA==.Berd:BAAANQAECggIBgAAAA==.',
Bi='Bigwillybob:BAAANQADCgIIAgAAAA==.Billiegoat:BAAANQAECggIAgAAAA==.Bina:BAAANQAECgQIBQAAAA==.Birblock:BAACNQAFFH8gAAQTAAYK6iKNAgBqAgATAAYK6iKNAgBqAgAUAAIKygE5EwB6AAAVAAEK/BkXCABiAAA1AAQKfyMABBMACQotJiYzALwCABMABwo1JiYzALwCABQABwq3GxUUAM8BABUAAQoAAFYpAEcAAAAA.',
Bo='Bobbo:BAAANQADCgYJBwAAAA==.',
Br='Brek:BAAANQAECgYIDAAAAA==.Brewtherguy:BAABNQAECn8iAAISAAkKAB1oBwDGAgASAAkKAB1oBwDGAgAAAA==.Brother:BAAANQADCgIIAgAAAA==.Bruceshepard:BAAANQADCgQICQABNQAECgUIDQAWAAAAAA==.Brutebuffalo:BAABNQAECn8lAAMXAAkKqh2uIwDYAgAXAAkKqh2uIwDYAgAGAAUKQBH/rQA3AQAAAA==.Bruteflappy:BAAANQADCggICAABNQAECgkJJQAXAKodAA==.Brutetestify:BAAANQADCggICAABNQAECgkJJQAXAKodAA==.',
Bu='Bubbleboi:BAAANQADCgYICAAAAA==.Bubblebôy:BAAANQAECgIIAgAAAA==.Bublz:BAABNQAECn8lAAIIAAoKohX2NQBmAgAIAAoKohX2NQBmAgAAAA==.',
['Bâ']='Bâra:BAABNQAECn8eAAIBAAoKahqhJQCoAgABAAoKahqhJQCoAgAAAA==.',
Ca='Camdreya:BAAANQABCgEIAQAAAA==.Carnal:BAAANQAECgYIBQAAAA==.Castro:BAAANQAECgIIAgAAAA==.',
Ce='Cedren:BAACNQAFFH8MAAIJAAYKsQugDgAfAQAJAAYKsQugDgAfAQA1AAQKfzYAAwkACgpCHVoeABkCAAkACgpFHFoeABkCABgACAotE7srAOQBAAAA.Ceewhya:BAAANQAECgEIAQAAAA==.Celestika:BAAANQABCgIIAgAAAA==.Cerari:BAAANQAECgEJAQAAAA==.',
Ch='Chalix:BAAANQAECgMIBQAAAA==.Chama:BAABNQAECn8aAAIYAAkKpxI0JAAmAgAYAAkKpxI0JAAmAgAAAA==.Cheapheal:BAABNQAECn9GAAMRAAoKNCDzBABSAwARAAoKNCDzBABSAwAZAAEKAACDogAAAAAAAA==.Cheapsnipe:BAABNQAECn8aAAMHAAoKhxbsQABTAgAHAAoKhxbsQABTAgAaAAUKFghGNgDKAAABNQAECgoKRgARADQgAA==.Cheburashka:BAACNQAFFH8aAAIGAAgKGCKrBABIAgAGAAgKGCKrBABIAgA1AAQKfyIAAgYACgpbIakoAN8CAAYACgpbIakoAN8CAAAA.Chimerabob:BAAANQAECgMIBwAAAA==.Chispaa:BAAANQADCgEIAQAAAA==.Chopsuey:BAAANQAECggIBAAAAA==.Chunkymonkey:BAACNQAFFH8XAAIbAAcK0xa7BADwAQAbAAcK0xa7BADwAQA1AAQKf0QAAhsACgrYI7sDAD0DABsACgrYI7sDAD0DAAAA.',
Ci='Cidren:BAAANQAECgEIAQAAAA==.',
Cl='Clappncheeks:BAABNQAECn8hAAIHAAoK+BhwUgAoAgAHAAoK+BhwUgAoAgAAAA==.Claudefrollo:BAABNQAECn8qAAIZAAoKFgzNNgBcAQAZAAoKFgzNNgBcAQAAAA==.',
Cr='Crankyelf:BAAANQABCgEIAQAAAA==.Crimsa:BAABNQAECn9QAAIVAAoK0QabDAB1AQAVAAoK0QabDAB1AQAAAA==.Crimsonaxel:BAABNQAECn8qAAIGAAoK1xmwOwCHAgAGAAoK1xmwOwCHAgAAAA==.Cryogen:BAAANQAECgQJCAAAAA==.',
Cu='Cursewords:BAAANQADCgUIBQABNQAECgYIBgAWAAAAAA==.',
Da='Daemonproph:BAAANQADCgYIDAAAAA==.Dakini:BAABNQAECn85AAIcAAoKUh/HGgDiAgAcAAoKUh/HGgDiAgAAAA==.Dam:BAAANQADCgUIBQABNQAECgkJIAAOABgXAA==.Dangerruss:BAAANQAECgYICQAAAA==.Darkspartan:BAAANQAECgcIBwAAAA==.Dashytash:BAABNQAECn86AAIKAAoK2h17BACUAgAKAAoK2h17BACUAgAAAA==.Dawnsoul:BAAANQAECgYIDQAAAA==.Daxos:BAAANQADCgcIDQAAAA==.',
De='Deadcowmeat:BAAANQAECggICAAAAA==.Deathschosen:BAAANQADCgQIBAAAAA==.Deiza:BAAANQAECgMIAQAAAA==.Demb:BAAANQAECgQIBwAAAA==.Demonicchoas:BAABNQAECn8yAAMUAAoKmx/MDAArAgATAAkKpx6tWwBEAgAUAAcKfhzMDAArAgAAAA==.Denagorn:BAACNQAFFH8FAAIdAAQKaB0cEAADAQAdAAQKaB0cEAADAQA1AAQKf0IAAh0ACgrNJB4RAIQDAB0ACgrNJB4RAIQDAAE1AAUUCQk0AAEAWB0A.Denaki:BAAANQAECgQIBAABNQAFFAkJNAABAFgdAA==.Denhunt:BAABNQAECn8nAAQHAAoKtCAHIgAPAwAHAAoKpyAHIgAPAwAaAAQKLRmsNwDDAAAeAAIK0RpcDgCqAAABNQAFFAkJNAABAFgdAA==.Dentsama:BAAANQAECggIDgABNQAFFAkJNAABAFgdAA==.Deplete:BAAANQADCgIJAgABNQAECgoKRgAZALgbAA==.Deutzfr:BAABNQAECn8YAAIKAAkKfxwZBwCfAgAKAAkKfxwZBwCfAgAAAA==.Devos:BAABNQAECn8YAAMGAAcKgBMrcgDKAQAGAAcKgBMrcgDKAQAXAAQKRQ6X1gC6AAABNQAFFAUICQAGAIcEAA==.',
Di='Dizzleman:BAAANQAECggICgAAAA==.',
Do='Dominant:BAABNQAECn8zAAMFAAoKHyALWQDOAgAFAAoKHyALWQDOAgAEAAEKAAA5SgAxAAAAAA==.',
Dp='Dpssos:BAAANQAECggIDgAAAA==.',
Dr='Draco:BAAANQADCgcIBwAAAA==.Drag:BAAANQADCgYICAAAAA==.Drbob:BAAANQADCgIIAgAAAA==.Dreadmar:BAAANQADCgYICAAAAA==.Drock:BAABNQAECn9CAAIYAAoKzCAqCABQAwAYAAoKzCAqCABQAwAAAA==.Druidgale:BAAANQAECgIIAwAAAA==.Drybonez:BAAANQAECgYICAAAAA==.Drygth:BAAANQADCgMIBgABNQAECgoKMQAfABEiAA==.Dräkarnoir:BAAANQADCggICAAAAA==.',
Dt='Dtb:BAACNQAFFH8XAAIOAAYKZh8UCADgAQAOAAYKZh8UCADgAQA1AAQKfzoAAg4ACgp4JeYEAKMDAA4ACgp4JeYEAKMDAAAA.',
Du='Dushimaya:BAABNQAECn8+AAIcAAoKAiSOBwCOAwAcAAoKAiSOBwCOAwAAAA==.',
Dv='Dvil:BAAANQAECgQIBQABNQAECgoKQgAYAMwgAA==.',
Dw='Dwyndi:BAAANQAECgYICAAAAA==.',
Ei='Eisador:BAABNQAECn8VAAIHAAcKWAtIqAC1AQAHAAcKWAtIqAC1AQAAAA==.',
El='Elsen:BAAANQAECgUIDQAAAA==.Elsha:BAABNQAECn8hAAISAAkKtxtdCACmAgASAAkKtxtdCACmAgAAAA==.',
Em='Emp:BAAANQAECgUIBgAAAA==.',
Er='Erilee:BAAANQAECgYICgAAAA==.',
Ev='Evelira:BAABNQAFFH8UAAIIAAgKdBq+BwARAgAIAAgKdBq+BwARAgAAAA==.',
Ey='Eyja:BAAANQADCgEIAgAAAA==.',
Ez='Ezailas:BAAANQAECgQIBQAAAA==.Ezpzndaheezy:BAAANQAECgQIBAABNQAECgoKSAAgAG0aAA==.',
Fa='Fatherangus:BAAANQAECggICAAAAA==.Fathercoast:BAAANQAECgYICwAAAA==.',
Fe='Fearful:BAACNQAFFH8FAAIcAAMKYAJkGwC+AAAcAAMKYAJkGwC+AAA1AAQKfyIAAhwACQr5Ff5GAEoCABwACQr5Ff5GAEoCAAAA.Felstrider:BAAANQADCgUIBQAAAA==.Ferador:BAACNQAFFH8ZAAMHAAcKPhSNEABUAQAHAAUKgxWNEABUAQAaAAUKDQ8gDwBMAQA1AAQKfykAAwcACgqVH+xDAJ8CAAcACgqVH+xDAJ8CABoABgq+Ero/AFUBAAAA.Feythe:BAACNQAFFH80AAIOAAoKlxK6AgBWAgAOAAoKlxK6AgBWAgA1AAQKfxgAAg4ACgreFxQ5ACICAA4ACgreFxQ5ACICAAAA.',
Fi='Figgleslock:BAAANQADCgUIBQAAAA==.',
Fl='Flakester:BAABNQAECn8pAAIIAAcKLiORNwCKAgAIAAcKLiORNwCKAgAAAA==.Fleebly:BAABNQAECn8iAAIYAAoKiBnXGQCLAgAYAAoKiBnXGQCLAgAAAA==.',
Fn='Fndruid:BAAANQAECgIIAgAAAA==.',
Fo='Fourbees:BAABNQAECn8wAAIdAAoKFQ2RlgCfAQAdAAoKFQ2RlgCfAQAAAA==.',
Fu='Fursure:BAAANQAECgMIAwAAAA==.',
Ga='Garfal:BAAANQAECgIIAwAAAA==.Gather:BAAANQABCgQIBAABNQAECgoKVQAXAGUfAA==.Gaurhoth:BAAANQAECgQIBAABNQAECgQIBgAWAAAAAA==.',
Ge='Gerissa:BAAANQAECgEIAQAAAA==.',
Gi='Gilgamesh:BAAANQAECggIDQAAAA==.',
Go='Gorobob:BAAANQAECgIIBgAAAA==.',
Gr='Graygkl:BAAANQAECgUIDwAAAA==.Greshanwise:BAABNQAECn8nAAIDAAoKSgoRMwBZAQADAAoKSgoRMwBZAQAAAA==.Grimreaper:BAABNQAECn86AAIhAAoKjxmSBQCPAgAhAAoKjxmSBQCPAgAAAA==.Groag:BAABNQAECn8xAAMfAAoKESKbBQAtAwAfAAoKCyKbBQAtAwAPAAgKYxuJKgBBAgAAAA==.',
Ha='Haarp:BAABNQAECn8WAAIGAAkK6xinYwBbAQAGAAkK6xinYwBbAQAAAA==.Haelar:BAAANQAECgEIAQAAAA==.Hakü:BAAANQAECgcIBwAAAA==.Hammered:BAABNQAECn8jAAIdAAkKxiTuIwDRAgAdAAkKxiTuIwDRAgAAAA==.Haonao:BAAANQAECgcICAABNQAECgoKLwAFALcWAA==.Hardwire:BAAANQAECgEIAQAAAA==.',
He='Heartred:BAAANQADCgYIBgAAAA==.Heifer:BAACNQAFFH8FAAIZAAIKWw3nIQCEAAAZAAIKWw3nIQCEAAA1AAQKfyQAAhkACQrRIZcZAPsCABkACQrRIZcZAPsCAAAA.Hemophilia:BAABNQAECn85AAIBAAoKoBKxHgDsAQABAAoKoBKxHgDsAQAAAA==.Heydk:BAABNQAECn8YAAMiAAkKlRuZWgA/AQAiAAUKRhqZWgA/AQABAAYKHBtBfgAjAQAAAA==.Heydruid:BAAANQAECgcIDQABNQAECgkJGAAiAJUbAA==.',
Ho='Hollowshädix:BAAANQAECgEIAQAAAA==.Holyanxiety:BAAANQADCgYIBgAAAA==.Holydave:BAAANQAECgMIBAAAAA==.Holymentos:BAABNQAECn8sAAMjAAoKIQ6mIgBxAQAjAAkKpAumIgBxAQAIAAcKhQQwygDDAAABNQAECgoKNAAkAAAVAA==.Hottsauce:BAABNQAECn8cAAILAAkKQBwwDQCbAgALAAkKQBwwDQCbAgAAAA==.Hottsaucefel:BAAANQAECgYIBgAAAA==.',
Hu='Hundard:BAAANQADCgIIAgAAAA==.Huntersmarc:BAAANQAECgIIBQAAAA==.Hushhides:BAABNQAECn8iAAMPAAoKEhO4DQDuAQAfAAkK8g2CGAAYAgAPAAkKYBK4DQDuAQAAAA==.Hushrage:BAAANQAECggICwABNQAECgoKIgAPABITAA==.Hushwing:BAAANQAECggICwABNQAECgoKIgAPABITAA==.',
Ia='Iamachick:BAAANQAECgEIAQAAAA==.',
Ib='Ibetrollinya:BAABNQAECn8YAAICAAoK6iMZBADyAgACAAoK6iMZBADyAgABNQAECgoKNQAlAEAmAA==.Iblisshaytan:BAACNQAFFH8GAAIJAAIKfwenFwBvAAAJAAIKfwenFwBvAAA1AAQKf1MAAgkACgrSHaYXAFsCAAkACgrSHaYXAFsCAAE1AAUUBggKAB8AMgUA.Ibtrollin:BAAANQADCggIJQAAAA==.',
Ig='Ignacious:BAAANQAECgEIAQAAAA==.',
Il='Illumina:BAACNQAFFH8JAAIkAAUKQxZ3BgDSAAAkAAUKQxZ3BgDSAAA1AAQKfzEAAiQACQpgIpkIABQDACQACQpgIpkIABQDAAAA.',
Io='Ionissa:BAABNQAECn8wAAIHAAoKTx38LwDdAgAHAAoKTx38LwDdAgAAAA==.',
Ir='Ironbreaker:BAAANQAECgYIDgAAAA==.',
Is='Ischia:BAACNQAFFH8JAAMIAAQK5wgCGwATAQAIAAQK5wgCGwATAQAjAAEKbAEPGwA0AAA1AAQKf0kAAwgACQo0HPU2AIwCAAgACQo0HPU2AIwCACMAAgrUE55pAFsAAAAA.',
Ja='Jallypally:BAAANQADCgIIAgAAAA==.Jarl:BAAANQADCgYICwAAAA==.',
Jc='Jch:BAACNQAFFH8gAAIHAAgKzxxiAQCCAgAHAAgKzxxiAQCCAgA1AAQKfz8AAwcACgq0Jc8LAC8DAAcACgq0Jc8LAC8DABoAAQpkFhCGADgAAAAA.',
Je='Jeay:BAAANQAECgEJAQAAAA==.Jedijeed:BAACNQAFFH8UAAIbAAYKhBysBACPAQAbAAYKhBysBACPAQA1AAQKfz8AAhsACgreI0oGAGwDABsACgreI0oGAGwDAAAA.Jedikepjr:BAACNQAFFH8GAAIdAAMKZQmRGwDLAAAdAAMKZQmRGwDLAAA1AAQKfyQAAh0ACgpdIwQqALkCAB0ACgpdIwQqALkCAAE1AAUUBggUABsAhBwA.Jenova:BAAANQADCgUIBwAAAA==.Jepage:BAABNQAECn9FAAQEAAoKuiDFAwC/AgAEAAoKuiDFAwC/AgAmAAcKXhmzAwB1AQAFAAYK7RPAHAFcAQAAAA==.Jess:BAAANQABCgIIAgAAAA==.',
Jo='Jolyne:BAAANQAECgcIBgAAAA==.Joyful:BAAANQAECgQIBAAAAA==.',
Jp='Jprottsoo:BAABNQAECn8gAAIZAAgKqh7oIgC4AgAZAAgKqh7oIgC4AgAAAA==.',
Ju='Jubei:BAABNQAECn8mAAIlAAoKMA7uDQDUAQAlAAoKMA7uDQDUAQAAAA==.',
Ka='Kagayaki:BAABNQAECn8ZAAMcAAoKXBQULgBrAgAcAAoKXBQULgBrAgAkAAEKWQpQaAAuAAABNQAECgoKLwAFALcWAA==.Kalmya:BAABNQAECn8nAAMDAAgKpQ0YMACaAQADAAgKpQ0YMACaAQACAAEKAAAhRgAuAAAAAA==.Kalrath:BAAANQAECgIIAgABNQAECgoKIQABAFobAA==.Kartam:BAAANQADCggIEAAAAA==.Kasheek:BAAANQADCggICAAAAA==.',
Ke='Keizzer:BAAANQAECgcICwABNQAECgkJHQAIAPcbAA==.Keshisaru:BAAANQADCgQIBAAAAA==.',
Kh='Khazra:BAAANQAECgMIBgAAAA==.',
Ki='Kierràalexis:BAAANQADCgYIBgAAAA==.',
Kl='Klunder:BAABNQAECn9AAAIXAAoKPyOfDgBJAwAXAAoKPyOfDgBJAwAAAA==.',
Ko='Korris:BAABNQAECn8wAAMHAAoKyiClMADaAgAHAAoKyiClMADaAgAaAAEK1wLwnAAiAAAAAA==.Kostik:BAAANQADCgUIBQAAAA==.',
Kr='Kridillis:BAABNQAECn8vAAIJAAoKNR6ZHAC1AgAJAAoKNR6ZHAC1AgAAAA==.',
Kt='Ktang:BAAANQAFFAEIAQAAAA==.',
Ky='Kybinc:BAAANQADCgQIBAAAAA==.',
['Kí']='Kírã:BAAANQABCgIIBAAAAA==.',
La='Lawls:BAAANQADCgQIBwAAAA==.Lazybigger:BAAANQAECgIIAgAAAA==.Lazycow:BAACNQAFFH8GAAIRAAMKxwkTCABnAAARAAMKxwkTCABnAAA1AAQKf0AAAhEACgr1F+4VAOQBABEACgr1F+4VAOQBAAAA.Lazyfrost:BAABNQAECn8tAAIFAAoKQxCdmwBJAgAFAAoKQxCdmwBJAgAAAA==.',
Le='Lethò:BAABNQAECn8xAAMcAAoKFyO0CACDAwAcAAoKFyO0CACDAwAdAAcKRxmtwgBOAQAAAA==.Lethô:BAAANQAECgYIDwAAAA==.Lethö:BAAANQAECgIIBQAAAA==.',
Li='Liesx:BAACNQAFFH8SAAMPAAcKhQ5JBQDfAQAPAAYKIw1JBQDfAQAfAAcKOAloCwBZAQA1AAQKfywAAw8ACgrbIbwUANUCAA8ACArtHrwUANUCAB8ACgq/HJgcAKECAAAA.Lilzarthe:BAAANQAECgYIDgAAAA==.Lindsybowhan:BAAANQABCggIHQAAAA==.',
Lo='Loerasdh:BAABNQAECn8eAAIJAAgK3CVICgBeAwAJAAgK3CVICgBeAwAAAA==.Loko:BAACNQAFFH8UAAIZAAgK5BRhCQDpAQAZAAgK5BRhCQDpAQA1AAQKf0gAAhkACgr/JEIEAE0DABkACgr/JEIEAE0DAAAA.Looio:BAAANQADCgIIAgAAAA==.',
Lu='Lucien:BAAANQABCgQIBAAAAA==.Lumièrevide:BAAANQADCggICAAAAA==.Luxxus:BAABNQAECn8dAAIIAAkK9xtcKwC7AgAIAAkK9xtcKwC7AgAAAA==.',
Ly='Lyesx:BAABNQAECn8tAAMHAAoKWSBWFwA9AwAHAAoKWSBWFwA9AwAaAAMKpxSTVwDHAAABNQAFFAcIEgAPAIUOAA==.Lyndsy:BAAANQADCgUIBQAAAA==.Lyri:BAAANQADCgMIAwAAAA==.',
Ma='Macros:BAAANQAECgQICQAAAA==.Mageyousad:BAAANQADCgEIAgAAAA==.Makhtor:BAAANQAECgQIBQAAAA==.Mallaer:BAABNQAECn8tAAIIAAoKKiEyGgALAwAIAAoKKiEyGgALAwAAAA==.Malícíous:BAABNQAECn8wAAITAAkK/RL2dwD7AQATAAkK/RL2dwD7AQAAAA==.Mantakore:BAACNQAFFH8KAAIQAAUKlAPqDgDxAAAQAAUKlAPqDgDxAAA1AAQKfzcAAhAACgooFuEVAFcCABAACgooFuEVAFcCAAAA.Marcdruid:BAAANQAECgUICQAAAA==.Maubles:BAAANQADCggICAABNQAFFAYIGAAkAFUOAA==.',
Mc='Mcdirk:BAAANQAECggICAAAAA==.',
Me='Menopaws:BAABNQAECn9RAAIRAAoKiCaBAACPAwARAAoKiCaBAACPAwAAAA==.Merdoon:BAAANQADCgEIAQAAAA==.Merrtt:BAAANQAECgYIBgAAAA==.Mertrik:BAABNQAECn8eAAMXAAkKtiIODQBYAwAXAAkKtiIODQBYAwAGAAMKiBDZ7QC7AAAAAA==.',
Mi='Midk:BAAANQAECgIIAwAAAA==.Mikayy:BAACNQAFFH8RAAIfAAYKUSJaAwAGAgAfAAYKUSJaAwAGAgA1AAQKf0AAAh8ACgpzJv0AAMsDAB8ACgpzJv0AAMsDAAAA.Milenko:BAABNQAECn9NAAIJAAoKZCOuBwAYAwAJAAoKZCOuBwAYAwAAAA==.Mileycypress:BAAANQABCgQIBAAAAA==.Milly:BAABNQAECn8XAAIdAAkK3hczjACzAQAdAAkK3hczjACzAQABNQAECgoKTQAJAGQjAA==.',
Mo='Molfsongal:BAAANQADCgIIAgAAAA==.Monstrous:BAACNQAFFH8ZAAIMAAgKgxIrCgC4AQAMAAgKgxIrCgC4AQA1AAQKf0gAAgwACgo0IPcwAHsCAAwACgo0IPcwAHsCAAAA.Moocher:BAAANQAECgEIAQAAAA==.Mordecaii:BAAANQADCgYIDgAAAA==.Morgul:BAAANQAECgQIBgAAAA==.Morox:BAABNQAECn8hAAQDAAkKeh36DwDHAgADAAgKoB76DwDHAgACAAcKExiAFACFAQARAAUKKBf5KgBAAQABNQAFFAgIFQAEAP8PAA==.Mothman:BAAANQAECgUICgAAAA==.Moyana:BAAANQADCgEIAQAAAA==.',
Ms='Msbehaven:BAABNQAECn8vAAITAAgK8AZXvQBSAQATAAgK8AZXvQBSAQAAAA==.',
Mt='Mthafknfreez:BAABNQAECn8zAAIEAAoK/Bs0BACwAgAEAAoK/Bs0BACwAgABNQAFFAYICgAfADIFAA==.',
Mu='Muffìns:BAAANQAECgUIBgAAAA==.Musashi:BAABNQAECn8kAAIIAAgKKBosQQBmAgAIAAgKKBosQQBmAgAAAA==.',
My='Mynuturchin:BAABNQAECn8WAAMOAAcK2BZeQwDuAQAOAAcK2BZeQwDuAQAiAAEKJApUswAsAAAAAA==.',
Na='Nagy:BAAANQAECgMIAwAAAA==.',
Ni='Night:BAABNQAECn8tAAIFAAkK5BLhtwAUAgAFAAkK5BLhtwAUAgAAAA==.Nightsecho:BAAANQAECgMIAQAAAA==.Nightshris:BAAANQAECgYIBwAAAA==.',
Nn='Nnyx:BAAANQABCgIIAgAAAA==.',
No='Notmehssos:BAAANQAECggIDAAAAA==.Notthechosen:BAABNQAECn8sAAQOAAoKLRBlKQC2AQAOAAkKLRBlKQC2AQABAAUKqQunjADyAAAiAAYKEQzxcwDTAAABNQAECgoKOQAMAJ4YAA==.',
Ny='Nymeriã:BAAANQAECgUICAAAAA==.',
Ob='Obzy:BAAANQAECgcIEwAAAA==.Obzz:BAAANQADCgEIAQABNQAECgcIEwAWAAAAAA==.',
Ok='Okamy:BAAANQAECgcIDAABNQAECgQIBQAWAAAAAA==.Oknelim:BAAANQADCggICAABNQAECgoKTQAJAGQjAA==.',
Ol='Olympicjeid:BAABNQAECn8dAAMaAAgK5ROcLgDXAQAaAAgK5ROcLgDXAQAHAAEKCQY7VwE7AAABNQAFFAYIFAAbAIQcAA==.',
Op='Opz:BAACNQAFFH8KAAMjAAMKmwz1CwDYAAAjAAMKmwz1CwDYAAAnAAEK0QdZAwA7AAA1AAQKfz8AAyMACgrpGvsZAH0CACMACgrpGvsZAH0CACcABgqbGFkIADYBAAAA.',
Or='Orghujon:BAAANQADCgMIAwAAAA==.',
Pa='Paladinfive:BAAANQAECgEIAgAAAA==.Parthos:BAAANQAECgQIDQAAAA==.Parts:BAAANQAECgEIAQABNQAECgoKMwAFAB8gAA==.',
Pe='Pedro:BAABNQAECn8mAAIdAAoKgAzTigC2AQAdAAoKgAzTigC2AQAAAA==.Perry:BAAANQADCgIIAgAAAA==.',
Ph='Phenomenon:BAAANQAECgUICQABNQAECgkJIwAdAMYkAA==.',
Pi='Pittydafoo:BAAANQAECgIIAgAAAA==.',
Pk='Pkunkk:BAAANQAECgcICwAAAA==.',
Pl='Ploxis:BAACNQAFFH8bAAIKAAgKaxSqAACLAQAKAAgKaxSqAACLAQA1AAQKfyEAAgoACgodG40HAIwCAAoACgodG40HAIwCAAAA.',
Po='Polskashaman:BAABNQAECn8lAAILAAoKyBDNFwDrAQALAAoKyBDNFwDrAQAAAA==.Pookiebonez:BAAANQADCgIIAgABNQAECgYICAAWAAAAAA==.',
Pr='Prea:BAABNQAECn8ZAAMXAAoK9BiDUQAgAgAXAAkKQBmDUQAgAgAGAAEKAAAQQgEtAAAAAA==.Premiumferal:BAABNQAECn8bAAMPAAkKECGiHQCTAgAPAAkKECGiHQCTAgAfAAUKxRj4MAA2AQAAAA==.Primecarry:BAACNQAFFH8YAAIcAAgKmxllBgAIAgAcAAgKmxllBgAIAgA1AAQKfycAAhwACgpNI88JAHoDABwACgpNI88JAHoDAAAA.Prine:BAABNQAECn8nAAIMAAoKgB6+KwANAwAMAAoKgB6+KwANAwABNQAFFAgIGAAcAJsZAA==.',
Pu='Puripuri:BAAANQAECgQIBAAAAA==.',
Qi='Qinkipa:BAAANQAECgEIAQAAAA==.',
Qo='Qovo:BAAANQABCggIDgAAAA==.',
Ra='Ragark:BAAANQADCgUIBQAAAA==.Raigko:BAABNQAECn9GAAIMAAoKdSWpCQCnAwAMAAoKdSWpCQCnAwAAAA==.Rainyday:BAABNQAECn8UAAIXAAYK9ApktwD+AAAXAAYK9ApktwD+AAAAAA==.Raiva:BAABNQAECn8qAAIYAAoKqxHHGADrAQAYAAoKqxHHGADrAQAAAA==.Raivek:BAAANQAECgIIAgAAAA==.Randenton:BAAANQADCgYICAAAAA==.Randezoth:BAAANQABCggIDQABNQADCgYICAAWAAAAAA==.Randomkiller:BAAANQADCgMIAwAAAA==.Rassputen:BAABNQAECn8wAAIOAAoK8xS/RwDaAQAOAAoK8xS/RwDaAQAAAA==.',
Re='Reck:BAAANQADCgEIAQAAAA==.Redjive:BAAANQAECggIAQAAAA==.Redonkulos:BAAANQADCgMIBAAAAA==.Reliri:BAAANQADCgYICgAAAA==.Renais:BAABNQAECn8VAAMOAAoKhwy4MACKAQAOAAoKhwy4MACKAQAiAAIKlQtWsAA7AAABNQAECgoKLwAFALcWAA==.Rex:BAABNQAECn8gAAIOAAkKGBfyMABNAgAOAAkKGBfyMABNAgAAAA==.',
Ri='Rileyesco:BAAANQABCgUIBgAAAA==.Ripskylark:BAAANQAECgIIAwAAAA==.Risk:BAAANQABCgcIEwAAAA==.',
Rj='Rjtheamazin:BAAANQAECgEIAQAAAA==.',
Ro='Roguen:BAACNQAFFH8KAAIfAAYKMgWeCwACAQAfAAYKMgWeCwACAQA1AAQKf1kAAx8ACgrQGR8NAKMCAB8ACgrQGR8NAKMCAA8AAwqGCNKCAKkAAAAA.Romirin:BAAANQADCgQIBAAAAA==.Rotan:BAAANQADCgYICwAAAA==.Roulduke:BAABNQAECn9IAAIGAAoKpA08SAC0AQAGAAoKpA08SAC0AQAAAA==.',
['Rù']='Rùckús:BAABNQAECn8pAAIBAAgKQR/eLgB1AgABAAgKQR/eLgB1AgABNQAECgkJHgAGALEZAA==.',
Sa='Sacredmentos:BAABNQAECn80AAMkAAoKABVZJgCsAQAkAAoKABVZJgCsAQAdAAYKagpm+gDyAAAAAA==.Salaen:BAAANQAECggIAwAAAA==.Sammybeans:BAAANQAFFAIIAwAAAA==.Sapito:BAAANQADCgYICgAAAA==.Saulotsalubr:BAAANQADCgQIBAAAAA==.',
Sc='Scarecrow:BAAANQAECgEIAQABNQAECgoKTQAJAGQjAA==.',
Se='Seceron:BAAANQAECgUIDAAAAA==.Sekai:BAAANQAECgIIAgAAAA==.Sevyns:BAAANQAECgMIBgAAAA==.',
Sg='Sgtslappy:BAAANQADCgMIAwAAAA==.',
Sh='Shamminator:BAAANQAECgEIAQAAAA==.Shanarelle:BAAANQAECgYIEwAAAA==.Shasa:BAACNQAFFH8KAAIHAAQKyxh0EQD9AAAHAAQKyxh0EQD9AAA1AAQKfycAAgcACgozHrw1AMoCAAcACgozHrw1AMoCAAAA.Shatteredsky:BAABNQAECn8hAAMXAAkKER2AKwC1AgAXAAkKER2AKwC1AgAGAAEKqgOgRQErAAAAAA==.Shazik:BAABNQAECn9VAAIXAAoKZR+qDQBRAwAXAAoKZR+qDQBRAwAAAA==.Shazzik:BAAANQAECgYICgABNQAECgoKVQAXAGUfAA==.Sheroko:BAAANQAECgIICAAAAA==.Sheñanigans:BAABNQAECn8eAAIGAAkKsRk/NQAAAgAGAAkKsRk/NQAAAgAAAA==.Shilbalam:BAAANQAECgYICgAAAA==.Shirohane:BAAANQAECgcICwABNQAECgoKLwAFALcWAA==.Shmoopy:BAAANQAECgEIAQAAAA==.Shmoove:BAAANQADCgEIAQAAAA==.Shnkz:BAAANQAECgEIAQAAAA==.Shotzer:BAAANQADCgMIBgAAAA==.',
Si='Silzo:BAABNQAECn8oAAMOAAoKTB2gEQCLAgAOAAoKTB2gEQCLAgABAAEKuQhkkQApAAABNQAECgoKKgAYAKsRAA==.Sirjames:BAAANQAECgEIAQAAAA==.',
Sk='Skelix:BAACNQAFFH8yAAIXAAkKUiBdAQARAwAXAAkKUiBdAQARAwA1AAQKfy8AAxcACQpLJmMFAJwDABcACQpLJmMFAJwDAAYAAwpVF6baAN8AAAAA.Skunkpaw:BAAANQADCgUIDwAAAA==.Skysong:BAACNQAFFH8XAAQgAAgK1BrKAQAxAQAgAAYKTh/KAQAxAQAoAAIK4BEuCwCcAAAQAAEKeAUJGQA+AAA1AAQKfyYABCAACgpJIYYJANkCACAACgpJIYYJANkCABAAAwp/BaZBAJQAACgAAQrwIysYAGcAAAAA.',
Sl='Slashedeye:BAABNQAECn9BAAImAAkKFRSWAgASAgAmAAkKFRSWAgASAgAAAA==.Slimgucci:BAAANQADCggICAAAAA==.',
Sn='Snowfox:BAAANQADCgIIAgAAAA==.Snowynn:BAABNQAECn8gAAMRAAkKfhaFFAAdAgARAAkKfhaFFAAdAgACAAMKxggGMgCDAAAAAA==.Snubby:BAABNQAECn8cAAMTAAkKtCJFOwCiAgATAAcKmyFFOwCiAgAUAAIKcyVYOgDYAAAAAA==.',
So='Solheim:BAAANQABCgUIBQAAAA==.Sonari:BAAANQADCgYIBgAAAA==.',
Sp='Spankz:BAAANQAECgQICQAAAA==.Spathi:BAAANQAFFAIIAwAAAA==.Spicymeatbal:BAAANQABCggIEQAAAA==.',
St='Stepz:BAAANQABCggIDAAAAA==.Strathz:BAABNQAECn8iAAMTAAkKfRw0NQC1AgATAAkKMxk0NQC1AgAUAAQKahyvKAA0AQAAAA==.Stregobor:BAAANQAECgYIDAABNQAECgoKMwAFAB8gAA==.Striker:BAAANQAECgYIBQAAAA==.Strongish:BAAANQADCgUIBQAAAA==.',
Su='Summerset:BAAANQAECgIIAQAAAA==.Sunstrider:BAAANQADCgMIBgAAAA==.Superdonkey:BAAANQADCgYICwABNQAFFAcIFwAbANMWAA==.Sushi:BAAANQADCgIIAgAAAA==.Suva:BAAANQADCgYIBgAAAA==.',
Sy='Sylatis:BAAANQAECgYIDAABNQAFFAYIIAATAOoiAA==.Sylätis:BAAANQAECgMIAwABNQAFFAYIIAATAOoiAA==.',
['Sö']='Söultender:BAAANQADCgMIAwABNQAECgYIDQAWAAAAAA==.',
['Sø']='Sølidus:BAAANQAECgMIDgABNQAFFAgIFAAIAHQaAA==.',
Ta='Taintedhealz:BAAANQADCgEIAQAAAA==.Talys:BAACNQAFFH8eAAIQAAgKAxYcBAA8AgAQAAgKAxYcBAA8AgA1AAQKf0IAAhAACgrnJCUBAMYDABAACgrnJCUBAMYDAAAA.Tankly:BAAANQADCgMIAwAAAA==.',
Te='Tehchosen:BAAANQADCggICAAAAA==.Terramor:BAAANQAECgIIAgAAAA==.Terranok:BAAANQADCgEIAQAAAA==.Texicola:BAABNQAECn9KAAIEAAoKrh/RAgAvAwAEAAoKrh/RAgAvAwAAAA==.',
Th='Thabdeady:BAAANQAECgYIDgABNQAECgoKSAAgAG0aAA==.Thabk:BAABNQAECn9IAAQgAAoKbRqVBACNAgAgAAoKbRqVBACNAgAoAAgKnwt9DgBfAQAQAAYKCQs9LQA7AQAAAA==.Thaelorn:BAAANQADCgEIAQAAAA==.Thesyra:BAABNQAECn8uAAMoAAoKGw1xCACkAQAoAAoKGw1xCACkAQAQAAoKLQj/JwB3AQAAAA==.Thundercrash:BAAANQADCgUIBgAAAA==.Thunderjeed:BAAANQAECgcICgABNQAFFAYIFAAbAIQcAA==.Thurmond:BAABNQAECn8hAAMBAAoKWhtnOwA0AgABAAoKthZnOwA0AgAOAAYKBBn9WQCLAQAAAA==.Thurmoons:BAABNQAECn8ZAAMZAAoK6RtOFgBjAgAZAAoKzRlOFgBjAgARAAUKJB7cHgCoAQABNQAECgoKIQABAFobAA==.Thurmund:BAAANQADCgYIBgABNQAECgoKIQABAFobAA==.',
Ti='Tiamat:BAAANQADCggICAAAAA==.Tidalanxiety:BAAANQAECgQIBQAAAA==.Tigray:BAAANQADCggIDgAAAA==.',
To='Toastay:BAAANQAECgQIDwAAAA==.Toastz:BAABNQAECn9HAAIHAAoKXiJuCwCCAwAHAAoKXiJuCwCCAwAAAA==.Toebeanz:BAAANQAECgUIDAAAAA==.Tokken:BAACNQAFFH8ZAAIMAAcKKBMcBwBPAgAMAAcKKBMcBwBPAgA1AAQKfzgAAgwACgoRIWc9ANMCAAwACgoRIWc9ANMCAAAA.Totemi:BAAANQADCgMIAwAAAA==.',
Tr='Treebeast:BAABNQAECn8WAAMGAAkKER+5LQDGAgAGAAkKER+5LQDGAgAXAAEKnQE3KAElAAAAAA==.Troile:BAAANQAECgcIEQAAAA==.Trojen:BAACNQAFFH8IAAIdAAQKVg72GQDYAAAdAAQKVg72GQDYAAA1AAQKfyAAAx0ACQp2GpaDACECAB0ACApyGpaDACECABwACAoYC3J8AKQBAAAA.Trolladin:BAAANQADCgYICgABNQADCggIJQAWAAAAAA==.',
Tw='Twig:BAABNQAECn8nAAMZAAkKGhgyLAB5AgAZAAkKGhgyLAB5AgADAAQKLA/PTwC8AAAAAA==.',
Ty='Tyras:BAABNQAECn8YAAMSAAYKFhDVFwC1AAAbAAUKzQ2GRQDvAAASAAUKFhDVFwC1AAAAAA==.',
Tz='Tzarina:BAAANQABCggICgAAAA==.',
['Tâ']='Tâz:BAABNQAECn8yAAMXAAoKix/KKgC4AgAXAAoKix/KKgC4AgAGAAEKAADNJwEAAAAAAA==.',
Ul='Ulanda:BAABNQAECn9NAAMCAAoKvxdMDAAOAgARAAkKNhQzEQBNAgACAAkKghZMDAAOAgAAAA==.',
Um='Umasi:BAACNQAFFH8hAAIkAAgK1CROAAABAwAkAAgK1CROAAABAwA1AAQKfzUAAiQACgqdJrEBAL8DACQACgqdJrEBAL8DAAAA.',
Un='Underbogg:BAAANQADCgUIBQAAAA==.Unus:BAAANQAECgQICwABNQAECgoKMwAFAB8gAA==.',
Ut='Utastebad:BAAANQADCggIDAAAAA==.',
Va='Vagabundo:BAAANQAECgMIAwABNQAECgYICwAWAAAAAA==.Vail:BAAANQADCgUIBgAAAA==.Vainquish:BAAANQADCgEIAQAAAA==.Valamaldoran:BAAANQADCgUIBQAAAA==.Vanthil:BAAANQAECgIIAgAAAA==.Vaporize:BAAANQAECgIIAgAAAA==.',
Ve='Venandi:BAABNQAECn8UAAIFAAgKzAyB4ADIAQAFAAgKzAyB4ADIAQAAAA==.Vengened:BAABNQAECn85AAIMAAoKnhjcVwCEAgAMAAoKnhjcVwCEAgAAAA==.Verax:BAAANQAECgIIAgAAAA==.Verestrasz:BAAANQADCgIIBAAAAA==.',
Vg='Vgly:BAAANQAECgQIEAAAAA==.',
Vi='Vilous:BAABNQAECn81AAIlAAoKQCaHAADVAwAlAAoKQCaHAADVAwAAAA==.',
Vy='Vyisesham:BAABNQAECn81AAMGAAoKKxpNQAB0AgAGAAkKJRlNQAB0AgAXAAkKSBaDaAB8AQAAAA==.',
['Vý']='Výce:BAAANQAECgEIAQAAAA==.',
Wa='Wagtar:BAAANQADCgYICwABNQADCgQIBAAWAAAAAA==.Warzug:BAAANQADCgQIBAAAAA==.',
We='Wesjin:BAABNQAECn8kAAMpAAoKrROWFAAyAgApAAoKrROWFAAyAgAbAAEKHQM/dgAiAAAAAA==.Wez:BAAANQAECgcICwAAAA==.',
Wh='Whiskee:BAACNQAFFH8KAAICAAMK8RnLAgCYAAACAAMK8RnLAgCYAAA1AAQKfykABAIACgoOIwMFADUDAAIACQoDIgMFADUDABEABwrzIHARAEoCABkAAQp2EaCFADsAAAAA.',
Wo='Wooglone:BAAANQAECgQJBAAAAA==.',
Wy='Wyndia:BAABNQAECn8aAAIFAAoK9RshZQC0AgAFAAoK9RshZQC0AgAAAA==.Wyndibear:BAAANQAECgMIAgAAAA==.',
Xa='Xanthos:BAAANQAECgEIAQABNQAECgQIBgAWAAAAAA==.',
Xe='Xela:BAAANQAECgUIDAABNQAECgoKMwAFAB8gAA==.Xenophontes:BAABNQAECn8dAAMEAAoKNR+jGgAeAQAFAAkK8xzKtQAYAgAEAAUKFR2jGgAeAQABNQAFFAgIFAAIAHQaAA==.Xeris:BAAANQADCgEIAQAAAA==.',
Xi='Xihuang:BAABNQAECn9EAAIZAAoK3RklGgA5AgAZAAoK3RklGgA5AgABNQAFFAYICgAfADIFAA==.Xiia:BAAANQAECgQIBAAAAA==.',
Xo='Xouu:BAAANQAFFAUIBAABNQAFFAgIBgAXADoRAA==.',
Xx='Xxuu:BAAANQAFFAgIAgABNQAFFAgIBgAXADoRAA==.Xxuusham:BAACNQAFFH8GAAIXAAYKOhFoBwDkAQAXAAYKOhFoBwDkAQA1AAQKf0cAAhcACgrTJSICAMYDABcACgrTJSICAMYDAAAA.Xxuuspr:BAAANQAECggIAgABNQAFFAgIBgAXADoRAA==.',
Ya='Yaoguai:BAABNQAECn9GAAMZAAoKuBvSFwBSAgAZAAoKuBvSFwBSAgARAAEKHwm6YAAzAAAAAA==.Yasei:BAAANQAECgQIBAAAAA==.Yawgmoth:BAABNQAECn8ZAAQVAAgKzgy/GgCuAAATAAgKwQlGvADZAAAVAAUKDA2/GgCuAAAUAAEKFgQthAAmAAABNQAECgkJIQASALcbAA==.',
Za='Zakkha:BAAANQADCgMIAwABNQADCggIEwAWAAAAAA==.Zaleris:BAAANQAECgQIBQAAAA==.Zaryana:BAABNQAECn8eAAINAAkKHgTJIgDjAAANAAkKHgTJIgDjAAAAAA==.',
Ze='Zephon:BAABNQAECn8lAAIHAAoKpgzzlQDcAQAHAAoKpgzzlQDcAQAAAA==.',
Zo='Zotiel:BAAANQAFFAQIBAABNQAFFAkJNAABAFgdAA==.',
Zy='Zynisch:BAAANQADCgcIEwAAAA==.',
['Ær']='Æris:BAAANQADCgMIAwAAAA==.',
['Ìr']='Ìroh:BAAANQADCgUIBgABNQAECgYIDQAWAAAAAA==.',
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
