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
local provider = {region='US',realm='Aegwynn',name='US',type='weekly',zone=53,date='2026-09-01',data={Aa='Aarista:BAAANQADCgIIAwAAAA==.',
Ab='Abhorrere:BAAANQABCgMIAwAAAA==.',
Ac='Acedririd:BAAANQAECgIIAgAAAA==.',
Ad='Ad:BAAANQADCgQIBAABNQADCgYIBwABAAAAAA==.Adönis:BAAANQABCgQIBQAAAA==.',
Ae='Aellerr:BAAANQAECgQIBAAAAA==.',
Af='Affyou:BAAANQADCggICAAAAA==.',
Ah='Ahzidal:BAAANQAECgEIAQABNQAECgcIDQABAAAAAA==.',
Ai='Ailbhe:BAAANQADCgUIBAAAAA==.Airbinwl:BAAANQAECgQIBAAAAA==.Aitchbar:BAAANQADCgEIAQAAAA==.',
Ak='Akanaar:BAAANQADCgEIAQAAAA==.Akilleess:BAAANQADCggIDAAAAA==.',
Al='Alaw:BAAANQADCgcICAAAAA==.Alexdd:BAAANQADCgEIAQAAAA==.Alexiathorne:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Alextros:BAEANQAECgEIAQAAAA==.Alivana:BAAANQADCgUIBgABNQAECgMIAwABAAAAAA==.Almaris:BAAANQAECgYICAAAAA==.Aloreilina:BAAANQADCgMIAwAAAA==.Alèx:BAAANQAECgYICAAAAA==.',
Am='Amarielle:BAAANQAECgMIAwAAAA==.Amire:BAAANQADCgYIEAAAAA==.Ammastolamor:BAAANQADCgIIAgAAAA==.',
An='Anahanu:BAAANQAECggICgAAAA==.Andrin:BAAANQADCgUIBQAAAA==.Angelawitch:BAAANQAECgEIAQABNQAECgYICgABAAAAAA==.Angienursey:BAAANQAECgYICgAAAA==.Annamolly:BAAANQAECgEIAQAAAA==.Annieruok:BAAANQADCgQIBAAAAA==.Antibiotix:BAAANQAECgQIBgAAAA==.',
Ap='Apocrithon:BAAANQADCgEIAQAAAA==.Apros:BAAANQAECgEIAQAAAA==.',
Aq='Aqss:BAAANQAECgYIDQAAAA==.',
Ar='Arakhana:BAAANQADCgIIAgAAAA==.Aralleah:BAAANQAECgEIAQAAAA==.Aratoreii:BAAANQADCgIIAgAAAA==.Archide:BAAANQAECgQIBAAAAA==.Arctose:BAAANQAECgcICgAAAA==.Ardoniak:BAAANQADCgQIBQAAAA==.Argenoth:BAAANQADCgEIAQAAAA==.Arkaeon:BAAANQADCgcIDQAAAA==.Arthar:BAAANQADCgEIAQAAAA==.',
As='Asdsfe:BAAANQADCgcIDQAAAA==.Ashandrei:BAAANQADCgcIDAAAAA==.Ashletil:BAAANQADCgEIAQAAAA==.Astraeadawn:BAAANQADCgMIAwAAAA==.Aszkme:BAAANQADCgMIAwAAAA==.',
At='Atri:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.',
Au='Auran:BAAANQAECgEIAQAAAA==.Authority:BAAANQAECgYIDAAAAA==.Autismosteve:BAAANQAECgMIAwAAAA==.',
Av='Avanlythia:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.',
Aw='Aware:BAAANQAECgcIDAAAAA==.',
Az='Azzuhpala:BAAANQAECggIDgAAAA==.',
Ba='Baddracthyr:BAAANQAECgYICgAAAA==.Batareva:BAAANQAECgQIBQAAAA==.',
Be='Beamnord:BAAANQADCgYIBwAAAA==.Beanie:BAAANQADCgcICQAAAA==.Bearlyere:BAAANQAECgMIAwAAAA==.Beastshine:BAAANQADCgQIBAAAAA==.Bendemus:BAAANQAECgYICQAAAA==.Berserkguts:BAAANQAECgIIAgAAAA==.Bersk:BAAANQADCgQIBAAAAA==.',
Bi='Bigker:BAAANQADCgIIAgAAAA==.Bitrot:BAAANQADCggIDQAAAA==.',
Bl='Blindbuns:BAAANQADCgUICwAAAA==.Blokejr:BAAANQADCgYIBwABNQADCggICAABAAAAAA==.Blooddagger:BAAANQAECgQIBAAAAA==.Bloodeater:BAAANQADCgYIBgAAAA==.Bloodnyte:BAAANQADCgIIAgAAAA==.',
Bo='Bobthbuilder:BAAANQADCgUIBQAAAA==.Bodhmal:BAAANQAECgYICgABNQAECgMIBAABAAAAAA==.Bootyhealz:BAAANQADCgQIBAAAAA==.',
Br='Brahe:BAAANQADCgYICgAAAA==.Brandun:BAAANQADCgYIBgAAAA==.Brokíìnn:BAAANQAECgYICgAAAA==.Broncas:BAAANQADCgEIAQAAAA==.Brotherbonk:BAAANQADCggICAAAAA==.Brucebearner:BAAANQAECggICQAAAA==.Bruff:BAAANQADCgEIAQAAAA==.Brufknight:BAAANQAECgEIAQAAAA==.Brókiinn:BAAANQADCggIDAAAAA==.',
Bu='Bukhanee:BAAANQADCgUICQAAAA==.Burmtron:BAAANQADCgcICwABNQADCgcIDwABAAAAAA==.Burmtronn:BAAANQADCgcIDwAAAA==.Bustabolt:BAAANQAECgIIAgAAAA==.',
Ca='Caceynn:BAAANQADCgEIAQAAAA==.Candyditto:BAAANQAECgIIAgABNQAFFAIIAgABAAAAAA==.Caoinlean:BAAANQADCgcIDQAAAA==.Carebearcare:BAAANQAECggIDAAAAA==.',
Ce='Celiaisake:BAAANQADCgYIDAAAAA==.Ceruibas:BAAANQADCgcIBwAAAA==.',
Ch='Chaoscat:BAAANQADCggIEAAAAA==.Chaossparkie:BAAANQADCggIDgAAAA==.Charlight:BAAANQADCggIEAAAAA==.Cheddarclaps:BAAANQABCgEIAQAAAA==.Cheeksdemon:BAAANQADCgYICwAAAA==.Cheesefriess:BAAANQAECgEIAQAAAA==.Chuckknight:BAAANQADCgMIAwAAAA==.Chuttbeeks:BAAANQADCgYIBgABNQADCggIEAABAAAAAA==.',
Ci='Cisnei:BAAANQABCgQIBgABNQADCgUICQABAAAAAA==.',
Co='Coggwalker:BAAANQADCgEIAQAAAA==.Coldiloks:BAAANQADCggIDQAAAA==.Corgruumn:BAAANQADCgMIAwAAAA==.',
Cr='Crastak:BAAANQADCgYIDAAAAA==.Crazyliquer:BAAANQADCgYIBgAAAA==.Crisy:BAAANQAECgQIBAAAAA==.',
Da='Dabbz:BAAANQAECgEIAQAAAA==.Daez:BAAANQADCgYICAABNQAECgYICAABAAAAAA==.Dahampster:BAAANQADCgQIBAAAAA==.Dailna:BAAANQAECgEIAQAAAA==.Dalamri:BAAANQADCgcIBwAAAA==.Dalarrorn:BAAANQADCgQIBwAAAA==.Dalitha:BAAANQADCgcICAAAAA==.Dalonar:BAAANQADCgYIBgAAAA==.Danhunter:BAAANQAECgcICwAAAA==.Darazana:BAAANQADCgUIBQAAAA==.Darkclawfox:BAAANQADCgQIBAAAAA==.Davbarx:BAAANQABCgQIBgAAAA==.Days:BAAANQAECgEIAQABNQAECgYICAABAAAAAA==.Daze:BAAANQAECgYICAAAAA==.Dazuiio:BAAANQAECgEIAQAAAA==.',
De='Deadrice:BAAANQAECgIIAgAAAA==.Declines:BAAANQADCgYICAAAAA==.Delso:BAAANQADCgUIBQAAAA==.Deltasara:BAAANQADCgMIAwAAAA==.Demonarbin:BAAANQAECgcIBwAAAA==.Demonkcorb:BAAANQADCggICAAAAA==.Deysonis:BAAANQAECgEIAQAAAA==.',
Dh='Dhbear:BAAANQAECgcICwAAAA==.',
Di='Dingberry:BAAANQAECgQIBAAAAA==.Dioghaltair:BAAANQADCgUIBQAAAA==.Diphyidae:BAAANQAECgEIAgAAAA==.Diyatea:BAAANQADCgYIBgAAAA==.Dizzle:BAAANQADCgYIBwAAAA==.',
Dm='Dmininstries:BAAANQAECgEIAQAAAA==.',
Do='Dodgeypoo:BAEANQADCgUIBQAAAA==.Domit:BAAANQADCgUICQAAAA==.Dommag:BAAANQADCgIIAgAAAA==.Doostfraba:BAAANQADCgEIAQAAAA==.Doots:BAAANQADCggIEAAAAA==.Dopey:BAAANQAECgQIBAAAAA==.Dorkplatypus:BAAANQAECgQIBwAAAA==.Doski:BAAANQAECgEIAQAAAA==.',
Dr='Dracoarbatel:BAAANQADCgMIAwAAAA==.Dragindeezz:BAAANQAECgEIAQABNQAFFAEIAQABAAAAAA==.Dragindemons:BAAANQAFFAEIAQAAAA==.Dragness:BAAANQADCgcIBwAAAA==.Dragonfroot:BAAANQADCggIEAAAAA==.Drakgo:BAAANQAECgIIAgAAAA==.Dravenuz:BAAANQAECgcICQAAAA==.Dreadarc:BAAANQADCgUIBQAAAA==.Drespirit:BAAANQADCgcICQAAAA==.Drewscylla:BAAANQADCggIDQAAAA==.Dripsyfist:BAAANQAECgUIBgAAAA==.Drixor:BAAANQADCgYICwABNQADCgcICgABAAAAAA==.Drone:BAAANQAECgYIBgABNQAECgcIDAABAAAAAA==.Druiden:BAAANQAECgYIBgABNQAFFAEIAQABAAAAAA==.Drumok:BAAANQAECgEIAQAAAA==.Dríxx:BAAANQADCgYIBwAAAA==.',
Du='Dumbledoof:BAAANQADCgYIDQAAAA==.',
['Dî']='Dîsfoo:BAAANQABCgIIAgAAAA==.',
Ea='Earlragnarl:BAAANQADCgEIAQAAAA==.',
Ec='Echarge:BAAANQAECgQICQAAAA==.',
Ed='Edandith:BAAANQADCggIDQAAAA==.Edsilencek:BAAANQADCggIDgAAAA==.',
El='Eleinna:BAAANQABCgIIAgABNQAECgEIAQABAAAAAA==.Ellodie:BAAANQADCgUIBQAAAA==.Ellíe:BAAANQADCgUIBwABNQAECgcIBwABAAAAAA==.Elmyndreda:BAAANQADCgcIDAAAAA==.Elrion:BAAANQAECgcIDQAAAA==.Eludin:BAAANQADCgcIBwAAAA==.Elwynyssa:BAAANQAECgUIBwAAAA==.',
Em='Emardo:BAAANQADCgQIBAAAAA==.Embiix:BAAANQADCgEIAQAAAA==.Emelia:BAAANQADCgEIAQAAAA==.Emptythreats:BAAANQADCgYIDgAAAA==.',
En='Enelyancalim:BAAANQADCgYICgAAAA==.',
Er='Erudite:BAAANQAECgQICQAAAA==.',
Et='Eteru:BAAANQADCgcIDQAAAA==.',
Eu='Euna:BAAANQADCgcIDQAAAA==.',
Ey='Eyko:BAAANQAECgQIBAAAAA==.',
['Eä']='Eädgyth:BAAANQAECgQIBwAAAA==.',
Fa='Farbauti:BAAANQAECgQIAwAAAA==.Fascinus:BAAANQABCgIIAgAAAA==.',
Fe='Fedrk:BAAANQADCgQIBAABNQADCgcICwABAAAAAA==.Fedu:BAAANQAECgEIAQAAAA==.Feldesk:BAAANQAECgQICQAAAA==.Fellich:BAAANQAECgIIAgAAAA==.Felspike:BAAANQADCgMIAwAAAA==.Ferp:BAAANQADCgYICwAAAA==.Festered:BAAANQAECgEIAQAAAA==.',
Fi='Fizzcopper:BAAANQAECgUICQAAAA==.',
Fk='Fkwalmart:BAAANQADCgYIBgABNQAECgYICQABAAAAAA==.',
Fl='Flitmg:BAAANQADCgQIBwAAAA==.Flowersnight:BAAANQAECgEIAQAAAA==.Flowerx:BAAANQADCggICAABNQADCggIDgABAAAAAA==.Flowerxx:BAAANQADCggIDgAAAA==.Flït:BAAANQADCgQIDgAAAA==.',
Fo='Fontanie:BAAANQADCgIIAgAAAA==.Fontaniebear:BAAANQABCgIIAgABNQADCgIIAgABAAAAAA==.Formroll:BAAANQADCgYICwAAAA==.',
Fr='Freakdawg:BAAANQAECgEIAQAAAA==.Freetime:BAAANQADCgYICgAAAA==.Freyabloom:BAAANQADCggIDgAAAA==.Froozxcdk:BAAANQAECgEIAQAAAA==.Froozxcwarr:BAAANQAECgQIBAAAAA==.Fruitloops:BAAANQADCgIIAgAAAA==.',
Fu='Furye:BAAANQAECgIIAgAAAA==.',
Ga='Gabbiani:BAAANQADCgcIBwAAAA==.Galondrake:BAAANQADCgIIAgABNQADCgYICgABAAAAAA==.Galonzenith:BAAANQADCgYICgAAAA==.Gargaki:BAAANQADCgUIAwAAAA==.Garm:BAAANQADCgEIAQAAAA==.Garyboldman:BAAANQADCgEIAQAAAA==.',
Ge='Geldrath:BAAANQADCgEIAQAAAA==.Genoddhunter:BAAANQAECgEIAQAAAA==.Gerfbert:BAAANQAECgQIBQAAAA==.Geø:BAAANQADCgYICwAAAA==.',
Gi='Giantess:BAAANQAECgIIAgABNQAECgMIBAABAAAAAA==.Gibbygibby:BAAANQADCggIEAAAAA==.Giggityz:BAAANQADCgMIAwAAAA==.Gigidygoo:BAAANQADCgMIAwAAAA==.Gilreth:BAAANQAECgQIBAAAAA==.Gilzaur:BAAANQAECgEIAQAAAA==.Gimrr:BAAANQADCgYICgAAAA==.',
Gj='Gjeoff:BAAANQADCgYIBgAAAA==.',
Gl='Glasshealing:BAAANQAECgEIAQAAAA==.',
Gn='Gnomepunzel:BAAANQADCgYICwAAAA==.',
Go='Goodys:BAAANQADCgEIAQAAAA==.Goopstick:BAAANQAECgQIBAAAAA==.Gorewood:BAAANQADCgQIBAAAAA==.Gorillamage:BAAANQAECgIIAgAAAA==.Gotag:BAAANQAECgIIAgAAAA==.',
Gr='Greatdeku:BAAANQADCgMIBAAAAA==.Grimmby:BAAANQADCgcIBwAAAA==.Grumpyangie:BAAANQADCgIIBAABNQAECgYICgABAAAAAA==.Grung:BAAANQAECgQIBAAAAA==.',
Gu='Gumbynutte:BAAANQADCggIDQAAAA==.',
Gw='Gwenita:BAAANQAECgEIAQAAAA==.Gwiontotems:BAEANQADCgQIBgABNQADCgcICwABAAAAAA==.',
Gy='Gyarados:BAAANQADCgIIAwAAAA==.Gyokuro:BAAANQADCgQIBAABNQADCgUIBQABAAAAAA==.',
['Gí']='Gízy:BAAANQAECgQIBAAAAA==.',
Ha='Habdearn:BAAANQADCgcIDQAAAA==.Hailey:BAEANQAECgYIBgAAAA==.Halfe:BAAANQADCgIIAgAAAA==.Hameey:BAAANQADCgYICwAAAA==.Haranitony:BAAANQAECgEIAQAAAA==.Havreth:BAAANQADCgUIBQAAAA==.Hazzardd:BAAANQAECgEIAQAAAA==.',
He='Heallium:BAAANQADCggIAgAAAA==.Healsonwheel:BAAANQADCgcIBwABNQAECgMIBQABAAAAAA==.Heelie:BAAANQADCgYIBgAAAA==.Heleris:BAAANQADCgMIBQAAAA==.Helgalila:BAAANQAECgMIAwAAAA==.Hellslord:BAAANQADCggICAAAAA==.Helmia:BAAANQADCggICQAAAA==.Heughjanus:BAAANQADCggIDwAAAA==.Hexonna:BAAANQADCgEIAQAAAA==.',
Hi='Hidere:BAAANQADCgEIAQAAAA==.',
Hl='Hlyparkbench:BAAANQAECgYICgABNQABCgIIAgABAAAAAA==.',
Ho='Hodge:BAAANQADCgYIBgABNQADCggIDQABAAAAAA==.Hodgey:BAAANQADCggIDQAAAA==.Holyhero:BAEANQADCgQIBAABNQADCgUIBQABAAAAAA==.Holymat:BAAANQADCgEIAQAAAA==.Holytweak:BAAANQABCgQIBAAAAA==.Hoovion:BAAANQADCgMIAwAAAA==.',
Hu='Hudimm:BAAANQADCgUICQAAAA==.Huggsnkisses:BAAANQADCgcICAAAAA==.Hunho:BAAANQADCggIBQAAAA==.Hunterjohn:BAAANQADCgEIAQAAAA==.',
Hy='Hynarillan:BAAANQADCgIIAQAAAA==.Hyorin:BAAANQADCgcIDAAAAA==.',
Ic='Icken:BAAANQADCgUIBQAAAA==.',
Id='Idefkanymore:BAAANQADCgYIDAAAAA==.Idomage:BAAANQADCgUIBQAAAA==.',
Il='Iludron:BAAANQADCgQIBAAAAA==.',
Im='Immaculates:BAAANQABCgIIAgAAAA==.Immunized:BAEANQADCgIIAgABNQADCgMIBQABAAAAAA==.Impedance:BAAANQADCgYIBgAAAA==.Imyaboi:BAAANQADCgYIBgAAAA==.Imzáiah:BAAANQADCggIDgAAAA==.',
In='Inforgame:BAAANQADCgUIBQAAAA==.Inkhunter:BAAANQADCgMIAwAAAA==.Inkmoon:BAAANQAECgMIAwAAAA==.Inningg:BAAANQADCggIDQAAAA==.Insânity:BAAANQAECgEIAQAAAA==.Invictus:BAAANQADCgYIDQAAAA==.',
Io='Ioweyouheals:BAAANQADCgYICgAAAA==.',
Ir='Ironaimorc:BAAANQADCgcIBwAAAA==.',
Is='Ishara:BAAANQADCgcIBwAAAA==.Isharian:BAAANQAECgIIAwAAAA==.Islandponder:BAAANQADCgMIBQABNQAECgQICQABAAAAAA==.',
It='Ithrowscars:BAAANQAECgQIBAAAAA==.',
Iv='Ivera:BAAANQADCggICQAAAA==.',
Ja='Jaliardys:BAAANQAECgUIBgAAAA==.Jareth:BAAANQADCgQIBAAAAA==.Jax:BAAANQADCgcIDQAAAA==.Jayia:BAAANQAECggIDgAAAA==.Jayie:BAAANQAECgcICwABNQAECggIDgABAAAAAA==.',
Je='Jedazar:BAAANQADCgUIBQAAAA==.Jefeli:BAAANQABCgEIAQAAAA==.',
Ji='Jijidruid:BAAANQADCgQIBAAAAA==.Jimf:BAAANQADCgQIBAAAAA==.Jinzi:BAAANQAECgEIAQAAAA==.',
Jj='Jjbang:BAAANQADCgYIBwAAAA==.',
Jm='Jmel:BAAANQADCgIIAgAAAA==.',
Jo='Jojomars:BAAANQADCgcICgAAAA==.Joosseri:BAAANQADCgQIBQAAAA==.Jorkho:BAAANQADCgQIBAAAAA==.Josespala:BAAANQAECgEIAQAAAA==.Journeydd:BAAANQADCgYICwAAAA==.',
Ka='Kaelish:BAAANQADCgEIAQAAAA==.Kafeene:BAAANQABCgQIBAAAAA==.Kagargo:BAAANQADCgYICQAAAA==.Kahlel:BAAANQADCgEIAQAAAA==.Kalnamos:BAAANQAECgQIBwAAAA==.Kaorinite:BAAANQAECgMIAwAAAA==.Karismâ:BAAANQADCgcIDAAAAA==.Kataela:BAAANQADCggICAAAAA==.Katanovich:BAAANQADCgcIDQAAAA==.Katparkbench:BAAANQADCgYIBgABNQABCgIIAgABAAAAAA==.Katyperryfan:BAAANQADCgUIBQAAAA==.Kauketkenna:BAAANQADCgEIAQAAAA==.',
Ke='Kegan:BAAANQADCgYICwAAAA==.Kela:BAAANQAECggICAAAAA==.Kelezekan:BAAANQADCggIDQAAAA==.Kelilina:BAAANQADCggIDwAAAA==.Keyelements:BAAANQADCgcIBwAAAA==.',
Kh='Khafie:BAAANQAECgYICwAAAA==.',
Ki='Killtech:BAAANQAECgEIAQAAAA==.Kimanip:BAAANQADCgYIBgAAAA==.Kimdeath:BAAANQAECgYIBgAAAA==.Kiraredclaw:BAAANQAECgQIBAAAAA==.Kitsukko:BAAANQAECgIIAgAAAA==.',
Kj='Kjarten:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.',
Ko='Kolu:BAAANQAECgEIAQAAAA==.Kozma:BAAANQADCgIIAgAAAA==.',
Kr='Kraedeyn:BAAANQAECgMIAwABNQADCgYIBgABAAAAAA==.Kraethas:BAAANQADCgEIAQAAAA==.Kraseva:BAAANQAECgEIAQAAAA==.Krell:BAAANQADCgYICwAAAA==.Kriek:BAAANQADCgYIBgABNQADCgYIDAABAAAAAA==.Krissiis:BAAANQADCgMIBAABNQADCgUIBQABAAAAAA==.Krixor:BAAANQADCgcICgAAAA==.Kråft:BAAANQADCggIEAABNQAECgEIAQABAAAAAA==.',
Ku='Kurome:BAAANQAECgIIBAAAAA==.',
Ky='Kynam:BAAANQADCgcIDQAAAA==.',
La='Landazanso:BAAANQADCgYICQAAAA==.Latina:BAAANQADCgcIBwAAAA==.Laynna:BAAANQAECgEIAQAAAA==.',
Le='Leguiz:BAAANQAECgQIBAAAAA==.Lemondreams:BAAANQAECgcIDAAAAA==.Lemontree:BAAANQADCgcICAAAAA==.Leorihk:BAAANQADCgEIAQAAAA==.Lerius:BAAANQADCgYIDAAAAA==.',
Li='Lightshadows:BAAANQADCggIDgAAAA==.Lilpikky:BAAANQADCgYIBgAAAA==.Lionfish:BAAANQADCgQIBAABNQADCgYIBwABAAAAAA==.Lirael:BAAANQADCgYICAAAAA==.Lizzborden:BAAANQADCgEIAQAAAA==.Lièrén:BAAANQAECgQIBAAAAA==.',
Lo='Lokjikju:BAAANQABCgIIAgAAAA==.Lonemadness:BAAANQADCgQIBQAAAA==.Lookitzmee:BAAANQADCgYIBgAAAA==.',
Lu='Lucixn:BAAANQADCggICAAAAA==.Lughbelenus:BAAANQADCgcIDAAAAA==.Lummytumkins:BAAANQADCggIDgAAAA==.',
Ly='Lyoko:BAAANQADCgIIAgAAAA==.Lyssandris:BAAANQAECgQIBQAAAA==.Lythany:BAAANQADCgYIDAAAAA==.',
['Lø']='Løkira:BAAANQADCgYIBwAAAA==.',
Ma='Mackncheese:BAAANQADCggIDgAAAA==.Maghhard:BAAANQAECgMIAwAAAA==.Magyst:BAAANQADCggIDwAAAA==.Malishine:BAAANQADCgMIAwAAAA==.Manabender:BAAANQADCgMIAwAAAA==.Mannersback:BAAANQAECgYICgAAAA==.Marrylou:BAAANQADCgIIAgAAAA==.Martelstorm:BAAANQADCgcIDAAAAA==.Materus:BAAANQAECgQIBgAAAA==.Mazzakeene:BAAANQADCgEIAQAAAA==.',
Me='Megasham:BAAANQAECgcICgAAAA==.Meion:BAEANQADCgYICQAAAA==.Melcam:BAAANQADCgYICAAAAA==.Metalspike:BAAANQADCgUIAwAAAA==.',
Mg='Mgdk:BAAANQAECgEIAQAAAA==.',
Mh='Mhorea:BAAANQAECgEIAQAAAA==.',
Mi='Miniash:BAAANQADCgcIBwAAAA==.Minox:BAAANQADCggIDAAAAA==.Mismage:BAAANQAECgEIAQAAAA==.Mistlore:BAAANQADCggICAAAAA==.Mistyfist:BAAANQADCgEIAQAAAA==.Mizuree:BAAANQADCgIIAgAAAA==.',
Mo='Monjax:BAAANQADCgYICQABNQAECgMIBwABAAAAAA==.Monkyblooms:BAAANQAECgYIBgAAAA==.Monmook:BAAANQAECgQIBQAAAA==.Moonfir:BAAANQADCgIIAgAAAA==.Moosah:BAAANQAECgYICgAAAA==.Moosetafa:BAAANQAECgEIAQAAAA==.Morgoonis:BAAANQAECgEIAQAAAA==.Morphyus:BAAANQAECgUIBQAAAA==.Mostlynotgay:BAAANQAECgEIAQAAAA==.Moxxz:BAAANQADCgQIBQAAAA==.',
Mu='Mundergy:BAAANQADCggICAABNQADCggIDQABAAAAAA==.Murazor:BAAANQAECgQIBAAAAA==.Mutilager:BAAANQADCggIDgAAAA==.',
My='Myeaasee:BAAANQAECgQIBgAAAA==.',
['Má']='Mágaidh:BAAANQADCgEIAQAAAA==.',
['Mî']='Mîko:BAAANQAECgQIBwAAAA==.',
Na='Naeyty:BAAANQAECgEIAQAAAA==.Nahtikalelle:BAAANQADCgYICwABNQAECgQIBQABAAAAAA==.Narcana:BAAANQADCggIDwABNQADCgUICQABAAAAAA==.Narusa:BAAANQAECgEIAQAAAA==.Nastyysham:BAAANQADCgYICwAAAA==.',
Ne='Neblissa:BAAANQADCgQIBAAAAA==.Negu:BAAANQAECgIIAgAAAA==.Neodknight:BAAANQAECgEIAQAAAA==.Neohuan:BAAANQADCgUICAAAAA==.Neomourne:BAAANQADCgUIBQABNQADCgUICAABAAAAAA==.Neoplasm:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Neoshield:BAAANQABCgEIAQABNQAECgEIAQABAAAAAA==.Nephran:BAAANQADCgEIAQAAAA==.Nerdibird:BAAANQADCgYICgAAAA==.',
Ni='Nialiaa:BAAANQADCgUIBQAAAA==.Nightvader:BAAANQAECggIBgABNQAECggICQABAAAAAA==.Nikomach:BAAANQADCgMIAwAAAA==.Nirwë:BAAANQADCgYICAAAAA==.Niviene:BAEANQADCgcICwAAAA==.',
No='Nokolutrearn:BAAANQADCgQIBAAAAA==.Noodlebender:BAAANQADCggIDQAAAA==.Noopsnoop:BAAANQAECgQIBAAAAA==.Noopy:BAAANQAECgIIAgAAAA==.Noriannera:BAAANQADCgcICAAAAA==.Nowhackingu:BAAANQADCgYIBgAAAA==.',
Nu='Nuggets:BAAANQADCgQIBAAAAA==.Nulight:BAAANQAECgIIAwAAAA==.Nutrients:BAAANQADCgIIAgAAAA==.',
Ny='Nyvrix:BAAANQADCgQICgAAAA==.Nyxnala:BAAANQADCgIIAwAAAA==.',
Oa='Oakenak:BAAANQADCgYIBgAAAA==.',
Oc='Octane:BAAANQADCgYIDAAAAA==.',
Od='Odiwen:BAAANQADCgUIBQAAAA==.Odyssa:BAAANQADCggIEAABNQAECgcIDQABAAAAAA==.',
Ol='Olfdu:BAAANQADCgUIBQAAAA==.',
Oo='Oolong:BAAANQADCgUIBQAAAA==.',
Or='Orindal:BAAANQADCgcIDQAAAA==.',
Pa='Palared:BAAANQAECgUIBwAAAA==.Palladiyne:BAAANQADCgUICgAAAA==.Palliearth:BAAANQADCgcIDQAAAA==.Pandö:BAAANQADCgYIBwAAAA==.Parict:BAAANQAECgYIAgAAAA==.',
Pe='Pennÿ:BAAANQADCgYICgAAAA==.Penthe:BAAANQADCgYIDgAAAA==.Penumbruh:BAAANQAECgQIBAAAAA==.',
Pf='Pfunk:BAAANQADCggIEgABNQAECgQIBwABAAAAAA==.',
Ph='Pheebegeobe:BAAANQAECgEIAQAAAA==.Phyzal:BAAANQADCgYICQAAAA==.Phåze:BAAANQADCgIIAgAAAA==.',
Pi='Piddlebom:BAAANQADCgcICQAAAA==.Pirani:BAAANQADCgMIAwAAAA==.Pitts:BAAANQADCgcICAAAAA==.',
Po='Ponyytail:BAAANQADCgYIFAAAAA==.Poodis:BAAANQADCgcIBwABNQADCgUIBQABAAAAAA==.Poshanka:BAAANQADCgYICgAAAA==.Poulsao:BAAANQADCgcIBwAAAA==.Powgun:BAAANQADCgIIAgAAAA==.',
Pr='Promyvïon:BAAANQADCgYIDAABNQADCgcIBwABAAAAAA==.',
Pu='Punchtruly:BAAANQADCggIDQAAAA==.',
Qd='Qdb:BAAANQADCggICQAAAA==.',
Qi='Qiaosheng:BAAANQADCgYIBgAAAA==.',
Ra='Rabbitunter:BAAANQADCgEIAQAAAA==.Rachejagerin:BAAANQADCgQIBAABNQAECgQIBQABAAAAAA==.Rackharrow:BAAANQADCgQIBAAAAA==.Raedammil:BAAANQADCgEIAQAAAA==.Raellé:BAAANQADCgcIBwAAAA==.Raiddaddy:BAAANQADCgUIBQABNQADCgYIDAABAAAAAA==.Ramlethal:BAAANQADCgEIAQAAAA==.Rapháèl:BAAANQAECgMIBwAAAA==.Rashelyn:BAAANQAECgQIBAAAAA==.Ravnsong:BAAANQADCgcICQAAAA==.Ravun:BAAANQABCgIIAgAAAA==.Raylea:BAAANQADCggIDgAAAA==.Raynevanity:BAAANQADCgEIAQAAAA==.Razenothen:BAAANQADCgMIAwAAAA==.',
Re='Reco:BAAANQAECgIIAwAAAA==.Rednazm:BAAANQADCggICAAAAA==.Redsdh:BAAANQADCgEIAQABNQAECgUIBwABAAAAAA==.Rem:BAAANQADCgUIBQAAAA==.Remimousy:BAAANQADCgIIAgAAAA==.Revdrax:BAAANQABCgIIAgAAAA==.Revosham:BAAANQAECgEIAQAAAA==.',
Rh='Rhaanall:BAAANQADCggIDAAAAA==.Rhaizu:BAAANQADCgYICAAAAA==.',
Ri='Riedreni:BAAANQABCgQIBAAAAA==.',
Ro='Rockytotems:BAAANQADCggICgAAAA==.Rogued:BAAANQAECgcICwAAAA==.Roldius:BAAANQADCgYIDAAAAA==.Rorodruida:BAAANQAECgIIAgAAAA==.Rothanos:BAAANQADCgUIBgAAAA==.Rouland:BAAANQAECgEIAQAAAA==.',
Ry='Rykthar:BAAANQADCgQIBAAAAA==.Ryvennah:BAAANQADCgYIBgAAAA==.',
['Rê']='Rêhm:BAAANQADCgYICwAAAA==.',
Sa='Sabelyn:BAAANQADCgMIAwAAAA==.Saioxenth:BAAANQAECgIIAgAAAA==.Sakmage:BAAANQAECgMIAwAAAA==.Salchypapa:BAAANQADCgYIDQABNQADCgcIBwABAAAAAA==.Salsbm:BAAANQADCggICAAAAA==.Samais:BAAANQADCgYIBgAAAA==.Samalia:BAAANQAECgYICQABNQAECggIDQABAAAAAA==.Samon:BAAANQADCgcICwAAAA==.Sanches:BAAANQADCgUIBQABNQAECgEIAgABAAAAAA==.Sandycheekz:BAAANQADCgIIAgAAAA==.Sanguineclaw:BAAANQADCgUICgAAAA==.Sanindon:BAAANQADCgMIAwAAAA==.Saranii:BAEANQADCgcICgAAAA==.Sariì:BAAANQADCgUIBgAAAA==.Sauloth:BAAANQADCgMIAwAAAA==.',
Sc='Scaled:BAAANQADCgEIAQAAAA==.Scarletpain:BAAANQADCgEIAQABNQADCggICQABAAAAAA==.Scarletpaws:BAAANQADCgUIBQABNQADCggICQABAAAAAA==.Scarlettanuk:BAAANQADCggICQAAAA==.Scragglum:BAAANQADCgIIAgAAAA==.Scromo:BAAANQADCggIEwAAAA==.Scv:BAAANQAECgcIDAAAAA==.',
Se='Senjougahara:BAAANQADCgQIBQAAAA==.Serejh:BAAANQADCgYICgAAAA==.',
Sh='Shadowbrnger:BAAANQAECgIIAgAAAA==.Shadowsongg:BAAANQADCgYIEwAAAA==.Shaggyd:BAAANQABCgIIAwAAAA==.Shamspam:BAAANQADCggIGAAAAA==.Shanatova:BAAANQADCgUICAAAAA==.Sharinknight:BAAANQAECgEIAQAAAA==.Shauriand:BAAANQADCgMIAwAAAA==.Shawman:BAAANQAECgEIAgAAAA==.Shehealfu:BAAANQADCggIDgAAAA==.Shigli:BAAANQADCgUIBQABNQAECgUIBQABAAAAAA==.Shishras:BAAANQAECgcICgAAAA==.Shnid:BAAANQADCgEIAQAAAA==.',
Si='Silentbozo:BAAANQADCgMIAwAAAA==.Sillydruid:BAAANQADCgUIBgAAAA==.Sillyrat:BAAANQAECgQIBAAAAA==.Sincados:BAAANQABCgIIAgAAAA==.Sionfaust:BAAANQADCgQIBAAAAA==.Sipper:BAAANQAECgMIBAAAAA==.Sixteenbit:BAAANQADCgEIAQAAAA==.',
Sk='Skandelóus:BAAANQADCggIDQAAAA==.',
Sl='Sleepymango:BAAANQADCgcIBwAAAA==.Slicky:BAAANQADCgIIAgABNQAECgYICwABAAAAAA==.',
Sm='Smashingface:BAAANQAECgEIAQAAAA==.',
So='Sokra:BAAANQADCgYICAAAAA==.Soldmyeggs:BAAANQADCggIDwAAAA==.Sordamac:BAAANQAECgQIBAAAAA==.',
Sp='Spidda:BAAANQAECgEIAQAAAA==.',
St='Stasismom:BAAANQAECgQIBAAAAA==.Stealthspike:BAAANQADCgcIBQAAAA==.Stompalittle:BAAANQADCggIEAABNQAECgcIDAABAAAAAA==.Stonesboyw:BAAANQADCgUICAAAAA==.Stormydniels:BAAANQAECgcIDQAAAA==.Strahz:BAAANQAECgQIBAAAAA==.Stunurazz:BAAANQAECgIIAgAAAA==.Sturtur:BAAANQADCgQIBAAAAA==.',
Su='Suddenstorm:BAAANQAECgUIBwAAAA==.Sudormrf:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.Sullywaffles:BAAANQADCgcIDAAAAA==.Sunryze:BAAANQADCgcIDQAAAA==.Sunspotted:BAAANQADCgIIAgAAAA==.Suralias:BAAANQAECgcICAAAAA==.Surashaman:BAAANQADCgcIBwABNQAECgcICAABAAAAAA==.',
Sw='Swankkie:BAAANQAECgQIBAAAAA==.',
Sy='Syraen:BAAANQADCggIDAAAAA==.',
Sz='Szylph:BAAANQADCgQIBgAAAA==.',
['Sä']='Säel:BAAANQADCgcICQAAAA==.',
['Sç']='Sçàr:BAAANQADCgMIAwAAAA==.',
Ta='Taebaek:BAAANQADCgUIBQAAAA==.Talantheron:BAAANQAECgIIAgABNQAECgcICgABAAAAAA==.Tanarcarissa:BAAANQADCgUIBwAAAA==.Tankboy:BAAANQAECgQIBAAAAA==.Tankiemctank:BAEANQADCgYICQAAAA==.Tathea:BAAANQADCggIDwAAAA==.Tatsuya:BAAANQAECgEIAQAAAA==.Tayzar:BAAANQADCgEIAQAAAA==.',
Te='Telisaria:BAAANQADCgcIBwAAAA==.Temnotal:BAAANQADCgQIBAAAAA==.Tendag:BAAANQADCgMIAwABNQAECggICgABAAAAAA==.Teorem:BAAANQADCgcIBwAAAA==.Tevulamezruj:BAAANQADCgUIBQAAAA==.',
Th='Thanaphos:BAAANQADCgcIDQAAAA==.Thatguyoquai:BAAANQADCgMIAwAAAA==.Thecbt:BAAANQADCgQIBAAAAA==.Thellara:BAAANQADCgYIBgAAAA==.Theprincer:BAAANQADCggIEAAAAA==.Therrai:BAAANQADCgYIDAAAAA==.Thirtyfloor:BAAANQADCgYIBgAAAA==.Thoromyr:BAAANQADCgUICQAAAA==.Thuato:BAAANQADCgQIBAAAAA==.Thundercats:BAAANQADCgYICgAAAA==.Thúndrstruck:BAAANQAECgEIAQABNQAECgcIDQABAAAAAA==.',
Ti='Tiffërny:BAAANQADCgIIAgAAAA==.Tivaan:BAAANQADCgcIFQAAAA==.Tizmprince:BAAANQADCgEIAQAAAA==.',
To='Torq:BAAANQAECgcIDQAAAA==.',
Tr='Traewynn:BAAANQADCgYIDQAAAA==.Trexy:BAAANQADCgcICgAAAA==.Triredgy:BAAANQAECgUIBQAAAA==.',
Ts='Tsilhqot:BAAANQADCgMIAwAAAA==.',
Tt='Tthatguyy:BAAANQADCgEIAQAAAA==.',
Tu='Tummyblaster:BAAANQADCgEIAQABNQADCgcIDQABAAAAAA==.Tummysnake:BAAANQADCgIIAgAAAA==.Turalya:BAAANQADCgYICwAAAA==.Tuychm:BAAANQADCgYICgAAAA==.',
Tw='Twareded:BAAANQADCgIIAgAAAA==.Twohandsome:BAAANQAECggIDQAAAA==.Twøføx:BAAANQAECgEIAQAAAA==.',
Ty='Tyinaa:BAAANQADCggIDQAAAA==.Tylenoldk:BAAANQADCgMIAwABNQAECgIIAwABAAAAAA==.Tyrallas:BAAANQADCggICgAAAA==.Tyrven:BAAANQADCgYIBgAAAA==.',
Ub='Ubba:BAAANQAECgIIAgAAAA==.',
Ul='Ulannya:BAAANQADCggICQAAAA==.Ulddon:BAAANQADCgYIBgAAAA==.Ullria:BAAANQADCgYIBgABNQADCgYIBwABAAAAAA==.',
Un='Undercovrmoo:BAAANQADCgcIDAAAAA==.',
Ur='Urdragon:BAAANQAECgEIAQAAAA==.Urving:BAAANQADCgYIBgAAAA==.',
Uw='Uwugnar:BAAANQADCgYIBgABNQADCggIDgABAAAAAA==.',
Va='Vaeltheris:BAAANQADCgYICQAAAA==.',
Ve='Vecxous:BAAANQABCgMIAgAAAA==.Veladar:BAAANQADCgMIAwAAAA==.Velaradraena:BAAANQADCgMIAwAAAA==.Velhunter:BAAANQAECgUICQAAAA==.Velush:BAAANQAFFAEIAQAAAA==.Veressta:BAAANQAECgEIAQAAAA==.',
Vi='Vienarissa:BAAANQADCgQIBAAAAA==.Vifekoygua:BAAANQAECgQIBAAAAA==.Virulnekron:BAAANQAECgYICQAAAA==.Vitaminbee:BAAANQAECgQICAAAAA==.',
Vl='Vlnar:BAAANQAECgYIBwAAAA==.',
Vo='Voeros:BAAANQADCgEIAQAAAA==.Voidplay:BAAANQADCgQIBgAAAA==.',
['Vê']='Vêspera:BAAANQADCgIIAgAAAA==.',
Wa='Warrod:BAAANQADCggIDQAAAA==.Washabilly:BAAANQAECgQIBAAAAA==.',
We='Welbiner:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.',
Wh='Whö:BAAANQADCgIIAgABNQABCgQIBAABAAAAAA==.',
Wi='Windbinder:BAAANQAECgEIAQAAAA==.Wizfla:BAAANQAECgUICQAAAA==.',
Wo='Wolfluna:BAAANQADCgcIBwAAAA==.Woljin:BAAANQADCgEIAQAAAA==.Woobzk:BAAANQADCgQIBwAAAA==.Woolala:BAAANQADCgUIBQABNQAECgQICAABAAAAAA==.Woouid:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Woovoke:BAAANQAECgEIAQAAAA==.Workmoose:BAAANQADCgYIDQAAAA==.Wouldisure:BAAANQADCgYIDAAAAA==.',
Xa='Xanelos:BAAANQADCgYICgAAAA==.',
Xo='Xoilbiss:BAAANQADCgIIAwAAAA==.',
Ya='Yanika:BAAANQADCgUIAQAAAA==.Yarellezi:BAAANQABCgQIBwAAAA==.',
Ye='Yehwe:BAAANQADCgYICgAAAA==.',
Yi='Yiwan:BAAANQAECgIIAgAAAA==.',
Yu='Yuismi:BAAANQADCgQIBAAAAA==.',
Za='Zartoga:BAAANQADCgEIAQAAAA==.Zasman:BAAANQAECgIIAQAAAA==.Zayabella:BAAANQADCgIIAgAAAA==.',
Ze='Zedrick:BAAANQADCgEIAQAAAA==.Zenchantress:BAAANQADCgEIAQAAAA==.Zephyrea:BAAANQAECgYICQAAAA==.Zerimah:BAAANQADCggIDgAAAA==.Zerx:BAAANQADCgYIBgAAAA==.Zetrathion:BAAANQAECgEIAQAAAA==.',
Zi='Ziaet:BAAANQADCgMIBAAAAA==.Zingerdk:BAEANQAECgIIAgAAAA==.Zinng:BAAANQAECgQIBAAAAA==.',
Zo='Zoalara:BAAANQAECgEIAQAAAA==.Zodiakmage:BAAANQAECgIIAgAAAA==.Zoroph:BAAANQADCgQIBAAAAA==.',
Zz='Zzaq:BAAANQAECgQICAAAAA==.',
['Zá']='Záhr:BAAANQADCgMIAwAAAA==.',
['Zí']='Zíngerdh:BAEANQAECgEIAQABNQAECgIIAgABAAAAAA==.',
['Éo']='Éowyn:BAAANQADCgUICgABNQADCggIDAABAAAAAA==.',
['ßr']='ßrutal:BAAANQAECgQIBQAAAQ==.',
['ßt']='ßteel:BAAANQADCggICQAAAA==.',
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
