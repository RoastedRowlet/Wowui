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

local lookup = {'Unknown-Unknown','Warlock-Demonology','Shaman-Restoration',}
local provider = {region='US',realm="Ner'zhul",name='US',type='weekly',zone=53,date='2026-09-01',data={Ab='Abeblinken:BAAANQABCgIIAgAAAA==.Abrigo:BAAANQADCgUIBgAAAA==.',
Ae='Aesbop:BAAANQAECgEIAQAAAA==.Aetherlight:BAAANQAECggIDgABNQADCggIDwABAAAAAA==.',
Al='Alaanz:BAAANQADCgUICgAAAA==.',
Am='Amonamarth:BAAANQAECgUIBwAAAA==.Amunwrath:BAAANQADCggIDgAAAA==.',
An='Anatharion:BAAANQAECgMIAwAAAA==.Annari:BAAANQAECgYIBwAAAA==.Anéantir:BAAANQADCgcIDgAAAA==.',
Ao='Aozeraa:BAAANQAECgIIAgAAAA==.',
Ap='Apostate:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.',
Aq='Aquadond:BAAANQADCgQIBAABNQAECgUIBgABAAAAAQ==.',
Ar='Arbaal:BAAANQAECgIIAgAAAA==.Artemais:BAAANQAECgcICwAAAA==.',
As='Asarmaul:BAAANQADCggICQAAAA==.',
Av='Avein:BAAANQADCgIIAgAAAA==.',
Aw='Awesomeaf:BAAANQABCgQIBQABNQAECgcICgABAAAAAA==.',
Az='Azgarth:BAAANQADCgUIBwABNQAECgEIAQABAAAAAA==.Azureky:BAAANQADCggIDgAAAA==.Azuresham:BAAANQADCgYIBgAAAA==.Azuric:BAAANQADCgUIBQAAAA==.',
Ba='Babytear:BAAANQADCgYIBgAAAA==.Badfelix:BAAANQAECgUIBwAAAA==.Baldrsonn:BAAANQADCggICgAAAA==.Balenciaga:BAAANQADCgcICQAAAA==.Bambuzzo:BAAANQAECgUIBQAAAA==.Barbrawr:BAAANQAECgEIAQAAAA==.Bawr:BAAANQADCggICAAAAA==.',
Be='Bearlee:BAAANQADCgIIAgAAAA==.Beautyboy:BAAANQADCggIDQAAAA==.Beefdip:BAAANQADCgUIBwAAAA==.Benbear:BAAANQADCgQIBQAAAA==.',
Bg='Bgneedwork:BAAANQADCgYIBgAAAA==.',
Bi='Billidari:BAAANQADCgcICgABNQAECgYIDAABAAAAAA==.Bixby:BAAANQADCgUIBQAAAA==.',
Bl='Blachdeath:BAAANQADCggIDwAAAA==.Blazedin:BAAANQAECgQIBAAAAA==.Bleumachine:BAAANQADCgEIAQAAAA==.',
Bo='Boeds:BAAANQADCggIDQAAAA==.Bokrim:BAAANQAECgIIAgAAAA==.',
Br='Braér:BAAANQADCgcIBwAAAA==.Brujo:BAAANQAECgQIBAABNQAECgcICwABAAAAAA==.Brutalious:BAAANQAECgcICwAAAA==.',
Bu='Bubbes:BAAANQADCggICwAAAA==.Bubblebeåm:BAAANQAECgUIBgAAAA==.Buggäsm:BAAANQADCgcICQAAAA==.Bumkin:BAAANQADCgYIBQAAAA==.Bunnyjuice:BAAANQADCgMIAwAAAA==.',
By='Byakuya:BAAANQADCgYIBgAAAA==.',
Ca='Calcub:BAAANQADCgIIAgAAAA==.Calystalyn:BAEANQAECgYICgAAAA==.Catheriana:BAAANQADCggICwAAAA==.',
Ch='Chach:BAAANQADCgUIBAAAAA==.Chris:BAAANQAECgUIBgAAAA==.Christmass:BAAANQAECgUIBwAAAA==.Chupas:BAAANQAECgQIBAAAAA==.',
Cl='Clorinde:BAAANQADCgQIBAABNQAECgYIBwABAAAAAA==.',
Co='Colauris:BAAANQAECgIIAgAAAA==.Coolweiner:BAAANQAECgQIBQAAAA==.Courserlul:BAAANQAECggICgABNQAFFAYICAACAN8bAA==.',
Cr='Craodin:BAAANQAECgEIAQAAAA==.Craydaughter:BAAANQADCgcIDAAAAA==.',
Da='Daddyops:BAAANQADCggIDwAAAA==.Dan:BAAANQADCgIIAgAAAA==.Dandylion:BAAANQAECgMIAwAAAA==.Dannamoth:BAAANQAECgIIAgAAAA==.Darknss:BAAANQAECgEIAQAAAA==.Dathrustae:BAAANQADCgYIBgAAAA==.',
De='Deathaxza:BAAANQADCgEIAQAAAA==.Deatherselfs:BAAANQADCgcIDQAAAA==.Deathessence:BAAANQADCgEIAQAAAA==.Demondy:BAAANQAECgMIBAAAAA==.Depaynes:BAAANQADCgQIBgAAAA==.Derekthegood:BAAANQADCgEIAQAAAA==.Dereliction:BAAANQADCggIDgAAAA==.Derpindot:BAAANQAECgQIAwAAAA==.',
Di='Dihruid:BAAANQADCgIIAgABNQAECgQIBAABAAAAAA==.Dihscipline:BAAANQADCgUIBQABNQAECgQIBAABAAAAAA==.Dinkdonk:BAAANQAECgIIBAAAAA==.Dipsnchip:BAAANQAECgcICwABNQAECgEIAQABAAAAAA==.Divine:BAAANQAECgMIBQAAAA==.Dizzynight:BAAANQADCgcIBwAAAA==.',
Dk='Dklulz:BAAANQAECgcIDAAAAA==.',
Do='Dojoe:BAAANQADCgYIBgAAAA==.',
Dr='Draac:BAAANQAECgEIAQAAAA==.Drachun:BAAANQADCggICAAAAA==.Drakelm:BAAANQAECgYICgAAAA==.Dranzdervish:BAAANQAECgEIAQAAAA==.Draykos:BAAANQADCgUIBQAAAA==.Droes:BAAANQADCgcIDQAAAA==.Dropaganda:BAAANQAECgEIAQAAAA==.Drrdead:BAAANQADCgUICgAAAA==.',
Du='Duckpond:BAAANQADCgYIBgAAAA==.Durrtybao:BAAANQAECgEIAQAAAA==.',
Ea='Easynuh:BAAANQADCgYIBgABNQADCggIDgABAAAAAA==.',
Ec='Ectheliön:BAAANQADCgMIAwABNQAECgQIBQABAAAAAA==.',
Ek='Ekkõ:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.',
El='Eldanor:BAAANQAECgIIAgAAAA==.Elitextony:BAAANQADCgIIAgAAAA==.',
Em='Ember:BAAANQAECgcICgAAAA==.Emberz:BAAANQADCggIDQAAAA==.Emobuzz:BAAANQAECgQIBQAAAA==.',
En='Enialis:BAAANQADCggICAAAAA==.',
Es='Esperranza:BAAANQADCggICwAAAA==.Espurr:BAAANQAECgYICgAAAA==.',
Ev='Eveid:BAAANQADCgEIAQAAAA==.Evodny:BAAANQADCgUICgAAAA==.',
Ex='Exodiaa:BAAANQADCgcICwAAAA==.',
Fa='Fact:BAAANQAECgMIAwAAAA==.Faeris:BAAANQADCgcIBwAAAA==.Fahcup:BAAANQABCgMIAwAAAA==.Faroreswind:BAAANQAECgEIAQAAAA==.Fatchance:BAAANQADCgIIAQAAAA==.Fatherdots:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.',
Fe='Felbladekid:BAAANQADCgEIAQAAAA==.',
Fi='Fikkle:BAAANQADCggIDwAAAA==.',
Fl='Flúffy:BAAANQADCgcIDgAAAA==.',
Fo='Fortyskols:BAAANQADCgEIAQAAAA==.',
Fr='Friarpuck:BAAANQAECgQIBAAAAA==.Frostchi:BAAANQADCgcICQABNQAECgQIBAABAAAAAA==.Frostdawn:BAAANQADCggIDQABNQAECgQIBAABAAAAAA==.Frosteye:BAAANQAECgQIBAAAAA==.Frozensalt:BAAANQAECgUIBwAAAA==.Fryerpuck:BAAANQADCgUIBgAAAA==.',
Fu='Furrbuddy:BAAANQAECgEIAQAAAA==.Furrsparta:BAAANQADCgYICQAAAA==.',
Ga='Galiphe:BAAANQAECgIIAgAAAA==.Garidan:BAAANQADCggIDgAAAA==.',
Ge='Geeyyanni:BAAANQAECgIIAgAAAA==.Geopetal:BAAANQAECgYICAAAAA==.',
Gh='Ghasdros:BAAANQAECgUIBQAAAA==.',
Gi='Gingy:BAAANQADCgQIBAABNQADCggIDwABAAAAAA==.',
Gl='Gladefresh:BAAANQADCgYIBgAAAA==.Glowytwinkie:BAAANQADCgYIBgAAAA==.',
Go='Goldenice:BAAANQADCggICAAAAA==.Gooseriver:BAAANQAECgYICAABNQADCgYIBgABAAAAAA==.',
Gr='Greylan:BAAANQADCgIIAgAAAA==.Grinzler:BAAANQAECgEIAQAAAA==.Grym:BAAANQADCggIDgAAAA==.',
Gu='Guappo:BAAANQADCggICAAAAA==.',
Ha='Hafwyn:BAAANQADCgYIDAABNQAECgUIBQABAAAAAA==.Hanor:BAAANQADCgYICwAAAA==.Harløt:BAAANQADCgYICgAAAA==.Hauntedblac:BAAANQAECgEIAQAAAA==.',
He='Heavenascend:BAAANQADCgUIBQAAAA==.Heraborn:BAAANQADCgMIAgAAAA==.',
Ho='Hojitalaurel:BAAANQADCgUICAAAAA==.Holysmiter:BAAANQADCggICAAAAA==.Holystrikér:BAAANQADCggICAAAAA==.Hoodfabulous:BAAANQAECgIIBAAAAA==.',
Hu='Huberto:BAAANQADCgQIBgAAAA==.Huntn:BAAANQAECgQIBAAAAA==.Hupyaptelyot:BAAANQAECgEIAQAAAA==.',
Hy='Hytierea:BAAANQADCggIDQAAAA==.',
Ia='Iammudkip:BAAANQADCgMIAwAAAA==.',
Ie='Iegoou:BAAANQADCggICAAAAA==.',
Il='Ilocku:BAAANQAECgUIBgAAAQ==.',
In='Incubus:BAAANQAECgIIAgAAAA==.',
Io='Ionigvaah:BAAANQAECgUIBwAAAA==.',
Ir='Iriemon:BAAANQADCggIDgAAAA==.',
It='Italiaa:BAAANQADCggIDwAAAA==.',
Ix='Ixtel:BAAANQADCgMIAwAAAA==.',
Ja='Jawesome:BAAANQADCgUIBwAAAA==.',
Je='Jedakye:BAAANQADCggIDgAAAA==.Jeepers:BAAANQADCgQIBAAAAA==.Jenzypoo:BAAANQADCgUIBwAAAA==.Jetson:BAAANQAECgIIAgAAAA==.',
Jo='Jojo:BAAANQAECgUIBQAAAA==.',
Ju='Junnarma:BAAANQADCgMIBAAAAA==.',
['Já']='Járnviðr:BAAANQAECgQIBQAAAA==.',
Ka='Kaalias:BAAANQADCgcICAAAAA==.Kabrax:BAAANQADCggIBgAAAA==.Kai:BAAANQADCgYIBwABNQAECgcICQABAAAAAA==.Kaiula:BAAANQAECgYICAAAAA==.Kalabar:BAAANQAECgEIAQAAAA==.Kaldrys:BAAANQAECgQIBQAAAA==.Kalnath:BAAANQAECgQIBAAAAA==.Kalynnah:BAAANQADCgcIBwAAAA==.Kamî:BAAANQABCgIIAgABNQAECgEIAQABAAAAAA==.Kanarra:BAAANQADCggICAAAAA==.Kanatoo:BAAANQAECgQIBAAAAA==.Kanekisenpai:BAAANQAECgcICwAAAA==.Kanjam:BAAANQAECgIIAgAAAA==.Kaylina:BAAANQADCgQIBAAAAA==.Kazrar:BAAANQADCggIDwAAAA==.',
Ke='Keepupheals:BAAANQADCgEIAQAAAA==.Keid:BAAANQAECgEIAgAAAA==.Kelai:BAAANQAECggICQAAAA==.Kenobi:BAAANQADCgYIBgAAAA==.',
Ki='Kikks:BAAANQADCgEIAQAAAA==.Kilusuka:BAAANQADCgUIBQAAAA==.',
Ko='Kobarr:BAAANQAECgEIAQAAAA==.Konbo:BAAANQAECgIIAgAAAA==.Koro:BAAANQADCggIDgAAAA==.',
Kr='Krapshoot:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Krump:BAAANQAECgIIAgAAAA==.',
Ku='Kuramá:BAAANQAECgEIAQAAAA==.Kuzé:BAAANQAECgQIBAAAAA==.',
Kw='Kwyj:BAAANQADCgQIBQAAAA==.Kwyjibo:BAAANQAECgcICgAAAA==.',
Ky='Kylebroflov:BAAANQAECgEIAQAAAA==.Kyyguy:BAAANQADCgIIAgAAAA==.',
['Kï']='Kïllerfrost:BAAANQADCggIDQAAAA==.',
La='Lambofgods:BAAANQAECgMIBAAAAA==.Lanana:BAAANQADCgEIAQAAAA==.',
Le='Lencel:BAAANQADCgYICAAAAA==.Leonidas:BAAANQADCggICgAAAA==.Letmo:BAAANQADCgcICwAAAA==.Letmu:BAAANQADCgUIBAABNQADCgcICwABAAAAAA==.Levelfour:BAAANQADCgIIAgAAAA==.',
Li='Liannia:BAAANQADCgUIBwABNQADCgYICwABAAAAAA==.Lightningki:BAAANQADCggIDwAAAA==.Lightofdawn:BAAANQADCgMIAwAAAA==.Lightscream:BAAANQAECgQIBAAAAA==.Lilshoobs:BAAANQADCgcIDAAAAA==.Lindariel:BAAANQADCgMIAwAAAA==.Lindir:BAAANQAECgYIBwAAAA==.Liparoonie:BAAANQAECgEIAQAAAA==.Liyt:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.',
Lo='Lockedupfoo:BAAANQAECgYICgAAAA==.Locktorty:BAAANQADCgIIAgAAAA==.',
Lu='Lunah:BAAANQAECgQIBQAAAA==.Lupozz:BAAANQAECgIIAgAAAA==.',
['Lå']='Låb:BAAANQADCgMIAwAAAA==.',
Ma='Machahunt:BAAANQAECgEIAQAAAA==.Machico:BAAANQADCgUICAAAAA==.Magicdeadly:BAAANQAECgEIAQAAAA==.Magicol:BAAANQADCgUIBgABNQAECgIIAgABAAAAAA==.Magosika:BAAANQAECgEIAQAAAA==.Maledizione:BAAANQADCgUIBwAAAA==.',
Me='Meerahs:BAAANQAECgEIAQAAAA==.Megahorn:BAAANQAECgQIBAAAAA==.Megthpallion:BAAANQADCgQIBAAAAA==.',
Mi='Midliyt:BAAANQAECgMIAwAAAA==.Midniyt:BAAANQADCgQIBAABNQAECgMIAwABAAAAAA==.Mikaylla:BAAANQADCgQICAAAAA==.Mikkilina:BAAANQAECgEIAQAAAA==.Mitric:BAAANQADCggIEAAAAA==.',
Mm='Mmeow:BAAANQADCgYICwAAAA==.',
Mo='Moowarrior:BAAANQADCggIDgAAAA==.Mosswyn:BAAANQADCgYICwAAAA==.',
Mu='Murmaiderr:BAAANQADCgcIDQAAAA==.',
Na='Nalla:BAAANQADCgUIBQAAAA==.Naravia:BAAANQADCgcIDAAAAA==.Narunî:BAAANQADCgMIAwAAAA==.Nater:BAAANQADCgUIBQAAAA==.',
Ne='Nekkrosys:BAAANQAECgIIAgAAAA==.Nekrron:BAAANQADCgIIAgAAAA==.Neona:BAAANQADCgEIAQAAAA==.Nevets:BAAANQABCgMIAwAAAA==.',
Ni='Nicessus:BAAANQAECgUIBQAAAA==.Nicksys:BAAANQAECgMIAwAAAA==.Nikkanika:BAAANQADCgYIDAABNQAECgUIBQABAAAAAA==.Niuzao:BAAANQADCgEIAQAAAA==.',
No='Nork:BAAANQADCggIDwAAAA==.Norko:BAAANQADCgQIBAAAAA==.Normalname:BAAANQADCggICAAAAA==.Novembër:BAAANQADCgcIDAAAAA==.',
['Nÿ']='Nÿkon:BAAANQAECgEIAQAAAA==.',
Ok='Okishama:BAAANQAECgcICwAAAA==.',
On='Onkrack:BAAANQADCgcICAAAAA==.',
Op='Ophelastra:BAAANQAECgEIAQAAAA==.',
Oz='Ozfiz:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Ozwiz:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.',
Pa='Pandatastic:BAABNQAECoEWAAIDAAkJFSHYAACBAwADAAkJFSHYAACBAwAAAA==.Pastrami:BAAANQAECgMIAwAAAA==.Patbee:BAAANQADCgIIAwAAAA==.Pawn:BAAANQADCgIIAQAAAA==.',
Pe='Pearlsham:BAAANQADCggIEAAAAA==.Peekaaboo:BAAANQADCgQIBAAAAA==.',
Ph='Phikkle:BAAANQADCgQIBAAAAA==.Phâtè:BAAANQAECgIIAgAAAA==.',
Pi='Picesty:BAAANQAECgYICAABNQABCgEIAQABAAAAAA==.Pilikiä:BAAANQADCgcIBwAAAA==.',
Pk='Pkflash:BAAANQADCggICwAAAA==.',
Pl='Platinumbull:BAAANQAECgUIBgAAAA==.Pleabsham:BAAANQADCgcIDAAAAA==.',
Po='Pokentotem:BAAANQADCggIDwAAAA==.Potlogic:BAAANQAECgEIAQABNQAECgYIDAABAAAAAA==.',
Pr='Prosciutto:BAAANQABCgQIBgAAAA==.',
Pu='Puddl:BAAANQADCgcICgAAAA==.Punkii:BAAANQAECgUIBgAAAA==.',
Qp='Qpawnz:BAAANQADCgMIAwABNQAECgcICgABAAAAAA==.',
Qu='Quidamtyra:BAAANQADCggICwAAAA==.Quigonjin:BAAANQAECgEIAQAAAA==.',
Ra='Rackem:BAAANQADCgEIAQAAAA==.Rackham:BAAANQAECgcICwAAAA==.Radiana:BAAANQADCggIDgAAAA==.Raeknor:BAAANQADCgYIBgAAAA==.Randomaction:BAAANQAECgEIAQAAAA==.Rathvyr:BAAANQAECggIDgAAAA==.Razuriell:BAAANQAECgYIBgAAAA==.',
Re='Reagan:BAAANQABCgIIAgAAAA==.Rebeakah:BAAANQAECgIIAgAAAA==.Reggs:BAAANQADCgcICwAAAQ==.Renko:BAAANQAECgMIAwAAAA==.',
Ri='Ribitey:BAAANQAECgcIDAAAAA==.Riggs:BAAANQADCgYICwAAAA==.Riggster:BAAANQAECgQIBQAAAA==.Rilakuma:BAAANQADCgYIBgAAAA==.',
Ro='Rolando:BAAANQAECgYICgAAAA==.Rosybel:BAAANQADCgQIBAAAAA==.Rotimus:BAAANQADCgIIAgAAAA==.Rozewyn:BAAANQAECgIIAgAAAA==.',
Ru='Rukator:BAAANQADCgYIDAAAAA==.',
Ry='Ryawhitefang:BAAANQAECgYIBgAAAA==.',
['Rà']='Ràgé:BAAANQADCgYICgAAAA==.',
Sa='Salael:BAAANQAECgYICQAAAA==.Saphirin:BAAANQAECgcIDQAAAA==.Sariphi:BAAANQADCgQIBAAAAA==.Sauron:BAAANQADCggICgAAAA==.Savagebrain:BAAANQADCgUIBQABNQAECgUIBQABAAAAAA==.Savagelung:BAAANQAECgUIBQAAAA==.',
Sc='Schoonie:BAAANQADCgYIBgAAAA==.Schutzengel:BAAANQAECgcICgAAAA==.Scribbl:BAAANQAECgUIBgAAAA==.Scylon:BAAANQADCgYIBgAAAA==.Scythen:BAAANQADCgYIBgAAAA==.',
Se='Sencerity:BAAANQADCgEIAQAAAA==.Serana:BAAANQADCggIDgAAAA==.',
Sh='Shadowbanned:BAAANQADCgUIBQAAAA==.Shallowgrave:BAAANQAECgQIBQAAAA==.Shammyhaggar:BAAANQADCggIDgAAAA==.Shamram:BAAANQADCggICAAAAA==.Shamywamy:BAAANQAECgIIAwAAAA==.Shaodh:BAAANQADCgUIBQAAAA==.Shaodk:BAAANQAECgcIAgAAAA==.Shibs:BAAANQADCgQIBAAAAA==.Shiffty:BAAANQADCggICAAAAA==.Shiggadin:BAAANQAECgEIAQAAAA==.Shikki:BAAANQAECgIIAgAAAA==.Shinys:BAAANQADCggICwABNQAECgEIAQABAAAAAA==.Shuki:BAAANQADCgEIAQAAAA==.Shäde:BAAANQAECgYICQAAAA==.',
Si='Simpai:BAAANQADCggIDgAAAA==.Sinzspirits:BAAANQADCgIIAgAAAA==.',
Sk='Skiethx:BAAANQAECgUICAAAAA==.Skipii:BAAANQADCggICwAAAA==.Skullderzix:BAAANQAECgMIAwAAAA==.',
Sl='Slopersafari:BAAANQAECgIIAgAAAA==.Slowqt:BAAANQAECggIDAAAAA==.',
Sm='Smashyz:BAAANQADCgYIBgABNQADCgYIBgABAAAAAA==.',
So='Somaria:BAAANQADCgYICgAAAA==.',
Sp='Spankybottom:BAAANQADCggIDgAAAA==.Sparykz:BAAANQADCgYIBgABNQADCggIDQABAAAAAA==.Spnkynvrsoft:BAAANQAECgUIBgAAAA==.',
Sq='Squee:BAAANQADCggIDgAAAA==.Squirts:BAAANQAECgIIAgAAAA==.',
Sr='Srmonkey:BAAANQADCggIDQAAAA==.',
St='Stabachacha:BAAANQAECgcICgAAAA==.Steamicyhott:BAAANQADCgUIBQAAAA==.Stgmavrick:BAAANQADCggIDAAAAA==.Stinkie:BAAANQAECgYICQAAAA==.Stonebeard:BAAANQADCgYIBgAAAA==.Stormcore:BAAANQADCgYIBgAAAA==.',
Su='Sunny:BAAANQADCgUICgAAAA==.Supernóva:BAAANQADCgEIAQABNQADCggICgABAAAAAA==.',
Sy='Sylverarrow:BAAANQADCgcICwAAAA==.Syreith:BAAANQADCgEIAQAAAA==.',
Ta='Tacabell:BAAANQAECgQIBAAAAA==.Taken:BAAANQAECgYICAAAAA==.Tarkarram:BAAANQADCgcICAAAAA==.Tarnfair:BAAANQADCgUICAAAAA==.Taurìel:BAAANQADCggIDgAAAA==.Taven:BAAANQAECgEIAQAAAA==.',
Te='Technique:BAAANQADCgcIBwAAAA==.Tekka:BAAANQADCggIDgAAAA==.Telegram:BAAANQADCgIIAgAAAA==.Telvor:BAAANQADCggICAAAAA==.Terrukk:BAAANQADCgYICwAAAA==.Teufelsnudel:BAAANQAECgIIAgAAAA==.',
Th='Theliver:BAAANQADCggICQAAAA==.Thelysong:BAAANQADCgYICAAAAA==.Therran:BAAANQAECgUIBQAAAA==.Theuss:BAAANQADCgYICgAAAA==.Thexador:BAAANQADCgUICgAAAA==.Thorraden:BAAANQABCgIIAgABNQADCggIDQABAAAAAA==.Thranduill:BAAANQADCggIDgAAAA==.',
Ti='Tidefury:BAAANQADCgcIBwAAAA==.Tidepod:BAAANQAECgYIBgABNQAECggIDAABAAAAAA==.Tigerclaw:BAAANQADCgMIAwAAAA==.Tilley:BAAANQADCgYICwAAAA==.Tingaling:BAAANQAECgEIAQAAAA==.',
Tl='Tlock:BAAANQADCgcIBwABNQADCgcICAABAAAAAA==.',
To='Toothlss:BAAANQADCgUICAABNQADCgYIBQABAAAAAA==.Totums:BAAANQADCgYIBgAAAA==.Toyletpaypah:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.',
Tr='Trashyz:BAAANQAECgEIAQABNQADCgYIBgABAAAAAA==.Treseme:BAAANQABCgIIAgAAAA==.Triaradea:BAAANQADCgUIBgAAAA==.Tribalz:BAAANQAECgIIAgAAAA==.Trunddle:BAAANQAECgQIBAAAAA==.',
Tu='Tuchmydemons:BAAANQADCggIDgAAAA==.',
Ty='Tygrelilly:BAAANQADCgYICwAAAA==.Tyrieal:BAAANQADCgcIDAAAAA==.',
Ul='Ulidan:BAAANQADCgIIAgAAAA==.',
Un='Ungoloth:BAAANQADCgMIAwABNQADCggICAABAAAAAA==.',
Va='Vamp:BAAANQADCggIDwAAAA==.Vanêssa:BAAANQADCgcIDAAAAA==.Varner:BAAANQAECgUIBQAAAA==.',
Vi='Vindict:BAAANQADCgEIAQAAAA==.',
Vl='Vlakshift:BAAANQAECgIIAgAAAA==.',
Vo='Voltedrage:BAAANQAECgYIBgAAAA==.Vongalas:BAAANQADCggICwAAAA==.Vongimi:BAAANQAECgMIAQAAAA==.Vongimiv:BAAANQADCgYIDAABNQAECgMIAQABAAAAAA==.Voucher:BAAANQAECgcICgAAAA==.',
Vy='Vyn:BAAANQADCgQIBAAAAA==.Vynstarcyon:BAAANQADCgMIAwAAAA==.Vysérå:BAAANQADCggIDgAAAA==.',
Wa='Wai:BAAANQAECgUIBgAAAA==.Warglaíve:BAAANQAECgUIBgAAAA==.Wasted:BAAANQAECgEIAQAAAA==.',
Wh='Whilson:BAAANQADCgYICwAAAA==.',
Wi='Wildbillee:BAAANQADCgYIDAABNQAECgYIDAABAAAAAA==.Wildbilly:BAAANQAECgQIBQABNQAECgYIDAABAAAAAA==.Wildbily:BAAANQADCgQIBAABNQAECgYIDAABAAAAAA==.Wilhson:BAAANQADCgEIAQABNQADCgYICwABAAAAAA==.Winterveil:BAAANQADCgEIAQAAAA==.Witchblade:BAAANQADCgEIAQABNQADCggIDgABAAAAAA==.',
Wo='Worldwaker:BAAANQAECgUIBgAAAA==.Wornn:BAAANQADCgUIBQAAAA==.',
Wr='Wretched:BAAANQAECgUICAAAAA==.',
Wu='Wukard:BAAANQADCggIDgAAAA==.',
Wy='Wylblly:BAAANQADCgYIBgABNQAECgYIDAABAAAAAA==.Wyldbill:BAAANQAECgYIDAAAAA==.',
Xa='Xarxzez:BAAANQAECgEIAQAAAA==.',
Xe='Xer:BAAANQABCgQIBAAAAA==.',
Xf='Xfaeble:BAAANQAECgQIBwABNQAECgYICQABAAAAAA==.',
Xg='Xgambit:BAAANQAECgQIBQAAAA==.',
Xp='Xprtdemon:BAAANQADCgcIDAAAAA==.',
Xy='Xylar:BAAANQADCgUIBQAAAA==.Xyno:BAAANQAECgIIAgAAAA==.',
Yo='Yoggibear:BAAANQADCgcIBwAAAA==.Yoreick:BAAANQADCgUIBQAAAA==.',
Yu='Yuckmouth:BAAANQAECgYIDAAAAA==.Yuli:BAAANQAECgMIAwABNQAECgMIBQABAAAAAA==.',
Za='Zadaen:BAAANQADCggIDgAAAA==.Zaladren:BAAANQAECgEIAQAAAA==.',
Ze='Zenshot:BAAANQAECgEIAQAAAA==.Zerazenazath:BAAANQADCgIIAgAAAA==.',
Zo='Zoobra:BAAANQADCgUIBQAAAA==.',
Zu='Zubinator:BAAANQADCgYIDAAAAA==.',
['Ác']='Áchu:BAAANQAECgQIBAAAAA==.',
['Âr']='Ârrgh:BAAANQAECgMIAwAAAA==.',
['Än']='Änh:BAAANQADCggIDwAAAA==.',
['Ðe']='Ðestroyer:BAAANQADCgcIBwAAAA==.',
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
