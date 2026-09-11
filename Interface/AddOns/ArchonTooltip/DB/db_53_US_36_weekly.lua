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

local lookup = {'Unknown-Unknown','DeathKnight-Unholy','DeathKnight-Blood','Hunter-Marksmanship','Mage-Arcane','Evoker-Devastation',}
local provider = {region='US',realm="Blade'sEdge",name='US',type='weekly',zone=53,date='2026-09-08',data={Af='Affli:BAAANQAECgcIDAAAAA==.',
Ai='Aiunar:BAAANQAECgIIAgAAAA==.Aiupriesty:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.',
Ak='Aka:BAAANQADCgIIAgAAAA==.Akaza:BAAANQADCggICAAAAA==.',
Al='Alastiria:BAAANQADCgcIDgAAAA==.Aleinara:BAAANQADCgYIDQAAAA==.',
Am='Amazngrace:BAAANQADCgYIBgAAAA==.',
An='Annore:BAAANQAECgUIBwAAAA==.',
Aq='Aquelius:BAAANQADCgcIDgAAAA==.Aqular:BAAANQAECgQIBgAAAA==.',
Ar='Argyre:BAAANQAECgYIDAAAAA==.Artifice:BAAANQAECgMIAwAAAA==.',
Av='Avadakedevra:BAAANQADCggICgAAAA==.',
Aw='Awooing:BAAANQADCggIDgABNQAECgQIBQABAAAAAA==.',
Az='Azaziel:BAAANQAECgQIBAAAAA==.Azells:BAAANQADCgEIAQABNQAECgcIDwABAAAAAA==.',
Ba='Bariesh:BAAANQADCgQIBAAAAA==.',
Be='Behindyou:BAAANQADCgYIBwAAAA==.Belgaria:BAAANQADCgQIBAAAAA==.Berryknight:BAAANQADCgYIBgAAAA==.Bewlzeye:BAAANQAECgEIAQAAAA==.',
Bi='Bigjonmachne:BAAANQAECgQICAABNQAECggIDQABAAAAAA==.Binky:BAAANQADCgUIBQAAAA==.',
Bl='Blackguyy:BAAANQAECgUICwAAAA==.Bloodletter:BAAANQABCgIIAgAAAA==.Bloodsail:BAAANQADCgYIBgAAAA==.',
Bo='Bollux:BAAANQAECgUIBgAAAA==.Bonetatter:BAAANQADCgcIDgAAAA==.Bongonnaink:BAAANQAECgIIAgAAAA==.Bownyxia:BAAANQAECgYIBwABNQAFFAEIAQABAAAAAA==.Bowties:BAABNQAECoEZAAMCAAkJIiRGAgCnAwACAAkJIiRGAgCnAwADAAIJ4wwaVQB2AAABNQAFFAEIAQABAAAAAA==.',
Br='Brotie:BAAANQAFFAEIAQAAAA==.',
Bt='Btmanight:BAAANQADCggICAABNQAECgMIBgABAAAAAA==.',
Bu='Bullshiift:BAAANQADCgYIBgAAAA==.Burntbiscuit:BAAANQADCgUIBQAAAA==.Buugada:BAAANQADCgYIDwAAAA==.',
Ca='Caedo:BAAANQADCgIIAgABNQADCgMIAwABAAAAAA==.Calischism:BAAANQAECgEIAQAAAA==.Canadiangoos:BAAANQADCgUIBQAAAA==.Cavantes:BAAANQADCgIIAgAAAA==.',
Ce='Celaris:BAAANQADCgcICwAAAA==.Cell:BAAANQABCgEIAQAAAA==.',
Ch='Chataykay:BAAANQADCgQIBQAAAA==.Chathsong:BAAANQADCggICAAAAA==.Chichichikin:BAAANQADCgcIBwAAAA==.',
Ci='Citrus:BAAANQAECgQIBwAAAA==.',
Cn='Cn:BAAANQAECgYICAAAAA==.',
Co='Codeman:BAAANQAECgIIAgAAAA==.',
Cp='Cptinsaneo:BAAANQAECggIEgAAAA==.',
Cr='Crimdk:BAAANQAECgUIBwABNQAECggICQABAAAAAA==.',
Cz='Czin:BAAANQADCgUICAAAAA==.',
Da='Dalén:BAAANQADCgUIBQAAAA==.',
De='Deathverses:BAABNQAECoEpAAIEAAgJjCZ6AgCFAwAEAAgJjCZ6AgCFAwAAAA==.Demonbiscuit:BAAANQAECgcIDAAAAA==.Derpydawg:BAAANQADCgYIBgABNQAECgcIDQABAAAAAA==.Destructus:BAAANQAECgEIAgAAAA==.Deviancy:BAAANQAECgQIBQAAAA==.Devocean:BAAANQADCgUIBQAAAA==.Dexxt:BAAANQADCggICAAAAA==.',
Di='Dikslapp:BAAANQADCggICAAAAA==.Ditto:BAAANQADCggIHQAAAA==.',
Dl='Dlitinaro:BAAANQAECgQIBgAAAA==.',
Do='Donoph:BAAANQAECgIIAgAAAA==.Doomar:BAAANQAECgYIBgAAAA==.Dotzilla:BAAANQADCgEIAQAAAA==.',
Dr='Dragindznuts:BAAANQADCgEIAQAAAA==.Drayn:BAAANQAECgYICAAAAA==.Dreaveous:BAAANQAECgQIBgAAAA==.Drugar:BAAANQADCgcICwAAAA==.',
Du='Duint:BAAANQADCgUIBQAAAA==.',
Eb='Eborsisk:BAAANQADCgEIAQAAAA==.',
Ec='Eclipsion:BAAANQADCgcIBwAAAA==.',
Ee='Eelane:BAAANQAECgQICQAAAA==.',
El='Ell:BAAANQADCgMIAwAAAA==.',
Er='Eradication:BAAANQAECgYICwAAAA==.',
Et='Etheria:BAAANQAECgEIAQABNQAECgcIDwABAAAAAA==.',
Ev='Evilexo:BAAANQADCgcIBwAAAA==.',
Ex='Exxotic:BAAANQABCgIIAgAAAA==.',
Fa='Faedia:BAAANQABCgYICAABNQADCggIFQABAAAAAA==.Fahlafflez:BAAANQAECgYICAAAAA==.Fahros:BAAANQAECgYIDgAAAA==.',
Fe='Felful:BAAANQADCgUIBQABNQAECgYICwABAAAAAA==.',
Ff='Ffloyd:BAAANQADCgcIBwAAAA==.',
Fi='Fingielock:BAAANQADCgYIDAAAAA==.Fishinfridge:BAAANQAECgEIAQAAAA==.',
Fl='Flloyd:BAAANQAECgUIBQAAAA==.Floÿd:BAAANQADCgYIBgAAAA==.Fløyd:BAAANQADCgYIBgAAAA==.',
Fo='Folid:BAAANQADCgMIAwAAAA==.',
Fr='Francy:BAAANQAECgMIAwAAAA==.',
Fu='Fuzzyspells:BAAANQADCgcICwAAAA==.',
Ga='Gatzul:BAAANQADCgMIBAABNQADCggICAABAAAAAA==.',
Gh='Ghostbladez:BAAANQAECgQIBAAAAA==.',
Gi='Gib:BAAANQADCgMIAwAAAA==.',
Go='Goththighs:BAABNQAECoEYAAIFAAkJkSIpBwCKAwAFAAkJkSIpBwCKAwAAAA==.',
Gr='Grawler:BAAANQADCgYIBwAAAA==.Grimdk:BAAANQAECgEIAQAAAA==.Grissa:BAAANQAECgEIAQAAAA==.',
Gu='Gumgumfury:BAAANQADCgYIDwAAAA==.',
Ha='Halzlok:BAAANQAECgQIBAAAAA==.Harmful:BAAANQADCgcIBwABNQAECgYICgABAAAAAA==.',
He='Herøn:BAAANQADCgYICgAAAA==.',
Hi='Hilarie:BAAANQADCgYIBwAAAA==.',
Hu='Hunterschmax:BAAANQAECgQIBAAAAA==.',
Ih='Ihot:BAAANQADCggIGQAAAA==.',
Ik='Ikayhaimahn:BAAANQAECgYIDwAAAA==.',
In='Incideranus:BAAANQADCggIBAAAAA==.Indishaman:BAAANQAECgYICgAAAA==.',
Ir='Iris:BAAANQADCgMIAwAAAA==.Ironbound:BAAANQADCgUIBQABNQADCggIFQABAAAAAA==.',
Iv='Ivoric:BAAANQAECggICAAAAA==.',
Ja='Jabronygos:BAABNQAECoEXAAIGAAkJaBrpAwAKAwAGAAkJaBrpAwAKAwAAAA==.Jarnroz:BAAANQADCgIIAgAAAA==.',
Je='Jeatalena:BAAANQADCgYIBgAAAA==.',
Jh='Jhara:BAAANQADCggIFQAAAA==.',
Jo='Joeheals:BAAANQADCgUIBwAAAA==.',
Ju='Junior:BAAANQAECgEIAQABNQAECgcIDwABAAAAAA==.',
Ka='Kablinkiaa:BAAANQADCgYICAAAAA==.Kalypso:BAAANQADCggIEwAAAA==.Kamekazi:BAAANQADCgYIBgAAAA==.Katastrophic:BAAANQADCgQIBwAAAA==.',
Ke='Keelanllan:BAAANQADCgQIBAAAAA==.Keilun:BAEANQADCgIIAgAAAA==.Kertzz:BAAANQADCgcIDQABNQADCgcIDgABAAAAAA==.',
Kn='Kneecromance:BAAANQAECgEIAQAAAA==.Knightxl:BAAANQADCgEIAQAAAA==.',
Ko='Kokuten:BAAANQADCgQIBAABNQAECgcIDwABAAAAAA==.Koral:BAAANQADCgcICwAAAA==.',
Ku='Kungfuhealya:BAAANQAECgEIAQAAAA==.Kurog:BAAANQABCgEIAQAAAA==.',
La='Larrydale:BAAANQADCgYICwAAAA==.',
Le='Lea:BAAANQADCgcIBwABNQADCgYIBgABAAAAAA==.Legacyx:BAAANQADCgcIDAABNQAECgYICwABAAAAAA==.Leonardorich:BAAANQADCgYICgAAAA==.Leondis:BAAANQAECgcICwAAAA==.Lexifu:BAAANQAECgcIEgAAAA==.Lexipriest:BAAANQADCggIDwAAAA==.Leylla:BAAANQADCgIIAQABNQADCgcIDgABAAAAAA==.',
Li='Lightful:BAAANQAECgYICwAAAA==.Lilbro:BAAANQAECggIDQAAAA==.Lit:BAAANQADCgQIAwABNQAECgYICgABAAAAAA==.',
Lo='Lokii:BAAANQABCgMIAwAAAA==.',
Lu='Lumosmaxiima:BAAANQADCggIDgAAAA==.',
Ma='Madamme:BAAANQAECgUIBwAAAA==.Madkingzack:BAAANQADCgcICAAAAA==.Malistavias:BAAANQADCgYIDQAAAA==.Malliki:BAAANQAECgUIBQAAAA==.Marnangus:BAAANQAECgQIBQABNQADCgIIAgABAAAAAA==.Mathan:BAAANQAECgQIBQAAAA==.Maudib:BAAANQAECgYICAAAAA==.Mawile:BAAANQAECgEIAQAAAA==.',
Me='Meesha:BAAANQADCgcICwAAAA==.Melinarra:BAAANQADCgYIBgAAAA==.Messe:BAAANQAECgQIBwAAAA==.Methious:BAAANQADCgUIBQAAAA==.',
Mi='Milicious:BAAANQABCgEIAQAAAA==.',
Mo='Montu:BAAANQADCggICAAAAA==.Moogyver:BAAANQABCgQIBQAAAA==.Moonsguard:BAAANQADCgUICQAAAA==.Moovit:BAAANQADCgcICwAAAA==.Moth:BAAANQAECgIIAgAAAA==.',
Mu='Murre:BAAANQADCgYIBgAAAA==.',
Ne='Nekfury:BAAANQADCgUIBQAAAA==.Nepeta:BAAANQAECgEIAQAAAA==.Nevenel:BAAANQADCgMIAwAAAA==.',
Ni='Nivan:BAAANQADCgYIDQAAAA==.Niço:BAAANQAECgYIBwAAAA==.',
No='Nocturnall:BAAANQADCgQIBAAAAA==.Noicce:BAAANQAECgYIBgAAAA==.Noicewar:BAAANQAECgIIAgAAAA==.Notcrims:BAAANQAECggICQAAAA==.Notcrym:BAAANQADCgQIBQABNQAECggICQABAAAAAA==.',
Oa='Oakmoss:BAAANQAECgcIBgAAAA==.',
Or='Orcleave:BAAANQAECgIIAgAAAA==.Orwan:BAAANQAECgQIBAAAAA==.',
Ra='Ragecakes:BAAANQADCgYIBQAAAA==.Rakagar:BAAANQAECgMIBAAAAA==.',
Re='Reue:BAAANQAECggIEAAAAA==.',
Rh='Rhaegos:BAAANQADCgcICwAAAA==.',
Ri='Riggzz:BAAANQADCgcICQAAAA==.',
Ru='Ruuna:BAAANQABCgIIAgAAAA==.',
['Rí']='Rígg:BAAANQAECgEIAQAAAA==.',
Sa='Salla:BAAANQADCgYIBgAAAA==.',
Sc='Schmaximus:BAAANQADCgYIDAAAAA==.Scrapyjack:BAAANQAECgQIBAABNQAECgQIBgABAAAAAA==.',
Se='Senna:BAAANQADCgMIAwAAAA==.',
Sh='Shale:BAAANQAECgUIBwAAAA==.Shammytyme:BAAANQAECgYIDwAAAA==.Shampow:BAAANQADCgcIEwAAAA==.Shamyhagar:BAAANQADCgQIBAAAAA==.Shangtsung:BAAANQAFFAIIAgAAAA==.Sharaiya:BAAANQAECgIIAgAAAA==.Sharkmanfive:BAAANQAECgQIBAAAAA==.Shaure:BAAANQADCgIIAgAAAA==.Shearwater:BAAANQAECgQIBQAAAA==.',
Sk='Skirtero:BAAANQADCgYIBgAAAA==.',
So='Soltergeist:BAAANQAECgQIBQAAAA==.',
Sp='Spine:BAAANQADCggIFQAAAA==.Spougebob:BAAANQADCgMIBAAAAA==.',
Ss='Ssyd:BAAANQADCggICAAAAA==.',
St='Stormhoofs:BAAANQAECgcIEgAAAA==.',
Su='Subzone:BAAANQAECgQIBwAAAA==.Sumnabiscuit:BAAANQAECgcIDQAAAA==.Sunder:BAAANQADCgUIBQABNQAECgYICwABAAAAAA==.Sunmaster:BAAANQAECgIIAgAAAA==.',
Ta='Tackshi:BAAANQADCggIDAAAAA==.Tankinit:BAAANQADCgYIDgAAAA==.Tarea:BAAANQADCgQIBwAAAA==.',
Te='Tenzink:BAAANQAECgYICgAAAA==.',
Tf='Tflow:BAAANQAECgQIBwAAAA==.',
Th='Théworld:BAAANQABCgIIBAABNQADCgUICQABAAAAAA==.',
Ti='Tindranga:BAAANQADCgcIEgAAAA==.',
To='Tolbert:BAAANQADCgMIAwABNQADCgYIBgABAAAAAA==.Totemir:BAAANQAECgQIBAAAAA==.',
Tr='Trammatize:BAAANQAECgUIDAAAAA==.Triptamean:BAAANQADCgUIBQAAAA==.',
Tw='Twobladebray:BAAANQAECgQIBAAAAA==.',
Un='Unglaus:BAAANQAECgYIBgAAAA==.',
Uz='Uzington:BAAANQAECgcIDAAAAA==.',
Va='Valeta:BAAANQADCggIEwAAAA==.Vanessa:BAAANQAECgQIBAAAAA==.Vanillacream:BAAANQADCgMIAwAAAA==.Vayth:BAAANQADCggICAAAAA==.',
Ve='Velinieron:BAAANQAECgYICAAAAA==.Velithiri:BAAANQAECgQICAAAAA==.Vellash:BAAANQADCgEIAQAAAA==.',
Vi='Vilencia:BAAANQABCgQIBQAAAA==.Vince:BAAANQADCgUIBgAAAA==.Vinny:BAAANQABCgIIAgAAAA==.',
Vo='Vonulter:BAAANQADCggIFAAAAA==.',
Vy='Vylon:BAAANQAECgIIAwAAAA==.Vynlandis:BAAANQAECgEIAQAAAA==.Vyrel:BAAANQADCgYICgAAAA==.',
Wa='Warbezerker:BAAANQADCgcIBwAAAA==.',
We='Weenbean:BAAANQAECgIIAgAAAA==.',
Wh='Whakoopa:BAAANQADCggIDgAAAA==.Whispertree:BAAANQAECgQIBgAAAA==.',
Wi='Wilddonut:BAAANQADCgQIBAAAAA==.Wixypoo:BAAANQAECgEIAQAAAA==.',
Wo='Woodnzhood:BAAANQAECgEIAQAAAA==.',
Wr='Wrylah:BAAANQAECgMIBQAAAA==.',
Wy='Wyyn:BAAANQADCggIFQAAAA==.',
Xa='Xanboi:BAAANQAECgIIAgAAAA==.',
Ys='Ysar:BAAANQADCggIFQAAAA==.',
Yu='Yumzug:BAAANQADCgQIBAAAAA==.',
['Yô']='Yôshi:BAAANQAECggICAAAAA==.',
Ze='Zeebu:BAAANQAECgEIAQAAAA==.',
Zh='Zhilan:BAAANQAECgQIBgAAAA==.',
Zo='Zoko:BAAANQAECgEIAQAAAA==.',
Zu='Zurgadhunter:BAAANQAECgUICAAAAA==.Zuzuki:BAAANQADCgQIBAAAAA==.',
['Zú']='Zúz:BAAANQADCggIDgAAAA==.',
['Ða']='Ðalinor:BAAANQADCgIIAgAAAA==.',
['Øc']='Øctø:BAAANQABCgEIAQAAAA==.',
['Ør']='Øreø:BAAANQAECgYICAAAAA==.',
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
