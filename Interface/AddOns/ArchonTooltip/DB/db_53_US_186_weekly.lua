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
local provider = {region='US',realm="Sen'jin",name='US',type='weekly',zone=53,date='2026-09-01',data={Ac='Actaeon:BAAANQADCgUIBQAAAA==.',
Ae='Aegrias:BAAANQAECgYICQAAAA==.',
Al='Alainy:BAAANQADCggIDwAAAA==.Alentrya:BAAANQADCgMIBAABNQADCggIDgABAAAAAA==.Alestraza:BAAANQADCgEIAQABNQAECgIIAwABAAAAAA==.Alice:BAAANQADCgYICwAAAA==.Aliveagain:BAAANQADCgMIBAAAAA==.',
Am='Amageros:BAAANQADCgcICwAAAA==.Amaterasu:BAAANQAECgQIBgAAAA==.Amonamärth:BAAANQADCgUIBwAAAA==.',
An='Andrael:BAAANQADCgMIBQAAAA==.Andraszun:BAAANQADCgYIDAAAAA==.Andruin:BAAANQADCgYIBgAAAA==.Annieoaklea:BAAANQADCgMIBAAAAA==.Anubuskid:BAAANQADCgYIBgAAAA==.',
Aq='Aqua:BAAANQAECgEIAQAAAA==.',
Ar='Aragurn:BAAANQADCgMIAwAAAA==.Artemís:BAAANQAECgIIAwAAAA==.Arthrogate:BAAANQADCgMIBAAAAA==.',
As='Astana:BAAANQAECgEIAQAAAA==.Astraii:BAAANQAECgEIAQAAAA==.',
At='Attrox:BAAANQADCggIDgAAAA==.',
Au='Augtistic:BAAANQADCgcIDQAAAA==.Auridia:BAAANQADCgMIBAAAAA==.',
Av='Avalef:BAAANQADCgIIAgAAAA==.',
Az='Azagonnath:BAAANQADCgcIDAAAAA==.',
Ba='Babybread:BAAANQADCgEIAQAAAA==.Backtrak:BAAANQADCggIDgAAAA==.Bamboomnster:BAAANQAECgEIAQAAAA==.Bankpokc:BAAANQADCgEIAQAAAA==.Bareeyyee:BAAANQAECgEIAQAAAA==.Baréin:BAAANQADCgUIBQAAAA==.Bassinel:BAAANQADCgYIBgAAAA==.',
Be='Beesbok:BAAANQADCgYIBgAAAA==.Belasius:BAAANQADCgMIAwAAAA==.Belldandy:BAAANQADCgYICwAAAA==.',
Bi='Bigdaddydan:BAAANQAECgYICAAAAA==.Bishämon:BAAANQAECgQIBQAAAA==.',
Bj='Bjorgan:BAAANQADCgYICwAAAA==.',
Bl='Blinddate:BAAANQAECgQIBQAAAA==.Blindside:BAAANQADCggICgAAAA==.Bloodrose:BAAANQADCgEIAQAAAA==.',
Bo='Bohe:BAAANQADCgMIBAAAAA==.Boldog:BAAANQADCgcIBwAAAA==.Bombpop:BAAANQADCgYIBgAAAA==.Bootyfull:BAAANQADCgQIBAAAAA==.Borderlands:BAAANQABCgEIAQAAAA==.Bouldin:BAAANQADCgYICwAAAA==.Bouseman:BAAANQABCgIIAgAAAA==.',
Br='Brandn:BAAANQAECgQIBgAAAA==.Bridgett:BAAANQADCggIDgAAAA==.Brioche:BAAANQADCgYIBgAAAA==.',
Bu='Budcrest:BAAANQADCgEIAQAAAA==.Bums:BAAANQADCgMIAwAAAA==.',
['Bü']='Bümps:BAAANQADCggIEAAAAA==.',
Ca='Cabinet:BAAANQADCgUIBQAAAA==.Caledor:BAAANQADCggIDwAAAA==.Cancer:BAAANQADCggIDgAAAA==.Captclamslam:BAAANQADCgQIBAABNQADCgYIBgABAAAAAA==.Catbutt:BAAANQAECgQIBQAAAA==.',
Ce='Cerissia:BAAANQADCggICAAAAA==.',
Ch='Chapo:BAAANQADCgYIBgAAAA==.Chewshocka:BAAANQADCgMIAwAAAA==.',
Co='Coco:BAAANQADCggICAAAAA==.Cocopuf:BAAANQAECgMIAwAAAA==.Codels:BAAANQADCgEIAQAAAA==.Corlock:BAAANQAECgEIAQAAAA==.',
Cr='Crb:BAAANQADCgYIBgAAAA==.Crimsonsong:BAAANQAECgEIAQAAAA==.Crixsas:BAAANQADCgEIAQAAAA==.Crocodile:BAAANQABCgEIAQAAAA==.Croise:BAAANQAECgQIBgAAAA==.Crystalneth:BAAANQADCgMIAwAAAA==.Crössblesser:BAAANQADCgcIDAAAAA==.',
Cy='Cynarel:BAAANQADCgMIAwAAAA==.Cyrial:BAAANQADCgMIBAABNQADCggIDgABAAAAAA==.',
Da='Darctricity:BAAANQAECgIIAgAAAA==.Dashay:BAAANQADCgYICgAAAA==.Dazao:BAAANQADCggIDgAAAA==.',
De='Deathdealr:BAAANQAECgQIBAAAAA==.Deathslayr:BAAANQADCgcIDQAAAA==.Deathsranger:BAAANQADCgYICgAAAA==.Decks:BAAANQAECgMIAwAAAA==.Deianne:BAAANQAECgYIBgAAAA==.Deks:BAAANQADCggIEAABNQAECgMIAwABAAAAAA==.Delerius:BAAANQAECgIIAgAAAA==.Deltre:BAAANQAECgYICwAAAA==.Demonimai:BAAANQADCgYICgAAAA==.Depletechkn:BAAANQAECgQIBgAAAA==.Desecratés:BAAANQAECgEIAQAAAA==.Deäthcowd:BAAANQAECgcICgAAAA==.',
Di='Dim:BAAANQADCgYIBgAAAA==.Dizdemona:BAAANQAECgIIAgAAAA==.Dizrupt:BAAANQAECgMIAwAAAA==.',
Dj='Dj:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.',
Do='Doomstickk:BAAANQADCgUIBQAAAA==.Dopy:BAAANQADCggICAAAAA==.Dorania:BAAANQADCgYIBgAAAA==.',
Dr='Dracoradh:BAAANQAECgQIBQABNQABCgQIBgABAAAAAA==.Dracorapalli:BAAANQADCgYIBgABNQABCgQIBgABAAAAAA==.Drakondra:BAAANQADCgYIBgAAAA==.Draziel:BAAANQADCggIDgAAAA==.',
Du='Dungarrth:BAAANQADCgEIAQAAAA==.Dunhammer:BAAANQADCgUICQAAAA==.Duverlierst:BAAANQADCggICwAAAA==.',
Dw='Dwarvenbufet:BAAANQADCgQIBQAAAA==.',
Dy='Dyhrd:BAAANQADCgcIDQAAAA==.',
['Dü']='Dücky:BAAANQADCgUICQAAAA==.',
El='Ellaryn:BAAANQAECgEIAQAAAA==.Elorla:BAAANQADCgUIBQAAAA==.',
Em='Emporerzur:BAAANQADCgcIBwAAAA==.',
En='Enchantertim:BAAANQADCgIIAgAAAA==.',
Er='Eriaeveline:BAAANQADCgQIBAAAAA==.',
Ew='Ewaker:BAAANQADCgYICwAAAA==.',
Ey='Eyante:BAAANQADCgYIBgABNQAECgQIBgABAAAAAA==.',
Fa='Faenerys:BAAANQADCgMIAwAAAA==.Faerundur:BAAANQADCgcIDAAAAA==.',
Fe='Felco:BAAANQAECgQIBgAAAA==.Feltharion:BAAANQADCgQIBQAAAA==.',
Fi='Fitzjuno:BAAANQADCgYIDAAAAA==.',
Fl='Flannegan:BAAANQABCgIIAwAAAA==.Flexgrip:BAAANQADCgEIAQABNQADCggIDgABAAAAAA==.Flixxer:BAAANQADCgYIBgAAAA==.Flÿnn:BAAANQABCgQIBQAAAA==.',
Fo='Forgotthehot:BAAANQAECgQIBAAAAA==.Fortified:BAAANQAECgIIAgAAAA==.',
Fr='Frostty:BAAANQAECggIBgAAAA==.',
Fu='Funkaspuck:BAAANQADCgMIAwAAAA==.',
Ga='Gaara:BAAANQADCgYICQAAAA==.Gafgalron:BAAANQADCgcICwAAAA==.Galatha:BAAANQAECgEIAQAAAA==.Gamonwan:BAAANQABCgIIAgAAAA==.Gandoofus:BAAANQADCggIDAAAAA==.Gardengnome:BAAANQAECgEIAQAAAA==.Garrot:BAAANQADCgQIBAABNQADCggICAABAAAAAA==.',
Ge='Gerardway:BAAANQADCggICAAAAA==.',
Gi='Giga:BAAANQAECgIIAwAAAA==.Gigashadow:BAAANQADCgUIBQAAAA==.',
Gl='Glad:BAAANQADCggIDgAAAA==.Gluck:BAAANQADCgQIBAAAAA==.',
Gr='Grampy:BAAANQADCgMIBAAAAA==.Greyparse:BAAANQADCgQIBAAAAA==.',
Gu='Gullurg:BAAANQADCgYICgABNQAECgIIAgABAAAAAA==.Gutthisclass:BAAANQADCgUIBQAAAA==.',
Gw='Gweneviere:BAAANQADCgYIDQAAAA==.',
['Gî']='Gîrth:BAAANQAECgQICQABNQAECggIDwABAAAAAA==.',
Ha='Hades:BAAANQADCggICgAAAA==.Hadesfalcon:BAAANQADCggIDgAAAA==.Hadesz:BAAANQADCgYICgAAAA==.Hainne:BAAANQADCgYIBgAAAA==.Handrob:BAAANQAECgEIAQAAAA==.Hanoii:BAAANQADCggIDAABNQAECgEIAQABAAAAAA==.Happyguy:BAAANQADCgQIBAABNQADCggICAABAAAAAA==.Harilas:BAAANQADCgEIAQAAAA==.Harrier:BAAANQADCgIIAgABNQADCggICwABAAAAAA==.Hayles:BAAANQADCgcICwAAAA==.',
He='Healteamsix:BAAANQAECgMIAwAAAA==.',
Hi='Hideyoshi:BAAANQADCgUIBQAAAA==.Hitowerr:BAAANQADCgMIAwAAAA==.',
Ho='Hollywoodx:BAAANQAECgMIAwAAAA==.',
Hu='Huangx:BAAANQAECgIIAgAAAA==.Husbones:BAAANQADCggIDgAAAA==.Huszilla:BAAANQAECgIIAgAAAA==.',
Ia='Iamgroot:BAAANQADCgQIBQAAAA==.',
Ic='Icwiener:BAAANQABCgIIAgAAAA==.',
Ig='Igniz:BAAANQAECgEIAQAAAA==.',
Im='Immunity:BAAANQADCgQIBAAAAA==.',
In='Indrä:BAAANQADCgQIBAAAAA==.',
It='Itaska:BAAANQAECgEIAQAAAA==.Itfitzwell:BAAANQADCgMIAwAAAA==.',
['Iù']='Iùwúl:BAAANQAECgQIBgAAAA==.',
Ja='Jackmage:BAAANQADCgUIBQAAAA==.Jameywomp:BAAANQAECgEIAQAAAA==.',
Je='Jellyfingerz:BAAANQADCgYICwAAAA==.Jestik:BAAANQAECgMIAwAAAA==.',
Jh='Jhyl:BAAANQADCggIDgAAAA==.',
Ji='Jinu:BAAANQADCgEIAQAAAA==.',
Jo='Joherys:BAAANQADCgYIBgAAAA==.Joints:BAAANQAECggICAAAAA==.Jordroy:BAAANQAECgQIBgAAAA==.',
['Jæ']='Jægeren:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.',
Ka='Kaanuu:BAAANQADCgcIDAAAAA==.Kaargadin:BAAANQADCgMIAwAAAA==.Kabbage:BAAANQADCggIDwAAAA==.Kablam:BAAANQAECgQIBgAAAA==.Kadon:BAAANQADCgYIBgABNQADCggIDwABAAAAAA==.Kalindigo:BAAANQADCgQIBAAAAA==.Kalter:BAAANQADCgIIAgAAAA==.Kamarigh:BAAANQADCgUIDQAAAA==.Kamui:BAAANQAECgQIBAAAAA==.Kapreesun:BAAANQADCggIEAABNQAECgIIAgABAAAAAA==.Kaprisun:BAAANQAECgIIAgAAAA==.Kapu:BAAANQADCggICgAAAA==.Karynnora:BAAANQAECgEIAQAAAA==.',
Ke='Kelibarranth:BAAANQADCgYICQAAAA==.Kemanthuurel:BAAANQADCgcIBwAAAA==.',
Kh='Khaoticus:BAAANQADCgYIDAAAAA==.',
Ki='Killerelvis:BAAANQAECgEIAQAAAA==.',
Kn='Knollyeti:BAAANQADCgYIDAAAAA==.',
Ko='Koalajin:BAAANQAECgQIBgAAAA==.Kobi:BAAANQADCgIIAwAAAA==.Kopróx:BAAANQAECgEIAQABNQAECgIIAwABAAAAAA==.Korfane:BAAANQADCggIDgAAAA==.',
Kr='Krazystrike:BAAANQADCgcICgAAAA==.Kryptonikz:BAAANQADCgUIBQAAAA==.',
Ku='Kuber:BAAANQAECgQIBgAAAA==.',
La='Laelene:BAAANQADCgYICgAAAA==.Layn:BAAANQADCgcICAAAAA==.',
Le='Lehsmit:BAAANQADCgEIAQAAAA==.Lemonpoppy:BAAANQADCgUIBwABNQADCgYIBgABAAAAAA==.',
Li='Lilspuds:BAAANQADCgQIBAAAAA==.',
Ll='Llucas:BAAANQAECgYIBgAAAA==.',
Lo='Locian:BAAANQAECgMIAwAAAA==.Locked:BAAANQADCgEIAQABNQADCgEIAQABAAAAAA==.Loycen:BAAANQAECgQIBgAAAA==.',
Lu='Lucàs:BAAANQAECgQIBAAAAA==.Lunarosá:BAAANQAECgMIAwAAAA==.',
Ly='Lykiri:BAAANQADCgYICQAAAA==.Lyllyth:BAAANQADCgYICgAAAA==.Lyric:BAAANQADCgcIDAAAAA==.Lysandraa:BAAANQADCggICAAAAA==.',
Ma='Madren:BAAANQADCggIDgAAAA==.Magicspell:BAAANQADCgYIBgAAAA==.Maidro:BAAANQADCgMIAwAAAA==.Maitotem:BAAANQADCggIDgAAAA==.Malhus:BAAANQADCgQIBAAAAA==.Manu:BAAANQADCgcICwAAAA==.Maplefoxx:BAAANQAECgIIAgAAAA==.Maragosa:BAAANQADCgYICwAAAA==.Marlik:BAAANQADCgMIBAAAAA==.Mashadar:BAAANQADCgcIDAAAAA==.',
Mc='Mcstuffíns:BAAANQADCgYICgAAAA==.',
Me='Mechaorcleb:BAAANQADCgMIAwAAAA==.Meducea:BAAANQADCgMIBAAAAA==.Meea:BAAANQADCgUIBQAAAA==.Megadööm:BAAANQAECgQIBgAAAA==.Megz:BAAANQADCgUIBQAAAA==.Megzies:BAAANQADCgcIBwAAAA==.',
Mi='Mikori:BAAANQADCggIEQAAAA==.Mikura:BAAANQABCgQIBAAAAA==.Mithael:BAAANQADCgUIBQAAAA==.',
Mo='Mobium:BAAANQADCgcICQAAAA==.Monolith:BAAANQADCgQIBAABNQADCggIDQABAAAAAA==.Montyopython:BAAANQADCggIDgAAAA==.Mordsithcara:BAAANQADCgYICAAAAA==.Motodk:BAAANQADCgIIAgABNQAECgEIAgABAAAAAA==.Motoguerr:BAAANQAECgEIAgAAAA==.Mozzie:BAAANQADCgQIBAAAAA==.',
Mu='Muertenoche:BAAANQADCgMIBAAAAA==.Murista:BAAANQAECgEIAQAAAA==.',
My='Mylke:BAAANQADCggIDgAAAA==.Myronar:BAAANQADCgEIAQAAAA==.Mysery:BAAANQADCgQIBQAAAA==.Myslicer:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.Mysticdragon:BAAANQADCgcIDAAAAA==.',
Na='Naisary:BAAANQADCgYIBgABNQAECgEIAgABAAAAAA==.Namanari:BAAANQADCgYICgAAAA==.Nazzareth:BAAANQADCgYICgAAAA==.',
Ne='Nest:BAAANQAECgIIAgAAAA==.Neverlied:BAAANQADCggIDgAAAA==.Nexum:BAAANQADCgcICQAAAA==.',
Ni='Nicolemarie:BAAANQAECgEIAgABNQAECgQIBAABAAAAAA==.Niipplets:BAAANQAECggIDwAAAA==.Nilophyte:BAAANQAECgYICQAAAA==.Ninzy:BAAANQAFFAEIAQAAAA==.Nito:BAAANQADCggIDQAAAA==.',
No='Nolenardan:BAAANQAECgEIAQAAAA==.Nosferotlock:BAAANQADCgcIDAAAAA==.Notspanky:BAAANQAECgUIBgAAAA==.',
Ny='Nyxenya:BAAANQAECgQIBwAAAA==.',
['Nô']='Nôvus:BAAANQADCggIDgAAAA==.',
['Nÿ']='Nÿx:BAAANQADCggICAAAAA==.',
Or='Orchestral:BAAANQADCgYIBwAAAA==.',
Pa='Pagtuga:BAAANQADCgYICgAAAA==.Palamine:BAAANQADCggICAAAAA==.Palasqueeze:BAAANQADCgQIBAAAAA==.Palicombat:BAAANQADCgYIBgAAAA==.',
Pe='Peenuts:BAAANQADCgcICAAAAA==.Pesha:BAAANQABCgQIAwABNQADCgcIDAABAAAAAA==.Petals:BAAANQADCgYICwAAAA==.',
Ph='Phandapart:BAAANQADCgUICAAAAA==.',
Pi='Piip:BAAANQAECgMIAwAAAA==.',
Pl='Plushfire:BAAANQADCgMIAwAAAA==.',
Po='Pokcmvmxckm:BAAANQADCggIDgAAAA==.Pokcmxmvkcm:BAAANQADCgMIAwAAAA==.',
Pr='Preyed:BAAANQADCgUIBwAAAA==.Primora:BAAANQADCgYICAAAAA==.Protocol:BAAANQADCggIDgAAAA==.',
Pt='Ptsdthegamer:BAAANQADCgMIAwAAAA==.',
Pu='Pugg:BAAANQADCggICgAAAA==.Purplecrayon:BAAANQAECgMIAwAAAA==.',
Qu='Quivers:BAAANQADCggICAABNQADCggICQABAAAAAA==.',
Ra='Rads:BAAANQADCggICQAAAA==.Rameth:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Ranji:BAAANQADCgMIBAAAAA==.Ranmojo:BAAANQADCgUICAAAAA==.Ravenholm:BAAANQADCgcIBwAAAA==.',
Re='Redlikeroses:BAAANQAECgQIBAAAAA==.',
Rh='Rhickssyn:BAAANQAECgQIBgAAAA==.Rhyleejo:BAAANQADCgMIBAAAAA==.Rhyzamel:BAAANQADCgMIAwAAAA==.',
Ri='Riias:BAAANQADCggIDwAAAA==.',
Ro='Rocq:BAAANQADCggIEAAAAA==.Roenix:BAAANQADCgMIAwAAAA==.Rogust:BAAANQADCgEIAQAAAA==.',
Ru='Rustybeer:BAAANQADCggICwAAAA==.',
Ry='Rynia:BAAANQADCgYIBgAAAA==.',
['Rí']='Ríddíck:BAAANQADCgQIBAAAAA==.',
['Ró']='Róxas:BAAANQADCgYIDAAAAA==.',
Sa='Sadîst:BAAANQADCggIEAAAAA==.Sanloran:BAAANQABCgIIAgAAAA==.Sarasvati:BAAANQAECgQIBgAAAA==.Sartoss:BAAANQADCgUIBQAAAA==.Savriemina:BAAANQAECgYICAAAAA==.',
Sc='Scallion:BAAANQADCgYIBgAAAA==.',
Se='Semara:BAAANQADCgEIAQAAAA==.Semya:BAAANQADCgYIDAAAAA==.Semí:BAAANQADCgcIBwAAAA==.Seradk:BAAANQAECgIIAgAAAA==.Seraphíne:BAAANQAECgcICQAAAA==.Serzul:BAAANQADCgcIDQAAAA==.Sewazbek:BAAANQADCgEIAQAAAA==.',
Sh='Shadowhayze:BAAANQADCgYIBgAAAA==.Shamanate:BAAANQADCgYICwAAAA==.Shamnanigans:BAAANQAECgIIAgAAAA==.Sharana:BAAANQADCgUIBQAAAA==.Sharin:BAAANQADCgMIAwAAAA==.Shevraeth:BAAANQADCgMIBAABNQADCggIDgABAAAAAA==.Shizhisjiz:BAAANQADCgYICgAAAA==.Shrilla:BAAANQADCggIDgAAAA==.',
Si='Sidonay:BAAANQAECgIIAwABNQAECgIIAwABAAAAAA==.Sikodeath:BAAANQADCgEIAQAAAA==.Simplysinful:BAAANQAECgQIBAAAAA==.Sims:BAAANQAECgIIAgAAAA==.Sinnershep:BAAANQADCgcIDAAAAA==.Siouxii:BAAANQADCggIDwAAAA==.',
Sk='Skul:BAAANQADCgYICwAAAA==.',
Sl='Slatag:BAAANQADCgYICwAAAA==.Slime:BAAANQAFFAEIAQAAAA==.',
Sm='Smashcombat:BAAANQADCgUICAAAAA==.',
So='Soiledsoul:BAAANQADCgUICQAAAA==.Sojourner:BAAANQADCggIDgAAAA==.',
Sp='Sparklenips:BAAANQADCgcIDAAAAA==.Spritezero:BAAANQADCgQIBAAAAA==.',
St='Staraynne:BAAANQADCgMIBAAAAA==.Starmaster:BAAANQADCgYIDAAAAA==.Steaktacular:BAAANQADCgMIAwAAAA==.Stihll:BAAANQAECgEIAQAAAA==.Storming:BAAANQADCgEIAQAAAA==.Stormlight:BAAANQAECgIIAgAAAA==.Stretchnutz:BAAANQADCgIIAgAAAA==.',
Su='Sunjia:BAAANQADCgIIAgABNQADCgcICQABAAAAAA==.',
Sw='Sweetangel:BAAANQADCgUIBQAAAA==.',
Sy='Synclaar:BAAANQAECgIIAgAAAA==.Syrioûs:BAAANQADCgUIBgAAAA==.',
['Så']='Såyoko:BAAANQADCgcIDQAAAA==.',
['Sø']='Søøner:BAAANQADCgcIBwAAAA==.',
Ta='Tadinanefer:BAAANQADCgEIAQAAAA==.Tailstwo:BAAANQAECgIIAgAAAA==.Taintshockur:BAAANQADCgUIBQAAAA==.Talmi:BAAANQADCgMIBAAAAA==.Tamiria:BAAANQADCgcIDQAAAA==.Tanora:BAAANQADCgEIAQAAAA==.',
Te='Terademon:BAAANQADCggICAAAAA==.Terryfic:BAAANQADCggIDgAAAA==.',
Th='Thefearful:BAAANQAECgcIDQAAAA==.Thejin:BAAANQADCgMIAwAAAA==.Thelios:BAAANQAECgQIBgAAAA==.Theomore:BAAANQADCgYIBgAAAA==.Thierryjames:BAAANQADCgcICwAAAA==.Thragar:BAAANQADCgYICQAAAA==.Thrina:BAAANQAECgIIAgAAAA==.Thuss:BAAANQADCgcIBwAAAA==.',
Ti='Titan:BAAANQADCgMIBAAAAA==.',
To='Toobyfour:BAAANQABCgQIBAAAAA==.Tooggy:BAAANQAECgUICgAAAA==.',
Tr='Trelocke:BAAANQAECgQIBAAAAA==.Tremira:BAAANQADCgEIAQAAAA==.Trickshot:BAAANQADCgQIBAAAAA==.Trogstomp:BAAANQADCggICwAAAA==.Trus:BAAANQADCgIIAgAAAA==.',
Tu='Tuatha:BAAANQAECgQIBgAAAA==.',
Tw='Twistedlight:BAAANQADCgQIBAAAAA==.',
Ty='Tygraen:BAAANQAECgEIAQAAAA==.',
['Tø']='Tønga:BAAANQADCgQIBAAAAA==.',
Uh='Uhohdh:BAAANQAECgcICwAAAA==.',
Un='Unos:BAAANQADCggICQAAAA==.Unosdk:BAAANQADCgQIBAABNQADCggICQABAAAAAA==.Unosmage:BAAANQADCgQIBAAAAA==.',
Us='Usva:BAAANQADCgYICwAAAA==.',
Va='Vaiygarshprd:BAAANQAECgQIBgAAAA==.Valhalla:BAAANQADCgQIBAAAAA==.Valreth:BAAANQADCgUIBwAAAA==.Valtorin:BAAANQABCgIIAgAAAA==.Vandalize:BAAANQADCgYIBwAAAA==.Vanitas:BAAANQAECgEIAQAAAA==.',
Ve='Veddar:BAAANQADCgQIBAAAAA==.Veleice:BAAANQADCgMIAwAAAA==.Vellaide:BAAANQADCgYICAAAAA==.Veltrafang:BAAANQAECgMIBAAAAA==.Veltramoon:BAAANQADCgIIAgABNQAECgMIBAABAAAAAA==.Vennisa:BAAANQAECgcICgAAAA==.',
Vh='Vhelkan:BAAANQAECgIIAgAAAA==.',
Vr='Vraelin:BAAANQADCggIDgAAAA==.',
['Vé']='Vélèdryke:BAAANQADCgQIBAAAAA==.',
Wa='Waltmallow:BAAANQADCgEIAQAAAA==.Warco:BAAANQADCgYIBgABNQAECgQIBgABAAAAAA==.Wardiv:BAAANQADCgMIBAAAAA==.',
We='Wedel:BAAANQAECgYICAAAAA==.Wesleywillis:BAAANQABCgIIAgAAAA==.',
Wh='Whisperas:BAAANQADCgEIAQAAAA==.Whodahoda:BAAANQADCgYICQAAAA==.',
Wi='Windfurry:BAAANQADCggIEQAAAA==.',
Wo='Wolf:BAAANQADCgEIAQAAAA==.Wookieebrew:BAAANQADCgUIBQAAAA==.Worbear:BAAANQAECgMIAwAAAA==.',
Wr='Wrent:BAAANQADCgEIAQAAAA==.',
Xa='Xandabull:BAAANQADCgMIBAAAAA==.Xaniengenn:BAAANQADCgIIAgAAAA==.',
Xe='Xeney:BAAANQAECgEIAQAAAA==.Xenie:BAAANQADCgQIBwAAAA==.Xenity:BAAANQADCgUIBQAAAA==.Xenjoza:BAAANQADCgcIDQAAAA==.Xenpai:BAAANQADCgQIBAAAAA==.Xens:BAAANQAECgQIBgAAAA==.Xeny:BAAANQADCgQIBAAAAA==.Xerorage:BAAANQAECgQIBAAAAA==.',
Xo='Xochil:BAAANQADCggIDgAAAA==.',
Xp='Xp:BAAANQADCgIIAgAAAA==.',
Ye='Yesican:BAAANQADCgYIBgAAAA==.',
Yi='Yimiru:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.',
Yu='Yuffie:BAAANQADCgQIBAAAAA==.Yumikiim:BAAANQAECgQIBAAAAA==.',
Za='Zaknafein:BAAANQADCgcIDAAAAA==.Zanazoth:BAAANQAECgYICAAAAA==.Zanziri:BAAANQADCgcICwAAAA==.',
Ze='Zeffyre:BAAANQADCgQIBQAAAA==.Zepher:BAAANQADCgYICQAAAA==.',
Zi='Zillaby:BAAANQAECgQIBgAAAA==.Zimbobway:BAAANQADCgIIAgABNQADCgYICQABAAAAAA==.Zindori:BAAANQAECgMIBAABNQAECgQIBAABAAAAAA==.Ziploc:BAAANQADCgMIAwABNQADCggIDgABAAAAAA==.',
Zo='Zodiark:BAAANQADCgUICQAAAA==.Zoltair:BAAANQADCgYIDAAAAA==.',
Zu='Zugadin:BAAANQAECgEIAQAAAA==.Zugthoth:BAAANQADCgEIAQABNQADCggIEAABAAAAAA==.Zukaya:BAAANQAECgEIAQAAAA==.Zullivain:BAAANQAECgQIBAAAAA==.',
Zx='Zxinn:BAAANQADCgIIAgAAAA==.',
['Åc']='Åcume:BAAANQADCgUIBQAAAA==.',
['Ív']='Ívery:BAAANQAECgQIBAAAAA==.',
['Íz']='Ízzÿ:BAAANQAECgEIAQAAAA==.',
['Ôm']='Ômëñ:BAAANQADCgIIAgAAAA==.',
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
