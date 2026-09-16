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

local lookup = {'Unknown-Unknown','Paladin-Protection','DemonHunter-Devourer','Druid-Restoration','Hunter-Marksmanship','Hunter-BeastMastery','Shaman-Restoration','DemonHunter-Havoc','DeathKnight-Unholy',}
local provider = {region='US',realm='ScarletCrusade',name='US',type='weekly',zone=53,date='2026-09-15',data={Ac='Acefu:BAAANQAECgIIAgAAAA==.Acornella:BAAANQAECgcIDQAAAA==.Acornkei:BAAANQAECgcICQABNQAECgcIDQABAAAAAA==.',
Ad='Adonsia:BAAANQADCgQIBAAAAA==.Adreva:BAAANQAECgIIBAAAAA==.',
Ae='Aelana:BAAANQADCgQIBAAAAA==.Aendor:BAAANQADCgcIBwABNQAECggIGQACALYbAA==.',
Ai='Ailanthus:BAAANQAECgIIAgAAAA==.',
Al='Albinophil:BAAANQADCgIIAgABNQAECgQIBgABAAAAAA==.Alloisaber:BAAANQABCgEIAQAAAA==.Alunne:BAAANQADCgQIBAAAAA==.',
Am='Amna:BAAANQADCgcICwAAAA==.',
An='Andrelsia:BAAANQADCgIIBAAAAA==.Andrilla:BAAANQADCgYIDAAAAA==.Ankeseth:BAAANQADCgUIBQAAAA==.',
Ar='Aracelis:BAAANQADCggICAAAAA==.Araxiel:BAAANQADCggICQAAAA==.Archangël:BAAANQAECgEIAQAAAA==.Arkenos:BAAANQADCgYICwAAAA==.Arén:BAAANQAECgMIBgAAAA==.',
As='Ashenshugär:BAAANQADCgMIBgAAAA==.Aszian:BAAANQABCgcICgAAAA==.Aszun:BAAANQAECgQIBgAAAA==.',
At='Atractiva:BAAANQAECgUICgAAAA==.',
Az='Azmar:BAAANQADCgIIAgAAAA==.Azuri:BAAANQADCgUICgABNQADCgcICwABAAAAAA==.',
Ba='Balain:BAAANQAECgQIBgAAAA==.',
Be='Bear:BAAANQADCggIFwAAAA==.Bearzerk:BAAANQAECgMIBQAAAA==.Benathar:BAAANQAECgIIBAAAAA==.',
Bl='Blaston:BAAANQADCgYIBgAAAA==.Blightbeard:BAAANQADCggIDgAAAA==.Bloodthorn:BAAANQAECgEIAgAAAA==.',
Bo='Boomnescient:BAAANQADCgYICwAAAA==.Bottomdps:BAAANQAECgQIBgABNQAECggIFwADAKIVAA==.',
Br='Bransonian:BAAANQADCgIIAwAAAA==.Brantu:BAAANQAECgQIBgAAAA==.Braultus:BAAANQAECgUICQAAAA==.Bravehearth:BAAANQADCgEIAQAAAA==.Breuddwydwr:BAAANQADCgEIAQAAAA==.',
Ca='Caanu:BAAANQAECgMIAwABNQAECggIGQACALYbAA==.Calydonia:BAAANQAECgEIAQAAAA==.',
Ce='Celdiseth:BAAANQADCgMIAwAAAA==.Cerdwin:BAAANQAECgUIBQABNQAECgUICgABAAAAAA==.',
Ch='Charferad:BAAANQADCgYIDAAAAA==.Chatter:BAAANQADCgcICAAAAA==.Cheeseydeath:BAAANQADCgYIFAAAAA==.Chibeard:BAAANQAECgIIBAAAAA==.',
Cl='Clevercrane:BAAANQAECgMIAgABNQAECgUIBgABAAAAAA==.',
Co='Coolbro:BAAANQADCgcIBwAAAA==.Corialis:BAAANQAECgMIBQAAAA==.',
Cr='Crom:BAAANQAECgQICQAAAA==.Crying:BAAANQAECgEIAQAAAA==.',
Cy='Cyn:BAAANQADCgQIBAAAAA==.',
Da='Dandarred:BAAANQAECgIIBAAAAA==.Dawne:BAAANQAECgYICwAAAA==.Dazanna:BAAANQAECgMIBQAAAA==.Dazre:BAAANQAECgIIAgAAAA==.',
De='Demeisen:BAAANQAECgQICAAAAA==.',
Di='Diksensei:BAAANQADCgYIEwAAAA==.Diod:BAAANQAECgIIAgAAAA==.',
Dr='Dracotincan:BAAANQADCgIIAgAAAA==.Draegis:BAAANQABCgIIAgAAAA==.Dragyns:BAAANQAECgcIEgAAAA==.Dragynslance:BAAANQADCggIDAABNQAECgcIEgABAAAAAA==.Drayper:BAAANQAECgIIBAAAAA==.',
Du='Dunbarke:BAAANQAECgIIAwAAAA==.',
['Dê']='Dêadlights:BAAANQAECgQIBgAAAA==.',
El='Elendrisa:BAAANQAECgQIBQAAAA==.Elliwynd:BAAANQAECgMIAwAAAA==.Elway:BAAANQADCgIIAgAAAA==.',
Er='Eraela:BAAANQADCggICAAAAA==.Erinnys:BAAANQAECgIIBAAAAA==.',
Es='Esoteria:BAAANQAECgQICQAAAA==.',
Eu='Eufemia:BAAANQADCgIIBAAAAA==.',
Ev='Evonnya:BAAANQADCggIDgAAAA==.',
Fe='Felfar:BAAANQADCgQIBAAAAA==.',
Fi='Finalomega:BAAANQADCgcIEQAAAA==.Finnshot:BAAANQAECgIIAgAAAA==.Finrod:BAAANQADCgQIBwAAAA==.',
Fl='Flaminfalcon:BAAANQAECgEIAgABNQAECgUIBgABAAAAAA==.',
Fo='Foulmilk:BAAANQADCgEIAQAAAA==.Foxflame:BAAANQAECgUICgAAAA==.',
Fr='Franzen:BAAANQADCgQIBQAAAA==.Frawd:BAAANQADCgcIBwABNQAECgcIEgABAAAAAA==.Freyalys:BAAANQADCgQIBAAAAA==.Frôstblade:BAAANQABCgYIBgAAAA==.',
Fu='Fulanita:BAAANQADCgcIEwAAAA==.Furyaid:BAAANQAECgQIBgAAAA==.',
Ge='Genkithered:BAAANQAECgIIBAAAAA==.',
Gl='Gloomy:BAAANQADCgEIAQAAAA==.',
Go='Gourak:BAAANQAECgIIAgAAAA==.',
Gr='Gravemarks:BAAANQADCgYIBAAAAA==.Grimhorn:BAAANQADCgcIGAAAAA==.Grimlie:BAAANQADCgYIDAABNQAECgQIBgABAAAAAA==.',
Gu='Guaritrice:BAAANQADCgcIDAAAAA==.',
Gw='Gwindor:BAAANQADCgIIBAAAAA==.',
['Gö']='Gödwyn:BAAANQADCggIGwABNQAECgIIBQABAAAAAA==.',
Ha='Hairyrage:BAAANQABCgQICAAAAA==.Hale:BAAANQADCgEIAgAAAA==.',
He='Healzey:BAAANQADCgUIBAAAAA==.Hetairoi:BAAANQAECgQIBgAAAA==.',
Hi='Hillbroken:BAAANQAECgQICgAAAA==.',
Hu='Huan:BAAANQAECgEIAQAAAA==.Huntrix:BAAANQADCgYICgAAAA==.',
['Hà']='Hànks:BAAANQADCggIEQAAAA==.',
Ib='Ibíng:BAAANQAECgEIAgAAAA==.',
In='Invariance:BAEANQADCgUIBQABNQAECgQIBAABAAAAAA==.Inèvitable:BAAANQAECgQICQAAAA==.',
Ir='Ironphant:BAAANQADCggIEgAAAA==.',
Is='Ishmethit:BAAANQADCgYIBgAAAA==.Istara:BAAANQADCgQIBQAAAA==.',
Je='Jebib:BAAANQAECgYIBgABNQAFFAYIDgAEAAAcAA==.Jeod:BAAANQADCgIIBAAAAA==.',
Ji='Jirachi:BAAANQADCgEIAQAAAA==.',
Jo='Jolty:BAAANQAECgcIEwAAAA==.',
Ju='Junghoulson:BAAANQAECgUIBQAAAA==.',
['Jð']='Jð:BAAANQAECgcICQAAAA==.',
Ka='Kaiou:BAAANQADCgMIAwAAAA==.Kantor:BAAANQAECgUICwAAAA==.Kasenko:BAAANQADCggICAABNQABCgQIBAABAAAAAA==.',
Ke='Kelmair:BAAANQADCgYIBgAAAA==.Keta:BAAANQABCgQIBAAAAA==.Ketameanie:BAAANQAECgMIBAAAAA==.',
Kh='Khadguy:BAAANQAECgUICAAAAA==.',
Km='Kmazing:BAAANQADCgcIEQABNQAECgQICQABAAAAAA==.',
Kn='Knikku:BAAANQADCggICAAAAA==.',
Ko='Konoha:BAAANQAECgMIBQAAAA==.Koven:BAAANQADCgcIDgAAAA==.',
Ku='Kultag:BAAANQAECgMIBQAAAA==.Kuun:BAAANQADCggIEQAAAA==.',
Ky='Kyaw:BAAANQAECgQIBwAAAA==.Kynzo:BAAANQAECgQICAAAAA==.',
La='Laelah:BAAANQABCgEIAQAAAA==.Lasmína:BAAANQADCgQIBQAAAA==.Laykeezenith:BAABNQAECoEcAAMFAAkJmiALDADKAgAFAAkJzhwLDADKAgAGAAYJyxcGVgCiAQAAAA==.Lazuli:BAAANQAECgYIDgAAAA==.',
Le='Lehann:BAAANQAECgEIAQAAAA==.',
Lo='Lothryn:BAAANQADCgYIDQAAAA==.',
Lp='Lp:BAAANQAECgEIAwAAAA==.',
Ma='Marenus:BAAANQAECgUICwAAAA==.Marten:BAAANQABCgIIAgAAAA==.Masume:BAAANQADCggIGgAAAA==.Maély:BAAANQADCgUIBQAAAA==.',
Me='Megaopto:BAAANQAECgIIAgAAAA==.Meowmix:BAAANQADCgMIAwAAAA==.Methanny:BAAANQABCgMIAQAAAA==.',
Mi='Mizmonk:BAAANQADCggICAAAAA==.',
Mj='Mjölnir:BAAANQAECgIIBQAAAA==.',
Mo='Momentum:BAAANQAECgEIAQAAAA==.',
Ms='Msdiiva:BAAANQAECgEIAQAAAA==.',
Na='Nahion:BAAANQADCgIIBAAAAA==.Nashira:BAAANQADCggIEwAAAA==.',
Ne='Nemasus:BAAANQAECgIIBQAAAA==.',
Ni='Ninjahh:BAAANQAECgQICAAAAA==.Nioshei:BAAANQAECgQIBgAAAA==.',
No='Nochmuerta:BAAANQADCgUIBQABNQADCgcIBwABAAAAAA==.Nogrid:BAAANQAECgUICwAAAA==.Noxstantine:BAAANQADCgQIBAAAAA==.',
Nu='Nuthar:BAAANQAECgMIAwAAAA==.',
Ny='Nyrrhi:BAAANQAECgcICgAAAA==.',
Ol='Oldeis:BAAANQADCgYIBgAAAA==.',
Or='Orneryosprey:BAAANQAECgMIAwABNQAECgQIBgABAAAAAA==.',
Ou='Ouroborös:BAAANQAECgMIBAAAAA==.',
Oy='Oyashiro:BAAANQADCggICwAAAA==.',
Pa='Pamburu:BAAANQAECgUIBwAAAA==.Papagrape:BAAANQAECgQIBgAAAA==.Paradiselost:BAAANQADCgQIBQAAAA==.Parzivàl:BAAANQADCgYIBgAAAA==.Paxa:BAAANQAECgMIBAAAAA==.',
Pe='Pennelo:BAAANQADCgQIBAAAAA==.Persayis:BAAANQADCgYIDAAAAA==.',
Pi='Pineappledk:BAEANQADCggIEgAAAA==.Pineapplle:BAEANQADCggICAABNQADCggIEgABAAAAAA==.',
Pl='Plazelly:BAAANQADCgUIBQAAAA==.',
Po='Podnov:BAAANQAECgcIEgAAAA==.Pollyanna:BAAANQABCgYICAAAAA==.',
Py='Pyrista:BAAANQAECggIAgAAAA==.',
Qa='Qang:BAAANQADCgYIDAAAAA==.',
Ra='Radiante:BAAANQAECgUIDAAAAA==.Rageadin:BAAANQABCgcIBQAAAA==.Raion:BAAANQAECgMIBQAAAA==.Raithis:BAAANQAFFAEIAQAAAA==.Ralzin:BAAANQADCgEIAQAAAA==.Ramhadin:BAEANQADCgMIBQABNQAECgIIAgABAAAAAA==.Raucousrhea:BAAANQABCgIIAgAAAA==.Rav:BAAANQAECgQIBQAAAA==.',
Re='Redvelvet:BAAANQADCggIFgAAAA==.Reznal:BAAANQAECgYIDQAAAA==.',
Ro='Romam:BAAANQADCgIIBAAAAA==.',
Ry='Rydran:BAAANQADCgIIAgAAAA==.Rykria:BAAANQADCgQIBQAAAA==.',
Sa='Sableanne:BAABNQAECoEXAAIHAAcJYwXUXQA2AQAHAAcJYwXUXQA2AQAAAA==.Saedirine:BAAANQADCgYIDAAAAA==.Saggi:BAAANQAECgEIAgAAAA==.',
Se='Secksiecutie:BAAANQAECgMIBQAAAA==.Secondwall:BAAANQADCgYIBgAAAA==.Selma:BAAANQABCgMIAwAAAA==.Serinar:BAAANQAECgUICQAAAA==.',
Sh='Shadowbolt:BAAANQABCgQIBgAAAA==.',
Si='Siako:BAAANQAECgIIAgAAAA==.Silversaiyan:BAAANQAECgYICgAAAA==.Sirlink:BAAANQABCgIIAgAAAA==.',
Sl='Slade:BAAANQAECgUICgAAAA==.Sliyce:BAAANQADCgEIAQAAAA==.',
Sn='Sneakyclubs:BAAANQADCgMIBgAAAA==.Snowfawn:BAAANQADCgcIDwABNQAECgQIAgABAAAAAA==.',
So='Sofedan:BAAANQAECgUICwAAAA==.Sorgath:BAAANQADCgUIBQAAAA==.Soriel:BAAANQAECgQIBgAAAA==.Sorokwa:BAAANQADCggIEAAAAA==.',
Sq='Squeeze:BAAANQAECgUIBwAAAA==.',
St='Stillwater:BAAANQAECgMIBQAAAA==.',
Sw='Swagidan:BAABNQAECoEaAAIIAAgJ3RnjEQBvAgAIAAgJ3RnjEQBvAgAAAA==.Sweaterpally:BAAANQADCgUICQAAAA==.Swiftera:BAAANQAECgIIAgAAAA==.',
Sy='Sylphrène:BAAANQAECgUIBgAAAA==.',
Ta='Taleth:BAAANQADCgcICwAAAA==.Tandrana:BAAANQADCgEIAQAAAA==.Targdh:BAABNQAECoEXAAIDAAgJohWZFQBLAgADAAgJohWZFQBLAgAAAA==.Targforeva:BAAANQADCgcICQABNQAECggIFwADAKIVAA==.',
Te='Terminus:BAAANQADCgMIAwAAAA==.',
Ti='Ticebane:BAAANQAECgYIEAAAAA==.Tichus:BAAANQADCgYIDgAAAA==.Tiduspullo:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.Titanbeard:BAAANQADCggIDgAAAA==.Titor:BAAANQAECgIIAwAAAA==.Tituspullo:BAAANQADCggIDwABNQAECgEIAQABAAAAAA==.',
To='Tolduan:BAAANQADCggIFQAAAA==.Toughturkey:BAAANQADCgEIAQABNQAECgQIBgABAAAAAA==.',
Tr='Tricarnetry:BAAANQAECgUIBgAAAA==.Tricarnity:BAAANQADCgYIBwABNQAECgUIBgABAAAAAA==.Trucknôrris:BAAANQADCgIIAgAAAA==.Trîela:BAAANQAECgMIBQAAAA==.',
Ul='Ulfer:BAAANQADCgYIBgABNQAECgYIEQAJAO0fAA==.',
Ve='Verakis:BAAANQAECgQIBgAAAA==.Verndarí:BAAANQAECgUICQAAAA==.Verudora:BAAANQAECgEIAQAAAA==.',
Vo='Vortheus:BAAANQADCggICwAAAA==.Votollis:BAAANQAECgEIAQAAAA==.',
Vr='Vrack:BAAANQADCgQIBAAAAA==.',
Wa='Warhowl:BAAANQABCggICwAAAA==.Warlanen:BAAANQADCgIIBAAAAA==.',
Wi='Willbur:BAAANQAECgUICwAAAA==.',
Wu='Wurthwhile:BAAANQADCgcIEQAAAA==.',
Wy='Wyndywalker:BAAANQAECgIIBAAAAA==.',
Za='Zamønk:BAAANQAECgQIBAAAAA==.',
Ze='Zeigfeld:BAAANQADCgYIDAAAAA==.',
Zi='Ziarra:BAAANQADCgUIBQAAAA==.',
Zo='Zok:BAAANQAECgIIBAAAAA==.',
Zy='Zyzz:BAAANQADCgQIBAAAAA==.',
['Zä']='Zädä:BAAANQADCgQIBQAAAA==.',
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
