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

local lookup = {'DeathKnight-Frost','Unknown-Unknown','Priest-Holy','Priest-Discipline','Warrior-Protection','Mage-Arcane','Hunter-BeastMastery','Shaman-Restoration','Shaman-Elemental','Hunter-Survival','Paladin-Holy','Paladin-Retribution','DemonHunter-Devourer','DemonHunter-Vengeance','Warlock-Demonology','Warlock-Destruction','DeathKnight-Unholy','DeathKnight-Blood','Druid-Guardian','Rogue-Assassination','Warlock-Affliction','Monk-Windwalker','Shaman-Enhancement','Warrior-Arms','Priest-Shadow','Druid-Balance','Monk-Brewmaster','Paladin-Protection','Rogue-Subtlety','Mage-Frost','Druid-Restoration','DemonHunter-Havoc','Hunter-Marksmanship',}
local provider = {region='US',realm='ArgentDawn',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Abajaba:BAAANQADCggIGAAAAA==.Abractus:BAAANQAECgUIDAAAAA==.',
Ad='Aderrig:BAAANQADCgQIBAAAAA==.Adohlin:BAAANQABCgQIBAAAAA==.Adriana:BAAANQAECgUICgAAAA==.Adrianix:BAAANQAECgIIBgAAAA==.Adru:BAAANQAECgUIBwAAAA==.',
Ae='Aeglos:BAACNQAFFIEFAAIBAAMKfAjXCQDUAAABAAMKfAjXCQDUAAA1AAQKgR0AAgEACQqUHT4XAIsCAAEACQqUHT4XAIsCAAAA.Aehrick:BAAANQAECgQIBwAAAA==.Aentharion:BAAANQAECgIIBAAAAA==.Aeyn:BAAANQABCggIEgAAAA==.',
Af='Afflixen:BAAANQADCgQJBAABNQAECgMIAwACAAAAAA==.',
Ai='Aileen:BAAANQAECgYIDwAAAA==.',
Al='Alakaz:BAAANQAECgEIAQAAAA==.Aldehyde:BAAANQADCgUIBQAAAA==.Alidoro:BAAANQADCgEIAQAAAA==.Alisonia:BAAANQADCgMIBQAAAA==.Alitikar:BAAANQADCgQIBAAAAA==.Alleximage:BAAANQAECgIIAQAAAA==.Alliancepaly:BAAANQADCgMIAwAAAA==.Alorren:BAAANQAECgUICwAAAA==.Aludor:BAAANQADCgEIAQAAAA==.',
Am='Ammo:BAAANQADCgcIEQABNQAECggIFwADANocAA==.Amo:BAAANQABCggIHAABNQAECggIFwADANocAA==.Amodegas:BAAANQAECgMIAwABNQAECggIFwADANocAA==.Amodillo:BAABNQAECoEXAAMDAAgK2hxDJwCRAgADAAgK2hxDJwCRAgAEAAEKchsgHABRAAAAAA==.Amoe:BAAANQADCggICwABNQAECggIFwADANocAA==.Amonra:BAAANQADCgYICQAAAA==.Amynrar:BAAANQADCggIEAAAAA==.',
An='Andriia:BAAANQADCggICAAAAA==.Angyaras:BAACNQAFFIENAAIFAAUKMSOjAADnAQAFAAUKMSOjAADnAQA1AAQKgR0AAgUACQotJgABALcDAAUACQotJgABALcDAAAA.Animos:BAAANQADCgMIAwAAAA==.',
Ap='Apiix:BAABNQAECoEaAAIGAAgKMxEamAAMAgAGAAgKMxEamAAMAgAAAA==.',
Ar='Araaras:BAAANQAFFAEIAQAAAA==.Araiguma:BAAANQAECgcIDQABNQAECgkJKAAHAIslAA==.Arcaisme:BAAANQAECgQIBQAAAA==.Arcticsnow:BAAANQAECgUICQAAAA==.Ariealla:BAAANQADCgUIBQAAAA==.Arkose:BAAANQADCggIEgAAAA==.',
As='Aschen:BAAANQADCgIJAwAAAA==.Ashlyngrace:BAAANQAECgQIBgABNQAECgkJJAAIAD4dAA==.Ashlynne:BAABNQAECoEkAAMIAAkKPh3IHwC2AgAIAAkKPh3IHwC2AgAJAAEKAALuGAEgAAAAAA==.Aslynna:BAAANQAECggICAAAAA==.Aspensong:BAAANQAECgIIBAAAAA==.Astracious:BAAANQADCggIIgAAAA==.Astrayice:BAAANQADCgQIBQAAAA==.',
At='Atarkormu:BAAANQAECgQICAABNQAECgYIDgACAAAAAA==.Atax:BAAANQAECgIIBAAAAA==.Athená:BAAANQAECgIJAwAAAA==.Atulkan:BAAANQAECgQICQAAAA==.',
Au='Auralyn:BAAANQADCgYIDQAAAA==.Aurelitrasza:BAAANQADCgYJEwAAAA==.',
Av='Avalar:BAAANQADCgUIBQAAAA==.Avrice:BAAANQAECgIIAgAAAA==.Avris:BAAANQAECgEIAQAAAA==.',
Ay='Ayayaras:BAAANQAFFAMIBAABNQAFFAUIDQAFADEjAA==.Ayddayd:BAAANQADCgQIBAAAAA==.Aylianya:BAAANQAECgQIBAABNQAECgkJJAAIAD4dAA==.',
Ba='Badshot:BAAANQADCgYIBgAAAA==.Bambu:BAAANQADCgcIDQABNQAECgIIBAACAAAAAA==.Bamevoker:BAAANQAECgIIBAAAAA==.Bariggs:BAABNQAECoEZAAIKAAgKFSGlAgDRAgAKAAgKFSGlAgDRAgAAAA==.Barilia:BAAANQADCgMIBAAAAA==.',
Be='Beals:BAAANQAECgQJBgAAAA==.Beladra:BAAANQADCgQIBQAAAA==.Ben:BAAANQAECgcIEwAAAA==.Beriadan:BAABNQAECoEeAAIJAAgKvhxbKwCTAgAJAAgKvhxbKwCTAgAAAA==.Bevee:BAABNQAECoEcAAMLAAkKah9WCwBPAwALAAkKah9WCwBPAwAMAAEK+xCLUgEwAAAAAA==.',
Bi='Bigwheels:BAAANQADCgYIBAAAAA==.Bisque:BAAANQADCgUIBQAAAA==.Bitemare:BAAANQADCgIIAgABNQAECgEIAQACAAAAAA==.',
Bl='Bleddwen:BAAANQAECgQIBwAAAQ==.Blindseer:BAAANQABCgIIAgAAAA==.Blrsama:BAAANQAECgIIAwAAAA==.',
Bo='Bohrnir:BAAANQADCgUIBQAAAA==.Boozelee:BAAANQADCgMIAwAAAA==.Bozo:BAAANQAECgIIAgAAAA==.Boüh:BAAANQAECgUICwAAAA==.',
Br='Brutalix:BAAANQADCgEIAQAAAA==.',
Bu='Bubblesonyou:BAAANQAECgYJDgAAAA==.Burnadine:BAAANQAECgQIBwAAAA==.Burnswhnpee:BAAANQAECgYIEQAAAA==.',
Ca='Caliie:BAAANQAECgIIBAAAAA==.Callektra:BAAANQADCggICwAAAA==.Callira:BAAANQADCgYIBgAAAA==.Captclamslam:BAAANQAECgIIAgAAAA==.Carhop:BAAANQADCgIIAgAAAA==.Caverick:BAAANQADCggICAAAAA==.Caw:BAAANQADCgMIAwABNQAECgIIAgACAAAAAA==.Cayuga:BAAANQADCgUICAAAAA==.',
Ch='Charå:BAAANQADCgUIBQAAAA==.Chintakari:BAAANQAECgUICQAAAA==.',
Co='Cocidiae:BAAANQADCgYICgAAAA==.Confusious:BAABNQAECoEgAAIIAAkK8h0eEwAEAwAIAAkK8h0eEwAEAwAAAA==.Coppers:BAAANQADCggICAAAAA==.Coree:BAAANQAECgIICgAAAA==.Cornflower:BAAANQAECgQIBAABNQAECgYIEgACAAAAAA==.Corvaan:BAABNQAECoEXAAINAAkKLhBGIAAPAgANAAkKLhBGIAAPAgAAAA==.Corvhuunta:BAAANQAECgYIBgAAAA==.',
Cr='Creg:BAAANQADCggIIgAAAA==.Crowbarr:BAAANQADCgYICwAAAA==.Cryostatic:BAAANQAECgEIAQABNQAECgQIBwACAAAAAA==.',
Cu='Cultel:BAABNQAECoEbAAIOAAgKbBXZCAAGAgAOAAgKbBXZCAAGAgAAAA==.Cuulon:BAAANQADCgQIBgAAAA==.',
Cy='Cyendia:BAAANQAECgUICQAAAA==.Cynlea:BAAANQADCgYJCgAAAA==.',
Da='Daddyraz:BAAANQAECgQICAAAAA==.Daemonquiver:BAAANQAECgIIAgAAAA==.Dahtotems:BAAANQAECggIEgAAAA==.Daphcelyn:BAAANQADCggIJgAAAA==.Dariusz:BAAANQAECgUICgAAAA==.Darkalen:BAAANQAECgYIDgAAAA==.Darklodus:BAAANQADCgYICwAAAA==.Darksethia:BAAANQADCgQIBAAAAA==.Darksoul:BAAANQADCgQIBAAAAA==.Dathea:BAACNQAFFIEPAAIIAAUK4x4XBQDUAQAIAAUK4x4XBQDUAQA1AAQKgSsAAggACQo9IjgLAEUDAAgACQo9IjgLAEUDAAAA.Daxetanlock:BAABNQAECoElAAMPAAkKUSOfFAANAwAPAAgK/iKfFAANAwAQAAQKURu6JgAqAQABNQAECgIIAgACAAAAAA==.Daxetans:BAAANQAECgIIAgAAAA==.',
De='Deathjingle:BAABNQAECoEgAAMRAAkKuxvPIAB8AgARAAkKhhrPIAB8AgASAAQK8B7JVwBOAQAAAA==.Deecayed:BAAANQAECgEIAQABNQAECgkJJAAIAAIdAA==.Deecoy:BAAANQAECgIIAwABNQAECgkJJAAIAAIdAA==.Deemonic:BAAANQAECgIIAgABNQAECgkJJAAIAAIdAA==.Deerslayer:BAAANQABCgIIAgAAAA==.Deetermined:BAABNQAECoEkAAIIAAkKAh1sGwDOAgAIAAkKAh1sGwDOAgAAAA==.Deloisela:BAAANQAECggIEgAAAA==.Denalii:BAAANQADCggICAAAAA==.Denchy:BAAANQAECgQICgAAAA==.Deylen:BAAANQAECgUIDQAAAA==.Deyndine:BAAANQAECgUIDAAAAA==.',
Di='Dizzyglaive:BAAANQADCgYIDQAAAA==.',
Dl='Dlkffjj:BAAANQAECgEJAgAAAA==.',
Dm='Dmdk:BAAANQAFFAIIAgAAAA==.Dmrwr:BAAANQAFFAIIAgAAAA==.',
Do='Dodson:BAAANQADCgEIAQAAAA==.Dottarus:BAAANQADCgUIBQABNQAECgIIAgACAAAAAA==.',
Dr='Draegloth:BAAANQAECggIAgAAAA==.Draelick:BAAANQABCgIIAgAAAA==.Driadora:BAAANQAECgUICQAAAA==.Droataxm:BAABNQAECoEoAAIGAAkKih+KNgD/AgAGAAkKih+KNgD/AgAAAA==.Drogath:BAAANQADCgcIDQAAAA==.',
Du='Duarraag:BAAANQADCgYICQAAAA==.',
['Dâ']='Dâvïd:BAABNQAECoEdAAITAAgKlBlnCwA/AgATAAgKlBlnCwA/AgAAAA==.',
['Dä']='Däß:BAAANQADCgEJAQAAAA==.',
['Dë']='Dëërez:BAAANQAECgUICwABNQAECgkJJAAIAAIdAA==.',
Ei='Eililis:BAAANQADCgYIBwAAAA==.',
El='Elani:BAAANQAECgcIDQAAAA==.Elaynaa:BAAANQAECgQIBwAAAA==.Elishaunt:BAAANQAECgEJAwABNQABCggICQACAAAAAA==.Elleizah:BAAANQAECgIIAgABNQAECgkJLAAUAPkfAA==.Elleth:BAAANQAECgQIBQAAAA==.Elliana:BAAANQAECgYIDwABNQAECgYIDwACAAAAAA==.Elogio:BAAANQADCgYIEAAAAA==.Elvoidra:BAAANQADCgUIBQAAAA==.',
Em='Emanymton:BAAANQAECgEIAQAAAA==.Embyr:BAAANQADCggIIAAAAA==.Emiley:BAAANQAECgMIAwAAAA==.',
En='Envymeh:BAAANQADCgYICwAAAA==.',
Er='Erinn:BAAANQADCgUIBQAAAA==.Erisaria:BAAANQADCggJCgAAAA==.Erixi:BAAANQAECgQIBwAAAA==.Eryn:BAAANQADCgEIAQAAAA==.',
Es='Esaria:BAAANQADCgEIAQAAAA==.',
Ev='Evissier:BAABNQAECoEZAAIVAAkKmh8UAQA5AwAVAAkKmh8UAQA5AwAAAA==.',
Ex='Excelimagust:BAAANQAECgEIAQAAAA==.',
Fa='Faelada:BAAANQADCggIDQAAAA==.Faid:BAAANQAECgIIAgAAAA==.Failor:BAAANQADCgYIBgAAAA==.Falcdhruid:BAAANQADCgYIDwAAAA==.',
Fe='Felbutton:BAAANQAECgQIBAAAAA==.Felsen:BAAANQABCgEIAQABNQAECgcIFwAFAEIcAA==.Felwit:BAABNQAECoEXAAIFAAcKQhxXCwA0AgAFAAcKQhxXCwA0AgAAAA==.Fennec:BAAANQAECgUIBgAAAA==.Feralie:BAAANQADCgYIBgAAAA==.Ferroz:BAAANQAECgQICAABNQAECgYIDgACAAAAAA==.',
Fl='Flamos:BAAANQAECgQIBAAAAA==.Flatline:BAAANQAECgMJBQAAAA==.Florabelle:BAAANQAECgYIEgAAAA==.Florid:BAAANQADCggIHAAAAA==.',
Fo='Foshomomo:BAAANQAECgIIBAAAAA==.Fozzle:BAAANQAECgYIEgAAAA==.',
Fr='Frenndi:BAAANQADCggIGQAAAA==.',
Fu='Fuknazuga:BAAANQAECgQIBwAAAA==.Furroz:BAAANQAECgQIBAABNQAECgYIDgACAAAAAA==.',
Fy='Fynedge:BAAANQAECgYIEgAAAA==.Fynnyntyss:BAAANQAECgYIEwAAAA==.Fyrè:BAAANQAECgYIEwAAAA==.',
Ga='Garthe:BAAANQADCgEIAQAAAA==.',
Ge='Geoma:BAAANQADCgUIBQAAAA==.Gerlock:BAAANQADCgUIBgAAAA==.',
Gh='Ghastrider:BAAANQABCgEIAQAAAA==.Ghostlyt:BAAANQABCgEJAQAAAA==.',
Gi='Gigatin:BAAANQAECgUICwAAAA==.Githnor:BAAANQAECgYIEwAAAA==.',
Go='Goldal:BAAANQADCgcIBwAAAA==.Gorellan:BAAANQADCgYIDgAAAA==.',
Gr='Grimwharf:BAAANQAECgEIAQAAAA==.Grum:BAAANQADCgQIBgAAAA==.Grunaelyn:BAAANQAECgUICwAAAA==.',
Gu='Guerrier:BAAANQAECgYIDAAAAA==.Guiong:BAAANQADCgYICgAAAA==.',
Gy='Gynx:BAAANQAECgEIAQAAAA==.',
['Gö']='Göttlich:BAAANQADCgUIBQABNQADCgUIBwACAAAAAA==.',
Ha='Haidas:BAAANQADCggJDwAAAA==.Hardcheese:BAAANQABCgQIBAAAAA==.Hasuna:BAAANQADCgQIBAAAAA==.',
He='Heikuro:BAAANQAECgQICQAAAA==.Heybestie:BAAANQADCggICAAAAA==.',
Hi='Hillo:BAAANQAECgEIAQAAAA==.',
Ho='Holychonks:BAAANQADCgcIEAAAAA==.Hommy:BAAANQADCggICAAAAA==.Honadain:BAAANQADCggIIgAAAA==.Honornight:BAAANQADCggJDgAAAA==.Hordestalker:BAAANQADCgUIBQAAAA==.Houtu:BAABNQAECoEaAAIIAAgKTBCwVQC9AQAIAAgKTBCwVQC9AQAAAA==.',
Hw='Hweilan:BAAANQADCgYICQAAAA==.Hwil:BAAANQADCgYIBgAAAA==.',
Hy='Hydrokill:BAAANQADCggICAAAAA==.Hypnos:BAAANQAECgEIAQAAAA==.',
['Hö']='Hölyföx:BAAANQAECgEIAQAAAA==.',
Ia='Iamearl:BAAANQAECgMIBQAAAA==.',
In='Incidental:BAABNQAECoEnAAIWAAkKiSH9CAAaAwAWAAkKiSH9CAAaAwAAAA==.Inconell:BAAANQAECgQIBgAAAA==.Invega:BAAANQAECgIJAwAAAA==.',
Ir='Iric:BAAANQADCgMIBQAAAA==.Irino:BAAANQADCgUIBQAAAA==.',
Is='Isabelle:BAAANQAECgQIBwAAAA==.',
Iz='Izaer:BAAANQAECgIIBwAAAA==.Iziel:BAAANQAECgQIBQAAAA==.Izumex:BAAANQAECgMIAwAAAA==.',
Ja='Jabzaklok:BAAANQADCggIIgAAAA==.Jacky:BAAANQAFFAEIAQABNQAFFAMIBAACAAAAAA==.Jahirah:BAAANQAECgUICwABNQAECgUIEAACAAAAAA==.Jaida:BAAANQAECgQIDAAAAA==.Jaleika:BAAANQAECgYIDwAAAA==.Jarius:BAAANQAECgIIBAAAAA==.Jayabalard:BAAANQADCgQIBAABNQAECgYIDgACAAAAAA==.',
Je='Jean:BAABNQAECoEiAAIHAAgKdiGKFwANAwAHAAgKdiGKFwANAwAAAA==.Jeez:BAAANQAECgcIEQAAAA==.Jesmaríe:BAAANQAECgMIAwAAAA==.',
Jo='Johadd:BAAANQADCgEIAQAAAA==.Jonyy:BAAANQADCgUIBgAAAA==.Jorianna:BAAANQAECgIIBAAAAA==.Joru:BAACNQAFFIEaAAIXAAYKEhxrAABWAgAXAAYKEhxrAABWAgA1AAQKgS8AAhcACQpmJqEAANQDABcACQpmJqEAANQDAAAA.',
Ju='Jurauth:BAAANQABCgQIBAAAAA==.Justyna:BAAANQAECgQIBQAAAA==.Juze:BAAANQAECgQICQABNQAECgMIAQACAAAAAQ==.',
Ka='Kaai:BAAANQAECgMIBAAAAA==.Kabaul:BAABNQAECoEoAAIYAAkKJCQHDACEAwAYAAkKJCQHDACEAwAAAA==.Kabir:BAAANQAECgQICgAAAA==.Kadria:BAAANQAECgQIBwAAAA==.Kailanii:BAAANQAECgEIAQABNQAECgUICgACAAAAAA==.Kalagon:BAAANQADCgEIAQAAAA==.Kalaman:BAAANQADCgQICAAAAA==.Kalito:BAAANQADCgMIAwAAAA==.Kallivar:BAAANQAECgQIBgABNQAECgkJJwASAJcfAA==.Kamb:BAAANQAECgIIBAAAAA==.Karalee:BAAANQAECgQIBgAAAA==.Katieey:BAACNQAFFIEWAAIIAAYKuyQbAgBOAgAIAAYKuyQbAgBOAgA1AAQKgSEAAggACQrzJjoBAMkDAAgACQrzJjoBAMkDAAAA.Kaybee:BAAANQAECgEIAQAAAA==.Kayde:BAAANQADCgYIBgAAAA==.Kayil:BAABNQAECoEbAAIZAAgKqhKBHQAJAgAZAAgKqhKBHQAJAgAAAA==.',
Ke='Kedalin:BAAANQADCggIHQAAAA==.Kennyloggy:BAACNQAFFIEQAAIaAAYKCReGBAADAgAaAAYKCReGBAADAgA1AAQKgSgAAhoACQp6JIYJAGwDABoACQp6JIYJAGwDAAAA.Kevris:BAAANQAECgQIBQABNQAECgUIEAACAAAAAA==.Keydan:BAAANQAECgQIBwAAAA==.',
Ki='Kianni:BAAANQADCggICAAAAA==.Kirafrayen:BAAANQAECgEJAQABNQAECgYICAACAAAAAA==.',
Kl='Klassy:BAAANQAECgYIEwAAAA==.',
Ko='Koppi:BAAANQAECgEIAQAAAA==.Korru:BAAANQAECgMIBgAAAA==.Kotie:BAAANQADCgQIBQAAAA==.',
Kr='Kramz:BAAANQADCgcIDQAAAA==.Kreoss:BAAANQADCgQIBAABNQAECggIHgAIAFsPAA==.Kronar:BAAANQAECgUIEgAAAA==.Krongar:BAAANQADCgQIBAAAAA==.Krumblo:BAEANQAECgUIBwABNQAECgUIDAACAAAAAA==.Kryztof:BAAANQADCgYIBgAAAA==.',
Ku='Kuiraptor:BAAANQADCgcIDgAAAA==.Kunea:BAAANQADCgYIBgAAAA==.Kungfujace:BAAANQADCgYICwAAAA==.',
Ky='Kyrgune:BAAANQAECgEIAQAAAA==.',
['Kà']='Kàhlan:BAAANQADCgYIBgAAAA==.',
La='Laoftey:BAAANQAECgcIEwAAAA==.Larquin:BAAANQAECgUIEAAAAA==.Lasmori:BAAANQAECgUICQABNQAECgcIDQACAAAAAA==.Laurenorder:BAAANQAECgUICgAAAA==.Laxxbroo:BAAANQADCgcIEAAAAA==.',
Le='Leam:BAAANQAECgMIBwAAAA==.Leglock:BAAANQAECgUICwAAAA==.Leiff:BAAANQADCggICAAAAA==.Leprhicon:BAAANQAECgIIAgAAAA==.Lesbihonest:BAAANQAECgcICQAAAA==.',
Li='Liendria:BAAANQAECgYICwAAAA==.Lifensoftpaw:BAACNQAFFIEMAAIWAAUKpxZSBACYAQAWAAUKpxZSBACYAQA1AAQKgSkAAxYACQruIrALAO0CABYACQruIrALAO0CABsABQo5IFgOAMkBAAAA.Lightemup:BAAANQAECgMIBQAAAA==.Lightkeeper:BAAANQABCgQIAgAAAA==.Likkash:BAAANQAECgQIBAABNQAECgYIDgACAAAAAA==.Limildea:BAAANQADCgIIAgAAAA==.Linthabeela:BAAANQADCgEIAQAAAA==.Liquidchiken:BAAANQAECgQIBAAAAA==.Lishalthen:BAAANQADCggJFwAAAA==.Littletouch:BAAANQADCgIIAgAAAA==.Livicecia:BAAANQAECgQIBQAAAA==.',
Lu='Lucciana:BAAANQAECgMIBAABNQAECgMIBAACAAAAAA==.Lucielinna:BAAANQADCgUIBQABNQAECgIJAwACAAAAAA==.Luckiiem:BAABNQAECoEbAAIGAAgK/xxSVACvAgAGAAgK/xxSVACvAgAAAA==.Luisfriendsn:BAAANQAECgQIBwAAAA==.Lumbo:BAEANQAECgUIDAAAAA==.Lunare:BAAANQADCgUJBQAAAA==.Lunarkin:BAAANQAECgIIAwAAAA==.Luthane:BAAANQAECgMIBgAAAA==.',
Ly='Lykinea:BAAANQADCgYIBgAAAA==.Lytebrite:BAABNQAECoEcAAILAAgKKBPhQQAcAgALAAgKKBPhQQAcAgAAAA==.',
['Lí']='Líu:BAAANQADCggICAAAAA==.',
['Lü']='Lümßo:BAEANQAECgQIBAABNQAECgUIDAACAAAAAA==.',
Ma='Mainos:BAAANQADCgUIBwAAAA==.Maiyr:BAAANQAECgEJAQAAAA==.Makanai:BAAANQAECgQIBQAAAA==.Makishi:BAAANQAECgQICgAAAA==.Malferious:BAAANQADCgIIAgAAAA==.Malfura:BAAANQAECgMIBQAAAA==.Malário:BAAANQAECgQICwAAAA==.Manamontana:BAAANQADCgYIEAABNQAECgEIAQACAAAAAA==.Mattedfurry:BAAANQAECgIIAgAAAA==.Maube:BAAANQAECgEIAQABNQAECgkJGwAcAFoOAA==.Mazzarzul:BAAANQADCgYIGQABNQAECggIKwAKAK4cAA==.',
Me='Meebles:BAAANQAECgYIEwAAAA==.Meiana:BAAANQAECgYIEwAAAA==.Melasmus:BAAANQADCgUIBQAAAA==.Mes:BAAANQAECgQJBwAAAA==.',
Mi='Micklaa:BAAANQAECgQICQAAAA==.Miebi:BAAANQADCgYICwABNQAECggIJAAbAHAhAA==.Milkbunny:BAAANQADCgUICQAAAA==.Mingtai:BAAANQAECgMIBgAAAA==.Misskaitlyn:BAAANQADCgcIBwAAAA==.',
Mo='Moirrah:BAAANQADCgYIBgABNQAECgEIAQACAAAAAA==.Moonriver:BAAANQAECgUJCQAAAA==.Moonsinde:BAAANQAECggIBwAAAA==.Moranta:BAAANQAECgQICgAAAA==.Moressandra:BAAANQAECgQIAwAAAA==.Morfina:BAAANQAECgIIAQABNQAECgMIBQACAAAAAA==.Morgaes:BAAANQAECgQIBQAAAA==.Mortannon:BAAANQAECgUICwAAAA==.Morîarty:BAAANQADCgIIAgAAAA==.',
Mu='Mushy:BAAANQADCgEIAQAAAA==.',
My='Mydruid:BAAANQAECgQJBQABNQAECgkJLAAUAPkfAA==.Mysticarc:BAAANQADCgYIBgAAAA==.Mysticmurv:BAABNQAECoEbAAIGAAcKfwih3wB3AQAGAAcKfwih3wB3AQAAAA==.Mystieren:BAAANQAECgQJBAABNQAECgYIEgACAAAAAA==.Mywarlock:BAABNQAECoEsAAMUAAkK+R/bBgA6AwAUAAkKih/bBgA6AwAdAAcKLxqfFwD+AQAAAA==.',
Na='Nalgotica:BAAANQAECgIIAgAAAA==.Nalynahwe:BAAANQADCggJGwAAAA==.Narima:BAAANQAECgUICwAAAA==.Nathronso:BAAANQADCgUIBQAAAA==.Nauticâ:BAAANQABCgYICAAAAA==.Navirose:BAAANQADCggIDwAAAA==.',
Ne='Necromos:BAAANQADCggIBgAAAA==.Neltheron:BAAANQADCgMIAwAAAA==.',
Nh='Nhala:BAAANQADCgUICAABNQAECgIIAgACAAAAAA==.',
Ni='Niavarr:BAAANQAECgYIBgAAAA==.Nightestrike:BAAANQAECgQIBgAAAA==.Ninali:BAAANQAECgQIBQAAAA==.Niuven:BAAANQAECggIBwAAAA==.Nivek:BAAANQADCgUICQAAAA==.',
No='Noralai:BAAANQADCgUIBAAAAA==.Nore:BAAANQAECgIIBAAAAA==.',
Nt='Ntviss:BAAANQADCgYIBgAAAA==.',
Ny='Nyali:BAAANQADCgQIBAABNQAECgUICgACAAAAAA==.',
['Nà']='Nàdya:BAABNQAECoEaAAIIAAgKfxnHMABbAgAIAAgKfxnHMABbAgAAAA==.',
['Nî']='Nîghtshade:BAAANQADCgIIAgAAAA==.',
Ob='Obidin:BAAANQADCgYIBgABNQAECgMIBQACAAAAAA==.Oblivions:BAABNQAECoEZAAIYAAgKsB+TNAC8AgAYAAgKsB+TNAC8AgAAAA==.',
Od='Odasa:BAAANQAECgUICgAAAA==.',
Og='Ogion:BAAANQADCggICAAAAA==.',
Ol='Olahn:BAAANQAECgIIAgAAAA==.',
On='Onekark:BAABNQAECoEXAAIIAAgKJhXqQwAEAgAIAAgKJhXqQwAEAgAAAA==.Onlysins:BAAANQADCggJGwAAAA==.',
Or='Orckus:BAAANQAECgEIAQAAAA==.Oreosbunny:BAAANQAECgUIDwAAAA==.Orìhimè:BAAANQABCgQIBAAAAA==.',
Pa='Padma:BAAANQADCgUIBAAAAA==.Pandaburn:BAAANQAECgUICQAAAA==.Pandalock:BAAANQADCgYIBgAAAA==.Pandsome:BAAANQADCgYICwAAAA==.Paroxism:BAABNQAECoEiAAIaAAkKwSBeEwAHAwAaAAkKwSBeEwAHAwAAAA==.Parzival:BAAANQAECgMIAwAAAA==.Pawsome:BAAANQADCgYIBgAAAA==.',
Pe='Peanût:BAAANQAECgUIDQAAAA==.Peautiful:BAAANQAECgIIAgAAAA==.',
Ph='Phaket:BAABNQAECoEeAAIHAAgKlh+bLACpAgAHAAgKlh+bLACpAgAAAA==.',
Pi='Picaduro:BAAANQADCgYICQAAAA==.Picture:BAAANQADCgcIEgABNQAECgkJIAAIAPIdAA==.Pika:BAAANQAECgUICwAAAA==.Pippá:BAAANQADCggIDwAAAA==.',
Po='Pockethealer:BAAANQAECgEIAQAAAA==.Polonius:BAAANQAECgUICAAAAA==.Potato:BAAANQADCgIIAgAAAA==.',
Pr='Probation:BAAANQADCgUICAAAAA==.',
Pu='Puchideperro:BAAANQAECgEIAgAAAA==.Pujo:BAAANQABCgUIBQAAAA==.',
Pw='Pwil:BAAANQABCgMIAgABNQADCgYIBgACAAAAAA==.',
Py='Pythe:BAAANQAECgYIEwAAAA==.',
Qa='Qap:BAAANQAECgIIAwAAAA==.',
Qi='Qingu:BAAANQAECgcIEgAAAA==.',
Qu='Qualnorr:BAAANQAECgIIAgAAAA==.Queldraayan:BAAANQAECgIJBAAAAA==.Quinnter:BAEANQAECgQIBQAAAA==.Quixxie:BAEANQADCggICAABNQAECgQIBQACAAAAAA==.',
Qw='Qwil:BAAANQABCgYICgABNQADCgYIBgACAAAAAA==.',
Ra='Radagon:BAABNQAECoEdAAMLAAgKIQw4XAC4AQALAAgKIQw4XAC4AQAMAAcK4RJ8kACZAQABNQAECgcIFwACAAAAAA==.Radalas:BAAANQAECgUICwAAAA==.Radreliris:BAAANQAECgMIAwAAAA==.Raelithi:BAAANQABCgMJAQAAAA==.Rally:BAAANQAECgQIBQAAAA==.Ramcco:BAEANQAECgUICwAAAA==.Ranelle:BAAANQAECgYIEwAAAA==.Rasmira:BAAANQAECgEIAQAAAA==.Ravenis:BAABNQAECoEeAAIdAAkKuCEfAwBnAwAdAAkKuCEfAwBnAwAAAA==.',
Re='Rebekkah:BAAANQADCgQIBAAAAA==.Reedem:BAAANQAECgIIAwAAAA==.Regilock:BAACNQAFFIEVAAQPAAcKkiCAAAClAgAPAAcKkiCAAAClAgAQAAIKqhLECgCnAAAVAAEKjhMTCQBNAAA1AAQKgWIABA8ACQrbJtIDAKADAA8ACArbJtIDAKADABAABAplJXoYAJsBABUAAgo7IOwTALwAAAAA.Reikí:BAAANQAECgQIBAABNQAECggIHgAJAL4cAA==.Reservoir:BAAANQADCgIIAgAAAA==.Revgard:BAAANQAECgQIBAAAAA==.',
Rh='Rhaenyrra:BAABNQAECoEWAAIeAAcK3wV1EwAuAQAeAAcK3wV1EwAuAQAAAA==.Rhaily:BAAANQADCgIIAgAAAA==.Rhallin:BAAANQADCggIDQAAAA==.',
Ro='Ronso:BAAANQADCgQJBAAAAA==.Rosiel:BAAANQABCgQIBAAAAA==.Rowain:BAAANQAECgYIEwAAAA==.',
Ry='Rylacus:BAAANQAECgQIBwAAAA==.Rylii:BAAANQAECgIIBAAAAA==.',
Sa='Saanda:BAAANQADCggIEAAAAA==.Safael:BAAANQADCggICAAAAA==.Salandre:BAAANQADCggIEAAAAA==.Saloman:BAAANQABCggICQABNQAECggIFwADANocAA==.Sarlef:BAAANQAECgUICgAAAA==.',
Sc='Scarm:BAAANQAECgYICwAAAA==.Scathed:BAAANQAECggIDAAAAA==.Scorpix:BAAANQADCgcIFQAAAA==.',
Se='Seaflower:BAAANQAECgEIAQAAAA==.Seig:BAAANQADCgQIBAAAAA==.Sellidra:BAAANQAECgUICwAAAA==.Serenitara:BAAANQADCggIEwAAAA==.Serifanlord:BAAANQAECgEJAgAAAA==.Seyana:BAAANQAECgQIBAAAAA==.',
Sh='Shaaddow:BAAANQAECgEIAwAAAA==.Shaffer:BAAANQAECgYIDAAAAA==.Shamanlady:BAAANQADCgUIBwAAAA==.Shamwhoa:BAAANQABCgQIBwAAAA==.Shellshocker:BAABNQAECoEaAAIJAAkK9yWjAgDTAwAJAAkK9yWjAgDTAwAAAA==.Sheng:BAAANQADCgUJBQAAAA==.Shermantånk:BAAANQADCgYICAAAAA==.Shey:BAAANQADCgQIBAAAAA==.Sheydon:BAAANQADCggICgAAAA==.Shikigamï:BAAANQAECgEJAQABNQAECgYIEAACAAAAAA==.Shikï:BAAANQAECgYIEAAAAA==.Shivermoón:BAABNQAECoEcAAIfAAgK4AmlJgCIAQAfAAgK4AmlJgCIAQAAAA==.',
Si='Siegbane:BAAANQAECgMIAwAAAA==.Sigesar:BAAANQADCggIIwAAAA==.Sigrún:BAAANQAECgQIBQAAAA==.Simpforsouls:BAAANQADCgMIAwAAAA==.Sinsimella:BAAANQABCgYIBgAAAA==.',
Sk='Skullash:BAAANQADCgcIBwAAAA==.Skywatcher:BAAANQAECgQICgAAAA==.',
Sl='Slaughtering:BAAANQADCgIIAgAAAA==.',
Sm='Smitemare:BAAANQADCggIDwABNQAECgEIAQACAAAAAA==.',
Sn='Sneakmode:BAAANQADCggIEwAAAA==.Snicky:BAAANQAECgEJAQAAAA==.',
So='Solare:BAAANQAECggIAgAAAA==.Sonwarr:BAABNQAECoEcAAIDAAgKlBkNMABmAgADAAgKlBkNMABmAgAAAA==.',
Sp='Spliphtoker:BAAANQAECgEIAQAAAA==.',
St='Stabsolutely:BAAANQADCgUJBQABNQAECgEIAQACAAAAAA==.Steelpen:BAAANQAECgMIBQAAAA==.Stenston:BAAANQAECgMIBQAAAA==.Sterede:BAAANQADCggIHQAAAA==.Stitchwhich:BAAANQAECgMJAwAAAA==.Stonehenge:BAAANQAECgUICwAAAA==.Stormwolves:BAAANQADCgYICQAAAA==.',
Su='Summers:BAAANQAECggIDQAAAA==.Surfclub:BAAANQAECgQIBAAAAA==.',
Sy='Sylphr:BAAANQAECgEIAQABNQAFFAEIAQACAAAAAA==.Sylphwild:BAAANQAECgQICAABNQAFFAEIAQACAAAAAA==.Sylvara:BAAANQAECgQIBgAAAA==.Synkinz:BAAANQAECgQICgAAAA==.Syntec:BAAANQABCgIIAgAAAA==.Syreite:BAAANQAECgUICQAAAA==.',
Ta='Tacori:BAAANQAECgMIBAAAAA==.Taessa:BAAANQADCgcICgAAAA==.Tainipuni:BAAANQADCgYIBgAAAA==.Tallic:BAABNQAECoEbAAIcAAgK1RnREABDAgAcAAgK1RnREABDAgAAAA==.Talynayl:BAAANQADCgUIBwAAAA==.Tamarah:BAAANQAECgEIAQAAAA==.Tandemonium:BAAANQAECgUIBgABNQAECgkJKAAgAH8kAA==.Taniz:BAAANQAECgcIEQAAAA==.Tarsi:BAAANQAECgUIBwAAAA==.Taseg:BAAANQABCggICgAAAA==.',
Td='Td:BAABNQAFFIENAAIJAAUKEhWyBgCsAQAJAAUKEhWyBgCsAQABNQAFFAkJHgAhAHYlAA==.',
Te='Tearinurside:BAAANQAECgQIBQAAAA==.Telidrel:BAAANQADCgIIAwAAAA==.',
Tg='Tgi:BAAANQAECgMIBAAAAA==.',
Th='Thaddeaus:BAABNQAECoEdAAIFAAgKSxPLDgDkAQAFAAgKSxPLDgDkAQAAAA==.Thaddeus:BAAANQAECgIIBAAAAA==.Thealin:BAAANQAECgMIAwAAAA==.Thebeefyone:BAAANQAECgMICAAAAA==.Thecanadian:BAAANQADCgQIBAAAAA==.Thegreatmel:BAAANQADCgIIAgAAAA==.Therizin:BAAANQAECgQIBAAAAA==.Thesummoner:BAAANQAECgEIAQAAAA==.Thornel:BAAANQADCgEIAQAAAA==.Thorrek:BAAANQAECggIEQAAAA==.Thumpette:BAAANQAECgIIBwAAAA==.',
Ti='Tierant:BAAANQADCggIFQAAAA==.Tinaris:BAAANQADCgUICQABNQAECgUICwACAAAAAA==.Tizaria:BAAANQAECgMIBQAAAA==.',
Tm='Tmai:BAAANQAECgQIBQAAAA==.',
To='Tominaetor:BAAANQADCgcIJAAAAA==.Tookans:BAAANQABCgUIBQAAAA==.Tosoto:BAABNQAECoEaAAMFAAcKhRe4FAB9AQAYAAcKGxCokACWAQAFAAYKZhe4FAB9AQAAAA==.Toxica:BAAANQADCgMIAwAAAA==.',
Tr='Travcula:BAABNQAECoEZAAIRAAcKHhqdNAD4AQARAAcKHhqdNAD4AQAAAA==.Treefiddy:BAAANQADCgEIAgAAAA==.Trumpd:BAAANQADCgUIBQABNQAECgEIAQACAAAAAA==.',
Ts='Tso:BAAANQADCgEIAQAAAA==.',
Tt='Ttriton:BAAANQADCgEIAQAAAA==.',
Tu='Tuuwa:BAAANQADCgMIAwAAAA==.',
Ty='Tyernan:BAAANQAECgYIDgAAAA==.Tyrioz:BAAANQAECgUICwAAAA==.',
Tz='Tzavcat:BAAANQAECgUICAAAAA==.',
Uh='Uhtred:BAAANQAECggIAgAAAA==.',
Un='Unknownmage:BAAANQABCgIIAgAAAA==.',
Ur='Urbi:BAAANQAECgQICgAAAA==.',
Uv='Uvsol:BAAANQADCgQIBAAAAA==.',
Va='Vadailla:BAAANQAECgUIDAAAAA==.Vahrik:BAAANQADCgMIAwAAAA==.Valeirra:BAAANQADCgMIBQAAAA==.Valius:BAAANQAECgUICgAAAA==.Valkyrae:BAAANQADCgQIBAAAAA==.Valornor:BAAANQAECgIJAgAAAA==.Vandill:BAABNQAECoEgAAIGAAgKNBUdhwAzAgAGAAgKNBUdhwAzAgAAAA==.Varyanwrynn:BAAANQADCgMIAwAAAA==.Vaxis:BAAANQADCgcIEwAAAA==.',
Ve='Veasnacool:BAAANQAECgQIEAAAAA==.Vestrit:BAAANQADCgIIAgABNQAECggIHgAJAL4cAA==.',
Vo='Vontote:BAAANQAECgUICgAAAA==.Vorix:BAAANQADCgcIBwAAAA==.',
['Ví']='Víc:BAAANQAECgQICgAAAA==.',
Wa='Wandorf:BAEANQAECgIIBAAAAA==.Warwolfe:BAAANQAECgYIEwAAAA==.Wayler:BAAANQADCggICAAAAA==.',
Wh='Whitewâlker:BAAANQABCgUIBQAAAA==.Whumpus:BAAANQADCgIIAgAAAA==.Whyn:BAAANQADCgUIBQAAAA==.',
Wi='Willei:BAAANQADCgUICwAAAA==.',
Wo='Wolferunner:BAAANQAECgMIBAAAAA==.Wondermang:BAAANQAECgMIAwAAAA==.Worgenwebb:BAAANQAECgQIBAABNQAECgkJHQAYAJMfAA==.',
Xa='Xaiden:BAAANQADCgcJBwAAAA==.Xaldora:BAAANQADCgEIAQAAAA==.Xali:BAAANQAECgIIAgAAAA==.Xanthrens:BAAANQADCgQIBgAAAA==.',
Xd='Xdxvuu:BAAANQAECgUIDAAAAA==.',
Xe='Xerimok:BAAANQAECgQIBwAAAA==.',
Xi='Xinya:BAAANQAECgMIBgAAAA==.',
Xs='Xsavior:BAAANQAECgUIBQAAAA==.Xshando:BAAANQAECgIIAgAAAA==.Xsmkmonk:BAAANQADCgUIBQAAAA==.',
Xz='Xzephyr:BAAANQAECgYIDgAAAA==.',
Ya='Yamato:BAAANQAECgYIBgAAAA==.',
Ye='Yesmín:BAAANQAECgcIDgAAAA==.',
Yi='Yil:BAAANQAECgYIDgAAAA==.',
Yo='Youwas:BAAANQAECgMIAQAAAA==.',
Ys='Yshtola:BAAANQADCgYICwAAAA==.',
Yu='Yukmouf:BAAANQAECggIDAAAAA==.Yuriika:BAAANQADCgYIBwAAAA==.Yuukmouf:BAAANQAECgQICgABNQAECggIDAACAAAAAA==.',
Za='Zakaris:BAAANQAECgUICwAAAA==.Zaladin:BAAANQADCgUIBQAAAA==.Zarrove:BAABNQAECoEaAAIWAAgK7xlOFQBbAgAWAAgK7xlOFQBbAgAAAA==.Zawl:BAAANQAECgMIBQAAAA==.',
Ze='Zea:BAAANQADCgMIAwAAAA==.Zeltri:BAABNQAECoEtAAIZAAgK3gagKwB3AQAZAAgK3gagKwB3AQAAAA==.Zerg:BAAANQAECgUICAAAAA==.',
Zh='Zhatva:BAABNQAECoEnAAMHAAkKOyGFEgAtAwAHAAkKOyGFEgAtAwAhAAMKLBIJRgDFAAAAAA==.Zhöe:BAAANQAECgUIBgAAAA==.',
Zi='Zimzhealz:BAAANQADCgcIDQAAAA==.Zimzorzz:BAAANQADCgUIBwABNQADCgcIDQACAAAAAA==.',
Zo='Zoelera:BAAANQAECgMIAwAAAA==.Zoldor:BAAANQAECgQICgAAAA==.Zoleia:BAAANQADCgMIAwAAAA==.Zorellion:BAAANQAECgUIDAAAAA==.',
Zu='Zuay:BAAANQADCgIIAgABNQAECgQICgACAAAAAA==.Zulianguy:BAABNQAECoEfAAMcAAkK8CAwDwBdAgAcAAYKbyMwDwBdAgAMAAQKZh1wsgBGAQAAAA==.',
Zy='Zycorr:BAAANQAECgEIAgAAAA==.Zytrex:BAAANQAECgQIBAAAAA==.',
['Zá']='Zátsu:BAAANQABCgEIAQAAAA==.',
['Äm']='Ämaterasu:BAAANQADCgYICAABNQAECgYIEAACAAAAAA==.',
['Ñÿ']='Ñÿx:BAAANQAECgUICQAAAA==.',
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
