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

local lookup = {'Shaman-Elemental','DeathKnight-Unholy','Druid-Guardian','Shaman-Restoration','Rogue-Subtlety','Unknown-Unknown','Mage-Arcane','Druid-Balance','Hunter-Survival','Paladin-Retribution','Monk-Brewmaster','Monk-Mistweaver','Mage-Frost','Priest-Holy','Priest-Shadow','Hunter-BeastMastery','DeathKnight-Blood','Rogue-Assassination','Rogue-Outlaw','Warlock-Demonology','Warlock-Destruction','Evoker-Augmentation','Evoker-Preservation','Priest-Discipline','Hunter-Marksmanship','Paladin-Holy','Shaman-Enhancement','Warrior-Protection','Warlock-Affliction','Druid-Feral','Warrior-Arms','Druid-Restoration','Monk-Windwalker','DemonHunter-Havoc','DeathKnight-Frost','Paladin-Protection','DemonHunter-Vengeance','Evoker-Devastation',}
local provider = {region='US',realm='KulTiras',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aarix:BAABNQAECoEZAAIBAAcK7gojfwB2AQABAAcK7gojfwB2AQAAAA==.',
Ae='Aendillan:BAAANQADCgUIBQAAAA==.',
Af='Affonasei:BAABNQAECoEaAAICAAcKOwnHaQBGAQACAAcKOwnHaQBGAQAAAA==.',
Ag='Agkistrodon:BAAANQADCgUIBQABNQAECgYIGAADACohAA==.',
Ai='Aicaramba:BAABNQAECoEZAAIEAAkKTx57JgCrAgAEAAkKTx57JgCrAgAAAA==.Aileen:BAAANQAECgQIBwAAAA==.',
Aj='Ajay:BAAANQAECgQIBAAAAA==.',
Ak='Akashi:BAAANQAECgcICgABNQAFFAQIBwAFAC4LAA==.',
Al='Alacrodie:BAAANQADCgUIEgAAAA==.',
Am='Amoonsi:BAAANQADCgMIAwABNQAECgYIEgAGAAAAAA==.Amordeyain:BAAANQAECgIIAgAAAA==.',
An='Angrydisc:BAAANQAECgQIBAABNQAECgcIEAAGAAAAAA==.Angrytotems:BAAANQAECgUIBwABNQAECgcIEAAGAAAAAA==.Annaborshen:BAAANQABCgIIAgAAAA==.Antoccino:BAAANQAECgQIBQABNQAECgYIEAAGAAAAAA==.',
Ar='Aragorno:BAAANQAECgYIDAAAAA==.Arcturen:BAAANQAECgMIBQAAAA==.Ardala:BAAANQAECggICAAAAA==.Arenthal:BAAANQAECgQICAABNQAECgkJLAAHAFIcAA==.Arturaan:BAAANQABCggIGAAAAA==.',
As='Ashalana:BAAANQADCgUIBQAAAA==.Asheby:BAAANQADCgMIAwABNQAECgYIEQAGAAAAAA==.Ashiera:BAABNQAECoEcAAIHAAcKYwI/MwESAQAHAAcKYwI/MwESAQAAAA==.Astralmorph:BAAANQADCgYIBgAAAA==.',
At='Atomic:BAAANQAECgEIAgAAAA==.',
Au='Augenblick:BAAANQADCgIIAgAAAA==.Aurorée:BAAANQAECgQICAAAAA==.',
Az='Azylstrid:BAAANQADCgYIDAAAAA==.',
Ba='Baeu:BAAANQABCgUIBwAAAA==.Balentine:BAAANQAECgUIDwAAAA==.Banostraza:BAAANQAECgQIBQAAAA==.Baspir:BAABNQAECoEdAAIIAAgKdhStNQAUAgAIAAgKdhStNQAUAgAAAA==.',
Be='Beeboop:BAAANQADCgIIAgAAAA==.Belly:BAABNQAECoEiAAIJAAgKvB3/AgDQAgAJAAgKvB3/AgDQAgAAAA==.Belrae:BAAANQAECgQIBAAAAA==.Benchfresh:BAABNQAECoEZAAIKAAcKbB6iXwBPAgAKAAcKbB6iXwBPAgAAAA==.Bendah:BAAANQAECgEIAQAAAA==.Bender:BAAANQADCgYIBgAAAA==.Bezieck:BAAANQAECgIIAgAAAA==.',
Bi='Bigfolks:BAAANQADCgUIBwAAAA==.Bigollock:BAAANQADCgYICwAAAA==.Bili:BAAANQADCgYIBgAAAA==.',
Bl='Bloodarrow:BAAANQADCgUIBwAAAA==.Bloodbound:BAAANQADCgYIBgAAAA==.',
Bo='Bockchi:BAAANQAECgQIBQAAAA==.Bonanas:BAAANQABCggICAAAAA==.Bonegavel:BAAANQABCgQIBgAAAA==.Bookhuntress:BAAANQAECgYIBgAAAA==.',
Br='Branex:BAAANQAECggICAAAAA==.Branpaw:BAAANQADCgMIAwAAAA==.Brewdeez:BAABNQAECoEhAAILAAgKjBmeCgBMAgALAAgKjBmeCgBMAgAAAA==.Brewzen:BAAANQADCgYIBgAAAA==.Brewzer:BAABNQAECoEnAAIMAAkKEw+kFgDiAQAMAAkKEw+kFgDiAQAAAA==.Brick:BAAANQADCgQIBAAAAA==.Brint:BAAANQADCgcICwAAAA==.Bronad:BAACNQAFFIENAAMNAAUKryJGBAC0AAAHAAQKhyKCFQCjAQANAAIKzR9GBAC0AAA1AAQKgTYAAwcACQrGJhkBAPkDAAcACQrGJhkBAPkDAA0AAQo/H80+ADYAAAAA.Broomhandle:BAABNQAECoEZAAIKAAcKUSACUQB5AgAKAAcKUSACUQB5AgAAAA==.',
Bu='Bumbushka:BAAANQAECgcICwAAAA==.Burinn:BAAANQAECgMIBQABNQAECgcIHgAOAJMXAA==.',
Ca='Caeus:BAAANQAECgYIEAAAAA==.Cam:BAAANQAECgYIEQAAAA==.Carolinabele:BAAANQADCggICAAAAA==.Cauud:BAAANQADCgYIEAAAAA==.',
Cb='Cbd:BAAANQADCgcIEwAAAA==.',
Ce='Celerious:BAAANQABCgIIAgAAAA==.',
Ch='Chacruna:BAAANQAECgMIBgAAAA==.Chelan:BAABNQAECoEeAAMOAAcKkxf9WgDhAQAOAAcKkxf9WgDhAQAPAAEK9wLmgAAbAAAAAA==.Chloelock:BAAANQABCgEJAQAAAA==.Chronicler:BAAANQADCgEIAQAAAA==.Chuntspeed:BAAANQADCgIIAgAAAA==.Chuye:BAAANQAECgEIAQABNQAECggIGgAOAJcYAA==.',
Cl='Clambulance:BAABNQAECoEjAAIQAAgK4RjESQBpAgAQAAgK4RjESQBpAgAAAA==.',
Cn='Cnova:BAAANQAECgUIDgABNQAECgYICQAGAAAAAA==.',
Co='Codythedead:BAACNQAFFIENAAMCAAUKRRUMCgBJAQACAAQKXxoMCgBJAQARAAEK3wA4OAAQAAA1AAQKgSYAAgIACQpYIoMXAOgCAAIACQpYIoMXAOgCAAAA.Coraf:BAACNQAFFIENAAIEAAUKTR5oBgDZAQAEAAUKTR5oBgDZAQA1AAQKgSIAAgQACQqnIpgNAD8DAAQACQqnIpgNAD8DAAAA.Coyotl:BAAANQAECgYIDAAAAA==.',
Cr='Crazyazshamy:BAAANQADCggIDgAAAA==.',
Cu='Cuvier:BAAANQADCggJFgAAAA==.',
Da='Danak:BAAANQADCgQIDQAAAA==.',
De='Deadlyfrosty:BAAANQADCgYIDgAAAA==.Deathmob:BAAANQAECgYIEwAAAA==.Deathsynth:BAAANQADCgQJBAABNQAECgYIDwAGAAAAAA==.Debixie:BAABNQAECoEgAAMSAAkKSR7qDAABAwASAAkKSR7qDAABAwATAAYKuBPJDABqAQAAAA==.Decisive:BAAANQADCgYIBgABNQAFFAgIFAAUAK4eAA==.Dejection:BAAANQABCgYIBwAAAA==.Demisi:BAAANQAECgYICgAAAA==.Demiurge:BAABNQAECoEZAAIIAAgKBxoXKABzAgAIAAgKBxoXKABzAgAAAA==.',
Di='Diasundra:BAABNQAECoEjAAIQAAgKhiH3JADlAgAQAAgKhiH3JADlAgAAAA==.Dibbons:BAAANQAECgYIBwAAAA==.Divinatjin:BAAANQADCgYICQAAAA==.',
Do='Dollars:BAAANQAECgIIAgABNQAECgYICgAGAAAAAA==.Dottingyou:BAACNQAFFIENAAMVAAUKwxJLCwCkAAAUAAMKoRLXHADhAAAVAAIK9hJLCwCkAAA1AAQKgSQAAxUACQr6HzkWALMBABQABwrGH6pNAEwCABUABgoiGjkWALMBAAAA.',
Dr='Dracthyrbm:BAAANQAECgIIAgAAAA==.Dreepy:BAAANQAECgUJBQAAAA==.Drransom:BAAANQADCgQICQAAAA==.Dryan:BAAANQAECgYIEQAAAA==.',
Du='Duo:BAABNQAECoEhAAIQAAgKehkmPwCJAgAQAAgKehkmPwCJAgAAAA==.Duragon:BAABNQAECoEcAAMWAAgKMgrkCwB1AQAWAAgKMgrkCwB1AQAXAAEKtQDiTgAaAAAAAA==.',
Ei='Eipwoc:BAAANQADCggIBwAAAA==.',
El='Eloreith:BAABNQAECoEcAAMIAAkKIBQ4KwBcAgAIAAkKJhM4KwBcAgADAAUKhwhuMwC7AAAAAA==.',
Em='Emamagee:BAAANQADCgQIBgAAAA==.Emilia:BAABNQAECoEeAAIOAAcKaBu0SQAhAgAOAAcKaBu0SQAhAgAAAA==.',
En='Endressa:BAABNQAECoElAAMYAAgKrxE0BwDwAQAYAAgKrxE0BwDwAQAPAAQKLRVXPgARAQAAAA==.',
Er='Eralendryn:BAAANQADCgEIAQAAAA==.Erelios:BAAANQAECgYIEAAAAA==.',
Es='Eski:BAABNQAECoExAAMTAAkKSiJfAgAkAwATAAkKSiJfAgAkAwASAAIK2wmxfABiAAAAAA==.Essaena:BAABNQAECoEYAAIRAAcKliFoIACXAgARAAcKliFoIACXAgAAAA==.',
Eu='Eura:BAAANQADCgEJAQAAAA==.Eureka:BAEANQAECgYIEAAAAA==.',
Fa='Faddeyshnek:BAABNQAECoEhAAIQAAgKNgzGeADvAQAQAAgKNgzGeADvAQAAAA==.Farmeador:BAAANQAECgEIAQAAAA==.Fastbeefball:BAAANQADCgIIAgAAAA==.Fatgirljuice:BAABNQAFFIEKAAMQAAYK6h+OAQBPAgAQAAYK6h+OAQBPAgAZAAIKrg/MFwCSAAAAAA==.',
Fe='Felysambre:BAAANQAECgQICAAAAA==.',
Fi='Fish:BAACNQAFFIEbAAIPAAcK2SR7AADvAgAPAAcK2SR7AADvAgA1AAQKgSoAAg8ACQrkJnkAAPMDAA8ACQrkJnkAAPMDAAAA.',
Fl='Flight:BAACNQAFFIEHAAMFAAQKLgsjCwDgAAAFAAMKiQYjCwDgAAASAAEKHxnbFgBVAAA1AAQKgSwAAxIACQqVHhwWAKYCABIACAoBHhwWAKYCAAUABgpcFqYfAL0BAAAA.Floofee:BAAANQADCgQIBAAAAA==.',
Fo='Footfinger:BAAANQABCgUIBgAAAA==.Forsynth:BAAANQAECgYIDwAAAA==.Foxymeatbal:BAAANQADCgYIBQAAAA==.',
Fu='Fubar:BAAANQADCggIEwAAAA==.',
Ga='Ganniy:BAAANQABCgEJAQAAAA==.',
Ge='Gewitt:BAAANQAECgQICAAAAA==.',
Gl='Glinda:BAAANQADCgUICgAAAA==.',
Go='Gonjah:BAAANQAECgYICgAAAA==.',
Gr='Grabomage:BAAANQAECgQICgABNQAFFAUIDQANAK8iAA==.Grabovoker:BAAANQADCgIIAgABNQAFFAUIDQANAK8iAA==.Grazienne:BAAANQADCgUIDQAAAA==.Greavos:BAABNQAECoEaAAIPAAcKHxlUIgD7AQAPAAcKHxlUIgD7AQAAAA==.Griggus:BAAANQAECgYIDQAAAA==.Grimgar:BAABNQAECoEaAAMNAAcKBBooJwCWAAAHAAUK6RlV7gCIAQANAAIKSBooJwCWAAAAAA==.Grimmshady:BAAANQADCgQIBgAAAA==.Grumpsky:BAAANQADCgEIAQABNQAECgcIGQAEAAMQAA==.',
Gu='Gumbles:BAABNQAECoEaAAIOAAgKlxiCOQBgAgAOAAgKlxiCOQBgAgAAAA==.Gurney:BAABNQAECoEWAAMaAAgKQBjqOQBgAgAaAAgKQBjqOQBgAgAKAAEK9gQ/ngEcAAAAAA==.Guzprimal:BAAANQAECgEIAQAAAA==.',
Gw='Gwenory:BAAANQABCgQIBAAAAA==.',
Gy='Gying:BAAANQAECgIIAgAAAA==.',
Ha='Hanekawa:BAAANQAECgYIDgABNQAECgkJKAANAL0kAA==.Hannie:BAAANQADCgUIEAAAAA==.',
He='Headhúnter:BAAANQAECgYICAAAAA==.Heartsparx:BAABNQAECoEaAAISAAgKZRcrHQBrAgASAAgKZRcrHQBrAgAAAA==.Heatseeka:BAABNQAECoEaAAMbAAcKmAIkHwAyAQAbAAcKmAIkHwAyAQAEAAYK+Qx+kwApAQAAAA==.Hexxiz:BAAANQAECgQIBQABNQAECggIGAADAJwiAA==.',
Hi='Hiphopinator:BAABNQAECoEYAAIcAAcKniRvBgDeAgAcAAcKniRvBgDeAgAAAA==.',
Ho='Ho:BAAANQADCgQIBAAAAA==.Holyshock:BAABNQAECoEqAAIaAAkKChpIKgClAgAaAAkKChpIKgClAgAAAA==.Holyterror:BAAANQADCgUIEgAAAA==.',
Ia='Ianthe:BAAANQAECgIIAgAAAA==.',
Ib='Iboga:BAAANQAECgQIEAAAAA==.Ibrahimovic:BAAANQADCggIEQAAAA==.',
Ig='Ignitecro:BAAANQABCgcIDwAAAA==.Igram:BAAANQAECgUIDAAAAA==.',
Il='Illumona:BAAANQAECgQICQAAAA==.Iluz:BAAANQADCgMIAwAAAA==.',
In='Inafume:BAAANQADCggJEwAAAA==.Inoxia:BAAANQAECgQIDAAAAA==.Intrépidice:BAAANQAECgQIDAAAAA==.',
Ix='Ixtabay:BAABNQAECoEnAAQdAAkK2B/TAQAEAwAdAAkKtR3TAQAEAwAVAAMK3BfaOADTAAAUAAMKvQ2f9gCqAAAAAA==.',
Ja='Jamurra:BAAANQAECgIIBgABNQAECgQIBAAGAAAAAA==.Jaylinn:BAABNQAECoEhAAIQAAgKfwiOiwDCAQAQAAgKfwiOiwDCAQAAAA==.Jazzmend:BAAANQAECgQJBAAAAA==.',
Je='Jeanne:BAABNQAECoEfAAIQAAgKohm6QwB7AgAQAAgKohm6QwB7AgABNQAECgkJMQATAEoiAA==.Jellykins:BAAANQAECgYIEQAAAA==.',
Ji='Jimjamjuju:BAAANQAECgUICQAAAA==.Jimsonweed:BAAANQAECgUIDAAAAA==.',
Jo='Josie:BAAANQAECgYIDwAAAA==.Jozbirt:BAABNQAECoEmAAIeAAgK6hBaDgD2AQAeAAgK6hBaDgD2AQAAAA==.',
Ka='Kaeiria:BAAANQADCgQIBAAAAA==.Kael:BAAANQAECgYIDQAAAA==.Kalaanri:BAAANQAECgMIBQAAAA==.Kalyandra:BAAANQAECgUIDQAAAA==.Karlach:BAAANQADCgUIBQABNQAECggIGgASAGUXAA==.Karumie:BAABNQAECoEgAAIEAAgKoBXLSAATAgAEAAgKoBXLSAATAgAAAA==.Kateera:BAAANQADCgQIBAAAAA==.',
Ke='Keden:BAAANQADCgUICAAAAA==.Kelesa:BAAANQAECgEIAQAAAA==.Keljaden:BAABNQAECoEZAAMfAAcKPSRAOwDCAgAfAAcKPSRAOwDCAgAcAAEKdxtINgBMAAAAAA==.',
Kh='Kheyra:BAABNQAECoEYAAIDAAYKKiFyDgA+AgADAAYKKiFyDgA+AgAAAA==.',
Ki='Kirsha:BAAANQAECgQIBAAAAA==.Kittybeef:BAAANQABCgIIAgAAAA==.Kiwiiga:BAAANQAECgIIAwAAAA==.',
Kn='Knoxxic:BAAANQADCgMIBAAAAA==.',
Ko='Kohnor:BAAANQADCgUIEQAAAA==.Koopalizard:BAAANQAECgUIDwAAAA==.Kopi:BAAANQAECgYIEAAAAA==.Korlatt:BAAANQAECgYIEQAAAA==.Kowalabear:BAAANQAECgEIAQAAAA==.',
Ku='Kuaha:BAAANQADCgYIBgABNQADCgQIBAAGAAAAAA==.Kupa:BAAANQADCgYJBwAAAA==.Kurom:BAAANQADCgcJDQAAAA==.Kurston:BAABNQAECoEeAAIgAAcKqCCxFACAAgAgAAcKqCCxFACAAgAAAA==.',
Ky='Ky:BAAANQADCgEIAQAAAA==.',
['Kã']='Kãtniss:BAAANQADCgUIEAAAAA==.',
La='Labella:BAAANQADCgUICQAAAA==.Lacia:BAAANQADCgYIBgABNQAECgcIEAAGAAAAAA==.Laih:BAAANQAECgYIDAAAAA==.Landsong:BAAANQADCgQIBAAAAA==.',
Le='Leyote:BAABNQAECoEaAAIEAAcK5wtciQBEAQAEAAcK5wtciQBEAQAAAA==.',
Li='Liady:BAAANQADCgEJAQAAAA==.Lightshop:BAAANQADCgYICQAAAA==.Liirah:BAAANQADCgUIBwAAAA==.Lilyfox:BAAANQAECgYIEAAAAA==.Lindithrial:BAAANQABCggICAAAAA==.Livingdead:BAAANQADCggIJQAAAA==.',
Lo='Lorianne:BAAANQADCggJEAAAAA==.Lorraine:BAAANQADCgQIBAAAAA==.Lowdangle:BAAANQADCgcIBwAAAA==.',
Lu='Lulz:BAAANQAECggICAAAAA==.Luucifur:BAAANQABCgMIAwAAAA==.',
Ma='Mackpumpkin:BAAANQAECgIIAgAAAA==.Macktheknife:BAAANQADCgQICAABNQAECgkJJwAdANgfAA==.Madalyn:BAAANQADCgEIAQAAAA==.Magdelyne:BAAANQAECggICQAAAA==.Makklehaney:BAAANQAECgUIDQAAAA==.Mallaah:BAAANQADCgUIBQAAAA==.Marovingian:BAAANQAECgYIEwAAAA==.Matthad:BAAANQAECgYIEAAAAA==.',
Mc='Mcnastie:BAAANQAECgQIBgAAAA==.Mcsluts:BAAANQADCgYJCwAAAA==.',
Me='Melmirict:BAAANQADCgMJAwAAAA==.Merciala:BAABNQAECoEbAAMIAAcK4whGVwBPAQAIAAcK4whGVwBPAQAgAAYKPQJ5TgCiAAAAAA==.',
Mi='Milyyanna:BAAANQADCgUIEAAAAA==.Mirilla:BAAANQAECggIEQAAAA==.',
Mo='Moddoxx:BAAANQAECgYIEAAAAA==.Mohawk:BAAANQAECgcIDAAAAA==.Molen:BAAANQAECgEIAQAAAA==.Mommyjuice:BAAANQAECggIDgABNQAFFAYICgAQAOofAA==.Monkeeh:BAAANQADCgQIBAAAAA==.Monkle:BAABNQAECoEgAAIhAAgKqB5SEgCpAgAhAAgKqB5SEgCpAgAAAA==.Monohan:BAAANQADCgUIBQABNQAECgYIEwAGAAAAAA==.Moonsii:BAAANQAECgYIEgAAAA==.Mooroth:BAABNQAECoEZAAIcAAcKEhYNFAC4AQAcAAcKEhYNFAC4AQAAAA==.Morkilro:BAAANQABCgIIAgAAAA==.Morozko:BAAANQADCgQIBAAAAA==.',
Ms='Msasani:BAAANQADCgEIAQABNQAECgYIGAADACohAA==.',
Mu='Muddler:BAAANQAECgQIBgAAAA==.Muire:BAAANQADCggIDQABNQAECggIGgAUAJYhAA==.Murinn:BAABNQAECoEYAAIQAAcKoAjonwCUAQAQAAcKoAjonwCUAQAAAA==.',
['Mà']='Màggles:BAAANQAECgUIDAAAAA==.',
Na='Nadd:BAAANQAECgUIBwAAAA==.Naledi:BAAANQADCggIDQAAAA==.Naralyn:BAABNQAECoEhAAMbAAkKjBZPCwCmAgAbAAkK+RVPCwCmAgABAAUKwRFVnwAnAQAAAA==.',
Ne='Negrido:BAABNQAECoEhAAQUAAgKvSEuMwCiAgAUAAcK3CEuMwCiAgAVAAMKiBuDMgDwAAAdAAIKHxu7GAChAAAAAA==.Nei:BAABNQAECoEVAAIKAAYKvhPFuABzAQAKAAYKvhPFuABzAQAAAA==.Neon:BAAANQADCgUICQAAAA==.',
Ni='Nikem:BAAANQAECgQICAAAAA==.',
No='Noelle:BAAANQAECgUICQAAAA==.Norelei:BAAANQADCgYICwABNQAECgYIGAADACohAA==.Noriyuki:BAAANQAECgMICAAAAA==.',
Ny='Nyxahlia:BAAANQADCgUIBgAAAA==.',
Og='Oghom:BAAANQADCggICAAAAA==.Ogrekin:BAAANQAECgYIBgAAAA==.',
Ol='Olderon:BAAANQAECgUIDgAAAA==.Olrong:BAABNQAECoEaAAIiAAcK3AjXRQBfAQAiAAcK3AjXRQBfAQAAAA==.Oluja:BAAANQAECgQIDwAAAA==.',
On='Onuris:BAAANQAECgEIAgAAAA==.',
Oo='Oogiboogi:BAAANQAECgMIAwAAAA==.',
Op='Opacuslupus:BAAANQAECgQICQAAAA==.Oppressin:BAAANQAECgYIEwAAAA==.',
Os='Oshunn:BAABNQAECoEiAAIHAAkK/g/BowAaAgAHAAkK/g/BowAaAgAAAA==.Oshìe:BAABNQAECoEkAAIaAAgKfSClHQDmAgAaAAgKfSClHQDmAgAAAA==.Osroes:BAAANQAECgQIEgAAAA==.',
Ov='Overdoom:BAABNQAECoEhAAMCAAgKMh5zKAB3AgACAAgKMh5zKAB3AgAjAAUK4hFvTwAqAQAAAA==.Ovscur:BAABNQAECoEaAAMUAAYKliG+lgB9AQAUAAQKhyG+lgB9AQAVAAIKtCHvWwBlAAAAAA==.',
Pa='Pacolock:BAAANQADCggICAAAAA==.Paladinjohn:BAACNQAFFIEMAAIKAAUKZCF+BAD2AQAKAAUKZCF+BAD2AQA1AAQKgSUAAgoACQrYJSsNAI0DAAoACQrYJSsNAI0DAAAA.Palykat:BAAANQAECgMIBQAAAA==.Pandadeez:BAAANQADCgIIAgAAAA==.Papiroflz:BAABNQAECoEhAAMBAAkKICGrEABWAwABAAkKICGrEABWAwAEAAMKMxZ5xgCxAAAAAA==.',
Pe='Pennywisé:BAABNQAECoEcAAIjAAgKeCGQEQDjAgAjAAgKeCGQEQDjAgAAAA==.Pesttilence:BAAANQADCgQIBAAAAA==.',
Pl='Plaguegying:BAAANQAECgUIDgABNQAECgIIAgAGAAAAAA==.Ploofee:BAAANQAECgMIAwAAAA==.',
Pr='Preparedr:BAACNQAFFIElAAMSAAkK8CUBAAAABAASAAkKziUBAAAABAAFAAcKOiVPAADTAgA1AAQKgR0AAwUACQrTJeMHAPECAAUACAoQJuMHAPECABIABgrvJe8cAG0CAAAA.Progresz:BAAANQAECgEIAQAAAA==.',
Pu='Purebread:BAAANQADCgUIBQAAAA==.',
Py='Pykel:BAABNQAECoEgAAIIAAcKzwdqWQBEAQAIAAcKzwdqWQBEAQAAAA==.',
Qa='Qaren:BAAANQADCgYIEAAAAA==.',
Ra='Raishun:BAAANQAECgEJAQAAAA==.Raizo:BAAANQAECgEIAQAAAA==.Rake:BAABNQAECoEhAAIeAAgK3h/0BQDrAgAeAAgK3h/0BQDrAgAAAA==.Rannï:BAAANQADCgQIBAABNQAECgkJJwAdANgfAA==.Raskreia:BAAANQAECgYICgABNQAECgkJKAANAL0kAA==.Rassina:BAAANQADCgEIAQAAAA==.Rawk:BAAANQAECgEIAQAAAA==.',
Re='Redeemly:BAAANQAECgYIBgABNQAECgYIDgAGAAAAAA==.Reeven:BAAANQAECgcIFwAAAQ==.Revokely:BAAANQAECgYIDgAAAA==.',
Rh='Rhcpmage:BAAANQADCggICgABNQAFFAUIDQANAK8iAA==.Rhetegast:BAABNQAECoEkAAIkAAgKlBn9FAA0AgAkAAgKlBn9FAA0AgAAAA==.',
Ri='Rieloesh:BAAANQADCgYICQAAAA==.Rike:BAABNQAECoEZAAMKAAcKvxttbgAlAgAKAAcKdBttbgAlAgAkAAUKIhqgMAAwAQAAAA==.Ristretto:BAAANQADCgYICwABNQAECgYIEAAGAAAAAA==.',
Ro='Roland:BAAANQADCgUJBwAAAA==.Rolandin:BAABNQAECoEaAAIaAAcKiREEaQC2AQAaAAcKiREEaQC2AQAAAA==.',
Ru='Rukraga:BAAANQAECgQJBAAAAA==.',
Ry='Rylagosa:BAAANQAECgYIEwAAAA==.Ryzesmidge:BAAANQAECgcJDAAAAA==.',
['Rê']='Rêdrum:BAAANQAECgYIBgABNQAECggIIwAlABYaAA==.',
Sa='Salandria:BAABNQAECoEfAAQkAAgKiRrcEwBCAgAkAAgKEBrcEwBCAgAaAAUKSSRKUgAEAgAKAAEKZhVQbgE3AAAAAA==.Sarionian:BAAANQAECgUICgAAAA==.Sarjin:BAAANQADCgYIBgABNQAECgYIGAADACohAA==.Sarvinblue:BAABNQAECoEtAAMEAAkK6SAZDwA1AwAEAAkK6SAZDwA1AwABAAcKWBdbVwDwAQAAAA==.',
Sc='Scopolamine:BAAANQAECgQICAAAAA==.',
Se='Sevrin:BAABNQAECoEhAAIRAAgKuBIqQgDWAQARAAgKuBIqQgDWAQAAAA==.Seymonty:BAABNQAECoEcAAMYAAgKgg+ZDABZAQAOAAgK7AjvcgCLAQAYAAYKWhCZDABZAQAAAA==.',
Sh='Shaeko:BAAANQADCggIEgAAAA==.Shanir:BAAANQADCgIIAgABNQAECggIGgAUAJYhAA==.Shazlulu:BAAANQAECgMIBQAAAA==.Shaznoir:BAABNQAECoEeAAIVAAcK2AZHJgA4AQAVAAcK2AZHJgA4AQAAAA==.Shilajit:BAAANQAECgMIBgAAAA==.Shokz:BAAANQADCgMIAwABNQAECgMIAwAGAAAAAA==.',
Sk='Skip:BAAANQADCgcIBwAAAA==.Skøøma:BAAANQABCgIIBAAAAA==.',
Sl='Sloe:BAAANQAECgEIAQABNQAECgYIEQAGAAAAAA==.',
Sm='Smokalot:BAAANQADCggICAAAAA==.Smokehunter:BAAANQADCgYIBgAAAA==.',
Sn='Snoop:BAAANQADCgYICgAAAA==.',
So='Solstîce:BAAANQADCgQIBAABNQAECggIIwAlABYaAA==.',
Sp='Speedbeefbal:BAAANQADCgQIBgAAAA==.Speeddwrfbal:BAAANQADCgYIDQAAAA==.Speedmeat:BAAANQAECgcIDgAAAA==.Speedmonkbal:BAAANQADCggICwAAAA==.Speedoe:BAAANQADCgUIBwAAAA==.Spidêrs:BAAANQABCgQICAAAAA==.Sporkulous:BAABNQAECoEcAAIQAAcKQwh9ngCXAQAQAAcKQwh9ngCXAQAAAA==.',
Sq='Squal:BAAANQAECgYICQAAAA==.Squiggle:BAAANQAECgYIEAAAAA==.',
St='Steevii:BAAANQADCgMJAwAAAA==.Stewie:BAAANQAECgIIAwAAAA==.Striker:BAAANQADCgYIDwABNQAECgcIGQAKAL8bAA==.Strikers:BAAANQABCgIIAgAAAA==.',
Su='Sunshíne:BAAANQAECgUICAAAAA==.',
Sy='Syver:BAAANQAECgcIEAAAAA==.',
['Sí']='Sírlancealot:BAAANQADCgMIBAAAAA==.',
Ta='Takeke:BAAANQAECggIEgAAAA==.Takeroux:BAAANQAECgEIAQAAAA==.Talandroz:BAABNQAECoEdAAMXAAgKvhydDwCbAgAXAAgKvhydDwCbAgAmAAIKTAumMQBiAAAAAA==.Tanagra:BAAANQADCgIIAgABNQAECgYIEAAGAAAAAA==.Tankz:BAAANQADCgIIAgAAAA==.Tanner:BAACNQAFFIEGAAIQAAMKoQqcFQDeAAAQAAMKoQqcFQDeAAA1AAQKgSgAAhAACQpfHC80AK0CABAACQpfHC80AK0CAAAA.',
Te='Tebo:BAAANQAECgEIAgAAAA==.Tedman:BAAANQAECgYIEgAAAA==.Temel:BAABNQAECoEZAAIEAAcKAxAtcgCFAQAEAAcKAxAtcgCFAQAAAA==.Teostra:BAABNQAECoEYAAIQAAgKZR6HMQC1AgAQAAgKZR6HMQC1AgAAAA==.Testoecles:BAAANQADCgcICwABNQAECgEIAgAGAAAAAA==.',
Th='Thadrack:BAAANQAECgcIEAAAAA==.Thalonstin:BAAANQADCgUIEgAAAA==.Thaneold:BAAANQAECgQJCQABNQAECgkJJQAOAMgfAA==.Thassarian:BAAANQAECgQIBAABNQAECgYIEAAGAAAAAA==.Theodrid:BAACNQAFFIERAAIkAAUKpB+gAgDKAQAkAAUKpB+gAgDKAQA1AAQKgSYAAiQACQrXIqoGACQDACQACQrXIqoGACQDAAAA.Thunderstomp:BAAANQADCgIIAgAAAA==.',
Ti='Tinkerspell:BAAANQADCgYICwAAAA==.Tinkíe:BAABNQAECoEhAAIMAAgK2RvLDgBvAgAMAAgK2RvLDgBvAgAAAA==.Tirzahdozier:BAAANQAECgEIAQABNQAECgQIBAAGAAAAAA==.Tiwohnne:BAAANQADCggIGQAAAA==.',
Tl='Tla:BAAANQADCgUIDgAAAA==.',
Tp='Tpaartos:BAAANQADCgIJAgABNQAECgYIEAAGAAAAAA==.',
Tr='Treat:BAABNQAECoEZAAIPAAcKpyJTEwCwAgAPAAcKpyJTEwCwAgAAAA==.Trippyshock:BAAANQADCgEIAQABNQAFFAgIFAAUAK4eAA==.Tristitia:BAAANQABCgYICAAAAA==.',
Tu='Turkeltin:BAAANQAFFAEIAwAAAA==.',
Tw='Twiggle:BAAANQADCgYIBgABNQAECgQIBAAGAAAAAA==.Twistedsquid:BAAANQABCgQIBAAAAA==.',
Ty='Tyamat:BAAANQAECgYIEAAAAA==.Tyche:BAAANQADCgYIDAAAAA==.Tyrinara:BAAANQADCggICAAAAA==.',
Ui='Uiewedaoez:BAABNQAECoEhAAIgAAgKDCUqBgBNAwAgAAgKDCUqBgBNAwAAAA==.',
Va='Vains:BAABNQAECoElAAIKAAgK7RydTwB+AgAKAAgK7RydTwB+AgAAAA==.Valrith:BAAANQADCgcIGAAAAA==.',
Ve='Velexi:BAAANQABCggIEgAAAA==.Velody:BAAANQADCgQIAQAAAA==.Vendettuh:BAAANQADCgYIBgAAAA==.Veronica:BAAANQAECgYIDgAAAA==.Verren:BAAANQAECgYIEwAAAA==.Vesfor:BAAANQADCgEIAQABNQAECgMIBQAGAAAAAA==.Vestus:BAAANQABCgcIDAAAAA==.',
Vy='Vyrridyl:BAAANQAECgIIBgAAAA==.',
Wa='Waddlez:BAAANQAECgYIBgAAAA==.Watermark:BAABNQAECoEVAAIEAAcKYgqEjAA8AQAEAAcKYgqEjAA8AQAAAA==.',
We='Weeblewobble:BAAANQAECgEIAgAAAA==.Weltamus:BAAANQADCgYIEAAAAA==.Weltazar:BAAANQAECgYIDwAAAA==.Weltzilla:BAAANQAECgYIEAAAAA==.Westside:BAAANQAECgYICgAAAA==.',
Wh='Whoosh:BAABNQAECoEiAAIRAAgKiiKIEQAMAwARAAgKiiKIEQAMAwAAAA==.',
Wi='Wickët:BAABNQAECoEfAAMEAAgK5h9XJwCmAgAEAAgK5h9XJwCmAgABAAYKPiA2SQAlAgAAAA==.Wildtiger:BAAANQAECgYIEwAAAA==.',
Wo='Wolfslied:BAAANQADCgQIBAABNQADCgQIBAAGAAAAAA==.',
Wu='Wulfenhide:BAAANQAECgYIEQAAAA==.',
Wy='Wyzsky:BAAANQADCgUIFwABNQAECgcIGQAEAAMQAA==.',
Xa='Xalreth:BAAANQAECgYIEwAAAA==.Xaviana:BAAANQAECgUIBQAAAQ==.',
Ya='Yastypoo:BAABNQAECoEZAAIaAAgKphFuWADuAQAaAAgKphFuWADuAQAAAA==.',
Za='Zarieda:BAAANQAECgcIDQAAAA==.Zayrelia:BAACNQAFFIEJAAIgAAUKYAjtBgBlAQAgAAUKYAjtBgBlAQA1AAQKgSwAAyAACQrFGTEOANICACAACQrFGTEOANICAAgABgq0FjhLAI4BAAAA.',
Ze='Zelenor:BAAANQAECgEIAQABNQAECgYIEAAGAAAAAA==.',
Zu='Zud:BAABNQAECoEZAAICAAcKbR7EMgA+AgACAAcKbR7EMgA+AgAAAA==.',
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
