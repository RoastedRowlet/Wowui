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

local lookup = {'Unknown-Unknown','Warrior-Protection',}
local provider = {region='US',realm='ArgentDawn',name='US',type='weekly',zone=53,date='2026-09-01',data={Ab='Abajaba:BAAANQADCgQIBAAAAA==.Abractus:BAAANQADCgYICwAAAA==.',
Ad='Aderrig:BAAANQADCgQIBAAAAA==.Adriana:BAAANQADCggIDgAAAA==.Adrianix:BAAANQADCgMIBAAAAA==.Adru:BAAANQADCgcICgAAAA==.',
Ae='Aeglos:BAAANQAECgQIBQAAAA==.Aehrick:BAAANQADCgQIBgAAAA==.Aentharion:BAAANQADCgcIDAAAAA==.',
Ai='Aileen:BAAANQADCgUICAAAAA==.',
Al='Alisonia:BAAANQADCgIIAgAAAA==.Alliancepaly:BAAANQADCgMIAwAAAA==.Alorren:BAAANQADCgUICgAAAA==.Aludor:BAAANQADCgEIAQAAAA==.',
Am='Ammo:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.Amo:BAAANQABCgQICQABNQAECgIIAgABAAAAAA==.Amodillo:BAAANQAECgIIAgAAAA==.Amonra:BAAANQADCgYICQAAAA==.',
An='Angyaras:BAABNQAECoEZAAICAAkJ3CUJAADzAwACAAkJ3CUJAADzAwAAAA==.Animos:BAAANQADCgMIAwAAAA==.',
Ap='Apiix:BAAANQADCggICAAAAA==.',
Ar='Araaras:BAAANQAFFAEIAQAAAA==.Araiguma:BAAANQAECgcIDQAAAA==.Arcticsnow:BAAANQADCgYICwAAAA==.Arkose:BAAANQADCgQIBAAAAA==.',
As='Aschen:BAAANQADCgIIAwAAAA==.Ashlynne:BAAANQAECgYICQAAAA==.Aspensong:BAAANQADCgcIDAAAAA==.Astracious:BAAANQADCgYIDAAAAA==.Astrayice:BAAANQADCgEIAQAAAA==.',
At='Atarkormu:BAAANQADCgQIBAABNQADCggIDgABAAAAAA==.Atax:BAAANQADCgcIDAAAAA==.Athená:BAAANQAECgEIAQAAAA==.Atulkan:BAAANQADCgYICwAAAA==.',
Au='Aurelitrasza:BAAANQADCgQIBAAAAA==.',
Av='Avrice:BAAANQADCgUIBQAAAA==.',
Ba='Bambu:BAAANQADCgMIAwABNQADCgYICgABAAAAAA==.Bamevoker:BAAANQADCgYICgAAAA==.Bariggs:BAAANQAECgMIAwAAAA==.Barilia:BAAANQADCgEIAQAAAA==.',
Be='Beals:BAAANQADCgcIDAAAAA==.Beladra:BAAANQADCgQIBAAAAA==.Ben:BAAANQAECgIIAgAAAA==.Beriadan:BAAANQAECgMIAwAAAA==.Bevee:BAAANQAECgUIBQAAAA==.',
Bi='Bisque:BAAANQADCgUIBQAAAA==.',
Bl='Bleddwen:BAAANQADCgcIDAAAAQ==.Blrsama:BAAANQADCgUIBQAAAA==.',
Bo='Bohrnir:BAAANQADCgUIBQAAAA==.Boozelee:BAAANQADCgMIAwAAAA==.Boüh:BAAANQADCgUIBQAAAA==.',
Bu='Bubblesonyou:BAAANQAECgEIAQAAAA==.Burnadine:BAAANQADCgUIBQAAAA==.',
Ca='Caliie:BAAANQADCgcIDAAAAA==.Callektra:BAAANQADCgEIAQAAAA==.Callira:BAAANQADCgYIBgAAAA==.Captclamslam:BAAANQADCgYIBgAAAA==.Cayuga:BAAANQADCgMIAwAAAA==.',
Ch='Charå:BAAANQADCgUIBQAAAA==.Chintakari:BAAANQADCgUIBQAAAA==.',
Co='Cocidiae:BAAANQADCgQIBAAAAA==.Confusious:BAAANQAECgYICAAAAA==.Coree:BAAANQADCgYIGgAAAA==.Cornflower:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.Corvaan:BAAANQAECgQIBQAAAA==.',
Cr='Creg:BAAANQADCgcICwAAAA==.Crowbarr:BAAANQADCgMIBQAAAA==.Cryostatic:BAAANQADCgQIBAABNQADCgUIBQABAAAAAA==.',
Cu='Cultel:BAAANQADCggIDwAAAA==.',
Cy='Cyendia:BAAANQADCggIDgAAAA==.Cynlea:BAAANQADCgYIBgAAAA==.',
Da='Daddyraz:BAAANQADCgUICQAAAA==.Daphcelyn:BAAANQADCgUICQAAAA==.Dariusz:BAAANQADCggIDgAAAA==.Darkalen:BAAANQADCggIDgAAAA==.Darklodus:BAAANQADCgYICwAAAA==.Darksethia:BAAANQADCgQIBAAAAA==.Dathea:BAAANQAECgcIDAAAAA==.Daxetanlock:BAAANQAECgUIBQAAAA==.Daxetans:BAAANQAECgIIAgAAAA==.',
De='Deathb:BAAANQADCgEIAQAAAA==.Deathjingle:BAAANQAECgQICAAAAA==.Deecayed:BAAANQADCgYICwABNQAECgMIBgABAAAAAA==.Deecoy:BAAANQADCggIDAABNQAECgMIBgABAAAAAA==.Deemonic:BAAANQADCgYIBgABNQAECgMIBgABAAAAAA==.Deetermined:BAAANQAECgMIBgAAAA==.Denchy:BAAANQADCgcIDAAAAA==.Deylen:BAAANQADCgcIDAAAAA==.Deyndine:BAAANQADCgYICwAAAA==.',
Di='Dizzyglaive:BAAANQADCgUIBwAAAA==.',
Dm='Dmrwr:BAAANQADCgYIBgAAAA==.',
Dr='Draelick:BAAANQABCgIIAgAAAA==.Droataxm:BAAANQAECgUIBwAAAA==.Drogath:BAAANQADCgcIDQAAAA==.',
Du='Duarraag:BAAANQADCgMIAwAAAA==.',
['Dâ']='Dâvïd:BAAANQAECgIIAgAAAA==.',
['Dë']='Dëërez:BAAANQADCgcIDQABNQAECgMIBgABAAAAAA==.',
Ei='Eililis:BAAANQADCgYIBgAAAA==.',
El='Elani:BAAANQADCgYIBgABNQADCggIDgABAAAAAA==.Elaynaa:BAAANQADCgcIDAAAAA==.Elishaunt:BAAANQADCgUICQAAAA==.Elliana:BAAANQADCgYIEAABNQADCggIDgABAAAAAA==.',
Em='Emanymton:BAAANQADCgUICQAAAA==.',
En='Endb:BAAANQADCgIIAgAAAA==.',
Er='Erisaria:BAAANQADCgYIBAAAAA==.Erixi:BAAANQADCgcIDAAAAA==.Eryn:BAAANQADCgEIAQAAAA==.',
Es='Esaria:BAAANQADCgEIAQAAAA==.',
Ev='Evissier:BAAANQAECgMIAwAAAA==.',
Ex='Excelimagust:BAAANQADCgQICAAAAA==.',
Fa='Falcdhruid:BAAANQADCgUICQAAAA==.Farundi:BAAANQADCgUIBQAAAA==.',
Fe='Felwit:BAAANQADCggIDgAAAA==.Fennec:BAAANQADCggIDQAAAA==.Feralie:BAAANQADCgYIBgAAAA==.',
Fl='Flatline:BAAANQADCgcIDAAAAA==.Florabelle:BAAANQAECgEIAQAAAA==.Florid:BAAANQADCgcIDQAAAA==.',
Fo='Foshomomo:BAAANQADCgcIDAAAAA==.Fozzle:BAAANQADCggIDwAAAA==.',
Fr='Frenndi:BAAANQADCgUIBQAAAA==.',
Fu='Fuknazuga:BAAANQAECgMIAwAAAA==.Furroz:BAAANQADCgYIBgABNQADCggIDgABAAAAAA==.',
Fy='Fynedge:BAAANQADCggIDgAAAA==.Fynnyntyss:BAAANQADCggIDwAAAA==.Fyrè:BAAANQADCggIDwAAAA==.',
Ge='Gerlock:BAAANQADCgEIAQAAAA==.',
Gi='Gigatin:BAAANQADCgUICgAAAA==.Githnor:BAAANQADCggIDwAAAA==.',
Gr='Grum:BAAANQADCgQIBAAAAA==.Grunaelyn:BAAANQADCgUICgAAAA==.',
Gu='Guerrier:BAAANQADCgcIBwAAAA==.Guiong:BAAANQABCgIIAgAAAA==.',
['Gö']='Göttlich:BAAANQADCgUIBQABNQADCgUIBwABAAAAAA==.',
He='Heikuro:BAAANQADCgcIDAAAAA==.Heybestie:BAAANQADCggICAAAAA==.',
Ho='Holychonks:BAAANQADCgUIBQAAAA==.Honadain:BAAANQADCgUIBwAAAA==.Hordestalker:BAAANQADCgUIBQAAAA==.Houtu:BAAANQAECgEIAQAAAA==.',
Hw='Hweilan:BAAANQADCgMIAwAAAA==.',
Hy='Hypnos:BAAANQADCgQICAAAAA==.',
['Hö']='Hölyföx:BAAANQAECgEIAQAAAA==.',
Ia='Iamearl:BAAANQADCgcICgAAAA==.',
In='Incidental:BAAANQAECgUIBwAAAA==.Inconell:BAAANQADCgUIBQAAAA==.Invega:BAAANQADCgYIBwAAAA==.',
Ir='Irino:BAAANQADCgUIBQAAAA==.',
Is='Isabelle:BAAANQADCgQICAAAAA==.',
Iz='Izaer:BAAANQADCgYIFgAAAA==.',
Ja='Jabzaklok:BAAANQADCgYICQAAAA==.Jacky:BAAANQAECgYICQAAAA==.Jahirah:BAAANQADCgUICgAAAA==.Jaida:BAAANQAECgIIAgAAAA==.Jaleika:BAAANQADCgUIBwAAAA==.Jarius:BAAANQADCgcICgAAAA==.',
Je='Jean:BAAANQAECgQIBQAAAA==.Jeez:BAAANQADCgcIDgAAAA==.',
Jo='Johadd:BAAANQADCgEIAQAAAA==.Jorianna:BAAANQADCgQIBAAAAA==.Joru:BAAANQAFFAMIAwAAAA==.',
Ka='Kabaul:BAAANQAECgUIBwAAAA==.Kabir:BAAANQADCggIDAAAAA==.Kadria:BAAANQADCgcIDAAAAA==.Kalaman:BAAANQADCgQICAAAAA==.Kalito:BAAANQADCgEIAQAAAA==.Kamb:BAAANQADCgcIDAAAAA==.Karalee:BAAANQADCgYICwAAAA==.Katieey:BAAANQAFFAQIBAAAAA==.Kaybee:BAAANQADCgQICAAAAA==.Kayil:BAAANQADCggIDwAAAA==.',
Ke='Kedalin:BAAANQADCgUICQAAAA==.Kennyloggy:BAAANQAFFAEIAQAAAA==.Keydan:BAAANQADCgcIDAAAAA==.',
Kl='Klassy:BAAANQADCggIDgAAAA==.',
Ko='Koppi:BAAANQADCgQIBQAAAA==.Korru:BAAANQADCgUICQAAAA==.Kotie:BAAANQADCgQIBQAAAA==.',
Kr='Kramz:BAAANQADCgcIBwAAAA==.Kronar:BAAANQADCgYIEgAAAA==.Krumblo:BAEANQADCgYIEgABNQADCgcIBwABAAAAAA==.Kryztof:BAAANQABCgQIAgAAAA==.',
Ku='Kunea:BAAANQADCgYIBgAAAA==.Kungfujace:BAAANQADCgYICwAAAA==.',
Ky='Kyrgune:BAAANQADCgUIBQAAAA==.',
La='Laoftey:BAAANQADCggIBwAAAA==.Larquin:BAAANQADCgUICgAAAA==.Lasmori:BAAANQADCggIDgAAAA==.Laurenorder:BAAANQADCgUICgAAAA==.Laxxbroo:BAAANQADCgQIBgAAAA==.',
Le='Leam:BAAANQADCgcIDQAAAA==.Leglock:BAAANQADCgcIDQAAAA==.',
Li='Liendria:BAAANQADCggIDgAAAA==.Lifensoftpaw:BAAANQAECgcIDQAAAA==.Lightemup:BAAANQAECgIIAgAAAA==.Lightkeeper:BAAANQABCgQIAgAAAA==.Linthabeela:BAAANQADCgEIAQAAAA==.Liquidchiken:BAAANQADCggIDgAAAA==.Lishalthen:BAAANQADCggIDwAAAA==.Littletouch:BAAANQADCgIIAgAAAA==.',
Lu='Lucielinna:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Luckiiem:BAAANQADCggIDwAAAA==.Luisfriendsn:BAAANQADCgIIAgABNQAECgUIBwABAAAAAA==.Lunare:BAAANQADCgUIBQAAAA==.Lunarkin:BAAANQADCgUIBwAAAA==.Luthane:BAAANQADCgcIDAAAAA==.',
Ly='Lykinea:BAAANQADCgQIBAAAAA==.Lytebrite:BAAANQADCggICAAAAA==.',
['Lü']='Lümßo:BAEANQADCgcIBwAAAA==.',
Ma='Makishi:BAAANQADCgcIDAAAAA==.Malfura:BAAANQADCgYICwAAAA==.Malário:BAAANQAECgIIAgAAAA==.Mattedfurry:BAAANQAECgIIAgAAAA==.Mazzarzul:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.',
Me='Meebles:BAAANQADCggIDwAAAA==.Meiana:BAAANQADCggIDgAAAA==.Melasmus:BAAANQABCgQIBgAAAA==.Mes:BAAANQADCgYICAAAAA==.',
Mi='Micklaa:BAAANQADCgcICwAAAA==.Milkbunny:BAAANQADCgUIBQAAAA==.Mingtai:BAAANQADCgUIBwAAAA==.',
Mo='Moirrah:BAAANQADCgYIBgAAAA==.Moonriver:BAAANQADCggIDwAAAA==.Moonsinde:BAAANQADCgYICwAAAA==.Moranta:BAAANQADCgYIBgAAAA==.Moressandra:BAAANQADCgUIBQAAAA==.Morgaes:BAAANQADCgQIBgAAAA==.Morîarty:BAAANQADCgIIAgAAAA==.',
My='Mysticmurv:BAAANQAECgQIBQAAAA==.Mywarlock:BAAANQAECgYICAAAAA==.',
Na='Nalgotica:BAAANQADCgMIAwAAAA==.Nalynahwe:BAAANQADCgYICQAAAA==.Narima:BAAANQADCgYIBgAAAA==.Nathronso:BAAANQADCgUIBQAAAA==.Nauticâ:BAAANQABCgMIAQAAAA==.Navirose:BAAANQADCgcIBwAAAA==.',
Ne='Necromos:BAAANQADCggIBgAAAA==.',
Nh='Nhala:BAAANQADCgUIBQAAAA==.',
Ni='Nightestrike:BAAANQADCgYICwAAAA==.Nivek:BAAANQADCgQIBAAAAA==.',
No='Nore:BAAANQADCgUICQAAAA==.',
['Nà']='Nàdya:BAAANQAECgMIAwAAAA==.',
Ob='Oblivions:BAAANQADCggIDwAAAA==.',
Od='Odasa:BAAANQADCgYICwAAAA==.',
On='Onekark:BAAANQAECgIIAwAAAA==.Onlysins:BAAANQADCgcICwAAAA==.',
Or='Orckus:BAAANQADCgQICAAAAA==.Oreosbunny:BAAANQADCggIDwAAAA==.Orìhimè:BAAANQABCgQIBAAAAA==.',
Pa='Pandaburn:BAAANQADCggICgAAAA==.Paroxism:BAAANQAECgUIBwAAAA==.',
Pe='Peanût:BAAANQADCgcIDAAAAA==.Peautiful:BAAANQADCgEIAQAAAA==.',
Ph='Phaket:BAAANQAECgEIAQAAAA==.',
Pi='Picaduro:BAAANQADCgYICQAAAA==.Picture:BAAANQADCgYICwABNQAECgYICAABAAAAAA==.Pippá:BAAANQADCgcIBwAAAA==.',
Po='Polonius:BAAANQADCgYICAAAAA==.Potato:BAAANQADCgIIAgAAAA==.',
Pr='Probation:BAAANQADCgMIAwAAAA==.',
Pu='Puchideperro:BAAANQADCgEIAQAAAA==.',
Pw='Pwil:BAAANQABCgMIAgABNQABCgQIBAABAAAAAA==.',
Py='Pythe:BAAANQADCggIDwAAAA==.',
Qa='Qap:BAAANQAECgIIAgAAAA==.',
Qi='Qingu:BAAANQAECgEIAQAAAA==.',
Qu='Qualnorr:BAAANQADCgUICAAAAA==.Queldraayan:BAAANQADCgYIBgAAAA==.Quinnter:BAEANQADCgcIDQAAAA==.',
Qw='Qwil:BAAANQABCgQIBAAAAA==.',
Ra='Radagon:BAAANQAECgEIAQABNQADCggIDgABAAAAAA==.Radalas:BAAANQADCgcIDQAAAA==.Radreliris:BAAANQADCgUIBwAAAA==.Rainlight:BAAANQADCgUIBQAAAA==.Ramcco:BAEANQADCgcIDQAAAA==.Ranelle:BAAANQADCggIDwAAAA==.Rasmira:BAAANQADCgYICQAAAA==.Ravenis:BAAANQAECgIIAgAAAA==.',
Re='Reedem:BAAANQADCgcIDAAAAA==.Regilock:BAAANQAFFAIIAgAAAA==.Reikí:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.',
Rh='Rhaenyrra:BAAANQADCgYIBgAAAA==.Rhaily:BAAANQADCgIIAgAAAA==.Rhallin:BAAANQADCgcIDAAAAA==.',
Ro='Ronso:BAAANQADCgQIBAAAAA==.Rowain:BAAANQADCggICQAAAA==.',
Ry='Rylacus:BAAANQADCgcIDAAAAA==.Rylii:BAAANQADCggIDgAAAA==.',
Sa='Saanda:BAAANQADCgYICAAAAA==.Sarlef:BAAANQADCggIDgAAAA==.',
Sc='Scarm:BAAANQAECgIIAgAAAA==.',
Se='Seaflower:BAAANQADCgYIBQAAAA==.Sellidra:BAAANQADCgcIDQAAAA==.Serenitara:BAAANQADCgQIBgAAAA==.',
Sh='Shaffer:BAAANQADCgEIAQAAAA==.Shellshocker:BAAANQAECgMIBwAAAA==.Sheng:BAAANQADCgUIBQAAAA==.Shermantånk:BAAANQADCgYICAAAAA==.Shikigamï:BAAANQADCgcICQABNQADCgYIBwABAAAAAA==.Shikï:BAAANQADCgYIBwAAAA==.Shivermoón:BAAANQAECgIIAgAAAA==.',
Si='Sigesar:BAAANQADCgcIDAAAAA==.',
Sk='Skullash:BAAANQADCgcIBwAAAA==.Skywatcher:BAAANQADCgcIDAAAAA==.',
So='Solare:BAAANQADCgMIAwAAAA==.Sonwarr:BAAANQAECgEIAQAAAA==.Soulriser:BAAANQADCgQIBAAAAA==.',
Sp='Spliphtoker:BAAANQADCgcIEgAAAA==.',
St='Steelpen:BAAANQAECgEIAQAAAA==.Stenston:BAAANQADCgYICwAAAA==.Sterede:BAAANQADCgUICQAAAA==.Stitchwhich:BAAANQADCgYICgAAAA==.Stonehenge:BAAANQADCgcIDQAAAA==.Stormb:BAAANQADCgQIBwAAAA==.',
Sy='Sylphwild:BAAANQADCggICwABNQAECgcIBwABAAAAAA==.Sylvara:BAAANQADCgYICgAAAA==.Synkinz:BAAANQADCgcICwAAAA==.Syntec:BAAANQABCgIIAgAAAA==.Syreite:BAAANQADCggIDgAAAA==.',
Ta='Tacori:BAAANQADCgUIBwAAAA==.Taessa:BAAANQADCgMIAwAAAA==.Tallic:BAAANQADCggIDwAAAA==.Talynayl:BAAANQADCgUIBwAAAA==.Tandemonium:BAAANQADCgIIAgABNQAECgUIBwABAAAAAA==.Tarsi:BAAANQADCgYICwAAAA==.',
Te='Telidrel:BAAANQADCgEIAQAAAA==.',
Th='Thaddeaus:BAAANQAECgIIAgAAAA==.Thaddeus:BAAANQADCgcIDAAAAA==.Thebeefyone:BAAANQADCgYIFwAAAA==.Thecanadian:BAAANQADCgQIBAAAAA==.Thesummoner:BAAANQAECgEIAQAAAA==.Thorrek:BAAANQADCgMIAwAAAA==.Thumpette:BAAANQADCgYIGAAAAA==.',
Ti='Tierant:BAAANQADCgEIAQAAAA==.Tizaria:BAAANQADCgcICwAAAA==.',
To='Tominaetor:BAAANQADCgcIHQAAAA==.Tosoto:BAAANQAECgEIAQAAAA==.',
Tr='Travcula:BAAANQAECgEIAQAAAA==.Treefiddy:BAAANQADCgEIAgAAAA==.',
Ts='Tso:BAAANQADCgEIAQAAAA==.',
Tt='Ttriton:BAAANQADCgEIAQAAAA==.',
Tu='Tuuwa:BAAANQADCgMIAwAAAA==.',
Ty='Tyernan:BAAANQADCggIDgAAAA==.Tyrioz:BAAANQADCgUICgAAAA==.',
Tz='Tzavcat:BAAANQADCgcIDAAAAA==.',
Uh='Uhtred:BAAANQAECggIAQAAAA==.',
Ur='Urbi:BAAANQADCgYIBgAAAA==.',
Uv='Uvsol:BAAANQADCgQIBAAAAA==.',
Va='Vadailla:BAAANQADCgYICwAAAA==.Valius:BAAANQADCggIDgAAAA==.Valkyrae:BAAANQADCgQIBAAAAA==.Valornor:BAAANQADCgIIAgAAAA==.Vandill:BAAANQAECgQIBAAAAA==.',
Ve='Veasnacool:BAAANQAECgIIAgAAAA==.Vestrit:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.',
Vo='Vontote:BAAANQADCggIDgAAAA==.',
['Ví']='Víc:BAAANQADCgcIDAAAAA==.',
Wa='Wandorf:BAEANQADCgYICwAAAA==.Warwolfe:BAAANQADCggIDgAAAA==.',
Wh='Whumpus:BAAANQADCgIIAgAAAA==.',
Wi='Willei:BAAANQADCgQIBwAAAA==.',
Wo='Wolferunner:BAAANQADCgYICwAAAA==.',
Xa='Xaiden:BAAANQADCgcIBwAAAA==.',
Xd='Xdxvuu:BAAANQAECgEIAQAAAA==.',
Xe='Xerimok:BAAANQADCgcIDAAAAA==.',
Xi='Xinya:BAAANQADCgUICgAAAA==.',
Xz='Xzephyr:BAAANQADCggIDwAAAA==.',
Ye='Yesmín:BAAANQAECgEIAQAAAA==.',
Yi='Yil:BAAANQADCggICAAAAA==.',
Yo='Youwas:BAAANQAECgEIAQAAAA==.',
Yu='Yukmouf:BAAANQADCggICAAAAA==.Yuriika:BAAANQADCgYIBwAAAA==.',
Za='Zakaris:BAAANQADCgYIBgAAAA==.Zarrove:BAAANQADCggIDwAAAA==.',
Ze='Zeltri:BAAANQAECgEIAgAAAA==.Zerg:BAAANQADCgIIAgAAAA==.',
Zh='Zhatva:BAAANQAECgUIBwAAAA==.Zhöe:BAAANQADCgcIDQAAAA==.',
Zi='Zimzhealz:BAAANQADCgUIBQAAAA==.Zimzorzz:BAAANQADCgIIAgABNQADCgUIBQABAAAAAA==.',
Zo='Zoldor:BAAANQADCgcIDAAAAA==.Zorellion:BAAANQADCgcICgAAAA==.',
Zu='Zuay:BAAANQADCgIIAgABNQAECgQIBAABAAAAAA==.Zulianguy:BAAANQAECgQIBAAAAA==.',
Zy='Zycorr:BAAANQAECgEIAQAAAA==.',
['Ñÿ']='Ñÿx:BAAANQADCgcIDAAAAA==.',
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
