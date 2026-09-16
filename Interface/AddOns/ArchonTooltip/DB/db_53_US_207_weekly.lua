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

local lookup = {'Monk-Windwalker','Unknown-Unknown','Druid-Guardian','Druid-Balance','Priest-Shadow','Monk-Brewmaster','DemonHunter-Vengeance','Priest-Discipline','Paladin-Retribution','Hunter-Marksmanship','Hunter-BeastMastery','Paladin-Holy','Priest-Holy','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','Evoker-Devastation','Evoker-Preservation','Mage-Arcane','Druid-Restoration','Shaman-Elemental','DemonHunter-Devourer','Warrior-Arms','Shaman-Restoration','Warrior-Fury','Warlock-Destruction','Warlock-Demonology','DemonHunter-Havoc','DeathKnight-Unholy','DeathKnight-Frost','Evoker-Augmentation','Mage-Frost','Warlock-Affliction','Shaman-Enhancement','DeathKnight-Blood',}
local provider = {region='US',realm='Stormreaver',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aaragondelta:BAAANQAECgcIBwABNQAFFAcIFQABALUgAA==.Aaragonius:BAAANQADCggIEAABNQAFFAcIFQABALUgAA==.Aaragonneo:BAACNQAFFIEVAAIBAAcJtSA7AADTAgABAAcJtSA7AADTAgA1AAQKgR4AAgEACQldJkYAAPcDAAEACQldJkYAAPcDAAAA.Aaragontheta:BAAANQADCgIIAgABNQAFFAcIFQABALUgAA==.Aaragonxeta:BAAANQADCgEIAQABNQAFFAcIFQABALUgAA==.',
Ab='Ablé:BAAANQAECgYIEAAAAA==.',
Ac='Ackreseth:BAAANQADCggIEwAAAA==.',
Ad='Adriön:BAAANQADCgYIBgAAAA==.',
Ae='Aeko:BAAANQAECgIIAgAAAA==.Aemeath:BAAANQADCgIIAgAAAA==.Aerae:BAAANQADCggIDQAAAA==.Aergoss:BAAANQAECgIIAgAAAA==.Aeristeia:BAAANQAECgYIDAAAAA==.Aethyria:BAAANQADCgYIBgABNQADCggIDAACAAAAAA==.',
Ah='Ahriena:BAAANQADCgEIAQABNQAFFAYIEQADAEwjAA==.',
Ai='Aiee:BAAANQAECgMIAwAAAA==.Aizén:BAAANQAECgMIBwAAAA==.',
Al='Allaboutme:BAAANQADCgUIBgAAAA==.',
Am='Amad:BAAANQADCgUIBQAAAA==.Amourn:BAAANQAECgIIAQAAAA==.',
An='Analrek:BAAANQAECgUICgAAAA==.Antekhrestos:BAAANQADCgQIBAAAAA==.Antoinedruid:BAABNQAECoEYAAIEAAkJlB2QEADmAgAEAAkJlB2QEADmAgABNQAFFAYIDgAFAMAXAA==.',
Ap='Apocalypsis:BAAANQADCggIDgAAAA==.Apodal:BAABNQAECoEYAAIGAAkJXAtACgDLAQAGAAkJXAtACgDLAQABNQAFFAcIFQAHALwfAA==.Apoluss:BAAANQADCgYICwAAAA==.',
Ar='Arih:BAAANQADCgUICQAAAA==.Arock:BAAANQAECgcIEAAAAA==.Arrithion:BAAANQAECgMIBQAAAA==.Arthaz:BAACNQAFFIEOAAIFAAYJwBeVAAAlAgAFAAYJwBeVAAAlAgA1AAQKgR4AAwUACQlYI+ECAJIDAAUACQlYI+ECAJIDAAgAAgnqDV0SAHEAAAAA.',
As='Astandra:BAAANQAECgEIAQAAAA==.Astro:BAAANQADCgIIAgABNQAECgYIDAACAAAAAA==.',
At='Atexnogaraa:BAABNQAECoEYAAIJAAkJ6xoJGgDRAgAJAAkJ6xoJGgDRAgABNQAFFAcIFQABALUgAA==.',
Av='Averelles:BAAANQAECgQICwAAAA==.',
Aw='Awwik:BAAANQAECgQIBgAAAA==.',
Az='Azsharaa:BAAANQAECgYIBgAAAA==.',
Ba='Babyjojo:BAAANQAECgMIBQAAAA==.Badaboomkin:BAAANQAECgIIAgABNQAFFAEIAQACAAAAAA==.Baeldun:BAAANQAECgQICAAAAA==.Baethoven:BAAANQAECgMIBQAAAA==.Bagagwa:BAAANQAECgEIAQAAAA==.Ballzac:BAAANQADCggICAAAAA==.Ballzout:BAAANQAECgUIBQABNQAFFAEIAQACAAAAAA==.Bamix:BAAANQADCgYIBgAAAA==.Bashm:BAAANQAECgUICAABNQAECggIEwACAAAAAA==.',
Be='Beaconbilly:BAAANQAECggICQAAAA==.Bearmanpig:BAAANQADCgMIAwAAAA==.Beelzemoan:BAAANQAECgEIAQAAAA==.Beens:BAACNQAFFIEKAAMKAAUJ5iEQAgDOAQAKAAUJ4h8QAgDOAQALAAEJriRgDQBmAAA1AAQKgSAAAgoACQkiJtgBAKkDAAoACQkiJtgBAKkDAAAA.Beewitched:BAAANQAECgEIAgAAAA==.Beloved:BAAANQAECgEIAQAAAA==.Belowzerolol:BAABNQAECoEYAAIMAAkJJw0jJQBEAgAMAAkJJw0jJQBEAgABNQAFFAcIFQANAD4kAA==.Benkaz:BAAANQAECgUIBwABNQAECgkJIAABAKAfAA==.',
Bi='Bierhops:BAAANQADCgcIBwAAAA==.Bigchimpin:BAAANQADCgcIBwAAAA==.',
Bl='Blacktacular:BAAANQADCgQIBAAAAA==.Bloodlust:BAAANQAECgcIEQAAAA==.Bluedaemon:BAAANQAECgQIBAAAAA==.Bluenchi:BAAANQADCggICgAAAA==.Blunttruama:BAAANQADCgYIBgAAAA==.',
Bo='Boomboompow:BAAANQADCgUICgAAAA==.',
Br='Breadbowl:BAAANQAECgcICgAAAA==.Brrzerk:BAAANQADCggICwAAAA==.',
Bu='Bubblesburst:BAAANQADCgYICQABNQAECgEIAgACAAAAAA==.Bubblëdin:BAAANQADCgYICgAAAA==.Buckee:BAABNQAECoELAAMOAAYJYBTlGAC4AQAOAAYJYBTlGAC4AQAPAAEJzAbgTAAwAAAAAA==.Buckets:BAAANQADCgcIDQAAAA==.Bucknutt:BAAANQAECgQIBwAAAA==.Buffoutlaw:BAABNQAECoEYAAIQAAkJ6iAxAQBJAwAQAAkJ6iAxAQBJAwABNQAFFAcIFQAQAO8mAA==.Bullzzeye:BAAANQAFFAIIAgAAAA==.Butternipz:BAAANQADCgcIBwAAAA==.',
By='Byshop:BAAANQAECgYIBgAAAA==.',
Ca='Cabe:BAAANQAECgQIBgAAAA==.Caerra:BAAANQADCgIIAgAAAA==.Caggarm:BAAANQAECgIIAgAAAA==.Cailber:BAAANQADCgUIBwAAAA==.Callipriest:BAAANQAECgQICgAAAA==.Castermaster:BAAANQAECgQICgAAAA==.',
Ce='Celthrinor:BAAANQAECgUIBQAAAA==.Cerevistra:BAAANQADCgEIAQAAAA==.',
Ch='Chakkah:BAAANQADCgQIBAAAAA==.Chillyy:BAAANQAECgcIEwAAAA==.Chipss:BAAANQABCgIIAgAAAA==.Chispot:BAAANQAECgEIAgAAAA==.Chitorpedo:BAAANQAECgQIBgAAAA==.Chodester:BAAANQADCgUIBQAAAA==.Chronis:BAAANQABCgYICgAAAA==.',
Ci='Cidel:BAAANQADCgUIBwAAAA==.Cifer:BAAANQADCgYIBgAAAA==.',
Co='Comatoast:BAAANQAECgYIDwAAAA==.Comeback:BAAANQADCgYIBgAAAA==.Course:BAAANQADCgIIAgAAAA==.',
Cr='Crackalaks:BAAANQAECgIIAgAAAA==.Crazyb:BAAANQAECgUICAAAAA==.Croith:BAAANQAECgYIDQAAAA==.Crotch:BAAANQABCgEIAgAAAA==.Crushbucket:BAAANQADCgQIBAAAAA==.Cryingorc:BAAANQAECgEIAQAAAA==.Crúz:BAAANQAECgEIAgAAAA==.',
Cw='Cwap:BAAANQAECgIIAgAAAA==.',
Cy='Cyndraylitha:BAAANQADCgYIBgAAAA==.',
Da='Daddywaumpus:BAAANQADCggICAAAAA==.Dageris:BAAANQAECgQIBAAAAA==.Damonic:BAAANQADCgYIBgABNQAFFAEIAQACAAAAAA==.Danas:BAAANQADCggIDgAAAA==.Darkwraith:BAAANQABCgMIBAABNQAECgEIAQACAAAAAA==.Davicurn:BAAANQADCggIEAAAAA==.Daythyme:BAAANQAECgIIAgAAAA==.',
De='Deadornot:BAAANQAECgUIBwAAAA==.Deadywaumpus:BAAANQAECgcIEwAAAA==.Deathbubbles:BAAANQADCgYIBwAAAA==.Deathkong:BAAANQAECgcIDwAAAA==.Deathofdager:BAAANQADCggICAAAAA==.Deetwenty:BAAANQAECgIIAgAAAA==.Deeztotemz:BAAANQAECgIIAgAAAA==.Demairis:BAAANQADCgcIBwAAAA==.Demonstyle:BAAANQAECgIIAgABNQAECgQICQACAAAAAA==.Desiiria:BAAANQAECgEIAQAAAA==.Deylicious:BAAANQAECggICAABNQAFFAcIFQALADYfAA==.',
Dh='Dhani:BAAANQAECgQIBwAAAA==.',
Di='Dietdrpibb:BAAANQADCgcIEQAAAA==.Diiemoar:BAAANQAECggIBAAAAA==.Dijoe:BAAANQAECgMIBgAAAA==.Dimmencius:BAAANQADCgQIBAAAAA==.Dippndotz:BAAANQAECggIEwAAAA==.Discfunction:BAAANQADCgcIGgAAAA==.Disciple:BAAANQADCgYIBgAAAA==.',
Do='Doafliploser:BAAANQADCgYIBgAAAA==.Dogwalterll:BAAANQAECgUIDQAAAA==.Dohvahkiin:BAAANQADCgYIBgAAAA==.Dontlosmë:BAAANQADCgQIBAABNQADCgYICgACAAAAAA==.',
Dr='Draaragon:BAAANQADCggICwABNQAFFAcIFQABALUgAA==.Dracgutx:BAAANQADCgYIBgAAAA==.Dragonboffa:BAAANQADCgYIEgAAAA==.Dragonlyfans:BAABNQAECoEgAAMRAAkJxRW7CACFAgARAAkJxRW7CACFAgASAAgJ3A5HEgDzAQABNQAFFAcIFAAEAIIjAA==.Dripz:BAAANQADCggIHAAAAA==.Drive:BAAANQAECgUICQAAAA==.Dryadwood:BAAANQADCgcIDQAAAA==.',
Du='Dubby:BAAANQAECgcIEgAAAA==.Duelley:BAAANQABCgYICQAAAA==.Dumptruckdan:BAABNQAECoEdAAIJAAkJ2BUXLQBZAgAJAAkJ2BUXLQBZAgABNQAFFAcIFQATADUcAA==.Durgur:BAAANQADCggICAABNQAECgcIEAACAAAAAA==.',
Ea='Eardi:BAAANQAECggIDQAAAA==.Earthpounder:BAAANQAECgQIBwAAAA==.',
Ec='Echoez:BAAANQAECgcIEgAAAA==.Eclipsa:BAAANQAECgQICAAAAA==.',
Ee='Eebo:BAAANQADCgMIAwAAAA==.',
El='Elbram:BAAANQADCggICAABNQAECgQIBwACAAAAAA==.Elunasolz:BAEANQADCggIFAABNQAECgQIBgACAAAAAA==.',
Em='Emilil:BAAANQADCggIDAAAAA==.Eminence:BAAANQADCggIFgAAAA==.',
En='Enlight:BAAANQABCgMIAwAAAA==.',
Er='Erdorco:BAAANQADCggICwABNQAECgUICgACAAAAAA==.',
Es='Escanor:BAAANQAECgIIAgAAAA==.Esu:BAAANQADCgUIBgAAAA==.',
Eu='Eudaimonia:BAAANQADCgYIDwAAAA==.',
Ex='Exias:BAAANQADCggIEgAAAA==.',
Fa='Facebeata:BAAANQAECgcIEgAAAA==.Faize:BAAANQADCggIDgABNQAFFAQICAAUACsJAA==.Falae:BAAANQAECgMIBgABNQAFFAIIAwACAAAAAA==.Fathêrhêlp:BAAANQADCgEIAQAAAA==.Faunuis:BAACNQAFFIEUAAMEAAcJgiNiAQAmAgAEAAUJgiViAQAmAgAUAAIJwhA9BQCaAAA1AAQKgR4AAwQACQk6JKIBAM0DAAQACQk6JKIBAM0DABQABgmKHW8VAMgBAAAA.Fawnbby:BAAANQAECgUIBQAAAA==.',
Fe='Featherbrain:BAAANQAECgMIBAAAAA==.Felhell:BAAANQADCggIFwABNQAECgcIEwACAAAAAA==.Ferenyet:BAAANQADCgYIBgAAAA==.Fermagus:BAAANQAECgUIEAAAAA==.',
Fi='Fistflurry:BAAANQAECgUIBQABNQAFFAEIAQACAAAAAA==.Fistlad:BAACNQAFFIEVAAIRAAcJrCYDAAAxAwARAAcJrCYDAAAxAwA1AAQKgR4AAhEACQkHJwgAACEEABEACQkHJwgAACEEAAAA.Fizzybubbles:BAAANQAECgUICgAAAA==.',
Fl='Flamehunter:BAAANQAECggIEAAAAA==.Flapple:BAABNQAECoEgAAIRAAkJniLoAQB7AwARAAkJniLoAQB7AwAAAA==.Flexicution:BAAANQADCgYIBgABNQAECgQIBAACAAAAAA==.Floweret:BAAANQAECgIIAgABNQAECgQIBAACAAAAAA==.Flu:BAAANQADCgEIAQABNQAECgIIAgACAAAAAA==.Flûffy:BAAANQAECgIIAwAAAA==.',
Fr='Freaknikk:BAAANQAECgUIDAABNQAECgYIDgACAAAAAA==.Freightraìn:BAAANQADCgIIAgABNQAECgcIDQACAAAAAQ==.Frozalth:BAAANQADCgUIBgAAAA==.',
Fu='Fudgemuffin:BAAANQAECgQIBAAAAA==.Furyofgnomes:BAAANQADCgEIAQABNQADCgYIBgACAAAAAA==.',
['Fë']='Fënrïr:BAAANQAECgMIBgABNQAECggIGAAVAB8cAA==.',
['Fú']='Fúzzybútt:BAAANQADCgMIAwAAAA==.',
Ga='Galice:BAAANQADCgMIAwAAAA==.Gardasil:BAAANQADCgYIBgAAAA==.Garlim:BAAANQADCgUIBQAAAA==.Gazebogary:BAAANQAECggIDAABNQAFFAcIFQATADUcAA==.',
Ge='Gellysong:BAAANQABCgQIBgAAAA==.Genos:BAAANQAECgEIAQAAAA==.Gerlim:BAAANQADCgEIAQAAAA==.',
Gi='Gix:BAAANQAECgEIAQAAAA==.',
Gl='Glolock:BAAANQAECgQIBgAAAA==.Glopanx:BAAANQAECgEIAQABNQAECgQIBgACAAAAAA==.',
Go='Goresnot:BAAANQADCggIGwAAAA==.',
Gr='Granrok:BAAANQADCgYIBgAAAA==.Gravedarknes:BAAANQAFFAIIAgAAAA==.Greendog:BAAANQADCgIIAgABNQAECgQIDgACAAAAAA==.Grievur:BAAANQADCgcIBwABNQAECggIDQACAAAAAA==.Grishknight:BAAANQADCggICgAAAA==.',
Gu='Guap:BAABNQAECoEYAAITAAkJzBn8RwB2AgATAAkJzBn8RwB2AgABNQAFFAcIFQARAKwmAA==.Gunray:BAAANQADCgUIBQAAAA==.Guttamane:BAAANQADCggIEgAAAA==.Gutx:BAAANQAECgEIAQAAAA==.',
Gy='Gyarrados:BAAANQADCgYIEAAAAA==.Gypsywolfe:BAAANQAECgMIBAAAAA==.',
['Gí']='Gífted:BAAANQAECgcIEwAAAA==.',
['Gü']='Günz:BAAANQABCgEIAQAAAA==.',
Ha='Hakasan:BAAANQAECgEIAQABNQAFFAEIAQACAAAAAA==.Haleybeary:BAAANQAECgEIAQAAAA==.Harawing:BAAANQADCgUIBQAAAA==.Hargrim:BAAANQADCggIDwAAAA==.Hastega:BAAANQAECgQIDgAAAA==.Haydonk:BAAANQADCgcIBwAAAA==.',
He='Herbage:BAAANQAECgQIBwAAAA==.Herrbjorn:BAAANQADCggIGgAAAA==.',
Hi='Hinata:BAAANQADCgQIBAAAAA==.Hippopotamus:BAAANQAECgMIAwAAAA==.Hitaman:BAAANQAECgEIAgAAAA==.',
Ho='Holik:BAAANQABCgEIAQAAAA==.Holybaguette:BAAANQAECgEIAQAAAA==.Holycritbro:BAAANQAECgEIAQAAAA==.Horôn:BAAANQAECgEIAQAAAA==.Hotgirlmegan:BAAANQAECggIBAAAAA==.Houndoomm:BAAANQADCggIHQAAAA==.',
Hr='Hriste:BAAANQAECgUICQAAAA==.',
Hu='Hunteress:BAAANQADCgQIBAAAAA==.Huntyhunt:BAAANQAECgIIAgAAAA==.',
Im='Imnosickmall:BAAANQAECgIIAQAAAA==.Impmafia:BAAANQAECgMIAgAAAA==.',
In='Incognetus:BAAANQAECgcIDQAAAQ==.Insurrection:BAAANQAECgUIBQABNQAECgYIDwACAAAAAA==.',
Ir='Ironmaiiden:BAAANQADCgYIDAAAAA==.Ironpally:BAAANQAECgUICAAAAA==.',
Iw='Iwantmead:BAAANQABCgMIAwAAAA==.',
Ja='Jaduen:BAAANQADCggIHQAAAA==.Jaesedar:BAAANQAFFAIIAwAAAA==.Jaestoes:BAAANQAECgEIAQABNQAFFAIIAwACAAAAAA==.Jaycen:BAAANQAECgQIBwABNQAECgcIDQACAAAAAQ==.',
Je='Jellythug:BAAANQAECgQIBgAAAA==.Jenny:BAAANQAECgMIAwAAAA==.Jerksnknight:BAAANQAECgQIBwAAAA==.Jethon:BAAANQADCgcIDwAAAA==.Jexro:BAABNQAECoEdAAIWAAkJZiQEAgCtAwAWAAkJZiQEAgCtAwAAAA==.Jezebaal:BAAANQAECgIIAgAAAA==.',
Jg='Jgremlin:BAAANQADCgUICAAAAA==.',
Ji='Jiun:BAAANQAECgMIAwAAAA==.',
Jo='Johnseenah:BAAANQADCgYIDAAAAA==.Jonnybravo:BAAANQAECgQICQAAAA==.Joshton:BAAANQADCgUIBQAAAA==.',
Jr='Jrrd:BAAANQAECgQIBQAAAA==.',
Ju='Judgmentoe:BAAANQADCggIGgAAAA==.Jusstice:BAAANQAECgQIBgAAAA==.',
Ka='Kack:BAAANQADCgYICgAAAA==.Kadzageth:BAAANQAECgEIAQAAAA==.Kalvosa:BAAANQADCgUICQAAAA==.Karlbarx:BAAANQAECgQIBAAAAA==.Kasaa:BAAANQAECgUICgAAAA==.Kasheira:BAAANQAECgQIBwAAAA==.Katti:BAAANQAECgQICwAAAA==.Katzfiel:BAAANQAECgQIBgAAAA==.Kaytwo:BAACNQAFFIEMAAIXAAYJASIGAQB3AgAXAAYJASIGAQB3AgA1AAQKgRgAAhcACQllJrUEALYDABcACQllJrUEALYDAAAA.',
Kb='Kblasti:BAAANQADCggIHQABNQAECgkJFwAEAMYbAA==.Kblastissimo:BAABNQAECoEXAAIEAAkJxhu7DgD/AgAEAAkJxhu7DgD/AgAAAA==.',
Kc='Kcommandr:BAAANQADCggICAABNQAECgUICgACAAAAAA==.',
Ke='Kendramp:BAAANQAECgQIBAAAAA==.Kersplode:BAAANQAECgMIBQABNQAECggIEwACAAAAAA==.',
Kh='Khariia:BAAANQADCgQIBAAAAA==.',
Ki='Kieloran:BAAANQAECgYIEAAAAA==.Kieralyn:BAAANQAECgEIAgAAAA==.Kiltlifter:BAAANQAECgEIAQAAAA==.Kisol:BAAANQADCgYIBgAAAA==.',
Ko='Koaladashian:BAAANQAECggIDwAAAA==.Koalaficent:BAAANQAECggIDgAAAA==.Kojodruid:BAAANQADCgYICgAAAA==.Kojohunter:BAAANQAECgEIAQAAAA==.Kong:BAAANQAECgUIBQAAAA==.Kookta:BAAANQAECgcIDwAAAA==.Kozmo:BAAANQAECgQIBQAAAA==.',
Kr='Kreep:BAAANQADCggIEAAAAA==.Kreepur:BAAANQADCgYIBgAAAA==.Kresnik:BAAANQADCgUIBQAAAA==.',
Ku='Kundin:BAAANQAECgYIDAABNQAECgkJGAABACcbAA==.Kurai:BAAANQAECgYIDQAAAA==.Kutaki:BAAANQADCgcIGgABNQABCgEIAQACAAAAAA==.',
['Kí']='Kíngbradley:BAAANQADCgQIBAABNQAECggIEwACAAAAAA==.',
La='Lasrin:BAABNQAECoEcAAIJAAkJRB7sEQASAwAJAAkJRB7sEQASAwAAAA==.Lavenia:BAAANQADCggIDAAAAA==.',
Ld='Ldawg:BAAANQAECgYIDQAAAA==.',
Le='Leastzenmonk:BAAANQAECgYIDgABNQAFFAUICAAYAGoQAA==.Lelu:BAAANQADCgUIBQAAAA==.Leucetios:BAAANQAECgEIAQAAAA==.',
Li='Liello:BAAANQAECgIIAQAAAA==.Lightchaos:BAAANQAECgYIBgAAAA==.Lightice:BAAANQADCgMIAwAAAA==.Lilgaypunk:BAABNQAECoEhAAIFAAkJwR3JBwAYAwAFAAkJwR3JBwAYAwAAAA==.Lilgaypunkk:BAAANQADCgUIBQABNQAECgkJIQAFAMEdAA==.Littlecyka:BAAANQADCggICAAAAA==.',
Lo='Lockfocks:BAAANQADCggICAABNQAECgEIAQACAAAAAA==.Locoscar:BAABNQAECoEiAAMLAAkJtSWFAQDRAwALAAkJtSWFAQDRAwAKAAQJ3BQXMQDVAAAAAA==.Loktark:BAACNQAFFIEVAAIQAAcJ7yYBAAACAwAQAAcJ7yYBAAACAwA1AAQKgR4AAhAACQnCJgwAAAQEABAACQnCJgwAAAQEAAAA.Lotei:BAAANQAECgIIAgAAAA==.',
Lu='Luckylock:BAAANQADCgYIBgABNQAECgcIBwACAAAAAA==.Lucresh:BAAANQADCgYIBgAAAA==.Lula:BAAANQADCgIIAgAAAA==.Lunasolz:BAEANQADCggIFgABNQAECgQIBgACAAAAAA==.Lustíé:BAAANQAECgIIAgAAAA==.',
Ly='Lythinlock:BAAANQAECgQIBwAAAA==.',
['Là']='Lànthus:BAAANQAECgYICQAAAA==.',
['Lê']='Lêêrøy:BAAANQADCgYICgAAAA==.',
Ma='Magedood:BAAANQAECgQIBAAAAA==.Magev:BAAANQAECgQIBwAAAA==.Magiccheif:BAAANQAECgQIDAAAAA==.Magnuz:BAAANQADCgQIBwAAAA==.Maisharona:BAAANQADCgYIDAABNQAECgYIFAATAKMhAA==.Makanir:BAAANQADCgIIBAAAAA==.Maleficent:BAAANQADCgEIAQAAAA==.Manginah:BAAANQAFFAEIAQAAAA==.Mavanthis:BAAANQAECgUICQAAAA==.Maxdizaster:BAAANQAECgQIBgAAAA==.Mazkaz:BAAANQADCgUIBQAAAA==.',
Mc='Mcbonk:BAABNQAECoEZAAMXAAkJhyBcGwDzAgAXAAkJVR5cGwDzAgAZAAMJCCQkDAAjAQAAAA==.Mckniferson:BAAANQADCgQIBgAAAA==.',
Me='Merlenoir:BAAANQADCgUIBQAAAA==.Messybedhead:BAABNQAECoEYAAQUAAgJShitDABjAgAUAAgJShitDABjAgADAAIJjAacIABcAAAEAAEJMwfNagBBAAABNQADCgYIBgACAAAAAA==.Methindour:BAAANQAECgEIAQAAAA==.',
Mi='Mightydwarf:BAAANQADCggIDgAAAA==.Mintwiskers:BAAANQAECgQIBgAAAA==.Misiana:BAAANQAECggIDQAAAA==.Mivix:BAAANQAECgUICAABNQAFFAYIEgANACQZAA==.',
Mo='Mom:BAAANQADCggIDgABNQAECggIFgAWAOgdAA==.Monkeyclaw:BAAANQAECgUIDQAAAA==.Moonfist:BAAANQADCgQIBAAAAA==.Mordrak:BAAANQAECgQICAAAAA==.Mordë:BAABNQAECoENAAMaAAcJjApTJgAJAQAaAAUJqghTJgAJAQAbAAQJHAyrjADMAAAAAA==.Mormzie:BAAANQAECgEIAQABNQAECgUIDQACAAAAAA==.Morwy:BAAANQAECgYIBgAAAA==.Moøbytoo:BAAANQAECgQIBwABNQAECgUICgACAAAAAA==.',
Ms='Msedd:BAAANQADCgMIAwAAAA==.',
Mu='Mugged:BAAANQAECgcIDwAAAA==.Muinogaraa:BAAANQAECgIIAgABNQAFFAcIFQABALUgAA==.Mum:BAABNQAECoEWAAIWAAgJ6B1eDADTAgAWAAgJ6B1eDADTAgAAAA==.Murked:BAAANQADCgQIBAAAAA==.Mushmouth:BAAANQAECgYIDgAAAA==.',
My='Myguy:BAAANQADCgYICgAAAA==.Mysiara:BAAANQADCggIEwAAAA==.',
['Mà']='Màjestic:BAAANQADCgYIDAAAAA==.',
['Mì']='Mìchael:BAAANQAECgQIBgAAAA==.',
['Mú']='Músu:BAAANQAECgYICwAAAA==.',
Na='Nagosho:BAAANQADCgcIBwAAAA==.Nampur:BAAANQAECgEIAQAAAA==.Naril:BAAANQAECgQIBAAAAA==.Narvana:BAAANQAECgQIDgAAAA==.Naughtyboy:BAAANQAECgEIAQABNQAECgkJFQATAPAfAA==.Nayalla:BAAANQAECgEIAQAAAA==.',
Ni='Nightbirdie:BAAANQAECgIIAgAAAA==.Nightshotz:BAAANQAECgQIBAAAAA==.Nitezz:BAAANQADCgMIAwAAAA==.Nityblast:BAAANQADCgYIDQAAAA==.',
No='Nodrus:BAAANQAECgIIAgAAAA==.Nogaraa:BAAANQAECgcIBwABNQAFFAcIFQABALUgAA==.Novath:BAACNQAFFIEVAAIMAAcJ4R8aAADIAgAMAAcJ4R8aAADIAgA1AAQKgSAAAwwACQkWJcQAANUDAAwACQkWJcQAANUDAAkABAkmJBRXAJ0BAAAA.',
Ny='Nyssarissa:BAAANQAECgcIEgAAAA==.',
['Nè']='Nèliel:BAAANQAECgMIBgAAAA==.',
Oa='Oakenstream:BAAANQADCgIIAgAAAA==.',
Oe='Oennogaraa:BAAANQADCggICAABNQAFFAcIFQABALUgAA==.',
Op='Ophélia:BAAANQAECgMIAwAAAA==.',
Or='Orbz:BAAANQADCgYIBQAAAA==.Orusmar:BAAANQADCgYIDQAAAA==.',
Ot='Otterguy:BAAANQAECgYIBgAAAA==.',
Ou='Oui:BAAANQAECgQIBgAAAA==.',
Ov='Overheated:BAAANQADCgYIDwAAAA==.',
Pa='Paalaz:BAACNQAFFIEFAAIcAAMJBxuaAwAkAQAcAAMJBxuaAwAkAQA1AAQKgRkAAhwACQmeI7AFAEsDABwACQmeI7AFAEsDAAAA.Paeldryth:BAABNQAECoEeAAMPAAkJWSYOAQCyAwAPAAkJWSYOAQCyAwAOAAgJPRnQDgBAAgAAAA==.Paliesto:BAAANQAECgEIAQAAAA==.Paljin:BAAANQADCgcICAAAAA==.Palkia:BAAANQAECgQIBQAAAA==.Palmface:BAAANQAECgQIBgAAAA==.Panatepriest:BAAANQAECgIIAgAAAA==.Pandadante:BAAANQAECgEIAQABNQAECgcIEgACAAAAAA==.Pandatunado:BAABNQAECoEZAAILAAgJYx4GEQDvAgALAAgJYx4GEQDvAgAAAA==.Panky:BAAANQAECgUICgAAAA==.',
Pe='Pedrocerrano:BAAANQAECgYICwAAAA==.Pelt:BAAANQAECggIEwAAAA==.Pewbot:BAAANQAECgUIBwABNQAECgcIDQACAAAAAQ==.',
Ph='Phoebë:BAAANQADCgUIBwAAAA==.Phusiion:BAAANQAECgEIAQAAAA==.',
Pi='Pickledin:BAAANQAECgUICQAAAA==.Pinecones:BAAANQAECgcIBwABNQAECgkJHwAXAJ4jAA==.',
Pk='Pkmntrainer:BAAANQADCgYIFgABNQADCgcIEQACAAAAAA==.',
Pl='Please:BAACNQAFFIEVAAIYAAcJeAfuAAAsAgAYAAcJeAfuAAAsAgA1AAQKgR4AAhgACQnmH2MLAA4DABgACQnmH2MLAA4DAAAA.Pleasetwo:BAABNQAECoEgAAIYAAkJwg0FMgDwAQAYAAkJwg0FMgDwAQABNQAFFAcIFQAYAHgHAA==.Plumaril:BAAANQAECgQIBgAAAA==.',
Po='Pondero:BAAANQADCgEIAQABNQAECgcICgACAAAAAA==.',
Pp='Ppleakin:BAAANQAECgcIEwAAAA==.',
Pr='Pranzar:BAAANQAECgYICQAAAA==.Prepdagoat:BAAANQADCggIGwABNQADCgQIBAACAAAAAA==.',
Pt='Pticky:BAAANQAECgIIAgABNQAFFAEIAQACAAAAAA==.',
Pu='Pullo:BAABNQAECoEWAAMdAAgJHBM0IwAfAgAdAAgJHBM0IwAfAgAeAAEJNBRmTwA3AAAAAA==.Punctualpaul:BAAANQAECggIDQABNQAFFAcIFQAMAOEfAA==.Purple:BAAANQAECgYIBgAAAA==.',
Py='Pyrê:BAAANQADCgYICgAAAA==.',
Qu='Quidditch:BAAANQAECgUICgAAAA==.',
Qw='Qwadsfwfgads:BAABNQAFFIETAAIUAAcJOyAHAADMAgAUAAcJOyAHAADMAgAAAA==.Qwamsfwfgads:BAAANQAECgIIAgABNQAFFAcIEwAUADsgAA==.',
Ra='Rabbi:BAAANQAECgIIAgABNQAECgcIDQACAAAAAQ==.Raelavent:BAAANQAECgEIAQAAAA==.Ragrappy:BAACNQAFFIEVAAINAAcJPiQQAAC6AgANAAcJPiQQAAC6AgA1AAQKgR4AAg0ACQm0JsAAAM0DAA0ACQm0JsAAAM0DAAAA.Raiju:BAAANQAECgQIBQAAAA==.Rakion:BAAANQAECgUIBQAAAA==.Ramped:BAAANQADCgUIBQAAAA==.Raszahk:BAAANQAECgcIEgABNQAFFAIIAwACAAAAAA==.',
Re='Reavêr:BAAANQAECgQIBwAAAA==.Redreximus:BAAANQAECgYICgAAAA==.Regilock:BAAANQAECgQICAAAAA==.Retlec:BAAANQAECgUICAAAAA==.Reïki:BAAANQADCgYIDAAAAA==.',
Ri='Ripto:BAAANQAECgEIAQAAAA==.',
Ro='Rochaca:BAAANQADCgUICQAAAA==.Roshana:BAAANQAECgQIBgAAAA==.Rothoof:BAAANQAECgMIAwAAAA==.',
Ru='Rudnos:BAAANQADCgMIAgABNQAECgQICQACAAAAAA==.Rumham:BAAANQAECgEIAQAAAA==.Ruzzart:BAAANQADCgQIBAAAAA==.',
Ry='Ryptup:BAAANQAECgQIBAAAAA==.',
['Rô']='Rôinujj:BAAANQAECgEIAQAAAA==.',
Sa='Safiyah:BAAANQAECgUICgAAAA==.Saltyevoker:BAAANQADCggIFgAAAA==.Same:BAABNQAECoEYAAIUAAkJiCE4AwBIAwAUAAkJiCE4AwBIAwABNQAFFAcIFQAMAOEfAA==.Samophlangy:BAAANQABCgIIAgAAAA==.Sandorstus:BAAANQAECgQICgAAAA==.Saothome:BAAANQAECgIIAgAAAA==.Sathreal:BAAANQAECgEIAQAAAA==.Saywho:BAAANQADCgUICQAAAA==.',
Sc='Scalywaumpus:BAAANQADCggICAAAAA==.Scienta:BAAANQAECggICwAAAA==.Scope:BAAANQADCgYIBgAAAA==.Scrubdk:BAAANQADCgcIBwABNQAECgYIBgACAAAAAA==.Scúbasteve:BAAANQAECgQIBwAAAA==.',
Se='Sefirot:BAAANQAECgEIAQAAAA==.Selinddra:BAAANQAECgEIAQAAAA==.Serrafin:BAAANQAECgcIAQAAAA==.',
Sh='Shadebringer:BAAANQADCggIFAAAAA==.Shadowboxin:BAAANQADCgUIBQAAAA==.Shamdaddy:BAAANQAECgQIBgAAAA==.Shamezee:BAAANQAECgQIBgAAAA==.Shampoo:BAAANQAECgMIAwAAAA==.Sharlotte:BAAANQADCggIDQAAAA==.Shilas:BAABNQAECoEZAAIBAAkJ/hmcCwCSAgABAAkJ/hmcCwCSAgABNQAECgkJHwAXAJ4jAA==.Shishkabug:BAAANQADCgIIAgAAAA==.Shownuph:BAAANQADCgEIAQAAAA==.',
Si='Sicilianhero:BAAANQADCggIDgAAAA==.Singelock:BAAANQAECgQIBAAAAA==.Sinsyn:BAAANQADCggICAABNQAECgQIBAACAAAAAA==.Sinwarrior:BAAANQAECggICAABNQAFFAUICwAGALEYAA==.Sizz:BAAANQADCgQIBAAAAA==.',
Sk='Skipcawk:BAACNQAFFIEVAAMLAAcJNh8JAAC8AgALAAcJqR4JAAC8AgAKAAQJ8BSyBABbAQA1AAQKgR4AAwoACQncJg8AABAEAAoACQnaJg8AABAEAAsABglNHSpIANcBAAAA.Skorpco:BAABNQAECoEYAAIWAAkJtRZvDwCjAgAWAAkJtRZvDwCjAgAAAA==.',
Sl='Slickngrity:BAAANQABCgMIAwAAAA==.Sluggo:BAAANQADCggIEAAAAA==.',
Sm='Smulol:BAAANQAECgYIDQAAAA==.',
Sn='Snoopfrogg:BAAANQAECgQICAAAAA==.Snow:BAAANQAECgUIBQAAAA==.',
So='Solfire:BAAANQAECgUICQAAAA==.Solstice:BAAANQAECgMIAwAAAA==.Sometingwong:BAAANQAECgQIBAAAAA==.',
Sp='Spamheal:BAAANQADCgcIDwAAAA==.Sparkle:BAAANQADCgcICAAAAA==.Spliffy:BAAANQABCgEIAQAAAA==.Spodermenpls:BAAANQADCgIIAgABNQAFFAUICAAYAGoQAA==.',
St='Stabber:BAAANQADCgQIBAAAAA==.Stoc:BAAANQAECgYIBgAAAA==.Stormweaver:BAAANQAECgQIBQAAAA==.',
Su='Suinogaraa:BAAANQADCgYIBgABNQAFFAcIFQABALUgAA==.Sunderwhere:BAAANQAFFAIIAwAAAA==.Superhomie:BAAANQABCgIIAQAAAA==.',
Sw='Swann:BAAANQAECgcIDgAAAA==.Swavor:BAAANQAECgUIBQAAAA==.Sweetbella:BAAANQADCgUIDAAAAA==.Swurves:BAAANQAECgIIAgAAAA==.',
Sy='Symbio:BAAANQADCggIDQAAAA==.Syna:BAAANQAECgQIBQAAAA==.',
Ta='Taearo:BAAANQAECgQIBAAAAA==.Taime:BAAANQAECgQICAAAAA==.Talirn:BAAANQADCggIFAAAAA==.Tallanvor:BAAANQADCggIEQAAAA==.',
Te='Teddywaumpus:BAAANQADCgYIBgAAAA==.Tendecay:BAAANQAECgQIBwAAAA==.',
Th='Thanquiol:BAACNQAFFIEVAAIHAAcJvB8DAACsAgAHAAcJvB8DAACsAgA1AAQKgR4AAgcACQk/JT0AANcDAAcACQk/JT0AANcDAAAA.Thebaraj:BAAANQAECgUIDQAAAA==.Thebigdawg:BAAANQADCgUICAAAAA==.Thedruidd:BAAANQADCgYICQAAAA==.Theeassassin:BAAANQADCgIIAQAAAA==.Thelance:BAAANQAECgEIAQAAAA==.Theseglaives:BAAANQAECgEIAQAAAA==.Thrilled:BAAANQAECgIIAwAAAA==.Thyora:BAABNQAECoEdAAQSAAkJJhHNEAAPAgASAAkJJhHNEAAPAgARAAQJFg93GwDuAAAfAAIJ9hc8DwB/AAAAAA==.',
Ti='Tijdruid:BAAANQAECgIIAgAAAA==.',
To='Tommypickles:BAACNQAFFIEVAAMTAAcJNRwPAgAuAgATAAYJwRgPAgAuAgAgAAIJLCKEAADZAAA1AAQKgSAAAxMACQn0Jd0CAM4DABMACQn0Jd0CAM4DACAAAgk+JsgQAN0AAAAA.Tomtrocity:BAAANQADCgUICQAAAA==.Tonestar:BAAANQAECgIIAgAAAA==.Toturaka:BAAANQADCgUIBQAAAA==.',
Tr='Trackerjoe:BAAANQADCgMIBAAAAA==.Train:BAAANQADCgIIAgABNQAECgcIDQACAAAAAQ==.Treerex:BAAANQAECgQIBwAAAA==.Troljin:BAAANQAECgYICwAAAA==.Trollpaladin:BAAANQAECgcIDAAAAA==.',
Ts='Tsipayeoc:BAAANQADCgcICAAAAA==.',
Tw='Twistedhavoc:BAAANQAECgEIAQAAAA==.Twk:BAAANQADCggIEgAAAA==.',
Ty='Tyrgann:BAAANQADCgUIBQAAAA==.Tytoflamina:BAAANQAECgEIAgAAAA==.',
Ui='Uiazel:BAAANQADCgEIAQAAAA==.',
Ul='Ulkanir:BAAANQADCgcICwAAAA==.',
Um='Umalinn:BAAANQAECgQIBgAAAA==.',
Ur='Urbellum:BAAANQADCgQIBAABNQAFFAUICgAXAOkJAA==.Urukhaixd:BAAANQABCgIIBAAAAA==.',
Va='Vacca:BAAANQAECgQIBgAAAA==.Vaeyethror:BAAANQADCgQIBAAAAA==.Vahvadon:BAAANQADCgQIBAAAAA==.Valucia:BAAANQADCgEIAQAAAA==.Vandagar:BAAANQAECgYICgAAAA==.Vapor:BAABNQAECoEpAAIQAAkJvCKlAACNAwAQAAkJvCKlAACNAwAAAA==.Varity:BAAANQABCgIIAgAAAA==.Varsity:BAABNQAECoEfAAIXAAkJniPdCACIAwAXAAkJniPdCACIAwAAAA==.Vason:BAAANQADCgMIAwAAAA==.',
Ve='Velaryn:BAAANQADCggICAAAAA==.Ventumceleri:BAAANQADCgUIBQAAAA==.',
Vh='Vhega:BAAANQABCgIIAgAAAA==.',
Vi='Victor:BAAANQABCgIIAgAAAA==.Vinyasa:BAAANQAECgUIBQAAAA==.',
Vo='Voodoobeast:BAAANQAECgQIBwAAAA==.',
Vu='Vulbahermosa:BAAANQAECgMIBgAAAA==.',
Wa='Waremtae:BAAANQADCgEIAQAAAA==.',
We='Wenguo:BAAANQAECgQIBQAAAA==.',
Wh='Wheatiees:BAAANQADCgcIDAAAAA==.Whyp:BAABNQAECoEZAAMPAAkJThqKCADFAgAPAAkJThqKCADFAgAOAAEJHwlGOgA3AAAAAA==.',
Wi='Wickle:BAAANQADCgcIBwAAAA==.Wingdaz:BAEANQADCggICQABNQAFFAEIAQACAAAAAA==.Wizliz:BAAANQADCgYIBgABNQAECgQICQACAAAAAA==.',
Xi='Xidara:BAAANQADCgcICAAAAA==.Xiqualani:BAAANQADCgYIBgAAAA==.Xivei:BAACNQAFFIESAAINAAYJJBmSAQAFAgANAAYJJBmSAQAFAgA1AAQKgRwAAw0ACQlFIPsTAKYCAA0ACQkaIPsTAKYCAAgABwksEAgHAJABAAAA.',
Xl='Xlegolas:BAAANQADCgUIBgAAAA==.',
Xo='Xorac:BAAANQAECgcIBwAAAA==.',
Xz='Xzach:BAABNQAECoEYAAIWAAkJgg1YGAAmAgAWAAkJgg1YGAAmAgAAAA==.',
Yi='Yinlou:BAAANQAECgEIAQAAAA==.',
Yo='Yorha:BAAANQADCgEIAQABNQAECgkJGAARAFIXAA==.',
Ys='Yshtolà:BAEANQAECgQIBgAAAA==.',
Yu='Yurmage:BAAANQAECgEIAQAAAA==.',
['Yì']='Yìffist:BAAANQADCgYIDAAAAA==.',
Za='Zachx:BAACNQAFFIEVAAQaAAcJ2yUbAAC1AQAaAAQJ7SUbAAC1AQAbAAMJJB+iBAAsAQAhAAIJECdgAADvAAA1AAQKgR4ABBoACQkZJuEAAIgDABoACQmuIuEAAIgDABsABwmDIBUZAJ0CACEAAgnDJUsLAOQAAAAA.Zaegorn:BAAANQAECggICwAAAA==.Zargar:BAABNQAECoEgAAIiAAkJSyGmAQB4AwAiAAkJSyGmAQB4AwAAAA==.Zarmakai:BAACNQAFFIEQAAMdAAYJrB8/AAAgAgAdAAUJpyM/AAAgAgAjAAEJxAskFgAuAAA1AAQKgR4AAh0ACQmkJk0AAAYEAB0ACQmkJk0AAAYEAAAA.',
Ze='Zenxo:BAAANQABCgYICQAAAA==.',
Zi='Zintalesh:BAAANQAECgIIAgAAAA==.Zionx:BAAANQADCgQIBAAAAA==.Zivie:BAAANQAECgYICwAAAA==.',
Zu='Zurry:BAAANQABCgEIAQAAAA==.',
Zy='Zygon:BAAANQAFFAEIAQAAAA==.',
['Ðr']='Ðrakie:BAAANQAECgYIBgAAAA==.',
['Ök']='Ökko:BAAANQAECgMIBAAAAA==.',
['Öw']='Öwly:BAAANQAECgYIBgAAAA==.',
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
