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

local lookup = {'Shaman-Elemental','DeathKnight-Unholy','Warlock-Destruction','Shaman-Restoration','DeathKnight-Frost','Rogue-Subtlety','Druid-Restoration','Priest-Holy','DemonHunter-Vengeance','Hunter-BeastMastery','Mage-Arcane','Paladin-Holy','Priest-Shadow','Druid-Balance','Hunter-Survival','DemonHunter-Havoc','Warrior-Protection','Paladin-Retribution','Unknown-Unknown','Monk-Brewmaster','Monk-Windwalker','Monk-Mistweaver','Priest-Discipline','Mage-Frost','DeathKnight-Blood','Shaman-Enhancement','Rogue-Assassination','Rogue-Outlaw','Warlock-Demonology','Druid-Guardian','Evoker-Augmentation','Evoker-Preservation','Hunter-Marksmanship','DemonHunter-Devourer','Warrior-Arms','Warlock-Affliction','Druid-Feral','Paladin-Protection','Evoker-Devastation',}
local provider = {region='US',realm='KulTiras',name='US',type='weekly',zone=53,date='2026-11-10',data={Aa='Aarix:BAABNQAECn8lAAIBAAoKlAsXkgB3AQABAAoKlAsXkgB3AQAAAA==.',
Ae='Aendillan:BAAANQADCgUIBQAAAA==.',
Af='Affonasei:BAABNQAECn89AAICAAkKNQlnMgBJAQACAAkKNQlnMgBJAQAAAA==.',
Ag='Agkistrodon:BAAANQADCgcIDQABNQAECgoKVAADAJwdAA==.',
Ai='Aicaramba:BAABNQAECn87AAIEAAoKwyCbFgAcAwAEAAoKwyCbFgAcAwAAAA==.Aileen:BAAANQAECgQIEAAAAA==.',
Aj='Ajay:BAAANQAECgYIBgAAAA==.',
Ak='Akashi:BAABNQAECn8XAAIFAAkKOhLFQgC5AQAFAAkKOhLFQgC5AQABNQAFFAYIEQAGAO0NAA==.',
Al='Alacrodie:BAAANQADCgYIHAAAAA==.',
Am='Amoonsi:BAAANQAECgMIAwABNQAECgoKNwAHABoRAA==.Amordeyain:BAAANQAECggIDwAAAA==.',
An='Angrydisc:BAABNQAECn8gAAIIAAoKjgcUcABzAQAIAAoKjgcUcABzAQAAAA==.Angrytotems:BAAANQAECgUIBwABNQAECgoKIAAIAI4HAA==.Angyll:BAAANQADCgEIAQAAAA==.Annaborshen:BAAANQABCgIIAgAAAA==.Antoccino:BAAANQAECgYICwABNQAECgoKLAAJAJ0dAA==.',
Ar='Aragorno:BAABNQAECn8qAAIKAAoKEBSgSQApAgAKAAoKEBSgSQApAgAAAA==.Arcturen:BAABNQAECn8hAAIKAAgKVxfTdQC3AQAKAAgKVxfTdQC3AQAAAA==.Ardala:BAAANQAECggICAAAAA==.Arenthal:BAAANQAECgYIDgABNQAECgoKQwALAJsfAA==.Armonni:BAAANQABCgIIAgAAAA==.Arturaan:BAAANQADCgIIAgAAAA==.',
As='Ashalana:BAAANQADCgUIBQAAAA==.Asheby:BAAANQADCgMIAwABNQAECgoKLQAMAFEWAA==.Ashenisson:BAAANQADCgQIBAABNQAECggIIQABANQTAA==.Ashiera:BAABNQAECn8lAAILAAgKwAKVMwE2AQALAAgKwAKVMwE2AQAAAA==.Ashrai:BAAANQADCgEIAQABNQAECgoKVAADAJwdAA==.Astralmorph:BAAANQADCgYIBgAAAA==.',
At='Atomic:BAAANQAECgQIDAAAAA==.',
Au='Augenblick:BAAANQADCgIIAgAAAA==.Aurorée:BAAANQAECgYICwAAAA==.',
Av='Avattar:BAAANQABCgMIBQAAAA==.',
Aw='Aware:BAAANQADCgIIAgAAAA==.',
Az='Azylstrid:BAAANQADCgYIDAAAAA==.',
Ba='Baeu:BAAANQABCgUIBwAAAA==.Balentine:BAABNQAECn8fAAMIAAkK4gnjegBQAQAIAAkK4gnjegBQAQANAAIKLwGweQA0AAAAAA==.Banostraza:BAAANQAECgQIBQAAAA==.Baspir:BAABNQAECn88AAIOAAoKcRlfFwBGAgAOAAoKcRlfFwBGAgAAAA==.Bavette:BAAANQAECgcIEgABNQAECgoKNgAIANUfAA==.',
Be='Beeboop:BAAANQAECgUICQAAAA==.Belly:BAABNQAECn8rAAIPAAkKZh/3AwC5AgAPAAkKZh/3AwC5AgAAAA==.Belrae:BAABNQAECn8sAAIQAAkK7RANJQDNAQAQAAkK7RANJQDNAQAAAA==.Beltira:BAAANQADCggIDAABNQAECgoKQQARAOQWAA==.Benchfresh:BAABNQAECn8xAAISAAgKYSFbOgBuAgASAAgKYSFbOgBuAgAAAA==.Bendah:BAAANQAECgEIAQAAAA==.Bender:BAAANQADCgYIBgAAAA==.Bezieck:BAAANQAECgUIDAAAAA==.',
Bi='Bigfolks:BAAANQADCgUIBwAAAA==.Bigollock:BAAANQADCgYICwAAAA==.Bili:BAAANQAECgUIBQAAAA==.',
Bl='Blacktide:BAAANQADCgYIBgAAAA==.Bloodarrow:BAAANQADCgUIBwAAAA==.Bloodbound:BAAANQADCgYIBgAAAA==.',
Bo='Bockchi:BAAANQAECgQIBQAAAA==.Bonanas:BAAANQABCggICAAAAA==.Bonegavel:BAAANQABCgQIBgABNQABCgYIDAATAAAAAA==.Bookhuntress:BAAANQAECggIDgAAAA==.',
Br='Branex:BAAANQAECggICAAAAA==.Branpaw:BAAANQADCgQIAwAAAA==.Brewdeez:BAABNQAECn8sAAMUAAoKXBYtDABCAgAUAAkKphgtDABCAgAVAAEKWQaoXQAoAAAAAA==.Brewzen:BAAANQADCgYIBgAAAA==.Brewzer:BAABNQAECn84AAIWAAoKpBDcEQDUAQAWAAoKpBDcEQDUAQAAAA==.Brick:BAAANQADCgUIBQABNQAECgkJJQAXAAwUAA==.Brint:BAAANQADCgcIDAAAAA==.Bronad:BAACNQAFFH8eAAMYAAcKvSVQAQAtAQALAAUKqSaeEgBFAQAYAAMK+yNQAQAtAQA1AAQKf1oAAwsACgriJp8BAPMDAAsACgriJp8BAPMDABgAAgrzH+gxAFcAAAAA.Broomhandle:BAABNQAECn8vAAISAAkKZiBfQQDQAgASAAkKZiBfQQDQAgAAAA==.',
Bu='Bumbushka:BAAANQAECgcIEQAAAA==.Burinn:BAABNQAECn8hAAIKAAgKOBLehACTAQAKAAgKOBLehACTAQABNQAECgoKRgAIAC8aAA==.',
Ca='Caeus:BAABNQAECn8nAAQFAAoKDR0YKwBDAgAFAAkK2hsYKwBDAgACAAYKUhrURwD4AQAZAAQKsxorWADRAAAAAA==.Cajuil:BAAANQAECgcICwAAAA==.Cam:BAABNQAECn8VAAMLAAcKLiE5pgA1AgALAAcKLiE5pgA1AgAYAAMKrhRRKgCmAAAAAA==.Carolinabele:BAAANQADCggICAAAAA==.Cauud:BAAANQADCgYIEAAAAA==.',
Cb='Cbd:BAAANQADCgcIEwAAAA==.',
Ce='Celerious:BAAANQAECggIDwAAAA==.',
Ch='Chacruna:BAAANQAECgMIBgAAAA==.Chelan:BAABNQAECn9GAAMIAAoKLxpbIADJAgAIAAoKLxpbIADJAgANAAEKAAAUkQAZAAAAAA==.Chloelock:BAAANQABCgEJAQAAAA==.Chronicler:BAAANQADCgEIAQAAAA==.Chuntspeed:BAAANQAECgYICwAAAA==.Chuye:BAAANQAECgEIAQABNQAECgoKNgAIANUfAA==.',
Cl='Clambulance:BAABNQAECn84AAIKAAoKmhvUQwCfAgAKAAoKmhvUQwCfAgAAAA==.',
Cn='Cnova:BAABNQAECn8bAAMEAAcKLxaQmABKAQAEAAcKLxaQmABKAQAaAAUKQwW9KQCRAAABNQAECgoKJwASAIsZAA==.',
Co='Codythedead:BAACNQAFFH8aAAMCAAcKzxnJAQCiAQACAAcKzxnJAQCiAQAZAAEKAAAkQQAOAAA1AAQKf0oAAgIACgrNJLcFAJ4DAAIACgrNJLcFAJ4DAAAA.Coraf:BAACNQAFFH8eAAIEAAcKXh5NBABQAgAEAAcKXh5NBABQAgA1AAQKfzIAAgQACgpXJMoNAFMDAAQACgpXJMoNAFMDAAAA.Coyotl:BAABNQAECn8bAAIPAAgKow4VCABpAQAPAAgKow4VCABpAQAAAA==.',
Cr='Crazyazshamy:BAAANQAECggIEwAAAA==.',
Cu='Cuvier:BAAANQADCggJFgAAAA==.',
Da='Daltenton:BAABNQAECn8YAAIMAAkKHg3eUgC2AQAMAAkKHg3eUgC2AQABNQAECgoKJgAXADcOAA==.Danak:BAAANQADCgYIFwAAAA==.Darcia:BAAANQABCggIDQAAAA==.Dascrazy:BAAANQADCgQICQAAAA==.',
De='Deadlyfrosty:BAAANQADCgYIDgAAAA==.Deathmob:BAABNQAECn8tAAIZAAkKnhujKgBxAgAZAAkKnhujKgBxAgAAAA==.Deathsynth:BAAANQADCgQJBAABNQAECgkJKwALAP8cAA==.Debixie:BAACNQAFFH8GAAMbAAMKNhuJFAClAAAbAAIKNhuJFAClAAAGAAEKAACIKQAAAAA1AAQKfysABBsACgoGIUwKADoDABsACgqBH0wKADoDABwABgoEE+QNAGIBAAYABQpZGMVxADMBAAAA.Decisive:BAAANQADCgYIBgABNQAFFAkJJQAdAAgjAA==.Dejection:BAAANQABCgYIBwAAAA==.Demisi:BAAANQAECgYICgAAAA==.Demiurge:BAABNQAECn8vAAIOAAoKUh4EHwDSAgAOAAoKUh4EHwDSAgAAAA==.Despayr:BAAANQADCgYIDAAAAA==.',
Di='Diasundra:BAABNQAECn9BAAIKAAoKXyOeEAAGAwAKAAoKXyOeEAAGAwAAAA==.Dibbons:BAAANQAECgYIBwAAAA==.Divinatjin:BAAANQADCgYICQAAAA==.',
Do='Dollars:BAAANQAECggICwAAAA==.Dottingyou:BAACNQAFFH8eAAMdAAcKohG+DwAWAQAdAAYKYw2+DwAWAQADAAIK9hJEBwCCAAA1AAQKfzYAAx0ACgonI6oiAHoCAB0ACQrAI6oiAHoCAAMABgrZGC4YAKsBAAAA.',
Dr='Dracthyrbm:BAAANQAECgUIDAAAAA==.Dragonshide:BAAANQAECgIIAgABNQAECgoKLwADAF4gAA==.Dreegor:BAAANQABCgIIAgAAAA==.Dreepy:BAAANQAECgYIBQAAAA==.Drransom:BAAANQADCgYIEwAAAA==.Dryan:BAABNQAECn8uAAIeAAoKAhM9GQCmAQAeAAoKAhM9GQCmAQAAAA==.',
Du='Duo:BAABNQAECn9AAAIKAAoKrRc3TgCEAgAKAAoKrRc3TgCEAgAAAA==.Duragon:BAABNQAECn8mAAMfAAkKYwlEDQB7AQAfAAkKYwlEDQB7AQAgAAEKtQAAVgAZAAAAAA==.',
Ei='Eipwoc:BAAANQADCggIBwAAAA==.',
El='Eloreith:BAABNQAECn81AAMOAAoKuBpnHAAOAgAOAAoKuBpnHAAOAgAeAAUKvAjzPwC7AAAAAA==.',
Em='Emamagee:BAAANQADCgQIBgAAAA==.Emilia:BAABNQAECn8/AAIIAAoKiRh0OgA9AgAIAAoKiRh0OgA9AgAAAA==.',
En='Endressa:BAABNQAECn9FAAMXAAoKmByDAQD9AgAXAAoKmByDAQD9AgANAAcKxhCbQgAeAQAAAA==.',
Er='Eralendryn:BAAANQADCgEIAQAAAA==.Erelios:BAABNQAECn8oAAMMAAoKkAgFbwBUAQAMAAoKkAgFbwBUAQASAAIKwAUHsgEvAAAAAA==.',
Es='Eski:BAABNQAECn9XAAMcAAoK9iJ6AAAYAwAcAAoK9iJ6AAAYAwAbAAIK2wn3lABgAAAAAA==.Essaena:BAABNQAECn8oAAIZAAoKASFkIQCpAgAZAAoKASFkIQCpAgAAAA==.',
Eu='Eura:BAAANQADCgEIAQAAAA==.Eureka:BAEANQAECgcIEQAAAA==.',
Ev='Everlight:BAAANQADCggIEAABNQAECgoKVAADAJwdAA==.',
Ez='Ezrì:BAAANQADCgcIBwAAAA==.',
Fa='Faddeyshnek:BAABNQAECn8rAAIKAAkKvg8QfQClAQAKAAkKvg8QfQClAQAAAA==.Farmeador:BAAANQAECgEIAQAAAA==.Fastbeefball:BAAANQADCggIGQAAAA==.Fatgirljuice:BAACNQAFFH8VAAMKAAcK1yCgAAC5AgAKAAcK1yCgAAC5AgAhAAIKrg+tHACMAAA1AAQKfx8AAwoACQpDJr4FAFsDAAoACQpDJr4FAFsDACEAAQr0Gn1+AEoAAAAA.',
Fe='Felysambre:BAABNQAECn8wAAIiAAgKpAxcKAA/AQAiAAgKpAxcKAA/AQAAAA==.',
Fi='Fish:BAACNQAFFH8hAAINAAkKCyX2AADZAgANAAkKCyX2AADZAgA1AAQKfzkAAg0ACgrWJqAAAIsDAA0ACgrWJqAAAIsDAAAA.',
Fl='Flight:BAACNQAFFH8RAAMGAAYK7Q3hCwAyAQAGAAUK5QnhCwAyAQAbAAEKCx7SGwBXAAA1AAQKf0UAAwYACgoYIWkYAK8CAAYACgoCHWkYAK8CABsACQo1IdAbAKACAAAA.Floofee:BAAANQADCgQIBAAAAA==.',
Fo='Footfinger:BAAANQAECgIIAgAAAA==.Forsynth:BAABNQAECn8rAAILAAkK/xxFSQAkAgALAAkK/xxFSQAkAgAAAA==.Foxymeatbal:BAAANQADCggIDQAAAA==.',
Fu='Fubar:BAAANQAECgYICQAAAA==.',
Ga='Ganniy:BAAANQABCgEJAQAAAA==.',
Ge='Gewitt:BAAANQAECgQICAAAAA==.',
Gl='Glinda:BAAANQADCgYIEQAAAA==.',
Go='Gonjah:BAABNQAECn8jAAQIAAkKfhGwjwBnAQAIAAgKRRKwjwBnAQANAAUKyA0CRQAPAQAXAAEKbQMhHQAfAAAAAA==.',
Gr='Grabomage:BAABNQAECn8VAAMLAAcKGCNhCQF9AQALAAcKGCNhCQF9AQAYAAEKvxpwRAA6AAABNQAFFAcIHgAYAL0lAA==.Grabovoker:BAAANQADCgIIAgABNQAFFAcIHgAYAL0lAA==.Grazienne:BAAANQADCgYIFAAAAA==.Greavos:BAABNQAECn8zAAINAAoKGhe8EwAKAgANAAoKGhe8EwAKAgAAAA==.Griggus:BAABNQAECn82AAIjAAoKwBMqVgDpAQAjAAoKwBMqVgDpAQAAAA==.Grimgar:BAABNQAECn84AAMLAAoKuReZegCkAQALAAgK3haZegCkAQAYAAMKEBmZIgDXAAAAAA==.Grimmshady:BAAANQADCgQIBgAAAA==.Grumpsky:BAAANQADCgEIAQABNQAECgoKPgAEAA8SAA==.',
Gu='Gumbles:BAABNQAECn82AAMIAAoK1R/NGwDpAgAIAAoK1R/NGwDpAgANAAIKbQI7cABIAAAAAA==.Gurney:BAABNQAECn8ZAAMMAAoKWxgrMgCcAgAMAAoKWxgrMgCcAgASAAEK9gRm0wEcAAAAAA==.Guzprimal:BAAANQAECgEIAQAAAA==.',
Gw='Gwenory:BAAANQABCgQIBAAAAA==.',
Gy='Gying:BAAANQAECgcIDgAAAA==.',
Ha='Hanekawa:BAABNQAECn8mAAIMAAoKFR1YKwBpAgAMAAoKFR1YKwBpAgABNQAFFAQIDgALANAhAA==.Hannie:BAAANQADCgcIHAAAAA==.',
He='Headhúnter:BAAANQAECgYICAAAAA==.Heartsparx:BAABNQAECn8yAAIbAAoKthb5CwABAgAbAAoKthb5CwABAgAAAA==.Heatseeka:BAABNQAECn81AAMEAAoKMhJ7XgCGAQAEAAkKVhF7XgCGAQAaAAcKbQLzIwAdAQAAAA==.Heitan:BAAANQAECgUIDAABNQAECgoKPwAdAAAdAA==.Hexxiz:BAAANQAECgUIBgABNQAECgoKJwAeAK8jAA==.',
Hi='Hiphopinator:BAABNQAECn8xAAIRAAoKlyRqAgAkAwARAAoKlyRqAgAkAwAAAA==.',
Ho='Ho:BAAANQADCgQIBAAAAA==.Holyshock:BAABNQAECn9DAAMMAAoK0hykLAC0AgAMAAoK0hykLAC0AgASAAEKLgTooQEgAAAAAA==.Holyterror:BAAANQADCgYIGQAAAA==.',
Ia='Ianthe:BAAANQAECgcICwAAAA==.',
Ib='Iboga:BAABNQAECn8cAAMPAAcK1gd3CgANAQAPAAcK1gd3CgANAQAKAAIKwwGkRwFQAAAAAA==.Ibrahimovic:BAAANQAECgUICAAAAA==.',
Ig='Ignitecro:BAAANQABCgcIDwAAAA==.Igram:BAAANQAECgcIEwAAAA==.',
Il='Illumona:BAABNQAECn8lAAMJAAcKCgjtGAC8AAAJAAcKCgjtGAC8AAAQAAYKZQKYaQBsAAAAAA==.Iluz:BAAANQADCgMIAwAAAA==.',
In='Inafume:BAAANQAECgYIBgAAAA==.Inoxia:BAAANQAECgUIDQAAAA==.Intrépidice:BAAANQAECgQIDQAAAA==.',
Ix='Ixtabay:BAABNQAECn8nAAQkAAkKAiB7AgD3AgAkAAkKQx17AgD3AgADAAMK3BeIPADPAAAdAAMKvQ1BEgGmAAAAAA==.',
Ja='Jamurra:BAAANQAECgcIDQABNQAECgcIEQATAAAAAA==.Jaylinn:BAABNQAECn8sAAIKAAoKnQfmpAC8AQAKAAoKnQfmpAC8AQAAAA==.Jazzmend:BAAANQAECgQIBAAAAA==.',
Je='Jeanne:BAABNQAECn85AAIKAAkK/hoBPABPAgAKAAkK/hoBPABPAgABNQAECgoKVwAcAPYiAA==.Jellykins:BAABNQAECn8tAAIMAAoKURYrJgCFAgAMAAoKURYrJgCFAgAAAA==.',
Ji='Jimjamjuju:BAAANQAECgYICQAAAA==.Jimsonweed:BAABNQAECn8fAAIGAAoKVgjyWQCDAQAGAAoKVgjyWQCDAQAAAA==.',
Jo='Josie:BAABNQAECn84AAMXAAoK8BqFAQD8AgAXAAoK8BqFAQD8AgANAAEKqwaKYwAqAAAAAA==.Jozbirt:BAABNQAECn8mAAIlAAgKng6tEQDmAQAlAAgKng6tEQDmAQAAAA==.',
Ka='Kaeiria:BAAANQADCgQIBAAAAA==.Kael:BAABNQAECn8oAAMEAAgKaxgxbgBSAQAEAAYKoRQxbgBSAQABAAgKqgrvcQAdAQAAAA==.Kalaanri:BAABNQAECn8hAAMBAAgK1BPOawAtAQABAAcKMxHOawAtAQAEAAYK4xKNvQDvAAAAAA==.Kalyandra:BAABNQAECn8pAAIVAAcKJQwIPAA1AQAVAAcKJQwIPAA1AQAAAA==.Karlach:BAAANQADCgYIBwABNQAECgoKMgAbALYWAA==.Karumie:BAABNQAECn8+AAIEAAoKUxuyHADAAgAEAAoKUxuyHADAAgAAAA==.Kateera:BAAANQADCgQIBAAAAA==.',
Ke='Keden:BAAANQADCgYICgAAAA==.Kelesa:BAAANQAECgEIAQAAAA==.Keljaden:BAABNQAECn9CAAMjAAoK5CWzAgB7AwAjAAoK5CWzAgB7AwARAAIKbB3/OABNAAAAAA==.Kenner:BAAANQAECgIIAgAAAA==.',
Kh='Kheyra:BAABNQAECn8rAAIeAAgK+SC8CwCuAgAeAAgK+SC8CwCuAgABNQAECgoKVAADAJwdAA==.',
Ki='Kirsha:BAAANQAECgcIEQAAAA==.Kittybeef:BAAANQABCgIIAgAAAA==.Kiwiiga:BAAANQAECgIIAwAAAA==.',
Kn='Knoxxic:BAAANQADCgMIBQAAAA==.',
Ko='Koggs:BAAANQADCgEIAQABNQAECgoKQQARAOQWAA==.Kohnor:BAAANQADCgcIHQAAAA==.Koopalizard:BAABNQAECn8rAAIgAAoKsSGHBQAQAwAgAAoKsSGHBQAQAwAAAA==.Kopi:BAABNQAECn8sAAIJAAoKnR1ZBACJAgAJAAoKnR1ZBACJAgAAAA==.Korlatt:BAABNQAECn85AAMQAAkKxB5FHAC3AgAQAAkKgB5FHAC3AgAJAAQKTCAgGAAuAQAAAA==.Kowalabear:BAAANQAECgEIAQAAAA==.',
Ku='Kuaha:BAAANQADCgYIBgABNQADCgQIBAATAAAAAA==.Kupa:BAAANQADCgYJBwAAAA==.Kurom:BAAANQADCgcJDQAAAA==.Kurston:BAABNQAECn9FAAIHAAoK8yIuAwDIAwAHAAoK8yIuAwDIAwAAAA==.',
Ky='Ky:BAAANQADCgEIAQAAAA==.',
['Kã']='Kãtniss:BAAANQADCgUIFQAAAA==.',
La='Labella:BAAANQADCggIJQAAAA==.Lacia:BAAANQAECgQIBQABNQAECgoKIAAIAI4HAA==.Laih:BAABNQAECn8nAAIbAAoKDgpFFACEAQAbAAoKDgpFFACEAQAAAA==.Landsong:BAAANQADCgQIBAAAAA==.',
Le='Leyote:BAABNQAECn85AAIEAAoKLhFXPAAOAgAEAAoKLhFXPAAOAgAAAA==.',
Li='Liady:BAAANQADCgEJAQAAAA==.Lightshop:BAAANQADCgYICQAAAA==.Liirah:BAAANQADCgYICQAAAA==.Lilyfox:BAAANQAECgYIEAABNQAECgYIFwAFAC4MAA==.Lindithrial:BAAANQABCggICAAAAA==.Livingdead:BAAANQAECgIIAgAAAA==.',
Lo='Lorianne:BAAANQAECgQICAAAAA==.Lorraine:BAAANQADCggIDAAAAA==.Lowdangle:BAAANQADCgcIBwAAAA==.',
Lu='Lulz:BAAANQAECggICQAAAA==.Luucifur:BAAANQABCgMIAwAAAA==.',
Ma='Mackpumpkin:BAAANQAECgIIAgAAAA==.Macktheknife:BAAANQADCgQICAABNQAECgkJJwAkAAIgAA==.Madalyn:BAAANQADCgEIAQAAAA==.Maexna:BAAANQADCgIIAgAAAA==.Magdelyne:BAABNQAECn8aAAISAAoKMQjb6gBGAQASAAoKMQjb6gBGAQAAAA==.Magglés:BAAANQAECgIIAgAAAA==.Makklehaney:BAABNQAECn8WAAIBAAgKZwstfACvAQABAAgKZwstfACvAQAAAA==.Mallaah:BAAANQADCgUIBQAAAA==.Marovingian:BAABNQAECn8tAAIMAAkKviMAFgAmAwAMAAkKviMAFgAmAwAAAA==.Matthad:BAABNQAECn8oAAIEAAoKWhkIXQD4AQAEAAoKWhkIXQD4AQAAAA==.Mazìkene:BAAANQAECgQIAwABNQAECgoKOAAJAI0bAA==.',
Mc='Mcnastie:BAAANQAECgUIDwAAAA==.Mcsluts:BAAANQADCgYJCwAAAA==.',
Me='Melmirict:BAAANQADCgMJAwAAAA==.Merciala:BAABNQAECn9DAAQOAAoKsQ+uOgAwAQAOAAkKrAuuOgAwAQAHAAoKQQORQgDjAAAeAAQK7g64OgDEAAAAAA==.',
Mi='Milyyanna:BAAANQADCgcIHAAAAA==.Mindßender:BAAANQADCgcIBwAAAA==.Mirilla:BAABNQAECn8sAAMLAAoKAxSPTQAYAgALAAoKAxSPTQAYAgAYAAcKPAWUGQApAQAAAA==.',
Mo='Moddoxx:BAABNQAECn82AAQdAAoKkxmlNwAiAgAdAAoKpxalNwAiAgAkAAcKOxkHDABmAQADAAEKHA1FeAA1AAAAAA==.Moffa:BAAANQADCgMIAwAAAA==.Mohawk:BAABNQAECn8lAAIHAAoKlBhqGQBwAgAHAAoKlBhqGQBwAgAAAA==.Molen:BAAANQAECgEIAQAAAA==.Mommyjuice:BAAANQAECggIDgABNQAFFAcIFQAKANcgAA==.Monkeeh:BAAANQADCggIEQAAAA==.Monkle:BAABNQAECn80AAIVAAoKNR/gCgClAgAVAAoKNR/gCgClAgAAAA==.Monohan:BAAANQADCgUIBQABNQAECgkJLQAZAJ4bAA==.Moonpaw:BAAANQAECgIIAgAAAA==.Moonsii:BAABNQAECn83AAMHAAoKGhHIHQD2AQAHAAoKGhHIHQD2AQAOAAEKQgYWjAAoAAAAAA==.Mooroth:BAABNQAECn9BAAMRAAoK5BayDQDHAQARAAkKjhiyDQDHAQAjAAIKQQtrIQE0AAAAAA==.Morozko:BAAANQADCgQIBAAAAA==.',
Ms='Msasani:BAAANQADCgEIAQABNQAECgoKVAADAJwdAA==.',
Mu='Muddler:BAABNQAECn8UAAIDAAYKiQGiVACBAAADAAYKiQGiVACBAAAAAA==.Murinn:BAABNQAECn8xAAIKAAoKyw20YADtAQAKAAoKyw20YADtAQAAAA==.',
['Mà']='Màggles:BAAANQAECgYIEQAAAA==.',
Na='Nadd:BAABNQAECn8eAAIKAAcKBgb7xwAIAQAKAAcKBgb7xwAIAQAAAA==.Naledi:BAAANQADCggIDQAAAA==.Naralyn:BAABNQAECn81AAMaAAoKOBoZDQAxAgAaAAoKOBoZDQAxAgABAAUKYRG6tgAlAQAAAA==.',
Ne='Needlepax:BAAANQADCgEIAQAAAA==.Negrido:BAABNQAECn9BAAQdAAoKYhzvPwCSAgAdAAgKHx3vPwCSAgADAAMKiBubNQDsAAAkAAMKHhUbHACfAAAAAA==.Nei:BAABNQAECn85AAISAAkK5BScZQD0AQASAAkK5BScZQD0AQAAAA==.Neon:BAAANQADCgUICQAAAA==.',
Ni='Nikem:BAABNQAECn8rAAIOAAoKfhL6HwDqAQAOAAoKfhL6HwDqAQAAAA==.',
No='Noelle:BAABNQAECn8aAAISAAkKdhvShgCqAQASAAkKdhvShgCqAQAAAA==.Norelei:BAAANQAECgIIAgABNQAECgoKVAADAJwdAA==.Noriyuki:BAABNQAECn8eAAIVAAYKEgKGXwBiAAAVAAYKEgKGXwBiAAAAAA==.',
Ny='Nyxahlia:BAAANQADCggIDwABNQAECgoKPwAIAIkYAA==.',
Og='Oghom:BAAANQADCggICAAAAA==.Ogrekin:BAABNQAECn8UAAIaAAkKXA/QEgDRAQAaAAkKXA/QEgDRAQAAAA==.',
Ol='Olderon:BAABNQAECn8nAAIMAAoKJxX1PgAHAgAMAAoKJxX1PgAHAgAAAA==.Olrong:BAABNQAECn85AAIQAAoKlQqaLwCCAQAQAAoKlQqaLwCCAQAAAA==.Oluja:BAABNQAECn8YAAIEAAkKQwyxjwDyAAAEAAkKQwyxjwDyAAAAAA==.',
On='Onuris:BAAANQAECgMICAAAAA==.',
Oo='Oogiboogi:BAAANQAECgQIAwAAAA==.',
Op='Opacuslupus:BAAANQAECgQICQAAAA==.Oppressin:BAABNQAECn8vAAIVAAkK8RaTIAAoAgAVAAkK8RaTIAAoAgAAAA==.',
Os='Oshunn:BAABNQAECn8pAAILAAoK/RD+qQAuAgALAAoK/RD+qQAuAgAAAA==.Osroes:BAAANQAECgQIEgAAAA==.',
Ov='Overdoom:BAABNQAECn8sAAMCAAoKTBsmLwB0AgACAAoKTBsmLwB0AgAFAAUKrBORYAAjAQAAAA==.Ovji:BAAANQAECgUIBQAAAA==.Ovli:BAAANQAECgUICQAAAA==.',
Ow='Owner:BAAANQAECggICQAAAA==.',
Pa='Pacolock:BAAANQADCggICAABNQAECggIFgAMANcTAA==.Paladinjohn:BAACNQAFFH8dAAISAAcKBSKbBACsAQASAAcKBSKbBACsAQA1AAQKfzUAAhIACgrhJREQACUDABIACgrhJREQACUDAAAA.Palykat:BAABNQAECn8jAAISAAgKugVc5wD7AAASAAgKugVc5wD7AAAAAA==.Pandadeez:BAAANQADCgYIDgAAAA==.Pandather:BAAANQADCgEIAQAAAA==.Papiroflz:BAABNQAECn9CAAMBAAoKBiXGBQBNAwABAAoKBiXGBQBNAwAEAAUKexz3fwCMAQAAAA==.',
Pe='Pennywisé:BAABNQAECn8mAAIFAAkKSiAhGQDCAgAFAAkKSiAhGQDCAgAAAA==.',
Pl='Plaguegying:BAABNQAECn82AAIZAAoKtRZfGwAVAgAZAAoKtRZfGwAVAgABNQAECgcIDgATAAAAAA==.Ploofee:BAAANQAECgMIBQAAAA==.',
Pr='Preparedr:BAACNQAFFH87AAMbAAkKdiYBAAAMBAAbAAkKYCYBAAAMBAAGAAcKwSZ/AAC0AgA1AAQKfx8AAwYACgruJc8JANgCAAYACAo/Js8JANgCABsABwryJSElAGECAAAA.Progresz:BAAANQAECgMIAwAAAA==.',
Pu='Purebread:BAAANQAECgEIAQAAAA==.',
Py='Pykel:BAABNQAECn8+AAIOAAoKCwvSKgCTAQAOAAoKCwvSKgCTAQAAAA==.',
Qa='Qaren:BAAANQADCgYIEAAAAA==.',
Qu='Questionable:BAAANQADCgEIAQAAAA==.',
Ra='Raishun:BAAANQAECgEJAQAAAA==.Raizo:BAAANQAECgEIAQAAAA==.Rake:BAABNQAECn9AAAIlAAoKmCFtAwD8AgAlAAoKmCFtAwD8AgAAAA==.Rannï:BAAANQADCgQIBAABNQAECgkJJwAkAAIgAA==.Raskreia:BAABNQAECn8dAAMCAAoKhyJKBgAKAwACAAoKhyJKBgAKAwAFAAUKnxriWABIAQABNQAFFAQIDgALANAhAA==.Rassina:BAAANQADCgEIAQAAAA==.Rawk:BAAANQAECgQIBgAAAA==.',
Re='Redeemly:BAABNQAECn8VAAISAAoKOBnbeQDGAQASAAoKOBnbeQDGAQAAAA==.Redeyejedi:BAAANQAECggIBwAAAA==.Reeven:BAAANQAECggILQAAAQ==.Revokely:BAAANQAECgYIDgABNQAECgoKFQASADgZAA==.',
Rh='Rhcpmage:BAAANQADCggICgABNQAFFAcIHgAYAL0lAA==.Rhetegast:BAABNQAECn9AAAImAAoKmxv5CwBgAgAmAAoKmxv5CwBgAgAAAA==.',
Ri='Rieloesh:BAAANQAECgMIAwAAAA==.Rike:BAABNQAECn84AAMSAAoKqhpZTgAwAgASAAoKvRhZTgAwAgAmAAYKVB7yHgDvAQAAAA==.Ristretto:BAAANQADCgYICwABNQAECgoKLAAJAJ0dAA==.',
Ro='Roland:BAAANQADCgUJBwAAAA==.Rolandin:BAABNQAECn8zAAIMAAoKjxNlLwBTAgAMAAoKjxNlLwBTAgAAAA==.',
Ru='Rukraga:BAAANQAECgQJBAAAAA==.',
Ry='Rylagosa:BAABNQAECn83AAMgAAkK1xuzBgDmAgAgAAkK1xuzBgDmAgAnAAIKGwv5JQAsAAAAAA==.Ryzesmidge:BAAANQAECgcJDAAAAA==.',
['Rê']='Rêdrum:BAAANQAECgYIBgABNQAECgoKOAAJAI0bAA==.',
Sa='Salandria:BAABNQAECn8qAAQmAAkKLhqXGQAnAgAmAAkKLhqXGQAnAgAMAAYKEiMXXgD+AQASAAEKAABWnwE3AAAAAA==.Sarionian:BAABNQAECn8iAAMHAAYKPREpNgArAQAHAAYKPREpNgArAQAOAAUK7RERRwD0AAAAAA==.Sarvinblue:BAABNQAECn9RAAMEAAoKKyJ4EABBAwAEAAoKKyJ4EABBAwABAAgKhhTUaQDjAQAAAA==.',
Sc='Scopolamine:BAAANQAECgUIDwAAAA==.',
Se='Sevrin:BAABNQAECn8rAAIZAAkKzw6PSgDNAQAZAAkKzw6PSgDNAQAAAA==.Seymonty:BAABNQAECn8mAAMXAAoKNw4zDgBMAQAIAAoK8giwhQCGAQAXAAcKMA8zDgBMAQAAAA==.',
Sh='Shaeko:BAAANQADCggIHgAAAA==.Shazlulu:BAABNQAECn8gAAIEAAcKdRMDbABZAQAEAAcKdRMDbABZAQAAAA==.Shaznoir:BAABNQAECn89AAIDAAoKhQsKBgBwAQADAAoKhQsKBgBwAQAAAA==.Shilajit:BAAANQAECgMICAAAAA==.Shokz:BAAANQADCgMIAwABNQAECgMIBQATAAAAAA==.',
Si='Simbelmynë:BAAANQADCgcIBwABNQAECgoKVAADAJwdAA==.',
Sk='Skip:BAAANQADCgcIBwAAAA==.Skøøma:BAAANQABCgIIBAAAAA==.',
Sl='Sloe:BAAANQAECgEIAQABNQAECgoKLQAMAFEWAA==.',
Sm='Smokehunter:BAAANQADCgYIBgAAAA==.',
Sn='Snoop:BAAANQADCgYICgAAAA==.',
So='Solstîce:BAAANQADCgQIBAABNQAECgoKOAAJAI0bAA==.Sonsu:BAAANQADCggICAABNQAECgcIIgAHAD0RAA==.',
Sp='Speedbeefbal:BAAANQAECgQIBAAAAA==.Speeddwrfbal:BAAANQADCggIJwAAAA==.Speedmeatbal:BAABNQAECn8iAAIBAAkKpgZ8iwDeAAABAAkKpgZ8iwDeAAAAAA==.Speedmeatlok:BAAANQAECgUICwAAAA==.Speedmonkbal:BAAANQAECgUICQAAAA==.Speedoe:BAAANQADCggIGAAAAA==.Spidêrs:BAAANQABCgQICAAAAA==.Sporkulous:BAABNQAECn8gAAIKAAgKRgj5uQCQAQAKAAgKRgj5uQCQAQAAAA==.',
Sq='Squal:BAABNQAECn8nAAISAAoKixmkRgBGAgASAAoKixmkRgBGAgAAAA==.Squiggle:BAABNQAECn8tAAImAAkKKRy0EAAKAgAmAAkKKRy0EAAKAgAAAA==.',
St='Steevii:BAAANQADCgMIAwAAAA==.Stewie:BAAANQAECgUIBQAAAA==.Striker:BAAANQADCgYIDwABNQAECgoKOAASAKoaAA==.',
Su='Sunshíne:BAABNQAECn8dAAMmAAcKERH8MgBKAQAmAAcKERH8MgBKAQASAAEKwgNK1AEbAAAAAA==.',
Sy='Syver:BAABNQAECn8jAAICAAoKWRcUHQDnAQACAAoKWRcUHQDnAQAAAA==.',
['Sí']='Sírlancealot:BAAANQADCgMIBAAAAA==.',
Ta='Takeke:BAABNQAECn8vAAMZAAoKDx0YDwCjAgAZAAkKDx0YDwCjAgACAAUKUgv/iAD+AAAAAA==.Takeroux:BAAANQAECgEIAQAAAA==.Talandroz:BAABNQAECn8nAAMgAAkK6RzrDAA4AgAgAAkK6RzrDAA4AgAnAAIKTAtvNQBiAAAAAA==.Tanagra:BAAANQADCgIIAgABNQAECgoKNgAdAJMZAA==.Tankz:BAAANQADCgYIDgAAAA==.Tanner:BAACNQAFFH8NAAIKAAUK1hMlFwDIAAAKAAUK1hMlFwDIAAA1AAQKf0gAAgoACgpqHdguAHkCAAoACgpqHdguAHkCAAAA.',
Te='Tebo:BAAANQAECgEIAgAAAA==.Teboe:BAAANQADCgcICQABNQAECgEIAgATAAAAAA==.Tedman:BAABNQAECn80AAMBAAkKChGqWwBcAQABAAgKfRCqWwBcAQAEAAcKfA3UtgD/AAAAAA==.Temel:BAABNQAECn8+AAMEAAoKDxK/SgDQAQAEAAoKDxK/SgDQAQABAAQKXAdI7QC8AAAAAA==.Teostra:BAABNQAECn8uAAMKAAoKESLmGQDRAgAKAAoKESLmGQDRAgAhAAEKyAphXwA3AAAAAA==.Terradan:BAAANQADCgEIAQAAAA==.Testoecles:BAAANQADCgcICwABNQAECgEIAgATAAAAAA==.',
Th='Thadrack:BAAANQAECgcIEAABNQAECgoKIAAIAI4HAA==.Thalonstin:BAAANQADCggIHgAAAA==.Thaneold:BAAANQAECgQJCQABNQAECgoKNwAIAJMjAA==.Thassarian:BAABNQAECn8XAAIFAAYKLgyZXQAKAQAFAAYKLgyZXQAKAQAAAA==.Theodrid:BAACNQAFFH8TAAImAAcKpBpPAgAVAgAmAAcKpBpPAgAVAgA1AAQKfzMAAiYACgpUJEMIABoDACYACgpUJEMIABoDAAAA.Thunderstomp:BAAANQADCgIIAgAAAA==.',
Ti='Tinkerspell:BAAANQADCgYICwAAAA==.Tinkíe:BAABNQAECn8pAAIWAAkKQx89CwDRAgAWAAkKQx89CwDRAgAAAA==.Tirzahdozier:BAAANQAECgEIAgABNQAECgcIEQATAAAAAA==.Tiwohnne:BAAANQAECgUIEAAAAA==.',
Tl='Tla:BAAANQADCgcIGgAAAA==.',
Tp='Tpaartos:BAAANQADCgIJAgABNQAECgoKKAAEAFoZAA==.',
Tr='Treat:BAABNQAECn9BAAINAAoK7yKpBQARAwANAAoK7yKpBQARAwAAAA==.Trippysheep:BAAANQAECgYIBwABNQAFFAkJJQAdAAgjAA==.Trippyshock:BAAANQAECggICAABNQAFFAkJJQAdAAgjAA==.Tristitia:BAAANQABCgYICgAAAA==.',
Tu='Turkeltin:BAACNQAFFH8OAAIiAAYKkhbLBQAHAQAiAAYKkhbLBQAHAQA1AAQKfzkAAiIACgrqJDsDAKYDACIACgrqJDsDAKYDAAAA.',
Tw='Twiggle:BAAANQADCgYIBgABNQAECgcIEQATAAAAAA==.Twistedsquid:BAAANQABCgQIBAAAAA==.',
Ty='Tyamat:BAABNQAECn8cAAMkAAcKxhf7CQDcAQAkAAcKxhf7CQDcAQAdAAIKGwVUMwFUAAAAAA==.Tyche:BAAANQADCgYIDAAAAA==.Tyrinara:BAAANQADCggICAAAAA==.Tysbich:BAAANQAECgIIAgABNQAECgkJLQAMAL4jAA==.',
Ui='Uiewedaoez:BAABNQAECn8rAAIHAAoKVSXQBwBMAwAHAAoKVSXQBwBMAwAAAA==.',
Va='Vains:BAABNQAECn86AAISAAoK9B2iTACvAgASAAoK9B2iTACvAgAAAA==.Valrith:BAAANQADCgcIGQAAAA==.',
Ve='Velexi:BAAANQABCggIEgAAAA==.Velin:BAAANQAECgQIBAAAAA==.Velody:BAAANQADCgQIAQAAAA==.Vendettuh:BAAANQADCgYIBgAAAA==.Veronica:BAABNQAECn8xAAILAAoKgQ9oYgDhAQALAAoKgQ9oYgDhAQAAAA==.Verren:BAABNQAECn8vAAIeAAkKihFBHQC3AQAeAAkKihFBHQC3AQAAAA==.Vesfor:BAAANQAECgEIAQABNQAECggIIQAKAFcXAA==.Vestus:BAAANQABCggIEAAAAA==.',
Vy='Vyrridyl:BAAANQAECgQICAAAAA==.',
Wa='Waddlez:BAAANQAECgcIBgAAAA==.Watermark:BAABNQAECn8oAAMEAAoKUgtGmwBCAQAEAAoKUgtGmwBCAQABAAUKpAT1qAChAAAAAA==.',
We='Weeblewobble:BAAANQAECgIIAgAAAA==.Weltamus:BAAANQADCgYIEAAAAA==.Weltazar:BAABNQAECn8nAAIBAAoKmROwNQDpAQABAAoKmROwNQDpAQAAAA==.Weltzilla:BAABNQAECn8pAAIKAAoKFRc7TAAiAgAKAAoKFRc7TAAiAgAAAA==.Westside:BAAANQAECgYIDQABNQAECggICwATAAAAAA==.',
Wh='Whoosh:BAABNQAECn8sAAIZAAkKKiKDFgD5AgAZAAkKKiKDFgD5AgAAAA==.',
Wi='Wickët:BAABNQAECn8pAAMEAAkKESQwFgAfAwAEAAgK6iMwFgAfAwABAAcKex2EWQAWAgAAAA==.Wildtiger:BAABNQAECn83AAIlAAoKHROAEACfAQAlAAoKHROAEACfAQAAAA==.Wisey:BAAANQAECgUIBAAAAA==.',
Wo='Wolfslied:BAAANQADCgQIBAABNQADCgQIBAATAAAAAA==.',
Wu='Wulfenhide:BAABNQAECn8zAAIbAAoK+iKfAgAjAwAbAAoK+iKfAgAjAwAAAA==.Wuntvor:BAAANQADCggICQAAAA==.',
Xa='Xalreth:BAABNQAECn8pAAIiAAkKIgl5KgAuAQAiAAkKIgl5KgAuAQAAAA==.Xaviana:BAAANQAECgUIBQAAAQ==.',
Ya='Yastypoo:BAABNQAECn8oAAMMAAoK6hD1VAAbAgAMAAoK6hD1VAAbAgASAAEKShkqggE4AAAAAA==.',
Za='Zarieda:BAAANQAECgcIDQAAAA==.Zayrelia:BAACNQAFFH8XAAIHAAcKqxUUBQC0AQAHAAcKqxUUBQC0AQA1AAQKf1IAAwcACgoiIkIHAFoDAAcACgoiIkIHAFoDAA4ACAo3FZtQAJsBAAAA.',
Ze='Zelenor:BAAANQAECgEIAgABNQAECgcIHAAkAMYXAA==.',
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
