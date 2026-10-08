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

local lookup = {'Unknown-Unknown','Warrior-Arms','Warlock-Destruction','Monk-Windwalker','DeathKnight-Frost','Shaman-Elemental','Priest-Holy','Priest-Shadow','Paladin-Protection','Paladin-Retribution','Druid-Balance','Warrior-Fury','Shaman-Restoration','Paladin-Holy','Mage-Frost','Mage-Arcane','Shaman-Enhancement','Warlock-Demonology','Warlock-Affliction','Druid-Restoration','Hunter-BeastMastery','Hunter-Marksmanship','DemonHunter-Vengeance','Druid-Guardian','Evoker-Devastation','Hunter-Survival','Monk-Mistweaver','DeathKnight-Blood','DemonHunter-Havoc','DemonHunter-Devourer',}
local provider = {region='US',realm='Greymane',name='US',type='weekly',zone=53,date='2026-10-06',data={Ak='Akaidia:BAAANQAECggIBgAAAA==.',
Al='Alckmin:BAAANQADCgYIBgABNQAECgQICAABAAAAAA==.Alderan:BAAANQADCgQIBAAAAA==.Alektophobia:BAAANQAECgQIBQAAAA==.Allysaun:BAAANQADCgcIBwAAAA==.',
Am='Amaurra:BAAANQABCgQIBAAAAA==.Amorina:BAAANQAECgUICwAAAA==.',
An='Anda:BAAANQADCgIIAgAAAA==.Andill:BAAANQAECgIIAgAAAA==.Andromeda:BAAANQADCgUIBgAAAA==.Aner:BAAANQADCgEIAQAAAA==.Angellete:BAABNQAECoEdAAICAAkKmR63PgC2AgACAAkKmR63PgC2AgAAAA==.Angrygnome:BAABNQAECoEdAAIDAAgKwBxiBQC5AgADAAgKwBxiBQC5AgAAAA==.Angélique:BAAANQAECgMIAwABNQAECgkJHQACAJkeAA==.Anieros:BAAANQAECgEIAgABNQAFFAEIAQABAAAAAA==.',
Ar='Arax:BAAANQAECgQIBgAAAA==.Arcamoon:BAAANQADCgEIAQAAAA==.Arianpali:BAAANQAECgUIBgAAAA==.Armâgeddon:BAABNQAECoEZAAICAAkKOxwVTwCBAgACAAkKOxwVTwCBAgAAAA==.Arrokoth:BAAANQADCggIDwAAAA==.Arthritas:BAAANQADCgQIBAAAAA==.',
At='Atropós:BAAANQAECgUICQAAAA==.Attachedplag:BAAANQAECgUICAAAAA==.Atulwa:BAAANQADCgMIAwAAAA==.',
Au='Autodrive:BAAANQADCgMIBQAAAA==.',
Az='Azmodious:BAAANQABCgIIAgAAAA==.',
Ba='Baconhuntard:BAAANQAECgMIAwAAAA==.Bambislayer:BAAANQADCgYIBwAAAA==.Banannana:BAAANQAECgUIBgAAAA==.Banzen:BAAANQADCggIGwAAAA==.Battle:BAEANQADCgEIAQABNQAECgkJJAAEANMcAA==.',
Be='Beardedyeti:BAAANQABCgQIBAAAAA==.Beginagain:BAAANQADCgcIFAAAAA==.Belgran:BAABNQAECoEYAAIFAAgKlxT7LgDzAQAFAAgKlxT7LgDzAQAAAA==.Bernese:BAAANQADCgIIAgAAAA==.Berunma:BAAANQAECgYIDQAAAA==.',
Bh='Bhain:BAAANQABCgIIAQABNQAECgkJHAAGAOwbAA==.',
Bi='Bileshots:BAAANQAECgMIAwAAAA==.Biowolf:BAAANQAFFAIIAgAAAA==.Birdhunter:BAAANQAECgYIBgAAAA==.Bishopixixix:BAAANQABCgMIAwABNQAECgQIBAABAAAAAA==.Bishopxix:BAAANQAECgQIBAAAAA==.Bits:BAAANQAECgIIAgAAAA==.',
Bj='Bjoren:BAABNQAECoEhAAMHAAgK7yL6EQAlAwAHAAgK7yL6EQAlAwAIAAEKYgAFhgALAAAAAA==.',
Bl='Blackki:BAAANQADCgQIBQAAAA==.',
Bo='Bootiebang:BAAANQAECgYIDwAAAA==.Bootycaall:BAAANQADCgcIBwAAAA==.Boxxie:BAAANQADCgcIDgAAAA==.',
Br='Branches:BAAANQADCgMIAwAAAA==.Brockshot:BAAANQAECgEIAQAAAA==.',
Bu='Bucknekkid:BAAANQADCgUIBgAAAA==.Buckwhild:BAAANQAECgcIEgAAAA==.',
By='Byleth:BAAANQADCgIIAgAAAA==.',
Ca='Caladbolg:BAABNQAECoElAAMJAAgKBh9VCwDFAgAJAAgKBh9VCwDFAgAKAAEKIBJdbwE3AAAAAA==.Canadaisheal:BAAANQAECgQIBgAAAA==.Catslol:BAAANQADCgEIAQAAAA==.',
Ce='Cesàrè:BAAANQAECgQICgAAAA==.',
Ch='Chahra:BAAANQADCgQIBQAAAA==.Chamuki:BAAANQADCgMIAwABNQAFFAUIDgALAK0RAA==.Cheesecake:BAAANQADCgMIAwABNQAECgkJHQACAJkeAA==.Chuubak:BAAANQAECggICAAAAA==.',
Cl='Clangeddin:BAAANQADCgIIAgAAAA==.Clangedin:BAAANQAECgQIBgAAAA==.',
Co='Colonidus:BAAANQAECgQIBAAAAA==.Coondic:BAAANQADCgIIAgAAAA==.Corsten:BAAANQAECgYIDgAAAA==.',
Cr='Crosis:BAAANQADCgQIBQAAAA==.',
Cu='Cute:BAABNQAECoEZAAMCAAcK1RyEhgDmAQACAAcKjhyEhgDmAQAMAAQKLBPIGgDUAAAAAA==.',
Da='Dagby:BAAANQADCgYIGgAAAA==.Dandi:BAAANQAECgIIAgAAAA==.Dangerzone:BAAANQADCgUIBQAAAA==.Darkchronos:BAAANQADCggICwAAAA==.Darkwolf:BAAANQAECgQIBAAAAA==.Darnuus:BAABNQAECoEaAAINAAkKcBo0JwCnAgANAAkKcBo0JwCnAgAAAA==.Datromandude:BAAANQAECgMIBQAAAA==.',
De='Deadmetalhed:BAAANQADCgIIAgAAAA==.Deathbydruid:BAAANQAECgYIEgABNQAECggIEQABAAAAAA==.Deathnelf:BAAANQADCgMIAwAAAA==.Deazraelle:BAAANQAECggIDwAAAA==.Dellin:BAAANQAECgUIDQAAAA==.Demeco:BAEANQAECgUJBwABNQAFFAcIEwAOAMsaAA==.Demondots:BAAANQAECgIIAgAAAA==.Denzalle:BAAANQADCgYJCQAAAA==.Devildognutz:BAAANQAECgEIAQAAAA==.',
Di='Diminuendo:BAAANQAECgIIAgAAAA==.',
Do='Doozydruid:BAAANQAECgYJEQAAAA==.Dorozh:BAAANQAECgQIBQAAAA==.',
Dr='Draeke:BAAANQAECgEIAQAAAA==.Dragonzdemon:BAAANQADCgcICQAAAA==.Drala:BAAANQAECgUIDwAAAA==.Dreadpally:BAAANQADCgYJCgABNQADCgYICgABAAAAAA==.Dreco:BAAANQAECgUIDAAAAA==.Drtydhn:BAAANQABCgMJAwAAAA==.Druuzak:BAABNQAECoEYAAIPAAgKHw6cDAC6AQAPAAgKHw6cDAC6AQAAAA==.Dryconias:BAABNQAECoEsAAIKAAkKDhzyRACgAgAKAAkKDhzyRACgAgAAAA==.Drèadpriest:BAAANQADCgUJBAAAAA==.',
Du='Duncanmcleod:BAAANQAECgYICgABNQAECgYIDgABAAAAAA==.Dunkelzhan:BAABNQAECoEbAAIQAAcKrBXHvwDhAQAQAAcKrBXHvwDhAQAAAA==.',
Dv='Dvldogma:BAAANQAECgUICAAAAA==.',
Dy='Dyana:BAAANQAECgQIBQAAAA==.',
Dz='Dz:BAABNQAECoEnAAMOAAkKvCGBBgCMAwAOAAkKvCGBBgCMAwAKAAYKDQ3B0QA9AQAAAA==.',
Ec='Ecobessie:BAAANQADCgYICgAAAA==.Ecowolf:BAAANQADCgQIBAABNQADCgYICgABAAAAAA==.',
Ed='Edlund:BAAANQAECgYIDgAAAA==.',
El='Electricfun:BAAANQAECgEIAQAAAA==.Ellenaim:BAAANQADCgQIBQAAAA==.Elvy:BAABNQAECoEgAAILAAgKLhW2NAAbAgALAAgKLhW2NAAbAgAAAA==.',
En='Enngin:BAAANQAECgMIAwAAAA==.Enroks:BAABNQAECoEjAAQGAAgKJBLVVwDuAQAGAAgKJBLVVwDuAQANAAYKZhmTbgCQAQARAAEKOgj5LwA5AAAAAA==.',
Er='Erythrina:BAAANQADCgYICAAAAA==.',
Es='Esaelle:BAAANQADCggICAAAAA==.',
Ev='Evangelene:BAAANQAECggIEAAAAA==.Evangelina:BAAANQADCgEIAQAAAA==.',
Ex='Exsalsior:BAAANQAFFAEIAQAAAA==.',
Fa='Fabulousness:BAAANQAECgUIBQAAAA==.Fathur:BAAANQADCggICwAAAA==.',
Fe='Fellstar:BAAANQADCgYIBgAAAA==.',
Fo='Fornix:BAAANQADCgEIAQAAAA==.',
Fu='Furryriver:BAAANQAECgUIBgAAAA==.Furussy:BAAANQADCgcIBwAAAA==.',
Ga='Galadhras:BAAANQADCgYIDAAAAA==.Gamboslice:BAABNQAECoEdAAIFAAkKXRZTIgBQAgAFAAkKXRZTIgBQAgAAAA==.Garkevon:BAAANQAECgUICwAAAA==.',
Ge='Gevul:BAABNQAECoEzAAQSAAkKJBteOwCFAgASAAgKdBteOwCFAgADAAMKZxV2OADUAAATAAEKngt4LAAzAAAAAA==.',
Gh='Ghuun:BAAANQAECgUICQAAAA==.',
Gl='Glep:BAAANQADCggICwAAAA==.Glimmervoid:BAAANQADCggIGQAAAA==.',
Go='Golland:BAAANQABCgIIAgABNQAECggIHAAGAIQXAA==.Goob:BAAANQADCgYIBgAAAA==.',
Gr='Grandmatank:BAAANQADCgYIBgAAAA==.Greeze:BAAANQAECgUICgAAAA==.Groinsapper:BAAANQADCgIIAgABNQADCgcIDgABAAAAAA==.Grozny:BAAANQADCgYIBgABNQAECgYIDQABAAAAAA==.',
Gu='Gumboslice:BAABNQAECoEpAAIUAAkKcB1cDgDQAgAUAAkKcB1cDgDQAgAAAA==.Gumiho:BAAANQAECgUIBwAAAA==.Gusgus:BAAANQAECgUICgAAAA==.',
Gy='Gyroflux:BAAANQAECgMIAwAAAA==.',
Ha='Haackh:BAACNQAFFIEFAAIVAAMKbBJNFADwAAAVAAMKbBJNFADwAAA1AAQKgR0AAhUACQqeIU4NAGMDABUACQqeIU4NAGMDAAAA.Habanero:BAAANQAECgUICQAAAA==.Hadd:BAAANQADCgEJAQAAAA==.Hadrìan:BAAANQADCgYIBgAAAA==.Hadéz:BAAANQAECggIAgABNQAECgcKHAAWADQOAA==.Hark:BAAANQADCgYIDwAAAA==.Haveabubble:BAAANQADCgQIAgABNQAECgYIDgABAAAAAA==.',
He='Healvisprsly:BAAANQADCggIIAAAAA==.Helena:BAABNQAECoEdAAMJAAgKeCITBwAbAwAJAAgKeCITBwAbAwAKAAgKTA3VmAC7AQAAAA==.Heliarc:BAAANQADCgYIFQAAAA==.',
Hi='Hidän:BAAANQAECgUIDQAAAA==.',
Ho='Holeyman:BAAANQADCgMIBAAAAA==.Hoomalu:BAAANQADCgIIAgAAAA==.',
Hu='Huund:BAAANQADCgUIBQAAAA==.Huutou:BAAANQADCgYJCgAAAA==.',
Il='Illatix:BAAANQAECgQICAAAAA==.Illustriä:BAAANQAECgEIAgAAAA==.',
In='Insidious:BAAANQAECgYIEgAAAA==.',
Ir='Irs:BAAANQAECgQIBAAAAA==.',
Is='Isisvane:BAAANQADCgcICQAAAA==.',
It='Itchydh:BAAANQADCgEJAQABNQAECggIHQAQAOAdAA==.Itchymage:BAABNQAECoEdAAIQAAgK4B2ybgCLAgAQAAgK4B2ybgCLAgAAAA==.',
Iv='Ivyrayne:BAAANQADCggICAAAAA==.',
Ja='Jaganash:BAAANQADCggICwABNQAECgUICQABAAAAAA==.Jakeofny:BAAANQAECgQIAwAAAA==.',
Je='Jeffsgoytoy:BAAANQAECgcIDQAAAA==.',
Ji='Jighlipuff:BAAANQAECgQICQAAAA==.Jigs:BAABNQAECoEYAAIVAAcKHQuTnwCVAQAVAAcKHQuTnwCVAQAAAA==.Jinxy:BAAANQADCggILwAAAA==.',
Ju='Judgements:BAAANQAECgQIBgAAAA==.Jug:BAAANQADCggIIgAAAA==.Jujutanketh:BAAANQAECgUIBgAAAA==.Junebugg:BAAANQAECgEIAQAAAA==.',
Ka='Kabøchi:BAAANQAECgUICAAAAA==.Kafia:BAAANQADCgEJAQAAAA==.Kalamak:BAAANQABCgYICQAAAA==.Kaldrick:BAAANQAECgUIBgAAAA==.Kanaloa:BAAANQAECgIIAgAAAA==.Karindis:BAABNQAECoEhAAIXAAgK5SFvAwAHAwAXAAgK5SFvAwAHAwAAAA==.Kathulhu:BAAANQAECgEIAgAAAA==.',
Ke='Kegerator:BAAANQADCgIIAwAAAA==.Keldica:BAAANQAECgUJBQABNQAECgYIEgABAAAAAA==.',
Kh='Khalinor:BAAANQAECgUICQAAAA==.Khotuhn:BAAANQADCgcIFQAAAA==.',
Ki='Kickazdin:BAABNQAECoErAAMOAAkKyR5HIQDRAgAOAAgKRh9HIQDRAgAKAAEKnRRJbQE4AAAAAA==.Kiryie:BAAANQADCgQIBQAAAA==.Kitinna:BAAANQAECgUICQAAAA==.',
Kl='Klaw:BAAANQADCgYIEAAAAA==.',
Ko='Korraa:BAABNQAECoEXAAMNAAcKOhs9VwDeAQANAAYKphw9VwDeAQAGAAUK0g8BmgAzAQAAAA==.',
Kp='Kprist:BAAANQAECgUIDAAAAA==.',
Kr='Kraigen:BAAANQAECgUIBwAAAA==.',
Ku='Kunzhut:BAAANQAECgYIDwAAAA==.Kuroi:BAAANQADCgMIAwAAAA==.',
Ky='Kynasmira:BAAANQADCgYIDAAAAA==.',
La='Ladrona:BAAANQAECgEIAQAAAA==.Laeli:BAAANQADCgYIBgABNQADCggILwABAAAAAA==.Laydin:BAAANQAECggIEQAAAA==.',
Lb='Lb:BAAANQAECgcIEQAAAA==.',
Le='Legzanot:BAABNQAECoEeAAIGAAgKoRL9VAD4AQAGAAgKoRL9VAD4AQAAAA==.Lestrade:BAAANQAECgUICgABNQAECgkJGgANAHAaAA==.',
Li='Lightdude:BAAANQADCgcJBwAAAA==.Lightningfox:BAAANQAECgUIDgAAAA==.Lightsfallen:BAAANQAECgYIDgAAAA==.Lithia:BAAANQADCgQIBQAAAA==.Littlemo:BAAANQAECgUIBgAAAA==.',
Lo='Lohnar:BAAANQAECgUIBgAAAA==.Lorzana:BAAANQADCgcIDQAAAA==.',
Lu='Lucidslock:BAAANQADCgYIEQAAAA==.Lucielbaal:BAAANQAECgYIDAAAAA==.Luckystop:BAAANQAECgEIAQAAAA==.Lumenir:BAAANQADCgYIBgAAAA==.Lunareth:BAAANQAECgQIBQABNQAECgYIDQABAAAAAA==.',
Ly='Lyrska:BAAANQAECgQIBQAAAA==.Lytearrow:BAAANQAECgcIEQAAAA==.',
['Lì']='Lìvíd:BAAANQAECgUICQAAAA==.',
Ma='Mahrylee:BAAANQAECgEIAQAAAA==.Majin:BAAANQAECgUICQAAAA==.Makmobius:BAAANQABCgQIBAAAAA==.Manbearpally:BAAANQAECgEIAQAAAA==.Mannypack:BAAANQAECgIJAgAAAA==.Mathagni:BAAANQADCgQIBAABNQADCgYIFgABAAAAAA==.Mathau:BAAANQADCgYIFgAAAA==.Maztrix:BAAANQAECgEIAQAAAA==.',
Mc='Mcleary:BAAANQAECgQJBQAAAA==.',
Me='Meldrus:BAAANQAECgYIEQAAAA==.Mending:BAAANQAECgIIAgAAAA==.',
Mi='Miala:BAAANQAECgIIAgAAAA==.Midnytestorm:BAAANQADCgcJBgAAAA==.Mierna:BAAANQAECgYIDgAAAA==.Miler:BAAANQAECgIIAwAAAA==.Mirota:BAAANQADCgEJAQAAAA==.',
Mo='Moemo:BAAANQAECgUIDwAAAA==.Mogryn:BAAANQAECgYICgAAAA==.Mommybree:BAAANQAECgIIAgAAAA==.Monotonous:BAAANQADCgUIEAAAAA==.Moonwarriorx:BAAANQADCgYIBgAAAA==.Morganalefey:BAAANQADCgMIBAAAAA==.Morsecode:BAAANQAECgMIAwABNQAECgYIEgABAAAAAA==.Morthok:BAAANQAECgUICQAAAA==.Mosh:BAAANQAECgUIDwAAAA==.',
Mu='Muskelunge:BAAANQADCgYIEQAAAA==.',
['Mã']='Mãf:BAAANQADCggICQAAAA==.',
Na='Naelyn:BAAANQAECgYIDgAAAA==.Nafir:BAAANQADCgYIDwAAAA==.Nakky:BAAANQADCggICwAAAA==.Nazgor:BAAANQAECgUICQAAAA==.',
Ne='Necrodragon:BAAANQADCgMIBgAAAA==.Necrosius:BAAANQADCgEIAQAAAA==.Neolythic:BAEANQADCgYIFQAAAA==.Newwt:BAAANQADCgcIBwAAAA==.',
Ny='Nyxstalia:BAAANQADCgUIAwAAAA==.Nyyx:BAAANQAECgIIAgAAAA==.',
Oa='Oath:BAAANQAECgUICQAAAA==.',
Ob='Obscyra:BAAANQAECgYIDQAAAA==.',
Oc='Ochiie:BAAANQADCgcIFgAAAA==.Ocho:BAAANQADCgUIBQAAAA==.',
Od='Oddsham:BAAANQADCgUIBQAAAA==.Oddyeppyep:BAAANQADCgYIEQAAAA==.',
Of='Offhand:BAAANQADCggJBwAAAA==.',
Ol='Olmek:BAACNQAFFIEIAAMCAAQK4AcZGgD8AAACAAQK4AcZGgD8AAAMAAEK7AmwBQA/AAA1AAQKgS0AAwIACQqMH1wmABADAAIACQqMH1wmABADAAwABArIEOQaANMAAAAA.',
Oo='Oochie:BAAANQAECgcICQAAAA==.Oochiee:BAAANQAECgEIAQAAAA==.Oochiië:BAAANQAECgEIAQAAAA==.',
Op='Oprahwndfury:BAAANQADCggIEgABNQADCggIIAABAAAAAA==.',
Pa='Palasades:BAAANQAECgUICwAAAA==.Palelore:BAAANQABCggIEQAAAA==.Pallydussy:BAAANQADCgYICgAAAA==.Pandalorian:BAABNQAECoEeAAIHAAgKtBaXQABDAgAHAAgKtBaXQABDAgAAAA==.Papapumpies:BAABNQAECoEmAAICAAkKyiD5LAD2AgACAAkKyiD5LAD2AgAAAA==.Parlow:BAAANQADCggIGQAAAA==.Pazzo:BAAANQADCgcIEQAAAA==.',
Ph='Pharaa:BAAANQAECgUICgAAAA==.Philandre:BAAANQADCgUIBQAAAA==.',
Pi='Picoso:BAAANQAECgUICQAAAA==.Piianna:BAABNQAECoEoAAIHAAkK0xYyJwCwAgAHAAkK0xYyJwCwAgAAAA==.Pizzaroll:BAABNQAECoEdAAIYAAcKOSHICQCeAgAYAAcKOSHICQCeAgAAAA==.',
['Pø']='Pøwe:BAAANQADCgMIAwABNQADCggIIAABAAAAAA==.',
Qa='Qatbarph:BAAANQAECgYIDAAAAA==.',
Qi='Qikkaw:BAAANQAECgUICgAAAA==.',
Qu='Quantos:BAAANQAECgQICAAAAA==.',
Ra='Raatha:BAAANQAECgYIDgAAAA==.Raganar:BAAANQAECgUICgAAAA==.Rago:BAAANQAECgcICwAAAA==.Rasz:BAABNQAECoEbAAMVAAYKdRpMhgDPAQAVAAYK/RlMhgDPAQAWAAQKEAqFTgDHAAAAAA==.Rayjean:BAAANQADCgMIAwABNQADCgYIEgABAAAAAA==.',
Re='Reider:BAAANQADCggIDwAAAA==.Relmax:BAAANQAECgQIBQAAAA==.Rennia:BAAANQAECgIIAgABNQAECggIBgABAAAAAA==.',
Rh='Rhonwynn:BAAANQAECgUICgAAAA==.',
Ri='Rikershipdwn:BAAANQAECgIJAgAAAA==.Rimrave:BAAANQAECgYIDgAAAA==.Ritobeans:BAAANQADCgMIAwAAAA==.',
Rk='Rk:BAABNQAECoEVAAIZAAYKvQgTIQAqAQAZAAYKvQgTIQAqAQABNQAECggIGwAaACwIAA==.',
Ro='Robertkenway:BAABNQAECoEbAAIaAAgKLAjvBwC4AQAaAAgKLAjvBwC4AQAAAA==.Rod:BAABNQAECoEZAAIbAAgKBxHhFwDPAQAbAAgKBxHhFwDPAQAAAA==.Rokte:BAAANQADCggIDgAAAA==.Rollhots:BAAANQAECgUIBwAAAA==.Rook:BAAANQAECgcIDgABNQAECgcIEgABAAAAAA==.Rooke:BAAANQAECgcIEgAAAA==.Rorsh:BAAANQADCgcIBwAAAA==.Rosekenway:BAAANQAECgcIDwABNQAECggIGwAaACwIAA==.',
Rr='Rratt:BAAANQADCgcIDgAAAA==.',
Ru='Running:BAAANQADCgEIAQAAAA==.',
['Rî']='Rîkku:BAAANQADCgEIAQAAAA==.',
Sa='Safewaybag:BAAANQADCgQIBAAAAA==.Samartyr:BAAANQAECgUIBgAAAA==.Sangwynaris:BAAANQADCggIDgAAAA==.Sanilien:BAAANQAECgQICQAAAA==.Saphiiraa:BAAANQADCgYIBgAAAA==.Sathara:BAAANQADCgEIAQAAAA==.',
Sc='Scorpmage:BAAANQAECgUIDAAAAA==.',
Se='Sedrick:BAAANQAECgYIEgAAAA==.Sekaholic:BAAANQADCgEIAQABNQADCgcIDgABAAAAAA==.Sekendipity:BAAANQADCgEIAQABNQADCgcIDgABAAAAAA==.Sekhmett:BAAANQADCgIIAgAAAA==.Sekndestroy:BAAANQADCgMIAwABNQADCgcIDgABAAAAAA==.Seksational:BAAANQADCgIIAgABNQADCgcIDgABAAAAAA==.Sekthyr:BAAANQADCgcIDgAAAA==.Sekzen:BAAANQADCgUJDgABNQADCgcIDgABAAAAAA==.',
Sh='Shamtune:BAABNQAECoEeAAMNAAkK4hS+TQAAAgANAAkK4hS+TQAAAgAGAAEKnQ7TDQE7AAAAAA==.Sharayman:BAAANQADCgYIEgAAAA==.Shattered:BAAANQADCgYICQAAAA==.Shaydra:BAAANQAECgYIEgAAAA==.Shazool:BAABNQAECoEfAAINAAgKbyQLEQAnAwANAAgKbyQLEQAnAwAAAA==.Shifterz:BAAANQAECgMIBQAAAA==.Shrieke:BAAANQADCgYIBgAAAA==.Shrubbery:BAAANQAECgQIBQAAAA==.',
Si='Siarra:BAAANQADCgMIAwAAAA==.Sind:BAAANQADCgIIAgABNQAECgQICQABAAAAAA==.Sindella:BAAANQAECgQICQAAAA==.Sindrè:BAAANQABCgUIBQABNQAECgQICQABAAAAAA==.Sinna:BAAANQADCgYICgAAAA==.',
Sk='Skedaddle:BAAANQAECgEIAQABNQAECgcIGQAPAGIgAA==.',
Sl='Slashgquit:BAABNQAECoEZAAIcAAcKgyGPKABhAgAcAAcKgyGPKABhAgAAAA==.Slumbermist:BAAANQAECgYIEgAAAA==.',
Sn='Snazzi:BAAANQAECgYICwAAAA==.Snowtitan:BAAANQADCgUIBQAAAA==.',
So='Solam:BAAANQAECgMIAwAAAA==.',
St='Stabbs:BAAANQADCggIDgAAAA==.Strongboy:BAAANQADCgUIBwAAAA==.Stx:BAAANQADCggICAABNQAECgcICQABAAAAAA==.',
Sy='Syndar:BAAANQAECgYIEgAAAA==.Synthetic:BAAANQAECgQIBgAAAA==.',
Sz='Szasstaam:BAAANQAECgIIAwAAAA==.',
Ta='Tarnaris:BAAANQADCgIIAgAAAA==.Tattersaile:BAAANQADCgIIAgAAAA==.',
Te='Tecsaran:BAAANQAECgUICQABNQAECgYIEgABAAAAAA==.Tekis:BAAANQAECgQICAAAAA==.Tensanio:BAAANQADCggIEwAAAA==.',
Th='Thalira:BAAANQAECgQIBAAAAA==.Thalrix:BAAANQAECgUIBQAAAA==.Thebiznitch:BAAANQADCgUIBAAAAA==.Theholyboi:BAAANQAECgUJBwAAAA==.Thetowelie:BAAANQABCgMIAwAAAA==.Thickneck:BAAANQADCgUIBQAAAA==.Thwackk:BAAANQAECggICQAAAA==.',
Ti='Tieson:BAAANQAECgEIAwAAAA==.Tinkera:BAAANQADCgYIEAAAAA==.Titanosaurus:BAAANQAECgIIAgAAAA==.',
To='Torridwells:BAAANQADCgQIBQAAAA==.',
Tr='Triebryn:BAAANQABCgQIBgAAAA==.Troag:BAAANQAECgQIBgAAAA==.Troagstar:BAAANQAECgQIBgAAAA==.',
Tu='Tubbytoe:BAAANQAECgEIAQAAAA==.',
Ty='Tyraana:BAABNQAECoEdAAMdAAgKpB0GHACVAgAdAAgKpB0GHACVAgAeAAEKyQuIXwA0AAAAAA==.Tyrmog:BAAANQADCggIFAAAAA==.',
Un='Undetha:BAAANQAECgUICQAAAA==.',
Us='Ushas:BAABNQAECoEXAAMHAAcKTheIcwCJAQAHAAYKtReIcwCJAQAIAAEKAAy7dAAoAAAAAA==.',
Va='Vaeiane:BAAANQADCggICAABNQAECggIBgABAAAAAA==.Vali:BAAANQADCgcIDQABNQAECgUICQABAAAAAA==.Valindrea:BAAANQAECgQIBgAAAA==.Vasrael:BAAANQAECgUICQAAAA==.',
Ve='Vel:BAAANQAECgcIEAAAAA==.Venvanse:BAAANQAECgEJAQABNQAECgYIEgABAAAAAA==.Vexen:BAAANQAECgYIEgAAAA==.',
Vn='Vnia:BAAANQAECgEIAQAAAA==.',
Vo='Voidmuffinz:BAABNQAECoEoAAMeAAkK4BkIFACwAgAeAAkK4BkIFACwAgAdAAcKegzgQACAAQAAAA==.',
Vy='Vynis:BAAANQAECgQIBAABNQAECgkJHgANAOIUAA==.Vyrahildard:BAAANQAECgYIDgAAAA==.',
Wa='Wakkiq:BAAANQADCgYICgAAAA==.Wasteland:BAABNQAECoEkAAIcAAkKjApFUQCPAQAcAAkKjApFUQCPAQAAAA==.Watermelon:BAABNQAECoEcAAMNAAgKCRFaZgCqAQANAAgKCRFaZgCqAQAGAAQKFAIr5gCMAAABNQAFFAIIAgABAAAAAA==.',
We='Weaselhunter:BAAANQAECgMIBgABNQAECgUICQABAAAAAA==.Weasellock:BAAANQAECgMICQABNQAECgUICQABAAAAAA==.Weaselmage:BAAANQAECgEIBgABNQAECgUICQABAAAAAA==.Weaselshammy:BAAANQAECgUICQAAAA==.',
Wh='Whatthef:BAAANQADCgcIDwAAAA==.',
Wi='Wildweasel:BAAANQAECgMIBAABNQAECgUICQABAAAAAA==.Winterhide:BAAANQAECgUICQAAAA==.Wishbone:BAAANQAECgQICQAAAA==.',
Wo='Womamatoo:BAAANQADCgcICgAAAA==.',
Xa='Xallie:BAEANQAECgYIDgAAAA==.Xanvyr:BAAANQAECgEIAQABNQAECgQICQABAAAAAA==.Xaquillis:BAABNQAECoEZAAIcAAgKKBAsTAClAQAcAAgKKBAsTAClAQAAAA==.Xaras:BAAANQADCgMIAwAAAA==.',
Xe='Xentrie:BAAANQADCggICAAAAA==.Xeyvara:BAAANQAECgYIDgAAAA==.',
Ya='Yah:BAAANQADCgMIAwAAAA==.',
Za='Zaravalatha:BAAANQADCgQIBAAAAA==.Zarihanna:BAABNQAECoErAAIQAAgKkREVrQAHAgAQAAgKkREVrQAHAgAAAA==.Zariia:BAAANQADCgQIBAAAAA==.Zarsiia:BAAANQAECgQIBgAAAA==.',
Ze='Zernakk:BAAANQAECgUICgAAAA==.Zestdh:BAAANQAECgIJAgAAAA==.Zestyknight:BAAANQAECgMIBQAAAA==.',
Zi='Zindeshal:BAAANQADCgcICwAAAA==.',
Zo='Zorcunter:BAABNQAECoEgAAIVAAkK/SRXDABqAwAVAAkK/SRXDABqAwAAAA==.',
Zu='Zulizzajabi:BAAANQAECgIJBAAAAA==.',
['Åt']='Åthenå:BAAANQADCgYICgAAAA==.',
['Ða']='Ðarthrevan:BAAANQAECgEIAQAAAA==.',
['Ðo']='Ðonjon:BAAANQADCgcICwAAAA==.',
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
