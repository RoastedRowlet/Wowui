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
local provider = {region='US',realm='Drakkari',name='US',type='weekly',zone=53,date='2026-09-01',data={Aa='Aatrøx:BAAANQADCgMIBAAAAA==.',
Ab='Abhigail:BAAANQADCgYICwAAAA==.Abuelabetzy:BAAANQADCgIIAgAAAA==.Abueladanger:BAAANQADCgUIBQAAAA==.',
Ac='Acaelus:BAAANQADCgUIBQAAAA==.Ackrüdk:BAAANQADCgcIBwAAAA==.',
Ad='Adirà:BAAANQADCgQIBAAAAA==.',
Ae='Aeroart:BAAANQADCgMIAwAAAA==.',
Ag='Aggy:BAAANQADCgMIAQAAAA==.Agreegor:BAAANQADCgIIAgAAAA==.Agrellor:BAAANQADCgYIBgAAAA==.Agrotank:BAAANQAECgQIBAAAAA==.Aguafluye:BAAANQADCgEIAQAAAA==.',
Ah='Ahktund:BAAANQADCgYICQAAAA==.',
Ai='Ailuros:BAAANQAECgEIAQAAAA==.',
Ak='Akachete:BAAANQADCgIIAgAAAA==.Akazael:BAAANQADCgYIDAAAAA==.',
Al='Ala:BAAANQADCgYIBwAAAA==.Alathra:BAAANQADCgYIBgAAAA==.Albaficar:BAAANQADCgMIBAAAAA==.Aldebbarann:BAAANQADCgYICgAAAA==.Aldrona:BAAANQADCgYICwAAAA==.Alejoz:BAAANQADCgQIBAAAAA==.Alessiià:BAAANQADCgcIBwAAAA==.Alfy:BAAANQADCgIIAgAAAA==.Aliicea:BAAANQADCgEIAQAAAA==.Alliesh:BAAANQADCgQIBAAAAA==.Alquimetal:BAAANQADCgUIBQAAAA==.Alrog:BAAANQADCgYIBgAAAA==.Alsiel:BAAANQADCgMIAwAAAA==.Alternative:BAAANQADCgYIBwAAAA==.Alvea:BAAANQADCgEIAQAAAA==.Alvorada:BAAANQADCgYIDAAAAA==.',
Am='Ambusoraka:BAAANQADCgYIDQAAAA==.Amor:BAAANQAECgYIBwAAAA==.Amumu:BAAANQAECgEIAQAAAA==.Amäzonya:BAAANQADCgYICwAAAA==.',
An='Anakiin:BAAANQADCgcICwAAAA==.Anakin:BAAANQABCgIIAgAAAA==.Analiha:BAAANQAECgMIBAAAAA==.Anaskmy:BAAANQADCgUICQAAAA==.Andrewsarkus:BAAANQADCgYIDQAAAA==.Ankthar:BAAANQADCgEIAQAAAA==.Annà:BAAANQADCggICAAAAA==.Anní:BAAANQAECgEIAQAAAA==.Anoano:BAAANQAECgEIAQAAAA==.Antimagee:BAAANQADCgQIBAAAAA==.Anux:BAAANQADCgIIAgAAAA==.',
Ao='Aoky:BAAANQADCgYICgAAAA==.Aom:BAAANQADCggIDgAAAA==.Aomesan:BAAANQADCggIDQAAAA==.',
Ap='Apholö:BAAANQADCgcIDAAAAA==.Apos:BAAANQAFFAEIAQAAAA==.Applevenus:BAAANQADCgUIBgAAAA==.',
Ar='Arandher:BAAANQADCgcIDAAAAA==.Arcanbot:BAAANQADCgIIAgAAAA==.Archeón:BAAANQABCgEIAQAAAA==.Arcrav:BAAANQAECgUICQAAAA==.Arcraxx:BAAANQAECgEIAQAAAA==.Ares:BAAANQADCgQIBAAAAA==.Argelo:BAAANQADCgQIBAAAAA==.Argilac:BAAANQADCgIIAgAAAA==.Ariël:BAAANQABCgQIBgAAAA==.Arkhonte:BAAANQAECgIIAgAAAA==.Arphenom:BAAANQADCgcICwAAAA==.Arry:BAAANQADCgYICQAAAA==.Artemisadn:BAAANQADCgcIDQAAAA==.Artherir:BAAANQAECgYIBgAAAA==.',
As='Ashalanor:BAAANQADCgEIAQAAAA==.Ashelatto:BAAANQADCgUIBQABNQAECgUIBgABAAAAAA==.Ashirogi:BAAANQADCgYICQAAAA==.Astralit:BAAANQADCgIIAgAAAA==.Astravia:BAAANQADCgMIAwAAAA==.',
At='Atenasuru:BAAANQADCgEIAQAAAA==.Athandrui:BAAANQADCgQIBAAAAA==.Atheas:BAAANQADCgEIAQAAAA==.Atilaa:BAAANQAECgQIBQAAAA==.',
Av='Avenaquaker:BAAANQAECgUIBQAAAA==.Avethrus:BAAANQADCggICwAAAA==.',
Ay='Ayorya:BAAANQAECgEIAQAAAA==.',
Az='Azaks:BAAANQAECgIIAgAAAA==.Azarelshot:BAAANQADCgYICQAAAA==.Azarelthas:BAAANQADCgQIBAAAAA==.Azarelux:BAAANQADCggIDgAAAA==.Azidahakas:BAAANQADCggIDAAAAA==.Azores:BAAANQADCgYICQAAAA==.Azsharael:BAAANQADCgYIBwAAAA==.Azymondiaz:BAAANQAECgMIBAAAAA==.',
Ba='Baballagha:BAAANQADCgIIAgAAAA==.Backup:BAAANQADCgQIBAAAAA==.Badpowell:BAAANQAECgIIAgAAAA==.Baileysade:BAAANQADCgYICgAAAA==.Bakarass:BAAANQADCgIIAgABNQABCgIIAgABAAAAAA==.Balanky:BAAANQADCgYIBgAAAA==.Baliyeh:BAAANQADCgMIAwAAAA==.Bathier:BAAANQAECgIIAgAAAA==.Bayula:BAAANQAECgEIAQAAAA==.',
Be='Beickergamer:BAAANQADCgMIBQAAAA==.Belladonna:BAAANQADCgUICAAAAA==.Beniøn:BAAANQADCgIIAgAAAA==.Benzott:BAAANQADCgcICQAAAA==.Berkas:BAAANQADCgMIAwAAAA==.Berserkss:BAAANQADCgMIAwAAAA==.Beyondhope:BAAANQADCgYICAAAAA==.',
Bh='Bhhal:BAAANQADCgcIBwAAAA==.',
Bi='Biance:BAAANQAECgEIAQAAAA==.Bicklouw:BAAANQADCgUIBQAAAA==.Bigpunisher:BAAANQADCgcIEgAAAA==.Biorns:BAAANQADCggIDAAAAA==.',
Bl='Blackkô:BAAANQAECgIIAgAAAA==.Blackraisond:BAAANQADCgQIBwAAAA==.Blakscorpion:BAAANQADCgQIBQAAAA==.Bleiis:BAAANQAECgEIAQAAAA==.Blessrage:BAAANQADCgMIAwAAAA==.Bloodoroth:BAAANQADCgQICAAAAA==.Bluedh:BAAANQADCgUICAABNQADCgYIBgABAAAAAA==.Bluevoker:BAAANQADCgYIBgAAAA==.',
Bo='Bolg:BAAANQADCgUIBQAAAA==.Bonsaijr:BAAANQADCgcICwAAAA==.Bonsaipro:BAAANQAECgIIAgAAAA==.Botìja:BAAANQADCgUICAAAAA==.',
Br='Branngus:BAAANQADCgYIEQAAAA==.Breiknar:BAAANQADCgQIBAAAAA==.Brewnation:BAAANQADCgcICwAAAA==.Brightsad:BAAANQAECgMIAwAAAA==.Brishna:BAAANQADCggIDwAAAA==.Brunoos:BAAANQADCgUIBQAAAA==.Brusiu:BAAANQAECgEIAQAAAA==.',
Bu='Buddy:BAAANQADCgQIBAAAAA==.Bulloflight:BAAANQADCgIIAgAAAA==.Bunda:BAAANQAECgMIAwAAAA==.',
Ca='Cabecar:BAAANQADCgYICQAAAA==.Caberlock:BAAANQAECgEIAQAAAA==.Cadmel:BAAANQADCgUIBQAAAA==.Caesarss:BAAANQADCgIIAwAAAA==.Calancho:BAAANQAECgIIAgAAAA==.Candise:BAAANQAECgIIAgAAAA==.Candlejack:BAAANQADCgUIBQAAAA==.Capkast:BAAANQADCgcIBwAAAA==.Caralock:BAAANQAECgIIAgAAAA==.Carcass:BAAANQADCgYIBQAAAA==.Carneasa:BAAANQADCggICAAAAA==.Carpinchø:BAAANQAECgEIAQAAAA==.Carrasquinho:BAAANQAECgIIAgAAAA==.Cassiusclay:BAAANQAECgEIAQAAAA==.Cawboy:BAAANQAECggIDQAAAA==.Cayuwoky:BAAANQAECgEIAQAAAA==.Cazadorpaska:BAAANQADCgQIBQAAAA==.',
Ce='Cearlink:BAAANQADCgYIBgAAAA==.Cel:BAAANQADCgQIBAAAAA==.Celhi:BAAANQADCgEIAQAAAA==.',
Ch='Chamask:BAAANQADCggICAAAAA==.Chameeto:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.Chamilk:BAAANQADCgYICwAAAA==.Chammiin:BAAANQADCgIIAgAAAA==.Chastia:BAAANQABCgIIAwAAAA==.Chechuna:BAAANQAECgIIAgAAAA==.Chepe:BAAANQADCgUIBQAAAA==.Chicobamm:BAAANQADCgEIAQAAAA==.Chiller:BAAANQADCgUIBQAAAA==.Chinxulin:BAAANQADCgYICwAAAA==.Chocottrenza:BAAANQABCgEIAQAAAA==.Choriser:BAAANQADCgQIBAAAAA==.Chrís:BAAANQADCggICAAAAA==.Chrïspala:BAAANQADCgUIBQAAAA==.Chuckyseador:BAAANQADCgEIAQAAAA==.Chyrene:BAAANQADCgYIBgABNQADCgcIBwABAAAAAA==.',
Ci='Ciagnai:BAAANQADCgUIBQAAAA==.Ciircé:BAAANQAECgQIBAAAAA==.',
Cl='Claribelle:BAAANQAECgEIAQAAAA==.Classicmurió:BAAANQADCgUIBQAAAA==.Clavakchan:BAAANQADCgQIBAAAAA==.Cliffs:BAAANQADCgEIAQABNQADCgUIBQABAAAAAA==.Clorpi:BAAANQADCgQIBAAAAA==.Clëoh:BAAANQAECgEIAQAAAA==.',
Co='Conkercx:BAAANQADCgIIAgAAAA==.Courel:BAAANQADCgQIBAAAAA==.Coyotino:BAAANQADCgQIAgAAAA==.',
Cr='Crimsonclaw:BAAANQADCggIBgAAAA==.Cristthell:BAAANQADCggICwAAAA==.Crixis:BAAANQADCgEIAQAAAA==.Crookie:BAAANQADCgEIAQAAAA==.Crìxus:BAAANQADCgYICgAAAA==.',
Cu='Cuchicuchl:BAAANQADCgEIAQAAAA==.',
['Cä']='Cärola:BAAANQAECgMIAwAAAA==.',
['Cë']='Cëlestial:BAAANQAECgEIAQAAAA==.',
['Cö']='Cönner:BAAANQADCgEIAQAAAA==.',
Da='Dadu:BAAANQADCgQIBAAAAA==.Daemerys:BAAANQADCggIDQAAAA==.Dagasnakë:BAAANQADCgYIBgAAAA==.Dagurame:BAAANQABCgQIBAAAAA==.Dailee:BAAANQADCgMIAwAAAA==.Daimøn:BAAANQAECgYICgAAAA==.Daishiro:BAAANQAECgQIBwAAAA==.Dakanji:BAAANQADCgEIAQAAAA==.Damarus:BAAANQADCgUIAgAAAA==.Damhián:BAAANQADCgEIAQAAAA==.Danot:BAAANQADCgQIBAAAAA==.Dantenamikaz:BAAANQADCgYIBgAAAA==.Darckamage:BAAANQADCgYIBgABNQAECgcIDAABAAAAAA==.Dariansa:BAAANQAECgcIDAABNQADCgYIBgABAAAAAA==.Darkamerica:BAAANQADCgEIAQAAAA==.Darkarus:BAAANQADCgMIAwAAAA==.Darkelezzard:BAAANQADCgEIAQAAAA==.Darkrivera:BAAANQAECgIIAgAAAA==.Darre:BAAANQAECgEIAQAAAA==.Darthveil:BAAANQAECgUIBgAAAA==.Datsury:BAAANQADCgIIAgABNQAECgQIBAABAAAAAA==.Daxxoz:BAAANQADCgcICgAAAA==.Dayhunter:BAAANQADCgYIBgAAAA==.Dayix:BAAANQAECgMIBAABNQAECgQIBQABAAAAAA==.Dayonïs:BAAANQAECgEIAQAAAA==.Dazielth:BAAANQABCgEIAQAAAA==.',
Dd='Ddualipa:BAAANQADCgMIAQAAAA==.',
De='Deathscyth:BAAANQADCgYIAwAAAA==.Deceris:BAAANQADCgEIAQAAAA==.Deet:BAAANQADCgMIAwAAAA==.Delsey:BAAANQADCgQIBgAAAA==.Demmontaz:BAAANQADCgEIAQAAAA==.Demoní:BAAANQADCgMIAwAAAA==.Demorzz:BAAANQAECgQICAAAAA==.Deoxis:BAAANQADCgYICQAAAA==.Depdep:BAAANQADCggIDQAAAA==.Depxy:BAAANQADCgIIAgABNQADCgUIBQABAAAAAA==.Dessaju:BAAANQADCgEIAQABNQAECgIIAwABAAAAAA==.Destia:BAAANQAECgQIBwABNQAFFAEIAQABAAAAAA==.Destinyxd:BAAANQAECgcIDgAAAA==.Det:BAAANQAECgQIBAAAAA==.Deusgéo:BAAANQADCgEIAQAAAA==.Dexrak:BAAANQAECgEIAQAAAA==.',
Dh='Dheka:BAAANQADCgIIAgAAAA==.',
Di='Diaska:BAAANQADCgMIAwAAAA==.Diazmerlyn:BAAANQAECgEIAQAAAA==.Diazo:BAAANQADCgMIAwAAAA==.Didragosa:BAAANQADCgIIAgAAAA==.Diego:BAAANQADCgYIBwAAAA==.Diegodruid:BAAANQAECgIIAgAAAA==.Diegolon:BAAANQADCgQIBgAAAA==.Diegostorm:BAAANQADCgYIBgAAAA==.Digbingus:BAAANQADCgIIAgAAAA==.Dinaara:BAAANQADCgMIAwAAAA==.Disturbiø:BAAANQADCgcICgAAAA==.Dizzys:BAAANQADCgIIAgAAAA==.',
Dj='Djmariof:BAAANQAECgEIAQAAAA==.',
Dk='Dkescanor:BAAANQAECgIIAgAAAA==.Dkgrisel:BAAANQABCgEIAQAAAA==.Dkingmax:BAAANQADCgIIAgAAAA==.Dklehif:BAAANQADCgIIAgAAAA==.Dkpibara:BAAANQAECgEIAQAAAA==.Dkraris:BAAANQAECgEIAQAAAA==.Dktazz:BAAANQADCgQIBAAAAA==.Dkzero:BAAANQADCgIIAgAAAA==.',
Do='Doblegador:BAAANQADCgYIBgAAAA==.Doluis:BAAANQADCgMIAwAAAA==.Doscuatro:BAAANQADCgQIBAAAAA==.Doucemort:BAAANQADCgYIBgAAAA==.',
Dp='Dpalas:BAAANQADCgUIBQAAAA==.',
Dr='Draconya:BAAANQADCgYICQAAAA==.Draell:BAAANQADCgYIBgAAAA==.Dragenh:BAAANQAECgYICgAAAA==.Dragonlight:BAAANQADCgYIBgAAAA==.Drakaelis:BAAANQADCgQIBgAAAA==.Drakalath:BAAANQADCgEIAQABNQADCgQIBgABAAAAAA==.Draknus:BAAANQADCggIDwAAAA==.Dralchukos:BAAANQADCggICAAAAA==.Drarry:BAAANQADCggICgABNQAECgQIBAABAAAAAA==.Drestroye:BAAANQABCgIIBQAAAA==.Drkemora:BAAANQADCgMIAwAAAA==.Drudnerr:BAAANQADCgcICgAAAA==.Druidprince:BAAANQADCgYIBwAAAA==.Dráconiant:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.',
Du='Duduboyito:BAAANQADCgYIBgAAAA==.Duurootar:BAAANQAECgEIAQAAAA==.',
Dw='Dwarfone:BAAANQADCggIDAAAAA==.',
Dz='Dzul:BAAANQADCgIIAgAAAA==.',
['Dø']='Dønpikin:BAAANQADCgQIBQAAAA==.',
['Dü']='Dürtz:BAAANQAECgEIAQAAAA==.',
Eb='Ebanel:BAAANQADCgYICAAAAA==.',
Ec='Eclipsa:BAAANQAECgMIAwAAAA==.Ecofrio:BAAANQADCgMIAwAAAA==.',
Ed='Edark:BAAANQAECgEIAQAAAA==.Edusp:BAAANQADCgYIBgAAAA==.',
Eg='Egoca:BAAANQADCgEIAQAAAA==.',
Ei='Eiko:BAAANQADCggIEAAAAA==.',
El='Elentiyaa:BAAANQAECgEIAQAAAA==.Eleonoret:BAAANQAECgEIAQAAAA==.Elguskullu:BAAANQAECgEIAQAAAA==.Elk:BAAANQADCggIDAAAAA==.Elkie:BAAANQADCgcICgAAAA==.Ellinar:BAAANQADCgYICQAAAA==.Elohisa:BAAANQADCgYIBgAAAA==.Elpoyoloco:BAAANQADCgcIDAAAAA==.Elrr:BAAANQABCgQIBAAAAA==.Eltormetias:BAAANQAECgEIAQAAAA==.Eltuerton:BAAANQADCgQIBAAAAA==.Elviraa:BAAANQADCgMIAwAAAA==.Elxadal:BAAANQADCgEIAQAAAA==.Elxochanguas:BAAANQADCgYICQAAAA==.Elyndræ:BAAANQADCgYICAAAAA==.',
Em='Emersyn:BAAANQADCgUICQAAAA==.Empanizado:BAAANQADCgIIAgAAAA==.',
En='Enror:BAAANQADCgMIAwAAAA==.Enzaro:BAAANQADCgYICQAAAA==.',
Er='Erlang:BAAANQAECgEIAQAAAA==.',
Es='Escannor:BAAANQADCgUIBQAAAA==.Escanorsama:BAAANQADCgMIAQAAAA==.Esnad:BAAANQAECgYICgAAAA==.',
Ev='Evilkerzel:BAAANQAECgEIAQAAAA==.Evillis:BAAANQADCgcIDAAAAA==.Eviltyra:BAAANQAECgQIBAAAAA==.Evissa:BAAANQAECgEIAQAAAA==.',
Ex='Explicits:BAAANQAECgEIAQAAAA==.',
Ez='Ezeqeel:BAAANQAECgEIAQAAAA==.',
['Eí']='Eísén:BAAANQADCgcIDAAAAA==.',
Fa='Fakkir:BAAANQAECgEIAQAAAA==.Fayyisaa:BAAANQADCgIIAgAAAA==.',
Fb='Fbk:BAAANQADCgEIAQAAAA==.',
Fe='Felicie:BAAANQADCgYICgAAAA==.Ferchudoto:BAAANQADCgEIAQAAAA==.',
Fh='Fherty:BAAANQAECgIIAQAAAA==.Fhxhs:BAAANQADCgYIDAAAAA==.',
Fi='Finheas:BAAANQADCgUIBQAAAA==.Fionnæ:BAAANQADCgcICQAAAA==.Firana:BAAANQADCgQIBAABNQADCgQIBAABAAAAAA==.',
Fk='Fkrsrs:BAAANQAECgQIBAAAAA==.',
Fl='Flacapala:BAAANQAECgIIAgAAAA==.Flashoflight:BAAANQADCgEIAQAAAA==.',
Fo='Forasstero:BAAANQADCggICAAAAA==.Forkan:BAAANQADCgUIAgAAAA==.',
Fr='Frisad:BAAANQADCggIDgAAAA==.Frostrike:BAAANQADCgUIBQAAAA==.',
Fu='Fullx:BAAANQADCgQIBgAAAA==.Furrynn:BAAANQADCgYICwAAAA==.',
['Fä']='Fäenor:BAAANQADCgcIDAAAAA==.',
Ga='Gabydit:BAAANQAECgEIAgAAAA==.Gadito:BAAANQAECgUIBwABNQAECggIDQABAAAAAA==.Galadhriell:BAAANQAECgQIAQAAAA==.Galädriel:BAAANQAECgEIAgAAAA==.Ganttzz:BAAANQADCgYIDQAAAA==.Gardner:BAAANQABCgQIBAAAAA==.Garrok:BAAANQADCgUIBQAAAA==.Gaspar:BAAANQAECgIIAgAAAA==.Gatyto:BAAANQADCgUIBQAAAA==.Gaudy:BAAANQADCgYIBgAAAA==.Gazi:BAAANQADCggIDgAAAA==.',
Ge='Gemíta:BAAANQAECgIIAgAAAA==.Gerc:BAAANQAECgEIAQAAAA==.',
Gi='Giur:BAAANQAECgEIAQAAAA==.',
Gl='Glimdar:BAAANQADCgcICQAAAA==.Glopis:BAAANQADCgIIAgAAAA==.Glørious:BAAANQADCgYICAAAAA==.',
Gn='Gnomecholas:BAAANQADCggIDgAAAA==.',
Go='Goge:BAAANQAECgEIAQAAAA==.Gokuderah:BAAANQADCgMIAwAAAA==.Goloh:BAAANQADCgYIBgAAAA==.Goodlike:BAAANQADCgQIBAAAAA==.Gordinho:BAAANQAECgEIAQAAAA==.Gordochispas:BAAANQAECgUIBgAAAA==.Gothdita:BAAANQAECgEIAQAAAA==.',
Gr='Grondy:BAAANQAECgMIAwAAAA==.Grthpaly:BAAANQADCgUIBQAAAA==.Grïsh:BAAANQAECgEIAQAAAA==.',
Gu='Guarmist:BAAANQADCgIIAgAAAA==.Guaztarger:BAAANQADCgQIBAAAAA==.Guiselle:BAAANQAECgIIAgAAAA==.Gusfringk:BAAANQADCgYICgAAAA==.Gustavh:BAAANQADCgMIAwAAAA==.Guxue:BAAANQADCgYIDAAAAA==.',
Gw='Gwendevere:BAAANQADCgYIBwAAAA==.',
Ha='Haethos:BAAANQADCgUICgAAAA==.Hajimi:BAAANQAECgQIBAAAAA==.Halrinak:BAAANQADCgYICgAAAA==.Hammernegro:BAAANQADCgUIBQAAAA==.Hanito:BAAANQAECgEIAQAAAA==.Happycherry:BAAANQAECgQIBAAAAA==.Harguenn:BAAANQADCgYIBgAAAA==.Harutox:BAAANQADCgIIAgAAAA==.Hashem:BAAANQAECgEIAQAAAA==.Hattzune:BAAANQADCgEIAQAAAA==.Hawkey:BAAANQADCgUICQAAAA==.Haz:BAAANQADCgUIBQAAAA==.Hazy:BAAANQAECgIIAgAAAA==.Hazzar:BAAANQADCgIIAgAAAA==.',
He='Hedblink:BAAANQADCgYICQAAAA==.Hefestor:BAAANQADCgEIAQAAAA==.Heffy:BAAANQADCgYIDAABNQAECgEIAQABAAAAAA==.Heffyd:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Heffyx:BAAANQAECgEIAQAAAA==.Hekan:BAAANQAECgEIAgAAAA==.Helsiing:BAAANQADCgQIBAAAAA==.Hernagorax:BAAANQADCgIIAgAAAA==.',
Hi='Hierbatero:BAAANQADCgQIAQAAAA==.Hiperioon:BAAANQADCgYICQAAAA==.Hisdra:BAAANQADCgQIBAAAAA==.',
Ho='Holoyuta:BAAANQAECgUICQAAAA==.Holoziru:BAAANQAECgIIAgAAAA==.Hommerjay:BAAANQAECgUIBQAAAA==.Houdax:BAAANQADCgIIAgAAAA==.',
Hu='Hunhao:BAAANQADCgUIBgAAAA==.Huntwok:BAAANQADCgYIBgAAAA==.Hurun:BAAANQADCggIDAAAAA==.',
Hy='Hyiakki:BAAANQADCgMIAwABNQADCgEIAQABAAAAAA==.Hyiâkki:BAAANQADCgEIAQAAAA==.',
['Hí']='Hínatax:BAAANQADCgQIBgAAAA==.',
Ia='Iamtenito:BAAANQADCggIDgAAAA==.',
Ic='Icarusa:BAAANQADCgEIAQAAAA==.',
Ik='Ikarik:BAAANQADCgYICgABNQAECgIIAgABAAAAAA==.',
Im='Imac:BAAANQADCgQIBAAAAA==.Imelda:BAAANQADCgMIAwAAAA==.Imnictus:BAAANQAECgIIAgAAAA==.Impstorm:BAAANQAECgQIBAAAAA==.Imsama:BAAANQADCgQIBwAAAA==.Imthor:BAAANQADCgEIAQAAAA==.Imzeen:BAAANQADCgQIBAAAAA==.',
In='Inguz:BAAANQADCggICAAAAA==.Innari:BAAANQAECgEIAQAAAA==.Inquisicion:BAAANQADCgYIBgAAAA==.Invitro:BAAANQADCgEIAQAAAA==.',
Ir='Irenebelse:BAAANQAECgEIAQAAAA==.Ironfaith:BAAANQAECgQIBAAAAA==.',
It='Itachila:BAAANQADCgQIBAAAAA==.',
Ja='Jacal:BAAANQADCgUIBQAAAA==.Jackstick:BAAANQAECgEIAQAAAA==.Jair:BAAANQAECgUICAAAAA==.Janetla:BAAANQADCgYIBgAAAA==.Jarred:BAAANQADCgEIAQAAAA==.Javiëra:BAAANQADCgcIDAAAAA==.',
Je='Jealfredó:BAAANQADCgQIAwAAAA==.Jelou:BAAANQADCgIIAgAAAA==.',
Jh='Jhirek:BAAANQADCgUIBQAAAA==.',
Ji='Jidenm:BAAANQAECgIIAgAAAA==.Jidrix:BAAANQADCgQIBQAAAA==.Jinath:BAAANQADCgMIAwABNQADCgUIBQABAAAAAA==.Jingu:BAAANQADCgQIBQAAAA==.',
Jk='Jkjn:BAAANQADCgMIAwAAAA==.Jkllein:BAAANQAECgMIAwAAAA==.',
Jl='Jlink:BAAANQAECgEIAQAAAA==.',
Jo='Josemadrazo:BAAANQAECgEIAQAAAA==.Joswar:BAAANQADCgQIBAAAAA==.Joudalf:BAAANQADCgUICQAAAA==.',
Ju='Juanky:BAAANQADCgUIBQAAAA==.Juanow:BAAANQADCgQIBgAAAA==.Juliux:BAAANQADCgYIBwAAAA==.Juraexanime:BAAANQAECgIIAgAAAA==.Jurgën:BAAANQADCgIIAgAAAA==.',
Jv='Jvgg:BAAANQADCgIIAgAAAA==.',
Jw='Jwickk:BAAANQADCgYIBgAAAA==.',
Ka='Kachupinsito:BAAANQAECgQIBgAAAA==.Kageru:BAAANQADCgYICAAAAA==.Kaguire:BAAANQADCggICAAAAA==.Kaiidari:BAAANQAECgIIAQAAAA==.Kalerin:BAAANQADCgQIBAAAAA==.Kaliell:BAAANQADCgQIBAAAAA==.Kalithas:BAAANQADCgEIAQAAAA==.Kaltiro:BAAANQADCgIIAgAAAA==.Kaltozz:BAAANQAECgMIAgAAAA==.Kalyza:BAAANQADCgIIAgAAAA==.Kamakawiwo:BAAANQADCgMIAwAAAA==.Kamuss:BAAANQAECgUIBQAAAA==.Kaníma:BAAANQADCggIDAAAAA==.Karmelin:BAAANQADCgUIAwAAAA==.Kazuprime:BAAANQAECgIIAgAAAA==.Kaøri:BAAANQAECgQIBwAAAA==.',
Ke='Kelethir:BAAANQADCgUIBQAAAA==.Kelsir:BAAANQAECgIIAgAAAA==.Keltzhar:BAAANQADCgQIBAAAAA==.Kenia:BAAANQADCgcIDAAAAA==.Kerarthas:BAAANQADCgEIAQAAAA==.Kezhu:BAAANQAECgEIAQAAAA==.',
Kh='Khhalo:BAAANQADCgYICAAAAA==.Khime:BAAANQADCgUICQAAAA==.Khurysta:BAAANQAECgEIAQAAAA==.Khäelth:BAAANQADCgYICgAAAA==.',
Ki='Kienesmarco:BAAANQADCgIIAgAAAA==.Kipura:BAAANQADCgIIAgAAAA==.Kiriotosu:BAAANQADCgYIBgAAAA==.Kittyfer:BAAANQADCgIIAgAAAA==.',
Kl='Klounte:BAAANQADCgIIAgAAAA==.',
Ko='Kojiro:BAAANQADCgUIBQAAAA==.Koller:BAAANQADCgMIAwAAAA==.Konha:BAAANQAECgEIAQAAAA==.Koriente:BAAANQAECgIIAgAAAA==.Korlat:BAAANQADCgEIAQAAAA==.Koruchi:BAAANQADCgQIBAAAAA==.Koshkauwu:BAAANQADCgEIAQAAAA==.',
Kr='Kratzio:BAAANQADCgYIBgAAAA==.Kresty:BAAANQADCgYICwAAAA==.Kronio:BAAANQADCgYICgAAAA==.Krystaluwu:BAAANQADCgQIBgAAAA==.',
Ku='Kukuman:BAAANQADCgEIAQAAAA==.Kungfuupanda:BAAANQADCgIIAgAAAA==.Kunlaoxd:BAAANQADCgUIBwAAAA==.Kuroyamiwow:BAAANQADCgcIDQAAAA==.Kuvira:BAAANQADCgUICgAAAA==.',
Kv='Kv:BAAANQADCgMIAwAAAA==.Kvicha:BAAANQADCgEIAQAAAA==.Kvinprince:BAAANQADCgEIAQABNQADCgYIBwABAAAAAA==.Kvolthe:BAAANQAECgEIAQAAAA==.',
Ky='Kyorî:BAAANQADCgMIAwAAAA==.Kyranthrax:BAAANQADCgcICAAAAA==.Kyraéth:BAAANQADCgYIBgAAAA==.',
['Kø']='Køa:BAAANQADCgYIBgAAAA==.',
La='Labambaa:BAAANQAECgEIAQAAAA==.Laboons:BAAANQADCgEIAQAAAA==.Lacuba:BAAANQADCgIIAgAAAA==.Ladroga:BAAANQADCgYICAAAAA==.Laeroth:BAAANQABCgMIAgAAAA==.Lafieroski:BAAANQADCgIIBAAAAA==.Lafoxi:BAAANQADCgQIBAAAAA==.Laheeja:BAAANQADCgEIAQAAAA==.Laidlywormpa:BAAANQAECgEIAQAAAA==.Lakungfusión:BAAANQADCgUICQAAAA==.Lanuda:BAAANQADCgYIBgAAAA==.Lardelx:BAAANQADCgcIDQAAAA==.Lastorc:BAAANQADCgUIBgAAAA==.Lastwärrior:BAAANQAECgUIBQAAAA==.Lavalock:BAAANQADCgYIBgAAAA==.',
Le='Leamblue:BAAANQADCgUIBQAAAA==.Lebombas:BAAANQADCgUIBQAAAA==.Lechushm:BAAANQADCgIIAgAAAA==.Leiah:BAAANQADCgIIAgAAAA==.Lemuria:BAAANQADCgQIBAAAAA==.Lenøre:BAAANQADCgcIBwAAAA==.Leomonx:BAAANQAECgEIAQAAAA==.Leopoldonx:BAAANQADCggIDQAAAA==.Letu:BAAANQADCgMIAwAAAA==.Letø:BAAANQADCgUIBQAAAA==.Leviastús:BAAANQAECgMIAwAAAA==.Leviattán:BAAANQADCgEIAQAAAA==.Leömön:BAAANQAECgQIBAAAAA==.',
Lh='Lhukan:BAAANQAECgMIAwAAAA==.Lhura:BAAANQADCgcIDQAAAA==.',
Li='Liacachetona:BAAANQADCgQIBAAAAA==.Libi:BAAANQADCgIIAgAAAA==.Lightjandra:BAAANQADCgYICAAAAA==.Lilea:BAAANQADCgYIBwAAAA==.Limcross:BAAANQADCgQIBAAAAA==.Limeña:BAAANQADCgQIBAAAAA==.Lindabb:BAAANQADCgQIBAAAAA==.Lindurita:BAAANQADCgEIAQAAAA==.Linkz:BAAANQADCgYICQAAAA==.Lios:BAAANQADCgUIBQAAAA==.Lipus:BAAANQADCgcIDAAAAA==.Litts:BAAANQADCgQIBQAAAA==.',
Lo='Lobillodk:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.Lochupontero:BAAANQADCgEIAQAAAA==.Lokani:BAAANQADCgcIBwAAAA==.Lostpower:BAAANQADCggICAAAAA==.',
Lt='Lt:BAAANQADCgQIBAAAAA==.',
Lu='Lubb:BAAANQADCgQIBQAAAA==.Lubye:BAAANQADCgEIAQAAAA==.Lucandlere:BAAANQADCgQIBAAAAA==.Luggubre:BAAANQAECgQIBwAAAA==.Luisaacg:BAAANQADCgMIAwAAAA==.Luisitoxx:BAAANQAECgEIAQAAAA==.Lumis:BAAANQADCggIDgAAAA==.Lusitanian:BAAANQADCgcIDQAAAA==.Luxiien:BAAANQAECgMIAwAAAA==.',
Lx='Lxa:BAAANQADCgQIBAAAAA==.Lxmrcheesexl:BAAANQAECgMIAwAAAA==.',
['Lá']='Lást:BAAANQADCggIDgAAAA==.',
['Lé']='Léonel:BAAANQADCggICAAAAA==.',
['Lì']='Lìlíth:BAAANQAECgEIAQAAAA==.',
['Lú']='Lúmiere:BAAANQADCgEIAQAAAA==.Lúriza:BAAANQADCgcICAAAAA==.Lúthién:BAAANQADCgEIAQAAAA==.',
Ma='Mabilomi:BAAANQADCgIIAgAAAA==.Macdonal:BAAANQADCgYIBgAAAA==.Macklein:BAAANQADCgYICAAAAA==.Magikall:BAAANQADCgUIBQAAAA==.Makatraka:BAAANQADCgQIBAAAAA==.Makodra:BAAANQAECgMIAwAAAA==.Malakaí:BAAANQADCgUICAAAAA==.Maldrux:BAAANQAECgMIBAAAAA==.Malextrasa:BAAANQAECgIIAwAAAA==.Malkrim:BAAANQADCgYIBgAAAA==.Manamonk:BAAANQADCgQIBAAAAA==.Manatz:BAAANQADCgYIBgAAAA==.Mandredivh:BAAANQADCggIDAAAAA==.Mannat:BAAANQADCgQIBAABNQADCgYIBgABAAAAAA==.Margrace:BAAANQADCgcICQAAAA==.Maripxd:BAAANQADCgIIAgAAAA==.Matusalix:BAAANQADCgUIBgAAAA==.Maynard:BAAANQADCgcIDQABNQAECgYICQABAAAAAA==.',
Md='Mddemon:BAAANQAECgEIAQABNQAECgYIBgABAAAAAA==.Mdmague:BAAANQAECgYIBgAAAA==.',
Me='Medaly:BAAANQADCgcIDAAAAA==.Meinxia:BAAANQADCggIDgAAAA==.Melhí:BAAANQADCgQIBAABNQAECgYICgABAAAAAA==.Melianor:BAAANQAECgEIAQAAAA==.Mellk:BAAANQADCgUIBwAAAA==.Melok:BAAANQAECgIIBAAAAA==.Menieblas:BAAANQAECgIIAgAAAA==.Merlindar:BAAANQADCgQIBAAAAA==.Meruru:BAAANQADCgEIAQAAAA==.Messier:BAAANQADCgUIBQAAAA==.Metalmilitia:BAAANQADCgcIEAAAAA==.Metalsickdos:BAAANQAECgEIAQAAAA==.',
Mi='Migajera:BAAANQAECgMIAwABNQAECgYIBwABAAAAAA==.Migui:BAAANQADCgIIAgAAAA==.Mikalau:BAAANQADCgYIBgAAAA==.Milkmom:BAAANQADCgYIBgAAAA==.Millyse:BAAANQADCgYIBgAAAA==.Minno:BAAANQAECgIIAgAAAA==.Mithaly:BAAANQAECgEIAQAAAA==.Miwixds:BAAANQADCgYIBgAAAA==.',
Mo='Moctex:BAAANQADCgYIBgAAAA==.Moguulkhan:BAAANQAECgEIAQAAAA==.Moirainekir:BAAANQADCgYIDAAAAA==.Momongaa:BAAANQAECgEIAQAAAA==.Monako:BAAANQADCgcIBwAAAA==.Monstrenco:BAAANQADCgUIBQABNQAECgQIBgABAAAAAA==.Moobit:BAAANQADCggIDgAAAA==.Moonbay:BAAANQADCgIIAwAAAA==.Moonfyre:BAAANQAECgIIAgAAAA==.Mortrono:BAAANQAECgMIAwAAAA==.Mortís:BAAANQADCgEIAQAAAA==.Motomámi:BAAANQADCgIIAgAAAA==.Moóncry:BAAANQAECgIIAwAAAA==.Moüt:BAAANQADCgEIAQAAAA==.',
Mu='Mugichwan:BAAANQADCgIIAgAAAA==.Muguettzu:BAAANQADCgIIAgAAAA==.Mullicundo:BAAANQADCgcIBwAAAA==.Muthechien:BAAANQADCgUIBQAAAA==.Muydeseado:BAAANQAECgIIAgAAAA==.',
My='Mykeks:BAAANQAECgMIBgAAAA==.Myls:BAAANQADCgIIAgAAAA==.',
['Mä']='Mässo:BAAANQAECgMIBAAAAA==.',
['Mé']='Mén:BAAANQAECgMIAwAAAA==.',
['Mï']='Mïtch:BAAANQADCgQIAQAAAA==.',
['Mö']='Mönkas:BAAANQAECgEIAQAAAA==.',
['Mø']='Møzartt:BAAANQADCgEIAQAAAA==.',
Na='Nadhil:BAAANQADCgQIBAAAAA==.Nanod:BAAANQADCggICwAAAA==.Naonak:BAAANQAECgEIAQAAAA==.Nardàl:BAAANQADCgEIAQAAAA==.Narieda:BAAANQADCgYIBgAAAA==.Narumí:BAAANQAECgEIAQAAAA==.Naturalfiend:BAAANQADCgIIAgAAAA==.Naught:BAAANQAECgMIAwABNQADCgQIBAABAAAAAA==.Naviri:BAAANQADCgMIAwAAAA==.Naxospyro:BAAANQADCgYIDAAAAA==.Naxxoll:BAAANQAECgUICAAAAA==.',
Ne='Necrazar:BAAANQADCgIIAgAAAA==.Necrodex:BAAANQADCgcIDAAAAA==.Necroseil:BAAANQAECgEIAQAAAA==.Neeloc:BAAANQADCgcIBwAAAA==.Nefële:BAAANQAECgIIAgAAAA==.Nelwolf:BAAANQADCgcIDAAAAA==.Nemeroth:BAAANQADCgYICAAAAA==.Neroonn:BAAANQAECgIIAgAAAA==.Netero:BAAANQADCgMIAwAAAA==.Netop:BAAANQAECgEIAQAAAA==.Netspider:BAAANQADCgQIBAAAAA==.Nevitszaid:BAAANQAECgIIAgAAAA==.',
Nh='Nhami:BAAANQADCgEIAQAAAA==.',
Ni='Nibelunge:BAAANQADCgYIDAAAAA==.Nicann:BAAANQADCgYICwAAAA==.Niceflaca:BAAANQADCgUIBgAAAA==.Nicolius:BAAANQADCgcIDAAAAA==.Nicolocho:BAAANQADCgQIBAAAAA==.Nikama:BAAANQAECgEIAQAAAA==.Nikisuga:BAAANQADCgUIAwAAAA==.Nikolaz:BAAANQADCgQIBAAAAA==.Nilhatak:BAAANQAECgIIAgAAAA==.Niloo:BAAANQADCgcIEwAAAA==.Nirviil:BAAANQADCgcIBwAAAA==.',
No='Nocthaelis:BAAANQADCgQIAgAAAA==.Noctiria:BAAANQADCgQIBAAAAA==.Noicanicula:BAAANQADCgEIAQAAAA==.Novacool:BAAANQADCgYIBgAAAA==.Nozghod:BAAANQADCgQIBAAAAA==.',
Ny='Nykstorm:BAAANQADCggICQAAAA==.Nyler:BAAANQADCgcIBwAAAA==.Nyyrikkii:BAAANQADCggIFAAAAA==.',
['Næ']='Næoko:BAAANQAECgMIAwAAAA==.',
['Né']='Némesiss:BAAANQADCgUICQAAAA==.',
['Nø']='Nøstradamuz:BAAANQADCggICAAAAA==.',
Oc='Occultus:BAAANQAECgIIAgAAAA==.',
Od='Odiseuz:BAAANQADCgYIBgAAAA==.',
Og='Oggus:BAAANQADCggIDQAAAA==.',
Ol='Olaznog:BAAANQADCgYIBgAAAA==.Oligisto:BAAANQAECgEIAQAAAA==.',
On='Ondro:BAAANQADCgQIBAAAAA==.Onugem:BAAANQADCgYICgAAAA==.',
Op='Oppenheimar:BAAANQADCgMIAwAAAA==.Opusdiáboli:BAAANQADCgUIBQAAAA==.',
Or='Orangë:BAAANQADCggIDAAAAA==.Orchidd:BAAANQAECgUICAAAAA==.Originalsoul:BAAANQADCgYICwAAAA==.Ortesd:BAAANQADCgYIBgAAAA==.',
Os='Osamdi:BAAANQADCgEIAQAAAA==.Osaurus:BAAANQABCgIIAgAAAA==.',
Ot='Oterö:BAAANQAECgEIAQAAAA==.',
Ou='Ouran:BAAANQADCgMIAwAAAA==.',
Ox='Oxii:BAAANQAECgIIAwAAAA==.',
Oz='Ozlem:BAAANQADCgcIBwAAAA==.Ozzur:BAAANQAECgEIAQAAAA==.',
Pa='Pairo:BAAANQAECgYIDgABNQAECggIDQABAAAAAA==.Pajarraco:BAAANQABCgIIAgAAAA==.Palamba:BAAANQABCgEIAQAAAA==.Palasino:BAAANQADCgYIBwAAAA==.Palatass:BAAANQAECgQIBAAAAA==.Pandefrica:BAAANQADCgYICQABNQAECgQIBAABAAAAAA==.Pandepascuas:BAAANQAECgQIBAAAAA==.Pandochurro:BAAANQADCgMIAwAAAA==.Pandrös:BAAANQAECggIDQAAAA==.Pandurian:BAAANQAECgEIAQAAAA==.Panjitinik:BAAANQADCgUIBQAAAA==.Panndii:BAAANQADCgMIAwAAAA==.Panxing:BAAANQADCgIIAgAAAA==.Papasote:BAAANQADCgcICwAAAA==.Paquin:BAAANQAECgEIAQAAAA==.Parkka:BAAANQADCgYIDgAAAA==.Pauljosue:BAAANQADCgYICQAAAA==.',
Pd='Pdza:BAAANQADCgQIBgAAAA==.',
Pe='Pencilgon:BAAANQADCgUICgAAAA==.Pentauret:BAAANQADCgYIBAAAAA==.Pepitaa:BAAANQAECgQIBAAAAA==.Perrucha:BAAANQADCgEIAQAAAA==.Petricita:BAAANQADCgUIAwAAAA==.Petunia:BAAANQADCgYIBgAAAA==.',
Pi='Picklesacred:BAAANQAECgYICgAAAA==.Pipila:BAAANQADCgQIBAAAAA==.',
Pk='Pkoo:BAAANQADCgYIBgAAAA==.',
Pl='Plac:BAAANQADCgQIBAAAAA==.Plsaleml:BAAANQADCgYICgAAAA==.',
Pm='Pmanar:BAAANQADCgQIBAAAAA==.',
Po='Polárize:BAAANQADCgUIBQAAAA==.Pompoh:BAAANQADCgIIAgAAAA==.Porrita:BAAANQADCgYICgAAAA==.',
Pp='Ppeltauren:BAAANQADCgYICAAAAA==.Pprincesa:BAAANQADCgUICAAAAA==.',
Pr='Prominens:BAAANQADCgYICgAAAA==.',
Py='Pyngon:BAAANQAECgMIBQAAAA==.',
['Pä']='Pädme:BAAANQADCgYICAAAAA==.',
['Pï']='Pïer:BAAANQADCggIDQAAAA==.',
Ql='Qliado:BAAANQADCgQIBAAAAA==.',
Qt='Qtaurentino:BAAANQAECgEIAQAAAA==.',
Qu='Quarantine:BAAANQAECgMIAwAAAA==.Querubinz:BAAANQADCgIIAgAAAA==.Quinasa:BAAANQADCgYIBgAAAA==.Quingg:BAAANQADCgYICQAAAA==.',
['Qñ']='Qñado:BAAANQADCgIIAgAAAA==.',
Ra='Radagas:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Radiance:BAAANQADCgUIBgAAAA==.Raenyx:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Rahemm:BAAANQAECgIIAgAAAA==.Raidenzz:BAAANQAECgIIBAAAAA==.Rakasha:BAAANQADCgQIBAAAAA==.Randester:BAAANQAECgYICgAAAA==.Raphiki:BAAANQADCgQIBwAAAA==.Rawalejandro:BAAANQAECgUIBQAAAA==.',
Re='Reavdud:BAAANQADCgQIBAAAAA==.Rebor:BAAANQADCgEIAQAAAA==.Recogemonte:BAAANQADCgYICAAAAA==.Redjar:BAAANQADCgYIDAAAAA==.Redspirit:BAAANQADCgUIAwAAAA==.Relocosxd:BAAANQADCgEIAQAAAA==.Remyy:BAAANQADCgQIBgABNQADCggICwABAAAAAA==.Reumanic:BAAANQADCgcIGAAAAA==.Rexdraconum:BAAANQAECgEIAQAAAA==.',
Rh='Rhaegn:BAAANQAECgEIAQAAAA==.Rhayzadk:BAAANQAECgQIBQAAAA==.Rhazty:BAAANQADCgUICQAAAA==.Rhea:BAAANQADCgQIBAAAAA==.Rhis:BAAANQADCgUIBQAAAA==.Rhiska:BAAANQADCgYIBgAAAA==.Rhyper:BAAANQAECgQIBAAAAA==.Rhäenyrä:BAAANQADCgUICAAAAA==.',
Ri='Richardriver:BAAANQADCgMIAwAAAA==.Ricketz:BAAANQAECgEIAQAAAA==.Rickygf:BAAANQADCgMIAwAAAA==.Riderless:BAAANQADCggICwAAAA==.Rikuo:BAAANQADCggICAAAAA==.Rinhosizora:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.Riotszen:BAAANQADCgQIBAAAAA==.Rizoman:BAAANQADCgQIBAAAAA==.',
Ro='Roadcm:BAAANQADCgQIBwAAAA==.Robattangas:BAAANQADCgYICQAAAA==.Rockblacki:BAAANQAECgIIAgAAAA==.Rompektrës:BAAANQADCgYIBgAAAA==.Ronstreet:BAAANQADCgEIAQAAAA==.Rotls:BAAANQADCggICQAAAA==.Roweenn:BAAANQADCgQIBAAAAA==.',
Ru='Rugal:BAAANQADCggICAAAAA==.',
['Rá']='Rámzx:BAAANQADCgcIDAAAAA==.',
['Rä']='Räx:BAAANQADCgMIBAAAAA==.',
['Rë']='Rëmbrandt:BAAANQAECgEIAQAAAA==.',
Sa='Sabriluisa:BAAANQADCgcIDAAAAA==.Sacredfire:BAAANQADCgEIAQAAAA==.Saintgermain:BAAANQADCgIIAgAAAA==.Saiphorionis:BAAANQADCgcIBwABNQAECgQIBAABAAAAAA==.Salginteer:BAAANQADCgMIAwAAAA==.Salvi:BAAANQADCgYIBwAAAA==.Samb:BAAANQADCgEIAQAAAA==.Samluck:BAAANQADCgUICQAAAA==.Sammwar:BAAANQAECgMIAwAAAA==.Sanghot:BAAANQADCgIIAgAAAA==.Sangreschwar:BAAANQADCgYIBwAAAA==.Sanguiiniuz:BAAANQADCgMIAwAAAA==.Sanmuertin:BAAANQADCggICgAAAA==.Sanndir:BAAANQAECgIIAgAAAA==.Santified:BAAANQADCgcIBwAAAA==.Sapixi:BAAANQAECgQIBAAAAA==.Sapphi:BAAANQADCgYIBgAAAA==.Sardak:BAAANQADCgYIBgAAAA==.Saria:BAAANQAECgIIAgAAAA==.Sasocas:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Saurona:BAAANQADCgMIAwAAAA==.Saycox:BAAANQAECgMIBAAAAA==.Sayrén:BAAANQAECgEIAQAAAA==.',
Sc='Scanx:BAAANQAECgYICQAAAA==.Scarmesh:BAAANQAECgEIAQAAAA==.',
Se='Sebvz:BAAANQAECgMIAwAAAA==.Seejmet:BAAANQADCgEIAQAAAA==.Seleka:BAAANQADCgYIAgAAAA==.Seneget:BAAANQADCgUIBQAAAA==.Senjib:BAAANQAECgUIBwAAAA==.Serotonin:BAAANQAECgcIDQAAAA==.',
Sh='Shadito:BAAANQADCggIDgAAAA==.Shamanin:BAAANQADCgMIAwAAAA==.Shameco:BAAANQADCgcIBwAAAA==.Shamyto:BAAANQADCgQIAwAAAA==.Shanan:BAAANQADCggIDAAAAA==.Shelox:BAAANQADCgYIBgAAAA==.Shermy:BAAANQADCgYIBgAAAA==.Shibamiyuki:BAAANQADCgMIAwAAAA==.Shigarakicam:BAAANQAECgQIBAAAAA==.Shiinosuke:BAAANQADCgUIBQAAAA==.Shirvallah:BAAANQADCgcIDQAAAA==.Shizaberu:BAAANQADCgUIAgAAAA==.Shmebuloçk:BAAANQADCgUIBQAAAA==.Shurien:BAAANQAECgEIAQAAAA==.Shushinn:BAAANQAECgQIBAAAAA==.Shusui:BAAANQAECgEIAQAAAA==.Shälash:BAAANQADCgQIBAAAAA==.',
Si='Sicarío:BAAANQADCgYICQAAAA==.Sieges:BAAANQADCggIDgAAAA==.Sigrin:BAAANQAECgEIAQABNQAECgcIDAABAAAAAA==.Silverkiller:BAAANQADCgcIDAAAAA==.Simoohayha:BAAANQAECgIIAgAAAA==.',
Sk='Skinhunter:BAAANQADCgYIDAAAAA==.Skylow:BAAANQAECgQIBAAAAA==.Skyréss:BAAANQADCgYIBgAAAA==.',
Sm='Smaul:BAAANQADCgUIBQAAAA==.',
Sn='Snad:BAAANQAECgQIBwABNQAECgYICgABAAAAAA==.',
So='Solaniin:BAAANQAECgMIAwAAAA==.Sommerwalker:BAAANQADCgYIDAAAAA==.Sonadow:BAAANQAECgQIBAAAAA==.Sonbej:BAAANQADCgYIBgABNQAECgUIBwABAAAAAA==.Sopaipiya:BAAANQADCggIDQAAAA==.Soulèater:BAAANQADCgQIBQAAAA==.Soyuno:BAAANQADCgUIBQAAAA==.',
Sp='Spacemage:BAAANQAECgYIBwAAAA==.Spacerm:BAAANQADCgIIAgABNQAECgYIBwABAAAAAA==.Speedyarrow:BAAANQADCgQIBAAAAA==.',
Sr='Srfelix:BAAANQADCgQIBAAAAA==.Srjusticia:BAAANQADCgEIAQAAAA==.Srsquishs:BAAANQADCgIIAgAAAA==.Srwea:BAAANQADCgYIBwAAAA==.',
Ss='Sskiper:BAAANQAECgIIAwAAAA==.',
St='Stalinsky:BAAANQAECgEIAQAAAA==.Staraptor:BAAANQADCggIDQAAAA==.Starkarya:BAAANQAECgEIAQAAAA==.Starsky:BAAANQADCgIIAgAAAA==.Starspawn:BAAANQADCgUIBQAAAA==.Stârlight:BAAANQADCgcIDAAAAA==.',
Su='Sucarita:BAAANQADCgcIDQAAAA==.Suhyokaa:BAAANQADCgYICQAAAA==.Sukaritas:BAAANQADCgYICAAAAA==.Sumäq:BAAANQADCgcIBwAAAA==.Sunfyre:BAAANQADCgEIAQAAAA==.',
Sw='Swindler:BAAANQADCgcIDAAAAA==.',
['Sâ']='Sâcrilegio:BAAANQAECggIDQAAAA==.',
['Sö']='Sökrates:BAAANQAECgIIAgAAAA==.',
Ta='Tahun:BAAANQADCgcICAAAAA==.Tailerx:BAAANQADCgQIBAAAAA==.Takachy:BAAANQADCgYICwAAAA==.Talarøn:BAAANQADCgYICwAAAA==.Talématros:BAAANQABCgIIAgAAAA==.Tasjon:BAAANQAECgQIBgAAAA==.Taster:BAAANQAECgIIAgAAAA==.Taurotoro:BAAANQAECgcIBQAAAA==.Tavitop:BAAANQAECgQIBwAAAA==.Tavop:BAAANQADCggICAABNQAECgQIBwABAAAAAA==.Tavozz:BAAANQAECgEIAQAAAA==.Tayamasan:BAAANQAECgEIAQAAAA==.Tayronisaias:BAAANQADCgQIBAAAAA==.Taysi:BAAANQAECgQIBQAAAA==.Tazg:BAAANQAECgQIBQAAAA==.',
Te='Tendrilion:BAAANQADCgcIDAAAAA==.Tenken:BAAANQADCgQIBAAAAA==.Tephie:BAAANQADCgMIAwAAAA==.Tereaux:BAAANQADCgEIAQAAAA==.Terrik:BAAANQADCggICAAAAA==.',
Th='Thebadboy:BAAANQADCgQICAAAAA==.Theconor:BAAANQADCgQIBAAAAA==.Thedrag:BAAANQAECgMIAwAAAA==.Thelastmønk:BAAANQAECgEIAQAAAA==.Themaga:BAAANQAECgIIAgAAAA==.Thenas:BAAANQADCgEIAQAAAA==.Theraliz:BAAANQADCggIDAAAAA==.Thereaux:BAAANQAECgIIAgAAAA==.Thesentry:BAAANQADCgUIBQAAAA==.Theshami:BAAANQADCgQIBAAAAA==.Theskaa:BAAANQAECgQIBAAAAA==.Thetoxica:BAAANQADCgIIAgAAAA==.Thorflins:BAAANQADCggICQABNQAECgUIBgABAAAAAA==.Thorgrimm:BAAANQADCgYICwAAAA==.Thoritank:BAAANQAECgYIAQAAAA==.Thorjin:BAAANQADCgQIBAAAAA==.Thorkkel:BAAANQADCgYICAAAAA==.Thrandüil:BAAANQADCgYICAAAAA==.Thráiin:BAAANQADCgEIAQAAAA==.Thularion:BAAANQADCgQIBAAAAA==.',
Ti='Timm:BAAANQADCgEIAQAAAA==.Tiramisü:BAAANQADCgYIDAAAAA==.Tiramizu:BAAANQADCgYIDwAAAA==.Tirne:BAAANQADCgUIBQAAAA==.Tirys:BAAANQADCgQIBAAAAA==.',
Tk='Tkiin:BAAANQADCgQIBAAAAA==.',
To='Toball:BAAANQADCgMIAwAAAA==.Tonswors:BAAANQAECgEIAQAAAA==.Toprac:BAAANQADCgMIAwAAAA==.Toravon:BAAANQAECgEIAQAAAA==.Toribianito:BAAANQADCgYIDAAAAA==.',
Tr='Trakkar:BAAANQADCgYICAAAAA==.Traxexd:BAAANQAECgEIAQAAAA==.Treeckko:BAAANQADCgUIBQAAAA==.Trizh:BAAANQAECgQIBAAAAA==.Trollzilla:BAAANQADCgQIBAAAAA==.Trolobayo:BAAANQADCgUIBQAAAA==.Trombe:BAAANQADCgYIBgAAAA==.Troth:BAAANQADCgYIBgAAAA==.Trx:BAAANQADCgQIBAAAAA==.Tryzthano:BAAANQADCgYIBgAAAA==.',
Ts='Tsukichamy:BAAANQAECgIIAgAAAA==.Tsukoni:BAAANQADCgYICwAAAA==.',
Tu='Tumbalino:BAAANQAECgIIAgAAAA==.Turlex:BAAANQADCgMIBAAAAA==.Tusi:BAAANQADCgUICAAAAA==.Tutte:BAAANQADCgMIBAAAAA==.Tutánca:BAAANQADCgUIBQAAAA==.',
Ty='Tyffania:BAAANQADCgYIBgAAAA==.Tyruz:BAAANQAECgcIDQAAAA==.',
['Tá']='Tántalo:BAAANQAECgIIAgABNQAECgIIAwABAAAAAA==.Tásjön:BAAANQAECgMIAwAAAA==.',
['Të']='Tëlchâr:BAAANQAECgIIAgAAAA==.',
['Tý']='Týphon:BAAANQADCggICwAAAA==.',
Uc='Uchida:BAAANQADCgUIAgABNQAECgQIBQABAAAAAA==.',
Uk='Ukog:BAAANQAECgQIBAAAAA==.',
Ul='Ulfgar:BAAANQADCgIIAgAAAA==.Ulkii:BAAANQADCgIIAgAAAA==.',
Un='Unaixo:BAAANQADCgYIBgAAAA==.',
Ur='Uriyael:BAAANQAECgIIAwAAAA==.Ursuur:BAAANQADCgUIBQAAAA==.',
Ut='Uthart:BAAANQADCgMIAwAAAA==.',
Va='Valarwen:BAAANQADCgcIDAAAAA==.Valdreth:BAAANQADCgUIBQAAAA==.Valkenhain:BAAANQADCgYICgAAAA==.Valmonkeyh:BAAANQAECgEIAQAAAA==.Vangonna:BAAANQADCgEIAQAAAA==.Vasheth:BAAANQADCgYICwAAAA==.Vasthorr:BAAANQADCgEIAQAAAA==.',
Ve='Velumbra:BAAANQADCgQIBAAAAA==.Vergasola:BAAANQADCgEIAQAAAA==.Vertrix:BAAANQADCgYIBgAAAA==.Verymelon:BAAANQAECgQIBgAAAA==.Vesperyx:BAAANQAECgEIAgAAAA==.',
Vh='Vhacko:BAAANQADCgYIBgAAAA==.',
Vi='Vianis:BAAANQADCgEIAQAAAA==.Vicaioros:BAAANQADCgYIBwAAAA==.Vichizchami:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.Vichizz:BAAANQAECgEIAQAAAA==.Viciiecal:BAAANQAECgYIDAAAAA==.Viejosabrosö:BAAANQAECgEIAgAAAA==.Violyn:BAAANQADCgMIAwAAAA==.Viszeral:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.Vitoxdary:BAAANQABCgIIAgAAAA==.',
Vo='Volldemort:BAAANQADCgIIAgAAAA==.Volttage:BAAANQADCgUICQAAAA==.Vonjum:BAAANQADCgQIBAAAAA==.',
Vt='Vtor:BAAANQAECgMIBAAAAA==.',
Vu='Vulkan:BAAANQAECgYIBwAAAA==.',
Wa='Wackø:BAAANQADCgQIBAAAAA==.Warorc:BAAANQADCgYICQAAAA==.Warriorgrego:BAAANQADCgUIBQAAAA==.Washimyngo:BAAANQADCgUIBQAAAA==.Watermelo:BAAANQAECgQIBAAAAA==.',
We='Wendhy:BAAANQADCgEIAQAAAA==.',
Wh='Whater:BAAANQADCgIIAgAAAA==.Whesley:BAAANQADCgUICwAAAA==.Whitemanee:BAAANQADCgQIBAABNQADCgcIBwABAAAAAA==.Whushung:BAAANQADCggICAAAAA==.',
Wi='Wildson:BAAANQADCgEIAQAAAA==.Wiraq:BAAANQADCgYIDAAAAA==.Wissepi:BAAANQADCggIDAAAAA==.Witzy:BAAANQADCgUIBQAAAA==.',
Wo='Wolfeligoza:BAAANQAECgQIBAAAAA==.Wolfgeralt:BAAANQADCgIIAgAAAA==.Wolfrain:BAAANQAECgIIAgAAAA==.Wolfsrain:BAAANQADCgYIBwAAAA==.Wounch:BAAANQADCgIIAgABNQADCgQIBQABAAAAAA==.',
Wr='Wrhayza:BAAANQADCgUIBQAAAA==.',
Wu='Wufar:BAAANQADCgQIBAAAAA==.Wurd:BAAANQADCgIIAgAAAA==.',
Wy='Wylgrim:BAAANQADCgYICwABNQAECgYIBgABAAAAAA==.',
['Wâ']='Wâckøø:BAAANQADCgcIBwAAAA==.',
Xa='Xanhk:BAAANQABCgIIAgAAAA==.',
Xe='Xetik:BAAANQADCgMIAwAAAA==.Xey:BAAANQADCgYIBgAAAA==.',
Xi='Xilk:BAAANQADCgQIBAABNQADCgUIBQABAAAAAA==.Xilka:BAAANQADCgUIBQAAAA==.',
Xn='Xnocturne:BAAANQADCgUIBQAAAA==.',
Xt='Xtreem:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.',
Xu='Xubb:BAAANQAECggIDgAAAA==.',
Ya='Yamisan:BAAANQAECgQIBAAAAA==.Yanjun:BAAANQADCgUIBQABNQABCgIIAgABAAAAAA==.Yazaam:BAAANQADCgIIAgAAAA==.',
Yh='Yhina:BAAANQADCggIDgAAAA==.',
Yi='Yinaiteen:BAAANQAECgEIAQAAAA==.',
Yo='Yojoy:BAAANQADCgUIBwAAAA==.Yorunecrum:BAAANQADCgcIDgAAAA==.',
Yr='Yracema:BAAANQADCgYIBwAAAA==.',
['Yâ']='Yâtzüry:BAAANQAECgQIBAAAAA==.',
['Yó']='Yóru:BAAANQADCgUICgAAAA==.',
Za='Zacarias:BAAANQAECgEIAQAAAA==.Zanudar:BAAANQADCgUIBQAAAA==.Zaokum:BAAANQAECgMIAwAAAA==.Zaracatunga:BAAANQADCgIIAgAAAA==.Zarnax:BAAANQADCgMIAwAAAA==.Zarzin:BAAANQADCgcICQAAAA==.',
Ze='Zedreg:BAAANQADCgIIAgAAAA==.Zeeds:BAAANQADCgYIBgAAAA==.Zehelyne:BAAANQAECgUIBgAAAA==.Zekutor:BAAANQAECgMIBAAAAA==.Zengil:BAAANQADCgQIBAAAAA==.Zentetsuken:BAAANQADCgYICAAAAA==.',
Zh='Zhatx:BAAANQADCgIIAgAAAA==.Zhenna:BAAANQAECgQIBAAAAA==.Zhinjoo:BAAANQADCgYICQABNQADCgYICwABAAAAAA==.',
Zi='Zizaa:BAAANQADCgMIAwAAAA==.Zizu:BAAANQADCgUIBgAAAA==.',
Zo='Zomma:BAAANQADCgUIAgAAAA==.',
Zu='Zucc:BAAANQADCgIIAgAAAA==.Zuffx:BAAANQADCgYIBgAAAA==.Zuikaku:BAAANQAECgQIBAAAAA==.Zunjin:BAAANQADCgEIAQAAAA==.',
Zz='Zzeus:BAAANQAECgQIBQAAAA==.',
['Zè']='Zèrò:BAAANQADCgQIBAAAAA==.',
['Zé']='Zéhel:BAAANQADCgYIBgAAAA==.',
['Zø']='Zøuht:BAAANQAECgQIBAAAAA==.Zøus:BAAANQADCggICAAAAA==.',
['Àl']='Àlphà:BAAANQADCggIDQAAAA==.',
['Ál']='Álibéll:BAAANQADCgMIAwAAAA==.',
['Áz']='Ázáél:BAAANQADCgMIAwAAAA==.',
['Âr']='Ârcänë:BAAANQAECgIIAgAAAA==.',
['Äd']='Ädriänä:BAAANQADCgUICAAAAA==.',
['Äs']='Äsmodeus:BAAANQADCgYIBgAAAA==.',
['Él']='Éléná:BAAANQADCgYIBgAAAA==.',
['Ëe']='Ëescanör:BAAANQAECgEIAQAAAA==.',
['Ëx']='Ëxecutor:BAAANQADCgQICAAAAA==.',
['Ðe']='Ðemon:BAAANQADCgQIBAAAAA==.',
['Ör']='Örchid:BAAANQADCgcIDAAAAA==.',
['ßl']='ßlæster:BAAANQADCgYICQAAAA==.',
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
