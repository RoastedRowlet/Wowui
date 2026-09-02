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

local lookup = {'Unknown-Unknown','DeathKnight-Blood','Evoker-Augmentation','Evoker-Devastation','Shaman-Restoration','Paladin-Retribution',}
local provider = {region='US',realm='Destromath',name='US',type='weekly',zone=53,date='2026-09-01',data={Ac='Achillis:BAAANQADCgIIAgAAAA==.',
Ad='Adapip:BAAANQAECgIIAgAAAA==.Adeille:BAAANQAECgEIAQAAAA==.Adrahmalik:BAAANQADCgYIBgAAAA==.',
Ae='Aeddann:BAAANQADCggICAAAAA==.Aegiskline:BAAANQADCgEIAQAAAA==.Aerystargaer:BAAANQADCgYIEQAAAA==.',
Ag='Agnos:BAAANQAECgQIBgAAAA==.',
Ah='Ahiri:BAAANQABCgQIBgABNQAECgYIBgABAAAAAA==.',
Ak='Akstar:BAAANQAECgYICgAAAA==.',
Al='Alaispere:BAAANQADCgUIBwAAAA==.Alalletsa:BAAANQAECgMIBQAAAA==.Alanm:BAAANQAECgQIBAAAAA==.Alf:BAAANQAECgQIBAAAAA==.Allenwrench:BAAANQABCgEIAQAAAA==.Aloezilla:BAAANQADCggICQAAAA==.Alouna:BAAANQADCgYICgAAAA==.Alureae:BAAANQADCggIDwAAAA==.',
An='Anaak:BAAANQAECgQIBQAAAA==.Anacooties:BAABNQAECoEZAAICAAgJahYeCwBFAgACAAgJahYeCwBFAgAAAA==.Angeliq:BAAANQADCgYICAAAAA==.Anillusíon:BAAANQADCgYIBgABNQADCggIDwABAAAAAA==.',
Ar='Arathandris:BAAANQADCgQIBAAAAA==.Artivicious:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.',
As='Ashalzith:BAAANQADCgQIBAAAAA==.Astegous:BAAANQADCgQIBAAAAA==.Astraldaddy:BAAANQADCgQIBAAAAA==.',
At='Athalandra:BAAANQAECgEIAQAAAA==.Athandor:BAAANQAECgEIAQAAAA==.Atmagos:BAAANQADCgMIAwAAAA==.',
Au='Aummgg:BAAANQADCgYICgAAAA==.Aurélius:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.',
Az='Azrei:BAAANQADCgYICAAAAA==.',
Ba='Baalhamoon:BAAANQAECgQIBAAAAA==.Baangdog:BAEANQAECgQIBAAAAA==.Bacsilog:BAAANQAECgQICQAAAA==.Bahamût:BAAANQAECgMIAwAAAA==.Baka:BAAANQADCgYIBgAAAA==.Balrong:BAAANQADCgEIAQAAAA==.Baobunns:BAAANQABCgQIBgABNQAECgQICQABAAAAAA==.Barackoshama:BAAANQADCgcIBwAAAA==.Barrac:BAAANQADCgQIBgAAAA==.Basland:BAAANQADCgYIBgAAAA==.Bastanninn:BAAANQAECgQIBgAAAA==.Battlebéast:BAAANQAECgQIBQAAAA==.',
Be='Belariana:BAAANQADCgYIBgAAAA==.Belfnholy:BAAANQADCgQIBAAAAA==.Beo:BAAANQADCgYICwAAAA==.Bezerk:BAAANQADCgIIAgAAAA==.',
Bi='Bigkeystone:BAAANQADCgYICgAAAA==.',
Bl='Blowkissbuny:BAAANQADCgUIBQAAAA==.',
Bo='Bolthirvoker:BAABNQAECoEYAAMDAAcJeRCFAgCqAQADAAcJeRCFAgCqAQAEAAIJlwggFgBjAAAAAA==.Bonesnapper:BAAANQADCgYICwAAAA==.Boochie:BAAANQADCggICAAAAA==.Boomrmnieech:BAAANQADCgEIAQAAAA==.',
Br='Brasidas:BAAANQADCgYICAAAAA==.Braxy:BAAANQADCgEIAQAAAA==.Brojan:BAAANQADCgEIAQAAAA==.Brokeni:BAAANQAECgIIAgAAAA==.Brokenn:BAAANQADCgUIBQAAAA==.Brontides:BAAANQAECgUICAAAAA==.',
Bu='Buffknight:BAAANQADCgUICQABNQADCggICQABAAAAAA==.Bulldin:BAAANQADCgQIBAAAAA==.Bullpup:BAABNQAECoEYAAIFAAcJOQ7wGQCtAQAFAAcJOQ7wGQCtAQAAAA==.Burrett:BAAANQADCggIBgAAAA==.Busschlight:BAAANQADCgUIBQAAAA==.',
Bw='Bweezy:BAAANQADCgUICwAAAA==.',
Ca='Calithil:BAAANQADCggICAAAAA==.Callea:BAAANQAECgIIBAAAAA==.Camellia:BAAANQAECgIIAgAAAA==.',
Ce='Cenna:BAAANQAECgUICAAAAA==.',
Ch='Chahilo:BAAANQADCgMIAwAAAA==.Chaostracker:BAAANQADCgUIBgAAAA==.Cheesedragon:BAAANQADCgYIBgAAAA==.Chikpi:BAAANQADCgcIDAAAAA==.Chipchops:BAAANQADCggIFQAAAA==.Chompyreaper:BAAANQAECgMIBAAAAA==.Choonmami:BAAANQADCgcIDQAAAA==.Chugbug:BAAANQAECgcIDQAAAA==.Chuuhai:BAAANQADCgQIBQAAAA==.',
Ci='Cigs:BAAANQADCgIIAgAAAA==.Citori:BAAANQADCgYICAAAAA==.',
Cl='Cloudburst:BAAANQADCgcIBwAAAA==.',
Co='Corpustotem:BAAANQADCgcICgAAAA==.Cowbizarre:BAAANQADCgUIBQAAAA==.',
Cr='Crotchchop:BAAANQADCgIIAgABNQADCggIDgABAAAAAA==.Crushadin:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Crushlock:BAAANQAECgIIAgAAAA==.',
Cu='Cuttymofukuh:BAAANQAECgYICAAAAA==.',
Cy='Cybelis:BAAANQAECgEIAQAAAA==.Cyclonespam:BAAANQAECgcIDAAAAA==.',
Da='Daemonicus:BAAANQABCgQIBgAAAA==.Damiansdabom:BAAANQADCgYIBwABNQADCgYICQABAAAAAA==.Dangnabbit:BAAANQADCgIIAgAAAA==.Danicoldruna:BAABNQAECoE8AAIGAAkJBScDAAArBAAGAAkJBScDAAArBAAAAA==.Daniellol:BAAANQAECgMIAwAAAA==.Darkcoffee:BAAANQAECgMIAwAAAA==.',
De='Deadfrost:BAAANQADCgMIAwAAAA==.Deadliftz:BAAANQADCgMIAwAAAA==.Deadwolv:BAAANQAECgQIBAAAAA==.Deathtreader:BAAANQADCgYICgAAAA==.Decoy:BAAANQADCgYIBgABNQAECgcIDAABAAAAAA==.Deepdh:BAAANQABCgMIAwAAAA==.Deepfathom:BAAANQAECgMIAwAAAA==.Denecon:BAAANQADCgUIBQAAAA==.Derrusk:BAAANQAECgcIDAAAAA==.Derusk:BAAANQADCgYICQAAAA==.',
Dh='Dhstone:BAAANQAECgcIDAAAAA==.',
Di='Dieten:BAAANQAECgYIBwAAAA==.Diploid:BAAANQADCggICAAAAA==.Discgrace:BAAANQAECgIIAgAAAA==.Dividoo:BAAANQAECgQICAAAAA==.',
Dj='Djankula:BAAANQADCggIDwAAAA==.',
Dl='Dliqnt:BAAANQAECgEIAQAAAA==.',
Do='Doclove:BAAANQAECgMIAwAAAA==.Dollass:BAAANQADCgEIAQAAAA==.Dominique:BAAANQADCgQIBAAAAA==.Doorah:BAAANQADCgYICAAAAA==.Doppleker:BAAANQAECgIIAgAAAA==.',
Dr='Draconectar:BAAANQADCggIDAAAAA==.Dragoncecil:BAAANQAECgEIAQAAAA==.Drakkar:BAEANQAECggIDQAAAA==.Drelle:BAAANQADCgUIBQAAAA==.Droll:BAAANQADCgYICwAAAA==.Druidzie:BAAANQADCgQIBAAAAA==.',
Du='Dudemanguy:BAAANQADCgIIAwAAAA==.Dungflinger:BAAANQADCgQIBAABNQADCggIDwABAAAAAA==.Dunston:BAAANQADCgIIAgAAAA==.Durgash:BAAANQADCgUIBQAAAA==.',
Ea='Earthengrex:BAAANQADCgEIAQAAAA==.Easyheal:BAAANQADCgMIAwAAAA==.Easylover:BAAANQAECgYICgAAAA==.',
Ee='Eetwontflush:BAAANQADCgUIBQAAAA==.',
Eh='Ehprilrayn:BAAANQADCggICAAAAA==.',
El='Elanderera:BAAANQADCgYICgAAAA==.Elphaba:BAAANQADCgYICQAAAA==.',
Ep='Ephemeral:BAAANQADCgYIBgAAAA==.',
Er='Eriaelyn:BAAANQADCgcICgAAAA==.',
Fa='Facesedict:BAAANQAECgIIAgAAAA==.Fargiland:BAAANQADCgMIAwAAAA==.',
Fe='Ferocitas:BAAANQAECgQIBAAAAA==.',
Fl='Flinn:BAAANQAECgMIBgAAAA==.Floe:BAAANQADCgEIAQAAAA==.',
Fo='Fostermatt:BAAANQADCgYICQAAAA==.Fowhammy:BAAANQAECgEIAQAAAA==.',
Fr='Frest:BAAANQADCggIEAAAAA==.Frostedflake:BAAANQADCgQIBgABNQAECgIIAgABAAAAAA==.Frostydurp:BAAANQAECgcICwAAAA==.',
Fu='Fumblepull:BAAANQADCgIIAgAAAA==.',
['Fæ']='Fælis:BAAANQADCgYIBgAAAA==.',
Ga='Gabiru:BAAANQAECgQIBQAAAA==.Galock:BAAANQADCggIDgAAAA==.Galois:BAAANQAECgMIBQAAAA==.Gazzygos:BAAANQAECgcICwAAAA==.',
Ge='Gexxor:BAAANQADCgcIDQAAAA==.',
Gl='Glickswap:BAAANQADCgUIBgAAAA==.Glimmr:BAEANQADCgYIDgABNQAECgQIBQABAAAAAA==.Glipbobotank:BAAANQAFFAMIAwAAAA==.',
Go='Goonslam:BAAANQAECgMIBQAAAA==.Goren:BAAANQADCgYIBgABNQAECgYICAABAAAAAA==.Gorgrimskull:BAAANQADCgcIDAAAAA==.',
Gr='Grandy:BAAANQADCgIIAgAAAA==.Grandydin:BAAANQADCgIIAgAAAA==.Grapple:BAAANQAECgIIAgAAAA==.Graveheart:BAAANQADCgEIAQAAAA==.Grinchh:BAAANQAECgIIAgAAAA==.Grinnlock:BAAANQAECgIIAgAAAA==.Grïmm:BAAANQADCgUIBQAAAA==.',
Gu='Gundee:BAAANQADCgEIAQAAAA==.',
Gy='Gymothee:BAAANQADCggIDAAAAA==.',
Ha='Hachimi:BAAANQADCgQIBAAAAA==.Halima:BAAANQAECgMIAwAAAA==.Hallowyn:BAAANQADCgQIBAAAAA==.Haraambe:BAAANQADCgUIBQABNQADCgYIDAABAAAAAA==.Harrothion:BAAANQAECgcICQAAAA==.Hautebussy:BAAANQAECgcIDAAAAA==.Havick:BAAANQADCgMIBAAAAA==.Hawkttwa:BAAANQADCgIIAgAAAA==.',
He='Heaton:BAAANQAECgcIDAAAAA==.Herfadin:BAAANQABCgQIBAAAAA==.Hewhohunts:BAAANQADCgQIBgAAAA==.Heävymetal:BAAANQADCgcICQAAAA==.',
Hi='Highmoo:BAAANQADCgMIBAAAAA==.',
Ho='Hodgemous:BAAANQADCgIIAgAAAA==.Hoetems:BAAANQADCggICAAAAA==.Holykrapoli:BAAANQADCgQIBAAAAA==.Hongkongcow:BAAANQAECgIIAwAAAA==.Hornsofcream:BAAANQADCgMIAwAAAA==.Hotpantz:BAAANQADCgYICgAAAA==.Howlingberry:BAAANQADCgMIAwAAAA==.',
Hu='Hubbabubble:BAAANQADCgQIBgAAAA==.Hubble:BAAANQAECgEIAQAAAA==.Huntlex:BAAANQADCggIDAAAAA==.',
Ic='Icen:BAAANQADCggIEAAAAA==.',
Ii='Iinjyapan:BAAANQAECgQICQAAAA==.',
Il='Ileñdil:BAAANQADCggICAAAAA==.Illialadin:BAAANQADCgYICwAAAA==.',
In='Invite:BAAANQADCggICAAAAA==.',
Io='Iod:BAAANQAECgIIAgABNQAECgUICQABAAAAAA==.',
Is='Ishibakudan:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.Ishinosenso:BAAANQADCgYIBgAAAA==.',
It='Itshebum:BAAANQAECgQIBAAAAA==.',
Iz='Izukumidorya:BAAANQADCgUICAAAAA==.',
Ja='Jacrispy:BAAANQADCgYIDAAAAA==.Jaxsmighty:BAAANQADCgYICQAAAA==.',
Je='Jedikenobi:BAAANQAECgMIAwAAAA==.Jeraldo:BAAANQADCggIEAAAAA==.',
Ji='Jibdorf:BAAANQADCgIIAgAAAA==.',
Jo='Joosyloosy:BAAANQAECgYICAABNQAFFAEIAQABAAAAAA==.Jov:BAAANQADCggIDgAAAA==.',
Js='Jstone:BAAANQAECgMIAwAAAA==.',
Ju='Judgecow:BAAANQAECgMIAwAAAA==.Juggo:BAAANQADCgYIBgAAAA==.Jupiterxalli:BAAANQADCgEIAQABNQAECgYIBgABAAAAAA==.Justidius:BAAANQADCgYICgAAAA==.Justjoan:BAAANQADCgIIAgAAAA==.',
Jv='Jvlbing:BAAANQADCgQIBQAAAA==.',
Ka='Kabrxis:BAAANQADCgUIBQAAAA==.Kalehl:BAAANQADCgEIAQAAAA==.Kassiaa:BAAANQADCgcIBwAAAA==.Kaylabug:BAAANQADCgQIBAAAAA==.',
Ke='Keanuglaives:BAEANQAECgEIAQABNQAECggIDQABAAAAAA==.Kelibastus:BAAANQAECgIIAgAAAA==.Kendoh:BAAANQADCgYIBgAAAA==.',
Ki='Killshat:BAAANQADCggICAABNQAECgMIBQABAAAAAA==.Kirt:BAAANQADCgQIAQAAAA==.Kissthismm:BAAANQADCgIIAgAAAA==.',
Ko='Kodoku:BAAANQAECgQIBQAAAA==.',
Kr='Krho:BAAANQAECgIIAwAAAA==.Kringy:BAAANQADCgIIAgAAAA==.Krushnic:BAAANQADCgYIBgAAAA==.',
Ku='Kurohìme:BAEANQAECgQIBQAAAA==.',
['Kö']='Könígs:BAAANQAECgUIBwAAAA==.',
La='Lacy:BAAANQADCgEIAQAAAA==.Lanadrius:BAAANQABCgIIAgAAAA==.Laralock:BAAANQADCgcIBwAAAA==.Laramage:BAAANQADCgUIBQAAAA==.Larhon:BAAANQAECgYIBgAAAA==.Larhonsmage:BAAANQAECgMIAwABNQAECgYIBgABAAAAAA==.',
Le='Leafeeh:BAAANQABCgQIBQAAAA==.Lesserashim:BAAANQADCgYIBgABNQAECgcIDAABAAAAAA==.',
Lo='Lockeden:BAAANQADCgUICQAAAA==.Lockia:BAAANQAECgYIBgAAAA==.Lohah:BAAANQADCgYIDAAAAA==.Lonron:BAAANQADCgcIDQAAAA==.Lornir:BAAANQADCgQIBwAAAA==.',
Lu='Lunagoodlove:BAAANQABCgMIAwABNQADCgMIBAABAAAAAA==.Lunamort:BAAANQADCgMIBAAAAA==.Lutes:BAAANQADCggICAABNQAECgcIDAABAAAAAA==.Lutesadactyl:BAAANQADCgYIBgABNQAECgcIDAABAAAAAA==.Lutesectomy:BAAANQAECgcIDAAAAA==.Luuigii:BAAANQADCgQIBAABNQADCgYICQABAAAAAA==.',
Ly='Lyghtbryght:BAAANQADCggICAAAAA==.Lyrath:BAAANQADCgYICQAAAA==.Lytta:BAAANQAECgUICAAAAA==.',
Ma='Macro:BAAANQAFFAQIBAAAAA==.Madkingog:BAAANQAECgQIBAAAAA==.Mageoffayt:BAAANQABCgIIAgAAAA==.Mageyoulook:BAAANQADCggIDgAAAA==.Malebolgia:BAAANQADCggIDgAAAA==.Malralailea:BAAANQAECgMIAwAAAA==.Mamallhama:BAAANQADCgYIBgAAAA==.Mattygg:BAAANQADCgcIBwAAAA==.Mazikëën:BAAANQADCgQIBAAAAA==.',
Mb='Mbappe:BAAANQADCgMIBAAAAA==.',
Mc='Mccuddles:BAAANQADCgQIBAAAAA==.Mcspoopy:BAAANQADCgYIDAAAAA==.',
Me='Mechhunter:BAAANQADCgMIAgAAAA==.Melodý:BAEANQAECgQIBAABNQAECgQIBQABAAAAAA==.Melunara:BAAANQAECgEIAQAAAA==.Metinks:BAAANQAECgIIAgAAAA==.',
Mi='Miqo:BAAANQAECgUIBAAAAA==.Missvanjie:BAAANQAECgYIDAAAAA==.',
Mo='Mortifera:BAAANQADCgUIBQAAAA==.',
Mu='Muckfury:BAAANQADCgcIDAAAAA==.Mursz:BAAANQAECgYICQAAAA==.',
My='Mybrand:BAAANQADCggICAAAAA==.',
['Më']='Mëphisto:BAAANQAECgEIAQAAAA==.',
Na='Nachtigall:BAAANQADCgYIBgAAAA==.Nadintodd:BAAANQADCgYIBgAAAA==.Narigusmodx:BAAANQADCgEIAQAAAA==.Natsù:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.Nazghoule:BAAANQAECgQIBQAAAA==.',
Ne='Neb:BAAANQADCgUIBQAAAA==.Nerdrange:BAAANQADCggIDwAAAA==.Nessiecutie:BAAANQAECgEIAQAAAA==.Neverlucky:BAAANQADCgUICQAAAA==.',
Ni='Nicorobin:BAAANQAECgIIAwAAAA==.Nikon:BAAANQAECgQIBAAAAA==.Nintuk:BAAANQAECgcICgAAAA==.',
No='Noagro:BAAANQAECgEIAQAAAA==.Nodam:BAAANQADCgQIBAAAAA==.Nostradam:BAAANQADCgYICQAAAA==.',
Ny='Nysiss:BAAANQADCgYICAAAAA==.',
Ol='Oldfart:BAAANQADCgIIAgAAAA==.',
Om='Omniheart:BAAANQADCgQIBAAAAA==.Omnilach:BAAANQADCgMIAwAAAA==.',
On='Onionn:BAAANQADCgYICgAAAA==.',
Oo='Ookamigin:BAAANQADCgUIBAAAAA==.Oomagain:BAAANQADCgYIBwAAAA==.Oopzmybad:BAAANQADCgUICAAAAA==.',
Ou='Outtacontrol:BAAANQAECgQIBAAAAA==.',
Ov='Overpew:BAAANQADCgUIBgAAAA==.',
Pa='Pallyjones:BAAANQAECgEIAQAAAA==.Pannduh:BAAANQADCgQIBAAAAA==.Panospatako:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.Panya:BAAANQAECgQIBAAAAA==.',
Pe='Peepeeslam:BAAANQAECgEIAQABNQAECggIDgABAAAAAA==.Pelukan:BAAANQADCgYIBgAAAA==.Pennyblink:BAAANQAECgIIAgAAAA==.Peterosé:BAAANQADCgYIBgAAAA==.',
Ph='Phartbomb:BAAANQAECgIIAgAAAA==.Phoenixra:BAAANQADCgMIBwAAAA==.',
Pi='Piker:BAAANQADCgcIDAAAAA==.',
Po='Popozhao:BAAANQAECgYIDgAAAA==.Portwine:BAAANQADCgEIAQAAAA==.',
Pr='Pragmata:BAAANQADCgMIBAAAAA==.Pryrxxe:BAAANQAECgEIAQAAAA==.',
Ps='Psyler:BAAANQADCgMIAwAAAA==.',
Pu='Pubzero:BAAANQADCggIDgAAAA==.Pumpkinjuice:BAAANQADCgYIBgAAAA==.Puppetcake:BAAANQADCgEIAQAAAA==.',
Qu='Quackiechan:BAAANQAECgYICQAAAA==.Quasibeast:BAAANQADCgIIAgAAAA==.',
Ra='Raer:BAAANQADCggIDwAAAA==.Ragabowa:BAAANQAECgQIBQAAAA==.Raikirii:BAAANQAECgcICwAAAA==.Rampagejaxon:BAAANQADCgQIBAAAAA==.Ravaxys:BAAANQADCgQIBAAAAA==.Rayzac:BAAANQAECgEIAQAAAA==.',
Re='Redfacedemon:BAAANQADCgYIBgAAAA==.Renwall:BAAANQADCgcICgAAAA==.',
Ri='Rictusempra:BAAANQADCggIDgAAAA==.Rilwarp:BAAANQADCgQIBAAAAA==.',
Ro='Rokash:BAAANQADCgYIBgABNQAECgYICAABAAAAAA==.Rozuveos:BAAANQADCgYIDwAAAA==.',
Ru='Rumplez:BAAANQAECgYIAwAAAA==.',
Sa='Saelzington:BAAANQAECggIDQAAAA==.Saepink:BAAANQADCggIDwABNQAECggIDQABAAAAAA==.Sakurajima:BAAANQAECgEIAgAAAA==.Samuraibicep:BAAANQADCgYICgAAAA==.Sariiane:BAAANQADCgQIBAAAAA==.Sarrizza:BAAANQADCgYICQAAAA==.',
Sc='Scaledaddy:BAAANQADCgcIDAAAAA==.Scartrist:BAAANQADCgcICgAAAA==.Scrotimus:BAAANQADCgYICQAAAA==.Scylent:BAAANQADCgQIBQAAAA==.',
Se='Seasontwodk:BAAANQADCgQIBQAAAA==.Selannil:BAAANQADCgEIAQAAAA==.',
Sh='Shadowbutt:BAAANQAECgIIAgAAAA==.Shadowdeadma:BAAANQAECgQIBAAAAA==.Shankfoo:BAAANQADCgUIBQAAAA==.Shimmew:BAAANQAECgcIDAAAAA==.Shinhati:BAAANQAECgUICAAAAA==.',
Si='Sicariox:BAAANQAECgMIAwAAAA==.',
Sk='Skizzixx:BAAANQADCgYIBwAAAA==.',
Sl='Slapshop:BAAANQAECgIIAgAAAA==.Slice:BAAANQADCggIEAAAAA==.Slippyfistt:BAAANQADCgYICwAAAA==.Slowansteady:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.',
Sm='Smoxx:BAAANQAECgMIAwAAAA==.Smörc:BAAANQADCgcIBwAAAA==.',
Sn='Sneeg:BAAANQAECgEIAQABNQAECgUIBQABAAAAAA==.',
So='Sobchak:BAAANQAECgYICAAAAA==.Sober:BAAANQAECgUIBwAAAA==.Softfleur:BAAANQADCgcIDQAAAA==.Softrminator:BAAANQADCgQIBAAAAA==.Sokz:BAAANQAECgUICQAAAA==.Soraka:BAAANQAECgEIAQABNQAECgQICQABAAAAAA==.Soxxs:BAAANQADCgYIBgAAAA==.',
Sp='Spartystrasz:BAAANQAECgQIBAAAAA==.',
St='Stonepaw:BAAANQADCgQIBQAAAA==.Stormsound:BAAANQADCgYIBgAAAA==.Stratuz:BAAANQADCgQIBwAAAA==.',
Su='Sugoi:BAAANQAECgMIAwAAAA==.Surtvyr:BAEANQAECgEIAQABNQAECggIDQABAAAAAA==.',
Sw='Sweetdemonic:BAAANQADCgIIAgAAAA==.Sweettoothz:BAAANQADCgYIBgAAAA==.Swiddles:BAAANQAECgUIBQAAAA==.',
Ta='Talara:BAAANQADCgUIBQAAAA==.Talsaiir:BAAANQADCgYIBgAAAA==.Talyyn:BAAANQADCgIIAgAAAA==.Tatorshot:BAAANQADCgUICQAAAA==.',
Te='Tekmatek:BAAANQAECgEIAQAAAA==.Terpenes:BAAANQAECgUIBQABNQAECgYICAABAAAAAA==.',
Th='Thelust:BAAANQADCgYIDAABNQAECgMIAwABAAAAAA==.Thorhin:BAAANQADCgYICwAAAA==.Thébígtúñá:BAAANQADCgYICgAAAA==.',
Ti='Ticklemytots:BAAANQAECgQIBAAAAA==.Tiltvoke:BAAANQADCgIIAgAAAA==.Tirynis:BAEANQAECgcIDAAAAA==.',
Tl='Tlow:BAAANQAECgQIBAAAAA==.',
Tm='Tmsmdfcrcls:BAAANQAECgMIAwAAAA==.',
To='Toelp:BAAANQADCgMIAwAAAA==.Toothnnailz:BAAANQADCggICAAAAA==.Topochica:BAAANQADCgcIDAAAAA==.Totemtankn:BAAANQAECgIIAgAAAA==.Toxic:BAAANQADCgMIAwABNQADCgcIDQABAAAAAA==.',
Tr='Trancemusic:BAAANQADCgcICgAAAA==.Trashdk:BAAANQADCggICAABNQAECgEIAQABAAAAAA==.Treeboi:BAAANQADCgUIBQAAAA==.Triibs:BAAANQADCgYICQAAAA==.',
Tu='Tulashir:BAAANQABCgIIBAAAAA==.Turayne:BAAANQAECgEIAQAAAA==.',
Ty='Tyerial:BAAANQADCgIIAgAAAA==.Tyronbigadin:BAAANQAECgQIBQAAAA==.',
['Té']='Témpèst:BAAANQAECgQIBAABNQAECgQIBQABAAAAAA==.',
['Tõ']='Tõby:BAAANQAECgQIBAAAAA==.',
Ul='Ultis:BAAANQADCgQIBAAAAA==.',
Va='Valkÿrie:BAAANQAECgMIAwAAAA==.Vandral:BAAANQAECgEIAQAAAA==.Varella:BAAANQAECgYICAAAAA==.',
Ve='Veinless:BAAANQADCggIDwAAAA==.Velanné:BAAANQAECgIIBQABNQADCgYIBgABAAAAAA==.Venusx:BAAANQAECgQIBAABNQAECgYIBgABAAAAAA==.Vethemir:BAAANQADCgYIBwAAAA==.Vexmachína:BAAANQAECgIIAgAAAA==.Vextheria:BAAANQADCgYIBgAAAA==.Veyg:BAAANQAECgUIBgAAAA==.',
Vi='Viletrance:BAAANQADCgYIDgAAAA==.Visenyatarg:BAAANQADCgYIBgAAAA==.',
Vo='Vondo:BAAANQADCgcIBwABNQAECgcIDAABAAAAAA==.Vorunaa:BAAANQAECgIIAgAAAA==.Vorztrix:BAAANQAECgYIBgAAAA==.',
Vy='Vythras:BAAANQAECgIIAgAAAA==.',
['Vä']='Välkyrie:BAAANQADCggICAAAAA==.',
['Vå']='Vålkyrie:BAAANQAECgQIBAAAAA==.',
['Vë']='Vëlzhen:BAAANQADCgIIAgABNQAECgYIBwABAAAAAA==.',
Wa='Wanacupcake:BAAANQADCgMIAwAAAA==.Warenn:BAAANQADCgEIAQAAAA==.Warstall:BAAANQAECgcICAAAAA==.Waterincone:BAAANQAECgMIAwAAAA==.',
We='Weakswings:BAAANQABCgQIBgAAAA==.Wezethejuice:BAAANQADCgUICgAAAA==.',
Wh='Whitebison:BAAANQADCgUIBQAAAA==.',
Wi='Willhsiao:BAAANQADCgYICgAAAA==.',
Wo='Wogawogawoga:BAAANQADCgYIDAAAAA==.',
Wy='Wyatta:BAAANQADCgUIBQAAAA==.Wyrmbane:BAAANQADCgIIAgAAAA==.',
['Wì']='Wìsdom:BAAANQAECgEIAQAAAA==.',
Xa='Xaltwer:BAAANQADCgUIBAAAAA==.Xasz:BAAANQAECgcIDAAAAA==.Xaszageth:BAAANQADCgcIDQABNQAECgcIDAABAAAAAA==.',
Xc='Xcrush:BAAANQAECgIIAwABNQAECgIIAgABAAAAAA==.',
Xd='Xdata:BAAANQAECgMIAwAAAA==.',
Xe='Xerias:BAAANQAECgQIBAAAAA==.',
Xi='Xieno:BAAANQADCgYIBgAAAA==.',
Xo='Xovyt:BAAANQADCggIDgABNQAECgcIDAABAAAAAA==.',
Ya='Yaana:BAAANQADCgcIEQAAAA==.Yaney:BAAANQADCgYICQAAAA==.',
Za='Zama:BAAANQADCgIIAgAAAA==.Zarzlek:BAAANQAECgQIBAAAAA==.',
Ze='Zenthyk:BAAANQAECgQIBAAAAA==.Zephahniah:BAAANQADCgIIAgAAAA==.',
Zh='Zheela:BAAANQADCgYICgAAAA==.',
Zi='Zimbala:BAAANQAECgEIAQAAAA==.',
Zp='Zpants:BAAANQADCgUICwAAAA==.',
Zu='Zulna:BAAANQADCggICQAAAA==.Zulrippa:BAAANQADCgMIAwAAAA==.',
Zy='Zyron:BAAANQADCgMIAwAAAA==.',
['Äm']='Ämon:BAAANQADCgcIBwAAAA==.',
['Ël']='Ëlyndal:BAAANQAECgYIBwAAAA==.',
['Ëñ']='Ëñÿõ:BAAANQAECgQIBQAAAA==.',
['ßr']='ßreezy:BAAANQAECgIIAgAAAA==.',
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
