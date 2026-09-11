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

local lookup = {'DeathKnight-Blood','Unknown-Unknown','Shaman-Elemental','Warrior-Protection','Evoker-Devastation','DeathKnight-Frost','Warlock-Demonology','Warlock-Destruction','Paladin-Holy','Priest-Holy','Priest-Discipline','Priest-Shadow','DemonHunter-Devourer','DemonHunter-Havoc','Mage-Arcane','Mage-Fire','Warlock-Affliction','Paladin-Protection',}
local provider = {region='US',realm='Mannoroth',name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aadda:BAAANQAECggIDwAAAA==.',
Ab='Abcdpal:BAAANQAFFAIIAgAAAA==.Abena:BAAANQAECgUIBgAAAA==.Abusive:BAABNQAECoEYAAIBAAkJlhnMCgDLAgABAAkJlhnMCgDLAgAAAA==.',
Ac='Acat:BAAANQADCgcIBwAAAA==.',
Ae='Aerogosa:BAAANQAECggIEwAAAA==.',
Ag='Agogagog:BAAANQAECgUIBQAAAA==.',
Ai='Aicam:BAAANQADCgYIBwAAAA==.',
Al='Alarg:BAAANQADCgIIAgABNQAECgIIAgACAAAAAA==.Alatide:BAAANQAECgIIAgAAAA==.Alcani:BAAANQADCgYIBgAAAA==.Aleena:BAAANQADCgcICgAAAA==.Alleriaa:BAAANQADCggICAAAAA==.Altazar:BAAANQAECgUICgAAAA==.Alxath:BAAANQAECgYIBwAAAA==.',
Am='Amaryste:BAAANQADCggICgAAAA==.Amidalah:BAAANQAECgMIAwAAAA==.Amorinaron:BAAANQAECggIEwAAAA==.',
An='Andsong:BAAANQADCgUIBQABNQAECgEIAQACAAAAAA==.Anfalas:BAABNQAECoEcAAIDAAkJFBwMCQAiAwADAAkJFBwMCQAiAwAAAA==.Anic:BAAANQAECgMIAwAAAA==.Anikora:BAAANQADCgcIDAAAAA==.Anjelika:BAAANQAECgIIAgAAAA==.Anklestabber:BAAANQAECgUICAAAAA==.Annathema:BAAANQADCgQIBAAAAA==.Anthlina:BAAANQADCgUIBQAAAA==.',
Ar='Archicrash:BAAANQADCgcICwAAAA==.Archipal:BAAANQADCgMIAwAAAA==.Archomen:BAAANQADCgQIBAABNQAECgQICQACAAAAAA==.Arcwave:BAAANQADCgMIBQAAAA==.Arcyon:BAAANQAECgIIAgAAAA==.Arethi:BAABNQAECoEXAAIEAAgJ5SJYAQA0AwAEAAgJ5SJYAQA0AwAAAA==.Arleos:BAAANQAECgUICAAAAA==.Arroyo:BAAANQADCggIDAAAAA==.Artemasz:BAAANQAECgIIAgAAAA==.Arvoreen:BAAANQADCggICQAAAA==.',
As='Asrelle:BAAANQAECgUIDAAAAA==.Astaumin:BAAANQADCgYICgAAAA==.Asterrin:BAAANQADCgUIBQAAAA==.Astralfrog:BAAANQADCggICAAAAA==.',
Au='Audeline:BAAANQAECgEIAQAAAA==.Augmented:BAAANQABCgYICgABNQAECgcIDwACAAAAAA==.Auraelia:BAAANQADCgEIAQAAAA==.Aurilia:BAAANQADCggICwAAAA==.Aurôra:BAAANQADCgQIBAAAAA==.',
Av='Avran:BAAANQAECgUICAAAAA==.',
Az='Aziala:BAAANQADCggICAABNQAECgYIDQACAAAAAA==.Azreluna:BAAANQAECgUICAAAAA==.',
Ba='Bajablight:BAAANQAECgEIAQAAAA==.Bajiggitee:BAAANQAECgUICAAAAA==.Bananarosin:BAAANQAECgMIBQAAAA==.Banlers:BAAANQADCgYIFAAAAA==.Banmedaddy:BAAANQADCggIFAABNQAECgIIAwACAAAAAA==.Baradoon:BAAANQADCgcIFQAAAA==.',
Be='Bealzhunter:BAAANQADCgUIBgAAAA==.Bela:BAAANQADCgcIBwAAAA==.Bellion:BAAANQADCgYICQAAAA==.Beo:BAAANQAECgcIDwAAAA==.',
Bi='Bigbluetaco:BAAANQAECgUICQAAAA==.Bigchug:BAAANQAECgYICgAAAA==.Bitelo:BAAANQADCggICAABNQADCggICAACAAAAAA==.',
Bl='Blast:BAAANQADCgIIAgAAAA==.Blech:BAAANQAECgYICgAAAA==.',
Bo='Bookerneg:BAAANQADCggIFQAAAA==.Boomslang:BAAANQAECgEIAQAAAA==.Borlen:BAAANQAECgEIAQAAAA==.',
Br='Brassfeather:BAAANQADCggIDQAAAA==.Brewcifer:BAAANQADCgMIAwAAAA==.Brezzath:BAAANQADCggICAAAAA==.Brezzon:BAAANQAECgMIAwABNQAECgYICgACAAAAAA==.Brizzletwo:BAAANQAECgIIAgAAAA==.Brozzath:BAAANQAECgYICgAAAA==.Bryanka:BAAANQADCgIIAgAAAA==.Brättie:BAAANQADCgUIBQAAAA==.Bróx:BAAANQAECgYIDAAAAA==.',
Bu='Bubbajoe:BAAANQAECgIIAgABNQAECgkJGQAFAO0kAA==.Bubbajr:BAAANQADCggIFAAAAA==.Burgy:BAAANQAECgMIAwAAAA==.Burgydk:BAAANQAECgMIAwAAAA==.Buttfancy:BAAANQAECgUICQAAAA==.',
Ca='Calmpressure:BAAANQADCgcICQAAAA==.Capnsparrow:BAAANQADCgQIBAAAAA==.Captncheese:BAAANQAECgEIAQAAAA==.Cassielee:BAAANQADCgMIBgAAAA==.Catabop:BAAANQAECgIIAwABNQAECgQICQACAAAAAA==.Catastorm:BAAANQAECgQICQAAAA==.Catavoker:BAAANQABCgUICQABNQAECgQICQACAAAAAA==.Caustic:BAAANQAECgYICQAAAA==.Caveatemptor:BAAANQAECgcIEgAAAA==.',
Ce='Celaina:BAAANQADCggIDgAAAA==.',
Ch='Chainhappy:BAAANQAECgYICwAAAA==.Cheezybread:BAAANQADCgUIBQAAAA==.Chimeric:BAAANQAECgYICwAAAA==.Chlover:BAAANQADCggIEwAAAA==.Chmap:BAAANQADCgcIBwAAAA==.Chontosh:BAAANQAECgEIAQAAAA==.Chozenfate:BAAANQADCggICQAAAA==.Chronuwu:BAAANQADCgIIAgAAAA==.',
Ci='Cindymccain:BAAANQAECgUIBQAAAA==.',
Cl='Clearsight:BAAANQADCgYIBgABNQAECgUICQACAAAAAA==.',
Co='Cometh:BAAANQADCgUIBQAAAA==.Compute:BAABNQAECoEVAAIGAAgJTxkcCQBLAgAGAAgJTxkcCQBLAgABNQAECgYIBwACAAAAAA==.Corursa:BAAANQADCgYIBgABNQAECgQIBAACAAAAAA==.Cozmowaffle:BAAANQADCgIIAgAAAA==.',
Cr='Cronauer:BAAANQADCgYIBgAAAA==.Cryofrog:BAAANQABCgIIAwAAAA==.',
Cu='Cuppicakies:BAAANQADCgMIAwAAAA==.',
Da='Daddyfatslap:BAAANQADCggIDQAAAA==.Daggerz:BAAANQAECgIIAwAAAA==.Daguitas:BAAANQAECgQIBAAAAA==.Danasty:BAAANQABCgIIBQAAAA==.Danidakiesh:BAAANQADCgQIBgAAAA==.Daralina:BAAANQABCgIIAgAAAA==.Darbreezius:BAAANQAECgMIAwAAAA==.Daribow:BAAANQADCgQIBAAAAA==.Darkcoffee:BAAANQAECgMIBAAAAA==.Darkvalk:BAAANQADCgEIAQAAAA==.Darvax:BAAANQADCgEIAQAAAA==.Datacenter:BAAANQAECgYIBwAAAA==.Dawgan:BAAANQAECgEIAQAAAA==.',
De='Deadlyfrog:BAAANQABCgEIAQAAAA==.Deamionn:BAAANQADCggIEgAAAA==.Deathbauchs:BAAANQADCgcICwAAAA==.Deathlylove:BAAANQABCgYIBgAAAA==.Deathtreader:BAAANQADCggICAAAAA==.Demoinc:BAAANQAECgcIDAAAAA==.Denathus:BAAANQADCgUICQAAAA==.Denovo:BAAANQADCggICAABNQAECgcIEgACAAAAAA==.Desipator:BAAANQADCgIIAgAAAA==.Destinyløl:BAAANQADCgUIBQAAAA==.',
Di='Diabolix:BAAANQADCgQIBwAAAA==.Dilo:BAAANQADCgMIAwAAAA==.Divalatina:BAAANQAFFAIIAgAAAA==.Divinefrog:BAAANQADCgcIBwAAAA==.',
Dj='Djmax:BAAANQADCgIIAgAAAA==.',
Dk='Dkthae:BAAANQAECgQIBwAAAA==.',
Dl='Dlxanomaly:BAAANQAECgQIBgAAAA==.',
Do='Donttouchme:BAAANQADCgcIDAAAAA==.Doohickey:BAAANQADCggIDgAAAA==.Doubledeez:BAAANQADCgIIAgAAAA==.Doubledz:BAAANQADCgYIDQAAAA==.',
Dr='Dragondzntz:BAAANQADCggIDwAAAA==.Dragonfrog:BAAANQABCgYIBwAAAA==.Dreamyeyes:BAAANQAECgMIAwAAAA==.Drerein:BAAANQADCgcIEwAAAA==.',
Du='Dubz:BAAANQAECgcIBwAAAA==.Dundeal:BAAANQADCgcIBwAAAA==.Dunkel:BAAANQAECgcIDwAAAA==.Dupichu:BAAANQAECgMIAwAAAA==.',
Ea='Eataa:BAAANQAECgIIAgAAAA==.',
Eb='Ebonhammer:BAAANQADCgIIAgAAAA==.',
Eg='Egrilo:BAAANQADCggICAAAAA==.',
Ei='Eileithyia:BAAANQAECgEIAQAAAA==.',
El='Elekastra:BAAANQADCgMIAwAAAA==.Elyndor:BAAANQADCgUIBQAAAA==.',
Em='Emopally:BAAANQAECgQIBAAAAA==.Emopower:BAAANQAECgIIAgAAAA==.',
En='Enderr:BAAANQAECgUIBwAAAA==.Enegma:BAAANQADCgYIBgAAAA==.Enzini:BAAANQAECgEIAQAAAA==.',
Er='Erashi:BAAANQAECgQIBAAAAA==.',
Fa='Falculan:BAAANQADCgEIAQAAAA==.Fallen:BAAANQAECgIIAwAAAA==.Fatherchung:BAAANQAECgEIAQAAAA==.Fayotbeanz:BAAANQABCgQIBgAAAA==.',
Fe='Felwyth:BAAANQADCgUIDgABNQAECgcIDAACAAAAAA==.',
Fi='Finneas:BAAANQADCgEIAQAAAA==.Fireworkxz:BAAANQAECgEIAgAAAA==.',
Fl='Flarehammer:BAAANQAECgYICgAAAA==.Flogh:BAAANQAECgUIBQAAAA==.',
Fo='Fomanshi:BAAANQAECgcIDwAAAA==.Forleaf:BAAANQADCgYIBgAAAA==.Forsierra:BAAANQADCgEIAQAAAA==.Foxiji:BAAANQADCgUIBQAAAA==.',
Fr='Frexican:BAAANQAECgQIAwAAAA==.Fright:BAAANQADCgcIDQAAAA==.Frogleggs:BAAANQABCgMIAwAAAA==.Frogshock:BAAANQABCgYICAAAAA==.',
Fu='Fupabean:BAAANQABCgQIBgAAAA==.Fure:BAAANQADCgQIBAAAAA==.Fuupa:BAAANQADCgIIAgAAAA==.',
Ge='Genridge:BAAANQADCgYIDAAAAA==.',
Gi='Gilani:BAAANQAECgEIAQAAAA==.',
Gl='Glp:BAAANQAECgIIAwAAAA==.',
Go='Gorpy:BAABNQAECoEfAAMHAAkJnCOTAwA8AwAHAAgJCiOTAwA8AwAIAAcJwh1ABgB3AgAAAA==.Gotrott:BAAANQADCgEIAQAAAA==.',
Gr='Gravybones:BAAANQADCgcIDQAAAA==.Greenjesh:BAAANQAECgYICAABNQAECgcIDwACAAAAAA==.Greensheesh:BAAANQAECgcIDwAAAA==.Greypilgram:BAAANQADCgYICAAAAA==.Grimstank:BAAANQADCgcIBwAAAA==.Grizzlygerm:BAAANQADCgUIBQAAAA==.Grizzlyoné:BAAANQADCgcIEgAAAA==.Grumbleface:BAABNQAECoEYAAIJAAkJqx7QBABJAwAJAAkJqx7QBABJAwAAAA==.Grumbletron:BAAANQAECgMIAwAAAA==.',
Gs='Gstatus:BAAANQAECgQIBAAAAA==.',
Gu='Gunel:BAAANQADCggICAAAAA==.',
Ha='Haawee:BAAANQAECgQIBQAAAA==.Hailcthulhu:BAAANQAECgUICgAAAA==.Handorn:BAAANQAECgEIAQABNQAECgcIDgACAAAAAA==.Hanwha:BAAANQAECgYICwAAAA==.Harrower:BAAANQAECgIIAgAAAA==.Haze:BAAANQAECgYIBgAAAA==.Hazzkul:BAAANQAECgYIBwAAAA==.',
He='Healness:BAAANQAECgcICAAAAA==.Helasam:BAAANQAECgEIAQAAAA==.Hellbourné:BAAANQAECgEIAQAAAA==.Helloboys:BAAANQAECgUICAAAAA==.Henzo:BAAANQABCgEIAQAAAA==.Herbavor:BAAANQAECgMIAwAAAA==.Hermes:BAAANQAECgYICwAAAA==.Hermestrisme:BAAANQADCgMIAwAAAA==.',
Ho='Holexplorer:BAAANQAECgcIEQAAAA==.Holytrashie:BAAANQADCgYIDgAAAA==.Honeybadger:BAAANQAECgUICAAAAA==.Honnybuns:BAAANQABCgEIAQAAAA==.Hordeslayer:BAAANQADCgUICAAAAA==.',
Hs='Hsk:BAAANQAECgUIBgAAAA==.',
Hu='Hulkaholic:BAAANQAECgIIAwAAAA==.Hulkclap:BAAANQABCgMIAwAAAA==.Hulkhunts:BAAANQABCgUIBwAAAA==.',
Ic='Icecat:BAAANQAECgUIBQAAAA==.',
Il='Ilian:BAAANQADCgQIBwAAAA==.',
In='Innothule:BAAANQADCgUIBQAAAA==.Inseratum:BAAANQADCgUICgAAAA==.',
Ir='Iriedraco:BAAANQABCgIIAgAAAA==.Irielite:BAAANQABCgQIBAAAAA==.Ironblast:BAAANQAECgEIAgAAAA==.',
Is='Ishaa:BAAANQADCgIIAgAAAA==.',
It='Ithanksource:BAAANQAECgYICQAAAA==.',
Iv='Ivincentl:BAAANQADCgUIBQAAAA==.',
Ix='Ixgangrxi:BAAANQADCgQIBAAAAA==.',
Ja='Jake:BAAANQABCgIIAwAAAA==.Jankie:BAAANQAECgQIBQAAAA==.Jarnar:BAAANQAECgQIBAAAAA==.Jaxsin:BAAANQADCgEIAQAAAA==.',
Je='Jearemy:BAAANQADCgEIAQAAAA==.Jekster:BAAANQADCgEIAQAAAA==.',
Ji='Jingburger:BAAANQADCggIDwAAAA==.Jinnosuke:BAAANQAECgEIAgAAAA==.',
Jo='Joecelin:BAAANQADCgUIBQAAAA==.Johnathanwow:BAAANQAECgIIAgAAAA==.Johnnytotem:BAAANQAECgcIDgABNQABCgIIAgACAAAAAA==.Jonastus:BAAANQADCgQIBAAAAA==.',
Ju='Judgemental:BAAANQADCgUIBgAAAA==.',
Jy='Jykyl:BAAANQAECgMIBAAAAA==.',
['Jê']='Jêkyl:BAAANQADCgEIAQAAAA==.',
Ka='Kaidoazure:BAAANQADCgUIBQAAAA==.Kaipod:BAAANQAECgEIAQAAAA==.Kaorrii:BAAANQADCgEIAQAAAA==.Karlaia:BAAANQADCgEIAQAAAA==.Kattána:BAAANQADCgYIDAABNQADCggIEwACAAAAAA==.Kauthoon:BAAANQADCgQIBwAAAA==.Kaykotta:BAAANQADCgMIAwAAAA==.Kazademon:BAAANQAECgMIAwAAAA==.Kazmo:BAAANQAECgMIBAAAAA==.',
Ke='Kegheimer:BAAANQADCgMIBAABNQADCgcIEQACAAAAAA==.Kensington:BAAANQAECgUIBQABNQAECgYICgACAAAAAA==.Keyalovar:BAABNQAECoFwAAIKAAgJ9ib/AACsAwAKAAgJ9ib/AACsAwAAAA==.Keìra:BAAANQADCgYIBwAAAA==.',
Kh='Khalgon:BAAANQADCggICAAAAA==.',
Ki='Kimbecky:BAAANQADCgIIAgAAAA==.Kimchii:BAAANQADCgQIBQAAAA==.Kiritoo:BAAANQABCgIIAgAAAA==.Kishukae:BAAANQAECgIIAwAAAA==.Kislosladkiy:BAAANQAECggIEAAAAA==.',
Kl='Klassik:BAAANQADCgYICwAAAA==.',
Kn='Knobsnob:BAABNQAECoEPAAQLAAcJAB1RBADaAQALAAUJPCBRBADaAQAKAAIJ6xTsVgCLAAAMAAIJtws+LwBsAAAAAA==.',
Ko='Kodeezy:BAAANQADCggICAABNQAECgQIBgACAAAAAA==.',
Kr='Kriztina:BAAANQADCggICQAAAA==.Kronkk:BAAANQADCgIIAgAAAA==.Kropie:BAAANQAECgQIBAAAAA==.',
Ky='Kynga:BAAANQADCgUIBwAAAA==.',
La='Ladrian:BAAANQAECgYICgAAAA==.Larenieth:BAAANQADCgcICQAAAA==.Larüd:BAAANQAECgYICAAAAA==.Lasmon:BAAANQADCgUIBQAAAA==.',
Le='Legallyblind:BAAANQAECgUIBwAAAA==.Legit:BAAANQAECgMIBAAAAA==.',
Li='Lightblessed:BAAANQADCgcIBwABNQAECgUIBwACAAAAAA==.Lightsworne:BAAANQAECgQIBgAAAA==.Lillithx:BAAANQADCgUIDQAAAA==.Lindarenne:BAAANQADCgUIBQAAAA==.Lindree:BAAANQADCgYIBgAAAA==.Lirang:BAAANQAECgEIAQAAAA==.Littlewashu:BAAANQABCgUIBwAAAA==.Lizardfistin:BAABNQAECoEZAAIFAAkJ7SSqAAC+AwAFAAkJ7SSqAAC+AwAAAA==.',
Lo='Loads:BAAANQAECggIAQAAAA==.Lockñlol:BAAANQABCgQIBAAAAA==.Loni:BAAANQADCggIFQAAAA==.Loonaimp:BAAANQAECgMIBQAAAA==.Lorthos:BAAANQABCgIIAgAAAA==.Lotús:BAAANQAECgYICwAAAA==.',
Lu='Lumenox:BAAANQAECgYICQAAAA==.Luminarria:BAAANQAECgIIAgAAAA==.Lupomic:BAAANQAECgIIAgAAAA==.',
Ma='Maeivalla:BAAANQAECgYICgAAAA==.Mageler:BAAANQAECgUIBwAAAA==.Magicpurro:BAAANQAECgQIBAABNQAECgkJGQAFAO0kAA==.Maiajayde:BAAANQABCgIIAgAAAA==.Malicebane:BAAANQABCgQIBAAAAA==.Malma:BAAANQADCgYIBgAAAA==.Mancane:BAAANQAECgcIEQAAAA==.Margolis:BAAANQADCggICAABNQAECgkJHwAHAJwjAA==.Margrathwin:BAAANQAECgYICwAAAA==.Marxman:BAAANQADCggIDwABNQAFFAEIAQACAAAAAA==.Mask:BAAANQADCgUIBQAAAA==.Mauchs:BAAANQADCgUICQAAAA==.Mayorwanna:BAAANQABCgIIBAAAAA==.',
Me='Meganite:BAAANQADCgYIDwAAAA==.Melaniatrump:BAAANQADCgEIAQAAAA==.Meningitis:BAAANQADCgMIAwAAAA==.',
Mi='Miahas:BAAANQADCgMIAwAAAA==.Mikecoxwoll:BAAANQAECgUICQAAAA==.Milkmountain:BAAANQABCgEIAQAAAA==.Minalina:BAAANQAECggIBwAAAA==.Mindedz:BAAANQAECgQIBgAAAA==.Minnow:BAAANQAECgEIAgAAAA==.Miren:BAAANQAECgUICQAAAA==.Mittsmitts:BAAANQADCgYIEQAAAA==.',
Mo='Moistbuns:BAAANQAECgEIAQAAAA==.Molatova:BAAANQAECgMIAwAAAA==.Moozart:BAAANQADCgQIBAABNQAECgUICQACAAAAAA==.Mooze:BAAANQAECgQIBAAAAA==.Morgiana:BAAANQAECgIIAgAAAA==.Mortiferia:BAAANQAECgUICAAAAA==.Mortzx:BAAANQADCgcIBwABNQADCggICQACAAAAAA==.Motown:BAAANQAECgQIBgAAAA==.',
Mu='Muyo:BAAANQADCgEIAQAAAA==.Muzzlefaulf:BAAANQABCgIIAgAAAA==.',
Mw='Mwooq:BAAANQADCgYICAAAAA==.',
My='Mystics:BAAANQAECgUICAAAAA==.Mystiklight:BAAANQADCgUIBQABNQADCggIDQACAAAAAA==.Mythomagic:BAAANQAECgUIBQAAAA==.',
Na='Nadin:BAAANQADCggIEAAAAA==.Naebchi:BAAANQADCgUIBQAAAA==.Nahjiky:BAAANQADCgYICwAAAA==.Nastyjob:BAAANQAECgYIAQAAAA==.',
Ne='Necronips:BAAANQADCgIIAgAAAA==.Neurosis:BAAANQADCggIDgAAAA==.Nezzthena:BAAANQADCgEIAQAAAA==.',
Ni='Niari:BAAANQADCgUIBwAAAA==.Nikale:BAAANQADCgcIEQAAAA==.',
No='Nordy:BAAANQAECgIIAgAAAA==.Normadin:BAAANQAECgUICAAAAA==.Norsefolk:BAAANQADCgIIAgAAAA==.Norseroch:BAAANQADCgYICgABNQADCgIIAgACAAAAAA==.',
Nv='Nvd:BAABNQAECoERAAMNAAkJfB7yCwCyAgANAAgJoyHyCwCyAgAOAAEJRwW3NQA+AAABNQAFFAIIAgACAAAAAA==.',
Ny='Nyan:BAAANQAECgUIBQABNQAECgcIDwACAAAAAA==.Nysonnia:BAAANQAECgMIBQABNQAECgcIDwACAAAAAA==.',
Ob='Obliterate:BAAANQAECgIIAwABNQAECgMIAwACAAAAAA==.Obsidianfire:BAAANQADCgQIBAABNQADCggIDQACAAAAAA==.',
Od='Odonn:BAAANQADCgIIAwAAAA==.Odìnsôn:BAAANQADCgcIEAAAAA==.',
Om='Omegafortswl:BAAANQADCgUICwAAAA==.Omeni:BAAANQAECgQICQAAAA==.',
On='Oneshockiboi:BAAANQADCgMIAwAAAA==.',
Or='Orbits:BAAANQADCgcIBwAAAA==.Oric:BAAANQAECgcIDwAAAA==.',
Pa='Pallverize:BAAANQADCggICAAAAA==.Paperdaen:BAAANQAECgIIAgAAAA==.Parkle:BAAANQADCgUICQAAAA==.Pastore:BAAANQAECgQIBgAAAA==.',
Pe='Pelee:BAAANQABCgIIAgAAAA==.Peonmè:BAAANQAECgIIAgAAAA==.',
Pf='Pfeffernusse:BAAANQAFFAEIAQAAAA==.',
Ph='Phalluic:BAAANQADCgYIBgAAAA==.Philpriest:BAAANQAECgMIBAAAAA==.',
Pl='Plagued:BAAANQADCgYICwABNQAECgIIAwACAAAAAA==.Plagueis:BAAANQADCgMIAwAAAA==.',
Po='Pokeysticks:BAAANQAECgMIBQAAAA==.Poncia:BAAANQAECgEIAQAAAA==.',
Pr='Pragmax:BAAANQAECgMIBAAAAA==.Praynation:BAAANQADCggIDAAAAA==.Prediction:BAAANQAECgEIAgAAAA==.',
Pu='Puffcodan:BAAANQAECgEIAwAAAA==.Pugcival:BAAANQADCgUIBQAAAA==.Punîshër:BAAANQAECgQIBgAAAA==.Puppenance:BAAANQADCgMIAwAAAA==.Purgatoriwlf:BAAANQAECgYICgAAAA==.',
Py='Pyrogale:BAAANQADCgcIDAAAAA==.',
['Pó']='Póe:BAAANQAECgYICAAAAA==.',
Ql='Qlimax:BAAANQADCgQIBAAAAA==.',
Qu='Quadzilla:BAAANQADCggICAAAAA==.',
Ra='Ragnalock:BAAANQADCgQIBgAAAA==.Ragnir:BAAANQADCgMIAwAAAA==.Rarh:BAAANQADCgYICQAAAA==.Rathlore:BAAANQADCgUIBQAAAA==.Rathorn:BAAANQADCgQIBwAAAA==.Rawdawgan:BAAANQADCgYIBwAAAA==.Rawrbotz:BAAANQADCgUICQAAAA==.Razeneth:BAAANQAECggIBgAAAA==.',
Re='Rebornqt:BAAANQADCgIIAgAAAA==.Reforsaken:BAAANQAECgYICgAAAA==.Relarian:BAAANQAECgQIBQAAAA==.Releimus:BAAANQADCgcIDAAAAA==.Revengeance:BAAANQAECgUICAAAAA==.',
Ro='Roanoke:BAAANQABCgMIAwAAAA==.Rocketsauce:BAAANQADCggICAABNQAECgEIAQACAAAAAA==.Romcrom:BAAANQAECgYICwAAAA==.Rommagicus:BAAANQADCgUIBQABNQAECgYICwACAAAAAA==.Rosalíe:BAAANQADCgQIBAAAAA==.Roxen:BAAANQAECgQIBQAAAA==.',
Ru='Rubyhart:BAAANQADCgYIBgAAAA==.Rukenji:BAAANQAECggIEgAAAA==.Runíc:BAAANQADCgEIAQAAAA==.',
Ry='Ryuunosuke:BAAANQAECgUICAAAAA==.',
Sa='Sabers:BAAANQAECgUIBgAAAA==.Sabriinaa:BAAANQABCgMIBAAAAA==.Sabrinadin:BAAANQABCgMIBAAAAA==.Sadako:BAAANQABCgQICAAAAA==.Sakkraa:BAAANQAECgcIDgAAAA==.Salla:BAAANQAECgMIAwAAAA==.Sannea:BAAANQADCgQIBQAAAA==.Saponite:BAAANQADCgIIAgAAAA==.Sarumon:BAAANQAECgQIBAAAAA==.',
Sc='Schwimdy:BAAANQADCgUIBQAAAA==.',
Se='Secondlife:BAAANQADCgQIBAAAAA==.Seeingeyedog:BAAANQAECgQIBwAAAA==.Sevenseconds:BAAANQADCgcIDQAAAA==.',
Sh='Shadowscythe:BAAANQADCggIDgAAAA==.Shampann:BAAANQADCgEIAQAAAA==.Sharish:BAAANQABCgIIAgAAAA==.Shaundel:BAAANQAECgUIDQAAAA==.Shavocadoos:BAAANQADCggICAAAAA==.Shezmu:BAAANQAECgUICQAAAA==.Shiftinman:BAAANQADCgIIAgAAAA==.Shiftintime:BAAANQADCgQIBAABNQAECgcIDQACAAAAAA==.Shoopa:BAAANQAECgMIAwAAAA==.Shoopah:BAAANQAECgQIBwAAAA==.Short:BAAANQAECgUICAAAAA==.Shädøwreeper:BAAANQADCgEIAQAAAA==.',
Si='Siduiss:BAAANQAECgIIAwAAAA==.Silvrfoxx:BAAANQADCgcIBwAAAA==.Silvänus:BAAANQAECgYIDAAAAA==.Simsha:BAAANQAECgQIBAAAAA==.',
Sk='Skinnylejend:BAAANQAECgUIBwAAAA==.Skmoon:BAAANQADCgIIAgAAAA==.',
Sm='Smiley:BAAANQAECgQIBQAAAA==.',
Sn='Snac:BAAANQABCgEIAQAAAA==.Snackrifice:BAAANQADCggIEgAAAA==.',
So='Somoner:BAAANQAECgYIDwAAAA==.Sompal:BAAANQAECgEIAgABNQAECgYIDwACAAAAAA==.',
Sp='Sparksizzle:BAABNQAECoEQAAMPAAgJxRBSTAAGAgAPAAgJxRBSTAAGAgAQAAMJqAYpAwC0AAAAAA==.Spiseyy:BAAANQADCgYIBgAAAA==.Spitfel:BAABNQAECoEYAAQIAAkJjCD/AwDCAgAIAAkJuhf/AwDCAgAHAAUJ3B+WLQCsAQARAAEJSRwqEQBSAAAAAA==.Spitfirex:BAAANQAECgQIBQABNQAECgkJGAAIAIwgAA==.',
St='Stoix:BAAANQADCgUIAgAAAA==.Stompymunk:BAAANQADCgIIAgAAAA==.Stopzîlla:BAAANQAECgQIBAAAAA==.',
Su='Sugrdadi:BAAANQAECgMIAwAAAA==.',
Sw='Swippie:BAAANQADCgYIBQAAAA==.',
Sy='Sylmar:BAAANQADCggIDQAAAA==.Syndora:BAAANQAECgYIDAAAAA==.',
Ta='Tacoboss:BAAANQADCgcIBwAAAA==.Taerun:BAAANQADCgYIBwAAAA==.Tahu:BAAANQAECgQIBQAAAA==.Takal:BAAANQADCgYICwAAAA==.Talreth:BAAANQADCgYICgAAAA==.',
Te='Teake:BAAANQADCgUIBQAAAA==.Teddymoove:BAAANQADCgYIBgAAAA==.Teddyruxpin:BAAANQADCgcIBwAAAA==.Teddytotems:BAAANQAECgMIBQAAAA==.Ternal:BAAANQADCgcICAAAAA==.Terrato:BAAANQAECgEIAQAAAA==.Terrorize:BAAANQAECgEIAQAAAA==.Terrous:BAAANQAECgcIEgAAAA==.Tetranutra:BAAANQADCgQIBAAAAA==.',
Th='Thakur:BAAANQAECgYIDQAAAA==.Theoslight:BAAANQAECgIIAgAAAA==.Thepetmaster:BAAANQADCgUICgAAAA==.Thordenson:BAAANQABCgIIAgAAAA==.Thrandorinil:BAAANQADCgQIBgAAAA==.Threxon:BAAANQAECgMIAwAAAA==.Thunderfire:BAAANQADCggIDQAAAA==.',
Ti='Timepally:BAAANQADCgYIBgAAAA==.Tinytimothy:BAAANQADCgIIAgAAAA==.',
To='Tokajok:BAAANQAECgcIEgAAAA==.Tokash:BAAANQADCggICQABNQAECgcIEgACAAAAAA==.Tokashi:BAAANQAECgcIDAABNQAECgcIEgACAAAAAA==.Tokeadin:BAAANQAECgQIBQAAAA==.Tokzillu:BAAANQADCgUIBQAAAA==.Tomaki:BAAANQADCgcIBwAAAA==.',
Tr='Trackervalk:BAAANQADCgIIAgAAAA==.Trenbölöne:BAAANQAECgYICgAAAA==.Treyrin:BAAANQAECgQIBAAAAA==.Tritonian:BAACNQAFFIEFAAISAAQJ3CNvAAC6AQASAAQJ3CNvAAC6AQA1AAQKgRkAAhIACQkhJj8AAOgDABIACQkhJj8AAOgDAAAA.Trollmother:BAAANQADCggICAAAAA==.Trolloutcast:BAAANQAECgQICAABNQAECgkJHwAHAJwjAA==.',
Tu='Turtle:BAABNQAECoEYAAIJAAkJahkJCgDtAgAJAAkJahkJCgDtAgAAAA==.',
Tw='Twizzlestick:BAAANQABCgUIBQAAAA==.',
Ty='Tyluwu:BAAANQAECgQIBAAAAA==.Tyranis:BAAANQADCgIIAgAAAA==.Tyzz:BAAANQAECgEIAQAAAA==.',
['Tì']='Tìtân:BAAANQADCgcIBwAAAA==.',
['Tÿ']='Tÿ:BAAANQAECgUIBQAAAA==.',
Um='Umbrianna:BAAANQAECgUICAAAAA==.',
Uw='Uwuhunterxd:BAAANQAFFAEIAQAAAA==.',
Va='Vaelowyn:BAAANQADCggICQAAAA==.Vakar:BAAANQADCgYIDgAAAA==.Valkyriee:BAAANQABCgIIAgAAAA==.Varninn:BAAANQADCgcICQAAAA==.Vasha:BAAANQAECgQIBAAAAA==.',
Ve='Ventee:BAAANQAECgEIAQAAAA==.',
Vi='Vincentv:BAAANQADCgYIBgAAAA==.Virtuositee:BAAANQADCgYICwABNQAECgUICAACAAAAAA==.Vitadin:BAAANQAECgEIAgAAAA==.',
Vr='Vraugashan:BAAANQADCgcICwAAAA==.Vrice:BAAANQADCgIIAgAAAA==.',
['Vá']='Váprak:BAAANQADCgcICAAAAA==.',
Wa='Walmage:BAAANQADCgQIBAAAAA==.',
Wh='Whompie:BAAANQABCgEIAQAAAA==.',
Wi='Winning:BAAANQAECggIBQAAAA==.Wireless:BAAANQAECgYICgAAAA==.',
Wo='Wokker:BAAANQADCggIFAAAAA==.',
Wq='Wqwq:BAAANQADCgEIAQAAAA==.',
Wu='Wuköng:BAAANQAECgEIAQAAAA==.',
Xe='Xencero:BAAANQAECgMIAwAAAA==.Xeum:BAAANQAECgMIBgAAAA==.',
Xg='Xgirlfriend:BAAANQAECgQICwAAAA==.',
Xh='Xhar:BAAANQAECgMIAwAAAA==.Xhyros:BAAANQAECgYIDQAAAA==.',
Xi='Xiahou:BAAANQAECgUICAAAAA==.',
Xo='Xoothette:BAAANQADCgcIBwABNQAECgkJHwAHAJwjAA==.',
Ya='Yahnari:BAAANQADCgMIAwAAAA==.',
Ye='Yel:BAAANQAECggIEAAAAA==.',
Yu='Yuanfen:BAAANQAECgEIAQAAAA==.Yungshrimpy:BAAANQADCgYIBgAAAA==.',
Za='Zaffira:BAAANQAECgIIAgAAAA==.Zamlen:BAAANQAECgUICgAAAA==.Zargan:BAAANQAECgQIDAAAAA==.Zargstrike:BAAANQADCgUIBQAAAA==.Zazie:BAAANQAECgUICAAAAA==.',
Ze='Zedicuzz:BAAANQAECgQIBgAAAA==.Zeesala:BAAANQADCgUIBQABNQAECgcIDwACAAAAAA==.Zemms:BAAANQADCggICAAAAA==.',
Zi='Zithazar:BAAANQADCgIIAgAAAA==.Zivyrial:BAAANQAECgUIBQAAAA==.',
Zu='Zugzugzugzug:BAAANQAECgUIBwABNQAECgcIDgACAAAAAA==.Zuken:BAAANQAECgQIBAAAAA==.Zuriki:BAAANQADCgMIAwAAAA==.',
['År']='Årdentmeta:BAAANQADCgYICwABNQAECgQIBAACAAAAAA==.',
['Ñe']='Ñemo:BAAANQAECgUICwAAAA==.',
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
