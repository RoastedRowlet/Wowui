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

local lookup = {'Shaman-Elemental','DeathKnight-Unholy','Warlock-Destruction','Shaman-Restoration','DeathKnight-Frost','Rogue-Subtlety','Druid-Restoration','Priest-Holy','DemonHunter-Vengeance','Hunter-BeastMastery','Mage-Arcane','Paladin-Holy','Priest-Shadow','Druid-Balance','Hunter-Survival','DemonHunter-Havoc','Warrior-Protection','Paladin-Retribution','Monk-Brewmaster','Monk-Windwalker','Monk-Mistweaver','Priest-Discipline','Mage-Frost','DeathKnight-Blood','Unknown-Unknown','Shaman-Enhancement','Rogue-Assassination','Rogue-Outlaw','Warlock-Demonology','Druid-Guardian','Evoker-Augmentation','Evoker-Preservation','Hunter-Marksmanship','DemonHunter-Devourer','Warrior-Arms','Warlock-Affliction','Druid-Feral','Paladin-Protection','Evoker-Devastation',}
local provider = {region='US',realm='KulTiras',name='US',type='weekly',zone=53,date='2026-11-03',data={Aa='Aarix:BAABNQAECn8hAAIBAAgKrgoXkgB3AQABAAgKrgoXkgB3AQAAAA==.',
Ae='Aendillan:BAAANQADCgUIBQAAAA==.',
Af='Affonasei:BAABNQAECn81AAICAAgK5Ai3OAALAQACAAgK5Ai3OAALAQAAAA==.',
Ag='Agkistrodon:BAAANQADCgcIDQABNQAECgoKUAADAJwdAA==.',
Ai='Aicaramba:BAABNQAECn8yAAIEAAoKwyCbFgAcAwAEAAoKwyCbFgAcAwAAAA==.Aileen:BAAANQAECgQIEwAAAA==.',
Aj='Ajay:BAAANQAECgYIBgAAAA==.',
Ak='Akashi:BAABNQAECn8XAAIFAAkKOhLFQgC5AQAFAAkKOhLFQgC5AQABNQAFFAUIEAAGABQQAA==.',
Al='Alacrodie:BAAANQADCgYIHAAAAA==.',
Am='Amoonsi:BAAANQAECgMIAwABNQAECgoKMgAHABoRAA==.Amordeyain:BAAANQAECggIEAAAAA==.',
An='Angrydisc:BAABNQAECn8gAAIIAAoKjgf5YgB7AQAIAAoKjgf5YgB7AQAAAA==.Angrytotems:BAAANQAECgUIBwABNQAECgoKIAAIAI4HAA==.Angyll:BAAANQABCggIGwAAAA==.Annaborshen:BAAANQADCgEIAQAAAA==.Antoccino:BAAANQAECgYICwABNQAECggIKQAJAMQdAA==.',
Ar='Aragorno:BAABNQAECn8mAAIKAAkKkBT0VQDdAQAKAAkKkBT0VQDdAQAAAA==.Arcturen:BAABNQAECn8aAAIKAAcKHhdjhwBhAQAKAAcKHhdjhwBhAQAAAA==.Ardala:BAAANQAECggICQAAAA==.Arenthal:BAAANQAECgYIDgABNQAECgoKQwALAJsfAA==.Armonni:BAAANQADCgEIAwAAAA==.Arturaan:BAAANQADCgIIAgAAAA==.',
As='Ashalana:BAAANQADCgUIBQAAAA==.Asheby:BAAANQADCgMIBAABNQAECggIKgAMAOkVAA==.Ashenisson:BAAANQADCgQIBAABNQAECgcIGgAEAP4WAA==.Ashiera:BAABNQAECn8lAAILAAgKwAKVMwE2AQALAAgKwAKVMwE2AQAAAA==.Ashrai:BAAANQADCgEIAQABNQAECgoKUAADAJwdAA==.Astralmorph:BAAANQADCgYIBgAAAA==.',
At='Atomic:BAAANQAECgQIDAAAAA==.',
Au='Augenblick:BAAANQADCgIIAgAAAA==.Aurorée:BAAANQAECgYIDQAAAA==.',
Av='Avattar:BAAANQABCgMIBQAAAA==.',
Aw='Aware:BAAANQADCgIIAgAAAA==.Awopaho:BAAANQADCgEIAQAAAA==.',
Az='Azylstrid:BAAANQADCgYIDAAAAA==.',
Ba='Baeu:BAAANQADCgEIAQAAAA==.Balentine:BAABNQAECn8fAAMIAAkK4gnqbQBWAQAIAAkK4gnqbQBWAQANAAIKLwGweQA0AAAAAA==.Banostraza:BAAANQAECgQIBQAAAA==.Baspir:BAABNQAECn88AAIOAAoKcRlZFABMAgAOAAoKcRlZFABMAgAAAA==.Bavette:BAAANQAECggIDQABNQAECgoKNgAIANUfAA==.',
Be='Beeboop:BAAANQAECgUICwAAAA==.Belly:BAABNQAECn8rAAIPAAkKZh/3AwC5AgAPAAkKZh/3AwC5AgAAAA==.Belrae:BAABNQAECn8kAAIQAAkKKBCMIgC6AQAQAAkKKBCMIgC6AQAAAA==.Beltira:BAAANQADCggICAABNQAECgoKOgARAKkVAA==.Benchfresh:BAABNQAECn8rAAISAAgKxh9LPwA8AgASAAgKxh9LPwA8AgAAAA==.Bendah:BAAANQAECgEIAQAAAA==.Bender:BAAANQADCgYIBgAAAA==.Bezieck:BAAANQAECgYICQAAAA==.',
Bi='Bigfolks:BAAANQADCgUIBwAAAA==.Bigollock:BAAANQADCgYIDQAAAA==.Bili:BAAANQAECgYIBwAAAA==.',
Bl='Blacktide:BAAANQADCgYIBgAAAA==.Bloodarrow:BAAANQADCgUICgAAAA==.Bloodbound:BAAANQADCgYIBgAAAA==.',
Bo='Bockchi:BAAANQAECgQIBQAAAA==.Bonanas:BAAANQADCgEIAgAAAA==.Bonegavel:BAAANQADCgEIAQAAAA==.Bookhuntress:BAAANQAECgYIBgAAAA==.',
Br='Branex:BAAANQAECggICAAAAA==.Branpaw:BAAANQADCgQIBAAAAA==.Brewdeez:BAABNQAECn8sAAMTAAoKXBYtDABCAgATAAkKphgtDABCAgAUAAEKWQbnVgApAAAAAA==.Brewzen:BAAANQADCgYIBwAAAA==.Brewzer:BAABNQAECn84AAIVAAoKpBCIDwDaAQAVAAoKpBCIDwDaAQAAAA==.Brick:BAAANQADCgUIBAABNQAECgkJJQAWAAwUAA==.Brint:BAAANQADCgcIDAAAAA==.Bronad:BAACNQAFFH8dAAMLAAYK0yUvDgBLAQALAAUKqSYvDgBLAQAXAAIKRyPMAwDCAAA1AAQKf1kAAwsACgriJp8BAPMDAAsACgriJp8BAPMDABcAAgrzH/ssAFcAAAAA.Broomhandle:BAABNQAECn8sAAISAAgKNSFfQQDQAgASAAgKNSFfQQDQAgAAAA==.',
Bu='Bumbushka:BAAANQAECgcIDwAAAA==.Burinn:BAABNQAECn8aAAIKAAcKxhNLiwBYAQAKAAcKxhNLiwBYAQABNQAECgkJPgAIAH4aAA==.Butche:BAAANQAECgEIAwAAAA==.',
Ca='Caeus:BAABNQAECn8mAAQFAAkKFR0YKwBDAgAFAAgKsBsYKwBDAgACAAYKUhrURwD4AQAYAAQKsxo1UADUAAAAAA==.Cajuil:BAAANQAECgcICAAAAA==.Cam:BAABNQAECn8VAAMLAAcKLiE5pgA1AgALAAcKLiE5pgA1AgAXAAMKrhRRKgCmAAAAAA==.Carolinabele:BAAANQADCggICQAAAA==.Cauud:BAAANQADCgYIFQAAAA==.',
Cb='Cbd:BAAANQADCgcIFAAAAA==.',
Ce='Celerious:BAAANQAECggIDgAAAA==.',
Ch='Chacruna:BAAANQAECgMIBgAAAA==.Chelan:BAABNQAECn8+AAMIAAkKfhq4JgCBAgAIAAkKfhq4JgCBAgANAAEKAAAUkQAZAAAAAA==.Chloelock:BAAANQADCgEIAQAAAA==.Chronicler:BAAANQADCgEIAQAAAA==.Chuntspeed:BAAANQAECgYIDAAAAA==.Chuye:BAAANQAECgEIAgABNQAECgoKNgAIANUfAA==.',
Cl='Clambulance:BAABNQAECn82AAIKAAoKMhvUQwCfAgAKAAoKMhvUQwCfAgAAAA==.Clotz:BAAANQADCgEIAQABNQAECgMIBQAZAAAAAA==.',
Cn='Cnova:BAABNQAECn8bAAMEAAcKLxaQmABKAQAEAAcKLxaQmABKAQAaAAUKOgV9MQAxAAABNQAECgoKGwASAH0XAA==.',
Co='Codythedead:BAACNQAFFH8ZAAMCAAYKoB1mAgBTAQACAAYKoB1mAgBTAQAYAAEKAAAkQQAOAAA1AAQKf0kAAgIACgrNJLcFAJ4DAAIACgrNJLcFAJ4DAAAA.Coraf:BAACNQAFFH8dAAIEAAYKRh40BQDzAQAEAAYKRh40BQDzAQA1AAQKfzEAAgQACgpXJMoNAFMDAAQACgpXJMoNAFMDAAAA.Coyotl:BAABNQAECn8bAAIPAAgKow72BgB0AQAPAAgKow72BgB0AQAAAA==.',
Cr='Crazyazshamy:BAAANQAECggIDwAAAA==.',
Cu='Cuvier:BAAANQADCggJGAAAAA==.',
Da='Daltenton:BAAANQAECgcIEAABNQAECgoKJgAWADcOAA==.Daminion:BAAANQADCgEIAQABNQAECggIKgAMAOIjAA==.Danak:BAAANQADCgYIFwAAAA==.Dascrazy:BAAANQADCgQICAAAAA==.Daynaa:BAAANQADCgEIAQABNQAECgcIEQAZAAAAAA==.',
De='Deadlyfrosty:BAAANQADCgYIEgAAAA==.Deathmob:BAABNQAECn8tAAIYAAkKnhujKgBxAgAYAAkKnhujKgBxAgAAAA==.Deathsynth:BAAANQADCgQJBAABNQAECggIKAALAJAdAA==.Debixie:BAACNQAFFH8GAAMbAAMKNhuJFAClAAAbAAIKNhuJFAClAAAGAAEKAAAbJQAAAAA1AAQKfyoABBsACgoGIUwKADoDABsACgqBH0wKADoDABwABgoEE+QNAGIBAAYABAq+G9JyAPgAAAAA.Decisive:BAAANQADCgYIBgABNQAFFAkJIQAdAAgjAA==.Dejection:BAAANQADCgEIAQAAAA==.Demisi:BAAANQAECgYICgAAAA==.Demiurge:BAABNQAECn8rAAIOAAoKQhwEHwDSAgAOAAoKQhwEHwDSAgABNQAECgoKNAAdAFIdAA==.Despayr:BAAANQADCgYIBgAAAA==.',
Di='Diasundra:BAABNQAECn9BAAIKAAoKXyMWDAAUAwAKAAoKXyMWDAAUAwAAAA==.Dibbons:BAAANQAECgYIBwAAAA==.Divinatjin:BAAANQADCgYICQAAAA==.',
Do='Doafarm:BAAANQAECgEIAQAAAA==.Dollars:BAAANQAECggIDQAAAA==.Dottingyou:BAACNQAFFH8dAAMDAAYKJxJlBgCDAAAdAAUKqQyfFgDEAAADAAIK9hJlBgCDAAA1AAQKfzMAAx0ACgonI2IgAGwCAB0ACQrAI2IgAGwCAAMABgrZGC4YAKsBAAAA.Doubleedged:BAAANQAECgEIAQAAAA==.',
Dr='Dracthyrbm:BAAANQAECgYICQAAAA==.Dragonshide:BAAANQAECgQIBAABNQAECgoKLAADAOMfAA==.Dreepy:BAAANQAECgYIBQAAAA==.Drransom:BAAANQADCgYIEwAAAA==.Dryan:BAABNQAECn8rAAIeAAgK3BUsGwDKAQAeAAgK3BUsGwDKAQAAAA==.',
Du='Duo:BAABNQAECn86AAIKAAoKrRcmQAAdAgAKAAoKrRcmQAAdAgAAAA==.Duragon:BAABNQAECn8mAAMfAAkKYwlEDQB7AQAfAAkKYwlEDQB7AQAgAAEKtQAAVgAZAAAAAA==.',
Ei='Eipwoc:BAAANQADCggIBwAAAA==.',
El='Eloreith:BAABNQAECn81AAMOAAoKuBrMGAAUAgAOAAoKuBrMGAAUAgAeAAUKvAjzPwC7AAAAAA==.',
Em='Emamagee:BAAANQADCgQIBgAAAA==.Emilia:BAABNQAECn82AAIIAAkKuRgqRgBUAgAIAAkKuRgqRgBUAgAAAA==.',
En='Endressa:BAABNQAECn9AAAMWAAoKhxyYAQDHAgAWAAoKhxyYAQDHAgANAAcKxhCbQgAeAQAAAA==.',
Er='Eralendryn:BAAANQADCgEIAQAAAA==.Erelios:BAABNQAECn8nAAMMAAkKfgiWcgAsAQAMAAkKfgiWcgAsAQASAAIKwAUHsgEvAAAAAA==.',
Es='Eski:BAABNQAECn9KAAMcAAoKXSI0AQCIAwAcAAoKXSI0AQCIAwAbAAIK2wn3lABgAAAAAA==.Essaena:BAABNQAECn8kAAIYAAgKNSFkIQCpAgAYAAgKNSFkIQCpAgAAAA==.',
Eu='Eura:BAAANQADCgEIAQAAAA==.Eureka:BAEANQAECgcIEQAAAA==.',
Ev='Everlight:BAAANQADCggIEAABNQAECgoKUAADAJwdAA==.',
Ex='Exigence:BAAANQADCgEIAgAAAA==.',
Ez='Ezrì:BAAANQADCgcIBwAAAA==.',
Fa='Faddeyshnek:BAABNQAECn8rAAIKAAkKvg/tbgCaAQAKAAkKvg/tbgCaAQAAAA==.Farmeador:BAAANQAECgEIAQAAAA==.Fastbeefball:BAAANQADCggIGAAAAA==.Fatgirljuice:BAACNQAFFH8VAAMKAAcK1yCgAAC5AgAKAAcK1yCgAAC5AgAhAAIKrg+tHACMAAA1AAQKfxcAAwoACQpDJisEAGEDAAoACQpDJisEAGEDACEAAQr0Gn1+AEoAAAAA.',
Fe='Felysambre:BAABNQAECn8pAAIiAAgKGgxcJQA3AQAiAAgKGgxcJQA3AQAAAA==.',
Fi='Fish:BAACNQAFFH8fAAINAAkKfyT2AADZAgANAAkKfyT2AADZAgA1AAQKfzkAAg0ACgrWJnYAAI0DAA0ACgrWJnYAAI0DAAAA.',
Fl='Flight:BAACNQAFFH8QAAMGAAUKFBAtEADkAAAGAAQKbAstEADkAAAbAAEKCx7SGwBXAAA1AAQKf0QAAwYACgoYIUUVAK0CAAYACgoCHUUVAK0CABsACQo1IdAbAKACAAAA.Floofee:BAAANQADCgQIBgAAAA==.',
Fo='Footfinger:BAAANQAECgIIAgAAAA==.Forsynth:BAABNQAECn8oAAILAAgKkB2rWgDbAQALAAgKkB2rWgDbAQAAAA==.Foxymeatbal:BAAANQADCggIDQAAAA==.',
Fu='Fubar:BAAANQAECgYICgAAAA==.',
Ga='Ganniy:BAAANQADCgEIAgAAAA==.',
Ge='Gewitt:BAAANQAECgQICAAAAA==.',
Gl='Glinda:BAAANQADCgYIEQAAAA==.',
Go='Gonjah:BAABNQAECn8hAAQIAAkKfhGwjwBnAQAIAAgKRRKwjwBnAQANAAUKyA0CRQAPAQAWAAEKbQP7GQAfAAAAAA==.',
Gr='Grabomage:BAABNQAECn8UAAMLAAcKGCNhCQF9AQALAAcKGCNhCQF9AQAXAAEKvxpwRAA6AAABNQAFFAYIHQALANMlAA==.Grabovoker:BAAANQADCgIIAgABNQAFFAYIHQALANMlAA==.Grazienne:BAAANQADCgYIFAAAAA==.Greavos:BAABNQAECn8wAAINAAgK7Rn8GACbAQANAAgK7Rn8GACbAQAAAA==.Griggus:BAABNQAECn8vAAIjAAoKwBNvSwDsAQAjAAoKwBNvSwDsAQAAAA==.Grimgar:BAABNQAECn81AAMXAAgKBxmZIgDXAAALAAYKZhghrAAhAQAXAAMKEBmZIgDXAAAAAA==.Grimmshady:BAAANQADCgQIBwAAAA==.Grumpsky:BAAANQADCgEIAQABNQAECggINQAEABkUAA==.',
Gu='Gumbles:BAABNQAECn82AAMIAAoK1R+sFgD1AgAIAAoK1R+sFgD1AgANAAIKbQI7cABIAAAAAA==.Gurney:BAABNQAECn8ZAAMMAAoKWxgrMgCcAgAMAAoKWxgrMgCcAgASAAEK9gRm0wEcAAAAAA==.Guzprimal:BAAANQAECgEIAQAAAA==.',
Gw='Gwenory:BAAANQADCgEIAQAAAA==.',
Gy='Gying:BAAANQAECgYIBwAAAA==.',
Ha='Hanekawa:BAABNQAECn8iAAIMAAoKLRzSLQA7AgAMAAoKLRzSLQA7AgABNQAFFAQICgALANAhAA==.Hannie:BAAANQADCgcIHAAAAA==.',
He='Headhúnter:BAAANQAECgYICAAAAA==.Heartsparx:BAABNQAECn8xAAIbAAoK6BWKCwDxAQAbAAoK6BWKCwDxAQAAAA==.Heatseeka:BAABNQAECn8tAAMEAAkKYRP0dwCkAQAEAAgKjxL0dwCkAQAaAAcKYwLzIwAdAQAAAA==.Heitan:BAAANQAECgUIDgABNQAECgoKPgAdAOgcAA==.Hexxiz:BAAANQAECgUIBgABNQAECgoKJwAeAK8jAA==.',
Hi='Hiphopinator:BAABNQAECn8vAAIRAAkKFCVIBABIAwARAAkKFCVIBABIAwAAAA==.',
Ho='Ho:BAAANQADCgQIBAAAAA==.Holyshock:BAABNQAECn9AAAMMAAoKsBykLAC0AgAMAAoKsBykLAC0AgASAAEKLgQbhgEgAAAAAA==.Holyterror:BAAANQADCgYIGQAAAA==.',
Ia='Ianthe:BAAANQAECgYIBwAAAA==.',
Ib='Iboga:BAABNQAECn8ZAAMPAAcK7AYsCgDsAAAPAAcK7AYsCgDsAAAKAAIKwwGkRwFQAAAAAA==.Ibrahimovic:BAAANQAECgUICQAAAA==.',
Ig='Ignitecro:BAAANQABCgcIDwAAAA==.Igram:BAAANQAECgcIEwAAAA==.',
Il='Illumona:BAABNQAECn8eAAMJAAYKaANUJwB9AAAJAAQK8QNUJwB9AAAQAAYKZQKiYABtAAAAAA==.Iluz:BAAANQADCgMIAwAAAA==.',
In='Inafume:BAAANQADCggJEwAAAA==.Inoxia:BAAANQAECgUIDgAAAA==.Intrépidice:BAAANQAECgQIDQAAAA==.',
Ix='Ixtabay:BAABNQAECn8nAAQkAAkKAiB7AgD3AgAkAAkKQx17AgD3AgADAAMK3BeIPADPAAAdAAMKvQ1BEgGmAAAAAA==.',
Ja='Jamurra:BAAANQAECgcIDQABNQAECgcIEQAZAAAAAA==.Jaylinn:BAABNQAECn8sAAIKAAoKnQfmpAC8AQAKAAoKnQfmpAC8AQAAAA==.Jazzmend:BAAANQAECgQJBAAAAA==.',
Je='Jeanne:BAABNQAECn8wAAIKAAkK/hreOgAuAgAKAAkK/hreOgAuAgABNQAECgoKSgAcAF0iAA==.Jellykins:BAABNQAECn8qAAIMAAgK6RVTOgD7AQAMAAgK6RVTOgD7AQAAAA==.',
Ji='Jimjamjuju:BAAANQAECgYICgAAAA==.Jimsonweed:BAABNQAECn8fAAIGAAoKVggpTgB7AQAGAAoKVggpTgB7AQAAAA==.',
Jo='Josie:BAABNQAECn84AAMWAAoK8Bo0AQD+AgAWAAoK8Bo0AQD+AgANAAEKqwbKWgAqAAAAAA==.Jozbirt:BAABNQAECn8mAAIlAAgKng6tEQDmAQAlAAgKng6tEQDmAQAAAA==.',
Ka='Kaeiria:BAAANQADCgQIBAAAAA==.Kael:BAABNQAECn8nAAMEAAcKPxeTYQBgAQAEAAYKoRSTYQBgAQABAAcKLQwicAD/AAAAAA==.Kalaanri:BAABNQAECn8aAAMEAAcK/haNvQDvAAAEAAUKlxKNvQDvAAABAAYK/BFXdwDsAAAAAA==.Kalyandra:BAABNQAECn8kAAIUAAYKAA4IPAA1AQAUAAYKAA4IPAA1AQAAAA==.Karlach:BAAANQADCgYICQABNQAECgoKMQAbAOgVAA==.Karumie:BAABNQAECn8+AAIEAAoKUxvPFgDUAgAEAAoKUxvPFgDUAgAAAA==.Kateera:BAAANQADCgQIBAAAAA==.',
Ke='Keden:BAAANQADCgYICgAAAA==.Kelesa:BAAANQAECgEIAQAAAA==.Keljaden:BAABNQAECn86AAMjAAoKUySKCwAoAwAjAAoKUySKCwAoAwARAAIKbB1tMwBPAAAAAA==.Kenner:BAAANQAECgIIAgAAAA==.',
Kh='Kheyra:BAABNQAECn8rAAIeAAgK+SD0CwBHAgAeAAgK+SD0CwBHAgABNQAECgoKUAADAJwdAA==.Khloesham:BAAANQAECgEIAQAAAA==.',
Ki='Kirsha:BAAANQAECgcIEQAAAA==.Kittybeef:BAAANQADCgEIAQAAAA==.Kiwiiga:BAAANQAECgIIAwAAAA==.',
Kn='Knoxxic:BAAANQADCgMIBgAAAA==.',
Ko='Kohnor:BAAANQADCgcIHQAAAA==.Koopalizard:BAABNQAECn8pAAIgAAkKxSGZCgD6AgAgAAkKxSGZCgD6AgAAAA==.Kopi:BAABNQAECn8pAAIJAAgKxB0OBwDlAQAJAAgKxB0OBwDlAQAAAA==.Korlatt:BAABNQAECn8yAAMQAAkKoh5FHAC3AgAQAAkKFB5FHAC3AgAJAAQKTCAgGAAuAQAAAA==.Kowalabear:BAAANQAECgEIAQAAAA==.',
Ku='Kuaha:BAAANQADCgYIBgABNQADCgQIBAAZAAAAAA==.Kupa:BAAANQADCgYJCgAAAA==.Kurom:BAAANQADCgcJDQAAAA==.Kurston:BAABNQAECn89AAIHAAkK+CKgBgBGAwAHAAkK+CKgBgBGAwAAAA==.',
Ky='Ky:BAAANQADCgEIAQAAAA==.',
['Kã']='Kãtniss:BAAANQADCgUIFQAAAA==.',
La='Labella:BAAANQADCggIHgAAAA==.Lacia:BAAANQAECgQIBQABNQAECgoKIAAIAI4HAA==.Laih:BAABNQAECn8kAAIbAAoKpgmdEwB6AQAbAAoKpgmdEwB6AQAAAA==.Landsong:BAAANQADCgQIBAAAAA==.Lathelinis:BAAANQADCgEIAQAAAA==.',
Le='Leyote:BAABNQAECn82AAIEAAgKGxM8RwDDAQAEAAgKGxM8RwDDAQAAAA==.',
Li='Liady:BAAANQADCgEJAQAAAA==.Lightshop:BAAANQADCgYICQAAAA==.Liirah:BAAANQADCgYICQAAAA==.Lilyfox:BAAANQAECgYIEQABNQAECgYIFgAFAHwLAA==.Lindithrial:BAAANQADCgEIAQAAAA==.Livingdead:BAAANQADCggILwAAAA==.',
Lo='Lorianne:BAAANQAECgQICQAAAA==.Lorraine:BAAANQADCggIDAAAAA==.Lowdangle:BAAANQADCgcIBwAAAA==.',
Lu='Lulz:BAAANQAECggICQAAAA==.Luminias:BAAANQAECgEIAQAAAA==.Luucifur:BAAANQADCgEIAQAAAA==.',
Ma='Mackpumpkin:BAAANQAECgIIAgAAAA==.Macktheknife:BAAANQADCgQICAABNQAECgkJJwAkAAIgAA==.Madalyn:BAAANQADCgEIAgAAAA==.Maexna:BAAANQAECgEIAgAAAA==.Magdelyne:BAABNQAECn8aAAISAAoKMQjb6gBGAQASAAoKMQjb6gBGAQAAAA==.Magglés:BAAANQAECgIIAgAAAA==.Makklehaney:BAABNQAECn8WAAIBAAgKZwstfACvAQABAAgKZwstfACvAQAAAA==.Mallaah:BAAANQADCgUIBgAAAA==.Marovingian:BAABNQAECn8qAAIMAAgK4iMAFgAmAwAMAAgK4iMAFgAmAwAAAA==.Matthad:BAABNQAECn8nAAIEAAkKwRgIXQD4AQAEAAkKwRgIXQD4AQAAAA==.Mazìkene:BAAANQAECgQIBAABNQAECgoKOAAJAI0bAA==.',
Mc='Mcnastie:BAAANQAECgUIDwAAAA==.Mcsluts:BAAANQADCgYJDQAAAA==.',
Me='Melmirict:BAAANQADCgMJAwAAAA==.Merciala:BAABNQAECn87AAQOAAkKCg30TwCeAQAOAAkKTAv0TwCeAQAeAAQK7g52MwDIAAAHAAkKOgMUQQDFAAAAAA==.',
Mi='Milyyanna:BAAANQADCgcIHAAAAA==.Mindßender:BAAANQADCgcIBwAAAA==.Mirilla:BAABNQAECn8rAAMLAAoKAxTWRAAaAgALAAoKAxTWRAAaAgAXAAcKPAWUGQApAQAAAA==.',
Mo='Moddoxx:BAABNQAECn8yAAQkAAkK+xhgCQBwAQAdAAkKpRWARADSAQAkAAcKOxlgCQBwAQADAAEKHA1FeAA1AAAAAA==.Moffa:BAAANQADCgMIAwAAAA==.Mohawk:BAABNQAECn8gAAIHAAoKaBZqGQBwAgAHAAoKaBZqGQBwAgAAAA==.Molen:BAAANQAECgEIAQAAAA==.Mommyjuice:BAAANQAECggIDgABNQAFFAcIFQAKANcgAA==.Monkeeh:BAAANQADCggIEAAAAA==.Monkle:BAABNQAECn80AAIUAAoKNR90CQCrAgAUAAoKNR90CQCrAgAAAA==.Monohan:BAAANQADCgUIBgABNQAECgkJLQAYAJ4bAA==.Moonpaw:BAAANQAECgIIAgAAAA==.Moonsii:BAABNQAECn8yAAMHAAoKGhGKGQD0AQAHAAoKGhGKGQD0AQAOAAEKQgYjgwAoAAAAAA==.Mooroth:BAABNQAECn86AAMRAAoKqRWCDgCVAQARAAkKJReCDgCVAQAjAAIKQQvrEAE0AAAAAA==.Morkilro:BAAANQAECgEIAwAAAA==.Morozko:BAAANQADCgQIBAAAAA==.',
Ms='Msasani:BAAANQADCgEIAQABNQAECgoKUAADAJwdAA==.Msmana:BAAANQAECgIIAwAAAA==.',
Mu='Muddler:BAABNQAECn8UAAIDAAYKiQGiVACBAAADAAYKiQGiVACBAAAAAA==.Muire:BAAANQAECgYIBAABNQAECgoKPgAdAOgcAA==.Murinn:BAABNQAECn8vAAIKAAkK/wx8bQCeAQAKAAkK/wx8bQCeAQAAAA==.',
['Mà']='Màggles:BAAANQAECgYIEQAAAA==.',
Na='Nadd:BAABNQAECn8YAAIKAAYKBgYTzwDPAAAKAAYKBgYTzwDPAAAAAA==.Naledi:BAAANQADCggIDQAAAA==.Naralyn:BAABNQAECn81AAMaAAoKOBogCwA1AgAaAAoKOBogCwA1AgABAAUKYRG6tgAlAQAAAA==.Narb:BAAANQADCggIAQAAAA==.',
Ne='Needlepax:BAAANQABCgMIAwAAAA==.Negrido:BAABNQAECn9BAAQdAAoKYhzvPwCSAgAdAAgKHx3vPwCSAgADAAMKiBubNQDsAAAkAAMKHhUbHACfAAAAAA==.Nei:BAABNQAECn8yAAISAAgKERWCcACvAQASAAgKERWCcACvAQAAAA==.Neon:BAAANQADCgUICwAAAA==.',
Ni='Nickellite:BAAANQAECgEIAQAAAA==.Nikem:BAABNQAECn8rAAIOAAoKfhJoHADsAQAOAAoKfhJoHADsAQAAAA==.',
No='Noelle:BAABNQAECn8XAAISAAkKlhi3kQBoAQASAAkKlhi3kQBoAQAAAA==.Norelei:BAAANQAECgIIAgABNQAECgoKUAADAJwdAA==.Noriyuki:BAABNQAECn8eAAIUAAYKEgKGXwBiAAAUAAYKEgKGXwBiAAAAAA==.',
Ny='Nyxahlia:BAAANQADCggIDwABNQAECgkJNgAIALkYAA==.',
Og='Oghom:BAAANQAECgEIAQAAAA==.Ogrekin:BAAANQAECggIEwAAAA==.',
Ol='Olderon:BAABNQAECn8jAAIMAAkKwxO5WwAFAgAMAAkKwxO5WwAFAgAAAA==.Olrong:BAABNQAECn82AAIQAAgKhwrROAAiAQAQAAgKhwrROAAiAQAAAA==.Oluja:BAABNQAECn8YAAIEAAkKQwxbfwADAQAEAAkKQwxbfwADAQAAAA==.',
On='Onuris:BAAANQAECgMICAAAAA==.',
Oo='Oogiboogi:BAAANQAECgQIAwAAAA==.',
Op='Opacuslupus:BAAANQAECgQICQAAAA==.Oppressin:BAABNQAECn8sAAIUAAgKXBeTIAAoAgAUAAgKXBeTIAAoAgAAAA==.',
Os='Oshunn:BAABNQAECn8pAAILAAoK/RD+qQAuAgALAAoK/RD+qQAuAgAAAA==.Osroes:BAAANQAECgQIEgAAAA==.',
Ov='Overdoom:BAABNQAECn8sAAMCAAoKTBsmLwB0AgACAAoKTBsmLwB0AgAFAAUKrBORYAAjAQAAAA==.Ovli:BAAANQAECgUICgAAAA==.',
Ow='Owner:BAAANQAECggICwAAAA==.',
Pa='Pacolock:BAAANQADCggICAABNQAECggIFgAMANcTAA==.Paladinjohn:BAACNQAFFH8cAAISAAYKvSP7BQD2AQASAAYKvSP7BQD2AQA1AAQKfzQAAhIACgrhJRUNACgDABIACgrhJRUNACgDAAAA.Palykat:BAABNQAECn8cAAISAAcKJwWa7gDJAAASAAcKJwWa7gDJAAAAAA==.Pandadeez:BAAANQADCgYIDQAAAA==.Papiroflz:BAABNQAECn87AAMBAAoKxSQYBwA0AwABAAoKxSQYBwA0AwAEAAUKexz3fwCMAQAAAA==.',
Pe='Pennydredful:BAAANQADCgEIAwAAAA==.Pennywisé:BAABNQAECn8mAAIFAAkKSiAhGQDCAgAFAAkKSiAhGQDCAgAAAA==.',
Pl='Plaguegying:BAABNQAECn8uAAIYAAkKERbjIQC/AQAYAAkKERbjIQC/AQABNQAECgYIBwAZAAAAAA==.Ploofee:BAAANQAECgMIBQAAAA==.',
Pr='Preparedr:BAACNQAFFH87AAMbAAkKdiYBAAAMBAAbAAkKYCYBAAAMBAAGAAcKwSZ/AAC0AgA1AAQKfx8AAwYACgruJc8JANgCAAYACAo/Js8JANgCABsABwryJSElAGECAAAA.Progresz:BAAANQAECgMIAwAAAA==.',
Pu='Purebread:BAAANQAECgEIAQAAAA==.',
Py='Pykel:BAABNQAECn8+AAIOAAoKCwsAJgCVAQAOAAoKCwsAJgCVAQAAAA==.',
Qa='Qaren:BAAANQADCgYIFQAAAA==.',
Qu='Questionable:BAAANQADCgEIAQAAAA==.',
Ra='Raishun:BAAANQAECgEJAQAAAA==.Raizo:BAAANQAECgEIAQAAAA==.Rake:BAABNQAECn9AAAIlAAoKmCGjAgAGAwAlAAoKmCGjAgAGAwAAAA==.Rannï:BAAANQADCgQIBAABNQAECgkJJwAkAAIgAA==.Raskreia:BAABNQAECn8aAAMCAAoKbSKVBQAKAwACAAoKbSKVBQAKAwAFAAUKnxriWABIAQABNQAFFAQICgALANAhAA==.Rassina:BAAANQADCgEIAQAAAA==.Rawk:BAAANQAECgQIBgAAAA==.',
Re='Redeemly:BAABNQAECn8VAAISAAoKOBm0aADCAQASAAoKOBm0aADCAQAAAA==.Redeyejedi:BAAANQAECggIBwAAAA==.Reeven:BAAANQAECggILQAAAQ==.Revokely:BAAANQAECgYIDgABNQAECgoKFQASADgZAA==.',
Rh='Rhcpmage:BAAANQADCggICwABNQAFFAYIHQALANMlAA==.Rhetegast:BAABNQAECn9AAAImAAoKmxv0CQBrAgAmAAoKmxv0CQBrAgAAAA==.',
Ri='Rieloesh:BAAANQAECgMIBAAAAA==.Rike:BAABNQAECn81AAMmAAgKZR3yHgDvAQAmAAYKVB7yHgDvAQASAAgK0xqGbQC2AQAAAA==.Ristretto:BAAANQADCgYIDgABNQAECggIKQAJAMQdAA==.',
Ro='Rodhunt:BAAANQADCgEIAQAAAA==.Roland:BAAANQADCgUJCgAAAA==.Rolandin:BAABNQAECn8wAAIMAAgKWRRZQADgAQAMAAgKWRRZQADgAQAAAA==.',
Ru='Rukraga:BAAANQAECgQJBAAAAA==.',
Ry='Rylagosa:BAABNQAECn8wAAMgAAkKIxu7BgDGAgAgAAkKIxu7BgDGAgAnAAIKGwtMIwAtAAAAAA==.Ryzesmidge:BAAANQAECgcJDAAAAA==.',
['Rê']='Rêdrum:BAAANQAECgYIBgABNQAECgoKOAAJAI0bAA==.',
Sa='Sadoh:BAAANQADCgEIAQABNQAECgMIBQAZAAAAAA==.Salandria:BAABNQAECn8pAAQmAAkKLhqXGQAnAgAmAAkKLhqXGQAnAgAMAAUKSSQXXgD+AQASAAEKAABWnwE3AAAAAA==.Sarionian:BAABNQAECn8eAAMHAAYKPRFULwAuAQAHAAYKPRFULwAuAQAOAAQKWhOCTgC4AAAAAA==.Sarjin:BAAANQAECgEIAQABNQAECgoKUAADAJwdAA==.Sarvinblue:BAABNQAECn9QAAMEAAoKKyJ4EABBAwAEAAoKKyJ4EABBAwABAAgKhhTUaQDjAQAAAA==.',
Sc='Schmøtz:BAAANQAECgEIAgAAAA==.Scopolamine:BAAANQAECgUIEAAAAA==.',
Se='Severian:BAAANQADCgEIAgAAAA==.Sevrin:BAABNQAECn8rAAIYAAkKzw6PSgDNAQAYAAkKzw6PSgDNAQAAAA==.Seymonty:BAABNQAECn8mAAMWAAoKNw4zDgBMAQAIAAoK8giwhQCGAQAWAAcKMA8zDgBMAQAAAA==.',
Sh='Shaeko:BAAANQADCggIGgAAAA==.Shazlulu:BAABNQAECn8aAAIEAAYK1RNxcgAoAQAEAAYK1RNxcgAoAQAAAA==.Shaznoir:BAABNQAECn81AAIDAAkKdgrgBgA7AQADAAkKdgrgBgA7AQAAAA==.Shilajit:BAAANQAECgMICAAAAA==.Shokz:BAAANQADCgMIBAABNQAECgMIBQAZAAAAAA==.',
Si='Simbelmynë:BAAANQADCgcIBwABNQAECgoKUAADAJwdAA==.',
Sk='Skip:BAAANQADCgcIBwAAAA==.Skøøma:BAAANQABCgIIBAAAAA==.',
Sl='Slicer:BAAANQADCgEIAQAAAA==.Sloe:BAAANQAECgEIAQABNQAECggIKgAMAOkVAA==.',
Sm='Smokalot:BAAANQAECgIIBQAAAA==.Smokehunter:BAAANQADCgYIBgAAAA==.',
Sn='Snoop:BAAANQADCgYICwAAAA==.',
So='Solstîce:BAAANQADCgQIBAABNQAECgoKOAAJAI0bAA==.Sonsu:BAAANQADCggICAABNQAECgcIHgAHAD0RAA==.',
Sp='Speedbeefbal:BAAANQAECgQIBAAAAA==.Speeddwrfbal:BAAANQADCggIKQAAAA==.Speedmeatbal:BAABNQAECn8fAAIBAAkKowbOfADeAAABAAkKowbOfADeAAAAAA==.Speedmeatlok:BAAANQAECgUICwAAAA==.Speedmonkbal:BAAANQAECgUICwAAAA==.Speedoe:BAAANQADCggIFgAAAA==.Spidêrs:BAAANQADCgEIAQAAAA==.Sporkulous:BAABNQAECn8gAAIKAAgKRgj5uQCQAQAKAAgKRgj5uQCQAQAAAA==.',
Sq='Squal:BAABNQAECn8bAAISAAoKfRewRAApAgASAAoKfRewRAApAgAAAA==.Squiggle:BAABNQAECn8tAAImAAkKKRwHDgAVAgAmAAkKKRwHDgAVAgAAAA==.',
St='Steevii:BAAANQADCgMIAwAAAA==.Stewie:BAAANQAECgUIBQAAAA==.Striker:BAAANQADCgYIFAABNQAECggINQAmAGUdAA==.Strikers:BAAANQAECgEIAgAAAA==.',
Su='Sunshíne:BAABNQAECn8bAAMmAAcKERH8MgBKAQAmAAcKERH8MgBKAQASAAEKwgNK1AEbAAAAAA==.',
Sy='Syver:BAABNQAECn8jAAICAAoKWReCGQDrAQACAAoKWReCGQDrAQAAAA==.',
['Sí']='Sírlancealot:BAAANQADCgMIBAAAAA==.',
Ta='Takeke:BAABNQAECn8mAAMYAAoKoBgKFQA+AgAYAAkKoBgKFQA+AgACAAUKUgv/iAD+AAAAAA==.Takeroux:BAAANQAECgEIAQAAAA==.Talandroz:BAABNQAECn8nAAMgAAkK6RxoCwA5AgAgAAkK6RxoCwA5AgAnAAIKTAtvNQBiAAAAAA==.Tanagra:BAAANQADCgIIAwABNQAECgkJMgAkAPsYAA==.Tankz:BAAANQADCgYIDQAAAA==.Tanner:BAACNQAFFH8NAAIKAAUK1hMBFADNAAAKAAUK1hMBFADNAAA1AAQKf0YAAgoACgpqHRwnAHgCAAoACgpqHRwnAHgCAAAA.Taraweeble:BAAANQADCgEIAQAAAA==.',
Te='Tebo:BAAANQAECgEIAgAAAA==.Teboe:BAAANQADCgcICQABNQAECgEIAgAZAAAAAA==.Tedman:BAABNQAECn8tAAMBAAkK+g9xigCKAQABAAgKQA9xigCKAQAEAAcK8QxvjQDdAAAAAA==.Temel:BAABNQAECn81AAMEAAgKGRQwWQB9AQAEAAgKGRQwWQB9AQABAAQKXAdI7QC8AAAAAA==.Teostra:BAABNQAECn8uAAMKAAoKESJpEwDgAgAKAAoKESJpEwDgAgAhAAEKyApHWQA3AAAAAA==.Terradan:BAAANQAECgIIAwAAAA==.Testoecles:BAAANQADCgcICwABNQAECgEIAgAZAAAAAA==.',
Th='Thadrack:BAAANQAECgcIEAABNQAECgoKIAAIAI4HAA==.Thalonstin:BAAANQADCggIHwAAAA==.Thaneold:BAAANQAECgQJCQABNQAECgoKNwAIAJMjAA==.Thassarian:BAABNQAECn8WAAIFAAYKfAszVgAAAQAFAAYKfAszVgAAAQAAAA==.Theodrid:BAACNQAFFH8TAAImAAcKpBpPAgAVAgAmAAcKpBpPAgAVAgA1AAQKfzIAAiYACgpUJEMIABoDACYACgpUJEMIABoDAAAA.Thunderstomp:BAAANQADCgIIAgAAAA==.',
Ti='Tinkerspell:BAAANQADCgYICwAAAA==.Tinkíe:BAABNQAECn8pAAIVAAkKQx89CwDRAgAVAAkKQx89CwDRAgAAAA==.Tirzahdozier:BAAANQAECgEIAgABNQAECgcIEQAZAAAAAA==.Tiwohnne:BAAANQAECgYIDAAAAA==.',
Tl='Tla:BAAANQADCgcIGgAAAA==.',
Tp='Tpaartos:BAAANQADCgIJAgABNQAECgkJJwAEAMEYAA==.',
Tr='Treat:BAABNQAECn85AAINAAkKKyPjCgA1AwANAAkKKyPjCgA1AwAAAA==.Trippysheep:BAAANQAECgYICQABNQAFFAkJIQAdAAgjAA==.Trippyshock:BAAANQAECggICQABNQAFFAkJIQAdAAgjAA==.Trips:BAAANQADCgEIAQAAAA==.Tristitia:BAAANQADCgEIAQAAAA==.',
Tu='Turkeltin:BAACNQAFFH8OAAIiAAYKkhbdBAALAQAiAAYKkhbdBAALAQA1AAQKfzUAAiIACgrVIzsDAKYDACIACgrVIzsDAKYDAAAA.',
Tw='Twiggle:BAAANQADCgYICAABNQAECgcIEQAZAAAAAA==.Twistedsquid:BAAANQABCgQIBAAAAA==.',
Ty='Tyamat:BAABNQAECn8cAAMkAAcKxhf7CQDcAQAkAAcKxhf7CQDcAQAdAAIKGwVUMwFUAAAAAA==.Tyche:BAAANQADCgYIEAAAAA==.Tyrinara:BAAANQADCggICAAAAA==.Tysbich:BAAANQAECgIIAgABNQAECggIKgAMAOIjAA==.',
Ui='Uiewedaoez:BAABNQAECn8rAAIHAAoKVSVCBgBPAwAHAAoKVSVCBgBPAwAAAA==.',
Va='Vains:BAABNQAECn86AAISAAoK9B23PgA+AgASAAoK9B23PgA+AgAAAA==.Valrith:BAAANQADCgcIGAAAAA==.',
Ve='Velexi:BAAANQABCggIEgAAAA==.Velin:BAAANQAECgQIBAAAAA==.Velody:BAAANQADCgQIAgAAAA==.Vendettuh:BAAANQADCgYIBwAAAA==.Veronica:BAABNQAECn8uAAILAAgKnxICeQCKAQALAAgKnxICeQCKAQAAAA==.Verren:BAABNQAECn8sAAIeAAgK3hFBHQC3AQAeAAgK3hFBHQC3AQAAAA==.Vesfor:BAAANQAECgEIAQABNQAECgcIGgAKAB4XAA==.Vestus:BAAANQADCgEIAgAAAA==.',
Vy='Vyrridyl:BAAANQAECgQICQAAAA==.',
Wa='Waddlez:BAAANQAECgcIBgAAAA==.Watermark:BAABNQAECn8jAAMEAAgK5gtGmwBCAQAEAAgK5gtGmwBCAQABAAUKkQRMmQCgAAAAAA==.',
We='Weeblewobble:BAAANQAECgIIAgAAAA==.Weltamus:BAAANQADCgYIFQAAAA==.Weltazar:BAABNQAECn8kAAIBAAgKfRUgRwB+AQABAAgKfRUgRwB+AQAAAA==.Weltzilla:BAABNQAECn8nAAIKAAkKexieVQDeAQAKAAkKexieVQDeAQAAAA==.Westside:BAAANQAECgYIDgABNQAECggIDQAZAAAAAA==.',
Wh='Whoosh:BAABNQAECn8sAAIYAAkKKiKDFgD5AgAYAAkKKiKDFgD5AgAAAA==.',
Wi='Wickët:BAABNQAECn8pAAMEAAkKESQwFgAfAwAEAAgK6iMwFgAfAwABAAcKex2EWQAWAgAAAA==.Wildtiger:BAABNQAECn8zAAIlAAkKMhI2EQDwAQAlAAkKMhI2EQDwAQAAAA==.Wisey:BAAANQAECgUIBQAAAA==.',
Wo='Wolfslied:BAAANQADCgQIBAABNQADCgQIBAAZAAAAAA==.',
Wu='Wulfenhide:BAABNQAECn8rAAIbAAkK0SN0BADFAgAbAAkK0SN0BADFAgAAAA==.Wuntvor:BAAANQADCggICAAAAA==.',
Wy='Wyzsky:BAAANQAECgEIAQABNQAECggINQAEABkUAA==.',
Xa='Xalreth:BAABNQAECn8mAAIiAAgKBgmUNwCHAQAiAAgKBgmUNwCHAQAAAA==.Xaviana:BAAANQAECgUIBQAAAQ==.',
Ya='Yastypoo:BAABNQAECn8oAAMMAAoK6hD1VAAbAgAMAAoK6hD1VAAbAgASAAEKShllYwE6AAAAAA==.',
Za='Zaiannah:BAAANQADCgEIAQAAAA==.Zarieda:BAAANQAECgcIDQAAAA==.Zayrelia:BAACNQAFFH8XAAIHAAcKqxXuAwDFAQAHAAcKqxXuAwDFAQA1AAQKf04AAwcACgoiIswFAF0DAAcACgoiIswFAF0DAA4ACAo3FZtQAJsBAAAA.',
Ze='Zelenor:BAAANQAECgEIAgABNQAECgcIHAAkAMYXAA==.',
Zu='Zud:BAABNQAECn8dAAICAAgKGR3IOwAyAgACAAgKGR3IOwAyAgAAAA==.',
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
