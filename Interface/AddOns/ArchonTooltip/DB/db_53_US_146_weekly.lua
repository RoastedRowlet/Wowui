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
local provider = {region='US',realm='Madoran',name='US',type='weekly',zone=53,date='2026-09-01',data={Ad='Adversary:BAAANQADCgIIAgAAAA==.',
Ag='Aglaranna:BAAANQADCgYIBgAAAA==.',
Ai='Aiyanna:BAAANQADCgEIAQABNQADCgYICAABAAAAAA==.',
Al='Alric:BAAANQADCggIDgAAAA==.',
Ar='Ardhammer:BAAANQADCgcIDQAAAA==.Arragorn:BAAANQAECgQIBAAAAA==.',
As='Astal:BAAANQAECgYICgAAAA==.',
At='Ate:BAAANQADCgcIDQAAAA==.',
Au='Aurathur:BAAANQADCgUICQAAAA==.',
Av='Avyl:BAAANQADCgEIAQAAAA==.',
Az='Azalenne:BAAANQADCgcIBwABNQAECgMIAwABAAAAAA==.Azriella:BAAANQADCgYICwAAAA==.Azuren:BAAANQADCggIEgAAAA==.',
Ba='Bacon:BAAANQAECgIIAgAAAA==.Bankai:BAAANQAECgQIBAAAAA==.',
Be='Beefstrasz:BAAANQAECgYICgAAAA==.Beyla:BAAANQADCgcIDAAAAA==.',
Bl='Bleau:BAAANQADCgYIBgAAAA==.Bloodhornbob:BAAANQADCgQIBQAAAA==.Bloodrayna:BAAANQADCgUIBQAAAA==.Bloodymary:BAAANQAECgQIBAAAAA==.Bluebarrie:BAAANQADCgUICQAAAA==.Bluwolferine:BAAANQAECgEIAQAAAA==.',
Bo='Boolzeye:BAAANQABCgIIBAAAAA==.Bowl:BAAANQAECgYICgAAAA==.',
Br='Branchling:BAAANQADCgEIAQABNQAECgcIDQABAAAAAA==.',
Bu='Butterkip:BAAANQAECgYICgAAAA==.',
Ce='Cellan:BAAANQADCgUIBwAAAA==.',
Ch='Cheww:BAAANQADCgYIBgAAAA==.Chlorofõrm:BAAANQADCggIDAAAAA==.Chokonit:BAAANQADCgYIBgAAAA==.Chopahoe:BAAANQADCggIDgAAAA==.Chumpcooker:BAAANQADCgUIBQAAAA==.',
Cl='Clamius:BAAANQAECgYIBwAAAA==.Cliff:BAAANQADCggICAAAAA==.',
Co='Coldstone:BAAANQADCgMIBAAAAA==.Conduit:BAAANQAECgYIBwAAAA==.Coombrain:BAAANQADCgEIAQAAAA==.Cotopla:BAAANQAECgEIAQAAAA==.',
De='Deathlentlez:BAAANQAECgIIAgAAAA==.Deepséeded:BAAANQADCgEIAQAAAA==.Delphyne:BAAANQABCgIIAgAAAA==.Demonià:BAAANQADCgUIBgAAAA==.',
Di='Disçiple:BAAANQADCgYICgAAAA==.',
Dj='Djazz:BAAANQADCgMIAwAAAA==.',
Dr='Drowsee:BAAANQADCgUIBgAAAA==.',
['Dà']='Dàrkscythe:BAAANQADCgEIAQAAAA==.',
Ea='Eazywin:BAAANQADCgUIBQAAAA==.',
Eh='Ehlsi:BAAANQAECgIIAgAAAA==.',
Ei='Eirinny:BAAANQADCggIDgAAAA==.',
El='Elindez:BAAANQADCgcIDQAAAA==.Elyviel:BAAANQAECgMIAwAAAA==.',
Em='Emyrson:BAAANQADCgEIAQAAAA==.',
Eo='Eowen:BAAANQAECgMIAwAAAA==.',
Ez='Ezmee:BAAANQADCgUIDAAAAA==.',
Fr='Frostdruid:BAAANQADCgEIAQAAAA==.',
Fu='Fundip:BAAANQADCgcIDQAAAA==.',
Fy='Fythra:BAAANQADCgUIBQAAAA==.Fythri:BAAANQADCgQIBAABNQADCgUIBQABAAAAAA==.',
Ga='Gart:BAAANQADCgcIBwAAAA==.',
Gi='Gibhasarms:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.Giblock:BAAANQAECgMIAwAAAA==.Ginju:BAAANQADCggIDgAAAA==.',
Go='Golomojek:BAAANQADCgYICAAAAA==.',
Gr='Gralmerte:BAAANQAECgEIAQAAAA==.Graziella:BAAANQADCgYIBQAAAA==.',
Gu='Guthrie:BAAANQADCgYICgAAAA==.',
Ha='Haether:BAAANQAECgIIAgAAAA==.',
He='Healulngtime:BAAANQADCgQIBwAAAA==.Heiling:BAAANQADCggIDgAAAA==.',
Ho='Holymun:BAAANQABCgQIBAABNQADCgcIBwABAAAAAA==.Holyox:BAAANQADCggICAAAAA==.',
Ht='Hturtle:BAAANQAECgIIAgAAAA==.',
Hu='Huzrula:BAAANQABCgQIAwAAAA==.',
In='Inexorable:BAAANQAECgYIBwAAAA==.',
Io='Iolegnaro:BAAANQAECgEIAgABNQAECgcICgABAAAAAA==.',
It='Itches:BAAANQAECggIDgAAAA==.',
Iz='Izry:BAAANQADCgQIBwAAAA==.',
Ja='Jaason:BAAANQAECgEIAQAAAA==.Jarico:BAAANQADCgUIBwABNQADCgYICQABAAAAAA==.',
Jh='Jhunts:BAAANQADCgYIBgAAAA==.',
Ji='Jinfuse:BAAANQADCggIDgAAAA==.',
Jp='Jpdh:BAAANQAECgQICAAAAA==.Jpdumb:BAAANQADCggICAABNQAECgQICAABAAAAAA==.',
Ju='Juddory:BAAANQADCgUICQAAAA==.Junksvil:BAAANQADCgYICQAAAA==.',
Kh='Khalyon:BAAANQAECgMIBAAAAA==.',
Ki='Killerelf:BAAANQADCgUIBQAAAA==.',
Ko='Korinth:BAEANQAECgYICAAAAA==.',
Kr='Kriaalis:BAAANQADCgEIAQAAAA==.',
Ky='Kyra:BAAANQADCggIBAAAAA==.Kyril:BAAANQAECgUICQAAAA==.',
La='Lagabriela:BAAANQAECgEIAQAAAA==.Lazuli:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.',
Le='Legault:BAAANQADCgcIDQAAAA==.Legionofboom:BAAANQADCgEIAQAAAA==.Lethfel:BAAANQADCgcIDQAAAA==.',
Li='Lillithfaust:BAAANQADCgcICgAAAA==.Lionfury:BAAANQADCgQIBAAAAA==.Lionguard:BAAANQAECgQIBQAAAA==.Livie:BAAANQADCgUICAAAAA==.',
Lo='Loca:BAAANQAECgEIAQAAAA==.Lonelylad:BAAANQABCgIIAgAAAA==.Loraddesmos:BAAANQADCggIEAAAAA==.',
Lu='Lucance:BAAANQADCgQIBAAAAA==.',
Ly='Lyship:BAAANQAECgIIAgAAAA==.',
Ma='Maeg:BAAANQAECgMIBAAAAA==.Maleveck:BAAANQADCgYIBgAAAA==.',
Mc='Mctanker:BAAANQAECgEIAQAAAA==.',
Me='Megavolt:BAAANQADCggICAABNQAECggIDgABAAAAAA==.Megs:BAAANQADCgQIBgAAAA==.Merc:BAAANQAECgYICQAAAA==.',
Mi='Miluo:BAAANQAECgIIAgAAAA==.Mindpuck:BAAANQADCgUIBQAAAA==.Mintchyp:BAAANQADCgIIAgAAAA==.Mirespike:BAAANQAECgYICgAAAA==.Mistbrew:BAAANQADCgMIAwAAAA==.',
Mo='Mommacougar:BAAANQADCgIIAgAAAA==.Moon:BAAANQABCgIIAgABNQADCgMIAwABAAAAAA==.Morlis:BAAANQADCgQIBAAAAA==.Morlock:BAAANQADCggIDgAAAA==.Morningstahr:BAAANQAECgIIAgAAAA==.',
Mu='Munion:BAAANQADCgcIBwAAAA==.',
Mv='Mvp:BAAANQADCgQIBAAAAA==.',
['Më']='Mëdpac:BAAANQAECgEIAQAAAA==.',
Na='Nanako:BAAANQADCgUIBQAAAA==.Naughtyreapr:BAAANQADCgEIAQABNQADCgYICwABAAAAAA==.',
Ne='Nevicus:BAAANQADCgEIAQAAAA==.',
Ni='Nickayla:BAAANQADCgYICwAAAA==.Nimblecow:BAAANQADCgEIAQAAAA==.',
No='Noobacleese:BAAANQADCggIDgAAAA==.Noraviae:BAAANQADCgMIBgAAAA==.',
Ny='Nyghtrider:BAAANQADCgYICAAAAA==.Nymëra:BAAANQADCgcIDQAAAA==.Nyneeve:BAAANQADCgcIDQAAAA==.',
Pa='Palpatinee:BAAANQADCgUIBQAAAA==.Parabelum:BAAANQADCgYICAAAAA==.Partita:BAAANQADCgUIBQABNQADCgYIBQABAAAAAA==.',
Pb='Pbób:BAAANQADCgMIAwAAAA==.',
Pe='Percocetpete:BAAANQAECgcIBwABNQAECggICAABAAAAAA==.Peregrine:BAAANQADCgEIAQAAAA==.',
Ph='Phaet:BAAANQAECgUICQAAAA==.Phaux:BAAANQADCgQIBAAAAA==.',
Pi='Piper:BAAANQADCgQIBAAAAA==.',
Pl='Plâgue:BAAANQADCggIDwAAAA==.',
Pu='Punslug:BAAANQADCgMIAwABNQAECgYICgABAAAAAA==.Puntthegnome:BAAANQADCgEIAQABNQAECgcIDQABAAAAAA==.',
Ra='Rainforest:BAAANQADCgYICAAAAA==.Ramden:BAAANQAECgIIAgAAAA==.Rampant:BAAANQADCgYIBgAAAA==.Randolier:BAAANQADCggIDgAAAA==.Ratherton:BAAANQAECgcIDQAAAA==.Rathtard:BAAANQADCgYICwABNQAECgcIDQABAAAAAA==.',
Re='Resoluteone:BAAANQAECgEIAQAAAA==.Retnu:BAAANQADCgQICAAAAA==.Revytwohand:BAAANQAECgYICgAAAA==.',
Ru='Rumii:BAAANQADCgcIBwAAAA==.',
Sa='Sabeladys:BAAANQADCgcIBwAAAA==.Saifir:BAAANQADCggIDgAAAA==.Sardmagia:BAAANQAECgIIAgAAAA==.Sardmongo:BAAANQADCgMIBAAAAA==.Sarduccini:BAAANQADCggICAABNQAECgIIAgABAAAAAA==.',
Si='Silvalus:BAAANQADCgEIAQAAAA==.Silvertide:BAAANQAECgEIAQAAAA==.',
Sk='Skyeforce:BAAANQADCgYICAAAAA==.',
Sl='Slipknoth:BAAANQAECgEIAQAAAA==.',
So='Sondaar:BAAANQABCgQIBQAAAA==.Sonoforak:BAAANQADCgQIBAAAAA==.',
Sp='Sped:BAAANQAECgIIAgAAAA==.',
St='Stiffyhaze:BAAANQADCgYICgAAAA==.Stormsteel:BAAANQADCgMIAwAAAA==.Stossel:BAAANQADCgYICwAAAA==.',
Sw='Sweetie:BAAANQADCgEIAQAAAA==.',
Ta='Talas:BAAANQADCggIDgAAAA==.Tanksabunch:BAAANQADCgIIAgAAAA==.',
Te='Tehmay:BAAANQADCgIIAgAAAA==.Tenssid:BAAANQADCgQIBgAAAA==.',
Th='Thorclap:BAAANQADCgUIBQAAAA==.',
Ti='Tim:BAAANQADCggICAABNQAECgQIBgABAAAAAA==.',
To='Tooru:BAAANQAECgYICgAAAA==.',
Tw='Twinkles:BAAANQAECgIIAgAAAA==.Twotoetimmy:BAAANQAECgIIAgAAAA==.',
Ul='Ulysius:BAAANQAECgIIAgAAAA==.',
Va='Valkisek:BAAANQAECgEIAQAAAA==.Vallarfax:BAAANQADCggIDgAAAA==.Vandro:BAAANQAECgMIBAAAAA==.Vashdk:BAAANQAECgYICgAAAA==.',
Ve='Velcyn:BAAANQADCggICAAAAA==.Veloranas:BAAANQAECgEIAQAAAA==.Vespyr:BAAANQADCgQIBAAAAA==.Vewdoo:BAAANQAECgIIAgAAAA==.Vexiara:BAAANQADCgYICwABNQAECgMIAwABAAAAAA==.',
Vi='Vizimir:BAAANQADCgYICwAAAA==.',
Vy='Vynstabbin:BAAANQADCgcIDQAAAA==.',
Wa='Warfarin:BAAANQADCgMIAwAAAA==.',
We='Weaken:BAAANQAECgUIBQAAAA==.',
Wi='Wizkerbizkit:BAAANQADCgcIDAAAAA==.',
Wy='Wyrmheal:BAAANQAECgIIAgAAAA==.',
Ya='Yamihime:BAAANQAECgEIAQAAAA==.Yatiri:BAAANQADCgcIBwAAAA==.',
Za='Zalinis:BAAANQADCgIIAgAAAA==.',
Ze='Zeaket:BAAANQAECggIDgAAAA==.Zephyr:BAAANQADCgIIBAABNQADCgQIBAABAAAAAA==.Zerrayna:BAAANQADCgYIBgAAAA==.',
Zi='Zinbad:BAAANQADCgUIBwAAAA==.',
Zo='Zorcan:BAAANQADCgUICAAAAA==.',
Zu='Zugzugz:BAAANQAECgIIAgAAAA==.Zulfilith:BAAANQADCgQIBAAAAA==.',
['Ãi']='Ãinz:BAAANQADCgIIAgAAAA==.',
['Ða']='Ðachee:BAAANQAECgEIAQAAAA==.',
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
