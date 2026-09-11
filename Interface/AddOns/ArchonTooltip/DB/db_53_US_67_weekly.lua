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

local lookup = {'Unknown-Unknown','DeathKnight-Blood','Paladin-Holy','Evoker-Augmentation','Evoker-Devastation','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Shaman-Restoration','Warrior-Arms','Druid-Balance','Druid-Restoration','Paladin-Retribution','Hunter-BeastMastery','Hunter-Marksmanship','DemonHunter-Devourer','DemonHunter-Vengeance','Warrior-Protection','DeathKnight-Unholy','DemonHunter-Havoc','Shaman-Elemental','Monk-Windwalker','Monk-Mistweaver',}
local provider = {region='US',realm='Destromath',name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Abraen:BAAANQADCgIIAgAAAA==.',
Ac='Achillis:BAAANQADCgIIAgAAAA==.',
Ad='Adapip:BAAANQAECgUIBgAAAA==.Adeille:BAAANQAECgIIAwAAAA==.Adrahmalik:BAAANQADCggIDgAAAA==.Adéra:BAAANQAECgEIAQAAAA==.',
Ae='Aeddann:BAAANQADCggIDgAAAA==.Aegiskline:BAAANQADCgYIBwAAAA==.Aerystargaer:BAAANQADCgYIFAAAAA==.',
Ag='Agnos:BAAANQAECgYIDAAAAA==.',
Ah='Ahiri:BAAANQABCgQIBgABNQAECgYIDAABAAAAAA==.',
Ak='Akstar:BAAANQAECgcIEQAAAA==.',
Al='Alaispere:BAAANQADCgcIDgAAAA==.Alalletsa:BAAANQAECgQICwAAAA==.Alanm:BAAANQAECgYICgAAAA==.Alf:BAAANQAECggIBAAAAA==.Allenwrench:BAAANQABCgEIAQAAAA==.Aloezilla:BAAANQADCggICQAAAA==.Alouna:BAAANQADCgYICgAAAA==.Alureae:BAAANQAECgQIBAAAAA==.',
An='Anaak:BAAANQAECgQIBQAAAA==.Anacooties:BAABNQAECoEpAAICAAgJkBwWDgCUAgACAAgJkBwWDgCUAgAAAA==.Angeliq:BAAANQAECgQIBAAAAA==.Anillusíon:BAAANQADCgYICwABNQAECgQIBAABAAAAAA==.',
Ar='Arathandris:BAAANQADCgQIBAAAAA==.Artivicious:BAAANQAECgEIAQABNQAECgQIBwABAAAAAA==.',
As='Ashalzith:BAAANQADCgQIBAAAAA==.Asherr:BAAANQADCgYIBgAAAA==.Astegous:BAAANQAECgMIAwAAAA==.Astraldaddy:BAAANQADCggIBAAAAA==.',
At='Athalandra:BAAANQAECgEIAQAAAA==.Athandor:BAAANQAECgYIBwAAAA==.Atmagos:BAAANQADCgMIAwAAAA==.',
Au='Aummgg:BAAANQADCgYICgAAAA==.Aurélius:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.',
Az='Azrei:BAAANQADCgYICAAAAA==.Azsrael:BAAANQADCgQIBAAAAA==.',
Ba='Baalhamoon:BAAANQAECgYICgAAAA==.Baangdog:BAEANQAECgQICAAAAA==.Bacsilog:BAAANQAECgUIDQAAAA==.Bahamût:BAAANQAECgUICAAAAA==.Baka:BAAANQADCgYIBgAAAA==.Balrong:BAAANQADCgEIAQAAAA==.Baobunns:BAAANQABCgYICgABNQAECgcIFwADAB8fAA==.Barackoshama:BAAANQAECgIIAgAAAA==.Barrac:BAAANQADCgQICQAAAA==.Basland:BAAANQAECgMIAwAAAA==.Bastanninn:BAAANQAECgQIBgAAAA==.Battlebéast:BAAANQAECgcIDQAAAA==.Baybaydrood:BAAANQADCgYIBgAAAA==.',
Be='Belariana:BAAANQADCgYIBwAAAA==.Belfnholy:BAAANQADCgUICQAAAA==.Beo:BAAANQADCgYICwAAAA==.Bezerk:BAAANQADCgIIAgAAAA==.',
Bi='Biff:BAAANQADCgMIAwAAAA==.Bigkeystone:BAAANQADCgYIDwABNQAECgUICAABAAAAAA==.',
Bl='Blaumeux:BAAANQADCggICAAAAA==.Bleepbleep:BAAANQADCgEIAQAAAA==.Blowkissbuny:BAAANQADCgUIBQAAAA==.',
Bo='Bolthirvoker:BAABNQAECoEoAAMEAAgJORbOAgAoAgAEAAgJORbOAgAoAgAFAAIJlwhiHgBdAAAAAA==.Bonesnapper:BAAANQADCgYICwAAAA==.Boochie:BAAANQADCggICAAAAA==.Boomrmnieech:BAAANQADCgEIAQAAAA==.Bountie:BAAANQADCgcIBwABNQAECgQIBAABAAAAAA==.',
Br='Braem:BAAANQABCgUICQAAAA==.Brasidas:BAAANQADCgcIDwAAAA==.Braxy:BAAANQADCgEIAQAAAA==.Brojan:BAAANQAECgIIAgAAAA==.Brokeni:BAAANQAECgQIBgAAAA==.Brokenn:BAAANQADCgUIBQAAAA==.Brontides:BAABNQAECoEQAAQGAAgJ/hK2GgBTAQAGAAUJgBK2GgBTAQAHAAUJchB9RAA7AQAIAAEJgRRmEQBQAAAAAA==.Bronzestra:BAAANQADCgYIBQAAAA==.',
Bu='Buffknight:BAAANQADCgUICwABNQAECgIIAgABAAAAAA==.Bufflock:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.Bulldin:BAAANQADCgQIBAAAAA==.Bullpup:BAABNQAECoEoAAIJAAgJXw4TKADVAQAJAAgJXw4TKADVAQAAAA==.Busschlight:BAAANQADCgUIBQAAAA==.',
Bw='Bweezy:BAAANQADCgUICwAAAA==.',
Ca='Calaies:BAAANQADCggICAAAAA==.Calithil:BAAANQADCggICAAAAA==.Callea:BAAANQAECgcIEgAAAA==.Camellia:BAAANQAECgMIBAAAAA==.',
Ce='Cenna:BAAANQAECgcIDwAAAA==.',
Ch='Chahilo:BAAANQADCgMIAwAAAA==.Chaostracker:BAAANQADCgUIBgAAAA==.Cheesedragon:BAAANQAECgQIBAAAAA==.Chicsilog:BAAANQADCgYIBwAAAA==.Chikkynuggy:BAAANQADCgUIBQAAAA==.Chikpi:BAAANQADCgcIDAAAAA==.Chipchops:BAAANQADCggIHAAAAA==.Chompyreaper:BAAANQAECgQICAAAAA==.Choonmami:BAAANQADCggIFQAAAA==.Chugbug:BAABNQAECoEYAAIKAAkJpyMWBQCVAwAKAAkJpyMWBQCVAwAAAA==.Chuuhai:BAAANQADCgQIBQAAAA==.',
Ci='Cigs:BAAANQADCgIIAgAAAA==.Citori:BAAANQADCgYIDAAAAA==.',
Cl='Clearlylight:BAAANQAECgEIAQAAAA==.Cloudburst:BAAANQAECgUIBQAAAA==.',
Co='Codysseus:BAAANQADCgcIBwAAAA==.Coldnad:BAAANQAECgEIAQAAAA==.Corpustotem:BAAANQADCggICwAAAA==.Cowbizarre:BAAANQADCgUIBQAAAA==.Cowcainez:BAAANQAECgYIBgAAAA==.',
Cr='Criptos:BAAANQAECgQIBAAAAA==.Cronus:BAAANQADCgQIBAAAAA==.Crotchchop:BAAANQADCgIIAgAAAA==.Crushadin:BAAANQADCgYIBgABNQAECgUIBwABAAAAAA==.Crushlock:BAAANQAECgUIBwAAAA==.Cryptastic:BAAANQADCgYICQAAAA==.',
Cu='Cureyourself:BAAANQADCgYIBgAAAA==.Cursedhunter:BAAANQADCgcIBwAAAA==.Cuttymofukuh:BAAANQAECgYICAABNQADCggICAABAAAAAA==.',
Cy='Cybelis:BAAANQAECgUIBQAAAA==.Cyclonespam:BAABNQAECoEXAAMLAAkJ6hwqEQCQAgALAAgJ5RsqEQCQAgAMAAUJXwmJGQAmAQAAAA==.',
Da='Daemonicus:BAAANQADCgYIBgAAAA==.Damiansdabom:BAAANQADCgYIBwABNQADCggIEQABAAAAAA==.Dangnabbit:BAAANQADCgIIAgAAAA==.Danicoldruna:BAABNQAECoGVAAINAAkJCycEAAArBAANAAkJCycEAAArBAAAAA==.Daniellol:BAAANQAECgMIAwAAAA==.Darkcoffee:BAAANQAECgMIAwAAAA==.',
De='Deadfrost:BAAANQADCgMIAwAAAA==.Deadliftz:BAAANQADCggICAAAAA==.Deadwolv:BAAANQAECgYIBgAAAA==.Deathtreader:BAAANQAECgQIBAAAAA==.Debeorer:BAAANQADCgcIBwAAAA==.Decoy:BAAANQADCggIDgABNQAECgkJFwAKANodAA==.Deepdh:BAAANQABCgMIAwAAAA==.Deepfathom:BAAANQAECgYICQAAAA==.Denecon:BAAANQAECgIIAgAAAA==.Derearis:BAAANQADCgYICAAAAA==.Derrusk:BAABNQAECoEXAAMOAAkJIiC6BwAUAwAOAAgJzSO6BwAUAwAPAAgJBA8GFQDwAQAAAA==.Derusk:BAAANQADCgYICQAAAA==.',
Dh='Dhazbëk:BAAANQADCggICAABNQAECgcIDgABAAAAAA==.Dhstone:BAABNQAECoEXAAMQAAkJ4hTYDgCAAgAQAAkJkxLYDgCAAgARAAEJjxrzDgBMAAAAAA==.',
Di='Dieten:BAAANQAECgYIBwAAAA==.Diploid:BAAANQAECgIIAgABNQAECgQIBAABAAAAAA==.Discgrace:BAAANQAECgQIBgAAAA==.Dividoo:BAAANQAECggIEAAAAA==.',
Dj='Djankula:BAAANQAECgUIBQAAAA==.',
Dl='Dliqnt:BAAANQAECgMIBAAAAA==.',
Do='Doclove:BAAANQAECgUIBwAAAA==.Doclux:BAAANQADCgQIBAAAAA==.Dollass:BAAANQAECgEIAQAAAA==.Dominique:BAAANQAECgQIBAAAAA==.Donkerz:BAAANQADCgIIAgABNQAECgcIEQABAAAAAA==.Doorah:BAAANQADCgYICAAAAA==.Doppleker:BAAANQAECgIIAgAAAA==.',
Dr='Draconectar:BAAANQAECgEIAQAAAA==.Dragoncecil:BAAANQAECgUIBQAAAA==.Drakkar:BAEANQAECggIEwAAAA==.Drakonasßaku:BAAANQADCggICAAAAA==.Dreezius:BAAANQAFFAEIAQAAAA==.Drelle:BAAANQAECgIIAgAAAA==.Droll:BAAANQADCggIEwAAAA==.Druidzie:BAAANQADCgQIBAAAAA==.',
Du='Dudemanguy:BAAANQADCgIIAwAAAA==.Dungflinger:BAAANQADCgcICwABNQAECgMIAwABAAAAAA==.Dunston:BAAANQADCgIIAgAAAA==.Durgash:BAAANQAECgIIAgAAAA==.',
Ea='Earthengrex:BAAANQAECgIIAgAAAA==.Easyheal:BAAANQADCgMIAwAAAA==.Easylover:BAAANQAECgcIEQAAAA==.',
Ee='Eetwontflush:BAAANQADCgUIBQAAAA==.',
Eh='Ehprilrayn:BAAANQAECgcIBwAAAA==.',
El='Elanderera:BAAANQADCgcIEQAAAA==.Elfy:BAAANQADCgQICAAAAA==.Elphaba:BAAANQADCgcIDAAAAA==.',
Em='Emsworth:BAAANQADCgIIAgAAAA==.',
Ep='Ephemeral:BAAANQADCgYIBgAAAA==.',
Er='Eriaelyn:BAAANQADCggIEQAAAA==.',
Fa='Facesedict:BAAANQAECgUIBwAAAA==.Fade:BAAANQAECgIIAgABNQAECgUIBgABAAAAAA==.Fargiland:BAAANQADCgQIBQAAAA==.',
Fe='Ferarche:BAAANQABCgQIAgABNQAECgYICgABAAAAAA==.Ferocitas:BAAANQAECgYICgAAAA==.',
Fl='Flinn:BAAANQAECgQICQAAAA==.Floe:BAAANQADCgEIAQAAAA==.',
Fo='Fostermatt:BAAANQADCggIEQAAAA==.Fowhammy:BAAANQAECgIIAwAAAA==.',
Fr='Frest:BAAANQAECgEIAQAAAA==.Frostedflake:BAAANQADCgQIBgABNQAECgUIBwABAAAAAA==.',
Fu='Fumblepull:BAAANQADCgIIAgAAAA==.',
['Fæ']='Fælis:BAAANQAECgMIAwAAAA==.',
Ga='Gabiru:BAAANQAECgYICwAAAA==.Galock:BAAANQAECgMIAwAAAA==.Galois:BAAANQAECgMIBQAAAA==.Gazzygos:BAAANQAECgcIEgAAAA==.',
Ge='Gexxor:BAAANQAECgQIBAAAAA==.',
Gl='Glassjaw:BAAANQADCgQIAwABNQAECgIIAgABAAAAAA==.Glickswap:BAAANQADCgUIBgAAAA==.Glimmr:BAEANQAECgMIAwABNQAECgYICwABAAAAAA==.',
Gn='Gniktar:BAAANQADCgcIBwAAAA==.',
Go='Goonslam:BAAANQAECgYIEgAAAA==.Goren:BAAANQAECgUIBgABNQAFFAEIAQABAAAAAA==.Gorgrimskull:BAAANQADCggIFAAAAA==.',
Gr='Grandy:BAAANQADCgIIAgAAAA==.Grandydin:BAAANQADCgIIAgAAAA==.Grapple:BAAANQAECgQIBgAAAA==.Graveheart:BAAANQADCgEIAQAAAA==.Greathadin:BAAANQABCgQIBAAAAA==.Grimnh:BAAANQADCgEIAgAAAA==.Grinchh:BAAANQAECgIIAgAAAA==.Grinnlock:BAAANQAECgcICQAAAA==.Gristle:BAAANQADCggICAABNQAECgUICAABAAAAAA==.Grïmm:BAAANQADCgcICwAAAA==.',
Gu='Guke:BAAANQADCgEIAQAAAA==.Gundee:BAAANQADCgEIAQAAAA==.',
Gy='Gymothee:BAAANQAECgEIAQAAAA==.',
Ha='Hachimi:BAAANQADCgQIBAAAAA==.Halima:BAAANQAECgUICAAAAA==.Hallowyn:BAAANQADCgUIBgAAAA==.Haraambe:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.Harandrood:BAAANQADCgEIAQABNQADCgMIAgABAAAAAA==.Harrothion:BAAANQAFFAMIAwAAAA==.Hautebussy:BAABNQAECoEXAAQHAAkJ0yPmBAAcAwAHAAgJZSPmBAAcAwAGAAYJzh1/DAD3AQAIAAEJ5iN3DgBoAAAAAA==.Havick:BAAANQADCgMIBAAAAA==.Hawkttwa:BAAANQADCgIIAgAAAA==.',
He='Heaton:BAABNQAECoEXAAMKAAkJ2h1JEQAAAwAKAAkJkh1JEQAAAwASAAIJUxy+EwCaAAAAAA==.Herfadin:BAAANQABCgQIBAAAAA==.Hewhohunts:BAAANQADCgYICgAAAA==.Heävymetal:BAAANQADCgcICQAAAA==.',
Hi='Highmoo:BAAANQAECgEIAQAAAA==.',
Ho='Hodgemous:BAAANQADCgIIAgAAAA==.Hoetems:BAAANQADCggICAAAAA==.Holykrapoli:BAAANQADCgQICAAAAA==.Hongkongcow:BAAANQAECgQIBwAAAA==.Hornsofcream:BAAANQADCgMIAwAAAA==.Hotpantz:BAAANQADCgcICwAAAA==.Howlingberry:BAAANQADCgcICgAAAA==.',
Hu='Hubbabubble:BAAANQADCgQIBgAAAA==.Hubble:BAAANQAECgEIAQAAAA==.Huntlex:BAAANQAECgUIBQAAAA==.Huntüdown:BAAANQADCggICAAAAA==.',
Ia='Iamfugly:BAAANQADCgUIBQAAAA==.',
Ic='Icen:BAAANQAECgMIAwAAAA==.',
Ii='Iinjyapan:BAABNQAECoEXAAIDAAcJHx9oEgCIAgADAAcJHx9oEgCIAgAAAA==.',
Il='Ileñdil:BAAANQADCggICAAAAA==.Illialadin:BAAANQADCggIEwAAAA==.',
Im='Imfiredurp:BAAANQAECgcIEgAAAA==.',
In='Invite:BAAANQAECgEIAQAAAA==.',
Io='Iod:BAAANQAECgQIBgABNQAECgYIDwABAAAAAA==.',
Is='Ishibakudan:BAAANQADCgUIBQABNQADCggIDgABAAAAAA==.Ishinosenso:BAAANQADCggIDgAAAA==.',
It='Itshebum:BAAANQAECgYICgAAAA==.',
Iz='Izukumidorya:BAAANQADCggIEAAAAA==.',
['Ià']='Iànocto:BAAANQADCgIIAgAAAA==.',
Ja='Jacrispy:BAAANQAECgIIAgAAAA==.Jaxsmighty:BAAANQADCgYIEAAAAA==.',
Je='Jedikenobi:BAAANQAECgYICQAAAA==.Jeraldo:BAAANQAECgIIAgAAAA==.',
Ji='Jibdorf:BAAANQADCgIIAgAAAA==.',
Jk='Jkilled:BAAANQAECgEIAQAAAA==.Jkstone:BAAANQADCgMIAwABNQAECgkJFwAQAOIUAA==.',
Jo='Joosyloosy:BAAANQAECgcICwABNQAECgkJGQAKAOEiAA==.Jov:BAAANQAECgMIAwAAAA==.',
Js='Jstone:BAAANQAECgQIBwAAAA==.',
Ju='Jubbad:BAAANQADCgcIBwAAAA==.Judgecow:BAAANQAECgUICAAAAA==.Juggo:BAAANQADCgYIBgAAAA==.Jupiterxalli:BAAANQAECgIIAgABNQAFFAEIAQABAAAAAA==.Justidius:BAAANQAECgEIAQAAAA==.Justjoan:BAAANQADCgIIAgAAAA==.',
Jv='Jvlbing:BAAANQADCgQIBQAAAA==.',
Ka='Kabrxis:BAAANQADCggIDQAAAA==.Kaelisa:BAAANQABCgIIAgAAAA==.Kalehl:BAAANQADCgUIBgAAAA==.Kassiaa:BAAANQADCgcIBwAAAA==.Kaylabug:BAAANQADCgQIBAAAAA==.',
Ke='Keanuglaives:BAEANQAECgIIAgABNQAECggIEwABAAAAAA==.Kelibastus:BAAANQAECgQIBgAAAA==.Kendoh:BAAANQADCgYICQAAAA==.',
Kh='Kharmah:BAAANQADCgQIBAAAAA==.',
Ki='Killshat:BAAANQAECgIIAwABNQAECgQICQABAAAAAA==.Kirt:BAAANQADCgYIBgAAAA==.Kissthismm:BAAANQADCgIIAgAAAA==.',
Ko='Kodoku:BAAANQAECgQICgAAAA==.Kovalo:BAAANQADCgMIAwAAAA==.',
Kr='Krho:BAAANQAECgQIBgAAAA==.Kringy:BAAANQADCgMIAwAAAA==.Krushnic:BAAANQADCgYIBgAAAA==.',
Ku='Kunalli:BAAANQADCggICAAAAA==.Kurohìme:BAEANQAECgYICwAAAA==.',
Kw='Kwynn:BAAANQADCgIIAgAAAA==.',
Ky='Kyrosh:BAAANQADCgUIBQAAAA==.',
['Kö']='Könígs:BAAANQAECggIDwAAAA==.',
La='Lacy:BAAANQADCgEIAQAAAA==.Lanadrius:BAAANQADCgYIBgAAAA==.Laralock:BAAANQADCgcICwAAAA==.Laramage:BAAANQADCgUIBQAAAA==.Larhon:BAAANQAFFAEIAQAAAA==.Larhonsmage:BAAANQAECgMIAwABNQAFFAEIAQABAAAAAA==.',
Le='Lesserashim:BAAANQADCgYIBgABNQAECgkJFwAPALIcAA==.',
Li='Lickity:BAAANQADCgEIAQABNQADCgMIAwABAAAAAA==.',
Lo='Lockeden:BAAANQADCgUICQAAAA==.Lockia:BAAANQAECgYIDAAAAA==.Lohah:BAAANQADCggIFAAAAA==.Lonron:BAAANQADCggIFAAAAA==.Lornir:BAAANQADCgQIBwAAAA==.Lorstan:BAAANQADCgUIBwAAAA==.',
Lu='Lunagoodlove:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Lunamort:BAAANQAECgEIAQAAAA==.Lutes:BAAANQADCggICwABNQAECgkJFwATALojAA==.Lutesadactyl:BAAANQADCgYIBgABNQAECgkJFwATALojAA==.Lutesectomy:BAABNQAECoEXAAITAAkJuiMpAwCNAwATAAkJuiMpAwCNAwAAAA==.Luuigii:BAAANQADCgcICwABNQADCggIEQABAAAAAA==.',
Ly='Lyghtbryght:BAAANQADCggICAAAAA==.Lyrath:BAAANQADCgcIEAAAAA==.Lytta:BAABNQAECoEQAAIUAAgJ6hugCQCJAgAUAAgJ6hugCQCJAgAAAA==.',
Ma='Macro:BAACNQAFFIEHAAIVAAYJqRVjAAApAgAVAAYJqRVjAAApAgA1AAQKgRoAAhUACQkIJoAAAO0DABUACQkIJoAAAO0DAAAA.Madkingog:BAAANQAECgQICQAAAA==.Mageoffayt:BAAANQABCgIIAgAAAA==.Mageyoulook:BAAANQADCggIDgAAAA==.Mahnu:BAAANQADCgQIBAAAAA==.Malebolgia:BAAANQADCggIEwAAAA==.Malodorous:BAAANQADCgIIAgAAAA==.Malralailea:BAAANQAECgQICQAAAA==.Mamallhama:BAAANQADCgcIDQAAAA==.Manathorr:BAAANQADCgYIBgAAAA==.Mattygg:BAAANQADCggIDgAAAA==.Mazikëën:BAAANQADCgcICAAAAA==.',
Mb='Mbappe:BAAANQADCgMIBAAAAA==.',
Mc='Mccuddles:BAAANQADCgUICAAAAA==.Mcspoopy:BAAANQADCgYIDQAAAA==.',
Me='Mechhunter:BAAANQADCgMIAgAAAA==.Melodý:BAEANQAECgYICgABNQAECgYICwABAAAAAA==.Melunara:BAAANQAECgEIAgAAAA==.Metinks:BAAANQAECgQIBgAAAA==.',
Mi='Miqo:BAAANQAECgUICQAAAA==.Missvanjie:BAABNQAECoEWAAIFAAkJ9RbWBADhAgAFAAkJ9RbWBADhAgAAAA==.',
Mo='Mooskie:BAAANQAECgQIBAAAAA==.Mortifera:BAAANQADCgUIBQAAAA==.',
Mu='Muckfury:BAAANQADCgcIEwAAAA==.Mursz:BAAANQAECgcIEQAAAA==.',
My='Mybrand:BAAANQADCggICAAAAA==.',
['Më']='Mëphisto:BAAANQAECgMIBAAAAA==.',
Na='Nachtigall:BAAANQADCgYIBgAAAA==.Nadintodd:BAAANQADCgYIBgAAAA==.Narigusmodx:BAAANQADCgEIAQAAAA==.Nastywill:BAAANQAECgYIBgAAAA==.Natsù:BAAANQAECgUIBgAAAA==.Nazghoule:BAAANQAECgYICwAAAA==.',
Ne='Neb:BAAANQADCgUIBQAAAA==.Nerdrange:BAAANQAECgUIBQAAAA==.Nessiecutie:BAAANQAECgEIAQAAAA==.Neverlucky:BAAANQADCgUIDAAAAA==.',
Ni='Nicorobin:BAAANQAECgUICAAAAA==.Nikon:BAAANQAECgQIBgAAAA==.Nintuk:BAAANQAECgcICwAAAA==.',
No='Noagro:BAAANQAECgMIAwAAAA==.Nodam:BAAANQADCgYICgAAAA==.Nostradam:BAAANQADCgYIDAAAAA==.',
Ny='Nysiss:BAAANQADCgcIDwAAAA==.',
Og='Ogdead:BAAANQADCgYIBgAAAA==.',
Oh='Ohyafenway:BAAANQADCgEIAQAAAA==.',
Ol='Oldfart:BAAANQADCgMIBAAAAA==.',
Om='Omniheart:BAAANQADCgYICgAAAA==.Omnilach:BAAANQAECgIIAgAAAA==.',
On='Onionn:BAAANQADCgYICgAAAA==.',
Oo='Ookamigin:BAAANQADCggIDAAAAA==.Oomagain:BAAANQADCgYIBwAAAA==.Oopzmybad:BAAANQADCgUIDAAAAA==.',
Ou='Outtacontrol:BAAANQAECgUICAAAAA==.',
Ov='Overpew:BAAANQAECgMIAwAAAA==.',
Pa='Pallyjones:BAAANQAECgMIBAAAAA==.Pannduh:BAAANQADCgQIBAAAAA==.Panospatako:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.Panya:BAAANQAECgQIBAAAAA==.',
Pe='Peepeeslam:BAAANQAECgYIBgABNQAECggIEAABAAAAAA==.Pekyaugai:BAAANQAECgEIAQAAAA==.Pelukan:BAAANQADCgYIBgAAAA==.Pennyblink:BAAANQAECgIIBAAAAA==.Peterosé:BAAANQADCgcIDQAAAA==.',
Ph='Phartbomb:BAAANQAECgIIAwAAAA==.Phatsy:BAAANQADCgYIBgAAAA==.Phoenixra:BAAANQADCgMIBwAAAA==.',
Pi='Piker:BAAANQAECgEIAQAAAA==.',
Pl='Pleb:BAAANQAECgIIAgAAAA==.',
Po='Policeman:BAAANQADCggICAAAAA==.Popozhao:BAABNQAECoEeAAMWAAkJbx/EBwCjAgAWAAcJWiHEBwCjAgAXAAgJ2AQXDwCDAQAAAA==.Portwine:BAAANQADCgEIAQAAAA==.Powerranger:BAAANQADCgYIBgAAAA==.',
Pr='Pragmata:BAAANQADCgUIBgAAAA==.Pryrxxe:BAAANQAECgQIBQAAAA==.',
Ps='Psyler:BAAANQADCgMIAwAAAA==.',
Pu='Pubzero:BAAANQAECgIIAgAAAA==.Pumpkindh:BAAANQADCgUIBQAAAA==.Pumpkinjuice:BAAANQAECgEIAQABNQADCgUIBQABAAAAAA==.Puppetcake:BAAANQADCgEIAQAAAA==.',
Qu='Quackiechan:BAAANQAECgcIEAAAAA==.Quasibeast:BAAANQADCgIIAgAAAA==.',
Ra='Raer:BAAANQAECgUIBQAAAA==.Ragabowa:BAAANQAECgYICwAAAA==.Raikirii:BAAANQAECggIEwAAAA==.Rampagejaxon:BAAANQADCgQIBAAAAA==.Ravaxys:BAAANQADCgQIBAAAAA==.Rayzac:BAAANQAECgQIBQAAAA==.',
Re='Redfacedemon:BAAANQADCgYIBgAAAA==.Renwall:BAAANQADCggIEgAAAA==.',
Ri='Rictusempra:BAAANQAECggIAQAAAA==.Rilwarp:BAAANQADCgYICgAAAA==.',
Ro='Rokash:BAAANQAECgIIAwABNQAFFAEIAQABAAAAAA==.Rozuveos:BAAANQADCgYIDwAAAA==.',
Ru='Rumplez:BAAANQAECggIBQAAAA==.',
Sa='Sabrano:BAAANQADCgQIBwAAAA==.Saelzington:BAABNQAECoEYAAIIAAkJGiQLAADZAwAIAAkJGiQLAADZAwAAAA==.Saepink:BAAANQADCggIDwABNQAECgkJGAAIABokAA==.Sakurajima:BAAANQAECgMIBAAAAA==.Samuraibicep:BAAANQADCgYIDwAAAA==.Sariiane:BAAANQAECgUIBQAAAA==.Sarrizza:BAAANQADCggIEQAAAA==.',
Sc='Scaledaddy:BAAANQADCggIFAAAAA==.Scartrist:BAAANQADCgcIEQAAAA==.Scrotimus:BAAANQADCggIEQAAAA==.Scylent:BAAANQADCgUIBgAAAA==.',
Se='Seasontwodk:BAAANQADCgQICQAAAA==.Selannil:BAAANQADCgEIAQAAAA==.',
Sh='Shadowbutt:BAAANQAECgUIBwAAAA==.Shadowdeadma:BAAANQAECgQIBAAAAA==.Shadowtaco:BAAANQADCgcIBwAAAA==.Shammyhagar:BAAANQABCgYIDAABNQABCgIIAgABAAAAAA==.Shankfoo:BAAANQADCgUIBQAAAA==.Shankpal:BAAANQADCgUIBQAAAA==.Shimmew:BAABNQAECoEXAAIPAAkJshzaBgAHAwAPAAkJshzaBgAHAwAAAA==.Shimmurt:BAAANQADCggICAABNQAECgkJFwAPALIcAA==.Shinhati:BAAANQAECgYICQAAAA==.',
Si='Sicariox:BAAANQAECgQICwAAAA==.',
Sk='Skeets:BAAANQADCgYICwAAAA==.Skizzixx:BAAANQADCgcICwAAAA==.',
Sl='Slapshop:BAAANQAECgQIBgAAAA==.Slice:BAAANQAECgIIAgAAAA==.Slippyfistt:BAAANQADCggIEwAAAA==.Slowansteady:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.',
Sm='Smashe:BAAANQABCgIIAgAAAA==.Smashleigh:BAAANQADCgUIBQAAAA==.Smoxx:BAAANQAECgQIBwAAAA==.Smörc:BAAANQADCgcIBwAAAA==.',
Sn='Sneeg:BAAANQAECgEIAgABNQAECggIDQABAAAAAA==.',
So='Sobchak:BAAANQAFFAEIAQAAAA==.Sober:BAAANQAECgcIDgAAAA==.Softfleur:BAAANQADCggIFQAAAA==.Softrminator:BAAANQADCgQIBQAAAA==.Sokz:BAAANQAECgYICgAAAA==.Sorago:BAAANQADCggICgAAAA==.Soraka:BAAANQAECgEIAQABNQAECgcIFwADAB8fAA==.Soxxs:BAAANQAECgEIAQAAAA==.',
Sp='Spartystrasz:BAAANQAECgYICgAAAA==.',
St='Starck:BAAANQADCggICAAAAA==.Starflight:BAAANQAECgEIAQAAAA==.Stonepaw:BAAANQADCgUICgAAAA==.Stormsound:BAAANQADCgYIBgAAAA==.',
Su='Sugoi:BAAANQAECgQIBwAAAA==.Surtvyr:BAEANQAECgEIAQABNQAECggIEwABAAAAAA==.',
Sw='Swagmonsta:BAAANQADCggICAAAAA==.Sweetdemonic:BAAANQADCgYICAAAAA==.Sweettoothz:BAAANQAECgYIBgAAAA==.Swiddles:BAAANQAECggIDQAAAA==.',
Sy='Syllee:BAAANQADCgMIAwAAAA==.',
Ta='Talara:BAAANQAECgEIAQAAAA==.Talsaiir:BAAANQADCgYIBgAAAA==.Talyyn:BAAANQADCgYICAAAAA==.Tater:BAAANQADCgQIBAABNQADCgUICQABAAAAAA==.Tatorshot:BAAANQADCgUICQAAAA==.',
Te='Tekmatek:BAAANQAECgUIBgAAAA==.Terpenes:BAAANQAECgYICwABNQADCggICAABAAAAAA==.',
Th='Thelust:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.Thienduongv:BAAANQADCgYIBgAAAA==.Thorhin:BAAANQAECgIIAgAAAA==.Thébígtúñá:BAAANQADCgcIEAAAAA==.',
Ti='Ticklemytots:BAAANQAECgUICgAAAA==.Tiltvoke:BAAANQAECgMIAwAAAA==.Tirynis:BAEBNQAECoEXAAINAAkJ0yQBAgDEAwANAAkJ0yQBAgDEAwAAAA==.',
Tl='Tlow:BAAANQAECgYICgAAAA==.',
Tm='Tmsmdfcrcls:BAAANQAECgMIBQAAAA==.',
To='Toelp:BAAANQAECgMIAwAAAA==.Tomacakes:BAAANQADCgIIAgAAAA==.Toothnnailz:BAAANQADCggICAAAAA==.Topochica:BAAANQADCgcIEwAAAA==.Totemtankn:BAAANQAECgQIBgAAAA==.Toxic:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.',
Tr='Trancemusic:BAAANQADCggICwAAAA==.Trashdk:BAAANQADCggICAABNQAECgMIBAABAAAAAA==.Treeboi:BAAANQADCgUIBQAAAA==.Triibs:BAAANQADCggIEQAAAA==.',
Tu='Tulashir:BAAANQABCgIIBAAAAA==.Turayne:BAAANQAECgEIAQAAAA==.Turbonex:BAAANQADCgIIAgAAAA==.',
Ty='Tyerial:BAAANQADCggICgAAAA==.Tyrear:BAAANQADCgEIAQAAAA==.Tyronbigadin:BAAANQAECgYICwAAAA==.',
['Té']='Témpèst:BAAANQAECgUICQABNQAECgcIDQABAAAAAA==.',
['Tõ']='Tõby:BAAANQAECgYICgAAAA==.',
Ul='Ultis:BAAANQADCgQIBAAAAA==.',
Va='Vaelphar:BAAANQADCgEIAQABNQADCgcICAABAAAAAA==.Valkÿrie:BAAANQAECgUICAAAAA==.Vandral:BAAANQAECgQIBQAAAA==.Varella:BAAANQAECgYICAAAAA==.Varnor:BAAANQADCgUICQAAAA==.',
Ve='Veinless:BAAANQAECgUIBQAAAA==.Velanné:BAAANQAECgYIDAABNQADCggICwABAAAAAA==.Venusx:BAAANQAECgQIBAABNQAFFAEIAQABAAAAAA==.Vethemir:BAAANQADCggICQABNQADCgYIBgABAAAAAA==.Vexmachína:BAAANQAECgQIBgAAAA==.Vextheria:BAAANQAECgMIAwAAAA==.Veyg:BAAANQAECgYIDAAAAA==.',
Vi='Viletrance:BAAANQADCggIEgAAAA==.Visenyatarg:BAAANQADCgYICgAAAA==.',
Vl='Vladikan:BAAANQADCgQIBAAAAA==.',
Vo='Vondo:BAAANQADCgcIBwABNQAECgkJFwAQAOIUAA==.Vorunaa:BAAANQAECgQIBQABNQAECgUIBgABAAAAAA==.Vorztrix:BAAANQAFFAEIAQAAAA==.',
Vy='Vythras:BAAANQAECgQIBgAAAA==.',
['Vä']='Välkyrie:BAAANQADCggIDAAAAA==.',
['Vå']='Vålkyrie:BAAANQAECgUICgAAAA==.',
['Vë']='Vëlzhen:BAAANQADCgMIAgABNQAECgcIDgABAAAAAA==.',
Wa='Wanacupcake:BAAANQADCgMIAwAAAA==.Warenn:BAAANQADCgIIAgAAAA==.Warstall:BAAANQAECgcIDgAAAA==.Waterincone:BAAANQAECgMIBAAAAA==.',
We='Weakswings:BAAANQABCgQICAAAAA==.Wercs:BAAANQADCgQIBAAAAA==.Wezethejuice:BAAANQADCgUICgAAAA==.',
Wh='Whitebison:BAAANQADCgcICgAAAA==.Wholelotaazz:BAAANQADCgEIAQAAAA==.',
Wi='Wiffartist:BAAANQAECgEIAQAAAA==.Willhsiao:BAAANQADCgYIDQAAAA==.',
Wo='Wogawogawoga:BAAANQADCgcIDQAAAA==.',
Wy='Wyatta:BAAANQADCgUIBQAAAA==.Wyrmbane:BAAANQADCgIIAgAAAA==.',
['Wì']='Wìsdom:BAAANQAECgQIBQAAAA==.',
Xa='Xaltwer:BAAANQADCggIDAAAAA==.Xasz:BAABNQAECoEXAAMJAAkJ7SVPAADfAwAJAAkJ7SVPAADfAwAVAAQJ2R77PQBYAQAAAA==.Xaszageth:BAAANQADCgcIDQABNQAECgkJFwAJAO0lAA==.',
Xc='Xcrush:BAAANQAECgYICQABNQAECgUIBwABAAAAAA==.',
Xd='Xdata:BAAANQAECgYICgAAAA==.',
Xe='Xerias:BAAANQAECgQICAAAAA==.',
Xi='Xieno:BAAANQADCgYIBgAAAA==.',
Xo='Xovyt:BAAANQAECgQIBAABNQAECgkJFwAHANMjAA==.',
Ya='Yaana:BAAANQADCggIGQAAAA==.Yaney:BAAANQADCgYICQAAAA==.',
Za='Zama:BAAANQADCgIIAgAAAA==.Zaranoria:BAAANQADCgQIBAABNQADCgYICwABAAAAAA==.Zarzlek:BAAANQAECgYICgAAAA==.',
Ze='Zenthyk:BAAANQAECgYICgAAAA==.Zephahniah:BAAANQADCgIIAgAAAA==.Zevyn:BAAANQADCgEIAQAAAA==.',
Zh='Zheela:BAAANQADCgYICgAAAA==.',
Zi='Zimbala:BAAANQAECgEIAQAAAA==.',
Zp='Zpants:BAAANQADCgUIEAAAAA==.',
Zu='Zulna:BAAANQAECgIIAgAAAA==.Zulrippa:BAAANQADCgMIAwAAAA==.',
Zy='Zyron:BAAANQADCgUIBwAAAA==.',
['Äm']='Ämon:BAAANQAECgEIAQAAAA==.',
['Ël']='Ëlyndal:BAAANQAECgcIDgAAAA==.',
['Ëñ']='Ëñÿõ:BAAANQAECgcIDAAAAA==.',
['ßr']='ßreezy:BAAANQAECgQIBAAAAA==.',
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
