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

local lookup = {'Shaman-Restoration','Unknown-Unknown','Shaman-Elemental','Rogue-Assassination','Rogue-Subtlety','Paladin-Holy','Druid-Guardian','Druid-Feral','DemonHunter-Devourer','Warrior-Protection','Mage-Arcane','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Unholy',}
local provider = {region='US',realm='Aegwynn',name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aarista:BAAANQADCgIIAwAAAA==.',
Ab='Abhorrere:BAAANQABCgMIAwAAAA==.',
Ac='Acedririd:BAAANQAECgIIAgAAAA==.Actuallyy:BAAANQADCgEIAQAAAA==.',
Ad='Ad:BAAANQAECgQIBAAAAA==.Adönis:BAAANQADCgIIAgAAAA==.',
Ae='Aellerr:BAAANQAECgUIBQAAAA==.',
Af='Affyou:BAAANQAECgEIAQAAAA==.',
Ah='Ahzidal:BAAANQAECgYIBwABNQAECgkJGAABAFciAA==.',
Ai='Ailbhe:BAAANQADCgYIBQAAAA==.Airbinwl:BAAANQAECggIDAAAAA==.Aitchbar:BAAANQADCgEIAQAAAA==.',
Ak='Akanaar:BAAANQADCgIIAwAAAA==.Akilleess:BAAANQAECgIIAgAAAA==.',
Al='Alaw:BAAANQAECgEIAQAAAA==.Alexdd:BAAANQADCgEIAQAAAA==.Alexiathorne:BAAANQADCgEIAQABNQAECgUIBgACAAAAAA==.Alextros:BAEANQAECgQIBQAAAA==.Alivana:BAAANQADCgUICgABNQAECgQIBQACAAAAAA==.Almaris:BAAANQAECgcIDwAAAA==.Aloreilina:BAAANQADCgMIAwAAAA==.Alèx:BAAANQAECgcIDwAAAA==.',
Am='Amarielle:BAAANQAECgQIBwAAAA==.Amire:BAAANQADCgYIFQAAAA==.Ammastolamor:BAAANQADCgIIAgAAAA==.',
An='Anahanu:BAAANQAECggIEQAAAA==.Andrin:BAAANQADCgUIBQAAAA==.Angelawitch:BAAANQAECgEIAQABNQAECgYIEAACAAAAAA==.Angienursey:BAAANQAECgYIEAAAAA==.Annamolly:BAAANQAECgEIAQAAAA==.Ansitris:BAAANQADCgQIBAAAAA==.Antibiotix:BAAANQAECgYIDAAAAA==.',
Ap='Apocrithon:BAAANQADCgMIAwAAAA==.Apros:BAAANQAECgQIBQAAAA==.',
Aq='Aqss:BAABNQAECoEcAAIDAAkJUx7SCAAmAwADAAkJUx7SCAAmAwAAAA==.',
Ar='Arakhana:BAAANQADCgIIAgAAAA==.Aralleah:BAAANQAECgEIAgAAAA==.Aratoreii:BAAANQADCgIIAgAAAA==.Archide:BAAANQAECgQIBAAAAA==.Archidus:BAAANQADCgcIBwAAAA==.Arctose:BAAANQAECgcIDAAAAA==.Ardoniak:BAAANQADCgUIBgAAAA==.Argenoth:BAAANQADCgIIAwAAAA==.Arkaeon:BAAANQAECgIIAgAAAA==.Arthar:BAAANQADCgEIAQAAAA==.',
As='Asdsfe:BAAANQAECgEIAQAAAA==.Ashandrei:BAAANQAECgIIAgAAAA==.Ashletil:BAAANQADCgIIAwAAAA==.Astraeadawn:BAAANQADCgMIAwAAAA==.Aszkme:BAAANQADCgUIBwAAAA==.',
At='Atri:BAAANQADCgUIBQABNQAECgEIAgACAAAAAA==.',
Au='Auran:BAAANQAECgEIAQAAAA==.Authority:BAAANQAECgYIEQAAAA==.Autismosteve:BAAANQAECgQIBQAAAA==.',
Av='Avanlythia:BAAANQADCgYIBgABNQAECgQIBQACAAAAAA==.Avlee:BAAANQADCgQIBAAAAA==.',
Aw='Aware:BAABNQAECoEUAAMEAAgJDSFTAwAGAwAEAAgJDSFTAwAGAwAFAAYJhxsaEwDRAQAAAA==.',
Az='Azathox:BAAANQABCgEIAQAAAA==.Azzuhpala:BAABNQAECoEZAAIGAAkJOBFtFAB0AgAGAAkJOBFtFAB0AgAAAA==.',
Ba='Baddracthyr:BAAANQAECgcIEQAAAA==.Balderus:BAAANQAECgQIBAAAAA==.Banjophd:BAAANQAECgEIAQAAAA==.Baracus:BAAANQADCggICAAAAA==.Batareva:BAAANQAECgQICQAAAA==.Batavira:BAAANQADCgMIAwABNQAECgQICQACAAAAAA==.Bayrock:BAAANQABCgIIAgAAAA==.',
Be='Beamnord:BAAANQAECgIIAgAAAA==.Beanie:BAAANQADCggIEQAAAA==.Bearlyere:BAAANQAECgYICAAAAA==.Beastshine:BAAANQADCgYICgAAAA==.Bendemus:BAAANQAECgYIDwAAAA==.Bentléy:BAAANQADCgEIAQAAAA==.Berserkguts:BAAANQAECgQIBgAAAA==.Bersk:BAAANQADCgQIBAAAAA==.',
Bi='Bigker:BAAANQADCgIIAgAAAA==.Bigzaddy:BAAANQADCgYIBgAAAA==.Bitrot:BAAANQAECgIIAgAAAA==.',
Bl='Blindbuns:BAAANQADCgYIDAAAAA==.Blokejr:BAAANQADCggIDwABNQAECgIIAgACAAAAAA==.Blooddagger:BAAANQAECgYICQAAAA==.Bloodeater:BAAANQADCgYIBgAAAA==.Bloodnyte:BAAANQAECgEIAQAAAA==.',
Bo='Bodhmal:BAAANQAECgcIEQABNQAECgcICwACAAAAAA==.Bootyhealz:BAAANQADCgUICAAAAA==.',
Br='Brahe:BAAANQADCgYICgAAAA==.Braliana:BAAANQADCggICAAAAA==.Brandun:BAAANQADCgYIBgAAAA==.Brethe:BAAANQADCgUIBQAAAA==.Brokíìnn:BAAANQAECgcIEgAAAA==.Broncas:BAAANQADCgEIAQAAAA==.Brotherbonk:BAAANQADCggICAAAAA==.Brucebearner:BAAANQAECggICgAAAA==.Bruff:BAAANQAECgUIBQAAAA==.Brufknight:BAAANQAECgEIAQAAAA==.Brufwar:BAAANQADCgcIBwAAAA==.Brókiinn:BAAANQADCggIDAAAAA==.',
Bu='Bukhanee:BAAANQAECgEIAQAAAA==.Burmtron:BAAANQADCggIEwABNQADCggIFwACAAAAAA==.Burmtronn:BAAANQADCggIFwAAAA==.Bustabolt:BAAANQAECgUIBwAAAA==.',
Bw='Bwansamdeez:BAAANQABCgIIAgABNQADCgUIBQACAAAAAA==.',
Ca='Caceynn:BAAANQADCgMIAwAAAA==.Candyditto:BAAANQAECgIIAgABNQAFFAUIBwAGABEVAA==.Caoinlean:BAAANQADCgcIDQAAAA==.Carebearcare:BAABNQAECoEWAAMHAAkJuROHAwBZAgAHAAkJuROHAwBZAgAIAAEJTwAJFgAjAAAAAA==.Cattledecap:BAAANQABCgIIAgAAAA==.',
Ce='Celiaisake:BAAANQAECgIIAgAAAA==.Celorleran:BAAANQADCgMIAwAAAA==.Ceruibas:BAAANQAECgIIAgAAAA==.',
Ch='Chaoscat:BAAANQAECgQIBAAAAA==.Chaossparkie:BAAANQAECgIIAgAAAA==.Charlight:BAAANQADCggIGAAAAA==.Cheddarclaps:BAAANQABCgEIAQAAAA==.Cheeksdemon:BAAANQADCggIEwAAAA==.Cheesefriess:BAAANQAECgEIAQAAAA==.Chetan:BAAANQADCgEIAQAAAA==.Chuckknight:BAAANQADCgYICQAAAA==.Chuttbeeks:BAAANQAECgQIBAAAAA==.',
Ci='Cisnei:BAAANQABCgQICgABNQAECgMIAwACAAAAAA==.',
Co='Coggwalker:BAAANQADCgUIAgAAAA==.Colbyjax:BAAANQADCggICAABNQAECgMIAwACAAAAAA==.Coldiloks:BAAANQAECgIIAgAAAA==.Corgruumn:BAAANQADCgMIAwAAAA==.',
Cr='Crastak:BAAANQAECgQIBAAAAA==.Crazyliquer:BAAANQADCgYIDAAAAA==.Crisy:BAAANQAECgYICgAAAA==.',
Cy='Cyndk:BAEANQADCgcIBwAAAA==.',
Da='Dabbz:BAAANQAECgEIAQAAAA==.Daez:BAAANQADCgYICAABNQAECgYICAACAAAAAA==.Dahampster:BAAANQADCgcICwAAAA==.Dailna:BAAANQAECgIIAwAAAA==.Dalamri:BAAANQADCgcIBwAAAA==.Dalarrorn:BAAANQADCgQIBwAAAA==.Dalitha:BAAANQAECgIIAgAAAA==.Dallart:BAAANQAECggIBgAAAA==.Dalonar:BAAANQADCgYIBgAAAA==.Damrath:BAAANQADCgQIBAAAAA==.Danhunter:BAAANQAFFAIIAgAAAA==.Danoriye:BAAANQADCgQIBAAAAA==.Darazana:BAAANQADCgUIBQAAAA==.Darkclawfox:BAAANQADCgQIBAAAAA==.Darknarsin:BAAANQAECgEIAQAAAA==.Davbarx:BAAANQABCgQIBgAAAA==.Days:BAAANQAECgEIAQABNQAECgYICAACAAAAAA==.Daze:BAAANQAECgYICAAAAA==.Dazuiio:BAAANQAECgIIAgAAAA==.',
De='Deadrice:BAAANQAECgMIAwAAAA==.Declines:BAAANQADCgYICAAAAA==.Delfriet:BAAANQADCgYIBgAAAA==.Delso:BAAANQADCgUIBQAAAA==.Deltasara:BAAANQADCgUIBQAAAA==.Demonarbin:BAAANQAECgcIBwAAAA==.Demonkcorb:BAAANQADCggICAAAAA==.Deysonis:BAAANQAECgEIAgAAAA==.',
Dh='Dhbear:BAAANQAFFAIIAgAAAA==.',
Di='Diligence:BAAANQADCgEIAgAAAA==.Dingberry:BAAANQAECgQICAAAAA==.Dioghaltair:BAAANQADCgUIBQAAAA==.Diphyidae:BAAANQAECgEIAwAAAA==.Diyatea:BAAANQAECgMIAwAAAA==.Dizzle:BAAANQADCgYIBwAAAA==.',
Dm='Dmininstries:BAAANQAECggIBAAAAA==.',
Do='Dodgeypoo:BAEANQADCgcIDAAAAA==.Domit:BAAANQADCgUICQAAAA==.Dommag:BAAANQADCgUIBwAAAA==.Doostfraba:BAAANQADCgEIAQAAAA==.Doots:BAAANQADCggIEAAAAA==.Dopey:BAAANQAECgQICAAAAA==.Dorkplatypus:BAAANQAECgYIDQAAAA==.Doski:BAAANQAECgEIAQABNQAECgYIBwACAAAAAA==.',
Dr='Dracoarbatel:BAAANQADCgUICAAAAA==.Dragindeezz:BAAANQAECgEIAQABNQAECgkJFwAJAFIeAA==.Dragindemons:BAABNQAECoEXAAIJAAkJUh5HBgAoAwAJAAkJUh5HBgAoAwAAAA==.Dragness:BAAANQADCgcIBwAAAA==.Dragonfroot:BAAANQAECgQIBAAAAA==.Drakgo:BAAANQAECgYIBwAAAA==.Dravenuz:BAAANQAECgcIEAAAAA==.Dreadarc:BAAANQADCgUIBQABNQAECgQICAACAAAAAA==.Drespirit:BAAANQAECgEIAQAAAA==.Drewscylla:BAAANQAECgMIAwAAAA==.Dripsyfist:BAAANQAECgcIDQAAAA==.Drixor:BAAANQADCgYICwABNQADCgcICgACAAAAAA==.Drone:BAAANQAECgYIBgABNQAECgkJFQAKAOMmAA==.Druiden:BAAANQAECgYICgAAAA==.Drumok:BAAANQAECgEIAgAAAA==.Dríxx:BAAANQADCgYICwAAAA==.',
Du='Dumbledoof:BAAANQADCgcIFAAAAA==.',
['Dâ']='Dâthomir:BAAANQAECgIIAwAAAA==.',
['Dî']='Dîsfoo:BAAANQABCgQIBAAAAA==.',
Ea='Earlragnarl:BAAANQADCgEIAQAAAA==.',
Eb='Ebonyeti:BAAANQADCgEIAQAAAA==.',
Ec='Echarge:BAAANQAECgQIDAAAAA==.',
Ed='Edandith:BAAANQAECgQIBAAAAA==.Edsilencek:BAAANQAECgEIAQAAAA==.',
Ei='Eizenhorn:BAAANQAECgQIBAAAAA==.',
El='Elasthanan:BAAANQADCgEIAQAAAA==.Eleinna:BAAANQAECgEIAQABNQAECgEIAgACAAAAAA==.Ellodie:BAAANQAECgIIAgAAAA==.Ellíe:BAAANQAECgMIBAABNQAECgQIBgACAAAAAA==.Elmyndreda:BAAANQADCggIEwAAAA==.Elrion:BAAANQAFFAEIAQAAAA==.Eludin:BAAANQADCgcIBwAAAA==.Elwynyssa:BAAANQAECgcIDgAAAA==.',
Em='Emardo:BAAANQADCgQIBAAAAA==.Embiix:BAAANQADCgEIAQAAAA==.Emelia:BAAANQADCgIIAwAAAA==.Emptythreats:BAAANQADCgYIDgAAAA==.',
En='Enelyancalim:BAAANQADCgYICgAAAA==.',
Er='Eraliela:BAAANQADCgEIAQAAAA==.Erudite:BAAANQAECgUIDgAAAA==.',
Et='Eteru:BAAANQADCggIEwAAAA==.',
Eu='Euna:BAAANQADCggIFQAAAA==.',
Ey='Eyko:BAAANQAECgYICQAAAA==.',
['Eä']='Eädgyth:BAAANQAECgYIEAAAAA==.',
Fa='Farbauti:BAAANQAECgUIDQAAAA==.Fascinus:BAAANQABCgIIAgAAAA==.',
Fe='Fedrk:BAAANQADCgQIBwABNQADCggIEwACAAAAAA==.Fedu:BAAANQAECgQIBQAAAA==.Feldesk:BAAANQAECgQIDQAAAA==.Fellich:BAAANQAECgQIBQAAAA==.Felspike:BAAANQADCgMIAwAAAA==.Fenrii:BAAANQADCgIIAgAAAA==.Ferp:BAAANQAECgEIAQAAAA==.Festered:BAAANQAECgUIBgAAAA==.',
Fi='Fizzcopper:BAAANQAECgcIEAAAAA==.',
Fk='Fkwalmart:BAAANQADCggIDgABNQAFFAEIAQACAAAAAA==.',
Fl='Flavortheman:BAAANQABCgMIAgAAAA==.Flit:BAAANQAECgIIAgAAAA==.Flitmg:BAAANQADCgQIBwAAAA==.Flowersnight:BAAANQAECgIIAwAAAA==.Flowerx:BAAANQADCggICAABNQAECgEIAQACAAAAAA==.Flowerxx:BAAANQAECgEIAQAAAA==.',
Fo='Fontanie:BAAANQADCgIIAgAAAA==.Fontaniebear:BAAANQABCgIIAgABNQADCgIIAgACAAAAAA==.Formroll:BAAANQADCgcIEgAAAA==.Foxyashammy:BAAANQADCgMIAwAAAA==.',
Fr='Freakdawg:BAAANQAECgMIBAAAAA==.Freetime:BAAANQAECgEIAQAAAA==.Freyabloom:BAAANQADCggIFAAAAA==.Froozxcdk:BAAANQAECgEIAQAAAA==.Froozxchunt:BAAANQADCgcIBwABNQAECgEIAQACAAAAAA==.Froozxcwarr:BAAANQAECgYIBgAAAA==.Fruitloops:BAAANQADCgIIAgAAAA==.',
Ga='Gabbiani:BAAANQADCggIDwAAAA==.Galondrake:BAAANQADCgIIAgABNQAECgEIAQACAAAAAA==.Galonzenith:BAAANQAECgEIAQAAAA==.Garamor:BAAANQADCgUIBQAAAA==.Gargaki:BAAANQADCgUIAwAAAA==.Garm:BAAANQADCgEIAQAAAA==.Garyboldman:BAAANQADCgIIAwAAAA==.',
Ge='Geldrath:BAAANQADCgEIAQAAAA==.Genoddhunter:BAAANQAECgYIBwAAAA==.Gerfbert:BAAANQAECgQIBwAAAA==.Geø:BAAANQADCgYIDwAAAA==.',
Gi='Giantess:BAAANQAECgYICAABNQAECgcIBwACAAAAAA==.Gibbygibby:BAAANQAECgIIAgABNQAECgQIBAACAAAAAA==.Giggityz:BAAANQADCgcICgAAAA==.Gigidygoo:BAAANQADCgMIAwAAAA==.Gilreth:BAAANQAECgYICgAAAA==.Gilzaur:BAAANQAECgQIBQAAAA==.Gimrr:BAAANQAECgEIAQAAAA==.Gimurr:BAAANQADCgMIAwABNQAECgEIAQACAAAAAA==.Gixrdano:BAAANQADCgQIBAAAAA==.',
Gj='Gjeoff:BAAANQADCggIDgAAAA==.',
Gl='Glasshealing:BAAANQAECgMIBAAAAA==.',
Gn='Gnomepunzel:BAAANQADCgcIEgAAAA==.',
Go='Goodys:BAAANQADCgEIAQAAAA==.Goopstick:BAAANQAECgQIBAAAAA==.Gorewood:BAAANQADCgUICAAAAA==.Gorillamage:BAAANQAECgIIAgAAAA==.Gortu:BAAANQADCgYIBgAAAA==.Gotag:BAAANQAECgQIBgAAAA==.',
Gr='Gravefang:BAAANQAECggICAAAAA==.Greatdeku:BAAANQADCgMIBAAAAA==.Grimmby:BAAANQAECgIIAgAAAA==.Grumpyangie:BAAANQADCgIIBAABNQAECgYIEAACAAAAAA==.Grung:BAAANQAECgUICQAAAA==.',
Gu='Guldum:BAAANQADCgMIAwAAAA==.Gumbynutte:BAAANQAECgIIAgAAAA==.',
Gw='Gwenita:BAAANQAECgMIBAAAAA==.Gwiontotems:BAEANQADCgYIDAABNQAECgIIAgACAAAAAA==.',
Gy='Gyarados:BAAANQADCgUIBwAAAA==.Gyokuro:BAAANQAECgQIBAABNQADCgUIBQACAAAAAA==.',
['Gí']='Gízy:BAAANQAECgQICwAAAA==.',
Ha='Habdearn:BAAANQADCgcIDgAAAA==.Hailey:BAEANQAFFAEIAQAAAA==.Hakunapotato:BAAANQADCgYICAAAAA==.Halfe:BAAANQADCgQIBAAAAA==.Hamchowder:BAAANQADCgIIAgAAAA==.Hameey:BAAANQAECgIIAgAAAA==.Haranitony:BAAANQAECgQIBQAAAA==.Havreth:BAAANQADCggICQAAAA==.Hazzardd:BAAANQAECgMIBAAAAA==.',
He='Heallium:BAAANQADCggIAgAAAA==.Heelie:BAAANQADCgYICgAAAA==.Heleris:BAAANQADCggIDQAAAA==.Helgalila:BAAANQAECgQIBQAAAA==.Hellslord:BAAANQADCggICAAAAA==.Helmia:BAAANQADCggICQAAAA==.Hemoglobe:BAAANQADCgEIAQAAAA==.Heughjanus:BAAANQAECgQIBAAAAA==.Hexonna:BAAANQADCgEIAQAAAA==.Hexshade:BAAANQADCgEIAQAAAA==.',
Hi='Hidere:BAAANQADCgEIAQAAAA==.',
Hl='Hlyparkbench:BAAANQAECgcIEQABNQABCgIIAgACAAAAAA==.',
Ho='Hodge:BAAANQADCggIDgABNQAECgIIAgACAAAAAA==.Hodgey:BAAANQAECgIIAgAAAA==.Holycrapola:BAAANQADCgYIBgABNQADCgYIBwACAAAAAA==.Holyhero:BAEANQADCgQIBAABNQADCgcIDAACAAAAAA==.Holykcorb:BAAANQAECgMIAwAAAA==.Holymat:BAAANQADCgEIAQAAAA==.Holytweak:BAAANQAECgQIBAAAAA==.Hoovion:BAAANQADCgMIAwAAAA==.',
Hu='Hudimm:BAAANQADCgUIDgAAAA==.Huggsnkisses:BAAANQADCggIEAAAAA==.Hunglownewb:BAAANQADCgQIBAAAAA==.Hunho:BAAANQAECggIBwAAAA==.Hunterjohn:BAAANQADCgEIAQAAAA==.',
Hy='Hynarillan:BAAANQADCgIIAQAAAA==.Hyorin:BAAANQADCggIFAAAAA==.',
Ic='Icken:BAAANQADCgcIDAAAAA==.',
Id='Idefkanymore:BAAANQADCgcIEwAAAA==.Idomage:BAAANQADCgUIBQAAAA==.',
Il='Iludron:BAAANQADCgYICQAAAA==.',
Im='Immaculates:BAAANQABCgIIAgAAAA==.Immunized:BAEANQADCgQIBgABNQADCgUIBQACAAAAAA==.Imoquai:BAAANQADCgYIBgAAAA==.Impedance:BAAANQADCggICwAAAA==.Imyaboi:BAAANQADCgYIBgAAAA==.Imzáiah:BAAANQAECgEIAQAAAA==.',
In='Inforgame:BAAANQADCgUIBQAAAA==.Inkhunter:BAAANQADCgMIAwAAAA==.Inkmoon:BAAANQAECgMIAwAAAA==.Inningg:BAAANQAECgQIBAAAAA==.Insânity:BAAANQAECgEIAQAAAA==.Invictus:BAAANQAECgIIAgAAAA==.Invoided:BAAANQAECggICAAAAA==.',
Io='Ioweyouheals:BAAANQADCgcICwAAAA==.',
Ir='Ironaimorc:BAAANQADCgcIBwAAAA==.',
Is='Ishara:BAAANQADCgcIBwAAAA==.Isharian:BAAANQAECgQICAAAAA==.Islandponder:BAAANQADCgMIBQABNQAECgQIDQACAAAAAA==.',
It='Ithrowscars:BAAANQAECgQIBQAAAA==.',
Iv='Ivera:BAAANQAECgEIAQAAAA==.',
Ja='Jaliardys:BAAANQAECgUIBwAAAA==.Jareth:BAAANQADCgYICgAAAA==.Jax:BAAANQADCgcIDQAAAA==.Jaxius:BAAANQAECgMIBgAAAA==.Jayia:BAABNQAECoEgAAILAAkJ/SPhBwCDAwALAAkJ/SPhBwCDAwAAAA==.Jayie:BAAANQAECgcICwABNQAECgkJIAALAP0jAA==.',
Je='Jedazar:BAAANQADCgUIBQAAAA==.Jefeli:BAAANQABCgEIAQAAAA==.',
Ji='Jijidruid:BAAANQADCgQIBAAAAA==.Jimf:BAAANQADCgUIBQAAAA==.Jinzi:BAAANQAECgUIBgAAAA==.',
Jj='Jjbang:BAAANQAECgEIAQAAAA==.',
Jm='Jmel:BAAANQADCgIIAgAAAA==.',
Jo='Jojomars:BAAANQADCgcICgAAAA==.Joosseri:BAAANQADCgUICgAAAA==.Jorkho:BAAANQADCgQIBAAAAA==.Josespala:BAAANQAECgEIAQAAAA==.Journeydd:BAAANQADCgYIEAAAAA==.',
Ka='Kaelish:BAAANQADCgIIAwAAAA==.Kafeene:BAAANQABCgQIBAAAAA==.Kagargo:BAAANQAECgIIAgAAAA==.Kahlel:BAAANQADCgEIAQAAAA==.Kalnamos:BAAANQAECgYIDQAAAA==.Kaorinite:BAAANQAECgUICAAAAA==.Karismâ:BAAANQAECgIIAgAAAA==.Kataela:BAAANQADCggICAAAAA==.Katanovich:BAAANQAECgEIAQAAAA==.Katixx:BAAANQADCgYIBgAAAA==.Katparkbench:BAAANQADCgYICwABNQABCgIIAgACAAAAAA==.Katyperryfan:BAAANQADCgUIBQAAAA==.Kauketkenna:BAAANQADCgEIAQAAAA==.Kaynfel:BAAANQADCgUIBQAAAA==.',
Ke='Kegan:BAAANQADCggIEwAAAA==.Kela:BAAANQAFFAIIAgAAAA==.Kelezekan:BAAANQAECgIIAgAAAA==.Kelilina:BAAANQAECgIIAgAAAA==.Keyelements:BAAANQADCgcIBwAAAA==.',
Kh='Khafie:BAAANQAECgcIEgAAAA==.',
Ki='Killtech:BAAANQAECgEIAgAAAA==.Kimanip:BAAANQAECgEIAQAAAA==.Kimdeath:BAAANQAECgYIBgAAAA==.Kiraredclaw:BAAANQAECgQIBAAAAA==.Kitsukko:BAAANQAECgIIAgAAAA==.',
Kj='Kjarten:BAAANQADCgQIBQABNQAECgYICAACAAAAAA==.',
Ko='Kolu:BAAANQAECgUIBgAAAA==.Korgara:BAAANQADCgYIBgAAAA==.Kozma:BAAANQADCgIIAgAAAA==.',
Kr='Kraedeyn:BAAANQAECgYICgABNQADCgYIBgACAAAAAA==.Kraethas:BAAANQADCgEIAQAAAA==.Kraseva:BAAANQAECgEIAQAAAA==.Krell:BAAANQADCgcIEgAAAA==.Krestfallen:BAAANQADCgUIBQAAAA==.Kriek:BAAANQAECgIIAgAAAA==.Krissiis:BAAANQADCgMIBAABNQADCgYICwACAAAAAA==.Krixor:BAAANQADCgcICgAAAA==.Kråft:BAAANQAECgEIAQABNQAECgIIAgACAAAAAA==.',
Ku='Kurolola:BAAANQABCgMIAwAAAA==.Kurome:BAAANQAECgQICAAAAA==.',
Ky='Kynam:BAAANQAECgEIAQAAAA==.',
La='Landazanso:BAAANQADCgcICgAAAA==.Latina:BAAANQAECgUIBAAAAA==.Laynna:BAAANQAECgQIBQAAAA==.',
Le='Leguiz:BAAANQAECgYICgAAAA==.Lemondreams:BAABNQAECoEVAAMMAAkJcB6MEQCeAgAMAAgJlSGMEQCeAgANAAcJyRkIEQA8AgAAAA==.Lemontree:BAAANQADCggICgAAAA==.Leorihk:BAAANQADCgIIAwAAAA==.Lerius:BAAANQADCgYIDAAAAA==.Leroyak:BAAANQADCgIIAgAAAA==.',
Li='Lightshadows:BAAANQAECgQIBAAAAA==.Lilpikky:BAAANQAECgQIBAAAAA==.Lionfish:BAAANQADCgcICwAAAA==.Lirael:BAAANQADCgYICAAAAA==.Lizzborden:BAAANQADCgIIAwAAAA==.Lièrén:BAAANQAECgYICgAAAA==.',
Lo='Lokjikju:BAAANQABCgQIBAAAAA==.Lonemadness:BAAANQADCgQIBQAAAA==.Longthorne:BAAANQADCgYIBgABNQAECgkJGAABAFciAA==.Lookitzmee:BAAANQADCggIDgAAAA==.Lostagro:BAAANQADCgIIAgAAAA==.',
Lu='Lucixn:BAAANQADCggIEQAAAA==.Lughbelenus:BAAANQADCggIFAAAAA==.Luminitz:BAAANQADCggICAAAAA==.Lummytumkins:BAAANQAECgIIAgAAAA==.Luxdk:BAAANQADCgYIBgAAAA==.',
Ly='Lyoko:BAAANQADCgYICAAAAA==.Lyssandris:BAAANQAECgcICwAAAA==.Lythany:BAAANQADCgcIDQAAAA==.',
['Lö']='Löckrocks:BAAANQAECgEIAQAAAA==.',
['Lø']='Løkira:BAAANQADCgYIBwAAAA==.',
Ma='Mackncheese:BAAANQAECgEIAQAAAA==.Madigan:BAAANQADCgMIAwAAAA==.Maghhard:BAAANQAECgMIBgAAAA==.Magyst:BAAANQAECgQIBAAAAA==.Maicyclone:BAAANQADCgYIBgAAAA==.Malishine:BAAANQADCgMIAwAAAA==.Manabender:BAAANQADCgQIBwAAAA==.Mannersback:BAAANQAECggIDgAAAA==.Mannethal:BAAANQADCgYIBgAAAA==.Marrylou:BAAANQADCgIIAgAAAA==.Martelstorm:BAAANQADCggIFAAAAA==.Materus:BAAANQAECgQICgAAAA==.Matxhias:BAAANQADCggICAAAAA==.Mazzakeene:BAAANQADCgIIAgAAAA==.',
Mc='Mcthor:BAAANQAECgIIAgAAAA==.',
Me='Megasham:BAAANQAECgcIEQAAAA==.Meion:BAEANQADCgYIDAAAAA==.Melcam:BAAANQADCgYICAAAAA==.Metalspike:BAAANQADCgUIAwAAAA==.',
Mg='Mgdk:BAAANQAECgMIAQAAAA==.',
Mh='Mhorea:BAAANQAECgQIBQAAAA==.',
Mi='Miniash:BAAANQAECgIIAgAAAA==.Minox:BAAANQAECgEIAQAAAA==.Mismage:BAAANQAECgQIAwAAAA==.Mistlore:BAAANQAECgIIAgAAAA==.Mistyfist:BAAANQADCgYIBwAAAA==.Miyamotosaki:BAAANQADCgEIAQAAAA==.Mizuree:BAAANQADCgMIAwAAAA==.',
Mo='Monjax:BAAANQADCgYICQABNQAECgMIBwACAAAAAA==.Monkyblooms:BAAANQAECgYICAAAAA==.Monmook:BAAANQAECgYICwAAAA==.Moonfir:BAAANQADCgQIBgAAAA==.Moosah:BAAANQAFFAEIAQABNQAECgEIAQACAAAAAA==.Moosetafa:BAAANQAECgIIAwAAAA==.Moosubi:BAAANQAECgEIAQAAAA==.Morgoonis:BAAANQAECgUIBQAAAA==.Morphyus:BAAANQAECgcIDAAAAA==.Mostlynotgay:BAAANQAECgEIAQAAAA==.Moxxz:BAAANQADCgQICQAAAA==.',
Mu='Muggernaut:BAAANQADCgYIBgABNQAECgEIAQACAAAAAA==.Mundergy:BAAANQADCggICAABNQAECgQIBAACAAAAAA==.Murazor:BAAANQAECgQICAAAAA==.Mutilager:BAAANQAECgIIAgAAAA==.',
My='Myeaasee:BAAANQAECgQIBgAAAA==.Mykickthirty:BAAANQAECgYIAQAAAA==.',
['Mà']='Màsnart:BAAANQADCgQIBQAAAA==.',
['Má']='Mágaidh:BAAANQADCgEIAQAAAA==.',
['Mî']='Mîko:BAAANQAECggIDwAAAA==.',
Na='Naeyty:BAAANQAECgEIAQAAAA==.Nahid:BAAANQADCgYIBgAAAA==.Nahtikalelle:BAAANQAECgIIAgABNQAECgQICQACAAAAAA==.Najmuldeen:BAAANQADCgMIAwAAAA==.Namewee:BAAANQABCgMIAwAAAA==.Narcana:BAAANQAECgQIBAABNQAECgMIAwACAAAAAA==.Narusa:BAAANQAECgMIBAAAAA==.Nastyysham:BAAANQADCggIEwAAAA==.Naturescienc:BAAANQADCgcIBwAAAA==.',
Ne='Neblissa:BAAANQADCgYICQAAAA==.Negu:BAAANQAECgQIBQAAAA==.Nejedi:BAAANQADCgEIAQABNQADCgYICQACAAAAAA==.Neodknight:BAAANQAECgUIBgAAAA==.Neohuan:BAAANQAECgEIAQAAAA==.Neomourne:BAAANQADCgcIDQABNQAECgEIAQACAAAAAA==.Neoplasm:BAAANQADCgYIBgABNQAECgUIBgACAAAAAA==.Neoshield:BAAANQADCgcIBwABNQAECgUIBgACAAAAAA==.Nephran:BAAANQADCgEIAQAAAA==.Nerdibird:BAAANQADCgcIEQAAAA==.Nerek:BAAANQAECgQIBAAAAA==.Nesthraxa:BAAANQAECgIIAgAAAA==.',
Ni='Nialen:BAAANQABCgQIBAAAAA==.Nialiaa:BAAANQADCgYICwAAAA==.Nightvader:BAAANQAECggIBwABNQAECggICgACAAAAAA==.Nikomach:BAAANQADCgUICAAAAA==.Nirwë:BAAANQADCgcIDwAAAA==.Niviene:BAEANQADCggIEwABNQAECgIIAgACAAAAAA==.',
No='Nokolutrearn:BAAANQADCgQIBAAAAA==.Noodlebender:BAAANQAECgUIBQAAAA==.Noopsnoop:BAAANQAECgQICAAAAA==.Noopy:BAAANQAECgMIBAAAAA==.Noriannera:BAAANQAECgEIAQAAAA==.Nowhackingu:BAAANQADCgYIBgAAAA==.',
Nu='Nuggets:BAAANQADCgQIBAAAAA==.Nulight:BAAANQAECgQIBwAAAA==.Nutrients:BAAANQADCgIIAgAAAA==.',
Ny='Nyvrix:BAAANQADCgQICgAAAA==.Nyxnala:BAAANQADCgIIAwAAAA==.',
Oa='Oakenak:BAAANQADCgYIDQAAAA==.',
Oc='Octane:BAAANQADCgYIDAABNQAECgIIAgACAAAAAA==.',
Od='Odiwen:BAAANQADCgUIBQAAAA==.Odyssa:BAAANQADCggIGQABNQAECggIFQANAHQeAA==.',
Oh='Ohdan:BAAANQADCgUIBQABNQAECgMIBAACAAAAAA==.',
Ol='Olfdu:BAAANQADCgUIBQAAAA==.',
Oo='Oolong:BAAANQADCgUIBQAAAA==.',
Or='Orindal:BAAANQAECgEIAQAAAA==.',
Ou='Ouluo:BAAANQADCgcIBwAAAA==.',
Pa='Palared:BAAANQAECgYIDQAAAA==.Palladiyne:BAAANQADCgYIEAAAAA==.Palliearth:BAAANQADCgcIDgAAAA==.Pandö:BAAANQADCgYICgABNQAECgQIBAACAAAAAA==.Papacooldwn:BAAANQADCgUIBQAAAA==.Parict:BAAANQAECgYIAgAAAA==.Pascaal:BAAANQADCgUIBwAAAA==.',
Pe='Pecansandies:BAAANQADCgcIBwAAAA==.Pennÿ:BAAANQADCgcIEQAAAA==.Penthe:BAAANQADCgYIDgAAAA==.Penumbruh:BAAANQAECgYICgAAAA==.Peruvianvil:BAAANQABCgEIAQAAAA==.',
Pf='Pfunk:BAAANQAECgEIAQABNQAECgYIDQACAAAAAA==.',
Ph='Pheebegeobe:BAAANQAECgMIBAAAAA==.Phyzal:BAAANQADCgYICQAAAA==.Phåze:BAAANQADCgIIAgAAAA==.',
Pi='Piddlebom:BAAANQADCggIGAAAAA==.Pirani:BAAANQADCgQIBwAAAA==.Pitts:BAAANQADCgcIDwAAAA==.',
Pl='Platanito:BAAANQADCgYIBgAAAA==.',
Po='Ponyytail:BAAANQADCggIJAAAAA==.Poodis:BAAANQAECgIIAgABNQADCgUIBQACAAAAAA==.Poshanka:BAAANQADCggIEgAAAA==.Poulsao:BAAANQADCgcIEAAAAA==.Powgun:BAAANQADCgQIBgAAAA==.',
Pr='Promyvïon:BAAANQADCgYIDAABNQAECgMIAwACAAAAAA==.',
Pu='Pulpgorillaz:BAAANQADCgYIBwAAAA==.Punchtruly:BAAANQAECgIIAgAAAA==.',
Qd='Qdb:BAAANQADCggICwAAAA==.',
Qi='Qiaosheng:BAAANQADCgYICAAAAA==.',
Ra='Rabbitunter:BAAANQADCgQIBQAAAA==.Rachejagerin:BAAANQADCgQIBAABNQAECgQICQACAAAAAA==.Rackharrow:BAAANQADCgQIBAAAAA==.Raedammil:BAAANQAECgQIBAAAAA==.Raellé:BAAANQAECgIIAgAAAA==.Raiddaddy:BAAANQADCgUIDAABNQADCgcIEwACAAAAAA==.Ramlethal:BAAANQADCgEIAQAAAA==.Rapháèl:BAAANQAECgMIBwAAAA==.Rapticon:BAAANQADCgIIAgAAAA==.Rashelyn:BAAANQAECgUICQAAAA==.Rathgart:BAAANQAECggIBgAAAA==.Ravnsong:BAAANQADCggIEQAAAA==.Ravun:BAAANQABCgIIAgAAAA==.Raylea:BAAANQADCggIFAAAAA==.Raynevanity:BAAANQADCgIIAgAAAA==.Razenothen:BAAANQADCgMIAwAAAA==.',
Re='Reco:BAAANQAECgQIBwAAAA==.Rednazm:BAAANQAECgQIBAAAAA==.Redsdh:BAAANQADCgEIAQABNQAECgYIDQACAAAAAA==.Redsmasher:BAAANQADCgEIAQAAAA==.Reindridaen:BAAANQADCgYIBgABNQAECgcICwACAAAAAA==.Rem:BAAANQADCgUIBQAAAA==.Remimousy:BAAANQADCgQIBgAAAA==.Revdrax:BAAANQAECgQIBAAAAA==.Revosham:BAAANQAECgEIAgAAAA==.Rexxywaffles:BAAANQADCgcIBwAAAA==.',
Rh='Rhaanall:BAAANQADCggIDgAAAA==.Rhaizu:BAAANQADCgYICAAAAA==.',
Ri='Riedreni:BAAANQAECgEIAQAAAA==.',
Ro='Rockytotems:BAAANQAECgIIAgAAAA==.Rogued:BAAANQAFFAEIAQAAAA==.Roldius:BAAANQADCgYIDAAAAA==.Rorodruida:BAAANQAECgQIBgAAAA==.Rorrk:BAAANQADCgYIBgAAAA==.Rosedemon:BAAANQABCgIIAgAAAA==.Rothanos:BAAANQAECgIIAgAAAA==.Rouland:BAAANQAECgQIBQAAAA==.Rowdawg:BAAANQADCgYIBgAAAA==.',
Ry='Rykthar:BAAANQADCgQIBAAAAA==.Ryvennah:BAAANQADCgYIBgAAAA==.',
['Rê']='Rêhm:BAAANQADCggIDQAAAA==.',
Sa='Sabelyn:BAAANQADCgYICAAAAA==.Saioxenth:BAAANQAECgUIBwAAAA==.Sakmage:BAAANQAECgQICQAAAA==.Salchypapa:BAAANQAECgIIAQAAAA==.Salsbm:BAAANQADCggICAAAAA==.Samais:BAAANQADCgYIBgAAAA==.Samalia:BAAANQAECgYIDQABNQAFFAMIAwACAAAAAA==.Samon:BAAANQADCggIDAAAAA==.Sanches:BAAANQAECgEIAQABNQABCgIIAgACAAAAAA==.Sandycheekz:BAAANQADCgIIAgAAAA==.Sanguineclaw:BAAANQADCgYIEAAAAA==.Sanindon:BAAANQADCgMIAwAAAA==.Saranii:BAEANQADCggIEgAAAA==.Sariì:BAAANQADCgYIBwAAAA==.Sathlinda:BAAANQADCgIIAgAAAA==.Sauloth:BAAANQADCgMIAwAAAA==.',
Sc='Scaled:BAAANQADCgEIAQAAAA==.Scarletpain:BAAANQADCgEIAQABNQAECgMIAwACAAAAAA==.Scarletpaws:BAAANQADCgUIBQABNQAECgMIAwACAAAAAA==.Scarlettanuk:BAAANQAECgMIAwAAAA==.Scarlitjoham:BAAANQADCgcIAwABNQAECgUICQACAAAAAA==.Scragglum:BAAANQADCgUIBwAAAA==.Scromo:BAAANQADCggIGQAAAA==.Scv:BAABNQAECoEVAAIKAAkJ4yYHAAAaBAAKAAkJ4yYHAAAaBAAAAA==.',
Se='Senjougahara:BAAANQADCgUICgAAAA==.Serejh:BAAANQAECgMIAwAAAA==.Serejhs:BAAANQADCgUIBQAAAA==.',
Sh='Shadowbrnger:BAAANQAECgIIBAAAAA==.Shadowsnipes:BAAANQAECgEIAgABNQAECggICAACAAAAAA==.Shadowsongg:BAAANQAECggICAAAAA==.Shaggyd:BAAANQABCgIIAwAAAA==.Shammygaga:BAAANQADCgUIBQABNQAECgEIAQACAAAAAA==.Shamspam:BAAANQAECgMIAwAAAA==.Shanatova:BAAANQADCgUICAAAAA==.Sharinknight:BAAANQAECgIIAwAAAA==.Shauriand:BAAANQADCgQIBAAAAA==.Shawman:BAAANQAECgEIAgABNQABCgIIAgACAAAAAA==.Shehealfu:BAAANQADCggIDgAAAA==.Shigli:BAAANQADCgUIBQABNQAECgYICwACAAAAAA==.Shishras:BAAANQAECggIEQAAAA==.Shnid:BAAANQADCgUIBgAAAA==.',
Si='Silentbozo:BAAANQADCgMIAwAAAA==.Sillydruid:BAAANQADCgYICAAAAA==.Sillyrat:BAAANQAECgQIBwAAAA==.Sincados:BAAANQABCgQIBAAAAA==.Sionfaust:BAAANQADCgYICgAAAA==.Sipper:BAAANQAECgQICAAAAA==.',
Sk='Skandelóus:BAAANQAECgMIAwAAAA==.',
Sl='Sleepymango:BAAANQADCgcIBwAAAA==.Slicky:BAAANQADCgIIAgAAAA==.',
Sm='Smashingface:BAAANQAECgEIAQAAAA==.',
So='Sodypop:BAAANQADCggICAABNQAECgQIBAACAAAAAA==.Sokra:BAAANQADCgYICAAAAA==.Soldmyeggs:BAAANQADCggIFwAAAA==.Somonia:BAAANQAECgEIAQABNQAFFAMIAwACAAAAAA==.Sordamac:BAAANQAECgcIBAAAAA==.',
Sp='Spicymustard:BAAANQABCgIIAgAAAA==.Spidda:BAAANQAECgEIAgAAAA==.',
St='Stasismom:BAAANQAECgUICQAAAA==.Stealthspike:BAAANQADCgcIBQAAAA==.Stellalemon:BAAANQADCgcIBAAAAA==.Stevvee:BAAANQADCggICAAAAA==.Stompalittle:BAAANQADCggIEAABNQAECggIFAAEAA0hAA==.Stonesboyw:BAAANQAECgMIAwAAAA==.Stormtox:BAAANQAECgEIAQAAAA==.Stormydniels:BAABNQAECoEYAAIDAAkJHiQGAgC5AwADAAkJHiQGAgC5AwAAAA==.Strahz:BAAANQAECgUICQAAAA==.Stunurazz:BAAANQAECgMIBAAAAA==.Sturtur:BAAANQADCgYICQAAAA==.Stârbow:BAAANQADCgMIAwAAAA==.',
Su='Suddenstorm:BAAANQAECgYIDQAAAA==.Sudormrf:BAAANQADCggICgABNQAECgQIBQACAAAAAA==.Sullywaffles:BAAANQADCggIFAAAAA==.Sunryze:BAAANQADCgcIDQAAAA==.Sunspotted:BAAANQADCgIIAgAAAA==.Suralias:BAAANQAECggIEAAAAA==.Surashaman:BAAANQAECggIBwABNQAECggIEAACAAAAAA==.',
Sw='Swankkie:BAAANQAECgQIBAAAAA==.Sweetdev:BAAANQADCgMIAwAAAA==.',
Sy='Syraen:BAAANQADCggIEgAAAA==.',
Sz='Szylph:BAAANQADCgYIDAAAAA==.',
['Sä']='Säel:BAAANQADCggIEQAAAA==.',
['Sç']='Sçàr:BAAANQADCgUIBQAAAA==.',
Ta='Taebaek:BAAANQADCgUIBQAAAA==.Talantheron:BAAANQAECgcICQABNQAECggIEQACAAAAAA==.Talhearn:BAAANQAECgEIAQAAAA==.Taminek:BAAANQAECgQIBAABNQAECggIEQACAAAAAA==.Tanarcarissa:BAAANQADCggIEgAAAA==.Tankboy:BAAANQAECgQIBQAAAA==.Tankiemctank:BAEANQADCgYICQAAAA==.Taqui:BAAANQADCggICAAAAA==.Tathea:BAAANQAECgQIBAAAAA==.Tatsuya:BAAANQAECgEIAQAAAA==.Tayded:BAAANQADCgEIAQAAAA==.Tayzar:BAAANQADCgEIAQAAAA==.',
Te='Tehrah:BAAANQABCgYIEAAAAA==.Telisaria:BAAANQADCgcIBwAAAA==.Telocurdle:BAAANQAECgEIAQAAAA==.Temnotal:BAAANQADCgcICwAAAA==.Tendag:BAAANQADCggICwABNQAECggIEQACAAAAAA==.Teorem:BAAANQAECgMIAwAAAA==.Tevulamezruj:BAAANQADCgUIBQAAAA==.',
Th='Thalyon:BAAANQADCgIIAgAAAA==.Thanaphos:BAAANQADCgcIFAAAAA==.Thatguyoquai:BAAANQADCgMIAwAAAA==.Thconsequenc:BAAANQADCgYIBgAAAA==.Theadore:BAAANQADCgEIAQAAAA==.Thecbt:BAAANQADCgQIBAAAAA==.Thellara:BAAANQADCgYIBgAAAA==.Thelmor:BAAANQADCgEIAQAAAA==.Theprincer:BAAANQADCggIGAAAAA==.Therrai:BAAANQADCgYIEgAAAA==.Thirtyfloor:BAAANQADCgYIBgAAAA==.Thoromyr:BAAANQAECgMIAwAAAA==.Thuato:BAAANQADCgYICgAAAA==.Thundercats:BAAANQADCgcIEQAAAA==.Thúndrstruck:BAAANQAECgUIBgABNQAECgkJGAABAFciAA==.',
Ti='Tiffërny:BAAANQADCgIIAgAAAA==.Tivaan:BAAANQAECgEIAgAAAA==.Tizmprince:BAAANQADCgEIAQAAAA==.',
To='Torq:BAABNQAECoEYAAIBAAkJVyIyAwBrAwABAAkJVyIyAwBrAwAAAA==.Totemful:BAAANQADCggICAABNQAECgkJGQAJAGAhAA==.',
Tr='Traewynn:BAAANQADCggIDwAAAA==.Transkitty:BAAANQADCgYIBgAAAA==.Trexy:BAAANQADCgcICwAAAA==.Triredgy:BAAANQAECgcIDAAAAA==.',
Ts='Tsilhqot:BAAANQADCgMIAwAAAA==.',
Tt='Tthatguyy:BAAANQADCgEIAQAAAA==.',
Tu='Tummyblaster:BAAANQADCgEIAQABNQADCggIEwACAAAAAA==.Tummysnake:BAAANQADCgQIBgAAAA==.Turalya:BAAANQAECgEIAQAAAA==.Tuychm:BAAANQAECgEIAQAAAA==.',
Tw='Twareded:BAAANQADCgIIAgAAAA==.Twohandsome:BAAANQAFFAMIAwAAAA==.Twøføx:BAAANQAECgQIBQAAAA==.',
Ty='Tyinaa:BAAANQAECgEIAQAAAA==.Tylenoldk:BAAANQADCgMIAwABNQAECgIIAwACAAAAAA==.Typherin:BAAANQAECgUIBQAAAA==.Tyrallas:BAAANQADCggIDAAAAA==.Tyrven:BAAANQADCgYIBgAAAA==.',
Ub='Ubba:BAAANQAECgYICAAAAA==.',
Ul='Ulannya:BAAANQAECgEIAQAAAA==.Ulddon:BAAANQADCgYIBgAAAA==.Ullria:BAAANQADCgYIBgABNQADCgYIBwACAAAAAA==.',
Un='Undercovrmoo:BAAANQAECgQIBAAAAA==.',
Ur='Urdragon:BAAANQAECgQIBQAAAA==.Urving:BAAANQADCgcIDQAAAA==.',
Uw='Uwugnar:BAAANQADCgYIBgABNQAECgIIAwACAAAAAA==.',
Va='Vaeltheris:BAAANQADCgYICQAAAA==.Vantelantien:BAAANQABCgQIBgAAAA==.Varjaz:BAAANQADCggICAABNQAECgYIDgACAAAAAA==.',
Ve='Vecxlolz:BAAANQABCgUIBQAAAA==.Vecxous:BAAANQABCgYICQAAAA==.Veladar:BAAANQADCgcIBwAAAA==.Velaradraena:BAAANQADCgMIAwAAAA==.Velhunter:BAAANQAECggIEAAAAA==.Velush:BAABNQAECoEZAAIOAAkJySQeAQDPAwAOAAkJySQeAQDPAwAAAA==.Veressta:BAAANQAECgEIAgAAAA==.Verkk:BAAANQADCgQIBAAAAA==.',
Vi='Vienarissa:BAAANQADCgUICQAAAA==.Vifekoygua:BAAANQAECgQIBAAAAA==.Virulnekron:BAAANQAECggIEAAAAA==.Viserysll:BAAANQAECgEIAQABNQAECgIIAgACAAAAAA==.Vitaemors:BAAANQADCgQIBAAAAA==.Vitaminbee:BAAANQAECgQIDAABNQAECgUICgACAAAAAA==.',
Vl='Vlnar:BAAANQAECgcIDgAAAA==.',
Vo='Voeros:BAAANQADCgEIAQAAAA==.Voyagesoul:BAAANQADCgEIAgAAAA==.',
['Vê']='Vêspera:BAAANQADCgIIAgAAAA==.',
Wa='Wadeboggs:BAAANQAECgEIAQABNQAECgkJGAADAB4kAA==.Warrod:BAAANQAECgIIAgAAAA==.Washabilly:BAAANQAECgYICgAAAA==.',
We='Welbiner:BAAANQADCgUIBQABNQAECgIIAgACAAAAAA==.',
Wh='Whackem:BAAANQADCgYIBQAAAA==.Whookies:BAAANQADCgEIAQABNQAECgUIBwACAAAAAA==.Whö:BAAANQADCgIIAgABNQADCgUIBQACAAAAAA==.',
Wi='Wileyy:BAAANQADCgEIAQAAAA==.Windbinder:BAAANQAECgQIBQAAAA==.Wizfla:BAAANQAECgcIEAAAAA==.',
Wo='Wolfluna:BAAANQADCgcIEQAAAA==.Woljin:BAAANQADCgEIAQAAAA==.Woobzk:BAAANQADCgQICwAAAA==.Woolala:BAAANQADCgUIBQABNQAECgUICgACAAAAAA==.Woouid:BAAANQADCgYIBgABNQAECgYIBwACAAAAAA==.Woovoke:BAAANQAECgYIBwAAAA==.Workmoose:BAAANQADCggIFQAAAA==.Wouldisure:BAAANQADCggIDgAAAA==.',
Ww='Wwiilloow:BAAANQABCgQIBgAAAA==.',
Xa='Xanelos:BAAANQADCgYIDgAAAA==.',
Xo='Xoilbiss:BAAANQADCgIIAwAAAA==.',
Ya='Yanika:BAAANQAECgEIAQAAAA==.Yarellezi:BAAANQABCgQICwAAAA==.',
Ye='Yehwe:BAAANQADCggIEQAAAA==.',
Yi='Yiwan:BAAANQAECgcICQAAAA==.',
Yu='Yuismi:BAAANQADCgUIBQAAAA==.',
Za='Zartoga:BAAANQADCgEIAQAAAA==.Zasman:BAAANQAECgIIAwAAAA==.Zayabella:BAAANQAECgEIAQAAAA==.',
Ze='Zedrick:BAAANQADCgMIAwAAAA==.Zenchantress:BAAANQADCgEIAQAAAA==.Zephyrea:BAAANQAECgcIEQAAAA==.Zerimah:BAAANQAECgMIAwAAAA==.Zerx:BAAANQADCgYIBgAAAA==.Zetrathion:BAAANQAECgEIAQAAAA==.',
Zh='Zhakloskar:BAAANQADCgYIBgAAAA==.',
Zi='Ziaet:BAAANQADCgMIBAAAAA==.Zingerdk:BAEANQAECgMIAwAAAA==.Zinng:BAAANQAECgYICgAAAA==.',
Zo='Zoalara:BAAANQAECgQIBQAAAA==.Zodiakmage:BAAANQAECgIIAgABNQAECgQIBgACAAAAAA==.Zoroph:BAAANQADCgQIBAAAAA==.',
Zz='Zzaq:BAAANQAECgQICAABNQAECgkJHAADAFMeAA==.',
['Zá']='Záhr:BAAANQADCgMIBQAAAA==.',
['Zí']='Zíngerdh:BAEANQAECgEIAQABNQAECgMIAwACAAAAAA==.',
['Æë']='Æëgwynn:BAAANQADCgMIAwAAAA==.',
['Éo']='Éowyn:BAAANQADCgUIDwABNQAECgMIAwACAAAAAA==.',
['ßr']='ßrutal:BAAANQAECgYICwAAAQ==.',
['ßt']='ßteel:BAAANQADCggIDwAAAA==.',
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
