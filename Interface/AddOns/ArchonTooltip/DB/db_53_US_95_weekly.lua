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

local lookup = {'Evoker-Devastation','Evoker-Preservation','Mage-Frost','Mage-Arcane','Warlock-Destruction','Shaman-Elemental','Monk-Brewmaster','Rogue-Assassination','Monk-Windwalker','Priest-Shadow','Rogue-Subtlety','DemonHunter-Havoc','Warlock-Affliction','Warlock-Demonology','Monk-Mistweaver','Paladin-Retribution','DeathKnight-Blood','Unknown-Unknown','Priest-Holy','Hunter-BeastMastery','Paladin-Holy','Shaman-Restoration','Mage-Fire','Druid-Feral','Rogue-Outlaw','DeathKnight-Frost','Warrior-Fury','Warrior-Arms','DeathKnight-Unholy','Evoker-Augmentation','Paladin-Protection','Warrior-Protection',}
local provider = {region='US',realm='Fenris',name='US',type='weekly',zone=53,date='2026-11-03',data={Ad='Adranelidk:BAAANQAECgQICwAAAA==.',
Ae='Aeromina:BAAANQADCggIDQAAAA==.',
Aj='Ajkuna:BAAANQAECgIIBQAAAA==.',
Ak='Akthor:BAAANQAECggIAgAAAA==.',
Al='Alypiia:BAAANQADCgEIAQAAAA==.',
Am='Amadori:BAAANQAECgUIBQAAAA==.',
An='Anarchy:BAAANQAECgIIAgAAAA==.Ancalagon:BAABNQAECn8aAAMBAAYK7BSPHACDAQABAAYK7BSPHACDAQACAAQK0hdyMAAZAQAAAA==.Angelic:BAAANQAECgEIAQAAAA==.Anubisz:BAAANQADCgQIBAAAAA==.',
Ap='Appix:BAAANQADCgQIBAAAAA==.',
Ar='Arcanasagosa:BAAANQADCgEIAQAAAA==.',
As='Ashtara:BAAANQADCgEIAgAAAA==.Ashå:BAAANQABCgUIBQAAAA==.',
Au='Aussilicious:BAAANQADCgIIAgABNQAECgUIGAACAKAOAA==.',
Av='Averyed:BAAANQAECgQIBAAAAA==.',
Az='Azerennia:BAABNQAECn8bAAMDAAYK8ggEHAAQAQADAAYK5AgEHAAQAQAEAAUKkgRj7gCrAAAAAA==.Azerious:BAABNQAECn8pAAIFAAcKKA0PCgD3AAAFAAcKKA0PCgD3AAAAAA==.Azrokke:BAAANQAECgMIBAAAAA==.',
Ba='Babetter:BAAANQAECgYIDAAAAA==.Baelz:BAABNQAECn8kAAIGAAoK1wYxZgAZAQAGAAoK1wYxZgAZAQAAAA==.Bahamaut:BAAANQAECgIJAgABNQAECgUIGAACAKAOAA==.Ballinacup:BAAANQADCgMIBAAAAA==.Bazroz:BAAANQADCgEJAQAAAA==.',
Be='Beerless:BAABNQAECn8fAAIHAAYKMQdUHgABAQAHAAYKMQdUHgABAQAAAA==.Bencicil:BAAANQAECgQICAAAAA==.Berk:BAAANQADCgMIAwABNQAECgoKKgAIABEPAA==.',
Bi='Bigbootijudy:BAABNQAECn8WAAIGAAgKPhpQUAA3AgAGAAgKPhpQUAA3AgABNQAFFAgIGgAJAAMaAA==.',
Bl='Blayde:BAAANQADCgQIBAAAAA==.Blowtorch:BAAANQAECgIIAgAAAA==.',
Bo='Bonnygreen:BAAANQADCgEIAQAAAA==.Botrollsnifr:BAAANQADCgEIBAABNQAECgYIFQAKAPYCAA==.',
Br='Brain:BAAANQAECgEIAQAAAA==.Brothergrog:BAAANQADCgcIDAAAAA==.',
Bu='Bunky:BAABNQAECn8qAAMIAAoKEQ8SQwC9AQAIAAoKWwsSQwC9AQALAAQKTRGNdgDsAAAAAA==.Butters:BAAANQAECgUICQAAAA==.',
Ca='Cair:BAACNQAFFH8PAAIMAAcKYCNgAwBQAgAMAAcKYCNgAwBQAgA1AAQKf0IAAgwACgpvJowAAIgDAAwACgpvJowAAIgDAAAA.Camili:BAAANQAECgEIAgAAAA==.',
Ch='Charling:BAAANQAECgQIBAABNQAFFAQICwANAK8OAA==.Chickensnake:BAAANQADCgIIAgAAAA==.Chlonghorn:BAAANQAECgYIEwAAAA==.Chokea:BAAANQADCgYIBgAAAA==.',
Da='Darkchain:BAAANQAECgIIAgAAAA==.Darrik:BAAANQAECgYIEAAAAA==.David:BAAANQAECgEIAQAAAA==.',
De='Deezboltz:BAAANQAECgIIAgAAAA==.Deezdemonz:BAABNQAECn8XAAIOAAcKtw2zlQD3AAAOAAcKtw2zlQD3AAAAAA==.Deezhealz:BAAANQAECgIIAgAAAA==.',
Di='Diddyfisting:BAACNQAFFH8aAAMJAAgKAxp9AgBfAgAJAAgKAxp9AgBfAgAHAAEKAADQCwA1AAA1AAQKfy8ABAkACgotJLcIAEQDAAkACgotJLcIAEQDAA8AAgpJFOQ+AH8AAAcAAgrpCDstAFMAAAAA.Dirtydill:BAABNQAECn8XAAIQAAkKkhPbZADLAQAQAAkKkhPbZADLAQABNQAECgkJKQAGAF8fAA==.Divine:BAAANQAECgQIBQAAAA==.Divinegirth:BAEANQAECgEIAQABNQAECgoKSAARAE4gAA==.Divinelaw:BAEANQADCgUIBQABNQAECgoKSAARAE4gAA==.',
Do='Doubleberry:BAAANQADCgYIBgABNQAECgYIDgASAAAAAA==.',
Dr='Dragonpet:BAAANQAECgYICwAAAA==.Drunk:BAABNQAECn8VAAMKAAYK9gKCUwDAAAAKAAYK9gKCUwDAAAATAAQKQwEcxgBoAAAAAA==.',
Du='Durto:BAAANQAECgIIAgAAAA==.',
Ed='Eduricos:BAAANQAECgIIAgAAAA==.',
Ep='Epicchub:BAABNQAECn8pAAIGAAkKXx9NDwDYAgAGAAkKXx9NDwDYAgAAAA==.',
Ev='Eviljoke:BAAANQADCgYIAQAAAA==.',
Fa='Faeda:BAAANQADCgUICQAAAA==.Faengrove:BAAANQAECggIDAAAAA==.Faestaul:BAABNQAECn8ZAAIQAAkKDhI1gQCKAQAQAAkKDhI1gQCKAQAAAA==.Fatima:BAAANQAECgIIAQAAAA==.Fatty:BAAANQAECgUIDAABNQAFFAcIFQAUANcgAA==.',
Fe='Ferra:BAAANQADCgIIAwAAAA==.',
Fi='Findinnan:BAABNQAECn8dAAIIAAgKpg1RJwDnAAAIAAgKpg1RJwDnAAAAAA==.',
Fo='Fordringxl:BAAANQAECgMIBwAAAA==.',
Ga='Gametheory:BAAANQAECgYIDQAAAA==.Gathan:BAAANQADCggILwAAAA==.Gathatsu:BAAANQADCgYIBgAAAA==.',
Ge='Genge:BAABNQAECn8hAAMQAAcKcw4e8AA8AQAQAAYKVg8e8AA8AQAVAAEKARSM1wA8AAAAAA==.Gertrex:BAAANQADCgcIEwAAAA==.',
Gh='Ghostclaw:BAAANQADCgEIAQAAAA==.',
Gl='Glennhelen:BAAANQADCgYIAQAAAA==.',
Go='Goatlord:BAAANQAECgcIDQAAAA==.Goatsavior:BAABNQAECn8YAAIWAAkKcAcZdAAjAQAWAAkKcAcZdAAjAQAAAA==.Goatshield:BAAANQADCgEIAQAAAA==.Goattotem:BAAANQADCgYICwAAAA==.Goblinsrhot:BAAANQADCggIGgAAAA==.',
Gr='Grymauch:BAAANQAECgIIAQAAAA==.',
Ha='Hal:BAAANQADCgcIKQAAAA==.Half:BAAANQAECgIIAwAAAA==.Hammertagrid:BAAANQADCggICAAAAA==.Havökush:BAABNQAECn8hAAIMAAkKXBaqJACpAQAMAAkKXBaqJACpAQAAAA==.',
He='Hedge:BAAANQAECggICAAAAA==.Heinaken:BAAANQADCgQIBwAAAA==.',
In='Inebriatus:BAABNQAECn82AAMHAAkKdyEABABhAgAHAAkKdyEABABhAgAJAAQKYgu6OwCYAAAAAA==.',
Is='Ismurfurpeak:BAAANQADCggIIAAAAA==.',
Ja='Jambisauce:BAAANQAECgQICQAAAA==.',
Jb='Jblaze:BAABNQAECn8oAAQDAAoKygqVDACGAQADAAoKygqVDACGAQAEAAMK4gJ9tQFVAAAXAAEK7QGVDwAhAAAAAA==.',
Ju='Judyhoppfuta:BAAANQAFFAIIAgAAAA==.',
Ka='Kalzak:BAABNQAECn8fAAIYAAYKcwd6IQAIAQAYAAYKcwd6IQAIAQAAAA==.Karkan:BAAANQADCgUIAQAAAA==.',
Kh='Khozilla:BAAANQADCgYICgABNQAECggIFgAQAPoHAA==.',
Ko='Kogori:BAAANQADCgcICQAAAA==.Kovara:BAAANQADCgEIAQAAAA==.',
Kr='Krystaline:BAABNQAECn8eAAIZAAYKawc2EQAAAQAZAAYKawc2EQAAAQAAAA==.',
La='Ladiemacbeth:BAAANQADCgYIAwABNQAECgYIHwAYAHMHAA==.',
Le='Leafs:BAAANQAECgUIEQAAAA==.',
Li='Linseeclancy:BAAANQAECggIDQABNQAFFAgIGgAJAAMaAA==.',
Ll='Lluvioso:BAABNQAECn9GAAMRAAoKPyTXCADrAgAaAAgKjiNoDwAWAwARAAoKjCLXCADrAgAAAA==.',
Lo='Loaf:BAABNQAECn8YAAIEAAkKPBu7NQBNAgAEAAkKPBu7NQBNAgAAAA==.Loredbd:BAAANQAECgQIDQAAAA==.',
Lu='Lunarbelle:BAAANQADCgYIAwAAAA==.',
Ly='Lyoni:BAAANQADCgEIAQAAAA==.',
Ma='Mageistic:BAAANQAECgUIDwAAAA==.Magersand:BAAANQADCgYIBgAAAA==.Malserok:BAAANQAECgUICAAAAA==.Mariis:BAAANQAECgMIBAAAAA==.',
Me='Merien:BAAANQAECgEIAgAAAA==.Meros:BAAANQAECgQIDgAAAA==.',
Mi='Mishaa:BAAANQADCgEIAQAAAA==.',
Mo='Molok:BAAANQADCgYIDgAAAA==.',
Mu='Muertesdemon:BAAANQAECgQIBgAAAA==.',
Na='Narmai:BAAANQADCgMIAwAAAA==.Natea:BAAANQAECgUIDgAAAA==.',
Ni='Nivom:BAAANQAECgIIAgAAAA==.',
No='Noctislucis:BAAANQADCgMIBAAAAA==.Norinna:BAAANQAECggIDAAAAA==.Nostrings:BAAANQADCggICgAAAA==.',
Od='Odiousego:BAACNQAFFH8LAAINAAQKrw4IAgDYAAANAAQKrw4IAgDYAAA1AAQKf0AAAg0ACgrTGiYEAKECAA0ACgrTGiYEAKECAAAA.',
Or='Orangutoon:BAAANQADCgcIFQAAAA==.Orlin:BAAANQAECgUIDgAAAA==.',
Pa='Pact:BAAANQADCgMIBAAAAA==.',
Pe='Petag:BAAANQADCgEIAgABNQAECgYICwASAAAAAA==.',
Ph='Phiadra:BAAANQADCgYIAwABNQAECgYIHQAUAPILAA==.Phixit:BAAANQADCgEIAQAAAA==.',
Pl='Plumpy:BAAANQADCgEIAQAAAA==.',
Po='Popeleo:BAAANQADCgUICAAAAA==.Powerwordhug:BAAANQAECgcIDQAAAA==.',
Pr='Proctolodin:BAABNQAECn8mAAIQAAoKiRQ0ngDmAQAQAAoKiRQ0ngDmAQAAAA==.',
Pu='Purplefart:BAAANQAECgQICQAAAA==.',
Qi='Qinki:BAAANQABCgIIAgAAAA==.',
Ql='Qlaryx:BAABNQAECn8dAAIUAAYK8gvYzABnAQAUAAYK8gvYzABnAQAAAA==.',
Qu='Quinner:BAABNQAECn8wAAMBAAoK/RFTCADRAQABAAoK/RFTCADRAQACAAEKcQFMVgAYAAAAAA==.',
Ra='Rahron:BAAANQADCgEIAQAAAA==.',
Re='Reckzx:BAAANQAECgYIBgAAAA==.Rehgar:BAAANQAECgMIBAAAAA==.Restore:BAAANQADCgYIBgAAAA==.',
Rh='Rhaegonz:BAAANQAECgQIBAAAAA==.',
Ro='Roguettetwo:BAAANQAECgEIAQAAAA==.Rokey:BAAANQADCgQIBAABNQAECgoKFwAEADgfAA==.',
Sa='Savagetitan:BAAANQADCgUIBQAAAA==.',
Se='Seda:BAABNQAECn8fAAIbAAYKVRw/DgDNAQAbAAYKVRw/DgDNAQAAAA==.Seichan:BAAANQADCgMIAwAAAA==.Seryiana:BAABNQAECn8UAAIFAAcKNxEGCgD4AAAFAAcKNxEGCgD4AAAAAA==.',
Sh='Shadowflood:BAAANQADCgEIAQAAAA==.Shiftysmash:BAAANQADCgcICAABNQAECgQIBQASAAAAAA==.Shnukems:BAAANQADCgcIEgAAAA==.',
Si='Silk:BAAANQAECgUIDQAAAA==.Silren:BAABNQAECn8UAAINAAUKBxHPEQAuAQANAAUKBxHPEQAuAQAAAA==.Sincere:BAAANQAECgEIAgAAAA==.Sita:BAAANQADCgYIAgAAAA==.',
Sk='Skytotem:BAAANQADCgEIAQAAAA==.',
Sn='Snowlord:BAAANQAECgQIBAABNQAECgoKJgAQAIkUAA==.',
So='Sorulus:BAAANQAECgQICwAAAA==.Souldance:BAABNQAECn8iAAMOAAkKqBSLXwA5AgAOAAkKqBSLXwA5AgAFAAEKZQuheQA0AAAAAA==.',
St='Starryknight:BAAANQAECgYIDAABNQAECgoKMAAVAJUUAA==.Storvan:BAABNQAECn8UAAIcAAoKawoNawCGAQAcAAoKawoNawCGAQAAAA==.',
Su='Surtür:BAABNQAECn8hAAMGAAgKXiN1OwCIAgAGAAYKCCV1OwCIAgAWAAMKAxWGsgCKAAAAAA==.Suyosh:BAAANQADCgEIAQAAAA==.',
Ta='Takhisis:BAEBNQAECn9IAAQRAAoKTiBsDwCIAgARAAoKTiBsDwCIAgAdAAkKHxBPWACvAQAaAAkK1AmKNgCKAQAAAA==.Talie:BAAANQADCgcIGQAAAA==.Tampax:BAABNQAECn8YAAMCAAUKoA7qHwDYAAACAAUKoA7qHwDYAAAeAAMK5ge5HQB2AAAAAA==.Targ:BAABNQAECn8gAAIUAAcKvh64eACCAQAUAAcKvh64eACCAQAAAA==.Targantua:BAAANQADCgYIHQAAAA==.Tastyburgah:BAAANQAECgEIAQAAAA==.',
Te='Tecknologic:BAAANQADCgYIBQAAAA==.Tefnutt:BAAANQAECgQIBwAAAA==.Tenjoshoten:BAAANQAECggICgAAAA==.',
Th='Throwntotems:BAAANQADCgEIAQAAAA==.Thugzug:BAABNQAECn8fAAIcAAgKKhdwewAmAgAcAAgKKhdwewAmAgAAAA==.',
Ti='Tillae:BAAANQADCgYIBgAAAA==.Timeless:BAAANQADCgcIEwAAAA==.Titàn:BAAANQABCgIIAgAAAA==.',
To='Torryn:BAAANQADCggIEgAAAA==.',
Tr='Travik:BAAANQADCgYIBgABNQAECgoKRAAbALIkAA==.Treshalth:BAAANQADCgEIAQAAAA==.Tryderrmage:BAAANQADCgMIBAAAAA==.Trydertoo:BAAANQAECgcICgAAAA==.',
Un='Unstable:BAAANQAECgcIDQABNQAFFAcIDAAfANMbAA==.',
Va='Valanya:BAABNQAECn8mAAIPAAkKGhhxEQBmAgAPAAkKGhhxEQBmAgAAAA==.Valonar:BAAANQADCgEIAQAAAA==.Valor:BAAANQAECgMIBQAAAA==.Vardeath:BAAANQAECgQICQAAAA==.',
Ve='Veldaan:BAAANQADCggILAAAAA==.Ventoso:BAABNQAECn8uAAMgAAkKPCXrBgDyAgAgAAgKciXrBgDyAgAcAAkKPCJzNQDsAgAAAA==.',
Vi='Vinskey:BAAANQAECgEIAQAAAA==.Vipe:BAAANQAECgYIEAAAAA==.',
Wa='Warliff:BAAANQADCgEIAQAAAA==.',
Wh='Whish:BAAANQAECgMIAwAAAA==.Whiteleaf:BAAANQAECgUIBAAAAA==.',
Xo='Xotha:BAAANQAECgQIDQAAAA==.',
Za='Zappomaticus:BAAANQADCgYIDgAAAA==.Zaratren:BAABNQAECn8iAAICAAgKFQy2GAAsAQACAAgKFQy2GAAsAQABNQAFFAQICwANAK8OAA==.',
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
