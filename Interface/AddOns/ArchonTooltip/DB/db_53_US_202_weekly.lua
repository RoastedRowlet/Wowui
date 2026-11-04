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

local lookup = {'DeathKnight-Unholy','Druid-Feral','Druid-Restoration','Mage-Frost','Mage-Arcane','Shaman-Elemental','Hunter-BeastMastery','Priest-Holy','DemonHunter-Havoc','DemonHunter-Vengeance','Shaman-Enhancement','Warrior-Arms','DeathKnight-Blood','Rogue-Assassination','Evoker-Preservation','Druid-Guardian','Monk-Brewmaster','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Unknown-Unknown','Shaman-Restoration','DemonHunter-Devourer','Druid-Balance','Monk-Windwalker','Paladin-Holy','Paladin-Retribution','Hunter-Marksmanship','Rogue-Subtlety','Evoker-Devastation','Rogue-Outlaw','DeathKnight-Frost','Priest-Shadow','Paladin-Protection','Warrior-Fury','Mage-Fire','Priest-Discipline','Evoker-Augmentation','Monk-Mistweaver',}
local provider = {region='US',realm='Spirestone',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Abduon:BAAANQADCgcIDAAAAA==.',
Ac='Aciddeath:BAAANQAECgEIAQABNQAFFAUIFQABAP8RAA==.',
Ad='Admaris:BAACNQAFFH8JAAMCAAIKbRFkAwCaAAACAAIKbRFkAwCaAAADAAIKMhpkDQCYAAA1AAQKfzsAAwMACgp1IPwMAP8CAAMACgp1IPwMAP8CAAIABwqQIdIJAKMCAAAA.',
Ae='Aelis:BAAANQADCgEIAQAAAA==.',
Ag='Agni:BAACNQAFFH8VAAMEAAgK/w9RAwDrAAAFAAUKwwuiJwBLAQAEAAMKOxRRAwDrAAA1AAQKfzEAAwUACgqSJDhLAOsCAAUACgqTIzhLAOsCAAQAAwrsI8MSACMBAAAA.',
Ak='Akkadian:BAAANQADCggICwAAAA==.',
Al='Almight:BAAANQADCgcICQAAAA==.Alnasham:BAACNQAFFH8TAAIGAAcKcxnCAwClAQAGAAcKcxnCAwClAQA1AAQKfzIAAgYACgoTIoUUAE4DAAYACgoTIoUUAE4DAAAA.Alnava:BAAANQAECgcIEAAAAA==.Altria:BAAANQAECgIIAQAAAA==.Alvoka:BAABNQAECn8VAAIFAAcKLRbv0QDiAQAFAAcKLRbv0QDiAQAAAA==.',
Am='Amarillos:BAABNQAECn8WAAIHAAkKSBQqYwBPAgAHAAkKSBQqYwBPAgAAAA==.Amarillys:BAACNQAFFH8IAAIIAAUK+Qt9EwBvAQAIAAUK+Qt9EwBvAQA1AAQKfzUAAggACgrgIB0KAHYDAAgACgrgIB0KAHYDAAAA.Ammutseba:BAABNQAECn8oAAMJAAoK0hkDGAAgAgAJAAoKlxkDGAAgAgAKAAMK2hZFIgCwAAAAAA==.',
An='Anfall:BAACNQAFFH8WAAILAAYKHBJ+AQA7AQALAAYKHBJ+AQA7AQA1AAQKfzYAAgsACgoxIksIAPUCAAsACgoxIksIAPUCAAAA.Angermeier:BAABNQAECn8+AAIMAAoKLBVxPgAbAgAMAAoKLBVxPgAbAgAAAA==.Angers:BAAANQAECgIIAgABNQAECgoKPgAMACwVAA==.Angrylady:BAAANQAECgEIAQAAAA==.Anjuna:BAAANQADCgUIBgAAAA==.Anohru:BAAANQAECggIEgAAAA==.Anthos:BAAANQAECggIDgAAAA==.Antikreist:BAAANQADCgUIBQAAAA==.Anyawnka:BAAANQAECgEIAgAAAA==.',
Ap='Aphotic:BAAANQAECgMIBQAAAA==.',
Ar='Arcady:BAAANQADCgYIBgAAAA==.Ards:BAAANQADCgIIAwAAAA==.Armanite:BAAANQAECgQIBQABNQAECgoKIQABAFobAA==.Arowin:BAAANQAECgEIAgAAAA==.Arthaniis:BAABNQAECn8YAAIGAAcKKCESSwBKAgAGAAcKKCESSwBKAgAAAA==.',
As='Asystoli:BAABNQAECn8jAAMFAAoKkBZwbQCnAQAFAAkKmxdwbQCnAQAEAAIKQw91NAA9AAAAAA==.',
At='Atheria:BAAANQADCgYICAAAAA==.Attackheli:BAAANQAECgQIEgAAAA==.',
Au='Audideath:BAAANQAECgUICwAAAA==.Auurdeath:BAAANQADCggIEwAAAA==.',
Av='Av:BAAANQADCgIIBQAAAA==.',
Aw='Aw:BAACNQAFFH8cAAIJAAcKLRyqAwBFAgAJAAcKLRyqAwBFAgA1AAQKfygAAgkACgpmJfQFAJYDAAkACgpmJfQFAJYDAAAA.',
Ax='Ax:BAECNQAFFH8RAAMBAAcKdRasBwCeAQABAAYKdRasBwCeAQANAAEKAADZOQAfAAA1AAQKfywAAgEACgqJIwQSAEACAAEACgqJIwQSAEACAAAA.',
Az='Azzazinzblo:BAAANQADCgUIBQAAAA==.',
['Aÿ']='Aÿa:BAAANQAECgUICgAAAA==.',
Ba='Baast:BAAANQADCgUIBQAAAA==.Bamph:BAAANQAECggIDQAAAA==.Bangbang:BAAANQAECgcIDwAAAA==.Batez:BAAANQAECgQIBAABNQAFFAYIEQAOAO8OAA==.',
Bd='Bdk:BAABNQAECn8UAAINAAkKuR2rGQDgAgANAAkKuR2rGQDgAgAAAA==.Bdog:BAAANQAECgEIAwAAAA==.',
Be='Beeatinu:BAAANQAECgMIAwAAAA==.Beers:BAAANQAECggIBwAAAA==.Beledros:BAABNQAECn8cAAIPAAkKVBP4FQBWAgAPAAkKVBP4FQBWAgAAAA==.Beni:BAABNQAECn9WAAMQAAoKBCRpAgBFAwAQAAoKBCRpAgBFAwACAAUK+BTEHAA7AQAAAA==.Benson:BAABNQAECn8hAAIRAAkKoxwsCACuAgARAAkKoxwsCACuAgAAAA==.Bensonadin:BAAANQAECgYIBgAAAA==.Berd:BAAANQAECggIBgAAAA==.',
Bi='Bigwillybob:BAAANQADCgIIAgAAAA==.Bina:BAAANQAECgQIBQAAAA==.Birblock:BAACNQAFFH8gAAQSAAYK6iKNAgBqAgASAAYK6iKNAgBqAgATAAIKygE5EwB6AAAUAAEK/BkXCABiAAA1AAQKfyMABBIACQotJiYzALwCABIABwo1JiYzALwCABMABwq3GxUUAM8BABQAAQoAAFYpAEcAAAAA.',
Bo='Bobbo:BAAANQADCgYJCAAAAA==.',
Br='Brek:BAAANQAFFAEIAQAAAA==.Brewtherguy:BAABNQAECn8iAAIRAAkKAB1oBwDGAgARAAkKAB1oBwDGAgAAAA==.Brother:BAAANQADCgIIAgAAAA==.Bruceshepard:BAAANQADCgQICQABNQAECgUIDQAVAAAAAA==.Brutebuffalo:BAABNQAECn8lAAMWAAkKqh2uIwDYAgAWAAkKqh2uIwDYAgAGAAUKQBH/rQA3AQAAAA==.Bruteflappy:BAAANQADCggICAABNQAECgkJJQAWAKodAA==.Brutetestify:BAAANQADCggICAABNQAECgkJJQAWAKodAA==.',
Bu='Bubbleboi:BAAANQADCgYICAAAAA==.Bubblebôy:BAAANQAECgIIAgAAAA==.Bublz:BAABNQAECn8cAAIIAAkKwRSgaQDhAQAIAAkKwRSgaQDhAQAAAA==.',
['Bâ']='Bâra:BAABNQAECn8eAAIBAAoKahqhJQCoAgABAAoKahqhJQCoAgAAAA==.',
Ca='Carnal:BAAANQADCgUIBQAAAA==.Castro:BAAANQAECgIIAgAAAA==.',
Ce='Cedren:BAACNQAFFH8LAAIJAAUKDQ6gDgAfAQAJAAUKDQ6gDgAfAQA1AAQKfzUAAwkACgpCHfYXACACAAkACgpFHPYXACACABcACAotE7srAOQBAAAA.Ceewhya:BAAANQAECgMIBAAAAA==.Celestika:BAAANQADCgEIAQAAAA==.Cerari:BAAANQAECgEJAQAAAA==.',
Ch='Chalix:BAAANQAECgMIBQAAAA==.Chama:BAABNQAECn8aAAIXAAkKpxI0JAAmAgAXAAkKpxI0JAAmAgAAAA==.Cheapheal:BAABNQAECn9DAAMQAAoKFSDzBABSAwAQAAoKFSDzBABSAwAYAAEKAADckAAAAAAAAA==.Cheapsnipe:BAAANQAECggIEgABNQAECgoKQwAQABUgAA==.Cheburashka:BAACNQAFFH8YAAIGAAcKxiKrBABIAgAGAAcKxiKrBABIAgA1AAQKfyIAAgYACgpbIakoAN8CAAYACgpbIakoAN8CAAAA.Chimerabob:BAAANQAECgQICAAAAA==.Chopsuey:BAAANQAECggIBwAAAA==.Chunkymonkey:BAACNQAFFH8XAAIZAAcK0xa7BADwAQAZAAcK0xa7BADwAQA1AAQKf0MAAhkACgrYI78CAEQDABkACgrYI78CAEQDAAAA.',
Ci='Cidren:BAAANQAECgEIAQAAAA==.',
Cj='Cjpriestly:BAAANQADCgEIAQAAAA==.',
Cl='Clappncheeks:BAABNQAECn8bAAIHAAoK+BhaPgAjAgAHAAoK+BhaPgAjAgAAAA==.Claudefrollo:BAABNQAECn8mAAIYAAoKgAu3MQBDAQAYAAoKgAu3MQBDAQAAAA==.Clorox:BAAANQADCgEIAQAAAA==.',
Cr='Crankyelf:BAAANQADCgEIAQAAAA==.Crimsa:BAABNQAECn88AAIUAAoKwAULCgBfAQAUAAoKwAULCgBfAQAAAA==.Crimsonaxel:BAABNQAECn8qAAIGAAoK1xkiJwATAgAGAAoK1xkiJwATAgAAAA==.Cryogen:BAAANQAECgQJCAAAAA==.',
Cu='Cursewords:BAAANQADCgUIBQABNQAECgYIBgAVAAAAAA==.',
Da='Daemonproph:BAAANQADCgYIDAAAAA==.Dakini:BAABNQAECn8zAAIaAAoK0hxdGQC/AgAaAAoK0hxdGQC/AgAAAA==.Dam:BAAANQADCgUIBQABNQAECgkJIAANABgXAA==.Danaowns:BAAANQAECgEIAgAAAA==.Dangerruss:BAAANQAECgYICQAAAA==.Darkspartan:BAAANQAECgYIBQAAAA==.Dashytash:BAABNQAECn82AAIKAAoKyh3FBABQAgAKAAoKyh3FBABQAgAAAA==.Dawnsoul:BAAANQAECgYIDQAAAA==.Daxos:BAAANQAECgEIAQAAAA==.',
De='Deadcowmeat:BAAANQAECggICQAAAA==.Deathschosen:BAAANQADCgQIBAAAAA==.Deiza:BAAANQAECgMIAwAAAA==.Demb:BAAANQAECgQIBwAAAA==.Demonicchoas:BAABNQAECn8wAAMTAAoKQh/MDAArAgASAAkKQh6tWwBEAgATAAcKfhzMDAArAgAAAA==.Denagorn:BAABNQAECn9AAAIbAAoKzSQeEQCEAwAbAAoKzSQeEQCEAwABNQAFFAgIMQABAPcdAA==.Denaki:BAAANQAECgQIBAABNQAFFAgIMQABAPcdAA==.Denhunt:BAABNQAECn8jAAMHAAoKlSAHIgAPAwAHAAoKiCAHIgAPAwAcAAQKLRkaLwDDAAABNQAFFAgIMQABAPcdAA==.Dentsama:BAAANQAECggICQABNQAFFAgIMQABAPcdAA==.Deplete:BAAANQADCgIJAgABNQAECgoKPgAYAEYbAA==.Deutzfr:BAABNQAECn8YAAIKAAkKfxwZBwCfAgAKAAkKfxwZBwCfAgAAAA==.Devos:BAABNQAECn8YAAMGAAcKgBMrcgDKAQAGAAcKgBMrcgDKAQAWAAQKRQ6X1gC6AAABNQAFFAUICQAGAIcEAA==.',
Di='Dizzleman:BAAANQAECggICgAAAA==.',
Do='Dominant:BAABNQAECn8uAAMFAAoKoB4LWQDOAgAFAAoKoB4LWQDOAgAEAAEKAAA5SgAxAAAAAA==.Dotemup:BAAANQAECgEIAQAAAA==.',
Dp='Dpssos:BAAANQAECggIDgAAAA==.',
Dr='Draco:BAAANQADCgcIBwAAAA==.Drag:BAAANQADCgYICQAAAA==.Drbob:BAAANQADCgIIAgAAAA==.Dreadmar:BAAANQADCgYICgAAAA==.Drock:BAABNQAECn87AAIXAAoKzCAqCABQAwAXAAoKzCAqCABQAwAAAA==.Druidgale:BAAANQAECgIIAwAAAA==.Drybonez:BAAANQAECgYICAAAAA==.Drygth:BAAANQADCgMIBgABNQAECgoKMQAdABEiAA==.Dräkarnoir:BAAANQADCggICAAAAA==.',
Dt='Dtb:BAACNQAFFH8XAAINAAYKZh8UCADgAQANAAYKZh8UCADgAQA1AAQKfzkAAg0ACgp4JeYEAKMDAA0ACgp4JeYEAKMDAAAA.',
Du='Dunfjord:BAAANQAECgEIAgAAAA==.Dushimaya:BAACNQAFFH8FAAIaAAMKoxe1EQDmAAAaAAMKoxe1EQDmAAA1AAQKfz4AAhoACgoCJI4HAI4DABoACgoCJI4HAI4DAAAA.',
Dv='Dvil:BAAANQAECgQIBQABNQAECgoKOwAXAMwgAA==.',
Dw='Dwyndi:BAAANQAFFAEIAQAAAA==.',
Eb='Ebichiri:BAAANQADCgEIAQAAAA==.',
Ei='Eisador:BAABNQAECn8VAAIHAAcKWAtIqAC1AQAHAAcKWAtIqAC1AQAAAA==.',
El='Elsen:BAAANQAECgUIDQAAAA==.Elsha:BAABNQAECn8hAAIRAAkKtxtdCACmAgARAAkKtxtdCACmAgAAAA==.',
Em='Emp:BAAANQAECgUIBgAAAA==.',
Er='Erilee:BAAANQAECgYICgAAAA==.',
Ev='Evelira:BAACNQAFFH8TAAIIAAcKyBu+BwARAgAIAAcKyBu+BwARAgA1AAQKfxUAAggACQoWFotiAPkBAAgACQoWFotiAPkBAAAA.',
Ey='Eyja:BAAANQADCgEIBAAAAA==.',
Ez='Ezailas:BAAANQAECgQIBQAAAA==.Ezpzndaheezy:BAAANQADCgYIBgABNQAECgoKQwAeAHcYAA==.',
Fa='Fatherangus:BAAANQAECggICAAAAA==.Fathercoast:BAAANQAECgYICwAAAA==.',
Fe='Fearful:BAACNQAFFH8FAAIaAAMKYAJkGwC+AAAaAAMKYAJkGwC+AAA1AAQKfyIAAhoACQr5Ff5GAEoCABoACQr5Ff5GAEoCAAAA.Felstrider:BAAANQAECgEIAQAAAA==.Ferador:BAACNQAFFH8XAAMHAAYK9BaNEABUAQAHAAQKjRmNEABUAQAcAAUKDQ8gDwBMAQA1AAQKfykAAwcACgqVH+xDAJ8CAAcACgqVH+xDAJ8CABwABgq+Ero/AFUBAAAA.Feythe:BAACNQAFFH8vAAINAAoKHhFOAQBWAgANAAoKHhFOAQBWAgA1AAQKfxgAAg0ACgreFxQ5ACICAA0ACgreFxQ5ACICAAAA.',
Fi='Figgleslock:BAAANQADCgUIBQAAAA==.',
Fl='Flakester:BAABNQAECn8pAAIIAAcKLiNlKgBrAgAIAAcKLiNlKgBrAgAAAA==.Fleebly:BAABNQAECn8iAAIXAAoKiBnXGQCLAgAXAAoKiBnXGQCLAgAAAA==.',
Fn='Fndruid:BAAANQAECgIIAgAAAA==.',
Fo='Fourbees:BAABNQAECn8uAAIbAAoKFw16fQCSAQAbAAoKFw16fQCSAQAAAA==.',
Fu='Furocious:BAAANQADCgEIAQAAAA==.Fursure:BAAANQAECgMIAwAAAA==.',
Ga='Garfal:BAAANQAECgIIAwAAAA==.Gather:BAAANQADCgEIAQABNQAECgoKTwAWAK0cAA==.Gaurhoth:BAAANQAECgQIBQABNQAECgYICgAVAAAAAA==.',
Gi='Gilgamesh:BAAANQAECggIDQAAAA==.',
Go='Gorobob:BAAANQAECgIIBgAAAA==.',
Gr='Graygkl:BAAANQAECgUIDwAAAA==.Greshanwise:BAABNQAECn8gAAIDAAoK1wesNAAMAQADAAoK1wesNAAMAQAAAA==.Grimreaper:BAABNQAECn86AAIfAAoKjxmSBQCPAgAfAAoKjxmSBQCPAgAAAA==.Groag:BAABNQAECn8xAAMdAAoKESKbBQAtAwAdAAoKCyKbBQAtAwAOAAgKYxuJKgBBAgAAAA==.',
Ha='Haarp:BAAANQAECgUIEwAAAA==.Haelar:BAAANQAECgEIAQAAAA==.Hakü:BAAANQAECgcIBwAAAA==.Hammered:BAABNQAECn8dAAIbAAkKkSOaJwCcAgAbAAkKkSOaJwCcAgAAAA==.Haonao:BAAANQAECgEIAgAAAA==.Hardwire:BAAANQAECgEIAQAAAA==.',
He='Heartred:BAAANQADCgYIBgAAAA==.Heifer:BAACNQAFFH8FAAIYAAIKWw3nIQCEAAAYAAIKWw3nIQCEAAA1AAQKfyQAAhgACQrRIZcZAPsCABgACQrRIZcZAPsCAAAA.Hemophilia:BAABNQAECn8xAAIBAAkKchMSIACuAQABAAkKchMSIACuAQAAAA==.Heydk:BAABNQAECn8YAAMgAAkKlRuZWgA/AQAgAAUKRhqZWgA/AQABAAYKHBtBfgAjAQAAAA==.Heydruid:BAAANQAECgcIDQABNQAECgkJGAAgAJUbAA==.',
Ho='Hollowshädix:BAAANQAECgEIAQAAAA==.Holyanxiety:BAAANQADCgYIBgAAAA==.Holydave:BAAANQAECgMIBAAAAA==.Holymentos:BAABNQAECn8gAAMhAAoKqw+uLwCmAQAhAAgKOQuuLwCmAQAIAAcKWgMwygDDAAABNQAECgoKMAAiAFIUAA==.Hottsauce:BAABNQAECn8cAAILAAkKQBwwDQCbAgALAAkKQBwwDQCbAgAAAA==.Hottsaucefel:BAAANQAECgYIBgAAAA==.',
Hu='Hundard:BAAANQADCgIIAgAAAA==.Huntersmarc:BAAANQAECgIIBQAAAA==.Hushhides:BAABNQAECn8iAAMOAAoKEhNCCwD2AQAdAAkK8g2CGAAYAgAOAAkKYBJCCwD2AQAAAA==.Hushrage:BAAANQAECggIDAABNQAECgoKIgAOABITAA==.Hushwing:BAAANQAECggICQABNQAECgoKIgAOABITAA==.',
Ia='Iamachick:BAAANQAECgEIAQAAAA==.',
Ib='Ibetrollinya:BAABNQAECn8YAAICAAoK6iPDAgAAAwACAAoK6iPDAgAAAwABNQAECgoKNQAjAEAmAA==.Iblisshaytan:BAABNQAECn9KAAIJAAoKSh2iFABIAgAJAAoKSh2iFABIAgABNQAFFAUICQAdAHAGAA==.Ibtrollin:BAAANQADCggIJwAAAA==.',
Ig='Ignacious:BAAANQAECgEIAQAAAA==.',
Il='Illumina:BAACNQAFFH8JAAIiAAUKQxbpBADUAAAiAAUKQxbpBADUAAA1AAQKfyoAAiIACQpgIpkIABQDACIACQpgIpkIABQDAAAA.',
Io='Ionissa:BAABNQAECn8wAAIHAAoKTx38LwDdAgAHAAoKTx38LwDdAgAAAA==.',
Ir='Ironbreaker:BAAANQAECgYIEAAAAA==.',
Is='Ischia:BAACNQAFFH8JAAMIAAQK5wgCGwATAQAIAAQK5wgCGwATAQAhAAEKbAEPGwA0AAA1AAQKf0cAAwgACQo0HPU2AIwCAAgACQo0HPU2AIwCACEAAgrUE55pAFsAAAAA.',
Ja='Jallypally:BAAANQADCgIIAgAAAA==.Jarl:BAAANQADCgYIDAAAAA==.',
Jc='Jch:BAACNQAFFH8gAAIHAAgKzxxiAQCCAgAHAAgKzxxiAQCCAgA1AAQKfzwAAwcACgq0JS8HAEADAAcACgq0JS8HAEADABwAAQpkFhCGADgAAAAA.',
Je='Jeay:BAAANQAECgEJAQAAAA==.Jedijeed:BAACNQAFFH8TAAIZAAYKhBzNAgCeAQAZAAYKhBzNAgCeAQA1AAQKfzsAAhkACgreI0oGAGwDABkACgreI0oGAGwDAAAA.Jedikepjr:BAACNQAFFH8GAAIbAAMKZQmRGwDLAAAbAAMKZQmRGwDLAAA1AAQKfyQAAhsACgpdI+8eAMYCABsACgpdI+8eAMYCAAE1AAUUBggTABkAhBwA.Jenova:BAAANQADCgUIBwAAAA==.Jepage:BAABNQAECn8+AAQEAAoKhiCyAgDCAgAEAAoKhiCyAgDCAgAkAAcKXhkSBAB/AQAFAAYK7RPAHAFcAQAAAA==.Jess:BAAANQADCgEIAQAAAA==.',
Jo='Jollypoly:BAAANQADCgEIAQAAAA==.Jolyne:BAAANQAECgUIBgAAAA==.Joyful:BAAANQAECgQIBAAAAA==.',
Jp='Jprottsoo:BAABNQAECn8gAAIYAAgKqh7oIgC4AgAYAAgKqh7oIgC4AgAAAA==.',
Ju='Jubei:BAABNQAECn8mAAIjAAoKMA7uDQDUAQAjAAoKMA7uDQDUAQAAAA==.',
Ka='Kagayaki:BAAANQAECggIEgAAAA==.Kalmya:BAABNQAECn8nAAMDAAgKpQ0YMACaAQADAAgKpQ0YMACaAQACAAEKAAAhRgAuAAAAAA==.Kalrath:BAAANQAECgIIAgABNQAECgoKIQABAFobAA==.Kartam:BAAANQADCgcIBwAAAA==.Kasheek:BAAANQADCggICAAAAA==.',
Ke='Keizzer:BAAANQAECgcICwABNQAECgkJHQAIAPcbAA==.Keshisaru:BAAANQADCgQIBAAAAA==.',
Kh='Khazra:BAAANQAECgMIBgAAAA==.',
Ki='Kierràalexis:BAAANQADCgYIBgAAAA==.',
Kl='Klunder:BAABNQAECn82AAIWAAoKdSLiHQD1AgAWAAoKdSLiHQD1AgAAAA==.',
Ko='Korris:BAABNQAECn8wAAMHAAoKyiClMADaAgAHAAoKyiClMADaAgAcAAEK1wLwnAAiAAAAAA==.Kostik:BAAANQADCgUIBQAAAA==.',
Kr='Kridillis:BAABNQAECn8tAAIJAAoKFx6ZHAC1AgAJAAoKFx6ZHAC1AgAAAA==.',
Kt='Ktang:BAAANQAFFAEIAQAAAA==.',
Ky='Kybinc:BAAANQADCgQIBgAAAA==.',
['Kí']='Kírã:BAAANQABCgIIBAAAAA==.',
La='Lacie:BAAANQADCgEIAQAAAA==.Lawls:BAAANQADCgQIBwAAAA==.Lazybigger:BAAANQAECgIIAgAAAA==.Lazycow:BAACNQAFFH8GAAIQAAMKxwmnBgBsAAAQAAMKxwmnBgBsAAA1AAQKfz0AAhAACgrTFxESANoBABAACgrTFxESANoBAAAA.Lazyfrost:BAABNQAECn8tAAIFAAoKQxCdmwBJAgAFAAoKQxCdmwBJAgAAAA==.',
Le='Lethò:BAABNQAECn8xAAMaAAoKFyO0CACDAwAaAAoKFyO0CACDAwAbAAcKRxninwBNAQAAAA==.Lethô:BAAANQAECgYIDwAAAA==.Lethö:BAAANQAECgIIBQAAAA==.',
Li='Liesx:BAACNQAFFH8RAAMOAAYK7w5JBQDfAQAOAAYKIw1JBQDfAQAdAAYKTgiFDAADAQA1AAQKfywAAx0ACgrbId8WAKACAA4ACArtHrwUANUCAB0ACgq/HN8WAKACAAAA.Lilzarthe:BAAANQAECgYIDgAAAA==.Lindsybowhan:BAAANQAECgEIBAAAAA==.',
Lo='Loerasdh:BAABNQAECn8eAAIJAAgK3CVICgBeAwAJAAgK3CVICgBeAwAAAA==.Loko:BAACNQAFFH8TAAIYAAcK1hRhCQDpAQAYAAcK1hRhCQDpAQA1AAQKfzkAAhgACgrvIzEMAL8CABgACgrvIzEMAL8CAAAA.Looio:BAAANQADCgIIAwAAAA==.',
Lu='Lucien:BAAANQADCgEIAQAAAA==.Lumièrevide:BAAANQADCggICQAAAA==.Luxxus:BAABNQAECn8dAAIIAAkK9xtcKwC7AgAIAAkK9xtcKwC7AgAAAA==.',
Ly='Lyesx:BAABNQAECn8kAAMHAAkKeiFWFwA9AwAHAAkKeiFWFwA9AwAcAAMKpxSTVwDHAAABNQAFFAYIEQAOAO8OAA==.Lyndsy:BAAANQADCgUIBQAAAA==.Lyri:BAAANQADCgMIAwAAAA==.',
Ma='Macros:BAAANQAECgQICQAAAA==.Mageyousad:BAAANQADCgEIBQAAAA==.Makhtor:BAAANQAECgQIBQAAAA==.Mallaer:BAABNQAECn8tAAIIAAoKKiEyGgALAwAIAAoKKiEyGgALAwAAAA==.Malícíous:BAABNQAECn8wAAISAAkK/RIrWwCJAQASAAkK/RIrWwCJAQAAAA==.Mangosalsa:BAAANQADCgEIAQAAAA==.Mantakore:BAACNQAFFH8JAAIPAAQKZwSfDADPAAAPAAQKZwSfDADPAAA1AAQKfzUAAg8ACgooFuEVAFcCAA8ACgooFuEVAFcCAAAA.Marcdruid:BAAANQAECgYICQAAAA==.Maubles:BAAANQADCggICAABNQAFFAYIGAAiAFUOAA==.',
Mc='Mcdirk:BAAANQAECggICAAAAA==.',
Me='Meloxicam:BAAANQADCgEIAQAAAA==.Menopaws:BAABNQAECn9KAAIQAAoKWSapAACGAwAQAAoKWSapAACGAwAAAA==.Merdoon:BAAANQADCgEIAQAAAA==.Merrtt:BAAANQAECgYIBgAAAA==.Mertrik:BAABNQAECn8eAAMWAAkKtiIODQBYAwAWAAkKtiIODQBYAwAGAAMKiBDZ7QC7AAAAAA==.',
Mi='Midk:BAAANQAECgIIAwAAAA==.Mikayy:BAACNQAFFH8QAAIdAAUKAiNaAwAGAgAdAAUKAiNaAwAGAgA1AAQKfz8AAh0ACgodJv0AAMsDAB0ACgodJv0AAMsDAAAA.Milenko:BAABNQAECn9FAAIJAAoK1SLdBgAMAwAJAAoK1SLdBgAMAwAAAA==.Milly:BAABNQAECn8WAAIbAAgKFhhniAB7AQAbAAgKFhhniAB7AQABNQAECgoKRQAJANUiAA==.Mirenna:BAAANQADCgEIAQAAAA==.Misosoup:BAAANQADCgEIAQAAAA==.',
Mo='Molfsongal:BAAANQADCgIIAgAAAA==.Monstrous:BAACNQAFFH8YAAIMAAcKYhP4CAB1AQAMAAcKYhP4CAB1AQA1AAQKf0EAAgwACgr5H9grAGsCAAwACgr5H9grAGsCAAAA.Montanaught:BAAANQADCgEIAQABNQADCgYICQAVAAAAAA==.Moocher:BAAANQAECgEIAQAAAA==.Mordecaii:BAAANQADCgYIDgAAAA==.Morgul:BAAANQAECgYICgAAAA==.Morox:BAAANQAECggIEwABNQAFFAgIFQAEAP8PAA==.Mothman:BAAANQAECgUICgAAAA==.Moyana:BAAANQADCgEIAQAAAA==.',
Ms='Msbehaven:BAABNQAECn8vAAISAAgK8Ab/kQAAAQASAAgK8Ab/kQAAAQAAAA==.',
Mt='Mthafknfreez:BAABNQAECn8kAAIEAAoKwBVbBwB7AgAEAAoKwBVbBwB7AgABNQAFFAUICQAdAHAGAA==.',
Mu='Muffìns:BAAANQAECgUIBgAAAA==.Musashi:BAABNQAECn8kAAIIAAgKKBosQQBmAgAIAAgKKBosQQBmAgAAAA==.',
My='Mynuturchin:BAABNQAECn8WAAMNAAcK2BZeQwDuAQANAAcK2BZeQwDuAQAgAAEKJApUswAsAAAAAA==.',
Na='Nagy:BAAANQAECgMIAwAAAA==.',
Ni='Night:BAABNQAECn8tAAIFAAkK5BLhtwAUAgAFAAkK5BLhtwAUAgAAAA==.Nightsecho:BAAANQAECgMIBAAAAA==.Nightshris:BAAANQAECgYICAAAAA==.',
Nn='Nnyx:BAAANQABCgIIAgAAAA==.',
No='Notmehssos:BAAANQAECggIDAAAAA==.Notthechosen:BAABNQAECn8bAAQNAAoK3Ay/RgD5AAANAAUKRw2/RgD5AAABAAUKqQunjADyAAAgAAYKEQy/YQDUAAABNQAECgoKLwAMANoXAA==.',
Ny='Nymeriã:BAAANQAECgUICAAAAA==.',
Ob='Obzy:BAAANQAECgcIEwAAAA==.Obzz:BAAANQADCgEIAQABNQAECgcIEwAVAAAAAA==.',
Ok='Okamy:BAAANQAECgcIDAABNQAECgQIBQAVAAAAAA==.Oknelim:BAAANQADCggICAABNQAECgoKRQAJANUiAA==.',
Ol='Olympicjeid:BAABNQAECn8dAAMcAAgK5ROcLgDXAQAcAAgK5ROcLgDXAQAHAAEKCQY7VwE7AAABNQAFFAYIEwAZAIQcAA==.',
Op='Opz:BAACNQAFFH8HAAMhAAMK/wnfCQDQAAAhAAMK/wnfCQDQAAAlAAEK0QfNAgA8AAA1AAQKfzcAAyEACgo8GfsZAH0CACEACgo8GfsZAH0CACUABgqbGO0GADQBAAAA.',
Or='Orghujon:BAAANQADCgMIAwAAAA==.',
Pa='Paladinfive:BAAANQAECgEIAgAAAA==.Parthos:BAAANQAECgQIDQAAAA==.Parts:BAAANQAECgEIAQABNQAECgoKLgAFAKAeAA==.',
Pe='Pedro:BAABNQAECn8dAAIbAAkKYAphmQBZAQAbAAkKYAphmQBZAQAAAA==.Perry:BAAANQADCgIIAgAAAA==.',
Ph='Phenomenon:BAAANQAECgUIDAABNQAECgkJHQAbAJEjAA==.',
Pi='Pittydafoo:BAAANQAECgIIAgAAAA==.',
Pk='Pkunkk:BAAANQAECgcICwAAAA==.',
Pl='Ploxis:BAACNQAFFH8ZAAIKAAcKPhafAABbAQAKAAcKPhafAABbAQA1AAQKfyEAAgoACgodG40HAIwCAAoACgodG40HAIwCAAAA.',
Po='Polskashaman:BAABNQAECn8jAAILAAkK9hDNFwDrAQALAAkK9hDNFwDrAQAAAA==.Pookiebonez:BAAANQADCgIIAgABNQAECgYICAAVAAAAAA==.',
Pr='Prea:BAABNQAECn8ZAAMWAAoK9BiDUQAgAgAWAAkKQBmDUQAgAgAGAAEKAAAQQgEtAAAAAA==.Premiumferal:BAABNQAECn8bAAMOAAkKECGiHQCTAgAOAAkKECGiHQCTAgAdAAUKxRj4MAA2AQAAAA==.Primecarry:BAACNQAFFH8WAAIaAAcKbxplBgAIAgAaAAcKbxplBgAIAgA1AAQKfycAAhoACgpNI88JAHoDABoACgpNI88JAHoDAAAA.Prine:BAABNQAECn8nAAIMAAoKgB6+KwANAwAMAAoKgB6+KwANAwABNQAFFAcIFgAaAG8aAA==.',
Pu='Puripuri:BAAANQAECgQIBAAAAA==.',
Qi='Qinkipa:BAAANQAECgMIBAAAAA==.',
Qo='Qovo:BAAANQADCgEIAwAAAA==.',
Ra='Ragark:BAAANQADCgUIBQAAAA==.Raigko:BAABNQAECn9EAAIMAAoKDSWpCQCnAwAMAAoKDSWpCQCnAwAAAA==.Rainyday:BAABNQAECn8UAAIWAAYK9ApktwD+AAAWAAYK9ApktwD+AAAAAA==.Raiva:BAABNQAECn8bAAIXAAoKBw9OHQCFAQAXAAoKBw9OHQCFAQAAAA==.Raivek:BAAANQAECgIIAgAAAA==.Randenton:BAAANQADCgYICgAAAA==.Randezoth:BAAANQADCgEIAgABNQADCgYICgAVAAAAAA==.Randomkiller:BAAANQADCgMIAwAAAA==.Rassputen:BAABNQAECn8vAAINAAoKuxS/RwDaAQANAAoKuxS/RwDaAQAAAA==.',
Re='Reck:BAAANQADCgEIAQAAAA==.Redjive:BAAANQAECggIAQAAAA==.Redonkulos:BAAANQADCgMIBAAAAA==.Reliri:BAAANQADCgYICgAAAA==.Relis:BAAANQAECgEIAwAAAA==.Renais:BAAANQAECgcIEAAAAA==.Rex:BAABNQAECn8gAAINAAkKGBfyMABNAgANAAkKGBfyMABNAgAAAA==.',
Ri='Rileyesco:BAAANQADCgEIAQAAAA==.Ripskylark:BAAANQAECgIIAwAAAA==.Risk:BAAANQAECgEIAQAAAA==.',
Rj='Rjtheamazin:BAAANQAECgEIAQAAAA==.',
Ro='Roguen:BAACNQAFFH8JAAIdAAUKcAaeCwACAQAdAAUKcAaeCwACAQA1AAQKf0wAAx0ACgoDGR8NAKMCAB0ACgoDGR8NAKMCAA4AAwqGCNKCAKkAAAAA.Romirin:BAAANQADCgQIBAAAAA==.Rotan:BAAANQADCgYIDAAAAA==.Roulduke:BAABNQAECn9AAAIGAAoKtgxHPACoAQAGAAoKtgxHPACoAQAAAA==.',
['Rù']='Rùckús:BAABNQAECn8pAAIBAAgKQR/eLgB1AgABAAgKQR/eLgB1AgABNQAECgkJGAAGAKUYAA==.',
Sa='Sacredmentos:BAABNQAECn8wAAMiAAoKUhRZJgCsAQAiAAoKUhRZJgCsAQAbAAYKagoj0QD4AAAAAA==.Salaen:BAAANQAECggIAwAAAA==.Sammybeans:BAAANQAFFAIIAwAAAA==.Sanpai:BAAANQAECgEIAQAAAA==.Sapito:BAAANQADCgYICgAAAA==.Sasamiya:BAAANQADCgEIAQAAAA==.Saulotsalubr:BAAANQADCgQIBAAAAA==.',
Sc='Scarecrow:BAAANQAECgEIAQABNQAECgoKRQAJANUiAA==.Scrolls:BAAANQAECgEIAQAAAA==.',
Se='Seceron:BAAANQAECgUIDAAAAA==.Sekai:BAAANQAECgIIAgAAAA==.Sevyns:BAAANQAECgMIBgAAAA==.',
Sg='Sgtslappy:BAAANQADCgMIAwAAAA==.',
Sh='Shamminator:BAAANQAECgEIAQAAAA==.Shanarelle:BAAANQAECgYIEwAAAA==.Shasa:BAACNQAFFH8IAAIHAAMKyxhYDAAGAQAHAAMKyxhYDAAGAQA1AAQKfyYAAgcACgozHrw1AMoCAAcACgozHrw1AMoCAAAA.Shatteredsky:BAABNQAECn8hAAMWAAkKER2AKwC1AgAWAAkKER2AKwC1AgAGAAEKqgOgRQErAAAAAA==.Shazik:BAABNQAECn9PAAIWAAoKrRwGDwAfAwAWAAoKrRwGDwAfAwAAAA==.Shazzik:BAAANQAECgYICgABNQAECgoKTwAWAK0cAA==.Sheroko:BAAANQAECgMIBwAAAA==.Sheñanigans:BAABNQAECn8YAAIGAAkKpRjbMADeAQAGAAkKpRjbMADeAQAAAA==.Shilbalam:BAAANQAECgUIBgAAAA==.Shirohane:BAAANQAECgUICQAAAA==.Shmoopy:BAAANQAECgEIAQAAAA==.Shmoove:BAAANQADCgEIAQAAAA==.Shnkz:BAAANQAECgEIAQAAAA==.Shotzer:BAAANQADCgMIBgAAAA==.',
Si='Silzo:BAABNQAECn8aAAMNAAkK0xy8KgBwAgANAAkK0xy8KgBwAgABAAEKuQgGgwApAAABNQAECgoKGwAXAAcPAA==.Sirjames:BAAANQAECgEIAwAAAA==.Sisterwife:BAAANQADCgEIAgAAAA==.',
Sk='Skelix:BAACNQAFFH8uAAIWAAkKxB+iAAAZAwAWAAkKxB+iAAAZAwA1AAQKfy8AAxYACQpLJmMFAJwDABYACQpLJmMFAJwDAAYAAwpVF6baAN8AAAAA.Skunkpaw:BAAANQAECgEIAwAAAA==.Skysong:BAACNQAFFH8VAAQeAAcKQB0yAQBAAQAeAAYKTh8yAQBAAQAmAAEKBxXfCgBSAAAPAAEKeAUJGQA+AAA1AAQKfyYABB4ACgpJIYYJANkCAB4ACgpJIYYJANkCAA8AAwp/BaZBAJQAACYAAQrwI74UAGkAAAAA.',
Sl='Slashedeye:BAABNQAECn9BAAIkAAkKFRSWAgASAgAkAAkKFRSWAgASAgAAAA==.Slimgucci:BAAANQADCggICAAAAA==.',
Sn='Snowfox:BAAANQADCgIIAgAAAA==.Snowynn:BAABNQAECn8gAAMQAAkKfhaFFAAdAgAQAAkKfhaFFAAdAgACAAMKxggGMgCDAAAAAA==.Snubby:BAABNQAECn8cAAMSAAkKtCJFOwCiAgASAAcKmyFFOwCiAgATAAIKcyVYOgDYAAAAAA==.',
So='Solheim:BAAANQABCgUIBQAAAA==.Sonari:BAAANQADCgYIBgAAAA==.',
Sp='Spankz:BAAANQAECgQICQAAAA==.Spathi:BAAANQAFFAMIBAAAAA==.Spicymeatbal:BAAANQADCgEIAgAAAA==.',
St='Stepz:BAAANQAECgEIAgAAAA==.Strathz:BAABNQAECn8iAAMSAAkKfRw0NQC1AgASAAkKMxk0NQC1AgATAAQKahyvKAA0AQAAAA==.Stregobor:BAAANQAECgUICAABNQAECgoKLgAFAKAeAA==.Striker:BAAANQAECggICwAAAA==.Strongish:BAAANQADCgUIBQAAAA==.',
Su='Summerset:BAAANQAECgIIAQAAAA==.Sunstrider:BAAANQADCgMIBgAAAA==.Superdonkey:BAAANQADCgYICwABNQAFFAcIFwAZANMWAA==.Sushi:BAAANQADCgIIAgAAAA==.Suva:BAAANQADCgYIBgAAAA==.',
Sy='Sylatis:BAAANQAECgYIDAABNQAFFAYIIAASAOoiAA==.Sylätis:BAAANQAFFAEIAwABNQAFFAYIIAASAOoiAA==.',
['Sö']='Söultender:BAAANQADCgMIAwABNQAECgYIDQAVAAAAAA==.',
['Sø']='Sølidus:BAAANQAECgQIDwABNQAFFAcIEwAIAMgbAA==.',
Ta='Taintedhealz:BAAANQADCgEIAQAAAA==.Talys:BAACNQAFFH8eAAIPAAgKAxYcBAA8AgAPAAgKAxYcBAA8AgA1AAQKf0IAAg8ACgrnJCUBAMYDAA8ACgrnJCUBAMYDAAAA.Tankly:BAAANQADCgMIBAAAAA==.',
Te='Tehchosen:BAAANQADCggICAAAAA==.Terramor:BAAANQAECgIIBAAAAA==.Texicola:BAABNQAECn9EAAIEAAoKrh/RAgAvAwAEAAoKrh/RAgAvAwAAAA==.',
Th='Thabdeady:BAAANQAECgQICgABNQAECgoKQwAeAHcYAA==.Thabk:BAABNQAECn9DAAQeAAoKdxhwBABkAgAeAAoKdxhwBABkAgAmAAgKnwt9DgBfAQAPAAYKCQs9LQA7AQAAAA==.Thaelorn:BAAANQADCgEIAQAAAA==.Thesyra:BAABNQAECn8nAAMPAAoKLQj/JwB3AQAPAAoKLQj/JwB3AQAmAAcKIg3ICwAFAQAAAA==.Thundercrash:BAAANQADCgUIBgAAAA==.Thunderjeed:BAAANQAECgcICwABNQAFFAYIEwAZAIQcAA==.Thurmond:BAABNQAECn8hAAMBAAoKWhtnOwA0AgABAAoKthZnOwA0AgANAAYKBBn9WQCLAQAAAA==.Thurmoons:BAABNQAECn8UAAMYAAkK6RsOEgBqAgAYAAkKzRkOEgBqAgAQAAUKJB7cHgCoAQABNQAECgoKIQABAFobAA==.Thurmund:BAAANQADCgYIBgABNQAECgoKIQABAFobAA==.',
Ti='Tiamat:BAAANQAECgEIAQAAAA==.Tidalanxiety:BAAANQAECgQIBQAAAA==.',
To='Toastay:BAAANQAECgQIDgAAAA==.Toastz:BAABNQAECn9BAAIHAAoKXiJuCwCCAwAHAAoKXiJuCwCCAwAAAA==.Toebeanz:BAAANQAECgUIDAAAAA==.Tokken:BAACNQAFFH8ZAAIMAAcKKBMcBwBPAgAMAAcKKBMcBwBPAgA1AAQKfzcAAgwACgq9Hmc9ANMCAAwACgq9Hmc9ANMCAAAA.Totemi:BAAANQADCgMIAwAAAA==.',
Tr='Treebeast:BAABNQAECn8WAAMGAAkKER+5LQDGAgAGAAkKER+5LQDGAgAWAAEKnQE3KAElAAAAAA==.Troile:BAAANQAECgYIDAAAAA==.Trojen:BAACNQAFFH8IAAIbAAQKVg72GQDYAAAbAAQKVg72GQDYAAA1AAQKfyAAAxsACQp2GpaDACECABsACApyGpaDACECABoACAoYC3J8AKQBAAAA.Trolladin:BAAANQADCgYICgABNQADCggIJwAVAAAAAA==.',
Tw='Twig:BAABNQAECn8nAAMYAAkKGhgyLAB5AgAYAAkKGhgyLAB5AgADAAQKLA+3QgC+AAAAAA==.',
Ty='Tyras:BAABNQAECn8YAAMRAAYKFhCwEwC7AAAZAAUKzQ2GRQDvAAARAAUKFhCwEwC7AAAAAA==.',
Tz='Tzarina:BAAANQAECgEIAQAAAA==.',
['Tâ']='Tâz:BAABNQAECn8yAAMWAAoKix/KKgC4AgAWAAoKix/KKgC4AgAGAAEKAADUBwEAAAAAAA==.',
Ul='Ulanda:BAABNQAECn9NAAMCAAoKvxeVCAAbAgAQAAkKNhQzEQBNAgACAAkKghaVCAAbAgAAAA==.',
Um='Umasi:BAACNQAFFH8hAAIiAAgK1CROAAABAwAiAAgK1CROAAABAwA1AAQKfzUAAiIACgqdJrEBAL8DACIACgqdJrEBAL8DAAAA.',
Un='Underbogg:BAAANQADCgUIBQAAAA==.Unus:BAAANQAECgIIBAABNQAECgoKLgAFAKAeAA==.',
Ut='Utastebad:BAAANQADCggIDAAAAA==.',
Va='Vagabundo:BAAANQAECgMIAwABNQAECgYICwAVAAAAAA==.Vail:BAAANQADCgUIBgAAAA==.Vainquish:BAAANQADCgEIAQAAAA==.Valamaldoran:BAAANQADCgUIBgAAAA==.Vanthil:BAAANQAECgIIAgAAAA==.Vaporize:BAAANQAECgIIAgAAAA==.',
Ve='Venandi:BAABNQAECn8UAAIFAAgKzAyB4ADIAQAFAAgKzAyB4ADIAQAAAA==.Vengened:BAABNQAECn8vAAIMAAoK2hfcVwCEAgAMAAoK2hfcVwCEAgAAAA==.Verax:BAAANQAECgIIAgAAAA==.Verestrasz:BAAANQADCgIIBAAAAA==.',
Vg='Vgly:BAAANQAECgQIEAAAAA==.',
Vi='Vilous:BAABNQAECn81AAIjAAoKQCZwAABwAwAjAAoKQCZwAABwAwAAAA==.',
Vy='Vyisesham:BAABNQAECn80AAMGAAoKKxpNQAB0AgAGAAkKJRlNQAB0AgAWAAkKSBaNUwCSAQAAAA==.',
['Vý']='Výce:BAAANQAECgEIAQAAAA==.',
Wa='Wagtar:BAAANQADCgYIDAABNQADCgQIBgAVAAAAAA==.Warzug:BAAANQADCgQIBAAAAA==.',
We='Wesjin:BAABNQAECn8kAAMnAAoKrROWFAAyAgAnAAoKrROWFAAyAgAZAAEKHQM/dgAiAAAAAA==.Wez:BAAANQAECgcICwAAAA==.',
Wh='Whiskee:BAACNQAFFH8GAAICAAIKfRVZAgCPAAACAAIKfRVZAgCPAAA1AAQKfycAAwIACgqaIgMFADUDAAIACQqQIQMFADUDABAABwrzIHARAEoCAAAA.',
Wo='Wooglone:BAAANQAECgQJBAAAAA==.',
Wy='Wyndia:BAABNQAECn8ZAAIFAAoK9RshZQC0AgAFAAoK9RshZQC0AgAAAA==.Wyndibear:BAAANQAECgMIAwAAAA==.',
Xa='Xanthos:BAAANQAECgEIAQABNQAECgYICgAVAAAAAA==.',
Xb='Xbert:BAAANQADCgcIBwAAAA==.',
Xe='Xela:BAAANQAECgMICwABNQAECgoKLgAFAKAeAA==.Xenophontes:BAABNQAECn8bAAMEAAoKXR6jGgAeAQAFAAkK/BvKtQAYAgAEAAUKFR2jGgAeAQABNQAFFAcIEwAIAMgbAA==.Xeris:BAAANQADCgEIAQAAAA==.',
Xi='Xihuang:BAABNQAECn89AAIYAAoK6RhNFwAmAgAYAAoK6RhNFwAmAgABNQAFFAUICQAdAHAGAA==.Xiia:BAAANQAECgQIBAAAAA==.',
Xo='Xouu:BAAANQAFFAUIBAABNQAFFAgIBgAWADoRAA==.',
Xx='Xxuu:BAAANQAFFAgIAwABNQAFFAgIBgAWADoRAA==.Xxuusham:BAACNQAFFH8GAAIWAAYKOhFoBwDkAQAWAAYKOhFoBwDkAQA1AAQKf0cAAhYACgrTJSICAMYDABYACgrTJSICAMYDAAAA.Xxuuspr:BAAANQAECggIAgABNQAFFAgIBgAWADoRAA==.',
Ya='Yaoguai:BAABNQAECn8+AAMYAAoKRhsAFwArAgAYAAoKRhsAFwArAgAQAAEKHwm6YAAzAAAAAA==.Yasei:BAAANQAECgQIBAAAAA==.Yawgmoth:BAABNQAECn8ZAAQUAAgKzgy/GgCuAAASAAgKwQlvpwDRAAAUAAUKDA2/GgCuAAATAAEKFgQthAAmAAABNQAECgkJIQARALcbAA==.',
Za='Zakkha:BAAANQADCgMIBAABNQADCggIEgAVAAAAAA==.Zaleris:BAAANQAECgQIBQAAAA==.Zaryana:BAAANQAECgcIEQAAAA==.',
Ze='Zephon:BAABNQAECn8aAAIHAAgK3g3zlQDcAQAHAAgK3g3zlQDcAQAAAA==.Zerrk:BAAANQADCgEIAQAAAA==.',
Zo='Zotiel:BAAANQAFFAQIBAABNQAFFAgIMQABAPcdAA==.',
Zy='Zynisch:BAAANQADCgcIFAAAAA==.',
['Ær']='Æris:BAAANQADCgMIAwAAAA==.',
['Ìr']='Ìroh:BAAANQADCgUIBgABNQAECgYIDQAVAAAAAA==.',
['Øl']='Øld:BAAANQADCgEIAwAAAA==.',
['Ør']='Ørangéjuice:BAAANQADCgEIAQAAAA==.',
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
