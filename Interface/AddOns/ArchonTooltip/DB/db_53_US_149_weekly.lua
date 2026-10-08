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

local lookup = {'Paladin-Retribution','Paladin-Holy','Druid-Balance','Unknown-Unknown','Hunter-BeastMastery','Evoker-Devastation','Evoker-Preservation','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','DeathKnight-Blood','DeathKnight-Unholy','Mage-Arcane','Mage-Frost','Mage-Fire','Paladin-Protection','Monk-Windwalker','Warrior-Protection','Warrior-Arms','Priest-Shadow','Monk-Brewmaster','Monk-Mistweaver','Druid-Restoration','DemonHunter-Havoc','Rogue-Assassination','Shaman-Elemental','Hunter-Marksmanship','DemonHunter-Devourer','DemonHunter-Vengeance','Priest-Holy','Shaman-Restoration','Hunter-Survival','Druid-Guardian','Priest-Discipline','DeathKnight-Frost',}
local provider = {region='US',realm='Maiev',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aayron:BAAANQADCgIIAgAAAA==.',
Ab='Abadizzo:BAAANQAECggIAwAAAA==.Abadizzoo:BAAANQAECggICwAAAA==.Abeyancë:BAABNQAECoEmAAMBAAkKwxgGVQBtAgABAAkKwxgGVQBtAgACAAIK8RLF6wBwAAAAAA==.Abilities:BAAANQABCgYIDAAAAA==.',
Ae='Aeshanth:BAAANQADCgUIBgAAAA==.',
Ai='Airie:BAAANQABCgIIAgAAAA==.Airwrecka:BAABNQAECoEnAAIDAAkK9xqWHQDBAgADAAkK9xqWHQDBAgAAAA==.Aite:BAAANQADCgcIBwAAAA==.',
Al='Altlas:BAAANQADCggIEAAAAA==.',
Am='Amaterasu:BAAANQADCgYIBgABNQAECgEIAQAEAAAAAA==.',
An='Anise:BAAANQADCgEJAQAAAA==.',
Ar='Arahgon:BAEBNQAECoEaAAIBAAgK6RQmeQAKAgABAAgK6RQmeQAKAgABNQAECggIDwAEAAAAAA==.Artvandelay:BAAANQAECgQIBgABNQAECggIIAAFAPsgAA==.',
As='Asukà:BAAANQAECgYIEwAAAA==.',
Au='Auchenile:BAABNQAECoEcAAMGAAcKpxoSFwC5AQAGAAYK5BgSFwC5AQAHAAMKzgkmPACYAAAAAA==.Austin:BAAANQAECgIIAQAAAA==.Austinthedog:BAAANQAECggICAAAAA==.',
Av='Avanoura:BAAANQADCggIDAABNQAECgUIBwAEAAAAAA==.',
['Aé']='Aéd:BAAANQADCgYIBgABNQAECgUIBwAEAAAAAA==.',
Ba='Barkthas:BAAANQAECgUICgAAAA==.',
Be='Bellarg:BAAANQAECgYIEgAAAA==.Belobog:BAAANQAECgUIBQAAAA==.Belyn:BAAANQAECgUICwAAAA==.',
Bi='Bifesor:BAAANQADCgMIAwAAAA==.Bizmania:BAAANQADCgQIBAAAAA==.',
Bl='Blackhøof:BAAANQADCgUIBwAAAA==.',
Bo='Bonedaddy:BAAANQAECgUIDQAAAA==.',
Br='Bratlax:BAAANQAECgQIBAABNQAFFAUIDgABALUgAA==.Bro:BAABNQAECoEbAAQIAAgKWBjiaQD4AQAIAAcKvRfiaQD4AQAJAAIK6hgoSgCWAAAKAAEKRhBOJQBFAAAAAA==.Brolich:BAABNQAECoEqAAMLAAkKHBKqOQD+AQALAAkKHBKqOQD+AQAMAAEKlQqhzQAyAAABNQAECggIGwAIAFgYAA==.Broo:BAAANQAECgQIBAABNQAECggIGwAIAFgYAA==.Brooak:BAAANQAECgYICgABNQAECggIGwAIAFgYAA==.Brother:BAAANQAECgIIAgABNQAECggIGwAIAFgYAA==.Brozeit:BAAANQAECgYIBwABNQAECggIGwAIAFgYAA==.',
Bu='Bubblegump:BAAANQAECgUIBQAAAA==.',
Ca='Calculusx:BAAANQAECgcIEAAAAA==.Camión:BAAANQADCggIDwAAAA==.',
Ce='Cellice:BAACNQAFFIEeAAMNAAcK0hmDCAAeAgANAAYK/xqDCAAeAgAOAAMKyRTFAQAGAQA1AAQKgSYABA0ACQqAI9YuACQDAA0ACQrwItYuACQDAA8AAwqfIXUFAAIBAA4AAQosJdk1AE0AAAAA.',
Ch='Chad:BAAANQADCgQIBAAAAA==.Chuckborris:BAAANQADCgEJAQABNQAFFAIIBQAQAAUfAA==.',
Cl='Clare:BAABNQAECoEXAAIQAAkKoh5FCwDFAgAQAAkKoh5FCwDFAgAAAA==.Cloúd:BAAANQAECgQIBgAAAA==.',
Da='Daddydimes:BAABNQAECoEdAAIRAAgKUxqDGABYAgARAAgKUxqDGABYAgAAAA==.',
De='Deathfu:BAAANQADCgQIBAAAAA==.Deathless:BAABNQAECoEeAAILAAcKSiMuGgDFAgALAAcKSiMuGgDFAgAAAA==.Demiize:BAABNQAECoEdAAIOAAcKtR37BgBcAgAOAAcKtR37BgBcAgAAAA==.Demize:BAABNQAECoEoAAIFAAkK2RsNHQAJAwAFAAkK2RsNHQAJAwAAAA==.Demíze:BAAANQAECgMIAwAAAA==.Deshield:BAABNQAECoEdAAMSAAgKOybPAgBnAwASAAgKMybPAgBnAwATAAgKNyEwPAC/AgAAAA==.Deus:BAABNQAECoEXAAINAAcKng6B2ACwAQANAAcKng6B2ACwAQAAAA==.Dewry:BAABNQAECoEXAAIUAAgKNR+AEwCuAgAUAAgKNR+AEwCuAgAAAA==.',
Dh='Dhudamuthi:BAABNQAECoEmAAMVAAgK9yOcAwA8AwAVAAgK9yOcAwA8AwARAAIKthb0UgBpAAAAAA==.',
Di='Dingis:BAAANQADCgQIBAABNQAECgUIBwAEAAAAAA==.Divine:BAAANQAECgYICQABNQAECggIIAAWABATAA==.Dizzo:BAABNQAECoEZAAIMAAcKrB0POAAgAgAMAAcKrB0POAAgAgAAAA==.',
Do='Doink:BAAANQAECgcIEgABNQAECgkJLwAXABUiAA==.Donnajuan:BAABNQAECoEVAAICAAcKpRx4OQBhAgACAAcKpRx4OQBhAgAAAA==.Dornath:BAAANQAECgQIBAAAAA==.',
Dr='Draaxelro:BAAANQADCgUIDAAAAA==.Dragontiddys:BAAANQADCgIIAgAAAA==.Drakaris:BAAANQADCggIEAAAAA==.',
Ed='Edgeillus:BAAANQADCgMIBAABNQAFFAUIDgAGAIobAA==.',
El='Elimere:BAABNQAECoEnAAIUAAkKPAyNJADjAQAUAAkKPAyNJADjAQAAAA==.Elvarg:BAABNQAECoEkAAIGAAgKjhz7CgCiAgAGAAgKjhz7CgCiAgAAAA==.Elywen:BAABNQAECoEpAAIFAAkK+x69FQAuAwAFAAkK+x69FQAuAwAAAA==.',
En='Enry:BAAANQADCggIEAAAAA==.',
Eq='Eqlipse:BAAANQADCgYIBgAAAA==.',
Es='Esira:BAAANQADCgIIAgAAAA==.',
Ev='Evién:BAAANQADCggIDAAAAA==.',
Ex='Executè:BAAANQADCgIIAgABNQAECggIJAAYAGIhAA==.',
Fi='Fiammetta:BAEANQADCgcIBwABNQAFFAYIEAAQANcaAA==.Finke:BAAANQAECgQICQAAAA==.Firemge:BAEANQAECgUIBQABNQAFFAcIFgAQANUYAA==.Fistzz:BAAANQADCgIIAgAAAA==.',
Fl='Flickerbeat:BAAANQAECgQIBwAAAA==.',
Fr='Free:BAAANQAECgUIEAAAAA==.',
Fu='Futurama:BAAANQADCgQIBAAAAA==.',
Ga='Gabi:BAAANQABCgIIAgAAAA==.',
Gd='Gdizz:BAABNQAECoEnAAINAAkK6Q9mnQAnAgANAAkK6Q9mnQAnAgAAAA==.',
Gh='Ghostshadows:BAABNQAECoEbAAIZAAcKWyLdEwC6AgAZAAcKWyLdEwC6AgAAAA==.',
Gi='Gigazapper:BAAANQAECgYIEgABNQAFFAIIBQAQAAUfAA==.Gizzlit:BAAANQAECgYIEQAAAA==.',
Go='Gobiasinds:BAAANQAECgMIBAABNQAFFAUICQAYANwbAA==.Gofetch:BAABNQAECoEdAAIFAAcKUh3YUQBSAgAFAAcKUh3YUQBSAgAAAA==.Goodbye:BAAANQAECgYIBgAAAA==.',
Gr='Grandgoop:BAAANQAECgMIBQAAAA==.Grasputin:BAAANQADCgUIBQAAAA==.Grissum:BAABNQAECoEgAAIFAAgK+yDSJwDZAgAFAAgK+yDSJwDZAgAAAA==.',
Gs='Gson:BAAANQAECggICAAAAA==.',
Gu='Guppy:BAAANQADCgYIBgAAAA==.',
Ha='Hac:BAAANQAECgUIBwABNQAECggIEQAEAAAAAA==.Hakka:BAAANQAECggIEQAAAA==.Hal:BAAANQADCgUIBQABNQAECgYIDQAEAAAAAA==.Hallack:BAAANQAECgYIDQAAAA==.',
He='Healingkiss:BAAANQAECgEIAQAAAA==.',
Hi='Hikingboots:BAABNQAECoEZAAIaAAcK4QrBfwB1AQAaAAcK4QrBfwB1AQAAAA==.',
Ho='Hollypallz:BAAANQAECgIIAgAAAA==.Holymages:BAABNQAECoEZAAINAAgKiBuadgB6AgANAAgKiBuadgB6AgAAAA==.',
Ik='Iknowaguy:BAAANQAECgQICAABNQAECgUIBgAEAAAAAA==.',
Il='Illani:BAAANQAECgEJAwAAAA==.Ilyanna:BAABNQAECoEkAAMJAAkKHBoMBwCNAgAJAAgK8hsMBwCNAgAIAAcKsQpDkgCJAQAAAA==.',
Im='Im:BAACNQAFFIESAAMbAAYKhSSHBAD+AQAbAAUKPSSHBAD+AQAFAAEK6SUlJQByAAA1AAQKgSwAAxsACQpLJScDAKMDABsACQpLJScDAKMDAAUAAQr0Jb0fAWUAAAAA.Imscary:BAAANQAECgEIAQAAAA==.',
It='Itooktheflag:BAAANQADCgMIAwAAAA==.',
Iz='Izzo:BAAANQAECggICAAAAA==.',
Ja='Jausi:BAAANQAECgQICQAAAA==.',
Je='Jenyaa:BAAANQADCggIDQAAAA==.',
Jh='Jhops:BAABNQAECoEgAAIaAAgKgxsZNwB0AgAaAAgKgxsZNwB0AgAAAA==.',
Ji='Jilliadk:BAAANQAECgEIAQAAAA==.Jirachi:BAAANQADCggIEwAAAA==.',
Ka='Katz:BAAANQADCgUIBQAAAA==.',
Ke='Keju:BAAANQAECgEJAQAAAA==.Kerrigan:BAABNQAECoEjAAMcAAkK2RqsHQBIAgAcAAgKAB2sHQBIAgAYAAQKVw6RWQDnAAAAAA==.',
Ko='Kookler:BAAANQADCgUIBQABNQAECgkJHgANALIfAA==.Kookluhh:BAAANQAECgUIBwABNQAECgkJHgANALIfAA==.Kozand:BAAANQADCgMIAwABNQAECgUIBwAEAAAAAA==.',
Ku='Kuji:BAAANQAECgQICAAAAA==.Kushmon:BAAANQADCgEIAQAAAA==.',
Ky='Kyirr:BAAANQAECggJEQAAAA==.Kyralen:BAAANQABCgQIBQABNQAECgcIHAAGAKcaAA==.',
La='Layke:BAAANQADCggIEwAAAA==.Lazerbeampew:BAAANQAECgcIEQAAAA==.',
Li='Lilli:BAEANQADCggICAABNQAFFAYIEAAQANcaAA==.',
Ll='Llynryn:BAAANQAECgUIBwAAAA==.',
Lo='Locktuah:BAAANQAECgQIBAABNQAECgUIBwAEAAAAAA==.Loklak:BAAANQADCgcIBwABNQAECgEIAQAEAAAAAA==.',
Ly='Lycann:BAAANQABCgYIDQAAAA==.',
Ma='Magicae:BAABNQAECoEoAAINAAkKkyEbIABQAwANAAkKkyEbIABQAwABNQAFFAcIGgAcAM4gAA==.Magicmanzz:BAAANQAECgUICgAAAA==.Magnifuso:BAAANQAECgQICAAAAA==.Maguapa:BAAANQAECgQICAAAAA==.Malgata:BAAANQAECgQICAAAAA==.Margarita:BAAANQADCgQIBAAAAA==.Masstech:BAABNQAECoEdAAIBAAkKHxjfTQCDAgABAAkKHxjfTQCDAgAAAA==.Mastab:BAABNQAECoEjAAMCAAkKPxmiKQCpAgACAAkKPxmiKQCpAgABAAIK4AxXPgF4AAAAAA==.',
Mc='Mchammerdin:BAAANQAECgYIEwAAAA==.',
Me='Meat:BAABNQAECoEcAAMdAAgKvxrdCAAyAgAdAAcK/hzdCAAyAgAYAAEKBwvPggA0AAAAAA==.',
Mi='Mikio:BAAANQAECgYIDgAAAA==.Milinka:BAABNQAECoElAAIeAAkKSxlsJAC9AgAeAAkKSxlsJAC9AgAAAA==.Mirror:BAAANQAECgYIBwABNQAECggIKwAcADskAA==.',
Mo='Moiryn:BAAANQADCgIJAgAAAA==.',
My='Myshaman:BAAANQAECgYIEAAAAA==.',
Na='Navillus:BAACNQAFFIEOAAIGAAUKihuaAgDNAQAGAAUKihuaAgDNAQA1AAQKgWwAAwYACQpzJl0AAOwDAAYACQpzJl0AAOwDAAcACAoTIKsLANoCAAAA.',
No='Noxi:BAAANQAECgQICgAAAA==.',
Oa='Oakensoul:BAAANQAECgEIAQABNQAECggIIwAQAA4lAA==.',
Og='Ogron:BAAANQADCgYIBgABNQAECggIHQASADsmAA==.',
Op='Ophindis:BAABNQAECoEcAAILAAcKjR1MKgBXAgALAAcKjR1MKgBXAgAAAA==.',
Os='Osten:BAAANQAECgQICAAAAA==.',
Pa='Pagoda:BAABNQAECoEgAAMWAAgKEBM+GADJAQAWAAgKEBM+GADJAQARAAQKVxNQPwDjAAAAAA==.Panerai:BAAANQADCgYIBgAAAA==.',
Pe='Pewpop:BAABNQAECoEZAAIFAAYK4CGYYwAjAgAFAAYK4CGYYwAjAgAAAA==.',
Pi='Pintsize:BAAANQABCgcJCQAAAA==.',
Pj='Pjt:BAAANQADCgEIAQAAAA==.',
Pr='Praystation:BAAANQAECgIIAgAAAA==.',
Pu='Putemuptoo:BAAANQAECgEIAQAAAA==.',
Py='Pyosi:BAAANQADCggICAAAAA==.',
Qp='Qpti:BAABNQAECoEbAAITAAkKeBPFaQA0AgATAAkKeBPFaQA0AgAAAA==.',
Ra='Razorclaw:BAAANQADCgEIAQABNQAECgUICwAEAAAAAA==.Razz:BAAANQABCgcIBgAAAA==.',
Re='Rejectlol:BAABNQAECoEiAAIBAAkKDhVrZABAAgABAAkKDhVrZABAAgAAAA==.Rennx:BAACNQAFFIEeAAIDAAcKaB1aAgCRAgADAAcKaB1aAgCRAgA1AAQKgR8AAgMACQpSJdIFAJ4DAAMACQpSJdIFAJ4DAAAA.Reznik:BAABNQAECoEgAAILAAgK8hVLPADxAQALAAgK8hVLPADxAQAAAA==.',
Ri='Rika:BAAANQAECgEIAQAAAA==.Ringmasta:BAAANQAECgEIAQAAAA==.Riot:BAABNQAECoEoAAIFAAkKFRqMLADHAgAFAAkKFRqMLADHAgAAAA==.',
Ro='Rosé:BAAANQAFFAEIAQAAAA==.Rowen:BAAANQAECgUIEAAAAA==.',
['Rè']='Rènza:BAAANQAECggIBwAAAA==.',
Sa='Saintlorric:BAAANQABCgQIBAAAAA==.Sanguineous:BAAANQAECgIIBAABNQAECgcIGQABAPAaAA==.Saphia:BAECNQAFFIEQAAIQAAYK1xoGAgD+AQAQAAYK1xoGAgD+AQA1AAQKgScAAhAACQpVJQcBANYDABAACQpVJQcBANYDAAAA.Saphyr:BAEBNQAECoEWAAMLAAkKpB9DDgAsAwALAAkKpB9DDgAsAwAMAAMKrgoppgCDAAABNQAFFAYIEAAQANcaAA==.',
Sb='Sblakedragon:BAAANQAECgEIAQAAAA==.',
Sc='Scarydude:BAAANQAECgcIDwAAAA==.',
Se='Sevrin:BAABNQAECoElAAMRAAkKLxyNEADBAgARAAkKLxyNEADBAgAVAAEK3hIRLAA4AAAAAA==.',
Sh='Shamoon:BAAANQAECgQIBQAAAA==.Shamwow:BAAANQAECgQICwABNQAECgUIBQAEAAAAAA==.Sheesh:BAABNQAECoEvAAMXAAkKFSKDBgBIAwAXAAkKFSKDBgBIAwADAAQKWxNIawDzAAAAAA==.Shinru:BAABNQAECoEuAAICAAkKNiFnDQBPAwACAAkKNiFnDQBPAwAAAA==.Shrikedk:BAAANQADCgIIAgABNQAECgkJFwAQAKIeAA==.',
Si='Sickdayze:BAABNQAECoEdAAICAAcKFSE2LQCWAgACAAcKFSE2LQCWAgAAAA==.Sickhymns:BAAANQAECgMIAwABNQAECgcIHQACABUhAA==.Sickntired:BAAANQADCgMJAwABNQAECgcIHQACABUhAA==.Sicktides:BAAANQADCgYICAABNQAECgcIHQACABUhAA==.',
Sk='Skinnymini:BAAANQADCgEIAQAAAA==.',
Sl='Slyxxar:BAABNQAECoEeAAIfAAcKLRViagCeAQAfAAcKLRViagCeAQAAAA==.',
Sn='Snaffu:BAAANQAECgYIBgAAAA==.Snoopyy:BAAANQADCgcIBwAAAA==.',
So='Soar:BAAANQAECgUICwAAAA==.Soph:BAABNQAECoEeAAMXAAkKJSOSAwCAAwAXAAkKJSOSAwCAAwADAAEKWhqVlgBMAAABNQAFFAUIDgABALUgAA==.Sophie:BAACNQAFFIEOAAIBAAUKtSD7BADqAQABAAUKtSD7BADqAQA1AAQKgS0AAgEACQp3JjkEANIDAAEACQp3JjkEANIDAAAA.Sophisticate:BAABNQAECoEeAAIgAAkKUx+OAQBFAwAgAAkKUx+OAQBFAwABNQAFFAUIDgABALUgAA==.Sophiz:BAABNQAECoEaAAIcAAkK3htSEQDRAgAcAAkK3htSEQDRAgABNQAFFAUIDgABALUgAA==.Sophlax:BAABNQAECoEfAAIeAAgKhR5oJQC4AgAeAAgKhR5oJQC4AgABNQAFFAUIDgABALUgAA==.Sophs:BAAANQAECgQIEwABNQAFFAUIDgABALUgAA==.Sophz:BAAANQAECggIEgABNQAFFAUIDgABALUgAA==.Sox:BAABNQAECoEnAAIhAAkKoyUYAQDTAwAhAAkKoyUYAQDTAwAAAA==.',
Sp='Spicynoodle:BAABNQAECoEgAAIFAAkKvhlTMgCzAgAFAAkKvhlTMgCzAgAAAA==.Spookyougi:BAAANQAECgQICwAAAA==.',
Sq='Squattinchop:BAAANQAECgYIEAAAAA==.',
St='Stabamon:BAAANQADCggICAAAAA==.Stiffcrit:BAABNQAECoEWAAINAAYKzxOm3wCjAQANAAYKzxOm3wCjAQAAAA==.',
Su='Sua:BAACNQAFFIEZAAITAAcKgBPaBQA/AgATAAcKgBPaBQA/AgA1AAQKgSAAAhMACQp2IGclABMDABMACQp2IGclABMDAAAA.Suksuksuk:BAAANQABCgQICAAAAA==.Supergogeta:BAABNQAECoEfAAMXAAgKVBXSIAD2AQAXAAgKVBXSIAD2AQADAAUKQg+SYAAjAQAAAA==.',
Sy='Sylvie:BAAANQAECgcIEQAAAA==.Synistër:BAAANQADCgYIDgAAAA==.',
['Sï']='Sïnsu:BAABNQAECoEfAAITAAgKtRyZRQCgAgATAAgKtRyZRQCgAgAAAA==.',
Ta='Takoda:BAAANQAECgQIBQAAAA==.Talauyia:BAAANQAECgIIBAAAAA==.Tankyou:BAAANQADCgYIBgAAAA==.',
Te='Temporë:BAAANQAECgEIAQAAAA==.',
Th='Thicness:BAAANQADCgUIBQAAAA==.Thndrsquirel:BAAANQAECgUIBgAAAA==.Thrayne:BAAANQABCgMIAwAAAA==.',
Ti='Tiriandrel:BAAANQAECgIIAgABNQAECgcIHAALAI0dAA==.',
To='Toofaded:BAAANQADCgUIBQAAAA==.Torio:BAABNQAECoEcAAIiAAcK6ReaBgAGAgAiAAcK6ReaBgAGAgAAAA==.',
Tw='Twofow:BAAANQAECgQICAAAAA==.',
Ty='Tyranis:BAEANQAECggIDwAAAA==.Tyê:BAABNQAECoEaAAIHAAcK4xYaHADrAQAHAAcK4xYaHADrAQAAAA==.',
['Té']='Témalabécane:BAABNQAECoEeAAINAAkKZSC1KgAwAwANAAkKZSC1KgAwAwAAAA==.',
['Të']='Tërry:BAAANQADCgEIAQAAAA==.',
Un='Unspoken:BAAANQADCgMIAwAAAA==.',
Va='Vael:BAAANQADCgYIBgAAAA==.Valexisea:BAAANQAECgUJBwAAAA==.Valériana:BAAANQADCgIIAgAAAA==.Vanítas:BAAANQADCgcIBgAAAA==.',
Vi='Visable:BAAANQAECgUIBwAAAA==.',
Vo='Voltage:BAAANQAECgQIDQABNQAECgYIGQAFAOAhAA==.',
Vu='Vulgnash:BAABNQAECoEsAAIMAAgKjCSKDgAvAwAMAAgKjCSKDgAvAwAAAA==.Vult:BAABNQAECoEmAAIjAAgKHxu1IABcAgAjAAgKHxu1IABcAgAAAA==.',
Wa='Water:BAAANQAECgIIAgAAAA==.',
We='Welgo:BAAANQAECgQIBgAAAA==.Welmage:BAAANQAECgIIAgABNQAECgQIBgAEAAAAAA==.',
Wi='Wickeddemon:BAAANQADCggIIAAAAA==.Windtusk:BAAANQADCggJCQAAAA==.',
Xc='Xcesive:BAAANQADCggJDQAAAA==.Xcessiv:BAAANQADCgQIBAAAAA==.Xcéssiv:BAABNQAECoEfAAINAAgK5B0lUgDMAgANAAgK5B0lUgDMAgAAAA==.',
Xe='Xerra:BAABNQAECoEmAAIcAAkKthwDDQAFAwAcAAkKthwDDQAFAwAAAA==.',
['Xû']='Xûrû:BAAANQADCgQIBAAAAA==.',
Ye='Yeast:BAAANQAECgYIBgAAAA==.',
Yr='Yravengi:BAAANQAECgQIBAAAAA==.Yrel:BAAANQAECgUIBwAAAA==.',
Ze='Zeit:BAAANQAECgYIDAABNQAECggIGwAIAFgYAA==.Zelgie:BAABNQAECoEfAAICAAgKNRmiLgCQAgACAAgKNRmiLgCQAgAAAA==.',
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
