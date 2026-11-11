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
local provider = {region='US',realm='Fenris',name='US',type='weekly',zone=53,date='2026-11-10',data={Ad='Adranelidk:BAAANQAECgUIEAAAAA==.',
Ae='Aeromina:BAAANQADCggICwAAAA==.',
Ah='Ahtabai:BAAANQAECgEIBAAAAA==.',
Aj='Ajkuna:BAAANQAECgIIBgAAAA==.',
Ak='Akthor:BAAANQAECggIAgAAAA==.',
Am='Amadori:BAAANQAECgQIDAAAAA==.',
An='Anarchy:BAAANQAECgMIAwAAAA==.Ancalagon:BAABNQAECn8hAAMBAAgKJxFVDgBOAQABAAgKJxFVDgBOAQACAAQK0hdyMAAZAQAAAA==.Angelic:BAAANQAECgEIAgAAAA==.Anubisz:BAAANQADCgQIBAAAAA==.',
Ap='Appix:BAAANQADCgQIBAAAAA==.',
Ar='Arturius:BAAANQAECgEIAwAAAA==.',
As='Ashtara:BAAANQADCgEIAQAAAA==.Ashå:BAAANQAECgEIAQAAAA==.',
Au='Aussilicious:BAAANQADCgIIAgABNQAECgUIGAACAKAOAA==.',
Av='Averyed:BAAANQAECgYICwAAAA==.',
Az='Azerennia:BAABNQAECn8cAAMDAAcKVQgEHAAQAQADAAYK5AgEHAAQAQAEAAYK1QSX5ADRAAAAAA==.Azerious:BAABNQAECn8vAAIFAAkKfg3rBgBWAQAFAAkKfg3rBgBWAQAAAA==.Azrokke:BAAANQAECgMIBgAAAA==.',
Ba='Babetter:BAAANQAECgYIDgAAAA==.Baelz:BAABNQAECn8sAAIGAAoK3QYmYgBIAQAGAAoK3QYmYgBIAQAAAA==.Bahamaut:BAAANQAECgIJAwABNQAECgUIGAACAKAOAA==.Ballinacup:BAAANQADCgMIAwAAAA==.Bazroz:BAAANQADCgEJAQAAAA==.',
Be='Beerless:BAABNQAECn8gAAIHAAcKrQbSFwCjAAAHAAcKrQbSFwCjAAAAAA==.Bencicil:BAAANQAECgQICAAAAA==.Berk:BAAANQADCgMIAwABNQAECgoKKgAIABEPAA==.',
Bi='Bigbootijudy:BAABNQAECn8WAAIGAAgKPhpQUAA3AgAGAAgKPhpQUAA3AgABNQAFFAgIGgAJAAMaAA==.',
Bl='Blayde:BAAANQADCgQIBAAAAA==.Blowtorch:BAAANQAECgIIAwAAAA==.',
Bo='Botrollsnifr:BAAANQADCgEIAgABNQAECgYIFQAKAPYCAA==.',
Br='Brain:BAAANQAECgEIAQAAAA==.Brothergrog:BAAANQAECgEIAQAAAA==.',
Bu='Bunky:BAABNQAECn8qAAMIAAoKEQ8SQwC9AQAIAAoKWwsSQwC9AQALAAQKTRFahAD3AAAAAA==.Butters:BAAANQAECgUIDgAAAA==.',
Ca='Cair:BAACNQAFFH8PAAIMAAcKYCNgAwBQAgAMAAcKYCNgAwBQAgA1AAQKf0YAAgwACgpvJqIAAIoDAAwACgpvJqIAAIoDAAAA.Camili:BAAANQAECgEIAgAAAA==.',
Ch='Charling:BAAANQAECgQIBQABNQAFFAUIDwANAIwPAA==.Chickensnake:BAAANQADCgIIAgAAAA==.Chlonghorn:BAAANQAECgYIEwAAAA==.Chokea:BAAANQADCgYIBgAAAA==.',
Da='Darkchain:BAAANQAECgMIAwAAAA==.Darrik:BAAANQAECgYIEwAAAA==.David:BAAANQAECgEIAwAAAA==.',
De='Deezboltz:BAAANQAECgIIAwAAAA==.Deezdemonz:BAABNQAECn8bAAIOAAcKJg6InwAEAQAOAAcKJg6InwAEAQAAAA==.Deezhealz:BAAANQAECgIIAwAAAA==.',
Di='Diddyfisting:BAACNQAFFH8aAAMJAAgKAxp9AgBfAgAJAAgKAxp9AgBfAgAHAAEKAADQCwA1AAA1AAQKfy8ABAkACgotJLcIAEQDAAkACgotJLcIAEQDAA8AAgpJFOQ+AH8AAAcAAgrpCDstAFMAAAAA.Dirtydill:BAABNQAECn8ZAAIQAAkKkhP+eQDFAQAQAAkKkhP+eQDFAQABNQAECgkJLAAGAOYgAA==.Divine:BAAANQAECgQIBQAAAA==.Divinegirth:BAEANQAECgEIAQABNQAECgoKSwARAJogAA==.Divinelaw:BAEANQADCgUIBQABNQAECgoKSwARAJogAA==.',
Do='Dotchester:BAAANQAECgEIAQAAAA==.Doubleberry:BAAANQADCgYIBgABNQAECgYIDgASAAAAAA==.',
Dr='Dragonpet:BAAANQAECgYIDgAAAA==.Drunk:BAABNQAECn8VAAMKAAYK9gKCUwDAAAAKAAYK9gKCUwDAAAATAAQKQwH/0wBlAAAAAA==.',
Du='Durto:BAAANQAECgIIAgAAAA==.',
Ed='Eduricos:BAAANQAECgYIBwAAAA==.',
Ep='Epicchub:BAABNQAECn8sAAIGAAkK5iBSDQD8AgAGAAkK5iBSDQD8AgAAAA==.',
Fa='Fabeô:BAAANQAECgcICAAAAA==.Faeda:BAAANQADCgUICAAAAA==.Faengrove:BAAANQAECggIDAAAAA==.Faestaul:BAABNQAECn8eAAIQAAkKDhLUkACVAQAQAAkKDhLUkACVAQAAAA==.Fatima:BAAANQAECgIIAgAAAA==.Fatty:BAAANQAECgUIDgABNQAFFAcIFQAUANcgAA==.',
Fe='Ferra:BAAANQADCgIIAgAAAA==.',
Fi='Findinnan:BAABNQAECn8fAAIIAAgK5g0CIQAbAQAIAAgK5g0CIQAbAQAAAA==.',
Fo='Fordringxl:BAAANQAECgMICQAAAA==.',
Ga='Gametheory:BAAANQAECgYIDQAAAA==.Gathan:BAAANQADCggILgAAAA==.Gathatsu:BAAANQADCgYIBgAAAA==.',
Ge='Genge:BAABNQAECn8oAAMQAAgKiwy6xAA0AQAQAAgKiwy6xAA0AQAVAAEKARRt5gA7AAAAAA==.Gertrex:BAAANQADCgcIEQAAAA==.',
Gh='Ghostclaw:BAAANQABCgMIBAAAAA==.',
Gl='Glennhelen:BAAANQADCgYIAQAAAA==.',
Go='Goatlord:BAAANQAECgcIEQAAAA==.Goatsavior:BAABNQAECn8bAAIWAAoK+AcEcQBKAQAWAAoK+AcEcQBKAQAAAA==.Goatshield:BAAANQABCgQIBAAAAA==.Goattotem:BAAANQADCgYICwAAAA==.Goblinsrhot:BAAANQADCggIGQAAAA==.',
Gr='Grymauch:BAAANQAECgQIBAAAAA==.',
Ha='Hal:BAAANQAECgEIAgAAAA==.Half:BAAANQAECgIIAwAAAA==.Hammertagrid:BAAANQADCggICAAAAA==.Havökush:BAABNQAECn8jAAIMAAkKahh5JgDCAQAMAAkKahh5JgDCAQAAAA==.',
He='Hedge:BAAANQAECggICAAAAA==.Heinaken:BAAANQADCgQIBwAAAA==.',
In='Inebriatus:BAABNQAECn86AAMHAAoKaSBAAwCpAgAHAAoKaSBAAwCpAgAJAAQKYgsrQQCWAAAAAA==.',
Is='Ismurfurpeak:BAAANQADCggIIwAAAA==.',
Ja='Jambisauce:BAAANQAECgQICgAAAA==.',
Jb='Jblaze:BAABNQAECn8oAAQDAAoKygr8DgCEAQADAAoKygr8DgCEAQAEAAMK4gJ9tQFVAAAXAAEK7QGVDwAhAAAAAA==.',
Ju='Judyhoppfuta:BAAANQAFFAIIAgAAAA==.',
Ka='Kalzak:BAABNQAECn8gAAIYAAcKywi1IgDOAAAYAAcKywi1IgDOAAAAAA==.Karkan:BAAANQADCgUIAQAAAA==.',
Kh='Khozilla:BAAANQADCgYICgABNQAECggIHQAQAC4IAA==.',
Ko='Kogori:BAAANQADCgcIBwAAAA==.Kovara:BAAANQABCgQIBAAAAA==.',
Kr='Krystaline:BAABNQAECn8fAAIZAAcKkwiPBgDZAAAZAAcKkwiPBgDZAAAAAA==.',
La='Ladiemacbeth:BAAANQADCgYIAgABNQAECgcIIAAYAMsIAA==.',
Le='Leafs:BAAANQAECgUIEQAAAA==.',
Li='Linseeclancy:BAAANQAECggIDgABNQAFFAgIGgAJAAMaAA==.',
Ll='Lluvioso:BAABNQAECn9OAAMRAAoKbCTiBQAjAwARAAoKbCPiBQAjAwAaAAkKlSFoDwAWAwAAAA==.',
Lo='Loaf:BAABNQAECn8YAAIEAAkKPBtZPgBFAgAEAAkKPBtZPgBFAgAAAA==.Loredbd:BAAANQAECgQIDwAAAA==.Lorediamslo:BAAANQAECgEIAQAAAA==.',
Lu='Lunarbelle:BAAANQADCgYIAgAAAA==.',
Ly='Lyoni:BAAANQAECgEIAQAAAA==.',
Ma='Mageistic:BAAANQAECgUIEQAAAA==.Magersand:BAAANQADCgYIBgAAAA==.Malserok:BAAANQAECgUICgAAAA==.Manidan:BAAANQAECgEIAgAAAA==.Mariis:BAAANQAECgMIBQAAAA==.',
Me='Merien:BAAANQAECgIIBAAAAA==.Meros:BAAANQAECgUIEwAAAA==.',
Mo='Molok:BAAANQADCgYIDgAAAA==.',
Mu='Muertesdemon:BAAANQAECgQIBgAAAA==.',
Na='Narmai:BAAANQADCgMIAwAAAA==.Natea:BAAANQAECgUIEQAAAA==.',
Ni='Nivom:BAAANQAECgIIBAAAAA==.',
No='Noctislucis:BAAANQADCgMIAwAAAA==.Norinna:BAAANQAECggIEAABNQAECgoKQQAEAP4YAA==.Nostrings:BAAANQADCggICQAAAA==.',
Od='Odiousego:BAACNQAFFH8PAAINAAUKjA90AQAyAQANAAUKjA90AQAyAQA1AAQKf0EAAg0ACgrTGiYEAKECAA0ACgrTGiYEAKECAAAA.',
Or='Orangutoon:BAAANQAECgEIAgAAAA==.Orlin:BAAANQAECgcIEQAAAA==.',
Pa='Pact:BAAANQADCgMIBAAAAA==.Painless:BAAANQAECgEIAQAAAA==.',
Pe='Petag:BAAANQADCgEIAQABNQAECgYIDgASAAAAAA==.',
Ph='Phiadra:BAAANQADCgYIAgABNQAECgcIHgAUAPQLAA==.Phixit:BAAANQABCgQIBAAAAA==.',
Po='Popeleo:BAAANQADCgUICAAAAA==.Powerwordhug:BAAANQAECgcIEgAAAA==.',
Pr='Proctolodin:BAABNQAECn8nAAIQAAoKzxUFfgC8AQAQAAoKzxUFfgC8AQAAAA==.',
Pu='Purplefart:BAAANQAECgQIDgAAAA==.',
Qi='Qinki:BAAANQAECgEIAQAAAA==.',
Ql='Qlaryx:BAABNQAECn8eAAIUAAcK9AvZvQAbAQAUAAcK9AvZvQAbAQAAAA==.',
Qu='Quinner:BAABNQAECn8wAAMBAAoK/RF0CQDOAQABAAoK/RF0CQDOAQACAAEKcQFMVgAYAAAAAA==.',
Ra='Rahron:BAAANQABCgIIAgAAAA==.',
Re='Reckzx:BAAANQAECgYIBwAAAA==.Rehgar:BAAANQAECgMICAAAAA==.Restore:BAAANQADCgYIBgAAAA==.',
Rh='Rhaegonz:BAAANQAECgQIBAAAAA==.',
Ro='Roguettetwo:BAAANQAECgEIAQAAAA==.Rokey:BAAANQADCgQIBAABNQAECgoKGAAEADgfAA==.',
Sa='Savagetitan:BAAANQAECgEIAgAAAA==.',
Se='Seda:BAABNQAECn8gAAIbAAcKHhw/DgDNAQAbAAcKHhw/DgDNAQAAAA==.Seichan:BAAANQADCgMIAwAAAA==.Seryiana:BAABNQAECn8UAAIFAAcKNxGxCwDyAAAFAAcKNxGxCwDyAAAAAA==.',
Sh='Shiftysmash:BAAANQADCgcICAABNQAECgQIBQASAAAAAA==.Shnukems:BAAANQAECgEIBAAAAA==.',
Si='Silk:BAAANQAECgUIDQAAAA==.Silren:BAABNQAECn8UAAINAAUKBxHPEQAuAQANAAUKBxHPEQAuAQAAAA==.Sincere:BAAANQAECgEIAgAAAA==.Sita:BAAANQADCgYIAQAAAA==.',
Sk='Skytotem:BAAANQADCgEIAQAAAA==.',
Sn='Snowlord:BAAANQAECgUIBgABNQAECgoKJwAQAM8VAA==.',
So='Sorulus:BAAANQAECgQIDgAAAA==.Souldance:BAABNQAECn8qAAMOAAoKHRSLXwA5AgAOAAoKHRSLXwA5AgAFAAMKrA6xHAB1AAAAAA==.',
St='Starryknight:BAAANQAECgYIDAABNQAECgoKNwAVAGkXAA==.Storvan:BAABNQAECn8VAAIcAAoKDQvHdgCKAQAcAAoKDQvHdgCKAQAAAA==.',
Su='Surtür:BAABNQAECn8iAAMGAAkKOSN1OwCIAgAGAAYKCCV1OwCIAgAWAAQKCBSFpwC6AAAAAA==.Suyosh:BAAANQABCgIIBAAAAA==.',
Ta='Takhisis:BAEBNQAECn9LAAQRAAoKmiD6DwCXAgARAAoKmiD6DwCXAgAdAAkKHxBPWACvAQAaAAkK1An8PgCJAQAAAA==.Talie:BAAANQADCgcIGgAAAA==.Tampax:BAABNQAECn8YAAMCAAUKoA42IwDXAAACAAUKoA42IwDXAAAeAAMK5ge5HQB2AAAAAA==.Targ:BAABNQAECn8nAAIUAAgKUR2WZwDcAQAUAAgKUR2WZwDcAQAAAA==.Targantua:BAAANQAECgEIAQAAAA==.Tastyburgah:BAAANQAECgEIAgAAAA==.',
Te='Tecknologic:BAAANQADCgYIBQAAAA==.Tefnutt:BAAANQAECgQIBwAAAA==.Tenjoshoten:BAAANQAECggIDQAAAA==.',
Th='Throwntotems:BAAANQADCgEIAQAAAA==.Thugzug:BAABNQAECn8fAAIcAAgKKhdwewAmAgAcAAgKKhdwewAmAgAAAA==.',
Ti='Tillae:BAAANQADCgYIBgAAAA==.Timeless:BAAANQADCgcIEwAAAA==.Titanmage:BAAANQAECgEIAQAAAA==.Titàn:BAAANQAECgEIAQAAAA==.',
To='Torryn:BAAANQAECgEIAQAAAA==.',
Tr='Travik:BAAANQADCgYIBgABNQAFFAIIBQAbACsbAA==.Treshalth:BAAANQABCgYIBwAAAA==.Tryderrmage:BAAANQADCgMIBAAAAA==.Trydertoo:BAAANQAECgcICwAAAA==.',
Un='Unstable:BAAANQAECgcIDQABNQAFFAgIDgAfAFIdAA==.',
Va='Valanya:BAABNQAECn8mAAIPAAkKGhhxEQBmAgAPAAkKGhhxEQBmAgAAAA==.Valonar:BAAANQADCgEIAQAAAA==.Valor:BAAANQAECgMIBQAAAA==.Vardeath:BAAANQAECgQIDAAAAA==.',
Ve='Veldaan:BAAANQAECgEIAQAAAA==.Velmont:BAAANQAECgEIAQAAAA==.Ventoso:BAABNQAECn80AAMcAAkKPCXLGADfAgAgAAgKciXrBgDyAgAcAAkKrCLLGADfAgAAAA==.',
Vi='Vinskey:BAAANQAECgEIAwAAAA==.Vipe:BAAANQAECgYIEgAAAA==.Viperlock:BAAANQADCgUIBQAAAA==.',
Wa='Warliff:BAAANQABCggICgAAAA==.',
Wh='Whish:BAAANQAECggIDAAAAA==.Whiteleaf:BAAANQAECgcICgAAAA==.',
Xo='Xotha:BAAANQAECgQIDQAAAA==.',
Za='Zappomaticus:BAAANQADCgYIDAAAAA==.Zaratren:BAABNQAECn8oAAICAAkKyg/5EgCyAQACAAkKyg/5EgCyAQABNQAFFAUIDwANAIwPAA==.',
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
