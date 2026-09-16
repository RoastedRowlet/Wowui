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

local lookup = {'Mage-Arcane','Paladin-Retribution','DeathKnight-Blood','Evoker-Devastation','Unknown-Unknown','Shaman-Elemental','Warrior-Protection','Paladin-Holy','Monk-Mistweaver','Druid-Balance','DeathKnight-Frost','DeathKnight-Unholy','Paladin-Protection','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Warrior-Arms','Shaman-Restoration','Priest-Holy','Priest-Discipline','Priest-Shadow','Druid-Restoration','DemonHunter-Devourer','DemonHunter-Havoc','Mage-Fire',}
local provider = {region='US',realm='Mannoroth',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aadda:BAABNQAECoEaAAIBAAkJcBQwQACSAgABAAkJcBQwQACSAgAAAA==.',
Ab='Abcdpal:BAABNQAFFIEGAAICAAQJuRwpAgCSAQACAAQJuRwpAgCSAQAAAA==.Abena:BAAANQAECgUIBgAAAA==.Abusive:BAABNQAECoEeAAIDAAkJZBwnDAD4AgADAAkJZBwnDAD4AgAAAA==.',
Ac='Acat:BAAANQAECgEIAQAAAA==.',
Ae='Aerogosa:BAABNQAECoEdAAIEAAkJpSAdAwBJAwAEAAkJpSAdAwBJAwAAAA==.',
Af='Affrika:BAAANQADCgEIAQAAAA==.',
Ag='Agogagog:BAAANQAECgcICwAAAA==.',
Ai='Aicam:BAAANQADCggIEgAAAA==.',
Al='Alarg:BAAANQADCgIIAgABNQAECgQIBgAFAAAAAA==.Alatide:BAAANQAECgQIBgAAAA==.Alcani:BAAANQADCgYIBgAAAA==.Aleena:BAAANQADCgcICgAAAA==.Alleriaa:BAAANQADCggIDAAAAA==.Altazar:BAAANQAECgYIEAAAAA==.Alxath:BAAANQAECgYIDQAAAA==.',
Am='Amaryste:BAAANQAECgEIAQAAAA==.Amidalah:BAAANQAECgYICQAAAA==.Amorinaron:BAABNQAECoEfAAIBAAkJLB5OGgAwAwABAAkJLB5OGgAwAwAAAA==.',
An='Anansi:BAAANQAECgIIAgABNQAFFAUICQAEAC0iAA==.Andsong:BAAANQADCgUIBQABNQAECgMIBAAFAAAAAA==.Anfalas:BAABNQAECoEjAAIGAAkJ7R0sDgAcAwAGAAkJ7R0sDgAcAwAAAA==.Anic:BAAANQAECgUICAAAAA==.Anikora:BAAANQADCgcIDAAAAA==.Anjelika:BAAANQAECgIIAgAAAA==.Anklestabber:BAAANQAECgYIDgAAAA==.Annathema:BAAANQADCgQIBAAAAA==.Anthlina:BAAANQADCgUIBQAAAA==.',
Ar='Archicrash:BAAANQADCgcICwAAAA==.Archipal:BAAANQADCgMIAwAAAA==.Archomen:BAAANQADCgQIBAABNQAECgQICQAFAAAAAA==.Arcwave:BAAANQADCgYICwAAAA==.Arcyon:BAAANQAECgQIBgAAAA==.Arethi:BAABNQAECoEaAAIHAAkJJiJNAQB4AwAHAAkJJiJNAQB4AwAAAA==.Arleos:BAAANQAECgYIDgAAAA==.Arroyo:BAAANQADCggIEQAAAA==.Artemasz:BAAANQAECgIIAgAAAA==.Arvoreen:BAAANQAECgEIAQAAAA==.',
As='Asrelle:BAAANQAECgYIEgAAAA==.Astaumin:BAAANQADCgYICgAAAA==.Asterrin:BAAANQADCgYICwAAAA==.Astralfrog:BAAANQAECgEIAQAAAA==.',
At='Ateelasham:BAAANQABCgQIBQAAAA==.',
Au='Audeline:BAAANQAECgEIAgAAAA==.Augmented:BAAANQABCgYICgABNQAECggIGQAIAPsmAA==.Auraelia:BAAANQADCgEIAQAAAA==.Aurilia:BAAANQADCggICwAAAA==.Aurôra:BAAANQADCggICQAAAA==.',
Av='Avran:BAAANQAECgYIDgAAAA==.',
Az='Aziala:BAAANQADCggICAABNQAECggIFwAEACIfAA==.Azreluna:BAAANQAECgYIDgAAAA==.',
Ba='Bajablight:BAAANQAECgEIAQAAAA==.Bajiggitee:BAAANQAECgUIDwAAAA==.Bananarosin:BAAANQAECgUICgAAAA==.Banlers:BAAANQADCgYIFAAAAA==.Banmedaddy:BAAANQADCggIFAABNQAECgQIBwAFAAAAAA==.Baradoon:BAAANQAECgQIBAAAAA==.',
Be='Bealzhunter:BAAANQADCgUIBgAAAA==.Bela:BAAANQADCgcIBwAAAA==.Bellion:BAAANQAECgEIAQAAAA==.Beo:BAABNQAECoEaAAIJAAgJvhgaCgBOAgAJAAgJvhgaCgBOAgAAAA==.',
Bi='Bigbluetaco:BAAANQAECgYIDwAAAA==.Bigchug:BAAANQAECgcIEQAAAA==.Bitelo:BAAANQADCggICAABNQADCggICAAFAAAAAA==.',
Bl='Blast:BAAANQADCgIIAgAAAA==.Blech:BAAANQAECgYIEAAAAA==.',
Bo='Bookerneg:BAAANQAECgIIAgAAAA==.Boomslang:BAAANQAECgIIAwAAAA==.Borlen:BAAANQAECgIIAwAAAA==.',
Br='Braids:BAAANQADCgUIBQABNQADCgUIBwAFAAAAAA==.Brassfeather:BAAANQAECgIIAgAAAA==.Brewcifer:BAAANQADCgMIAwAAAA==.Brezzath:BAAANQADCggICAAAAA==.Brezzid:BAAANQADCgYIBgABNQAECgYICgAFAAAAAA==.Brezzon:BAAANQAECgUICAABNQAECgYICgAFAAAAAA==.Brizzletwo:BAAANQAECgUIBwAAAA==.Brozzath:BAAANQAECgYICgAAAA==.Bryanka:BAAANQADCggICgAAAA==.Brättie:BAAANQADCgYICgAAAA==.Bróx:BAAANQAECgYIEAAAAA==.',
Bu='Bubbajoe:BAAANQAECgIIAgABNQAFFAUICQAEAC0iAA==.Bubbajr:BAAANQADCggIFAAAAA==.Burgy:BAAANQAECgQIBwAAAA==.Burgydk:BAAANQAECgYICgAAAA==.Buttfancy:BAAANQAECgUIDgAAAA==.',
['Bï']='Bïgdot:BAAANQAECgYIBgAAAA==.',
Ca='Caliery:BAAANQABCgEIAQAAAA==.Calmpressure:BAAANQAECgcICQAAAA==.Capnsparrow:BAAANQADCgYICwAAAA==.Captncheese:BAAANQAECgEIAgAAAA==.Cargy:BAAANQADCgIIAgAAAA==.Carshas:BAAANQADCgYIBgAAAA==.Cassielee:BAAANQADCgMIBgAAAA==.Catabop:BAAANQAECgIIAwABNQAECgcIEAAFAAAAAA==.Catastorm:BAAANQAECgcIEAAAAA==.Catavoker:BAAANQAECgQIBAABNQAECgcIEAAFAAAAAA==.Caustic:BAAANQAECgcICgAAAA==.Caveatemptor:BAABNQAECoEdAAIKAAgJxSHkEQDVAgAKAAgJxSHkEQDVAgAAAA==.',
Ce='Celaina:BAAANQADCggIDgAAAA==.',
Ch='Chainhappy:BAAANQAECgYICwAAAA==.Cheezybread:BAAANQADCgUIBQAAAA==.Chesshire:BAAANQAECgEIAQAAAA==.Chimeric:BAAANQAECgYIEAAAAA==.Chlover:BAAANQAECgMIAwAAAA==.Chmap:BAAANQADCgcIDQAAAA==.Chontosh:BAAANQAECgQIBwAAAA==.Chozenfate:BAAANQADCggIEQAAAA==.Chronuwu:BAAANQAECgEIAQAAAA==.',
Ci='Cindymccain:BAAANQAECgUICgAAAA==.',
Cl='Clearsight:BAAANQAECgMIBAABNQAECgYIDwAFAAAAAA==.',
Co='Cometh:BAAANQADCggIEAAAAA==.Compute:BAABNQAECoEjAAILAAgJDxytDACIAgALAAgJDxytDACIAgABNQAECggIDwAFAAAAAA==.Corursa:BAAANQADCgcICgABNQAECgUIBQAFAAAAAA==.Cozmowaffle:BAAANQADCgIIAgAAAA==.',
Cr='Cronauer:BAAANQAECgEIAQAAAA==.Cryofrog:BAAANQABCgIIAwAAAA==.',
Cu='Cuppicakies:BAAANQADCgMIAwAAAA==.',
Da='Dabbington:BAAANQABCgYIBwAAAA==.Daddilock:BAAANQADCgMIAwAAAA==.Daddyfatslap:BAAANQAECgYIBgAAAA==.Daggerz:BAAANQAECgQIBwAAAA==.Daguitas:BAAANQAECgQIBAAAAA==.Danasty:BAAANQABCgIIBQAAAA==.Danidakiesh:BAAANQADCgYICgAAAA==.Daralina:BAAANQABCgIIAgAAAA==.Darbreezius:BAAANQAECgMIBQAAAA==.Daribow:BAAANQADCgYICgAAAA==.Darkcoffee:BAAANQAECggIDAAAAA==.Darkvalk:BAAANQADCgEIAQAAAA==.Daroc:BAAANQAECggIAgAAAA==.Darvax:BAAANQAECgEIAQAAAA==.Datacenter:BAAANQAECggIDwAAAA==.Dawgan:BAAANQAECgIIAgAAAA==.',
De='Deadlyfrog:BAAANQABCgQIBQAAAA==.Deamionn:BAAANQAECgIIAgAAAA==.Deathbauchs:BAAANQADCgcICwAAAA==.Deathlylove:BAAANQABCgYIBgAAAA==.Deathtreader:BAAANQADCggICAAAAA==.Demoinc:BAAANQAECgcIEgAAAA==.Denathus:BAAANQADCgYIDwAAAA==.Denovo:BAAANQADCggICAABNQAECggIHQAKAMUhAA==.Desipator:BAAANQADCgIIAwAAAA==.Destinyløl:BAAANQADCgUIBQAAAA==.',
Di='Diabolix:BAAANQADCgQIBwAAAA==.Dilo:BAAANQADCgMIAwAAAA==.Divalatina:BAACNQAFFIEFAAIIAAMJaQO6BwDcAAAIAAMJaQO6BwDcAAA1AAQKgR8AAggACQkMFWgYAJsCAAgACQkMFWgYAJsCAAAA.Divinefrog:BAAANQAECgEIAQAAAA==.',
Dj='Djmax:BAAANQADCgIIAgAAAA==.',
Dk='Dkthae:BAAANQAECgUIDAAAAA==.',
Dl='Dlxanomaly:BAAANQAECgQIBgAAAA==.',
Do='Donttouchme:BAAANQADCgcIDAAAAA==.Doohickey:BAAANQAECgIIAgAAAA==.Dotsdaddy:BAAANQADCggIBwAAAA==.Doubledeez:BAAANQADCgIIAgAAAA==.Doubledz:BAAANQADCggIFQAAAA==.',
Dr='Dracslaya:BAAANQADCgcIBwAAAA==.Dragondzntz:BAAANQAECgIIAgAAAA==.Dragonfrog:BAAANQABCgYIBwAAAA==.Dragonmans:BAAANQADCgYIBgAAAA==.Dreamyeyes:BAAANQAECgUICAAAAA==.Drerein:BAAANQADCggIGgAAAA==.',
Du='Dubz:BAAANQAECggICgAAAA==.Dundeal:BAAANQADCgcIBwAAAA==.Dunkel:BAABNQAECoEZAAIMAAgJPxbfHABWAgAMAAgJPxbfHABWAgAAAA==.Dupichu:BAAANQAECgYICQAAAA==.',
Ea='Eataa:BAAANQAECgIIBAAAAA==.',
Eb='Ebonhammer:BAAANQADCgIIAgAAAA==.',
Eg='Egrilo:BAAANQADCggICAAAAA==.',
Ei='Eileithyia:BAAANQAECgUIBgAAAA==.',
El='Elekastra:BAAANQADCgYICQAAAA==.Ellonan:BAAANQADCggICwABNQAECgkJFQANANcNAA==.Elyndor:BAAANQADCgUIBQAAAA==.',
Em='Emopally:BAAANQAECgQICAAAAA==.Emopower:BAAANQAECgQIBgAAAA==.',
En='Enderr:BAAANQAECgYIDQAAAA==.Enegma:BAAANQADCgYIBgAAAA==.Enzini:BAAANQAECgQIBQAAAA==.',
Er='Erashi:BAAANQAECgQIBAAAAA==.',
Fa='Falculan:BAAANQADCgEIAQAAAA==.Fallen:BAAANQAECgQIBwAAAA==.Fatherchung:BAAANQAECgEIAQAAAA==.Fayotbeanz:BAAANQABCgYIDAAAAA==.',
Fe='Felwyth:BAAANQADCgcIEAABNQAECgcIEgAFAAAAAA==.',
Fi='Finneas:BAAANQADCgEIAQAAAA==.Fireworkxz:BAAANQAECgEIAgAAAA==.Fishhawk:BAAANQAECgQIBAAAAA==.',
Fl='Flarehammer:BAAANQAECgYIEAAAAA==.Flogh:BAAANQAECgUIBwAAAA==.',
Fo='Fomanshi:BAABNQAECoEXAAIEAAgJkQ3TDgDjAQAEAAgJkQ3TDgDjAQAAAA==.Forleaf:BAAANQADCgYIBgAAAA==.Forsierra:BAAANQADCgEIAQAAAA==.Foxiji:BAAANQAECgIIAgAAAA==.',
Fr='Frexadin:BAAANQADCgYIBgAAAA==.Frexican:BAAANQAECgUICAAAAA==.Fright:BAAANQAECgIIAgAAAA==.Frogleggs:BAAANQABCgMIAwAAAA==.Frogshock:BAAANQABCgYICAAAAA==.',
Fu='Fupabean:BAAANQABCgYIDAAAAA==.Fure:BAAANQADCgQIBAAAAA==.Fuupa:BAAANQADCgIIAgAAAA==.',
Ge='Genridge:BAAANQADCgYIDAAAAA==.',
Gi='Gilani:BAAANQAECgEIAQAAAA==.',
Gl='Glp:BAAANQAECgIIAwAAAA==.',
Go='Gorpy:BAABNQAECoEiAAMOAAkJYSXFBQBQAwAOAAgJCCXFBQBQAwAPAAcJwh1zBwBoAgAAAA==.Gotrott:BAAANQADCgEIAQAAAA==.',
Gr='Gravybones:BAAANQADCgcIDQAAAA==.Greenjesh:BAAANQAECgYIDgABNQAECgkJGQABALYVAA==.Greensheesh:BAABNQAECoEZAAIBAAkJthU9RACDAgABAAkJthU9RACDAgAAAA==.Greypilgram:BAAANQADCgYIDQAAAA==.Grimstank:BAAANQADCggIDwAAAA==.Grizzlygerm:BAAANQADCgUIBQAAAA==.Grizzlyoné:BAAANQADCggIGgAAAA==.Grumbleface:BAABNQAECoEcAAIIAAkJih/6BwBAAwAIAAkJih/6BwBAAwAAAA==.Grumbletron:BAAANQAECgYICQAAAA==.',
Gs='Gstatus:BAAANQAECgcIDAAAAA==.',
Gu='Gunel:BAAANQAECgEIAQAAAA==.',
Ha='Haawee:BAAANQAECgQIBQAAAA==.Hailcthulhu:BAAANQAECgYIEAAAAA==.Handcuffs:BAAANQAECgMIAwAAAA==.Handorn:BAAANQAECgMIAwABNQAECgkJGwAQAPQZAA==.Hanwha:BAAANQAECgYICwAAAA==.Harrower:BAAANQAECgIIAwAAAA==.Haze:BAAANQAECggICAAAAA==.Hazzkul:BAAANQAECgYIDQAAAA==.',
He='Healness:BAAANQAECggIDwAAAA==.Helasam:BAAANQAECgEIAQAAAA==.Hellbourné:BAAANQAECgEIAQAAAA==.Helloboys:BAAANQAECgYIDgAAAA==.Henzo:BAAANQABCgEIAQAAAA==.Herbavor:BAAANQAECgMIAwAAAA==.Hermes:BAAANQAECgYIEQAAAA==.Hermestrisme:BAAANQADCgMIAwAAAA==.',
Ho='Holexplorer:BAABNQAECoEYAAIRAAgJtBzGIgDGAgARAAgJtBzGIgDGAgAAAA==.Holytrashie:BAAANQADCgcIEwAAAA==.Honeybadger:BAAANQAECgYIDQAAAA==.Honnybuns:BAAANQABCgUIBQAAAA==.Hoofsmack:BAAANQADCgIIAgAAAA==.Hordeji:BAAANQADCgYIBgAAAA==.Hordeslayer:BAAANQADCgUICAAAAA==.',
Hs='Hsk:BAAANQAECgYIDAAAAA==.',
Hu='Hulkaholic:BAAANQAECgcICQAAAA==.Hulkclap:BAAANQABCgMIAwAAAA==.Hulkhunts:BAAANQABCgUICQAAAA==.',
['Hÿ']='Hÿphy:BAAANQAECgIIAgAAAA==.',
Ic='Icecat:BAAANQAECgUICQAAAA==.',
Il='Ilian:BAAANQADCgQICAAAAA==.',
In='Innothule:BAAANQADCgUIBQAAAA==.Inseratum:BAAANQADCgYIEAAAAA==.Inê:BAAANQAECgQIBAAAAA==.',
Iq='Iqbal:BAAANQADCgEIAQABNQAECgUICgAFAAAAAA==.',
Ir='Iriedraco:BAAANQABCgIIAgAAAA==.Irielite:BAAANQABCgQIBAAAAA==.Ironblast:BAAANQAECgQIBwAAAA==.Ironbolt:BAAANQADCgQIBAABNQAECgQIBwAFAAAAAA==.',
Is='Ishaa:BAAANQADCgIIAgAAAA==.',
It='Ithanksource:BAAANQAECgYICQAAAA==.',
Iv='Ivincentl:BAAANQADCgUIBQAAAA==.',
Ix='Ixgangrxi:BAAANQADCgQIBAAAAA==.',
Ja='Jadethunder:BAAANQADCgEIAQABNQAECgMIAwAFAAAAAA==.Jake:BAAANQABCgIIAwAAAA==.Jankie:BAAANQAECgUICwAAAA==.Jarnar:BAAANQAECgQIBAAAAA==.Jaxsin:BAAANQADCgEIAQAAAA==.',
Je='Jearemy:BAAANQADCgEIAQAAAA==.Jekster:BAAANQADCgEIAQAAAA==.',
Ji='Jingburger:BAAANQAECgUIBQAAAA==.Jinnosuke:BAAANQAECgEIAwAAAA==.',
Jo='Joecelin:BAAANQAECgMIAwAAAA==.Johnathanwow:BAAANQAECgQIBwAAAA==.Johnnytotem:BAABNQAECoEZAAMGAAkJVhG4JgBBAgAGAAkJVhG4JgBBAgASAAcJfAPvYwAgAQAAAA==.Jonastus:BAAANQADCgQIBAAAAA==.',
Ju='Judgemental:BAAANQADCgUIBgAAAA==.Justicé:BAAANQAECgEIAQAAAA==.',
Jy='Jykyl:BAAANQAECgUICQAAAA==.',
['Jê']='Jêkyl:BAAANQADCgEIAQAAAA==.',
Ka='Kaidoazure:BAAANQADCggICwAAAA==.Kaipod:BAAANQAECgQIBQAAAA==.Kaorrii:BAAANQAECgUIBAAAAA==.Karlaia:BAAANQADCgEIAQAAAA==.Kattána:BAAANQADCgcIEgABNQAECgMIAwAFAAAAAA==.Kauthoon:BAAANQADCgQIBwAAAA==.Kaykotta:BAAANQADCgUICAAAAA==.Kazademon:BAAANQAECgUICAAAAA==.Kazmo:BAAANQAECgYICAAAAA==.',
Ke='Kegheimer:BAAANQADCgQIBQABNQAECgQICAAFAAAAAA==.Keigis:BAAANQADCgYIBgAAAA==.Kensington:BAAANQAECgUIBQABNQAECgYIEAAFAAAAAA==.Keyalovar:BAABNQAECoGjAAITAAgJ/SZ8AQCrAwATAAgJ/SZ8AQCrAwAAAA==.Keìra:BAAANQADCgYIBwAAAA==.',
Kh='Khalgon:BAAANQADCggICAAAAA==.',
Ki='Kimbecky:BAAANQADCgIIAgAAAA==.Kimchii:BAAANQADCgUIBgAAAA==.Kiritoo:BAAANQABCgQIBAAAAA==.Kishukae:BAAANQAECgUICAAAAA==.Kislosladkiy:BAAANQAECggIEAAAAA==.',
Kl='Klassik:BAAANQADCgYICwABNQAECgQIBQAFAAAAAA==.',
Kn='Knitbeaniex:BAAANQAECgEIAQABNQAECgEIAgAFAAAAAA==.Knobsnob:BAABNQAECoEXAAQUAAgJNCFXAwBIAgAUAAYJViFXAwBIAgATAAMJPBzqXAD/AAAVAAIJtwsjPABpAAAAAA==.',
Ko='Kodeezy:BAAANQADCggICAABNQAECgcIDQAFAAAAAA==.',
Kr='Kriztina:BAAANQAECgEIAQAAAA==.Kronkk:BAAANQADCgIIAgAAAA==.Kropie:BAAANQAECgQIBAAAAA==.Krågden:BAAANQADCgUIBQABNQAECgQICAAFAAAAAA==.',
Ku='Kunfuzion:BAAANQAECgQIBQAAAA==.',
Ky='Kynga:BAAANQADCgUIBwAAAA==.',
La='Ladrian:BAAANQAECggIEgAAAA==.Landoresh:BAAANQAECgEIAQAAAA==.Langers:BAAANQADCgEIAQAAAA==.Larenieth:BAAANQADCgcICQAAAA==.Larüd:BAAANQAECgcIDwAAAA==.Lasmon:BAAANQAECgYIDAAAAA==.',
Le='Legallyblind:BAAANQAECgYIDAAAAA==.Legit:BAAANQAECgMIBAAAAA==.',
Li='Lightblessed:BAAANQADCgcIBwABNQAECgYIDQAFAAAAAA==.Lightsworne:BAAANQAECgcIDQAAAA==.Lillithx:BAAANQADCgUIDQAAAA==.Lindarenne:BAAANQADCgUIBQAAAA==.Lindree:BAAANQADCgcICAAAAA==.Liquidfire:BAAANQADCgYIBgAAAA==.Lirang:BAAANQAECgQIBQAAAA==.Littlewashu:BAAANQABCgUIBwAAAA==.Lizardfistin:BAACNQAFFIEJAAIEAAUJLSKHAAD+AQAEAAUJLSKHAAD+AQA1AAQKgRsAAgQACQk0JRsBAKUDAAQACQk0JRsBAKUDAAAA.',
Lo='Loads:BAAANQAECggIAQAAAA==.Lockñlol:BAAANQABCgQIBAAAAA==.Loni:BAAANQAECgIIAgAAAA==.Loonaimp:BAAANQAECgMIBQAAAA==.Lorthos:BAAANQABCgIIAgAAAA==.Lotús:BAAANQAECgcIEgAAAA==.',
Lu='Lucithalle:BAAANQADCgYIBgAAAA==.Lumenox:BAABNQAECoEVAAMNAAkJ1w38DgDdAQANAAkJ1w38DgDdAQACAAEJfgL//gAlAAAAAA==.Luminarria:BAAANQAECgIIAwAAAA==.Luminisong:BAAANQAECgIIAgAAAA==.Lupomic:BAAANQAECgIIAgAAAA==.',
Ma='Maeivalla:BAAANQAECgYICgAAAA==.Mageler:BAAANQAECgYIDQAAAA==.Magicpurro:BAAANQAECgYICgABNQAFFAUICQAEAC0iAA==.Maiajayde:BAAANQABCgIIAgAAAA==.Malicebane:BAAANQADCgQIBAAAAA==.Mallory:BAAANQAECgcIBwAAAA==.Malma:BAAANQADCgYIBgAAAA==.Mancane:BAABNQAECoEbAAIBAAgJRRmdUABaAgABAAgJRRmdUABaAgAAAA==.Margolis:BAAANQADCggICgABNQAECgkJIgAOAGElAA==.Margrathwin:BAAANQAECgcIEgAAAA==.Marxman:BAAANQAECgYIBgABNQAFFAMIBAAFAAAAAA==.Mask:BAAANQADCgUIBQAAAA==.Mauchs:BAAANQADCgUICQAAAA==.Mayorwanna:BAAANQABCgIIBAAAAA==.',
Me='Meganite:BAAANQADCgYIFAAAAA==.Melaniatrump:BAAANQADCgEIAQAAAA==.Meningitis:BAAANQAECgEIAQAAAA==.',
Mi='Miahas:BAAANQADCgMIAwAAAA==.Mikecoxwoll:BAAANQAECgYIDwAAAA==.Milkmountain:BAAANQADCgIIAgAAAA==.Milkymoo:BAAANQADCgYIBgAAAA==.Minalina:BAAANQAECggIDQAAAA==.Minalinaria:BAAANQAECggIBwAAAA==.Mindedz:BAAANQAECgYIDAAAAA==.Minnow:BAAANQAECgIIBAAAAA==.Miren:BAAANQAECgYIDwAAAA==.Mittsmitts:BAAANQADCggIGQAAAA==.',
Mo='Moistbuns:BAAANQAECgQIBQAAAA==.Molatova:BAAANQAECgQIBAAAAA==.Moozart:BAAANQADCgQIBAABNQAECgYIEAAFAAAAAA==.Mooze:BAAANQAECgQIBAAAAA==.Morgiana:BAAANQAECgIIAgAAAA==.Mortiferia:BAAANQAECgYIDgAAAA==.Mortzx:BAAANQAECgQIBAAAAA==.Motown:BAAANQAECgcIDQAAAA==.',
Mu='Mundane:BAAANQADCggICAAAAA==.Muyo:BAAANQADCgEIAQAAAA==.Muzzlefaulf:BAAANQABCgIIAgAAAA==.',
Mw='Mwooq:BAAANQADCgYICAAAAA==.',
My='Mystics:BAAANQAECgYIDgAAAA==.Mystiklight:BAAANQADCgUIBQABNQAECgMIAwAFAAAAAA==.Mythomagic:BAAANQAECgYICwAAAA==.',
Na='Naebchi:BAAANQADCgUIBQAAAA==.Nahjiky:BAAANQADCgYIEQAAAA==.Nastyjob:BAAANQAECgYIBgAAAA==.',
Ne='Necronips:BAAANQADCgIIAgAAAA==.Neurosis:BAAANQADCggIDgAAAA==.Nezzthena:BAAANQADCgEIAQAAAA==.',
Ni='Niari:BAAANQADCggIDwAAAA==.Nibelung:BAABNQAECoEkAAMKAAgJoiPZCABOAwAKAAgJoiPZCABOAwAWAAEJ2x/RNwBgAAAAAA==.Nikale:BAAANQAECgQICAAAAA==.',
No='Nordy:BAAANQAECgQIBgAAAA==.Normadin:BAAANQAECgYIDgAAAA==.Norsefolk:BAAANQADCgIIAgAAAA==.Norseroch:BAAANQADCgYICgABNQADCgIIAgAFAAAAAA==.',
Nv='Nvd:BAABNQAECoETAAMXAAkJfB5dEACVAgAXAAgJoyFdEACVAgAYAAEJRwXvTAA8AAABNQAFFAIIAgAFAAAAAA==.',
Ny='Nyan:BAAANQAECgcICAABNQAECggIGQAIAPsmAA==.Nysonnia:BAAANQAECgYICwABNQAECggIGQAIAPsmAA==.',
Ob='Obliterate:BAAANQAECgQIBwAAAA==.Obsidianfire:BAAANQADCgQIBAABNQAECgMIAwAFAAAAAA==.',
Od='Odonn:BAAANQADCgUICAAAAA==.Odìnsôn:BAAANQADCggIGAAAAA==.',
Om='Omegafortswl:BAAANQADCgYIEQAAAA==.Omeni:BAAANQAECgQICQAAAA==.',
On='Oneshockiboi:BAAANQADCgMIAwAAAA==.',
Oo='Oogiie:BAAANQABCgQIBAAAAA==.',
Or='Orbits:BAAANQADCgcIBwAAAA==.Oric:BAABNQAECoEZAAIIAAgJ+yY6AgCoAwAIAAgJ+yY6AgCoAwAAAA==.',
Pa='Pallverize:BAAANQADCggICAAAAA==.Paperdaen:BAAANQAECgQIBQAAAA==.Parkle:BAAANQADCgYIDwAAAA==.Pastore:BAAANQAECgQIBgAAAA==.',
Pe='Pelee:BAAANQABCgIIAgAAAA==.Pelos:BAAANQADCgEIAQAAAA==.Peonmè:BAAANQAECgIIAgAAAA==.Pepitopingon:BAAANQABCggICwAAAA==.',
Pf='Pfeffernusse:BAAANQAFFAMIBAAAAA==.',
Ph='Phalluic:BAAANQADCgYIBgAAAA==.Philpriest:BAAANQAECgYICgAAAA==.',
Pl='Plagued:BAAANQAECgMIAwABNQAECgQIBwAFAAAAAA==.Plagueis:BAAANQADCgMIAwAAAA==.',
Po='Pochaccob:BAAANQAECgcIBwAAAA==.Pokeysticks:BAAANQAECgMIBQAAAA==.Poncia:BAAANQAECgEIAgAAAA==.',
Pr='Pragmax:BAAANQAECgQIBwAAAA==.Praynation:BAAANQADCggIDAAAAA==.Prediction:BAAANQAECgEIAgAAAA==.',
Pu='Puffcodan:BAAANQAECgEIAwAAAA==.Pugcival:BAAANQADCgUIBQAAAA==.Punîshër:BAAANQAECgUIBwAAAA==.Puppenance:BAAANQADCgUIBQAAAA==.Purgatoriwlf:BAAANQAECgYIEAAAAA==.',
Py='Pyrogale:BAAANQADCggIDgAAAA==.',
['Pó']='Póe:BAAANQAFFAEIAQAAAA==.',
Ql='Qlimax:BAAANQADCgcICwAAAA==.',
Qu='Quadzilla:BAAANQADCggIEgAAAA==.Quem:BAAANQAECgYIBQAAAA==.',
Ra='Ragnalock:BAAANQADCgQIBgAAAA==.Ragnir:BAAANQADCgUIAwAAAA==.Raker:BAAANQABCgcIDAAAAA==.Rarh:BAAANQADCgYICQAAAA==.Rathlokor:BAAANQADCgMIAwAAAA==.Rathlore:BAAANQADCgUIBQAAAA==.Rathorn:BAAANQADCgQIBwAAAA==.Rawdawgan:BAAANQADCgYIBwAAAA==.Rawrbotz:BAAANQADCgUIDAAAAA==.Razeneth:BAAANQAECggIBgAAAA==.',
Re='Rebornqt:BAAANQADCgIIAgAAAA==.Reforsaken:BAAANQAECgcIEQAAAA==.Relarian:BAAANQAECgQICAAAAA==.Releimus:BAAANQADCgcIDAAAAA==.Revengeance:BAAANQAECgYIDgAAAA==.',
Rm='Rmplstilskin:BAAANQADCgUIBQAAAA==.',
Ro='Roanoke:BAAANQABCgMIAwAAAA==.Rocketsauce:BAAANQAECgIIAgAAAA==.Romcrom:BAAANQAECgYICwAAAA==.Rommagicus:BAAANQADCggIDQABNQAECgYICwAFAAAAAA==.Rosalíe:BAAANQADCgQIBAAAAA==.Rougetoon:BAAANQADCgYIBgAAAA==.Rouxnic:BAAANQADCgEIAQAAAA==.Roxen:BAAANQAECgYICwAAAA==.',
Ru='Rubyhart:BAAANQADCgYIBgAAAA==.Rukenji:BAABNQAECoEfAAMTAAkJgR0MCgALAwATAAkJRx0MCgALAwAUAAQJyxzZCgAXAQAAAA==.Runehulk:BAAANQABCgQIBAAAAA==.Runíc:BAAANQADCgEIAQAAAA==.',
Ry='Ryuunosuke:BAAANQAECgYIDgAAAA==.',
Sa='Sabers:BAAANQAECgYIDAAAAA==.Sabriinaa:BAAANQABCgMIBAAAAA==.Sabrinadin:BAAANQABCgMIBAAAAA==.Sadako:BAAANQADCgQIBAAAAA==.Sakkraa:BAABNQAECoEbAAMQAAkJ9Bn1AAACAwAQAAkJ9Bn1AAACAwAOAAEJdg6duAA9AAAAAA==.Salla:BAAANQAECgMIAwAAAA==.Sannea:BAAANQADCgYIBwAAAA==.Saponite:BAAANQADCgIIAgAAAA==.Sarumon:BAAANQAECgQICAAAAA==.',
Sc='Schwimdy:BAAANQAECgMIAwAAAA==.',
Se='Secondlife:BAAANQADCgQIBAAAAA==.Seeingeyedog:BAAANQAECgUIDAAAAA==.Sevenseconds:BAAANQADCgcIDQAAAA==.',
Sh='Shadowscythe:BAAANQAECgQIBAAAAA==.Shampann:BAAANQADCgEIAQAAAA==.Sharish:BAAANQABCgIIAgAAAA==.Shaundel:BAABNQAECoEdAAISAAcJKBpoLQAJAgASAAcJKBpoLQAJAgAAAA==.Shavocadoos:BAAANQADCggICAAAAA==.Shezmu:BAAANQAECgcIEAAAAA==.Shiftinman:BAAANQADCgMIAwAAAA==.Shiftintime:BAAANQADCgQIBAABNQAECggIFQAYAEYdAA==.Shoopa:BAAANQAECgMIAwAAAA==.Shoopah:BAAANQAECgQICwAAAA==.Short:BAAANQAECgUIDQAAAA==.Shunned:BAAANQADCgMIBAABNQADCgYIBwAFAAAAAA==.Shädøwreeper:BAAANQAECgMIAwAAAA==.',
Si='Siduiss:BAAANQAECgIIAwAAAA==.Silvrfoxx:BAAANQAECgEIAQAAAA==.Silvänus:BAAANQAECgcIEwAAAA==.Simsha:BAAANQAECgQICAAAAA==.',
Sk='Skinnylejend:BAAANQAECgYIDQAAAA==.Skipperty:BAAANQADCggIBAAAAA==.Skmoon:BAAANQADCgIIAgAAAA==.Skãr:BAAANQADCgYIBgAAAA==.',
Sm='Smiley:BAAANQAECgQICwAAAA==.',
Sn='Snac:BAAANQADCgQIBAAAAA==.Snackrifice:BAAANQAECgMIAwAAAA==.Snacs:BAAANQADCgMIAwAAAA==.Sndancekd:BAAANQAECgIIAQAAAA==.Sneakybeanz:BAAANQADCgUIBQAAAA==.',
So='Somoner:BAABNQAECoEaAAMPAAcJdiCJBQCaAgAPAAcJdiCJBQCaAgAQAAEJsw/QGgA+AAAAAA==.Sompal:BAAANQAECgQIBgABNQAECgcIGgAPAHYgAA==.',
Sp='Sparksizzle:BAABNQAECoEXAAMBAAkJrBHuVABLAgABAAkJrBHuVABLAgAZAAMJqAYsBACyAAAAAA==.Spiseyy:BAAANQADCgYIBgAAAA==.Spitfel:BAABNQAECoEYAAQPAAkJjCDZBACvAgAPAAkJuhfZBACvAgAOAAUJ3B+vTQCUAQAQAAEJSRw7FwBKAAAAAA==.Spitfirex:BAAANQAECgcIDAABNQAECgkJGAAPAIwgAA==.Spreadshecat:BAAANQAECgYIBgABNQAECgYICQAFAAAAAA==.',
St='Stoix:BAAANQADCgUIAgAAAA==.Stompymunk:BAAANQADCgcICAAAAA==.Stopzîlla:BAAANQAECgYICgAAAA==.',
Su='Sugrdadi:BAAANQAECgMIBQAAAA==.',
Sw='Swippie:BAAANQADCgYICwAAAA==.',
Sy='Sylmar:BAAANQADCggIDQAAAA==.Syndora:BAAANQAECgYIEQAAAA==.',
Ta='Tacoboss:BAAANQAECgEIAQAAAA==.Taerun:BAAANQADCggICAAAAA==.Tahu:BAAANQAECgUICgAAAA==.Takal:BAAANQADCgYICwAAAA==.Talorn:BAAANQADCgUIBQAAAA==.Talreth:BAAANQAECgMIAwAAAA==.Tappnlock:BAAANQABCgIIAgABNQAECgYIDAAFAAAAAA==.',
Te='Teake:BAAANQAECgIIAgAAAA==.Teddymoove:BAAANQADCgYIBgAAAA==.Teddyruxpin:BAAANQADCgcIBwAAAA==.Teddytotems:BAAANQAECgQICQAAAA==.Telemarketer:BAAANQADCgIIAgAAAA==.Ternal:BAAANQADCgcICAAAAA==.Terrato:BAAANQAECgEIAQAAAA==.Terrorize:BAAANQAECgMIAwAAAA==.Terrous:BAABNQAECoEeAAIMAAkJZRsODgDyAgAMAAkJZRsODgDyAgAAAA==.Tetranutra:BAAANQADCgQIBAAAAA==.',
Th='Thakur:BAAANQAECgYIDwAAAA==.Theoslight:BAAANQAECgIIAgAAAA==.Thepetmaster:BAAANQADCgUICgAAAA==.Thighler:BAAANQAECgIIAgAAAA==.Thordenson:BAAANQABCgIIAgAAAA==.Thrandorinil:BAAANQADCgQIBgAAAA==.Threxon:BAAANQAECgYICQAAAA==.Thunderfire:BAAANQAECgMIAwAAAA==.',
Ti='Timepally:BAAANQADCgYIBgAAAA==.Tinytimothy:BAAANQADCgIIAgAAAA==.',
To='Tokajok:BAABNQAECoEdAAIXAAgJUx1hDQDEAgAXAAgJUx1hDQDEAgAAAA==.Tokash:BAAANQADCggICQABNQAECggIHQAXAFMdAA==.Tokashi:BAAANQAECgcIDAABNQAECggIHQAXAFMdAA==.Tokeadin:BAAANQAECgYICwAAAA==.Tokzillu:BAAANQADCgUIBQAAAA==.Tomaki:BAAANQADCgcICQAAAA==.',
Tr='Trackervalk:BAAANQADCgIIAgAAAA==.Trenbölöne:BAAANQAECgYIEAAAAA==.Treyrin:BAAANQAECgQICAAAAA==.Tritonian:BAACNQAFFIEKAAINAAUJoiRrAAAgAgANAAUJoiRrAAAgAgA1AAQKgR0AAg0ACQkmJnwAANsDAA0ACQkmJnwAANsDAAAA.Trollmother:BAAANQADCggICAAAAA==.Trolloutcast:BAAANQAECgQICAABNQAECgkJIgAOAGElAA==.',
Tu='Turtle:BAABNQAECoEhAAIIAAkJ9xrhDwDmAgAIAAkJ9xrhDwDmAgAAAA==.',
Tw='Twizzlestick:BAAANQABCgUIBQAAAA==.',
Ty='Tyluwu:BAAANQAECgQIBwAAAA==.Tyranis:BAAANQADCgIIAgAAAA==.Tyzz:BAAANQAECgEIAgAAAA==.',
['Tì']='Tìtân:BAAANQADCgcIBwAAAA==.',
['Tÿ']='Tÿ:BAAANQAECgYICwAAAA==.',
Um='Umbrianna:BAAANQAECgYIDgAAAA==.',
Un='Unstablemagi:BAAANQADCgYIBgAAAA==.',
Uw='Uwuhunterxd:BAAANQAFFAIIAwAAAA==.',
Va='Vaelowyn:BAAANQAECgEIAQAAAA==.Vakar:BAAANQAECgEIAQAAAA==.Valkyriee:BAAANQABCgQIBgAAAA==.Varninn:BAAANQADCgcIDAAAAA==.Vasha:BAAANQAECgUIBQAAAA==.',
Ve='Ventee:BAAANQAECgIIBAAAAA==.',
Vi='Vincentv:BAAANQADCgYIBgAAAA==.Virtuositee:BAAANQADCgYICwABNQAECgUIDwAFAAAAAA==.Vitadin:BAAANQAECgEIAwAAAA==.',
Vr='Vraugashan:BAAANQAECgQIBAAAAA==.Vrice:BAAANQADCgIIAgAAAA==.',
['Vá']='Váprak:BAAANQADCgcICAAAAA==.',
Wa='Walmage:BAAANQADCgYIBgAAAA==.Wannabe:BAAANQABCgUIBQABNQAECgYICwAFAAAAAA==.Warbuck:BAAANQADCgUIBAAAAA==.Warlas:BAAANQAECgEIAQAAAA==.',
We='Wesson:BAAANQAECgIIAgAAAA==.',
Wh='Whompie:BAAANQABCgEIAQAAAA==.',
Wi='Winning:BAAANQAFFAEIAQAAAA==.Wireless:BAAANQAECgYIEAAAAA==.',
Wo='Wokker:BAAANQADCggIFAAAAA==.',
Wq='Wqwq:BAAANQADCgEIAQAAAA==.',
Wu='Wuköng:BAAANQAECgIIAwAAAA==.',
Xa='Xau:BAAANQABCgUIBQAAAA==.',
Xe='Xencero:BAAANQAECgMIAwABNQAECgQIBwAFAAAAAA==.Xerrash:BAAANQADCggICAABNQAECgcIDQAFAAAAAA==.Xeum:BAAANQAECgMICQAAAA==.',
Xg='Xgirlfriend:BAAANQAECgQICwAAAA==.',
Xh='Xhar:BAAANQAECgQIBwAAAA==.Xhyros:BAABNQAECoEXAAIEAAgJIh/9BQDdAgAEAAgJIh/9BQDdAgAAAA==.',
Xi='Xiahou:BAAANQAECgYIDgAAAA==.',
Xo='Xoothette:BAAANQADCgcIBwABNQAECgkJIgAOAGElAA==.',
Ya='Yahnari:BAAANQADCgMIAwAAAA==.',
Ye='Yel:BAABNQAECoEfAAIEAAkJmSJmAQCUAwAEAAkJmSJmAQCUAwAAAA==.',
Yu='Yuanfen:BAAANQAECgEIAQAAAA==.Yunaraz:BAAANQADCgEIAQAAAA==.Yungshrimpy:BAAANQADCgYIBgAAAA==.',
Za='Zaffira:BAAANQAECgQIBgAAAA==.Zamlen:BAAANQAECgcIEAAAAA==.Zaq:BAAANQADCgYIBgAAAA==.Zargan:BAAANQAECgQIDAAAAA==.Zargstrike:BAAANQADCggIDQABNQAECgQIDAAFAAAAAA==.Zazie:BAAANQAECgYIDgAAAA==.',
Ze='Zedicuzz:BAAANQAECgQICgAAAA==.Zeesala:BAAANQADCgUIBwABNQAECggIGQAIAPsmAA==.Zemms:BAAANQADCggICAAAAA==.',
Zi='Zinbad:BAAANQADCgYIBgAAAA==.Zippbang:BAAANQADCgEIAQAAAA==.Zithazar:BAAANQADCgIIAgAAAA==.Zivyrial:BAAANQAECgUIBQAAAA==.',
Zu='Zugzugzugzug:BAAANQAECgcIDQABNQAECggICAAFAAAAAA==.Zuken:BAAANQAECgQIBAAAAA==.Zuriki:BAAANQADCgMIAwAAAA==.',
['År']='Årdentmeta:BAAANQADCgYIDAABNQAECgUIBQAFAAAAAA==.',
['Ñe']='Ñemo:BAAANQAECggIEgAAAA==.',
['Ør']='Øreo:BAAANQADCgYICwAAAA==.',
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
