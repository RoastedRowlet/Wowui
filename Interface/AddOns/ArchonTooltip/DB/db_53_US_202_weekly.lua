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

local lookup = {'DeathKnight-Unholy','Druid-Restoration','Druid-Feral','Mage-Frost','Mage-Arcane','Shaman-Elemental','Priest-Holy','DemonHunter-Havoc','DemonHunter-Vengeance','Shaman-Enhancement','Warrior-Arms','DeathKnight-Blood','Rogue-Assassination','Evoker-Preservation','Druid-Guardian','Monk-Brewmaster','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Unknown-Unknown','Shaman-Restoration','DemonHunter-Devourer','Monk-Windwalker','Druid-Balance','Paladin-Holy','Paladin-Retribution','Hunter-BeastMastery','Hunter-Marksmanship','Rogue-Subtlety','Evoker-Devastation','Rogue-Outlaw','DeathKnight-Frost','Priest-Shadow','Paladin-Protection','Warrior-Fury','Mage-Fire','Priest-Discipline','Evoker-Augmentation','Monk-Mistweaver',}
local provider = {region='US',realm='Spirestone',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abduon:BAAANQADCgcICwAAAA==.',
Ac='Aciddeath:BAAANQAECgEIAQABNQAFFAUIEQABAP8RAA==.',
Ad='Admaris:BAACNQAFFH8JAAMCAAIKMhqUBgCoAAACAAIKMhqUBgCoAAADAAIKbRFkAwCaAAA1AAQKfzIAAwIACgrKH/wMAP8CAAIACgrKH/wMAP8CAAMABwqQIdIJAKMCAAAA.',
Ae='Aelis:BAAANQABCgEIAQAAAA==.',
Ag='Agni:BAACNQAFFH8TAAMEAAcK1BJRAwDrAAAFAAQKuRCiJwBLAQAEAAMKOxRRAwDrAAA1AAQKfyUAAwUACgqiIThLAOsCAAUACgqiIThLAOsCAAQAAQpCGP1JADEAAAAA.',
Ak='Akkadian:BAAANQADCggICwAAAA==.',
Al='Alnasham:BAACNQAFFH8SAAIGAAYKEBo2AgBoAQAGAAYKEBo2AgBoAQA1AAQKfyoAAgYACgoAIoUUAE4DAAYACgoAIoUUAE4DAAAA.Alnava:BAAANQAECgcIDwAAAA==.Alvoka:BAABNQAECn8VAAIFAAcKLRbv0QDiAQAFAAcKLRbv0QDiAQAAAA==.',
Am='Amarillos:BAAANQAECggIEQAAAA==.Amarillys:BAABNQAECn8kAAIHAAoKVxnXPQBzAgAHAAoKVxnXPQBzAgAAAA==.Ammutseba:BAABNQAECn8eAAMIAAkKtRc/EQBhAQAIAAkK8RY/EQBhAQAJAAMK2hZFIgCwAAAAAA==.',
An='Anfall:BAACNQAFFH8NAAIKAAUKJhZwAQD6AAAKAAUKJhZwAQD6AAA1AAQKfysAAgoACgrOIEsIAPUCAAoACgrOIEsIAPUCAAAA.Angermeier:BAABNQAECn8sAAILAAkKERXeCAAuAgALAAkKERXeCAAuAgAAAA==.Angers:BAAANQAECgIIAgABNQAECgkJLAALABEVAA==.Angrylady:BAAANQAECgEIAQAAAA==.Anjuna:BAAANQADCgUIBQAAAA==.Anohru:BAAANQAECggIBQAAAA==.Anthos:BAAANQAECggIDQAAAA==.Antikreist:BAAANQADCgQJBAAAAA==.Anyawnka:BAAANQABCggIGAAAAA==.',
Ap='Aphotic:BAAANQAECgIIAQAAAA==.',
Ar='Ards:BAAANQADCgIIAwAAAA==.Armanite:BAAANQAECgQIBQABNQAECgoKHAABAOUaAA==.Arthaniis:BAABNQAECn8YAAIGAAcKKCESSwBKAgAGAAcKKCESSwBKAgAAAA==.',
As='Asystoli:BAABNQAECn8YAAMFAAgKbRIjWgAJAQAFAAcKDxMjWgAJAQAEAAEKQw84GQA/AAAAAA==.',
At='Atheria:BAAANQADCgYICAAAAA==.Attackheli:BAAANQAECgMIDAAAAA==.',
Au='Audideath:BAAANQAECgQICQAAAA==.Auurdeath:BAAANQADCggIEwAAAA==.',
Av='Av:BAAANQADCgIIBQAAAA==.',
Aw='Aw:BAACNQAFFH8bAAIIAAYKfh+qAwBFAgAIAAYKfh+qAwBFAgA1AAQKfyIAAggACQoTJvQFAJYDAAgACQoTJvQFAJYDAAAA.',
Ax='Ax:BAECNQAFFH8QAAMBAAYKzBqsBwCeAQABAAUKzBqsBwCeAQAMAAEKAADZOQAfAAA1AAQKfyUAAgEACgrbIDIkALECAAEACgrbIDIkALECAAAA.',
Az='Azzazinzblo:BAAANQADCgUIBQAAAA==.',
['Aÿ']='Aÿa:BAAANQAECgUIBwAAAA==.',
Ba='Baast:BAAANQADCgUIBQAAAA==.Bamph:BAAANQAECgcIDAAAAA==.Bangbang:BAAANQAECgcIDwAAAA==.Batez:BAAANQAECgQIBAABNQAFFAYIEQANAO8OAA==.',
Bd='Bdk:BAABNQAECn8UAAIMAAkKuR2rGQDgAgAMAAkKuR2rGQDgAgAAAA==.Bdog:BAAANQAECgEIAwAAAA==.',
Be='Beeatinu:BAAANQADCgYICgAAAA==.Beers:BAAANQAECggIBwAAAA==.Beledros:BAABNQAECn8cAAIOAAkKVBP4FQBWAgAOAAkKVBP4FQBWAgAAAA==.Beni:BAABNQAECn9CAAMPAAoKiR+KAQCDAgAPAAoKiR+KAQCDAgADAAUK/RLEHAA7AQAAAA==.Benson:BAABNQAECn8hAAIQAAkKoxwsCACuAgAQAAkKoxwsCACuAgAAAA==.Bensonadin:BAAANQAECgYIBgAAAA==.Berd:BAAANQAECggIBgAAAA==.',
Bi='Bina:BAAANQAECgQIBQAAAA==.Birblock:BAACNQAFFH8gAAQRAAYK6iKNAgBqAgARAAYK6iKNAgBqAgASAAIKygE5EwB6AAATAAEK/BkXCABiAAA1AAQKfyMABBEACQotJiYzALwCABEABwo1JiYzALwCABIABwq3GxUUAM8BABMAAQoAAFYpAEcAAAAA.',
Bo='Bobbo:BAAANQADCgYJBwAAAA==.',
Br='Brek:BAAANQAECgYIDAAAAA==.Brewtherguy:BAABNQAECn8iAAIQAAkKAB1oBwDGAgAQAAkKAB1oBwDGAgAAAA==.Brother:BAAANQADCgIIAgAAAA==.Bruceshepard:BAAANQADCgQICQABNQAECgIIBAAUAAAAAA==.Brutebuffalo:BAABNQAECn8lAAMVAAkKqh2uIwDYAgAVAAkKqh2uIwDYAgAGAAUKQBH/rQA3AQAAAA==.Bruteflappy:BAAANQADCggICAABNQAECgkJJQAVAKodAA==.Brutetestify:BAAANQADCggICAABNQAECgkJJQAVAKodAA==.',
Bu='Bubbleboi:BAAANQADCgYICAAAAA==.Bubblebôy:BAAANQAECgIIAgAAAA==.Bublz:BAAANQAECgcIEgAAAA==.',
['Bâ']='Bâra:BAABNQAECn8eAAIBAAoKahqhJQCoAgABAAoKahqhJQCoAgAAAA==.',
Ca='Carnal:BAAANQADCgUIBQAAAA==.',
Ce='Cedren:BAACNQAFFH8KAAIIAAQKohKgDgAfAQAIAAQKohKgDgAfAQA1AAQKfywAAwgACgqWGTEjAIICAAgACgqZGDEjAIICABYACAotE7srAOQBAAAA.Ceewhya:BAAANQAECgEIAQAAAA==.Celestika:BAAANQABCgIIAgAAAA==.Cerari:BAAANQAECgEJAQAAAA==.',
Ch='Chalix:BAAANQAECgEIAgAAAA==.Chama:BAABNQAECn8aAAIWAAkKpxI0JAAmAgAWAAkKpxI0JAAmAgAAAA==.Cheapheal:BAABNQAECn89AAIPAAoK8x66AQBvAgAPAAoK8x66AQBvAgAAAA==.Cheapsnipe:BAAANQAECgIIAwABNQAECgoKPQAPAPMeAA==.Cheburashka:BAACNQAFFH8XAAIGAAYKLySrBABIAgAGAAYKLySrBABIAgA1AAQKfyAAAgYACgpIIakoAN8CAAYACgpIIakoAN8CAAAA.Chimerabob:BAAANQAECgQIBQAAAA==.Chopsuey:BAAANQAECggIAwAAAA==.Chunkymonkey:BAACNQAFFH8XAAIXAAcK0xa7BADwAQAXAAcK0xa7BADwAQA1AAQKfzEAAhcACgrHH88LABkDABcACgrHH88LABkDAAAA.',
Ci='Cidren:BAAANQAECgEIAQAAAA==.',
Cl='Clappncheeks:BAAANQAECgcIEgAAAA==.Claudefrollo:BAABNQAECn8YAAIYAAkKTAk1IgDgAAAYAAkKTAk1IgDgAAAAAA==.',
Cr='Crankyelf:BAAANQABCgEIAQAAAA==.Crimsa:BAABNQAECn8pAAITAAkKawQ5DgBvAQATAAkKawQ5DgBvAQAAAA==.Crimsonaxel:BAABNQAECn8hAAIGAAgKghywOwCHAgAGAAgKghywOwCHAgAAAA==.Cryogen:BAAANQAECgQJCAAAAA==.',
Cu='Cursewords:BAAANQADCgUIBQABNQAECgYIBgAUAAAAAA==.',
Da='Daemonproph:BAAANQADCgYIDAAAAA==.Dakini:BAABNQAECn8mAAIZAAkKBR6xCwAJAgAZAAkKBR6xCwAJAgAAAA==.Dam:BAAANQADCgUIBQABNQAECgkJIAAMABgXAA==.Dangerruss:BAAANQAECgUICQAAAA==.Darkspartan:BAAANQAECgUIBQAAAA==.Dashytash:BAABNQAECn8sAAIJAAkKWRyCAQAFAgAJAAkKWRyCAQAFAgAAAA==.Dawnsoul:BAAANQAECgYIDQAAAA==.',
De='Deathschosen:BAAANQADCgQIBAAAAA==.Demb:BAAANQAECgQIBwAAAA==.Demonicchoas:BAABNQAECn8tAAMSAAoKOh/MDAArAgASAAcKfhzMDAArAgARAAkKOR6dGQCLAQAAAA==.Denagorn:BAABNQAECn83AAIaAAoKKCQeEQCEAwAaAAoKKCQeEQCEAwABNQAFFAcIJQABAM4gAA==.Denaki:BAAANQADCgIIAgABNQAFFAcIJQABAM4gAA==.Denhunt:BAABNQAECn8WAAMbAAoKXRsHIgAPAwAbAAoKUBsHIgAPAwAcAAQKLRmkEwDoAAABNQAFFAcIJQABAM4gAA==.Dentsama:BAAANQADCgEIAQAAAA==.Deplete:BAAANQADCgIJAgABNQAECgoKMAAYABMaAA==.Deutzfr:BAABNQAECn8YAAIJAAkKfxwZBwCfAgAJAAkKfxwZBwCfAgAAAA==.Develop:BAAANQAECgQIBAAAAA==.Devos:BAABNQAECn8YAAMGAAcKgBMrcgDKAQAGAAcKgBMrcgDKAQAVAAQKRQ6X1gC6AAABNQAFFAUICQAGAIcEAA==.',
Di='Dizzleman:BAAANQAECggICgAAAA==.',
Do='Dominant:BAABNQAECn8kAAMFAAoKih0LWQDOAgAFAAoKih0LWQDOAgAEAAEKAAA5SgAxAAAAAA==.',
Dp='Dpssos:BAAANQAECgcIDQAAAA==.',
Dr='Draco:BAAANQADCgcIBwAAAA==.Drag:BAAANQADCgYICAAAAA==.Dreadmar:BAAANQADCgYICAAAAA==.Drock:BAABNQAECn8xAAIWAAoKSSAkAQC7AgAWAAoKSSAkAQC7AgAAAA==.Druidgale:BAAANQAECgIIAwAAAA==.Drybonez:BAAANQAECgYICAAAAA==.Drygth:BAAANQADCgMIBgABNQAECgoKLQAdAJ0gAA==.Dräkarnoir:BAAANQADCggICAAAAA==.',
Dt='Dtb:BAACNQAFFH8SAAIMAAUKNSAUCADgAQAMAAUKNSAUCADgAQA1AAQKfy4AAgwACgp4JeYEAKMDAAwACgp4JeYEAKMDAAAA.',
Du='Dushimaya:BAABNQAECn8tAAIZAAoKtSOOBwCOAwAZAAoKtSOOBwCOAwAAAA==.',
Dv='Dvil:BAAANQAECgQIBQABNQAECgoKMQAWAEkgAA==.',
Dw='Dwyndi:BAAANQAECgcICAAAAA==.',
Ei='Eisador:BAABNQAECn8VAAIbAAcKWAtIqAC1AQAbAAcKWAtIqAC1AQAAAA==.',
El='Elsen:BAAANQAECgUIDQAAAA==.Elsha:BAABNQAECn8hAAIQAAkKtxtdCACmAgAQAAkKtxtdCACmAgAAAA==.',
Em='Emp:BAAANQAECgUIBgAAAA==.',
Er='Erilee:BAAANQAECgUICgAAAA==.',
Ev='Evelira:BAABNQAFFH8SAAIHAAYKPhu+BwARAgAHAAYKPhu+BwARAgAAAA==.',
Ey='Eyja:BAAANQADCgEIAgAAAA==.',
Ez='Ezailas:BAAANQAECgQIBQAAAA==.Ezpzndaheezy:BAAANQADCgYIBgABNQAECgoKMQAeAMcRAA==.',
Fa='Fatherangus:BAAANQAECggICAAAAA==.Fathercoast:BAAANQAECgYICwAAAA==.',
Fe='Fearful:BAACNQAFFH8FAAIZAAMKYAJkGwC+AAAZAAMKYAJkGwC+AAA1AAQKfyIAAhkACQr5Ff5GAEoCABkACQr5Ff5GAEoCAAAA.Felstrider:BAAANQADCgUIBQAAAA==.Ferador:BAACNQAFFH8XAAMbAAYK9BaNEABUAQAbAAQKjRmNEABUAQAcAAUKDQ8gDwBMAQA1AAQKfygAAxsACgp1HuxDAJ8CABsACgp1HuxDAJ8CABwABgq+Ero/AFUBAAAA.Feythe:BAACNQAFFH8jAAIMAAoKdgurAAAiAgAMAAoKdgurAAAiAgA1AAQKfxcAAgwACgreFxQ5ACICAAwACgreFxQ5ACICAAAA.',
Fi='Figgleslock:BAAANQADCgUIBQAAAA==.',
Fl='Flakester:BAABNQAECn8lAAIHAAcKjCJzCgA9AgAHAAcKjCJzCgA9AgAAAA==.Fleebly:BAABNQAECn8iAAIWAAoKiBnXGQCLAgAWAAoKiBnXGQCLAgAAAA==.',
Fn='Fndruid:BAAANQAECgIIAgAAAA==.',
Fo='Fourbees:BAABNQAECn8gAAIaAAkK8wvZrQDDAQAaAAkK8wvZrQDDAQAAAA==.',
Fu='Fursure:BAAANQAECgMIAwAAAA==.',
Ga='Garfal:BAAANQAECgIIAwAAAA==.Gather:BAAANQABCgQIBAABNQAECgoKOwAVABsZAA==.',
Gi='Gilgamesh:BAAANQAECgcIDAAAAA==.',
Go='Gorobob:BAAANQAECgIIBAAAAA==.',
Gr='Graygkl:BAAANQAECgUIDwAAAA==.Greshanwise:BAABNQAECn8YAAICAAgKjAcpQgAYAQACAAgKjAcpQgAYAQAAAA==.Grimreaper:BAABNQAECn8wAAIfAAoK0xd/AQB7AQAfAAoK0xd/AQB7AQAAAA==.Groa:BAAANQABCgQIBgAAAA==.Groag:BAABNQAECn8tAAMdAAoKnSCbBQAtAwAdAAoKlyCbBQAtAwANAAgKYxuJKgBBAgAAAA==.',
Ha='Haarp:BAAANQAECgUIDwAAAA==.Hakü:BAAANQAECgcIBwAAAA==.Hammered:BAAANQAECgYIDQAAAA==.Hardwire:BAAANQAECgEIAQAAAA==.',
He='Heartred:BAAANQADCgYIBgAAAA==.Heifer:BAACNQAFFH8FAAIYAAIKWw3nIQCEAAAYAAIKWw3nIQCEAAA1AAQKfyQAAhgACQrRIZcZAPsCABgACQrRIZcZAPsCAAAA.Hemophilia:BAABNQAECn8tAAIBAAgKwBKPDwBhAQABAAgKwBKPDwBhAQAAAA==.Heydk:BAABNQAECn8YAAMgAAkKlRuZWgA/AQAgAAUKRhqZWgA/AQABAAYKHBtBfgAjAQAAAA==.Heydruid:BAAANQAECgcIDQABNQAECgkJGAAgAJUbAA==.',
Ho='Hollowshädix:BAAANQAECgEIAQAAAA==.Holyanxiety:BAAANQADCgYIBgAAAA==.Holydave:BAAANQAECgMIBAAAAA==.Holymentos:BAABNQAECn8eAAMhAAgKOQuuLwCmAQAhAAgKOQuuLwCmAQAHAAUK4AIwygDDAAABNQAECgoKKAAiANYPAA==.Hottsauce:BAABNQAECn8cAAIKAAkKQBwwDQCbAgAKAAkKQBwwDQCbAgAAAA==.Hottsaucefel:BAAANQAECgYIBgAAAA==.',
Hu='Hundard:BAAANQADCgIIAgAAAA==.Huntersmarc:BAAANQAECgIIBQAAAA==.Hushhides:BAABNQAECn8WAAIdAAkK8g2CGAAYAgAdAAkK8g2CGAAYAgAAAA==.Hushrage:BAAANQAECggICwABNQAECgkJFgAdAPINAA==.',
Ia='Iamachick:BAAANQAECgEIAQAAAA==.',
Ib='Ibetrollinya:BAAANQAECgcICgABNQAECgoKJwAjAD0kAA==.Iblisshaytan:BAABNQAECn86AAIIAAoKcRtACQCxAQAIAAoKcRtACQCxAQABNQAFFAQIBwAdAHAGAA==.Ibtrollin:BAAANQADCggIJQAAAA==.',
Ig='Ignacious:BAAANQAECgEIAQAAAA==.',
Il='Illumina:BAACNQAFFH8IAAIiAAQKQxYoAgDxAAAiAAQKQxYoAgDxAAA1AAQKfxgAAiIACQqeIZkIABQDACIACQqeIZkIABQDAAAA.',
Io='Ionissa:BAABNQAECn8nAAIbAAoK4xv8LwDdAgAbAAoK4xv8LwDdAgAAAA==.',
Ir='Ironbreaker:BAAANQAECgcICAAAAA==.',
Is='Ischia:BAACNQAFFH8JAAMHAAQK5wgCGwATAQAHAAQK5wgCGwATAQAhAAEKbAEPGwA0AAA1AAQKfzgAAwcACQrrGvU2AIwCAAcACQrrGvU2AIwCACEAAgrUE55pAFsAAAAA.',
Ja='Jallypally:BAAANQADCgIIAgAAAA==.Jarl:BAAANQADCgYICwAAAA==.',
Jc='Jch:BAACNQAFFH8eAAIbAAcK2h5iAQCCAgAbAAcK2h5iAQCCAgA1AAQKfzAAAxsACgrIJOUTAE8DABsACgrIJOUTAE8DABwAAQpkFhCGADgAAAAA.',
Je='Jeay:BAAANQAECgEJAQAAAA==.Jedijeed:BAACNQAFFH8NAAIXAAUKOhvYAQBSAQAXAAUKOhvYAQBSAQA1AAQKfzIAAhcACgr7IUoGAGwDABcACgr7IUoGAGwDAAAA.Jedikepjr:BAACNQAFFH8GAAIaAAMKZQmRGwDLAAAaAAMKZQmRGwDLAAA1AAQKfxwAAhoACgr3GQQoAIcBABoACgr3GQQoAIcBAAE1AAUUBQgNABcAOhsA.Jenova:BAAANQADCgUIBwAAAA==.Jepage:BAABNQAECn8vAAQEAAkKzx81AQAkAgAEAAkKNx81AQAkAgAkAAUK/hkSBAB/AQAFAAUKkhXAHAFcAQAAAA==.Jess:BAAANQABCgIIAgAAAA==.',
Jo='Jolyne:BAAANQAECgQIBAAAAA==.',
Jp='Jprottsoo:BAABNQAECn8gAAIYAAgKqh7oIgC4AgAYAAgKqh7oIgC4AgAAAA==.',
Ju='Jubei:BAABNQAECn8kAAIjAAgKVQ7uDQDUAQAjAAgKVQ7uDQDUAQAAAA==.',
Ka='Kagayaki:BAAANQAECgMIAwAAAA==.Kalmya:BAABNQAECn8nAAMCAAgKpQ0YMACaAQACAAgKpQ0YMACaAQADAAEKAAAhRgAuAAAAAA==.Kalrath:BAAANQAECgIIAgABNQAECgoKHAABAOUaAA==.Kasheek:BAAANQADCggICAAAAA==.',
Ke='Keizzer:BAAANQAECgcICwABNQAECgkJHQAHAPcbAA==.Keshisaru:BAAANQADCgQIBAAAAA==.',
Kh='Khazra:BAAANQAECgMIBgAAAA==.',
Ki='Kierràalexis:BAAANQADCgYIBgAAAA==.',
Kl='Klunder:BAABNQAECn8qAAIVAAkKoCLiHQD1AgAVAAkKoCLiHQD1AgAAAA==.',
Ko='Korris:BAABNQAECn8lAAMbAAoKkBylMADaAgAbAAoKkBylMADaAgAcAAEK1wLwnAAiAAAAAA==.Kostik:BAAANQADCgUIBQAAAA==.',
Kr='Kridillis:BAABNQAECn8nAAIIAAoKgR0dCADDAQAIAAoKgR0dCADDAQAAAA==.',
Kt='Ktang:BAAANQAFFAEIAQAAAA==.',
Ky='Kybinc:BAAANQADCgQIBAAAAA==.',
['Kí']='Kírã:BAAANQABCgIIBAAAAA==.',
La='Lawls:BAAANQADCgQIBwAAAA==.Lazybigger:BAAANQAECgIIAgAAAA==.Lazycow:BAABNQAECn8sAAIPAAoKWxTcEwAmAgAPAAoKWxTcEwAmAgAAAA==.Lazyfrost:BAABNQAECn8mAAIFAAoKmA+dmwBJAgAFAAoKmA+dmwBJAgAAAA==.',
Le='Lethò:BAABNQAECn8pAAMZAAoKFyO0CACDAwAZAAoKFyO0CACDAwAaAAQK1xf0MwHMAAAAAA==.Lethô:BAAANQAECgQICQAAAA==.Lethö:BAAANQAECgIIBQAAAA==.',
Li='Liesx:BAACNQAFFH8RAAMNAAYK7w5JBQDfAQANAAYKIw1JBQDfAQAdAAYKTggjBAAWAQA1AAQKfxoAAw0ACQr4HLwUANUCAA0ACArtHrwUANUCAB0ABQrLD6caAAwBAAAA.Lilzarthe:BAAANQAECgQIDAAAAA==.',
Lo='Loerasdh:BAABNQAECn8eAAIIAAgK3CVICgBeAwAIAAgK3CVICgBeAwAAAA==.Loko:BAACNQAFFH8SAAIYAAYKTBVhCQDpAQAYAAYKTBVhCQDpAQA1AAQKfysAAhgACgoLI14TACwDABgACgoLI14TACwDAAAA.Looio:BAAANQADCgIIAgAAAA==.',
Lu='Lucien:BAAANQABCgQIBAAAAA==.Lumièrevide:BAAANQADCggICAAAAA==.Luxxus:BAABNQAECn8dAAIHAAkK9xtcKwC7AgAHAAkK9xtcKwC7AgAAAA==.',
Ly='Lyesx:BAABNQAECn8hAAMbAAkKeiFWFwA9AwAbAAkKeiFWFwA9AwAcAAMKpxSTVwDHAAABNQAFFAYIEQANAO8OAA==.Lyndsy:BAAANQADCgUIBQAAAA==.Lyri:BAAANQADCgMIAwAAAA==.',
Ma='Macros:BAAANQAECgQICQAAAA==.Magai:BAAANQABCggIEQAAAA==.Mageyousad:BAAANQADCgEIAgAAAA==.Makhtor:BAAANQAECgMIBQAAAA==.Mallaer:BAABNQAECn8fAAIHAAoKdB0yGgALAwAHAAoKdB0yGgALAwAAAA==.Malícíous:BAABNQAECn8pAAIRAAgKIBRqLABDAQARAAgKIBRqLABDAQAAAA==.Mantakore:BAACNQAFFH8IAAIOAAMKUQUDCAChAAAOAAMKUQUDCAChAAA1AAQKfysAAg4ACgpKE+EVAFcCAA4ACgpKE+EVAFcCAAAA.Marcdruid:BAAANQAECgUICQAAAA==.Maubles:BAAANQADCggICAABNQAFFAUIDwAiAMwNAA==.',
Mc='Mcdirk:BAAANQAECggICAAAAA==.',
Me='Menopaws:BAABNQAECn8xAAIPAAoKdCVXAQDUAwAPAAoKdCVXAQDUAwAAAA==.Merrtt:BAAANQAECgYIBgAAAA==.Mertrik:BAABNQAECn8eAAMVAAkKtiIODQBYAwAVAAkKtiIODQBYAwAGAAMKiBDZ7QC7AAAAAA==.',
Mi='Midk:BAAANQAECgIIAwAAAA==.Mikayy:BAACNQAFFH8QAAIdAAUKAiNaAwAGAgAdAAUKAiNaAwAGAgA1AAQKfzkAAh0ACgoCJv0AAMsDAB0ACgoCJv0AAMsDAAAA.Milenko:BAABNQAECn8wAAIIAAkKVSA2AwBeAgAIAAkKVSA2AwBeAgAAAA==.Milly:BAAANQAECgYIDgABNQAECgkJMAAIAFUgAA==.',
Mo='Molfsongal:BAAANQADCgIIAgAAAA==.Monstrous:BAACNQAFFH8XAAILAAYKKRbZBAA9AQALAAYKKRbZBAA9AQA1AAQKfzIAAgsACgraHHM5AN8CAAsACgraHHM5AN8CAAAA.Moocher:BAAANQAECgEIAQAAAA==.Moonpie:BAAANQADCgUICQABNQAECgYIDQAUAAAAAA==.Mordecaii:BAAANQADCgYIDgAAAA==.Morgul:BAAANQAECgUIBgAAAA==.Morox:BAAANQAECggICQABNQAFFAcIEwAEANQSAA==.Mothman:BAAANQAECgUICQAAAA==.Moyana:BAAANQADCgEIAQAAAA==.',
Ms='Msbehaven:BAABNQAECn8mAAIRAAgK6QVXvQBSAQARAAgK6QVXvQBSAQAAAA==.',
Mt='Mthafknfreez:BAABNQAECn8eAAIEAAoKwBXRAQDlAQAEAAoKwBXRAQDlAQABNQAFFAQIBwAdAHAGAA==.',
Mu='Muffìns:BAAANQAECgQIBgAAAA==.Musashi:BAABNQAECn8iAAIHAAgKDxpZGgCjAQAHAAgKDxpZGgCjAQAAAA==.',
My='Mynuturchin:BAABNQAECn8WAAMMAAcK2BZeQwDuAQAMAAcK2BZeQwDuAQAgAAEKJApUswAsAAAAAA==.',
Na='Nagy:BAAANQAECgMIAwAAAA==.',
Ni='Night:BAABNQAECn8iAAIFAAgKmRLhtwAUAgAFAAgKmRLhtwAUAgAAAA==.Nightsecho:BAAANQAECgEIAQAAAA==.Nightshris:BAAANQAECgYIBwAAAA==.',
No='Notmehssos:BAAANQAECgcICwAAAA==.Notthechosen:BAAANQAFFAEIAQAAAA==.',
Ny='Nymeriã:BAAANQAECgUICAAAAA==.',
Ob='Obzy:BAAANQAECgcIEwAAAA==.Obzz:BAAANQADCgEIAQABNQAECgcIEwAUAAAAAA==.',
Ok='Okamy:BAAANQAECgcIDAABNQAECgQIBQAUAAAAAA==.Oknelim:BAAANQADCggICAABNQAECgkJMAAIAFUgAA==.',
Ol='Olympicjeid:BAABNQAECn8cAAMcAAgK5ROcLgDXAQAcAAgK5ROcLgDXAQAbAAEKCQY7VwE7AAABNQAFFAUIDQAXADobAA==.',
Op='Opz:BAABNQAECn8vAAMhAAoKmhf7GQB9AgAhAAoKmhf7GQB9AgAlAAIKiBbMGwCIAAAAAA==.',
Or='Orghujon:BAAANQABCgYICAAAAA==.',
Pa='Paladinfive:BAAANQAECgEIAgAAAA==.Parthos:BAAANQAECgQIDQAAAA==.Parts:BAAANQABCgEIAQABNQAECgoKJAAFAIodAA==.',
Pe='Pedro:BAAANQAECgUIDQAAAA==.Perry:BAAANQADCgIIAgAAAA==.',
Ph='Phenomenon:BAAANQAECgUICQABNQAECgYIDQAUAAAAAA==.',
Pi='Pittydafoo:BAAANQAECgIIAgAAAA==.',
Pk='Pkunkk:BAAANQAECgcICwAAAA==.',
Pl='Ploxis:BAACNQAFFH8XAAIJAAYK6BRwAAAvAQAJAAYK6BRwAAAvAQA1AAQKfxwAAgkACgoUGo0HAIwCAAkACgoUGo0HAIwCAAAA.',
Po='Polskashaman:BAABNQAECn8fAAIKAAcKsxPNFwDrAQAKAAcKsxPNFwDrAQAAAA==.Pookiebonez:BAAANQADCgIIAgABNQAECgYICAAUAAAAAA==.',
Pr='Prea:BAABNQAECn8WAAMVAAoK9BiDUQAgAgAVAAkKQBmDUQAgAgAGAAEKAAAQQgEtAAAAAA==.Premiumferal:BAABNQAECn8bAAMNAAkKECGiHQCTAgANAAkKECGiHQCTAgAdAAUKxRj4MAA2AQAAAA==.Primecarry:BAACNQAFFH8VAAIZAAYKThtlBgAIAgAZAAYKThtlBgAIAgA1AAQKfyUAAhkACgqOIM8JAHoDABkACgqOIM8JAHoDAAAA.Prine:BAABNQAECn8iAAILAAoK6xy+KwANAwALAAoK6xy+KwANAwABNQAFFAYIFQAZAE4bAA==.',
Pu='Puripuri:BAAANQAECgQIBAAAAA==.',
Qi='Qinkipa:BAAANQAECgEIAQAAAA==.',
Qo='Qovo:BAAANQABCggIDgAAAA==.',
Ra='Ragark:BAAANQADCgUIBQAAAA==.Raigko:BAABNQAECn8zAAILAAoKmSGpCQCnAwALAAoKmSGpCQCnAwAAAA==.Rainyday:BAABNQAECn8UAAIVAAYK9ApktwD+AAAVAAYK9ApktwD+AAAAAA==.Raiva:BAAANQAECggIEQAAAA==.Raivek:BAAANQAECgIIAgAAAA==.Randenton:BAAANQADCgYICAAAAA==.Randezoth:BAAANQABCggIDQABNQADCgYICAAUAAAAAA==.Randomkiller:BAAANQADCgMIAwAAAA==.Rassputen:BAABNQAECn8tAAIMAAoKSRNnIAD7AAAMAAoKSRNnIAD7AAAAAA==.',
Re='Reck:BAAANQADCgEIAQAAAA==.Redjive:BAAANQAECggIAQAAAA==.Redonkulos:BAAANQADCgMIBAAAAA==.Reliri:BAAANQADCgYICgAAAA==.Renais:BAAANQAECgMIAwAAAA==.Rex:BAABNQAECn8gAAIMAAkKGBfyMABNAgAMAAkKGBfyMABNAgAAAA==.',
Ri='Rileyesco:BAAANQABCgUIBgAAAA==.Ripskylark:BAAANQAECgIIAwAAAA==.',
Rj='Rjtheamazin:BAAANQAECgEIAQAAAA==.',
Ro='Roguen:BAACNQAFFH8HAAIdAAQKcAaeCwACAQAdAAQKcAaeCwACAQA1AAQKfzoAAx0ACgqwFtMHALMBAB0ACgqwFtMHALMBAA0AAwqGCNKCAKkAAAAA.Romirin:BAAANQADCgQIBAAAAA==.Rotan:BAAANQADCgYICwAAAA==.Roulduke:BAABNQAECn8tAAIGAAoK3QrLDQCkAQAGAAoK3QrLDQCkAQAAAA==.',
['Rù']='Rùckús:BAABNQAECn8pAAIBAAgKQR/eLgB1AgABAAgKQR/eLgB1AgAAAA==.',
Sa='Sacredmentos:BAABNQAECn8oAAMiAAoK1g9ZJgCsAQAiAAoK1g9ZJgCsAQAaAAYKagriWAATAQAAAA==.Salaen:BAAANQAECggIAQAAAA==.Sammybeans:BAAANQAFFAEIAQAAAA==.Sapito:BAAANQADCgYICgAAAA==.Saulotsalubr:BAAANQADCgQIBAAAAA==.',
Sc='Scarecrow:BAAANQAECgEIAQABNQAECgkJMAAIAFUgAA==.',
Se='Seceron:BAAANQAECgUIDAAAAA==.Sekai:BAAANQAECgIIAgAAAA==.',
Sg='Sgtslappy:BAAANQADCgMIAwAAAA==.',
Sh='Shamminator:BAAANQAECgEIAQAAAA==.Shanarelle:BAAANQAECgYIEwAAAA==.Shasa:BAABNQAECn8hAAIbAAoK1Bu8NQDKAgAbAAoK1Bu8NQDKAgAAAA==.Shatteredsky:BAABNQAECn8hAAMVAAkKER2AKwC1AgAVAAkKER2AKwC1AgAGAAEKqgOgRQErAAAAAA==.Shazik:BAABNQAECn87AAIVAAoKGxkLBQCUAgAVAAoKGxkLBQCUAgAAAA==.Shazzik:BAAANQAECgYICgABNQAECgoKOwAVABsZAA==.Sheroko:BAAANQAECgIIBQAAAA==.Sheñanigans:BAAANQAECggIDQABNQAECggIKQABAEEfAA==.Shilbalam:BAAANQAECgQIBAAAAA==.Shmoopy:BAAANQAECgEIAQAAAA==.Shmoove:BAAANQADCgEIAQAAAA==.Shnkz:BAAANQAECgEIAQAAAA==.Shotzer:BAAANQADCgMIBgAAAA==.',
Si='Silzo:BAAANQAECggIDgABNQAECggIEQAUAAAAAA==.Sirjames:BAAANQAECgEIAQAAAA==.',
Sk='Skelix:BAACNQAFFH8hAAIVAAgK/R+BAQC2AgAVAAgK/R+BAQC2AgA1AAQKfy8AAxUACQpLJmMFAJwDABUACQpLJmMFAJwDAAYAAwpVF6baAN8AAAAA.Skunkpaw:BAAANQADCgUICwAAAA==.Skysong:BAACNQAFFH8UAAQeAAYKLR7dAAD+AAAeAAUKOiHdAAD+AAAmAAEKBxXWBABcAAAOAAEKeAUJGQA+AAA1AAQKfyQAAx4ACgoUIYYJANkCAB4ACgoUIYYJANkCAA4AAwp/BaZBAJQAAAAA.',
Sl='Slashedeye:BAABNQAECn8+AAIkAAkKFRSWAgASAgAkAAkKFRSWAgASAgAAAA==.Slimgucci:BAAANQADCggICAAAAA==.',
Sn='Snowfox:BAAANQADCgIIAgAAAA==.Snowynn:BAABNQAECn8gAAMPAAkKfhaFFAAdAgAPAAkKfhaFFAAdAgADAAMKxggGMgCDAAAAAA==.Snubby:BAABNQAECn8cAAMRAAkKtCJFOwCiAgARAAcKmyFFOwCiAgASAAIKcyVYOgDYAAAAAA==.',
So='Solheim:BAAANQABCgUIBQAAAA==.Sonari:BAAANQADCgYIBgAAAA==.',
Sp='Spankz:BAAANQAECgQICQAAAA==.Spathi:BAAANQAFFAIIAgAAAA==.Spicymeatbal:BAAANQABCggIEQAAAA==.',
St='Strathz:BAABNQAECn8iAAMRAAkKfRw0NQC1AgARAAkKMxk0NQC1AgASAAQKahyvKAA0AQAAAA==.Strongish:BAAANQADCgUIBQAAAA==.',
Su='Summerset:BAAANQAECgIIAQAAAA==.Sunstrider:BAAANQADCgMIBgAAAA==.Superdonkey:BAAANQADCgYICwABNQAFFAcIFwAXANMWAA==.Sushi:BAAANQADCgIIAgAAAA==.Suva:BAAANQADCgYIBgAAAA==.',
Sy='Sylatis:BAAANQAECgYIDAABNQAFFAYIIAARAOoiAA==.Sylätis:BAAANQAECgMIAwABNQAFFAYIIAARAOoiAA==.',
['Sö']='Söultender:BAAANQADCgMIAwABNQAECgYIDQAUAAAAAA==.',
['Sø']='Sølidus:BAAANQAECgMIDQABNQAFFAYIEgAHAD4bAA==.',
Ta='Taintedhealz:BAAANQADCgEIAQAAAA==.Talys:BAACNQAFFH8cAAIOAAcKABccBAA8AgAOAAcKABccBAA8AgA1AAQKfzkAAg4ACgr9IyUBAMYDAA4ACgr9IyUBAMYDAAAA.Tankly:BAAANQADCgMIAwAAAA==.',
Te='Tehchosen:BAAANQADCggICAAAAA==.Texicola:BAABNQAECn84AAIEAAoKOR7RAgAvAwAEAAoKOR7RAgAvAwAAAA==.',
Th='Thabdeady:BAAANQAECgMIBgABNQAECgoKMQAeAMcRAA==.Thabk:BAABNQAECn8xAAQeAAoKxxFTAQAQAgAeAAoKxxFTAQAQAgAmAAcKkQp9DgBfAQAOAAYKCQs9LQA7AQAAAA==.Thaelorn:BAAANQADCgEIAQAAAA==.Thesyra:BAABNQAECn8bAAMOAAgKPQj/JwB3AQAOAAgKPQj/JwB3AQAmAAQKLwpZGgCbAAAAAA==.Thunderjeed:BAAANQAECgMIAwABNQAFFAUIDQAXADobAA==.Thurmond:BAABNQAECn8cAAMBAAoK5RpnOwA0AgABAAoKQRZnOwA0AgAMAAYKBBn9WQCLAQAAAA==.Thurmoons:BAAANQAECgYICQABNQAECgoKHAABAOUaAA==.Thurmund:BAAANQADCgYIBgABNQAECgoKHAABAOUaAA==.',
Ti='Tiamat:BAAANQADCggICAAAAA==.Tidalanxiety:BAAANQAECgQIBQAAAA==.',
To='Toastay:BAAANQAECgMICgAAAA==.Toastz:BAABNQAECn83AAIbAAoKGR9uCwCCAwAbAAoKGR9uCwCCAwAAAA==.Toebeanz:BAAANQAECgQIDAAAAA==.Tokken:BAACNQAFFH8ZAAILAAcKKBMcBwBPAgALAAcKKBMcBwBPAgA1AAQKfzAAAgsACgrTHGc9ANMCAAsACgrTHGc9ANMCAAAA.',
Tr='Treebeast:BAABNQAECn8WAAMGAAkKER+5LQDGAgAGAAkKER+5LQDGAgAVAAEKnQE3KAElAAAAAA==.Troile:BAAANQADCggIHwAAAA==.Trojen:BAACNQAFFH8IAAIaAAQKVg72GQDYAAAaAAQKVg72GQDYAAA1AAQKfx8AAxoACQp2GpaDACECABoACApyGpaDACECABkACAoYC3J8AKQBAAAA.Trolladin:BAAANQADCgYICgABNQADCggIJQAUAAAAAA==.',
Tw='Twig:BAABNQAECn8eAAIYAAkKXBYyLAB5AgAYAAkKXBYyLAB5AgAAAA==.',
Ty='Tyras:BAAANQAECgUIDwAAAA==.',
Tz='Tzarina:BAAANQABCgYIBgAAAA==.',
['Tâ']='Tâz:BAABNQAECn8qAAMVAAoKix+jFgChAQAVAAoKix+jFgChAQAGAAEKAAB2qwAAAAAAAA==.',
Ul='Ulanda:BAABNQAECn87AAMPAAoK8xUzEQBNAgAPAAkKNhQzEQBNAgADAAgKVhFHFQCmAQAAAA==.',
Um='Umasi:BAACNQAFFH8fAAIiAAcK8iVOAAABAwAiAAcK8iVOAAABAwA1AAQKfzAAAiIACgorJrEBAL8DACIACgorJrEBAL8DAAAA.',
Un='Underbogg:BAAANQADCgUIBQAAAA==.',
Ut='Utastebad:BAAANQADCggIDAAAAA==.',
Va='Vagabundo:BAAANQAECgMIAwABNQAECgYICwAUAAAAAA==.Vail:BAAANQADCgUIBgAAAA==.Vainquish:BAAANQADCgEIAQAAAA==.Valamaldoran:BAAANQADCgUIBQAAAA==.Vanthil:BAAANQAECgIIAgAAAA==.Vaporize:BAAANQAECgIIAgAAAA==.',
Ve='Venandi:BAABNQAECn8UAAIFAAgKzAyB4ADIAQAFAAgKzAyB4ADIAQAAAA==.Vengened:BAABNQAECn8lAAILAAgKUBncVwCEAgALAAgKUBncVwCEAgABNQAFFAEIAQAUAAAAAA==.Verax:BAAANQAECgIIAgAAAA==.Verestrasz:BAAANQADCgIIBAAAAA==.',
Vg='Vgly:BAAANQAECgQIEAAAAA==.',
Vi='Vilous:BAABNQAECn8nAAIjAAoKPSSHAADVAwAjAAoKPSSHAADVAwAAAA==.',
Vy='Vyisesham:BAABNQAECn8oAAMGAAkKaRdNQAB0AgAGAAgKgxlNQAB0AgAVAAcK8BcpLAAxAQAAAA==.',
['Vý']='Výce:BAAANQAECgEIAQAAAA==.',
Wa='Wagtar:BAAANQADCgYICwABNQADCgQIBAAUAAAAAA==.Warzug:BAAANQADCgQIBAAAAA==.',
We='Wesjin:BAABNQAECn8hAAMnAAoKrROWFAAyAgAnAAoKrROWFAAyAgAXAAEKHQM/dgAiAAAAAA==.Wez:BAAANQAECgcICwAAAA==.',
Wh='Whiskee:BAABNQAECn8lAAMDAAoKmiKDAgDHAQAPAAcK8yBwEQBKAgADAAkKkCGDAgDHAQAAAA==.',
Wo='Wooglone:BAAANQAECgQJBAAAAA==.',
Wy='Wyndia:BAABNQAECn8UAAIFAAoKPhghZQC0AgAFAAoKPhghZQC0AgAAAA==.Wyndibear:BAAANQABCgEIAQAAAA==.',
Xa='Xanthos:BAAANQAECgEIAQABNQAECgUIBgAUAAAAAA==.',
Xb='Xbert:BAAANQADCgcIBwAAAA==.',
Xe='Xela:BAAANQAECgIIAgABNQAECgoKJAAFAIodAA==.Xenophontes:BAABNQAECn8ZAAMEAAoKuByjGgAeAQAFAAkKGhrKtQAYAgAEAAUKFR2jGgAeAQABNQAFFAYIEgAHAD4bAA==.Xeris:BAAANQADCgEIAQAAAA==.',
Xi='Xihuang:BAABNQAECn80AAIYAAoKKRfbAgBdAgAYAAoKKRfbAgBdAgABNQAFFAQIBwAdAHAGAA==.Xiia:BAAANQAECgQIBAAAAA==.',
Xo='Xouu:BAAANQAFFAQIBAABNQAFFAgIBgAVADoRAA==.',
Xx='Xxuu:BAAANQAFFAgIAgABNQAFFAgIBgAVADoRAA==.Xxuusham:BAACNQAFFH8GAAIVAAYKOhFoBwDkAQAVAAYKOhFoBwDkAQA1AAQKfz4AAhUACgrRJSICAMYDABUACgrRJSICAMYDAAAA.Xxuuspr:BAAANQAECggIAgABNQAFFAgIBgAVADoRAA==.Xxuutwo:BAAANQAECggIAQABNQAFFAgIBgAVADoRAA==.',
Ya='Yaoguai:BAABNQAECn8wAAMYAAoKExqPAwA5AgAYAAoKExqPAwA5AgAPAAEKHwm6YAAzAAAAAA==.Yasei:BAAANQAECgQIBAAAAA==.Yawgmoth:BAAANQAECgcIDQABNQAECgkJIQAQALcbAA==.',
Za='Zakkha:BAAANQADCgMIAwABNQADCggIDQAUAAAAAA==.Zaleris:BAAANQAECgQIBQAAAA==.Zaryana:BAAANQAECgcIDQAAAA==.',
Ze='Zephon:BAABNQAECn8aAAIbAAgK3g3zlQDcAQAbAAgK3g3zlQDcAQAAAA==.',
Zo='Zotiel:BAAANQAFFAQIBAABNQAFFAcIJQABAM4gAA==.',
Zy='Zynisch:BAAANQADCgcIEwAAAA==.',
['Ær']='Æris:BAAANQADCgMIAwAAAA==.',
['Ìr']='Ìroh:BAAANQADCgUIBgABNQAECgYIDQAUAAAAAA==.',
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
