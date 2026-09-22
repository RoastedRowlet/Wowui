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

local lookup = {'DeathKnight-Frost','Unknown-Unknown','Warrior-Protection','Shaman-Restoration','Shaman-Elemental','Hunter-Survival','DemonHunter-Devourer','Warlock-Demonology','Warlock-Destruction','DeathKnight-Unholy','DeathKnight-Blood','Mage-Arcane','Warlock-Affliction','Monk-Windwalker','Hunter-BeastMastery','Shaman-Enhancement','Warrior-Arms','Druid-Balance','Monk-Brewmaster','Paladin-Protection','Rogue-Assassination','Rogue-Subtlety','DemonHunter-Havoc','Hunter-Marksmanship','Priest-Shadow','Paladin-Retribution',}
local provider = {region='US',realm='ArgentDawn',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abajaba:BAAANQADCgYIFgAAAA==.Abractus:BAAANQAECgQIBwAAAA==.',
Ad='Aderrig:BAAANQADCgQIBAAAAA==.Adriana:BAAANQAECgQJBQAAAA==.Adrianix:BAAANQAECgIJAgAAAA==.Adru:BAAANQAECgIJAgAAAA==.',
Ae='Aeglos:BAABNQAECoEbAAIBAAkKlB15DgDFAgABAAkKlB15DgDFAgAAAA==.Aehrick:BAAANQAECgIJAwAAAA==.Aentharion:BAAANQAECgIJAgAAAA==.Aeyn:BAAANQABCggJEwAAAA==.',
Af='Afflixen:BAAANQADCgQJBAAAAA==.',
Ai='Aileen:BAAANQAECgUJDQAAAA==.',
Aj='Ajora:BAAANQABCgEIAQABNQAECgQJBwACAAAAAA==.',
Al='Alakaz:BAAANQAECgEIAQAAAA==.Aldehyde:BAAANQADCgUIBQAAAA==.Alidoro:BAAANQADCgEIAQAAAA==.Alisonia:BAAANQADCgMJBQAAAA==.Alitikar:BAAANQADCgQIBAAAAA==.Alleximage:BAAANQAECgIIAQAAAA==.Alliancepaly:BAAANQADCgMIAwAAAA==.Alorren:BAAANQAECgUJBgAAAA==.Aludor:BAAANQADCgEIAQAAAA==.',
Am='Ammo:BAAANQADCgcIEQABNQAECgYIDgACAAAAAA==.Amo:BAAANQABCggIHQABNQAECgYIDgACAAAAAA==.Amodegas:BAAANQAECgMIAwABNQAECgYIDgACAAAAAA==.Amodillo:BAAANQAECgYIDgAAAA==.Amoe:BAAANQADCggJCAABNQAECgYIDgACAAAAAA==.Amonra:BAAANQADCgYICQAAAA==.Amynrar:BAAANQADCggIEAAAAA==.',
An='Angyaras:BAACNQAFFIENAAIDAAUKMSNXAAAJAgADAAUKMSNXAAAJAgA1AAQKgRwAAgMACQoHJpsAAMkDAAMACQoHJpsAAMkDAAAA.Animos:BAAANQADCgMIAwAAAA==.',
Ap='Apiix:BAAANQAECgcIEQAAAA==.',
Ar='Araaras:BAAANQAFFAEJAQAAAA==.Araiguma:BAAANQAECgcIDQAAAA==.Arcaisme:BAAANQAECgEIAQAAAA==.Arcticsnow:BAAANQAECgQIBAAAAA==.Ariealla:BAAANQADCgUIBQAAAA==.Arkose:BAAANQADCggJDAAAAA==.',
As='Aschen:BAAANQADCgIJAwAAAA==.Ashlyngrace:BAAANQAECgIIAgABNQAECggJIAAEALQaAA==.Ashlynne:BAABNQAECoEgAAMEAAgKtBrHLwA7AgAEAAgKtBrHLwA7AgAFAAEKAALi9QAhAAAAAA==.Aspensong:BAAANQAECgIJAgAAAA==.Astracious:BAAANQADCggIIgAAAA==.Astrayice:BAAANQADCgQIBQAAAA==.',
At='Atarkormu:BAAANQAECgQIBAABNQAECgUJCAACAAAAAA==.Atax:BAAANQAECgIJAgAAAA==.Athená:BAAANQAECgIJAwAAAA==.Atulkan:BAAANQAECgQJBQAAAA==.',
Au='Auralyn:BAAANQADCgUJBwAAAA==.Aurelitrasza:BAAANQADCgYJEwAAAA==.',
Av='Avalar:BAAANQADCgUJBQAAAA==.Avrice:BAAANQADCggIEwAAAA==.Avris:BAAANQAECgEIAQAAAA==.',
Ay='Ayayaras:BAAANQAFFAIIAwABNQAFFAUIDQADADEjAA==.',
Ba='Badshot:BAAANQADCgYIBgAAAA==.Bambu:BAAANQADCgcJCgABNQAECgIIAgACAAAAAA==.Bamevoker:BAAANQAECgIIAgAAAA==.Bariggs:BAABNQAECoEXAAIGAAgKjiDGAQDsAgAGAAgKjiDGAQDsAgAAAA==.Barilia:BAAANQADCgEJAQAAAA==.',
Be='Beals:BAAANQAECgQJBgAAAA==.Beladra:BAAANQADCgQIBQAAAA==.Ben:BAAANQAECgcJDgAAAA==.Beriadan:BAABNQAECoEXAAIFAAcKIRx/NAAwAgAFAAcKIRx/NAAwAgAAAA==.Bevee:BAAANQAFFAEJAQAAAA==.',
Bi='Bisque:BAAANQADCgUIBQAAAA==.',
Bl='Bleddwen:BAAANQAECgIJAwAAAQ==.Blindseer:BAAANQABCgIIAgAAAA==.Blrsama:BAAANQAECgIIAwAAAA==.',
Bo='Bohrnir:BAAANQADCgUIBQAAAA==.Boozelee:BAAANQADCgMIAwAAAA==.Boüh:BAAANQAECgQJBgAAAA==.',
Br='Brutalix:BAAANQADCgEIAQAAAA==.',
Bu='Bubblesonyou:BAAANQAECgYJDgAAAA==.Burnadine:BAAANQAECgIJAwAAAA==.Burnswhnpee:BAAANQAECgYICwAAAA==.',
Ca='Caliie:BAAANQAECgIJAgAAAA==.Callektra:BAAANQADCggICwAAAA==.Callira:BAAANQADCgYIBgAAAA==.Captclamslam:BAAANQADCgcIDAAAAA==.Carhop:BAAANQADCgIIAgAAAA==.Caw:BAAANQADCgMIAwABNQAECgIIAgACAAAAAA==.Cayuga:BAAANQADCgUICAAAAA==.',
Ch='Charå:BAAANQADCgUIBQAAAA==.Chintakari:BAAANQAECgUJBQAAAA==.',
Co='Cocidiae:BAAANQADCgQJBAAAAA==.Confusious:BAABNQAECoEYAAIEAAkKeRy8FwDKAgAEAAkKeRy8FwDKAgAAAA==.Coppers:BAAANQADCggICAAAAA==.Coree:BAAANQAECgIJBgAAAA==.Cornflower:BAAANQADCgYICQABNQAECgUJDAACAAAAAA==.Corvaan:BAABNQAECoEXAAIHAAkKLhAMGwAtAgAHAAkKLhAMGwAtAgAAAA==.Corvhuunta:BAAANQAECgQJBAAAAA==.',
Cr='Creg:BAAANQADCggIIgAAAA==.Crowbarr:BAAANQADCgYICwAAAA==.Cryostatic:BAAANQAECgEJAQABNQAECgMJAwACAAAAAA==.',
Cu='Cultel:BAAANQAECgcIEQAAAA==.Cuulon:BAAANQADCgQJBAAAAA==.',
Cy='Cyendia:BAAANQAECgQJBAAAAA==.Cynlea:BAAANQADCgYJCgAAAA==.',
Da='Daddyraz:BAAANQAECgQJBAAAAA==.Daemonquiver:BAAANQADCgUIBQAAAA==.Dahtotems:BAAANQAECggICgAAAA==.Daphcelyn:BAAANQADCggJHgAAAA==.Dariusz:BAAANQAECgQJBQAAAA==.Darkalen:BAAANQAECgUJCAAAAA==.Darklodus:BAAANQADCgYICwAAAA==.Darksethia:BAAANQADCgQIBAAAAA==.Dathea:BAACNQAFFIEKAAIEAAUK4x4IAwDhAQAEAAUK4x4IAwDhAQA1AAQKgSIAAgQACQplIX0LADEDAAQACQplIX0LADEDAAAA.Daxetanlock:BAABNQAECoEfAAMIAAkKnSLJDgAWAwAIAAgKhiLJDgAWAwAJAAQKrBpIJQAkAQABNQAECgIIAgACAAAAAA==.Daxetans:BAAANQAECgIIAgAAAA==.',
De='Deathjingle:BAABNQAECoEbAAMKAAkKXxvkFgC0AgAKAAkKKhrkFgC0AgALAAQK8B4qSgBaAQAAAA==.Deecayed:BAAANQAECgEIAQABNQAECgkJHAAEAOMcAA==.Deecoy:BAAANQAECgEIAQABNQAECgkJHAAEAOMcAA==.Deemonic:BAAANQADCggIDgABNQAECgkJHAAEAOMcAA==.Deerslayer:BAAANQABCgIIAwAAAA==.Deetermined:BAABNQAECoEcAAIEAAkK4xwpFADlAgAEAAkK4xwpFADlAgAAAA==.Deloisela:BAAANQAECggIDQAAAA==.Denchy:BAAANQAECgQJBwAAAA==.Deylen:BAAANQAECgQJCAAAAA==.Deyndine:BAAANQAECgQIBwAAAA==.',
Di='Dizzyglaive:BAAANQADCgYIDQAAAA==.',
Dl='Dlkffjj:BAAANQAECgEJAgAAAA==.',
Dm='Dmdk:BAAANQAECgIIAgAAAA==.Dmrwr:BAAANQAECggIEQAAAA==.',
Do='Dodson:BAAANQADCgEIAQAAAA==.Dottarus:BAAANQADCgUIBQABNQADCggICQACAAAAAA==.',
Dr='Draegloth:BAAANQAECggJAgAAAA==.Draelick:BAAANQABCgIIAgAAAA==.Driadora:BAAANQAECgQJBgAAAA==.Droataxm:BAABNQAECoEiAAIMAAkKSh/JKwANAwAMAAkKSh/JKwANAwAAAA==.Drogath:BAAANQADCgcIDQAAAA==.',
Du='Duarraag:BAAANQADCgYICQAAAA==.',
['Dâ']='Dâvïd:BAAANQAECgYIEQAAAA==.',
['Dä']='Däß:BAAANQADCgEJAQAAAA==.',
['Dë']='Dëërez:BAAANQAECgQIBgABNQAECgkJHAAEAOMcAA==.',
Ei='Eililis:BAAANQADCgYIBwAAAA==.',
El='Elani:BAAANQAECgYICwAAAA==.Elaynaa:BAAANQAECgIJAwAAAA==.Elishaunt:BAAANQAECgEJAwABNQABCgEIAQACAAAAAA==.Elleth:BAAANQAECgEIAQAAAA==.Elliana:BAAANQAECgUJCgAAAA==.Elogio:BAAANQADCgYJCwAAAA==.Elvoidra:BAAANQADCgUIBQAAAA==.',
Em='Emanymton:BAAANQADCgcJEgAAAA==.Embyr:BAAANQADCggJGQAAAA==.Emiley:BAAANQADCgMJAwAAAA==.',
En='Envymeh:BAAANQADCgUIBQAAAA==.',
Er='Erinn:BAAANQADCgUIBQAAAA==.Erisaria:BAAANQADCggJCgAAAA==.Erixi:BAAANQAECgIIAwAAAA==.Eryn:BAAANQADCgEIAQAAAA==.',
Es='Esaria:BAAANQADCgEIAQAAAA==.',
Ev='Evissier:BAABNQAECoEWAAINAAgKtR9oAQD9AgANAAgKtR9oAQD9AgAAAA==.',
Ex='Excelimagust:BAAANQADCgYIFAAAAA==.',
Fa='Faelada:BAAANQADCggICAAAAA==.Faid:BAAANQAECgEIAQAAAA==.Failor:BAAANQADCgYIBgAAAA==.Falcdhruid:BAAANQADCgUICQAAAA==.Farundi:BAAANQADCgUIBQAAAA==.',
Fe='Felbutton:BAAANQADCgYIAQAAAA==.Felsen:BAAANQABCgEJAQABNQAECgYIDwACAAAAAA==.Felwit:BAAANQAECgYIDwAAAA==.Fennec:BAAANQAECgEIAQAAAA==.Feralie:BAAANQADCgYIBgAAAA==.Ferroz:BAAANQAECgQJBAABNQAECgUJCAACAAAAAA==.',
Fl='Flamos:BAAANQAECgQIBAAAAA==.Flatline:BAAANQAECgMJBQAAAA==.Florabelle:BAAANQAECgUJDAAAAA==.Florid:BAAANQADCggIHAAAAA==.',
Fo='Foshomomo:BAAANQAECgIJAgAAAA==.Fozzle:BAAANQAECgUJDAAAAA==.',
Fr='Frenndi:BAAANQADCggJEwAAAA==.',
Fu='Fuknazuga:BAAANQAECgQIBwAAAA==.Furroz:BAAANQADCgYJBgABNQAECgUJCAACAAAAAA==.',
Fy='Fynedge:BAAANQAECgUIDAAAAA==.Fynnyntyss:BAAANQAECgUJDQAAAA==.Fyrè:BAAANQAECgUJDQAAAA==.',
Ga='Garthe:BAAANQADCgEIAQAAAA==.',
Ge='Geoma:BAAANQADCgUIBQAAAA==.Gerlock:BAAANQADCgUJBgAAAA==.',
Gh='Ghastrider:BAAANQABCgEIAQAAAA==.Ghostlyt:BAAANQABCgEJAQAAAA==.',
Gi='Gigatin:BAAANQAECgUJBgAAAA==.Githnor:BAAANQAECgUJDQAAAA==.',
Go='Goldal:BAAANQADCgcIBwAAAA==.Gorellan:BAAANQADCgYJCAAAAA==.',
Gr='Grimwharf:BAAANQADCgUIBQAAAA==.Grum:BAAANQADCgQIBgAAAA==.Grunaelyn:BAAANQAECgUJBgAAAA==.',
Gu='Guerrier:BAAANQAECgUIBgAAAA==.Guiong:BAAANQADCgYICgAAAA==.',
Gy='Gynx:BAAANQADCgUIBQAAAA==.',
['Gö']='Göttlich:BAAANQADCgUIBQABNQADCgUIBwACAAAAAA==.',
Ha='Haidas:BAAANQADCggJDwAAAA==.',
He='Heikuro:BAAANQAECgIJAwAAAA==.Heybestie:BAAANQADCggICAAAAA==.',
Hi='Hillo:BAAANQAECgEIAQAAAA==.',
Ho='Holychonks:BAAANQADCgcIEAAAAA==.Honadain:BAAANQADCgcIGgAAAA==.Honornight:BAAANQADCggJDgAAAA==.Hordestalker:BAAANQADCgUIBQAAAA==.Houtu:BAAANQAECgUIDwAAAA==.',
Hw='Hweilan:BAAANQADCgYICQAAAA==.Hwil:BAAANQADCgYIBgAAAA==.',
Hy='Hydrokill:BAAANQADCggICAAAAA==.Hypnos:BAAANQADCgYIFAAAAA==.',
['Hö']='Hölyföx:BAAANQAECgEIAQAAAA==.',
Ia='Iamearl:BAAANQAECgEIAQAAAA==.',
In='Incidental:BAABNQAECoEhAAIOAAkKLSH4BgAlAwAOAAkKLSH4BgAlAwAAAA==.Inconell:BAAANQAECgQIBAAAAA==.Invega:BAAANQAECgIJAwAAAA==.',
Ir='Iric:BAAANQADCgMIBQAAAA==.Irino:BAAANQADCgUIBQAAAA==.',
Is='Isabelle:BAAANQAECgMIBQAAAA==.',
Iz='Izaer:BAAANQAECgIJBAAAAA==.Iziel:BAAANQAECgEIAQAAAA==.Izumex:BAAANQAECgMIAwAAAA==.',
Ja='Jabzaklok:BAAANQADCggJGgAAAA==.Jacky:BAAANQAFFAEIAQABNQAFFAIJAwACAAAAAA==.Jahirah:BAAANQAECgUJBgABNQAECgUJCwACAAAAAA==.Jaida:BAAANQAECgQIDAAAAA==.Jaleika:BAAANQAECgUJCwAAAA==.Jarius:BAAANQAECgIJAgAAAA==.',
Je='Jean:BAABNQAECoEaAAIPAAcKrh7+LwBzAgAPAAcKrh7+LwBzAgAAAA==.Jeez:BAAANQAECgcICgAAAA==.Jesmaríe:BAAANQAECgEIAQAAAA==.',
Jo='Johadd:BAAANQADCgEIAQAAAA==.Jonyy:BAAANQADCgUIBQAAAA==.Jorianna:BAAANQAECgIIAgAAAA==.Joru:BAACNQAFFIEUAAIQAAYK7BhJAABOAgAQAAYK7BhJAABOAgA1AAQKgSsAAhAACQpmJmEAAOEDABAACQpmJmEAAOEDAAAA.',
Ju='Jurauth:BAAANQABCgQIBAAAAA==.Justyna:BAAANQAECgEIAQAAAA==.Juze:BAAANQAECgQICQABNQAECgMIAQACAAAAAQ==.',
Ka='Kaai:BAAANQAECgEIAQAAAA==.Kabaul:BAABNQAECoEiAAIRAAkKJCRsBwCgAwARAAkKJCRsBwCgAwAAAA==.Kabir:BAAANQAECgQJBwAAAA==.Kadria:BAAANQAECgIJAwAAAA==.Kailanii:BAAANQAECgEIAQABNQAECgUJBQACAAAAAA==.Kalagon:BAAANQADCgEIAQAAAA==.Kalaman:BAAANQADCgQICAAAAA==.Kalito:BAAANQADCgMIAwAAAA==.Kamb:BAAANQAECgIJAgAAAA==.Karalee:BAAANQAECgQJBAAAAA==.Katieey:BAACNQAFFIESAAIEAAUKqiQGAwDiAQAEAAUKqiQGAwDiAQA1AAQKgR8AAgQACQrzJrEAANsDAAQACQrzJrEAANsDAAAA.Kaybee:BAAANQADCgYIFAAAAA==.Kayde:BAAANQADCgYIBgAAAA==.Kayil:BAAANQAECgcIEQAAAA==.',
Ke='Kedalin:BAAANQADCggJFwAAAA==.Kennyloggy:BAACNQAFFIEKAAISAAQKzx2aBgCJAQASAAQKzx2aBgCJAQA1AAQKgSYAAhIACQp6JGQGAIUDABIACQp6JGQGAIUDAAAA.Kevris:BAAANQAECgQIBQABNQAECgUJCwACAAAAAA==.Keydan:BAAANQAECgIJAwAAAA==.',
Ki='Kianni:BAAANQADCggICAAAAA==.Kirafrayen:BAAANQAECgEJAQABNQAECgIIAgACAAAAAA==.',
Kl='Klassy:BAAANQAECgYIDgAAAA==.',
Ko='Koppi:BAAANQADCgYIEQAAAA==.Korru:BAAANQAECgMJAwAAAA==.Kotie:BAAANQADCgQIBQAAAA==.',
Kr='Kramz:BAAANQADCgcIBwAAAA==.Kreoss:BAAANQADCgQJBAABNQAECggIFgAEAAcJAA==.Kronar:BAAANQAECgQICQAAAA==.Krongar:BAAANQADCgQIBAAAAA==.Krumblo:BAEANQAECgIJAgABNQAECgUIBwACAAAAAA==.Kryztof:BAAANQADCgYJBgAAAA==.',
Ku='Kuiraptor:BAAANQADCgcJBwAAAA==.Kunea:BAAANQADCgYIBgAAAA==.Kungfujace:BAAANQADCgYICwAAAA==.',
Ky='Kyrgune:BAAANQADCggIGwAAAA==.',
['Kà']='Kàhlan:BAAANQADCgYIBgAAAA==.',
La='Laoftey:BAAANQAECgcIEQAAAA==.Larquin:BAAANQAECgUJCwAAAA==.Lasmori:BAAANQAECgMIBAABNQAECgYICwACAAAAAA==.Laurenorder:BAAANQAECgUJBQAAAA==.Laxxbroo:BAAANQADCgUICQAAAA==.',
Le='Leam:BAAANQAECgMIBAAAAA==.Leglock:BAAANQAECgQJBgAAAA==.Lesbihonest:BAAANQAECgcIBwAAAA==.',
Li='Liendria:BAAANQAECgIIBQAAAA==.Lifensoftpaw:BAACNQAFFIEIAAIOAAQKKhQSBABOAQAOAAQKKhQSBABOAQA1AAQKgScAAw4ACQruIv8HABEDAA4ACQruIv8HABEDABMABQo5IOQLANYBAAAA.Lightemup:BAAANQAECgMJBQAAAA==.Lightkeeper:BAAANQABCgQIAgAAAA==.Likkash:BAAANQADCggJCAABNQAECgUJCAACAAAAAA==.Limildea:BAAANQADCgIIAgAAAA==.Linthabeela:BAAANQADCgEJAQAAAA==.Liquidchiken:BAAANQAECgQIBAAAAA==.Lishalthen:BAAANQADCggJFwAAAA==.Littletouch:BAAANQADCgIIAgAAAA==.Livicecia:BAAANQAECgMJAwAAAA==.',
Lu='Lucciana:BAAANQAECgIIAgABNQAECgIJAgACAAAAAA==.Lucielinna:BAAANQADCgUIBQABNQAECgIJAwACAAAAAA==.Luckiiem:BAAANQAECgcIEQAAAA==.Luisfriendsn:BAAANQAECgQIBQABNQAECgkJGQAMAEYTAA==.Lumbo:BAEANQAECgUIBwAAAA==.Lunare:BAAANQADCgUJBQAAAA==.Lunarkin:BAAANQAECgIJAgAAAA==.Luthane:BAAANQAECgIIAwAAAA==.',
Ly='Lykinea:BAAANQADCgYIBgAAAA==.Lytebrite:BAAANQAECgcJEQAAAA==.',
['Lí']='Líu:BAAANQADCggICAAAAA==.',
['Lü']='Lümßo:BAEANQAECgIJAgABNQAECgUIBwACAAAAAA==.',
Ma='Mainos:BAAANQADCgUIBwAAAA==.Maiyr:BAAANQAECgEJAQAAAA==.Makanai:BAAANQAECgEIAQAAAA==.Makishi:BAAANQAECgQJBwAAAA==.Malferious:BAAANQADCgIIAgAAAA==.Malfura:BAAANQAECgEJAgAAAA==.Malário:BAAANQAECgQJBwAAAA==.Manamontana:BAAANQADCgUIBQABNQADCggIDQACAAAAAA==.Mattedfurry:BAAANQAECgIIAgAAAA==.Maube:BAAANQADCgcJBwABNQAECggIGAAUAPMMAA==.Mazzarzul:BAAANQADCgYJGQABNQAECggIHAAGAJkZAA==.',
Me='Meebles:BAAANQAECgUJDQAAAA==.Meiana:BAAANQAECgYIDQAAAA==.Melasmus:BAAANQADCgUIBQAAAA==.Mes:BAAANQAECgQJBwAAAA==.',
Mi='Micklaa:BAAANQAECgQJBgAAAA==.Miebi:BAAANQADCgYICwABNQAECgcIHAATAN8gAA==.Milkbunny:BAAANQADCgUICQAAAA==.Mingtai:BAAANQAECgIJAwAAAA==.Misskaitlyn:BAAANQADCgcIBwAAAA==.',
Mo='Moirrah:BAAANQADCgYIBgABNQAECgEIAQACAAAAAA==.Moonriver:BAAANQAECgUJCQAAAA==.Moonsinde:BAAANQAECggJBAAAAA==.Moranta:BAAANQAECgQJBwAAAA==.Moressandra:BAAANQAECgIIAwAAAA==.Morgaes:BAAANQAECgIIAgAAAA==.Mortannon:BAAANQAECgQJBgAAAA==.Morîarty:BAAANQADCgIIAgAAAA==.',
Mu='Mushy:BAAANQADCgEIAQAAAA==.',
My='Mydruid:BAAANQAECgQJBQABNQAECgkJIwAVANUcAA==.Mysticarc:BAAANQADCgYIBgAAAA==.Mysticmurv:BAABNQAECoEYAAIMAAcKCQh9vwCDAQAMAAcKCQh9vwCDAQAAAA==.Mystieren:BAAANQAECgQJBAABNQAECgUIDAACAAAAAA==.Mywarlock:BAABNQAECoEjAAMVAAkK1RyqCAAAAwAVAAkKcByqCAAAAwAWAAcKhxnUFAAHAgAAAA==.',
Na='Nalgotica:BAAANQADCgMIAwAAAA==.Nalynahwe:BAAANQADCggJGwAAAA==.Narima:BAAANQAECgQIBgAAAA==.Nathronso:BAAANQADCgUIBQAAAA==.Nauticâ:BAAANQABCgYICAAAAA==.Navirose:BAAANQADCggIDwAAAA==.',
Ne='Necromos:BAAANQADCggIBgAAAA==.Neltheron:BAAANQADCgMIAwAAAA==.',
Nh='Nhala:BAAANQADCgUICAABNQADCggICQACAAAAAA==.',
Ni='Niavarr:BAAANQAECgYIBgAAAA==.Nightestrike:BAAANQAECgQIBgAAAA==.Ninali:BAAANQAECgEIAQAAAA==.Niuven:BAAANQAECggIBwAAAA==.Nivek:BAAANQADCgUICQAAAA==.',
No='Noralai:BAAANQADCgUIBAAAAA==.Nore:BAAANQAECgIJAgAAAA==.',
Nt='Ntviss:BAAANQADCgYIBgAAAA==.',
Ny='Nyali:BAAANQADCgQIBAABNQAECgUJBQACAAAAAA==.',
['Nà']='Nàdya:BAAANQAECgYIDQAAAA==.',
Ob='Oblivions:BAAANQAECgcIDwAAAA==.',
Od='Odasa:BAAANQAECgQIBQAAAA==.Odikios:BAAANQABCgEIAQAAAA==.',
Og='Ogion:BAAANQADCggICAAAAA==.',
Ol='Olahn:BAAANQADCggICQAAAA==.',
On='Onekark:BAAANQAECgYJDwABNQAFFAYIEAAEAAgXAA==.Onlysins:BAAANQADCggJGwAAAA==.',
Or='Orckus:BAAANQADCgYIGgAAAA==.Oreosbunny:BAAANQAECgUJCgAAAA==.Orìhimè:BAAANQABCgQIBAAAAA==.',
Pa='Padma:BAAANQADCgUIBAAAAA==.Pandaburn:BAAANQAECgQJBAAAAA==.Pandalock:BAAANQADCgYIBgAAAA==.Pandsome:BAAANQADCgUJCAAAAA==.Paroxism:BAABNQAECoEfAAISAAkKwSAILgD2AQASAAkKwSAILgD2AQAAAA==.Parzival:BAAANQADCgEIAQABNQADCgQJBAACAAAAAA==.',
Pe='Peanût:BAAANQAECgUICAAAAA==.Peautiful:BAAANQADCgMIBAAAAA==.',
Ph='Phaket:BAAANQAECgYIEQAAAA==.',
Pi='Picaduro:BAAANQADCgYICQAAAA==.Picture:BAAANQADCgcIEgABNQAECgkJGAAEAHkcAA==.Pika:BAAANQAECgUJBgAAAA==.Pippá:BAAANQADCggIDwAAAA==.',
Po='Pockethealer:BAAANQAECgEIAQAAAA==.Polonius:BAAANQAECgQIBwAAAA==.Potato:BAAANQADCgIIAgAAAA==.',
Pr='Probation:BAAANQADCgUICAAAAA==.',
Pu='Puchideperro:BAAANQAECgEIAgAAAA==.Pujo:BAAANQABCgUIBAAAAA==.',
Pw='Pwil:BAAANQABCgMIAwABNQADCgYIBgACAAAAAA==.',
Py='Pythe:BAAANQAECgUJDQAAAA==.',
Qa='Qap:BAAANQAECgIIAwAAAA==.',
Qi='Qingu:BAAANQAECgcJEgAAAA==.',
Qu='Qualnorr:BAAANQADCgcJHAAAAA==.Queldraayan:BAAANQAECgIJBAAAAA==.Quinnter:BAEANQAECgQIBQAAAA==.Quixxie:BAEANQADCggICAABNQAECgQIBQACAAAAAA==.',
Qw='Qwil:BAAANQABCgYICwABNQADCgYIBgACAAAAAA==.',
Ra='Radagon:BAAANQAECgYIEgABNQAECgYIEAACAAAAAA==.Radalas:BAAANQAECgQJBgAAAA==.Radreliris:BAAANQAECgEJAQAAAA==.Raelithi:BAAANQABCgMJAwAAAA==.Raisulad:BAAANQABCgEIAgAAAA==.Rally:BAAANQAECgEIAQAAAA==.Ramcco:BAEANQAECgQIBgAAAA==.Ranelle:BAAANQAECgUJDQAAAA==.Rasmira:BAAANQAECgEIAQAAAA==.Ravenis:BAABNQAECoEaAAIWAAkKHSHzBQAGAwAWAAkKHSHzBQAGAwAAAA==.',
Re='Rebekkah:BAAANQADCgQIBAAAAA==.Reedem:BAAANQADCggIKgAAAA==.Regilock:BAACNQAFFIESAAQIAAYK9R7XAABCAgAIAAYK9R7XAABCAgAJAAIKqhIhCACuAAANAAEKjhNuBgBRAAA1AAQKgTUABAgACQqQJvEDAI0DAAgACAqiJvEDAI0DAAkABAowJZEXAJgBAA0AAQr6JV4WAG4AAAAA.Reikí:BAAANQAECgQIBAABNQAECgcJFwAFACEcAA==.Reservoir:BAAANQADCgIIAgAAAA==.Revgard:BAAANQADCgYIAQAAAA==.',
Rh='Rhaenyrra:BAAANQAECgYIDwAAAA==.Rhaily:BAAANQADCgIIAgAAAA==.Rhallin:BAAANQADCggIDQAAAA==.',
Ro='Ronso:BAAANQADCgQJBAAAAA==.Rosiel:BAAANQABCgQIBQAAAA==.Rowain:BAAANQAECgUJDQAAAA==.',
Ry='Rylacus:BAAANQAECgIJAwAAAA==.Rylii:BAAANQAECgIJAwAAAA==.',
Sa='Saanda:BAAANQADCggIEAAAAA==.Salandre:BAAANQADCggICAAAAA==.Sarlef:BAAANQAECgQJBQAAAA==.',
Sc='Scarm:BAAANQAECgIIBAAAAA==.Scathed:BAAANQAECggICwAAAA==.Scorpix:BAAANQADCgcIFQAAAA==.',
Se='Seaflower:BAAANQADCggJCwAAAA==.Seig:BAAANQADCgQIBAAAAA==.Sellidra:BAAANQAECgQJBgAAAA==.Serenitara:BAAANQADCggIEwAAAA==.Serifanlord:BAAANQAECgEJAgAAAA==.',
Sh='Shaaddow:BAAANQAECgEIAQAAAA==.Shaffer:BAAANQAECgQIBgAAAA==.Shamanlady:BAAANQABCgcJCQAAAA==.Shamwhoa:BAAANQABCgQIBwAAAA==.Shardera:BAAANQABCgEIAQAAAA==.Shellshocker:BAAANQAFFAEIAQAAAA==.Sheng:BAAANQADCgUJBQAAAA==.Shermantånk:BAAANQADCgYICAAAAA==.Sheydon:BAAANQADCgcJBwAAAA==.Shikigamï:BAAANQAECgEJAQABNQAECgUICQACAAAAAA==.Shikï:BAAANQAECgUICQAAAA==.Shivermoón:BAAANQAECgYJEAAAAA==.',
Si='Siegbane:BAAANQAECgMJAwAAAA==.Sigesar:BAAANQADCggIIwAAAA==.Sigrún:BAAANQAECgEIAQAAAA==.Simpforsouls:BAAANQADCgMIAwAAAA==.Sinsimella:BAAANQABCgYIBwAAAA==.',
Sk='Skullash:BAAANQADCgcIBwAAAA==.Skywatcher:BAAANQAECgQJBwAAAA==.',
Sm='Smitemare:BAAANQADCggIDQAAAA==.',
Sn='Sneakmode:BAAANQADCgcJEgAAAA==.Snicky:BAAANQAECgEJAQAAAA==.',
So='Sonwarr:BAAANQAECgcIEQAAAA==.',
Sp='Spliphtoker:BAAANQAECgEIAQAAAA==.',
St='Stabsolutely:BAAANQADCgUJBQABNQADCggIDQACAAAAAA==.Steelpen:BAAANQAECgMIAwAAAA==.Stenston:BAAANQAECgIJBAAAAA==.Sterede:BAAANQADCggJFwAAAA==.Stitchwhich:BAAANQAECgMJAwAAAA==.Stonehenge:BAAANQAECgQJBgAAAA==.Stormwolves:BAAANQADCgYICQAAAA==.',
Su='Summers:BAAANQAECgYJBwAAAA==.',
Sy='Sylphr:BAAANQAECgEIAQABNQAFFAEJAQACAAAAAA==.Sylphwild:BAAANQAECgQIBwABNQAFFAEJAQACAAAAAA==.Sylvara:BAAANQAECgQIBgAAAA==.Synkinz:BAAANQAECgQJBwAAAA==.Syntec:BAAANQABCgIIAgAAAA==.Syreite:BAAANQAECgIJBAAAAA==.',
Ta='Tacori:BAAANQAECgIJAgAAAA==.Taessa:BAAANQADCgMIAwAAAA==.Tainipuni:BAAANQADCgYIBgAAAA==.Takutantayo:BAAANQABCgEIAQAAAA==.Tallic:BAAANQAECgcIEQAAAA==.Talynayl:BAAANQADCgUIBwAAAA==.Tamarah:BAAANQAECgEIAQAAAA==.Tandemonium:BAAANQAECgUJBQABNQAECgkJIAAXALAjAA==.Taniz:BAAANQAECgYJDwAAAA==.Tarsi:BAAANQAECgEJAgAAAA==.',
Td='Td:BAABNQAFFIEIAAIFAAQK8g3QBwA7AQAFAAQK8g3QBwA7AQABNQAFFAgIHAAYAEMlAA==.',
Te='Tearinurside:BAAANQAECgEIAQAAAA==.Telidrel:BAAANQADCgIIAwAAAA==.',
Tg='Tgi:BAAANQAECgIJAgAAAA==.',
Th='Thaddeaus:BAAANQAECgYJEQAAAA==.Thaddeus:BAAANQAECgIJAgAAAA==.Thealin:BAAANQAECgMIAwAAAA==.Thebeefyone:BAAANQAECgIIBAAAAA==.Thecanadian:BAAANQADCgQIBAAAAA==.Thegreatmel:BAAANQADCgIIAgAAAA==.Therizin:BAAANQADCgcIBwAAAA==.Thesummoner:BAAANQAECgEIAQAAAA==.Thornel:BAAANQADCgEIAQAAAA==.Thorrek:BAAANQAECgcJDwAAAA==.Thumpette:BAAANQAECgIIBAAAAA==.',
Ti='Tierant:BAAANQADCgYIDwAAAA==.Tinaris:BAAANQADCgUICQABNQAECgUJBgACAAAAAA==.Tizaria:BAAANQAECgEIAgAAAA==.',
Tm='Tmai:BAAANQAECgEIAQAAAA==.',
To='Tominaetor:BAAANQADCgcJJAAAAA==.Tookans:BAAANQABCgUIBgAAAA==.Tosoto:BAAANQAECgUJDgAAAA==.Toxica:BAAANQADCgMIAwAAAA==.',
Tr='Travcula:BAAANQAECgYJDwAAAA==.Treefiddy:BAAANQADCgEIAgAAAA==.',
Ts='Tso:BAAANQADCgEIAQAAAA==.',
Tt='Ttriton:BAAANQADCgEIAQAAAA==.',
Tu='Tuuwa:BAAANQADCgMIAwAAAA==.',
Ty='Tyernan:BAAANQAECgUJCAAAAA==.Tyrioz:BAAANQAECgUJBgAAAA==.',
Tz='Tzavcat:BAAANQAECgIJAwAAAA==.',
Uh='Uhtred:BAAANQAECggIAgAAAA==.',
Un='Unknownmage:BAAANQABCgIIAgAAAA==.',
Ur='Urbi:BAAANQAECgQJBgAAAA==.',
Uv='Uvsol:BAAANQADCgQIBAAAAA==.',
Va='Vadailla:BAAANQAECgQIBwAAAA==.Vahrik:BAAANQADCgMIAwAAAA==.Valeirra:BAAANQADCgMIBQAAAA==.Valius:BAAANQAECgQJBQAAAA==.Valkyrae:BAAANQADCgQIBAAAAA==.Valornor:BAAANQAECgIJAgAAAA==.Vandill:BAABNQAECoEZAAIMAAgKBhGcfwAZAgAMAAgKBhGcfwAZAgAAAA==.Vaxis:BAAANQADCgYJDAAAAA==.',
Ve='Veasnacool:BAAANQAECgQJDAAAAA==.Vestrit:BAAANQADCgIIAgABNQAECgcJFwAFACEcAA==.',
Vo='Vontote:BAAANQAECgQJBQAAAA==.',
['Ví']='Víc:BAAANQAECgQJBwAAAA==.',
Wa='Wandorf:BAEANQAECgIJAgAAAA==.Warwolfe:BAAANQAECgYIDgAAAA==.Wayler:BAAANQADCggICAAAAA==.',
Wh='Whitewâlker:BAAANQABCgQIBAAAAA==.Whumpus:BAAANQADCgIIAgAAAA==.Whyn:BAAANQADCgUIBQAAAA==.',
Wi='Willei:BAAANQADCgUICwAAAA==.',
Wo='Wolferunner:BAAANQAECgIJAgAAAA==.',
Xa='Xaiden:BAAANQADCgcJBwAAAA==.Xaldora:BAAANQADCgEIAQAAAA==.Xanthrens:BAAANQADCgIIAgAAAA==.',
Xd='Xdxvuu:BAAANQAECgUIDAAAAA==.',
Xe='Xerimok:BAAANQAECgIJAwAAAA==.',
Xi='Xinya:BAAANQAECgIJAwAAAA==.',
Xs='Xsmkmonk:BAAANQADCgUIBQAAAA==.',
Xz='Xzephyr:BAAANQAECgUJDQAAAA==.',
Ye='Yesmín:BAAANQAECgYIDAAAAA==.',
Yi='Yil:BAAANQAECgUJCAAAAA==.',
Yo='Youwas:BAAANQAECgEIAQAAAA==.',
Ys='Yshtola:BAAANQADCgYICwAAAA==.',
Yu='Yukmouf:BAAANQAECggICQAAAA==.Yuriika:BAAANQADCgYJBwAAAA==.Yuukmouf:BAAANQAECgQIBgABNQAECggICQACAAAAAA==.',
Za='Zakaris:BAAANQAECgMJBgAAAA==.Zaladin:BAAANQADCgUIBQAAAA==.Zarrove:BAAANQAECgcIEAAAAA==.Zawl:BAAANQAECgMIBAAAAA==.',
Ze='Zea:BAAANQADCgMIAwAAAA==.Zeltri:BAABNQAECoEhAAIZAAgK8QNHKQBZAQAZAAgK8QNHKQBZAQAAAA==.Zerg:BAAANQAECgIIAwAAAA==.',
Zh='Zhatva:BAABNQAECoEhAAMPAAkKRR8yMgBqAgAPAAgKciEyMgBqAgAYAAMKLBItWAA+AAAAAA==.Zhöe:BAAANQAECgUIBgAAAA==.',
Zi='Zimzhealz:BAAANQADCgcIDQAAAA==.Zimzorzz:BAAANQADCgUIBwABNQADCgcIDQACAAAAAA==.',
Zo='Zoelera:BAAANQAECgIIAgAAAA==.Zoldor:BAAANQAECgQJBwAAAA==.Zoleia:BAAANQADCgMIAwAAAA==.Zorellion:BAAANQAECgQJBwAAAA==.',
Zu='Zuay:BAAANQADCgIIAgABNQAECgQICQACAAAAAA==.Zulianguy:BAABNQAECoEYAAMUAAkK3B2IEAASAgAUAAYKWiCIEAASAgAaAAQKjxNOrwAIAQAAAA==.',
Zy='Zycorr:BAAANQAECgEIAQAAAA==.Zytrex:BAAANQAECgQJBAAAAA==.',
['Zá']='Zátsu:BAAANQABCgEIAQAAAA==.',
['Äm']='Ämaterasu:BAAANQADCgIIAgABNQAECgUICQACAAAAAA==.',
['Ñÿ']='Ñÿx:BAAANQAECgMJBAAAAA==.',
['ßl']='ßluerain:BAAANQABCgQICAAAAA==.',
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
