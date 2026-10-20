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

local lookup = {'Shaman-Elemental','DeathKnight-Unholy','Druid-Guardian','Shaman-Restoration','Rogue-Subtlety','Druid-Restoration','Unknown-Unknown','DemonHunter-Vengeance','Hunter-BeastMastery','Mage-Arcane','Paladin-Holy','Druid-Balance','Hunter-Survival','Paladin-Retribution','Monk-Brewmaster','Monk-Mistweaver','Mage-Frost','Priest-Holy','DeathKnight-Frost','Priest-Shadow','DeathKnight-Blood','Priest-Discipline','Rogue-Assassination','Rogue-Outlaw','Warlock-Demonology','Warlock-Destruction','Evoker-Augmentation','Evoker-Preservation','Hunter-Marksmanship','DemonHunter-Devourer','Warrior-Arms','Shaman-Enhancement','Warrior-Protection','Warlock-Affliction','Druid-Feral','Monk-Windwalker','DemonHunter-Havoc','Paladin-Protection','Evoker-Devastation',}
local provider = {region='US',realm='KulTiras',name='US',type='weekly',zone=53,date='2026-10-20',data={Aa='Aarix:BAABNQAECn8fAAIBAAcKvQwXkgB3AQABAAcKvQwXkgB3AQAAAA==.',
Ae='Aendillan:BAAANQADCgUIBQAAAA==.',
Af='Affonasei:BAABNQAECn8nAAICAAcKXgi8dABFAQACAAcKXgi8dABFAQAAAA==.',
Ag='Agkistrodon:BAAANQADCgcIDQABNQAECgcIJgADAPEhAA==.',
Ai='Aicaramba:BAABNQAECn8lAAIEAAoKwyCbFgAcAwAEAAoKwyCbFgAcAwAAAA==.Aileen:BAAANQAECgQICwAAAA==.',
Aj='Ajay:BAAANQAECgYIBgAAAA==.',
Ak='Akashi:BAAANQAECggIEwABNQAFFAQIDwAFAKMSAA==.',
Al='Alacrodie:BAAANQADCgYIHAAAAA==.',
Am='Amoonsi:BAAANQADCgMIAwABNQAECggIIwAGACoPAA==.Amordeyain:BAAANQAECgIIBgAAAA==.',
An='Angrydisc:BAAANQAECgcIEQAAAA==.Angrytotems:BAAANQAECgUIBwABNQAECgcIEQAHAAAAAA==.Angyll:BAAANQABCggIFgAAAA==.Annaborshen:BAAANQABCgIIAgAAAA==.Antoccino:BAAANQAECgYICwABNQAECgcIGgAIAPYeAA==.',
Ar='Aragorno:BAABNQAECn8aAAIJAAkKSxMSJwB+AQAJAAkKSxMSJwB+AQAAAA==.Arcturen:BAAANQAECgQIDAAAAA==.Ardala:BAAANQAECggICQAAAA==.Arenthal:BAAANQAECgQICAABNQAECgoKNgAKACEcAA==.Armonni:BAAANQABCgIIAgAAAA==.',
As='Ashalana:BAAANQADCgUIBQAAAA==.Asheby:BAAANQADCgMIAwABNQAECgcIGwALACARAA==.Ashenisson:BAAANQADCgQIBAABNQAECgQIDAAHAAAAAA==.Ashiera:BAABNQAECn8eAAIKAAgKrAKVMwE2AQAKAAgKrAKVMwE2AQAAAA==.Ashrai:BAAANQADCgEIAQABNQAECgcIJgADAPEhAA==.Astralmorph:BAAANQADCgYIBgAAAA==.',
At='Atomic:BAAANQAECgQIBwAAAA==.',
Au='Augenblick:BAAANQADCgIIAgAAAA==.Aurorée:BAAANQAECgUIDAAAAA==.',
Av='Avattar:BAAANQABCgMIBQAAAA==.',
Az='Azylstrid:BAAANQADCgYIDAAAAA==.',
Ba='Baeu:BAAANQABCgUIBwAAAA==.Balentine:BAAANQAECgUIEgAAAA==.Banostraza:BAAANQAECgQIBQAAAA==.Baspir:BAABNQAECn8oAAIMAAoK5RU1KgCGAgAMAAoK5RU1KgCGAgAAAA==.',
Be='Belly:BAABNQAECn8oAAINAAgKqB/cAQCjAQANAAgKqB/cAQCjAQAAAA==.Belrae:BAAANQAECggIEgAAAA==.Benchfresh:BAABNQAECn8cAAIOAAgK+htbfAAyAgAOAAgK+htbfAAyAgAAAA==.Bendah:BAAANQAECgEIAQAAAA==.Bender:BAAANQADCgYIBgAAAA==.Bezieck:BAAANQAECgIIAwAAAA==.',
Bi='Bigfolks:BAAANQADCgUIBwAAAA==.Bigollock:BAAANQADCgYICwAAAA==.Bili:BAAANQAECgEIAQAAAA==.',
Bl='Bloodarrow:BAAANQADCgUIBwAAAA==.Bloodbound:BAAANQADCgYIBgAAAA==.',
Bo='Bockchi:BAAANQAECgQIBQAAAA==.Bonanas:BAAANQABCggICAAAAA==.Bonegavel:BAAANQABCgQIBgABNQABCgYIDAAHAAAAAA==.Bookhuntress:BAAANQAECgYIBgAAAA==.',
Br='Branex:BAAANQAECggICAAAAA==.Branpaw:BAAANQADCgQIAwAAAA==.Brewdeez:BAABNQAECn8oAAIPAAgKjxctDABCAgAPAAgKjxctDABCAgAAAA==.Brewzen:BAAANQADCgYIBgAAAA==.Brewzer:BAABNQAECn8qAAIQAAkKVA9eGgDaAQAQAAkKVA9eGgDaAQAAAA==.Brint:BAAANQADCgcIDAAAAA==.Bronad:BAACNQAFFH8XAAMKAAYK0yUXBQBbAQAKAAUKqSYXBQBbAQARAAIKzR8jBgCuAAA1AAQKf00AAwoACgq5JZ8BAPMDAAoACgq5JZ8BAPMDABEAAQo/H2VGADYAAAAA.Broomhandle:BAABNQAECn8mAAIOAAgKqh9fQQDQAgAOAAgKqh9fQQDQAgAAAA==.',
Bu='Bumbushka:BAAANQAECgcICwAAAA==.Burinn:BAAANQAECgQIDAABNQAECgkJLgASABYaAA==.Butche:BAAANQAECgEIAQAAAA==.',
Ca='Caeus:BAABNQAECn8iAAMTAAgKzh3lEAB+AQACAAYKUhrURwD4AQATAAgKsBvlEAB+AQAAAA==.Cam:BAABNQAECn8VAAMKAAcKLiE5pgA1AgAKAAcKLiE5pgA1AgARAAMKrhRRKgCmAAAAAA==.Carolinabele:BAAANQADCggICAAAAA==.Cauud:BAAANQADCgYIEAAAAA==.',
Cb='Cbd:BAAANQADCgcIEwAAAA==.',
Ce='Celerious:BAAANQABCgIIAgAAAA==.',
Ch='Chacruna:BAAANQAECgMIBgAAAA==.Chelan:BAABNQAECn8uAAMSAAkKFhqSBgCIAgASAAkKFhqSBgCIAgAUAAEKAAAUkQAZAAAAAA==.Chloelock:BAAANQABCgEJAQAAAA==.Chronicler:BAAANQADCgEIAQAAAA==.Chuntspeed:BAAANQADCgcIDAAAAA==.Chuye:BAAANQAECgIIAgABNQAECgoKKwASAKUcAA==.',
Cl='Clambulance:BAABNQAECn8qAAIJAAoKZBbUQwCfAgAJAAoKZBbUQwCfAgAAAA==.',
Cn='Cnova:BAAANQAECgUIDwABNQAECgcIEAAHAAAAAA==.',
Co='Codythedead:BAACNQAFFH8XAAMCAAYKoB3FAABuAQACAAYKoB3FAABuAQAVAAEKAAAkQQAOAAA1AAQKfzsAAgIACgoyJLcFAJ4DAAIACgoyJLcFAJ4DAAAA.Coraf:BAACNQAFFH8XAAIEAAYKNB53AwCmAQAEAAYKNB53AwCmAQA1AAQKfycAAgQACgqsI8oNAFMDAAQACgqsI8oNAFMDAAAA.Coyotl:BAABNQAECn8aAAINAAgKCg75AQCaAQANAAgKCg75AQCaAQAAAA==.',
Cr='Crazyazshamy:BAAANQAECgQIBAAAAA==.',
Cu='Cuvier:BAAANQADCggJFgAAAA==.',
Da='Daltenton:BAAANQAECgEIAQABNQAECggIIQAWAIIPAA==.Danak:BAAANQADCgYIFwAAAA==.Dascrazy:BAAANQADCgMIAwAAAA==.',
De='Deadlyfrosty:BAAANQADCgYIDgAAAA==.Deathmob:BAABNQAECn8jAAIVAAgKChx1DwBnAQAVAAgKChx1DwBnAQAAAA==.Deathsynth:BAAANQADCgQJBAABNQAECggIHwAKAPoXAA==.Debixie:BAACNQAFFH8FAAIXAAIKNhuJFAClAAAXAAIKNhuJFAClAAA1AAQKfyUAAxcACQo2H0wKADoDABcACQo2H0wKADoDABgABgoEE+QNAGIBAAAA.Decisive:BAAANQADCgYIBgABNQAFFAkJFgAZAHwcAA==.Dejection:BAAANQABCgYIBwAAAA==.Demisi:BAAANQAECgYICgAAAA==.Demiurge:BAABNQAECn8nAAIMAAkK8BoEHwDSAgAMAAkK8BoEHwDSAgABNQAECggIKAAZAOUZAA==.Despayr:BAAANQADCgYIBgAAAA==.',
Di='Diasundra:BAABNQAECn8tAAIJAAoK2B/OFgA/AwAJAAoK2B/OFgA/AwAAAA==.Dibbons:BAAANQAECgYIBwAAAA==.Divinatjin:BAAANQADCgYICQAAAA==.',
Do='Dollars:BAAANQAECgIIBAABNQAECgYIDgAHAAAAAA==.Dottingyou:BAACNQAFFH8XAAMaAAYKJxIrAwCXAAAZAAQKVxHMIQDqAAAaAAIK9hIrAwCXAAA1AAQKfykAAxoACgrwIS4YAKsBABkACAqKIj9XAFACABoABgrZGC4YAKsBAAAA.Doubleedged:BAAANQAECgEIAQAAAA==.',
Dr='Dracthyrbm:BAAANQAECgQIBQAAAA==.Dragonshide:BAAANQADCgQIBAABNQAECgkJIgAaAHYeAA==.Dreepy:BAAANQAECgYIBQAAAA==.Drransom:BAAANQADCgYIEwAAAA==.Dryan:BAABNQAECn8cAAIDAAcKHRcsGwDKAQADAAcKHRcsGwDKAQAAAA==.',
Du='Duo:BAABNQAECn8vAAIJAAkKFRhFJACHAQAJAAkKFRhFJACHAQAAAA==.Duragon:BAABNQAECn8jAAMbAAgKGApEDQB7AQAbAAgKGApEDQB7AQAcAAEKtQAAVgAZAAAAAA==.',
Ei='Eipwoc:BAAANQADCggIBwAAAA==.Eistir:BAAANQAECgUICAABNQAECgoKMAAZAHYZAA==.',
El='Eloreith:BAABNQAECn8lAAMMAAkK6BiJKQCLAgAMAAkK6BiJKQCLAgADAAUKvAjzPwC7AAAAAA==.',
Em='Emamagee:BAAANQADCgQIBgAAAA==.Emilia:BAABNQAECn8tAAISAAgKqRkNFgDAAQASAAgKqRkNFgDAAQAAAA==.',
En='Endressa:BAABNQAECn8xAAMWAAoKNhh7AABIAgAWAAoKNhh7AABIAgAUAAQKZhGbQgAeAQAAAA==.',
Er='Eralendryn:BAAANQADCgEIAQAAAA==.Erelios:BAABNQAECn8iAAMLAAgKAQfXPQDyAAALAAgKAQfXPQDyAAAOAAEKAAAHsgEvAAAAAA==.',
Es='Eski:BAABNQAECn89AAMYAAoKvyBYAAA3AgAYAAoKvyBYAAA3AgAXAAIK2wn3lABgAAAAAA==.Essaena:BAABNQAECn8gAAIVAAgKNSFkIQCpAgAVAAgKNSFkIQCpAgAAAA==.',
Eu='Eura:BAAANQADCgEIAQAAAA==.Eureka:BAEANQAECgYIEAAAAA==.',
Ev='Everlight:BAAANQADCggIEAABNQAECgcIJgADAPEhAA==.',
Ez='Ezrì:BAAANQADCgUIBQAAAA==.',
Fa='Faddeyshnek:BAABNQAECn8oAAIJAAgKzQ9uIQCSAQAJAAgKzQ9uIQCSAQAAAA==.Farmeador:BAAANQAECgEIAQAAAA==.Fastbeefball:BAAANQADCggIEAAAAA==.Fatgirljuice:BAABNQAFFH8VAAMJAAcK1yCgAAC5AgAJAAcK1yCgAAC5AgAdAAIKrg+tHACMAAAAAA==.',
Fe='Felysambre:BAABNQAECn8YAAIeAAYKpgxqIQCmAAAeAAYKpgxqIQCmAAAAAA==.',
Fi='Fish:BAACNQAFFH8dAAIUAAgKZiT2AADZAgAUAAgKZiT2AADZAgA1AAQKfysAAhQACgqLJusAAOYDABQACgqLJusAAOYDAAAA.',
Fl='Flight:BAACNQAFFH8PAAMFAAQKoxKYDADlAAAFAAMK7wyYDADlAAAXAAEKCx7iBwBZAAA1AAQKfzMAAxcACgpRINAbAKACABcACQq+INAbAKACAAUABgpuFjkhAMMBAAAA.Floofee:BAAANQADCgQIBAAAAA==.',
Fo='Footfinger:BAAANQAECgIIAgAAAA==.Forsynth:BAABNQAECn8fAAIKAAgK+hfIGwCgAQAKAAgK+hfIGwCgAQAAAA==.Foxymeatbal:BAAANQADCggIDQAAAA==.',
Fu='Fubar:BAAANQAECgYIBgAAAA==.',
Ga='Ganniy:BAAANQABCgEJAQAAAA==.',
Ge='Gewitt:BAAANQAECgQICAAAAA==.',
Gl='Glinda:BAAANQADCgUIDwAAAA==.',
Go='Gonjah:BAAANQAECgYIEgAAAA==.',
Gr='Grabomage:BAAANQAECgYIDgABNQAFFAYIFwAKANMlAA==.Grabovoker:BAAANQADCgIIAgABNQAFFAYIFwAKANMlAA==.Grazienne:BAAANQADCgUIEgAAAA==.Greavos:BAABNQAECn8hAAIUAAcKZxvOCwBAAQAUAAcKZxvOCwBAAQAAAA==.Griggus:BAABNQAECn8fAAIfAAoKrBGmGwCWAQAfAAoKrBGmGwCWAQAAAA==.Grimgar:BAABNQAECn8mAAMKAAcKaBl2agDnAAAKAAUK0hh2agDnAAARAAMKEBmZIgDXAAAAAA==.Grimmshady:BAAANQADCgQIBgAAAA==.Grumpsky:BAAANQADCgEIAQABNQAECggIJwAEAKQSAA==.',
Gu='Gumbles:BAABNQAECn8rAAMSAAoKpRzREgDdAQASAAoKpRzREgDdAQAUAAIKbQI7cABIAAAAAA==.Gurney:BAABNQAECn8YAAMLAAkKDRgrMgCcAgALAAkKDRgrMgCcAgAOAAEK9gRm0wEcAAAAAA==.Guzprimal:BAAANQAECgEIAQAAAA==.',
Gw='Gwenory:BAAANQABCgQIBAAAAA==.',
Gy='Gying:BAAANQAECgIIAgAAAA==.',
Ha='Hanekawa:BAABNQAECn8WAAILAAkKeBmdPgBqAgALAAkKeBmdPgBqAgABNQAFFAIIBQARANUfAA==.Hannie:BAAANQADCgYIGgAAAA==.',
He='Headhúnter:BAAANQAECgYICAAAAA==.Heartsparx:BAABNQAECn8qAAIXAAkKOhNzCACVAQAXAAkKOhNzCACVAQAAAA==.Heatseeka:BAABNQAECn8iAAMEAAkKPBL0dwCkAQAEAAgKRhH0dwCkAQAgAAcKYwLzIwAdAQAAAA==.Heitan:BAAANQAECgYIBwABNQAECgoKMAAZAHYZAA==.Hexxiz:BAAANQAECgQIBQABNQAECgkJIQADAFEiAA==.',
Hi='Hiphopinator:BAABNQAECn8mAAIhAAgKXSQ5AQBhAgAhAAgKXSQ5AQBhAgAAAA==.',
Ho='Ho:BAAANQADCgQIBAAAAA==.Holyshock:BAABNQAECn81AAILAAoK5xmkLAC0AgALAAoK5xmkLAC0AgAAAA==.Holyterror:BAAANQADCgUIFwAAAA==.',
Ia='Ianthe:BAAANQAECgYIBwAAAA==.',
Ib='Iboga:BAAANQAECgQIEQAAAA==.Ibrahimovic:BAAANQADCggIEQAAAA==.',
Ig='Ignitecro:BAAANQABCgcIDwAAAA==.Igram:BAAANQAECgcIEgAAAA==.',
Il='Illumona:BAAANQAECgYIDwAAAA==.Iluz:BAAANQADCgMIAwAAAA==.',
In='Inafume:BAAANQADCggJEwAAAA==.Inoxia:BAAANQAECgUIDgAAAA==.Intrépidice:BAAANQAECgQIDQAAAA==.',
Ix='Ixtabay:BAABNQAECn8nAAQiAAkKAiB7AgD3AgAiAAkKQx17AgD3AgAaAAMK3BeIPADPAAAZAAMKvQ1BEgGmAAAAAA==.',
Ja='Jamurra:BAAANQAECgIIBgABNQAECgcICwAHAAAAAA==.Jaylinn:BAABNQAECn8oAAIJAAgKyQfmpAC8AQAJAAgKyQfmpAC8AQAAAA==.Jazzmend:BAAANQAECgQJBAAAAA==.',
Je='Jeanne:BAABNQAECn8nAAIJAAkKtBjlVABzAgAJAAkKtBjlVABzAgABNQAECgoKPQAYAL8gAA==.Jellykins:BAABNQAECn8bAAILAAcKIBEQfgCfAQALAAcKIBEQfgCfAQAAAA==.',
Ji='Jimjamjuju:BAAANQAECgUICQAAAA==.Jimsonweed:BAAANQAECgYIDwAAAA==.',
Jo='Josie:BAABNQAECn8kAAMWAAoKeRqlAAAaAgAWAAkKvBqlAAAaAgAUAAEKqwYmNgArAAAAAA==.Jozbirt:BAABNQAECn8mAAIjAAgKng6tEQDmAQAjAAgKng6tEQDmAQAAAA==.',
Ka='Kaeiria:BAAANQADCgQIBAAAAA==.Kael:BAABNQAECn8aAAMEAAcKPxebGwCBAQAEAAYKoRSbGwCBAQABAAcKwQgvoABWAQAAAA==.Kalaanri:BAAANQAECgQIDAAAAA==.Kalyandra:BAABNQAECn8XAAIkAAYKAA6+GADiAAAkAAYKAA6+GADiAAAAAA==.Karlach:BAAANQADCgYIBwABNQAECgkJKgAXADoTAA==.Karumie:BAABNQAECn8qAAIEAAoK/xeNQABeAgAEAAoK/xeNQABeAgAAAA==.Kateera:BAAANQADCgQIBAAAAA==.',
Ke='Keden:BAAANQADCgUICAAAAA==.Kelesa:BAAANQAECgEIAQAAAA==.Keljaden:BAABNQAECn8oAAMfAAkK7CNsGQBSAwAfAAgKASVsGQBSAwAhAAIKbB0THABXAAAAAA==.Kenner:BAAANQAECgIIAgAAAA==.',
Kh='Kheyra:BAABNQAECn8mAAIDAAcK8SGJAgApAgADAAcK8SGJAgApAgAAAA==.',
Ki='Kirsha:BAAANQAECgcICwAAAA==.Kittybeef:BAAANQABCgIIAgAAAA==.Kiwiiga:BAAANQAECgIIAwAAAA==.',
Kn='Knoxxic:BAAANQADCgMIBAAAAA==.',
Ko='Kohnor:BAAANQADCgYIGwAAAA==.Koopalizard:BAABNQAECn8gAAIcAAgKwCJaAQCXAgAcAAgKwCJaAQCXAgAAAA==.Kopi:BAABNQAECn8aAAIIAAcK9h6hBABMAQAIAAcK9h6hBABMAQAAAA==.Korlatt:BAABNQAECn8jAAMlAAgK4R4aBwDYAQAlAAgKqR0aBwDYAQAIAAQKTCAgGAAuAQAAAA==.Kowalabear:BAAANQAECgEIAQAAAA==.',
Ku='Kuaha:BAAANQADCgYIBgABNQADCgQIBAAHAAAAAA==.Kupa:BAAANQADCgYJBwAAAA==.Kurom:BAAANQADCgcJDQAAAA==.Kurston:BAABNQAECn8uAAIGAAkKxyJdAQAkAwAGAAkKxyJdAQAkAwAAAA==.',
Ky='Ky:BAAANQADCgEIAQAAAA==.',
['Kã']='Kãtniss:BAAANQADCgUIFQAAAA==.',
La='Lacia:BAAANQAECgQIBQABNQAECgcIEQAHAAAAAA==.Laih:BAABNQAECn8YAAIXAAgKiQfqTwB/AQAXAAgKiQfqTwB/AQAAAA==.Landsong:BAAANQADCgQIBAAAAA==.',
Le='Leyote:BAABNQAECn8nAAIEAAcK1RKuHAB6AQAEAAcK1RKuHAB6AQAAAA==.',
Li='Liady:BAAANQADCgEJAQAAAA==.Lightshop:BAAANQADCgYICQAAAA==.Liirah:BAAANQADCgUIBwAAAA==.Lilyfox:BAAANQAECgYIEQAAAA==.Lindithrial:BAAANQABCggICAAAAA==.Livingdead:BAAANQADCggIKwAAAA==.',
Lo='Lorianne:BAAANQAECgUIBAAAAA==.Lorraine:BAAANQADCggIDAAAAA==.Lowdangle:BAAANQADCgcIBwAAAA==.',
Lu='Lulz:BAAANQAECggICQAAAA==.Luucifur:BAAANQABCgMIAwAAAA==.',
Ma='Mackpumpkin:BAAANQAECgIIAgAAAA==.Macktheknife:BAAANQADCgQICAABNQAECgkJJwAiAAIgAA==.Madalyn:BAAANQADCgEIAQAAAA==.Maexna:BAAANQAECgEIAQAAAA==.Magdelyne:BAABNQAECn8XAAIOAAoK9gbb6gBGAQAOAAoK9gbb6gBGAQAAAA==.Magglés:BAAANQAECgEIAQAAAA==.Makklehaney:BAABNQAECn8WAAIBAAgKZwstfACvAQABAAgKZwstfACvAQAAAA==.Mallaah:BAAANQADCgUIBQAAAA==.Marovingian:BAABNQAECn8jAAILAAgK4iOZBACeAgALAAgK4iOZBACeAgAAAA==.Matthad:BAABNQAECn8jAAIEAAgKMhp2LQAsAQAEAAgKMhp2LQAsAQAAAA==.Mazìkene:BAAANQAECgMIBAABNQAECgkJKgAIAGQaAA==.',
Mc='Mcnastie:BAAANQAECgQIBgAAAA==.Mcsluts:BAAANQADCgYJCwAAAA==.',
Me='Melmirict:BAAANQADCgMJAwAAAA==.Merciala:BAABNQAECn8rAAMMAAkKIAv0TwCeAQAMAAkKIAv0TwCeAQAGAAcKhwIyWgCfAAAAAA==.',
Mi='Milyyanna:BAAANQADCgYIGgAAAA==.Mirilla:BAABNQAECn8fAAMRAAoK9QqUGQApAQAKAAoKbgo8wAAEAgARAAcKPAWUGQApAQAAAA==.',
Mo='Moddoxx:BAABNQAECn8iAAMZAAcKSBRkRgD+AAAZAAcKSBRkRgD+AAAaAAEKHA1FeAA1AAAAAA==.Moffa:BAAANQADCgMIAwAAAA==.Mohawk:BAABNQAECn8aAAIGAAkKEBdqGQBwAgAGAAkKEBdqGQBwAgAAAA==.Molen:BAAANQAECgEIAQAAAA==.Mommyjuice:BAAANQAECggIDgABNQAFFAcIFQAJANcgAA==.Monkeeh:BAAANQADCggIDQAAAA==.Monkle:BAABNQAECn8oAAIkAAgK/yAsEgDMAgAkAAgK/yAsEgDMAgAAAA==.Monohan:BAAANQADCgUIBQABNQAECggIIwAVAAocAA==.Moonpaw:BAAANQAECgIIAgAAAA==.Moonsii:BAABNQAECn8jAAIGAAgKKg88NAB4AQAGAAgKKg88NAB4AQAAAA==.Mooroth:BAABNQAECn8pAAIhAAgKbhZEBgBYAQAhAAgKbhZEBgBYAQAAAA==.Morkilro:BAAANQAECgEIAQAAAA==.Morozko:BAAANQADCgQIBAAAAA==.',
Ms='Msasani:BAAANQADCgEIAQABNQAECgcIJgADAPEhAA==.Msmana:BAAANQAECgIIAgAAAA==.',
Mu='Muddler:BAAANQAECgYIDAAAAA==.Muire:BAAANQAECgUIBAABNQAECgoKMAAZAHYZAA==.Murinn:BAABNQAECn8mAAIJAAgKkgy3JQCCAQAJAAgKkgy3JQCCAQAAAA==.',
['Mà']='Màggles:BAAANQAECgYIEQAAAA==.',
Na='Nadd:BAAANQAECgYIDQAAAA==.Naledi:BAAANQADCggIDQAAAA==.Naralyn:BAABNQAECn8oAAMgAAoK+xgWDwB5AgAgAAoK+xgWDwB5AgABAAUKYRG6tgAlAQAAAA==.',
Ne='Negrido:BAABNQAECn8oAAQZAAgKTyHvPwCSAgAZAAcKkSHvPwCSAgAaAAMKiBubNQDsAAAiAAIK7hUbHACfAAAAAA==.Nei:BAABNQAECn8kAAIOAAYK+BXeTwAlAQAOAAYK+BXeTwAlAQAAAA==.Neon:BAAANQADCgUICQAAAA==.',
Ni='Nikem:BAABNQAECn8cAAIMAAkKTQ/qDgBkAQAMAAkKTQ/qDgBkAQAAAA==.',
No='Noelle:BAAANQAECgcIEQAAAA==.Norelei:BAAANQADCgcIDwABNQAECgcIJgADAPEhAA==.Noriyuki:BAAANQAECgUIDgAAAA==.',
Ny='Nyxahlia:BAAANQADCgUIBgAAAA==.',
Og='Oghom:BAAANQADCggICAAAAA==.Ogrekin:BAAANQAECgYICgAAAA==.',
Ol='Olderon:BAABNQAECn8WAAILAAkK3RK5WwAFAgALAAkK3RK5WwAFAgAAAA==.Olrong:BAABNQAECn8nAAIlAAcK0AqvJgDVAAAlAAcK0AqvJgDVAAAAAA==.Oluja:BAAANQAECgUIEgAAAA==.',
On='Onuris:BAAANQAECgMIBgAAAA==.',
Oo='Oogiboogi:BAAANQAECgMIAwAAAA==.',
Op='Opacuslupus:BAAANQAECgQICQAAAA==.Oppressin:BAABNQAECn8jAAIkAAgKXBfMCgBmAQAkAAgKXBfMCgBmAQAAAA==.',
Os='Oshunn:BAABNQAECn8pAAIKAAoK/RD+qQAuAgAKAAoK/RD+qQAuAgAAAA==.Osroes:BAAANQAECgQIEgAAAA==.',
Ov='Overdoom:BAABNQAECn8pAAMCAAkKVhsmLwB0AgACAAkKVhsmLwB0AgATAAUKrBORYAAjAQAAAA==.',
Pa='Pacolock:BAAANQADCggICAABNQAECggIFgALANcTAA==.Paladinjohn:BAACNQAFFH8WAAIOAAYKGyMsAgBdAQAOAAYKGyMsAgBdAQA1AAQKfyoAAg4ACgqxJZwUAHMDAA4ACgqxJZwUAHMDAAAA.Palykat:BAAANQAECgYIDgAAAA==.Pandadeez:BAAANQADCgYICAAAAA==.Papiroflz:BAABNQAECn8wAAMBAAoKnSHXDQB6AwABAAoKnSHXDQB6AwAEAAUKexz3fwCMAQAAAA==.',
Pe='Pennywisé:BAABNQAECn8kAAITAAkKrB4hGQDCAgATAAkKrB4hGQDCAgAAAA==.',
Pl='Plaguegying:BAABNQAECn8iAAIVAAgKtRMEEQBZAQAVAAgKtRMEEQBZAQABNQAECgIIAgAHAAAAAA==.Ploofee:BAAANQAECgMIBQAAAA==.',
Pr='Preparedr:BAACNQAFFH8zAAMXAAkKdiYBAAAMBAAXAAkKYCYBAAAMBAAFAAcKwSZ/AAC0AgA1AAQKfx0AAwUACQrrJc8JANgCAAUACAo/Js8JANgCABcABgrvJSElAGECAAAA.Progresz:BAAANQAECgIIAgAAAA==.',
Pu='Purebread:BAAANQADCgUIBQAAAA==.',
Py='Pykel:BAABNQAECn8qAAIMAAoKuAcuJADWAAAMAAoKuAcuJADWAAAAAA==.',
Qa='Qaren:BAAANQADCgYIEAAAAA==.',
Ra='Raishun:BAAANQAECgEJAQAAAA==.Raizo:BAAANQAECgEIAQAAAA==.Rake:BAABNQAECn80AAIjAAoK3BzmAABqAgAjAAoK3BzmAABqAgAAAA==.Rannï:BAAANQADCgQIBAABNQAECgkJJwAiAAIgAA==.Raskreia:BAAANQAECgYIDgABNQAFFAIIBQARANUfAA==.Rassina:BAAANQADCgEIAQAAAA==.Rawk:BAAANQAECgEIAQAAAA==.',
Re='Redeemly:BAAANQAECggIDAAAAA==.Redeyejedi:BAAANQAECggIBwAAAA==.Reeven:BAAANQAECggIIQAAAQ==.Revokely:BAAANQAECgYIDgABNQAECggIDAAHAAAAAA==.',
Rh='Rhcpmage:BAAANQADCggICgABNQAFFAYIFwAKANMlAA==.Rhetegast:BAABNQAECn8tAAImAAoKBxmTEACVAgAmAAoKBxmTEACVAgAAAA==.',
Ri='Rieloesh:BAAANQAECgMIBAAAAA==.Rike:BAABNQAECn8mAAMmAAcKsB7yHgDvAQAOAAcKmhsSiwAQAgAmAAYKVB7yHgDvAQAAAA==.Ristretto:BAAANQADCgYICwABNQAECgcIGgAIAPYeAA==.',
Ro='Roland:BAAANQADCgUJBwAAAA==.Rolandin:BAABNQAECn8hAAILAAcKlRJ2dgC0AQALAAcKlRJ2dgC0AQAAAA==.',
Ru='Rukraga:BAAANQAECgQJBAAAAA==.',
Ry='Rylagosa:BAABNQAECn8iAAMcAAgKsBr/AwC5AQAcAAgKsBr/AwC5AQAnAAIKGwueFQA1AAAAAA==.Ryzesmidge:BAAANQAECgcJDAAAAA==.',
['Rê']='Rêdrum:BAAANQAECgYIBgABNQAECgkJKgAIAGQaAA==.',
Sa='Salandria:BAABNQAECn8mAAQLAAgKtyMXXgD+AQALAAUKSSQXXgD+AQAmAAgKDxyRBwCEAQAOAAEKAABWnwE3AAAAAA==.Sarionian:BAABNQAECn8UAAIGAAUKywzsHgDTAAAGAAUKywzsHgDTAAAAAA==.Sarjin:BAAANQAECgEIAQABNQAECgcIJgADAPEhAA==.Sarvinblue:BAABNQAECn86AAMEAAoK0R94EABBAwAEAAoK0R94EABBAwABAAgKohPUaQDjAQAAAA==.',
Sc='Scopolamine:BAAANQAECgQICgAAAA==.',
Se='Sevrin:BAABNQAECn8oAAIVAAgKuw+PSgDNAQAVAAgKuw+PSgDNAQAAAA==.Seymonty:BAABNQAECn8hAAMWAAgKgg8zDgBMAQASAAgK7AiwhQCGAQAWAAcKPw4zDgBMAQAAAA==.',
Sh='Shaeko:BAAANQADCggIGQAAAA==.Shazlulu:BAAANQAECgYIDQAAAA==.Shaznoir:BAABNQAECn8lAAIaAAgKtgedAwAHAQAaAAgKtgedAwAHAQAAAA==.Shilajit:BAAANQAECgMICAAAAA==.Shokz:BAAANQADCgMIAwABNQAECgMIBQAHAAAAAA==.',
Sk='Skip:BAAANQADCgcIBwAAAA==.Skøøma:BAAANQABCgIIBAAAAA==.',
Sl='Sloe:BAAANQAECgEIAQABNQAECgcIGwALACARAA==.',
Sm='Smokalot:BAAANQAECgIIAQAAAA==.Smokehunter:BAAANQADCgYIBgAAAA==.',
Sn='Snoop:BAAANQADCgYICgAAAA==.',
So='Solstîce:BAAANQADCgQIBAABNQAECgkJKgAIAGQaAA==.Sonsu:BAAANQADCggICAABNQAECgUIFAAGAMsMAA==.',
Sp='Speedbeefbal:BAAANQADCggIFAAAAA==.Speeddwrfbal:BAAANQADCgYIGQAAAA==.Speedmeatbal:BAAANQAECggIEgAAAA==.Speedmeatlok:BAAANQADCggIFAAAAA==.Speedmonkbal:BAAANQAECgMIBAAAAA==.Speedoe:BAAANQADCggIEgAAAA==.Spidêrs:BAAANQABCgQICAAAAA==.Sporkulous:BAABNQAECn8cAAIJAAcKqgj5uQCQAQAJAAcKqgj5uQCQAQAAAA==.',
Sq='Squal:BAAANQAECgcIEAAAAA==.Squiggle:BAABNQAECn8eAAImAAgKoBmoBQCmAQAmAAgKoBmoBQCmAQAAAA==.',
St='Steevii:BAAANQADCgMJAwAAAA==.Stewie:BAAANQAECgUIBQAAAA==.Striker:BAAANQADCgYIDwABNQAECgcIJgAmALAeAA==.Strikers:BAAANQAECgEIAQAAAA==.',
Su='Sunshíne:BAABNQAECn8VAAMmAAYK/BL8MgBKAQAmAAYK/BL8MgBKAQAOAAEKwgNK1AEbAAAAAA==.',
Sy='Syver:BAABNQAECn8fAAICAAgK+xhtCwCJAQACAAgK+xhtCwCJAQAAAA==.',
['Sí']='Sírlancealot:BAAANQADCgMIBAAAAA==.',
Ta='Takeke:BAABNQAECn8cAAMVAAoKVBDyFQA3AQAVAAkKVBDyFQA3AQACAAUKUgv/iAD+AAAAAA==.Takeroux:BAAANQAECgEIAQAAAA==.Talandroz:BAABNQAECn8kAAMcAAgKBx1mAgAaAgAcAAgKBx1mAgAaAgAnAAIKTAtvNQBiAAAAAA==.Tanagra:BAAANQADCgIIAgABNQAECgcIIgAZAEgUAA==.Tankz:BAAANQADCgYICAAAAA==.Tanner:BAACNQAFFH8KAAIJAAUK9At7GwDdAAAJAAUK9At7GwDdAAA1AAQKfzUAAgkACgo2GgBDAKICAAkACgo2GgBDAKICAAAA.',
Te='Tebo:BAAANQAECgEIAgAAAA==.Teboe:BAAANQADCgcICQABNQAECgEIAgAHAAAAAA==.Tedman:BAABNQAECn8eAAMEAAgKgBXUtgD/AAAEAAUKgg3UtgD/AAABAAgK4g0wOwDYAAAAAA==.Temel:BAABNQAECn8nAAMEAAgKpBIiHgByAQAEAAgKpBIiHgByAQABAAQKXAdI7QC8AAAAAA==.Teostra:BAABNQAECn8gAAMJAAkK5R7sPgCtAgAJAAkK5R7sPgCtAgAdAAEKyAqqNgBAAAAAAA==.Terradan:BAAANQAECgEIAQAAAA==.Testoecles:BAAANQADCgcICwABNQAECgEIAgAHAAAAAA==.',
Th='Thadrack:BAAANQAECgcIEAABNQAECgcIEQAHAAAAAA==.Thalonstin:BAAANQADCgYIHAAAAA==.Thaneold:BAAANQAECgQJCQABNQAECgoKLAASAHojAA==.Thassarian:BAAANQAECgUICwABNQAECgYIEQAHAAAAAA==.Theodrid:BAACNQAFFH8TAAImAAcKpBpPAgAVAgAmAAcKpBpPAgAVAgA1AAQKfy0AAiYACgpEIkMIABoDACYACgpEIkMIABoDAAAA.Thunderstomp:BAAANQADCgIIAgAAAA==.',
Ti='Tinkerspell:BAAANQADCgYICwAAAA==.Tinkíe:BAABNQAECn8mAAIQAAgKxx89CwDRAgAQAAgKxx89CwDRAgAAAA==.Tirzahdozier:BAAANQAECgEIAgABNQAECgcICwAHAAAAAA==.Tiwohnne:BAAANQAECgYICAAAAA==.',
Tl='Tla:BAAANQADCgYIGAAAAA==.',
Tp='Tpaartos:BAAANQADCgIJAgABNQAECggIIwAEADIaAA==.',
Tr='Treat:BAABNQAECn8pAAIUAAkKPiK8AQBdAgAUAAkKPiK8AQBdAgAAAA==.Trippysheep:BAAANQAECgIIAgABNQAFFAkJFgAZAHwcAA==.Trippyshock:BAAANQADCgEIAQABNQAFFAkJFgAZAHwcAA==.Tristitia:BAAANQABCgYICgAAAA==.',
Tu='Turkeltin:BAACNQAFFH8JAAIeAAQKORaQBADMAAAeAAQKORaQBADMAAA1AAQKfyQAAh4ACgpPIjsDAKYDAB4ACgpPIjsDAKYDAAAA.',
Tw='Twiggle:BAAANQADCgYIBgABNQAECgcICwAHAAAAAA==.Twistedsquid:BAAANQABCgQIBAAAAA==.',
Ty='Tyamat:BAABNQAECn8cAAMiAAcKxhf7CQDcAQAiAAcKxhf7CQDcAQAZAAIKGwVUMwFUAAAAAA==.Tyche:BAAANQADCgYIDAAAAA==.Tyrinara:BAAANQADCggICAAAAA==.',
Ui='Uiewedaoez:BAABNQAECn8oAAIGAAkKFSWTAgChAgAGAAkKFSWTAgChAgAAAA==.',
Va='Vains:BAABNQAECn8sAAIOAAoKcByiTACvAgAOAAoKcByiTACvAgAAAA==.Valrith:BAAANQADCgcIGAAAAA==.',
Ve='Velexi:BAAANQABCggIEgAAAA==.Velody:BAAANQADCgQIAQAAAA==.Vendettuh:BAAANQADCgYIBgAAAA==.Veronica:BAABNQAECn8fAAIKAAcKIw+xZgDvAAAKAAcKIw+xZgDvAAAAAA==.Verren:BAABNQAECn8jAAIDAAgK3hGSDwAUAQADAAgK3hGSDwAUAQAAAA==.Vesfor:BAAANQADCgEIAQABNQAECgQIDAAHAAAAAA==.Vestus:BAAANQABCgcIDAAAAA==.',
Vy='Vyrridyl:BAAANQAECgMICAAAAA==.',
Wa='Waddlez:BAAANQAECgcIBgAAAA==.Watermark:BAABNQAECn8dAAIEAAgK5gtGmwBCAQAEAAgK5gtGmwBCAQAAAA==.',
We='Weeblewobble:BAAANQAECgEIAgAAAA==.Weltamus:BAAANQADCgYIEAAAAA==.Weltazar:BAABNQAECn8aAAIBAAcKzRSicADPAQABAAcKzRSicADPAQAAAA==.Weltzilla:BAABNQAECn8hAAIJAAgKKhzPDQADAgAJAAgKKhzPDQADAgAAAA==.Westside:BAAANQAECgYIDgAAAA==.',
Wh='Whoosh:BAABNQAECn8pAAIVAAgKlyLGBAAJAgAVAAgKlyLGBAAJAgAAAA==.',
Wi='Wickët:BAABNQAECn8mAAMEAAgK6iMwFgAfAwAEAAgK6iMwFgAfAwABAAYKpR+EWQAWAgAAAA==.Wildtiger:BAABNQAECn8mAAIjAAkKLhClBgBHAQAjAAkKLhClBgBHAQAAAA==.',
Wo='Wolfslied:BAAANQADCgQIBAABNQADCgQIBAAHAAAAAA==.',
Wu='Wulfenhide:BAABNQAECn8bAAIXAAgKGh8nIACAAgAXAAgKGh8nIACAAgAAAA==.Wuntvor:BAAANQADCggICAAAAA==.',
Wy='Wyzsky:BAAANQAECgEIAQABNQAECggIJwAEAKQSAA==.',
Xa='Xalreth:BAABNQAECn8fAAIeAAgKPgivGADnAAAeAAgKPgivGADnAAAAAA==.Xaviana:BAAANQAECgUIBQAAAQ==.',
Ya='Yastypoo:BAABNQAECn8iAAILAAoKfhD1VAAbAgALAAoKfhD1VAAbAgAAAA==.',
Za='Zarieda:BAAANQAECgcIDQAAAA==.Zayrelia:BAACNQAFFH8SAAIGAAUKPha0AwA7AQAGAAUKPha0AwA7AQA1AAQKfzsAAwYACgohHpYNAPYCAAYACgohHpYNAPYCAAwABgphFZtQAJsBAAAA.',
Ze='Zelenor:BAAANQAECgEIAgABNQAECgcIHAAiAMYXAA==.',
Zu='Zud:BAABNQAECn8bAAICAAgK2hzIOwAyAgACAAgK2hzIOwAyAgAAAA==.',
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
