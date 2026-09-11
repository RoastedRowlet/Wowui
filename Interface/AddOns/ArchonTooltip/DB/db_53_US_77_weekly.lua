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

local lookup = {'Priest-Holy','Unknown-Unknown','Hunter-BeastMastery','Hunter-Marksmanship','Rogue-Assassination','Rogue-Subtlety','Mage-Arcane','Monk-Windwalker','Paladin-Retribution','Monk-Mistweaver','Shaman-Restoration',}
local provider = {region='US',realm='Drakkari',name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aatrøx:BAAANQADCgMIBAAAAA==.',
Ab='Abhigail:BAAANQADCggIDQAAAA==.Absënt:BAAANQADCgEIAQAAAA==.Abuelabetzy:BAAANQADCgIIAgAAAA==.Abueladanger:BAAANQAECgIIAgAAAA==.',
Ac='Ackruts:BAAANQAECgEIAQAAAA==.Ackrüdk:BAAANQADCgcIBwAAAA==.',
Ad='Adirà:BAAANQADCgYICgAAAA==.',
Ae='Aeriallu:BAAANQAECgEIAQAAAA==.Aeroart:BAAANQADCgMIAwAAAA==.',
Ag='Aggy:BAAANQADCgMIAQAAAA==.Agreegor:BAAANQADCgIIAgAAAA==.Agregorr:BAAANQADCgQIBAAAAA==.Agrellor:BAAANQADCgYICQAAAA==.Agrotank:BAAANQAECgYICgAAAA==.Aguafluye:BAAANQADCggICQAAAA==.Agüita:BAAANQAECgQIBAAAAA==.',
Ah='Ahktund:BAAANQADCgYICQAAAA==.',
Ai='Ailhen:BAAANQAECgEIAQAAAA==.Aillyn:BAAANQADCgQIBAAAAA==.Ailuros:BAAANQAECgMIBAAAAA==.',
Ak='Akachete:BAAANQADCgUIBwAAAA==.Akazael:BAAANQADCgYIEAAAAA==.',
Al='Ala:BAAANQADCggIDwAAAA==.Alathra:BAAANQADCgYIBgAAAA==.Albaficar:BAAANQADCgMIBAAAAA==.Aldebbarann:BAAANQADCggIDAAAAA==.Aldrona:BAAANQADCgcIEgAAAA==.Alechiquita:BAAANQADCgQIBAAAAA==.Alejoz:BAAANQADCgUIBQAAAA==.Alessiià:BAAANQADCggIDgAAAA==.Alfy:BAAANQADCgQIBgAAAA==.Aliicea:BAAANQADCgUIBgAAAA==.Alkail:BAAANQADCgUIBQAAAA==.Alliesh:BAAANQAECgIIAgAAAA==.Alquimetal:BAAANQADCggIDQAAAA==.Alrog:BAAANQADCgYICgAAAA==.Alsiel:BAAANQADCgMIAwAAAA==.Alternative:BAAANQADCgYIDAAAAA==.Altharious:BAAANQAECgQIBAAAAA==.Alvarezz:BAAANQADCggICAAAAA==.Alvea:BAAANQADCgYIBwAAAA==.Alvorada:BAAANQADCggIDgAAAA==.',
Am='Ambusoraka:BAAANQADCgYIEQAAAA==.Amor:BAAANQAFFAEIAQAAAA==.Amumu:BAAANQAECgQIBQAAAA==.Amäzonya:BAAANQADCgYICwAAAA==.',
An='Anakiin:BAAANQAECgQIBAAAAA==.Anakin:BAAANQAECgEIAQAAAA==.Analiha:BAAANQAECgUICQAAAA==.Anarin:BAAANQABCgQIBwAAAA==.Anaskmy:BAAANQADCgYIDwAAAA==.Andrewsarkus:BAAANQADCgYIEAAAAA==.Angelboy:BAAANQADCgEIAQAAAA==.Ankthar:BAAANQADCgIIAgAAAA==.Annacleti:BAAANQADCggIBwAAAA==.Annà:BAAANQAECgQIBAAAAA==.Anní:BAAANQAECgEIAQAAAA==.Anoano:BAAANQAECgEIAQAAAA==.Anux:BAAANQADCgQIBgAAAA==.',
Ao='Aoky:BAAANQADCggIDAAAAA==.Aom:BAAANQAECgQIBAAAAA==.Aomesan:BAAANQAECgEIAQAAAA==.',
Ap='Apholö:BAAANQAECgIIAgAAAA==.Apos:BAABNQAECoEcAAIBAAkJaxpTBwD+AgABAAkJaxpTBwD+AgAAAA==.Applevenus:BAAANQADCgUICwAAAA==.Apøløfun:BAAANQADCgMIAwAAAA==.',
Ar='Arandher:BAAANQADCgcIDQAAAA==.Arcanbot:BAAANQADCgIIAgAAAA==.Archeón:BAAANQABCgEIAQAAAA==.Arcrav:BAAANQAECgYICgAAAA==.Arcraxx:BAAANQAECgMIBAAAAA==.Ardoger:BAAANQAECgIIAgAAAA==.Ares:BAAANQAECgEIAQAAAA==.Argelo:BAAANQADCgYIBwAAAA==.Argilac:BAAANQADCgIIAgAAAA==.Ariël:BAAANQABCgQICAAAAA==.Arkhonte:BAAANQAECgUIBwAAAA==.Arphenom:BAAANQAECgQIBAAAAA==.Arry:BAAANQADCgYICQAAAA==.Artemisadn:BAAANQAECgQIBAAAAA==.Artherir:BAAANQAECgcIDQAAAA==.',
As='Ashalanor:BAAANQADCgYIBwAAAA==.Ashelatto:BAAANQADCggIDQABNQAECgUICwACAAAAAA==.Ashirogi:BAAANQADCgcIEAAAAA==.Astralit:BAAANQADCgIIAgAAAA==.Astravia:BAAANQAECgIIAgAAAA==.',
At='Atenasuru:BAAANQADCgEIAQAAAA==.Athandrui:BAAANQADCgYIBgAAAA==.Atheas:BAAANQADCgEIAQAAAA==.Atilaa:BAAANQAECgQIBQABNQAECgcICwACAAAAAA==.',
Au='Aureliuz:BAAANQADCggICAAAAA==.',
Av='Avenaquaker:BAAANQAECggIDgAAAA==.Avethrus:BAAANQADCggIEwAAAA==.Avratz:BAAANQADCgUIBQAAAA==.',
Ay='Ayorya:BAAANQAECgEIAQAAAA==.',
Az='Azaks:BAAANQAECgMIBQAAAA==.Azarelshot:BAAANQAECgQIBAAAAA==.Azarelthas:BAAANQADCgQIBAAAAA==.Azarelux:BAAANQAECgEIAQAAAA==.Azarél:BAAANQADCgQIBAAAAA==.Azgus:BAAANQADCggICAAAAA==.Azidahakas:BAAANQAECgEIAQAAAA==.Azores:BAAANQADCgYICQAAAA==.Azsharael:BAAANQADCgcIDgAAAA==.Azymondiaz:BAAANQAECgUIBgAAAA==.',
Ba='Baballagha:BAAANQADCgMIAwAAAA==.Backup:BAAANQADCgQIBAAAAA==.Badpowell:BAAANQAECgUIBwAAAA==.Baileysade:BAAANQAECgMIAwAAAA==.Bakarass:BAAANQADCgIIAgABNQABCgIIAgACAAAAAA==.Balanky:BAAANQADCgYICgAAAA==.Baliyeh:BAAANQAECgEIAQAAAA==.Balthasar:BAAANQADCgQIBAAAAA==.Banesa:BAAANQADCgMIAwAAAA==.Bathier:BAAANQAECgIIAgAAAA==.Bayula:BAAANQAECgMIAwAAAA==.',
Be='Beelzebù:BAAANQADCgIIAgAAAA==.Beickergamer:BAAANQADCgQIBgAAAA==.Beliin:BAAANQAECggICAAAAA==.Belladonna:BAAANQAECgEIAQAAAA==.Beniøn:BAAANQADCgIIAgAAAA==.Benzott:BAAANQAECgQIBAAAAA==.Berkas:BAAANQADCgMIAwAAAA==.Berserkss:BAAANQADCgMIAwAAAA==.Beyondhope:BAAANQADCggIEAAAAA==.',
Bh='Bhhaal:BAAANQADCgMIAwABNQAECgQIBAACAAAAAA==.Bhhal:BAAANQAECgQIBAAAAA==.',
Bi='Biance:BAAANQAECgMIAwAAAA==.Bicklouw:BAAANQADCggIDQAAAA==.Bigpunisher:BAAANQAECgMIAwAAAA==.Biorns:BAAANQADCggIDAAAAA==.',
Bl='Blackkô:BAAANQAECgUIBwAAAA==.Blackraisond:BAAANQADCgUICwAAAA==.Blakscorpion:BAAANQADCgQIBQAAAA==.Bleiis:BAAANQAECgQIBQAAAA==.Blessrage:BAAANQADCggIDAAAAA==.Bloodoroth:BAAANQAECgEIAQAAAA==.Bloodýx:BAAANQADCgQIBAAAAA==.Blossomder:BAAANQADCgYIBwAAAA==.Blossomy:BAAANQADCgUIBQAAAA==.Bluedh:BAAANQADCgYIDgAAAA==.Bluevoker:BAAANQADCgYICgABNQADCgYIDgACAAAAAA==.',
Bo='Bolg:BAAANQADCgUIBQAAAA==.Bonsaijr:BAAANQADCgcICwAAAA==.Bonsaipro:BAAANQAECgUIBwAAAA==.Botìja:BAAANQADCgUICAAAAA==.',
Br='Brandishs:BAAANQADCggICAAAAA==.Branngus:BAAANQADCgYIEQAAAA==.Breiknar:BAAANQADCgQIBAAAAA==.Brewnation:BAAANQAECgEIAQAAAA==.Brightsad:BAAANQAECgQIBwAAAA==.Brishna:BAAANQAECgQIBAAAAA==.Brunoos:BAAANQADCgYICAAAAA==.Brusiu:BAAANQAECgEIAgAAAA==.',
Bu='Buddy:BAAANQADCgQIBAAAAA==.Bulloflight:BAAANQADCgIIAgABNQADCggICAACAAAAAA==.Bunda:BAAANQAECgYICQAAAA==.',
['Bæ']='Bæ:BAAANQADCgcIBwABNQAECgQIBAACAAAAAA==.',
Ca='Cabecar:BAAANQADCgYIDwAAAA==.Caberdeath:BAAANQADCgIIAgAAAA==.Caberlock:BAAANQAECgQIBQAAAA==.Cadmel:BAAANQADCgcICwABNQAECgEIAQACAAAAAA==.Caesarss:BAAANQADCgIIAwAAAA==.Calancho:BAAANQAECgQIBgAAAA==.Candise:BAAANQAECgUIBwAAAA==.Candlejack:BAAANQADCgUIBQAAAA==.Capkast:BAAANQAECgEIAQAAAA==.Caralock:BAAANQAECgQIBgAAAA==.Carbonxx:BAAANQAECgEIAQAAAA==.Carcass:BAAANQAECgIIAgAAAA==.Carneasa:BAAANQADCggICAAAAA==.Carpinchø:BAAANQAECgQIBQAAAA==.Carrasquinho:BAAANQAECgUIBwAAAA==.Cassiusclay:BAAANQAECgQIBQAAAA==.Cawboy:BAABNQAECoEYAAMDAAkJSCbnAgBzAwADAAgJPCbnAgBzAwAEAAkJLSIKBwADAwAAAA==.Cayuwoky:BAAANQAECgMIAwAAAA==.Cazadorpaska:BAAANQADCgcIDAAAAA==.',
Ce='Cearlink:BAAANQADCgYICwAAAA==.Cel:BAAANQADCgQIBAAAAA==.Celhi:BAAANQADCgUIBgAAAA==.',
Ch='Chamask:BAAANQAECgEIAQAAAA==.Chameeto:BAAANQADCgIIAQABNQAECgUIBwACAAAAAA==.Chamilk:BAAANQADCgYICwAAAA==.Chammiin:BAAANQADCgIIAgAAAA==.Chastia:BAAANQABCgQIBQAAAA==.Chaumita:BAAANQABCgMIAwAAAA==.Chechuna:BAAANQAECgUIBwAAAA==.Chepe:BAAANQADCgYICwAAAA==.Chicobamm:BAAANQADCgEIAQAAAA==.Chiller:BAAANQADCgUIBQAAAA==.Chinxulin:BAAANQADCgcIEgABNQADCggIEAACAAAAAA==.Chocottrenza:BAAANQABCgEIAQAAAA==.Choriser:BAAANQADCgQIBAAAAA==.Chrís:BAAANQADCggIDgAAAA==.Chrïspala:BAAANQAECgQIBAAAAA==.Chuckyseador:BAAANQAECgQIBAAAAA==.Chyrene:BAAANQADCgYIDAABNQAECgQIBAACAAAAAA==.Chöcoboom:BAAANQADCgYIBgAAAA==.',
Ci='Ciagnai:BAAANQADCggIDQAAAA==.Ciircé:BAAANQAECgUICQAAAA==.',
Cl='Claribelle:BAAANQAECgMIBAAAAA==.Classicmurió:BAAANQADCgUIBQAAAA==.Clavakchan:BAAANQADCgQIBAAAAA==.Clenzoil:BAAANQADCgMIAwABNQAECgcICgACAAAAAA==.Cliffs:BAAANQADCgEIAQABNQADCgYICwACAAAAAA==.Clorpi:BAAANQADCgcICwAAAA==.Clëoh:BAAANQAECgMIBAAAAA==.',
Co='Commendatori:BAAANQADCgIIAwAAAA==.Courel:BAAANQAECgEIAQAAAA==.Coyotino:BAAANQADCgQIAgAAAA==.',
Cr='Crimsonclaw:BAAANQADCggIDAAAAA==.Cristthell:BAAANQAECgQIBgAAAA==.Crixis:BAAANQADCgQIBAAAAA==.Crookie:BAAANQADCgEIAQAAAA==.Crossbone:BAAANQADCggICQAAAA==.Crìxus:BAAANQAECgUIBAAAAA==.',
Cu='Cuchicuchl:BAAANQADCgEIAQAAAA==.',
Cy='Cyrsse:BAAANQADCgYIBgAAAA==.Cythorn:BAAANQADCgYIBwAAAA==.Cyttaria:BAAANQADCgUIBQAAAA==.',
['Cä']='Cärola:BAAANQAECgUIBwAAAA==.Cäroly:BAAANQAECgMIAwAAAA==.',
['Cë']='Cëlestial:BAAANQAECgEIAQAAAA==.',
['Cö']='Cönner:BAAANQADCgEIAQAAAA==.',
Da='Dadu:BAAANQADCgQIBAAAAA==.Daemerys:BAAANQADCggIDQAAAA==.Dagasnakë:BAAANQADCgYIBgAAAA==.Dagath:BAAANQAECgIIAgAAAA==.Dagrone:BAAANQAECgEIAQAAAA==.Dagurame:BAAANQABCgQIBgAAAA==.Dailee:BAAANQADCgMIAwAAAA==.Daimøn:BAAANQAECgcIEQAAAA==.Daishiro:BAAANQAECgQIBwAAAA==.Dakanji:BAAANQADCgYIBwAAAA==.Damadodia:BAAANQADCgUIBQAAAA==.Damarihs:BAAANQADCgUIBQAAAA==.Damhián:BAAANQAECgEIAQAAAA==.Danot:BAAANQADCgQIBAAAAA==.Dansy:BAAANQADCgcIBgABNQAECgcICgACAAAAAA==.Dantenamikaz:BAAANQADCgYIBgAAAA==.Darckamage:BAAANQAECgIIAgAAAA==.Dariansa:BAABNQAECoEXAAMFAAkJORYfCwACAgAFAAcJxRQfCwACAgAGAAUJ5g+yGQBsAQABNQADCgYIBgACAAAAAA==.Darkamerica:BAAANQADCgEIAQAAAA==.Darkarus:BAAANQADCgQIBgAAAA==.Darkbelh:BAAANQADCgYIBgAAAA==.Darkelezzard:BAAANQADCgEIAQAAAA==.Darkengel:BAAANQABCgIIAgAAAA==.Darkinghul:BAAANQADCgQIBAAAAA==.Darkrivera:BAAANQAECgIIAgAAAA==.Darre:BAAANQAECgEIAQAAAA==.Darthveil:BAAANQAECgUICAAAAA==.Datsury:BAAANQADCgIIAgABNQAECgYICQACAAAAAA==.Davik:BAAANQADCgYIBwAAAA==.Daxxoz:BAAANQAECgMIBAAAAA==.Dayhunter:BAAANQADCgYIBgAAAA==.Dayix:BAAANQAECgcICwAAAA==.Dayonïs:BAAANQAECgEIAQAAAA==.Dazielth:BAAANQABCgEIAQAAAA==.',
Dd='Ddualipa:BAAANQADCgUIBgAAAA==.',
De='Deathscyth:BAAANQADCggIBQAAAA==.Deceris:BAAANQADCgMIAQAAAA==.Deet:BAAANQADCgMIAwAAAA==.Delsey:BAAANQADCgQICQAAAA==.Demmontaz:BAAANQADCgQIBAAAAA==.Demoní:BAAANQADCgMIBAAAAA==.Demorzz:BAAANQAECgQICgAAAA==.Deoxis:BAAANQADCgYICwAAAA==.Depdep:BAAANQAECgIIAgAAAA==.Depxy:BAAANQAECgEIAQAAAA==.Dessaju:BAAANQAECgQIBAAAAA==.Destia:BAAANQAECgQIBwABNQAECgkJHAABAGsaAA==.Destinyxd:BAABNQAECoEZAAIHAAkJgg70OwBJAgAHAAkJgg70OwBJAgAAAA==.Det:BAAANQAECgUICQAAAA==.Deusgéo:BAAANQADCgEIAQAAAA==.Dexrak:BAAANQAECgIIAwAAAA==.',
Dh='Dheka:BAAANQAECgEIAQAAAA==.Dhexts:BAAANQADCgMIAwAAAA==.',
Di='Diaska:BAAANQADCggICwAAAA==.Diazmerlyn:BAAANQAECgYIBwAAAA==.Diazo:BAAANQADCgUIBgAAAA==.Didragosa:BAAANQADCgIIAgAAAA==.Diego:BAAANQAECgYIAwAAAA==.Diegodruid:BAAANQAECgYIBwAAAA==.Diegolon:BAAANQADCgQICgAAAA==.Diegostorm:BAAANQADCgYIBgAAAA==.Digbingus:BAAANQADCgIIAgAAAA==.Dinaara:BAAANQADCgMIAwAAAA==.Disturbiø:BAAANQADCggICwAAAA==.Dizzys:BAAANQADCgIIAgAAAA==.',
Dj='Djmariof:BAAANQAECgMIBAAAAA==.',
Dk='Dkescanor:BAAANQAECgUIBwAAAA==.Dkingmax:BAAANQADCgQIBgAAAA==.Dklehif:BAAANQADCggICgAAAA==.Dkpibara:BAAANQAECgQIBgAAAA==.Dkraris:BAAANQAECgYIDgAAAA==.Dktazz:BAAANQADCgYIBgAAAA==.Dkzero:BAAANQADCgIIAgAAAA==.',
Do='Doblegador:BAAANQADCggICQAAAA==.Doluis:BAAANQADCgMIAwAAAA==.Doote:BAAANQADCgYIBwAAAA==.Dopadoo:BAAANQAECgIIAgAAAA==.Doscuatro:BAAANQADCgUIBAAAAA==.Doucemort:BAAANQADCgYICAAAAA==.',
Dp='Dpalas:BAAANQADCgUIBQAAAA==.',
Dr='Draconya:BAAANQADCgYICQAAAA==.Draell:BAAANQADCgYIDAAAAA==.Dragenh:BAAANQAECgcIEQAAAA==.Dragonlight:BAAANQAECgIIAgAAAA==.Dragum:BAAANQAECgMIAwABNQAECgQIBQACAAAAAA==.Drakaelis:BAAANQADCgQIBgAAAA==.Drakalath:BAAANQADCgIIAgABNQADCgQIBgACAAAAAA==.Draknus:BAAANQADCggIFgAAAA==.Drakths:BAAANQADCgUIBQAAAA==.Dralchukos:BAAANQADCggIEAAAAA==.Drarry:BAAANQAECgUIBQAAAA==.Draugcr:BAAANQADCggICAAAAA==.Drekzo:BAAANQADCgIIAgAAAA==.Drestroye:BAAANQAECgEIAQAAAA==.Drkemora:BAAANQADCgMIAwAAAA==.Droshko:BAAANQAECgYIBgABNQAECgkJFQAIAD4dAA==.Drudnerr:BAAANQAECgEIAgAAAA==.Druidprince:BAAANQADCgYIBwAAAA==.Dráconiant:BAAANQADCgUICgABNQAECgQIBQACAAAAAA==.',
Du='Duduboyito:BAAANQAECgIIAgAAAA==.Duurootar:BAAANQAECgEIAQAAAA==.',
Dw='Dwarfone:BAAANQADCggIEgAAAA==.',
Dz='Dzul:BAAANQADCgIIAgAAAA==.',
['Dä']='Därkässäsin:BAAANQADCgMIAwAAAA==.',
['Dø']='Dønpikin:BAAANQADCgUICQAAAA==.',
['Dü']='Dürtz:BAAANQAECgEIAgAAAA==.',
Eb='Ebanel:BAAANQADCggIEAAAAA==.',
Ec='Eclipsa:BAAANQAECgQIBwAAAA==.Ecofrio:BAAANQADCgcICgAAAA==.',
Ed='Edark:BAAANQAECgEIAQAAAA==.Edusp:BAAANQAECgQIBAAAAA==.',
Eg='Egoca:BAAANQADCgEIAQAAAA==.',
Ei='Eiko:BAAANQADCggIEAAAAA==.',
El='Elentiyaa:BAAANQAECgEIAQAAAA==.Eleonoret:BAAANQAECgEIAQAAAA==.Elguskullu:BAAANQAECgIIAgAAAA==.Elidhana:BAAANQABCgYICQAAAA==.Elk:BAAANQADCggIDQAAAA==.Elkie:BAAANQAECgQIBAAAAA==.Ellinar:BAAANQAECgQIBAAAAA==.Elohisa:BAAANQADCgYICwAAAA==.Elpolloloco:BAAANQADCgUIBQAAAA==.Elpoyoloco:BAAANQAECgQIBAAAAA==.Elrr:BAAANQABCgQIBAAAAA==.Eltormetias:BAAANQAECgEIAQAAAA==.Eltuerton:BAAANQADCgQIBAAAAA==.Elviraa:BAAANQADCgMIAwAAAA==.Elxadal:BAAANQAECgIIAgAAAA==.Elxochanguas:BAAANQAECgIIAgAAAA==.Elyndræ:BAAANQADCgYICAAAAA==.',
Em='Emersyn:BAAANQADCgYICgAAAA==.Empanizado:BAAANQADCgQIBgAAAA==.',
En='Enror:BAAANQADCgQIBAAAAA==.Enzaro:BAAANQADCgYICQAAAA==.',
Er='Erectho:BAAANQADCgYIBgAAAA==.Erlang:BAAANQAECgQIBQAAAA==.Ernendil:BAAANQADCgUIBQAAAA==.',
Es='Escannor:BAAANQADCgUIBQAAAA==.Escanorsama:BAAANQADCgMIAQAAAA==.Esnad:BAAANQAECgcICgAAAA==.',
Ev='Evilkerzel:BAAANQAECgQIBQAAAA==.Evillis:BAAANQAECgIIAgAAAA==.Eviltyra:BAAANQAECgcICwAAAA==.Evissa:BAAANQAECgMIBAAAAA==.',
Ex='Exado:BAAANQADCgYIBgABNQADCggICgACAAAAAA==.Explicits:BAAANQAECgQIBQAAAA==.',
Ez='Ezeqeel:BAAANQAECgEIAQAAAA==.',
['Eí']='Eísén:BAAANQADCgcIDAAAAA==.',
['Eö']='Eönar:BAAANQAECgQIAwAAAA==.',
Fa='Fakkir:BAAANQAECgMIBQAAAA==.Farat:BAAANQABCgEIAQAAAA==.Fayyisaa:BAAANQAECgIIAgAAAA==.',
Fb='Fbk:BAAANQADCgEIAQAAAA==.',
Fe='Felicie:BAAANQADCgYICgAAAA==.Ferchudoto:BAAANQADCgEIAQAAAA==.Fexmen:BAAANQAECgEIAQAAAA==.Feéling:BAAANQAECgEIAQAAAA==.',
Fh='Fherty:BAAANQAECgUIBgAAAA==.Fhxhs:BAAANQADCgYIEgAAAA==.',
Fi='Fibi:BAAANQADCgQIBAAAAA==.Finheas:BAAANQADCgYICwAAAA==.Fionnæ:BAAANQADCgcIEAAAAA==.Firana:BAAANQADCgQIBAABNQADCgQIBAACAAAAAA==.',
Fk='Fkrsrs:BAAANQAECgUICAAAAA==.',
Fl='Flacapala:BAAANQAECgMIBgAAAA==.Flashoflight:BAAANQADCgEIAQAAAA==.',
Fo='Fofitóó:BAAANQADCgEIAQAAAA==.Forasstero:BAAANQADCggICAAAAA==.Forkan:BAAANQADCgYIAgAAAA==.',
Fr='Frisad:BAAANQAECgMIAwAAAA==.Frostrike:BAAANQADCgUIBQAAAA==.',
Fu='Fullx:BAAANQADCgQIBgAAAA==.Furrynn:BAAANQADCgYIDgAAAA==.',
['Fä']='Fäenor:BAAANQAECgIIAgAAAA==.',
Ga='Gabydit:BAAANQAECgYICAAAAA==.Gadito:BAAANQAECgcIDgABNQAECgkJGAAJAEsgAA==.Galadhriell:BAAANQAECgUIBAAAAA==.Galletitauwu:BAAANQADCgEIAQAAAA==.Galädriel:BAAANQAECgMIBQAAAA==.Ganttzz:BAAANQAECgQIBAAAAA==.Gardner:BAAANQABCgYICgAAAA==.Garkencio:BAAANQAECgEIAQAAAA==.Garrok:BAAANQADCgcIDAAAAA==.Gaspar:BAAANQAECgIIAgAAAA==.Gathodaimon:BAAANQAECgIIAgAAAA==.Gatyto:BAAANQAECgIIAgAAAA==.Gaudy:BAAANQADCgcIDQAAAA==.Gazi:BAAANQAECgIIAgAAAA==.',
Ge='Gemíta:BAAANQAECgIIAgAAAA==.Gerc:BAAANQAECgQIBQAAAA==.',
Gi='Giovano:BAAANQADCgQIBAAAAA==.Giur:BAAANQAECgMIBAAAAA==.',
Gl='Glimdar:BAAANQADCgcIEAAAAA==.Glopis:BAAANQADCgIIAgAAAA==.Glørious:BAAANQAECgIIAgAAAA==.',
Gn='Gnomecholas:BAAANQADCggIDgAAAA==.',
Go='Goge:BAAANQAECgEIAQAAAA==.Gogeta:BAAANQADCgYIBgAAAA==.Gokuderah:BAAANQAECgEIAQAAAA==.Goloh:BAAANQAECgIIAQAAAA==.Gooddrag:BAAANQABCgIIAgAAAA==.Goodlike:BAAANQAECgEIAQAAAA==.Gordeewa:BAAANQAECgIIAgAAAA==.Gordinho:BAAANQAECgUIBgAAAA==.Gordochispas:BAAANQAECgYICAAAAA==.Gothdita:BAAANQAECgQIBQAAAA==.Gothmog:BAAANQAECgMIAwAAAA==.',
Gr='Grahas:BAAANQADCgEIAQAAAA==.Grasa:BAAANQADCgcIBwAAAA==.Grondy:BAAANQAECgUICAAAAA==.Grthpaly:BAAANQADCgUIBQAAAA==.Grïsh:BAAANQAECgYIBwAAAA==.',
Gu='Guarmist:BAAANQADCgMIAwAAAA==.Guaztarger:BAAANQADCgQIBAAAAA==.Gufren:BAAANQADCggICAAAAA==.Guiselle:BAAANQAECgMIBAAAAA==.Gusfringk:BAAANQADCgYICgAAAA==.Gustavh:BAAANQADCgMIAwAAAA==.Guxue:BAAANQADCgYIDAAAAA==.',
Gw='Gwendevere:BAAANQADCgYIBwAAAA==.',
Gz='Gzlock:BAAANQADCgQIBAAAAA==.',
Ha='Haethos:BAAANQAECgEIAQAAAA==.Hajimi:BAAANQAECgQIBgABNQAECgYICAACAAAAAA==.Hakeshï:BAAANQADCgYIBgAAAA==.Halrinak:BAAANQADCggIDQAAAA==.Hammernegro:BAAANQADCgUIBQAAAA==.Hanito:BAAANQAECgEIAgAAAA==.Happycherry:BAAANQAECgQIBwAAAA==.Harguenn:BAAANQADCgYIBgAAAA==.Harutox:BAAANQADCgMIAwAAAA==.Hashem:BAAANQAECgQIBQAAAA==.Hattzune:BAAANQAECgMIAwAAAA==.Hawkay:BAAANQADCgYIDwAAAA==.Haz:BAAANQAECgUIBQAAAA==.Hazy:BAAANQAECgYIBwAAAA==.',
He='Healignacio:BAAANQADCgUIBQAAAA==.Hecatomb:BAAANQADCgcIBwAAAA==.Hedblink:BAAANQADCgYICQAAAA==.Hefestor:BAAANQADCgEIAQAAAA==.Heffy:BAAANQADCgYIDAABNQAECgQIBQACAAAAAA==.Heffyd:BAAANQADCgUIBQABNQAECgQIBQACAAAAAA==.Heffyx:BAAANQAECgQIBQAAAA==.Hekan:BAAANQAECgQIBgAAAA==.Helsiing:BAAANQADCgYICQAAAA==.Hernagorax:BAAANQADCgIIAgAAAA==.',
Hi='Hierbatero:BAAANQADCgQIAQAAAA==.Hiperioon:BAAANQADCgcICgAAAA==.Hisdra:BAAANQAECgIIAgAAAA==.',
Ho='Holoyuta:BAAANQAECgYIDwAAAA==.Holoziru:BAAANQAECgUIBgAAAA==.Hommerjay:BAAANQAECgcICgAAAA==.Houdax:BAAANQADCgIIAgAAAA==.',
Hu='Hukun:BAAANQADCgMIAwAAAA==.Hunhao:BAAANQADCgUIBgAAAA==.Huntwok:BAAANQADCgYIBgAAAA==.Hurona:BAAANQADCgQIBAAAAA==.Hurun:BAAANQAECgIIAgAAAA==.',
Hy='Hyiakki:BAAANQADCgMIAwABNQAECgEIAQACAAAAAA==.Hyiâkki:BAAANQAECgEIAQAAAA==.',
['Hí']='Hínatax:BAAANQADCgcIDQAAAA==.',
['Hù']='Hùnterkiller:BAAANQAECgIIAgAAAA==.',
Ia='Iamtenito:BAAANQAECgcIBgAAAA==.',
Ic='Icarusa:BAAANQADCgUIBwAAAA==.Iceblockirl:BAAANQADCgYIBgAAAA==.',
Ig='Igrisl:BAAANQADCgcICQAAAA==.',
Ik='Ikarik:BAAANQADCgYICgABNQAECgQIBgACAAAAAA==.',
Il='Illidaris:BAAANQADCgUIBQAAAA==.',
Im='Imac:BAAANQAECgEIAQAAAA==.Imelda:BAAANQADCgMIAwAAAA==.Imnictus:BAAANQAECgUIBwAAAA==.Impstorm:BAAANQAECgQIBwAAAA==.Imsama:BAAANQADCgUIDgAAAA==.Imthor:BAAANQADCgEIAQAAAA==.Imzeen:BAAANQAECgEIAQAAAA==.',
In='Inguz:BAAANQADCggICAAAAA==.Inmörthal:BAAANQADCgUIBQABNQADCgcICwACAAAAAA==.Innari:BAAANQAECgIIAwAAAA==.Inquisicion:BAAANQAECgEIAQAAAA==.Invitro:BAAANQADCgEIAQAAAA==.',
Ir='Irenebelse:BAAANQAECgQIBQAAAA==.Ironfaith:BAAANQAECgQICAAAAA==.',
Is='Issoku:BAAANQADCgEIAQABNQAECgUICAACAAAAAA==.',
It='Itachila:BAAANQADCgQIBAAAAA==.',
Ja='Jacal:BAAANQADCgUIBQAAAA==.Jackstick:BAAANQAECgMIBAAAAA==.Jair:BAAANQAECgYICgAAAA==.Janetla:BAAANQADCgcICwAAAA==.Jarred:BAAANQADCgEIAQAAAA==.Javiëra:BAAANQAECgIIAgAAAA==.',
Je='Jealfredó:BAAANQADCgQIAwAAAA==.Jelou:BAAANQADCgIIAgAAAA==.',
Jh='Jhirek:BAAANQADCgUIBQAAAA==.',
Ji='Jidenm:BAAANQAECgUIBgAAAA==.Jidrix:BAAANQADCgQIBQABNQAECgQIBAACAAAAAA==.Jinath:BAAANQADCgMIAwABNQADCgYICQACAAAAAA==.Jingu:BAAANQADCgQIBQAAAA==.Jinjer:BAAANQAECgQIBAAAAA==.',
Jk='Jkjn:BAAANQADCgMIAwAAAA==.Jkllein:BAAANQAECgMIAwAAAA==.',
Jl='Jlink:BAAANQAECgIIAgAAAA==.',
Jo='Joms:BAAANQADCgMIBQAAAA==.Jonhar:BAAANQADCgYIBgAAAA==.Josemadrazo:BAAANQAECgEIAQAAAA==.Joswar:BAAANQAECgMIAwAAAA==.Joudalf:BAAANQADCgUICQAAAA==.',
Ju='Juanky:BAAANQADCgUIBQAAAA==.Juanow:BAAANQAECgIIAgAAAA==.Juliux:BAAANQADCgYIBwAAAA==.Juraexanime:BAAANQAECgIIAgAAAA==.Jurasickhan:BAAANQADCgMIAwAAAA==.Jurgën:BAAANQADCgIIAgAAAA==.',
Jv='Jvgg:BAAANQADCgUIAgAAAA==.',
Jw='Jwickk:BAAANQADCgYIBgAAAA==.',
Ka='Kaano:BAAANQADCgcICAAAAA==.Kachex:BAAANQADCgIIAgAAAA==.Kachupinsito:BAAANQAECgYIDAAAAA==.Kageru:BAAANQADCgcIDwAAAA==.Kaguire:BAAANQADCggIEAAAAA==.Kahula:BAAANQABCgQIAgAAAA==.Kaiidari:BAAANQAECgQIBQAAAA==.Kailink:BAAANQADCgcIBwAAAA==.Kaithar:BAAANQABCgIIAQAAAA==.Kalerin:BAAANQADCgUIBwABNQADCgcIEAACAAAAAA==.Kaliell:BAAANQADCgQIBAAAAA==.Kalithas:BAAANQAECgIIAgAAAA==.Kalixx:BAAANQADCgUIBQAAAA==.Kaltiro:BAAANQADCgIIAgAAAA==.Kaltozz:BAAANQAECgYICAAAAA==.Kalyza:BAAANQADCggICgAAAA==.Kamakawiwo:BAAANQADCgMIAwAAAA==.Kamuss:BAAANQAECgYICgAAAA==.Kaníma:BAAANQADCggIEwAAAA==.Karmelin:BAAANQADCgUIAwAAAA==.Kazuprime:BAAANQAECgUIBwAAAA==.Kaøri:BAAANQAECgQIBwAAAA==.',
Ke='Kelethir:BAAANQAECgEIAQAAAA==.Kelsir:BAAANQAECgIIAgAAAA==.Keltzhar:BAAANQAECgIIAgAAAA==.Kenia:BAAANQAECgIIAgAAAA==.Kerarthas:BAAANQADCgEIAQAAAA==.Kezhu:BAAANQAECgMIBAAAAA==.',
Kh='Khamhaleaga:BAAANQADCgUIBwAAAA==.Khelly:BAAANQAECgIIAgAAAA==.Khhalo:BAAANQAECgIIAwAAAA==.Khime:BAAANQADCgUICQAAAA==.Khurisu:BAAANQADCgIIAgAAAA==.Khurysta:BAAANQAECgMIBAAAAA==.Khäelth:BAAANQADCggIDAAAAA==.',
Ki='Kienesmarco:BAAANQADCgYIBgAAAA==.Kiillswitch:BAAANQABCgYICQAAAA==.Kintos:BAAANQADCgQIBAAAAA==.Kipura:BAAANQADCgIIAgAAAA==.Kiriotosu:BAAANQADCgYIBgAAAA==.Kittyfer:BAAANQADCggICgAAAA==.',
Kj='Kjal:BAAANQADCggICAAAAA==.',
Kl='Klounte:BAAANQADCgIIAgAAAA==.',
Ko='Koblai:BAAANQADCgcIBwAAAA==.Kojiro:BAAANQADCgYICwAAAA==.Koller:BAAANQADCgMIAwAAAA==.Konha:BAAANQAECgQIBQAAAA==.Koriente:BAAANQAECgQIBgAAAA==.Korlat:BAAANQADCgEIAQAAAA==.Koruchi:BAAANQADCgQIBAAAAA==.Koshkauwu:BAAANQADCgEIAQAAAA==.',
Kr='Kratzio:BAAANQADCggIDgAAAA==.Kresty:BAAANQADCggIEwAAAA==.Kronio:BAAANQAECgIIAgAAAA==.Krystaluwu:BAAANQADCgQIBgAAAA==.',
Ku='Kukuman:BAAANQADCgEIAQAAAA==.Kungfuupanda:BAAANQADCgIIAgAAAA==.Kunlaoxd:BAAANQADCgUIBwAAAA==.Kuroyamiwow:BAAANQAECgIIAgAAAA==.Kuvira:BAAANQADCgYIEAAAAA==.',
Kv='Kv:BAAANQADCgQIAwAAAA==.Kvicha:BAAANQAECgIIAgAAAA==.Kvinprince:BAAANQADCgEIAQABNQADCgYIBwACAAAAAA==.Kvolthe:BAAANQAECgMIBAAAAA==.',
Ky='Kyorî:BAAANQADCgMIAwAAAA==.Kyranthrax:BAAANQADCggIEAAAAA==.Kyraéth:BAAANQADCgYIDAAAAA==.',
['Kí']='Kíller:BAAANQADCgYIBgAAAA==.',
['Kø']='Køa:BAAANQADCgYICQAAAA==.',
La='Labambaa:BAAANQAECgQIBQAAAA==.Laboons:BAAANQADCgEIAQAAAA==.Lacuba:BAAANQADCgIIAgAAAA==.Ladroga:BAAANQADCgYICAAAAA==.Laeroth:BAAANQABCgMIAgAAAA==.Lafieroski:BAAANQADCgIIBAAAAA==.Lafoxi:BAAANQADCgQIBAABNQADCgUIBwACAAAAAA==.Laheeja:BAAANQADCgUIBQAAAA==.Laidlywormpa:BAAANQAECgEIAQAAAA==.Lakungfusión:BAAANQADCgYICgAAAA==.Lardelx:BAAANQADCgcIDQAAAA==.Lastorc:BAAANQADCgUIBgAAAA==.Lastwärrior:BAAANQAECgcICwAAAA==.Lavacabacana:BAAANQAECgMIAwAAAA==.Lavalock:BAAANQADCgYIBgAAAA==.',
Le='Leamblue:BAAANQADCgYICQAAAA==.Lebombas:BAAANQAECgIIAgAAAA==.Lechushm:BAAANQADCgIIAgAAAA==.Leiah:BAAANQADCgQICAAAAA==.Lemuria:BAAANQADCgQIBgAAAA==.Lená:BAAANQADCggICAAAAA==.Lenøre:BAAANQAECgEIAQAAAA==.Leomonx:BAAANQAECgMIBAABNQAECgYIBwACAAAAAA==.Letu:BAAANQADCgMIAwAAAA==.Letø:BAAANQADCgcIDAAAAA==.Leviastús:BAAANQAECgQIBQAAAA==.Leviattán:BAAANQADCgEIAQAAAA==.Leömön:BAAANQAECgQIBAABNQAECgYIBwACAAAAAA==.',
Lh='Lhukan:BAAANQAECgUICAAAAA==.Lhura:BAAANQAECgEIAQAAAA==.',
Li='Liacachetona:BAAANQADCgQIBAAAAA==.Libi:BAAANQADCgIIAgAAAA==.Lichpaw:BAAANQADCgQIBAAAAA==.Lightjandra:BAAANQADCgYIDgAAAA==.Lilea:BAAANQAECgIIAwAAAA==.Lilithuchuan:BAAANQADCgYIBgAAAA==.Lillean:BAAANQADCgIIAgAAAA==.Limcross:BAAANQADCgUIBwAAAA==.Limeña:BAAANQADCgQIBAAAAA==.Lindabb:BAAANQADCgQIBAAAAA==.Lindurita:BAAANQADCgEIAQAAAA==.Linkz:BAAANQADCggIDgAAAA==.Linnea:BAAANQADCgQIBAABNQADCggIDgACAAAAAA==.Lios:BAAANQAECgEIAQAAAA==.Lipus:BAAANQAECgIIAgAAAA==.Litts:BAAANQADCgQIBQAAAA==.',
Lo='Lobillodk:BAAANQAECgQIBAABNQAECgQIBQACAAAAAA==.Lochupontero:BAAANQADCgEIAQAAAA==.Lokani:BAAANQADCgcIBwAAAA==.Lostpower:BAAANQAECgQIBAAAAA==.Lothbruner:BAAANQADCggICAAAAA==.',
Lt='Lt:BAAANQADCgUIBAAAAA==.',
Lu='Lubb:BAAANQADCggICgAAAA==.Lubye:BAAANQADCgEIAQAAAA==.Lucandlere:BAAANQADCgQIBAAAAA==.Lucret:BAAANQADCgMIAwAAAA==.Luggubre:BAAANQAECgYIDwAAAA==.Luisaacg:BAAANQADCgMIAwAAAA==.Luisitoxx:BAAANQAECgEIAQAAAA==.Lumis:BAAANQAECgMIAwAAAA==.Lunainverse:BAAANQADCgQIBAAAAA==.Lupùs:BAAANQADCgYIBgABNQADCggICgACAAAAAA==.Lusitanian:BAAANQAECgUIBQAAAA==.Luxiien:BAAANQAECgQIBwAAAA==.',
Lx='Lxa:BAAANQADCgcICwAAAA==.Lxmrcheesexl:BAAANQAECgQIBwAAAA==.',
['Lá']='Lást:BAAANQAECgQIBAAAAA==.',
['Lé']='Léonel:BAAANQAECgMIAwAAAA==.',
['Lë']='Lëomon:BAAANQAECgYIBwAAAA==.',
['Lì']='Lìlíth:BAAANQAECgEIAgAAAA==.',
['Lú']='Lúmiere:BAAANQADCgcIDgAAAA==.Lúriza:BAAANQAECgEIAQAAAA==.Lúthién:BAAANQAECgEIAQAAAA==.',
Ma='Mabilomi:BAAANQADCgUIBgAAAA==.Macdonal:BAAANQADCggIDgAAAA==.Macklein:BAAANQADCggICgAAAA==.Madhunt:BAAANQADCggICAAAAA==.Maffo:BAAANQAECgIIAgAAAA==.Magikall:BAAANQADCgcIDQAAAA==.Makatraka:BAAANQADCgQIBAAAAA==.Makodra:BAAANQAECgUIBwAAAA==.Malakaí:BAAANQADCgYIDgAAAA==.Maldrux:BAAANQAECgUIBgAAAA==.Malextrasa:BAAANQAECgcIEAAAAA==.Malkrim:BAAANQAECgQIBAAAAA==.Malènia:BAAANQADCgYIBgAAAA==.Manamonk:BAAANQADCgYICgAAAA==.Manatz:BAAANQADCgYIBgABNQAECgEIAQACAAAAAA==.Mandredivh:BAAANQADCggIEgAAAA==.Mannat:BAAANQAECgEIAQAAAA==.Margrace:BAAANQADCggIDgAAAA==.Margys:BAAANQADCgYICQABNQAECgMIBQACAAAAAA==.Maripxd:BAAANQADCgIIAwAAAA==.Mariána:BAAANQAECgEIAQAAAA==.Marlenor:BAAANQAECgEIAQAAAA==.Marusita:BAAANQADCgQIBAAAAA==.Matusalix:BAAANQADCgUICwAAAA==.Maynard:BAAANQADCgcIDwABNQAECgcIEAACAAAAAA==.',
Md='Mddemon:BAAANQAECgEIAQABNQAECgcICAACAAAAAA==.Mdlock:BAAANQAECgEIAQABNQAECgcICAACAAAAAA==.Mdmague:BAAANQAECgcICAAAAA==.',
Me='Medaly:BAAANQAECgUIBgAAAA==.Mediff:BAAANQAECgEIAQAAAA==.Meinxia:BAAANQAECgIIAgAAAA==.Melhí:BAAANQADCgQICAABNQAECgcIEQACAAAAAA==.Melianor:BAAANQAECgEIAQAAAA==.Mellk:BAAANQAECgQIBAAAAA==.Melok:BAAANQAECgUICQAAAA==.Menieblas:BAAANQAECgMIBQAAAA==.Merlindar:BAAANQADCgQIBAAAAA==.Meruru:BAAANQAECgEIAQAAAA==.Messier:BAAANQADCgUIBQAAAA==.Metalmilitia:BAAANQADCggIEQAAAA==.Metalsickdos:BAAANQAECgEIAQAAAA==.',
Mi='Migajera:BAAANQAECgUIBwABNQAFFAEIAQACAAAAAA==.Migatteluca:BAAANQADCgMIAwABNQAECgUICwACAAAAAA==.Migui:BAAANQADCgYICAAAAA==.Mikalau:BAAANQADCggIDgAAAA==.Mikku:BAAANQADCgIIAgAAAA==.Milkmom:BAAANQADCgYIBgAAAA==.Millyse:BAAANQADCgYIBgAAAA==.Minichoco:BAAANQAECgMIAwABNQAECgUIBwACAAAAAA==.Minno:BAAANQAECgQIBgAAAA==.Miréi:BAAANQADCgEIAQAAAA==.Mithaly:BAAANQAECgQIBQAAAA==.Miwixds:BAAANQADCggIDgAAAA==.',
Mo='Moctecuzuma:BAAANQADCgEIAQAAAA==.Moctex:BAAANQADCgYIBgAAAA==.Moguulkhan:BAAANQAECgEIAQAAAA==.Moirainekir:BAAANQAECgMIAwAAAA==.Momongaa:BAAANQAECgEIAgAAAA==.Monako:BAAANQAECgQIBAAAAA==.Monstrenco:BAAANQADCgUIBQABNQAECgYIDAACAAAAAA==.Monthana:BAAANQAECgEIAQAAAA==.Moobit:BAAANQAECgQIBAAAAA==.Moonbay:BAAANQADCgMIBAAAAA==.Moonfyre:BAAANQAECgQIBgAAAA==.Mortrono:BAAANQAECgUIBwAAAA==.Mortís:BAAANQADCgEIAQAAAA==.Motomámi:BAAANQADCgIIAgAAAA==.Moóncry:BAAANQAECgQIBwAAAA==.Moüt:BAAANQADCgEIAQAAAA==.',
Ms='Msoujiro:BAAANQAECgIIAgAAAA==.',
Mu='Mugichwan:BAAANQADCgYICQAAAA==.Muguettzu:BAAANQADCgIIAgAAAA==.Mullicundo:BAAANQADCgcIBwAAAA==.Muthechien:BAAANQADCgcIDAAAAA==.Muydeseado:BAAANQAECgUIBwAAAA==.',
My='Mykeks:BAAANQAECgMICQAAAA==.Myls:BAAANQADCgIIAgAAAA==.',
['Mä']='Mässo:BAAANQAECgYICgAAAA==.',
['Mé']='Mén:BAAANQAECgQIBwAAAA==.',
['Mï']='Mïtch:BAAANQAECgEIAQAAAA==.',
['Mö']='Mönkas:BAAANQAECgMIAwAAAA==.',
['Mø']='Møzartt:BAAANQADCgEIAQAAAA==.',
Na='Nadhil:BAAANQADCgQIBAAAAA==.Nadyia:BAAANQABCgMIAwAAAA==.Nanod:BAAANQADCggICwAAAA==.Naonak:BAAANQAECgQIBQAAAA==.Nardàl:BAAANQADCgEIAQAAAA==.Narieda:BAAANQAECgIIAgAAAA==.Narumí:BAAANQAECgQIBQAAAA==.Naturalfiend:BAAANQAECgEIAQAAAA==.Naught:BAAANQAECgQIBwABNQADCgUICQACAAAAAA==.Naviri:BAAANQADCgMIAwAAAA==.Naxospyro:BAAANQAECgMIAwAAAA==.Naxxoll:BAAANQAECgcIDwAAAA==.',
Ne='Necrazar:BAAANQADCgIIAgAAAA==.Necrodex:BAAANQAECgMIAwAAAA==.Necroseil:BAAANQAECgEIAQAAAA==.Neeloc:BAAANQAECgMIAwAAAA==.Nefële:BAAANQAECgUIBwAAAA==.Nelwolf:BAAANQAECgIIAgAAAA==.Nemeroth:BAAANQADCgYICAAAAA==.Nenéx:BAAANQADCgMIAwABNQAECgQIBwACAAAAAA==.Neroonn:BAAANQAECgQIBQAAAA==.Nesbitsan:BAAANQADCggICQAAAA==.Netero:BAAANQADCgMIAwAAAA==.Netop:BAAANQAECgQIBQAAAA==.Netspider:BAAANQADCgQIBAAAAA==.Nevitszaid:BAAANQAECgUIBwAAAA==.',
Nh='Nhami:BAAANQADCgEIAQAAAA==.',
Ni='Nibelunge:BAAANQADCgYIEgAAAA==.Nicann:BAAANQADCggIGgAAAA==.Niceflaca:BAAANQADCgcIEAAAAA==.Nicolius:BAAANQADCgcIDAAAAA==.Nicolocho:BAAANQADCgUIBQAAAA==.Nikama:BAAANQAECgQIBQAAAA==.Nikisuga:BAAANQADCgUIAwAAAA==.Nikolaz:BAAANQAECgEIAQAAAA==.Nilhatak:BAAANQAECgQIBgAAAA==.Niloo:BAAANQADCgcIGgAAAA==.Nirviil:BAAANQADCgcIBwAAAA==.',
No='Nocthaelis:BAAANQADCgQIAgAAAA==.Noctiria:BAAANQADCgQIBAAAAA==.Nogarmonia:BAAANQAECgEIAQAAAA==.Noicanicula:BAAANQADCgEIAQAAAA==.Novacool:BAAANQADCgYIBgAAAA==.Nozghod:BAAANQADCgQIBAAAAA==.',
Ny='Nykstorm:BAAANQAECgQIAwAAAA==.Nyler:BAAANQADCgcIBwAAAA==.Nyyrikkii:BAAANQAECgMIAwAAAA==.',
['Næ']='Næoko:BAAANQAECgMIAwAAAA==.',
['Né']='Némesiss:BAAANQADCgcICwAAAA==.',
['Nø']='Nøstradamuz:BAAANQADCggIDwAAAA==.',
Oc='Occultus:BAAANQAECgUIBwAAAA==.',
Od='Odelyx:BAAANQADCgEIAQAAAA==.Odiseuz:BAAANQADCgYIBgAAAA==.',
Of='Offsham:BAAANQAECgIIAgABNQAECgQIBAACAAAAAA==.',
Og='Oggus:BAAANQAECgIIAgAAAA==.',
Ol='Olaznog:BAAANQADCgYIBgAAAA==.Oligisto:BAAANQAECgUIBgAAAA==.',
On='Ondro:BAAANQADCgQIBAAAAA==.Onirial:BAAANQADCgQIBAAAAA==.Onugem:BAAANQADCgYIEAAAAA==.',
Op='Oppenheimar:BAAANQADCgUICAAAAA==.Opusdiáboli:BAAANQADCgYICQAAAA==.',
Or='Orangë:BAAANQADCggIEAAAAA==.Orchidd:BAAANQAECgUICwAAAA==.Originalsoul:BAAANQAECgEIAQAAAA==.Orihimie:BAAANQADCgYIBgAAAA==.Ortesd:BAAANQADCgYIDAAAAA==.',
Os='Osamdi:BAAANQADCgUIBQAAAA==.Osaurus:BAAANQABCgIIAgAAAA==.Osen:BAAANQADCgYIBgAAAA==.',
Ot='Oterö:BAAANQAECgEIAQAAAA==.Ottisra:BAAANQADCgUIBQAAAA==.',
Ou='Ouran:BAAANQADCgMIAwAAAA==.',
Ow='Owvudú:BAAANQADCggICAAAAA==.',
Ox='Oxii:BAAANQAECgIIAwAAAA==.',
Oz='Ozlem:BAAANQADCgcICQAAAA==.Ozzur:BAAANQAECgcICAAAAA==.',
Pa='Pairo:BAAANQAECgcIEwABNQAECgkJFQAIAD4dAA==.Pajarraco:BAAANQABCgIIAgAAAA==.Palabray:BAAANQADCgUIBQAAAA==.Palasino:BAAANQADCgYIBwAAAA==.Palatass:BAAANQAECgQICAAAAA==.Pandefrica:BAAANQADCgcIDQABNQAECgQICAACAAAAAA==.Pandepascuas:BAAANQAECgQICAAAAA==.Panditaninja:BAAANQADCgcICAAAAA==.Pandochurro:BAAANQADCgQIBwAAAA==.Pandrös:BAABNQAECoEVAAIIAAkJPh1hBQDvAgAIAAkJPh1hBQDvAgAAAA==.Pandurian:BAAANQAECgEIAQAAAA==.Panjitinik:BAAANQADCgYIBgAAAA==.Panndii:BAAANQADCgMIAwAAAA==.Panxing:BAAANQADCgIIAgAAAA==.Papabrava:BAAANQADCgQIBAABNQAECgEIAQACAAAAAA==.Papasote:BAAANQADCggIFgAAAA==.Papibardockk:BAAANQADCgMIAwAAAA==.Paquin:BAAANQAFFAEIAQAAAA==.Parkka:BAAANQADCgYIDgAAAA==.Pauljosue:BAAANQAECgEIAQAAAA==.',
Pd='Pdza:BAAANQADCggIEQAAAA==.',
Pe='Pencilgon:BAAANQADCgUIDgAAAA==.Pentauret:BAAANQADCgYIBAAAAA==.Pepitaa:BAAANQAECgUICAAAAA==.Perrucha:BAAANQADCgEIAQAAAA==.Petricita:BAAANQADCgUIAwAAAA==.Petunia:BAAANQADCggIDgAAAA==.',
Pi='Picklesacred:BAAANQAECgcIEQAAAA==.Pipila:BAAANQADCgQIBAAAAA==.',
Pk='Pkoo:BAAANQAECgQIBAAAAA==.',
Pl='Plac:BAAANQADCgQIBAAAAA==.Playpaya:BAAANQADCgQIAwAAAA==.Plsaleml:BAAANQADCgYICgAAAA==.',
Pm='Pmanar:BAAANQADCgQIBAAAAA==.',
Po='Polárize:BAAANQADCgUIBQAAAA==.Pompoh:BAAANQAECgIIAgAAAA==.Pontecorvo:BAAANQADCgEIAQAAAA==.Porrita:BAAANQAECgEIAQAAAA==.',
Pp='Ppeltauren:BAAANQADCggICgAAAA==.Pprincesa:BAAANQADCgUICAAAAA==.',
Pr='Prominens:BAAANQADCggIDwAAAA==.',
Py='Pyngon:BAAANQAECgMIBgAAAA==.',
['Pä']='Pädme:BAAANQAECgMIAwAAAA==.',
['Pï']='Pïer:BAAANQADCggIDQAAAA==.',
['Pó']='Póntius:BAAANQAECgYIBwAAAA==.',
Qi='Qinshihuangt:BAAANQADCgIIAgAAAA==.',
Ql='Qliado:BAAANQADCgQIBgAAAA==.',
Qt='Qtaurentino:BAAANQAECgQIBQAAAA==.',
Qu='Quarantine:BAAANQAECgYICQAAAA==.Qubb:BAAANQAECgQIBAAAAA==.Queldales:BAAANQADCgYIBQAAAA==.Querubinz:BAAANQADCgIIAwAAAA==.Quinasa:BAAANQADCgcIDQAAAA==.Quingg:BAAANQADCggIEwAAAA==.',
['Qñ']='Qñado:BAAANQADCgIIAwAAAA==.',
Ra='Radagas:BAAANQADCgYIBgABNQAECgEIAQACAAAAAA==.Radiance:BAAANQADCgUICQAAAA==.Raenyx:BAAANQADCgIIAgABNQAECgUIBwACAAAAAA==.Rahemm:BAAANQAECgUIBwAAAA==.Rakasha:BAAANQADCgQIBAAAAA==.Raknar:BAAANQAECgEIAQAAAA==.Ramasheka:BAAANQAECgMIAwABNQAECgQIBAACAAAAAA==.Randester:BAAANQAECgYIEAAAAA==.Ranzhu:BAAANQADCgEIAQAAAA==.Raphiki:BAAANQADCgYIDQAAAA==.Rasky:BAAANQADCgUIBQAAAA==.Rawalejandro:BAAANQAECgYICgAAAA==.Raxfor:BAAANQADCgUIBQAAAA==.Raynorfx:BAAANQADCgYIBgAAAA==.',
Re='Reavdud:BAAANQADCgQIBAAAAA==.Rebor:BAAANQADCgIIAwAAAA==.Recogemonte:BAAANQADCgYICAAAAA==.Redjar:BAAANQADCgYIDAAAAA==.Redspirit:BAAANQADCgUIAwAAAA==.Reliah:BAAANQADCgUICQAAAA==.Relocosxd:BAAANQADCgEIAQAAAA==.Remyy:BAAANQADCgYICAABNQAECgQIBgACAAAAAA==.Rendel:BAAANQADCgUIBQAAAA==.Reumanic:BAAANQADCggIHQAAAA==.Rexdraconum:BAAANQAECgIIAwAAAA==.',
Rh='Rhaegn:BAAANQAECgEIAQAAAA==.Rhayza:BAAANQADCgMIAwABNQAECgQIBwACAAAAAA==.Rhayzadk:BAAANQAECgQIBwAAAA==.Rhazty:BAAANQADCgUIDgAAAA==.Rhea:BAAANQADCgQIBAAAAA==.Rhis:BAAANQADCgUIBQAAAA==.Rhiska:BAAANQADCgYIBgAAAA==.Rhyper:BAAANQAECgUIDQAAAA==.Rhäenyrä:BAAANQADCgYICQAAAA==.',
Ri='Richardriver:BAAANQADCgMIAwAAAA==.Ricketz:BAAANQAECgMIBAAAAA==.Rickygf:BAAANQADCgMIAwAAAA==.Riderless:BAAANQADCggIEAAAAA==.Rikudoü:BAAANQADCgQIBAAAAA==.Rikuo:BAAANQAECgQIBAAAAA==.Rinhosizora:BAAANQAECgMIBAABNQAECgQIBwACAAAAAA==.Riotszen:BAAANQADCgQIBAAAAA==.Rizoman:BAAANQADCgQIBAAAAA==.',
Ro='Roadcm:BAAANQADCgQIBwAAAA==.Robattangas:BAAANQADCggIDgAAAA==.Rockblacki:BAAANQAECgIIBAAAAA==.Rompektrës:BAAANQADCggICQAAAA==.Ronstreet:BAAANQAECgEIAQAAAA==.Rotls:BAAANQAECgUIBgAAAA==.Roweenn:BAAANQADCgQIBAAAAA==.',
Ru='Rugal:BAAANQAECgQIBAAAAA==.',
Ry='Ryuugan:BAAANQADCgQIBAABNQADCggIDAACAAAAAA==.',
['Rá']='Rámzx:BAAANQAECgIIAgAAAA==.',
['Rä']='Räx:BAAANQADCgMIBAAAAA==.',
['Rë']='Rëmbrandt:BAAANQAECgEIAQAAAA==.',
Sa='Sabriluisa:BAAANQADCgcIDAAAAA==.Sacredfire:BAAANQADCgEIAQAAAA==.Saintgermain:BAAANQADCgIIAgAAAA==.Saiphorionis:BAAANQAECgQIBAABNQAECgYIBwACAAAAAA==.Salginteer:BAAANQADCgMIAwAAAA==.Salvi:BAAANQADCggICgAAAA==.Samb:BAAANQADCgMIAwAAAA==.Samluck:BAAANQADCgUICQAAAA==.Sammwar:BAAANQAECgYICQAAAA==.Sanchin:BAAANQADCgUIBgABNQAECgQIBQACAAAAAA==.Sanghot:BAAANQADCgMIBAAAAA==.Sangreschwar:BAAANQADCgYIBwAAAA==.Sanguiiniuz:BAAANQADCgMIAwAAAA==.Sanmuertin:BAAANQAECgQIBAAAAA==.Sanndir:BAAANQAECgUIBwAAAA==.Santified:BAAANQADCggIDgAAAA==.Sapixi:BAAANQAECgQICAAAAA==.Sapphi:BAAANQADCggIDgAAAA==.Sardak:BAAANQADCggIEAAAAA==.Saria:BAAANQAECgUIBwAAAA==.Sasocas:BAAANQAECgQIBAAAAA==.Saurona:BAAANQADCgUICAAAAA==.Saycox:BAAANQAECgYICAAAAA==.Sayrén:BAAANQAECgEIAQAAAA==.',
Sc='Scanx:BAAANQAECgcIEAAAAA==.Scarmesh:BAAANQAECgQIBAAAAA==.Scavenge:BAAANQADCgEIAQAAAA==.',
Se='Sebvz:BAAANQAECgUICAAAAA==.Seejmet:BAAANQADCgEIAQAAAA==.Seguridad:BAAANQADCgIIAwAAAA==.Seleka:BAAANQADCgcIAgAAAA==.Selle:BAAANQADCgIIAgAAAA==.Seneget:BAAANQADCgUIBQAAAA==.Senjib:BAAANQAECgcIDgAAAA==.Serotonin:BAABNQAECoEYAAIKAAkJ3SBcAQBoAwAKAAkJ3SBcAQBoAwAAAA==.',
Sh='Shadito:BAAANQAECgQIBAAAAA==.Shagu:BAAANQADCgQIBAAAAA==.Shamanin:BAAANQADCgQIBAAAAA==.Shameco:BAAANQADCgcIDQAAAA==.Shamyto:BAAANQAECgEIAQAAAA==.Shanan:BAAANQAECgQIBAAAAA==.Shelox:BAAANQADCggIDgAAAA==.Shermy:BAAANQADCggICQAAAA==.Shibamiyuki:BAAANQAECgIIAgAAAA==.Shigarakicam:BAAANQAECgQICAAAAA==.Shiinosuke:BAAANQADCgUIBQAAAA==.Shinoshibi:BAAANQADCgYIBgAAAA==.Shirvallah:BAAANQADCgcIDwAAAA==.Shizaberu:BAAANQADCgYICAAAAA==.Shmebuloçk:BAAANQAECgEIAQAAAA==.Shokey:BAAANQADCgEIAQAAAA==.Sholva:BAAANQADCgMIAwAAAA==.Shurien:BAAANQAECgUIBgAAAA==.Shushinn:BAAANQAECgcICgAAAA==.Shusui:BAAANQAECgIIAQAAAA==.Shälash:BAAANQADCgQIBAAAAA==.',
Si='Sicarío:BAAANQADCgYICQAAAA==.Sieges:BAAANQAECgIIAgAAAA==.Sigrin:BAAANQAECgMIAwABNQAECgkJFQADAEweAA==.Silverkiller:BAAANQAECgIIAgAAAA==.Silvérwolf:BAAANQADCgEIAQAAAA==.Simoohayha:BAAANQAECgQIBgAAAA==.',
Sk='Skinhunter:BAAANQADCggIFAAAAA==.Sklother:BAAANQADCggICAABNQAECgcIEAACAAAAAA==.Skylow:BAAANQAECgQIBwAAAA==.Skyréss:BAAANQADCgYIBgAAAA==.',
Sm='Smaul:BAAANQADCgUIBQAAAA==.',
Sn='Snad:BAAANQAECgQIBwABNQAECgcICgACAAAAAA==.Snikerflitzz:BAAANQADCgUIBQAAAA==.Snoobdogg:BAAANQADCgUIBQAAAA==.',
So='Sofënox:BAAANQADCgQIAgAAAA==.Solaniin:BAAANQAECgQIBwAAAA==.Sommermage:BAAANQAECgIIAgAAAA==.Sommerwalker:BAAANQADCgYIEQAAAA==.Sonadow:BAAANQAECgQIBAABNQAECgUIBQACAAAAAA==.Sonbej:BAAANQAECgQIBgABNQAECgcIDgACAAAAAA==.Soogx:BAAANQAECgEIAQAAAA==.Sopaipiya:BAAANQAECgEIAQAAAA==.Souling:BAAANQADCggICAAAAA==.Soulèater:BAAANQADCgUICAAAAA==.Soyuno:BAAANQADCgcICgAAAA==.',
Sp='Spacemage:BAAANQAECggIDwAAAA==.Spacerm:BAAANQADCgIIAgABNQAECggIDwACAAAAAA==.Speedyarrow:BAAANQADCgQIBAAAAA==.Spêctrê:BAAANQADCgEIAQAAAA==.',
Sq='Sqlote:BAAANQADCgQIBAAAAA==.',
Sr='Srfelix:BAAANQADCgQIBgAAAA==.Srjusticia:BAAANQADCgMIAQAAAA==.Srsquishs:BAAANQADCgIIAgAAAA==.Srwea:BAAANQADCgYIBwAAAA==.',
Ss='Sskiper:BAAANQAECgUICAAAAA==.',
St='Stalinsky:BAAANQAECgQIBQAAAA==.Staraptor:BAAANQAECgUIBQAAAA==.Starkarya:BAAANQAECgIIAgAAAA==.Starsky:BAAANQADCgIIAgAAAA==.Starspawn:BAAANQADCgUIBQABNQADCgcIBwACAAAAAA==.Stonnex:BAAANQADCgEIAQAAAA==.Stârlight:BAAANQAECgEIAQAAAA==.',
Su='Sucarita:BAAANQADCgcIDQAAAA==.Suhyokaa:BAAANQADCgcICwAAAA==.Sukaritas:BAAANQAECgEIAQAAAA==.Sumäq:BAAANQAECgEIAQAAAA==.Sunfyre:BAAANQADCgEIAQAAAA==.Supre:BAAANQAECgMIBAAAAA==.',
Sw='Swindler:BAAANQAECgMIAwAAAA==.',
Sy='Sylvanderb:BAAANQADCgQIBAAAAA==.',
['Sâ']='Sâcrilegio:BAABNQAECoEYAAIJAAkJSyCzCAA0AwAJAAkJSyCzCAA0AwAAAA==.',
['Sî']='Sîxtecó:BAAANQAECgEIAQAAAA==.',
['Sö']='Sökrates:BAAANQAECgUIBwAAAA==.',
Ta='Tahun:BAAANQAECgIIAgAAAA==.Tailerx:BAAANQADCgQIBAAAAA==.Takachy:BAAANQADCgYICwAAAA==.Talarøn:BAAANQAECgEIAQAAAA==.Talématros:BAAANQADCgQIBgAAAA==.Tasjon:BAAANQAECgYIDAAAAA==.Tasjón:BAAANQADCgQIBAAAAA==.Taster:BAAANQAECgIIAgAAAA==.Tatcho:BAAANQADCgQIBAAAAA==.Tatgrim:BAAANQADCgUIBQAAAA==.Taurotoro:BAAANQAECgcIBgAAAA==.Tavitop:BAAANQAECgQIBwAAAA==.Tavop:BAAANQAECgEIAQABNQAECgQIBwACAAAAAA==.Tavozz:BAAANQAECgQIBQAAAA==.Tayamasan:BAAANQAECgIIAgAAAA==.Tayronisaias:BAAANQADCgUIBQAAAA==.Taysi:BAAANQAECgQIBwAAAA==.Tazg:BAAANQAECgcICwAAAA==.',
Te='Tendrilion:BAAANQAECgQIBQAAAA==.Tenken:BAAANQADCgQIBAAAAA==.Tephie:BAAANQADCgMIAwAAAA==.Tereaux:BAAANQADCgEIAQAAAA==.Termanology:BAAANQADCgYIBgAAAA==.Terrik:BAAANQADCggIDAAAAA==.Testiculona:BAAANQADCgMIAwAAAA==.',
Th='Thebadboy:BAAANQADCgYIEQAAAA==.Theconor:BAAANQADCgQIBgAAAA==.Thedrag:BAAANQAECgYICQAAAA==.Theewarrior:BAAANQAECgMIAwAAAA==.Thelastmønk:BAAANQAECgEIAQAAAA==.Themaga:BAAANQAECgQIBgAAAA==.Thenas:BAAANQADCgEIAQAAAA==.Thenight:BAAANQABCgIIAgAAAA==.Theogro:BAAANQADCgQIBAAAAA==.Thepepper:BAAANQADCgUIBQAAAA==.Theraliz:BAAANQAECgQIBAAAAA==.Thereaux:BAAANQAECgUIBwAAAA==.Thesentry:BAAANQADCgUIBgAAAA==.Theshami:BAAANQADCggIDAAAAA==.Theskaa:BAAANQAECgUICQAAAA==.Thetoxica:BAAANQADCgUIBwAAAA==.Thomiko:BAAANQADCgEIAQAAAA==.Thorflins:BAAANQAECgEIAQABNQAECgUICwACAAAAAA==.Thorfínn:BAAANQADCgYIBgAAAA==.Thorgrimm:BAAANQADCgcIEQAAAA==.Thoritank:BAAANQAECgcIBQAAAA==.Thorjin:BAAANQADCgQIBAAAAA==.Thorkkel:BAAANQADCgYICAAAAA==.Thrandüil:BAAANQADCgYIDgAAAA==.Thráiin:BAAANQADCgEIAQAAAA==.Thularion:BAAANQADCgQIBAAAAA==.',
Ti='Timm:BAAANQADCgcICAAAAA==.Tiramisü:BAAANQADCgYIDAAAAA==.Tiramizu:BAAANQAECgQIBAAAAA==.Tirne:BAAANQADCgcICgAAAA==.Tirys:BAAANQADCgQIBAAAAA==.Titanozcuro:BAAANQADCgMIAwAAAA==.',
Tk='Tkiin:BAAANQADCgQIBAAAAA==.',
To='Toball:BAAANQADCgMIAwAAAA==.Tonswors:BAAANQAECgMIBAAAAA==.Toprac:BAAANQADCgMIAwAAAA==.Toravon:BAAANQAECgMIBAAAAA==.Toribianito:BAAANQAECgMIAwAAAA==.Torujo:BAAANQADCgIIAgAAAA==.',
Tr='Trakkar:BAAANQADCgYIDQAAAA==.Traxexd:BAAANQAECgQIBQAAAA==.Treeckko:BAAANQADCgUIBQAAAA==.Trizh:BAAANQAECgYICgAAAA==.Trogloditamr:BAAANQADCgEIAQABNQAECgIIAgACAAAAAA==.Trollzilla:BAAANQADCgQIBAAAAA==.Trolobayo:BAAANQADCggIDQAAAA==.Trombe:BAAANQADCggICAAAAA==.Troth:BAAANQADCgYICwAAAA==.Trx:BAAANQADCgcICwAAAA==.Tryzthano:BAAANQADCgYIBgAAAA==.',
Ts='Tsukichamy:BAAANQAECgQIBgAAAA==.Tsukinohono:BAAANQADCgIIAgABNQADCgUICAACAAAAAA==.Tsukoni:BAAANQADCgcIDwAAAA==.',
Tu='Tumbalino:BAAANQAECgUIBwAAAA==.Tunche:BAAANQABCgIIAgAAAA==.Turlex:BAAANQADCgMIBAAAAA==.Tusi:BAAANQADCgUICAAAAA==.Tuskankamon:BAAANQADCgIIAgAAAA==.Tutte:BAAANQAECgQIBAAAAA==.Tutánca:BAAANQADCgUIBQAAAA==.',
Ty='Tyffania:BAAANQADCgYIBwAAAA==.Tyruz:BAAANQAECgcIDgAAAA==.',
['Tá']='Tánjiro:BAAANQAECgMIAwAAAA==.Tántalo:BAAANQAECgIIAwABNQAECgMIBgACAAAAAA==.Tásjön:BAAANQAECgMIAwAAAA==.',
['Të']='Tëlchâr:BAAANQAECgMIAwAAAA==.',
['Tý']='Týphon:BAAANQAECgIIAgAAAA==.',
Uc='Uchida:BAAANQADCgUIAgABNQAECgQIBwACAAAAAA==.',
Uk='Ukog:BAAANQAECgUICQAAAA==.',
Ul='Ulfgar:BAAANQADCgIIAgAAAA==.Ulisesh:BAAANQADCgYIBgAAAA==.Ulkii:BAAANQADCgYICAAAAA==.Ultramazter:BAAANQADCgUIBQAAAA==.',
Un='Unaixo:BAAANQADCgYIBgAAAA==.',
Ur='Uriyael:BAAANQAECgMIBgAAAA==.Ursuur:BAAANQADCggIDgAAAA==.',
Ut='Uthart:BAAANQADCgQIBAAAAA==.',
Va='Valarwen:BAAANQADCgcIDAAAAA==.Valdreth:BAAANQADCggIDQAAAA==.Valeneth:BAAANQADCgUIAwAAAA==.Valiant:BAAANQADCgYIBgAAAA==.Valkenhain:BAAANQADCgYICgAAAA==.Valmonkeyh:BAAANQAECgIIAwAAAA==.Valmonkeyl:BAAANQADCgcIBwAAAA==.Vangonna:BAAANQADCgEIAQAAAA==.Varthur:BAAANQABCgIIAgAAAA==.Vasculio:BAAANQAECgIIAgAAAA==.Vasheth:BAAANQADCgYICwAAAA==.Vasthorr:BAAANQADCgEIAQAAAA==.',
Ve='Vejrekku:BAAANQADCgQIBQAAAA==.Velumbra:BAAANQADCgQIBAAAAA==.Vergasola:BAAANQADCgMIAwAAAA==.Vertrix:BAAANQADCgYIBgAAAA==.Verymelon:BAAANQAECgYIDgAAAA==.Vesperyx:BAAANQAECgIIAwAAAA==.',
Vh='Vhacko:BAAANQADCgYICgAAAA==.',
Vi='Vialucis:BAAANQADCgcIBwAAAA==.Vianis:BAAANQADCgEIAQAAAA==.Vicaioros:BAAANQADCgYIBwAAAA==.Vichizchami:BAAANQAECgUIBQAAAA==.Vichizz:BAAANQAECgMIAwABNQAECgUIBQACAAAAAA==.Viciiecal:BAAANQAECgcIEwAAAA==.Vicius:BAAANQADCgMIAwAAAA==.Viejosabrosö:BAAANQAECgIIBAAAAA==.Violyn:BAAANQADCgMIAwAAAA==.Viszeral:BAAANQAECgMIAwABNQAECgUICAACAAAAAA==.Vitoxdary:BAAANQABCgIIAgAAAA==.',
Vo='Voidcha:BAAANQADCgEIAQAAAA==.Volldemort:BAAANQAECgIIAgAAAA==.Volttage:BAAANQADCgcICwAAAA==.Vonjum:BAAANQADCgUICQAAAA==.',
Vt='Vtor:BAAANQAECgQICAAAAA==.',
Vu='Vulkan:BAAANQAECgcIDgAAAA==.',
['Vá']='Vána:BAAANQADCgIIAgAAAA==.',
['Vó']='Vóróz:BAAANQADCgIIAgAAAA==.',
Wa='Wackø:BAAANQADCgQIBAAAAA==.Warorc:BAAANQADCgYICQAAAA==.Warrelegante:BAAANQADCgIIAgABNQAECgQICAACAAAAAA==.Warriorgrego:BAAANQADCgYICwAAAA==.Washimyngo:BAAANQADCgUIBQAAAA==.Watermelo:BAAANQAECgUICQAAAA==.',
We='Wendhy:BAAANQADCgEIAQAAAA==.Wendyita:BAAANQABCgMIAwAAAA==.',
Wh='Whater:BAAANQADCgIIAgAAAA==.Whesley:BAAANQADCgYIDAAAAA==.Whitemanee:BAAANQADCgUICAABNQAECgQIBAACAAAAAA==.Whushung:BAAANQAECgQIBAAAAA==.',
Wi='Wiinly:BAAANQAECgEIAQAAAA==.Wildson:BAAANQAECgEIAQAAAA==.Wiraq:BAAANQAECgMIAgAAAA==.Wissepi:BAAANQADCggIFAAAAA==.Witzy:BAAANQADCggIDQAAAA==.',
Wo='Wolfeligoza:BAAANQAECgUIBgAAAA==.Wolfgeralt:BAAANQADCgIIAgAAAA==.Wolfrain:BAAANQAECgIIAwAAAA==.Wolfsrain:BAAANQADCggICwAAAA==.Wolvy:BAAANQABCgQIBAAAAA==.Wounch:BAAANQADCgIIAgABNQADCgUICAACAAAAAA==.',
Wr='Wrhayza:BAAANQADCgUIBQAAAA==.',
Wu='Wufar:BAAANQADCgUICAAAAA==.Wurd:BAAANQADCgMIAwAAAA==.',
Wy='Wylgrim:BAAANQADCgYICwABNQAECgcIDQACAAAAAA==.',
['Wâ']='Wâckøø:BAAANQADCgcIBwAAAA==.',
Xa='Xanhk:BAAANQADCgUIBgAAAA==.',
Xe='Xetik:BAAANQADCgMIAwAAAA==.Xey:BAAANQADCgYIBgAAAA==.',
Xi='Xilk:BAAANQADCgQIBgABNQADCgYICwACAAAAAA==.Xilka:BAAANQADCgYICwAAAA==.',
Xn='Xnocturne:BAAANQADCgUIBQAAAA==.',
Xo='Xolokin:BAAANQADCgIIAgAAAA==.',
Xt='Xtreem:BAAANQAECgEIAQAAAA==.',
Xu='Xubb:BAABNQAECoEYAAILAAkJvRaKEwB0AgALAAkJvRaKEwB0AgAAAA==.',
Ya='Yakuzagt:BAAANQADCgIIAgAAAA==.Yamisan:BAAANQAECgQICAAAAA==.Yanjun:BAAANQADCgYIBwABNQABCgIIAgACAAAAAA==.Yasky:BAAANQADCgQIBAAAAA==.Yazaam:BAAANQADCgIIAgAAAA==.',
Yh='Yhina:BAAANQAECgQIBAAAAA==.',
Yi='Yinaiteen:BAAANQAECgMIBAAAAA==.',
Yo='Yojoy:BAAANQADCgcICQAAAA==.Yorukage:BAAANQABCgIIAgAAAA==.Yorunecrum:BAAANQADCgcIEgAAAA==.',
Yr='Yracema:BAAANQADCgYIBwAAAA==.',
['Yâ']='Yâtzüry:BAAANQAECgYICQAAAA==.',
['Yó']='Yóru:BAAANQADCgYIEAAAAA==.',
Za='Zacarias:BAAANQAECgMIBAAAAA==.Zagal:BAAANQADCgUIBQAAAA==.Zanudar:BAAANQADCgUICgAAAA==.Zaokum:BAAANQAECgYICQAAAA==.Zaracatunga:BAAANQAECgIIAgAAAA==.Zarnax:BAAANQADCgMIAwAAAA==.Zarzin:BAAANQADCgcICwAAAA==.',
Ze='Zeckert:BAAANQAECggICAAAAA==.Zedreg:BAAANQAECgEIAQAAAA==.Zeeds:BAAANQADCgYIBgAAAA==.Zehelyne:BAAANQAECgcIDAAAAA==.Zekutor:BAAANQAECgQICQAAAA==.Zengil:BAAANQADCgUICQAAAA==.Zentetsuken:BAAANQADCgYICAAAAA==.Zephania:BAAANQADCggICAAAAA==.',
Zh='Zharfel:BAAANQADCgIIAgAAAA==.Zhatx:BAAANQAECgMIAwAAAA==.Zhenna:BAAANQAECgUIBgAAAA==.Zhinjoo:BAAANQADCggIEAAAAA==.Zhyer:BAAANQAECgEIAQAAAA==.',
Zi='Zizaa:BAAANQADCgMIAwAAAA==.Zizu:BAAANQADCgUICwAAAA==.',
Zo='Zomma:BAAANQADCgYIAgAAAA==.Zonoscope:BAAANQADCgUIBQAAAA==.',
Zu='Zucc:BAAANQADCgIIAgAAAA==.Zuffx:BAAANQADCgYICgAAAA==.Zuikaku:BAAANQAECgYICgAAAA==.Zukumbia:BAAANQADCgQIAgAAAA==.Zunjin:BAAANQADCgYIBwAAAA==.',
Zz='Zzeus:BAAANQAECgcICwAAAA==.',
['Zè']='Zèrò:BAAANQADCgQIBAAAAA==.',
['Zé']='Zéhel:BAAANQADCgYICgAAAA==.',
['Zø']='Zøuht:BAAANQAECgQICQAAAA==.Zøus:BAAANQADCggIDQAAAA==.',
['Àl']='Àlphà:BAAANQADCggIFQAAAA==.',
['Ál']='Álibéll:BAAANQAECgUIBQAAAA==.',
['Ár']='Ártemiz:BAAANQADCgMIAwAAAA==.',
['Áz']='Ázáél:BAAANQADCgMIAwAAAA==.',
['Ân']='Ângie:BAAANQADCgMIAwAAAA==.',
['Âr']='Ârcänë:BAAANQAECgMIBQAAAA==.',
['Äd']='Ädriänä:BAAANQADCgYIDgAAAA==.',
['Än']='Änäwänäsäký:BAAANQAECgEIAQAAAA==.',
['Är']='Ärtïs:BAAANQABCgQICAAAAA==.',
['Äs']='Äsmodeus:BAAANQAECgIIAQAAAA==.',
['Él']='Éléná:BAAANQADCgYIBwAAAA==.',
['Ëd']='Ëder:BAAANQADCggICAAAAA==.',
['Ëe']='Ëescanör:BAAANQAECgUIBgAAAA==.',
['Ëx']='Ëxecutor:BAAANQAECgIIAgAAAA==.',
['Ðe']='Ðemon:BAAANQADCgUIBAAAAA==.Ðexters:BAAANQADCgUIBQAAAA==.',
['Ör']='Örchid:BAAANQAECgIIAgAAAA==.',
['ßl']='ßlæster:BAAANQADCggIEgAAAA==.',
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
