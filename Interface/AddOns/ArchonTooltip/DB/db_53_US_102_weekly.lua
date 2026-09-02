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
local provider = {region='US',realm='Gallywix',name='US',type='weekly',zone=53,date='2026-09-01',data={Ac='Acelord:BAAANQAECgIIAgAAAA==.',
Ad='Adilma:BAAANQADCgQIBAAAAA==.Adriannos:BAAANQADCgcICQAAAA==.',
Al='Alexextreme:BAAANQADCgUIBQAAAA==.Algea:BAAANQADCgMIAwABNQADCgYIDAABAAAAAA==.Algrixx:BAAANQADCgQIBQAAAA==.Aliaksandr:BAAANQADCgIIAwAAAA==.',
An='Angelloz:BAAANQADCgUIBQAAAA==.Annia:BAAANQADCgEIAQAAAA==.Anystorm:BAAANQADCgEIAQAAAA==.',
Ap='Apökalÿpsïs:BAAANQAECgIIAgAAAA==.',
As='Asaff:BAAANQADCgMIBQAAAA==.',
Az='Azul:BAAANQADCgcICQAAAA==.Azzalyn:BAAANQADCgQIBQAAAA==.',
Be='Beelgarath:BAAANQADCgEIAQAAAA==.Belowlight:BAAANQADCgYIBgAAAA==.',
Bl='Blackteriaa:BAAANQAECgEIAQAAAA==.Blastoize:BAAANQADCgYIBgAAAA==.Bloodh:BAAANQADCgUIBgAAAA==.Bluforged:BAEANQAECgQIBAAAAA==.',
Bo='Boruck:BAAANQABCgEIAQAAAA==.',
Br='Braeon:BAAANQADCgQIBQAAAA==.Bridda:BAAANQADCgMIAwAAAA==.Brinkst:BAAANQAECgEIAQAAAA==.',
Bw='Bwozaghar:BAAANQADCgIIAgAAAA==.',
Ca='Casuall:BAAANQADCggICAAAAA==.Catalango:BAAANQADCgQIBQAAAA==.Catapinha:BAAANQADCgEIAQAAAA==.Catapó:BAAANQADCgMIAwAAAA==.',
Cl='Climps:BAAANQAECgQIBAAAAA==.',
Co='Corollaxei:BAAANQADCgIIAgAAAA==.',
Cr='Cruzade:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.Cröwllëy:BAAANQADCgUIBQAAAA==.',
Cu='Cubatao:BAAANQADCgYICgAAAA==.',
Da='Dakshayani:BAAANQADCgcIDAAAAA==.Dallion:BAAANQADCgQIBQAAAA==.Dardano:BAAANQABCgQIBgAAAA==.Darkfuntz:BAAANQAECgEIAQAAAA==.Darksiderxd:BAAANQADCgEIAQAAAA==.',
De='Deadvi:BAAANQADCgcIEQAAAA==.Derothey:BAAANQAECgIIAgAAAA==.',
Dk='Dkabeza:BAAANQADCgcIBwAAAA==.',
Dn='Dngkakuzo:BAAANQADCggIDAAAAA==.',
Do='Doomsman:BAAANQADCgMIAwAAAA==.',
Dr='Dracomamante:BAAANQAECgQIBAAAAA==.Draconoide:BAAANQADCggIEAAAAA==.Dragondrukc:BAAANQAECgEIAQAAAA==.Dreamingdrow:BAEANQAECgcIBwAAAA==.Dreykar:BAAANQADCgcICwAAAA==.Druidaezeki:BAAANQADCgUIBwAAAA==.',
Du='Duquetjb:BAAANQADCgYIBwAAAA==.',
['Dä']='Dähäkä:BAAANQADCgQIBAAAAA==.',
Ed='Edven:BAAANQAECgQIBQAAAA==.',
Ei='Eilin:BAAANQADCgIIAgAAAA==.',
El='Elbruxão:BAAANQADCgEIAQAAAA==.Eldarië:BAAANQABCgIIBAAAAA==.Elementais:BAAANQAECgIIAgAAAA==.Ellanor:BAAANQADCgYICQAAAA==.Ellocopere:BAAANQADCgQIBAAAAA==.Eltão:BAAANQADCgQIBQAAAA==.',
En='Enegadiel:BAAANQADCgYICAAAAA==.Envie:BAAANQAECgQIBQAAAA==.',
Er='Erickya:BAAANQADCgcICQAAAA==.Ervadocè:BAAANQADCgIIAgAAAA==.',
Es='Eskaris:BAAANQADCgQIBAAAAA==.',
Ev='Evely:BAAANQADCgYIDAAAAA==.',
Fi='Firexo:BAAANQADCgEIAQAAAA==.',
Fl='Flemma:BAAANQADCgMIAwAAAA==.Flexer:BAAANQABCgMIAgAAAA==.',
Fo='Fonderus:BAAANQADCgIIAgAAAA==.Foxyfox:BAAANQADCgEIAQAAAA==.',
Fr='Friodokrl:BAAANQAECgMIBAAAAA==.Frostmalt:BAAANQABCgQIBAAAAA==.',
Fu='Fubukiofhell:BAAANQAECgQIBgAAAA==.',
Ga='Gafgar:BAAANQADCgYIBgAAAA==.Gafowi:BAAANQADCggICAAAAA==.Garrincha:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.',
Ge='Gearfried:BAAANQADCgQIBAAAAA==.',
Gh='Ghopo:BAAANQADCgQIBAAAAA==.',
Gr='Grimblade:BAAANQADCgEIAQAAAA==.Grimflame:BAAANQADCgEIAQAAAA==.Grommhell:BAAANQADCgYIBgAAAA==.',
Ha='Haandir:BAAANQADCgYIBwAAAA==.',
He='Herablack:BAAANQADCgUICQAAAA==.',
Hi='Himikonee:BAAANQADCgIIAgAAAA==.',
Ho='Horstmeyer:BAAANQADCgIIAgAAAA==.',
Ib='Ib:BAAANQABCgMIAwAAAA==.',
Ig='Igthil:BAAANQADCgUIBgAAAA==.',
Ik='Ikiam:BAAANQAECgMIAgAAAA==.Ikslawok:BAAANQADCgUIBwAAAA==.',
Il='Ileria:BAAANQADCgQIBAAAAA==.Illusionarc:BAAANQADCggICwABNQAECgMIAgABAAAAAA==.',
Im='Imnotbryan:BAAANQADCgUIBQAAAA==.',
In='Incognita:BAAANQADCggICwAAAA==.',
Ir='Iramm:BAAANQAECgIIAgAAAA==.Irion:BAAANQADCgYIDQAAAA==.',
Is='Iscalio:BAAANQADCggIDwAAAA==.',
It='Itatchii:BAAANQADCgYICQAAAA==.',
Iu='Iuuh:BAAANQAECgEIAQAAAA==.',
Ja='Jackdawnsong:BAAANQADCgQICAAAAA==.Jahuun:BAAANQAECgEIAQAAAA==.',
Je='Jefflich:BAAANQADCgQIBAAAAA==.',
Jj='Jjokerr:BAAANQADCgEIAQAAAA==.',
Ju='Jubard:BAAANQADCgUIBwAAAA==.',
Ka='Kaelyrah:BAAANQADCgQIBAAAAA==.Kardibito:BAAANQADCgQIBAAAAA==.Kazuopala:BAAANQADCgIIAgAAAA==.',
Kh='Khoj:BAAANQADCggICAAAAA==.',
Kl='Kluzlocak:BAAANQADCgEIAQAAAA==.',
Ku='Kutirenzo:BAAANQADCgUICAAAAA==.',
La='Lafiel:BAAANQADCgUICgAAAA==.Lahllis:BAAANQADCgMIAwAAAA==.Lanmo:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Laurea:BAAANQAECgQIBAAAAA==.',
Le='Ledor:BAAANQADCgYIBwAAAA==.Lendarion:BAAANQADCgYIDAAAAA==.Leozadock:BAAANQADCgYICwAAAA==.',
Li='Lichtbaum:BAAANQAECgEIAQAAAA==.Liifecomm:BAAANQAECgQIBAAAAA==.Lipaodrk:BAAANQAECgcICwAAAA==.',
Lk='Lkazaktoch:BAAANQADCgQIBQAAAA==.',
Lo='Lordpain:BAAANQADCggIDgAAAA==.Lortherti:BAAANQADCgMIBAAAAA==.Louisenacioo:BAAANQADCgcICQAAAA==.',
Lu='Luccablack:BAAANQADCgEIAQAAAA==.Luccagelido:BAAANQADCgUIBQAAAA==.Luidar:BAAANQADCgIIAgAAAA==.Lukaslions:BAAANQAECgEIAQAAAA==.Luphoe:BAAANQADCgUIBQAAAA==.',
Ma='Madushi:BAAANQADCgcICAAAAA==.Madzerø:BAAANQADCgQIBgAAAA==.Magatas:BAAANQADCgQIBAAAAA==.Maguul:BAAANQADCgYIBwAAAA==.Malandrvs:BAAANQAECgYIBwAAAA==.Maldiçoadora:BAAANQAECgIIAgAAAA==.Mangudah:BAAANQADCgcIDQAAAA==.Mannaton:BAAANQADCgcIDQABNQADCgcIDQABAAAAAA==.Manzagon:BAAANQADCgcIBwABNQADCgcIDQABAAAAAA==.Maruh:BAAANQAECgIIAgAAAA==.Marúh:BAAANQAECgUIBwAAAA==.Maølayking:BAAANQAFFAEIAQAAAA==.',
Mc='Mclovingo:BAAANQADCgUIBAAAAA==.',
Me='Mendingu:BAAANQADCgcIEQAAAA==.Mercenarybr:BAAANQADCggIDgAAAA==.',
Mi='Mikasaackerr:BAAANQADCgYICAAAAA==.Milone:BAAANQADCgMIAwAAAA==.Mindlocker:BAAANQADCgQIBAAAAA==.',
Mo='Momongadk:BAAANQAECgQIBAAAAA==.Monkeydking:BAAANQADCgUIBQAAAA==.Monozoio:BAAANQADCgMIAwAAAA==.Moriyama:BAAANQADCgUICgAAAA==.Morphizs:BAAANQADCgcICwABNQADCgcIDQABAAAAAA==.Morphoss:BAAANQADCgUIBQABNQADCgcIDQABAAAAAA==.Mortesan:BAAANQADCgEIAQABNQADCgUIBgABAAAAAA==.',
['Må']='Måximus:BAAANQADCgcICAAAAA==.',
Na='Naeryndam:BAAANQADCgUIBQAAAA==.Naturezo:BAAANQAECgEIAQAAAA==.',
Ne='Necrograves:BAAANQADCgUIBwAAAA==.Negblack:BAAANQADCgUIBQAAAA==.Netherbane:BAAANQADCgMIAwAAAA==.Nezkur:BAAANQADCgMIBAAAAA==.Neürose:BAAANQADCgEIAQAAAA==.',
Oa='Oakshlar:BAAANQAECgEIAQAAAA==.',
Ot='Otton:BAAANQADCgYICgAAAA==.',
Pa='Paidesanto:BAAANQAECgEIAQAAAA==.Paladinokun:BAAANQADCgUIBgAAAA==.Pandadruid:BAAANQADCgYIBgAAAA==.',
Pe='Pedrö:BAAANQAECgEIAQAAAA==.',
Pl='Playsson:BAAANQAECgMIBAAAAA==.',
Pr='Pravios:BAAANQADCgcIBwAAAA==.',
Pu='Puherito:BAAANQADCgYIBgAAAA==.',
Ra='Ravenblak:BAAANQADCgQIBAAAAA==.',
Re='Reigeladinho:BAAANQADCgEIAQAAAA==.',
Ro='Robadoom:BAAANQABCgEIAQAAAA==.',
Ru='Ruanna:BAAANQADCgEIAQAAAA==.Runak:BAAANQADCgYIDAAAAA==.',
Sa='Safiralc:BAAANQADCgEIAQAAAA==.Salaciel:BAAANQADCgIIAgAAAA==.Sardron:BAAANQADCgEIAQAAAA==.Saydrom:BAAANQADCgYIBgAAAA==.Sayur:BAAANQADCgUIBwAAAA==.',
Sh='Shaladrasil:BAAANQADCgEIAgAAAA==.Shieldhonor:BAAANQADCgQIBAAAAA==.Shisuui:BAAANQADCgYIBgAAAA==.',
Si='Silvanna:BAAANQADCgEIAQAAAA==.Silvao:BAAANQADCgEIAQAAAA==.Sinkra:BAAANQADCgEIAQAAAA==.Sion:BAAANQADCgIIAgAAAA==.Sirgonzo:BAAANQADCgcIDAAAAA==.',
So='Sorim:BAAANQADCgYICgAAAA==.',
St='Staffkiller:BAAANQADCgMIAwAAAA==.Stx:BAAANQADCgYIBgAAAA==.',
Su='Sushhi:BAAANQADCgEIAQAAAA==.',
Sw='Swam:BAAANQAECgEIAQAAAA==.',
Ta='Tamuriano:BAAANQADCgEIAQAAAA==.Tarez:BAAANQADCgYIBwAAAA==.Tarfonir:BAAANQADCgQIBAAAAA==.',
Te='Ted:BAAANQADCggIEAAAAA==.',
Th='Thejokker:BAAANQADCgYIBgAAAA==.Themooster:BAAANQAECgIIAgAAAA==.Thepunk:BAAANQADCgcIBwAAAA==.Thormento:BAAANQADCgIIAgAAAA==.',
Ti='Tiriricao:BAAANQADCgQIBAAAAA==.Titanicos:BAAANQADCgIIAgAAAA==.',
To='Tobbiy:BAAANQAECgQIBAAAAA==.',
Tr='Trévor:BAAANQADCgIIAgAAAA==.',
['Tÿ']='Tÿriøn:BAAANQADCgYIBgAAAA==.',
Va='Valmila:BAAANQADCgYICQAAAA==.',
Ve='Velkharun:BAAANQAECgIIAgAAAA==.',
Vh='Vhaeraun:BAAANQADCgEIAQAAAA==.',
Vi='Viseryss:BAAANQADCgEIAQAAAA==.Vivifirex:BAAANQADCgEIAQAAAA==.',
Wa='Wako:BAAANQAECgQIBwAAAA==.Warlôck:BAAANQADCgYICwAAAA==.Watdafoxsay:BAAANQADCgYICQAAAA==.',
Wh='Whitersoul:BAAANQAECgQIEAAAAA==.',
Wi='Wiserys:BAAANQAECgUICQAAAA==.',
Wm='Wmarcão:BAAANQADCgUIDQAAAA==.',
Wo='Wolfnwar:BAAANQAECgMIAwAAAA==.',
Xe='Xexnew:BAAANQAECgIIAgAAAA==.',
Xm='Xmari:BAAANQAECgEIAQAAAA==.',
Xn='Xnyx:BAAANQADCgEIAQAAAA==.',
Xo='Xots:BAAANQADCgIIAgAAAA==.',
Xx='Xxcantsidex:BAAANQADCgcIDAAAAA==.',
Ya='Yangyung:BAAANQADCgUIBQAAAA==.Yannadcg:BAAANQAECgQIBQAAAA==.',
Yc='Ycantsideyx:BAAANQADCgUIBQAAAA==.',
Ym='Ymperor:BAAANQADCgQIBAAAAA==.',
Yo='Yorickundyer:BAAANQADCgMIAgAAAA==.',
Ze='Zerdrax:BAAANQADCgcICQAAAA==.',
Zi='Ziikiipala:BAAANQADCgEIAQAAAA==.',
['Ál']='Álucard:BAAANQAECgEIAQAAAA==.',
['Éy']='Éyga:BAAANQADCgUIBwAAAA==.',
['Ðw']='Ðwons:BAAANQADCgEIAQAAAA==.',
['Ök']='Ökamì:BAAANQADCgIIAgAAAA==.',
['Öx']='Öx:BAAANQADCgEIAQAAAA==.',
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
