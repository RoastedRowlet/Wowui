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

local lookup = {'DeathKnight-Frost','Unknown-Unknown','Warrior-Protection','Shaman-Restoration','Shaman-Elemental','DemonHunter-Devourer','DeathKnight-Unholy','DeathKnight-Blood','Mage-Arcane','Monk-Windwalker','Shaman-Enhancement','Warrior-Arms','Druid-Balance','Monk-Brewmaster','Rogue-Assassination','Rogue-Subtlety','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','DemonHunter-Havoc','Hunter-Marksmanship','Hunter-BeastMastery',}
local provider = {region='US',realm='ArgentDawn',name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Abajaba:BAAANQADCgYIEAAAAA==.Abractus:BAAANQAECgIIAwAAAA==.',
Ad='Aderrig:BAAANQADCgQIBAAAAA==.Adriana:BAAANQAECgEIAQAAAA==.Adrianix:BAAANQAECgIIAgAAAA==.Adru:BAAANQAECgIIAgAAAA==.',
Ae='Aeglos:BAABNQAECoEVAAIBAAgJ4By2DgBkAgABAAgJ4By2DgBkAgAAAA==.Aehrick:BAAANQAECgEIAQAAAA==.Aentharion:BAAANQADCggIGwAAAA==.Aeyn:BAAANQABCgcIDgAAAA==.',
Ai='Aileen:BAAANQAECgQICAAAAA==.',
Al='Alakaz:BAAANQADCggICAAAAA==.Alidoro:BAAANQADCgEIAQAAAA==.Alisonia:BAAANQADCgIIBAAAAA==.Alitikar:BAAANQADCgQIBAAAAA==.Alleximage:BAAANQAECgIIAQAAAA==.Alliancepaly:BAAANQADCgMIAwAAAA==.Alorren:BAAANQAECgEIAQAAAA==.Aludor:BAAANQADCgEIAQAAAA==.',
Am='Ammo:BAAANQADCgUICgABNQAECgUICwACAAAAAA==.Amo:BAAANQABCggIFgABNQAECgUICwACAAAAAA==.Amodegas:BAAANQADCgYIBgABNQAECgUICwACAAAAAA==.Amodillo:BAAANQAECgUICwAAAA==.Amoe:BAAANQADCggICAABNQAECgUICwACAAAAAA==.Amonra:BAAANQADCgYICQAAAA==.Amynrar:BAAANQADCggIEAAAAA==.',
An='Angyaras:BAACNQAFFIEIAAIDAAUJMBs6AADXAQADAAUJMBs6AADXAQA1AAQKgRsAAgMACQkHJloAANsDAAMACQkHJloAANsDAAAA.Animos:BAAANQADCgMIAwAAAA==.',
Ap='Apiix:BAAANQAECgYICgAAAA==.',
Ar='Araaras:BAAANQAFFAIIAQAAAA==.Araiguma:BAAANQAECgcIDQAAAA==.Arcaisme:BAAANQAECgEIAQAAAA==.Arcticsnow:BAAANQADCgYIEQAAAA==.Ariealla:BAAANQADCgUIBQAAAA==.Arkose:BAAANQADCgYICgAAAA==.',
As='Aschen:BAAANQADCgIIAwAAAA==.Ashlyngrace:BAAANQAECgIIAgABNQAECggIGAAEAJkaAA==.Ashlynne:BAABNQAECoEYAAMEAAgJmRq1LQAHAgAEAAcJUhy1LQAHAgAFAAEJAAI+zwAiAAAAAA==.Aspensong:BAAANQADCggIGwAAAA==.Astracious:BAAANQADCggIIgAAAA==.Astrayice:BAAANQADCgQIBQAAAA==.',
At='Atarkormu:BAAANQADCgcIDwABNQAECgQIBwACAAAAAA==.Atax:BAAANQADCggIGwAAAA==.Athená:BAAANQAECgEIAQAAAA==.Atulkan:BAAANQAECgEIAQAAAA==.',
Au='Auralyn:BAAANQADCgUIBwAAAA==.Aurelitrasza:BAAANQADCgUIDQAAAA==.',
Av='Avrice:BAAANQADCggIEwAAAA==.Avris:BAAANQAECgEIAQAAAA==.',
Ay='Ayayaras:BAAANQAFFAIIAwABNQAFFAUICAADADAbAA==.',
Ba='Badshot:BAAANQADCgYIBgAAAA==.Bambu:BAAANQADCgYICQABNQADCgcIEQACAAAAAA==.Bamevoker:BAAANQADCgcIEQAAAA==.Bariggs:BAAANQAECgYIDQAAAA==.Barilia:BAAANQADCgEIAQAAAA==.',
Be='Beals:BAAANQAECgIIAgAAAA==.Beladra:BAAANQADCgQIBQAAAA==.Ben:BAAANQAECgMIBwAAAA==.Beriadan:BAAANQAECgYIDgAAAA==.Bevee:BAAANQAFFAEIAQAAAA==.',
Bi='Bisque:BAAANQADCgUIBQAAAA==.',
Bl='Bleddwen:BAAANQAECgEIAQAAAQ==.Blindseer:BAAANQABCgIIAgAAAA==.Blrsama:BAAANQAECgIIAwAAAA==.',
Bo='Bohrnir:BAAANQADCgUIBQAAAA==.Boozelee:BAAANQADCgMIAwAAAA==.Boüh:BAAANQAECgIIAgAAAA==.',
Br='Brutalix:BAAANQADCgEIAQAAAA==.',
Bu='Bubblesonyou:BAAANQAECgMIBQAAAA==.Burnadine:BAAANQAECgEIAQAAAA==.Burnswhnpee:BAAANQAECgUIBQAAAA==.',
Ca='Caliie:BAAANQADCggIGwAAAA==.Callektra:BAAANQADCggICwAAAA==.Callira:BAAANQADCgYIBgAAAA==.Captclamslam:BAAANQADCgcIDAAAAA==.Caw:BAAANQADCgMIAwABNQAECgIIAgACAAAAAA==.Cayuga:BAAANQADCgUICAAAAA==.',
Ch='Charå:BAAANQADCgUIBQAAAA==.Chintakari:BAAANQADCgcIBwAAAA==.',
Co='Cocidiae:BAAANQADCgQIBAAAAA==.Confusious:BAABNQAECoEWAAIEAAcJJR+lHwBeAgAEAAcJJR+lHwBeAgAAAA==.Coppers:BAAANQADCggICAAAAA==.Coree:BAAANQAECgEIAgAAAA==.Cornflower:BAAANQADCgYICQABNQAECgQIBwACAAAAAA==.Corvaan:BAABNQAECoEVAAIGAAgJxRFnGQAaAgAGAAgJxRFnGQAaAgAAAA==.',
Cr='Creg:BAAANQADCggIGgAAAA==.Crowbarr:BAAANQADCgYICwAAAA==.Cryostatic:BAAANQAECgEIAQABNQADCggIEgACAAAAAA==.',
Cu='Cultel:BAAANQAECgYICgAAAA==.',
Cy='Cyendia:BAAANQADCggIHgAAAA==.Cynlea:BAAANQADCgYIBgAAAA==.',
Da='Daddyraz:BAAANQADCgUICQAAAA==.Daemonquiver:BAAANQADCgUIBQAAAA==.Dahtotems:BAAANQAECgcIBwAAAA==.Daphcelyn:BAAANQADCgcIFgAAAA==.Dariusz:BAAANQAECgEIAQAAAA==.Darkalen:BAAANQAECgQIBwAAAA==.Darklodus:BAAANQADCgYICwAAAA==.Darksethia:BAAANQADCgQIBAAAAA==.Dathea:BAABNQAECoEcAAIEAAkJ0iDEBwA7AwAEAAkJ0iDEBwA7AwAAAA==.Daxetanlock:BAAANQAECgcIEwABNQAECgIIAgACAAAAAA==.Daxetans:BAAANQAECgIIAgAAAA==.',
De='Deathjingle:BAABNQAECoEWAAMHAAkJVhsXEQDNAgAHAAkJJxoXEQDNAgAIAAIJyB9lXQC2AAAAAA==.Deecayed:BAAANQAECgEIAQABNQAECggIEQACAAAAAA==.Deecoy:BAAANQAECgEIAQABNQAECggIEQACAAAAAA==.Deemonic:BAAANQADCggIDgABNQAECggIEQACAAAAAA==.Deerslayer:BAAANQABCgIIAgAAAA==.Deetermined:BAAANQAECggIEQAAAA==.Deloisela:BAAANQAECggIBQAAAA==.Denchy:BAAANQAECgIIAwAAAA==.Deylen:BAAANQAECgQIBAAAAA==.Deyndine:BAAANQAECgIIAwAAAA==.',
Di='Dizzyglaive:BAAANQADCgYIDQAAAA==.',
Dl='Dlkffjj:BAAANQAECgEIAQAAAA==.',
Dm='Dmdk:BAAANQAECgIIAQAAAA==.Dmrwr:BAAANQAECgcICwAAAA==.',
Do='Dodson:BAAANQADCgEIAQAAAA==.Dottarus:BAAANQADCgUIBQABNQADCggICQACAAAAAA==.',
Dr='Draelick:BAAANQABCgIIAgAAAA==.Driadora:BAAANQAECgIIAgAAAA==.Droataxm:BAABNQAECoEZAAIJAAgJVx/XPQCaAgAJAAgJVx/XPQCaAgAAAA==.Drogath:BAAANQADCgcIDQAAAA==.',
Du='Duarraag:BAAANQADCgYICQAAAA==.',
['Dâ']='Dâvïd:BAAANQAECgUICwAAAA==.',
['Dë']='Dëërez:BAAANQAECgIIAgABNQAECggIEQACAAAAAA==.',
Ei='Eililis:BAAANQADCgYIBwAAAA==.',
El='Elani:BAAANQAECgYICwAAAA==.Elaynaa:BAAANQAECgEIAQAAAA==.Elishaunt:BAAANQAECgEIAgAAAA==.Elleth:BAAANQAECgEIAQAAAA==.Elliana:BAAANQAECgQIBQAAAA==.Elogio:BAAANQADCgYIBgAAAA==.Elvoidra:BAAANQADCgUIBQAAAA==.',
Em='Emanymton:BAAANQADCgYIDwAAAA==.Embyr:BAAANQADCggIEAAAAA==.',
Er='Erisaria:BAAANQADCgcICgAAAA==.Erixi:BAAANQAECgEIAQAAAA==.Eryn:BAAANQADCgEIAQAAAA==.',
Es='Esaria:BAAANQADCgEIAQAAAA==.',
Ev='Evissier:BAAANQAECgYIDwAAAA==.',
Ex='Excelimagust:BAAANQADCgYIDgAAAA==.',
Fa='Faid:BAAANQAECgEIAQAAAA==.Failor:BAAANQADCgYIBgAAAA==.Falcdhruid:BAAANQADCgUICQAAAA==.Farundi:BAAANQADCgUIBQAAAA==.',
Fe='Felbutton:BAAANQADCgYIAQAAAA==.Felwit:BAAANQAECgUICQAAAA==.Fennec:BAAANQAECgEIAQAAAA==.Feralie:BAAANQADCgYIBgAAAA==.Ferroz:BAAANQAECgQIBAABNQAECgQIBwACAAAAAA==.',
Fl='Flamos:BAAANQAECgQIBAAAAA==.Flatline:BAAANQAECgIIAgAAAA==.Florabelle:BAAANQAECgQIBwAAAA==.Florid:BAAANQADCggIHAAAAA==.',
Fo='Foshomomo:BAAANQADCggIGwAAAA==.Fozzle:BAAANQAECgQIBwAAAA==.',
Fr='Frenndi:BAAANQADCgYIEQAAAA==.',
Fu='Fuknazuga:BAAANQAECgQIBwAAAA==.Furroz:BAAANQADCgYIBgABNQAECgQIBwACAAAAAA==.',
Fy='Fynedge:BAAANQAECgQIBwAAAA==.Fynnyntyss:BAAANQAECgQICAAAAA==.Fyrè:BAAANQAECgQICAAAAA==.',
Ga='Garthe:BAAANQADCgEIAQAAAA==.',
Ge='Geoma:BAAANQADCgUIBQAAAA==.Gerlock:BAAANQADCgUIBgAAAA==.',
Gh='Ghastrider:BAAANQABCgEIAQAAAA==.',
Gi='Gigatin:BAAANQAECgEIAQAAAA==.Githnor:BAAANQAECgQICAAAAA==.',
Go='Goldal:BAAANQADCgcIBwAAAA==.Gorellan:BAAANQADCgYIBgAAAA==.',
Gr='Grimwharf:BAAANQADCgUIBQAAAA==.Grum:BAAANQADCgQIBgAAAA==.Grunaelyn:BAAANQAECgEIAQAAAA==.',
Gu='Guerrier:BAAANQAECgMIAwAAAA==.Guiong:BAAANQADCgYICgAAAA==.',
Gy='Gynx:BAAANQADCgUIBQAAAA==.',
['Gö']='Göttlich:BAAANQADCgUIBQABNQADCgUIBwACAAAAAA==.',
Ha='Haidas:BAAANQADCgcIBwAAAA==.',
He='Heikuro:BAAANQAECgEIAQAAAA==.Heybestie:BAAANQADCggICAAAAA==.',
Ho='Holychonks:BAAANQADCgcIEAAAAA==.Honadain:BAAANQADCgcIFAAAAA==.Honornight:BAAANQADCggICAAAAA==.Hordestalker:BAAANQADCgUIBQAAAA==.Houtu:BAAANQAECgUICgAAAA==.',
Hw='Hweilan:BAAANQADCgYICQAAAA==.Hwil:BAAANQADCgYIBgAAAA==.',
Hy='Hydrokill:BAAANQADCggICAAAAA==.Hypnos:BAAANQADCgYIDgAAAA==.',
['Hö']='Hölyföx:BAAANQAECgEIAQAAAA==.',
Ia='Iamearl:BAAANQADCggIIQAAAA==.',
In='Incidental:BAABNQAECoEYAAIKAAgJIyFbCADcAgAKAAgJIyFbCADcAgAAAA==.Inconell:BAAANQAECgQIBAAAAA==.Invega:BAAANQAECgIIAgAAAA==.',
Ir='Iric:BAAANQADCgMIAwAAAA==.Irino:BAAANQADCgUIBQAAAA==.',
Is='Isabelle:BAAANQAECgMIBQAAAA==.',
Iz='Izaer:BAAANQAECgEIAQAAAA==.Iziel:BAAANQAECgEIAQAAAA==.Izumex:BAAANQADCggICAAAAA==.',
Ja='Jabzaklok:BAAANQADCgcIFwAAAA==.Jacky:BAAANQAFFAEIAQAAAA==.Jahirah:BAAANQAECgEIAQABNQAECgQIBgACAAAAAA==.Jaida:BAAANQAECgQICAAAAA==.Jaleika:BAAANQAECgQIBgAAAA==.Jarius:BAAANQADCggIGAAAAA==.',
Je='Jean:BAAANQAECgYIEQAAAA==.Jeez:BAAANQAECgMIAwAAAA==.Jesmaríe:BAAANQADCggICAAAAA==.',
Jo='Johadd:BAAANQADCgEIAQAAAA==.Jonyy:BAAANQADCgQIBAAAAA==.Jorianna:BAAANQADCggIFAAAAA==.Joru:BAACNQAFFIEOAAILAAUJKBs/AAAAAgALAAUJKBs/AAAAAgA1AAQKgSMAAgsACQnsJWQAANoDAAsACQnsJWQAANoDAAAA.',
Ju='Jurauth:BAAANQABCgQIBAAAAA==.Justyna:BAAANQAECgEIAQAAAA==.Juze:BAAANQAECgQICQABNQAECgMIAQACAAAAAQ==.',
Ka='Kaai:BAAANQAECgEIAQAAAA==.Kabaul:BAABNQAECoEZAAIMAAgJJyITGAAJAwAMAAgJJyITGAAJAwAAAA==.Kabir:BAAANQAECgIIAwAAAA==.Kadria:BAAANQAECgEIAQAAAA==.Kailanii:BAAANQAECgEIAQAAAA==.Kalagon:BAAANQADCgEIAQAAAA==.Kalaman:BAAANQADCgQICAAAAA==.Kalito:BAAANQADCgMIAwAAAA==.Kamb:BAAANQADCggIFQAAAA==.Karalee:BAAANQADCgcIGAAAAA==.Katieey:BAACNQAFFIEOAAIEAAUJqiRmAQD9AQAEAAUJqiRmAQD9AQA1AAQKgRwAAgQACQnzJk0AAOsDAAQACQnzJk0AAOsDAAAA.Kaybee:BAAANQADCgYIDgAAAA==.Kayde:BAAANQADCgUIBQAAAA==.Kayil:BAAANQAECgYICgAAAA==.',
Ke='Kedalin:BAAANQADCgYIFQAAAA==.Kennyloggy:BAACNQAFFIEGAAINAAQJjBbDBABqAQANAAQJjBbDBABqAQA1AAQKgSEAAg0ACQmOI4wFAIEDAA0ACQmOI4wFAIEDAAAA.Kevris:BAAANQAECgEIAQABNQAECgQIBgACAAAAAA==.Keydan:BAAANQAECgEIAQAAAA==.',
Kl='Klassy:BAAANQAECgQICAAAAA==.',
Ko='Koppi:BAAANQADCgYICwAAAA==.Kotie:BAAANQADCgQIBQAAAA==.',
Kr='Kramz:BAAANQADCgcIBwAAAA==.Kreoss:BAAANQADCgMIAwABNQAECgYIDQACAAAAAA==.Kronar:BAAANQADCggILgAAAA==.Krongar:BAAANQADCgQIBAAAAA==.Krumblo:BAEANQAECgIIAgAAAA==.Kryztof:BAAANQABCgQIAgAAAA==.',
Ku='Kunea:BAAANQADCgYIBgAAAA==.Kungfujace:BAAANQADCgYICwAAAA==.',
Ky='Kyrgune:BAAANQADCggIEwAAAA==.',
['Kà']='Kàhlan:BAAANQADCgYIBgAAAA==.',
La='Laoftey:BAAANQAECgYICgAAAA==.Larquin:BAAANQAECgQIBgAAAA==.Lasmori:BAAANQAECgEIAQABNQAECgYICwACAAAAAA==.Laurenorder:BAAANQADCggIDgABNQAECgEIAQACAAAAAA==.Laxxbroo:BAAANQADCgUICQAAAA==.',
Le='Leam:BAAANQAECgEIAQAAAA==.Leglock:BAAANQAECgIIAgAAAA==.',
Li='Liendria:BAAANQAECgIIAwAAAA==.Lifensoftpaw:BAABNQAECoEfAAMKAAkJ7iL8BAA2AwAKAAkJ7iL8BAA2AwAOAAQJzBR+EQAXAQAAAA==.Lightemup:BAAANQAECgIIAgAAAA==.Lightkeeper:BAAANQABCgQIAgAAAA==.Likkash:BAAANQADCggICAABNQAECgQIBwACAAAAAA==.Limildea:BAAANQADCgIIAgAAAA==.Linthabeela:BAAANQADCgEIAQAAAA==.Liquidchiken:BAAANQAECgQIBAAAAA==.Lishalthen:BAAANQADCggIFwAAAA==.Littletouch:BAAANQADCgIIAgAAAA==.Livicecia:BAAANQAECgIIAgAAAA==.',
Lu='Lucciana:BAAANQADCgEIAQAAAA==.Lucielinna:BAAANQADCgUIBQABNQAECgEIAQACAAAAAA==.Luckiiem:BAAANQAECgYICgAAAA==.Luisfriendsn:BAAANQAECgEIAQABNQAFFAEIAQACAAAAAA==.Lumbo:BAEANQAECgIIAgABNQAECgIIAgACAAAAAA==.Lunare:BAAANQADCgUIBQAAAA==.Lunarkin:BAAANQADCggIEQAAAA==.Luthane:BAAANQAECgIIAwAAAA==.',
Ly='Lykinea:BAAANQADCgYIBgAAAA==.Lytebrite:BAAANQAECgYICgAAAA==.',
['Lü']='Lümßo:BAEANQAECgIIAgABNQAECgIIAgACAAAAAA==.',
Ma='Mainos:BAAANQADCgIIAgAAAA==.Makanai:BAAANQAECgEIAQAAAA==.Makishi:BAAANQAECgIIAwAAAA==.Malferious:BAAANQADCgIIAgAAAA==.Malfura:BAAANQAECgEIAQAAAA==.Malário:BAAANQAECgQIBgAAAA==.Mattedfurry:BAAANQAECgIIAgAAAA==.Maube:BAAANQADCgcIBwABNQADCggICAACAAAAAA==.Mazzarzul:BAAANQADCgYIFAABNQAECgYIEAACAAAAAA==.',
Me='Meebles:BAAANQAECgQICAAAAA==.Meiana:BAAANQAECgUIBwAAAA==.Melasmus:BAAANQABCgYICgAAAA==.Mes:BAAANQAECgQIBwAAAA==.',
Mi='Micklaa:BAAANQAECgIIAgAAAA==.Miebi:BAAANQADCgYICwABNQAECgYIEQACAAAAAA==.Milkbunny:BAAANQADCgUICQAAAA==.Mingtai:BAAANQAECgEIAQAAAA==.Misskaitlyn:BAAANQADCgcIBwAAAA==.',
Mo='Moirrah:BAAANQADCgYIBgABNQAECgEIAQACAAAAAA==.Moonriver:BAAANQAECgQIBAAAAA==.Moranta:BAAANQAECgIIAwAAAA==.Moressandra:BAAANQAECgEIAQAAAA==.Morgaes:BAAANQADCgYIEgAAAA==.Mortannon:BAAANQAECgIIAgAAAA==.Morîarty:BAAANQADCgIIAgAAAA==.',
Mu='Mushy:BAAANQADCgEIAQAAAA==.',
My='Mydruid:BAAANQAECgMIBAABNQAECggIGQAPAHUdAA==.Mysticarc:BAAANQADCgYIBgAAAA==.Mysticmurv:BAAANQAECgYIEAAAAA==.Mywarlock:BAABNQAECoEZAAMPAAgJdR2DFgDbAQAQAAcJhxlDEQAbAgAPAAYJzBqDFgDbAQAAAA==.',
Na='Nalgotica:BAAANQADCgMIAwAAAA==.Nalynahwe:BAAANQADCggIEwAAAA==.Narima:BAAANQAECgIIAwAAAA==.Nathronso:BAAANQADCgUIBQAAAA==.Nauticâ:BAAANQABCgYIBwAAAA==.Navirose:BAAANQADCggIDwAAAA==.',
Ne='Necromos:BAAANQADCggIBgAAAA==.',
Nh='Nhala:BAAANQADCgUICAABNQADCggICQACAAAAAA==.',
Ni='Niavarr:BAAANQADCgEIAQAAAA==.Nightestrike:BAAANQAECgIIAgAAAA==.Ninali:BAAANQAECgEIAQAAAA==.Nivek:BAAANQADCgUICQAAAA==.',
No='Noralai:BAAANQADCgUIBAAAAA==.Nore:BAAANQADCggIGAAAAA==.',
['Nà']='Nàdya:BAAANQAECgUIDAAAAA==.',
Ob='Oblivions:BAAANQAECgYICAAAAA==.',
Od='Odasa:BAAANQAECgEIAQAAAA==.',
Ol='Olahn:BAAANQADCggICQAAAA==.',
On='Onekark:BAAANQAECgUICQABNQAFFAUICgAEACIOAA==.Onlysins:BAAANQADCggIEwAAAA==.',
Or='Orckus:BAAANQADCgYIFAAAAA==.Oreosbunny:BAAANQAECgQIBQAAAA==.Orìhimè:BAAANQABCgQIBAAAAA==.',
Pa='Padma:BAAANQADCgUIBAAAAA==.Pandaburn:BAAANQADCggIEgAAAA==.Pandalock:BAAANQADCgYIBgAAAA==.Pandsome:BAAANQADCgUICAAAAA==.Paroxism:BAABNQAECoEYAAINAAgJwCHICwAmAwANAAgJwCHICwAmAwAAAA==.Parzival:BAAANQADCgEIAQAAAA==.',
Pe='Peanût:BAAANQAECgIIAwAAAA==.Peautiful:BAAANQADCgMIBAAAAA==.',
Ph='Phaket:BAAANQAECgYICwAAAA==.',
Pi='Picaduro:BAAANQADCgYICQAAAA==.Picture:BAAANQADCgcIEgABNQAECgcIFgAEACUfAA==.Pika:BAAANQAECgEIAQAAAA==.Pippá:BAAANQADCggIDwAAAA==.',
Po='Polonius:BAAANQAECgMIAwAAAA==.Potato:BAAANQADCgIIAgAAAA==.',
Pr='Probation:BAAANQADCgUICAAAAA==.',
Pu='Puchideperro:BAAANQAECgEIAgAAAA==.',
Pw='Pwil:BAAANQABCgMIAgABNQADCgYIBgACAAAAAA==.',
Py='Pythe:BAAANQAECgQICAAAAA==.',
Qa='Qap:BAAANQAECgIIAwAAAA==.',
Qi='Qingu:BAAANQAECgYICwAAAA==.',
Qu='Qualnorr:BAAANQADCgcIFQAAAA==.Queldraayan:BAAANQAECgIIAwAAAA==.Quinnter:BAEANQAECgEIAQAAAA==.Quixxie:BAEANQADCggICAABNQAECgEIAQACAAAAAA==.',
Qw='Qwil:BAAANQABCgYICgABNQADCgYIBgACAAAAAA==.',
Ra='Radagon:BAAANQAECgYIDAABNQAECgUICgACAAAAAA==.Radalas:BAAANQAECgIIAgAAAA==.Radreliris:BAAANQADCggIDwAAAA==.Raelithi:BAAANQABCgMIAQAAAA==.Raildo:BAAANQADCggICAAAAA==.Rally:BAAANQAECgEIAQAAAA==.Ramcco:BAEANQAECgIIAgAAAA==.Ranelle:BAAANQAECgQICAAAAA==.Rasmira:BAAANQADCgYIEgAAAA==.Ravenis:BAAANQAECgcIEAAAAA==.',
Re='Rebekkah:BAAANQADCgQIBAAAAA==.Reedem:BAAANQADCggIIgAAAA==.Regilock:BAACNQAFFIENAAQRAAYJTh3fAADvAQARAAUJqx7fAADvAQASAAIJqhJkBQCyAAATAAEJjhMSBABSAAA1AAQKgRoABBEACQlQJrYKABMDABEABwloJrYKABMDABIABAkwJYgVAJ0BABMAAQn6JRISAHAAAAAA.Reikí:BAAANQAECgQIBAABNQAECgYIDgACAAAAAA==.Revgard:BAAANQADCgYIAQAAAA==.',
Rh='Rhaenyrra:BAAANQAECgUICQAAAA==.Rhaily:BAAANQADCgIIAgAAAA==.Rhallin:BAAANQADCggIDQAAAA==.',
Ro='Ronso:BAAANQADCgQIBAAAAA==.Rosiel:BAAANQABCgQIBAAAAA==.Rowain:BAAANQAECgQICAAAAA==.',
Ry='Rylacus:BAAANQAECgEIAQAAAA==.Rylii:BAAANQAECgEIAQAAAA==.',
Sa='Saanda:BAAANQADCggIEAAAAA==.Sarlef:BAAANQAECgEIAQAAAA==.',
Sc='Scarm:BAAANQAECgIIAwAAAA==.Scathed:BAAANQAECggICQAAAA==.Scorpix:BAAANQADCgcIDwAAAA==.',
Se='Seaflower:BAAANQADCgcICwAAAA==.Seig:BAAANQADCgQIBAAAAA==.Sellidra:BAAANQAECgIIAgAAAA==.Serenitara:BAAANQADCgcIEwAAAA==.Serifanlord:BAAANQAECgEIAgAAAA==.',
Sh='Shaaddow:BAAANQADCgUIBwAAAA==.Shaffer:BAAANQAECgQIBgAAAA==.Shamanlady:BAAANQABCgYIBgAAAA==.Shamwhoa:BAAANQABCgQIBwAAAA==.Shellshocker:BAAANQAECggIEQAAAA==.Sheng:BAAANQADCgUIBQAAAA==.Shermantånk:BAAANQADCgYICAAAAA==.Shikigamï:BAAANQAECgEIAQABNQAECgQIBAACAAAAAA==.Shikï:BAAANQAECgQIBAAAAA==.Shivermoón:BAAANQAECgUICgAAAA==.',
Si='Siegbane:BAAANQAECgMIAwAAAA==.Sigesar:BAAANQADCggIGwAAAA==.Sigrún:BAAANQAECgEIAQAAAA==.Simpforsouls:BAAANQADCgMIAwAAAA==.Sinsimella:BAAANQABCgYIBgAAAA==.',
Sk='Skullash:BAAANQADCgcIBwAAAA==.Skywatcher:BAAANQAECgIIAwAAAA==.',
Sm='Smitemare:BAAANQADCgcIBwAAAA==.',
Sn='Sneakmode:BAAANQADCgYICwAAAA==.Snicky:BAAANQADCgYICwAAAA==.',
So='Sonwarr:BAAANQAECgUICgAAAA==.',
Sp='Spliphtoker:BAAANQADCggIIQAAAA==.',
St='Steelpen:BAAANQAECgIIAwAAAA==.Stenston:BAAANQAECgIIAwAAAA==.Sterede:BAAANQADCgYIFQAAAA==.Stitchwhich:BAAANQADCggIEgAAAA==.Stonehenge:BAAANQAECgIIAgAAAA==.Stormwolves:BAAANQADCgMIAwAAAA==.',
Su='Summers:BAAANQAECgEIAQAAAA==.',
Sy='Sylphr:BAAANQAECgEIAQABNQAECgkJGQAIAJoSAA==.Sylphwild:BAAANQAECgQIBwABNQAECgkJGQAIAJoSAA==.Sylvara:BAAANQAECgIIAgAAAA==.Synkinz:BAAANQAECgIIAwAAAA==.Syntec:BAAANQABCgIIAgAAAA==.Syreite:BAAANQAECgEIAgAAAA==.',
Ta='Tacori:BAAANQADCgYICAAAAA==.Taessa:BAAANQADCgMIAwAAAA==.Tallic:BAAANQAECgYICgAAAA==.Talynayl:BAAANQADCgUIBwAAAA==.Tamarah:BAAANQAECgEIAQAAAA==.Tandemonium:BAAANQADCgUICwABNQAECgkJGgAUALAjAA==.Taniz:BAAANQAECgUICQAAAA==.Tarsi:BAAANQAECgEIAQAAAA==.',
Td='Td:BAAANQAFFAMIAwABNQAFFAcIFAAVAHMlAA==.',
Te='Tearinurside:BAAANQAECgEIAQAAAA==.Telidrel:BAAANQADCgIIAwAAAA==.',
Tg='Tgi:BAAANQAECgIIAgAAAA==.',
Th='Thaddeaus:BAAANQAECgUICwAAAA==.Thaddeus:BAAANQADCggIGwAAAA==.Thebeefyone:BAAANQAECgIIAwAAAA==.Thecanadian:BAAANQADCgQIBAAAAA==.Thegreatmel:BAAANQADCgIIAgAAAA==.Therizin:BAAANQADCgcIBwAAAA==.Thesummoner:BAAANQAECgEIAQAAAA==.Thornel:BAAANQADCgEIAQAAAA==.Thorrek:BAAANQAECgcICQAAAA==.Thumpette:BAAANQAECgEIAQAAAA==.',
Ti='Tierant:BAAANQADCgUICQAAAA==.Tinaris:BAAANQADCgUIBQABNQAECgEIAQACAAAAAA==.Tizaria:BAAANQAECgEIAgAAAA==.',
Tm='Tmai:BAAANQAECgEIAQAAAA==.',
To='Tominaetor:BAAANQADCgcIJAAAAA==.Tookans:BAAANQABCgUIBQAAAA==.Tosoto:BAAANQAECgQICQAAAA==.Toxica:BAAANQADCgMIAwAAAA==.',
Tr='Travcula:BAAANQAECgUICQAAAA==.Treefiddy:BAAANQADCgEIAgAAAA==.',
Ts='Tso:BAAANQADCgEIAQAAAA==.',
Tt='Ttriton:BAAANQADCgEIAQAAAA==.',
Tu='Tuuwa:BAAANQADCgMIAwAAAA==.',
Ty='Tyernan:BAAANQAECgQIBwAAAA==.Tyrioz:BAAANQAECgEIAQAAAA==.',
Tz='Tzavcat:BAAANQAECgEIAQAAAA==.',
Uh='Uhtred:BAAANQAECggIAgAAAA==.',
Un='Unknownmage:BAAANQABCgIIAgAAAA==.',
Ur='Urbi:BAAANQAECgIIAgAAAA==.',
Uv='Uvsol:BAAANQADCgQIBAAAAA==.',
Va='Vadailla:BAAANQAECgIIAwAAAA==.Vahrik:BAAANQABCgMIAwAAAA==.Valeirra:BAAANQADCgMIBQAAAA==.Valius:BAAANQAECgEIAQAAAA==.Valkyrae:BAAANQADCgQIBAAAAA==.Valornor:BAAANQADCgIIAgAAAA==.Vandill:BAAANQAECgYIDwAAAA==.Vaxis:BAAANQADCgYIBgAAAA==.',
Ve='Veasnacool:BAAANQAECgQIBwAAAA==.Vestrit:BAAANQADCgIIAgABNQAECgYIDgACAAAAAA==.',
Vo='Vontote:BAAANQAECgEIAQAAAA==.',
['Ví']='Víc:BAAANQAECgIIAwAAAA==.',
Wa='Wandorf:BAEANQADCggIGgAAAA==.Warwolfe:BAAANQAECgQICAAAAA==.Wayler:BAAANQADCggICAAAAA==.',
Wh='Whitewâlker:BAAANQABCgMIAwAAAA==.Whumpus:BAAANQADCgIIAgAAAA==.',
Wi='Willei:BAAANQADCgUICwAAAA==.',
Wo='Wolferunner:BAAANQAECgIIAgAAAA==.',
Xa='Xaiden:BAAANQADCgcIBwAAAA==.Xaldora:BAAANQADCgEIAQAAAA==.',
Xd='Xdxvuu:BAAANQAECgUICgAAAA==.',
Xe='Xerimok:BAAANQAECgEIAQAAAA==.',
Xi='Xinya:BAAANQAECgEIAQAAAA==.',
Xs='Xsmkmonk:BAAANQADCgUIBQAAAA==.',
Xz='Xzephyr:BAAANQAECgQICAAAAA==.',
Ye='Yesmín:BAAANQAECgUIBwAAAA==.',
Yi='Yil:BAAANQAECgQIBwAAAA==.',
Yo='Youwas:BAAANQAECgEIAQAAAA==.',
Ys='Yshtola:BAAANQADCgYIBgAAAA==.',
Yu='Yukmouf:BAAANQAECgUIAwAAAA==.Yuriika:BAAANQADCgYIBwAAAA==.Yuukmouf:BAAANQAECgQIBgABNQAECgUIAwACAAAAAA==.',
Za='Zakaris:BAAANQAECgIIAgAAAA==.Zaladin:BAAANQADCgUIBQAAAA==.Zarrove:BAAANQAECgYICgAAAA==.Zawl:BAAANQAECgEIAQAAAA==.',
Ze='Zea:BAAANQADCgMIAwAAAA==.Zeltri:BAAANQAECgYIEAAAAA==.Zerg:BAAANQAECgIIAgAAAA==.',
Zh='Zhatva:BAABNQAECoEaAAMWAAkJ9R53EADzAgAWAAgJGCF3EADzAgAVAAEJ3Q1wRwBCAAAAAA==.Zhöe:BAAANQAECgUIBgAAAA==.',
Zi='Zimzhealz:BAAANQADCgcIDQAAAA==.Zimzorzz:BAAANQADCgUIBwABNQADCgcIDQACAAAAAA==.',
Zo='Zoelera:BAAANQADCggICgAAAA==.Zoldor:BAAANQAECgIIAwAAAA==.Zorellion:BAAANQAECgMIAwAAAA==.',
Zu='Zuay:BAAANQADCgIIAgABNQAECgcIFAAGACgbAA==.Zulianguy:BAAANQAFFAIIAgAAAA==.',
Zy='Zycorr:BAAANQAECgEIAQAAAA==.Zytrex:BAAANQADCgEIAQAAAA==.',
['Zá']='Zátsu:BAAANQABCgEIAQAAAA==.',
['Äm']='Ämaterasu:BAAANQADCgIIAgABNQAECgQIBAACAAAAAA==.',
['Ñÿ']='Ñÿx:BAAANQAECgEIAQAAAA==.',
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
