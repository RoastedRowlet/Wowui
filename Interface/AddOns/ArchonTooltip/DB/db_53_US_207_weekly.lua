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

local lookup = {'Monk-Windwalker','Unknown-Unknown','Druid-Guardian','Druid-Balance','Priest-Shadow','Monk-Brewmaster','DemonHunter-Vengeance','Priest-Discipline','Paladin-Retribution','Hunter-Marksmanship','Hunter-BeastMastery','Paladin-Holy','Priest-Holy','Rogue-Outlaw','Evoker-Devastation','Evoker-Preservation','Mage-Arcane','Druid-Restoration','DemonHunter-Devourer','Warrior-Arms','Shaman-Restoration','Warrior-Fury','Warlock-Destruction','Warlock-Demonology','Rogue-Assassination','Rogue-Subtlety','Evoker-Augmentation','Mage-Frost','Warlock-Affliction','Shaman-Enhancement','DeathKnight-Unholy','DeathKnight-Blood',}
local provider = {region='US',realm='Stormreaver',name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aaragondelta:BAAANQADCggIDgABNQAFFAcIDgABAAwZAA==.Aaragonius:BAAANQADCggIEAABNQAFFAcIDgABAAwZAA==.Aaragonneo:BAACNQAFFIEOAAIBAAcJDBkiAAC1AgABAAcJDBkiAAC1AgA1AAQKgRsAAgEACQmLJUYAAPIDAAEACQmLJUYAAPIDAAAA.Aaragontheta:BAAANQADCgIIAgABNQAFFAcIDgABAAwZAA==.',
Ab='Ablé:BAAANQAECgYICgAAAA==.',
Ac='Ackreseth:BAAANQADCggIDQAAAA==.',
Ad='Adriön:BAAANQADCgYIBgAAAA==.',
Ae='Aeko:BAAANQADCggIEgAAAA==.Aemeath:BAAANQADCgIIAgAAAA==.Aerae:BAAANQADCgUIBQAAAA==.Aergoss:BAAANQAECgIIAgAAAA==.Aeristeia:BAAANQAECgQIBgAAAA==.Aethyria:BAAANQADCgYIBgABNQADCggICgACAAAAAA==.',
Ah='Ahriena:BAAANQADCgEIAQABNQAFFAYICwADAKAiAA==.',
Ai='Aiee:BAAANQADCgUIBQAAAA==.Aizén:BAAANQAECgMIBAAAAA==.',
Al='Allaboutme:BAAANQADCgUIBgAAAA==.',
Am='Amad:BAAANQADCgUIBQAAAA==.Amourn:BAAANQAECgIIAQAAAA==.',
An='Analrek:BAAANQAECgUIBQAAAA==.Antoinedruid:BAABNQAECoEYAAIEAAkJlB2kCQAIAwAEAAkJlB2kCQAIAwABNQAFFAUICQAFAOkVAA==.',
Ap='Apocalypsis:BAAANQADCggIDgAAAA==.Apodal:BAABNQAECoEYAAIGAAkJXAsgBwDhAQAGAAkJXAsgBwDhAQABNQAFFAcIDgAHAH0aAA==.Apoluss:BAAANQADCgYICwAAAA==.',
Ar='Arih:BAAANQADCgQIBAAAAA==.Arock:BAAANQAECgYICQAAAA==.Arrithion:BAAANQAECgIIAgAAAA==.Arthaz:BAACNQAFFIEJAAIFAAUJ6RV2AADqAQAFAAUJ6RV2AADqAQA1AAQKgRsAAwUACQlPI0cBALIDAAUACQlPI0cBALIDAAgAAgnqDVEPAHEAAAAA.',
As='Astandra:BAAANQADCgcICgAAAA==.Astro:BAAANQADCgIIAgABNQAECgQIBgACAAAAAA==.',
At='Atexnogaraa:BAABNQAECoEYAAIJAAkJ6xoUDAAAAwAJAAkJ6xoUDAAAAwABNQAFFAcIDgABAAwZAA==.',
Av='Averelles:BAAANQAECgQIBwAAAA==.',
Aw='Awwik:BAAANQAECgIIAgAAAA==.',
Az='Azsharaa:BAAANQAECgMIAwAAAA==.',
Ba='Babyjojo:BAAANQAECgIIAgAAAA==.Badaboomkin:BAAANQADCggIDQABNQAECgUIBQACAAAAAA==.Baeldun:BAAANQAECgQIBwAAAA==.Baethoven:BAAANQAECgIIAgAAAA==.Bagagwa:BAAANQAECgEIAQAAAA==.Ballzac:BAAANQADCggICAAAAA==.Ballzout:BAAANQAECgUIBQAAAA==.Bamix:BAAANQADCgYIBgAAAA==.Bashm:BAAANQAECgUIBgABNQAECggIDAACAAAAAA==.',
Be='Beaconbilly:BAAANQAECgEIAQAAAA==.Beelzemoan:BAAANQADCgUIBwAAAA==.Beens:BAACNQAFFIEGAAMKAAUJ1xwwAQDUAQAKAAUJ0howAQDUAQALAAEJriREBgBfAAA1AAQKgRgAAgoACQnNJXUBAK0DAAoACQnNJXUBAK0DAAAA.Beewitched:BAAANQAECgEIAQAAAA==.Beloved:BAAANQAECgEIAQAAAA==.Belowzerolol:BAABNQAECoEYAAIMAAkJJw3wFwBUAgAMAAkJJw3wFwBUAgABNQAFFAcIDgANAOojAA==.Benkaz:BAAANQAECgIIAgAAAA==.',
Bi='Bierhops:BAAANQADCgcIBwAAAA==.Bigchimpin:BAAANQADCgcIBwAAAA==.',
Bl='Bloodlust:BAAANQAECgcIDgAAAA==.Bluedaemon:BAAANQAECgQIBAAAAA==.Bluenchi:BAAANQADCggICAAAAA==.',
Bo='Boomboompow:BAAANQADCgUICgAAAA==.',
Br='Breadbowl:BAAANQAECgYIBwAAAA==.Brrzerk:BAAANQADCggICwAAAA==.',
Bu='Bubblesburst:BAAANQADCgMIAwABNQAECgEIAQACAAAAAA==.Bubblëdin:BAAANQADCgYICgAAAA==.Buckee:BAAANQAECgQIBQAAAA==.Buckets:BAAANQADCgcIBwAAAA==.Bucknutt:BAAANQAECgIIAwAAAA==.Buffoutlaw:BAABNQAECoEYAAIOAAkJ6iCgAABqAwAOAAkJ6iCgAABqAwABNQAFFAcIDgAOAA8mAA==.Bullzzeye:BAAANQAECggIDwAAAA==.Butternipz:BAAANQADCgcIBwAAAA==.',
By='Byshop:BAAANQAECgMIAwAAAA==.',
Ca='Cabe:BAAANQAECgIIAgAAAA==.Caerra:BAAANQADCgIIAgAAAA==.Caggarm:BAAANQADCggIDgAAAA==.Cailber:BAAANQADCgUIBwAAAA==.Callipriest:BAAANQAECgQIBgAAAA==.Castermaster:BAAANQAECgQICAAAAA==.',
Ce='Celthrinor:BAAANQAECgUIBQAAAA==.Cerevistra:BAAANQADCgEIAQAAAA==.',
Ch='Chakkah:BAAANQADCgQIBAAAAA==.Chillyy:BAAANQAECgYIDAAAAA==.Chipss:BAAANQABCgIIAgAAAA==.Chispot:BAAANQAECgEIAgAAAA==.Chitorpedo:BAAANQAECgQIBAAAAA==.Chodester:BAAANQADCgUIBQAAAA==.Chronis:BAAANQABCgYICgAAAA==.',
Ci='Cidel:BAAANQADCgMIAwAAAA==.Cifer:BAAANQADCgYIBgAAAA==.',
Co='Comatoast:BAAANQAECgUICQAAAA==.Comeback:BAAANQADCgYIBgAAAA==.Course:BAAANQADCgIIAgAAAA==.',
Cr='Crackalaks:BAAANQADCggIDgAAAA==.Crazyb:BAAANQAECgMIAwAAAA==.Croith:BAAANQAECgUIBwAAAA==.Crotch:BAAANQABCgEIAgAAAA==.Cryingorc:BAAANQADCggIDgAAAA==.Crúz:BAAANQAECgEIAQAAAA==.',
Cw='Cwap:BAAANQAECgIIAgAAAA==.',
Cy='Cyndraylitha:BAAANQADCgYIBgAAAA==.',
Da='Daddywaumpus:BAAANQADCggICAAAAA==.Danas:BAAANQADCgYIDgAAAA==.Davicurn:BAAANQADCggICgAAAA==.Daythyme:BAAANQADCggIDgAAAA==.',
De='Deadornot:BAAANQAECgIIAgAAAA==.Deadywaumpus:BAAANQAECgYIDAAAAA==.Deathbubbles:BAAANQADCgYIBwAAAA==.Deathkong:BAAANQAECgcIDwAAAA==.Deathofdager:BAAANQADCggICAAAAA==.Deetwenty:BAAANQADCgcIDAAAAA==.Deeztotemz:BAAANQAECgEIAQAAAA==.Demairis:BAAANQADCgcIBwAAAA==.Demonstyle:BAAANQAECgIIAgAAAA==.Desiiria:BAAANQADCggIDQAAAA==.Deylicious:BAAANQAECgQIBAABNQAFFAcIDgALAI4aAA==.',
Dh='Dhani:BAAANQAECgMIAwAAAA==.',
Di='Dietdrpibb:BAAANQADCgcIEQAAAA==.Dijoe:BAAANQAECgMIBQAAAA==.Dimmencius:BAAANQADCgQIBAAAAA==.Dippndotz:BAAANQAECggIEAAAAA==.Discfunction:BAAANQADCgcIEwAAAA==.Disciple:BAAANQADCgYIBgAAAA==.',
Do='Doafliploser:BAAANQADCgYIBgAAAA==.Dogwalterll:BAAANQAECgQIBwAAAA==.Dohvahkiin:BAAANQADCgYIBgAAAA==.Dontlosmë:BAAANQADCgQIBAABNQADCgYICgACAAAAAA==.',
Dr='Draaragon:BAAANQADCggICwABNQAFFAcIDgABAAwZAA==.Dragonboffa:BAAANQADCgYIEgAAAA==.Dragonlyfans:BAABNQAECoEYAAMPAAkJtRYqCQA/AgAPAAgJJxUqCQA/AgAQAAgJJwlREQCxAQABNQAFFAcIDQAEAD8hAA==.Dripz:BAAANQADCggIFQAAAA==.Drive:BAAANQAECgQIBAAAAA==.Dryadwood:BAAANQADCgcIDQAAAA==.',
Du='Dubby:BAAANQAECgcICwAAAA==.Dumptruckdan:BAABNQAECoEYAAIJAAkJ2BVlGQB3AgAJAAkJ2BVlGQB3AgABNQAFFAcIDgARAEYWAA==.Durgur:BAAANQADCgQIBAABNQAECgcIEAACAAAAAA==.',
Ea='Eardi:BAAANQAECgcICgAAAA==.Earthpounder:BAAANQAECgMIAwAAAA==.',
Ec='Echoez:BAAANQAECgcIDAAAAA==.Eclipsa:BAAANQAECgQIBAAAAA==.',
Ee='Eebo:BAAANQADCgMIAwAAAA==.',
El='Elbram:BAAANQADCggICAABNQAECgMIAwACAAAAAA==.Elunasolz:BAEANQADCggIDwABNQAECgIIAgACAAAAAA==.',
Em='Emilil:BAAANQADCgMIAwAAAA==.Eminence:BAAANQADCggIDgAAAA==.',
En='Enlight:BAAANQABCgEIAQAAAA==.',
Er='Erdorco:BAAANQADCggICwABNQAECgQIBQACAAAAAA==.',
Es='Escanor:BAAANQADCggIDgAAAA==.Esu:BAAANQADCgUIBgAAAA==.',
Eu='Eudaimonia:BAAANQADCgYIDwAAAA==.',
Ex='Exias:BAAANQADCggIDQAAAA==.',
Fa='Facebeata:BAAANQAECgYICwAAAA==.Faize:BAAANQADCggIDgABNQAECgkJGQASAOsSAA==.Falae:BAAANQAECgMIAwABNQAFFAEIAQACAAAAAA==.Fathêrhêlp:BAAANQADCgEIAQAAAA==.Faunuis:BAACNQAFFIENAAMEAAcJPyG0AAAYAgAEAAUJVyK0AAAYAgASAAIJAhBrAgCtAAA1AAQKgRsAAwQACQkrJMcAANkDAAQACQkrJMcAANkDABIABgmKHaoOANkBAAAA.Fawnbby:BAAANQAECgUIBQAAAA==.',
Fe='Featherbrain:BAAANQAECgEIAQAAAA==.Felhell:BAAANQADCggIEAABNQAECgYIDAACAAAAAA==.Ferenyet:BAAANQADCgYIBgAAAA==.Fermagus:BAAANQAECgUICgAAAA==.',
Fi='Fistflurry:BAAANQAECgUIBQAAAA==.Fistlad:BAACNQAFFIEOAAIPAAcJeCQDAAAoAwAPAAcJeCQDAAAoAwA1AAQKgRsAAg8ACQkHJwEAACwEAA8ACQkHJwEAACwEAAAA.Fizzybubbles:BAAANQAECgQIBQAAAA==.',
Fl='Flamehunter:BAAANQAECggIDAAAAA==.Flapple:BAABNQAECoEXAAIPAAkJqCGsAQB6AwAPAAkJqCGsAQB6AwAAAA==.Flexicution:BAAANQADCgYIBgABNQAECgQIBAACAAAAAA==.Floweret:BAAANQAECgIIAgAAAA==.Flu:BAAANQADCgEIAQABNQAECgIIAgACAAAAAA==.Flûffy:BAAANQAECgEIAQAAAA==.',
Fr='Freaknikk:BAAANQAECgUIBwABNQAECgYIDgACAAAAAA==.Freightraìn:BAAANQADCgIIAgABNQAECgYIDAACAAAAAQ==.Frozalth:BAAANQADCgUIBgAAAA==.',
Fu='Fudgemuffin:BAAANQADCggIFQAAAA==.',
['Fë']='Fënrïr:BAAANQAECgIIAwABNQAECgcIEAACAAAAAA==.',
['Fú']='Fúzzybútt:BAAANQADCgMIAwAAAA==.',
Ga='Galice:BAAANQADCgMIAwAAAA==.Garlim:BAAANQADCgUIBQAAAA==.Gazebogary:BAAANQAECgQIBAABNQAFFAcIDgARAEYWAA==.',
Ge='Gellysong:BAAANQABCgQIBgAAAA==.Gerlim:BAAANQADCgEIAQAAAA==.',
Gi='Gix:BAAANQADCgQIBwAAAA==.',
Gl='Glolock:BAAANQAECgIIAgAAAA==.Glopanx:BAAANQADCgYIDAABNQAECgIIAgACAAAAAA==.',
Go='Goresnot:BAAANQADCggIEwAAAA==.',
Gr='Granrok:BAAANQADCgYIBgAAAA==.Gravedarknes:BAAANQAECggIDgAAAA==.Greendog:BAAANQADCgIIAgABNQAECgQICAACAAAAAA==.Grishknight:BAAANQADCgIIAgAAAA==.',
Gu='Guap:BAABNQAECoEYAAIRAAkJzBlMLACTAgARAAkJzBlMLACTAgABNQAFFAcIDgAPAHgkAA==.Gunray:BAAANQADCgUIBQAAAA==.Guttamane:BAAANQADCggIDQAAAA==.Gutx:BAAANQADCgYIDgAAAA==.',
Gy='Gyarrados:BAAANQADCgYICgAAAA==.Gypsywolfe:BAAANQAECgEIAQAAAA==.',
['Gí']='Gífted:BAAANQAECgYIDAAAAA==.',
Ha='Haleybeary:BAAANQADCgcIEwAAAA==.Harawing:BAAANQADCgUIBQAAAA==.Hargrim:BAAANQADCggICAAAAA==.Hastega:BAAANQAECgQICAAAAA==.Haydonk:BAAANQADCgcIBwAAAA==.',
He='Herbage:BAAANQAECgMIAwAAAA==.Herrbjorn:BAAANQADCggIFQAAAA==.',
Hi='Hinata:BAAANQADCgQIBAAAAA==.Hippopotamus:BAAANQADCggIDgAAAA==.Hitaman:BAAANQAECgEIAQAAAA==.',
Ho='Holik:BAAANQABCgEIAQAAAA==.Holybaguette:BAAANQAECgEIAQAAAA==.Holycritbro:BAAANQADCgcIFAAAAA==.Horôn:BAAANQADCggICgAAAA==.Houndoomm:BAAANQADCggIFQAAAA==.',
Hr='Hriste:BAAANQAECgQIBAAAAA==.',
Hu='Hunteress:BAAANQADCgQIBAAAAA==.Huntyhunt:BAAANQAECgIIAgAAAA==.',
Im='Imnosickmall:BAAANQADCgUIBQAAAA==.Impmafia:BAAANQABCgIIBAAAAA==.',
In='Incognetus:BAAANQAECgYIDAAAAQ==.Insurrection:BAAANQADCgYIDAABNQAECgUICQACAAAAAA==.',
Ir='Ironmaiiden:BAAANQADCgYIBgAAAA==.Ironpally:BAAANQAECgMIAwAAAA==.',
Iw='Iwantmead:BAAANQABCgMIAwAAAA==.',
Ja='Jaduen:BAAANQADCggIFwAAAA==.Jaesedar:BAAANQAFFAEIAQAAAA==.Jaycen:BAAANQAECgMIAwABNQAECgYIDAACAAAAAQ==.',
Je='Jellythug:BAAANQAECgIIAgAAAA==.Jenny:BAAANQADCgYICQAAAA==.Jerksnknight:BAAANQAECgMIAwAAAA==.Jethon:BAAANQADCgcIDwAAAA==.Jexro:BAABNQAECoEYAAITAAkJWyEMAgCcAwATAAkJWyEMAgCcAwAAAA==.Jezebaal:BAAANQADCgQIBAAAAA==.',
Jg='Jgremlin:BAAANQADCgUIBAAAAA==.',
Ji='Jiun:BAAANQADCgEIAQAAAA==.',
Jo='Johnseenah:BAAANQADCgYIDAAAAA==.Jonnybravo:BAAANQAECgQIBQAAAA==.Joshton:BAAANQADCgUIBQAAAA==.',
Jr='Jrrd:BAAANQAECgQIBQAAAA==.',
Ju='Judgmentoe:BAAANQADCggIEwAAAA==.Jusstice:BAAANQAECgMIAwAAAA==.',
Ka='Kack:BAAANQADCgYICgAAAA==.Kalvosa:BAAANQADCgMIBAAAAA==.Karlbarx:BAAANQAECgIIAgAAAA==.Kasaa:BAAANQAECgQIBgAAAA==.Kasheira:BAAANQAECgMIAwAAAA==.Katti:BAAANQAECgQICAAAAA==.Katzfiel:BAAANQAECgIIAgAAAA==.Kaytwo:BAACNQAFFIEHAAIUAAYJpRnNAABAAgAUAAYJpRnNAABAAgA1AAQKgRYAAhQACQn7JaECAMEDABQACQn7JaECAMEDAAAA.',
Kb='Kblasti:BAAANQADCggIFgABNQAECgcIDQACAAAAAA==.Kblastissimo:BAAANQAECgcIDQAAAA==.',
Kc='Kcommandr:BAAANQADCggICAABNQAECgUICAACAAAAAA==.',
Ke='Kendramp:BAAANQADCgIIAgAAAA==.Kersplode:BAAANQADCgUIBQABNQAECgYIDAACAAAAAA==.',
Kh='Khariia:BAAANQADCgQIBAAAAA==.',
Ki='Kieloran:BAAANQAECgUICgAAAA==.Kieralyn:BAAANQAECgEIAQAAAA==.Kiltlifter:BAAANQADCgcIEQAAAA==.Kisol:BAAANQADCgYIBgAAAA==.',
Ko='Koaladashian:BAAANQAECggIDwAAAA==.Koalaficent:BAAANQAECggIDgAAAA==.Kojodruid:BAAANQADCgYICgAAAA==.Kojohunter:BAAANQADCgcIBwAAAA==.Kong:BAAANQAECgUIBQAAAA==.Kookta:BAAANQAECgYIDAAAAA==.Kozmo:BAAANQAECgEIAQAAAA==.',
Kr='Kreep:BAAANQADCgYICAAAAA==.Kresnik:BAAANQADCgUIBQAAAA==.',
Ku='Kundin:BAAANQAECgYIBgABNQAFFAEIAQACAAAAAA==.Kurai:BAAANQAECgUIBwAAAA==.Kutaki:BAAANQADCgcIEwAAAA==.',
['Kí']='Kíngbradley:BAAANQADCgQIBAABNQAECgYIDAACAAAAAA==.',
La='Lasrin:BAAANQAECggIEwAAAA==.Lavenia:BAAANQADCggIDAAAAA==.',
Ld='Ldawg:BAAANQAECgUIBwAAAA==.',
Le='Leastzenmonk:BAAANQAECgYICwABNQAECgkJFwAVAO4fAA==.Lelu:BAAANQADCgUIBQAAAA==.',
Li='Liello:BAAANQAECgEIAQAAAA==.Lightchaos:BAAANQAECgYIBgAAAA==.Lightice:BAAANQADCgMIAwAAAA==.Lilgaypunk:BAABNQAECoEZAAIFAAkJRBvMBQAXAwAFAAkJRBvMBQAXAwAAAA==.Lilgaypunkk:BAAANQADCgUIBQABNQAECgkJGQAFAEQbAA==.Littlecyka:BAAANQADCggICAAAAA==.',
Lo='Lockfocks:BAAANQADCggICAABNQAECgEIAQACAAAAAA==.Locoscar:BAABNQAECoEZAAMLAAkJtSXIAADPAwALAAkJtSXIAADPAwAKAAQJ3BQnJgDpAAAAAA==.Loktark:BAACNQAFFIEOAAIOAAcJDyYBAAD7AgAOAAcJDyYBAAD7AgA1AAQKgRsAAg4ACQmiJggAAAUEAA4ACQmiJggAAAUEAAAA.Lotei:BAAANQADCggIEgAAAA==.',
Lu='Luckylock:BAAANQADCgYIBgABNQAECgcIBwACAAAAAA==.Lucresh:BAAANQADCgYIBgAAAA==.Lula:BAAANQADCgIIAgAAAA==.Lunasolz:BAEANQADCggIDwABNQAECgIIAgACAAAAAA==.Lustíé:BAAANQADCgcIEgAAAA==.',
Ly='Lythinlock:BAAANQAECgMIAwAAAA==.',
['Là']='Lànthus:BAAANQAECgMIBgAAAA==.',
['Lê']='Lêêrøy:BAAANQADCgEIAQAAAA==.',
Ma='Magev:BAAANQAECgMIAwAAAA==.Magiccheif:BAAANQAECgQICAAAAA==.Magnuz:BAAANQADCgQIBwAAAA==.Maisharona:BAAANQADCgYIDAABNQAECgYIDgACAAAAAA==.Manginah:BAAANQAECgEIAQABNQAECgUIBQACAAAAAA==.Mauringo:BAAANQADCggICAAAAA==.Mavanthis:BAAANQAECgQIBAAAAA==.Maxdizaster:BAAANQAECgIIAgAAAA==.Mazkaz:BAAANQADCgUIBQAAAA==.',
Mc='Mcbonk:BAABNQAECoEWAAMUAAkJah/+DwANAwAUAAkJOB3+DwANAwAWAAMJCCSTCAAvAQAAAA==.Mckniferson:BAAANQADCgQIBgAAAA==.',
Me='Merlenoir:BAAANQADCgUIBQAAAA==.Messybedhead:BAAANQAECgcIDwABNQADCgYIBgACAAAAAA==.Methindour:BAAANQADCgcIEgAAAA==.',
Mi='Mightydwarf:BAAANQADCggIDAAAAA==.Mintwiskers:BAAANQAECgIIAgAAAA==.Misiana:BAAANQAECgYIDAAAAA==.Mivix:BAAANQAECgUICAABNQAFFAYIDAANAOsTAA==.',
Mo='Mom:BAAANQADCggIDgABNQAECgcIDQACAAAAAA==.Monkeyclaw:BAAANQAECgQICAAAAA==.Moonfist:BAAANQADCgQIBAAAAA==.Mordrak:BAAANQAECgQIBgAAAA==.Mordë:BAABNQAECoENAAMXAAcJjAr+IQAQAQAXAAUJqgj+IQAQAQAYAAQJHAybYADRAAAAAA==.Mormzie:BAAANQAECgEIAQABNQAECgQICAACAAAAAA==.Morwy:BAAANQAECgIIAgAAAA==.Moøbytoo:BAAANQAECgQIBwABNQAECgUICAACAAAAAA==.',
Ms='Msedd:BAAANQADCgMIAwAAAA==.',
Mu='Mugged:BAAANQAECgYIDAAAAA==.Muinogaraa:BAAANQAECgIIAgABNQAFFAcIDgABAAwZAA==.Mum:BAAANQAECgcIDQAAAA==.Mushmouth:BAAANQAECgQICAAAAA==.',
My='Myguy:BAAANQADCgQIBAAAAA==.Mysiara:BAAANQADCgYIEQAAAA==.',
['Mà']='Màjestic:BAAANQADCgYIBgAAAA==.',
['Mì']='Mìchael:BAAANQAECgIIAgAAAA==.',
['Mú']='Músu:BAAANQAECgUIBQAAAA==.',
Na='Nagosho:BAAANQADCgUIBQAAAA==.Nampur:BAAANQAECgEIAQAAAA==.Naril:BAAANQADCggIFAAAAA==.Narvana:BAAANQAECgQICAAAAA==.Naughtyboy:BAAANQAECgEIAQAAAA==.Nayalla:BAAANQADCgcICwAAAA==.',
Ni='Nitezz:BAAANQADCgMIAwAAAA==.Nityblast:BAAANQADCgYICwAAAA==.',
No='Nodrus:BAAANQADCggICgAAAA==.Nogaraa:BAAANQAECgcIBwABNQAFFAcIDgABAAwZAA==.Novath:BAACNQAFFIEOAAIMAAcJ4R8MAADaAgAMAAcJ4R8MAADaAgA1AAQKgRwAAwwACQkWJV4AAN8DAAwACQkWJV4AAN8DAAkAAglyJGJwANcAAAAA.',
Ny='Nyssarissa:BAAANQAECgcIDAAAAA==.',
['Nè']='Nèliel:BAAANQAECgMIBQAAAA==.',
Oa='Oakenstream:BAAANQADCgIIAgAAAA==.',
Oe='Oennogaraa:BAAANQADCggICAABNQAFFAcIDgABAAwZAA==.',
Op='Ophélia:BAAANQAECgMIAwAAAA==.',
Or='Orbz:BAAANQADCgQIAwAAAA==.Orusmar:BAAANQADCgYIBgAAAA==.',
Ou='Oui:BAAANQAECgQIBAAAAA==.',
Ov='Overheated:BAAANQADCgYIDQAAAA==.',
Pa='Paalaz:BAAANQAFFAIIAgAAAA==.Paeldryth:BAABNQAECoEbAAMZAAkJMSZ+AAC/AwAZAAkJMSZ+AAC/AwAaAAgJPRkACwBYAgAAAA==.Paliesto:BAAANQAECgEIAQAAAA==.Paljin:BAAANQADCgUIBgAAAA==.Palkia:BAAANQAECgEIAQAAAA==.Palmface:BAAANQAECgIIAgAAAA==.Panatepriest:BAAANQADCggIDgAAAA==.Pandadante:BAAANQAECgEIAQABNQAECgcIDgACAAAAAA==.Pandatunado:BAAANQAFFAIIAgAAAA==.Panky:BAAANQAECgUIBQAAAA==.',
Pe='Pedrocerrano:BAAANQAECgUIBQAAAA==.Pelt:BAAANQAECgYIDAAAAA==.Pewbot:BAAANQAECgIIAgABNQAECgYIDAACAAAAAQ==.',
Ph='Phoebë:BAAANQADCgUIBwAAAA==.Phusiion:BAAANQADCgQIBQAAAA==.',
Pi='Pickledin:BAAANQAECgUIBgAAAA==.',
Pk='Pkmntrainer:BAAANQADCgYIEgABNQADCgcIEQACAAAAAA==.',
Pl='Please:BAACNQAFFIEOAAIVAAcJZwdaAAA7AgAVAAcJZwdaAAA7AgA1AAQKgRsAAhUACQkBH0sHABIDABUACQkBH0sHABIDAAAA.Pleasetwo:BAABNQAECoEYAAIVAAkJAAwkIgD9AQAVAAkJAAwkIgD9AQABNQAFFAcIDgAVAGcHAA==.Plumaril:BAAANQAECgIIAgAAAA==.',
Po='Pondero:BAAANQABCgMIAwABNQAECgYIBwACAAAAAA==.',
Pp='Ppleakin:BAAANQAECgcIDwAAAA==.',
Pr='Pranzar:BAAANQAECgUIAwAAAA==.Prepdagoat:BAAANQADCggIEwABNQADCgQIBAACAAAAAA==.',
Pu='Pullo:BAAANQAECgYIDgAAAA==.Punctualpaul:BAAANQAECggIDAABNQAFFAcIDgAMAOEfAA==.Purple:BAAANQAECgMIAwAAAA==.',
Py='Pyrê:BAAANQADCgQIBAAAAA==.',
Qu='Quidditch:BAAANQAECgUICAAAAA==.',
Qw='Qwadsfwfgads:BAABNQAFFIEMAAISAAYJvxkWAABCAgASAAYJvxkWAABCAgAAAA==.Qwamsfwfgads:BAAANQAECgIIAgABNQAFFAYIDAASAL8ZAA==.',
Ra='Rabbi:BAAANQADCgIIBQABNQAECgYIDAACAAAAAQ==.Raelavent:BAAANQAECgEIAQAAAA==.Ragrappy:BAACNQAFFIEOAAINAAcJ6iMCAADyAgANAAcJ6iMCAADyAgA1AAQKgRsAAg0ACQmsJiMAAPQDAA0ACQmsJiMAAPQDAAAA.Raiju:BAAANQAECgEIAQAAAA==.Ramped:BAAANQADCgUIBQAAAA==.Raszahk:BAAANQAECgYICwABNQAFFAEIAQACAAAAAA==.',
Re='Reavêr:BAAANQAECgMIAwAAAA==.Redreximus:BAAANQAECgQICAAAAA==.Regilock:BAAANQAECgQIBwAAAA==.Retlec:BAAANQAECgMIAwAAAA==.Reïki:BAAANQADCgYIBgAAAA==.',
Ri='Ripto:BAAANQAECgEIAQAAAA==.',
Ro='Rochaca:BAAANQADCgQIBAAAAA==.Roshana:BAAANQAECgIIAgAAAA==.Rothoof:BAAANQAECgMIAwAAAA==.',
Ru='Rudnos:BAAANQADCgMIAgABNQAECgIIAgACAAAAAA==.Rumham:BAAANQADCgUIBQABNQAECgEIAQACAAAAAA==.Ruzzart:BAAANQADCgQIBAAAAA==.',
Ry='Ryptup:BAAANQAECgQIBAAAAA==.',
['Rô']='Rôinujj:BAAANQADCgUIBgAAAA==.',
Sa='Safiyah:BAAANQAECgQIBgAAAA==.Saltyevoker:BAAANQADCgcIDgAAAA==.Same:BAABNQAECoEYAAISAAkJiCGAAQBgAwASAAkJiCGAAQBgAwABNQAFFAcIDgAMAOEfAA==.Samophlangy:BAAANQABCgIIAgAAAA==.Sandorstus:BAAANQAECgQIBgAAAA==.Saothome:BAAANQADCggIDAAAAA==.Sathreal:BAAANQADCgMIAwAAAA==.Saywho:BAAANQADCgUICQAAAA==.',
Sc='Scalywaumpus:BAAANQADCggICAAAAA==.Scienta:BAAANQAECgYIBwABNQAECgcIEAACAAAAAA==.Scope:BAAANQADCgYIBgAAAA==.Scrubdk:BAAANQADCgcIBwAAAA==.Scúbasteve:BAAANQAECgMIAwAAAA==.',
Se='Sefirot:BAAANQADCgcIEwAAAA==.Selinddra:BAAANQADCgcIEAAAAA==.Serrafin:BAAANQAECgcIAQAAAA==.',
Sh='Shadebringer:BAAANQADCggIFAAAAA==.Shadowboxin:BAAANQADCgUIBQAAAA==.Shamdaddy:BAAANQAECgIIAgAAAA==.Shamezee:BAAANQAECgQIBgAAAA==.Shampoo:BAAANQADCggICQAAAA==.Sharlotte:BAAANQADCgUIBQAAAA==.Shilas:BAABNQAECoEYAAIBAAkJaxm+BgDDAgABAAkJaxm+BgDDAgABNQAECgkJHAAUADMiAA==.Shishkabug:BAAANQADCgIIAgAAAA==.Shownuph:BAAANQADCgEIAQAAAA==.',
Si='Sicilianhero:BAAANQADCggIDgAAAA==.Singelock:BAAANQADCgQIBAABNQADCggICAACAAAAAA==.Sinsyn:BAAANQADCggICAAAAA==.Sinwarrior:BAAANQADCggIEAABNQAFFAUIBgAGANwQAA==.Sizz:BAAANQADCgQIBAAAAA==.',
Sk='Skipcawk:BAACNQAFFIEOAAMLAAcJjhrlAAApAQAKAAQJ8BRnAgBtAQALAAMJCiLlAAApAQA1AAQKgRsAAwoACQlqJhMAABQEAAoACQlqJhMAABQEAAsABgm2G141ALkBAAAA.Skorpco:BAABNQAECoEYAAITAAkJtRYiCwDBAgATAAkJtRYiCwDBAgAAAA==.',
Sl='Sluggo:BAAANQADCggIEAAAAA==.',
Sm='Smulol:BAAANQAECgQIBwAAAA==.',
Sn='Snoopfrogg:BAAANQAECgQICAAAAA==.',
So='Solfire:BAAANQAECgQIBAAAAA==.Solstice:BAAANQADCgQIBAAAAA==.Somehobo:BAAANQADCgUIBwAAAA==.Sometingwong:BAAANQADCgYICgAAAA==.',
Sp='Spamheal:BAAANQADCgcIDwAAAA==.Sparkle:BAAANQADCgUIBgAAAA==.Spliffy:BAAANQABCgEIAQAAAA==.Spodermenpls:BAAANQADCgIIAgABNQAECgkJFwAVAO4fAA==.',
St='Stabber:BAAANQADCgQIBAAAAA==.Stoc:BAAANQAECgMIAwAAAA==.Stormweaver:BAAANQAECgEIAQAAAA==.',
Su='Suinogaraa:BAAANQADCgYIBgABNQAFFAcIDgABAAwZAA==.Sunderwhere:BAAANQAFFAEIAQAAAA==.',
Sw='Swann:BAAANQAECgUICAAAAA==.Swavor:BAAANQADCggIDgAAAA==.Sweetbella:BAAANQADCgQIBwAAAA==.Swurves:BAAANQADCggIFAABNQAECgEIAQACAAAAAA==.',
Sy='Symbio:BAAANQADCggIDQAAAA==.Syna:BAAANQAECgEIAQAAAA==.',
Ta='Taearo:BAAANQADCggIFgABNQAECgIIAgACAAAAAA==.Taime:BAAANQAECgMIBAAAAA==.Talirn:BAAANQADCggIFAAAAA==.Tallanvor:BAAANQADCgcIDQAAAA==.',
Te='Teddywaumpus:BAAANQADCgYIBgAAAA==.Tendecay:BAAANQAECgMIAwAAAA==.',
Th='Thanquiol:BAACNQAFFIEOAAIHAAcJfRoCAACfAgAHAAcJfRoCAACfAgA1AAQKgRsAAgcACQlEI0IAAKYDAAcACQlEI0IAAKYDAAAA.Thebaraj:BAAANQAECgQICAAAAA==.Thebigdawg:BAAANQADCgUICAAAAA==.Thedruidd:BAAANQADCgYIBQAAAA==.Theeassassin:BAAANQADCgIIAQAAAA==.Thelance:BAAANQADCggIDgAAAA==.Thrilled:BAAANQADCggIFQAAAA==.Thyora:BAABNQAECoEaAAQQAAkJQxBjDAAbAgAQAAkJQxBjDAAbAgAPAAMJdAzsGQCtAAAbAAIJ9hf9CgCFAAAAAA==.',
Ti='Tijdruid:BAAANQADCggIDgAAAA==.',
To='Tommypickles:BAACNQAFFIEOAAMRAAcJRhYgAQAcAgARAAYJbxIgAQAcAgAcAAIJXSAmAADTAAA1AAQKgR0AAxEACQn0JRIBAOIDABEACQn0JRIBAOIDABwAAgk+JgoMAOMAAAAA.Tomtrocity:BAAANQADCgMIBAAAAA==.Tonestar:BAAANQADCgcIDAAAAA==.Toturaka:BAAANQADCgUIBQAAAA==.',
Tr='Trackerjoe:BAAANQADCgMIBAAAAA==.Train:BAAANQADCgIIAgABNQAECgYIDAACAAAAAQ==.Treerex:BAAANQAECgMIAwAAAA==.Troljin:BAAANQAECgQIBgAAAA==.Trollpaladin:BAAANQAECgcICQAAAA==.',
Ts='Tsipayeoc:BAAANQADCgUIBgAAAA==.',
Tw='Twk:BAAANQADCgcIDgAAAA==.',
Ty='Tyrgann:BAAANQADCgUIBQAAAA==.Tytoflamina:BAAANQAECgEIAQAAAA==.',
Ul='Ulkanir:BAAANQADCgUIBQAAAA==.',
Um='Umalinn:BAAANQAECgIIAgAAAA==.',
Ur='Urbellum:BAAANQADCgEIAQABNQAFFAQIBgAUAFUHAA==.Urukhaixd:BAAANQABCgIIBAAAAA==.',
Va='Vacca:BAAANQAECgIIAgAAAA==.Vaeyethror:BAAANQADCgQIBAAAAA==.Vahvadon:BAAANQADCgQIBAAAAA==.Valucia:BAAANQADCgEIAQAAAA==.Vandagar:BAAANQAECgMIAwAAAA==.Vapor:BAAANQAECgYIEwAAAA==.Varsity:BAABNQAECoEcAAIUAAkJMyKRBQCOAwAUAAkJMyKRBQCOAwAAAA==.Vason:BAAANQADCgMIAwAAAA==.',
Ve='Ventumceleri:BAAANQADCgUIBQAAAA==.',
Vh='Vhega:BAAANQABCgIIAgAAAA==.',
Vi='Victor:BAAANQABCgIIAgAAAA==.Vinyasa:BAAANQAECgUIBQAAAA==.',
Vo='Voodoobeast:BAAANQAECgMIAwAAAA==.',
Vu='Vulbahermosa:BAAANQAECgMIBAAAAA==.',
Wa='Waremtae:BAAANQADCgEIAQAAAA==.',
We='Wenguo:BAAANQAECgMIAwAAAA==.',
Wh='Wheatiees:BAAANQADCgUIBQAAAA==.Whyp:BAAANQAECgcIEwAAAA==.',
Wi='Wickle:BAAANQADCgcIBwAAAA==.Wingdaz:BAEANQADCggICQABNQAFFAEIAQACAAAAAA==.Wizliz:BAAANQADCgYIBgABNQAECgIIAgACAAAAAA==.',
Xi='Xidara:BAAANQADCgUIBgAAAA==.Xiqualani:BAAANQADCgYIBgAAAA==.Xivei:BAACNQAFFIEMAAINAAYJ6xO0AAANAgANAAYJ6xO0AAANAgA1AAQKgRsAAw0ACQlFIAkIAPICAA0ACQkaIAkIAPICAAgABwksEJkFAJcBAAAA.',
Xl='Xlegolas:BAAANQADCgUIBgAAAA==.',
Xo='Xorac:BAAANQADCgcICwAAAA==.',
Xz='Xzach:BAABNQAECoEYAAITAAkJgg0aEwA8AgATAAkJgg0aEwA8AgAAAA==.',
Yi='Yinlou:BAAANQADCggIEgAAAA==.',
Yo='Yorha:BAAANQADCgEIAQABNQAECgkJGAAPAFIXAA==.',
Ys='Yshtolà:BAEANQAECgIIAgAAAA==.',
Yu='Yurmage:BAAANQAECgEIAQAAAA==.',
['Yì']='Yìffist:BAAANQADCgYIDAAAAA==.',
Za='Zachx:BAACNQAFFIEOAAQXAAcJFyINAACyAQAXAAQJESQNAACyAQAYAAMJPB7UAQAoAQAdAAEJeCZ8AAB2AAA1AAQKgRsAAxcACQmXJZoAAJkDABcACQmuIpoAAJkDABgABwmDICEMALECAAAA.Zaegorn:BAAANQAECgMIAwAAAA==.Zargar:BAABNQAECoEXAAIeAAgJAyD1AgDxAgAeAAgJAyD1AgDxAgAAAA==.Zarmakai:BAACNQAFFIELAAMfAAYJ0RoWAAASAgAfAAUJ0x0WAAASAgAgAAEJxAuHDQAuAAA1AAQKgRsAAh8ACQmBJWQAAPQDAB8ACQmBJWQAAPQDAAAA.',
Ze='Zenxo:BAAANQABCgYIBwAAAA==.',
Zi='Zivie:BAAANQAECgQIBQAAAA==.',
Zu='Zurry:BAAANQABCgEIAQAAAA==.',
Zy='Zygon:BAAANQAECgQICgAAAA==.',
['Ök']='Ökko:BAAANQAECgMIAwAAAA==.',
['Öw']='Öwly:BAAANQAECgMIAwAAAA==.',
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
