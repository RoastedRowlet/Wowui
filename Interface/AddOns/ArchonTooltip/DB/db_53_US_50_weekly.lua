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

local lookup = {'Hunter-Marksmanship','Hunter-BeastMastery','Unknown-Unknown','Priest-Shadow','Warrior-Arms','Evoker-Preservation','Paladin-Holy','Paladin-Retribution','Warrior-Protection','Mage-Arcane','DeathKnight-Frost','DeathKnight-Unholy','Druid-Feral','Druid-Balance','DemonHunter-Havoc','DemonHunter-Vengeance',}
local provider = {region='US',realm='CenarionCircle',name='US',type='weekly',zone=53,date='2026-09-15',data={Ac='Aceieus:BAAANQABCgUIBQAAAA==.Achelis:BAAANQAECgQIBQAAAA==.',
Ad='Adorian:BAAANQADCggIEgAAAA==.Adros:BAAANQADCggICAAAAA==.Adrrel:BAAANQADCgYIBgABNQAECgkJGwABAPoXAA==.Adrrelle:BAABNQAECoEbAAMBAAkJ+hcbFwAcAgABAAgJ7hQbFwAcAgACAAIJjSW/nQDEAAAAAA==.',
Ae='Aelfwine:BAAANQAECgEIAQAAAA==.',
Ai='Ailaith:BAAANQAECgIIAwAAAA==.',
Ak='Akariliselle:BAAANQAECgYIEwAAAA==.',
Al='Alan:BAAANQADCgcICgAAAA==.Alcun:BAAANQADCgYIBgAAAA==.Alydrostage:BAAANQADCggIGgAAAA==.Alystriaz:BAAANQAECgIIAgAAAA==.Alzheimerz:BAAANQAECgQICgAAAA==.',
Am='Amaelalin:BAAANQAECgIIAwAAAA==.Amatoria:BAAANQADCggICwAAAA==.',
An='Anaralyth:BAAANQADCgUICQABNQAECgMIBgADAAAAAA==.Andaya:BAAANQAECgYIDgAAAA==.Andemeli:BAAANQADCgcIFwAAAA==.Andrewrynn:BAAANQADCgEIAQAAAA==.Annarah:BAAANQADCgUIBQAAAA==.',
Ar='Arandis:BAAANQAECgEIAQAAAA==.Arcianna:BAAANQAECgMIAwAAAA==.Arctica:BAAANQAECgEIAQAAAA==.Arctîc:BAAANQAECgEIAgAAAA==.Arjurn:BAAANQAECgQIBQAAAA==.Armpitbutter:BAAANQAECgQIBgAAAA==.Artymiss:BAAANQAECgEIAQAAAA==.',
As='Astraleth:BAAANQAECgMIBgAAAA==.',
Av='Avocat:BAAANQAECgQIBAAAAA==.',
Ay='Ayorana:BAAANQADCgYIBgAAAA==.',
Az='Azzinôth:BAAANQAECgcIEgAAAA==.',
Ba='Baldr:BAAANQAECgIIAgAAAA==.Balgar:BAAANQADCggIFQAAAA==.Bammz:BAAANQAECgcIDQAAAA==.Bastia:BAAANQADCgYIDAAAAA==.Baumstrum:BAAANQADCgcIDAAAAA==.',
Be='Beltbuckle:BAAANQADCgMIBAABNQADCgUICQADAAAAAA==.Benbeckman:BAAANQADCgQIBAAAAA==.',
Bi='Bigtbag:BAAANQADCgUIBwAAAA==.',
Bl='Bloodrayvn:BAAANQAECgEIAQAAAA==.',
Bo='Borrkbuster:BAAANQADCgcIFwAAAA==.',
Br='Brenri:BAAANQAECgEIAQAAAA==.Brewtality:BAAANQAECgQIBAABNQAECgcIEwADAAAAAA==.Brudanature:BAAANQADCgUIBQABNQADCggIGQADAAAAAA==.Brughe:BAAANQADCggIFwAAAA==.Brywynn:BAAANQADCgYIBgABNQADCggIFAADAAAAAA==.',
Bu='Bubbleoseven:BAAANQAECgMIAwABNQAECgcIEwADAAAAAA==.Burnbabyburn:BAAANQADCgYIBgAAAA==.Buttacutta:BAAANQADCgUIBwAAAA==.',
Ca='Cahoots:BAAANQAECgcIEAAAAA==.Caneste:BAABNQAECoEZAAIEAAkJZR2PCAAFAwAEAAkJZR2PCAAFAwAAAA==.Capela:BAAANQABCgQIBAAAAA==.Catty:BAAANQAECgQIBQAAAA==.Cayleynne:BAAANQAECgUICQAAAA==.',
Ce='Celestyl:BAAANQAECgEIAQAAAA==.',
Ch='Chadman:BAAANQADCgYIBgAAAA==.Chamadel:BAAANQADCgMIAwAAAA==.Cheapbeerz:BAAANQAECgUIBgAAAA==.Cheesemon:BAAANQADCgUIBQAAAA==.Chiforged:BAAANQADCgcIDwAAAA==.Chromstrasza:BAAANQAECgQIBwAAAA==.',
Ci='Cinnia:BAAANQAECgMIAwAAAA==.',
Co='Comitus:BAAANQAECgEIAQAAAA==.Conjarr:BAAANQAECgUICwAAAA==.Cooters:BAAANQADCgQIBAABNQAECgQIBQADAAAAAA==.Cougarsixsix:BAAANQADCggIGQAAAA==.',
Cr='Crabcarbs:BAAANQADCgUICQAAAA==.Crimos:BAAANQAECgUICwAAAA==.Crypticcurse:BAAANQADCgYIDAAAAA==.',
Cy='Cynnai:BAABNQAECoEUAAIFAAcJpRnJPQA/AgAFAAcJpRnJPQA/AgAAAA==.',
Da='Daerthor:BAAANQADCgYICQAAAA==.Dalora:BAAANQADCggIDAAAAA==.Damaclies:BAAANQAECgQICQAAAA==.Danashal:BAAANQAECgIIAgAAAA==.Dangerranger:BAAANQAECgIIAgAAAA==.Dansen:BAAANQADCgUIBQAAAA==.Darksyn:BAAANQADCggIFgAAAA==.Darrth:BAAANQAECgMIAwAAAA==.Darthbane:BAAANQADCggIGgAAAA==.Darthjareth:BAAANQADCgUIBQAAAA==.Darude:BAAANQADCgUIBQABNQADCgUICQADAAAAAA==.Dattiffany:BAAANQAECgIIAwAAAA==.',
De='Dekkan:BAAANQADCgYIDAAAAA==.Delphyne:BAAANQADCggIEwAAAA==.Denasel:BAAANQADCgcIBwAAAA==.Denwarenji:BAAANQAECgYICgAAAA==.Desmádre:BAAANQADCggIEwAAAA==.',
Di='Diend:BAAANQAECgIIAwAAAA==.Dissonanita:BAAANQADCgUICQAAAA==.',
Dj='Djthelock:BAAANQAECgEIAQAAAA==.',
Do='Doctachris:BAAANQABCgUICQAAAA==.',
Dr='Drbrad:BAAANQADCggIEAAAAA==.Dreadfists:BAAANQAECgIIBAAAAA==.Druen:BAAANQAECgMIAwAAAA==.Drunkenpo:BAAANQAECgIIAwAAAA==.Drunkxdemon:BAAANQADCgYIBgAAAA==.Drunkxmonk:BAAANQAECgYIBwAAAA==.Drïzl:BAEANQAECgIIAgABNQAECggIEwADAAAAAA==.',
Du='Duckchow:BAAANQADCgIIAgAAAA==.',
Dw='Dwarfoo:BAAANQADCggIEgAAAA==.Dweñde:BAAANQAECgQIBgAAAA==.',
Eb='Ebonfang:BAAANQABCgEIAQAAAA==.',
Ec='Ecthelion:BAAANQADCgYIBgAAAA==.',
Ed='Eddrick:BAAANQAECgEIAQAAAA==.Edrid:BAAANQAECgYICwABNQAFFAMIBQAGALsWAA==.',
En='Engo:BAAANQAECgUICwAAAA==.',
Er='Eradrá:BAAANQAECgIIBAAAAA==.Eragon:BAAANQADCggIGQAAAA==.',
Et='Ethaan:BAAANQABCgQIBAAAAA==.',
Eu='Eureka:BAAANQAECggICAAAAA==.',
Ev='Evandra:BAAANQADCggIGgAAAA==.Evanorah:BAAANQAECgMIAwAAAA==.',
Fa='Faedeyeda:BAAANQADCggIEgAAAA==.',
Fe='Ferheim:BAAANQADCgQIBAAAAA==.Ferhold:BAAANQADCgIIAgAAAA==.',
Fi='Fiddyone:BAAANQADCgUIBQABNQAECgEIAQADAAAAAA==.Figment:BAAANQADCgMIAwAAAA==.Firered:BAAANQADCgIIBAABNQAECgMIBAADAAAAAA==.Fizzfuzzbttm:BAAANQAECgEIAQAAAA==.',
Fo='Fodurzin:BAAANQAECgEIAQAAAA==.',
Fr='Frojio:BAAANQAECgQIBQAAAA==.Frosten:BAAANQADCgYIFQAAAA==.',
Fu='Furenio:BAAANQADCgYIBgAAAA==.',
Ga='Gabaghoul:BAAANQAECgIIAwAAAA==.Gaff:BAAANQAECgMIBQAAAA==.',
Gr='Grauth:BAAANQADCgUICgAAAA==.Grido:BAAANQADCgIIAgAAAA==.',
Gu='Gulishdaniel:BAAANQADCgcIDQABNQAECgkJGQAEAGUdAA==.',
Ha='Hadin:BAAANQAECgIIAgAAAA==.Halalnt:BAAANQADCgUIBQABNQAECgQICAADAAAAAA==.Hamplanet:BAAANQAECgEIAQABNQAFFAEIAQADAAAAAA==.Hamster:BAAANQADCgYIBgABNQAECgMIBQADAAAAAA==.Haozhao:BAAANQAECgIIAwAAAA==.Hazenpryde:BAAANQAECgYIDQAAAA==.',
He='Hearsay:BAAANQADCgYIDAABNQADCggIGgADAAAAAA==.Hecatamu:BAAANQADCgUIBQAAAA==.Hephaistian:BAAANQAECgMIAwAAAA==.',
Ho='Holytoe:BAAANQADCgYIBgAAAA==.',
Hu='Hulud:BAAANQAECgIIAwAAAA==.',
Hy='Hysgar:BAAANQAECgEIAQAAAA==.',
Ie='Iechu:BAAANQADCgUICgAAAA==.',
Il='Illidaz:BAAANQADCgUIBgAAAA==.',
Im='Immortál:BAAANQAECgQIBAAAAA==.',
In='Indraz:BAAANQADCgQIBAAAAA==.Infinìte:BAAANQAECgQIBQAAAA==.Inic:BAAANQABCgQIBQAAAA==.',
Iv='Ivysnow:BAAANQAECgIIAgAAAA==.',
Ja='Jackfruit:BAAANQAECgEIAQAAAA==.Jaod:BAAANQADCgUICwAAAA==.',
Jd='Jdghoul:BAAANQADCgYIBgAAAA==.',
Ji='Jindrac:BAAANQADCggIEQAAAA==.Jitsuru:BAAANQADCggICgAAAA==.',
Ju='Juanfiles:BAAANQABCgMIAwAAAA==.',
['Jà']='Jàcaranda:BAAANQADCgMIAwAAAA==.',
Ka='Kahnrah:BAAANQADCgcIHQAAAA==.Kalarae:BAAANQADCgcIDAAAAA==.Kaljeer:BAAANQAECgMIBQAAAA==.Kalki:BAAANQADCgEIAQAAAA==.Kaltharion:BAAANQAECgEIAQAAAA==.Kaluren:BAACNQAFFIEFAAIHAAMJXx6QBQAfAQAHAAMJXx6QBQAfAQA1AAQKgSAAAwcACQmtJiEAAP4DAAcACQmtJiEAAP4DAAgABQnfHBJVAKQBAAAA.Kalurion:BAAANQADCgIIAgAAAA==.Kanade:BAAANQAECgIIAwAAAA==.Kanishi:BAAANQABCgYIBgAAAA==.Kantong:BAAANQAECgQIBgAAAA==.Kapp:BAAANQADCggIFQAAAA==.Karabar:BAAANQAECgQIBQAAAA==.Karnnaged:BAAANQAECgMIAwAAAA==.Karnnagex:BAAANQADCgEIAQABNQAECgMIAwADAAAAAA==.Karnnagexxl:BAAANQAECgEIAQABNQAECgMIAwADAAAAAA==.Kayiku:BAAANQADCgYIBgAAAA==.Kazagol:BAAANQAECgQIBQAAAA==.',
Kh='Khamaracy:BAAANQADCggIGQAAAA==.',
Ko='Kojote:BAAANQADCgIIAgAAAA==.Kovalenko:BAAANQAECgEIAQAAAA==.',
Kr='Kryptus:BAAANQAECgMIAwAAAA==.',
Ku='Kurick:BAAANQADCgcIFwABNQAECgEIAQADAAAAAA==.Kurshak:BAAANQAECgQIBAABNQAECgYICgADAAAAAA==.',
Ky='Kyngizzard:BAAANQAECgIIAgABNQAECgQICAADAAAAAA==.',
La='Latte:BAAANQADCggIFAAAAA==.',
Le='Lenity:BAAANQAECgIIBAAAAA==.',
Lo='Loan:BAAANQADCgYIBgABNQAECgMIBQADAAAAAA==.Lockstar:BAAANQADCgYIBgAAAA==.Lokinah:BAAANQADCgcIFwAAAA==.',
Lu='Lucoryphus:BAAANQAECgMIAwAAAA==.Lukeduke:BAACNQAFFIEFAAIJAAMJAR/ZAAAeAQAJAAMJAR/ZAAAeAQA1AAQKgRwAAgkACQl0IjwBAIADAAkACQl0IjwBAIADAAAA.Luketheduke:BAAANQAECgMIAwABNQAFFAMIBQAJAAEfAA==.Lunä:BAAANQAECgUIBwAAAA==.',
Ly='Lydia:BAAANQAECgQIBgAAAA==.Lyleath:BAAANQADCgQIBAAAAA==.',
Ma='Magickeys:BAAANQADCgMIAwAAAA==.Malifel:BAAANQADCggIFQABNQADCggIFgADAAAAAA==.Mallord:BAAANQABCgQIBAABNQADCggIFgADAAAAAA==.Malstrom:BAAANQADCggIFgAAAA==.Mandarin:BAAANQAECgEIAQAAAA==.Mararose:BAAANQABCgIIBAAAAA==.Marashades:BAAANQADCggIFAAAAA==.',
Me='Melabrin:BAAANQAECgIIAwAAAA==.Mercia:BAAANQAECgIIAgAAAA==.Mercý:BAAANQADCgYICQAAAA==.Merekoma:BAAANQAECgQIBgAAAA==.',
Mi='Mieena:BAAANQABCgQIBAAAAA==.Milhouse:BAAANQADCgUIBQAAAA==.Mingonashoba:BAAANQAECgEIAQAAAA==.Misschris:BAAANQADCggIGgAAAA==.Mistaricky:BAAANQADCggIGQAAAA==.',
Mo='Moadeed:BAAANQAECgEIAQAAAA==.Morphmious:BAAANQAECgUICwAAAA==.Mortesque:BAAANQAECgQIBgAAAA==.',
Mu='Muttblitzed:BAAANQADCgcICQAAAA==.',
My='Myrrh:BAAANQAECgYIDgAAAA==.',
['Mí']='Místermage:BAAANQAECgQIBAAAAA==.',
['Mô']='Môses:BAAANQADCgMIBQAAAA==.',
Na='Naidia:BAAANQADCgYIEgAAAA==.Nausican:BAAANQADCgQIBQAAAA==.',
Ne='Necrosector:BAAANQAECgQIBAAAAA==.Nelandra:BAAANQADCggIGQAAAA==.Nerazlyn:BAAANQADCgMIAwAAAA==.',
Ni='Nickflare:BAAANQABCgQIBAAAAA==.',
No='Nomahuata:BAAANQAECgQICQAAAA==.',
Nu='Nufrus:BAAANQADCggIGQAAAA==.',
Ny='Nyeli:BAAANQADCggIFAAAAA==.Nyxi:BAAANQADCggIEwAAAA==.',
['Né']='Néo:BAAANQADCggIFQAAAA==.',
On='Onefiftyone:BAAANQAECgEIAQAAAA==.',
Pa='Palochka:BAAANQADCgcIDQAAAA==.Palpetine:BAAANQADCgYIEAAAAA==.Paltator:BAAANQAECgIIAgAAAA==.Pandazuken:BAAANQAECgQIBAAAAA==.Paradots:BAAANQAECgcIEwAAAA==.Paranitis:BAAANQADCggICAAAAA==.Paraparaboom:BAAANQAECgQIBQAAAA==.',
Ph='Phatboi:BAAANQADCgQIBAAAAA==.Pheroth:BAAANQADCgYIDAABNQADCggIFgADAAAAAA==.',
Pi='Pixpax:BAAANQADCgQIBQAAAA==.Pixyofdeath:BAAANQADCggIAwABNQADCggIGQADAAAAAA==.Pixystix:BAAANQADCggIGQAAAA==.',
Po='Pomortem:BAAANQADCggIGQAAAA==.Potsomancy:BAABNQAECoEYAAIKAAkJNCTEEwBSAwAKAAkJNCTEEwBSAwAAAA==.',
Pr='Profian:BAAANQADCgcIBwAAAA==.',
Ra='Radioshack:BAAANQADCgUIBQABNQADCggIGQADAAAAAA==.Raivel:BAAANQADCgcIEQABNQADCggIFAADAAAAAA==.Raneyth:BAAANQADCgcIFgAAAA==.Ranoku:BAAANQADCgYIBgAAAA==.',
Re='Redwinetoast:BAAANQADCggIGgAAAA==.Reignblade:BAAANQABCgIIAwAAAA==.Reno:BAAANQAECgMIBQAAAA==.Reposess:BAAANQABCggIDQAAAA==.Reshyk:BAAANQADCggIGQAAAA==.',
Rh='Rhobes:BAAANQADCgYIBgAAAA==.',
Ri='Rickkrolled:BAAANQAECgEIAQAAAA==.Riordaa:BAAANQADCggIGgAAAA==.',
Ro='Roboskritch:BAAANQADCgUIBwABNQADCgUICQADAAAAAA==.Rowene:BAAANQADCgUICwAAAA==.',
Ru='Rumor:BAAANQADCggIGgAAAA==.Rurry:BAACNQAFFIEFAAIGAAMJuxY+BQANAQAGAAMJuxY+BQANAQA1AAQKgRoAAgYACQnIIhoCAHQDAAYACQnIIhoCAHQDAAAA.',
Ry='Ryuuki:BAAANQAECgQICAAAAA==.',
['Rï']='Rïzzler:BAEANQAECggIEwAAAA==.',
Sa='Safetysham:BAAANQADCgcICwAAAA==.Saffia:BAAANQABCgUIBAAAAA==.Salmoo:BAAANQADCgYIBwABNQAECgEIAQADAAAAAA==.Saltytator:BAAANQAECgMIAwAAAA==.Savonah:BAAANQADCgYIDwAAAA==.',
Sc='Scaledaddy:BAAANQAECgQIBQAAAA==.Scaryl:BAAANQADCggIHAAAAA==.Schneè:BAAANQAECgYIEAAAAA==.Scoom:BAACNQAFFIEFAAIKAAMJTBtkDAAaAQAKAAMJTBtkDAAaAQA1AAQKgR4AAgoACQn7Iy4IAJwDAAoACQn7Iy4IAJwDAAAA.Scourgespawn:BAABNQAECoEdAAMLAAkJuCLMAwBbAwALAAkJuCLMAwBbAwAMAAMJpAlcZQCgAAAAAA==.',
Se='Seikyo:BAAANQAECgQIBQAAAA==.Seilah:BAAANQADCgUIBwABNQAECgQICAADAAAAAA==.Selenë:BAAANQAECgIIAgAAAA==.Serok:BAAANQAECgYICgAAAA==.',
Sh='Shadowbox:BAAANQADCgMIAwAAAA==.Shadyaf:BAAANQADCggIFQAAAA==.Shalis:BAAANQADCggIFwAAAA==.Sharivee:BAAANQADCggIFAAAAA==.Shazamir:BAAANQADCggIGgAAAA==.Shibui:BAAANQAECgIIAwAAAA==.Shifthead:BAABNQAECoEXAAMNAAgJ4BldBACKAgANAAgJ4BldBACKAgAOAAEJoQG9dwAmAAAAAA==.Shockazilla:BAAANQAECgIIAwAAAA==.Shortspanky:BAAANQAECgMIAwAAAA==.',
Si='Silverhorn:BAAANQAECgIIAwAAAA==.',
Sk='Skoduh:BAAANQADCggIFwAAAA==.',
Sl='Slack:BAAANQAECgIIBAABNQAECgMIBQADAAAAAA==.Sluggo:BAABNQAECoEbAAIIAAkJGxx0IACkAgAIAAkJGxx0IACkAgAAAA==.',
Sm='Smokeü:BAAANQADCggICgAAAA==.',
So='Solinaara:BAAANQABCgQIBAAAAA==.Soraka:BAAANQABCgMIAQAAAA==.',
St='Stonedalways:BAAANQADCggIFQAAAA==.Stonytoni:BAAANQADCgMIBgAAAA==.',
Su='Sunfuri:BAAANQAECgQIBAAAAA==.Sus:BAABNQAECoEcAAMPAAkJ1R7VBwAbAwAPAAkJ1R7VBwAbAwAQAAQJ3AWsDwCqAAAAAA==.Susanoo:BAAANQADCgYIBgAAAA==.',
Ta='Taalia:BAAANQADCggIGQAAAA==.Talonas:BAAANQAECgEIAQAAAA==.Tarathor:BAAANQADCggIGQAAAA==.Tatortott:BAAANQADCgMIAwAAAA==.',
Te='Teknofarious:BAAANQAECgUIDQAAAA==.',
Th='Thesafe:BAAANQADCggIGgAAAA==.Thevin:BAAANQAECgIIAgABNQAECgMIBQADAAAAAA==.Thialia:BAAANQAECgUIBQABNQAECgIIAwADAAAAAA==.Thickems:BAAANQAECgYIDwAAAA==.Thoralon:BAAANQADCgYIBgAAAA==.',
Ti='Tinkabella:BAAANQAECgQIBQAAAA==.',
To='Torrey:BAAANQADCgIIAgAAAA==.',
Tr='Trek:BAAANQADCggIGgAAAA==.Trema:BAAANQAECgMIAwAAAA==.Trix:BAAANQADCggIFgAAAA==.',
Ts='Tserendelgor:BAAANQAECgUIBQAAAA==.',
Tu='Tulsi:BAAANQAECgIIAgAAAA==.',
Ty='Tyronos:BAAANQADCgcIDAAAAA==.',
Va='Vaeltharion:BAAANQADCggIEQAAAA==.Vas:BAAANQADCgYICAAAAA==.',
Ve='Verdandi:BAAANQADCgYIBgAAAA==.Vevicenth:BAAANQADCggICAAAAA==.',
Vo='Voranth:BAAANQAECgEIAQAAAA==.',
Wa='Warenio:BAAANQAECgQIBQAAAA==.Warpsbulge:BAAANQAFFAEIAQAAAA==.Wayawoman:BAAANQABCgIIAgABNQADCggIGgADAAAAAA==.',
Wh='Whakan:BAAANQADCgYIDwABNQAECgMIAwADAAAAAA==.',
Wo='Wolfos:BAAANQAECgIIBAAAAA==.',
Wt='Wtfox:BAEANQAECgQIBAAAAA==.',
Wy='Wysteri:BAAANQADCgMIAwAAAA==.',
Xa='Xalatos:BAAANQADCgcICgAAAA==.Xalfein:BAAANQADCgYIBgAAAA==.',
Xi='Xinu:BAAANQADCgIIAgABNQAECgIIAwADAAAAAA==.',
Xo='Xolani:BAAANQAECgQIAwAAAA==.',
Ya='Yanakana:BAAANQADCgcIFgAAAA==.',
Za='Zakeko:BAAANQADCggIGQAAAA==.',
Ze='Zenus:BAAANQAECgIIAgAAAA==.Zesty:BAAANQADCgIIAgAAAA==.Zeusinator:BAAANQADCgIIAgAAAA==.',
Zf='Zfatpanda:BAAANQADCggICAAAAA==.',
Zi='Zinu:BAAANQAECgIIAwAAAA==.',
Zu='Zukarius:BAAANQADCgUIBQABNQAECgEIAQADAAAAAA==.Zulfionn:BAAANQAECgEIAQAAAA==.',
['Áy']='Áyrá:BAAANQADCggIGQAAAA==.',
['Øu']='Øuroboros:BAAANQAECgMIBAAAAA==.',
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
