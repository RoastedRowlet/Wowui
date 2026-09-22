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

local lookup = {'Monk-Windwalker','Shaman-Restoration','Unknown-Unknown','Druid-Guardian','Druid-Balance','Priest-Shadow','Hunter-Marksmanship','Monk-Brewmaster','DemonHunter-Vengeance','Priest-Discipline','Paladin-Retribution','Warlock-Demonology','Hunter-BeastMastery','Paladin-Holy','Priest-Holy','Mage-Arcane','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','Monk-Mistweaver','DeathKnight-Blood','Warlock-Destruction','Evoker-Devastation','Evoker-Preservation','Hunter-Survival','Druid-Restoration','Shaman-Elemental','Warrior-Fury','Warrior-Arms','DemonHunter-Devourer','Paladin-Protection','Mage-Frost','Warrior-Protection','Warlock-Affliction','DemonHunter-Havoc','DeathKnight-Unholy','DeathKnight-Frost','Evoker-Augmentation','Shaman-Enhancement',}
local provider = {region='US',realm='Stormreaver',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aaragondelta:BAAANQAECgcIBwABNQAFFAcIFQABALUgAA==.Aaragonius:BAAANQADCggIEAABNQAFFAcIFQABALUgAA==.Aaragonneo:BAACNQAFFIEVAAIBAAcKtSCOAACiAgABAAcKtSCOAACiAgA1AAQKgSQAAgEACQprJl8AAPQDAAEACQprJl8AAPQDAAAA.Aaragontheta:BAAANQADCgIIAgABNQAFFAcIFQABALUgAA==.Aaragonxeta:BAAANQADCgEIAQABNQAFFAcIFQABALUgAA==.',
Ab='Ablé:BAABNQAECoEXAAICAAcKCRirOwACAgACAAcKCRirOwACAgAAAA==.',
Ac='Ackreseth:BAAANQAECgMIAwAAAA==.',
Ad='Adriön:BAAANQADCgYIBgAAAA==.',
Ae='Aeko:BAAANQAECgIIBAAAAA==.Aemeath:BAAANQADCgIIAgAAAA==.Aerae:BAAANQADCggIDQAAAA==.Aergoss:BAAANQAECgIJAgAAAA==.Aeristeia:BAAANQAECgcJEwAAAA==.Aethyria:BAAANQADCgYIBgABNQAECgIJAgADAAAAAA==.',
Ah='Ahriena:BAAANQADCgEIAQABNQAFFAYIFwAEAL4kAA==.',
Ai='Aiee:BAAANQAECgUJCAAAAA==.Aizén:BAAANQAECgYIDQAAAA==.',
Al='Allaboutme:BAAANQADCgUJBgAAAA==.',
Am='Amad:BAAANQAECgUJBQAAAA==.Amourn:BAAANQAECgIIAQAAAA==.',
An='Analrek:BAAANQAECgYJEAAAAA==.Antekhrestos:BAAANQADCgQIBAAAAA==.Antoinedruid:BAABNQAECoEgAAIFAAkKsR7wEQD5AgAFAAkKsR7wEQD5AgABNQAFFAYIDwAGAMAXAA==.',
Ap='Apocalypsis:BAAANQAECgQIBAABNQAECggIHQAHAEIMAA==.Apodal:BAABNQAECoEYAAIIAAkKXAuJDQCxAQAIAAkKXAuJDQCxAQABNQAFFAcIFQAJALwfAA==.Apoluss:BAAANQADCgYICwAAAA==.',
Ar='Arih:BAAANQADCgUIDAAAAA==.Arock:BAAANQAECgcJEgAAAA==.Arrithion:BAAANQAECgUICgAAAA==.Arthaz:BAACNQAFFIEPAAIGAAYKwBdeAQAWAgAGAAYKwBdeAQAWAgA1AAQKgSEAAwYACQqcJPwCAJsDAAYACQqcJPwCAJsDAAoAAgrqDTQVAGsAAAAA.',
As='Asgorath:BAAANQADCgcJBwAAAA==.Astandra:BAAANQAECgEJAQAAAA==.Astro:BAAANQADCgIIAgABNQAECgcIEwADAAAAAA==.',
At='Atexnogaraa:BAABNQAECoEYAAILAAkK6xprLACqAgALAAkK6xprLACqAgABNQAFFAcIFQABALUgAA==.',
Av='Averelles:BAAANQAECgYJEQAAAA==.',
Aw='Awwik:BAAANQAECgYJDAAAAA==.',
Az='Azsharaa:BAAANQAECgcIBwAAAA==.',
Ba='Babyjojo:BAAANQAECgUJCgAAAA==.Badaboomkin:BAAANQAECgMIBQABNQAFFAEIAQADAAAAAA==.Baeldun:BAAANQAECgUJDQAAAA==.Baethoven:BAAANQAECgUICgAAAA==.Bagagwa:BAAANQAECgEIAQAAAA==.Ballzac:BAAANQADCggICAAAAA==.Ballzout:BAAANQAECgcIDAABNQAFFAEIAQADAAAAAA==.Bamix:BAAANQADCgYIBgAAAA==.Bashm:BAAANQAECgYIDAABNQAECgkJHQAMAFIiAA==.',
Be='Beaconbilly:BAAANQAECggIEQAAAA==.Bearmanpig:BAAANQADCgcJBwAAAA==.Beelzemoan:BAAANQAECgQJCQAAAA==.Beens:BAACNQAFFIEPAAMHAAYKviJuAwDQAQAHAAUKKiFuAwDQAQANAAIKnSLPCgDVAAA1AAQKgSIAAgcACQo4JgMDAJMDAAcACQo4JgMDAJMDAAAA.Beewitched:BAAANQAECgEIAwAAAA==.Beloved:BAAANQAECgEIAQAAAA==.Belowzerolol:BAABNQAECoEYAAIOAAkKJw11MgAzAgAOAAkKJw11MgAzAgABNQAFFAcIFgAPAD4kAA==.Benkaz:BAAANQAECgUIBwABNQAECgUIBQADAAAAAA==.',
Bi='Bierhops:BAAANQADCgcIBwAAAA==.Bigchimpin:BAAANQADCgcIBwAAAA==.',
Bl='Blacktacular:BAAANQADCgQIBAAAAA==.Bloodlust:BAABNQAECoEZAAIFAAkKtRIHIgBdAgAFAAkKtRIHIgBdAgAAAA==.Bluedaemon:BAAANQAECgUICQAAAA==.Bluenchi:BAAANQADCggICwABNQAECgkJJAAQAAUmAA==.Blunttruama:BAAANQAECgUJBQAAAA==.',
Bo='Boomboompow:BAAANQADCgUICgAAAA==.',
Br='Breadbowl:BAAANQAECggIDgAAAA==.Brontide:BAAANQAECgIJAgABNQAECgYIDwADAAAAAA==.Brrzerk:BAAANQADCggICwAAAA==.Brrzrrq:BAAANQADCgEIAQAAAA==.',
Bu='Bubblesburst:BAAANQADCgYIDQABNQAECgEIAwADAAAAAA==.Bubblëdin:BAAANQADCgYICgAAAA==.Buckee:BAABNQAECoESAAMRAAgKdROYFgDyAQARAAcKWROYFgDyAQASAAIKjQ/AUACAAAAAAA==.Buckets:BAAANQADCgcIFAAAAA==.Bucknutt:BAAANQAECgUJDAAAAA==.Buffoutlaw:BAABNQAECoEYAAITAAkK6iDTAQArAwATAAkK6iDTAQArAwABNQAFFAcIFgATAO8mAA==.Bullzzeye:BAAANQAFFAIIAgAAAA==.Butternipz:BAAANQADCgcIBwAAAA==.',
By='Byshop:BAAANQAECgcIBwAAAA==.',
Ca='Cabe:BAAANQAECgYJDAAAAA==.Caerra:BAAANQADCgIIAgAAAA==.Caggarm:BAAANQAECgIIAgAAAA==.Cailber:BAAANQADCgUIBwAAAA==.Callipriest:BAAANQAECgQICgAAAA==.Castermaster:BAAANQAECgQICwAAAA==.',
Ce='Celthrinor:BAAANQAECgcJDAAAAA==.Cerevistra:BAAANQADCgEIAQAAAA==.',
Ch='Chaeni:BAAANQADCgMIAQAAAA==.Chakkah:BAAANQADCgQIBAAAAA==.Chillyy:BAABNQAECoEdAAMUAAkKZhdXCAC3AgAUAAkKZhdXCAC3AgABAAEK9ATTTQAkAAAAAA==.Chipss:BAAANQAECgQIBAAAAA==.Chispot:BAAANQAECgEJAgAAAA==.Chitorpedo:BAAANQAECgQIBgAAAA==.Chodester:BAAANQADCgUIBQAAAA==.Chokyo:BAAANQAECgUJBQAAAA==.Chronis:BAAANQABCgYICgAAAA==.',
Ci='Cidel:BAAANQADCgcJDQAAAA==.Cifer:BAAANQADCgYIBgAAAA==.',
Co='Comatoast:BAAANQAECgYIDwAAAA==.Comeback:BAAANQADCgYIBgAAAA==.Course:BAAANQADCgIIAgAAAA==.',
Cr='Crackalaks:BAAANQAECgQIBgAAAA==.Crazyb:BAAANQAECgYJDgAAAA==.Croith:BAAANQAECgYIEwAAAA==.Crotch:BAAANQABCgEIAgAAAA==.Crushbucket:BAAANQADCgQIBAAAAA==.Cryingorc:BAAANQAECgEIAQAAAA==.Crúz:BAAANQAECgIJBAAAAA==.',
Cw='Cwap:BAAANQAECgIIAgAAAA==.',
Cy='Cyndraylitha:BAAANQADCgYJBgAAAA==.',
Da='Daddywaumpus:BAAANQADCggJCAAAAA==.Dageris:BAAANQAECgUICQAAAA==.Damonic:BAAANQADCggIDgABNQAFFAEIAQADAAAAAA==.Danas:BAAANQADCggIDgAAAA==.Darkwraith:BAAANQABCgMIBAABNQAECgEIAQADAAAAAA==.Davicurn:BAAANQADCggIEAAAAA==.Daythyme:BAEANQAECgIIAgAAAA==.',
De='Deadornot:BAAANQAECgYJDQAAAA==.Deadywaumpus:BAABNQAECoEdAAIVAAkKQhhVGgCFAgAVAAkKQhhVGgCFAgAAAA==.Deathbubbles:BAAANQADCgYIBwAAAA==.Deathkong:BAAANQAECgcIDwAAAA==.Deathofdager:BAAANQADCggICAAAAA==.Deetwenty:BAAANQAECgQJBgAAAA==.Deeztotemz:BAAANQAECgIJAgAAAA==.Demairis:BAAANQADCgcIBwAAAA==.Demonstyle:BAAANQAECgIIAgABNQAECgUJDgADAAAAAA==.Desiiria:BAAANQAECgEIAQAAAA==.Deylicious:BAAANQAECggICQABNQAFFAcIFgANAHEfAA==.',
Dh='Dhani:BAAANQAECgUIDAAAAA==.',
Di='Dietdrpibb:BAAANQADCgcIEQAAAA==.Diiemoar:BAAANQAECggICgAAAA==.Dijoe:BAAANQAECgQJCgAAAA==.Dimmencius:BAAANQAECgMJBAAAAA==.Dippndotz:BAABNQAECoEYAAMWAAkKxxecFgCgAQAWAAcKqxKcFgCgAQAMAAYKahWXcQBuAQAAAA==.Discfunction:BAAANQADCgcIGgAAAA==.Disciple:BAAANQADCgYIBgAAAA==.',
Do='Doafliploser:BAAANQADCgYIBgAAAA==.Dogwalterll:BAAANQAECgYJEwAAAA==.Dohvahkiin:BAAANQADCgYJDAAAAA==.Dontlosmë:BAAANQADCgQIBAABNQADCgYICgADAAAAAA==.',
Dr='Draaragon:BAAANQADCggICwABNQAFFAcIFQABALUgAA==.Dracgutx:BAAANQADCgYJCwAAAA==.Dragonboffa:BAAANQADCgYIEgAAAA==.Dragonlyfans:BAABNQAECoEoAAMXAAkKNRodCADBAgAXAAkKNRodCADBAgAYAAgKIw8ZFgDtAQABNQAFFAcIFAAFAIIjAA==.Dripz:BAAANQAECggIDAAAAA==.Drive:BAAANQAECgYJDwAAAA==.Drunken:BAAANQADCgYIBgAAAA==.Dryadwood:BAAANQADCgcIDQAAAA==.',
Du='Dubby:BAABNQAECoEYAAIFAAkK3BwtFwDCAgAFAAkK3BwtFwDCAgAAAA==.Duelley:BAAANQABCgYICQAAAA==.Dumptruckdan:BAABNQAECoEdAAILAAkK2BVdRABCAgALAAkK2BVdRABCAgABNQAFFAcIFgAQAKkcAA==.Durgur:BAAANQAECgEJAQABNQAECgcJEAADAAAAAA==.',
Ea='Eardi:BAAANQAECggIDQAAAA==.Earthpounder:BAAANQAECgUIDAAAAA==.',
Ec='Echoez:BAABNQAECoEdAAIUAAgKSQ36EwC1AQAUAAgKSQ36EwC1AQAAAA==.Eclipsa:BAAANQAECgQICQAAAA==.',
Ee='Eebo:BAAANQADCgMIAwAAAA==.',
El='Elbram:BAAANQADCggICAABNQAECgUJDAADAAAAAA==.Elunasolz:BAEANQADCggIGgABNQAECgQJBgADAAAAAA==.',
Em='Emilil:BAAANQADCggIDAAAAA==.Eminence:BAAANQADCggIFgAAAA==.',
En='Enlight:BAAANQABCgMIAwAAAA==.',
Er='Erdorco:BAAANQADCggICwABNQAECgcJEQADAAAAAA==.',
Es='Escanor:BAAANQAECgIIAgAAAA==.Esu:BAAANQADCgYIBwAAAA==.',
Eu='Eudaimonia:BAAANQADCgYIDwAAAA==.',
Ex='Exias:BAAANQADCggJGQAAAA==.',
Ey='Eyejuice:BAAANQADCgQJBAAAAA==.',
Fa='Facebeata:BAABNQAECoEdAAMHAAgKQgxZIQDTAQAHAAgKQgxZIQDTAQAZAAEKkgcrDgAxAAAAAA==.Faize:BAAANQADCggIDgABNQAFFAUIDAAaALQHAA==.Falae:BAAANQAECgMJBgABNQAFFAQJBwAOANISAA==.Fathêrhêlp:BAAANQADCgEIAQAAAA==.Faunuis:BAACNQAFFIEUAAMFAAcKgiPSAgAQAgAFAAUKgiXSAgAQAgAaAAIKwhAJCACYAAA1AAQKgSEAAwUACQqwJtYAAOoDAAUACQqwJtYAAOoDABoABgqKHb0cALQBAAAA.Fawnbby:BAAANQAECgUIBQAAAA==.Faüst:BAAANQADCgEIAQABNQAECgkJIgAPAD8iAA==.',
Fe='Fearthebeef:BAAANQABCgEIAQABNQAECgYJDAADAAAAAA==.Featherbrain:BAAANQAECgUICQAAAA==.Felhell:BAAANQAECgQIBAABNQAECgkJHQAUAGYXAA==.Ferenyet:BAAANQADCgYIBgAAAA==.Fermagus:BAABNQAECoEdAAIQAAcKHgYj0QBfAQAQAAcKHgYj0QBfAQAAAA==.',
Fi='Fistflurry:BAAANQAECgUIBgABNQAFFAEIAQADAAAAAA==.Fistlad:BAACNQAFFIEVAAIXAAcKrCYFAAAlAwAXAAcKrCYFAAAlAwA1AAQKgR4AAhcACQoHJwsAABgEABcACQoHJwsAABgEAAAA.Fizzybubbles:BAAANQAECgYJEAAAAA==.',
Fl='Flamehunter:BAAANQAECggIEQAAAA==.Flapple:BAABNQAECoEnAAIXAAkKACP+AQCEAwAXAAkKACP+AQCEAwAAAA==.Fleshgrind:BAAANQADCgQIBAAAAA==.Flexicution:BAAANQADCgYIBgABNQAECgQIBAADAAAAAA==.Floweret:BAAANQAECgIIAgABNQAECgYJCgADAAAAAA==.Flu:BAAANQADCgEIAQABNQAECgIIAgADAAAAAA==.Flûffy:BAAANQAECgQJBwAAAA==.',
Fr='Freaknikk:BAAANQAECgYJEgABNQAECgYIDgADAAAAAA==.Freakuency:BAAANQABCgYICgAAAA==.Freightraìn:BAAANQADCgIIAgABNQAECgcIFAADAAAAAQ==.Frozalth:BAAANQADCgUJBgAAAA==.',
Fu='Fudgemuffin:BAAANQAFFAEJAQAAAA==.Furyofgnomes:BAAANQADCgEIAQABNQADCgYIBgADAAAAAA==.',
['Fë']='Fënrïr:BAAANQAECgMIBgABNQAECgkJIQAbAEsdAA==.',
['Fú']='Fúzzybútt:BAAANQADCgMIAwAAAA==.',
Ga='Galice:BAAANQAECgQJBAAAAA==.Gardasil:BAAANQAECggIAgAAAA==.Garlim:BAAANQADCgUIBQAAAA==.Gazebogary:BAABNQAECoEVAAIXAAkKCh5yBAAqAwAXAAkKCh5yBAAqAwABNQAFFAcIFgAQAKkcAA==.',
Ge='Gellysong:BAAANQABCgQJBgAAAA==.Genos:BAAANQAECgEIAQAAAA==.Gerlim:BAAANQADCgEIAQAAAA==.',
Gi='Gix:BAAANQAECgEIAQAAAA==.',
Gl='Glolock:BAAANQAECgYJDAAAAA==.Glopanx:BAAANQAECgEIAQABNQAECgYJDAADAAAAAA==.',
Go='Goresnot:BAAANQADCggJIwAAAA==.Gorgygrinds:BAAANQABCgQIBQAAAA==.',
Gr='Gravedarknes:BAABNQAECoEUAAMcAAgKBiFDDABqAQAdAAYK/B1gWwABAgAcAAQKmyJDDABqAQAAAA==.Greendog:BAAANQADCgIIAgABNQAECgQIEwADAAAAAA==.Grievur:BAAANQADCgcICwABNQAECggIEgADAAAAAA==.',
Gu='Guap:BAABNQAECoEYAAIQAAkKzBmEYwBkAgAQAAkKzBmEYwBkAgABNQAFFAcIFQAXAKwmAA==.Guineasaurus:BAAANQADCgUIBQAAAA==.Gunray:BAAANQADCgUIBQAAAA==.Guttamane:BAAANQAECgQJBAAAAA==.Gutx:BAAANQAECgEIAgAAAA==.',
Gy='Gyarrados:BAAANQADCgYJEAAAAA==.Gypsywolfe:BAAANQAECgMJBQAAAA==.',
['Gí']='Gífted:BAABNQAECoEhAAIQAAkKlBYhTgChAgAQAAkKlBYhTgChAgAAAA==.',
['Gü']='Günz:BAAANQABCgEIAQAAAA==.',
Ha='Hakasan:BAAANQAECgEIAQABNQAFFAEIAQADAAAAAA==.Haleybeary:BAAANQAECgEIAQAAAA==.Harawing:BAAANQADCgUIBQAAAA==.Hargrim:BAAANQADCggIDwAAAA==.Hastega:BAAANQAECgQIEgAAAA==.Haydonk:BAAANQADCgcIBwAAAA==.',
He='Herbage:BAAANQAECgUIDAAAAA==.Herrbjorn:BAAANQAECgMJBQAAAA==.',
Hi='Hinata:BAAANQADCgQIBAAAAA==.Hippopotamus:BAAANQAECgMIBQAAAA==.Hitaman:BAAANQAECgMIBQAAAA==.',
Ho='Holik:BAAANQABCgEIAQAAAA==.Holybaguette:BAAANQAECgUJBgAAAA==.Holycritbro:BAAANQAECgEJAQAAAA==.Horôn:BAAANQAECgYIBQAAAA==.Hotgirlmegan:BAAANQAECggIBAAAAA==.Houndoomm:BAAANQADCggIHQAAAA==.',
Hr='Hriste:BAAANQAECgUICQAAAA==.',
Hu='Hunteress:BAAANQADCgQIBAAAAA==.Huntyhunt:BAAANQAECgIIAgAAAA==.',
['Hô']='Hôrôn:BAAANQADCgYIBgAAAA==.',
Im='Imnosickmall:BAAANQAECgYJBwAAAA==.Impmafia:BAAANQAECgMJAgAAAA==.',
In='Incognetus:BAAANQAECgcIFAAAAQ==.Insurrection:BAAANQAECgUJCgABNQAECggJGQABAI8TAA==.',
Ir='Ironmaiiden:BAAANQADCgYIDAAAAA==.Ironpally:BAAANQAECgYJDgAAAA==.',
Iw='Iwantmead:BAAANQABCgMIAwAAAA==.',
Ja='Jaduen:BAAANQADCggIHQAAAA==.Jadziä:BAAANQADCgUIBQAAAA==.Jaes:BAAANQAECgQJBQABNQAFFAQJBwAOANISAA==.Jaesedar:BAABNQAFFIEHAAIOAAQK0hJgBwBVAQAOAAQK0hJgBwBVAQAAAA==.Jankizzle:BAAANQADCggICAAAAA==.Jaycen:BAAANQAECgQJCwABNQAECgcIFAADAAAAAQ==.',
Je='Jellythug:BAAANQAECgUICwAAAA==.Jenny:BAAANQAECgUIBQAAAA==.Jerksnknight:BAAANQAECgYJDQAAAA==.Jethon:BAAANQADCgcIDwAAAA==.Jexro:BAABNQAECoElAAIeAAkKfSSmAgCkAwAeAAkKfSSmAgCkAwAAAA==.Jezebaal:BAAANQAECgIIAgAAAA==.',
Jg='Jgremlin:BAAANQADCgUICAAAAA==.',
Ji='Jiun:BAAANQAECgMJAwAAAA==.',
Jo='Johnseenah:BAAANQADCgYIDAAAAA==.Jonnybravo:BAAANQAECgQICQAAAA==.Joshton:BAAANQADCgUIBQAAAA==.',
Jr='Jrrd:BAAANQAECgYJBwAAAA==.',
Ju='Judgmentoe:BAAANQAECgIJAgAAAA==.Jusstice:BAAANQAECgUICwAAAA==.',
Ka='Kack:BAAANQAECgYIBgAAAA==.Kadzageth:BAAANQAECgUIBgAAAA==.Kalvosa:BAAANQADCgUIDgAAAA==.Kanglizard:BAAANQADCgQIBAAAAA==.Karlbarx:BAAANQAECgQJBQAAAA==.Kasaa:BAAANQAECgUJDwAAAA==.Kasheira:BAAANQAECgUIDAAAAA==.Katti:BAAANQAECgUJDAAAAA==.Katzfiel:BAAANQAECgYJDAAAAA==.Kaytwo:BAACNQAFFIESAAIdAAcKkiR6AADoAgAdAAcKkiR6AADoAgA1AAQKgRoAAh0ACQplJvwIAJMDAB0ACQplJvwIAJMDAAAA.',
Kb='Kblasti:BAAANQAECgQIBAABNQAECgkJHwAFALoiAA==.Kblastissimo:BAABNQAECoEfAAIFAAkKuiK6BACcAwAFAAkKuiK6BACcAwAAAA==.',
Kc='Kcommandr:BAAANQADCggJDQABNQAECgYIEAADAAAAAA==.',
Ke='Kendramp:BAAANQAECgQJBQAAAA==.Kersplode:BAAANQAECgMIBQABNQAECggJGwANAPIXAA==.',
Kh='Khariia:BAAANQADCgQIBAAAAA==.',
Ki='Kieloran:BAABNQAECoEkAAMfAAcKogtGIABRAQAfAAcKogtGIABRAQALAAEKCgGXRQEMAAAAAA==.Kieralyn:BAAANQAECgEIAgAAAA==.Kiltlifter:BAAANQAECgEIAQAAAA==.Kisol:BAAANQADCgYIBgAAAA==.',
Ko='Koaladashian:BAAANQAECggIDwAAAA==.Koalaficent:BAAANQAECggIDgAAAA==.Kojodruid:BAAANQADCgYICgAAAA==.Kojohunter:BAAANQAECgEIAQAAAA==.Kong:BAAANQAECgUIBgAAAA==.Kookta:BAAANQAECgcIDwAAAA==.Kozmo:BAAANQAECgUJCgAAAA==.',
Kr='Kreep:BAAANQAECgMIAwAAAA==.Kreepur:BAAANQADCgcJDQAAAA==.Kresnik:BAAANQADCgUIBQAAAA==.',
Ku='Kundin:BAAANQAECgcIDgABNQAECgkJGwABACodAA==.Kurai:BAABNQAECoEXAAIIAAgKyQnsDwB7AQAIAAgKyQnsDwB7AQAAAA==.Kutaki:BAAANQADCgcJIQABNQABCgEIAQADAAAAAA==.',
['Kí']='Kíngbradley:BAAANQADCgQIBAABNQAECggJGwANAPIXAA==.',
['Kô']='Kôvu:BAAANQAECgUJBQAAAA==.',
La='Lasrin:BAACNQAFFIEGAAILAAQKWgz6BwALAQALAAQKWgz6BwALAQA1AAQKgR8AAgsACQoEH2QaAA0DAAsACQoEH2QaAA0DAAAA.Lavenia:BAAANQADCggIDAAAAA==.',
Lc='Lcboss:BAAANQADCgEIAQAAAA==.',
Ld='Ldawg:BAABNQAECoEYAAMQAAgKAAhJugCOAQAQAAgK1gdJugCOAQAgAAEKzAKGNAAuAAAAAA==.',
Le='Leastzenmonk:BAAANQAECgYJDgABNQAFFAYIDgACAA4XAA==.Lelu:BAAANQADCgUIBQAAAA==.Leucetios:BAAANQAECgQIBQAAAA==.',
Li='Liello:BAAANQAECgIJAgAAAA==.Lightchaos:BAAANQAECgYIBgAAAA==.Lightice:BAAANQADCgMIAwAAAA==.Lilgaypunk:BAACNQAFFIEGAAMGAAQKdBlQBgAUAQAGAAMKRxlQBgAUAQAPAAEKgQzhGgBVAAA1AAQKgSQAAgYACQq4HtcJAA4DAAYACQq4HtcJAA4DAAAA.Lilgaypunkk:BAAANQAECgcIBwABNQAFFAQIBgAGAHQZAA==.Littlecyka:BAAANQADCggICAAAAA==.',
Lo='Lockfocks:BAAANQADCggICAABNQAECgEIAQADAAAAAA==.Locoscar:BAACNQAFFIEHAAINAAQKyRnxBABpAQANAAQKyRnxBABpAQA1AAQKgSUAAw0ACQq9JdwCALoDAA0ACQq9JdwCALoDAAcABArcFLY7AM0AAAAA.Loktark:BAACNQAFFIEWAAITAAcK7yYCAADeAgATAAcK7yYCAADeAgA1AAQKgSEAAhMACQrFJhYAAP0DABMACQrFJhYAAP0DAAAA.Lootini:BAAANQAECggJCAAAAA==.Lotei:BAAANQAECgUIBwAAAA==.',
Lu='Luckylock:BAAANQADCgYIBgABNQAECgYICAADAAAAAA==.Lucresh:BAAANQADCgYIBgAAAA==.Luhari:BAAANQAECgQIBAAAAA==.Lula:BAAANQADCgIIAgAAAA==.Lunasolz:BAEANQAECgIJAgABNQAECgQJBgADAAAAAA==.Lustíé:BAAANQAECgMJBQAAAA==.',
Ly='Lythinlock:BAAANQAECgQIBwAAAA==.Lythinmk:BAAANQAECgYJBgAAAA==.',
['Là']='Lànthus:BAAANQAECgcICgAAAA==.',
['Lê']='Lêêrøy:BAAANQADCgYIEgAAAA==.',
Ma='Magedood:BAAANQAECgUICQAAAA==.Magev:BAAANQAECgUIDAAAAA==.Maggerz:BAAANQADCgMJAwAAAA==.Magiccheif:BAAANQAECgUIEQAAAA==.Magnuz:BAAANQADCgQIBwAAAA==.Maisharona:BAAANQADCgYIDAABNQAECgcJFQAQAPAhAA==.Makanir:BAAANQAECgcIBwAAAA==.Maleficent:BAAANQADCgQJBAAAAA==.Manginah:BAAANQAFFAEIAQAAAA==.Mauringo:BAAANQAECgYICwAAAA==.Mavanthis:BAAANQAECgUJDAAAAA==.Maxdizaster:BAAANQAECgUICwAAAA==.Mazkaz:BAAANQADCgUIBQAAAA==.',
Mc='Mcbonk:BAACNQAFFIEIAAMcAAIKPB42AQChAAAcAAIKPB42AQChAAAdAAIKBBW9FQChAAA1AAQKgRwAAx0ACQqfIdAgAPUCAB0ACQptH9AgAPUCABwAAwoIJPEPABwBAAAA.Mckniferson:BAAANQADCgQJBgAAAA==.',
Me='Merlenoir:BAAANQADCgcJDAAAAA==.Messybedhead:BAABNQAECoEeAAQaAAkKThbqDQCKAgAaAAkKThbqDQCKAgAEAAIKjAblKgBZAAAFAAEKMwfLfQA9AAABNQADCgYIBgADAAAAAA==.Methindour:BAAANQAECgEJAQAAAA==.',
Mi='Mightydwarf:BAAANQADCggIEQAAAA==.Mintwiskers:BAAANQAECgQIBgAAAA==.Misiana:BAAANQAECgcIEAAAAA==.Mivix:BAAANQAECgUICAABNQAFFAYIGAAPAIYeAA==.',
Mo='Mom:BAAANQAECgQIBAABNQAECgkJHgAeAAcgAA==.Monkeyclaw:BAAANQAECgUJEgAAAA==.Moonfist:BAAANQADCgQIBAAAAA==.Mordrak:BAAANQAECgYIDgAAAA==.Mordë:BAABNQAECoENAAMWAAcKjAozKwD+AAAWAAUKqggzKwD+AAAMAAQKHAxusgDDAAAAAA==.Mormzie:BAAANQAECgEJAQABNQAECgkJGgAhAM0SAA==.Morwy:BAAANQAECgcICwAAAA==.Moøbytoo:BAAANQAECgYJDwABNQAECgYIEAADAAAAAA==.',
Ms='Msedd:BAAANQADCgMIAwAAAA==.',
Mu='Mugged:BAAANQAECgcIDwAAAA==.Muinogaraa:BAAANQAECgMIBgABNQAFFAcIFQABALUgAA==.Mum:BAABNQAECoEeAAIeAAkKByAFBwBGAwAeAAkKByAFBwBGAwAAAA==.Murked:BAAANQADCggJDQAAAA==.Mushmouth:BAABNQAECoEYAAIQAAgKliB/NgDpAgAQAAgKliB/NgDpAgAAAA==.',
My='Myguy:BAAANQADCgYICgAAAA==.Mysiara:BAAANQADCggIEwAAAA==.',
['Mà']='Màjestic:BAAANQADCgYIDAAAAA==.',
['Mì']='Mìchael:BAAANQAECgYJDAAAAA==.',
['Mú']='Músu:BAAANQAECgYICwAAAA==.',
Na='Nagosho:BAAANQADCggICAAAAA==.Nampur:BAAANQAECgEIAQAAAA==.Naril:BAAANQAECgYJCgAAAA==.Narvana:BAAANQAECgQIEwAAAA==.Naughtyboy:BAAANQAECgEIAQABNQAECgkJFQAQAPAfAA==.Nayalla:BAAANQAECgUIBgAAAA==.',
Ni='Nightbirdie:BAAANQAECgMJBQAAAA==.Nightshotz:BAAANQAECgQJBgAAAA==.Niobé:BAAANQADCgUIBQAAAA==.Nitezz:BAAANQADCgMIAwAAAA==.Nityblast:BAAANQADCgYIDQAAAA==.',
No='Nodrus:BAAANQAECgIIAgAAAA==.Nogaraa:BAAANQAECggIDwABNQAFFAcIFQABALUgAA==.Novath:BAACNQAFFIEWAAMOAAcK4R9TAACvAgAOAAcK4R9TAACvAgALAAEKzAPYGABIAAA1AAQKgSUAAw4ACQqTJeEAANwDAA4ACQqTJeEAANwDAAsABwohJLMmAMcCAAAA.',
Ny='Nyssarissa:BAABNQAECoEdAAIiAAgKThtrAgCbAgAiAAgKThtrAgCbAgAAAA==.',
['Nè']='Nèliel:BAAANQAECgMJBgAAAA==.',
Oa='Oakenstream:BAAANQADCgIJAgAAAA==.',
Oe='Oennogaraa:BAAANQADCggICAABNQAFFAcIFQABALUgAA==.',
Op='Ophélia:BAAANQAECgQIBAAAAA==.',
Or='Orbz:BAAANQADCgcICgABNQAECgcIDwADAAAAAA==.Orusmar:BAAANQADCgYIDQAAAA==.',
Ot='Otterguy:BAAANQAECgYICwAAAA==.',
Ou='Oui:BAAANQAECgQIBgAAAA==.',
Ov='Overheated:BAAANQADCgYIDwAAAA==.',
Pa='Paalaz:BAACNQAFFIEKAAIjAAUKLBq5AgDJAQAjAAUKLBq5AgDJAQA1AAQKgR0AAiMACQr9I+cIADQDACMACQr9I+cIADQDAAAA.Pacifister:BAAANQADCgQJBAAAAA==.Paeldryth:BAABNQAECoEhAAMSAAkKWSbxAQCeAwASAAkKWSbxAQCeAwARAAgKPRloEgAmAgAAAA==.Paliesto:BAAANQAECgEIAQAAAA==.Paljin:BAAANQADCggICQAAAA==.Palkia:BAAANQAECgQJCQAAAA==.Palmface:BAAANQAECgYJCgAAAA==.Panatepriest:BAAANQAECgIIAgAAAA==.Pandadante:BAAANQAECgEIAQABNQAECgkJHQABANUaAA==.Pandatunado:BAABNQAECoEdAAINAAgKdh4KHADSAgANAAgKdh4KHADSAgAAAA==.Panky:BAAANQAECgYJEAAAAA==.',
Pe='Pedrocerrano:BAAANQAECggIEgAAAA==.Pelt:BAABNQAECoEbAAMNAAgK8hdVPgA9AgANAAcK+RpVPgA9AgAHAAUKxglLNAAKAQAAAA==.Pewbot:BAAANQAECgUJDAABNQAECgcIFAADAAAAAQ==.',
Ph='Phirefly:BAAANQADCggIEAAAAA==.Phoebë:BAAANQADCgUIBwAAAA==.Phusiion:BAAANQAECgEJAQAAAA==.',
Pi='Pickledin:BAAANQAECgUICQAAAA==.Pinecones:BAAANQAECgcJDgABNQAECgkJIgAdAJ4jAA==.',
Pk='Pkmntrainer:BAAANQADCgYIFgABNQADCgcIEQADAAAAAA==.',
Pl='Please:BAACNQAFFIEVAAICAAcKeAcMAgAQAgACAAcKeAcMAgAQAgA1AAQKgSEAAgIACQr8IEUPAA4DAAIACQr8IEUPAA4DAAAA.Pleasetwo:BAABNQAECoEgAAICAAkKwg2oRQDVAQACAAkKwg2oRQDVAQABNQAFFAcIFQACAHgHAA==.Plumaril:BAAANQAECgUJCwAAAA==.',
Po='Pondero:BAAANQADCgEJAQABNQAECggIDgADAAAAAA==.Pondos:BAAANQADCgEIAQABNQAECggIDgADAAAAAA==.',
Pp='Ppleakin:BAAANQAECgcIEwAAAA==.',
Pr='Pranzar:BAAANQAECgcJEAAAAA==.Prepdagoat:BAAANQADCggIGwABNQADCgQJBAADAAAAAA==.',
Pt='Pticky:BAAANQAECgIIAgABNQAECgkJFQAeACEZAA==.',
Pu='Pullo:BAABNQAECoEdAAMkAAgKBBarKwANAgAkAAgKHBOrKwANAgAlAAcKeBMBJQDNAQAAAA==.Punctualpaul:BAABNQAECoEVAAIQAAkKdiLnDwB+AwAQAAkKdiLnDwB+AwABNQAFFAcIFgAOAOEfAA==.Purple:BAAANQAECgcIBwAAAA==.',
Py='Pyrê:BAAANQAECgIJAgAAAA==.',
Qu='Quidditch:BAAANQAECgYIEAAAAA==.',
Qw='Qwadsfwfgads:BAACNQAFFIEaAAIaAAcKTCIJAADaAgAaAAcKTCIJAADaAgA1AAQKgRgAAhoACQoII8AEAEIDABoACQoII8AEAEIDAAAA.Qwamsfwfgads:BAAANQAECgIIAgABNQAFFAcIGgAaAEwiAA==.',
Ra='Rabbi:BAAANQAECgIIAgABNQAECgcIFAADAAAAAQ==.Raelavent:BAAANQAECgMIBQAAAA==.Ragrappy:BAACNQAFFIEWAAIPAAcKPiQ5AADDAgAPAAcKPiQ5AADDAgA1AAQKgR4AAg8ACQq0JkYBAMUDAA8ACQq0JkYBAMUDAAAA.Raherius:BAAANQADCgQJBAAAAA==.Raiju:BAAANQAECgUJCgAAAA==.Rakion:BAAANQAECgcIDQAAAA==.Ramped:BAAANQADCgUIBQAAAA==.Raszahk:BAABNQAECoEeAAMMAAkKvRwGLwBjAgAMAAcKUh0GLwBjAgAWAAIKsRpnQACdAAABNQAFFAMIBgAdAKAWAA==.',
Re='Realm:BAAANQADCggICAAAAA==.Reavêr:BAAANQAECgQICwAAAA==.Redreximus:BAAANQAECggJDAAAAA==.Regilock:BAAANQAECgQICgAAAA==.Retlec:BAAANQAECgUIDQAAAA==.Reïki:BAAANQADCgcIDQAAAA==.',
Ri='Rickaz:BAAANQAECgYIBAAAAA==.Ripto:BAAANQAECgEIAQAAAA==.',
Ro='Rochaca:BAAANQADCgcIEAAAAA==.Roshana:BAAANQAECgYJDAAAAA==.Rothoof:BAAANQAECgMIAwAAAA==.',
Ru='Rudnos:BAAANQADCgMIAgABNQAECgUJDgADAAAAAA==.Rumham:BAAANQAECgYIBwAAAA==.',
Ry='Ryptup:BAAANQAECgQIBAAAAA==.',
['Rô']='Rôinujj:BAAANQAECgMJAwAAAA==.',
Sa='Safiyah:BAAANQAECgYJEAAAAA==.Saltyevoker:BAAANQADCggJHgAAAA==.Same:BAABNQAECoEgAAIaAAkKbyLRAgB2AwAaAAkKbyLRAgB2AwABNQAFFAcIFgAOAOEfAA==.Samophlangy:BAAANQADCgMJAwAAAA==.Sandorstus:BAAANQAECgYJEAAAAA==.Saothome:BAAANQAECgQIBgAAAA==.Sathreal:BAAANQAECgUIBgAAAA==.Saywho:BAAANQADCgUJCQAAAA==.',
Sc='Scalywaumpus:BAAANQAECgQIBAAAAA==.Scienta:BAAANQAFFAEIAQAAAA==.Scope:BAAANQADCgYIDAAAAA==.Scrubdk:BAAANQADCgcIBwABNQAECgcJCQADAAAAAA==.Scúbasteve:BAAANQAECgUIDAAAAA==.',
Se='Sefirot:BAAANQAECgEJAQAAAA==.Selinddra:BAAANQAECgEJAQAAAA==.Serrafin:BAAANQAECgcJAQAAAA==.',
Sh='Shadebringer:BAAANQADCggIGwAAAA==.Shadowboxin:BAAANQADCgUIBQAAAA==.Shadowscale:BAAANQADCgUIBQAAAA==.Shamdaddy:BAAANQAECgUICwAAAA==.Shamezee:BAAANQAECgcJDgAAAA==.Shampoo:BAAANQAECgMIAwAAAA==.Sharlotte:BAAANQAECgIIAgAAAA==.Shilas:BAABNQAECoEaAAIBAAkKohoLEAB5AgABAAkKohoLEAB5AgABNQAECgkJIgAdAJ4jAA==.Shishkabug:BAAANQADCgIIAgAAAA==.Show:BAAANQADCgcIBwAAAA==.Shownuph:BAAANQADCgYJBwAAAA==.',
Si='Sicilianhero:BAAANQADCggIEgAAAA==.Sinestroo:BAAANQAECgYIBgAAAA==.Singelock:BAAANQAECgQIBAAAAA==.Sinsyn:BAAANQADCggICAABNQAECgQIBAADAAAAAA==.Sinwarrior:BAAANQAECggIEgABNQAECggICAADAAAAAA==.Sizz:BAAANQADCgQIBAAAAA==.',
Sk='Skipcawk:BAACNQAFFIEWAAMNAAcKcR8dAACiAgANAAcK5B4dAACiAgAHAAQK8BRwBwBVAQA1AAQKgSEAAwcACQrdJkIAAAEEAAcACQraJkIAAAEEAA0ABwo1Hck+ADwCAAAA.Skorpco:BAABNQAECoEcAAIeAAkKSheAEQCjAgAeAAkKSheAEQCjAgAAAA==.',
Sl='Slickngrity:BAAANQABCgMIAwAAAA==.Sluggo:BAAANQADCggIEAAAAA==.',
Sm='Smulol:BAABNQAECoEZAAIMAAkKCA48PQAoAgAMAAkKCA48PQAoAgAAAA==.Smutterli:BAAANQADCgQJBAAAAA==.',
Sn='Snoopfrogg:BAAANQAECgcJDwAAAA==.Snow:BAAANQAECgYJCwAAAA==.',
So='Solfire:BAAANQAECgUJDAAAAA==.Solstice:BAAANQAECgMIAwAAAA==.Sometingwong:BAAANQAECgQIBAAAAA==.',
Sp='Spamheal:BAAANQADCgcIDwAAAA==.Sparkle:BAAANQADCggICQAAAA==.Spliffy:BAAANQABCgEIAQAAAA==.Spodermenpls:BAAANQADCgIIAgABNQAFFAYIDgACAA4XAA==.',
St='Stabber:BAAANQADCgQIBAAAAA==.Stoc:BAAANQAECgcIBwAAAA==.Stormweaver:BAAANQAECgUJCgAAAA==.',
Su='Suinogaraa:BAAANQADCgYIBgABNQAFFAcIFQABALUgAA==.Sunderwhere:BAACNQAFFIEGAAIdAAMKoBZyDwDyAAAdAAMKoBZyDwDyAAA1AAQKgQ8AAh0ACQqXIBAlAN4CAB0ACQqXIBAlAN4CAAAA.Superhomie:BAAANQABCgIIAQAAAA==.',
Sw='Swann:BAABNQAECoEXAAIBAAgKdRvcEABrAgABAAgKdRvcEABrAgAAAA==.Swavor:BAAANQAECgYJCwAAAA==.Sweetbella:BAAANQADCgUIEQAAAA==.Swurves:BAAANQAECgIIAgAAAA==.',
Sy='Symbio:BAAANQADCggIDQAAAA==.Syna:BAAANQAECgYICwAAAA==.Syndct:BAAANQADCgIJAgAAAA==.',
Ta='Taearo:BAAANQAECgYJCgAAAA==.Taime:BAAANQAECgQICAAAAA==.Talirn:BAAANQADCggIFAAAAA==.Tallanvor:BAAANQADCggIFgAAAA==.',
Te='Teax:BAAANQAECggICAAAAA==.Teddywaumpus:BAAANQADCgYJBgAAAA==.Tendecay:BAAANQAECgUIDAAAAA==.',
Th='Thanquiol:BAACNQAFFIEVAAIJAAcKvB8HAACfAgAJAAcKvB8HAACfAgA1AAQKgSEAAgkACQo/JWgAAM4DAAkACQo/JWgAAM4DAAAA.Thebaraj:BAAANQAECgYIEwAAAA==.Thebigdawg:BAAANQADCgUICAAAAA==.Thedrude:BAAANQADCgUIBQAAAA==.Thedruidd:BAAANQADCgYICQAAAA==.Theeassassin:BAAANQADCgIIAQAAAA==.Thelance:BAAANQAECgEIAgAAAA==.Theseglaives:BAAANQAECgEIAQAAAA==.Thrilled:BAAANQAECgMIBgAAAA==.Thyora:BAACNQAFFIEJAAQmAAUKzRA6AgBUAQAmAAQKvxM6AgBUAQAYAAIK8AagDACUAAAXAAIKegh1CACGAAA1AAQKgR8ABBgACQomEa4UAAYCABgACQomEa4UAAYCABcABAoWD+EfAOYAACYAAgr2F9sSAHsAAAAA.',
Ti='Tijdruid:BAAANQAECgIIAgAAAA==.Timouthy:BAAANQADCgEIAQAAAA==.Tinyblast:BAAANQADCgQIBAAAAA==.',
Tj='Tjomme:BAAANQADCgQIBAAAAA==.',
To='Tommypickles:BAACNQAFFIEWAAMQAAcKqRzTAwAsAgAQAAYKSBnTAwAsAgAgAAIKLCJBAQDPAAA1AAQKgSMAAxAACQo7JjEFAMEDABAACQo7JjEFAMEDACAAAgo+JiYWANcAAAAA.Tomtrocity:BAAANQADCgUICQAAAA==.Toneclone:BAAANQAECgEIAQAAAA==.Tonestar:BAAANQAECgcJCAAAAA==.Tonyaharding:BAAANQABCgQJBAAAAA==.Toturaka:BAAANQAECgQJBAAAAA==.',
Tr='Trackerjoe:BAAANQADCgMIBAAAAA==.Train:BAAANQADCgIIAgABNQAECgcIFAADAAAAAQ==.Treerex:BAAANQAECgUIDAAAAA==.Troljin:BAAANQAECgYIEQAAAA==.Trollpaladin:BAAANQAECgcIDAAAAA==.',
Ts='Tsipayeoc:BAAANQADCggICQAAAA==.',
Tw='Twistedhavoc:BAAANQAECgUIBgAAAA==.Twk:BAAANQADCggIFwAAAA==.',
Ty='Tyrgann:BAAANQADCgUIBQAAAA==.Tytoflamina:BAAANQAECgUIBgAAAA==.',
Ui='Uiazel:BAAANQADCgEIAQAAAA==.',
Um='Umalinn:BAAANQAECgYJDAAAAA==.',
Un='Unholyrep:BAAANQAECgQIBAAAAA==.',
Ur='Urbellum:BAAANQADCgQIBAABNQAFFAYJDwAdAJkUAA==.',
Va='Vacca:BAAANQAECgYJDAAAAA==.Vaeyethror:BAAANQADCgQJBAAAAA==.Vahvadon:BAAANQADCgQIBAAAAA==.Valucia:BAAANQADCgEIAQAAAA==.Vandagar:BAAANQAECggIDgAAAA==.Vapor:BAACNQAFFIEHAAITAAQKKx9uAACgAQATAAQKKx9uAACgAQA1AAQKgTQAAhMACQpSI6QAAKMDABMACQpSI6QAAKMDAAAA.Varity:BAAANQABCgIIAgAAAA==.Varsity:BAABNQAECoEiAAIdAAkKniPEDgBkAwAdAAkKniPEDgBkAwAAAA==.Vason:BAAANQADCgMIAwAAAA==.',
Ve='Velaryn:BAAANQAECgIJAgAAAA==.Ventumceleri:BAAANQADCgUIBQAAAA==.',
Vh='Vhega:BAAANQABCgIIAgAAAA==.',
Vi='Vinyasa:BAAANQAECgYJCwAAAA==.',
Vo='Voodoobeast:BAAANQAECgUIDAAAAA==.',
Vu='Vulbahermosa:BAAANQAECgMJBwAAAA==.',
Wa='Waremtae:BAAANQADCgEIAQAAAA==.',
We='Wenguo:BAAANQAECgQIBQAAAA==.',
Wh='Wheatiees:BAAANQADCgcJEgAAAA==.Whyp:BAABNQAECoEdAAMSAAkKoBuwDAC/AgASAAkKoBuwDAC/AgARAAEKHwkzQQA0AAAAAA==.',
Wi='Wickle:BAAANQADCgcIBwAAAA==.Wingdaz:BAEANQADCggICQABNQAFFAEJAQADAAAAAA==.Wizliz:BAAANQADCgYIBgABNQAECgUJDgADAAAAAA==.',
Wo='Worgenzrdumb:BAAANQADCgYIBgAAAA==.',
Xi='Xidara:BAAANQADCggICQAAAA==.Xiqualani:BAAANQADCgYIBgAAAA==.Xivei:BAACNQAFFIEYAAIPAAYKhh6YAQBLAgAPAAYKhh6YAQBLAgA1AAQKgSEAAw8ACQpFIPsdAJsCAA8ACQoaIPsdAJsCAAoABwosEJ8IAH0BAAAA.',
Xl='Xlegolas:BAAANQADCgUIBgAAAA==.',
Xo='Xorac:BAAANQAECggJDQAAAA==.',
Xz='Xzach:BAABNQAECoEYAAIeAAkKgg2oHQAQAgAeAAkKgg2oHQAQAgAAAA==.',
Yi='Yinlou:BAAANQAECgMJBAAAAA==.',
Yo='Yorha:BAAANQADCgEIAQABNQAFFAUJCQAmAEUKAA==.',
Ys='Yshtolà:BAEANQAECgQJBgAAAA==.',
Yu='Yurmage:BAAANQAECgEIAQAAAA==.',
['Yì']='Yìffist:BAAANQADCgYIDAAAAA==.',
Za='Zachx:BAACNQAFFIEWAAQWAAcK2yU3AACrAQAWAAQK7SU3AACrAQAMAAMKJB+mCQAeAQAiAAIKECfPAADsAAA1AAQKgSEABBYACQosJiABAHgDABYACQquIiABAHgDAAwABwqDIJQoAIECACIAAwodJtsJAFUBAAAA.Zaegorn:BAAANQAECggIEgAAAA==.Zamoarak:BAAANQADCgIIAgAAAA==.Zargar:BAABNQAECoEpAAInAAkKOSK1AQCGAwAnAAkKOSK1AQCGAwAAAA==.Zarmakai:BAACNQAFFIEQAAMkAAYKrB/QAAAJAgAkAAUKpyPQAAAJAgAVAAEKxAsBIAApAAA1AAQKgSEAAiQACQqkJp4AAPoDACQACQqkJp4AAPoDAAAA.',
Ze='Zenxo:BAAANQABCgYICQAAAA==.',
Zi='Zintalesh:BAAANQAECgIIAgAAAA==.Zionx:BAAANQADCgQIBAAAAA==.Zivie:BAAANQAECgYIEQAAAA==.',
Zo='Zorrick:BAAANQABCgQIBwAAAA==.',
Zu='Zurry:BAAANQABCgEIAQAAAA==.',
Zy='Zygon:BAAANQAFFAIIAgAAAA==.',
['Ðr']='Ðrakie:BAAANQAECggIDgAAAA==.',
['Ök']='Ökko:BAAANQAECgUICQAAAA==.',
['Öw']='Öwly:BAAANQAECgcICAAAAA==.',
['Øk']='Øktavïa:BAAANQADCgQIAgAAAA==.',
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
