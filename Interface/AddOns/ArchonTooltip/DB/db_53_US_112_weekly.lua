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

local lookup = {'Unknown-Unknown','Paladin-Holy','Warrior-Arms','Warrior-Fury',}
local provider = {region='US',realm='Greymane',name='US',type='weekly',zone=53,date='2026-09-08',data={Al='Alderan:BAAANQADCgQIBAAAAA==.Alektophobia:BAAANQADCggIDwAAAA==.',
Am='Amorina:BAAANQAECgEIAQAAAA==.',
An='Andill:BAAANQADCggICAAAAA==.Andromeda:BAAANQADCgEIAQAAAA==.Aner:BAAANQADCgEIAQAAAA==.Angellete:BAAANQAECgcIDQAAAA==.Angrygnome:BAAANQAECgQIBgAAAA==.Angélique:BAAANQADCggIDAABNQAECgcIDQABAAAAAA==.',
Ar='Arax:BAAANQADCgcIDQAAAA==.Arcamoon:BAAANQADCgEIAQAAAA==.Armâgeddon:BAAANQAECgcICQAAAA==.Arrokoth:BAAANQADCgUIBwAAAA==.Arthritas:BAAANQADCgQIBAAAAA==.',
At='Atropós:BAAANQADCgcIDQAAAA==.Attachedplag:BAAANQAECgEIAQAAAA==.',
Au='Autodrive:BAAANQADCgIIAgAAAA==.',
Az='Azmodious:BAAANQABCgIIAgAAAA==.',
Ba='Bambislayer:BAAANQADCgYIBwAAAA==.Banannana:BAAANQADCgIIAgAAAA==.Banzen:BAAANQADCgYIBgAAAA==.',
Be='Beginagain:BAAANQADCgcIDwAAAA==.Belgran:BAAANQAECgQIBgAAAA==.Berunma:BAAANQADCggIFAAAAA==.',
Bi='Bileshots:BAAANQADCgYIDAAAAA==.Biowolf:BAAANQAECgUICQAAAA==.Birdhunter:BAAANQAECgQIBAAAAA==.Bishopixixix:BAAANQABCgMIAwAAAA==.Bits:BAAANQADCgYICQAAAA==.',
Bj='Bjoren:BAAANQAECgQIBQAAAA==.',
Bo='Bootiebang:BAAANQAECgEIAQAAAA==.',
Br='Brockshot:BAAANQADCgUICQAAAA==.',
Bu='Bucknekkid:BAAANQADCgEIAQAAAA==.Buckwhild:BAAANQAECgIIAgAAAA==.',
By='Byleth:BAAANQADCgIIAgAAAA==.',
Ca='Caladbolg:BAAANQAECgQICAAAAA==.Canadaisheal:BAAANQABCgMIAwAAAA==.',
Ce='Cesàrè:BAAANQADCgcIEAAAAA==.',
Ch='Chahra:BAAANQADCgQIBQAAAA==.Chamuki:BAAANQADCgMIAwABNQAFFAEIAQABAAAAAA==.Cheesecake:BAAANQADCgMIAwABNQAECgcIDQABAAAAAA==.Chuubak:BAAANQADCggIBgAAAA==.',
Cl='Clangeddin:BAAANQADCgIIAgAAAA==.Clangedin:BAAANQADCgcICwAAAA==.',
Co='Colonidus:BAAANQADCgYIEAAAAA==.Coondic:BAAANQADCgIIAgAAAA==.Corsten:BAAANQADCgcIEAAAAA==.',
Cr='Crosis:BAAANQADCgQIBQAAAA==.',
Cu='Cute:BAAANQAECgQIDwAAAA==.',
Da='Dagby:BAAANQADCgQIBAAAAA==.Darkchronos:BAAANQADCggICwAAAA==.Darnuus:BAAANQAECgEIAQAAAA==.Datromandude:BAAANQAECgIIAgAAAA==.',
De='Deadmetalhed:BAAANQADCgIIAgAAAA==.Deathbydruid:BAAANQADCggIFQABNQAECggIAQABAAAAAA==.Deathguy:BAAANQADCgMIAwAAAA==.Deathnelf:BAAANQADCgMIAwAAAA==.Deazraelle:BAAANQADCgYIBgAAAA==.Dellin:BAAANQAECgIIAgAAAA==.Demeco:BAEANQAECgUIBwABNQAFFAQIBgACAMoXAA==.Demondots:BAAANQADCgcIDQAAAA==.Devildognutz:BAAANQADCgYIBgAAAA==.',
Di='Diminuendo:BAAANQADCgIIAwAAAA==.',
Do='Doozydruid:BAAANQAECgUIBQAAAA==.Dorozh:BAAANQADCggIDwAAAA==.',
Dr='Dragonzdemon:BAAANQADCgMIAwAAAA==.Drala:BAAANQAECgEIAQAAAA==.Dreadpally:BAAANQADCgYICgAAAA==.Druuzak:BAAANQAECgQICAAAAA==.Dryconias:BAAANQAECgcIEQAAAA==.',
Du='Duncanmcleod:BAAANQAECgEIAQAAAA==.Dunkelzhan:BAAANQAECgMIBAAAAA==.',
Dy='Dyana:BAAANQADCggIDwAAAA==.',
Dz='Dz:BAAANQAECgQIBwAAAA==.',
Ec='Ecowolf:BAAANQADCgMIAwAAAA==.',
Ed='Edlund:BAAANQAECgIIAgAAAA==.',
El='Ellenaim:BAAANQADCgQIBQAAAA==.Elvy:BAAANQAECgQIBQAAAA==.',
En='Enngin:BAAANQADCgIIAQAAAA==.Enroks:BAAANQAECgQIBgAAAA==.',
Er='Erythrina:BAAANQADCgMIBQAAAA==.',
Es='Esaelle:BAAANQADCggICAAAAA==.',
Ev='Evangelene:BAAANQADCggIGwAAAA==.',
Fa='Fabulousness:BAAANQADCgcIDQAAAA==.',
Fu='Furryriver:BAAANQADCgIIAwAAAA==.',
Ga='Gamboslice:BAAANQAECgQICAAAAA==.Garkevon:BAAANQAECgIIAgAAAA==.',
Ge='Gevul:BAAANQAECgUICgAAAA==.',
Gh='Ghuun:BAAANQAECgEIAQAAAA==.',
Gl='Glimmervoid:BAAANQADCgYICgAAAA==.',
Gr='Grandmatank:BAAANQADCgYIBgAAAA==.Greeze:BAAANQAECgEIAQAAAA==.Groinsapper:BAAANQADCgIIAgABNQADCgcIDgABAAAAAA==.',
Gu='Gumboslice:BAAANQAECgYIDQAAAA==.Gusgus:BAAANQADCgYIBwAAAA==.',
Gy='Gyroflux:BAAANQAECgMIAwAAAA==.',
Ha='Haackh:BAAANQADCgcIBwAAAA==.Habanero:BAAANQAECgIIAgAAAA==.Hadd:BAAANQADCgEIAQAAAA==.Hadrìan:BAAANQADCgYIBgAAAA==.Hadéz:BAAANQADCgYIBgAAAA==.Hark:BAAANQADCgQIBQAAAA==.Haveabubble:BAAANQADCgQIAgABNQAECgIIAgABAAAAAA==.',
He='Healvisprsly:BAAANQADCgcIDQAAAA==.Helena:BAAANQAECgIIAwAAAA==.Heliarc:BAAANQADCgQIBQAAAA==.',
Hi='Hidän:BAAANQAECgEIAQAAAA==.',
Ho='Holeyman:BAAANQADCgEIAQAAAA==.',
Hu='Huutou:BAAANQADCgYIBgAAAA==.',
Il='Illatix:BAAANQAECgQIBAAAAA==.Illustriä:BAAANQADCgQIBQAAAA==.',
In='Insidious:BAAANQADCggICwAAAA==.',
Is='Isisvane:BAAANQADCgUIBwAAAA==.',
It='Itchymage:BAAANQAECgMIAwAAAA==.',
Iv='Ivyrayne:BAAANQABCgIIAgAAAA==.',
Ja='Jakeofny:BAAANQADCgEIAQAAAA==.',
Je='Jeffsgoytoy:BAAANQAECgcIDAAAAA==.',
Ji='Jighlipuff:BAAANQADCgcIDwAAAA==.Jigs:BAAANQAECgIIAgAAAA==.Jinxy:BAAANQADCgUIFAAAAA==.',
Ju='Jug:BAAANQADCgQIBAAAAA==.Jujutanketh:BAAANQADCggICwAAAA==.',
Ka='Kafia:BAAANQADCgEIAQAAAA==.Kalamak:BAAANQABCgQIBwAAAA==.Kaldrick:BAAANQADCgYIDgAAAA==.Kanaloa:BAAANQADCgcIDQAAAA==.Karindis:BAAANQAECgQIBQAAAA==.',
Ke='Kegerator:BAAANQADCgIIAwAAAA==.Keldica:BAAANQAECgEIAQAAAA==.',
Kh='Khalinor:BAAANQADCgcIDAAAAA==.',
Ki='Kickazdin:BAAANQAECgcIDgAAAA==.Kiryie:BAAANQADCgQIBQAAAA==.Kitinna:BAAANQADCgcIBwAAAA==.',
Ko='Korraa:BAAANQAECgMIAwAAAA==.',
Kp='Kprist:BAAANQAECgEIAQAAAA==.',
Kr='Kraigen:BAAANQADCgcIDAAAAA==.',
Ku='Kunzhut:BAAANQAECgEIAQAAAA==.Kuroi:BAAANQADCgMIAwAAAA==.',
Ky='Kynasmira:BAAANQADCgQIBQAAAA==.',
La='Ladrona:BAAANQADCgcICwAAAA==.Lailyre:BAAANQADCggICAAAAA==.Laydin:BAAANQAECggIAQAAAA==.',
Lb='Lb:BAAANQABCgYIBgABNQAECgQIBQABAAAAAA==.',
Le='Legzanot:BAAANQAECggIAwAAAA==.Lestrade:BAAANQADCgcIDAABNQAECgEIAQABAAAAAA==.',
Li='Lightningfox:BAAANQADCgcIDAAAAA==.Lithia:BAAANQADCgQIBQAAAA==.Littlemo:BAAANQADCgIIAwAAAA==.',
Lo='Lohnar:BAAANQADCgIIAwAAAA==.Lorzana:BAAANQADCgcIDQAAAA==.',
Lu='Lucidslock:BAAANQADCgQIBAAAAA==.Lucielbaal:BAAANQADCggICgAAAA==.Luckystop:BAAANQAECgEIAQAAAA==.Lumenir:BAAANQADCgYIBgAAAA==.Lunareth:BAAANQADCgYIDQABNQAECgEIAQABAAAAAA==.',
Ly='Lyrska:BAAANQADCgcICgAAAA==.Lytearrow:BAAANQAECgEIAQAAAA==.',
['Lì']='Lìvíd:BAAANQAECgMIBAAAAA==.',
Ma='Mahrylee:BAAANQADCggIFAAAAA==.Majin:BAAANQAECgQIBAAAAA==.Manbearpally:BAAANQADCgYIDgAAAA==.Mannypack:BAAANQADCggIDgAAAA==.Mathagni:BAAANQADCgQIBAAAAA==.',
Mc='Mcleary:BAAANQADCgYIEAAAAA==.',
Me='Meldrus:BAAANQAECgEIAQAAAA==.Merrill:BAAANQADCgcIBwAAAA==.',
Mi='Miala:BAAANQAECgIIAgAAAA==.Mierna:BAAANQAECgIIAgAAAA==.Miler:BAAANQADCgIIAgAAAA==.Mirota:BAAANQADCgEIAQAAAA==.',
Mo='Moemo:BAAANQAECgEIAQAAAA==.Mogryn:BAAANQADCggICgAAAA==.Mommybree:BAAANQAECgIIAgAAAA==.Monotonous:BAAANQADCgUICwAAAA==.Moondog:BAAANQADCgYIBgAAAA==.Moonwarriorx:BAAANQADCgYIBgAAAA==.Morganalefey:BAAANQADCgMIBAAAAA==.Morthok:BAAANQADCgcIDQAAAA==.Mosh:BAAANQAECgEIAQAAAA==.',
['Mã']='Mãf:BAAANQADCgEIAQAAAA==.',
Na='Naelyn:BAAANQAECgIIAgAAAA==.Nafir:BAAANQADCgQIBAAAAA==.Nazgor:BAAANQADCggIDgAAAA==.',
Ne='Necrosius:BAAANQADCgEIAQAAAA==.Neolythic:BAEANQADCgQIBQAAAA==.',
Ny='Nyxstalia:BAAANQADCgUIAwAAAA==.Nyyx:BAAANQADCgcIDQAAAA==.',
Ob='Obscyra:BAAANQAECgEIAQAAAA==.',
Oc='Ochiie:BAAANQADCgYICgAAAA==.',
Od='Oddyeppyep:BAAANQADCgYIBwAAAA==.',
Ol='Olmek:BAABNQAECoEWAAMDAAgJ3xetJgBaAgADAAgJ3xetJgBaAgAEAAQJyBCDCgD3AAAAAA==.',
Oo='Oochiee:BAAANQABCgIIAgAAAA==.',
Op='Oprahwndfury:BAAANQADCggIDwABNQADCgcIDQABAAAAAA==.',
Pa='Palasades:BAAANQADCgEIAQAAAA==.Pandalorian:BAAANQAECgMIAwAAAA==.Papapumpies:BAAANQAECgcIDAAAAA==.Parlow:BAAANQADCggIEgAAAA==.Pazzo:BAAANQADCgYICQAAAA==.',
Ph='Pharaa:BAAANQADCgcIDAAAAA==.',
Pi='Picoso:BAAANQADCgcIDQAAAA==.Piianna:BAAANQAECgYICgAAAA==.Pizzaroll:BAAANQAECgIIAgAAAA==.',
Qa='Qatbarph:BAAANQADCgcICwAAAA==.',
Qi='Qikkaw:BAAANQADCgcIDAAAAA==.',
Qu='Quantos:BAAANQADCgcIDgAAAA==.',
Ra='Raatha:BAAANQAECgIIAgAAAA==.Raganar:BAAANQADCgcIDAAAAA==.Rasz:BAAANQAECgMIBgAAAA==.Rayjean:BAAANQADCgMIAwAAAA==.',
Re='Relmax:BAAANQADCggIDwAAAA==.Rennia:BAAANQADCggIBwABNQADCggICAABAAAAAA==.',
Rh='Rhonwynn:BAAANQADCgcIBwAAAA==.',
Ri='Rikershipdwn:BAAANQADCggIDwAAAA==.Rimrave:BAAANQAECgIIAgAAAA==.Ritobeans:BAAANQADCgMIAwAAAA==.',
Rk='Rk:BAAANQAECgQIBgAAAA==.',
Ro='Robertkenway:BAAANQAECgIIAgABNQAECgQIBgABAAAAAA==.Rod:BAAANQAECgQIBQAAAA==.Rokte:BAAANQADCgUIBgAAAA==.Rooke:BAAANQAECgEIAwAAAA==.Rosekenway:BAAANQAECgIIAgABNQAECgQIBgABAAAAAA==.',
Rr='Rratt:BAAANQADCgcIBwAAAA==.',
Ru='Running:BAAANQADCgEIAQAAAA==.',
['Rî']='Rîkku:BAAANQADCgEIAQAAAA==.',
Sa='Safewaybag:BAAANQADCgQIBAAAAA==.Samartyr:BAAANQADCgIIAwAAAA==.Sangwynaris:BAAANQADCggIDgAAAA==.Sanilien:BAAANQAECgEIAQAAAA==.Saphiiraa:BAAANQADCgYIBgAAAA==.Sathara:BAAANQADCgEIAQAAAA==.',
Sc='Scorpmage:BAAANQADCgcIDAAAAA==.',
Se='Sedrick:BAAANQADCggIFQAAAA==.Sekaholic:BAAANQADCgEIAQABNQADCgcIDgABAAAAAA==.Sekendipity:BAAANQADCgEIAQABNQADCgcIDgABAAAAAA==.Sekndestroy:BAAANQADCgMIAwABNQADCgcIDgABAAAAAA==.Sekthyr:BAAANQADCgcIDgAAAA==.Sekzen:BAAANQADCgUICQABNQADCgcIDgABAAAAAA==.',
Sh='Shamtune:BAAANQAECgcIDQAAAA==.Sharayman:BAAANQADCgIIAgABNQADCgMIAwABAAAAAA==.Shattered:BAAANQADCgYICQAAAA==.Shaydra:BAAANQADCggIFQAAAA==.Shazool:BAAANQAECgUIBwAAAA==.Shifterz:BAAANQADCgIIAwAAAA==.Shrubbery:BAAANQADCggIDAAAAA==.',
Si='Sindella:BAAANQADCgcIEQAAAA==.Sinna:BAAANQADCgQIBAABNQADCgYICgABAAAAAA==.',
Sk='Skedaddle:BAAANQABCgIIAQABNQADCgYIBgABAAAAAA==.',
Sl='Slashgquit:BAAANQAECgUIBgAAAA==.Slumbermist:BAAANQADCggIFQAAAA==.',
St='Strongboy:BAAANQADCgUIBwAAAA==.',
Sy='Syndar:BAAANQADCgQIBgABNQAECgEIAQABAAAAAA==.Synthetic:BAAANQADCgYIDgAAAA==.',
Sz='Szasstaam:BAAANQADCggIFAAAAA==.',
Te='Tecsaran:BAAANQADCggIEwABNQAECgEIAQABAAAAAA==.Tekis:BAAANQAECgQIBAAAAA==.Tensanio:BAAANQADCgYICwAAAA==.',
Th='Thalira:BAAANQADCgYIDAAAAA==.Thalrix:BAAANQADCgYICgAAAA==.Thebiznitch:BAAANQADCgUIBAAAAA==.Theholyboi:BAAANQAECgUIBgAAAA==.Thwackk:BAAANQAECggICQAAAA==.',
Ti='Tinkera:BAAANQADCgQIBAAAAA==.Titanosaurus:BAAANQADCgIIAwAAAA==.',
To='Torridwells:BAAANQADCgQIBQAAAA==.',
Tr='Triebryn:BAAANQABCgQIBgAAAA==.Troag:BAAANQADCgYIDgAAAA==.Troagstar:BAAANQADCgYIDgAAAA==.',
Tu='Tubbytoe:BAAANQAECgEIAQAAAA==.',
Ty='Tyraana:BAAANQAECgUIBQAAAA==.Tyrmog:BAAANQADCggIDgAAAA==.',
Un='Undetha:BAAANQADCgUIBQAAAA==.',
Us='Ushas:BAAANQAECgQIBAAAAA==.',
Va='Vali:BAAANQADCgcIDQAAAA==.Valindrea:BAAANQADCgIIAwAAAA==.',
Ve='Vel:BAAANQAECgMIAwAAAA==.Venvanse:BAAANQAECgEIAQAAAA==.Vexen:BAAANQADCggIFQAAAA==.',
Vn='Vnia:BAAANQAECgEIAQAAAA==.',
Vo='Voidmuffinz:BAAANQAECgUIBgAAAA==.',
Vy='Vynis:BAAANQAECgIIAgABNQAECgcIDQABAAAAAA==.Vyrahildard:BAAANQAECgIIAgAAAA==.',
Wa='Wakkiq:BAAANQABCgIIAgAAAA==.Wasteland:BAAANQAECggICQAAAA==.Watermelon:BAAANQAECgYICQAAAA==.',
We='Weaselhunter:BAAANQAECgIIAgABNQAECgMIBAABAAAAAA==.Weasellock:BAAANQAECgMIBAAAAA==.Weaselmage:BAAANQAECgEIAQABNQAECgMIBAABAAAAAA==.Weaselshammy:BAAANQADCgQIBAABNQAECgMIBAABAAAAAA==.',
Wi='Wildweasel:BAAANQADCgYICgABNQAECgMIBAABAAAAAA==.Winterhide:BAAANQADCgcIDQAAAA==.',
Xa='Xallie:BAEANQAECgUIBQAAAA==.Xanvyr:BAAANQADCgQICAABNQAECgQIBQABAAAAAA==.Xaquillis:BAAANQAECgUIBwAAAA==.',
Xe='Xeyvara:BAAANQAECgIIAgAAAA==.',
Za='Zarihanna:BAAANQAECgQIBwAAAA==.Zarsiia:BAAANQADCgMIBQAAAA==.',
Ze='Zernakk:BAAANQAECgIIAwAAAA==.Zestyknight:BAAANQADCgcIDQAAAA==.',
Zi='Zindeshal:BAAANQADCgQIBAAAAA==.',
Zo='Zorcunter:BAAANQAECgUICgAAAA==.',
Zu='Zulizzajabi:BAAANQAECgIIBAAAAA==.',
['Åt']='Åthenå:BAAANQADCgQIBAAAAA==.',
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
