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

local lookup = {'Priest-Shadow','Unknown-Unknown','DeathKnight-Unholy','DemonHunter-Devourer','Hunter-BeastMastery','Shaman-Elemental','Mage-Frost','Paladin-Retribution','Mage-Fire','Druid-Balance','Shaman-Restoration','Priest-Holy','Monk-Mistweaver','DemonHunter-Havoc','Warrior-Arms','Warrior-Fury','Priest-Discipline','Warlock-Destruction','Mage-Arcane','DeathKnight-Blood','Warlock-Demonology','Hunter-Marksmanship','Evoker-Devastation',}
local provider = {region='US',realm='Nemesis',name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Abyssdk:BAAANQAECgEIAQABNQAECgkJIAABAFAjAA==.',
Ac='Acadêmica:BAAANQAECgMIBQAAAA==.Acnaya:BAAANQADCgQIBAAAAA==.',
Ad='Adcosmos:BAAANQADCggICAABNQAECgMIBQACAAAAAA==.Adebaio:BAABNQAECoEdAAIDAAkJsCGaBgBlAwADAAkJsCGaBgBlAwAAAA==.',
Ae='Aegislashh:BAAANQAECgUICgAAAA==.Aerlath:BAACNQAFFIEEAAIEAAIJXhdBBgC6AAAEAAIJXhdBBgC6AAA1AAQKgSAAAgQACQlDI3gCAKEDAAQACQlDI3gCAKEDAAAA.Aetulia:BAAANQAECgQIBQAAAA==.',
Af='Afixo:BAAANQADCgQIBAABNQADCggIEAACAAAAAA==.',
Ag='Aggroster:BAAANQAECgIIAgAAAA==.Agnestesia:BAAANQAECgQIBwAAAA==.',
Ah='Ahrathor:BAAANQAECgMIAwAAAA==.',
Ak='Akasta:BAAANQAECgYIDQAAAA==.Akkiralock:BAAANQADCgYIBgAAAA==.Akâme:BAAANQADCgYIBgABNQAFFAEIAQACAAAAAA==.',
Al='Alascayoung:BAAANQADCggIEAAAAA==.Alatroz:BAAANQADCgIIAgAAAA==.Aldrathion:BAAANQAECgEIAQABNQAECgkJIgAFACYiAA==.Aledk:BAAANQADCgYIEAAAAA==.Alessan:BAAANQADCgYIBgAAAA==.Alessary:BAAANQADCgYIBwAAAA==.Alfurieb:BAAANQAECgIIAgAAAA==.Alianar:BAAANQADCgMIAwAAAA==.Alicel:BAABNQAECoEXAAIDAAgJHCDoEQDEAgADAAgJHCDoEQDEAgAAAA==.Altreir:BAAANQADCgYICgABNQADCggIEAACAAAAAA==.Aluny:BAAANQABCgEIAQABNQAECgQIBQACAAAAAA==.Aluxxious:BAAANQAECgQICAAAAA==.Alëcream:BAAANQAECgUIBQAAAA==.Alíne:BAAANQAECgMIAwAAAA==.',
Am='Amøm:BAAANQAECgMIBAAAAA==.',
An='Anduinwill:BAAANQAECgEIAQAAAA==.Andärilho:BAAANQADCgYICwAAAA==.Ankados:BAAANQAECgUIDAABNQAECgkJGQAGANcdAA==.Ankapos:BAAANQAECgQIBQAAAA==.Annish:BAAANQADCgYICwAAAA==.Anthorforged:BAAANQAECgQIBgAAAA==.',
Ap='Apocalipse:BAABNQAECoEXAAIHAAgJJBqtAgCNAgAHAAgJJBqtAgCNAgAAAA==.',
Aq='Aquillez:BAAANQAECgQIAgAAAA==.',
Ar='Araurz:BAAANQADCgIIAgABNQAECgQIBgACAAAAAA==.Arinn:BAAANQAECgQIBAAAAA==.Artradian:BAAANQADCggIDwAAAA==.Arucàrd:BAAANQADCgQIBAAAAA==.Aryethi:BAAANQAECgQIDAAAAA==.',
As='Ashabellanar:BAAANQAECgMIBQAAAA==.Ashenna:BAAANQAECgIIAgAAAA==.Aslatiel:BAAANQADCgYIBgABNQAECgQIBQACAAAAAA==.',
Au='Aurdraen:BAAANQAECgEIAQAAAA==.',
Av='Avanthara:BAAANQAECgQIBQAAAA==.',
Aw='Awk:BAAANQAECgYIBQAAAA==.',
Az='Azuros:BAAANQABCgIIAgAAAA==.',
['Aø']='Aøc:BAABNQAECoEaAAIIAAgJpRJ4PQAFAgAIAAgJpRJ4PQAFAgAAAA==.',
Ba='Babara:BAAANQABCgYIBwAAAA==.Babyfart:BAAANQAECgQICgAAAA==.Bakushiterra:BAAANQAECgQIBwAAAA==.Barao:BAAANQAECgQIBgAAAA==.Barriguinha:BAAANQAECgEIAQAAAA==.Batlemage:BAAANQABCgQIBgAAAA==.Batmano:BAAANQADCgYICgAAAA==.',
Be='Beornin:BAAANQADCgMIAwAAAA==.',
Bh='Bherg:BAAANQAECgIIAgAAAA==.',
Bi='Biskademon:BAAANQAECgcIEgAAAA==.Bizum:BAAANQADCgcIDAAAAA==.',
Bj='Bjørn:BAAANQADCgQIBAAAAA==.',
Bl='Blackee:BAAANQAECgEIAQAAAA==.Blackwatch:BAAANQAECgEIAQAAAA==.Blitzkrig:BAABNQAECoEbAAIJAAkJLxxTAAAcAwAJAAkJLxxTAAAcAwAAAA==.Bloodlioness:BAAANQAECgEIAQAAAA==.Bloodyclaw:BAAANQADCggIFAAAAA==.',
Bo='Boomgoesyou:BAABNQAECoEWAAIKAAgJ1Q3IKgDSAQAKAAgJ1Q3IKgDSAQAAAA==.Bourdriel:BAAANQAECgQIBAAAAA==.',
Br='Bradoki:BAAANQAECgMIBgAAAA==.Brancalleone:BAAANQAECgIIAgAAAA==.Brazukmaiden:BAAANQAECgIIAgABNQAECgQIBAACAAAAAA==.Brisawave:BAABNQAECoEcAAILAAkJhyKIDAABAwALAAkJhyKIDAABAwAAAA==.Brizagato:BAAANQAECgUICgAAAA==.Broke:BAAANQAECgQIBQAAAA==.Brujaria:BAAANQADCggICAAAAA==.Bruxxaum:BAAANQADCgEIAQAAAA==.Brád:BAAANQAECgMIBwAAAA==.',
Bu='Bushido:BAAANQADCgYIEgAAAA==.Bustgril:BAAANQAECgEIAQAAAA==.',
Bz='Bzbit:BAAANQADCgMIAgAAAA==.',
['Bé']='Béssi:BAAANQADCgMIAwAAAA==.',
Ca='Caiquebmq:BAAANQAECgEIAQAAAA==.Calanguejo:BAAANQADCgQIBAABNQAECgQIBwACAAAAAA==.Calanguinhe:BAAANQADCggIDgAAAA==.Caldrin:BAAANQADCgEIAQAAAA==.Calliphora:BAAANQAECgQIBAAAAA==.Canard:BAAANQADCgUICAABNQAECggIBQACAAAAAA==.Cannibal:BAAANQABCgYICgAAAA==.Carinha:BAAANQADCggIAgAAAA==.Carloxamã:BAAANQAECgQICwABNQAECgcICwACAAAAAA==.Cassisus:BAAANQADCggICAAAAA==.Catarnaldo:BAAANQADCgYICQABNQAECgQIBQACAAAAAA==.Cathiseev:BAAANQAECgUICgAAAA==.Cathury:BAAANQAECgIIBgAAAA==.Catÿ:BAAANQAECgUICgABNQAECgkJGQAMAHwjAA==.Cavernozo:BAAANQAECgQIBAABNQAECgYIAwACAAAAAA==.Caxola:BAAANQADCgIIAgAAAA==.',
Ce='Cerino:BAAANQADCgQIBAAAAA==.Cevadão:BAAANQAECgYIBgABNQAECgcIEQACAAAAAA==.',
Ch='Chaleira:BAAANQADCgUICQAAAA==.Changjin:BAAANQADCgMIAwAAAA==.Cheweir:BAAANQAECgIIAgAAAA==.Chiclete:BAAANQAECgYIEQAAAA==.Chopz:BAAANQAECgIIAgAAAA==.Chovor:BAAANQAECgIIAgAAAA==.Chrizantm:BAAANQAECgIIAgABNQAECgQIBgACAAAAAA==.Chucknòórris:BAAANQADCgcIEQAAAA==.',
Cl='Clairë:BAAANQAECgUIBQAAAA==.Claude:BAAANQADCgQIBQAAAA==.Clio:BAAANQAECgQICwAAAA==.',
Co='Cockcroft:BAAANQADCgIIAgABNQAECggIGAANAGYQAA==.Coionir:BAAANQAECgQIBQAAAA==.Coiovoker:BAAANQADCgEIAQABNQAECgQIBQACAAAAAA==.Coldblooded:BAAANQADCgcIBwABNQADCggICAACAAAAAA==.Comunistaa:BAAANQAECgcIEAAAAA==.Corstine:BAAANQAECgIIAgAAAA==.Corvynus:BAAANQADCgUIBgAAAA==.Couldovisk:BAAANQADCgIIAgAAAA==.',
Cr='Cronosxdm:BAAANQAFFAEIAQAAAA==.Crucyatus:BAAANQAECgQICQAAAA==.Cruelmoon:BAAANQADCgEIAQAAAA==.',
['Cå']='Cåssio:BAAANQAECgYICQAAAA==.',
['Cÿ']='Cÿgnus:BAAANQADCgEIAQABNQAECgcIEAACAAAAAA==.',
Da='Dadashi:BAAANQADCggICAAAAA==.Danadinn:BAAANQADCgcIBwAAAA==.Danteholy:BAAANQADCgMIAwAAAA==.Darkhold:BAAANQAECgYIEgAAAA==.Darklendio:BAAANQADCgUICgAAAA==.Daroncosp:BAAANQADCgIIAgAAAA==.Dashuman:BAAANQAECgYIDQAAAA==.Davicohunter:BAAANQADCgIIAgAAAA==.Dazhu:BAAANQADCggICAAAAA==.',
De='Deadguth:BAAANQAECggIBwAAAA==.Deadusopp:BAAANQADCgQIBAAAAA==.Deathatrix:BAAANQADCgUICAABNQAECgUICQACAAAAAA==.Deceive:BAAANQAECgMIBAAAAA==.Defroque:BAAANQAECgQIBAAAAA==.Deis:BAAANQADCgUIBAAAAA==.Delarÿn:BAAANQADCggIFwAAAA==.Demoncrashe:BAAANQADCgEIAQAAAA==.Demzumilde:BAAANQAECgMIBAAAAA==.Denevy:BAAANQAECgYIDQAAAA==.Deraelda:BAAANQADCgMIBAAAAA==.Derbster:BAAANQAECgcICQAAAA==.Destructiom:BAAANQAECgUICgABNQAECgYIDgACAAAAAA==.',
Dh='Dhamburguer:BAAANQAECgYICwAAAA==.Dhanadrai:BAAANQAECgUICgAAAA==.',
Di='Diggop:BAAANQADCgcIBwAAAA==.Dijank:BAAANQADCgIIAgABNQADCgUICQACAAAAAA==.Dima:BAAANQAECgcIEAAAAA==.',
Do='Dornaa:BAAANQADCgYICgAAAA==.Dosmagos:BAAANQABCgMIBQAAAA==.Doulce:BAAANQAECgEIAgAAAA==.',
Dr='Dracarysz:BAAANQADCgUIBQAAAA==.Draculavmp:BAAANQADCgEIAQAAAA==.Dragonbaby:BAAANQADCgUIBQAAAA==.Drainetty:BAAANQAECgEIAQAAAA==.Dranacs:BAAANQAECggIBQAAAA==.Dreamremix:BAAANQAFFAEIAQAAAA==.Dreyol:BAAANQADCgYICQAAAA==.Drts:BAAANQAECgcIEgAAAA==.',
Du='Dumar:BAAANQAECgIIAgAAAA==.',
Ed='Eduarthas:BAAANQAECgQIBAAAAA==.',
Eg='Egoist:BAAANQADCggICAAAAA==.',
El='Elementys:BAAANQAECgEIAwAAAA==.Elemëntum:BAAANQADCgcIBwAAAA==.Elfuryon:BAAANQADCgIIAgABNQAECgkJIgAFACYiAA==.Elinaara:BAAANQAECgYIDwAAAA==.Elizabeth:BAAANQABCgIIAgAAAA==.Elliith:BAAANQADCgIIAgAAAA==.Ellithyx:BAAANQAECgIIAgAAAA==.Elricky:BAAANQADCgIIBAAAAA==.Eluna:BAAANQAECgMIAwAAAA==.Elwiñ:BAAANQADCgEIAQAAAA==.',
En='Encanis:BAAANQADCgYIAgAAAA==.',
Er='Ermooke:BAAANQAECgEIAQAAAA==.',
Es='Escanorzão:BAAANQADCgcIBwABNQADCggIEAACAAAAAA==.Escola:BAAANQAECgQICQAAAA==.',
Ex='Exo:BAAANQAECgYIDgAAAA==.Exorciseur:BAABNQAECoEcAAIOAAgJ1x+BCgDoAgAOAAgJ1x+BCgDoAgAAAA==.',
Fa='Fabercästell:BAAANQAECgMIAwAAAA==.Fabers:BAAANQAECgMIAwAAAA==.Fargunn:BAAANQAECgQIBgAAAA==.',
Fe='Feanori:BAAANQAECgUICwAAAA==.Feanør:BAAANQADCgYIDQAAAA==.Feinanduo:BAAANQADCgMIAwAAAA==.Felfury:BAAANQADCgUIBQABNQAECgUIBgACAAAAAA==.Feyrin:BAAANQADCggIGgAAAA==.',
Fi='Finngermy:BAAANQADCggICQAAAA==.',
Fl='Flodearthen:BAAANQADCgQIBwABNQAECgEIAQACAAAAAA==.Flodfelblood:BAAANQAECgEIAQAAAA==.',
['Fí']='Fíli:BAAANQAECgEIAQAAAA==.',
['Fï']='Fïrestorm:BAAANQADCgYIBgAAAA==.',
Ga='Gabela:BAAANQAECgEIAQAAAA==.Gaiataur:BAAANQADCgMIAwAAAA==.Galandiel:BAAANQADCggIDgAAAA==.Galinni:BAAANQADCggICAAAAA==.Gallon:BAAANQAECgQIBQAAAA==.',
Gl='Glacyale:BAAANQAECgEIAQAAAA==.Glisa:BAAANQAECgQIAgAAAA==.',
Gn='Gnomepink:BAAANQADCggIEwAAAA==.',
Go='Godadrian:BAAANQAECgUIBwAAAA==.Gordãobtm:BAAANQAECgQIBAAAAA==.Gosu:BAAANQAECgUIBwAAAA==.',
Gr='Gralfor:BAAANQADCggIFgAAAA==.Grekorio:BAAANQADCgcIDgAAAA==.Greylord:BAAANQAECgIIAgABNQAECgQIBwACAAAAAA==.Greylorddrak:BAAANQAECgQIBwAAAA==.Greylordp:BAAANQAECgEIAQABNQAECgQIBwACAAAAAA==.Gronak:BAAANQAECgQIAgAAAA==.',
Gu='Guillyn:BAAANQADCgYIBgAAAA==.Gults:BAAANQADCgQIBAAAAA==.Gultsz:BAAANQADCgUIBwAAAA==.Gunpowter:BAAANQABCgIIAwAAAA==.Guxrock:BAAANQAECgIIAwAAAA==.',
Gy='Gyllenhaal:BAAANQADCgUIBQAAAA==.',
['Gä']='Gäspär:BAAANQADCgYIBgAAAA==.',
['Gø']='Gødmar:BAAANQAECgIIAgAAAA==.',
Ha='Hafo:BAAANQADCgYICAAAAA==.Hagnaredk:BAAANQADCgMIAwAAAA==.Haiume:BAAANQAECgQIBAAAAA==.Hamiister:BAAANQADCgQIBAAAAA==.Hancalimon:BAAANQAECgQIDQAAAA==.Haokö:BAAANQADCgYIBgAAAA==.Hasanzi:BAAANQADCgUIBQAAAA==.Hastterix:BAAANQAECgQIBAAAAA==.Hatezon:BAAANQAECgMIBQAAAA==.',
He='Heavyking:BAAANQAECgQIBQAAAA==.Heishoo:BAAANQADCgIIAgAAAA==.Helitox:BAAANQAECgMIAwAAAA==.Hellhoundish:BAAANQADCgYIBgABNQAFFAEIAQACAAAAAA==.Hellreaper:BAAANQAECgYIDQAAAA==.Heloisaa:BAAANQAECgUIBwAAAA==.Helwen:BAAANQAECgEIAQAAAA==.Heracranosx:BAAANQAECgEIAQAAAA==.Herdy:BAAANQADCgEIAQAAAA==.Herta:BAAANQAECgMIBgAAAA==.Hess:BAAANQAECgMIBAAAAA==.',
Hi='Hireque:BAAANQAECgQIBAAAAA==.Hitkilled:BAAANQADCggICAAAAA==.Hitkins:BAAANQADCgYIBwAAAA==.',
Ho='Hofpriest:BAAANQADCgUIBQAAAA==.Hoiac:BAAANQAECgMIBwAAAA==.Holycel:BAAANQADCggIDQABNQAECggIFwADABwgAA==.',
Hu='Hunterpica:BAAANQAECgQIBwAAAA==.Huntmon:BAAANQAECgYIDAAAAA==.Huskat:BAAANQAECgYIDAAAAA==.',
Hy='Hysillens:BAAANQADCgcIFAAAAA==.',
['Hã']='Hãn:BAAANQADCgEIAQAAAA==.',
['Hä']='Härü:BAAANQADCgUIAwAAAA==.',
Il='Ilane:BAAANQABCggIDAAAAA==.Illidatrix:BAAANQAECgUICQAAAA==.Illïndão:BAAANQADCggICAAAAA==.Ilovealtgirl:BAAANQADCggIDwAAAA==.',
In='Inot:BAAANQAECgQIBQAAAA==.',
Ir='Irmãsafada:BAAANQADCgEIAQAAAA==.',
Is='Iscariotes:BAAANQABCgQIBAAAAA==.Ismael:BAAANQAECgQIBgAAAA==.',
It='Italodpz:BAAANQAECgUIBQAAAA==.Itsälasca:BAAANQADCgUICwAAAA==.',
Iu='Iuri:BAAANQAECgQIAgAAAA==.',
Ix='Ixlzvaxtylxl:BAAANQADCgYIBgAAAA==.',
Iz='Izanna:BAAANQADCgcICwAAAA==.',
Ja='Jalinrabeidh:BAAANQAECgEIAQAAAA==.Jampack:BAABNQAECoEZAAILAAgJKCKIDQD1AgALAAgJKCKIDQD1AgAAAA==.',
Je='Jeevas:BAAANQAECgQIBwAAAA==.Jefté:BAAANQADCgEIAQAAAA==.Jeguinha:BAAANQABCggIDgAAAA==.Jeu:BAAANQADCgcICQAAAA==.Jeyla:BAAANQADCgEIAQAAAA==.',
Jh='Jhasperr:BAAANQADCggIEwAAAA==.',
Jo='Jocabiroca:BAAANQAECgcIDgAAAA==.Johnez:BAAANQADCgIIAgAAAA==.Jotavê:BAAANQADCgUICQAAAA==.',
Jp='Jpleuk:BAAANQAECgUICAAAAA==.',
Jr='Jrxamã:BAAANQAECgMIBAAAAA==.',
Ju='Juliia:BAAANQAECgMIAwAAAA==.Jusgu:BAAANQAECgIIBQAAAA==.',
['Jö']='Jönah:BAAANQADCgMIAwAAAA==.',
Ka='Kaaliel:BAAANQADCgQIBQAAAA==.Kagero:BAAANQADCgQIBAAAAA==.Kaiev:BAAANQADCgYICgAAAA==.Kaju:BAAANQAECggIEAAAAA==.Kalinis:BAAANQAECgEIAQAAAA==.Kalliiope:BAAANQAECgQIDAAAAA==.Kamesenin:BAAANQADCgEIAQAAAA==.Kamïlla:BAAANQAECgMIAwAAAA==.Karak:BAAANQADCgIIAgAAAA==.Karamatsu:BAAANQAECgIIAgAAAA==.Karollus:BAAANQABCgIIAgAAAA==.Kath:BAAANQADCgYIBgAAAA==.Kathana:BAAANQABCggIDAAAAA==.Katona:BAAANQAECgQIAgAAAA==.',
Kd='Kdposa:BAAANQABCgQIBAAAAA==.',
Ke='Keior:BAAANQADCgcIDQAAAA==.Kenai:BAAANQAECgUICAAAAA==.Kewenz:BAAANQAECggIDAAAAA==.',
Kh='Khasin:BAAANQAECgMIBAAAAA==.',
Ki='Kierke:BAAANQADCgUIBQABNQAECgIIAwACAAAAAA==.Kindz:BAAANQADCgEIAQABNQAECggIDAACAAAAAA==.Kiregeth:BAAANQAECgUIBwAAAA==.Kitrel:BAAANQAECgMIAwAAAA==.',
Kl='Kllauzz:BAAANQAECgQIBQABNQAECgQICAACAAAAAA==.Kllauzzmage:BAAANQAECgIIAgABNQAECgQICAACAAAAAA==.Kllauzzpalla:BAAANQAECgQICAAAAA==.',
Kn='Knufolgado:BAAANQADCgYIBgAAAA==.',
Ko='Kolyn:BAABNQAECoEiAAIFAAkJJiJGBACNAwAFAAkJJiJGBACNAwAAAA==.Komamurasou:BAAANQAECgQIBAAAAA==.',
Kr='Krastian:BAAANQAECgMIBgAAAA==.Kreegh:BAAANQAECgEIAQAAAA==.Krupper:BAAANQAECgMIAwABNQAECgYIDAACAAAAAA==.Krynesa:BAAANQADCggICwAAAA==.',
Ku='Kuhaku:BAAANQADCgQIBAAAAA==.Kukuatzo:BAAANQAECgQIBAAAAA==.',
Ky='Kyary:BAAANQADCgUIBQABNQAECgcIEAACAAAAAA==.Kyndin:BAAANQADCgEIAQABNQAECggIDAACAAAAAA==.',
['Kä']='Kälini:BAAANQADCgcIDAABNQADCggIFwACAAAAAA==.Käyros:BAAANQADCgQIBQAAAA==.',
['Kó']='Kónar:BAAANQADCgEIAQAAAA==.',
['Kö']='Köndmänö:BAAANQAECgUICQAAAA==.Köri:BAAANQAECgYIEQAAAA==.',
La='Lakaioo:BAAANQAECgQIBwAAAA==.Lamont:BAAANQAECgQICAAAAA==.Lampiião:BAAANQAECgYIEAAAAA==.Lanllaniel:BAAANQAECgQIBgAAAA==.Largartixa:BAAANQADCgQIBAABNQAECgQIAgACAAAAAA==.Larslion:BAAANQABCgYIBgAAAA==.',
Le='Lebelisco:BAAANQAECgIIBAAAAA==.Leehyori:BAAANQAECgEIAQAAAA==.Lennorien:BAAANQAECgUICgAAAA==.Lestard:BAAANQABCgQIBAAAAA==.',
Lh='Lhyunl:BAAANQADCgIIAgAAAA==.',
Li='Liciox:BAAANQADCgIIAgAAAA==.Lifestrream:BAAANQAECgUICQAAAA==.Liftshertail:BAAANQAECgUIEQABNQAECgcIBgACAAAAAA==.Ligiaf:BAAANQAECgEIAQAAAA==.Liilum:BAAANQADCgcIBwAAAA==.Linë:BAAANQADCgcIFgABNQADCggIFwACAAAAAA==.Linëa:BAAANQADCgEIAQAAAA==.Linüss:BAAANQAECgEIAQAAAA==.Lionarot:BAAANQAECgQICAAAAA==.Littleshelby:BAAANQADCgYIDwAAAA==.',
Lo='Lobinox:BAAANQADCggICgAAAA==.Longaim:BAAANQAECgUICgAAAA==.Lorthaeron:BAAANQAECgYICQAAAA==.Lostminder:BAAANQAECgIIAgAAAA==.Lothbrok:BAAANQAECgUICgAAAA==.',
Lu='Lucanor:BAAANQADCgUIBQAAAA==.Lucasbr:BAAANQADCggIDgAAAA==.Lucasyeah:BAACNQAFFIEHAAIPAAQJpBWuBgBaAQAPAAQJpBWuBgBaAQA1AAQKgRsAAw8ACQnQHyMXABADAA8ACQk1HyMXABADABAAAQnQITYXAF4AAAAA.Lukanelas:BAAANQADCgUICgAAAA==.Lulyssa:BAAANQADCggICwAAAA==.Luna:BAAANQAECgQICgAAAA==.Lunes:BAAANQAECgYIDQAAAA==.Lusther:BAAANQADCggIDgAAAA==.Luzdacelesc:BAABNQAECoEgAAMBAAkJUCNwAgCdAwABAAkJUCNwAgCdAwAMAAEJgA1JhwA/AAAAAA==.',
Ly='Lyaah:BAAANQADCgYICwAAAA==.',
['Ló']='Lólzhé:BAAANQADCgYIBgAAAA==.',
['Lø']='Lølzhê:BAABNQAECoEaAAINAAcJjxx1CwAoAgANAAcJjxx1CwAoAgAAAA==.Løvizinha:BAAANQAECgQIBQAAAA==.',
['Lú']='Lúaprata:BAAANQADCggICAAAAA==.',
['Lü']='Lüthero:BAABNQAECoEeAAMMAAgJXR6XEQC7AgAMAAgJXR6XEQC7AgARAAUJSBW3CQA0AQAAAA==.',
Ma='Madbuddha:BAAANQADCgQIBAAAAA==.Mageli:BAAANQAECgEIAQAAAA==.Magodanilo:BAAANQADCgYIBgAAAA==.Magodavida:BAAANQAECgQICAAAAA==.Magodotruco:BAAANQADCgIIAgAAAA==.Maheena:BAAANQAECgQIAgAAAA==.Mai:BAAANQAECgUICgAAAA==.Mairon:BAAANQADCgcICQAAAA==.Makksha:BAAANQADCgEIAQAAAA==.Makoto:BAAANQAECgQIBwAAAA==.Malborion:BAAANQAECgIIAgAAAA==.Malignõ:BAABNQAECoEeAAIGAAkJSSE2BgCFAwAGAAkJSSE2BgCFAwAAAA==.Maltozo:BAAANQAECgUIDgAAAA==.Mandrakson:BAAANQAECgUICQAAAA==.Mandubim:BAAANQADCgEIAQAAAA==.Mariiamil:BAAANQADCggIGQAAAA==.Marvelos:BAAANQABCggIBgAAAA==.Marvvila:BAAANQAECgMIBQAAAA==.Marycristiny:BAAANQAECgQICQAAAA==.Mauwolf:BAAANQADCgcICAAAAA==.Mazaky:BAAANQAECgQICAAAAA==.',
Me='Medivi:BAAANQADCgMIAwAAAA==.Megumi:BAAANQAECgMIAwAAAA==.Memphis:BAAANQADCgcIBwAAAA==.Menorxidil:BAABNQAECoEYAAINAAgJ+hXpCwAbAgANAAgJ+hXpCwAbAgAAAA==.Merigold:BAAANQADCgYICwAAAA==.Mestreløck:BAAANQADCgMIBgAAAA==.Metallicä:BAAANQADCgMIAwAAAA==.',
Mh='Mhenb:BAAANQAECgQICAAAAA==.Mhorgothh:BAAANQADCgQIBAAAAA==.',
Mi='Micherouc:BAAANQABCgcICAAAAA==.Mikal:BAAANQAECgEIAQAAAA==.Minort:BAAANQAECgEIAQAAAA==.Minör:BAAANQAECgQIBQAAAA==.Missmarvel:BAAANQABCgYICgAAAA==.Mithrael:BAAANQADCgUIBQAAAA==.Mizukagesou:BAAANQAECgIIAgAAAA==.',
Mo='Monkbest:BAAANQADCgcICwAAAA==.Montej:BAAANQAECgEIAQAAAA==.Montäna:BAAANQABCgMIAwAAAA==.Mooncap:BAAANQAECgMIBAAAAA==.Moondragoon:BAAANQADCgcICQAAAA==.Morakhir:BAAANQADCgQIBAAAAA==.Moranguinhö:BAAANQADCgEIAQAAAA==.Mordiidinha:BAAANQAECgQIBQABNQAECgkJHgAGAEkhAA==.Morganviolet:BAAANQAECgQIBAAAAA==.',
Mu='Mugidinhaa:BAAANQABCgcIBQAAAA==.Murdoky:BAAANQADCgEIAQABNQAECgEIAQACAAAAAA==.Musleira:BAAANQAECgEIAQAAAA==.',
My='Myrzin:BAAANQADCggIDAAAAA==.Mythariel:BAAANQAECgEIAQAAAA==.Mythcut:BAAANQAECgQICAAAAA==.Mythjegue:BAAANQADCgYIBgAAAA==.',
['Mä']='Mällü:BAAANQAECgQIBAAAAA==.Mälthazar:BAAANQAECgYICwAAAA==.Määt:BAAANQADCggICAABNQAFFAMIBQASAA8OAA==.',
['Må']='Mågus:BAAANQAECgQIBgAAAA==.',
['Mò']='Mòrgan:BAAANQADCgQIBQAAAA==.',
['Mø']='Mørgåna:BAAANQAECgIIAwAAAA==.',
Na='Naamt:BAAANQADCgYIBgAAAA==.Naero:BAAANQADCgQIBAAAAA==.Naerylla:BAAANQADCgYICgABNQADCggICAACAAAAAA==.Nagashina:BAAANQADCggIFgAAAA==.Naizow:BAAANQAECgMIBgAAAA==.Namisan:BAAANQADCgYIBgAAAA==.Namuhß:BAAANQAECgQIBgAAAA==.Namøøh:BAAANQADCggICAAAAA==.Naomiy:BAAANQADCgYIEAAAAA==.Naoto:BAAANQAECgQIDQAAAA==.Napru:BAAANQADCgEIAQAAAA==.Narjes:BAAANQAECgQIBAAAAA==.Nathrezim:BAAANQADCgUIBQAAAA==.',
Ne='Necrogélido:BAAANQADCgYIEQAAAA==.Nefariio:BAAANQADCgQIBAAAAA==.Neninhaa:BAAANQADCgcIBQAAAA==.Neopaladino:BAAANQADCgYIDAAAAA==.Nerlock:BAAANQAECgEIAQAAAA==.',
Ni='Nicom:BAAANQADCgYIBgAAAA==.Nightforms:BAAANQADCggIEAAAAA==.Nikity:BAAANQAECgUICwAAAA==.',
No='Noahwallker:BAAANQADCgYIBgAAAA==.Noazard:BAAANQADCggIIAAAAA==.Nopainnogain:BAAANQAECgEIAQAAAA==.Nortênho:BAAANQAECgYICwAAAA==.Nossilat:BAAANQAECgcIEAAAAA==.',
Nu='Nuit:BAAANQAECgEIAwAAAA==.Nunhöly:BAAANQAECgMIBQAAAA==.',
Ny='Nysthiael:BAAANQAECgYIDQAAAA==.Nyxicel:BAAANQAECgEIAwABNQAECggIFwADABwgAA==.',
['Nä']='Nästÿ:BAAANQADCgYIBwAAAA==.',
['Nö']='Nöturnö:BAAANQABCgYICgAAAA==.',
['Ný']='Nýmm:BAAANQAECgQIBgAAAA==.',
Oc='Ocon:BAAANQABCgIIAgAAAA==.',
Od='Odigo:BAAANQADCgIIAgAAAA==.Odio:BAAANQADCgEIAQAAAA==.',
Ok='Okrigg:BAAANQADCggIEwAAAA==.',
Ol='Oldcook:BAAANQABCgYIBQAAAA==.Oliele:BAAANQADCgQIDAAAAA==.',
On='Onixpala:BAAANQAECgQIBAAAAA==.Onlydruix:BAAANQADCgIIAgAAAA==.',
Op='Opsdesculpa:BAAANQAECgQIDAAAAA==.',
Or='Organ:BAAANQAECgQIBQAAAA==.Orinoldo:BAABNQAECoEYAAITAAkJtBs/LADgAgATAAkJtBs/LADgAgAAAA==.',
Os='Osiria:BAAANQABCgYICAAAAA==.',
Ot='Otacki:BAAANQADCgIIAgAAAA==.Otherside:BAAANQAECgMIAwABNQAECggIHAASAIQSAA==.Otávio:BAAANQADCgYIDgAAAA==.',
Ox='Oxentedragon:BAAANQADCgMIAwAAAA==.',
Pa='Palluz:BAAANQAECgMIAwABNQAECggIHAAFAM4dAA==.Panicdeath:BAAANQAECgEIAQAAAA==.Parafinaisis:BAAANQAECgEIAQAAAA==.Parafinared:BAAANQADCgYICwAAAA==.Parrot:BAAANQADCgEIAQAAAA==.Pauladinho:BAAANQADCgIIAgAAAA==.',
Pe='Peltrow:BAAANQAFFAEIAQAAAA==.Penndrive:BAAANQADCgIIAgAAAA==.Perciwal:BAAANQADCgQIBAABNQAECgUIBwACAAAAAA==.Pesaa:BAAANQAECgYIDAAAAA==.',
Ph='Phanttoz:BAAANQADCgIIAgAAAA==.Phesti:BAAANQABCgEIAQAAAA==.Philii:BAAANQADCggIDQAAAA==.',
Pi='Picklerick:BAAANQAECgIIAQABNQAECgcIAQACAAAAAA==.Pirizin:BAAANQAECgcIEgAAAA==.',
Po='Popopeka:BAAANQADCgcIBwAAAA==.Porcaleta:BAAANQAECgQIBwAAAA==.Portal:BAAANQAECgQIBgAAAA==.Portelamage:BAABNQAECoEcAAITAAkJ+x2aKADvAgATAAkJ+x2aKADvAgAAAA==.Portheus:BAAANQADCggIFwAAAA==.',
Pr='Praeglacius:BAAANQAECgYIDQAAAA==.Priapista:BAAANQADCgUIBQAAAA==.Priyla:BAAANQABCgcICgAAAA==.Prosaic:BAAANQADCggICAABNQADCggICAACAAAAAA==.Pråhå:BAAANQAECgQIBAAAAA==.',
Ps='Psicopanda:BAAANQAECgQIBQAAAA==.',
Pu='Puffys:BAAANQADCgYIBgAAAA==.',
Pw='Pwcca:BAAANQAECgEIAQAAAA==.',
Qu='Queirozm:BAAANQADCgYIBgAAAA==.',
Ra='Radork:BAAANQAECgUICQAAAA==.Raewyn:BAAANQAECgcIDAAAAA==.Rafaelgame:BAAANQAECgIIBAAAAA==.Ragdead:BAABNQAECoEYAAIUAAgJqRpjGQBaAgAUAAgJqRpjGQBaAgAAAA==.Ragdöll:BAAANQADCgIIAgAAAA==.Ragnaryos:BAAANQAECgEIAQABNQAECggIGAAUAKkaAA==.Rairone:BAAANQAECgQIBwAAAA==.Raparigaloka:BAAANQAECgQIBAAAAA==.Rapunxel:BAABNQAECoEcAAMSAAgJhBJ7CQA6AgASAAgJhBJ7CQA6AgAVAAUJZAhncQAZAQAAAA==.Rarkion:BAAANQAECgMIBQAAAA==.Raulthalas:BAAANQADCgYIBgAAAA==.Rawrii:BAAANQADCgUIBQAAAA==.Raynmake:BAAANQAECgEIAQABNQAECgcIBwACAAAAAA==.',
Rb='Rbchama:BAAANQAECgQIDgAAAA==.',
Re='Redvil:BAAANQADCgUIBwAAAA==.Revoltedhunt:BAAANQAECggICgABNQAFFAUICwAWAEsQAA==.Revolthed:BAACNQAFFIELAAMWAAUJSxDUBgATAQAWAAQJyhPUBgATAQAFAAIJQQHeCwCDAAA1AAQKgR0AAxYACQkMISMHACADABYACQkMISMHACADAAUABAmFEveOAPkAAAAA.',
Rh='Rhaadora:BAAANQAECgQIBAAAAA==.Rhoghar:BAAANQAECgcIDAAAAA==.Rhoghardruid:BAAANQADCgIIAgABNQAECgcIDAACAAAAAA==.',
Ri='Riachu:BAAANQADCgcIAwAAAA==.',
Ro='Rokalf:BAAANQAECgYIDQAAAA==.Rossiten:BAAANQAECgMIBgAAAA==.Roöf:BAAANQAECgUIDQAAAA==.',
Ru='Runavento:BAAANQADCgIIAgAAAA==.Ruélatórta:BAAANQAECgQIBAAAAA==.',
['Rä']='Räidela:BAAANQAFFAEIAQAAAA==.',
Sa='Sagman:BAAANQABCgIIAgAAAA==.Sagädegemeos:BAAANQAECgQICAAAAA==.Salasär:BAAANQAECgYIDgAAAA==.Saleyi:BAAANQAECgEIAQAAAA==.Saluton:BAAANQAECgEIAgAAAA==.Samidemon:BAAANQADCgYIBgAAAA==.Sarashi:BAAANQADCgUICQAAAA==.Sarzlok:BAAANQAECgEIAQAAAA==.',
Sc='Schiabellee:BAAANQADCgUICQAAAA==.Scoobydruida:BAAANQAECgUICAAAAA==.Screan:BAAANQAECgUICwAAAA==.Scrøøge:BAAANQAECgQIBgAAAA==.',
Se='Seelyvorey:BAAANQAECgYICwAAAA==.Selph:BAAANQAECgYIAwAAAA==.Sengos:BAAANQAECgQIBAAAAA==.Sephhiroth:BAAANQADCgcICgAAAA==.Serrase:BAAANQAECgQICQAAAA==.',
Sh='Shalquoir:BAAANQAECgcIBgAAAA==.Sharckaron:BAAANQAECgEIAQAAAA==.Shedleass:BAAANQAECgMIBQAAAA==.Shendalar:BAAANQAECgQICgAAAA==.Shigami:BAAANQADCgcIBwAAAA==.Shywa:BAAANQADCgQIBgAAAA==.Shîvas:BAAANQAECgEIAgAAAA==.Shøtinha:BAAANQAECgcIDQAAAA==.Shøwtime:BAAANQAECgEIAQABNQAECgQIBwACAAAAAA==.',
Si='Sianus:BAAANQAECgIIAwAAAA==.Sicarious:BAAANQADCgYICwAAAA==.Sicariuz:BAAANQAECgUIDQAAAA==.Silara:BAAANQADCgMIAwAAAA==.Silves:BAAANQABCgYICgAAAA==.',
Sk='Skybourne:BAAANQADCgMIAwAAAA==.',
Sl='Slickdaddy:BAAANQADCgQIBAABNQAECgcICwACAAAAAA==.',
Sn='Snipinho:BAAANQAECgYICQAAAA==.Snowtail:BAAANQAECgIIBQABNQAECgQIBwACAAAAAA==.',
So='Sodragon:BAAANQADCgQIBAAAAA==.Sokun:BAAANQAECgEIAQAAAA==.Solaryel:BAAANQAECgUIBgAAAA==.Solidheals:BAAANQAECgIIBgAAAA==.Sougigante:BAAANQAECgIIAwAAAA==.Soupombagira:BAAANQAECgMIAwAAAA==.',
Sp='Spellshadown:BAAANQAECgUIDAAAAA==.Spratch:BAAANQADCgQIBAAAAA==.',
Sr='Srburns:BAAANQAECgIIAgAAAA==.',
St='Stelluna:BAAANQADCggICgAAAA==.Stormimrage:BAAANQADCgcIDQAAAA==.Strexx:BAAANQAECgEIAQAAAA==.Stronoffgard:BAAANQAECgYICwAAAA==.Stronq:BAAANQADCgYICAAAAA==.',
Su='Sulfur:BAAANQAECgIIBAAAAA==.',
Sy='Syberdal:BAAANQAECgQICwAAAA==.',
['Sà']='Sàgadegemeos:BAAANQAECgQICwAAAA==.',
['Sï']='Sïlent:BAAANQADCgMIBAABNQAECggIGAAVABkaAA==.',
Ta='Tacka:BAAANQADCgYIFgAAAA==.Tafoki:BAAANQAECgYIDAAAAA==.Tanakin:BAAANQADCgIIAgABNQAECgcIEAACAAAAAA==.Tangdebanana:BAAANQADCgUIBQABNQAECgQIBwACAAAAAA==.Tankairotty:BAAANQAECgEIAQAAAA==.Tassali:BAAANQADCgQIBgAAAA==.',
Td='Tdarklord:BAAANQADCggIFAAAAA==.',
Te='Temkutemmedo:BAAANQAECgIIBQABNQADCggIEAACAAAAAA==.Tennkkar:BAAANQAECgEIAQAAAA==.Texugojogatv:BAAANQAECgIIAwAAAA==.Texugosa:BAAANQAECgEIAQAAAA==.',
Th='Thamihime:BAAANQAECgUICgAAAA==.Tharizdum:BAAANQAECgQICQAAAA==.Thontonas:BAAANQADCgIIAgAAAA==.Thornus:BAAANQAFFAEIAQAAAA==.Thorudos:BAAANQADCgQIAgAAAA==.Thrandu:BAAANQADCgYIBgAAAA==.Thulin:BAAANQADCgMIAwAAAA==.Thuzalduum:BAAANQADCgIIAgAAAA==.',
Tn='Tntgirl:BAAANQAECgIIAgABNQAECgIIBAACAAAAAA==.',
To='Toni:BAAANQAECgIIAgAAAA==.Tostão:BAAANQADCgQIBgAAAA==.Touchhme:BAAANQAECgIIAgAAAA==.Toven:BAAANQADCgQIBAABNQADCgUICQACAAAAAA==.',
Tp='Tprdmage:BAAANQAECgEIAQAAAA==.Tprdtank:BAAANQABCgQIBAAAAA==.',
Tr='Trighit:BAAANQADCgMIAwAAAA==.Trolhöl:BAAANQAECgYIDAAAAA==.Trollrogue:BAAANQAECgUICAAAAA==.Troyana:BAAANQADCggICAABNQAFFAMIBQAPAIQXAA==.',
Tu='Tukiel:BAAANQAECgEIAwAAAA==.Tunkav:BAAANQABCgUIBQAAAA==.Tuska:BAAANQADCgUIBAAAAA==.',
Ty='Tyde:BAAANQAECgMIAgABNQAECgQICgACAAAAAA==.Typol:BAAANQAECgIIAwAAAA==.',
['Tó']='Tóten:BAAANQADCgUIBQAAAA==.',
['Tö']='Törtz:BAAANQAECgQIBgAAAA==.',
['Tø']='Tøtemhubby:BAAANQADCgQIBAAAAA==.',
Ug='Ugabugah:BAAANQADCgIIAgAAAA==.',
Ul='Ulish:BAAANQAECgEIAQAAAA==.',
Um='Umburana:BAAANQADCgMIAwABNQADCgUICQACAAAAAA==.Umehara:BAABNQAECoEZAAIWAAgJDh0LDgCoAgAWAAgJDh0LDgCoAgAAAA==.Umokh:BAAANQAECgcIEAAAAA==.',
Un='Unbrøken:BAAANQAECgEIAgAAAA==.Unclearnaldo:BAAANQADCgYIBgABNQAECgQIBQACAAAAAA==.',
Uo='Uolokoelfo:BAABNQAECoEeAAIPAAgJthzWJAC6AgAPAAgJthzWJAC6AgAAAA==.',
Ur='Urannia:BAABNQAECoEVAAIFAAcJAw0ISADXAQAFAAcJAw0ISADXAQAAAA==.Urgath:BAAANQAECgMIBQAAAA==.',
Ut='Uther:BAAANQAECgIIAgAAAA==.',
Va='Valan:BAAANQAECgEIAgAAAA==.Valdeco:BAAANQADCgMIAwAAAA==.Valdevino:BAAANQAECgQIAwAAAA==.Valk:BAAANQADCgIIAgAAAA==.Varyssa:BAAANQADCggIDgAAAA==.Vazgoroth:BAAANQADCgYICgAAAA==.',
Ve='Venator:BAAANQAECgQIBwAAAA==.Venonpoison:BAAANQADCgMIAgAAAA==.Vermeryn:BAAANQAECgEIAQAAAA==.',
Vi='Viciadø:BAAANQADCggICAABNQAECggIEAACAAAAAA==.Villalobos:BAAANQAECgIIBAAAAA==.Vits:BAAANQAECgQICgAAAA==.',
Vo='Voidsurge:BAAANQAECgEIAQAAAA==.Voidwar:BAAANQADCgQIBAABNQAECgEIAQACAAAAAA==.Vollin:BAAANQAECgQIAgAAAA==.Volrun:BAAANQADCggIDAAAAA==.Voragem:BAAANQAECgQIBwAAAA==.',
Vu='Vulkova:BAAANQADCgQIBQAAAA==.',
Wa='Warlockdoido:BAAANQAECgEIAQAAAA==.Warlôka:BAAANQADCgUIBQAAAA==.',
Wi='Wiillord:BAAANQAECgEIAQAAAA==.Willbm:BAAANQAECgUIDgAAAA==.Winnettou:BAAANQAECgMIAwAAAA==.Wipalogo:BAAANQADCggIEAAAAA==.Wise:BAAANQAECggIEgAAAA==.',
Wm='Wmana:BAAANQAECgQICQAAAA==.',
Wu='Wuan:BAAANQAECgYICwAAAA==.',
Xa='Xamanico:BAAANQAECgQIBAAAAA==.Xanasmanas:BAAANQAECgYIDQAAAA==.Xazon:BAAANQADCgQIBAAAAA==.',
Xh='Xharlios:BAAANQADCggIFgAAAA==.',
Xu='Xusp:BAAANQADCggIDgAAAA==.',
Xx='Xxbizu:BAAANQAECgUICAAAAA==.',
Xy='Xymor:BAABNQAECoEcAAIXAAkJhR+eAwAyAwAXAAkJhR+eAwAyAwABNQAECgQIBAACAAAAAA==.',
Ya='Yagaami:BAAANQADCgQIBAAAAA==.Yant:BAAANQADCgYIBgAAAA==.',
Ye='Yenniferxd:BAAANQABCgUIBQAAAA==.',
Yl='Ylanna:BAAANQAECgUICgAAAA==.',
Yo='Yonnyson:BAAANQADCgEIAQAAAA==.Yoodoo:BAAANQABCgMIAwAAAA==.Yoriko:BAAANQAECgQIBAAAAA==.Yorú:BAAANQAECgQIBgAAAA==.',
Yu='Yulaw:BAAANQADCgQIBAAAAA==.',
['Yá']='Yásuo:BAAANQADCgcIEwAAAA==.',
Za='Zamii:BAAANQADCgIIAgABNQAECgQIBQACAAAAAA==.Zarik:BAAANQADCgcIBwAAAA==.',
Ze='Zenolis:BAAANQADCgcIDQAAAA==.Zerathir:BAAANQADCgIIAgAAAA==.',
Zh='Zhalazar:BAAANQAECgQIBAAAAA==.Zhenb:BAAANQADCgEIAQAAAA==.',
Zi='Zigosmar:BAAANQABCgIIAgAAAA==.',
Zo='Zolet:BAAANQAECgEIAQAAAA==.Zones:BAAANQAECgEIAQABNQAECgQIBgACAAAAAA==.',
Zu='Zumbix:BAAANQADCgcIBwAAAA==.',
['Äl']='Älexandër:BAAANQADCgYIBgAAAA==.',
['Än']='Ängron:BAAANQAECgEIAwAAAA==.Änä:BAAANQADCggIDgAAAA==.',
['Är']='Ärthås:BAAANQADCgMIAwAAAA==.',
['Äz']='Äzra:BAAANQAECgEIAQAAAA==.',
['Ær']='Ærikão:BAAANQAECgQIBQAAAA==.',
['Æt']='Ætherfel:BAAANQAECgIIAgAAAA==.',
['Ét']='Étel:BAAANQADCgYIFgAAAA==.',
['Ðr']='Ðrakko:BAAANQADCgQICAAAAA==.',
['Ör']='Örigem:BAAANQAECgEIAQAAAA==.',
['ßl']='ßlåkehunter:BAAANQADCgEIAQAAAA==.',
['ßr']='ßradvi:BAAANQADCggIDAAAAA==.ßrutalßarbie:BAAANQADCgYIBgAAAA==.',
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
