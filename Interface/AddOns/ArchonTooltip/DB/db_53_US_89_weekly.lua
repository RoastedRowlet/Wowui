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

local lookup = {'Unknown-Unknown','Shaman-Elemental',}
local provider = {region='US',realm='Eonar',name='US',type='weekly',zone=53,date='2026-09-01',data={Ab='Abysseus:BAAANQADCgcIDwAAAA==.',
Aj='Ajagar:BAAANQADCgYICgAAAA==.',
Al='Alamora:BAAANQADCgMIBgAAAA==.Alathena:BAAANQAECgMIAwAAAA==.Alexandrya:BAAANQAECgMIAwAAAA==.Alickdh:BAAANQADCgIIAgABNQADCgYIBgABAAAAAA==.Almostpanda:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.',
Am='Amsahunter:BAAANQADCggICAAAAA==.Amsroeb:BAAANQADCgcIDAABNQADCggICAABAAAAAA==.',
An='Anelavenger:BAAANQAECgYICgAAAA==.',
Ar='Arathor:BAAANQADCgUICQAAAA==.Ardor:BAAANQADCgYICgAAAA==.Arent:BAAANQAECgIIAgAAAA==.Arkanna:BAAANQADCgYIBgAAAA==.Artemislives:BAAANQADCgYIBgAAAA==.',
As='Asharia:BAAANQADCgcIBwAAAA==.Assateague:BAAANQADCgMIBgAAAA==.',
['Aë']='Aëro:BAAANQABCgMIAwAAAA==.',
Ba='Bananapistol:BAAANQABCgIIBAAAAA==.',
Be='Beefcake:BAAANQADCgYICgAAAA==.Beserol:BAAANQADCgYIBwAAAA==.',
Bi='Biest:BAAANQADCggIEAAAAA==.Billy:BAAANQAECgEIAQAAAA==.Bionicle:BAAANQADCgQIBAAAAA==.Biscuít:BAAANQAECgIIAgAAAA==.',
Bl='Bloodeagle:BAAANQADCggICAAAAA==.Bloodyfate:BAAANQADCgYIBgAAAA==.Bluechalk:BAAANQADCgIIAgABNQAECggIDwABAAAAAA==.',
Bo='Boomslap:BAAANQAECgEIAQAAAA==.Borzoi:BAAANQAECgQICAAAAA==.',
Br='Brawne:BAAANQADCgUIBQAAAA==.',
Bu='Buzzdruu:BAAANQADCgMIAwAAAA==.',
['Bø']='Bønës:BAAANQADCgQIBAAAAA==.',
Ca='Caduceus:BAAANQADCgUIBQAAAA==.Caesus:BAAANQADCgMIBAAAAA==.Cagedancer:BAAANQADCgUICQAAAA==.Callio:BAAANQAECgIIAgAAAA==.Caritta:BAAANQAECgEIAQAAAA==.Cathillex:BAAANQADCgYICwAAAA==.Caycay:BAAANQAECgcICwAAAA==.',
Ch='Chillbros:BAAANQAECgcICgAAAA==.Churd:BAAANQAECgIIAgAAAA==.Chypnotic:BAAANQADCggIDwAAAA==.',
Cl='Cleft:BAAANQADCggIDgAAAA==.Clowwnshoes:BAAANQADCgcICAAAAA==.',
Co='Coalystra:BAAANQAECgIIAgAAAA==.Cocopuffs:BAAANQAECgEIAQAAAA==.Colostrom:BAAANQAECgIIAgAAAA==.Coramage:BAAANQADCgcIDAAAAA==.Corliss:BAAANQADCggIDgAAAA==.Corruptdata:BAAANQAECgEIAQABNQAECgcICQABAAAAAA==.',
Da='Darkbeast:BAAANQAECgEIAQAAAA==.Daten:BAAANQAECgQIBAAAAA==.Dazshauran:BAAANQADCgEIAQAAAA==.',
De='Deadzexcs:BAAANQADCgQIBwAAAA==.Decayed:BAAANQADCgcIBwAAAA==.Deladoria:BAAANQAECgEIAQAAAA==.',
Di='Diagonalli:BAAANQADCgEIAQAAAA==.Dirkdìggler:BAAANQADCgUIBwAAAA==.Divirian:BAAANQABCgQIBAAAAA==.',
Dj='Djdrakshadow:BAAANQADCgMIBAAAAA==.Djpriest:BAAANQADCgEIAQAAAA==.Djshadowar:BAAANQADCgYIBwAAAA==.Djshadowhunt:BAAANQADCgQIBAAAAA==.Djshadowlock:BAAANQABCgQIBgAAAA==.Djshadowlok:BAAANQADCgEIAQAAAA==.Djshadowrog:BAAANQADCgUIBQAAAA==.Djshamy:BAAANQABCgQIBAAAAA==.Djzhadow:BAAANQABCgIIAgAAAA==.',
Dk='Dkshadow:BAAANQADCgMIAwAAAA==.',
Dr='Draktând:BAAANQADCggIDgAAAA==.Dreve:BAAANQABCgIIBAAAAA==.Drunkenpanda:BAAANQAECgEIAQAAAA==.',
Ec='Echö:BAEANQAECgIIAgAAAA==.',
El='Elaine:BAAANQADCgQIBAAAAA==.Elronnd:BAAANQADCgIIAgAAAA==.Elöhim:BAAANQAECgYIBgAAAA==.',
Ep='Epic:BAAANQADCgYICQAAAA==.',
Er='Erebosa:BAAANQABCgIIAgAAAA==.',
Fa='Fatherchill:BAAANQAECgIIAgAAAA==.',
Fi='Fitco:BAAANQADCgYIBgABNQAECgEIAgABAAAAAA==.',
Fr='Frantecks:BAAANQADCggICAAAAA==.Freela:BAEANQADCgUIBQAAAA==.Frostmon:BAAANQAECgUIBgAAAA==.',
Fu='Furbee:BAAANQAECggIBgAAAA==.',
Ga='Garim:BAAANQADCggIDwAAAA==.Gaztingo:BAAANQAECgIIAgAAAA==.',
Gi='Girthshock:BAAANQADCgcIBwABNQAECgUIBwABAAAAAA==.',
Gn='Gnar:BAAANQADCgEIAQAAAA==.',
Go='Gobi:BAAANQADCgMIAwAAAA==.Gowtherpunch:BAAANQAECgIIAgAAAA==.',
Gr='Gruxxiron:BAAANQAECgIIAgAAAA==.',
Gu='Gulnn:BAAANQADCgcIBwAAAA==.',
Ha='Haelena:BAAANQADCgYICgAAAA==.Harmossy:BAAANQAECgIIAgAAAA==.',
He='Heriotza:BAAANQAECgIIAgAAAA==.',
Ho='Holypaladin:BAAANQAECgYICgAAAA==.',
Ii='Iimit:BAAANQAECgQIBAAAAA==.',
Il='Illidead:BAAANQAECgYICwAAAA==.Illooj:BAAANQAECgYICgAAAA==.',
In='Indexes:BAAANQADCgYICgAAAA==.Inspiration:BAAANQADCgQICwAAAA==.',
Is='Ist:BAAANQAECgEIAQAAAA==.',
It='Itskamertime:BAAANQADCgcIDwABNQAECgIIAwABAAAAAA==.',
Iv='Ivgorod:BAAANQADCgcIDAAAAA==.',
Ja='Jarhead:BAAANQADCgMIBgAAAA==.Jazilyne:BAAANQADCgMIAwAAAA==.',
Ju='Justcalmdown:BAAANQADCgcICwABNQAECgIIAgABAAAAAA==.Justyra:BAAANQADCgYIBgABNQADCggIDwABAAAAAA==.',
Ka='Kambative:BAAANQAECgIIAwAAAA==.Kamphiyer:BAAANQADCgMIAwABNQAECgIIAwABAAAAAA==.Kantheal:BAAANQADCgcIDAAAAA==.',
Ki='Kiagas:BAAANQAECgUIBQAAAA==.Kimbrawly:BAAANQADCgYIBgAAAA==.',
Kr='Kravex:BAAANQADCgYICwAAAA==.',
Ku='Kukoc:BAAANQADCgUIBQABNQAECgMIAwABAAAAAA==.',
La='Lanta:BAAANQAECgQIBAAAAA==.Larayvia:BAAANQAECgMIAwAAAA==.',
Le='Leesala:BAAANQAECgIIAgAAAA==.',
Li='Lic:BAAANQADCgUICAAAAA==.Lilililil:BAAANQAECgIIAgAAAA==.Lillabet:BAAANQADCgMIBgAAAA==.Limpydk:BAAANQADCgUIBQABNQAECgUIBwABAAAAAA==.Limpypal:BAAANQAECgUIBwAAAA==.',
Ma='Magifur:BAAANQAECgIIAwAAAA==.Magnakilro:BAAANQADCggICAAAAA==.Magnomar:BAAANQADCgcIDQAAAA==.Maleficus:BAAANQADCgUICgABNQADCgYICgABAAAAAA==.Mamoswine:BAAANQABCgIIBAAAAA==.Mattyfu:BAAANQAECgEIAQAAAA==.Mazikeen:BAAANQADCgcIDQAAAA==.',
Me='Meatsupreme:BAAANQAECgIIAgAAAA==.Meepin:BAAANQAECgYICgAAAA==.Mesopyro:BAAANQADCgMIBgAAAA==.',
Mi='Microchyp:BAAANQADCgEIAQAAAA==.Milemarker:BAAANQAECgEIAQAAAA==.',
Mo='Mojodaemon:BAAANQADCgUIBQAAAA==.Moondevil:BAAANQADCgMIAwAAAA==.Morta:BAEANQADCgQIBAABNQADCgUIBQABAAAAAA==.',
Mu='Muted:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.',
['Mö']='Mörph:BAAANQADCgUIBQAAAA==.',
Na='Narrodus:BAAANQADCgcIDAAAAA==.Nasht:BAAANQADCggICQAAAA==.Nataku:BAAANQADCgYIBgAAAA==.',
Ne='Neelix:BAAANQADCgUICAAAAA==.Nezzick:BAAANQAECgIIAgAAAA==.',
Ni='Nightreaper:BAAANQADCgUIBQAAAA==.Nimbus:BAABNQAECoEaAAICAAkJVR5mAgBdAwACAAkJVR5mAgBdAwAAAA==.',
No='Normel:BAAANQAECgEIAQAAAA==.Noz:BAAANQADCgQIBAABNQAECgQIBwABAAAAAA==.',
Nr='Nrvous:BAAANQADCgIIAgAAAA==.',
Ny='Nytesage:BAAANQAECgcICQAAAA==.',
['Nä']='Näners:BAAANQADCgYIBwABNQAECgcIDQABAAAAAA==.',
['Në']='Nëvërmind:BAAANQADCgcIDQAAAA==.',
['Nì']='Nìghtcat:BAAANQADCgYICwAAAA==.',
Oz='Ozgar:BAAANQADCgYICAAAAA==.Ozo:BAAANQADCgIIAgAAAA==.',
Pa='Painavolian:BAAANQAECgQIBwAAAA==.',
Ph='Phoenixdówn:BAAANQADCgcIBwAAAA==.',
Pi='Pingpong:BAAANQAECgEIAQAAAA==.Pisspadpanda:BAAANQAECgMIAwAAAA==.',
Po='Poggies:BAAANQAECgcIBwAAAA==.Potatodh:BAAANQAECgEIAgAAAA==.',
Pr='Praynes:BAAANQAECgIIAgAAAA==.',
Pu='Puppet:BAAANQADCgEIAQAAAA==.',
Py='Pylanora:BAAANQADCgMIAwAAAA==.',
Ra='Rael:BAAANQADCgIIAgAAAA==.Ranoe:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.Raxity:BAAANQADCgIIAgAAAA==.Razji:BAAANQAECgIIAgAAAA==.',
Ri='Riete:BAAANQADCggIDQAAAA==.',
Ro='Rocknwolf:BAAANQADCgYIBwAAAA==.Rokd:BAAANQAECgIIAgAAAA==.Roscoelock:BAAANQAECgQIBQAAAA==.',
Ru='Ruibaron:BAAANQADCgUIBQAAAA==.',
['Rá']='Ráyne:BAAANQADCgQIBwAAAA==.',
Sa='Sadeel:BAAANQAECgIIAgAAAA==.Sadewolf:BAAANQAECgIIAgAAAA==.Samentoni:BAAANQAECgIIAgAAAA==.Samgal:BAAANQADCgcIDAAAAA==.Sampsyn:BAAANQABCgQIBAAAAA==.Satyra:BAAANQADCggIDwAAAA==.Saurphang:BAAANQAECgYICQAAAA==.',
Sc='Scamanes:BAAANQADCgcIBwAAAA==.',
Se='Severis:BAAANQADCgEIAQAAAA==.',
Sh='Shadora:BAAANQADCggIDgAAAA==.Shadowwizard:BAAANQAECgMIAwAAAA==.Shaladin:BAAANQADCggICAAAAA==.Shidan:BAAANQAECgQIBwAAAA==.Shockaho:BAAANQAECgMIAwAAAA==.Shockchalk:BAAANQAECggIDwAAAA==.Shocknorris:BAAANQAECgEIAgAAAA==.Shulk:BAAANQADCgcIDAAAAA==.',
Si='Sibbiah:BAEANQADCgYIDQAAAQ==.Silanre:BAAANQADCgYICgAAAA==.',
Sk='Skaðï:BAAANQAECgYICwAAAA==.',
Sp='Spadesrage:BAAANQADCgQIBwAAAA==.Spicyycurryy:BAAANQAECgIIAwAAAA==.',
St='Strahm:BAAANQADCggIDwAAAA==.Stryhm:BAAANQADCgQIBAABNQADCggIDwABAAAAAA==.',
Su='Sulfass:BAAANQABCgIIAgAAAA==.',
Sy='Sylryn:BAAANQADCgQIBAAAAA==.Symple:BAAANQADCgQIBwAAAA==.Synz:BAAANQADCgYIBgAAAA==.Syssare:BAAANQADCggIDgAAAA==.',
Ta='Tacpally:BAAANQADCgIIAwAAAA==.Talamor:BAAANQADCgMIAwAAAA==.Talasam:BAAANQADCgQIBAAAAA==.Tastetickle:BAAANQAECgIIAgAAAA==.Tazdrin:BAAANQAECgIIAgAAAA==.',
Te='Telidrus:BAAANQAECgcIDQAAAA==.Teneturadvys:BAAANQADCgQIBAABNQADCggIDQABAAAAAA==.',
Th='Thicc:BAAANQABCgQIBAAAAA==.Thicchunter:BAAANQAECgIIAgAAAA==.Thiccwiggy:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.Thunderbug:BAAANQADCgIIAgAAAA==.',
To='Topaze:BAAANQAECgQIBAAAAA==.Totemmonster:BAAANQABCgIIAgAAAA==.',
Tr='Tripx:BAAANQAECgcICQAAAA==.Tripxed:BAAANQAECgEIAQABNQAECgcICQABAAAAAA==.Trishan:BAAANQADCgIIAgAAAA==.Trolk:BAAANQADCgIIAgAAAA==.Tronko:BAAANQADCgMIAwAAAA==.',
Tu='Turntsnaco:BAAANQAECgQIBAAAAA==.',
Un='Unafhaen:BAAANQADCgQIBAAAAA==.Unaverse:BAAANQADCgYIBgAAAA==.',
Us='Usmccpl:BAAANQADCgYICQAAAA==.',
Va='Valengarde:BAAANQADCgIIAgAAAA==.Vangoon:BAAANQADCgcICQAAAA==.Vann:BAAANQADCgMIAwAAAA==.Vannix:BAAANQAECgIIAgAAAA==.',
Ve='Vereena:BAAANQADCgYIBgAAAA==.Vesstar:BAAANQABCgIIAgAAAA==.',
Vi='Virmethir:BAAANQADCgcICwAAAA==.',
Wi='Wiwi:BAAANQAECgcIDAAAAA==.',
Xa='Xares:BAAANQAECgIIAgABNQAECgQIBAABAAAAAA==.',
Xe='Xenp:BAAANQAECgEIAQAAAA==.',
Xu='Xuri:BAAANQAECgIIAgAAAA==.',
['Yö']='Yöurfired:BAAANQADCgQICAAAAA==.',
Za='Zake:BAAANQAECgMIAwAAAA==.Zalileina:BAAANQADCgMIAgAAAA==.Zantanna:BAAANQADCgQIBAAAAA==.Zappythile:BAAANQADCggIDQAAAA==.Zayiro:BAAANQADCgYIDAAAAA==.',
Zo='Zoz:BAAANQADCgMIBgAAAA==.',
Zu='Zulfrik:BAAANQAECgIIAgAAAA==.',
Zy='Zyzy:BAAANQAECgMIAwABNQAECgcICQABAAAAAA==.',
['ße']='ßeef:BAAANQADCgcIDAAAAA==.',
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
