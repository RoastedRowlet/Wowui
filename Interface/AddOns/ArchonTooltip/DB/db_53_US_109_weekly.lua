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

local lookup = {'Priest-Shadow','Unknown-Unknown','DemonHunter-Vengeance',}
local provider = {region='US',realm='Goldrinn',name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Abaca:BAAANQADCgYIBgAAAA==.Abacatte:BAAANQADCggIDAAAAA==.',
Ad='Adelaide:BAAANQADCgEIAQABNQAECgkJGgABAOYeAA==.',
Ae='Aelthor:BAAANQADCgYIEwAAAA==.',
Ai='Aioliavictus:BAAANQADCgUIBQAAAA==.',
Al='Aleriastorm:BAAANQABCgIIAgAAAA==.Alessaxd:BAAANQADCgYIDgAAAA==.Alfajhor:BAAANQAECgMIAwAAAA==.Alfajhòr:BAAANQADCgUIBQAAAA==.Alladryel:BAAANQADCgYIBgAAAA==.Alleriane:BAAANQAECgMIBgAAAA==.Allone:BAAANQAECgQIBQAAAA==.Allunt:BAAANQADCgYIHQAAAA==.',
Am='Ametnys:BAAANQAECgEIAQAAAA==.',
An='Anakata:BAAANQADCgYICAAAAA==.Andaliz:BAAANQAECgUICgAAAA==.Antonel:BAAANQABCgYIBgAAAA==.',
Ar='Arctorius:BAAANQADCgYIEQAAAA==.Aronys:BAAANQADCggIDQAAAA==.Arthashand:BAAANQADCgEIAQAAAA==.Artronis:BAAANQAECgQIBQAAAA==.Arukäi:BAAANQAECgEIAQAAAA==.',
At='Atriuz:BAAANQAECgQIBwAAAA==.',
['Aÿ']='Aÿ:BAAANQADCgcICAAAAA==.',
Ba='Balk:BAAANQAECgUICQAAAA==.Bambur:BAAANQADCgIIAgAAAA==.Barbabruto:BAAANQAECgQIBAAAAA==.Barbasanta:BAAANQABCgMIAwABNQAECgQIBAACAAAAAA==.',
Bi='Bigbag:BAAANQADCgQIBQAAAA==.Biønic:BAAANQAECgEIAQAAAA==.',
Bl='Blackmoonx:BAAANQADCgYIBgAAAA==.Blu:BAEANQAECgEIAQABNQAECgQIBQACAAAAAA==.',
Bo='Box:BAAANQADCgMIAwAAAA==.',
Bu='Buzzumaaky:BAAANQAECgEIAQAAAA==.',
['Bá']='Bávor:BAAANQADCgEIAQAAAA==.',
Ca='Callstorm:BAAANQABCgIIAgAAAA==.Calteryeker:BAAANQADCgYICwAAAA==.Capyvara:BAAANQABCgQIBQAAAA==.Caralh:BAAANQAECgYIDAAAAA==.Caçaorda:BAAANQAECgIIAgAAAA==.',
Ce='Cecilith:BAAANQAECgYIBgAAAA==.Cernûnnos:BAAANQAECgEIAgAAAA==.',
Ch='Champdude:BAAANQAECgMIAwAAAA==.Chopquatro:BAAANQADCggICAAAAA==.',
Co='Cowzeroth:BAAANQAECgQIBAAAAA==.',
Cr='Cristcalad:BAAANQADCggIEwAAAA==.',
Cu='Cutiesissy:BAAANQADCgUIBQABNQAECgIIAgACAAAAAA==.',
Da='Daemi:BAAANQAECgUIBQAAAA==.Dariok:BAAANQADCggIEwAAAA==.Darkove:BAAANQAECgQIBgAAAA==.Darkpaladinx:BAAANQADCggICAAAAA==.Darrow:BAAANQAECgQIBQAAAA==.Day:BAAANQADCgYIBgAAAA==.',
De='Deathinhu:BAAANQAECgQIBgAAAA==.Dethroned:BAAANQAECgEIAgAAAA==.',
Di='Dimeros:BAAANQAECgEIAQAAAA==.Divano:BAAANQAECgMIBgAAAA==.',
Dk='Dkats:BAAANQADCgQIBAAAAA==.Dkhalifa:BAAANQADCgYIBgAAAA==.',
Do='Dogowner:BAAANQADCgcICAAAAA==.Donora:BAAANQADCggIDgAAAA==.Dorfillaw:BAAANQAECgUIBQAAAA==.',
Dr='Dragonstyle:BAAANQAECgcICgAAAA==.Dragony:BAAANQABCgIIBQAAAA==.Drexus:BAAANQADCgIIAgAAAA==.Drigolas:BAAANQADCgYIBgAAAA==.',
Ei='Eirin:BAAANQAECgMIAwAAAA==.',
El='Eldris:BAAANQADCgEIAQAAAA==.Elidibus:BAAANQADCgQIBAAAAA==.Ellvarg:BAAANQADCgYIDAAAAA==.',
En='Enkrenco:BAAANQADCgQIBAAAAA==.Ensabanú:BAAANQADCgQIBAAAAA==.',
Er='Erilaethaen:BAAANQAECgIIAgAAAA==.Ernest:BAAANQAECgMIAwAAAA==.Erulan:BAAANQADCgQIBwAAAA==.',
Es='Estgan:BAAANQADCgMIAwAAAA==.',
Et='Ether:BAAANQAECgQIBgAAAA==.',
Ev='Evangelouco:BAAANQADCgQIBAAAAA==.Evilbarba:BAAANQAECgIIAwAAAA==.',
Ex='Exort:BAAANQAECgQIBwAAAA==.Exothus:BAAANQADCgYIBgAAAA==.',
Fa='Faranir:BAAANQADCggIEAAAAA==.Faris:BAAANQAECgUIBwAAAA==.Faver:BAAANQADCgMIAwAAAA==.Faölin:BAAANQAECgQIBwAAAA==.',
Fe='Ferael:BAAANQAECgQIBgAAAA==.',
Fl='Flavors:BAAANQAECgEIAQAAAA==.Florbela:BAAANQAECgEIAQAAAA==.',
Fr='Fredericc:BAAANQADCgYICwAAAA==.Freyá:BAAANQAECgQIBAAAAA==.Frostburn:BAAANQAECgEIAQAAAA==.Froststriker:BAAANQAECgEIAQAAAA==.',
Ga='Gadodamorena:BAAANQADCggICQAAAA==.Galfur:BAAANQAECgQICwAAAA==.Galica:BAAANQABCgQIAgAAAA==.',
Ge='Geisty:BAAANQAECgEIAQABNQAECgIIBAACAAAAAA==.',
Gr='Grumax:BAAANQAECgQICAAAAA==.',
Gu='Gudeath:BAAANQAECgYICwAAAA==.Gulek:BAAANQADCgUIBQAAAA==.Gussg:BAAANQAECgEIAQAAAA==.',
['Gö']='Göhan:BAAANQAECgEIAQAAAA==.',
['Gü']='Güttz:BAAANQAECgYICgAAAA==.',
Ha='Hanaluna:BAAANQADCggICAAAAA==.Hargarthul:BAAANQADCgIIAgAAAA==.Hazell:BAAANQADCggIDQAAAA==.',
He='Hellspont:BAAANQAECgEIAQAAAA==.',
Ho='Hotmojo:BAAANQAECgcIDAAAAA==.',
Hu='Hunfox:BAAANQAECgYIDAAAAA==.',
['Hö']='Hölycrüsh:BAAANQAECgUICQAAAA==.',
Ik='Ikoo:BAAANQAECgMIAwAAAA==.',
Il='Illaril:BAABNQAECoEYAAIDAAkJNBOlAgAwAgADAAkJNBOlAgAwAgAAAA==.',
In='Interestelar:BAAANQADCgYIBgAAAA==.Invisiblelol:BAAANQAECgQIBgAAAA==.',
Is='Isenhearth:BAAANQABCgUIBQAAAA==.Ishtarie:BAAANQAECgEIAQAAAA==.',
Iv='Ivina:BAAANQAECgcIEwAAAA==.',
Ja='Jangeoffry:BAAANQABCgMIAwAAAA==.',
Jh='Jhonatinha:BAAANQAECgUICAAAAA==.',
Jk='Jks:BAAANQADCgYIBgAAAA==.',
Ju='Jullianxd:BAAANQADCggIFAAAAA==.',
Ka='Kaallew:BAAANQAECgEIAQAAAA==.Kaelonidas:BAAANQAECgQIBwAAAA==.Kainer:BAAANQADCgYIBgAAAA==.Kalazshar:BAAANQAECgMIAwAAAA==.Kalduran:BAAANQADCggIHQAAAA==.Kaluss:BAAANQAECgMIBQAAAA==.Kantaa:BAAANQADCggIEAAAAA==.Kauss:BAAANQADCgYIDQAAAA==.Kavartu:BAAANQAECgYIDQAAAA==.Kayli:BAAANQADCgUIBQAAAA==.',
Ke='Keillor:BAAANQAECgIIAgAAAA==.Kenzou:BAAANQADCgcICwAAAA==.Keytymari:BAAANQAECgEIAQAAAA==.',
Kh='Khaliq:BAAANQAECgEIAQAAAA==.Khallani:BAAANQADCgIIAgABNQAECgIIBAACAAAAAA==.',
Ki='Kissme:BAAANQAECgQIBAAAAA==.Kitamor:BAAANQAECgQIBgAAAA==.',
Ko='Koriakin:BAAANQADCgQIBAAAAA==.Kosmo:BAAANQADCgYIDQAAAA==.',
Kr='Krosmu:BAAANQABCgEIAQAAAA==.Kräsus:BAAANQADCgQIBAABNQAECgMIAwACAAAAAA==.',
La='La:BAAANQADCgYIBgAAAA==.Ladyrichter:BAAANQABCgUIBgAAAA==.Laetus:BAAANQAECgIIAgAAAA==.Laiander:BAAANQAECgEIAQAAAA==.Laiany:BAAANQAECgQIBgAAAA==.',
Le='Leetohro:BAAANQADCgcIDAAAAA==.Leodoros:BAAANQADCgcIDQAAAA==.',
Li='Lighty:BAAANQADCgQICAAAAA==.Lijiang:BAAANQAECgMIAwAAAA==.Lindaah:BAAANQADCggIFgAAAA==.Lindapriesty:BAAANQADCgIIAgAAAA==.Lislfox:BAAANQAECgIIAgAAAA==.',
Lo='Lockdown:BAAANQAECgUICQAAAA==.Loukou:BAAANQADCgQICAAAAA==.',
Lu='Luacs:BAAANQADCgYICwAAAA==.Lucileia:BAAANQADCgcIBwAAAA==.Lucyfary:BAAANQADCgcICAAAAA==.Luhhrogue:BAAANQADCgYIBgAAAA==.Lunirah:BAAANQADCgYICAAAAA==.Luxwind:BAAANQABCgIIAgAAAA==.',
Ly='Lylka:BAAANQAECgMIAwAAAA==.',
['Lé']='Léofar:BAAANQAECgEIAQAAAA==.',
Ma='Maanu:BAAANQADCgUIBQABNQADCggIFgACAAAAAA==.Maeghann:BAAANQADCgQIAwAAAA==.Magostosaa:BAAANQABCgIIAgAAAA==.Makani:BAAANQAECgEIAgAAAA==.Malewolyyc:BAAANQAECgYICgAAAA==.Massafera:BAAANQAECgEIAQAAAA==.Mathfacbruxo:BAAANQADCgYIBgABNQAECgEIAQACAAAAAA==.Mathfacii:BAAANQAECgEIAQAAAA==.Mayanyy:BAAANQAECgEIAQAAAA==.',
Md='Mdrdark:BAAANQAECgYICgAAAA==.',
Me='Medz:BAAANQAECgEIAQAAAA==.Meetjack:BAAANQADCgUICQAAAA==.Meizu:BAAANQAECgQIBAAAAA==.Mellkor:BAAANQAECgEIAQAAAA==.Metamorful:BAAANQAECgQIBwAAAA==.',
Mi='Milim:BAAANQADCgcICAAAAA==.Mistogunn:BAAANQADCggICAAAAA==.',
Mo='Modes:BAAANQAECgEIAQAAAA==.Moffir:BAAANQADCgYIBgAAAA==.Mogrus:BAAANQADCgUIAgAAAA==.Mohotok:BAAANQAECgIIAgAAAA==.Mortixxia:BAAANQADCgcIEQAAAA==.',
Mu='Murano:BAAANQAECgYICAAAAA==.',
['Má']='Máia:BAAANQAECgIIAgAAAA==.',
['Mä']='Mändosz:BAAANQADCgcIEwAAAA==.',
['Mø']='Mørgane:BAAANQADCggIDQAAAA==.',
['Mÿ']='Mÿstyna:BAAANQADCgUIBQAAAA==.',
Na='Nagts:BAAANQADCggICgAAAA==.Nalathiel:BAAANQAECgEIAQAAAA==.Narrih:BAAANQAECgIIBAAAAA==.',
Ne='Nefas:BAAANQAECgQIBAAAAA==.Nepthunus:BAAANQAECgMIAwAAAA==.',
No='Notforall:BAAANQADCgIIAgAAAA==.',
Od='Odestruidor:BAAANQAECgEIAQAAAA==.',
Ol='Oluss:BAAANQAECgYICwABNQAECgYIDAACAAAAAA==.',
Op='Opus:BAAANQAECgEIAQAAAA==.Opusbergen:BAAANQADCgQIBAAAAA==.',
Or='Orillan:BAAANQAECgMIAwAAAA==.Orsonn:BAAANQADCgEIAQAAAA==.Orucão:BAAANQABCgEIAQAAAA==.Orukam:BAAANQAECgEIAQAAAA==.Orukanorum:BAAANQADCgQIAgAAAA==.Orukrente:BAAANQABCgIIAgAAAA==.Orulord:BAAANQABCgIIAwAAAA==.Orurage:BAAANQABCgIIAgAAAA==.',
Pa='Palatina:BAAANQAECgMICAABNQAECgUICgACAAAAAA==.Pangedrey:BAAANQAECgQIBAAAAA==.Parký:BAAANQADCgYIBwAAAA==.',
Pe='Penseur:BAAANQABCgYIBgAAAA==.Peruchi:BAAANQADCgIIAgAAAA==.',
Pi='Picu:BAAANQADCgUICQAAAA==.Pitombinha:BAAANQADCgYIBgAAAA==.Pixiks:BAAANQABCgQIBQAAAA==.',
Py='Pyrix:BAAANQADCgIIAgAAAA==.',
['Pî']='Pîo:BAAANQAECgcICQAAAA==.',
Qu='Quirow:BAAANQAECgQIBAAAAA==.',
Ra='Radiação:BAAANQADCgUIBgAAAA==.Radunz:BAAANQAECgMIAwAAAA==.Ragnaros:BAAANQAECgQIBQAAAA==.Ragnarøk:BAAANQABCgYIBgAAAA==.Raio:BAAANQAECgQIBQAAAA==.Ranruulfnarm:BAAANQABCgQICAAAAA==.Rargsa:BAAANQADCgIIAgAAAA==.Rariel:BAAANQADCggICAAAAA==.Raymain:BAAANQAECgcIDAAAAA==.Raíka:BAAANQADCgYICwAAAA==.',
Re='Rendoras:BAAANQAECgEIAQAAAA==.',
Ro='Rodbree:BAAANQAECgEIAQAAAA==.Roguinhu:BAAANQADCgEIAQAAAA==.',
Ru='Rubian:BAAANQADCgYIDAAAAA==.Rustovick:BAAANQADCgUIBwAAAA==.',
['Rå']='Råy:BAAANQAECgUIBwAAAA==.',
Sa='Saffír:BAAANQAECgEIAQAAAA==.Saniest:BAAANQAECgEIAQAAAA==.Sapekinhä:BAAANQAECgEIAQAAAA==.Satanvitória:BAAANQADCgUIBQAAAA==.',
Se='Segavaxx:BAAANQABCgIIAgAAAA==.Sereiaa:BAAANQAECgEIAQAAAA==.',
Sh='Shamate:BAAANQADCgQIAQAAAA==.Sharae:BAAANQADCggIDQAAAA==.Shedo:BAAANQAECgIIAgAAAA==.Shonja:BAAANQADCgEIAQAAAA==.',
Si='Sialeeds:BAAANQADCgMIAwAAAA==.Siclop:BAAANQADCgQIBAAAAA==.Simplicity:BAAANQADCgYIBgAAAA==.Sinton:BAAANQABCgIIAgAAAA==.',
Sk='Skadryan:BAAANQADCgYIBgAAAA==.Skinme:BAAANQADCgcIBwAAAA==.Skysoul:BAAANQAECgEIAQAAAA==.',
So='Sofiela:BAAANQABCgIIAgAAAA==.Soijiro:BAAANQADCgIIAgAAAA==.Soju:BAAANQADCgIIAgAAAA==.Sombrea:BAAANQADCgMIAwAAAA==.',
Sp='Sperber:BAAANQADCggICAAAAA==.',
St='Starkz:BAAANQADCgUIBQAAAA==.Stëlla:BAAANQADCggIFAAAAA==.',
Su='Suckmyhammer:BAAANQADCgcIEAAAAA==.Sungjinwoo:BAAANQADCggICAAAAA==.Sunnara:BAAANQAECgYICAAAAA==.',
Sy='Syuon:BAAANQAECgcIBwAAAA==.',
Ta='Talandar:BAAANQAECgQIBgAAAA==.Tankudo:BAAANQAECgQIBgAAAA==.',
Th='Thabitah:BAAANQAECgMIAwAAAA==.Thanathus:BAAANQADCgYICQAAAA==.',
Ti='Tiih:BAAANQABCgUIBQAAAA==.',
Us='Usfull:BAAANQAECgIIAgAAAA==.',
Va='Vallkÿria:BAAANQADCgcIBQAAAA==.',
Ve='Vehuiáh:BAAANQADCggIDgAAAA==.Velen:BAAANQAECgIIAwAAAA==.Verno:BAAANQADCgYICAAAAA==.Verzuk:BAAANQADCgcICwAAAA==.',
Vi='Vintekilo:BAAANQAECgIIBAAAAA==.',
Vo='Voiddh:BAAANQAECggIDwAAAA==.',
Vr='Vrenshrrgn:BAAANQADCggIFgAAAA==.',
Vy='Vygh:BAAANQAECgQIBAAAAA==.Vyndrill:BAAANQAECgMIAwAAAA==.',
Wa='Walkers:BAAANQAECgMIAwAAAA==.Warlaka:BAAANQADCgIIAgAAAA==.',
We='Weevil:BAAANQADCgYICgAAAA==.',
Xu='Xurumeloun:BAAANQADCgYIBgAAAA==.',
Ya='Yamii:BAAANQADCgQIBAAAAA==.Yasmini:BAAANQABCgEIAQAAAA==.',
Yi='Yingsu:BAAANQAECgEIAQAAAA==.Yippwarr:BAAANQADCgMIBAAAAA==.',
Yv='Yvin:BAAANQAECgIIAgAAAA==.',
['Yä']='Yäsuz:BAAANQADCgcIBwAAAA==.',
Za='Zaolron:BAAANQADCgIIAQAAAA==.',
Ze='Zeddshm:BAAANQADCgQIBAAAAA==.Zeeno:BAAANQADCgEIAQAAAA==.',
Zh='Zhynah:BAAANQADCgMIAwAAAA==.',
Zi='Ziracruz:BAAANQAECgMIBAAAAA==.',
Zu='Zulyn:BAAANQADCgEIAQAAAA==.',
['Àr']='Àrdath:BAAANQADCgYIBgAAAA==.Àrthemís:BAAANQADCgEIAQAAAA==.',
['Ár']='Árÿä:BAAANQAECgMIAwAAAA==.',
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
