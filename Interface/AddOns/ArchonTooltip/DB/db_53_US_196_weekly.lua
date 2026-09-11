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

local lookup = {'Unknown-Unknown','Druid-Balance','Shaman-Elemental','Mage-Arcane','DeathKnight-Unholy','Warlock-Demonology','Warlock-Destruction','Mage-Frost','Evoker-Preservation','Warrior-Arms','DemonHunter-Devourer','Shaman-Restoration','Hunter-BeastMastery','Warrior-Fury',}
local provider = {region='US',realm='Silvermoon',name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aakura:BAAANQAECgYICwAAAA==.Aamira:BAAANQADCgUICQAAAA==.Aaravas:BAAANQADCgIIAgAAAA==.Aarcadia:BAAANQADCgUIDgAAAA==.',
Ad='Adamantus:BAAANQADCggIEQAAAA==.',
Ae='Aelasong:BAAANQADCgcIDQAAAA==.Aelioran:BAAANQAECgMIAwAAAA==.Aenlor:BAAANQADCgYICwAAAA==.Aestar:BAAANQADCgcICAAAAA==.',
Ai='Airedhiel:BAAANQADCgUIBwAAAA==.',
Al='Alacantos:BAAANQAECgQIBQAAAA==.Alainnaingil:BAAANQADCggICAAAAA==.Alanjackson:BAAANQADCgUICQAAAA==.Alawyn:BAAANQAECgUICgAAAA==.Alayssaria:BAAANQAECgIIAgAAAA==.Alcana:BAAANQADCgQIBAAAAA==.Alexstrazett:BAAANQADCgMIBAAAAA==.Alextros:BAEANQAECgEIAQABNQAECgQIBQABAAAAAA==.Alltaken:BAAANQADCgYIDwAAAA==.Alokin:BAAANQADCgEIAQAAAA==.Alpharetta:BAABNQAECoEWAAICAAkJBx5zCAAeAwACAAkJBx5zCAAeAwABNQAECgkJGAADAFkaAA==.Alsera:BAAANQAECgMIAwAAAA==.',
Am='Amarae:BAAANQADCgYICwAAAA==.Amicoolyet:BAAANQADCgcIEAAAAA==.Ammon:BAAANQADCgIIAgAAAA==.Amorene:BAAANQAECgcIEQAAAA==.Amorvane:BAAANQADCggICAABNQAECgcIEQABAAAAAA==.Amoryn:BAAANQAECgIIAgABNQAECgcIEQABAAAAAA==.',
An='Anaraellea:BAAANQADCgYICgAAAA==.Andcheese:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Andramedally:BAAANQADCgcIBwAAAA==.Andrusius:BAAANQAECgYIBgAAAA==.Angellena:BAAANQAECgQIBAAAAA==.Anian:BAAANQADCgUICgAAAA==.Antadin:BAAANQADCggIFgAAAA==.Anthela:BAAANQADCggICAABNQAECgIIAgABAAAAAA==.',
Ap='Apherilia:BAAANQADCggIDwAAAA==.',
Ar='Aranos:BAAANQADCgYICQAAAA==.Ardrick:BAAANQADCggIDQAAAA==.Arihua:BAAANQADCgYIBwAAAA==.Arkano:BAAANQADCgYIBgAAAA==.Aronau:BAAANQADCgUICgAAAA==.Arosen:BAAANQAECgIIAgAAAA==.Artforidiots:BAAANQAECgQIBAAAAA==.Arthurious:BAAANQADCgcICwAAAA==.',
As='Asenath:BAAANQAECgIIAgAAAA==.Askec:BAAANQADCgYIBgAAAA==.Asmodeus:BAAANQAECgQIBwAAAA==.Aspect:BAAANQAECgEIAQAAAA==.Astraeâ:BAAANQADCggIDgAAAA==.',
Av='Avacado:BAAANQADCggICgABNQAFFAQIBwACALoaAA==.Avicularia:BAAANQADCgYIBgAAAA==.',
Aw='Awake:BAAANQAECggICAAAAA==.',
Ax='Axdk:BAAANQAECgIIAgAAAA==.',
Ay='Ayalha:BAAANQAECgUICQAAAA==.',
Ba='Babychewie:BAAANQAECgQIBQAAAA==.Balla:BAAANQADCggIFQAAAA==.Bambismash:BAAANQADCgUICAAAAA==.',
Be='Beansgreens:BAAANQADCgMIBAAAAA==.Beantism:BAAANQAECgIIAgAAAA==.Beardeath:BAAANQAECgQIBQAAAA==.Bearleft:BAAANQABCgQIBQAAAA==.Beaross:BAAANQAECgEIAgAAAA==.Beeflomein:BAAANQAECgQIBQAAAA==.Beledros:BAAANQAECgUIDQABNQAECgMIBQABAAAAAA==.Beratol:BAAANQADCgUICAAAAA==.',
Bi='Bigeasy:BAAANQADCgcIEAAAAA==.',
Bl='Blakkadin:BAAANQADCgUIBgABNQAECggIEgABAAAAAA==.Blayzn:BAAANQADCgUIBwAAAA==.Bloodmoonpal:BAAANQADCgMIAwAAAA==.Bloodychêwy:BAAANQADCgcIBwAAAA==.Bluex:BAAANQADCgMIAwAAAA==.Blutdurst:BAAANQADCggIDAAAAA==.',
Bo='Bojammies:BAAANQADCgMIBQAAAA==.Bombad:BAAANQADCggICAABNQAECgkJFQAEAPwgAQ==.Bonelargeles:BAAANQAECgQIAgAAAA==.Booyaah:BAAANQAFFAIIAgAAAA==.Boulderbro:BAAANQADCgEIAQAAAA==.',
Br='Brazok:BAAANQADCggICAAAAA==.Brigade:BAAANQAECggIEQAAAA==.Brigadester:BAAANQAECggIEQAAAA==.Brogaine:BAAANQADCgUIBwAAAA==.Broodin:BAAANQADCgYIBwAAAA==.Bruen:BAAANQADCgUIBQAAAA==.',
Bu='Bullbas:BAAANQADCggICgAAAA==.Bumdog:BAAANQADCggICwAAAA==.',
Ca='Calrisa:BAAANQAECgQICAAAAQ==.Calrisyia:BAAANQADCgEIAQABNQAECgQICAABAAAAAA==.Camin:BAAANQADCgUIBQAAAA==.Carltonhoot:BAAANQADCgMIAwAAAA==.Cassadk:BAAANQAECgIIAgAAAA==.Cassapedia:BAAANQADCgYICwABNQAECgIIAgABAAAAAA==.Cassawings:BAAANQADCgUICQABNQAECgIIAgABAAAAAA==.',
Ce='Celestria:BAAANQAECgQIBQAAAA==.Celna:BAAANQADCgYIEAAAAA==.Celyssia:BAAANQAECgIIAgAAAA==.Cernos:BAAANQADCgYIEAAAAA==.',
Ch='Chance:BAAANQAECgUICgAAAA==.Chardclass:BAAANQAECgEIAQABNQAECggIFQACALkiAA==.Charzard:BAAANQAECgEIAQAAAA==.Cheerio:BAAANQAECgQIBAAAAA==.Cheezit:BAAANQADCggICAAAAA==.',
Ci='Cinderson:BAAANQABCgMIAwAAAA==.',
Cl='Clömp:BAAANQAECgMIBAAAAA==.',
Co='Coreion:BAAANQADCgcICwAAAA==.',
Cr='Crimsonmist:BAAANQAECgQIDAABNQAECggICwABAAAAAA==.Crisstos:BAAANQADCgMIBAAAAA==.Cristhel:BAAANQAECgcICgAAAA==.Critneyfearz:BAAANQADCgYIBgAAAA==.Crusk:BAAANQADCggIEQAAAA==.',
Cs='Csg:BAAANQAECgIIAgAAAA==.',
Cy='Cyllene:BAAANQADCgMIBAAAAA==.',
['Cé']='Cérnunnos:BAAANQAECgQIBQAAAA==.',
Da='Daemonslayer:BAAANQADCggIFQAAAA==.Daftknight:BAAANQAECgEIAQAAAA==.Daisycutter:BAAANQAECgQIBgAAAA==.Dakoo:BAAANQADCgIIAgAAAA==.Daluon:BAAANQABCgIIAgABNQAECgMIBAABAAAAAA==.Damai:BAAANQABCgIIBAAAAA==.Dances:BAAANQADCggIEQAAAA==.Daravanthel:BAAANQAECgIIAgAAAA==.Daresh:BAAANQAECgIIAgABNQAECgYICwABAAAAAA==.Darkbeast:BAAANQAECgUIBgAAAA==.Darkbáine:BAAANQAECgcICwAAAA==.Darkdarion:BAAANQABCgQIBQAAAA==.Darling:BAAANQAECgYICwAAAA==.Darmorg:BAAANQAECgYIDQAAAA==.Darthaxe:BAAANQAECggIEwAAAA==.Dazzlok:BAAANQADCgIIAgAAAA==.',
De='Deathsurge:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.Deegoddaem:BAAANQADCgYIBgAAAA==.Delacour:BAEANQAECgcIEQABNQAECgUIBQABAAAAAA==.Dembjuicy:BAAANQADCgUIBQAAAA==.Derkaus:BAAANQAECgEIAQAAAA==.Dev:BAAANQAECgQIAwAAAA==.Dezz:BAAANQAECgIIAgAAAA==.Dezza:BAAANQAECgMIAwAAAA==.',
Dh='Dharenar:BAAANQAECgUICgAAAA==.',
Di='Diazepam:BAAANQADCgMIAwAAAA==.Dizzyflores:BAAANQAECgIIAgAAAA==.',
Dj='Djguckie:BAAANQADCgYICgAAAA==.',
Dk='Dkordis:BAAANQADCgMIAwAAAA==.',
Dn='Dnyce:BAAANQAECgUIBQAAAA==.',
Do='Doomcore:BAAANQAECgMIBAAAAA==.Dooper:BAAANQAECgYIDAAAAA==.Dorbinn:BAAANQADCgUIBQAAAA==.Dorrf:BAAANQADCgUIBAAAAA==.Doshneil:BAAANQADCggIEAAAAA==.',
Dr='Dragongor:BAAANQADCggIEQAAAA==.Dragonsmight:BAAANQAECgUICQAAAA==.Dreamvore:BAAANQAECgYICwAAAA==.Droknarr:BAAANQABCgIIAwAAAA==.Droø:BAAANQADCgEIAQAAAA==.',
Du='Dualwield:BAAANQAECgIIAgAAAA==.Dustobones:BAAANQAECgQICQAAAA==.',
Dw='Dwee:BAAANQADCgUIBQABNQADCgUIBwABAAAAAA==.Dweedy:BAAANQADCgUIBwAAAA==.',
Ea='Ealen:BAAANQADCgYIBgAAAA==.',
Ee='Eellyqt:BAAANQADCgQIBAAAAA==.',
El='Eliyana:BAAANQAECgIIAgAAAA==.Elledrus:BAAANQAECgEIAQAAAA==.Elm:BAAANQADCgcIDwAAAA==.Elsiñd:BAAANQAECgIIAgAAAA==.Eluniel:BAAANQAECgEIAgAAAA==.',
Em='Emberdk:BAABNQAECoEYAAIFAAkJaw0PGgAxAgAFAAkJaw0PGgAxAgAAAA==.Emojones:BAAANQADCgYIDwAAAA==.',
Ep='Ephysa:BAAANQADCgYICQAAAA==.',
Er='Erasra:BAAANQAECgIIAwAAAA==.',
Es='Essenne:BAAANQADCgYIEAABNQAECgIIAgABAAAAAA==.',
Et='Etali:BAAANQADCgQIBAABNQAECgMIBQABAAAAAA==.Etrigg:BAAANQADCggICgAAAA==.',
Ex='Exstatik:BAAANQAECgIIAQAAAA==.',
Ey='Eyeamgroot:BAAANQAECgEIAQAAAA==.Eyeholeman:BAAANQAECgIIAgAAAA==.',
Ez='Ezzrra:BAAANQAECgMIBAAAAA==.',
Fa='Faelunae:BAAANQADCgUIBgAAAA==.Faillock:BAABNQAECoEXAAMGAAkJwhW/JADhAQAGAAcJVBS/JADhAQAHAAQJfxBlJAD+AAAAAA==.Falora:BAAANQADCgUIBwAAAA==.Fangshot:BAAANQAECgEIAQAAAA==.',
Fe='Feldwn:BAAANQADCgMIAwAAAA==.Felraux:BAAANQADCgEIAQAAAA==.Fengbao:BAAANQAECgIIAgAAAA==.Fezzik:BAAANQADCgQIBAAAAA==.',
Fi='Filthydegén:BAAANQADCgYIBwAAAA==.Finnior:BAAANQADCgEIAQAAAA==.Fionnaghuala:BAAANQADCgQIBAABNQAECgQIBwABAAAAAA==.Firedemon:BAAANQADCgYIEgAAAA==.Firemedivh:BAAANQADCgIIAgAAAA==.Fishspells:BAAANQAECgYIDgAAAA==.',
Fl='Flashfrozen:BAAANQAECgIIAgAAAA==.Flute:BAAANQAECgUICgAAAA==.',
Fo='Foxshot:BAAANQADCgQIBAAAAA==.',
Fr='Frayden:BAAANQAECgMIAwAAAA==.Frizmo:BAAANQADCgMIAwAAAA==.Frogprincess:BAAANQADCgcIEAAAAA==.Frontdeboeuf:BAAANQADCggIEwAAAA==.Frostygrrl:BAAANQADCgQIBAAAAA==.Frozaller:BAAANQADCgEIAQAAAA==.',
Fu='Fuilsidhe:BAAANQADCgcIEwAAAA==.Furricane:BAAANQADCgEIAQAAAA==.',
Ga='Gadios:BAAANQAECgcIEAAAAA==.Gaiyia:BAAANQADCggIEwAAAA==.Galebjorn:BAAANQAECgQIDAAAAA==.Garfna:BAAANQADCggIEAAAAA==.Garfrost:BAAANQADCgIIAgAAAA==.Gascoigne:BAAANQADCggIDgAAAA==.',
Ge='Gencil:BAAANQADCgYICgAAAA==.',
Gh='Ghadpri:BAAANQADCgEIAQAAAA==.Ghemanis:BAAANQADCgQIBAAAAA==.',
Gi='Gimboo:BAAANQADCggICAAAAA==.Gizzimo:BAAANQADCgQIBwAAAA==.',
Go='Goobr:BAAANQADCggICgABNQAECgMIBQABAAAAAA==.Goover:BAAANQADCgcIEwAAAA==.Gosu:BAAANQADCggIEwAAAA==.',
Gr='Gracelyn:BAAANQAECgIIAgAAAA==.Graftin:BAAANQADCgYIBgAAAA==.Greener:BAAANQADCgYICwAAAA==.Grezgara:BAAANQADCggIEQAAAA==.Griimace:BAAANQAECgIIAgAAAA==.Grimoldone:BAAANQADCggIFQAAAA==.Grimverdict:BAAANQADCgQIBQABNQAECgIIAwABAAAAAA==.Grinderrg:BAAANQAECgMIBAAAAA==.Grommashryon:BAAANQAECgIIAgAAAA==.Grumbledecay:BAAANQADCgYIBgAAAA==.Grumbledore:BAABNQAECoEVAAMEAAkJ/CBjLgCJAgAEAAcJzB9jLgCJAgAIAAMJlSQCCQAuAQAAAA==.',
Gu='Gumbö:BAAANQAECgQIBQAAAA==.Guttzes:BAAANQAECgEIAQAAAA==.',
['Gï']='Gïngersnaps:BAAANQADCgQIBAAAAA==.',
Ha='Halidril:BAAANQAECgQIBQAAAA==.Hanshiro:BAAANQAECgUIBQAAAA==.Hardin:BAAANQADCgUIBQAAAA==.Hasel:BAAANQAECgEIAQAAAA==.Hawkhunter:BAAANQAECgMIAwAAAA==.Hazzazz:BAAANQAECgEIAQAAAA==.',
He='Hearthbunny:BAAANQADCgYIBgAAAA==.Hegs:BAAANQAECgUICQAAAA==.Heladin:BAAANQADCggICAAAAA==.Helaku:BAAANQAECgQIBAAAAA==.Helbrecht:BAAANQADCgEIAQAAAA==.Hemogoblin:BAAANQADCgcIDQAAAA==.Hevharuk:BAAANQAECgMIAwAAAA==.Hewk:BAAANQADCggIFQAAAA==.',
Ho='Hogslight:BAAANQADCgcIBwAAAA==.Homerism:BAAANQADCgYIDgAAAA==.Hoofhearted:BAAANQADCgYIBwAAAA==.Hotanimemoms:BAAANQADCgMIAwAAAA==.',
Hu='Huntrhen:BAAANQADCgIIAgABNQAECgQIBwABAAAAAA==.',
Hy='Hybris:BAAANQAECgEIAQAAAA==.',
Il='Illidares:BAAANQAECgYICwAAAA==.',
Im='Implosion:BAAANQADCgcIEAAAAA==.Imwarminside:BAAANQAECgYIBwAAAA==.',
In='Innerrage:BAAANQAECgQIBQAAAA==.',
Ir='Ireliae:BAAANQAECgQIBAABNQAECgcIEAABAAAAAA==.Irnakk:BAAANQADCggIEAAAAA==.',
Is='Isaria:BAAANQADCgIIAgAAAA==.Iside:BAAANQADCgYIBwABNQAECgEIAQABAAAAAA==.Isindril:BAAANQAECgUICgAAAA==.Isnacky:BAAANQADCgYICwAAAA==.',
Ja='Jackforever:BAAANQAECgEIAQAAAA==.Jadianarcane:BAAANQAECgYIBwAAAA==.Jameswarren:BAAANQADCgYIDgAAAA==.Jannik:BAAANQAECgYICwAAAA==.',
Je='Jenntly:BAAANQAECgEIAQABNQAECgcIEAABAAAAAA==.Jessibel:BAAANQADCgUICQAAAA==.',
Ji='Jirasia:BAAANQAECgUICgAAAA==.',
Jm='Jmart:BAAANQAECgIIAgAAAA==.',
Jo='Joedalok:BAAANQADCgYIEAABNQAECgUIDAABAAAAAA==.Joedamonk:BAAANQAECgUIDAAAAA==.Jovat:BAAANQADCgYICgAAAA==.',
Ju='Jundras:BAAANQADCggIEQAAAA==.Juniormintz:BAAANQADCggIFgAAAA==.',
Ka='Kadryck:BAAANQADCgcIDwABNQAECgMIBQABAAAAAA==.Kageriyu:BAAANQAECgcIDAAAAA==.Kalmo:BAAANQAECgQIBgAAAA==.Kano:BAAANQADCgYIDAABNQADCggICAABAAAAAA==.Kanomoonbark:BAAANQADCgcIBwABNQADCggICAABAAAAAA==.Kanorexia:BAAANQADCggICAAAAA==.Kaotika:BAAANQAECgEIAQAAAA==.Kas:BAAANQADCgYIBgAAAA==.Kassira:BAAANQABCgMIAwAAAA==.Kayla:BAAANQADCggICgAAAA==.',
Ke='Keatøn:BAAANQADCggIDAAAAA==.Kegsmash:BAAANQADCgYIBgABNQADCgYIBgABAAAAAA==.Kelethius:BAAANQAECgcIEQAAAA==.Kerek:BAAANQADCgMIAwAAAA==.Kesthus:BAAANQAECgYICAAAAA==.Keystonelite:BAAANQAECgUICgAAAA==.Kezyah:BAAANQADCgYIDwAAAA==.',
Kh='Khatrina:BAAANQADCgUIBQAAAA==.Khârn:BAAANQADCgYICwAAAA==.',
Ki='Kirkitin:BAAANQADCgQIBAAAAA==.',
Kl='Klaustralus:BAAANQADCgcIDQAAAA==.',
Kn='Knaan:BAAANQADCggIEQAAAA==.',
Ko='Koohwip:BAABNQAFFIEIAAIJAAYJhgK1AQCeAQAJAAYJhgK1AQCeAQAAAA==.Kotarian:BAAANQADCgUIBQAAAA==.',
Ku='Kungflupanda:BAAANQAECgYICAABNQADCgEIAQABAAAAAA==.Kuruk:BAAANQADCgYICwAAAA==.',
['Kà']='Kànkàn:BAAANQAECgIIAgAAAA==.Kàylee:BAAANQAECgIIBAAAAA==.',
La='Lagaris:BAAANQADCggIFQAAAA==.Lampz:BAAANQAECgMIAwAAAA==.Lamue:BAAANQADCggICAAAAA==.Landaros:BAAANQADCgYICwAAAA==.Lariniira:BAAANQADCggIDgAAAA==.Lastdance:BAAANQAECggICwAAAA==.Laveda:BAAANQADCgcICAAAAA==.Lawgrus:BAAANQADCggICAABNQADCggICAABAAAAAA==.',
Ld='Ldycathlyn:BAAANQADCgEIAQAAAA==.',
Le='Leesylock:BAAANQAECgIIAgAAAA==.Letri:BAAANQAECgQIBgAAAA==.Leyland:BAAANQADCgMIAwAAAA==.',
Li='Libnorathis:BAAANQAECggIDQAAAA==.Licheternal:BAAANQAECgcIEAAAAA==.Lightwolves:BAAANQAFFAEIAQAAAA==.Limeaide:BAAANQAECgMIBAAAAA==.Liminalys:BAAANQADCggIEQAAAA==.',
Lo='Lockrhen:BAAANQAECgQIBwAAAA==.Lonsoo:BAAANQADCgUIBQAAAA==.Lotharion:BAAANQADCgcICQAAAA==.Lovelydeäth:BAAANQAECgUICgAAAA==.',
Lu='Lucitra:BAAANQABCgQIBAAAAA==.Luckeecharmz:BAAANQADCgYIBgAAAA==.Lunabell:BAAANQAECgcICAAAAA==.',
Ly='Lycealon:BAAANQABCgQIBAAAAA==.',
['Lé']='Léf:BAAANQAECgMIAwAAAA==.',
['Lï']='Lïlith:BAAANQADCggICAAAAA==.',
Ma='Madbad:BAAANQAECgIIAgAAAA==.Maidermaider:BAAANQADCgQICAAAAA==.Maimgor:BAAANQADCggIEQAAAA==.Makubai:BAAANQAECgEIAQAAAA==.Malza:BAAANQAECgMIAwAAAA==.Malzahar:BAAANQADCgYICAAAAA==.Mamamaya:BAAANQAECgcIDQAAAA==.Manawood:BAAANQAECgIIAgABNQAECgkJGQAKAFYhAA==.Mangodk:BAAANQAECgQIBgAAAA==.Maniic:BAAANQADCgcIEAAAAA==.Marien:BAAANQAECgEIAQABNQAECgQIBQABAAAAAA==.Marre:BAAANQAECgUICwAAAA==.Matabei:BAAANQAECgQIBwAAAA==.Mater:BAAANQADCgYICQAAAA==.Matsuda:BAAANQAECgYICwAAAA==.Mavralara:BAAANQADCgYICgAAAA==.Mawea:BAAANQAECgQIBQAAAA==.Maxious:BAAANQAECgIIAgAAAA==.',
Mc='Mcfrown:BAAANQAECgEIAQAAAA==.Mclight:BAAANQAECgMIAwAAAA==.',
Me='Mechamonk:BAAANQADCggIFAAAAA==.Megumïn:BAAANQAECgQIBAAAAA==.Meinfrau:BAAANQADCgIIAgABNQAECgQIBgABAAAAAA==.Melvin:BAAANQAECgMIBQAAAA==.Mercurý:BAAANQADCgYICQABNQAECgYIDQABAAAAAA==.Merlinsfire:BAAANQAECgIIAgAAAA==.Methingright:BAAANQADCgEIAQABNQAECgMIBQABAAAAAA==.',
Mi='Mightyraw:BAAANQADCgMIAwAAAA==.Mildfire:BAAANQADCgUIBQAAAA==.Milix:BAAANQADCgMIAwAAAA==.Mirima:BAAANQAECgIIAgAAAA==.',
Mk='Mknuttyy:BAAANQADCggIDAAAAA==.',
Mo='Mochafrap:BAAANQADCgUIBQAAAA==.Molly:BAAANQAECgEIAQAAAA==.Monsterman:BAAANQADCgUICgAAAA==.Moong:BAAANQAECgMIBAAAAA==.Morees:BAAANQADCggIEQAAAA==.',
Ms='Mstrjonathan:BAAANQAECgMIAwAAAA==.',
Mu='Mungogo:BAAANQADCggIJwAAAA==.',
My='Myia:BAAANQADCgcIBwAAAA==.Mylan:BAAANQADCgIIAgAAAA==.',
Na='Nagrand:BAAANQAECgQIBwAAAA==.Naive:BAAANQADCgUIBQAAAA==.Naivete:BAAANQADCggICgAAAA==.Nalaria:BAAANQAECgUICQAAAA==.Nastiee:BAAANQAECgUIBwAAAA==.',
Ne='Neava:BAAANQABCgQIBAAAAA==.Necrofeelsya:BAAANQADCgcIBwAAAA==.Necromantic:BAAANQADCgQIBAAAAA==.Nemhea:BAABNQAECoEXAAILAAkJciIGAwB5AwALAAkJciIGAwB5AwAAAA==.',
Ng='Ngorongoro:BAAANQADCgYIDgAAAA==.',
Ni='Niame:BAAANQAECgEIAQAAAA==.Nillaice:BAAANQADCgYICQAAAA==.Nindar:BAAANQADCgUIBwAAAA==.Ninjakitten:BAAANQADCggICgAAAA==.',
No='Nobuddude:BAAANQAECgEIAQAAAA==.Noiscopiamo:BAAANQAECgYIBwAAAA==.',
Ny='Nyxiis:BAAANQADCgcIDQAAAA==.',
Oa='Oashian:BAAANQAECgUICAAAAA==.',
Ol='Oladra:BAAANQAECgIIBAAAAA==.',
Or='Orcishfury:BAAANQABCgYICgAAAA==.Orcrinds:BAAANQADCgYIBgAAAA==.Orgruun:BAAANQADCggICgAAAA==.Orr:BAAANQADCggIEgAAAA==.Orrindan:BAAANQAECgMIBAAAAA==.',
Os='Osy:BAAANQABCgQIBgABNQADCggICgABAAAAAA==.',
Pa='Palaneer:BAAANQADCgYICgAAAA==.Pallieguy:BAAANQADCggICgAAAA==.Pandu:BAAANQADCggICAAAAA==.Patience:BAAANQAECgEIAQAAAA==.',
Pe='Peachtea:BAAANQAECgQIAwAAAA==.Penetrate:BAAANQAECgUICAAAAQ==.Pennyg:BAAANQADCgYIBgAAAA==.',
Ph='Pharoahe:BAAANQADCgYIBgABNQAECgYICwABAAAAAA==.Phett:BAAANQADCgQICAAAAA==.Philippe:BAAANQAECgEIAQAAAA==.Philo:BAAANQAECgQIBwAAAA==.Phineasflame:BAAANQADCgUIBwAAAA==.Phorsworn:BAAANQADCgYIBgAAAA==.',
Pi='Picard:BAAANQAECgYICwAAAA==.Piggymaru:BAAANQAECgIIAgAAAA==.Pikkin:BAAANQADCggIEAAAAA==.Pincushion:BAAANQAECgIIAgAAAA==.',
Pl='Plagues:BAAANQADCggIFQAAAA==.',
Po='Potaters:BAAANQADCgYIBgAAAA==.',
Pr='Prel:BAAANQAECgEIAQAAAA==.Princia:BAAANQADCgcIDwAAAA==.',
Ps='Psynoria:BAAANQAECgIIAgAAAA==.',
Pu='Pu:BAAANQAECgEIAQAAAA==.',
Py='Pyrose:BAAANQADCgcIEAAAAA==.Pyrowarrior:BAAANQADCggICwAAAA==.',
['Pó']='Póe:BAAANQAECgMIAwAAAA==.',
Qi='Qiteag:BAAANQADCggIEQABNQAECgIIAgABAAAAAA==.',
Qk='Qkcomputer:BAAANQADCgMIAwABNQAECgIIAgABAAAAAA==.',
Qz='Qzymandia:BAAANQAECgIIAgAAAA==.',
Ra='Rah:BAAANQAECgQIBAAAAA==.Raiset:BAAANQAECgMIAwAAAA==.Ramattra:BAAANQADCgcIEwAAAA==.Rambler:BAAANQADCgUIBQAAAA==.Rambling:BAAANQAECgMIBAAAAA==.Rawrp:BAAANQADCggICgAAAA==.',
Re='Recquency:BAAANQADCgMIBAAAAA==.Rekue:BAAANQADCgYICwABNQAECgIIAgABAAAAAA==.Remisnekro:BAAANQADCgUIBgAAAA==.Rengarage:BAAANQAECgEIAQAAAA==.Reshe:BAAANQADCgQIBAAAAA==.Reyortsed:BAAANQADCgIIAgAAAA==.',
Rh='Rhiandali:BAAANQAECgMIAwAAAA==.Rhiasith:BAAANQADCgYICwABNQAECgMIAwABAAAAAA==.Rhonna:BAAANQADCggIEwAAAA==.Rhyxi:BAAANQADCggICgAAAA==.',
Ri='Riloah:BAAANQAECgQIBAAAAA==.Riptide:BAAANQADCgYICwABNQAECgMIBQABAAAAAA==.Rizon:BAAANQADCggIFQAAAA==.',
Ro='Rocks:BAAANQABCgIIAgAAAA==.Rollis:BAAANQAECgEIAgAAAA==.Royalreishi:BAAANQABCgQIBAAAAA==.',
Ru='Rubedö:BAAANQADCgcICwAAAA==.Ruckyss:BAAANQADCgYIBgAAAA==.Runedorgasm:BAAANQAECgIIAgAAAA==.Rusâ:BAAANQAECgEIAQAAAA==.',
Ry='Ryobie:BAAANQADCgYIBgAAAA==.',
Sa='Saladriel:BAAANQAECgUICQAAAA==.Salandria:BAAANQAECgUICwAAAA==.Sandeoki:BAAANQADCgUICQAAAA==.Sandz:BAAANQADCgQIBwAAAA==.Sanguinex:BAAANQADCgQIBAAAAA==.Sanlien:BAAANQAECgUIBwAAAA==.Sarif:BAAANQADCgQICAAAAA==.Sarithrä:BAAANQADCgEIAQAAAA==.Sathona:BAAANQAECgQIBQABNQAECgYIBgABAAAAAA==.Satsa:BAAANQADCggIFQAAAA==.Savagedoodle:BAAANQAFFAEIAQAAAA==.',
Sc='Scooters:BAAANQADCgUIBwAAAA==.',
Se='Seidhra:BAAANQAECgMIBQAAAA==.Seiza:BAAANQAECgQIBAAAAA==.Sekhmet:BAAANQAECgEIAQAAAA==.Selenax:BAAANQADCgQIBwABNQAECgQIBwABAAAAAA==.Seriola:BAAANQADCgQIBQAAAA==.',
Sg='Sgtdoom:BAAANQADCgIIAgAAAA==.',
Sh='Shabs:BAAANQADCggIDwAAAA==.Shaburger:BAAANQAECgIIAgABNQAECgYIBwABAAAAAA==.Shalash:BAAANQADCgIIAgAAAA==.Shalisaura:BAAANQAECgEIAQABNQAECgQIBwABAAAAAA==.Shamania:BAAANQADCgMIAwAAAA==.Shamleesy:BAAANQADCgYICAABNQAECgIIAgABAAAAAA==.Shataco:BAAANQAECgEIAQAAAA==.Shemonoma:BAAANQADCgQIBgABNQADCggIFgABAAAAAA==.Shinjii:BAAANQADCggICAAAAA==.Shinysuicune:BAAANQAECgEIAQAAAA==.Shivrael:BAAANQADCggICAAAAA==.Showpup:BAAANQADCgUICgAAAA==.',
Si='Silvernightz:BAAANQADCgYICwAAAA==.Sinbreaker:BAAANQAECgIIAgAAAA==.',
Sk='Skaddamoosh:BAAANQAECgQIBQAAAA==.',
Sl='Sladecraven:BAAANQAECgEIAQAAAA==.Slopmelon:BAAANQADCggICgAAAA==.Slowdeath:BAAANQADCgYICAAAAA==.Slícedbread:BAAANQADCgQIBAABNQAECgkJFgAMAMIYAA==.',
Sm='Smøkechedda:BAAANQADCggIDgAAAA==.',
Sn='Snuffduck:BAAANQAECgUICgAAAA==.Snugglbooty:BAAANQADCggIDgAAAA==.Snugglebuns:BAAANQADCgIIAgAAAA==.Snuggletushy:BAAANQADCgIIAgAAAA==.',
So='Sodem:BAAANQADCggICgAAAA==.Sorrentoone:BAAANQADCgYIDgAAAA==.Sorta:BAAANQAECgUICgAAAA==.Sothoth:BAAANQABCgUIBwAAAA==.',
Sp='Spankinstein:BAAANQAECgYICQABNQAECgYICwABAAAAAA==.Spellbraker:BAAANQAECgMIBAAAAA==.Spinraux:BAAANQADCgcICgAAAA==.Spookyvibes:BAAANQAECgEIAQAAAA==.',
St='Stanojustice:BAAANQADCgYICgAAAA==.Starburstz:BAAANQADCgYIEAAAAA==.Starknight:BAAANQAFFAIIAgAAAA==.Staywokee:BAAANQAECgUIDgAAAA==.Stilits:BAAANQADCgYICwABNQAECgEIAQABAAAAAA==.Stinkyguy:BAAANQAECgEIAQAAAA==.Stolenblight:BAAANQADCgUICgAAAA==.Streamline:BAAANQAECgYIEAAAAA==.Strife:BAAANQAECggIAQAAAA==.',
Su='Suavemuerte:BAAANQABCgYICgAAAA==.',
Sw='Swagnasty:BAAANQAECgcIEAAAAA==.',
Sy='Sydarais:BAAANQAECgIIAgAAAA==.Sylshadow:BAAANQADCgEIAQAAAA==.',
Ta='Takua:BAAANQAECgEIAQAAAA==.Taleya:BAAANQAECgQIBgAAAA==.Tanarumn:BAAANQAECgEIAQAAAA==.Tanilyn:BAAANQADCgUIBQAAAA==.Tarryn:BAAANQADCgUIBwAAAA==.',
Te='Teahupoo:BAAANQADCgUIBwAAAA==.Tennesil:BAAANQADCgEIAQAAAA==.Tenraiyoshi:BAAANQADCgIIAgAAAA==.Terrorblades:BAAANQADCggICAABNQAECgYICwABAAAAAA==.Tevye:BAAANQAECgEIAQAAAA==.',
Th='Theßrush:BAAANQAECgEIAQAAAA==.Thorag:BAAANQADCgEIAQABNQAECgYICwABAAAAAA==.Thornlox:BAAANQADCggICgAAAA==.Thorwal:BAAANQADCgEIAQAAAA==.Thorzak:BAAANQAECgYIBwAAAA==.Threeplates:BAAANQAECgcIEwAAAA==.',
Ti='Tiktik:BAAANQAECgQIBAAAAA==.Tiktikmage:BAAANQAECgIIAgAAAA==.Tiltz:BAAANQADCggIFQAAAA==.',
To='Toptree:BAAANQADCgUIBgAAAA==.Topétine:BAAANQADCggIEwAAAA==.',
Tr='Traskk:BAAANQADCggIEgAAAA==.Trelious:BAAANQAECgEIAQAAAA==.Trenet:BAAANQADCgUIBQAAAA==.Trist:BAAANQADCgYIBgAAAA==.Truid:BAAANQAECgEIAQAAAA==.Tryel:BAAANQAECgcIDgAAAA==.Trínídad:BAAANQAECgIIAgAAAA==.',
Tu='Tuaca:BAAANQABCgIIAgAAAA==.Turdsmasher:BAAANQAECgEIAQAAAA==.Turumbar:BAAANQAECgIIAgAAAA==.',
Tw='Twysted:BAAANQAECgMIBAAAAA==.',
Ty='Tybeross:BAAANQAECgEIAQAAAA==.Tyrtwo:BAAANQADCgYICwAAAA==.',
Ul='Ultrazord:BAAANQADCgYIDgAAAA==.',
Un='Unholynight:BAAANQADCgcIEAAAAA==.',
Ur='Urosh:BAAANQABCgYIBgAAAA==.',
Va='Vaks:BAAANQAECgcICQAAAA==.Valantriç:BAAANQAECgMIAwAAAA==.Valkormyr:BAAANQAECgEIAQAAAA==.Vanishingson:BAAANQADCggIFgAAAA==.Varaldori:BAAANQADCgIIAgAAAA==.Varuguard:BAAANQADCgYIDAABNQADCggIDwABAAAAAA==.Vaylkyrie:BAAANQADCgUIBQAAAA==.',
Ve='Velell:BAAANQADCgYICwAAAA==.Venomsnake:BAAANQADCgcIEAAAAA==.Venura:BAAANQAECgIIAgAAAA==.Verelidaine:BAABNQAECoEYAAINAAkJRiLAAgB3AwANAAkJRiLAAgB3AwAAAA==.Vessper:BAAANQAECgYICwAAAA==.Vexmama:BAAANQADCgEIAQAAAA==.',
Vh='Vheigar:BAAANQADCgEIAQAAAA==.',
Vi='Viabelle:BAAANQAECgIIAgAAAA==.Vicious:BAAANQADCgMIAwAAAA==.Victor:BAAANQAECgEIAQAAAA==.',
Vo='Voidglazer:BAAANQAECgEIAQAAAA==.Vorvadoss:BAAANQADCgUIBQABNQADCgYICgABAAAAAA==.Vosik:BAAANQADCgUIDQAAAA==.Voxxy:BAAANQADCgUIBQABNQADCgMIAwABAAAAAA==.',
Vy='Vyne:BAAANQADCgQIBAAAAA==.',
Wa='Wafsei:BAAANQADCggIDwAAAA==.',
We='Welcor:BAAANQADCgEIAQABNQAECgUIBwABAAAAAA==.Welkor:BAAANQAECgEIAQABNQAECgUIBwABAAAAAA==.',
Wh='Whammyshammy:BAAANQADCgUIBQAAAA==.Whew:BAAANQADCgIIAgAAAA==.',
Wi='Wickebone:BAAANQABCgQIAgAAAA==.Wildheart:BAAANQADCgMIAwAAAA==.Wiligoldi:BAAANQAECgEIAgAAAA==.Withsauce:BAAANQAECgEIAQAAAA==.',
Wo='Wolfram:BAAANQADCgQIBAAAAA==.Woodish:BAABNQAECoEZAAMKAAkJViHHBwBvAwAKAAkJViHHBwBvAwAOAAEJcgzrFAA+AAAAAA==.',
['Wä']='Wäyz:BAAANQADCggIBAABNQADCggIFQABAAAAAA==.',
Xa='Xanbar:BAAANQADCggICgAAAA==.Xandent:BAAANQADCggIDgAAAA==.Xanju:BAAANQAECgYICwAAAA==.Xanothar:BAAANQADCgIIAgAAAA==.Xarc:BAAANQADCgMIAQAAAA==.Xarnlu:BAAANQADCgEIAQABNQAECgQIDAABAAAAAA==.',
Xe='Xep:BAAANQAECgYIDAAAAA==.',
Xi='Xinkz:BAAANQADCggICgAAAA==.',
Xu='Xunji:BAAANQADCgYIBgAAAA==.',
Ya='Yaariissa:BAAANQADCgMIBAAAAA==.',
Yl='Ylliria:BAAANQAECgQIBwAAAA==.',
Yo='Yourholyness:BAAANQADCggIDwAAAA==.',
Ys='Yso:BAAANQADCggICgAAAA==.',
Za='Zaletra:BAAANQADCggICAAAAA==.Zalil:BAAANQADCggIEQAAAA==.Zarcyna:BAABNQAECoEXAAMGAAkJMCPiAwA1AwAGAAgJrSLiAwA1AwAHAAQJcyN9FwB3AQAAAA==.Zathoron:BAAANQAECgYICwAAAA==.',
Ze='Zenfox:BAAANQAECgYICgAAAA==.',
Zi='Ziatora:BAAANQAECgMIBQAAAA==.Zimmy:BAAANQADCggIDQAAAA==.',
Zo='Zosh:BAAANQABCgQIBQAAAA==.',
Zu='Zultaj:BAAANQADCggIEAAAAA==.Zumwalathas:BAAANQADCgYIBgAAAA==.',
['Àr']='Àriýa:BAAANQAECgIIAgAAAA==.',
['Âs']='Âstryl:BAAANQADCgYIBgAAAA==.',
['Ãs']='Ãstryl:BAAANQADCgEIAQAAAA==.',
['Är']='Ärth:BAAANQADCgYICQAAAA==.',
['Äs']='Ästryl:BAAANQADCgIIAwAAAA==.',
['Çç']='Çç:BAAANQAECgEIAQAAAA==.',
['Èu']='Èugene:BAAANQADCgUIBQAAAA==.',
['Ëv']='Ëvan:BAAANQADCggICgAAAA==.',
['Ða']='Ðarrow:BAAANQAECgUIBgAAAA==.',
['Öm']='Ömni:BAAANQADCgUIBQAAAA==.',
['Öu']='Öutßreak:BAAANQADCggIDwAAAA==.',
['Ûl']='Ûllr:BAAANQADCgYICQAAAA==.',
['Ûn']='Ûnwise:BAAANQAECgQIBwAAAA==.',
['ßa']='ßaroness:BAAANQAECgQIBQAAAA==.',
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
