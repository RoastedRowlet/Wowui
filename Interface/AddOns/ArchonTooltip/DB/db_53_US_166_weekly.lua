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
local provider = {region='US',realm='Nemesis',name='US',type='weekly',zone=53,date='2026-09-01',data={Ab='Abyssdk:BAAANQAECgEIAQABNQAECggIDQABAAAAAA==.',
Ac='Acadêmica:BAAANQADCgYICgABNQAECgIIAgABAAAAAA==.Acnaya:BAAANQADCgQIBAAAAA==.',
Ad='Adebaio:BAAANQAECgYICwAAAA==.',
Ae='Aegislashh:BAAANQADCgUIBQAAAA==.Aerlath:BAAANQAFFAEIAQAAAA==.Aetherius:BAAANQADCgMIAwAAAA==.Aetulia:BAAANQADCgYIEgAAAA==.',
Af='Afixo:BAAANQADCgQIBAABNQABCgQIBAABAAAAAA==.',
Ag='Aggroster:BAAANQAECgEIAQAAAA==.Agiota:BAAANQAECgQIBQAAAA==.Agnestesia:BAAANQAECgMIAwAAAA==.',
Ah='Ahrathor:BAAANQADCgQIBAAAAA==.',
Ak='Akasta:BAAANQAECgIIAgAAAA==.Akkiralock:BAAANQADCgYIBgAAAA==.',
Al='Alascayoung:BAAANQADCgYIBgAAAA==.Alatroz:BAAANQADCgIIAgAAAA==.Aldrathion:BAAANQAECgEIAQABNQAECgYICwABAAAAAA==.Aledk:BAAANQADCgYICgAAAA==.Alfurieb:BAAANQADCgYIEQAAAA==.Alicel:BAAANQAECgYIBwAAAA==.Altreir:BAAANQADCgUIBQABNQABCgQIBAABAAAAAA==.Aluxxious:BAAANQAECgEIAQAAAA==.Alíne:BAAANQADCggIDgAAAA==.',
Am='Amøm:BAAANQADCgIIAgAAAA==.',
An='Andärilho:BAAANQADCgYICwAAAA==.Ankados:BAAANQAECgQIBAAAAA==.Ankapos:BAAANQADCggICAAAAA==.Annish:BAAANQADCgUIBQAAAA==.Anthorforged:BAAANQADCggIFQAAAA==.',
Ap='Apocalipse:BAAANQAECgUIBgAAAA==.',
Ar='Arinn:BAAANQADCggIDgAAAA==.Artradian:BAAANQADCgcICQAAAA==.Aryethi:BAAANQAECgIIAwAAAA==.',
As='Ashabellanar:BAAANQAECgIIAgAAAA==.',
Au='Aurdraen:BAAANQADCgIIAwAAAA==.',
Av='Avanthara:BAAANQADCgIIBAAAAA==.',
Aw='Awk:BAAANQADCgMIBAAAAA==.',
['Aø']='Aøc:BAAANQAECgQICAAAAA==.',
Ba='Babara:BAAANQABCgQIBAAAAA==.Babyfart:BAAANQAECgEIAQAAAA==.Bakushiterra:BAAANQAECgEIAQAAAA==.Barao:BAAANQADCggIBQAAAA==.Barriguinha:BAAANQADCgIIBAAAAA==.Batmano:BAAANQADCgYICgAAAA==.',
Bh='Bherg:BAAANQADCgYICQAAAA==.',
Bi='Biskademon:BAAANQAECgEIAQAAAA==.Bizum:BAAANQADCgcIDAAAAA==.',
Bl='Blackee:BAAANQADCgMIBAAAAA==.Blackwatch:BAAANQADCgYICgAAAA==.Blitzkrig:BAAANQAECgcICwAAAA==.Bloodyclaw:BAAANQADCgYIBgAAAA==.',
Bo='Boomgoesyou:BAAANQAECgYICwAAAA==.Bourdriel:BAAANQADCggIFQAAAA==.',
Br='Bradoki:BAAANQAECgMIBgAAAA==.Brancalleone:BAAANQADCgcIDAAAAA==.Brazukmaiden:BAAANQADCggIDgAAAA==.Brisawave:BAAANQAECgUICQAAAA==.Brizagato:BAAANQAECgEIAQAAAA==.Broke:BAAANQADCgYIDQAAAA==.Brád:BAAANQAECgIIAgAAAA==.',
Bu='Bushido:BAAANQADCgYIEAAAAA==.Bustgril:BAAANQADCgYICQAAAA==.',
Bz='Bzbit:BAAANQADCgMIAgAAAA==.',
['Bé']='Béssi:BAAANQADCgMIAwAAAA==.',
Ca='Caiquebmq:BAAANQADCgYICgAAAA==.Calanguejo:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Caldrin:BAAANQADCgEIAQAAAA==.Calliphora:BAAANQADCgYICwAAAA==.Canard:BAAANQADCgUIBQAAAA==.Cannibal:BAAANQABCgQIAgAAAA==.Carloxamã:BAAANQAECgMIAwAAAA==.Cathiseev:BAAANQAECgEIAQAAAA==.Cathury:BAAANQAECgEIAwAAAA==.Catÿ:BAAANQAECgEIAQABNQAECgYIBAABAAAAAA==.Cavernozo:BAAANQADCgcIBwAAAA==.',
Ce='Cerino:BAAANQADCgQIBAAAAA==.',
Ch='Changjin:BAAANQADCgMIAwAAAA==.Chiclete:BAAANQAECgQIBAAAAA==.Chopz:BAAANQADCgMIAwAAAA==.Chrizantm:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Chucknòórris:BAAANQADCgYIDAAAAA==.',
Cl='Clairë:BAAANQADCgQIBAAAAA==.Claude:BAAANQADCgQIBQAAAA==.',
Co='Coionir:BAAANQADCggIEwAAAA==.Coiovoker:BAAANQADCgEIAQABNQADCggIEwABAAAAAA==.Comunistaa:BAAANQAECgIIAgAAAA==.Contadoruns:BAAANQADCgYIBgAAAA==.Corstine:BAAANQADCgcICgAAAA==.Corvynus:BAAANQADCgUIBgAAAA==.Cosmicgarou:BAAANQADCgMIAwAAAA==.',
Cr='Cronosxdm:BAAANQAECgEIAQAAAA==.Crucyatus:BAAANQAECgMIBAAAAA==.Cruelmoon:BAAANQADCgEIAQAAAA==.',
['Cå']='Cåssio:BAAANQAECgEIAQAAAA==.',
['Cÿ']='Cÿgnus:BAAANQADCgEIAQABNQAECgMIAwABAAAAAA==.',
Da='Danteholy:BAAANQADCgMIAwAAAA==.Darkhold:BAAANQAECgQIBQAAAA==.Darklendio:BAAANQADCgQIBAAAAA==.Daroncosp:BAAANQADCgIIAgAAAA==.Dashuman:BAAANQAECgQIBAAAAA==.Davicohunter:BAAANQADCgIIAgAAAA==.Dazhu:BAAANQADCggICAAAAA==.',
De='Deadusopp:BAAANQADCgQIBAAAAA==.Deathatrix:BAAANQADCgUIBQAAAA==.Defroque:BAAANQADCgYIBgAAAA==.Delarÿn:BAAANQADCgYIBgABNQADCgcIDAABAAAAAA==.Demoncrashe:BAAANQADCgEIAQAAAA==.Denevy:BAAANQAECgIIAgAAAA==.Deraelda:BAAANQADCgIIAgAAAA==.Destructiom:BAAANQAECgEIAQAAAA==.',
Dh='Dhamburguer:BAAANQAECgEIAQAAAA==.',
Di='Diggop:BAAANQADCgYIBgAAAA==.Dijank:BAAANQADCgIIAgABNQADCgUICQABAAAAAA==.Dima:BAAANQAECgIIAwAAAA==.',
Do='Dornaa:BAAANQADCgYICgAAAA==.Dosmagos:BAAANQABCgMIBQAAAA==.',
Dr='Dracarysz:BAAANQADCgUIBQAAAA==.Draculavmp:BAAANQADCgEIAQAAAA==.Drainetty:BAAANQADCgMIAwAAAA==.Dranacs:BAAANQADCgMIAwABNQADCgUIBQABAAAAAA==.Dreamremix:BAAANQAECgQIBAAAAA==.Dreyol:BAAANQADCgYICQAAAA==.Drts:BAAANQAECgQIBQAAAA==.',
Ed='Eduarthas:BAAANQADCgUIBwAAAA==.',
El='Elementys:BAAANQAECgEIAQAAAA==.Elfuryon:BAAANQADCgIIAgABNQAECgYICwABAAAAAA==.Elinaara:BAAANQAECgQIBAAAAA==.Elliith:BAAANQADCgIIAgAAAA==.Elricky:BAAANQADCgEIAQAAAA==.Eluna:BAAANQAECgEIAQAAAA==.Elwiñ:BAAANQADCgEIAQAAAA==.',
En='Encanis:BAAANQADCgYIAgAAAA==.',
Es='Escanorzão:BAAANQADCgcIBwABNQABCgQIBAABAAAAAA==.Escola:BAAANQAECgQICQAAAA==.',
Ex='Exo:BAAANQAECgMIAwAAAA==.Exorciseur:BAAANQAECgYICgAAAA==.',
Fa='Fabercästell:BAAANQADCgUIBQAAAA==.Fabers:BAAANQAECgMIAwAAAA==.',
Fe='Feanori:BAAANQAECgEIAQAAAA==.Feanør:BAAANQADCgYIBwAAAA==.Feinanduo:BAAANQADCgMIAwAAAA==.Felfury:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Feyrin:BAAANQADCggIEgAAAA==.',
Fi='Finngermy:BAAANQADCggICQAAAA==.',
Fl='Flodearthen:BAAANQADCgQIBAAAAA==.Flodfelblood:BAAANQADCgQIBgAAAA==.',
Ga='Gabela:BAAANQADCgIIAgAAAA==.Gaiataur:BAAANQADCgMIAwAAAA==.Galinni:BAAANQADCggICAAAAA==.Gallon:BAAANQADCggIEwAAAA==.',
Gl='Glacyale:BAAANQADCgMIAwAAAA==.',
Gn='Gnomepink:BAAANQADCgYIBgAAAA==.',
Go='Godadrian:BAAANQADCgQIBAAAAA==.Gosu:BAAANQADCggICAAAAA==.',
Gr='Gralfor:BAAANQADCgcICQAAAA==.Grekorio:BAAANQADCgUIBQAAAA==.Greylord:BAAANQAECgIIAgABNQAECgIIAwABAAAAAA==.Greylorddrak:BAAANQAECgIIAwAAAA==.Greylordp:BAAANQAECgEIAQABNQAECgIIAwABAAAAAA==.',
Gu='Gults:BAAANQADCgQIAgAAAA==.Gultsz:BAAANQADCgMIAwAAAA==.Gunpowter:BAAANQABCgEIAQAAAA==.Guxrock:BAAANQADCgIIAgAAAA==.',
Gy='Gyllenhaal:BAAANQADCgUIBQAAAA==.',
['Gä']='Gäspär:BAAANQADCgYIBgAAAA==.',
['Gø']='Gødmar:BAAANQAECgIIAgAAAA==.',
Ha='Hagnaredk:BAAANQADCgMIAwAAAA==.Haiume:BAAANQADCggIDQAAAA==.Hamiister:BAAANQADCgQIBAAAAA==.Hancalimon:BAAANQAECgMIAwAAAA==.Haokö:BAAANQADCgYIBgAAAA==.Hastterix:BAAANQADCgQIAgAAAA==.Hatezon:BAAANQAECgEIAgAAAA==.',
He='Heavyking:BAAANQADCgYICQAAAA==.Hellreaper:BAAANQAECgEIAQAAAA==.Heracranosx:BAAANQADCgYICgAAAA==.Herdy:BAAANQADCgEIAQAAAA==.Herta:BAAANQAECgMIBAAAAA==.Hess:BAAANQADCgYIDAAAAA==.',
Hi='Hireque:BAAANQADCggIDgAAAA==.Hitkins:BAAANQADCgUIBQAAAA==.',
Ho='Hofpriest:BAAANQADCgUIBQAAAA==.Hoiac:BAAANQAECgEIAQAAAA==.Holycel:BAAANQADCgUIBwABNQAECgYIBwABAAAAAA==.',
Hu='Hunterpica:BAAANQADCggIDgAAAA==.Huntmon:BAAANQAECgMIBAAAAA==.Huskat:BAAANQAECgQIBQAAAA==.',
Hy='Hysillens:BAAANQADCgYIBwAAAA==.',
Il='Ilane:BAAANQABCgQIBAAAAA==.Illidatrix:BAAANQAECgIIAgAAAA==.Ilovealtgirl:BAAANQADCgYIBgAAAA==.',
In='Inot:BAAANQADCggICgAAAA==.',
Is='Iscariotes:BAAANQABCgQIBAAAAA==.Ismael:BAAANQADCgcICAAAAA==.',
It='Itsälasca:BAAANQADCgUIBQAAAA==.',
Iu='Iuri:BAAANQADCgcIAQAAAA==.',
Iz='Izanna:BAAANQADCgUIBQAAAA==.',
Ja='Jampack:BAAANQAECgQICAAAAA==.',
Je='Jeevas:BAAANQAECgEIAQAAAA==.Jefté:BAAANQADCgEIAQAAAA==.Jeu:BAAANQADCgcICQAAAA==.',
Jh='Jhasperr:BAAANQADCgQIBAAAAA==.',
Jo='Jocabiroca:BAAANQAECgIIAgAAAA==.Jotavê:BAAANQADCgUICQAAAA==.',
Jp='Jpleuk:BAAANQADCggICgAAAA==.',
Jr='Jrxamã:BAAANQADCgYICgAAAA==.',
Ka='Kaaliel:BAAANQADCgQIBQAAAA==.Kagero:BAAANQADCgQIBAAAAA==.Kaju:BAAANQAECgYICAAAAA==.Kalinis:BAAANQADCgIIAgAAAA==.Kalliiope:BAAANQAECgMIAwAAAA==.Kamïlla:BAAANQADCgUIBAAAAA==.Karak:BAAANQADCgIIAgAAAA==.Kath:BAAANQADCgYIBgAAAA==.Kathana:BAAANQABCgMIAwAAAA==.',
Ke='Keior:BAAANQADCgcIBwAAAA==.Kenai:BAAANQADCggICAAAAA==.Kewenz:BAAANQAECgQIAQAAAA==.',
Kh='Khasin:BAAANQADCggIDgAAAA==.',
Ki='Kiregeth:BAAANQAECgIIAgAAAA==.Kitrel:BAAANQADCgYIBgAAAA==.',
Kl='Kllauzz:BAAANQADCgYICgABNQAECgEIAQABAAAAAA==.Kllauzzmage:BAAANQADCgUIBwABNQAECgEIAQABAAAAAA==.Kllauzzpalla:BAAANQAECgEIAQAAAA==.',
Kr='Krastian:BAAANQAECgEIAgAAAA==.Krupper:BAAANQAECgMIAwABNQAECgQIBQABAAAAAA==.Krynesa:BAAANQADCgIIAgAAAA==.',
Ku='Kuhaku:BAAANQADCgQIBAAAAA==.',
Ky='Kyary:BAAANQADCgUIBQABNQAECgMIBQABAAAAAA==.',
['Kä']='Kälini:BAAANQADCgcIDAAAAA==.',
['Kó']='Kónar:BAAANQADCgEIAQAAAA==.',
['Kö']='Köndmänö:BAAANQAECgEIAQAAAA==.Köri:BAAANQAECgUIBQAAAA==.',
La='Lakaioo:BAAANQADCggIFQAAAA==.Lamont:BAAANQAECgEIAQAAAA==.Lampiião:BAAANQAECgQIBQAAAA==.Lanllaniel:BAAANQAECgIIAgAAAA==.',
Le='Lebelisco:BAAANQAECgEIAQAAAA==.Leehyori:BAAANQADCgQIBAAAAA==.Lennorien:BAAANQAECgEIAQAAAA==.',
Lh='Lhyunl:BAAANQADCgIIAgAAAA==.',
Li='Liciox:BAAANQADCgIIAgAAAA==.Liftshertail:BAAANQAECgQIBAAAAA==.Linë:BAAANQADCgYIDAABNQADCgcIDAABAAAAAA==.Linëa:BAAANQADCgEIAQAAAA==.Linüss:BAAANQADCgQIBQAAAA==.Littleshelby:BAAANQADCgYIBgAAAA==.',
Lo='Longaim:BAAANQAECgEIAQAAAA==.Lorthaeron:BAAANQADCgYICQAAAA==.',
Lu='Lucasbr:BAAANQADCggIDgAAAA==.Lucasyeah:BAAANQAFFAEIAQAAAA==.Lukanelas:BAAANQADCgEIAQAAAA==.Lulyssa:BAAANQADCggICwAAAA==.Luna:BAAANQAECgIIAgABNQAECgQIBAABAAAAAA==.Lunes:BAAANQADCgYICgAAAA==.Lusther:BAAANQADCgQIBAAAAA==.Luzdacelesc:BAAANQAECggIDQAAAA==.',
Ly='Lyaah:BAAANQADCgYIBgAAAA==.',
['Ló']='Lólzhé:BAAANQADCgYIBgAAAA==.',
['Lø']='Lølzhê:BAAANQAECgQIBwAAAA==.Løvizinha:BAAANQAECgEIAQAAAA==.',
Ma='Madbuddha:BAAANQADCgQIBAAAAA==.Magodanilo:BAAANQADCgQIBAAAAA==.Magodavida:BAAANQADCggIEgAAAA==.Magodotruco:BAAANQADCgIIAgAAAA==.Maheena:BAAANQADCgYIBgAAAA==.Mai:BAAANQAECgEIAQAAAA==.Makksha:BAAANQADCgEIAQAAAA==.Makoto:BAAANQAECgEIAQAAAA==.Malborion:BAAANQADCggICgAAAA==.Malignõ:BAAANQAECgYICQAAAA==.Maltozo:BAAANQAECgIIBAAAAA==.Mandrakson:BAAANQADCggIDgAAAA==.Mandubim:BAAANQADCgEIAQAAAA==.Mariiamil:BAAANQADCgYICgAAAA==.Marvvila:BAAANQADCggIDgAAAA==.Marycristiny:BAAANQAECgEIAQAAAA==.Mazaky:BAAANQAECgEIAQAAAA==.',
Me='Megumi:BAAANQAECgEIAQAAAA==.Menorxidil:BAAANQAECgUIBgAAAA==.Merigold:BAAANQADCgYICwAAAA==.Metallicä:BAAANQADCgMIAwAAAA==.',
Mh='Mhenb:BAAANQADCgQIBAAAAA==.',
Mi='Mikal:BAAANQAECgEIAQAAAA==.Minör:BAAANQAECgEIAQAAAA==.Missmarvel:BAAANQABCgQIBgAAAA==.Mizukagesou:BAAANQADCggICAAAAA==.',
Mo='Monkbest:BAAANQADCgEIAQAAAA==.Montej:BAAANQADCgQIBAAAAA==.Mooncap:BAAANQADCgEIAQAAAA==.Moondragoon:BAAANQADCgIIAgAAAA==.Morakhir:BAAANQADCgQIBAAAAA==.Morganviolet:BAAANQADCgYICwAAAA==.',
Mu='Murdoky:BAAANQADCgEIAQABNQADCgIIAgABAAAAAA==.Musleira:BAAANQAECgEIAQAAAA==.',
My='Myrzin:BAAANQADCgYICgAAAA==.Mythcut:BAAANQADCgcICAAAAA==.Mythjegue:BAAANQADCgYIBgAAAA==.',
['Mä']='Mälthazar:BAAANQAECgEIAQAAAA==.Määt:BAAANQADCggICAABNQAECgcIDQABAAAAAA==.',
['Må']='Mågus:BAAANQADCggICgAAAA==.',
['Mø']='Mørgåna:BAAANQADCgMIAwAAAA==.',
Na='Naero:BAAANQADCgQIBAAAAA==.Naerylla:BAAANQADCgYICgAAAA==.Nagashina:BAAANQADCggIDgAAAA==.Naizow:BAAANQAECgEIAQAAAA==.Naomiy:BAAANQADCgYICwAAAA==.Naoto:BAAANQAECgMIAwAAAA==.Napru:BAAANQADCgEIAQAAAA==.Narjes:BAAANQADCgQIBQAAAA==.',
Ne='Necrogélido:BAAANQADCgYICgAAAA==.Neopaladino:BAAANQADCgIIAgAAAA==.Nerlock:BAAANQADCgYICQAAAA==.',
Ni='Nightforms:BAAANQADCggICAAAAA==.Nikity:BAAANQAECgEIAQAAAA==.',
No='Noazard:BAAANQADCgYIDAAAAA==.Nopainnogain:BAAANQADCgIIAgAAAA==.Nortênho:BAAANQAECgEIAQAAAA==.Nossilat:BAAANQAECgMIAwAAAA==.',
Nu='Nuit:BAAANQAECgEIAQAAAA==.Nunhöly:BAAANQADCgcIDQAAAA==.',
Ny='Nysthiael:BAAANQAECgEIAQAAAA==.Nyxicel:BAAANQADCgYIBgABNQAECgYIBwABAAAAAA==.',
['Ný']='Nýmm:BAAANQADCgUIBQAAAA==.',
Oc='Ocon:BAAANQABCgIIAgAAAA==.',
Od='Odio:BAAANQADCgEIAQAAAA==.',
Ok='Okrigg:BAAANQADCgQIBwAAAA==.',
On='Onlydruix:BAAANQADCgIIAgAAAA==.',
Op='Opsdesculpa:BAAANQAECgIIAgAAAA==.',
Or='Organ:BAAANQAECgMIBAAAAA==.Orinoldo:BAAANQAECgYICAAAAA==.',
Ot='Otherside:BAAANQADCgYIDAABNQAECgYICgABAAAAAA==.Otávio:BAAANQADCgQIBAAAAA==.',
Ox='Oxentedragon:BAAANQADCgMIAwAAAA==.',
Pa='Palluz:BAAANQADCgYIBgABNQAECgYIBwABAAAAAA==.Panicdeath:BAAANQADCgMIAwAAAA==.Parafinaisis:BAAANQADCgQIBgAAAA==.Pauladinho:BAAANQADCgIIAgAAAA==.',
Pe='Peltrow:BAAANQAECgcIBwAAAA==.Perciwal:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.Pesaa:BAAANQAECgIIAgAAAA==.',
Ph='Phanttoz:BAAANQADCgIIAgAAAA==.Philii:BAAANQADCggIDQAAAA==.',
Pi='Pirizin:BAAANQAECgQIBwAAAA==.',
Po='Porcaleta:BAAANQADCgcICwAAAA==.Portal:BAAANQADCggICgAAAA==.Portelamage:BAAANQAECgQICAAAAA==.Portheus:BAAANQADCggIDwAAAA==.',
Pr='Praeglacius:BAAANQAECgMIAwAAAA==.Priapista:BAAANQADCgUIBQAAAA==.Priyla:BAAANQABCgIIAQAAAA==.',
Ps='Psicopanda:BAAANQADCgUICgAAAA==.',
Pw='Pwcca:BAAANQADCgYIBwAAAA==.',
Qu='Queirozm:BAAANQADCgYIBgAAAA==.',
Ra='Radork:BAAANQADCggICwAAAA==.Raewyn:BAAANQAECgYIBwAAAA==.Rafaelgame:BAAANQAECgEIAQAAAA==.Ragdead:BAAANQAECgUIBwAAAA==.Ragnaryos:BAAANQAECgEIAQABNQAECgUIBwABAAAAAA==.Rairone:BAAANQAECgMIAwAAAA==.Rapunxel:BAAANQAECgYICgAAAA==.Rarkion:BAAANQAECgIIAgAAAA==.',
Rb='Rbchama:BAAANQAECgMIBAAAAA==.',
Re='Redvil:BAAANQADCgUIBQAAAA==.Revoltedhunt:BAAANQADCggIEAABNQAFFAIIAgABAAAAAA==.Revolthed:BAAANQAFFAIIAgAAAA==.',
Rh='Rhaadora:BAAANQADCgEIAQABNQADCggIDgABAAAAAA==.Rhoghar:BAAANQADCggICAAAAA==.',
Ro='Rokalf:BAAANQAECgQIBAAAAA==.Rossiten:BAAANQADCgcICwAAAA==.Roöf:BAAANQAECgQIBAAAAA==.',
['Rä']='Räidela:BAAANQAECgEIAQAAAA==.',
Sa='Sagman:BAAANQABCgIIAgAAAA==.Salasär:BAAANQADCgcIDAABNQAECgEIAQABAAAAAA==.Saleyi:BAAANQADCgcICwAAAA==.Saluton:BAAANQADCgYIBQAAAA==.Samidemon:BAAANQADCgYIBgAAAA==.Sarashi:BAAANQADCgUICQAAAA==.Sarzlok:BAAANQADCgcICQAAAA==.',
Sc='Scoobydruida:BAAANQAECgEIAQAAAA==.Screan:BAAANQAECgUIBQAAAA==.Scrøøge:BAAANQADCgEIAQAAAA==.',
Se='Seelyvorey:BAAANQADCggIDwAAAA==.Selph:BAAANQADCgQIBQABNQADCgcIBwABAAAAAA==.Serrase:BAAANQAECgIIAgAAAA==.',
Sh='Shalquoir:BAAANQADCgUIBQABNQAECgQIBAABAAAAAA==.Sharckaron:BAAANQADCggIDwAAAA==.Shedleass:BAAANQADCggIDgAAAA==.Shendalar:BAAANQAECgMIAwAAAA==.Shigami:BAAANQADCgcIBwAAAA==.Shywa:BAAANQADCgIIAgAAAA==.Shîvas:BAAANQADCgEIAQAAAA==.Shøtinha:BAAANQAECgEIAQAAAA==.Shøwtime:BAAANQADCgQIBAAAAA==.',
Si='Sicarious:BAAANQADCgYICwAAAA==.Sicariuz:BAAANQADCgYIBgAAAA==.',
Sk='Skybourne:BAAANQADCgMIAwAAAA==.',
Sn='Snowtail:BAAANQAECgEIAQAAAA==.',
So='Sodragon:BAAANQADCgQIBAAAAA==.Solaryel:BAAANQADCggIDQAAAA==.Solidheals:BAAANQAECgIIAgAAAA==.Sougigante:BAAANQADCgYIDAAAAA==.Soupombagira:BAAANQADCggIDQAAAA==.',
Sp='Spellshadown:BAAANQAECgMIBAAAAA==.Spratch:BAAANQADCgQIBAAAAA==.',
Sr='Srburns:BAAANQADCgEIAQAAAA==.',
St='Stormimrage:BAAANQADCgUIBgAAAA==.Strexx:BAAANQADCgYICQAAAA==.Stronoffgard:BAAANQADCgYIBgAAAA==.Stronq:BAAANQADCgYIBgAAAA==.',
Su='Sulfur:BAAANQAECgIIAgAAAA==.',
Sy='Syberdal:BAAANQADCggIDgAAAA==.',
['Sà']='Sàgadegemeos:BAAANQAECgQIBAAAAA==.',
['Sï']='Sïlent:BAAANQADCgMIAwAAAA==.',
Ta='Tacka:BAAANQADCgYICwAAAA==.Tafoki:BAAANQAECgEIAQAAAA==.Tankairotty:BAAANQAECgEIAQAAAA==.Tassali:BAAANQADCgQIBgAAAA==.',
Td='Tdarklord:BAAANQADCgMIAwAAAA==.',
Te='Temkutemmedo:BAAANQAECgIIAwABNQABCgQIBAABAAAAAA==.Tennkkar:BAAANQADCgQIAwAAAA==.Texugojogatv:BAAANQAECgEIAQAAAA==.Texugosa:BAAANQAECgEIAQAAAA==.',
Th='Thamihime:BAAANQAECgIIAgAAAA==.Tharizdum:BAAANQAECgEIAQAAAA==.Thornus:BAAANQAECgcICwAAAA==.Thorudos:BAAANQADCgQIAgAAAA==.Thulin:BAAANQADCgMIAwAAAA==.',
To='Toni:BAAANQADCgUICQAAAA==.Toven:BAAANQADCgQIBAABNQADCgUICQABAAAAAA==.',
Tp='Tprdmage:BAAANQADCggICAAAAA==.',
Tr='Trolhöl:BAAANQAECgEIAQAAAA==.Troyana:BAAANQADCggICAABNQAECgcIDQABAAAAAA==.',
Tu='Tukiel:BAAANQAECgEIAgAAAA==.',
Ty='Tyde:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Typol:BAAANQADCgYIEQAAAA==.',
['Tó']='Tóten:BAAANQADCgUIBQAAAA==.',
['Tö']='Törtz:BAAANQADCggIFQAAAA==.',
Ug='Ugabugah:BAAANQADCgIIAgAAAA==.',
Ul='Ulish:BAAANQAECgEIAQAAAA==.',
Um='Umburana:BAAANQADCgMIAwABNQADCgUICQABAAAAAA==.Umehara:BAAANQAECgYICQAAAA==.Umokh:BAAANQAECgMIBQAAAA==.',
Uo='Uolokoelfo:BAAANQAECgcIDAAAAA==.',
Ur='Urannia:BAAANQAECgYICgAAAA==.Urgath:BAAANQADCggIDQAAAA==.',
Va='Valan:BAAANQADCgYIBwAAAA==.Valdevino:BAAANQAECgEIAQAAAA==.Valk:BAAANQADCgIIAgAAAA==.Varyssa:BAAANQADCggIDgAAAA==.Vazgoroth:BAAANQADCgYICgAAAA==.',
Ve='Venator:BAAANQAECgEIAQAAAA==.',
Vi='Viciadø:BAAANQADCgYIBQABNQAECgYIAgABAAAAAA==.Villalobos:BAAANQAECgEIAQAAAA==.Vits:BAAANQAECgEIAgAAAA==.',
Vo='Voidsurge:BAAANQADCgYIBgAAAA==.Voidwar:BAAANQADCgQIBAABNQADCgYIBgABAAAAAA==.Volrun:BAAANQADCggICQAAAA==.Voragem:BAAANQAECgEIAQAAAA==.',
Vu='Vulkova:BAAANQADCgQIBQAAAA==.',
Wa='Warlôka:BAAANQADCgUIBQAAAA==.',
Wi='Wiillord:BAAANQADCgUIBQAAAA==.Willbm:BAAANQAECgEIAgAAAA==.Winnettou:BAAANQADCgQIBgAAAA==.Wise:BAAANQAECgMIBAAAAA==.',
Wm='Wmana:BAAANQAECgIIAgAAAA==.',
Wu='Wuan:BAAANQAECgQIBAAAAA==.',
Xa='Xamanico:BAAANQADCgQIBAAAAA==.Xanasmanas:BAAANQAECgMIBAAAAA==.',
Xh='Xharlios:BAAANQADCggIDwAAAA==.',
Xu='Xusp:BAAANQADCggIDgAAAA==.',
Xx='Xxbizu:BAAANQADCggICAAAAA==.',
Xy='Xymor:BAAANQAECgcIDQABNQAECgQIBAABAAAAAA==.',
Ya='Yagaami:BAAANQADCgQIBAAAAA==.Yant:BAAANQADCgYIBgAAAA==.',
Yl='Ylanna:BAAANQAECgEIAQAAAA==.',
Yo='Yonnyson:BAAANQADCgEIAQAAAA==.Yoriko:BAAANQAECgQIBAAAAA==.Yorú:BAAANQADCggIDwAAAA==.',
Yu='Yulaw:BAAANQADCgQIBAAAAA==.',
['Yá']='Yásuo:BAAANQADCgcIEwAAAA==.',
Zh='Zhalazar:BAAANQADCgYIBgAAAA==.',
Zi='Zigosmar:BAAANQABCgIIAgAAAA==.',
Zo='Zolet:BAAANQADCgIIAgAAAA==.Zones:BAAANQADCgIIAgABNQADCggIFQABAAAAAA==.',
['Äl']='Älexandër:BAAANQADCgYIBgAAAA==.',
['Ær']='Ærikão:BAAANQAECgEIAQAAAA==.',
['Æt']='Ætherfel:BAAANQADCggIDgAAAA==.',
['Ét']='Étel:BAAANQADCgQIBAAAAA==.',
['Ör']='Örigem:BAAANQADCgIIAgAAAA==.',
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
