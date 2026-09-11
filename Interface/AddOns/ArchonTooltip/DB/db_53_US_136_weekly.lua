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

local lookup = {'Unknown-Unknown','Paladin-Holy','DemonHunter-Havoc','Shaman-Elemental','Monk-Windwalker','Druid-Restoration','Mage-Arcane','DeathKnight-Blood','Priest-Shadow','Warlock-Demonology','Warlock-Destruction','Rogue-Assassination','DemonHunter-Devourer','DeathKnight-Unholy',}
local provider = {region='US',realm='Korgath',name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Abbygrace:BAAANQAECgQIBQAAAA==.',
Ad='Adar:BAAANQAECgUIBgAAAA==.',
Ae='Aegeis:BAAANQAECgEIAQAAAA==.Aelaryn:BAAANQADCggIEAAAAA==.Aeonffx:BAAANQABCgQIBAAAAA==.',
Af='Afterearth:BAAANQAECggIEgAAAA==.',
Ag='Aggrobeast:BAAANQADCgcIEgAAAA==.Agoný:BAAANQADCgQIBAAAAA==.',
Ai='Ailie:BAAANQAECgYICgAAAA==.',
Ak='Akadey:BAAANQADCgYICAAAAA==.',
Al='Aliì:BAAANQAECgMIAwABNQAECggIEgABAAAAAA==.Allise:BAAANQADCggICQAAAA==.Allnightløng:BAAANQAECgUIBgAAAA==.Alphonos:BAAANQADCgMIAwAAAA==.Alverez:BAAANQAECggIEgAAAA==.',
Am='Amorilas:BAAANQAECgYIDAAAAA==.Amunera:BAAANQADCgYIDAABNQADCgYIEQABAAAAAA==.Amàrok:BAAANQADCgUIBQABNQADCgcIDgABAAAAAA==.',
An='Andersan:BAABNQAECoEXAAICAAgJVREmHgAgAgACAAgJVREmHgAgAgAAAA==.Anetharion:BAAANQAECgEIAQAAAA==.Animalchange:BAAANQAECgIIBAAAAA==.',
Ap='Apeth:BAAANQADCgEIAQAAAA==.Applepi:BAAANQAECgEIAQAAAA==.Aproditee:BAAANQADCgMIBAAAAA==.',
Ar='Areayl:BAAANQAECgUICAAAAA==.Arinn:BAAANQAECggIEgAAAA==.',
As='Ashtkal:BAAANQAECgYICwAAAA==.Ashtoes:BAAANQAECgQIBAAAAA==.Astralbubble:BAAANQAECgQIBwAAAA==.',
Au='August:BAAANQADCggIEAAAAA==.Auratic:BAAANQADCgcIBwAAAA==.Automation:BAAANQADCgcICQABNQAECggIEgABAAAAAA==.',
Av='Avalea:BAAANQADCgUIBwAAAA==.',
Ay='Ayyvlaad:BAAANQAECgUICQAAAA==.',
Az='Azerlite:BAAANQADCgcIBwABNQAECgcIDwABAAAAAA==.Azkota:BAAANQAECgQIBAAAAA==.Azulwall:BAAANQADCggIEwAAAA==.Azureros:BAAANQAECgUIBwAAAA==.',
Ba='Bandaayd:BAAANQAECgEIAQAAAA==.Bargaug:BAAANQADCgYIBgABNQAECgcICAABAAAAAA==.Bathasar:BAAANQADCgYIDAAAAA==.Bathpally:BAAANQAECgIIAgAAAA==.',
Be='Beandh:BAAANQADCggIEAABNQAECgkJFQADADYcAA==.Beanygene:BAAANQADCgQIBAAAAA==.Beastfury:BAAANQAECgMIBAAAAA==.Beefyclap:BAAANQAECgQIBAAAAA==.Beha:BAAANQADCgEIAQAAAA==.Beleria:BAAANQADCgMIAwAAAA==.Bellaidd:BAAANQAECgcIDQAAAA==.Bellore:BAAANQADCgQIBAAAAA==.Benedîct:BAAANQADCgIIAgAAAA==.Bewblywoobly:BAAANQAECgEIAQAAAA==.Bezvoker:BAAANQADCgUIBQAAAA==.Beástboy:BAAANQAECgIIAgAAAA==.',
Bi='Biekdafreak:BAAANQAECgYIBgAAAA==.Bigbuffalo:BAAANQADCgYICAAAAA==.Bigdaddoo:BAAANQADCgUIBQAAAA==.Biggisign:BAAANQAECgEIAQAAAA==.Bina:BAAANQADCggICAAAAA==.Bitemenow:BAAANQADCggIDgAAAA==.Bitsobacon:BAAANQAECgQIBAAAAA==.Bizzó:BAAANQADCggICQAAAA==.',
Bl='Bladeboy:BAAANQABCgIIAgAAAA==.Blambussi:BAAANQADCgcIDAAAAA==.Blitzball:BAAANQAECgEIAQAAAA==.Blooddragoon:BAAANQAECgQIBQAAAA==.Bloodycrow:BAAANQABCgMIAwAAAA==.',
Bo='Bohica:BAAANQAECgYIBwAAAA==.Bombadil:BAAANQAECgQIBQAAAA==.Bomberdeath:BAAANQAECgEIAQAAAA==.Bongrip:BAAANQADCgcIEQAAAA==.Boochstorm:BAAANQADCggIDAAAAA==.Boogiee:BAAANQADCgcIDQABNQAECgQIBQABAAAAAA==.',
Br='Bradington:BAAANQADCggIFwAAAA==.Brezel:BAAANQADCgYIBgAAAA==.Brond:BAAANQABCgIIAgAAAA==.Brontide:BAAANQAECgEIAQAAAA==.Bruengar:BAAANQAECgUICAAAAA==.Bruniik:BAAANQAECgEIAQAAAA==.',
Bu='Bubblehêarth:BAAANQAECgMIBQAAAA==.Budapest:BAAANQAECgUICQAAAA==.Buddyolpal:BAAANQAECgIIAQAAAA==.Bumbleh:BAAANQAECgEIAQAAAA==.Bumibe:BAAANQADCgcIBwAAAA==.Bungulator:BAAANQAECgcIDwAAAA==.Buné:BAAANQAECgUICQAAAA==.',
Ca='Caad:BAAANQADCggIEQAAAA==.Cador:BAAANQAECgEIAgAAAA==.Cadwarr:BAAANQADCgYIBgAAAA==.Cam:BAAANQAECgMIBQAAAQ==.Cannibubz:BAAANQAECgIIAgAAAA==.Cannimal:BAAANQAECggIEgAAAA==.Cataylst:BAAANQADCggICQAAAA==.Catwilliams:BAAANQAECgcIDQAAAA==.',
Ce='Celestas:BAAANQADCgIIAgAAAA==.',
Ch='Cheeze:BAAANQADCgYICgAAAA==.Chiliwop:BAAANQAECgUIBgAAAA==.Chippydk:BAAANQADCgIIAgAAAA==.Chippyh:BAAANQADCggICAAAAA==.Chloei:BAAANQAECgMIAwAAAA==.Chwonk:BAAANQADCggIFQAAAA==.',
Ci='Circê:BAAANQADCgYICwAAAA==.',
Cl='Clevoker:BAAANQAECgYIDAAAAA==.Clusion:BAAANQAECgYIBgAAAA==.',
Co='Codex:BAAANQAECgQIBAAAAA==.Cole:BAAANQADCggIDAAAAA==.Conductor:BAAANQAECgQIBgAAAA==.Convergent:BAAANQAECgYICwAAAA==.Coosh:BAAANQAECggIEgAAAA==.Corov:BAAANQAECgEIAQAAAA==.Courigon:BAAANQAECgEIAQAAAA==.',
Cp='Cptamerica:BAAANQAECgIIBAAAAA==.',
Cr='Craigolas:BAAANQADCggIDwAAAA==.Crippler:BAAANQADCgcICQAAAA==.Crossbow:BAAANQADCgMIBgAAAA==.Crosscut:BAAANQAECgEIAQAAAA==.Cruelty:BAAANQADCgQIBAAAAA==.',
Cu='Cummins:BAAANQAECgcIDwAAAA==.Currents:BAAANQADCggICAAAAA==.',
Da='Dadstealer:BAAANQADCgcIEgAAAA==.Dagrundel:BAAANQAECgEIAQAAAA==.Dalinarix:BAAANQADCggIEQAAAA==.Dankpope:BAAANQAECgIIAgAAAA==.Davrin:BAAANQAECgUICQAAAA==.',
De='Deathbyarow:BAAANQAECgEIAQAAAA==.Deathhammer:BAAANQAECgEIAQAAAA==.Deathjrak:BAAANQAECgYICAAAAA==.Deesixxfour:BAAANQADCgUIBQABNQAECgUICQABAAAAAA==.Degates:BAAANQAECgIIAgAAAA==.Demonia:BAAANQAECgQIBgAAAA==.Demonicshoes:BAAANQADCggIFAAAAA==.Dethwing:BAAANQAECgQIBQAAAA==.Devaña:BAAANQADCggIFAAAAA==.',
Di='Diclonius:BAAANQAECgEIAQAAAA==.Dirtystaff:BAAANQADCggIEwAAAA==.Dirtzmage:BAAANQAECgUIBQAAAA==.Dizzledh:BAAANQAECgEIAgAAAA==.',
Dj='Djkhaledd:BAAANQAECgEIAQAAAA==.',
Do='Doobins:BAAANQADCggIFQAAAA==.Dookiboy:BAAANQADCgYIBgABNQAECgcIEAABAAAAAA==.Dooy:BAAANQADCggICAAAAA==.Douii:BAAANQADCggICAAAAA==.',
Dr='Draco:BAAANQABCgQICAAAAA==.Draconir:BAAANQABCgYICAAAAA==.Dragao:BAAANQADCgYIBgAAAA==.Draggen:BAAANQAECgUIBgAAAA==.Dragimal:BAAANQAECgEIAQAAAA==.Dragonn:BAAANQAECgQICAAAAA==.Dragonoied:BAAANQADCgMIAwAAAA==.Dragonxlord:BAAANQABCgMIAwAAAA==.Dragosia:BAAANQAECgQICQAAAA==.Drakojangens:BAAANQAECgUIBwABNQAECgcICQABAAAAAA==.Drakthar:BAAANQADCgUICgAAAA==.Dranoric:BAAANQADCggIDAABNQAECgUICwABAAAAAA==.Dreebus:BAAANQADCgYIBgABNQAECgUICQABAAAAAA==.Drlawyerphd:BAAANQAECgYICgAAAA==.Druz:BAAANQADCggIDwAAAA==.',
Ds='Dsixxfour:BAAANQAECgUICQAAAA==.',
Du='Duncedivh:BAAANQADCgUICAAAAA==.Dunzjan:BAAANQAECgQIBQAAAA==.',
Dy='Dysmai:BAAANQADCgYICwAAAA==.',
['Dé']='Déathwolf:BAAANQAECgUICAAAAA==.',
Ea='Eatsammich:BAAANQADCggIDwAAAA==.',
Eg='Eggsbenedïct:BAAANQAECgYICQAAAA==.Egol:BAAANQAECgYICwAAAA==.',
El='Eldonra:BAAANQADCgYIBgABNQAECggIEwABAAAAAA==.Elidrine:BAAANQAECgQIBAAAAA==.Elmerfuddz:BAAANQAECgMIAwAAAA==.Elyrayldin:BAAANQADCggIFAAAAA==.',
En='Enazenoth:BAAANQAFFAEIAQAAAA==.Enryu:BAAANQAECgQIBAAAAA==.Envburnz:BAAANQAECgQIBAAAAA==.',
Er='Erooka:BAAANQAECgYICQAAAA==.',
Es='Esio:BAAANQAECgcICwAAAA==.',
Ev='Evileyes:BAAANQADCgIIAgABNQADCggICAABAAAAAA==.',
Ey='Eyri:BAAANQAECgUICQAAAA==.',
Ez='Ezzie:BAAANQAECgEIAQAAAA==.',
Fa='Falsodew:BAAANQAECgcIDgAAAA==.',
Fe='Felicity:BAAANQAECgIIAwAAAA==.Femmever:BAAANQAECgEIAQAAAA==.Feonix:BAAANQAECgYIDAAAAA==.Ferenus:BAAANQABCgQIBAAAAA==.Fewsha:BAACNQAFFIEHAAIEAAUJBhm8AADTAQAEAAUJBhm8AADTAQA1AAQKgRoAAgQACQlAITQEAIEDAAQACQlAITQEAIEDAAAA.',
Fi='Fidellia:BAAANQADCgcIDQAAAA==.Findie:BAAANQADCggIDQAAAA==.',
Fo='Foofoolala:BAAANQADCgYIBgAAAA==.Fookadk:BAAANQADCgYICwAAAA==.Fookapalli:BAAANQABCgYICAAAAA==.Forttoo:BAAANQADCgEIAQAAAA==.Fourthwing:BAAANQADCgQIBAAAAA==.',
Fr='Frawstbyte:BAAANQAECgYIDAAAAA==.Freeholed:BAAANQAECgYICgAAAA==.Fridgefister:BAAANQAECgQIBAAAAA==.Frodie:BAAANQAECgYIBwAAAA==.',
Fu='Fumina:BAAANQADCggICAAAAA==.',
Ga='Gaea:BAAANQAECgQIBAAAAA==.Gallanon:BAAANQADCgcIBwAAAA==.Gallshot:BAAANQADCgUIBQAAAA==.Gamergirl:BAAANQABCgYIBgAAAA==.Gangrêl:BAAANQADCgYIDAABNQADCgYIEQABAAAAAA==.Garithor:BAAANQADCgQIBAAAAA==.',
Gb='Gbang:BAAANQAECgIIAwAAAA==.',
Ge='Gekidoryu:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Gerebert:BAAANQAECgEIAQAAAA==.Getajobubum:BAAANQAECgUIBwAAAA==.',
Gh='Ghostdance:BAAANQAFFAIIAgAAAA==.Ghoulia:BAAANQADCgcIDQAAAA==.',
Gi='Giggz:BAAANQAECgEIAQAAAA==.Gingerpala:BAAANQADCgQIBwAAAA==.Giuttrix:BAAANQADCgcIEAAAAA==.',
Gl='Gloriousdead:BAAANQADCgYIBgAAAA==.Glowing:BAAANQADCggIEwAAAA==.',
Go='Gokukakarot:BAAANQAECgEIAQAAAA==.Goldlore:BAAANQAECgIIAgAAAA==.Goopdk:BAAANQAECgEIAQAAAA==.Gothikia:BAAANQADCggIFQAAAA==.',
Gr='Gremhunt:BAAANQAECgIIAgAAAA==.Grondel:BAAANQAECgIIAgAAAA==.Grumpybear:BAAANQADCgcIDQAAAA==.',
Gu='Gundham:BAAANQADCggIEwAAAA==.Gunko:BAAANQADCggICAAAAA==.Gunstrong:BAAANQADCggIFgAAAA==.',
['Gõ']='Gõsia:BAAANQAECgQIBAAAAA==.',
['Gø']='Gøtt:BAAANQADCgIIAgAAAA==.',
Ha='Haagendots:BAAANQAECgEIAQAAAA==.Hairofwar:BAAANQAECgUICAAAAA==.Haleynicole:BAAANQAECgEIAQAAAA==.Happydaug:BAAANQADCgcICwABNQAECgcIDQABAAAAAA==.Happydawg:BAAANQAECgcIDQAAAA==.Hasted:BAAANQAECggIEgAAAA==.Hawktar:BAAANQAECgYIBgAAAA==.',
He='Healimus:BAAANQAECgUIBwAAAA==.Healmates:BAAANQAECgYICQAAAA==.Helix:BAAANQAECgcIDwAAAA==.Hennybull:BAAANQADCgIIAgAAAA==.',
Hm='Hmmfock:BAAANQADCggICAAAAA==.',
Ho='Ho:BAAANQAECgcIBwAAAA==.Holee:BAAANQADCgEIAQAAAA==.Holybaby:BAAANQAECgQIBQAAAA==.Holybrute:BAAANQAECgIIAwABNQAECgYICQABAAAAAA==.Holybunger:BAAANQAECgEIAQAAAA==.Holysheetz:BAAANQABCgQIBAAAAA==.Horde:BAAANQADCgcICwAAAA==.',
Hu='Hueycheeks:BAAANQAECgcIDAAAAA==.Huntstatus:BAAANQAECggIEgAAAA==.Huxium:BAAANQAECgYICgAAAA==.',
Hy='Hymnpossible:BAAANQAECgEIAQAAAA==.',
Ic='Icetongue:BAAANQAECgUIBQAAAA==.',
If='Iflingpoo:BAAANQAECgcIEQAAAA==.Ifusêekamy:BAAANQADCggIEwAAAA==.',
Ij='Ijrakwarrior:BAAANQAECgIIAgAAAA==.',
Im='Impulse:BAAANQAECgQIBgAAAA==.',
In='Indelebi:BAAANQABCgQIBgAAAA==.Inorgeing:BAAANQAECgMIAwAAAA==.',
Ir='Irmengaud:BAAANQADCggIDwAAAA==.Ironpup:BAAANQADCgIIAwAAAA==.Ironscales:BAAANQAECgQIAQAAAA==.',
Ja='Jabbyjr:BAAANQAECgcIDwAAAA==.Jabum:BAAANQAECgYIBwAAAA==.Jaio:BAAANQADCggICAAAAA==.Jajakuna:BAAANQADCggIDwAAAA==.Jangens:BAAANQAECgcICQAAAA==.Jaruni:BAAANQAECgUICAAAAA==.Jaynine:BAAANQAECgYICgAAAA==.',
Je='Jeffvyrt:BAAANQAECgQIBwAAAA==.Jeksulee:BAAANQABCgYIBgAAAA==.',
Ji='Jibbs:BAAANQADCgYIDQAAAA==.',
Jo='Jodimaw:BAAANQADCggICAAAAA==.Jorian:BAAANQADCgIIAgABNQADCggICQABAAAAAA==.Joridiezs:BAAANQADCggIEQAAAA==.Joshness:BAAANQADCgMIAwAAAA==.',
Ju='Juanrambo:BAAANQADCggIDAAAAA==.Juicyjohnson:BAAANQADCgMIAwABNQAECgYIBgABAAAAAA==.Jumblo:BAAANQAECgEIAQAAAA==.Jupileo:BAAANQAECgMIAwAAAA==.Jurassichots:BAAANQADCgYIDAAAAA==.',
Ka='Kaalista:BAAANQAECgEIAQABNQAECgYIDAABAAAAAA==.Kailee:BAACNQAFFIEFAAIFAAQJvRNLAQBqAQAFAAQJvRNLAQBqAQA1AAQKgRkAAgUACQkGJfQAALoDAAUACQkGJfQAALoDAAE1AAQKAQgBAAEAAAAA.Kaito:BAAANQAECgEIAQAAAA==.Kaolis:BAAANQADCgEIAQAAAA==.Kariba:BAAANQAECgUIBQABNQAECggIEgABAAAAAA==.Karmana:BAAANQAECggIAwAAAA==.Katael:BAAANQADCgYICwAAAA==.Kavel:BAAANQAECgQICAAAAA==.Kaylie:BAAANQAECgEIAQAAAA==.Kayti:BAAANQADCggIEwAAAA==.',
Ke='Kelfiona:BAAANQADCgYIDQAAAA==.Keraboo:BAAANQAECgEIAQAAAA==.Kerie:BAAANQAECgEIAQAAAA==.Ketamyne:BAAANQADCggIDgAAAA==.Keynin:BAAANQADCgUIBQAAAA==.',
Kh='Khalu:BAAANQADCgEIAQAAAA==.',
Ki='Kiandron:BAAANQADCgYIDgAAAA==.Killerqtlol:BAAANQADCgcIDAABNQAECgUICAABAAAAAA==.Kimbostab:BAAANQADCgMIBAAAAA==.',
Kn='Knockbak:BAAANQAECgEIAQAAAA==.',
Ko='Kohko:BAAANQADCgYIBgAAAA==.Kozinirus:BAAANQADCggIDwAAAA==.',
Kq='Kqmav:BAAANQAECgQIBAAAAA==.',
Kr='Kruwll:BAAANQADCggIDwAAAA==.Krít:BAAANQADCggICgABNQADCgQIBAABAAAAAA==.',
Ku='Kumolock:BAAANQAECgQIBAAAAA==.Kuongsun:BAAANQADCggIDgAAAA==.',
['Kú']='Kúrama:BAAANQABCgYICAAAAA==.',
La='Ladeehunter:BAAANQAECgIIAgAAAA==.Lambsbreath:BAAANQADCgcIBwAAAA==.Lanto:BAAANQADCgQIBwABNQABCgIIAgABAAAAAA==.Laprofessora:BAAANQADCggICAAAAA==.Laquince:BAAANQAECgEIAQAAAA==.Lasagnazaddy:BAAANQADCgYICwAAAA==.Laurafel:BAAANQADCgUIBQAAAA==.',
Le='Lelouché:BAAANQABCgIIAgABNQABCgYICAABAAAAAA==.Lertglochen:BAAANQAECgMIBgAAAA==.Lexistarr:BAEANQADCgYIBgABNQADCggIEgABAAAAAA==.',
Li='Lightbunz:BAAANQADCgQIBAAAAA==.Lightcast:BAAANQAECgEIAQABNQAECgkJFwAGAAUeAA==.Lightra:BAAANQADCgYIBgAAAA==.Limeywater:BAAANQAECgUIBwAAAA==.Lindramech:BAAANQABCgYIBgAAAA==.Litherous:BAAANQAECgQIBQAAAA==.Litzdh:BAAANQAECgEIAQAAAA==.',
Ll='Llazereth:BAAANQAECgUICQAAAA==.Llordvalar:BAAANQADCgIIAgAAAA==.',
Lo='Lockimar:BAEANQAECgYICgAAAA==.Lockuru:BAAANQAECgYICwAAAA==.Lonestàr:BAAANQAECgEIAQAAAA==.Lowiqslowirl:BAAANQABCgIIAgAAAA==.',
Lu='Lucidy:BAAANQAECgUIBQAAAA==.Lumberjacked:BAAANQAECgMIAwABNQAECgcIEQABAAAAAA==.Luna:BAAANQADCgYIDQABNQAECgQICAABAAAAAA==.Luspriest:BAAANQADCgQIBAAAAA==.Lusuffer:BAAANQAECgQICAAAAA==.Lusufferr:BAAANQADCgYIDAABNQAECgQICAABAAAAAA==.Lutra:BAAANQAECgUICAAAAA==.',
Ly='Lyx:BAAANQAECgEIAQAAAA==.',
Ma='Magerpwn:BAAANQADCgUIBQAAAA==.Makrio:BAAANQABCgQIBQAAAA==.Malachî:BAAANQADCgYIBgAAAA==.Malitan:BAAANQAECgcIEAAAAA==.Mamif:BAAANQAECgEIAQAAAA==.Mannasto:BAAANQADCgYIBgAAAA==.Manuelek:BAAANQAECgEIAQAAAA==.Markatron:BAAANQAECgUIBQAAAA==.Mattiekay:BAAANQAECgMIBgAAAA==.Maxx:BAAANQADCgcIBwAAAA==.Mañajuana:BAAANQAECgUICAAAAA==.',
Me='Meatrocket:BAAANQADCgYIBgABNQAECgYIDAABAAAAAA==.Meefalo:BAAANQAECgQIBAAAAA==.Meggfox:BAAANQADCgQIBAAAAA==.Meghanics:BAAANQADCgYIDAAAAA==.Menethol:BAAANQADCgUIBQABNQAECgYIFQAHAEsWAA==.Mercymage:BAAANQADCgQIBAAAAA==.Merie:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.Merlinswrath:BAAANQADCgYIBAAAAA==.Merril:BAAANQABCgYICAABNQAECgcIEAABAAAAAA==.Merza:BAAANQADCggICAABNQAECgcIDgABAAAAAA==.Merzinator:BAAANQAECgcIDgAAAA==.',
Mi='Mickle:BAAANQADCgEIAQAAAA==.Midgrad:BAAANQADCggIDgABNQAECgMIAwABAAAAAA==.Mikelowry:BAAANQADCggIDQAAAA==.Minimum:BAAANQAECgIIAgABNQAECgQIBAABAAAAAA==.Mischeveous:BAAANQAECgIIAgAAAA==.Mithrandir:BAAANQAECgUIBgAAAA==.',
Mj='Mjiltanke:BAAANQAECgEIAQAAAA==.',
Mo='Moistcarry:BAAANQADCgUIBQAAAA==.Mokniahiah:BAAANQAECgEIAgAAAA==.Monkmates:BAAANQAECgEIAQAAAA==.Moodoon:BAAANQAECgEIAQAAAA==.Mooseyfate:BAAANQADCggIEQAAAA==.Moraxy:BAAANQADCgcIDQAAAA==.Moromagus:BAAANQAECgUICwAAAA==.Motorboats:BAAANQADCgQIBAAAAA==.',
Mu='Mualpractice:BAAANQADCgQIBQAAAA==.Murdok:BAAANQADCggICAAAAA==.Murray:BAAANQAECgYIBgABNQAECgkJGAAIAKEZAA==.Mutknodeprac:BAAANQAECgEIAQAAAA==.',
Mx='Mxsery:BAAANQAECgIIAgAAAA==.Mxz:BAAANQADCgcIBwABNQAECgcIDwABAAAAAA==.',
My='Myræl:BAAANQADCggIEwAAAA==.Mystíle:BAAANQAECggIEwAAAA==.Mythrix:BAAANQABCgIIAgABNQADCgcIDgABAAAAAA==.Mythrixx:BAAANQADCgcIDgAAAA==.',
['Mà']='Màjíque:BAAANQAECgEIAQAAAA==.',
['Mé']='Méadow:BAAANQADCgcIDgAAAA==.',
Na='Nabesan:BAAANQADCgIIAgAAAA==.Naked:BAAANQADCggIBAAAAA==.Narhi:BAAANQAECgEIAQAAAA==.Nasminthe:BAAANQADCgcICwAAAA==.Nature:BAAANQADCgUIBQAAAA==.Naughtya:BAAANQAECgQIBAAAAA==.Nazem:BAAANQADCggICAAAAA==.',
Ne='Nekoro:BAAANQAECgYICQAAAA==.Nelfsquantch:BAAANQADCgcIEAAAAA==.Nevadawolf:BAAANQAECgQIBAAAAA==.',
Ni='Nightreaver:BAAANQADCgcIEAAAAA==.Nightshiftér:BAAANQAECgEIAgAAAA==.Nimbex:BAAANQADCgQIBAAAAA==.Ninetailsfox:BAAANQAECgcIEAAAAA==.Nion:BAAANQAECgQIBAAAAA==.Nippy:BAAANQADCgYIBgABNQAECgQIBgABAAAAAA==.',
No='Nolo:BAAANQADCgQIBQAAAA==.Northzen:BAAANQAECgUICAAAAA==.Notaorc:BAAANQADCgUIBQAAAA==.Notmyconcern:BAAANQADCgYIBgAAAA==.Novaflux:BAAANQAECgYICgAAAA==.Noxxicc:BAAANQADCgYICwABNQAECgIIAgABAAAAAA==.',
Ny='Nyghtterror:BAAANQADCgYIEQAAAA==.Nyreeh:BAAANQADCggIEwAAAA==.Nytearcher:BAAANQAECgQIBgAAAA==.Nyxa:BAAANQAECgEIAQAAAA==.',
['Ná']='Nálera:BAAANQADCggIEAAAAA==.',
['Nü']='Nüguns:BAAANQAECgEIAQAAAA==.',
Ok='Okamifist:BAAANQADCgYIBgAAAA==.Oklyra:BAAANQABCgYICgAAAA==.',
Om='Omnia:BAAANQAECgUICQABNQABCgMIAwABAAAAAA==.',
On='Onlyshams:BAAANQADCgMIAwAAAA==.',
Oo='Oogiee:BAAANQAECgQIBQAAAA==.',
Or='Orcmonk:BAAANQADCgUICAAAAA==.',
Os='Oschun:BAAANQAECgYICwAAAA==.',
Pa='Palacandia:BAAANQADCgYIBQAAAA==.Palanar:BAAANQAECgYIDAAAAA==.Pallyboi:BAAANQAECgIIAgAAAA==.Paluru:BAAANQAECgEIAQABNQAECgYICwABAAAAAA==.Panosh:BAAANQADCgUIBQAAAA==.',
Pc='Pchef:BAAANQAECgQIBQAAAA==.',
Pe='Pelayo:BAAANQADCgcIEAABNQADCggICAABAAAAAA==.Peperoninips:BAAANQADCgQICAAAAA==.Petricia:BAAANQAECgUIBwAAAA==.',
Pf='Pfeffer:BAAANQADCggIFAAAAA==.',
Ph='Phaithful:BAABNQAECoEYAAIJAAkJ6B2mBAA8AwAJAAkJ6B2mBAA8AwAAAA==.Phazerman:BAAANQAECgQIBAAAAA==.Phocus:BAAANQAECgMIAwABNQAECgkJGAAJAOgdAA==.Phury:BAAANQADCggICwABNQAECgkJGAAJAOgdAA==.',
Pi='Pikapikapika:BAAANQAECgQIBAAAAA==.',
Pl='Planthoofem:BAAANQADCgQIAwAAAA==.Playpride:BAAANQAECgEIAQAAAA==.',
Po='Poboy:BAAANQAECgIIBAAAAA==.Pocket:BAAANQADCggIEAABNQAECgQICAABAAAAAA==.Pokepokepoke:BAAANQAECgQIBAAAAA==.Poppop:BAAANQAECgEIAQAAAA==.Poriand:BAAANQAECgEIAQAAAA==.Portzul:BAAANQAECgEIAQAAAA==.',
Pr='Priesttea:BAAANQADCgIIAgAAAA==.Procology:BAAANQABCgEIAQAAAA==.',
Ps='Pseudogrim:BAAANQAECgUICAAAAA==.Psspspss:BAAANQADCgYIBgAAAA==.',
Pu='Pugnosano:BAAANQADCgQIBAAAAA==.Pussnboots:BAAANQAECgQIBAAAAA==.',
Ra='Raefe:BAAANQADCgcIDAAAAA==.Raffaj:BAAANQAECgEIAQAAAA==.Raidedww:BAAANQADCgUIBQAAAA==.Raihnese:BAEANQADCggIEQAAAA==.Ramenveg:BAAANQAECgEIAQAAAA==.Rancora:BAAANQAECgUIBQAAAA==.Ravnwing:BAAANQADCgcIDQAAAA==.',
Re='Reapersbless:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Reapersbount:BAAANQAECgEIAQAAAA==.Reapersele:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.Redbuffpls:BAAANQAFFAIIAgAAAA==.Redbul:BAAANQAECgQIBQAAAA==.Redbullz:BAAANQADCgUIBQAAAA==.Reddrock:BAAANQADCggICQAAAA==.Redstörm:BAAANQADCgcIBwAAAA==.Reffusul:BAAANQADCgMIAwABNQAECgQICAABAAAAAA==.Reilanna:BAAANQADCgYIBgAAAA==.Reptilia:BAAANQAECgYICwAAAA==.Rewef:BAAANQADCggICAABNQAFFAUIBwAEAAYZAA==.Rex:BAAANQAECgYICgAAAA==.',
Rh='Rhune:BAAANQADCgIIAgAAAA==.',
Ri='Riffz:BAAANQAECgYIDAAAAA==.Rig:BAAANQADCgYICwAAAA==.Rinzsha:BAAANQAECgEIAQAAAA==.Rishka:BAAANQADCgUIBQAAAA==.Rivien:BAAANQAECgMIAwAAAA==.',
Ro='Roostersauce:BAAANQADCgYIBgAAAA==.Rosare:BAAANQADCgEIAQAAAA==.',
Ru='Ruhkouri:BAAANQADCggIEwAAAA==.Rustibox:BAABNQAECoEZAAMKAAkJVyKcBAAjAwAKAAgJMCKcBAAjAwALAAQJxhLjHwAiAQAAAA==.',
Sa='Samardev:BAAANQADCgYIBgABNQAECgcIEAABAAAAAA==.Sammichomg:BAAANQAECgcICwAAAA==.Sammyfuego:BAAANQAECgEIAQAAAA==.Sarutko:BAAANQAECgUIBQAAAA==.',
Sc='Scalestas:BAAANQAECgUICAAAAA==.',
Se='Searing:BAAANQAECgcIEQAAAA==.Segfaulted:BAAANQAECgMIAwAAAA==.Seleane:BAAANQAECgUICAAAAA==.Sellvanya:BAAANQADCgQIBAAAAA==.Senyor:BAAANQAECgEIAQABNQAECgQIBgABAAAAAA==.Seraphia:BAAANQADCgQIBAAAAA==.Sethcure:BAAANQAECgIIAgAAAA==.',
Sh='Shaadas:BAAANQAECgUICQAAAA==.Shabazz:BAAANQADCggICAAAAA==.Shacklestorm:BAAANQADCgIIAgAAAA==.Shadeau:BAAANQADCgcIDgAAAA==.Shamackerd:BAAANQAECgIIAgABNQAECgMIAwABAAAAAA==.Shampoo:BAAANQABCgIIAQAAAA==.Shandriss:BAAANQAECgIIAgAAAA==.Shawlen:BAAANQABCgIIAgAAAA==.Sheve:BAAANQADCgQIBAAAAA==.Shockapal:BAAANQAECgIIBAAAAA==.Shrimon:BAAANQADCgIIAgAAAA==.Shrimps:BAAANQAECgQICQAAAA==.',
Si='Sidewinder:BAAANQADCggIFAAAAA==.Siong:BAAANQAECgUIBwAAAA==.Sitch:BAAANQADCgMIAQAAAA==.',
Sk='Skeletorz:BAAANQADCgYIBgAAAA==.Skunknmidget:BAAANQADCggIDgAAAA==.Skyvestris:BAAANQAECgEIAQAAAA==.',
Sl='Slamueladams:BAAANQADCgMIAwAAAA==.Slayberto:BAAANQAECgUIBwAAAA==.Sleepbringer:BAAANQAECgEIAQAAAA==.',
Sm='Smellmygas:BAAANQADCgcIFgAAAA==.Smoko:BAAANQAECgQIBgAAAA==.',
Sn='Sneaky:BAAANQAECgQIBAABNQAFFAEIAgABAAAAAA==.Sneakyr:BAAANQAFFAEIAgAAAA==.Snypar:BAAANQAECgUICAAAAA==.Snôva:BAAANQAECgEIAQAAAA==.',
So='Soaraga:BAAANQABCgQIBAAAAA==.Sodosopa:BAAANQADCgYIBgAAAA==.Solaire:BAAANQAECgIIAgAAAA==.Sole:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.Soleim:BAAANQAECgEIAQAAAA==.Somavanna:BAAANQAECgEIAQAAAA==.Sophara:BAAANQAECgUIBwAAAA==.Sorbet:BAAANQAECgYIDAAAAA==.Soulgrinder:BAAANQADCgcIDAAAAA==.',
Sp='Sparhawk:BAAANQAECgYIDAAAAA==.Sparklebolts:BAAANQADCgQIBAAAAA==.Speedwagon:BAAANQAECgQIBgAAAA==.Spicytotems:BAAANQAECgQIBAAAAA==.Spidercowsd:BAAANQADCgIIAgAAAA==.Spippy:BAAANQAECgQIBAAAAA==.Splõõsh:BAAANQAECgIIAgAAAA==.Spooky:BAAANQADCgUIBQABNQAECgkJFwAMAMsjAA==.Spro:BAAANQAECgMIAwABNQAECgcIEQABAAAAAA==.Sprogue:BAAANQAECgQICgABNQAECgcIEQABAAAAAA==.Spronatty:BAAANQADCgIIAgAAAA==.Sprosport:BAAANQAECgQIBAABNQAECgcIEQABAAAAAA==.Sprø:BAAANQAECgEIAQABNQAECgcIEQABAAAAAA==.Spurlock:BAAANQADCgYIDwAAAA==.Spyrogos:BAAANQAECgEIAQAAAA==.',
Sq='Squidbits:BAAANQAECgEIAQAAAA==.Sqwuanchigos:BAAANQADCggICAAAAA==.',
St='Stabsandhugs:BAAANQADCgQIBAAAAA==.Starclaw:BAAANQAECgYIDgAAAA==.Stasis:BAAANQAECgYICgAAAA==.Statixx:BAAANQADCgYIBgAAAA==.Stel:BAAANQAECgEIAQAAAA==.',
Su='Sugarteets:BAAANQAECgEIAQAAAA==.Sukubis:BAAANQADCgUIBQAAAA==.Supadope:BAAANQADCggIFQAAAA==.Superpaladin:BAAANQAECgEIAQAAAA==.',
Sy='Sydner:BAAANQADCggIDgAAAA==.Synergize:BAAANQADCgMIAwAAAA==.Sythila:BAABNQAECoEVAAMDAAkJNhwCBwDQAgADAAkJDRsCBwDQAgANAAYJPhi+GgDWAQAAAA==.',
['Sü']='Süblime:BAAANQADCgQIBQAAAA==.',
Ta='Tachichan:BAAANQADCgUIBQAAAA==.Tadertod:BAAANQAECgcIBwAAAA==.Talleth:BAAANQAECgYIEgAAAA==.Tallìsh:BAAANQADCgYICgAAAA==.Talorion:BAAANQAECgQIBQAAAA==.Tandrisell:BAAANQAECgEIAQAAAA==.Tassyn:BAAANQAECgUICQAAAA==.Tattianna:BAAANQAECgEIAQAAAA==.Tazenezoth:BAAANQAECgcIEAAAAA==.',
Te='Tehmachine:BAAANQAECgUICQAAAA==.Terry:BAAANQAECgEIAQAAAA==.',
Th='Thanyros:BAAANQAECgQIBQAAAA==.Thanywar:BAAANQAECgcIBwAAAA==.Thebrowner:BAAANQAECgEIAQAAAA==.Thejuice:BAAANQADCggIDQAAAA==.Thetrashman:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Thoian:BAAANQAECgEIAQAAAA==.Thork:BAAANQADCgYIBgAAAA==.Thrindy:BAAANQADCggIDwAAAA==.Thugnificint:BAAANQAECgYIBgABNQAECgcIEAABAAAAAA==.Thåwn:BAAANQAECgUIBQAAAA==.Thèokoles:BAAANQAFFAEIAQAAAA==.',
Ti='Tiblock:BAAANQAECgYIDQAAAA==.Tidalsage:BAAANQAECgYICgAAAA==.Timeskip:BAAANQADCggIDgAAAA==.Timfinnigut:BAAANQAECgUICAAAAA==.Tinkiewinkie:BAAANQADCggICAAAAA==.Tinx:BAAANQADCggIEwAAAA==.Tinylego:BAAANQADCggIFAAAAA==.Tinytiran:BAAANQAECgQIBAABNQAECgUICQABAAAAAA==.',
To='Tonktotem:BAEANQADCgEIAQABNQAECgEIAQABAAAAAA==.Toptearcryer:BAAANQAECgUICQAAAA==.Tortilla:BAAANQAECgYIDAAAAA==.Toryn:BAAANQADCgYICgABNQABCgMIAwABAAAAAA==.',
Tr='Trailwalker:BAAANQAECgIIAgAAAA==.Trashypally:BAAANQADCgYIBgAAAA==.Trecks:BAAANQADCggIDgAAAA==.Treesumm:BAAANQAECgIIAgAAAA==.Trickyrickyy:BAAANQAECgQIBQAAAA==.Triptix:BAAANQADCggIEQAAAA==.Truthbringer:BAAANQADCgQIBAAAAA==.Trynitie:BAAANQADCggIFQAAAA==.',
Tu='Turlane:BAAANQAECgYICQAAAA==.',
Tw='Twinkslayer:BAAANQADCgYIDgABNQAECgUIBgABAAAAAA==.Twinkugly:BAAANQABCgYICAAAAA==.',
Ty='Tyberia:BAAANQABCgQIBQAAAA==.Tyeret:BAAANQAECgQIBgABNQAECggIAgABAAAAAA==.',
['Tø']='Tørvald:BAAANQAECgIIAwAAAA==.',
Us='Uslurper:BAAANQAECgcIEAAAAA==.',
Va='Varenar:BAAANQAECgUICAAAAA==.',
Ve='Vearn:BAAANQADCgMIAwABNQADCggIEAABAAAAAA==.Vellamo:BAAANQADCgMIBQAAAA==.Vengeful:BAAANQADCggIEwAAAA==.Venuveus:BAAANQAECgEIAQAAAA==.Verdan:BAAANQAECgUICAAAAA==.',
Vi='Virlomi:BAABNQAECoEYAAIGAAkJxx+7AgAmAwAGAAkJxx+7AgAmAwAAAA==.',
Vl='Vlix:BAAANQADCgMIAwAAAA==.',
Vo='Vowz:BAAANQADCgYICgAAAA==.',
Vy='Vynx:BAAANQAECgEIAQAAAA==.Vyrogash:BAAANQADCgMIAwAAAA==.Vythica:BAAANQAECgYIDAAAAA==.',
Wa='Wakoguyc:BAAANQAECgQIBgAAAA==.Warcaige:BAAANQAFFAEIAQABNQAFFAUICAAOADERAA==.Wargodd:BAAANQAECggIAgAAAA==.',
We='Weierstraß:BAAANQAECgUICAAAAA==.Welari:BAAANQAECgUICAAAAA==.Weskerx:BAAANQADCggIEAAAAA==.',
Wh='Whindd:BAAANQAECgEIAQAAAA==.Whurstresort:BAAANQAECgUIBwAAAA==.Whurstyx:BAAANQADCgIIAgAAAA==.',
Wi='Wickedsoul:BAAANQADCggICAAAAA==.Widowmaker:BAAANQADCggICQAAAA==.Wif:BAAANQAECgMIBAAAAA==.Wingmancole:BAAANQADCgQIBAAAAA==.Withers:BAAANQADCgYIBgABNQAECgcICAABAAAAAA==.',
Wo='Wondrball:BAAANQAECgUIDAAAAA==.Worgen:BAAANQAECgMIAwAAAA==.',
Xa='Xalvelora:BAAANQADCgYIBgAAAA==.Xanderia:BAAANQAECgEIAQAAAA==.Xandil:BAAANQADCggICAAAAA==.',
Xe='Xeralath:BAAANQAECgUICAAAAA==.',
Xv='Xvibe:BAAANQADCggIDQAAAA==.',
Xy='Xyphira:BAAANQADCggIEgAAAA==.',
['Xý']='Xý:BAAANQADCgYIDQAAAA==.',
Ya='Yaboo:BAAANQAECgEIAQAAAA==.Yaen:BAAANQADCgUICgAAAA==.',
Ye='Yehvenâh:BAAANQAECgEIAQAAAA==.Yeska:BAAANQADCgQIBAAAAA==.',
Yo='Yootle:BAAANQAECgQIBAAAAA==.Yourgothgf:BAEANQAECgEIAQAAAA==.Yovanna:BAAANQADCgQIBAABNQAECgYIAgABAAAAAA==.',
Za='Zallo:BAAANQAECgQIBAAAAA==.Zaloria:BAAANQADCgYIBgAAAA==.Zaqws:BAAANQADCggICAAAAA==.Zarth:BAAANQADCgIIAgAAAA==.Zathral:BAAANQAECgQIAgAAAA==.Zava:BAAANQAECgQIBwAAAA==.',
Ze='Zeelos:BAAANQADCggIFgAAAA==.Zembu:BAAANQADCgQIBAAAAA==.Zephhyr:BAAANQAECgcICAAAAA==.Zephyr:BAAANQADCgQIBAAAAA==.Zeñor:BAAANQAECgQIBgAAAA==.',
Zh='Zhax:BAAANQABCgMIAwAAAA==.',
Zi='Zireael:BAAANQAECgQIBAAAAA==.',
Zo='Zornox:BAAANQADCgUIBQAAAA==.',
['Óp']='Óprawïndfury:BAAANQAECgQIBwAAAA==.',
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
