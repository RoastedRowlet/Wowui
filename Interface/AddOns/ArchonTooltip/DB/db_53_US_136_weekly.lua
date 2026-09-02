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
local provider = {region='US',realm='Korgath',name='US',type='weekly',zone=53,date='2026-09-01',data={Ab='Abbygrace:BAAANQAECgEIAQAAAA==.',
Ad='Adar:BAAANQADCggIDQAAAA==.',
Ae='Aegeis:BAAANQADCgcIBwABNQAECgIIAgABAAAAAA==.Aelaryn:BAAANQADCgcICAAAAA==.',
Af='Afterearth:BAAANQAECgcICgAAAA==.',
Ag='Aggrobeast:BAAANQADCgYICwAAAA==.Agoný:BAAANQADCgQIBAAAAA==.',
Ai='Ailie:BAAANQAECgQIBAAAAA==.',
Ak='Akadey:BAAANQADCgYICAAAAA==.',
Al='Aliì:BAAANQADCggIDQABNQAECgcICgABAAAAAA==.Allise:BAAANQADCgIIAQAAAA==.Allnightløng:BAAANQAECgEIAQAAAA==.Alverez:BAAANQAECgcICgAAAA==.',
Am='Amorilas:BAAANQAECgQIBgAAAA==.Amunera:BAAANQADCgUIBQABNQADCgYICAABAAAAAA==.',
An='Andersan:BAAANQAECgQICgAAAA==.Anetharion:BAAANQAECgEIAQAAAA==.Animalchange:BAAANQAECgIIAgAAAA==.',
Ap='Apeth:BAAANQADCgEIAQAAAA==.Applepi:BAAANQADCgYIDAAAAA==.Aproditee:BAAANQADCgMIAwAAAA==.',
Ar='Arborhealz:BAAANQADCgIIAQAAAA==.Areayl:BAAANQAECgMIAwAAAA==.Arinn:BAAANQAECgcICgAAAA==.',
As='Ashtkal:BAAANQAECgQIBQAAAA==.Ashtoes:BAAANQADCgUIBQAAAA==.Astralbubble:BAAANQAECgQIBAAAAA==.',
Au='August:BAAANQADCgcICAAAAA==.',
Av='Avalea:BAAANQADCgIIAgAAAA==.',
Ay='Ayyvlaad:BAAANQAECgMIBAAAAA==.',
Az='Azerlite:BAAANQADCgEIAQABNQAECgYICAABAAAAAA==.Azkota:BAAANQADCggIDwAAAA==.Azulwall:BAAANQADCggICwAAAA==.Azureros:BAAANQAECgIIAgAAAA==.',
Ba='Bandaayd:BAAANQAECgEIAQAAAA==.Bathasar:BAAANQADCgUIBwAAAA==.Bathpally:BAAANQADCggICQAAAA==.',
Be='Beandh:BAAANQADCggIEAABNQAECgcIDAABAAAAAA==.Beastfury:BAAANQAECgEIAQAAAA==.Beefyclap:BAAANQADCgYIBgAAAA==.Beha:BAAANQADCgEIAQAAAA==.Beleria:BAAANQADCgMIAwAAAA==.Bellaidd:BAAANQAECgUIBQAAAA==.Bellore:BAAANQADCgQIBAAAAA==.Bewblywoobly:BAAANQADCgYICgAAAA==.Bezvoker:BAAANQADCgUIBQAAAA==.Beástboy:BAAANQADCggICgAAAA==.',
Bi='Biekdafreak:BAAANQADCgUIBgAAAA==.Bigdaddoo:BAAANQADCgUIBQAAAA==.Biggisign:BAAANQADCgYIDAAAAA==.Bitemenow:BAAANQADCgMIBgAAAA==.Bitsobacon:BAAANQADCggIDgAAAA==.Bizzó:BAAANQADCgcIBwAAAA==.',
Bl='Blambussi:BAAANQADCgUIBQAAAA==.Blitzball:BAAANQADCgYIBgAAAA==.Blooddragoon:BAAANQAECgEIAQAAAA==.Bloodycrow:BAAANQABCgMIAwAAAA==.',
Bo='Bohica:BAAANQAECgQIBAAAAA==.Bombadil:BAAANQAECgQIBAAAAA==.Bomberdeath:BAAANQADCgcIBwAAAA==.Bongrip:BAAANQADCgYICgAAAA==.Boochstorm:BAAANQADCgYIBgAAAA==.Boogiee:BAAANQADCgcIDQABNQAECgEIAQABAAAAAA==.',
Br='Bradington:BAAANQADCgcIDQAAAA==.Brezel:BAAANQADCgYIBgAAAA==.Brond:BAAANQABCgIIAgAAAA==.Brontide:BAAANQADCgcIDAAAAA==.Bruengar:BAAANQAECgMIAwAAAA==.Bruniik:BAAANQADCgcIDgAAAA==.',
Bu='Bubblehêarth:BAAANQADCgUIBQAAAA==.Budapest:BAAANQAECgQIBAAAAA==.Buddyolpal:BAAANQADCgYICwAAAA==.Bullistic:BAAANQADCggICAAAAA==.Bumbleh:BAAANQADCggIDgAAAA==.Bumibe:BAAANQADCgcIBwAAAA==.Bungulator:BAAANQAECgYICAAAAA==.Buné:BAAANQAECgQIBAAAAA==.',
Ca='Caad:BAAANQADCgcICQAAAA==.Cador:BAAANQAECgEIAgAAAA==.Cadwarr:BAAANQADCgYIBgAAAA==.Cam:BAAANQAECgMIBQAAAQ==.Cannibubz:BAAANQADCggIDgAAAA==.Cannimal:BAAANQAECgYICgAAAA==.Cataylst:BAAANQADCgIIAQABNQADCgIIAgABAAAAAA==.Catwilliams:BAAANQAECgQIBgAAAA==.',
Ce='Celestas:BAAANQADCgIIAgAAAA==.',
Ch='Chadreaper:BAAANQABCgEIAQAAAA==.Cheeze:BAAANQADCgMIBAAAAA==.Chiliwop:BAAANQAECgEIAQAAAA==.Chloei:BAAANQADCgIIAQAAAA==.Chwonk:BAAANQADCggIDQAAAA==.',
Ci='Circê:BAAANQADCgUIBQAAAA==.',
Cl='Clevoker:BAAANQAECgUIBgAAAA==.Clusion:BAAANQADCgYIBgAAAA==.',
Co='Codex:BAAANQADCggIDwAAAA==.Cole:BAAANQADCgMIBAAAAA==.Conductor:BAAANQAECgIIAgAAAA==.Convergent:BAAANQAECgMIBAAAAA==.Coosh:BAAANQAECgcICgAAAA==.Corov:BAAANQADCgUIBQAAAA==.',
Cp='Cptamerica:BAAANQAECgIIAwAAAA==.',
Cr='Craigolas:BAAANQADCgcIBwAAAA==.Crippler:BAAANQADCgIIAgAAAA==.Crossbow:BAAANQADCgMIAwAAAA==.Crosscut:BAAANQAECgEIAQAAAA==.',
Cu='Cummins:BAAANQAECgYICAAAAA==.',
Da='Dadstealer:BAAANQADCgYICwAAAA==.Dagrundel:BAAANQADCgcIDAAAAA==.Dalinarix:BAAANQADCgcICQAAAA==.Dankpope:BAAANQAECgIIAgAAAA==.Davrin:BAAANQAECgQIBAAAAA==.',
De='Deathbyarow:BAAANQADCgcIDAAAAA==.Deathhammer:BAAANQADCgYICwAAAA==.Deathjrak:BAAANQAECgMIAgAAAA==.Deesixxfour:BAAANQADCgUIBQAAAA==.Degates:BAAANQADCggIDgAAAA==.Demonia:BAAANQAECgEIAgAAAA==.Demonicshoes:BAAANQADCgcIDAAAAA==.Dethwing:BAAANQAECgEIAQAAAA==.Devaña:BAAANQADCgYIDAAAAA==.',
Di='Diclonius:BAAANQADCggIDAAAAA==.Dirtystaff:BAAANQADCgcICwAAAA==.Dirtzmage:BAAANQADCggIDgAAAA==.Dizzledh:BAAANQADCgUIBQAAAA==.',
Dj='Djkhaledd:BAAANQAECgEIAQAAAA==.',
Do='Doobins:BAAANQADCggIDQAAAA==.Dookiboy:BAAANQADCgYIBgABNQAECgUICQABAAAAAA==.Douii:BAAANQADCggICAAAAA==.',
Dr='Draco:BAAANQABCgQIBAAAAA==.Dragao:BAAANQADCgYIBgAAAA==.Draggen:BAAANQAECgIIAgAAAA==.Dragimal:BAAANQADCgYIDAAAAA==.Dragonn:BAAANQAECgQIBAAAAA==.Dragosia:BAAANQAECgQIBQAAAA==.Drakojangens:BAAANQAECgUIBQAAAA==.Drakthar:BAAANQADCgUIBQAAAA==.Dranoric:BAAANQADCgUIBQAAAA==.Drlawyerphd:BAAANQAECgQIBAAAAA==.Druz:BAAANQADCggIDAAAAA==.',
Ds='Dsixxfour:BAAANQAECgQIBAAAAA==.',
Du='Dunzjan:BAAANQAECgEIAQAAAA==.',
Dy='Dysmai:BAAANQADCgUIBQAAAA==.',
['Dé']='Déathwolf:BAAANQAECgMIAwAAAA==.',
Ea='Eatsammich:BAAANQADCgcIBwAAAA==.',
Eg='Eggsbenedïct:BAAANQAECgMIAwAAAA==.Egol:BAAANQAECgQIBQAAAA==.',
El='Eldonra:BAAANQADCgYIBgABNQAECgcICwABAAAAAA==.Elidrine:BAAANQADCgUIBQAAAA==.Elmerfuddz:BAAANQADCggICQAAAA==.Elyrayldin:BAAANQADCggIDQAAAA==.',
En='Enazenoth:BAAANQAECggICAAAAA==.Enryu:BAAANQADCgcIBwAAAA==.Envburnz:BAAANQADCggIDgAAAA==.',
Er='Erooka:BAAANQAECgMIAwAAAA==.',
Es='Esio:BAAANQAECgQIBAAAAA==.',
Ey='Eyri:BAAANQAECgQIBAAAAA==.',
Ez='Ezzie:BAAANQADCggIDAAAAA==.',
Fa='Falsodew:BAAANQAECgYIBwAAAA==.',
Fe='Felicity:BAAANQAECgEIAQAAAA==.Femmever:BAAANQADCgYIBQAAAA==.Feonix:BAAANQAECgUIBgAAAA==.Ferenus:BAAANQABCgQIBAAAAA==.Fewsha:BAAANQAFFAIIAwAAAA==.',
Fi='Fidellia:BAAANQADCgcIDQAAAA==.Findie:BAAANQADCggIDQAAAA==.',
Fo='Foofoolala:BAAANQABCgQIBAAAAA==.Fookadk:BAAANQADCgUIBQAAAA==.Fookapalli:BAAANQABCgQIBAAAAA==.Forttoo:BAAANQADCgEIAQAAAA==.',
Fr='Frawstbyte:BAAANQAECgUIBgAAAA==.Freeholed:BAAANQAECgQIBAAAAA==.Fridgefister:BAAANQADCggIDwAAAA==.Frodie:BAAANQAECgEIAQAAAA==.',
Ga='Gaea:BAAANQADCggIDwAAAA==.Gangrêl:BAAANQADCgQIBgABNQADCgYICAABAAAAAA==.',
Gb='Gbang:BAAANQADCgYICAAAAA==.',
Ge='Gekidoryu:BAAANQADCgQIBAABNQADCgYIBgABAAAAAA==.Gerebert:BAAANQADCggIDQAAAA==.Getajobubum:BAAANQAECgIIAgAAAA==.',
Gh='Ghostdance:BAAANQAECgcICwAAAA==.Ghoulia:BAAANQADCgUIBgAAAA==.',
Gi='Giggz:BAAANQADCggIDQAAAA==.Gingerpala:BAAANQADCgMIAwAAAA==.Giuttrix:BAAANQADCgUICQAAAA==.',
Gl='Gloriousdead:BAAANQADCgYIBgAAAA==.Glowing:BAAANQADCgYICwAAAA==.',
Go='Gokukakarot:BAAANQADCgYIBgAAAA==.Goldlore:BAAANQADCgYIBgAAAA==.Goopdk:BAAANQADCgYICwAAAA==.Gothikia:BAAANQADCggIDQAAAA==.',
Gr='Gremhunt:BAAANQADCgEIAQAAAA==.Grondel:BAAANQADCgYICQAAAA==.Grumpybear:BAAANQADCgYIBgAAAA==.',
Gu='Gundham:BAAANQADCgcICwAAAA==.Gunko:BAAANQABCgIIAgAAAA==.Gunstrong:BAAANQADCggIDQAAAA==.',
Ha='Haagendots:BAAANQADCggIDAAAAA==.Hairofwar:BAAANQAECgMIAwAAAA==.Haleynicole:BAAANQADCggIDAAAAA==.Happydaug:BAAANQADCgQIBAABNQAECgQIBgABAAAAAA==.Happydawg:BAAANQAECgQIBgAAAA==.Hasted:BAAANQAECgYICgAAAA==.Hawktar:BAAANQADCggIEAAAAA==.',
He='Healimus:BAAANQAECgMIAwAAAA==.Healmates:BAAANQAECgMIAwAAAA==.Helix:BAAANQAECgUICAAAAA==.Hennybull:BAAANQADCgIIAgAAAA==.',
Hm='Hmmfock:BAAANQADCggICAAAAA==.',
Ho='Ho:BAAANQAECgcIBwAAAA==.Holybrute:BAAANQAECgIIAwAAAA==.Holybunger:BAAANQADCgcICwAAAA==.Holysheetz:BAAANQABCgQIBAAAAA==.Horde:BAAANQADCgYIBgAAAA==.',
Hu='Hueycheeks:BAAANQAECgUIBQAAAA==.Huntstatus:BAAANQAECggIDAAAAA==.Huxium:BAAANQAECgQIBAAAAA==.',
Hy='Hymnpossible:BAAANQADCgcIDAAAAA==.',
Ic='Icetongue:BAAANQADCggIDwAAAA==.',
If='Iflingpoo:BAAANQAECgYICgAAAA==.Ifusêekamy:BAAANQADCgcICwAAAA==.',
Ij='Ijrakwarrior:BAAANQAECgIIAgAAAA==.',
Im='Impulse:BAAANQAECgIIAgAAAA==.',
Ir='Irmengaud:BAAANQADCgcIBwAAAA==.',
Ja='Jabbyjr:BAAANQAECgUIBQAAAA==.Jabum:BAAANQAECgIIAgAAAA==.Jajakuna:BAAANQADCgcIBwAAAA==.Jangens:BAAANQAECgIIAgABNQAECgUIBQABAAAAAA==.Jaruni:BAAANQAECgMIAwAAAA==.Jaynine:BAAANQAECgQIBAAAAA==.',
Je='Jeffvyrt:BAAANQAECgMIAwAAAA==.',
Ji='Jibbs:BAAANQADCgYICAAAAA==.',
Jo='Jodimaw:BAAANQADCgQIBAAAAA==.Jorian:BAAANQADCgIIAgAAAA==.Joridiezs:BAAANQADCggICwAAAA==.Joshness:BAAANQADCgMIAwAAAA==.',
Ju='Juanrambo:BAAANQADCgYICgAAAA==.Jumblo:BAAANQADCggIDAAAAA==.Jupileo:BAAANQAECgIIAgAAAA==.Jurassichots:BAAANQADCgYIBgAAAA==.',
Ka='Kailee:BAAANQAFFAEIAQABNQAECgEIAQABAAAAAA==.Kariba:BAAANQADCgYIBgAAAA==.Katael:BAAANQADCgYICwAAAA==.Kavel:BAAANQAECgQICAAAAA==.Kaylie:BAAANQAECgEIAQAAAA==.Kayti:BAAANQADCggIDQAAAA==.',
Ke='Kelfiona:BAAANQADCgUIBwAAAA==.Keraboo:BAAANQADCgcIDQAAAA==.Kerie:BAAANQADCgYIBgAAAA==.Ketamyne:BAAANQADCgYIBgAAAA==.',
Ki='Kiandron:BAAANQADCgYICAAAAA==.Killerqtlol:BAAANQADCgQIBQABNQAECgIIAgABAAAAAA==.',
Kn='Knockbak:BAAANQADCgYIBQAAAA==.',
Ko='Kohko:BAAANQADCgYIBgAAAA==.Kozinirus:BAAANQADCgcIBwAAAA==.',
Kq='Kqmav:BAAANQADCggIDgAAAA==.',
Kr='Kruwll:BAAANQADCggIDwAAAA==.Krít:BAAANQADCgIIAgABNQADCgQIBAABAAAAAA==.',
Ku='Kumolock:BAAANQADCggIDwAAAA==.Kuongsun:BAAANQADCggIDgAAAA==.',
['Kú']='Kúrama:BAAANQABCgMIBAAAAA==.',
La='Ladeehunter:BAAANQADCggIDwAAAA==.Lanto:BAAANQADCgMIAwABNQABCgIIAgABAAAAAA==.Laquince:BAAANQADCggIDQAAAA==.Lasagnazaddy:BAAANQADCgYICwAAAA==.Laurafel:BAAANQADCgUIBQAAAA==.',
Le='Lelouché:BAAANQABCgIIAgABNQABCgMIBAABAAAAAA==.Lertglochen:BAAANQAECgMIAwAAAA==.',
Li='Lightcast:BAAANQAECgEIAQABNQAECgcIDAABAAAAAA==.Limeywater:BAAANQAECgIIAgAAAA==.Litherous:BAAANQAECgMIAwAAAA==.Litzdh:BAAANQADCgYICwAAAA==.',
Ll='Llazereth:BAAANQAECgQIBAAAAA==.',
Lo='Lockimar:BAEANQAECgQIBAAAAA==.Lockuru:BAAANQAECgUIBQAAAA==.Lonestàr:BAAANQADCgcIDAAAAA==.Lowiqslowirl:BAAANQABCgIIAgAAAA==.',
Lu='Lucidy:BAAANQAECgMIAwAAAA==.Lumberjacked:BAAANQADCgIIAgABNQAECgcICwABAAAAAA==.Luna:BAAANQADCgUIBwABNQAECgQIBAABAAAAAA==.Lusuffer:BAAANQAECgQIBAAAAA==.Lusufferr:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.Lutra:BAAANQAECgMIAwAAAA==.',
Ly='Lyx:BAAANQADCgcIDAAAAA==.',
Ma='Magerpwn:BAAANQADCgUIBQAAAA==.Makrio:BAAANQABCgMIAwAAAA==.Malachî:BAAANQADCgYIBgAAAA==.Malitan:BAAANQAECgUICQAAAA==.Mamif:BAAANQADCggIDAAAAA==.Mannasto:BAAANQADCgYIBgAAAA==.Manuelek:BAAANQADCgYICQAAAA==.Markatron:BAAANQAECgUIBQAAAA==.Mattiekay:BAAANQAECgMIAwAAAA==.Maxx:BAAANQADCgcIBwAAAA==.Mañajuana:BAAANQAECgMIAwAAAA==.',
Me='Meatrocket:BAAANQADCgYIBgABNQAECgUIBgABAAAAAA==.Meefalo:BAAANQADCgcIBwAAAA==.Meggfox:BAAANQADCgQIBAAAAA==.Meghanics:BAAANQADCgYIDAAAAA==.Menethol:BAAANQADCgUIBQAAAA==.Merie:BAAANQADCgQIBAABNQADCggIDwABAAAAAA==.Merlinswrath:BAAANQADCgUIBAAAAA==.Merzinator:BAAANQAECgcIBwAAAA==.',
Mi='Midgrad:BAAANQADCggIDgAAAA==.Mikelowry:BAAANQADCggIDQAAAA==.Minimum:BAAANQAECgIIAgAAAA==.Mischeveous:BAAANQADCgcICgAAAA==.Mithrandir:BAAANQAECgEIAQAAAA==.',
Mj='Mjiltanke:BAAANQADCgcIDQAAAA==.',
Mo='Moistcarry:BAAANQADCgUIBQAAAA==.Mokniahiah:BAAANQAECgEIAQAAAA==.Monkmates:BAAANQAECgEIAQAAAA==.Moodoon:BAAANQADCgcICwAAAA==.Mooseyfate:BAAANQADCgYICQAAAA==.Moraxy:BAAANQADCgcIDQAAAA==.Moromagus:BAAANQAECgQIBgAAAA==.',
Mu='Murdok:BAAANQADCggICAAAAA==.Mutknodeprac:BAAANQADCggIDAAAAA==.',
Mx='Mxsery:BAAANQADCgYICQAAAA==.Mxz:BAAANQADCgcIBwABNQAECgYICAABAAAAAA==.',
My='Myræl:BAAANQADCgcICwAAAA==.Mystíle:BAAANQAECgcICwAAAA==.Mythrixx:BAAANQADCgQIBwAAAA==.',
['Mà']='Màjíque:BAAANQADCgYIBQAAAA==.',
['Mé']='Méadow:BAAANQADCgUIBwAAAA==.',
Na='Nabesan:BAAANQADCgIIAgAAAA==.Naked:BAAANQADCggIBAAAAA==.Narhi:BAAANQADCggIDAAAAA==.Nasminthe:BAAANQADCgcICwAAAA==.Nature:BAAANQADCgUIBQAAAA==.Naughtya:BAAANQADCgYIBgAAAA==.',
Ne='Nekoro:BAAANQAECgIIAwABNQAECgIIAwABAAAAAA==.Nelfsquantch:BAAANQADCgcIDAAAAA==.Nevadawolf:BAAANQADCgcICAAAAA==.',
Ni='Nightreaver:BAAANQADCgUICQAAAA==.Nightshiftér:BAAANQAECgEIAQAAAA==.Ninetailsfox:BAAANQAECgUICQAAAA==.Nion:BAAANQADCggIDwAAAA==.',
No='Nolo:BAAANQADCgQIBQAAAA==.Northzen:BAAANQAECgMIAwAAAA==.Notaorc:BAAANQADCgUIBQAAAA==.Novaflux:BAAANQAECgQIBAAAAA==.Noxxicc:BAAANQADCgYICwAAAA==.',
Ny='Nyghtterror:BAAANQADCgYICAAAAA==.Nyreeh:BAAANQADCgcICwAAAA==.Nytearcher:BAAANQAECgIIAgAAAA==.Nyxa:BAAANQADCgcICwAAAA==.',
['Ná']='Nálera:BAAANQADCggICAAAAA==.',
Ok='Okamifist:BAAANQADCgYIBgAAAA==.Oklyra:BAAANQABCgQIBAAAAA==.',
Om='Omnia:BAAANQAECgQIBAABNQABCgMIAwABAAAAAA==.',
On='Onlyshams:BAAANQADCgMIAwAAAA==.',
Oo='Oogiee:BAAANQAECgEIAQAAAA==.',
Or='Orcmonk:BAAANQADCgMIAwAAAA==.',
Os='Oschun:BAAANQAECgQIBQAAAA==.',
Pa='Palacandia:BAAANQADCgYIBQAAAA==.Palanar:BAAANQAECgUIBgAAAA==.Pallyboi:BAAANQADCggIDgAAAA==.Paluru:BAAANQAECgEIAQABNQAECgUIBQABAAAAAA==.Panosh:BAAANQADCgUIBQAAAA==.',
Pc='Pchef:BAAANQAECgEIAQAAAA==.',
Pe='Pelayo:BAAANQADCgcICQAAAA==.Peperoninips:BAAANQADCgQICAAAAA==.Petricia:BAAANQAECgIIAgAAAA==.',
Pf='Pfeffer:BAAANQADCgcIDAAAAA==.',
Ph='Phaithful:BAAANQAECgcIDQAAAA==.Phazerman:BAAANQADCgUIBQAAAA==.Phocus:BAAANQADCgcIDAABNQAECgcIDQABAAAAAA==.Phury:BAAANQADCggICwABNQAECgcIDQABAAAAAA==.',
Pi='Pikapikapika:BAAANQADCggIDwAAAA==.',
Pl='Planthoofem:BAAANQADCgIIAQAAAA==.Playpride:BAAANQADCgYIBQAAAA==.',
Po='Poboy:BAAANQAECgIIAgAAAA==.Pocket:BAAANQADCgQICAABNQAECgQIBAABAAAAAA==.Pokepokepoke:BAAANQADCggIDgAAAA==.Poppop:BAAANQADCgYICwAAAA==.Poriand:BAAANQADCgEIAQAAAA==.Portzul:BAAANQADCggIDwAAAA==.',
Pr='Priesttea:BAAANQADCgIIAgAAAA==.',
Ps='Pseudogrim:BAAANQAECgMIAwAAAA==.Psspspss:BAAANQADCgYIBgAAAA==.',
Pu='Pugnosano:BAAANQADCgQIBAAAAA==.',
Ra='Raefe:BAAANQADCgUIBQAAAA==.Raffaj:BAAANQADCggIDAAAAA==.Raidedww:BAAANQADCgUIBQAAAA==.Raihnese:BAEANQADCgYICQAAAA==.Ramenveg:BAAANQADCgcIDQAAAA==.Ravnwing:BAAANQADCgcICAAAAA==.',
Re='Reapersbless:BAAANQADCgQIBAAAAA==.Reapersbount:BAAANQADCgIIAgABNQADCgQIBAABAAAAAA==.Reapersele:BAAANQADCgMIAwABNQADCgQIBAABAAAAAA==.Redbuffpls:BAAANQAECgcICwAAAA==.Redbul:BAAANQAECgEIAQAAAA==.Reddrock:BAAANQADCgEIAQAAAA==.Redstörm:BAAANQADCgcIBwAAAA==.Reffusul:BAAANQADCgQIBAABNQAECgQIBAABAAAAAA==.Reptilia:BAAANQAECgQIBQAAAA==.Resurge:BAAANQADCgQIBAAAAA==.Rewef:BAAANQADCggICAABNQAFFAIIAwABAAAAAA==.Rex:BAAANQAECgQIBAAAAA==.',
Ri='Riffz:BAAANQAECgUIBgAAAA==.Rig:BAAANQADCgYICwAAAA==.Rinzsha:BAAANQADCgYICwAAAA==.Rishka:BAAANQADCgUIBQAAAA==.',
Ro='Rockhard:BAAANQABCgEIAQAAAA==.Roostersauce:BAAANQADCgYIBgAAAA==.Rosare:BAAANQADCgEIAQAAAA==.',
Ru='Ruhkouri:BAAANQADCgcICwAAAA==.Rustibox:BAAANQAFFAEIAQAAAA==.',
Sa='Samardev:BAAANQADCgYIBgABNQAECgYICQABAAAAAA==.Sammichomg:BAAANQAECgQIBAAAAA==.Sammyfuego:BAAANQADCggIDAAAAA==.',
Sc='Scalestas:BAAANQAECgMIAwAAAA==.',
Se='Searing:BAAANQAECgYICgAAAA==.Segfaulted:BAAANQADCgIIAgAAAA==.Seleane:BAAANQAECgMIAwAAAA==.Sellvanya:BAAANQADCgQIBAAAAA==.Senyor:BAAANQAECgEIAQAAAA==.Sethcure:BAAANQADCgUIBwAAAA==.',
Sh='Shaadas:BAAANQAECgQIBAAAAA==.Shadeau:BAAANQADCgcIBwAAAA==.Shamackerd:BAAANQADCgYICQABNQADCggIDQABAAAAAA==.Shampoo:BAAANQABCgIIAQAAAA==.Shandriss:BAAANQADCggIDgAAAA==.Shockapal:BAAANQAECgIIAgAAAA==.Shrimon:BAAANQADCgIIAgAAAA==.Shrimps:BAAANQAECgQIBAAAAA==.',
Si='Sidewinder:BAAANQADCggIDAAAAA==.Siong:BAAANQAECgIIAgAAAA==.Sitch:BAAANQADCgMIAQAAAA==.',
Sk='Skunknmidget:BAAANQADCggIDgAAAA==.Skyvestris:BAAANQADCgUIBQAAAA==.',
Sl='Slamueladams:BAAANQADCgEIAQAAAA==.Slayberto:BAAANQAECgIIAgAAAA==.',
Sm='Smellmygas:BAAANQADCgUICAAAAA==.Smoko:BAAANQAECgIIAgAAAA==.',
Sn='Sneaky:BAAANQADCgcIBwABNQAECgUICQABAAAAAA==.Sneakyr:BAAANQAECgUICQAAAA==.Snypar:BAAANQAECgMIAwAAAA==.Snôva:BAAANQADCgYIBgAAAA==.',
So='Soaraga:BAAANQABCgQIBAAAAA==.Sodosopa:BAAANQADCgYIBgAAAA==.Solaire:BAAANQADCgcIDQAAAA==.Sole:BAAANQADCgcIBwAAAA==.Soleim:BAAANQADCgUIBQABNQADCgcIBwABAAAAAA==.Somavanna:BAAANQADCgYICwAAAA==.Sophara:BAAANQAECgIIAgAAAA==.Sorbet:BAAANQAECgUIBgAAAA==.Soulgrinder:BAAANQADCgUIBQAAAA==.',
Sp='Sparhawk:BAAANQAECgUIBgAAAA==.Sparklebolts:BAAANQADCgQIBAAAAA==.Speedwagon:BAAANQAECgIIAgAAAA==.Spicytotems:BAAANQADCgcIDQAAAA==.Spidercowsd:BAAANQADCgIIAgAAAA==.Spippy:BAAANQAECgQIBAAAAA==.Splõõsh:BAAANQADCgYIBgABNQADCgYICwABAAAAAA==.Sprogue:BAAANQAECgMIAwABNQAECgcICgABAAAAAA==.Spronatty:BAAANQADCgIIAgAAAA==.Sprosport:BAAANQADCgEIAQABNQAECgcICgABAAAAAA==.Sprø:BAAANQADCgMIAwABNQAECgcICgABAAAAAA==.Spurlock:BAAANQADCgUICQAAAA==.Spyrogos:BAAANQADCgcIBwAAAA==.',
Sq='Squidbits:BAAANQADCgcIDAAAAA==.',
St='Stabsandhugs:BAAANQADCgQIBAAAAA==.Starclaw:BAAANQAECgYICAAAAA==.Stasis:BAAANQAECgQIBAAAAA==.Statixx:BAAANQADCgYIBgAAAA==.Stel:BAAANQADCgYIBgAAAA==.',
Su='Sugarteets:BAAANQADCgcIBwAAAA==.Supadope:BAAANQADCgYIDQAAAA==.',
Sy='Sydner:BAAANQADCgYICwAAAA==.Synergize:BAAANQADCgMIAwAAAA==.Sythila:BAAANQAECgcIDAAAAA==.',
['Sü']='Süblime:BAAANQADCgEIAQAAAA==.',
Ta='Tachichan:BAAANQADCgUIBQAAAA==.Tadertod:BAAANQADCggIEQAAAA==.Talleth:BAAANQAECgMIBgAAAA==.Tallìsh:BAAANQADCgQIBAAAAA==.Talorion:BAAANQAECgIIAgAAAA==.Tandrisell:BAAANQADCgEIAQAAAA==.Tassyn:BAAANQAECgQIBAAAAA==.Tattianna:BAAANQADCggIDAAAAA==.Tazenezoth:BAAANQAECgYICQAAAA==.',
Te='Tehmachine:BAAANQAECgQIBAAAAA==.Terry:BAAANQADCgYIBQAAAA==.',
Th='Thanyros:BAAANQAECgEIAQAAAA==.Thebrowner:BAAANQADCgYIBgAAAA==.Thejuice:BAAANQADCggICQAAAA==.Thoian:BAAANQADCgYIDAAAAA==.Thrindy:BAAANQADCgUIBwAAAA==.Thugnificint:BAAANQADCgYICAABNQAECgUICQABAAAAAA==.Thåwn:BAAANQADCggIDgAAAA==.Thèokoles:BAAANQAFFAEIAQAAAA==.',
Ti='Tiblock:BAAANQAECgUIBwAAAA==.Tidalsage:BAAANQAECgQIBAAAAA==.Timeskip:BAAANQADCggIDQAAAA==.Timfinnigut:BAAANQAECgMIAwAAAA==.Tinx:BAAANQADCgcICwAAAA==.Tinylego:BAAANQADCggIDAAAAA==.Tinytiran:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.',
To='Tonktotem:BAEANQADCgEIAQAAAA==.Toptearcryer:BAAANQAECgQIBAAAAA==.Tortilla:BAAANQAECgYIDAAAAA==.Toryn:BAAANQADCgIIAgABNQABCgMIAwABAAAAAA==.',
Tr='Trecks:BAAANQADCgUIBQAAAA==.Treesumm:BAAANQAECgEIAQAAAA==.Trickyrickyy:BAAANQAECgEIAQAAAA==.Triptix:BAAANQADCgYICQAAAA==.Trynitie:BAAANQADCggIDQAAAA==.',
Tu='Turlane:BAAANQAECgMIAwAAAA==.',
Tw='Twinkslayer:BAAANQADCgYICAABNQAECgQIBAABAAAAAA==.',
Ty='Tyeret:BAAANQAECgIIAgAAAA==.',
['Tø']='Tørvald:BAAANQAECgEIAQAAAA==.',
Us='Uslurper:BAAANQAECgYICQAAAA==.',
Va='Varenar:BAAANQAECgMIAwAAAA==.',
Ve='Vearn:BAAANQADCgMIAwABNQADCgcICAABAAAAAA==.Vellamo:BAAANQADCgMIBQAAAA==.Vengeful:BAAANQADCggICwAAAA==.Venuveus:BAAANQADCgcIDAAAAA==.Verdan:BAAANQAECgMIAwAAAA==.',
Vi='Virlomi:BAAANQAECgcIDQAAAA==.',
Vl='Vlix:BAAANQADCgMIAwAAAA==.',
Vo='Vowz:BAAANQADCgYICgAAAA==.',
Vy='Vynx:BAAANQADCggIDAAAAA==.Vyrogash:BAAANQADCgMIAwAAAA==.Vythica:BAAANQAECgUIBgAAAA==.',
Wa='Wakoguyc:BAAANQAECgQIBAAAAA==.Warcaige:BAAANQADCgYIBgABNQAFFAIIAwABAAAAAA==.',
We='Weierstraß:BAAANQAECgMIAwAAAA==.Welari:BAAANQAECgMIAwAAAA==.Weskerx:BAAANQADCggICAAAAA==.',
Wh='Whindd:BAAANQAECgEIAQAAAA==.Whurstresort:BAAANQAECgQIBAAAAA==.',
Wi='Wickedsoul:BAAANQADCggICAABNQADCggICAABAAAAAA==.Widowmaker:BAAANQADCgIIAQAAAA==.Wingmancole:BAAANQADCgQIBAAAAA==.Withers:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.',
Wo='Wondrball:BAAANQAECgIIAgAAAA==.Worgen:BAAANQADCgYIBgAAAA==.',
Xa='Xanderia:BAAANQADCgYICwAAAA==.',
Xe='Xeralath:BAAANQAECgMIAwAAAA==.',
Xv='Xvibe:BAAANQADCgcICwAAAA==.',
Xy='Xyphira:BAAANQADCgYICgAAAA==.',
['Xý']='Xý:BAAANQADCgYICAAAAA==.',
Ya='Yaboo:BAAANQAECgEIAQAAAA==.Yaen:BAAANQADCgUICgAAAA==.',
Ye='Yehvenâh:BAAANQADCgcIDAAAAA==.Yeska:BAAANQADCgQIBAAAAA==.',
Yo='Yootle:BAAANQADCgcIBwAAAA==.Yovanna:BAAANQADCgQIBAAAAA==.',
Za='Zallo:BAAANQADCggIDwAAAA==.Zaloria:BAAANQADCgIIAgAAAA==.Zarth:BAAANQADCgIIAgAAAA==.Zava:BAAANQAECgIIAwAAAA==.',
Ze='Zeelos:BAAANQADCggIDgAAAA==.Zephhyr:BAAANQAECgMIAwAAAA==.Zephyr:BAAANQADCgQIBAAAAA==.Zeñor:BAAANQAECgQIBAABNQAECgEIAQABAAAAAA==.',
Zh='Zhax:BAAANQABCgMIAwAAAA==.',
Zi='Zireael:BAAANQADCggIDwAAAA==.',
Zo='Zornox:BAAANQABCgQIBAAAAA==.',
['Óp']='Óprawïndfury:BAAANQAECgMIAwAAAA==.',
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
