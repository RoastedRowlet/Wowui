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

local lookup = {'Shaman-Elemental','DeathKnight-Unholy','Warlock-Destruction','Shaman-Restoration','DeathKnight-Frost','Rogue-Subtlety','Druid-Restoration','Priest-Holy','DemonHunter-Vengeance','Hunter-BeastMastery','Mage-Arcane','Paladin-Holy','Priest-Shadow','Druid-Balance','Hunter-Survival','DemonHunter-Havoc','Paladin-Retribution','Unknown-Unknown','Monk-Brewmaster','Monk-Windwalker','Monk-Mistweaver','Priest-Discipline','Mage-Frost','DeathKnight-Blood','Shaman-Enhancement','Rogue-Assassination','Rogue-Outlaw','Warlock-Demonology','Druid-Guardian','Evoker-Augmentation','Evoker-Preservation','Hunter-Marksmanship','DemonHunter-Devourer','Warrior-Arms','Warrior-Protection','Warlock-Affliction','Druid-Feral','Paladin-Protection','Evoker-Devastation',}
local provider = {region='US',realm='KulTiras',name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aarix:BAABNQAECn8fAAIBAAcKvQwXkgB3AQABAAcKvQwXkgB3AQAAAA==.',
Ae='Aendillan:BAAANQADCgUIBQAAAA==.',
Af='Affonasei:BAABNQAECn8uAAICAAcKXgiSNwDfAAACAAcKXgiSNwDfAAAAAA==.',
Ag='Agkistrodon:BAAANQADCgcIDQABNQAECgoKRgADAHIcAA==.',
Ai='Aicaramba:BAABNQAECn8rAAIEAAoKwyCbFgAcAwAEAAoKwyCbFgAcAwAAAA==.Aileen:BAAANQAECgUIEwAAAA==.',
Aj='Ajay:BAAANQAECgYIBgAAAA==.',
Ak='Akashi:BAABNQAECn8WAAIFAAgKDhPFQgC5AQAFAAgKDhPFQgC5AQABNQAFFAUIEAAGABQQAA==.',
Al='Alacrodie:BAAANQADCgYIHAAAAA==.',
Am='Amoonsi:BAAANQADCgMIAwABNQAECgkJKAAHAJcPAA==.Amordeyain:BAAANQAECggIDwAAAA==.',
An='Angrydisc:BAABNQAECn8aAAIIAAoKhgfOSwCCAQAIAAoKhgfOSwCCAQAAAA==.Angrytotems:BAAANQAECgUIBwABNQAECgoKGgAIAIYHAA==.Angyll:BAAANQABCggIGQAAAA==.Annaborshen:BAAANQABCgIIAgAAAA==.Antoccino:BAAANQAECgYIDQABNQAECggIIgAJACodAA==.',
Ar='Aragorno:BAABNQAECn8eAAIKAAkK4hOZdQAkAgAKAAkK4hOZdQAkAgAAAA==.Arcturen:BAABNQAECn8VAAIKAAYKxxmDhgAlAQAKAAYKxxmDhgAlAQAAAA==.Ardala:BAAANQAECggIDQAAAA==.Arenthal:BAAANQAECgYIDAABNQAECgoKQgALAJsfAA==.Armonni:BAAANQABCgIIAgAAAA==.Arturaan:BAAANQAECgEIAQAAAA==.',
As='Ashalana:BAAANQADCgUIBQAAAA==.Asheby:BAAANQADCgMIAwABNQAECggIIwAMAH8UAA==.Ashenisson:BAAANQADCgQIBAABNQAECgYIFQAEAMUVAA==.Ashiera:BAABNQAECn8lAAILAAgKwAKVMwE2AQALAAgKwAKVMwE2AQAAAA==.Ashrai:BAAANQADCgEIAQABNQAECgoKRgADAHIcAA==.Astralmorph:BAAANQADCgYIBgAAAA==.',
At='Atomic:BAAANQAECgUICwAAAA==.',
Au='Augenblick:BAAANQADCgIIAgAAAA==.Aurorée:BAAANQAECgYIDwAAAA==.',
Av='Avattar:BAAANQAECgEIAQAAAA==.',
Az='Azylstrid:BAAANQADCgYIDAAAAA==.',
Ba='Baeu:BAAANQABCgUIBwAAAA==.Balentine:BAABNQAECn8ZAAMIAAgK/AfDgwDQAAAIAAgK/AfDgwDQAAANAAIKLwGweQA0AAAAAA==.Banostraza:BAAANQAECgQICAAAAA==.Baspir:BAABNQAECn8yAAIOAAoKihZBFQD9AQAOAAoKihZBFQD9AQAAAA==.Bavette:BAAANQAECgcICAABNQAECgoKMgAIAKgeAA==.',
Be='Beeboop:BAAANQAECgUIBgAAAA==.Belly:BAABNQAECn8rAAIPAAkKZh/3AwC5AgAPAAkKZh/3AwC5AgAAAA==.Belrae:BAABNQAECn8bAAIQAAkKtw39HQCoAQAQAAkKtw39HQCoAQAAAA==.Benchfresh:BAABNQAECn8nAAIRAAgKch5ALgBDAgARAAgKch5ALgBDAgAAAA==.Bendah:BAAANQAECgEIAgAAAA==.Bender:BAAANQADCgYIBgAAAA==.Bezieck:BAAANQAECgMIBgAAAA==.',
Bi='Bigfolks:BAAANQADCgUIBwAAAA==.Bigollock:BAAANQAECgEIAQAAAA==.Bili:BAAANQAECgEIAQAAAA==.',
Bl='Bloodarrow:BAAANQADCgUIBwAAAA==.Bloodbound:BAAANQADCgYIBgAAAA==.',
Bo='Bockchi:BAAANQAECgQICAAAAA==.Bonanas:BAAANQABCggICAAAAA==.Bonegavel:BAAANQABCgQIBgABNQABCgYIDAASAAAAAA==.Bookhuntress:BAAANQAECgYIBgAAAA==.',
Br='Branex:BAAANQAECggICAAAAA==.Branpaw:BAAANQADCgQIAwAAAA==.Brewdeez:BAABNQAECn8sAAMTAAoKXBYtDABCAgATAAkKphgtDABCAgAUAAEKWQZqTAApAAAAAA==.Brewzen:BAAANQADCgYIBgAAAA==.Brewzer:BAABNQAECn80AAIVAAoKkRAWCwDyAQAVAAoKkRAWCwDyAQAAAA==.Brick:BAAANQAECgEIAQABNQAECggIHAAWACcSAA==.Brint:BAAANQADCgcIDAAAAA==.Bronad:BAACNQAFFH8dAAMLAAYK0yXpCQBUAQALAAUKqSbpCQBUAQAXAAIKRyN1AgDNAAA1AAQKf1cAAwsACgriJp8BAPMDAAsACgriJp8BAPMDABcAAgrzHzQkAFkAAAAA.Broomhandle:BAABNQAECn8qAAIRAAgKpiBfQQDQAgARAAgKpiBfQQDQAgAAAA==.',
Bu='Bumbushka:BAAANQAECgcIDwAAAA==.Burinn:BAABNQAECn8VAAIKAAYK0hH/nQDzAAAKAAYK0hH/nQDzAAABNQAECgkJNgAIABYaAA==.Butche:BAAANQAECgEIBgAAAA==.',
Ca='Caeus:BAABNQAECn8mAAQFAAkKFR0YKwBDAgAFAAgKsBsYKwBDAgACAAYKUhrURwD4AQAYAAQKsxoDQQDdAAAAAA==.Cajuil:BAAANQAECgEIAQAAAA==.Cam:BAABNQAECn8VAAMLAAcKLiE5pgA1AgALAAcKLiE5pgA1AgAXAAMKrhRRKgCmAAAAAA==.Carolinabele:BAAANQADCggICAAAAA==.Cauud:BAAANQADCgYIEAAAAA==.',
Cb='Cbd:BAAANQADCgcIEwAAAA==.',
Ce='Celerious:BAAANQAECgYIDQAAAA==.',
Ch='Chacruna:BAAANQAECgMICQAAAA==.Chelan:BAABNQAECn82AAMIAAkKFhqHGQCUAgAIAAkKFhqHGQCUAgANAAEKAAAUkQAZAAAAAA==.Chloelock:BAAANQABCgEJAQAAAA==.Chronicler:BAAANQADCgEIAQAAAA==.Chuntspeed:BAAANQAECgYIBgAAAA==.Chuye:BAAANQAECgIIAwABNQAECgoKMgAIAKgeAA==.',
Cl='Clambulance:BAABNQAECn80AAIKAAoK3xrUQwCfAgAKAAoK3xrUQwCfAgAAAA==.',
Cn='Cnova:BAABNQAECn8VAAMEAAcKLxaQmABKAQAEAAcKLxaQmABKAQAZAAIKUgTDKgAyAAABNQAECggIEwASAAAAAA==.',
Co='Codythedead:BAACNQAFFH8ZAAMCAAYKoB2SAQBqAQACAAYKoB2SAQBqAQAYAAEKAAAkQQAOAAA1AAQKf0QAAgIACgrLJLcFAJ4DAAIACgrLJLcFAJ4DAAAA.Coraf:BAACNQAFFH8dAAIEAAYKRh5JAwACAgAEAAYKRh5JAwACAgA1AAQKfzAAAgQACgpXJMoNAFMDAAQACgpXJMoNAFMDAAAA.Coyotl:BAABNQAECn8bAAIPAAgKow5IBQB7AQAPAAgKow5IBQB7AQAAAA==.',
Cr='Crazyazshamy:BAAANQAECgcICwAAAA==.',
Cu='Cuvier:BAAANQADCggJFgAAAA==.',
Da='Daltenton:BAAANQAECgYICAABNQAECgoKJQAWADcOAA==.Danak:BAAANQADCgYIFwAAAA==.Dascrazy:BAAANQADCgUIBgAAAA==.',
De='Deadlyfrosty:BAAANQADCgYIDgAAAA==.Deathmob:BAABNQAECn8qAAIYAAgKPx2jKgBxAgAYAAgKPx2jKgBxAgAAAA==.Deathsynth:BAAANQADCgQJBAABNQAECggIJgALABAbAA==.Debixie:BAACNQAFFH8FAAIaAAIKNhuJFAClAAAaAAIKNhuJFAClAAA1AAQKfykABBoACQrxIEwKADoDABoACQo2H0wKADoDABsABgoEE+QNAGIBAAYABAq+GztaAPIAAAAA.Decisive:BAAANQADCgYIBgABNQAFFAkJGwAcALkeAA==.Dejection:BAAANQABCgYIBwAAAA==.Demisi:BAAANQAECgYICwAAAA==.Demiurge:BAABNQAECn8pAAIOAAoKKxsEHwDSAgAOAAoKKxsEHwDSAgAAAA==.Despayr:BAAANQADCgYIBgAAAA==.',
Di='Diasundra:BAABNQAECn83AAIKAAoK0iACEQDHAgAKAAoK0iACEQDHAgAAAA==.Dibbons:BAAANQAECgYICgAAAA==.Divinatjin:BAAANQADCgYICQAAAA==.',
Do='Dollars:BAAANQAECggIDQAAAA==.Dottingyou:BAACNQAFFH8dAAMDAAYKJxICBQCMAAAcAAUKqQwZEQDGAAADAAIK9hICBQCMAAA1AAQKfzIAAxwACgrLIp8WAHgCABwACQpXI58WAHgCAAMABgrZGC4YAKsBAAAA.Doubleedged:BAAANQAECgEIAQAAAA==.',
Dr='Dracthyrbm:BAAANQAECgYICQAAAA==.Dragonshide:BAAANQADCgQIBAABNQAECgoKKQADAOMfAA==.Dreepy:BAAANQAECgYIBgAAAA==.Drransom:BAAANQADCgYIEwAAAA==.Dryan:BAABNQAECn8kAAIdAAgKLBV/FgBeAQAdAAgKLBV/FgBeAQAAAA==.',
Du='Duo:BAABNQAECn81AAIKAAoKlRd+KwAyAgAKAAoKlRd+KwAyAgAAAA==.Duragon:BAABNQAECn8mAAMeAAkKYwlEDQB7AQAeAAkKYwlEDQB7AQAfAAEKtQAAVgAZAAAAAA==.',
Ei='Eipwoc:BAAANQADCggIBwAAAA==.Eistir:BAAANQAECgUICQABNQAECgoKOAAcAMEaAA==.',
El='Eloreith:BAABNQAECn8uAAMOAAoKQRmJKQCLAgAOAAoKQRmJKQCLAgAdAAUKvAjzPwC7AAAAAA==.',
Em='Emamagee:BAAANQADCgQIBgAAAA==.Emilia:BAABNQAECn8zAAIIAAgKqRkqRgBUAgAIAAgKqRkqRgBUAgAAAA==.',
En='Endressa:BAABNQAECn83AAMWAAoK3BidAQBrAgAWAAoK3BidAQBrAgANAAQKZhGbQgAeAQAAAA==.',
Er='Eralendryn:BAAANQADCgEIAQAAAA==.Erelios:BAABNQAECn8mAAMMAAkKfgjRWQA1AQAMAAkKfgjRWQA1AQARAAEKAAAHsgEvAAAAAA==.',
Es='Eski:BAABNQAECn9JAAMbAAoKXSJOAAAWAwAbAAoKXSJOAAAWAwAaAAIK2wn3lABgAAAAAA==.Essaena:BAABNQAECn8iAAIYAAgKNSFkIQCpAgAYAAgKNSFkIQCpAgAAAA==.',
Eu='Eura:BAAANQADCgEIAQAAAA==.Eureka:BAEANQAECgcIEwAAAA==.',
Ev='Everlight:BAAANQADCggIEAABNQAECgoKRgADAHIcAA==.',
Ez='Ezrì:BAAANQADCgUIBQAAAA==.',
Fa='Faddeyshnek:BAABNQAECn8rAAIKAAkKvg+5TQC0AQAKAAkKvg+5TQC0AQAAAA==.Farmeador:BAAANQAECgEIAQAAAA==.Fastbeefball:BAAANQADCggIEAAAAA==.Fatgirljuice:BAACNQAFFH8VAAMKAAcK1yCgAAC5AgAKAAcK1yCgAAC5AgAgAAIKrg+tHACMAAA1AAQKfxcAAwoACQpDJpIBAHoDAAoACQpDJpIBAHoDACAAAQr0Gn1+AEoAAAAA.',
Fe='Felysambre:BAABNQAECn8iAAIhAAcKKAxuKgDUAAAhAAcKKAxuKgDUAAAAAA==.',
Fi='Fish:BAACNQAFFH8dAAINAAgKZiT2AADZAgANAAgKZiT2AADZAgA1AAQKfzUAAg0ACgrWJj4AAJADAA0ACgrWJj4AAJADAAAA.',
Fl='Flight:BAACNQAFFH8QAAMGAAUKFBCuDADlAAAGAAQKbAuuDADlAAAaAAEKCx7BCgBWAAA1AAQKfzsAAxoACgoYIdAbAKACABoACQo1IdAbAKACAAYACQpPGTUxAK4BAAAA.Floofee:BAAANQADCgQIBAAAAA==.',
Fo='Footfinger:BAAANQAECgIIAwAAAA==.Forsynth:BAABNQAECn8mAAILAAgKEBs+RgDgAQALAAgKEBs+RgDgAQAAAA==.Foxymeatbal:BAAANQADCggIDQAAAA==.',
Fu='Fubar:BAAANQAECgYIDQAAAA==.',
Ga='Ganniy:BAAANQAECgEIAQAAAA==.',
Ge='Gewitt:BAAANQAECgQICwAAAA==.',
Gl='Glinda:BAAANQADCgUIDwAAAA==.',
Go='Gonjah:BAABNQAECn8cAAQIAAkKCRGwjwBnAQAIAAgKwhGwjwBnAQANAAUKaQ0CRQAPAQAWAAEKbQNvFAAiAAAAAA==.',
Gr='Grabomage:BAAANQAECgYIEAABNQAFFAYIHQALANMlAA==.Grabovoker:BAAANQADCgIIAgABNQAFFAYIHQALANMlAA==.Grazienne:BAAANQADCgUIEgAAAA==.Greavos:BAABNQAECn8pAAINAAgKYhnUEgCcAQANAAgKYhnUEgCcAQAAAA==.Griggus:BAABNQAECn8mAAIiAAoKrBGdUQCOAQAiAAoKrBGdUQCOAQAAAA==.Grimgar:BAABNQAECn8uAAMXAAgKzRaZIgDXAAALAAYKDxWflQAZAQAXAAMKEBmZIgDXAAAAAA==.Grimmshady:BAAANQADCgQIBgAAAA==.Grumpsky:BAAANQADCgEIAQABNQAECggILgAEAO8TAA==.',
Gu='Gumbles:BAABNQAECn8yAAMIAAoKqB6bEgDUAgAIAAoKqB6bEgDUAgANAAIKbQI7cABIAAAAAA==.Gurney:BAABNQAECn8ZAAMMAAoKWxgrMgCcAgAMAAoKWxgrMgCcAgARAAEK9gRm0wEcAAAAAA==.Guzprimal:BAAANQAECgEIAgAAAA==.',
Gw='Gwenory:BAAANQABCgQIBAAAAA==.',
Gy='Gying:BAAANQAECgIIAwAAAA==.',
Ha='Hanekawa:BAABNQAECn8cAAIMAAoK2RudPgBqAgAMAAoK2RudPgBqAgABNQAFFAMIBgAXALoaAA==.Hannie:BAAANQADCgYIGgAAAA==.',
He='Headhúnter:BAAANQAECgYICAAAAA==.Heartsparx:BAABNQAECn8uAAIaAAoK4RSkCQDuAQAaAAoK4RSkCQDuAQAAAA==.Heatseeka:BAABNQAECn8mAAMEAAkK0xL0dwCkAQAEAAgK7xH0dwCkAQAZAAcKYwLzIwAdAQAAAA==.Heitan:BAAANQAECgYIDAABNQAECgoKOAAcAMEaAA==.Hexxiz:BAAANQAECgUICAABNQAECgoKJQAdAK8jAA==.',
Hi='Hiphopinator:BAABNQAECn8sAAIjAAkKSSQNAwDAAgAjAAkKSSQNAwDAAgAAAA==.',
Ho='Ho:BAAANQADCgQIBAAAAA==.Holyshock:BAABNQAECn87AAIMAAoKgBqkLAC0AgAMAAoKgBqkLAC0AgAAAA==.Holyterror:BAAANQADCgUIFwAAAA==.',
Ia='Ianthe:BAAANQAECgYICAAAAA==.',
Ib='Iboga:BAAANQAECgQIEwAAAA==.Ibrahimovic:BAAANQAECgUIBgAAAA==.',
Ig='Ignitecro:BAAANQAECgEIAgAAAA==.Igram:BAABNQAECn8UAAIIAAcKnxZcgwCNAQAIAAcKnxZcgwCNAQAAAA==.',
Il='Illumona:BAABNQAECn8YAAMJAAYKaANUJwB9AAAJAAQK8QNUJwB9AAAQAAYKZQKQVgBtAAAAAA==.Iluz:BAAANQADCgMIAwAAAA==.',
In='Inafume:BAAANQADCggJEwAAAA==.Inoxia:BAAANQAECgUIDwAAAA==.Intrépidice:BAAANQAECgQIDwAAAA==.',
Ix='Ixtabay:BAABNQAECn8nAAQkAAkKAiB7AgD3AgAkAAkKQx17AgD3AgADAAMK3BeIPADPAAAcAAMKvQ1BEgGmAAAAAA==.',
Ja='Jamurra:BAAANQAECgIICQABNQAECgcIEgASAAAAAA==.Jaylinn:BAABNQAECn8sAAIKAAoKnQfmpAC8AQAKAAoKnQfmpAC8AQAAAA==.Jazzmend:BAAANQAECgQJBAAAAA==.',
Je='Jeanne:BAABNQAECn8wAAIKAAkK/hrvJABQAgAKAAkK/hrvJABQAgABNQAECgoKSQAbAF0iAA==.Jellykins:BAABNQAECn8jAAIMAAgKfxSkLAD3AQAMAAgKfxSkLAD3AQAAAA==.',
Ji='Jimjamjuju:BAAANQAECgYIDAAAAA==.Jimsonweed:BAABNQAECn8YAAIGAAgKWQbgXgDhAAAGAAgKWQbgXgDhAAAAAA==.',
Jo='Josie:BAABNQAECn8sAAMWAAoKDxroAADsAgAWAAoKDxroAADsAgANAAEKqwYzTAAqAAAAAA==.Jozbirt:BAABNQAECn8mAAIlAAgKng6tEQDmAQAlAAgKng6tEQDmAQAAAA==.',
Ka='Kaeiria:BAAANQADCgQIBAAAAA==.Kael:BAABNQAECn8hAAMEAAcKPxeFSgBrAQAEAAYKoRSFSgBrAQABAAcK6gppYgDmAAAAAA==.Kalaanri:BAABNQAECn8VAAMEAAYKxRWNvQDvAAAEAAQKXBONvQDvAAABAAYKbxBxYgDmAAAAAA==.Kalyandra:BAABNQAECn8cAAIUAAYKAA4IPAA1AQAUAAYKAA4IPAA1AQAAAA==.Karlach:BAAANQADCgYIBwABNQAECgoKLgAaAOEUAA==.Karumie:BAABNQAECn80AAIEAAoK4howEgC8AgAEAAoK4howEgC8AgAAAA==.Kateera:BAAANQADCgQIBAAAAA==.',
Ke='Keden:BAAANQADCgUICAAAAA==.Kelesa:BAAANQAECgEIAQAAAA==.Keljaden:BAABNQAECn8yAAMiAAoKciNsGQBSAwAiAAoKciJsGQBSAwAjAAIKbB0YKgBSAAAAAA==.Kenner:BAAANQAECgIIAgAAAA==.',
Kh='Kheyra:BAABNQAECn8pAAIdAAgKxSB8CABRAgAdAAgKxSB8CABRAgABNQAECgoKRgADAHIcAA==.Khloesham:BAAANQAECgEIAQAAAA==.',
Ki='Kirsha:BAAANQAECgcIEgAAAA==.Kittybeef:BAAANQABCgIIAgAAAA==.Kiwiiga:BAAANQAECgIIBAAAAA==.',
Kn='Knoxxic:BAAANQADCgMIBAAAAA==.',
Ko='Koggs:BAAANQAECgEIAQABNQAECgkJMgAjANoUAA==.Kohnor:BAAANQADCgYIGwAAAA==.Koopalizard:BAABNQAECn8mAAIfAAgK9SKZCgD6AgAfAAgK9SKZCgD6AgAAAA==.Kopi:BAABNQAECn8iAAIJAAgKKh1NBQDeAQAJAAgKKh1NBQDeAQAAAA==.Korlatt:BAABNQAECn8qAAMQAAgK4R5FHAC3AgAQAAgKqR1FHAC3AgAJAAQKTCAgGAAuAQAAAA==.Kowalabear:BAAANQAECgEIAQAAAA==.',
Ku='Kuaha:BAAANQADCgYIBgABNQADCgQIBAASAAAAAA==.Kupa:BAAANQAECgEIAgAAAA==.Kurom:BAAANQADCgcJDQAAAA==.Kurston:BAABNQAECn81AAIHAAkKxyKLBABCAwAHAAkKxyKLBABCAwAAAA==.',
Ky='Ky:BAAANQADCgEIAQAAAA==.',
['Kã']='Kãtniss:BAAANQADCgUIFQAAAA==.',
La='Labella:BAAANQAECgEIAgAAAA==.Lacia:BAAANQAECgQIBgABNQAECgoKGgAIAIYHAA==.Laih:BAABNQAECn8iAAIaAAoKmgkKDwCTAQAaAAoKmgkKDwCTAQAAAA==.Landsong:BAAANQADCgQIBAAAAA==.',
Le='Leyote:BAABNQAECn8vAAIEAAgK2xLiNADKAQAEAAgK2xLiNADKAQAAAA==.',
Li='Liady:BAAANQADCgEJAQAAAA==.Lightshop:BAAANQADCgYICQAAAA==.Liirah:BAAANQADCgUIBwAAAA==.Lilyfox:BAAANQAECgYIEgABNQAECgYIEwASAAAAAA==.Lindithrial:BAAANQABCggICAAAAA==.Livingdead:BAAANQADCggILwAAAA==.',
Lo='Lorianne:BAAANQAECgQICgAAAA==.Lorraine:BAAANQAECgEIAQAAAA==.Lowdangle:BAAANQADCgcIBwAAAA==.',
Lu='Lulz:BAAANQAECggICQAAAA==.Luucifur:BAAANQABCgMIAwAAAA==.',
Ma='Mackpumpkin:BAAANQAECgIIAgAAAA==.Macktheknife:BAAANQADCgQICAABNQAECgkJJwAkAAIgAA==.Madalyn:BAAANQADCgEIAQAAAA==.Maexna:BAAANQAECgIIAwAAAA==.Magdelyne:BAABNQAECn8YAAIRAAoKMQjb6gBGAQARAAoKMQjb6gBGAQAAAA==.Magglés:BAAANQAECgEIAQAAAA==.Makklehaney:BAABNQAECn8WAAIBAAgKZwstfACvAQABAAgKZwstfACvAQAAAA==.Mallaah:BAAANQADCgUIBQAAAA==.Marovingian:BAABNQAECn8oAAIMAAgK4iMAFgAmAwAMAAgK4iMAFgAmAwAAAA==.Matthad:BAABNQAECn8nAAIEAAkKwRgIXQD4AQAEAAkKwRgIXQD4AQAAAA==.Mazìkene:BAAANQAECgQIBAABNQAECgoKNAAJADsbAA==.',
Mc='Mcnastie:BAAANQAECgQICgAAAA==.Mcsluts:BAAANQADCgYJCwAAAA==.',
Me='Melmirict:BAAANQADCgMJAwAAAA==.Merciala:BAABNQAECn8zAAQdAAkK3gwoKADPAAAOAAkKIAv0TwCeAQAdAAQK7g4oKADPAAAHAAcKMAMyWgCfAAAAAA==.',
Mi='Milyyanna:BAAANQADCgYIGgAAAA==.Mirilla:BAABNQAECn8iAAMXAAoKtw6UGQApAQALAAoKMA48wAAEAgAXAAcKPAWUGQApAQAAAA==.',
Mo='Moddoxx:BAABNQAECn8qAAQkAAgKuBZSBQCLAQAcAAgKJBMthQDZAQAkAAcK4RZSBQCLAQADAAEKHA1FeAA1AAAAAA==.Moffa:BAAANQADCgMIAwAAAA==.Mohawk:BAABNQAECn8cAAIHAAkKEBdqGQBwAgAHAAkKEBdqGQBwAgAAAA==.Molen:BAAANQAECgEIAQAAAA==.Mommyjuice:BAAANQAECggIEAABNQAFFAcIFQAKANcgAA==.Monkeeh:BAAANQADCggIDQAAAA==.Monkle:BAABNQAECn8qAAIUAAkKgSAsEgDMAgAUAAkKgSAsEgDMAgAAAA==.Monohan:BAAANQADCgUIBQABNQAECggIKgAYAD8dAA==.Moonpaw:BAAANQAECgIIAgAAAA==.Moonsii:BAABNQAECn8oAAMHAAkKlw88NAB4AQAHAAgKZg88NAB4AQAOAAEKQgbwcwAoAAAAAA==.Mooroth:BAABNQAECn8yAAMjAAkK2hQJEgAGAgAjAAgKdBYJEgAGAgAiAAIKQQvU8wA3AAAAAA==.Moreagon:BAAANQAECgIIAgAAAA==.Morkilro:BAAANQAECgEIBAAAAA==.Morozko:BAAANQADCgQIBAAAAA==.',
Ms='Msasani:BAAANQADCgEIAQABNQAECgoKRgADAHIcAA==.Msmana:BAAANQAECgIIBwAAAA==.',
Mu='Muddler:BAABNQAECn8UAAIDAAYKiQGiVACBAAADAAYKiQGiVACBAAAAAA==.Muire:BAAANQAECgYIBQABNQAECgoKOAAcAMEaAA==.Murinn:BAABNQAECn8sAAIKAAkK8QzzTwCtAQAKAAkK8QzzTwCtAQAAAA==.',
['Mà']='Màggles:BAAANQAECgYIEwAAAA==.',
Na='Nadd:BAABNQAECn8WAAIKAAYKBgZcrQDTAAAKAAYKBgZcrQDTAAAAAA==.Naledi:BAAANQADCggIDQAAAA==.Naralyn:BAABNQAECn8xAAMZAAoKHBqlBwBJAgAZAAoKHBqlBwBJAgABAAUKYRG6tgAlAQAAAA==.',
Ne='Negrido:BAABNQAECn85AAQcAAoK7hvvPwCSAgAcAAgKHx3vPwCSAgADAAMKiBubNQDsAAAkAAMKTxMbHACfAAAAAA==.Nei:BAABNQAECn8sAAIRAAgKaBT0VgCxAQARAAgKaBT0VgCxAQAAAA==.Neon:BAAANQADCgUICQAAAA==.',
Ni='Nickellite:BAAANQAECgEIBQAAAA==.Nikem:BAABNQAECn8iAAIOAAoK5hALGADYAQAOAAoK5hALGADYAQAAAA==.',
No='Noelle:BAABNQAECn8VAAIRAAkKpxX9fABXAQARAAkKpxX9fABXAQAAAA==.Norelei:BAAANQAECgIIAgABNQAECgoKRgADAHIcAA==.Noriyuki:BAABNQAECn8YAAIUAAYKEgKGXwBiAAAUAAYKEgKGXwBiAAAAAA==.',
Ny='Nyxahlia:BAAANQADCgUIBgAAAA==.',
Og='Oghom:BAAANQADCggICAAAAA==.Ogrekin:BAAANQAECggIEwAAAA==.',
Ol='Olderon:BAABNQAECn8cAAIMAAkKBhO5WwAFAgAMAAkKBhO5WwAFAgAAAA==.Olrong:BAABNQAECn8vAAIQAAgKgArJLgAsAQAQAAgKgArJLgAsAQAAAA==.Oluja:BAABNQAECn8YAAIEAAkKQwyWZgAKAQAEAAkKQwyWZgAKAQAAAA==.',
On='Onuris:BAAANQAECgMIBwAAAA==.',
Oo='Oogiboogi:BAAANQAECgQIBAAAAA==.',
Op='Opacuslupus:BAAANQAECgQICwAAAA==.Oppressin:BAABNQAECn8qAAIUAAgKXBeTIAAoAgAUAAgKXBeTIAAoAgAAAA==.',
Os='Oshunn:BAABNQAECn8pAAILAAoK/RD+qQAuAgALAAoK/RD+qQAuAgAAAA==.Osroes:BAABNQAECn8VAAIMAAUKXQ6+ugAHAQAMAAUKXQ6+ugAHAQAAAA==.',
Ov='Overdoom:BAABNQAECn8sAAMCAAoKTBsmLwB0AgACAAoKTBsmLwB0AgAFAAUKrBORYAAjAQAAAA==.',
Ow='Owner:BAAANQAECggICAAAAA==.',
Pa='Pacolock:BAAANQADCggICAABNQAECggIFgAMANcTAA==.Paladinjohn:BAACNQAFFH8cAAIRAAYKvSO/AwBnAQARAAYKvSO/AwBnAQA1AAQKfzMAAhEACgrhJawGAEgDABEACgrhJawGAEgDAAAA.Palykat:BAABNQAECn8WAAIRAAYKzQOsKQHbAAARAAYKzQOsKQHbAAAAAA==.Pandadeez:BAAANQADCgYIDQAAAA==.Papiroflz:BAABNQAECn8zAAMBAAoKpyPXDQB6AwABAAoKpyPXDQB6AwAEAAUKexz3fwCMAQAAAA==.',
Pe='Pennydredful:BAAANQAECgEIAQAAAA==.Pennywisé:BAABNQAECn8mAAIFAAkKSiAhGQDCAgAFAAkKSiAhGQDCAgAAAA==.',
Pl='Plaguegying:BAABNQAECn8mAAIYAAkKPhWqJABwAQAYAAkKPhWqJABwAQABNQAECgIIAwASAAAAAA==.Ploofee:BAAANQAECgMICAAAAA==.',
Pr='Preparedr:BAACNQAFFH87AAMaAAkKdiYBAAAMBAAaAAkKYCYBAAAMBAAGAAcKwSZ/AAC0AgA1AAQKfx4AAwYACgrQJc8JANgCAAYACAo/Js8JANgCABoABwrQJSElAGECAAAA.Progresz:BAAANQAECgIIAgAAAA==.',
Pu='Purebread:BAAANQAECgEIAQAAAA==.',
Py='Pykel:BAABNQAECn80AAIOAAoK5QmyHwCJAQAOAAoK5QmyHwCJAQAAAA==.',
Qa='Qaren:BAAANQADCgYIEAAAAA==.',
Qu='Questionable:BAAANQADCgEIAQAAAA==.',
Ra='Raishun:BAAANQAECgEJAQAAAA==.Raizo:BAAANQAECgEIAgAAAA==.Rake:BAABNQAECn84AAIlAAoK6h3hBABOAgAlAAoK6h3hBABOAgAAAA==.Rannï:BAAANQADCgQIBAABNQAECgkJJwAkAAIgAA==.Raskreia:BAABNQAECn8YAAMCAAoKWCJeAwAfAwACAAoKWCJeAwAfAwAFAAUKnxriWABIAQABNQAFFAMIBgAXALoaAA==.Rassina:BAAANQADCgEIAQAAAA==.Rawk:BAAANQAECgEIAgAAAA==.',
Re='Redeemly:BAABNQAECn8VAAIRAAoKOBnzSADdAQARAAoKOBnzSADdAQAAAA==.Redeyejedi:BAAANQAECggIBwAAAA==.Reeven:BAAANQAECggILAAAAQ==.Revokely:BAAANQAECgYIDwABNQAECgoKFQARADgZAA==.',
Rh='Rhcpmage:BAAANQADCggICgABNQAFFAYIHQALANMlAA==.Rhetegast:BAABNQAECn83AAImAAoKcRqTEACVAgAmAAoKcRqTEACVAgAAAA==.',
Ri='Rieloesh:BAAANQAECgMIBQAAAA==.Rike:BAABNQAECn8uAAMmAAgK7RzyHgDvAQAmAAYKVB7yHgDvAQARAAgKXBpWZQCNAQAAAA==.Ristretto:BAAANQADCgYICwABNQAECggIIgAJACodAA==.',
Ro='Roland:BAAANQADCgUJBwAAAA==.Rolandin:BAABNQAECn8pAAIMAAgKohJBMwDUAQAMAAgKohJBMwDUAQAAAA==.',
Ru='Rukraga:BAAANQAECgQJBAAAAA==.',
Ry='Rylagosa:BAABNQAECn8oAAMfAAgK4xxRBgCJAgAfAAgK4xxRBgCJAgAnAAIKGwsgHgAwAAAAAA==.Ryzesmidge:BAAANQAECgcJDQAAAA==.',
['Rê']='Rêdrum:BAAANQAECgYIBgABNQAECgoKNAAJADsbAA==.',
Sa='Salandria:BAABNQAECn8pAAQMAAkKNiMXXgD+AQAMAAUKSSQXXgD+AQAmAAkKLhpCEQCOAQARAAEKAABWnwE3AAAAAA==.Sarionian:BAABNQAECn8aAAIHAAYKPRECJQA1AQAHAAYKPRECJQA1AQAAAA==.Sarjin:BAAANQAECgEIAQABNQAECgoKRgADAHIcAA==.Sarvinblue:BAABNQAECn9GAAMEAAoKKyJ4EABBAwAEAAoKKyJ4EABBAwABAAgKhhTUaQDjAQAAAA==.',
Sc='Schmøtz:BAAANQAECgEIAQAAAA==.Scopolamine:BAAANQAECgQIEAAAAA==.',
Se='Sevrin:BAABNQAECn8rAAIYAAkKzw6PSgDNAQAYAAkKzw6PSgDNAQAAAA==.Seymonty:BAABNQAECn8lAAMWAAoKNw4zDgBMAQAIAAoK8giwhQCGAQAWAAcKMA8zDgBMAQAAAA==.',
Sh='Shaeko:BAAANQADCggIGQAAAA==.Shazlulu:BAABNQAECn8WAAIEAAYK1ROQXQAmAQAEAAYK1ROQXQAmAQAAAA==.Shaznoir:BAABNQAECn8tAAIDAAkKIgm+BQAwAQADAAkKIgm+BQAwAQAAAA==.Shilajit:BAAANQAECgMICwAAAA==.Shokz:BAAANQADCgMIAwABNQAECgMICAASAAAAAA==.',
Sk='Skip:BAAANQADCgcIBwAAAA==.Skøøma:BAAANQAECgEIAQAAAA==.',
Sl='Sloe:BAAANQAECgEIAgABNQAECggIIwAMAH8UAA==.',
Sm='Smokalot:BAAANQAECgIIBgAAAA==.Smokehunter:BAAANQADCgYIBgAAAA==.',
Sn='Snoop:BAAANQAECgEIAQAAAA==.',
So='Solstîce:BAAANQADCgQIBAABNQAECgoKNAAJADsbAA==.Sonsu:BAAANQADCggICAABNQAECgYIGgAHAD0RAA==.',
Sp='Speedbeefbal:BAAANQADCggIFQAAAA==.Speeddwrfbal:BAAANQADCgYIGQAAAA==.Speedmeatbal:BAABNQAECn8ZAAIBAAkKfwUPbADMAAABAAkKfwUPbADMAAAAAA==.Speedmeatlok:BAAANQAECgMIBQAAAA==.Speedmonkbal:BAAANQAECgMIBgAAAA==.Speedoe:BAAANQADCggIEgAAAA==.Spidêrs:BAAANQAECgEIAQAAAA==.Sporkulous:BAABNQAECn8eAAIKAAgKIQj5uQCQAQAKAAgKIQj5uQCQAQAAAA==.',
Sq='Squal:BAAANQAECggIEwAAAA==.Squiggle:BAABNQAECn8lAAImAAgKiBpyEACYAQAmAAgKiBpyEACYAQAAAA==.',
St='Steevii:BAAANQADCgMIAwAAAA==.Stewie:BAAANQAECgUIBgAAAA==.Striker:BAAANQADCgYIDwABNQAECggILgAmAO0cAA==.Strikers:BAAANQAECgEIAwAAAA==.',
Su='Sunshíne:BAABNQAECn8WAAMmAAcKERH8MgBKAQAmAAcKERH8MgBKAQARAAEKwgNK1AEbAAAAAA==.',
Sy='Syver:BAABNQAECn8hAAICAAgKkxmeHgB/AQACAAgKkxmeHgB/AQAAAA==.',
['Sí']='Sírlancealot:BAAANQADCgMIBAAAAA==.',
Ta='Takeke:BAABNQAECn8fAAMYAAoKhxKEHgCdAQAYAAkKhxKEHgCdAQACAAUKUgv/iAD+AAAAAA==.Takeroux:BAAANQAECgEIAQAAAA==.Talandroz:BAABNQAECn8nAAMfAAkK6RxkCAA/AgAfAAkK6RxkCAA/AgAnAAIKTAtvNQBiAAAAAA==.Tanagra:BAAANQADCgIIAgABNQAECggIKgAkALgWAA==.Tankz:BAAANQADCgYIDQAAAA==.Tanner:BAACNQAFFH8NAAIKAAUK1hOXDwDRAAAKAAUK1hOXDwDRAAA1AAQKf0AAAgoACgpOHKwZAIwCAAoACgpOHKwZAIwCAAAA.',
Te='Tebo:BAAANQAECgEIAgAAAA==.Teboe:BAAANQADCgcICQABNQAECgEIAgASAAAAAA==.Tedman:BAABNQAECn8lAAMBAAgKsQ5xigCKAQABAAgKsQ5xigCKAQAEAAYKtg3UtgD/AAAAAA==.Temel:BAABNQAECn8uAAMEAAgK7xOURQB/AQAEAAgK7xOURQB/AQABAAQKXAdI7QC8AAAAAA==.Teostra:BAABNQAECn8qAAMKAAoK7CHNDQDgAgAKAAoK7CHNDQDgAgAgAAEKyAoRTwA3AAAAAA==.Terradan:BAAANQAECgIIAgAAAA==.Testoecles:BAAANQADCgcICwABNQAECgEIAgASAAAAAA==.',
Th='Thadrack:BAAANQAECgcIEQABNQAECgoKGgAIAIYHAA==.Thalonstin:BAAANQAECgEIAQAAAA==.Thaneold:BAAANQAECgQJCgABNQAECgoKMwAIAI4jAA==.Thassarian:BAAANQAECgYIEwAAAA==.Theodrid:BAACNQAFFH8TAAImAAcKpBpPAgAVAgAmAAcKpBpPAgAVAgA1AAQKfzEAAiYACgp/I0MIABoDACYACgp/I0MIABoDAAAA.Thunderstomp:BAAANQADCgIIAgAAAA==.',
Ti='Tinkerspell:BAAANQAECgEIAQAAAA==.Tinkíe:BAABNQAECn8pAAIVAAkKQx89CwDRAgAVAAkKQx89CwDRAgAAAA==.Tirzahdozier:BAAANQAECgEIBAABNQAECgcIEgASAAAAAA==.Tiwohnne:BAAANQAECgUICgAAAA==.',
Tl='Tla:BAAANQADCgYIGAAAAA==.',
Tp='Tpaartos:BAAANQADCgIJAgABNQAECgkJJwAEAMEYAA==.',
Tr='Treat:BAABNQAECn8xAAINAAkKTiLjCgA1AwANAAkKTiLjCgA1AwAAAA==.Trippysheep:BAAANQAECggICQABNQAFFAkJGwAcALkeAA==.Trippyshock:BAAANQADCgEIAQABNQAFFAkJGwAcALkeAA==.Tristitia:BAAANQABCgYICgAAAA==.',
Tu='Turkeltin:BAACNQAFFH8OAAIhAAYKkhaSAwAZAQAhAAYKkhaSAwAZAQA1AAQKfy0AAiEACgrpIjsDAKYDACEACgrpIjsDAKYDAAAA.',
Tw='Twiggle:BAAANQADCgYIBgABNQAECgcIEgASAAAAAA==.Twistedsquid:BAAANQAECgEIAQAAAA==.',
Ty='Tyamat:BAABNQAECn8cAAMkAAcKxhf7CQDcAQAkAAcKxhf7CQDcAQAcAAIKGwVUMwFUAAAAAA==.Tyche:BAAANQADCgYIDAAAAA==.Tyrinara:BAAANQADCggICAAAAA==.Tysbich:BAAANQAECgIIAgABNQAECggIKAAMAOIjAA==.',
Ui='Uiewedaoez:BAABNQAECn8rAAIHAAoKVSWrAwBkAwAHAAoKVSWrAwBkAwAAAA==.',
Va='Vains:BAABNQAECn82AAIRAAoKXR04LgBEAgARAAoKXR04LgBEAgAAAA==.Valrith:BAAANQADCgcIGAAAAA==.',
Ve='Velexi:BAAANQAECgEIAQAAAA==.Velin:BAAANQAECgQIBAAAAA==.Velody:BAAANQADCgQIAQAAAA==.Vendettuh:BAAANQADCgYIBgAAAA==.Veronica:BAABNQAECn8nAAILAAgKqw9jaAB3AQALAAgKqw9jaAB3AQAAAA==.Verren:BAABNQAECn8qAAIdAAgK3hFBHQC3AQAdAAgK3hFBHQC3AQAAAA==.Vesfor:BAAANQAECgEIAQABNQAECgYIFQAKAMcZAA==.Vestus:BAAANQABCggIEAAAAA==.',
Vy='Vyrridyl:BAAANQAECgQIDAAAAA==.',
Wa='Waddlez:BAAANQAECgcIBwAAAA==.Watermark:BAABNQAECn8hAAMEAAgK5gtGmwBCAQAEAAgK5gtGmwBCAQABAAQKiANSlgByAAAAAA==.',
We='Weeblewobble:BAAANQAECgIIAwAAAA==.Weltamus:BAAANQADCgYIEAAAAA==.Weltazar:BAABNQAECn8hAAIBAAgKRRSiRQA/AQABAAgKRRSiRQA/AQAAAA==.Weltzilla:BAABNQAECn8kAAIKAAgKKhxtRADSAQAKAAgKKhxtRADSAQAAAA==.Westside:BAAANQAECgYIDgABNQAECggIDQASAAAAAA==.',
Wh='Whoosh:BAABNQAECn8sAAIYAAkKKiKDFgD5AgAYAAkKKiKDFgD5AgAAAA==.',
Wi='Wickët:BAABNQAECn8pAAMEAAkKESQwFgAfAwAEAAgK6iMwFgAfAwABAAcKex2EWQAWAgAAAA==.Wildtiger:BAABNQAECn8sAAIlAAkKGxE2EQDwAQAlAAkKGxE2EQDwAQAAAA==.Wisey:BAAANQAECgQIBAAAAA==.',
Wo='Wolfslied:BAAANQADCgQIBAABNQADCgQIBAASAAAAAA==.',
Wu='Wulfenhide:BAABNQAECn8jAAIaAAkKCyBlBQBmAgAaAAkKCyBlBQBmAgAAAA==.Wuntvor:BAAANQADCggICAAAAA==.',
Wy='Wyzsky:BAAANQAECgEIAwABNQAECggILgAEAO8TAA==.',
Xa='Xalren:BAAANQAECgEIAQAAAA==.Xalreth:BAABNQAECn8kAAIhAAgKfAiUNwCHAQAhAAgKfAiUNwCHAQAAAA==.Xaviana:BAAANQAECgUIBgAAAQ==.',
Ya='Yastypoo:BAABNQAECn8oAAMMAAoK6hD1VAAbAgAMAAoK6hD1VAAbAgARAAEKShlkNAE/AAAAAA==.',
Za='Zarieda:BAAANQAECgcIDwAAAA==.Zayrelia:BAACNQAFFH8WAAIHAAYKFhVQBAB4AQAHAAYKFhVQBAB4AQA1AAQKf0UAAwcACgrTIcMDAGEDAAcACgrTIcMDAGEDAA4ABgphFZtQAJsBAAAA.',
Ze='Zelenor:BAAANQAECgEIBAABNQAECgcIHAAkAMYXAA==.',
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
