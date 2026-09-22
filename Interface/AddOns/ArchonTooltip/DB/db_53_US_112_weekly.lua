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

local lookup = {'Unknown-Unknown','Warrior-Arms','Druid-Balance','Paladin-Holy','Paladin-Retribution','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Druid-Restoration','Warrior-Fury','Priest-Holy','Shaman-Restoration','DemonHunter-Devourer','DeathKnight-Blood','Shaman-Elemental','Mage-Arcane','Hunter-BeastMastery',}
local provider = {region='US',realm='Greymane',name='US',type='weekly',zone=53,date='2026-09-22',data={Al='Alckmin:BAAANQADCgYIBgABNQAECgIIBQABAAAAAA==.Alderan:BAAANQADCgQIBAAAAA==.Alektophobia:BAAANQAECgIJAgAAAA==.',
Am='Amaurra:BAAANQABCgQIBAAAAA==.Amorina:BAAANQAECgUJCAAAAA==.',
An='Andill:BAAANQADCggJDwAAAA==.Andromeda:BAAANQADCgEIAQAAAA==.Aner:BAAANQADCgEIAQAAAA==.Angellete:BAABNQAECoEZAAICAAkKYx7gJQDaAgACAAkKYx7gJQDaAgAAAA==.Angrygnome:BAAANQAECgYJDAAAAA==.Angélique:BAAANQADCggIDAABNQAECgkJGQACAGMeAA==.Anieros:BAAANQAECgEIAgABNQAECgcJBwABAAAAAA==.',
Ar='Arax:BAAANQAECgQJBAAAAA==.Arcamoon:BAAANQADCgEIAQAAAA==.Arianpali:BAAANQADCgQIBQAAAA==.Armâgeddon:BAAANQAECgcIDQAAAA==.Arrokoth:BAAANQADCgYJDQAAAA==.Arthritas:BAAANQADCgQIBAAAAA==.',
At='Atropós:BAAANQAECgQJBAAAAA==.Attachedplag:BAAANQAECgEIAQAAAA==.Atulwa:BAAANQADCgMIAwAAAA==.',
Au='Autodrive:BAAANQADCgMIBQAAAA==.',
Az='Azmodious:BAAANQABCgIIAgAAAA==.',
Ba='Bambislayer:BAAANQADCgYIBwAAAA==.Banannana:BAAANQADCggICQAAAA==.Banzen:BAAANQADCggIGgAAAA==.Battle:BAEANQADCgEJAQABNQAECgcIEQABAAAAAA==.',
Be='Beardedyeti:BAAANQABCgQIBAAAAA==.Beginagain:BAAANQADCgcIFAAAAA==.Belgran:BAAANQAECgYJEAAAAA==.Berunma:BAAANQAECgMIBQAAAA==.',
Bi='Bileshots:BAAANQADCgYIDAAAAA==.Biowolf:BAAANQAECgcIEAAAAA==.Birdhunter:BAAANQAECgQIBAAAAA==.Bishopixixix:BAAANQABCgMIAwABNQAECgIIAgABAAAAAA==.Bishopxix:BAAANQAECgIIAgAAAA==.Bits:BAAANQADCgYJGwAAAA==.',
Bj='Bjoren:BAAANQAECgUIDgAAAA==.',
Bo='Bootiebang:BAAANQAECgMJBwAAAA==.',
Br='Brockshot:BAAANQAECgEJAQAAAA==.',
Bu='Bucknekkid:BAAANQADCgEIAQAAAA==.Buckwhild:BAAANQAECgUICgAAAA==.',
By='Byleth:BAAANQADCgIIAgAAAA==.',
Ca='Caladbolg:BAAANQAECgYIEgAAAA==.Canadaisheal:BAAANQAECgIIAgAAAA==.Catslol:BAAANQADCgEJAQAAAA==.',
Ce='Cesàrè:BAAANQAECgIIAgAAAA==.',
Ch='Chahra:BAAANQADCgQIBQAAAA==.Chamuki:BAAANQADCgMIAwABNQAFFAIIBQADAAgIAA==.Cheesecake:BAAANQADCgMIAwABNQAECgkJGQACAGMeAA==.Chuubak:BAAANQAECggICAAAAA==.',
Cl='Clangeddin:BAAANQADCgIIAgAAAA==.Clangedin:BAAANQAECgEJAQAAAA==.',
Co='Colonidus:BAAANQADCgYIFgAAAA==.Coondic:BAAANQADCgIIAgAAAA==.Corsten:BAAANQAECgIIAgAAAA==.',
Cr='Crosis:BAAANQADCgQIBQAAAA==.',
Cu='Cute:BAAANQAECgYIEwAAAA==.',
Da='Dagby:BAAANQADCgUIDgAAAA==.Dangerzone:BAAANQADCgUIBQAAAA==.Darkchronos:BAAANQADCggICwAAAA==.Darnuus:BAAANQAECgcIDQAAAA==.Datromandude:BAAANQAECgMIBQAAAA==.',
De='Deadmetalhed:BAAANQADCgIIAgAAAA==.Deathbydruid:BAAANQAECgQJBwABNQAECggJCQABAAAAAA==.Deathnelf:BAAANQADCgMIAwAAAA==.Deazraelle:BAAANQAECgUICAAAAA==.Dellin:BAAANQAECgQICAAAAA==.Demeco:BAEANQAECgUJBwABNQAFFAcJEgAEAKAYAA==.Demondots:BAAANQADCggIHQAAAA==.Denzalle:BAAANQADCgYJCQAAAA==.Devildognutz:BAAANQAECgEIAQAAAA==.',
Di='Diminuendo:BAAANQADCggJCwAAAA==.',
Do='Doozydruid:BAAANQAECgYJEQAAAA==.Dorozh:BAAANQAECgIJAgAAAA==.',
Dr='Draeke:BAAANQAECgEIAQAAAA==.Dragonzdemon:BAAANQADCgcICQAAAA==.Drala:BAAANQAECgMJBwAAAA==.Dreadpally:BAAANQADCgYJCgABNQADCgYICgABAAAAAA==.Dreco:BAAANQAECgUJBwAAAA==.Drtydhn:BAAANQABCgMJAwAAAA==.Druuzak:BAAANQAECgQIDAAAAA==.Dryconias:BAABNQAECoElAAIFAAkKuBqsKgCzAgAFAAkKuBqsKgCzAgAAAA==.Drèadpriest:BAAANQADCgUJBAAAAA==.',
Du='Duncanmcleod:BAAANQAECgMIAQABNQAECgUJCQABAAAAAA==.Dunkelzhan:BAAANQAECgQICwAAAA==.',
Dy='Dyana:BAAANQAECgIIAgAAAA==.',
Dz='Dz:BAAANQAECgYJEwAAAA==.',
Ec='Ecowolf:BAAANQADCgQJBAAAAA==.',
Ed='Edlund:BAAANQAECgQJCAAAAA==.',
El='Ellenaim:BAAANQADCgQIBQAAAA==.Elvy:BAAANQAECgYJEQAAAA==.',
En='Enngin:BAAANQAECgMIAwAAAA==.Enroks:BAAANQAECgYJEQAAAA==.',
Er='Erythrina:BAAANQADCgYICAAAAA==.',
Es='Esaelle:BAAANQADCggICAAAAA==.',
Ev='Evangelene:BAAANQAECgcJCgAAAA==.',
Ex='Exsalsior:BAAANQAECgcJBwAAAA==.',
Fa='Fabulousness:BAAANQADCggIFQAAAA==.Fathur:BAAANQADCggICAAAAA==.',
Fe='Fellstar:BAAANQADCgYIBgAAAA==.',
Fo='Fornix:BAAANQADCgEIAQAAAA==.',
Fu='Furryriver:BAAANQADCggICwAAAA==.Furussy:BAAANQADCgcIBwAAAA==.',
Ga='Galadhras:BAAANQADCgYJBgAAAA==.Gamboslice:BAAANQAECgYIDwAAAA==.Garkevon:BAAANQAECgIIAgAAAA==.',
Ge='Gevul:BAABNQAECoEhAAQGAAgKjhUTUADgAQAGAAcKzhUTUADgAQAHAAIKfA99SwB5AAAIAAEKngveIgA0AAAAAA==.',
Gh='Ghuun:BAAANQAECgEIAQAAAA==.',
Gl='Glep:BAAANQADCggICAAAAA==.Glimmervoid:BAAANQADCgYIEAAAAA==.',
Go='Golland:BAAANQABCgIJAgABNQAECgcIEgABAAAAAA==.Goob:BAAANQADCgYIBgAAAA==.',
Gr='Grandmatank:BAAANQADCgYIBgAAAA==.Greeze:BAAANQAECgEJAwAAAA==.Groinsapper:BAAANQADCgIIAgABNQADCgcIDgABAAAAAA==.',
Gu='Gumboslice:BAABNQAECoEgAAIJAAkKxhyyCgDCAgAJAAkKxhyyCgDCAgAAAA==.Gusgus:BAAANQAECgIJAgAAAA==.',
Gy='Gyroflux:BAAANQAECgMIAwAAAA==.',
Ha='Haackh:BAAANQAFFAIJAgAAAA==.Habanero:BAAANQAECgQJCAAAAA==.Hadd:BAAANQADCgEJAQAAAA==.Hadrìan:BAAANQADCgYIBgAAAA==.Hark:BAAANQADCgYJCwAAAA==.Haveabubble:BAAANQADCgQIAgABNQAECgQJCAABAAAAAA==.',
He='Healvisprsly:BAAANQADCgcIGAAAAA==.Helena:BAAANQAECgYJCgAAAA==.Heliarc:BAAANQADCgYJCwAAAA==.',
Hi='Hidän:BAAANQAECgMJBQAAAA==.',
Ho='Holeyman:BAAANQADCgMIBAAAAA==.',
Hu='Huutou:BAAANQADCgYJCgAAAA==.',
Il='Illatix:BAAANQAECgQICAAAAA==.Illustriä:BAAANQAECgEJAQAAAA==.',
In='Insidious:BAAANQAECgQIBwAAAA==.',
Is='Isisvane:BAAANQADCgUJBwAAAA==.',
It='Itchydh:BAAANQADCgEJAQABNQAECgcJEQABAAAAAA==.Itchymage:BAAANQAECgcJEQAAAA==.',
Iv='Ivyrayne:BAAANQADCggJCAAAAA==.',
Ja='Jaganash:BAAANQADCggICAABNQAECgQIBAABAAAAAA==.Jakeofny:BAAANQADCggICQAAAA==.',
Je='Jeffsgoytoy:BAAANQAECgcJDAAAAA==.',
Ji='Jighlipuff:BAAANQAECgEIAQAAAA==.Jigs:BAAANQAECgQICgAAAA==.Jinxy:BAAANQADCgcIGwAAAA==.',
Ju='Judgements:BAAANQAECgEIAgAAAA==.Jug:BAAANQADCgcJFAAAAA==.Jujutanketh:BAAANQADCggIEwAAAA==.Junebugg:BAAANQADCggJCwAAAA==.',
Ka='Kabøchi:BAAANQAECgEJAQAAAA==.Kafia:BAAANQADCgEJAQAAAA==.Kalamak:BAAANQABCgYICQAAAA==.Kaldrick:BAAANQADCggJIQAAAA==.Kanaloa:BAAANQADCgcIDQAAAA==.Karindis:BAAANQAECgUIDgAAAA==.Kathulhu:BAAANQAECgEJAQAAAA==.',
Ke='Kegerator:BAAANQADCgIIAwAAAA==.Keldica:BAAANQAECgUJBQABNQAECgUICAABAAAAAA==.Kenshan:BAAANQADCgcJCgAAAA==.',
Kh='Khalinor:BAAANQAECgQIBAAAAA==.Khotuhn:BAAANQADCgcJBwAAAA==.',
Ki='Kickazdin:BAABNQAECoEhAAMEAAkK4hzZGwC0AgAEAAgKIh3ZGwC0AgAFAAEKnRQ6EAE/AAAAAA==.Kiryie:BAAANQADCgQJBQAAAA==.Kitinna:BAAANQAECgIIAgAAAA==.',
Kl='Klaw:BAAANQADCgYJBgAAAA==.',
Ko='Korraa:BAAANQAECgUIDAAAAA==.',
Kp='Kprist:BAAANQAECgQIBgAAAA==.',
Kr='Kraigen:BAAANQAECgQJBAAAAA==.',
Ku='Kunzhut:BAAANQAECgQJCQAAAA==.Kuroi:BAAANQADCgMIAwAAAA==.',
Ky='Kynasmira:BAAANQADCgUJBgAAAA==.',
La='Ladrona:BAAANQAECgEJAQAAAA==.Lailyre:BAAANQADCggICAABNQAECgIJAQABAAAAAA==.Laydin:BAAANQAECggJCQAAAA==.',
Lb='Lb:BAAANQAECgYICwAAAA==.',
Le='Legzanot:BAAANQAFFAEIAQAAAA==.Lestrade:BAAANQAECgIJAgABNQAECgcIDQABAAAAAA==.',
Li='Lightdude:BAAANQADCgcJBwAAAA==.Lightningfox:BAAANQAECgIJAgAAAA==.Lightsfallen:BAAANQAECgUJCQAAAA==.Lithia:BAAANQADCgQIBQAAAA==.Littlemo:BAAANQADCggICwAAAA==.',
Lo='Lohnar:BAAANQADCggICwAAAA==.Lorzana:BAAANQADCgcIDQAAAA==.',
Lu='Lucidslock:BAAANQADCgUIDgAAAA==.Lucielbaal:BAAANQAECgQJBgAAAA==.Luckystop:BAAANQAECgEIAQAAAA==.Lumenir:BAAANQADCgYIBgAAAA==.Lunareth:BAAANQAECgIJAgABNQAECgYJCwABAAAAAA==.',
Ly='Lyrska:BAAANQAECgEJAQAAAA==.Lytearrow:BAAANQAECgUICgAAAA==.',
['Lì']='Lìvíd:BAAANQAECgUICQAAAA==.',
Ma='Mahrylee:BAAANQADCggIHAAAAA==.Majin:BAAANQAECgQIBAAAAA==.Manbearpally:BAAANQAECgEIAQAAAA==.Mannypack:BAAANQAECgIJAgAAAA==.Mathagni:BAAANQADCgQIBAABNQADCgUICgABAAAAAA==.Mathau:BAAANQADCgUICgAAAA==.',
Mc='Mcleary:BAAANQAECgQJBQAAAA==.',
Me='Meldrus:BAAANQAECgUJCgAAAA==.',
Mi='Miala:BAAANQAECgIIAgAAAA==.Midnytestorm:BAAANQADCgcJBgAAAA==.Mierna:BAAANQAECgQJCAAAAA==.Miler:BAAANQAECgEJAQAAAA==.Mirota:BAAANQADCgEJAQAAAA==.',
Mo='Moemo:BAAANQAECgMIBwAAAA==.Mogryn:BAAANQAECgMIBAAAAA==.Mommybree:BAAANQAECgIIAgAAAA==.Monotonous:BAAANQADCgUIEAAAAA==.Moondog:BAAANQADCgcICgAAAA==.Moonwarriorx:BAAANQADCgYIBgAAAA==.Morganalefey:BAAANQADCgMIBAAAAA==.Morthok:BAAANQAECgQJBAAAAA==.Mosh:BAAANQAECgMJBwAAAA==.',
Mu='Muskelunge:BAAANQADCgYICwAAAA==.',
['Mã']='Mãf:BAAANQADCggICQAAAA==.',
Na='Naelyn:BAAANQAECgQJCAAAAA==.Nafir:BAAANQADCgYIDwAAAA==.Nakky:BAAANQADCggICAAAAA==.Nazgor:BAAANQAECgIJAgAAAA==.',
Ne='Necrosius:BAAANQADCgEIAQAAAA==.Neolythic:BAEANQADCgYJCwAAAA==.',
Ny='Nyxstalia:BAAANQADCgUIAwAAAA==.Nyyx:BAAANQADCggIFwAAAA==.',
Oa='Oath:BAAANQAECgQIBAAAAA==.',
Ob='Obscyra:BAAANQAECgYJCwAAAA==.',
Oc='Ochiie:BAAANQADCgcIEAAAAA==.Ocho:BAAANQADCgUIBQAAAA==.',
Od='Oddyeppyep:BAAANQADCgYJDAAAAA==.',
Of='Offhand:BAAANQADCggJBwAAAA==.',
Ol='Olmek:BAABNQAECoEjAAMCAAkKrRrmKwC8AgACAAkKrRrmKwC8AgAKAAQKyBBGEwDfAAAAAA==.',
Oo='Oochie:BAAANQADCgYJBwAAAA==.Oochiee:BAAANQAECgEJAQAAAA==.Oochiië:BAAANQADCgcJCQAAAA==.',
Op='Oprahwndfury:BAAANQADCggJEAABNQADCgcIGAABAAAAAA==.',
Pa='Palasades:BAAANQAECgEIAQAAAA==.Pallydussy:BAAANQADCgQIBAAAAA==.Pandalorian:BAAANQAECgYJDgAAAA==.Papapumpies:BAABNQAECoEcAAICAAgKMSJkJADiAgACAAgKMSJkJADiAgAAAA==.Parlow:BAAANQADCggIGQAAAA==.Pazzo:BAAANQADCgcJEQAAAA==.',
Ph='Pharaa:BAAANQAECgIJAgAAAA==.Philandre:BAAANQADCgUJBQAAAA==.',
Pi='Picoso:BAAANQAECgQJBAAAAA==.Piianna:BAABNQAECoEbAAILAAkKLhQFIwB8AgALAAkKLhQFIwB8AgAAAA==.Pizzaroll:BAAANQAECgYJDAAAAA==.',
['Pø']='Pøwe:BAAANQADCgMIAwABNQADCgcIGAABAAAAAA==.',
Qa='Qatbarph:BAAANQADCgcICwAAAA==.',
Qi='Qikkaw:BAAANQAECgIJAgAAAA==.',
Qu='Quantos:BAAANQADCggIHQAAAA==.',
Ra='Raatha:BAAANQAECgQICAAAAA==.Raganar:BAAANQAECgIJAgAAAA==.Rago:BAAANQAECgQJBAAAAA==.Rasz:BAAANQAECgUJDwAAAA==.Rayjean:BAAANQADCgMIAwABNQADCgYJCAABAAAAAA==.',
Re='Reider:BAAANQADCggJCAAAAA==.Relmax:BAAANQAECgIJAgAAAA==.Rennia:BAAANQAECgIJAQAAAA==.',
Rh='Rhonwynn:BAAANQAECgIJAgAAAA==.',
Ri='Rikershipdwn:BAAANQAECgIJAgAAAA==.Rimrave:BAAANQAECgQJCAAAAA==.Ritobeans:BAAANQADCgMIAwAAAA==.',
Rk='Rk:BAAANQAECgUJDwAAAA==.',
Ro='Robertkenway:BAAANQAECgUICwABNQAECgUJDwABAAAAAA==.Rod:BAAANQAECgUIDgAAAA==.Rokte:BAAANQADCggIDgAAAA==.Rollhots:BAAANQAECgQJBAAAAA==.Rooke:BAAANQAECgYIEAAAAA==.Rorsh:BAAANQADCgcIBwAAAA==.Rosekenway:BAAANQAECgQIBgABNQAECgUJDwABAAAAAA==.',
Rr='Rratt:BAAANQADCgcIDgAAAA==.',
Ru='Running:BAAANQADCgEIAQAAAA==.',
['Rî']='Rîkku:BAAANQADCgEIAQAAAA==.',
Sa='Safewaybag:BAAANQADCgQIBAAAAA==.Samartyr:BAAANQADCggICwAAAA==.Sangwynaris:BAAANQADCggIDgAAAA==.Sanilien:BAAANQAECgQJCQAAAA==.Saphiiraa:BAAANQADCgYIBgAAAA==.Sathara:BAAANQADCgEIAQAAAA==.',
Sc='Scorpmage:BAAANQAECgMJBQAAAA==.',
Se='Sedrick:BAAANQAECgQJBwAAAA==.Sekaholic:BAAANQADCgEIAQABNQADCgcIDgABAAAAAA==.Sekendipity:BAAANQADCgEIAQABNQADCgcIDgABAAAAAA==.Sekndestroy:BAAANQADCgMIAwABNQADCgcIDgABAAAAAA==.Seksational:BAAANQADCgIIAgABNQADCgcIDgABAAAAAA==.Sekthyr:BAAANQADCgcIDgAAAA==.Sekzen:BAAANQADCgUJDgABNQADCgcIDgABAAAAAA==.',
Sh='Shamtune:BAABNQAECoEYAAIMAAkKwRQJMgAvAgAMAAkKwRQJMgAvAgAAAA==.Sharayman:BAAANQADCgYJCAAAAA==.Shattered:BAAANQADCgYICQAAAA==.Shaydra:BAAANQAECgQJBwAAAA==.Shazool:BAABNQAECoEWAAIMAAgKbyRsCQBGAwAMAAgKbyRsCQBGAwAAAA==.Shifterz:BAAANQADCggICwAAAA==.Shrieke:BAAANQADCgYIBgAAAA==.Shrubbery:BAAANQAECgIJAgAAAA==.',
Si='Sind:BAAANQADCgIIAgABNQAECgIJAwABAAAAAA==.Sindella:BAAANQAECgIJAwAAAA==.Sindrè:BAAANQABCgUJBQABNQAECgIJAwABAAAAAA==.Sinna:BAAANQADCgYICgAAAA==.',
Sk='Skedaddle:BAAANQABCgIIAQABNQAECgQICgABAAAAAA==.',
Sl='Slashgquit:BAAANQAECgYJEgAAAA==.Slumbermist:BAAANQAECgQJBwAAAA==.',
Sn='Snazzi:BAAANQADCgIJAgAAAA==.',
St='Stabbs:BAAANQADCgkJDgAAAA==.Strongboy:BAAANQADCgUIBwAAAA==.',
Sy='Syndar:BAAANQAECgUICAAAAA==.Synthetic:BAAANQADCgcIGwAAAA==.',
Sz='Szasstaam:BAAANQAECgIIAwAAAA==.',
Te='Tecsaran:BAAANQAECgQIBAABNQAECgUICAABAAAAAA==.Tekis:BAAANQAECgQJCAAAAA==.Tensanio:BAAANQADCggIEwAAAA==.',
Th='Thalira:BAAANQAECgEJAQAAAA==.Thalrix:BAAANQAECgUIBQAAAA==.Thebiznitch:BAAANQADCgUIBAAAAA==.Theholyboi:BAAANQAECgUJBwAAAA==.Thwackk:BAAANQAECggJCQAAAA==.',
Ti='Tieson:BAAANQADCgcJEwAAAA==.Tinkera:BAAANQADCgUICQAAAA==.Titanosaurus:BAAANQADCggICwAAAA==.',
To='Torridwells:BAAANQADCgQIBQAAAA==.',
Tr='Triebryn:BAAANQABCgQIBgAAAA==.Troag:BAAANQADCgcIGwAAAA==.Troagstar:BAAANQADCggJHQAAAA==.',
Tu='Tubbytoe:BAAANQAECgEIAQAAAA==.',
Ty='Tyraana:BAAANQAECgYICgAAAA==.Tyrmog:BAAANQADCggIEAAAAA==.',
Un='Undetha:BAAANQAECgQJBAAAAA==.',
Us='Ushas:BAAANQAECgYJCQAAAA==.',
Va='Vaeiane:BAAANQADCggJCAABNQAECgIJAQABAAAAAA==.Vali:BAAANQADCgcIDQABNQAECgQIBAABAAAAAA==.Valindrea:BAAANQADCggICwAAAA==.Vasrael:BAAANQAECgQJBAAAAA==.',
Ve='Vel:BAAANQAECgcICgAAAA==.Venvanse:BAAANQAECgEJAQABNQAECgQJCAABAAAAAA==.Vexen:BAAANQAECgQJBwAAAA==.',
Vn='Vnia:BAAANQAECgEIAQAAAA==.',
Vo='Voidmuffinz:BAABNQAECoEXAAINAAgKxhgbFACCAgANAAgKxhgbFACCAgAAAA==.',
Vy='Vynis:BAAANQAECgQJBAABNQAECgkJGAAMAMEUAA==.Vyrahildard:BAAANQAECgQICAAAAA==.',
Wa='Wakkiq:BAAANQABCgIIAwAAAA==.Wasteland:BAABNQAECoEZAAIOAAkKdgiuQQCDAQAOAAkKdgiuQQCDAQAAAA==.Watermelon:BAABNQAECoEZAAMMAAgK6wxeUwCcAQAMAAgK6wxeUwCcAQAPAAQKFAKorwCVAAAAAA==.',
We='Weaselhunter:BAAANQAECgMIBAABNQAECgMJCAABAAAAAA==.Weasellock:BAAANQAECgMJCAAAAA==.Weaselmage:BAAANQAECgEJBAABNQAECgMJCAABAAAAAA==.Weaselshammy:BAAANQAECgMJBAABNQAECgMJCAABAAAAAA==.',
Wh='Whatthef:BAAANQADCgcJCAAAAA==.',
Wi='Wildweasel:BAAANQAECgMIAwABNQAECgMJCAABAAAAAA==.Winterhide:BAAANQAECgQJBAAAAA==.Wishbone:BAAANQAECgEIAQAAAA==.',
Wo='Womamatoo:BAAANQADCgYJAwAAAA==.',
Xa='Xallie:BAEANQAECgYIDgAAAA==.Xanvyr:BAAANQADCgQICAABNQAECgQICQABAAAAAA==.Xaquillis:BAABNQAECoEYAAIOAAgKcg/ZNwC4AQAOAAgKcg/ZNwC4AQAAAA==.',
Xe='Xeyvara:BAAANQAECgQJCAAAAA==.',
Za='Zaravalatha:BAAANQADCgQIBAAAAA==.Zarihanna:BAABNQAECoEfAAIQAAgKrw6khwAEAgAQAAgKrw6khwAEAgAAAA==.Zarsiia:BAAANQAECgEJAQAAAA==.',
Ze='Zernakk:BAAANQAECgQIBwAAAA==.Zestdh:BAAANQAECgIJAgAAAA==.Zestyknight:BAAANQAECgIJAgAAAA==.',
Zi='Zindeshal:BAAANQADCgUICQAAAA==.',
Zo='Zorcunter:BAABNQAECoEZAAIRAAgKCiUODwAqAwARAAgKCiUODwAqAwAAAA==.',
Zu='Zulizzajabi:BAAANQAECgIJBAAAAA==.',
['Åt']='Åthenå:BAAANQADCgYICgAAAA==.',
['Ða']='Ðarthrevan:BAAANQAECgEJAQAAAA==.',
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
