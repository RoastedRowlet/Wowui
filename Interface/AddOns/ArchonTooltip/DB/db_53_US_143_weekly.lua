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

local lookup = {'Unknown-Unknown','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Holy','DemonHunter-Devourer','DemonHunter-Havoc','Druid-Balance','Warrior-Fury','Warrior-Arms',}
local provider = {region='US',realm='Lightninghoof',name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Abukuma:BAAANQADCggIDQAAAA==.',
Ad='Adrewid:BAAANQADCgEIAQABNQAECgcIDwABAAAAAA==.',
Ae='Aenstalash:BAAANQAECgEIAQAAAA==.Aephium:BAAANQADCgQIBAAAAA==.Aeson:BAAANQAECgIIAgAAAA==.',
Al='Alistur:BAAANQAECgEIAQAAAA==.',
Am='Ameena:BAAANQAECgEIAQAAAA==.Amuraby:BAAANQADCgEIAQAAAA==.',
An='Angus:BAAANQADCgYIDAAAAA==.',
Ar='Arthrasz:BAAANQAECgIIAgAAAA==.Arthraz:BAAANQAECgIIAgAAAA==.',
As='Astara:BAAANQAECgYICQAAAA==.Astrex:BAAANQAECgIIAgAAAA==.',
Au='Aurali:BAAANQADCgYIBgAAAA==.Aureliá:BAAANQAECgEIAQAAAA==.',
['Aü']='Aütobot:BAAANQAECgIIAgAAAA==.',
Ba='Babayaga:BAAANQADCgUIBQAAAA==.Badgirl:BAAANQADCgQIBAAAAA==.Balnar:BAAANQADCgIIAgABNQAECgQIBQABAAAAAA==.',
Bl='Bloodlustplz:BAAANQAECgQIBAAAAA==.',
Bo='Bobster:BAAANQAECgIIAgAAAA==.Bonepaw:BAAANQADCgUICAABNQADCgYICgABAAAAAA==.Booyea:BAAANQAECgMIAwAAAA==.',
Br='Brewwnor:BAAANQAECgEIAQAAAA==.',
Bu='Bubblenoodle:BAAANQADCgQIBAAAAA==.',
Ca='Calaestra:BAAANQAECgIIAgAAAA==.Calamuelis:BAABNQAECoEaAAMCAAkJLiTkAgBzAwACAAgJNSbkAgBzAwADAAIJHBq7LgCNAAAAAA==.Caliope:BAAANQADCgcIEAAAAA==.Cathbad:BAAANQADCggICgAAAA==.Cazlek:BAAANQADCggIFAAAAA==.',
Ce='Celery:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Cerelus:BAAANQAECgEIAQAAAA==.',
Ch='Chaac:BAAANQAECgQIBAAAAA==.Cheesûs:BAAANQAECgIIAgAAAA==.',
['Cã']='Cãrloy:BAAANQAECgYICQAAAA==.',
Da='Daedalas:BAAANQAECgEIAQAAAA==.Darkxsoul:BAAANQAECgQIBQAAAA==.Darthgrogu:BAAANQADCgUIBQABNQAECgcIDgABAAAAAA==.Darthknull:BAAANQAECgcIDgAAAA==.Darthputska:BAAANQADCgcIBwABNQAECgcIDgABAAAAAA==.Darthreven:BAAANQADCgQIBAABNQAECgcIDgABAAAAAA==.Darthtalon:BAAANQAECgEIAQABNQAECgcIDgABAAAAAA==.',
De='Deathwood:BAAANQADCgUICQAAAA==.Deitrichx:BAAANQADCgUIBQAAAA==.',
Do='Donkform:BAAANQAECgIIAgAAAA==.',
Dr='Draconith:BAAANQAECgUICwAAAA==.',
Du='Dunsparrow:BAAANQAECgcIDQAAAA==.Durzul:BAAANQADCgcIBwAAAA==.',
Ei='Eindraken:BAAANQAECgMIAwAAAA==.Eisis:BAAANQAECgEIAQAAAA==.',
Em='Empoleonn:BAAANQADCgcIBwAAAA==.',
En='Engos:BAAANQADCgYIBgAAAA==.',
Er='Erroz:BAAANQADCggIDwAAAA==.',
Ex='Exemplar:BAAANQADCgEIAQAAAA==.',
Fe='Fearwatermac:BAAANQAECgIIAgAAAA==.Feider:BAAANQABCgQIBwAAAA==.Felais:BAAANQAECgYICQAAAA==.Felin:BAAANQABCgYICgAAAA==.Femmefatale:BAAANQAECgUICAAAAA==.',
Fl='Flamecube:BAAANQADCgMIAwAAAA==.Flashx:BAAANQADCgcIDQAAAA==.Flass:BAAANQADCgYIBgAAAA==.',
Fr='Freerin:BAAANQABCgQIBAAAAA==.Frevpl:BAAANQADCggICAAAAA==.Frofrohunter:BAAANQAECgIIAwAAAA==.Froggie:BAAANQADCgYICgAAAA==.',
Fu='Fuzywuuzy:BAAANQADCggIEQAAAA==.',
Ga='Gazdorn:BAAANQAECgIIAgAAAA==.',
Gd='Gddmnbigcrit:BAAANQAECgMIAwAAAA==.',
Ge='Genghis:BAAANQADCgQIBAAAAA==.',
Gh='Ghost:BAAANQAECgQIBAAAAA==.',
Gi='Gigof:BAAANQADCgUIBQAAAA==.Gil:BAAANQADCgcIDwAAAA==.',
Gl='Glissa:BAAANQAECgMIBAAAAA==.',
Gt='Gt:BAAANQAECgQICAAAAA==.',
Ha='Habanero:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.Hadory:BAAANQAECgEIAQAAAA==.',
He='Hellzzdemon:BAAANQADCggIEwAAAA==.Herrvoller:BAAANQADCgEIAQAAAA==.Hexinverter:BAAANQADCgcICgAAAA==.',
Ho='Holycannoli:BAAANQADCgcIEgAAAA==.Horiffic:BAAANQAECgMIAwAAAA==.Hotfuzz:BAAANQAECgIIBQAAAA==.Hotsforthots:BAAANQAECgIIAwAAAA==.',
Hu='Huntyboi:BAAANQADCgUIBwAAAA==.',
Hy='Hyena:BAAANQAECgEIAQAAAA==.',
Ii='Iilli:BAAANQADCgYIBgAAAA==.',
In='Inari:BAAANQADCgYIBQAAAA==.Inkkubus:BAAANQAFFAEIAQAAAA==.',
Ir='Ironfur:BAAANQABCgQIBgABNQAECggIHAAEAFAcAA==.',
Je='Jeffpwnros:BAAANQAECgQIBQAAAA==.',
Ji='Jintan:BAAANQAECgEIAQAAAA==.',
Ka='Kaing:BAAANQAECgQIBAAAAA==.Kaissa:BAAANQADCgEIAQAAAA==.Kalena:BAAANQADCggIEAAAAA==.Kariatyda:BAAANQAECgQIBQAAAA==.Kasaí:BAAANQADCggIEwAAAA==.Kassandra:BAAANQADCggICAAAAA==.',
Ki='Kiloton:BAAANQADCggIEQAAAA==.Kitzy:BAAANQAECgIIAgAAAA==.',
Kl='Klippertdk:BAAANQAECgMIAwAAAA==.Klutz:BAAANQAECgMIBAAAAA==.',
Ku='Kurzo:BAAANQAECgYICQAAAA==.',
Ky='Kylarian:BAAANQAECgEIAQAAAA==.Kyntara:BAAANQAECgQIBAAAAA==.',
La='Lachancea:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Lakshmee:BAAANQADCggICwAAAA==.Lanre:BAAANQADCgcIBwAAAA==.',
Le='Ledarm:BAAANQAECgIIAgAAAA==.Lexxi:BAAANQAECgIIAgAAAA==.',
Li='Lightbehunt:BAAANQAECgIIAgAAAA==.Livaless:BAAANQAECgMIAwABNQAECgUIBQABAAAAAA==.',
Lu='Lucialyn:BAAANQAECgYIBAABNQAECgcIBQABAAAAAA==.',
Ma='Maitotoxin:BAAANQADCggIEgAAAA==.Malthaius:BAAANQADCgUIBQAAAA==.Mastablasta:BAAANQAECgMIBgAAAA==.Matfekk:BAAANQADCgEIAQAAAA==.Maursaline:BAAANQAECgIIAgAAAA==.Mawks:BAAANQAECgQIBQAAAA==.',
Me='Meragos:BAAANQADCgEIAQAAAA==.',
Mo='Moisten:BAAANQADCgMIAwABNQAECgIIAwABAAAAAA==.Monkent:BAAANQADCgQIBAAAAA==.',
Na='Nallaa:BAAANQAECgEIAQAAAA==.Naranak:BAAANQADCgQIBAAAAA==.',
Ne='Neremian:BAAANQADCgMIAwAAAA==.',
No='Noodles:BAAANQADCggIEAAAAA==.',
Ny='Nymara:BAAANQAECgEIAQAAAA==.',
Ol='Oldenglish:BAAANQADCgQIBAAAAA==.',
On='Ontos:BAAANQAECgQIBAAAAA==.',
Pa='Painnkiller:BAAANQAECgMIAwAAAA==.Pallycracker:BAAANQADCgEIAQAAAA==.Parsley:BAAANQADCgcIEgABNQAECgIIAgABAAAAAA==.',
Pe='Perriwinkle:BAAANQAECgYIDgAAAA==.',
Ph='Phylloxeras:BAAANQAECgQIBwAAAA==.',
Po='Powders:BAAANQAECgQIBQAAAA==.',
Pr='Priopopo:BAAANQABCgIIBAAAAA==.Prophecyrose:BAAANQADCgQIBQAAAA==.Proshot:BAAANQAECgIIAgAAAA==.',
Pu='Puddles:BAAANQADCgMIBQAAAA==.',
Py='Pyrasi:BAAANQAECgUICAAAAA==.',
Ra='Raccoon:BAAANQAECgEIAQAAAA==.Ralor:BAAANQADCgMIAwAAAA==.Razza:BAAANQADCggIEQAAAA==.',
Rh='Rhewz:BAAANQADCgYIBgAAAA==.',
Ri='Rivet:BAAANQADCgYIBgABNQAECgUIBgABAAAAAA==.',
Ro='Roa:BAAANQADCggIDgAAAA==.Rokkuhato:BAAANQAECgEIAQAAAA==.Roronoazoro:BAABNQAECoEXAAIFAAkJrRqlCQDdAgAFAAkJrRqlCQDdAgAAAA==.',
Ry='Ryrin:BAAANQADCgYIBgAAAA==.',
['Rë']='Rëggië:BAAANQAECgEIAQAAAA==.',
Sa='Samidrac:BAAANQADCgYICwAAAA==.Sammidormu:BAAANQADCgYIEAAAAA==.Saräha:BAAANQADCgUIBAAAAA==.Satòshí:BAAANQADCgQIBAAAAA==.',
Sc='Scerevisiae:BAAANQAECgEIAQAAAA==.',
Se='Sedelis:BAAANQAECgIIAgAAAA==.Selaya:BAAANQADCgUIBQAAAA==.Serafín:BAAANQAECgMIAwAAAA==.',
Sh='Shaadra:BAAANQADCgMIAwAAAA==.Shaay:BAAANQADCgUICQAAAA==.Shazzam:BAAANQADCgEIAQAAAA==.Shieldwall:BAAANQAECgIIAgAAAA==.',
Si='Silanah:BAAANQADCgcIEgABNQAECgcIDQABAAAAAA==.Silveroaks:BAAANQADCgMIAwAAAA==.',
So='Somavra:BAAANQADCggIDQAAAA==.Sopidia:BAAANQADCgYIEAAAAA==.Sorvato:BAAANQADCgYICAAAAA==.',
Sp='Spiritholy:BAAANQAECgEIAgAAAA==.Spúdd:BAAANQAECgIIAgAAAA==.',
St='Stamavan:BAAANQAECgIIAgAAAA==.',
Su='Supermelon:BAAANQAECgEIAQAAAA==.',
Sy='Syena:BAAANQADCgIIAgAAAA==.Sylvanaria:BAAANQAECgMIAwAAAA==.',
Ta='Tammirya:BAAANQADCgEIAQAAAA==.',
Te='Television:BAAANQADCgYIBgAAAA==.Teronreborn:BAAANQAECgIIAgAAAA==.',
Th='Thaneer:BAAANQADCgQIBAAAAA==.Throstmok:BAAANQAECgYICQAAAA==.Thumbalina:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.',
Ti='Tiantu:BAAANQADCggIEgAAAA==.Tilingo:BAAANQADCgYIBwAAAA==.',
To='Torg:BAAANQAECgMIAwAAAA==.',
Tu='Turgies:BAAANQAECgMIAwAAAA==.',
Ub='Ubaubajuana:BAAANQADCgUIBQAAAA==.',
Ul='Ulfast:BAAANQAECgMIAwAAAA==.',
Va='Vannhellsing:BAAANQAECgMIAwAAAA==.Vanyel:BAAANQAECgQIBgAAAA==.',
Ve='Vemal:BAAANQADCggIFAAAAA==.',
Vi='Vidula:BAAANQABCgQIBAAAAA==.Vigorous:BAAANQAECgEIAQAAAA==.',
Vo='Vociferoy:BAAANQAECgMIAwAAAA==.Voidsteffan:BAAANQAECgIIAgAAAA==.',
Vv='Vv:BAACNQAFFIEKAAMGAAYJHB5xAADqAQAGAAUJmhxxAADqAQAFAAUJ4hjZAADcAQA1AAQKgR0AAwUACQmMJpkAAN8DAAUACQmMJpkAAN8DAAYABQlKJLQPAAQCAAAA.',
Wu='Wushiilock:BAAANQADCgQIBAABNQAECgkJGQAHAFAiAA==.',
Xu='Xul:BAAANQABCgYIBgAAAA==.',
Xy='Xyphër:BAAANQADCgQIBAAAAA==.',
Za='Zannytoes:BAAANQAECgIIAgAAAA==.',
Zi='Zie:BAAANQAECgQIBgAAAA==.',
['Ñi']='Ñice:BAABNQAECoEXAAMIAAkJCyK2AAAdAwAIAAgJyCG2AAAdAwAJAAYJwhlcQwC7AQAAAA==.',
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
