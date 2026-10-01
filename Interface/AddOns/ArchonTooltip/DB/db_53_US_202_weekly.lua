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

local lookup = {'DeathKnight-Unholy','Druid-Restoration','Druid-Feral','Mage-Frost','Mage-Arcane','Shaman-Elemental','Priest-Holy','Shaman-Enhancement','Warrior-Arms','Unknown-Unknown','DemonHunter-Havoc','DeathKnight-Blood','DeathKnight-Frost','Evoker-Preservation','Druid-Guardian','Monk-Brewmaster','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Shaman-Restoration','DemonHunter-Devourer','Monk-Windwalker','DemonHunter-Vengeance','Paladin-Retribution','Rogue-Subtlety','Paladin-Holy','Evoker-Devastation','Hunter-BeastMastery','Hunter-Marksmanship','Rogue-Outlaw','Rogue-Assassination','Druid-Balance','Paladin-Protection','Warrior-Fury','Priest-Shadow','Priest-Discipline','Mage-Fire','Monk-Mistweaver',}
local provider = {region='US',realm='Spirestone',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Abduon:BAAANQADCgcICwAAAA==.',
Ac='Aciddeath:BAAANQAECgEIAQABNQAECgkJIgABAOkiAA==.',
Ad='Admaris:BAABNQAECoEnAAMCAAkKqh+pBwAdAwACAAkKqh+pBwAdAwADAAcKkh6hBwCAAgAAAA==.',
Ae='Aelis:BAAANQABCgEIAQAAAA==.',
Ag='Agni:BAACNQAFFIERAAMEAAcKShVKAQADAQAFAAQKFRbXFgBfAQAEAAMKOxRKAQADAQA1AAQKgR0AAwUACQrwIsM5APYCAAUACQrwIsM5APYCAAQAAQpCGNE4ADcAAAAA.',
Ak='Akkadian:BAAANQADCggICAAAAA==.',
Al='Alnasham:BAACNQAFFIEGAAIGAAQKfAo+DQAdAQAGAAQKfAo+DQAdAQA1AAQKgSYAAgYACQo9IK8QAEgDAAYACQo9IK8QAEgDAAAA.Alnava:BAAANQAECgUJCQAAAA==.Alvoka:BAAANQAECgYJEQAAAA==.',
Am='Amarillos:BAAANQAECgYIBgAAAA==.Amarillys:BAABNQAECoEZAAIHAAkKpRrILQBxAgAHAAkKpRrILQBxAgAAAA==.Ammutseba:BAAANQAECgUIDgAAAA==.',
An='Anfall:BAABNQAECoEhAAIIAAkKjxxvBgD6AgAIAAkKjxxvBgD6AgAAAA==.Angermeier:BAABNQAECoEZAAIJAAcKWRSjewDTAQAJAAcKWRSjewDTAQAAAA==.Angrylady:BAAANQAECgEIAQAAAA==.Anjuna:BAAANQADCgUIBQAAAA==.Anohru:BAAANQAECggIAwAAAA==.Anthos:BAAANQAECgUIBQAAAA==.Antikreist:BAAANQADCgQJBAAAAA==.',
Ap='Aphotic:BAAANQAECgEIAQAAAA==.',
Ar='Ards:BAAANQADCgIIAwAAAA==.Armanite:BAAANQAECgQIBQABNQAECggIEAAKAAAAAA==.Arthaniis:BAAANQAECgYJEwAAAA==.',
As='Asystoli:BAAANQAECgUIBgAAAA==.',
At='Atheria:BAAANQADCgYIBwAAAA==.Attackheli:BAAANQAECgMIAwAAAA==.',
Au='Audideath:BAAANQAECgMIAwAAAA==.Auurdeath:BAAANQADCggIEwAAAA==.',
Av='Av:BAAANQADCgIIBAAAAA==.',
Aw='Aw:BAACNQAFFIEOAAILAAUKOiMUAwAEAgALAAUKOiMUAwAEAgA1AAQKgSIAAgsACQryJZsCAL8DAAsACQryJZsCAL8DAAAA.',
Ax='Ax:BAECNQAFFIEGAAMBAAQKjxj1CAAEAQABAAMKtB31CAAEAQAMAAEKIQmBKgAkAAA1AAQKgSAAAgEACQqIH7kWAMwCAAEACQqIH7kWAMwCAAAA.',
Az='Azzazinzblo:BAAANQADCgUIBQAAAA==.',
['Aÿ']='Aÿa:BAAANQAECgQIBAAAAA==.',
Ba='Bamph:BAAANQAECgYJCwAAAA==.Bangbang:BAAANQAECgcIDwAAAA==.Batez:BAAANQAECgQIBAABNQAFFAUICgANAP8NAA==.',
Bd='Bdk:BAAANQAECgUICQAAAA==.Bdog:BAAANQAECgEIAwAAAA==.',
Be='Beeatinu:BAAANQADCgYICQAAAA==.Beledros:BAABNQAECoEcAAIOAAkKVBP/EABsAgAOAAkKVBP/EABsAgAAAA==.Beni:BAABNQAECoEsAAMPAAkKiiGsAgBiAwAPAAkKiiGsAgBiAwADAAQKDQuUHQDGAAAAAA==.Benson:BAABNQAECoEhAAIQAAkKoB1lBQDOAgAQAAkKoB1lBQDOAgAAAA==.Bensonadin:BAAANQAECgYIBgAAAA==.Berd:BAAANQAECggIBgAAAA==.',
Bi='Bina:BAAANQAECgQIBQAAAA==.Birblock:BAACNQAFFIEbAAMRAAYKeyAsAQBjAgARAAYKeyAsAQBjAgASAAIKygFsDgCIAAA1AAQKgSAABBEACQogJvIgAM0CABEABwojJvIgAM0CABIABwpLGLYQAOUBABMAAQpHIMYgAEkAAAAA.',
Bo='Bobbo:BAAANQADCgYJBwAAAA==.',
Br='Brek:BAAANQAECgUIBgAAAA==.Brewtherguy:BAABNQAECoEfAAIQAAgKux2aBgCgAgAQAAgKux2aBgCgAgAAAA==.Bruceshepard:BAAANQADCgQIBwABNQAECgIIAgAKAAAAAA==.Brutebuffalo:BAABNQAECoEfAAMUAAgKuh6IIQCrAgAUAAgKuh6IIQCrAgAGAAEKUw9i/gAyAAAAAA==.Bruteflappy:BAAANQADCggICAABNQAECggIHwAUALoeAA==.Brutetestify:BAAANQADCggICAABNQAECggIHwAUALoeAA==.',
Bu='Bubbleboi:BAAANQADCgYICAAAAA==.Bubblebôy:BAAANQAECgIIAgAAAA==.Bublz:BAAANQAECgcIDgAAAA==.',
['Bâ']='Bâra:BAABNQAECoEZAAIBAAgKihxoGgCtAgABAAgKihxoGgCtAgAAAA==.',
Ca='Carnal:BAAANQADCgUIBQAAAA==.',
Ce='Cedren:BAABNQAECoEkAAMLAAkK5hqJGACSAgALAAkKBRqJGACSAgAVAAgKARYUIAARAgAAAA==.Ceewhya:BAAANQAECgEIAQAAAA==.Celestika:BAAANQABCgIIAgAAAA==.Cerari:BAAANQAECgEJAQAAAA==.',
Ch='Chalix:BAAANQADCgYICAAAAA==.Chama:BAABNQAECoEZAAIVAAgKNxHyHwATAgAVAAgKNxHyHwATAgAAAA==.Cheapheal:BAABNQAECoEkAAIPAAkK+x1mBAAVAwAPAAkK+x1mBAAVAwAAAA==.Cheburashka:BAACNQAFFIEJAAIGAAQK3R26CAB7AQAGAAQK3R26CAB7AQA1AAQKgRwAAgYACQpSH5AeAOECAAYACQpSH5AeAOECAAAA.Chimerabob:BAAANQAECgIIAwAAAA==.Chunkymonkey:BAACNQAFFIELAAIWAAUKDRvaAwCvAQAWAAUKDRvaAwCvAQA1AAQKgSYAAhYACQpMIQYJABkDABYACQpMIQYJABkDAAAA.',
Ci='Cidren:BAAANQAECgEJAQAAAA==.',
Cl='Clappncheeks:BAAANQAECgQIBQAAAA==.Claudefrollo:BAAANQAECgQIBQAAAA==.',
Cr='Crankyelf:BAAANQABCgEIAQAAAA==.Crimsa:BAABNQAECoEYAAITAAgKsQNkDABKAQATAAgKsQNkDABKAQAAAA==.Crimsonaxel:BAAANQAECgcIEQAAAA==.Cryogen:BAAANQAECgQJCAAAAA==.',
Cu='Cursewords:BAAANQADCgUIBQABNQAECgYIBgAKAAAAAA==.',
Da='Daemonproph:BAAANQADCgYIDAAAAA==.Dakini:BAAANQAECgYIEQAAAA==.Dam:BAAANQADCgUIBQABNQAECggIHQAMAAoaAA==.Dangerruss:BAAANQAECgUICQAAAA==.Dashytash:BAABNQAECoEZAAIXAAcKbhp1CAAUAgAXAAcKbhp1CAAUAgAAAA==.Dawnsoul:BAAANQAECgYIDQAAAA==.Daxos:BAAANQADCgcICAAAAA==.',
De='Demb:BAAANQAECgQIBwAAAA==.Demonicchoas:BAABNQAECoElAAMSAAkKaR1RCgBAAgARAAgKuhqEPgBYAgASAAcKzR1RCgBAAgAAAA==.Denagorn:BAABNQAECoEkAAIYAAkKfyS8CQCYAwAYAAkKfyS8CQCYAwABNQAFFAUIEgABALsaAA==.Denhunt:BAAANQADCggICAABNQAFFAUIEgABALsaAA==.Dentsama:BAAANQADCgEIAQAAAA==.Deplete:BAAANQADCgIJAgABNQAECgcIEgAKAAAAAA==.Deutzfr:BAABNQAECoEYAAIXAAkKlRzqAwDIAgAXAAkKlRzqAwDIAgAAAA==.Develop:BAAANQAECgMIBAAAAA==.Devos:BAAANQAECgYIEwABNQAECgkJIQAGANkYAA==.',
Di='Dizzleman:BAAANQAECggIAgAAAA==.',
Do='Dominant:BAABNQAECoEcAAMFAAgKUR4kUQC3AgAFAAgKUR4kUQC3AgAEAAEKtwsjOwAyAAAAAA==.',
Dp='Dpssos:BAAANQAECgYIDAAAAA==.',
Dr='Drag:BAAANQADCgYICAAAAA==.Dreadmar:BAAANQADCgYICAAAAA==.Drock:BAAANQAECgYIEgAAAA==.Druidgale:BAAANQAECgIIAwAAAA==.Drybonez:BAAANQAECgQIBQAAAA==.Drygth:BAAANQADCgMJBQABNQAECggIHgAZAOEeAA==.Dräkarnoir:BAAANQADCggICAAAAA==.',
Dt='Dtb:BAABNQAECoEcAAIMAAkKrh4REgD0AgAMAAkKrh4REgD0AgABNQAFFAEIAQAKAAAAAA==.',
Du='Dushimaya:BAABNQAECoEgAAIaAAkKMSA0DQA+AwAaAAkKMSA0DQA+AwAAAA==.',
Dv='Dvil:BAAANQAECgQIBQABNQAECgYIEgAKAAAAAA==.',
Dw='Dwyndi:BAAANQAECgYJBgAAAA==.',
Ei='Eisador:BAAANQAECgYICwAAAA==.',
El='Elsen:BAAANQAECgQICQAAAA==.Elsha:BAABNQAECoEeAAIQAAgKWxveBwB3AgAQAAgKWxveBwB3AgAAAA==.',
Em='Emp:BAAANQAECgUIBgAAAA==.',
Er='Erilee:BAAANQAECgUICgAAAA==.',
Ev='Evelira:BAABNQAFFIEGAAIHAAQKkBUuDQBbAQAHAAQKkBUuDQBbAQAAAA==.',
Ey='Eyja:BAAANQADCgEIAgAAAA==.',
Ez='Ezailas:BAAANQAECgMIAwAAAA==.Ezpzndaheezy:BAAANQADCgYIBgABNQAECggIGgAbAAcVAA==.',
Fa='Fathercoast:BAAANQAECgYICwAAAA==.',
Fe='Fearful:BAACNQAFFIEFAAIaAAMKYAK2EQDIAAAaAAMKYAK2EQDIAAA1AAQKgSIAAhoACQr5FQsxAGYCABoACQr5FQsxAGYCAAAA.Felstrider:BAAANQADCgUIBQAAAA==.Ferador:BAACNQAFFIEJAAMcAAQKsBMPDQADAQAcAAMKwBgPDQADAQAdAAEKgQTOHAA/AAA1AAQKgR8AAxwACQopH/MnAL0CABwACQopH/MnAL0CAB0ABQqaDQ08AAkBAAAA.',
Fi='Figgleslock:BAAANQADCgUIBQAAAA==.',
Fl='Flakester:BAAANQAECgYIEgAAAA==.Fleebly:BAABNQAECoEdAAIVAAgKZBnuFgB4AgAVAAgKZBnuFgB4AgAAAA==.',
Fn='Fndruid:BAAANQAECgIIAgAAAA==.',
Fo='Fourbees:BAABNQAECoEaAAIYAAgK9gmeigCoAQAYAAgK9gmeigCoAQAAAA==.',
Fu='Fursure:BAAANQAECgMIAwAAAA==.',
Ga='Garfal:BAAANQAECgIIAwAAAA==.Gather:BAAANQABCgQIBAABNQAECggIJAAUADQXAA==.',
Gi='Gilgamesh:BAAANQAECgYJCwAAAA==.',
Go='Gorobob:BAAANQAECgIIBAAAAA==.',
Gr='Graygkl:BAAANQAECgUIDwAAAA==.Greshanwise:BAAANQAECgUICAAAAA==.Grimreaper:BAABNQAECoEeAAIeAAgK0xTnBgApAgAeAAgK0xTnBgApAgAAAA==.Groa:BAAANQABCgQIBgAAAA==.Groag:BAABNQAECoEeAAMZAAgK4R7MCADUAgAZAAgKyx3MCADUAgAfAAcKAhqfIwAIAgAAAA==.',
Ha='Haarp:BAAANQAECgQIBwAAAA==.Hakü:BAAANQAECgYIBwAAAA==.Hammered:BAAANQAECgQIAwAAAA==.Hardwire:BAAANQAECgEIAQAAAA==.',
He='Heartred:BAAANQADCgYIBgAAAA==.Heifer:BAABNQAECoEkAAIgAAkKTyHtEAAfAwAgAAkKTyHtEAAfAwABNQAFFAEJAQAKAAAAAA==.Hemophilia:BAAANQAECgYIEgAAAA==.Heydk:BAABNQAECoEVAAMNAAgKcBrNPwBRAQANAAUKYhrNPwBRAQABAAUKoBWoXAA4AQAAAA==.Heydruid:BAAANQAECgUIBQABNQAECggIFQANAHAaAA==.',
Ho='Hollowshädix:BAAANQAECgEIAQAAAA==.Holyanxiety:BAAANQADCgYIBgAAAA==.Holydave:BAAANQAECgMIBAAAAA==.Holymentos:BAAANQAECgYIDQABNQAECggIGAAhAN4PAA==.Hottsauce:BAABNQAECoEYAAIIAAkK0hVLCgCZAgAIAAkK0hVLCgCZAgAAAA==.Hottsaucefel:BAAANQAECgYJBgAAAA==.',
Hu='Hundard:BAAANQADCgIIAgAAAA==.Huntersmarc:BAAANQAECgEIAQAAAA==.Hushhides:BAAANQAECggIDgAAAA==.',
Ia='Iamachick:BAAANQAECgEIAQAAAA==.',
Ib='Ibetrollinya:BAAANQAECgEIAgABNQAECggIGAAiAEklAA==.Iblisshaytan:BAABNQAECoEjAAILAAkKhhYsGQCNAgALAAkKhhYsGQCNAgABNQAECgkJIgAZAKsVAA==.Ibtrollin:BAAANQADCggIJQAAAA==.',
Ig='Ignacious:BAAANQAECgEIAQAAAA==.',
Il='Illumina:BAAANQAFFAEIAQAAAA==.',
Io='Ionissa:BAAANQAECgcIEgAAAA==.',
Is='Ischia:BAABNQAECoEqAAMHAAkK5RdGKQCHAgAHAAkK5RdGKQCHAgAjAAIK3w22UgBjAAAAAA==.',
Ja='Jarl:BAAANQADCgYICwAAAA==.',
Jc='Jch:BAACNQAFFIERAAIcAAYKgBlzAQArAgAcAAYKgBlzAQArAgA1AAQKgSYAAxwACQpeJYsIAHsDABwACQpeJYsIAHsDAB0AAQpkFktmAD4AAAAA.',
Je='Jeay:BAAANQAECgEJAQAAAA==.Jedijeed:BAABNQAECoEiAAIWAAkKFSCDCgD/AgAWAAkKFSCDCgD/AgAAAA==.Jedikepjr:BAAANQAFFAMIAwABNQAECgkJIgAWABUgAA==.Jenova:BAAANQADCgUIBwAAAA==.Jepage:BAAANQAECgYIEwAAAA==.Jess:BAAANQABCgIIAgAAAA==.',
Jo='Jolyne:BAAANQAECgQIBAAAAA==.',
Jp='Jprottsoo:BAABNQAECoEgAAIgAAgKfx+/FwDeAgAgAAgKfx+/FwDeAgAAAA==.',
Ju='Jubei:BAAANQAECgcIEwAAAA==.',
Ka='Kalmya:BAABNQAECoEeAAMCAAgKdw35IgCuAQACAAgKdw35IgCuAQADAAEKzgcHLwAvAAAAAA==.Kalrath:BAAANQAECgIIAgABNQAECggIEAAKAAAAAA==.',
Ke='Keizzer:BAAANQAECgcICwABNQAECgcIEwAKAAAAAA==.Keshisaru:BAAANQADCgQIBAAAAA==.',
Kh='Khazra:BAAANQAECgMIBgAAAA==.',
Ki='Kierràalexis:BAAANQADCgYIBgAAAA==.',
Kl='Klunder:BAABNQAECoEWAAIUAAgKGiHZFgDrAgAUAAgKGiHZFgDrAgAAAA==.',
Ko='Korris:BAABNQAECoEbAAMcAAgKuh0GLQCnAgAcAAgKuh0GLQCnAgAdAAEK1wL7eAAiAAAAAA==.Kostik:BAAANQADCgUIBQAAAA==.',
Kr='Kridillis:BAAANQAECgcJEwAAAA==.',
Ky='Kybinc:BAAANQADCgQIBAAAAA==.',
['Kí']='Kírã:BAAANQABCgIIBAAAAA==.',
La='Lawls:BAAANQADCgQIBwAAAA==.Lazybigger:BAAANQAECgIIAgAAAA==.Lazycow:BAABNQAECoEgAAIPAAkKBxSPDAAnAgAPAAkKBxSPDAAnAgAAAA==.Lazyfrost:BAABNQAECoEdAAIFAAgKnQ6mogD0AQAFAAgKnQ6mogD0AQAAAA==.',
Le='Lethò:BAABNQAECoEgAAMaAAgKLCNLDwAuAwAaAAgKLCNLDwAuAwAYAAQKvBNa5gDcAAAAAA==.Lethô:BAAANQAECgIIAwAAAA==.Lethö:BAAANQAECgIIBQAAAA==.',
Li='Liesx:BAAANQAECgcIDQABNQAFFAUICgANAP8NAA==.Lilzarthe:BAAANQAECgQIDAAAAA==.Lindsybowhan:BAAANQABCggIEAAAAA==.',
Lo='Loerasdh:BAABNQAECoEcAAILAAcKrSZjDAAbAwALAAcKrSZjDAAbAwAAAA==.Loko:BAACNQAFFIEMAAIgAAUKuxXkBwCiAQAgAAUKuxXkBwCiAQA1AAQKgSQAAiAACQqTIqEMAEoDACAACQqTIqEMAEoDAAAA.Looio:BAAANQADCgMIAgAAAA==.',
Lu='Lucien:BAAANQABCgQIBAAAAA==.Lumièrevide:BAAANQABCgMIAwAAAA==.Luxxus:BAAANQAECgcIEwAAAA==.',
Ly='Lyesx:BAAANQAECggIEgABNQAFFAUICgANAP8NAA==.Lyndsy:BAAANQADCgUIBQAAAA==.Lyri:BAAANQADCgMIAwAAAA==.',
Ma='Macros:BAAANQAECgEIAgAAAA==.Mageyousad:BAAANQADCgEIAgAAAA==.Maixia:BAAANQAECgIIBQAAAA==.Makhtor:BAAANQAECgMIBQAAAA==.Mallaer:BAABNQAECoEYAAIHAAgKYiLBGADkAgAHAAgKYiLBGADkAgAAAA==.Malícíous:BAABNQAECoEaAAIRAAcKDBTdZwDQAQARAAcKDBTdZwDQAQAAAA==.Mantakore:BAABNQAECoEgAAIOAAkKkRRXEQBnAgAOAAkKkRRXEQBnAgAAAA==.Marcdruid:BAAANQAECgQJBwAAAA==.Maubles:BAAANQADCggJCAABNQAECgkJGwAhAFoOAA==.',
Me='Menopaws:BAABNQAECoEdAAIPAAgKBiWyAgBhAwAPAAgKBiWyAgBhAwAAAA==.Merrtt:BAAANQAECgYIBgAAAA==.Mertrik:BAABNQAECoEdAAMUAAgK+yNbDwAhAwAUAAgK+yNbDwAhAwAGAAMKBBTFugDCAAAAAA==.',
Mi='Midk:BAAANQAECgIIAwAAAA==.Mikayy:BAABNQAECoEvAAIZAAkKrSXnAADLAwAZAAkKrSXnAADLAwAAAA==.Milenko:BAABNQAECoEXAAILAAcKeCGBFwCcAgALAAcKeCGBFwCcAgAAAA==.Milly:BAAANQAECgMIBQABNQAECgcIFwALAHghAA==.',
Mo='Molfsongal:BAAANQADCgIIAgAAAA==.Monstrous:BAACNQAFFIEJAAIJAAQKHAuHEgAhAQAJAAQKHAuHEgAhAQA1AAQKgSgAAgkACQoaH10nAPMCAAkACQoaH10nAPMCAAAA.Moocher:BAAANQAECgEIAQAAAA==.Moonpie:BAAANQADCgUICQAAAA==.Mordecaii:BAAANQADCgYIDgAAAA==.Morgul:BAAANQAECgQIBgAAAA==.Mothman:BAAANQAECgMJBAAAAA==.Moyana:BAAANQADCgEIAQAAAA==.',
Ms='Msbehaven:BAAANQAECgYIEwAAAA==.',
Mt='Mthafknfreez:BAAANQAECgQIBAABNQAECgkJIgAZAKsVAA==.',
Mu='Muffìns:BAAANQAECgQIBQAAAA==.Musashi:BAAANQAECgYIDwAAAA==.',
My='Mynuturchin:BAAANQAECgcIDQAAAA==.',
Na='Nagy:BAAANQADCgcIDAAAAA==.',
Ni='Night:BAAANQAECgYIEAAAAA==.Nightsecho:BAAANQAECgEIAQAAAA==.Nightshris:BAAANQAECgIIAgAAAA==.',
No='Notmehssos:BAAANQAECgYICgAAAA==.Notthechosen:BAAANQAECgMIAwABNQAECgYIDAAKAAAAAA==.',
Ny='Nymeriã:BAAANQAECgEIAQAAAA==.',
Ob='Obzy:BAAANQAECgcIEwAAAA==.Obzz:BAAANQADCgEIAQABNQAECgcIEwAKAAAAAA==.',
Ok='Okamy:BAAANQAECgYJCwABNQAECgMIAwAKAAAAAA==.',
Ol='Olympicjeid:BAAANQAECgQICAABNQAECgkJIgAWABUgAA==.',
Op='Opz:BAABNQAECoEiAAMjAAgKHhtLFgBmAgAjAAgKHhtLFgBmAgAkAAIKiBZfFgCKAAAAAA==.',
Pa='Paladinfive:BAAANQAECgEIAQAAAA==.Parthos:BAAANQAECgQICgAAAA==.',
Pe='Pedro:BAAANQADCgcIEAABNQADCggIEQAKAAAAAA==.Perry:BAAANQADCgIIAgAAAA==.',
Ph='Phenomenon:BAAANQAECgQIAwAAAA==.',
Pi='Pittydafoo:BAAANQAECgIIAgAAAA==.',
Pk='Pkunkk:BAAANQAECgcJCwAAAA==.',
Pl='Ploxis:BAACNQAFFIEGAAIXAAQK9RCEAQAEAQAXAAQK9RCEAQAEAQA1AAQKgRUAAhcACQouGEwFAIwCABcACQouGEwFAIwCAAAA.',
Po='Polskashaman:BAAANQAECgUIDQAAAA==.Pookiebonez:BAAANQADCgIIAgABNQAECgQIBQAKAAAAAA==.',
Pr='Prea:BAAANQAFFAIIAgAAAA==.Premiumferal:BAABNQAECoEbAAMfAAkK8iDSDwDBAgAfAAkK8iDSDwDBAgAZAAUKFBkBKQBKAQAAAA==.Primecarry:BAACNQAFFIEJAAIaAAQKhBMVCwBFAQAaAAQKhBMVCwBFAQA1AAQKgR4AAhoACQp1I+YGAHsDABoACQp1I+YGAHsDAAAA.Prine:BAABNQAECoEZAAIJAAkKLh4EHAAoAwAJAAkKLh4EHAAoAwABNQAFFAQICQAaAIQTAA==.',
Pu='Puripuri:BAAANQAECgQIBAAAAA==.',
Qi='Qinkipa:BAAANQAECgEIAQAAAA==.',
Qo='Qovo:BAAANQABCggIDgAAAA==.',
Ra='Ragark:BAAANQABCgMIAwAAAA==.Raigko:BAABNQAECoEjAAIJAAkKlCJPFwBBAwAJAAkKlCJPFwBBAwAAAA==.Rainyday:BAABNQAECoEUAAIUAAYK9ApYkQAFAQAUAAYK9ApYkQAFAQAAAA==.Raiva:BAAANQAECgIIBAABNQAECgUIBgAKAAAAAA==.Raivek:BAAANQAECgIIAgAAAA==.Randenton:BAAANQADCgYICAAAAA==.Randezoth:BAAANQABCggIDQABNQADCgYICAAKAAAAAA==.Rassputen:BAABNQAECoElAAIMAAkKjxFUOQDgAQAMAAkKjxFUOQDgAQAAAA==.',
Re='Reck:BAAANQADCgEIAQAAAA==.Redjive:BAAANQAECggIAQAAAA==.Redonkulos:BAAANQADCgMIBAAAAA==.Reliri:BAAANQADCgYIBgAAAA==.Relis:BAAANQABCgYICAAAAA==.Renais:BAAANQAECgMIAwAAAA==.Rex:BAABNQAECoEdAAIMAAgKChpcJwBLAgAMAAgKChpcJwBLAgAAAA==.',
Ri='Rileyesco:BAAANQABCgUIBgAAAA==.Ripskylark:BAAANQAECgIIAwAAAA==.Risk:BAAANQABCgcIEAAAAA==.',
Ro='Roguen:BAABNQAECoEiAAMZAAkKqxUSDACZAgAZAAkKqxUSDACZAgAfAAMKhgh6WgCyAAAAAA==.Romirin:BAAANQADCgQJBAAAAA==.Rotan:BAAANQADCgYICwAAAA==.Roulduke:BAABNQAECoEXAAIGAAcKgglEcAB6AQAGAAcKgglEcAB6AQAAAA==.',
['Rù']='Rùckús:BAABNQAECoEhAAIBAAgKuR3mHgCJAgABAAgKuR3mHgCJAgAAAA==.',
Sa='Sacredmentos:BAABNQAECoEYAAIhAAgK3g9wHgCZAQAhAAgK3g9wHgCZAQAAAA==.Salaen:BAAANQAECggIAQAAAA==.Sammybeans:BAAANQAECgIIAgAAAA==.Sapito:BAAANQADCgYICgAAAA==.',
Sc='Scarecrow:BAAANQADCgMIAwABNQAECgcIFwALAHghAA==.',
Se='Seceron:BAAANQAECgUIDAAAAA==.Sekai:BAAANQADCgcICQAAAA==.',
Sg='Sgtslappy:BAAANQADCgMIAwAAAA==.',
Sh='Shanarelle:BAAANQAECgYIEwAAAA==.Shasa:BAABNQAECoEWAAIcAAkKQR0mJADNAgAcAAkKQR0mJADNAgAAAA==.Shatteredsky:BAABNQAECoEeAAMUAAgKrBzxLABuAgAUAAgKrBzxLABuAgAGAAEKqgOWCAEsAAAAAA==.Shazik:BAABNQAECoEkAAIUAAgKNBdhQAAUAgAUAAgKNBdhQAAUAgAAAA==.Shazzik:BAAANQAECgYICgABNQAECggIJAAUADQXAA==.Shilbalam:BAAANQADCgQIBAAAAA==.Shmoopy:BAAANQAECgEIAQAAAA==.Shmoove:BAAANQADCgEIAQAAAA==.Shnkz:BAAANQADCgcJBwAAAA==.Shotzer:BAAANQADCgMIBgAAAA==.',
Si='Silzo:BAAANQAECgUIBgAAAA==.Sirjames:BAAANQADCggIDgAAAA==.',
Sk='Skelix:BAACNQAFFIEaAAIUAAYKZyJtAQB1AgAUAAYKZyJtAQB1AgA1AAQKgSoAAhQACQpLJjYCALMDABQACQpLJjYCALMDAAAA.Skunkpaw:BAAANQADCgUICwAAAA==.Skysong:BAACNQAFFIEGAAIbAAQK5hPZBAA8AQAbAAQK5hPZBAA8AQA1AAQKgR4AAxsACQpLH0MIAM8CABsACQpLH0MIAM8CAA4AAwp/Bcs2AJcAAAAA.',
Sl='Slashedeye:BAABNQAECoEmAAIlAAYKdhP8AgChAQAlAAYKdhP8AgChAQAAAA==.Slimgucci:BAAANQADCggICAAAAA==.',
Sn='Snowynn:BAAANQAECgcIEwAAAA==.Snubby:BAABNQAECoEbAAMRAAgKuiTRNQB4AgARAAYKfSTRNQB4AgASAAIKcyUINADeAAAAAA==.',
So='Solheim:BAAANQABCgUIBQAAAA==.Sonari:BAAANQADCgYIBgAAAA==.',
Sp='Spankz:BAAANQAECgMIBgAAAA==.Spathi:BAAANQADCggICAAAAA==.Spicymeatbal:BAAANQABCggICwAAAA==.',
St='Stepz:BAAANQABCggICgAAAA==.Strathz:BAABNQAECoEfAAMRAAgK0h8/JgC2AgARAAgK8Rw/JgC2AgASAAQKVxsbJAA9AQAAAA==.Strongish:BAAANQADCgUIBQAAAA==.',
Su='Summerset:BAAANQAECgIIAQAAAA==.Sunstrider:BAAANQADCgIIAgAAAA==.Superdonkey:BAAANQADCgYICwABNQAFFAUICwAWAA0bAA==.Sushi:BAAANQADCgIIAgAAAA==.Suva:BAAANQADCgYIBgAAAA==.',
Sy='Sylatis:BAAANQAECgYIDAABNQAFFAYIGwARAHsgAA==.Sylätis:BAAANQAECgMJAwABNQAFFAYIGwARAHsgAA==.',
['Sö']='Söultender:BAAANQADCgMIAwABNQAECgYIDQAKAAAAAA==.',
['Sø']='Sølidus:BAAANQAECgMIAwABNQAFFAQIBgAHAJAVAA==.',
Ta='Talys:BAACNQAFFIESAAIOAAYKIRffAwADAgAOAAYKIRffAwADAgA1AAQKgScAAg4ACQrjHvIIAPQCAA4ACQrjHvIIAPQCAAAA.Tankly:BAAANQADCgMIAwAAAA==.',
Te='Tehchosen:BAAANQADCggICAAAAA==.Terramor:BAAANQADCgQIBAAAAA==.Texicola:BAABNQAECoEiAAIEAAgKLx6lAwDIAgAEAAgKLx6lAwDIAgAAAA==.',
Th='Thabdeady:BAAANQAECgIIAgABNQAECggIGgAbAAcVAA==.Thabk:BAABNQAECoEaAAMbAAgKBxVrFADEAQAbAAcK6xJrFADEAQAOAAYKowkqJgA8AQAAAA==.Thaelorn:BAAANQADCgEIAQAAAA==.Thesyra:BAAANQAECgYICwAAAA==.Thurmond:BAAANQAECggIEAAAAA==.Thurmoons:BAAANQAECgEIAQABNQAECggIEAAKAAAAAA==.Thurmund:BAAANQADCgYIBgABNQAECggIEAAKAAAAAA==.',
Ti='Tidalanxiety:BAAANQAECgQIBQAAAA==.',
To='Toastay:BAAANQAECgIIAgAAAA==.Toastz:BAABNQAECoEhAAIcAAgKCyAbIQDbAgAcAAgKCyAbIQDbAgAAAA==.Toebeanz:BAAANQAECgQIDAAAAA==.Tokken:BAACNQAFFIENAAIJAAYKOxFvCQC0AQAJAAYKOxFvCQC0AQA1AAQKgSYAAgkACQrVH0IoAO8CAAkACQrVH0IoAO8CAAAA.',
Tr='Treebeast:BAAANQAFFAIIBAAAAA==.Troile:BAAANQADCgYIDAAAAA==.Trojen:BAAANQAFFAEIAQAAAA==.Trolladin:BAAANQADCgYICgABNQADCggIJQAKAAAAAA==.',
Tw='Twig:BAAANQAECggIEgAAAA==.',
Ty='Tyras:BAAANQAECgMIBgAAAA==.',
['Tâ']='Tâz:BAABNQAECoEjAAIUAAgKTCHYGgDSAgAUAAgKTCHYGgDSAgAAAA==.',
Ul='Ulanda:BAABNQAECoEaAAMPAAcKlxVdEQDHAQAPAAcKlxVdEQDHAQADAAUK/QYhGwDiAAAAAA==.',
Um='Umasi:BAACNQAFFIESAAIhAAYKayZVAACqAgAhAAYKayZVAACqAgA1AAQKgSYAAiEACQpUJhYBAMoDACEACQpUJhYBAMoDAAAA.',
Un='Underbogg:BAAANQADCgUIBQAAAA==.',
Ut='Utastebad:BAAANQADCggIDAAAAA==.',
Va='Vagabundo:BAAANQAECgMIAwABNQAECgYICwAKAAAAAA==.Vail:BAAANQADCgMIBAAAAA==.Valamaldoran:BAAANQADCgUIBQAAAA==.Vanthil:BAAANQAECgIIAgAAAA==.Vaporize:BAAANQADCgUIBQAAAA==.',
Ve='Venandi:BAAANQAECgcIEQAAAA==.Vengened:BAAANQAECgYIDAAAAA==.Verax:BAAANQAECgIIAgAAAA==.Verestrasz:BAAANQADCgIIBAAAAA==.',
Vg='Vgly:BAAANQAECgQIDwAAAA==.',
Vi='Vilous:BAABNQAECoEYAAIiAAgKSSVOAQBrAwAiAAgKSSVOAQBrAwAAAA==.',
Vy='Vyisesham:BAAANQAECgYIEwAAAA==.',
['Vý']='Výce:BAAANQAECgEIAQAAAA==.',
Wa='Wagtar:BAAANQADCgYICwABNQADCgQIBAAKAAAAAA==.Warzug:BAAANQADCgQIBAAAAA==.',
We='Wesjin:BAABNQAECoEYAAMmAAgKvhHmFADYAQAmAAgKvhHmFADYAQAWAAEKHQM1WgAlAAAAAA==.Wez:BAAANQAECgEIAQAAAA==.',
Wh='Whiskee:BAAANQAECgYIEwAAAA==.',
Wo='Wooglone:BAAANQAECgQJBAAAAA==.',
Wy='Wyndia:BAAANQAFFAIIAgAAAA==.',
Xa='Xanthos:BAAANQAECgEIAQABNQAECgQIBgAKAAAAAA==.',
Xb='Xbert:BAAANQADCgcIBwAAAA==.',
Xe='Xela:BAAANQABCgYICgABNQAECggIHAAFAFEeAA==.Xenophontes:BAAANQAECgcJEwABNQAFFAQIBgAHAJAVAA==.',
Xi='Xihuang:BAABNQAECoEbAAIgAAgK5BZwLAA1AgAgAAgK5BZwLAA1AgABNQAECgkJIgAZAKsVAA==.Xiia:BAAANQADCggICwAAAA==.',
Xo='Xouu:BAAANQAECggIAQABNQAECggIBQAKAAAAAA==.',
Xx='Xxuublue:BAAANQAECggIBQAAAA==.Xxuuspr:BAAANQAECggIAgABNQAECggIBQAKAAAAAA==.Xxuutwo:BAAANQAECggIAQABNQAECggIBQAKAAAAAA==.',
Ya='Yaoguai:BAAANQAECgcIEgAAAA==.Yasei:BAAANQAECgQIBAAAAA==.Yawgmoth:BAAANQAECgQIBQABNQAECggIHgAQAFsbAA==.',
Za='Zaleris:BAAANQAECgQIBQAAAA==.',
Ze='Zephon:BAAANQAECgQIDQAAAA==.',
Zo='Zotiel:BAAANQADCgcIDwABNQAFFAUIEgABALsaAA==.',
Zy='Zynisch:BAAANQADCgcIEwAAAA==.',
['Ær']='Æris:BAAANQADCgMIAwAAAA==.',
['Ìr']='Ìroh:BAAANQADCgUIBgABNQAECgYIDQAKAAAAAA==.',
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
