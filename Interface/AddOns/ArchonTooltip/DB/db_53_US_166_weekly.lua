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

local lookup = {'Priest-Shadow','DemonHunter-Devourer','Unknown-Unknown','Druid-Balance','Warrior-Arms','Warrior-Fury','Priest-Holy','Warlock-Demonology','Hunter-Marksmanship','Hunter-BeastMastery','Evoker-Devastation',}
local provider = {region='US',realm='Nemesis',name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Abyssdk:BAAANQAECgEIAQABNQAECgkJFwABABwgAA==.',
Ac='Acadêmica:BAAANQAECgIIAgAAAA==.Acnaya:BAAANQADCgQIBAAAAA==.',
Ad='Adebaio:BAAANQAECgcIEgAAAA==.',
Ae='Aegislashh:BAAANQAECgUIBQAAAA==.Aerlath:BAABNQAECoEYAAICAAkJ2yDVAgCCAwACAAkJ2yDVAgCCAwAAAA==.Aetherius:BAAANQADCgMIAwAAAA==.Aetulia:BAAANQAECgEIAQAAAA==.',
Af='Afixo:BAAANQADCgQIBAABNQADCggICAADAAAAAA==.',
Ag='Aggroster:BAAANQAECgEIAQAAAA==.Agnestesia:BAAANQAECgQIBwAAAA==.',
Ah='Ahrathor:BAAANQADCggICQAAAA==.',
Ak='Akasta:BAAANQAECgUIBwAAAA==.Akkiralock:BAAANQADCgYIBgAAAA==.',
Al='Alascayoung:BAAANQADCggIDgAAAA==.Alatroz:BAAANQADCgIIAgAAAA==.Aldrathion:BAAANQAECgEIAQABNQAECggIEgADAAAAAA==.Aledk:BAAANQADCgYIEAAAAA==.Alessan:BAAANQADCgYIBgAAAA==.Alessary:BAAANQADCgYICQAAAA==.Alfurieb:BAAANQADCgYIGQAAAA==.Alianar:BAAANQADCgMIAwAAAA==.Alicel:BAAANQAECgcIDgAAAA==.Altreir:BAAANQADCgYICgABNQADCggICAADAAAAAA==.Aluny:BAAANQABCgEIAQABNQAECgQICAADAAAAAA==.Aluxxious:BAAANQAECgQIBQAAAA==.Alíne:BAAANQADCggIFgAAAA==.',
Am='Amøm:BAAANQAECgMIAwAAAA==.',
An='Andärilho:BAAANQADCgYICwAAAA==.Ankados:BAAANQAECgUICQABNQAECgcIDQADAAAAAA==.Ankapos:BAAANQAECgEIAQAAAA==.Annish:BAAANQADCgYICwAAAA==.Anthorforged:BAAANQAECgIIAgAAAA==.',
Ap='Apocalipse:BAAANQAECgcIDQAAAA==.',
Aq='Aquillez:BAAANQADCgcIBwAAAA==.',
Ar='Araurz:BAAANQADCgIIAgABNQAECgEIAgADAAAAAA==.Arinn:BAAANQADCggIFgAAAA==.Artradian:BAAANQADCggIDQAAAA==.Aryethi:BAAANQAECgQICAAAAA==.',
As='Ashabellanar:BAAANQAECgMIBQAAAA==.Aslatiel:BAAANQADCgYIBgABNQAECgEIAQADAAAAAA==.',
Au='Aurdraen:BAAANQADCgIIAwAAAA==.',
Av='Avanthara:BAAANQAECgEIAQAAAA==.',
Aw='Awk:BAAANQAECgEIAQAAAA==.',
['Aø']='Aøc:BAAANQAECgYIDgAAAA==.',
Ba='Babara:BAAANQABCgQIBAAAAA==.Babyfart:BAAANQAECgMIBAAAAA==.Bakushiterra:BAAANQAECgIIAwAAAA==.Barao:BAAANQAECgMIBAAAAA==.Barriguinha:BAAANQAECgEIAQAAAA==.Batlemage:BAAANQABCgQIBgAAAA==.Batmano:BAAANQADCgYICgAAAA==.',
Bh='Bherg:BAAANQADCggIEQAAAA==.',
Bi='Billpaxtonn:BAAANQAECgYIBgAAAA==.Biskademon:BAAANQAECgUIBgAAAA==.Bizum:BAAANQADCgcIDAAAAA==.',
Bj='Bjørn:BAAANQADCgQIBAAAAA==.',
Bl='Blackee:BAAANQADCgMIBAAAAA==.Blackwatch:BAAANQADCgcIEQAAAA==.Blitzkrig:BAAANQAFFAEIAQAAAA==.Bloodyclaw:BAAANQADCgcIDQAAAA==.',
Bo='Boomgoesyou:BAABNQAECoEWAAIEAAgJ1Q16HgDhAQAEAAgJ1Q16HgDhAQAAAA==.Bourdriel:BAAANQADCggIFQAAAA==.',
Br='Bradoki:BAAANQAECgMIBgAAAA==.Brancalleone:BAAANQADCggIEwAAAA==.Brazukmaiden:BAAANQAECgIIAgAAAA==.Brisawave:BAAANQAECggIEQAAAA==.Brizagato:BAAANQAECgQIBQAAAA==.Broke:BAAANQAECgMIAwAAAA==.Bruxxaum:BAAANQADCgEIAQAAAA==.Brád:BAAANQAECgIIBAAAAA==.',
Bu='Bushido:BAAANQADCgYIEgAAAA==.Bustgril:BAAANQADCgcIEAAAAA==.',
Bz='Bzbit:BAAANQADCgMIAgAAAA==.',
['Bé']='Béssi:BAAANQADCgMIAwAAAA==.',
Ca='Caiquebmq:BAAANQADCggIDwAAAA==.Calanguejo:BAAANQADCgQIBAABNQAECgIIAwADAAAAAA==.Calanguinhe:BAAANQADCggIDgAAAA==.Caldrin:BAAANQADCgEIAQAAAA==.Calliphora:BAAANQADCggIEgAAAA==.Canard:BAAANQADCgUICAABNQAECggIAQADAAAAAA==.Cannibal:BAAANQABCgYIBgAAAA==.Carloxamã:BAAANQAECgQIBwAAAA==.Cassisus:BAAANQADCggICAAAAA==.Catarnaldo:BAAANQADCgYIBgABNQAECgEIAQADAAAAAA==.Cathiseev:BAAANQAECgQIBQAAAA==.Cathury:BAAANQAECgEIBAAAAA==.Catÿ:BAAANQAECgQIBQABNQAFFAEIAQADAAAAAA==.Cavernozo:BAAANQADCgcICQAAAA==.Caxola:BAAANQADCgIIAgAAAA==.',
Ce='Cerino:BAAANQADCgQIBAAAAA==.',
Ch='Chaleira:BAAANQADCgQIBAAAAA==.Changjin:BAAANQADCgMIAwAAAA==.Chiclete:BAAANQAECgYICwAAAA==.Chopz:BAAANQADCgQIBAAAAA==.Chovor:BAAANQAECgIIAgAAAA==.Chrizantm:BAAANQADCgcICwABNQAECgEIAgADAAAAAA==.Chucknòórris:BAAANQADCgYIDAAAAA==.',
Cl='Clairë:BAAANQAECgEIAQAAAA==.Claude:BAAANQADCgQIBQAAAA==.Clio:BAAANQAECgQIBgAAAA==.',
Co='Coionir:BAAANQAECgIIAgAAAA==.Coiovoker:BAAANQADCgEIAQABNQAECgIIAgADAAAAAA==.Coldblooded:BAAANQADCgcIBwAAAA==.Comunistaa:BAAANQAECgcICQAAAA==.Contadoruns:BAAANQADCggIDgAAAA==.Corstine:BAAANQADCgcICgAAAA==.Corvynus:BAAANQADCgUIBgAAAA==.',
Cr='Cronosxdm:BAAANQAECgIIAgAAAA==.Crucyatus:BAAANQAECgMIBQAAAA==.Cruelmoon:BAAANQADCgEIAQAAAA==.',
['Cå']='Cåssio:BAAANQAECgYIBwAAAA==.',
['Cÿ']='Cÿgnus:BAAANQADCgEIAQABNQAECgYICQADAAAAAA==.',
Da='Dadashi:BAAANQADCggICAAAAA==.Danadinn:BAAANQADCgcIBwAAAA==.Danteholy:BAAANQADCgMIAwAAAA==.Darkhold:BAAANQAECgYICwAAAA==.Darklendio:BAAANQADCgUICQAAAA==.Daroncosp:BAAANQADCgIIAgAAAA==.Dashuman:BAAANQAECgQICAAAAA==.Davicohunter:BAAANQADCgIIAgAAAA==.Dazhu:BAAANQADCggICAAAAA==.',
De='Deadusopp:BAAANQADCgQIBAAAAA==.Deathatrix:BAAANQADCgUICAABNQAECgMIBQADAAAAAA==.Deceive:BAAANQAECgEIAQAAAA==.Defroque:BAAANQADCggIDgAAAA==.Deis:BAAANQADCgUIBAAAAA==.Delarÿn:BAAANQADCggIEAAAAA==.Demoncrashe:BAAANQADCgEIAQAAAA==.Demzumilde:BAAANQADCgYIBgAAAA==.Denevy:BAAANQAECgUIBwAAAA==.Deraelda:BAAANQADCgMIAwAAAA==.Derbster:BAAANQAECgUIAQAAAA==.Destructiom:BAAANQAECgQIBQABNQAECgYIBgADAAAAAA==.',
Dh='Dhamburguer:BAAANQAECgQIBQAAAA==.Dhanadrai:BAAANQAECgQIBAAAAA==.',
Di='Diggop:BAAANQADCgYIBgAAAA==.Dijank:BAAANQADCgIIAgABNQADCgUICQADAAAAAA==.Dima:BAAANQAECgYICQAAAA==.',
Do='Dornaa:BAAANQADCgYICgAAAA==.Dosmagos:BAAANQABCgMIBQAAAA==.Doulce:BAAANQADCgYIBgAAAA==.',
Dr='Dracarysz:BAAANQADCgUIBQAAAA==.Draculavmp:BAAANQADCgEIAQAAAA==.Dragonbaby:BAAANQADCgUIBQAAAA==.Drainetty:BAAANQAECgEIAQAAAA==.Dranacs:BAAANQAECggIAQAAAA==.Dreamremix:BAAANQAECgQIBAAAAA==.Dreyol:BAAANQADCgYICQAAAA==.Drts:BAAANQAECgYICwAAAA==.',
Ed='Eduarthas:BAAANQADCgUIBwAAAA==.',
El='Elementys:BAAANQAECgEIAgAAAA==.Elemëntum:BAAANQADCgcIBwAAAA==.Elfuryon:BAAANQADCgIIAgABNQAECggIEgADAAAAAA==.Elinaara:BAAANQAECgYICgAAAA==.Elliith:BAAANQADCgIIAgAAAA==.Ellithyx:BAAANQAECgIIAgAAAA==.Elricky:BAAANQADCgIIAwAAAA==.Eluna:BAAANQAECgEIAQAAAA==.Elwiñ:BAAANQADCgEIAQAAAA==.',
En='Encanis:BAAANQADCgYIAgAAAA==.',
Er='Ermooke:BAAANQAECgEIAQAAAA==.',
Es='Escanorzão:BAAANQADCgcIBwABNQADCggICAADAAAAAA==.Escola:BAAANQAECgQICQAAAA==.',
Ex='Exo:BAAANQAECgUICAAAAA==.Exorciseur:BAAANQAECgcIEQAAAA==.',
Fa='Fabercästell:BAAANQADCgYICwAAAA==.Fabers:BAAANQAECgMIAwAAAA==.Fargunn:BAAANQAECgIIAgAAAA==.',
Fe='Feanori:BAAANQAECgUIBgAAAA==.Feanør:BAAANQADCgYIDQAAAA==.Feinanduo:BAAANQADCgMIAwAAAA==.Felfury:BAAANQADCgUIBQABNQAECgQIBQADAAAAAA==.Feyrin:BAAANQADCggIFAAAAA==.',
Fi='Finngermy:BAAANQADCggICQAAAA==.',
Fl='Flodearthen:BAAANQADCgQIBwABNQAECgEIAQADAAAAAA==.Flodfelblood:BAAANQAECgEIAQAAAA==.',
['Fí']='Fíli:BAAANQADCgQIBAAAAA==.',
['Fï']='Fïrestorm:BAAANQADCgYIBgAAAA==.',
Ga='Gabela:BAAANQADCgUIBwAAAA==.Gaiataur:BAAANQADCgMIAwAAAA==.Galandiel:BAAANQADCggICAAAAA==.Galinni:BAAANQADCggICAAAAA==.Gallon:BAAANQAECgEIAQAAAA==.',
Gl='Glacyale:BAAANQADCgcICgAAAA==.Glisa:BAAANQADCgcIBwAAAA==.',
Gn='Gnomepink:BAAANQADCggIEwAAAA==.',
Go='Godadrian:BAAANQAECgIIAgAAAA==.Gosu:BAAANQAECgMIAwAAAA==.',
Gr='Gralfor:BAAANQADCggIDwAAAA==.Grekorio:BAAANQADCgYIBgAAAA==.Greylord:BAAANQAECgIIAgABNQAECgIIBAADAAAAAA==.Greylorddrak:BAAANQAECgIIBAAAAA==.Greylordp:BAAANQAECgEIAQABNQAECgIIBAADAAAAAA==.Gronak:BAAANQADCgcIBwAAAA==.',
Gu='Gults:BAAANQADCgQIBAAAAA==.Gultsz:BAAANQADCgQIBgAAAA==.Gunpowter:BAAANQABCgIIAwAAAA==.Guxrock:BAAANQAECgEIAQAAAA==.',
Gy='Gyllenhaal:BAAANQADCgUIBQAAAA==.',
['Gä']='Gäspär:BAAANQADCgYIBgAAAA==.',
['Gø']='Gødmar:BAAANQAECgIIAgAAAA==.',
Ha='Hagnaredk:BAAANQADCgMIAwAAAA==.Haiume:BAAANQAECgQIBAAAAA==.Hamiister:BAAANQADCgQIBAAAAA==.Hancalimon:BAAANQAECgQIBwAAAA==.Haokö:BAAANQADCgYIBgAAAA==.Hastterix:BAAANQADCgQIAgAAAA==.Hatezon:BAAANQAECgEIAgAAAA==.',
He='Heavyking:BAAANQAECgEIAQAAAA==.Heishoo:BAAANQADCgIIAgAAAA==.Hellreaper:BAAANQAECgYIBwAAAA==.Heloisaa:BAAANQAECgIIAgAAAA==.Helwen:BAAANQAECgEIAQAAAA==.Heracranosx:BAAANQADCgcIEQAAAA==.Herdy:BAAANQADCgEIAQAAAA==.Herta:BAAANQAECgMIBgAAAA==.Hess:BAAANQAECgEIAQAAAA==.',
Hi='Hireque:BAAANQADCggIEQAAAA==.Hitkilled:BAAANQADCggICAAAAA==.Hitkins:BAAANQADCgYIBgAAAA==.',
Ho='Hofpriest:BAAANQADCgUIBQAAAA==.Hoiac:BAAANQAECgMIBAAAAA==.Holycel:BAAANQADCggIDQABNQAECgcIDgADAAAAAA==.',
Hu='Hunterpica:BAAANQAECgIIAwAAAA==.Huntmon:BAAANQAECgQIBgAAAA==.Huskat:BAAANQAECgQICQAAAA==.',
Hy='Hysillens:BAAANQADCgcIDgAAAA==.',
['Hã']='Hãn:BAAANQADCgEIAQAAAA==.',
Il='Ilane:BAAANQABCgYICgAAAA==.Illidatrix:BAAANQAECgMIBQAAAA==.Illïndão:BAAANQADCggICAAAAA==.Ilovealtgirl:BAAANQADCggIDgAAAA==.',
In='Inot:BAAANQAECgEIAQAAAA==.',
Ir='Irmãsafada:BAAANQADCgEIAQAAAA==.',
Is='Iscariotes:BAAANQABCgQIBAAAAA==.Ismael:BAAANQAECgQIBAAAAA==.',
It='Itsälasca:BAAANQADCgUICgAAAA==.',
Iu='Iuri:BAAANQADCgcICAAAAA==.',
Iz='Izanna:BAAANQADCgcICwAAAA==.',
Ja='Jampack:BAAANQAECgcIDwAAAA==.',
Je='Jeevas:BAAANQAECgIIAwAAAA==.Jefté:BAAANQADCgEIAQAAAA==.Jeguinha:BAAANQABCgYICAAAAA==.Jeu:BAAANQADCgcICQAAAA==.Jeyla:BAAANQADCgEIAQAAAA==.',
Jh='Jhasperr:BAAANQADCggIDAAAAA==.',
Jo='Jocabiroca:BAAANQAECgUIBwAAAA==.Jotavê:BAAANQADCgUICQAAAA==.',
Jp='Jpleuk:BAAANQAECgMIAwAAAA==.',
Jr='Jrxamã:BAAANQADCgYIEAAAAA==.',
Ju='Juliia:BAAANQADCgEIAQAAAA==.Jusgu:BAAANQAECgIIAgAAAA==.',
Ka='Kaaliel:BAAANQADCgQIBQAAAA==.Kagero:BAAANQADCgQIBAAAAA==.Kaiev:BAAANQADCgMIBAAAAA==.Kaju:BAAANQAECgcIDgAAAA==.Kalinis:BAAANQADCgIIAgAAAA==.Kalliiope:BAAANQAECgQICAAAAA==.Kamïlla:BAAANQADCggIBgAAAA==.Karak:BAAANQADCgIIAgAAAA==.Karamatsu:BAAANQAECgIIAgAAAA==.Karollus:BAAANQABCgIIAgAAAA==.Kath:BAAANQADCgYIBgAAAA==.Kathana:BAAANQABCgYICAAAAA==.Katona:BAAANQADCgcIBwAAAA==.',
Kd='Kdposa:BAAANQABCgQIBAAAAA==.',
Ke='Keior:BAAANQADCgcIBwAAAA==.Kenai:BAAANQAECgMIAwAAAA==.Kewenz:BAAANQAECggIBAAAAA==.',
Kh='Khasin:BAAANQAECgMIAwAAAA==.',
Ki='Kindz:BAAANQADCgEIAQABNQAECggIBAADAAAAAA==.Kiregeth:BAAANQAECgMIBQAAAA==.Kitrel:BAAANQADCgYIBgAAAA==.',
Kl='Kllauzz:BAAANQAECgEIAQABNQAECgMIBAADAAAAAA==.Kllauzzmage:BAAANQADCgUICwABNQAECgMIBAADAAAAAA==.Kllauzzpalla:BAAANQAECgMIBAAAAA==.',
Ko='Kolyn:BAAANQAECggIEgAAAA==.Komamurasou:BAAANQAECgQIBAAAAA==.',
Kr='Krastian:BAAANQAECgMIBQAAAA==.Kreegh:BAAANQADCgQIBAAAAA==.Krupper:BAAANQAECgMIAwABNQAECgQICQADAAAAAA==.Krynesa:BAAANQADCgIIAgAAAA==.',
Ku='Kuhaku:BAAANQADCgQIBAAAAA==.',
Ky='Kyary:BAAANQADCgUIBQABNQAECgYICgADAAAAAA==.',
['Kä']='Kälini:BAAANQADCgcIDAABNQADCggIEAADAAAAAA==.',
['Kó']='Kónar:BAAANQADCgEIAQAAAA==.',
['Kö']='Köndmänö:BAAANQAECgQIBQAAAA==.Köri:BAAANQAECgUICQAAAA==.',
La='Lakaioo:BAAANQAECgMIAwAAAA==.Lamont:BAAANQAECgMIBQAAAA==.Lampiião:BAAANQAECgUICgAAAA==.Lanllaniel:BAAANQAECgIIBAAAAA==.Largartixa:BAAANQADCgQIBAABNQADCgcIBwADAAAAAA==.Larslion:BAAANQABCgYIBgAAAA==.',
Le='Lebelisco:BAAANQAECgEIAgAAAA==.Leehyori:BAAANQADCgcICwAAAA==.Lennorien:BAAANQAECgQIBQAAAA==.Lestard:BAAANQABCgQIBAAAAA==.',
Lh='Lhyunl:BAAANQADCgIIAgAAAA==.',
Li='Liciox:BAAANQADCgIIAgAAAA==.Lifestrream:BAAANQAECgUIBQAAAA==.Liftshertail:BAAANQAECgQIDAABNQAECgYIBQADAAAAAA==.Ligiaf:BAAANQADCgcIBwAAAA==.Linë:BAAANQADCgcIEwABNQADCggIEAADAAAAAA==.Linëa:BAAANQADCgEIAQAAAA==.Linüss:BAAANQADCgQICAAAAA==.Lionarot:BAAANQAECgIIAgAAAA==.Littleshelby:BAAANQADCgYIBgAAAA==.',
Lo='Lobinøx:BAAANQADCggICAAAAA==.Longaim:BAAANQAECgUIBgAAAA==.Lorthaeron:BAAANQAECgMIAwAAAA==.Lostminder:BAAANQAECgIIAgAAAA==.Lothbrok:BAAANQAECgUIBQAAAA==.',
Lu='Lucanor:BAAANQADCgUIBQAAAA==.Lucasbr:BAAANQADCggIDgAAAA==.Lucasyeah:BAABNQAECoEXAAMFAAkJqR6IDQAoAwAFAAkJDh6IDQAoAwAGAAEJ0CEtEQBjAAAAAA==.Lukanelas:BAAANQADCgEIAQAAAA==.Lulyssa:BAAANQADCggICwAAAA==.Luna:BAAANQAECgQIBgAAAA==.Lunes:BAAANQAECgIIAgAAAA==.Lusther:BAAANQADCggIDAAAAA==.Luzdacelesc:BAABNQAECoEXAAMBAAkJHCCzAwBbAwABAAkJHCCzAwBbAwAHAAEJgA3GYwBDAAAAAA==.',
Ly='Lyaah:BAAANQADCgYICwAAAA==.',
['Ló']='Lólzhé:BAAANQADCgYIBgAAAA==.',
['Lø']='Lølzhê:BAAANQAECgYIDQAAAA==.Løvizinha:BAAANQAECgQIBQAAAA==.',
['Lú']='Lúaprata:BAAANQADCggICAAAAA==.',
Ma='Madbuddha:BAAANQADCgQIBAAAAA==.Mageli:BAAANQABCgMIAwAAAA==.Magodanilo:BAAANQADCgYIBgAAAA==.Magodavida:BAAANQAECgQIBAAAAA==.Magodotruco:BAAANQADCgIIAgAAAA==.Maheena:BAAANQADCgYIDAAAAA==.Mai:BAAANQAECgQIBQAAAA==.Makksha:BAAANQADCgEIAQAAAA==.Makoto:BAAANQAECgIIAwAAAA==.Malborion:BAAANQADCggIEgAAAA==.Malignõ:BAAANQAECggIEAAAAA==.Maltozo:BAAANQAECgMIBwAAAA==.Mandrakson:BAAANQAECgQIBAAAAA==.Mandubim:BAAANQADCgEIAQAAAA==.Mariiamil:BAAANQADCgcIEQAAAA==.Marvvila:BAAANQAECgIIAgAAAA==.Marycristiny:BAAANQAECgQIBQAAAA==.Mazaky:BAAANQAECgQIBwAAAA==.',
Me='Megumi:BAAANQAECgEIAQAAAA==.Memphis:BAAANQADCgcIBwAAAA==.Menorxidil:BAAANQAECgcIDQAAAA==.Merigold:BAAANQADCgYICwAAAA==.Mestreløck:BAAANQADCgMIAwAAAA==.Metallicä:BAAANQADCgMIAwAAAA==.',
Mh='Mhenb:BAAANQAECgMIAwAAAA==.Mhorgothh:BAAANQADCgQIBAAAAA==.',
Mi='Mikal:BAAANQAECgEIAQAAAA==.Minort:BAAANQADCgcIBwAAAA==.Minör:BAAANQAECgEIAQAAAA==.Missmarvel:BAAANQABCgYICgAAAA==.Mizukagesou:BAAANQADCggICAAAAA==.',
Mo='Monkbest:BAAANQADCgcICAAAAA==.Montej:BAAANQADCgQIBgAAAA==.Montäna:BAAANQABCgMIAwAAAA==.Mooncap:BAAANQAECgEIAQAAAA==.Moondragoon:BAAANQADCgcICQAAAA==.Morakhir:BAAANQADCgQIBAAAAA==.Mordiidinha:BAAANQAECgEIAQABNQAECggIEAADAAAAAA==.Morganviolet:BAAANQADCggIEwAAAA==.',
Mu='Murdoky:BAAANQADCgEIAQABNQAECgEIAQADAAAAAA==.Musleira:BAAANQAECgEIAQAAAA==.',
My='Myrzin:BAAANQADCggIDAAAAA==.Mythcut:BAAANQAECgQIBAAAAA==.Mythjegue:BAAANQADCgYIBgAAAA==.',
['Mä']='Mällü:BAAANQADCggICAAAAA==.Mälthazar:BAAANQAECgQIBQAAAA==.Määt:BAAANQADCggICAABNQAECgkJFwAIAOsdAA==.',
['Må']='Mågus:BAAANQAECgIIAgAAAA==.',
['Mò']='Mòrgan:BAAANQADCgQIBQAAAA==.',
['Mø']='Mørgåna:BAAANQAECgEIAQAAAA==.',
Na='Naero:BAAANQADCgQIBAAAAA==.Naerylla:BAAANQADCgYICgAAAA==.Nagashina:BAAANQADCggIFgAAAA==.Naizow:BAAANQAECgMIBAAAAA==.Namisan:BAAANQADCgYIBgAAAA==.Namuhß:BAAANQAECgIIAgAAAA==.Naomiy:BAAANQADCgYIEAAAAA==.Naoto:BAAANQAECgQICQAAAA==.Napru:BAAANQADCgEIAQAAAA==.Narjes:BAAANQAECgQIBAAAAA==.',
Ne='Necrogélido:BAAANQADCgYIDAAAAA==.Neninhaa:BAAANQADCgcIBQAAAA==.Neopaladino:BAAANQADCgQIBgAAAA==.Nerlock:BAAANQADCgYIDwAAAA==.',
Ni='Nightforms:BAAANQADCggIEAAAAA==.Nikity:BAAANQAECgMIBgAAAA==.',
No='Noahwallker:BAAANQADCgYIBgAAAA==.Noazard:BAAANQADCggIFQAAAA==.Nopainnogain:BAAANQAECgEIAQAAAA==.Nortênho:BAAANQAECgQIBQAAAA==.Nossilat:BAAANQAECgYICQAAAA==.',
Nu='Nuit:BAAANQAECgEIAgAAAA==.Nunhöly:BAAANQAECgIIAgAAAA==.',
Ny='Nysthiael:BAAANQAECgQIBwAAAA==.Nyxicel:BAAANQAECgEIAgABNQAECgcIDgADAAAAAA==.',
['Nä']='Nästÿ:BAAANQADCgYIBgAAAA==.',
['Nö']='Nöturnö:BAAANQABCgYICgAAAA==.',
['Ný']='Nýmm:BAAANQAECgIIAgAAAA==.',
Oc='Ocon:BAAANQABCgIIAgAAAA==.',
Od='Odio:BAAANQADCgEIAQAAAA==.',
Ok='Okrigg:BAAANQADCgcIDgAAAA==.',
Ol='Oldcook:BAAANQABCgQIAwAAAA==.Oliele:BAAANQADCgQICAAAAA==.',
On='Onlydruix:BAAANQADCgIIAgAAAA==.',
Op='Opsdesculpa:BAAANQAECgMICAAAAA==.',
Or='Organ:BAAANQAECgQIBQAAAA==.Orinoldo:BAAANQAECgcIDgAAAA==.',
Ot='Otacki:BAAANQADCgIIAgAAAA==.Otherside:BAAANQAECgMIAwABNQAECgcIEQADAAAAAA==.Otávio:BAAANQADCgUICQAAAA==.',
Ox='Oxentedragon:BAAANQADCgMIAwAAAA==.',
Pa='Palluz:BAAANQADCgYIBgABNQAECgcIDgADAAAAAA==.Panicdeath:BAAANQAECgEIAQAAAA==.Parafinaisis:BAAANQADCggIEQAAAA==.Parafinared:BAAANQADCgUIBQAAAA==.Parrot:BAAANQADCgEIAQAAAA==.Pauladinho:BAAANQADCgIIAgAAAA==.',
Pe='Peltrow:BAAANQAFFAEIAQAAAA==.Penndrive:BAAANQADCgEIAQAAAA==.Perciwal:BAAANQADCgQIBAABNQAECgMIBQADAAAAAA==.Pesaa:BAAANQAECgQIBgAAAA==.',
Ph='Phanttoz:BAAANQADCgIIAgAAAA==.Phesti:BAAANQABCgEIAQAAAA==.Philii:BAAANQADCggIDQAAAA==.',
Pi='Pirizin:BAAANQAECgQICgAAAA==.',
Po='Popopeka:BAAANQADCgcIBwAAAA==.Porcaleta:BAAANQAECgQIBAAAAA==.Portal:BAAANQAECgIIAgAAAA==.Portelamage:BAAANQAECgUIDQAAAA==.Portheus:BAAANQADCggIFwAAAA==.',
Pr='Praeglacius:BAAANQAECgQIBwAAAA==.Priapista:BAAANQADCgUIBQAAAA==.Priyla:BAAANQABCgQIBAAAAA==.Prosaic:BAAANQADCggICAAAAA==.',
Ps='Psicopanda:BAAANQAECgEIAQAAAA==.',
Pu='Puffys:BAAANQABCgYICAABNQADCgUIEwADAAAAAA==.',
Pw='Pwcca:BAAANQADCggIDwAAAA==.',
Qu='Queirozm:BAAANQADCgYIBgAAAA==.',
Ra='Radork:BAAANQAECgUIBQAAAA==.Raewyn:BAAANQAECgcICQAAAA==.Rafaelgame:BAAANQAECgIIAgAAAA==.Ragdead:BAAANQAECgcIDQAAAA==.Ragnaryos:BAAANQAECgEIAQABNQAECgcIDQADAAAAAA==.Rairone:BAAANQAECgQIBwAAAA==.Rapunxel:BAAANQAECgcIEQAAAA==.Rarkion:BAAANQAECgIIAgAAAA==.Raulthalas:BAAANQADCgYIBgAAAA==.Raynmake:BAAANQADCgYIBgABNQAECgYIBQADAAAAAA==.',
Rb='Rbchama:BAAANQAECgQICQAAAA==.',
Re='Redvil:BAAANQADCgUIBQAAAA==.Revoltedhunt:BAAANQAECgYIBgABNQAFFAQIBgAJAFQPAA==.Revolthed:BAACNQAFFIEGAAIJAAQJVA/HAwAYAQAJAAQJVA/HAwAYAQA1AAQKgRkAAwkACQn4HHsGABEDAAkACQn4HHsGABEDAAoABAmFEo5iAP8AAAAA.',
Rh='Rhaadora:BAAANQADCgYIBwABNQAECgIIAgADAAAAAA==.Rhoghar:BAAANQAECgYIBQAAAA==.',
Ri='Riachu:BAAANQADCgcIAwAAAA==.',
Ro='Rokalf:BAAANQAECgQICAAAAA==.Rossiten:BAAANQAECgMIAwAAAA==.Roöf:BAAANQAECgUICQAAAA==.',
Ru='Ruélatórta:BAAANQAECgQIBAAAAA==.',
['Rä']='Räidela:BAAANQAECgUIBgAAAA==.',
Sa='Sagman:BAAANQABCgIIAgAAAA==.Sagädegemeos:BAAANQAECgQIBAAAAA==.Salasär:BAAANQAECgYIBgAAAA==.Saleyi:BAAANQADCggIEwAAAA==.Saluton:BAAANQAECgEIAgAAAA==.Samidemon:BAAANQADCgYIBgAAAA==.Sarashi:BAAANQADCgUICQAAAA==.Sarzlok:BAAANQADCggIEQAAAA==.',
Sc='Scoobydruida:BAAANQAECgEIAgAAAA==.Screan:BAAANQAECgUIBgAAAA==.Scrøøge:BAAANQAECgIIAgAAAA==.',
Se='Seelyvorey:BAAANQAECgUIBQAAAA==.Selph:BAAANQADCgYICwABNQADCgcICQADAAAAAA==.Sephhiroth:BAAANQADCgMIAwAAAA==.Serrase:BAAANQAECgQIBgAAAA==.',
Sh='Shalivane:BAAANQADCgYIBgAAAA==.Shalquoir:BAAANQAECgYIBQAAAA==.Sharckaron:BAAANQADCggIFgAAAA==.Shedleass:BAAANQAECgMIAwAAAA==.Shendalar:BAAANQAECgQIBgAAAA==.Shigami:BAAANQADCgcIBwAAAA==.Shywa:BAAANQADCgIIAgAAAA==.Shîvas:BAAANQADCgYIBwAAAA==.Shøtinha:BAAANQAECgYIBwAAAA==.Shøwtime:BAAANQAECgEIAQABNQAECgQIBAADAAAAAA==.',
Si='Sianus:BAAANQAECgIIAgAAAA==.Sicarious:BAAANQADCgYICwAAAA==.Sicariuz:BAAANQAECgQIBAAAAA==.Silara:BAAANQADCgMIAwAAAA==.',
Sk='Skybourne:BAAANQADCgMIAwAAAA==.',
Sl='Slickdaddy:BAAANQADCgQIBAABNQAECgQIBwADAAAAAA==.',
Sn='Snipinho:BAAANQAECgQIBAAAAA==.Snowtail:BAAANQAECgEIAgABNQAECgQIBwADAAAAAA==.',
So='Sodragon:BAAANQADCgQIBAAAAA==.Sokun:BAAANQAECgEIAQAAAA==.Solaryel:BAAANQADCggIEwAAAA==.Solidheals:BAAANQAECgIIBAAAAA==.Sougigante:BAAANQAECgEIAQAAAA==.Soupombagira:BAAANQAECgMIAwAAAA==.',
Sp='Spellshadown:BAAANQAECgMIBgAAAA==.Spratch:BAAANQADCgQIBAAAAA==.',
Sr='Srburns:BAAANQADCgEIAQAAAA==.',
St='Stelluna:BAAANQADCgYIBwAAAA==.Stormimrage:BAAANQADCgYIDAAAAA==.Strexx:BAAANQADCggIDwAAAA==.Stronoffgard:BAAANQAECgUIBQAAAA==.Stronq:BAAANQADCgYICAAAAA==.',
Su='Sulfur:BAAANQAECgIIAwAAAA==.',
Sy='Syberdal:BAAANQAECgQIBwAAAA==.',
['Sà']='Sàgadegemeos:BAAANQAECgQIBwAAAA==.',
['Sï']='Sïlent:BAAANQADCgMIBAABNQAECgcIDwADAAAAAA==.',
Ta='Tacka:BAAANQADCgYIEQAAAA==.Tafoki:BAAANQAECgcICQAAAA==.Tanakin:BAAANQADCgIIAgABNQAECgYICgADAAAAAA==.Tankairotty:BAAANQAECgEIAQAAAA==.Tanrity:BAAANQADCgcIBwAAAA==.Tassali:BAAANQADCgQIBgAAAA==.',
Td='Tdarklord:BAAANQADCgUIBwAAAA==.',
Te='Temkutemmedo:BAAANQAECgIIBQABNQADCggICAADAAAAAA==.Tennkkar:BAAANQADCgQIAwAAAA==.Texugojogatv:BAAANQAECgIIAgAAAA==.Texugosa:BAAANQAECgEIAQAAAA==.',
Th='Thamihime:BAAANQAECgMIBQAAAA==.Tharizdum:BAAANQAECgQIBQAAAA==.Thontonas:BAAANQADCgIIAgAAAA==.Thornus:BAAANQAECgcIEQAAAA==.Thorudos:BAAANQADCgQIAgAAAA==.Thrandu:BAAANQADCgYIBgAAAA==.Thulin:BAAANQADCgMIAwAAAA==.Thuzalduum:BAAANQADCgIIAgAAAA==.',
To='Toni:BAAANQADCggIEQAAAA==.Touchhme:BAAANQADCgcIBwAAAA==.Toven:BAAANQADCgQIBAABNQADCgUICQADAAAAAA==.',
Tp='Tprdmage:BAAANQAECgEIAQAAAA==.Tprdtank:BAAANQABCgQIBAAAAA==.',
Tr='Trighit:BAAANQADCgMIAwAAAA==.Trolhöl:BAAANQAECgUIBgAAAA==.Trollrogue:BAAANQAECgMIAwAAAA==.Troyana:BAAANQADCggICAABNQAECgkJGAAFAMohAA==.',
Tu='Tukiel:BAAANQAECgEIAwAAAA==.Tuska:BAAANQADCgUIBAAAAA==.',
Ty='Tyde:BAAANQADCgYIDAABNQAECgQIBgADAAAAAA==.Typol:BAAANQAECgEIAQAAAA==.',
['Tó']='Tóten:BAAANQADCgUIBQAAAA==.',
['Tö']='Törtz:BAAANQAECgIIAgAAAA==.',
['Tø']='Tøtemhubby:BAAANQADCgMIAQAAAA==.',
Ug='Ugabugah:BAAANQADCgIIAgAAAA==.',
Ul='Ulish:BAAANQAECgEIAQAAAA==.',
Um='Umburana:BAAANQADCgMIAwABNQADCgUICQADAAAAAA==.Umehara:BAAANQAECgcIEAAAAA==.Umokh:BAAANQAECgYICgAAAA==.',
Un='Unbrøken:BAAANQAECgEIAgAAAA==.Unclearnaldo:BAAANQADCgYIBgABNQAECgEIAQADAAAAAA==.',
Uo='Uolokoelfo:BAABNQAECoEXAAIFAAgJnxhvJQBiAgAFAAgJnxhvJQBiAgAAAA==.',
Ur='Urannia:BAAANQAECgYIEQAAAA==.Urgath:BAAANQAECgEIAQAAAA==.',
Va='Valan:BAAANQAECgEIAQAAAA==.Valdevino:BAAANQAECgEIAQAAAA==.Valk:BAAANQADCgIIAgAAAA==.Varyssa:BAAANQADCggIDgAAAA==.Vazgoroth:BAAANQADCgYICgAAAA==.',
Ve='Venator:BAAANQAECgIIAwAAAA==.',
Vi='Viciadø:BAAANQADCgYIBQABNQAECgcICQADAAAAAA==.Villalobos:BAAANQAECgIIAwAAAA==.Vits:BAAANQAECgQIBgAAAA==.',
Vo='Voidsurge:BAAANQADCgcIDQAAAA==.Voidwar:BAAANQADCgQIBAABNQADCgcIDQADAAAAAA==.Vollin:BAAANQADCgcIBwAAAA==.Volrun:BAAANQADCggICQAAAA==.Voragem:BAAANQAECgIIAwAAAA==.',
Vu='Vulkova:BAAANQADCgQIBQAAAA==.',
Wa='Warlôka:BAAANQADCgUIBQAAAA==.',
Wi='Wiillord:BAAANQAECgEIAQAAAA==.Willbm:BAAANQAECgMIBQAAAA==.Winnettou:BAAANQAECgEIAQAAAA==.Wipalogo:BAAANQADCggICAAAAA==.Wise:BAAANQAECgcICwAAAA==.',
Wm='Wmana:BAAANQAECgMIBQAAAA==.',
Wu='Wuan:BAAANQAECgQICAAAAA==.',
Xa='Xamanico:BAAANQAECgIIAgAAAA==.Xanasmanas:BAAANQAECgMIBwAAAA==.',
Xh='Xharlios:BAAANQADCggIFAAAAA==.',
Xu='Xusp:BAAANQADCggIDgAAAA==.',
Xx='Xxbizu:BAAANQAECgMIAwAAAA==.',
Xy='Xymor:BAABNQAECoEXAAILAAgJ/R4iBQDWAgALAAgJ/R4iBQDWAgABNQAECgQIBAADAAAAAA==.',
Ya='Yagaami:BAAANQADCgQIBAAAAA==.Yant:BAAANQADCgYIBgAAAA==.',
Yl='Ylanna:BAAANQAECgQIBQAAAA==.',
Yo='Yonnyson:BAAANQADCgEIAQAAAA==.Yoriko:BAAANQAECgQIBAAAAA==.Yorú:BAAANQAECgIIAgAAAA==.',
Yu='Yulaw:BAAANQADCgQIBAAAAA==.',
['Yá']='Yásuo:BAAANQADCgcIEwAAAA==.',
Ze='Zenolis:BAAANQADCgYIBgAAAA==.',
Zh='Zhalazar:BAAANQADCgcIBwAAAA==.',
Zi='Zigosmar:BAAANQABCgIIAgAAAA==.',
Zo='Zolet:BAAANQAECgEIAQAAAA==.Zones:BAAANQADCgIIAgABNQAECgIIAgADAAAAAA==.',
Zu='Zumbix:BAAANQADCgcIBwAAAA==.',
['Äl']='Älexandër:BAAANQADCgYIBgAAAA==.',
['Än']='Ängron:BAAANQADCgQIBQAAAA==.Änä:BAAANQADCgYIBgAAAA==.',
['Ær']='Ærikão:BAAANQAECgEIAgAAAA==.',
['Æt']='Ætherfel:BAAANQAECgIIAgAAAA==.',
['Ét']='Étel:BAAANQADCgYICwAAAA==.',
['Ör']='Örigem:BAAANQADCgcICQAAAA==.',
['ßr']='ßradvi:BAAANQADCggIDAAAAA==.',
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
