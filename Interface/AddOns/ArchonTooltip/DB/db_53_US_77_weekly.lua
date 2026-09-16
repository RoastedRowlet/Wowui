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

local lookup = {'Unknown-Unknown','Druid-Restoration','DemonHunter-Havoc','Priest-Holy','Paladin-Retribution','Priest-Discipline','Hunter-BeastMastery','Hunter-Marksmanship','Warlock-Affliction','Warlock-Destruction','Warlock-Demonology','Rogue-Assassination','Rogue-Subtlety','Mage-Arcane','DeathKnight-Unholy','DeathKnight-Blood','Monk-Windwalker','Druid-Guardian','Shaman-Restoration','Paladin-Protection','Evoker-Preservation','Monk-Mistweaver','Shaman-Elemental','Rogue-Outlaw','Paladin-Holy',}
local provider = {region='US',realm='Drakkari',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aatrøx:BAAANQADCgMIBAAAAA==.',
Ab='Abhigail:BAAANQAECgEIAQAAAA==.Absënt:BAAANQADCgEIAQAAAA==.Abuelabetzy:BAAANQADCgMIAwAAAA==.Abueladanger:BAAANQAECgMIBAAAAA==.',
Ac='Acaelus:BAAANQADCgcIBgAAAA==.Ackruts:BAAANQAECgEIAQAAAA==.Ackrüdk:BAAANQADCgcIBwAAAA==.',
Ad='Adirà:BAAANQADCgYICgAAAA==.',
Ae='Aeriallu:BAAANQAECgIIAgAAAA==.Aeroart:BAAANQADCgMIAwAAAA==.',
Ag='Ageis:BAAANQADCgMIAgAAAA==.Aggy:BAAANQADCgMIAQAAAA==.Agreegor:BAAANQADCgIIAgAAAA==.Agregorr:BAAANQADCgQIBAAAAA==.Agrellor:BAAANQAECgIIAgAAAA==.Agrotank:BAAANQAECgcIEQAAAA==.Aguafluye:BAAANQADCggIDgAAAA==.Agüita:BAAANQAECgQIBwAAAA==.',
Ah='Ahktund:BAAANQADCgYICQAAAA==.Ahnkhalan:BAAANQADCgUIBQAAAA==.',
Ai='Ailhen:BAAANQAECgEIAgAAAA==.Aillyn:BAAANQADCgQIBQAAAA==.Ailuros:BAAANQAECgUICQAAAA==.Aisslin:BAAANQAECgQIBAAAAA==.',
Ak='Akachete:BAAANQADCgUICwAAAA==.Akazael:BAAANQADCgYIEAAAAA==.Akhushtal:BAAANQADCgEIAQAAAA==.',
Al='Ala:BAAANQAECgIIAgAAAA==.Alathra:BAAANQADCgYIBgAAAA==.Albaficar:BAAANQADCgMIBAAAAA==.Aldebbarann:BAAANQADCggIFAAAAA==.Aldrichk:BAAANQABCgIIAgAAAA==.Aldrona:BAAANQAECgEIAQAAAA==.Alechiquita:BAAANQADCgQIBAAAAA==.Alejoz:BAAANQADCgUIBQAAAA==.Alessiià:BAAANQADCggIFgAAAA==.Alfy:BAAANQADCggIDgAAAA==.Alibell:BAAANQADCgQIAgABNQAECgUICgABAAAAAA==.Aliicea:BAAANQADCgUIBgAAAA==.Alkail:BAAANQADCggIDgAAAA==.Allielith:BAAANQAECgIIAgAAAA==.Alliesh:BAAANQAECgIIAgAAAA==.Alonda:BAAANQADCggICAAAAA==.Alquimetal:BAAANQAECgIIAwAAAA==.Alrog:BAAANQADCgYICgAAAA==.Alsiel:BAAANQADCgMIAwAAAA==.Alternative:BAAANQADCgYIEQAAAA==.Altharious:BAAANQAECgQICQAAAA==.Alvarezz:BAAANQADCggICAAAAA==.Alvea:BAAANQADCggICQAAAA==.Alvorada:BAAANQADCggIDgAAAA==.Alúbram:BAAANQADCgMIAwAAAA==.',
Am='Ambusoraka:BAAANQADCgYIFgAAAA==.Amelhía:BAAANQAECgMIBAAAAA==.Amiraa:BAAANQADCgEIAQAAAA==.Ammuhobi:BAAANQADCgMIAwAAAA==.Amor:BAABNQAECoEZAAICAAkJGBk4CQCqAgACAAkJGBk4CQCqAgAAAA==.Amorsiyou:BAAANQAECgMIAwAAAA==.Amumu:BAAANQAECgUICgAAAA==.Amäzonya:BAAANQADCgYICwAAAA==.',
An='Anakiin:BAAANQAECgQICAAAAA==.Anakin:BAAANQAECgEIAQAAAA==.Analiha:BAAANQAECgUICQAAAA==.Anarin:BAAANQABCgYICwAAAA==.Anaskmy:BAAANQADCgYIDwAAAA==.Andrewsarkus:BAAANQADCgYIEAAAAA==.Angelado:BAAANQADCgMIAwAAAA==.Angelboy:BAAANQADCgEIAQAAAA==.Ankthar:BAAANQADCgQIBAAAAA==.Annacleti:BAAANQAECgQIBAAAAA==.Annà:BAAANQAECgUICQAAAA==.Anní:BAAANQAECgEIAgAAAA==.Anoyngorange:BAAANQADCgUIBQAAAA==.Antauro:BAAANQADCgYIBgAAAA==.Antezanaz:BAAANQADCgEIAQAAAA==.Antimagee:BAAANQADCgQIBAABNQAECgkJHAADAOYhAA==.Anux:BAAANQADCgQIBgAAAA==.',
Ao='Aoky:BAAANQAECgIIAgAAAA==.Aom:BAAANQAECgQIBwAAAA==.Aomesan:BAAANQAECgEIAQAAAA==.',
Ap='Apholö:BAAANQAECgQIBgAAAA==.Apos:BAABNQAECoEmAAIEAAkJQxscDADzAgAEAAkJQxscDADzAgAAAA==.Applevenus:BAAANQADCgUIEAAAAA==.Aprhodithe:BAAANQADCgIIAgABNQAECgQIBgABAAAAAA==.Apøløfun:BAAANQADCgYICQAAAA==.',
Ar='Arandher:BAAANQADCgcIDgAAAA==.Arcanbot:BAAANQADCgIIAgAAAA==.Archeón:BAAANQABCgQIBAAAAA==.Arcrav:BAAANQAECgcIDQAAAA==.Arcraxx:BAAANQAECgMIBgAAAA==.Ardoger:BAAANQAECgMIAwAAAA==.Ares:BAAANQAECgEIAQAAAA==.Argelo:BAAANQADCgYIBwAAAA==.Argilac:BAAANQADCgIIAgAAAA==.Ariël:BAAANQADCgQIBAAAAA==.Arkhonte:BAAANQAECgYIDQAAAA==.Arphenom:BAAANQAECgUIBwAAAA==.Arry:BAAANQADCgYIDwAAAA==.Artemisadn:BAAANQAECgUICQAAAA==.Arthaslt:BAAANQADCgMIAwAAAA==.Artherir:BAABNQAECoEYAAIFAAgJ0xkQMABJAgAFAAgJ0xkQMABJAgAAAA==.Artémísä:BAAANQADCgQIBAAAAA==.',
As='Ashalanor:BAAANQADCgYIBwAAAA==.Ashelatto:BAAANQADCggIDQABNQAECgUICwABAAAAAA==.Ashirogi:BAAANQAECgIIAgAAAA==.Asproz:BAAANQADCgQIAgAAAA==.Astralit:BAAANQADCgIIAgAAAA==.Astralx:BAAANQAECgEIAQAAAA==.Astravia:BAAANQAECgIIAwAAAA==.Aströzombie:BAAANQADCgEIAQAAAA==.',
At='Atenasuru:BAAANQADCgEIAQAAAA==.Athandrui:BAAANQADCgYIBgAAAA==.Atheas:BAAANQADCgEIAQAAAA==.Atilaa:BAAANQAECgQIBQABNQAECgcIEgABAAAAAA==.',
Au='Aureliuz:BAAANQADCggICAAAAA==.Aurovia:BAAANQADCgUIBQAAAA==.',
Av='Avenaquaker:BAABNQAECoEZAAMEAAkJfB6qCQAQAwAEAAkJGB6qCQAQAwAGAAEJ0B2iFgBBAAAAAA==.Avethrus:BAAANQAECgQIBAAAAA==.Avratz:BAAANQADCggIDQAAAA==.',
Ax='Axazel:BAAANQADCgcIBwAAAA==.',
Ay='Aynoah:BAAANQADCgIIAgAAAA==.Ayorya:BAAANQAECgEIAQAAAA==.',
Az='Azaks:BAAANQAECgUICgAAAA==.Azarelshot:BAAANQAECgQIBAAAAA==.Azarelthas:BAAANQADCgQIBAAAAA==.Azarelux:BAAANQAECgIIAgAAAA==.Azarél:BAAANQADCgYICgAAAA==.Azgus:BAAANQADCggIEAAAAA==.Azidahakas:BAAANQAECgQIBQAAAA==.Azize:BAAANQADCgQIAwAAAA==.Azores:BAAANQADCgYICQAAAA==.Azsharael:BAAANQAECgQIBAAAAA==.Azymondiaz:BAAANQAECgUICAAAAA==.',
['Añ']='Añá:BAAANQADCgYIBgAAAA==.',
Ba='Baballagha:BAAANQAECgMIAwAAAA==.Backup:BAAANQADCgQIBAAAAA==.Baclo:BAAANQADCgYIBgAAAA==.Badpowell:BAAANQAECgYIDQAAAA==.Baileysade:BAAANQAECgQIBwAAAA==.Bakarass:BAAANQADCgIIAgABNQABCgIIAgABAAAAAA==.Balanky:BAAANQADCgYICgAAAA==.Baliyeh:BAAANQAECgEIAQAAAA==.Balthasar:BAAANQADCgQIBAAAAA==.Banesa:BAAANQADCgMIAwAAAA==.Banr:BAAANQAECgEIAQAAAA==.Baraqiel:BAAANQADCgQIBAAAAA==.Bathier:BAAANQAECgUIBQAAAA==.Bayula:BAAANQAECgUICAAAAA==.Bazuca:BAAANQADCgQIBAAAAA==.',
Be='Beatrixkidoo:BAAANQADCgUICAAAAA==.Beelzebù:BAAANQADCgQIBgAAAA==.Beickergamer:BAAANQADCgQIBgAAAA==.Belham:BAAANQAECgIIAgAAAA==.Beliin:BAAANQAECggICAAAAA==.Belionar:BAAANQADCgQIBAAAAA==.Belladonna:BAAANQAECgIIAwAAAA==.Beniøn:BAAANQADCgIIAgAAAA==.Benzac:BAAANQADCgMIAwAAAA==.Benzott:BAAANQAECgQIBQAAAA==.Berkas:BAAANQADCgMIAwAAAA==.Berserkss:BAAANQADCgMIAwAAAA==.Beyondhope:BAAANQADCggIEAAAAA==.',
Bh='Bhanshee:BAAANQADCgUIBQAAAA==.Bhhaal:BAAANQADCgMIAwABNQAECgQIBwABAAAAAA==.Bhhal:BAAANQAECgQIBwAAAA==.',
Bi='Biance:BAAANQAECgMIAwAAAA==.Bicklouw:BAAANQAECgQIBAAAAA==.Bigpunisher:BAAANQAECgMIBgAAAA==.Biorns:BAAANQADCggIDAAAAA==.',
Bl='Blaackpearl:BAAANQADCgcIBwAAAA==.Blackkô:BAAANQAECgYIDwAAAA==.Blackraisond:BAAANQADCgUICwAAAA==.Blakscorpion:BAAANQADCgUICAAAAA==.Bleiis:BAAANQAECgcIDAAAAA==.Blessrage:BAAANQADCggIDgAAAA==.Bloodoroth:BAAANQAECgIIAwAAAA==.Bloodýx:BAAANQADCggICgAAAA==.Blossomder:BAAANQADCgYIBwAAAA==.Blossomy:BAAANQADCgUIBQAAAA==.Bluedh:BAAANQADCggIFwABNQAECgIIAgABAAAAAA==.Bluevoker:BAAANQAECgIIAgAAAA==.',
Bo='Bolg:BAAANQAECgUIBQAAAA==.Bonsaijr:BAAANQAECgIIAgAAAA==.Bonsaipro:BAAANQAECgYIDQAAAA==.Botìja:BAAANQADCgYIDgAAAA==.',
Br='Brandishs:BAAANQAECgQIBAAAAA==.Branngus:BAAANQADCgYIEQAAAA==.Breiknar:BAAANQADCgQIBAAAAA==.Brewnation:BAAANQAECgMIAwAAAA==.Brightsad:BAAANQAECgYICQAAAA==.Brishna:BAAANQAECgQIBAAAAA==.Brunoos:BAAANQADCgcICQAAAA==.Brusiu:BAAANQAECgQIBgAAAA==.',
Bu='Buddy:BAAANQADCgQIBAAAAA==.Bulloflight:BAAANQADCgIIAgABNQADCggICAABAAAAAA==.Bunda:BAAANQAECgYIDwAAAA==.Busyxw:BAAANQAECgQIBAAAAA==.',
['Bæ']='Bæ:BAAANQADCgcIBwABNQAECgQIBAABAAAAAA==.',
Ca='Cabecar:BAAANQAECgEIAQAAAA==.Caberdeath:BAAANQADCgIIAgAAAA==.Caberlock:BAAANQAECgYIDAAAAA==.Cadmel:BAAANQADCgcICwABNQAECgEIAQABAAAAAA==.Caesarss:BAAANQAECgIIAgAAAA==.Calancho:BAAANQAECgQICAAAAA==.Cambum:BAAANQADCgYIBwAAAA==.Candise:BAAANQAECgYIDwAAAA==.Candlejack:BAAANQADCgUIBQAAAA==.Capkast:BAAANQAECgEIAQAAAA==.Caralock:BAAANQAECgUICwAAAA==.Carbonxx:BAAANQAECgEIAgAAAA==.Carcass:BAAANQAECgMIAwAAAA==.Carneasa:BAAANQADCggICAAAAA==.Carpinchø:BAAANQAECgUICgAAAA==.Carrasquinho:BAAANQAECgUICgAAAA==.Cassiusclay:BAAANQAECgUICgAAAA==.Cawboy:BAACNQAFFIEGAAMHAAUJMRnjAQB3AQAHAAQJYxjjAQB3AQAIAAEJaRyzDgBQAAA1AAQKgSEAAwcACQmiJkYAAAMEAAcACQmiJkYAAAMEAAgACQktIvQLAMwCAAAA.Cayuwoky:BAAANQAECgMIBQAAAA==.Cazadorpaska:BAAANQADCggIFAAAAA==.',
Cd='Cdu:BAAANQADCggICAAAAA==.',
Ce='Cearlink:BAAANQAECgEIAQAAAA==.Cel:BAAANQADCgQIBAAAAA==.Celhi:BAAANQAECgUIBQAAAA==.',
Ch='Chamask:BAAANQAECgQIBQAAAA==.Chameeto:BAAANQADCgIIAQABNQAECgYIDwABAAAAAA==.Chamiix:BAAANQADCgQIBAAAAA==.Chamilk:BAAANQADCgYICwAAAA==.Chammiin:BAAANQAECgIIAgAAAA==.Chastia:BAAANQABCgYIBwAAAA==.Chaumita:BAAANQABCgMIAwAAAA==.Chechuna:BAAANQAECgcIDgAAAA==.Chepe:BAAANQADCgYICwAAAA==.Chicobamm:BAAANQAECgEIAQAAAA==.Chikyy:BAAANQADCgMIAwAAAA==.Chiller:BAAANQADCgUIBQAAAA==.Chinxulin:BAAANQAECgIIAgAAAA==.Chocottrenza:BAAANQABCgEIAQAAAA==.Chondinero:BAAANQADCgQIBAAAAA==.Choriser:BAAANQADCgQIBAAAAA==.Chrís:BAAANQAECgIIAgAAAA==.Chrïspala:BAAANQAECgUICQAAAA==.Chuckyseador:BAAANQAECgQICAAAAA==.Chyrene:BAAANQADCgYIEAABNQAECgQIBwABAAAAAA==.Chöcoboom:BAAANQAECgEIAQAAAA==.',
Ci='Ciagnai:BAAANQADCggIEgAAAA==.Ciircé:BAAANQAECgYIDwAAAA==.Citlâli:BAAANQABCgIIAgAAAA==.',
Cl='Claribelle:BAAANQAECgUICQAAAA==.Classicmurió:BAAANQADCgUIBQAAAA==.Clavakchan:BAAANQADCgQIBAAAAA==.Clenzoil:BAAANQAECgEIAQABNQAECggIEQABAAAAAA==.Cliffs:BAAANQADCgEIAQABNQADCgYICwABAAAAAA==.Clorpi:BAAANQADCgcICwAAAA==.Clëoh:BAAANQAECgUICQAAAA==.',
Co='Commendatori:BAAANQADCgIIAwAAAA==.Courel:BAAANQAECgEIAQAAAA==.Coyotino:BAAANQADCgQIAgAAAA==.',
Cr='Creman:BAAANQABCgIIAgAAAA==.Crimsonclaw:BAAANQADCggIEgAAAA==.Crisbareta:BAAANQAECgEIAQAAAA==.Cristthell:BAAANQAECgQICwAAAA==.Crixis:BAAANQAECgQIBAAAAA==.Crookie:BAAANQADCgEIAQAAAA==.Crossbone:BAAANQADCggIDQAAAA==.Crìxus:BAAANQAECgUIBAAAAA==.Crüll:BAAANQAECgIIAgAAAA==.',
Cu='Cuchicuchl:BAAANQADCgEIAQAAAA==.Cuija:BAAANQAECgQIBAAAAA==.',
Cy='Cyrsse:BAAANQADCgYIBgAAAA==.Cythorn:BAAANQADCgYICQAAAA==.Cyttaria:BAAANQADCgYIBwAAAA==.',
['Cä']='Cärola:BAAANQAECgUICQAAAA==.Cäroly:BAAANQAECgQIBwAAAA==.',
['Cë']='Cëlestial:BAAANQAECgYIBwAAAA==.',
['Cö']='Cönner:BAAANQADCgEIAQAAAA==.',
Da='Dadu:BAAANQADCgQIBAAAAA==.Daemerys:BAAANQADCggIEAAAAA==.Dagasnakë:BAAANQADCgYIBgAAAA==.Dagath:BAAANQAECgIIAgAAAA==.Dagrone:BAAANQAECgIIAwAAAA==.Dagurame:BAAANQADCgUIBQAAAA==.Dailee:BAAANQADCgMIAwAAAA==.Daimøn:BAABNQAECoEbAAQJAAgJ1B08AQDaAgAJAAgJcB08AQDaAgAKAAQJaBVsJQAQAQALAAIJphQ5oACMAAAAAA==.Daishiro:BAAANQAFFAEIAQAAAA==.Dakanji:BAAANQADCgYIBwAAAA==.Damadodia:BAAANQADCgUIBQAAAA==.Damarihs:BAAANQADCgUIBQAAAA==.Damarus:BAAANQADCgcIAwAAAA==.Damhián:BAAANQAECgEIAgAAAA==.Danot:BAAANQADCgQIBAAAAA==.Dansy:BAAANQAECgYIBgABNQAECgcICgABAAAAAA==.Dantenamikaz:BAAANQAECgEIAQAAAA==.Darckamage:BAAANQAECgcICQABNQAECgkJIAAEAAQZAA==.Darckmont:BAAANQADCgIIAgAAAA==.Dariansa:BAABNQAECoEYAAMMAAkJORYcFQDuAQAMAAcJxRQcFQDuAQANAAUJ5g8IIABdAQABNQADCgYIBgABAAAAAA==.Darkamerica:BAAANQADCgEIAQAAAA==.Darkarus:BAAANQADCgQIBgAAAA==.Darkelezzard:BAAANQADCgEIAQAAAA==.Darkengel:BAAANQABCgIIAgAAAA==.Darkinghul:BAAANQAECgIIAgAAAA==.Darkrivera:BAAANQAECgQIBgAAAA==.Darre:BAAANQAECgQIBQAAAA==.Darthveil:BAAANQAECgUICAAAAA==.Datsury:BAAANQADCgIIAgABNQAECgcIEAABAAAAAA==.Davik:BAAANQADCggIDwAAAA==.Daxxoz:BAAANQAECgMIBQAAAA==.Dayhunter:BAAANQADCgYIBgAAAA==.Dayix:BAAANQAECgcIEgAAAA==.Dayonïs:BAAANQAECgEIBAAAAA==.Dazielth:BAAANQABCgEIAQAAAA==.',
Dd='Ddualipa:BAAANQAECgIIAgAAAA==.',
De='Deathfrost:BAAANQABCgMIAwAAAA==.Deathscyth:BAAANQADCggIDAAAAA==.Deceris:BAAANQADCgQIAgAAAA==.Deet:BAAANQADCgMIAwAAAA==.Delsey:BAAANQADCgQICQAAAA==.Demmontaz:BAAANQADCgQIBAAAAA==.Demoní:BAAANQAECgUIBQAAAA==.Demorzz:BAAANQAECgQIDgAAAA==.Deoxis:BAAANQADCgYICwAAAA==.Depdep:BAAANQAECgIIAgAAAA==.Depxy:BAAANQAECgEIAQAAAA==.Dessaju:BAAANQAECgQICAAAAA==.Destia:BAAANQAECgQICgABNQAECgkJJgAEAEMbAA==.Destinyxd:BAABNQAECoEiAAIOAAkJFROlSwBqAgAOAAkJFROlSwBqAgAAAA==.Det:BAAANQAECgUICwAAAA==.Deusgéo:BAAANQADCgEIAQAAAA==.Dexrach:BAAANQABCgMIAwAAAA==.Dexrak:BAAANQAECgUICAAAAA==.',
Dh='Dheka:BAAANQAECgEIAQAAAA==.Dhexts:BAAANQADCgMIAwAAAA==.',
Di='Diaska:BAAANQAECgIIAgAAAA==.Diazmerlyn:BAAANQAECgYIDQAAAA==.Diazo:BAAANQADCgYIDAAAAA==.Didragosa:BAAANQADCgIIAgAAAA==.Diego:BAAANQAECgcIBAAAAA==.Diegodruid:BAAANQAECgUICgAAAA==.Diegolon:BAAANQADCgQICgAAAA==.Diegostorm:BAAANQAECgEIAQAAAA==.Digbingus:BAAANQADCgIIAgAAAA==.Dilaryz:BAAANQADCgEIAgAAAA==.Dinaara:BAAANQADCgUICAAAAA==.Disturbiø:BAAANQAECgEIAQAAAA==.Dizzys:BAAANQADCgIIAgAAAA==.',
Dj='Djmariof:BAAANQAECgUICAAAAA==.',
Dk='Dkescanor:BAAANQAECgUIBwAAAA==.Dkgrisel:BAAANQABCgEIAQAAAA==.Dkingmax:BAAANQADCgQIBgAAAA==.Dklehif:BAAANQAECgEIAQAAAA==.Dkpibara:BAAANQAECgQIBgAAAA==.Dkraris:BAABNQAECoEhAAIPAAcJhBX7JgACAgAPAAcJhBX7JgACAgAAAA==.Dktazz:BAAANQADCgYIBgAAAA==.Dkzero:BAAANQADCgIIAgAAAA==.',
Do='Doblegador:BAAANQADCggICQAAAA==.Doluis:BAAANQADCgMIAwAAAA==.Doote:BAAANQAECgQIBAAAAA==.Dopadoo:BAAANQAECgMIAwAAAA==.Doscuatro:BAAANQADCgUIBAAAAA==.Doucemort:BAAANQADCggIDgAAAA==.Doxtoradh:BAAANQAECgQIBAAAAA==.Doxtorferal:BAAANQADCgYIBgABNQAECgUIDAABAAAAAA==.',
Dp='Dpalas:BAAANQADCgYIBwAAAA==.',
Dr='Draconya:BAAANQADCgYICQAAAA==.Draell:BAAANQADCgYIDAAAAA==.Dragenh:BAABNQAECoEaAAIQAAgJrBZOHgArAgAQAAgJrBZOHgArAgAAAA==.Dragonlight:BAAANQAECgQIBgAAAA==.Dragum:BAAANQAECgMIBwABNQAECgUIDgABAAAAAA==.Drakaelis:BAAANQADCgQIBgAAAA==.Drakalath:BAAANQADCgIIAgABNQADCgQIBgABAAAAAA==.Drakktor:BAAANQAECgQIBQAAAA==.Draknus:BAAANQAECgEIAQAAAA==.Drakths:BAAANQADCgUIBQAAAA==.Dralchukos:BAAANQADCggIGAAAAA==.Drarry:BAAANQAECgUICAAAAA==.Draugcr:BAAANQADCggICAAAAA==.Drekzo:BAAANQADCgYICAAAAA==.Drestroye:BAAANQAECgEIAQAAAA==.Driès:BAAANQADCgQIBAAAAA==.Drkemora:BAAANQADCgMIAwAAAA==.Droshko:BAAANQAECgcIDAABNQAECgkJHQARAOofAA==.Drudnerr:BAAANQAECgEIAwAAAA==.Druidprince:BAAANQAECgIIAgAAAA==.Druidtaz:BAAANQAECgUIBQAAAA==.Dráconiant:BAAANQADCgUICgABNQAECgUICgABAAAAAA==.',
Du='Duduboyito:BAAANQAECgIIBAAAAA==.Duurootar:BAAANQAECgEIAQAAAA==.',
Dw='Dwarfone:BAAANQADCggIEgAAAA==.',
Dz='Dzul:BAAANQADCgIIAgAAAA==.',
['Dä']='Därkässäsin:BAAANQADCgMIAwAAAA==.',
['Dø']='Dønpikin:BAAANQADCgUICQAAAA==.',
['Dü']='Dürtz:BAAANQAECgEIAgAAAA==.',
Eb='Ebanel:BAAANQADCggIEAAAAA==.',
Ec='Eclipsa:BAAANQAECgYIDQAAAA==.Ecofrio:BAAANQADCgcICgAAAA==.',
Ed='Edark:BAAANQAECgEIAQAAAA==.Edusp:BAAANQAECgQICAAAAA==.',
Eg='Egoca:BAAANQADCgEIAQAAAA==.',
Ei='Eiko:BAAANQADCggIEQAAAA==.',
El='Elements:BAAANQADCgMIAwABNQADCggIFgABAAAAAA==.Elentiyaa:BAAANQAECgEIAQAAAA==.Eleonoret:BAAANQAECgIIAgAAAA==.Elguskullu:BAAANQAECgIIAgAAAA==.Elidhana:BAAANQABCgYICwAAAA==.Elk:BAAANQADCggIDgAAAA==.Elkie:BAAANQAECgUICQAAAA==.Ellenai:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.Ellinar:BAAANQAECgQIBgAAAA==.Elohisa:BAAANQADCgYICwAAAA==.Elpolloloco:BAAANQADCgUIBQAAAA==.Elpoyoloco:BAAANQAECgQIBgAAAA==.Elrr:BAAANQABCgUIBQAAAA==.Eltormetias:BAAANQAECgEIAQAAAA==.Eltuerton:BAAANQADCgQIBAAAAA==.Elviraa:BAAANQADCgMIAwAAAA==.Elxadal:BAAANQAECgIIAgAAAA==.Elxochanguas:BAAANQAECgQIBgAAAA==.Elyndræ:BAAANQADCgYICAAAAA==.',
Em='Emersyn:BAAANQADCgYICgAAAA==.Empanizado:BAAANQAECgEIAQAAAA==.',
En='Enror:BAAANQADCgQIBAAAAA==.Enzaro:BAAANQAECgIIAgAAAA==.',
Er='Erectho:BAAANQADCgYICQAAAA==.Erlang:BAAANQAECgUICgAAAA==.Ernendil:BAAANQADCgUIBQAAAA==.',
Es='Escannor:BAAANQADCgUIBQAAAA==.Escanorsama:BAAANQADCgMIAQAAAA==.Esnad:BAAANQAECgcICgAAAA==.',
Eu='Eurìdice:BAAANQAECgIIAgAAAA==.',
Ev='Evilkerzel:BAAANQAECgUICgAAAA==.Evillis:BAAANQAECgMIBQAAAA==.Eviltyra:BAAANQAECgcIEgAAAA==.Evissa:BAAANQAECgMIBwAAAA==.',
Ex='Exado:BAAANQADCgYICAABNQADCggICgABAAAAAA==.Explicits:BAAANQAECgUICgAAAA==.',
Ez='Ezeqeel:BAAANQAECgEIAQAAAA==.Ezti:BAAANQADCgEIAQAAAA==.',
['Eí']='Eísén:BAAANQADCgcIDAAAAA==.',
['Eö']='Eönar:BAAANQAECgcICQAAAA==.',
Fa='Fabifrut:BAAANQAECgQIBAAAAA==.Fakkir:BAAANQAECgQIBwAAAA==.Farat:BAAANQABCgEIAQAAAA==.Fashu:BAAANQADCgYIBgAAAA==.Fayyisaa:BAAANQAECgIIBAAAAA==.',
Fb='Fbk:BAAANQADCgEIAQAAAA==.',
Fe='Felicie:BAAANQADCgYIDQAAAA==.Ferchudoto:BAAANQADCgEIAQAAAA==.Fexmen:BAAANQAECgYIBgAAAA==.Fezal:BAAANQADCgYIBgAAAA==.Feéling:BAAANQAECgEIAQAAAA==.',
Fh='Fhxhs:BAAANQAECgEIAQAAAA==.',
Fi='Fibi:BAAANQADCgQIBAAAAA==.Finheas:BAAANQADCgcIEgAAAA==.Finigas:BAAANQADCgcIBwAAAA==.Fionnæ:BAAANQAECgEIAQAAAA==.Firana:BAAANQADCgQIBAABNQADCgQIBAABAAAAAA==.Fisad:BAAANQADCgcIBwAAAA==.',
Fk='Fkrsrs:BAAANQAECgUIDQAAAA==.',
Fl='Flacapala:BAAANQAECgMICAAAAA==.Flashoflight:BAAANQADCgEIAQAAAA==.Flixiz:BAAANQAECgEIAQAAAA==.',
Fo='Fofitóó:BAAANQADCgEIAQAAAA==.Forasstero:BAAANQAECgIIAgAAAA==.Forkan:BAAANQADCgcIAwAAAA==.',
Fr='Frisad:BAAANQAECgMIBgAAAA==.Frostrike:BAAANQADCgUIBQAAAA==.',
Fu='Fullx:BAAANQADCgQIBgAAAA==.Furrynn:BAAANQAECgEIAQAAAA==.',
['Fä']='Fäenor:BAAANQAECgMIBQAAAA==.',
Ga='Gabitmaru:BAAANQADCgcIBwAAAA==.Gabun:BAAANQADCgQIBAAAAA==.Gabydit:BAAANQAECggIDwAAAA==.Gadito:BAABNQAECoEYAAISAAgJ7yO/AQBLAwASAAgJ7yO/AQBLAwABNQAECgkJIQAFALgjAA==.Galadhriell:BAAANQAECgYIBQAAAA==.Galakrhon:BAAANQAECgQIBAAAAA==.Galletitauwu:BAAANQADCgEIAQAAAA==.Galädriel:BAAANQAECgMIBQAAAA==.Ganttzz:BAAANQAECgQICAAAAA==.Gardner:BAAANQABCgYICgAAAA==.Garkencio:BAAANQAECgMIAwAAAA==.Garrok:BAAANQADCgcIDAAAAA==.Gaspar:BAAANQAECgIIAgAAAA==.Gathodaimon:BAAANQAECgMIAwAAAA==.Gatyto:BAAANQAECgQIBQAAAA==.Gaudy:BAAANQADCgcIDQAAAA==.Gazi:BAAANQAECgQIBAAAAA==.',
Ge='Gemíta:BAAANQAECgIIAgAAAA==.Gerc:BAAANQAECgUICgAAAA==.',
Gh='Ghenk:BAAANQADCgYIBgAAAA==.',
Gi='Giovano:BAAANQADCggIDAAAAA==.Giur:BAAANQAECgUICQAAAA==.',
Gl='Glimdar:BAAANQAECgEIAQAAAA==.Glopis:BAAANQADCgIIAgAAAA==.Glørious:BAAANQAECgMIAwAAAA==.',
Gn='Gnomecholas:BAAANQADCggIDgAAAA==.',
Go='Goge:BAAANQAECgMIBAAAAA==.Gogeta:BAAANQADCgYIBgAAAA==.Gokuderah:BAAANQAECgEIAgAAAA==.Goloh:BAAANQAECgEIAQAAAA==.Gooddrag:BAAANQABCgQIBAAAAA==.Goodlike:BAAANQAECgEIAQAAAA==.Gordeewa:BAAANQAECgIIAgAAAA==.Gordinho:BAAANQAECgYIDAAAAA==.Gordochispas:BAAANQAECgUICAAAAA==.Gosó:BAAANQADCgcIBwAAAA==.Gothdita:BAAANQAECgUICgAAAA==.Gothmog:BAAANQAECgQIBwAAAA==.',
Gr='Grahas:BAAANQADCgEIAQAAAA==.Grandioso:BAAANQADCggICAAAAA==.Grasa:BAAANQADCgcIBwAAAA==.Griethh:BAAANQADCgMIAwAAAA==.Grondy:BAAANQAECgUIDQAAAA==.Grthpaly:BAAANQADCgUIBQAAAA==.Grïsh:BAAANQAECgYIBwAAAA==.',
Gu='Guarmist:BAAANQADCgUICAAAAA==.Guaztarger:BAAANQADCgQIBAAAAA==.Gufren:BAAANQAECgQIBAAAAA==.Guiselle:BAAANQAECgMIBwAAAA==.Gunndalff:BAAANQAECgEIAQAAAA==.Gusfringk:BAAANQADCgcICwAAAA==.Gustavh:BAAANQADCgMIAwAAAA==.Guxue:BAAANQADCgYIDAAAAA==.',
Gw='Gwendevere:BAAANQAECgEIAQAAAA==.',
Gz='Gzlock:BAAANQAECgQIBAAAAA==.',
['Gî']='Gîerig:BAAANQADCgcIBwAAAA==.',
Ha='Haethos:BAAANQAECgQIBQAAAA==.Hajimi:BAAANQAECgQIBgABNQAECgcIDwABAAAAAA==.Hakeshï:BAAANQAECgEIAQAAAA==.Hakumø:BAAANQADCgYIBgAAAA==.Halrinak:BAAANQAECgEIAQAAAA==.Hammernegro:BAAANQADCgUIBQAAAA==.Hanito:BAAANQAECgIIBAAAAA==.Hanku:BAAANQADCgIIAgAAAA==.Happycherry:BAAANQAECgYIEQAAAA==.Harguenn:BAAANQADCgYIBgAAAA==.Harutox:BAAANQAECgEIAQAAAA==.Hashem:BAAANQAECgUICgAAAA==.Hattzune:BAAANQAECgQIBgAAAA==.Hawkay:BAAANQADCgYIEwAAAA==.Haz:BAAANQAECgYICwAAAA==.Hazy:BAAANQAECgYIDAAAAA==.',
He='Healignacio:BAAANQADCgYICgAAAA==.Hecatomb:BAAANQADCgcIBwABNQAECgIIAgABAAAAAA==.Hedblink:BAAANQADCgYICQAAAA==.Hefestor:BAAANQADCgEIAQAAAA==.Heffy:BAAANQADCgYIDwABNQAECgUIBwABAAAAAA==.Heffyd:BAAANQADCgUIBQABNQAECgUIBwABAAAAAA==.Heffyx:BAAANQAECgUIBwAAAA==.Hekan:BAAANQAECgUICAAAAA==.Hellblack:BAAANQADCgUIBQAAAA==.Helsiing:BAAANQADCgYICQAAAA==.Hernagorax:BAAANQAECgEIAQAAAA==.',
Hi='Hierbatero:BAAANQADCgQIAQABNQADCgUIBQABAAAAAA==.Hilyeki:BAAANQADCgQIBAAAAA==.Hiperioon:BAAANQAECgIIAgAAAA==.Hipotérmica:BAAANQABCgQIBgAAAA==.Hisdra:BAAANQAECgIIAgAAAA==.',
Ho='Holoyuta:BAAANQAECgYIDwAAAA==.Holoziru:BAAANQAFFAEIAQAAAA==.Hommerjay:BAAANQAECggIEQAAAA==.Houdax:BAAANQADCgIIAgAAAA==.',
Hu='Hukun:BAAANQADCgMIAwAAAA==.Hunhao:BAAANQADCgUIBgAAAA==.Huntwok:BAAANQADCgYIBgAAAA==.Hurona:BAAANQADCgQIBAAAAA==.Hurrenn:BAAANQADCgMIAwAAAA==.Hurun:BAAANQAECgIIBAAAAA==.',
Hy='Hyiakki:BAAANQADCgMIAwABNQAECgIIAgABAAAAAA==.Hyiâkki:BAAANQAECgIIAgAAAA==.',
['Hí']='Hínatax:BAAANQADCgcIEgAAAA==.',
['Hù']='Hùnterkiller:BAAANQAECgMIAwAAAA==.',
Ia='Iamtenito:BAAANQAECgcICwAAAA==.',
Ic='Icarusa:BAAANQADCgcIDgAAAA==.Iceblockirl:BAAANQAECgQICgAAAA==.',
Ig='Igrisl:BAAANQADCgcICQAAAA==.',
Ik='Ikarik:BAAANQADCgYICgABNQAECgUICwABAAAAAA==.Ikes:BAAANQADCggICAAAAA==.',
Il='Illidaris:BAAANQADCgUIBQAAAA==.',
Im='Imac:BAAANQAECgEIAgAAAA==.Imelda:BAAANQADCgMIAwAAAA==.Imnictus:BAAANQAECgYIDQAAAA==.Impstorm:BAAANQAECgQIBwAAAA==.Imsama:BAAANQADCgUIEwAAAA==.Imthor:BAAANQADCgEIAQAAAA==.Imzeen:BAAANQAECgEIAQAAAA==.',
In='Inguz:BAAANQAECgEIAQAAAA==.Inmörthal:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Innari:BAAANQAECgMIBgAAAA==.Innate:BAAANQADCgUIBQAAAA==.Inquisicion:BAAANQAECgMIAwAAAA==.Invitro:BAAANQADCgEIAQAAAA==.',
Ir='Irenebelse:BAAANQAECgUIDgAAAA==.Ironfaith:BAAANQAECgcIDwAAAA==.',
Is='Issoku:BAAANQAECgIIAgABNQAECgUIDQABAAAAAA==.',
It='Itachila:BAAANQADCgQIBAAAAA==.',
Ja='Jacal:BAAANQAECgIIAgAAAA==.Jackstick:BAAANQAECgMIBAAAAA==.Jair:BAAANQAECgcIDgAAAA==.Jakoda:BAAANQADCgQIBAAAAA==.Jamiroso:BAAANQAECgMIAwAAAA==.Janetla:BAAANQADCggIEwAAAA==.Jarred:BAAANQADCgEIAQAAAA==.Javiëra:BAAANQAECgIIAwAAAA==.',
Je='Jealfredó:BAAANQADCgQIAwAAAA==.Jechas:BAAANQADCgYIBgAAAA==.Jekill:BAAANQADCgQIBAAAAA==.Jelou:BAAANQADCgIIAgAAAA==.Jesús:BAAANQADCgIIAgAAAA==.',
Jh='Jhirek:BAAANQADCgUIBQAAAA==.Jhunal:BAAANQAECgEIAQAAAA==.',
Ji='Jidenm:BAAANQAECgQIBgAAAA==.Jidrix:BAAANQAECgEIAQABNQAECgQICQABAAAAAA==.Jinath:BAAANQADCgMIAwABNQADCgYICQABAAAAAA==.Jingu:BAAANQADCgQIBQAAAA==.Jinjer:BAAANQAECgQIBgABNQAECgQIBwABAAAAAA==.',
Jk='Jkjn:BAAANQADCgMIAwAAAA==.Jkllein:BAAANQAECgMIAwAAAA==.',
Jl='Jlink:BAAANQAECgIIAgAAAA==.',
Jo='Joms:BAAANQAECgEIAgAAAA==.Jonhar:BAAANQADCgYIBwAAAA==.Josemadrazo:BAAANQAECgIIAgAAAA==.Joswar:BAAANQAECgMIBAAAAA==.Joudalf:BAAANQADCgUICQAAAA==.',
Ju='Juanky:BAAANQADCgUIBQAAAA==.Juanow:BAAANQAECgIIAwAAAA==.Juliux:BAAANQAECgEIAQAAAA==.Juraexanime:BAAANQAECgIIAwAAAA==.Jurasickhan:BAAANQADCgMIAwAAAA==.Jurgën:BAAANQADCgIIAgAAAA==.',
Jv='Jvgg:BAAANQADCgYIBgAAAA==.',
Jw='Jwickk:BAAANQADCgYIBgAAAA==.',
Ka='Kaano:BAAANQADCgcICAAAAA==.Kachex:BAAANQADCgIIAgAAAA==.Kachupinsito:BAAANQAECgYIDAAAAA==.Kageru:BAAANQADCgcIDwAAAA==.Kaguire:BAAANQADCggIEAAAAA==.Kahula:BAAANQABCgQIAgAAAA==.Kaiidari:BAAANQAECgUICgAAAA==.Kailink:BAAANQADCgcIBwAAAA==.Kaithar:BAAANQABCgIIAQAAAA==.Kaizenleap:BAAANQADCgYIBgAAAA==.Kalerin:BAAANQADCgUIBwABNQADCggIGAABAAAAAA==.Kalhima:BAAANQADCgUICAABNQAECgEIAQABAAAAAA==.Kaliell:BAAANQADCgQIBAAAAA==.Kalithas:BAAANQAECgQIBgAAAA==.Kalixx:BAAANQADCgUIBQAAAA==.Kaltiro:BAAANQADCgIIAgAAAA==.Kaltozz:BAAANQAECgcIDwAAAA==.Kalyza:BAAANQADCggICgAAAA==.Kamakawiwo:BAAANQADCgMIAwAAAA==.Kamko:BAAANQAECgIIAgAAAA==.Kamuss:BAAANQAECgcIEQAAAA==.Kaníma:BAAANQADCggIGgAAAA==.Karacroft:BAAANQADCgUIBQAAAA==.Karmelin:BAAANQADCgUIAwAAAA==.Kartagus:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.Katakurí:BAAANQADCgEIAQAAAA==.Kazuprime:BAAANQAECgQIDgAAAA==.Kaøri:BAAANQAECgQIBwAAAA==.',
Ke='Kelethir:BAAANQAECgIIAgAAAA==.Kelsir:BAAANQAECgIIAgAAAA==.Keltzhar:BAAANQAECgIIAgAAAA==.Kenia:BAAANQAECgQIBgAAAA==.Keranas:BAAANQADCgQIBgAAAA==.Kerarthas:BAAANQADCgEIAQAAAA==.Kezhu:BAAANQAECgQICAAAAA==.',
Kh='Khamhaleaga:BAAANQAECgIIAgAAAA==.Khaost:BAAANQADCggICAABNQADCggIDAABAAAAAA==.Khelly:BAAANQAECgMIAwAAAA==.Khhalo:BAAANQAECgQIBgAAAA==.Khime:BAAANQADCgUICQAAAA==.Khurisu:BAAANQADCgcIDQAAAA==.Khurysta:BAAANQAECgUICQAAAA==.Khäelth:BAAANQADCggIDAAAAA==.',
Ki='Kienesmarco:BAAANQAECgMIAwAAAA==.Kiillswitch:BAAANQABCggIDQAAAA==.Killercroft:BAAANQADCgUIBQAAAA==.Kintos:BAAANQADCgQIBQAAAA==.Kipura:BAAANQADCgIIAgAAAA==.Kiriotosu:BAAANQADCgYIBgAAAA==.Kittyfer:BAAANQAECgEIAQAAAA==.',
Kj='Kjal:BAAANQADCggIDgAAAA==.',
Kl='Kladune:BAAANQADCgEIAQAAAA==.Klounte:BAAANQADCgIIAgAAAA==.',
Ko='Koblai:BAAANQADCgcIBwAAAA==.Kojiro:BAAANQADCgYIEQAAAA==.Koller:BAAANQADCgMIAwAAAA==.Konha:BAAANQAECgUICgAAAA==.Koriente:BAAANQAECggIDgAAAA==.Korlat:BAAANQADCgcICAAAAA==.Koruchi:BAAANQADCgQIBAAAAA==.Koshkauwu:BAAANQADCgEIAQAAAA==.',
Kr='Kratzio:BAAANQADCggIDgAAAA==.Kresty:BAAANQADCggIEwAAAA==.Krikers:BAAANQADCgQIAgAAAA==.Krocus:BAAANQADCgEIAQAAAA==.Kronio:BAAANQAECgMIBAAAAA==.Krystaluwu:BAAANQADCgQIBgAAAA==.',
Ku='Kukuman:BAAANQADCgEIAQAAAA==.Kungfuupanda:BAAANQADCgIIAgAAAA==.Kunlaoxd:BAAANQAECgQIBAAAAA==.Kuroyamiwow:BAAANQAECgQICQAAAA==.Kuvira:BAAANQADCgcIEQAAAA==.',
Kv='Kv:BAAANQADCgQIAwAAAA==.Kvicha:BAAANQAECgIIAgAAAA==.Kvinprince:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.Kvolthe:BAAANQAECgUICQAAAA==.',
Ky='Kyorî:BAAANQADCgMIAwAAAA==.Kyranthrax:BAAANQADCggIEAAAAA==.Kyraéth:BAAANQADCgYIDAAAAA==.',
['Kí']='Kíller:BAAANQADCgcICAAAAA==.',
['Kø']='Køa:BAAANQADCgYICQAAAA==.',
La='Labambaa:BAAANQAECgUICgAAAA==.Laboons:BAAANQADCgEIAQAAAA==.Lacuba:BAAANQADCgIIAgAAAA==.Ladroga:BAAANQADCgYICAAAAA==.Laeroth:BAAANQABCgMIAgAAAA==.Lafieroski:BAAANQADCgIIBAAAAA==.Lafoxi:BAAANQADCgQIBAABNQADCgUIBwABAAAAAA==.Laheeja:BAAANQADCggIDQAAAA==.Laidlynegrit:BAAANQAECgUIBQAAAA==.Laidlywormpa:BAAANQAECgEIAQAAAA==.Lakungfusión:BAAANQADCgYICgAAAA==.Lanuda:BAAANQAECgQIBAAAAA==.Lardelx:BAAANQAECgEIAQAAAA==.Lastorc:BAAANQADCgUIBgAAAA==.Lastwärrior:BAAANQAECgcIEwAAAA==.Latrasil:BAAANQADCgYIBgABNQAECgYIDQABAAAAAA==.Lavacabacana:BAAANQAECgYICAAAAA==.Lavalock:BAAANQADCgYIBgAAAA==.',
Le='Leamblue:BAAANQADCgYICQAAAA==.Lebombas:BAAANQAECgIIBAAAAA==.Lechushm:BAAANQADCgIIAgAAAA==.Leiah:BAAANQADCgQICAAAAA==.Lemuria:BAAANQADCgQIBgAAAA==.Lená:BAAANQADCggICAAAAA==.Lenøre:BAAANQAECgQIBQAAAA==.Leomonx:BAAANQAECgQICAABNQAECgcICQABAAAAAA==.Leongrox:BAAANQAECgEIAQAAAA==.Leopoldonx:BAAANQAECgQIAgAAAA==.Letu:BAAANQADCgMIAwAAAA==.Letø:BAAANQAECgIIAgAAAA==.Leviastús:BAAANQAECgYICwAAAA==.Leviattán:BAAANQADCgEIAQAAAA==.Leömön:BAAANQAECgQIBAABNQAECgcICQABAAAAAA==.',
Lh='Lhukan:BAAANQAECgYICwAAAA==.Lhura:BAAANQAECgMIBAAAAA==.',
Li='Liacachetona:BAAANQADCgQIBAAAAA==.Libi:BAAANQADCgUIBQAAAA==.Lichpaw:BAAANQADCgQIBAAAAA==.Lightjandra:BAAANQADCgcIFQAAAA==.Lilea:BAAANQAECgIIAwAAAA==.Lilithuchuan:BAAANQAECgEIAQAAAA==.Lillean:BAAANQADCgIIAgAAAA==.Lilspark:BAAANQADCgcIBwABNQAECgQICAABAAAAAA==.Limcross:BAAANQADCgUIBwAAAA==.Limeña:BAAANQAECgQIBQAAAA==.Lindabb:BAAANQADCgQIBAAAAA==.Lindurita:BAAANQADCgEIAQAAAA==.Linkz:BAAANQADCggIFAAAAA==.Linnea:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.Lios:BAAANQAECgEIAgAAAA==.Lipus:BAAANQAECgMIBQAAAA==.Litts:BAAANQADCgQIBQAAAA==.',
Ll='Llerenakun:BAAANQABCgYICQAAAA==.',
Lo='Loabol:BAAANQAECgQIBAAAAA==.Lobillodk:BAAANQAECgQICAABNQAECgUIDgABAAAAAA==.Loboloko:BAAANQAECgEIAQAAAA==.Lochupontero:BAAANQADCgEIAQAAAA==.Lokani:BAAANQADCgcIBwAAAA==.Lostpower:BAAANQAECgUICQAAAA==.Lothbruner:BAAANQADCggICAAAAA==.',
Ls='Lsserafim:BAAANQABCgQIBAAAAA==.',
Lt='Lt:BAAANQADCgUIBAAAAA==.',
Lu='Lubb:BAAANQAECgQIBAAAAA==.Lubye:BAAANQADCgEIAQAAAA==.Lucandlere:BAAANQADCgQIBAAAAA==.Luchosanlore:BAAANQADCgIIAgAAAA==.Lucret:BAAANQADCgMIAwAAAA==.Luggubre:BAABNQAECoEWAAIFAAcJWiCTLQBXAgAFAAcJWiCTLQBXAgAAAA==.Luisaacg:BAAANQADCgMIAwAAAA==.Luisitoxx:BAAANQAECgEIAQAAAA==.Lumis:BAAANQAECgMIAwAAAA==.Lumiére:BAAANQABCgEIAQAAAA==.Lunainverse:BAAANQADCgQIBAAAAA==.Lupùs:BAAANQADCgYIDAABNQADCggICgABAAAAAA==.Lusitanian:BAAANQAECgYICwAAAA==.Lusyan:BAAANQADCgIIAgAAAA==.Luxiien:BAAANQAECgcIDgAAAA==.',
Lx='Lxa:BAAANQAECgMIAwAAAA==.Lxmrcheesexl:BAAANQAECgQIDAAAAA==.',
['Lá']='Lást:BAAANQAECgQIBwAAAA==.',
['Lé']='Léonel:BAAANQAECgQIBwAAAA==.',
['Lë']='Lëomon:BAAANQAECgcICQAAAA==.',
['Lì']='Lìlíth:BAAANQAECgEIAgAAAA==.',
['Lú']='Lúmiere:BAAANQADCgcIDgAAAA==.Lúriza:BAAANQAECgEIAQAAAA==.Lúthién:BAAANQAECgMIAgAAAA==.',
Ma='Mabilomi:BAAANQADCgUIBgAAAA==.Macdonal:BAAANQADCggIDgAAAA==.Macklein:BAAANQAECgIIAgAAAA==.Madeleyn:BAAANQADCgIIAgAAAA==.Madhunt:BAAANQAECgcICAAAAA==.Madwin:BAAANQAECgQIBAAAAA==.Maffo:BAAANQAECgUICAAAAA==.Mafufa:BAAANQADCgEIAQAAAA==.Magikall:BAAANQAECgMIAwAAAA==.Magoloco:BAAANQABCgQIBAAAAA==.Makatraka:BAAANQADCgQIBAAAAA==.Maker:BAAANQAECgEIAQAAAA==.Makodra:BAAANQAECgUICwAAAA==.Malakaí:BAAANQADCgYIDgAAAA==.Maldrux:BAAANQAECgYIDAAAAA==.Malefør:BAAANQADCgUICgAAAA==.Malextrasa:BAABNQAECoEdAAITAAkJ4ByADAABAwATAAkJ4ByADAABAwAAAA==.Malkrim:BAAANQAECgQICAAAAA==.Malènia:BAAANQAECgQIBAAAAA==.Manamonk:BAAANQADCgYICgAAAA==.Manatz:BAAANQADCgYIBgABNQAECgUIBgABAAAAAA==.Mancokapak:BAAANQABCgQIBAAAAA==.Mandredivh:BAAANQADCggIGgAAAA==.Mannat:BAAANQAECgUIBgAAAA==.Maomao:BAAANQADCgcIBwAAAA==.Margrace:BAAANQADCggIEAAAAA==.Margys:BAAANQAECgEIAQABNQAECgQICQABAAAAAA==.Maripxd:BAAANQAECgEIAQAAAA==.Mariána:BAAANQAECgUIBgAAAA==.Marlenor:BAAANQAECgEIAQAAAA==.Marusita:BAAANQADCggIDAAAAA==.Matusalix:BAAANQADCgYIEQAAAA==.Maynard:BAAANQAECgIIAgABNQAECgkJGwATAHQbAA==.',
Md='Mddemon:BAAANQAECgEIAQABNQAECgcICAABAAAAAA==.Mdlock:BAAANQAECgIIAwABNQAECgcICAABAAAAAA==.Mdmague:BAAANQAECgcICAAAAA==.',
Me='Medaly:BAAANQAECgUICQAAAA==.Mediff:BAAANQAECgIIAgAAAA==.Meerle:BAAANQADCgQIBAAAAA==.Meiimeii:BAAANQADCgEIAQAAAA==.Meinxia:BAAANQAECgQIBgAAAA==.Melhí:BAAANQADCgQICAABNQAECgkJHQAEAIEWAA==.Melianor:BAAANQAECgEIAQAAAA==.Melisandree:BAAANQADCgQIBAAAAA==.Mellk:BAAANQAECgQICAAAAA==.Melok:BAAANQAECgYIDwAAAA==.Memerln:BAAANQADCggICAAAAA==.Menieblas:BAAANQAECgMIBQAAAA==.Meraxez:BAAANQADCggICAAAAA==.Merlindar:BAAANQADCgQIBAAAAA==.Meruru:BAAANQAECgEIAQAAAA==.Messier:BAAANQADCgUIBQAAAA==.Messir:BAAANQADCgUIAwABNQADCgUICQABAAAAAA==.Metalmilitia:BAAANQADCggIEQAAAA==.Metalsickdos:BAAANQAECgEIAQAAAA==.',
Mi='Migajera:BAAANQAECgQICwABNQAECgkJGQACABgZAA==.Migatteluca:BAAANQADCgUIBgABNQAECgUICwABAAAAAA==.Migui:BAAANQADCgYICAAAAA==.Miimoss:BAAANQADCgUIBQAAAA==.Mikalau:BAAANQADCggIFAAAAA==.Mikku:BAAANQADCgIIAgAAAA==.Milkmom:BAAANQADCgYIBgAAAA==.Millyse:BAAANQADCgYIBgAAAA==.Minichoco:BAAANQAECgMIAwABNQAECgUICwABAAAAAA==.Minno:BAAANQAECgUICwAAAA==.Miréi:BAAANQADCgEIAQAAAA==.Mithaly:BAAANQAECgQIBwAAAA==.Miwixds:BAAANQADCggIFQAAAA==.',
Mo='Moctecuzuma:BAAANQADCgEIAQAAAA==.Moctex:BAAANQAECgEIAQAAAA==.Moguulkhan:BAAANQAECgEIAQAAAA==.Moirainekir:BAAANQAECgUICAAAAA==.Momongaa:BAAANQAECgQIBgAAAA==.Monako:BAAANQAECgUICQAAAA==.Monstrenco:BAAANQADCgUIBQABNQAECgYIDAABAAAAAA==.Monthana:BAAANQAECgEIAQAAAA==.Moobit:BAAANQAECgQIBwAAAA==.Moonbay:BAAANQADCgMIBAAAAA==.Moonfyre:BAAANQAECgUICwAAAA==.Mortrono:BAAANQAECgUICwAAAA==.Mortís:BAAANQADCgEIAQAAAA==.Motomámi:BAAANQADCgIIAgAAAA==.Moóncry:BAAANQAECgUIDAAAAA==.Moüt:BAAANQADCgEIAQAAAA==.',
Ms='Msoujiro:BAAANQAECgMIAwAAAA==.',
Mu='Mugichwan:BAAANQAECgIIAwAAAA==.Muguettzu:BAAANQADCgQIBgAAAA==.Mullicundo:BAAANQADCgcIBwAAAA==.Muthechien:BAAANQAECgEIAQAAAA==.Muydeseado:BAAANQAECgYIDQAAAA==.',
My='Mykeks:BAAANQAECgUIDgAAAA==.',
['Má']='Máyá:BAAANQAECgIIAgAAAA==.',
['Mä']='Mässo:BAAANQAECgcIDQAAAA==.',
['Mé']='Mén:BAAANQAECgQIBwAAAA==.',
['Mï']='Mïtch:BAAANQAECgIIAwAAAA==.',
['Mö']='Mönkas:BAAANQAECgUICAAAAA==.',
['Mø']='Møzartt:BAAANQADCgEIAQABNQAECgYIBgABAAAAAA==.',
Na='Nadhil:BAAANQADCgQIBAAAAA==.Nadyia:BAAANQABCgMIAwAAAA==.Nanod:BAAANQADCggICwAAAA==.Naonak:BAAANQAECgUICgAAAA==.Nardàl:BAAANQADCgEIAQAAAA==.Narieda:BAAANQAECgMIBQAAAA==.Narumí:BAAANQAECgYICwAAAA==.Naturalfiend:BAAANQAECgMIAwAAAA==.Naught:BAAANQAECgUIDQABNQADCgUICQABAAAAAA==.Naviri:BAAANQAECgIIAgAAAA==.Naxospyro:BAAANQAECgUICAAAAA==.Naxxoll:BAABNQAECoEaAAIOAAgJcyB+KgDnAgAOAAgJcyB+KgDnAgAAAA==.',
Ne='Necrazar:BAAANQADCgIIAgAAAA==.Necrodex:BAAANQAECgQICAAAAA==.Necroseil:BAAANQAECgYIBwAAAA==.Neeloc:BAAANQAECgQIBgAAAA==.Nefële:BAAANQAECgYIDwAAAA==.Nelwolf:BAAANQAECgQIBgAAAA==.Nemeroth:BAAANQADCgYICAAAAA==.Nenéx:BAAANQADCgMIAwABNQAECgQIDgABAAAAAA==.Nephen:BAAANQADCgYICAAAAA==.Neroonn:BAAANQAECgYICgAAAA==.Nesbitsan:BAAANQADCggIEQAAAA==.Netero:BAAANQAECgEIAQAAAA==.Netop:BAAANQAECgQICQAAAA==.Netspider:BAAANQADCgQIBAAAAA==.Nevitszaid:BAAANQAECgYIDQAAAA==.',
Nh='Nhami:BAAANQADCgEIAQAAAA==.Nhan:BAAANQADCgEIAQAAAA==.',
Ni='Nibelunge:BAAANQADCgYIGAAAAA==.Nicann:BAAANQAECgEIAQAAAA==.Niceflaca:BAAANQADCggIEgAAAA==.Nicholle:BAAANQADCgIIAgAAAA==.Nicolius:BAAANQAECgIIAgAAAA==.Nicolocho:BAAANQADCgUIBQAAAA==.Nikama:BAAANQAECgUICgAAAA==.Nikisuga:BAAANQADCgUIAwAAAA==.Nikoflen:BAAANQAECgEIAQAAAA==.Nikolaz:BAAANQAECgEIAgAAAA==.Nilhatak:BAAANQAECgUICwAAAA==.Niloo:BAAANQAECgEIAQAAAA==.Nirviil:BAAANQADCgcIBwAAAA==.',
No='Nocthaelis:BAAANQADCgQIAgAAAA==.Noctiria:BAAANQADCgQIBAAAAA==.Nogarmonia:BAAANQAECgEIAQAAAA==.Noicanicula:BAAANQADCgEIAQAAAA==.Novacool:BAAANQAECgEIAQAAAA==.Novarah:BAAANQADCgMIAwAAAA==.Nozghod:BAAANQADCgQIBAAAAA==.',
Nu='Nueth:BAAANQADCggICAAAAA==.',
Ny='Nykstorm:BAAANQAECgQIBQAAAA==.Nyler:BAAANQADCgcIBwAAAA==.Nyyrikkii:BAAANQAECgUICAAAAA==.',
['Næ']='Næoko:BAAANQAECgMIAwAAAA==.',
['Né']='Némesiss:BAAANQADCgcICwAAAA==.',
['Nø']='Nøstradamuz:BAAANQADCggIDwAAAA==.',
Oc='Occultus:BAAANQAECgYIDQAAAA==.',
Od='Odelyx:BAAANQADCgEIAQAAAA==.Odiseuz:BAAANQADCgYIBgABNQADCgYIBgABAAAAAA==.',
Of='Offsham:BAAANQAECgQIBgABNQAECgQICAABAAAAAA==.',
Og='Oggus:BAAANQAECgQIBgAAAA==.',
Ol='Olaznog:BAAANQADCgcIDAAAAA==.Olddirtybtr:BAAANQAECgQIBAAAAA==.Olidi:BAAANQAECgIIAgABNQAECgcIEQABAAAAAA==.Oligisto:BAAANQAECgUIBgAAAA==.',
On='Ondro:BAAANQADCgQIBAAAAA==.Onirial:BAAANQADCgQIBAAAAA==.Onugem:BAAANQAECgIIAgAAAA==.',
Op='Oppenheimar:BAAANQADCgUIDQAAAA==.Opusdiáboli:BAAANQADCgYICQAAAA==.',
Or='Orangë:BAAANQADCggIEAAAAA==.Orchidd:BAAANQAECgUIDwAAAA==.Originalsoul:BAAANQAECgQIBQAAAA==.Orihimie:BAAANQADCgYIBgAAAA==.Ortesd:BAAANQADCgYIDgAAAA==.',
Os='Osamdi:BAAANQADCgUIBQAAAA==.Osaurus:BAAANQABCgIIAgAAAA==.Osen:BAAANQAECgQIBAAAAA==.',
Ot='Oterö:BAAANQAECgEIAQAAAA==.Ottisra:BAAANQADCggIDQAAAA==.',
Ou='Ouran:BAAANQADCgMIAwAAAA==.',
Ow='Owvudú:BAAANQADCggICAAAAA==.',
Ox='Oxii:BAAANQAECgcICgAAAA==.',
Oz='Ozlem:BAAANQADCgcICQAAAA==.Ozzur:BAAANQAECgcIDwAAAA==.',
Pa='Pablog:BAAANQADCgQIAQAAAA==.Pairo:BAABNQAECoEaAAIPAAgJbxDrJAARAgAPAAgJbxDrJAARAgABNQAECgkJHQARAOofAA==.Pajarraco:BAAANQABCgIIAgAAAA==.Palabray:BAAANQADCgUIBQAAAA==.Palabxy:BAAANQADCgQIBAAAAA==.Palamba:BAAANQADCgQIAQAAAA==.Palasino:BAAANQAECgMIAwAAAA==.Palatass:BAAANQAECgQICAAAAA==.Pallyez:BAAANQAECgIIAgABNQAECgIIBAABAAAAAA==.Panchite:BAAANQADCggICAAAAA==.Pandefrica:BAAANQADCgcIDQABNQAECgUIDQABAAAAAA==.Pandepascuas:BAAANQAECgUIDQAAAA==.Panditaninja:BAAANQAECgIIAgAAAA==.Pandochurro:BAAANQADCgUICAAAAA==.Pandrös:BAABNQAECoEdAAIRAAkJ6h/RBAA7AwARAAkJ6h/RBAA7AwAAAA==.Pandurian:BAAANQAECgYICAAAAA==.Panjitinik:BAAANQADCgYIBgAAAA==.Panndii:BAAANQADCgMIAwAAAA==.Panxing:BAAANQADCgIIAgAAAA==.Papabrava:BAAANQADCgQIBAABNQAECgUIBgABAAAAAA==.Papasote:BAAANQADCggIFgAAAA==.Papibardockk:BAAANQADCgMIAwAAAA==.Paquin:BAAANQAFFAEIAQAAAA==.Parcum:BAAANQADCgYIBgAAAA==.Parkka:BAAANQADCgYIDgAAAA==.Patsii:BAAANQADCgEIAQAAAA==.Pauljosue:BAAANQAECgQIBQAAAA==.',
Pd='Pdza:BAAANQADCggIGQAAAA==.',
Pe='Pelluk:BAAANQAECgMIAgAAAA==.Pencilgon:BAAANQADCgUIEwAAAA==.Pentauret:BAAANQADCgYIBAAAAA==.Pepeledudu:BAAANQADCgcIBwAAAA==.Pepitaa:BAAANQAECgYIDgAAAA==.Perrucha:BAAANQADCgEIAQAAAA==.Petricita:BAAANQADCgUIAwAAAA==.Petunia:BAAANQADCggIDgAAAA==.',
Ph='Pheebes:BAAANQADCgYIBgAAAA==.',
Pi='Picklesacred:BAABNQAECoEaAAMFAAgJARZPRADmAQAFAAcJDBdPRADmAQAUAAEJsw5TPgAtAAAAAA==.Pipila:BAAANQADCgQIBAAAAA==.Pishtakito:BAAANQADCgMIAwAAAA==.',
Pk='Pkoo:BAAANQAECgQICAAAAA==.',
Pl='Plac:BAAANQADCgQIBAAAAA==.Plapaya:BAAANQADCgUIBQAAAA==.Playpaya:BAAANQADCgYIBwAAAA==.Plsaleml:BAAANQADCgYICgAAAA==.',
Pm='Pmanar:BAAANQADCgQIBAAAAA==.',
Po='Polárize:BAAANQADCgUIBgAAAA==.Pompoh:BAAANQAECgIIBAAAAA==.Pontecorvo:BAAANQADCgEIAQAAAA==.Porrita:BAAANQAECgIIAwAAAA==.',
Pp='Ppeltauren:BAAANQADCggIEgAAAA==.Pprincesa:BAAANQADCgUICAAAAA==.',
Pr='Prominens:BAAANQAECgIIAgAAAA==.',
Py='Pyngon:BAAANQAECgMIBgAAAA==.',
['Pà']='Pàolá:BAAANQAECgEIAQAAAA==.',
['Pä']='Pädme:BAAANQAECgUICAAAAA==.',
['Pï']='Pïer:BAAANQADCggIDQAAAA==.',
['Pó']='Póntius:BAAANQAECgYIBwAAAA==.',
Qi='Qinshihuangt:BAAANQAECgIIAgAAAA==.',
Ql='Qliado:BAAANQADCgQIBgAAAA==.',
Qt='Qtaurentino:BAAANQAECgUICgAAAA==.',
Qu='Quarantine:BAAANQAECgYIDwAAAA==.Qubb:BAAANQAECggIDAAAAA==.Queldales:BAAANQADCgYIBQAAAA==.Querubinz:BAAANQADCgIIAwAAAA==.Quetzaliztli:BAAANQADCgcIBwAAAA==.Quinasa:BAAANQAECgEIAQAAAA==.Quingg:BAAANQAECgQIBAAAAA==.',
['Qñ']='Qñado:BAAANQADCgIIAwAAAA==.',
Ra='Radagas:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Radagasst:BAAANQAECgQIBAABNQAECgcIDwABAAAAAA==.Raddek:BAAANQADCgIIAgAAAA==.Radiance:BAAANQAECgMIAwAAAA==.Raenyx:BAAANQADCgIIAgABNQAECgYIDwABAAAAAA==.Rahemm:BAAANQAECgYIDQAAAA==.Rakasha:BAAANQADCgQIBAAAAA==.Raknar:BAAANQAECgEIAQAAAA==.Ramasheka:BAAANQAECgQIBwAAAA==.Randester:BAAANQAECgcIEQAAAA==.Ranzhu:BAAANQADCgEIAQAAAA==.Raphiki:BAAANQADCgYIDQAAAA==.Rasky:BAAANQAECgEIAQAAAA==.Ratann:BAAANQADCgcIBwAAAA==.Ravaena:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Rawalejandro:BAAANQAECgUICwAAAA==.Raxfor:BAAANQADCgUIBQAAAA==.Raynorfx:BAAANQADCgYIBgAAAA==.Raìzen:BAAANQADCgQIBAAAAA==.',
Re='Reavdud:BAAANQADCgQIBAAAAA==.Rebor:BAAANQADCgIIAwAAAA==.Recogemonte:BAAANQADCgYICAAAAA==.Redjar:BAAANQADCgYIEgAAAA==.Redspirit:BAAANQADCgUIAwAAAA==.Reexyoids:BAAANQAECgEIAQAAAA==.Reliah:BAAANQADCggIEQAAAA==.Relocosxd:BAAANQADCgEIAQAAAA==.Remyy:BAAANQADCggIDgABNQAECgQICwABAAAAAA==.Rendel:BAAANQADCgUIBQAAAA==.Renkhor:BAAANQADCgUIBQAAAA==.Reumanic:BAAANQAECgIIAgAAAA==.Rexdraconum:BAAANQAECgQIBwAAAA==.Rexxona:BAAANQABCgIIAgAAAA==.',
Rh='Rhaegn:BAAANQAECgIIAwAAAA==.Rhayza:BAAANQADCgMIAwABNQAECgYICQABAAAAAA==.Rhayzadk:BAAANQAECgYICQAAAA==.Rhazty:BAAANQADCgUIEgAAAA==.Rhea:BAAANQADCgQIBAAAAA==.Rhis:BAAANQADCgUIBQAAAA==.Rhiska:BAAANQADCgYIBgAAAA==.Rhyper:BAAANQAECgYIEwAAAA==.Rhyperiork:BAAANQAECgIIAgAAAA==.Rhäenyrä:BAAANQADCgYICQAAAA==.',
Ri='Ricketz:BAAANQAECgUICQAAAA==.Rickygf:BAAANQADCgMIAwAAAA==.Riderless:BAAANQADCggIEAAAAA==.Rikudoü:BAAANQAECgUIBQAAAA==.Rikuo:BAAANQAECgUICQAAAA==.Rinhosizora:BAAANQAECgUICQABNQAECgYIDQABAAAAAA==.Rintkun:BAAANQADCgQIBAAAAA==.Riotszen:BAAANQAECgQIBAAAAA==.Rizoman:BAAANQADCgQIBAAAAA==.',
Ro='Road:BAAANQADCgcIBwAAAA==.Roadcm:BAAANQADCgQIBwABNQADCgcIBwABAAAAAA==.Robattangas:BAAANQAECgUIBQAAAA==.Rockblacki:BAAANQAECgMIBgAAAA==.Rocklets:BAAANQADCgEIAQAAAA==.Rompektrës:BAAANQAECgIIAgAAAA==.Rondarousey:BAAANQAECgEIAQAAAA==.Ronstreet:BAAANQAECgEIAgAAAA==.Ronín:BAAANQADCgYIBgAAAA==.Rotls:BAAANQAECgYICwAAAA==.Roup:BAAANQADCgEIAQAAAA==.Roweenn:BAAANQADCgQIBAAAAA==.',
Ru='Rugal:BAAANQAECgUICQAAAA==.Rusinante:BAAANQAECgYIDAAAAA==.',
Ry='Ryuugan:BAAANQADCgQIBAABNQADCggIEgABAAAAAA==.',
['Rá']='Rámzx:BAAANQAECgMIBQAAAA==.',
['Rä']='Räx:BAAANQADCgMIBAAAAA==.',
['Rë']='Rëmbrandt:BAAANQAECgEIAQAAAA==.',
Sa='Sabriluisa:BAAANQAECgIIAgAAAA==.Sacredfire:BAAANQADCgEIAQAAAA==.Safetyman:BAAANQADCgMIAwAAAA==.Saintgermain:BAAANQAECgQIBAAAAA==.Saiphorionis:BAAANQAECgUICQABNQAECgcICQABAAAAAA==.Saknu:BAAANQADCgEIAQAAAA==.Salginteer:BAAANQADCgMIAwAAAA==.Salvi:BAAANQADCggIGgAAAA==.Samb:BAAANQAECgQIBAAAAA==.Samluck:BAAANQADCgUICQAAAA==.Sammwar:BAAANQAECgYIDwAAAA==.Sanchin:BAAANQADCgUIBgABNQAECgUIDgABAAAAAA==.Sanghot:BAAANQADCggIDAAAAA==.Sangreschwar:BAAANQAECgEIAQAAAA==.Sanguiiniuz:BAAANQADCgMIAwAAAA==.Sanmuertin:BAAANQAECgQICAAAAA==.Sanndir:BAAANQAECgUICQAAAA==.Santified:BAAANQAECgIIAgAAAA==.Sapixi:BAAANQAECgQICwAAAA==.Sapphi:BAAANQADCggIDgAAAA==.Sardak:BAAANQADCggIEAAAAA==.Saria:BAAANQAECgYIDQAAAA==.Sasocas:BAAANQAECgQIBAAAAA==.Saurona:BAAANQADCgUICAAAAA==.Saycox:BAAANQAECggIDAAAAA==.Sayrén:BAAANQAECgEIAQAAAA==.',
Sc='Scanx:BAABNQAECoEbAAITAAkJdBvYGACPAgATAAkJdBvYGACPAgAAAA==.Scarmesh:BAAANQAECgQIBgAAAA==.Scavenge:BAAANQADCgEIAQAAAA==.Schamanco:BAAANQADCgYICAAAAA==.Schicksal:BAAANQADCgQIBAAAAA==.',
Se='Sebvz:BAAANQAECgUIDQAAAA==.Seejmet:BAAANQADCgEIAQAAAA==.Sefmer:BAAANQADCgYIBgAAAA==.Seguridad:BAAANQADCgYICQAAAA==.Seleka:BAAANQADCgcIAgAAAA==.Selle:BAAANQADCgIIAgAAAA==.Seneget:BAAANQADCgUIBQAAAA==.Senjib:BAABNQAECoEaAAIVAAkJDBaBCgCPAgAVAAkJDBaBCgCPAgAAAA==.Sentryx:BAAANQAECgIIAgAAAA==.Serhi:BAAANQADCgUIBQAAAA==.Serock:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Serotonin:BAABNQAECoEgAAIWAAkJdSKBAQCDAwAWAAkJdSKBAQCDAwAAAA==.Seshomarux:BAAANQAECgEIAQAAAA==.',
Sg='Sgaray:BAAANQADCgMIAwAAAA==.',
Sh='Shaders:BAAANQADCgQIBQABNQAECgkJHQAFANUgAA==.Shadito:BAAANQAECgQIBQAAAA==.Shadoweak:BAAANQADCgUIBQABNQAECgcIDwABAAAAAA==.Shagu:BAAANQADCgQIBAAAAA==.Shamanin:BAAANQADCgUIBQAAAA==.Shameco:BAAANQADCgcIEAAAAA==.Shamyto:BAAANQAECgEIAQAAAA==.Shanan:BAAANQAECgUICQAAAA==.Shelox:BAAANQAECgMIAwAAAA==.Shermy:BAAANQADCggICQAAAA==.Sheytocaru:BAAANQADCgcIBwAAAA==.Shibamiyuki:BAAANQAECgMIBQAAAA==.Shigarakicam:BAAANQAECgUIDQAAAA==.Shiinosuke:BAAANQAECgEIAQAAAA==.Shimuu:BAAANQADCggICAAAAA==.Shinoshibi:BAAANQAECgEIAQAAAA==.Shirvallah:BAAANQADCgcIDwAAAA==.Shizaberu:BAAANQADCgYIDgAAAA==.Shmebuloçk:BAAANQAECgIIAQAAAA==.Shokey:BAAANQADCgEIAQAAAA==.Sholva:BAAANQADCgMIAwAAAA==.Shurien:BAAANQAECgUIBgAAAA==.Shushinn:BAAANQAECgcICwAAAA==.Shusui:BAAANQAECgEIAQAAAA==.Shälash:BAAANQADCgQIBAAAAA==.',
Si='Sicarío:BAAANQADCgYICQAAAA==.Siebzehn:BAAANQADCgEIAQAAAA==.Sieges:BAAANQAECgQIBgAAAA==.Sigrin:BAAANQAECgQIBAABNQAECgkJHQAHAOgeAA==.Silverkiller:BAAANQAECgQIBgAAAA==.Silvérwolf:BAAANQADCgQIBQAAAA==.Simoohayha:BAAANQAECgQICgAAAA==.Sisifox:BAAANQADCgQIBAAAAA==.',
Sk='Skhiper:BAAANQADCgQIBAAAAA==.Skinhunter:BAAANQAECgIIAgAAAA==.Sklother:BAAANQAECgEIAgABNQAECggIEgABAAAAAA==.Skylow:BAAANQAECgQICAAAAA==.Skyréss:BAAANQADCgYIBgAAAA==.',
Sm='Smaul:BAAANQADCgUIBQAAAA==.',
Sn='Snad:BAAANQAECgQIBwABNQAECgcICgABAAAAAA==.Snikerflitzz:BAAANQADCgUIBQAAAA==.Snoobdogg:BAAANQADCgUIBQAAAA==.',
So='Sochiee:BAAANQADCgEIAQAAAA==.Sofënox:BAAANQADCgQIAgAAAA==.Solaniin:BAAANQAECgQIDgAAAA==.Sommermage:BAAANQAECgMIAwAAAA==.Sommerwalker:BAAANQADCgYIEQAAAA==.Sonadow:BAAANQAECgQIBAABNQAECgUICAABAAAAAA==.Sonbej:BAAANQAECgUIDAABNQAECgkJGgAVAAwWAA==.Soogx:BAAANQAECgEIAQAAAA==.Sopaipiya:BAAANQAECgQIBQAAAA==.Souling:BAAANQADCggICAAAAA==.Soulèater:BAAANQADCgUICAAAAA==.Soyuno:BAAANQADCgcICgAAAA==.',
Sp='Spacemage:BAABNQAECoEkAAIOAAkJnCF1DQB4AwAOAAkJnCF1DQB4AwAAAA==.Spacerm:BAAANQADCgIIAgABNQAECgkJJAAOAJwhAA==.Spacerogue:BAAANQADCgYIBgABNQAECgkJJAAOAJwhAA==.Speedyarrow:BAAANQADCgQIBAAAAA==.Spêctrê:BAAANQADCgEIAQAAAA==.',
Sq='Sqlote:BAAANQADCgQIBAAAAA==.',
Sr='Srfelix:BAAANQADCgQIBgAAAA==.Srjusticia:BAAANQADCgUIBwAAAA==.Srsquishs:BAAANQADCgIIAgAAAA==.Srwea:BAAANQADCgYIBwAAAA==.',
Ss='Sskiper:BAAANQAECgYIDgAAAA==.',
St='Stalinsky:BAAANQAECgUICgAAAA==.Staraptor:BAAANQAECgUIBQAAAA==.Starkarya:BAAANQAECgMIBQAAAA==.Starsky:BAAANQADCgIIAgAAAA==.Starspawn:BAAANQAECgIIAgAAAA==.Stet:BAAANQADCggICAAAAA==.Stonnex:BAAANQAECgIIAgAAAA==.Stormyr:BAAANQADCgMIAwAAAA==.Stríga:BAAANQADCgcIBwAAAA==.Stârlight:BAAANQAECgMIBAAAAA==.',
Su='Sucarita:BAAANQADCgcIDQAAAA==.Suhyokaa:BAAANQADCggIEQAAAA==.Sukaritas:BAAANQAECgEIAQAAAA==.Sumäq:BAAANQAECgMIBAAAAA==.Sunelfdnns:BAAANQAECgIIAgAAAA==.Sunfyre:BAAANQADCgEIAQAAAA==.Sunner:BAAANQADCgYIBgAAAA==.Supre:BAAANQAECgYICgAAAA==.Sutraxu:BAAANQADCgIIAQAAAA==.',
Sv='Svyatogor:BAAANQADCgIIAgAAAA==.',
Sw='Swindler:BAAANQAECgMIAwAAAA==.',
Sy='Sylvanderb:BAAANQADCgUIBQAAAA==.',
['Sâ']='Sâcrilegio:BAABNQAECoEhAAIFAAkJuCMcBgCVAwAFAAkJuCMcBgCVAwAAAA==.',
['Sî']='Sîxtecó:BAAANQAECgYICwAAAA==.',
['Sö']='Sökrates:BAAANQAECgYICQAAAA==.',
Ta='Tadashï:BAAANQADCggICAAAAA==.Tahun:BAAANQAECgQIBgAAAA==.Tailerx:BAAANQADCgQIBAAAAA==.Takachy:BAAANQAECgQIBAAAAA==.Talarøn:BAAANQAECgEIAQAAAA==.Talématros:BAAANQAECgMIAwAAAA==.Tarruo:BAAANQAECgMIAwAAAA==.Tasjon:BAAANQAECgYIDQAAAA==.Tasjón:BAAANQAECgQIBAAAAA==.Taster:BAAANQAECgIIAgAAAA==.Tatcho:BAAANQADCgQIBAAAAA==.Tatgrim:BAAANQADCgUIBQAAAA==.Taurotoro:BAAANQAECgcICQAAAA==.Tavitop:BAAANQAECgQIBwAAAA==.Tavop:BAAANQAECgQIBQABNQAECgQIBwABAAAAAA==.Tavozz:BAAANQAECggIDQAAAA==.Tayamasan:BAAANQAECgIIAwAAAA==.Tayronisaias:BAAANQADCgUIBQAAAA==.Taysi:BAAANQAECgQICAAAAA==.Tayvonga:BAAANQADCgQIBAAAAA==.Tazg:BAABNQAECoEVAAIDAAgJ9BPeFgAqAgADAAgJ9BPeFgAqAgAAAA==.',
Te='Tendrilion:BAAANQAECgQIBQAAAA==.Tenken:BAAANQADCgQIBAAAAA==.Teoma:BAAANQADCgQIBAAAAA==.Tephie:BAAANQADCgMIAwAAAA==.Tereaux:BAAANQADCgEIAQAAAA==.Termanology:BAAANQADCgcIDQAAAA==.Terrik:BAAANQADCggIDAAAAA==.Testiculona:BAAANQADCgMIAwAAAA==.',
Th='Thebadboy:BAAANQADCgYIFwAAAA==.Thebigone:BAAANQAECgQIBAAAAA==.Theconor:BAAANQADCgQIBgAAAA==.Thedrag:BAAANQAECgYIDwAAAA==.Theewarrior:BAAANQAECgQIBgAAAA==.Thekla:BAAANQABCgEIAQAAAA==.Thelastmønk:BAAANQAECgQIBQAAAA==.Themaga:BAAANQAECgQICQAAAA==.Thenas:BAAANQADCgEIAQAAAA==.Thenight:BAAANQABCgIIAgAAAA==.Theogro:BAAANQADCgQIBAAAAA==.Thepepper:BAAANQADCgUIBQAAAA==.Thepowerful:BAAANQADCggICAAAAA==.Theraliz:BAAANQAECgUICQAAAA==.Thereaux:BAAANQAECgYIDQAAAA==.Thesentry:BAAANQADCgYIDAAAAA==.Theshami:BAAANQAECgYICAAAAA==.Theskaa:BAAANQAECgYIDwAAAA==.Thetoxica:BAAANQADCgYIDQAAAA==.Thomiko:BAAANQAECgEIAQAAAA==.Thorflins:BAAANQAECgEIAQABNQAECgUICwABAAAAAA==.Thorfínn:BAAANQADCgYIBgAAAA==.Thorgrimm:BAAANQAECgUIBQAAAA==.Thoritank:BAAANQAECggICgAAAA==.Thorjin:BAAANQADCgQIBAAAAA==.Thorkkel:BAAANQADCgYICAAAAA==.Thrandüil:BAAANQAECgIIAgAAAA==.Thráiin:BAAANQADCgEIAQAAAA==.Thularion:BAAANQADCgQIBAAAAA==.',
Ti='Timm:BAAANQADCggIEAAAAA==.Tiramisü:BAAANQADCgYIDAAAAA==.Tiramizu:BAAANQAECgUICQAAAA==.Tirne:BAAANQAECgIIAQAAAA==.Tirys:BAAANQADCgQIBAAAAA==.Titanozcuro:BAAANQADCgMIAwAAAA==.',
Tk='Tkiin:BAAANQADCgQIBAAAAA==.',
To='Toball:BAAANQADCgMIAwAAAA==.Tonswors:BAAANQAECgUICQAAAA==.Toprac:BAAANQADCgMIAwAAAA==.Toravon:BAAANQAECgUIBwAAAA==.Toribianito:BAAANQAECgQIBgAAAA==.Toritotop:BAAANQADCgQIBAAAAA==.Torujo:BAAANQAECgEIAQAAAA==.',
Tr='Trabalindo:BAAANQADCgUIBQAAAA==.Trakkar:BAAANQADCgYIDQAAAA==.Traxexd:BAAANQAECgQICQAAAA==.Treeckko:BAAANQAECgEIAQAAAA==.Trizh:BAAANQAECgcIEQAAAA==.Trogloditamr:BAAANQAECgEIAQABNQAECgMIBQABAAAAAA==.Trollzilla:BAAANQADCgQIBAAAAA==.Trolobayo:BAAANQADCggIDQAAAA==.Trombe:BAAANQADCggICAAAAA==.Troth:BAAANQADCgYIDgAAAA==.Trx:BAAANQAECgIIAgAAAA==.Tryzthano:BAAANQAECgEIAQAAAA==.',
Ts='Tsukichamy:BAAANQAECgUICwAAAA==.Tsukinohono:BAAANQADCgIIAgABNQADCgUICAABAAAAAA==.Tsukoni:BAAANQADCgcIDwAAAA==.',
Tu='Tumbalino:BAAANQAECgUIBwAAAA==.Tunche:BAAANQABCgIIAgAAAA==.Tundreal:BAAANQADCgcIBwAAAA==.Turlex:BAAANQADCgMIBAAAAA==.Tusi:BAAANQADCgUICwAAAA==.Tuskankamon:BAAANQADCgIIAgAAAA==.Tutte:BAAANQAECgUICwAAAA==.Tutánca:BAAANQADCgUIBQAAAA==.',
Ty='Tyffania:BAAANQADCgYIBwAAAA==.Tyfus:BAAANQADCgQIBAAAAA==.Tyruz:BAAANQAFFAEIAQAAAA==.',
['Tá']='Tábris:BAAANQADCgMIBAAAAA==.Tánjiro:BAAANQAECgMIBQAAAA==.Tántalo:BAAANQAECgIIAwABNQAECgQIBwABAAAAAA==.Tásjön:BAAANQAECgMIAwAAAA==.',
['Té']='Téra:BAAANQADCgMIAwAAAA==.',
['Të']='Tëlchâr:BAAANQAECgIIBAABNQAECgUICQABAAAAAA==.',
['Tý']='Týphon:BAAANQAECgQIBgAAAA==.',
Uc='Uchida:BAAANQADCgUIAgABNQAECgQICAABAAAAAA==.',
Uk='Ukog:BAAANQAECgYIDwAAAA==.',
Ul='Ulfgar:BAAANQADCgIIAgAAAA==.Ulisesh:BAAANQADCgYIBgAAAA==.Ulkii:BAAANQADCgYICAAAAA==.Ultramazter:BAAANQAECgEIAQAAAA==.',
Un='Unaixo:BAAANQADCggICQAAAA==.',
Ur='Uriyael:BAAANQAECgQIBwAAAA==.Ursuur:BAAANQAECgMIAwAAAA==.',
Ut='Uthart:BAAANQADCgQIBAAAAA==.',
Va='Vacelin:BAAANQABCgUICAAAAA==.Valarwen:BAAANQADCgcIDAAAAA==.Valdreth:BAAANQAECgEIAQAAAA==.Valeneth:BAAANQADCgcICQAAAA==.Valiant:BAAANQADCgYIBgAAAA==.Valkenhain:BAAANQADCgYICgAAAA==.Valmonkeyh:BAAANQAECgIIAwAAAA==.Valmonkeyl:BAAANQADCgcIBwAAAA==.Vangonna:BAAANQADCgEIAQAAAA==.Varthur:BAAANQABCgIIAgAAAA==.Vasculio:BAAANQAECgMIAwAAAA==.Vasheth:BAAANQADCgYICwAAAA==.Vasthorr:BAAANQADCgEIAQAAAA==.',
Ve='Vejrekku:BAAANQADCgQIBgAAAA==.Velumbra:BAAANQADCgQIBAAAAA==.Venerabilis:BAAANQADCgMIAwAAAA==.Venomoth:BAAANQADCgcIBwAAAA==.Vergasola:BAAANQADCgMIAwAAAA==.Vertrix:BAAANQAECgIIAgAAAA==.Verymelon:BAABNQAECoEZAAIXAAgJUxooGwCaAgAXAAgJUxooGwCaAgAAAA==.Vesperyx:BAAANQAECgIIAwAAAA==.',
Vh='Vhacko:BAAANQAECgEIAQAAAA==.',
Vi='Vialucis:BAAANQADCgcIBwAAAA==.Vianis:BAAANQADCgEIAQAAAA==.Vicaioros:BAAANQADCgcIDQAAAA==.Vichizchami:BAAANQAECgUIBgABNQAECgYICQABAAAAAA==.Vichizz:BAAANQAECgYICQAAAA==.Viciiecal:BAABNQAECoEdAAIYAAgJkRgKBABlAgAYAAgJkRgKBABlAgAAAA==.Vicius:BAAANQADCgMIAwAAAA==.Viejosabrosö:BAAANQAECgQICwAAAA==.Violyn:BAAANQADCgMIAwAAAA==.Viszeral:BAAANQAECgQIBgABNQAECgUIDQABAAAAAA==.Vitoxdary:BAAANQABCgIIAgAAAA==.',
Vo='Voidcha:BAAANQADCgEIAQAAAA==.Volldemort:BAAANQAECgQIBgAAAA==.Volttage:BAAANQAECgEIAQAAAA==.Vonjum:BAAANQADCgUICQAAAA==.',
Vt='Vtor:BAAANQAECgUIDQAAAA==.',
Vu='Vulkan:BAABNQAECoEZAAIWAAgJkQ5zDwDMAQAWAAgJkQ5zDwDMAQAAAA==.',
['Vá']='Vána:BAAANQADCgIIAgAAAA==.',
['Vó']='Vóróz:BAAANQADCgIIAgAAAA==.',
Wa='Wachifurro:BAAANQAECgIIAQAAAA==.Wackø:BAAANQADCgQIBAAAAA==.Wallas:BAAANQADCggICAAAAA==.Warorc:BAAANQADCgYICQAAAA==.Warrelegante:BAAANQADCgIIAgABNQAECgUIDQABAAAAAA==.Warrfury:BAAANQADCgUIBQAAAA==.Warriorgrego:BAAANQADCgYIDQAAAA==.Washimyngo:BAAANQADCgUIBQAAAA==.Watermelo:BAAANQAECgYIDwAAAA==.Wathor:BAAANQABCgMIAwAAAA==.',
We='Wendhy:BAAANQADCgEIAQAAAA==.Wendyita:BAAANQABCgMIBQAAAA==.Wessler:BAAANQADCgIIAgAAAA==.',
Wh='Whater:BAAANQADCgIIAgAAAA==.Whesley:BAAANQAECgEIAQAAAA==.Whitemanee:BAAANQADCgUICAABNQAECgQIBwABAAAAAA==.Whushung:BAAANQAECgUICQAAAA==.',
Wi='Wiinly:BAAANQAECgUIBgAAAA==.Wildson:BAAANQAECgEIAQAAAA==.Wiraq:BAAANQAECgIIBAAAAA==.Wissepi:BAAANQAECgEIAQAAAA==.Witzy:BAAANQAECgEIAQAAAA==.',
Wo='Wolfeligoza:BAAANQAECgYIBwAAAA==.Wolfrain:BAAANQAECgYICAAAAA==.Wolfsrain:BAAANQAECgIIAgAAAA==.Wolvy:BAAANQADCgYIBwAAAA==.Wordok:BAAANQADCgcIBwAAAA==.Wounch:BAAANQADCgIIAgABNQADCgUICAABAAAAAA==.',
Wr='Wrhayza:BAAANQADCgUIBQAAAA==.',
Wu='Wufar:BAAANQADCgUICAAAAA==.Wurd:BAAANQADCgMIAwAAAA==.',
Wy='Wylgrim:BAAANQADCgYICwABNQAECggIGAAFANMZAA==.',
['Wâ']='Wâckøø:BAAANQADCgcIBwAAAA==.',
Xa='Xanhk:BAAANQADCgcIDQAAAA==.',
Xe='Xetik:BAAANQAECgEIAQAAAA==.Xey:BAAANQADCgYICgAAAA==.',
Xi='Xilk:BAAANQADCgUICwABNQADCgYICwABAAAAAA==.Xilka:BAAANQADCgYICwAAAA==.',
Xn='Xnocturne:BAAANQADCgUIBQAAAA==.',
Xo='Xolokin:BAAANQADCgIIAgAAAA==.',
Xs='Xstark:BAAANQADCgEIAQAAAA==.',
Xt='Xtreem:BAAANQAECgQIBQAAAA==.',
Xu='Xubb:BAABNQAECoEhAAITAAkJ+BlsEQDOAgATAAkJ+BlsEQDOAgAAAA==.Xulzaya:BAAANQADCgUIBQAAAA==.',
Ya='Yakuzagt:BAAANQADCgIIAgAAAA==.Yamisan:BAAANQAECgUIDQAAAA==.Yanjun:BAAANQADCgYIBwABNQABCgIIAgABAAAAAA==.Yasky:BAAANQADCgQIBAAAAA==.Yazaam:BAAANQADCgIIAgAAAA==.',
Yh='Yhina:BAAANQAECgQICAAAAA==.',
Yi='Yinaiteen:BAAANQAECgUICQAAAA==.',
Yo='Yojoy:BAAANQAECgMIAwAAAA==.Yomix:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Yorukage:BAAANQABCgIIAgAAAA==.Yorunecrum:BAAANQADCggIGAAAAA==.',
Yr='Yracema:BAAANQADCgYIBwAAAA==.',
['Yâ']='Yâtzüry:BAAANQAECgcIEAAAAA==.',
['Yó']='Yóru:BAAANQADCgcIEQAAAA==.',
Za='Zacarias:BAAANQAECgMIBAAAAA==.Zagal:BAAANQAECgEIAQAAAA==.Zalzuks:BAAANQADCgEIAQAAAA==.Zamoraby:BAAANQADCgYIAgAAAA==.Zanudar:BAAANQADCgUICgAAAA==.Zaokum:BAAANQAECgYIDQAAAA==.Zaracatunga:BAAANQAECgIIAwAAAA==.Zarnax:BAAANQADCgUICAAAAA==.Zarzin:BAAANQADCgcICwABNQAECgEIAQABAAAAAA==.',
Ze='Zeckert:BAAANQAECggICAAAAA==.Zedreg:BAAANQAECgEIAgAAAA==.Zeeds:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.Zehelyne:BAABNQAECoEYAAIZAAkJxCM1AQDDAwAZAAkJxCM1AQDDAwAAAA==.Zekutor:BAAANQAECgQIDgAAAA==.Zekuz:BAAANQABCgIIAgAAAA==.Zengil:BAAANQAECgMIAwAAAA==.Zentetsuken:BAAANQADCgYICAAAAA==.Zephania:BAAANQADCggIDQAAAA==.Zetadragus:BAAANQADCgUIBQAAAA==.',
Zh='Zharfel:BAAANQADCgIIAgAAAA==.Zhatx:BAAANQAECgMIBgAAAA==.Zhenna:BAAANQAECgQICgAAAA==.Zhinjoo:BAAANQADCggIGAABNQAECgIIAgABAAAAAA==.Zhyer:BAAANQAECgEIAgAAAA==.',
Zi='Zizaa:BAAANQADCgMIAwAAAA==.Zizu:BAAANQADCgUIEAAAAA==.',
Zo='Zomma:BAAANQADCgcIAwAAAA==.Zonoscope:BAAANQAECgEIAQAAAA==.Zoujc:BAAANQADCgIIAgAAAA==.',
Zt='Ztelius:BAAANQADCgYIBgAAAA==.',
Zu='Zucc:BAAANQADCgcICQAAAA==.Zuffx:BAAANQADCgYICgAAAA==.Zuikaku:BAAANQAECgcIEQAAAA==.Zukumbia:BAAANQADCgQIAgAAAA==.Zunjin:BAAANQAECgEIAQAAAA==.',
Zz='Zzeus:BAAANQAECgcIDgAAAA==.',
['Zè']='Zèrò:BAAANQADCgQIBAAAAA==.',
['Zé']='Zéhel:BAAANQAECggICAAAAA==.',
['Zí']='Zíigg:BAAANQAECgIIAgAAAA==.Zíígg:BAAANQADCgYIBgAAAA==.',
['Zø']='Zøuht:BAAANQAECgUIDgAAAA==.Zøus:BAAANQADCggIEAAAAA==.',
['Àl']='Àlphà:BAAANQAECgEIAQAAAA==.',
['Ác']='Ácetaminofen:BAAANQADCgMIAwAAAA==.',
['Ál']='Álibéll:BAAANQAECgUICgAAAA==.',
['Ár']='Ártemiz:BAAANQADCgYIBgAAAA==.',
['Áz']='Ázáél:BAAANQADCgMIAwAAAA==.',
['Ân']='Ângie:BAAANQADCgMIAwAAAA==.',
['Âr']='Ârcänë:BAAANQAECgUICQAAAA==.',
['Äd']='Ädriänä:BAAANQAECgIIAgAAAA==.',
['Äm']='Ämoon:BAAANQADCgIIAgAAAA==.',
['Än']='Änäwänäsäký:BAAANQAECgEIAQAAAA==.',
['Är']='Ärtïs:BAAANQABCgQICAAAAA==.',
['Äs']='Äsmodeus:BAAANQAECgQIBAAAAA==.',
['Él']='Éléná:BAAANQADCgYIBwAAAA==.',
['Ëd']='Ëder:BAAANQADCggICAAAAA==.',
['Ëe']='Ëescanör:BAAANQAECgUICgAAAA==.',
['Ëx']='Ëxecutor:BAAANQAECgYICAABNQAECgYIDwABAAAAAA==.',
['Ðe']='Ðemon:BAAANQAECgIIAgAAAA==.Ðexters:BAAANQADCgUIBQAAAA==.',
['Ör']='Örchid:BAAANQAECgQIBgAAAA==.',
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
