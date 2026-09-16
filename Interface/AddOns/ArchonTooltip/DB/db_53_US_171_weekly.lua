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

local lookup = {'Unknown-Unknown','DeathKnight-Frost','Paladin-Protection','Mage-Arcane','Mage-Frost','Priest-Holy','Hunter-BeastMastery','DeathKnight-Blood','Rogue-Assassination','Paladin-Retribution','Paladin-Holy','DeathKnight-Unholy','DemonHunter-Havoc','Evoker-Preservation',}
local provider = {region='US',realm='Onyxia',name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Abrams:BAAANQAECgQIBQAAAA==.',
Ad='Addý:BAAANQAECgYIDQAAAA==.',
Ae='Aethyra:BAAANQAECgMIBAAAAA==.',
Ah='Ahimsa:BAAANQAECgUICwAAAA==.',
Ai='Ailisuuith:BAAANQAECgQIBQAAAA==.',
Al='Almamun:BAAANQADCgQIBgAAAA==.',
Ar='Arcz:BAAANQADCgEIAQABNQAECgMICAABAAAAAA==.',
As='Ashenclaw:BAAANQAECgcICAAAAA==.',
At='Athalena:BAAANQAECgMIAwABNQAECgMIAwABAAAAAA==.',
Ba='Babyboo:BAAANQADCgIIAgAAAA==.Bamboom:BAAANQAECgEIAgAAAA==.',
Bi='Biggrnmonstr:BAAANQAECgEIAgABNQAECggIFwACABYVAA==.Bigxthezug:BAAANQAECgYIDwAAAA==.',
Bl='Blaine:BAAANQADCgcIEgAAAA==.',
Bo='Bongripa:BAAANQABCgEIAQAAAA==.Bonquiqui:BAAANQADCgcIDAAAAA==.Boypartz:BAAANQAECgMIBwAAAA==.',
Br='Breakfast:BAAANQADCgMIAwABNQAECgYIDwABAAAAAA==.Brittinia:BAAANQAECgIIAwAAAA==.',
Bu='Bulbasaurus:BAAANQAECgcIEgAAAA==.Bus:BAACNQAFFIEOAAIDAAUJlCCDAAACAgADAAUJlCCDAAACAgA1AAQKgRoAAgMACQkOJdAAAMYDAAMACQkOJdAAAMYDAAAA.',
Ce='Celeres:BAAANQAECgcIEgAAAA==.Ceo:BAAANQAECgMICQAAAA==.',
De='Deadcell:BAAANQAECgUIAwAAAA==.Denamage:BAABNQAECoEdAAMEAAkJWRYLOgCpAgAEAAkJWRYLOgCpAgAFAAUJ/QbzEADbAAAAAA==.',
Do='Doomtickle:BAAANQADCgYIBgAAAA==.',
Dy='Dysknektd:BAAANQABCgIIAwAAAA==.',
Ea='Earthigga:BAAANQADCgQIBAAAAA==.',
Ei='Eichmann:BAAANQADCgUIBQAAAA==.',
El='Eldruida:BAAANQAECgcIEQAAAA==.Elixxi:BAAANQADCgYIBgAAAA==.Ellipsoro:BAAANQAECgQICQAAAA==.Eltrol:BAAANQAECgEIAQAAAA==.',
Er='Erale:BAAANQAECgEIAQAAAA==.',
Fa='Faeris:BAABNQAECoEZAAIGAAkJhSG8BgA5AwAGAAkJhSG8BgA5AwAAAA==.Fatalis:BAABNQAECoEgAAIHAAkJGBKXHgCRAgAHAAkJGBKXHgCRAgAAAA==.',
Fe='Fedqt:BAAANQADCgYICgAAAA==.Felko:BAAANQADCgIIAgAAAA==.',
Fi='Fiestykitten:BAAANQADCgYICgAAAA==.Fizaw:BAAANQAECgYIDwAAAA==.',
Fl='Floydmagussy:BAABNQAECoEXAAIEAAkJWh+IFgBDAwAEAAkJWh+IFgBDAwAAAA==.',
Fo='Foamdk:BAAANQADCgQIBAAAAA==.',
Fr='Freezypuff:BAAANQADCggICAAAAA==.Frostee:BAAANQAECgEIAQAAAA==.Frøzen:BAAANQADCgcIBwAAAA==.',
Ga='Gaurr:BAAANQAECgEIAgAAAA==.',
Ge='Geneviere:BAAANQADCgMIAwAAAA==.',
Gi='Gianna:BAAANQADCggICwAAAA==.Gislain:BAAANQADCgcIDQAAAA==.',
Go='Goldeye:BAAANQADCgYIEwAAAA==.',
Gr='Greyspirit:BAAANQAECgUIDwAAAA==.Grimothy:BAAANQAECgUIBQAAAA==.',
Ha='Halcoldrek:BAAANQADCgQIBAAAAA==.',
Hb='Hbc:BAAANQAECgYIBgABNQABCgIIAwABAAAAAA==.',
He='Healarious:BAAANQADCgQIBAAAAA==.Hembrota:BAAANQADCgQICQAAAA==.Heyz:BAAANQADCgYIBgABNQAECgMICAABAAAAAA==.',
Hi='Himbo:BAAANQAECgIIAgAAAA==.',
Ho='Hogs:BAAANQAECgQIDgABNQAECgYIDwABAAAAAA==.Holypoopp:BAAANQAECgUIBwAAAA==.Holyreturn:BAAANQAECgQIBwAAAA==.',
Il='Illanyth:BAAANQADCgUIBQAAAA==.',
Im='Imran:BAABNQAECoEeAAIDAAkJGBVOCwAtAgADAAkJGBVOCwAtAgAAAA==.',
In='Inthelayer:BAAANQADCgYIBgABNQAECgYIDwABAAAAAA==.',
Je='Jether:BAAANQADCgYICgAAAA==.',
Jo='Jojobaggins:BAAANQAECgUIBQAAAA==.',
Kc='Kcthegreat:BAAANQADCgQIBQAAAA==.',
Ke='Keyholes:BAACNQAFFIERAAIIAAYJgB0WAQAlAgAIAAYJgB0WAQAlAgA1AAQKgRcAAggACQkoISsJACUDAAgACQkoISsJACUDAAE1AAEKAggDAAEAAAAA.Keyohs:BAAANQADCgcICAABNQABCgIIAwABAAAAAA==.',
Ki='Kirky:BAAANQADCgUIBgAAAA==.',
Kk='Kkoda:BAAANQADCgUIBQAAAA==.',
Ko='Koal:BAAANQAECgQICwAAAA==.Kodabear:BAAANQADCggICAAAAA==.',
Kr='Kronos:BAAANQADCgYIBgABNQAECgUIBgABAAAAAA==.',
Ku='Kushage:BAAANQADCgMIAwAAAA==.',
Le='Lettussy:BAABNQAECoEYAAIJAAkJ2iWZAADUAwAJAAkJ2iWZAADUAwABNQAECgkJHgAEAA8jAA==.',
Li='Lixxi:BAAANQAECgYIDAAAAA==.',
Lu='Luminyssa:BAAANQADCgEIAQAAAA==.',
['Lú']='Lúthien:BAAANQAECgUIBQAAAA==.',
Ma='Maeby:BAAANQADCgYIBgAAAA==.Magicwater:BAABNQAECoEXAAIEAAkJGSGLEgBaAwAEAAkJGSGLEgBaAwAAAA==.',
Me='Meeoowzer:BAAANQAECgUICwAAAA==.Meloo:BAAANQAECgIIAgAAAA==.',
Mo='Mollymauk:BAAANQAECgMIAwAAAA==.Moorality:BAAANQAFFAIIAgABNQABCgIIAwABAAAAAA==.Moretino:BAAANQADCgEIAQAAAA==.Morgane:BAAANQADCgEIAQAAAA==.Mothra:BAAANQADCggICAABNQAECgUICwABAAAAAA==.',
Mu='Muhjo:BAAANQADCgYIDQAAAA==.Murryjane:BAAANQAECgMICAAAAA==.Muufarmer:BAAANQADCgIIAgAAAA==.',
Na='Natedk:BAAANQADCgUIBQAAAA==.',
Ne='Neyt:BAAANQAECgYIDwAAAA==.',
Ni='Nitesrider:BAAANQADCgcIBwAAAA==.',
No='Nora:BAACNQAFFIETAAIKAAcJViIOAADUAgAKAAcJViIOAADUAgA1AAQKgSMAAwoACQl9JkgBAOwDAAoACQl9JkgBAOwDAAsABwnJHx8ZAJYCAAAA.Nostrodom:BAAANQADCgcIEQAAAA==.',
Nu='Nubbs:BAAANQAECgQICQAAAA==.Nubheala:BAAANQADCgcIFAAAAA==.Nuri:BAAANQAECgMIBgAAAA==.',
Od='Odylight:BAAANQADCggICQAAAA==.',
Pi='Pingopango:BAAANQAECgIIAgABNQAECgYICAABAAAAAA==.Pinkdefender:BAAANQADCggICAABNQAECggIFwACABYVAA==.Pinpanpum:BAAANQAECgEIAQAAAA==.',
Po='Pokeumon:BAAANQADCggIEwAAAA==.Poosistrox:BAABNQAECoEXAAQCAAgJFhUeHACoAQACAAcJwBAeHACoAQAMAAYJNA0TQABeAQAIAAQJkg/AWADKAAAAAA==.',
Ps='Pspspspsps:BAAANQADCgEIAQAAAA==.',
Pt='Ptheve:BAACNQAFFIETAAINAAcJqyULAAAGAwANAAcJqyULAAAGAwA1AAQKgR0AAg0ACQnjJjwAAAYEAA0ACQnjJjwAAAYEAAAA.',
Qs='Qsham:BAAANQAECgIIAgAAAA==.',
Qw='Qwarlock:BAAANQAECgQICAAAAA==.',
Ra='Raela:BAABNQAECoESAAICAAcJ4x1yDwBYAgACAAcJ4x1yDwBYAgAAAA==.Rahnarmight:BAAANQADCgMIAwAAAA==.Raygor:BAAANQAECgIIAwAAAA==.Razzle:BAAANQADCgIIAgABNQAECgMIBgABAAAAAA==.',
Ri='Rickthyr:BAAANQAECgMIBQAAAA==.',
Ro='Rosewalker:BAAANQAECgYIEAABNQAECgkJFwAEABkhAA==.Rosewall:BAAANQADCgIIAgABNQAECgkJFwAEABkhAA==.Rottgut:BAAANQADCgEIAQAAAA==.',
Ry='Rykix:BAAANQADCgEIAQAAAA==.Rykò:BAAANQAECgUIDwAAAA==.',
Sa='Salmorg:BAAANQAECgcIEgAAAA==.Sayafaed:BAAANQAECgYIDAAAAA==.',
Sc='Scalen:BAAANQADCgYIBgAAAA==.Scatback:BAAANQAECgMIBgAAAA==.Schwarzmagic:BAAANQADCggIEgAAAA==.',
Sh='Shilor:BAAANQAECgEIAQAAAA==.Shogun:BAAANQADCgcIGAAAAA==.',
Si='Sicarii:BAAANQAECgYIDwAAAA==.Sicarrious:BAAANQADCggIEQABNQAECgYIDwABAAAAAA==.Sinatra:BAAANQAECgMIAwAAAA==.',
Sk='Skyarc:BAAANQAECgEIAgABNQAECggIDQABAAAAAA==.Skybolt:BAAANQAECgIIAgABNQAECggIDQABAAAAAA==.Skylite:BAAANQAECggIDQAAAA==.Skyrak:BAAANQADCgQIBAABNQAECggIDQABAAAAAA==.',
So='Soulpurge:BAAANQADCgEIAQAAAA==.',
Sp='Spënny:BAAANQAECgQIBAAAAA==.',
St='Stélle:BAAANQAECgYIDAAAAA==.',
Su='Supdude:BAAANQAECgYIDQAAAA==.',
Sy='Sycoraxx:BAAANQABCgIIAgAAAA==.',
Ta='Tatorz:BAAANQAECgQICAAAAA==.Tazbirkloa:BAAANQADCgUIBQAAAA==.',
Ti='Tigas:BAAANQAECggIDwAAAA==.',
To='Tooth:BAAANQADCgQIBQAAAA==.',
Tr='Trashdragon:BAAANQAECgMIBgAAAA==.',
Ty='Typhoonz:BAAANQADCgYIBgAAAA==.',
Vi='Vipex:BAAANQAECgEIAQAAAA==.',
Vo='Vore:BAAANQADCgYIBgAAAA==.',
Vy='Vynii:BAAANQAECgUICgAAAA==.',
Wa='Wallofstars:BAAANQADCgQIBQAAAA==.Wardamage:BAAANQABCgEIAQAAAA==.Wasabi:BAAANQAECgIIAgAAAA==.',
Xa='Xaida:BAAANQAECgYICgABNQAFFAcIFgAOAHILAA==.Xalant:BAAANQADCgEIAQAAAA==.',
Yo='Yourhammy:BAAANQADCgMIAwAAAA==.Yoyo:BAAANQADCgYIDAAAAA==.',
Yt='Ytteriul:BAAANQADCgYIEgAAAA==.',
Za='Zangyaku:BAAANQAECgMICQAAAA==.',
Ze='Zenis:BAAANQAECgYICAAAAA==.Zerø:BAAANQADCgIIAgAAAA==.Zetsuï:BAAANQAECgYIBgAAAA==.',
['ßa']='ßadfish:BAAANQAECgYIDwAAAA==.',
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
