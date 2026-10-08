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

local lookup = {'DeathKnight-Unholy','Druid-Restoration','Druid-Feral','Mage-Frost','Mage-Arcane','Shaman-Elemental','Priest-Holy','DemonHunter-Havoc','DemonHunter-Vengeance','Shaman-Enhancement','Warrior-Arms','DeathKnight-Blood','Rogue-Assassination','Evoker-Preservation','Druid-Guardian','Monk-Brewmaster','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Unknown-Unknown','Shaman-Restoration','DemonHunter-Devourer','Monk-Windwalker','Paladin-Holy','Paladin-Retribution','Druid-Balance','Rogue-Subtlety','Evoker-Devastation','Hunter-BeastMastery','Hunter-Marksmanship','Rogue-Outlaw','DeathKnight-Frost','Paladin-Protection','Warrior-Fury','Priest-Shadow','Mage-Fire','Priest-Discipline','Monk-Mistweaver',}
local provider = {region='US',realm='Spirestone',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abduon:BAAANQADCgcICwAAAA==.',
Ac='Aciddeath:BAAANQAECgEIAQABNQAFFAQICAABACcSAA==.',
Ad='Admaris:BAACNQAFFIEFAAMCAAIKIBFqDQCZAAACAAIKIBFqDQCZAAADAAEKsA4zBABMAAA1AAQKgSoAAwIACQqqHyoKAAoDAAIACQqqHyoKAAoDAAMABwopIdEHAK8CAAAA.',
Ae='Aelis:BAAANQABCgEIAQAAAA==.',
Ag='Agni:BAACNQAFFIESAAMEAAcKShUaAgD2AAAFAAQKFRarHQBZAQAEAAMKOxQaAgD2AAA1AAQKgSAAAwUACQrwIhhCAPICAAUACQrwIhhCAPICAAQAAQpCGPA/ADUAAAAA.',
Ak='Akkadian:BAAANQADCggICwAAAA==.',
Al='Alnasham:BAACNQAFFIEJAAIGAAUKlw2OCwB/AQAGAAUKlw2OCwB/AQA1AAQKgSkAAgYACQqdIb4PAF0DAAYACQqdIb4PAF0DAAAA.Alnava:BAAANQAECgUJCQAAAA==.Alvoka:BAAANQAECgYJEQAAAA==.',
Am='Amarillos:BAAANQAECgYIBgAAAA==.Amarillys:BAABNQAECoEgAAIHAAkKpRrPNwBnAgAHAAkKpRrPNwBnAgAAAA==.Ammutseba:BAABNQAECoEWAAMIAAgKKhhmKwAcAgAIAAgKfhdmKwAcAgAJAAMK2hZfHQC0AAAAAA==.',
An='Anfall:BAABNQAECoEkAAIKAAkKUB05BwD+AgAKAAkKUB05BwD+AgAAAA==.Angermeier:BAABNQAECoEcAAILAAcKWRSfjwDOAQALAAcKWRSfjwDOAQAAAA==.Angrylady:BAAANQAECgEIAQAAAA==.Anjuna:BAAANQADCgUIBQAAAA==.Anohru:BAAANQAECggIAwAAAA==.Anthos:BAAANQAECgUIBQAAAA==.Antikreist:BAAANQADCgQJBAAAAA==.',
Ap='Aphotic:BAAANQAECgEIAQAAAA==.',
Ar='Ards:BAAANQADCgIIAwAAAA==.Armanite:BAAANQAECgQIBQABNQAECgkJFgABAEIYAA==.Arthaniis:BAAANQAECgYJEwAAAA==.',
As='Asystoli:BAAANQAECgUICwAAAA==.',
At='Atheria:BAAANQADCgYICAAAAA==.Attackheli:BAAANQAECgMIBgAAAA==.',
Au='Audideath:BAAANQAECgQIBwAAAA==.Auurdeath:BAAANQADCggIEwAAAA==.',
Av='Av:BAAANQADCgIIBQAAAA==.',
Aw='Aw:BAACNQAFFIEUAAIIAAYKJB9TAgBSAgAIAAYKJB9TAgBSAgA1AAQKgSIAAggACQryJfoDAKkDAAgACQryJfoDAKkDAAAA.',
Ax='Ax:BAECNQAFFIEKAAMBAAUKgBdJCgBFAQABAAQKGBtJCgBFAQAMAAEKIQngMQAkAAA1AAQKgSMAAgEACQqlH3QeALcCAAEACQqlH3QeALcCAAAA.',
Az='Azzazinzblo:BAAANQADCgUIBQAAAA==.',
['Aÿ']='Aÿa:BAAANQAECgQIBAAAAA==.',
Ba='Baast:BAAANQADCgUIBQAAAA==.Bamph:BAAANQAECgcIDAAAAA==.Bangbang:BAAANQAECgcIDwAAAA==.Batez:BAAANQAECgQIBAABNQAFFAUIBQANANQFAA==.',
Bd='Bdk:BAAANQAECggIEwAAAA==.Bdog:BAAANQAECgEIAwAAAA==.',
Be='Beeatinu:BAAANQADCgYICgAAAA==.Beledros:BAABNQAECoEcAAIOAAkKVBOGEwBhAgAOAAkKVBOGEwBhAgAAAA==.Beni:BAABNQAECoE5AAMPAAkKUiLIAwBWAwAPAAkKUiLIAwBWAwADAAUKKhQRGABCAQAAAA==.Benson:BAABNQAECoEhAAIQAAkKoB3RBgC7AgAQAAkKoB3RBgC7AgAAAA==.Bensonadin:BAAANQAECgYIBgAAAA==.Berd:BAAANQAECggIBgAAAA==.',
Bi='Bina:BAAANQAECgQIBQAAAA==.Birblock:BAACNQAFFIEgAAQRAAYKlCNUAQB6AgARAAYKlCNUAQB6AgASAAIKygGFEACBAAATAAEK/Bk+BgBiAAA1AAQKgSMABBEACQorJg0pAMgCABEABwowJg0pAMgCABIABwpLGIkSANYBABMAAQpHIHEkAEgAAAAA.',
Bo='Bobbo:BAAANQADCgYJBwAAAA==.',
Br='Brek:BAAANQAECgYICQAAAA==.Brewtherguy:BAABNQAECoEhAAIQAAgKux0mCACQAgAQAAgKux0mCACQAgAAAA==.Bruceshepard:BAAANQADCgQIBwABNQAECgIIAgAUAAAAAA==.Brutebuffalo:BAABNQAECoEkAAMVAAgKuh4PKQCdAgAVAAgKuh4PKQCdAgAGAAUKARMElABCAQAAAA==.Bruteflappy:BAAANQADCggICAABNQAECggIJAAVALoeAA==.Brutetestify:BAAANQADCggICAABNQAECggIJAAVALoeAA==.',
Bu='Bubbleboi:BAAANQADCgYICAAAAA==.Bubblebôy:BAAANQAECgIIAgAAAA==.Bublz:BAAANQAECgcIEQAAAA==.',
['Bâ']='Bâra:BAABNQAECoEaAAIBAAkKfRsqHwCyAgABAAkKfRsqHwCyAgAAAA==.',
Ca='Carnal:BAAANQADCgUIBQAAAA==.',
Ce='Cedren:BAACNQAFFIEIAAIIAAQKTws2DAAbAQAIAAQKTws2DAAbAQA1AAQKgSYAAwgACQrmG2gdAIkCAAgACQoFG2gdAIkCABYACAoBFrQkAAECAAAA.Ceewhya:BAAANQAECgEIAQAAAA==.Celestika:BAAANQABCgIIAgAAAA==.Cerari:BAAANQAECgEJAQAAAA==.',
Ch='Chalix:BAAANQADCgYICAAAAA==.Chama:BAABNQAECoEZAAIWAAgKNxEGJAAHAgAWAAgKNxEGJAAHAgAAAA==.Cheapheal:BAABNQAECoEtAAIPAAkKrR4xBQAjAwAPAAkKrR4xBQAjAwAAAA==.Cheapsnipe:BAAANQAECgIIAgABNQAECgkJLQAPAK0eAA==.Cheburashka:BAACNQAFFIEOAAIGAAUKEhtxBwDNAQAGAAUKEhtxBwDNAQA1AAQKgR8AAgYACQr4H6wgAOsCAAYACQr4H6wgAOsCAAAA.Chimerabob:BAAANQAECgMIBQAAAA==.Chunkymonkey:BAACNQAFFIEQAAIXAAYKqRZPBADHAQAXAAYKqRZPBADHAQA1AAQKgSkAAhcACQpbIhUJACsDABcACQpbIhUJACsDAAAA.',
Ci='Cidren:BAAANQAECgEIAQAAAA==.',
Cl='Clappncheeks:BAAANQAECgYICwAAAA==.Claudefrollo:BAAANQAECgUICgAAAA==.',
Cr='Crankyelf:BAAANQABCgEIAQAAAA==.Crimsa:BAABNQAECoEfAAITAAgKWASdDABsAQATAAgKWASdDABsAQAAAA==.Crimsonaxel:BAABNQAECoEcAAIGAAgK1RePPgBRAgAGAAgK1RePPgBRAgAAAA==.Cryogen:BAAANQAECgQJCAAAAA==.',
Cu='Cursewords:BAAANQADCgUIBQABNQAECgYIBgAUAAAAAA==.',
Da='Daemonproph:BAAANQADCgYIDAAAAA==.Dakini:BAABNQAECoEbAAIYAAcK+h7mMwB5AgAYAAcK+h7mMwB5AgAAAA==.Dam:BAAANQADCgUIBQABNQAECggIHwAMAAoaAA==.Dangerruss:BAAANQAECgUICQAAAA==.Darkspartan:BAAANQAECgUIBQAAAA==.Dashytash:BAABNQAECoEfAAIJAAgKEBtZBwBmAgAJAAgKEBtZBwBmAgAAAA==.Dawnsoul:BAAANQAECgYIDQAAAA==.Daxos:BAAANQADCgcICAAAAA==.',
De='Demb:BAAANQAECgQIBwAAAA==.Demonicchoas:BAABNQAECoEoAAMSAAkKiB6MCwAzAgARAAgK/RtcRwBfAgASAAcKzR2MCwAzAgAAAA==.Denagorn:BAABNQAECoEqAAIZAAkKfySaDACRAwAZAAkKfySaDACRAwABNQAFFAYIGAABAAkeAA==.Denhunt:BAAANQAECgUIBQABNQAFFAYIGAABAAkeAA==.Dentsama:BAAANQADCgEIAQAAAA==.Deplete:BAAANQADCgIJAgABNQAECgkJHQAaAKAVAA==.Deutzfr:BAABNQAECoEYAAIJAAkKlRxWBQCzAgAJAAkKlRxWBQCzAgAAAA==.Develop:BAAANQAECgMIBAAAAA==.Devos:BAABNQAECoEYAAMGAAcKnhW5YADPAQAGAAcKnhW5YADPAQAVAAQKRQ5LwAC9AAABNQAECgkJJwAGANIZAA==.',
Di='Dizzleman:BAAANQAECggIBgAAAA==.',
Do='Dominant:BAABNQAECoEeAAMFAAgKUR6bZAChAgAFAAgKUR6bZAChAgAEAAEKtwt6QgAxAAAAAA==.',
Dp='Dpssos:BAAANQAECgcIDQAAAA==.',
Dr='Drag:BAAANQADCgYICAAAAA==.Dreadmar:BAAANQADCgYICAAAAA==.Drock:BAABNQAECoEcAAIWAAcKqh5JGgBrAgAWAAcKqh5JGgBrAgAAAA==.Druidgale:BAAANQAECgIIAwAAAA==.Drybonez:BAAANQAECgQIBQAAAA==.Drygth:BAAANQADCgMIBgABNQAECgkJIgAbANEeAA==.Dräkarnoir:BAAANQADCggICAAAAA==.',
Dt='Dtb:BAACNQAFFIEJAAIMAAQKUxrdDQBEAQAMAAQKUxrdDQBEAQA1AAQKgSMAAgwACQqJIVoLAEoDAAwACQqJIVoLAEoDAAAA.',
Du='Dushimaya:BAABNQAECoEmAAIYAAkKXyPKBQCVAwAYAAkKXyPKBQCVAwAAAA==.',
Dv='Dvil:BAAANQAECgQIBQABNQAECgcIHAAWAKoeAA==.',
Dw='Dwyndi:BAAANQAECgYJBgAAAA==.',
Ei='Eisador:BAAANQAECgYIEQAAAA==.',
El='Elsen:BAAANQAECgQICQAAAA==.Elsha:BAABNQAECoEfAAIQAAkKlRqPBwCjAgAQAAkKlRqPBwCjAgAAAA==.',
Em='Emp:BAAANQAECgUIBgAAAA==.',
Er='Erilee:BAAANQAECgUICgAAAA==.',
Ev='Evelira:BAABNQAFFIEKAAIHAAUKbxhNCgC9AQAHAAUKbxhNCgC9AQAAAA==.',
Ey='Eyja:BAAANQADCgEIAgAAAA==.',
Ez='Ezailas:BAAANQAECgQIBQAAAA==.Ezpzndaheezy:BAAANQADCgYIBgABNQAECggIIAAcABQVAA==.',
Fa='Fatherangus:BAAANQAECggICAAAAA==.Fathercoast:BAAANQAECgYICwAAAA==.',
Fe='Fearful:BAACNQAFFIEFAAIYAAMKYAI/FgDGAAAYAAMKYAI/FgDGAAA1AAQKgSIAAhgACQr5FUw7AFoCABgACQr5FUw7AFoCAAAA.Felstrider:BAAANQADCgUIBQAAAA==.Ferador:BAACNQAFFIEOAAMdAAUKaBFQEgABAQAeAAUK+waQDABKAQAdAAMKwBhQEgABAQA1AAQKgSIAAx0ACQopH6A0AKsCAB0ACQopH6A0AKsCAB4ABgp6EtM3AGIBAAAA.',
Fi='Figgleslock:BAAANQADCgUIBQAAAA==.',
Fl='Flakester:BAABNQAECoEYAAIHAAYKTSELRAA2AgAHAAYKTSELRAA2AgAAAA==.Fleebly:BAABNQAECoEeAAIWAAkK0BeiFQCeAgAWAAkK0BeiFQCeAgAAAA==.',
Fn='Fndruid:BAAANQAECgIIAgAAAA==.',
Fo='Fourbees:BAABNQAECoEdAAIZAAkKiwoHkQDOAQAZAAkKiwoHkQDOAQAAAA==.',
Fu='Fursure:BAAANQAECgMIAwAAAA==.',
Ga='Garfal:BAAANQAECgIIAwAAAA==.Gather:BAAANQABCgQIBAABNQAECgkJKwAVALEVAA==.',
Gi='Gilgamesh:BAAANQAECgcIDAAAAA==.',
Go='Gorobob:BAAANQAECgIIBAAAAA==.',
Gr='Graygkl:BAAANQAECgUIDwAAAA==.Greshanwise:BAAANQAECgUIDQAAAA==.Grimreaper:BAABNQAECoElAAIfAAgKGBYpBwA0AgAfAAgKGBYpBwA0AgAAAA==.Groa:BAAANQABCgQIBgAAAA==.Groag:BAABNQAECoEiAAMbAAkK0R5YCgDCAgAbAAgKyx1YCgDCAgANAAgKjRoUIQBQAgAAAA==.',
Ha='Haarp:BAAANQAECgUICwAAAA==.Hakü:BAAANQAECgYIBwAAAA==.Hammered:BAAANQAECgYIBwAAAA==.Hardwire:BAAANQAECgEIAQAAAA==.',
He='Heartred:BAAANQADCgYIBgAAAA==.Heifer:BAABNQAECoEkAAIaAAkKTyH7FAAJAwAaAAkKTyH7FAAJAwABNQAFFAEJAQAUAAAAAA==.Hemophilia:BAABNQAECoEdAAIBAAgKGhKqRwDSAQABAAgKGhKqRwDSAQAAAA==.Heydk:BAABNQAECoEWAAMgAAgKcBrlSQBJAQAgAAUKYhrlSQBJAQABAAUKoBVhcgAmAQAAAA==.Heydruid:BAAANQAECgYICwABNQAECggIFgAgAHAaAA==.',
Ho='Hollowshädix:BAAANQAECgEIAQAAAA==.Holyanxiety:BAAANQADCgYIBgAAAA==.Holydave:BAAANQAECgMIBAAAAA==.Holymentos:BAAANQAECgYIEwABNQAECggIGwAhALgQAA==.Hottsauce:BAABNQAECoEYAAIKAAkK0hXZDACHAgAKAAkK0hXZDACHAgAAAA==.Hottsaucefel:BAAANQAECgYJBgAAAA==.',
Hu='Hundard:BAAANQADCgIIAgAAAA==.Huntersmarc:BAAANQAECgEIAgAAAA==.Hushhides:BAAANQAECggIEQAAAA==.',
Ia='Iamachick:BAAANQAECgEIAQAAAA==.',
Ib='Ibetrollinya:BAAANQAECgUIBwABNQAECgkJIQAiANIjAA==.Iblisshaytan:BAABNQAECoEsAAIIAAkKJxvMFgDFAgAIAAkKJxvMFgDFAgABNQAFFAQIBwAbAAYFAA==.Ibtrollin:BAAANQADCggIJQAAAA==.',
Ig='Ignacious:BAAANQAECgEIAQAAAA==.',
Il='Illumina:BAAANQAFFAEIAgAAAA==.',
Io='Ionissa:BAABNQAECoEgAAIdAAkK+BrAKgDNAgAdAAkK+BrAKgDNAgAAAA==.',
Is='Ischia:BAACNQAFFIEJAAMHAAQK5wi3FAAkAQAHAAQK5wi3FAAkAQAjAAEKbAEWFwA0AAA1AAQKgS4AAwcACQrlF8AzAHcCAAcACQrlF8AzAHcCACMAAgrfDY9dAGAAAAAA.',
Ja='Jallypally:BAAANQADCgIIAgAAAA==.Jarl:BAAANQADCgYICwAAAA==.',
Jc='Jch:BAACNQAFFIEXAAIdAAYKHBx8AgApAgAdAAYKHBx8AgApAgA1AAQKgSkAAx0ACQpfJb0MAGcDAB0ACQpfJb0MAGcDAB4AAQpkFsl0ADwAAAAA.',
Je='Jeay:BAAANQAECgEJAQAAAA==.Jedijeed:BAABNQAECoEoAAIXAAkKsiGVCAAzAwAXAAkKsiGVCAAzAwAAAA==.Jedikepjr:BAABNQAFFIEFAAIZAAMKCQjPFADSAAAZAAMKCQjPFADSAAABNQAECgkJKAAXALIhAA==.Jenova:BAAANQADCgUIBwAAAA==.Jepage:BAABNQAECoEeAAQEAAgKEyEMBQCkAgAEAAcKXSEMBQCkAgAkAAUKShqDAwCKAQAFAAMKWRqsWQHYAAAAAA==.Jess:BAAANQABCgIIAgAAAA==.',
Jo='Jolyne:BAAANQAECgQIBAAAAA==.',
Jp='Jprottsoo:BAABNQAECoEgAAIaAAgKfx/rHADHAgAaAAgKfx/rHADHAgAAAA==.',
Ju='Jubei:BAABNQAECoEcAAIiAAgK+Q2GDADNAQAiAAgK+Q2GDADNAQAAAA==.',
Ka='Kagayaki:BAAANQAECgIIAgAAAA==.Kalmya:BAABNQAECoElAAMCAAgKpQ0QKQClAQACAAgKpQ0QKQClAQADAAEKzgcOOQAvAAAAAA==.Kalrath:BAAANQAECgIIAgABNQAECgkJFgABAEIYAA==.Kasheek:BAAANQADCggICAAAAA==.',
Ke='Keizzer:BAAANQAECgcICwABNQAECggIHAAHANYcAA==.Keshisaru:BAAANQADCgQIBAAAAA==.',
Kh='Khazra:BAAANQAECgMIBgAAAA==.',
Ki='Kierràalexis:BAAANQADCgYIBgAAAA==.',
Kl='Klunder:BAABNQAECoEfAAIVAAgK1CHEGAD1AgAVAAgK1CHEGAD1AgAAAA==.',
Ko='Korris:BAABNQAECoEdAAMdAAkKQR1lJgDfAgAdAAkKQR1lJgDfAgAeAAEK1wJoiQAiAAAAAA==.Kostik:BAAANQADCgUIBQAAAA==.',
Kr='Kridillis:BAABNQAECoEdAAIIAAgKfxjSJABOAgAIAAgKfxjSJABOAgAAAA==.',
Ky='Kybinc:BAAANQADCgQIBAAAAA==.',
['Kí']='Kírã:BAAANQABCgIIBAAAAA==.',
La='Lawls:BAAANQADCgQIBwAAAA==.Lazybigger:BAAANQAECgIIAgAAAA==.Lazycow:BAABNQAECoEiAAIPAAkKVBRqEAAaAgAPAAkKVBRqEAAaAgAAAA==.Lazyfrost:BAABNQAECoEfAAIFAAkKABC7jwBEAgAFAAkKABC7jwBEAgAAAA==.',
Le='Lethò:BAABNQAECoEiAAMYAAgKLCNjEwAlAwAYAAgKLCNjEwAlAwAZAAQKvBNlCwHUAAAAAA==.Lethô:BAAANQAECgIIBAAAAA==.Lethö:BAAANQAECgIIBQAAAA==.',
Li='Liesx:BAABNQAFFIEFAAINAAUK1AVGBgCAAQANAAUK1AVGBgCAAQAAAA==.Lilzarthe:BAAANQAECgQIDAAAAA==.Lindsybowhan:BAAANQABCggIEAAAAA==.',
Lo='Loerasdh:BAABNQAECoEeAAIIAAgK9CXFBwBtAwAIAAgK9CXFBwBtAwAAAA==.Loko:BAACNQAFFIESAAIaAAYK9hXCBgDxAQAaAAYK9hXCBgDxAQA1AAQKgScAAhoACQq1ImUPADwDABoACQq1ImUPADwDAAAA.Looio:BAAANQADCgMIAgAAAA==.',
Lu='Lucien:BAAANQABCgQIBAAAAA==.Lumièrevide:BAAANQABCgMIAwAAAA==.Luxxus:BAABNQAECoEcAAIHAAgK1hwMMwB7AgAHAAgK1hwMMwB7AgAAAA==.',
Ly='Lyesx:BAABNQAECoEYAAMdAAkKkh+zEwA5AwAdAAkKkh+zEwA5AwAeAAIK1RCdYQB6AAABNQAFFAUIBQANANQFAA==.Lyndsy:BAAANQADCgUIBQAAAA==.Lyri:BAAANQADCgMIAwAAAA==.',
Ma='Macros:BAAANQAECgQICQAAAA==.Mageyousad:BAAANQADCgEIAgAAAA==.Maixia:BAAANQAECgIIBQAAAA==.Makhtor:BAAANQAECgMIBQAAAA==.Mallaer:BAABNQAECoEaAAIHAAkKnB+4EwAaAwAHAAkKnB+4EwAaAwAAAA==.Malícíous:BAABNQAECoEbAAIRAAgKOhOKZAAIAgARAAgKOhOKZAAIAgAAAA==.Mantakore:BAABNQAECoEjAAIOAAkKkRTUEwBdAgAOAAkKkRTUEwBdAgAAAA==.Marcdruid:BAAANQAECgQICAAAAA==.Maubles:BAAANQADCggICAABNQAFFAIIBQAhANULAA==.',
Mc='Mcdirk:BAAANQAECggICAAAAA==.',
Me='Menopaws:BAABNQAECoEjAAIPAAkKKiUnAQDPAwAPAAkKKiUnAQDPAwAAAA==.Merrtt:BAAANQAECgYIBgAAAA==.Mertrik:BAABNQAECoEdAAMVAAgK+yNyEwAWAwAVAAgK+yNyEwAWAwAGAAMKBBSx0gC9AAAAAA==.',
Mi='Midk:BAAANQAECgIIAwAAAA==.Mikayy:BAACNQAFFIEHAAIbAAMK/h1DCQAjAQAbAAMK/h1DCQAjAQA1AAQKgTIAAhsACQojJrgAANsDABsACQojJrgAANsDAAAA.Milenko:BAABNQAECoEfAAIIAAgKqx+2FQDPAgAIAAgKqx+2FQDPAgAAAA==.Milly:BAAANQAECgMIBwABNQAECggIHwAIAKsfAA==.',
Mo='Molfsongal:BAAANQADCgIIAgAAAA==.Monstrous:BAACNQAFFIEOAAILAAUK9A3cEAB8AQALAAUK9A3cEAB8AQA1AAQKgSsAAgsACQrZHw8rAP4CAAsACQrZHw8rAP4CAAAA.Moocher:BAAANQAECgEIAQAAAA==.Moonpie:BAAANQADCgUICQAAAA==.Mordecaii:BAAANQADCgYIDgAAAA==.Morgul:BAAANQAECgQIBgAAAA==.Morox:BAAANQABCgQIBAAAAA==.Mothman:BAAANQAECgQIBgAAAA==.Moyana:BAAANQADCgEIAQAAAA==.',
Ms='Msbehaven:BAABNQAECoEdAAIRAAcKwQYTqgBOAQARAAcKwQYTqgBOAQAAAA==.',
Mt='Mthafknfreez:BAAANQAECgYICwABNQAFFAQIBwAbAAYFAA==.',
Mu='Muffìns:BAAANQAECgQIBQAAAA==.Musashi:BAABNQAECoEZAAIHAAcKrRvFRAAzAgAHAAcKrRvFRAAzAgAAAA==.',
My='Mynuturchin:BAAANQAECgcIEwAAAA==.',
Na='Nagy:BAAANQAECgIIAgAAAA==.',
Ni='Night:BAABNQAECoEbAAIFAAcKsBRItgD0AQAFAAcKsBRItgD0AQAAAA==.Nightsecho:BAAANQAECgEIAQAAAA==.Nightshris:BAAANQAECgIIAgAAAA==.',
No='Notmehssos:BAAANQAECgcICwAAAA==.Notthechosen:BAAANQAECgQIBwABNQAECgYIEgAUAAAAAA==.',
Ny='Nymeriã:BAAANQAECgIIAwAAAA==.',
Ob='Obzy:BAAANQAECgcIEwAAAA==.Obzz:BAAANQADCgEIAQABNQAECgcIEwAUAAAAAA==.',
Ok='Okamy:BAAANQAECgcIDAABNQAECgQIBQAUAAAAAA==.',
Ol='Olympicjeid:BAAANQAECgYIEQABNQAECgkJKAAXALIhAA==.',
Op='Opz:BAABNQAECoEoAAMjAAkK0xm8FQCOAgAjAAkK0xm8FQCOAgAlAAIKiBYVGQCJAAAAAA==.',
Pa='Paladinfive:BAAANQAECgEIAgAAAA==.Parthos:BAAANQAECgQICgAAAA==.',
Pe='Pedro:BAAANQAECgEIAQAAAA==.Perry:BAAANQADCgIIAgAAAA==.',
Ph='Phenomenon:BAAANQAECgQIBQABNQAECgYIBwAUAAAAAA==.',
Pi='Pittydafoo:BAAANQAECgIIAgAAAA==.',
Pk='Pkunkk:BAAANQAECgcJCwAAAA==.',
Pl='Ploxis:BAACNQAFFIELAAIJAAUKsRU+AQBtAQAJAAUKsRU+AQBtAQA1AAQKgRgAAgkACQoZGR0GAJQCAAkACQoZGR0GAJQCAAAA.',
Po='Polskashaman:BAAANQAECgYIEwAAAA==.Pookiebonez:BAAANQADCgIIAgABNQAECgQIBQAUAAAAAA==.',
Pr='Prea:BAAANQAFFAIIAgAAAA==.Premiumferal:BAABNQAECoEbAAMNAAkK8iD+FQCnAgANAAkK8iD+FQCnAgAbAAUKFBlNLABDAQAAAA==.Primecarry:BAACNQAFFIENAAIYAAUKoxntBwC8AQAYAAUKoxntBwC8AQA1AAQKgSIAAhgACQp1I0QJAHEDABgACQp1I0QJAHEDAAAA.Prine:BAABNQAECoEcAAILAAkKix7vIQAiAwALAAkKix7vIQAiAwABNQAFFAUIDQAYAKMZAA==.',
Pu='Puripuri:BAAANQAECgQIBAAAAA==.',
Qi='Qinkipa:BAAANQAECgEIAQAAAA==.',
Qo='Qovo:BAAANQABCggIDgAAAA==.',
Ra='Ragark:BAAANQADCgUIBQAAAA==.Raigko:BAABNQAECoEoAAILAAkKeCNYDACPAwALAAkKeCNYDACPAwAAAA==.Rainyday:BAABNQAECoEUAAIVAAYK9AqLowAAAQAVAAYK9AqLowAAAQAAAA==.Raiva:BAAANQAECgQICAABNQAECgYIBwAUAAAAAA==.Raivek:BAAANQAECgIIAgAAAA==.Randenton:BAAANQADCgYICAAAAA==.Randezoth:BAAANQABCggIDQABNQADCgYICAAUAAAAAA==.Rassputen:BAABNQAECoEoAAIMAAkKMRL4PgDkAQAMAAkKMRL4PgDkAQAAAA==.',
Re='Reck:BAAANQADCgEIAQAAAA==.Redjive:BAAANQAECggIAQAAAA==.Redonkulos:BAAANQADCgMIBAAAAA==.Reliri:BAAANQADCgYIBgAAAA==.Relis:BAAANQABCgYICAAAAA==.Renais:BAAANQAECgMIAwAAAA==.Rex:BAABNQAECoEfAAIMAAgKChrgLgA7AgAMAAgKChrgLgA7AgAAAA==.',
Ri='Rileyesco:BAAANQABCgUIBgAAAA==.Ripskylark:BAAANQAECgIIAwAAAA==.Risk:BAAANQABCgcIEgAAAA==.',
Ro='Roguen:BAACNQAFFIEHAAIbAAQKBgWgCQAVAQAbAAQKBgWgCQAVAQA1AAQKgSsAAxsACQqZF1kLALACABsACQqZF1kLALACAA0AAwqGCLhsAKwAAAAA.Romirin:BAAANQADCgQIBAAAAA==.Rotan:BAAANQADCgYICwAAAA==.Roulduke:BAABNQAECoEcAAIGAAcKjAzjdgCNAQAGAAcKjAzjdgCNAQAAAA==.',
['Rù']='Rùckús:BAABNQAECoEpAAIBAAgK4h6OJgCCAgABAAgK4h6OJgCCAgAAAA==.',
Sa='Sacredmentos:BAABNQAECoEbAAIhAAgKuBAMJACTAQAhAAgKuBAMJACTAQAAAA==.Salaen:BAAANQAECggIAQAAAA==.Sammybeans:BAAANQAECgIIAgAAAA==.Sapito:BAAANQADCgYICgAAAA==.',
Sc='Scarecrow:BAAANQADCgMIAwABNQAECggIHwAIAKsfAA==.',
Se='Seceron:BAAANQAECgUIDAAAAA==.Sekai:BAAANQAECgIIAgAAAA==.',
Sg='Sgtslappy:BAAANQADCgMIAwAAAA==.',
Sh='Shamminator:BAAANQADCgIIAgAAAA==.Shanarelle:BAAANQAECgYIEwAAAA==.Shasa:BAABNQAECoEaAAIdAAkKih1kKQDTAgAdAAkKih1kKQDTAgAAAA==.Shatteredsky:BAABNQAECoEfAAMVAAkKAR1kIwC6AgAVAAkKAR1kIwC6AgAGAAEKqgP0IgEsAAAAAA==.Shazik:BAABNQAECoErAAIVAAkKsRWMSAAUAgAVAAkKsRWMSAAUAgAAAA==.Shazzik:BAAANQAECgYICgABNQAECgkJKwAVALEVAA==.Sheroko:BAAANQAECgIIAwAAAA==.Shilbalam:BAAANQADCgQIBAAAAA==.Shmoopy:BAAANQAECgEIAQAAAA==.Shmoove:BAAANQADCgEIAQAAAA==.Shnkz:BAAANQAECgEIAQAAAA==.Shotzer:BAAANQADCgMIBgAAAA==.',
Si='Silzo:BAAANQAECgYIBwAAAA==.Sirjames:BAAANQADCggIDgAAAA==.',
Sk='Skelix:BAACNQAFFIEbAAIVAAYKZyJKAgBpAgAVAAYKZyJKAgBpAgA1AAQKgS4AAxUACQpLJlIDAKYDABUACQpLJlIDAKYDAAYAAwpVF1y9AOkAAAAA.Skunkpaw:BAAANQADCgUICwAAAA==.Skysong:BAACNQAFFIEKAAMcAAQK+x18BAByAQAcAAQK+x18BAByAQAOAAEKeAVFFgBBAAA1AAQKgSEAAxwACQoWIPAHAOgCABwACQoWIPAHAOgCAA4AAwp/BWc8AJYAAAAA.',
Sl='Slashedeye:BAABNQAECoEsAAIkAAcKjBLPAgDWAQAkAAcKjBLPAgDWAQAAAA==.Slimgucci:BAAANQADCggICAAAAA==.',
Sn='Snowynn:BAABNQAECoEVAAIPAAgKnhTvFADRAQAPAAgKnhTvFADRAQAAAA==.Snubby:BAABNQAECoEbAAMRAAgKuiSxRABnAgARAAYKfSSxRABnAgASAAIKcyX9NgDbAAAAAA==.',
So='Solheim:BAAANQABCgUIBQAAAA==.Sonari:BAAANQADCgYIBgAAAA==.',
Sp='Spankz:BAAANQAECgQICAAAAA==.Spathi:BAAANQAECgYIBgAAAA==.Spicymeatbal:BAAANQABCggIDwAAAA==.',
St='Stepz:BAAANQABCggIDAAAAA==.Strathz:BAABNQAECoEhAAMRAAgK0h8YNQCbAgARAAgK8RwYNQCbAgASAAQKVxtDJgA4AQAAAA==.Strongish:BAAANQADCgUIBQAAAA==.',
Su='Summerset:BAAANQAECgIIAQAAAA==.Sunstrider:BAAANQADCgMIBAAAAA==.Superdonkey:BAAANQADCgYICwABNQAFFAYIEAAXAKkWAA==.Sushi:BAAANQADCgIIAgAAAA==.Suva:BAAANQADCgYIBgAAAA==.',
Sy='Sylatis:BAAANQAECgYIDAABNQAFFAYIIAARAJQjAA==.Sylätis:BAAANQAECgMJAwABNQAFFAYIIAARAJQjAA==.',
['Sö']='Söultender:BAAANQADCgMIAwABNQAECgYIDQAUAAAAAA==.',
['Sø']='Sølidus:BAAANQAECgMIBwABNQAFFAUICgAHAG8YAA==.',
Ta='Taintedhealz:BAAANQADCgEIAQAAAA==.Talys:BAACNQAFFIEXAAIOAAYKpRkUBQD1AQAOAAYKpRkUBQD1AQA1AAQKgTEAAg4ACQqMI1QBALgDAA4ACQqMI1QBALgDAAAA.Tankly:BAAANQADCgMIAwAAAA==.',
Te='Tehchosen:BAAANQADCggICAAAAA==.Terramor:BAAANQADCgQIBAAAAA==.Texicola:BAABNQAECoEqAAIEAAgK8yAwAwD6AgAEAAgK8yAwAwD6AgAAAA==.',
Th='Thabdeady:BAAANQAECgMIAwABNQAECggIIAAcABQVAA==.Thabk:BAABNQAECoEgAAMcAAgKFBWnFgC/AQAcAAcK+xKnFgC/AQAOAAYKCQslKQBEAQAAAA==.Thaelorn:BAAANQADCgEIAQAAAA==.Thesyra:BAAANQAECgYIDgAAAA==.Thurmond:BAABNQAECoEWAAMBAAkKQhggOgAWAgABAAkKIhQgOgAWAgAMAAYKchivTgCaAQAAAA==.Thurmoons:BAAANQAECgUIBgABNQAECgkJFgABAEIYAA==.Thurmund:BAAANQADCgYIBgABNQAECgkJFgABAEIYAA==.',
Ti='Tidalanxiety:BAAANQAECgQIBQAAAA==.',
To='Toastay:BAAANQAECgMIBQAAAA==.Toastz:BAABNQAECoEpAAIdAAgKhCIOGgAYAwAdAAgKhCIOGgAYAwAAAA==.Toebeanz:BAAANQAECgQIDAAAAA==.Tokken:BAACNQAFFIETAAILAAYKcxQaCQDyAQALAAYKcxQaCQDyAQA1AAQKgSkAAgsACQrVH+syAOACAAsACQrVH+syAOACAAAA.',
Tr='Treebeast:BAAANQAFFAIIBAAAAA==.Troile:BAAANQADCgYIDwAAAA==.Trojen:BAABNQAECoEaAAMZAAkKghZlcwAZAgAZAAgKABZlcwAZAgAYAAgKGAtAawCvAQAAAA==.Trolladin:BAAANQADCgYICgABNQADCggIJQAUAAAAAA==.',
Tw='Twig:BAABNQAECoEdAAIaAAgKLhh8LwA/AgAaAAgKLhh8LwA/AgAAAA==.',
Ty='Tyras:BAAANQAECgQICgAAAA==.',
['Tâ']='Tâz:BAABNQAECoEkAAIVAAgKTCFcIQDEAgAVAAgKTCFcIQDEAgAAAA==.',
Ul='Ulanda:BAABNQAECoEnAAMPAAcKUBieEgD2AQAPAAcKUBieEgD2AQADAAYK0gibGgAgAQAAAA==.',
Um='Umasi:BAACNQAFFIEYAAIhAAYKayaZAACcAgAhAAYKayaZAACcAgA1AAQKgSkAAiEACQpUJl4BAMYDACEACQpUJl4BAMYDAAAA.',
Un='Underbogg:BAAANQADCgUIBQAAAA==.',
Ut='Utastebad:BAAANQADCggIDAAAAA==.',
Va='Vagabundo:BAAANQAECgMIAwABNQAECgYICwAUAAAAAA==.Vail:BAAANQADCgUIBgAAAA==.Valamaldoran:BAAANQADCgUIBQAAAA==.Vanthil:BAAANQAECgIIAgAAAA==.Vaporize:BAAANQAECgIIAgAAAA==.',
Ve='Venandi:BAAANQAECgcIEQAAAA==.Vengened:BAAANQAECgYIEgAAAA==.Verax:BAAANQAECgIIAgAAAA==.Verestrasz:BAAANQADCgIIBAAAAA==.',
Vg='Vgly:BAAANQAECgQIEAAAAA==.',
Vi='Vilous:BAABNQAECoEhAAIiAAkK0iNxAQB2AwAiAAkK0iNxAQB2AwAAAA==.',
Vy='Vyisesham:BAABNQAECoEeAAMGAAcKPhyEQgBAAgAGAAcKPhyEQgBAAgAVAAQKhR0/kwAqAQAAAA==.',
['Vý']='Výce:BAAANQAECgEIAQAAAA==.',
Wa='Wagtar:BAAANQADCgYICwABNQADCgQIBAAUAAAAAA==.Warzug:BAAANQADCgQIBAAAAA==.',
We='Wesjin:BAABNQAECoEZAAMmAAgKexJDFwDZAQAmAAgKexJDFwDZAQAXAAEKHQO7ZwAjAAAAAA==.Wez:BAAANQAECgUIBgAAAA==.',
Wh='Whiskee:BAABNQAECoEdAAMDAAkKySKEBAAgAwADAAgKliGEBAAgAwAPAAcK1SDlDABZAgAAAA==.',
Wo='Wooglone:BAAANQAECgQJBAAAAA==.',
Wy='Wyndia:BAAANQAFFAIIAgAAAA==.Wyndibear:BAAANQABCgEIAQAAAA==.',
Xa='Xanthos:BAAANQAECgEIAQABNQAECgQIBgAUAAAAAA==.',
Xb='Xbert:BAAANQADCgcIBwAAAA==.',
Xe='Xela:BAAANQABCgYICgABNQAECggIHgAFAFEeAA==.Xenophontes:BAAANQAECgcIEwABNQAFFAUICgAHAG8YAA==.',
Xi='Xihuang:BAABNQAECoEjAAIaAAgKTxwYIwCYAgAaAAgKTxwYIwCYAgABNQAFFAQIBwAbAAYFAA==.Xiia:BAAANQADCggICwAAAA==.',
Xo='Xouu:BAAANQAECggIAQABNQAFFAgIBgAVADoRAA==.',
Xx='Xxuusham:BAABNQAFFIEGAAIVAAYKOhEQBQD8AQAVAAYKOhEQBQD8AQAAAA==.Xxuuspr:BAAANQAECggIAgABNQAFFAgIBgAVADoRAA==.Xxuutwo:BAAANQAECggIAQABNQAFFAgIBgAVADoRAA==.',
Ya='Yaoguai:BAABNQAECoEdAAMaAAkKoBWtKQBmAgAaAAkKoBWtKQBmAgAPAAEKHwmjTQA0AAAAAA==.Yasei:BAAANQAECgQIBAAAAA==.Yawgmoth:BAAANQAECgQIBQABNQAECgkJHwAQAJUaAA==.',
Za='Zaleris:BAAANQAECgQIBQAAAA==.Zaryana:BAAANQAECgYIBgAAAA==.',
Ze='Zephon:BAAANQAECgYIEwAAAA==.',
Zo='Zotiel:BAAANQADCgcIDwABNQAFFAYIGAABAAkeAA==.',
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
