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

local lookup = {'DeathKnight-Blood','Evoker-Preservation','Evoker-Devastation','Mage-Frost','Mage-Arcane','Warlock-Destruction','Shaman-Elemental','Monk-Brewmaster','Rogue-Assassination','Monk-Windwalker','Priest-Shadow','Rogue-Subtlety','DemonHunter-Havoc','Warlock-Affliction','Warlock-Demonology','Monk-Mistweaver','Paladin-Retribution','Unknown-Unknown','Priest-Holy','Hunter-BeastMastery','Paladin-Holy','Shaman-Restoration','Mage-Fire','Druid-Feral','Rogue-Outlaw','DeathKnight-Frost','Warrior-Fury','Warrior-Protection','Warrior-Arms','DeathKnight-Unholy','Evoker-Augmentation','Paladin-Protection',}
local provider = {region='US',realm='Fenris',name='US',type='weekly',zone=53,date='2026-11-17',data={Ad='Adranelidk:BAABNQAECn8UAAIBAAUKGQqFZQCzAAABAAUKGQqFZQCzAAAAAA==.',
Ae='Aeromina:BAAANQAECgYIBgAAAA==.',
Aj='Ajkuna:BAAANQAECgIIBQAAAA==.',
Ak='Akthor:BAAANQAECggIAgAAAA==.',
Am='Amadori:BAAANQAECgQICAAAAA==.',
An='Anarchy:BAAANQAECgMIAwAAAA==.Ancalagon:BAABNQAECn8pAAMCAAkKCBc7EAAEAgACAAkKCBc7EAAEAgADAAgKJxFUDwBNAQAAAA==.Angelic:BAAANQAECgEIAQAAAA==.Anubisz:BAAANQADCgQIBAAAAA==.',
Ap='Appix:BAAANQADCgQIBAAAAA==.',
As='Ashtara:BAAANQADCgEIAQAAAA==.Ashå:BAAANQAECgIIAgAAAA==.',
Au='Aussilicious:BAAANQADCgIIAgABNQAECgUIGAACAKAOAA==.',
Av='Averyed:BAAANQAECggIDgAAAA==.',
Az='Azerennia:BAABNQAECn8hAAMEAAgK/wcEHAAQAQAEAAYK5AgEHAAQAQAFAAcKXwV70wADAQAAAA==.Azerious:BAABNQAECn8xAAIGAAoKjg0mBgCFAQAGAAoKjg0mBgCFAQAAAA==.Azrokke:BAAANQAECgMIBAAAAA==.Azrâ:BAAANQADCgMIAwAAAA==.',
Ba='Babetter:BAAANQAECgYIDAAAAA==.Baelz:BAABNQAECn8yAAIHAAoKGQcPZgBVAQAHAAoKGQcPZgBVAQAAAA==.Bahamaut:BAAANQAECgIJAgABNQAECgUIGAACAKAOAA==.Ballinacup:BAAANQADCgMIAwAAAA==.Bazroz:BAAANQADCgEJAQAAAA==.',
Be='Beerless:BAABNQAECn8lAAIIAAgKjwc9FADhAAAIAAgKjwc9FADhAAAAAA==.Bencicil:BAAANQAECgQICAAAAA==.Berk:BAAANQADCgMIAwABNQAECgoKKgAJABEPAA==.',
Bi='Bigbootijudy:BAABNQAECn8WAAIHAAgKPhpQUAA3AgAHAAgKPhpQUAA3AgABNQAFFAgIGgAKAAMaAA==.',
Bl='Blayde:BAAANQADCgQIBAAAAA==.Blowtorch:BAAANQAECgIIAgAAAA==.',
Bo='Botrollsnifr:BAAANQADCgEIAgABNQAECgYIFQALAPYCAA==.',
Br='Brain:BAAANQAECgEIAQAAAA==.Brothergrog:BAAANQADCgcIFAAAAA==.',
Bu='Bunky:BAABNQAECn8qAAMJAAoKEQ8SQwC9AQAJAAoKWwsSQwC9AQAMAAQKTRG6jwD3AAAAAA==.Butters:BAAANQAECgUICQAAAA==.',
Ca='Cair:BAACNQAFFH8PAAINAAcKYCNgAwBQAgANAAcKYCNgAwBQAgA1AAQKf0kAAg0ACgpvJssAAIkDAA0ACgpvJssAAIkDAAAA.Camili:BAAANQAECgEIAgAAAA==.',
Ch='Charling:BAAANQAECgQIBAABNQAFFAUIEAAOAIwPAA==.Chickensnake:BAAANQADCgIIAgAAAA==.Chlonghorn:BAAANQAECgYIEwAAAA==.Chokea:BAAANQADCgYIBgAAAA==.',
Da='Darkchain:BAAANQAECgQIBgAAAA==.Darrik:BAAANQAECgYIEAAAAA==.David:BAAANQAECgEIAQAAAA==.',
De='Deezboltz:BAAANQAECgIIAgAAAA==.Deezdemonz:BAABNQAECn8eAAIPAAgK8Q2AkAA6AQAPAAgK8Q2AkAA6AQAAAA==.Deezhealz:BAAANQAECgIIAgAAAA==.',
Di='Diddyfisting:BAACNQAFFH8aAAMKAAgKAxp9AgBfAgAKAAgKAxp9AgBfAgAIAAEKAADQCwA1AAA1AAQKfy8ABAoACgotJLcIAEQDAAoACgotJLcIAEQDABAAAgpJFOQ+AH8AAAgAAgrpCDstAFMAAAAA.Dirtydill:BAABNQAECn8cAAIRAAkKeBaQYwALAgARAAkKeBaQYwALAgABNQAECgkJLAAHAOYgAA==.Divine:BAAANQAECgQIBQAAAA==.Divinegirth:BAEANQAECgEIAQABNQAECgoKSwABAJogAA==.Divinelaw:BAEANQADCgUIBQABNQAECgoKSwABAJogAA==.',
Do='Doubleberry:BAAANQADCgYIBgABNQAECgYIBgASAAAAAA==.',
Dr='Dragonpet:BAAANQAECgcIEAAAAA==.Drunk:BAABNQAECn8VAAMLAAYK9gKCUwDAAAALAAYK9gKCUwDAAAATAAQKQwHt3QBjAAAAAA==.',
Du='Durto:BAAANQAECgIIAgAAAA==.',
Ed='Eduricos:BAAANQAECgYIDAAAAA==.',
Ep='Epicchub:BAABNQAECn8sAAIHAAkK5iCkDgD4AgAHAAkK5iCkDgD4AgAAAA==.',
Fa='Fabeô:BAABNQAECn8eAAMLAAoKtQpzHACxAQALAAoKtQpzHACxAQATAAIK+QJN6wBCAAAAAA==.Faeda:BAAANQADCgUICAAAAA==.Faengrove:BAAANQAECggIDAAAAA==.Faestaul:BAABNQAECn8eAAIRAAkKDhJfngCQAQARAAkKDhJfngCQAQAAAA==.Fatima:BAAANQAECgMIAQAAAA==.Fatty:BAAANQAECgUIDAABNQAFFAcIFQAUANcgAA==.',
Fe='Ferra:BAAANQADCgIIAgAAAA==.',
Fi='Findinnan:BAABNQAECn8gAAIJAAgKOA5MIgAaAQAJAAgKOA5MIgAaAQAAAA==.',
Fo='Fordringxl:BAAANQAECgMIBwAAAA==.',
Ga='Gametheory:BAAANQAECgYIDQAAAA==.Gathan:BAAANQADCggILgAAAA==.Gathatsu:BAAANQADCgYIBgAAAA==.',
Ge='Genge:BAABNQAECn8wAAMRAAkKwA1zxABLAQARAAgKwg1zxABLAQAVAAIKkQ221QBqAAAAAA==.Gertrex:BAAANQADCgcIEQAAAA==.',
Gh='Ghostclaw:BAAANQABCgMIBAAAAA==.',
Gl='Glennhelen:BAAANQADCgYIAQAAAA==.',
Go='Goatlord:BAAANQAECgcIDQAAAA==.Goatsavior:BAABNQAECn8bAAIWAAoK+AeHeQBGAQAWAAoK+AeHeQBGAQAAAA==.Goatshield:BAAANQABCgQIBAAAAA==.Goattotem:BAAANQADCgYICwAAAA==.Goblinsrhot:BAAANQADCggIGQAAAA==.',
Gr='Grymauch:BAAANQAECgYICwAAAA==.',
Ha='Hal:BAAANQADCgcIJgAAAA==.Half:BAAANQAECgMIAwAAAA==.Hammertagrid:BAAANQADCggICAAAAA==.Havökush:BAABNQAECn8lAAINAAkK+hkHJgDbAQANAAkK+hkHJgDbAQAAAA==.',
He='Hedge:BAAANQAECggICAAAAA==.Heinaken:BAAANQADCgQIBwAAAA==.',
In='Inebriatus:BAABNQAECn86AAMIAAoKaSCWAwCpAgAIAAoKaSCWAwCpAgAKAAQKYgsbRQCWAAAAAA==.',
Is='Ismurfurpeak:BAAANQAECgMIBAAAAA==.',
Ja='Jambisauce:BAAANQAECgQICQAAAA==.',
Jb='Jblaze:BAABNQAECn8oAAQEAAoKygrPEACCAQAEAAoKygrPEACCAQAFAAMK4gJ9tQFVAAAXAAEK7QGVDwAhAAAAAA==.',
Ju='Judyhoppfuta:BAAANQAFFAIIAgAAAA==.',
Ka='Kalzak:BAABNQAECn8lAAIYAAgKQgqcHwAHAQAYAAgKQgqcHwAHAQAAAA==.',
Kh='Khozilla:BAAANQADCgYICgABNQAECgkJIAARAEsIAA==.',
Ko='Kogori:BAAANQADCgcIBwAAAA==.Kovara:BAAANQABCgQIBAAAAA==.',
Kr='Krystaline:BAABNQAECn8kAAIZAAgK8Al/BQAhAQAZAAgK8Al/BQAhAQAAAA==.',
La='Ladiemacbeth:BAAANQADCgYIAgABNQAECggIJQAYAEIKAA==.',
Le='Leafs:BAAANQAECgUIEQAAAA==.',
Li='Linseeclancy:BAAANQAECggIDQABNQAFFAgIGgAKAAMaAA==.',
Ll='Lluvioso:BAABNQAECn9UAAMBAAoKgCRLBgAhAwABAAoKdSNLBgAhAwAaAAkKqSJoDwAWAwAAAA==.',
Lo='Loaf:BAABNQAECn8YAAIFAAkKPBvvQwBBAgAFAAkKPBvvQwBBAgAAAA==.Loredbd:BAAANQAECgQIDQAAAA==.',
Lu='Lunarbelle:BAAANQADCgYIAgAAAA==.',
Ma='Mageistic:BAABNQAECn8YAAIEAAgKigkmGgAMAQAEAAgKigkmGgAMAQAAAA==.Magersand:BAAANQADCgYIBgAAAA==.Malserok:BAAANQAECgUICgAAAA==.Manidan:BAAANQABCggICQAAAA==.Mariis:BAAANQAECgMIBAAAAA==.',
Me='Merien:BAAANQAECgMIBwAAAA==.Meros:BAABNQAECn8ZAAIUAAYKDAfu5gDiAAAUAAYKDAfu5gDiAAAAAA==.',
Mo='Molok:BAAANQADCgYIDgAAAA==.',
Mu='Muertesdemon:BAAANQAECgQIBgAAAA==.',
Na='Narmai:BAAANQADCgMIAwAAAA==.Natea:BAAANQAECgUIDgAAAA==.',
Ni='Nivom:BAAANQAECgIIAgAAAA==.',
No='Noctislucis:BAAANQADCgMIAwAAAA==.Norinna:BAABNQAECn8ZAAIFAAoKxhCnXAAAAgAFAAoKxhCnXAAAAgABNQAECgoKQQAFAP4YAA==.Nostrings:BAAANQADCggICQAAAA==.',
Od='Odiousego:BAACNQAFFH8QAAIOAAUKjA/5AQAqAQAOAAUKjA/5AQAqAQA1AAQKf0oAAg4ACgpuHJYDAHkCAA4ACgpuHJYDAHkCAAAA.',
Or='Orangutoon:BAAANQADCgcIEgAAAA==.Orlin:BAAANQAECgcIEAAAAA==.',
Pa='Pact:BAAANQADCgMIBAAAAA==.',
Pe='Petag:BAAANQADCgEIAQABNQAECgcIEAASAAAAAA==.',
Ph='Phiadra:BAAANQADCgYIAgABNQAECggIIwAUAJANAA==.Phixit:BAAANQABCgQIBAAAAA==.',
Po='Popeleo:BAAANQADCgUICAAAAA==.Powerwordhug:BAAANQAECgcIDQAAAA==.',
Pr='Proctolodin:BAABNQAECn8nAAIRAAoKzxU4iwC1AQARAAoKzxU4iwC1AQAAAA==.',
Pu='Purplefart:BAAANQAECgQICQAAAA==.',
Qi='Qinki:BAAANQABCgIIAgAAAA==.',
Ql='Qlaryx:BAABNQAECn8jAAIUAAgKkA3CoAByAQAUAAgKkA3CoAByAQAAAA==.',
Qu='Quinner:BAABNQAECn8wAAMDAAoK/REsCgDNAQADAAoK/REsCgDNAQACAAEKcQFMVgAYAAAAAA==.',
Ra='Rahron:BAAANQABCgIIAgAAAA==.',
Re='Reckzx:BAAANQAECgYIBgAAAA==.Rehgar:BAAANQAECgMIBAAAAA==.Restore:BAAANQADCgYIBgAAAA==.',
Rh='Rhaegonz:BAAANQAECgQIBAAAAA==.',
Ro='Roguettetwo:BAAANQAECgEIAQAAAA==.Rokey:BAAANQADCgQIBAABNQAECgoKGQAFADgfAA==.',
Sa='Savagetitan:BAAANQADCgUIBQAAAA==.',
Se='Seda:BAABNQAECn8lAAMbAAgKIhwJDQCyAQAbAAgKIhwJDQCyAQAcAAEKiRXxPwBBAAAAAA==.Seichan:BAAANQADCgMIAwAAAA==.Seryiana:BAABNQAECn8UAAIGAAcKNxH+DADvAAAGAAcKNxH+DADvAAAAAA==.',
Sh='Shiftysmash:BAAANQADCgcICAABNQAECgQIBQASAAAAAA==.Shnukems:BAAANQADCgcIEgAAAA==.',
Si='Silk:BAAANQAECgYIEQAAAA==.Silren:BAABNQAECn8XAAIOAAcKJA3PEQAuAQAOAAcKJA3PEQAuAQAAAA==.Sincere:BAAANQAECgEIAgAAAA==.Sita:BAAANQADCgYIAQAAAA==.',
Sk='Skytotem:BAAANQADCgEIAQAAAA==.',
Sn='Snowlord:BAAANQAECgYICQABNQAECgoKJwARAM8VAA==.',
So='Sorulus:BAAANQAECgQICwAAAA==.Souldance:BAABNQAECn8qAAMPAAoKHRSLXwA5AgAPAAoKHRSLXwA5AgAGAAMKrA7IHgB0AAAAAA==.',
St='Starryknight:BAAANQAECgYIDAABNQAECgoKPQAVAGkXAA==.Storvan:BAABNQAECn8VAAIdAAoKDQsHgACIAQAdAAoKDQsHgACIAQAAAA==.',
Su='Surtür:BAABNQAECn8jAAMHAAkKhSN1OwCIAgAHAAcKtCR1OwCIAgAWAAQKCBSAsAC6AAAAAA==.Suyosh:BAAANQABCgIIBAAAAA==.',
Ta='Takhisis:BAEBNQAECn9LAAQBAAoKmiBdEQCOAgABAAoKmiBdEQCOAgAeAAkKHxBPWACvAQAaAAkK1AlERQCFAQAAAA==.Talie:BAAANQADCgcIHwAAAA==.Tampax:BAABNQAECn8YAAMCAAUKoA6cJQDVAAACAAUKoA6cJQDVAAAfAAMK5ge5HQB2AAAAAA==.Tanjee:BAAANQAECgMIAwAAAA==.Targ:BAABNQAECn8vAAIUAAkKcxy6UAArAgAUAAkKcxy6UAArAgAAAA==.Targantua:BAAANQADCgYIGAAAAA==.Tastyburgah:BAAANQAECgEIAQAAAA==.',
Te='Tecknologic:BAAANQADCgYIBQAAAA==.Tefnutt:BAAANQAECgQIBwAAAA==.Tenjoshoten:BAAANQAECggICgABNQAECgoKNAAYAHQjAA==.',
Th='Throwntotems:BAAANQADCgEIAQAAAA==.Thugzug:BAABNQAECn8fAAIdAAgKKhdwewAmAgAdAAgKKhdwewAmAgAAAA==.',
Ti='Tillae:BAAANQADCgYIBgAAAA==.Timeless:BAAANQADCgcIEwAAAA==.Titàn:BAAANQABCgIIAgAAAA==.',
To='Torryn:BAAANQADCggIDwAAAA==.',
Tr='Travik:BAAANQADCgYIBgABNQAFFAIIBgAbAJgbAA==.Treshalth:BAAANQABCgYIBwAAAA==.Tryderrmage:BAAANQADCgMIBAAAAA==.Trydertoo:BAAANQAECgcICgAAAA==.',
Un='Unstable:BAAANQAECgcIDQABNQAFFAgIDgAgAFIdAA==.',
Va='Valanya:BAABNQAECn8mAAIQAAkKGhhxEQBmAgAQAAkKGhhxEQBmAgAAAA==.Valonar:BAAANQADCgEIAQAAAA==.Valor:BAAANQAECgMIBQAAAA==.Vardeath:BAAANQAECgQICQAAAA==.',
Ve='Veldaan:BAAANQADCggIKgAAAA==.Ventoso:BAABNQAECn88AAMdAAkKPCVZDwAcAwAdAAkK7iJZDwAcAwAcAAgKciXrBgDyAgAAAA==.',
Vi='Vinskey:BAAANQAECgEIAQAAAA==.Vipe:BAAANQAECgYIEAAAAA==.Viperlock:BAAANQADCgUIBQAAAA==.',
Wa='Warliff:BAAANQABCggICgAAAA==.',
Wh='Whish:BAAANQAECggIDAAAAA==.Whiteleaf:BAAANQAECgcICgAAAA==.',
Xo='Xotha:BAAANQAECgQIDQAAAA==.',
Za='Zappomaticus:BAAANQADCgYIDAAAAA==.Zaratren:BAABNQAECn8qAAICAAkKyg95FACwAQACAAkKyg95FACwAQABNQAFFAUIEAAOAIwPAA==.',
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
