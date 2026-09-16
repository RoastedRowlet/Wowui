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

local lookup = {'Unknown-Unknown','Shaman-Elemental','Hunter-Marksmanship','Shaman-Restoration','Paladin-Holy','Hunter-BeastMastery','Mage-Arcane','DemonHunter-Havoc','Druid-Guardian','Druid-Balance','Druid-Restoration','Warrior-Arms','Evoker-Devastation','Monk-Windwalker','DeathKnight-Blood','Warrior-Fury','DeathKnight-Unholy','Paladin-Retribution','Evoker-Preservation','DemonHunter-Devourer','Priest-Shadow','Priest-Discipline','Warlock-Demonology','Warlock-Destruction','Paladin-Protection','Rogue-Assassination','Druid-Feral','Warrior-Protection',}
local provider = {region='US',realm='Korgath',name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Abbygrace:BAAANQAECgUIBgAAAA==.',
Ad='Adar:BAAANQAECgUICgAAAA==.',
Ae='Aegeis:BAAANQAECgEIAQABNQAECgYIDQABAAAAAA==.Aelaryn:BAAANQAECgEIAQAAAA==.Aeonffx:BAAANQAECgIIAgAAAA==.',
Af='Afterearth:BAABNQAECoEbAAICAAkJeySpAwCwAwACAAkJeySpAwCwAwAAAA==.',
Ag='Aggrobeast:BAAANQAECgMIAwAAAA==.Agoný:BAAANQADCgQIBAAAAA==.',
Ai='Ailie:BAAANQAECgcIEQAAAA==.',
Ak='Akadey:BAAANQADCgYICAAAAA==.',
Al='Aliì:BAAANQAECgMIBgABNQAECgkJGQADAFYdAA==.Allise:BAAANQAECgEIAQAAAA==.Allnightløng:BAAANQAECgUIEAAAAA==.Alphonos:BAAANQADCgMIAwAAAA==.Alverez:BAABNQAECoEdAAIEAAkJuiCVBABuAwAEAAkJuiCVBABuAwAAAA==.',
Am='Amorilas:BAAANQAECgYIEQAAAA==.Amunera:BAAANQADCgYIEAABNQAECgEIAQABAAAAAA==.Amàrok:BAAANQADCgUICgABNQADCgcIFQABAAAAAA==.',
An='Andersan:BAABNQAECoEdAAIFAAgJYhG8LQARAgAFAAgJYhG8LQARAgAAAA==.Anetharion:BAAANQAECgEIAQAAAA==.Animalchange:BAAANQAECgQIDAAAAA==.',
Ap='Apeth:BAAANQADCgEIAQAAAA==.Applepi:BAAANQAECgQIBQAAAA==.Aproditee:BAAANQADCgMIBAAAAA==.',
Ar='Areayl:BAAANQAECgYIDgAAAA==.Arinn:BAABNQAECoEZAAMDAAkJVh2NEwBPAgADAAgJmxeNEwBPAgAGAAcJ2RhWQgDuAQAAAA==.',
As='Ashtkal:BAAANQAECgcIEgAAAA==.Ashtoes:BAAANQAECgQICAAAAA==.Astralbubble:BAAANQAECgQICgAAAA==.',
Au='August:BAAANQADCggIEAAAAA==.Auratic:BAAANQADCgcIBwAAAA==.Automation:BAAANQADCgcIDwABNQAECgkJGAAHAIghAA==.',
Av='Avalea:BAAANQADCgUIBwAAAA==.',
Ay='Ayyvlaad:BAAANQAECgUICQAAAA==.',
Az='Azerlite:BAAANQAECgIIAgABNQAECggIGgACAHkYAA==.Azkota:BAAANQAECgQICAAAAA==.Azulwall:BAAANQAECgMIAwAAAA==.Azureros:BAAANQAECgYIDQAAAA==.',
Ba='Bandaayd:BAAANQAECgEIAQAAAA==.Bargaug:BAAANQADCgYIBgABNQAECgcIDAABAAAAAA==.Bathasar:BAAANQAECgMIAwAAAA==.Bathpally:BAAANQAECgQIBgAAAA==.',
Be='Beandh:BAAANQADCggIEAABNQAECgkJHQAIAMMdAA==.Beanygene:BAAANQADCgcICwAAAA==.Beastfury:BAAANQAECgQICAAAAA==.Beefyclap:BAAANQAECgQICAAAAA==.Begal:BAAANQAFFAIIAgAAAA==.Beha:BAAANQADCgEIAQAAAA==.Beleria:BAAANQADCgMIAwAAAA==.Bellaidd:BAABNQAECoEVAAIJAAgJgw6BCwCRAQAJAAgJgw6BCwCRAQAAAA==.Bellore:BAAANQADCgQIBAAAAA==.Benedîct:BAAANQADCgIIAgAAAA==.Bewblywoobly:BAAANQAECgQIBQAAAA==.Bezvoker:BAAANQADCgUIBQAAAA==.Beástboy:BAAANQAECgQIBgAAAA==.',
Bi='Biekdafreak:BAAANQAECgYIBgAAAA==.Bigbuffalo:BAAANQADCgYICQAAAA==.Bigdaddoo:BAAANQADCgUIBQAAAA==.Biggisign:BAAANQAECgQIBQAAAA==.Bina:BAAANQADCggICAAAAA==.Bitemenow:BAAANQADCggIFgAAAA==.Bitsobacon:BAAANQAECgQIBQAAAA==.Bizzó:BAAANQADCggICQAAAA==.',
Bl='Bladeboy:BAAANQABCgIIAgAAAA==.Blambussi:BAAANQADCgcIEgAAAA==.Blitzball:BAAANQAECgEIAQAAAA==.Blooddragoon:BAAANQAECgQICQAAAA==.Bloodycrow:BAAANQABCgMIAwAAAA==.',
Bo='Bohica:BAAANQAECgcIDwAAAA==.Bombadil:BAAANQAECgQIBgAAAA==.Bomberdeath:BAAANQAECgQIBQAAAA==.Bongrip:BAAANQAECgMIAQAAAA==.Boochstorm:BAAANQADCggIDAAAAA==.Boogiee:BAAANQADCgcIFAABNQAECgYICwABAAAAAA==.Boosh:BAAANQADCgQIBAAAAA==.Boostednub:BAAANQABCgYIDAAAAA==.',
Br='Bradington:BAAANQAECgMIAwAAAA==.Brezel:BAAANQADCgYIBgAAAA==.Briko:BAAANQABCgEIAQABNQAECgEIAwABAAAAAA==.Brond:BAAANQABCgIIAgAAAA==.Brontide:BAAANQAECgQIBQAAAA==.Bruengar:BAAANQAECgUIDAAAAA==.Bruniik:BAAANQAECgcICAAAAA==.',
Bu='Bubblehêarth:BAAANQAECgQICAAAAA==.Budapest:BAAANQAECgYIDwAAAA==.Buddyolpal:BAAANQAECgMIAwAAAA==.Bumbleh:BAAANQAECgIIAgAAAA==.Bumibe:BAAANQADCgcIBwAAAA==.Bungulator:BAABNQAECoEaAAICAAgJeRjIIQBkAgACAAgJeRjIIQBkAgAAAA==.Buné:BAAANQAECgYIDwAAAA==.Butkus:BAAANQADCgYIBgABNQADCggIGAABAAAAAA==.',
Ca='Caad:BAAANQADCggIGQAAAA==.Cador:BAAANQAECgEIAwAAAA==.Cadwarr:BAAANQADCgYIBgAAAA==.Cak:BAAANQADCgMIAwABNQAECgIIAwABAAAAAA==.Cam:BAAANQAECgMIBQAAAQ==.Camazotz:BAAANQADCgMIAgAAAA==.Cannibubz:BAAANQAECgIIAwAAAA==.Cannimal:BAABNQAECoEXAAIKAAkJAx29DAAYAwAKAAkJAx29DAAYAwAAAA==.Cataylst:BAAANQAECgEIAQAAAA==.Catwilliams:BAAANQAECgcIEwAAAA==.',
Ce='Celestas:BAAANQADCgIIAgAAAA==.',
Ch='Cheeze:BAAANQADCgcICwAAAA==.Chiliwop:BAAANQAECgUICgAAAA==.Chippydk:BAAANQADCgYICAAAAA==.Chippyh:BAAANQAECgYICgAAAA==.Chippym:BAAANQADCgQIBAAAAA==.Chloei:BAAANQAECgMIBAAAAA==.Chwonk:BAAANQAECgMIAwAAAA==.',
Ci='Circê:BAAANQADCgYICwAAAA==.Cirin:BAAANQAECgEIAQAAAA==.',
Cl='Clevoker:BAAANQAECgcIEwAAAA==.Cloacussy:BAAANQADCgYIBgAAAA==.Clusion:BAAANQAECgYIBwAAAA==.',
Co='Codex:BAAANQAECgQICAAAAA==.Cole:BAAANQADCggIDAAAAA==.Conanb:BAAANQABCgIIAgAAAA==.Conductor:BAAANQAECgQIDgAAAA==.Convergent:BAAANQAECgYIEQAAAA==.Coosh:BAABNQAECoEbAAIHAAkJ3CEXEABoAwAHAAkJ3CEXEABoAwAAAA==.Corov:BAAANQAECgEIAQAAAA==.Courigon:BAAANQAECgEIAQAAAA==.',
Cp='Cptamerica:BAAANQAECggIDAAAAA==.',
Cr='Craigolas:BAAANQAECgEIAQAAAA==.Crippler:BAAANQADCggIEQAAAA==.Crossbow:BAAANQADCgMIBgAAAA==.Crosscut:BAAANQAECgEIAQAAAA==.Cruelty:BAAANQADCgQIBAAAAA==.',
Cu='Cummins:BAABNQAECoEZAAILAAgJhB9nCAC+AgALAAgJhB9nCAC+AgAAAA==.Currents:BAAANQADCggICAAAAA==.',
Da='Dadstealer:BAAANQAECgIIAgAAAA==.Daemonwing:BAAANQADCgMIAwAAAA==.Dagrundel:BAAANQAECgQIBQAAAA==.Dalinarix:BAAANQAECgEIAQAAAA==.Dankpope:BAAANQAECgIIAgAAAA==.Darkballs:BAAANQADCgEIAQABNQAECgQIBgABAAAAAA==.Davrin:BAAANQAECgYIDwAAAA==.',
De='Deathbyarow:BAAANQAECgQIBQAAAA==.Deathhammer:BAAANQAECgQIBQAAAA==.Deathjrak:BAAANQAECgYIDgAAAA==.Deesixxfour:BAAANQADCgUIBQABNQAECgcIEAABAAAAAA==.Degates:BAAANQAECgIIAgAAAA==.Demonia:BAAANQAECgQIBgAAAA==.Demonicshoes:BAAANQAECgEIAQAAAA==.Dethwing:BAAANQAECgUICgAAAA==.Devaña:BAAANQAECgQIBAAAAA==.',
Di='Diclonius:BAAANQAECgMIAwAAAA==.Dirtystaff:BAAANQADCggIEwAAAA==.Dirtzmage:BAAANQAECgUICQAAAA==.Dirtzz:BAAANQADCgQIBAAAAA==.Dizzledh:BAAANQAECgQIBgAAAA==.',
Dj='Djkhaledd:BAAANQAECgcICAAAAA==.',
Do='Doobins:BAAANQAECgMIAwAAAA==.Dookiboy:BAAANQADCggIDgABNQAECgcIEAABAAAAAA==.Dooy:BAAANQAECgMIAwAAAA==.Douii:BAAANQADCggICAAAAA==.',
Dr='Draco:BAAANQABCgQICAAAAA==.Draconir:BAAANQABCgYICAAAAA==.Dragao:BAAANQADCgYIBgAAAA==.Draggen:BAAANQAECgUICwAAAA==.Dragimal:BAAANQAECgEIAQAAAA==.Dragonn:BAAANQAECgQICAAAAA==.Dragonoied:BAAANQADCgMIAwAAAA==.Dragonxlord:BAAANQABCgMIAwAAAA==.Dragosia:BAAANQAECgYIEwAAAA==.Drakojangens:BAAANQAECgUICQABNQAECggIEQABAAAAAA==.Drakthar:BAAANQADCggIEgAAAA==.Dranoric:BAAANQADCggIDAAAAA==.Dreebus:BAAANQADCgYIBgABNQAECgYIDwABAAAAAA==.Drlawyerphd:BAAANQAECgcIEQAAAA==.Druz:BAAANQAECgIIAgAAAA==.',
Ds='Dsixxfour:BAAANQAECgcIEAAAAA==.',
Du='Duncedivh:BAAANQADCgYIDgAAAA==.Dunzjan:BAAANQAECgQICQAAAA==.Durrinn:BAAANQADCgcIBwABNQAECgYIDAABAAAAAA==.',
Dy='Dysmai:BAAANQADCgYICwAAAA==.',
['Dé']='Déathwolf:BAAANQAECgUIDAAAAA==.',
Ea='Eatsammich:BAAANQADCggIEQAAAA==.',
Eg='Eggsbenedïct:BAAANQAECgcIEAAAAA==.Egol:BAAANQAECgcIEgAAAA==.',
El='Eldonra:BAAANQADCgYIBgABNQAECgkJGAAMAH4gAA==.Elidrine:BAAANQAECgQIBAAAAA==.Elmerfuddz:BAAANQAECgUICAAAAA==.Elyrayldin:BAAANQAECgMIAwAAAA==.',
En='Enazenoth:BAABNQAECoEWAAINAAkJbSGbAgBbAwANAAkJbSGbAgBbAwAAAA==.Enryu:BAAANQAECgYICgAAAA==.Envburnz:BAAANQAECgQIBAAAAA==.',
Er='Erooka:BAAANQAECgcIEAAAAA==.',
Es='Esio:BAAANQAECggIEgAAAA==.',
Ev='Evileyes:BAAANQADCgUIBQABNQADCggICAABAAAAAA==.',
Ey='Eyri:BAAANQAECgUIDgAAAA==.',
Ez='Ezzie:BAAANQAECgMIAwAAAA==.',
Fa='Falsodew:BAABNQAECoEWAAIEAAgJ2xm6JwApAgAEAAgJ2xm6JwApAgAAAA==.',
Fe='Felicity:BAAANQAECgUICAAAAA==.Femmever:BAAANQAECgEIAQAAAA==.Feonix:BAAANQAECgcIEwAAAA==.Ferenus:BAAANQABCggICAAAAA==.Fewsha:BAACNQAFFIEMAAICAAYJ6hycAABHAgACAAYJ6hycAABHAgA1AAQKgR0AAgIACQkdJMsEAJsDAAIACQkdJMsEAJsDAAAA.',
Fi='Fidellia:BAAANQAECgIIAgAAAA==.Findie:BAAANQAECgUIBQAAAA==.',
Fo='Foofoolala:BAAANQADCgYICwAAAA==.Fookadk:BAAANQADCggIEwAAAA==.Fookapalli:BAAANQABCgYICgAAAA==.Forttoo:BAAANQADCgEIAQAAAA==.Fourthwing:BAAANQADCgQIBAAAAA==.',
Fr='Frawstbyte:BAAANQAECgcIEwAAAA==.Fredbearr:BAAANQADCgMIAwAAAA==.Freeholed:BAAANQAECgcIEQAAAA==.Fridgefister:BAAANQAECgQIBAAAAA==.Frodie:BAAANQAECgYIDQAAAA==.',
Fu='Fumina:BAAANQAECgEIAQAAAA==.',
Ga='Gaea:BAAANQAECgQICAAAAA==.Gallanon:BAAANQADCgcIDAAAAA==.Gallshot:BAAANQADCgUIBQAAAA==.Gamergirl:BAAANQABCgcIBwAAAA==.Gangrêl:BAAANQADCgYIDAABNQAECgEIAQABAAAAAA==.Garithor:BAAANQADCgUIBQAAAA==.',
Gb='Gbang:BAAANQAECgIIAwAAAA==.',
Ge='Gekidoryu:BAAANQADCgQIBAABNQAECgMIAwABAAAAAA==.Gerebert:BAAANQAECgQIBQAAAA==.Getajobubum:BAAANQAECgUIDAAAAA==.',
Gh='Ghalizor:BAAANQADCgYIBgABNQAECgIIAwABAAAAAA==.Ghostdance:BAACNQAFFIEFAAIHAAMJPh1QDAAbAQAHAAMJPh1QDAAbAQA1AAQKgR8AAgcACQktJDYHAKQDAAcACQktJDYHAKQDAAAA.Ghoulia:BAAANQADCgcIGQAAAA==.',
Gi='Giggz:BAAANQAECgIIAwAAAA==.Gingerpala:BAAANQADCgQIBwAAAA==.Giuttrix:BAAANQADCgcIFAAAAA==.',
Gl='Glacie:BAAANQADCgYIBgAAAA==.Gleams:BAAANQAECgIIAgAAAA==.Gloriousdead:BAAANQADCgYIBgAAAA==.Glowing:BAAANQADCggIGQAAAA==.',
Go='Gokukakarot:BAAANQAECgIIAgAAAA==.Goldlore:BAAANQAECgIIAgAAAA==.Goopdk:BAAANQAECgQIBQAAAA==.Gosiâ:BAAANQAECgMIBAABNQAECgYIEwABAAAAAA==.Gothikia:BAAANQAECgMIAwAAAA==.',
Gr='Gremhunt:BAAANQAECgIIAgAAAA==.Grondel:BAAANQAECgQIBgAAAA==.Grumpybear:BAAANQADCgcIDwAAAA==.',
Gu='Gundham:BAAANQADCggIGwAAAA==.Gunko:BAAANQAECgQIBAAAAA==.Gunstrong:BAAANQAECgMIAwAAAA==.',
['Gõ']='Gõsia:BAAANQAECgQIBAAAAA==.',
['Gø']='Gøtt:BAAANQADCgIIAgAAAA==.',
Ha='Haagendots:BAAANQAECgMIAwAAAA==.Hairofwar:BAAANQAECgUIDAAAAA==.Haleynicole:BAAANQAECgMIAwAAAA==.Happydaug:BAAANQADCgcICwABNQAECgkJGAAOAGEdAA==.Happydawg:BAABNQAECoEYAAIOAAkJYR3fBwDpAgAOAAkJYR3fBwDpAgAAAA==.Hasted:BAABNQAECoEYAAIHAAkJiCGTEABlAwAHAAkJiCGTEABlAwAAAA==.Hawktar:BAAANQAECgYIDAAAAA==.',
He='Healimus:BAAANQAECgUIDAAAAA==.Healmates:BAAANQAECgYICQAAAA==.Helix:BAABNQAECoEZAAIEAAgJTh1uGACTAgAEAAgJTh1uGACTAgAAAA==.Hennybull:BAAANQADCgIIAgAAAA==.Henný:BAAANQADCgQIBAAAAA==.Hesperos:BAAANQADCgYIBgAAAA==.',
Hm='Hmmfock:BAAANQADCggICAAAAA==.',
Ho='Ho:BAAANQAECgcIBwAAAA==.Holee:BAAANQADCgIIAgAAAA==.Holybaby:BAAANQAECgYIDAAAAA==.Holybrute:BAAANQAECgIIAwABNQAECgYIDwABAAAAAA==.Holybunger:BAAANQAECgIIAwAAAA==.Holyscheisse:BAAANQAECggIAwAAAA==.Holysheetz:BAAANQABCgQIBAAAAA==.Horde:BAAANQADCgcICwAAAA==.',
Hu='Hueycheeks:BAAANQAECgcIEwAAAA==.Huntstatus:BAABNQAECoEaAAIGAAgJGREWXQCIAQAGAAgJGREWXQCIAQAAAA==.Huxium:BAAANQAECgcIEQAAAA==.',
Hw='Hwangdoyoung:BAAANQABCgEIAQABNQADCgEIAQABAAAAAA==.',
Hy='Hymnpossible:BAAANQAECgQIBQAAAA==.',
Ic='Icecreamdveg:BAAANQABCgUIBQAAAA==.Icetongue:BAAANQAECgYICwAAAA==.',
If='Iflingpoo:BAABNQAECoEXAAIPAAgJQRjUHAA4AgAPAAgJQRjUHAA4AgAAAA==.Ifusêekamy:BAAANQADCggIGwAAAA==.',
Ij='Ijrakwarrior:BAAANQAECgIIAgAAAA==.',
Il='Illidussy:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.Illregularxx:BAAANQAECgEIAQAAAA==.',
Im='Impulse:BAAANQAECgUICwAAAA==.',
In='Indelebi:BAAANQABCgQIBgAAAA==.Inorgeing:BAAANQAECgMIBAAAAA==.Intrúder:BAAANQADCgEIAQAAAA==.',
Ir='Irdaman:BAAANQAECgEIAQAAAA==.Irmengaud:BAAANQAECgEIAQAAAA==.Ironpup:BAAANQAECgQIBAAAAA==.Ironscales:BAAANQAECgQIAQAAAA==.',
Ja='Jabbyjr:BAABNQAECoEXAAMQAAgJng9gBQD5AQAQAAgJng9gBQD5AQAMAAEJTQ2W0gA8AAAAAA==.Jabum:BAAANQAECgcICgAAAA==.Jaio:BAAANQAECgQIBAAAAA==.Jajakuna:BAAANQAECgEIAQAAAA==.Jangens:BAAANQAECggIEQAAAA==.Jarofsomethi:BAAANQAECgQIBAAAAA==.Jaruni:BAAANQAECgUIDAAAAA==.Jaynine:BAAANQAECggIEQAAAA==.',
Je='Jeffvyrt:BAAANQAECgQIBwAAAA==.Jeksulee:BAAANQABCggIEAAAAA==.',
Ji='Jibbs:BAAANQAECgQIBAAAAA==.',
Jo='Jodimaw:BAAANQADCggICAAAAA==.Jorian:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.Joridiezs:BAAANQAECgMIAwAAAA==.Joshness:BAAANQADCgMIAwAAAA==.',
Ju='Juanrambo:BAAANQAECgQIBAAAAA==.Juicyjohnson:BAAANQADCgMIAwABNQAECgYICgABAAAAAA==.Jumblo:BAAANQAECgMIAwAAAA==.Jupileo:BAAANQAECgUIBwAAAA==.Jurassichots:BAAANQADCgYIDAAAAA==.',
Ka='Kaalista:BAAANQAECgEIAgABNQAECgYIDAABAAAAAA==.Kailee:BAACNQAFFIEKAAIOAAUJlR5qAQDbAQAOAAUJlR5qAQDbAQA1AAQKgSEAAg4ACQltJR8BAMYDAA4ACQltJR8BAMYDAAE1AAQKAQgBAAEAAAAA.Kaito:BAAANQAECgEIAQAAAA==.Kakaboy:BAAANQADCgMIAwABNQAECgcIEAABAAAAAA==.Kaolis:BAAANQADCggICQAAAA==.Kariba:BAAANQAECgYIDQABNQAECgkJHgARAPYkAA==.Karmana:BAAANQAECggICQAAAA==.Katael:BAAANQADCgYICwAAAA==.Kavel:BAAANQAECgcIDgAAAA==.Kaylie:BAAANQAECgEIAQAAAA==.Kayti:BAAANQAECgMIAwAAAA==.',
Ke='Kelfiona:BAAANQADCgcIFAAAAA==.Keraboo:BAAANQAECgUIBQAAAA==.Kerie:BAAANQAECgQIBQAAAA==.Ketamyne:BAAANQADCggIFgAAAA==.Keynin:BAAANQADCgUIBQAAAA==.',
Kh='Khalu:BAAANQADCgEIAQAAAA==.',
Ki='Kiandron:BAAANQADCgYIDgAAAA==.Killerqtlol:BAAANQADCggIEQABNQAECgcIDwABAAAAAA==.Kimbostab:BAAANQADCgMIBAAAAA==.',
Kn='Knockbak:BAAANQAECgQIBQAAAA==.',
Ko='Kohko:BAAANQADCgYIBgAAAA==.Kozinirus:BAAANQAECgEIAQAAAA==.',
Kq='Kqmav:BAAANQAECgUICQAAAA==.',
Kr='Kromewell:BAAANQADCgYIBgAAAA==.Kruwll:BAAANQAECgQIBAAAAA==.Krít:BAAANQADCggICgABNQADCgQIBAABAAAAAA==.',
Ku='Kumolock:BAAANQAECgQICAAAAA==.Kuongsun:BAAANQADCggIEAAAAA==.',
['Kú']='Kúrama:BAAANQABCgYICAAAAA==.',
La='Ladeehunter:BAAANQAECgQIBgAAAA==.Lambsbreath:BAAANQADCggIDgAAAA==.Lanto:BAAANQADCgUICAABNQABCgIIAgABAAAAAA==.Laprofessora:BAAANQADCggICAAAAA==.Laquince:BAAANQAECgQIBQAAAA==.Lasagnazaddy:BAAANQADCgYICwAAAA==.Laurafel:BAAANQADCgUIBQAAAA==.',
Le='Leetlee:BAAANQADCgMIAwAAAA==.Lelouché:BAAANQABCgIIAgABNQABCgYICAABAAAAAA==.Lertglochen:BAAANQAECgMICAAAAA==.Lexistarr:BAEANQAECgQIBAAAAA==.',
Li='Lickmelow:BAAANQADCgEIAQAAAA==.Lightbunz:BAAANQADCgQIBAAAAA==.Lightcast:BAAANQAECgIIAgABNQAECgkJGgALADIfAA==.Lightra:BAAANQAECgEIAQAAAA==.Limeywater:BAAANQAECgYIDQAAAA==.Lindramech:BAAANQADCgYIBgAAAA==.Litherous:BAAANQAECgQICAAAAA==.Litzdh:BAAANQAECgQIBQAAAA==.',
Ll='Llazereth:BAAANQAECgYIDwAAAA==.Llordvalar:BAAANQADCgIIAgAAAA==.',
Lo='Lockimar:BAEANQAECgcIEQAAAA==.Lockuru:BAAANQAECgcIEgAAAA==.Lonestàr:BAAANQAECgQIBQAAAA==.Lowiqslowirl:BAAANQABCgIIAgAAAA==.',
Lu='Lucidy:BAAANQAECgYIBwAAAA==.Lumberjacked:BAAANQAECgMIAwABNQAECggIEgABAAAAAA==.Luna:BAAANQADCgYIDQABNQAECgcIDwABAAAAAA==.Luspriest:BAAANQADCgQIBAAAAA==.Lusuffer:BAAANQAECgYIDgAAAA==.Lusufferr:BAAANQADCgYIEgABNQAECgYIDgABAAAAAA==.Lutra:BAAANQAECgYIDgAAAA==.',
Ly='Lyx:BAAANQAECgQIBQAAAA==.',
Ma='Magerpwn:BAAANQADCgUIBQAAAA==.Magusarcanus:BAAANQADCgQIBAAAAA==.Makrio:BAAANQABCgUIBwAAAA==.Malachî:BAAANQADCgcIBwAAAA==.Malitan:BAABNQAECoEZAAISAAgJLRfHOAAbAgASAAgJLRfHOAAbAgAAAA==.Mamif:BAAANQAECgMIAwAAAA==.Manfrony:BAAANQADCggICAABNQAECgQICAABAAAAAA==.Mannasto:BAAANQADCgYIBgAAAA==.Manuelek:BAAANQAECgEIAQAAAA==.Markatron:BAAANQAECgYICwAAAA==.Mattiekay:BAAANQAECgYIDAAAAA==.Maxx:BAAANQAECgYIBgAAAA==.Mañajuana:BAAANQAECgYIDgAAAA==.',
Me='Meatrocket:BAAANQADCgYIBgABNQAECgcIEwABAAAAAA==.Meefalo:BAAANQAECgQICAAAAA==.Meganfox:BAAANQADCggICAAAAA==.Meggfox:BAAANQADCgQIBAAAAA==.Meghanics:BAAANQADCgYIDAAAAA==.Meileen:BAAANQADCgEIAQAAAA==.Menethol:BAAANQADCgUIBQABNQAECgYIIgAHAEUbAA==.Mercymage:BAAANQADCgQIBAAAAA==.Merie:BAAANQADCgUIBQABNQAECgQIBgABAAAAAA==.Merlinswrath:BAAANQADCgYIBAAAAA==.Merril:BAAANQABCgcICQABNQAECgkJGgATAA0dAA==.Merza:BAAANQADCggICAABNQAECgkJGQAUACcaAA==.Merzinator:BAABNQAECoEZAAMUAAkJJxpCDQDFAgAUAAkJJxpCDQDFAgAIAAIJdwFrTQA6AAAAAA==.',
Mi='Mickle:BAAANQADCgEIAQAAAA==.Midgrad:BAAANQADCggIDgABNQAECgQIBwABAAAAAA==.Mikelowry:BAAANQAECgQIBAAAAA==.Minimum:BAAANQAECgQIBAABNQAECgUIBQABAAAAAA==.Mischeveous:BAAANQAECgUIBwAAAA==.Missu:BAAANQADCgEIAQAAAA==.Mithrandir:BAAANQAECgYIDAAAAA==.',
Mj='Mjiltanke:BAAANQAECgIIAwAAAA==.',
Mo='Moistcarry:BAAANQADCgUIBQAAAA==.Mokniahiah:BAAANQAECgUIBwAAAA==.Monkmates:BAAANQAECgEIAQAAAA==.Moodoon:BAAANQAECgIIAgAAAA==.Moohammadali:BAAANQADCgYIBgAAAA==.Mooseyfate:BAAANQAECgQIBAAAAA==.Moraxy:BAAANQAECgIIAgAAAA==.Moromagus:BAAANQAECgcIEgAAAA==.Mortis:BAAANQAECgQIBAAAAA==.Motorboats:BAAANQADCgYICgAAAA==.',
Mu='Mualpractice:BAAANQADCgQIBQAAAA==.Murdok:BAAANQAECgEIAQAAAA==.Murray:BAAANQAECgcIBwABNQAFFAMIBQAPAD0FAA==.Mutknodeprac:BAAANQAECgMIAwAAAA==.',
Mx='Mxsery:BAAANQAECgQIBgAAAA==.Mxz:BAAANQADCgcIBwABNQAECggIGgACAHkYAA==.',
My='Myræl:BAAANQAECgMIAwAAAA==.Mystíle:BAABNQAECoEfAAIRAAkJ7yRoAgC7AwARAAkJ7yRoAgC7AwAAAA==.Mythrix:BAAANQABCgIIAgABNQADCgcIDgABAAAAAA==.Mythrixx:BAAANQADCgcIDgAAAA==.',
['Mà']='Màjíque:BAAANQAECgQIBQAAAA==.',
['Mé']='Méadow:BAAANQADCgcIFQAAAA==.',
Na='Nabesan:BAAANQADCgIIAgAAAA==.Naked:BAAANQADCggIBAAAAA==.Nalera:BAAANQAECggIBwAAAA==.Narhi:BAAANQAECgMIAwAAAA==.Nasminthe:BAAANQAECgEIAQAAAA==.Nature:BAAANQADCgUIBQAAAA==.Naughtya:BAAANQAECgQIBAAAAA==.Nazem:BAAANQAECgEIAQAAAA==.',
Ne='Nekoro:BAAANQAECgYIDwAAAA==.Nelfsquantch:BAAANQADCgcIEgAAAA==.Nevadawolf:BAAANQAECgQIBAAAAA==.',
Ni='Nightreaver:BAAANQADCgcIEAAAAA==.Nightshiftér:BAAANQAECgEIAgAAAA==.Nimbex:BAAANQADCgQIBAAAAA==.Ninetailsfox:BAAANQAECgcIEAAAAA==.Nion:BAAANQAECgQICAAAAA==.Nippy:BAAANQADCgYIBgABNQAECgQICQABAAAAAA==.',
No='Nolo:BAAANQADCgQIBQAAAA==.Northzen:BAAANQAECgYIDgAAAA==.Notaorc:BAAANQADCgUIBQAAAA==.Notmyconcern:BAAANQADCgYIBgAAAA==.Novaflux:BAAANQAECgYIEAAAAA==.Noxxicc:BAAANQAECgMIAwABNQAECgYIDgABAAAAAA==.',
Ny='Nyghtterror:BAAANQAECgEIAQAAAA==.Nyreeh:BAAANQADCggIGAAAAA==.Nytearcher:BAAANQAECgYICgAAAA==.Nyxa:BAAANQAECgIIAwAAAA==.',
['Ná']='Nálera:BAAANQADCggIEAAAAA==.',
['Nü']='Nüguns:BAAANQAECgEIAQAAAA==.',
Ok='Okamifist:BAAANQADCgYIBgAAAA==.Oklyra:BAAANQABCgYICgAAAA==.',
Om='Omnia:BAAANQAECgYIDwABNQABCgMIAwABAAAAAA==.',
On='Onlyshams:BAAANQADCgMIAwAAAA==.',
Oo='Oogiee:BAAANQAECgYICwAAAA==.',
Or='Orcmonk:BAAANQADCgcIDgAAAA==.',
Os='Oschun:BAAANQAECgcIEgAAAA==.',
Pa='Palacandia:BAAANQADCgYIBQAAAA==.Palanar:BAAANQAECgcIEwAAAA==.Palle:BAAANQAECgYIBgAAAA==.Pallyboi:BAAANQAECgMIBQAAAA==.Paluru:BAAANQAECgEIAQABNQAECgcIEgABAAAAAA==.Panosh:BAAANQADCgUIBQAAAA==.Pantricelog:BAAANQADCggICAABNQAECgYIDQABAAAAAA==.',
Pc='Pchef:BAAANQAECgQIBgAAAA==.',
Pe='Pelayo:BAAANQADCggIGAAAAA==.Peperoninips:BAAANQAECgIIAgAAAA==.Petricia:BAAANQAECgYIDQAAAA==.',
Pf='Pfeffer:BAAANQAECgQIBAAAAA==.',
Ph='Phaithful:BAABNQAECoEbAAMVAAkJUx6nBwAbAwAVAAkJUx6nBwAbAwAWAAEJCwmEGQA1AAAAAA==.Phazerman:BAAANQAECgQICAAAAA==.Phocus:BAAANQAECgcICgABNQAECgkJGwAVAFMeAA==.Phury:BAAANQAECgYIBgABNQAECgkJGwAVAFMeAA==.',
Pi='Pikapikapika:BAAANQAECgUICQAAAA==.',
Pl='Planthoofem:BAAANQAECgEIAQAAAA==.Playpride:BAAANQAECgQIBQAAAA==.',
Po='Poboy:BAAANQAECgYICgAAAA==.Pocket:BAAANQADCggIFQABNQAECgcIDwABAAAAAA==.Pokepokepoke:BAAANQAECgUICQAAAA==.Poppop:BAAANQAECgQIBQAAAA==.Poriand:BAAANQAECgMIBAAAAA==.Portzul:BAAANQAECgEIAQAAAA==.',
Pr='Priesttea:BAAANQAECgEIAQAAAA==.Procology:BAAANQABCgEIAQAAAA==.',
Ps='Pseudogrim:BAAANQAECgYIDAAAAA==.Psspspss:BAAANQADCgYIBgAAAA==.',
Pu='Pugnosano:BAAANQADCgQIBAAAAA==.Pussnboots:BAAANQAECgQIBAAAAA==.',
['Pö']='Pöppop:BAAANQADCgcIBwABNQAECgQIBQABAAAAAA==.',
Ra='Raefe:BAAANQAECgMIAwAAAA==.Raffaj:BAAANQAECgMIAwAAAA==.Raidedww:BAAANQADCgUIBQAAAA==.Raihnese:BAEANQAECgQIBAAAAA==.Ramenveg:BAAANQAECgQIBQAAAA==.Rancora:BAAANQAECgYICwAAAA==.Ravnsifu:BAAANQADCgUIBQAAAA==.Ravnwing:BAAANQADCggIFQAAAA==.',
Re='Reapersbless:BAAANQAECgEIAQABNQAECgEIAgABAAAAAA==.Reapersbount:BAAANQAECgEIAgAAAA==.Reapersele:BAAANQADCgMIAwABNQAECgEIAgABAAAAAA==.Redbuffpls:BAABNQAECoEcAAISAAkJZCWbAgDPAwASAAkJZCWbAgDPAwAAAA==.Redbul:BAAANQAECgQIBQAAAA==.Redbullz:BAAANQADCgUIBQAAAA==.Reddrock:BAAANQADCggIDwAAAA==.Redstörm:BAAANQADCgcIBwAAAA==.Reffusul:BAAANQADCgMIAwABNQAECgYIDgABAAAAAA==.Reilanna:BAAANQADCgYICwAAAA==.Reptilia:BAAANQAECgcIEgAAAA==.Rewef:BAAANQAECgIIAgABNQAFFAYIDAACAOocAA==.Rex:BAAANQAECgYIEAAAAA==.',
Rh='Rhune:BAAANQADCgIIAgAAAA==.',
Ri='Riffz:BAAANQAECgcIEwAAAA==.Rig:BAAANQAECgQIBAAAAA==.Rinzsha:BAAANQAECgQIBQAAAA==.Rishka:BAAANQADCgUIBQAAAA==.Riv:BAAANQADCggICAABNQAECgQIBwABAAAAAA==.Rivien:BAAANQAECgQIBwAAAA==.',
Ro='Roostersauce:BAAANQADCgYIBgAAAA==.Rosare:BAAANQADCgEIAQAAAA==.',
Ru='Ruhkouri:BAAANQADCggIGwAAAA==.Rulez:BAAANQADCgQIBAAAAA==.Rustibox:BAACNQAFFIEJAAMXAAUJtA1NCADrAAAXAAMJcQxNCADrAAAYAAIJlw/pBQCvAAA1AAQKgSIAAxcACQkSIw0DAIEDABcACQnJIg0DAIEDABgABAnoErAiACMBAAAA.',
Sa='Samardev:BAAANQADCgYIBgABNQAECgkJGgATAA0dAA==.Sammichomg:BAAANQAECgcIEgAAAA==.Sammyfuego:BAAANQAECgMIAwAAAA==.Sarutko:BAAANQAECgUIBQAAAA==.',
Sc='Scalestas:BAAANQAECgUIDAAAAA==.',
Se='Searing:BAABNQAECoEXAAIZAAkJuRiBBwCSAgAZAAkJuRiBBwCSAgAAAA==.Segfaulted:BAAANQAECgQIBwAAAA==.Seleane:BAAANQAECgUIDAAAAA==.Sellvanya:BAAANQADCgQIBAAAAA==.Senyor:BAAANQAECgEIAQABNQAECgQICQABAAAAAA==.Seraphia:BAAANQADCgQIBAAAAA==.Sethcure:BAAANQAECgIIAgAAAA==.',
Sh='Shaadas:BAAANQAECgYIEAAAAA==.Shabazz:BAAANQADCggIEQABNQADCggIGAABAAAAAA==.Shacklestorm:BAAANQADCgIIAgAAAA==.Shadeau:BAAANQADCgcIDgAAAA==.Shamackerd:BAAANQAECgQIBgAAAA==.Shampoo:BAAANQABCgQIAwAAAA==.Shandriss:BAAANQAECgIIAwAAAA==.Shawlen:BAAANQABCgIIAgAAAA==.Sheve:BAAANQADCgQIBAAAAA==.Shmimon:BAAANQAECgMIAwAAAA==.Shockapal:BAAANQAECgUICQAAAA==.Shockvalue:BAAANQAECgEIAQAAAA==.Shrimon:BAAANQADCgIIAgAAAA==.Shrimps:BAAANQAECgQICgAAAA==.',
Si='Sidewinder:BAAANQAECgIIAgAAAA==.Siong:BAAANQAECgYICAAAAA==.Sitch:BAAANQADCgMIAgAAAA==.',
Sk='Skeletorz:BAAANQADCgYIDAAAAA==.Skunknmidget:BAAANQADCggIDgAAAA==.Skyvestris:BAAANQAECgIIAwAAAA==.',
Sl='Slamueladams:BAAANQADCgMIAwAAAA==.Slayberto:BAAANQAECgYIDQAAAA==.Sleepbringer:BAAANQAECgEIAQAAAA==.Sloppysecond:BAAANQADCgQIBAAAAA==.',
Sm='Smellmygas:BAAANQAECgEIAQAAAA==.Smoko:BAAANQAECgUICwAAAA==.',
Sn='Sneaky:BAAANQAECgYICgABNQAECgkJHQAJAM0kAA==.Sneakyr:BAABNQAECoEdAAIJAAkJzSRtAADQAwAJAAkJzSRtAADQAwAAAA==.Snypar:BAAANQAECgUIDAAAAA==.Snôva:BAAANQAECgQIBQAAAA==.',
So='Soaraga:BAAANQABCgQIBAAAAA==.Sodosopa:BAAANQADCgYIBgAAAA==.Solaire:BAAANQAECgIIBAAAAA==.Sole:BAAANQADCgcIBwABNQAECgQIBQABAAAAAA==.Soleim:BAAANQAECgQIBQAAAA==.Somavanna:BAAANQAECgQIBQAAAA==.Sophara:BAAANQAECgUIBwAAAA==.Sorbet:BAAANQAECgcIEwAAAA==.Soulgrinder:BAAANQADCggIFAAAAA==.',
Sp='Sparhawk:BAAANQAECgcIEwAAAA==.Sparklebolts:BAAANQADCgQIBAAAAA==.Speedwagon:BAAANQAECgUICwAAAA==.Spicytotems:BAAANQAECgUICQAAAA==.Spidercowsd:BAAANQADCgIIAgAAAA==.Spippy:BAAANQAECgQIBAAAAA==.Spitzer:BAAANQADCgEIAQAAAA==.Splõõsh:BAAANQAECgYIDgAAAA==.Spooky:BAAANQADCgYICwABNQAECgkJHAAaAMsjAA==.Spro:BAAANQAECgMIAwABNQAECgkJHQAIAAIiAA==.Sprogue:BAAANQAECgUIDwABNQAECgkJHQAIAAIiAA==.Spronatty:BAAANQADCgIIAgAAAA==.Sprosport:BAAANQAECgQIBwABNQAECgkJHQAIAAIiAA==.Sprø:BAAANQAECgEIAQABNQAECgkJHQAIAAIiAA==.Spurlock:BAAANQADCgcIFgAAAA==.Spyrogos:BAAANQAECgEIAgAAAA==.',
Sq='Squidbits:BAAANQAECgQIBQAAAA==.Sqwuanchigos:BAAANQADCggICAAAAA==.',
St='Stabsandhugs:BAAANQADCgQIBAAAAA==.Starclaw:BAABNQAECoEWAAIbAAgJUCOaAQBXAwAbAAgJUCOaAQBXAwAAAA==.Stasis:BAAANQAECgcIEQAAAA==.Statixx:BAAANQADCgYIBgAAAA==.Stel:BAAANQAECgEIAQAAAA==.Styrmir:BAAANQABCgIIAgAAAA==.',
Su='Sugarteets:BAAANQAECgMIBAAAAA==.Sukubis:BAAANQADCgUIBQAAAA==.Supadope:BAAANQADCggIHQAAAA==.Superpaladin:BAAANQAECgQIBQAAAA==.',
Sy='Sydner:BAAANQAECgMIAwAAAA==.Synergize:BAAANQADCgMIAwAAAA==.Sythila:BAABNQAECoEdAAMIAAkJwx1zCwDWAgAIAAkJmhxzCwDWAgAUAAYJPhjOIQDAAQAAAA==.',
['Sé']='Séamus:BAAANQADCgYIBgAAAA==.',
['Sü']='Süblime:BAAANQAECggIBgAAAA==.',
Ta='Tachichan:BAAANQADCgUIBQAAAA==.Tadertod:BAAANQAECggIDwAAAA==.Talleth:BAABNQAECoEhAAINAAkJEh3fAwAnAwANAAkJEh3fAwAnAwAAAA==.Tallìsh:BAAANQADCgYICgAAAA==.Talorion:BAAANQAECgYICwAAAA==.Tandrisell:BAAANQAECgEIAQAAAA==.Tassyn:BAAANQAECgYIDwAAAA==.Tattianna:BAAANQAECgMIAwAAAA==.Tazenezoth:BAABNQAECoEaAAITAAkJDR0DBwDiAgATAAkJDR0DBwDiAgAAAA==.',
Te='Tehmachine:BAAANQAECgUIDQAAAA==.Terry:BAAANQAECgQIBQAAAA==.',
Th='Thanyros:BAAANQAECgYICwAAAA==.Thanywar:BAAANQAECgcIDgAAAA==.Thebrowner:BAAANQAECgIIAgABNQAECgMIAwABAAAAAA==.Thejuice:BAAANQADCggIDQAAAA==.Thetrashman:BAAANQAECgMIAwAAAA==.Thoian:BAAANQAECgQIBQAAAA==.Thork:BAAANQADCgYIBgAAAA==.Thrindy:BAAANQAECgMIAwAAAA==.Thugnificint:BAAANQAECgcIDQABNQAECgcIEAABAAAAAA==.Thåwn:BAAANQAECgYICAAAAA==.Thèokoles:BAABNQAECoEZAAQMAAgJ1xSYPwA3AgAMAAgJ1xSYPwA3AgAcAAYJKwvmEAA/AQAQAAEJpgtuHAA2AAAAAA==.',
Ti='Tiblock:BAABNQAECoEYAAIYAAgJEAuqEADOAQAYAAgJEAuqEADOAQAAAA==.Tidalsage:BAAANQAECgYICgAAAA==.Tilolas:BAAANQADCgYIBgAAAA==.Timeskip:BAAANQAECgMIAwAAAA==.Timfinnigut:BAAANQAECgUIDAAAAA==.Tinkiewinkie:BAAANQADCggICAAAAA==.Tinx:BAAANQAECgIIAgAAAA==.Tinylego:BAAANQADCggIGwAAAA==.Tinytiran:BAAANQAECgYICgABNQAECgcIDAABAAAAAA==.',
To='Tonktotem:BAEANQADCgEIAQABNQAECgQIBQABAAAAAA==.Toptearcryer:BAAANQAECgYIDwAAAA==.Tortilla:BAAANQAECgYIDAAAAA==.Toryn:BAAANQADCgYICgABNQABCgMIAwABAAAAAA==.',
Tr='Trailwalker:BAAANQAECgQIBgAAAA==.Trashypally:BAAANQAECgEIAQAAAA==.Trecks:BAAANQADCggIEwAAAA==.Treelonmüsk:BAAANQAECgEIAQAAAA==.Treesumm:BAAANQAECgIIAwAAAA==.Trickyrickyy:BAAANQAECgUICgAAAA==.Triptix:BAAANQADCggIEQAAAA==.Truthbringer:BAAANQADCgQIBAAAAA==.Trynitie:BAAANQAECgMIAwAAAA==.',
Tu='Turlane:BAAANQAECgYIDAAAAA==.',
Tw='Twinkslayer:BAAANQADCgYIDgABNQAECgcIDQABAAAAAA==.Twinkugly:BAAANQABCgcIDwAAAA==.',
Ty='Tyberia:BAAANQAECgMIAwAAAA==.Tychó:BAAANQAECgYIBgAAAA==.Tyeret:BAAANQAECgYIDAABNQAECggIBQABAAAAAA==.Tyet:BAAANQAECgYIBAABNQAECggIBQABAAAAAA==.',
['Tø']='Tørvald:BAAANQAECgIIAwAAAA==.',
Un='Unbeliever:BAAANQABCgYICgAAAA==.',
Us='Uslurper:BAABNQAECoEcAAMZAAkJxxcDCgBNAgAZAAkJhhIDCgBNAgASAAcJYRh1PgABAgAAAA==.',
Va='Varenar:BAAANQAECgYIDgAAAA==.',
Ve='Vearn:BAAANQADCgMIAwABNQADCggIEAABAAAAAA==.Vellamo:BAAANQADCgMIBQAAAA==.Vengeful:BAAANQADCggIGgAAAA==.Venuveus:BAAANQAECgQIBQAAAA==.Verdan:BAAANQAECgUICAAAAA==.',
Vi='Virlomi:BAABNQAECoEhAAILAAkJxx+RBAAdAwALAAkJxx+RBAAdAwAAAA==.Viyya:BAAANQADCgYIBgAAAA==.',
Vl='Vlix:BAAANQADCgMIAwAAAA==.',
Vo='Vowz:BAAANQADCgYICgAAAA==.',
Vy='Vynx:BAAANQAECgMIAwAAAA==.Vyrogash:BAAANQADCgMIAwAAAA==.Vythica:BAAANQAECgYIDAAAAA==.',
['Vå']='Vålåk:BAAANQAECgEIAQAAAA==.',
Wa='Wakoguyc:BAAANQAECgQIBwAAAA==.Warcaige:BAAANQAFFAEIAQABNQAFFAUIDAARAN4TAA==.Wargodd:BAAANQAECggIBQAAAA==.',
We='Weierstraß:BAAANQAECgUIDAAAAA==.Welari:BAAANQAECgYIDgAAAA==.Weskerx:BAAANQADCggIEAAAAA==.',
Wh='Whindd:BAAANQAECgEIAQAAAA==.Whurstresort:BAAANQAECgYIDAAAAA==.Whurstrong:BAAANQADCgEIAQABNQAECgYIDAABAAAAAA==.Whurstyx:BAAANQADCgIIAgAAAA==.',
Wi='Wickedsoul:BAAANQADCggICAAAAA==.Widowmaker:BAAANQAECgEIAQAAAA==.Wif:BAAANQAECgMIBAAAAA==.Wingmancole:BAAANQADCgQIBAAAAA==.Withers:BAAANQADCgYIBgABNQAECgcIDAABAAAAAA==.',
Wo='Wondrball:BAAANQAECgUIDAAAAA==.Worgen:BAAANQAECgYICgAAAA==.',
Xa='Xalvelora:BAAANQADCgYICQAAAA==.Xanderia:BAAANQAECgIIAwAAAA==.Xandil:BAAANQADCggICAAAAA==.',
Xe='Xeralath:BAAANQAECgYIDgAAAA==.',
Xv='Xvibe:BAAANQADCggIDQAAAA==.',
Xy='Xyphira:BAAANQADCggIGgAAAA==.',
['Xý']='Xý:BAAANQADCgYIEQAAAA==.',
Ya='Yaboo:BAAANQAECgEIAQAAAA==.Yaen:BAAANQADCgcIDAAAAA==.',
Ye='Yehvenâh:BAAANQAECgQIBQAAAA==.Yeska:BAAANQADCgQIBAAAAA==.',
Yo='Yootle:BAAANQAECgUICQAAAA==.Yourgothgf:BAEANQAECgQIBQAAAA==.Yovanna:BAAANQADCgYIBAABNQAECggIAgABAAAAAA==.',
Yu='Yummyx:BAAANQAECgEIAQAAAA==.',
Za='Zallo:BAAANQAECgQICAAAAA==.Zaloria:BAAANQADCgYIDAAAAA==.Zaqws:BAAANQADCggIDAAAAA==.Zarth:BAAANQADCgIIAgAAAA==.Zathral:BAAANQAECgQIBAAAAA==.Zava:BAAANQAECgQIDAAAAA==.Zaxon:BAAANQADCgQIBAABNQABCgMIAwABAAAAAA==.',
Ze='Zeelos:BAAANQAECgUIBQAAAA==.Zembu:BAAANQADCgQIBAAAAA==.Zephhyr:BAAANQAECgcIDAAAAA==.Zephyr:BAAANQAECgQIBAAAAA==.Zeñor:BAAANQAECgQICQAAAA==.',
Zh='Zhax:BAAANQABCgMIAwAAAA==.',
Zi='Zireael:BAAANQAECgQICAAAAA==.',
Zo='Zornox:BAAANQADCgYICwAAAA==.',
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
