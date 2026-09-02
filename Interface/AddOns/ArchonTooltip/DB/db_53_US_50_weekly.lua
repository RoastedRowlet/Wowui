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
local provider = {region='US',realm='CenarionCircle',name='US',type='weekly',zone=53,date='2026-09-01',data={Ac='Achelis:BAAANQADCgYIBgAAAA==.',
Ad='Adorian:BAAANQADCgYICgAAAA==.Adrrelle:BAAANQAECgcICwAAAA==.',
Ai='Ailaith:BAAANQADCggIDwAAAA==.',
Ak='Akariliselle:BAAANQAECgUICAAAAA==.',
Al='Alan:BAAANQADCgUIBQAAAA==.Alydrostage:BAAANQADCgcIDAAAAA==.Alystriaz:BAAANQADCgYIDAAAAA==.Alzheimerz:BAAANQAECgIIAgAAAA==.',
Am='Amaelalin:BAAANQADCggIDwAAAA==.Amatoria:BAAANQADCgEIAQAAAA==.',
An='Anaralyth:BAAANQADCgUICQABNQADCggIEwABAAAAAA==.Andaya:BAAANQAECgMIAwAAAA==.Andemeli:BAAANQADCgUICQAAAA==.Andrewrynn:BAAANQADCgEIAQAAAA==.',
Ar='Arandis:BAAANQADCggIDAAAAA==.Arcianna:BAAANQADCgYICgAAAA==.Arctica:BAAANQADCgYIBwAAAA==.Arctîc:BAAANQADCgYIDAAAAA==.Arjurn:BAAANQADCgYIBgAAAA==.Armpitbutter:BAAANQAECgEIAQAAAA==.Artymiss:BAAANQADCgcICgAAAA==.',
As='Astraleth:BAAANQADCggIEwAAAA==.',
Av='Avocat:BAAANQADCgQIBQAAAA==.',
Az='Azzinôth:BAAANQAECgQIBgAAAA==.',
Ba='Baldr:BAAANQADCgQIBAAAAA==.Balgar:BAAANQADCgcIDQAAAA==.Bammz:BAAANQAECgcICAAAAA==.Bastia:BAAANQADCgIIAgAAAA==.Baumstrum:BAAANQADCgcIDAAAAA==.',
Be='Beltbuckle:BAAANQADCgMIBAAAAA==.',
Bi='Bigtbag:BAAANQADCgUIBwAAAA==.',
Bl='Bloodrayvn:BAAANQADCgYIDAAAAA==.',
Bo='Borrkbuster:BAAANQADCgUICQAAAA==.',
Br='Brenri:BAAANQADCgYIBgAAAA==.Brughe:BAAANQADCggIDwAAAA==.',
Bu='Bubbleoseven:BAAANQADCggICgABNQAECgQIBQABAAAAAA==.Buttacutta:BAAANQADCgIIAgAAAA==.',
Ca='Cahoots:BAAANQAECgQIBAAAAA==.Caneste:BAAANQAECggIDAAAAA==.Catty:BAAANQADCggIDgAAAA==.Cayleynne:BAAANQAECgMIAwAAAA==.',
Ce='Celestyl:BAAANQADCgYIDAAAAA==.',
Ch='Chamadel:BAAANQADCgMIAwAAAA==.Cheapbeerz:BAAANQAECgEIAQAAAA==.Cheesemon:BAAANQADCgUIBQAAAA==.Chiforged:BAAANQADCgIIAgAAAA==.Chromstrasza:BAAANQADCgcICgAAAA==.',
Ci='Cinnia:BAAANQADCgYIDAAAAA==.',
Co='Comitus:BAAANQADCggIDwAAAA==.Conjarr:BAAANQAECgIIAgAAAA==.Cooters:BAAANQADCgQIBAAAAA==.Cougarsixsix:BAAANQADCgYICgAAAA==.',
Cr='Crabcarbs:BAAANQADCgUIBQAAAA==.Crimos:BAAANQAECgIIAgAAAA==.',
Cy='Cynnai:BAAANQAECgUICAAAAA==.',
Da='Daerthor:BAAANQADCgYICQAAAA==.Dalora:BAAANQADCggIDAAAAA==.Damaclies:BAAANQAECgQIBAAAAA==.Danashal:BAAANQADCgYICgAAAA==.Darksyn:BAAANQADCgQIBwAAAA==.Darthbane:BAAANQADCgYICgAAAA==.Darude:BAAANQADCgUIBQAAAA==.Dattiffany:BAAANQAECgEIAQAAAA==.',
De='Dekkan:BAAANQADCgYIDAAAAA==.Delphyne:BAAANQADCgYICwAAAA==.Denwarenji:BAAANQAECgIIAgAAAA==.Desmádre:BAAANQADCgMIAwAAAA==.',
Di='Diend:BAAANQADCggIDwAAAA==.Dissonanita:BAAANQADCgQIBAAAAA==.',
Dj='Djthelock:BAAANQADCgYIDAAAAA==.',
Do='Doctachris:BAAANQABCgQIBAAAAA==.',
Dr='Drbrad:BAAANQADCgYICAAAAA==.Dreadfists:BAAANQADCggIDAAAAA==.Druen:BAAANQADCgYICgAAAA==.Drunkenpo:BAAANQADCggIDgAAAA==.Drunkxmonk:BAAANQAECgIIAgAAAA==.Drïzl:BAEANQADCgQIBAABNQAECgUICQABAAAAAA==.',
Du='Duckchow:BAAANQADCgIIAgAAAA==.',
Dw='Dwarfoo:BAAANQADCgYICgAAAA==.Dweñde:BAAANQADCggIDgAAAA==.',
Ed='Eddrick:BAAANQADCgYIDAAAAA==.Edrid:BAAANQADCgYIBgABNQAECggIDgABAAAAAA==.',
En='Engo:BAAANQAECgIIAgAAAA==.',
Er='Eradrá:BAAANQAECgEIAgAAAA==.Eragon:BAAANQADCgcIDQAAAA==.',
Eu='Eureka:BAAANQADCgYIBwABNQADCggIDgABAAAAAA==.',
Ev='Evandra:BAAANQADCgcIDQAAAA==.Evanorah:BAAANQADCgYICwAAAA==.',
Fa='Faedeyeda:BAAANQADCgQIBgAAAA==.',
Fi='Fiddyone:BAAANQADCgUIBQABNQADCgcIBwABAAAAAA==.Figment:BAAANQADCgMIAwAAAA==.Firered:BAAANQADCgIIBAABNQAECgIIAwABAAAAAA==.',
Fo='Fodurzin:BAAANQADCgUIBwAAAA==.',
Fr='Frojio:BAAANQADCggIDgAAAA==.Frosten:BAAANQADCgUICQAAAA==.',
Fu='Furenio:BAAANQADCgYIBgAAAA==.',
Ga='Gabaghoul:BAAANQAECgEIAQAAAA==.Gaff:BAAANQADCgcIDQAAAA==.',
Gr='Grauth:BAAANQADCgUIBQAAAA==.Grido:BAAANQADCgIIAgAAAA==.',
Gu='Gulishdaniel:BAAANQADCgUIBgABNQAECggIDAABAAAAAA==.',
Ha='Hadin:BAAANQADCggIDwAAAA==.Halalnt:BAAANQADCgUIBQABNQADCgUIBwABAAAAAA==.Hamplanet:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.Haozhao:BAAANQADCggIDwAAAA==.Hazenpryde:BAAANQAECgMIAwAAAA==.',
He='Hearsay:BAAANQADCgMIAwABNQADCgYICgABAAAAAA==.Hecatamu:BAAANQADCgUIBQAAAA==.Hephaistian:BAAANQADCggIDgAAAA==.',
Ho='Holytoe:BAAANQADCgYIBgAAAA==.',
Hu='Hulud:BAAANQADCggICAAAAA==.',
Ie='Iechu:BAAANQADCgMIAwAAAA==.',
Il='Illidaz:BAAANQADCgUIBgAAAA==.',
Im='Immortál:BAAANQADCgYIBgAAAA==.',
In='Infinìte:BAAANQADCgYIBgAAAA==.Inic:BAAANQABCgIIAwAAAA==.',
Iv='Ivysnow:BAAANQADCggIDgAAAA==.',
Ja='Jaod:BAAANQADCgIIAgAAAA==.',
Jd='Jdghoul:BAAANQADCgYIBgAAAA==.',
Ji='Jindrac:BAAANQADCgcICgAAAA==.',
Ju='Juanfiles:BAAANQABCgIIAgAAAA==.',
['Jà']='Jàcaranda:BAAANQADCgIIAgAAAA==.',
Ka='Kahnrah:BAAANQADCgUICwAAAA==.Kalarae:BAAANQADCgcIDAAAAA==.Kaljeer:BAAANQADCggIDgAAAA==.Kalki:BAAANQADCgEIAQAAAA==.Kaltharion:BAAANQADCgEIAQAAAA==.Kaluren:BAAANQAECggIDgAAAA==.Kanade:BAAANQADCggICwAAAA==.Kantong:BAAANQADCggIDgAAAA==.Kapp:BAAANQADCgUIBQAAAA==.Karabar:BAAANQADCgYIBgAAAA==.Karnnagex:BAAANQADCgEIAQAAAA==.Karnnagexxl:BAAANQADCgYIBgAAAA==.Kazagol:BAAANQADCgYIBgAAAA==.',
Kh='Khamaracy:BAAANQADCgYICgAAAA==.',
Ko='Kojote:BAAANQABCgQIBwAAAA==.Kovalenko:BAAANQADCgYIDAAAAA==.',
Kr='Kryptus:BAAANQADCgYIDAAAAA==.',
Ku='Kurick:BAAANQADCgUICQAAAA==.',
La='Latte:BAAANQADCgUIBQAAAA==.',
Le='Lenity:BAAANQADCggIDgAAAA==.',
Lo='Lokinah:BAAANQADCgYICgAAAA==.',
Lu='Lucoryphus:BAAANQADCgYICwAAAA==.Lukeduke:BAAANQAECggICwAAAA==.Luketheduke:BAAANQAECgMIAwABNQAECggICwABAAAAAA==.Lunä:BAAANQAECgEIAQAAAA==.',
Ly='Lydia:BAAANQADCgcIDAAAAA==.Lyleath:BAAANQADCgQIBAAAAA==.',
Ma='Magictomb:BAAANQADCgcIDQAAAA==.Malifel:BAAANQADCgQIBwABNQADCgYIBgABAAAAAA==.Malstrom:BAAANQADCgYIBgAAAA==.Mandarin:BAAANQADCgYIDAAAAA==.Mararose:BAAANQABCgIIBAAAAA==.Marashades:BAAANQADCgcIDQAAAA==.',
Me='Melabrin:BAAANQADCggICgAAAA==.Mercia:BAAANQADCgYICgAAAA==.Mercý:BAAANQADCgMIAwAAAA==.Merekoma:BAAANQAECgEIAQAAAA==.',
Mi='Mingonashoba:BAAANQADCgYICwAAAA==.Misschris:BAAANQADCgcIDQAAAA==.Mistaricky:BAAANQADCgYIDAAAAA==.',
Mo='Moadeed:BAAANQADCgcICgAAAA==.Morphmious:BAAANQAECgIIAgAAAA==.Mortesque:BAAANQADCggIDgAAAA==.',
Mu='Muttblitzed:BAAANQADCgIIAgAAAA==.',
My='Myrrh:BAAANQAECgQIBAAAAA==.',
Na='Naidia:BAAANQADCgYIBgAAAA==.Nausican:BAAANQADCgEIAQAAAA==.',
Ne='Nelandra:BAAANQADCgYICgAAAA==.Nerazlyn:BAAANQADCgMIAwAAAA==.',
Ni='Nickflare:BAAANQABCgQIBAAAAA==.',
No='Nomahuata:BAAANQAECgEIAQAAAA==.',
Nu='Nufrus:BAAANQADCgYIDAAAAA==.',
Ny='Nyeli:BAAANQADCgQIBAABNQADCgYICgABAAAAAA==.Nyxi:BAAANQADCgMIAwAAAA==.',
['Né']='Néo:BAAANQADCgUIBQAAAA==.',
On='Onefiftyone:BAAANQADCgcIBwAAAA==.',
Pa='Palpetine:BAAANQADCgYIBwAAAA==.Paltator:BAAANQADCggICwAAAA==.Paradots:BAAANQAECgQIBQAAAA==.',
Pi='Pixpax:BAAANQADCgQIBQAAAA==.Pixystix:BAAANQADCgYICgAAAA==.',
Po='Pomortem:BAAANQADCgYICgAAAA==.Potsomancy:BAAANQAECgcICwAAAA==.',
Pr='Profian:BAAANQADCgcIBwAAAA==.',
Ra='Radioshack:BAAANQADCgUIBQABNQADCggIDQABAAAAAA==.Raivel:BAAANQADCgYICgAAAA==.Raneyth:BAAANQADCgUICQAAAA==.',
Re='Redwinetoast:BAAANQADCgcIDQAAAA==.Reno:BAAANQADCggIDgAAAA==.Reposess:BAAANQABCgQIBQAAAA==.Reshyk:BAAANQADCgYIDAAAAA==.',
Ri='Rickkrolled:BAAANQADCgMIAwAAAA==.Riordaa:BAAANQADCgcIDQAAAA==.',
Ro='Roboskritch:BAAANQADCgUIBwAAAA==.Rowene:BAAANQADCgIIAgAAAA==.',
Ru='Rumor:BAAANQADCgYICgAAAA==.Rurry:BAAANQAECggIDgAAAA==.',
Ry='Ryuuki:BAAANQAECgMIAwAAAA==.',
['Rï']='Rïzzler:BAEANQAECgUICQAAAA==.',
Sa='Safetysham:BAAANQABCgIIAgAAAA==.Salmoo:BAAANQADCgUIBQABNQADCgUIBwABAAAAAA==.Savonah:BAAANQADCgMIAwAAAA==.',
Sc='Scaledaddy:BAAANQADCgYIBgAAAA==.Scaryl:BAAANQADCgcIDQAAAA==.Schneè:BAAANQAECgQIBgAAAA==.Scoom:BAAANQAECggIDAAAAA==.Scourgespawn:BAAANQAECgcICwAAAA==.',
Se='Seikyo:BAAANQADCgYIBgAAAA==.Seilah:BAAANQADCgUIBwAAAA==.Selenë:BAAANQADCgYICQAAAA==.Serok:BAAANQAECgEIAQAAAA==.',
Sh='Shadowbox:BAAANQADCgMIAwAAAA==.Shadyaf:BAAANQADCgcIDQAAAA==.Shalis:BAAANQADCgcICgAAAA==.Sharivee:BAAANQADCgcIBwAAAA==.Shazamir:BAAANQADCgcIDAAAAA==.Shibui:BAAANQADCggIDwAAAA==.Shifthead:BAAANQAECgUIBgAAAA==.Shockazilla:BAAANQADCgUIBQAAAA==.',
Si='Silverhorn:BAAANQADCgYIBwAAAA==.',
Sk='Skoduh:BAAANQADCgQICAAAAA==.',
Sl='Slack:BAAANQADCgcIDQABNQADCggIDgABAAAAAA==.Sluggo:BAAANQAECggIDQAAAA==.',
Sm='Smokeü:BAAANQADCggICgAAAA==.',
St='Stonedalways:BAAANQADCgUIBQAAAA==.Stonytoni:BAAANQABCgIIAgAAAA==.',
Su='Sunfuri:BAAANQADCgYIBgAAAA==.Sus:BAAANQAECgcICgAAAA==.Susanoo:BAAANQADCgYIBgAAAA==.',
Ta='Taalia:BAAANQADCgYICgAAAA==.Talonas:BAAANQADCgEIAQAAAA==.Tarathor:BAAANQADCgYICgAAAA==.Tatortott:BAAANQADCgMIAwAAAA==.',
Te='Teknofarious:BAAANQAECgMIAwAAAA==.',
Th='Thesafe:BAAANQADCgcIDQAAAA==.Thickems:BAAANQAECgQIBgAAAA==.Thoralon:BAAANQADCgYIBgAAAA==.',
Ti='Tinkabella:BAAANQADCgYIBgAAAA==.',
To='Torrey:BAAANQADCgIIAgAAAA==.',
Tr='Trek:BAAANQADCgcIDQAAAA==.Trema:BAAANQADCgYICwAAAA==.Trix:BAAANQADCgYIBgAAAA==.',
Ty='Tyronos:BAAANQADCgcIBwAAAA==.',
Va='Vaeltharion:BAAANQADCgQIBAAAAA==.',
Vo='Voranth:BAAANQADCgYIDAAAAA==.',
Wa='Warenio:BAAANQADCggICAAAAA==.Warpsbulge:BAAANQAECgQIBAAAAA==.Wayawoman:BAAANQABCgIIAgABNQADCgcIDQABAAAAAA==.',
Wh='Whakan:BAAANQADCgMIAwABNQADCgYICwABAAAAAA==.',
Wo='Wolfos:BAAANQADCggIDwAAAA==.',
Wt='Wtfox:BAEANQADCggIDgAAAA==.',
Xa='Xalatos:BAAANQADCgMIAwAAAA==.',
Xi='Xinu:BAAANQADCgIIAgABNQADCgcIDAABAAAAAA==.',
Xo='Xolani:BAAANQAECgIIAgAAAA==.',
Ya='Yanakana:BAAANQADCgUICQAAAA==.',
Za='Zakeko:BAAANQADCgYICgAAAA==.',
Ze='Zenus:BAAANQADCgYIBgAAAA==.Zeusinator:BAAANQADCgIIAgAAAA==.',
Zi='Zinu:BAAANQADCgcIDAAAAA==.',
Zu='Zulfionn:BAAANQADCgYIBgAAAA==.',
['Áy']='Áyrá:BAAANQADCgYIDAAAAA==.',
['Øu']='Øuroboros:BAAANQAECgIIAwAAAA==.',
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
