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

local lookup = {'Hunter-BeastMastery','Hunter-Marksmanship','Warlock-Destruction','Warlock-Demonology','Unknown-Unknown','Rogue-Assassination','Rogue-Outlaw','Shaman-Restoration','DemonHunter-Havoc','DemonHunter-Devourer','Warrior-Arms','Evoker-Preservation','Monk-Windwalker','Priest-Shadow','Evoker-Devastation','Priest-Holy','DeathKnight-Unholy','Druid-Guardian','Priest-Discipline','Mage-Frost','Paladin-Holy','Paladin-Retribution','Warrior-Protection','Druid-Feral','Shaman-Elemental','Mage-Arcane','Rogue-Subtlety','DeathKnight-Frost','Druid-Balance','DemonHunter-Vengeance',}
local provider = {region='US',realm='CenarionCircle',name='US',type='weekly',zone=53,date='2026-09-29',data={Ac='Aceieus:BAAANQABCgUIBQAAAA==.Achelis:BAAANQAECgcIEQAAAA==.',
Ad='Adorian:BAAANQAECgIIAgAAAA==.Adros:BAAANQADCggJEAAAAA==.Adrrel:BAAANQADCgYIBgABNQAFFAQICQABABAQAA==.Adrrelle:BAACNQAFFIEJAAMBAAQKEBBgDwDoAAABAAMKRBJgDwDoAAACAAIKegYGFwB9AAA1AAQKgSEAAwIACQpjGvsiAPMBAAIACApgFvsiAPMBAAEABAq0HdajAFUBAAAA.',
Ae='Aelfwine:BAAANQAECgIIBQAAAA==.',
Ai='Ailaith:BAAANQAECgYIDAAAAA==.',
Ak='Akariliselle:BAABNQAECoEjAAMDAAcKKB5BCQBVAgADAAcKGRxBCQBVAgAEAAQKIh8+iwBmAQAAAA==.',
Al='Alan:BAAANQADCgcICgAAAA==.Alcun:BAAANQADCgYIBgAAAA==.Alein:BAAANQADCgEJAQAAAA==.Alluriel:BAAANQADCggICAABNQADCgcIDQAFAAAAAA==.Alydrostage:BAAANQAECgQIBwAAAA==.Alystriaz:BAAANQAECgIIBAAAAA==.Alzheimerz:BAABNQAECoEZAAMGAAgKZhwTFQCIAgAGAAgKMhsTFQCIAgAHAAIKZBeuEwCAAAAAAA==.',
Am='Amaelalin:BAAANQAECgYIDAAAAA==.Amatoria:BAAANQAECgEIAQAAAA==.',
An='Anaralyth:BAAANQADCgUICQABNQAFFAEIAQAFAAAAAA==.Andaya:BAABNQAECoEaAAIIAAgK3RrKLwBgAgAIAAgK3RrKLwBgAgAAAA==.Andemeli:BAAANQAECgIIAwAAAA==.Andrewrynn:BAAANQADCgEIAQAAAA==.Annarah:BAAANQAECgIIAwAAAA==.',
Ar='Arandis:BAAANQAECgQIBwAAAA==.Arcianna:BAAANQAECgUIDQAAAA==.Arctica:BAAANQAECgIIBQAAAA==.Arjurn:BAAANQAECgYIEQAAAA==.Armpitbutter:BAAANQAECgYIEgAAAA==.Artymiss:BAAANQAECgIIBQAAAA==.',
As='Astraleth:BAAANQAFFAEIAQAAAA==.',
Au='Autry:BAAANQADCgEIAQAAAA==.',
Av='Avocat:BAAANQAECgQIDAAAAA==.',
Ay='Ayorana:BAAANQADCgcIDQAAAA==.',
Az='Azshura:BAAANQADCgYIAwAAAA==.Azzinôth:BAABNQAECoEkAAMJAAgKshHjLADjAQAJAAgKUQ/jLADjAQAKAAcK3Q+pLACcAQAAAA==.',
Ba='Baldr:BAAANQAECgUIDAAAAA==.Balgar:BAAANQAECgIIAgAAAA==.Bammz:BAABNQAECoEbAAILAAgK1h5RPQCaAgALAAgK1h5RPQCaAgAAAA==.Bastia:BAAANQADCgYIEgAAAA==.Baumstrum:BAAANQADCgcIDAAAAA==.',
Be='Beltbuckle:BAAANQADCgMIBAABNQADCgUICQAFAAAAAA==.Benbeckman:BAAANQAECgcIBwAAAA==.',
Bi='Bigtbag:BAAANQADCgUIBwAAAA==.',
Bl='Bloodrayvn:BAAANQAECgQIBwAAAA==.Bloodytusks:BAAANQADCggIDgAAAA==.',
Bo='Borrkbuster:BAAANQAECgMIAwAAAA==.',
Br='Brenri:BAAANQAECgMJBAAAAA==.Brewtality:BAAANQAECgQIBAABNQAECgkJJgAMAEkbAA==.Brudanature:BAAANQADCgUIBQABNQAECgQIBQAFAAAAAA==.Brughe:BAAANQAECgUICAAAAA==.Brywynn:BAAANQADCggJDgABNQAECgIIAwAFAAAAAA==.',
Bu='Bubbleoseven:BAAANQAECgYIEQABNQAECgkJJgAMAEkbAA==.Burnbabyburn:BAAANQADCgYICgABNQAECgEIAQAFAAAAAA==.Buttacutta:BAAANQADCggIFgAAAA==.',
Ca='Cahoots:BAABNQAECoEeAAINAAkKBiDUCQALAwANAAkKBiDUCQALAwAAAA==.Caneste:BAACNQAFFIEIAAIOAAMKkhUkCQAAAQAOAAMKkhUkCQAAAQA1AAQKgR8AAg4ACQoUIDsNAOoCAA4ACQoUIDsNAOoCAAAA.Capela:BAAANQABCgQIBAAAAA==.Catty:BAAANQAECgYIEAAAAA==.Cayleynne:BAAANQAECgcIEAAAAA==.',
Ce='Celestyl:BAAANQAECgEIAwAAAA==.',
Ch='Chadman:BAAANQADCgYIBgAAAA==.Chamadel:BAAANQADCgMIAwAAAA==.Cheapbeerz:BAAANQAECgYIDAAAAA==.Cheesemon:BAAANQADCgUIBQAAAA==.Chiforged:BAAANQAECgEIAQAAAA==.Chromstrasza:BAABNQAECoEWAAIPAAgK1w3HFAC+AQAPAAgK1w3HFAC+AQAAAA==.',
Ci='Cinnia:BAAANQAECgUIDQAAAA==.',
Co='Comitus:BAAANQAECgYICwAAAA==.Conj:BAAANQADCgIIAgAAAA==.Conjarr:BAABNQAECoEXAAIQAAgK2BvdJgCTAgAQAAgK2BvdJgCTAgAAAA==.Cooters:BAAANQADCgQJBAABNQAECgUIDgAFAAAAAA==.Cotournix:BAAANQADCgcIBwAAAA==.Cougarsixsix:BAAANQAECgIIAgAAAA==.',
Cr='Crabcarbs:BAAANQADCgUICQAAAA==.Creideam:BAAANQADCgcJBwAAAA==.Crimos:BAABNQAECoEYAAIRAAcKcwtWVQBVAQARAAcKcwtWVQBVAQAAAA==.Crypticcurse:BAAANQADCgcIGQAAAA==.',
Cy='Cynnai:BAABNQAECoEXAAILAAcK8htlaQAJAgALAAcK8htlaQAJAgAAAA==.',
Da='Daerthor:BAAANQADCgYJCQABNQAECgIIAgAFAAAAAA==.Dalora:BAAANQADCggIDAAAAA==.Damaclies:BAAANQAECgYIDwAAAA==.Danashal:BAAANQAECgUIDAAAAA==.Dangerranger:BAAANQAECgIIAgAAAA==.Dansen:BAAANQADCgUIBQAAAA==.Darkspanner:BAAANQADCgQIBAAAAA==.Darksyn:BAAANQADCggIJQAAAA==.Darrth:BAAANQAECgUIDAAAAA==.Darthbane:BAAANQAECgIIBAAAAA==.Darthjareth:BAAANQADCgUIBQAAAA==.Darude:BAAANQADCgUIBQABNQADCgUICQAFAAAAAA==.Dattiffany:BAAANQAECgIIAwAAAA==.',
De='Dekkan:BAAANQAECgQICAAAAA==.Delphyne:BAAANQAECgUICgAAAA==.Demontator:BAAANQADCggICAAAAA==.Denasel:BAAANQADCgcIBwAAAA==.Denwarenji:BAAANQAECgYIEgAAAA==.Desmádre:BAAANQAECgcICgAAAA==.',
Di='Dia:BAAANQADCgQIBAAAAA==.Diend:BAAANQAECgYIDgAAAA==.Dillathis:BAAANQADCgMJAwAAAA==.Dissonanita:BAAANQADCgUICQAAAA==.',
Dj='Djthelock:BAAANQAECgQIBwAAAA==.',
Do='Doctachris:BAAANQABCgUICQAAAA==.Domodios:BAAANQADCgYJBgABNQAECgQIBAAFAAAAAA==.',
Dr='Dravenpryde:BAAANQAECgUIBQABNQAECggIHAASAAwdAA==.Drbrad:BAAANQAECgQIBAAAAA==.Dreadfists:BAAANQAECgUIDQAAAA==.Druen:BAAANQAECgUIDQAAAA==.Drunkenpo:BAAANQAECgYIDgAAAA==.Drunkxdemon:BAAANQAECgQIBAAAAA==.Drunkxmonk:BAAANQAFFAEIAQAAAA==.Drïzl:BAEANQAECgYIDQABNQAECgkJHgAGACYZAA==.',
Du='Duckchow:BAAANQADCgIIAgAAAA==.',
Dw='Dwarfoo:BAAANQAECgIIAgAAAA==.Dweñde:BAAANQAECgYIEAAAAA==.',
Eb='Ebonfang:BAAANQABCgEIAQAAAA==.',
Ec='Ecthelion:BAAANQAECgEIAQAAAA==.',
Ed='Eddrick:BAAANQAECgQIBwAAAA==.Edrid:BAAANQAECgYICwABNQAFFAQIDQAMAAYeAA==.',
En='Engo:BAABNQAECoEbAAITAAgKpx5QAgDUAgATAAgKpx5QAgDUAgAAAA==.',
Er='Eradrá:BAAANQAECgIIBAAAAA==.Eragon:BAAANQAECgIIAgAAAA==.',
Et='Ethaan:BAAANQABCgQIBAAAAA==.',
Eu='Eureka:BAAANQAECggIDgAAAA==.',
Ev='Evandra:BAAANQAECgIIAgAAAA==.Evanorah:BAAANQAECgMICAAAAA==.',
Fa='Faedeyeda:BAAANQAECgIIAgAAAA==.',
Fe='Ferheim:BAAANQADCgQJBAAAAA==.Ferhold:BAAANQADCgIIAgAAAA==.',
Fi='Fiddyone:BAAANQADCgUIBQABNQAECgUICwAFAAAAAA==.Figment:BAAANQADCgMIAwAAAA==.Firered:BAAANQADCgIIBAABNQAECgMIBQAFAAAAAA==.Fizzfuzzbttm:BAAANQAECgEJAQAAAA==.',
Fo='Fodurzin:BAAANQAECgEJAQABNQAECgUIBgAFAAAAAA==.',
Fr='Frojio:BAAANQAECgYIEQAAAA==.Frosten:BAAANQADCgcIIwAAAA==.',
Fu='Furenio:BAAANQADCgYIBgAAAA==.',
Ga='Gabaghoul:BAAANQAECgIIAwAAAA==.Gaff:BAAANQAECgUIDgAAAA==.',
Ge='Georgiana:BAAANQABCgIIAgAAAA==.',
Gr='Grauth:BAAANQADCgUICgAAAA==.Grido:BAAANQADCgYICAAAAA==.',
Gu='Gulishdaniel:BAAANQADCgcIDQABNQAFFAMICAAOAJIVAA==.',
Ha='Hadin:BAAANQAECgYIDAAAAA==.Halalnt:BAAANQAECgEJAQABNQAECgQICQAFAAAAAA==.Hamplanet:BAAANQAECgQIBAABNQAECgkJGAAUAJUaAA==.Hamster:BAAANQADCgYIBgABNQAECgUIDgAFAAAAAA==.Hanu:BAAANQABCggICgAAAA==.Haozhao:BAAANQAECgYIDgAAAA==.Hazenpryde:BAABNQAECoEcAAISAAgKDB2KBwClAgASAAgKDB2KBwClAgAAAA==.',
He='Healicious:BAAANQADCgcIDgAAAA==.Hearsay:BAAANQADCggIFAABNQAECgIIBQAFAAAAAA==.Hecatamu:BAAANQADCgUIBQAAAA==.Hephaistian:BAAANQAECgcIEQAAAA==.',
Ho='Holytoe:BAAANQADCgYIBgAAAA==.',
Hu='Hulud:BAAANQAECgYICgAAAA==.',
Hy='Hysgar:BAAANQAECgUICQAAAA==.',
Ie='Iechu:BAAANQAECgEJAQAAAA==.',
Il='Illidaz:BAAANQADCgUIBgAAAA==.',
Im='Immortál:BAAANQAECgYIEAAAAA==.',
In='Indraz:BAAANQADCgQIBAAAAA==.Infinìte:BAAANQAECgYIEQAAAA==.Inic:BAAANQABCgQJBQAAAA==.',
Is='Isildur:BAAANQADCgEIAQAAAA==.',
Iv='Ivysnow:BAAANQAECgIIAgAAAA==.',
Ja='Jackfruit:BAAANQAECgUICQAAAA==.Jaod:BAAANQADCgYIFgAAAA==.',
Jd='Jdghoul:BAAANQADCgYIBgAAAA==.',
Ji='Jindrac:BAAANQADCggIEQAAAA==.Jitsuru:BAAANQADCggICgAAAA==.',
Ju='Juanfiles:BAAANQABCgQIAwAAAA==.',
['Jà']='Jàcaranda:BAAANQADCgMIAwAAAA==.',
Ka='Kahnrah:BAAANQADCggILAAAAA==.Kalarae:BAAANQAECgQIBAAAAA==.Kaljeer:BAAANQAECgUIDgAAAA==.Kalki:BAAANQADCgEIAQAAAA==.Kaltharion:BAAANQAECgEIAQAAAA==.Kaluren:BAACNQAFFIENAAIVAAQKvB8WCQB8AQAVAAQKvB8WCQB8AQA1AAQKgSYAAxUACQqtJnoAAO8DABUACQqtJnoAAO8DABYABQoCHcScAHoBAAAA.Kalurion:BAAANQADCgIIAgAAAA==.Kanade:BAAANQAECgUIDQAAAA==.Kanishi:BAAANQABCggIDAAAAA==.Kantong:BAAANQAECgYIEAAAAA==.Kapp:BAAANQAECgIIAwAAAA==.Karabar:BAAANQAECgYIEQAAAA==.Karnnaged:BAAANQAECgMIBgABNQAECgQIBQAFAAAAAA==.Karnnagex:BAAANQAECgQIBQAAAA==.Karnnagexx:BAAANQADCgQJBAABNQAECgQIBQAFAAAAAA==.Karnnagexxl:BAAANQAECgMIAwABNQAECgQIBQAFAAAAAA==.Kasarra:BAAANQADCgYIBgAAAA==.Kayiku:BAAANQADCggIFAAAAA==.Kazagol:BAAANQAECgYIEQAAAA==.',
Kh='Khamaracy:BAAANQAECgIIAgAAAA==.',
Ko='Kojote:BAAANQADCgMIBgAAAA==.Kovalenko:BAAANQAECgQIBwAAAA==.',
Kr='Kryptus:BAAANQAECgUIDAAAAA==.',
Ku='Kurick:BAAANQAECgIIBAABNQAECgUICQAFAAAAAA==.Kurshak:BAAANQAECgYIEAAAAA==.',
Ky='Kyngizzard:BAAANQAECgIIBAABNQAECgQICQAFAAAAAA==.',
La='Latte:BAAANQAECgIIAgAAAA==.',
Le='Lenity:BAAANQAECgYIDwAAAA==.',
Lo='Loan:BAAANQADCggIDgABNQAECgUIDgAFAAAAAA==.Lockstar:BAAANQADCgYIBgAAAA==.Lokinah:BAAANQAECgIIBAAAAA==.',
Lu='Lucoryphus:BAAANQAECgMIBQAAAA==.Lukeduke:BAACNQAFFIENAAIXAAQK9R2lAQBMAQAXAAQK9R2lAQBMAQA1AAQKgSIAAhcACQq8IxgCAHYDABcACQq8IxgCAHYDAAAA.Luketheduke:BAAANQAECgMIAwABNQAFFAQIDQAXAPUdAA==.Lunä:BAAANQAECgYIDwAAAA==.',
Ly='Lydia:BAAANQAECgUIEAAAAA==.Lyleath:BAAANQADCgQIBAABNQADCgcIDQAFAAAAAA==.',
Ma='Malcontent:BAAANQAECgMIAwABNQAECgQIBAAFAAAAAA==.Malifel:BAAANQAECgIIAgABNQAECgQIBAAFAAAAAA==.Mallord:BAAANQAECgQIBAAAAA==.Malstrom:BAAANQAECgIIBAABNQAECgQIBAAFAAAAAA==.Mandarin:BAAANQAECgIIAwAAAA==.Mararose:BAAANQABCgIIBAAAAA==.Marashades:BAAANQAECgIIAgAAAA==.Marsali:BAAANQADCgcIBwAAAA==.',
Me='Melabrin:BAAANQAECgYIDAAAAA==.Mercia:BAAANQAECgUIDAAAAA==.Mercý:BAAANQADCgcIEAAAAA==.Merekoma:BAAANQAECgQICwAAAA==.',
Mi='Mieena:BAAANQABCgQIBAAAAA==.Milhouse:BAAANQAECgEIAwAAAA==.Mingonashoba:BAAANQAECgEIAQAAAA==.Miragosa:BAAANQADCgMIAwAAAA==.Misschris:BAAANQAECgIIAgAAAA==.Mistaricky:BAAANQAECgIIAgAAAA==.',
Mo='Moadeed:BAAANQAECgIIBQAAAA==.Morphmious:BAABNQAECoEbAAIYAAgKhBWACQBCAgAYAAgKhBWACQBCAgAAAA==.Mortesque:BAAANQAECgQICgAAAA==.',
Mu='Muffinz:BAAANQADCgcIEAAAAA==.Muttblitzed:BAAANQAECgIIAgAAAA==.',
My='Myrrh:BAABNQAECoEfAAIMAAgKlwYIIgB0AQAMAAgKlwYIIgB0AQAAAA==.Mysklef:BAAANQADCgMJAwABNQAECgUICQAFAAAAAA==.Mythrandyl:BAAANQADCgYIBgAAAA==.',
['Mí']='Místermage:BAAANQAECgQJCAAAAA==.',
['Mô']='Môses:BAAANQADCgMIBQAAAA==.',
Na='Naidia:BAAANQAECgQIBAABNQADCgcIDQAFAAAAAA==.Nausican:BAAANQADCgUIBgAAAA==.',
Ne='Necrogue:BAAANQADCgIIAgABNQAECgQIBwAFAAAAAA==.Necrosector:BAAANQAECgcIEQAAAA==.Nelandra:BAAANQAECgIIAgAAAA==.Neongrasp:BAAANQAECgYIBgAAAA==.Nerazlyn:BAAANQADCgMIAwAAAA==.',
Ni='Nickflare:BAAANQAECgIIAgAAAA==.',
No='Nomahuata:BAABNQAECoEbAAIZAAgKJA5+UgDeAQAZAAgKJA5+UgDeAQAAAA==.',
Nu='Nufrus:BAAANQAECgIIAgAAAA==.Nurgle:BAAANQADCgUIBQAAAA==.',
Ny='Nyeli:BAAANQAECgIIAwAAAA==.Nyxi:BAAANQAECgIIAwAAAA==.',
['Né']='Néo:BAAANQAECgIIAgAAAA==.',
On='Onefiftyone:BAAANQAECgUICwAAAA==.',
Pa='Palochka:BAAANQAECgIIAgAAAA==.Palpetine:BAAANQADCgYJEAAAAA==.Paltator:BAAANQAECgUICwAAAA==.Pandazuken:BAAANQAECgcIEQAAAA==.Paradots:BAABNQAECoEmAAIMAAkKSRvnCgDSAgAMAAkKSRvnCgDSAgAAAA==.Paranitis:BAAANQADCggJCAAAAA==.Paraparaboom:BAAANQAECgUIDgAAAA==.',
Ph='Phatboi:BAAANQADCgQIBAAAAA==.Pheroth:BAAANQADCgYIDAABNQADCggIJQAFAAAAAA==.',
Pi='Pixpax:BAAANQAECgYICwAAAA==.Pixyofdeath:BAAANQADCggIAwABNQAECgIIAgAFAAAAAA==.Pixystix:BAAANQAECgIIAgAAAA==.',
Po='Pomortem:BAAANQAECgQIBQAAAA==.Potsomancy:BAACNQAFFIEHAAIaAAUK/BJ5EAClAQAaAAUK/BJ5EAClAQA1AAQKgRwAAhoACQo0JCA0AAUDABoACQo0JCA0AAUDAAAA.',
Pr='Profian:BAAANQADCgcIBwAAAA==.',
Ra='Radioshack:BAAANQADCgUIBQABNQADCggIJgAFAAAAAA==.Raivel:BAAANQAECgIIAgABNQAECgIIAwAFAAAAAA==.Rambogg:BAAANQADCgMIAwABNQAECgkJIQAaABIaAA==.Raneyth:BAAANQAECgIIAgAAAA==.Ranoku:BAAANQADCgYIBgAAAA==.Ravusternath:BAAANQADCgYIBgAAAA==.',
Re='Redwinetoast:BAAANQAECgIIAgAAAA==.Reignblade:BAAANQABCgIIAwAAAA==.Reno:BAAANQAECgUIDgAAAA==.Reposess:BAAANQABCggIEQAAAA==.Reshyk:BAAANQADCggIGQAAAA==.',
Rh='Rhobes:BAAANQADCgcIFAAAAA==.',
Ri='Rickkrolled:BAAANQAECgEIAQAAAA==.Riordaa:BAAANQAECgIIAgAAAA==.',
Ro='Roboskritch:BAAANQADCgUJBwABNQADCgUICQAFAAAAAA==.Rowene:BAAANQADCgYIFgAAAA==.',
Ru='Rumor:BAAANQAECgIIBQAAAA==.Rurry:BAACNQAFFIENAAIMAAQKBh62BwB7AQAMAAQKBh62BwB7AQA1AAQKgSAAAwwACQprI/gCAHwDAAwACQprI/gCAHwDAA8AAQohJZMsAGwAAAAA.',
Ry='Ryuuki:BAAANQAECgcIEwAAAA==.',
['Rï']='Rïzzler:BAEBNQAECoEeAAMGAAkKJhnLIgAPAgAGAAcKwRnLIgAPAgAbAAYKYxThIgCKAQAAAA==.',
Sa='Safetysham:BAAANQADCgcICwAAAA==.Saffia:BAAANQABCgUIBAAAAA==.Saleos:BAAANQADCgYJBgAAAA==.Sall:BAAANQADCgQIBAABNQADCgUICQAFAAAAAA==.Salmoo:BAAANQAECgUIBgAAAA==.Saltytator:BAAANQAECgMIBQAAAA==.Savonah:BAAANQADCggIGAAAAA==.',
Sc='Scaledaddy:BAAANQAECgUICQAAAA==.Scallion:BAAANQADCggICwABNQAECgcIEQAFAAAAAA==.Scaryl:BAAANQAECgUIBwAAAA==.Schneè:BAABNQAECoEhAAIXAAgKABMPEQC4AQAXAAgKABMPEQC4AQAAAA==.Scoom:BAACNQAFFIENAAIaAAQK+hszFgBlAQAaAAQK+hszFgBlAQA1AAQKgSgAAhoACQruJLINAJIDABoACQruJLINAJIDAAAA.Scourgespawn:BAACNQAFFIEKAAMcAAQKiBSsBQA5AQAcAAQKiBSsBQA5AQARAAEKYQcUFwBBAAA1AAQKgSUAAxwACQoFIxYKACEDABwACQoFIxYKACEDABEAAwqkCdGOAIAAAAAA.',
Se='Seikyo:BAAANQAECgYIEQAAAA==.Seilah:BAAANQADCgUIBwABNQAECgQICQAFAAAAAA==.Selenë:BAAANQAECgQIBQAAAA==.Serok:BAAANQAECgYIDgAAAA==.',
Sh='Shadowbox:BAAANQADCgMIAwAAAA==.Shadyaf:BAAANQAECgMJAwAAAA==.Shailora:BAAANQADCgQIBAAAAA==.Shalis:BAAANQADCggIHwAAAA==.Sharivee:BAAANQAECgIIAgAAAA==.Shazamir:BAAANQAECgQIBwAAAA==.Shibui:BAAANQAECgYIDgAAAA==.Shifthead:BAABNQAECoEiAAMYAAkKsRjYCABVAgAYAAgK4BnYCABVAgAdAAkKPhBXLgAnAgAAAA==.Shockazilla:BAAANQAECgYIDAAAAA==.Shortspanky:BAAANQAECgQIBgAAAA==.',
Si='Silaveen:BAAANQABCgIIAgAAAA==.Silverhorn:BAAANQAECgUIDAAAAA==.',
Sk='Skoduh:BAAANQAECgQIBQAAAA==.',
Sl='Slack:BAAANQAECgMJBgABNQAECgUIDgAFAAAAAA==.Sluggo:BAACNQAFFIELAAIWAAQKTRIYCQBNAQAWAAQKTRIYCQBNAQA1AAQKgSEAAhYACQpTH2wxAMUCABYACQpTH2wxAMUCAAAA.',
Sm='Smokeü:BAAANQADCggICgAAAA==.',
So='Solinaara:BAAANQABCgQIBAAAAA==.Soraka:BAAANQAECgEIAQAAAA==.',
St='Stonedalways:BAAANQAECgIIAwAAAA==.Stonytoni:BAAANQAECgEIAQAAAA==.',
Su='Sunfuri:BAAANQAECgYJCgAAAA==.Sus:BAACNQAFFIEMAAIJAAQKvhUkCABHAQAJAAQKvhUkCABHAQA1AAQKgSIAAwkACQr+IAAQAO0CAAkACQr+IAAQAO0CAB4ABAoJCVwYAL8AAAAA.Susanoo:BAAANQAECgYIBgAAAA==.',
Ta='Taalia:BAAANQAECgIIAgAAAA==.Talonas:BAAANQAECgIIAgAAAA==.Tarathor:BAAANQAECgIIAgAAAA==.Tatortott:BAAANQADCgMIAwAAAA==.',
Te='Teknofarious:BAAANQAECgUIDQAAAA==.',
Th='Thesafe:BAAANQAECgIIAgAAAA==.Thevin:BAAANQAECgUICQABNQAECgUIDgAFAAAAAA==.Thialia:BAAANQAECgUIEAABNQAECgYIDAAFAAAAAA==.Thickems:BAAANQAECgYIDwAAAA==.Thoralon:BAAANQAECgIIAgAAAA==.',
Ti='Tinkabella:BAAANQAECgYIEQAAAA==.',
To='Torrey:BAAANQADCgIIAgAAAA==.',
Tr='Trek:BAAANQAECgIIAgAAAA==.Trema:BAAANQAECgYIEQAAAA==.Trix:BAAANQADCggIFgAAAA==.',
Ts='Tserendelgor:BAAANQAECgUIBQABNQAECggIGQAGAGYcAA==.',
Tu='Tulsi:BAAANQAECgMIBQAAAA==.',
Ty='Tyronos:BAAANQAECgIIAgAAAA==.',
Va='Vaeltharion:BAAANQAECgIIAgAAAA==.Varedrae:BAAANQADCggICAAAAA==.Vas:BAAANQADCgYIDgAAAA==.',
Ve='Verdandi:BAAANQADCgcIDQAAAA==.Vevicenth:BAAANQAECgUICAAAAA==.',
Vo='Voranth:BAAANQAECgQIBwAAAA==.',
Wa='Warenio:BAAANQAECgYIDwAAAA==.Warick:BAAANQADCgIIAgAAAA==.Warpsbulge:BAABNQAECoEYAAMUAAkKlRquBgBIAgAUAAkKHxeuBgBIAgAaAAYKtx3qmgAGAgAAAA==.Wayawoman:BAAANQABCgIIAgABNQAECgIIAgAFAAAAAA==.',
Wh='Whakan:BAAANQADCggIGAABNQAECgMIBQAFAAAAAA==.',
Wo='Wolfos:BAAANQAECgIIBgAAAA==.',
Wt='Wtfox:BAEANQAECgYIDAAAAA==.',
Wy='Wysteri:BAAANQAECgQIBAAAAA==.',
Xa='Xalatos:BAAANQAECgYICQAAAA==.Xalfein:BAAANQADCggIFAAAAA==.',
Xi='Xinu:BAAANQADCgIIAgABNQAECgYIDgAFAAAAAA==.',
Xo='Xolani:BAAANQAECgQIAwAAAA==.',
Ya='Yanakana:BAAANQADCggIFwAAAA==.',
Za='Zakeko:BAAANQAECgIIAgAAAA==.Zanderpryde:BAAANQADCggIDgABNQAECggIHAASAAwdAA==.',
Ze='Zenus:BAAANQAECgIJAgAAAA==.Zesty:BAAANQADCgIJAgAAAA==.Zeusinator:BAAANQAECgQIBAAAAA==.',
Zf='Zfatpanda:BAAANQADCggICAAAAA==.',
Zi='Zinu:BAAANQAECgYIDgAAAA==.',
Zu='Zukarius:BAAANQADCgUIBQABNQAECgUICQAFAAAAAA==.Zulfionn:BAAANQAECgIIAwAAAA==.Zurok:BAAANQADCgcIBwABNQAECgUIDgAFAAAAAA==.',
['Áy']='Áyrá:BAAANQAECgIIAgAAAA==.',
['Øu']='Øuroboros:BAAANQAECgMIBQAAAA==.',
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
