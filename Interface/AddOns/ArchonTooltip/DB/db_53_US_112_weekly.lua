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

local lookup = {'Warrior-Arms','Unknown-Unknown','Druid-Balance','Paladin-Holy','Paladin-Retribution','Druid-Restoration','Warrior-Fury','Shaman-Restoration',}
local provider = {region='US',realm='Greymane',name='US',type='weekly',zone=53,date='2026-09-15',data={Al='Alderan:BAAANQADCgQIBAAAAA==.Alektophobia:BAAANQADCggIDwAAAA==.',
Am='Amaurra:BAAANQABCgQIBAAAAA==.Amorina:BAAANQAECgEIAQAAAA==.',
An='Andill:BAAANQADCggICQAAAA==.Andromeda:BAAANQADCgEIAQAAAA==.Aner:BAAANQADCgEIAQAAAA==.Angellete:BAABNQAECoEXAAIBAAgJ3B3bKACjAgABAAgJ3B3bKACjAgAAAA==.Angrygnome:BAAANQAECgQIBgAAAA==.Angélique:BAAANQADCggIDAABNQAECggIFwABANwdAA==.Anieros:BAAANQAECgEIAgAAAA==.',
Ar='Arax:BAAANQADCggIFQAAAA==.Arcamoon:BAAANQADCgEIAQAAAA==.Arianpali:BAAANQADCgQIBQAAAA==.Armâgeddon:BAAANQAECgcIDQAAAA==.Arrokoth:BAAANQADCgUIBwAAAA==.Arthritas:BAAANQADCgQIBAAAAA==.',
At='Atropós:BAAANQADCggIFQAAAA==.Attachedplag:BAAANQAECgEIAQAAAA==.Atulwa:BAAANQADCgMIAwAAAA==.',
Au='Autodrive:BAAANQADCgIIAgAAAA==.',
Az='Azmodious:BAAANQABCgIIAgAAAA==.',
Ba='Bambislayer:BAAANQADCgYIBwAAAA==.Banannana:BAAANQADCggICQAAAA==.Banzen:BAAANQADCggIFgAAAA==.',
Be='Beardedyeti:BAAANQABCgQIBAAAAA==.Beginagain:BAAANQADCgcIFAAAAA==.Belgran:BAAANQAECgQICgAAAA==.Berunma:BAAANQAECgIIAgAAAA==.',
Bi='Bileshots:BAAANQADCgYIDAAAAA==.Biowolf:BAAANQAECgYIDwAAAA==.Birdhunter:BAAANQAECgQIBAAAAA==.Bishopixixix:BAAANQABCgMIAwABNQADCgYIBgACAAAAAA==.Bishopxix:BAAANQADCgYIBgAAAA==.Bits:BAAANQADCgYIDwAAAA==.',
Bj='Bjoren:BAAANQAECgQICQAAAA==.',
Bo='Bootiebang:BAAANQAECgMIBAAAAA==.',
Br='Brockshot:BAAANQAECgEIAQAAAA==.',
Bu='Bucknekkid:BAAANQADCgEIAQAAAA==.Buckwhild:BAAANQAECgQIBAAAAA==.',
By='Byleth:BAAANQADCgIIAgAAAA==.',
Ca='Caladbolg:BAAANQAECgUIDQAAAA==.Canadaisheal:BAAANQABCgQIBAAAAA==.',
Ce='Cesàrè:BAAANQADCggIGAAAAA==.',
Ch='Chahra:BAAANQADCgQIBQAAAA==.Chamuki:BAAANQADCgMIAwABNQAECgkJFgADAKUZAA==.Cheesecake:BAAANQADCgMIAwABNQAECggIFwABANwdAA==.Chuubak:BAAANQADCggIBgAAAA==.',
Cl='Clangeddin:BAAANQADCgIIAgAAAA==.Clangedin:BAAANQADCgcIEQAAAA==.',
Co='Colonidus:BAAANQADCgYIFgAAAA==.Coondic:BAAANQADCgIIAgAAAA==.Corsten:BAAANQADCggIGAAAAA==.',
Cr='Crosis:BAAANQADCgQIBQAAAA==.',
Cu='Cute:BAAANQAECgYIEQAAAA==.',
Da='Dagby:BAAANQADCgUICQAAAA==.Dangerzone:BAAANQADCgUIBQAAAA==.Darkchronos:BAAANQADCggICwAAAA==.Darnuus:BAAANQAECgYIBwAAAA==.Datromandude:BAAANQAECgMIBQAAAA==.',
De='Deadmetalhed:BAAANQADCgIIAgAAAA==.Deathbydruid:BAAANQAECgMIAwABNQAECggIAQACAAAAAA==.Deathnelf:BAAANQADCgMIAwAAAA==.Deazraelle:BAAANQAECgMIAwAAAA==.Dellin:BAAANQAECgMIBAAAAA==.Demeco:BAEANQAECgUIBwABNQAFFAUICwAEALgXAA==.Demondots:BAAANQADCggIFQAAAA==.Denzalle:BAAANQADCgQIBAAAAA==.Devildognutz:BAAANQADCggIDgAAAA==.',
Di='Diminuendo:BAAANQADCggICwAAAA==.',
Do='Doozydruid:BAAANQAECgYICwAAAA==.Dorozh:BAAANQADCggIDwAAAA==.',
Dr='Draeke:BAAANQAECgEIAQAAAA==.Dragonzdemon:BAAANQADCgcICQAAAA==.Drala:BAAANQAECgMIBAAAAA==.Dreadpally:BAAANQADCgYICgABNQADCgYICgACAAAAAA==.Dreco:BAAANQAECgIIAgAAAA==.Drtydhn:BAAANQABCgMIAgAAAA==.Druuzak:BAAANQAECgQIDAAAAA==.Dryconias:BAABNQAECoEdAAIFAAkJAhhnKgBoAgAFAAkJAhhnKgBoAgAAAA==.',
Du='Duncanmcleod:BAAANQAECgEIAQABNQAECgQIBAACAAAAAA==.Dunkelzhan:BAAANQAECgMIBwAAAA==.',
Dy='Dyana:BAAANQADCggIDwAAAA==.',
Dz='Dz:BAAANQAECgYIDQAAAA==.',
Ec='Ecowolf:BAAANQADCgMIAwAAAA==.',
Ed='Edlund:BAAANQAECgIIBAAAAA==.',
El='Ellenaim:BAAANQADCgQIBQAAAA==.Elvy:BAAANQAECgYICwAAAA==.',
En='Enngin:BAAANQAECgMIAwAAAA==.Enroks:BAAANQAECgUICwAAAA==.',
Er='Erythrina:BAAANQADCgYICAAAAA==.',
Es='Esaelle:BAAANQADCggICAAAAA==.',
Ev='Evangelene:BAAANQAECgQIBAAAAA==.',
Fa='Fabulousness:BAAANQADCggIFQAAAA==.Fathur:BAAANQADCggICAAAAA==.',
Fo='Fornix:BAAANQADCgEIAQAAAA==.',
Fu='Furryriver:BAAANQADCggICwAAAA==.Furussy:BAAANQADCgcIBwAAAA==.',
Ga='Galadhras:BAAANQADCgUIBQAAAA==.Gamboslice:BAAANQAECgQICgAAAA==.Garkevon:BAAANQAECgIIAgAAAA==.',
Ge='Gevul:BAAANQAECgYIEgAAAA==.',
Gh='Ghuun:BAAANQAECgEIAQAAAA==.',
Gl='Glep:BAAANQADCggICAAAAA==.Glimmervoid:BAAANQADCgYICgAAAA==.',
Go='Golland:BAAANQABCgIIAgABNQAECgYIDgACAAAAAA==.Goob:BAAANQADCgYIBgAAAA==.',
Gr='Grandmatank:BAAANQADCgYIBgAAAA==.Greeze:BAAANQAECgEIAgAAAA==.Groinsapper:BAAANQADCgIIAgABNQADCgcIDgACAAAAAA==.',
Gu='Gumboslice:BAABNQAECoEXAAIGAAgJ5xwHCwCDAgAGAAgJ5xwHCwCDAgAAAA==.Gusgus:BAAANQADCgYICAAAAA==.',
Gy='Gyroflux:BAAANQAECgMIAwAAAA==.',
Ha='Haackh:BAAANQAECgcIBwAAAA==.Habanero:BAAANQAECgMIBAAAAA==.Hadd:BAAANQADCgEIAQAAAA==.Hadrìan:BAAANQADCgYIBgAAAA==.Hadéz:BAAANQADCgYIBgABNQAECgEIAQACAAAAAA==.Hark:BAAANQADCgUICgAAAA==.Haveabubble:BAAANQADCgQIAgABNQAECgMIBAACAAAAAA==.',
He='Healvisprsly:BAAANQADCgcIFAAAAA==.Helena:BAAANQAECgIIBAAAAA==.Heliarc:BAAANQADCgUICgAAAA==.',
Hi='Hidän:BAAANQAECgMIBAAAAA==.',
Ho='Holeyman:BAAANQADCgMIBAAAAA==.',
Hu='Huutou:BAAANQADCgYIBgAAAA==.',
Il='Illatix:BAAANQAECgQICAAAAA==.Illustriä:BAAANQADCgUICgAAAA==.',
In='Insidious:BAAANQAECgMIAwAAAA==.',
Is='Isisvane:BAAANQADCgUIBwAAAA==.',
It='Itchymage:BAAANQAECgcICgAAAA==.',
Iv='Ivyrayne:BAAANQADCggICAAAAA==.',
Ja='Jakeofny:BAAANQADCggICQAAAA==.',
Je='Jeffsgoytoy:BAAANQAECgcIDAAAAA==.',
Ji='Jighlipuff:BAAANQAECgEIAQAAAA==.Jigs:BAAANQAECgQIBgAAAA==.Jinxy:BAAANQADCgUIFAAAAA==.',
Ju='Judgements:BAAANQAECgEIAgAAAA==.Jug:BAAANQADCgUICwAAAA==.Jujutanketh:BAAANQADCggIEwAAAA==.',
Ka='Kabøchi:BAAANQADCgIIAgAAAA==.Kafia:BAAANQADCgEIAQAAAA==.Kalamak:BAAANQABCgYICQAAAA==.Kaldrick:BAAANQADCgYIFAAAAA==.Kanaloa:BAAANQADCgcIDQAAAA==.Karindis:BAAANQAECgQICQAAAA==.Kathulhu:BAAANQADCggICAAAAA==.',
Ke='Kegerator:BAAANQADCgIIAwAAAA==.Keldica:BAAANQAECgEIAQABNQAECgQIBAACAAAAAA==.Kenshan:BAAANQADCgcICAAAAA==.',
Kh='Khalinor:BAAANQADCgcIDAAAAA==.',
Ki='Kickazdin:BAABNQAECoEZAAMEAAkJUBiWHgBvAgAEAAgJ/xeWHgBvAgAFAAEJnRQe2wBAAAAAAA==.Kiryie:BAAANQADCgQIBQAAAA==.Kitinna:BAAANQADCgcIDgAAAA==.',
Kl='Klaw:BAAANQADCgUIBQAAAA==.',
Ko='Korraa:BAAANQAECgQIBwAAAA==.',
Kp='Kprist:BAAANQAECgQIBgAAAA==.',
Kr='Kraigen:BAAANQADCgcIDAAAAA==.',
Ku='Kunzhut:BAAANQAECgQIBQAAAA==.Kuroi:BAAANQADCgMIAwAAAA==.',
Ky='Kynasmira:BAAANQADCgQIBQAAAA==.',
La='Ladrona:BAAANQAECgEIAQAAAA==.Lailyre:BAAANQADCggICAAAAA==.Laydin:BAAANQAECggIAQAAAA==.',
Lb='Lb:BAAANQAECgUIBQAAAA==.',
Le='Legzanot:BAAANQAFFAEIAQAAAA==.Lestrade:BAAANQADCgcIFQABNQAECgYIBwACAAAAAA==.',
Li='Lightningfox:BAAANQADCgcIEwAAAA==.Lightsfallen:BAAANQAECgQIBAAAAA==.Lithia:BAAANQADCgQIBQAAAA==.Littlemo:BAAANQADCggICwAAAA==.',
Lo='Lohnar:BAAANQADCggICwAAAA==.Lorzana:BAAANQADCgcIDQAAAA==.',
Lu='Lucidslock:BAAANQADCgUICQAAAA==.Lucielbaal:BAAANQAECgMIAgAAAA==.Luckystop:BAAANQAECgEIAQAAAA==.Lumenir:BAAANQADCgYIBgAAAA==.Lunareth:BAAANQADCgYIDQABNQAECgQIBQACAAAAAA==.',
Ly='Lyrska:BAAANQADCggIEgAAAA==.Lytearrow:BAAANQAECgQIBQAAAA==.',
['Lì']='Lìvíd:BAAANQAECgUICQAAAA==.',
Ma='Mahrylee:BAAANQADCggIHAAAAA==.Majin:BAAANQAECgQIBAAAAA==.Manbearpally:BAAANQAECgEIAQAAAA==.Mannypack:BAAANQADCggIDgAAAA==.Mathagni:BAAANQADCgQIBAABNQADCgUIBQACAAAAAA==.Mathau:BAAANQADCgUIBQAAAA==.',
Mc='Mcleary:BAAANQADCgYIFQAAAA==.',
Me='Meldrus:BAAANQAECgQIBQAAAA==.Merrill:BAAANQADCgcICwAAAA==.',
Mi='Miala:BAAANQAECgIIAgAAAA==.Mierna:BAAANQAECgMIBAAAAA==.Miler:BAAANQADCgQIBgAAAA==.Mirota:BAAANQADCgEIAQAAAA==.',
Mo='Moemo:BAAANQAECgMIBAAAAA==.Mogryn:BAAANQAECgMIAgAAAA==.Mommybree:BAAANQAECgIIAgAAAA==.Monotonous:BAAANQADCgUICwAAAA==.Moondog:BAAANQADCgcICgAAAA==.Moonwarriorx:BAAANQADCgYIBgAAAA==.Morganalefey:BAAANQADCgMIBAAAAA==.Morsecode:BAAANQADCgYIBgABNQAECgMIAwACAAAAAA==.Morthok:BAAANQADCggIFQAAAA==.Mosh:BAAANQAECgMIBAAAAA==.',
Mu='Muskelunge:BAAANQADCgYIBgAAAA==.',
['Mã']='Mãf:BAAANQADCgEIAQAAAA==.',
Na='Naelyn:BAAANQAECgMIBAAAAA==.Nafir:BAAANQADCgYICgAAAA==.Nazgor:BAAANQADCggIFQAAAA==.',
Ne='Necrosius:BAAANQADCgEIAQAAAA==.Neolythic:BAEANQADCgUICgAAAA==.',
Ny='Nyxstalia:BAAANQADCgUIAwAAAA==.Nyyx:BAAANQADCggIDwAAAA==.',
Oa='Oath:BAAANQADCggICAAAAA==.',
Ob='Obscyra:BAAANQAECgQIBQAAAA==.',
Oc='Ochiie:BAAANQADCgcIEAAAAA==.',
Od='Oddyeppyep:BAAANQADCgYIDAAAAA==.',
Of='Offhand:BAAANQADCggIBwAAAA==.',
Ol='Olmek:BAABNQAECoEeAAMBAAkJpBh/JgCxAgABAAkJpBh/JgCxAgAHAAQJyBA1DwDiAAAAAA==.',
Oo='Oochie:BAAANQADCgQIBQAAAA==.Oochiee:BAAANQADCgIIAgAAAA==.Oochiië:BAAANQADCgIIAgAAAA==.',
Pa='Palasades:BAAANQADCgEIAQAAAA==.Pandalorian:BAAANQAECgUICAAAAA==.Papapumpies:BAAANQAECgcIEwAAAA==.Parlow:BAAANQADCggIGQAAAA==.Pazzo:BAAANQADCgcIDgAAAA==.',
Ph='Pharaa:BAAANQADCgcIEwAAAA==.',
Pi='Picoso:BAAANQADCggIFQAAAA==.Piianna:BAAANQAECggIEQAAAA==.Pizzaroll:BAAANQAECgQIBgAAAA==.',
Qa='Qatbarph:BAAANQADCgcICwAAAA==.',
Qi='Qikkaw:BAAANQADCgcIEwAAAA==.',
Qu='Quantos:BAAANQADCgcIFQAAAA==.',
Ra='Raatha:BAAANQAECgMIBAAAAA==.Raganar:BAAANQADCgcIEwAAAA==.Rago:BAAANQADCggICAAAAA==.Rasz:BAAANQAECgQICgAAAA==.Rayjean:BAAANQADCgMIAwABNQADCgUIBwACAAAAAA==.',
Re='Relmax:BAAANQADCggIDwAAAA==.Rennia:BAAANQADCggIBwABNQADCggICAACAAAAAA==.',
Rh='Rhonwynn:BAAANQADCgcIDgAAAA==.',
Ri='Rikershipdwn:BAAANQADCggIDwAAAA==.Rimrave:BAAANQAECgMIBAAAAA==.Ritobeans:BAAANQADCgMIAwAAAA==.',
Rk='Rk:BAAANQAECgQICgAAAA==.',
Ro='Robertkenway:BAAANQAECgQIBgABNQAECgQICgACAAAAAA==.Rod:BAAANQAECgQICQAAAA==.Rokte:BAAANQADCggIDgAAAA==.Rooke:BAAANQAECgQICQAAAA==.Rorsh:BAAANQADCgcIBwAAAA==.Rosekenway:BAAANQAECgQIBgABNQAECgQICgACAAAAAA==.',
Rr='Rratt:BAAANQADCgcIDgAAAA==.',
Ru='Running:BAAANQADCgEIAQAAAA==.',
['Rî']='Rîkku:BAAANQADCgEIAQAAAA==.',
Sa='Safewaybag:BAAANQADCgQIBAAAAA==.Samartyr:BAAANQADCggICwAAAA==.Sangwynaris:BAAANQADCggIDgAAAA==.Sanilien:BAAANQAECgQIBQAAAA==.Saphiiraa:BAAANQADCgYIBgAAAA==.Sathara:BAAANQADCgEIAQAAAA==.',
Sc='Scorpmage:BAAANQAECgMIAwAAAA==.',
Se='Sedrick:BAAANQAECgMIAwAAAA==.Sekaholic:BAAANQADCgEIAQABNQADCgcIDgACAAAAAA==.Sekendipity:BAAANQADCgEIAQABNQADCgcIDgACAAAAAA==.Sekndestroy:BAAANQADCgMIAwABNQADCgcIDgACAAAAAA==.Seksational:BAAANQADCgIIAgABNQADCgcIDgACAAAAAA==.Sekthyr:BAAANQADCgcIDgAAAA==.Sekzen:BAAANQADCgUIDgABNQADCgcIDgACAAAAAA==.',
Sh='Shamtune:BAABNQAECoEVAAIIAAgJIRUiMAD6AQAIAAgJIRUiMAD6AQAAAA==.Sharayman:BAAANQADCgUIBwAAAA==.Shattered:BAAANQADCgYICQAAAA==.Shaydra:BAAANQAECgMIAwAAAA==.Shazool:BAAANQAECgYIDQAAAA==.Shifterz:BAAANQADCggICwAAAA==.Shrieke:BAAANQADCgYIBgAAAA==.Shrubbery:BAAANQADCggIDAAAAA==.',
Si='Sindella:BAAANQAECgEIAQAAAA==.Sinna:BAAANQADCgYICgAAAA==.',
Sk='Skedaddle:BAAANQABCgIIAQABNQAECgQIBgACAAAAAA==.',
Sl='Slashgquit:BAAANQAECgYIDAAAAA==.Slumbermist:BAAANQAECgMIAwAAAA==.',
St='Stabbs:BAAANQADCggICAAAAA==.Strongboy:BAAANQADCgUIBwAAAA==.',
Sy='Syndar:BAAANQAECgIIAgABNQAECgQIBAACAAAAAA==.Synthetic:BAAANQADCgcIFQAAAA==.',
Sz='Szasstaam:BAAANQAECgEIAQAAAA==.',
Te='Tecsaran:BAAANQADCggIEwABNQAECgQIBAACAAAAAA==.Tekis:BAAANQAECgQICAAAAA==.Tensanio:BAAANQADCggIEwAAAA==.',
Th='Thalira:BAAANQADCgYIDAAAAA==.Thalrix:BAAANQADCgYIEAAAAA==.Thebiznitch:BAAANQADCgUIBAAAAA==.Theholyboi:BAAANQAECgUIBgAAAA==.Thwackk:BAAANQAECggICQAAAA==.',
Ti='Tieson:BAAANQADCgQIBQAAAA==.Tinkera:BAAANQADCgUICQAAAA==.Titanosaurus:BAAANQADCggICwAAAA==.',
To='Torridwells:BAAANQADCgQIBQAAAA==.',
Tr='Triebryn:BAAANQABCgQIBgAAAA==.Troag:BAAANQADCgcIFQAAAA==.Troagstar:BAAANQADCgcIFQAAAA==.',
Tu='Tubbytoe:BAAANQAECgEIAQAAAA==.',
Ty='Tyraana:BAAANQAECgYICgAAAA==.Tyrmog:BAAANQADCggIEAAAAA==.',
Un='Undetha:BAAANQADCgUIBQAAAA==.',
Us='Ushas:BAAANQAECgQIBwAAAA==.',
Va='Vali:BAAANQADCgcIDQABNQADCggICAACAAAAAA==.Valindrea:BAAANQADCggICwAAAA==.Vasrael:BAAANQADCggICAAAAA==.',
Ve='Vel:BAAANQAECgMIAwAAAA==.Venvanse:BAAANQAECgEIAQAAAA==.Vexen:BAAANQAECgMIAwAAAA==.',
Vn='Vnia:BAAANQAECgEIAQAAAA==.',
Vo='Voidmuffinz:BAAANQAECgcIDQAAAA==.',
Vy='Vynis:BAAANQAECgMIAwABNQAECggIFQAIACEVAA==.Vyrahildard:BAAANQAECgMIBAAAAA==.',
Wa='Wakkiq:BAAANQABCgIIAwAAAA==.Wasteland:BAAANQAECggIEQAAAA==.Watermelon:BAAANQAECgYIDwABNQAECgcIDQACAAAAAA==.',
We='Weaselhunter:BAAANQAECgMIBAABNQAECgMIBgACAAAAAA==.Weasellock:BAAANQAECgMIBgAAAA==.Weaselmage:BAAANQAECgEIAgABNQAECgMIBgACAAAAAA==.Weaselshammy:BAAANQAECgEIAQABNQAECgMIBgACAAAAAA==.',
Wh='Whatthef:BAAANQADCgEIAQAAAA==.',
Wi='Wildweasel:BAAANQAECgIIAgABNQAECgMIBgACAAAAAA==.Winterhide:BAAANQADCggIFQAAAA==.',
Xa='Xallie:BAEANQAECgYICAAAAA==.Xanvyr:BAAANQADCgQICAABNQAECgQICQACAAAAAA==.Xaquillis:BAAANQAECgYIDQAAAA==.',
Xe='Xeyvara:BAAANQAECgMIBAAAAA==.',
Za='Zaravalatha:BAAANQADCgQIBAAAAA==.Zarihanna:BAAANQAECgYIDQAAAA==.Zarsiia:BAAANQADCgUIBwAAAA==.',
Ze='Zernakk:BAAANQAECgQIBQAAAA==.Zestyknight:BAAANQADCggIFQAAAA==.',
Zi='Zindeshal:BAAANQADCgUICQAAAA==.',
Zo='Zorcunter:BAAANQAECgYIEAAAAA==.',
Zu='Zulizzajabi:BAAANQAECgIIBAAAAA==.',
['Åt']='Åthenå:BAAANQADCgYICgAAAA==.',
['Ða']='Ðarthrevan:BAAANQADCggICAAAAA==.',
['Ðo']='Ðonjon:BAAANQADCgcIBwAAAA==.',
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
