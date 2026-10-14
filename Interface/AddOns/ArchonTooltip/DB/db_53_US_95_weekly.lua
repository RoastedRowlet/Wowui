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

local lookup = {'Unknown-Unknown','Warlock-Destruction','Shaman-Elemental','Rogue-Assassination','Monk-Windwalker','DemonHunter-Havoc','Warlock-Affliction','Monk-Brewmaster','Monk-Mistweaver','DeathKnight-Blood','Hunter-BeastMastery','DeathKnight-Frost','Mage-Arcane','Paladin-Retribution','Evoker-Devastation','Evoker-Preservation','Warlock-Demonology','Paladin-Holy','DeathKnight-Unholy','Warrior-Arms','Warrior-Fury','Warrior-Protection',}
local provider = {region='US',realm='Fenris',name='US',type='weekly',zone=53,date='2026-10-13',data={Ad='Adranelidk:BAAANQAECgIIAgAAAA==.',
Ae='Aeromina:BAAANQADCggICwAAAA==.',
Aj='Ajkuna:BAAANQAECgIIAwAAAA==.',
Ak='Akthor:BAAANQAECggIAQAAAA==.',
Am='Amadori:BAAANQAECgQIBQAAAA==.',
An='Anarchy:BAAANQAECgIIAgAAAA==.Ancalagon:BAAANQAECgUIDQAAAA==.Angelic:BAAANQAECgEIAQAAAA==.Anguish:BAAANQAECgUIDAAAAA==.',
Ap='Appix:BAAANQADCgQIBAAAAA==.',
As='Ashtara:BAAANQADCgEIAQAAAA==.',
Au='Aussilicious:BAAANQADCgIIAgABNQAECgUIDwABAAAAAA==.',
Av='Averyed:BAAANQADCgcIHQAAAA==.',
Az='Azerennia:BAAANQAECgUIDgAAAA==.Azerious:BAABNQAECn8XAAICAAcKvAkXHwB1AQACAAcKvAkXHwB1AQAAAA==.Azrokke:BAAANQAECgMIBAAAAA==.',
Ba='Babetter:BAAANQAECgQIBQAAAA==.Baelz:BAABNQAECn8aAAIDAAgKlwb6kQBzAQADAAgKlwb6kQBzAQAAAA==.Bahamaut:BAAANQAECgIJAgABNQAECgUIDwABAAAAAA==.Ballinacup:BAAANQADCgMIAwAAAA==.Bazroz:BAAANQADCgEJAQAAAA==.',
Be='Beerless:BAAANQAECgUIEgAAAA==.Bencicil:BAAANQAECgMIAwAAAA==.Berk:BAAANQADCgMIAwABNQAECgkJIAAEAP0LAA==.',
Bi='Bigbootijudy:BAABNQAECn8VAAIDAAgKPhpmTwA3AgADAAgKPhpmTwA3AgABNQAFFAcIGAAFACQcAA==.',
Bl='Blayde:BAAANQADCgQIBAAAAA==.Blowtorch:BAAANQAECgEIAQAAAA==.',
Bo='Bobmb:BAAANQADCgYIDgAAAA==.Botrollsnifr:BAAANQADCgEIAgABNQAECgUIDQABAAAAAA==.',
Br='Brain:BAAANQAECgEIAQAAAA==.Brothergrog:BAAANQADCgcICwAAAA==.',
Bu='Bunky:BAABNQAECn8gAAIEAAkK/QvfQQC9AQAEAAkK/QvfQQC9AQAAAA==.Butters:BAAANQAECgQICQAAAA==.',
Ca='Cair:BAACNQAFFH8OAAIGAAYKNiRAAwBRAgAGAAYKNiRAAwBRAgA1AAQKfy8AAgYACQrvJGEIAHQDAAYACQrvJGEIAHQDAAAA.Camili:BAAANQAECgEIAQAAAA==.',
Ch='Charling:BAAANQAECgQIBAABNQAECgkJMgAHAIsaAA==.Chickensnake:BAAANQADCgIIAgAAAA==.Chlonghorn:BAAANQAECgYIEwAAAA==.',
Cu='Cuffaladin:BAAANQADCggICAAAAA==.',
Da='Darrik:BAAANQAECgUIEAAAAA==.David:BAAANQAECgEIAQAAAA==.',
De='Deathshand:BAAANQAECgIIAgAAAA==.Deezhealz:BAAANQAECgEIAQAAAA==.',
Di='Diddyfisting:BAACNQAFFH8YAAMFAAcKJBxfAgBfAgAFAAcKJBxfAgBfAgAIAAEKAACXCwA1AAA1AAQKfyYABAUACQoVIpUIAEQDAAUACQoVIpUIAEQDAAkAAgpJFAw+AH8AAAgAAgrpCLQsAFMAAAAA.Dirtydill:BAAANQAECgYIBgAAAA==.Divine:BAAANQAECgEIAQAAAA==.Divinelaw:BAEANQADCgUIBQABNQAECggIJQAKADcdAA==.',
Do='Dotchester:BAAANQADCgYIDAAAAA==.Doubleberry:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.',
Dr='Dragonpet:BAAANQAECgUICQAAAA==.Drunk:BAAANQAECgUIDQAAAA==.',
Du='Durto:BAAANQADCgQIBAAAAA==.',
Ep='Epicchub:BAABNQAECn8XAAIDAAYKYhgacgDGAQADAAYKYhgacgDGAQAAAA==.',
Fa='Faeda:BAAANQADCgUICAAAAA==.Faestaul:BAAANQAECgYICgAAAA==.Fatima:BAAANQAECgIIAQAAAA==.Fatty:BAAANQAECgUIDAABNQAFFAcIEQALAKogAA==.',
Fe='Ferra:BAAANQADCgIIAgAAAA==.',
Fi='Findinnan:BAAANQAECgYIDgAAAA==.',
Fo='Fordringxl:BAAANQAECgMIBwAAAA==.',
Ga='Gametheory:BAAANQAECgYIDQAAAA==.Gathan:BAAANQADCgYIGgAAAA==.Gathatsu:BAAANQADCgYIBgAAAA==.',
Ge='Genge:BAAANQAECgUIDgAAAA==.Gertrex:BAAANQADCgcIEQAAAA==.',
Gh='Ghostclaw:BAAANQABCgMIBAAAAA==.',
Gl='Glennhelen:BAAANQADCgYIAQAAAA==.',
Go='Goatlord:BAAANQAECgYIDQAAAA==.Goatsavior:BAAANQAECgYIDAAAAA==.Goatshield:BAAANQABCgQIBAAAAA==.Goattotem:BAAANQADCgYICwAAAA==.Goblinsrhot:BAAANQADCggIGQAAAA==.',
Gr='Grymauch:BAAANQADCggIFwAAAA==.',
Ha='Hal:BAAANQADCgcIJgAAAA==.Hammertagrid:BAAANQADCggICAAAAA==.Havökush:BAAANQAECgUIEAAAAA==.',
He='Hedge:BAAANQAECggICAAAAA==.Heinaken:BAAANQADCgQIBwAAAA==.',
In='Inebriatus:BAABNQAECn8jAAIIAAcK/SOQBgDgAgAIAAcK/SOQBgDgAgAAAA==.',
Ja='Jambisauce:BAAANQAECgQICQAAAA==.',
Jb='Jblaze:BAAANQAECgMIDgAAAA==.',
Ju='Judyhoppfuta:BAAANQAECggICwAAAA==.',
Ka='Kalzak:BAAANQAECgUIEgAAAA==.Karkan:BAAANQADCgEIAQAAAA==.',
Kh='Khozilla:BAAANQADCgYICgABNQAECgQIDAABAAAAAA==.',
Ko='Kogori:BAAANQADCgcIBwAAAA==.Kovara:BAAANQABCgQIBAAAAA==.',
Kr='Krystaline:BAAANQAECgUIEQAAAA==.',
La='Ladiemacbeth:BAAANQADCgYIAgABNQAECgUIEgABAAAAAA==.',
Le='Leafs:BAAANQAECgUIBQAAAA==.',
Li='Linseeclancy:BAAANQAECggIDQABNQAFFAcIGAAFACQcAA==.',
Ll='Lluvioso:BAABNQAECn8yAAMKAAkKbCTLDgA3AwAKAAkKxyHLDgA3AwAMAAgKjiP9DgAXAwAAAA==.',
Lo='Loaf:BAAANQAECgYICwAAAA==.Loredbd:BAAANQAECgQIDQAAAA==.',
Lu='Lunarbelle:BAAANQADCgYIAgAAAA==.',
Ma='Mageistic:BAAANQAECgQICAAAAA==.Magersand:BAAANQADCgYIBgAAAA==.Malserok:BAAANQADCgEIAQAAAA==.Manidan:BAAANQABCggICQAAAA==.Mariis:BAAANQAECgMIBAAAAA==.',
Me='Merien:BAAANQADCggIHAAAAA==.Meros:BAAANQAECgIIAgAAAA==.',
Mo='Molok:BAAANQADCgYIDgAAAA==.',
Mu='Muertesdemon:BAAANQAECgQIBAAAAA==.',
Na='Natea:BAAANQAECgUIDgAAAA==.',
Ni='Nivom:BAAANQAECgIIAgAAAA==.',
No='Noctislucis:BAAANQADCgMIAwAAAA==.Norinna:BAAANQAECgQIBQABNQAECggIJwANAGwYAA==.Nostrings:BAAANQADCggICQAAAA==.',
Od='Odiousego:BAABNQAECn8yAAIHAAkKixodBAChAgAHAAkKixodBAChAgAAAA==.',
Or='Orangutoon:BAAANQADCgcIEgAAAA==.Orlin:BAAANQAECgQICQAAAA==.',
Pa='Pact:BAAANQADCgMIBAAAAA==.Painless:BAAANQADCggIOwAAAA==.',
Pe='Petag:BAAANQADCgEIAQABNQAECgUICQABAAAAAA==.',
Ph='Phiadra:BAAANQADCgYIAgABNQAECgUIEQABAAAAAA==.Phixit:BAAANQABCgQIBAAAAA==.',
Po='Popeleo:BAAANQADCgUICAAAAA==.Powerwordhug:BAAANQAECgcIDQAAAA==.',
Pr='Proctolodin:BAABNQAECn8ZAAIOAAgKaBKemwDmAQAOAAgKaBKemwDmAQAAAA==.',
Pu='Purplefart:BAAANQAECgQICQAAAA==.',
Qi='Qinki:BAAANQABCgIIAgAAAA==.',
Ql='Qlaryx:BAAANQAECgUIEQAAAA==.',
Qu='Quinner:BAABNQAECn8eAAMPAAcKWxFyGgCfAQAPAAcKWxFyGgCfAQAQAAEKcQE2VQAYAAAAAA==.',
Ra='Rahron:BAAANQABCgIIAgAAAA==.',
Re='Reckzx:BAAANQAECgQIBQAAAA==.Rehgar:BAAANQAECgIIBAAAAA==.Restore:BAAANQADCgYIBgAAAA==.',
Rh='Rhaegonz:BAAANQAECgQIBAAAAA==.',
Ro='Roguettetwo:BAAANQAECgEIAQAAAA==.Rokey:BAAANQADCgQJBAABNQAECggIDgABAAAAAA==.',
['Rá']='Rázer:BAAANQABCgQIAwAAAA==.',
Sa='Savagetitan:BAAANQADCgUIBQAAAA==.',
Se='Seda:BAAANQAECgUIEgAAAA==.Seichan:BAAANQADCgMIAwAAAA==.Seryiana:BAAANQAECgUIDAAAAA==.',
Sh='Shiftysmash:BAAANQADCgcICAABNQAECgQIBQABAAAAAA==.Shnukems:BAAANQADCgcIEgAAAA==.',
Si='Silk:BAAANQADCgcIEwAAAA==.Silren:BAAANQAECgQICgAAAA==.Sita:BAAANQADCgYIAQAAAA==.',
Sn='Snowlord:BAAANQADCgEIAgABNQAECggIGQAOAGgSAA==.',
So='Sorulus:BAAANQAECgQICwAAAA==.Souldance:BAABNQAECn8iAAMRAAkKqBQhXgA6AgARAAkKqBQhXgA6AgACAAEKZQsBeQA0AAAAAA==.',
St='Starryknight:BAAANQAECgYICQABNQAECgkJJQASAEsQAA==.Storvan:BAAANQAECgMIAwAAAA==.',
Su='Surtür:BAAANQAECgYIEQAAAA==.Suyosh:BAAANQABCgIIBAAAAA==.',
Ta='Takhisis:BAEBNQAECn8lAAMKAAgKNx3+NAA2AgAKAAcKoR/+NAA2AgATAAgKHxB/VwCvAQAAAA==.Talie:BAAANQADCgEIAQAAAA==.Tampax:BAAANQAECgUIDwAAAA==.Targ:BAAANQAECgUIDwAAAA==.Targantua:BAAANQADCgYIGAAAAA==.Tastyburgah:BAAANQAECgEIAQAAAA==.',
Te='Tecknologic:BAAANQADCgYIBQAAAA==.Tefnutt:BAAANQAECgMIBwAAAA==.Tenjoshoten:BAAANQAECgYIBwABNQAECggICAABAAAAAA==.',
Th='Thugzug:BAABNQAECn8ZAAIUAAgKKhereQAnAgAUAAgKKhereQAnAgAAAA==.',
Ti='Tillae:BAAANQADCgYIBgAAAA==.Timeless:BAAANQADCgcIEgAAAA==.Titàn:BAAANQABCgIIAgAAAA==.',
To='Torryn:BAAANQADCggIDwAAAA==.',
Tr='Travik:BAAANQADCgYIBgABNQAECggIJwAVAO0kAA==.Treshalth:BAAANQABCgYIBgAAAA==.Tryderrmage:BAAANQADCgMIBAAAAA==.Trydertoo:BAAANQAECgYICgAAAA==.',
Va='Valanya:BAABNQAECn8mAAIJAAkKGhg9EQBmAgAJAAkKGhg9EQBmAgAAAA==.Valonar:BAAANQADCgEIAQAAAA==.Valor:BAAANQADCgcIEwAAAA==.Vardeath:BAAANQAECgQICQAAAA==.',
Ve='Veldaan:BAAANQADCggIKgAAAA==.Velmont:BAAANQADCgYIDAAAAA==.Ventoso:BAABNQAECn8cAAMWAAgKFSPMBgDyAgAWAAcKLCXMBgDyAgAUAAgKNCBxNADtAgAAAA==.',
Vi='Vinskey:BAAANQAECgEIAQAAAA==.Vipe:BAAANQAECgUIDAAAAA==.',
Wa='Warliff:BAAANQABCggICgAAAA==.',
Wh='Whish:BAAANQAECgIIAgAAAA==.Whiteleaf:BAAANQAECgQIBAAAAA==.',
Xo='Xotha:BAAANQAECgQIDQAAAA==.',
Za='Zappomaticus:BAAANQADCgYIDAAAAA==.Zaratren:BAAANQAECgYIEAABNQAECgkJMgAHAIsaAA==.',
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
