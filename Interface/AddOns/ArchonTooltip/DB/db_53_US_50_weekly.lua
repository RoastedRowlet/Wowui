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

local lookup = {'Unknown-Unknown','Priest-Shadow','Evoker-Preservation','Paladin-Holy','Mage-Arcane','Paladin-Retribution',}
local provider = {region='US',realm='CenarionCircle',name='US',type='weekly',zone=53,date='2026-09-08',data={Ac='Aceieus:BAAANQABCgQIBAAAAA==.Achelis:BAAANQAECgEIAQAAAA==.',
Ad='Adorian:BAAANQADCgcIEQAAAA==.Adros:BAAANQADCggICAAAAA==.Adrrel:BAAANQADCgYIBgABNQAFFAEIAQABAAAAAA==.Adrrelle:BAAANQAFFAEIAQAAAA==.',
Ae='Aelfwine:BAAANQADCgcIBwAAAA==.',
Ai='Ailaith:BAAANQAECgEIAQAAAA==.',
Ak='Akariliselle:BAAANQAECgYIDwAAAA==.',
Al='Alan:BAAANQADCgUIBQAAAA==.Alcun:BAAANQADCgYIBgAAAA==.Alydrostage:BAAANQADCgcIEwAAAA==.Alystriaz:BAAANQADCgcIEwAAAA==.Alzheimerz:BAAANQAECgQIBgAAAA==.',
Am='Amaelalin:BAAANQAECgEIAQAAAA==.Amatoria:BAAANQADCggICQAAAA==.',
An='Anaralyth:BAAANQADCgUICQABNQADCggIFQABAAAAAA==.Andaya:BAAANQAECgUICAAAAA==.Andemeli:BAAANQADCgcIEAAAAA==.Andrewrynn:BAAANQADCgEIAQAAAA==.',
Ar='Arandis:BAAANQADCggIFAAAAA==.Arcianna:BAAANQADCggIEgAAAA==.Arctica:BAAANQADCgYIDQAAAA==.Arctîc:BAAANQADCggIFAAAAA==.Arjurn:BAAANQAECgEIAQAAAA==.Armpitbutter:BAAANQAECgEIAgAAAA==.Artymiss:BAAANQADCggIEQAAAA==.',
As='Astraleth:BAAANQADCggIFQAAAA==.',
Av='Avocat:BAAANQADCgUICQAAAA==.',
Az='Azzinôth:BAAANQAECgYIDAAAAA==.',
Ba='Baldr:BAAANQADCggIDAAAAA==.Balgar:BAAANQADCgcIDQAAAA==.Bammz:BAAANQAECgcIDAAAAA==.Bastia:BAAANQADCgYICAAAAA==.Baumstrum:BAAANQADCgcIDAAAAA==.',
Be='Beltbuckle:BAAANQADCgMIBAABNQADCgUICQABAAAAAA==.',
Bi='Bigtbag:BAAANQADCgUIBwAAAA==.',
Bl='Bloodrayvn:BAAANQADCgcIDQAAAA==.',
Bo='Borrkbuster:BAAANQADCgcIEAAAAA==.',
Br='Brenri:BAAANQADCgYIBgAAAA==.Brughe:BAAANQADCggIFwAAAA==.Brywynn:BAAANQADCgYIBgABNQADCggIDAABAAAAAA==.',
Bu='Bubbleoseven:BAAANQAECgIIAgABNQAECgcIDAABAAAAAA==.Buttacutta:BAAANQADCgUIBwAAAA==.',
Ca='Cahoots:BAAANQAECgYICgAAAA==.Caneste:BAABNQAECoEWAAICAAkJLBy/BQAZAwACAAkJLBy/BQAZAwAAAA==.Capela:BAAANQABCgQIBAAAAA==.Catty:BAAANQAECgEIAQAAAA==.Cayleynne:BAAANQAECgUICAAAAA==.',
Ce='Celestyl:BAAANQADCggIFAAAAA==.',
Ch='Chamadel:BAAANQADCgMIAwAAAA==.Cheapbeerz:BAAANQAECgEIAQAAAA==.Cheesemon:BAAANQADCgUIBQAAAA==.Chiforged:BAAANQADCgcICgAAAA==.Chromstrasza:BAAANQAECgMIAwAAAA==.',
Ci='Cinnia:BAAANQADCgcIEwAAAA==.',
Co='Comitus:BAAANQAECgEIAQAAAA==.Conjarr:BAAANQAECgQIBgAAAA==.Cooters:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Cougarsixsix:BAAANQADCgcIEQAAAA==.',
Cr='Crabcarbs:BAAANQADCgUICQAAAA==.Crimos:BAAANQAECgQIBgAAAA==.',
Cy='Cynnai:BAAANQAECgcIDgAAAA==.',
Da='Daerthor:BAAANQADCgYICQAAAA==.Dalora:BAAANQADCggIDAAAAA==.Damaclies:BAAANQAECgQIBQAAAA==.Danashal:BAAANQADCggIEgAAAA==.Dansen:BAAANQADCgEIAQAAAA==.Darksyn:BAAANQADCgcIDgAAAA==.Darthbane:BAAANQADCgcIEQAAAA==.Darude:BAAANQADCgUIBQABNQADCgUICQABAAAAAA==.Dattiffany:BAAANQAECgIIAwAAAA==.',
De='Dekkan:BAAANQADCgYIDAAAAA==.Delphyne:BAAANQADCggIEwAAAA==.Denwarenji:BAAANQAECgYIBwAAAA==.Desmádre:BAAANQADCggICwAAAA==.',
Di='Diend:BAAANQAECgEIAQAAAA==.Dissonanita:BAAANQADCgUICQAAAA==.',
Dj='Djthelock:BAAANQADCggIFAAAAA==.',
Do='Doctachris:BAAANQABCgUICQAAAA==.',
Dr='Drbrad:BAAANQADCgcICgAAAA==.Dreadfists:BAAANQAECgIIAgAAAA==.Druen:BAAANQADCggIEgAAAA==.Drunkenpo:BAAANQAECgEIAQAAAA==.Drunkxmonk:BAAANQAECgIIAwAAAA==.Drïzl:BAEANQADCggIDAABNQAECgcIEAABAAAAAA==.',
Du='Duckchow:BAAANQADCgIIAgAAAA==.',
Dw='Dwarfoo:BAAANQADCgYICgAAAA==.Dweñde:BAAANQAECgIIAgAAAA==.',
Ec='Ecthelion:BAAANQADCgYIBgAAAA==.',
Ed='Eddrick:BAAANQADCggIFAAAAA==.Edrid:BAAANQAECgUIBQABNQAECgkJGAADAFMiAA==.',
En='Engo:BAAANQAECgQIBgAAAA==.',
Er='Eradrá:BAAANQAECgIIBAAAAA==.Eragon:BAAANQADCgcIEgAAAA==.',
Eu='Eureka:BAAANQADCggIDwABNQAECgIIAgABAAAAAA==.',
Ev='Evandra:BAAANQADCgcIEgAAAA==.Evanorah:BAAANQADCggIDQAAAA==.',
Fa='Faedeyeda:BAAANQADCgcIDQAAAA==.',
Fe='Ferheim:BAAANQADCgQIBAAAAA==.',
Fi='Fiddyone:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Figment:BAAANQADCgMIAwAAAA==.Firered:BAAANQADCgIIBAABNQAECgIIBAABAAAAAA==.Fizzfuzzbttm:BAAANQAECgEIAQAAAA==.',
Fo='Fodurzin:BAAANQADCggIDwAAAA==.',
Fr='Frojio:BAAANQAECgEIAQAAAA==.Frosten:BAAANQADCgYIDwAAAA==.',
Fu='Furenio:BAAANQADCgYIBgAAAA==.',
Ga='Gabaghoul:BAAANQAECgIIAwAAAA==.Gaff:BAAANQAECgIIAgAAAA==.',
Gr='Grauth:BAAANQADCgUICgAAAA==.Grido:BAAANQADCgIIAgAAAA==.',
Gu='Gulishdaniel:BAAANQADCgcIDQABNQAECgkJFgACACwcAA==.',
Ha='Hadin:BAAANQADCggIFwAAAA==.Halalnt:BAAANQADCgUIBQABNQADCgcIBwABAAAAAA==.Hamplanet:BAAANQAECgEIAQABNQAFFAEIAQABAAAAAA==.Hamster:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Haozhao:BAAANQAECgEIAQAAAA==.Hazenpryde:BAAANQAECgQIBwAAAA==.',
He='Hearsay:BAAANQADCgYIBwABNQADCggIEgABAAAAAA==.Hecatamu:BAAANQADCgUIBQAAAA==.Hephaistian:BAAANQAECgMIAwAAAA==.',
Ho='Holytoe:BAAANQADCgYIBgAAAA==.',
Hu='Hulud:BAAANQAECgEIAQAAAA==.',
Hy='Hysgar:BAAANQABCgYICAABNQADCgcIEAABAAAAAA==.',
Ie='Iechu:BAAANQADCgUICgAAAA==.',
Il='Illidaz:BAAANQADCgUIBgAAAA==.',
Im='Immortál:BAAANQADCggIDgAAAA==.',
In='Infinìte:BAAANQAECgEIAQAAAA==.Inic:BAAANQABCgQIBQAAAA==.',
Iv='Ivysnow:BAAANQAECgIIAgAAAA==.',
Ja='Jackfruit:BAAANQADCgUIBQAAAA==.Jaod:BAAANQADCgQIBgAAAA==.',
Jd='Jdghoul:BAAANQADCgYIBgAAAA==.',
Ji='Jindrac:BAAANQADCggIEQAAAA==.Jitsuru:BAAANQADCggICAAAAA==.',
Ju='Juanfiles:BAAANQABCgIIAgAAAA==.',
['Jà']='Jàcaranda:BAAANQADCgMIAwAAAA==.',
Ka='Kahnrah:BAAANQADCgcIFQAAAA==.Kalarae:BAAANQADCgcIDAAAAA==.Kaljeer:BAAANQAECgIIAgAAAA==.Kalki:BAAANQADCgEIAQAAAA==.Kaltharion:BAAANQAECgEIAQAAAA==.Kaluren:BAABNQAECoEYAAIEAAkJiyYMAAAEBAAEAAkJiyYMAAAEBAAAAA==.Kalurion:BAAANQADCgIIAgAAAA==.Kanade:BAAANQAECgEIAQAAAA==.Kantong:BAAANQAECgQIBgAAAA==.Kapp:BAAANQADCggIDQAAAA==.Karabar:BAAANQAECgEIAQAAAA==.Karnnaged:BAAANQADCggICwAAAA==.Karnnagex:BAAANQADCgEIAQAAAA==.Karnnagexxl:BAAANQAECgEIAQAAAA==.Kayiku:BAAANQADCgYIBgAAAA==.Kazagol:BAAANQAECgEIAQAAAA==.',
Kh='Khamaracy:BAAANQADCgcIEQAAAA==.',
Ko='Kojote:BAAANQADCgIIAgAAAA==.Kovalenko:BAAANQADCggIFAAAAA==.',
Kr='Kryptus:BAAANQADCgcIEwAAAA==.',
Ku='Kurick:BAAANQADCgcIEAAAAA==.',
Ky='Kyngizzard:BAAANQADCgcIBwAAAA==.',
La='Latte:BAAANQADCgcIDAAAAA==.',
Le='Lenity:BAAANQAECgIIAgAAAA==.',
Lo='Lokinah:BAAANQADCgcIEQAAAA==.',
Lu='Lucoryphus:BAAANQADCggIDQAAAA==.Lukeduke:BAAANQAFFAIIAgAAAA==.Luketheduke:BAAANQAECgMIAwABNQAFFAIIAgABAAAAAA==.Lunä:BAAANQAECgUIBgAAAA==.',
Ly='Lydia:BAAANQAECgIIAgAAAA==.Lyleath:BAAANQADCgQIBAAAAA==.',
Ma='Magickeys:BAAANQABCgEIAQAAAA==.Magictomb:BAAANQAECgIIAgAAAA==.Malifel:BAAANQADCggIDwAAAA==.Malstrom:BAAANQADCggIDgABNQADCggIDwABAAAAAA==.Mandarin:BAAANQADCggIFAAAAA==.Mararose:BAAANQABCgIIBAAAAA==.Marashades:BAAANQADCgcIDQAAAA==.',
Me='Melabrin:BAAANQAECgEIAQAAAA==.Mercia:BAAANQADCggIEgAAAA==.Mercý:BAAANQADCgQIBAAAAA==.Merekoma:BAAANQAECgEIAQAAAA==.',
Mi='Mingonashoba:BAAANQADCgcIEgAAAA==.Misschris:BAAANQADCgcIEgAAAA==.Mistaricky:BAAANQADCgYIEQAAAA==.',
Mo='Moadeed:BAAANQADCggIEQAAAA==.Morphmious:BAAANQAECgQIBgAAAA==.Mortesque:BAAANQAECgIIAgAAAA==.',
Mu='Muttblitzed:BAAANQADCgcICQAAAA==.',
My='Myrrh:BAAANQAECgQICAAAAA==.',
['Mô']='Môses:BAAANQADCgIIAgAAAA==.',
Na='Naidia:BAAANQADCgYIDAAAAA==.Nausican:BAAANQADCgEIAQAAAA==.',
Ne='Nelandra:BAAANQADCgcIEQAAAA==.Nerazlyn:BAAANQADCgMIAwAAAA==.',
Ni='Nickflare:BAAANQABCgQIBAAAAA==.',
No='Nomahuata:BAAANQAECgQIBQAAAA==.',
Nu='Nufrus:BAAANQADCgYIEQAAAA==.',
Ny='Nyeli:BAAANQADCggIDAAAAA==.Nyxi:BAAANQADCggICwAAAA==.',
['Né']='Néo:BAAANQADCggIDQAAAA==.',
On='Onefiftyone:BAAANQAECgEIAQAAAA==.',
Pa='Palochka:BAAANQADCgYIBgAAAA==.Palpetine:BAAANQADCgYICwAAAA==.Paltator:BAAANQAECgIIAgAAAA==.Paradots:BAAANQAECgcIDAAAAA==.Paranitis:BAAANQADCggICAAAAA==.Paraparaboom:BAAANQAECgEIAQAAAA==.',
Ph='Pheroth:BAAANQADCgYIBgABNQADCgcIDgABAAAAAA==.',
Pi='Pixpax:BAAANQADCgQIBQAAAA==.Pixyofdeath:BAAANQADCggIAwAAAA==.Pixystix:BAAANQADCgcIEQABNQADCggIAwABAAAAAA==.',
Po='Pomortem:BAAANQADCgcIEQAAAA==.Potsomancy:BAAANQAECggIEwAAAA==.',
Pr='Profian:BAAANQADCgcIBwAAAA==.',
Ra='Radioshack:BAAANQADCgUIBQABNQADCggIEQABAAAAAA==.Raivel:BAAANQADCgcIEQABNQADCggIDAABAAAAAA==.Raneyth:BAAANQADCgYIDwAAAA==.',
Re='Redwinetoast:BAAANQADCgcIEgAAAA==.Reno:BAAANQAECgIIAgAAAA==.Reposess:BAAANQABCgQIBwAAAA==.Reshyk:BAAANQADCgYIEQAAAA==.',
Ri='Rickkrolled:BAAANQAECgEIAQAAAA==.Riordaa:BAAANQADCgcIEgAAAA==.',
Ro='Roboskritch:BAAANQADCgUIBwABNQADCgUICQABAAAAAA==.Rowene:BAAANQADCgQIBgAAAA==.',
Ru='Rumor:BAAANQADCggIEgAAAA==.Rurry:BAABNQAECoEYAAIDAAkJUyI+AQCCAwADAAkJUyI+AQCCAwAAAA==.',
Ry='Ryuuki:BAAANQAECgMIBAAAAA==.',
['Rï']='Rïzzler:BAEANQAECgcIEAAAAA==.',
Sa='Safetysham:BAAANQADCgQIBwAAAA==.Saffia:BAAANQABCgQIAwAAAA==.Salmoo:BAAANQADCgYIBgABNQADCggIDwABAAAAAA==.Saltytator:BAAANQADCgYIBgAAAA==.Savonah:BAAANQADCgYICQAAAA==.',
Sc='Scaledaddy:BAAANQAECgEIAQAAAA==.Scaryl:BAAANQADCggIFQAAAA==.Schneè:BAAANQAECgUICwAAAA==.Scoom:BAABNQAECoEWAAIFAAkJ3iFBCQB1AwAFAAkJ3iFBCQB1AwAAAA==.Scourgespawn:BAAANQAFFAEIAQAAAA==.',
Se='Seikyo:BAAANQAECgEIAQAAAA==.Seilah:BAAANQADCgUIBwABNQADCgcIBwABAAAAAA==.Selenë:BAAANQAECgIIAgAAAA==.Serok:BAAANQAECgIIBAAAAA==.',
Sh='Shadowbox:BAAANQADCgMIAwAAAA==.Shadyaf:BAAANQADCggIFQAAAA==.Shalis:BAAANQADCgcIDwAAAA==.Sharivee:BAAANQADCgcIDAAAAA==.Shazamir:BAAANQADCgcIEwAAAA==.Shibui:BAAANQAECgEIAQAAAA==.Shifthead:BAAANQAECgcIDQAAAA==.Shockazilla:BAAANQAECgEIAQAAAA==.',
Si='Silverhorn:BAAANQAECgEIAQAAAA==.',
Sk='Skoduh:BAAANQADCgcIDwAAAA==.',
Sl='Slack:BAAANQAECgIIAgABNQAECgIIAgABAAAAAA==.Sluggo:BAABNQAECoEXAAIGAAkJZhtbEgC7AgAGAAkJZhtbEgC7AgAAAA==.',
Sm='Smokeü:BAAANQADCggICgAAAA==.',
So='Solinaara:BAAANQABCgQIBAAAAA==.',
St='Stonedalways:BAAANQADCggIDQAAAA==.Stonytoni:BAAANQABCgQIBAAAAA==.',
Su='Sunfuri:BAAANQADCgYICQAAAA==.Sus:BAAANQAFFAEIAQAAAA==.Susanoo:BAAANQADCgYIBgAAAA==.',
Ta='Taalia:BAAANQADCgcIEQAAAA==.Talonas:BAAANQAECgEIAQAAAA==.Tarathor:BAAANQADCgcIEQAAAA==.Tatortott:BAAANQADCgMIAwAAAA==.',
Te='Teknofarious:BAAANQAECgUICAAAAA==.',
Th='Thesafe:BAAANQADCgcIEgAAAA==.Thevin:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Thialia:BAAANQADCgcICgABNQAECgEIAQABAAAAAA==.Thickems:BAAANQAECgUICgAAAA==.Thoralon:BAAANQADCgYIBgAAAA==.',
Ti='Tinkabella:BAAANQAECgEIAQAAAA==.',
To='Torrey:BAAANQADCgIIAgAAAA==.',
Tr='Trek:BAAANQADCgcIEgAAAA==.Trema:BAAANQADCgcIEgAAAA==.Trix:BAAANQADCggIDgAAAA==.',
Ts='Tserendelgor:BAAANQADCgMIAwAAAA==.',
Ty='Tyronos:BAAANQADCgcIDAAAAA==.',
Va='Vaeltharion:BAAANQADCgYICQAAAA==.Vas:BAAANQADCgEIAQAAAA==.',
Ve='Verdandi:BAAANQADCgYIBgAAAA==.Vevicenth:BAAANQADCggICAAAAA==.',
Vo='Voranth:BAAANQADCggIFAAAAA==.',
Wa='Warenio:BAAANQAECgEIAQAAAA==.Warpsbulge:BAAANQAFFAEIAQAAAA==.Wayawoman:BAAANQABCgIIAgABNQADCgcIEgABAAAAAA==.',
Wh='Whakan:BAAANQADCgYICQABNQADCggIDQABAAAAAA==.',
Wo='Wolfos:BAAANQAECgIIAgAAAA==.',
Wt='Wtfox:BAEANQADCggIDgAAAA==.',
Xa='Xalatos:BAAANQADCgcICgAAAA==.Xalfein:BAAANQADCgYIBgAAAA==.',
Xi='Xinu:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.',
Xo='Xolani:BAAANQAECgIIAgAAAA==.',
Ya='Yanakana:BAAANQADCgYIDwAAAA==.',
Za='Zakeko:BAAANQADCgcIEQAAAA==.',
Ze='Zenus:BAAANQADCggIDgAAAA==.Zesty:BAAANQADCgIIAgAAAA==.Zeusinator:BAAANQADCgIIAgAAAA==.',
Zf='Zfatpanda:BAAANQADCggICAAAAA==.',
Zi='Zinu:BAAANQAECgEIAQAAAA==.',
Zu='Zulfionn:BAAANQADCgYIBgAAAA==.',
['Áy']='Áyrá:BAAANQADCgYIEQAAAA==.',
['Øu']='Øuroboros:BAAANQAECgIIBAAAAA==.',
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
