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

local lookup = {'Unknown-Unknown','Warlock-Destruction','Paladin-Retribution','Shaman-Restoration','Shaman-Elemental','Shaman-Enhancement','Priest-Holy','Druid-Balance','DeathKnight-Unholy','Monk-Windwalker','Monk-Brewmaster','Hunter-BeastMastery','Hunter-Marksmanship','Mage-Frost','DemonHunter-Vengeance','Rogue-Assassination','Rogue-Subtlety','Warlock-Affliction','Warlock-Demonology','Paladin-Holy','Warrior-Protection','Warrior-Arms',}
local provider = {region='US',realm='Nagrand',name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Abysalwombie:BAAANQADCgcIDAAAAA==.',
Ac='Academic:BAAANQAECgIIAgAAAA==.Achallo:BAAANQADCggICAAAAA==.Acherron:BAAANQAECgQICwAAAA==.Achh:BAAANQADCgEIAQAAAA==.Acilia:BAAANQADCgYICwABNQAECgEIAQABAAAAAA==.',
Ad='Addiie:BAAANQADCgIIBAAAAA==.Adenachi:BAAANQADCgYICgAAAA==.Adenalock:BAAANQAECgQIBQAAAA==.Adialetha:BAAANQADCgYIEgAAAA==.',
Ae='Aelinhunter:BAAANQADCgYIDgAAAA==.Aerwyn:BAAANQABCgQIBQAAAA==.Aeryz:BAAANQADCgMIBQAAAA==.',
Ag='Agiel:BAAANQADCgcIBwABNQAECgMIAwABAAAAAA==.',
Ah='Ahxiongzz:BAAANQAFFAEIAQAAAA==.',
Ai='Aimaradin:BAAANQADCgMIAwAAAA==.Aiolia:BAAANQAECgIIAgAAAA==.',
Ak='Akakai:BAAANQAECgQIBgAAAA==.',
Al='Alagette:BAAANQADCgYICwAAAA==.Alagsham:BAAANQADCgUIBQAAAA==.Alblaireo:BAAANQADCgcIFgAAAA==.Alexantros:BAAANQAECgcIDAAAAA==.Alexstrazas:BAAANQADCggICAABNQAECgkJFwACANUiAA==.Alisaya:BAAANQADCgYIBgABNQAECgYIEQABAAAAAA==.Allewyn:BAAANQADCgcIEwAAAA==.Alnhai:BAAANQADCgYICQAAAA==.Alotdemonz:BAAANQADCgUIBQAAAA==.Althena:BAAANQADCgMIAwAAAA==.Altheous:BAAANQADCggIFQAAAA==.Alunamus:BAAANQAECgYICgAAAA==.Alvanâ:BAAANQAECgQIBQAAAA==.',
Am='Amandelthul:BAAANQAECgEIAQAAAA==.Amarizara:BAAANQADCggIFwAAAA==.Ambioracle:BAAANQAECggIEAAAAA==.Ambiwilds:BAAANQADCgYIBgAAAA==.Amullugh:BAAANQADCggIEQAAAA==.',
An='Angelfeet:BAAANQABCgYICQAAAA==.Ankarna:BAAANQAECgYICgAAAA==.Anorre:BAAANQAECgEIAQAAAA==.Antarie:BAAANQAECgYICgAAAA==.Anumbra:BAAANQAECgEIAQAAAA==.',
Ap='Apollyoin:BAAANQAECgcIEAAAAA==.Apophiis:BAAANQAECgEIAQAAAA==.Aprilkat:BAAANQAECgQIBgAAAA==.',
Ar='Arcenwrit:BAAANQAECgYICwAAAA==.Archonyx:BAAANQAECgQIBgAAAA==.Aredhele:BAAANQAECgUIBgAAAA==.Aribetha:BAAANQADCggICAAAAA==.Arlanaria:BAAANQAECgEIAQAAAA==.Arundal:BAABNQAECoEYAAIDAAkJ0iQ7AwCjAwADAAkJ0iQ7AwCjAwAAAA==.',
As='Asamara:BAAANQADCgYIEQAAAA==.Ashwathama:BAAANQADCggIDgABNQAECgYICwABAAAAAA==.Astaril:BAAANQAECgQIBQAAAA==.Asttrixe:BAAANQADCgIIAgAAAA==.',
Au='Auri:BAAANQAECgYICwAAAA==.Auriana:BAAANQADCggIIAAAAQ==.Aurithel:BAAANQADCgUIDwABNQADCggIIAABAAAAAQ==.',
Av='Avelaara:BAAANQADCggIEgAAAA==.Avren:BAAANQADCgEIAQAAAA==.Avys:BAAANQADCgIIAgABNQAECgQIBgABAAAAAA==.',
Aw='Awakia:BAAANQADCgIIAgAAAA==.Aweks:BAAANQABCgQIBwAAAA==.Awooweewaa:BAEANQAECgIIAgAAAA==.',
Az='Azarix:BAAANQAECgEIAQAAAA==.Azdaja:BAAANQADCgUIDwABNQAECgYICwABAAAAAA==.Azinosuke:BAAANQAECgMIBgAAAA==.Azriathi:BAAANQADCgYIBgAAAA==.Azrilia:BAAANQADCggIEAAAAA==.Azstrixe:BAAANQADCgYIBgAAAA==.',
Ba='Baconbaby:BAAANQAECgMIBQAAAA==.Balbimlin:BAAANQAECgUIBwAAAA==.Baneblades:BAAANQADCgYICAAAAA==.Banggoes:BAAANQADCggIEAAAAA==.Banokles:BAAANQADCgUIBQAAAA==.Banonir:BAAANQAECgYICwAAAA==.Batuman:BAAANQADCggIEAAAAA==.Baynz:BAAANQAECgcIDwAAAA==.',
Be='Beckdormu:BAAANQADCggIGAAAAA==.Bekstar:BAAANQAECgYIDAAAAA==.Belgora:BAAANQAECgIIAgAAAA==.Belnakor:BAAANQAECgcICwAAAA==.Bewinator:BAABNQAECoEXAAMEAAkJ/g2ZGwAtAgAEAAkJ/g2ZGwAtAgAFAAUJFgpgTgASAQAAAA==.',
Bi='Bigjoe:BAAANQAECgIIBQAAAA==.Bigs:BAAANQAECgIIBAAAAA==.Billy:BAAANQAECgcICgAAAA==.Binnie:BAABNQAECoEYAAIGAAkJdSYPAAAFBAAGAAkJdSYPAAAFBAAAAA==.Biscuits:BAAANQADCgIIBAAAAA==.Bixwar:BAAANQAECgEIAQAAAA==.',
Bl='Blackwing:BAAANQADCgQIBAAAAA==.Blatsphemare:BAAANQADCggIFAAAAA==.',
Bo='Bobhots:BAAANQAECgEIAQAAAA==.Bolr:BAAANQABCgQIBwAAAA==.Bongfury:BAAANQAECgQIBgAAAA==.Boomerite:BAAANQADCgcIDAAAAA==.Boomoist:BAAANQADCgcIBwABNQADCgcIDAABAAAAAA==.Boomshaka:BAAANQAECgQIBAAAAA==.Boostwunk:BAAANQAECgQIBAABNQAECgQIBQABAAAAAA==.Boraicho:BAAANQADCgMIAwAAAA==.Bosswamdi:BAAANQAECggIEQAAAA==.Bouch:BAAANQAECgYICwAAAA==.Boujee:BAAANQAECgEIAQABNQAECgYIBwABAAAAAA==.',
Br='Brakenjan:BAAANQADCgEIAQAAAA==.Break:BAAANQADCgMIAwAAAA==.Brewzleé:BAAANQADCgQIBAAAAA==.Brickfield:BAAANQAECgIIAgAAAA==.Brillybril:BAAANQAECgYIBwAAAA==.Browngirl:BAAANQADCggIDgABNQADCggIEQABAAAAAA==.Brownonion:BAAANQAECgQIBQAAAA==.Broxstar:BAAANQADCggICAAAAA==.Brutalpala:BAAANQADCgUICAAAAA==.Brutalshammy:BAAANQAECgQIBgAAAA==.',
Bu='Budbundy:BAAANQADCggICAAAAA==.Buffalot:BAAANQADCgYIDgAAAA==.Bullsock:BAAANQADCggICAAAAA==.Bundaburg:BAAANQAECgMIAwAAAA==.Busting:BAAANQADCggIFQAAAA==.',
['Bå']='Båconbåby:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.',
Ca='Caean:BAAANQAECgUIBQAAAA==.Caelthus:BAAANQADCgEIAQAAAA==.Captplanetz:BAAANQAECggIEwAAAA==.Cargrim:BAAANQAECgQICAAAAA==.Carithye:BAAANQADCgUIAgAAAA==.Carnacki:BAAANQADCggIDgAAAA==.Catmoncorgi:BAABNQAECoEXAAIHAAkJhiS7AAC5AwAHAAkJhiS7AAC5AwABNQAFFAIIBAABAAAAAA==.Caywen:BAAANQADCggICgAAAA==.',
Ce='Celaxus:BAAANQAECgQIBQAAAA==.Celish:BAAANQAECgIIAwABNQAECgQIBQABAAAAAA==.Cerrast:BAAANQAECgUIEAAAAA==.',
Ch='Chaosdots:BAAANQADCggIDgAAAA==.Charben:BAAANQADCgUICwAAAA==.Chickade:BAAANQADCgYICgAAAA==.Chickekk:BAABNQAECoEXAAIIAAkJgSSpAQC4AwAIAAkJgSSpAQC4AwAAAA==.Chips:BAABNQAECoEYAAIJAAkJkR+eCAAbAwAJAAkJkR+eCAAbAwAAAA==.Choko:BAAANQADCgYIBgAAAA==.Chowder:BAAANQAECgIIAgAAAA==.Chowdo:BAAANQAECgIIAgAAAA==.',
Cj='Cjhunter:BAAANQAECgQIBwAAAA==.Cjshammy:BAAANQAECgYICQAAAA==.',
Ck='Ckc:BAAANQAECgQICAAAAA==.',
Cl='Cliege:BAAANQAECgIIAgAAAA==.Cloutermage:BAAANQAECgUICAAAAA==.Clr:BAAANQADCgYIEAAAAA==.',
Co='Coganini:BAAANQADCgUIAQAAAA==.Coldrethreth:BAAANQADCgUIEQAAAA==.Computation:BAAANQADCgIIAgAAAA==.Conystus:BAAANQADCgQIBAAAAA==.Corpsemere:BAAANQADCgUIBQAAAA==.Cowoflife:BAAANQAECgQIEgAAAA==.Cozmo:BAAANQAECgEIAQABNQAECgcIDQABAAAAAA==.',
Cr='Crackle:BAAANQAECgMIAwAAAA==.Crazee:BAAANQADCggIEwAAAA==.Crimdal:BAAANQAECgcIDQAAAA==.Crunchadin:BAAANQAECgEIAQAAAA==.Cryptoxic:BAAANQADCggIEAAAAA==.',
Cs='Cshake:BAAANQAECgQIBAAAAA==.',
Cu='Cutnanslunch:BAAANQAECgIIAgAAAA==.',
Cx='Cxzza:BAAANQAECgUIBgAAAA==.',
Da='Dahdahdahw:BAAANQABCgIIAgAAAA==.Dalston:BAAANQAECgEIAQAAAA==.Damarah:BAABNQAECoEYAAIIAAkJBiJDBAB0AwAIAAkJBiJDBAB0AwAAAA==.Dannerus:BAAANQADCgUIBwAAAA==.Danotia:BAAANQADCgYIDQAAAA==.Danthalian:BAAANQADCgYIEAAAAA==.Darianus:BAAANQADCggIFwAAAA==.Darkerella:BAAANQADCgQIBwABNQAECgMIAwABAAAAAA==.Darkrose:BAAANQAECgYIDwAAAA==.Darthcutie:BAAANQADCggICAAAAA==.Daspdruid:BAAANQADCgIIAgAAAA==.Daspp:BAAANQADCgIIAgABNQADCgIIAgABAAAAAA==.Datch:BAAANQABCgMIAwAAAA==.Dato:BAAANQAECgMIBAAAAA==.Davebutblue:BAAANQADCgUIBQAAAA==.Dawndeath:BAAANQADCgcIBwABNQAECgQIBAABAAAAAA==.',
De='Deadcalm:BAAANQADCgIIAgAAAA==.Deathdealers:BAAANQADCggIEAAAAA==.Deathlen:BAAANQADCgQIBAABNQAECgkJFwAKAJAdAA==.Deathlyclown:BAAANQAECgYICgAAAA==.Deathlypach:BAAANQAECgIIAgAAAA==.Deathnerrisa:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Deathrange:BAABNQAECoEaAAIHAAgJcQECPQAoAQAHAAgJcQECPQAoAQAAAA==.Decawraith:BAAANQAECgcIDwAAAA==.Decitar:BAAANQAECgMIAwABNQAFFAEIAQABAAAAAA==.Dekïngrekt:BAAANQAECgIIAwAAAA==.Deldin:BAAANQADCgEIAQABNQAFFAIIBAABAAAAAA==.Desura:BAAANQAECgIIAwAAAA==.Dex:BAAANQAECgEIAgAAAA==.Deysona:BAAANQADCgMIAwABNQAECgcIDwABAAAAAA==.Deãthnchaos:BAAANQADCgQIBAAAAA==.',
Di='Dileyna:BAAANQADCgYIDwAAAA==.Dirtbike:BAAANQAECgIIAwAAAA==.Discretion:BAAANQADCgcIDQAAAA==.Dismàl:BAAANQAECgcIDAAAAA==.Divinarius:BAAANQADCgEIAQAAAA==.Dizzyfrizz:BAAANQADCggIDAAAAA==.Dizzygrizz:BAAANQADCgQIBQAAAA==.',
Dj='Djabooty:BAAANQADCgcIEAAAAA==.Djarin:BAAANQADCgYICAABNQAECgQIBAABAAAAAA==.',
Dk='Dkarmour:BAAANQADCgcIBwABNQAECgUIBgABAAAAAA==.Dkarth:BAAANQADCgYIBgAAAA==.Dkinaböx:BAAANQAECgIIAwAAAA==.',
Do='Doktor:BAAANQADCgYICwAAAA==.Donnlock:BAAANQAECgYIBwAAAA==.Doob:BAAANQAECgcIEAAAAA==.Dovatomt:BAAANQADCggICAAAAA==.',
Dr='Dragolord:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.Dragonsaint:BAAANQAECgQICAAAAA==.Draik:BAAANQADCgMIAwABNQADCgUIBQABAAAAAA==.Dranoth:BAAANQADCgcICwAAAA==.Dreadzie:BAAANQAECgYIBgAAAA==.Dreadzz:BAAANQADCgcIBwABNQAECgYIBgABAAAAAA==.Dreary:BAAANQAECgEIAQAAAA==.Drogodoth:BAAANQADCgcIDAAAAA==.Drogøn:BAAANQADCgYIBgAAAA==.Droopsy:BAAANQADCgIIAgAAAA==.Druiz:BAAANQADCgYIBgAAAA==.Drunkdwarf:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.Dryhemp:BAAANQAECgcICgAAAA==.Dryx:BAAANQADCgYIBgAAAA==.',
Du='Duffmann:BAAANQAECgIIAgAAAA==.Dunghai:BAAANQADCggIDgAAAA==.',
['Dé']='Déaxta:BAAANQADCggIFQAAAA==.',
Ea='Eastty:BAAANQAECgcIEAAAAA==.Eatrootnleaf:BAAANQADCgIIBAAAAA==.',
Ed='Ed:BAAANQADCgYIBgAAAA==.Edrooney:BAAANQAECgQIBgAAAA==.',
Eg='Eggyokegamer:BAAANQAECgQIBgAAAA==.',
Ei='Eisenschutz:BAAANQADCgYICgAAAA==.',
El='Eldodo:BAAANQADCgYIBgABNQADCggICAABAAAAAA==.Eldr:BAAANQAECgIIAwAAAA==.Eletyre:BAAANQAECgYIEQAAAA==.Elliann:BAAANQADCggIDgABNQAECgQIBAABAAAAAA==.Ellizer:BAAANQADCgQIBAAAAA==.Elwìngs:BAAANQAECgIIAwAAAA==.',
Em='Emchi:BAABNQAECoEXAAILAAkJsBpVAgDqAgALAAkJsBpVAgDqAgABNQAFFAYICQALAB4SAA==.Emeli:BAAANQAECgEIAQAAAA==.',
En='Enderosi:BAAANQAECgIIAgABNQAECgIIBQABAAAAAA==.Englshmuffn:BAAANQAECgQICQAAAA==.Enigmazole:BAAANQADCgUICgABNQAECgkJGAAMAJsfAA==.',
Er='Erereas:BAAANQAECgIIBQAAAA==.Eryndor:BAAANQABCgQIBQAAAA==.',
Es='Esabelle:BAAANQADCgcIBwAAAA==.Esaul:BAAANQADCgYIBgAAAA==.Eshaybruh:BAAANQADCgMIBAAAAA==.',
Ev='Everdream:BAAANQAECgQIBQAAAA==.',
Ex='Exovenator:BAABNQAECoEYAAMMAAkJmx94DADUAgAMAAcJrCV4DADUAgANAAQJAhDVJgDgAAAAAA==.',
Ez='Ezoth:BAAANQADCgQIBQAAAA==.Ezram:BAAANQADCgUIBQAAAA==.',
Fa='Faithguard:BAAANQADCgYIBgAAAA==.Faizoo:BAAANQADCgYICwAAAA==.Faizuu:BAAANQADCgYIBgAAAA==.Faizzah:BAAANQADCgcICwAAAA==.Falassion:BAAANQADCggIDAAAAA==.Faloria:BAAANQADCgQIBAABNQADCgcIDwABAAAAAA==.Fandraynna:BAAANQADCgMIBwAAAA==.Faranir:BAAANQAECgEIAwAAAA==.Farbio:BAAANQADCgYIBgAAAA==.Fawni:BAAANQAECgcIDAAAAA==.Fazzadru:BAAANQADCgYIDQAAAA==.',
Fe='Feets:BAAANQADCgUIBQAAAA==.Fergasmo:BAAANQAECgIIBAAAAA==.Ferny:BAAANQADCggIDgAAAA==.Ferragus:BAAANQAECgEIAQAAAA==.',
Fi='Filiana:BAAANQADCgUIBQAAAA==.Filicane:BAAANQADCgYIBgAAAA==.Finalsigma:BAAANQAECgQIBgAAAA==.Finlan:BAAANQAECgIIAgAAAA==.Fistsofchaos:BAAANQAECgEIAQAAAA==.',
Fl='Flamemaster:BAAANQADCgYIBgAAAA==.Flickascale:BAAANQAECgUIBgAAAA==.Flossytop:BAAANQAECgEIAQAAAA==.Flutterhoof:BAAANQADCgUIBwABNQAECgMIAwABAAAAAA==.Flybubye:BAAANQAECgEIAQAAAA==.Flykickednan:BAAANQAECgIIAgAAAA==.',
Fo='Formsfriend:BAABNQAECoEXAAIOAAcJJCMpAQDRAgAOAAcJJCMpAQDRAgAAAA==.Foxxglove:BAAANQAECgIIBAAAAA==.',
Fr='Fractalicius:BAAANQABCgQIAgABNQADCgYIBgABAAAAAA==.Freakytouch:BAAANQAECgEIAQAAAA==.Friesnaioli:BAAANQADCgcICQAAAA==.Friya:BAAANQADCgMIAwABNQAECgYICwABAAAAAA==.Frostmore:BAAANQADCgQIBgAAAA==.Frostyveins:BAAANQAECgQIBAAAAA==.',
Fu='Furbý:BAAANQAECgQIBQAAAA==.',
Fy='Fythir:BAAANQADCgMIAwAAAA==.',
Ga='Gaberiel:BAAANQAECgIIAgAAAA==.Galaron:BAAANQADCgQICQAAAA==.Gavo:BAAANQADCggIFQAAAA==.',
Ge='Genelas:BAAANQADCgUIBQAAAA==.Gentayangan:BAAANQADCgQIBQABNQAECgEIAwABAAAAAA==.',
Gh='Ghillian:BAAANQADCggIEQAAAA==.',
Gi='Gilfit:BAAANQADCgYICwAAAA==.Gilgámesh:BAABNQAECoEXAAIDAAkJ0BngDQDqAgADAAkJ0BngDQDqAgAAAA==.Gilreis:BAAANQADCgYIBgAAAA==.Gimpmama:BAAANQAECgcIEAAAAA==.',
Go='Goldeer:BAAANQAECgUIBQAAAA==.Goopyheals:BAAANQADCgEIAQAAAA==.Gorwrath:BAAANQAECgYIDgAAAA==.Gotrek:BAAANQADCggIIAAAAA==.',
Gr='Greybalgruf:BAAANQAECgQICAAAAA==.Grimakh:BAAANQAECgEIAQAAAA==.Gruesome:BAAANQADCggIEwABNQADCgEIAQABAAAAAA==.Gruesomely:BAAANQADCgEIAQAAAA==.Grugblasts:BAAANQABCgYIBgAAAA==.Grânite:BAAANQADCggIDQAAAA==.',
Gy='Gypse:BAAANQAECgYICwAAAA==.Gypsi:BAAANQADCgQICgAAAA==.Gypsie:BAAANQADCgUIBQAAAA==.',
['Gõ']='Gõdly:BAAANQAECgEIAQAAAA==.',
Ha='Hadouken:BAAANQAECgUICQAAAA==.Haenlas:BAAANQADCgQIBAAAAA==.Hairytoetum:BAAANQADCgUIBQAAAA==.Halleydinde:BAAANQAECgEIAQAAAA==.Hanz:BAAANQADCggICAAAAA==.Hargol:BAAANQADCgQIBAABNQAECgQICAABAAAAAA==.Hasunstraza:BAAANQADCgUICAAAAA==.Hayhatchie:BAAANQAECgQICAAAAA==.Hazel:BAAANQAECgEIAQAAAA==.Hazèful:BAAANQAECgIIAgAAAA==.',
He='Heirophant:BAAANQAECgIIAgAAAA==.Hellisha:BAAANQAECgIIAgAAAA==.Henwee:BAAANQADCggIIAAAAA==.Herakles:BAAANQADCgcIAQAAAA==.Herborial:BAAANQADCgcICgAAAA==.Hex:BAAANQADCggICQAAAA==.Hexx:BAAANQAECgEIAQAAAA==.Hexxage:BAAANQAECgEIAQAAAA==.Hezekïel:BAAANQADCgMIAwAAAA==.',
Hi='Hilfy:BAAANQAECgQIBgAAAA==.Hixl:BAAANQAECgEIAgAAAQ==.',
Ho='Holyfoxclaws:BAAANQAECgMIAwAAAA==.Holysmokê:BAAANQADCgYIBgAAAA==.Hongtoufa:BAAANQADCgQICgAAAA==.Hopskipjump:BAAANQAECgYICgAAAA==.Hoshiyomi:BAAANQAECgUIBgAAAA==.Hotpink:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.Hotpocket:BAAANQADCgQIBAABNQAECgEIAgABAAAAAA==.Hotshöt:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.',
Hu='Humphrey:BAAANQADCgIIAgAAAA==.',
['Hé']='Hétzu:BAAANQADCggIAgAAAA==.',
Ic='Icyberry:BAAANQAECgQIBgAAAA==.',
If='If:BAAANQAECgQICAAAAA==.',
Ik='Iklehannican:BAAANQADCgYICwAAAA==.Ikneb:BAAANQADCgcIDwAAAA==.',
Il='Illdotyabox:BAAANQADCgUIBQAAAA==.',
Im='Imoheals:BAAANQADCggICAABNQAECgcICwABAAAAAA==.Imohsdk:BAAANQAECgcICwAAAA==.Impmama:BAAANQAECgcIEAAAAA==.',
In='Inariarse:BAAANQADCgMIBAABNQAECgQICAABAAAAAA==.Insomniac:BAAANQADCgMIAwAAAA==.',
Ir='Ireneroev:BAAANQAECgYICgAAAA==.Ireneropr:BAAANQADCgYICwABNQAECgYICgABAAAAAA==.Iridra:BAAANQADCggICAAAAA==.Irrelevance:BAAANQAECgYICwAAAA==.',
Is='Isenpal:BAEANQAECgMIAwAAAA==.',
It='Ithleron:BAAANQAECgIIAgAAAA==.Itsriv:BAAANQAECgUIEAAAAA==.',
['Iç']='Içy:BAAANQAECgcIDQAAAA==.',
Ja='Jackpawt:BAAANQADCgIIBAAAAA==.Jafs:BAAANQADCgUIAwAAAA==.Jainaproudmo:BAABNQAECoEXAAICAAkJ1SKIAACkAwACAAkJ1SKIAACkAwAAAA==.Jallopeno:BAAANQAECgQICAAAAA==.Jastar:BAAANQAECgYIDAAAAA==.Jawatko:BAAANQADCggIEgAAAA==.Jayrob:BAAANQADCgYIAwAAAA==.Jayzin:BAAANQAECgcIEAAAAA==.Jazzyfizzle:BAAANQAECgEIAQAAAA==.',
Jb='Jboomy:BAAANQADCgcICQABNQAECgcICgABAAAAAA==.',
Je='Jenniku:BAAANQADCgIIAgAAAA==.',
Ji='Jimmyrecard:BAAANQADCgYIDQAAAA==.Jimscautery:BAAANQAECgMIBAAAAA==.Jimshealing:BAAANQADCgYIBwABNQAECgMIBAABAAAAAA==.',
Jl='Jlãb:BAAANQADCggICAABNQAECgQIBQABAAAAAA==.',
Jo='Joestjoe:BAAANQADCggIEgAAAA==.Jonesysz:BAAANQAECgYICAAAAA==.Joofheart:BAAANQADCggIDgAAAA==.Jorick:BAAANQAECgYIDAAAAA==.Jormungand:BAAANQAECgQIBAAAAA==.Jormunter:BAAANQAECgEIAQAAAA==.',
Js='Jshammy:BAAANQAECgEIAQABNQAECgcICgABAAAAAA==.',
Ju='Judzia:BAAANQADCgcIEQAAAA==.Juggérnaut:BAAANQAECgQIBgAAAA==.Juguan:BAAANQADCgQIBAAAAA==.Justclick:BAAANQADCgcIBwABNQAECgYICgABAAAAAA==.',
Ka='Kadôs:BAAANQAECgMIBAAAAA==.Kaggon:BAAANQADCggIDgABNQAECgQIBwABAAAAAA==.Kaigha:BAAANQABCgYIBwAAAA==.Kainendh:BAABNQAECoEYAAIPAAkJryFeAAB1AwAPAAkJryFeAAB1AwAAAA==.Kaizen:BAAANQADCggIIAAAAA==.Kakanda:BAAANQADCgQIBAABNQAECgEIAwABAAAAAA==.Kamiikazee:BAABNQAECoEYAAMQAAkJiRlACABQAgAQAAkJthNACABQAgARAAYJXRSPFQCqAQAAAA==.Karlise:BAAANQADCgEIAQAAAA==.Katheriina:BAAANQAECgIIAgAAAA==.Kattarinna:BAAANQADCgcIDQAAAA==.Kattiiee:BAAANQAECgQIBgAAAA==.Katyia:BAAANQADCgMIAwAAAA==.Kayubi:BAAANQADCgIIAwAAAA==.Kazer:BAAANQAECgcICQAAAA==.Kazutaka:BAAANQAECgQIBgAAAA==.Kazx:BAAANQADCggIBwAAAA==.Kaìtlyn:BAAANQAECgUIBwAAAA==.',
Ke='Kehlaina:BAAANQAECgQIBAAAAA==.Kesh:BAAANQADCgMIAwAAAA==.Ketsuko:BAAANQAECgUICQAAAA==.Keyies:BAAANQADCgYIBgAAAA==.',
Kh='Khaal:BAAANQAECgcIDQAAAA==.Khalessii:BAAANQAECgIIAwAAAA==.Khalina:BAAANQAECgMIAwAAAA==.Khanethus:BAAANQADCggIDgAAAA==.Kharli:BAAANQADCgcIEQAAAA==.Khon:BAAANQADCggICAAAAA==.',
Ki='Kidstuff:BAAANQAECgEIAQAAAA==.Kijin:BAAANQAECgMIAwAAAA==.Kikashi:BAAANQADCgIIAgAAAA==.Kinko:BAAANQADCgcIEwAAAA==.Kiped:BAAANQAECgEIAwAAAA==.Kirlen:BAABNQAECoEXAAISAAkJTxxiAAA4AwASAAkJTxxiAAA4AwAAAA==.Kisschasey:BAAANQADCggIDgAAAA==.',
Kl='Kleb:BAAANQAECgIIAgAAAA==.',
Kn='Kny:BAAANQAECgYIBgAAAA==.',
Kr='Kruzt:BAAANQAECgQIBQAAAA==.',
Ky='Kyrièl:BAAANQAECgEIAQAAAA==.',
La='Laihoxi:BAAANQADCggIDAAAAA==.Lalwenya:BAAANQAECgEIAgAAAA==.Lantanis:BAAANQAECgQIBQAAAA==.',
Le='Lebronion:BAAANQADCgYICwAAAA==.Lemonpledge:BAAANQADCgQIBAABNQAECgYICwABAAAAAA==.Levares:BAAANQAECgMIAwAAAA==.',
Li='Lieken:BAAANQAECgUIEAAAAA==.Linestanas:BAAANQAECgQIBgAAAA==.Lirrah:BAAANQADCgYIDAAAAA==.',
Lo='Locknerissa:BAAANQADCggICAABNQAECgEIAQABAAAAAA==.Lorkel:BAAANQADCgcICQAAAA==.Lottiee:BAAANQADCgYICgAAAA==.',
Lu='Lucero:BAAANQADCggIDgAAAA==.Luigii:BAAANQADCgUIBgAAAA==.Luminel:BAABNQAECoEXAAMTAAkJRxlIJQDdAQATAAYJfBpIJQDdAQACAAQJjhPVIQARAQAAAA==.Lunaleri:BAAANQAECgQIBAAAAA==.Lunavoker:BAAANQADCgcIBwABNQAECgQIBAABAAAAAA==.Lunguci:BAAANQADCggIDgAAAA==.',
['Lë']='Lëndis:BAAANQADCgYIDQAAAA==.',
['Lì']='Lìfebinder:BAAANQADCggIEgAAAA==.',
Ma='Madgettie:BAAANQAECgYICwAAAA==.Madmax:BAAANQADCgcIBwAAAA==.Madross:BAAANQADCgcIDQAAAA==.Maevis:BAAANQADCggIEwAAAA==.Magadin:BAABNQAECoEYAAMDAAkJVCKMBQBtAwADAAkJVCKMBQBtAwAUAAEJ7QGLlAAvAAAAAA==.Magheer:BAAANQADCgcIBwAAAA==.Magiclock:BAAANQAECgMIAwAAAA==.Magictuxedo:BAAANQAECgYIBgAAAA==.Magicwaffles:BAAANQADCgcIDQAAAA==.Magnayah:BAAANQAECgEIAQAAAA==.Magretta:BAAANQADCgYIDQABNQAECgEIAQABAAAAAA==.Mainblitz:BAAANQADCgcIBwAAAA==.Maladria:BAAANQAECgEIAQABNQAECgcIEAABAAAAAA==.Malastraza:BAAANQAECgQICAAAAA==.Manablast:BAAANQADCggICAAAAA==.Mandamar:BAABNQAECoEYAAIVAAkJZCOJAACjAwAVAAkJZCOJAACjAwAAAA==.Mariio:BAAANQAECgIIAgAAAA==.Mashd:BAAANQAECgcIBwAAAA==.Matt:BAAANQADCgYICwAAAA==.Matthias:BAAANQADCggIFQAAAA==.Mattiblood:BAAANQADCgYIBgAAAA==.Maverinna:BAAANQAECgEIAQAAAA==.Mavv:BAAANQAECgMIBwAAAA==.Maxiless:BAAANQAECgIIAgAAAA==.Maxpowaah:BAAANQAECgEIAQAAAA==.Maxumas:BAAANQAECgIIBQAAAA==.Maymays:BAAANQADCgYIBgABNQAECggIFwAJAN4mAA==.Mayshunt:BAAANQADCgUIBQAAAA==.',
Mc='Mcflurry:BAAANQAECgEIAQAAAA==.',
Me='Mebisu:BAAANQADCgYIBgAAAA==.Megapet:BAAANQAECgMIAwAAAA==.Melliena:BAAANQAECgUIEAAAAA==.Merchardo:BAAANQADCggICAAAAA==.Metajücy:BAAANQADCgMIBQAAAA==.Metalgear:BAAANQABCgEIAQAAAA==.',
Mi='Miichelle:BAAANQAECgIIAgAAAA==.Milkyway:BAAANQADCgYIBgABNQAECggICwABAAAAAA==.Miloiced:BAAANQAECgQIBAAAAA==.Mimosa:BAAANQAECgQIBAAAAA==.Minae:BAEANQAECgQIBAABNQAECgcIEAABAAAAAA==.Misspinkz:BAAANQADCgEIAQAAAA==.Mistjester:BAAANQAECgEIAQAAAA==.Mistyc:BAAANQAECgUIEAAAAA==.Mistycbicdig:BAAANQAECgQIBwABNQAECgUIEAABAAAAAA==.Mitsue:BAEANQAECgcIEAAAAA==.',
Mj='Mjay:BAAANQADCggIEwAAAA==.',
Mo='Modeus:BAAANQADCggICAAAAA==.Moffmatiks:BAAANQADCggIFQAAAA==.Momspriest:BAAANQAECgIIAgAAAA==.Monika:BAAANQAECgQIBgAAAA==.Mookikiat:BAAANQAECgIIAgAAAA==.Moonstorm:BAAANQAECgEIAQAAAA==.Moophus:BAAANQAECgEIAQAAAA==.Moraykings:BAAANQAECgcIEQAAAA==.Morbthegreat:BAAANQADCgYICAABNQAECgMIBAABAAAAAA==.Morbzz:BAAANQAECgMIBAAAAA==.Moretal:BAAANQADCggICAAAAA==.Morgoloth:BAAANQADCgYIBgAAAA==.',
Mu='Muddywaters:BAAANQAECgQIBAABNQAECgYICwABAAAAAA==.Muggles:BAAANQAECgMIAwAAAA==.Mulathor:BAAANQADCgYIBgABNQAECgQICAABAAAAAA==.Mulloy:BAAANQADCgUIBQAAAA==.Munabuunii:BAAANQAECgcIEgAAAA==.Munamage:BAAANQADCggICAABNQAECgcIEgABAAAAAA==.Munch:BAAANQAECgEIAQAAAA==.Musclethighs:BAAANQADCggIEQAAAA==.',
Mv='Mvp:BAAANQADCgYIBwAAAA==.',
My='Mybâd:BAAANQAECgMIAwAAAA==.Myehv:BAAANQAECgQIBAAAAA==.Mylowe:BAAANQAECgQIBAAAAA==.Myneckmyback:BAAANQADCggICAAAAA==.Mysticshadow:BAAANQAECgYIEgAAAA==.Mystimonk:BAAANQADCgUIBQABNQAECgYIEgABAAAAAA==.Mystèrion:BAAANQADCgIIAgAAAA==.',
['Mô']='Môth:BAAANQAECgQIBgAAAA==.',
Na='Naacho:BAAANQAECggIEwAAAA==.Naachoh:BAAANQADCgIIAgABNQAECggIEwABAAAAAA==.Nachomage:BAAANQADCgYIBgABNQAECggIEwABAAAAAA==.Nadyae:BAAANQAECgQIBAAAAA==.Nas:BAAANQAECgYICwAAAA==.Nasayuki:BAAANQAECgIIAwAAAA==.Nasmilk:BAAANQADCggIFAAAAA==.',
Ne='Nehdrake:BAAANQAECgEIAQAAAA==.Neltar:BAAANQADCgQIBAAAAA==.Nelth:BAAANQAECgEIAQAAAA==.Nerancis:BAAANQADCggICwAAAA==.Nerastrasza:BAAANQADCggIIAAAAA==.Nerrisa:BAAANQADCggIDgABNQAECgEIAQABAAAAAA==.Netragal:BAAANQADCggICAAAAA==.Nety:BAABNQAECoEWAAMNAAkJVyZOAQC0AwANAAkJOiROAQC0AwAMAAQJ3ya5PACUAQAAAA==.Nexx:BAAANQADCgQICAABNQADCggIIAABAAAAAA==.Neytiriee:BAAANQADCgYICwAAAA==.Nezihs:BAAANQADCggIFwAAAA==.',
Ni='Niftybeasty:BAAANQADCgYIDQAAAA==.Nightmarexx:BAAANQAECgIIAwAAAA==.Nightwish:BAAANQADCgQIBAAAAA==.Nihilus:BAAANQAECgYICwAAAA==.Nihlus:BAAANQADCggIFAAAAA==.Nish:BAAANQAECgIIAgAAAA==.Niwa:BAAANQABCgEIAQAAAA==.',
No='Noblepark:BAAANQAECgQICgAAAA==.Noirpalm:BAAANQAECgMIAwAAAA==.Nonothing:BAAANQAECgEIAQAAAA==.Noona:BAAANQAECgEIAQAAAA==.Norwyck:BAAANQAECgEIAQAAAA==.Notgrippin:BAAANQAECgIIAgAAAA==.Notjuzzie:BAAANQAECgQIBgAAAA==.Notvie:BAAANQADCgYIDwABNQAECgEIAQABAAAAAA==.Novai:BAAANQADCggICAAAAA==.',
Nu='Nudnud:BAAANQADCgUIBQABNQADCggIIAABAAAAAA==.Nudtharion:BAAANQADCggIIAAAAA==.',
Ob='Obbi:BAAANQAECgQICwAAAA==.Obesewikaman:BAAANQAECgQIBAAAAA==.',
Ol='Olyhornz:BAAANQAECgYICwAAAA==.',
Om='Omatikayar:BAAANQAECgYICQAAAA==.Omegacub:BAAANQADCgYIEwAAAA==.',
On='Onejobmoon:BAAANQADCgQIBAAAAA==.Oneo:BAAANQAECgcIEwAAAA==.',
Oo='Oomma:BAAANQAECgcIEAAAAA==.',
Or='Oralock:BAAANQAECgEIAQAAAA==.Orczilla:BAAANQAECgIIBAAAAA==.Orduk:BAAANQAECgEIAQAAAA==.Orisong:BAAANQAECgIIAgAAAA==.',
Os='Osirris:BAAANQADCggICAAAAA==.',
Ou='Outshot:BAAANQAECgEIAQAAAA==.',
Pa='Pahnicious:BAAANQADCgYIDQAAAA==.Paimon:BAAANQADCggICAAAAA==.Paladinium:BAAANQADCgEIAQAAAA==.Palalord:BAAANQAECgIIAwAAAA==.Paliotank:BAAANQADCgcIEQAAAA==.Pallyperson:BAAANQAECgQIBQAAAA==.Pallytato:BAAANQAECgUIDgAAAA==.Parag:BAAANQADCgUIBQAAAA==.Parallaxian:BAAANQAECgQIBgAAAA==.Pariroa:BAAANQADCgUIBQAAAA==.Pasteytaco:BAAANQADCggIEAABNQAECggIEwABAAAAAA==.',
Pe='Pedros:BAAANQAECgcIDQAAAA==.Peggbundy:BAAANQAECgMIBQAAAA==.Pentahealixx:BAAANQAECgMIAwAAAA==.Peon:BAAANQAECgEIAQAAAA==.Perisauce:BAAANQAECgIIAgAAAA==.Pew:BAAANQAECgcIDAAAAA==.',
Ph='Phaidor:BAAANQADCgUICQAAAA==.Phenomblack:BAAANQAECgQIBgAAAA==.Phil:BAAANQADCggIFwAAAA==.Phlbrew:BAAANQADCgMIAwABNQAECggIEgABAAAAAA==.Phldot:BAAANQADCgQIBAABNQAECggIEgABAAAAAA==.',
Pi='Piglock:BAAANQADCgYICAABNQAECgQICAABAAAAAA==.Pindleskins:BAAANQADCgQIBAAAAA==.Pinkadin:BAAANQAECgMIAwAAAA==.Piñdleskins:BAAANQADCgYIBgAAAA==.',
Pl='Plastique:BAAANQADCggIFQAAAA==.Plopperjr:BAAANQAECgcIEAAAAA==.',
Po='Pokemonster:BAAANQADCggIFgABNQAECgkJFwAMAP0iAA==.Ponendus:BAAANQADCgcIEgAAAA==.Poogie:BAAANQAECgUIBQAAAA==.Popalot:BAAANQADCgYIEQAAAA==.Potatoshoes:BAAANQAECggIEwAAAA==.Poyo:BAAANQADCggICAAAAA==.',
Pr='Prepared:BAAANQAECgUIDgAAAA==.Priestlydots:BAAANQAECgIIAwAAAA==.Priestlåd:BAAANQADCgYIBwAAAA==.',
Pu='Puddiin:BAAANQADCgYIDgAAAA==.Puffthemagi:BAAANQAECgQIBAAAAA==.',
Py='Pyrothermia:BAAANQAECgcIDQAAAA==.Pyzrlil:BAAANQAECgQIBQAAAA==.',
['Pä']='Pändah:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.',
['Pé']='Pérsephóne:BAAANQAECgYICwAAAA==.',
['Qü']='Qüelaag:BAAANQADCgIIAgABNQAECgcIEAABAAAAAA==.',
Ra='Raeleth:BAAANQAECgEIAQAAAA==.Rageissues:BAAANQAECgQIBwAAAA==.Rainiar:BAAANQAECgcICgAAAA==.Rambutan:BAAANQADCggIDwAAAA==.Rascalanger:BAAANQAECgEIAQAAAA==.Rastaloth:BAAANQAECgQIBgAAAA==.Raurr:BAAANQADCgEIAQAAAA==.Ravýn:BAAANQAECgQIBQAAAA==.Raybans:BAAANQADCgIIAgAAAA==.Raídbos:BAAANQADCgEIAQAAAA==.',
Re='Reedy:BAAANQAECgcIDAAAAA==.Reililim:BAAANQADCgIIAgAAAA==.Reladria:BAAANQAECgcIEAAAAA==.Renren:BAAANQAECgEIAQAAAA==.Renrenboomy:BAAANQADCggIDwAAAA==.Rentheous:BAAANQADCgYIBgABNQADCggIDwABAAAAAA==.Restopig:BAAANQAECgQICAAAAA==.Retage:BAAANQAECgMIBQAAAA==.Retbro:BAAANQADCgYICwAAAA==.Revii:BAAANQAECgUIBwAAAA==.',
Rh='Rhaedryana:BAAANQADCgYIBgAAAA==.Rhinock:BAAANQADCgcIDAAAAA==.Rhinoh:BAAANQADCggIFQAAAA==.Rhover:BAAANQADCgcIBwABNQAECgMIAwABAAAAAA==.Rhyfelpod:BAAANQAECgcIDQAAAA==.Rhymenocerus:BAAANQAECgEIAQAAAA==.',
Ri='Riftera:BAAANQADCgYICwABNQAECgkJGAADANIkAA==.Ringostaarr:BAAANQADCggIDgAAAA==.Rinkleesak:BAAANQADCgMIBgABNQAECgUIEAABAAAAAA==.Ripiggy:BAAANQAECgIIAgAAAA==.Ripto:BAAANQAECgEIAQAAAA==.Rivi:BAAANQADCggIEgABNQAECgUIEAABAAAAAA==.',
Ro='Roeilai:BAAANQADCgMIBAAAAA==.Rogbert:BAAANQAECgQICAAAAA==.Roidboss:BAAANQADCggIHgAAAA==.Rokarn:BAAANQAECgYIEwAAAA==.',
Rr='Rr:BAAANQAECgQICgAAAA==.',
Ry='Rysan:BAAANQADCggICQABNQAECgUIBwABAAAAAA==.',
Sa='Saani:BAAANQADCggIDgAAAA==.Saber:BAAANQAECgUIBwAAAA==.Sabré:BAAANQADCggIDwAAAA==.Saddragon:BAAANQAECgIIAwABNQAECgEIAwABAAAAAA==.Sadoderé:BAAANQAECgQIBAAAAA==.Saelor:BAAANQAFFAEIAwAAAA==.Saennia:BAAANQAECgUIBgAAAA==.Saetan:BAAANQADCgYIBgAAAA==.Sagje:BAAANQADCggIFAAAAA==.Sagjiie:BAAANQADCgEIAQABNQADCggIFAABAAAAAA==.Sagé:BAAANQAECgQIBAAAAA==.Salestra:BAAANQADCgYICAAAAA==.Saloondoors:BAAANQAECgYICwAAAA==.Sameara:BAAANQAECgIIAgAAAA==.Samila:BAAANQAECgQIBAAAAA==.Sandioncrack:BAAANQAECgIIBAAAAA==.Sappheiros:BAAANQAECgEIAQAAAA==.Sareila:BAAANQADCgcIEwAAAA==.Savaris:BAAANQADCggIIAAAAA==.Savis:BAAANQAECgYIDQAAAA==.',
Sc='Scatho:BAAANQADCgYIBgAAAA==.',
Se='Seakay:BAAANQAECgIIAgAAAA==.Seladang:BAAANQAECgMIAwABNQAECgcICQABAAAAAA==.Selenabowmez:BAAANQAECgUICAAAAA==.Serdeath:BAAANQADCgMIAwAAAA==.Serenitymick:BAAANQABCgIIAgAAAA==.Servellan:BAAANQADCgcICQAAAA==.',
Sf='Sfetti:BAAANQAECgcIDQAAAA==.',
Sh='Shabar:BAAANQAECgcIEAAAAA==.Shadowarrior:BAAANQADCgYIBgAAAA==.Shadowevil:BAAANQAECgIIAgAAAA==.Shadowmoonn:BAAANQADCgUIBwAAAA==.Shaimara:BAAANQAECggIEwAAAA==.Shaimu:BAAANQADCggIEAAAAA==.Shamayonaise:BAAANQAECgYICwAAAA==.Shamosh:BAAANQADCggIGgAAAA==.Sharrowsham:BAAANQADCggICAAAAA==.Sherkizk:BAAANQAECgYIBwAAAA==.Shiomi:BAAANQAECgQIBAAAAA==.Shivhappens:BAAANQADCgcIEgAAAA==.Shockolat:BAAANQADCgYIBgAAAA==.Shopintrolli:BAAANQADCgcIFQAAAA==.Shottigrippa:BAAANQADCgUIBQAAAA==.',
Si='Sible:BAAANQADCgUIDwAAAA==.Siilver:BAAANQAECgYIBwAAAA==.Sikla:BAAANQAECgIIAgAAAA==.Silverbreeze:BAAANQAECgEIAQAAAA==.Simadin:BAAANQAECgIIBQAAAA==.Singletarget:BAAANQAECgQICAAAAA==.',
Sk='Sk:BAAANQAECgIIAgAAAA==.Skaðizie:BAAANQADCgcIFQAAAA==.Skrunkly:BAAANQAECgQIBQAAAA==.Skullflare:BAAANQADCgYIBgABNQAECgQIBgABAAAAAA==.Skyrun:BAAANQADCgYIDQAAAA==.Skyíerxy:BAAANQAECgQIBgAAAA==.',
Sl='Slatefox:BAAANQAECgIIAwAAAA==.',
Sm='Smoothy:BAAANQAFFAEIAQAAAA==.',
Sn='Sniffington:BAAANQAECgQIBgAAAA==.Sniggles:BAAANQADCgYIBgAAAA==.Snoofÿ:BAAANQADCgUIBQAAAA==.Snotshöt:BAAANQAECgEIAQAAAA==.',
So='Sockadin:BAAANQADCgMIAwAAAA==.Sockhuntr:BAAANQADCgQIBAAAAA==.Sohei:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.Solargeist:BAAANQADCgcIBwAAAA==.Sonoka:BAAANQAECgIIBQAAAA==.Sooffy:BAAANQAECgYIDAAAAA==.Sor:BAAANQADCggIAQAAAA==.Soryu:BAAANQADCgIIAgAAAA==.',
Sp='Sparvo:BAAANQAECgIIAwAAAA==.Spawñ:BAAANQAECgMIAwAAAA==.Spellwave:BAAANQAECgEIAQAAAA==.Spiicy:BAAANQADCgMIAwABNQADCgMIAwABAAAAAA==.Spippy:BAAANQADCgcIBwAAAA==.Splashzonë:BAAANQAECgMIBAAAAA==.Spootless:BAAANQAECgMIAwAAAA==.Sprouters:BAAANQADCgEIAQAAAA==.Sprouties:BAAANQAECgUIDwAAAA==.',
St='Stab:BAAANQADCgcIBwAAAA==.Stav:BAAANQADCggIFgABNQAECgcIEwABAAAAAA==.Stealthybaz:BAAANQAECgEIAQAAAA==.Sterixi:BAAANQADCgcIBgAAAA==.Stickward:BAAANQAECgEIAQAAAA==.Stoen:BAAANQAECgcIEwAAAA==.Stolemumscar:BAAANQADCgcIBwAAAA==.Stonetalent:BAAANQABCgYICgAAAA==.Stormclaw:BAAANQAECgQIBgAAAA==.Stormclaws:BAAANQADCgEIAQABNQAECgQIBgABAAAAAA==.Streetjezus:BAAANQADCgIIAgABNQAECgUICAABAAAAAA==.Strhaza:BAAANQADCggICAABNQAECgMIAwABAAAAAA==.Strogganoff:BAAANQAECgQIBQAAAA==.Stòrmy:BAAANQADCgcIDQAAAA==.',
Su='Sulakin:BAAANQADCgYIEQAAAA==.Sumatru:BAAANQAECgYICwAAAA==.Sustained:BAAANQADCggIDgAAAA==.Suwee:BAAANQAECgIIAwABNQAECgQIBAABAAAAAA==.Suweetcheeks:BAAANQAECgQIBAAAAA==.Suzuchan:BAAANQAECgQIBgAAAA==.',
Sw='Swagrid:BAAANQAECgQIBQAAAA==.',
Sx='Sxix:BAAANQAECgEIAgAAAA==.',
Sy='Sygrogiàn:BAABNQAECoEVAAMMAAgJYhnbFAB/AgAMAAgJYhnbFAB/AgANAAQJpASFKADMAAAAAA==.Sylrune:BAAANQAECgQIBAAAAA==.Syrenaria:BAAANQADCgcIEQAAAA==.',
Ta='Taelthas:BAAANQAECgQIBAAAAA==.Tagazog:BAAANQADCgYIBgAAAA==.Tahlana:BAAANQADCgYIDQAAAA==.Takabuka:BAAANQADCggIDQAAAA==.Takkumampu:BAAANQAECgMIBAAAAA==.Taladañ:BAAANQABCgQIBAAAAA==.Talanthae:BAAANQAECgIIAgAAAA==.Talent:BAAANQADCgYIBgAAAA==.Taserface:BAAANQAECgYIDAAAAA==.Tathagor:BAAANQADCggIIAAAAA==.',
Te='Teachernote:BAAANQADCgYIDwAAAA==.Teaora:BAAANQADCgcIFQAAAA==.Tefli:BAAANQAECgQIBgAAAA==.Tenuki:BAAANQAECgYICAAAAA==.',
Th='Theboo:BAAANQAECgQIBQAAAA==.Thefaveazn:BAAANQADCgYIDwAAAA==.Theimppimp:BAAANQABCgYICQAAAA==.Thelayl:BAAANQAECgQIBgAAAA==.Themaladan:BAAANQADCgYICwABNQAECgIIBQABAAAAAA==.Theodoros:BAAANQADCggIIAABNQAECgYICwABAAAAAA==.Theolethros:BAAANQAECgYICwAAAA==.Thewizeone:BAAANQAECgQIBAAAAA==.Thomö:BAAANQAECgIIAgAAAA==.Thorarchmage:BAAANQAECgIIAgAAAA==.Thorickto:BAAANQAECgEIAQAAAA==.Thorr:BAAANQAECgcICQABNQAECgcIEwABAAAAAA==.Thorsky:BAAANQADCgUIBQAAAA==.Throatslit:BAAANQADCgcICQAAAA==.Thunderfists:BAAANQADCgYICwAAAA==.',
Ti='Tiberium:BAAANQAECgQIBQAAAA==.Tin:BAAANQAECgcIDAABNQAECgIIAgABAAAAAA==.Tipsyclick:BAAANQAECgYICgAAAA==.Tirraz:BAAANQADCgYIBgAAAA==.Tirti:BAAANQAECgEIAQABNQAECgcIEAABAAAAAA==.',
To='Tod:BAAANQADCggIFQAAAA==.Toodemented:BAAANQADCgEIAQAAAA==.Toodlez:BAAANQAECgIIAgAAAA==.Toughmoecha:BAAANQAECgcIEAAAAA==.',
Tr='Trenpanda:BAAANQAECgUIBQAAAA==.Trinelle:BAAANQAECgQIBQAAAA==.Trorr:BAAANQAECgIIAgAAAA==.',
Ts='Tszyu:BAAANQAECgEIAQAAAA==.',
Tt='Tthor:BAAANQAECgcIEwAAAA==.',
Tu='Tumbawumba:BAAANQAECggICAAAAA==.Turango:BAAANQADCgUIDwABNQADCggIIAABAAAAAA==.Turkandar:BAAANQADCggIFQAAAA==.Turkblond:BAAANQADCgYIBgAAAA==.Turkinater:BAAANQADCgYIDgAAAA==.Turkmag:BAAANQADCgQIBAAAAA==.Turkpand:BAAANQABCgQIBAAAAA==.',
Tw='Twidgey:BAAANQAECgUIBwAAAA==.Twilightl:BAAANQAECgUIBQAAAA==.Twizzler:BAAANQADCgUIBQAAAA==.',
Ty='Tydrocast:BAAANQADCgUIBQAAAA==.Tylamoriel:BAAANQADCgcICAAAAA==.Typhist:BAAANQADCgYIAgAAAA==.Typhouge:BAAANQADCggIDQAAAA==.Tyrandewhis:BAAANQAECgQIBAABNQAECgkJFwACANUiAA==.Tythramor:BAAANQAECgQIBgAAAA==.',
['Tó']='Tóomi:BAAANQAECgcIEQAAAA==.',
Ul='Ulfvaar:BAAANQAECgEIAQAAAA==.',
Um='Umairah:BAAANQAECggIEgAAAA==.Umbrageist:BAAANQAECgIIBAAAAA==.',
Un='Unbearable:BAAANQADCgYIDwAAAA==.Unholyjlab:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.Unmilkable:BAAANQAECgIIAwAAAA==.',
Ur='Urglefloggah:BAAANQADCgYIDQAAAA==.',
Uy='Uyko:BAAANQAECgMIAwAAAA==.',
Va='Vabos:BAAANQADCgYIBgAAAA==.Vachan:BAAANQADCgUIBQAAAA==.Vaedor:BAAANQAECgQIBAAAAA==.Vagiant:BAAANQAECgUIDQAAAA==.Vakahna:BAAANQADCgcIBwABNQAECgQIBQABAAAAAA==.Vako:BAAANQADCgcIBwAAAA==.Valea:BAAANQAECgMIAwAAAA==.Valenya:BAAANQAECgQIBgAAAA==.Valestraee:BAAANQADCggIEwAAAA==.Valinys:BAAANQABCgIIAgAAAA==.Valkyrja:BAAANQAECgEIAQAAAA==.Vandarkholme:BAAANQADCgYIBgAAAA==.Vansa:BAAANQADCgUIBQABNQADCgcIDQABAAAAAA==.Varantus:BAAANQADCgcIEwAAAA==.Varenda:BAAANQAECgEIAQAAAA==.Varrior:BAABNQAECoEYAAIWAAkJOiWLAgDDAwAWAAkJOiWLAgDDAwAAAA==.Vassallo:BAAANQAECgQIBAAAAA==.Vatcharin:BAAANQAECgUIBgAAAA==.',
Ve='Veelayna:BAAANQADCgcIEAAAAA==.Velirys:BAAANQADCgEIAQAAAA==.Velvetdreams:BAAANQADCgYIDAAAAA==.Vengefilth:BAAANQAECgcIDQAAAA==.Veralei:BAAANQAECgIIAwAAAA==.Verrior:BAABNQAECoEYAAIVAAkJcRmxAgC4AgAVAAkJcRmxAgC4AgAAAA==.Veshale:BAAANQADCgIIAgAAAA==.Vesherok:BAAANQAECgEIAQAAAA==.Veylira:BAAANQAECgEIAQAAAA==.',
Vi='Vic:BAAANQAECgEIAQAAAA==.Viebae:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Viebai:BAAANQAECgMIAwABNQAECgEIAQABAAAAAA==.Viehi:BAAANQAECgEIAQAAAA==.Viekay:BAAANQADCgUIBgABNQAECgEIAQABAAAAAA==.Vienir:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.Vieno:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Vietoo:BAAANQADCggIEwABNQAECgEIAQABAAAAAA==.Vigilante:BAAANQAECgIIAwAAAA==.Vitalizes:BAAANQAECgYICwAAAA==.',
Vo='Voidbunny:BAAANQABCgIIAgAAAA==.Voidmaple:BAAANQAECgEIAQAAAA==.Voidnerissa:BAAANQAECgEIAQAAAA==.Volatilehugs:BAAANQAECgEIAQAAAA==.',
Vu='Vulpeera:BAAANQABCgYIAwAAAA==.',
Vy='Vyndrolar:BAAANQADCggIEwAAAA==.',
Wa='Wafflefloof:BAAANQAECgIIAgABNQADCgMIBAABAAAAAA==.Wallpuncher:BAAANQADCgUIBwAAAA==.Warbsy:BAAANQADCgQIBQAAAA==.Warimoh:BAAANQADCggICAABNQAECgcICwABAAAAAA==.Warlocknon:BAAANQAECgQIBAAAAA==.Warriorscott:BAAANQAECgEIAQAAAA==.Warstine:BAAANQAECgcIEAAAAA==.Wasahk:BAAANQAECgQIBQAAAA==.Watchar:BAAANQAECgYICwAAAA==.',
We='Wessa:BAAANQADCgcIBwAAAA==.Wetfur:BAAANQADCgYIDwAAAA==.',
Wh='Whiskcy:BAAANQADCgcIFQAAAA==.',
Wi='Wicklez:BAAANQADCgYIBgAAAA==.Wifii:BAAANQAECgEIAQAAAA==.Wildhêart:BAAANQADCgcIBwAAAA==.Wilkie:BAAANQAECgEIAQAAAA==.Wilnikyastuf:BAAANQAECgEIAQAAAA==.Window:BAAANQADCgYIBwABNQAECgQIBAABAAAAAA==.Winnygolds:BAAANQABCgMIBgAAAA==.Witrin:BAAANQAECgIIAgAAAA==.',
Wo='Worgana:BAAANQAECgcIDwAAAA==.Wotenhearg:BAAANQADCgYIDgAAAA==.',
Wu='Wuffiandesu:BAAANQADCgUIBQAAAA==.',
Wy='Wyrdevoke:BAAANQAECgcIEwAAAA==.',
['Wä']='Wäyda:BAAANQABCgIIAgAAAA==.',
['Wí']='Wíld:BAAANQADCgYIBgABNQAECgkJFwAKADgkAA==.',
['Wî']='Wîld:BAABNQAECoEXAAIKAAkJOCTsAQCBAwAKAAkJOCTsAQCBAwAAAA==.',
Xa='Xamchi:BAAANQADCgYIBgAAAA==.Xamhorns:BAAANQAECgEIAQAAAA==.Xanalor:BAAANQADCgcIBwABNQAECgQIBQABAAAAAA==.Xandov:BAAANQAECgQIBQAAAA==.Xaner:BAAANQADCgcIBwABNQAECgQIBQABAAAAAA==.Xanteen:BAAANQADCgUIBQAAAA==.Xathrian:BAAANQADCgUIBQAAAA==.',
Xe='Xeropally:BAAANQAECgQIBAAAAA==.Xervish:BAAANQADCgQIBAAAAA==.Xevrion:BAAANQAECgcIEQAAAA==.',
Xi='Xifer:BAAANQAECgYICAAAAA==.',
Xo='Xocks:BAAANQADCggICAAAAA==.Xolialumbra:BAAANQAECgIIAwAAAA==.',
Xs='Xsurani:BAAANQAECgEIAgAAAA==.',
Ya='Yaimakmak:BAAANQAECgUIBQAAAA==.Yamargi:BAAANQADCggIDwAAAA==.',
Ye='Yeahbuggzy:BAAANQAECgUIBQAAAA==.',
Yh='Yhazzmine:BAAANQAECgQIBQAAAA==.',
Yo='Yohda:BAAANQAECgQIBgAAAA==.Yomumma:BAAANQAECgEIAQAAAA==.',
Ys='Ysabbell:BAAANQAECgEIAQAAAA==.Ysone:BAAANQADCggIDgAAAA==.',
Za='Zaarkann:BAAANQADCggIDgAAAA==.Zailen:BAAANQADCggIFwAAAA==.Zappymcblam:BAAANQAECgQIBQAAAA==.Zarba:BAAANQADCgcIFAAAAA==.Zariallyn:BAAANQADCggIFwAAAA==.',
Ze='Zebba:BAAANQAECgQIBAAAAA==.Zeldoris:BAAANQABCgQIBgAAAA==.Zenky:BAAANQAECgMIAwAAAA==.Zephaeryn:BAAANQADCggIEQAAAA==.Zeykoyu:BAAANQAECgMIAwAAAA==.',
Zi='Zigbiy:BAAANQADCgMIAwAAAA==.',
Zn='Znemde:BAAANQADCgYIBwAAAA==.',
Zo='Zollmalath:BAAANQADCgIIAgAAAA==.',
Zu='Zuczuc:BAAANQABCgIIAgAAAA==.Zumwalt:BAAANQAECgcICwAAAA==.Zunther:BAAANQAECgIIAgAAAA==.Zus:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.Zuzum:BAAANQADCggICAAAAA==.',
Zy='Zyræl:BAAANQADCgYIBgAAAA==.',
['Zú']='Zúës:BAAANQAECgEIAQABNQAECgYICwABAAAAAA==.',
['Ðr']='Ðryks:BAAANQADCgYIDAAAAA==.',
['Ðu']='Ðurakwir:BAAANQADCgMIAwAAAA==.',
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
