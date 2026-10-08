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

local lookup = {'DeathKnight-Frost','Unknown-Unknown','Priest-Holy','Priest-Discipline','Warrior-Protection','Mage-Arcane','Hunter-BeastMastery','Shaman-Restoration','Shaman-Elemental','DeathKnight-Blood','Hunter-Survival','Monk-Windwalker','Paladin-Holy','Paladin-Retribution','Warlock-Demonology','DemonHunter-Devourer','DemonHunter-Vengeance','Warlock-Destruction','DeathKnight-Unholy','Druid-Guardian','Rogue-Assassination','Warlock-Affliction','Mage-Frost','Evoker-Augmentation','Priest-Shadow','Shaman-Enhancement','Warrior-Arms','Druid-Balance','Monk-Brewmaster','Paladin-Protection','Evoker-Devastation','Rogue-Subtlety','Evoker-Preservation','Druid-Feral','Druid-Restoration','DemonHunter-Havoc','Hunter-Marksmanship',}
local provider = {region='US',realm='ArgentDawn',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abajaba:BAAANQAECgQIBAAAAA==.Abractus:BAAANQAECgUIEAAAAA==.',
Ad='Aderrig:BAAANQADCgQIBAAAAA==.Adohlin:BAAANQABCgQIBgAAAA==.Adriana:BAAANQAECgYIEAAAAA==.Adrianix:BAAANQAECgIICAAAAA==.Adru:BAAANQAECgYIDQAAAA==.',
Ae='Aeglos:BAACNQAFFIEFAAIBAAMKfAhjDADMAAABAAMKfAhjDADMAAA1AAQKgSMAAgEACQpiIPkSANYCAAEACQpiIPkSANYCAAAA.Aehrick:BAAANQAECgQIBwAAAA==.Aentharion:BAAANQAECgQICAAAAA==.Aeyn:BAAANQABCggIGAAAAA==.',
Af='Afflixen:BAAANQAECgMIAwABNQAECgUIBgACAAAAAA==.',
Ai='Aileen:BAAANQAECgYIEQAAAA==.Aimshot:BAAANQAECgQIBAAAAA==.',
Al='Alakaz:BAAANQAECgEIAQAAAA==.Aldehyde:BAAANQADCgYIBwAAAA==.Alidoro:BAAANQADCgEIAQAAAA==.Alisonia:BAAANQADCgMIBQAAAA==.Alitikar:BAAANQADCgQIBAAAAA==.Alleximage:BAAANQAECgIIAQAAAA==.Alliancepaly:BAAANQADCgMIAwAAAA==.Alorren:BAAANQAECgYIEQAAAA==.Aludor:BAAANQADCgEIAQAAAA==.',
Am='Ammo:BAAANQAECgEIAQABNQAECggIHgADADweAA==.Amo:BAAANQABCggIHgABNQAECggIHgADADweAA==.Amodegas:BAAANQAECgQIBAABNQAECggIHgADADweAA==.Amodillo:BAABNQAECoEeAAMDAAgKPB75LQCQAgADAAgKPB75LQCQAgAEAAMKARMSFQC+AAAAAA==.Amoe:BAAANQADCggICwABNQAECggIHgADADweAA==.Amonra:BAAANQADCgYICQAAAA==.Amynrar:BAAANQADCggIEAAAAA==.',
An='Andriia:BAAANQADCggIDwAAAA==.Angyaras:BAACNQAFFIENAAIFAAUKMSP5AADaAQAFAAUKMSP5AADaAQA1AAQKgSAAAgUACQpSJgYBAMIDAAUACQpSJgYBAMIDAAAA.Animos:BAAANQADCgMIAwAAAA==.',
Ap='Apiix:BAABNQAECoEhAAIGAAgKlhP+pQAVAgAGAAgKlhP+pQAVAgAAAA==.',
Ar='Araaras:BAAANQAFFAEIAQAAAA==.Araiguma:BAAANQAECgcIDQABNQAFFAcIIgAHALojAA==.Arcaisme:BAAANQAECgYICwAAAA==.Arcticsnow:BAAANQAECgUIDQAAAA==.Ariealla:BAAANQADCgUIBQAAAA==.Arkose:BAAANQAECgEIAQAAAA==.',
As='Aschen:BAAANQADCgIJAwAAAA==.Ashlyngrace:BAAANQAECgUICwABNQAECgkJLQAIAOofAA==.Ashlynne:BAABNQAECoEtAAMIAAkK6h/aDgA3AwAIAAkK6h/aDgA3AwAJAAEKAAIJNwEfAAAAAA==.Aslynna:BAAANQAECggICAAAAA==.Aspensong:BAAANQAECgQICAAAAA==.Astracious:BAAANQAECgMIAwAAAA==.Astrayice:BAAANQADCgQIBQAAAA==.',
At='Atarkormu:BAAANQAECgQICgABNQAECggIGQAKABETAA==.Atax:BAAANQAECgQICAAAAA==.Athená:BAAANQAECgQIBwAAAA==.Atulkan:BAAANQAECgQICwAAAA==.',
Au='Auralyn:BAAANQADCgYIDQAAAA==.Aurelitrasza:BAAANQADCgYJEwAAAA==.',
Av='Avalar:BAAANQADCgYIBgAAAA==.Avrice:BAAANQAECgUIBwAAAA==.Avris:BAAANQAECgEIAQAAAA==.',
Ay='Ayayaras:BAAANQAFFAMIBAABNQAFFAUIDQAFADEjAA==.Ayddayd:BAAANQADCgQICAAAAA==.Aylianya:BAAANQAECgUICQABNQAECgkJLQAIAOofAA==.',
Ba='Badshot:BAAANQADCgYIBgAAAA==.Bambu:BAAANQADCggIEwABNQAECgQICAACAAAAAA==.Bamdruid:BAAANQADCgIIAgABNQAECgQICAACAAAAAA==.Bamevoker:BAAANQAECgQICAAAAA==.Bariggs:BAABNQAECoEbAAILAAgKTiEkAwDIAgALAAgKTiEkAwDIAgAAAA==.Barilia:BAAANQADCgMIBAAAAA==.',
Be='Beals:BAAANQAECgQIBgAAAA==.Beladra:BAAANQADCgQIBQAAAA==.Ben:BAABNQAECoEZAAIMAAgKLx23FACLAgAMAAgKLx23FACLAgAAAA==.Beriadan:BAABNQAECoElAAIJAAgK0R/AIgDeAgAJAAgK0R/AIgDeAgAAAA==.Bevee:BAABNQAECoEjAAMNAAkKrR9rDQBPAwANAAkKrR9rDQBPAwAOAAEK+xCEfAEwAAAAAA==.',
Bi='Bigwheels:BAAANQADCgYIBAAAAA==.Bisque:BAAANQADCgUIBQAAAA==.Bitemare:BAAANQADCgIIAgABNQAECgQIBQACAAAAAA==.Bixii:BAAANQADCgYIBgAAAA==.',
Bl='Bleddwen:BAAANQAECgUIDAAAAQ==.Blindseer:BAAANQABCgIIAgAAAA==.Bloodjustice:BAAANQAECgQIBAAAAA==.Blrsama:BAAANQAECgIIAwAAAA==.',
Bo='Bohrnir:BAAANQADCgUIBQAAAA==.Boozelee:BAAANQADCgMIAwAAAA==.Bozo:BAAANQAECgUIBwAAAA==.Boüh:BAAANQAECgYIEQAAAA==.',
Br='Brutalix:BAAANQADCgEIAQAAAA==.',
Bu='Bubblesonyou:BAAANQAECgYIEgAAAA==.Burnadine:BAAANQAECgQIBwAAAA==.Burnswhnpee:BAABNQAECoEZAAIPAAgKHRGIZwD/AQAPAAgKHRGIZwD/AQAAAA==.',
Ca='Caliie:BAAANQAECgQICAAAAA==.Callektra:BAAANQADCggICwAAAA==.Callira:BAAANQADCgYIBgAAAA==.Calzypher:BAAANQADCgEIAQAAAA==.Captclamslam:BAAANQAECgIIAgAAAA==.Carhop:BAAANQADCgIIAgAAAA==.Caverick:BAAANQADCggICAAAAA==.Caw:BAAANQADCgMIAwABNQAECgIIAgACAAAAAA==.Cayuga:BAAANQADCgUICAAAAA==.',
Ch='Charå:BAAANQADCgUIBQAAAA==.Chintakari:BAAANQAECgYIDwAAAA==.',
Co='Cocidiae:BAAANQADCgYICgAAAA==.Confusious:BAABNQAECoEiAAIIAAkK8h1hGAD3AgAIAAkK8h1hGAD3AgAAAA==.Coppers:BAAANQADCggIBAAAAA==.Coree:BAAANQAECgQIDgAAAA==.Cornflower:BAAANQAECgYIBgABNQAECgcIHAAHAAwTAA==.Corvaan:BAABNQAECoEXAAIQAAkKLhA3JAAFAgAQAAkKLhA3JAAFAgAAAA==.Corvhuunta:BAAANQAFFAIIAgAAAA==.',
Cr='Creg:BAAANQADCggIIgABNQAECgQIBAACAAAAAA==.Crowbarr:BAAANQADCgYICwAAAA==.Cryostatic:BAAANQAECgMIBQABNQAECgQICAACAAAAAA==.',
Cu='Cultel:BAABNQAECoEiAAIRAAgKsRatCQAaAgARAAgKsRatCQAaAgAAAA==.Cuulon:BAAANQADCgQIBgAAAA==.',
Cy='Cyendia:BAAANQAECgYIDwAAAA==.Cynlea:BAAANQADCgYJCgAAAA==.',
Da='Daddyraz:BAAANQAECgUIDQAAAA==.Daemonquiver:BAAANQAECgUIBwAAAA==.Dahtotems:BAABNQAECoEcAAIJAAkKWyNHBwCkAwAJAAkKWyNHBwCkAwAAAA==.Daphcelyn:BAAANQAECgEIAQAAAA==.Dariusz:BAAANQAECgYIEAAAAA==.Darkalen:BAABNQAECoEZAAIKAAgKERN2QADdAQAKAAgKERN2QADdAQAAAA==.Darkfogg:BAAANQAECggIAQAAAA==.Darklodus:BAAANQADCgYICwAAAA==.Darksethia:BAAANQADCgQIBAAAAA==.Darksoul:BAAANQADCgQIBAAAAA==.Dathea:BAACNQAFFIEVAAIIAAYKzxytAwAsAgAIAAYKzxytAwAsAgA1AAQKgTQAAggACQpTIi4OADsDAAgACQpTIi4OADsDAAAA.Daxetanlock:BAABNQAECoEsAAMPAAkKZCO6GAAQAwAPAAgKEyO6GAAQAwASAAQKURvDKQAhAQAAAA==.Daxetans:BAAANQAECgIIAgABNQAECgkJLAAPAGQjAA==.',
De='Deathjingle:BAABNQAECoEnAAMTAAkKLhwyLABhAgATAAkKzBoyLABhAgAKAAYKpRwGQQDaAQAAAA==.Deecayed:BAAANQAECgEIAQABNQAECgkJKgAIAHcgAA==.Deecoy:BAAANQAECgQICAABNQAECgkJKgAIAHcgAA==.Deemonic:BAAANQAECgIIAgABNQAECgkJKgAIAHcgAA==.Deerslayer:BAAANQABCgIIAgAAAA==.Deetermined:BAABNQAECoEqAAIIAAkKdyDgEQAhAwAIAAkKdyDgEQAhAwAAAA==.Deloisela:BAABNQAECoEcAAIGAAgKvAyp0QC9AQAGAAgKvAyp0QC9AQAAAA==.Denalii:BAAANQADCggICAAAAA==.Denchy:BAAANQAECgUIDwAAAA==.Deylen:BAAANQAECgYIEgAAAA==.Deyndine:BAAANQAECgUIEAAAAA==.',
Di='Dizzyglaive:BAAANQADCgYIDQAAAA==.',
Dl='Dlkffjj:BAAANQAECgEJAgAAAA==.',
Dm='Dmdk:BAAANQAFFAIIBAAAAA==.Dmrwr:BAAANQAFFAIIBAAAAA==.',
Do='Dodson:BAAANQADCgEIAQAAAA==.Dorilax:BAAANQAECgIIAgABNQAECgYIDQACAAAAAA==.Dottarus:BAAANQADCgUIBQABNQAECgUIBwACAAAAAA==.',
Dr='Draegloth:BAAANQAECggIAgAAAA==.Draelick:BAAANQABCgIIAgAAAA==.Driadora:BAAANQAECgYIDQAAAA==.Droataxm:BAABNQAECoEuAAIGAAkKLCB3NwAMAwAGAAkKLCB3NwAMAwAAAA==.Droataxpr:BAAANQAECgYIBgABNQAECgkJLgAGACwgAA==.Drogath:BAAANQADCgcIDQAAAA==.',
Du='Duarraag:BAAANQADCgYICQAAAA==.',
['Dâ']='Dâvïd:BAABNQAECoElAAIUAAgK8BnbDQBIAgAUAAgK8BnbDQBIAgAAAA==.',
['Dä']='Däß:BAAANQADCgEJAQAAAA==.',
['Dë']='Dëërez:BAAANQAECgYIEQABNQAECgkJKgAIAHcgAA==.',
Ei='Eililis:BAAANQADCgYIBwAAAA==.',
El='Elani:BAAANQAECgcIDwAAAA==.Elaynaa:BAAANQAECgUIDAAAAA==.Elishaunt:BAAANQAECgQIBwABNQABCggICQACAAAAAA==.Elleizah:BAAANQAECggICQABNQAECgkJLQAVADAhAA==.Elleth:BAAANQAECgYICwAAAA==.Elliana:BAAANQAECgYIEwABNQAECgcIFwANAK0gAA==.Elogio:BAAANQADCgYIEAAAAA==.Elvoidra:BAAANQADCgUICQAAAA==.',
Em='Emanymton:BAAANQAECgIIAwAAAA==.Emiley:BAAANQAECgMIAwAAAA==.',
En='Envymeh:BAAANQADCgcIEgAAAA==.',
Er='Erinn:BAAANQADCgYIBgAAAA==.Erisaria:BAAANQADCggICgAAAA==.Erixi:BAAANQAECgUIDAAAAA==.Eryn:BAAANQADCgEIAQAAAA==.',
Es='Esaria:BAAANQADCgEIAQAAAA==.',
Ev='Evissier:BAABNQAECoEgAAIWAAkKOCEUAQBQAwAWAAkKOCEUAQBQAwAAAA==.',
Ex='Excelimagust:BAAANQAECgQIBQAAAA==.',
Fa='Faelada:BAAANQADCggIEgAAAA==.Faid:BAAANQAECgUIBgAAAA==.Failor:BAAANQADCgYIBgAAAA==.Faize:BAAANQADCgEIAQAAAA==.Falcdhruid:BAAANQAECgEIAQAAAA==.Farundi:BAAANQAECgEIAQAAAA==.',
Fe='Felbutton:BAAANQAECgYICgAAAA==.Felsen:BAAANQAECgQIBAABNQAECggIHgAFAMgbAA==.Felwit:BAABNQAECoEeAAIFAAgKyBs5CgB2AgAFAAgKyBs5CgB2AgAAAA==.Fennec:BAAANQAECgYIDAAAAA==.Feralie:BAAANQADCgYIBgAAAA==.Ferroz:BAAANQAECgQIDAABNQAECggIGQAKABETAA==.Ferrozious:BAAANQAECgQIBAABNQAECggIGQAKABETAA==.',
Fl='Flamos:BAAANQAECgQIBAAAAA==.Flatline:BAAANQAECgQICQAAAA==.Florabelle:BAABNQAECoEcAAIHAAcKDBNEfADmAQAHAAcKDBNEfADmAQAAAA==.Florid:BAAANQADCggIHAAAAA==.',
Fo='Foshomomo:BAAANQAECgQICAAAAA==.Fozzle:BAABNQAECoEdAAIXAAcKXhYRCwDeAQAXAAcKXhYRCwDeAQAAAA==.',
Fr='Frenndi:BAAANQAECgEIAQAAAA==.',
Fu='Fuknazuga:BAAANQAECgQIBwAAAA==.Furroz:BAAANQAECgQIBAABNQAECggIGQAKABETAA==.',
Fy='Fynedge:BAABNQAECoEZAAIOAAcKHgbh3QAlAQAOAAcKHgbh3QAlAQAAAA==.Fynnyntyss:BAABNQAECoEcAAIYAAcK2g2UDABhAQAYAAcK2g2UDABhAQAAAA==.Fyrè:BAABNQAECoEeAAIHAAcKwRymUwBNAgAHAAcKwRymUwBNAgAAAA==.',
Ga='Garthe:BAAANQADCgEIAQAAAA==.',
Ge='Geoma:BAAANQADCgYIBwAAAA==.Gerlock:BAAANQAECgUIBQAAAA==.',
Gh='Ghastrider:BAAANQABCgEIAQAAAA==.Ghostlyt:BAAANQABCgEJAQAAAA==.',
Gi='Gigatin:BAAANQAECgYIEQAAAA==.Githnor:BAABNQAECoEeAAIOAAcKcAijyABRAQAOAAcKcAijyABRAQAAAA==.',
Go='Goldal:BAAANQAECgQIBAAAAA==.Gorellan:BAAANQADCgYIDgAAAA==.',
Gr='Grimwharf:BAAANQAECgEIAQAAAA==.Grum:BAAANQADCgQIBgAAAA==.Grunaelyn:BAAANQAECgYIDAAAAA==.',
Gu='Guerrier:BAAANQAECgcIEwAAAA==.Guiong:BAAANQADCgYICgAAAA==.',
Gy='Gynx:BAAANQAECgEIAQAAAA==.',
['Gö']='Göttlich:BAAANQADCgUIBQABNQADCgUIBwACAAAAAA==.',
Ha='Haidas:BAAANQAECgYIBgAAAA==.Hardcheese:BAAANQADCgQIBAAAAA==.Hasuna:BAAANQADCgQIBAAAAA==.',
He='Heikuro:BAAANQAECgUIDgAAAA==.Heybestie:BAAANQADCggICAAAAA==.',
Hi='Hillo:BAAANQAECgEIAQAAAA==.',
Ho='Holychonks:BAAANQADCgcIEAAAAA==.Hommy:BAAANQADCggIDgAAAA==.Honadain:BAAANQAECgIIAgAAAA==.Honornight:BAAANQADCggJDgAAAA==.Hordestalker:BAAANQADCgUIBQAAAA==.Houtu:BAABNQAECoEhAAIIAAgKbBI1XQDIAQAIAAgKbBI1XQDIAQAAAA==.',
Hw='Hweilan:BAAANQADCgYIDAAAAA==.Hwil:BAAANQADCgYIBgAAAA==.',
Hy='Hydrokill:BAAANQADCggICAAAAA==.Hypnos:BAAANQAECgQIBQAAAA==.',
['Hö']='Hölyföx:BAAANQAECgEIAQAAAA==.',
Ia='Iamearl:BAAANQAECgUIDAAAAA==.',
In='Incidental:BAABNQAECoEtAAIMAAkKKiIyCAA5AwAMAAkKKiIyCAA5AwAAAA==.Inconell:BAAANQAECgQICgAAAA==.Invega:BAAANQAECgIJAwAAAA==.',
Ir='Iric:BAAANQADCgQIBgAAAA==.Irino:BAAANQADCgUIBQAAAA==.',
Is='Isabelle:BAAANQAECgQICwAAAA==.',
It='Itsredbush:BAAANQABCgEIAQAAAA==.',
Iz='Izaer:BAAANQAECgMICgAAAA==.Iziel:BAAANQAECgYICwAAAA==.Izumex:BAAANQAECgMIAwAAAA==.',
Ja='Jabzaklok:BAAANQAECgQIBAAAAA==.Jacky:BAAANQAFFAEIAQABNQAFFAUICAAZAKATAA==.Jahirah:BAAANQAECgYIEQABNQAECgcIGwATAFUMAA==.Jaida:BAAANQAECgQIDAAAAA==.Jaleika:BAAANQAECgYIEwAAAA==.Jarius:BAAANQAECgQICAAAAA==.Jayabalard:BAAANQAECgIIAgABNQAECggIGQAKABETAA==.',
Je='Jean:BAABNQAECoEqAAIHAAgK9SEBGwATAwAHAAgK9SEBGwATAwAAAA==.Jeez:BAAANQAECgcIEQAAAA==.Jesmaríe:BAAANQAECgQIBwAAAA==.',
Jo='Johadd:BAAANQADCgEIAQAAAA==.Jonyy:BAAANQADCgYICgAAAA==.Jorianna:BAAANQAECgQICAAAAA==.Joru:BAACNQAFFIEcAAIaAAcKLBk7AACxAgAaAAcKLBk7AACxAgA1AAQKgTIAAhoACQpmJvwAAMIDABoACQpmJvwAAMIDAAAA.',
Ju='Jurauth:BAAANQABCgQIBAAAAA==.Justyna:BAAANQAECgYICwAAAA==.Juze:BAAANQAECgQICQABNQAECgMIAQACAAAAAQ==.',
Ka='Kaai:BAAANQAECgYICgAAAA==.Kabaul:BAABNQAECoEuAAIbAAkKgSSJDACOAwAbAAkKgSSJDACOAwAAAA==.Kabir:BAAANQAECgUIDwAAAA==.Kadria:BAAANQAECgUIDAAAAA==.Kailanii:BAAANQAECgIIAgABNQAECgUICgACAAAAAA==.Kalagon:BAAANQADCgEIAQAAAA==.Kalaman:BAAANQADCgQICAAAAA==.Kalito:BAAANQADCgMIAwAAAA==.Kallivar:BAAANQAECgQICgABNQAECgkJLwAKAEgjAA==.Kamb:BAAANQAECgQICAAAAA==.Karalee:BAAANQAECgQICAAAAA==.Katieey:BAACNQAFFIEcAAIIAAcK7iMyAQCoAgAIAAcK7iMyAQCoAgA1AAQKgSQAAggACQrzJvMBAL0DAAgACQrzJvMBAL0DAAAA.Kaybee:BAAANQAECgQIBQAAAA==.Kayde:BAAANQADCgYIBgAAAA==.Kayil:BAABNQAECoEiAAIZAAgKlBTMHgAhAgAZAAgKlBTMHgAhAgAAAA==.',
Ke='Kedalin:BAAANQAECgEIAQAAAA==.Kennyloggy:BAACNQAFFIERAAIcAAcK7BepAwBXAgAcAAcK7BepAwBXAgA1AAQKgS8AAhwACQohJXkEAK8DABwACQohJXkEAK8DAAAA.Kevris:BAAANQAECgQICQABNQAECgcIGwATAFUMAA==.Keydan:BAAANQAECgUIDAAAAA==.',
Kh='Khalunna:BAAANQADCgYIBgAAAA==.Khyn:BAAANQADCgIIAQABNQAECgIIAgACAAAAAA==.',
Ki='Kianni:BAAANQADCggIDwAAAA==.Kirafrayen:BAAANQAECgEJAQABNQAECgcICQACAAAAAA==.',
Kl='Klassy:BAABNQAECoEcAAILAAgKWg54BgAFAgALAAgKWg54BgAFAgAAAA==.',
Ko='Koppi:BAAANQAECgQIBQAAAA==.Korru:BAAANQAECgMIBgAAAA==.Kotie:BAAANQAECgUIBQAAAA==.',
Kr='Kramz:BAAANQADCgcIDQAAAA==.Kreoss:BAAANQADCgQIBAABNQAECggIJAAIAAgQAA==.Kronar:BAABNQAECoEdAAIHAAUKbwyGwgBJAQAHAAUKbwyGwgBJAQAAAA==.Krongar:BAAANQADCgQIBAAAAA==.Krumblo:BAEANQAECgUICwABNQAECgYIEgACAAAAAA==.Kryztof:BAAANQADCgYIBgAAAA==.',
Ku='Kuiraptor:BAAANQADCgcIDgAAAA==.Kumojo:BAAANQADCgEIAQAAAA==.Kunea:BAAANQADCgYIBgAAAA==.Kungfujace:BAAANQADCgYICwAAAA==.',
Ky='Kyrgune:BAAANQAECgMIBAAAAA==.',
['Kà']='Kàhlan:BAAANQADCgYIBgAAAA==.',
La='Laoftey:BAABNQAECoEcAAIIAAgKRCIIGgDuAgAIAAgKRCIIGgDuAgAAAA==.Larquin:BAABNQAECoEbAAMTAAcKVQw/YwBdAQATAAcKEgw/YwBdAQABAAUKuwZnZADGAAAAAA==.Lasmori:BAAANQAECgYIDgABNQAECgcIDwACAAAAAA==.Laurenorder:BAAANQAECgUICgAAAA==.Laxxbroo:BAAANQAECgMIAwAAAA==.',
Le='Leam:BAAANQAECgUIDAAAAA==.Leglock:BAAANQAECgYIEQAAAA==.Leiff:BAAANQADCggIDgAAAA==.Leprhicon:BAAANQAECgMIBAAAAA==.Lesbihonest:BAAANQAECgcICwAAAA==.',
Li='Liendria:BAABNQAECoEbAAIHAAcKzhaZbgAIAgAHAAcKzhaZbgAIAgAAAA==.Lifensoftpaw:BAACNQAFFIERAAIMAAYK4BLhBQCBAQAMAAYK4BLhBQCBAQA1AAQKgSsAAwwACQpXI0wNAOwCAAwACQpXI0wNAOwCAB0ABQo5IIUQAMABAAAA.Lightemup:BAAANQAECgMIBQAAAA==.Lightkeeper:BAAANQABCgQIAgAAAA==.Likkash:BAAANQAECgQIBAABNQAECggIGQAKABETAA==.Limildea:BAAANQADCgIIAgAAAA==.Linthabeela:BAAANQADCgEIAQAAAA==.Liquidchiken:BAAANQAECgQIBAAAAA==.Lishalthen:BAAANQADCggJFwAAAA==.Littletouch:BAAANQADCgIIAgAAAA==.Livicecia:BAAANQAECgYICwAAAA==.',
Lu='Lucciana:BAAANQAECgQIBgAAAA==.Lucielinna:BAAANQADCgUIBQABNQAECgQIBwACAAAAAA==.Luckiiem:BAABNQAECoEiAAIGAAgKmiAdSQDhAgAGAAgKmiAdSQDhAgAAAA==.Luisfriendsn:BAAANQAECgUIDQABNQAECgkJJwAGAGsYAA==.Lumbo:BAEANQAECgYIEgAAAA==.Lunare:BAAANQADCgUJBQAAAA==.Lunarkin:BAAANQAECgQIBQAAAA==.Luthane:BAAANQAECgUICwAAAA==.',
Ly='Lykinea:BAAANQADCgYIBgAAAA==.Lyono:BAAANQADCgYIBgABNQAECggIGQAKABETAA==.Lytebrite:BAABNQAECoEkAAINAAgKixPTTAAWAgANAAgKixPTTAAWAgAAAA==.',
['Lí']='Líu:BAAANQADCggICAAAAA==.',
['Lü']='Lümßo:BAEANQAECgQICAABNQAECgYIEgACAAAAAA==.',
Ma='Mainos:BAAANQADCgUIBwAAAA==.Maiyr:BAAANQAECgEJAQAAAA==.Makanai:BAAANQAECgYICwAAAA==.Makishi:BAAANQAECgUIDwAAAA==.Malakenjin:BAAANQABCgMIAgAAAA==.Malferious:BAAANQADCgIIAgAAAA==.Malfura:BAAANQAECgQICQAAAA==.Malário:BAAANQAECgYIDQAAAA==.Manamontana:BAAANQADCgYIEAABNQAECgQIBQACAAAAAA==.Mattedfurry:BAAANQAECgIIAgAAAA==.Maube:BAAANQAECgEIAQABNQAFFAIIBQAeANULAA==.Mazzarzul:BAAANQAECgMIAQABNQAECgkJMwALAIobAA==.',
Me='Meebles:BAABNQAECoEeAAIUAAcKng14IQBHAQAUAAcKng14IQBHAQAAAA==.Meiana:BAABNQAECoEbAAIfAAgKUBVsEQAfAgAfAAgKUBVsEQAfAgAAAA==.Melasmus:BAAANQADCgYIBgAAAA==.Mes:BAAANQAECgYICgAAAA==.',
Mi='Micklaa:BAAANQAECgUIDgAAAA==.Miebi:BAAANQADCgYICwABNQAECggILAAdAAMiAA==.Milkbunny:BAAANQADCgUICQAAAA==.Mingtai:BAAANQAECgUICwAAAA==.Misskaitlyn:BAAANQADCgcIBwAAAA==.Mixen:BAAANQADCgQIBAABNQAECgUIBgACAAAAAA==.',
Mo='Moirrah:BAAANQADCgYIBgABNQAECgEIAQACAAAAAA==.Moonriver:BAAANQAECgYIDwAAAA==.Moonsinde:BAAANQAECggIBwAAAA==.Moranta:BAAANQAECgUIDwAAAA==.Moressandra:BAAANQAECgQIAwAAAA==.Morfina:BAAANQAECgIIAQABNQAECgMIBQACAAAAAA==.Morgaes:BAAANQAECgQIBwAAAA==.Mortannon:BAAANQAECgYIEQAAAA==.Morîarty:BAAANQADCgIIAgAAAA==.Mozzare:BAAANQADCgYIBgABNQAECgcIHgAUAJ4NAA==.',
Mu='Mushy:BAAANQADCgEIAQAAAA==.',
My='Mydruid:BAAANQAECgUIBgABNQAECgkJLQAVADAhAA==.Mysticarc:BAAANQADCgYIBgAAAA==.Mysticmurv:BAABNQAECoEeAAIGAAgK1Aj41wCxAQAGAAgK1Aj41wCxAQAAAA==.Mystieren:BAAANQAECgQICAABNQAECgkJHAAWALEPAA==.Mywarlock:BAABNQAECoEtAAMVAAkKMCHHCAA0AwAVAAkKwSDHCAA0AwAgAAcKLxqnGgDwAQAAAA==.',
Na='Nalgotica:BAAANQAECgIIAgAAAA==.Nalynahwe:BAAANQADCggJGwAAAA==.Narima:BAAANQAECgUICwAAAA==.Nathronso:BAAANQADCgUIBQAAAA==.Nauticâ:BAAANQABCgYIDAAAAA==.Navirose:BAAANQADCggIDwAAAA==.',
Ne='Necromos:BAAANQADCggIBgAAAA==.Neltheron:BAAANQADCgMIAwAAAA==.',
Nh='Nhala:BAAANQADCgUICAABNQAECgUIBwACAAAAAA==.',
Ni='Niavarr:BAAANQAECgYIBgAAAA==.Nightestrike:BAAANQAECgQICgAAAA==.Ninali:BAAANQAECgYICwAAAA==.Nivek:BAAANQADCgUICQAAAA==.',
No='Noralai:BAAANQADCgUIBAAAAA==.Nore:BAAANQAECgIIBgAAAA==.',
Nt='Ntviss:BAAANQADCgYIBgAAAA==.',
Ny='Nyali:BAAANQAECgUIBQABNQAECgUICgACAAAAAA==.',
['Nà']='Nàdya:BAABNQAECoEoAAMIAAgKrBqQNQBjAgAIAAgKrBqQNQBjAgAJAAEKRg+PEQE3AAAAAA==.',
['Nî']='Nîghtshade:BAAANQADCgYIBwAAAA==.',
Ob='Obidin:BAAANQADCggICAABNQAECgQICQACAAAAAA==.Oblivions:BAABNQAECoEgAAIbAAgKsB+cPwCzAgAbAAgKsB+cPwCzAgAAAA==.',
Od='Odasa:BAAANQAECgUIDgAAAA==.',
Og='Ogion:BAAANQADCggICAAAAA==.',
Ol='Olahn:BAAANQAECgUIBwAAAA==.',
On='Onekark:BAABNQAECoEYAAIIAAgKMRZQRgAdAgAIAAgKMRZQRgAdAgABNQAFFAcIGAAIAPYXAA==.Onlysins:BAAANQADCggJGwAAAA==.',
Or='Orckus:BAAANQAECgMIAwAAAA==.Oreosbunny:BAABNQAECoEYAAIOAAcKFB+KYgBGAgAOAAcKFB+KYgBGAgAAAA==.Orìhimè:BAAANQABCgQIBAAAAA==.',
Pa='Padma:BAAANQADCgUIBAAAAA==.Pandaburn:BAAANQAECgYIDwAAAA==.Pandalock:BAAANQADCgYIBgAAAA==.Pandsome:BAAANQADCgYICwAAAA==.Paroxism:BAACNQAFFIEFAAIcAAIKPRaoGQCiAAAcAAIKPRaoGQCiAAA1AAQKgSQAAhwACQqyIdMVAAIDABwACQqyIdMVAAIDAAAA.Parzival:BAAANQAECgMIAwABNQAECgUIBgACAAAAAA==.Pawsome:BAAANQADCgYIBgAAAA==.',
Pe='Peanût:BAAANQAECgUIEQAAAA==.Peautiful:BAAANQAECgUIBgAAAA==.',
Ph='Phaket:BAABNQAECoEeAAIHAAgKlh+jPACQAgAHAAgKlh+jPACQAgAAAA==.',
Pi='Picaduro:BAAANQADCgYICQAAAA==.Picture:BAAANQADCgcIEgABNQAECgkJIgAIAPIdAA==.Pika:BAAANQAECgYIEQAAAA==.Pippá:BAAANQAECgIIAgAAAA==.',
Po='Pockethealer:BAAANQAECgEIAQAAAA==.Polonius:BAAANQAECgYIDAAAAA==.Potato:BAAANQADCgIIAgAAAA==.',
Pr='Priss:BAAANQADCgYIBgAAAA==.Probation:BAAANQADCgUICAAAAA==.',
Pu='Puchideperro:BAAANQAECgEIAgAAAA==.Pujo:BAAANQABCgcICQAAAA==.',
Pw='Pwil:BAAANQABCgMIAgABNQADCgYIBgACAAAAAA==.',
Py='Pythe:BAABNQAECoEeAAIOAAcKzyIfRQCgAgAOAAcKzyIfRQCgAgAAAA==.',
Qa='Qap:BAAANQAECgIIAwAAAA==.',
Qi='Qingu:BAABNQAECoEdAAQYAAgKvw3aCQCvAQAYAAgKsw3aCQCvAQAfAAcKQAexHwA9AQAhAAYK+wMDMwDcAAAAAA==.',
Qu='Qualnorr:BAAANQAECgMIBAAAAA==.Queldraayan:BAAANQAECgQICAAAAA==.Quinnter:BAEANQAECgQIBQAAAA==.Quixii:BAEANQABCgYIBgABNQAECgQIBQACAAAAAA==.Quixxie:BAEANQAECgQIBAABNQAECgQIBQACAAAAAA==.',
Qw='Qwil:BAAANQABCgYICgABNQADCgYIBgACAAAAAA==.',
Ra='Radagon:BAABNQAECoEeAAMNAAgK0gyoaQC0AQANAAgK0gyoaQC0AQAOAAcK4RKYrACOAQABNQAECgcIHgACAAAAAA==.Radalas:BAAANQAECgYIEQAAAA==.Radreliris:BAAANQAECgQIBwAAAA==.Raelithi:BAAANQABCgMJAQAAAA==.Rahdalas:BAAANQADCgEIAQABNQAECgYIEQACAAAAAA==.Rainfall:BAAANQADCgYIBgAAAA==.Rally:BAAANQAECgYICwAAAA==.Ramcco:BAEANQAECgYIEQAAAA==.Ranelle:BAABNQAECoEeAAIDAAcKlhm5UwD8AQADAAcKlhm5UwD8AQAAAA==.Rasmira:BAAANQAECgEIAgAAAA==.Ravenis:BAACNQAFFIEHAAIgAAMKNRB1CgD7AAAgAAMKNRB1CgD7AAA1AAQKgSEAAiAACQpwIl8DAGcDACAACQpwIl8DAGcDAAAA.',
Re='Reanette:BAAANQADCgQIBAABNQAECggIFgAOAE0dAA==.Rebekkah:BAAANQADCgQIBAAAAA==.Reedem:BAAANQAECgYICQAAAA==.Regilock:BAACNQAFFIEZAAQPAAcKkiDBAACnAgAPAAcKkiDBAACnAgASAAIKqhLjDACfAAAWAAEKjhN4CwBIAAA1AAQKgXYABA8ACQrqJvQEAKADAA8ACArtJvQEAKADABIABAplJb0ZAJYBABYAAgo7IIgWALsAAAAA.Reikí:BAAANQAECgQIBgABNQAECggIJQAJANEfAA==.Relarria:BAAANQAECgEIAQAAAA==.Renbe:BAAANQADCgEIAQAAAA==.Revgard:BAAANQAECgQICAAAAA==.',
Rh='Rhaenyrra:BAABNQAECoEYAAIXAAgK6AWuFAA7AQAXAAgK6AWuFAA7AQAAAA==.Rhaily:BAAANQADCgIIAgAAAA==.Rhallin:BAAANQAECgIIAgAAAA==.Rhasalgul:BAAANQAECgQIBAAAAA==.',
Ro='Ronso:BAAANQADCgQJBAAAAA==.Rosiel:BAAANQABCgQIBAAAAA==.Rowain:BAABNQAECoEeAAMiAAcK4wpnGgAiAQAiAAYKdAhnGgAiAQAjAAYKlwMoQwDcAAAAAA==.Rozemary:BAAANQADCggICAAAAA==.',
Ry='Rylacus:BAAANQAECgUIDAAAAA==.Rylii:BAAANQAECgIIBQAAAA==.',
Sa='Saanda:BAAANQADCggIEAAAAA==.Safael:BAAANQADCggICAAAAA==.Salandre:BAAANQADCggIFgAAAA==.Saloman:BAAANQABCggIDQABNQAECggIHgADADweAA==.Sarlef:BAAANQAECgYIEAAAAA==.',
Sc='Scarm:BAAANQAECggIEwAAAA==.Scathed:BAAANQAECggIDAAAAA==.Scorpix:BAAANQAECgIIAgAAAA==.',
Se='Seaflower:BAAANQAECgEIAQAAAA==.Seig:BAAANQADCgQIBAAAAA==.Sellidra:BAAANQAECgYIEQAAAA==.Serenitara:BAAANQADCggIEwAAAA==.Serifanlord:BAAANQAECgQIBgAAAA==.Seyana:BAAANQAECgUICQAAAA==.',
Sh='Shaaddow:BAAANQAECgEIBAAAAA==.Shaffer:BAAANQAECgYIDAAAAA==.Shamanlady:BAAANQAECgQIBAAAAA==.Shamwhoa:BAAANQABCgQIBwAAAA==.Shellshocker:BAABNQAECoEaAAIJAAkK9yVoBADBAwAJAAkK9yVoBADBAwAAAA==.Sheng:BAAANQADCgUJBQAAAA==.Shermantånk:BAAANQADCgYICAAAAA==.Shey:BAAANQADCggIDAAAAA==.Sheydon:BAAANQADCggICgAAAA==.Shikigamï:BAAANQAECgEJAQABNQAECggIGwAZADckAA==.Shikï:BAABNQAECoEbAAIZAAgKNyTNCAA/AwAZAAgKNyTNCAA/AwAAAA==.Shivermoón:BAABNQAECoEjAAIjAAgKmQsVLACHAQAjAAgKmQsVLACHAQAAAA==.',
Si='Siegbane:BAAANQAECgMIAwAAAA==.Sigesar:BAAANQADCggIIwAAAA==.Sigrún:BAAANQAECgYICwAAAA==.Simpforsouls:BAAANQADCgMIAwAAAA==.Sinsimella:BAAANQAECgEIAQAAAA==.',
Sk='Skullash:BAAANQADCgcIBwAAAA==.Skywatcher:BAAANQAECgUIDwAAAA==.',
Sl='Slaughtering:BAAANQAECgIIAgAAAA==.',
Sm='Smitemare:BAAANQAECgMIAwABNQAECgQIBQACAAAAAA==.',
Sn='Sneakmode:BAAANQAECgIIAgAAAA==.Sneakyz:BAAANQADCgIIAgAAAA==.Snicky:BAAANQAECgEJAQAAAA==.',
So='Solare:BAAANQAECggIAgAAAA==.Sonwarr:BAABNQAECoEeAAIDAAgKEhqzOQBfAgADAAgKEhqzOQBfAgAAAA==.',
Sp='Spliphtoker:BAAANQAECgEIAQAAAA==.',
St='Stabsolutely:BAAANQADCgUJBQABNQAECgQIBQACAAAAAA==.Steelpen:BAAANQAECgMIBQAAAA==.Stenston:BAAANQAECgYICwAAAA==.Sterede:BAAANQAECgEIAQAAAA==.Stitchwhich:BAAANQAECgYICQAAAA==.Stonehenge:BAAANQAECgYIEQAAAA==.Stormwolves:BAAANQAECgQIBAAAAA==.',
Su='Summers:BAAANQAECggIDwAAAA==.Surfclub:BAAANQAECgYIBAAAAA==.',
Sy='Sylphr:BAAANQAECgEIAQABNQAECggIFgAOAE0dAA==.Sylphrená:BAAANQAECgEIAQABNQAECggIJQAJANEfAA==.Sylphwild:BAAANQAECgYIDgABNQAECggIFgAOAE0dAA==.Sylvara:BAAANQAECgQICgAAAA==.Synkinz:BAAANQAECgUIDwAAAA==.Syntec:BAAANQABCgMIAgAAAA==.Syreite:BAAANQAECgUIDgAAAA==.',
Ta='Tacori:BAAANQAECgMIBAABNQAECgQIBgACAAAAAA==.Taessa:BAAANQADCgcIEQAAAA==.Tainipuni:BAAANQADCgYIBgAAAA==.Tallic:BAABNQAECoEiAAIeAAgKAhu9EwBEAgAeAAgKAhu9EwBEAgAAAA==.Talynayl:BAAANQADCgUIBwAAAA==.Tamarah:BAAANQAECgEIAQAAAA==.Tandemonium:BAAANQAECgUIBgABNQAFFAIIBQAkAOIcAA==.Taniz:BAABNQAECoEcAAMHAAgKXxv3QwB6AgAHAAgKXxv3QwB6AgAlAAcKLw/qMQCVAQAAAA==.Tarsi:BAAANQAECgUICwAAAA==.Taseg:BAAANQABCggICgAAAA==.',
Td='Td:BAABNQAFFIEUAAIJAAcKBR0vAQCvAgAJAAcKBR0vAQCvAgABNQAFFAkJJgAlAAgmAA==.',
Te='Tearinurside:BAAANQAECgYICwAAAA==.Telidrel:BAAANQADCgIIAwAAAA==.',
Tg='Tgi:BAAANQAECgMIBAAAAA==.',
Th='Thaddeaus:BAABNQAECoEjAAIFAAgK3BjbCwBOAgAFAAgK3BjbCwBOAgAAAA==.Thaddeus:BAAANQAECgQICAAAAA==.Thealin:BAAANQAECgMIAwAAAA==.Thebeefyone:BAAANQAECgQICwAAAA==.Thecanadian:BAAANQADCgQIBAAAAA==.Thegreatmel:BAAANQADCgIIAgAAAA==.Therizin:BAAANQAECgQIBAAAAA==.Thesummoner:BAAANQAECgEIAQAAAA==.Thornel:BAAANQADCgEIAQAAAA==.Thorrek:BAAANQAECggIEQAAAA==.Thrallete:BAAANQADCgUIBQAAAA==.Thugnificent:BAAANQABCggIDAAAAA==.Thumpette:BAAANQAECgMICgAAAA==.',
Ti='Tierant:BAAANQADCggIFgAAAA==.Tinaris:BAAANQADCgUICQABNQAECgYIEQACAAAAAA==.Tizaria:BAAANQAECgQICQAAAA==.',
Tm='Tmai:BAAANQAECgYICwAAAA==.',
To='Tominaetor:BAAANQADCgcIJAAAAA==.Tookans:BAAANQABCgUIBQAAAA==.Tosoto:BAABNQAECoEhAAMFAAcKhxvNDgASAgAFAAcKgRrNDgASAgAbAAcKZhHynQCnAQAAAA==.Toxica:BAAANQADCgMIAwAAAA==.',
Tr='Travcula:BAABNQAECoEcAAITAAgKBBqKMwA5AgATAAgKBBqKMwA5AgAAAA==.Treefiddy:BAAANQADCgEIAgAAAA==.Trumpd:BAAANQADCgUIBQABNQAECgEIAQACAAAAAA==.',
Ts='Tso:BAAANQADCgEIAQAAAA==.',
Tt='Ttriton:BAAANQADCgEIAQAAAA==.',
Tu='Tuuwa:BAAANQADCgMIAwAAAA==.',
Ty='Tyernan:BAABNQAECoEYAAIOAAgKkAWIyQBPAQAOAAgKkAWIyQBPAQAAAA==.Tyrioz:BAAANQAECgYIEQAAAA==.',
Tz='Tzavcat:BAAANQAECgYIDgAAAA==.',
Uh='Uhtred:BAAANQAECggIAgAAAA==.',
Un='Unknownmage:BAAANQABCgIIAgAAAA==.',
Ur='Urbi:BAAANQAECgUIDwAAAA==.',
Uv='Uvsol:BAAANQAECgMIAwAAAA==.',
Va='Vadailla:BAAANQAECgUIDAAAAA==.Vahrik:BAAANQADCgMIAwAAAA==.Valeirra:BAAANQADCgMIBQAAAA==.Valius:BAAANQAECgYIEAAAAA==.Valkyrae:BAAANQADCgQIBAAAAA==.Valornor:BAAANQAECgIJAgAAAA==.Vandill:BAABNQAECoEmAAIGAAgKghUjmQAwAgAGAAgKghUjmQAwAgAAAA==.Varyanwrynn:BAAANQAECgEIAQAAAA==.Vaxis:BAAANQADCgcIEwAAAA==.',
Ve='Veasnacool:BAABNQAECoEdAAIHAAUKxBviqQB+AQAHAAUKxBviqQB+AQAAAA==.Vestrit:BAAANQADCgIIAgABNQAECggIJQAJANEfAA==.',
Vo='Vontote:BAAANQAECgYIEAAAAA==.Vorix:BAAANQADCgcICwAAAA==.',
Vy='Vyluna:BAAANQADCggIKAAAAA==.',
['Ví']='Víc:BAAANQAECgUIDwAAAA==.',
Wa='Wandorf:BAEANQAECgQICAAAAA==.Warwolfe:BAABNQAECoEdAAMPAAcKMgqwnQBsAQAPAAcKOgmwnQBsAQAWAAIKHApqHAB2AAAAAA==.Wayler:BAAANQADCggICAAAAA==.',
Wh='Whitewâlker:BAAANQABCgUIBQAAAA==.Whumpus:BAAANQADCgIIAgAAAA==.Whyn:BAAANQAECgQIBAAAAA==.',
Wi='Willei:BAAANQADCgUICwAAAA==.',
Wo='Wolferunner:BAAANQAECgMIBgAAAA==.Wondermang:BAAANQAECgMIBgAAAA==.Worgenwebb:BAAANQAECgQICAABNQAECgkJIAAbAJMfAA==.',
Xa='Xaiden:BAAANQADCgcJBwAAAA==.Xaldora:BAAANQADCgEIAQAAAA==.Xali:BAAANQAECgIIBAAAAA==.Xanthrens:BAAANQADCgQIBgAAAA==.',
Xd='Xdxvuu:BAAANQAECgUIDAAAAA==.',
Xe='Xerimok:BAAANQAECgUIDAAAAA==.',
Xi='Xinya:BAAANQAECgUICwAAAA==.',
Xs='Xsavior:BAAANQAECgYIBwAAAA==.Xshando:BAAANQAECgIIAwAAAA==.Xsmkmonk:BAAANQAECgEIAQAAAA==.',
Xz='Xzephyr:BAABNQAECoEZAAIcAAcKWyKdHwCyAgAcAAcKWyKdHwCyAgAAAA==.',
Ya='Yamato:BAAANQAECgYIBgAAAA==.',
Ye='Yesmín:BAAANQAECgcIEgAAAA==.',
Yi='Yil:BAABNQAECoEXAAIDAAcK1xnrUwD7AQADAAcK1xnrUwD7AQAAAA==.',
Yo='Youwas:BAAANQAECgMIBQAAAA==.',
Ys='Yshtola:BAAANQADCgYICwAAAA==.',
Yu='Yukmouf:BAABNQAECoEWAAIOAAkKpBt2MwDeAgAOAAkKpBt2MwDeAgAAAA==.Yukshadow:BAAANQADCgMIAwAAAA==.Yuriika:BAAANQADCgYIBwAAAA==.Yuukmouf:BAAANQAECgQICgABNQAECgkJFgAOAKQbAA==.',
Za='Zakaris:BAAANQAECgUIEAAAAA==.Zaladin:BAAANQADCgUIBQAAAA==.Zarrove:BAABNQAECoEhAAIMAAgKRx3qEgCiAgAMAAgKRx3qEgCiAgAAAA==.Zawl:BAAANQAECgMIBQAAAA==.',
Ze='Zea:BAAANQADCgMIAwAAAA==.Zedael:BAAANQAECgYIBgAAAA==.Zellgadis:BAAANQADCgIIAgAAAA==.Zeltri:BAABNQAECoE1AAIZAAgKOgjhLwB8AQAZAAgKOgjhLwB8AQAAAA==.Zerg:BAAANQAECgUIDQAAAA==.',
Zh='Zhatva:BAACNQAFFIEFAAIHAAMKfRXeEQAFAQAHAAMKfRXeEQAFAQA1AAQKgSsAAwcACQp8Ia4YAB8DAAcACQp8Ia4YAB8DACUAAwosEpZQAL0AAAAA.Zhöe:BAAANQAECgUIBgAAAA==.',
Zi='Zimzhealz:BAAANQADCgcIDQAAAA==.Zimzorzz:BAAANQADCgUIBwABNQADCgcIDQACAAAAAA==.',
Zo='Zoelera:BAAANQAECgMIBAAAAA==.Zoldor:BAAANQAECgUIDwAAAA==.Zoleia:BAAANQADCgMIAwAAAA==.Zorellion:BAAANQAECgUIDgAAAA==.',
Zu='Zuay:BAAANQADCgIIAgABNQAECgkJLAAQANweAA==.Zulianguy:BAACNQAFFIEGAAIOAAIKpw/CHQCRAAAOAAIKpw/CHQCRAAA1AAQKgSIAAx4ACQoWIakSAFECAB4ABgptI6kSAFECAA4ABAq/HYjQAEABAAAA.',
Zy='Zycorr:BAAANQAECgEIAgAAAA==.Zytrex:BAAANQAECgQIBAAAAA==.',
['Zá']='Zátsu:BAAANQABCgEIAQAAAA==.',
['Äm']='Ämaterasu:BAAANQAECgQIBAABNQAECggIGwAZADckAA==.',
['Ñÿ']='Ñÿx:BAAANQAECgYICwAAAA==.',
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
