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

local lookup = {'DemonHunter-Havoc','Unknown-Unknown','Priest-Shadow','Evoker-Preservation','Evoker-Devastation','Rogue-Assassination','Rogue-Subtlety','Priest-Holy','Shaman-Restoration','Warlock-Destruction','DeathKnight-Unholy','Mage-Arcane','Monk-Brewmaster','Warlock-Affliction','Warlock-Demonology','Paladin-Holy','Paladin-Retribution','Shaman-Elemental','Druid-Guardian','Monk-Windwalker','DemonHunter-Vengeance','Hunter-BeastMastery','Monk-Mistweaver','Druid-Balance','DemonHunter-Devourer','Hunter-Marksmanship','Priest-Discipline','DeathKnight-Blood','Paladin-Protection','Warrior-Arms','Warrior-Fury','Mage-Frost',}
local provider = {region='US',realm="Khaz'goroth",name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Abaddom:BAAANQAECgIIBAAAAA==.Abassa:BAAANQADCgUIBwAAAA==.Abyssalblade:BAAANQAECgcIDQAAAA==.Abyssia:BAAANQAECgEIAQAAAA==.',
Ac='Acidfier:BAAANQADCggICAAAAA==.Ackwah:BAAANQAECgUIEgAAAA==.Actaeön:BAAANQADCgcIDQAAAA==.Acupuncher:BAAANQAECgIIBgAAAA==.Acutar:BAAANQADCgYIEgAAAA==.',
Ad='Adamance:BAAANQADCggICAABNQAECggIEgABAHwVAA==.Adeemo:BAAANQAECgEIAgAAAA==.Adrielar:BAAANQADCgYIBgAAAA==.Adámant:BAABNQAECoESAAIBAAgJfBXSDABAAgABAAgJfBXSDABAAgAAAA==.',
Ae='Aedd:BAAANQADCgYIBgAAAA==.Aeirra:BAAANQAECgQIDgAAAA==.Aengima:BAAANQADCgEIAQAAAA==.Aestryn:BAAANQAECgEIAQAAAA==.',
Ah='Ahpolynomial:BAAANQADCggICAAAAA==.Ahsokatano:BAAANQAECgQIBgAAAA==.',
Ai='Aillie:BAAANQAECgYICQAAAA==.Aiyawa:BAAANQAECgQIBAAAAA==.Aizmirst:BAAANQAECgIIAgAAAA==.',
Ak='Akaisha:BAAANQABCgUIBwAAAA==.',
Al='Alarÿ:BAAANQAECgYICQAAAA==.Aldrettius:BAAANQAECgQIBAABNQAECgQICgACAAAAAA==.Aldrêttius:BAAANQAECgQICgAAAA==.Alexandrion:BAAANQADCgQIBAAAAA==.Algove:BAAANQAECgMIBgAAAA==.Alicity:BAAANQADCgYICwAAAA==.Alkyrie:BAAANQAECgQIDAAAAA==.Alleiria:BAAANQAECgcIEAAAAA==.Allhammer:BAAANQADCgYIBwAAAA==.Alliiran:BAAANQAECgcIDAAAAA==.Alphônse:BAAANQADCggIFQAAAA==.Altherius:BAAANQAECgEIAQAAAA==.Alucârd:BAAANQAECgQIBAAAAA==.Alumar:BAAANQADCggIDwAAAA==.Aléus:BAAANQAECgYICgAAAA==.',
Am='Amyn:BAAANQADCgcIBgAAAA==.',
An='Anane:BAAANQADCgcIEgAAAA==.Anasteriian:BAAANQAECgEIAQAAAA==.Anddi:BAAANQADCgcIDQAAAA==.Angelism:BAABNQAFFIEFAAIDAAUJehOxAADFAQADAAUJehOxAADFAQAAAA==.Anine:BAAANQAECgMIBAAAAA==.Anketell:BAAANQAECgUICgAAAA==.Annkulotz:BAAANQAECgQIBAAAAA==.Anohti:BAAANQADCgYIBgAAAA==.Antoranthree:BAABNQAECoEZAAMEAAgJ9BIxEADIAQAEAAcJtRIxEADIAQAFAAIJ2wuPHAB4AAAAAA==.',
Ap='Aphasiawye:BAAANQAECgQICAAAAA==.Aphell:BAAANQAECgMIBAAAAA==.Apocryphal:BAAANQAECgUIBgAAAA==.Apopshunter:BAAANQAECgIIAwAAAA==.',
Aq='Aquamage:BAAANQADCgcIBwABNQAECgUIEgACAAAAAA==.',
Ar='Araiak:BAAANQAECgQIBAABNQAECgkJGAAGABIcAA==.Araiakk:BAABNQAECoEYAAMGAAkJEhxFCgAaAgAGAAcJBhdFCgAaAgAHAAYJOxwEEQDxAQAAAA==.Arakz:BAAANQAECgQIBgAAAA==.Arallia:BAABNQAECoEYAAIIAAkJPyASCgDQAgAIAAkJPyASCgDQAgAAAA==.Arallija:BAAANQAECgIIAgAAAA==.Arbrack:BAAANQAECgMIBAAAAA==.Arch:BAAANQAECgQIBwAAAA==.Arctauran:BAAANQADCgMIAgAAAA==.Areaky:BAAANQADCgcIGgAAAA==.Arianamarie:BAAANQAECgYICgAAAA==.Arkdrood:BAAANQAECgQICAAAAA==.Arkelicious:BAAANQADCggICAAAAA==.Arkinup:BAAANQADCgcIFQAAAA==.Arrowrin:BAAANQADCgUIBQABNQAECgEIAQACAAAAAA==.Artimes:BAAANQADCggICAABNQAECgMIAwACAAAAAA==.',
As='Asasia:BAAANQADCggIFAAAAA==.Aserlock:BAAANQADCgQIAwABNQADCgYIBgACAAAAAA==.Aserpala:BAAANQADCgYIBgAAAA==.Ashalune:BAAANQAECgEIAQAAAA==.Ashanormu:BAAANQADCgUIBQABNQAECgEIAQACAAAAAA==.Ashendary:BAAANQAECgcIDAAAAA==.Asterisk:BAAANQABCgQIBAAAAA==.',
At='Atchias:BAAANQAECgIIAgAAAA==.Aths:BAAANQAECgQIBQAAAA==.Attachedruid:BAAANQAECgYIBgABNQAECgYICwACAAAAAA==.Attachedsham:BAAANQAECgYICwAAAA==.Attís:BAAANQADCgYIBgAAAA==.',
Au='Auroraknight:BAAANQADCgcIBgAAAA==.Aussyey:BAAANQAECgYICgAAAA==.Aussyp:BAAANQAECgIIAwABNQAECgYICgACAAAAAA==.Autumnbury:BAAANQADCgUIBQAAAA==.',
Ay='Aytrune:BAAANQAECgEIAQAAAA==.',
Az='Azaraler:BAAANQAECgUICgAAAA==.Azraelor:BAAANQADCggICAABNQAECgcIDQACAAAAAA==.Azraiel:BAAANQAECgQIBwAAAA==.Azureuz:BAAANQAECgYICAAAAA==.',
Ba='Baalz:BAAANQADCgcIEgAAAA==.Backhair:BAAANQAECgcIDgAAAA==.Badimps:BAAANQADCgYIBgABNQAECgkJGAAJAKYiAA==.Badpriest:BAAANQAECgEIAQABNQAECgkJGAAJAKYiAA==.Badsham:BAABNQAECoEYAAIJAAkJpiK6AgB3AwAJAAkJpiK6AgB3AwAAAA==.Badshaman:BAAANQADCggICAAAAA==.Badtóuch:BAAANQAECgYICwAAAA==.Badwarlock:BAAANQADCggICAAAAA==.Badzugzug:BAAANQAECgEIAQAAAA==.Baelfoar:BAAANQAECgIIBAAAAA==.Baindage:BAAANQAECgcIDwAAAA==.Baininator:BAAANQAECgMIAwABNQAECgcIDwACAAAAAA==.Baj:BAABNQAECoEYAAIKAAkJoB15AQBEAwAKAAkJoB15AQBEAwAAAA==.Bakugo:BAAANQADCggICAABNQAECgIIAgACAAAAAQ==.Balock:BAAANQAECgQIBwAAAA==.Balthamael:BAAANQADCggIEQAAAA==.Banoffi:BAAANQADCgYIDgAAAA==.Baptism:BAAANQAECgQIDAAAAA==.Barabel:BAAANQADCgIIAgAAAA==.Barfonimous:BAAANQADCgQIBQAAAA==.Barrazza:BAAANQABCgEIAQAAAA==.Barricade:BAAANQADCgcIDAAAAA==.Bashath:BAAANQADCgYIBwAAAA==.Batboi:BAAANQAECgQIBAAAAA==.Baz:BAAANQAECgEIAQAAAA==.',
Bb='Bbora:BAAANQAECgEIAQAAAA==.',
Be='Bearbottom:BAAANQADCgcIDAAAAA==.Bearicade:BAAANQAECgQIBAAAAA==.Beewe:BAAANQADCgIIAgAAAA==.Belanguis:BAAANQADCggIFgAAAA==.Beni:BAAANQAECgEIAQAAAA==.Bennimaru:BAAANQADCgYIBgAAAA==.Bexta:BAAANQADCgUIBQAAAA==.',
Bi='Bidzz:BAAANQAECgEIAQAAAA==.Binchikin:BAAANQAECgQIBgAAAA==.',
Bl='Blackscale:BAAANQAECgEIAQAAAA==.Bladeygaga:BAAANQAECgMIAwAAAA==.Blarrg:BAAANQADCggIFgAAAA==.Blazedk:BAAANQADCgIIAgAAAA==.Blazingdeath:BAAANQAECgQIBgAAAA==.Blazon:BAAANQADCggICAAAAA==.Bloodednuzz:BAAANQAECgEIAQAAAA==.Bluntaxe:BAAANQADCgQIBAAAAA==.',
Bo='Bojamba:BAAANQADCgIIAgAAAA==.Boland:BAAANQAECgEIAQAAAA==.Bombeeky:BAAANQADCgYIEAAAAA==.Boodsy:BAAANQADCgcIBwAAAA==.Boomlock:BAAANQAECgEIAQAAAA==.Booshti:BAAANQADCgYIDAABNQAECgcIDQACAAAAAA==.Bosora:BAAANQADCgYIBgABNQAECgYICwACAAAAAA==.Boulvar:BAAANQABCgQIBQAAAA==.',
Br='Brahmin:BAAANQADCgEIAQAAAA==.Braingap:BAAANQAECgUIBgAAAA==.Brandooni:BAAANQADCgIIAwAAAA==.Brewdk:BAAANQAECgMIBAAAAA==.Brodeadious:BAAANQAECgYIBgAAAA==.Brotherdrood:BAAANQADCgYICAAAAA==.Brotherdwarf:BAAANQAECgQIBwAAAA==.Brunetta:BAAANQAECgYICAAAAA==.Brynhîldr:BAAANQADCgYIEgAAAA==.',
Bu='Bumblbea:BAAANQADCggIFAAAAA==.Buncicle:BAAANQAECgQIBAABNQAECgcIDwACAAAAAA==.Bundycat:BAAANQAECgUIBwAAAA==.Bunnifer:BAAANQAECgIIAwABNQAECgcIDwACAAAAAA==.Bunsxo:BAAANQAECgcIDwAAAA==.Burgshot:BAAANQADCgUIBQAAAA==.Burno:BAAANQADCggIDAABNQAECggIDwACAAAAAA==.',
['Bé']='Béørn:BAAANQAECgEIAQAAAA==.',
['Bï']='Bïill:BAAANQADCgcIDQAAAA==.',
['Bò']='Bòggie:BAACNQAFFIEHAAILAAQJRhHpAABDAQALAAQJRhHpAABDAQA1AAQKgRkAAgsACQmzItsCAJYDAAsACQmzItsCAJYDAAAA.',
Ca='Cadburychomp:BAAANQAECgUIBQAAAA==.Caedaari:BAAANQAECgEIAQAAAA==.Cairos:BAAANQAECgEIAQAAAA==.Caldaemon:BAAANQAECgMIBAAAAA==.Caothanis:BAAANQADCgYIEAAAAA==.Caphalor:BAAANQAECgYICAAAAA==.Cappuchino:BAAANQADCggICAAAAA==.Captinjack:BAAANQADCgYICgAAAA==.Carawar:BAAANQAECgYICAAAAA==.Carámel:BAAANQAECgcIBwAAAA==.Cashdk:BAAANQADCgYIBgAAAA==.Catgirltamer:BAAANQADCggIEwAAAA==.Cayder:BAAANQADCggIEQAAAA==.Cayether:BAAANQAECgIIBAAAAA==.Cayneth:BAAANQAECgEIAQAAAA==.',
Ce='Celarelia:BAAANQADCgQIBAAAAA==.Celestiallok:BAAANQAECgQIBAAAAA==.Celestlmage:BAABNQAECoEVAAIMAAkJPyRfAwC2AwAMAAkJPyRfAwC2AwAAAA==.Celorimran:BAAANQAECgMICAAAAA==.Cementhead:BAAANQADCgMIAwABNQAECggICgACAAAAAA==.Cendin:BAAANQADCgYIBwAAAA==.Cerebral:BAAANQAECgYICgAAAA==.Cesspool:BAAANQAECgUIEAAAAA==.Cesspools:BAAANQADCgYIHAABNQAECgUIEAACAAAAAA==.Cettie:BAAANQAECgMIAwAAAA==.',
Ch='Cheddar:BAAANQAECgcIDQAAAA==.Chirpeh:BAAANQAECgQIBgAAAA==.Choicebeast:BAAANQADCgcIBwABNQAECgMIBgACAAAAAA==.Choodmarani:BAAANQAECgQIDAAAAA==.Choofa:BAAANQADCggIFgAAAA==.Choppingdmg:BAAANQAECgMIBAAAAA==.Chordatan:BAAANQAECgEIAQAAAA==.Chrónos:BAAANQAECgcIDQABNQAFFAUIBgANAGcJAA==.Chucklee:BAAANQADCgIIAgAAAA==.Chunkycess:BAAANQADCgYIBgABNQAECgUIEAACAAAAAA==.',
Ci='Cindafella:BAAANQAECgMIBAAAAA==.',
Cl='Clareitheria:BAAANQADCgYICAAAAA==.Clarkson:BAAANQAECgUIBgAAAA==.Clerial:BAAANQABCgYIBgAAAA==.Cloudhuntër:BAAANQADCgIIAgAAAA==.',
Co='Cobrakaì:BAAANQADCggICAAAAA==.Combustya:BAAANQADCggICAAAAA==.Conjuredmilk:BAAANQADCggIFAAAAA==.Coode:BAAANQADCgIIAgAAAA==.Costafruit:BAAANQADCgQIBAABNQAECgEIAQACAAAAAA==.Cowvid:BAAANQAECgQICAAAAA==.',
Cr='Crawford:BAAANQAECgQIBgAAAA==.Crimz:BAAANQADCgYICwAAAA==.Crispi:BAAANQAECgQIDQAAAA==.Crit:BAAANQAECgQIBgAAAA==.',
Cu='Cucu:BAAANQAECgQIDAAAAA==.Cultured:BAAANQAECgIIAgABNQAECgQIEgACAAAAAA==.',
Cy='Cynnsdead:BAAANQAECgIIBAAAAA==.Cynthea:BAAANQABCgYIBwAAAA==.',
Da='Daddyhands:BAAANQADCgYICgAAAA==.Daddylua:BAAANQAECgQICQAAAA==.Daeshim:BAAANQADCgIIAgABNQAECgEIAgACAAAAAA==.Dahlila:BAAANQADCggIFAAAAA==.Dakila:BAAANQADCgUICAAAAA==.Damahs:BAAANQAECgEIAQAAAA==.Dangao:BAAANQAECgQIBgAAAA==.Dareapa:BAAANQAECgMIBAAAAA==.Darkasha:BAAANQAECgEIAQAAAA==.Darkballs:BAAANQADCgEIAQABNQAECgEIAQACAAAAAA==.Darkburn:BAAANQADCgUICwAAAA==.Darkdots:BAAANQADCgQIBQAAAA==.Darkopal:BAAANQADCgIIAgAAAA==.Darksõul:BAAANQADCgYICwAAAA==.Darktiger:BAAANQADCgYIDQAAAA==.Darrant:BAAANQAECgEIAQAAAA==.Darthdecimus:BAAANQADCgYICQAAAA==.Dashifter:BAAANQADCgYIBgAAAA==.Dawarlord:BAAANQADCggIBAAAAA==.',
De='Deadseye:BAAANQADCggICwAAAA==.Deadthan:BAAANQADCggIFgAAAA==.Deathshnd:BAAANQADCggICQAAAA==.Deathxpress:BAABNQAECoEVAAIGAAkJIhpNAwAHAwAGAAkJIhpNAwAHAwAAAA==.Deathyeet:BAAANQADCggICwAAAA==.Debrad:BAAANQADCgYIGAAAAA==.Deewizz:BAAANQAECgcIEQAAAA==.Defance:BAAANQAECgEIAQAAAA==.Defazknight:BAAANQABCgIIAgAAAA==.Deff:BAAANQAECgEIAQAAAA==.Defsnotamage:BAAANQABCgQIBAAAAA==.Demonexpress:BAAANQADCgYICwAAAQ==.Demonicbacon:BAAANQADCggIGgAAAA==.Denifer:BAAANQAECgQICQAAAA==.Denona:BAAANQAECgUIEgAAAA==.Depi:BAAANQADCgcIBwABNQAECgIIAgACAAAAAA==.Dermeister:BAAANQADCgYIBgAAAA==.Desumasuku:BAAANQAECgEIAQAAAA==.Deverel:BAAANQADCgUIBQAAAA==.Dexx:BAAANQAECgYIBgAAAA==.Dexxd:BAAANQADCgEIAQABNQAECgYIBgACAAAAAA==.',
Di='Diabellstar:BAAANQAECggIFQAAAQ==.Dinoraa:BAAANQADCgUICwAAAA==.Dinorogue:BAAANQADCgYIBQAAAA==.Disolve:BAAANQADCgUIBQAAAA==.Disrupt:BAAANQADCgIIAwAAAA==.Divinity:BAAANQADCgYIBgAAAA==.',
Dm='Dmin:BAAANQADCgUIBQAAAA==.',
Do='Doll:BAAANQAECgIIAgAAAA==.Dolock:BAACNQAFFIEGAAMOAAMJkg1GAADAAAAOAAIJuhJGAADAAAAPAAEJQwPzEABFAAA1AAQKgScABAoACQnsHqAFAIgCAAoABwkJIaAFAIgCAA8ABgm7FxMoAM0BAA4ABAnPGt4EAF0BAAAA.Dotdaddy:BAAANQAECgEIAQABNQAECgcIDQACAAAAAA==.Dotless:BAAANQADCggIEwAAAA==.Doubleclicks:BAAANQAECgQICAAAAA==.',
Dr='Drabsham:BAAANQADCgYIBgAAAA==.Drawlin:BAAANQAECgEIAQAAAA==.Dreaming:BAAANQABCgIIAgABNQAECgQICAACAAAAAA==.Drellarn:BAAANQADCgYIBgAAAA==.Drellarne:BAAANQADCgIIAgAAAA==.Drexil:BAAANQADCggIFgAAAA==.Drool:BAAANQADCgYIDAAAAA==.Druidnique:BAAANQADCgMIAwAAAA==.Drulari:BAAANQAECgQIDAAAAA==.Drzoiidburg:BAAANQADCgcIDAAAAA==.',
Du='Dulfbron:BAAANQADCgYIBgAAAA==.',
Dw='Dwarfgazmik:BAAANQAECgEIAQAAAA==.Dwaynage:BAAANQAECgQIBQAAAA==.Dwayne:BAABNQAECoEXAAMQAAgJ0R3DDgCwAgAQAAgJ0R3DDgCwAgARAAMJHxP+eQC3AAAAAA==.',
Dy='Dyldk:BAAANQADCgEIAQABNQAECggICgACAAAAAA==.Dynamike:BAAANQADCgYIEQABNQAECgEIAgACAAAAAA==.Dysstatíc:BAAANQAECgUIBgAAAA==.Dysturbia:BAAANQADCgYIDAAAAA==.',
['Dú']='Dúza:BAAANQADCgUICgAAAA==.',
Eg='Egadazor:BAAANQAECgEIAQAAAA==.',
Ei='Einbroch:BAAANQAECgEIAQAAAA==.',
Ek='Ekarus:BAAANQABCgIIAgAAAA==.',
El='Elementalex:BAABNQAECoEZAAISAAkJ4h1IBgBWAwASAAkJ4h1IBgBWAwAAAA==.Eletea:BAAANQAECgcIDQAAAA==.Elijahangel:BAAANQAECgEIAQAAAA==.Elinera:BAAANQAECgQIBAAAAA==.Elissanora:BAAANQAECgMIBAAAAA==.Ellouise:BAAANQADCggIFAAAAA==.Elsidure:BAAANQADCggICAAAAA==.Elsiie:BAAANQADCgQIBgAAAA==.Elså:BAAANQAECgUICgAAAA==.Elviscious:BAAANQADCgcIDQABNQAECgEIAQACAAAAAA==.Elåin:BAAANQAECgEIAQAAAA==.',
En='Enzenia:BAAANQADCgcIEQAAAA==.',
Er='Eranei:BAABNQAECoEZAAIQAAkJLCFIAwBrAwAQAAkJLCFIAwBrAwAAAA==.Erimira:BAAANQADCgYIBgAAAA==.Ershim:BAAANQAECgQIBQAAAA==.Erzå:BAAANQAECgYICwAAAA==.',
Es='Espexie:BAAANQADCgYICwAAAA==.',
Et='Etharien:BAAANQADCgIIAgAAAA==.',
Ev='Evanthe:BAAANQAECgIIAgAAAA==.Evilchicken:BAAANQAECgEIAQAAAA==.Evistrianza:BAEANQADCggIFAAAAA==.Evokaderp:BAAANQAECgEIAQAAAA==.Evonehence:BAAANQAECgQIDAAAAA==.',
Ey='Eyoker:BAAANQAECgIIAgAAAA==.',
Ez='Ezarscarlet:BAAANQAECgIIAgAAAA==.',
Fa='Faragon:BAAANQADCgcIEAAAAA==.Fareeha:BAAANQADCgUIBQAAAA==.Fatalkink:BAAANQADCggIEwAAAA==.Faultea:BAAANQAECgQICAAAAA==.Fayleaves:BAAANQAECgQIBgAAAA==.',
Fe='Feleater:BAAANQAECgQIBgAAAA==.Felmaho:BAAANQADCgEIAQABNQAECgEIAQACAAAAAA==.Felphrena:BAAANQAECgIIAgAAAA==.Fembar:BAAANQADCgUIBgAAAA==.Feralaz:BAAANQADCgQIBAAAAA==.',
Fi='Finchy:BAAANQAECgUICAABNQAECgMIAwACAAAAAA==.Fistivity:BAAANQADCgIIAgAAAA==.Fistysmash:BAAANQADCgYIBgAAAA==.',
Fl='Flayualive:BAAANQADCggICAABNQAECgQIBAACAAAAAA==.Flëäbäg:BAAANQAECgEIAQAAAA==.',
Fo='Forkenslag:BAAANQADCgIIAgAAAA==.Fortiarrows:BAAANQAECgYIBgAAAA==.Fortiforms:BAAANQAECgUIBQABNQAECgYIBgACAAAAAA==.Foruon:BAAANQADCgMIAwAAAA==.Foshankai:BAAANQADCggIDwAAAA==.Foxychax:BAAANQAECgYIEgAAAA==.',
Fr='Frankdpriest:BAAANQABCgIIAgABNQABCgYICgACAAAAAA==.Freeused:BAAANQADCgIIAgAAAA==.Frenzee:BAAANQADCgUIBQAAAA==.Frip:BAAANQAECgcIDgAAAA==.Friskmage:BAAANQAECgEIAQAAAA==.Frisky:BAABNQAECoEZAAISAAkJLCLUBAByAwASAAkJLCLUBAByAwAAAA==.Frodobaggíns:BAAANQADCgYIBwAAAA==.Frostiemcduc:BAAANQADCggICAAAAA==.',
Fu='Furey:BAAANQAECgQIBgAAAA==.Furf:BAAANQAECgMIBAAAAA==.',
['Fá']='Fáitalïty:BAAANQADCgUIBwAAAA==.',
['Fæ']='Fæhecate:BAAANQADCgYICQAAAA==.',
Ga='Gaberiella:BAAANQAECgEIAwAAAA==.Gadodin:BAAANQAECgEIAQAAAA==.Galidiirn:BAABNQAECoEaAAITAAcJPBPnBgCoAQATAAcJPBPnBgCoAQAAAA==.Galila:BAAANQADCggIDQABNQAECgEIAQACAAAAAA==.Galinaedra:BAAANQABCgIIAgAAAA==.Gallade:BAAANQADCggIEgABNQAECgcIGAAUALwVAA==.Galnddrael:BAAANQADCgIIAgAAAA==.Gayfrost:BAAANQAECgIIAgABNQAECgcICQACAAAAAA==.',
Ge='Geef:BAAANQAECgQICAAAAA==.Geoði:BAAANQADCgcIEQAAAA==.',
Gh='Ghosterhunte:BAAANQADCgQIBAAAAA==.Ghunne:BAAANQAECgEIAQAAAA==.',
Gi='Gilgamèsh:BAAANQADCgYIBgAAAA==.Gisella:BAAANQAECgIIBAAAAA==.',
Gl='Glenn:BAAANQAECgYIBgABNQAECgkJGQAQACwhAA==.',
Go='Goatley:BAAANQABCgYIDAAAAA==.Gobbledoc:BAAANQAECgEIAQAAAQ==.Goblane:BAAANQAECgMIBAAAAA==.Gokakyu:BAAANQADCgUIAgAAAA==.Goobydh:BAABNQAECoEYAAIVAAkJACNLAACRAwAVAAkJACNLAACRAwAAAA==.Gorothma:BAAANQADCgYIBgAAAA==.',
Gr='Gralin:BAAANQAECgMIBAAAAA==.Grampy:BAAANQADCgYIBgAAAA==.Grandioso:BAAANQAECgUIBwAAAA==.Gregorc:BAAANQADCggIDgAAAA==.Griimmx:BAAANQABCgIIAgAAAA==.Grimzdemon:BAAANQADCgcIEQAAAA==.Groxthyr:BAAANQADCgYIBgAAAA==.Grumblebeard:BAAANQADCgYICwAAAA==.',
Gu='Guff:BAAANQADCggIIAABNQAECgQICAACAAAAAA==.Guilia:BAAANQABCgQIBAAAAA==.Guldann:BAAANQADCgcIDAAAAA==.Gundjax:BAAANQABCgYIBgAAAA==.Gunstein:BAAANQAECgEIAQAAAA==.',
['Gå']='Gål:BAAANQAECgEIAQAAAA==.',
['Gõ']='Gõatçheesed:BAAANQADCgMIAwABNQADCgUIBwACAAAAAA==.',
Ha='Hadlé:BAAANQAECgYICQAAAA==.Hailthelight:BAAANQAECgcIEQAAAA==.Hannelore:BAAANQAECgQIBQAAAA==.Happyissues:BAAANQADCgIIAgAAAA==.Happypallie:BAAANQADCgYIBgAAAA==.Haymawty:BAAANQAECgIIBAAAAA==.',
He='Helea:BAAANQADCgYICQAAAA==.Heliosax:BAAANQAECgIIBAAAAA==.Hellgrazerr:BAAANQAECgIIAgABNQAECgQIBgACAAAAAA==.Helpfllgirl:BAAANQAECgMIAwAAAA==.Hemardest:BAAANQADCgMIAgAAAA==.Henlas:BAAANQADCggIEAAAAA==.Heraklees:BAAANQADCgIIAgAAAA==.Hexdancer:BAAANQABCgQIBAAAAA==.Hezzadem:BAAANQAECgIIAgAAAA==.',
Hi='Hilam:BAAANQABCgYIAgAAAA==.',
Ho='Holycheet:BAAANQADCgcIDQAAAA==.Holyderki:BAAANQAECgcIEQAAAA==.Holyleah:BAAANQAECgIIBAAAAA==.Holypoonz:BAAANQAECgUIBgAAAA==.Hontar:BAAANQADCgcIDQAAAA==.Hornlulz:BAAANQADCgYIDAABNQAECgQIDAACAAAAAA==.Howzaboot:BAAANQAECgQIBAAAAA==.',
Hu='Hunteradam:BAAANQADCgUIDAAAAA==.Hunterchickn:BAABNQAECoEsAAIWAAgJvhy2DQDFAgAWAAgJvhy2DQDFAgAAAA==.Huntericles:BAAANQADCggICQAAAA==.',
Hy='Hyperxd:BAAANQAECgEIAQAAAA==.',
Ia='Iamhisalt:BAAANQAECgMIAwAAAA==.Iamnohealer:BAAANQAECgQIBwAAAA==.Iarebingbong:BAAANQAECgUIBwAAAA==.',
Id='Idontparsee:BAAANQADCgcIDwABNQAECgcIDQACAAAAAA==.',
Ig='Igzi:BAAANQAECgMIAwABNQAECgQIBgACAAAAAA==.Igzyy:BAAANQAECgQIBgAAAA==.',
Ik='Ikahsia:BAAANQAECgMIBQAAAA==.',
Il='Illaiya:BAAANQADCgUICAAAAA==.Illish:BAAANQAECgQIBAABNQADCgUIBQACAAAAAA==.',
In='Int:BAAANQADCggICAABNQAECgQIBgACAAAAAA==.Interlude:BAAANQAECgQICgAAAA==.',
Ir='Irotor:BAAANQABCgYIBgAAAA==.',
Is='Isc:BAAANQADCgYIBgAAAA==.Isleys:BAAANQADCgIIAgAAAA==.Isobel:BAAANQADCgYIBgAAAA==.Issac:BAAANQAECgYIEQAAAA==.Isuckatmage:BAAANQAECgYIEQAAAA==.',
Iv='Ivenate:BAAANQAECgEIAQAAAA==.Ivesham:BAAANQADCgYIBgABNQAECgEIAQACAAAAAA==.',
Iy='Iymrith:BAAANQAECgEIAgAAAA==.',
Ja='Jaarrius:BAAANQAECgUICAAAAA==.Jacho:BAAANQADCggICQABNQAECgcICAACAAAAAA==.Jacian:BAAANQAECgMIBAAAAA==.Jackiee:BAAANQAECgUICgAAAA==.Jailbreaktau:BAAANQAECgQIBAAAAA==.Jailshifter:BAAANQADCggIDAAAAA==.Jakethesully:BAABNQAECoEtAAIXAAgJ7yJ/AgAiAwAXAAgJ7yJ/AgAiAwAAAA==.Jakharo:BAAANQADCgYICgAAAA==.Jakto:BAAANQADCgUIBQABNQAECgUIEAACAAAAAA==.Jallta:BAAANQADCgQIBgAAAA==.Janjan:BAAANQADCgQIBAAAAA==.Javinda:BAAANQAECgEIAQAAAA==.Jaykob:BAAANQADCgYIBgAAAA==.Jayze:BAAANQADCgcIEAAAAA==.Jaênellê:BAABNQAECoEmAAIQAAgJJArwKgDKAQAQAAgJJArwKgDKAQAAAA==.',
Je='Jenkies:BAAANQAECgEIAgAAAA==.',
Ji='Jimbajumba:BAAANQAECgYICQAAAA==.',
Jo='Jodaniki:BAAANQAECgQIBwAAAA==.Joethebrew:BAAANQADCgUIBQAAAA==.Johnygoodboi:BAAANQAECgUIBgAAAA==.Jolínar:BAAANQADCgUIBQAAAA==.',
Ju='Justaddwater:BAAANQADCggIEwABNQADCgUIEwACAAAAAA==.Justinlaw:BAAANQAECgEIAQAAAA==.',
['Já']='Jáyden:BAAANQAECgQIBwAAAA==.',
['Jó']='Jónsí:BAAANQAECgMIBQAAAA==.',
Ka='Kaeel:BAAANQADCgMIAwAAAA==.Kaichrome:BAAANQAECgEIAQAAAA==.Kaidy:BAAANQADCgcIGwAAAA==.Kalathar:BAAANQAECgEIAQAAAA==.Kalixte:BAAANQABCgMIAwABNQADCggIFAACAAAAAA==.Kamegedon:BAAANQAECgEIAQAAAA==.Kameline:BAAANQAECgEIAQAAAA==.Kangalock:BAAANQADCgYIBgAAAA==.Kangarang:BAAANQADCgYIDgAAAA==.Kanoo:BAAANQAECgEIAgAAAA==.Karissa:BAAANQADCgYIBgAAAA==.Karou:BAAANQADCgYIBgAAAA==.Karrmaa:BAAANQADCgcIDwAAAA==.Katalyna:BAAANQAECgEIAQAAAA==.Kathyhilton:BAAANQADCgYICgAAAA==.Kavedon:BAAANQADCgEIAQAAAA==.Kavis:BAAANQADCgYIBgAAAA==.Kaylehuntz:BAAANQADCgQIAwAAAA==.',
Ke='Keanubreaths:BAAANQADCgYICgAAAA==.Keary:BAAANQADCgYIGAAAAA==.Kerza:BAAANQAECgQIBAAAAA==.Kethraev:BAAANQADCgMIAwAAAA==.Kettlechip:BAAANQADCgcICgAAAA==.Keyalien:BAAANQADCgcICgAAAA==.',
Kh='Khioracle:BAAANQAECgEIAQAAAA==.',
Ki='Kicka:BAAANQAECgEIAwAAAA==.Kiele:BAAANQAECgIIAgAAAA==.Kihí:BAAANQADCgYIBgAAAA==.Killhunter:BAAANQADCgMIAwAAAA==.Kinyo:BAAANQADCgYICAAAAA==.Kirdin:BAAANQAECgcICgAAAA==.Kitcatt:BAAANQADCggIEAAAAA==.Kiwiaz:BAAANQAECgEIAQAAAA==.',
Kl='Klawbringer:BAAANQADCgcIEAAAAA==.Klystara:BAAANQAECgMIAQAAAA==.',
Ko='Kortlex:BAAANQADCggICAABNQAECgkJGAARAP4gAA==.Kortlexx:BAAANQAECgQIBAABNQAECgkJGAARAP4gAA==.',
Kr='Kriela:BAAANQAECgcIDwAAAA==.Krispen:BAAANQAECgUIBwAAAA==.Kryptiposd:BAABNQAECoEZAAIYAAkJAR/eBgA9AwAYAAkJAR/eBgA9AwAAAA==.',
Ku='Kumitsu:BAAANQAECgQIDAAAAA==.Kuralei:BAAANQAECgEIAQAAAA==.Kushlack:BAAANQAECgEIAQAAAA==.',
Ky='Kyrnea:BAAANQADCgYIBgAAAA==.Kyrzen:BAAANQADCgcIBwAAAA==.Kytheon:BAAANQAECgcIDAAAAA==.',
['Ká']='Káèl:BAAANQADCggICAABNQAECgUIEAACAAAAAA==.',
['Kã']='Kãylee:BAAANQAECgIIAgAAAA==.Kãêl:BAAANQADCggIFgABNQAECgUIEAACAAAAAA==.',
['Kä']='Käèl:BAAANQAECgUIEAAAAA==.',
['Kí']='Kíhí:BAAANQAECgYICQAAAA==.Kíntor:BAAANQAECgUIBgAAAA==.',
La='Ladeliana:BAAANQAECgYIDAAAAA==.Ladorill:BAABNQAECoEjAAIZAAkJQhl5CQDhAgAZAAkJQhl5CQDhAgAAAA==.Laliaquest:BAAANQADCgQIBQAAAA==.Lallorona:BAAANQADCgcICwAAAA==.Lanyue:BAAANQADCgQIBAAAAA==.Larcenciel:BAAANQAECgYIEwAAAA==.Lathus:BAAANQADCggICAAAAA==.Laudde:BAEANQAECgQIDAAAAA==.',
Le='Leicapanda:BAAANQADCgMIAwAAAA==.Leighen:BAAANQAECgIIAgAAAA==.Lembah:BAAANQADCgcIEQAAAA==.Lemony:BAAANQADCggICwAAAA==.Lempal:BAAANQADCgEIAQAAAA==.Leonìdas:BAAANQAECgYIBgAAAA==.Lexiness:BAAANQAECgEIAQAAAA==.Leylithia:BAAANQADCgYIBgAAAA==.',
Li='Lilavo:BAAANQAECgEIAQABNQAECgcIDAACAAAAAA==.Lili:BAAANQAECgEIAQAAAA==.Liliane:BAAANQABCgYICwAAAA==.Lilix:BAAANQADCgUIBQAAAA==.Lilliana:BAAANQAECgMIAwABNQAECgcIDAACAAAAAA==.Lilnib:BAAANQAECgQIBgAAAA==.Limm:BAAANQAECgUIBQAAAA==.Limmortalk:BAAANQAECgYIDwAAAA==.Lionwombat:BAAANQADCgEIAQAAAA==.Litewave:BAAANQAECgMIBAAAAA==.Littlebomm:BAAANQAECgcICAAAAA==.Littlemel:BAAANQAECgEIAQAAAA==.Lizardoor:BAAANQABCgIIAgAAAA==.',
Lo='Lockstok:BAAANQABCgIIAgAAAA==.Lockwars:BAAANQAECgEIAQAAAA==.Lockydoor:BAAANQABCgYICgAAAA==.Lokai:BAAANQAECgcIDgAAAA==.Longicorn:BAAANQAECgYIDwAAAA==.Lookthatway:BAAANQADCggIFgAAAA==.Loott:BAAANQAECgQIBAAAAA==.',
Lr='Lrelia:BAABNQAECoEYAAMaAAkJ4QwSEgApAgAaAAkJvAoSEgApAgAWAAcJgQjwSQBZAQAAAA==.',
Lu='Lukaryn:BAAANQAECgMIAwAAAA==.Lukusmaximus:BAACNQAFFIEGAAIWAAUJdB4gAADxAQAWAAUJdB4gAADxAQA1AAQKgRkAAxYACQmDJdcAAMsDABYACQmDJdcAAMsDABoAAQkiBiU5AEEAAAAA.Lummos:BAAANQAECgEIAQAAAA==.Lumpypuddle:BAAANQADCgcIBwAAAA==.Lunaxwar:BAAANQAECgMIBAAAAA==.Lunch:BAAANQAECgYIBwAAAA==.Lungerie:BAAANQAECgQIBgAAAA==.Lurts:BAAANQADCgcICgAAAA==.Lusserina:BAAANQADCgYIBgAAAA==.Lustaen:BAAANQADCgUICgAAAA==.Lustiun:BAAANQAECgQIDQAAAA==.Luviana:BAAANQADCggIFAAAAA==.Luvstaspooje:BAAANQAECgQIDAAAAA==.',
Ly='Lyll:BAAANQAFFAMIBAAAAA==.Lynborough:BAAANQAECgIIAgAAAA==.Lyndaks:BAAANQADCgUICQAAAA==.',
Ma='Maalus:BAAANQADCgcIGwAAAA==.Machlin:BAAANQADCgcIEQAAAA==.Madalgerca:BAAANQADCgYIDQAAAA==.Maddi:BAAANQAECgMICAAAAA==.Madlorekeep:BAABNQAECoEZAAMbAAkJ7iDoAAACAwAbAAgJriHoAAACAwAIAAEJ6xoDYABWAAAAAA==.Madmaorid:BAACNQAFFIEGAAIcAAUJOwx5AgBFAQAcAAUJOwx5AgBFAQA1AAQKgRgAAhwACQl0EXQTAEoCABwACQl0EXQTAEoCAAAA.Madmaorip:BAAANQAECgEIAQAAAA==.Madoren:BAABNQAECoEsAAIdAAgJZxQHCQAFAgAdAAgJZxQHCQAFAgAAAA==.Magibloopa:BAAANQAECgcIEAAAAA==.Mahy:BAAANQAECgEIAQAAAA==.Majel:BAAANQADCggIFAAAAQ==.Makikun:BAAANQAECgYICwAAAA==.Malerris:BAAANQAECgQIDAAAAA==.Maliae:BAAANQADCgcIDQAAAA==.Malithyus:BAAANQAECgEIAQAAAA==.Mammonite:BAAANQADCggIFgAAAA==.Manastealeaf:BAAANQAECgQIDgAAAA==.Manginahead:BAAANQADCgcICwAAAA==.Marapcus:BAAANQABCgQIBAAAAA==.Martielle:BAAANQABCgQIBAAAAA==.Matchatotems:BAAANQADCgYIBgAAAA==.Matheral:BAAANQADCgYIBwAAAA==.Matoaka:BAAANQADCgMIAwAAAA==.Matpriest:BAAANQAECgEIAgAAAA==.Matspriest:BAAANQAECgEIAQAAAA==.Mavmeow:BAAANQADCgYICAAAAA==.Mavèrick:BAAANQADCgcIBwAAAA==.Maximilian:BAAANQABCgQIBgAAAA==.',
Mc='Mchammasmash:BAAANQADCgMIBQAAAA==.Mclusky:BAAANQAECgQIDAAAAA==.',
Me='Medi:BAAANQAECgIIAgAAAA==.Meeran:BAAANQADCgEIAQABNQAECgUIBwACAAAAAA==.Megaclite:BAAANQAECgEIAQAAAA==.Meirdris:BAAANQAECgMIAwAAAA==.Melinaya:BAAANQADCgcICQAAAA==.Melissà:BAAANQAECgYICgAAAA==.Melora:BAAANQADCggICAAAAA==.Meltonjohn:BAAANQADCgMIAwAAAA==.Meritorious:BAAANQAECgMIBgAAAA==.Metalwar:BAAANQAECgcIEAAAAA==.',
Mi='Midnightdove:BAAANQADCgcIEQAAAA==.Mikeo:BAAANQAECgIIAgAAAA==.Milesysmash:BAAANQAECgEIAQAAAA==.Minifrost:BAAANQADCggIFAAAAA==.Miotas:BAAANQADCggIDAAAAA==.Miracydia:BAAANQADCggICAABNQAECgMIAwACAAAAAA==.Miralai:BAAANQAECgcIDgAAAA==.Mishkaa:BAAANQAECgMICAAAAA==.Mistfist:BAAANQADCgcIBgAAAA==.Mistq:BAAANQADCgYIGAAAAA==.Mittyree:BAAANQADCgcIGgAAAA==.Mixer:BAAANQAECgcIDQAAAA==.Mizuiro:BAAANQAECgMIAwAAAA==.',
Mo='Moirain:BAABNQAECoEsAAIJAAgJThxEDwCgAgAJAAgJThxEDwCgAgAAAA==.Monkeymagìc:BAAANQADCgcIDQAAAA==.Monotron:BAAANQAECgQIDAAAAA==.Moodrown:BAAANQAECgQIBwAAAA==.Moogh:BAAANQAECgQIBAAAAA==.Moonieezz:BAAANQAECgUICQAAAA==.Moonniiee:BAAANQADCggICgAAAA==.Morgäna:BAAANQAECgUIDQAAAA==.Morte:BAAANQADCgcICAAAAA==.Mouseybrew:BAAANQAECgEIAQAAAA==.',
Mt='Mtisaelf:BAAANQADCggIEwAAAA==.',
My='Myrlidoran:BAAANQADCgcIDAABNQAECgUIEAACAAAAAA==.Mythdiirus:BAAANQADCgcIDAAAAA==.Mythtress:BAAANQAECgEIAQAAAA==.',
['Må']='Måtcoss:BAAANQADCgQIBAABNQAECgEIAgACAAAAAA==.',
['Më']='Mërlin:BAAANQAECgQIBAAAAA==.',
Na='Nafari:BAAANQADCgMIAwAAAA==.Nanageddon:BAAANQAECgQIDAAAAA==.Narinutogar:BAAANQADCgQIBAAAAA==.Narsilion:BAAANQADCgcIDwAAAA==.Nasril:BAAANQAECgEIAQAAAA==.Nastazia:BAAANQAECgIIAgAAAA==.Nasthvel:BAAANQADCgcIFwAAAA==.Nathemate:BAAANQAECgIIAwAAAA==.Naykaido:BAAANQAECgIIBAAAAA==.Nazarene:BAAANQADCgUIBAAAAA==.Nazzgul:BAAANQADCgYIDAAAAA==.',
Ne='Nedorshock:BAAANQAECgMIBAAAAA==.Neinah:BAAANQAECgEIAQAAAA==.Neirdra:BAAANQAECgEIAQAAAA==.Nemises:BAAANQADCgUICQABNQAECgIIBAACAAAAAA==.Neralith:BAAANQADCggIEwAAAA==.Nerv:BAAANQADCggIEwAAAA==.Netimerin:BAAANQAECgUIEAAAAA==.Nezrai:BAAANQAECgIIBgAAAA==.',
Ni='Nicet:BAAANQAECgQIBwAAAA==.Ninannunaki:BAAANQADCgUIBQABNQADCgcIEAACAAAAAA==.',
No='Noncultured:BAAANQADCgYIBgABNQAECgQIEgACAAAAAA==.Normerules:BAAANQAECgEIAgAAAA==.Norsi:BAAANQAECgMIAwAAAA==.Norstraz:BAAANQAECgEIAQAAAA==.Nostrobow:BAAANQADCgMIAwABNQADCgUICQACAAAAAA==.Nostromo:BAAANQADCgUICQAAAA==.Nouvy:BAAANQAECgEIAgAAAA==.Novicima:BAAANQADCgcIEQAAAA==.',
Nu='Nuz:BAAANQAECgQIDAAAAA==.',
Ny='Nymphea:BAAANQAECgQIBAAAAA==.Nyssandria:BAAANQAECgQIBAAAAA==.Nyter:BAAANQAECgIIAgAAAA==.Nyxalotol:BAAANQADCggICAAAAA==.',
Nz='Nzswarrior:BAAANQAECgEIAQAAAA==.',
['Nê']='Nêmmza:BAAANQADCgYICQAAAA==.',
['Në']='Nëll:BAAANQADCgUIBQAAAA==.',
Oc='Occultus:BAAANQAECgEIAQAAAA==.',
Od='Oddpaladin:BAAANQADCgYIBgABNQAECgQIBgACAAAAAA==.Oddshot:BAAANQAECgQIBgAAAA==.',
Oh='Ohnyxia:BAAANQAECgMIAwAAAA==.',
Oj='Ojlahk:BAAANQAECgIIBAAAAA==.',
Ol='Ollydog:BAAANQADCgUIBQABNQAECgQIBAACAAAAAA==.Ollywarr:BAAANQAECgQIBAAAAA==.',
Om='Omnibrew:BAACNQAFFIEFAAINAAUJ0Bo7AADFAQANAAUJ0Bo7AADFAQA1AAQKgRkAAg0ACQkjJikAAO4DAA0ACQkjJikAAO4DAAAA.Omnipudge:BAAANQADCggIEAABNQAFFAUIBQANANAaAA==.',
Op='Optionless:BAAANQADCgUIBQAAAA==.',
Or='Orb:BAAANQAECgYICwAAAA==.Orceissua:BAAANQAECgQIBAAAAA==.Orchtaed:BAAANQADCgcIBwABNQAECgQIBAACAAAAAA==.',
Ou='Outplagued:BAAANQAECggICgAAAA==.',
Ow='Owlee:BAAANQAECgEIAQAAAA==.',
Ox='Oxoid:BAAANQAECggIEAAAAA==.',
Pa='Padner:BAAANQAECgUIBgAAAA==.Pain:BAAANQADCgcIDQAAAA==.Palabee:BAAANQAECgIIBAABNQAECgcICAACAAAAAA==.Palalamb:BAAANQAECgIIBAAAAA==.Palastrifus:BAAANQADCgQIBwAAAA==.Pandafelow:BAAANQAECgUICAAAAA==.Panpann:BAAANQADCgcIGwAAAA==.Parapet:BAAANQAECgMIBQAAAA==.Parmageddon:BAAANQADCggIFQAAAA==.Pawsey:BAAANQAECgEIAQAAAA==.',
Pe='Peanutbuter:BAAANQAECgIIBAAAAA==.Penbryn:BAAANQADCgQIBAABNQAECgcIDQACAAAAAA==.Peppermint:BAAANQAECgIIAgAAAA==.Permafrost:BAAANQADCgYIBwAAAA==.Pewershaman:BAAANQADCgcIDAAAAA==.',
Ph='Phaeora:BAAANQADCgEIAQAAAA==.Phantomfear:BAAANQADCgUIBgAAAA==.Phatzz:BAAANQAECgQIBAAAAA==.Philmccrackn:BAAANQADCgYIEgAAAA==.Phyllixia:BAAANQADCgcIEgAAAA==.',
Pi='Pididdy:BAAANQAECgIIAgAAAA==.Piffles:BAAANQAECgEIAQAAAA==.',
Pl='Plaguedaddy:BAAANQADCggICAABNQADCgIIAgACAAAAAA==.',
Po='Polymorphinê:BAAANQAECgYIDgABNQABCgIIAgACAAAAAA==.Pondmordial:BAAANQAECgUIBgAAAA==.Popeisnomore:BAAANQADCggIIQAAAA==.',
Pr='Precursor:BAAANQADCggIGQAAAA==.Priestycro:BAAANQADCggIDQABNQAECgQIBAACAAAAAA==.Primemoover:BAAANQADCggIFAAAAA==.Prodigyloy:BAAANQAECgIIAgAAAA==.Prodigyloysh:BAAANQAECgQICAABNQAECgIIAgACAAAAAA==.Prodigyloyw:BAAANQAECgIIAgABNQAECgIIAgACAAAAAA==.Prodigyloyz:BAAANQAECgQIBgABNQAECgIIAgACAAAAAA==.Prodigylõy:BAAANQAECgYIDQABNQAECgIIAgACAAAAAA==.Prune:BAAANQADCgMIAwABNQAECgIIAgACAAAAAA==.',
Ps='Psychedeliah:BAAANQADCgcIDAAAAA==.',
Pu='Puddey:BAAANQAECgQIDAAAAA==.Pumpershot:BAACNQAFFIEJAAMWAAYJcBveAAAsAQAWAAMJAR7eAAAsAQAaAAMJ3xjlAwASAQA1AAQKgRoAAxoACQn0ITMJANUCABoACAl6HzMJANUCABYABwlaI/sWAG8CAAAA.Punnisher:BAAANQAECgEIAgAAAA==.Pureshock:BAAANQADCgUIBQAAAA==.Purpleshoes:BAAANQAECgUIBgAAAA==.',
Py='Pyjamish:BAAANQAECgEIAQAAAA==.Pyroglyphix:BAAANQADCgIIAgAAAA==.Pyrolusite:BAAANQADCgQIDgAAAA==.',
['Pá']='Pát:BAACNQAFFIEGAAMeAAUJ0yBSAQDzAQAeAAUJHh9SAQDzAQAfAAEJbx/NAABbAAA1AAQKgRkAAh4ACQkZJhIBAOcDAB4ACQkZJhIBAOcDAAAA.',
['Pú']='Púddums:BAAANQAECgYICQAAAA==.',
Qa='Qasida:BAAANQADCgYICwAAAA==.',
Qu='Quaril:BAAANQADCgEIAQAAAA==.Quiksilverx:BAAANQAECgcIEQAAAA==.Qutie:BAAANQADCgYIBgABNQAECgQIBgACAAAAAA==.',
Ra='Radathmor:BAAANQADCggIFAAAAA==.Raefafa:BAAANQAECgYICQAAAA==.Raelynddra:BAAANQADCgYIBgAAAA==.Raethena:BAAANQAECgEIAQAAAA==.Ragermini:BAAANQAECgUIBwAAAA==.Ragonmibrals:BAAANQADCggIGAAAAA==.Raharlem:BAAANQADCgUIDwABNQAECgYICwACAAAAAA==.Ravenkiller:BAAANQAECgUIDQAAAA==.Ravion:BAAANQADCgYIBgAAAA==.Ravosh:BAAANQADCggIDAAAAA==.Raze:BAEANQAECgQIBQABNQAECgkJGAAWADYhAA==.Razex:BAEBNQAECoEYAAMWAAkJNiFGBABTAwAWAAkJNiFGBABTAwAaAAEJHxKdNgBJAAAAAA==.Razzmage:BAAANQAECgEIAQAAAA==.Razzpally:BAAANQADCgYIBgAAAA==.',
Re='Realhardcore:BAAANQAECgMIBAAAAA==.Redsolodk:BAAANQAECgQIBAAAAA==.Reflexes:BAAANQAECgMIBAAAAA==.Reidon:BAAANQAECgMIBAAAAA==.Reing:BAAANQAECgMIAgAAAA==.Renki:BAAANQADCggIEQAAAA==.Reversehyuki:BAAANQAECgMIAwAAAA==.Reyedrà:BAAANQAECgEIAQAAAA==.Rez:BAAANQAECgEIAgAAAA==.Reza:BAAANQAECgQIBQAAAA==.Rezashiver:BAAANQADCgcIDgABNQAECgQIBQACAAAAAA==.',
Rh='Rhonid:BAAANQABCgQIBAAAAA==.Rhysana:BAAANQADCgYIBgAAAA==.',
Ri='Riddian:BAAANQAECgEIAQAAAA==.Riot:BAAANQABCgIIAgAAAA==.Ripcord:BAAANQAECgQIBAAAAA==.Rishima:BAAANQAECgUICAAAAA==.',
Ro='Rocinante:BAAANQAFFAEIAQAAAA==.Rogerramjet:BAAANQAECgQIBAAAAA==.Roguenjosh:BAAANQADCggIEQAAAA==.Rol:BAAANQAECgcIEwAAAA==.Rongozhunter:BAAANQAECgcIDQABNQADCggIDgACAAAAAA==.Rongozz:BAAANQADCgYIBgABNQADCggIDgACAAAAAA==.',
Ru='Ruaird:BAAANQAECgEIAQAAAA==.Rubladorhar:BAAANQADCgcIDwAAAA==.Rudejin:BAAANQADCgUICQABNQADCgYICwACAAAAAQ==.Ruleturner:BAAANQAECgEIAQAAAA==.Rutiger:BAAANQAECgMIBAAAAA==.Ruwyn:BAAANQADCgYIBgAAAA==.',
Ry='Ryugin:BAAANQAECgIIAgAAAA==.',
Sa='Sabrecried:BAAANQAECgEIAQABNQAECgUIBwACAAAAAA==.Saddragon:BAAANQAECgQIBAAAAA==.Saltybird:BAAANQAECgUIBAAAAA==.Saltyjesuzz:BAABNQAECoEYAAMDAAkJhBhMEAANAgADAAcJgRdMEAANAgAIAAkJ9w74HQD8AQAAAA==.Samm:BAAANQADCggICAAAAA==.Sartharion:BAAANQAECgQIBgABNQAFFAMIBgAOAJINAA==.Satanservant:BAAANQAECgEIAgAAAA==.Saturne:BAAANQABCgMIAwAAAA==.Sax:BAAANQAECgEIAQAAAA==.',
Sc='Scaryheäls:BAEANQADCgcIGwAAAA==.Schmacko:BAAANQAECgUIBgAAAA==.Schneakattac:BAAANQADCgMIAwAAAA==.Schooners:BAABNQAECoEkAAIYAAgJYhy3DwCmAgAYAAgJYhy3DwCmAgAAAA==.Scitolock:BAAANQADCgQIBAAAAA==.Scorpina:BAAANQADCgYIBgABNQAECgUIEAACAAAAAA==.Scroopy:BAAANQAECgQIBgAAAA==.',
Se='Seerarcane:BAAANQABCgMIAwAAAA==.Semavoidp:BAAANQADCgEIAQAAAA==.Senilia:BAAANQADCgQIBAAAAA==.Serenta:BAAANQAECgEIAQAAAA==.Sermixalot:BAAANQAECgEIAQABNQAECgMIBAACAAAAAA==.Serphina:BAAANQAECgEIAQAAAA==.Serrilia:BAAANQAECggIEAAAAA==.Servinthius:BAAANQAECgMIBgAAAA==.Servmonkage:BAAANQAECgEIAgABNQAECgMIBgACAAAAAA==.Sezra:BAAANQAECgQIBgAAAA==.',
Sh='Shabentos:BAAANQAECgEIAQAAAA==.Shadowbrew:BAAANQAECgIIAgAAAA==.Shadyman:BAAANQAECgMIAwAAAA==.Shamfurion:BAAANQAECgEIAQAAAA==.Shamizer:BAAANQAECgEIAgAAAA==.Shammallama:BAAANQADCgQICAABNQAECgYIBgACAAAAAA==.Shammeryy:BAAANQADCggIDgAAAA==.Shammybites:BAAANQAECgIIAgAAAA==.Shamouse:BAAANQAECgcIDwAAAA==.Sharmac:BAAANQADCggIFgAAAA==.Sharpslice:BAAANQAECgEIAQAAAA==.Shazåm:BAAANQADCgQIBAAAAA==.Sheit:BAAANQADCgcIBwAAAA==.Shenseea:BAAANQAECgQIDAAAAA==.Sherie:BAAANQAECgUIEAAAAA==.Sherå:BAAANQADCgcICAAAAA==.Shiftingalex:BAAANQAECgQIBQABNQAECgkJGQASAOIdAA==.Shiiro:BAAANQAECgEIAQAAAA==.Shiok:BAAANQADCgYIBwAAAA==.Shirimassen:BAAANQAECgEIAQABNQAECgMIAQACAAAAAA==.Shix:BAAANQADCgUIBQAAAA==.Shoniroo:BAAANQAECgQIBAAAAA==.Shoyomagic:BAAANQADCgMIAwAAAA==.Shyntaro:BAAANQADCgIIAgAAAA==.Shádowhound:BAAANQABCgQIBgAAAA==.Shádowshaman:BAAANQADCgMIAwAAAA==.',
Si='Sideslash:BAAANQAECgIIAgAAAA==.Signaturez:BAAANQADCgQIBAAAAA==.Silendia:BAAANQAECgEIAgAAAA==.Silkfeather:BAAANQAECgIIAgAAAA==.Siltheren:BAAANQAECgEIAQAAAA==.Silverpink:BAAANQAECgIIAwAAAA==.Sim:BAAANQAECgEIAQABNQAECgUIBgACAAAAAA==.Sin:BAAANQAECgQIBgAAAA==.Sinora:BAAANQAECgQIBwAAAA==.Sitra:BAAANQADCggIDAABNQAECgcIDgACAAAAAA==.',
Sk='Skate:BAAANQADCgYICgAAAA==.Skatty:BAAANQADCgMIAwABNQAECggICgACAAAAAA==.Skattyboohoo:BAAANQADCgYIBgABNQAECggICgACAAAAAA==.Skiadrum:BAAANQADCggICAABNQAECgcIEQACAAAAAA==.Skippyx:BAABNQAECoEcAAMHAAkJLSKpBwClAgAHAAcJYiOpBwClAgAGAAMJ+x12GQASAQAAAA==.Skook:BAAANQADCgIIAgABNQAECgQIDgACAAAAAA==.Skyebow:BAAANQADCgYICAAAAA==.Skyenz:BAAANQABCgMIAQAAAA==.Skyetrix:BAAANQADCggICAAAAA==.Skyevader:BAAANQAECgEIAQAAAA==.Skyller:BAAANQADCgIIAgAAAA==.Skyraa:BAAANQADCgcIEAAAAA==.',
Sl='Sliceyboi:BAAANQADCgcICAAAAA==.Slimkidney:BAAANQAECgQIBAAAAA==.Slopes:BAAANQADCgYIBgAAAA==.Slyclaran:BAAANQADCgYICgAAAA==.',
Sm='Smôôthy:BAAANQADCgcIEAAAAA==.',
Sn='Snollas:BAAANQAECgcIDwAAAA==.Snootyjam:BAAANQADCggIDgAAAA==.Snoozetotems:BAAANQADCgMIAwAAAA==.Snorkes:BAAANQADCgUIAQAAAA==.Snotbubble:BAAANQADCgYIBgAAAA==.Snowmae:BAAANQAECgEIAQAAAA==.',
So='Solestra:BAAANQAECgQIDAAAAA==.Somethingnew:BAAANQAECgEIAQAAAA==.Sonead:BAAANQAECgEIAQAAAA==.Sorcxisto:BAAANQADCggIDQAAAQ==.Sostrate:BAAANQADCgcIBwAAAA==.',
Sp='Spankmybeast:BAAANQADCggIEQAAAA==.Sparkerlee:BAAANQAECgMIBAAAAA==.Spellsteel:BAAANQADCgYIDAAAAA==.Splurtle:BAAANQADCgcICAAAAA==.Sprayandpray:BAAANQAECggIDgABNQAFFAcIDgAMAEscAA==.Spraynwipe:BAABNQAFFIEOAAMMAAcJSxyAAQD7AQAMAAUJ9xyAAQD7AQAgAAIJnRopAADQAAAAAA==.Spuudrou:BAAANQADCgcIBwAAAA==.',
Sq='Squibler:BAAANQAECgQIBAAAAA==.',
St='Stackbundles:BAAANQABCgIIAgAAAA==.Stalidin:BAAANQAECgIIAgAAAA==.Steilgar:BAAANQAECgEIAQAAAA==.Stellaar:BAAANQADCgIIAgAAAA==.Steveybaby:BAAANQAECgIIAgAAAA==.Sticksy:BAAANQAECgQIDAAAAA==.Stormchoice:BAAANQAECgMIBgAAAA==.Strangest:BAAANQADCggIFgAAAA==.Stàrlord:BAAANQADCgcIDgAAAA==.',
Su='Sudno:BAABNQAECoEYAAMPAAkJTSPZDACpAgAPAAcJySLZDACpAgAKAAUJgxjtHAA9AQAAAA==.Sugarmelons:BAAANQADCgMIAgAAAA==.Suntanis:BAAANQADCggIFQAAAA==.Sunwuxing:BAAANQAECgIIAgAAAQ==.Superstorm:BAAANQADCgcIBwABNQAECgQIBAACAAAAAA==.Supertedd:BAAANQAECgIIAgAAAA==.Supratojz:BAAANQADCggIBgAAAA==.Surger:BAAANQADCgQIBQAAAA==.',
Sv='Svenigmatic:BAAANQADCgcIFAAAAA==.Svårl:BAAANQAECgYICgAAAA==.',
Sw='Swagmasterr:BAAANQADCggIEAAAAA==.Sweetieman:BAAANQAECgEIAQAAAA==.Swen:BAAANQADCgcICwAAAA==.',
Sy='Sydneysweeny:BAAANQAECgQIBwAAAA==.Sylliné:BAAANQAECgYICQAAAA==.Sylphâ:BAAANQADCgUIBwAAAA==.Sylreilea:BAAANQAECgIIAgAAAA==.Sylrinn:BAAANQABCgQIBAAAAA==.Sylvie:BAAANQAECgIIAgAAAA==.Synpal:BAAANQAECgIIAgAAAA==.Syranz:BAAANQADCgcIDgAAAA==.',
['Sì']='Sìgnature:BAAANQADCgcIBwAAAA==.',
['Sý']='Sýnyster:BAAANQAECgEIAQAAAA==.',
Ta='Tabachoy:BAAANQADCgYIBgAAAA==.Talanos:BAAANQAECgQIBAAAAA==.Talbs:BAAANQAECgUIEQAAAA==.Talbz:BAAANQADCgYIBgAAAA==.Talwen:BAAANQAECgEIAQAAAA==.Tandarin:BAAANQAECgIIAgAAAA==.Tangomago:BAAANQADCgYICgAAAA==.Tantalus:BAAANQAECgQIBQAAAA==.Tareeya:BAAANQADCgcIGwAAAA==.Tasmanica:BAAANQAECgEIAQAAAA==.Tasse:BAAANQADCggIFAAAAA==.Tassiban:BAAANQAECgEIAQAAAA==.Taurmien:BAAANQAECgUIDQAAAA==.Tazviro:BAAANQAECggIDwAAAA==.',
Tc='Tcuntius:BAAANQADCgIIAgABNQAECgUIEAACAAAAAA==.',
Te='Tealwing:BAAANQADCgUICQAAAA==.Teigra:BAAANQADCggICAABNQAECgQICAACAAAAAA==.Tekadin:BAAANQAECgEIAgAAAA==.Tekká:BAAANQAECgEIAQAAAA==.Teledron:BAABNQAECoEYAAIeAAkJQBrKFwDHAgAeAAkJQBrKFwDHAgAAAA==.Telladk:BAAANQAECgQIBgAAAA==.Telordroth:BAAANQADCgUIBQAAAA==.Tephilaisli:BAAANQADCgcIEAAAAA==.Terminated:BAAANQADCggIDwAAAA==.Terraform:BAAANQAECgQIBgAAAA==.Terrorscale:BAAANQADCgYIBgAAAA==.Terzani:BAAANQADCggICAAAAA==.',
Th='Thebubble:BAAANQAECggIEwAAAA==.Theelfchick:BAAANQAECgQIBQAAAA==.Therassra:BAAANQAECgIIAgAAAA==.Thethem:BAAANQADCgcICAABNQAECgQIEgACAAAAAA==.Thiccshot:BAAANQAECgYIDAAAAA==.Thirdleg:BAAANQADCggICAAAAA==.Thorgoodsdk:BAAANQADCgcICgAAAA==.Thoughtless:BAAANQADCggIEgAAAA==.Throlde:BAAANQAECgMIBAAAAA==.Thunderam:BAAANQAECgQIBAAAAA==.Thundrstryke:BAAANQAECgEIAQAAAA==.',
Ti='Ticklemaster:BAAANQADCgYIDAAAAA==.Tikitoki:BAAANQAECgMIAwAAAA==.Timmeh:BAAANQAECgEIAgAAAA==.Tingo:BAAANQAECgIIAgAAAA==.Tinkerspell:BAAANQADCggIDwAAAA==.Tinsham:BAAANQAECgMICAAAAA==.Tipps:BAAANQADCgUIBwAAAA==.Tipsydipsy:BAAANQAECgQIBgAAAA==.Tipsygypsy:BAAANQADCggIDAAAAA==.Tirayvia:BAAANQADCgYIDAABNQAECgUICgACAAAAAA==.',
Tl='Tlusticus:BAAANQAECgUIEAAAAA==.',
Tn='Tnucyllap:BAAANQAECgQIBAAAAA==.',
To='Tobymanajinx:BAAANQADCgYIDQAAAA==.Tomar:BAEANQAECgEIAQAAAA==.Torturous:BAAANQABCgQIBAAAAA==.Totemrunna:BAAANQADCgMIAwAAAA==.',
Tr='Tragos:BAAANQADCggIEQAAAA==.Treyel:BAAANQADCgcIGQAAAA==.Tricksybelle:BAAANQAECgQIBAAAAA==.Tripitakä:BAAANQADCgcIEAAAAA==.Trollmon:BAAANQAECgEIAQAAAA==.',
Ts='Tsubyiaki:BAAANQAECgEIAQABNQAECgMIAwACAAAAAA==.',
Tu='Tubig:BAAANQAECgUIBwAAAA==.Tuskarus:BAAANQADCgcIEgAAAA==.',
Tv='Tvpper:BAAANQAECgQIBgAAAA==.',
Tw='Twiglet:BAAANQAECgIIAgAAAA==.Twohandedaxe:BAAANQAECgQIBAAAAA==.',
Tx='Txlbs:BAAANQADCgYIBgAAAA==.',
['Tö']='Tölls:BAAANQADCggIEQAAAA==.',
['Tø']='Tølls:BAAANQAECgEIAQAAAA==.',
Ul='Uleo:BAAANQAECgEIAQAAAA==.Ultaburg:BAAANQADCggICAAAAA==.',
Un='Uncultured:BAAANQAECgQIEgAAAA==.Unculturedg:BAAANQADCgYIBgABNQAECgQIEgACAAAAAA==.Unculturedzz:BAAANQADCggIDgABNQAECgQIEgACAAAAAA==.Unrelenting:BAAANQAECgEIAQAAAA==.Unstopbubbl:BAAANQAECgIIBAABNQAECgYIBgACAAAAAA==.',
Ur='Urukhia:BAAANQAECgQIBQAAAA==.',
Ut='Uturnip:BAAANQAECgMIAwAAAA==.',
Va='Valeryan:BAAANQADCgIIAgAAAA==.Vamoose:BAAANQAECgQICAAAAA==.Vanatoarea:BAAANQADCgQIBAAAAA==.Vargula:BAAANQADCgYIBwABNQADCgIIAgACAAAAAA==.',
Ve='Veliondel:BAABNQAECoEYAAIRAAkJ/iB2BwBKAwARAAkJ/iB2BwBKAwAAAA==.Velisar:BAAANQAECgQIBAAAAA==.Velliidira:BAAANQABCgIIAgAAAA==.Verymoist:BAAANQAECgEIAQAAAA==.Vesperath:BAAANQADCgUIBQAAAA==.',
Vi='Victim:BAAANQADCggICAAAAA==.Vikzulx:BAAANQAECgEIAQABNQAECgkJGAARAP4gAA==.Vineweaver:BAAANQAECgEIAgAAAA==.',
Vo='Vodkasam:BAAANQAECgUIBQAAAA==.Vodkaspin:BAAANQAECgUICQAAAA==.Voidgirl:BAABNQAECoEYAAIDAAgJ9xPHDQBBAgADAAgJ9xPHDQBBAgABNQABCgIIAgACAAAAAA==.Voidnight:BAAANQAECgEIAQAAAA==.Voljuin:BAAANQADCgYIBgAAAA==.Volrod:BAAANQAECgEIAQAAAA==.Voltros:BAAANQAECgEIAQAAAA==.Vorpaxx:BAAANQADCgQIBwAAAA==.',
Vr='Vrenga:BAAANQAECgEIAwAAAA==.',
Vt='Vthunda:BAAANQAECgIIAgAAAA==.',
Vu='Vurne:BAAANQAECgMIBAABNQAECggIDwACAAAAAA==.Vurve:BAAANQAECgEIAQAAAA==.',
Vy='Vyssali:BAAANQADCgUIBgAAAA==.',
['Vë']='Vël:BAAANQADCggIDgAAAA==.',
Wa='Walpurgis:BAAANQAECgEIAQAAAA==.Warhammerer:BAAANQAECgEIAQAAAA==.Warjez:BAAANQADCgEIAQAAAA==.Wasamedis:BAAANQADCgYIEgAAAA==.Wasstwo:BAAANQAECgEIAgAAAA==.Wavey:BAAANQADCgMIAwAAAA==.Wayfinder:BAAANQAECgYICwABNQAECgkJGQAbAO4gAA==.',
We='Wellofheaven:BAAANQADCgQIBAAAAA==.Wemenn:BAAANQAECgMICAAAAA==.Wentz:BAAANQAECgEIAQAAAA==.',
Wh='Whatmeows:BAAANQAECgIIBAAAAA==.Wheels:BAAANQADCggIDwAAAA==.Whoox:BAAANQADCggIDQAAAA==.',
Wi='Widdlish:BAAANQADCggICAABNQADCggIDgACAAAAAA==.Widpally:BAAANQADCggIDgAAAA==.Wildclaw:BAAANQAECgEIAQAAAA==.Wildhunt:BAAANQADCggICgAAAA==.Willdiealot:BAAANQAECgEIAQAAAA==.Wintèr:BAAANQADCgcIBwABNQABCgIIAgACAAAAAA==.',
Wo='Wonkydonky:BAAANQAECgEIAQAAAA==.Woolnd:BAAANQADCgcICgAAAA==.',
Wr='Wraitthh:BAAANQAECgQIBAAAAA==.',
Wy='Wyspå:BAAANQADCgYICAAAAA==.',
Xa='Xalafoot:BAAANQAECgUIBQAAAA==.Xalatath:BAAANQAECgQIBgAAAA==.Xaneie:BAAANQADCgcICAAAAA==.',
Xo='Xonkz:BAAANQADCgEIAQAAAA==.',
Xt='Xtreme:BAAANQADCggIDAAAAA==.',
Xu='Xuanwu:BAABNQAECoEbAAILAAkJOh2jBwAtAwALAAkJOh2jBwAtAwAAAA==.',
Xy='Xylaera:BAAANQAECgYIDgAAAA==.Xylunara:BAAANQAECgMIAwABNQAECgYIDgACAAAAAA==.',
['Xà']='Xàbìñ:BAAANQADCggICAAAAA==.',
Ya='Yachtclub:BAAANQAECgYICgABNQABCgQIBAACAAAAAA==.Yadito:BAAANQAECgQIBAAAAA==.Yanthra:BAAANQADCgcIFAAAAA==.Yazmi:BAAANQAECgQIBAABNQABCgIIAgACAAAAAA==.',
Yb='Ybjealous:BAAANQADCgcIEQAAAA==.',
Yi='Yimee:BAAANQAECgEIAQAAAA==.',
Yl='Ylessa:BAAANQAECgEIAQAAAA==.',
Yn='Ynotvoidberg:BAAANQADCgcIBwAAAA==.',
Yo='Yoops:BAAANQAECgEIAQAAAA==.Yoopsee:BAAANQAECgQIBAABNQAECgQIBgACAAAAAA==.',
Ys='Yseeri:BAABNQAECoEWAAIJAAkJtiPxAAC6AwAJAAkJtiPxAAC6AwAAAA==.Yseri:BAAANQAECgQIBAABNQAECgkJFgAJALYjAA==.',
Yu='Yurika:BAAANQADCgYIBgAAAA==.',
Yv='Yvvi:BAAANQADCgcIBgAAAA==.',
Za='Zachbuc:BAAANQADCgQICAAAAA==.Zackiya:BAAANQAECgQIBwAAAA==.Zadkielle:BAAANQADCgIIAgAAAA==.Zambiéz:BAAANQAECgUIBQAAAA==.Zandar:BAAANQADCgYIEQAAAA==.Zaphiel:BAAANQADCggICQAAAA==.Zat:BAAANQAECgEIAQABNQAECgkJGAAIAIIkAA==.Zatqt:BAABNQAECoEYAAMIAAkJgiSpAQCLAwAIAAkJuiOpAQCLAwAbAAcJDhwXAwAqAgAAAA==.Zatriel:BAAANQAECgQIBAABNQAECgkJGAAIAIIkAA==.',
Ze='Zebo:BAAANQAECgcIEAAAAA==.Zekes:BAABNQAECoEYAAIeAAkJFSWnAQDWAwAeAAkJFSWnAQDWAwABNQADCggIEQACAAAAAA==.Zendma:BAAANQADCggIFgAAAA==.Zephyrielle:BAAANQADCgUIBQAAAA==.Zeralia:BAAANQAECgUIEAAAAA==.',
Zi='Zialayn:BAAANQAECgUIEgAAAA==.Zingabox:BAAANQADCgQIBAAAAA==.Zinrokh:BAAANQADCggIDgAAAA==.',
Zo='Zorali:BAAANQADCgcIEQABNQAECgcIDwACAAAAAA==.Zoranna:BAAANQAECgcIDwAAAA==.',
Zu='Zugzy:BAACNQAFFIEFAAIIAAQJXSOgAQCsAQAIAAQJXSOgAQCsAQA1AAQKgRkAAwgACQmXJfQAAK4DAAgACQlnJfQAAK4DABsABgmmHHYEANEBAAAA.Zurafa:BAAANQADCgQIBAABNQAECgQIBgACAAAAAA==.Zuxx:BAAANQADCgEIAQAAAA==.',
['Äz']='Äzzä:BAAANQAECgUICQAAAA==.',
['Ål']='Ålary:BAAANQAECgUICwAAAA==.',
['Êê']='Êêvêê:BAAANQADCggIDgAAAA==.',
['Ðe']='Ðevine:BAAANQAECgEIAQABNQAECgcIEQACAAAAAA==.',
['Ón']='Ónzo:BAAANQADCgcIHAAAAA==.',
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
