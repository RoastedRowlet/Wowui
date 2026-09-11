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

local lookup = {'Priest-Holy','Priest-Shadow','Priest-Discipline','Unknown-Unknown','Warlock-Destruction','DeathKnight-Unholy','Mage-Arcane','Rogue-Subtlety','Warlock-Demonology','Shaman-Restoration','Shaman-Elemental','Mage-Frost','Warrior-Arms','DeathKnight-Blood','Warlock-Affliction',}
local provider = {region='US',realm="Ner'zhul",name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Abeblinken:BAAANQABCgIIAgAAAA==.Abrigo:BAAANQAECgQIBAAAAA==.',
Ae='Aesbop:BAAANQAECgMIBAAAAA==.Aetherlight:BAABNQAECoEZAAQBAAkJvCLtBQAaAwABAAkJWCLtBQAaAwACAAUJBBe7GQBqAQADAAIJiSNSDACxAAAAAA==.',
Al='Alaanz:BAAANQADCgYIEAAAAA==.Alpharatz:BAAANQAECgUIBQAAAA==.',
Am='Amonamarth:BAAANQAECgcIDgAAAA==.Amunwrath:BAAANQAECgQIBAAAAA==.',
An='Anatharion:BAAANQAECgYICQAAAA==.Angrybao:BAAANQABCgYICAAAAA==.Annari:BAAANQAECgYICgAAAA==.Anéantir:BAAANQAECgMIAwAAAA==.',
Ao='Aozeraa:BAAANQAECgUIBwAAAA==.',
Ap='Apostate:BAAANQAECgEIAQABNQAECgUIBwAEAAAAAA==.',
Aq='Aquadond:BAAANQADCgcICwABNQAECgYIDAAEAAAAAQ==.',
Ar='Arbaal:BAAANQAECgQIBwAAAA==.Artemais:BAAANQAFFAEIAQAAAA==.',
As='Asaki:BAAANQADCgIIAgAAAA==.Asarmaul:BAAANQADCggIEAAAAA==.',
Av='Avein:BAAANQADCgQIBgAAAA==.',
Aw='Awesomeaf:BAAANQADCggICAABNQAECggIEgAEAAAAAA==.',
Az='Azernaut:BAAANQADCgYIBgAAAA==.Azgarth:BAAANQADCgcIDgABNQAECgEIAgAEAAAAAA==.Azureky:BAAANQAECgIIAgAAAA==.Azuresham:BAAANQADCgYIBgAAAA==.Azuric:BAAANQAECgMIAwAAAA==.',
Ba='Babytear:BAAANQAECgQIBAAAAA==.Badfelix:BAAANQAECgcIDwAAAA==.Baldrsonn:BAAANQAECgEIAQAAAA==.Balenciaga:BAAANQADCgcICQAAAA==.Bambuzzo:BAAANQAECgYICwAAAA==.Barbrawr:BAAANQAECgEIAgAAAA==.Bawr:BAAANQADCggICAAAAA==.',
Bd='Bdft:BAAANQADCgcIBwAAAA==.',
Be='Bearlee:BAAANQADCgIIAgAAAA==.Beautyboy:BAAANQAECgQIBAAAAA==.Beefdip:BAAANQAECgQIBAAAAA==.Benbear:BAAANQADCgQIBQAAAA==.',
Bg='Bgneedwork:BAAANQAECgMIAwAAAA==.',
Bi='Billidari:BAAANQAECgMIAwABNQAECgkJGAAFAGIZAA==.Bixby:BAAANQAECgIIAgAAAA==.',
Bl='Blachdeath:BAAANQAECgEIAQAAAA==.Blazedin:BAAANQAECgYICgAAAA==.Bleumachine:BAAANQADCgEIAQAAAA==.',
Bo='Boeds:BAAANQAECgEIAQAAAA==.Bokrim:BAAANQAECgQIBgAAAA==.',
Br='Brawns:BAAANQABCgYIDAABNQAECgcIDwAEAAAAAA==.Braér:BAAANQADCgcIBwAAAA==.Brisktwo:BAAANQADCgUIBQAAAA==.Brujo:BAAANQAECgQIBAABNQAFFAEIAQAEAAAAAA==.Brutalious:BAAANQAFFAEIAgAAAA==.Bryxie:BAAANQADCgYIBgABNQADCgYIBgAEAAAAAA==.',
Bu='Bubbes:BAAANQAECgMIAwAAAA==.Bubblebeåm:BAAANQAECgcIDQAAAA==.Buddy:BAAANQADCgcIBwAAAA==.Buggäsm:BAAANQADCgcIDgAAAA==.Bullterra:BAAANQADCggICAAAAA==.Bumkin:BAAANQAECgIIAgABNQADCgcIBwAEAAAAAA==.Bunnyjuice:BAAANQAECgIIAwAAAA==.',
By='Byakuya:BAAANQAECgQIBgAAAA==.',
Ca='Calcub:BAAANQAECgIIAgAAAA==.Calystalyn:BAEANQAECggIEQAAAA==.Captaïnjazz:BAAANQABCgIIAgAAAA==.Carelyda:BAAANQADCgYIBgAAAA==.Carneasada:BAAANQABCgEIAQAAAA==.Catheriana:BAAANQAECgMIAwAAAA==.',
Ch='Chach:BAAANQADCgUIBAAAAA==.Chris:BAAANQAECgcIDQAAAA==.Christmass:BAAANQAECgYIDQAAAA==.Chupas:BAAANQAECgQICAAAAA==.',
Cl='Clorinde:BAAANQADCgQIBAABNQAECgYICAAEAAAAAA==.',
Co='Colauris:BAAANQAECgYICQAAAA==.Coolweiner:BAAANQAECgcIDAAAAA==.Courserlul:BAAANQAECggIDAABNQAFFAcIDwAFAB8eAA==.',
Cr='Craodin:BAAANQAECgEIAQAAAA==.Craydaughter:BAAANQAECgEIAQAAAA==.Crayson:BAAANQADCgQIBAABNQAECgEIAQAEAAAAAA==.',
Da='Daddyops:BAAANQAECgQIBAAAAA==.Dan:BAAANQADCgIIAgAAAA==.Dandylion:BAAANQAECgUICAAAAA==.Dannamoth:BAAANQAECgYICAAAAA==.Darkmayhm:BAAANQADCgUIAwABNQAECgQIBwAEAAAAAA==.Darknss:BAAANQAECgEIAgAAAA==.Dathrustae:BAAANQADCgYIBgAAAA==.',
De='Deathaxza:BAAANQADCgEIAQAAAA==.Deatherselfs:BAAANQAECgQIBAAAAA==.Deathessence:BAAANQADCgEIAQAAAA==.Demondy:BAAANQAECgQICAAAAA==.Depaynes:BAAANQADCgYIDAAAAA==.Derekthegood:BAAANQAECgQIBAAAAA==.Dereliction:BAAANQAECgMIAwAAAA==.Derpindot:BAAANQAECgQIAwAAAA==.',
Di='Dihruid:BAAANQADCgIIAgABNQAECgQICAAEAAAAAA==.Dihscipline:BAAANQAECgIIAgABNQAECgQICAAEAAAAAA==.Dinkdonk:BAAANQAECgQICwAAAA==.Dipsnchip:BAAANQAECggIDgABNQAECgYIBwAEAAAAAA==.Divine:BAAANQAECgMIBwAAAA==.Dizzynight:BAAANQADCggIBwAAAA==.',
Dk='Dklulz:BAABNQAECoEWAAIGAAkJUx/lBgA6AwAGAAkJUx/lBgA6AwAAAA==.',
Do='Dojoe:BAAANQADCgYIBgAAAA==.',
Dr='Draac:BAAANQAECgEIAQAAAA==.Drachun:BAAANQAECgMIAwAAAA==.Drakelm:BAAANQAECggIEQAAAA==.Dranzdervish:BAAANQAECgMIBAAAAA==.Draykos:BAAANQADCgUIBQAAAA==.Droes:BAAANQADCgcIEwAAAA==.Dropaganda:BAAANQAECgQIBQAAAA==.Drrdead:BAAANQADCggIEgAAAA==.Dryeth:BAAANQADCgEIAQAAAA==.',
Du='Duckpond:BAAANQADCgYIBgAAAA==.Durrtybao:BAAANQAECgMIBAAAAA==.',
Dy='Dylanharp:BAAANQADCgQIBgAAAA==.',
Ea='Easynuh:BAAANQADCgYIBgABNQADCggIFgAEAAAAAA==.',
Ec='Ectheliön:BAAANQADCgMIAwABNQAECgUICgAEAAAAAA==.',
Eh='Ehkoe:BAAANQADCgQIBAAAAA==.',
Ek='Ekkõ:BAAANQADCgUIBQABNQAECgEIAQAEAAAAAA==.',
El='Elated:BAAANQAECgEIAQAAAA==.Eldanor:BAAANQAECgQIBQAAAA==.Elitextony:BAAANQADCgIIAgAAAA==.',
Em='Ember:BAAANQAECggIEgAAAA==.Emberz:BAAANQAECgIIAwAAAA==.Emiris:BAAANQADCgUIBQAAAA==.Emobuzz:BAAANQAECgUICgAAAA==.',
En='Enialis:BAAANQAECgYIBgAAAA==.Enyaspace:BAAANQADCgYIBgAAAA==.',
Es='Esperranza:BAAANQAECgMIAwAAAA==.Espurr:BAAANQAECggIEQAAAA==.',
Ev='Eveid:BAAANQAECgMIAwAAAA==.Evodny:BAAANQADCgYIEAAAAA==.',
Ex='Exodiaa:BAAANQADCgcICwAAAA==.',
Fa='Fact:BAAANQAECgYICQAAAA==.Faeris:BAAANQAECgMIAwAAAA==.Fahcup:BAAANQABCgYIBwAAAA==.Faroreswind:BAAANQAECgEIAQAAAA==.Fatchance:BAAANQADCgIIAQAAAA==.Fatherdots:BAAANQADCgIIAwABNQAECgUIBwAEAAAAAA==.',
Fe='Felbladekid:BAAANQADCgEIAQAAAA==.',
Fi='Fikkle:BAAANQAECgIIAgAAAA==.',
Fl='Flúffy:BAAANQADCggIFgAAAA==.',
Fo='Foodang:BAAANQADCgQIBAAAAA==.Fortyskols:BAAANQADCgQIBQAAAA==.',
Fr='Friarpuck:BAAANQAECgQICAAAAA==.Frostchi:BAAANQADCgcICQABNQAECgYICgAEAAAAAA==.Frostdawn:BAAANQAECgQIBAABNQAECgYICgAEAAAAAA==.Frosteye:BAAANQAECgYICgAAAA==.Frozensalt:BAABNQAECoERAAIHAAgJNyMBEQA2AwAHAAgJNyMBEQA2AwAAAA==.Fryerpuck:BAAANQADCgUIBgAAAA==.',
Fu='Furrbuddy:BAAANQAECgMIBAAAAA==.Furrsparta:BAAANQAECgEIAQAAAA==.',
Ga='Galiphe:BAAANQAECgUIBwAAAA==.Garidan:BAAANQAECgQIBAAAAA==.',
Ge='Geeyyanni:BAAANQAECgUIBwAAAA==.Geopetal:BAAANQAECgYIDgAAAA==.',
Gh='Ghasdros:BAAANQAECgUIBQAAAA==.',
Gi='Gingy:BAAANQADCgQIBAABNQAECgQIBAAEAAAAAA==.',
Gl='Gladefresh:BAAANQAECgQIBAAAAA==.Glowytwinkie:BAAANQADCgYIBgAAAA==.',
Go='Goldenice:BAAANQAECgIIAgAAAA==.Gooseriver:BAAANQAECgYIDgABNQADCgYIBgAEAAAAAA==.',
Gr='Greylan:BAAANQADCgYICAAAAA==.Greysha:BAAANQADCgcIBwAAAA==.Grinzler:BAAANQAECgQIBQAAAA==.Grym:BAAANQAECgMIAwAAAA==.',
Gu='Guappo:BAAANQAECgEIAQAAAA==.',
Ha='Hafwyn:BAAANQADCgYIDAABNQAECgYICgAEAAAAAA==.Hanor:BAAANQAECgQIBAAAAA==.Harløt:BAAANQAECgEIAQAAAA==.Hauntedblac:BAAANQAECgMIBAAAAA==.',
He='Heavenascend:BAAANQADCgcIBgAAAA==.Heraborn:BAAANQADCgMIAgAAAA==.',
Ho='Hojitalaurel:BAAANQADCgUICAAAAA==.Holymacaroli:BAAANQADCgEIAQAAAA==.Holysmiter:BAAANQAECgEIAQAAAA==.Holystrikér:BAAANQADCggICAAAAA==.Hoodfabulous:BAAANQAECgUICQAAAA==.',
Hu='Huberto:BAAANQADCgYIDAAAAA==.Huntn:BAAANQAECgQICAAAAA==.Hupyaptelyot:BAAANQAECgMIAwAAAA==.',
Hy='Hytierea:BAAANQAECgMIAwAAAA==.',
Ia='Iammudkip:BAAANQADCgYIDAAAAA==.',
Il='Ilocku:BAAANQAECgYIDAAAAQ==.',
Im='Imshamazing:BAAANQADCgQIBAAAAA==.',
In='Incubus:BAAANQAECgUIBwAAAA==.',
Io='Ionigvaah:BAAANQAECgcIDgAAAA==.',
Ir='Iriemon:BAAANQADCggIFgAAAA==.',
Is='Isabeau:BAAANQADCgEIAQAAAA==.Issowimonk:BAAANQADCgEIAQAAAA==.',
It='Italiaa:BAAANQAECgIIAgAAAA==.',
Ix='Ixtel:BAAANQAECgIIAgAAAA==.',
Ja='Jawesome:BAAANQAECgUIBQAAAA==.Jayron:BAAANQABCgUIBQAAAA==.',
Je='Jedakye:BAAANQAECgMIAwAAAA==.Jeepers:BAAANQADCgYIEAAAAA==.Jenzypoo:BAAANQADCgcIEQAAAA==.Jetson:BAAANQAECgQIBgAAAA==.',
Ji='Jiblits:BAAANQADCgcIBwABNQAECgUICQAEAAAAAA==.',
Jo='Jojo:BAAANQAECgYICwAAAA==.',
Jp='Jpow:BAAANQAECgEIAQAAAA==.',
Ju='Junnarma:BAAANQAECgMIAQAAAA==.',
['Já']='Járnviðr:BAAANQAECgUICgAAAA==.',
Ka='Kaalias:BAAANQADCgcIDgAAAA==.Kabrax:BAAANQADCggIBgAAAA==.Kai:BAAANQADCgYIBwAAAA==.Kaiula:BAAANQAECgcIDwAAAA==.Kalabar:BAAANQAECgMIBAAAAA==.Kaldrys:BAAANQAECgUICgAAAA==.Kalnath:BAAANQAECgYICgAAAA==.Kalynnah:BAAANQADCgcIBwAAAA==.Kamî:BAAANQADCgYIBgABNQAECgIIAgAEAAAAAA==.Kanarra:BAAANQADCggIEAAAAA==.Kanatoo:BAAANQAECgYIBwAAAA==.Kanekisenpai:BAAANQAECggIEwAAAA==.Kanjam:BAAANQAECgQIBgAAAA==.Kaylina:BAAANQADCgQIBAAAAA==.Kazrar:BAAANQADCggIDwAAAA==.',
Ke='Keepupheals:BAAANQADCgEIAQAAAA==.Keid:BAAANQAECgQIBgAAAA==.Kelai:BAAANQAECggIEAAAAA==.Kellion:BAAANQADCggICAAAAA==.Kenobi:BAAANQADCgYIBgAAAA==.',
Ki='Kikks:BAAANQADCgEIAQAAAA==.Kilusuka:BAAANQADCgUIBQAAAA==.',
Ko='Kobarr:BAAANQAECgUIBgAAAA==.Konbo:BAAANQAECgUIBwAAAA==.Koro:BAAANQAFFAEIAQAAAA==.',
Kr='Krapshoot:BAAANQADCgYICgABNQAECgQIBQAEAAAAAA==.Krolghoul:BAAANQAECgQIBAABNQAECgkJGAAIAKoeAA==.Krolgor:BAAANQAECgEIAQABNQAECgkJGAAIAKoeAA==.Krump:BAAANQAECgMIBQAAAA==.',
Ku='Kuramá:BAAANQAECgMIBAAAAA==.Kuzé:BAAANQAECgQIBQAAAA==.',
Kw='Kwyj:BAAANQAECgMIAwAAAA==.Kwyjibo:BAAANQAECgcIEQAAAA==.',
Ky='Kylebroflov:BAAANQAECgUIBgAAAA==.Kyyguy:BAAANQADCgYICAAAAA==.',
['Kí']='Kítkatz:BAAANQADCgUIBQAAAA==.',
['Kï']='Kïllerfrost:BAAANQAECgMIAwAAAA==.',
La='Lafizz:BAAANQADCgYIBgAAAA==.Lambofgods:BAAANQAECgUICQAAAA==.Lanana:BAAANQADCgEIAQAAAA==.',
Le='Lencel:BAAANQAECgEIAQAAAA==.Leonidas:BAAANQADCggIDAAAAA==.Letmo:BAAANQADCgcICwAAAA==.Letmu:BAAANQADCgUICAABNQADCgcICwAEAAAAAA==.Levelfour:BAAANQADCgIIAgAAAA==.',
Li='Liannia:BAAANQADCgUIBwABNQAECgQIBAAEAAAAAA==.Lightningki:BAAANQAECgIIAgAAAA==.Lightofdawn:BAAANQADCgMIAwAAAA==.Lightscream:BAAANQAECgYICgAAAA==.Lilshoobs:BAAANQADCggIFAAAAA==.Lindariel:BAAANQADCgMIAwAAAA==.Lindir:BAAANQAECgcIDgAAAA==.Liparoonie:BAAANQAECgMIBAAAAA==.Liyt:BAAANQADCgIIAgABNQAECgQIBgAEAAAAAA==.',
Lo='Lockedupfoo:BAABNQAECoEYAAMJAAgJQyPNCwC1AgAJAAcJcSLNCwC1AgAFAAQJaxkiHQA7AQAAAA==.Locktorty:BAAANQADCgIIAgAAAA==.Lolmindflay:BAAANQADCgYIBgAAAA==.',
Lu='Ludd:BAAANQADCgQIAQAAAA==.Lunah:BAAANQAECgUICgAAAA==.Lupozz:BAAANQAECgUIBwAAAA==.',
['Lå']='Låb:BAAANQADCgQIBAAAAA==.',
Ma='Machahunt:BAAANQAECgEIAgAAAA==.Machico:BAAANQAECgQIBAAAAA==.Magicdeadly:BAAANQAECgMIBAAAAA==.Magicol:BAAANQAECgMIAwABNQAECgYICQAEAAAAAA==.Magosika:BAAANQAECgQIBAAAAA==.Maledizione:BAAANQADCgYIDQAAAA==.Manaburner:BAAANQAECgEIAQAAAA==.',
Me='Meerahs:BAAANQAECgQIBAAAAA==.Megahorn:BAAANQAECgcICwAAAA==.Megthpallion:BAAANQADCgcICwAAAA==.',
Mf='Mfhambone:BAAANQADCgIIAwAAAA==.',
Mi='Midliyt:BAAANQAECgQIBgAAAA==.Midniyt:BAAANQADCgQIBAABNQAECgQIBgAEAAAAAA==.Mikaylla:BAAANQADCgQICAAAAA==.Mikkilina:BAAANQAECgEIAQAAAA==.Mitric:BAAANQADCggIFgAAAA==.',
Mm='Mmeow:BAAANQAECgQIBAAAAA==.',
Mo='Moowarrior:BAAANQAECgIIAgAAAA==.Mosswyn:BAAANQADCggIDQAAAA==.',
Mu='Murmaiderr:BAAANQAECgEIAQAAAA==.Murman:BAAANQADCgIIAgAAAA==.',
Na='Nalla:BAAANQADCgYIBgAAAA==.Naravia:BAAANQADCggIFAAAAA==.Narunî:BAAANQADCgYICQAAAA==.Nater:BAAANQAECgQIBAAAAA==.',
Ne='Necrovyn:BAAANQADCgEIAQAAAA==.Nekkrosys:BAAANQAECgMIBQAAAA==.Nekrron:BAAANQADCgIIAgAAAA==.Neona:BAAANQAECgEIAQAAAA==.Nevets:BAAANQABCgYIBwAAAA==.',
Ni='Nicessus:BAAANQAECgYICgAAAA==.Nicksys:BAAANQAECgQIBwAAAA==.Nikkanika:BAAANQAECgQIBAABNQAECgYICwAEAAAAAA==.Niuzao:BAAANQADCgEIAQAAAA==.',
No='Nork:BAAANQAECgIIAgAAAA==.Norko:BAAANQADCgQIBAAAAA==.Norks:BAAANQADCgYIBgAAAA==.Normalname:BAAANQADCggICAAAAA==.Novembër:BAAANQAECgEIAQAAAA==.',
['Nÿ']='Nÿkon:BAAANQAECgIIAgAAAA==.',
Od='Oderrus:BAAANQADCgUIBQABNQAECgEIAQAEAAAAAA==.',
Ok='Okishama:BAAANQAECggIEwAAAA==.',
On='Onkrack:BAAANQADCgcIDgABNQAECgIIAgAEAAAAAA==.',
Op='Ophelastra:BAAANQAECgQIBQAAAA==.',
Oz='Ozfiz:BAAANQADCgYIBgABNQAECgQIBQAEAAAAAA==.Ozwiz:BAAANQADCgMIAwABNQAECgQIBQAEAAAAAA==.',
Pa='Pandatastic:BAABNQAECoEfAAMKAAkJoSMcAQCxAwAKAAkJoSMcAQCxAwALAAEJNAwAAAAAAAAAAA==.Pastrami:BAAANQAECgUICAAAAA==.Patbee:BAAANQADCgIIBAABNQADCgQIAQAEAAAAAA==.Pawn:BAAANQADCgcICAAAAA==.',
Pe='Pearlsham:BAAANQAECgQIBAAAAA==.Peekaaboo:BAAANQADCgQIBAAAAA==.',
Ph='Phikkle:BAAANQADCgUIBQAAAA==.Phâtè:BAAANQAECgIIBAAAAA==.',
Pi='Picesty:BAAANQAECgYIDgABNQABCgYIBwAEAAAAAA==.Pilikiä:BAAANQADCgcIBwAAAA==.',
Pk='Pkflash:BAAANQAECgMIAwAAAA==.',
Pl='Platinumbull:BAAANQAECgYIDAAAAA==.Pleabsham:BAAANQAECgEIAQAAAA==.',
Po='Pokentotem:BAAANQAECgQIBAAAAA==.Potlogic:BAAANQAECgQIBQABNQAECggIFwAMACcUAA==.',
Pr='Prandel:BAAANQABCgMIAwABNQAECgQIBQAEAAAAAA==.Prosciutto:BAAANQABCgQIBgAAAA==.',
Pu='Puddl:BAAANQAECgIIAgAAAA==.Punkii:BAAANQAECgcIDAAAAA==.Punnisher:BAAANQADCgYIBgAAAA==.',
Qp='Qpawnz:BAAANQADCgMIAwABNQAECggIEgAEAAAAAA==.',
Qu='Quidamtyra:BAAANQAECgMIAwAAAA==.Quigonjin:BAAANQAECgEIAgAAAA==.',
Ra='Rabbifrost:BAAANQADCggICAAAAA==.Rackem:BAAANQADCgEIAQAAAA==.Rackham:BAAANQAECgcIEgAAAA==.Radiana:BAAANQAECgQIBAAAAA==.Raeknor:BAAANQAECgQIBAAAAA==.Raizén:BAAANQABCgQIBAAAAA==.Randomaction:BAAANQAECgMIBAAAAA==.Rastabution:BAAANQAECggIAQAAAA==.Rathvyr:BAABNQAECoEZAAINAAkJ2B4DDgAjAwANAAkJ2B4DDgAjAwAAAA==.Razuriell:BAAANQAECgYICQAAAA==.',
Re='Reagan:BAAANQABCgIIAgAAAA==.Rebeakah:BAAANQAECgQIBgAAAA==.Reggs:BAAANQAECgEIAQAAAQ==.Renko:BAAANQAECgUICAAAAA==.',
Ri='Ribitey:BAAANQAFFAEIAQAAAA==.Riggs:BAAANQADCgYIEAAAAA==.Riggster:BAAANQAECgUICgAAAA==.Rilakuma:BAAANQAECgQIBAAAAA==.',
Ro='Rockyballz:BAAANQADCgEIAQAAAA==.Rolando:BAABNQAECoEYAAINAAgJ5Q+uNAAIAgANAAgJ5Q+uNAAIAgAAAA==.Rosybel:BAAANQADCgQIBAAAAA==.Rotimus:BAAANQADCgIIAgAAAA==.Rozewyn:BAAANQAECgMIBQAAAA==.',
Ru='Rukator:BAAANQAECgEIAQAAAA==.',
Ry='Ryawhitefang:BAAANQAECgcIDQAAAA==.',
['Rà']='Ràgé:BAAANQAECgIIAgAAAA==.',
['Rê']='Rêddit:BAAANQADCgMIAwAAAA==.',
Sa='Salael:BAAANQAECgcIEAAAAA==.Saphi:BAAANQADCggICAAAAA==.Saphirin:BAABNQAECoEYAAIOAAkJMxjyDwB5AgAOAAkJMxjyDwB5AgAAAA==.Sariphi:BAAANQADCgQIBAAAAA==.Sauron:BAAANQADCggIEQAAAA==.Savagebrain:BAAANQADCgUIBwABNQAECggIDQAEAAAAAA==.Savagelung:BAAANQAECggIDQAAAA==.Saya:BAAANQADCgYIBgAAAA==.',
Sc='Schoonie:BAAANQADCgYIDAAAAA==.Schutzengel:BAAANQAFFAEIAgAAAA==.Scribbl:BAAANQAECgYIDAAAAA==.Scylon:BAAANQADCgYIBgAAAA==.Scythen:BAAANQADCgYIBgAAAA==.',
Se='Sencerity:BAAANQADCgEIAQAAAA==.Serana:BAAANQAECgIIAgAAAA==.',
Sh='Shadowbanned:BAAANQADCgUIBQAAAA==.Shallowgrave:BAAANQAECgYICwAAAA==.Shamanhands:BAAANQAECgEIAQAAAA==.Shammyhaggar:BAAANQAECgQIBAAAAA==.Shamram:BAAANQADCggIEAAAAA==.Shamywamy:BAAANQAECggICwAAAA==.Shaodh:BAAANQADCgUIBQAAAA==.Shaodk:BAAANQAECggICAAAAA==.Sharkeesha:BAAANQADCgQIBAAAAA==.Shawdi:BAAANQABCgIIAgAAAA==.Shibs:BAAANQADCgQIBAAAAA==.Shiffty:BAAANQAECgEIAQAAAA==.Shiggadin:BAAANQAECgMIBQAAAA==.Shiggalaw:BAAANQAECgEIAQABNQAECgMIBQAEAAAAAA==.Shikki:BAAANQAECgQIBwAAAA==.Shinys:BAAANQAECgMIBAABNQAECgUIBgAEAAAAAA==.Shuki:BAAANQADCgEIAQAAAA==.Shámtastic:BAAANQADCgYIBgAAAA==.Shäde:BAAANQAECgcIEAAAAA==.',
Si='Simpai:BAAANQAECgIIAgAAAA==.Sinzspirits:BAAANQADCgIIAgAAAA==.',
Sk='Skiethx:BAAANQAECggIEAAAAA==.Skipii:BAAANQAECgIIAgAAAA==.Skullderzix:BAAANQAECgQIBAAAAA==.',
Sl='Slopersafari:BAAANQAECgQIBgAAAA==.Slowqt:BAABNQAECoEXAAIGAAkJYR/yBgA5AwAGAAkJYR/yBgA5AwAAAA==.',
Sm='Smashyz:BAAANQADCgYIBgABNQADCgYIBgAEAAAAAA==.',
So='Somaria:BAAANQAECgEIAQAAAA==.Sonabrie:BAAANQADCgEIAQAAAA==.',
Sp='Spankybottom:BAAANQAECgIIAgAAAA==.Sparykz:BAAANQADCgYICgABNQAECgIIAwAEAAAAAA==.Spiyt:BAAANQADCgQIBAABNQAECgQIBgAEAAAAAA==.Spnkynvrsoft:BAAANQAECgYIDAAAAA==.',
Sq='Squeaky:BAAANQAECgQIBgAAAA==.Squee:BAAANQAECgMIAwAAAA==.',
Sr='Srmonkey:BAAANQADCggIDQAAAA==.',
St='Stabachacha:BAAANQAECggIEgAAAA==.Steamicyhott:BAAANQADCgcICwAAAA==.Stinkie:BAAANQAFFAEIAQAAAA==.Stonebeard:BAAANQADCgYIBgAAAA==.Stormcore:BAAANQAECgMIAwAAAA==.',
Su='Sunny:BAAANQADCgYIEAAAAA==.Supernóva:BAAANQADCgEIAQABNQADCggIDAAEAAAAAA==.',
Sw='Swampybutt:BAAANQABCgMIAgAAAA==.',
Sy='Sylvanass:BAAANQADCgYICAAAAA==.Sylverarrow:BAAANQAECgMIAwAAAA==.Syreith:BAAANQADCgQIBQAAAA==.',
Ta='Tacabell:BAAANQAECgUICAAAAA==.Taken:BAAANQAECgcIEAAAAA==.Tarkarram:BAAANQAECgIIAgAAAA==.Tarnfair:BAAANQADCgUIDAAAAA==.Taurìel:BAAANQAECgIIAgAAAA==.Taven:BAAANQAECgEIAQAAAA==.',
Te='Technique:BAAANQADCgcIDAAAAA==.Tekka:BAAANQAECgIIAgAAAA==.Telegram:BAAANQADCgIIAgAAAA==.Telvor:BAAANQAECgEIAQAAAA==.Terrukk:BAAANQAECgIIAgAAAA==.Tessalie:BAAANQADCgMIAwAAAA==.Teufelsnudel:BAAANQAECgIIAgAAAA==.',
Th='Theliver:BAAANQADCggICQAAAA==.Thelysong:BAAANQAECgEIAQAAAA==.Therran:BAAANQAECgYICwAAAA==.Theuss:BAAANQAECgEIAQAAAA==.Thexador:BAAANQAECgIIAgAAAA==.Thorraden:BAAANQADCgMIAwABNQAECgIIAwAEAAAAAA==.Thranduill:BAAANQAECgEIAQAAAA==.',
Ti='Tidefury:BAAANQAECgEIAQAAAA==.Tidepod:BAAANQAECgYIBgABNQAECgkJFgAJAPIhAA==.Tigerclaw:BAAANQAECgIIAwAAAA==.Tilley:BAAANQADCgYICwAAAA==.Tingaling:BAAANQAECgQIBQAAAA==.',
Tl='Tlock:BAAANQAECgIIAgAAAA==.',
To='Tool:BAAANQABCgIIAgAAAA==.Toothlss:BAAANQADCgUICAABNQADCgcIBwAEAAAAAA==.Toragza:BAAANQAECgEIAQAAAA==.Totums:BAAANQADCggIDgAAAA==.Toyletpaypah:BAAANQADCgQIBAABNQAECgMIAwAEAAAAAA==.',
Tr='Trashyz:BAAANQAECgQIBQABNQADCgYIBgAEAAAAAA==.Treseme:BAAANQABCgIIAgAAAA==.Triaradea:BAAANQADCgUIBgABNQADCgYIBgAEAAAAAA==.Tribalz:BAAANQAECgUIBwAAAA==.Trunddle:BAAANQAECgQIBgAAAA==.',
Tu='Tuchmydemons:BAAANQAECgEIAQAAAA==.',
Ty='Tygrelilly:BAAANQAECgQIBAAAAA==.Tyrieal:BAAANQADCggIFAAAAA==.',
['Tø']='Tøøthlss:BAAANQADCgcIBwAAAA==.',
Ul='Ulidan:BAAANQADCgIIAgAAAA==.',
Un='Ungoloth:BAAANQADCgMIAwABNQAECgQIBAAEAAAAAA==.',
Va='Vamp:BAAANQADCggIDwAAAA==.Vanêssa:BAAANQAECgEIAQAAAA==.Varner:BAAANQAFFAEIAQAAAA==.',
Vi='Vindict:BAAANQADCgEIAQAAAA==.',
Vl='Vlakshift:BAAANQAECgQIBgAAAA==.',
Vo='Voltedrage:BAAANQAECggIBgAAAA==.Vongalas:BAAANQAECgMIAwAAAA==.Vongimi:BAAANQAECgMIBAAAAA==.Vongimiv:BAAANQADCgYIDAABNQAECgMIBAAEAAAAAA==.Voucher:BAAANQAECggIEgAAAA==.',
Vy='Vyn:BAAANQAECgQIBAAAAA==.Vynstarcyon:BAAANQADCgcICgAAAA==.Vysérå:BAAANQAECgQIBAAAAA==.',
Wa='Wai:BAAANQAECgYIDAAAAA==.Warglaíve:BAAANQAECgYIDAAAAA==.Wasted:BAAANQAECgQIBQAAAA==.',
Wh='Whilson:BAAANQADCggIEwAAAA==.Whilsonh:BAAANQADCgcIBwABNQADCggIEwAEAAAAAA==.',
Wi='Wildbillee:BAAANQAECgMIAwABNQAECgkJGAAFAGIZAA==.Wildbilly:BAAANQAECgQICQABNQAECgkJGAAFAGIZAA==.Wildbily:BAAANQADCgYIBgABNQAECgkJGAAFAGIZAA==.Wilhson:BAAANQADCgEIAQABNQADCggIEwAEAAAAAA==.Wilsuhn:BAAANQADCgIIAgABNQADCggIEwAEAAAAAA==.Winterveil:BAAANQADCgEIAQAAAA==.Witchblade:BAAANQADCgQIBQABNQADCggIFgAEAAAAAA==.',
Wo='Worldwaker:BAAANQAECgYIDAAAAA==.Wornn:BAAANQADCgYICQAAAA==.',
Wr='Wretched:BAAANQAECgcIDwAAAA==.',
Wu='Wukard:BAAANQAECgQIBAAAAA==.',
Wy='Wylblly:BAAANQADCggIDgABNQAECgkJGAAFAGIZAA==.Wyldbill:BAABNQAECoEYAAQFAAkJYhnuCwD/AQAFAAYJERzuCwD/AQAJAAMJNQy6ZQC+AAAPAAEJeCTCDgBlAAAAAA==.',
Xa='Xarxzez:BAAANQAECgQIBQAAAA==.',
Xe='Xer:BAAANQABCgQIBAAAAA==.',
Xf='Xfaeble:BAAANQAECggIDwAAAA==.',
Xg='Xgambit:BAAANQAECgQIBwAAAA==.',
Xp='Xprtdemon:BAAANQADCgcIDAAAAA==.',
Xy='Xylar:BAAANQADCgUIBQAAAA==.Xyno:BAAANQAECgQIBgAAAA==.',
Ya='Yandora:BAAANQABCgEIAQAAAA==.',
Yo='Yoggibear:BAAANQAECgIIAgAAAA==.Yoreick:BAAANQADCgUIBQAAAA==.',
Yu='Yuckmouth:BAABNQAECoEXAAIMAAgJJxTzAgAmAgAMAAgJJxTzAgAmAgAAAA==.Yuli:BAAANQAECgMIAwABNQAECgMIBwAEAAAAAA==.',
Za='Zadaen:BAAANQAECgIIAgAAAA==.Zaladren:BAAANQAECgEIAQAAAA==.Zave:BAAANQAECgEIAQAAAA==.',
Ze='Zenshot:BAAANQAECgQIBQAAAA==.Zerazenazath:BAAANQADCgYIDwAAAA==.',
Zi='Ziegevolk:BAAANQADCgQIBAABNQADCgYIBgAEAAAAAA==.',
Zo='Zoobra:BAAANQADCgcIDAAAAA==.Zorkky:BAAANQADCgQIBAAAAA==.',
Zu='Zubinator:BAAANQAECgMIAwAAAA==.Zulteld:BAAANQADCgIIAgABNQAECgQIBQAEAAAAAA==.',
['Ác']='Áchu:BAAANQAECgcICwAAAA==.',
['Âr']='Ârrgh:BAAANQAECgMIBgAAAA==.',
['Än']='Änh:BAAANQAECgMIAwAAAA==.',
['Ðe']='Ðestroyer:BAAANQADCggIDwAAAA==.',
['Ðj']='Ðjinzen:BAAANQADCgMIAwAAAA==.',
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
