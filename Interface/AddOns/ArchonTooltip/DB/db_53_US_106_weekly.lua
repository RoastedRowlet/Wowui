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

local lookup = {'Hunter-Marksmanship','Hunter-BeastMastery','Paladin-Holy','Monk-Brewmaster','Unknown-Unknown','Rogue-Assassination','Evoker-Preservation','DeathKnight-Unholy','Priest-Holy','Warrior-Arms','Warrior-Fury','DeathKnight-Blood','DemonHunter-Devourer','DemonHunter-Havoc','Rogue-Subtlety','Monk-Windwalker','Warlock-Destruction','Warlock-Demonology','Mage-Arcane','Shaman-Enhancement','Warrior-Protection','Priest-Shadow','Paladin-Retribution',}
local provider = {region='US',realm='Ghostlands',name='US',type='weekly',zone=53,date='2026-09-08',data={Af='Aft:BAAANQAECggIEAAAAA==.',
Ai='Aislin:BAAANQADCgEIAQAAAQ==.',
Ak='Akumu:BAAANQAECgUIBQAAAA==.',
Al='Alarkin:BAABNQAECoEWAAMBAAkJuRXQEQAtAgABAAgJZxLQEQAtAgACAAYJjxWbOACoAQAAAA==.Alasmira:BAAANQADCggIEAAAAA==.Alcarde:BAAANQAECgYIBgAAAA==.Aldoan:BAAANQADCgYIEAAAAA==.Aleza:BAAANQADCgEIAQAAAA==.Alialeman:BAAANQADCgIIAgAAAA==.Alistiri:BAAANQAECgIIAgAAAA==.Alix:BAAANQADCgcIEQAAAA==.Allforge:BAAANQAECgIIAgAAAA==.Almina:BAAANQAECgEIAQAAAA==.Alpal:BAABNQAECoEXAAIDAAkJ3RiZCgDkAgADAAkJ3RiZCgDkAgAAAA==.',
Am='Ambs:BAAANQAECgIIAwAAAA==.',
An='Andalya:BAAANQAECgEIAQAAAA==.Angharrad:BAAANQADCgIIAgAAAA==.',
Ao='Aonani:BAAANQADCgcIBwAAAA==.',
Ap='Aprix:BAAANQAECgQIBgAAAA==.',
Ar='Aralyn:BAAANQADCgUIBQAAAA==.Arejay:BAAANQAECgEIAQAAAA==.Argeth:BAAANQADCgYIBgAAAA==.Arshika:BAAANQAECgUIBgAAAA==.Artek:BAAANQADCgMIAwAAAA==.Arthan:BAAANQADCgYIBwAAAA==.Arthonix:BAAANQADCggIDAAAAA==.Arthurleywin:BAAANQAECgQIBgAAAA==.Arvis:BAAANQADCgYIDQAAAA==.',
As='Asamia:BAABNQAECoEZAAIEAAkJrCEWAQBqAwAEAAkJrCEWAQBqAwAAAA==.Ashaki:BAAANQAECgIIAgAAAA==.Astå:BAAANQADCggICAAAAA==.',
At='Athyná:BAAANQADCgIIAgAAAA==.',
Au='Auroramoon:BAAANQADCggIFQAAAA==.',
Av='Avana:BAAANQADCgIIAgAAAA==.',
Aw='Awake:BAAANQAECgYICAAAAA==.',
Ax='Axionar:BAAANQAECgMIBAAAAA==.',
Az='Azshauria:BAAANQABCgQIBAAAAA==.Azurend:BAAANQAECgIIAgAAAA==.Azázél:BAAANQADCgYICgAAAA==.',
Ba='Badtimeboy:BAAANQAECgEIAQAAAA==.Baffle:BAAANQADCgYIEQABNQAECgMIBQAFAAAAAA==.Bahula:BAAANQAECgMIAwAAAA==.Bainehuln:BAAANQADCggIFwAAAA==.Bastianos:BAAANQAECgEIAQAAAA==.Batsom:BAAANQABCgEIAQAAAA==.',
Be='Bellapearl:BAAANQADCggIBgAAAA==.Bellmont:BAAANQADCggIDAAAAA==.Bernes:BAAANQAECgcIDwAAAA==.',
Bi='Bigteef:BAAANQADCgUICQAAAA==.Birdhouse:BAAANQADCggIEwAAAA==.',
Bl='Blackthornn:BAABNQAECoEXAAIGAAkJcx01AwANAwAGAAkJcx01AwANAwAAAA==.Blastin:BAAANQADCgIIAgAAAA==.Blastofel:BAAANQADCgUIBQAAAA==.Bloodreign:BAAANQADCgYIBgAAAA==.Blottzilla:BAABNQAECoEXAAIHAAkJ8RQ0CACIAgAHAAkJ8RQ0CACIAgAAAA==.Bluestreak:BAAANQABCgIIAgAAAA==.',
Bo='Bobbyray:BAAANQADCggIDAAAAA==.Bobertbigg:BAAANQAECgYICAAAAA==.Bowbuttkick:BAAANQAFFAEIAQAAAA==.Boxiebrown:BAAANQAECggIEwAAAA==.',
Br='Bralae:BAAANQADCggIDwAAAA==.Breaya:BAAANQADCgIIAgAAAA==.Brewskiez:BAAANQADCgYIBQAAAA==.Bricktop:BAAANQADCgIIAgAAAA==.Brokuo:BAABNQAECoEXAAIIAAkJxiOwAwB/AwAIAAkJxiOwAwB/AwAAAA==.Broon:BAAANQADCgQIBwAAAA==.Brucellosis:BAAANQAECgQIBAAAAA==.',
Bu='Bubbawoodkin:BAAANQADCgcIBwAAAA==.Buffpres:BAAANQADCgUIBQABNQAECgEIAgAFAAAAAA==.Buzzlez:BAABNQAECoEXAAIJAAkJyxCIFgBBAgAJAAkJyxCIFgBBAgAAAA==.',
Ca='Candyquartz:BAAANQADCgMIAwAAAA==.Carkleaschah:BAAANQADCgYIBwABNQAECgQIBAAFAAAAAA==.Cat:BAAANQABCgIIAgAAAA==.',
Ch='Chaddrique:BAAANQABCgQIBgAAAA==.Chadgolas:BAAANQADCgIIAgAAAA==.Chadimir:BAAANQAECgQIBAAAAA==.Chahae:BAABNQAECoEdAAIIAAgJWyTNBQBQAwAIAAgJWyTNBQBQAwAAAA==.Cheerwine:BAAANQAECgUIBwAAAA==.Cheezits:BAAANQADCgUIBQAAAA==.',
Cl='Clapdo:BAEBNQAECoEXAAMKAAkJuyCcCwA/AwAKAAkJuyCcCwA/AwALAAEJNRuIEgBQAAAAAA==.Clinician:BAAANQADCggIEAAAAA==.',
Co='Commandor:BAAANQADCgEIAQAAAA==.Congolense:BAAANQAECgUIBQAAAA==.Corbzz:BAAANQADCgMIAwAAAA==.Cowacusrex:BAAANQADCgUIBQAAAA==.',
Cp='Cptrisky:BAAANQABCgIIAgAAAA==.',
Cr='Crazzenburns:BAAANQAECgEIAQABNQAECgYICwAFAAAAAA==.Creamer:BAAANQAECgQIBQAAAA==.Crunchin:BAAANQAECgcIEgAAAA==.',
Cu='Cutedwarfxd:BAABNQAECoEXAAIMAAkJOiXkAADUAwAMAAkJOiXkAADUAwAAAA==.',
Da='Dakkadakka:BAAANQADCgUIBQAAAA==.Danìel:BAABNQAECoEXAAMNAAkJ/BQiEwA7AgANAAgJvRUiEwA7AgAOAAIJzRP+KwCQAAAAAA==.Darkarts:BAAANQADCgIIAgAAAA==.Dartwo:BAAANQADCgcICgAAAA==.',
De='Deathspoons:BAABNQAECoEYAAIMAAkJuBLQEwBFAgAMAAkJuBLQEwBFAgAAAA==.Delecto:BAAANQADCgYICgAAAA==.Delushoni:BAAANQADCgUIBQAAAA==.Dendalaus:BAABNQAECoEVAAMPAAkJOSG8BwCkAgAPAAcJkyK8BwCkAgAGAAQJUB1vEwBjAQAAAA==.Derkamental:BAAANQAECgIIAgAAAA==.',
Di='Digallo:BAAANQADCggICwAAAA==.Dimsumbun:BAAANQADCggIEwAAAA==.Dingledorf:BAAANQAECgQIBAAAAA==.Dinoxeye:BAAANQAECgQIBAAAAA==.',
Do='Donut:BAAANQADCgMIAwAAAA==.',
Dr='Dragonpandas:BAAANQADCggICAABNQAECgcIEwAFAAAAAA==.Dramonk:BAABNQAECoEWAAIQAAkJhx6zBAAHAwAQAAkJhx6zBAAHAwAAAA==.Dravianne:BAAANQADCgQIBAAAAA==.Druinlock:BAAANQADCgUIBQAAAA==.',
Du='Dustydrewid:BAAANQADCgEIAQAAAA==.',
Dy='Dyre:BAAANQAECgMIBAAAAA==.',
Ei='Eir:BAAANQAECgMIAwAAAA==.',
El='Ellsnarl:BAAANQADCgYIBgAAAA==.',
Em='Emeraldjin:BAAANQAECgEIAQAAAA==.',
En='Ensera:BAAANQADCgcIEwAAAA==.',
Er='Eraesong:BAAANQADCgMIAwAAAA==.Erielyn:BAAANQAECgIIAgAAAA==.Ernet:BAAANQAECgMIBAAAAA==.',
Ex='Extraho:BAAANQAECgUIBQAAAA==.',
Fa='Fabled:BAABNQAECoEXAAMRAAkJ9SBXAwDbAgARAAgJMh9XAwDbAgASAAQJ3R9nOwBkAQAAAA==.Faeyice:BAAANQAECgEIAQAAAA==.',
Fe='Fearmachine:BAAANQADCggIDgABNQAECgMIBAAFAAAAAA==.Feyden:BAAANQAECgEIAQAAAA==.',
Ff='Ffxivcatgirl:BAAANQADCgQIBAABNQAECgkJFwAMADolAA==.',
Fi='Fiiryazell:BAAANQAECgEIAQAAAA==.Fijaswarerth:BAAANQAECgMIBAAAAA==.Fimbulvargr:BAAANQAECgEIAQAAAA==.Finiith:BAAANQAECgUIBQABNQAECgkJFgABALkVAA==.Firedragön:BAAANQADCgQIBAAAAA==.',
Fl='Flogurnoggin:BAAANQADCggIAQAAAA==.Fluffyokami:BAAANQAECgQIBAAAAA==.Flyingrodent:BAAANQAECgIIAwAAAA==.',
Fo='Foneer:BAAANQAECgMIAwAAAA==.Forestsky:BAAANQAECgEIAQAAAA==.',
Fr='Freezepop:BAAANQAECgYICAAAAA==.Frenchieboi:BAAANQADCgcIDQABNQAECgQIBAAFAAAAAA==.Frenchielock:BAAANQAECgQIBAAAAA==.Frenchthyr:BAAANQAECgMIAwABNQAECgQIBAAFAAAAAA==.',
Ga='Galdiian:BAAANQADCgYIEAAAAA==.Gawdspet:BAAANQAECggIEQAAAA==.',
Gh='Ghosi:BAAANQAECgcIDgAAAA==.',
Gl='Glaivier:BAAANQADCggICwAAAA==.',
Go='Goodtimeboy:BAAANQADCgYIBwAAAA==.Goregrind:BAAANQAECgcIEwAAAA==.Gorgeous:BAAANQADCgIIAgAAAA==.Gorius:BAAANQADCgcIDAAAAA==.',
Gr='Grampman:BAAANQADCgMIAwAAAA==.Gremory:BAAANQAECgIIAgAAAA==.',
Gu='Guldank:BAAANQAECgIIAgAAAA==.Guretta:BAAANQAECgEIAQAAAA==.',
Gw='Gwynhwyvar:BAAANQADCggIEwAAAA==.',
Ha='Haeneros:BAAANQAECgEIAQAAAA==.Handmemytank:BAAANQAECgEIAQABNQAECgUICgAFAAAAAA==.Harumi:BAAANQAECgUICgAAAA==.',
He='Hearo:BAAANQAECgEIAQAAAA==.Heavyhead:BAAANQADCggIEgAAAA==.Hedgehog:BAAANQAECgYICQAAAA==.Heightning:BAAANQAECgMIBAAAAA==.Heisenberf:BAABNQAECoEXAAITAAkJshivJQC2AgATAAkJshivJQC2AgAAAA==.Hextrathicc:BAAANQAECgYICwAAAA==.',
Ho='Holybuttkick:BAAANQAECgQIBQABNQAFFAEIAQAFAAAAAA==.Hoozurdaddy:BAAANQAECgUIBQAAAA==.',
Ic='Icê:BAAANQAECgMIBAAAAA==.',
Ig='Ignatius:BAAANQAECgIIAgAAAA==.Igniting:BAAANQAECgcIDQABNQADCggICwAFAAAAAA==.',
Ik='Ikillyoutoo:BAAANQAECgUIBgAAAA==.',
Im='Impenetrable:BAAANQADCgcIBwAAAA==.Impression:BAAANQAFFAEIAQAAAA==.',
In='Incarnated:BAAANQAECgUIBwAAAA==.Incursion:BAAANQAECgEIAQAAAA==.Inviçtus:BAAANQAECgQIBAAAAA==.',
Ir='Ironwolf:BAAANQAECgYICQAAAA==.',
Ja='Jademoot:BAAANQAECgIIAgAAAA==.Jadis:BAAANQADCgUIBQAAAA==.Jaeaoria:BAAANQABCgIIAQAAAA==.Jaxblack:BAAANQADCggIEAAAAA==.Jayvlyn:BAAANQAECgEIAQAAAA==.',
Jj='Jjman:BAAANQAECgYIBwAAAA==.Jjuicyfruit:BAAANQADCgYIEAAAAA==.',
Jo='Joftokal:BAAANQAECgIIAgAAAA==.Jokesonme:BAAANQADCgYICgAAAA==.Jonebonejovi:BAAANQADCgIIAgAAAA==.Jorabna:BAAANQADCgYICgAAAA==.Joyboy:BAAANQAECgQICwAAAA==.',
Ka='Kakiso:BAAANQAECgMIAwAAAA==.Kalanash:BAAANQADCgUIBQAAAA==.Kalim:BAAANQADCgIIAgAAAA==.Kaloneras:BAAANQADCgYICAAAAA==.Kattle:BAABNQAECoEXAAIUAAkJZh7TAQA4AwAUAAkJZh7TAQA4AwAAAA==.',
Ke='Kellistus:BAAANQADCgUICQAAAA==.Keyrasky:BAAANQADCgYICQAAAA==.',
Kh='Khailyn:BAAANQADCgEIAQAAAA==.',
Ki='Kikuu:BAAANQAECgIIAgAAAA==.Kiradanna:BAAANQAECgUIDAAAAA==.Kiroa:BAAANQADCggIEAAAAA==.Kitå:BAEANQAECgQIBAAAAA==.Kiyoshiru:BAAANQADCgUIBQAAAA==.',
Kn='Knoks:BAAANQAECgYICQAAAA==.',
Ko='Koff:BAAANQAECggIDwAAAA==.Koreshei:BAAANQADCgYIEQAAAA==.',
Kr='Krixxus:BAAANQAECgEIAQAAAA==.',
Ku='Kuni:BAAANQAECgEIAQAAAQ==.',
La='Lamynx:BAAANQAECgMIBAAAAA==.Larinstore:BAAANQADCggIEwAAAA==.Lazydragon:BAAANQAECgIIAgAAAA==.',
Le='Leone:BAAANQAECgQIBAABNQAECgUIBQAFAAAAAA==.',
Li='Liberation:BAAANQAECgQIBAAAAA==.Lilreggie:BAAANQADCggIDgAAAA==.Lilvoids:BAAANQAECgYIEgAAAA==.Lineste:BAAANQAECgIIAgAAAA==.Lion:BAAANQAECgIIAwAAAA==.',
Lo='Loldie:BAAANQAECgEIAQAAAA==.Lonepanda:BAABNQAECoEXAAIVAAkJbSOZAACTAwAVAAkJbSOZAACTAwAAAA==.Lorwynx:BAAANQAECgYIDgAAAA==.',
Lu='Luciliv:BAAANQADCgYIBgABNQAECgYICgAFAAAAAA==.Lunado:BAAANQADCgUIBwAAAA==.Lupinaea:BAAANQADCggIEgAAAA==.',
Ma='Mabellah:BAAANQADCggIGgAAAA==.Maemikyu:BAAANQAECgUIDwAAAA==.Magusultimis:BAAANQAECgEIAQAAAA==.Mahöshöjo:BAAANQADCgcIEQAAAA==.Maintank:BAAANQAECgQIBgAAAA==.Makepoop:BAAANQAECgQIBgAAAA==.Manbomanbo:BAAANQAECgQIBAAAAA==.Marianita:BAAANQAECgUIBQAAAA==.Maureen:BAAANQADCgUIBQAAAA==.',
Me='Mediarahan:BAAANQADCgcIEQAAAA==.Melfist:BAAANQADCgcIEwAAAA==.Melysse:BAAANQAECgQIBQAAAA==.Mendocino:BAAANQADCgcIEAAAAA==.',
Mi='Mikiko:BAAANQAECgQIBQAAAA==.Millcreek:BAAANQAECgIIAgAAAA==.Milliananeko:BAAANQADCgUICQABNQAECgEIAQAFAAAAAA==.Missindragon:BAAANQAECgIIAgAAAA==.',
Mo='Moomoohead:BAAANQADCgEIAQAAAA==.Morberto:BAAANQABCgYICAAAAA==.Mormel:BAAANQAECgEIAQAAAA==.Morticus:BAAANQADCgEIAQAAAA==.',
Ms='Msthea:BAAANQADCggIDwAAAA==.',
['Mä']='Mälina:BAAANQADCgcIEQAAAA==.',
Na='Narial:BAAANQADCgIIAQAAAA==.Narru:BAAANQAECgcIEgAAAA==.',
Ne='Nebyula:BAAANQADCgcIDgAAAA==.',
No='Norieka:BAAANQADCggIEQAAAA==.Norvasc:BAAANQADCgEIAQAAAA==.Noskillidan:BAAANQADCgYIBgABNQAECgkJFwATALIYAA==.',
Nu='Numinous:BAAANQADCgUIBgABNQAECgYIBgAFAAAAAA==.',
Ny='Nykoleus:BAAANQAECgMIAwAAAA==.Nylokar:BAAANQABCgIIAgAAAA==.',
Og='Oggoat:BAAANQABCgQIBAAAAA==.',
Pa='Painindaazz:BAAANQADCgYIEgAAAA==.Pallygranny:BAEANQAECgQIBAAAAA==.Pawptart:BAAANQABCgQIBAAAAA==.',
Ph='Phyntom:BAAANQADCggIEAAAAA==.',
Pi='Pibbs:BAAANQAECgcIDQAAAA==.',
Pl='Plaguepanda:BAAANQAECgcIEwAAAA==.Platinumcas:BAAANQADCgYICgAAAA==.',
Po='Poohonroids:BAAANQAECgQIBgAAAA==.Poppatroll:BAAANQADCgcICwAAAA==.',
Pr='Protagoras:BAAANQAECgEIAQAAAA==.',
['Pä']='Pänz:BAAANQAECgEIAQAAAA==.',
Ra='Rafig:BAABNQAECoEXAAITAAkJTiIZBQChAwATAAkJTiIZBQChAwAAAA==.Ragefyre:BAAANQADCgcIDwAAAA==.Ralobii:BAAANQAECgIIAgABNQABCgQIBAAFAAAAAA==.Ramellis:BAAANQADCgMIAwAAAA==.Ramses:BAAANQAECggIEwAAAA==.Ratbasterd:BAAANQADCgQIBAAAAA==.Rats:BAAANQAECgIIAgAAAA==.Rayy:BAAANQAECgIIAwAAAA==.',
Re='Reinerbraun:BAAANQADCgEIAQAAAA==.Renade:BAAANQAECgEIAQAAAA==.Rexx:BAAANQADCgMIAwAAAA==.',
Ri='Rigidsxz:BAAANQADCgUIBQAAAA==.Riskymonk:BAAANQADCgIIAgAAAA==.Riskyshammy:BAAANQAECgYICQAAAA==.Riteaid:BAAANQAECgEIAQAAAA==.',
Ro='Robe:BAAANQADCgUICQABNQAECgEIAQAFAAAAAA==.Ronok:BAAANQAECgUIBQAAAA==.Rorthach:BAAANQADCgcIBwAAAA==.Roru:BAAANQAECgcIEwAAAA==.Roseire:BAAANQAECgIIAwAAAA==.Rosethebrute:BAAANQAECgYIDAAAAA==.Rosetheholy:BAAANQAECgQIBwABNQAECgYIDAAFAAAAAA==.Rougeloving:BAAANQAECggIEAAAAA==.',
Ru='Ruler:BAAANQAECgEIAQAAAA==.Ruli:BAAANQAECgYICwAAAA==.Rusticdiino:BAAANQADCgEIAQABNQAECgMIBwAFAAAAAA==.',
Ry='Ryshin:BAAANQAECgcIEAAAAA==.',
['Rø']='Rørs:BAAANQADCgcIBwAAAA==.',
Sa='Sabeck:BAAANQAECgMIAwABNQAECgYIBwAFAAAAAA==.Safi:BAAANQADCggICAAAAA==.Saltine:BAEANQADCgEIAQABNQAECgQIBAAFAAAAAA==.Sanctano:BAAANQADCggIFgAAAA==.Saneras:BAAANQADCgEIAQAAAA==.Sarshia:BAAANQADCgYICAAAAA==.Sayn:BAAANQAECgYICgAAAA==.',
Sc='Schultzies:BAAANQADCggIFQAAAA==.',
Sd='Sdog:BAAANQADCgIIAgAAAA==.',
Se='Seanboyymage:BAAANQAECgcIDwAAAA==.Seina:BAAANQAECgEIAQAAAA==.Sensei:BAAANQAECgEIAQAAAA==.Sephirofl:BAAANQAECgIIAgAAAA==.Seulrene:BAAANQAECgQIBgAAAA==.',
Sh='Shamlaw:BAAANQAECgQIBQAAAA==.Shammydavis:BAAANQAECgIIAgAAAA==.Shampayn:BAAANQADCgIIAgAAAA==.Shankiee:BAAANQABCgIIAgAAAA==.Shanti:BAAANQAECgEIAQAAAA==.Shhuffle:BAAANQAECgMIBQAAAA==.Shupasins:BAAANQAECgYICAAAAA==.Shyamablue:BAAANQAECgEIAQAAAA==.',
Si='Silvercas:BAAANQAECgMIAwAAAA==.Simpleyfire:BAAANQAECgMIBwAAAA==.',
Sk='Skullet:BAAANQAECgIIAgAAAA==.',
Sl='Slimshadyy:BAAANQADCgQIBQAAAA==.Slurpee:BAAANQAECgMIBAAAAA==.',
Sm='Smooth:BAAANQAECgQICAAAAA==.',
Sn='Sneekypete:BAAANQADCgYIBgAAAA==.Sniffer:BAAANQAECgYICgAAAA==.Snipercat:BAAANQAECgQIBAAAAA==.Snuffles:BAAANQAECgEIAQAAAA==.Snøkie:BAAANQADCgYIBgAAAA==.',
So='Solitude:BAAANQAFFAEIAQAAAA==.Sorscha:BAAANQADCggICAAAAA==.',
Sp='Spammy:BAAANQAECgcIDwAAAA==.Sparlyy:BAABNQAECoEXAAMWAAkJrSQFAQC/AwAWAAkJrSQFAQC/AwAJAAEJXQt+ZwA4AAAAAA==.Spectrality:BAAANQADCggIDQABNQAECgEIAQAFAAAAAA==.',
Ss='Sswordy:BAABNQAECoEYAAICAAkJeB1fCAAJAwACAAkJeB1fCAAJAwAAAA==.Sswordyvani:BAAANQADCgYIDAABNQAECgkJGAACAHgdAA==.',
St='Stimulus:BAAANQADCggIFgAAAA==.Stinkynuuts:BAAANQADCgcIDAAAAA==.Stormcloak:BAAANQADCggIDgAAAA==.Stormfang:BAAANQAECgEIAQAAAA==.',
Su='Sunkist:BAAANQADCggIDgAAAA==.Sunwing:BAAANQADCgUIBQAAAA==.Surlym:BAAANQAECgQIBQAAAA==.',
Sw='Switchglaive:BAAANQAECgMIBwAAAA==.',
Sy='Sylphie:BAAANQADCggIFQAAAA==.Symphemon:BAAANQAECgcIEwAAAA==.Symphoid:BAAANQADCgcIDAAAAA==.Syseloris:BAAANQAECgQIBAAAAA==.Sythion:BAAANQAECgcIDAAAAA==.',
['Së']='Sëphy:BAAANQADCgIIAgAAAA==.',
Ta='Taliiha:BAAANQAECgEIAQAAAA==.Tanao:BAAANQADCggIFgAAAA==.',
Te='Tengenuzui:BAAANQADCgEIAQAAAA==.Tenshi:BAAANQAECgMIAwAAAA==.Terravesh:BAAANQADCgIIAgAAAA==.',
Th='Thundergunt:BAAANQAECgEIAQABNQAECgYICAAFAAAAAA==.',
Ti='Tianjin:BAAANQADCgcIEgAAAA==.Tintaglia:BAAANQAECgIIAgAAAA==.Tiqtaqto:BAAANQADCgIIAgAAAA==.Tivali:BAAANQADCgIIAgAAAA==.',
To='Toaster:BAAANQAECgEIAQAAAA==.Tober:BAAANQADCgcIEAAAAA==.Toni:BAAANQADCgcIDwAAAA==.Toodles:BAAANQADCgUIBQAAAA==.',
Tr='Trust:BAAANQAECgIIAgAAAA==.',
Tu='Tunawhale:BAAANQADCgcIEAAAAA==.',
Ty='Tyloriavis:BAAANQADCgcICAAAAA==.',
Ul='Ulfin:BAAANQADCgUIBQABNQADCggIDwAFAAAAAA==.Ultramind:BAAANQADCgUIBQAAAA==.',
Um='Umbras:BAAANQADCgIIAgAAAA==.',
Un='Uncletouchie:BAAANQADCgIIAgAAAA==.',
Va='Vaeliir:BAAANQADCgUICQAAAA==.',
Ve='Vesani:BAAANQADCgQIBAAAAA==.',
Vi='Vinfuriating:BAAANQADCggIFQAAAA==.Violentjudge:BAAANQAECgIIAgAAAA==.Violla:BAAANQADCgcIEQAAAA==.Virgocelest:BAAANQAECgEIAQAAAA==.Viridion:BAAANQAECgEIAgAAAA==.Vivax:BAAANQAECgUICAAAAA==.',
Vo='Vorlos:BAAANQADCgUIBQAAAA==.',
Vr='Vreeg:BAAANQAECgIIAgAAAA==.',
Wh='Whiteflag:BAABNQAECoEWAAIXAAkJeSWTAgC1AwAXAAkJeSWTAgC1AwAAAA==.Whoopington:BAAANQADCgYIDQAAAA==.Whyamialive:BAABNQAECoEXAAIMAAkJXCZ+AADpAwAMAAkJXCZ+AADpAwAAAA==.',
Wi='Willowes:BAEANQADCggICAABNQAECgkJFwAJAOYVAA==.Willowest:BAEANQADCgYIBgABNQAECgkJFwAJAOYVAA==.Willowing:BAEANQAECgQIBAABNQAECgkJFwAJAOYVAA==.Willowish:BAEBNQAECoEXAAIJAAkJ5hUcFQBOAgAJAAkJ5hUcFQBOAgAAAA==.Winterz:BAAANQAECgQIDAAAAA==.Wiskii:BAAANQAECgIIAgAAAA==.',
Wo='Worio:BAAANQADCgYIDwAAAA==.',
Wy='Wytenha:BAAANQAECgEIAQABNQAECgcIEwAFAAAAAA==.Wytnarthom:BAAANQADCggICAABNQAECgcIEwAFAAAAAA==.Wytohne:BAAANQAECgcIEwAAAA==.',
Xa='Xaree:BAAANQAECgIIAgAAAA==.',
Xc='Xcat:BAAANQAECggIEgAAAA==.',
Xy='Xymer:BAAANQADCgcIDgAAAA==.',
Yi='Yim:BAAANQAECggICwAAAA==.Yismypetdead:BAAANQADCgYIBgABNQAECgEIAQAFAAAAAA==.',
Yo='Yorshka:BAAANQAECgYICgAAAA==.',
['Yú']='Yúno:BAAANQAECgUIBwAAAA==.',
Za='Zaffhavoc:BAAANQADCgYIBgABNQADCggIDAAFAAAAAA==.Zako:BAAANQADCgMIAwABNQAECgIIAgAFAAAAAA==.Zalliea:BAAANQADCgcIEwAAAA==.',
Ze='Zeff:BAAANQADCgcIEQAAAA==.',
Zo='Zompt:BAAANQADCggICAAAAA==.Zorndk:BAAANQAECgEIAQAAAA==.',
Zy='Zymar:BAAANQADCgMIAwABNQADCgcIDgAFAAAAAA==.',
['Ön']='Öni:BAAANQAECgcIDwAAAA==.',
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
