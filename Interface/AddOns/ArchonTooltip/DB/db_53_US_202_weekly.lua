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

local lookup = {'DeathKnight-Unholy','Druid-Restoration','Mage-Frost','Mage-Arcane','Shaman-Elemental','Shaman-Enhancement','Unknown-Unknown','DemonHunter-Havoc','DeathKnight-Frost','Druid-Guardian','Druid-Feral','Monk-Brewmaster','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','DemonHunter-Devourer','Monk-Windwalker','Paladin-Retribution','DemonHunter-Vengeance','Paladin-Holy','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Restoration','Druid-Balance','Priest-Holy','Priest-Shadow','Rogue-Subtlety','Warrior-Arms','Rogue-Assassination','DeathKnight-Blood','Evoker-Devastation','Evoker-Preservation','Mage-Fire','Paladin-Protection',}
local provider = {region='US',realm='Spirestone',name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Abduon:BAAANQADCgcICwAAAA==.',
Ac='Aciddeath:BAAANQADCggICAABNQAECgkJHAABAM8gAA==.',
Ad='Admaris:BAABNQAECoEaAAICAAkJqh8SAwBMAwACAAkJqh8SAwBMAwAAAA==.',
Ag='Agni:BAACNQAFFIEJAAMDAAUJ3xH/AACyAAAEAAMJTA16DwD5AAADAAIJuxj/AACyAAA1AAQKgRkAAwQACQlDIgkcACgDAAQACQlDIgkcACgDAAMAAQlCGA8lAD4AAAAA.',
Al='Alnasham:BAABNQAECoEcAAIFAAkJ/B0uDgAcAwAFAAkJ/B0uDgAcAwAAAA==.Alnava:BAAANQAECgQIBAAAAA==.Alvoka:BAAANQAECgYIDAAAAA==.',
Am='Amarillos:BAAANQAECgYIBgAAAA==.Amarillys:BAAANQAECggIEgAAAA==.Ammutseba:BAAANQAECgUIDgAAAA==.',
An='Anfall:BAABNQAECoEZAAIGAAgJShgaBwCPAgAGAAgJShgaBwCPAgAAAA==.Angermeier:BAAANQAECgYICwAAAA==.Angrylady:BAAANQAECgEIAQAAAA==.Anjuna:BAAANQADCgUIBQAAAA==.Anohru:BAAANQAECgMIAwAAAA==.Anthos:BAAANQAECgMIAwAAAA==.Antikreist:BAAANQADCgIIAgAAAA==.',
Ap='Aphotic:BAAANQABCgYIBgAAAA==.',
Ar='Armanite:BAAANQADCgEIAQABNQAECggICAAHAAAAAA==.Arthaniis:BAAANQAECgYIEwAAAA==.',
Au='Audideath:BAAANQADCggIGQAAAA==.Auurdeath:BAAANQADCggIEwAAAA==.',
Aw='Aw:BAABNQAECoEcAAIIAAkJ7CWwAADpAwAIAAkJ7CWwAADpAwAAAA==.',
Ax='Ax:BAEBNQAECoEaAAIBAAkJsBwSDgDyAgABAAkJsBwSDgDyAgAAAA==.',
Az='Azzazinzblo:BAAANQADCgUIBQAAAA==.',
['Aÿ']='Aÿa:BAAANQAECgQIBAAAAA==.',
Ba='Bamph:BAAANQAECgQIBQAAAA==.Bangbang:BAAANQAECgQIBAAAAA==.Batez:BAAANQAECgQIBAABNQAECgkJHQAJAF4hAA==.',
Bd='Bdk:BAAANQAECgIIAQAAAA==.Bdog:BAAANQAECgEIAwAAAA==.',
Be='Beeatinu:BAAANQADCgQIAwAAAA==.Beledros:BAAANQAFFAIIAgAAAA==.Beni:BAABNQAECoEkAAMKAAkJuh6UAgAAAwAKAAkJuh6UAgAAAwALAAMJhwiKFACYAAAAAA==.Benson:BAABNQAECoEhAAIMAAkJoB3RAgAMAwAMAAkJoB3RAgAMAwAAAA==.Bensonadin:BAAANQAECgYIBgAAAA==.Berd:BAAANQAECggIBgAAAA==.',
Bi='Bina:BAAANQAECgQIBQAAAA==.Birblock:BAACNQAFFIEPAAMNAAYJ8xndAADwAQANAAUJ0h7dAADwAQAOAAIJygG8BwCRAAA1AAQKgRgABA0ACQmKJbcXAKcCAA0ABwlhJbcXAKcCAA4ABwlLGEQMAAgCAA8AAQlHIIUWAE0AAAAA.',
Bo='Bobbo:BAAANQADCgYIBwAAAA==.',
Br='Brek:BAAANQAECgQIBAAAAA==.Brewtherguy:BAAANQAECgYIDAAAAA==.Bruceshepard:BAAANQADCgQIBwABNQAECgIIAgAHAAAAAA==.Brutebuffalo:BAAANQAECgYIDAAAAA==.',
Bu='Bubbleboi:BAAANQADCgYICAAAAA==.Bubblebôy:BAAANQAECgIIAgAAAA==.Bublz:BAAANQAECgUIBgAAAA==.',
['Bâ']='Bâra:BAAANQAECgYICgAAAA==.',
Ca='Carnal:BAAANQADCgUIBQAAAA==.',
Ce='Cedren:BAABNQAECoEcAAMIAAkJTBg2DADJAgAIAAkJ3BY2DADJAgAQAAgJARYjFgBDAgAAAA==.Ceewhya:BAAANQADCgQIBAAAAA==.Celestika:BAAANQABCgIIAgAAAA==.Cerari:BAAANQAECgEIAQAAAA==.',
Ch='Chalix:BAAANQADCgYICAAAAA==.Chama:BAAANQAECgYICwAAAA==.Cheapheal:BAAANQAECgcIEQAAAA==.Cheburashka:BAABNQAECoEYAAIFAAkJxh6WEQD2AgAFAAkJxh6WEQD2AgAAAA==.Chimerabob:BAAANQAECgEIAQAAAA==.Chunkymonkey:BAABNQAECoEgAAIRAAkJayDFBQAeAwARAAkJayDFBQAeAwAAAA==.',
Ci='Cidren:BAAANQADCgcIBwAAAA==.',
Cl='Clappncheeks:BAAANQAECgQIBQAAAA==.Claudefrollo:BAAANQADCgYIDwAAAA==.',
Cr='Crankyelf:BAAANQABCgEIAQAAAA==.Crimsa:BAAANQAECgQICAAAAA==.Crimsonaxel:BAAANQAECgMIBQAAAA==.Cryogen:BAAANQAECgQICAAAAA==.',
Cu='Cursewords:BAAANQADCgUIBQABNQAECgYIBgAHAAAAAA==.',
Da='Daemonproph:BAAANQADCgYIDAAAAA==.Dakini:BAAANQAECgQIBgAAAA==.Dam:BAAANQADCgUIBQAAAA==.Dangerruss:BAAANQAECgIIBAAAAA==.Dashytash:BAAANQAECgUICQAAAA==.Dawnsoul:BAAANQAECgUIBwAAAA==.Daxos:BAAANQADCgcICAAAAA==.',
De='Demb:BAAANQAECgQIBwAAAA==.Demonicchoas:BAABNQAECoEbAAMOAAkJKRwJCABYAgANAAgJSxmbHwByAgAOAAcJzR0JCABYAgAAAA==.Denagorn:BAABNQAECoEYAAISAAkJLiMKCAB5AwASAAkJLiMKCAB5AwABNQAFFAUICgABAEsNAA==.Densama:BAAANQADCgEIAQABNQAFFAUICgABAEsNAA==.Deutzfr:BAABNQAECoEYAAITAAkJlRyzAQDsAgATAAkJlRyzAQDsAgAAAA==.Devos:BAAANQAECgYICwAAAA==.',
Do='Dominant:BAAANQAECgYIDAAAAA==.',
Dp='Dpssos:BAAANQAECgQIBAAAAA==.',
Dr='Drag:BAAANQADCgYICAAAAA==.Dreadmar:BAAANQADCgYICAAAAA==.Drock:BAAANQAECgQIBgAAAA==.Druidgale:BAAANQAECgIIAwAAAA==.Drybonez:BAAANQAECgIIAwAAAA==.Dräkarnoir:BAAANQADCggICAAAAA==.',
Dt='Dtb:BAAANQAECggIEwAAAA==.',
Du='Dushimaya:BAABNQAECoEYAAIUAAkJ0R1CCwAXAwAUAAkJ0R1CCwAXAwAAAA==.',
Dv='Dvil:BAAANQAECgQIBQABNQAECgQIBgAHAAAAAA==.',
Dw='Dwyndi:BAAANQAECgYIBgAAAA==.',
Ei='Eisador:BAAANQAECgUIBQAAAA==.',
El='Elsen:BAAANQAECgQIBgAAAA==.Elsha:BAAANQAECgYIDgAAAA==.',
Em='Emp:BAAANQAECgUIBgAAAA==.',
Er='Erilee:BAAANQADCgIIAgAAAA==.',
Ev='Evelira:BAAANQAFFAIIAgAAAA==.',
Ey='Eyja:BAAANQADCgEIAQAAAA==.',
Ez='Ezpzndaheezy:BAAANQADCgYIBgABNQAECgYICwAHAAAAAA==.',
Fa='Fathercoast:BAAANQAECgYICwAAAA==.',
Fe='Fearful:BAACNQAFFIEFAAIUAAMJYALfBwDVAAAUAAMJYALfBwDVAAA1AAQKgSIAAhQACQn5FfQaAIkCABQACQn5FfQaAIkCAAAA.Felstrider:BAAANQADCgUIBQAAAA==.Ferador:BAABNQAECoEZAAMVAAkJ8hvjHgCQAgAVAAgJYB3jHgCQAgAWAAQJSg+rLwDjAAAAAA==.',
Fi='Figgleslock:BAAANQADCgUIBQAAAA==.',
Fl='Flakester:BAAANQAECgQIBwAAAA==.Fleebly:BAAANQAECgYIDgAAAA==.',
Fo='Fourbees:BAAANQAECgYICgAAAA==.',
Fu='Fursure:BAAANQAECgMIAwAAAA==.',
Ga='Garfal:BAAANQAECgIIAwAAAA==.Gather:BAAANQABCgQIBAABNQAECggIHgAXAAMXAA==.',
Gi='Gilgamesh:BAAANQAECgQIBQAAAA==.',
Go='Gorobob:BAAANQAECgEIAQAAAA==.',
Gr='Graygkl:BAAANQAECgUIBQAAAA==.Greshanwise:BAAANQADCgYIEQAAAA==.Grimreaper:BAAANQAECgUIDAAAAA==.Groa:BAAANQABCgQIBgAAAA==.Groag:BAAANQAECgYIDgAAAA==.',
Ha='Haarp:BAAANQAECgIIAgAAAA==.Hakü:BAAANQADCgYICgAAAA==.Hammered:BAAANQAECgIIAgAAAA==.Hardwire:BAAANQAECgEIAQAAAA==.',
He='Heifer:BAABNQAECoEeAAIYAAkJGiDJCgAzAwAYAAkJGiDJCgAzAwABNQAFFAEIAQAHAAAAAA==.Hemophilia:BAAANQAECgQICAAAAA==.Heydk:BAAANQAECgUICgAAAA==.Heydruid:BAAANQADCgcICAABNQAECgUICgAHAAAAAA==.',
Ho='Hollowshädix:BAAANQAECgEIAQAAAA==.Holyanxiety:BAAANQADCgYIBgAAAA==.Holydave:BAAANQAECgEIAQAAAA==.Holymentos:BAAANQAECgMIBAABNQAECgYICwAHAAAAAA==.Hottsauce:BAAANQAECggIEQAAAA==.Hottsaucefel:BAAANQAECgYIBgAAAA==.',
Hu='Hundard:BAAANQADCgIIAgAAAA==.Huntersmarc:BAAANQADCgYIBgAAAA==.',
Ia='Iamachick:BAAANQAECgEIAQAAAA==.',
Ib='Ibetrollinya:BAAANQAECgEIAQABNQAECgYICAAHAAAAAA==.Iblisshaytan:BAAANQAECgcIEgABNQAFFAIIAgAHAAAAAA==.Ibtrollin:BAAANQADCgYIHQAAAA==.',
Ig='Ignacious:BAAANQAECgEIAQAAAA==.',
Io='Ionissa:BAAANQAECgQIBgAAAA==.',
Is='Ischia:BAABNQAECoEeAAMZAAkJxBfxFgCNAgAZAAkJxBfxFgCNAgAaAAEJ6gejTAAqAAAAAA==.',
Ja='Jarl:BAAANQADCgYICQAAAA==.',
Jc='Jch:BAABNQAECoEgAAMVAAkJuSSIAwCbAwAVAAkJuSSIAwCbAwAWAAEJZBasRQBGAAAAAA==.',
Je='Jeay:BAAANQADCgIIAgAAAA==.Jedijeed:BAABNQAECoEXAAIRAAkJmh6VBwDwAgARAAkJmh6VBwDwAgAAAA==.Jedikepjr:BAAANQADCgYIBgABNQAECgkJFwARAJoeAA==.Jenova:BAAANQADCgUIBwAAAA==.Jepage:BAAANQAECgQIBwAAAA==.',
Jo='Jolyne:BAAANQADCggIEgAAAA==.',
Jp='Jprottsoo:BAAANQAECgYIDgAAAA==.',
Ju='Jubei:BAAANQAECgUIBgAAAA==.',
Ka='Kalmya:BAAANQAECgYIDAAAAA==.Kalrath:BAAANQAECgIIAgABNQAECggICAAHAAAAAA==.',
Ke='Keizzer:BAAANQAECgQIBgABNQAECgYICwAHAAAAAA==.Keshisaru:BAAANQADCgQIBAAAAA==.',
Kh='Khazra:BAAANQAECgMIBAAAAA==.',
Ki='Kierràalexis:BAAANQADCgYIBgAAAA==.',
Kl='Klunder:BAAANQAECgUIBwAAAA==.',
Ko='Korris:BAAANQAECgYIDwAAAA==.Kostik:BAAANQADCgUIBQAAAA==.',
Kr='Kridillis:BAAANQAECgUIDAAAAA==.',
Ky='Kybinc:BAAANQADCgMIAwAAAA==.',
['Kí']='Kírã:BAAANQABCgIIBAAAAA==.',
La='Lawls:BAAANQADCgQIBwAAAA==.Lazybigger:BAAANQAECgIIAgAAAA==.Lazycow:BAABNQAECoEYAAIKAAkJmxPCBQBPAgAKAAkJmxPCBQBPAgAAAA==.Lazyfrost:BAAANQAECgYIDgAAAA==.',
Le='Lethò:BAAANQAECgUIDQAAAA==.Lethô:BAAANQADCggICAAAAA==.Lethö:BAAANQAECgIIBQAAAA==.',
Li='Lilzarthe:BAAANQAECgQICAAAAA==.',
Lo='Loerasdh:BAAANQAECgYIEAAAAA==.Loko:BAACNQAFFIEGAAIYAAQJ5hX4BABhAQAYAAQJ5hX4BABhAQA1AAQKgRsAAhgACQmNHDAQAOwCABgACQmNHDAQAOwCAAAA.Looio:BAAANQADCgMIAgAAAA==.',
Lu='Lucien:BAAANQABCgQIBAAAAA==.Luxxus:BAAANQAECgYICwAAAA==.',
Ly='Lyesx:BAAANQAECgYIBgABNQAECgkJHQAJAF4hAA==.Lyndsy:BAAANQADCgUIBQAAAA==.Lyri:BAAANQADCgMIAwAAAA==.',
Ma='Macros:BAAANQAECgEIAgAAAA==.Mageyousad:BAAANQADCgEIAQAAAA==.Makhtor:BAAANQAECgMIBQAAAA==.Mallaer:BAAANQAECgYIDwAAAA==.Malícíous:BAAANQAECgYICgAAAA==.Mantakore:BAAANQAECgcIEAAAAA==.Marcdruid:BAAANQAECgQIBwAAAA==.Maubles:BAAANQADCggICAABNQAECgcIEwAHAAAAAA==.',
Me='Menopaws:BAAANQAECgYIDgAAAA==.Merrtt:BAAANQAECgYIBgAAAA==.Mertrik:BAAANQAECgYIDAAAAA==.',
Mi='Midk:BAAANQAECgIIAwAAAA==.Mikayy:BAABNQAECoEfAAIbAAkJeiW5AADPAwAbAAkJeiW5AADPAwAAAA==.Milenko:BAAANQAECgQICAAAAA==.Milly:BAAANQAECgMIAwABNQAECgQICAAHAAAAAA==.',
Mo='Molfsongal:BAAANQADCgIIAgAAAA==.Monstrous:BAABNQAECoEeAAIcAAkJ3hrOHQDkAgAcAAkJ3hrOHQDkAgAAAA==.Moocher:BAAANQAECgEIAQAAAA==.Moonpie:BAAANQADCgUICQAAAA==.Mordecaii:BAAANQADCgYIDgAAAA==.Morgul:BAAANQAECgMIBAAAAA==.Mothman:BAAANQAECgEIAQAAAA==.',
Ms='Msbehaven:BAAANQAECgQICAAAAA==.',
Mu='Muffìns:BAAANQAECgEIAQAAAA==.Musashi:BAAANQAECgQIBAAAAA==.',
My='Mynuturchin:BAAANQAECgUIBgAAAA==.',
Na='Nagy:BAAANQADCgcIDAAAAA==.',
Ni='Night:BAAANQAECgQIBQAAAA==.Nightsecho:BAAANQABCgYIBgAAAA==.Nightshris:BAAANQAECgIIAgAAAA==.',
No='Notmehssos:BAAANQAECgQIBAAAAA==.Notthechosen:BAAANQADCgEIAQABNQAECgIIAgAHAAAAAA==.',
Ny='Nymeriã:BAAANQADCgYIDgAAAA==.',
Ob='Obzy:BAAANQAECgUIBgAAAA==.Obzz:BAAANQADCgEIAQABNQAECgUIBgAHAAAAAA==.',
Ok='Okamy:BAAANQAECgQIBQAAAA==.',
Op='Opz:BAAANQAECgYIEAAAAA==.',
Pa='Parthos:BAAANQAECgMIAwAAAA==.',
Pe='Pedro:BAAANQADCgcIBwABNQADCggIEQAHAAAAAA==.Perry:BAAANQADCgIIAgAAAA==.',
Ph='Phenomenon:BAAANQAECgIIAgAAAA==.',
Pi='Pittydafoo:BAAANQAECgIIAgAAAA==.',
Pk='Pkunkk:BAAANQAECgcICwAAAA==.',
Pl='Ploxis:BAAANQAFFAIIAgAAAA==.',
Po='Polskashaman:BAAANQAECgMIBAAAAA==.Pookiebonez:BAAANQADCgIIAgABNQAECgIIAwAHAAAAAA==.',
Pr='Prea:BAAANQAECgUIBQAAAA==.Premiumferal:BAABNQAECoEYAAMdAAkJGiBjBgD1AgAdAAkJGiBjBgD1AgAbAAUJFBm3HwBiAQAAAA==.Primecarry:BAABNQAECoEYAAIUAAkJdSPtAgCXAwAUAAkJdSPtAgCXAwAAAA==.Prine:BAAANQAECgcICwABNQAECgkJGAAUAHUjAA==.',
Pu='Puripuri:BAAANQAECgQIBAAAAA==.',
Qi='Qinkipa:BAAANQABCgYIBgAAAA==.',
Qo='Qovo:BAAANQABCgcICQAAAA==.',
Ra='Ragark:BAAANQABCgMIAwAAAA==.Raigko:BAABNQAECoEXAAIcAAkJtB8UFAAmAwAcAAkJtB8UFAAmAwAAAA==.Rainyday:BAAANQAECgUICgAAAA==.Raiva:BAAANQAECgIIAgABNQAECgQIAgAHAAAAAA==.Raivek:BAAANQAECgIIAgAAAA==.Randenton:BAAANQADCgYICAAAAA==.Rassputen:BAABNQAECoEbAAIeAAkJSg+oJQDvAQAeAAkJSg+oJQDvAQAAAA==.',
Re='Reck:BAAANQADCgEIAQAAAA==.Redjive:BAAANQAECggIAQAAAA==.Redonkulos:BAAANQADCgMIBAAAAA==.Relis:BAAANQABCgYICAAAAA==.Rex:BAAANQAECgYIDAAAAA==.',
Ri='Rileyesco:BAAANQABCgUIBgAAAA==.Ripskylark:BAAANQAECgIIAwAAAA==.',
Ro='Roguen:BAAANQAFFAIIAgAAAA==.Romirin:BAAANQADCgQIBAAAAA==.Rotan:BAAANQADCgYICwAAAA==.Roulduke:BAAANQAECgYICwAAAA==.',
['Rù']='Rùckús:BAAANQAECgYIEAAAAA==.',
Sa='Sacredmentos:BAAANQAECgYICwAAAA==.Sammybeans:BAAANQADCgEIAQAAAA==.Sapito:BAAANQADCgYICgAAAA==.',
Se='Seceron:BAAANQAECgQIBwAAAA==.Sekai:BAAANQADCgcICQAAAA==.',
Sg='Sgtslappy:BAAANQADCgMIAwAAAA==.',
Sh='Shanarelle:BAAANQAECgYIEwAAAA==.Shasa:BAAANQAECgYICgAAAA==.Shatteredsky:BAAANQAECgYIDgAAAA==.Shazik:BAABNQAECoEeAAIXAAgJAxdYKQAgAgAXAAgJAxdYKQAgAgAAAA==.Shazzik:BAAANQAECgYICgABNQAECggIHgAXAAMXAA==.Shilbalam:BAAANQADCgQIBAAAAA==.Shmoopy:BAAANQAECgEIAQAAAA==.Shmoove:BAAANQADCgEIAQAAAA==.Shnkz:BAAANQADCgUIBQAAAA==.Shotzer:BAAANQADCgMIBgAAAA==.',
Si='Silzo:BAAANQAECgQIAgAAAA==.Sirjames:BAAANQADCggIDgAAAA==.',
Sk='Skelix:BAACNQAFFIEOAAIXAAYJdB+UAABfAgAXAAYJdB+UAABfAgA1AAQKgSMAAhcACQlLJpQAANkDABcACQlLJpQAANkDAAAA.Skunkpaw:BAAANQADCgUIBgAAAA==.Skysong:BAABNQAECoEYAAMfAAkJJR7DBQDkAgAfAAkJJR7DBQDkAgAgAAEJuQoqMABFAAAAAA==.',
Sl='Slashedeye:BAABNQAECoEgAAIhAAYJzRG5AQC7AQAhAAYJzRG5AQC7AQAAAA==.Slimgucci:BAAANQADCggICAAAAA==.',
Sn='Snowynn:BAAANQAECgYIBwAAAA==.Snubby:BAAANQAECgYIDAAAAA==.',
So='Sonari:BAAANQADCgYIBgAAAA==.',
Sp='Spankz:BAAANQADCgYIBgAAAA==.Spicymeatbal:BAAANQABCgUICAAAAA==.',
St='Strathz:BAAANQAECgYIDAAAAA==.Strongish:BAAANQADCgUIBQAAAA==.',
Su='Superdonkey:BAAANQADCgUIBQABNQAECgkJIAARAGsgAA==.Sushi:BAAANQADCgIIAgAAAA==.Suva:BAAANQADCgYIBgAAAA==.',
Sy='Sylatis:BAAANQAECgYIDAABNQAFFAYIDwANAPMZAA==.Sylätis:BAAANQAECgMIAwABNQAFFAYIDwANAPMZAA==.',
['Sö']='Söultender:BAAANQADCgMIAwABNQAECgUIBwAHAAAAAA==.',
Ta='Talys:BAACNQAFFIEHAAIgAAQJdBMeBABaAQAgAAQJdBMeBABaAQA1AAQKgSAAAiAACQnjHh4GAP0CACAACQnjHh4GAP0CAAAA.Tankly:BAAANQADCgMIAwAAAA==.',
Te='Texicola:BAAANQAECgYIEAAAAA==.',
Th='Thabdeady:BAAANQADCgUIBQABNQAECgYICwAHAAAAAA==.Thabk:BAAANQAECgYICwAAAA==.Thaelorn:BAAANQADCgEIAQAAAA==.Thesyra:BAAANQAECgQIBQAAAA==.Thurmond:BAAANQAECggICAAAAA==.Thurmund:BAAANQADCgYIBgABNQAECggICAAHAAAAAA==.',
Ti='Tidalanxiety:BAAANQAECgQIBQAAAA==.',
To='Toastay:BAAANQADCgcIDgAAAA==.Toastz:BAAANQAECgYIEAAAAA==.Toebeanz:BAAANQAECgQICAAAAA==.Tokken:BAABNQAECoEgAAIcAAkJtx5pFwAOAwAcAAkJtx5pFwAOAwAAAA==.',
Tr='Treebeast:BAAANQAFFAIIBAAAAA==.Troile:BAAANQADCgYIBgAAAA==.Trojen:BAAANQAECgcIDAAAAA==.Trolladin:BAAANQADCgQIBAABNQADCgYIHQAHAAAAAA==.',
Tw='Twig:BAAANQAECggICAAAAA==.',
Ty='Tyras:BAAANQAECgEIAQAAAA==.',
['Tâ']='Tâz:BAAANQAECgYIDwAAAA==.',
Ul='Ulanda:BAAANQAECgMIBAAAAA==.',
Um='Umasi:BAACNQAFFIEHAAIiAAQJ1yTrAAC0AQAiAAQJ1yTrAAC0AQA1AAQKgSAAAiIACQkiJlYAAOYDACIACQkiJlYAAOYDAAAA.',
Un='Underbogg:BAAANQADCgUIBQAAAA==.',
Va='Vail:BAAANQADCgMIAwAAAA==.Valamaldoran:BAAANQADCgUIBQAAAA==.Vanthil:BAAANQAECgIIAgAAAA==.Vaporize:BAAANQADCgUIBQAAAA==.',
Ve='Venandi:BAAANQAECgUICgAAAA==.Vengened:BAAANQAECgIIAgAAAA==.Verax:BAAANQAECgIIAgAAAA==.Verestrasz:BAAANQADCgIIBAAAAA==.',
Vg='Vgly:BAAANQAECgQIDgAAAA==.',
Vi='Vilous:BAAANQAECgYICAAAAA==.',
Vr='Vraax:BAAANQADCgcIBwABNQAECgYIDAAHAAAAAA==.',
Vy='Vyisesham:BAAANQAECgQICAAAAA==.',
['Vý']='Výce:BAAANQAECgEIAQAAAA==.',
Wa='Wagtar:BAAANQADCgYIBgABNQADCgMIAwAHAAAAAA==.Warzug:BAAANQADCgQIBAAAAA==.',
We='Wesjin:BAAANQAECgYIDAAAAA==.Wez:BAAANQAECgEIAQAAAA==.',
Wh='Whiskee:BAAANQAECgYICgAAAA==.',
Wo='Wooglone:BAAANQAECgQIBAAAAA==.',
Wy='Wyndia:BAAANQAECgQIBAAAAA==.',
Xa='Xanthos:BAAANQAECgEIAQABNQAECgMIBAAHAAAAAA==.',
Xb='Xbert:BAAANQADCgcIBwAAAA==.',
Xe='Xela:BAAANQABCgYICgABNQAECgYIDAAHAAAAAA==.Xenophontes:BAAANQAECgcIEwABNQAFFAIIAgAHAAAAAA==.',
Xi='Xihuang:BAAANQAECgYIDgABNQAFFAIIAgAHAAAAAA==.Xiia:BAAANQADCggICwAAAA==.',
Xo='Xouu:BAAANQAECggIAQABNQAECggIBQAHAAAAAA==.',
Xx='Xxuublue:BAAANQAECggIBQAAAA==.Xxuuspr:BAAANQAECggIAgABNQAECggIBQAHAAAAAA==.Xxuutwo:BAAANQAECggIAQABNQAECggIBQAHAAAAAA==.',
Ya='Yaoguai:BAAANQAECgMIBAAAAA==.Yasei:BAAANQAECgQIBAAAAA==.Yawgmoth:BAAANQAECgQIBAABNQAECgYIDgAHAAAAAA==.',
Za='Zaleris:BAAANQAECgQIBQAAAA==.',
Ze='Zephon:BAAANQAECgQIBQAAAA==.',
Zo='Zotiel:BAAANQADCgcIDwABNQAFFAUICgABAEsNAA==.',
Zy='Zynisch:BAAANQADCgcIEwAAAA==.',
['Ær']='Æris:BAAANQADCgMIAwAAAA==.',
['Ìr']='Ìroh:BAAANQADCgUIBgABNQAECgUIBwAHAAAAAA==.',
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
