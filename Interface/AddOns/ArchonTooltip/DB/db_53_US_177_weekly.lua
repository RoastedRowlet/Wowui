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
local provider = {region='US',realm='Ravencrest',name='US',type='weekly',zone=53,date='2026-09-01',data={Ab='Abracadavr:BAAANQADCgQIBAAAAA==.',
Ac='Acell:BAAANQADCggIHAAAAA==.',
Ad='Adeleas:BAAANQADCgcICQAAAA==.Adêrna:BAAANQAECgIIAgAAAA==.',
Ag='Agba:BAAANQAECgMIAwAAAA==.',
Ai='Aibrean:BAAANQADCgcIDAAAAA==.',
Al='Alaala:BAAANQADCgUIBQAAAA==.Alaidan:BAAANQADCgYICgAAAA==.Alanus:BAAANQADCgcICgAAAA==.Alarion:BAAANQADCgQIBgAAAA==.Alavia:BAAANQAECgMIAwAAAA==.Alydrus:BAAANQADCgQIBAAAAA==.',
An='Angryelf:BAAANQADCgYIBgAAAA==.Annahe:BAAANQAECgEIAQAAAA==.Anub:BAAANQAECgEIAQAAAA==.Anzala:BAAANQADCgUIBQAAAA==.',
Ar='Armsmaster:BAAANQADCggIHAABNQAECgEIAQABAAAAAA==.Artemistha:BAAANQADCgYICwAAAA==.',
Av='Avielle:BAAANQADCgUIBQAAAA==.',
['Aø']='Aøi:BAAANQADCggICAAAAA==.',
Ba='Baey:BAAANQABCgEIAQAAAA==.Barelycastin:BAAANQAECgEIAQAAAA==.',
Be='Beleriand:BAAANQADCgcICwAAAA==.Belgarathh:BAAANQADCgMIAwAAAA==.Bellei:BAAANQADCgcIBwAAAA==.',
Bl='Blacat:BAAANQAECgIIAwAAAA==.Blacksirloin:BAAANQADCgYIBgAAAA==.Blitzcomets:BAAANQADCgUIBgAAAA==.Bloodshunter:BAAANQADCgYICAAAAA==.',
Bo='Borda:BAAANQADCgUIBQAAAA==.',
Br='Brendenhunt:BAAANQADCggICAAAAA==.',
Bu='Buddypal:BAAANQADCgYICAAAAA==.Buddypriest:BAAANQADCgIIAgABNQADCgYICAABAAAAAA==.',
Ca='Carini:BAAANQAECgEIAQAAAA==.',
Ch='Chickynuggy:BAAANQADCgcIBwAAAA==.Chrischan:BAAANQABCgMIAQAAAA==.Chónk:BAAANQADCgQIBgAAAA==.',
Cl='Clûtch:BAAANQAECgIIAgAAAA==.',
Co='Corynthe:BAAANQADCggIDwAAAA==.',
Cr='Crickie:BAAANQADCgYICwAAAA==.Crovaxis:BAAANQAECgEIAQAAAA==.',
Da='Daedrìc:BAAANQADCgQIBAAAAA==.Darktalyn:BAAANQAECgEIAQAAAA==.',
De='Deathgrip:BAAANQADCgUIBgAAAA==.Deathhawkzz:BAAANQAECgMIAwAAAA==.Deekura:BAAANQADCgcIDQAAAA==.Dezireth:BAAANQAECgQIBAAAAA==.',
Di='Dinak:BAAANQADCgcICgAAAA==.Dionan:BAAANQAECgEIAQAAAA==.',
Do='Docs:BAAANQADCgUIBQAAAA==.Doks:BAAANQADCggIDgAAAA==.',
Ea='Ealara:BAAANQADCgcIBwAAAA==.',
Ec='Echidna:BAAANQADCggICAABNQAECggICwABAAAAAA==.',
Em='Emiira:BAAANQADCggIDgAAAA==.',
Er='Erebrethil:BAAANQADCgYIBgAAAA==.',
Es='Espe:BAAANQAECgEIAQAAAA==.',
Fa='Fallen:BAAANQAECgEIAQAAAA==.Faynor:BAAANQADCggIDwAAAA==.',
Fi='Finalycalm:BAAANQADCgQIBAAAAA==.',
Fr='Fraggle:BAEANQAECgcIDAAAAA==.Frogchi:BAAANQADCgYICwAAAA==.Frostbité:BAAANQADCggIDAAAAA==.Fruit:BAAANQADCgUICQAAAA==.',
Fu='Fumikiko:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.',
['Fí']='Físh:BAAANQADCgcICAABNQAECgEIAQABAAAAAA==.',
Ga='Gali:BAAANQADCgYIBgAAAA==.Gargybyn:BAAANQADCgUIBwAAAA==.',
Gi='Girliepop:BAAANQADCgIIAgAAAA==.',
Gl='Glaistiguain:BAAANQAECgEIAQAAAA==.Glifin:BAAANQADCgUICgAAAA==.Glizzeldra:BAAANQADCgUIBQAAAA==.Gloomstalkin:BAAANQADCgcIBwABNQAECgIIAgABAAAAAA==.Glynna:BAAANQADCgUIBQAAAA==.',
Gr='Gr:BAAANQADCgcICgAAAA==.Gryffs:BAAANQADCggIDgAAAA==.',
Gu='Gutts:BAAANQADCgcICgABNQAECgEIAQABAAAAAA==.',
['Gì']='Gìzmo:BAAANQADCgcIBwAAAA==.',
Ha='Halartion:BAAANQADCgYICQAAAA==.Haruun:BAAANQADCgUIBgAAAA==.',
He='Hesmydaddy:BAAANQAECgIIAgAAAA==.',
Ic='Icemann:BAAANQABCgIIAgAAAA==.',
Im='Imherdaddy:BAAANQAECgIIAgAAAA==.',
Ja='Jarrack:BAAANQADCggIDwAAAA==.Jaye:BAAANQABCgQIBAAAAA==.',
Je='Jessicae:BAAANQAECgEIAQAAAA==.Jeuno:BAAANQADCggIDgABNQAECgEIAQABAAAAAA==.',
Ju='Junazeena:BAAANQADCgYIDAAAAA==.',
Ka='Kayfabe:BAAANQADCgcICwAAAA==.',
Ke='Keirasti:BAAANQADCgQIBgABNQADCgcICQABAAAAAA==.Keishilda:BAAANQADCgIIBAAAAA==.Keladria:BAAANQADCgQIBgAAAA==.Kelirra:BAAANQADCgIIAgAAAA==.Kenel:BAAANQAECgIIAgAAAA==.Kerea:BAAANQADCggIDwAAAA==.Keyarga:BAAANQADCgUIBQABNQADCgcIDAABAAAAAA==.',
Kh='Khazadoom:BAAANQADCgQIBgAAAA==.Khazargon:BAAANQADCgYIBgAAAA==.',
Ki='Kicken:BAAANQADCgcIDQAAAA==.',
Ko='Korthelan:BAAANQAECgIIAgAAAA==.Kothara:BAAANQADCggIDwAAAA==.',
Kr='Krimzin:BAAANQAECgcICwAAAA==.Krystine:BAAANQADCgUICQAAAA==.',
Ks='Kserasera:BAAANQAECgIIAgAAAA==.',
Ku='Kuball:BAAANQAECgEIAQAAAA==.',
['Kî']='Kîllara:BAAANQADCgUIBQAAAA==.',
Le='Lebronjames:BAAANQAECgEIAQAAAA==.Letheos:BAAANQAECgUIBwAAAA==.',
Li='Librarte:BAAANQADCggIEAAAAA==.Litty:BAAANQADCgYICAAAAA==.',
Lo='Loalu:BAAANQADCgUICAAAAA==.Locktärd:BAAANQADCgcIDQABNQAECgYIBgABAAAAAA==.Lox:BAAANQADCggIDwAAAA==.',
Ly='Lydirn:BAAANQADCgUIBgAAAA==.',
['Lí']='Lítterbox:BAAANQADCgcICAAAAA==.',
Ma='Magedzen:BAAANQABCgIIAgAAAA==.Magicguy:BAAANQADCgcIBwAAAA==.Mahariel:BAAANQAECgIIAgAAAA==.Mahdy:BAAANQAECgQIBQAAAA==.Malva:BAAANQADCgcIBwAAAA==.Marcie:BAAANQADCggIDwAAAA==.Martinriggz:BAAANQADCgYICgAAAA==.',
Me='Meatyloaf:BAAANQADCgYICwAAAA==.Medsedation:BAAANQAECgIIAgAAAA==.Melkedrik:BAAANQADCgYICwAAAA==.Melleren:BAAANQADCgYIBgAAAA==.',
Mi='Mirei:BAAANQADCgcIDQAAAA==.',
Mo='Moolander:BAAANQADCgQIBAAAAA==.Moovidlin:BAAANQADCgUIBgAAAA==.',
Mu='Mushhead:BAAANQAECgIIAgAAAA==.',
My='Mythantherox:BAAANQADCgcICAABNQAECgYICQABAAAAAA==.',
Ne='Nethershade:BAAANQADCgcIDQAAAA==.',
Ni='Niclea:BAAANQADCgUIBQAAAA==.Nightelm:BAAANQAECgEIAQAAAA==.',
No='Nostradamuz:BAAANQAECgIIAgAAAA==.',
Ny='Nymneria:BAAANQADCgYICwAAAA==.Nyxiera:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Nyxstonia:BAAANQAECgEIAQAAAA==.',
Ol='Olierra:BAAANQADCgQIBAAAAA==.',
Or='Oreshin:BAAANQADCgYICgAAAA==.Orphantrope:BAAANQABCgEIAQAAAA==.',
Ot='Otto:BAAANQADCgEIAQAAAA==.Ottomagus:BAAANQADCgcIDAAAAA==.',
Pe='Persephoneia:BAAANQAECgEIAQAAAA==.',
Pi='Piperclip:BAAANQADCgYIBgAAAA==.',
Pr='Preacherman:BAAANQADCgQIBgAAAA==.Priority:BAAANQADCgQIBAAAAA==.',
Ra='Ravenloare:BAAANQABCgQIBAAAAA==.',
Ri='Rilz:BAAANQAECgEIAQAAAA==.',
Ro='Rockasham:BAAANQADCgYICwAAAA==.Rottn:BAAANQADCgcICAAAAA==.',
Sa='Safmen:BAAANQADCgIIAgAAAA==.Sanikoa:BAAANQADCgEIAQAAAA==.Saraid:BAAANQAECgEIAQAAAA==.Saravase:BAAANQADCgMIAwAAAA==.Saurot:BAAANQADCgIIAgAAAA==.',
Se='Sev:BAAANQADCgQIBgAAAA==.Señorcleave:BAAANQADCgQICgAAAA==.',
Sh='Shadk:BAEANQAECgEIAQAAAA==.Shadowstorm:BAAANQAECgIIAgAAAA==.Shinoto:BAAANQADCgYIDQAAAA==.',
Si='Silvein:BAAANQADCggICgAAAA==.Silverpower:BAAANQADCgIIAgAAAA==.',
Sk='Skyë:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.',
Sp='Spyro:BAAANQAECgMIAwAAAA==.',
Sr='Sron:BAAANQAECgEIAQAAAA==.',
Sw='Swooze:BAAANQAECgMIAwAAAA==.',
Sy='Syndar:BAAANQADCgQIBAABNQADCggICAABAAAAAA==.',
Sz='Szuzette:BAAANQADCgIIAgAAAA==.',
Ta='Tankcontrols:BAAANQADCgQIBAAAAA==.Tarlyn:BAAANQAECgEIAQAAAA==.',
Th='Thaenet:BAAANQADCgUIBwAAAA==.',
To='Topu:BAAANQADCgcICQAAAA==.',
Tr='Trek:BAAANQADCggICAAAAA==.',
Us='Usdaprime:BAAANQADCgYIDAAAAA==.',
Va='Valhalia:BAAANQAECgEIAQAAAA==.',
Ve='Velinariae:BAAANQADCgMIBAAAAA==.Vengful:BAAANQADCgYIDAAAAA==.',
Vh='Vhalúryn:BAAANQADCgQIBgAAAA==.',
Vo='Vorumbrae:BAAANQADCgYICgAAAA==.',
Wa='Wali:BAAANQAECgEIAQAAAA==.',
Wi='Wildefaux:BAAANQADCggICAAAAA==.',
Wo='Wooties:BAAANQADCgMIBAABNQADCggIDgABAAAAAA==.',
Wy='Wyleriya:BAAANQADCggIDgAAAA==.',
Xc='Xcella:BAAANQADCgUIBwAAAA==.',
Xu='Xurael:BAAANQADCgYIBgAAAA==.',
Ye='Yelhsa:BAAANQADCgYIBgAAAA==.Yelizaveta:BAAANQADCgYICgAAAA==.',
Za='Zalarah:BAAANQADCgQIBgAAAA==.Zardan:BAAANQADCgYICwAAAA==.',
Zu='Zuggerker:BAAANQADCggIDwAAAA==.',
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
