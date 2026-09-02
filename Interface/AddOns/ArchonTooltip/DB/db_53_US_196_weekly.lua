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
local provider = {region='US',realm='Silvermoon',name='US',type='weekly',zone=53,date='2026-09-01',data={Aa='Aakura:BAAANQAECgQIBQAAAA==.Aamira:BAAANQADCgUIBQAAAA==.Aaravas:BAAANQADCgIIAgAAAA==.Aarcadia:BAAANQADCgUICQAAAA==.',
Ad='Adamantus:BAAANQADCgYICQAAAA==.',
Ae='Aelasong:BAAANQADCgcIDQAAAA==.Aelioran:BAAANQADCggIDgAAAA==.Aenlor:BAAANQADCgYICQAAAA==.Aestar:BAAANQADCgYIBwAAAA==.',
Ai='Airedhiel:BAAANQADCgMIAwAAAA==.',
Al='Alacantos:BAAANQAECgEIAQAAAA==.Alanjackson:BAAANQADCgUIBwAAAA==.Alawyn:BAAANQAECgQIBQAAAA==.Alayssaria:BAAANQADCggIDgAAAA==.Alcana:BAAANQADCgQIBAAAAA==.Alexstrazett:BAAANQADCgMIBAAAAA==.Alextros:BAEANQADCgUIBQABNQAECgEIAQABAAAAAA==.Alltaken:BAAANQADCgUICQAAAA==.Alpharetta:BAAANQAECgcIDAABNQAECggIDQABAAAAAA==.Alsera:BAAANQADCgQIAQAAAA==.',
Am='Amarae:BAAANQADCgYIBgAAAA==.Amicoolyet:BAAANQADCgYICQAAAA==.Ammon:BAAANQADCgIIAgAAAA==.Amorene:BAAANQAECgcICgAAAA==.Amorvane:BAAANQADCggICAABNQAECgcICgABAAAAAA==.Amoryn:BAAANQADCgEIAQABNQAECgcICgABAAAAAA==.',
An='Anaraellea:BAAANQADCgMIBAAAAA==.Angellena:BAAANQADCggIDQAAAA==.Anian:BAAANQADCgUIBgAAAA==.Antadin:BAAANQADCggIDgAAAA==.',
Ap='Apherilia:BAAANQADCggIDwAAAA==.',
Ar='Aranos:BAAANQADCgUIBgAAAA==.Ardrick:BAAANQADCgYIBQAAAA==.Arihua:BAAANQADCgEIAQAAAA==.Arkano:BAAANQADCgYIBgAAAA==.Aronau:BAAANQADCgUICgAAAA==.Arosen:BAAANQADCgQIBAAAAA==.Artforidiots:BAAANQADCggIDwAAAA==.Arthurious:BAAANQADCgQIBAAAAA==.',
As='Asenath:BAAANQADCggIDgAAAA==.Asmodeus:BAAANQAECgMIAwAAAA==.Aspect:BAAANQAECgEIAQAAAA==.Astraeâ:BAAANQADCgYIBgAAAA==.',
Av='Avacado:BAAANQADCgIIAgABNQAFFAIIAwABAAAAAA==.Avicularia:BAAANQADCgYIBgAAAA==.',
Aw='Awake:BAAANQADCgYIBgAAAA==.',
Ax='Axdk:BAAANQADCggIDgAAAA==.',
Ay='Ayalha:BAAANQAECgQIBAAAAA==.',
Ba='Babychewie:BAAANQAECgEIAQAAAA==.Balla:BAAANQADCgcIDQAAAA==.Bambismash:BAAANQADCgMIAwAAAA==.',
Be='Beansgreens:BAAANQADCgMIBAAAAA==.Beantism:BAAANQADCggIDgAAAA==.Beardeath:BAAANQAECgEIAQAAAA==.Bearleft:BAAANQABCgQIBQAAAA==.Beaross:BAAANQAECgEIAQAAAA==.Beeflomein:BAAANQAECgEIAQAAAA==.Beledros:BAAANQAECgQIBwABNQAECgEIAgABAAAAAA==.',
Bi='Bigeasy:BAAANQADCgYICQAAAA==.',
Bl='Blakkadin:BAAANQADCgQIBAABNQAECgYICAABAAAAAA==.Blayzn:BAAANQADCgUIAwAAAA==.Bloodychêwy:BAAANQADCgcIBwAAAA==.Blutdurst:BAAANQADCgMIBAAAAA==.',
Bo='Bojammies:BAAANQADCgMIBQAAAA==.Bombad:BAAANQADCggICAABNQAECgcIDAABAAAAAQ==.Bonelargeles:BAAANQAECgMIAQAAAA==.Booyaah:BAAANQAECggICQAAAA==.Boulderbro:BAAANQADCgEIAQAAAA==.',
Br='Brigade:BAAANQAECgYICQAAAA==.Brigadester:BAAANQAECgYICQAAAA==.Brogaine:BAAANQADCgMIAwAAAA==.Broodin:BAAANQADCgYIBwAAAA==.',
Bu='Bullbas:BAAANQADCgEIAQAAAA==.Bumdog:BAAANQADCggICwAAAA==.',
Ca='Calrisa:BAAANQAECgQIBAAAAQ==.Camin:BAAANQADCgQIBAAAAA==.Carltonhoot:BAAANQADCgMIAwAAAA==.Cassadk:BAAANQADCggIDgAAAA==.Cassapedia:BAAANQADCgUIBQABNQADCggIDgABAAAAAA==.Cassawings:BAAANQADCgUICQABNQADCggIDgABAAAAAA==.',
Ce='Celestria:BAAANQAECgEIAQAAAA==.Celna:BAAANQADCgUICgAAAA==.Celyssia:BAAANQADCgYIBgAAAA==.Cernos:BAAANQADCgYICgAAAA==.',
Ch='Chance:BAAANQAECgQIBQAAAA==.Chardclass:BAAANQADCggIEAABNQAECgcIDQABAAAAAA==.Charzard:BAAANQADCgcIBwAAAA==.Cheerio:BAAANQADCgYICgAAAA==.Cheezit:BAAANQADCggICAAAAA==.',
Cl='Clömp:BAAANQAECgEIAQAAAA==.',
Co='Coreion:BAAANQADCgYIBgAAAA==.',
Cr='Crimsonmist:BAAANQAECgQIDAAAAA==.Crisstos:BAAANQADCgMIBAAAAA==.Cristhel:BAAANQAECgEIAQAAAA==.Critneyfearz:BAAANQADCgYIBgAAAA==.Crusk:BAAANQADCgYICQAAAA==.',
Cs='Csg:BAAANQADCgYIBgAAAA==.',
Cy='Cyllene:BAAANQADCgMIBAAAAA==.',
['Cé']='Cérnunnos:BAAANQAECgEIAQAAAA==.',
Da='Daemonslayer:BAAANQADCgcIDQAAAA==.Daftknight:BAAANQAECgEIAQAAAA==.Daisycutter:BAAANQAECgIIAgAAAA==.Dakoo:BAAANQADCgIIAgAAAA==.Daluon:BAAANQABCgIIAgABNQAECgEIAQABAAAAAA==.Dances:BAAANQADCgYICQAAAA==.Daravanthel:BAAANQADCgQIBAAAAA==.Daresh:BAAANQADCgcIDQABNQAECgQIBQABAAAAAA==.Darkbeast:BAAANQAECgEIAQAAAA==.Darkbáine:BAAANQAECgQIBAAAAA==.Darkdarion:BAAANQABCgMIAwAAAA==.Darling:BAAANQAECgUIBQAAAA==.Darmorg:BAAANQAECgUIBwAAAA==.Darthaxe:BAAANQAECggIDAAAAA==.Dazzlok:BAAANQADCgIIAgAAAA==.',
De='Deathsurge:BAAANQAECgEIAQAAAA==.Deegoddaem:BAAANQADCgMIAwAAAA==.Delacour:BAEANQAECgYICgABNQADCggIDQABAAAAAA==.Derkaus:BAAANQAECgEIAQAAAA==.Dev:BAAANQADCgQIBAAAAA==.Dezz:BAAANQAECgIIAgAAAA==.Dezza:BAAANQADCgQIBAAAAA==.',
Dh='Dharenar:BAAANQAECgQIBQAAAA==.',
Di='Dizzyflores:BAAANQADCggIDgAAAA==.',
Dj='Djguckie:BAAANQADCgYICgAAAA==.',
Dk='Dkordis:BAAANQADCgMIAwAAAA==.',
Dn='Dnyce:BAAANQADCgQIBQAAAA==.',
Do='Doomcore:BAAANQAECgEIAQAAAA==.Dooper:BAAANQAECgQIBgAAAA==.Doshneil:BAAANQADCgUIBwAAAA==.',
Dr='Dragongor:BAAANQADCgYICQAAAA==.Dragonsmight:BAAANQAECgQIBAAAAA==.Dreamvore:BAAANQAECgQIBQAAAA==.Droknarr:BAAANQABCgIIAwAAAA==.Droø:BAAANQADCgEIAQAAAA==.',
Du='Dualwield:BAAANQADCgcIDAAAAA==.Dustobones:BAAANQAECgMIBQAAAA==.',
Dw='Dweedy:BAAANQADCgMIAwAAAA==.',
El='Eliyana:BAAANQADCggIDAAAAA==.Elm:BAAANQADCgcIDwAAAA==.Elsiñd:BAAANQADCggIDgAAAA==.Eluniel:BAAANQAECgEIAgAAAA==.',
Em='Emberdk:BAAANQAECgcIDQAAAA==.Emojones:BAAANQADCgYICQAAAA==.Empyreal:BAAANQADCgYICgAAAA==.',
Ep='Ephysa:BAAANQADCgYICAAAAA==.',
Er='Erasra:BAAANQAECgIIAgAAAA==.',
Es='Essenne:BAAANQADCgUICgABNQADCggIDgABAAAAAA==.',
Et='Etali:BAAANQADCgQIBAABNQAECgEIAgABAAAAAA==.Etrigg:BAAANQADCgIIAgAAAA==.',
Ex='Exstatik:BAAANQAECgEIAQAAAA==.',
Ey='Eyeamgroot:BAAANQADCgQIBQAAAA==.',
Ez='Ezzrra:BAAANQAECgEIAQAAAA==.',
Fa='Faelunae:BAAANQADCgEIAQAAAA==.Faillock:BAAANQAECgcIDAAAAA==.Falora:BAAANQADCgMIAwAAAA==.Fangshot:BAAANQADCgcIDAAAAA==.',
Fe='Felraux:BAAANQADCgEIAQAAAA==.Fengbao:BAAANQADCggIDgAAAA==.Fezzik:BAAANQADCgQIBAAAAA==.',
Fi='Filthydegén:BAAANQADCgQIBQAAAA==.Finnior:BAAANQADCgEIAQAAAA==.Fionnaghuala:BAAANQADCgQIBAABNQAECgMIAwABAAAAAA==.Firedemon:BAAANQADCgYICgAAAA==.Fishspells:BAAANQAECgYICAAAAA==.',
Fl='Flashfrozen:BAAANQADCgcIBwAAAA==.Flute:BAAANQAECgQIBQAAAA==.',
Fr='Frayden:BAAANQADCggIDQAAAA==.Frizmo:BAAANQADCgMIAwAAAA==.Frogprincess:BAAANQADCgYICQAAAA==.Frontdeboeuf:BAAANQADCgYICwAAAA==.Frozaller:BAAANQADCgEIAQAAAA==.',
Fu='Fuilsidhe:BAAANQADCgYIDAAAAA==.Furricane:BAAANQADCgEIAQAAAA==.',
Ga='Gadios:BAAANQAECgYICQAAAA==.Gaiyia:BAAANQADCgYICwAAAA==.Galebjorn:BAAANQAECgQICQAAAA==.Garfna:BAAANQADCgcICAAAAA==.Garfrost:BAAANQADCgIIAgAAAA==.Gascoigne:BAAANQADCgYIBgAAAA==.',
Ge='Gencil:BAAANQADCgUIBwAAAA==.',
Gi='Gizzimo:BAAANQADCgMIAwAAAA==.',
Go='Goobr:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Goover:BAAANQADCgcIDAAAAA==.Gosu:BAAANQADCgYICwAAAA==.',
Gr='Gracelyn:BAAANQADCggIDgAAAA==.Graftin:BAAANQADCgYIBgAAAA==.Greener:BAAANQADCgUIBQAAAA==.Grezgara:BAAANQADCgYICQAAAA==.Griimace:BAAANQADCgcICgAAAA==.Grimoldone:BAAANQADCgcIDQAAAA==.Grimverdict:BAAANQADCgQIBQABNQAECgIIAgABAAAAAA==.Grinderrg:BAAANQAECgEIAQAAAA==.Grommashryon:BAAANQADCgcIDQAAAA==.Grumbledecay:BAAANQADCgYIBgAAAA==.Grumbledore:BAAANQAECgcIDAAAAA==.',
Gu='Gumbö:BAAANQAECgEIAQAAAA==.Guttzes:BAAANQADCgUICAAAAA==.',
['Gï']='Gïngersnaps:BAAANQADCgQIBAAAAA==.',
Ha='Halidril:BAAANQAECgEIAQAAAA==.Hanshiro:BAAANQADCgUIBQAAAA==.Hasel:BAAANQADCggICAAAAA==.Hawkhunter:BAAANQADCgUIBQAAAA==.Hazzazz:BAAANQADCgcICQAAAA==.',
He='Hearthbunny:BAAANQADCgYIBgAAAA==.Hegs:BAAANQAECgQIBAAAAA==.Helaku:BAAANQADCggICAAAAA==.Helbrecht:BAAANQADCgEIAQAAAA==.Hemogoblin:BAAANQADCgYIBgAAAA==.Hevharuk:BAAANQADCggIDgAAAA==.Hewk:BAAANQADCggIDgAAAA==.',
Ho='Homerism:BAAANQADCgUIBwAAAA==.Hoofhearted:BAAANQADCgIIAgAAAA==.',
Hu='Huntrhen:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.',
Hy='Hybris:BAAANQADCgYIBgAAAA==.',
Il='Illidares:BAAANQAECgQIBQAAAA==.',
Im='Implosion:BAAANQADCgYICQAAAA==.Imwarminside:BAAANQAECgYIBwAAAA==.',
In='Innerrage:BAAANQAECgEIAQAAAA==.',
Ir='Irnakk:BAAANQADCggIDgAAAA==.',
Is='Isaria:BAAANQADCgIIAgAAAA==.Iside:BAAANQADCgYIBwABNQADCgcIEQABAAAAAA==.Isindril:BAAANQAECgQIBQAAAA==.Isnacky:BAAANQADCgUIBQAAAA==.',
Ja='Jackforever:BAAANQAECgEIAQAAAA==.Jadianarcane:BAAANQAECgEIAQAAAA==.Jameswarren:BAAANQADCgUICAAAAA==.Jannik:BAAANQAECgQIBQAAAA==.',
Je='Jenntly:BAAANQAECgEIAQABNQAECgUICQABAAAAAA==.Jessibel:BAAANQADCgUIBQAAAA==.',
Ji='Jirasia:BAAANQAECgQIBQAAAA==.',
Jm='Jmart:BAAANQADCgcIBwAAAA==.',
Jo='Joedalok:BAAANQADCgYICgABNQAECgQIBwABAAAAAA==.Joedamonk:BAAANQAECgQIBwAAAA==.Jovat:BAAANQADCgUICAAAAA==.',
Ju='Jundras:BAAANQADCgYICQAAAA==.Juniormintz:BAAANQADCggIDgAAAA==.',
Ka='Kadryck:BAAANQADCgYICwABNQAECgIIAgABAAAAAA==.Kageriyu:BAAANQAECgQIBQAAAA==.Kalmo:BAAANQADCggIDQAAAA==.Kano:BAAANQADCgYIDAABNQADCgcIBwABAAAAAA==.Kanomoonbark:BAAANQADCgcIBwAAAA==.Kaotika:BAAANQADCgcIDQAAAA==.Kas:BAAANQADCgYIBgABNQADCgYIBgABAAAAAA==.Kassira:BAAANQABCgEIAQAAAA==.Kayla:BAAANQADCgIIAgAAAA==.',
Ke='Keatøn:BAAANQADCggIDAAAAA==.Kegsmash:BAAANQADCgYIBgAAAA==.Kelethius:BAAANQAECgYICgAAAA==.Kesthus:BAAANQAECgMIAwAAAA==.Keystonelite:BAAANQAECgQIBQAAAA==.Kezyah:BAAANQADCgUICQAAAA==.',
Kh='Khârn:BAAANQADCgQIBQAAAA==.',
Kl='Klaustralus:BAAANQADCgYIBgAAAA==.',
Kn='Knaan:BAAANQADCgUICAAAAA==.',
Ko='Koohwip:BAAANQAFFAIIAgAAAA==.Kotarian:BAAANQADCgUIBQAAAA==.',
Ku='Kungflupanda:BAAANQAECgIIAgABNQADCgEIAQABAAAAAA==.Kuruk:BAAANQADCgUIBQAAAA==.',
['Kà']='Kànkàn:BAAANQADCggICAAAAA==.Kàylee:BAAANQAECgIIAgAAAA==.',
La='Lagaris:BAAANQADCgcIDQAAAA==.Lampz:BAAANQADCgQIBAAAAA==.Lamue:BAAANQADCggICAAAAA==.Landaros:BAAANQADCgYICwAAAA==.Lariniira:BAAANQADCgUIBQAAAA==.Lastdance:BAAANQAECgMIAwABNQAECgQIDAABAAAAAA==.Laveda:BAAANQADCgEIAQAAAA==.',
Ld='Ldycathlyn:BAAANQADCgEIAQAAAA==.',
Le='Leesylock:BAAANQADCggIDwAAAA==.Letri:BAAANQAECgIIAgAAAA==.',
Li='Libnorathis:BAAANQAECgYIBwAAAA==.Licheternal:BAAANQAECgUICQAAAA==.Lightwolves:BAAANQAECgcICwAAAA==.Limeaide:BAAANQAECgEIAQAAAA==.Liminalys:BAAANQADCgYICQAAAA==.',
Lo='Lockrhen:BAAANQAECgMIAwAAAA==.Lotharion:BAAANQADCgcICQAAAA==.Lovelydeäth:BAAANQAECgQIBQAAAA==.',
Lu='Lucitra:BAAANQABCgQIBAAAAA==.Luckeecharmz:BAAANQADCgYIBgAAAA==.Lunabell:BAAANQAECgEIAQAAAA==.',
Ly='Lycealon:BAAANQABCgIIAgAAAA==.',
['Lé']='Léf:BAAANQADCgcIBwAAAA==.',
Ma='Madbad:BAAANQADCggIDgAAAA==.Maimgor:BAAANQADCgYICQAAAA==.Makubai:BAAANQADCgcIDQAAAA==.Malza:BAAANQADCggIDQAAAA==.Malzahar:BAAANQADCgYICAAAAA==.Mamamaya:BAAANQAECgYIBgAAAA==.Manawood:BAAANQADCggIDgABNQAECggIDgABAAAAAA==.Mangodk:BAAANQAECgIIAgAAAA==.Maniic:BAAANQADCgYICQAAAA==.Marien:BAAANQADCgYIDAABNQAECgIIAgABAAAAAA==.Marre:BAAANQAECgQIBgAAAA==.Matabei:BAAANQAECgMIAwAAAA==.Mater:BAAANQADCgYIBgAAAA==.Matsuda:BAAANQAECgQIBQAAAA==.Mavralara:BAAANQADCgMIBAAAAA==.Mawea:BAAANQAECgIIAgAAAA==.Maxious:BAAANQADCgcICwAAAA==.',
Mc='Mcfrown:BAAANQADCgcICQAAAA==.Mclight:BAAANQADCgcICgAAAA==.',
Me='Mechamonk:BAAANQADCgcIDAAAAA==.Megumïn:BAAANQADCgYIBgAAAA==.Meinfrau:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Melvin:BAAANQAECgIIAgAAAA==.Mercurý:BAAANQADCgYICQAAAA==.Methingright:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.',
Mi='Mightyraw:BAAANQADCgMIAwAAAA==.Milix:BAAANQADCgMIAwAAAA==.Mirima:BAAANQADCggIDgAAAA==.',
Mk='Mknuttyy:BAAANQADCgUIBAAAAA==.',
Mo='Mochafrap:BAAANQADCgUIBQAAAA==.Molly:BAAANQADCgYICgAAAA==.Monsterman:BAAANQADCgUICgAAAA==.Moong:BAAANQAECgIIAgAAAA==.Morees:BAAANQADCggIEQAAAA==.',
Ms='Mstrjonathan:BAAANQADCggIDgAAAA==.',
Mu='Mungogo:BAAANQADCgYIFwAAAA==.',
My='Mylan:BAAANQADCgIIAgAAAA==.',
Na='Nagrand:BAAANQADCgcIDgAAAA==.Naive:BAAANQADCgIIAgAAAA==.Naivete:BAAANQADCggICgAAAA==.Nalaria:BAAANQAECgQIBQAAAA==.Nastiee:BAAANQAECgIIAgAAAA==.',
Ne='Necromantic:BAAANQADCgQIBAAAAA==.Nemhea:BAAANQAFFAEIAQAAAA==.',
Ng='Ngorongoro:BAAANQADCgUICAAAAA==.',
Ni='Niame:BAAANQADCggIDgAAAA==.Nillaice:BAAANQADCgMIAwAAAA==.Nindar:BAAANQADCgIIAgAAAA==.Ninjakitten:BAAANQADCgIIAgAAAA==.',
No='Nobuddude:BAAANQADCgYICQAAAA==.Noiscopiamo:BAAANQAECgEIAQAAAA==.',
Ny='Nyxiis:BAAANQADCgYIDAAAAA==.',
Oa='Oashian:BAAANQAECgMIAwAAAA==.',
Ol='Oladra:BAAANQAECgEIAgAAAA==.',
Or='Orcrinds:BAAANQADCgYIBgAAAA==.Orgruun:BAAANQADCggICgAAAA==.Orr:BAAANQADCgYICgAAAA==.Orrindan:BAAANQAECgEIAQAAAA==.',
Os='Osy:BAAANQABCgQIBgABNQADCgIIAgABAAAAAA==.',
Pa='Pallieguy:BAAANQADCgIIAgAAAA==.Patience:BAAANQADCggIBAAAAA==.',
Pe='Penetrate:BAAANQAECgMIAwAAAQ==.Pennyg:BAAANQADCgYIBgAAAA==.',
Ph='Pharoahe:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.Phett:BAAANQADCgQIBAAAAA==.Philippe:BAAANQADCgcIDAAAAA==.Philo:BAAANQAECgMIAwAAAA==.Phineasflame:BAAANQADCgMIAwAAAA==.Phorsworn:BAAANQADCgYIBgAAAA==.',
Pi='Picard:BAAANQAECgQIBQAAAA==.Piggymaru:BAAANQADCggIDgAAAA==.Pikkin:BAAANQADCggICQAAAA==.Pincushion:BAAANQADCgcIDQAAAA==.',
Pl='Plagues:BAAANQADCgcIDQAAAA==.',
Pr='Prel:BAAANQAECgEIAQAAAA==.Princia:BAAANQADCgYICAAAAA==.',
Pu='Pu:BAAANQADCggIDgAAAA==.',
Py='Pyrose:BAAANQADCgYICQAAAA==.Pyrowarrior:BAAANQADCgcICQAAAA==.',
['Pó']='Póe:BAAANQADCgcIDAAAAA==.',
Qi='Qiteag:BAAANQADCgUICQABNQADCggIDgABAAAAAA==.',
Qk='Qkcomputer:BAAANQADCgMIAwABNQADCggIDgABAAAAAA==.',
Qz='Qzymandia:BAAANQADCggIDgAAAA==.',
Ra='Rah:BAAANQADCggICQAAAA==.Raiset:BAAANQADCggIDwAAAA==.Ramattra:BAAANQADCgcIDAAAAA==.Rambler:BAAANQADCgUIBQAAAA==.Rambling:BAAANQAECgIIAgAAAA==.Rawrp:BAAANQADCgIIAgAAAA==.',
Re='Recquency:BAAANQADCgMIAwAAAA==.Rekue:BAAANQADCgUIBQABNQADCggIDgABAAAAAA==.Remisnekro:BAAANQADCgEIAQAAAA==.Rengarage:BAAANQADCggICAAAAA==.Reshe:BAAANQADCgQIBAAAAA==.Reyortsed:BAAANQADCgIIAgAAAA==.',
Rh='Rhiandali:BAAANQADCggIDgAAAA==.Rhiasith:BAAANQADCgYICwABNQADCggIDgABAAAAAA==.Rhonna:BAAANQADCgYICwAAAA==.Rhyxi:BAAANQADCgIIAgAAAA==.',
Ri='Riloah:BAAANQADCggIDgAAAA==.Riptide:BAAANQADCgYICwABNQAECgEIAgABAAAAAA==.Rizon:BAAANQADCgcIDQAAAA==.',
Ro='Rollis:BAAANQAECgEIAQAAAA==.Royalreishi:BAAANQABCgQIBAAAAA==.',
Ru='Rubedö:BAAANQADCgYICQAAAA==.Runedorgasm:BAAANQADCgQIBAAAAA==.Rusâ:BAAANQADCggIDQAAAA==.',
Sa='Saladriel:BAAANQAECgQIBAAAAA==.Salandria:BAAANQAECgEIAQAAAA==.Sandeoki:BAAANQADCgUIBQAAAA==.Sandz:BAAANQADCgQIBwAAAA==.Sanlien:BAAANQAECgIIAgAAAA==.Sarif:BAAANQADCgIIBAAAAA==.Sarithrä:BAAANQADCgEIAQAAAA==.Sathona:BAAANQAECgQIBQABNQABCgIIAgABAAAAAA==.Satsa:BAAANQADCggIDQAAAA==.Savagedoodle:BAAANQAECgYICgAAAA==.',
Sc='Scooters:BAAANQADCgMIAwAAAA==.',
Se='Seidhra:BAAANQAECgIIAgAAAA==.Sekhmet:BAAANQADCgcIEQAAAA==.Selenax:BAAANQADCgQIBwABNQAECgMIAwABAAAAAA==.Seriola:BAAANQADCgQIBQAAAA==.',
Sg='Sgtdoom:BAAANQADCgIIAQAAAA==.',
Sh='Shabs:BAAANQADCggIDwAAAA==.Shaburger:BAAANQADCggIDgABNQAECgYIBwABAAAAAA==.Shalisaura:BAAANQADCgcIBwABNQAECgMIAwABAAAAAA==.Shamania:BAAANQADCgMIAwAAAA==.Shataco:BAAANQAECgEIAQAAAA==.Shemonoma:BAAANQADCgQIBAABNQADCggIDgABAAAAAA==.Showpup:BAAANQADCgUIBQAAAA==.',
Si='Silvernightz:BAAANQADCgYIBgAAAA==.Sinbreaker:BAAANQADCggIDAAAAA==.',
Sk='Skaddamoosh:BAAANQAECgEIAQAAAA==.',
Sl='Sladecraven:BAAANQADCgYICgAAAA==.Slopmelon:BAAANQADCgIIAgAAAA==.Slowdeath:BAAANQADCgYICAAAAA==.Slícedbread:BAAANQADCgQIBAABNQAECgcIDAABAAAAAA==.',
Sm='Smøkechedda:BAAANQADCggIDgAAAA==.',
Sn='Snuffduck:BAAANQAECgQIBQAAAA==.Snugglbooty:BAAANQADCggIDgAAAA==.Snugglebuns:BAAANQADCgIIAgAAAA==.Snuggletushy:BAAANQADCgIIAgAAAA==.',
So='Sodem:BAAANQADCgIIAgAAAA==.Sorrentoone:BAAANQADCgUICAAAAA==.Sorta:BAAANQAECgQIBQAAAA==.Sothoth:BAAANQABCgIIAgAAAA==.',
Sp='Spankinstein:BAAANQAECgMIAwABNQAECgQIBQABAAAAAA==.Spellbraker:BAAANQAECgEIAQAAAA==.Spinraux:BAAANQADCgMIAwAAAA==.Spookyvibes:BAAANQADCgUICQAAAA==.',
St='Stanojustice:BAAANQADCgMIBAAAAA==.Starburstz:BAAANQADCgYICgAAAA==.Starknight:BAAANQAECggICQAAAA==.Staywokee:BAAANQAECgQICQAAAA==.Stilits:BAAANQADCgYICwABNQADCggICAABAAAAAA==.Stinkyguy:BAAANQADCgIIAgAAAA==.Stolenblight:BAAANQADCgUIBQAAAA==.Streamline:BAAANQAECgQIBwAAAA==.Strife:BAAANQAECggIAQAAAA==.',
Su='Suavemuerte:BAAANQABCgQIBgAAAA==.',
Sw='Swagnasty:BAAANQAECgYICQAAAA==.',
Sy='Sydarais:BAAANQADCggIDgAAAA==.Sylshadow:BAAANQADCgEIAQAAAA==.',
Ta='Takua:BAAANQADCggICAAAAA==.Taleya:BAAANQAECgIIAgAAAA==.Tanarumn:BAAANQAECgEIAQAAAA==.Tarryn:BAAANQADCgMIAwAAAA==.',
Te='Teahupoo:BAAANQADCgMIAwAAAA==.Tennesil:BAAANQADCgEIAQAAAA==.Tenraiyoshi:BAAANQADCgIIAgAAAA==.Tevye:BAAANQADCgcIDAAAAA==.',
Th='Theßrush:BAAANQADCggICAAAAA==.Thorag:BAAANQADCgEIAQABNQAECgQIBQABAAAAAA==.Thornlox:BAAANQADCgIIAgAAAA==.Thorzak:BAAANQAECgEIAQAAAA==.Threeplates:BAAANQAECgYIDAAAAA==.',
Ti='Tiktik:BAAANQADCggIDgAAAA==.Tiltz:BAAANQADCggIDQAAAA==.',
To='Toptree:BAAANQADCgUIBQAAAA==.Topétine:BAAANQADCggIDAAAAA==.',
Tr='Traskk:BAAANQADCgYICgAAAA==.Trelious:BAAANQADCgcIDAAAAA==.Trenet:BAAANQADCgUIBQAAAA==.Trist:BAAANQADCgYIBgAAAA==.Truid:BAAANQADCgUIBQAAAA==.Tryel:BAAANQAECgYIBwAAAA==.Trínídad:BAAANQADCgQIBAAAAA==.',
Tu='Tuaca:BAAANQABCgIIAgAAAA==.Turdsmasher:BAAANQADCgEIAQAAAA==.Turumbar:BAAANQADCggIDAAAAA==.',
Tw='Twysted:BAAANQAECgEIAQAAAA==.',
Ty='Tybeross:BAAANQADCgYIBgAAAA==.Tyrtwo:BAAANQADCgYICwAAAA==.',
Ul='Ultrazord:BAAANQADCgUICAAAAA==.',
Un='Unholynight:BAAANQADCgUICQAAAA==.',
Ur='Urosh:BAAANQABCgQIBAAAAA==.',
Va='Vaks:BAAANQAECgYIBAAAAA==.Valantriç:BAAANQAECgMIAwAAAA==.Valkormyr:BAAANQADCgcIDAAAAA==.Vanishingson:BAAANQADCggIEAAAAA==.Varaldori:BAAANQADCgIIAgAAAA==.Varuguard:BAAANQADCgYIDAABNQADCgcIBwABAAAAAA==.',
Ve='Velell:BAAANQADCgYICwAAAA==.Venomsnake:BAAANQADCgYICQAAAA==.Venura:BAAANQADCgYIDAAAAA==.Verelidaine:BAAANQAECgcIDQAAAA==.Vessper:BAAANQAECgQIBQAAAA==.Vexmama:BAAANQADCgEIAQAAAA==.',
Vh='Vheigar:BAAANQADCgEIAQAAAA==.',
Vi='Viabelle:BAAANQADCgEIAQAAAA==.Vicious:BAAANQADCgMIAwAAAA==.Victor:BAAANQADCgcICgAAAA==.',
Vo='Voidglazer:BAAANQADCggIDgAAAA==.Vorvadoss:BAAANQADCgUIBQABNQADCgUIBwABAAAAAA==.Vosik:BAAANQADCgUICAAAAA==.Voxxy:BAAANQADCgUIBQAAAA==.',
Wa='Wafsei:BAAANQADCggICAAAAA==.',
We='Welcor:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.Welkor:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.',
Wi='Wickebone:BAAANQABCgQIAgAAAA==.Wildheart:BAAANQADCgMIAwAAAA==.Withsauce:BAAANQADCgIIAgAAAA==.',
Wo='Wolfram:BAAANQADCgQIBAAAAA==.Woodish:BAAANQAECggIDgAAAA==.',
['Wä']='Wäyz:BAAANQADCggIBAABNQADCggIDQABAAAAAA==.',
Xa='Xanbar:BAAANQADCggICAAAAA==.Xandent:BAAANQADCgYIBgAAAA==.Xanju:BAAANQAECgQIBQAAAA==.Xanothar:BAAANQADCgIIAgAAAA==.',
Xe='Xep:BAAANQAECgEIAQAAAA==.',
Xi='Xinkz:BAAANQADCgIIAgAAAA==.',
Ya='Yaariissa:BAAANQADCgMIAwAAAA==.',
Yl='Ylliria:BAAANQAECgMIAwAAAA==.',
Yo='Yourholyness:BAAANQADCgcIBwAAAA==.',
Ys='Yso:BAAANQADCgIIAgAAAA==.',
Za='Zalil:BAAANQADCgYICQAAAA==.Zarcyna:BAAANQAECgcIDQAAAA==.Zathoron:BAAANQAECgQIBQAAAA==.',
Ze='Zenfox:BAAANQAECgQIBAAAAA==.',
Zi='Ziatora:BAAANQAECgEIAgAAAA==.Zimmy:BAAANQADCgYICwAAAA==.',
Zo='Zosh:BAAANQABCgQIBQAAAA==.',
Zu='Zultaj:BAAANQADCggICQAAAA==.',
['Àr']='Àriýa:BAAANQADCgYIBgAAAA==.',
['Ãs']='Ãstryl:BAAANQADCgEIAQAAAA==.',
['Är']='Ärth:BAAANQADCgEIAQAAAA==.',
['Äs']='Ästryl:BAAANQADCgIIAwAAAA==.',
['Çç']='Çç:BAAANQAECgEIAQAAAA==.',
['Èu']='Èugene:BAAANQADCgUIBQAAAA==.',
['Ëv']='Ëvan:BAAANQADCgIIAgAAAA==.',
['Ða']='Ðarrow:BAAANQADCggIEAAAAA==.',
['Öu']='Öutßreak:BAAANQADCggIDwAAAA==.',
['Ûl']='Ûllr:BAAANQADCgYICQAAAA==.',
['Ûn']='Ûnwise:BAAANQAECgMIAwAAAA==.',
['ßa']='ßaroness:BAAANQAECgEIAQAAAA==.',
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
