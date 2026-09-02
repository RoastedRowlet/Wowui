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
local provider = {region='US',realm='Goldrinn',name='US',type='weekly',zone=53,date='2026-09-01',data={Ab='Abacatte:BAAANQADCgQIBAAAAA==.',
Ae='Aelthor:BAAANQADCgYICwAAAA==.',
Al='Aleriastorm:BAAANQABCgIIAgAAAA==.Alessaxd:BAAANQADCgYICgAAAA==.Alfajhor:BAAANQADCggIDQAAAA==.Alladryel:BAAANQADCgYIBgAAAA==.Alleriane:BAAANQAECgMIAwAAAA==.Allone:BAAANQADCgUIBgAAAA==.Allunt:BAAANQADCgYIEQAAAA==.',
Am='Ametnys:BAAANQADCgUIBwAAAA==.',
An='Anakata:BAAANQADCgIIAgAAAA==.Andaliz:BAAANQAECgQIBQAAAA==.',
Ar='Arctorius:BAAANQADCgYICwAAAA==.Aronys:BAAANQADCggIDQAAAA==.Arthashand:BAAANQADCgEIAQAAAA==.Artronis:BAAANQAECgEIAQAAAA==.Arukäi:BAAANQADCgcICwAAAA==.',
At='Atriuz:BAAANQAECgMIAwAAAA==.',
['Aÿ']='Aÿ:BAAANQADCgEIAQAAAA==.',
Ba='Balk:BAAANQAECgMIAwAAAA==.Bambur:BAAANQADCgIIAgAAAA==.Barbabruto:BAAANQADCggIDgAAAA==.Barbasanta:BAAANQABCgMIAwABNQADCggIDgABAAAAAA==.',
Bi='Bigbag:BAAANQADCgMIAwAAAA==.Biønic:BAAANQADCgYIBgAAAA==.',
Bl='Blu:BAEANQAECgEIAQABNQAECgQIBAABAAAAAA==.',
Bo='Box:BAAANQADCgIIAgAAAA==.',
Bu='Buzzumaaky:BAAANQADCgMIAwAAAA==.',
Ca='Callstorm:BAAANQABCgIIAgAAAA==.Calteryeker:BAAANQADCgUIBQAAAA==.Capyvara:BAAANQABCgQIBQAAAA==.Caralh:BAAANQAECgQIBgAAAA==.Caçaorda:BAAANQADCgYIDAAAAA==.',
Ce='Cecilith:BAAANQADCgQIBQAAAA==.Cernûnnos:BAAANQAECgEIAQAAAA==.',
Ch='Champdude:BAAANQADCggIDgAAAA==.Chopquatro:BAAANQADCggICAAAAA==.',
Co='Cowzeroth:BAAANQADCgQIBAAAAA==.',
Cr='Cristcalad:BAAANQADCgYICwAAAA==.',
Da='Daemi:BAAANQADCgYIBgAAAA==.Dariok:BAAANQADCggIDAAAAA==.Darkove:BAAANQAECgIIAgAAAA==.Darrow:BAAANQAECgEIAQAAAA==.Day:BAAANQADCgYIBgAAAA==.',
De='Deathinhu:BAAANQAECgIIAgAAAA==.Dethroned:BAAANQAECgEIAQAAAA==.',
Di='Dimeros:BAAANQADCggICwAAAA==.Divano:BAAANQAECgEIAQAAAA==.',
Do='Dogowner:BAAANQADCgcICAAAAA==.Donora:BAAANQADCggIDgAAAA==.',
Dr='Dragonstyle:BAAANQAECgMIAwAAAA==.Dragony:BAAANQABCgIIAgAAAA==.',
Ei='Eirin:BAAANQADCgYICAAAAA==.',
El='Eldris:BAAANQADCgEIAQAAAA==.Elidibus:BAAANQADCgQIBAAAAA==.Ellvarg:BAAANQADCgYIDAAAAA==.',
En='Enkrenco:BAAANQADCgQIBAAAAA==.',
Er='Ernest:BAAANQADCggIDgAAAA==.Erulan:BAAANQADCgQIBAAAAA==.',
Es='Estgan:BAAANQADCgMIAwAAAA==.',
Et='Ether:BAAANQAECgQIBAAAAA==.',
Ev='Evilbarba:BAAANQAECgEIAQAAAA==.',
Ex='Exort:BAAANQAECgMIAwAAAA==.',
Fa='Faranir:BAAANQADCggICAAAAA==.Faris:BAAANQAECgIIAgAAAA==.Faver:BAAANQADCgMIAwAAAA==.Faölin:BAAANQADCgYIDAAAAA==.',
Fe='Ferael:BAAANQAECgIIAgAAAA==.',
Fl='Flavors:BAAANQADCgcIDQAAAA==.Florbela:BAAANQADCgcIDAAAAA==.',
Fr='Fredericc:BAAANQADCgYICwAAAA==.Freyá:BAAANQADCggIDgAAAA==.Frostburn:BAAANQADCgYICwAAAA==.',
Ga='Gadodamorena:BAAANQADCgIIAgAAAA==.Galfur:BAAANQAECgQICQAAAA==.',
Gr='Grumax:BAAANQAECgIIAgAAAA==.',
Gu='Gudeath:BAAANQAECgQIBAAAAA==.Gussg:BAAANQADCgcIDgAAAA==.',
['Gö']='Göhan:BAAANQAECgEIAQAAAA==.',
['Gü']='Güttz:BAAANQAECgQIBAAAAA==.',
Ha='Hanaluna:BAAANQADCgYIBgAAAA==.Hazell:BAAANQADCgMIBQAAAA==.',
He='Hellspont:BAAANQADCgUICAAAAA==.',
Ho='Hotmojo:BAAANQAECgQIBAAAAA==.',
Hu='Hunfox:BAAANQAECgQIBwAAAA==.',
['Hö']='Hölycrüsh:BAAANQAECgQIBQAAAA==.',
Ik='Ikoo:BAAANQADCggIDQAAAA==.',
Il='Illaril:BAAANQAECgcIDQAAAA==.',
In='Invisiblelol:BAAANQAECgQIBQAAAA==.',
Is='Ishtarie:BAAANQADCgYICwAAAA==.',
Iv='Ivina:BAAANQAECgYIDAAAAA==.',
Jh='Jhonatinha:BAAANQAECgUICAAAAA==.',
Jk='Jks:BAAANQADCgYIBgAAAA==.',
Ju='Jullianxd:BAAANQADCgYIDAAAAA==.',
Ka='Kaallew:BAAANQADCgYICwAAAA==.Kaelonidas:BAAANQAECgQIBAAAAA==.Kalazshar:BAAANQADCggIDgAAAA==.Kalduran:BAAANQADCggIFAAAAA==.Kaluss:BAAANQAECgIIAgAAAA==.Kantaa:BAAANQADCggICAAAAA==.Kauss:BAAANQADCgUIBwAAAA==.Kavartu:BAAANQAECgUIBwAAAA==.Kayli:BAAANQADCgUIBQAAAA==.',
Ke='Keillor:BAAANQADCgYIDwAAAA==.Kenzou:BAAANQADCgYICgAAAA==.Keytymari:BAAANQADCgIIAgAAAA==.',
Kh='Khaliq:BAAANQADCgcICwAAAA==.Khallani:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.',
Ki='Kissme:BAAANQADCgcICgAAAA==.Kitamor:BAAANQAECgIIAgAAAA==.',
Ko='Kosmo:BAAANQADCgYIBwAAAA==.',
Kr='Kräsus:BAAANQADCgQIBAABNQADCggICgABAAAAAA==.',
La='La:BAAANQADCgYIBgAAAA==.Laetus:BAAANQADCgcICwAAAA==.Laiander:BAAANQADCgUICQAAAA==.Laiany:BAAANQAECgIIAgAAAA==.',
Le='Leetohro:BAAANQADCgQIBQAAAA==.Leodoros:BAAANQADCgMIAwAAAA==.',
Li='Lighty:BAAANQADCgQICAAAAA==.Lijiang:BAAANQADCggICgAAAA==.Lindaah:BAAANQADCggIDgAAAA==.Lindapriesty:BAAANQADCgEIAQAAAA==.Lislfox:BAAANQADCggIDgAAAA==.',
Lo='Lockdown:BAAANQAECgMIBAAAAA==.Loukou:BAAANQADCgQIBAAAAA==.',
Lu='Luacs:BAAANQADCgUIBgAAAA==.Lucileia:BAAANQADCgYIBgAAAA==.Luhhrogue:BAAANQADCgYIBgAAAA==.Lunirah:BAAANQADCgYICAAAAA==.',
Ly='Lylka:BAAANQADCggIDgAAAA==.',
['Lé']='Léofar:BAAANQADCgUIBQAAAA==.',
Ma='Maeghann:BAAANQADCgQIAwAAAA==.Magostosaa:BAAANQABCgIIAgAAAA==.Makani:BAAANQADCgMIBQAAAA==.Malewolyyc:BAAANQAECgQIBAAAAA==.Massafera:BAAANQADCgcIDAAAAA==.Mathfacbruxo:BAAANQADCgYIBgABNQADCggICAABAAAAAA==.Mathfacii:BAAANQADCggICAAAAA==.Mayanyy:BAAANQAECgEIAQAAAA==.',
Md='Mdrdark:BAAANQAECgMIBAAAAA==.',
Me='Medz:BAAANQADCgcIDAAAAA==.Meetjack:BAAANQADCgUICQAAAA==.Mellkor:BAAANQADCgYICgAAAA==.Metamorful:BAAANQAECgQIBQAAAA==.',
Mi='Milim:BAAANQADCgcICAAAAA==.',
Mo='Modes:BAAANQADCgcIDAAAAA==.Mohotok:BAAANQADCgcIDQAAAA==.Mortixxia:BAAANQADCgYICgAAAA==.',
Mu='Murano:BAAANQAECgIIAgAAAA==.',
['Mä']='Mändosz:BAAANQADCgcIDAAAAA==.',
['Mø']='Mørgane:BAAANQADCgUIBQAAAA==.',
Na='Nagts:BAAANQADCgIIAgAAAA==.Nalathiel:BAAANQADCgYICAAAAA==.Narrih:BAAANQAECgIIAgAAAA==.',
Ne='Nefas:BAAANQADCggIDAAAAA==.Nepthunus:BAAANQADCggICgAAAA==.',
Od='Odestruidor:BAAANQADCgIIAgAAAA==.',
Ol='Oluss:BAAANQAECgQIBQABNQAECgQIBwABAAAAAA==.',
Op='Opus:BAAANQADCgYIBgAAAA==.Opusbergen:BAAANQADCgQIBAAAAA==.',
Or='Orsonn:BAAANQABCgEIAQAAAA==.Orukam:BAAANQADCggIDgAAAA==.Orulord:BAAANQABCgIIAgAAAA==.',
Pa='Palatina:BAAANQAECgMIBAABNQAECgQIBQABAAAAAA==.Pangedrey:BAAANQADCggIDwAAAA==.Parký:BAAANQADCgQIBAAAAA==.',
Pe='Peruchi:BAAANQADCgIIAgAAAA==.',
Pi='Picu:BAAANQADCgUICQAAAA==.Pixiks:BAAANQABCgQIBQAAAA==.',
Py='Pyrix:BAAANQADCgIIAgAAAA==.',
['Pî']='Pîo:BAAANQAECgUIAwAAAA==.',
Qu='Quirow:BAAANQADCgYIBgAAAA==.',
Ra='Radiação:BAAANQADCgUIBgAAAA==.Radunz:BAAANQADCggIDgAAAA==.Ragnaros:BAAANQAECgEIAQAAAA==.Raio:BAAANQAECgEIAQAAAA==.Raymain:BAAANQAECgQIBwAAAA==.Raíka:BAAANQADCgYICwAAAA==.',
Ru='Rubian:BAAANQADCgYIDAAAAA==.Rustovick:BAAANQADCgUIBwAAAA==.',
['Rå']='Råy:BAAANQAECgIIAgAAAA==.',
Sa='Saffír:BAAANQADCgYICgAAAA==.Saniest:BAAANQADCggIDQAAAA==.Sapekinhä:BAAANQADCggIDgAAAA==.',
Se='Sereiaa:BAAANQADCgYICgAAAA==.',
Sh='Sharae:BAAANQADCgcICAAAAA==.Shedo:BAAANQADCgEIAQAAAA==.Shonja:BAAANQADCgEIAQAAAA==.',
Si='Sialeeds:BAAANQADCgMIAwAAAA==.Sinton:BAAANQABCgIIAgAAAA==.',
Sk='Skadryan:BAAANQADCgYIBgAAAA==.Skysoul:BAAANQADCgQIBgAAAA==.',
So='Soju:BAAANQADCgIIAgAAAA==.Sombrea:BAAANQADCgEIAQAAAA==.',
St='Starkz:BAAANQADCgUIBQAAAA==.Stëlla:BAAANQADCggIDAAAAA==.',
Su='Suckmyhammer:BAAANQADCgUICAAAAA==.Sunnara:BAAANQAECgIIAgAAAA==.',
Ta='Talandar:BAAANQAECgIIAgAAAA==.Tankudo:BAAANQAECgIIAgAAAA==.',
Th='Thabitah:BAAANQADCggIDgAAAA==.Thanathus:BAAANQADCgQIBAAAAA==.',
Ti='Tiih:BAAANQABCgQIBAAAAA==.',
Us='Usfull:BAAANQADCggIDgAAAA==.',
Va='Vallkÿria:BAAANQADCgEIAQAAAA==.',
Ve='Vehuiáh:BAAANQADCgYIBgAAAA==.Velen:BAAANQAECgEIAQAAAA==.Verzuk:BAAANQADCgYICgAAAA==.',
Vi='Vintekilo:BAAANQAECgIIAgAAAA==.',
Vo='Voiddh:BAAANQAECggICAAAAA==.',
Vr='Vrenshrrgn:BAAANQADCggIDgAAAA==.',
Vy='Vygh:BAAANQADCggIDgAAAA==.Vyndrill:BAAANQADCggIDQAAAA==.',
Wa='Walkers:BAAANQADCgYIDAAAAA==.Warlaka:BAAANQADCgIIAgAAAA==.',
We='Weevil:BAAANQADCgYICgAAAA==.',
Yi='Yingsu:BAAANQADCgYICQAAAA==.Yippwarr:BAAANQADCgEIAQAAAA==.',
Yv='Yvin:BAAANQADCgUIBAAAAA==.',
Za='Zaolron:BAAANQADCgIIAQAAAA==.',
Ze='Zeddshm:BAAANQADCgQIBAAAAA==.Zeeno:BAAANQADCgEIAQAAAA==.',
Zi='Ziracruz:BAAANQAECgMIAwAAAA==.',
['Ár']='Árÿä:BAAANQADCggIDQAAAA==.',
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
