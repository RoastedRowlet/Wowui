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

local lookup = {'Unknown-Unknown',}
local provider = {region='US',realm='Spirestone',name='US',type='weekly',zone=53,date='2026-09-01',data={Ad='Admaris:BAAANQAECgUIBgAAAA==.',
Ag='Agni:BAAANQAECggIDgAAAA==.',
Al='Alnasham:BAAANQAECgcICgAAAA==.Alvoka:BAAANQAECgEIAQAAAA==.',
Am='Amarillos:BAAANQAECgYIBgAAAA==.Amarillys:BAAANQAECgcIAgAAAA==.Ammutseba:BAAANQAECgEIAQAAAA==.',
An='Anfall:BAAANQAECgUIBwAAAA==.Angermeier:BAAANQADCgYIBwAAAA==.Angrylady:BAAANQADCggICAAAAA==.Anjuna:BAAANQADCgUIBQAAAA==.Anohru:BAAANQADCgYIDAAAAA==.Anthos:BAAANQAECgMIAwAAAA==.',
Ar='Arthaniis:BAAANQAECgUIBwAAAA==.',
Au='Audideath:BAAANQADCgYICwAAAA==.Auurdeath:BAAANQADCgcIEQAAAA==.',
Aw='Aw:BAAANQAECgcICQAAAA==.',
Ax='Ax:BAEANQAECgcICwAAAA==.',
Ba='Bamph:BAAANQADCggIDQAAAA==.Batez:BAAANQADCgYIBgABNQAECgcIDQABAAAAAA==.',
Bd='Bdk:BAAANQADCgYIBgAAAA==.Bdog:BAAANQAECgEIAwAAAA==.',
Be='Beeatinu:BAAANQADCgQIAwAAAA==.Beledros:BAAANQAECgYIBgAAAA==.Beni:BAAANQADCggIDwAAAA==.Benson:BAAANQAECgcIDQAAAA==.',
Bi='Birblock:BAAANQAFFAMIAwAAAA==.',
Bo='Bobbo:BAAANQADCgIIAQAAAA==.',
Br='Brek:BAAANQADCggICAAAAA==.Brewtherguy:BAAANQAECgEIAQAAAA==.Bruceshepard:BAAANQADCgQIBwABNQADCgYICgABAAAAAA==.Brutebuffalo:BAAANQAECgEIAQAAAA==.',
Bu='Bubblebôy:BAAANQADCgQIBAAAAA==.Bublz:BAAANQAECgEIAQAAAA==.',
['Bâ']='Bâra:BAAANQAECgMIAwAAAA==.',
Ce='Cedren:BAAANQAECgUICAAAAA==.Cerari:BAAANQAECgEIAQAAAA==.',
Ch='Chalix:BAAANQADCgYICAAAAA==.Chama:BAAANQADCgYIBgAAAA==.Cheapheal:BAAANQAECgQIBAAAAA==.Cheburashka:BAAANQAECgcICwAAAA==.Chunkymonkey:BAAANQAECgcIDAAAAA==.',
Ci='Cidren:BAAANQADCgcIBwAAAA==.',
Cl='Claudefrollo:BAAANQADCgYICAAAAA==.',
Cr='Crimsa:BAAANQAECgEIAQAAAA==.Crimsonaxel:BAAANQAECgEIAQAAAA==.Cryogen:BAAANQAECgQIBAAAAA==.',
Cu='Cursewords:BAAANQADCgUIBQAAAA==.',
Da='Dakini:BAAANQAECgIIAgAAAA==.Dam:BAAANQADCgUIBQAAAA==.Dangerruss:BAAANQAECgIIAgAAAA==.Dashytash:BAAANQADCggIDgAAAA==.Dawnsoul:BAAANQAECgEIAQAAAA==.',
De='Demb:BAAANQAECgMIAwAAAA==.Demonicchoas:BAAANQAECgYICQAAAA==.Denagorn:BAAANQAECggIDwAAAA==.Densama:BAAANQADCgEIAQABNQAECggIDwABAAAAAA==.Deutzfr:BAAANQAECgcIDwAAAA==.Devos:BAAANQAECgQIBAABNQAECgYICgABAAAAAA==.',
Di='Dizzleman:BAAANQADCgYICgAAAA==.',
Do='Dominant:BAAANQAECgEIAQAAAA==.',
Dp='Dpssos:BAAANQADCgYIBgAAAA==.',
Dr='Drag:BAAANQADCgIIAgAAAA==.Dreadmar:BAAANQADCgYICAAAAA==.Drock:BAAANQAECgIIAgAAAA==.Druidgale:BAAANQAECgEIAQAAAA==.Drybonez:BAAANQAECgIIAgAAAA==.',
Dt='Dtb:BAAANQAECgcIDAAAAA==.',
Du='Dushimaya:BAAANQAECgUIBgAAAA==.',
Ei='Eisador:BAAANQAECgIIAgAAAA==.',
El='Elsen:BAAANQAECgIIAgAAAA==.Elsha:BAAANQAECgMIAwAAAA==.',
Em='Emp:BAAANQAECgQIBQAAAA==.',
Ey='Eyja:BAAANQADCgEIAQAAAA==.',
Ez='Ezpzndaheezy:BAAANQADCgYIBgABNQADCgYIBgABAAAAAA==.',
Fa='Fathercoast:BAAANQAECgEIAQAAAA==.',
Fe='Fearful:BAAANQAFFAEIAQAAAA==.Felstrider:BAAANQADCgUIBQAAAA==.Ferador:BAAANQAECgcICwAAAA==.',
Fl='Flakester:BAAANQADCggIDQAAAA==.Fleebly:BAAANQAECgMIAwAAAA==.',
Fo='Fourbees:BAAANQABCgQIBAAAAA==.',
Fu='Fursure:BAAANQAECgMIAwAAAA==.',
Gi='Gilgamesh:BAAANQADCggIDgAAAA==.',
Gr='Graygkl:BAAANQADCggIDgAAAA==.Greshanwise:BAAANQADCgUIBgAAAA==.Grimreaper:BAAANQAECgMIAwAAAA==.Groa:BAAANQABCgQIBgAAAA==.Groag:BAAANQAECgMIAwAAAA==.',
Ha='Haarp:BAAANQADCgYIDAAAAA==.Hakü:BAAANQADCgEIAQAAAA==.',
He='Heifer:BAAANQAECggIDwABNQAFFAEIAQABAAAAAA==.Hemophilia:BAAANQAECgEIAQAAAA==.Heydk:BAAANQAECgIIAgAAAA==.Heydruid:BAAANQADCgYIBwABNQAECgIIAgABAAAAAA==.',
Hi='Hithaeglir:BAAANQAECgQIBAAAAA==.',
Ho='Holyanxiety:BAAANQADCgYIBgAAAA==.Holymentos:BAAANQADCgYICwABNQADCggIEAABAAAAAA==.Hottsauce:BAAANQAECgcIBwAAAA==.',
Hu='Hundard:BAAANQADCgIIAgAAAA==.',
Ib='Ibetrollinya:BAAANQADCgcICAABNQAECgIIAgABAAAAAA==.Iblisshaytan:BAAANQAECgQIBQABNQAECgQIBgABAAAAAA==.Ibtrollin:BAAANQADCgUIBgAAAA==.',
Ig='Ignacious:BAAANQAECgEIAQAAAA==.',
Io='Ionissa:BAAANQAECgIIAgAAAA==.',
Is='Ischia:BAAANQAECgcICwAAAA==.',
Jc='Jch:BAAANQAECggIDgAAAA==.',
Je='Jeay:BAAANQADCgIIAgAAAA==.Jedijeed:BAAANQAECgYICQAAAA==.Jenova:BAAANQADCgUIBQAAAA==.Jepage:BAAANQADCggIDgAAAA==.',
Jo='Jolyne:BAAANQADCggICAAAAA==.',
Jp='Jprottsoo:BAAANQAECgQIBAAAAA==.',
Ju='Jubei:BAAANQAECgEIAQAAAA==.',
Ka='Kalmya:BAAANQAECgIIAgAAAA==.Kalrath:BAAANQADCgYIBgABNQADCgYIDAABAAAAAA==.',
Ke='Keizzer:BAAANQAECgIIAgAAAA==.',
Kh='Khazra:BAAANQADCgIIAgAAAA==.',
Kl='Klunder:BAAANQADCgcIBwAAAA==.',
Ko='Korris:BAAANQAECgMIBAAAAA==.Kostik:BAAANQADCgUIBQAAAA==.',
Kr='Kridillis:BAAANQAECgMIAwAAAA==.',
Ky='Kybinc:BAAANQABCgQIBAAAAA==.',
La='Lawls:BAAANQADCgQIBwAAAA==.Lazycow:BAAANQAECgUIBgAAAA==.Lazyfrost:BAAANQAECgMIAwAAAA==.',
Le='Lethò:BAAANQAECgMIBAAAAA==.Lethö:BAAANQAECgEIAQAAAA==.',
Li='Lilzarthe:BAAANQAECgIIAgAAAA==.',
Lo='Loerasdh:BAAANQAECgMIBQAAAA==.Loko:BAAANQAECgcIDAAAAA==.Looio:BAAANQADCgMIAgAAAA==.',
Lu='Luxxus:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.',
Ly='Lyndsy:BAAANQADCgUIBQAAAA==.Lyri:BAAANQADCgMIAwAAAA==.',
Ma='Mageyousad:BAAANQADCgEIAQAAAA==.Makhtor:BAAANQAECgIIAgAAAA==.Mallaer:BAAANQAECgQIBAAAAA==.Malícíous:BAAANQADCgYICAAAAA==.Mantakore:BAAANQAECgMIAwAAAA==.Marcdruid:BAAANQADCgYICwAAAA==.Maubles:BAAANQADCggICAABNQAECgYICQABAAAAAA==.',
Me='Menopaws:BAAANQAECgMIAwAAAA==.Merrtt:BAAANQADCgcIBwAAAA==.Mertrik:BAAANQAECgIIAgAAAA==.',
Mi='Midk:BAAANQAECgEIAQAAAA==.Mikayy:BAAANQAECgcICwAAAA==.Milenko:BAAANQAECgEIAQAAAA==.',
Mo='Molfsongal:BAAANQADCgIIAgAAAA==.Monstrous:BAAANQAECgcICwAAAA==.Moocher:BAAANQADCggIDgAAAA==.Moonpie:BAAANQADCgQIBAAAAA==.Mordecaii:BAAANQADCgUICQAAAA==.Mothman:BAAANQADCgUICAAAAA==.',
Ms='Msbehaven:BAAANQAECgIIAgAAAA==.',
Mu='Muffìns:BAAANQADCgMIAwAAAA==.',
Ni='Night:BAAANQADCggICgAAAA==.Nightshris:BAAANQADCgMIAwAAAA==.',
No='Notmehssos:BAAANQADCggICQAAAA==.',
Ny='Nymeriã:BAAANQADCgYICQAAAA==.',
Ob='Obzy:BAAANQAECgEIAQAAAA==.',
Ok='Okamy:BAAANQADCggIDgAAAA==.',
Op='Opz:BAAANQAECgQIBAAAAA==.',
Pa='Parthos:BAAANQADCgUIBQAAAA==.',
Pe='Perry:BAAANQADCgIIAgAAAA==.',
Ph='Phenomenon:BAAANQADCgYICwAAAA==.',
Pi='Pittydafoo:BAAANQAECgEIAQAAAA==.',
Pk='Pkunkk:BAAANQAECgcICwAAAA==.',
Pl='Ploxis:BAAANQAECgQIBAAAAA==.',
Po='Polskashaman:BAAANQADCgcIDAAAAA==.',
Pr='Premiumferal:BAAANQAECggIDgAAAA==.Primecarry:BAAANQAECgcICwAAAA==.Prine:BAAANQAECgQIBAABNQAECgcICwABAAAAAA==.',
Pu='Puripuri:BAAANQAECgQIBAAAAA==.',
Ra='Raigko:BAAANQAECgYICQAAAA==.Rainyday:BAAANQAECgEIAQAAAA==.Raivek:BAAANQAECgIIAgAAAA==.Randenton:BAAANQADCgYICAAAAA==.Rassputen:BAAANQAECgYICQAAAA==.',
Re='Redjive:BAAANQADCgYICAAAAA==.Redonkulos:BAAANQADCgMIBAAAAA==.Relis:BAAANQABCgIIAgAAAA==.Rex:BAAANQAECgEIAQAAAA==.',
Ri='Ripskylark:BAAANQAECgIIAwAAAA==.',
Ro='Roguen:BAAANQAECgQIBgAAAA==.Rotan:BAAANQADCgUIBQAAAA==.Roulduke:BAAANQADCgYIBgAAAA==.',
['Rù']='Rùckús:BAAANQAECgQIBAAAAA==.',
Sa='Sacredmentos:BAAANQADCggIEAAAAA==.Sapito:BAAANQADCgQIBAABNQADCgYIBwABAAAAAA==.',
Se='Seceron:BAAANQAECgEIAQAAAA==.Sekai:BAAANQADCgMIAwAAAA==.',
Sg='Sgtslappy:BAAANQADCgMIAwAAAA==.',
Sh='Shanarelle:BAAANQAECgUIBwAAAA==.Shasa:BAAANQAECgQIBAAAAA==.Shatteredsky:BAAANQAECgMIAwAAAA==.Shazik:BAAANQADCggICAAAAA==.Shazzik:BAAANQADCggICAABNQADCggICAABAAAAAA==.Shilbalam:BAAANQADCgQIBAAAAA==.Shmoopy:BAAANQADCgYICQAAAA==.Shotzer:BAAANQADCgMIBgAAAA==.',
Si='Silzo:BAAANQADCggIDgAAAA==.Sirjames:BAAANQADCgMIBAAAAA==.',
Sk='Skelix:BAAANQAFFAIIAwAAAA==.Skunkpaw:BAAANQADCgUIBQAAAA==.Skysong:BAAANQAECgcICwAAAA==.',
Sl='Slashedeye:BAAANQAECgQICAAAAA==.Slimgucci:BAAANQADCggICAAAAA==.',
Sn='Snowynn:BAAANQAECgEIAQAAAA==.Snubby:BAAANQAECgIIAgAAAA==.',
So='Sonari:BAAANQADCgYIBgAAAA==.',
Sp='Spankz:BAAANQADCgYIBgAAAA==.',
St='Strathz:BAAANQAECgEIAQAAAA==.Strongish:BAAANQADCgUIBQAAAA==.',
Su='Sushi:BAAANQADCgIIAgAAAA==.Suva:BAAANQADCgYIBgAAAA==.',
Sy='Sylatis:BAAANQAECgYIDAABNQAFFAMIAwABAAAAAA==.Sylätis:BAAANQADCggICAABNQAFFAMIAwABAAAAAA==.',
['Sö']='Söultender:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.',
Ta='Talys:BAAANQAECggIDgAAAA==.Tankly:BAAANQADCgMIAwAAAA==.',
Te='Texicola:BAAANQAECgQIBAAAAA==.',
Th='Thabk:BAAANQADCgYIBgAAAA==.Thesyra:BAAANQAECgEIAQAAAA==.Thurmond:BAAANQADCgYIDAAAAA==.Thurmund:BAAANQADCgYIBgABNQADCgYIDAABAAAAAA==.',
Ti='Tidalanxiety:BAAANQADCggICAAAAA==.',
To='Toastz:BAAANQAECgQIBAAAAA==.Toebeanz:BAAANQAECgIIAgAAAA==.Tokken:BAAANQAECggIDgAAAA==.',
Tr='Treebeast:BAAANQAFFAEIAQAAAA==.Trojen:BAAANQAECgQIBQAAAA==.Trolladin:BAAANQADCgQIBAABNQADCgUIBgABAAAAAA==.',
Tw='Twig:BAAANQAECgEIAQAAAA==.',
['Tâ']='Tâz:BAAANQAECgQIBAAAAA==.',
Ul='Ulanda:BAAANQADCgcIGAAAAA==.',
Um='Umasi:BAAANQAECggIDgAAAA==.',
Un='Underbogg:BAAANQADCgUIBQAAAA==.',
Va='Vanthil:BAAANQADCgUIBgAAAA==.',
Ve='Venandi:BAAANQAECgEIAQAAAA==.Vengened:BAAANQADCgYICwAAAA==.Verax:BAAANQAECgIIAgAAAA==.',
Vg='Vgly:BAAANQAECgMIAwAAAA==.',
Vi='Vilous:BAAANQAECgIIAgAAAA==.',
Vr='Vraax:BAAANQADCgcIBwABNQAECgYICwABAAAAAA==.',
Vy='Vyisesham:BAAANQAECgIIAgAAAA==.',
['Vý']='Výce:BAAANQAECgEIAQAAAA==.',
Wa='Wagtar:BAAANQABCgQIBgABNQABCgQIBAABAAAAAA==.Warzug:BAAANQADCgQIBAAAAA==.',
We='Wesjin:BAAANQAECgEIAQAAAA==.Wez:BAAANQADCgcIBwAAAA==.',
Wh='Whiskee:BAAANQAECgMIBAAAAA==.',
Wo='Wooglone:BAAANQADCgUICQAAAA==.',
Wy='Wyndia:BAAANQADCgcICgAAAA==.',
Xa='Xanthos:BAAANQADCgUIBgAAAA==.',
Xe='Xenophontes:BAAANQAECgcICwAAAA==.',
Xi='Xihuang:BAAANQAECgQIBAABNQAECgQIBgABAAAAAA==.Xiia:BAAANQADCggICwAAAA==.',
Xx='Xxuublue:BAAANQAECggIBQAAAA==.',
Ya='Yaoguai:BAAANQAECgMIAwAAAA==.Yawgmoth:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.',
Za='Zaleris:BAAANQAECgEIAQAAAA==.',
Zo='Zotiel:BAAANQADCgEIAgABNQAECggIDwABAAAAAA==.',
Zy='Zynisch:BAAANQADCgcIDQAAAA==.',
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
