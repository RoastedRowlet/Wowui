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

local lookup = {'Unknown-Unknown','Warrior-Protection','Shaman-Restoration','Shaman-Enhancement','Druid-Balance','Monk-Windwalker','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Hunter-Marksmanship',}
local provider = {region='US',realm='ArgentDawn',name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Abajaba:BAAANQADCgYICgAAAA==.Abractus:BAAANQAECgEIAQAAAA==.',
Ad='Aderrig:BAAANQADCgQIBAAAAA==.Adriana:BAAANQADCggIFgAAAA==.Adrianix:BAAANQADCgYICgAAAA==.Adru:BAAANQADCggIEgAAAA==.',
Ae='Aeglos:BAAANQAECgcIDAAAAA==.Aehrick:BAAANQADCgUICAAAAA==.Aentharion:BAAANQADCgcIEwAAAA==.',
Ai='Aileen:BAAANQAECgQIBAAAAA==.',
Al='Alidoro:BAAANQADCgEIAQAAAA==.Alisonia:BAAANQADCgIIBAAAAA==.Alleximage:BAAANQAECgIIAQAAAA==.Alliancepaly:BAAANQADCgMIAwAAAA==.Alorren:BAAANQAECgEIAQAAAA==.Aludor:BAAANQADCgEIAQAAAA==.',
Am='Ammo:BAAANQADCgUICgABNQAECgQIBgABAAAAAA==.Amo:BAAANQABCgYIEAABNQAECgQIBgABAAAAAA==.Amodillo:BAAANQAECgQIBgAAAA==.Amonra:BAAANQADCgYICQAAAA==.Amynrar:BAAANQADCggICAAAAA==.',
An='Angyaras:BAACNQAFFIEFAAICAAQJCh07AACVAQACAAQJCh07AACVAQA1AAQKgRkAAgIACQncJS8AAOUDAAIACQncJS8AAOUDAAAA.Animos:BAAANQADCgMIAwAAAA==.',
Ap='Apiix:BAAANQAECgQIBAAAAA==.',
Ar='Araaras:BAAANQAFFAEIAQAAAA==.Araiguma:BAAANQAECgcIDQAAAA==.Arcticsnow:BAAANQADCgYIEQAAAA==.Ariealla:BAAANQADCgUIBQAAAA==.Arkose:BAAANQADCgQIBAAAAA==.',
As='Aschen:BAAANQADCgIIAwAAAA==.Ashlyngrace:BAAANQAECgIIAgABNQAECgcIEAABAAAAAA==.Ashlynne:BAAANQAECgcIEAAAAA==.Aspensong:BAAANQADCgcIEwAAAA==.Astracious:BAAANQADCggIGgAAAA==.Astrayice:BAAANQADCgQIBQAAAA==.',
At='Atarkormu:BAAANQADCgQICAABNQAECgMIAwABAAAAAA==.Atax:BAAANQADCgcIEwAAAA==.Athená:BAAANQAECgEIAQAAAA==.Atulkan:BAAANQADCgcIDAAAAA==.',
Au='Auralyn:BAAANQADCgMIAwAAAA==.Aurelitrasza:BAAANQADCgUICQAAAA==.',
Av='Avrice:BAAANQADCgYICwAAAA==.',
Ay='Ayayaras:BAAANQAFFAEIAQABNQAFFAQIBQACAAodAA==.',
Ba='Bambu:BAAANQADCgYICQABNQADCgcIEQABAAAAAA==.Bamevoker:BAAANQADCgcIEQAAAA==.Bariggs:BAAANQAECgUICAAAAA==.Barilia:BAAANQADCgEIAQAAAA==.',
Be='Beals:BAAANQADCgcIEwAAAA==.Beladra:BAAANQADCgQIBQAAAA==.Ben:BAAANQAECgMIBQAAAA==.Beriadan:BAAANQAECgUICAAAAA==.Bevee:BAAANQAECgYICgAAAA==.',
Bi='Bisque:BAAANQADCgUIBQAAAA==.',
Bl='Bleddwen:BAAANQADCggIFAAAAQ==.Blindseer:BAAANQABCgIIAgAAAA==.Blrsama:BAAANQADCgUIBQAAAA==.',
Bo='Bohrnir:BAAANQADCgUIBQAAAA==.Boozelee:BAAANQADCgMIAwAAAA==.Boüh:BAAANQADCggIDQAAAA==.',
Br='Brutalix:BAAANQADCgEIAQAAAA==.',
Bu='Bubblesonyou:BAAANQAECgIIAwAAAA==.Burnadine:BAAANQADCggIDQAAAA==.',
Ca='Caliie:BAAANQADCgcIEwAAAA==.Callektra:BAAANQADCgUIBQAAAA==.Callira:BAAANQADCgYIBgAAAA==.Captclamslam:BAAANQADCgYICgAAAA==.Cayuga:BAAANQADCgMIAwAAAA==.',
Ch='Charå:BAAANQADCgUIBQAAAA==.Chintakari:BAAANQADCgcIBwAAAA==.',
Co='Cocidiae:BAAANQADCgQIBAAAAA==.Confusious:BAAANQAECgcIDwAAAA==.Coppers:BAAANQADCggICAAAAA==.Coree:BAAANQADCggIIgAAAA==.Cornflower:BAAANQADCgMIAwABNQAECgIIAwABAAAAAA==.Corvaan:BAAANQAECgcIDAAAAA==.',
Cr='Creg:BAAANQADCgcIEgAAAA==.Crowbarr:BAAANQADCgYICwAAAA==.Cryostatic:BAAANQADCgQIBAABNQADCggIDAABAAAAAA==.',
Cu='Cultel:BAAANQAECgQIBAAAAA==.',
Cy='Cyendia:BAAANQADCggIFgAAAA==.Cynlea:BAAANQADCgYIBgAAAA==.',
Da='Daddyraz:BAAANQADCgUICQAAAA==.Daemonquiver:BAAANQADCgUIBQAAAA==.Daphcelyn:BAAANQADCgYIDwAAAA==.Dariusz:BAAANQADCggIFgAAAA==.Darkalen:BAAANQAECgMIAwAAAA==.Darklodus:BAAANQADCgYICwAAAA==.Darksethia:BAAANQADCgQIBAAAAA==.Dathea:BAABNQAECoEXAAIDAAkJ7x0SBQA9AwADAAkJ7x0SBQA9AwAAAA==.Daxetanlock:BAAANQAECgcIDAAAAA==.Daxetans:BAAANQAECgIIAgAAAA==.',
De='Deathb:BAAANQADCgYIBwAAAA==.Deathjingle:BAAANQAECggIDwAAAA==.Deecayed:BAAANQADCgYICwABNQAECgYIDAABAAAAAA==.Deecoy:BAAANQADCggIDAABNQAECgYIDAABAAAAAA==.Deemonic:BAAANQADCggIDgABNQAECgYIDAABAAAAAA==.Deerslayer:BAAANQABCgIIAgAAAA==.Deetermined:BAAANQAECgYIDAAAAA==.Denchy:BAAANQAECgEIAQAAAA==.Deylen:BAAANQADCgcIEwAAAA==.Deyndine:BAAANQAECgEIAQAAAA==.',
Di='Dizzyglaive:BAAANQADCgYIDQAAAA==.',
Dm='Dmrwr:BAAANQAECgUIBAAAAA==.',
Do='Dottarus:BAAANQADCgUIBQABNQADCgUICAABAAAAAA==.',
Dr='Draelick:BAAANQABCgIIAgAAAA==.Driadora:BAAANQADCggICAAAAA==.Droataxm:BAAANQAECgcIDgAAAA==.Drogath:BAAANQADCgcIDQAAAA==.',
Du='Duarraag:BAAANQADCgYICQAAAA==.',
['Dâ']='Dâvïd:BAAANQAECgQIBgAAAA==.',
['Dë']='Dëërez:BAAANQADCggIFQABNQAECgYIDAABAAAAAA==.',
Ei='Eililis:BAAANQADCgYIBwAAAA==.',
El='Elani:BAAANQAECgUIBQAAAA==.Elaynaa:BAAANQADCggIFAAAAA==.Elishaunt:BAAANQAECgEIAQAAAA==.Elliana:BAAANQAECgEIAQAAAA==.Elvoidra:BAAANQABCgMIAwAAAA==.',
Em='Emanymton:BAAANQADCgUIDgAAAA==.Embyr:BAAANQADCgcIBwAAAA==.',
En='Endb:BAAANQADCgMIAwAAAA==.',
Er='Erisaria:BAAANQADCgYIBAAAAA==.Erixi:BAAANQADCggIFAAAAA==.Eryn:BAAANQADCgEIAQAAAA==.',
Es='Esaria:BAAANQADCgEIAQAAAA==.',
Ev='Evissier:BAAANQAECgYICQAAAA==.',
Ex='Excelimagust:BAAANQADCgQICAAAAA==.',
Fa='Falcdhruid:BAAANQADCgUICQAAAA==.Farundi:BAAANQADCgUIBQAAAA==.',
Fe='Felwit:BAAANQAECgQIBAAAAA==.Fennec:BAAANQADCggIFQAAAA==.Feralie:BAAANQADCgYIBgAAAA==.Ferroz:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.',
Fl='Flamos:BAAANQAECgQIBAAAAA==.Flatline:BAAANQAECgEIAQAAAA==.Florabelle:BAAANQAECgIIAwAAAA==.Florid:BAAANQADCggIFQAAAA==.',
Fo='Foshomomo:BAAANQADCgcIEwAAAA==.Fozzle:BAAANQAECgMIAwAAAA==.',
Fr='Frenndi:BAAANQADCgYICwAAAA==.',
Fu='Fuknazuga:BAAANQAECgQIBwAAAA==.Furroz:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.',
Fy='Fynedge:BAAANQAECgMIAwAAAA==.Fynnyntyss:BAAANQAECgQIBAAAAA==.Fyrè:BAAANQAECgQIBAAAAA==.',
Ga='Garthe:BAAANQADCgEIAQAAAA==.',
Ge='Gerlock:BAAANQADCgUIBgAAAA==.',
Gi='Gigatin:BAAANQAECgEIAQAAAA==.Githnor:BAAANQAECgQIBAAAAA==.',
Go='Gorellan:BAAANQADCgYIBgAAAA==.',
Gr='Grimwharf:BAAANQADCgUIBQAAAA==.Grum:BAAANQADCgQIBAAAAA==.Grunaelyn:BAAANQAECgEIAQAAAA==.',
Gu='Guerrier:BAAANQADCgcIBwAAAA==.Guiong:BAAANQADCgYIBgAAAA==.',
Gy='Gynx:BAAANQADCgUIBQAAAA==.',
['Gö']='Göttlich:BAAANQADCgUIBQABNQADCgUIBwABAAAAAA==.',
He='Heikuro:BAAANQADCggIFAAAAA==.Heybestie:BAAANQADCggICAAAAA==.',
Ho='Holychonks:BAAANQADCgYICQAAAA==.Honadain:BAAANQADCgYIDQAAAA==.Hordestalker:BAAANQADCgUIBQAAAA==.Houtu:BAAANQAECgQIBQAAAA==.',
Hw='Hweilan:BAAANQADCgYICQAAAA==.',
Hy='Hydrokill:BAAANQADCggICAAAAA==.Hypnos:BAAANQADCgYIDgAAAA==.',
['Hö']='Hölyföx:BAAANQAECgEIAQAAAA==.',
Ia='Iamearl:BAAANQADCggIEwAAAA==.',
In='Incidental:BAAANQAECgcIDgAAAA==.Inconell:BAAANQAECgQIBAAAAA==.Invega:BAAANQAECgIIAgAAAA==.',
Ir='Iric:BAAANQADCgMIAwAAAA==.Irino:BAAANQADCgUIBQAAAA==.',
Is='Isabelle:BAAANQAECgEIAgAAAA==.',
Iz='Izaer:BAAANQADCggIJgAAAA==.',
Ja='Jabzaklok:BAAANQADCgcIEAAAAA==.Jacky:BAAANQAFFAEIAQAAAA==.Jahirah:BAAANQAECgEIAQAAAA==.Jaida:BAAANQAECgIIBAAAAA==.Jaleika:BAAANQAECgMIAwAAAA==.Jarius:BAAANQADCgcIEQAAAA==.',
Je='Jean:BAAANQAECgYICwAAAA==.Jeez:BAAANQAECgIIAgAAAA==.Jesmaríe:BAAANQADCggICAAAAA==.',
Jo='Johadd:BAAANQADCgEIAQAAAA==.Jorianna:BAAANQADCggIDAAAAA==.Joru:BAACNQAFFIEJAAIEAAUJoxgdAAD2AQAEAAUJoxgdAAD2AQA1AAQKgRoAAgQACQmVJWgAAMQDAAQACQmVJWgAAMQDAAAA.',
Ka='Kabaul:BAAANQAECgcIDgAAAA==.Kabir:BAAANQAECgEIAQAAAA==.Kadria:BAAANQADCggIFAAAAA==.Kailanii:BAAANQAECgEIAQAAAA==.Kalaman:BAAANQADCgQICAAAAA==.Kalito:BAAANQADCgMIAwAAAA==.Kamb:BAAANQADCgcIDQAAAA==.Karalee:BAAANQADCgYIEQAAAA==.Katieey:BAABNQAFFIEKAAIDAAUJqiSfAAAJAgADAAUJqiSfAAAJAgAAAA==.Kaybee:BAAANQADCgYIDgAAAA==.Kayde:BAAANQADCgUIBQAAAA==.Kayil:BAAANQAECgQIBAAAAA==.',
Ke='Kedalin:BAAANQADCgYIDwAAAA==.Kennyloggy:BAABNQAECoEYAAIFAAkJ+SKoBABqAwAFAAkJ+SKoBABqAwAAAA==.Keydan:BAAANQADCggIFAAAAA==.',
Kh='Khorunn:BAAANQADCgQIBAAAAA==.',
Kl='Klassy:BAAANQAECgQIBAAAAA==.',
Ko='Koppi:BAAANQADCgYICwAAAA==.Korru:BAAANQADCgUIDQAAAA==.Kotie:BAAANQADCgQIBQAAAA==.',
Kr='Kramz:BAAANQADCgcIBwAAAA==.Kronar:BAAANQADCggIIAAAAA==.Krumblo:BAEANQADCggIGgABNQAECgIIAgABAAAAAA==.Kryztof:BAAANQABCgQIAgAAAA==.',
Ku='Kunea:BAAANQADCgYIBgAAAA==.Kungfujace:BAAANQADCgYICwAAAA==.',
Ky='Kyrgune:BAAANQADCgYICwAAAA==.',
La='Laoftey:BAAANQAECgQIBAAAAA==.Larquin:BAAANQAECgEIAQAAAA==.Laurenorder:BAAANQADCgcIDAABNQAECgEIAQABAAAAAA==.Laxxbroo:BAAANQADCgQIBgAAAA==.',
Le='Leam:BAAANQADCggIFQAAAA==.Leglock:BAAANQADCggIFQAAAA==.',
Li='Liendria:BAAANQAECgEIAQAAAA==.Lifensoftpaw:BAABNQAECoEYAAIGAAkJ7iJsAgBlAwAGAAkJ7iJsAgBlAwAAAA==.Lightemup:BAAANQAECgIIAgAAAA==.Lightkeeper:BAAANQABCgQIAgAAAA==.Likkash:BAAANQADCggICAABNQAECgMIAwABAAAAAA==.Linthabeela:BAAANQADCgEIAQAAAA==.Liquidchiken:BAAANQAECgQIBAAAAA==.Lishalthen:BAAANQADCggIDwAAAA==.Littletouch:BAAANQADCgIIAgAAAA==.Livicecia:BAAANQADCggICAAAAA==.',
Lu='Lucielinna:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Luckiiem:BAAANQAECgQIBAAAAA==.Luisfriendsn:BAAANQAECgEIAQABNQAFFAEIAQABAAAAAA==.Lumbo:BAEANQADCgUIBQABNQAECgIIAgABAAAAAA==.Lunare:BAAANQADCgUIBQAAAA==.Lunarkin:BAAANQADCgcICQAAAA==.Luthane:BAAANQAECgEIAQAAAA==.',
Ly='Lykinea:BAAANQADCgQIBAAAAA==.Lytebrite:BAAANQAECgQIBAAAAA==.',
['Lü']='Lümßo:BAEANQAECgIIAgAAAA==.',
Ma='Mainos:BAAANQADCgIIAgAAAA==.Makishi:BAAANQAECgEIAQAAAA==.Malfura:BAAANQADCggIEwAAAA==.Malário:BAAANQAECgQIBQAAAA==.Mattedfurry:BAAANQAECgIIAgAAAA==.Maube:BAAANQADCgcIBwABNQAECgcIEAABAAAAAA==.Mazzarzul:BAAANQADCgYIDAABNQAECgYICwABAAAAAA==.',
Me='Meebles:BAAANQAECgQIBAAAAA==.Meiana:BAAANQAECgIIAgAAAA==.Melasmus:BAAANQABCgYICgAAAA==.Mes:BAAANQAECgQIBAAAAA==.',
Mi='Micklaa:BAAANQADCgcIEgAAAA==.Miebi:BAAANQADCgUIBQABNQAECgYICwABAAAAAA==.Milkbunny:BAAANQADCgUIBQAAAA==.Mingtai:BAAANQADCggIDwAAAA==.',
Mo='Moirrah:BAAANQADCgYIBgAAAA==.Moonriver:BAAANQAECgQIBAAAAA==.Moranta:BAAANQAECgEIAQAAAA==.Moressandra:BAAANQADCggIDQAAAA==.Morgaes:BAAANQADCgYIDAAAAA==.Morîarty:BAAANQADCgIIAgAAAA==.',
My='Mydruid:BAAANQAECgMIBAABNQAECgcIDwABAAAAAA==.Mysticmurv:BAAANQAECgUICgAAAA==.Mywarlock:BAAANQAECgcIDwAAAA==.',
Na='Nalgotica:BAAANQADCgMIAwAAAA==.Nalynahwe:BAAANQADCggICwAAAA==.Narima:BAAANQAECgEIAQAAAA==.Nathronso:BAAANQADCgUIBQAAAA==.Nauticâ:BAAANQABCgQIAwAAAA==.Navirose:BAAANQADCggIDwAAAA==.',
Ne='Necromos:BAAANQADCggIBgAAAA==.',
Nh='Nhala:BAAANQADCgUICAAAAA==.',
Ni='Nightestrike:BAAANQAECgEIAQAAAA==.Nivek:BAAANQADCgUICQAAAA==.',
No='Noralai:BAAANQADCgUIBAAAAA==.Nore:BAAANQADCgcIEAAAAA==.',
['Nà']='Nàdya:BAAANQAECgUICAAAAA==.',
Ob='Oblivions:BAAANQAECgIIAgAAAA==.',
Od='Odasa:BAAANQAECgEIAQAAAA==.',
Ol='Olahn:BAAANQADCgEIAQABNQADCgUICAABAAAAAA==.',
On='Onekark:BAAANQAECgIIBAABNQAFFAQIBQADADYKAA==.Onlysins:BAAANQADCggIEwAAAA==.',
Or='Orckus:BAAANQADCgYIDgAAAA==.Oreosbunny:BAAANQAECgQIBAAAAA==.Orìhimè:BAAANQABCgQIBAAAAA==.',
Pa='Padma:BAAANQADCgUIBAAAAA==.Pandaburn:BAAANQADCggIEgAAAA==.Paroxism:BAAANQAECgcIDgAAAA==.',
Pe='Peanût:BAAANQAECgIIAgAAAA==.Peautiful:BAAANQADCgMIBAAAAA==.',
Ph='Phaket:BAAANQAECgQIBQAAAA==.',
Pi='Picaduro:BAAANQADCgYICQAAAA==.Picture:BAAANQADCgcIEgABNQAECgcIDwABAAAAAA==.Pika:BAAANQAECgEIAQAAAA==.Pippá:BAAANQADCggIDwAAAA==.',
Po='Polonius:BAAANQADCgcICQAAAA==.Potato:BAAANQADCgIIAgAAAA==.',
Pr='Probation:BAAANQADCgUICAAAAA==.',
Pu='Puchideperro:BAAANQAECgEIAQAAAA==.',
Pw='Pwil:BAAANQABCgMIAgABNQABCgYICgABAAAAAA==.',
Py='Pythe:BAAANQAECgQIBAAAAA==.',
Qa='Qap:BAAANQAECgIIAwAAAA==.',
Qi='Qingu:BAAANQAECgQIBQAAAA==.',
Qu='Qualnorr:BAAANQADCgYIDgAAAA==.Queldraayan:BAAANQAECgEIAQAAAA==.Quinnter:BAEANQAECgEIAQAAAA==.Quixxie:BAEANQABCgYICAABNQAECgEIAQABAAAAAA==.',
Qw='Qwil:BAAANQABCgYICgAAAA==.',
Ra='Radagon:BAAANQAECgUIBgABNQAECgQIBAABAAAAAA==.Radalas:BAAANQADCggIFQAAAA==.Radreliris:BAAANQADCgUIBwAAAA==.Rainlight:BAAANQADCgUIBQAAAA==.Ramcco:BAEANQADCggIFQAAAA==.Ranelle:BAAANQAECgQIBAAAAA==.Rasmira:BAAANQADCgYIDgAAAA==.Ravenis:BAAANQAECgcICQAAAA==.',
Re='Reedem:BAAANQADCggIFAAAAA==.Regilock:BAABNQAFFIEHAAQHAAUJxBYKAgAdAQAHAAMJwBkKAgAdAQAIAAIJ7wxYAwCzAAAJAAEJjhPwAQBaAAAAAA==.Reikí:BAAANQAECgQIBAABNQAECgUICAABAAAAAA==.',
Rh='Rhaenyrra:BAAANQAECgQIBAAAAA==.Rhaily:BAAANQADCgIIAgAAAA==.Rhallin:BAAANQADCgcIDAAAAA==.',
Ro='Ronso:BAAANQADCgQIBAAAAA==.Rosiel:BAAANQABCgQIBAAAAA==.Rowain:BAAANQAECgQIBAAAAA==.',
Ry='Rylacus:BAAANQADCggIFAAAAA==.Rylii:BAAANQADCggIFgAAAA==.',
Sa='Saanda:BAAANQADCggIEAAAAA==.Sarlef:BAAANQADCggIFgAAAA==.',
Sc='Scarm:BAAANQAECgIIAwAAAA==.Scathed:BAAANQAECgcIBwAAAA==.Scorpix:BAAANQADCgYIBwAAAA==.',
Se='Seaflower:BAAANQADCgYIBQAAAA==.Sellidra:BAAANQADCggIFQAAAA==.Serenitara:BAAANQADCgYIDAAAAA==.Serifanlord:BAAANQAECgEIAQAAAA==.',
Sh='Shaffer:BAAANQAECgIIAgAAAA==.Shellshocker:BAAANQAECgYIDAAAAA==.Sheng:BAAANQADCgUIBQAAAA==.Shermantånk:BAAANQADCgYICAAAAA==.Shikigamï:BAAANQADCgcICQABNQADCggIDwABAAAAAA==.Shikï:BAAANQADCggIDwAAAA==.Shivermoón:BAAANQAECgMIBQAAAA==.',
Si='Sigesar:BAAANQADCgcIEwAAAA==.Sinsimella:BAAANQABCgYIBgAAAA==.',
Sk='Skullash:BAAANQADCgcIBwAAAA==.Skywatcher:BAAANQAECgEIAQAAAA==.',
Sm='Smitemare:BAAANQADCgcIBwAAAA==.',
Sn='Sneakmode:BAAANQADCgYIBgAAAA==.Snicky:BAAANQADCgUIBQAAAA==.',
So='Solare:BAAANQADCgMIAwAAAA==.Sonwarr:BAAANQAECgQIBQAAAA==.',
Sp='Spliphtoker:BAAANQADCgcIGQAAAA==.',
St='Steelpen:BAAANQAECgIIAwAAAA==.Stenston:BAAANQAECgEIAQAAAA==.Sterede:BAAANQADCgYIDwAAAA==.Stitchwhich:BAAANQADCgYICgAAAA==.Stonehenge:BAAANQADCggIFQAAAA==.Stormb:BAAANQADCgQICAAAAA==.Stormwolves:BAAANQADCgMIAwAAAA==.',
Sy='Sylphr:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.Sylphwild:BAAANQAECgQIBAAAAA==.Sylvara:BAAANQAECgEIAQAAAA==.Synkinz:BAAANQAECgEIAQAAAA==.Syntec:BAAANQABCgIIAgAAAA==.Syreite:BAAANQAECgEIAQAAAA==.',
Ta='Tacori:BAAANQADCgYICAAAAA==.Taessa:BAAANQADCgMIAwAAAA==.Tallic:BAAANQAECgQIBAAAAA==.Talynayl:BAAANQADCgUIBwAAAA==.Tandemonium:BAAANQADCgUIBwABNQAECgcIDgABAAAAAA==.Taniz:BAAANQAECgQIBAAAAA==.Tarsi:BAAANQAECgEIAQAAAA==.',
Td='Td:BAAANQAECgUIBQABNQAFFAcIDQAKABsiAA==.',
Te='Telidrel:BAAANQADCgEIAQAAAA==.',
Th='Thaddeaus:BAAANQAECgQIBgAAAA==.Thaddeus:BAAANQADCgcIEwAAAA==.Thebeefyone:BAAANQAECgIIAgAAAA==.Thecanadian:BAAANQADCgQIBAAAAA==.Thesummoner:BAAANQAECgEIAQAAAA==.Thorrek:BAAANQADCgMIAwAAAA==.Thumpette:BAAANQADCggIKAAAAA==.',
Ti='Tierant:BAAANQADCgUIBAAAAA==.Tizaria:BAAANQAECgEIAQAAAA==.',
To='Tominaetor:BAAANQADCgcIJAAAAA==.Tosoto:BAAANQAECgQIBQAAAA==.Toxica:BAAANQADCgMIAwAAAA==.',
Tr='Travcula:BAAANQAECgQIBQAAAA==.Treefiddy:BAAANQADCgEIAgAAAA==.',
Ts='Tso:BAAANQADCgEIAQAAAA==.',
Tt='Ttriton:BAAANQADCgEIAQAAAA==.',
Tu='Tuuwa:BAAANQADCgMIAwAAAA==.',
Ty='Tyernan:BAAANQAECgMIAwAAAA==.Tyrioz:BAAANQAECgEIAQAAAA==.',
Tz='Tzavcat:BAAANQADCggIFAAAAA==.',
Uh='Uhtred:BAAANQAECggIAgAAAA==.',
Ur='Urbi:BAAANQADCgYIBgAAAA==.',
Uv='Uvsol:BAAANQADCgQIBAAAAA==.',
Va='Vadailla:BAAANQAECgEIAQAAAA==.Vahrik:BAAANQABCgMIAwAAAA==.Valius:BAAANQADCggIFgAAAA==.Valkyrae:BAAANQADCgQIBAAAAA==.Valornor:BAAANQADCgIIAgAAAA==.Vandill:BAAANQAECgUICQAAAA==.Vaxis:BAAANQADCgEIAQAAAA==.',
Ve='Veasnacool:BAAANQAECgQIBgAAAA==.Vestrit:BAAANQADCgIIAgABNQAECgUICAABAAAAAA==.',
Vo='Vontote:BAAANQADCggIFgAAAA==.',
['Ví']='Víc:BAAANQAECgEIAQAAAA==.',
Wa='Wandorf:BAEANQADCgcIEgAAAA==.Warwolfe:BAAANQAECgQIBAAAAA==.Wayler:BAAANQADCggICAAAAA==.',
Wh='Whumpus:BAAANQADCgIIAgAAAA==.',
Wi='Willei:BAAANQADCgUICwAAAA==.',
Wo='Wolferunner:BAAANQADCggIEwAAAA==.',
Xa='Xaiden:BAAANQADCgcIBwAAAA==.Xaldora:BAAANQADCgEIAQAAAA==.',
Xd='Xdxvuu:BAAANQAECgQIBQAAAA==.',
Xe='Xerimok:BAAANQADCggIDgAAAA==.',
Xi='Xinya:BAAANQADCggIEgAAAA==.',
Xz='Xzephyr:BAAANQAECgQIBAAAAA==.',
Ye='Yesmín:BAAANQAECgIIAgAAAA==.',
Yi='Yil:BAAANQAECgMIAwAAAA==.',
Yo='Youwas:BAAANQAECgEIAQAAAA==.',
Yu='Yukmouf:BAAANQADCggIEAABNQAECgQIBAABAAAAAA==.Yuriika:BAAANQADCgYIBwAAAA==.Yuukmouf:BAAANQAECgQIBAAAAA==.',
Za='Zakaris:BAAANQADCgYIBgAAAA==.Zaladin:BAAANQADCgUIBQAAAA==.Zarrove:BAAANQAECgQIBAAAAA==.',
Ze='Zeltri:BAAANQAECgQIBgAAAA==.Zerg:BAAANQAECgEIAQAAAA==.',
Zh='Zhatva:BAAANQAECgcIDgAAAA==.Zhöe:BAAANQAECgQIBAAAAA==.',
Zi='Zimzhealz:BAAANQADCgYIBgAAAA==.Zimzorzz:BAAANQADCgUIBwABNQADCgYIBgABAAAAAA==.',
Zo='Zoelera:BAAANQADCggICAAAAA==.Zoldor:BAAANQAECgEIAQAAAA==.Zorellion:BAAANQAECgEIAQAAAA==.',
Zu='Zuay:BAAANQADCgIIAgABNQAECgQIBQABAAAAAA==.Zulianguy:BAAANQAECgcICwAAAA==.',
Zy='Zycorr:BAAANQAECgEIAQAAAA==.Zytrex:BAAANQADCgEIAQAAAA==.',
['Zá']='Zátsu:BAAANQABCgEIAQAAAA==.',
['Ñÿ']='Ñÿx:BAAANQADCggIFAAAAA==.',
['ßl']='ßluerain:BAAANQABCgQIBQAAAA==.',
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
