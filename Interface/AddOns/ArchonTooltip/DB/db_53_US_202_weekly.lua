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

local lookup = {'Unknown-Unknown','Mage-Arcane','Mage-Frost','DeathKnight-Frost','Monk-Brewmaster','Warlock-Demonology','Warlock-Destruction','Monk-Windwalker','Paladin-Holy','Druid-Balance','Hunter-BeastMastery','Hunter-Marksmanship','Rogue-Assassination','Rogue-Subtlety','Shaman-Restoration','Mage-Fire','Evoker-Preservation','Warrior-Arms','Paladin-Protection',}
local provider = {region='US',realm='Spirestone',name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Abduon:BAAANQADCgQIBAAAAA==.',
Ac='Aciddeath:BAAANQADCggICAABNQAECgcIEQABAAAAAA==.',
Ad='Admaris:BAAANQAECggIDQAAAA==.',
Ag='Agni:BAABNQAECoEXAAMCAAkJHCCUEAA5AwACAAkJHCCUEAA5AwADAAEJQhjfGABIAAAAAA==.',
Al='Alnasham:BAAANQAECggIEgAAAA==.Alnava:BAAANQADCggICAAAAA==.Alvoka:BAAANQAECgUIBgAAAA==.',
Am='Amarillos:BAAANQAECgYIBgAAAA==.Amarillys:BAAANQAECggICgAAAA==.Ammutseba:BAAANQAECgQIBwAAAA==.',
An='Anfall:BAAANQAECgcIDgAAAA==.Angermeier:BAAANQAECgQIBAAAAA==.Angrylady:BAAANQADCggICAAAAA==.Anjuna:BAAANQADCgUIBQAAAA==.Anohru:BAAANQADCgcIEwAAAA==.Anthos:BAAANQAECgMIAwAAAA==.',
Ap='Aphotic:BAAANQABCgQIAgAAAA==.',
Ar='Arthaniis:BAAANQAECgYIDQAAAA==.',
Au='Audideath:BAAANQADCgYIEQAAAA==.Auurdeath:BAAANQADCggIEwAAAA==.',
Aw='Aw:BAAANQAFFAEIAQAAAA==.',
Ax='Ax:BAEANQAECggIEwAAAA==.',
Ba='Bamph:BAAANQAECgEIAQAAAA==.Bangbang:BAAANQADCgIIAgAAAA==.Batez:BAAANQAECgQIBAABNQAECgkJGAAEAHsfAA==.',
Bd='Bdk:BAAANQAECgIIAQAAAA==.Bdog:BAAANQAECgEIAwAAAA==.',
Be='Beeatinu:BAAANQADCgQIAwAAAA==.Beledros:BAAANQAECggIDgAAAA==.Beni:BAAANQAECggIEgAAAA==.Benson:BAABNQAECoEYAAIFAAkJRxauAwCIAgAFAAkJRxauAwCIAgAAAA==.Bensonadin:BAAANQAECgQIBAAAAA==.',
Bi='Bina:BAAANQAECgQIBQAAAA==.Birblock:BAABNQAFFIEJAAMGAAUJ6hXvAACEAQAGAAQJ/hrvAACEAQAHAAIJygEvBACXAAAAAA==.',
Bo='Bobbo:BAAANQADCgEIAQAAAA==.',
Br='Brek:BAAANQADCggICAAAAA==.Brewtherguy:BAAANQAECgUIBgAAAA==.Bruceshepard:BAAANQADCgQIBwABNQADCgcIEAABAAAAAA==.Brutebuffalo:BAAANQAECgUIBgAAAA==.',
Bu='Bubbleboi:BAAANQADCgIIAgAAAA==.Bubblebôy:BAAANQAECgIIAgAAAA==.Bublz:BAAANQAECgEIAQAAAA==.',
['Bâ']='Bâra:BAAANQAECgMIBAAAAA==.',
Ce='Cedren:BAAANQAECggIEAAAAA==.Ceewhya:BAAANQADCgQIBAAAAA==.Celestika:BAAANQABCgIIAgAAAA==.Cerari:BAAANQAECgEIAQAAAA==.',
Ch='Chalix:BAAANQADCgYICAAAAA==.Chama:BAAANQAECgUIBQAAAA==.Cheapheal:BAAANQAECgYICgAAAA==.Cheburashka:BAAANQAECggIEwAAAA==.Chimerabob:BAAANQAECgEIAQAAAA==.Chunkymonkey:BAABNQAECoEXAAIIAAkJhR4OBQD7AgAIAAkJhR4OBQD7AgAAAA==.',
Ci='Cidren:BAAANQADCgcIBwAAAA==.',
Cl='Clappncheeks:BAAANQAECgEIAQAAAA==.Claudefrollo:BAAANQADCgYIDwAAAA==.',
Cr='Crankyelf:BAAANQABCgEIAQAAAA==.Crimsa:BAAANQAECgMIBAAAAA==.Crimsonaxel:BAAANQAECgIIAwAAAA==.Cryogen:BAAANQAECgQIBAAAAA==.',
Cu='Cursewords:BAAANQADCgUIBQABNQAECgQIBAABAAAAAA==.',
Da='Daemonproph:BAAANQADCgYIBgAAAA==.Dakini:BAAANQAECgIIAgAAAA==.Dam:BAAANQADCgUIBQAAAA==.Dangerruss:BAAANQAECgIIBAAAAA==.Dashytash:BAAANQAECgQIBAAAAA==.Dawnsoul:BAAANQAECgIIAgAAAA==.',
De='Demb:BAAANQAECgQIBwAAAA==.Demonicchoas:BAAANQAECgcIEAAAAA==.Denagorn:BAAANQAECggIEQAAAA==.Densama:BAAANQADCgEIAQABNQAECggIEQABAAAAAA==.Deutzfr:BAAANQAECggIEwAAAA==.Devos:BAAANQAECgYICgABNQAECgcIDgABAAAAAA==.',
Di='Dizzleman:BAAANQADCgYIDAAAAA==.',
Do='Dominant:BAAANQAECgUIBgAAAA==.',
Dp='Dpssos:BAAANQADCgYIBgAAAA==.',
Dr='Drag:BAAANQADCgYICAAAAA==.Dreadmar:BAAANQADCgYICAAAAA==.Drock:BAAANQAECgMIBQAAAA==.Druidgale:BAAANQAECgEIAQAAAA==.Drybonez:BAAANQAECgIIAgAAAA==.Dräkarnoir:BAAANQADCggICAAAAA==.',
Dt='Dtb:BAAANQAECggIEAAAAA==.',
Du='Dushimaya:BAAANQAECgYIDAAAAA==.',
Dv='Dvil:BAAANQAECgEIAQABNQAECgMIBQABAAAAAA==.',
Dw='Dwyndi:BAAANQAECgYIBgAAAA==.',
Ei='Eisador:BAAANQAECgIIAgAAAA==.',
El='Elsen:BAAANQAECgIIAgAAAA==.Elsha:BAAANQAECgUICAAAAA==.',
Em='Emp:BAAANQAECgUIBgAAAA==.',
Ev='Evelira:BAAANQAECgcIBwABNQAECgcIEgABAAAAAA==.',
Ey='Eyja:BAAANQADCgEIAQAAAA==.',
Ez='Ezpzndaheezy:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.',
Fa='Fathercoast:BAAANQAECgQIBQAAAA==.',
Fe='Fearful:BAABNQAECoEZAAIJAAkJHQg7IQAKAgAJAAkJHQg7IQAKAgAAAA==.Felstrider:BAAANQADCgUIBQAAAA==.Ferador:BAAANQAECggIEwAAAA==.',
Fi='Figgleslock:BAAANQADCgUIBQAAAA==.',
Fl='Flakester:BAAANQAECgMIAwAAAA==.Fleebly:BAAANQAECgUICAAAAA==.',
Fo='Fourbees:BAAANQAECgQIBAAAAA==.',
Fu='Fursure:BAAANQAECgMIAwAAAA==.',
Gi='Gilgamesh:BAAANQAECgEIAQAAAA==.',
Gr='Graygkl:BAAANQAECgMIAwAAAA==.Greshanwise:BAAANQADCgUICwAAAA==.Grimreaper:BAAANQAECgQIBwAAAA==.Groa:BAAANQABCgQIBgAAAA==.Groag:BAAANQAECgUICAAAAA==.',
Ha='Haarp:BAAANQADCgYIDAAAAA==.Hakü:BAAANQADCgYIBgAAAA==.',
He='Heifer:BAABNQAECoEYAAIKAAkJ+x4kCwDtAgAKAAkJ+x4kCwDtAgABNQAFFAEIAQABAAAAAA==.Hemophilia:BAAANQAECgMIBAAAAA==.Heydk:BAAANQAECgMIBQAAAA==.Heydruid:BAAANQADCgYIBwABNQAECgMIBQABAAAAAA==.',
Ho='Hollowshädix:BAAANQAECgEIAQAAAA==.Holyanxiety:BAAANQADCgYIBgAAAA==.Holydave:BAAANQAECgEIAQAAAA==.Holymentos:BAAANQAECgEIAQABNQAECgUIBgABAAAAAA==.Hottsauce:BAAANQAECggICQAAAA==.',
Hu='Hundard:BAAANQADCgIIAgAAAA==.Huntersmarc:BAAANQADCgYIBgAAAA==.',
Ib='Ibetrollinya:BAAANQADCggIEAABNQAECgMIBQABAAAAAA==.Iblisshaytan:BAAANQAECgcIDAAAAA==.Ibtrollin:BAAANQADCgYIEQAAAA==.',
Ig='Ignacious:BAAANQAECgEIAQAAAA==.',
Io='Ionissa:BAAANQAECgQIBgAAAA==.',
Is='Ischia:BAAANQAECggIEwAAAA==.',
Ja='Jarl:BAAANQADCgQIBAAAAA==.',
Jc='Jch:BAABNQAECoEYAAMLAAkJlCPeBQAzAwALAAgJOiXeBQAzAwAMAAEJZBbvNQBNAAAAAA==.',
Je='Jeay:BAAANQADCgIIAgAAAA==.Jedijeed:BAAANQAECgcIEAAAAA==.Jedikepjr:BAAANQADCgYIBgABNQAECgcIEAABAAAAAA==.Jenova:BAAANQADCgUIBwAAAA==.Jepage:BAAANQAECgMIAwAAAA==.',
Jo='Jolyne:BAAANQADCggIEAAAAA==.',
Jp='Jprottsoo:BAAANQAECgYICgAAAA==.',
Ju='Jubei:BAAANQAECgEIAQAAAA==.',
Ka='Kalmya:BAAANQAECgQIBgAAAA==.Kalrath:BAAANQADCgYIBgABNQADCgYIDAABAAAAAA==.',
Ke='Keizzer:BAAANQAECgQIBgABNQAECgUIBQABAAAAAA==.',
Kh='Khazra:BAAANQAECgIIAgAAAA==.',
Ki='Kierràalexis:BAAANQADCgYIBgAAAA==.',
Kl='Klunder:BAAANQAECgIIAgAAAA==.',
Ko='Korris:BAAANQAECgUICQAAAA==.Kostik:BAAANQADCgUIBQAAAA==.',
Kr='Kridillis:BAAANQAECgQIBwAAAA==.',
Ky='Kybinc:BAAANQABCgYIBgAAAA==.',
['Kí']='Kírã:BAAANQABCgIIBAAAAA==.',
La='Lawls:BAAANQADCgQICQAAAA==.Lazycow:BAAANQAECgYIDAAAAA==.Lazyfrost:BAAANQAECgUICAAAAA==.',
Le='Lethò:BAAANQAECgQICAAAAA==.Lethô:BAAANQADCggICAAAAA==.Lethö:BAAANQAECgIIBAAAAA==.',
Li='Lilzarthe:BAAANQAECgIIBAAAAA==.',
Lo='Loerasdh:BAAANQAECgQICwAAAA==.Loko:BAABNQAECoEXAAIKAAkJdBrmDADSAgAKAAkJdBrmDADSAgAAAA==.Looio:BAAANQADCgMIAgAAAA==.',
Lu='Lucien:BAAANQABCgQIBAAAAA==.Luxxus:BAAANQAECgUIBQAAAA==.',
Ly='Lyndsy:BAAANQADCgUIBQAAAA==.Lyri:BAAANQADCgMIAwAAAA==.',
Ma='Mageyousad:BAAANQADCgEIAQAAAA==.Makhtor:BAAANQAECgMIBQAAAA==.Mallaer:BAAANQAECgUICQAAAA==.Malícíous:BAAANQAECgQIBAAAAA==.Mantakore:BAAANQAECgYICQAAAA==.Marcdruid:BAAANQAECgMIAwAAAA==.Maubles:BAAANQADCggICAABNQAECgcIEAABAAAAAA==.',
Me='Menopaws:BAAANQAECgUICAAAAA==.Merrtt:BAAANQADCgcIBwAAAA==.Mertrik:BAAANQAECgQIBgAAAA==.',
Mi='Midk:BAAANQAECgEIAQAAAA==.Mikayy:BAAANQAFFAIIAgAAAA==.Milenko:BAAANQAECgMIBAAAAA==.Milly:BAAANQADCggICAABNQAECgMIBAABAAAAAA==.',
Mo='Molfsongal:BAAANQADCgIIAgAAAA==.Monstrous:BAAANQAECggIEwAAAA==.Moocher:BAAANQAECgEIAQAAAA==.Moonpie:BAAANQADCgUICQAAAA==.Mordecaii:BAAANQADCgYICQAAAA==.Morgul:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Mothman:BAAANQADCgcICwAAAA==.',
Ms='Msbehaven:BAAANQAECgIIBAAAAA==.',
Mu='Muffìns:BAAANQADCgcICgAAAA==.',
My='Mynuturchin:BAAANQAECgEIAQAAAA==.',
Na='Nagy:BAAANQADCgYIBgAAAA==.',
Ni='Night:BAAANQADCggIEQAAAA==.Nightsecho:BAAANQABCgQIAgAAAA==.Nightshris:BAAANQADCgMIAwAAAA==.',
No='Notmehssos:BAAANQAECgEIAQAAAA==.',
Ny='Nymeriã:BAAANQADCgYIDgAAAA==.',
Ob='Obzy:BAAANQAECgEIAQAAAA==.Obzz:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.',
Ok='Okamy:BAAANQAECgEIAQAAAA==.',
Op='Opz:BAAANQAECgYICgAAAA==.',
Pa='Parthos:BAAANQAECgMIAwAAAA==.',
Pe='Pedro:BAAANQADCgcIBwABNQADCggIEQABAAAAAA==.Perry:BAAANQADCgIIAgAAAA==.',
Ph='Phenomenon:BAAANQAECgIIAgAAAA==.',
Pi='Pittydafoo:BAAANQAECgEIAQAAAA==.',
Pk='Pkunkk:BAAANQAECgcICwAAAA==.',
Pl='Ploxis:BAAANQAECggIDAAAAA==.',
Po='Polskashaman:BAAANQAECgEIAQAAAA==.Pookiebonez:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.',
Pr='Premiumferal:BAABNQAECoEYAAMNAAkJGiC4AgAjAwANAAkJGiC4AgAjAwAOAAUJFBlOGQByAQAAAA==.Primecarry:BAAANQAECggIEwAAAA==.Prine:BAAANQAECgcICwABNQAECggIEwABAAAAAA==.',
Pu='Puripuri:BAAANQAECgQIBAAAAA==.',
Qi='Qinkipa:BAAANQABCgQIAgAAAA==.',
Qo='Qovo:BAAANQABCgYIBwAAAA==.',
Ra='Ragark:BAAANQABCgMIAwAAAA==.Raigko:BAAANQAECgcIDwAAAA==.Rainyday:BAAANQAECgQIBQAAAA==.Raivek:BAAANQAECgIIAgAAAA==.Randenton:BAAANQADCgYICAAAAA==.Rassputen:BAAANQAECgcIEAAAAA==.',
Re='Reck:BAAANQADCgEIAQAAAA==.Redjive:BAAANQADCgcIDQAAAA==.Redonkulos:BAAANQADCgMIBAAAAA==.Relis:BAAANQABCgYICAAAAA==.Rex:BAAANQAECgUIBgAAAA==.',
Ri='Rileyesco:BAAANQABCgUIBgAAAA==.Ripskylark:BAAANQAECgIIAwAAAA==.',
Ro='Roguen:BAAANQAECgQICQABNQAECgcIDAABAAAAAA==.Romirin:BAAANQADCgQIBAAAAA==.Rotan:BAAANQADCgYICwAAAA==.Roulduke:BAAANQAECgQIBAAAAA==.',
['Rù']='Rùckús:BAAANQAECgYICgAAAA==.',
Sa='Sacredmentos:BAAANQAECgUIBgAAAA==.Sapito:BAAANQADCgYICgAAAA==.',
Se='Seceron:BAAANQAECgIIAwAAAA==.Sekai:BAAANQADCgcICQAAAA==.',
Sg='Sgtslappy:BAAANQADCgMIAwAAAA==.',
Sh='Shanarelle:BAAANQAECgYIDQAAAA==.Shasa:BAAANQAECgUICQAAAA==.Shatteredsky:BAAANQAECgUICAAAAA==.Shazik:BAAANQAECgYICAAAAA==.Shazzik:BAAANQAECgYIBgABNQAECgYICAABAAAAAA==.Shilbalam:BAAANQADCgQIBAAAAA==.Shmoopy:BAAANQAECgEIAQAAAA==.Shmoove:BAAANQADCgEIAQAAAA==.Shnkz:BAAANQABCgQIBAAAAA==.Shotzer:BAAANQADCgMIBgAAAA==.',
Si='Sirjames:BAAANQADCgMIBAAAAA==.',
Sk='Skelix:BAACNQAFFIEIAAIPAAUJWBr6AADPAQAPAAUJWBr6AADPAQA1AAQKgRoAAg8ACQmTJW4AANYDAA8ACQmTJW4AANYDAAAA.Skunkpaw:BAAANQADCgUIBgAAAA==.Skysong:BAAANQAECggIEwAAAA==.',
Sl='Slashedeye:BAABNQAECoEUAAIQAAYJ2AtlAQCUAQAQAAYJ2AtlAQCUAQAAAA==.Slimgucci:BAAANQADCggICAAAAA==.',
Sn='Snowynn:BAAANQAECgEIAQAAAA==.Snubby:BAAANQAECgQIBgAAAA==.',
So='Sonari:BAAANQADCgYIBgAAAA==.',
Sp='Spankz:BAAANQADCgYIBgAAAA==.Spicymeatbal:BAAANQABCgMIAwAAAA==.',
St='Strathz:BAAANQAECgUIBgAAAA==.Strongish:BAAANQADCgUIBQAAAA==.',
Su='Sushi:BAAANQADCgIIAgAAAA==.Suva:BAAANQADCgYIBgAAAA==.',
Sy='Sylatis:BAAANQAECgYIDAABNQAFFAUICQAGAOoVAA==.Sylätis:BAAANQAECgMIAwABNQAFFAUICQAGAOoVAA==.',
['Sö']='Söultender:BAAANQADCgMIAwABNQAECgIIAgABAAAAAA==.',
Ta='Talys:BAABNQAECoEYAAIRAAkJtR2bBAD2AgARAAkJtR2bBAD2AgAAAA==.Tankly:BAAANQADCgMIAwAAAA==.',
Te='Texicola:BAAANQAECgYICgAAAA==.',
Th='Thabk:BAAANQAECgQIBAAAAA==.Thesyra:BAAANQAECgEIAQAAAA==.Thurmond:BAAANQADCgYIDAAAAA==.Thurmund:BAAANQADCgYIBgABNQADCgYIDAABAAAAAA==.',
Ti='Tidalanxiety:BAAANQAECgEIAQAAAA==.',
To='Toastay:BAAANQADCgcIBwAAAA==.Toastz:BAAANQAECgYICgAAAA==.Toebeanz:BAAANQAECgIIBAAAAA==.Tokken:BAABNQAECoEYAAISAAkJSR1AEwDvAgASAAkJSR1AEwDvAgAAAA==.',
Tr='Treebeast:BAAANQAFFAIIAwAAAA==.Troile:BAAANQADCgYIBgAAAA==.Trojen:BAAANQAECgYICwAAAA==.Trolladin:BAAANQADCgQIBAABNQADCgYIEQABAAAAAA==.',
Tw='Twig:BAAANQAECggIAwAAAA==.',
Ty='Tyras:BAAANQADCgcIDQAAAA==.',
['Tâ']='Tâz:BAAANQAECgUICQAAAA==.',
Ul='Ulanda:BAAANQAECgEIAQAAAA==.',
Um='Umasi:BAABNQAECoEYAAITAAkJHyY4AADsAwATAAkJHyY4AADsAwAAAA==.',
Un='Underbogg:BAAANQADCgUIBQAAAA==.',
Va='Vanthil:BAAANQAECgIIAgAAAA==.Vaporize:BAAANQADCgUIBQAAAA==.',
Ve='Venandi:BAAANQAECgQIBQAAAA==.Vengened:BAAANQADCgcIEgAAAA==.Verax:BAAANQAECgIIAgAAAA==.',
Vg='Vgly:BAAANQAECgMIBAAAAA==.',
Vi='Vilous:BAAANQAECgMIBQAAAA==.',
Vr='Vraax:BAAANQADCgcIBwABNQAECgYIDAABAAAAAA==.',
Vy='Vyisesham:BAAANQAECgIIBAAAAA==.',
['Vý']='Výce:BAAANQAECgEIAQAAAA==.',
Wa='Wagtar:BAAANQABCgUIBwABNQABCgYIBgABAAAAAA==.Warzug:BAAANQADCgQIBAAAAA==.',
We='Wesjin:BAAANQAECgUIBgAAAA==.Wez:BAAANQAECgEIAQAAAA==.',
Wh='Whiskee:BAAANQAECgYICgAAAA==.',
Wo='Wooglone:BAAANQAECgQIBAAAAA==.',
Wy='Wyndia:BAAANQADCgcICgAAAA==.',
Xa='Xanthos:BAAANQAECgEIAQAAAA==.',
Xb='Xbert:BAAANQABCgUIBwAAAA==.',
Xe='Xela:BAAANQABCgYICAABNQAECgUIBgABAAAAAA==.Xenophontes:BAAANQAECgcIEgAAAA==.',
Xi='Xihuang:BAAANQAECgQICAABNQAECgcIDAABAAAAAA==.Xiia:BAAANQADCggICwAAAA==.',
Xx='Xxuublue:BAAANQAECggIBQAAAA==.',
Ya='Yaoguai:BAAANQAECgMIBAAAAA==.Yawgmoth:BAAANQAECgQIBAABNQAECgUICAABAAAAAA==.',
Za='Zaleris:BAAANQAECgQIBQAAAA==.',
Ze='Zephon:BAAANQAECgEIAQAAAA==.',
Zo='Zotiel:BAAANQADCgcICQABNQAECggIEQABAAAAAA==.',
Zy='Zynisch:BAAANQADCgcIEwAAAA==.',
['Ær']='Æris:BAAANQADCgMIAwAAAA==.',
['Ìr']='Ìroh:BAAANQADCgMIAwABNQAECgIIAgABAAAAAA==.',
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
