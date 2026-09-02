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
local provider = {region='US',realm='Whisperwind',name='US',type='weekly',zone=53,date='2026-09-01',data={Ab='Abernith:BAAANQADCgIIAwAAAA==.Abmi:BAAANQAECgcICwAAAA==.',
Ad='Adahlinas:BAAANQAECgEIAQAAAA==.Adarannia:BAAANQADCgMIBAAAAA==.Aderosa:BAAANQADCgMIAwABNQADCgYICAABAAAAAA==.Adex:BAAANQAECgEIAQAAAA==.Adiase:BAAANQADCgcIDAAAAA==.Adosdruid:BAAANQADCgYIBgAAAA==.',
Ae='Aelena:BAAANQAECgEIAQAAAA==.Aemondson:BAAANQAECgQIBAAAAA==.Aennirel:BAAANQADCgEIAQAAAA==.Aeroch:BAAANQAECgYICAAAAA==.Aerodon:BAAANQADCgUIBgABNQAECgEIAQABAAAAAA==.Aerowynne:BAAANQADCgIIAgAAAA==.Aezeras:BAAANQADCgMIBQAAAA==.',
Ah='Ahmreah:BAAANQADCgUIBwAAAA==.',
Aj='Aj:BAAANQAECgcICwAAAA==.',
Ak='Akimandia:BAAANQAECgIIAgAAAA==.Akinira:BAEANQAECgMIBAAAAA==.Akronite:BAAANQADCgcIDQAAAA==.',
Al='Alamoor:BAAANQAECgEIAQAAAA==.Alandien:BAAANQADCgcIDAAAAA==.Alcar:BAAANQAECgEIAQAAAA==.Aldorite:BAAANQAECgYICAAAAA==.Alethus:BAAANQADCgQIBAABNQADCgcIDAABAAAAAA==.Alexandreth:BAAANQABCgEIAQAAAA==.Alexeas:BAAANQADCgcIDQAAAA==.Alexinux:BAAANQADCggIDgAAAA==.Alsneak:BAAANQAECgUIBAAAAA==.Alteredshock:BAAANQADCgEIAQAAAA==.Alyshamanele:BAAANQADCgcIBwAAAA==.Alyxz:BAAANQAECgEIAQAAAA==.',
Am='Amareth:BAAANQAECgEIAQAAAA==.Ambuscade:BAAANQADCgYICgAAAA==.Amelrik:BAEANQAECgcIDQAAAA==.Amirä:BAAANQAECgMIAwAAAA==.Ammonkguy:BAAANQADCgMIBAABNQAECgEIAQABAAAAAA==.Amooncrima:BAAANQAECgEIAQAAAA==.Ampharosite:BAAANQADCgEIAQABNQAECgcICwABAAAAAA==.',
An='Anchalon:BAAANQADCgUIBgAAAA==.Angerpaw:BAAANQAECgcICwAAAA==.Anhurst:BAAANQADCgYICwAAAA==.Annikkin:BAAANQADCgUIBQAAAA==.Anoon:BAAANQAECgQIBAAAAA==.Ansys:BAEANQAECgYICAAAAA==.Anubis:BAAANQADCgcIDQAAAA==.Anìmalmother:BAAANQADCgMIAwAAAA==.',
Ap='Aperthir:BAAANQADCgEIAQAAAA==.Aphrodittes:BAAANQADCgcIBwAAAA==.Apocalypto:BAAANQADCgMIAwAAAA==.Apøc:BAAANQADCgYICwAAAA==.',
Ar='Archaelus:BAAANQADCgUICgAAAA==.Archevil:BAAANQAECgEIAQAAAA==.Arctichail:BAAANQAECgYICAAAAA==.Ardent:BAAANQAECgMIBAAAAA==.Ares:BAAANQADCgEIAQAAAA==.Aretreja:BAAANQAECgEIAQAAAA==.Arramin:BAAANQADCgUIBQAAAQ==.Arries:BAEANQADCggIDwAAAA==.Arsis:BAAANQAECgYICAAAAA==.Arthricia:BAAANQADCgcIDQAAAA==.Artspriest:BAAANQAECgIIAgAAAA==.Aryii:BAAANQADCgMIBAAAAA==.',
As='Asamelth:BAAANQADCggIDgAAAA==.Asguard:BAAANQAECgIIAgAAAA==.Astoropterix:BAAANQADCgQIBQAAAA==.Astu:BAAANQADCgMIBQAAAA==.',
At='Athy:BAAANQADCgcIDAAAAA==.Atreida:BAAANQAECgEIAQAAAA==.',
Au='Aurana:BAAANQADCgQIBAAAAA==.Auriok:BAAANQADCgcIDQAAAA==.Auriya:BAAANQADCgMIBQAAAA==.Auzua:BAAANQADCggIDwAAAA==.',
Av='Averianna:BAAANQADCgcIDAAAAA==.Avess:BAAANQADCgQIBAAAAA==.',
Aw='Awekah:BAAANQAECgIIAgAAAA==.',
Az='Azleah:BAAANQAECgcIDQAAAA==.Azorthas:BAEANQADCgcIDwAAAA==.',
Ba='Babygdhunt:BAAANQADCgYIDAAAAA==.Baconlock:BAAANQAECgMIBAABNQAECgYIDAABAAAAAA==.Badragon:BAAANQAECgcICwAAAA==.Badunter:BAAANQADCgYIBgAAAA==.Balleont:BAAANQADCggIDgAAAA==.Banagar:BAAANQADCgYIDAAAAA==.Banotesa:BAAANQADCgMIAwAAAA==.Barbelle:BAAANQAECgMIAwAAAA==.Basdia:BAAANQADCgcIDgAAAA==.',
Be='Beakin:BAAANQADCgcIDQAAAA==.Bedpan:BAAANQABCgMIAwABNQADCgYIBgABAAAAAA==.Beefdip:BAAANQADCggICwAAAA==.Beenekromant:BAAANQADCgYICwAAAA==.Beenjii:BAAANQAECgQIBQAAAA==.Behrak:BAAANQABCgMIAwAAAA==.Beletrix:BAAANQABCgQIAgAAAA==.Belgaroth:BAAANQADCgYICwAAAA==.Belker:BAAANQADCgYICwAAAA==.Belleta:BAAANQADCgUIBwAAAA==.Beniniah:BAAANQAECgcICwAAAA==.Berelaine:BAAANQADCgEIAQAAAA==.Beringthree:BAAANQAECgcICwAAAA==.Berthon:BAAANQADCgQICAAAAA==.Betaraybill:BAAANQADCgUIBwAAAA==.',
Bi='Biermon:BAAANQADCgYIBgAAAA==.Biertoladin:BAAANQADCgYIBgAAAA==.Bigchest:BAAANQADCgYIBwAAAA==.Bigfishy:BAAANQAECgcICwAAAA==.Biggins:BAAANQADCggIDwAAAA==.Bikini:BAAANQADCggIDwAAAA==.Bilpaladin:BAAANQADCgYICwAAAA==.Biqqi:BAAANQADCgUICAAAAA==.Birdboy:BAAANQAECgIIAgAAAA==.Bitfu:BAAANQADCgcIBwAAAA==.',
Bl='Blackpurple:BAAANQADCggICAAAAA==.Bladefall:BAAANQADCggIDQABNQABCgIIAgABAAAAAA==.Blademane:BAAANQADCgcIBwAAAA==.Blanch:BAAANQAECgEIAQAAAA==.Bloc:BAAANQAECgIIAgAAAA==.Blondragoon:BAAANQADCgcIBwABNQAECgcIDAABAAAAAA==.Blueshark:BAAANQADCgMIAwABNQADCgcIDgABAAAAAA==.Bluesknight:BAAANQAECgQIBQAAAA==.',
Bm='Bmn:BAAANQADCgIIAgAAAA==.',
Bo='Bobfilthy:BAAANQADCgYIBgAAAA==.Bodypillow:BAAANQAECgUIBQAAAA==.Bodytype:BAAANQADCgYIBgAAAA==.Bojanglz:BAAANQADCgMIAwAAAA==.Bolvasaur:BAAANQADCgcIBwAAAA==.Bonanza:BAAANQADCgYICwAAAA==.Bonitamuerte:BAAANQADCgYICwAAAA==.Bonës:BAAANQAECgEIAQAAAA==.Boomboombang:BAAANQAECgYICQAAAA==.Boozìn:BAAANQADCgcIDQAAAA==.Bordock:BAAANQADCgEIAQAAAA==.Boricc:BAAANQAECgEIAQAAAA==.Bowbow:BAAANQADCgUIBwAAAA==.Boykisser:BAAANQADCgQIBAAAAA==.',
Br='Bragaul:BAAANQAECgcICQAAAA==.Bragnar:BAAANQADCggICAAAAA==.Branch:BAAANQADCgQIBAAAAA==.Brandodin:BAAANQADCgcIBwAAAA==.Brewadin:BAAANQADCggIDgAAAA==.Brewdragon:BAAANQAECgIIAgAAAA==.Briarclaw:BAAANQADCgYICwAAAA==.Brightlockk:BAAANQADCgcIDQAAAA==.Brotherbear:BAAANQADCgMIBQAAAA==.Brotherodd:BAAANQABCgIIAgAAAA==.Bruceflee:BAAANQADCgQIBAAAAA==.Brynstormr:BAAANQADCgUIBwAAAA==.',
Bu='Bubblecream:BAAANQADCgQIBgAAAA==.Budsdeath:BAAANQAECgYICwAAAA==.Bufflock:BAAANQADCgMIAwAAAA==.Bulen:BAAANQADCgIIAgAAAA==.',
By='Byiak:BAAANQADCgcICwAAAA==.',
['Bê']='Bêêfstick:BAAANQADCgEIAQAAAA==.',
['Bó']='Bób:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.',
Ca='Caddylucifer:BAAANQAECgQIBAAAAA==.Caillte:BAAANQADCgMIBQAAAA==.Caldormu:BAAANQADCggIDQAAAA==.Caleé:BAAANQADCggIDwAAAA==.Callicia:BAAANQAECgIIAgAAAA==.Calypie:BAAANQAECgEIAQAAAA==.Camlostiae:BAAANQADCggIDQAAAA==.Canolgon:BAAANQAECgIIAgAAAA==.Canthia:BAAANQADCggIDgAAAA==.Capncrunch:BAAANQADCgMIBQAAAA==.Caprock:BAAANQADCgcIDAAAAA==.Capymage:BAAANQAECgEIAQABNQAECgYICgABAAAAAA==.Capywarr:BAAANQAECgYICgAAAA==.Cassima:BAAANQAECgEIAQAAAA==.Catharin:BAAANQADCgIIAgAAAA==.Catjam:BAAANQADCgEIAQAAAA==.Cattibreezze:BAAANQADCgQIBwAAAA==.Cawnar:BAAANQADCgQICAAAAA==.',
Ce='Cediar:BAAANQADCggIEAAAAA==.Celandius:BAAANQAECgEIAQAAAA==.Celaphalopod:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Celathorís:BAAANQAECgEIAQAAAA==.Celeste:BAAANQADCgcICwAAAA==.Cenecia:BAAANQAECgEIAQAAAA==.',
Ch='Chaddilock:BAAANQAECgEIAQAAAA==.Chaimee:BAAANQAECgYICAAAAA==.Chaoticshamm:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Chapters:BAAANQADCgQIBAAAAA==.Chebangbang:BAAANQADCgUIBwAAAA==.Cheekytiki:BAAANQAECgIIAgAAAA==.Cheesewizz:BAAANQADCggIDgAAAA==.Cheeze:BAAANQADCgMIBAAAAA==.Chelsarda:BAAANQAECgcIDAAAAA==.Chenohai:BAAANQAECgEIAQAAAA==.Cheracuda:BAAANQADCgYIBgAAAA==.Cherisê:BAAANQADCgcIDAAAAA==.Chessie:BAAANQADCgYICwAAAA==.Chestercheto:BAAANQADCggICAAAAA==.Chillivibes:BAAANQAECgcIDQAAAA==.Choal:BAAANQAECgEIAQAAAA==.Chogalbuu:BAAANQADCgcICwAAAA==.Chopaa:BAAANQADCgYIBwAAAA==.Chronostrasz:BAAANQADCggIDwAAAA==.Chubhub:BAAANQAECgEIAQAAAA==.',
Ci='Ciante:BAAANQAECggIDgAAAA==.Cindara:BAAANQAECgEIAQAAAA==.Cinderazenot:BAAANQAECgIIAgAAAA==.Cinderwyn:BAAANQADCgQIBwAAAA==.Cirene:BAAANQAECgEIAQAAAA==.',
Cl='Clapmycheeks:BAAANQADCgMIAwAAAA==.Clapprcob:BAAANQADCgMIBAAAAA==.Clei:BAAANQAECgQIBAABNQAECgYICAABAAAAAA==.Cleopet:BAAANQADCgEIAQAAAA==.Clerrick:BAAANQADCgcIDgAAAA==.Clexise:BAAANQAECgYIBwAAAA==.Clownmilkie:BAAANQADCgYIBgABNQAECgcICwABAAAAAA==.Clutchcake:BAAANQAECgYICQAAAA==.Clutchpal:BAAANQADCgIIAgABNQADCgQIBAABAAAAAA==.',
Co='Comac:BAAANQAECgEIAQAAAA==.Coopdaloop:BAAANQADCgcIDQAAAA==.Copelin:BAAANQAECgEIAQAAAA==.Coreylock:BAAANQAECgYICwAAAA==.Cornputer:BAAANQADCggIDwAAAA==.',
Cp='Cptarcano:BAAANQADCggIDgAAAA==.',
Cr='Crashingvoid:BAAANQADCgQIBgAAAA==.Creacher:BAAANQADCgQIBAAAAA==.Crelix:BAAANQADCgQIBAAAAA==.Crescendo:BAAANQADCgUICAAAAA==.Cresencia:BAAANQAFFAMIAwAAAA==.Creservation:BAAANQAFFAEIAQAAAA==.Crestoration:BAAANQAECgIIAgAAAA==.Cret:BAAANQADCgcIDQAAAA==.Crimsoneye:BAAANQADCgYIBgAAAA==.Crimsonrosé:BAAANQADCggIDwAAAA==.',
Cu='Curbi:BAAANQADCgcIBwAAAA==.Cursedd:BAAANQADCgYIDAAAAA==.',
Cy='Cynderash:BAAANQADCgUIBwAAAA==.Cyndvia:BAAANQADCgUIBQAAAA==.',
['Cä']='Cätrÿnae:BAAANQADCgcIDgAAAA==.',
['Có']='Cóuch:BAAANQADCgcICgAAAA==.',
Da='Dachopper:BAAANQAECgIIAgAAAA==.Daedrak:BAAANQAECgYICAAAAA==.Damase:BAAANQADCggIDgAAAA==.Damasen:BAAANQADCgYICgAAAA==.Dantioch:BAAANQAECgIIAgAAAA==.Daphni:BAAANQADCgUIBQAAAA==.Darckmage:BAAANQAECgEIAQAAAA==.Dardelindor:BAAANQADCgUIBQAAAA==.Darkenda:BAAANQAECgEIAQAAAA==.Darkpenance:BAAANQABCgQIBAAAAA==.Darkruneses:BAAANQAECgQIBQAAAA==.Darkwarden:BAAANQADCgcIDgAAAA==.Darkwisdom:BAAANQADCgYIDAAAAA==.Dartford:BAAANQADCgYIBgAAAA==.Dawnbreaker:BAAANQADCgQIBAAAAA==.',
Dd='Ddog:BAAANQADCgQIBgAAAA==.',
De='Deadris:BAAANQADCgIIAgABNQADCgUIBwABAAAAAA==.Deathbuds:BAAANQAFFAIIAgAAAA==.Deathsdance:BAAANQAECgEIAQAAAA==.Deathspecta:BAAANQAECgIIAgAAAA==.Deathtickles:BAAANQADCgYICgAAAA==.Deathzero:BAAANQADCggICQAAAA==.Decora:BAAANQADCgUIBQAAAA==.Deekayray:BAAANQADCgQIBAAAAA==.Deemonray:BAAANQADCgQIBAAAAA==.Deer:BAAANQAFFAMIAwAAAA==.Deftx:BAAANQAFFAMIBAAAAA==.Deltoramasta:BAAANQAFFAMIBAAAAA==.Demaddotter:BAAANQADCgcICQAAAA==.Demeric:BAAANQADCgMIBAAAAA==.Demiria:BAAANQADCggIDQAAAA==.Demonclutch:BAAANQADCgQIBAAAAA==.Demondiablo:BAAANQADCgUIBgAAAA==.Demteddies:BAAANQADCgQIBgAAAA==.Derpherper:BAAANQADCggIDwAAAA==.Deselation:BAAANQADCggICAAAAA==.Dethbringr:BAAANQAECgEIAQAAAA==.Devilldog:BAAANQADCggIDwAAAA==.Devilshale:BAAANQAECgIIAgAAAA==.Dezardondor:BAAANQAECgMIBAAAAA==.',
Di='Dienetta:BAAANQAECggICAAAAA==.Dirkens:BAAANQAECgIIAgAAAA==.Disapointing:BAAANQADCgcIDAAAAA==.Ditini:BAAANQADCggIDQAAAA==.',
Dk='Dkata:BAAANQAECgEIAQAAAA==.',
Dm='Dmalf:BAAANQAFFAIIAgAAAA==.Dmalfthree:BAAANQAECgYICAAAAA==.',
Dn='Dnice:BAAANQAECgIIAgAAAA==.',
Do='Dorkstar:BAAANQAECgcICwAAAA==.Dorlondo:BAAANQADCgMIBQABNQADCgcIDgABAAAAAA==.Dorriel:BAAANQADCgUIBwAAAA==.Doup:BAAANQAECgQIBQAAAA==.Doveknight:BAAANQAECgcIDgAAAA==.Dowal:BAAANQAECgcICwAAAQ==.Dozar:BAAANQAECgMIAwAAAA==.',
Dr='Dragonrey:BAAANQAECgEIAQAAAA==.Dragonton:BAEANQAECgcICwAAAA==.Drakaury:BAAANQADCggIDgABNQAECgMIAwABAAAAAA==.Drays:BAAANQADCgQIBAAAAA==.Drbean:BAAANQADCgYICwAAAA==.Dreåm:BAAANQADCgYIDAAAAA==.Drgndeeznuts:BAAANQADCggICQAAAA==.Drhynno:BAAANQAECgcIDAAAAA==.Drshockër:BAAANQADCgYICwAAAA==.Drwho:BAAANQAECgEIAQAAAA==.',
Du='Duderocker:BAAANQAECgcIDAAAAA==.Duhstorm:BAAANQADCgYIBgAAAA==.Dulapeep:BAAANQADCgYIBgAAAA==.Dumond:BAAANQAECgIIAgAAAA==.Dunkdiving:BAAANQAECgQIBAAAAA==.Dunkelplex:BAAANQADCgYICwAAAA==.Duttio:BAAANQADCgEIAQAAAA==.Dutts:BAAANQADCgYIDAAAAA==.Duzell:BAAANQADCgEIAQAAAA==.',
Ec='Eckis:BAAANQAECgEIAQAAAA==.',
Ee='Ee:BAAANQADCgUICAAAAA==.Eelos:BAAANQAECgEIAQAAAA==.',
Eg='Egregious:BAAANQADCgEIAQAAAA==.',
Ei='Eidon:BAAANQADCgMIBAAAAA==.',
El='Elaahla:BAAANQAECgEIAQAAAA==.Elderin:BAAANQAECgEIAQAAAA==.Eldin:BAAANQAECgEIAQAAAA==.Elegiacal:BAAANQADCgEIAQABNQADCgYICwABAAAAAA==.Elenarae:BAAANQAECgIIAgAAAA==.Elissareh:BAAANQAECgEIAQABNQAECgcIDQABAAAAAA==.Elsenor:BAAANQADCgYIBwAAAA==.Elunie:BAAANQAECgEIAQAAAA==.Elwynne:BAAANQADCgYIBgAAAA==.',
Em='Emberosia:BAAANQADCgYIBgAAAA==.',
En='Enigmatic:BAAANQADCggIDgAAAA==.',
Ep='Epicgirlhero:BAAANQAECgYICgAAAA==.Epicheroine:BAAANQAECgcIDQABNQAECgYICgABAAAAAA==.Epirate:BAAANQAFFAMIBAAAAA==.',
Er='Erelyda:BAAANQADCgcICAAAAA==.Eriic:BAAANQADCggIDwAAAA==.Erumak:BAAANQADCgYICgAAAA==.',
Ev='Eveth:BAAANQADCgcIDQAAAA==.Evierlena:BAAANQADCgQIBgAAAA==.Eviliciøus:BAAANQAECgIIAgAAAA==.Evilorc:BAAANQADCgMIAwAAAA==.',
Ex='Exergymage:BAAANQAECgIIAgAAAA==.',
Ez='Ezye:BAAANQADCgcIBwAAAA==.',
Fa='Facépalm:BAAANQADCgIIAgABNQAECgQIBQABAAAAAA==.Fadalaurance:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.Faedryth:BAAANQADCgUICQAAAA==.Fairalicious:BAAANQADCgQIBwAAAA==.Fairladyz:BAAANQADCgcICAAAAA==.Falcygos:BAAANQADCgUIBQAAAA==.Falstad:BAAANQADCgYICgAAAA==.Fathdh:BAAANQAFFAMIBAAAAA==.Fatniss:BAAANQADCgEIAQAAAA==.',
Fe='Fektt:BAAANQADCgUIBQAAAA==.Fells:BAAANQAECgMIBAAAAA==.Felmungandr:BAAANQAECgEIAgAAAA==.Felstone:BAAANQADCgMIBAAAAA==.Feníxx:BAAANQAECgQIBAAAAA==.Ferelyse:BAAANQADCggICAAAAA==.Fezim:BAAANQADCggIDQAAAA==.',
Fi='Fionnavhair:BAAANQADCgcIBwAAAA==.Firecrusader:BAAANQADCgYICgAAAA==.Fistermcghee:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.Fixedchance:BAAANQADCgEIAQAAAA==.',
Fl='Flameclaw:BAAANQADCgMIAwAAAA==.Flatulentone:BAAANQADCgQIBQAAAA==.Flidalyeth:BAAANQADCggIDwAAAA==.Floofyreg:BAAANQAECgcICwAAAA==.Flybynight:BAAANQAECgUIBgAAAA==.',
Fo='Fogoldin:BAAANQADCgUIBQAAAA==.Fourtwinke:BAAANQADCggIDwAAAA==.Foxcat:BAAANQADCgcIDgAAAA==.Foxykitten:BAAANQADCgIIAgABNQADCgQIBAABAAAAAA==.',
Fr='Freezeorburn:BAAANQADCggICQAAAA==.Fryhunter:BAAANQADCgMIAwABNQADCgcICQABAAAAAA==.Frymeareaver:BAAANQADCgcICQAAAA==.Frôstyz:BAAANQADCggICwAAAA==.',
Fu='Fublizz:BAAANQADCgMIBQAAAA==.Fullbuster:BAAANQADCggIDAAAAA==.Fumious:BAAANQADCgYICAAAAA==.Fundus:BAAANQAECgcICwAAAA==.Fupachalupa:BAAANQADCggIDAAAAA==.Furrosty:BAAANQADCgcIBwAAAA==.Furrplay:BAAANQADCgUIBgAAAA==.',
Ga='Galahad:BAAANQADCgYIDAAAAA==.Galaxxy:BAAANQAECgEIAQAAAA==.Ganathros:BAAANQAECgIIAgAAAA==.Ganzolo:BAAANQADCggICwAAAA==.Garaga:BAAANQADCggIDwAAAA==.Garalivey:BAAANQADCgcIDQAAAA==.Garutas:BAAANQADCggICAAAAA==.Gavrack:BAAANQAECgMIBAAAAA==.',
Ge='Geirrod:BAAANQADCgcIDAAAAA==.Geißelseher:BAAANQAECgEIAQAAAA==.Genevirerosa:BAAANQAECgEIAQAAAA==.Gerenos:BAAANQADCgYICgABNQADCgYIDAABAAAAAA==.Gettinlucky:BAAANQADCgcIDgAAAA==.',
Gh='Ghìs:BAAANQADCgEIAQABNQAFFAEIAQABAAAAAA==.',
Gi='Gisëla:BAAANQADCgYICwAAAA==.',
Gl='Glizzylizard:BAAANQADCgcIDQAAAA==.Gloopi:BAAANQADCgEIAQAAAA==.',
Gn='Gnas:BAAANQAFFAMIBAAAAA==.Gnometzu:BAAANQAECgIIAgAAAA==.',
Go='Goldmage:BAAANQADCggIBQAAAA==.Goldmaiden:BAAANQADCgMIBQAAAA==.Gothrogue:BAAANQAECgMIAwABNQAECgcIDAABAAAAAA==.',
Gr='Gramcraker:BAAANQADCgYIBgAAAA==.Gramz:BAAANQAFFAIIAgAAAA==.Grandidierit:BAAANQADCgcIDQAAAA==.Grandyded:BAAANQADCggIDQAAAA==.Greenweaver:BAAANQADCgcIDgAAAA==.Grglgrgl:BAAANQAECgIIAgABNQAECgcIDgABAAAAAA==.Grootleaf:BAAANQABCgIIAgAAAA==.Groudon:BAAANQADCgcIDQAAAA==.Grumpymage:BAAANQADCgcIBwAAAA==.',
Gu='Guenter:BAAANQADCggIAwAAAA==.Gunnèr:BAAANQADCgYIDwAAAA==.',
Gy='Gyattguard:BAAANQAECgQIBgAAAA==.',
Ha='Haat:BAAANQADCgYICQAAAA==.Halp:BAAANQADCgcICgAAAA==.Hanari:BAAANQAECgMIAwAAAA==.Hannalieh:BAAANQADCgcIDQAAAA==.Happs:BAAANQAECgcICwAAAA==.Harvonice:BAAANQAECgIIAgABNQAECgYIBwABAAAAAA==.',
He='Heallzzs:BAAANQADCggICwAAAA==.Hekah:BAAANQAECgQIBAAAAA==.Helianna:BAAANQAECgEIAQAAAA==.Herbitarian:BAAANQADCgIIAgAAAA==.Hexiboo:BAAANQAECgEIAQAAAA==.',
Hi='Hibbin:BAAANQADCgEIAQAAAA==.Highjinks:BAAANQADCgcIEQAAAA==.',
Ho='Hobohh:BAAANQADCgQIBwAAAA==.Hogmage:BAAANQADCgYIBgAAAA==.Hogmeat:BAAANQAECgMIAwAAAA==.Hollowpizza:BAAANQADCgcIBwABNQAECgcICwABAAAAAA==.Homy:BAAANQADCgYIBwAAAA==.Honeylily:BAAANQAFFAMIBAAAAA==.Honeystack:BAAANQADCgQIBAAAAA==.Honorius:BAAANQAECgEIAQAAAQ==.Hoofpunch:BAAANQADCgEIAQAAAA==.Hotbloodead:BAAANQAECgEIAQAAAA==.Hotsalot:BAAANQADCgIIAgABNQADCgUIBgABAAAAAA==.',
Hu='Huffle:BAAANQADCgUIBQAAAA==.Huhn:BAAANQADCggICgAAAA==.',
Hy='Hygeiah:BAAANQAFFAMIBAAAAA==.Hygeiahh:BAAANQAECgIIAgABNQAFFAMIBAABAAAAAA==.',
['Hé']='Héxx:BAAANQADCggIDgAAAA==.',
Ic='Icebearz:BAAANQADCgEIAQAAAA==.Icemonk:BAAANQADCgYICAAAAA==.Iceweasel:BAAANQAECgIIAgAAAA==.Ichinobu:BAAANQAECgIIAgAAAA==.Icyboy:BAAANQAECgEIAQAAAA==.Icypick:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.',
Ii='Iinaa:BAAANQADCggIDQAAAA==.',
Ik='Ikor:BAAANQADCgYIBgAAAA==.',
Il='Ilneval:BAAANQABCgEIAQAAAA==.Iludiin:BAAANQABCgIIAgAAAA==.Ilus:BAAANQADCgYIBgAAAA==.',
Im='Imogenn:BAAANQADCgUICQAAAA==.',
In='Indigostorm:BAAANQADCgEIAQAAAA==.Inexa:BAAANQADCggICAAAAA==.Infynite:BAAANQADCgUICAAAAA==.Inspriration:BAAANQADCgYIBgAAAA==.Insuendov:BAAANQAECgQIBwAAAA==.Invisibae:BAAANQAECgQIBAAAAA==.',
Ir='Ironcask:BAAANQAECgUIBQAAAQ==.',
Is='Isabelle:BAAANQADCggIDQAAAA==.Isy:BAAANQADCggIDwAAAA==.Iszari:BAAANQAECgQIBQAAAA==.',
Iv='Ivorye:BAAANQADCgQIBwAAAA==.',
Ja='Jackyjack:BAAANQADCgEIAQAAAA==.Jackyshamz:BAAANQAECgEIAQAAAA==.Jammanjake:BAAANQADCgUIBQABNQAECgIIAgABAAAAAQ==.Jaspadin:BAAANQAECgcICwAAAA==.Jasperjade:BAAANQADCgMIBAAAAA==.Jaymanjyden:BAAANQADCgcIBwAAAA==.',
Je='Jekkyll:BAAANQAECgEIAQAAAA==.Jekylle:BAAANQADCgQIBgAAAA==.Jerichacane:BAAANQADCgYIBwAAAA==.Jesùs:BAAANQADCgUIBgAAAA==.Jetpacks:BAAANQADCgcIDAAAAA==.Jetsura:BAAANQADCgUIBQAAAA==.',
Ji='Jihye:BAAANQADCgUIBQAAAA==.',
Jo='Joehealz:BAAANQAECgEIAQAAAA==.Joeydiaz:BAAANQADCgcIBwAAAA==.Jollyballs:BAAANQAECgIIAgAAAA==.',
Ju='Judgment:BAAANQADCggIDwAAAA==.Junpei:BAAANQADCggICAABNQAECgcIDAABAAAAAA==.',
Ka='Kaelthar:BAAANQADCgQIBAABNQADCgUICgABAAAAAA==.Kaesilius:BAAANQAECgEIAQAAAA==.Kaezon:BAAANQADCgcIDAAAAA==.Kairii:BAAANQADCggIDQAAAA==.Kajoko:BAAANQADCggIEAAAAA==.Kalaya:BAAANQADCgMIBAAAAA==.Kalinia:BAAANQAECgcICwAAAA==.Kalystia:BAAANQAECgIIAgAAAA==.Kantariss:BAAANQAFFAEIAQAAAA==.Kantp:BAAANQAECgUIBwABNQAFFAEIAQABAAAAAA==.Kantsu:BAAANQAECgIIAgAAAA==.Karaan:BAAANQADCgIIAwAAAA==.Kardev:BAAANQAECgYICAAAAA==.Kardrick:BAAANQADCgUIBQAAAA==.Kariik:BAAANQAECgcIBwAAAA==.Karnport:BAAANQADCgUIBQAAAA==.Karrak:BAAANQADCgcIBwAAAA==.Kayallie:BAAANQADCgIIAgAAAA==.',
Ke='Kegales:BAAANQAECgcIBgABNQAECgcIBwABAAAAAA==.Keight:BAAANQAECgIIAgAAAA==.Kendrisite:BAAANQADCgMIAwAAAA==.Kenlock:BAAANQAECgEIAQAAAA==.Kennas:BAAANQADCgYIBgAAAA==.Kennypaladin:BAAANQADCgYIDAAAAA==.Kerelyse:BAAANQADCgQIBAAAAA==.',
Kh='Khake:BAAANQADCggIDQAAAA==.Khilea:BAAANQADCgQIBQAAAA==.Khorm:BAAANQAECgEIAQAAAA==.',
Ki='Kierstin:BAAANQAECgIIAgAAAA==.Kijay:BAAANQAECgIIAgAAAA==.Kimishima:BAAANQAECgEIAQAAAA==.Kitsunami:BAAANQAECgEIAQAAAA==.Kittenlove:BAAANQADCgYIBwAAAA==.Kittew:BAAANQAECgcIDAAAAA==.Kiwipox:BAAANQAECgcICwAAAA==.Kiwî:BAAANQAECgYICAAAAA==.',
Kj='Kj:BAAANQAECgMIBAAAAA==.',
Kk='Kkilljoy:BAAANQADCgUIBQAAAA==.Kkj:BAAANQADCgYIBwAAAA==.',
Kl='Kljy:BAAANQADCgYICQAAAA==.',
Kn='Knai:BAAANQADCggIDAAAAA==.',
Ko='Komak:BAAANQADCgcIBwAAAA==.Koravellium:BAAANQAECgcICwAAAA==.Korìì:BAAANQADCgYICwAAAA==.Koume:BAAANQADCggICwAAAA==.',
Kr='Kraison:BAAANQADCgYIDQAAAA==.Krayola:BAAANQADCgYICwAAAA==.Kriocyl:BAAANQADCgYIBgAAAA==.Kryllian:BAAANQADCgYIBgAAAA==.Kryzak:BAAANQADCgYIDAAAAA==.',
Ku='Kusanagisama:BAAANQADCgcIBwAAAA==.Kushmints:BAAANQAECgIIAgAAAQ==.Kutham:BAAANQAECgMIAwAAAA==.Kuula:BAAANQADCgMIAwAAAA==.',
Ky='Kychan:BAAANQAFFAEIAQAAAA==.Kynada:BAAANQAECgEIAQAAAA==.',
La='Labrat:BAAANQADCgUIBgAAAA==.Lacutis:BAAANQADCgMIAwAAAA==.Lamona:BAAANQADCgUIBwAAAA==.Lanille:BAAANQAECgcICwAAAA==.Lanli:BAAANQADCggIDAABNQAECgcICwABAAAAAA==.Larissah:BAEANQADCggICAABNQAECgcICgABAAAAAA==.Lastirishman:BAAANQADCgYIBgAAAA==.Latondra:BAAANQAECgEIAQABNQAECggICwABAAAAAA==.Lavendardoe:BAAANQADCgYICgAAAA==.Lazuriel:BAAANQADCgcIDQAAAA==.',
Lb='Lb:BAAANQAECgEIAQAAAA==.',
Le='Learissa:BAAANQADCgUICQAAAA==.Leharas:BAAANQAECgcIDAAAAA==.Leharthas:BAAANQADCggIDwABNQAECgcIDAABAAAAAA==.Lejeune:BAAANQADCgYICgAAAA==.Lenana:BAAANQADCggIEQAAAA==.Lesgrossman:BAAANQADCgUIBwAAAA==.Levv:BAAANQAECgEIAQAAAA==.Lexaprohoe:BAAANQAECgEIAQAAAA==.',
Lh='Lhpitts:BAAANQADCgcICwAAAA==.',
Li='Lifestalk:BAAANQADCgYIBgAAAA==.Lillers:BAAANQAECgEIAQAAAA==.Livedøg:BAAANQAECgYIBgAAAA==.Lizardwizard:BAAANQADCgYIBgABNQAECgcICwABAAAAAA==.Lizzymcguire:BAAANQADCggIEAAAAA==.',
Lj='Ljn:BAAANQADCgIIAgAAAA==.',
Lo='Lockstock:BAAANQADCgEIAQAAAA==.Locktober:BAAANQAECgUIBwAAAA==.Lom:BAAANQADCggIEAAAAA==.Lomuur:BAAANQAECgEIAQAAAA==.Lonzso:BAAANQADCggIDgAAAA==.Lorcàn:BAAANQADCgUICgAAAA==.Loriat:BAAANQADCgcIDgAAAA==.Lorthan:BAAANQAECgIIAgAAAA==.Lostdruid:BAAANQAECgEIAQAAAA==.Lotekshunter:BAAANQAFFAMIBAAAAA==.Louerre:BAAANQAECgIIAwAAAA==.Loyolla:BAAANQADCgYICgAAAA==.Lozenn:BAAANQADCgEIAQAAAA==.',
Lu='Luagarb:BAAANQABCgQIAgABNQAECgcICQABAAAAAA==.Lucie:BAAANQADCgUIBwAAAA==.Lucinde:BAAANQADCgcIDQAAAA==.Luminescent:BAAANQAECgIIAgAAAA==.Lumineus:BAAANQAECgEIAQAAAA==.Lunaelvira:BAAANQAECgEIAQAAAA==.Lunamina:BAAANQADCgIIAgAAAA==.Lunathiicc:BAAANQADCgYIBgAAAA==.Lunith:BAAANQADCgYICwAAAA==.Lurai:BAAANQAECgEIAQAAAA==.',
Ly='Lyletoa:BAAANQADCgcIDQAAAA==.Lyphia:BAAANQABCgIIAgAAAA==.Lyssera:BAAANQADCgUIBQAAAA==.',
['Lö']='Lövis:BAAANQADCgcIDgAAAA==.',
Ma='Maceofbase:BAAANQAECgMIAwAAAA==.Maemis:BAAANQAECgUIBQAAAA==.Magiczeejay:BAAANQABCgIIBAAAAA==.Magmaragma:BAAANQAECgcICwAAAA==.Majishin:BAAANQAECgIIAgAAAA==.Malibo:BAAANQAECgIIAgAAAA==.Malloc:BAAANQADCgcIDQAAAA==.Malmack:BAAANQAECgEIAQAAAA==.Manutebol:BAAANQADCggICwAAAA==.Marhayho:BAAANQADCgUIBQAAAA==.Mariecrystal:BAAANQADCgYICwAAAA==.Marragma:BAAANQADCgUIBQABNQAECgcICwABAAAAAA==.Marsbars:BAAANQAECgEIAQAAAA==.Matty:BAAANQAECgQIBAAAAA==.Mazrae:BAAANQADCgYICgAAAA==.',
Mc='Mccheesee:BAAANQADCgIIAgAAAA==.Mcnonal:BAAANQAECgEIAQAAAA==.',
Me='Meatshiëld:BAAANQADCgYICwAAAA==.Meech:BAAANQADCggIDQAAAA==.Megalopizza:BAAANQAECgcICwAAAA==.Mennalich:BAAANQADCgQIBAABNQADCgYIBwABAAAAAA==.Mercutios:BAAANQADCgcICQAAAA==.Mercyarrow:BAAANQADCgYIBgAAAA==.Merlotta:BAAANQADCgUIBwAAAA==.Mershy:BAAANQADCggIEQAAAA==.Merìngue:BAAANQADCgcIDAAAAA==.Meshuntress:BAAANQADCggIDAAAAA==.Meslaandra:BAAANQADCgQIBAABNQADCggIDAABAAAAAA==.Meterio:BAAANQADCggIDgAAAA==.Methelin:BAAANQABCgIIAgAAAA==.Meyna:BAAANQADCgUICQAAAA==.',
Mi='Miand:BAAANQADCgIIAgABNQADCggIDwABAAAAAA==.Micheal:BAAANQADCgcIDgAAAA==.Mictain:BAAANQADCgYICwAAAA==.Mikeg:BAAANQAECgIIAgAAAA==.Mikobroods:BAAANQADCgcIDQAAAA==.Millandra:BAAANQADCgYIDAAAAA==.Millificent:BAAANQAECgUIBwAAAA==.Minató:BAAANQADCgYIBgAAAA==.Miraclemax:BAAANQABCgIIAgAAAA==.Misbehavin:BAAANQAECgYICAAAAA==.Misuse:BAAANQADCgcIBgAAAA==.Mitsuba:BAAANQADCgcIDAAAAA==.',
Mo='Moa:BAAANQADCgYICwAAAA==.Mocii:BAAANQADCgEIAQAAAA==.Moldram:BAAANQAECgEIAQAAAA==.Momoney:BAAANQADCgQIBAAAAA==.Monadox:BAAANQADCgUIBQAAAA==.Monthaniel:BAAANQAECgYICwAAAA==.Moochpriest:BAAANQAECgYICAAAAA==.Moocowjr:BAAANQADCggIDgAAAA==.Mooni:BAAANQADCgYICwAAAA==.Moontide:BAAANQADCgYIDAAAAA==.Moorg:BAAANQADCgIIAgAAAA==.Mora:BAAANQAECgQIBAAAAA==.Morgannion:BAAANQADCgUICAAAAA==.Morgathiel:BAAANQADCggIDwAAAA==.Moroth:BAAANQADCggICAAAAA==.Motogrowl:BAAANQADCgMIAwAAAA==.',
Ms='Mschel:BAAANQADCgIIAgAAAA==.Mstroomtoyou:BAAANQADCgEIAQAAAA==.Mstrshredder:BAAANQADCgEIAQAAAA==.',
Mu='Muffens:BAAANQABCgIIAgAAAA==.Mugastrasza:BAAANQADCgUIBQAAAA==.Mungle:BAAANQADCgIIAgAAAA==.Mungler:BAAANQADCgIIAgAAAA==.Murdisnt:BAAANQADCgEIAQABNQAECgcIBgABAAAAAA==.Murwar:BAAANQAECgcIBgAAAA==.Musashiden:BAAANQAECgYICAAAAA==.',
My='Mydrood:BAAANQADCggIDwAAAA==.Myrabelle:BAAANQADCggIDQAAAA==.Mythious:BAAANQADCgUIBwAAAA==.',
['Mà']='Màrasi:BAAANQADCggICAAAAA==.',
Na='Naaru:BAAANQAECgIIAgAAAA==.Naerina:BAAANQAECgIIAgAAAA==.Nakeam:BAAANQAECgEIAQAAAA==.Nakiasha:BAAANQABCgQIBAAAAA==.Nallyssa:BAAANQADCgcIDgAAAA==.Namaah:BAAANQADCgMIBAAAAA==.Namaria:BAAANQADCgYICwAAAA==.Narset:BAAANQAECgIIAgAAAA==.Nash:BAAANQADCgUIBQAAAA==.Nayra:BAAANQADCgcIDQAAAA==.Nazjana:BAAANQAECgYIBgAAAA==.',
Ne='Neandra:BAAANQADCgcICAAAAA==.Necrox:BAAANQADCgUIBwAAAA==.Neinlawst:BAAANQADCgQIBAAAAA==.Neorawr:BAAANQAECgEIAQAAAQ==.Nereana:BAAANQADCgUIBgAAAA==.Neriel:BAAANQAECgEIAQAAAA==.Neuromance:BAAANQADCgYICAAAAA==.Nev:BAAANQAECgYICAAAAA==.',
Ni='Niamhaisling:BAAANQADCgQIBAAAAA==.Nightcastar:BAAANQAECgIIAgAAAA==.Nightgem:BAAANQAECgQIBgAAAA==.Nightmen:BAAANQADCggIDAAAAA==.Niiknox:BAAANQADCggIDgAAAA==.Nikorai:BAAANQADCgUICQAAAA==.Nimka:BAAANQADCgYIBgAAAA==.Ninevolts:BAAANQAECgEIAQAAAA==.Nintern:BAAANQAFFAIIAgAAAA==.Nirileene:BAAANQAECgEIAQAAAA==.Nissangtr:BAAANQADCgYICwAAAQ==.Niven:BAAANQADCgcIDQAAAA==.',
No='Nocoifos:BAAANQADCgQIBgAAAA==.Noemi:BAAANQADCggIDgAAAA==.Nooriie:BAAANQADCgcIDgAAAA==.Noperino:BAAANQADCgUIBgAAAA==.Norimort:BAAANQADCgEIAQABNQADCgUIBQABAAAAAA==.Norp:BAAANQADCgQIBAAAAA==.',
Nu='Nuck:BAAANQAECgYICAAAAQ==.Nullpizza:BAAANQADCgYIBgABNQAECgcICwABAAAAAA==.Nurgle:BAAANQADCgYIDAAAAA==.Nursing:BAAANQABCgIIAgAAAA==.',
Ny='Nykole:BAAANQADCgUIBwAAAA==.Nyxdruid:BAAANQADCgEIAQAAAA==.',
Ob='Obex:BAAANQADCgEIAQAAAA==.Obus:BAAANQAECgEIAQAAAA==.Obviousness:BAAANQAECgQICAAAAA==.',
Ol='Ollivander:BAAANQADCgYIDAAAAA==.Olmec:BAAANQADCgMIBQAAAA==.Olmeck:BAAANQADCgQIBQAAAA==.Olugbeja:BAAANQADCggIFAAAAA==.',
Om='Omnomnomnomy:BAAANQAECgIIAgAAAA==.',
Oo='Oofie:BAAANQADCgUIBQAAAA==.',
Or='Ormazd:BAAANQADCgIIAgAAAA==.',
Os='Oshoot:BAAANQAECgEIAQAAAA==.Osiyo:BAAANQADCgQIAwABNQADCgUIBgABAAAAAA==.',
Ou='Outz:BAAANQADCgIIAgAAAA==.',
Pa='Pacificia:BAAANQADCgcIDQAAAA==.Padt:BAAANQADCgYIBgAAAA==.Paladaes:BAAANQADCgMIBQAAAA==.Pallyhax:BAAANQAECgIIAQAAAA==.Pallytickles:BAAANQADCgMIAwAAAA==.Paltari:BAAANQAECgEIAQAAAA==.Panana:BAAANQADCggICwAAAA==.Pandaale:BAAANQADCgcIDAAAAA==.Pandurin:BAAANQADCgIIAgAAAA==.Pannok:BAAANQADCgEIAQAAAA==.Panzer:BAAANQADCgYICgAAAA==.Papajohnsceo:BAAANQAECggICwAAAA==.Papamnk:BAAANQADCggICAAAAA==.Papatotem:BAAANQAECgIIAgAAAA==.Parzival:BAAANQADCgEIAQAAAA==.Pathoren:BAAANQAECgEIAQAAAA==.Pawzja:BAAANQAECgQIBQAAAA==.',
Pe='Pegasus:BAAANQAECgEIAQAAAA==.Pepsired:BAAANQAECgcICwAAAA==.',
Pf='Pfezwik:BAAANQAECgYICAAAAA==.',
Ph='Phlygurl:BAAANQADCggIDwAAAA==.Phonng:BAAANQADCgMIAwAAAA==.Phorquaaray:BAAANQADCgYICgAAAA==.',
Pi='Pitu:BAAANQAECgEIAQAAAA==.',
Pl='Placid:BAAANQAECgUIBgAAAQ==.Plixxy:BAAANQAECgIIAgAAAA==.',
Po='Pokez:BAAANQADCgIIAgAAAA==.Poobies:BAAANQADCgUIBQAAAA==.',
Pr='Primenecro:BAAANQADCgMIBAAAAA==.Pristitute:BAAANQAECgQIBAAAAA==.Providence:BAAANQAECgEIAQAAAA==.',
Ps='Psylocin:BAAANQABCgQIBgAAAA==.',
Pu='Puddyng:BAAANQAECgEIAQAAAA==.Puflight:BAAANQADCggIDgAAAA==.Pukasama:BAAANQABCgQIBgAAAA==.Puncake:BAAANQAECgEIAQAAAA==.Punemonsune:BAAANQADCgUIBQAAAA==.Purzalot:BAAANQADCgYIBgABNQAECgcIDAABAAAAAA==.',
Qu='Quava:BAAANQAECgcIDAAAAA==.Quintilian:BAAANQAECggIDAAAAA==.Quìnn:BAAANQADCgcIBwAAAA==.',
Qw='Qwelzee:BAAANQABCgEIAQAAAA==.',
Ra='Racktar:BAAANQADCgcIDAAAAA==.Rada:BAAANQADCgEIAQABNQADCgUICAABAAAAAA==.Radaski:BAAANQADCgUICAAAAA==.Raines:BAAANQADCgMIAwAAAA==.Rainnshine:BAAANQADCgYICwAAAA==.Rakdos:BAAANQADCgYIBgAAAA==.Rakkel:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Ramohna:BAAANQADCgIIAgAAAA==.Ranpha:BAAANQAECgEIAQAAAA==.Rathanin:BAAANQADCgUIBQAAAA==.Razar:BAAANQADCgcIDQAAAA==.',
Re='Reapersdeath:BAAANQADCgMIBQAAAA==.Redhydra:BAAANQADCggIDgAAAA==.Redmagic:BAAANQAECgIIAgAAAA==.Reera:BAAANQAECgIIAgAAAA==.Reiyaya:BAAANQAECgQIBAAAAA==.Remetik:BAAANQADCgEIAQAAAA==.Remma:BAAANQADCggIDgAAAA==.Reneli:BAAANQAECgUIBwAAAA==.Renillia:BAAANQADCgUIAgAAAA==.Rezik:BAAANQAFFAMIBAAAAA==.Rezin:BAAANQADCgUICQAAAA==.Rezzmonk:BAAANQAECgUIBwABNQAFFAMIBAABAAAAAA==.',
Rh='Rhaellä:BAAANQADCgYIBgAAAA==.Rhalladin:BAAANQAFFAMIBAAAAA==.Rhane:BAAANQADCgYIBgAAAA==.',
Ri='Riccio:BAAANQAECgIIAgAAAA==.Richhomiecon:BAAANQAECgQIBQAAAA==.Rikon:BAAANQADCgcIBwAAAA==.Rince:BAAANQAECgUIBgAAAA==.Rivars:BAAANQAECgQIBgAAAA==.Riyyah:BAAANQAECgMIAwAAAA==.',
Rj='Rjysk:BAAANQADCgcIDAAAAA==.',
Ro='Rocklobsta:BAAANQADCgYIBwAAAA==.Rolipol:BAAANQADCgUIBwAAAA==.Rootfang:BAAANQAECgIIAgAAAA==.Roshy:BAAANQADCgIIAgAAAA==.Rowynne:BAAANQADCgYIBgAAAA==.Royaldkplz:BAAANQAECgMIAwAAAA==.',
Ry='Ryhasia:BAAANQADCggIDwAAAA==.',
['Râ']='Râiny:BAAANQADCgUIBQAAAA==.',
['Rä']='Räine:BAAANQADCgIIAwAAAA==.',
Sa='Sailrpluto:BAAANQAECgUIBgAAAA==.Saleh:BAAANQADCgMIAwAAAA==.Salidus:BAAANQADCgYIDAAAAA==.Sallumash:BAAANQADCgYICwAAAA==.Salos:BAAANQADCgYICwAAAA==.Sando:BAAANQADCgMIBQAAAA==.Sanglant:BAAANQADCgcIDQAAAA==.Sanobu:BAAANQAECgIIAgAAAA==.Saphilock:BAAANQAECgcICwAAAA==.Saphmage:BAAANQADCgYIBgAAAA==.Saraubs:BAAANQAECgEIAQAAAA==.Sariona:BAAANQADCgYIBgAAAA==.Sarsarran:BAAANQADCgQIBAAAAA==.Saryona:BAAANQAECgEIAQAAAA==.Saylavee:BAAANQAECgEIAQAAAA==.',
Sc='Scandium:BAAANQAECgYICAAAAA==.Schuetzy:BAAANQAECgIIAgAAAA==.Scibrew:BAAANQADCggIDQAAAA==.Scndamndmnt:BAAANQADCgYICgAAAA==.Scuttlebut:BAAANQADCgQIBAAAAA==.Scytal:BAAANQAECgQIBAAAAA==.',
Se='Seacreamy:BAAANQAECgIIAgAAAA==.Seanald:BAEANQAECgcIDAAAAA==.Selaith:BAAANQADCgUIBgAAAA==.Seradriel:BAAANQABCgIIAwAAAA==.Seres:BAAANQADCgcIDQAAAA==.Serix:BAAANQAECgcICwAAAA==.',
Sh='Shaddydaddy:BAAANQADCgcIDAAAAA==.Shadeey:BAAANQADCgcIDAAAAA==.Shadowdawn:BAAANQADCgYIBgAAAA==.Shadoweater:BAAANQAECgUIBgAAAA==.Shadowyn:BAAANQABCgQIBAAAAA==.Shadyhermit:BAAANQAECgIIAgAAAA==.Shalanta:BAAANQAECgEIAQAAAA==.Shaminater:BAAANQADCggIDgAAAA==.Shamysparrow:BAAANQADCgMIAwAAAA==.Sharkeey:BAAANQAECgYICQAAAA==.Shatan:BAAANQADCgEIAQAAAA==.Shawnicon:BAAANQADCgQIBAAAAA==.Shayne:BAAANQAECgYICgAAAA==.Shestrouble:BAAANQAECgYICAAAAA==.Shezz:BAAANQADCgYIBgAAAA==.Shezzam:BAAANQADCgIIAgAAAA==.Shezzus:BAAANQADCgIIAgAAAA==.Shinikes:BAAANQADCgcIDAABNQADCggICgABAAAAAA==.Shinryu:BAAANQABCgIIAgAAAA==.Shinyterp:BAAANQAECgYICAAAAA==.Shirokuma:BAAANQADCgcIDQAAAA==.Shivarezz:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.Shockserker:BAAANQADCgQIBAAAAA==.Shootinbeers:BAAANQADCgEIAQABNQADCgQIBgABAAAAAA==.Shryk:BAAANQADCgQIBAAAAA==.Shuragos:BAAANQAECgcIDQAAAA==.Shxne:BAAANQADCgcICwAAAA==.Shyla:BAAANQADCgUICQAAAA==.Shyvenei:BAAANQAECgIIAgAAAA==.',
Si='Sight:BAAANQADCgcIDQAAAA==.Silverfur:BAAANQAECgYICAAAAQ==.Silverstar:BAAANQADCgYICgAAAA==.Singebeard:BAAANQAECgIIAgAAAA==.Sitrie:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.',
Sk='Skael:BAAANQADCgMIAwAAAA==.Skarnax:BAAANQADCgMIBAAAAA==.Skibidi:BAAANQADCgcIDQAAAA==.Skout:BAAANQADCgYIBgAAAA==.',
Sl='Slipshod:BAAANQADCgEIAQAAAA==.Slyferrain:BAAANQAECgEIAQAAAA==.',
Sn='Sneeze:BAAANQADCggIDQAAAA==.Snerbert:BAAANQADCgUIBQABNQADCgYIBwABAAAAAA==.Snuggle:BAAANQAECgUIBgAAAQ==.Snuggledooms:BAAANQADCggIDwAAAA==.',
So='Sofiocon:BAAANQAECgUIBQAAAA==.Soknee:BAAANQAECgIIAgAAAA==.Solshear:BAAANQADCgcIDAAAAA==.Soshha:BAAANQAECgEIAQAAAA==.Soül:BAAANQAECgEIAQAAAA==.',
Sp='Spcialblonde:BAAANQAECgcIDAAAAA==.Spilledmilk:BAAANQAECgIIAgAAAA==.Spiritgemmed:BAAANQAECgQIBAAAAA==.Sprunklez:BAAANQADCggICAABNQAECggIDgABAAAAAA==.Spyglys:BAAANQAFFAMIBAAAAA==.Spysham:BAAANQADCgcIBwAAAA==.',
Sq='Squirmys:BAAANQAECgcICwAAAA==.',
Ss='Sspepsi:BAAANQADCgcICQAAAA==.',
St='Stalis:BAAANQAECgEIAQAAAA==.Starballer:BAAANQAECgcIDQAAAA==.Stashamanda:BAAANQADCgcIDQAAAA==.Staticfury:BAAANQADCgUICQAAAA==.Sterilized:BAAANQADCgUIBwAAAA==.Stonedtotem:BAAANQADCgYICwAAAA==.Stormdraft:BAAANQADCgcIDAAAAA==.Stormen:BAAANQADCgYIBwABNQADCgcIDQABAAAAAA==.Stormenstout:BAAANQABCgQIBgABNQADCgcIDQABAAAAAA==.Strìkê:BAAANQADCgIIAgAAAA==.',
Su='Subshammy:BAAANQADCgMIAQAAAA==.Suidt:BAAANQAECgcICwAAAA==.Sunkist:BAAANQAECgIIAgAAAA==.Superchicken:BAAANQADCgYIBgAAAA==.Superspammer:BAAANQABCgEIAQAAAA==.',
Sw='Swen:BAAANQAECgUICQAAAA==.Swiatek:BAAANQAECgIIAgAAAA==.Swoozerker:BAAANQAECgEIAQAAAA==.',
Sy='Syberis:BAAANQABCgMIBQAAAA==.Syk:BAAANQADCgUIBQAAAA==.Sylmara:BAAANQAECgEIAQAAAA==.Sylvaron:BAAANQAECgUICAAAAA==.Syy:BAEANQAECgIIAgAAAA==.',
['Sÿ']='Sÿnova:BAAANQADCgcIBwAAAA==.',
Ta='Tabi:BAAANQADCgcIDQAAAA==.Tagart:BAAANQADCgEIAQAAAA==.Talanok:BAAANQADCgQIBAAAAA==.Tallerazure:BAAANQADCgcIDQAAAA==.Tanadin:BAAANQADCgQIBQAAAA==.Tanknight:BAAANQAECgQIBAAAAA==.Tanksinatra:BAAANQADCgIIAgAAAA==.Tarhasjr:BAAANQAECgEIAQAAAA==.Tawonka:BAAANQADCgMIAwABNQADCgUIBgABAAAAAA==.Taxingr:BAAANQADCgQIBAABNQADCgcICwABAAAAAA==.Taydan:BAAANQAECgEIAQAAAA==.Tazon:BAAANQAECgEIAQAAAA==.',
Te='Tencatty:BAAANQADCgcICgAAAA==.Teâ:BAAANQAECgcIDQABNQAFFAMIAwABAAAAAA==.',
Th='Thaurt:BAAANQADCgEIAQABNQADCgUICAABAAAAAA==.Thaurtt:BAAANQADCgUICAAAAA==.Thealogy:BAAANQAECgQIBQAAAA==.Thedadlife:BAAANQAECgEIAQAAAA==.Theirin:BAAANQADCgMIBQAAAA==.Theodora:BAAANQADCgUICQAAAA==.Thisisatestt:BAAANQAFFAIIAgAAAA==.Thordun:BAAANQADCgYIBgAAAA==.Thorimbor:BAAANQADCgcICwAAAA==.Thormir:BAAANQADCgUIBgAAAA==.Thoterella:BAAANQADCggIDgAAAA==.Threetrees:BAAANQADCgIIAgAAAA==.Throckmorten:BAAANQADCgYIDQAAAA==.Thundercrap:BAAANQADCgIIAgABNQADCggICAABAAAAAA==.Thymbal:BAAANQAECgMIAwAAAA==.Thót:BAAANQADCggICAAAAA==.',
Ti='Tianis:BAAANQADCgQIBwAAAA==.Tidepode:BAAANQAECgcICwAAAQ==.Timoathy:BAAANQAECgQIBAAAAA==.Tinslee:BAAANQADCggICAAAAA==.Tinykilla:BAAANQADCggIDQAAAA==.Tirarose:BAAANQAECgEIAQAAAA==.Tiric:BAAANQADCgcIDQAAAA==.Tisphonie:BAAANQADCggICAAAAA==.',
To='Toasttamer:BAAANQADCgYIDQAAAA==.Toji:BAAANQADCgYIBgAAAA==.Tonediary:BAAANQAFFAMIBAAAAA==.Tonynugz:BAAANQADCgcIDQAAAA==.Toodems:BAAANQADCggIDQAAAA==.Toothbrushs:BAAANQADCgcIDgAAAA==.Tortillaboy:BAAANQADCggIDgAAAA==.Torzha:BAAANQADCgYIDAAAAA==.Tot:BAAANQADCgcIDQAAAA==.Totempalooza:BAAANQADCgEIAQAAAA==.',
Tr='Trainteph:BAAANQADCgUICQAAAA==.Traxeon:BAAANQADCgYICAAAAA==.Tredici:BAAANQADCggIDwAAAA==.Treefïddy:BAAANQADCgIIAgABNQADCggIDAABAAAAAA==.Trekonz:BAAANQADCggICwAAAA==.Tridiah:BAAANQAECgIIAgAAAA==.Trinzen:BAAANQADCgcICgAAAA==.Truok:BAAANQAECgIIAgAAAA==.',
Ts='Tsaphiel:BAAANQAECgIIAQAAAA==.Tsaps:BAAANQAECgEIAQAAAA==.',
Tt='Ttrag:BAAANQADCgUIBwAAAA==.',
Tu='Tuckerdeath:BAAANQADCgUIBQAAAA==.Tuffey:BAAANQADCgYICgAAAA==.Tunod:BAAANQAECgcICwAAAA==.Turpentyne:BAAANQADCggIDgAAAA==.',
Tw='Twixxmonk:BAAANQADCgIIAgAAAA==.',
Tx='Txd:BAAANQAFFAMIAwAAAA==.',
Ty='Ty:BAAANQADCgIIAgAAAA==.Tyrent:BAAANQADCgcIDAAAAA==.',
['Tã']='Tãnk:BAAANQADCgEIAQAAAA==.',
Ug='Uglie:BAAANQADCgcICgAAAA==.',
Uj='Ujabamy:BAAANQAECgEIAQAAAA==.',
Ul='Ulgroth:BAAANQAECgEIAQAAAA==.',
Un='Unbound:BAAANQADCgYIBgABNQADCgcICgABAAAAAA==.Unchanged:BAAANQADCgYICwAAAA==.',
Ur='Uruwashii:BAAANQAECgEIAQAAAA==.',
Ut='Utherfer:BAAANQADCgUICwAAAA==.',
Uw='Uwuform:BAAANQAECgQIBgAAAA==.',
Va='Vaellinn:BAAANQADCgMIBAAAAA==.Vaeltar:BAAANQAECgYICAAAAA==.Vaihalla:BAAANQADCgUICAAAAA==.Valdezz:BAAANQAECgIIAgAAAA==.Valdrakken:BAAANQADCgcIDQAAAA==.Valerys:BAAANQADCgUICQAAAA==.Valloran:BAAANQADCgUIBwAAAA==.Valorish:BAAANQAECgEIAgAAAA==.Vaminnasul:BAAANQADCggIDAAAAA==.Vazindi:BAAANQADCgcIBwAAAA==.',
Ve='Vejita:BAAANQADCgYICQAAAA==.Venatora:BAAANQADCgEIAgAAAA==.Vergetorix:BAAANQADCgcIDQAAAA==.Vexkwondo:BAEANQADCgYICwAAAA==.',
Vi='Vidafacil:BAAANQADCgcIDgAAAA==.Vija:BAAANQADCgcIDQAAAA==.Vimes:BAAANQADCgIIAgAAAA==.Vindle:BAAANQADCgYICwAAAA==.Virren:BAAANQADCgYIBgABNQAECgcICwABAAAAAQ==.Virus:BAAANQAECgcIDQAAAA==.Viscica:BAAANQADCggICAAAAA==.Vixenia:BAAANQAECgIIAgAAAA==.',
Vo='Voidarcane:BAAANQAECgEIAQAAAA==.Voidfu:BAAANQADCgcIDgAAAA==.Voidrotten:BAAANQADCgQIBAAAAA==.Vowels:BAAANQAECgYICAAAAA==.',
Vp='Vpdeath:BAAANQADCggIDwABNQAECggICgABAAAAAA==.Vpsham:BAAANQAECggICgAAAA==.Vpslow:BAAANQAECgQIBAABNQAECggICgABAAAAAA==.',
Vy='Vyerix:BAAANQADCgMIAwAAAA==.Vyktorr:BAAANQADCgUICQAAAA==.Vyrix:BAAANQAECgcIDAAAAA==.',
['Vò']='Vòlp:BAAANQAECgIIAgAAAA==.',
Wa='Warelder:BAAANQAECgcIDAAAAA==.Wargazim:BAAANQAECgEIAQAAAA==.Wargens:BAAANQABCgMIAwAAAA==.Waylander:BAAANQAECgEIAQAAAA==.Wazapalooza:BAAANQAECgQIBAAAAA==.Wazvlnt:BAAANQADCgQIBQAAAA==.',
We='Weemac:BAAANQAECgEIAQAAAA==.Weledrindor:BAAANQADCgYIBgAAAA==.Welglick:BAAANQAECgEIAQAAAA==.Wendell:BAAANQAECgQIBAAAAA==.',
Wh='Whackers:BAAANQADCgcIDQAAAA==.',
Wi='Wickedh:BAAANQADCggIDgAAAA==.Wiesn:BAAANQADCgIIAgAAAA==.Willöw:BAAANQADCgcIDQAAAA==.Wilmette:BAAANQADCgYICAAAAA==.Winchu:BAAANQADCgcIDQAAAA==.Wingman:BAAANQADCgUIBQAAAA==.',
Wo='Woody:BAAANQADCgEIAQAAAA==.',
Wr='Wrongtotem:BAAANQADCgMIAwAAAA==.',
Wt='Wtfrtotems:BAAANQAECgIIAgAAAA==.',
Wy='Wytanithia:BAAANQADCgQIBAAAAA==.',
['Wì']='Wìldbìll:BAAANQADCgEIAQAAAA==.',
['Wî']='Wîcked:BAAANQADCgQIBAABNQADCggIDgABAAAAAA==.',
Xa='Xaak:BAAANQADCgYICwAAAA==.Xaldyn:BAAANQAECgEIAQAAAA==.Xalvadore:BAAANQAECgcICwAAAA==.Xanathaz:BAAANQABCgEIAQAAAA==.Xandarya:BAAANQADCgUIBQAAAA==.',
Xe='Xeliand:BAAANQADCgcIDAAAAA==.Xenarya:BAAANQADCgUICQAAAA==.Xenus:BAAANQAECgEIAQAAAA==.Xenå:BAAANQADCgUIBgAAAA==.Xerna:BAAANQADCgMIBQAAAA==.',
Xi='Xinsuendo:BAAANQAECgEIAQAAAA==.',
Xy='Xyth:BAAANQADCgMIBQAAAA==.',
['Xé']='Xérö:BAAANQADCgcIDgAAAA==.',
Ya='Yazshyr:BAAANQADCgcIDQAAAA==.',
Ye='Yellowducky:BAAANQADCggICAAAAA==.Yelmo:BAAANQAECgIIAgAAAA==.Yesshua:BAAANQADCggIDgAAAA==.',
Yi='Yiffyvulpine:BAAANQADCggIDAAAAA==.',
Yo='Yokohp:BAAANQADCgYICgAAAA==.Yoshinami:BAAANQADCgcIDQAAAA==.Yourdealers:BAAANQADCgUIBQAAAA==.',
Yr='Yreneonia:BAAANQADCgQIBQAAAA==.',
Yu='Yuliana:BAAANQADCggIDgAAAA==.Yungslash:BAAANQAECgEIAQAAAA==.Yuzuyu:BAAANQAECgEIAQAAAA==.',
Za='Zabuzã:BAAANQADCgcIBwAAAA==.Zadacyn:BAAANQADCggIDwAAAA==.Zaefel:BAAANQADCgQIBAAAAA==.Zaelais:BAAANQAECgYIBgAAAA==.Zaell:BAAANQAECgUIBAABNQAECgcIBwABAAAAAA==.Zaem:BAAANQADCgUIBQAAAA==.Zaheer:BAAANQAECgYICwAAAA==.Zahel:BAAANQAECgcICwAAAA==.Zaidya:BAAANQADCgUIBgAAAA==.Zaldias:BAAANQADCgYICgAAAA==.Zam:BAAANQAECgEIAQAAAA==.Zaqiel:BAAANQAECgUIBwAAAA==.Zashthar:BAAANQAECgEIAQAAAA==.',
Ze='Zeenie:BAAANQADCggICAAAAA==.Zeezou:BAAANQADCggIDwAAAA==.Zeltic:BAAANQADCgMIAwAAAA==.Zeno:BAAANQAECggIDgAAAA==.Zephraar:BAAANQADCgQIBAAAAA==.Zeriahz:BAAANQAECgEIAQAAAA==.Zeroinstinct:BAAANQADCgUIBQAAAA==.Zerosense:BAAANQAECgIIAwAAAA==.',
Zh='Zharkan:BAAANQADCgQIBgAAAA==.Zhenyun:BAAANQAECgEIAQAAAA==.',
Zi='Ziendi:BAAANQAECgEIAQAAAA==.',
Zo='Zoltide:BAAANQADCgUIBQABNQAECggIDAABAAAAAA==.Zolvoker:BAAANQAECggIDAAAAA==.Zombok:BAAANQADCgcIBwAAAA==.Zoobox:BAAANQAECgIIAgAAAA==.Zormond:BAAANQADCgYICwABNQADCgcIDgABAAAAAA==.',
Zu='Zuro:BAAANQADCgcIBwAAAA==.',
Zy='Zyroe:BAAANQADCgMIBAAAAA==.',
['Áe']='Áegwynn:BAAANQADCgYIBgAAAA==.',
['Âd']='Âdapt:BAAANQAECgEIAQAAAA==.',
['Ãz']='Ãzzy:BAAANQADCgYICQAAAA==.',
['Ät']='Äthenä:BAAANQAECgQIBgAAAA==.',
['Åm']='Åma:BAAANQAECgIIAgAAAA==.',
['Üt']='Üthor:BAAANQADCgUIBwAAAA==.',
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
