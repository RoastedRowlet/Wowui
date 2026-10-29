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

local lookup = {'Evoker-Devastation','Evoker-Preservation','Mage-Frost','Mage-Arcane','Warlock-Destruction','Shaman-Elemental','Monk-Brewmaster','Rogue-Assassination','Monk-Windwalker','Priest-Shadow','Rogue-Subtlety','DemonHunter-Havoc','Warlock-Affliction','Warlock-Demonology','Monk-Mistweaver','DeathKnight-Blood','Unknown-Unknown','Priest-Holy','Hunter-BeastMastery','Paladin-Retribution','Paladin-Holy','Shaman-Restoration','Mage-Fire','Druid-Feral','Rogue-Outlaw','DeathKnight-Frost','Warrior-Fury','DeathKnight-Unholy','Evoker-Augmentation','Warrior-Arms','Paladin-Protection','Warrior-Protection',}
local provider = {region='US',realm='Fenris',name='US',type='weekly',zone=53,date='2026-10-27',data={Ad='Adranelidk:BAAANQAECgQIBwAAAA==.',
Ae='Aeromina:BAAANQADCggICwAAAA==.',
Ah='Ahtabai:BAAANQAECgEIBAAAAA==.',
Aj='Ajkuna:BAAANQAECgIIBgAAAA==.',
Ak='Akthor:BAAANQAECggIAwAAAA==.',
Am='Amadori:BAAANQAECgUICQAAAA==.',
An='Anarchy:BAAANQAECgIIAgAAAA==.Ancalagon:BAABNQAECn8VAAMBAAYK7BSPHACDAQABAAYK7BSPHACDAQACAAQK0hdyMAAZAQAAAA==.Angelic:BAAANQAECgEIAgAAAA==.',
Ap='Appix:BAAANQADCgQIBAAAAA==.',
Ar='Arturius:BAAANQAECgEIAwAAAA==.',
As='Ashtara:BAAANQADCgEIAQAAAA==.',
Au='Aussilicious:BAAANQADCgIIAgABNQAECgUIGAACAKAOAA==.',
Av='Averyed:BAAANQAECgEIBAAAAA==.',
Az='Azerennia:BAABNQAECn8bAAMDAAYK8ggEHAAQAQADAAYK5AgEHAAQAQAEAAUKkgQQ0gCsAAAAAA==.Azerious:BAABNQAECn8iAAIFAAcKmAtDHwB1AQAFAAcKmAtDHwB1AQAAAA==.Azrokke:BAAANQAECgMIBgAAAA==.',
Ba='Babetter:BAAANQAECgYIDgAAAA==.Baelz:BAABNQAECn8dAAIGAAkK4QbekwBzAQAGAAkK4QbekwBzAQAAAA==.Bahamaut:BAAANQAECgIJAwABNQAECgUIGAACAKAOAA==.Ballinacup:BAAANQAECgEIAQAAAA==.Bazroz:BAAANQADCgEJAQAAAA==.',
Be='Beerless:BAABNQAECn8fAAIHAAYKMQdUHgABAQAHAAYKMQdUHgABAQAAAA==.Bencicil:BAAANQAECgQICAAAAA==.Berk:BAAANQADCgMIAwABNQAECgoKJwAIAGYOAA==.',
Bi='Bigbootijudy:BAABNQAECn8WAAIGAAgKPhpQUAA3AgAGAAgKPhpQUAA3AgABNQAFFAcIGAAJACQcAA==.',
Bl='Blackanvil:BAAANQAECgIIAgAAAA==.Blayde:BAAANQADCgQIBAAAAA==.Blowtorch:BAAANQAECgIIAwAAAA==.',
Bo='Bobmb:BAAANQAECgEIAgAAAA==.Botrollsnifr:BAAANQADCgEIAgABNQAECgYIFQAKAPYCAA==.',
Br='Brain:BAAANQAECgEIAQAAAA==.Brothergrog:BAAANQAECgEIAgAAAA==.',
Bu='Bunky:BAABNQAECn8nAAMIAAoKZg4SQwC9AQAIAAoKWwsSQwC9AQALAAMKgBHNZwDBAAAAAA==.Butters:BAAANQAECgUIDgAAAA==.',
Ca='Cair:BAACNQAFFH8PAAIMAAcKYCNgAwBQAgAMAAcKYCNgAwBQAgA1AAQKfzcAAgwACgoGJpIIAHMDAAwACgoGJpIIAHMDAAAA.Camili:BAAANQAECgEIAgAAAA==.',
Ch='Charling:BAAANQAECgQIBQABNQAFFAQICQANAEUKAA==.Chickensnake:BAAANQADCgIIAgAAAA==.Chlonghorn:BAAANQAECgYIEwAAAA==.',
Da='Darrik:BAAANQAECgUIEwAAAA==.David:BAAANQAECgEIAwAAAA==.',
De='Deathshand:BAAANQAECgMIAwAAAA==.Deezdemonz:BAABNQAECn8WAAIOAAYKQhAyjwDRAAAOAAYKQhAyjwDRAAAAAA==.Deezhealz:BAAANQAECgIIAgAAAA==.',
Di='Diddyfisting:BAACNQAFFH8YAAMJAAcKJBx9AgBfAgAJAAcKJBx9AgBfAgAHAAEKAADQCwA1AAA1AAQKfy4ABAkACgotJLcIAEQDAAkACgotJLcIAEQDAA8AAgpJFOQ+AH8AAAcAAgrpCDstAFMAAAAA.Dirtydill:BAAANQAECggIEwAAAA==.Divine:BAAANQAECgEIAQAAAA==.Divinelaw:BAEANQADCgUIBQABNQAECgkJNAAQAOgcAA==.',
Do='Dotchester:BAAANQAECgEIAQAAAA==.Doubleberry:BAAANQADCgYIBgABNQAECgUICgARAAAAAA==.',
Dr='Dragonpet:BAAANQAECgYIDgAAAA==.Drunk:BAABNQAECn8VAAMKAAYK9gKCUwDAAAAKAAYK9gKCUwDAAAASAAQKQwFWrQBoAAAAAA==.',
Du='Durto:BAAANQADCgQICAAAAA==.',
Ed='Eduricos:BAAANQAECgIIAgAAAA==.',
Ep='Epicchub:BAABNQAECn8gAAIGAAcK2BlycwDHAQAGAAcK2BlycwDHAQAAAA==.',
Fa='Faeda:BAAANQADCgUICAAAAA==.Faengrove:BAAANQAECggIEAAAAA==.Faestaul:BAAANQAECgcIEgAAAA==.Fatima:BAAANQAECgIIAgAAAA==.Fatty:BAAANQAECgUIDgABNQAFFAcIFQATANcgAA==.',
Fe='Ferra:BAAANQADCgIIAgAAAA==.',
Fi='Findinnan:BAABNQAECn8XAAIIAAcKzQ13LAC+AAAIAAcKzQ13LAC+AAAAAA==.',
Fo='Fordringxl:BAAANQAECgMICQAAAA==.',
Ga='Gametheory:BAAANQAECgYIDQAAAA==.Gathan:BAAANQADCgYIIAAAAA==.Gathatsu:BAAANQADCgYIBgAAAA==.',
Ge='Genge:BAABNQAECn8cAAMUAAcK5Q0e8AA8AQAUAAYKpA4e8AA8AQAVAAEKARRZvQA+AAAAAA==.Gertrex:BAAANQADCgcIEQAAAA==.',
Gh='Ghostclaw:BAAANQABCgMIBAAAAA==.',
Gl='Glennhelen:BAAANQADCgYIAQAAAA==.',
Go='Goatlord:BAAANQAECgcIEQAAAA==.Goatsavior:BAABNQAECn8WAAIWAAgKbQeaawD7AAAWAAgKbQeaawD7AAAAAA==.Goatshield:BAAANQABCgQIBAAAAA==.Goattotem:BAAANQADCgYICwAAAA==.Goblinsrhot:BAAANQADCggIGQAAAA==.',
Gr='Grymauch:BAAANQAECgEIAQAAAA==.',
Ha='Hal:BAAANQAECgEIAgAAAA==.Half:BAAANQAECgIIBAAAAA==.Hammertagrid:BAAANQADCggICAAAAA==.Havökush:BAABNQAECn8dAAIMAAYKHxsWNwD4AQAMAAYKHxsWNwD4AQAAAA==.',
He='Hedge:BAAANQAECggICAAAAA==.Heinaken:BAAANQADCgQIBwAAAA==.Hesperax:BAAANQAECgEIAQAAAA==.',
In='Inebriatus:BAABNQAECn8vAAIHAAcK/SOdBgDfAgAHAAcK/SOdBgDfAgAAAA==.',
Is='Ismurfurpeak:BAAANQADCggIEgAAAA==.',
Ja='Jambisauce:BAAANQAECgQICgAAAA==.',
Jb='Jblaze:BAABNQAECn8fAAQDAAcKXgX6FgC7AAADAAcKXgX6FgC7AAAEAAMK4gJ9tQFVAAAXAAEK7QGVDwAhAAAAAA==.',
Ju='Judyhoppfuta:BAAANQAFFAIIAgAAAA==.',
Ka='Kalzak:BAABNQAECn8fAAIYAAYKcwd6IQAIAQAYAAYKcwd6IQAIAQAAAA==.Karkan:BAAANQADCgUIAQAAAA==.',
Kh='Khozilla:BAAANQADCgYICgABNQAECggIFgAUAPoHAA==.',
Ko='Kogori:BAAANQADCgcIBwAAAA==.Kovara:BAAANQABCgQIBAAAAA==.',
Kr='Krystaline:BAABNQAECn8eAAIZAAYKawc2EQAAAQAZAAYKawc2EQAAAQAAAA==.',
La='Ladiemacbeth:BAAANQADCgYIAgABNQAECgYIHwAYAHMHAA==.',
Le='Leafs:BAAANQAECgUIDQAAAA==.',
Li='Linseeclancy:BAAANQAECggIDgABNQAFFAcIGAAJACQcAA==.',
Ll='Lluvioso:BAABNQAECn9AAAMQAAoKkiOzBwDYAgAaAAgKjiNoDwAWAwAQAAoK3iGzBwDYAgAAAA==.',
Lo='Loaf:BAABNQAECn8XAAIEAAgKFxorQAD1AQAEAAgKFxorQAD1AQAAAA==.Loredbd:BAAANQAECgQIDwAAAA==.Lorediamslo:BAAANQAECgEIAQAAAA==.',
Lu='Lunarbelle:BAAANQADCgYIAgAAAA==.',
Ly='Lyoni:BAAANQAECgEIAQAAAA==.',
Ma='Mageistic:BAAANQAECgQIDAAAAA==.Magersand:BAAANQADCgYIBgAAAA==.Malserok:BAAANQAECgMIBAAAAA==.Manidan:BAAANQAECgEIAwAAAA==.Mariis:BAAANQAECgMIBQAAAA==.',
Me='Merien:BAAANQAECgEIAQAAAA==.Meros:BAAANQAECgQICgAAAA==.',
Mo='Molok:BAAANQADCgYIDgAAAA==.',
Mu='Muertesdemon:BAAANQAECgQIBgAAAA==.',
Na='Natea:BAAANQAECgUIEQAAAA==.',
Ni='Nivom:BAAANQAECgIIBAAAAA==.',
No='Noctislucis:BAAANQADCgMIAwAAAA==.Norinna:BAAANQAECgYICgABNQAECgoKNAAEADkWAA==.Nostrings:BAAANQADCggICQAAAA==.',
Od='Odiousego:BAACNQAFFH8JAAINAAQKRQr0AADbAAANAAQKRQr0AADbAAA1AAQKfz8AAg0ACgqqGvgBAF4CAA0ACgqqGvgBAF4CAAAA.',
Or='Orangutoon:BAAANQAECgEIAgAAAA==.Orlin:BAAANQAECgUIEAAAAA==.',
Pa='Pact:BAAANQADCgMIBAAAAA==.Painless:BAAANQAECgEIAQAAAA==.',
Pe='Petag:BAAANQADCgEIAQABNQAECgYIDgARAAAAAA==.',
Ph='Phiadra:BAAANQADCgYIAgABNQAECgYIHQATAPILAA==.Phixit:BAAANQABCgQIBAAAAA==.',
Po='Popeleo:BAAANQADCgUICAAAAA==.Powerwordhug:BAAANQAECgcIEgAAAA==.',
Pr='Proctolodin:BAABNQAECn8gAAIUAAgKmBM0ngDmAQAUAAgKmBM0ngDmAQAAAA==.',
Pu='Purplefart:BAAANQAECgQIDgAAAA==.',
Qi='Qinki:BAAANQAECgEIAQAAAA==.',
Ql='Qlaryx:BAABNQAECn8dAAITAAYK8gvYzABnAQATAAYK8gvYzABnAQAAAA==.',
Qu='Quinner:BAABNQAECn8pAAMBAAgKRRLwBwCRAQABAAgKRRLwBwCRAQACAAEKcQFMVgAYAAAAAA==.',
Ra='Rahron:BAAANQABCgIIAgAAAA==.',
Re='Reckzx:BAAANQAECgYICAAAAA==.Rehgar:BAAANQAECgMICgAAAA==.Restore:BAAANQADCgYIBgAAAA==.',
Rh='Rhaegonz:BAAANQAECgQIBAAAAA==.',
Ro='Roguettetwo:BAAANQAECgEIAQAAAA==.Rokey:BAAANQADCgQIBAABNQAECgoKFgAEADgfAA==.',
['Rá']='Rázer:BAAANQAECgEIAQAAAA==.',
Sa='Savagetitan:BAAANQAECgEIAgAAAA==.',
Se='Seda:BAABNQAECn8fAAIbAAYKVRw/DgDNAQAbAAYKVRw/DgDNAQAAAA==.Seichan:BAAANQADCgMIAwAAAA==.Seryiana:BAABNQAECn8UAAIFAAcKNxGVBwD8AAAFAAcKNxGVBwD8AAAAAA==.',
Sh='Shiftysmash:BAAANQADCgcICAABNQAECgQIBQARAAAAAA==.Shnukems:BAAANQAECgEIBAAAAA==.',
Si='Silk:BAAANQAECgUICQAAAA==.Silren:BAABNQAECn8UAAINAAUKBxHPEQAuAQANAAUKBxHPEQAuAQAAAA==.Sincere:BAAANQAECgEIAQAAAA==.Sita:BAAANQADCgYIAQAAAA==.',
Sn='Snowlord:BAAANQADCgEIAgABNQAECggIIAAUAJgTAA==.',
So='Sorulus:BAAANQAECgQIDgAAAA==.Souldance:BAABNQAECn8iAAMOAAkKqBSLXwA5AgAOAAkKqBSLXwA5AgAFAAEKZQuheQA0AAAAAA==.',
St='Starryknight:BAAANQAECgYIDgABNQAECgoKLAASAHoKAA==.Stockdoc:BAAANQAECgEIAQAAAA==.Storvan:BAAANQAECggIEgAAAA==.',
Su='Surtür:BAABNQAECn8gAAMGAAcKSiR1OwCIAgAGAAYKCCV1OwCIAgAWAAIKdxFe/QBwAAAAAA==.Suyosh:BAAANQABCgIIBAAAAA==.',
Ta='Takhisis:BAEBNQAECn80AAQQAAkK6BwrGQDOAQAQAAgK7x4rGQDOAQAcAAgKHxBPWACvAQAaAAMKlge+YgCYAAAAAA==.Talie:BAAANQADCgcIEwAAAA==.Tampax:BAABNQAECn8YAAMCAAUKoA5DGgDaAAACAAUKoA5DGgDaAAAdAAMK5ge5HQB2AAAAAA==.Targ:BAABNQAECn8bAAITAAcKYh5IXQCGAQATAAcKYh5IXQCGAQAAAA==.Targantua:BAAANQAECgEIAQAAAA==.Tastyburgah:BAAANQAECgEIAgAAAA==.',
Te='Tecknologic:BAAANQADCgYIBQAAAA==.Tefnutt:BAAANQAECgQIBwAAAA==.Tenjoshoten:BAAANQAECggIDQAAAA==.',
Th='Thugzug:BAABNQAECn8bAAIeAAgKKhdwewAmAgAeAAgKKhdwewAmAgAAAA==.',
Ti='Tillae:BAAANQADCgYIBgAAAA==.Timeless:BAAANQADCgcIEwAAAA==.Titanmage:BAAANQAECgEIAQAAAA==.Titàn:BAAANQAECgEIAQAAAA==.',
To='Torryn:BAAANQAECgEIAQAAAA==.',
Tr='Travik:BAAANQADCgYIBgABNQAECgoKPAAbAJ0kAA==.Treshalth:BAAANQABCgYIBwAAAA==.Tryderrmage:BAAANQADCgMIBAAAAA==.Trydertoo:BAAANQAECgcICwAAAA==.',
Un='Unstable:BAAANQAECgcIDgABNQAFFAcIDAAfANMbAA==.',
Va='Valanya:BAABNQAECn8mAAIPAAkKGhhxEQBmAgAPAAkKGhhxEQBmAgAAAA==.Valonar:BAAANQADCgEIAQAAAA==.Valor:BAAANQAECgQIBAAAAA==.Vardeath:BAAANQAECgQIDAAAAA==.',
Ve='Veldaan:BAAANQAECgEIAQAAAA==.Velmont:BAAANQAECgEIAgAAAA==.Ventoso:BAABNQAECn8oAAMgAAkKPCXrBgDyAgAgAAgKZCXrBgDyAgAeAAkKPCIiHgB/AgAAAA==.',
Vi='Vinskey:BAAANQAECgEIAwAAAA==.Vipe:BAAANQAECgYIEgAAAA==.',
Wa='Warliff:BAAANQABCggICgAAAA==.',
Wh='Whish:BAAANQAECgIIAgAAAA==.Whiteleaf:BAAANQAECgUICAAAAA==.',
Xo='Xotha:BAAANQAECgQIDQAAAA==.',
Za='Zappomaticus:BAAANQADCgYIDAAAAA==.Zaratren:BAABNQAECn8eAAICAAcKKgyxFwD2AAACAAcKKgyxFwD2AAABNQAFFAQICQANAEUKAA==.',
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
