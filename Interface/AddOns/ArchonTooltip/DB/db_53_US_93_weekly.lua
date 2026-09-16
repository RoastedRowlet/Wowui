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

local lookup = {'Unknown-Unknown','Priest-Holy','Hunter-Marksmanship','Warrior-Arms','Warrior-Fury','Paladin-Holy','Mage-Arcane','Mage-Frost','Evoker-Preservation',}
local provider = {region='US',realm='Farstriders',name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Absolon:BAAANQADCgcIEQABNQAECgIIAgABAAAAAA==.',
Ae='Aellynn:BAAANQAECgMIBAAAAA==.Aerir:BAAANQAECgIIAgABNQAECgYIEgABAAAAAA==.',
Ak='Akinom:BAAANQADCgUIDQAAAA==.',
Al='Alltheheals:BAAANQAECgUICQAAAA==.',
Am='Amarawyn:BAAANQADCggIEgAAAA==.Amoonfalar:BAAANQADCgUIDQAAAA==.Amoradrac:BAAANQADCgYIBgAAAA==.Amoragan:BAAANQAECgEIAQAAAA==.',
An='Andriela:BAAANQADCgYIBgAAAA==.',
Ap='Apexy:BAAANQADCgYICgAAAA==.',
As='Asclepius:BAAANQADCgYICwAAAA==.Asurion:BAAANQADCgIIBAAAAA==.',
At='Atlantis:BAAANQAECgIIAgABNQAECgkJHwACAL8lAA==.',
Au='Augidget:BAAANQAECgEIAQAAAA==.',
Av='Avilen:BAAANQAECgQIBwAAAA==.',
Ba='Balinteen:BAAANQADCgcIDAAAAA==.Bastael:BAAANQADCggIFAAAAA==.',
Bi='Biopainr:BAAANQADCgcIFwAAAA==.Bitxi:BAAANQADCgYICwAAAA==.',
Br='Brandalin:BAAANQADCgcIDQAAAA==.Brax:BAAANQAECgQICAAAAA==.',
Bu='Burda:BAAANQAECgYIDAAAAA==.Buttspanker:BAAANQADCgUIBQAAAA==.',
Ca='Caenae:BAAANQADCgYIEgAAAA==.Cakes:BAAANQADCgMIAwAAAA==.Cattlerage:BAAANQADCgYICAABNQAECgYIBgABAAAAAA==.',
Co='Condar:BAAANQADCgIIBAAAAA==.Corri:BAAANQADCgcIDwAAAA==.',
Cr='Credon:BAAANQADCgcIEAAAAA==.',
Da='Davin:BAAANQADCgEIAQAAAA==.',
Dh='Dhrimr:BAAANQADCggIDAAAAA==.',
Di='Dierlyn:BAAANQADCggIEgAAAA==.Dimir:BAAANQAECgIIAwAAAA==.Dirtytaters:BAAANQADCgYICwAAAA==.Divastating:BAAANQADCggIMgAAAA==.',
Do='Doró:BAAANQADCgYIDAABNQAECgMIBAABAAAAAA==.',
Dr='Dragonberry:BAAANQAECgEIAQAAAA==.',
Dt='Dtothed:BAAANQADCggIEAABNQAECgcIGwADADMbAA==.',
Dw='Dwaleen:BAAANQADCgYICgAAAA==.Dwarfred:BAAANQADCggIEgAAAA==.',
['Dò']='Dòro:BAAANQAECgMIBAAAAA==.',
El='Elasong:BAAANQADCgcIDAAAAA==.Elletal:BAAANQAECgQICAAAAA==.Elloria:BAAANQADCgUIBQAAAA==.Elybria:BAAANQADCgEIAQAAAA==.',
Er='Erkil:BAAANQADCgYIBgAAAA==.',
Fi='Figbe:BAAANQADCggICAABNQAECgkJHgAEAD4gAA==.Fizzlyn:BAAANQAECgYICwAAAA==.',
Fl='Flaren:BAAANQADCggIDAAAAA==.',
Ge='Gereleron:BAAANQADCgQIBAAAAA==.',
Gr='Grewsöm:BAAANQAECgYIBgAAAA==.Grotusque:BAAANQAECgIIAwAAAA==.',
Ha='Haerin:BAAANQADCgQIBAAAAA==.Hardim:BAAANQADCgUIBQAAAA==.Harknesse:BAAANQADCgYICwAAAA==.Haxxis:BAAANQADCggICwAAAA==.',
He='Healingways:BAAANQADCgUIBwAAAA==.Heezee:BAAANQADCggIEwAAAA==.Heftypaw:BAAANQADCggIFQAAAA==.Hextor:BAAANQADCgcIBwABNQADCgcIDQABAAAAAA==.',
Ho='Hog:BAAANQAECgYIBgABNQAECgkJIQAFAHsjAA==.Holyboy:BAAANQADCggICQAAAA==.',
Hr='Hranu:BAAANQADCgYICgABNQAECgYIEAABAAAAAA==.',
Hy='Hydraulicman:BAAANQADCgQIBwAAAA==.',
In='Invinciboi:BAAANQADCggICAABNQAECgkJFgAGAIQKAA==.',
Ja='Jasmirana:BAAANQAECgMIBAAAAA==.',
Je='Jemano:BAAANQADCgIIAgAAAA==.',
Jo='Jolage:BAAANQADCgYICAABNQAECgcIGwADADMbAA==.Jolreal:BAABNQAECoEbAAIDAAcJMxuJFwAVAgADAAcJMxuJFwAVAgAAAA==.Jophiel:BAAANQAECgEIAQAAAA==.',
Ju='Julez:BAAANQADCgcIEAAAAA==.Julezara:BAAANQADCgUIEAAAAA==.Jumbledmess:BAAANQABCgMIAwAAAA==.Junkai:BAAANQAECgEIAQAAAA==.',
Ka='Kandyman:BAAANQADCgcIBwAAAA==.',
Ke='Keco:BAAANQADCgcIEAABNQADCggIMgABAAAAAA==.Kennie:BAAANQAECgQICAAAAA==.',
Kl='Kladibo:BAAANQAECgEIAQAAAA==.Kladivo:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.',
Kr='Kröwten:BAAANQAECgQIBwAAAA==.',
['Kì']='Kìlana:BAAANQAECgIIAwAAAA==.',
La='Lahlania:BAAANQADCgYIBgAAAA==.Lanaki:BAAANQAECgYIEgAAAA==.',
Li='Lionheart:BAAANQAECgQIBAABNQAECgkJFgAGAIQKAA==.',
Lu='Lunareon:BAAANQADCggIEAAAAA==.',
Ma='Maccbeth:BAAANQAECgEIAQAAAA==.Machette:BAAANQADCgQIBAABNQAECgcIGwADADMbAA==.Mailaria:BAAANQAECgEIAQAAAA==.Maithe:BAAANQADCgMIAwAAAA==.Mambo:BAAANQADCgMIAwAAAA==.Maralucia:BAAANQADCgIIAgAAAA==.',
Mc='Mcsplatapus:BAAANQADCggIEQAAAA==.',
Me='Meingsolin:BAAANQADCgcIDQAAAA==.',
Mo='Monkeydluffy:BAAANQADCgEIAQAAAA==.Morfas:BAAANQABCgQIBwAAAA==.',
My='Myuk:BAAANQADCggIHAAAAA==.',
Na='Naminay:BAAANQADCgYIDwABNQAECgIIAgABAAAAAA==.',
Ne='Neroz:BAAANQAECgQICAAAAA==.Nerppie:BAAANQAECgQICAAAAA==.',
Ni='Nina:BAAANQADCgYIBgAAAA==.',
Nk='Nkript:BAAANQADCgYIEAAAAA==.',
Od='Odysemus:BAAANQAECgUICgAAAA==.',
On='Onari:BAAANQAECgEIAQAAAA==.Onlyfannz:BAAANQADCgUIBQAAAA==.',
Pa='Pandamoníum:BAAANQADCggIGQAAAA==.',
Pe='Perce:BAAANQAECgIIAwAAAA==.',
Pf='Pfemme:BAAANQAECgQIBgAAAA==.',
Ph='Phalaris:BAAANQADCgIIAgAAAA==.',
Pi='Pikupchew:BAAANQAECgQIBAABNQAECgkJFgAGAIQKAA==.Pinball:BAAANQADCgEIAQAAAA==.Pixie:BAAANQAECgEIAQAAAA==.',
Po='Popcorns:BAAANQADCgIIAgAAAA==.',
Qu='Qualanthar:BAAANQADCgQIBQAAAA==.Quantismo:BAAANQAECgQIBAAAAA==.',
Re='Reyaieleron:BAAANQADCgcIDAAAAA==.',
Ri='Rivenaer:BAAANQAECgUICgAAAA==.',
Ru='Rus:BAAANQADCggIGgAAAA==.Rustymark:BAAANQAECgcIEQAAAA==.',
Sc='Screechowl:BAAANQADCgUIBQAAAA==.',
Se='Sealalicious:BAAANQAECgQIBQAAAA==.Seenaa:BAAANQADCgcIDwAAAA==.',
Sh='Shammywow:BAAANQADCggIFgAAAA==.Sharkzilla:BAAANQAECgUIBQAAAA==.Shiggs:BAAANQADCgcIBwABNQAECgQICAABAAAAAA==.Shine:BAAANQAECgIIBQAAAA==.Shinso:BAAANQADCgcIBwABNQAECgIIAgABAAAAAA==.Shiro:BAAANQADCgYICwAAAA==.',
Si='Silksmilk:BAAANQADCggIGgAAAA==.Silt:BAAANQABCgQIBAAAAA==.Sixt:BAAANQADCgYIBgAAAA==.',
Sl='Sloppy:BAAANQADCgIIAgAAAA==.',
Sm='Smoo:BAAANQADCgUIDwAAAA==.',
Sn='Snøsham:BAAANQADCggICgAAAA==.',
So='Soggyaugi:BAAANQADCgcIDAAAAA==.',
St='Stopdontstop:BAAANQABCgQIBQAAAA==.',
Su='Sunwälker:BAAANQABCgYICAAAAA==.',
Sy='Synora:BAAANQADCgcICwAAAA==.',
['Sè']='Sèphiroth:BAAANQADCgUIBwAAAA==.',
Ta='Tallchief:BAAANQADCgYIEgAAAA==.Talliah:BAAANQADCggIDAAAAA==.',
To='Tonjuren:BAAANQADCgYIEgABNQADCgcIDQABAAAAAA==.',
Tr='Trickery:BAAANQADCgUIBQAAAA==.Trublood:BAAANQADCgYICQAAAA==.',
Us='Usorloups:BAAANQAECgUICQAAAA==.',
Va='Valithra:BAAANQAECgIIAgAAAA==.Vargrulfr:BAAANQAECgEIAQAAAA==.',
Ve='Velonys:BAAANQAECgYIDgAAAA==.Vendy:BAAANQAECgEIAQAAAA==.',
Vi='Victory:BAAANQAECgEIAQAAAA==.Vindictus:BAAANQADCgMIAwAAAA==.',
Vy='Vyu:BAAANQADCgEIAQAAAA==.',
Wa='Wanayu:BAAANQADCgYIBgAAAA==.Wanweasley:BAAANQAECgEIAQAAAA==.',
We='Weh:BAABNQAECoEXAAMHAAkJZCK0EwBTAwAHAAkJkx+0EwBTAwAIAAUJbR5NCQBwAQAAAA==.',
Wi='Wizagon:BAAANQADCggIGAAAAA==.',
Wo='Woodsy:BAAANQAECgEIAQAAAA==.',
Wu='Wuinn:BAAANQAECggICAABNQAECgkJFgAJAL8TAA==.Wunna:BAAANQAECgQIBAAAAA==.',
Xe='Xeran:BAAANQAECgEIAQAAAA==.',
Ya='Yawnight:BAAANQADCgIIAgAAAA==.',
Zi='Zitpally:BAAANQAECgQIBAABNQAECggIEgABAAAAAA==.',
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
