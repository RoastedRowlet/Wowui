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

local lookup = {'DeathKnight-Unholy','Druid-Feral','Druid-Restoration','Mage-Frost','Mage-Arcane','Shaman-Elemental','Priest-Holy','DemonHunter-Havoc','DemonHunter-Vengeance','Shaman-Enhancement','Warrior-Arms','DeathKnight-Blood','Rogue-Assassination','Evoker-Preservation','Druid-Guardian','Monk-Brewmaster','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Unknown-Unknown','Shaman-Restoration','DemonHunter-Devourer','Monk-Windwalker','Paladin-Holy','Paladin-Retribution','Druid-Balance','Rogue-Subtlety','Evoker-Devastation','Hunter-BeastMastery','Hunter-Marksmanship','Rogue-Outlaw','DeathKnight-Frost','Priest-Shadow','Paladin-Protection','Warrior-Fury','Mage-Fire','Priest-Discipline','Evoker-Augmentation','Monk-Mistweaver',}
local provider = {region='US',realm='Spirestone',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abduon:BAAANQADCgcICwAAAA==.',
Ac='Aciddeath:BAAANQAECgEIAQABNQAFFAQIDAABAP8RAA==.',
Ad='Admaris:BAACNQAFFH8HAAMCAAIKbRFaAwCaAAACAAIKbRFaAwCaAAADAAIKIBF0EACNAAA1AAQKfy0AAwMACQqqH8cMAP4CAAMACQqqH8cMAP4CAAIABwqQIa4JAKMCAAAA.',
Ae='Aelis:BAAANQABCgEIAQAAAA==.',
Ag='Agni:BAACNQAFFH8TAAMEAAcK1BIxAwDrAAAFAAQKuRCfJgBKAQAEAAMKOxQxAwDrAAA1AAQKfyIAAwUACQriIhBKAO4CAAUACQriIhBKAO4CAAQAAQpCGBdJADEAAAAA.',
Ak='Akkadian:BAAANQADCggICwAAAA==.',
Al='Alnasham:BAACNQAFFH8NAAIGAAYKWBQhCADsAQAGAAYKWBQhCADsAQA1AAQKfykAAgYACQpkISEUAE8DAAYACQpkISEUAE8DAAAA.Alnava:BAAANQAECgcIDAAAAA==.Alvoka:BAAANQAECgYJEQAAAA==.',
Am='Amarillos:BAAANQAECggIDgAAAA==.Amarillys:BAABNQAECn8jAAIHAAkKpRrmPABzAgAHAAkKpRrmPABzAgAAAA==.Ammutseba:BAABNQAECn8YAAMIAAgKvBm9MQAXAgAIAAgK1xi9MQAXAgAJAAMK2hbVIQCwAAAAAA==.',
An='Anfall:BAACNQAFFH8IAAIKAAMKPhd7BAD4AAAKAAMKPhd7BAD4AAA1AAQKfycAAgoACQqGHyIIAPYCAAoACQqGHyIIAPYCAAAA.Angermeier:BAABNQAECn8jAAILAAcK1RP5nwDIAQALAAcK1RP5nwDIAQAAAA==.Angers:BAAANQAECgIIAgABNQAECgcIIwALANUTAA==.Angrylady:BAAANQAECgEIAQAAAA==.Anjuna:BAAANQADCgUIBQAAAA==.Anohru:BAAANQAECggIBQAAAA==.Anthos:BAAANQAECgcICgAAAA==.Antikreist:BAAANQADCgQJBAAAAA==.Anyawnka:BAAANQABCggIFwAAAA==.',
Ap='Aphotic:BAAANQAECgEIAQAAAA==.',
Ar='Ards:BAAANQADCgIIAwAAAA==.Armanite:BAAANQAECgQIBQABNQAECgkJGAABAOoZAA==.Arthaniis:BAAANQAECgYJEwAAAA==.',
As='Asystoli:BAAANQAECgYIDgAAAA==.',
At='Atheria:BAAANQADCgYICAAAAA==.Attackheli:BAAANQAECgMICQAAAA==.',
Au='Audideath:BAAANQAECgQICQAAAA==.Auurdeath:BAAANQADCggIEwAAAA==.',
Av='Av:BAAANQADCgIIBQAAAA==.',
Aw='Aw:BAACNQAFFH8aAAIIAAYKfh+FAwBGAgAIAAYKfh+FAwBGAgA1AAQKfyIAAggACQoTJtYFAJYDAAgACQoTJtYFAJYDAAAA.',
Ax='Ax:BAECNQAFFH8PAAMBAAYKzBqTBwCeAQABAAUKzBqTBwCeAQAMAAEKAAAHOQAfAAA1AAQKfyQAAgEACQqnINEjALECAAEACQqnINEjALECAAAA.',
Az='Azzazinzblo:BAAANQADCgUIBQAAAA==.',
['Aÿ']='Aÿa:BAAANQAECgQIBAAAAA==.',
Ba='Baast:BAAANQADCgUIBQAAAA==.Bamph:BAAANQAECgcIDAAAAA==.Bangbang:BAAANQAECgcIDwAAAA==.Batez:BAAANQAECgQIBAABNQAFFAYICwANACMNAA==.',
Bd='Bdk:BAAANQAECggIEwAAAA==.Bdog:BAAANQAECgEIAwAAAA==.',
Be='Beeatinu:BAAANQADCgYICgAAAA==.Beers:BAAANQAECggIBwAAAA==.Beledros:BAABNQAECn8cAAIOAAkKVBPFFQBXAgAOAAkKVBPFFQBXAgAAAA==.Beni:BAABNQAECn86AAMPAAkKUSL9AwBuAwAPAAkKUSL9AwBuAwACAAUK/RJdHAA8AQAAAA==.Benson:BAABNQAECn8hAAIQAAkKoxwWCACuAgAQAAkKoxwWCACuAgAAAA==.Bensonadin:BAAANQAECgYIBgAAAA==.Berd:BAAANQAECggIBgAAAA==.',
Bi='Bina:BAAANQAECgQIBQAAAA==.Birblock:BAACNQAFFH8gAAQRAAYK6iJ4AgBtAgARAAYK6iJ4AgBtAgASAAIKygHuEgB9AAATAAEK/BniBwBiAAA1AAQKfyMABBEACQotJiEyAL0CABEABwo1JiEyAL0CABIABwq3G/ITAM8BABMAAQoAAOsoAEcAAAAA.',
Bo='Bobbo:BAAANQADCgYJBwAAAA==.',
Br='Brek:BAAANQAECgYIDAAAAA==.Brewtherguy:BAABNQAECn8iAAIQAAkKAB1VBwDHAgAQAAkKAB1VBwDHAgAAAA==.Brother:BAAANQADCgIIAgAAAA==.Bruceshepard:BAAANQADCgQIBwABNQAECgIIAgAUAAAAAA==.Brutebuffalo:BAABNQAECn8lAAMVAAkKqh02IwDYAgAVAAkKqh02IwDYAgAGAAUKQBHJqwA4AQAAAA==.Bruteflappy:BAAANQADCggICAABNQAECgkJJQAVAKodAA==.Brutetestify:BAAANQADCggICAABNQAECgkJJQAVAKodAA==.',
Bu='Bubbleboi:BAAANQADCgYICAAAAA==.Bubblebôy:BAAANQAECgIIAgAAAA==.Bublz:BAAANQAECgcIEQAAAA==.',
['Bâ']='Bâra:BAABNQAECn8dAAIBAAkKFB1QJQCnAgABAAkKFB1QJQCnAgAAAA==.',
Ca='Carnal:BAAANQADCgUIBQAAAA==.',
Ce='Cedren:BAACNQAFFH8KAAIIAAQKohJFDgAfAQAIAAQKohJFDgAfAQA1AAQKfygAAwgACQpoG6ciAIICAAgACQpHGqciAIICABYACAotE0grAOQBAAAA.Ceewhya:BAAANQAECgEIAQAAAA==.Celestika:BAAANQABCgIIAgAAAA==.Cerari:BAAANQAECgEJAQAAAA==.',
Ch='Chalix:BAAANQAECgIIAQAAAA==.Chama:BAABNQAECn8aAAIWAAkKpxLUIwAmAgAWAAkKpxLUIwAmAgAAAA==.Cheapheal:BAABNQAECn81AAIPAAkKwR/mBABRAwAPAAkKwR/mBABRAwAAAA==.Cheapsnipe:BAAANQAECgIIAgABNQAECgkJNQAPAMEfAA==.Cheburashka:BAACNQAFFH8TAAIGAAYKbCN6BABIAgAGAAYKbCN6BABIAgA1AAQKfx8AAgYACQqfIBYoAN8CAAYACQqfIBYoAN8CAAAA.Chimerabob:BAAANQAECgMIBQAAAA==.Chopsuey:BAAANQAECggIAwAAAA==.Chunkymonkey:BAACNQAFFH8VAAIXAAYKPhmSBADwAQAXAAYKPhmSBADwAQA1AAQKfywAAhcACQpJI50LABkDABcACQpJI50LABkDAAAA.',
Ci='Cidren:BAAANQAECgEIAQAAAA==.',
Cl='Clappncheeks:BAAANQAECgYICwAAAA==.Claudefrollo:BAAANQAECgcIEQAAAA==.',
Cr='Crankyelf:BAAANQABCgEIAQAAAA==.Crimsa:BAABNQAECn8mAAITAAgKmwQXDgBvAQATAAgKmwQXDgBvAQAAAA==.Crimsonaxel:BAABNQAECn8hAAIGAAgKghzsOgCHAgAGAAgKghzsOgCHAgAAAA==.Cryogen:BAAANQAECgQJCAAAAA==.',
Cu='Cursewords:BAAANQADCgUIBQABNQAECgYIBgAUAAAAAA==.',
Da='Daemonproph:BAAANQADCgYIDAAAAA==.Dakini:BAABNQAECn8eAAIYAAgKQR4OKgC9AgAYAAgKQR4OKgC9AgAAAA==.Dam:BAAANQADCgUIBQABNQAECgkJIAAMABgXAA==.Dangerruss:BAAANQAECgUICQAAAA==.Darkspartan:BAAANQAECgUIBQAAAA==.Dashytash:BAABNQAECn8lAAIJAAgK6RvhCABdAgAJAAgK6RvhCABdAgAAAA==.Dawnsoul:BAAANQAECgYIDQAAAA==.Daxos:BAAANQADCgcIDQAAAA==.',
De='Deathschosen:BAAANQADCgQIBAAAAA==.Demb:BAAANQAECgQIBwAAAA==.Demonicchoas:BAABNQAECn8pAAMSAAkKhx23DAArAgARAAgKEhxdWgBEAgASAAcKfhy3DAArAgAAAA==.Denagorn:BAABNQAECn8xAAIZAAkKQyS6EACFAwAZAAkKQyS6EACFAwABNQAFFAYIHgABAEYjAA==.Denhunt:BAAANQAECggIDgABNQAFFAYIHgABAEYjAA==.Dentsama:BAAANQADCgEIAQAAAA==.Deplete:BAAANQADCgIJAgABNQAECgkJJgAaAIcZAA==.Deutzfr:BAABNQAECn8YAAIJAAkKfxwFBwCeAgAJAAkKfxwFBwCeAgAAAA==.Develop:BAAANQAECgMIBAAAAA==.Devos:BAABNQAECn8YAAMGAAcKgBOMcADLAQAGAAcKgBOMcADLAQAVAAQKRQ5A1AC6AAABNQAFFAQICAAGAIcEAA==.',
Di='Dizzleman:BAAANQAECggICgAAAA==.',
Do='Dominant:BAABNQAECn8gAAMFAAkKJB6YVgDTAgAFAAkKJB6YVgDTAgAEAAEKAABSSQAxAAAAAA==.',
Dp='Dpssos:BAAANQAECgcIDQAAAA==.',
Dr='Draco:BAAANQADCgcIBwAAAA==.Drag:BAAANQADCgYICAAAAA==.Dreadmar:BAAANQADCgYICAAAAA==.Drock:BAABNQAECn8mAAIWAAkKFCAUCABQAwAWAAkKFCAUCABQAwAAAA==.Druidgale:BAAANQAECgIIAwAAAA==.Drybonez:BAAANQAECgQIBgAAAA==.Drygth:BAAANQADCgMIBgABNQAECgkJKQAbAJ8gAA==.Dräkarnoir:BAAANQADCggICAAAAA==.',
Dt='Dtb:BAACNQAFFH8OAAIMAAUKJyDLBwDgAQAMAAUKJyDLBwDgAQA1AAQKfysAAgwACQq7JdcEAKQDAAwACQq7JdcEAKQDAAAA.',
Du='Dushimaya:BAABNQAECn8pAAIYAAkKhSNqBwCOAwAYAAkKhSNqBwCOAwAAAA==.',
Dv='Dvil:BAAANQAECgQIBQABNQAECgkJJgAWABQgAA==.',
Dw='Dwyndi:BAAANQAECgYICAAAAA==.',
Ei='Eisador:BAAANQAECgYIEQAAAA==.',
El='Elsen:BAAANQAECgQICQAAAA==.Elsha:BAABNQAECn8hAAIQAAkKtxtFCACnAgAQAAkKtxtFCACnAgAAAA==.',
Em='Emp:BAAANQAECgUIBgAAAA==.',
Er='Erilee:BAAANQAECgUICgAAAA==.',
Ev='Evelira:BAABNQAFFH8OAAIHAAYKRhpqBwARAgAHAAYKRhpqBwARAgAAAA==.',
Ey='Eyja:BAAANQADCgEIAgAAAA==.',
Ez='Ezailas:BAAANQAECgQIBQAAAA==.Ezpzndaheezy:BAAANQADCgYIBgABNQAECgkJKAAcAOEOAA==.',
Fa='Fatherangus:BAAANQAECggICAAAAA==.Fathercoast:BAAANQAECgYICwAAAA==.',
Fe='Fearful:BAACNQAFFH8FAAIYAAMKYALXGgC+AAAYAAMKYALXGgC+AAA1AAQKfyIAAhgACQr5FSJGAEsCABgACQr5FSJGAEsCAAAA.Felstrider:BAAANQADCgUIBQAAAA==.Ferador:BAACNQAFFH8TAAMdAAYKuxMMEABUAQAdAAQK2BcMEABUAQAeAAUKdgzLDgBMAQA1AAQKfyUAAx0ACQoHH9RCAKACAB0ACQoHH9RCAKACAB4ABgq+Evo+AFUBAAAA.Feythe:BAACNQAFFH8aAAIMAAkKogrfAwBEAgAMAAkKogrfAwBEAgA1AAQKfxYAAgwACQokF5Q4ACICAAwACQokF5Q4ACICAAAA.',
Fi='Figgleslock:BAAANQADCgUIBQAAAA==.',
Fl='Flakester:BAABNQAECn8fAAIHAAcK+iCmNgCKAgAHAAcK+iCmNgCKAgAAAA==.Fleebly:BAABNQAECn8hAAIWAAkKdRuBGQCLAgAWAAkKdRuBGQCLAgAAAA==.',
Fn='Fndruid:BAAANQAECgIIAgAAAA==.',
Fo='Fourbees:BAABNQAECn8gAAIZAAkK8wtcqwDDAQAZAAkK8wtcqwDDAQAAAA==.',
Fu='Fursure:BAAANQAECgMIAwAAAA==.',
Ga='Garfal:BAAANQAECgIIAwAAAA==.Gather:BAAANQABCgQIBAABNQAECgkJMQAVAAcXAA==.',
Gi='Gilgamesh:BAAANQAECgcIDAAAAA==.',
Go='Gorobob:BAAANQAECgIIBAAAAA==.',
Gr='Graygkl:BAAANQAECgUIDwAAAA==.Greshanwise:BAAANQAECgYIEwAAAA==.Grimreaper:BAABNQAECn8qAAIfAAkKIhiLBQCPAgAfAAkKIhiLBQCPAgAAAA==.Groa:BAAANQABCgQIBgAAAA==.Groag:BAABNQAECn8pAAMbAAkKnyCQBQAuAwAbAAkKmCCQBQAuAwANAAgKYxvBKQBAAgAAAA==.',
Ha='Haarp:BAAANQAECgUIDAAAAA==.Hakü:BAAANQAECgYIBwAAAA==.Hammered:BAAANQAECgYICgAAAA==.Hardwire:BAAANQAECgEIAQAAAA==.',
He='Heartred:BAAANQADCgYIBgAAAA==.Heifer:BAABNQAECn8kAAIaAAkK0SFYGQD7AgAaAAkK0SFYGQD7AgABNQAFFAEJAQAUAAAAAA==.Hemophilia:BAABNQAECn8lAAIBAAgKABIqTwDUAQABAAgKABIqTwDUAQAAAA==.Heydk:BAABNQAECn8XAAMgAAgKqxrOWABAAQAgAAUKRhrOWABAAQABAAUKIhk9fQAjAQAAAA==.Heydruid:BAAANQAECgcICwABNQAECggIFwAgAKsaAA==.',
Ho='Hollowshädix:BAAANQAECgEIAQAAAA==.Holyanxiety:BAAANQADCgYIBgAAAA==.Holydave:BAAANQAECgMIBAAAAA==.Holymentos:BAABNQAECn8eAAMhAAgKOQswLwCmAQAhAAgKOQswLwCmAQAHAAUK4AKvxwDDAAABNQAECgkJHgAiAL0PAA==.Hottsauce:BAABNQAECn8cAAIKAAkKQBz4DACdAgAKAAkKQBz4DACdAgAAAA==.Hottsaucefel:BAAANQAECgYIBgAAAA==.',
Hu='Hundard:BAAANQADCgIIAgAAAA==.Huntersmarc:BAAANQAECgIIBAAAAA==.Hushhides:BAABNQAECn8WAAIbAAkK8g1FGAAYAgAbAAkK8g1FGAAYAgAAAA==.Hushrage:BAAANQAECggICAABNQAECgkJFgAbAPINAA==.',
Ia='Iamachick:BAAANQAECgEIAQAAAA==.',
Ib='Ibetrollinya:BAAANQAECgUIBwABNQAECgkJIwAjADElAA==.Iblisshaytan:BAABNQAECn8zAAIIAAkKrxy2GgDBAgAIAAkKrxy2GgDBAgABNQAFFAQIBwAbAHAGAA==.Ibtrollin:BAAANQADCggIJQAAAA==.',
Ig='Ignacious:BAAANQAECgEIAQAAAA==.',
Il='Illumina:BAACNQAFFH8FAAIiAAMKJROACQC2AAAiAAMKJROACQC2AAA1AAQKfxQAAiIACAryIoMIABQDACIACAryIoMIABQDAAAA.',
Io='Ionissa:BAABNQAECn8jAAIdAAkK1hvwLgDeAgAdAAkK1hvwLgDeAgAAAA==.',
Ir='Ironbreaker:BAAANQAECgUIBQAAAA==.',
Is='Ischia:BAACNQAFFH8JAAMHAAQK5whvGgATAQAHAAQK5whvGgATAQAhAAEKbAGVGgA0AAA1AAQKfzQAAwcACQolGRo2AIwCAAcACQolGRo2AIwCACEAAgrUE15oAFsAAAAA.',
Ja='Jallypally:BAAANQADCgIIAgAAAA==.Jarl:BAAANQADCgYICwAAAA==.',
Jc='Jch:BAACNQAFFH8eAAIdAAcK2h5LAQCCAgAdAAcK2h5LAQCCAgA1AAQKfywAAx0ACQp1JXYTAFADAB0ACQp1JXYTAFADAB4AAQpkFkaEADgAAAAA.',
Je='Jeay:BAAANQAECgEJAQAAAA==.Jedijeed:BAACNQAFFH8IAAIXAAUKGBmSBwB0AQAXAAUKGBmSBwB0AQA1AAQKfy8AAhcACQq3IikGAGwDABcACQq3IikGAGwDAAAA.Jedikepjr:BAACNQAFFH8GAAIZAAMKZQnjGgDLAAAZAAMKZQnjGgDLAAA1AAQKfxYAAhkACQpLGkBEAMQCABkACQpLGkBEAMQCAAE1AAUUBQgIABcAGBkA.Jenova:BAAANQADCgUIBwAAAA==.Jepage:BAABNQAECn8mAAQEAAgKOSDKBQCtAgAEAAcKdiDKBQCtAgAkAAUKzhgKBAB/AQAFAAUKkhVLGgFcAQAAAA==.Jess:BAAANQABCgIIAgAAAA==.',
Jo='Jolyne:BAAANQAECgQIBAAAAA==.',
Jp='Jprottsoo:BAABNQAECn8gAAIaAAgKqh5/IgC5AgAaAAgKqh5/IgC5AgAAAA==.',
Ju='Jubei:BAABNQAECn8iAAIjAAgKVQ7SDQDUAQAjAAgKVQ7SDQDUAQAAAA==.',
Ka='Kagayaki:BAAANQAECgIIAgAAAA==.Kalmya:BAABNQAECn8nAAMDAAgKpQ2oLwCaAQADAAgKpQ2oLwCaAQACAAEKAABSRAAuAAAAAA==.Kalrath:BAAANQAECgIIAgABNQAECgkJGAABAOoZAA==.Kasheek:BAAANQADCggICAAAAA==.',
Ke='Keizzer:BAAANQAECgcICwABNQAECgkJHQAHAPcbAA==.Keshisaru:BAAANQADCgQIBAAAAA==.',
Kh='Khazra:BAAANQAECgMIBgAAAA==.',
Ki='Kierràalexis:BAAANQADCgYIBgAAAA==.',
Kl='Klunder:BAABNQAECn8mAAIVAAgKSyJiHQD1AgAVAAgKSyJiHQD1AgAAAA==.',
Ko='Korris:BAABNQAECn8gAAMdAAkK6h2mLwDcAgAdAAkK6h2mLwDcAgAeAAEK1wKvmgAiAAAAAA==.Kostik:BAAANQADCgUIBQAAAA==.',
Kr='Kridillis:BAABNQAECn8hAAIIAAkK+xopHAC1AgAIAAkK+xopHAC1AgAAAA==.',
Ky='Kybinc:BAAANQADCgQIBAAAAA==.',
['Kí']='Kírã:BAAANQABCgIIBAAAAA==.',
La='Lawls:BAAANQADCgQIBwAAAA==.Lazybigger:BAAANQAECgIIAgAAAA==.Lazycow:BAABNQAECn8oAAIPAAkKChWUEwAkAgAPAAkKChWUEwAkAgAAAA==.Lazyfrost:BAABNQAECn8iAAIFAAkKmxAemQBNAgAFAAkKmxAemQBNAgAAAA==.',
Le='Lethò:BAABNQAECn8mAAMYAAkKJiOECACDAwAYAAkKJiOECACDAwAZAAQK1xdsLwHMAAAAAA==.Lethô:BAAANQAECgIIBQAAAA==.Lethö:BAAANQAECgIIBQAAAA==.',
Li='Liesx:BAACNQAFFH8LAAINAAYKIw0VBQDfAQANAAYKIw0VBQDfAQA1AAQKfxUAAw0ACArtHmAUANUCAA0ACArtHmAUANUCABsAAQpIB8dRADUAAAAA.Lilzarthe:BAAANQAECgQIDAAAAA==.',
Lo='Loerasdh:BAABNQAECn8eAAIIAAgK3CUWCgBeAwAIAAgK3CUWCgBeAwAAAA==.Loko:BAACNQAFFH8SAAIaAAYKTBUQCQDpAQAaAAYKTBUQCQDpAQA1AAQKfycAAhoACQqMIx8TAC0DABoACQqMIx8TAC0DAAAA.Looio:BAAANQADCgIIAgAAAA==.',
Lu='Lucien:BAAANQABCgQIBAAAAA==.Lumièrevide:BAAANQABCgMIAwAAAA==.Luxxus:BAABNQAECn8dAAIHAAkK9xumKgC8AgAHAAkK9xumKgC8AgAAAA==.',
Ly='Lyesx:BAABNQAECn8cAAMdAAkKeiHsFgA9AwAdAAkKeiHsFgA9AwAeAAMKpxSRVgDHAAABNQAFFAYICwANACMNAA==.Lyndsy:BAAANQADCgUIBQAAAA==.Lyri:BAAANQADCgMIAwAAAA==.',
Ma='Macros:BAAANQAECgQICQAAAA==.Magai:BAAANQABCggIDQAAAA==.Mageyousad:BAAANQADCgEIAgAAAA==.Maixia:BAAANQAECgIIBgAAAA==.Makhtor:BAAANQAECgMIBQAAAA==.Mallaer:BAABNQAECn8cAAIHAAkKnB+zGQAMAwAHAAkKnB+zGQAMAwAAAA==.Malícíous:BAABNQAECn8iAAIRAAgKIBQldgD7AQARAAgKIBQldgD7AQAAAA==.Mantakore:BAACNQAFFH8FAAIOAAIKvwT+FQByAAAOAAIKvwT+FQByAAA1AAQKfycAAg4ACQpLFagVAFgCAA4ACQpLFagVAFgCAAAA.Marcdruid:BAAANQAECgUICQAAAA==.Maubles:BAAANQADCggICAABNQAFFAUICgAiAHoNAA==.',
Mc='Mcdirk:BAAANQAECggICAAAAA==.',
Me='Menopaws:BAABNQAECn8qAAIPAAkK1SVPAQDUAwAPAAkK1SVPAQDUAwAAAA==.Merrtt:BAAANQAECgYIBgAAAA==.Mertrik:BAABNQAECn8eAAMVAAkKtiLVDABYAwAVAAkKtiLVDABYAwAGAAMKiBCM6gC7AAAAAA==.',
Mi='Midk:BAAANQAECgIIAwAAAA==.Mikayy:BAACNQAFFH8MAAIbAAUKAiM+AwAGAgAbAAUKAiM+AwAGAgA1AAQKfzUAAhsACQqGJvgAAMwDABsACQqGJvgAAMwDAAAA.Milenko:BAABNQAECn8nAAIIAAgKkSGFFQDuAgAIAAgKkSGFFQDuAgAAAA==.Milly:BAAANQAECgUIDAABNQAECggIJwAIAJEhAA==.',
Mo='Molfsongal:BAAANQADCgIIAgAAAA==.Monstrous:BAACNQAFFH8TAAILAAYKPhD/DADbAQALAAYKPhD/DADbAQA1AAQKfzAAAgsACQoQIGI4AOACAAsACQoQIGI4AOACAAAA.Moocher:BAAANQAECgEIAQAAAA==.Moonpie:BAAANQADCgUICQAAAA==.Mordecaii:BAAANQADCgYIDgAAAA==.Morgul:BAAANQAECgUIBgAAAA==.Morox:BAAANQAECgcIBwABNQAFFAcIEwAEANQSAA==.Mothman:BAAANQAECgQICAAAAA==.Moyana:BAAANQADCgEIAQAAAA==.',
Ms='Msbehaven:BAABNQAECn8fAAIRAAgK6QUfuwBSAQARAAgK6QUfuwBSAQAAAA==.',
Mt='Mthafknfreez:BAAANQAECggIEwABNQAFFAQIBwAbAHAGAA==.',
Mu='Muffìns:BAAANQAECgQIBgAAAA==.Musashi:BAABNQAECn8bAAIHAAgKxBkXQABnAgAHAAgKxBkXQABnAgAAAA==.',
My='Mynuturchin:BAABNQAECn8WAAMMAAcK2BasQgDuAQAMAAcK2BasQgDuAQAgAAEKJArErwAsAAAAAA==.',
Na='Nagy:BAAANQAECgMIAwAAAA==.',
Ni='Night:BAABNQAECn8fAAIFAAgKFhL6tAAYAgAFAAgKFhL6tAAYAgAAAA==.Nightsecho:BAAANQAECgEIAQAAAA==.Nightshris:BAAANQAECgUIBwAAAA==.',
No='Notmehssos:BAAANQAECgcICwAAAA==.Notthechosen:BAAANQAFFAEIAQAAAA==.',
Ny='Nymeriã:BAAANQAECgUICAAAAA==.',
Ob='Obzy:BAAANQAECgcIEwAAAA==.Obzz:BAAANQADCgEIAQABNQAECgcIEwAUAAAAAA==.',
Ok='Okamy:BAAANQAECgcIDAABNQAECgQIBQAUAAAAAA==.',
Ol='Olympicjeid:BAABNQAECn8XAAMeAAcKFBMmLgDYAQAeAAcKFBMmLgDYAQAdAAEKCQbSUgE7AAABNQAFFAUICAAXABgZAA==.',
Op='Opz:BAABNQAECn8rAAMhAAkKixi4GQB+AgAhAAkKixi4GQB+AgAlAAIKiBaMGwCIAAAAAA==.',
Pa='Paladinfive:BAAANQAECgEIAgAAAA==.Parthos:BAAANQAECgQIDQAAAA==.',
Pe='Pedro:BAAANQAECgEIAgAAAA==.Perry:BAAANQADCgIIAgAAAA==.',
Ph='Phenomenon:BAAANQAECgUICAABNQAECgYICgAUAAAAAA==.',
Pi='Pittydafoo:BAAANQAECgIIAgAAAA==.',
Pk='Pkunkk:BAAANQAECgcICwAAAA==.',
Pl='Ploxis:BAACNQAFFH8SAAIJAAYKZRTwAADGAQAJAAYKZRTwAADGAQA1AAQKfxsAAgkACQoPGXgHAIwCAAkACQoPGXgHAIwCAAAA.',
Po='Polskashaman:BAABNQAECn8fAAIKAAcKsxNzFwDsAQAKAAcKsxNzFwDsAQAAAA==.Pookiebonez:BAAANQADCgIIAgABNQAECgQIBgAUAAAAAA==.',
Pr='Prea:BAAANQAFFAIIAgAAAA==.Premiumferal:BAABNQAECn8bAAMNAAkKECErHQCRAgANAAkKECErHQCRAgAbAAUKxRhrMAA2AQAAAA==.Primecarry:BAACNQAFFH8RAAIYAAYKRRcsBgAIAgAYAAYKRRcsBgAIAgA1AAQKfyMAAhgACQrYI5wJAHoDABgACQrYI5wJAHoDAAAA.Prine:BAABNQAECn8eAAILAAkKCx0EKwANAwALAAkKCx0EKwANAwABNQAFFAYIEQAYAEUXAA==.',
Pu='Puripuri:BAAANQAECgQIBAAAAA==.',
Qi='Qinkipa:BAAANQAECgEIAQAAAA==.',
Qo='Qovo:BAAANQABCggIDgAAAA==.',
Ra='Ragark:BAAANQADCgUIBQAAAA==.Raigko:BAABNQAECn8tAAILAAkK1iN5CQCoAwALAAkK1iN5CQCoAwAAAA==.Rainyday:BAABNQAECn8UAAIVAAYK9AqDtQD+AAAVAAYK9AqDtQD+AAAAAA==.Raiva:BAAANQAECgUIDgABNQAECggIDAAUAAAAAA==.Raivek:BAAANQAECgIIAgAAAA==.Randenton:BAAANQADCgYICAAAAA==.Randezoth:BAAANQABCggIDQABNQADCgYICAAUAAAAAA==.Randomkiller:BAAANQADCgIIAgAAAA==.Rassputen:BAABNQAECn8pAAIMAAkK6RIaRwDaAQAMAAkK6RIaRwDaAQAAAA==.',
Re='Reck:BAAANQADCgEIAQAAAA==.Redjive:BAAANQAECggIAQAAAA==.Redonkulos:BAAANQADCgMIBAAAAA==.Reliri:BAAANQADCgYICgAAAA==.Relis:BAAANQABCgYICAAAAA==.Renais:BAAANQAECgMIAwAAAA==.Rex:BAABNQAECn8gAAIMAAkKGBdtMABNAgAMAAkKGBdtMABNAgAAAA==.',
Ri='Rileyesco:BAAANQABCgUIBgAAAA==.Ripskylark:BAAANQAECgIIAwAAAA==.Risk:BAAANQABCgcIEwAAAA==.',
Ro='Roguen:BAACNQAFFH8HAAIbAAQKcAZyCwACAQAbAAQKcAZyCwACAQA1AAQKfzIAAxsACQrUF/gMAKMCABsACQrUF/gMAKMCAA0AAwqGCC+AAKkAAAAA.Romirin:BAAANQADCgQIBAAAAA==.Rotan:BAAANQADCgYICwAAAA==.Roulduke:BAABNQAECn8jAAIGAAcKhguFiQCIAQAGAAcKhguFiQCIAQAAAA==.',
['Rù']='Rùckús:BAABNQAECn8pAAIBAAgKQR9SLgB2AgABAAgKQR9SLgB2AgAAAA==.',
Sa='Sacredmentos:BAABNQAECn8eAAIiAAkKvQ/aJQCtAQAiAAkKvQ/aJQCtAQAAAA==.Salaen:BAAANQAECggIAQAAAA==.Sammybeans:BAAANQAECgQIBgAAAA==.Sapito:BAAANQADCgYICgAAAA==.',
Sc='Scarecrow:BAAANQAECgEIAQABNQAECggIJwAIAJEhAA==.',
Se='Seceron:BAAANQAECgUIDAAAAA==.Sekai:BAAANQAECgIIAgAAAA==.',
Sg='Sgtslappy:BAAANQADCgMIAwAAAA==.',
Sh='Shamminator:BAAANQAECgEIAQAAAA==.Shanarelle:BAAANQAECgYIEwAAAA==.Shasa:BAABNQAECn8dAAIdAAkKKhyXNADLAgAdAAkKKhyXNADLAgAAAA==.Shatteredsky:BAABNQAECn8hAAMVAAkKER30KgC1AgAVAAkKER30KgC1AgAGAAEKqgMdQQErAAAAAA==.Shazik:BAABNQAECn8xAAIVAAkKBxcrOAB8AgAVAAkKBxcrOAB8AgAAAA==.Shazzik:BAAANQAECgYICgABNQAECgkJMQAVAAcXAA==.Sheroko:BAAANQAECgIIBQAAAA==.Sheñanigans:BAAANQAECggICAABNQAECggIKQABAEEfAA==.Shilbalam:BAAANQADCgQIBAAAAA==.Shmoopy:BAAANQAECgEIAQAAAA==.Shmoove:BAAANQADCgEIAQAAAA==.Shnkz:BAAANQAECgEIAQAAAA==.Shotzer:BAAANQADCgMIBgAAAA==.',
Si='Silzo:BAAANQAECggIDAAAAA==.Sirjames:BAAANQAECgEIAQAAAA==.',
Sk='Skelix:BAACNQAFFH8dAAIVAAcKZyBqAQC2AgAVAAcKZyBqAQC2AgA1AAQKfy4AAxUACQpLJjsFAJ0DABUACQpLJjsFAJ0DAAYAAwpVF/7XAOAAAAAA.Skunkpaw:BAAANQADCgUICwAAAA==.Skysong:BAACNQAFFH8OAAQcAAYK5Rl8AwC4AQAcAAUKOiF8AwC4AQAmAAEK5wP7CwBKAAAOAAEKeAWqGAA+AAA1AAQKfyIAAxwACQqhIGUJANoCABwACQqhIGUJANoCAA4AAwp/Bc5AAJUAAAAA.',
Sl='Slashedeye:BAABNQAECn82AAIkAAgK/xKRAgASAgAkAAgK/xKRAgASAgAAAA==.Slimgucci:BAAANQADCggICAAAAA==.',
Sn='Snowfox:BAAANQADCgIIAgAAAA==.Snowynn:BAABNQAECn8gAAMPAAkKfhY7FAAbAgAPAAkKfhY7FAAbAgACAAMKxgi8MACFAAAAAA==.Snubby:BAABNQAECn8cAAMRAAkKtCIzOgCiAgARAAcKmyEzOgCiAgASAAIKcyUKOgDYAAAAAA==.',
So='Solheim:BAAANQABCgUIBQAAAA==.Sonari:BAAANQADCgYIBgAAAA==.',
Sp='Spankz:BAAANQAECgQICQAAAA==.Spathi:BAAANQAECgYIBwAAAA==.Spicymeatbal:BAAANQABCggIEQAAAA==.',
St='Strathz:BAABNQAECn8iAAMRAAkKfRwCNAC3AgARAAkKMxkCNAC3AgASAAQKahx8KAA0AQAAAA==.Strongish:BAAANQADCgUIBQAAAA==.',
Su='Summerset:BAAANQAECgIIAQAAAA==.Sunstrider:BAAANQADCgMIBgAAAA==.Superdonkey:BAAANQADCgYICwABNQAFFAYIFQAXAD4ZAA==.Sushi:BAAANQADCgIIAgAAAA==.Suva:BAAANQADCgYIBgAAAA==.',
Sy='Sylatis:BAAANQAECgYIDAABNQAFFAYIIAARAOoiAA==.Sylätis:BAAANQAECgMJAwABNQAFFAYIIAARAOoiAA==.',
['Sö']='Söultender:BAAANQADCgMIAwABNQAECgYIDQAUAAAAAA==.',
['Sø']='Sølidus:BAAANQAECgMICgABNQAFFAYIDgAHAEYaAA==.',
Ta='Taintedhealz:BAAANQADCgEIAQAAAA==.Talys:BAACNQAFFH8cAAIOAAcKABfuAwA8AgAOAAcKABfuAwA8AgA1AAQKfzUAAg4ACQreJB8BAMYDAA4ACQreJB8BAMYDAAAA.Tankly:BAAANQADCgMIAwAAAA==.',
Te='Tehchosen:BAAANQADCggICAAAAA==.Terramor:BAAANQADCgQIBAAAAA==.Texicola:BAABNQAECn8yAAIEAAkKrB7EAgAvAwAEAAkKrB7EAgAvAwAAAA==.',
Th='Thabdeady:BAAANQAECgMIBQABNQAECgkJKAAcAOEOAA==.Thabk:BAABNQAECn8oAAQcAAkK4Q5yFgDiAQAcAAgKig9yFgDiAQAmAAcKkQpZDgBfAQAOAAYKCQvjLAA7AQAAAA==.Thaelorn:BAAANQADCgEIAQAAAA==.Thesyra:BAABNQAECn8YAAMOAAgKFwiqJwB3AQAOAAgKFwiqJwB3AQAmAAMKnwsIGgCbAAAAAA==.Thunderjeed:BAAANQADCggICAABNQAFFAUICAAXABgZAA==.Thurmond:BAABNQAECn8YAAMBAAkK6hnsOgA0AgABAAkKnBTsOgA0AgAMAAYKBBkrWQCLAQAAAA==.Thurmoons:BAAANQAECgYIBwABNQAECgkJGAABAOoZAA==.Thurmund:BAAANQADCgYIBgABNQAECgkJGAABAOoZAA==.',
Ti='Tidalanxiety:BAAANQAECgQIBQAAAA==.',
To='Toastay:BAAANQAECgMIBwAAAA==.Toastz:BAABNQAECn8xAAIdAAkKrSI7CwCDAwAdAAkKrSI7CwCDAwAAAA==.Toebeanz:BAAANQAECgQIDAAAAA==.Tokken:BAACNQAFFH8ZAAILAAcKKBPOBgBPAgALAAcKKBPOBgBPAgA1AAQKfywAAgsACQp1IIY8ANMCAAsACQp1IIY8ANMCAAAA.',
Tr='Treebeast:BAAANQAFFAIIBAAAAA==.Troile:BAAANQADCggIGQAAAA==.Trojen:BAACNQAFFH8HAAIZAAMKVg5NGQDYAAAZAAMKVg5NGQDYAAA1AAQKfx0AAxkACQrvF6iBACACABkACAp/F6iBACACABgACAoYC0N7AKQBAAAA.Trolladin:BAAANQADCgYICgABNQADCggIJQAUAAAAAA==.',
Tw='Twig:BAABNQAECn8eAAIaAAkKXBbDKwB5AgAaAAkKXBbDKwB5AgAAAA==.',
Ty='Tyras:BAAANQAECgQIDAAAAA==.',
['Tâ']='Tâz:BAABNQAECn8kAAIVAAgKTCE4KgC4AgAVAAgKTCE4KgC4AgAAAA==.',
Ul='Ulanda:BAABNQAECn80AAMPAAkKnxXvEABMAgAPAAkKNhTvEABMAgACAAcKIw/aFACpAQAAAA==.',
Um='Umasi:BAACNQAFFH8fAAIiAAcK8iVKAAABAwAiAAcK8iVKAAABAwA1AAQKfywAAiIACQqMJqwBAL8DACIACQqMJqwBAL8DAAAA.',
Un='Underbogg:BAAANQADCgUIBQAAAA==.',
Ut='Utastebad:BAAANQADCggIDAAAAA==.',
Va='Vagabundo:BAAANQAECgMIAwABNQAECgYICwAUAAAAAA==.Vail:BAAANQADCgUIBgAAAA==.Vainquish:BAAANQADCgEIAQAAAA==.Valamaldoran:BAAANQADCgUIBQAAAA==.Vanthil:BAAANQAECgIIAgAAAA==.Vaporize:BAAANQAECgIIAgAAAA==.',
Ve='Venandi:BAAANQAECgcIEQAAAA==.Vengened:BAABNQAECn8dAAILAAgKUBmBVgCEAgALAAgKUBmBVgCEAgABNQAFFAEIAQAUAAAAAA==.Verax:BAAANQAECgIIAgAAAA==.Verestrasz:BAAANQADCgIIBAAAAA==.',
Vg='Vgly:BAAANQAECgQIEAAAAA==.',
Vi='Vilous:BAABNQAECn8jAAIjAAkKMSWFAADVAwAjAAkKMSWFAADVAwAAAA==.',
Vy='Vyisesham:BAABNQAECn8gAAMGAAgKgxlOPwB1AgAGAAgKgxlOPwB1AgAVAAQKhR26pQAjAQAAAA==.',
['Vý']='Výce:BAAANQAECgEIAQAAAA==.',
Wa='Wagtar:BAAANQADCgYICwABNQADCgQIBAAUAAAAAA==.Warzug:BAAANQADCgQIBAAAAA==.',
We='Wesjin:BAABNQAECn8dAAMnAAkKYxNZFAAyAgAnAAkKYxNZFAAyAgAXAAEKHQNQdAAiAAAAAA==.Wez:BAAANQAECgcICwAAAA==.',
Wh='Whiskee:BAABNQAECn8gAAMCAAkKkSPoBAA1AwACAAgKYCLoBAA1AwAPAAcK8yAWEQBKAgAAAA==.',
Wo='Wooglone:BAAANQAECgQJBAAAAA==.',
Wy='Wyndia:BAAANQAFFAIIAgAAAA==.Wyndibear:BAAANQABCgEIAQAAAA==.',
Xa='Xanthos:BAAANQAECgEIAQABNQAECgUIBgAUAAAAAA==.',
Xb='Xbert:BAAANQADCgcIBwAAAA==.',
Xe='Xela:BAAANQABCgYICgABNQAECgkJIAAFACQeAA==.Xenophontes:BAABNQAECn8XAAMEAAkKmB5XGgAeAQAFAAgK3BtXswAbAgAEAAUKFR1XGgAeAQABNQAFFAYIDgAHAEYaAA==.',
Xi='Xihuang:BAABNQAECn8rAAIaAAkKZxeaIADGAgAaAAkKZxeaIADGAgABNQAFFAQIBwAbAHAGAA==.Xiia:BAAANQAECgQIBAAAAA==.',
Xo='Xouu:BAAANQAFFAQIBAABNQAFFAgIBgAVADoRAA==.',
Xx='Xxuu:BAAANQAFFAcIAgABNQAFFAgIBgAVADoRAA==.Xxuusham:BAACNQAFFH8GAAIVAAYKOhEFBwDnAQAVAAYKOhEFBwDnAQA1AAQKfzAAAhUACQpDJQ8CAMYDABUACQpDJQ8CAMYDAAAA.Xxuuspr:BAAANQAECggIAgABNQAFFAgIBgAVADoRAA==.Xxuutwo:BAAANQAECggIAQABNQAFFAgIBgAVADoRAA==.',
Ya='Yaoguai:BAABNQAECn8mAAMaAAkKhxmzIwCwAgAaAAkKhxmzIwCwAgAPAAEKHwloXgAzAAAAAA==.Yasei:BAAANQAECgQIBAAAAA==.Yawgmoth:BAAANQAECgUICgABNQAECgkJIQAQALcbAA==.',
Za='Zaleris:BAAANQAECgQIBQAAAA==.Zaryana:BAAANQAECgcICQAAAA==.',
Ze='Zephon:BAABNQAECn8YAAIdAAgK3g0elADcAQAdAAgK3g0elADcAQAAAA==.',
Zo='Zotiel:BAAANQAFFAQIBAABNQAFFAYIHgABAEYjAA==.',
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
