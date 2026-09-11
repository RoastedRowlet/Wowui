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

local lookup = {'DeathKnight-Frost','Unknown-Unknown','Paladin-Retribution','DeathKnight-Unholy','Shaman-Restoration','Evoker-Devastation','Druid-Balance','DeathKnight-Blood','Hunter-BeastMastery','Priest-Shadow','Druid-Restoration','Priest-Holy','Warrior-Arms','Mage-Arcane','Evoker-Preservation','Paladin-Holy','Rogue-Assassination','Rogue-Outlaw','DemonHunter-Devourer','Warlock-Demonology','Warlock-Destruction','Shaman-Elemental','Shaman-Enhancement','Hunter-Marksmanship','Warlock-Affliction','Monk-Brewmaster','Rogue-Subtlety','Druid-Feral','Mage-Frost',}
local provider = {region='US',realm='Whisperwind',name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Abernith:BAAANQADCgQIBwAAAA==.Abmi:BAABNQAECoEXAAIBAAkJwCTpAACpAwABAAkJwCTpAACpAwAAAA==.',
Ad='Adahlinas:BAAANQAECgEIAgAAAA==.Adarannia:BAAANQADCgUIBgAAAA==.Aderosa:BAAANQADCgMIAwABNQAECgEIAQACAAAAAA==.Adex:BAAANQAECgQIBQAAAA==.Adiase:BAAANQADCgcIDAAAAA==.Adosdruid:BAAANQADCgYIDAAAAA==.',
Ae='Aelena:BAAANQAECgEIAQAAAA==.Aemondson:BAAANQAECgUICQAAAA==.Aennirel:BAAANQADCgEIAQAAAA==.Aeroch:BAAANQAECgcIDwAAAA==.Aerodon:BAAANQADCgcIDQABNQAECgQIBQACAAAAAA==.Aerowynne:BAAANQADCgIIAgAAAA==.Aezeras:BAAANQADCgMIBQAAAA==.',
Ah='Ahmreah:BAAANQADCgUIDAAAAA==.',
Ai='Aigneis:BAAANQADCggICAAAAA==.',
Aj='Aj:BAAANQAECgcIEgAAAA==.',
Ak='Akimandia:BAAANQAECgQIBgAAAA==.Akinira:BAEANQAECgYICgAAAA==.Akronite:BAAANQAECgMIAwAAAA==.',
Al='Alamoor:BAAANQAECgUIBgAAAA==.Alandien:BAAANQADCggIFAAAAA==.Alcar:BAAANQAECgIIAwAAAA==.Aldorite:BAAANQAECgcIDwAAAA==.Alethus:BAAANQADCgYICgABNQADCggIFAACAAAAAA==.Alexandreth:BAAANQABCgEIAQAAAA==.Alexeas:BAAANQAECgEIAQAAAA==.Alexinux:BAAANQAECgEIAQAAAA==.Alphadogz:BAAANQADCgUIBQAAAA==.Alsneak:BAAANQAECgYICAAAAA==.Alteredshock:BAAANQADCgEIAQAAAA==.Alyshamanele:BAAANQAECgcIBwAAAA==.Alyxz:BAAANQAECgQIBQAAAA==.',
Am='Amareth:BAAANQAECgEIAQAAAA==.Ambuscade:BAAANQADCgcIEQAAAA==.Amelrik:BAEBNQAECoEYAAIDAAkJdyUmAQDgAwADAAkJdyUmAQDgAwAAAA==.Amirä:BAAANQAECgMIAwAAAA==.Ammonkguy:BAAANQADCgcICwAAAA==.Amooncrima:BAAANQAECgQIBQAAAA==.Ampharosite:BAAANQADCgEIAQABNQAECggIEwACAAAAAA==.',
An='Anchalon:BAAANQADCgYIDAAAAA==.Angerpaw:BAAANQAECggIEwAAAA==.Anhurst:BAAANQADCgcIEgAAAA==.Annikkin:BAAANQAECgIIAgAAAA==.Anoon:BAAANQAECgYICgAAAA==.Anshara:BAAANQAECgUIBgAAAA==.Ansys:BAEANQAECgcIDwAAAA==.Anubis:BAAANQAECgEIAQAAAA==.Anìmalmother:BAAANQADCgMIBQAAAA==.',
Ap='Aperthir:BAAANQADCgYIBwAAAA==.Aphrodittes:BAAANQADCggIDQAAAA==.Apøc:BAAANQAECgEIAQAAAA==.',
Ar='Archaelus:BAAANQADCgUIDgABNQADCgYICgACAAAAAA==.Archevil:BAAANQAECgUIBgAAAA==.Arctichail:BAAANQAECgcIDwAAAA==.Ardent:BAAANQAECgYICgAAAA==.Ares:BAAANQADCgEIAQAAAA==.Aretreja:BAAANQAECgEIAQAAAA==.Ariaala:BAAANQADCgQIBAABNQAECgIIAgACAAAAAA==.Arramin:BAAANQADCgcIDAAAAQ==.Arrenthan:BAAANQADCggICAAAAA==.Arries:BAEANQAECgQIBAAAAA==.Arsis:BAAANQAECgcIDgAAAA==.Arthricia:BAAANQADCgcIEwAAAA==.Artspriest:BAAANQAECgQIBQAAAA==.Aryii:BAAANQADCgQICAAAAA==.',
As='Asamelth:BAAANQAECgEIAQAAAA==.Ascoot:BAAANQADCgUIBgABNQADCgYIBgACAAAAAA==.Asguard:BAAANQAECgQIBgAAAA==.Astorea:BAAANQAECgQIBAAAAA==.Astoropterix:BAAANQADCgQIBQAAAA==.Astu:BAAANQADCgUICgAAAA==.',
At='Athy:BAAANQAECgEIAQAAAA==.Atreida:BAAANQAECgUIBgAAAA==.',
Au='Aurana:BAAANQADCgQIBAAAAA==.Auriok:BAAANQADCggIFQAAAA==.Auriya:BAAANQADCgUICgAAAA==.Auzua:BAAANQAECgIIAgAAAA==.',
Av='Averianna:BAAANQADCggIFAAAAA==.Avess:BAAANQADCgQIBAABNQADCgYIBgACAAAAAA==.',
Aw='Awekah:BAAANQAECgQIBgAAAA==.Awoodove:BAAANQAECgcICAABNQAECgkJGgAEAF8iAA==.',
Az='Azleah:BAABNQAECoEYAAIFAAkJuxxMBwASAwAFAAkJuxxMBwASAwAAAA==.Azorthas:BAEANQAECgEIAgAAAA==.',
Ba='Babygdhunt:BAAANQADCgcIEwAAAA==.Babyhuntard:BAAANQADCgIIAgAAAA==.Baconlock:BAAANQAECgMIBgABNQAECgkJFwAGANwhAA==.Badragon:BAAANQAECggIEwAAAA==.Badunter:BAAANQADCgYIBgAAAA==.Balleont:BAAANQAECgIIAgAAAA==.Banagar:BAAANQADCggIFAAAAA==.Banotesa:BAAANQAECgIIAgAAAA==.Barbelle:BAAANQAECggIDQAAAA==.Basdia:BAAANQAECgEIAQAAAA==.',
Be='Beakin:BAAANQAECgIIAgAAAA==.Bearcavalry:BAAANQADCgEIAQAAAA==.Bedpan:BAAANQABCgUIBQABNQADCgYIBgACAAAAAA==.Beefdip:BAAANQAECgEIAQAAAA==.Beenekromant:BAAANQADCgcIEgAAAA==.Beenjii:BAAANQAECgQICQAAAA==.Behrak:BAAANQABCgYIDgAAAA==.Beletrix:BAAANQABCgYICAAAAA==.Belgaroth:BAAANQADCgcIEgAAAA==.Belker:BAAANQADCgcIEgABNQADCggIEgACAAAAAA==.Belleta:BAAANQADCgYIDQAAAA==.Beniniah:BAAANQAFFAIIAgAAAA==.Berelaine:BAAANQADCgQIBQAAAA==.Beringthree:BAAANQAFFAEIAQAAAA==.Berthon:BAAANQADCggIFQAAAA==.Betaraybill:BAAANQADCgYIDQAAAA==.',
Bi='Biermon:BAAANQADCgYIBgAAAA==.Biertoladin:BAAANQADCgYICgAAAA==.Biertoo:BAAANQADCgEIAQAAAA==.Biertotem:BAAANQADCgMIAwAAAA==.Bigchest:BAAANQADCgYIBwAAAA==.Bigfishy:BAAANQAFFAIIAgAAAA==.Biggins:BAAANQAECgQIBAAAAA==.Bikini:BAAANQADCggIFwAAAA==.Bilpaladin:BAAANQAECgEIAQAAAA==.Biqqi:BAAANQADCgYIDgAAAA==.Birdboy:BAAANQAECgQIBgAAAA==.Bitfu:BAAANQADCggIDwAAAA==.',
Bl='Blackpurple:BAAANQAECgIIAgAAAA==.Bladefall:BAAANQAECgMIAwABNQABCgIIAgACAAAAAA==.Blademane:BAAANQAECgIIAgAAAA==.Blanch:BAAANQAECgQIBQAAAA==.Bloc:BAAANQAECgQIBgAAAA==.Blondragoon:BAAANQAECgQIBAABNQAECggIEQACAAAAAA==.Bloodzeus:BAAANQADCgUIBQABNQADCggIFgACAAAAAA==.Bluekitten:BAAANQADCgMIAwAAAA==.Blueshark:BAAANQADCgQIBwABNQADCggIFgACAAAAAA==.Bluesknight:BAAANQAECgUICQAAAA==.Bluestem:BAAANQADCgEIAQAAAA==.',
Bm='Bmn:BAAANQADCgIIAgAAAA==.',
Bo='Bobfilthy:BAAANQADCggICwAAAA==.Bodypillow:BAAANQAECgYIBwAAAA==.Bodytype:BAAANQAECgEIAQAAAA==.Bojanglz:BAAANQADCgYICQAAAA==.Bolvasaur:BAAANQADCggIDwAAAA==.Bonanza:BAAANQADCgYIEQAAAA==.Bonitamuerte:BAAANQADCgcIEgAAAA==.Bonës:BAAANQAECgMIBQAAAA==.Boomboombang:BAAANQAECgcIEAAAAA==.Boozìn:BAAANQADCgcIDQAAAA==.Bordock:BAAANQADCgEIAQAAAA==.Boricc:BAAANQAECgYIBwAAAA==.Bowbow:BAAANQADCgYIDQAAAA==.Boykisser:BAAANQADCgQIBAAAAA==.',
Br='Brad:BAAANQAECgEIAQABNQAFFAYICQAHAKMaAA==.Bragaul:BAAANQAECgcIEAAAAA==.Bragnar:BAAANQAECgMIAwAAAA==.Branch:BAAANQADCgQIBgAAAA==.Brandodin:BAAANQADCggIDwAAAA==.Brewadin:BAAANQAECgMIAwAAAA==.Brewdragon:BAAANQAECgUIBwAAAA==.Briarclaw:BAAANQADCgYICwAAAA==.Brightlockk:BAAANQAECgUIBQAAAA==.Brotherbear:BAAANQADCgUICgAAAA==.Brotherodd:BAAANQABCgIIAgAAAA==.Bruceflee:BAAANQADCgYICgAAAA==.Brynstormr:BAAANQADCgcIDgAAAA==.',
Bu='Bubblecream:BAAANQADCgYIDAAAAA==.Bubbletea:BAAANQAECgEIAQAAAA==.Budsdeath:BAAANQAECgcIEgABNQAFFAUIBwAIAIwRAA==.Bufflock:BAAANQADCgYICQAAAA==.Bulen:BAAANQADCgIIAgAAAA==.',
By='Byiak:BAAANQADCggIEwAAAA==.',
['Bê']='Bêêfstick:BAAANQADCgQIBQAAAA==.',
['Bó']='Bób:BAAANQADCgUIBQABNQAECgQIBQACAAAAAA==.',
Ca='Caddyclap:BAAANQADCggICAABNQAFFAIIAgACAAAAAA==.Caddylucifer:BAAANQAFFAIIAgAAAA==.Cadus:BAAANQAECgEIAQAAAA==.Caillte:BAAANQADCgUICgAAAA==.Caldormu:BAAANQAECgIIAgAAAA==.Caleé:BAAANQADCggIFwAAAA==.Callicia:BAAANQAECgQIBgAAAA==.Calypie:BAAANQAECgIIAwAAAA==.Camlostiae:BAAANQAECgIIAgAAAA==.Canolgon:BAAANQAECgUIBQAAAA==.Canthia:BAAANQADCggIEwAAAA==.Capncrunch:BAAANQADCgUICgAAAA==.Caprock:BAAANQADCggIFAAAAA==.Capymage:BAAANQAECgcICQAAAA==.Capywarr:BAAANQAECgYICgABNQAECgcICQACAAAAAA==.Cardim:BAAANQADCgcIBwABNQAECgIIAgACAAAAAA==.Carryo:BAAANQADCgEIAgAAAA==.Cassima:BAAANQAECgQIBQAAAA==.Catharin:BAAANQADCgIIAgAAAA==.Catjam:BAAANQAECgMIAwAAAA==.Cattibreezze:BAAANQADCgQIBwAAAA==.Cawnar:BAAANQAECgEIAQAAAA==.',
Ce='Cediar:BAAANQADCggIEAAAAA==.Celandius:BAAANQAECgEIAgAAAA==.Celaphalopod:BAAANQADCgUIBQABNQAECgEIAgACAAAAAA==.Celathorís:BAAANQAECgQIBQAAAA==.Celeste:BAAANQADCggIEwAAAA==.Cenecia:BAAANQAECgUIBgAAAA==.',
Ch='Chaddilock:BAAANQAECgQIBAAAAA==.Chaimee:BAAANQAECgYICAAAAA==.Chaoticshamm:BAAANQADCgUIBQABNQAECgQIBQACAAAAAA==.Chapters:BAAANQADCgQIBAAAAA==.Chebangbang:BAAANQADCgYIDQAAAA==.Cheekytiki:BAAANQAECgQIBgAAAA==.Cheesewizz:BAAANQADCggIDgAAAA==.Cheeze:BAAANQADCgYICgAAAA==.Chelsarda:BAABNQAECoEXAAIJAAkJ+BbTEACkAgAJAAkJ+BbTEACkAgAAAA==.Chenohai:BAAANQAECgQIBQAAAA==.Cheracuda:BAAANQADCggICAAAAA==.Cherisê:BAAANQADCggIFAAAAA==.Chessie:BAAANQAECgEIAQAAAA==.Chestercheto:BAAANQADCggICAAAAA==.Chillivibes:BAABNQAECoEXAAIKAAgJCQ21DwAZAgAKAAgJCQ21DwAZAgAAAA==.Chinanewyear:BAAANQAECgcICwABNQAECggIEwACAAAAAA==.Choal:BAAANQAECgMIBAAAAA==.Chogalbuu:BAAANQADCggIEwAAAA==.Chopaa:BAAANQADCgcICQAAAA==.Chopstick:BAAANQADCgYICAABNQAECgEIAQACAAAAAA==.Chronostrasz:BAAANQAECgIIAgAAAA==.Chubhub:BAAANQAECgUIBgAAAA==.',
Ci='Ciante:BAABNQAECoEYAAILAAkJHREACwAqAgALAAkJHREACwAqAgAAAA==.Cindara:BAAANQAECgEIAQAAAA==.Cinderazenot:BAAANQAECgQIBgAAAA==.Cinderwyn:BAAANQADCgUIDAAAAA==.Cirene:BAAANQAECgIIAwAAAA==.',
Cl='Clapmycheeks:BAAANQADCgYICQAAAA==.Clapprcob:BAAANQADCgYICgAAAA==.Clei:BAAANQAECgQIBAABNQAECgcIEAACAAAAAA==.Cleopet:BAAANQADCgYIBwAAAA==.Clerrick:BAAANQAECgEIAQAAAA==.Clexise:BAAANQAECgcIDgAAAA==.Clownmilkie:BAAANQADCggIDgABNQAECggIEwACAAAAAA==.Clutchcake:BAAANQAECgcIEAAAAA==.Clutchpal:BAAANQADCgYICAAAAA==.',
Co='Comac:BAAANQAECgUIBgAAAA==.Connielingus:BAAANQADCggICAAAAA==.Coopdaloop:BAAANQAECgMIAwAAAA==.Copelin:BAAANQAECgUIBgAAAA==.Coreylock:BAAANQAECgcIEgAAAA==.Cornputer:BAAANQAECgIIAgAAAA==.',
Cp='Cptarcano:BAAANQAECgEIAQAAAA==.',
Cr='Crashingvoid:BAAANQADCggIDQAAAA==.Creacher:BAAANQADCgYICgAAAA==.Crelix:BAAANQADCgQIBAAAAA==.Crescendo:BAAANQADCgUICAAAAA==.Cresencia:BAABNQAFFIEKAAIMAAYJnBpvAAA4AgAMAAYJnBpvAAA4AgAAAA==.Creservation:BAAANQAFFAEIAQAAAA==.Crestoration:BAAANQAECgIIAgAAAA==.Cret:BAAANQADCggIDwAAAA==.Crimsoneye:BAAANQADCgYIBgAAAA==.Crimsonrosé:BAAANQAECgQIBAAAAA==.',
Cu='Curbi:BAAANQADCgcIBwAAAA==.Cursedd:BAAANQADCggIFAAAAA==.',
Cy='Cynderash:BAAANQADCgYIDQAAAA==.Cyndvia:BAAANQADCgYIBgAAAA==.',
['Cä']='Cätrÿnae:BAAANQAECgEIAQAAAA==.',
['Có']='Cóuch:BAAANQADCgcICgABNQAECgEIAQACAAAAAA==.',
Da='Dachopper:BAAANQAECgQIBgAAAA==.Daedrak:BAAANQAECgcIDwAAAA==.Damase:BAAANQAECgQIBAAAAA==.Damasen:BAAANQADCgYIEAAAAA==.Dantioch:BAAANQAECgIIAgAAAA==.Daphni:BAAANQADCgUIBQAAAA==.Darckmage:BAAANQAECgUIBgAAAA==.Dardelindor:BAAANQADCgYICwAAAA==.Darkenda:BAAANQAECgIIAwAAAA==.Darkpenance:BAAANQABCgQIBAAAAA==.Darkruneses:BAAANQAECgYICwAAAA==.Darkwarden:BAAANQADCggIFgAAAA==.Darkwisdom:BAAANQAECgUIBQAAAA==.Dartford:BAAANQADCgYIBgAAAA==.Dawnbreaker:BAAANQADCgQIBAAAAA==.',
Dd='Ddog:BAAANQADCgYIDAAAAA==.',
De='Deadris:BAAANQADCgIIAgABNQADCgYIDQACAAAAAA==.Deathbuds:BAABNQAFFIEHAAIIAAUJjBEEAgBwAQAIAAUJjBEEAgBwAQAAAA==.Deathsdance:BAAANQAECgEIAQAAAA==.Deathspecta:BAAANQAECgUIBwAAAA==.Deathtickles:BAAANQADCgYICgAAAA==.Deathzero:BAAANQADCggIDgAAAA==.Decora:BAAANQADCgUIBQAAAA==.Deekayray:BAAANQADCgUICAAAAA==.Deemonray:BAAANQADCgYICgAAAA==.Deer:BAABNQAFFIEJAAMHAAYJoxqJAAAxAgAHAAYJoxqJAAAxAgALAAEJbASyBABJAAAAAA==.Deft:BAAANQAECgYIBgABNQAFFAYICwANAEAbAA==.Deftx:BAABNQAFFIELAAINAAYJQButAABRAgANAAYJQButAABRAgAAAA==.Deltoramasta:BAABNQAFFIELAAIOAAYJLRuHAABSAgAOAAYJLRuHAABSAgAAAA==.Demaddotter:BAAANQAECgIIAgAAAA==.Demeric:BAAANQADCgYICgAAAA==.Demiria:BAAANQAECgIIAgAAAA==.Demonclutch:BAAANQADCgQIBAABNQADCgYICAACAAAAAA==.Demondiablo:BAAANQADCgYIDAAAAA==.Demteddies:BAAANQADCgYIDAAAAA==.Derkk:BAAANQADCgUIBQAAAA==.Derpherper:BAAANQAECgIIAgAAAA==.Deselation:BAAANQADCggICAAAAA==.Dethbringr:BAAANQAECgEIAQAAAA==.Devilldog:BAAANQADCggIFQAAAA==.Devilshale:BAAANQAECgIIBAAAAA==.Dezardondor:BAAANQAECgQICAAAAA==.',
Di='Dienetta:BAAANQAFFAEIAQAAAA==.Dirkens:BAAANQAECgQIBAAAAA==.Disapointing:BAAANQAECgEIAQAAAA==.Ditini:BAAANQAECgIIAgAAAA==.Ditusen:BAAANQABCgQIBAABNQAECgIIAgACAAAAAA==.',
Dk='Dkata:BAAANQAECgUIBgAAAA==.',
Dm='Dmalf:BAABNQAFFIEJAAIMAAYJoRZaAABBAgAMAAYJoRZaAABBAgAAAA==.Dmalfthree:BAAANQAECgcIEAAAAA==.',
Dn='Dnice:BAAANQAECgUIBwAAAA==.',
Do='Dorkstar:BAAANQAECggIEwABNQADCgQIBAACAAAAAA==.Dorlondo:BAAANQADCgUICgABNQAECgIIAgACAAAAAA==.Dorriel:BAAANQADCgcIDgAAAA==.Doup:BAAANQAECgQIBgAAAA==.Doveknight:BAABNQAECoEaAAIEAAkJXyLvAgCTAwAEAAkJXyLvAgCTAwAAAA==.Dowal:BAAANQAFFAEIAQAAAQ==.Dozar:BAAANQAECgMIAwAAAA==.',
Dr='Dragonrey:BAAANQAECgQIBQAAAA==.Dragonton:BAEANQAECggIEwAAAA==.Drakaury:BAAANQAECgEIAQABNQAECgUICAACAAAAAA==.Drays:BAAANQADCgYICgAAAA==.Drbean:BAAANQADCgcIEgAAAA==.Dreåm:BAAANQADCggIFAAAAA==.Drgndeeznuts:BAAANQAECgIIAgAAAA==.Drhynno:BAABNQAECoEXAAMGAAkJiBSlCQAvAgAGAAgJXBKlCQAvAgAPAAEJrAGuKAAzAAAAAA==.Drshockër:BAAANQADCgcIEgAAAA==.Drwho:BAAANQAECgQIBQAAAA==.',
Du='Duderocker:BAABNQAECoEYAAMQAAkJzwOyKgDLAQAQAAkJzwOyKgDLAQADAAcJYwppQwB7AQAAAA==.Duhstorm:BAAANQADCgYIBgAAAA==.Dulapeep:BAAANQADCgYIBgAAAA==.Dumond:BAAANQAECgUIBwAAAA==.Dunkdiving:BAAANQAECgcICwAAAA==.Dunkelplex:BAAANQADCggIEwAAAA==.Duttio:BAAANQAECgEIAQAAAA==.Dutts:BAAANQADCggIFAAAAA==.Duzell:BAAANQADCggICQAAAA==.',
Dx='Dxft:BAAANQAECgIIAgABNQAFFAYICwANAEAbAA==.',
['Dô']='Dôtsfired:BAAANQAECgIIAgAAAA==.',
Ec='Eckis:BAAANQAECgEIAgAAAA==.Eclipzeno:BAAANQADCgMIAwABNQAECgkJGQAOAJgmAA==.',
Ee='Ee:BAAANQADCgYIDgAAAA==.Eelos:BAAANQAECgQIBQAAAA==.',
Eg='Egregious:BAAANQADCgQIBQAAAA==.',
Ei='Eidon:BAAANQADCgYICgAAAA==.',
El='Elaahla:BAAANQAECgEIAQAAAA==.Elderin:BAAANQAECgQIBQAAAA==.Eldin:BAAANQAECgEIAgAAAA==.Elegiacal:BAAANQADCgEIAQABNQADCggIEwACAAAAAA==.Elenarae:BAAANQAECgQIBgAAAA==.Elissareh:BAAANQAECgEIAgABNQAECgkJGAAFALscAA==.Elissia:BAAANQAECgEIAQABNQAECgQICAACAAAAAA==.Elliara:BAAANQAECgEIAQAAAA==.Ellosaran:BAAANQADCgUIBQAAAA==.Elsenor:BAAANQADCgcIDgAAAA==.Elunie:BAAANQAECgEIAQAAAA==.Elwynne:BAAANQADCgYIBgAAAA==.',
Em='Emberosia:BAAANQADCgYIBgAAAA==.',
En='Enigmatic:BAAANQADCggIEwAAAA==.',
Ep='Epicgirlhero:BAAANQAFFAEIAQAAAA==.Epicheroine:BAABNQAECoEXAAILAAkJhh6DBADgAgALAAkJhh6DBADgAgABNQAFFAEIAQACAAAAAA==.Epirate:BAABNQAFFIELAAMRAAYJ1BVxAABuAQASAAQJ3xUjAAB+AQARAAQJtRBxAABuAQAAAA==.',
Er='Erelyda:BAAANQADCgcICAAAAA==.Eriic:BAAANQADCggIDwAAAA==.Erumak:BAAANQADCggIDAAAAA==.',
Et='Etzio:BAAANQADCgYIBgABNQAECgQICgACAAAAAA==.',
Ev='Eveth:BAAANQADCgcIDQAAAA==.Evierlena:BAAANQADCgQIBgAAAA==.Evilbettie:BAAANQABCgIIAgAAAA==.Eviliciøus:BAAANQAECgUIBwAAAA==.Evilorc:BAAANQADCgMIAwAAAA==.',
Ex='Exergymage:BAAANQAECgUIBwAAAA==.Exmortus:BAAANQAECgIIAgAAAA==.',
Ez='Ezye:BAAANQAECgEIAQAAAA==.',
Fa='Facépalm:BAAANQADCgIIAgABNQAECgYICwACAAAAAA==.Fadalaurance:BAAANQAECgQIBAABNQAECgQIBgACAAAAAA==.Faedryth:BAAANQADCgcIEAAAAA==.Fairalicious:BAAANQADCgQICwAAAA==.Fairladyz:BAAANQADCggIEAAAAA==.Falcygos:BAAANQADCgYICwAAAA==.Falstad:BAAANQADCgYIEAAAAA==.Fartmastery:BAAANQADCgUIBQAAAA==.Fathdh:BAABNQAFFIEKAAITAAUJRglYAQCLAQATAAUJRglYAQCLAQAAAA==.Fathmonk:BAAANQAECgYIBgABNQAFFAUICgATAEYJAA==.',
Fe='Fektt:BAAANQADCgUIBQAAAA==.Fells:BAAANQAECgYICgAAAA==.Felmungandr:BAAANQAECgQIBgAAAA==.Felstone:BAAANQADCgYICgAAAA==.Fenrier:BAAANQADCgEIAQAAAA==.Feníxx:BAAANQAECgUICQAAAA==.Ferelyse:BAAANQADCggICAAAAA==.Fezim:BAAANQAECgIIAgAAAA==.',
Fi='Fingerdeath:BAAANQADCgYIBgABNQAECgIIAgACAAAAAA==.Fionnavhair:BAAANQADCggIDwAAAA==.Firecrusader:BAAANQADCgYIEAAAAA==.Fistermcghee:BAAANQADCgQIBAABNQAECgQIBgACAAAAAA==.Fixedchance:BAAANQADCgEIAQAAAA==.',
Fl='Flameclaw:BAAANQADCggICwAAAA==.Flatulentone:BAAANQADCgQICQAAAA==.Flidalyeth:BAAANQAECgIIAgAAAA==.Floofyreg:BAAANQAFFAIIAgAAAA==.Floorpov:BAAANQAECgEIAgAAAA==.Flybynight:BAAANQAECgUICwAAAA==.',
Fo='Fogoldin:BAAANQADCgUIBQAAAA==.Fourtwinke:BAAANQAECgIIAgAAAA==.Foxcat:BAAANQAECgEIAQAAAA==.Foxykitten:BAAANQADCgIIAgABNQADCgQIBAACAAAAAA==.',
Fr='Freakyfast:BAAANQADCgcIBwAAAA==.Freezeorburn:BAAANQAECgQIBQAAAA==.Fryhunter:BAAANQADCgMIAwABNQAECgIIAgACAAAAAA==.Frymeareaver:BAAANQAECgIIAgAAAA==.Frôstyz:BAAANQAECgEIAQAAAA==.',
Fu='Fublizz:BAAANQADCgUICgAAAA==.Fullbuster:BAAANQAECgIIAgAAAA==.Fumious:BAAANQAECgEIAQAAAA==.Fundus:BAAANQAECggIEwAAAA==.Fupachalupa:BAAANQADCggIEgAAAA==.Furrosty:BAAANQADCgcIBwAAAA==.Furrplay:BAAANQAECgEIAQAAAA==.Fuzzytotem:BAAANQADCgMIAwABNQAECgYIDQACAAAAAA==.',
Ga='Galahad:BAAANQADCggIFAAAAA==.Galaxxy:BAAANQAECgUIBgAAAA==.Galdace:BAAANQADCgEIAQABNQADCgYIDQACAAAAAA==.Ganathros:BAAANQAECgIIAgAAAA==.Ganzolo:BAAANQAECgEIAQAAAA==.Garaga:BAAANQAECgIIAgAAAA==.Garalivey:BAAANQADCggIFQAAAA==.Garutas:BAAANQADCggIEAAAAA==.Gavrack:BAAANQAECgYICgAAAA==.',
Ge='Geirrod:BAAANQADCggIFAAAAA==.Geißelseher:BAAANQAECgQIBQAAAA==.Gelbrath:BAAANQAECgYIBgAAAA==.Genevirerosa:BAAANQAECgUIBgAAAA==.Gerbsy:BAAANQAECgEIAQAAAA==.Gerenos:BAAANQADCgYICgABNQADCggIFAACAAAAAA==.Gettinlucky:BAAANQADCggIFgABNQAECgEIAQACAAAAAA==.',
Gh='Ghìs:BAAANQADCgEIAQABNQAFFAMIBAACAAAAAA==.',
Gi='Gier:BAAANQAECgEIAQAAAA==.Gisëla:BAAANQADCggIEwAAAA==.',
Gl='Glizzylizard:BAAANQAECgMIAwAAAA==.Gloopi:BAAANQADCgEIAQAAAA==.',
Gn='Gnas:BAACNQAFFIELAAMUAAYJXQ/DAACcAQAUAAUJwgrDAACcAQAVAAMJSBLUAAATAQA1AAQKgRkAAxUACQlQJLsBAC4DABUACQkiH7sBAC4DABQABwkkJJ0IAOACAAAA.Gnometzu:BAAANQAECgQIBgAAAA==.',
Go='Goldmage:BAAANQADCggICQAAAA==.Goldmaiden:BAAANQADCgUICgAAAA==.Gooba:BAAANQAECgMIAwAAAA==.Gothrogue:BAAANQAECgMIAwABNQAECgkJGQATAB8hAA==.',
Gr='Gramcraker:BAAANQADCgYIBgAAAA==.Gramz:BAAANQAFFAIIAgAAAA==.Grandidierit:BAAANQADCggIFQAAAA==.Grandy:BAAANQADCgEIAQAAAA==.Grandyded:BAAANQAECgYIBAAAAA==.Greenweaver:BAAANQAECgEIAQAAAA==.Grglgrgl:BAAANQAECgIIBQABNQAECgkJGgAEAF8iAA==.Grootleaf:BAAANQADCgQIBAAAAA==.Groudon:BAAANQAECgEIAQAAAA==.Grumpymage:BAAANQAECgEIAQAAAA==.',
Gu='Guenter:BAAANQADCggIDAAAAA==.Gunnèr:BAAANQADCgcIFgAAAA==.',
Gy='Gyattguard:BAAANQAECgYIDAAAAA==.',
Ha='Haat:BAAANQADCggIEQAAAA==.Halp:BAAANQADCgcICgAAAA==.Hanari:BAAANQAECgUICAAAAA==.Hannalieh:BAAANQADCgcIFAAAAA==.Happs:BAAANQAECggIEwAAAA==.Harvonice:BAAANQAECgIIAgABNQAECggIDQACAAAAAA==.',
He='Heallzzs:BAAANQADCggIEQAAAA==.Hekah:BAAANQAECgYICgAAAA==.Helhand:BAAANQADCgMIAwAAAA==.Helianna:BAAANQAECgIIAwAAAA==.Herbitarian:BAAANQADCgYICAAAAA==.Hexiboo:BAAANQAECgYIBwAAAA==.',
Hi='Hibbin:BAAANQADCgEIAQAAAA==.Highjinks:BAAANQADCgcIEQAAAA==.',
Ho='Hobohh:BAAANQADCgYIDQAAAA==.Hogmage:BAAANQADCgYIDAAAAA==.Hogmeat:BAAANQAECgQIBwAAAA==.Hojichapanna:BAAANQADCgUIBQAAAA==.Hollowpizza:BAAANQADCgcIBwABNQAECggIEwACAAAAAA==.Homy:BAAANQAECgQIBAAAAA==.Honeylily:BAABNQAFFIEKAAIFAAYJTw6cAAAKAgAFAAYJTw6cAAAKAgAAAA==.Honeystack:BAAANQADCgYICgAAAA==.Honorius:BAAANQAECgUIBgAAAQ==.Hoofpunch:BAAANQAECgEIAQAAAA==.Hotbloodead:BAAANQAECgIIAwAAAA==.Hotsalot:BAAANQADCgIIAgABNQADCgYIDAACAAAAAA==.Hover:BAAANQAECgIIAgAAAA==.',
Hu='Huffle:BAAANQADCgYICwAAAA==.Huhn:BAAANQADCggICgAAAA==.',
Hy='Hygeiah:BAACNQAFFIEJAAIKAAQJXRNgAQBkAQAKAAQJXRNgAQBkAQA1AAQKgRoAAgoACQn/HvgDAFIDAAoACQn/HvgDAFIDAAAA.Hygeiahh:BAAANQAECgYICQABNQAFFAQICQAKAF0TAA==.',
['Hé']='Héxx:BAAANQADCggIFwAAAA==.',
Ib='Ibukí:BAAANQAECgIIAgAAAA==.',
Ic='Icebearz:BAAANQADCgEIAQAAAA==.Icemonk:BAAANQADCgcICQAAAA==.Iceweasel:BAAANQAECgQIBgAAAA==.Ichinobu:BAAANQAECgQIBgAAAA==.Icyboy:BAAANQAECgQIBQAAAA==.Icye:BAAANQAECgQIBAABNQADCggIDwACAAAAAA==.Icypick:BAAANQADCgEIAQABNQAECgQIBgACAAAAAA==.',
Ii='Iinaa:BAAANQAECgMIAwAAAA==.',
Ik='Ikor:BAAANQADCgYIDAAAAA==.',
Il='Ilneval:BAAANQABCgMIAwAAAA==.Iludiin:BAAANQABCgIIAgAAAA==.Ilus:BAAANQADCgYIBgAAAA==.',
Im='Imogenn:BAAANQADCgcIEAAAAA==.',
In='Indigostorm:BAAANQADCgEIAQAAAA==.Inexa:BAAANQADCggICAAAAA==.Infynite:BAAANQADCgYIDgAAAA==.Inspriration:BAAANQADCgYIBgAAAA==.Insuendov:BAAANQAECgQICwAAAA==.Invisibae:BAAANQAECgQIBAAAAA==.',
Ir='Ironcask:BAAANQAECgUICgAAAQ==.',
Is='Isabelle:BAAANQAECgIIAgAAAA==.Isy:BAAANQADCggIDwAAAA==.Iszari:BAAANQAECgYICwAAAA==.',
Iv='Ivorye:BAAANQADCgUIDAAAAA==.',
Iw='Iwashiding:BAAANQAECgQIBAABNQAECgkJGAAGAFcfAA==.',
Ja='Jackyjack:BAAANQADCgEIAQAAAA==.Jackyshamz:BAAANQAECgEIAQAAAA==.Jammanjake:BAAANQADCgUIBQABNQAECgQIBgACAAAAAQ==.Jaspadin:BAAANQAFFAIIAgAAAA==.Jasperjade:BAAANQADCgMIBAAAAA==.Jaymanjyden:BAAANQADCgcIBwAAAA==.',
Je='Jekkyll:BAAANQAECgUIBgAAAA==.Jekylle:BAAANQAECgIIAgAAAA==.Jerichacane:BAAANQAECgEIAQAAAA==.Jesùs:BAAANQADCgYIDAAAAA==.Jetpacks:BAAANQADCggIFAAAAA==.Jetsura:BAAANQADCgUIBQAAAA==.',
Ji='Jihye:BAAANQADCgUIBQAAAA==.',
Jo='Joehealz:BAAANQAECgQIBQAAAA==.Joeydiaz:BAAANQADCgcICwAAAA==.Jollyballs:BAAANQAECgQIBgAAAA==.Jorkohnkohk:BAAANQABCgIIAgAAAA==.',
Ju='Judgment:BAAANQAECgIIAgAAAA==.Junpei:BAAANQADCggICAABNQAECgkJFgAWAHAjAA==.',
Ka='Kaelthar:BAAANQADCgYICgAAAA==.Kaesilius:BAAANQAECgEIAgAAAA==.Kaezon:BAAANQAECgEIAQAAAA==.Kaii:BAAANQADCgYIBgAAAA==.Kairii:BAAANQADCggIDgAAAA==.Kajoko:BAAANQAECgQIAgAAAA==.Kalastra:BAAANQADCggICAABNQAECggIDgACAAAAAA==.Kalaya:BAAANQADCgUICQAAAA==.Kalinia:BAAANQAECggIDgAAAA==.Kalyssa:BAAANQAECgYIBgABNQAECggIDgACAAAAAA==.Kalystia:BAAANQAECgQIBgAAAA==.Kantariss:BAAANQAFFAEIAgAAAA==.Kantp:BAAANQAECgcIDgABNQAFFAEIAgACAAAAAA==.Kantsu:BAAANQAECgUIBwAAAA==.Karaan:BAAANQADCgIIAwAAAA==.Kardev:BAAANQAECgcIDwAAAA==.Kardrick:BAAANQADCggIDQAAAA==.Kariik:BAAANQAECgcIBwABNQAECgcIDAACAAAAAA==.Karnport:BAAANQADCgUIBQAAAA==.Karrak:BAAANQAECgMIAwAAAA==.Katherla:BAAANQADCggICAAAAA==.Kayallie:BAAANQADCgIIAgAAAA==.',
Ke='Kegales:BAAANQAECgcIDAAAAA==.Keight:BAAANQAECgQIBgAAAA==.Kendrisite:BAEANQADCgMIAwAAAA==.Kenjii:BAAANQADCgYIBgAAAA==.Kenlock:BAAANQAECgIIAwAAAA==.Kennas:BAAANQAECgEIAQAAAA==.Kennypaladin:BAAANQADCggIFAAAAA==.Kerelyse:BAAANQADCgQIBAAAAA==.Keskers:BAAANQAECgMIAwAAAA==.',
Kh='Khake:BAAANQAECgIIAgAAAA==.Khalani:BAAANQAECgIIAgAAAA==.Khard:BAAANQADCgUIBQAAAA==.Khilea:BAAANQAECgIIAgAAAA==.Khorm:BAAANQAECgEIAQAAAA==.',
Ki='Kierstin:BAAANQAECgQIBgAAAA==.Kijay:BAAANQAECgQIBgAAAA==.Kiji:BAAANQADCgcIBwAAAA==.Kimishima:BAAANQAECgMIBAAAAA==.Kitsunami:BAAANQAECgUIBgAAAA==.Kittenlove:BAAANQADCggIDwAAAA==.Kittew:BAABNQAECoEZAAITAAkJHyFpAQC0AwATAAkJHyFpAQC0AwAAAA==.Kiwipox:BAAANQAFFAIIAgAAAA==.Kiwî:BAAANQAECgcIDwAAAA==.',
Kj='Kj:BAAANQAECgQIBwAAAA==.',
Kk='Kkilljoy:BAAANQADCgUIBQAAAA==.Kkj:BAAANQADCgYIBwAAAA==.',
Kl='Kljy:BAAANQAECgEIAQAAAA==.',
Kn='Knai:BAAANQAECgMIAwAAAA==.',
Ko='Komak:BAAANQADCgcIBwAAAA==.Koravellium:BAAANQAFFAIIAgAAAA==.Korìì:BAAANQADCggIEwAAAA==.Koume:BAAANQAECgIIAgAAAA==.',
Kr='Kraison:BAAANQAECgIIAgAAAA==.Krayola:BAAANQADCggIEwAAAA==.Krayzon:BAAANQADCgQIBAABNQAECgIIAgACAAAAAA==.Kriocyl:BAAANQADCggIDgAAAA==.Kryllian:BAAANQADCgYICwAAAA==.Kryzak:BAAANQADCggIFAAAAA==.',
Ku='Kudria:BAAANQADCgcIBwAAAA==.Kusanagisama:BAAANQADCggIDwAAAA==.Kushmints:BAAANQAECgQIBgAAAQ==.Kutham:BAAANQAECgUICAAAAA==.Kuula:BAAANQADCgQIBAAAAA==.',
Ky='Kychan:BAABNQAECoEXAAMWAAkJCx6pCQAXAwAWAAkJCx6pCQAXAwAXAAEJuQNxGABEAAAAAA==.Kynada:BAAANQAECgEIAQAAAA==.Kyora:BAAANQADCggICAABNQADCggIDgACAAAAAA==.Kyy:BAAANQAECgIIAgABNQAECgkJFwAWAAseAA==.',
La='Labrat:BAAANQAECgQIBAAAAA==.Lacutis:BAAANQADCgUICAAAAA==.Lamona:BAAANQADCgYICAAAAA==.Lanille:BAAANQAECggIEwAAAA==.Lanli:BAAANQADCggIFAABNQAECggIEwACAAAAAA==.Large:BAAANQADCgIIAgAAAA==.Larissah:BAEANQADCggICAABNQAECggIEgACAAAAAA==.Lastirishman:BAAANQADCgYIBgAAAA==.Latondra:BAAANQAECgEIAQABNQAECggIEwACAAAAAA==.Lavendardoe:BAAANQADCgYIEAAAAA==.Lawra:BAAANQADCgIIAgAAAA==.Lazuriel:BAAANQAECgMIAwAAAA==.',
Lb='Lb:BAAANQAECgQIBQAAAA==.',
Le='Learissa:BAAANQADCgYIDwAAAA==.Leharas:BAAANQAECggIEAAAAA==.Leharthas:BAAANQAECgIIAgABNQAECggIEAACAAAAAA==.Lejeune:BAAANQADCgYIEAAAAA==.Lenana:BAAANQAECgcIBwAAAA==.Lesgrossman:BAAANQADCgUICQAAAA==.Levv:BAAANQAECgEIAQABNQADCggIDQACAAAAAA==.Lexaprohoe:BAAANQAECgIIAwAAAA==.Lexus:BAAANQADCgEIAQAAAA==.',
Lh='Lhpitts:BAAANQADCggIEwAAAA==.',
Li='Lifestalk:BAAANQAECgQIBAAAAA==.Lightlance:BAAANQADCggICAAAAA==.Lightmunch:BAAANQADCgQIBAABNQAECgkJGAAGAFcfAA==.Lilasta:BAAANQAECgUIBQAAAA==.Lillers:BAAANQAECgQIBQAAAA==.Linda:BAAANQAECgEIAQAAAA==.Livedøg:BAAANQAECgcIDQAAAA==.Lizardwizard:BAAANQADCggIDgABNQAFFAIIAgACAAAAAA==.',
Lj='Ljn:BAAANQADCgQIBwAAAA==.',
Lo='Lockstock:BAAANQADCgEIAQAAAA==.Locktober:BAAANQAECgcIDgAAAA==.Lom:BAAANQAECgIIAgAAAA==.Lomuur:BAAANQAECgIIAwAAAA==.Lonzso:BAAANQAECgEIAQAAAA==.Lorcàn:BAAANQADCggIDQAAAA==.Loriat:BAAANQAECgIIAgAAAA==.Lorthan:BAAANQAECgQIBgAAAA==.Lostdruid:BAAANQAECgEIAgAAAA==.Loteksdruid:BAAANQAECgYIBgABNQAFFAYICwAYAOscAA==.Lotekshunter:BAABNQAFFIELAAIYAAYJ6xxgAABbAgAYAAYJ6xxgAABbAgAAAA==.Louerre:BAAANQAECgQIBgAAAA==.Loyolla:BAAANQADCgYICgAAAA==.Lozenn:BAAANQAECgEIAQAAAA==.',
Lu='Luagarb:BAAANQABCgYICAABNQAECgcIEAACAAAAAA==.Lucie:BAAANQADCgYIDQAAAA==.Lucinde:BAAANQADCggIFQAAAA==.Luckysdruid:BAAANQAECgEIAQAAAA==.Luminescent:BAAANQAECgUIBwAAAA==.Lumineus:BAAANQAECgIIAwAAAA==.Lunaelvira:BAAANQAECgIIAgAAAA==.Lunamina:BAAANQAECgMIAwAAAA==.Lunathiicc:BAAANQADCgYIBgAAAA==.Lunith:BAAANQADCgYIEAAAAA==.Lurai:BAAANQAECgUIBgAAAA==.',
Ly='Lyletoa:BAAANQAECgMIAwAAAA==.Lyphia:BAAANQABCgQIBAAAAA==.Lyssera:BAAANQADCgcIDAAAAA==.',
['Lö']='Lövis:BAAANQAECgMIAwAAAA==.',
Ma='Maceofbase:BAAANQAECgYICAAAAA==.Maemis:BAAANQAECgUICAAAAA==.Magdalyne:BAAANQADCgYIBgAAAA==.Magiczeejay:BAAANQABCgQIBgAAAA==.Magmaragma:BAAANQAECggIEwAAAA==.Majishin:BAAANQAECgQIBgAAAA==.Makuta:BAAANQADCgIIAgAAAA==.Malibo:BAAANQAECgQIBgAAAA==.Malloc:BAAANQAECgEIAgAAAA==.Malmack:BAAANQAECgQIBQAAAA==.Manutebol:BAAANQAECgEIAQAAAA==.Marhayho:BAAANQADCggIDgAAAA==.Mariecrystal:BAAANQADCggIEwAAAA==.Marragma:BAAANQADCggIDQABNQAECggIEwACAAAAAA==.Marsbars:BAAANQAECgUIBgAAAA==.Matty:BAAANQAECgQIBAAAAA==.Mazrae:BAAANQADCgYIEAAAAA==.',
Mc='Mcbirdi:BAAANQADCgcIBwAAAA==.Mccheesee:BAAANQADCgIIAgAAAA==.Mcnonal:BAAANQAECgMIBAAAAA==.',
Me='Meatshiëld:BAAANQADCggIEwAAAA==.Meech:BAAANQAECgIIAgAAAA==.Megalopizza:BAAANQAECggIEwAAAA==.Mennalich:BAAANQADCgQIBAABNQAECgEIAQACAAAAAA==.Mercutios:BAAANQADCgcIDAAAAA==.Mercyarrow:BAAANQADCgYIDQAAAA==.Merlotta:BAAANQADCgYIDQAAAA==.Mershy:BAAANQAECgMIAwAAAA==.Merìngue:BAAANQADCggIFAAAAA==.Meshuntress:BAAANQAECgQIBAAAAA==.Meslaandra:BAAANQADCgQIBAABNQAECgQIBAACAAAAAA==.Metamorftis:BAAANQADCgUIBQABNQAECgMIAwACAAAAAA==.Meterio:BAAANQAECgQIBAAAAA==.Methelin:BAAANQABCgIIAgAAAA==.Meyna:BAAANQADCgcIEAAAAA==.',
Mi='Miand:BAAANQADCgUIBgABNQAECgIIAgACAAAAAA==.Micheal:BAAANQAECgEIAQAAAA==.Mictain:BAAANQADCgYIEQAAAA==.Mikeg:BAAANQAECgQIBgAAAA==.Mikobroods:BAAANQAECgEIAQAAAA==.Millandra:BAAANQADCgYIDAAAAA==.Millificent:BAAANQAECgYIDQAAAA==.Minató:BAAANQADCgYIBgAAAA==.Miraclemax:BAAANQAECgEIAQAAAA==.Misbehavin:BAAANQAECgcIEAAAAA==.Mistlily:BAAANQAECgYIBgAAAA==.Misuse:BAAANQADCgcIBgAAAA==.Mitsuba:BAAANQAECgEIAQAAAA==.',
Mo='Moa:BAAANQADCggIEwAAAA==.Mocii:BAAANQADCgQIBQAAAA==.Moksee:BAAANQADCggICAAAAA==.Moldram:BAAANQAECgIIAwAAAA==.Momoney:BAAANQADCgYICgAAAA==.Monadox:BAAANQADCgUICgAAAA==.Monthaniel:BAAANQAECgcIEgAAAA==.Moochpriest:BAAANQAECgcIEAAAAA==.Moocowjr:BAAANQAECgQIAwAAAA==.Moonfel:BAAANQAECgQIBAABNQAECgcIEQACAAAAAA==.Mooni:BAAANQADCggIEwAAAA==.Moontide:BAAANQADCggIFAAAAA==.Moorg:BAAANQADCgYICAAAAA==.Mora:BAAANQAECgUICQAAAA==.Morgannion:BAAANQADCgYIDgAAAA==.Morgathiel:BAAANQAECgEIAQAAAA==.Moroth:BAAANQAECgIIAgAAAA==.Motogrowl:BAAANQADCgMIAwAAAA==.',
Ms='Mschel:BAAANQADCgYICAAAAA==.Mstroomtoyou:BAAANQADCgQIBQAAAA==.Mstrshredder:BAAANQADCgEIAQAAAA==.',
Mu='Muffens:BAAANQABCgIIAgAAAA==.Mugastrasza:BAAANQADCgUIBQAAAA==.Mungle:BAAANQAECgMIAwAAAA==.Mungler:BAAANQADCgIIAgAAAA==.Murdisnt:BAAANQADCgEIAQABNQAECgcIDQACAAAAAA==.Murdiss:BAAANQADCgIIAgAAAA==.Murwar:BAAANQAECgcIDQAAAA==.Musashiden:BAAANQAECgcIDwAAAA==.',
My='Mydrood:BAAANQAECgQIBAAAAA==.Myrabelle:BAAANQAECgIIAgAAAA==.Mythious:BAAANQADCgUIBwAAAA==.',
['Mà']='Màrasi:BAAANQADCggICAAAAA==.',
Na='Naaru:BAAANQAECgIIAgAAAA==.Naerina:BAAANQAECgQIBgAAAA==.Nakeam:BAAANQAECgUIBgAAAA==.Nakiasha:BAAANQABCgYICQAAAA==.Nallyssa:BAAANQAECgEIAQAAAA==.Namaah:BAAANQADCgYICgAAAA==.Namaria:BAAANQADCgYICwAAAA==.Narset:BAAANQAECgYIBwAAAA==.Nash:BAAANQADCgUIBQAAAA==.Naturestorm:BAAANQADCgYIBgABNQADCgYIBgACAAAAAA==.Nayra:BAAANQAECgMIAwAAAA==.Nazjana:BAAANQAECgYIDAAAAA==.',
Ne='Neandra:BAAANQADCggIEAAAAA==.Necrox:BAAANQADCgYIDQAAAA==.Neinlawst:BAAANQADCgYICgAAAA==.Neorawr:BAAANQAECgUIBgAAAQ==.Nereana:BAAANQADCgUICgAAAA==.Neriel:BAAANQAECgUIBgAAAA==.Nero:BAAANQADCgUIBQABNQAECgYICAACAAAAAA==.Nerzhül:BAAANQAECgIIAgAAAA==.Neuromance:BAAANQAECgEIAQAAAA==.Nev:BAAANQAECgcICwAAAA==.Nevielaian:BAAANQAECgUIBQABNQAECgcICwACAAAAAA==.',
Ni='Niamhaisling:BAAANQADCgQIBAAAAA==.Nightcastar:BAAANQAECgQIBgAAAA==.Nightgem:BAAANQAECgQIDAAAAA==.Nightmen:BAAANQAECgMIAwAAAA==.Niiknox:BAAANQAECgEIAQAAAA==.Nikorai:BAAANQADCgYICgAAAA==.Nimka:BAAANQADCgYIDAAAAA==.Ninevolts:BAAANQAECgEIAQAAAA==.Nintern:BAAANQAFFAIIBAAAAA==.Ninturn:BAAANQAECgcIBgABNQAFFAIIBAACAAAAAA==.Nirileene:BAAANQAECgQIBQAAAA==.Nissangtr:BAAANQADCgcIEgAAAQ==.Niven:BAAANQADCggIFQAAAA==.',
No='Nocoifos:BAAANQADCgQIBgAAAA==.Noemi:BAAANQADCggIFgAAAA==.Nonoka:BAAANQAECgEIAQABNQAECgQICAACAAAAAA==.Nooriie:BAAANQAECgEIAQAAAA==.Noperino:BAAANQADCgYIDAAAAA==.Norallitha:BAAANQADCgcIBwAAAA==.Norimort:BAAANQADCgEIAQABNQADCgYICwACAAAAAA==.Norp:BAAANQADCgQIBAAAAA==.Noru:BAAANQADCgUIBQAAAA==.',
Nu='Nuck:BAAANQAECgcICgAAAQ==.Nuckchoris:BAAANQAECgYIBgABNQAECgcICgACAAAAAQ==.Nuckhunt:BAAANQADCgIIAgABNQAECgcICgACAAAAAQ==.Nucks:BAAANQADCgYIBgABNQAECgcICgACAAAAAQ==.Nullpizza:BAAANQAECgEIAQABNQAECggIEwACAAAAAA==.Numllöck:BAAANQABCgQIBAAAAA==.Nurgle:BAAANQADCgYIDAAAAA==.Nursing:BAAANQABCgQIBAAAAA==.',
Ny='Nykole:BAAANQADCgUIBwAAAA==.Nyxdruid:BAAANQADCgYIBwAAAA==.',
Nz='Nzot:BAAANQAECgEIAQAAAA==.',
Ob='Obeone:BAAANQAECgQIBAAAAA==.Obex:BAAANQADCgEIAQABNQAECgQIBAACAAAAAA==.Obus:BAAANQAECgEIAQAAAA==.Obviousness:BAAANQAECgcIDwAAAA==.',
Ol='Ollivander:BAAANQADCgYIEgAAAA==.Olmec:BAAANQADCgUICgAAAA==.Olmeck:BAAANQADCgQIBQAAAA==.Olugbeja:BAAANQADCggIFQAAAA==.',
Om='Omnomnomnomy:BAAANQAECgUIBwAAAA==.',
Oo='Oofie:BAAANQADCgYICwAAAA==.',
Or='Ormazd:BAAANQADCgUICAAAAA==.',
Os='Oshoot:BAAANQAECgQIBAAAAA==.Osiyo:BAAANQADCgQIBQABNQADCgUICAACAAAAAA==.',
Ou='Outz:BAAANQADCgIIAgAAAA==.',
Pa='Pacificia:BAAANQAECgMIAwAAAA==.Padt:BAAANQAECgQIBAAAAA==.Paladaes:BAAANQADCgMIBgAAAA==.Palanetta:BAAANQADCgcIBwAAAA==.Pallyhax:BAAANQAECgQIBQAAAA==.Pallytickles:BAAANQADCgQIBwAAAA==.Paltari:BAAANQAECgEIAgAAAA==.Panana:BAAANQAECgEIAQAAAA==.Pandaale:BAAANQADCggIFAAAAA==.Pandurin:BAAANQADCgYICAAAAA==.Pannok:BAAANQADCgIIAwAAAA==.Panzer:BAAANQADCgcIEQAAAA==.Papajohnsceo:BAAANQAECggIEwAAAA==.Papamnk:BAAANQADCggICAAAAA==.Papatotem:BAAANQAECgQIBgAAAA==.Parzival:BAAANQADCgEIAQAAAA==.Pathoren:BAAANQAECgQIBQAAAA==.Pawzja:BAAANQAECgYICwAAAA==.',
Pe='Pegasus:BAAANQAECgQIBQAAAA==.Pepsired:BAAANQAECgcIEgAAAA==.',
Pf='Pfezwik:BAAANQAECgcIDwAAAA==.',
Ph='Phlygurl:BAAANQAECgIIAgAAAA==.Phonng:BAAANQADCgUICAAAAA==.Phorquaaray:BAAANQADCgYIEAAAAA==.',
Pi='Pitu:BAAANQAECgIIAwAAAA==.',
Pl='Placid:BAAANQAECgYIDAAAAQ==.Plixxy:BAAANQAECgQIBgAAAA==.',
Po='Pokez:BAAANQADCgIIAgAAAA==.Poobies:BAAANQADCgcIBwAAAA==.',
Pr='Primenecro:BAAANQADCgYICgAAAA==.Pristitute:BAAANQAECgQIBAAAAA==.Prodigal:BAAANQADCgQIBAABNQAECgMIAwACAAAAAA==.Providence:BAAANQAECgQIBQAAAA==.',
Ps='Psychdragon:BAAANQAECgQIBAAAAA==.Psylocin:BAAANQABCgQIBgAAAA==.',
Pu='Puddyng:BAAANQAECgUIBgAAAA==.Puflight:BAAANQAECgEIAQAAAA==.Pukasama:BAAANQADCgYIBgAAAA==.Puncake:BAAANQAECgUIBgAAAA==.Punemonsune:BAAANQADCgYICwAAAA==.Purzalot:BAAANQADCgYIBgABNQAECgkJFwAOAAcZAA==.',
Qu='Quava:BAABNQAECoEXAAQUAAkJpCN8CwC5AgAUAAcJlSJ8CwC5AgAVAAYJHyEpCQAwAgAZAAIJ0CToCADKAAAAAA==.Queniecallie:BAAANQADCgMIAwAAAA==.Quintilian:BAABNQAECoEXAAIaAAkJtSU8AADgAwAaAAkJtSU8AADgAwAAAA==.Quìnn:BAAANQAECgIIAgAAAA==.',
Qw='Qwelzee:BAAANQABCgEIAQAAAA==.',
Ra='Racktar:BAAANQADCgcIEwAAAA==.Rada:BAAANQADCgEIAQABNQADCgUIDQACAAAAAA==.Radaski:BAAANQADCgUIDQAAAA==.Raines:BAAANQADCgMIBQAAAA==.Rainnshine:BAAANQAECgMIAwAAAA==.Rakdos:BAAANQADCgcIDQAAAA==.Rakkel:BAAANQADCgUIBQABNQAECgYIBwACAAAAAA==.Ramohna:BAAANQADCgIIAgAAAA==.Ranpha:BAAANQAECgEIAgAAAA==.Rathanin:BAAANQADCgUIBQAAAA==.Razar:BAAANQAECgEIAQAAAA==.',
Re='Reapersdeath:BAAANQADCgQICQAAAA==.Redhydra:BAAANQAECgQIBAAAAA==.Redmagic:BAAANQAECgUIBwAAAA==.Reera:BAAANQAECgIIAgAAAA==.Reiyaya:BAAANQAECgQICAAAAA==.Remetik:BAAANQADCgEIAQAAAA==.Remma:BAAANQAECgEIAQAAAA==.Reneli:BAAANQAECgUICwAAAA==.Renillia:BAAANQADCgYIAwAAAA==.Retrovision:BAAANQAECgYIBgAAAA==.Reyn:BAAANQADCggICgAAAA==.Rezik:BAABNQAFFIELAAINAAYJVhyzAABOAgANAAYJVhyzAABOAgAAAA==.Rezin:BAAANQADCgcIEAAAAA==.Rezzmonk:BAAANQAECgcIDgABNQAFFAYICwANAFYcAA==.',
Rh='Rhaellä:BAAANQAECgEIAQAAAA==.Rhale:BAAANQAECgEIAQABNQAFFAYICwAQABgdAA==.Rhalladin:BAABNQAFFIELAAIQAAYJGB1TAABXAgAQAAYJGB1TAABXAgAAAA==.Rhane:BAAANQADCgYIBgAAAA==.',
Ri='Riccio:BAAANQAECgQIBgAAAA==.Richhomiecon:BAAANQAECgUICgAAAA==.Rikon:BAAANQADCggIDwAAAA==.Rince:BAABNQAECoEVAAIMAAkJzhzvBQAaAwAMAAkJzhzvBQAaAwAAAA==.Rissarî:BAAANQADCgUIBQABNQAECgMIAwACAAAAAA==.Rivars:BAAANQAECgQICgAAAA==.Riyyah:BAAANQAECgQIBwAAAA==.',
Rj='Rjysk:BAAANQADCggIFAAAAA==.',
Ro='Rocklobsta:BAAANQADCgYIBwABNQAECgEIAQACAAAAAA==.Rogüe:BAAANQAECgEIAQAAAA==.Roknar:BAAANQADCggICAAAAA==.Rolipol:BAAANQADCgYIDQAAAA==.Rootfang:BAAANQAECgUIBwAAAA==.Roshy:BAAANQADCgIIAgAAAA==.Rowynne:BAAANQADCgYICgAAAA==.Royaldkplz:BAAANQAECgMIAwABNQAECgYIBwACAAAAAA==.',
Ry='Ryhasia:BAAANQAECgQIBAAAAA==.',
['Râ']='Râiny:BAAANQADCgYICwAAAA==.',
['Rä']='Räine:BAAANQADCgIIAwAAAA==.',
Sa='Saibric:BAAANQAECgEIAQAAAA==.Sailrpluto:BAAANQAECgYIDAAAAA==.Saleh:BAAANQAECgIIAgAAAA==.Salidus:BAAANQADCggIFAAAAA==.Sallumash:BAAANQADCgYIEQAAAA==.Salos:BAAANQADCgcIEgAAAA==.Salvetheron:BAAANQABCgYICAAAAA==.Sando:BAAANQADCgUICgAAAA==.Sanglant:BAAANQADCgcIFAAAAA==.Sanobu:BAAANQAECgQIBgAAAA==.Saphilock:BAAANQAFFAIIAgAAAA==.Saphmage:BAAANQADCgYIBgAAAA==.Saraubs:BAAANQAECgMIBAAAAA==.Sariona:BAAANQADCgYIBgAAAA==.Sarsarran:BAAANQADCgYICgAAAA==.Saryona:BAAANQAECgUIBgAAAA==.Saylavee:BAAANQAECgUIBgAAAA==.',
Sc='Scandium:BAAANQAECgcICgAAAA==.Schuetzy:BAAANQAECgQIBgAAAA==.Scibrew:BAAANQAECgIIAgAAAA==.Scndamndmnt:BAAANQADCgYIEAAAAA==.Scuttlebut:BAAANQADCgYICgAAAA==.Scytal:BAAANQAECgQIBgAAAA==.',
Se='Seacreamy:BAAANQAECgUIBwAAAA==.Seanald:BAEBNQAECoEXAAIIAAkJUB0KCAD/AgAIAAkJUB0KCAD/AgAAAA==.Selaith:BAAANQADCgYIDAAAAA==.Seradriel:BAAANQABCgIIAwAAAA==.Seres:BAAANQAECgEIAQAAAA==.Serix:BAAANQAFFAEIAQAAAA==.',
Sh='Shaddydaddy:BAAANQADCggIFAAAAA==.Shadeey:BAAANQADCgcIEwAAAA==.Shadowdawn:BAAANQADCgYIBgAAAA==.Shadoweater:BAAANQAECgYIDAAAAA==.Shadowyn:BAAANQABCgQIBAAAAA==.Shadyhermit:BAAANQAECgQIBgAAAA==.Shaeline:BAAANQADCgIIAgAAAA==.Shalanta:BAAANQAECgEIAQAAAA==.Shamazzor:BAAANQADCgMIBAAAAA==.Shaminater:BAAANQAECgEIAQAAAA==.Shamysparrow:BAAANQADCgMIAwAAAA==.Shanton:BAEANQADCggICAABNQAECggIEwACAAAAAA==.Sharkeey:BAAANQAECgcIEAAAAA==.Shatan:BAAANQADCgEIAQAAAA==.Shawnicon:BAAANQADCgQIBAAAAA==.Shayne:BAAANQAECgcIEQAAAA==.Sheesh:BAAANQADCgIIAgAAAA==.Shestrouble:BAAANQAECgcIDwAAAA==.Shezmu:BAAANQADCgYIBgAAAA==.Shezz:BAAANQADCgYIBgAAAA==.Shezzam:BAAANQADCgIIAgAAAA==.Shezzus:BAAANQADCgIIAgAAAA==.Shinikes:BAAANQAECgEIAQABNQAECgEIAQACAAAAAA==.Shinryu:BAAANQABCgIIAgAAAA==.Shinyterp:BAAANQAECgcIEAAAAA==.Shirokuma:BAAANQAECgEIAQAAAA==.Shivarezz:BAAANQADCgUIBQABNQADCgYIBgACAAAAAA==.Shocknhaunt:BAAANQABCgIIBAAAAA==.Shockserker:BAAANQADCgYICgAAAA==.Shootinbeers:BAAANQADCgEIAQABNQADCggIDQACAAAAAA==.Shryk:BAAANQADCgQIBAAAAA==.Shuragos:BAABNQAECoEYAAIGAAkJVx8/AgBbAwAGAAkJVx8/AgBbAwAAAA==.Shxne:BAAANQAECgEIAQAAAA==.Shyla:BAAANQADCgcIEAAAAA==.Shyvenei:BAAANQAECgQIBgAAAA==.',
Si='Sight:BAAANQAECgEIAQAAAA==.Silverfur:BAAANQAECgcIDwAAAQ==.Silverstar:BAAANQADCgcIEQAAAA==.Singebeard:BAAANQAECgUIBwAAAA==.Sitrie:BAAANQADCgIIAgABNQADCggIDQACAAAAAA==.Sixtynineuwu:BAAANQADCgYIBgAAAA==.',
Sk='Skael:BAAANQADCgYICQAAAA==.Skarnax:BAAANQADCgYICQAAAA==.Skibidi:BAAANQAECgEIAQAAAA==.Skout:BAAANQADCgYIBgAAAA==.',
Sl='Slipshod:BAAANQADCgEIAQAAAA==.Slowbow:BAAANQABCgEIAQAAAA==.Slyferrain:BAEANQAECgIIAwAAAA==.',
Sn='Sneeze:BAAANQAECgMIAwAAAA==.Snerbert:BAAANQADCgUIBQABNQADCgYIBwACAAAAAA==.Snuggle:BAAANQAECgYIDAAAAQ==.Snuggledooms:BAAANQAECgEIAQAAAA==.Snôwy:BAAANQAECgEIAQAAAA==.',
So='Sofiocon:BAAANQAECgYIBwAAAA==.Soknee:BAAANQAECgIIAgAAAA==.Solshear:BAAANQAECgEIAQAAAA==.Soshha:BAAANQAECgQIBAAAAA==.Sothos:BAAANQADCgcIBwAAAA==.Soulfyyre:BAAANQABCgIIAgAAAA==.Soül:BAAANQAECgIIAgAAAA==.',
Sp='Spcialblonde:BAAANQAECggIEQAAAA==.Spilledmilk:BAAANQAECgUIBwAAAA==.Spiritbomb:BAAANQADCgMIAwAAAA==.Spiritgemmed:BAAANQAECgQICAAAAA==.Spiritronix:BAAANQADCgcIBwAAAA==.Sprunklez:BAAANQADCggICAABNQAECgkJGQAMABcdAA==.Spyglys:BAABNQAFFIEJAAIHAAQJXRtaAgBrAQAHAAQJXRtaAgBrAQAAAA==.Spysham:BAAANQADCgcIBwAAAA==.',
Sq='Squirmie:BAAANQADCggICAAAAA==.Squirmys:BAAANQAECggIEwAAAA==.',
Ss='Sspepsi:BAAANQAECgEIAQAAAA==.',
St='Stalis:BAAANQAECgUIBgAAAA==.Starballer:BAABNQAECoEZAAIDAAkJ+SVSAQDZAwADAAkJ+SVSAQDZAwAAAA==.Stashamanda:BAAANQAECgEIAQAAAA==.Staticfury:BAAANQAECgQIBAAAAA==.Sterilized:BAAANQADCgYIDQAAAA==.Stonedtotem:BAAANQAECgQIBAAAAA==.Stormdraft:BAAANQADCggIFAAAAA==.Stormen:BAAANQADCggIDgABNQAECgMIAwACAAAAAA==.Stormenstout:BAAANQABCgQIBgABNQAECgMIAwACAAAAAA==.Struct:BAAANQADCgMIAwABNQAECgEIAgACAAAAAA==.Strìkê:BAAANQAECgQIBAAAAA==.',
Su='Subshammy:BAAANQADCgMIAQAAAA==.Suidt:BAAANQAFFAIIAgAAAA==.Sunkist:BAAANQAECgUIBwAAAA==.Superchicken:BAAANQADCgYIBgAAAA==.Supersoaker:BAAANQABCgIIAgAAAA==.Superspammer:BAAANQABCgEIAQAAAA==.Surginghole:BAAANQADCgcIBwAAAA==.',
Sw='Swaldar:BAAANQADCgYIBgAAAA==.Swen:BAAANQAECgYIDQAAAA==.Swiatek:BAAANQAECgUIBwAAAA==.Swoozerker:BAAANQAECgMIBAAAAA==.',
Sy='Syberis:BAAANQABCgMIBQAAAA==.Sydal:BAAANQADCgQIBQAAAA==.Syk:BAAANQADCgUIBQAAAA==.Sylmara:BAAANQAECgEIAgAAAA==.Sylvaron:BAAANQAECggIEQAAAA==.Syy:BAEANQAECgQIBgAAAA==.',
['Sì']='Sìrænus:BAAANQADCgcIBwAAAA==.',
['Sÿ']='Sÿnova:BAAANQADCgcICwAAAA==.',
Ta='Tabi:BAAANQAECgEIAQAAAA==.Tagart:BAAANQADCgYIBwAAAA==.Taichi:BAAANQAECgEIAQABNQAECgkJGAAGAFcfAA==.Talanok:BAAANQADCgcICQAAAA==.Tallerazure:BAAANQADCggIFQAAAA==.Tanadin:BAAANQADCgQIBQAAAA==.Tanknight:BAAANQAECgQIBgAAAA==.Tanksinatra:BAAANQADCgIIAgAAAA==.Tarhasjr:BAAANQAECgQIBQAAAA==.Tarrondor:BAAANQADCgYIBgAAAA==.Tawonka:BAAANQADCgUICAAAAA==.Taxingr:BAAANQADCgYICgABNQAECgEIAQACAAAAAA==.Taxings:BAAANQADCgUIBQABNQAECgEIAQACAAAAAA==.Taydan:BAAANQAECgEIAQAAAA==.Tazon:BAAANQAECgMIBQAAAA==.',
Te='Tencatty:BAAANQADCgcICgAAAA==.Tezzerret:BAAANQAECgUIBQAAAA==.Teâ:BAABNQAECoEXAAIKAAkJHxltBgAEAwAKAAkJHxltBgAEAwABNQAFFAYICQATADQRAA==.',
Th='Tharus:BAAANQADCgUIBQAAAA==.Thaurt:BAAANQADCgEIAQABNQADCggIDAACAAAAAA==.Thaurtt:BAAANQADCggIDAAAAA==.Thealogy:BAAANQAECgQIBQAAAA==.Thedadlife:BAAANQAECgEIAQAAAA==.Theirin:BAAANQADCgMIBQAAAA==.Theodora:BAAANQADCgcIEAAAAA==.Thephuk:BAAANQADCgYIBgAAAA==.Thisisatestt:BAABNQAFFIEJAAIbAAYJICIhAAB8AgAbAAYJICIhAAB8AgAAAA==.Thordun:BAAANQADCgYIDAAAAA==.Thorimbor:BAAANQADCgcIEQAAAA==.Thormir:BAAANQADCgUIBwAAAA==.Thoterella:BAAANQAECgEIAQAAAA==.Threetrees:BAAANQADCgQIBAAAAA==.Throckmorten:BAAANQADCggIFQAAAA==.Thundercrap:BAAANQADCgIIAgABNQAECgIIAgACAAAAAA==.Thundershout:BAAANQAECgEIAQABNQAECgcIEQACAAAAAA==.Thymbal:BAAANQAECgUICAAAAA==.Thót:BAAANQAECgMIAwAAAA==.',
Ti='Tianis:BAAANQADCgcIDgAAAA==.Tiburias:BAAANQADCgcICQABNQAECgUIBgACAAAAAQ==.Tidelwave:BAAANQABCgIIAgABNQADCggIEwACAAAAAA==.Tidepode:BAAANQAFFAEIAQAAAQ==.Timbowthy:BAAANQADCggICAABNQAECgQIBwACAAAAAA==.Timoathy:BAAANQAECgQIBwAAAA==.Tinslee:BAAANQADCggIEAAAAA==.Tinykilla:BAAANQADCggIFQAAAA==.Tirarose:BAAANQAECgEIAQAAAA==.Tiric:BAAANQAECgMIAwAAAA==.Tisphonie:BAAANQAECgMIAwAAAA==.',
Tn='Tnugz:BAAANQABCgQIBAABNQAECgMIAwACAAAAAA==.',
To='Toasttamer:BAAANQADCggIFQAAAA==.Todeathend:BAAANQAECgQIBAAAAA==.Toji:BAAANQADCgYIBgAAAA==.Tomosvelgr:BAAANQAECgEIAQAAAA==.Tonediary:BAABNQAFFIELAAIOAAYJTRx+AABYAgAOAAYJTRx+AABYAgAAAA==.Tonynugz:BAAANQAECgMIAwAAAA==.Toodems:BAAANQAECgIIAgAAAA==.Toothbrushs:BAAANQADCggIFQAAAA==.Tortillaboy:BAAANQAECgMIAwAAAA==.Torzha:BAAANQADCgcIEwAAAA==.Tot:BAAANQAECgEIAQAAAA==.Totempalooza:BAAANQADCgEIAQAAAA==.',
Tr='Trainteph:BAAANQADCgYIDwAAAA==.Traxeon:BAAANQADCgcIDwAAAA==.Trece:BAAANQADCgYIBgABNQAECgIIAgACAAAAAA==.Tredici:BAAANQAECgIIAgAAAA==.Treefïddy:BAAANQADCgIIAgABNQAECgMIAwACAAAAAA==.Trekonz:BAAANQAECgIIAgAAAA==.Tridiah:BAAANQAECgQIBgAAAA==.Trinzen:BAAANQADCggIEgAAAA==.Truok:BAAANQAECgQIBgAAAA==.',
Ts='Tsaphiel:BAAANQAECgQIBQAAAA==.Tsaps:BAAANQAECgIIAwAAAA==.',
Tt='Ttrag:BAAANQADCggIDwAAAA==.',
Tu='Tubtaro:BAAANQADCgIIAgAAAA==.Tuckerdeath:BAAANQADCgUICQAAAA==.Tuffey:BAAANQADCgYIEAAAAA==.Tunod:BAAANQAFFAIIAgAAAA==.Turpentyne:BAAANQAECgMIAwAAAA==.',
Tw='Twixxmonk:BAAANQADCgIIAgAAAA==.Twohander:BAAANQADCgIIAgAAAA==.Twó:BAAANQADCgMIAwAAAA==.',
Tx='Txd:BAABNQAFFIEJAAITAAYJNBF1AAAgAgATAAYJNBF1AAAgAgAAAA==.',
Ty='Ty:BAAANQADCgIIAgAAAA==.Tyrent:BAAANQADCggIEgAAAA==.',
['Tã']='Tãnk:BAAANQADCgEIAQAAAA==.',
Ug='Uglie:BAAANQADCgcICgAAAA==.',
Uj='Ujabamy:BAAANQAECgEIAgAAAA==.',
Ul='Ulgroth:BAAANQAECgEIAgAAAA==.',
Un='Unbound:BAAANQADCgYIDAABNQADCgcICgACAAAAAA==.Unchanged:BAAANQADCggIEwAAAA==.Unførgiven:BAAANQADCgYICQAAAA==.',
Ur='Uruwashii:BAAANQAECgQIBQAAAA==.',
Ut='Utherfer:BAAANQADCgUIEAAAAA==.',
Uw='Uwuform:BAAANQAECggIDgAAAA==.',
Va='Vaelissa:BAAANQADCgYIBgAAAA==.Vaellinn:BAAANQADCgMIBAAAAA==.Vaeltar:BAAANQAECgcIEAAAAA==.Vaihalla:BAAANQADCgYIDgAAAA==.Valdezz:BAAANQAECgMIBQAAAA==.Valdrakken:BAAANQAECgMIAwAAAA==.Valerys:BAAANQADCgcIEAAAAA==.Valloran:BAAANQADCgYIDQAAAA==.Valorish:BAAANQAECgYICAAAAA==.Vaminnasul:BAAANQAECgIIAgAAAA==.Vanhaalen:BAAANQADCgYIBgAAAA==.Vazindi:BAAANQADCgcIBwAAAA==.',
Ve='Vejita:BAAANQADCgYICQAAAA==.Venatora:BAAANQADCgEIAgAAAA==.Vergetorix:BAAANQADCggIFQAAAA==.Vesk:BAAANQADCggIDQAAAA==.Vexkwondo:BAEANQADCgYIEQAAAA==.',
Vi='Vidafacil:BAAANQAECgEIAQAAAA==.Vija:BAAANQADCggIFQAAAA==.Vimes:BAAANQADCgIIAgAAAA==.Vindle:BAAANQADCgcIEgAAAA==.Virren:BAAANQADCggIDgABNQAFFAEIAQACAAAAAQ==.Virus:BAAANQAFFAIIAgAAAA==.Viscica:BAAANQADCggIEAAAAA==.Vixenia:BAAANQAECgUIBgAAAA==.',
Vo='Voidarcane:BAAANQAECgQIBQAAAA==.Voidfu:BAAANQAECgEIAQAAAA==.Voidrotten:BAAANQADCgQIBAAAAA==.Vowels:BAAANQAECgcIDwAAAA==.',
Vp='Vpdeath:BAAANQAECgIIAgABNQAECggIEgACAAAAAA==.Vpsham:BAAANQAECggIEgAAAA==.Vpslow:BAAANQAECgQIBAABNQAECggIEgACAAAAAA==.',
Vy='Vyerix:BAAANQADCgMIAwAAAA==.Vyktorr:BAAANQADCgYIDwAAAA==.Vyrix:BAABNQAECoEWAAIWAAkJcCNXAgCvAwAWAAkJcCNXAgCvAwAAAA==.',
['Vò']='Vòlp:BAAANQAECgQIBgAAAA==.',
Wa='Warelder:BAABNQAECoEYAAIcAAkJrh//AABOAwAcAAkJrh//AABOAwAAAA==.Wargazim:BAAANQAECgIIAwAAAA==.Wargens:BAAANQABCgMIAwAAAA==.Waylander:BAAANQAECgUIBgAAAA==.Wazapalooza:BAAANQAECgYICgAAAA==.Wazvlnt:BAAANQADCgQICAAAAA==.',
We='Weemac:BAAANQAECgQIBQAAAA==.Weledrindor:BAAANQADCgYIDAAAAA==.Welglick:BAAANQAECgUIBgAAAA==.Wendell:BAAANQAECgYICgAAAA==.Westen:BAAANQABCgIIAgAAAA==.',
Wh='Whackers:BAAANQADCggIDgAAAA==.',
Wi='Wickedh:BAAANQADCggIDgAAAA==.Wiesn:BAAANQADCgIIBAABNQADCgQIBgACAAAAAA==.Willöw:BAAANQAECgEIAQAAAA==.Winchu:BAAANQADCggIFQAAAA==.Wingman:BAAANQADCgUIBQAAAA==.',
Wo='Woody:BAAANQADCgIIAwAAAA==.',
Wr='Wrongtotem:BAAANQADCgMIAwAAAA==.',
Wt='Wtfrtotems:BAAANQAECgQIBgAAAA==.',
Wy='Wytanithia:BAAANQADCgQIBAAAAA==.',
['Wì']='Wìldbìll:BAAANQADCgQIBQAAAA==.',
['Wî']='Wîcked:BAAANQADCggIDAABNQADCggIDgACAAAAAA==.',
Xa='Xaak:BAAANQADCgcIEgAAAA==.Xaldyn:BAAANQAECgUIBgAAAA==.Xalvadore:BAAANQAFFAEIAQAAAA==.Xanathaz:BAAANQADCgQIBAAAAA==.Xandarya:BAAANQADCgUIBQAAAA==.Xans:BAAANQADCgYIBgABNQAECgMIAwACAAAAAA==.',
Xe='Xeliand:BAAANQADCggIFAAAAA==.Xenarya:BAAANQADCgcIEAAAAA==.Xenus:BAAANQAECgQIBQAAAA==.Xenå:BAAANQADCgUIBgAAAA==.Xerna:BAAANQADCgUICgAAAA==.',
Xi='Xien:BAAANQADCgIIAgAAAA==.Xinsuendo:BAAANQAECgEIAQAAAA==.',
Xy='Xyth:BAAANQADCgUICgAAAA==.',
['Xé']='Xérö:BAAANQADCgcIEgAAAA==.',
Ya='Yazshyr:BAAANQADCggIFQAAAA==.',
Ye='Yellowducky:BAAANQAECgIIAgAAAA==.Yelmo:BAAANQAECgQIBgAAAA==.Yesshua:BAAANQAECgIIAgAAAA==.',
Yi='Yiffyvulpine:BAAANQAECgMIAwAAAA==.',
Yo='Yokohp:BAAANQADCggIEAAAAA==.Yoshinami:BAAANQAECgMIAwAAAA==.Yourdealers:BAAANQADCgUIBQAAAA==.',
Yr='Yreneonia:BAAANQADCgYICwAAAA==.Yrël:BAAANQADCgQIBAABNQAECgEIAQACAAAAAA==.',
Yu='Yuliana:BAAANQAECgQIBAAAAA==.Yungslash:BAAANQAECgEIAQAAAA==.Yuzuyu:BAAANQAECgIIAwAAAA==.',
Za='Zabuzã:BAAANQADCgcIBwAAAA==.Zadacyn:BAAANQAECgIIAgAAAA==.Zaefel:BAAANQADCgQIBAAAAA==.Zaelais:BAAANQAECgcIDQAAAA==.Zaell:BAAANQAECgcICgABNQAECgcIDAACAAAAAA==.Zaelyndri:BAAANQADCgYIBgABNQAECggIEgACAAAAAA==.Zaem:BAAANQADCgUIBQAAAA==.Zaep:BAAANQABCgIIAgAAAA==.Zaew:BAAANQABCgIIAwAAAA==.Zaheer:BAAANQAECgcIEgAAAA==.Zahel:BAAANQAECgcIEgAAAA==.Zaidya:BAAANQADCgYIDAAAAA==.Zaldias:BAAANQAECgEIAQAAAA==.Zam:BAAANQAECgEIAQAAAA==.Zaqiel:BAAANQAECggIDQAAAA==.Zaque:BAAANQADCgMIAwAAAA==.Zashthar:BAAANQAECgEIAQAAAA==.Zatoichi:BAAANQABCgQIBAAAAA==.',
Ze='Zeelya:BAAANQADCgMIAwABNQAECgMIAwACAAAAAA==.Zeenie:BAAANQAECgYIBgAAAA==.Zeezou:BAAANQAECgQIBAAAAA==.Zeltic:BAAANQADCgMIAwAAAA==.Zeno:BAABNQAECoEZAAMOAAkJmCYAFwAOAwAOAAcJTiYAFwAOAwAdAAMJsSa1BwBWAQAAAA==.Zenosham:BAAANQAECgQIBAABNQAECgkJGQAOAJgmAA==.Zephraar:BAAANQADCgYICgAAAA==.Zeriahz:BAAANQAECgQIBQAAAA==.Zeroinstinct:BAAANQAECgQIBAAAAA==.Zerosense:BAAANQAECgUICAAAAA==.',
Zh='Zharkan:BAAANQADCgYIDAABNQAECgEIAQACAAAAAA==.Zhenyun:BAAANQAECgIIAwAAAA==.',
Zi='Ziendi:BAAANQAECgEIAgAAAA==.',
Zo='Zoku:BAAANQADCgIIAgAAAA==.Zolneos:BAAANQADCggICAABNQAECgkJFwAGADAkAA==.Zoltide:BAAANQADCgUIBQABNQAECgkJFwAGADAkAA==.Zolvoker:BAABNQAECoEXAAIGAAkJMCSRAADGAwAGAAkJMCSRAADGAwAAAA==.Zombok:BAAANQADCgcIBwAAAA==.Zoobox:BAAANQAECgIIAgAAAA==.Zormond:BAAANQADCgcIEgABNQAECgIIAgACAAAAAA==.',
Zu='Zuro:BAAANQADCgcIBwAAAA==.',
Zy='Zyroe:BAAANQADCgQIBgAAAA==.',
['Áe']='Áegwynn:BAAANQADCgYIBgAAAA==.',
['Âd']='Âdapt:BAAANQAECgEIAQAAAA==.',
['Ãz']='Ãzzy:BAAANQADCgYICQAAAA==.',
['Ät']='Äthenä:BAAANQAECgQIBgAAAA==.',
['Åm']='Åma:BAAANQAECgQIBgAAAA==.',
['Üt']='Üthor:BAAANQADCgYIDQAAAA==.',
['ßû']='ßûnny:BAAANQAECgEIAQABNQAECgkJGQATAB8hAA==.',
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
