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

local lookup = {'Paladin-Retribution','Druid-Balance','Unknown-Unknown','DeathKnight-Blood','Mage-Arcane','Mage-Frost','Mage-Fire','Paladin-Protection','Hunter-BeastMastery','Warrior-Protection','Warrior-Arms','Druid-Restoration','Priest-Shadow','DemonHunter-Havoc','Warlock-Destruction','Warlock-Demonology','Hunter-Marksmanship','DemonHunter-Devourer','Rogue-Subtlety','Paladin-Holy','Priest-Holy','Evoker-Devastation','Evoker-Preservation','Monk-Mistweaver','Monk-Windwalker','Shaman-Restoration','Druid-Guardian','DeathKnight-Unholy','DeathKnight-Frost',}
local provider = {region='US',realm='Maiev',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abeyancë:BAABNQAECoEaAAIBAAgKUhdaRgA6AgABAAgKUhdaRgA6AgAAAA==.Abilities:BAAANQABCgYIDAAAAA==.',
Ae='Aeshanth:BAAANQADCgUIBgAAAA==.',
Ai='Airwrecka:BAABNQAECoEaAAICAAgK1xePIwBQAgACAAgK1xePIwBQAgAAAA==.',
Al='Altlas:BAAANQADCggIEAAAAA==.',
Am='Amaterasu:BAAANQADCgYIBgABNQAECgEIAQADAAAAAA==.',
An='Anise:BAAANQADCgEJAQAAAA==.',
Ar='Arahgon:BAEANQAECgcIDwABNQAECggIBAADAAAAAA==.',
As='Asukà:BAAANQAECgQICAAAAA==.',
Au='Auchenile:BAAANQAECgUICwAAAA==.Austin:BAAANQAECgIIAQAAAA==.',
Av='Avanoura:BAAANQABCgQIBAABNQAECgIIAgADAAAAAA==.',
['Aé']='Aéd:BAAANQADCgQIBAABNQAECgQIBAADAAAAAA==.',
Ba='Barkthas:BAAANQAECgQIBgAAAA==.',
Be='Bellarg:BAAANQAECgQIBgAAAA==.Belobog:BAAANQAECgUJBQAAAA==.Belyn:BAAANQAECgIJAgAAAA==.',
Bi='Bifesor:BAAANQADCgMIAwAAAA==.Bizmania:BAAANQADCgQIBAAAAA==.',
Bl='Blackhøof:BAAANQADCgUIBwAAAA==.',
Br='Bratlax:BAAANQADCgIIAgABNQAECgkJJAABAGgmAA==.Bro:BAAANQAECgcICwAAAA==.Brolich:BAABNQAECoEcAAIEAAgKfQ8RNwC8AQAEAAgKfQ8RNwC8AQABNQAECgcICwADAAAAAA==.Broo:BAAANQADCggICAABNQAECgcICwADAAAAAA==.Brooak:BAAANQAECgMIAwABNQAECgcICwADAAAAAA==.Brozeit:BAAANQADCggICAABNQAECgcICwADAAAAAA==.',
Bu='Bubblegump:BAAANQAECgUIBQAAAA==.',
Ca='Calculusx:BAAANQAECgQJCAAAAA==.Camión:BAAANQADCgYIBgAAAA==.',
Ce='Cellice:BAACNQAFFIERAAMFAAYKxRfgAwArAgAFAAYKxRfgAwArAgAGAAEKfR9OBQBcAAA1AAQKgSQABAUACQqAI8cbAEcDAAUACQrqIscbAEcDAAcAAwqfIeUDAB0BAAYAAQosJdElAFgAAAAA.',
Ch='Chad:BAAANQADCgQIBAAAAA==.Chuckborris:BAAANQADCgEJAQABNQAECgkJGgAIAH4fAA==.',
Cl='Clare:BAAANQAECgcIDwAAAA==.Cloúd:BAAANQADCgUJBQAAAA==.',
Da='Daddydimes:BAAANQAECgUIDgAAAA==.',
De='Deathfu:BAAANQABCgYIBgAAAA==.Deathless:BAAANQAECgUJDgAAAA==.Demiize:BAAANQAECgUICQAAAA==.Demize:BAABNQAECoEcAAIJAAgKYRrMIQCzAgAJAAgKYRrMIQCzAgAAAA==.Deshield:BAABNQAECoEaAAMKAAgK2SVuAwAKAwAKAAcKBiZuAwAKAwALAAgKNyG0IgDrAgAAAA==.Deus:BAAANQAECgUICwAAAA==.Dewry:BAAANQAECgYIDgAAAA==.',
Dh='Dhudamuthi:BAAANQAECgYJEgAAAA==.',
Di='Dizzo:BAAANQAECggIDgAAAA==.',
Do='Doink:BAAANQAECgQIBQABNQAECgkJIwAMAIIhAA==.Donnajuan:BAAANQAECgYJDAAAAA==.Dornath:BAAANQADCggICAAAAA==.',
Dr='Draaxelro:BAAANQADCgUIDAAAAA==.Dragontiddys:BAAANQADCgIIAgAAAA==.',
El='Elimere:BAABNQAECoEcAAINAAgK+wgMIAC+AQANAAgK+wgMIAC+AQAAAA==.Elvarg:BAAANQAECgYJEAAAAA==.Elywen:BAABNQAECoEZAAIJAAgK1x0OHQDMAgAJAAgK1x0OHQDMAgAAAA==.',
En='Enry:BAAANQADCggIEAAAAA==.',
Eq='Eqlipse:BAAANQADCgYIBgAAAA==.',
Es='Esira:BAAANQADCgIIAgAAAA==.',
Ev='Evién:BAAANQADCggICAAAAA==.',
Fi='Fiammetta:BAEANQADCgcIBwABNQAFFAUICAAIAFIWAA==.Finke:BAAANQAECgQICQAAAA==.Firemge:BAEANQAECgUIBQAAAA==.Fistzz:BAAANQADCgIIAgAAAA==.',
Fl='Flickerbeat:BAAANQAECgMJAwAAAA==.',
Fr='Free:BAAANQAECgQJBwAAAA==.',
Fu='Futurama:BAAANQADCgQIBAAAAA==.',
Ga='Gabi:BAAANQABCgIIAgAAAA==.',
Gd='Gdizz:BAAANQAECggJEgAAAA==.',
Gh='Ghostshadows:BAAANQAECgUIDAAAAA==.',
Gi='Gigazapper:BAAANQAECgUJBwABNQAECgkJGgAIAH4fAA==.Gizzlit:BAAANQAECgQIBgAAAA==.',
Go='Gobiasinds:BAAANQAECgIJAwABNQAECgkJJAAOAHskAA==.Gofetch:BAAANQAECgUIDAAAAA==.',
Gr='Grandgoop:BAAANQAECgIJAgAAAA==.Grissum:BAAANQAECgYJDwAAAA==.',
Gs='Gson:BAAANQADCggICAAAAA==.',
Gu='Guppy:BAAANQADCgYIBgAAAA==.',
Ha='Hac:BAAANQAECgUIBwAAAA==.Hakka:BAAANQAECgIJAgABNQAECgUIBwADAAAAAA==.Hallack:BAAANQAECgUIBgAAAA==.',
He='Healingkiss:BAAANQADCggIDwAAAA==.',
Hi='Hikingboots:BAAANQAECgQICQAAAA==.',
Ho='Hollypallz:BAAANQAECgIIAgAAAA==.Holymages:BAAANQAECgYJCgAAAA==.',
Ik='Iknowaguy:BAAANQAECgQICAAAAA==.',
Il='Illani:BAAANQAECgEJAwAAAA==.Ilyanna:BAABNQAECoEbAAMPAAgKRRmMCQBDAgAPAAcKIhuMCQBDAgAQAAYKzAmOegBTAQAAAA==.',
Im='Im:BAACNQAFFIEJAAIRAAUKPSMrAgASAgARAAUKPSMrAgASAgA1AAQKgSYAAxEACQprJE4CAKcDABEACQprJE4CAKcDAAkAAQr0JZjbAGwAAAAA.Imscary:BAAANQADCggIDQAAAA==.',
Iz='Izzo:BAAANQAECggICAAAAA==.',
Ja='Jausi:BAAANQAECgQIBQAAAA==.',
Je='Jenyaa:BAAANQADCgYIBgAAAA==.',
Jh='Jhops:BAAANQAECgUIDgAAAA==.',
Ji='Jilliadk:BAAANQAECgEIAQAAAA==.Jirachi:BAAANQADCggIDAAAAA==.',
Ke='Keju:BAAANQAECgEJAQAAAA==.Kerrigan:BAABNQAECoEcAAMSAAkKwRk3FgBmAgASAAgKxhs3FgBmAgAOAAEKoQmaXgA9AAAAAA==.',
Ko='Kookler:BAAANQADCgUIBQABNQAECggIGgATAP0bAA==.Kozand:BAAANQADCgMIAwABNQAECgQIBAADAAAAAA==.',
Ku='Kuji:BAAANQAECgQICAAAAA==.',
Ky='Kyirr:BAAANQAECggJEQAAAA==.',
La='Layke:BAAANQADCggIEwAAAA==.Lazerbeampew:BAAANQAECgcJEAAAAA==.',
Li='Lilli:BAEANQADCggICAABNQAFFAUICAAIAFIWAA==.',
Ll='Llynryn:BAAANQAECgIIAgAAAA==.',
Lo='Locktuah:BAAANQAECgQIBAAAAA==.Loklak:BAAANQADCgcIBwABNQAECgEIAQADAAAAAA==.',
Ma='Magicae:BAABNQAECoEdAAIFAAkK/B3LKwANAwAFAAkK/B3LKwANAwABNQAFFAYIDgASAC4cAA==.Magicmanzz:BAAANQAECgEIAQAAAA==.Magnifuso:BAAANQAECgIIAgAAAA==.Maguapa:BAAANQAECgQIBgAAAA==.Malgata:BAAANQAECgIJAgAAAA==.Margarita:BAAANQADCgQIBAAAAA==.Masstech:BAAANQAECgcIEAAAAA==.Mastab:BAABNQAECoEZAAIUAAgKOxlQJwBuAgAUAAgKOxlQJwBuAgAAAA==.',
Mc='Mchammerdin:BAAANQAECgQJBwAAAA==.',
Me='Meat:BAAANQAECgYIDgAAAA==.',
Mi='Mikio:BAAANQAECgQJBwAAAA==.Milinka:BAABNQAECoEbAAIVAAgKBRvPHgCWAgAVAAgKBRvPHgCWAgAAAA==.Mirror:BAAANQAECgYIBwABNQAECggIHAASAGgfAA==.',
Mo='Moiryn:BAAANQADCgIJAgAAAA==.',
My='Myshaman:BAAANQAECgUICAAAAA==.',
Na='Navillus:BAABNQAECoE6AAMWAAkKWCZAAAD0AwAWAAkKWCZAAAD0AwAXAAYK8xy1FQD0AQAAAA==.',
No='Noxi:BAAANQAECgQJBwAAAA==.',
Oa='Oakensoul:BAAANQAECgEIAQABNQAECgcIEwADAAAAAA==.',
Og='Ogron:BAAANQADCgYIBgABNQAECggJGgAKANklAA==.',
Op='Ophindis:BAAANQAECgYJEAAAAA==.',
Pa='Pagoda:BAABNQAECoEaAAMYAAgKEBPrEADtAQAYAAgKEBPrEADtAQAZAAEKrAtoSAAxAAAAAA==.Panerai:BAAANQADCgYIBgAAAA==.',
Pe='Pewpop:BAABNQAECoEZAAIJAAYK4CEzOQBQAgAJAAYK4CEzOQBQAgAAAA==.',
Pi='Pintsize:BAAANQABCgcJCQAAAA==.',
Pj='Pjt:BAAANQADCgEIAQAAAA==.',
Pr='Praystation:BAAANQADCgIJAgAAAA==.',
Pu='Putemuptoo:BAAANQAECgEIAQAAAA==.',
Py='Pyosi:BAAANQADCggICAAAAA==.',
Qp='Qpti:BAAANQAECgcIEwAAAA==.',
Ra='Razorclaw:BAAANQADCgEIAQABNQAECgQICgADAAAAAA==.Razz:BAAANQABCgcIBgAAAA==.',
Re='Rejectlol:BAAANQAECgYIDwAAAA==.Rennx:BAACNQAFFIESAAICAAYKKx/SAQBTAgACAAYKKx/SAQBTAgA1AAQKgRsAAgIACQowJdQCALsDAAIACQowJdQCALsDAAAA.Reznik:BAAANQAECgYJDwAAAA==.',
Ri='Rika:BAAANQADCgQIBAAAAA==.Ringmasta:BAAANQADCggIHgAAAA==.Riot:BAABNQAECoEaAAIJAAgKRBYRMwBnAgAJAAgKRBYRMwBnAgAAAA==.',
Ro='Rosé:BAAANQAFFAEIAQAAAA==.Rowen:BAAANQAECgUICAAAAA==.',
['Rè']='Rènza:BAAANQAECggIAgAAAA==.',
Sa='Saintlorric:BAAANQABCgQIBAAAAA==.Sanguineous:BAAANQAECgIIBAABNQAECgcIDAADAAAAAA==.Saphia:BAECNQAFFIEIAAIIAAUKUhbWAQCeAQAIAAUKUhbWAQCeAQA1AAQKgRsAAggACQpHI2gDAF0DAAgACQpHI2gDAF0DAAAA.Saphyr:BAEANQAECggIDAABNQAFFAUICAAIAFIWAA==.',
Sc='Scarydude:BAAANQAECgYJDgAAAA==.',
Se='Sevrin:BAABNQAECoEYAAIZAAgKaRtfDwCEAgAZAAgKaRtfDwCEAgAAAA==.',
Sh='Shamoon:BAAANQAECgQIBQAAAA==.Shamwow:BAAANQAECgQICQABNQAECgUJBQADAAAAAA==.Sheesh:BAABNQAECoEjAAMMAAkKgiFOBABOAwAMAAkKgiFOBABOAwACAAQK7BKyVwDvAAAAAA==.Shinru:BAABNQAECoEkAAIUAAgKiR4mGQDGAgAUAAgKiR4mGQDGAgAAAA==.Shrikedk:BAAANQADCgIIAgABNQAECgcIDwADAAAAAA==.',
Si='Sickdayze:BAAANQAECgUIDAAAAA==.Sickhymns:BAAANQADCgcIDQABNQAECgUIDAADAAAAAA==.Sickntired:BAAANQADCgMJAwABNQAECgUIDAADAAAAAA==.Sicktides:BAAANQADCgYICAABNQAECgUIDAADAAAAAA==.',
Sk='Skinnymini:BAAANQADCgEIAQAAAA==.',
Sl='Slyxxar:BAABNQAECoEZAAIaAAcKuBNpTgCuAQAaAAcKuBNpTgCuAQAAAA==.',
Sn='Snoopyy:BAAANQADCgcIBwAAAA==.',
So='Soar:BAAANQAECgQICgAAAA==.Soph:BAAANQAECgcIEgABNQAECgkJJAABAGgmAA==.Sophie:BAABNQAECoEkAAIBAAkKaCaXAQDsAwABAAkKaCaXAQDsAwAAAA==.Sophisticate:BAAANQAECgYIDQABNQAECgkJJAABAGgmAA==.Sophiz:BAAANQAECgUJCgABNQAECgkJJAABAGgmAA==.Sophlax:BAAANQAECgUJEQABNQAECgkJJAABAGgmAA==.Sophs:BAAANQAECgUICwABNQAECgkJJAABAGgmAA==.Sophz:BAAANQAECgQIBQABNQAECgkJJAABAGgmAA==.Sox:BAABNQAECoEaAAIbAAgKrCQ/AgBUAwAbAAgKrCQ/AgBUAwAAAA==.',
Sp='Spicynoodle:BAABNQAECoEcAAIJAAgK7hgMKwCIAgAJAAgK7hgMKwCIAgAAAA==.Spookyougi:BAAANQAECgQICwAAAA==.',
Sq='Squattinchop:BAAANQAECgUICQAAAA==.',
St='Stabamon:BAAANQADCggICAAAAA==.Stiffcrit:BAAANQAECgUICwAAAA==.',
Su='Sua:BAACNQAFFIEOAAILAAUKpRaLBgCwAQALAAUKpRaLBgCwAQA1AAQKgRwAAgsACQq7H0EZACADAAsACQq7H0EZACADAAAA.Suksuksuk:BAAANQABCgQICAAAAA==.Supergogeta:BAAANQAECgYJDwAAAA==.',
Sy='Sylvie:BAAANQAECgYJEAAAAA==.Synistër:BAAANQADCgYIDgAAAA==.',
['Sï']='Sïnsu:BAAANQAECgYJDwAAAA==.',
Ta='Takoda:BAAANQAECgQIBQAAAA==.Talauyia:BAAANQAECgIIAgAAAA==.Tankyou:BAAANQADCgYIBgAAAA==.',
Te='Temporë:BAAANQAECgEIAQAAAA==.',
Th='Thndrsquirel:BAAANQAECgEIAQABNQAECgQICAADAAAAAA==.Thrayne:BAAANQABCgMIAwAAAA==.',
Ti='Tiriandrel:BAAANQADCggICAABNQAECgYJEAADAAAAAA==.',
To='Toofaded:BAAANQADCgUJBQAAAA==.Torio:BAAANQAECgUICwAAAA==.',
Tw='Twofow:BAAANQAECgIJAgAAAA==.',
Ty='Tyranis:BAEANQAECggIBAAAAA==.Tyê:BAAANQAECgcJEQAAAA==.',
['Té']='Témalabécane:BAABNQAECoEWAAIFAAkK4R+XGABWAwAFAAkK4R+XGABWAwAAAA==.',
['Të']='Tërry:BAAANQADCgEIAQAAAA==.',
Va='Vael:BAAANQADCgYIBgAAAA==.Valexisea:BAAANQAECgUJBwAAAA==.Valériana:BAAANQADCgIIAgAAAA==.Vanítas:BAAANQADCgcIBgAAAA==.',
Vi='Visable:BAAANQAECgIJAgAAAA==.',
Vo='Voltage:BAAANQAECgQIDQABNQAECgYIGQAJAOAhAA==.',
Vu='Vulgnash:BAABNQAECoEdAAIcAAgKhCJaDQAbAwAcAAgKhCJaDQAbAwAAAA==.Vult:BAABNQAECoEYAAIdAAgKvxVCHgAJAgAdAAgKvxVCHgAJAgAAAA==.',
We='Welgo:BAAANQAECgQIBgAAAA==.Welmage:BAAANQABCgIJAgABNQAECgQIBgADAAAAAA==.',
Wi='Wickeddemon:BAAANQADCggIGAAAAA==.Windtusk:BAAANQADCggJCQAAAA==.',
Xc='Xcesive:BAAANQADCggJDQAAAA==.Xcessiv:BAAANQADCgQIBAAAAA==.Xcéssiv:BAAANQAECgcIDwAAAA==.',
Xe='Xerra:BAAANQAECgcJEgAAAA==.',
['Xû']='Xûrû:BAAANQADCgQIBAAAAA==.',
Ye='Yeast:BAAANQAECgYIBgAAAA==.',
Yr='Yravengi:BAAANQADCgMIAwAAAA==.Yrel:BAAANQADCgcIEAABNQAECgQIBAADAAAAAA==.',
Ze='Zelgie:BAAANQAECgYJEAAAAA==.',
Zi='Zienna:BAAANQADCgcICQAAAA==.Zin:BAAANQADCgYJDAAAAA==.',
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
