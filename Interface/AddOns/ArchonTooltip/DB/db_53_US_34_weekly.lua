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

local lookup = {'Warlock-Demonology','Warlock-Destruction','Unknown-Unknown','Warrior-Arms','Druid-Guardian','DemonHunter-Havoc','DemonHunter-Vengeance','Rogue-Outlaw',}
local provider = {region='US',realm='BlackwaterRaiders',name='US',type='weekly',zone=53,date='2026-09-15',data={Ae='Aelarion:BAAANQADCgQIBAAAAA==.',
Al='Alba:BAAANQAECgcIEgAAAA==.',
An='Andezard:BAAANQAECgIIAgAAAA==.Angelys:BAAANQADCgUICAAAAA==.',
As='Ashynn:BAAANQADCgYIBgAAAA==.Astrit:BAAANQADCgcIDQAAAA==.',
At='Athenaowl:BAAANQADCggIEQAAAA==.',
Ay='Ayanoriko:BAAANQAECgYIEwAAAA==.',
Az='Azonia:BAAANQADCgYIEQAAAA==.',
Ba='Babaganoosh:BAAANQADCgIIAwAAAA==.Bacca:BAAANQADCgcIBwAAAA==.Baleme:BAAANQADCgYIDwAAAA==.',
Be='Beans:BAABNQAECoEeAAMBAAkJ6SG0DwDjAgABAAgJzyG0DwDjAgACAAcJkxq+CwAQAgABNQAFFAMIBAADAAAAAA==.',
Bi='Bigsharder:BAAANQADCggICQABNQAFFAYIEQAEAA4WAA==.Bigstones:BAAANQAECgYIDwAAAA==.',
Bl='Blacksavior:BAAANQAECgUICQAAAA==.Blindbone:BAAANQADCggICAABNQAECgcIDQADAAAAAA==.Bloodnightz:BAAANQAECgIIAgAAAA==.Bluepocalyps:BAAANQADCgQICAAAAA==.',
Bo='Bobbydigital:BAAANQAECgEIAQAAAA==.Bolas:BAAANQAECgIIAgAAAA==.',
Br='Bracynn:BAAANQADCggIGQAAAA==.',
Ce='Cealia:BAAANQAECgUICAAAAA==.Cephalo:BAAANQADCgcIEgAAAA==.',
Ch='Chancleta:BAAANQAECgQIBAAAAA==.Christae:BAAANQAECgIIAgAAAA==.Chronuwu:BAAANQADCgYIBgAAAA==.',
Cl='Clydè:BAAANQADCgYICwAAAA==.Cláncey:BAAANQAECgYIDQAAAA==.',
Co='Compromised:BAAANQAECgUICAAAAA==.',
Cr='Crwth:BAAANQAECgEIAgAAAA==.',
Cu='Curendae:BAAANQAECgEIAQAAAA==.Curst:BAAANQADCgQIBAAAAA==.',
Da='Danika:BAAANQAECgEIAQAAAA==.Darthknight:BAAANQADCgIIAwAAAA==.Dawk:BAAANQADCggIEQAAAA==.Daxzazi:BAAANQADCggIEwAAAA==.',
De='Decillian:BAAANQAECgMIBAAAAA==.Delicious:BAEANQAECgYICQABNQAECgkJGwAEAAkYAA==.Dern:BAAANQAECgQICAAAAA==.Desolit:BAAANQAECgIIBAAAAA==.Dextur:BAAANQADCgUIBQAAAA==.',
Di='Dice:BAAANQAECgUIBQAAAA==.',
Dr='Drunkenhealz:BAAANQAECgQIBAAAAA==.Drunks:BAAANQAECgIIAgAAAA==.',
Du='Duldar:BAAANQABCgQIBAAAAA==.',
El='Elmo:BAAANQADCggIFQAAAA==.',
Er='Erosis:BAAANQAECgYIEwAAAA==.',
Es='Esidk:BAAANQAECggIAgAAAA==.Esimage:BAAANQADCggICAABNQAECggIAgADAAAAAA==.',
Ez='Ezrin:BAAANQADCggIFAAAAA==.',
Fe='Fear:BAAANQAECgYIDAAAAA==.',
Fr='Frequency:BAEANQAECgMIAwAAAA==.Frizzer:BAAANQADCgUIBQAAAA==.',
Ga='Gakopozy:BAAANQADCggIFwAAAA==.',
Gr='Grimlokke:BAAANQAECgEIAQABNQAECgYIDAADAAAAAA==.',
['Gé']='Géne:BAAANQABCgYIBgABNQAECgYIDQADAAAAAA==.',
Ha='Harbard:BAAANQAECgMIBAAAAA==.Havrin:BAABNQAECoEeAAIFAAcJ/xFaCwCUAQAFAAcJ/xFaCwCUAQAAAA==.',
He='Headshots:BAAANQADCgQIBAABNQAECgcIEgADAAAAAA==.Heizenburg:BAAANQADCgIIAgAAAA==.Hew:BAAANQAECgQIBQABNQAECgUIBQADAAAAAA==.',
Hi='Hitomi:BAAANQADCgQIBAAAAA==.',
Ho='Honk:BAAANQAECgMIBAAAAA==.Hoogaplop:BAAANQAFFAMIBAAAAA==.',
Hu='Huamulan:BAAANQAECgMIBAAAAA==.',
Ib='Ibchilling:BAAANQAECgUIBwAAAA==.Ibcleaving:BAAANQADCggIDgAAAA==.',
Ic='Icarrus:BAAANQAECgcIEwABNQAECgMIAwADAAAAAA==.Iccarus:BAAANQAECgQICAABNQAECgMIAwADAAAAAA==.',
Ig='Ignis:BAAANQAECgMIAwAAAA==.',
Is='Iseldra:BAAANQADCgUIBQAAAA==.',
It='Itslifestyle:BAAANQADCggICAAAAA==.',
Ja='Jackbfistn:BAAANQAECgIIAwABNQAECgcIDQADAAAAAA==.Jaskim:BAAANQAECgQICAAAAA==.Jaszy:BAAANQADCgMIAwABNQAECgQICAADAAAAAA==.',
Jo='Jogo:BAAANQAECgQIBQAAAA==.Johanne:BAAANQADCgcIDQAAAA==.Jordomon:BAAANQAECgEIAQAAAA==.',
Ka='Kaffee:BAAANQADCgUIBQAAAA==.Kahtonah:BAAANQABCgIIBAAAAA==.Kaltaan:BAAANQAECgQIBwAAAA==.Karasan:BAAANQADCgQIBgAAAA==.Karenas:BAAANQAECgUICQAAAA==.Katbeans:BAAANQAECgQICQAAAA==.Kathrynne:BAAANQAECgUIDAAAAA==.Katpaws:BAAANQADCgYIBgAAAA==.Kaykoh:BAAANQAECgIIAgAAAA==.',
Ke='Kelicemoon:BAAANQAECgUICgAAAA==.Kesta:BAAANQADCgIIAgAAAA==.',
Kh='Khaliope:BAAANQADCgQIBAAAAA==.',
Ki='Kiara:BAAANQAECgEIAQAAAA==.',
Kl='Kloner:BAAANQADCgIIAQAAAA==.',
Ko='Kopiroll:BAAANQAECgEIAQAAAA==.',
Kr='Krecia:BAAANQADCgUICQAAAA==.',
La='Ladielayne:BAAANQABCgUIBQAAAA==.Lahrnaon:BAAANQADCgUIBQAAAA==.Laxeron:BAAANQAECgIIAgAAAA==.',
Le='Leotherassy:BAAANQADCgMIBAAAAA==.',
Lo='Lodehavoc:BAAANQADCgUIDgAAAA==.Longboneman:BAAANQADCgEIAQABNQAECgcIDQADAAAAAA==.',
Lu='Lusariah:BAAANQADCgYICQAAAA==.',
Ly='Lyat:BAAANQAECgYIEAAAAA==.Lynthirae:BAAANQAECgYIEAAAAA==.',
Ma='Madpearl:BAAANQAECgEIAQAAAA==.',
Mc='Mcbodhran:BAAANQAECgEIAQAAAA==.Mcfeast:BAAANQAECgIIAgAAAA==.',
Me='Medra:BAAANQAECgIIAgAAAA==.Meowdi:BAAANQADCgUIDgAAAA==.',
Mi='Milou:BAAANQAECgYIDAAAAA==.Minibone:BAAANQAECgUIBQABNQAECgcIDQADAAAAAA==.',
Mo='Moishe:BAAANQABCgQIBgAAAA==.Monana:BAAANQADCgUIDAAAAA==.',
My='Mysticwood:BAAANQAECgcIDQAAAA==.',
Na='Nadjá:BAAANQADCgYIBgAAAA==.Nanija:BAAANQADCgUIDgAAAA==.Nathen:BAAANQADCgUIBQAAAA==.',
Ni='Nightcat:BAAANQAECgQICQAAAA==.Nitestorm:BAAANQAECgUIBwAAAA==.Nixstyn:BAAANQABCgUIBwAAAA==.',
No='Nobonesjones:BAAANQAECgMIBAAAAA==.Noraelissa:BAAANQABCgcIEAAAAA==.',
Og='Ogwarshock:BAAANQAECgYIEgAAAA==.',
Ol='Oliiver:BAAANQAECgUICAAAAA==.',
Om='Omni:BAAANQABCgMIAwABNQAECgYIDAADAAAAAA==.',
Or='Orcgasams:BAAANQADCgYIBwAAAA==.',
Ox='Oxidatia:BAAANQAECgEIAQAAAA==.',
Pa='Panaceus:BAAANQAECgYICgAAAA==.',
Pe='Perpetrator:BAAANQABCgIIAgABNQAECgEIAQADAAAAAA==.',
Ph='Phrequency:BAEANQADCgcIDQABNQAECgMIAwADAAAAAA==.',
Po='Poisonóus:BAAANQAECgYIEwAAAA==.Polyxo:BAAANQADCggIGAAAAA==.Pon:BAAANQABCgIIAgAAAA==.',
Pr='Prépared:BAABNQAECoEYAAMGAAkJ9BjQEgBjAgAGAAgJdRrQEgBjAgAHAAEJ6wzsFwAtAAAAAA==.',
Py='Pyrelic:BAAANQADCgYIBgAAAA==.',
Qa='Qayllera:BAAANQAECgEIAQAAAA==.',
Ra='Radicchio:BAAANQADCgUIDAAAAA==.Radkeem:BAAANQAECgUICAAAAA==.Ragnar:BAAANQADCgEIAQAAAA==.Raya:BAAANQAECgEIAQABNQABCgYIAgADAAAAAA==.',
Re='Reluanne:BAAANQADCggICAAAAA==.Remorsa:BAAANQADCgcIDQAAAA==.Reshath:BAAANQADCgEIAQAAAA==.Reznor:BAAANQAECgYIDQAAAA==.',
Ro='Roejawb:BAAANQAECgQICAAAAA==.Roeshamboe:BAAANQADCgYIBgAAAA==.Rosealia:BAAANQADCggIFgAAAA==.',
Ry='Ryder:BAAANQADCggIEQABNQADCgEIAQADAAAAAA==.',
Sa='Sableanne:BAAANQADCgYICgAAAA==.Sacon:BAAANQADCgYIBgABNQADCggIFQADAAAAAA==.Sahmeah:BAAANQADCgUIBwAAAA==.Saintzan:BAAANQAECgUICgAAAA==.Salorll:BAAANQADCgYICgAAAA==.Savia:BAAANQADCgQIBAAAAA==.',
Sc='Schmoogus:BAAANQADCgcIBQAAAA==.Schmoop:BAAANQAECggIEgABNQAFFAMIBAADAAAAAA==.',
Se='Senza:BAAANQADCggIGQAAAA==.Senzyri:BAAANQAECgUICQAAAA==.',
Sh='Shadyscales:BAABNQAECoEYAAIIAAkJgRAwBABbAgAIAAkJgRAwBABbAgAAAA==.Shenro:BAAANQAECgMIBAAAAA==.Shierà:BAAANQADCgcIBwAAAA==.',
Si='Simic:BAAANQADCgcIEwAAAA==.',
Sm='Smiddy:BAAANQAECgUIBQAAAA==.',
So='Soyjak:BAAANQAECgQIBQAAAA==.',
Sp='Spin:BAAANQAECgEIAgAAAA==.',
St='Stonymahoney:BAAANQAECgQIBAAAAA==.',
Su='Suraisu:BAAANQAECgQIBwAAAA==.',
Sv='Sveela:BAAANQAECgcIEQAAAA==.Sveelaa:BAAANQAECgQIDAABNQAECgcIEQADAAAAAA==.Sveella:BAAANQABCgMIAwABNQAECgcIEQADAAAAAA==.',
Sy='Syleinthus:BAAANQADCgQIBAAAAA==.',
Ta='Tacocat:BAAANQAECgUICwAAAA==.',
Te='Temlock:BAAANQAECgIIAgAAAA==.Temtank:BAAANQADCggIFQABNQAECgIIAgADAAAAAA==.',
Th='Thechiefster:BAAANQAECgIIAgAAAA==.',
Tr='Trukarak:BAAANQAECgIIAgAAAA==.',
Va='Valor:BAAANQAECgMIBQAAAA==.',
Ve='Veepwakeup:BAAANQAECggIAgAAAA==.',
Wa='Wagons:BAAANQAECgcIBgAAAA==.',
Wi='Wildama:BAAANQAECgEIAQAAAA==.Wildtail:BAAANQADCgcIDAAAAA==.',
Xh='Xhadowz:BAAANQAECgYICQAAAA==.',
Xi='Xiao:BAAANQAECgUICAAAAA==.Xibi:BAAANQAECgMIAwAAAA==.',
Ya='Yahargul:BAAANQAECgQIBwAAAA==.',
Yo='Yogafarts:BAAANQADCgYIBgAAAA==.',
Za='Zanatilli:BAAANQADCgUIDgAAAA==.Zaradin:BAAANQADCggIDQABNQADCggIEQADAAAAAA==.',
Ze='Zeik:BAAANQAECgUICAAAAA==.Zerkchum:BAAANQADCgQIBAAAAA==.',
Zu='Zurone:BAAANQAECgMIAgAAAA==.',
['Æv']='Ævølütîøn:BAAANQAECgQIBgAAAA==.',
['Ÿa']='Ÿamar:BAAANQADCgUICgAAAA==.',
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
