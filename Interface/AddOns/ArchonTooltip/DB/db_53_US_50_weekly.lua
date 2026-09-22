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

local lookup = {'Hunter-BeastMastery','Hunter-Marksmanship','Warlock-Destruction','Warlock-Demonology','Unknown-Unknown','DemonHunter-Havoc','DemonHunter-Devourer','Warrior-Arms','Evoker-Preservation','Monk-Windwalker','Priest-Shadow','Rogue-Assassination','Paladin-Holy','Paladin-Retribution','Warrior-Protection','Mage-Arcane','Rogue-Subtlety','DeathKnight-Frost','DeathKnight-Unholy','Druid-Feral','Druid-Balance','DemonHunter-Vengeance',}
local provider = {region='US',realm='CenarionCircle',name='US',type='weekly',zone=53,date='2026-09-22',data={Ac='Aceieus:BAAANQABCgUIBQAAAA==.Achelis:BAAANQAECgYICwAAAA==.',
Ad='Adorian:BAAANQADCggJGgAAAA==.Adros:BAAANQADCggJEAAAAA==.Adrrel:BAAANQADCgYIBgABNQAFFAMIBwABAJ0TAA==.Adrrelle:BAACNQAFFIEHAAMBAAMKnRP/DgCxAAABAAIKsxj/DgCxAAACAAIKegaUEQCJAAA1AAQKgR4AAwIACQowGcUcAAwCAAIACApKFsUcAAwCAAEAAgqNJQLGALgAAAAA.',
Ae='Aelfwine:BAAANQAECgIJAwAAAA==.',
Ai='Ailaith:BAAANQAECgMJBgAAAA==.',
Ak='Akariliselle:BAABNQAECoEdAAMDAAcK9RuACABZAgADAAcK9RuACABZAgAEAAQKIRYMjgAdAQAAAA==.',
Al='Alan:BAAANQADCgcICgAAAA==.Alcun:BAAANQADCgYIBgAAAA==.Alein:BAAANQADCgEJAQAAAA==.Alydrostage:BAAANQAECgMIAwAAAA==.Alystriaz:BAAANQAECgIIBAAAAA==.Alzheimerz:BAAANQAECgYJEAAAAA==.',
Am='Amaelalin:BAAANQAECgMJBgAAAA==.Amatoria:BAAANQAECgEJAQAAAA==.',
An='Anaralyth:BAAANQADCgUICQABNQAECgQJCgAFAAAAAA==.Andaya:BAAANQAECgcJDwAAAA==.Andemeli:BAAANQAECgEJAQAAAA==.Andrewrynn:BAAANQADCgEIAQAAAA==.Annarah:BAAANQAECgEJAQAAAA==.',
Ar='Arandis:BAAANQAECgIIAwAAAA==.Arcianna:BAAANQAECgUICAAAAA==.Arctica:BAAANQAECgIJAwAAAA==.Arjurn:BAAANQAECgYJCwAAAA==.Armpitbutter:BAAANQAECgYJDAAAAA==.Artymiss:BAAANQAECgIJAwAAAA==.',
As='Astraleth:BAAANQAECgQJCgAAAA==.',
Av='Avocat:BAAANQAECgQICAAAAA==.',
Ay='Ayorana:BAAANQADCgcIDQAAAA==.',
Az='Azshura:BAAANQADCgMIAwAAAA==.Azzinôth:BAABNQAECoEdAAMGAAgKGRG0JADuAQAGAAgKrg20JADuAQAHAAcK3Q8VJwCzAQAAAA==.',
Ba='Baldr:BAAANQAECgUIBwAAAA==.Balgar:BAAANQADCggIGgAAAA==.Bammz:BAABNQAECoEVAAIIAAgKHx5DLwCtAgAIAAgKHx5DLwCtAgAAAA==.Bastia:BAAANQADCgYIDAAAAA==.Baumstrum:BAAANQADCgcIDAAAAA==.',
Be='Beltbuckle:BAAANQADCgMIBAABNQADCgUICQAFAAAAAA==.Benbeckman:BAAANQADCgQJBAAAAA==.',
Bi='Bigtbag:BAAANQADCgUIBwAAAA==.',
Bl='Bloodrayvn:BAAANQAECgIIAwAAAA==.Bloodytusks:BAAANQADCgcIBwAAAA==.',
Bo='Borrkbuster:BAAANQADCggJHwAAAA==.',
Br='Brenri:BAAANQAECgMJBAAAAA==.Brewtality:BAAANQAECgQIBAABNQAECggIHQAJAOYaAA==.Brudanature:BAAANQADCgUIBQABNQAECgEJAQAFAAAAAA==.Brughe:BAAANQAECgMJAwAAAA==.Brywynn:BAAANQADCggJDgABNQAECgEJAQAFAAAAAA==.',
Bu='Bubbleoseven:BAAANQAECgYJCQABNQAECggIHQAJAOYaAA==.Burnbabyburn:BAAANQADCgYIBgAAAA==.Buttacutta:BAAANQADCgcJDgAAAA==.',
Ca='Cahoots:BAABNQAECoEZAAIKAAgKpB8oCwDTAgAKAAgKpB8oCwDTAgAAAA==.Caneste:BAACNQAFFIEGAAILAAMKxBSaBgALAQALAAMKxBSaBgALAQA1AAQKgRwAAgsACQrHHswKAP0CAAsACQrHHswKAP0CAAAA.Capela:BAAANQABCgQIBAAAAA==.Catty:BAAANQAECgUJCgAAAA==.Cayleynne:BAAANQAECgUJCQAAAA==.',
Ce='Celestyl:BAAANQAECgEJAgAAAA==.',
Ch='Chadman:BAAANQADCgYIBgAAAA==.Chamadel:BAAANQADCgMIAwAAAA==.Cheapbeerz:BAAANQAECgUIBgAAAA==.Cheesemon:BAAANQADCgUIBQAAAA==.Chiforged:BAAANQADCggIFQAAAA==.Chromstrasza:BAAANQAECgYIDQAAAA==.',
Ci='Cinnia:BAAANQAECgUICAAAAA==.',
Co='Comitus:BAAANQAECgQIBQAAAA==.Conj:BAAANQADCgIIAgAAAA==.Conjarr:BAAANQAECgUIDwAAAA==.Cooters:BAAANQADCgQJBAABNQAECgUICgAFAAAAAA==.Cougarsixsix:BAAANQADCggIIQAAAA==.',
Cr='Crabcarbs:BAAANQADCgUICQAAAA==.Creideam:BAAANQADCgcJBwAAAA==.Crimos:BAAANQAECgYJEQAAAA==.Crypticcurse:BAAANQADCgcIEQAAAA==.',
Cy='Cynnai:BAABNQAECoEWAAIIAAcK8htXUQAmAgAIAAcK8htXUQAmAgAAAA==.',
Da='Daerthor:BAAANQADCgYJCQABNQADCggJFQAFAAAAAA==.Dalora:BAAANQADCggIDAAAAA==.Damaclies:BAAANQAECgQICQAAAA==.Danashal:BAAANQAECgUIBwAAAA==.Dangerranger:BAAANQAECgIIAgAAAA==.Dansen:BAAANQADCgUIBQAAAA==.Darksyn:BAAANQADCggJHQAAAA==.Darrth:BAAANQAECgQJBwAAAA==.Darthbane:BAAANQAECgIIAgAAAA==.Darthjareth:BAAANQADCgUIBQAAAA==.Darude:BAAANQADCgUIBQABNQADCgUICQAFAAAAAA==.Dattiffany:BAAANQAECgIIAwAAAA==.',
De='Dekkan:BAAANQAECgQIBAAAAA==.Delphyne:BAAANQAECgUJBQAAAA==.Denasel:BAAANQADCgcIBwAAAA==.Denwarenji:BAAANQAECgYJDgAAAA==.Desmádre:BAAANQAECgYIBwAAAA==.',
Di='Diend:BAAANQAECgUICAAAAA==.Dillathis:BAAANQADCgMJAwAAAA==.Dissonanita:BAAANQADCgUICQAAAA==.',
Dj='Djthelock:BAAANQAECgIIAwAAAA==.',
Do='Doctachris:BAAANQABCgUJCQAAAA==.Domodios:BAAANQADCgYJBgABNQAECgIIAgAFAAAAAA==.',
Dr='Dravenpryde:BAAANQADCgUIBgABNQAECgYJEwAFAAAAAA==.Drbrad:BAAANQADCggIEAAAAA==.Dreadfists:BAAANQAECgUICAAAAA==.Druen:BAAANQAECgUICAAAAA==.Drunkenpo:BAAANQAECgUICAAAAA==.Drunkxdemon:BAAANQADCgYICQAAAA==.Drunkxmonk:BAAANQAFFAEJAQAAAA==.Drïzl:BAEANQAECgUJBwABNQAECgkJGgAMAFUYAA==.',
Du='Duckchow:BAAANQADCgIIAgAAAA==.',
Dw='Dwarfoo:BAAANQADCggJGgAAAA==.Dweñde:BAAANQAECgUJCwAAAA==.',
Eb='Ebonfang:BAAANQABCgEIAQAAAA==.',
Ec='Ecthelion:BAAANQADCgYIBgAAAA==.',
Ed='Eddrick:BAAANQAECgIIAwAAAA==.Edrid:BAAANQAECgYICwABNQAFFAQICQAJAOwbAA==.',
En='Engo:BAAANQAECgYJEQAAAA==.',
Er='Eradrá:BAAANQAECgIIBAAAAA==.Eragon:BAAANQADCggIIQAAAA==.',
Et='Ethaan:BAAANQABCgQIBAAAAA==.',
Eu='Eureka:BAAANQAECggJCwAAAA==.',
Ev='Evandra:BAAANQADCggIIgAAAA==.Evanorah:BAAANQAECgMIBQAAAA==.',
Fa='Faedeyeda:BAAANQADCggJFQAAAA==.',
Fe='Ferheim:BAAANQADCgQJBAAAAA==.Ferhold:BAAANQADCgIIAgAAAA==.',
Fi='Fiddyone:BAAANQADCgUIBQABNQAECgUIBgAFAAAAAA==.Figment:BAAANQADCgMIAwAAAA==.Firered:BAAANQADCgIIBAABNQAECgMIBAAFAAAAAA==.Fizzfuzzbttm:BAAANQAECgEJAQAAAA==.',
Fo='Fodurzin:BAAANQAECgEJAQABNQAECgEJAQAFAAAAAA==.',
Fr='Frojio:BAAANQAECgYICwAAAA==.Frosten:BAAANQADCgcIHAAAAA==.',
Fu='Furenio:BAAANQADCgYIBgAAAA==.',
Ga='Gabaghoul:BAAANQAECgIIAwAAAA==.Gaff:BAAANQAECgQICQAAAA==.',
Ge='Georgiana:BAAANQABCgIJAgAAAA==.',
Gr='Grauth:BAAANQADCgUICgAAAA==.Grido:BAAANQADCgIIAgAAAA==.',
Gu='Gulishdaniel:BAAANQADCgcIDQABNQAFFAMIBgALAMQUAA==.',
Ha='Hadin:BAAANQAECgQIBgAAAA==.Halalnt:BAAANQAECgEJAQABNQAECgQICQAFAAAAAA==.Hamplanet:BAAANQAECgEJAQABNQAFFAEIAQAFAAAAAA==.Hamster:BAAANQADCgYIBgABNQAECgQICQAFAAAAAA==.Haozhao:BAAANQAECgUICAAAAA==.Hazenpryde:BAAANQAECgYJEwAAAA==.',
He='Hearsay:BAAANQADCgcIEgABNQAECgIIAwAFAAAAAA==.Hecatamu:BAAANQADCgUIBQAAAA==.Hephaistian:BAAANQAECgcJCgAAAA==.',
Ho='Holytoe:BAAANQADCgYIBgAAAA==.',
Hu='Hulud:BAAANQAECgQIBQAAAA==.',
Hy='Hysgar:BAAANQAECgUIBgAAAA==.',
Ie='Iechu:BAAANQAECgEJAQAAAA==.',
Il='Illidaz:BAAANQADCgUIBgAAAA==.',
Im='Immortál:BAAANQAECgYJCgAAAA==.',
In='Indraz:BAAANQADCgQIBAAAAA==.Infinìte:BAAANQAECgYJCwAAAA==.Inic:BAAANQABCgQJBQAAAA==.',
Iv='Ivysnow:BAAANQAECgIIAgAAAA==.',
Ja='Jackfruit:BAAANQAECgMJBAAAAA==.Jaod:BAAANQADCgUJEAAAAA==.',
Jd='Jdghoul:BAAANQADCgYIBgAAAA==.',
Ji='Jindrac:BAAANQADCggIEQAAAA==.Jitsuru:BAAANQADCggICgAAAA==.',
Ju='Juanfiles:BAAANQABCgQIAwAAAA==.',
['Jà']='Jàcaranda:BAAANQADCgMIAwAAAA==.',
Ka='Kahnrah:BAAANQADCggJJAAAAA==.Kalarae:BAAANQADCgcIDAAAAA==.Kaljeer:BAAANQAECgQJCQAAAA==.Kalki:BAAANQADCgEIAQAAAA==.Kaltharion:BAAANQAECgEIAQAAAA==.Kaluren:BAACNQAFFIEJAAINAAQKvx5RBgB7AQANAAQKvx5RBgB7AQA1AAQKgSMAAw0ACQqtJkQAAPUDAA0ACQqtJkQAAPUDAA4ABQoCHdx4AJMBAAAA.Kalurion:BAAANQADCgIIAgAAAA==.Kanade:BAAANQAECgUICAAAAA==.Kanishi:BAAANQABCggIDAAAAA==.Kantong:BAAANQAECgQJCgAAAA==.Kapp:BAAANQAECgEJAQAAAA==.Karabar:BAAANQAECgYJCwAAAA==.Karnnaged:BAAANQAECgMJBgABNQAECgQIBQAFAAAAAA==.Karnnagex:BAAANQAECgQIBQAAAA==.Karnnagexx:BAAANQADCgQJBAABNQAECgQIBQAFAAAAAA==.Karnnagexxl:BAAANQAECgMIAwABNQAECgQIBQAFAAAAAA==.Kayiku:BAAANQADCgYJDAAAAA==.Kazagol:BAAANQAECgYJCwAAAA==.',
Kh='Khamaracy:BAAANQADCggJIQAAAA==.',
Ko='Kojote:BAAANQADCgMJBQAAAA==.Kovalenko:BAAANQAECgIIAwAAAA==.',
Kr='Kryptus:BAAANQAECgQJBwAAAA==.',
Ku='Kurick:BAAANQAECgEIAgABNQAECgUIBgAFAAAAAA==.Kurshak:BAAANQAECgYICgAAAA==.',
Ky='Kyngizzard:BAAANQAECgIIAgABNQAECgQICQAFAAAAAA==.',
La='Latte:BAAANQADCggIFAAAAA==.',
Le='Lenity:BAAANQAECgUJCQAAAA==.',
Lo='Loan:BAAANQADCgYIBgABNQAECgQICQAFAAAAAA==.Lockstar:BAAANQADCgYIBgAAAA==.Lokinah:BAAANQAECgIIAgAAAA==.',
Lu='Lucoryphus:BAAANQAECgMJBQAAAA==.Lukeduke:BAACNQAFFIEJAAIPAAQK9R37AABnAQAPAAQK9R37AABnAQA1AAQKgR8AAg8ACQqnIr8BAHEDAA8ACQqnIr8BAHEDAAAA.Luketheduke:BAAANQAECgMIAwABNQAFFAQICQAPAPUdAA==.Lunä:BAAANQAECgYJDQAAAA==.',
Ly='Lydia:BAAANQAECgUJCwAAAA==.Lyleath:BAAANQADCgQIBAAAAA==.',
Ma='Magickeys:BAAANQADCgMIAwAAAA==.Malifel:BAAANQADCggJGwABNQAECgIIAgAFAAAAAA==.Mallord:BAAANQABCgQIBAABNQAECgIIAgAFAAAAAA==.Malstrom:BAAANQAECgIIAgAAAA==.Mandarin:BAAANQAECgIIAwAAAA==.Mararose:BAAANQABCgIIBAAAAA==.Marashades:BAAANQADCggIFAAAAA==.',
Me='Melabrin:BAAANQAECgMJBgAAAA==.Mercia:BAAANQAECgUIBwAAAA==.Mercý:BAAANQADCgcJEAAAAA==.Merekoma:BAAANQAECgQJBwAAAA==.',
Mi='Mieena:BAAANQABCgQIBAAAAA==.Milhouse:BAAANQAECgEIAwAAAA==.Mingonashoba:BAAANQAECgEIAQAAAA==.Miragosa:BAAANQADCgMJAwAAAA==.Misschris:BAAANQADCggIIgAAAA==.Mistaricky:BAAANQADCggIIQAAAA==.',
Mo='Moadeed:BAAANQAECgIJAwAAAA==.Morphmious:BAAANQAECgYJEQAAAA==.Mortesque:BAAANQAECgQJCgAAAA==.',
Mu='Muttblitzed:BAAANQADCgcICQAAAA==.',
My='Myrrh:BAABNQAECoEYAAIJAAcKUwZmIQBCAQAJAAcKUwZmIQBCAQAAAA==.Mysklef:BAAANQADCgMJAwABNQAECgUIBgAFAAAAAA==.',
['Mí']='Místermage:BAAANQAECgQJCAAAAA==.',
['Mô']='Môses:BAAANQADCgMIBQAAAA==.',
Na='Naidia:BAAANQADCgYIEgAAAA==.Nausican:BAAANQADCgQIBQAAAA==.',
Ne='Necrosector:BAAANQAECgcIDAAAAA==.Nelandra:BAAANQADCggJIQAAAA==.Neongrasp:BAAANQADCgcJBwAAAA==.Nerazlyn:BAAANQADCgMIAwAAAA==.',
Ni='Nickflare:BAAANQAECgIJAgAAAA==.',
No='Nomahuata:BAAANQAECgYIDwAAAA==.',
Nu='Nufrus:BAAANQADCggIIQAAAA==.',
Ny='Nyeli:BAAANQAECgEJAQAAAA==.Nyxi:BAAANQAECgEJAQAAAA==.',
['Né']='Néo:BAAANQADCggIFQAAAA==.',
On='Onefiftyone:BAAANQAECgUIBgAAAA==.',
Pa='Palochka:BAAANQADCggJDgAAAA==.Palpetine:BAAANQADCgYJEAAAAA==.Paltator:BAAANQAECgQJBgAAAA==.Pandazuken:BAAANQAECgYICgAAAA==.Paradots:BAABNQAECoEdAAIJAAgK5hpwEABQAgAJAAgK5hpwEABQAgAAAA==.Paranitis:BAAANQADCggJCAAAAA==.Paraparaboom:BAAANQAECgUICgAAAA==.',
Ph='Phatboi:BAAANQADCgQIBAAAAA==.Pheroth:BAAANQADCgYIDAABNQADCggJHQAFAAAAAA==.',
Pi='Pixpax:BAAANQAECgUJBQAAAA==.Pixyofdeath:BAAANQADCggIAwABNQADCggJGQAFAAAAAA==.Pixystix:BAAANQADCggJGQAAAA==.',
Po='Pomortem:BAAANQAECgEJAQAAAA==.Potsomancy:BAACNQAFFIEFAAIQAAQKmRGfDwBkAQAQAAQKmRGfDwBkAQA1AAQKgRoAAhAACQo0JMAiACwDABAACQo0JMAiACwDAAAA.',
Pr='Profian:BAAANQADCgcIBwAAAA==.',
Ra='Radioshack:BAAANQADCgUIBQABNQADCggIHgAFAAAAAA==.Raivel:BAAANQADCggJGQABNQAECgEJAQAFAAAAAA==.Raneyth:BAAANQADCggIFwAAAA==.Ranoku:BAAANQADCgYIBgAAAA==.',
Re='Redwinetoast:BAAANQADCggIIgAAAA==.Reignblade:BAAANQABCgIIAwAAAA==.Reno:BAAANQAECgQICQAAAA==.Reposess:BAAANQABCggIDQAAAA==.Reshyk:BAAANQADCggIGQAAAA==.',
Rh='Rhobes:BAAANQADCgcIDQAAAA==.',
Ri='Rickkrolled:BAAANQAECgEIAQAAAA==.Riordaa:BAAANQADCggIIgAAAA==.',
Ro='Roboskritch:BAAANQADCgUJBwABNQADCgUICQAFAAAAAA==.Rowene:BAAANQADCgUJEAAAAA==.',
Ru='Rumor:BAAANQAECgIIAwAAAA==.Rurry:BAACNQAFFIEJAAIJAAQK7BsbBgBoAQAJAAQK7BsbBgBoAQA1AAQKgR0AAgkACQprIzICAIcDAAkACQprIzICAIcDAAAA.',
Ry='Ryuuki:BAAANQAECgQIDAAAAA==.',
['Rï']='Rïzzler:BAEBNQAECoEaAAMMAAkKVRjmGwAHAgAMAAcKmhjmGwAHAgARAAYKmRMBIACJAQAAAA==.',
Sa='Safetysham:BAAANQADCgcICwAAAA==.Saffia:BAAANQABCgUIBAAAAA==.Saleos:BAAANQADCgYJBgAAAA==.Sall:BAAANQADCgQJBAABNQADCgUICQAFAAAAAA==.Salmoo:BAAANQAECgEJAQAAAA==.Saltytator:BAAANQAECgMIBQAAAA==.Savonah:BAAANQADCgcIFgAAAA==.',
Sc='Scaledaddy:BAAANQAECgUJBgAAAA==.Scallion:BAAANQADCggJCAAAAA==.Scaryl:BAAANQAECgEJAQAAAA==.Schneè:BAABNQAECoEZAAIPAAgKABPNDADUAQAPAAgKABPNDADUAQAAAA==.Scoom:BAACNQAFFIEJAAIQAAQK+hu5DgBwAQAQAAQK+hu5DgBwAQA1AAQKgSUAAhAACQqNJDEKAJ4DABAACQqNJDEKAJ4DAAAA.Scourgespawn:BAACNQAFFIEGAAISAAMKSRQNBgDxAAASAAMKSRQNBgDxAAA1AAQKgSIAAxIACQr+IskFAFUDABIACQr+IskFAFUDABMAAwqkCadzAJsAAAAA.',
Se='Seikyo:BAAANQAECgYJCwAAAA==.Seilah:BAAANQADCgUIBwABNQAECgQICQAFAAAAAA==.Selenë:BAAANQAECgIIAgAAAA==.Serok:BAAANQAECgYIDgAAAA==.',
Sh='Shadowbox:BAAANQADCgMIAwAAAA==.Shadyaf:BAAANQAECgMJAwAAAA==.Shalis:BAAANQADCggIFwAAAA==.Sharivee:BAAANQADCggIHAAAAA==.Shazamir:BAAANQAECgMIAwAAAA==.Shibui:BAAANQAECgUICAAAAA==.Shifthead:BAABNQAECoEeAAMUAAgK4BmMBgBqAgAUAAgK4BmMBgBqAgAVAAcKXw+8NgC3AQAAAA==.Shockazilla:BAAANQAECgMJBgAAAA==.Shortspanky:BAAANQAECgMJBAAAAA==.',
Si='Silaveen:BAAANQABCgIJAgAAAA==.Silverhorn:BAAANQAECgQIBwAAAA==.',
Sk='Skoduh:BAAANQAECgEJAQAAAA==.',
Sl='Slack:BAAANQAECgMJBgABNQAECgQICQAFAAAAAA==.Sluggo:BAACNQAFFIEHAAIOAAQKMgvXBgAqAQAOAAQKMgvXBgAqAQA1AAQKgR4AAg4ACQrxHVYrAK8CAA4ACQrxHVYrAK8CAAAA.',
Sm='Smokeü:BAAANQADCggICgAAAA==.',
So='Solinaara:BAAANQABCgQIBAAAAA==.Soraka:BAAANQABCgMIAQAAAA==.',
St='Stonedalways:BAAANQAECgEJAQAAAA==.Stonytoni:BAAANQADCgMJBgAAAA==.',
Su='Sunfuri:BAAANQAECgYJCgAAAA==.Sus:BAACNQAFFIEIAAIGAAQK4g/JBQA/AQAGAAQK4g/JBQA/AQA1AAQKgR8AAwYACQq5ILYLAAgDAAYACQq5ILYLAAgDABYABArcBeUUAKkAAAAA.Susanoo:BAAANQAECgYIBgAAAA==.',
Ta='Taalia:BAAANQADCggJIQAAAA==.Talonas:BAAANQAECgEIAQAAAA==.Tarathor:BAAANQADCggJIQAAAA==.Tatortott:BAAANQADCgMIAwAAAA==.',
Te='Teknofarious:BAAANQAECgUIDQAAAA==.',
Th='Thesafe:BAAANQADCggIIgAAAA==.Thevin:BAAANQAECgQJBgABNQAECgQICQAFAAAAAA==.Thialia:BAAANQAECgUIDAABNQAECgMJBgAFAAAAAA==.Thickems:BAAANQAECgYIDwAAAA==.Thoralon:BAAANQADCgYIBgAAAA==.',
Ti='Tinkabella:BAAANQAECgYJCwAAAA==.',
To='Torrey:BAAANQADCgIIAgAAAA==.',
Tr='Trek:BAAANQADCggIIgAAAA==.Trema:BAAANQAECgQJBwAAAA==.Trix:BAAANQADCggIFgAAAA==.',
Ts='Tserendelgor:BAAANQAECgUIBQABNQAECgYJEAAFAAAAAA==.',
Tu='Tulsi:BAAANQAECgMJBQAAAA==.',
Ty='Tyronos:BAAANQADCgcIDAAAAA==.',
Va='Vaeltharion:BAAANQADCggJFQAAAA==.Vas:BAAANQADCgYJCAAAAA==.',
Ve='Verdandi:BAAANQADCgYIBgAAAA==.Vevicenth:BAAANQAECgMJAwAAAA==.',
Vo='Voranth:BAAANQAECgIIAwAAAA==.',
Wa='Warenio:BAAANQAECgQJCQAAAA==.Warpsbulge:BAAANQAFFAEIAQAAAA==.Wayawoman:BAAANQABCgIJAgABNQADCggIIgAFAAAAAA==.',
Wh='Whakan:BAAANQADCgcIFgABNQAECgMJBQAFAAAAAA==.',
Wo='Wolfos:BAAANQAECgIIBgAAAA==.',
Wt='Wtfox:BAEANQAECgYJBwAAAA==.',
Wy='Wysteri:BAAANQADCgMIAwAAAA==.',
Xa='Xalatos:BAAANQAECgQIBAAAAA==.Xalfein:BAAANQADCgYJDAAAAA==.',
Xi='Xinu:BAAANQADCgIIAgABNQAECgUICAAFAAAAAA==.',
Xo='Xolani:BAAANQAECgQIAwAAAA==.',
Ya='Yanakana:BAAANQADCggJFwAAAA==.',
Za='Zakeko:BAAANQADCggJIQAAAA==.Zanderpryde:BAAANQADCggJCAABNQAECgYJEwAFAAAAAA==.',
Ze='Zenus:BAAANQAECgIJAgAAAA==.Zesty:BAAANQADCgIJAgAAAA==.Zeusinator:BAAANQADCgcICQAAAA==.',
Zf='Zfatpanda:BAAANQADCggICAAAAA==.',
Zi='Zinu:BAAANQAECgUICAAAAA==.',
Zu='Zukarius:BAAANQADCgUIBQABNQAECgUIBgAFAAAAAA==.Zulfionn:BAAANQAECgIJAwAAAA==.Zurok:BAAANQADCgcIBwABNQAECgQICQAFAAAAAA==.',
['Áy']='Áyrá:BAAANQADCggIIQAAAA==.',
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
