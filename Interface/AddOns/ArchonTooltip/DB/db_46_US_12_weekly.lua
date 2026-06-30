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

local lookup = {'Mage-Frost','Warlock-Affliction','Warlock-Destruction','Priest-Holy','Warrior-Fury','Shaman-Elemental','Rogue-Subtlety','Evoker-Preservation','DemonHunter-Vengeance','Druid-Guardian','Hunter-Survival','Warlock-Demonology','Paladin-Holy','Unknown-Unknown','Evoker-Augmentation','Evoker-Devastation','Shaman-Restoration','DemonHunter-Devourer','Paladin-Retribution','Warrior-Protection','Warrior-Arms','Monk-Windwalker','Hunter-BeastMastery','Priest-Discipline','Priest-Shadow','DeathKnight-Unholy','DeathKnight-Frost','Druid-Feral','Paladin-Protection','Monk-Brewmaster','Monk-Mistweaver','Hunter-Marksmanship','Shaman-Enhancement',}
local provider = {region='US',realm='Anetheron',name='US',type='weekly',zone=46,date='2026-06-27',data={Ab='Abcmico:BAACLgAFFH8GAAIBAAUJrgwGKgClAAABAAUJrgwGKgClAAAuAAQKfxcAAgEACQndHM0aALoCAAEACQndHM0aALoCAAAA.',
Ar='Aragarne:BAAALgAECgEJAQAAAA==.Arsha:BAAALgAECgQJBAAAAA==.Arskii:BAAALgADCggJCAAAAA==.',
As='Askii:BAABLgAECn8mAAMCAAgJlhzrCQDDAQACAAgJlhzrCQDDAQADAAQJpBFcNADlAAAAAA==.',
At='Atulock:BAAALgAECgcJCAAAAA==.',
Az='Azuth:BAAALgADCgYJAQABLgAECgkJLgAEAF8PAA==.',
Ba='Badaspen:BAAALgAECgYJBgAAAA==.Banshee:BAAALgAECgQJCAAAAA==.Batlad:BAAALgAECgEJAwAAAA==.',
Be='Beefcake:BAACLgAFFH8HAAIFAAMJHR88JgAcAQAFAAMJHR88JgAcAQAuAAQKf14AAgUACQnPJfkAAHoDAAUACQnPJfkAAHoDAAAA.',
Bi='Bigsneak:BAAALgAECgEJAgAAAA==.',
Bj='Bjorn:BAAALgAECgMJAwABLgAFFAUJDgAGAKIIAA==.',
Bo='Bojtit:BAAALgADCgUJBQABLgAECgkJIgAHAH0YAA==.Borgor:BAAALgAECgYJDgAAAA==.',
Br='Brachroy:BAAALgADCgcJDAAAAA==.',
Bu='Bunnie:BAAALgAECgUJDAABLgAECgYJGAAIAOUMAA==.Bus:BAABLgAFFH8NAAIJAAYJXCVFAAARAgAJAAYJXCVFAAARAgABLgAFFAkJHAAKAP8jAA==.',
Ca='Canttoucthis:BAAALgADCggJDAAAAA==.Casaran:BAAALgAECgkJEgAAAA==.',
Ce='Cesio:BAABLgAFFH8GAAILAAMJFxYyHQDnAAALAAMJFxYyHQDnAAAAAA==.',
Ch='Cheesecrums:BAAALgAECgEJAQAAAA==.Chen:BAAALgAECgkJEwAAAA==.',
Co='Cotilliôn:BAACLgAFFH8TAAIHAAQJDhaQGgBCAQAHAAQJDhaQGgBCAQAuAAQKfzUAAgcACAlVIHgKAHwCAAcACAlVIHgKAHwCAAAA.',
Cr='Criticaltuna:BAACLgAFFH8aAAMMAAUJpB3TRABAAQAMAAUJCB3TRABAAQACAAEJ+x9MGQBaAAAuAAQKfygABAMACAloHukZAH0BAAwABgkkGPNkAJwBAAMABQlgGukZAH0BAAIAAQmXHzElAF0AAAAA.',
Da='Dadadin:BAAALgAECgQJBAAAAA==.Dalanaar:BAAALgADCgQJBAAAAA==.Danimal:BAAALgAFFAIJAgAAAA==.',
De='Deadmens:BAAALgAECgYJCwABLgAFFAQJEAACAHETAA==.Deathblooms:BAACLgAFFH8QAAIJAAUJkR1SAACgAQAJAAUJkR1SAACgAQAuAAQKfyoAAgkACAkwIrYBAP8CAAkACAkwIrYBAP8CAAAA.Destinie:BAACLgAFFH8aAAINAAUJ3yVNCgATAgANAAUJ3yVNCgATAgAuAAQKfzgAAg0ACQn4IhgFAEMDAA0ACQn4IhgFAEMDAAAA.Destiniedrud:BAAALgAECgUJCgABLgAFFAUJGgANAN8lAA==.Destiniepves:BAAALgAECgQJBAABLgAFFAUJGgANAN8lAA==.',
Di='Dimlock:BAAALgAECgkJDAAAAA==.Disbearleaf:BAAALgAECgYJCQAAAA==.Disc:BAAALgADCgQJBAABLgADCgYJCwAOAAAAAA==.',
Dr='Dragooning:BAACLgAFFH8MAAIPAAQJ9BCYMwD0AAAPAAQJ9BCYMwD0AAAuAAQKfzQAAw8ACQmFG5sNAIUCAA8ACQmFG5sNAIUCABAAAgl6EtcaAHYAAAAA.',
Du='Duriniknight:BAAALgAFFAIJAwAAAA==.',
['Dé']='Déllenna:BAABLgAECn8nAAIPAAgJGQYgBgCdAAAPAAgJGQYgBgCdAAAAAA==.',
Ea='Earthen:BAABLgAFFH8GAAIRAAQJsQ92NwAEAQARAAQJsQ92NwAEAQABLgAFFAUJCgASAGMaAA==.',
El='Elfisto:BAAALgAECgEJAQAAAA==.Ellaa:BAAALgADCgEJAQAAAA==.Ellin:BAAALgAECgIJAgAAAA==.Elokyria:BAAALgAFFAEJAQAAAA==.Elorom:BAAALgAECgQJBgAAAA==.Elrentha:BAAALgADCgEJAQAAAA==.',
Em='Emiira:BAAALgAECgMJAwAAAA==.',
Eo='Eos:BAAALgADCgEJAgAAAA==.',
Ep='Ephana:BAAALgAECgEJAQAAAA==.Ephemeral:BAAALgAECgQJCAABLgAFFAIJBwATAEQhAA==.',
Es='Esme:BAAALgAECgYJDQAAAA==.',
Ex='Excalibes:BAEALgAECgkJAwABLgAECgkJZgAIAC4bAA==.',
Fa='Falkion:BAACLgAFFH8cAAIFAAUJUx6FFABoAQAFAAUJUx6FFABoAQAuAAQKfzgAAgUACQmvIAEIAN8CAAUACQmvIAEIAN8CAAAA.',
Fi='Fistingpower:BAAALgAECggJEwABLgAFFAQJDAAPAPQQAA==.',
Fo='Folus:BAAALgAECgEJAQAAAA==.Foluspriest:BAAALgADCgUJBQABLgAECgEJAQAOAAAAAA==.',
Fr='Frozarak:BAAALgADCgQJBAAAAA==.',
Fu='Fuzzy:BAABLgAECn8gAAIUAAkJihuHCwA1AgAUAAkJihuHCwA1AgAAAA==.',
Ge='Gemini:BAAALgAECgUJCgAAAA==.Gewch:BAAALgAECgEJAQAAAA==.',
Gi='Gimlii:BAABLgAECn83AAMVAAkJYx5MBQC3AgAVAAkJYx5MBQC3AgAFAAYJHhYYRwCIAQAAAA==.',
Go='Goybeam:BAAALgADCgIJAgAAAA==.',
['Gû']='Gûst:BAAALgAECgQJBAAAAA==.',
Ha='Hachi:BAAALgADCgIJAgAAAA==.Hans:BAAALgAECgIJAgAAAA==.Hanui:BAAALgAECgEJAwAAAA==.Harvoldold:BAAALgAECgEJBAABLgAECgMJBgAOAAAAAA==.',
Hi='Hib:BAAALgAECgMJAwAAAA==.',
Ho='Hokage:BAAALgAECgIJAgAAAA==.',
Hu='Hunterbidens:BAABLgAECn8zAAIWAAkJkSO+BAALAwAWAAkJkSO+BAALAwAAAA==.',
Ig='Igorz:BAAALgAECgIJAgAAAA==.',
Im='Important:BAAALgAFFAEJAQAAAA==.',
Io='Io:BAAALgADCgQJBAABLgAECgEJAQAOAAAAAA==.',
Ir='Ironhawk:BAAALgAECgUJCAAAAA==.Irønhåwk:BAAALgADCgEJAgAAAA==.',
It='Itchytasty:BAAALgAECgIJAgAAAA==.',
Iu='Iu:BAABLgAECn8dAAMFAAgJoQz/OQBeAQAFAAgJyAv/OQBeAQAVAAUJKgmZJADIAAAAAA==.',
Ja='Jada:BAAALgADCgYJBgAAAA==.Jazzy:BAAALgADCgEJAQAAAA==.',
Jo='Johnblizard:BAAALgAECgcJBwAAAA==.Jolly:BAABLgAECn88AAITAAkJ0w8vcACOAQATAAkJ0w8vcACOAQAAAA==.Jollymage:BAAALgAECgcJCQAAAA==.',
Ka='Kamia:BAAALgADCgEJAQAAAA==.Karina:BAABLgAECn8dAAITAAkJJA0JTQD7AQATAAkJJA0JTQD7AQAAAA==.Kathadin:BAAALgAECgIJAgAAAA==.Kayd:BAAALgADCgcJBwAAAA==.Kazuha:BAABLgAFFH8FAAIXAAMJPgydGQDXAAAXAAMJPgydGQDXAAAAAA==.',
Ki='Kimari:BAACLgAFFH8OAAIWAAMJJhmcBQDgAAAWAAMJJhmcBQDgAAAuAAQKfxoAAhYACQmHG0cNAHECABYACQmHG0cNAHECAAAA.Kimìltonze:BAABLgAECn8eAAIUAAkJJgzAHQBHAQAUAAkJJgzAHQBHAQAAAA==.Kite:BAAALgAECgIJAgAAAA==.',
La='Lambpie:BAAALgAECgUJDQABLgAFFAMJBwAFAB0fAA==.Lancealot:BAAALgAECgUJBQAAAA==.',
Li='Lillith:BAAALgAECgYJEgAAAA==.Lilyanna:BAAALgAECgIJAwAAAA==.Limeaid:BAACLgAFFH8PAAMQAAQJ6h1HAgBoAQAQAAQJ6h1HAgBoAQAPAAEJuBSkZABAAAAuAAQKfzUABBAACQnxItIAAG8DABAACQnxItIAAG8DAA8ACAnfGLI3AFABAAgAAglABOxAAGQAAAEuAAUUCAkeABgApxIA.Limelight:BAABLgAECn8XAAITAAkJaBDeCAAbAQATAAkJaBDeCAAbAQABLgAFFAgJHgAYAKcSAA==.Limeylady:BAACLgAFFH8eAAMYAAgJpxI9EAAYAgAYAAcJkBI9EAAYAgAZAAUJphbzEABiAQAuAAQKfzgAAxkACQnVIh0EABoDABkACQnVIh0EABoDABgABwmYHr8QADYCAAAA.Liridra:BAAALgAECgYJCAAAAA==.',
Ma='Madwilliam:BAAALgAECgkJBgAAAA==.Magicaltuna:BAAALgAECgUJDgABLgAFFAUJGgAMAKQdAA==.Malvado:BAACLgAFFH8QAAMCAAQJcRNcBQAxAQACAAQJcRNcBQAxAQAMAAIJJARgswByAAAuAAQKfzQABAIACQlZGF4GABgCAAIACQlZGF4GABgCAAwABQlxEdGVAC0BAAMABAnDEFwiAJ0AAAAA.Matheney:BAEALgAFFAEJAQABLgAFFAYJCwAPAAYPAA==.Mazikeen:BAAALgADCgcJDgAAAA==.',
Mi='Milktruk:BAACLgAFFH8aAAMaAAUJdh7VGAANAQAaAAUJdh7VGAANAQAbAAQJZR5CEwD1AAAuAAQKfysAAxoACQm8JH8HADoDABoACQm8JH8HADoDABsAAwl4GiMgAMwAAAAA.Minji:BAABLgAECn8ZAAIcAAkJMBbuCQAjAgAcAAkJMBbuCQAjAgAAAA==.',
Mo='Mook:BAAALgADCgQJBAAAAA==.Morzrac:BAAALgADCgMJAwAAAA==.',
Ne='Nemosum:BAABLgAECn8YAAQNAAcJsAhFXAAMAQANAAcJsAhFXAAMAQATAAQJjgjjLgGBAAAdAAUJcwMMQQBbAAAAAA==.',
Ni='Nightingale:BAAALgADCgcJBwAAAA==.Ningning:BAAALgAECgkJEAAAAA==.Nizyr:BAAALgAECgEJBgAAAA==.',
No='Noodles:BAAALgADCgcJBwABLgAECggJIgASAH0WAA==.Nottahealer:BAAALgADCgcJDQAAAA==.',
Ny='Nyra:BAAALgAECgMJAwAAAA==.',
Og='Ogma:BAAALgADCgUJBQAAAA==.',
On='One:BAAALgAECgcJBwAAAA==.',
Os='Osiris:BAAALgADCgcJBwAAAA==.',
Pa='Padfoot:BAAALgAECgUJBQABLgAECgUJBgAOAAAAAA==.',
Pr='Prey:BAABLgAECn8fAAMKAAkJvxecDAAXAgAKAAkJvxecDAAXAgAcAAQJNQLbLABfAAAAAA==.',
Pu='Purpp:BAAALgAFFAMJAQAAAA==.',
Py='Pyreyn:BAACLgAFFH8NAAMNAAMJdxgKKgDXAAANAAMJdxgKKgDXAAATAAIJ1gjZKgB/AAAuAAQKfzMAAw0ACAkSHisdABoCAA0ABwkJHisdABoCABMACAmnF7tKAOYBAAAA.',
Qu='Qutfazz:BAAALgAECgEJAQAAAA==.',
Ra='Radley:BAAALgAECgYJDwABLgAFFAkJEAAbAKEVAA==.Raelilah:BAABLgAECn8iAAIHAAkJfRgADgBIAgAHAAkJfRgADgBIAgAAAA==.Raenia:BAAALgAECgEJAQAAAA==.Rakuma:BAAALgADCgEJAQAAAA==.Rawr:BAAALgAECgcJBwAAAA==.',
Re='Reptar:BAACLgAFFH8dAAIeAAcJfhQ8EgCSAQAeAAcJfhQ8EgCSAQAuAAQKfxgAAh4ACAkHHA4bACwCAB4ACAkHHA4bACwCAAAA.',
Rh='Rhaegar:BAAALgAECgMJAwABLgAECgQJBAAOAAAAAA==.Rheolette:BAAALgAECgEJAQAAAA==.Rheolin:BAABLgAECn8XAAIfAAYJdR4uJQD6AQAfAAYJdR4uJQD6AQAAAA==.Rheolynx:BAABLgAECn8dAAINAAYJHSQJAQATAgANAAYJHSQJAQATAgAAAA==.Rheomei:BAAALgAECgUJCQAAAA==.Rheomoon:BAABLgAECn8eAAIRAAcJpRwABAB3AQARAAcJpRwABAB3AQAAAA==.',
Ri='Richelly:BAAALgAFFAEJAQAAAA==.Ricki:BAAALgAECgQJAwAAAA==.',
Ro='Rookhrux:BAAALgAECgUJBgAAAA==.Rookrollux:BAAALgAECgUJCQAAAA==.Rosenya:BAAALgADCgMJAwAAAA==.',
['Rø']='Røsenrøt:BAABLgAECn8UAAIWAAcJvxS/LQBVAQAWAAcJvxS/LQBVAQAAAA==.',
Sa='Saelydera:BAAALgAECgQJBQAAAA==.Saizan:BAAALgAECgcJEQAAAA==.Samsara:BAAALgAECgYJCAAAAA==.',
Sc='Scourgeknigh:BAAALgADCgUJBAAAAA==.',
Se='Seolen:BAAALgAECgEJAQAAAA==.Seppuku:BAAALgAECgEJBAAAAA==.Serie:BAAALgAECgQJCQAAAA==.Severus:BAAALgAECgMJAgAAAA==.',
Sh='Shìfty:BAAALgADCgcJDgAAAA==.',
Si='Silverthorn:BAAALgAECgYJEAAAAA==.Sindrei:BAAALgADCgYJBgAAAA==.Sixxpack:BAAALgADCgcJAQAAAA==.',
Sm='Smokabull:BAAALgAECgEJAQAAAA==.',
St='Stamina:BAAALgADCgYJCwAAAA==.Stathome:BAAALgAECgEJAQAAAA==.Stormm:BAAALgAECgEJAQABLgAECgkJEQAOAAAAAA==.',
Su='Suicidalone:BAAALgAECgEJAQAAAA==.',
Sy='Sylveon:BAABLgAFFH8OAAIcAAYJbyYcAQAlAgAcAAYJbyYcAQAlAgABLgAFFAMJBgAcAMccAA==.Syndara:BAAALgAECgUJCQAAAA==.',
Ta='Tab:BAAALgAECgkJAQAAAA==.',
Ti='Tiamatt:BAAALgAECgkJEQAAAA==.',
To='Tornheart:BAABLgAECn8uAAICAAkJCRV6BQASAgACAAkJCRV6BQASAgAAAA==.',
Tr='Treyni:BAAALgADCgYJBgAAAA==.',
Tu='Tubby:BAAALgAECgYJDQAAAA==.Tubbycoin:BAABLgAECn8fAAMgAAkJmx8OCwC6AQAgAAgJPSAOCwC6AQALAAIJ3xrgSACWAAAAAA==.Tulkas:BAACLgAFFH8PAAIhAAQJlh4KBwBIAQAhAAQJlh4KBwBIAQAuAAQKfxcAAiEACAl7G1IIAEECACEACAl7G1IIAEECAAAA.',
Va='Vae:BAAALgAECgIJAgABLgAFFAcJDwAaAPAXAA==.Vandel:BAAALgAECgYJBgAAAA==.',
Vr='Vrazten:BAAALgAECgEJAQABLgAECgYJDwAOAAAAAA==.',
Wh='Whisper:BAAALgADCgYJBgAAAA==.',
Wt='Wthdmas:BAAALgAECgkJBQAAAA==.',
Wy='Wyburn:BAAALgAECgUJCgAAAA==.Wyrm:BAAALgAECgUJBgAAAA==.',
['Yø']='Yøriçk:BAAALgAECgYJEwAAAA==.',
Za='Zane:BAAALgAECgYJBwAAAA==.Zaraelina:BAAALgAECgYJCQAAAA==.',
['Çl']='Çleadon:BAAALgAECgcJDgAAAA==.',
['ßê']='ßêästÿßöÿ:BAAALgAECgcJDAAAAA==.',
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
