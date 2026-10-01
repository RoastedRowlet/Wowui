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

local lookup = {'Paladin-Retribution','Paladin-Holy','Druid-Balance','Unknown-Unknown','Hunter-BeastMastery','DeathKnight-Blood','Mage-Frost','Mage-Arcane','Mage-Fire','Paladin-Protection','Monk-Windwalker','Warrior-Protection','Warrior-Arms','Priest-Shadow','Monk-Brewmaster','Monk-Mistweaver','Druid-Restoration','Evoker-Devastation','DemonHunter-Havoc','Warlock-Destruction','Warlock-Demonology','Hunter-Marksmanship','Shaman-Elemental','DemonHunter-Devourer','DemonHunter-Vengeance','Priest-Holy','Evoker-Preservation','Shaman-Restoration','Hunter-Survival','Druid-Guardian','DeathKnight-Unholy','DeathKnight-Frost',}
local provider = {region='US',realm='Maiev',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aayron:BAAANQADCgIIAgAAAA==.',
Ab='Abadizzo:BAAANQAECggIAwAAAA==.Abadizzoo:BAAANQAECggIBAAAAA==.Abeyancë:BAABNQAECoEhAAMBAAgKMhhOWwAwAgABAAgKMhhOWwAwAgACAAIK8RIF1ABzAAAAAA==.Abilities:BAAANQABCgYIDAAAAA==.',
Ae='Aeshanth:BAAANQADCgUIBgAAAA==.',
Ai='Airwrecka:BAABNQAECoEiAAIDAAgKnBuTIQCLAgADAAgKnBuTIQCLAgAAAA==.Aite:BAAANQADCgYIBgAAAA==.',
Al='Altlas:BAAANQADCggIEAAAAA==.',
Am='Amaterasu:BAAANQADCgYIBgABNQAECgEIAQAEAAAAAA==.',
An='Anise:BAAANQADCgEJAQAAAA==.',
Ar='Arahgon:BAEBNQAECoEWAAIBAAcKyxWrdwDdAQABAAcKyxWrdwDdAQABNQAECggIDAAEAAAAAA==.Artvandelay:BAAANQAECgQIBAABNQAECggIGQAFANQfAA==.',
As='Asukà:BAAANQAECgYIDgAAAA==.',
Au='Auchenile:BAAANQAECgYIEQAAAA==.Austin:BAAANQAECgIIAQAAAA==.Austinthedog:BAAANQAECggICAAAAA==.',
Av='Avanoura:BAAANQADCggICAABNQAECgIIAgAEAAAAAA==.',
['Aé']='Aéd:BAAANQADCgQIBAABNQADCgcIEwAEAAAAAA==.',
Ba='Barkthas:BAAANQAECgUICgAAAA==.',
Be='Bellarg:BAAANQAECgYIDAAAAA==.Belobog:BAAANQAECgUIBQAAAA==.Belyn:BAAANQAECgQIBgAAAA==.',
Bi='Bifesor:BAAANQADCgMIAwAAAA==.Bizmania:BAAANQADCgQIBAAAAA==.',
Bl='Blackhøof:BAAANQADCgUIBwAAAA==.',
Bo='Bonedaddy:BAAANQAECgUIBgAAAA==.',
Br='Bratlax:BAAANQAECgQIBAABNQAFFAUICgABALUgAA==.Bro:BAAANQAECgcIEgAAAA==.Brolich:BAABNQAECoEiAAIGAAgKaxLVOADjAQAGAAgKaxLVOADjAQABNQAECgcIEgAEAAAAAA==.Broo:BAAANQAECgQIBAABNQAECgcIEgAEAAAAAA==.Brooak:BAAANQAECgMIBAABNQAECgcIEgAEAAAAAA==.Brother:BAAANQAECgIIAgABNQAECgcIEgAEAAAAAA==.Brozeit:BAAANQAECgUIBQABNQAECgcIEgAEAAAAAA==.',
Bu='Bubblegump:BAAANQAECgUIBQAAAA==.',
Ca='Calculusx:BAAANQAECgUICQAAAA==.Camión:BAAANQADCgYIBgAAAA==.',
Ce='Cellice:BAACNQAFFIEXAAMHAAcKQRcYAQARAQAIAAYKABgiBwASAgAHAAMKyRQYAQARAQA1AAQKgSQABAgACQqAI5goACgDAAgACQrqIpgoACgDAAkAAwqfIbsEABEBAAcAAQosJUsuAFIAAAAA.',
Ch='Chad:BAAANQADCgQIBAAAAA==.Chuckborris:BAAANQADCgEJAQABNQAECgkJHQAKAMIgAA==.',
Cl='Clare:BAAANQAECggIEQAAAA==.Cloúd:BAAANQAECgIIAgAAAA==.',
Da='Daddydimes:BAABNQAECoEWAAILAAgK1xcQGAA0AgALAAgK1xcQGAA0AgAAAA==.',
De='Deathfu:BAAANQABCgYIBgAAAA==.Deathless:BAAANQAECgUIEwAAAA==.Demiize:BAAANQAECgYIDwAAAA==.Demize:BAABNQAECoEhAAIFAAgK/RulKAC6AgAFAAgK/RulKAC6AgAAAA==.Demíze:BAAANQAECgMIAwAAAA==.Deshield:BAABNQAECoEdAAMMAAgKOyYoAgBzAwAMAAgKMyYoAgBzAwANAAgKNyFMLwDRAgAAAA==.Deus:BAAANQAECgYIEQAAAA==.Dewry:BAABNQAECoEXAAIOAAgKNR+iDwDHAgAOAAgKNR+iDwDHAgAAAA==.',
Dh='Dhudamuthi:BAABNQAECoEeAAMPAAgK9yMLAwBCAwAPAAgK9yMLAwBCAwALAAIKthYZSQBpAAAAAA==.',
Di='Divine:BAAANQAECgQIBAABNQAECggIHgAQABATAA==.Dizzo:BAAANQAECggIEgAAAA==.',
Do='Doink:BAAANQAECgYICwABNQAECgkJKgARABUiAA==.Donnajuan:BAAANQAECgcIEgAAAA==.Dornath:BAAANQADCggIEAAAAA==.',
Dr='Draaxelro:BAAANQADCgUIDAAAAA==.Dragontiddys:BAAANQADCgIIAgAAAA==.Drakaris:BAAANQADCgcIBwAAAA==.',
Ed='Edgeillus:BAAANQADCgMIBAABNQAFFAUICgASADcZAA==.',
El='Elimere:BAABNQAECoEjAAIOAAgKpgw7IwDJAQAOAAgKpgw7IwDJAQAAAA==.Elvarg:BAABNQAECoEcAAISAAgKORtNCgCdAgASAAgKORtNCgCdAgAAAA==.Elywen:BAABNQAECoEhAAIFAAkK7B57EQA0AwAFAAkK7B57EQA0AwAAAA==.',
En='Enry:BAAANQADCggIEAAAAA==.',
Eq='Eqlipse:BAAANQADCgYIBgAAAA==.',
Es='Esira:BAAANQADCgIIAgAAAA==.',
Ev='Evién:BAAANQADCggICAAAAA==.',
Fi='Fiammetta:BAEANQADCgcIBwABNQAFFAUIDAAKAJgZAA==.Finke:BAAANQAECgQICQAAAA==.Firemge:BAEANQAECgUIBQABNQAFFAcIDwAKAHkWAA==.Fistzz:BAAANQADCgIIAgAAAA==.',
Fl='Flickerbeat:BAAANQAECgQIBwAAAA==.',
Fr='Free:BAAANQAECgQICwAAAA==.',
Fu='Futurama:BAAANQADCgQIBAAAAA==.',
Ga='Gabi:BAAANQABCgIIAgAAAA==.',
Gd='Gdizz:BAABNQAECoEeAAIIAAkKCg47mwAFAgAIAAkKCg47mwAFAgAAAA==.',
Gh='Ghostshadows:BAAANQAECgUIDwAAAA==.',
Gi='Gigazapper:BAAANQAECgUIDAABNQAECgkJHQAKAMIgAA==.Gizzlit:BAAANQAECgYIDQAAAA==.',
Go='Gobiasinds:BAAANQAECgIJAwABNQAECgkJLAATAH4kAA==.Gofetch:BAAANQAECgYIEgAAAA==.',
Gr='Grandgoop:BAAANQAECgIJAgAAAA==.Grissum:BAABNQAECoEZAAIFAAgK1B9XIwDRAgAFAAgK1B9XIwDRAgAAAA==.',
Gs='Gson:BAAANQADCggICAAAAA==.',
Gu='Guppy:BAAANQADCgYIBgAAAA==.',
Ha='Hac:BAAANQAECgUIBwABNQAECgcICQAEAAAAAA==.Hakka:BAAANQAECgcICQAAAA==.Hallack:BAAANQAECgYIBwAAAA==.',
He='Healingkiss:BAAANQADCggIFwAAAA==.',
Hi='Hikingboots:BAAANQAECgUIDgAAAA==.',
Ho='Hollypallz:BAAANQAECgIIAgAAAA==.Holymages:BAAANQAECgcIEQAAAA==.',
Ik='Iknowaguy:BAAANQAECgQICAAAAA==.',
Il='Illani:BAAANQAECgEJAwAAAA==.Ilyanna:BAABNQAECoEiAAMUAAgK8htIBgCYAgAUAAgK8htIBgCYAgAVAAYKkgo2kABZAQAAAA==.',
Im='Im:BAACNQAFFIEMAAIWAAUKPyO5AwD6AQAWAAUKPyO5AwD6AQA1AAQKgSwAAxYACQpLJRoCALcDABYACQpLJRoCALcDAAUAAQr0JbL/AGgAAAAA.Imscary:BAAANQAECgEIAQAAAA==.',
It='Itooktheflag:BAAANQADCgMIAwAAAA==.',
Iz='Izzo:BAAANQAECggICAAAAA==.',
Ja='Jausi:BAAANQAECgQIBgAAAA==.',
Je='Jenyaa:BAAANQADCggICAAAAA==.',
Jh='Jhops:BAABNQAECoEZAAIXAAgKkhe7OgBCAgAXAAgKkhe7OgBCAgAAAA==.',
Ji='Jilliadk:BAAANQAECgEIAQAAAA==.Jirachi:BAAANQADCggIEwAAAA==.',
Ke='Keju:BAAANQAECgEJAQAAAA==.Kerrigan:BAABNQAECoEdAAMYAAkKwRloGwBFAgAYAAgKxhtoGwBFAgATAAEKoQkIcQA6AAAAAA==.',
Ko='Kookler:BAAANQADCgUIBQABNQAECggIEwAEAAAAAA==.Kookluhh:BAAANQAECgUIBQABNQAECggIEwAEAAAAAA==.Kozand:BAAANQADCgMIAwABNQADCgcIEwAEAAAAAA==.',
Ku='Kuji:BAAANQAECgQICAAAAA==.',
Ky='Kyirr:BAAANQAECggJEQAAAA==.Kyralen:BAAANQABCgQIBQABNQAECgYIEQAEAAAAAA==.',
La='Layke:BAAANQADCggIEwAAAA==.Lazerbeampew:BAAANQAECgcIEQAAAA==.',
Li='Lilli:BAEANQADCggICAABNQAFFAUIDAAKAJgZAA==.',
Ll='Llynryn:BAAANQAECgIIAgAAAA==.',
Lo='Locktuah:BAAANQAECgQIBAABNQADCgcIEwAEAAAAAA==.Loklak:BAAANQADCgcIBwABNQAECgEIAQAEAAAAAA==.',
Ma='Magicae:BAABNQAECoEoAAIIAAkKkyHnFgBoAwAIAAkKkyHnFgBoAwABNQAFFAcIFAAYADQeAA==.Magicmanzz:BAAANQAECgQIBQAAAA==.Magnifuso:BAAANQAECgIIBAAAAA==.Maguapa:BAAANQAECgQICAAAAA==.Malgata:BAAANQAECgIIBAAAAA==.Margarita:BAAANQADCgQIBAAAAA==.Masstech:BAABNQAECoEZAAIBAAgKYxa4WQA2AgABAAgKYxa4WQA2AgAAAA==.Mastab:BAABNQAECoEeAAICAAgKBhtaLgBzAgACAAgKBhtaLgBzAgAAAA==.',
Mc='Mchammerdin:BAAANQAECgYIDQAAAA==.',
Me='Meat:BAABNQAECoEVAAMZAAcK3xvJCAAHAgAZAAYKrR7JCAAHAgATAAEKBwtscgA2AAAAAA==.',
Mi='Mikio:BAAANQAECgUIDAAAAA==.Milinka:BAABNQAECoEhAAIaAAgKBRu6KQCFAgAaAAgKBRu6KQCFAgAAAA==.Mirror:BAAANQAECgYIBwABNQAECggIIwAYAIcjAA==.',
Mo='Moiryn:BAAANQADCgIJAgAAAA==.',
My='Myshaman:BAAANQAECgUIDQAAAA==.',
Na='Navillus:BAACNQAFFIEKAAISAAUKNxlqAgC9AQASAAUKNxlqAgC9AQA1AAQKgVAAAxIACQpqJkgAAPEDABIACQpqJkgAAPEDABsABgptHgMYAAMCAAAA.',
No='Noxi:BAAANQAECgQICgAAAA==.',
Oa='Oakensoul:BAAANQAECgEIAQABNQAECggIHwAKAN0kAA==.',
Og='Ogron:BAAANQADCgYIBgABNQAECggIHQAMADsmAA==.',
Op='Ophindis:BAABNQAECoEWAAIGAAcKaBruMAAMAgAGAAcKaBruMAAMAgAAAA==.',
Os='Osten:BAAANQAECgQIBAAAAA==.',
Pa='Pagoda:BAABNQAECoEeAAMQAAgKEBPrFADXAQAQAAgKEBPrFADXAQALAAQKVxNkNgDxAAAAAA==.Panerai:BAAANQADCgYIBgAAAA==.',
Pe='Pewpop:BAABNQAECoEZAAIFAAYK4CEiTgA2AgAFAAYK4CEiTgA2AgAAAA==.',
Pi='Pintsize:BAAANQABCgcJCQAAAA==.',
Pj='Pjt:BAAANQADCgEIAQAAAA==.',
Pr='Praystation:BAAANQADCgIJAgAAAA==.',
Pu='Putemuptoo:BAAANQAECgEIAQAAAA==.',
Py='Pyosi:BAAANQADCggICAAAAA==.',
Qp='Qpti:BAABNQAECoEZAAINAAkK4BKWXwAnAgANAAkK4BKWXwAnAgAAAA==.',
Ra='Razorclaw:BAAANQADCgEIAQABNQAECgUICwAEAAAAAA==.Razz:BAAANQABCgcIBgAAAA==.',
Re='Rejectlol:BAABNQAECoEZAAIBAAgKfRDgfwDFAQABAAgKfRDgfwDFAQAAAA==.Rennx:BAACNQAFFIEYAAIDAAcKgxycAQCaAgADAAcKgxycAQCaAgA1AAQKgR0AAgMACQowJcoEAKUDAAMACQowJcoEAKUDAAAA.Reznik:BAABNQAECoEZAAIGAAgKrRNEOADmAQAGAAgKrRNEOADmAQAAAA==.',
Ri='Rika:BAAANQAECgEIAQAAAA==.Ringmasta:BAAANQADCggIJgAAAA==.Riot:BAABNQAECoEiAAIFAAgKYBtdLwCeAgAFAAgKYBtdLwCeAgAAAA==.',
Ro='Rosé:BAAANQAFFAEIAQAAAA==.Rowen:BAAANQAECgUICwAAAA==.',
['Rè']='Rènza:BAAANQAECggIBgAAAA==.',
Sa='Saintlorric:BAAANQABCgQIBAAAAA==.Sanguineous:BAAANQAECgIIBAABNQAECgcIEQAEAAAAAA==.Saphia:BAECNQAFFIEMAAIKAAUKmBlqAgCeAQAKAAUKmBlqAgCeAQA1AAQKgR8AAgoACQq0I+4DAFYDAAoACQq0I+4DAFYDAAAA.Saphyr:BAEANQAECggIEgABNQAFFAUIDAAKAJgZAA==.',
Sb='Sblakedragon:BAAANQADCggICAAAAA==.',
Sc='Scarydude:BAAANQAECgcIDwAAAA==.',
Se='Sevrin:BAABNQAECoEfAAILAAgKyhwwEgCGAgALAAgKyhwwEgCGAgAAAA==.',
Sh='Shamoon:BAAANQAECgQIBQAAAA==.Shamwow:BAAANQAECgQICQABNQAECgUIBQAEAAAAAA==.Sheesh:BAABNQAECoEqAAMRAAkKFSJIBQBOAwARAAkKFSJIBQBOAwADAAQK7BIwYwDsAAAAAA==.Shinru:BAABNQAECoEpAAICAAgKqiHTFQD+AgACAAgKqiHTFQD+AgAAAA==.Shrikedk:BAAANQADCgIIAgABNQAECggIEQAEAAAAAA==.',
Si='Sickdayze:BAAANQAECgYIEgAAAA==.Sickhymns:BAAANQAECgMIAwABNQAECgYIEgAEAAAAAA==.Sickntired:BAAANQADCgMJAwABNQAECgYIEgAEAAAAAA==.Sicktides:BAAANQADCgYICAABNQAECgYIEgAEAAAAAA==.',
Sk='Skinnymini:BAAANQADCgEIAQAAAA==.',
Sl='Slyxxar:BAABNQAECoEeAAIcAAcKLRXvWgCrAQAcAAcKLRXvWgCrAQAAAA==.',
Sn='Snaffu:BAAANQADCgUIBQAAAA==.Snoopyy:BAAANQADCgcIBwAAAA==.',
So='Soar:BAAANQAECgUICwAAAA==.Soph:BAABNQAECoEYAAIRAAgKjiPoBgAtAwARAAgKjiPoBgAtAwABNQAFFAUICgABALUgAA==.Sophie:BAACNQAFFIEKAAIBAAUKtSAYAwD5AQABAAUKtSAYAwD5AQA1AAQKgSkAAgEACQpoJmoDANUDAAEACQpoJmoDANUDAAAA.Sophisticate:BAABNQAECoEXAAIdAAgKER9SAgDqAgAdAAgKER9SAgDqAgABNQAFFAUICgABALUgAA==.Sophiz:BAAANQAECggIEQABNQAFFAUICgABALUgAA==.Sophlax:BAABNQAECoEZAAIaAAYK0R5NRAAOAgAaAAYK0R5NRAAOAgABNQAFFAUICgABALUgAA==.Sophs:BAAANQAECgQIDwABNQAFFAUICgABALUgAA==.Sophz:BAAANQAECgYICwABNQAFFAUICgABALUgAA==.Sox:BAABNQAECoEiAAIeAAgKxiV4AgBvAwAeAAgKxiV4AgBvAwAAAA==.',
Sp='Spicynoodle:BAABNQAECoEcAAIFAAgK7hgUPQBsAgAFAAgK7hgUPQBsAgAAAA==.Spookyougi:BAAANQAECgQICwAAAA==.',
Sq='Squattinchop:BAAANQAECgYIDwAAAA==.',
St='Stabamon:BAAANQADCggICAAAAA==.Stiffcrit:BAAANQAECgUIEAAAAA==.',
Su='Sua:BAACNQAFFIETAAINAAcKRBMtBAA+AgANAAcKRBMtBAA+AgA1AAQKgR4AAg0ACQpsIKccACUDAA0ACQpsIKccACUDAAAA.Suksuksuk:BAAANQABCgQICAAAAA==.Supergogeta:BAABNQAECoEYAAMRAAgKVBUOHAAAAgARAAgKVBUOHAAAAgADAAUKpQnKXgAAAQAAAA==.',
Sy='Sylvie:BAAANQAECgcIEQAAAA==.Synistër:BAAANQADCgYIDgAAAA==.',
['Sï']='Sïnsu:BAABNQAECoEYAAINAAgKyBXYZgARAgANAAgKyBXYZgARAgAAAA==.',
Ta='Takoda:BAAANQAECgQIBQAAAA==.Talauyia:BAAANQAECgIIAgAAAA==.Tankyou:BAAANQADCgYIBgAAAA==.',
Te='Temporë:BAAANQAECgEIAQAAAA==.',
Th='Thicness:BAAANQADCgUIBQAAAA==.Thndrsquirel:BAAANQAECgEIAQABNQAECgQICAAEAAAAAA==.Thrayne:BAAANQABCgMIAwAAAA==.',
Ti='Tiriandrel:BAAANQADCggICAABNQAECgcIFgAGAGgaAA==.',
To='Toofaded:BAAANQADCgUIBQAAAA==.Torio:BAAANQAECgYIEQAAAA==.',
Tw='Twofow:BAAANQAECgIIBAAAAA==.',
Ty='Tyranis:BAEANQAECggIDAAAAA==.Tyê:BAABNQAECoEYAAIbAAcK4xYSGQDzAQAbAAcK4xYSGQDzAQAAAA==.',
['Té']='Témalabécane:BAABNQAECoEbAAIIAAkKZSDjHwBGAwAIAAkKZSDjHwBGAwAAAA==.',
['Të']='Tërry:BAAANQADCgEIAQAAAA==.',
Va='Vael:BAAANQADCgYIBgAAAA==.Valexisea:BAAANQAECgUJBwAAAA==.Valériana:BAAANQADCgIIAgAAAA==.Vanítas:BAAANQADCgcIBgAAAA==.',
Vi='Visable:BAAANQAECgUIBwAAAA==.',
Vo='Voltage:BAAANQAECgQIDQABNQAECgYIGQAFAOAhAA==.',
Vu='Vulgnash:BAABNQAECoEkAAIfAAgKTCNXEQD7AgAfAAgKTCNXEQD7AgAAAA==.Vult:BAABNQAECoEfAAIgAAgKkRnHHgBHAgAgAAgKkRnHHgBHAgAAAA==.',
Wa='Water:BAAANQAECgIIAgAAAA==.',
We='Welgo:BAAANQAECgQIBgAAAA==.Welmage:BAAANQAECgIIAgABNQAECgQIBgAEAAAAAA==.',
Wi='Wickeddemon:BAAANQADCggIIAAAAA==.Windtusk:BAAANQADCggJCQAAAA==.',
Xc='Xcesive:BAAANQADCggJDQAAAA==.Xcessiv:BAAANQADCgQIBAAAAA==.Xcéssiv:BAABNQAECoEYAAIIAAgKSRz4XgCUAgAIAAgKSRz4XgCUAgAAAA==.',
Xe='Xerra:BAABNQAECoEeAAIYAAkKDBqSEADGAgAYAAkKDBqSEADGAgAAAA==.',
['Xû']='Xûrû:BAAANQADCgQIBAAAAA==.',
Ye='Yeast:BAAANQAECgYIBgAAAA==.',
Yr='Yravengi:BAAANQAECgQIBAAAAA==.Yrel:BAAANQADCgcIEwAAAA==.',
Ze='Zeit:BAAANQAECgMIAwABNQAECgcIEgAEAAAAAA==.Zelgie:BAABNQAECoEYAAICAAgKwRdxLQB4AgACAAgKwRdxLQB4AgAAAA==.',
Zi='Zienna:BAAANQADCgcICQAAAA==.Zin:BAAANQADCgYIDAAAAA==.',
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
