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

local lookup = {'Shaman-Elemental','DeathKnight-Unholy','Druid-Guardian','Shaman-Restoration','Rogue-Subtlety','Druid-Restoration','Unknown-Unknown','Mage-Arcane','Paladin-Holy','Druid-Balance','Hunter-Survival','Paladin-Retribution','Monk-Brewmaster','Monk-Mistweaver','Mage-Frost','Priest-Holy','DeathKnight-Frost','Priest-Shadow','Hunter-BeastMastery','DeathKnight-Blood','Priest-Discipline','Rogue-Assassination','Rogue-Outlaw','Warlock-Demonology','Warlock-Destruction','Evoker-Augmentation','Evoker-Preservation','Hunter-Marksmanship','Shaman-Enhancement','Warrior-Protection','Warlock-Affliction','Druid-Feral','Warrior-Arms','DemonHunter-Havoc','DemonHunter-Vengeance','Monk-Windwalker','Paladin-Protection','Evoker-Devastation','DemonHunter-Devourer',}
local provider = {region='US',realm='KulTiras',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aarix:BAABNQAECn8fAAIBAAcKvQxIkAB4AQABAAcKvQxIkAB4AQAAAA==.',
Ae='Aendillan:BAAANQADCgUIBQAAAA==.',
Af='Affonasei:BAABNQAECn8hAAICAAcKHgiicwBFAQACAAcKHgiicwBFAQAAAA==.',
Ag='Agkistrodon:BAAANQADCgcIDQABNQAECgcIHwADANIhAA==.',
Ai='Aicaramba:BAABNQAECn8fAAIEAAkKRB87FgAdAwAEAAkKRB87FgAdAwAAAA==.Aileen:BAAANQAECgQICAAAAA==.',
Aj='Ajay:BAAANQAECgQIBAAAAA==.',
Ak='Akashi:BAAANQAECgcIEAABNQAFFAQICwAFAI4PAA==.',
Al='Alacrodie:BAAANQADCgUIFwAAAA==.',
Am='Amoonsi:BAAANQADCgMIAwABNQAECgcIHgAGAEwQAA==.Amordeyain:BAAANQAECgIIBAAAAA==.',
An='Angrydisc:BAAANQAECgYIDAABNQAECgcIEAAHAAAAAA==.Angrytotems:BAAANQAECgUIBwABNQAECgcIEAAHAAAAAA==.Annaborshen:BAAANQABCgIIAgAAAA==.Antoccino:BAAANQAECgYICwABNQAECgYIEAAHAAAAAA==.',
Ar='Aragorno:BAAANQAECgcIDgAAAA==.Arcturen:BAAANQAECgMICAAAAA==.Ardala:BAAANQAECggICAAAAA==.Arenthal:BAAANQAECgQICAABNQAECgkJNAAIAB4eAA==.Armonni:BAAANQABCgEIAQAAAA==.Arturaan:BAAANQABCggIGQAAAA==.',
As='Ashalana:BAAANQADCgUIBQAAAA==.Asheby:BAAANQADCgMIAwABNQAECgcIGwAJACARAA==.Ashenisson:BAAANQADCgQIBAABNQAECgMICAAHAAAAAA==.Ashiera:BAABNQAECn8eAAIIAAgKrAKrMAE3AQAIAAgKrAKrMAE3AQAAAA==.Ashrai:BAAANQADCgEIAQABNQAECgcIHwADANIhAA==.Astralmorph:BAAANQADCgYIBgAAAA==.',
At='Atomic:BAAANQAECgQIBgAAAA==.',
Au='Augenblick:BAAANQADCgIIAgAAAA==.Aurorée:BAAANQAECgQICAAAAA==.',
Av='Avattar:BAAANQABCgMIBQAAAA==.',
Az='Azylstrid:BAAANQADCgYIDAAAAA==.',
Ba='Baeu:BAAANQABCgUIBwAAAA==.Balentine:BAAANQAECgUIDwAAAA==.Banostraza:BAAANQAECgQIBQAAAA==.Baspir:BAABNQAECn8jAAIKAAkK4BXCKQCGAgAKAAkK4BXCKQCGAgAAAA==.',
Be='Beeboop:BAAANQADCgcICQAAAA==.Belly:BAABNQAECn8iAAILAAgKyx7xAwC5AgALAAgKyx7xAwC5AgAAAA==.Belrae:BAAANQAECggIDAAAAA==.Benchfresh:BAABNQAECn8ZAAIMAAcK8h0aegAzAgAMAAcK8h0aegAzAgAAAA==.Bendah:BAAANQAECgEIAQAAAA==.Bender:BAAANQADCgYIBgAAAA==.Bezieck:BAAANQAECgIIAwAAAA==.',
Bi='Bigfolks:BAAANQADCgUIBwAAAA==.Bigollock:BAAANQADCgYICwAAAA==.Bili:BAAANQADCgYIBgAAAA==.',
Bl='Bloodarrow:BAAANQADCgUIBwAAAA==.Bloodbound:BAAANQADCgYIBgAAAA==.',
Bo='Bockchi:BAAANQAECgQIBQAAAA==.Bonanas:BAAANQABCggICAAAAA==.Bonegavel:BAAANQABCgQIBgABNQABCgYIDAAHAAAAAA==.Bookhuntress:BAAANQAECgYIBgAAAA==.',
Br='Branex:BAAANQAECggICAAAAA==.Branpaw:BAAANQADCgMIAwAAAA==.Brewdeez:BAABNQAECn8oAAINAAgKjxcKDABDAgANAAgKjxcKDABDAgAAAA==.Brewzen:BAAANQADCgYIBgAAAA==.Brewzer:BAABNQAECn8qAAIOAAkKVA8XGgDaAQAOAAkKVA8XGgDaAQAAAA==.Brick:BAAANQADCgQIBAAAAA==.Brint:BAAANQADCgcICwAAAA==.Bronad:BAACNQAFFH8SAAMIAAUKfiVnGQCpAQAIAAQKlSZnGQCpAQAPAAIKzR/5BQCuAAA1AAQKf0IAAwgACQrVJpABAPQDAAgACQrVJpABAPQDAA8AAQo/H4xFADYAAAAA.Broomhandle:BAABNQAECn8hAAIMAAgKqh/3PwDSAgAMAAgKqh/3PwDSAgAAAA==.',
Bu='Bumbushka:BAAANQAECgcICwAAAA==.Burinn:BAAANQAECgMICAABNQAECggIJgAQACwWAA==.',
Ca='Caeus:BAABNQAECn8cAAMRAAcKpyE2KgBFAgARAAcKHR82KgBFAgACAAYKUhr6RgD4AQAAAA==.Cam:BAABNQAECn8VAAMIAAcKLiHApAA2AgAIAAcKLiHApAA2AgAPAAMKrhTNKQCmAAAAAA==.Carolinabele:BAAANQADCggICAAAAA==.Cauud:BAAANQADCgYIEAAAAA==.',
Cb='Cbd:BAAANQADCgcIEwAAAA==.',
Ce='Celerious:BAAANQABCgIIAgAAAA==.',
Ch='Chacruna:BAAANQAECgMIBgAAAA==.Chelan:BAABNQAECn8mAAMQAAgKLBZSVwAZAgAQAAgKLBZSVwAZAgASAAEKAAA0jwAZAAAAAA==.Chloelock:BAAANQABCgEJAQAAAA==.Chronicler:BAAANQADCgEIAQAAAA==.Chuntspeed:BAAANQADCgcICQAAAA==.Chuye:BAAANQAECgEIAQABNQAECgkJJAAQADUYAA==.',
Cl='Clambulance:BAABNQAECn8mAAITAAkKZxgDQwCgAgATAAkKZxgDQwCgAgAAAA==.',
Cn='Cnova:BAAANQAECgUIDgABNQAECgYICQAHAAAAAA==.',
Co='Codythedead:BAACNQAFFH8RAAMCAAUK9R/pCgBdAQACAAQK9R/pCgBdAQAUAAEKAAA8QAAOAAA1AAQKfzYAAgIACQoBJa8FAJ0DAAIACQoBJa8FAJ0DAAAA.Coraf:BAACNQAFFH8SAAIEAAUKTR6mCADDAQAEAAUKTR6mCADDAQA1AAQKfyQAAgQACQqZI4wNAFMDAAQACQqZI4wNAFMDAAAA.Coyotl:BAAANQAECgYIDwAAAA==.',
Cr='Crazyazshamy:BAAANQADCggIEAAAAA==.',
Cu='Cuvier:BAAANQADCggJFgAAAA==.',
Da='Daltenton:BAAANQAECgEIAQABNQAECggIHwAVAIIPAA==.Danak:BAAANQADCgUIEgAAAA==.Dascrazy:BAAANQADCgMIAwAAAA==.',
De='Deadlyfrosty:BAAANQADCgYIDgAAAA==.Deathmob:BAABNQAECn8dAAIUAAcKDh4YKgBxAgAUAAcKDh4YKgBxAgAAAA==.Deathsynth:BAAANQADCgQJBAABNQAECggIGAAIANwXAA==.Debixie:BAACNQAFFH8FAAIWAAIKNhsEFAClAAAWAAIKNhsEFAClAAA1AAQKfyUAAxYACQo2H2ILACsDABYACQo2H2ILACsDABcABgoEE9MNAGIBAAAA.Decisive:BAAANQADCgYIBgABNQAFFAgIFAAYAIQdAA==.Dejection:BAAANQABCgYIBwAAAA==.Demisi:BAAANQAECgYICgAAAA==.Demiurge:BAABNQAECn8kAAIKAAkKjxquHgDTAgAKAAkKjxquHgDTAgAAAA==.Despayr:BAAANQADCgYIBgAAAA==.',
Di='Diasundra:BAABNQAECn8pAAITAAkKaSFhFgBAAwATAAkKaSFhFgBAAwAAAA==.Dibbons:BAAANQAECgYIBwAAAA==.Divinatjin:BAAANQADCgYICQAAAA==.',
Do='Dollars:BAAANQAECgIIAgABNQAECgYICgAHAAAAAA==.Dottingyou:BAACNQAFFH8SAAMZAAUKGRdsDQCfAAAYAAMKYB99IQDuAAAZAAIK9hJsDQCfAAA1AAQKfyYAAxkACQrxIQQYAKsBABgABwqqItJVAFECABkABgrZGAQYAKsBAAAA.',
Dr='Dracthyrbm:BAAANQAECgMIAwAAAA==.Dreepy:BAAANQAECgUIBQAAAA==.Drransom:BAAANQADCgUIDgAAAA==.Dryan:BAAANQAECgYIEgAAAA==.',
Du='Duo:BAABNQAECn8oAAITAAgKFRnHTACFAgATAAgKFRnHTACFAgAAAA==.Duragon:BAABNQAECn8jAAMaAAgKGAoeDQB7AQAaAAgKGAoeDQB7AQAbAAEKtQDxVAAZAAAAAA==.',
Ei='Eipwoc:BAAANQADCggIBwAAAA==.Eistir:BAAANQAECgQIAwABNQAECgkJKQAYAPIYAA==.',
El='Eloreith:BAABNQAECn8iAAMKAAkKchcVKQCLAgAKAAkKchcVKQCLAgADAAUKvAjHPgC6AAAAAA==.',
Em='Emamagee:BAAANQADCgQIBgAAAA==.Emilia:BAABNQAECn8mAAIQAAgK/xgERQBVAgAQAAgK/xgERQBVAgAAAA==.',
En='Endressa:BAABNQAECn8pAAMVAAkKgRPIBQBCAgAVAAkKgRPIBQBCAgASAAQKZhHeQQAeAQAAAA==.',
Er='Eralendryn:BAAANQADCgEIAQAAAA==.Erelios:BAABNQAECn8cAAMJAAcK3wbtoABAAQAJAAcK3wbtoABAAQAMAAEKAADKqwEvAAAAAA==.',
Es='Eski:BAABNQAECn81AAMXAAkK9yEvAQCIAwAXAAkK9yEvAQCIAwAWAAIK2wnKkQBgAAAAAA==.Essaena:BAABNQAECn8eAAIUAAcKVyL6IACqAgAUAAcKVyL6IACqAgAAAA==.',
Eu='Eura:BAAANQADCgEIAQAAAA==.Eureka:BAEANQAECgYIEAAAAA==.',
Ev='Everlight:BAAANQADCggICAABNQAECgcIHwADANIhAA==.',
Fa='Faddeyshnek:BAABNQAECn8hAAITAAgKqA4SkADlAQATAAgKqA4SkADlAQAAAA==.Farmeador:BAAANQAECgEIAQAAAA==.Fastbeefball:BAAANQADCgcICQAAAA==.Fatgirljuice:BAABNQAFFH8RAAMTAAcKqiCRAAC5AgATAAcKqiCRAAC5AgAcAAIKrg8nHACMAAAAAA==.',
Fe='Felysambre:BAAANQAECgUIDQAAAA==.',
Fi='Fish:BAACNQAFFH8bAAISAAcKbCXoAADaAgASAAcKbCXoAADaAgA1AAQKfyoAAhIACQrrJt0AAOcDABIACQrrJt0AAOcDAAAA.',
Fl='Flight:BAACNQAFFH8LAAMFAAQKjg9iDADlAAAFAAMKUAhiDADlAAAWAAEKCx4QGwBXAAA1AAQKfy8AAxYACQrxH0wbAJ8CABYACApgIEwbAJ8CAAUABgpuFswgAMMBAAAA.Floofee:BAAANQADCgQIBAAAAA==.',
Fo='Footfinger:BAAANQAECgIIAgAAAA==.Forsynth:BAABNQAECn8YAAIIAAgK3BfAqAAvAgAIAAgK3BfAqAAvAgAAAA==.Foxymeatbal:BAAANQADCggIDQAAAA==.',
Fu='Fubar:BAAANQAECgUIBQAAAA==.',
Ga='Ganniy:BAAANQABCgEJAQAAAA==.',
Ge='Gewitt:BAAANQAECgQICAAAAA==.',
Gl='Glinda:BAAANQADCgUIDwAAAA==.',
Go='Gonjah:BAAANQAECgYIDwAAAA==.',
Gr='Grabomage:BAAANQAECgQIDAABNQAFFAUIEgAIAH4lAA==.Grabovoker:BAAANQADCgIIAgABNQAFFAUIEgAIAH4lAA==.Grazienne:BAAANQADCgUIEgAAAA==.Greavos:BAABNQAECn8bAAISAAcKShckJwDvAQASAAcKShckJwDvAQAAAA==.Griggus:BAAANQAECggIEwAAAA==.Grimgar:BAABNQAECn8gAAMPAAcKaBkbIgDXAAAIAAUK0hjRCAF7AQAPAAMKEBkbIgDXAAAAAA==.Grimmshady:BAAANQADCgQIBgAAAA==.Grumpsky:BAAANQADCgEIAQABNQAECgcIIAAEADQSAA==.',
Gu='Gumbles:BAABNQAECn8kAAMQAAkKNRj5NACRAgAQAAgK7xr5NACRAgASAAIKbQLmbgBHAAAAAA==.Gurney:BAABNQAECn8YAAMJAAkKDRhvMQCdAgAJAAkKDRhvMQCdAgAMAAEK9gTMzAEcAAAAAA==.Guzprimal:BAAANQAECgEIAQAAAA==.',
Gy='Gying:BAAANQAECgIIAgAAAA==.',
Ha='Hanekawa:BAABNQAECn8VAAIJAAgKHxmoPQBrAgAJAAgKHxmoPQBrAgABNQAECgkJKwAPAO4kAA==.Hannie:BAAANQADCgUIFQAAAA==.',
He='Headhúnter:BAAANQAECgYICAAAAA==.Heartsparx:BAABNQAECn8iAAIWAAgK2hRCJABiAgAWAAgK2hRCJABiAgAAAA==.Heatseeka:BAABNQAECn8hAAMEAAgKwROedgCkAQAEAAcK3xKedgCkAQAdAAcKYwKHIwAdAQAAAA==.Hexxiz:BAAANQAECgQIBQABNQAECgkJHgADADwiAA==.',
Hi='Hiphopinator:BAABNQAECn8fAAIeAAgKSiQ5BABIAwAeAAgKSiQ5BABIAwAAAA==.',
Ho='Ho:BAAANQADCgQIBAAAAA==.Holyshock:BAABNQAECn8wAAIJAAkKbhogLAC0AgAJAAkKbhogLAC0AgAAAA==.Holyterror:BAAANQADCgUIFwAAAA==.',
Ia='Ianthe:BAAANQAECgQIBAAAAA==.',
Ib='Iboga:BAAANQAECgQIEAAAAA==.Ibrahimovic:BAAANQADCggIEQAAAA==.',
Ig='Ignitecro:BAAANQABCgcIDwAAAA==.Igram:BAAANQAECgUIEQAAAA==.',
Il='Illumona:BAAANQAECgUIDAAAAA==.Iluz:BAAANQADCgMIAwAAAA==.',
In='Inafume:BAAANQADCggJEwAAAA==.Inoxia:BAAANQAECgQIDAAAAA==.Intrépidice:BAAANQAECgQIDQAAAA==.',
Ix='Ixtabay:BAABNQAECn8nAAQfAAkKAiB4AgD3AgAfAAkKQx14AgD3AgAZAAMK3Bc/PADPAAAYAAMKvQ3iDgGmAAAAAA==.',
Ja='Jamurra:BAAANQAECgIIBgABNQAECgQIBgAHAAAAAA==.Jaylinn:BAABNQAECn8oAAITAAgKyQeiogC9AQATAAgKyQeiogC9AQAAAA==.Jazzmend:BAAANQAECgQJBAAAAA==.',
Je='Jeanne:BAABNQAECn8kAAITAAgK+xpmUwB0AgATAAgK+xpmUwB0AgABNQAECgkJNQAXAPchAA==.Jellykins:BAABNQAECn8bAAIJAAcKIBHjfACfAQAJAAcKIBHjfACfAQAAAA==.',
Ji='Jimjamjuju:BAAANQAECgUICQAAAA==.Jimsonweed:BAAANQAECgUIDgAAAA==.',
Jo='Josie:BAABNQAECn8aAAIVAAgKHRzVAwCfAgAVAAgKHRzVAwCfAgAAAA==.Jozbirt:BAABNQAECn8mAAIgAAgKng5lEQDpAQAgAAgKng5lEQDpAQAAAA==.',
Ka='Kaeiria:BAAANQADCgQIBAAAAA==.Kael:BAAANQAECgYIEQAAAA==.Kalaanri:BAAANQAECgMICAAAAA==.Kalyandra:BAAANQAECgUIEQAAAA==.Karlach:BAAANQADCgUIBQABNQAECggIIgAWANoUAA==.Karumie:BAABNQAECn8mAAIEAAkKgxW8PwBeAgAEAAkKgxW8PwBeAgAAAA==.Kateera:BAAANQADCgQIBAAAAA==.',
Ke='Keden:BAAANQADCgUICAAAAA==.Kelesa:BAAANQAECgEIAQAAAA==.Keljaden:BAABNQAECn8hAAMhAAgKASXoGABTAwAhAAgKASXoGABTAwAeAAEKAABFPQBKAAAAAA==.Kenner:BAAANQAECgIIAgAAAA==.',
Kh='Kheyra:BAABNQAECn8fAAIDAAcK0iGSCwCtAgADAAcK0iGSCwCtAgAAAA==.',
Ki='Kirsha:BAAANQAECgQIBgAAAA==.Kittybeef:BAAANQABCgIIAgAAAA==.Kiwiiga:BAAANQAECgIIAwAAAA==.',
Kn='Knoxxic:BAAANQADCgMIBAAAAA==.',
Ko='Kohnor:BAAANQADCgUIFgAAAA==.Koopalizard:BAABNQAECn8ZAAIbAAgK9iCCCgD6AgAbAAgK9iCCCgD6AgAAAA==.Kopi:BAAANQAECgYIEAAAAA==.Korlatt:BAABNQAECn8bAAMiAAgK4R7IGwC4AgAiAAgKqR3IGwC4AgAjAAQKTCDbFwAuAQAAAA==.Kowalabear:BAAANQAECgEIAQAAAA==.',
Ku='Kuaha:BAAANQADCgYIBgABNQADCgQIBAAHAAAAAA==.Kupa:BAAANQADCgYJBwAAAA==.Kurom:BAAANQADCgcJDQAAAA==.Kurston:BAABNQAECn8mAAIGAAgK5iCBDwDbAgAGAAgK5iCBDwDbAgAAAA==.',
Ky='Ky:BAAANQADCgEIAQAAAA==.',
['Kã']='Kãtniss:BAAANQADCgUIFQAAAA==.',
La='Labella:BAAANQADCgYIDgAAAA==.Lacia:BAAANQAECgQIBAABNQAECgcIEAAHAAAAAA==.Laih:BAAANQAECgcIEwAAAA==.Landsong:BAAANQADCgQIBAAAAA==.',
Le='Leyote:BAABNQAECn8hAAIEAAcKCgy4mQBCAQAEAAcKCgy4mQBCAQAAAA==.',
Li='Liady:BAAANQADCgEJAQAAAA==.Lightshop:BAAANQADCgYICQAAAA==.Liirah:BAAANQADCgUIBwAAAA==.Lilyfox:BAAANQAECgYIEAAAAA==.Lindithrial:BAAANQABCggICAAAAA==.Livingdead:BAAANQADCggIKwAAAA==.',
Lo='Lorianne:BAAANQADCggJEAAAAA==.Lorraine:BAAANQADCggIDAAAAA==.Lowdangle:BAAANQADCgcIBwAAAA==.',
Lu='Lulz:BAAANQAECggICQAAAA==.Luucifur:BAAANQABCgMIAwAAAA==.',
Ma='Mackpumpkin:BAAANQAECgIIAgAAAA==.Macktheknife:BAAANQADCgQICAABNQAECgkJJwAfAAIgAA==.Madalyn:BAAANQADCgEIAQAAAA==.Maexna:BAAANQADCgIIAgAAAA==.Magdelyne:BAAANQAECggIEQAAAA==.Makklehaney:BAABNQAECn8WAAIBAAgKZwt3egCvAQABAAgKZwt3egCvAQAAAA==.Mallaah:BAAANQADCgUIBQAAAA==.Marovingian:BAABNQAECn8cAAIJAAgKLCOtFQAnAwAJAAgKLCOtFQAnAwAAAA==.Matthad:BAABNQAECn8dAAIEAAcK5hrmWwD4AQAEAAcK5hrmWwD4AQAAAA==.',
Mc='Mcnastie:BAAANQAECgQIBgAAAA==.Mcsluts:BAAANQADCgYJCwAAAA==.',
Me='Melmirict:BAAANQADCgMJAwAAAA==.Merciala:BAABNQAECn8jAAMKAAgKnwstTwCeAQAKAAgKnwstTwCeAQAGAAYKPQL8WACfAAAAAA==.',
Mi='Milyyanna:BAAANQADCgUIFQAAAA==.Mirilla:BAABNQAECn8bAAMPAAkKaQxOGQApAQAIAAkKzgusvQAHAgAPAAcKPAVOGQApAQAAAA==.',
Mo='Moddoxx:BAABNQAECn8cAAMYAAcKfBM9gwDZAQAYAAcKfBM9gwDZAQAZAAEKHA2qdwA1AAAAAA==.Moffa:BAAANQADCgMIAwAAAA==.Mohawk:BAABNQAECn8YAAIGAAkKYBYaGQBvAgAGAAkKYBYaGQBvAgAAAA==.Molen:BAAANQAECgEIAQAAAA==.Mommyjuice:BAAANQAECggIDgABNQAFFAcIEQATAKogAA==.Monkeeh:BAAANQADCggIDQAAAA==.Monkle:BAABNQAECn8mAAIkAAgK/yDoEQDMAgAkAAgK/yDoEQDMAgAAAA==.Monohan:BAAANQADCgUIBQABNQAECgcIHQAUAA4eAA==.Moonpaw:BAAANQAECgIIAgAAAA==.Moonsii:BAABNQAECn8eAAIGAAcKTBC4MwB4AQAGAAcKTBC4MwB4AQAAAA==.Mooroth:BAABNQAECn8hAAIeAAgKRBbWEQAGAgAeAAgKRBbWEQAGAgAAAA==.Morkilro:BAAANQABCgIIAgAAAA==.Morozko:BAAANQADCgQIBAAAAA==.',
Ms='Msasani:BAAANQADCgEIAQABNQAECgcIHwADANIhAA==.',
Mu='Muddler:BAAANQAECgUICQAAAA==.Muire:BAAANQAECgQIBAABNQAECgkJKQAYAPIYAA==.Murinn:BAABNQAECn8fAAITAAgKVgtJkQDjAQATAAgKVgtJkQDjAQAAAA==.',
['Mà']='Màggles:BAAANQAECgUIEQAAAA==.',
Na='Nadd:BAAANQAECgUICwAAAA==.Naledi:BAAANQADCggIDQAAAA==.Naralyn:BAABNQAECn8kAAMdAAkK2hflDgB6AgAdAAkK2hflDgB6AgABAAUKYRFhtAAlAQAAAA==.',
Ne='Negrido:BAABNQAECn8oAAQYAAgKTyGdPgCTAgAYAAcKkSGdPgCTAgAZAAMKiBtZNQDsAAAfAAIK7hXXGwCfAAAAAA==.Nei:BAABNQAECn8cAAIMAAYKbhVTwQCTAQAMAAYKbhVTwQCTAQAAAA==.Neon:BAAANQADCgUICQAAAA==.',
Ni='Nikem:BAAANQAECgcIEAAAAA==.',
No='Noelle:BAAANQAECgcIDQAAAA==.Norelei:BAAANQADCgcIDwABNQAECgcIHwADANIhAA==.Noriyuki:BAAANQAECgQICwAAAA==.',
Ny='Nyxahlia:BAAANQADCgUIBgAAAA==.',
Og='Oghom:BAAANQADCggICAAAAA==.Ogrekin:BAAANQAECgYICAAAAA==.',
Ol='Olderon:BAAANQAECgcIEAAAAA==.Olrong:BAABNQAECn8hAAIiAAcKTQnUTABmAQAiAAcKTQnUTABmAQAAAA==.Oluja:BAAANQAECgQIEQAAAA==.',
On='Onuris:BAAANQAECgIIBAAAAA==.',
Oo='Oogiboogi:BAAANQAECgMIAwAAAA==.',
Op='Opacuslupus:BAAANQAECgQICQAAAA==.Oppressin:BAABNQAECn8cAAIkAAgKXBcnIAApAgAkAAgKXBcnIAApAgAAAA==.',
Os='Oshunn:BAABNQAECn8lAAIIAAkK6xFipwAyAgAIAAkK6xFipwAyAgAAAA==.Osroes:BAAANQAECgQIEgAAAA==.',
Ov='Overdoom:BAABNQAECn8oAAMCAAgKJh6WLgB0AgACAAgKJh6WLgB0AgARAAUKrBOwXgAjAQAAAA==.',
Pa='Pacolock:BAAANQADCggICAAAAA==.Paladinjohn:BAACNQAFFH8RAAIMAAUKzCPJBQD3AQAMAAUKzCPJBQD3AQA1AAQKfycAAgwACQqbJQMUAHQDAAwACQqbJQMUAHQDAAAA.Palykat:BAAANQAECgUICgAAAA==.Pandadeez:BAAANQADCgUIBQAAAA==.Papiroflz:BAABNQAECn8nAAMBAAkKfCKQDQB6AwABAAkKfCKQDQB6AwAEAAUKexyPfgCMAQAAAA==.',
Pe='Pennywisé:BAABNQAECn8jAAIRAAgKmyCFGADDAgARAAgKmyCFGADDAgAAAA==.',
Pl='Plaguegying:BAABNQAECn8bAAIUAAgKRg9dVwCTAQAUAAgKRg9dVwCTAQABNQAECgIIAgAHAAAAAA==.Ploofee:BAAANQAECgMIBQAAAA==.',
Pr='Preparedr:BAACNQAFFH8tAAMWAAkKdiYBAAAMBAAWAAkKYCYBAAAMBAAFAAcKwSZ6AAC0AgA1AAQKfx0AAwUACQrrJbkJANkCAAUACAo/JrkJANkCABYABgrvJVwkAGECAAAA.Progresz:BAAANQAECgIIAgAAAA==.',
Pu='Purebread:BAAANQADCgUIBQAAAA==.',
Py='Pykel:BAABNQAECn8mAAIKAAkKBwhjTQCnAQAKAAkKBwhjTQCnAQAAAA==.',
Qa='Qaren:BAAANQADCgYIEAAAAA==.',
Ra='Raishun:BAAANQAECgEJAQAAAA==.Raizo:BAAANQAECgEIAQAAAA==.Rake:BAABNQAECn8oAAIgAAgKrB/BBgD6AgAgAAgKrB/BBgD6AgAAAA==.Rannï:BAAANQADCgQIBAABNQAECgkJJwAfAAIgAA==.Raskreia:BAAANQAECgYICgABNQAECgkJKwAPAO4kAA==.Rassina:BAAANQADCgEIAQAAAA==.Rawk:BAAANQAECgEIAQAAAA==.',
Re='Redeemly:BAAANQAECggICgAAAA==.Redeyejedi:BAAANQAECggIBwAAAA==.Reeven:BAAANQAECggIGQAAAQ==.Revokely:BAAANQAECgYIDgABNQAECggICgAHAAAAAA==.',
Rh='Rhcpmage:BAAANQADCggICgABNQAFFAUIEgAIAH4lAA==.Rhetegast:BAABNQAECn8pAAIlAAkKChtUEACWAgAlAAkKChtUEACWAgAAAA==.',
Ri='Rieloesh:BAAANQAECgIIAwAAAA==.Rike:BAABNQAECn8gAAMlAAcKsB6LHgDxAQAMAAcKmhtLiAARAgAlAAYKVB6LHgDxAQAAAA==.Ristretto:BAAANQADCgYICwABNQAECgYIEAAHAAAAAA==.',
Ro='Roland:BAAANQADCgUJBwAAAA==.Rolandin:BAABNQAECn8hAAIJAAcKlRJldQC0AQAJAAcKlRJldQC0AQAAAA==.',
Ru='Rukraga:BAAANQAECgQJBAAAAA==.',
Ry='Rylagosa:BAABNQAECn8aAAIbAAcKnBu/GAAwAgAbAAcKnBu/GAAwAgAAAA==.Ryzesmidge:BAAANQAECgcJDAAAAA==.',
['Rê']='Rêdrum:BAAANQAECgYIBgABNQAECggIJgAjAJEcAA==.',
Sa='Salandria:BAABNQAECn8fAAQlAAgKyxs+GQAoAgAlAAgKyxs+GQAoAgAJAAUKSSQOXQD/AQAMAAEKAABImQE3AAAAAA==.Sarionian:BAAANQAECgUIDwAAAA==.Sarjin:BAAANQADCgcIDQABNQAECgcIHwADANIhAA==.Sarvinblue:BAABNQAECn80AAMEAAkKaCEzEABBAwAEAAkKaCEzEABBAwABAAcKmBZgaADjAQAAAA==.',
Sc='Scopolamine:BAAANQAECgQICQAAAA==.',
Se='Sevrin:BAABNQAECn8oAAIUAAgKuw/JSQDOAQAUAAgKuw/JSQDOAQAAAA==.Seymonty:BAABNQAECn8fAAMVAAgKgg8oDgBLAQAQAAgK7AguhACGAQAVAAYKWhAoDgBLAQAAAA==.',
Sh='Shaeko:BAAANQADCggIGQAAAA==.Shazlulu:BAAANQAECgUICgAAAA==.Shaznoir:BAABNQAECn8eAAIZAAcKpgVRKAA1AQAZAAcKpgVRKAA1AQAAAA==.Shilajit:BAAANQAECgMICAAAAA==.Shokz:BAAANQADCgMIAwABNQAECgMIBQAHAAAAAA==.',
Sk='Skip:BAAANQADCgcIBwAAAA==.Skøøma:BAAANQABCgIIBAAAAA==.',
Sl='Slicer:BAAANQABCgQIBAAAAA==.Sloe:BAAANQAECgEIAQABNQAECgcIGwAJACARAA==.',
Sm='Smokalot:BAAANQADCggICAAAAA==.Smokehunter:BAAANQADCgYIBgAAAA==.',
Sn='Snoop:BAAANQADCgYICgAAAA==.',
So='Solstîce:BAAANQADCgQIBAABNQAECggIJgAjAJEcAA==.',
Sp='Speedbeefbal:BAAANQADCgYIDAAAAA==.Speeddwrfbal:BAAANQADCgYIEwAAAA==.Speedmeatbal:BAAANQAECgcIDgAAAA==.Speedmeatlok:BAAANQADCggIDAAAAA==.Speedmonkbal:BAAANQADCggIEQAAAA==.Speedoe:BAAANQADCggIDwAAAA==.Spidêrs:BAAANQABCgQICAAAAA==.Sporkulous:BAABNQAECn8cAAITAAcKqghVtwCQAQATAAcKqghVtwCQAQAAAA==.',
Sq='Squal:BAAANQAECgYICQAAAA==.Squiggle:BAABNQAECn8WAAIlAAgKWxnWHAACAgAlAAgKWxnWHAACAgAAAA==.',
St='Steevii:BAAANQADCgMJAwAAAA==.Stewie:BAAANQAECgQIBQAAAA==.Striker:BAAANQADCgYIDwABNQAECgcIIAAlALAeAA==.Strikers:BAAANQABCgIIAgAAAA==.',
Su='Sunshíne:BAAANQAECgUIDQAAAA==.',
Sy='Syver:BAABNQAECn8YAAICAAgK+xi7QAAXAgACAAgK+xi7QAAXAgAAAA==.',
['Sí']='Sírlancealot:BAAANQADCgMIBAAAAA==.',
Ta='Takeke:BAABNQAECn8WAAMUAAkK2A0hXAB/AQAUAAgKJQ0hXAB/AQACAAUKUgvBhwD+AAAAAA==.Takeroux:BAAANQAECgEIAQAAAA==.Talandroz:BAABNQAECn8dAAMbAAgKvhyaEQCPAgAbAAgKvhyaEQCPAgAmAAIKTAv5NABiAAAAAA==.Tanagra:BAAANQADCgIIAgABNQAECgcIHAAYAHwTAA==.Tankz:BAAANQADCgUIBQAAAA==.Tanner:BAABNQAECn8wAAITAAkKyhq2QQCjAgATAAkKyhq2QQCjAgAAAA==.',
Te='Tebo:BAAANQAECgEIAgAAAA==.Teboe:BAAANQADCgYIBgABNQAECgEIAgAHAAAAAA==.Tedman:BAABNQAECn8ZAAMBAAgK9Q+5iACKAQABAAcKLg65iACKAQAEAAUKgg3stAD/AAAAAA==.Temel:BAABNQAECn8gAAMEAAcKNBKAcgCwAQAEAAcKNBKAcgCwAQABAAQKXAdN6gC8AAAAAA==.Teostra:BAABNQAECn8cAAMTAAgK5x/kPQCuAgATAAgK5x/kPQCuAgAcAAEKyAoOhgA2AAAAAA==.Testoecles:BAAANQADCgcICwABNQAECgEIAgAHAAAAAA==.',
Th='Thadrack:BAAANQAECgcIEAAAAA==.Thalonstin:BAAANQADCgUIFwAAAA==.Thaneold:BAAANQAECgQJCQABNQAECgkJKAAQAFQjAA==.Thassarian:BAAANQAECgQIBwABNQAECgYIEAAHAAAAAA==.Theodrid:BAACNQAFFH8SAAIlAAYKpBk7AgAVAgAlAAYKpBk7AgAVAgA1AAQKfykAAiUACQq5IikIABoDACUACQq5IikIABoDAAAA.Thunderstomp:BAAANQADCgIIAgAAAA==.',
Ti='Tinkerspell:BAAANQADCgYICwAAAA==.Tinkíe:BAABNQAECn8mAAIOAAgKxx8OCwDRAgAOAAgKxx8OCwDRAgAAAA==.Tirzahdozier:BAAANQAECgEIAgABNQAECgQIBgAHAAAAAA==.Tiwohnne:BAAANQAECgUIBQAAAA==.',
Tl='Tla:BAAANQADCgUIEwAAAA==.',
Tp='Tpaartos:BAAANQADCgIJAgABNQAECgcIHQAEAOYaAA==.',
Tr='Treat:BAABNQAECn8hAAISAAgK0yKrCgA2AwASAAgK0yKrCgA2AwAAAA==.Trippyshock:BAAANQADCgEIAQABNQAFFAgIFAAYAIQdAA==.Tristitia:BAAANQABCgYICgAAAA==.',
Tu='Turkeltin:BAABNQAECn8eAAInAAkKoSMfAwCmAwAnAAkKoSMfAwCmAwAAAA==.',
Tw='Twiggle:BAAANQADCgYIBgABNQAECgQIBgAHAAAAAA==.Twistedsquid:BAAANQABCgQIBAAAAA==.',
Ty='Tyamat:BAABNQAECn8YAAMfAAcK9hXmCQDcAQAfAAcK9hXmCQDcAQAYAAIKGwWJLwFUAAAAAA==.Tyche:BAAANQADCgYIDAAAAA==.Tyrinara:BAAANQADCggICAAAAA==.',
Ui='Uiewedaoez:BAABNQAECn8hAAIGAAgKDCXzBwBDAwAGAAgKDCXzBwBDAwAAAA==.',
Va='Vains:BAABNQAECn8oAAIMAAkKPh0dSwCwAgAMAAkKPh0dSwCwAgAAAA==.Valrith:BAAANQADCgcIGAAAAA==.',
Ve='Velexi:BAAANQABCggIEgAAAA==.Velody:BAAANQADCgQIAQAAAA==.Vendettuh:BAAANQADCgYIBgAAAA==.Veronica:BAABNQAECn8ZAAIIAAcKJQ4n8gCjAQAIAAcKJQ4n8gCjAQAAAA==.Verren:BAABNQAECn8cAAIDAAgK3hHAHAC2AQADAAgK3hHAHAC2AQAAAA==.Vesfor:BAAANQADCgEIAQABNQAECgMICAAHAAAAAA==.Vestus:BAAANQABCgcIDAAAAA==.',
Vy='Vyrridyl:BAAANQAECgMICAAAAA==.',
Wa='Waddlez:BAAANQAECgYIBgAAAA==.Watermark:BAABNQAECn8bAAIEAAcKagutmQBCAQAEAAcKagutmQBCAQAAAA==.',
We='Weeblewobble:BAAANQAECgEIAgAAAA==.Weltamus:BAAANQADCgYIEAAAAA==.Weltazar:BAABNQAECn8aAAIBAAcKzRQKbwDPAQABAAcKzRQKbwDPAQAAAA==.Weltzilla:BAABNQAECn8aAAITAAgKaRkCYQBSAgATAAgKaRkCYQBSAgAAAA==.Westside:BAAANQAECgYICgAAAA==.',
Wh='Whoosh:BAABNQAECn8iAAIUAAgKlyIvFgD5AgAUAAgKlyIvFgD5AgAAAA==.',
Wi='Wickët:BAABNQAECn8mAAMEAAgK6iPVFQAfAwAEAAgK6iPVFQAfAwABAAYKpR9fWAAXAgAAAA==.Wildtiger:BAABNQAECn8eAAIgAAgKGRH9EADyAQAgAAgKGRH9EADyAQAAAA==.',
Wo='Wolfslied:BAAANQADCgQIBAABNQADCgQIBAAHAAAAAA==.',
Wu='Wulfenhide:BAABNQAECn8aAAIWAAcK2iCJHwCAAgAWAAcK2iCJHwCAAgAAAA==.',
Wy='Wyzsky:BAAANQADCgUIHAABNQAECgcIIAAEADQSAA==.',
Xa='Xalreth:BAABNQAECn8YAAInAAgKPgjtNgCHAQAnAAgKPgjtNgCHAQAAAA==.Xaviana:BAAANQAECgUIBQAAAQ==.',
Ya='Yastypoo:BAABNQAECn8fAAIJAAkK9xDbUwAbAgAJAAkK9xDbUwAbAgAAAA==.',
Za='Zarieda:BAAANQAECgcIDQAAAA==.Zayrelia:BAACNQAFFH8OAAIGAAUKNQ3+BwBvAQAGAAUKNQ3+BwBvAQA1AAQKfzQAAwYACQplHGMNAPYCAAYACQplHGMNAPYCAAoABgphFctPAJsBAAAA.',
Ze='Zelenor:BAAANQAECgEIAgABNQAECgcIGAAfAPYVAA==.',
Zu='Zud:BAABNQAECn8ZAAICAAcKHh8vOwAyAgACAAcKHh8vOwAyAgAAAA==.',
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
