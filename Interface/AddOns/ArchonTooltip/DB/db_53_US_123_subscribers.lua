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

local lookup = {'Unknown-Unknown','Evoker-Preservation','Druid-Balance','Monk-Windwalker','Priest-Holy','DeathKnight-Blood','Warlock-Destruction','Warrior-Arms','Hunter-Marksmanship','Paladin-Protection','Warlock-Affliction','Warlock-Demonology','Mage-Arcane',}
local provider = {region='US',realm='Illidan',name='US',type='subscribers',zone=53,date='2026-09-01',data={Aa='Aajt:BAEANQADCgYIBgABNQAFFAIIAgABAAAAAA==.',
Ab='Abhavani:BAEANQAECgMIAwABNQAECgQIBQABAAAAAA==.Abmyn:BAEANQAECgQICAABNQAFFAIIAgABAAAAAA==.Abracastrun:BAEANQADCgYIBgABNQAECgMIBQABAAAAAA==.',
Ac='Aceybdreamin:BAEANQAECgcIDQAAAA==.Acrodruid:BAEANQAECggIDgAAAA==.Acrojr:BAECNQAFFIEHAAICAAYJWxUaAAA0AgaODQAAAgA8AHUNAAABAEYAfw0AAAEASQCpDQAAAQBJAFwNAAABAA8AMw0AAAEAIgACAAYJWxUaAAA0AgaODQAAAgA8AHUNAAABAEYAfw0AAAEASQCpDQAAAQBJAFwNAAABAA8AMw0AAAEAIgA1AAQKgRgAAgIACQlEJR0AANoDAAIACQlEJR0AANoDAAE1AAQKCAgOAAEAAAAA.Acropala:BAEANQAECgIIAgABNQAECggIDgABAAAAAA==.',
Ae='Aelern:BAEANQAECgMIAwAAAA==.',
Af='Afkpally:BAEANQADCggICAAAAA==.',
Ah='Ahiraja:BAEANQADCgYIDAABNQAECgYICQABAAAAAA==.',
Ai='Ailistrasza:BAEANQAECgYICgAAAA==.Ailithm:BAEANQADCgEIAQABNQAECgYICgABAAAAAA==.Airbearkegs:BAEANQADCggIDgAAAA==.',
Aj='Ajtt:BAEANQAFFAIIAgAAAA==.',
Ak='Akygho:BAEANQAECgUIBwABNQAECggIDQABAAAAAA==.Akylix:BAEANQAECgcIDAABNQAECggIDQABAAAAAA==.',
Al='Allisall:BAEANQAECgcIDAABNQAFFAYIBgADACQYAA==.Alpacadisco:BAEANQAECgcIBAABNQAECggIBgABAAAAAA==.Alteron:BAEANQADCggICgABNQAECgIIAgABAAAAAA==.',
Am='Ambyulentz:BAEANQADCgUICAABNQAECgYIBgABAAAAAA==.',
Aq='Aqual:BAEANQAECgcIBwAAAA==.',
Ar='Arcaneoogie:BAEANQAECgIIAgABNQAECgQIBAABAAAAAA==.',
As='Asfri:BAEANQADCggICAABNQAFFAUIBwACAJoXAA==.Asguardlol:BAEANQAECgQIBwABNQAFFAUIBwACAJoXAA==.Ashineb:BAEANQAECggIBQABNQAECggIBgABAAAAAA==.Ashined:BAEANQAECggIBgAAAA==.Ashinedkfive:BAEANQAECggIBQABNQAECggIBgABAAAAAA==.Ashinedktre:BAEANQAECggIBQABNQAECggIBgABAAAAAA==.Ashinedktwo:BAEANQAECggIBQABNQAECggIBgABAAAAAA==.Askaori:BAEBNQAFFIEHAAICAAUJmhdNAADVAQWODQAAAgBUAHUNAAABADUAfw0AAAEAHwCpDQAAAgBkADMNAAABACEAAgAFCZoXTQAA1QEFjg0AAAIAVAB1DQAAAQA1AH8NAAABAB8AqQ0AAAIAZAAzDQAAAQAhAAAA.Asynchronous:BAEANQADCggICAABNQAFFAUIBwAEAG4gAA==.',
At='Atrocity:BAEBNQAFFIEHAAIFAAYJvR4DAABvAgaODQAAAgBaAHUNAAABAGIAfw0AAAEAUACpDQAAAQBcAFwNAAABAFQAMw0AAAEAGQAFAAYJvR4DAABvAgaODQAAAgBaAHUNAAABAGIAfw0AAAEAUACpDQAAAQBcAFwNAAABAFQAMw0AAAEAGQAAAA==.Atrocitydr:BAEANQAECgcIBwABNQAFFAYIBwAFAL0eAA==.Atrocityev:BAEANQAECgIIAgABNQAFFAYIBwAFAL0eAA==.',
Au='Aumni:BAEANQAFFAEIAQAAAA==.',
Az='Azazèll:BAEANQADCgIIAgABNQAECgcIDQABAAAAAA==.Azumaru:BAEANQAECgcIDwAAAA==.Azôth:BAEANQAECggIDgAAAA==.',
Ba='Babylonius:BAEANQAFFAEIAgAAAA==.Badboyx:BAEANQAECggIBQAAAA==.Badgerdh:BAEANQAECgMIAwABNQAECgcIBwABAAAAAA==.Badgerr:BAEANQAECgcIBwAAAA==.',
Be='Beaktease:BAEANQADCggICAABNQADCggIDQABAAAAAA==.Beefjerkyjac:BAEANQAECgIIAgABNQAECgYIBgABAAAAAA==.Bennymage:BAEANQAECgQIBAABNQAECgcIDQABAAAAAA==.Benzoath:BAEANQAECgcIDQAAAA==.Berul:BAEANQAECgQIBAABNQAECgcIDQABAAAAAA==.Beyloc:BAEANQAFFAEIAQAAAA==.',
Bi='Bigdewd:BAEANQADCgYIBwAAAA==.Bigglés:BAEANQADCgIIAgABNQAECgcIDQABAAAAAA==.',
Bl='Bladecrazy:BAEANQAECgcICwAAAA==.Bluebare:BAEANQADCgQIBAABNQADCggIDgABAAAAAA==.Bluecast:BAEANQADCgUIBQABNQADCggIDgABAAAAAA==.Blueshiv:BAEANQADCgQIBAABNQADCggIDgABAAAAAA==.Blueshout:BAEANQADCggIDgAAAA==.',
Br='Breadlife:BAEANQAECgQIBAAAAA==.Brewwcifer:BAEANQAECgUIBQAAAQ==.Bricklordx:BAEANQAECgcIDQAAAA==.Brotherlip:BAEANQAECgYIBAABNQAECggIBgABAAAAAA==.',
Bu='Burritotime:BAEANQAECgIIBAAAAA==.Busroll:BAEANQADCggICAABNQAECgcICgABAAAAAA==.Bussygrip:BAEANQAECgcIDQABNQAECgcICgABAAAAAA==.',
['Bë']='Bëru:BAEANQAECgcIDQAAAA==.',
Ca='Captclit:BAEANQAECgYICgAAAA==.Cataraxe:BAEANQAECgMIBAAAAA==.',
Ce='Cellainemoon:BAEANQAECgQIBAABNQABCgIIAgABAAAAAA==.Cernish:BAEANQAECgcIBwAAAA==.',
Ch='Cheetahdisco:BAEANQAECggIBQABNQAECggIBgABAAAAAA==.Chiives:BAEANQADCgUIBQAAAA==.Chinaru:BAEANQAECgQIBAAAAA==.Chuckrally:BAEANQADCgYIBgAAAA==.Chungushole:BAEANQAECgcIBAABNQAECggIBgABAAAAAA==.',
Cj='Cjkp:BAEANQADCgYIBgABNQAECgYICQABAAAAAA==.',
Cl='Clipdh:BAEANQAFFAEIAQAAAA==.Clippiedh:BAEANQAECgUIBgABNQAFFAEIAQABAAAAAA==.Cloudzard:BAEANQAECgQIBAABNQAFFAIIAgABAAAAAA==.Clôuds:BAEANQAFFAIIAgAAAA==.Clöver:BAEANQADCgcIDQAAAA==.',
Co='Cohvoker:BAEANQAECggIDQAAAQ==.Coldbruw:BAEANQAECggIDgAAAA==.Coqinspector:BAEANQAECgYIBgAAAA==.Covènna:BAEANQAECgcIDQAAAA==.Cowboysam:BAEANQAECgcIBAABNQAECggIBQABAAAAAA==.',
Cr='Craazyeyes:BAEANQAECgcIDAAAAA==.Crankcanon:BAEANQAECgEIAQAAAA==.Criminalx:BAEANQAECggIBQABNQAECggIBQABAAAAAA==.Crookedhand:BAEANQAECgQIBQABNQAECgcIBwABAAAAAA==.',
['Cø']='Cørmbread:BAEANQADCggIDgAAAA==.',
Da='Daevar:BAEANQAECgQIBAAAAA==.Dankscale:BAEANQAECgUIAwABNQAECggIBgABAAAAAA==.',
De='Delacour:BAEANQAFFAEIAQAAAA==.Demonpandy:BAEANQADCgYIBgABNQAECgQIBQABAAAAAA==.',
Di='Disqordant:BAEANQAECggICQAAAA==.Disqpriest:BAEANQAECgQIBAABNQAECggICQABAAAAAA==.Dixirekt:BAEANQAECgEIAQABNQAFFAEIAQABAAAAAA==.',
Dk='Dkestro:BAEANQAECggIDgAAAA==.',
Do='Domideus:BAEANQAFFAQIBAABNQAFFAUIBgAGAFwfAA==.Domidk:BAEBNQAFFIEGAAIGAAUJXB8vAADtAQWODQAAAgBQAHUNAAABAEMAfw0AAAEAYACpDQAAAQBPADMNAAABAE0ABgAFCVwfLwAA7QEFjg0AAAIAUAB1DQAAAQBDAH8NAAABAGAAqQ0AAAEATwAzDQAAAQBNAAAA.Domistarus:BAEANQADCgIIAgABNQAFFAUIBgAGAFwfAA==.Donjuán:BAEANQAECgcICQAAAA==.Dooleymain:BAEANQAECggIBgAAAA==.Doubleaamp:BAEANQADCgEIAQABNQAFFAQIBgAHAB4YAA==.Doubleape:BAEBNQAECoEPAAIIAAgJvxdKEQCRAgiODQAAAwBZAHUNAAABAAAAfw0AAAIAWgCpDQAAAgBfAFwNAAACADsAXQ0AAAIASwBlDQAAAgAyAKQNAAABABkACAAICb8XShEAkQIIjg0AAAMAWQB1DQAAAQAAAH8NAAACAFoAqQ0AAAIAXwBcDQAAAgA7AF0NAAACAEsAZQ0AAAIAMgCkDQAAAQAZAAE1AAUUBAgGAAcAHhgA.Doublêamp:BAEANQADCgEIAgABNQAFFAQIBgAHAB4YAA==.',
Dr='Drampa:BAEANQAECgUIAgABNQAECggIBgABAAAAAA==.Drineym:BAEANQAECggIBQAAAA==.Drineymonk:BAEANQAECggIBQABNQAECggIBQABAAAAAA==.Drineys:BAEANQAECggIBQABNQAECggIBQABAAAAAA==.Drineysthree:BAEANQAECggIBQABNQAECggIBQABAAAAAA==.Drjebediah:BAEANQAECggIBQABNQAECggIBQABAAAAAA==.',
Ds='Dsdk:BAEANQAECgIIAgABNQAFFAEIAQABAAAAAA==.',
Du='Duckdisco:BAEANQAECggIBgABNQAECggIBgABAAAAAA==.',
Dy='Dylqt:BAEANQAECgEIAQAAAA==.',
['Dè']='Dèmandred:BAEANQAECgYICQAAAA==.',
['Dõ']='Dõubleamp:BAEANQADCgIIAwABNQAFFAQIBgAHAB4YAA==.',
Ec='Ecodk:BAEANQAECgcIDgAAAA==.',
Ed='Eddieiwl:BAEANQAECgYICwABNQAFFAUIBgAIAFUPAA==.',
El='Elfylicious:BAEANQAECgYICQAAAA==.',
En='Endor:BAEANQAECgcIDQAAAA==.Endormu:BAEANQADCggIEAABNQAECgcIDQABAAAAAA==.Enjoylegion:BAEANQAECgEIAQABNQAECggIBQABAAAAAA==.Enzyte:BAEANQAECggIDgAAAA==.',
Er='Ericjunior:BAEBNQAFFIEGAAIJAAUJ5BwwAAD8AQWODQAAAgBjAHUNAAABAFAAqQ0AAAEAMQBcDQAAAQA7ADMNAAABAFEACQAFCeQcMAAA/AEFjg0AAAIAYwB1DQAAAQBQAKkNAAABADEAXA0AAAEAOwAzDQAAAQBRAAAA.Ericsmage:BAEANQAECgcICQABNQAFFAUIBgAJAOQcAA==.',
Fa='Faoln:BAEBNQAFFIEHAAIEAAUJbiAkAAAFAgWODQAAAgBfAHUNAAABAEQAfw0AAAEAZACpDQAAAgBgADMNAAABADcABAAFCW4gJAAABQIFjg0AAAIAXwB1DQAAAQBEAH8NAAABAGQAqQ0AAAIAYAAzDQAAAQA3AAAA.',
Fe='Felgas:BAEANQADCggICAABNQAECgYIBgABAAAAAA==.',
Fi='Firewing:BAEANQAECggIBQABNQAECggIBgABAAAAAA==.',
Fl='Flurpedm:BAEANQAECgYICAAAAA==.',
Fo='Foltysp:BAEANQADCgYIBgABNQAECgcIDQABAAAAAA==.Fossadisco:BAEANQAECggIBQABNQAECggIBgABAAAAAA==.Foxdisco:BAEANQAECggIBgABNQAECggIBgABAAAAAA==.',
Fu='Fuon:BAEANQADCggIDgAAAA==.',
Ga='Gankedurma:BAEANQADCgQIBAABNQAECgEIAQABAAAAAA==.Garyeet:BAEANQAFFAMIBAAAAA==.Garym:BAEANQAECgMIAwABNQAFFAMIBAABAAAAAA==.Garyuhyuh:BAEANQAECgcICgABNQAFFAMIBAABAAAAAA==.',
Ge='Germbrew:BAEANQAECgEIAQABNQAECgcIDAABAAAAAA==.Germpal:BAEANQAECgcIDAAAAA==.',
Gi='Gillywar:BAEANQADCgIIAgAAAA==.',
Go='Goopmother:BAEANQAECgQIBAAAAA==.Goosedisco:BAEANQAECggIBgABNQAECggIBgABAAAAAA==.Gordonfreems:BAEANQAECgcIDQAAAA==.Goudacris:BAEBNQAFFIEHAAIGAAUJVB8sAADvAQWODQAAAgBdAHUNAAABAEcAfw0AAAEANwCpDQAAAgBWADMNAAABAF0ABgAFCVQfLAAA7wEFjg0AAAIAXQB1DQAAAQBHAH8NAAABADcAqQ0AAAIAVgAzDQAAAQBdAAAA.',
Gu='Gugugugagaga:BAEANQAFFAIIAgAAAA==.Guntagg:BAEANQAECgcIDAAAAA==.',
Ha='Happymango:BAEANQAECgYICQAAAA==.Hasagixd:BAEANQAECgUICQAAAA==.Hashmaker:BAEANQAECgcICgAAAA==.',
He='Headexplode:BAEANQAECggIBQABNQAECggIBgABAAAAAA==.Hentainsfw:BAEANQADCgQIBAABNQAECgYIBgABAAAAAA==.',
Ho='Hojwarts:BAEANQAECgQIBAABNQAFFAUIBwAEAG4gAA==.Holybeni:BAEANQAECgEIAQABNQAECgcIDQABAAAAAA==.Holybruw:BAEANQADCgIIAgABNQAECggIDgABAAAAAA==.',
['Hä']='Hämmy:BAEANQADCgQIBAAAAA==.',
Il='Ileftmydad:BAEANQAECgcIEwAAAA==.',
Im='Imcookedup:BAEANQAECgcIDgAAAA==.Impecboom:BAEANQAECggIBQAAAA==.Impecotp:BAEANQAECggIBQABNQAECggIBQABAAAAAA==.',
Is='Isaaclock:BAEANQAECgcIDQAAAA==.Isaacwar:BAEANQAECgMIAwABNQAECgcIDQABAAAAAA==.',
It='Itsadethnite:BAEANQADCgQIBAABNQAFFAEIAQABAAAAAA==.Itskale:BAEANQAECgcIDAAAAA==.',
Ja='Jakenoph:BAEANQAECgYICQAAAA==.',
Je='Jebe:BAEANQAECggIBQABNQAECggIBQABAAAAAA==.Jebedíah:BAEANQAECggIBQAAAA==.Jeongjian:BAEANQAECgQIBgABNQAECgIIAgABAAAAAA==.Jetblast:BAEANQAECgEIAQABNQAECgYIBgABAAAAAA==.Jetkaos:BAEANQADCgYIBgABNQAECgYIBgABAAAAAA==.Jetzx:BAEANQAECgYIBgAAAA==.',
Ju='Jupiterboiz:BAEANQAECgMIAwABNQAFFAEIAQABAAAAAA==.',
Jy='Jyhevoker:BAEANQAECgcICwAAAA==.',
Ka='Kaenaira:BAEANQAECgMIAwAAAA==.Kamsdhunter:BAEANQADCgYIBgABNQAECgUIBgABAAAAAA==.Kamsmage:BAEANQAECgUIBgAAAA==.Kattsummi:BAEANQAECgUIBwABNQAECgcIDAABAAAAAA==.Kattsurro:BAEANQAECgcIDAAAAA==.',
Kh='Khalick:BAEANQAECgcIDQAAAA==.',
Ko='Koaladisco:BAEANQAECgYIAwABNQAECggIBgABAAAAAA==.Konvicevoker:BAEANQAFFAIIAwAAAA==.Konvicpally:BAEANQAECgMIBAABNQAFFAIIAwABAAAAAA==.Korpfel:BAEANQAECgEIAQAAAA==.Korpiklannie:BAEANQADCgUIBQABNQAECgEIAQABAAAAAA==.',
Kr='Kraigie:BAEANQAFFAEIAQAAAA==.',
Ks='Kspbozo:BAEANQAECgUIAgABNQAECggIBQABAAAAAA==.Kspeasy:BAEANQAECggIBQABNQAECggIBQABAAAAAA==.Kspfish:BAEANQAECgcIBAABNQAECggIBQABAAAAAA==.Ksploft:BAEANQAECgcIBQABNQAECggIBQABAAAAAA==.Ksptoes:BAEANQAECggIBQABNQAECggIBQABAAAAAA==.',
Ku='Kurejdiamond:BAEANQADCgcIBwABNQAECgYIBgABAAAAAA==.Kuthdk:BAEANQAECgMIBgABNQABCgQIBAABAAAAAA==.',
Ky='Kymíra:BAEANQAECgIIAgAAAA==.Kymîra:BAEANQADCgMIAwABNQAECgIIAgABAAAAAA==.',
La='Laibia:BAEANQADCgQIBgAAAA==.Lanarhoadès:BAEANQADCgYICgAAAA==.Laneloril:BAEANQAECgIIAgAAAA==.Langster:BAEANQAECgQIBQAAAA==.Largenietto:BAEANQADCggIDgABNQAFFAIIAwABAAAAAA==.Lavalerp:BAEANQAECgYICgAAAA==.',
Le='Lemurdisco:BAEANQAECggIBQABNQAECggIBgABAAAAAA==.Letaros:BAEANQAFFAEIAQAAAA==.Leyoric:BAEANQAECgEIAQAAAA==.',
Li='Lidenskap:BAEANQAECggIBQABNQAECggIBgABAAAAAA==.Likeblast:BAEANQADCgQIBAABNQAECgMIAwABAAAAAA==.Likeorange:BAEANQAECgMIAwAAAA==.Likeshock:BAEANQADCgEIAQABNQAECgMIAwABAAAAAA==.Lip:BAEANQAECggIBQABNQAECggIBgABAAAAAA==.Lippeanut:BAEANQAECgcIBAABNQAECggIBgABAAAAAA==.Lipyogurt:BAEANQAECggIBQABNQAECggIBgABAAAAAA==.',
Lu='Luxuther:BAEANQADCggICAAAAA==.Luzesis:BAEANQAECgYICAAAAA==.',
Ma='Markass:BAEBNQAFFIEGAAIKAAQJwRweAACLAQSODQAAAgBIAHUNAAABAE8AqQ0AAAIAUgBcDQAAAQA8AAoABAnBHB4AAIsBBI4NAAACAEgAdQ0AAAEATwCpDQAAAgBSAFwNAAABADwAAAA=.Martechsigil:BAEANQAECgQIBAABNQAECggIEAABAAAAAA==.Maxxedout:BAEANQAECgcICwAAAA==.',
Mc='Mcburney:BAEBNQAECoENAAQLAAkJ1BuEAwAIAQmODQAAAgBVAHUNAAACAFYAfw0AAAIARACpDQAAAgBVAFwNAAABAFkAXQ0AAAEAPQBlDQAAAQAqAKQNAAABADYAMw0AAAEAQQAHAAUJyBWpEwCNAQWODQAAAQATAHUNAAACAFYAfw0AAAEAGQCpDQAAAgBVAF0NAAABAD0ACwADCboZhAMACAEDXA0AAAEAWQBlDQAAAQAqADMNAAABAEEADAADCUwb2SgABAEDjg0AAAEAVQB/DQAAAQBEAKQNAAABADYAAAA=.Mcgrimey:BAEANQAECgcIBwAAAA==.',
Me='Mechagzilla:BAEANQAECggIDgAAAA==.Mellamolip:BAEANQAECggIBQABNQAECggIBgABAAAAAA==.Menydk:BAEANQAECggICAAAAA==.Mettasutta:BAEANQAECgYICQAAAA==.',
Mi='Mikanmagic:BAEANQADCgcIDQABNQAECggIDwABAAAAAA==.Milklizard:BAEANQAECggIDgAAAA==.Milklysmite:BAEANQADCgIIAgABNQADCgYICAABAAAAAA==.Milkycakes:BAEANQADCgYICAAAAA==.',
Mn='Mnemoan:BAEANQAECgIIAgABNQAECgcICAABAAAAAA==.',
Mo='Monstercan:BAEANQAECgcIBQAAAA==.Mordious:BAEANQAECgIIAgAAAA==.Morrowens:BAEANQAECgIIAgAAAA==.Mowens:BAEANQADCgYIBgABNQAECgIIAgABAAAAAA==.',
Mu='Mugefury:BAEANQAECgQIBQAAAA==.Mumsicle:BAEANQADCgEIAQABNQAFFAUIBgACAEkfAA==.Mumsydragon:BAEBNQAFFIEGAAICAAUJSR8zAAAHAgWODQAAAgBhAHUNAAABAD4Afw0AAAEAYQCpDQAAAQA4ADMNAAABAFYAAgAFCUkfMwAABwIFjg0AAAIAYQB1DQAAAQA+AH8NAAABAGEAqQ0AAAEAOAAzDQAAAQBWAAAA.Mumsypally:BAEANQAFFAQIBAABNQAFFAUIBgACAEkfAA==.',
['Må']='Måru:BAEANQAECgIIAgABNQAECgcIDQABAAAAAA==.',
Na='Namiya:BAEANQAECgQIBwAAAA==.Nastaskia:BAEANQADCggIDQAAAA==.Nattypandy:BAEANQAECgQIBQAAAA==.',
Ni='Nietto:BAEANQAFFAIIAwAAAA==.Niettobrew:BAEANQAECgEIAQABNQAFFAIIAwABAAAAAA==.',
No='Notkaz:BAEANQADCgUIBQAAAA==.',
Nr='Nrfgpt:BAEANQAECggIBwAAAA==.Nrfmeta:BAEANQAECgEIAQABNQAECggIBwABAAAAAA==.',
Ny='Nymba:BAEANQADCggICAABNQAFFAIIAgABAAAAAA==.Nymbazerker:BAEANQAFFAIIAgAAAA==.',
['Nî']='Nîghthûnt:BAEANQAECgQIBAAAAA==.',
Oh='Ohmrpickels:BAEANQAECgEIAQAAAA==.',
On='Onahymn:BAEANQADCgIIAgAAAA==.Onlyfriend:BAEANQAECgUIBQABNQAFFAUIBwAEAG4gAA==.',
Or='Oreodh:BAEANQAECgcIDQAAAA==.Oreow:BAEANQAECgIIAgABNQAECgcIDQABAAAAAA==.',
Ot='Otherway:BAEANQAECgEIAQABNQAECgcIBwABAAAAAA==.',
Ou='Outp:BAEANQAECggIEAAAAA==.',
Pa='Palinvoker:BAEANQAFFAIIAwAAAA==.Pallystein:BAEANQAFFAEIAQAAAA==.Pandadisco:BAEANQAECgcIBAABNQAECggIBgABAAAAAA==.Panos:BAEANQAFFAEIAQAAAA==.Paruru:BAEANQAECggIDwAAAA==.',
Pe='Peroxyl:BAEANQAFFAIIAgAAAA==.Perromalo:BAEANQADCggICAABNQAFFAUIBwAGAFQfAA==.',
Ph='Phixx:BAEANQAECgcIDQAAAA==.Phlufy:BAEANQADCggICAAAAA==.',
Pm='Pmoney:BAEANQAECgcICgAAAA==.',
Po='Porlix:BAEBNQAFFIEGAAIDAAYJJBgKAABVAgaODQAAAQBiAHUNAAABADsAfw0AAAEAIQCpDQAAAQAHAFwNAAABAFoAMw0AAAEAUQADAAYJJBgKAABVAgaODQAAAQBiAHUNAAABADsAfw0AAAEAIQCpDQAAAQAHAFwNAAABAFoAMw0AAAEAUQAAAA==.Porlixe:BAEANQAECgYICwABNQAFFAYIBgADACQYAA==.',
Pr='Promiscuity:BAEANQAECgYIBwAAAA==.',
Pt='Pterygium:BAEANQABCgQIBAABNQAECgMIBAABAAAAAA==.',
Pu='Pudgirion:BAEANQADCgUIBQABNQAECgcIBwABAAAAAA==.Pudgisimo:BAEANQADCgYIBgABNQAECgcIBwABAAAAAA==.Pudgymon:BAEANQAECgEIAQABNQAECgcIBwABAAAAAA==.',
Pw='Pwnerpriest:BAEANQAECgcIDAAAAA==.',
Py='Pylore:BAEANQADCggICAABNQAFFAEIAQABAAAAAA==.',
Qu='Quokkadisco:BAEANQAECggIBgABNQAECggIBgABAAAAAA==.',
Ra='Raandwarrior:BAEANQADCggIEAAAAA==.Rabbi:BAEANQAECgQIBAABNQAFFAUIBwAGAFQfAA==.Rachèlmaddöw:BAEANQAECgIIBAAAAA==.',
Re='Rensia:BAEANQAECgQIBQABNQAECgQIBwABAAAAAA==.',
Ri='Rillidan:BAEANQADCgcIDAABNQADCggIDgABAAAAAA==.Riple:BAEANQAECgQIBgAAAA==.Riverdev:BAEANQAFFAEIAQAAAA==.',
Ro='Rolliepoley:BAEANQAECgcIDQAAAA==.',
['Rü']='Rürü:BAEANQAFFAEIAQAAAA==.',
Sa='Sabbith:BAEANQAFFAEIAQAAAA==.Sandgoon:BAEANQAECgUICQAAAA==.Sangbeats:BAEANQAECggIBAABNQAECggIBgABAAAAAA==.Sangwing:BAEANQAECggIBgABNQAECggIBgABAAAAAA==.',
Sc='Scoochi:BAEANQAECgUIBwAAAA==.',
Se='Seanmage:BAEANQADCggICAAAAA==.Selepew:BAEANQAECgcIDQAAAA==.Sentrox:BAEANQAECgcIDQAAAA==.',
Sh='Shadowbeak:BAEANQAECggIBQABNQAECggIBgABAAAAAA==.Sharkdisco:BAEANQAECggIBgAAAA==.Shawnzdh:BAEANQADCgQIAwAAAA==.Shawnzr:BAEANQAECgcIDQABNQADCgQIAwABAAAAAA==.Shindru:BAEANQAECgMIAwAAAA==.Shlidd:BAEANQAECgYICQABNQABCgEIAQABAAAAAA==.Shotsi:BAEANQADCgcIDgABNQAECgYICQABAAAAAA==.Shotsie:BAEANQAECgYICQAAAA==.',
Si='Sillystyle:BAEANQADCggICQABNQAECgcIDQABAAAAAA==.',
Sk='Skeddosis:BAEANQAECgEIAQAAAA==.Skøg:BAEANQADCgQIAwABNQAECggIDgABAAAAAA==.',
Sl='Sloy:BAEANQADCgYIBgABNQAECgcIBwABAAAAAA==.',
Sm='Smazzoo:BAEANQAECgUIBQABNQAFFAQIBAABAAAAAQ==.Smckluvrcane:BAEANQAECgYICwAAAA==.',
So='Softpush:BAEANQAFFAEIAQAAAA==.',
Sp='Sparid:BAEANQAECgcIDQAAAA==.Spyragos:BAEANQAECgcIBAABNQAECggIBgABAAAAAA==.',
Sq='Squirtgodx:BAEANQAECgMIBAAAAA==.',
St='Stormarc:BAEANQAECgcIDAAAAA==.Stormboli:BAEANQAECgMIBAABNQAFFAUIBwAGAFQfAA==.Strongtoast:BAEANQAECgMIBAAAAA==.Stylinshaman:BAEANQAECggIDgAAAA==.',
Sw='Swampage:BAEANQAFFAEIAQAAAA==.Swegglesjr:BAEANQADCgIIAgABNQAFFAUIBgACAEkfAA==.',
Ta='Tacosaladin:BAEANQAECgIIAgAAAA==.Tamikochan:BAEANQAECggIDQAAAA==.Tamikotate:BAEANQAECgMIBQABNQAECggIDQABAAAAAA==.Tatteredpall:BAEANQAFFAEIAQAAAA==.',
Te='Teleglockb:BAEANQADCgIIAgABNQAFFAUIBgAGAFkLAA==.Telegon:BAEBNQAFFIEGAAIGAAUJWQuUAABfAQWODQAAAgAVAHUNAAABAA0Afw0AAAEANgCpDQAAAQAEADMNAAABADQABgAFCVkLlAAAXwEFjg0AAAIAFQB1DQAAAQANAH8NAAABADYAqQ0AAAEABAAzDQAAAQA0AAAA.Telegonw:BAEANQADCgcIBwABNQAFFAUIBgAGAFkLAA==.Terriscaly:BAEANQAECggIDwAAAA==.Terrish:BAEANQADCgYIBgABNQAECggIDwABAAAAAA==.Tetrå:BAEANQAFFAIIAgAAAA==.',
Th='Thawdknight:BAEANQADCgYIBgABNQAECgcIDQABAAAAAA==.Thawdwar:BAEANQAECgEIAQABNQAECgcIDQABAAAAAA==.Thdlocka:BAEANQAECgcIBAABNQAECggIBQABAAAAAA==.Thdlockb:BAEANQAECggIBQABNQAECggIBQABAAAAAA==.Thdlocki:BAEANQAECggIBQABNQAECggIBQABAAAAAA==.Thdlockk:BAEANQAECggIBQABNQAECggIBQABAAAAAA==.Thdlockl:BAEANQAECggIBQABNQAECggIBQABAAAAAA==.Thdlockn:BAEANQAECggIBQABNQAECggIBQABAAAAAA==.Thdlockq:BAEANQAECggIBQAAAA==.Thdlockt:BAEANQAECggIBQABNQAECggIBQABAAAAAA==.Thdlocku:BAEANQAECggIBQABNQAECggIBQABAAAAAA==.Thelwynn:BAEANQAECgEIAQAAAA==.',
To='Toateem:BAEANQAECggICgABNQABCgQIBAABAAAAAA==.Tonkabrew:BAEANQADCgIIAgABNQAECgcIDAABAAAAAA==.Toomuchpower:BAEANQAECgYIBgAAAA==.Torchiblink:BAEANQAECgQIBwABNQAECgQIBAABAAAAAA==.Tossintides:BAEANQADCgcIDQAAAA==.Totalidiot:BAEANQAECggIBgAAAA==.Toucandisco:BAEANQAECggIBgABNQAECggIBgABAAAAAA==.',
Tr='Trevorstrnad:BAEANQAECgEIAQAAAA==.Trillpassion:BAEANQAECggIBQABNQAECggIBQABAAAAAA==.Trilltime:BAEANQAECggIBQABNQAECggIBQABAAAAAA==.Trillvoid:BAEANQAECggIBQABNQAECggIBQABAAAAAA==.Trillwar:BAEANQAECggIBQABNQAECggIBQABAAAAAA==.Trillww:BAEANQAECggIBQAAAA==.Trogyndh:BAEANQAFFAQIBAAAAA==.Trogyndk:BAEANQAECgYICQABNQAFFAQIBAABAAAAAA==.Truefirexd:BAEANQADCgQIBAAAAA==.',
Ts='Tsumommy:BAEANQADCggIEAAAAA==.',
Un='Unbounddeath:BAEANQAFFAEIAQAAAA==.',
Va='Vanzman:BAEANQAECgcIBwAAAA==.Vaporkicks:BAEANQAECgcIDAAAAA==.',
Ve='Vendiktiv:BAEANQAECgYIBgAAAA==.Veìl:BAEANQAECgUIBQAAAA==.',
Vi='Viridia:BAEANQAECgcIBAABNQAECggIBgABAAAAAA==.',
Vo='Voidzoon:BAEANQADCgcIBwAAAA==.Vondglaive:BAEANQAECgQIBQAAAA==.',
Vu='Vuduo:BAEANQAECgEIAgABNQABCgIIAgABAAAAAA==.',
Wa='Waffietv:BAEANQAECggIBwAAAA==.Waffledemon:BAEANQAFFAIIAgAAAA==.Wallifexe:BAEANQAECggIBgAAAA==.',
We='Weenusmobile:BAEANQAFFAEIAgAAAA==.',
Wh='Whiskerstein:BAEANQADCgEIAQABNQAECggIDAABAAAAAA==.Whitebread:BAEANQADCggICAABNQAECgQIBAABAAAAAA==.',
Wi='Wideweenus:BAEANQADCgIIAgABNQAFFAEIAgABAAAAAA==.Wildtotes:BAEANQAECgYICQAAAA==.',
Ww='Wwarble:BAEANQADCgUIBgAAAA==.',
Xe='Xesevy:BAEANQAECgcIBAAAAA==.',
Xw='Xwaterd:BAEANQADCggIBwAAAA==.',
Xy='Xyebeam:BAEANQAECggICgABNQAFFAUIBgAMAOgUAA==.',
Yo='Youaugtist:BAEANQAECgQICAABNQAFFAIIAgABAAAAAA==.',
Yv='Yvairel:BAEANQAECgcICwAAAA==.',
Yz='Yzao:BAEANQAFFAEIAQAAAA==.',
Za='Zachbeshady:BAEANQAECgYICwABNQABCgQIBgABAAAAAA==.Zajuiruh:BAEANQAFFAEIAQAAAA==.Zalhalla:BAEANQAECgYIBgAAAA==.Zalshibou:BAEANQAECgQIBAABNQAECgYIBgABAAAAAA==.Zapdos:BAEANQAECggIBgAAAA==.',
Zb='Zbeans:BAEANQAECgUIBwAAAA==.',
Ze='Zebradisco:BAEANQAECgcIBAABNQAECggIBgABAAAAAA==.Zeebroo:BAEANQAECgMIBQABNQAFFAEIAQABAAAAAA==.Zeedrick:BAEANQAFFAEIAQAAAA==.Zenben:BAEBNQAECoEQAAINAAkJ0yLiBABnAwmODQAAAgBbAHUNAAACAGIAfw0AAAIAYACpDQAAAgBAAFwNAAACAFkAXQ0AAAIATABlDQAAAQBfAKQNAAABAFwAMw0AAAIAYQANAAkJ0yLiBABnAwmODQAAAgBbAHUNAAACAGIAfw0AAAIAYACpDQAAAgBAAFwNAAACAFkAXQ0AAAIATABlDQAAAQBfAKQNAAABAFwAMw0AAAIAYQAAAA==.',
Zo='Zolden:BAEANQAECgYICQABNQAECgcICAABAAAAAA==.Zoldin:BAEANQAECgcICAAAAA==.Zorannder:BAEANQADCggIDgAAAA==.Zorró:BAEANQADCgUIBQAAAA==.',
['Ðo']='Ðoubleamp:BAEBNQAFFIEGAAMHAAQJHhg3AAAsAQSODQAAAgBbAHUNAAABAEAAqQ0AAAIAUAAzDQAAAQAKAAcAAwnAHjcAACwBA44NAAACAFsAdQ0AAAEAQACpDQAAAgBQAAsAAQk3BMsAAEwAATMNAAABAAoAAAA=.',
['Óm']='Ómar:BAEANQAFFAEIAQABNQAFFAQIBgAKAMEcAA==.',
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
