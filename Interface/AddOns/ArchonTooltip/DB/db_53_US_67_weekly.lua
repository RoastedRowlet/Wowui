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

local lookup = {'Unknown-Unknown','Mage-Arcane','Druid-Balance','DeathKnight-Blood','Monk-Windwalker','Paladin-Holy','Evoker-Augmentation','Evoker-Devastation','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Shaman-Restoration','Priest-Shadow','Priest-Holy','DemonHunter-Havoc','Warrior-Arms','Druid-Restoration','Paladin-Retribution','Hunter-BeastMastery','Hunter-Marksmanship','DemonHunter-Devourer','DemonHunter-Vengeance','Shaman-Elemental','Evoker-Preservation','Warrior-Protection','Rogue-Assassination','Rogue-Outlaw','DeathKnight-Unholy','Monk-Mistweaver','Hunter-Survival',}
local provider = {region='US',realm='Destromath',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aadden:BAAANQAECggIAgAAAA==.',
Ab='Abraen:BAAANQADCgIIAgAAAA==.',
Ac='Achillis:BAAANQADCgIIAgAAAA==.',
Ad='Adapip:BAAANQAECgcIDAAAAA==.Adeille:BAAANQAECgQIBwAAAA==.Adrahmalik:BAAANQADCggIDgAAAA==.Adéra:BAAANQAECgQIBQAAAA==.',
Ae='Aeddann:BAAANQADCggIDgAAAA==.Aegiskline:BAAANQADCgYIBwAAAA==.Aerystargaer:BAAANQADCgYIGgAAAA==.',
Ag='Agnos:BAAANQAECgYIDAAAAA==.',
Ah='Ahiri:BAAANQABCgQIBgABNQAECgYIEAABAAAAAA==.',
Ak='Akstar:BAABNQAECoEaAAICAAgJMhtlPwCVAgACAAgJMhtlPwCVAgAAAA==.',
Al='Alaispere:BAAANQADCgcIFAAAAA==.Alalletsa:BAABNQAECoEWAAIDAAYJhxHtNQB5AQADAAYJhxHtNQB5AQAAAA==.Alanm:BAAANQAECgYICgAAAA==.Alf:BAAANQAECggIBwAAAA==.Alfons:BAAANQADCgUIBQAAAA==.Allenwrench:BAAANQABCgEIAQAAAA==.Aloezilla:BAAANQADCggICQAAAA==.Alouna:BAAANQADCgYICgAAAA==.Alureae:BAAANQAECgUICQAAAA==.',
An='Anaak:BAAANQAECgQIBQAAAA==.Anacooties:BAABNQAECoE7AAIEAAkJtR0JDAD6AgAEAAkJtR0JDAD6AgAAAA==.Angeliq:BAAANQAECgQICQAAAA==.Anillusíon:BAAANQADCgYICwABNQAECgUICQABAAAAAA==.',
Ap='Apistotoke:BAAANQADCgUIBQAAAA==.',
Ar='Arathandris:BAAANQADCgQIBAAAAA==.Artivicious:BAAANQAECgIIAgABNQAECgUIDAABAAAAAA==.',
As='Ashalzith:BAAANQADCgQIBAAAAA==.Asherr:BAAANQADCgYIBgAAAA==.Astegous:BAAANQAECgMIAwAAAA==.Astrae:BAAANQADCgYIBgAAAA==.Astraldaddy:BAAANQADCggIBAAAAA==.',
At='Athalandra:BAAANQAECgEIAQAAAA==.Athandor:BAAANQAECgYIDQAAAA==.Atmagos:BAAANQADCgMIAwAAAA==.',
Au='Aummgg:BAAANQADCgcIDgAAAA==.Aurélius:BAAANQADCgYIBgABNQAECgQIBwABAAAAAA==.',
Az='Azrei:BAAANQADCgYICAAAAA==.Azsrael:BAAANQADCgQIBAAAAA==.',
Ba='Baalhamoon:BAAANQAECgcIEQAAAA==.Baangdog:BAEANQAECgYIDgAAAA==.Bacsilog:BAABNQAECoEaAAIFAAcJaQ/0GACfAQAFAAcJaQ/0GACfAQAAAA==.Bahamût:BAAANQAECgUICAAAAA==.Baka:BAAANQAECgEIAQAAAA==.Balrong:BAAANQADCgEIAQAAAA==.Baobunns:BAAANQABCgYICgABNQAECggIJgAGAB8hAA==.Barackoshama:BAAANQAECgQIBgAAAA==.Barrac:BAAANQADCggIEQAAAA==.Basland:BAAANQAECgMIBAAAAA==.Bastanninn:BAAANQAECgUICAAAAA==.Battlebéast:BAAANQAECgcIEAAAAA==.Baybaydrood:BAAANQADCgYIBwAAAA==.',
Be='Belariana:BAAANQADCgYIBwAAAA==.Belfnholy:BAAANQADCgUICQAAAA==.Bellybutton:BAAANQADCgYIBgAAAA==.Beo:BAAANQADCgYICwAAAA==.Bezerk:BAAANQADCgUIBwAAAA==.',
Bi='Biff:BAAANQAECgEIAQAAAA==.Bigkeystone:BAAANQAECgIIAgABNQAECgUIDQABAAAAAA==.',
Bl='Blaumeux:BAAANQADCggICAAAAA==.Bleepbleep:BAAANQADCgEIAQAAAA==.Blowkissbuny:BAAANQADCgUIBQAAAA==.',
Bo='Bolthirfists:BAAANQADCggICgABNQAECgkJOQAHAAAbAA==.Bolthirvoker:BAABNQAECoE5AAMHAAkJABsCAgDnAgAHAAkJABsCAgDnAgAIAAIJlwiOJABaAAAAAA==.Bonesnapper:BAAANQADCggIEwAAAA==.Boomrmnieech:BAAANQADCgYIBwAAAA==.Bountie:BAAANQADCgcIBwABNQAECgYICgABAAAAAA==.',
Br='Braem:BAAANQABCgYIDAAAAA==.Bralinian:BAAANQADCgMIAwAAAA==.Brasidas:BAAANQADCggIFgAAAA==.Braxy:BAAANQADCgEIAQAAAA==.Brojan:BAAANQAECgQIBAAAAA==.Brokeni:BAAANQAECgQICQAAAA==.Brokenn:BAAANQADCgUIBQAAAA==.Brontides:BAABNQAECoETAAQJAAkJHhJrFgCVAQAJAAYJYBFrFgCVAQAKAAYJjg/FVQB0AQALAAEJgRSPFwBJAAAAAA==.Bronzestra:BAAANQADCgYIBQAAAA==.',
Bu='Buffknight:BAAANQADCgUICwABNQAECgUIBwABAAAAAA==.Bufflock:BAAANQADCgUIBQABNQAECgUIBwABAAAAAA==.Bulldin:BAAANQADCgQIBAAAAA==.Bullpup:BAABNQAECoE5AAIMAAkJ+hCLKQAeAgAMAAkJ+hCLKQAeAgAAAA==.Burrett:BAAANQAECgQIBAAAAA==.Busschlight:BAAANQADCgUIBQAAAA==.',
Bw='Bweezy:BAAANQADCgUICwAAAA==.',
Ca='Calaies:BAAANQADCggICAAAAA==.Calithil:BAAANQADCggIDgAAAA==.Callea:BAABNQAECoEnAAMNAAkJUBd1EABhAgANAAgJfxV1EABhAgAOAAEJCwwUhQBHAAAAAA==.Camellia:BAAANQAECgMIBgAAAA==.',
Ce='Cenna:BAABNQAECoEXAAIPAAgJmRzUDQCuAgAPAAgJmRzUDQCuAgAAAA==.',
Ch='Chahilo:BAAANQADCgMIAwAAAA==.Chaostracker:BAAANQADCgUIBgAAAA==.Cheesedragon:BAAANQAECgQICAAAAA==.Chicsilog:BAAANQAECgEIAQAAAA==.Chikkynuggy:BAAANQADCgUIBQAAAA==.Chikpi:BAAANQADCggIFAAAAA==.Chipchops:BAAANQADCggIHAAAAA==.Chompyreaper:BAAANQAECgQICAAAAA==.Choonmami:BAAANQADCggIGwAAAA==.Chugbug:BAACNQAFFIEGAAIQAAQJ5BhhBgBkAQAQAAQJ5BhhBgBkAQA1AAQKgR4AAhAACQmqI60IAIoDABAACQmqI60IAIoDAAAA.Chuuhai:BAAANQADCgQIBQAAAA==.',
Ci='Cigs:BAAANQADCgIIAgAAAA==.Citori:BAAANQADCgcIDAAAAA==.',
Cl='Clearlylight:BAAANQAECgYICQAAAA==.Cloudburst:BAAANQAECgUICAAAAA==.',
Co='Codysseus:BAAANQADCgcIBwAAAA==.Coldnad:BAAANQAECgEIAQAAAA==.Corpustotem:BAAANQADCggIDgAAAA==.Cowbizarre:BAAANQADCggIDQAAAA==.Cowcainez:BAAANQAECgYIBgAAAA==.',
Cr='Criptos:BAAANQAECgUICAAAAA==.Cronus:BAAANQADCgQIBAAAAA==.Crotchchop:BAAANQADCgIIAgABNQAECgQIBgABAAAAAA==.Crushadin:BAAANQADCgYIBgABNQAECgYIDQABAAAAAA==.Crushlock:BAAANQAECgYIDQAAAA==.Cryptastic:BAAANQADCggIEgAAAA==.',
Cu='Cureyourself:BAAANQADCgYICwAAAA==.Cursedhunter:BAAANQADCgcIBwAAAA==.Cuttymofukuh:BAAANQAECgYICAABNQADCggIDAABAAAAAA==.',
Cy='Cyb:BAAANQADCggICAAAAA==.Cybelin:BAAANQADCgYIBgAAAA==.Cybelis:BAAANQAECgUIBgAAAA==.Cyclonespam:BAABNQAECoEgAAMDAAkJmR8EFAC7AgADAAgJ5B4EFAC7AgARAAUJXwlmIgAhAQAAAA==.',
Da='Daemonicus:BAAANQADCgcICwAAAA==.Damiansdabom:BAAANQADCgYIDQABNQAECgIIAgABAAAAAA==.Dancemusic:BAAANQADCggICAAAAA==.Dangnabbit:BAAANQADCgIIAgAAAA==.Danicoldruna:BAABNQAECoH0AAISAAkJDCcCAAApBAASAAkJDCcCAAApBAAAAA==.Daniellol:BAAANQAECgMIBAAAAA==.Darkcoffee:BAAANQAECgMIAwAAAA==.',
De='Deadfrost:BAAANQADCgUIBQAAAA==.Deadliftz:BAAANQADCggICAAAAA==.Deadwolv:BAAANQAECgYIDAAAAA==.Deathtreader:BAAANQAECgQIBQAAAA==.Debeorer:BAAANQADCgcIBwAAAA==.Decoy:BAAANQADCggIDgABNQAECgkJIAAQAPogAA==.Deepdh:BAAANQABCgMIAwAAAA==.Deepfathom:BAAANQAECgYIDwAAAA==.Denecon:BAAANQAECgIIAgAAAA==.Derearis:BAAANQADCgYICAAAAA==.Derrusk:BAABNQAECoEgAAMTAAkJCSGSDwD7AgATAAgJpCSSDwD7AgAUAAgJ0RG/GAADAgAAAA==.Derusk:BAAANQADCggIEQAAAA==.',
Dh='Dhazbëk:BAAANQAECgQIBAABNQAECggIEwABAAAAAA==.Dhstone:BAABNQAECoEcAAMVAAkJHxiIDgCyAgAVAAkJ+heIDgCyAgAWAAEJjxo9FQBJAAAAAA==.',
Di='Dieten:BAAANQAECgYIBwAAAA==.Diploid:BAAANQAECgQIBgABNQAECgUICAABAAAAAA==.Discgrace:BAAANQAECgQIBgAAAA==.Discordance:BAAANQABCgMIBQAAAA==.Dividoo:BAABNQAECoEdAAMGAAkJyhj/EwDAAgAGAAkJyhj/EwDAAgASAAEJkRp50gBQAAAAAA==.',
Dj='Djankula:BAAANQAECgUICgAAAA==.',
Dl='Dliqnt:BAAANQAECgUICQAAAA==.',
Do='Doclove:BAAANQAECgYIDAAAAA==.Doclux:BAAANQADCgQIBAAAAA==.Dollass:BAAANQAECgEIAQAAAA==.Dominique:BAAANQAECgYIDAAAAA==.Donkerz:BAAANQAECgcIBwABNQAECgcIEQABAAAAAA==.Doorah:BAAANQADCgYICAAAAA==.Doppleker:BAAANQAECgIIAgAAAA==.',
Dr='Draconectar:BAAANQAECgMIBAAAAA==.Dragoncecil:BAAANQAECgUIBgAAAA==.Drakkar:BAEBNQAECoEaAAIXAAkJLROtJQBIAgAXAAkJLROtJQBIAgAAAA==.Drakonasßaku:BAAANQADCggICAAAAA==.Dreezius:BAAANQAFFAIIAwAAAA==.Drelle:BAAANQAECgQIBgAAAA==.Droll:BAAANQAECgEIAQAAAA==.Druidzie:BAAANQADCgQIBAAAAA==.Drunkus:BAAANQABCgIIAgAAAA==.',
Du='Dudemanguy:BAAANQADCgMIBgAAAA==.Dungflinger:BAAANQADCgcICwABNQAECgMIAwABAAAAAA==.Dunston:BAAANQADCgIIAgAAAA==.Durgash:BAAANQAECgMIAwAAAA==.',
Dv='Dvergr:BAAANQADCgMIAwAAAA==.',
Ea='Earthengrex:BAAANQAECgMIBQAAAA==.Easyheal:BAAANQADCgMIAwAAAA==.Easylover:BAAANQAECgcIEQAAAA==.',
Ee='Eetwontflush:BAAANQADCgUIBQAAAA==.Eevuhl:BAAANQABCgYIBAAAAA==.',
Eh='Ehprilrayn:BAAANQAECgcIBwAAAA==.',
Ek='Ekoli:BAAANQADCgUIBQAAAA==.',
El='Elanderera:BAAANQADCgcIGAAAAA==.Electratic:BAAANQADCgYIBgABNQAECgYIDQABAAAAAA==.Elfy:BAAANQADCgQICAAAAA==.Elphaba:BAAANQADCgcIDAAAAA==.',
Em='Emberstorm:BAAANQABCgUIBQAAAA==.',
Ep='Ephemeral:BAAANQADCgYIBgAAAA==.',
Er='Eriaelyn:BAAANQAECgEIAQAAAA==.',
Fa='Facesedict:BAAANQAECgUICwAAAA==.Fade:BAAANQAECgIIAwABNQAECgUICQABAAAAAA==.Fargiland:BAAANQADCgQIBQAAAA==.',
Fe='Ferarche:BAAANQABCggICQABNQAECgYIEAABAAAAAA==.Ferocitas:BAAANQAECgYIEAAAAA==.',
Fl='Flaccidarrow:BAAANQAECgEIAQABNQAECgUIDQABAAAAAA==.Flinn:BAAANQAECgQIDQAAAA==.Floe:BAAANQADCgEIAQAAAA==.Flutter:BAEANQADCgQICAABNQAECgcIDQABAAAAAA==.',
Fo='Forshy:BAAANQADCgUIBQAAAA==.Fostermatt:BAAANQADCggIGQAAAA==.Fowhammy:BAAANQAECgUICAAAAA==.',
Fr='Frest:BAAANQAECgIIAwAAAA==.Frostedflake:BAAANQADCgQIBgABNQAECgYIDQABAAAAAA==.',
Fu='Fumblepull:BAAANQADCgIIAgAAAA==.',
['Fæ']='Fælis:BAAANQAECgMIAwAAAA==.',
Ga='Gabiru:BAAANQAECgcIDQAAAA==.Galock:BAAANQAECgQIBwAAAA==.Galois:BAAANQAECgMIBQAAAA==.Gazzygos:BAABNQAECoEdAAIIAAkJKxzoBAAAAwAIAAkJKxzoBAAAAwAAAA==.',
Ge='Getdrunk:BAAANQADCgcIBwAAAA==.Gexxor:BAAANQAECgQIBAAAAA==.',
Gh='Ghouldanny:BAAANQAECgEIAQAAAA==.',
Gi='Gilith:BAAANQADCggICAAAAA==.',
Gl='Glassjaw:BAAANQAECgMIAwABNQAECgQICQABAAAAAA==.Glickswap:BAAANQAECgUIBQAAAA==.Glimmr:BAEANQAECgMIAwABNQAECgcIDQABAAAAAA==.',
Gn='Gniktar:BAAANQADCgcIBwAAAA==.',
Go='Goonslam:BAABNQAECoEZAAIQAAcJpyCxLACQAgAQAAcJpyCxLACQAgAAAA==.Goren:BAAANQAECgUICAABNQAECgkJHAAPAPoQAA==.Goretexx:BAAANQADCgEIAgAAAA==.Gorgrimskull:BAAANQADCggIHAAAAA==.',
Gr='Grandy:BAAANQADCgIIAgAAAA==.Grandydin:BAAANQADCgIIAgAAAA==.Grapple:BAAANQAECgYIDAAAAA==.Graveheart:BAAANQADCgEIAQAAAA==.Greathadin:BAAANQABCgQICAAAAA==.Grimnh:BAAANQADCgEIAgAAAA==.Grinchh:BAAANQAECgIIAgAAAA==.Grinnlock:BAAANQAECgcIEAAAAA==.Gristle:BAAANQADCggICAABNQAECgYIDgABAAAAAA==.Grïmm:BAAANQADCgcICwAAAA==.',
Gu='Guke:BAAANQADCgEIAQAAAA==.Gundee:BAAANQADCgEIAQAAAA==.',
Gy='Gymothee:BAAANQAECgQIBQAAAA==.',
Ha='Hachimi:BAAANQADCgQIBAAAAA==.Halima:BAAANQAECgYIDgAAAA==.Hallowyn:BAAANQADCgcICwAAAA==.Haraambe:BAAANQADCgUIBQABNQAECgQICQABAAAAAA==.Harandrood:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Harrothion:BAACNQAFFIEJAAIYAAUJJA8rAwCcAQAYAAUJJA8rAwCcAQA1AAQKgSEAAhgACQlAINsBAH4DABgACQlAINsBAH4DAAAA.Hautebussy:BAABNQAECoEgAAQKAAkJhyTKBgA/AwAKAAgJMCTKBgA/AwAJAAYJzh3eDAD/AQALAAEJ5iNVEwBlAAABNQAFFAQIBAABAAAAAA==.Havick:BAAANQADCgMIBAAAAA==.Hawkttwa:BAAANQADCgIIAgAAAA==.Hazuna:BAAANQAECgQIBAAAAA==.',
He='Heaton:BAABNQAECoEgAAMQAAkJ+iBVDgBWAwAQAAkJ+iBVDgBWAwAZAAIJUxwWGwCWAAAAAA==.Herfadin:BAAANQABCgQIBAAAAA==.Hewhohunts:BAAANQADCgYIEAAAAA==.Heävymetal:BAAANQADCgcICQAAAA==.',
Hi='Highmoo:BAAANQAECgEIAQAAAA==.',
Ho='Hodgemous:BAAANQADCgIIAgAAAA==.Hoetems:BAAANQADCggICAAAAA==.Holykrapoli:BAAANQADCgQICAAAAA==.Holypoca:BAAANQADCgcICAAAAA==.Hongkongcow:BAAANQAECgQICgAAAA==.Hornsofcream:BAAANQADCgMIAwAAAA==.Hotpantz:BAAANQADCggIDAAAAA==.Howlingberry:BAAANQADCgcICgAAAA==.',
Hu='Hubbabubble:BAAANQADCgQIBgAAAA==.Hubble:BAAANQAECgEIAQAAAA==.Huntlex:BAAANQAECgYICwAAAA==.Huntüdown:BAAANQADCggIEAAAAA==.',
Ia='Iamfugly:BAAANQADCgYIDQAAAA==.',
Ic='Icen:BAAANQAECgMIAwAAAA==.',
Ii='Iinjyapan:BAABNQAECoEmAAIGAAgJHyGZDAAIAwAGAAgJHyGZDAAIAwAAAA==.',
Ik='Ikelle:BAAANQADCgUIBQAAAA==.',
Il='Ileñdil:BAAANQADCggICAAAAA==.Illialadin:BAAANQAECgEIAQAAAA==.Illidragon:BAAANQADCgIIAgAAAA==.',
Im='Imfiredurp:BAABNQAECoEeAAICAAkJICNvCwCFAwACAAkJICNvCwCFAwAAAA==.',
In='Invite:BAAANQAECgEIAQAAAA==.',
Io='Iod:BAAANQAECgQICQABNQAECgcIGQAXAN4aAA==.',
Is='Ishibakudan:BAAANQADCgUIBQABNQADCggIFgABAAAAAA==.Ishinosenso:BAAANQADCggIFgAAAA==.',
It='Itshebum:BAAANQAECgYIEAAAAA==.',
Iz='Izukumidorya:BAAANQAECgEIAQAAAA==.',
['Ià']='Iànocto:BAAANQADCgcICAAAAA==.',
Ja='Jacrispy:BAAANQAECgQICQAAAA==.Jaxsmighty:BAAANQADCgcIFQAAAA==.',
Je='Jedikenobi:BAAANQAECgYIDgAAAA==.Jeraldo:BAAANQAECgUIBwAAAA==.',
Ji='Jibdorf:BAAANQADCgIIAgAAAA==.',
Jk='Jkilled:BAAANQAECgEIAQAAAA==.Jkstone:BAAANQAECgUIBQABNQAECgkJHAAVAB8YAA==.',
Jo='Joosyloosy:BAAANQAECgcIEQABNQAFFAUICAAQACMaAA==.Jov:BAAANQAECgUICAAAAA==.',
Js='Jstone:BAAANQAECgQIBwAAAA==.',
Ju='Jubbad:BAAANQAECgYIBgAAAA==.Judgecow:BAAANQAECgYIDgAAAA==.Juggo:BAAANQADCggIDgAAAA==.Jupiterxalli:BAAANQAECgQIBgABNQAECgkJGQATAJsgAA==.Justidius:BAAANQAECgIIAwAAAA==.Justjoan:BAAANQADCgIIAgAAAA==.Juuse:BAAANQADCggICAABNQABCgQIBAABAAAAAA==.',
Jv='Jvlbing:BAAANQADCggIDQAAAA==.',
Ka='Kabrxis:BAAANQAECgEIAQAAAA==.Kaelisa:BAAANQABCgIIAgAAAA==.Kalehl:BAAANQADCggIDgAAAA==.Karkashan:BAAANQADCgEIAQAAAA==.Kassiaa:BAAANQAECgEIAQAAAA==.Kaylabug:BAAANQADCgQIBAAAAA==.',
Ke='Keanuglaives:BAEANQAECgIIAgABNQAECgkJGgAXAC0TAA==.Kelibastus:BAAANQAECgYIDAAAAA==.Kendoh:BAAANQADCgYICQABNQAECgIIAgABAAAAAA==.Kendont:BAAANQADCgUIBQAAAA==.',
Kh='Kharmah:BAAANQADCgQIBAAAAA==.',
Ki='Killshat:BAAANQAECgUICAABNQAECgcIEAABAAAAAA==.Kirt:BAAANQADCgYICQAAAA==.Kissthismm:BAAANQADCgIIAgAAAA==.',
Kl='Kleiin:BAAANQADCgIIAgAAAA==.',
Ko='Kodoku:BAAANQAECgQICgAAAA==.Koraen:BAAANQAECgEIAQAAAA==.Kovalo:BAAANQADCgMIAwAAAA==.',
Kr='Krho:BAAANQAECggIEgAAAA==.Kringy:BAAANQADCgMIAwAAAA==.Krushnic:BAAANQADCgYIBgAAAA==.',
Ku='Kunalli:BAAANQADCggIEAAAAA==.Kurohìme:BAEANQAECgcIDQAAAA==.',
Kw='Kwynn:BAAANQADCgIIAgAAAA==.',
Ky='Kyrosh:BAAANQADCgcICwAAAA==.',
['Kö']='Könígs:BAABNQAECoEbAAMaAAkJ9iJ/AQCcAwAaAAkJ9iJ/AQCcAwAbAAMJGwkNDwCfAAAAAA==.',
La='Lacy:BAAANQADCgMIBAAAAA==.Lanadrius:BAAANQADCgYIBgAAAA==.Laralock:BAAANQADCgcICwAAAA==.Laramage:BAAANQADCgUIBQAAAA==.Larhon:BAABNQAECoEgAAINAAkJ0hpmCQDzAgANAAkJ0hpmCQDzAgAAAA==.Larhonsmage:BAAANQAECgMIAwABNQAECgkJIAANANIaAA==.',
Le='Lesserashim:BAAANQADCgYIBgABNQAECgkJIAAUABUhAA==.',
Li='Lickity:BAAANQADCgEIAQABNQADCgMIAwABAAAAAA==.Lightpal:BAAANQAECgYIBgAAAA==.Lildeadboy:BAAANQADCgIIAgABNQAECgQIBAABAAAAAA==.',
Lo='Lockeden:BAAANQADCggIEQAAAA==.Lockia:BAAANQAECgYIEAAAAA==.Lohah:BAAANQADCggIFAAAAA==.Lonron:BAAANQADCggIFAAAAA==.Lornir:BAAANQADCgQIBwAAAA==.Lorstan:BAAANQADCgUIBwAAAA==.Lounaa:BAAANQADCgEIAQAAAA==.',
Lu='Lunagoodlove:BAAANQADCgUIBQABNQAECgEIAgABAAAAAA==.Lunamort:BAAANQAECgEIAgAAAA==.Lutes:BAAANQAECgMIAwABNQAECgkJIAAcAOQkAA==.Lutesadactyl:BAAANQADCgYIBgABNQAECgkJIAAcAOQkAA==.Lutesectomy:BAABNQAECoEgAAIcAAkJ5CRwAgC7AwAcAAkJ5CRwAgC7AwAAAA==.Luuigii:BAAANQAECgIIAgAAAA==.',
Ly='Lyghtbryght:BAAANQADCggICAAAAA==.Lytta:BAABNQAECoETAAIPAAkJNhwODQC7AgAPAAkJNhwODQC7AgAAAA==.',
Ma='Macro:BAACNQAFFIEHAAIXAAYJqRX1AAAdAgAXAAYJqRX1AAAdAgA1AAQKgRoAAhcACQkIJqIBANgDABcACQkIJqIBANgDAAAA.Madflexin:BAAANQAECgIIAgABNQAECgkJHAAPAPoQAA==.Madkingog:BAAANQAECgQICQAAAA==.Madslock:BAAANQAECgEIAQAAAA==.Mageoffayt:BAAANQABCgIIAgAAAA==.Mageyoulook:BAAANQADCggIDgAAAA==.Magikmurder:BAAANQADCgYIBgAAAA==.Mahnu:BAAANQADCgQIBAAAAA==.Makinoa:BAAANQADCgYIBgAAAA==.Malebolgia:BAAANQADCggIGwAAAA==.Malodorous:BAAANQADCgIIAgAAAA==.Malralailea:BAAANQAECgQIDwAAAA==.Mamallhama:BAAANQADCgcIDQAAAA==.Manathorr:BAAANQADCgYIBgAAAA==.Mattygg:BAAANQADCggIFAAAAA==.Mazikëën:BAAANQADCgcICAABNQADCggICQABAAAAAA==.',
Mb='Mbappe:BAAANQADCgMIBAAAAA==.',
Mc='Mccuddles:BAAANQADCgUICAAAAA==.Mcspoopy:BAAANQADCgYIDQAAAA==.',
Me='Mechhunter:BAAANQAECgEIAQAAAA==.Melodý:BAEANQAECgYIEAABNQAECgcIDQABAAAAAA==.Melunara:BAAANQAECgEIAwAAAA==.',
Mi='Miqo:BAAANQAECgcIDwAAAA==.Missvanjie:BAABNQAECoEbAAIIAAkJeBlGBQD0AgAIAAkJeBlGBQD0AgAAAA==.',
Mo='Moonhalf:BAAANQADCgEIAQAAAA==.Mooskie:BAAANQAECgQIBAAAAA==.Mortifera:BAAANQADCgUIBQAAAA==.',
Mu='Muckfury:BAAANQAECgEIAQAAAA==.Mursz:BAABNQAECoEdAAMSAAkJGR7GFAD6AgASAAkJGR7GFAD6AgAGAAUJRAweXQA8AQAAAA==.',
My='Mybrand:BAAANQADCggICAAAAA==.Mycelia:BAAANQAECgQIBAAAAA==.',
['Më']='Mëphisto:BAAANQAECgMIBAAAAA==.',
Na='Nachtigall:BAAANQADCggIDQAAAA==.Nadintodd:BAAANQADCgYIBgAAAA==.Narigusmodx:BAAANQADCgEIAQAAAA==.Nastywill:BAAANQAECggIDgAAAA==.Natsù:BAAANQAECgUICwAAAA==.Nazghoule:BAAANQAECgYICwAAAA==.',
Ne='Neb:BAAANQADCgUIBQAAAA==.Nerdrange:BAAANQAECgUIBQAAAA==.Nessiecutie:BAAANQAECgEIAQAAAA==.Neverlucky:BAAANQADCgUIDQAAAA==.',
Ni='Nicorobin:BAAANQAECgYIDgAAAA==.Nikon:BAAANQAECgcIDQAAAA==.Nintuk:BAAANQAECgcIEgAAAA==.Nirazervis:BAAANQABCgMIAQAAAA==.',
No='Noagro:BAAANQAECgQIBwAAAA==.Nodam:BAAANQADCgYICgAAAA==.Nostalgia:BAAANQAECgQIBAAAAA==.Nostradam:BAAANQADCgcIDQAAAA==.',
Ny='Nysiss:BAAANQADCggIFwAAAA==.',
Oa='Oakenshields:BAAANQADCgYICQAAAA==.',
Og='Ogdead:BAAANQADCgYIBgAAAA==.',
Oh='Ohyafenway:BAAANQADCgEIAQAAAA==.',
Ol='Oldfart:BAAANQADCgMIBAAAAA==.',
Om='Omniheart:BAAANQADCgYICgAAAA==.Omnilach:BAAANQAECgQIBgAAAA==.',
On='Onionn:BAAANQADCggIDwAAAA==.',
Oo='Ookamigin:BAAANQADCggIEgAAAA==.Oomagain:BAAANQADCgYIBwAAAA==.Oopzmybad:BAAANQADCgUIDAAAAA==.',
Ou='Outtacontrol:BAAANQAECgUIDQAAAA==.',
Ov='Overpew:BAAANQAECgMIBAAAAA==.',
Pa='Pallyjones:BAAANQAECgQICgAAAA==.Pannduh:BAAANQADCgQIBAAAAA==.Panospatako:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.Panya:BAAANQAECgUICQAAAA==.',
Pe='Peepeeslam:BAAANQAECgcICwABNQAFFAQIBAABAAAAAA==.Pekyaugai:BAAANQAECgEIAQAAAA==.Pelukan:BAAANQADCgYIBgAAAA==.Pennyblink:BAAANQAECgYICgAAAA==.Peterosé:BAAANQAECgEIAQAAAA==.',
Ph='Phartbomb:BAAANQAECgIIAwAAAA==.Phatsy:BAAANQADCgYIBgAAAA==.Phoenixra:BAAANQADCgMIBwAAAA==.',
Pi='Picklebumps:BAAANQADCgIIAgAAAA==.Piker:BAAANQAECgUIBgAAAA==.',
Pl='Pleb:BAAANQAECgQIBgAAAA==.',
Po='Policeman:BAAANQADCggICAAAAA==.Popozhao:BAABNQAECoEpAAMFAAkJWCAYBwD7AgAFAAgJ0R8YBwD7AgAdAAgJ2ATnEwBzAQAAAA==.Portwine:BAAANQADCgEIAQAAAA==.Powerranger:BAAANQADCgYIBgAAAA==.',
Pr='Pragmata:BAAANQAECgEIAQAAAA==.Pryrxxe:BAAANQAECgYICwAAAA==.',
Ps='Psyler:BAAANQADCgMIAwAAAA==.',
Pu='Pubzero:BAAANQAECgIIAgAAAA==.Pumpkindh:BAAANQADCgUIBQAAAA==.Pumpkinjuice:BAAANQAECgEIAgABNQADCgUIBQABAAAAAA==.Punchman:BAAANQAECgcIBwAAAA==.Puppetcake:BAAANQADCgEIAQAAAA==.',
Qu='Quackiechan:BAABNQAECoEaAAMdAAgJNhivCgA8AgAdAAgJNhivCgA8AgAFAAIJfAHZOQA4AAAAAA==.Quasibeast:BAAANQADCgIIAgAAAA==.',
Ra='Raer:BAAANQAECgUICgAAAA==.Ragabowa:BAAANQAECgcIEgAAAA==.Raikirii:BAABNQAECoEaAAICAAkJJhrcKQDqAgACAAkJJhrcKQDqAgAAAA==.Ravaxys:BAAANQADCgQIBAAAAA==.Rayzac:BAAANQAECgUICgAAAA==.Raznar:BAAANQABCgIIAgAAAA==.',
Re='Redfacedemon:BAAANQADCgYIBgAAAA==.Renwall:BAAANQADCggIGgAAAA==.Revan:BAAANQADCgcIBwAAAA==.',
Ri='Rickyli:BAAANQADCgMIAwAAAA==.Rictusempra:BAAANQAECggIAQAAAA==.Rilwarp:BAAANQADCgYICgAAAA==.',
Ro='Rokash:BAAANQAECgUICAABNQAECgkJHAAPAPoQAA==.Rozuveos:BAAANQADCgYIDwAAAA==.',
Ru='Rumplez:BAAANQAECggIBQAAAA==.',
Sa='Sabrano:BAAANQADCgQIBwAAAA==.Saelzington:BAACNQAFFIEHAAILAAUJ6BMTAADhAQALAAUJ6BMTAADhAQA1AAQKgRsAAgsACQkaJBwAAMcDAAsACQkaJBwAAMcDAAAA.Saepink:BAAANQAECgIIAgABNQAFFAUIBwALAOgTAA==.Sakurajima:BAAANQAECgUICQAAAA==.Samuraibicep:BAAANQADCgYIDwAAAA==.Sariiane:BAAANQAECgUICQAAAA==.',
Sc='Scaledaddy:BAAANQADCggIGQAAAA==.Scartrist:BAAANQADCgcIGAAAAA==.Scrotimus:BAAANQADCggIGQAAAA==.Scylent:BAAANQADCgUIBgAAAA==.',
Se='Seasontwodk:BAAANQADCgQIDAAAAA==.Selannil:BAAANQADCgEIAQAAAA==.Seras:BAAANQADCgUIBQAAAA==.Serathia:BAAANQADCgQIBAAAAA==.',
Sh='Shadowbutt:BAAANQAECgcIDQAAAA==.Shadowdeadma:BAAANQAECgQIBAAAAA==.Shadowtaco:BAAANQADCgcIBwAAAA==.Shammyhagar:BAAANQABCgYIDAABNQABCgIIBAABAAAAAA==.Shanaynay:BAAANQADCgYIBgAAAA==.Shankfoo:BAAANQADCgUIBQAAAA==.Shankpal:BAAANQADCgUIBQAAAA==.Shimmew:BAABNQAECoEgAAIUAAkJFSEMBwAjAwAUAAkJFSEMBwAjAwAAAA==.Shimmurt:BAAANQADCggICAABNQAECgkJIAAUABUhAA==.Shinhati:BAAANQAECgcICwAAAA==.Shwinkles:BAAANQAECgIIAgAAAA==.',
Si='Sicariox:BAAANQAECgQIDwAAAA==.Simkhan:BAAANQADCgcIBwAAAA==.',
Sk='Skarlett:BAAANQADCggICAAAAA==.Skeets:BAAANQADCgYIFgAAAA==.Skizzixx:BAAANQADCgcIDwAAAA==.Skullie:BAAANQABCgYIBgAAAA==.',
Sl='Slapshop:BAAANQAECgYIDAAAAA==.Slice:BAAANQAECgQIBgAAAA==.Slippyfistt:BAAANQAECgEIAQAAAA==.Slowansteady:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.',
Sm='Smashe:BAAANQABCgQIBQAAAA==.Smashleigh:BAAANQADCgUIBQAAAA==.Smiteful:BAAANQADCgYIBgAAAA==.Smittysen:BAAANQADCgYIBgAAAA==.Smoxx:BAAANQAECgYIDQAAAA==.Smörc:BAAANQADCgcIBwAAAA==.',
Sn='Sneeg:BAAANQAECgQIBgABNQAECggIFQATACkfAA==.',
So='Sobchak:BAABNQAECoEcAAMPAAkJ+hCYEwBXAgAPAAkJpQ+YEwBXAgAVAAgJaws6HgDlAQAAAA==.Sober:BAABNQAECoEYAAIcAAgJ0R/ADgDpAgAcAAgJ0R/ADgDpAgAAAA==.Softfleur:BAAANQAECgIIAgAAAA==.Softrminator:BAAANQADCgQICAAAAA==.Sokz:BAAANQAECgYICgAAAA==.Sorago:BAAANQADCggICgAAAA==.Soraka:BAAANQAECgEIAQABNQAECggIJgAGAB8hAA==.Soxxs:BAAANQAECgEIAQAAAA==.',
Sp='Sparator:BAAANQADCgQIBAABNQAECgYIEAABAAAAAA==.Spartystrasz:BAAANQAECgYIEAAAAA==.',
St='Stalladin:BAAANQADCgcIBwAAAA==.Starck:BAAANQADCggIDAAAAA==.Starflight:BAAANQAECgEIAQAAAA==.Stonepaw:BAAANQADCgUIDwAAAA==.Stormsound:BAAANQADCgYICgAAAA==.',
Su='Sugoi:BAAANQAECgUIDAAAAA==.Sultan:BAAANQADCgMIAwAAAA==.Surtvyr:BAEANQAECgEIAQABNQAECgkJGgAXAC0TAA==.',
Sw='Swagmonsta:BAAANQADCggICAAAAA==.Sweetdemonic:BAAANQADCgYICAAAAA==.Sweettoothz:BAAANQAECgYICwAAAA==.Swiddles:BAABNQAECoEVAAQTAAgJKR8LLABMAgATAAcJJyILLABMAgAeAAQJ1h6zBQBkAQAUAAIJ/wmAPQB9AAAAAA==.',
Sy='Syllee:BAAANQADCgMIAwAAAA==.',
Ta='Talan:BAAANQADCgMIBgAAAA==.Talara:BAAANQAECgEIAQAAAA==.Talsaiir:BAAANQADCgYIBgAAAA==.Talyyn:BAAANQADCgYICAAAAA==.Tater:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Tatorshot:BAAANQAECgEIAQAAAA==.',
Te='Tekmatek:BAAANQAECgcIDQAAAA==.Terpenes:BAAANQAECgcIEgABNQADCggIDAABAAAAAA==.',
Th='Thelust:BAAANQAECgEIAQABNQAECgMIBAABAAAAAA==.Thienduongv:BAAANQAECgQIBAAAAA==.Thorhin:BAAANQAECgIIAgAAAA==.Thébígtúñá:BAAANQAECgIIAgAAAA==.',
Ti='Ticklemytots:BAAANQAECgcIEAAAAA==.Tiltvoke:BAAANQAECgQIBAABNQAECggIBgABAAAAAA==.Tirynis:BAEBNQAECoEgAAISAAkJjyXbAgDLAwASAAkJjyXbAgDLAwAAAA==.',
Tl='Tlow:BAAANQAECgYIEAAAAA==.',
Tm='Tmsmdfcrcls:BAAANQAECgYICwAAAA==.',
To='Toelp:BAAANQAECgUICAAAAA==.Tomacakes:BAAANQADCgIIAgAAAA==.Toothnnailz:BAAANQADCggICAAAAA==.Topochica:BAAANQAECgEIAQAAAA==.Totemtankn:BAAANQAECgYIDAAAAA==.Toxic:BAAANQADCgMIAwABNQAECgMIBAABAAAAAA==.',
Tr='Trancemusic:BAAANQADCggICwAAAA==.Trashdk:BAAANQADCggICAABNQAECgUICQABAAAAAA==.Treeboi:BAAANQADCgUIBQAAAA==.Triibs:BAAANQAECgEIAQAAAA==.',
Tu='Tulashir:BAAANQABCgIIBAAAAA==.Turayne:BAAANQAECgEIAQAAAA==.Turbonex:BAAANQADCgIIAgAAAA==.',
Ty='Tyerial:BAAANQAECgIIAgAAAA==.Tyrear:BAAANQADCgQIBAAAAA==.Tyronbigadin:BAAANQAECgcIEgAAAA==.',
['Té']='Témpèst:BAAANQAECgUIDgABNQAECgcIEAABAAAAAA==.',
['Tõ']='Tõby:BAAANQAECgYICgAAAA==.',
Ul='Ultis:BAAANQADCgQIBAAAAA==.',
Va='Vaelphar:BAAANQADCggICQAAAA==.Valkÿrie:BAAANQAECgUICgAAAA==.Vandral:BAAANQAECgQICQAAAA==.Varella:BAAANQAECgYICAAAAA==.Varnor:BAAANQADCgUICQAAAA==.',
Ve='Veinless:BAAANQAECgUICgAAAA==.Velanné:BAAANQAECgcIDwABNQADCggICwABAAAAAA==.Venusx:BAAANQAECgQIBAABNQAECgkJGQATAJsgAA==.Vethemir:BAAANQADCggIEQABNQADCgYIBwABAAAAAA==.Vexmachína:BAAANQAECgQIBwAAAA==.Vextheria:BAAANQAECgYICQAAAA==.Veyg:BAAANQAECgcIEwAAAA==.',
Vi='Viletrance:BAAANQADCggIHwAAAA==.Visenyatarg:BAAANQADCgYIEAAAAA==.',
Vl='Vladikan:BAAANQADCgQIBAAAAA==.',
Vo='Vondo:BAAANQADCgcIBwABNQAECgkJHAAVAB8YAA==.Vorunaa:BAAANQAECgUICgABNQAECgUICwABAAAAAA==.Vorztrix:BAABNQAECoEZAAITAAkJmyBHDAAcAwATAAkJmyBHDAAcAwAAAA==.',
Vy='Vythras:BAAANQAECgYIDAAAAA==.',
['Vä']='Välkyrie:BAAANQADCggIDAAAAA==.',
['Vå']='Vålkyrie:BAAANQAECgYIEAAAAA==.',
['Vë']='Vëlzhen:BAAANQADCggICgABNQAECggIEwABAAAAAA==.',
Wa='Wanacupcake:BAAANQADCgMIAwAAAA==.Wandjovi:BAAANQAECgEIAQAAAA==.Warenn:BAAANQAECgEIAQAAAA==.Warstall:BAABNQAECoEXAAIQAAgJsBlHNABqAgAQAAgJsBlHNABqAgAAAA==.Warzie:BAAANQAECgMIAwAAAA==.Waterincone:BAAANQAECgQICAAAAA==.',
We='Weakswings:BAAANQABCgQICAAAAA==.Wercs:BAAANQADCgUIBgAAAA==.Werrcs:BAAANQADCgMIAwAAAA==.Wezethejuice:BAAANQADCgYIEAAAAA==.',
Wh='Whitebison:BAAANQADCgcICgAAAA==.Wholelotaazz:BAAANQADCgcIBAAAAA==.',
Wi='Wiffartist:BAAANQAECgEIAQAAAA==.Wildpeppoo:BAAANQADCgYIBgAAAA==.Willhsiao:BAAANQADCgYIDQAAAA==.',
Wo='Wogawogawoga:BAAANQADCgcIDQAAAA==.Worak:BAAANQAECgEIAQAAAA==.',
Wy='Wyatta:BAAANQADCgUIBQAAAA==.Wyrmbane:BAAANQADCgIIAgAAAA==.',
['Wì']='Wìsdom:BAAANQAECgUICQAAAA==.',
['Wî']='Wînter:BAAANQADCgcIEAAAAA==.',
Xa='Xaltwer:BAAANQAECgEIAQAAAA==.Xasz:BAABNQAECoEgAAMMAAkJDia+AADTAwAMAAkJDia+AADTAwAXAAUJwyD6OgDHAQAAAA==.Xaszageth:BAAANQADCgcIDQABNQAECgkJIAAMAA4mAA==.',
Xc='Xcrush:BAAANQAECgYICQABNQAECgYIDQABAAAAAA==.',
Xd='Xdata:BAAANQAECgYIEAAAAA==.Xdatadh:BAAANQADCgUIBQAAAA==.',
Xe='Xerias:BAAANQAECgYIDgAAAA==.',
Xi='Xieno:BAAANQADCggICAAAAA==.',
Xo='Xovyt:BAAANQAFFAQIBAAAAA==.',
Ya='Yaana:BAAANQADCggIGQAAAA==.Yaney:BAAANQADCgYIDgAAAA==.',
Yu='Yunihara:BAAANQAECggIAwAAAA==.',
Za='Zalroth:BAAANQAECgIIAgAAAA==.Zama:BAAANQADCgIIAgAAAA==.Zaranoria:BAAANQADCgQIBAAAAA==.Zarzlek:BAAANQAECgYIEAAAAA==.',
Ze='Zenthyk:BAAANQAECgcIEQAAAA==.Zephahniah:BAAANQADCgQICgAAAA==.Zevyn:BAAANQADCgEIAQAAAA==.',
Zh='Zheela:BAAANQADCgYIEAAAAA==.',
Zi='Zimbala:BAAANQAECgMIBAAAAA==.',
Zo='Zomb:BAAANQAECgUICwAAAA==.',
Zp='Zpants:BAAANQADCgUIEAAAAA==.',
Zu='Zulna:BAAANQAECgUIBwAAAA==.Zulrippa:BAAANQADCgMIAwAAAA==.',
Zy='Zyron:BAAANQADCgUIBwAAAA==.',
['Äm']='Ämon:BAAANQAECgMIAwAAAA==.',
['Ël']='Ëlyndal:BAAANQAECggIEwAAAA==.',
['Ëñ']='Ëñÿõ:BAAANQAECgcIEwAAAA==.',
['ßr']='ßreezy:BAAANQAECgQIBwAAAA==.',
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
