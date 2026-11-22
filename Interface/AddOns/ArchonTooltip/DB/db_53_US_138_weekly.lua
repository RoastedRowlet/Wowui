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

local lookup = {'Shaman-Elemental','DeathKnight-Unholy','Warlock-Destruction','Shaman-Restoration','Evoker-Devastation','Evoker-Preservation','DeathKnight-Frost','Rogue-Subtlety','Druid-Restoration','Priest-Holy','DemonHunter-Vengeance','Hunter-BeastMastery','Mage-Arcane','Paladin-Holy','Priest-Shadow','Druid-Balance','Paladin-Retribution','Hunter-Survival','DemonHunter-Havoc','Warrior-Protection','Unknown-Unknown','Monk-Brewmaster','Monk-Windwalker','Monk-Mistweaver','Priest-Discipline','Mage-Frost','Warrior-Fury','Warrior-Arms','DeathKnight-Blood','Shaman-Enhancement','Rogue-Assassination','Rogue-Outlaw','Warlock-Demonology','Druid-Guardian','Evoker-Augmentation','Hunter-Marksmanship','DemonHunter-Devourer','Warlock-Affliction','Druid-Feral','Paladin-Protection',}
local provider = {region='US',realm='KulTiras',name='US',type='weekly',zone=53,date='2026-11-17',data={Aa='Aarix:BAABNQAECn8lAAIBAAoKlAsXkgB3AQABAAoKlAsXkgB3AQAAAA==.',
Ae='Aendillan:BAAANQADCgUIBQAAAA==.',
Af='Affonasei:BAABNQAECn8/AAICAAkKNQk8NQBKAQACAAkKNQk8NQBKAQAAAA==.',
Ag='Agkistrodon:BAAANQADCgcIDQABNQAECgoKVAADAJwdAA==.',
Ai='Aicaramba:BAABNQAECn9BAAIEAAoK8yCEEAA3AwAEAAoK8yCEEAA3AwAAAA==.Aileen:BAABNQAECn8eAAMFAAUK6AHpLwCbAAAFAAUK6AHpLwCbAAAGAAUK4ASvLACZAAAAAA==.',
Aj='Ajay:BAAANQAECgYIBgAAAA==.',
Ak='Akashi:BAABNQAECn8XAAIHAAkKOhLFQgC5AQAHAAkKOhLFQgC5AQABNQAFFAYIEQAIAO0NAA==.',
Al='Alacrodie:BAAANQADCgYIHAAAAA==.',
Am='Amoonsi:BAAANQAECgMIAwABNQAECgoKPwAJAE0SAA==.Amordeyain:BAAANQAECggIDwAAAA==.',
An='Angrydisc:BAABNQAECn8gAAIKAAoKjgdHegBrAQAKAAoKjgdHegBrAQAAAA==.Angrytotems:BAAANQAECgUIBwABNQAECgoKIAAKAI4HAA==.Angyll:BAAANQABCggIGwAAAA==.Annaborshen:BAAANQABCgIIAgAAAA==.Antoccino:BAAANQAECgcIDQABNQAECgoKLAALAJ0dAA==.',
Ar='Aragorno:BAABNQAECn8zAAIMAAoKFBWdTAA2AgAMAAoKFBWdTAA2AgAAAA==.Arcturen:BAABNQAECn8oAAIMAAgKoRnFngB2AQAMAAgKoRnFngB2AQAAAA==.Ardala:BAAANQAECggICAAAAA==.Arenthal:BAAANQAECgYIDgABNQAECgoKQwANAJsfAA==.Armonni:BAAANQABCgIIAgAAAA==.Arturaan:BAAANQADCgIIAgAAAA==.',
As='Ashalana:BAAANQADCgUIBQAAAA==.Asheby:BAAANQADCgMIAwABNQAECgoKLwAOACgXAA==.Ashenisson:BAAANQAECgQIBAABNQAECggIKAABABQSAA==.Ashiera:BAABNQAECn8lAAINAAgKwAKVMwE2AQANAAgKwAKVMwE2AQAAAA==.Ashrai:BAAANQADCgEIAQABNQAECgoKVAADAJwdAA==.Astralmorph:BAAANQADCgYIBgAAAA==.',
At='Atomic:BAAANQAECgQIDAAAAA==.',
Au='Augenblick:BAAANQADCgIIAgAAAA==.Aurorée:BAAANQAECgYICwAAAA==.',
Av='Avattar:BAAANQABCgMIBQAAAA==.',
Aw='Aware:BAAANQADCgIIAgAAAA==.',
Az='Azylstrid:BAAANQADCgYIDAAAAA==.',
Ba='Baeu:BAAANQABCgUIBwAAAA==.Balentine:BAABNQAECn8fAAMKAAkK4gnehQBHAQAKAAkK4gnehQBHAQAPAAIKLwGweQA0AAAAAA==.Banostraza:BAAANQAECgQIBQAAAA==.Baspir:BAABNQAECn88AAIQAAoKcRkyGQBEAgAQAAoKcRkyGQBEAgAAAA==.Bavette:BAABNQAECn8bAAMOAAgKpxmTLwBkAgAOAAgKpxmTLwBkAgARAAgK3AKyOgGWAAABNQAECgoKNgAKANUfAA==.',
Be='Beeboop:BAAANQAECgUICQAAAA==.Belly:BAABNQAECn8rAAISAAkKZh/3AwC5AgASAAkKZh/3AwC5AgAAAA==.Belrae:BAABNQAECn8vAAITAAkKIhPvIwDrAQATAAkKIhPvIwDrAQAAAA==.Beltira:BAAANQADCggIDAABNQAECgoKQQAUAOQWAA==.Benchfresh:BAABNQAECn8xAAIRAAgKYSGDQQBlAgARAAgKYSGDQQBlAgAAAA==.Bendah:BAAANQAECgEIAQAAAA==.Bender:BAAANQADCgYIBgAAAA==.Bezieck:BAAANQAECgYIEQAAAA==.',
Bi='Bigfolks:BAAANQADCgUIBwAAAA==.Bigollock:BAAANQADCgYICwAAAA==.Bili:BAAANQAECgYIBgAAAA==.',
Bl='Blacktide:BAAANQADCgYIBgAAAA==.Bloodarrow:BAAANQADCgUIBwAAAA==.Bloodbound:BAAANQADCgYIBgAAAA==.',
Bo='Bockchi:BAAANQAECgQIBQAAAA==.Bonanas:BAAANQABCggICAAAAA==.Bonegavel:BAAANQABCgQIBgABNQABCgYIDAAVAAAAAA==.Bookhuntress:BAAANQAECggIEQAAAA==.',
Br='Branex:BAAANQAECggICAAAAA==.Branpaw:BAAANQADCgQIAwAAAA==.Brewdeez:BAABNQAECn8sAAMWAAoKXBYtDABCAgAWAAkKphgtDABCAgAXAAEKWQZ/YgAoAAAAAA==.Brewzen:BAAANQADCgYIBgAAAA==.Brewzer:BAABNQAECn84AAIYAAoKpBDQEwDJAQAYAAoKpBDQEwDJAQAAAA==.Brick:BAAANQADCgUIBAABNQAECgkJJQAZAAwUAA==.Brint:BAAANQADCgcIDAAAAA==.Bronad:BAACNQAFFH8eAAMaAAcKvSXNAQAmAQANAAUKqSaGFgA/AQAaAAMK+yPNAQAmAQA1AAQKf1oAAw0ACgriJp8BAPMDAA0ACgriJp8BAPMDABoAAgrzHyE2AFMAAAAA.Broomhandle:BAABNQAECn83AAIRAAoKTh5fQQDQAgARAAoKTh5fQQDQAgAAAA==.',
Bu='Bumbushka:BAABNQAECn8UAAMbAAkKRRw/CwAQAgAbAAgKWh0/CwAQAgAcAAIKdRXp9gCGAAAAAA==.Burinn:BAABNQAECn8oAAIMAAgK9BKuqQBfAQAMAAgK9BKuqQBfAQABNQAECgoKTwAKAC8aAA==.',
Ca='Caeus:BAABNQAECn8rAAQHAAoKER0YKwBDAgAHAAoKDxsYKwBDAgACAAYKUhrURwD4AQAdAAQKsxroXADOAAAAAA==.Cajuil:BAAANQAECggIEAAAAA==.Cam:BAABNQAECn8VAAMNAAcKLiE5pgA1AgANAAcKLiE5pgA1AgAaAAMKrhRRKgCmAAAAAA==.Carolinabele:BAAANQADCggICAAAAA==.Cauud:BAAANQADCgYIEAAAAA==.',
Cb='Cbd:BAAANQADCgcIEwAAAA==.',
Ce='Celerious:BAAANQAECggIEwAAAA==.',
Ch='Chacruna:BAAANQAECgMIBgAAAA==.Chelan:BAABNQAECn9PAAMKAAoKLxpEJQC+AgAKAAoKLxpEJQC+AgAPAAEKAAAUkQAZAAAAAA==.Chewseph:BAAANQADCgMIAwAAAA==.Chloelock:BAAANQABCgEJAQABNQABCgQIBAAVAAAAAA==.Chronicler:BAAANQADCgEIAQAAAA==.Chuntspeed:BAAANQAECgYICwAAAA==.Chuye:BAAANQAECgEIAQABNQAECgoKNgAKANUfAA==.',
Cl='Clambulance:BAABNQAECn84AAIMAAoKmhvUQwCfAgAMAAoKmhvUQwCfAgAAAA==.',
Cn='Cnova:BAABNQAECn8bAAMEAAcKLxaQmABKAQAEAAcKLxaQmABKAQAeAAUKQwVvLACRAAABNQAECgoKJwARAIsZAA==.',
Co='Codythedead:BAACNQAFFH8aAAMCAAcKzxlRAgCUAQACAAcKzxlRAgCUAQAdAAEKAAAkQQAOAAA1AAQKf0oAAgIACgrNJLcFAJ4DAAIACgrNJLcFAJ4DAAAA.Coraf:BAACNQAFFH8eAAIEAAcKXh62BQBOAgAEAAcKXh62BQBOAgA1AAQKfzIAAgQACgpXJMoNAFMDAAQACgpXJMoNAFMDAAAA.Coyotl:BAABNQAECn8bAAISAAgKow7DCABpAQASAAgKow7DCABpAQAAAA==.',
Cr='Crazyazshamy:BAAANQAECggIEwAAAA==.',
Cu='Cuvier:BAAANQADCggJFgAAAA==.',
Da='Daltenton:BAABNQAECn8YAAIOAAkKHg03WgCvAQAOAAkKHg03WgCvAQABNQAECgoKJgAZADcOAA==.Danak:BAAANQADCgYIFwAAAA==.Darcia:BAAANQABCggIDwAAAA==.Dascrazy:BAAANQADCgQICAAAAA==.',
De='Deadlyfrosty:BAAANQADCgYIDgAAAA==.Deathmob:BAABNQAECn8wAAIdAAoKnhqjKgBxAgAdAAoKnhqjKgBxAgAAAA==.Deathsynth:BAAANQADCgQJBAABNQAECgoKLQANAO8bAA==.Debixie:BAACNQAFFH8GAAMfAAMKNhuJFAClAAAfAAIKNhuJFAClAAAIAAEKAADgLAAAAAA1AAQKfywABB8ACgoGIUwKADoDAB8ACgqBH0wKADoDACAABgoEE+QNAGIBAAgABQp5G0h1AEkBAAAA.Decisive:BAAANQADCgYIBgABNQAFFAkJKQAhAFMkAA==.Dejection:BAAANQABCgYIBwAAAA==.Demisi:BAAANQAECgYICgAAAA==.Demiurge:BAABNQAECn8yAAIQAAoKUh4EHwDSAgAQAAoKUh4EHwDSAgABNQAFFAUIBQAhAJwHAA==.Despayr:BAAANQADCgYICwAAAA==.',
Di='Diasundra:BAABNQAECn9BAAIMAAoKXyP8EwD8AgAMAAoKXyP8EwD8AgAAAA==.Dibbons:BAAANQAECgYIBwAAAA==.Divinatjin:BAAANQADCgYICQAAAA==.',
Do='Dollars:BAAANQAECggICwAAAA==.Dottingyou:BAACNQAFFH8eAAMhAAcKohHpEgARAQAhAAYKYw3pEgARAQADAAIK9hIWCACBAAA1AAQKfzYAAyEACgonI9cmAHUCACEACQrAI9cmAHUCAAMABgrZGC4YAKsBAAAA.',
Dr='Dracthyrbm:BAAANQAECgUIEAAAAA==.Dragonshide:BAAANQAECgIIAgABNQAECgoKLwADAF4gAA==.Dreegor:BAAANQABCgIIAgAAAA==.Dreepy:BAAANQAECgYIBQAAAA==.Drransom:BAAANQADCgYIEwAAAA==.Dryan:BAABNQAECn8wAAIiAAoKAhNbHACgAQAiAAoKAhNbHACgAQAAAA==.',
Du='Dugathaks:BAAANQADCgYIBgAAAA==.Duo:BAABNQAECn9FAAIMAAoKrRc3TgCEAgAMAAoKrRc3TgCEAgAAAA==.Duragon:BAABNQAECn8mAAMjAAkKYwlEDQB7AQAjAAkKYwlEDQB7AQAGAAEKtQAAVgAZAAAAAA==.',
Ei='Eipwoc:BAAANQADCggIBwAAAA==.',
El='Eloreith:BAABNQAECn81AAMQAAoKuBqrHgALAgAQAAoKuBqrHgALAgAiAAUKvAjzPwC7AAAAAA==.',
Em='Emamagee:BAAANQADCgQIBgAAAA==.Emilia:BAABNQAECn9IAAIKAAoK9RtsMACCAgAKAAoK9RtsMACCAgAAAA==.',
En='Endressa:BAABNQAECn9FAAMZAAoKmBysAQD6AgAZAAoKmBysAQD6AgAPAAcKxhCbQgAeAQAAAA==.',
Er='Eralendryn:BAAANQADCgEIAQAAAA==.Erelios:BAABNQAECn8sAAMOAAoKJgm2dQBUAQAOAAoKJgm2dQBUAQARAAMK0gh2dQFRAAAAAA==.',
Es='Eski:BAABNQAECn9bAAMgAAoKUCNxAAAkAwAgAAoKUCNxAAAkAwAfAAIK2wn3lABgAAAAAA==.Essaena:BAABNQAECn8oAAIdAAoKASFkIQCpAgAdAAoKASFkIQCpAgAAAA==.',
Eu='Eura:BAAANQADCgEIAQAAAA==.Eureka:BAEANQAECgcIEQAAAA==.',
Ev='Everlight:BAAANQADCggIEAABNQAECgoKVAADAJwdAA==.',
Ez='Ezrì:BAAANQADCgcIBwAAAA==.',
Fa='Faddeyshnek:BAABNQAECn8rAAIMAAkKvg8GigCkAQAMAAkKvg8GigCkAQAAAA==.Farmeador:BAAANQAECgEIAQAAAA==.Fastbeefball:BAAANQADCggIGAAAAA==.Fatgirljuice:BAACNQAFFH8VAAMMAAcK1yCgAAC5AgAMAAcK1yCgAAC5AgAkAAIKrg+tHACMAAA1AAQKfx8AAwwACQpDJhUHAFQDAAwACQpDJhUHAFQDACQAAQr0Gn1+AEoAAAAA.',
Fe='Felysambre:BAABNQAECn82AAIlAAgKAw3sKgBAAQAlAAgKAw3sKgBAAQAAAA==.',
Fi='Fish:BAACNQAFFH8pAAIPAAkK7yWkAAD0AgAPAAkK7yWkAAD0AgA1AAQKfzkAAg8ACgrWJr8AAIoDAA8ACgrWJr8AAIoDAAAA.',
Fl='Flight:BAACNQAFFH8RAAMIAAYK7Q2aDQAyAQAIAAUK5QmaDQAyAQAfAAEKCx7SGwBXAAA1AAQKf0UAAwgACgoYIeAaAKsCAAgACgoCHeAaAKsCAB8ACQo1IdAbAKACAAAA.Floofee:BAAANQADCgQIBAAAAA==.',
Fo='Footfinger:BAAANQAECgIIAgAAAA==.Forsynth:BAABNQAECn8tAAINAAoK7xuQNwBnAgANAAoK7xuQNwBnAgAAAA==.Foxymeatbal:BAAANQADCggIDQAAAA==.',
Fu='Fubar:BAAANQAECgYICQAAAA==.',
Ga='Ganniy:BAAANQABCgEJAQAAAA==.',
Ge='Gewitt:BAAANQAECgQICAAAAA==.',
Gl='Glinda:BAAANQADCgYIEQAAAA==.',
Go='Gonjah:BAABNQAECn8jAAQKAAkKfhGwjwBnAQAKAAgKRRKwjwBnAQAPAAUKyA0CRQAPAQAZAAEKbQMbHwAfAAAAAA==.',
Gr='Grabomage:BAABNQAECn8VAAMNAAcKGCNhCQF9AQANAAcKGCNhCQF9AQAaAAEKvxpwRAA6AAABNQAFFAcIHgAaAL0lAA==.Grabovoker:BAAANQADCgIIAgABNQAFFAcIHgAaAL0lAA==.Grazienne:BAAANQADCgYIFAAAAA==.Greavos:BAABNQAECn81AAIPAAoKGhdxEwAlAgAPAAoKGhdxEwAlAgAAAA==.Griggus:BAABNQAECn82AAIcAAoKwBOUXQDmAQAcAAoKwBOUXQDmAQAAAA==.Grimgar:BAABNQAECn86AAMNAAoKxheygQCmAQANAAgK8BaygQCmAQAaAAMKEBmZIgDXAAAAAA==.Grimmshady:BAAANQADCgQICgAAAA==.Grumpsky:BAAANQADCgEIAQABNQAECgoKQgAEAKETAA==.',
Gu='Gumbles:BAABNQAECn82AAMKAAoK1R8EIADfAgAKAAoK1R8EIADfAgAPAAIKbQI7cABIAAAAAA==.Gurney:BAABNQAECn8ZAAMOAAoKWxgrMgCcAgAOAAoKWxgrMgCcAgARAAEK9gRm0wEcAAAAAA==.Guzprimal:BAAANQAECgEIAQAAAA==.',
Gw='Gwenory:BAAANQABCgQIBAAAAA==.',
Gy='Gying:BAAANQAECgcIDgAAAA==.',
Ha='Hanekawa:BAABNQAECn8oAAIOAAoKFR2ILgBpAgAOAAoKFR2ILgBpAgABNQAFFAUIDwAaABIfAA==.Hannie:BAAANQADCgcIHAAAAA==.',
He='Headhúnter:BAAANQAECgYICAAAAA==.Heartsparx:BAABNQAECn8yAAIfAAoKthbnDAD9AQAfAAoKthbnDAD9AQAAAA==.Heatseeka:BAABNQAECn81AAMEAAoKMhLAZgCBAQAEAAkKVhHAZgCBAQAeAAcKbQLzIwAdAQAAAA==.Heitan:BAAANQAECgUIDAABNQAECgoKPwAhAAAdAA==.Hexxiz:BAAANQAECgUIBgABNQAECgoKJwAiAK8jAA==.',
Hi='Hiphopinator:BAABNQAECn8xAAIUAAoKlyTKAgAfAwAUAAoKlyTKAgAfAwAAAA==.',
Ho='Ho:BAAANQADCgQIBAAAAA==.Holyshock:BAABNQAECn9DAAMOAAoK0hykLAC0AgAOAAoK0hykLAC0AgARAAEKLgTGswEgAAAAAA==.Holyterror:BAAANQADCgYIGQAAAA==.',
Ia='Ianthe:BAAANQAECgcICwAAAA==.',
Ib='Iboga:BAABNQAECn8cAAMSAAcK1gc6CwANAQASAAcK1gc6CwANAQAMAAIKwwGkRwFQAAAAAA==.Ibrahimovic:BAAANQAECgUICAAAAA==.',
Ig='Ignitecro:BAAANQABCgcIDwAAAA==.Igram:BAAANQAECgcIEwAAAA==.',
Il='Illumona:BAABNQAECn8lAAMLAAcKCggQGwC8AAALAAcKCggQGwC8AAATAAYKZQLAbwBqAAAAAA==.Iluz:BAAANQADCgMIAwAAAA==.',
In='Inafume:BAAANQAECgYIBgAAAA==.Inoxia:BAAANQAECgUIDQAAAA==.Intrépidice:BAAANQAECgQIDQAAAA==.',
Ix='Ixtabay:BAABNQAECn8nAAQmAAkKAiB7AgD3AgAmAAkKQx17AgD3AgADAAMK3BeIPADPAAAhAAMKvQ1BEgGmAAAAAA==.',
Ja='Jamurra:BAAANQAECgcIEgAAAA==.Jaylinn:BAABNQAECn8sAAIMAAoKnQfmpAC8AQAMAAoKnQfmpAC8AQAAAA==.Jazzmend:BAAANQAECgQIBAAAAA==.',
Je='Jeanne:BAABNQAECn89AAIMAAkK/hq/QgBOAgAMAAkK/hq/QgBOAgABNQAECgoKWwAgAFAjAA==.Jellykins:BAABNQAECn8vAAIOAAoKKBcMKACLAgAOAAoKKBcMKACLAgAAAA==.',
Ji='Jimjamjuju:BAAANQAECgYICQAAAA==.Jimsonweed:BAABNQAECn8fAAIIAAoKVggLYwCDAQAIAAoKVggLYwCDAQAAAA==.',
Jo='Josie:BAABNQAECn84AAMZAAoK8Bq6AQDzAgAZAAoK8Bq6AQDzAgAPAAEKqwaXaQAqAAAAAA==.Jozbirt:BAABNQAECn8mAAInAAgKng6tEQDmAQAnAAgKng6tEQDmAQAAAA==.',
Ka='Kaeiria:BAAANQADCgQIBAAAAA==.Kael:BAABNQAECn8oAAMEAAgKaxj0dwBLAQAEAAYKoRT0dwBLAQABAAgKqgoAewAdAQAAAA==.Kalaanri:BAABNQAECn8oAAMBAAgKFBK+bwA5AQABAAgKFBK+bwA5AQAEAAYK4xKNvQDvAAAAAA==.Kalyandra:BAABNQAECn8wAAIXAAkKTQsmKwBAAQAXAAkKTQsmKwBAAQAAAA==.Karlach:BAAANQADCgYIBwABNQAECgoKMgAfALYWAA==.Karumie:BAABNQAECn8+AAIEAAoKUxugIAC5AgAEAAoKUxugIAC5AgAAAA==.Kateera:BAAANQADCgQIBAAAAA==.',
Ke='Keden:BAAANQADCgYICgAAAA==.Kelesa:BAAANQAECgEIAQAAAA==.Keljaden:BAABNQAECn9LAAMcAAoKSCZAAQCQAwAcAAoKSCZAAQCQAwAUAAIKbB39PABMAAAAAA==.Kenner:BAAANQAECgIIAgAAAA==.',
Kh='Kheyra:BAABNQAECn8sAAIiAAgKqCG8CwCuAgAiAAgKqCG8CwCuAgABNQAECgoKVAADAJwdAA==.Khloesham:BAAANQABCgQIBAAAAA==.',
Ki='Kirsha:BAAANQAECgcIEQABNQAECgcIEgAVAAAAAA==.Kittybeef:BAAANQABCgIIAgAAAA==.Kiwiiga:BAAANQAECgIIAwAAAA==.',
Kn='Knoxxic:BAAANQADCgMIBAAAAA==.',
Ko='Koggs:BAAANQADCgEIAQABNQAECgoKQQAUAOQWAA==.Kohnor:BAAANQADCgcIHQAAAA==.Koopalizard:BAABNQAECn8rAAIGAAoKsSEIBgAPAwAGAAoKsSEIBgAPAwAAAA==.Kopi:BAABNQAECn8sAAILAAoKnR3LBACIAgALAAoKnR3LBACIAgAAAA==.Korlatt:BAABNQAECn86AAMTAAoK/h2HFgBmAgATAAoKwx2HFgBmAgALAAQKTCAgGAAuAQAAAA==.Kowalabear:BAAANQAECgEIAQAAAA==.',
Ku='Kuaha:BAAANQADCgYIBgABNQADCgQIBAAVAAAAAA==.Kupa:BAAANQADCgYJBwAAAA==.Kurom:BAAANQADCgcJDQAAAA==.Kurston:BAABNQAECn9OAAIJAAoK8yKvAwDEAwAJAAoK8yKvAwDEAwAAAA==.',
Ky='Ky:BAAANQADCgEIAQAAAA==.',
['Kã']='Kãtniss:BAAANQADCgUIFQAAAA==.',
La='Labella:BAAANQADCggIKwAAAA==.Lacia:BAAANQAECgQIBQABNQAECgoKIAAKAI4HAA==.Laih:BAABNQAECn8pAAIfAAoKDgqZFQCBAQAfAAoKDgqZFQCBAQAAAA==.Landsong:BAAANQADCgQIBAAAAA==.Lastmanalive:BAAANQADCgcIBwAAAA==.',
Le='Leyote:BAABNQAECn87AAIEAAoKLhFAQgALAgAEAAoKLhFAQgALAgAAAA==.',
Li='Liady:BAAANQADCgEJAQAAAA==.Lightshop:BAAANQADCgYICQAAAA==.Liirah:BAAANQADCgYICQAAAA==.Lilyfox:BAAANQAECgYIEAABNQAECgYIFwAHAC4MAA==.Lindithrial:BAAANQABCggICgAAAA==.Livingdead:BAAANQAECgIIAgAAAA==.',
Lo='Lorianne:BAAANQAECgQICAAAAA==.Lorraine:BAAANQADCggIDAAAAA==.Loupon:BAAANQAECggIAwABNQAECgoKPwAhAAAdAA==.Lowdangle:BAAANQADCgcIBwAAAA==.',
Lu='Lulz:BAAANQAECggICQAAAA==.Luucifur:BAAANQABCgMIAwAAAA==.',
Ma='Mackpumpkin:BAAANQAECgIIAgAAAA==.Macktheknife:BAAANQADCgQICAABNQAECgkJJwAmAAIgAA==.Madalyn:BAAANQADCgEIAQAAAA==.Maexna:BAAANQADCgIIAgAAAA==.Magdelyne:BAABNQAECn8aAAIRAAoKMQjb6gBGAQARAAoKMQjb6gBGAQAAAA==.Magglés:BAAANQAECgIIAgAAAA==.Makklehaney:BAABNQAECn8WAAIBAAgKZwstfACvAQABAAgKZwstfACvAQAAAA==.Mallaah:BAAANQADCgUIBQAAAA==.Marovingian:BAABNQAECn8vAAIOAAoKVSPsEQAtAwAOAAoKVSPsEQAtAwAAAA==.Matthad:BAABNQAECn8sAAIEAAoKyRkIXQD4AQAEAAoKyRkIXQD4AQAAAA==.Mazìkene:BAAANQAECgQIAwABNQAECgoKOAALAI0bAA==.',
Mc='Mcnastie:BAAANQAECgUIDwAAAA==.Mcsluts:BAAANQADCgYJCwAAAA==.',
Me='Melmirict:BAAANQADCgMJAwAAAA==.Merciala:BAABNQAECn9MAAQQAAoKwBC6MQB8AQAQAAkKLA26MQB8AQAJAAoKQQOHRwDiAAAiAAQK7g7HPwDAAAAAAA==.',
Mi='Milyyanna:BAAANQADCgcIHAAAAA==.Mindßender:BAAANQADCgcIBwAAAA==.Mirilla:BAABNQAECn8sAAMNAAoKAxQtVAAWAgANAAoKAxQtVAAWAgAaAAcKPAWUGQApAQAAAA==.',
Mo='Moddoxx:BAABNQAECn84AAQhAAoKkxnZPQAdAgAhAAoKpxbZPQAdAgAmAAcKOxl5DQBjAQADAAEKHA1FeAA1AAAAAA==.Moffa:BAAANQADCgMIAwAAAA==.Mohawk:BAABNQAECn8lAAIJAAoKlBhqGQBwAgAJAAoKlBhqGQBwAgAAAA==.Molen:BAAANQAECgEIAQAAAA==.Mommyjuice:BAAANQAECggIDgABNQAFFAcIFQAMANcgAA==.Monkeeh:BAAANQADCggIEAAAAA==.Monkle:BAABNQAECn80AAIXAAoKNR+3CwCkAgAXAAoKNR+3CwCkAgAAAA==.Monohan:BAAANQADCgUIBQABNQAECgoKMAAdAJ4aAA==.Moonpaw:BAAANQAECgIIAgAAAA==.Moonsii:BAABNQAECn8/AAMJAAoKTRLMHgAJAgAJAAoKTRLMHgAJAgAQAAEKQgZ+kgAoAAAAAA==.Mooroth:BAABNQAECn9BAAMUAAoK5BZODwDDAQAUAAkKjhhODwDDAQAcAAIKQQueLAEzAAAAAA==.Morkilro:BAAANQABCgIIAgAAAA==.Morozko:BAAANQADCgQIBAAAAA==.',
Ms='Msasani:BAAANQADCgEIAQABNQAECgoKVAADAJwdAA==.',
Mu='Muddler:BAABNQAECn8UAAIDAAYKiQGiVACBAAADAAYKiQGiVACBAAAAAA==.Murinn:BAABNQAECn8xAAIMAAoKyw3qawDqAQAMAAoKyw3qawDqAQAAAA==.',
['Mà']='Màggles:BAAANQAECgYIEQAAAA==.',
Na='Nadd:BAABNQAECn8fAAIMAAgKUgZduwA7AQAMAAgKUgZduwA7AQAAAA==.Naledi:BAAANQADCggIDQAAAA==.Naralyn:BAABNQAECn81AAMeAAoKOBpfDgAvAgAeAAoKOBpfDgAvAgABAAUKYRG6tgAlAQAAAA==.',
Ne='Needlepax:BAAANQABCgMIAwAAAA==.Negrido:BAABNQAECn9BAAQhAAoKYhzvPwCSAgAhAAgKHx3vPwCSAgADAAMKiBubNQDsAAAmAAMKHhUbHACfAAAAAA==.Nei:BAABNQAECn9AAAIRAAkKUhVgaQD9AQARAAkKUhVgaQD9AQAAAA==.Neon:BAAANQADCgUICQAAAA==.',
Ni='Nikem:BAABNQAECn8rAAIQAAoKfhJfIgDqAQAQAAoKfhJfIgDqAQAAAA==.',
No='Noelle:BAABNQAECn8aAAIRAAkKdht8lACjAQARAAkKdht8lACjAQAAAA==.Norelei:BAAANQAECgIIAgABNQAECgoKVAADAJwdAA==.Noriyuki:BAABNQAECn8eAAIXAAYKEgKGXwBiAAAXAAYKEgKGXwBiAAAAAA==.',
Ny='Nyxahlia:BAAANQADCggIDgABNQAECgoKSAAKAPUbAA==.',
Og='Oghom:BAAANQADCggICAAAAA==.Ogrekin:BAABNQAECn8UAAIeAAkKXA91FADPAQAeAAkKXA91FADPAQAAAA==.',
Ol='Olderon:BAABNQAECn8oAAIOAAoKJxW4RgD5AQAOAAoKJxW4RgD5AQAAAA==.Olrong:BAABNQAECn87AAITAAoKlQrHMwB/AQATAAoKlQrHMwB/AQAAAA==.Oluja:BAABNQAECn8YAAIEAAkKQwyqmQDuAAAEAAkKQwyqmQDuAAAAAA==.',
On='Onuris:BAAANQAECgMICAAAAA==.',
Oo='Oogiboogi:BAAANQAECgQIAwAAAA==.',
Op='Opacuslupus:BAAANQAECgQICQAAAA==.Oppressin:BAABNQAECn8xAAIXAAoKfRV/GgDYAQAXAAoKfRV/GgDYAQAAAA==.',
Os='Oshunn:BAABNQAECn8pAAINAAoK/RD+qQAuAgANAAoK/RD+qQAuAgAAAA==.Osroes:BAAANQAECgQIEgAAAA==.',
Ov='Overdoom:BAABNQAECn8sAAMCAAoKTBsmLwB0AgACAAoKTBsmLwB0AgAHAAUKrBORYAAjAQAAAA==.Ovji:BAAANQAECgUIBgAAAA==.Ovli:BAAANQAECgUIDQAAAA==.',
Ow='Owner:BAAANQAECggICQAAAA==.',
Pa='Pacolock:BAAANQADCggICAABNQAECggIFgAOANcTAA==.Paladinjohn:BAACNQAFFH8dAAIRAAcKBSL7BQD2AQARAAcKBSL7BQD2AQA1AAQKfzUAAhEACgrhJa4SABsDABEACgrhJa4SABsDAAAA.Palykat:BAABNQAECn8qAAIRAAgKMgbKDAHWAAARAAgKMgbKDAHWAAAAAA==.Pandadeez:BAAANQADCgYIDQAAAA==.Papiroflz:BAABNQAECn9GAAMBAAoKBiXQBQBSAwABAAoKBiXQBQBSAwAEAAUKexz3fwCMAQAAAA==.',
Pe='Pennywisé:BAABNQAECn8mAAIHAAkKSiAhGQDCAgAHAAkKSiAhGQDCAgAAAA==.',
Pl='Plaguegying:BAABNQAECn8/AAIdAAoKXBqcFABoAgAdAAoKXBqcFABoAgABNQAECgcIDgAVAAAAAA==.Ploofee:BAAANQAECgMIBQAAAA==.',
Pr='Preparedr:BAACNQAFFH87AAMfAAkKdiYBAAAMBAAfAAkKYCYBAAAMBAAIAAcKwSZ/AAC0AgA1AAQKfx8AAwgACgruJc8JANgCAAgACAo/Js8JANgCAB8ABwryJSElAGECAAAA.Progresz:BAAANQAECgMIAwAAAA==.',
Pu='Purebread:BAAANQAECgEIAQAAAA==.',
Py='Pykel:BAABNQAECn8+AAIQAAoKCwtBLgCTAQAQAAoKCwtBLgCTAQAAAA==.',
Qa='Qaren:BAAANQADCgYIEAAAAA==.',
Qu='Questionable:BAAANQADCgEIAQAAAA==.',
Ra='Raishun:BAAANQAECgEJAQAAAA==.Raizo:BAAANQAECgEIAQAAAA==.Rake:BAABNQAECn9AAAInAAoKmCHlAwD4AgAnAAoKmCHlAwD4AgAAAA==.Rannï:BAAANQADCgQIBAABNQAECgkJJwAmAAIgAA==.Raskreia:BAABNQAECn8dAAMCAAoKhyIWBwAEAwACAAoKhyIWBwAEAwAHAAUKnxriWABIAQABNQAFFAUIDwAaABIfAA==.Rassina:BAAANQADCgEIAQAAAA==.Rawk:BAAANQAECgQIBgAAAA==.',
Re='Redeemly:BAABNQAECn8VAAIRAAoKOBmkhgC/AQARAAoKOBmkhgC/AQAAAA==.Redeyejedi:BAAANQAECggIBwAAAA==.Reeven:BAAANQAECggILQAAAQ==.Revokely:BAAANQAECgYIDgABNQAECgoKFQARADgZAA==.',
Rh='Rhcpmage:BAAANQADCggICgABNQAFFAcIHgAaAL0lAA==.Rhetegast:BAABNQAECn9AAAIoAAoKmxs3DQBbAgAoAAoKmxs3DQBbAgAAAA==.',
Ri='Rieloesh:BAAANQAECgMIAwAAAA==.Rike:BAABNQAECn86AAMRAAoKqhoqUgA2AgARAAoKvRgqUgA2AgAoAAYKVB7yHgDvAQAAAA==.Ristretto:BAAANQADCgYICwABNQAECgoKLAALAJ0dAA==.',
Ro='Roland:BAAANQADCgUJBwAAAA==.Rolandin:BAABNQAECn81AAIOAAoKvhNnMwBRAgAOAAoKvhNnMwBRAgAAAA==.',
Ru='Rukraga:BAAANQAECgQJBAAAAA==.',
Ry='Rylagosa:BAABNQAECn84AAMGAAoKnBkhBgALAwAGAAoKnBkhBgALAwAFAAIKGwvAJwAsAAAAAA==.Ryzesmidge:BAAANQAECgcJDAAAAA==.',
['Rê']='Rêdrum:BAAANQAECgYIBgABNQAECgoKOAALAI0bAA==.',
Sa='Salandria:BAABNQAECn8qAAQoAAkKLhqXGQAnAgAoAAkKLhqXGQAnAgAOAAYKEiMXXgD+AQARAAEKAABWnwE3AAAAAA==.Sarionian:BAABNQAECn8iAAMJAAYKPRHVOgApAQAJAAYKPRHVOgApAQAQAAUK7RHISwDzAAAAAA==.Sarvinblue:BAABNQAECn9RAAMEAAoKKyJ4EABBAwAEAAoKKyJ4EABBAwABAAgKhhTUaQDjAQAAAA==.',
Sc='Scopolamine:BAAANQAECgUIDwAAAA==.',
Se='Sevrin:BAABNQAECn8rAAIdAAkKzw6PSgDNAQAdAAkKzw6PSgDNAQAAAA==.Seymonty:BAABNQAECn8mAAMZAAoKNw4zDgBMAQAKAAoK8giwhQCGAQAZAAcKMA8zDgBMAQAAAA==.',
Sh='Shaeko:BAAANQADCggIHgAAAA==.Shazlulu:BAABNQAECn8nAAIEAAgK9hKPZgCCAQAEAAgK9hKPZgCCAQAAAA==.Shaznoir:BAABNQAECn89AAIDAAoKhQvwBgBrAQADAAoKhQvwBgBrAQAAAA==.Shilajit:BAAANQAECgMICAAAAA==.Shokz:BAAANQADCgMIAwABNQAECgMIBQAVAAAAAA==.',
Si='Simbelmynë:BAAANQADCgcIBwABNQAECgoKVAADAJwdAA==.',
Sk='Skip:BAAANQADCgcIBwAAAA==.Skøøma:BAAANQABCgIIBAAAAA==.',
Sl='Sloe:BAAANQAECgEIAQABNQAECgoKLwAOACgXAA==.',
Sm='Smokehunter:BAAANQADCgYIBgAAAA==.',
Sn='Snoop:BAAANQADCgYICgAAAA==.',
So='Solstîce:BAAANQADCgQIBAABNQAECgoKOAALAI0bAA==.Sonsu:BAAANQADCggICAABNQAECgcIIgAJAD0RAA==.',
Sp='Speedbeefbal:BAAANQAECgQIBAAAAA==.Speeddwrfbal:BAAANQADCggIJwAAAA==.Speedmeatbal:BAABNQAECn8iAAIBAAkKpgZLlQDeAAABAAkKpgZLlQDeAAAAAA==.Speedmeatlok:BAAANQAECgUICwAAAA==.Speedmonkbal:BAAANQAECgUICQAAAA==.Speedoe:BAAANQADCggIFgAAAA==.Spidêrs:BAAANQABCgQICAAAAA==.Sporkulous:BAABNQAECn8gAAIMAAgKRgj5uQCQAQAMAAgKRgj5uQCQAQAAAA==.',
Sq='Squal:BAABNQAECn8nAAIRAAoKixkKUAA8AgARAAoKixkKUAA8AgAAAA==.Squiggle:BAABNQAECn8uAAIoAAoKCByCDQBUAgAoAAoKCByCDQBUAgAAAA==.',
St='Steevii:BAAANQADCgMIAwAAAA==.Stewie:BAAANQAECgUIBQAAAA==.Striker:BAAANQADCgYIDwABNQAECgoKOgARAKoaAA==.',
Su='Sunshíne:BAABNQAECn8eAAMoAAgKWQ/8MgBKAQAoAAcKERH8MgBKAQARAAIKQgXWrgElAAAAAA==.',
Sy='Syver:BAABNQAECn8qAAICAAoKlhf5HAD6AQACAAoKlhf5HAD6AQAAAA==.',
['Sí']='Sírlancealot:BAAANQADCgMIBAAAAA==.',
Ta='Takeke:BAABNQAECn8wAAMdAAoKDx09EACdAgAdAAkKDx09EACdAgACAAUKUgv/iAD+AAAAAA==.Takeroux:BAAANQAECgMIBAAAAA==.Talandroz:BAABNQAECn8nAAMGAAkK6Ry9EQCPAgAGAAkK6Ry9EQCPAgAFAAIKTAtvNQBiAAAAAA==.Tanagra:BAAANQADCgIIAgABNQAECgoKOAAhAJMZAA==.Tankz:BAAANQADCgYIDQAAAA==.Tanner:BAACNQAFFH8NAAIMAAUK1hPHGQDFAAAMAAUK1hPHGQDFAAA1AAQKf0gAAgwACgpqHfY1AHICAAwACgpqHfY1AHICAAAA.',
Te='Tebo:BAAANQAECgEIAgAAAA==.Teboe:BAAANQADCgcICQABNQAECgEIAgAVAAAAAA==.Tedman:BAABNQAECn80AAMBAAkKChHxYwBaAQABAAgKfRDxYwBaAQAEAAcKfA3UtgD/AAAAAA==.Temel:BAABNQAECn9CAAMEAAoKoROhSwDkAQAEAAoKoROhSwDkAQABAAQKXAdI7QC8AAAAAA==.Teostra:BAABNQAECn8uAAMMAAoKESKNHgDGAgAMAAoKESKNHgDGAgAkAAEKyArLYwA3AAAAAA==.Terradan:BAAANQABCgQIBgAAAA==.Testoecles:BAAANQADCgcICwABNQAECgEIAgAVAAAAAA==.',
Th='Thadrack:BAAANQAECgcIEAABNQAECgoKIAAKAI4HAA==.Thalonstin:BAAANQADCggIHgAAAA==.Thaneold:BAAANQAECgQJCQABNQAECgoKNwAKAJMjAA==.Thassarian:BAABNQAECn8XAAIHAAYKLgwWZAAKAQAHAAYKLgwWZAAKAQAAAA==.Theodrid:BAACNQAFFH8TAAIoAAcKpBpPAgAVAgAoAAcKpBpPAgAVAgA1AAQKfzMAAigACgpUJEMIABoDACgACgpUJEMIABoDAAAA.Thunderstomp:BAAANQADCgIIAgAAAA==.',
Ti='Tinkerspell:BAAANQADCgYICwAAAA==.Tinkíe:BAABNQAECn8pAAIYAAkKQx89CwDRAgAYAAkKQx89CwDRAgAAAA==.Tirzahdozier:BAAANQAECgEIAgABNQAECgcIEgAVAAAAAA==.Tiwohnne:BAABNQAECn8eAAIhAAoKqxbgPAAgAgAhAAoKqxbgPAAgAgAAAA==.',
Tl='Tla:BAAANQADCgcIGgAAAA==.',
Tp='Tpaartos:BAAANQADCgIJAgABNQAECgoKLAAEAMkZAA==.',
Tr='Treat:BAABNQAECn9KAAIPAAoKnSPNAwBCAwAPAAoKnSPNAwBCAwAAAA==.Trippysheep:BAAANQAECgYIBwABNQAFFAkJKQAhAFMkAA==.Trippyshock:BAAANQAECggICAABNQAFFAkJKQAhAFMkAA==.Tristitia:BAAANQABCgYICgAAAA==.',
Tu='Turkeltin:BAACNQAFFH8OAAIlAAYKkhaqBgD+AAAlAAYKkhaqBgD+AAA1AAQKf0IAAiUACgrqJDsDAKYDACUACgrqJDsDAKYDAAAA.',
Tw='Twiggle:BAAANQADCgYIBgABNQAECgcIEgAVAAAAAA==.Twistedsquid:BAAANQABCgQIBAAAAA==.',
Ty='Tyamat:BAABNQAECn8dAAMmAAgK6xf7CQDcAQAmAAgK6xf7CQDcAQAhAAIKGwVUMwFUAAAAAA==.Tyche:BAAANQADCgYIDAAAAA==.Tyrinara:BAAANQADCggICAAAAA==.Tysbich:BAAANQAECgMIBAABNQAECgoKLwAOAFUjAA==.',
Ui='Uiewedaoez:BAABNQAECn8rAAIJAAoKVSUhCABDAwAJAAoKVSUhCABDAwAAAA==.',
Va='Vains:BAABNQAECn86AAIRAAoK9B2iTACvAgARAAoK9B2iTACvAgAAAA==.Valrith:BAAANQADCgcIGAAAAA==.',
Ve='Velexi:BAAANQABCggIEgAAAA==.Velin:BAAANQAECgQIBAAAAA==.Velody:BAAANQADCgQIAQAAAA==.Vendettuh:BAAANQADCgYIBgAAAA==.Veronica:BAABNQAECn8zAAINAAoKgQ9maQDhAQANAAoKgQ9maQDhAQAAAA==.Verren:BAABNQAECn8xAAIiAAoKgBBBHQC3AQAiAAoKgBBBHQC3AQAAAA==.Vesfor:BAAANQAECgEIAQABNQAECggIKAAMAKEZAA==.Vestus:BAAANQABCggIEgAAAA==.',
Vy='Vyrridyl:BAAANQAECgQICAAAAA==.',
Wa='Waddlez:BAAANQAECgcIBgAAAA==.Watermark:BAABNQAECn8oAAMEAAoKUgtGmwBCAQAEAAoKUgtGmwBCAQABAAUKpARhswChAAAAAA==.',
We='Weeblewobble:BAAANQAECgIIAgAAAA==.Weltamus:BAAANQADCgYIEAAAAA==.Weltazar:BAABNQAECn8qAAIBAAoKhRUGNgD9AQABAAoKhRUGNgD9AQAAAA==.Weltzilla:BAABNQAECn8rAAIMAAoKMxjMSgA6AgAMAAoKMxjMSgA6AgAAAA==.Westside:BAAANQAECgYIDQABNQAECggICwAVAAAAAA==.',
Wh='Whoosh:BAABNQAECn8sAAIdAAkKKiKDFgD5AgAdAAkKKiKDFgD5AgAAAA==.',
Wi='Wickët:BAABNQAECn8pAAMEAAkKESQwFgAfAwAEAAgK6iMwFgAfAwABAAcKex2EWQAWAgAAAA==.Wildtiger:BAABNQAECn84AAInAAoKQxN7EgChAQAnAAoKQxN7EgChAQAAAA==.Wisey:BAAANQAECgUIBAAAAA==.',
Wo='Wolfslied:BAAANQADCgQIBAABNQADCgQIBAAVAAAAAA==.',
Wu='Wulfenhide:BAABNQAECn88AAIfAAoKZiORAgAtAwAfAAoKZiORAgAtAwAAAA==.Wuntvor:BAAANQADCggICAAAAA==.',
Xa='Xalreth:BAABNQAECn8rAAIlAAoK7QitJwBcAQAlAAoK7QitJwBcAQAAAA==.Xaviana:BAAANQAECgUIBQAAAQ==.',
Ya='Yastypoo:BAABNQAECn8oAAMOAAoK6hD1VAAbAgAOAAoK6hD1VAAbAgARAAEKShnLlAE3AAAAAA==.',
Za='Zarieda:BAAANQAECgcIDQAAAA==.Zayrelia:BAACNQAFFH8XAAIJAAcKqxXuBQCyAQAJAAcKqxXuBQCyAQA1AAQKf1sAAwkACgqDIl8EAK8DAAkACgqDIl8EAK8DABAACAo3FZtQAJsBAAAA.',
Ze='Zelenor:BAAANQAECgEIAgABNQAECggIHQAmAOsXAA==.',
Zi='Zixarian:BAAANQABCgIIAgAAAA==.',
Zu='Zud:BAABNQAECn8gAAICAAkK1RvIOwAyAgACAAkK1RvIOwAyAgAAAA==.',
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
