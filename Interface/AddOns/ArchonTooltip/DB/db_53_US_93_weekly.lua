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

local lookup = {'Hunter-BeastMastery','Priest-Holy','Hunter-Survival','Unknown-Unknown','Hunter-Marksmanship','Warrior-Arms','Warrior-Protection','Druid-Restoration','Paladin-Holy','Warrior-Fury','Shaman-Restoration','Shaman-Elemental','DemonHunter-Havoc','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','Mage-Arcane','Mage-Frost','Evoker-Preservation','DeathKnight-Frost',}
local provider = {region='US',realm='Farstriders',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Aberren:BAAANQADCgQIBAAAAA==.Absolon:BAAANQAECgUIBQAAAA==.',
Ae='Aellynn:BAAANQAECgUIDQAAAA==.Aerir:BAAANQAECgIIAgABNQAECgkJHAABAE4XAA==.',
Ak='Akinom:BAAANQADCgUIDQAAAA==.',
Al='Alltheheals:BAAANQAECgcIEgAAAA==.',
Am='Amarawyn:BAAANQAECgIIAwAAAA==.Amoonfalar:BAAANQADCgYIDgAAAA==.Amoradrac:BAAANQADCgYIBgAAAA==.Amoragan:BAAANQAECgYIDAAAAA==.',
An='Andriela:BAAANQADCgYIBgAAAA==.',
Ap='Apexy:BAAANQAECgMIAwAAAA==.',
Ar='Arashikaze:BAAANQAECgUIBgAAAA==.',
As='Asclepius:BAAANQAECgMIAwAAAA==.Asurion:BAAANQADCgIIBAAAAA==.',
At='Atlantis:BAAANQAECgcIDgABNQAFFAcIEQACAP8hAA==.',
Au='Augidget:BAAANQAECgYIDAAAAA==.',
Av='Avilen:BAAANQAECgQICQAAAA==.',
Ba='Balinteen:BAAANQAECgMIBgAAAA==.Bastael:BAAANQAECgYICwAAAA==.',
Bi='Biopainr:BAAANQADCggJHwAAAA==.Bitxi:BAAANQAECgMIAwAAAA==.',
Bl='Bloodtusk:BAAANQADCgIIAgAAAA==.',
Br='Brandalin:BAAANQADCgcIDQAAAA==.Brax:BAAANQAECgUIDwAAAA==.',
Bu='Burda:BAABNQAECoEYAAIDAAgK+hV0BABPAgADAAgK+hV0BABPAgAAAA==.Buttspanker:BAAANQADCgcIEgAAAA==.',
Ca='Caenae:BAAANQADCgcIGQAAAA==.Cakes:BAAANQADCgMIAwAAAA==.Cattlerage:BAAANQAECgcIBwABNQAECgcICAAEAAAAAA==.',
Ci='Ciannie:BAAANQADCgEIAQAAAA==.',
Co='Condar:BAAANQADCgIIBAAAAA==.Corri:BAAANQAECgEIAQAAAA==.',
Cr='Credon:BAAANQAECgIJAgAAAA==.',
Da='Davin:BAAANQADCgQIAQAAAA==.',
Dh='Dhrimr:BAAANQADCggIDAAAAA==.',
Di='Dieceptionz:BAAANQADCggICAAAAA==.Dierlyn:BAAANQAECgIIAwAAAA==.Dimir:BAAANQAECgUICwAAAA==.Dirtytaters:BAAANQAECgMIAwAAAA==.Divastating:BAAANQAECgEIAQAAAA==.',
Do='Doró:BAAANQADCgYIDQABNQAECgUIDQAEAAAAAA==.',
Dr='Dragonberry:BAAANQAECgIJAwAAAA==.',
Dt='Dtothed:BAAANQAECgQIBAABNQAECgkJJQAFAIccAA==.',
Dw='Dwaleen:BAAANQADCgcJEQAAAA==.Dwarfred:BAAANQAECgIIAwAAAA==.',
Dy='Dyàsis:BAAANQABCggIBgAAAA==.',
['Dò']='Dòro:BAAANQAECgUIDQAAAA==.',
El='Elasong:BAAANQADCggIHAAAAA==.Elletal:BAAANQAECgUIDwAAAA==.Elloria:BAAANQADCgUIBQAAAA==.Elybria:BAAANQADCgEIAQAAAA==.',
Er='Erkil:BAAANQAECgMIAwAAAA==.',
Fa='Fayona:BAAANQADCgIJAgAAAA==.',
Fi='Figbe:BAAANQAECgUJBQABNQAFFAMICAAGAG4hAA==.Fizzlyn:BAAANQAFFAEIAQAAAA==.',
Fl='Flaren:BAAANQADCggIDAAAAA==.',
Fu='Furybutt:BAAANQABCgQIBAABNQAECgYIDAAEAAAAAA==.',
Ga='Galedriel:BAAANQADCgEIAQAAAA==.',
Ge='Gereleron:BAAANQADCgQJBAAAAA==.',
Gr='Grewsöm:BAAANQAECgcICAAAAA==.Grizzlegom:BAAANQADCgYICQABNQAECgkJJQAFAIccAA==.Grotusque:BAAANQAECgUIDQAAAA==.',
Ha='Haerin:BAAANQADCgQIBAAAAA==.Hardim:BAAANQADCgcJBwAAAA==.Harknesse:BAAANQAECgMIAwAAAA==.Haxxis:BAAANQAECgUICQAAAA==.',
He='Healingways:BAAANQADCgUIBwAAAA==.Heezee:BAAANQAECgMIAwAAAA==.Heftypaw:BAAANQADCggIFQAAAA==.Helliglys:BAAANQADCgEIAQAAAA==.Hextor:BAAANQADCgcIBwABNQADCgcIDQAEAAAAAA==.',
Ho='Hog:BAAANQAECggIDwABNQAECgkJNwAHANImAA==.Holyboy:BAAANQAECgIIAwAAAA==.',
Hr='Hranu:BAAANQADCggIEgABNQAECgkJIgAIAKYcAA==.',
Hy='Hydraulicman:BAAANQADCgQIBwAAAA==.',
In='Invinciboi:BAAANQADCggICAABNQAECgkJHAAJAK4LAA==.',
Ja='Jasmirana:BAAANQAECgUICgAAAA==.',
Je='Jemano:BAAANQADCgIIAgAAAA==.',
Ji='Jibbzin:BAAANQADCgYIBgABNQAECgUICgAEAAAAAA==.',
Jo='Jolage:BAAANQAECgMIBAABNQAECgkJJQAFAIccAA==.Jolreal:BAABNQAECoElAAIFAAkKhxw6DwDNAgAFAAkKhxw6DwDNAgAAAA==.Jophiel:BAAANQAECgUIBgAAAA==.',
Ju='Julez:BAAANQAECgIJAgAAAA==.Julezara:BAAANQADCgYIGgAAAA==.Jumbledmess:BAAANQABCgMIAwAAAA==.Junkai:BAAANQAFFAEIAQAAAA==.',
Ka='Kandyman:BAAANQADCgcIBwAAAA==.',
Ke='Keco:BAAANQADCggIHQABNQAECgEIAQAEAAAAAA==.Kennie:BAAANQAECgUIDgAAAA==.',
Kl='Kladibo:BAAANQAECgYIDAAAAA==.Kladivo:BAAANQADCgYIBgABNQAECgYIDAAEAAAAAA==.Klick:BAAANQADCgYIBgABNQAFFAEIAQAEAAAAAA==.',
Kr='Kröwten:BAAANQAECgUIDQAAAA==.',
['Kì']='Kìlana:BAAANQAECgUICgAAAA==.',
La='Lahlania:BAAANQAECgEJAQAAAA==.Lanaki:BAABNQAECoEcAAIBAAkKThcXNgCFAgABAAkKThcXNgCFAgAAAA==.',
Li='Lionheart:BAAANQAECgQIBAABNQAECgkJHAAJAK4LAA==.',
Lo='Logarithmic:BAAANQAECgIIAgABNQAECgUIDQAEAAAAAA==.',
Lu='Lunareon:BAAANQAECgIIAgAAAA==.',
Ma='Maccbeth:BAAANQAECgIIBAAAAA==.Machette:BAAANQAECgQIBgABNQAECgkJJQAFAIccAA==.Mailaria:BAAANQAECgYIDAAAAA==.Maithe:BAAANQADCgMIAwAAAA==.Mambo:BAAANQADCgMIAwAAAA==.Maralucia:BAAANQADCgIIAgAAAA==.Marellaa:BAAANQADCgcIDwAAAA==.Marottie:BAAANQADCgIJAgAAAA==.',
Mc='Mcsplatapus:BAAANQAECgQIBQAAAA==.',
Me='Meingsolin:BAAANQAECgIIAgAAAA==.Methodical:BAAANQAECgUICQAAAA==.',
Mo='Monkeydluffy:BAAANQADCgEIAQAAAA==.Mopa:BAAANQADCggICAAAAA==.Morfas:BAAANQABCgQIBwAAAA==.',
My='Myuk:BAAANQAECgYICgAAAA==.',
Na='Naminay:BAAANQADCgYIDwABNQAECgUICwAEAAAAAA==.',
Ne='Neroz:BAAANQAECgUIDwAAAA==.Nerppie:BAAANQAECgUIDwAAAA==.Netherlight:BAAANQAECgMIAwAAAA==.',
Ni='Nina:BAAANQADCgYIBgAAAA==.',
Nk='Nkript:BAAANQAECgQIBAAAAA==.',
Od='Odysemus:BAABNQAECoEaAAMGAAcK0BRKfgDLAQAGAAcK0BRKfgDLAQAKAAEKDgo1KgAtAAAAAA==.',
On='Onari:BAAANQAECgYIDAAAAA==.Onlyfannz:BAAANQADCgYICwAAAA==.',
Pa='Palara:BAAANQABCgUIBQABNQAECgYIDAAEAAAAAA==.Pandamoníum:BAAANQADCggIKQAAAA==.',
Pe='Perce:BAAANQAECgQICAAAAA==.',
Pf='Pfemme:BAAANQAECgYIEQAAAA==.',
Ph='Phalaris:BAAANQADCgIIAgAAAA==.',
Pi='Pikupchew:BAABNQAECoEUAAMLAAgKyQrgYQCRAQALAAgKyQrgYQCRAQAMAAQKkQOYwgCtAAABNQAECgkJHAAJAK4LAA==.Pinball:BAAANQADCgEIAQAAAA==.Pixie:BAAANQAECgMIBgAAAA==.',
Po='Popcorns:BAAANQADCgIIAgAAAA==.Popcornss:BAAANQAECgIIAgAAAA==.',
Pu='Purian:BAAANQADCgIJAgAAAA==.',
Qu='Qualanthar:BAAANQADCgQIBQAAAA==.Quantismo:BAAANQAECgQIBAAAAA==.',
Re='Reyaieleron:BAAANQADCggIHAAAAA==.',
Ri='Rivenaer:BAABNQAECoEcAAINAAgK/AtdMADHAQANAAgK/AtdMADHAQAAAA==.',
Ru='Rus:BAAANQAECgMIBAAAAA==.Rustymark:BAAANQAECgcIEQAAAA==.',
Sc='Schmezzy:BAAANQAECgYICgAAAA==.Screechowl:BAAANQAECgMIAwAAAA==.',
Se='Sealalicious:BAAANQAECgUIDAAAAA==.Seenaa:BAAANQAECgIIAwAAAA==.',
Sh='Shailenya:BAAANQADCgIJAgAAAA==.Shallot:BAAANQADCgEIAQAAAA==.Shammywow:BAAANQAECgYIBgAAAA==.Sharkzilla:BAAANQAECggIEAAAAA==.Shiggs:BAAANQADCgcIBwABNQAECgUIDwAEAAAAAA==.Shine:BAAANQAECgQIDAAAAA==.Shinso:BAAANQADCggIEQABNQAECgUICwAEAAAAAA==.Shiro:BAAANQADCgYICwAAAA==.',
Si='Silksmilk:BAAANQADCggIGgAAAA==.Silt:BAAANQABCgQIBAAAAA==.Siobhân:BAAANQABCgIIAgAAAA==.Sixt:BAAANQADCgYIBgAAAA==.',
Sl='Sloppy:BAAANQADCgIIAgAAAA==.',
Sm='Smoo:BAAANQADCgYIGgAAAA==.',
Sn='Snøsham:BAAANQAECgMIBQAAAA==.',
So='Soggyaugi:BAAANQADCgcIDAAAAA==.',
St='Stopdontstop:BAAANQABCgQIBQAAAA==.',
Su='Sunwälker:BAAANQABCgYICAAAAA==.',
Sy='Synora:BAAANQADCgcICwAAAA==.',
['Sè']='Sèphiroth:BAAANQADCgUIBwAAAA==.',
Ta='Tallchief:BAAANQADCgcIIQAAAA==.Talliah:BAAANQADCggJDAAAAA==.',
Ti='Tinx:BAAANQADCgMJAwAAAA==.',
To='Tonjuren:BAAANQADCgcIIAABNQAECgIIAgAEAAAAAA==.',
Tr='Trickery:BAAANQAECgEIAQAAAA==.Trublood:BAAANQAECgMIAwAAAA==.',
Ty='Tybbalt:BAAANQADCgcICAAAAA==.',
Us='Usorloups:BAAANQAECggIEQAAAA==.',
Va='Valithra:BAAANQAECgUICwAAAA==.Vargrulfr:BAAANQAECgIIBQAAAA==.',
Ve='Velonys:BAABNQAECoEbAAQOAAgKIB1UBgCXAgAOAAgK1BtUBgCXAgAPAAYKGxkfCQCiAQAQAAEKqAYMFwEmAAAAAA==.Vendy:BAAANQAECgYIDAAAAA==.',
Vi='Victory:BAAANQAECgEJAgAAAA==.Vindictus:BAAANQADCgMIAwAAAA==.Vite:BAAANQADCgYIBgAAAA==.',
Vy='Vyu:BAAANQADCgEIAQAAAA==.',
Wa='Wanayu:BAAANQAECgYICwAAAA==.Wanweasley:BAAANQAECgQJBQAAAA==.',
We='Weh:BAABNQAECoEfAAMRAAkKVyM6JgAwAwARAAkKXSA6JgAwAwASAAUKth5QEABbAQAAAA==.',
Wi='Wizagon:BAAANQAECgYICwAAAA==.',
Wo='Woodlet:BAAANQADCgMIAwAAAA==.Woodsy:BAAANQAECgYIDAAAAA==.Woody:BAAANQADCgQIBAAAAA==.Wounded:BAAANQADCgQIBAAAAA==.Woundliquor:BAAANQAECgYIBgAAAA==.',
Wu='Wuinn:BAAANQAECggIDwABNQAFFAUICwATAIgJAA==.Wunna:BAAANQAECgQICAAAAA==.',
Xc='Xcalabar:BAAANQADCgQIBAAAAA==.',
Xe='Xeran:BAAANQAECgYIDAAAAA==.',
Ya='Yawnight:BAAANQADCggJDAAAAA==.',
Zi='Zitpally:BAAANQAECgQICgABNQAECgkJJwAUAJsjAA==.',
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
