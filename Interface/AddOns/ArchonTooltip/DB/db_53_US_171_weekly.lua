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

local lookup = {'Hunter-Marksmanship','Evoker-Devastation','Paladin-Holy','Unknown-Unknown','Warrior-Arms','Warrior-Protection','DeathKnight-Unholy','Shaman-Elemental','Shaman-Restoration','Warrior-Fury','Paladin-Protection','Evoker-Preservation','Mage-Arcane','Mage-Frost','Druid-Balance','Priest-Holy','Priest-Discipline','Hunter-BeastMastery','Monk-Mistweaver','Paladin-Retribution','Druid-Guardian','Warlock-Destruction','Rogue-Assassination','Rogue-Outlaw','Rogue-Subtlety','DeathKnight-Blood','DemonHunter-Devourer','DemonHunter-Havoc','DeathKnight-Frost','Warlock-Demonology','Druid-Restoration',}
local provider = {region='US',realm='Onyxia',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abrams:BAAANQAECgUIDgAAAA==.',
Ad='Addý:BAAANQAECgcIDgAAAA==.',
Ae='Aethyra:BAAANQAECgUICQAAAA==.',
Ah='Ahimsa:BAABNQAECn8fAAIBAAkKvxH4IQA7AgABAAkKvxH4IQA7AgAAAA==.',
Ai='Ailisuuith:BAAANQAECgcIEQAAAA==.',
Al='Almamun:BAAANQADCgYICAAAAA==.',
Ar='Arcanemommy:BAAANQAECgEIAQAAAA==.Arcz:BAAANQAECgcIDQAAAA==.',
As='Ashenclaw:BAABNQAECn8rAAICAAkKiRiaCwCsAgACAAkKiRiaCwCsAgAAAA==.',
At='Athalena:BAAANQAECgQIBgABNQAECggIJwADAIgRAA==.',
Au='Auzatryx:BAAANQAECgUIBQAAAA==.',
Ba='Babs:BAAANQABCgIIAgABNQAECgYIEwAEAAAAAA==.Babyboo:BAAANQADCgcIFAAAAA==.Bamboom:BAAANQAECgEIAwAAAA==.',
Bi='Biggrnmonstr:BAABNQAECn8VAAMFAAcKfA40tQCSAQAFAAcKsAw0tQCSAQAGAAEKdRb2QgAyAAABNQAECgkJMQAHAKIgAA==.Bigxthezug:BAABNQAECn8bAAMIAAkKxh3wMgCqAgAIAAkKxh3wMgCqAgAJAAMKowXp9AB7AAAAAA==.',
Bl='Blaine:BAAANQADCgcIEgAAAA==.',
Bo='Bongripa:BAAANQABCgEIAQAAAA==.Bonquiqui:BAAANQADCgcIDAAAAA==.Boypartz:BAABNQAECn8hAAIFAAgKSBrDaQBQAgAFAAgKSBrDaQBQAgAAAA==.',
Br='Braidedbewbs:BAAANQAECgEIAQAAAA==.Breakfast:BAAANQADCgMIAwABNQAECgkJGwAIAMYdAA==.Brittinia:BAAANQAECgIIBAAAAA==.',
Bu='Bulbasaurus:BAABNQAECn8vAAIKAAkKkyY1AAD0AwAKAAkKkyY1AAD0AwAAAA==.Bus:BAACNQAFFH8VAAILAAYK/SD3AQArAgALAAYK/SD3AQArAgA1AAQKfyMAAgsACQrfJikAAAoEAAsACQrfJikAAAoEAAAA.',
By='Bylunn:BAAANQADCgEIAQAAAA==.',
Ca='Cactusjuicee:BAAANQAECgEIAQAAAA==.',
Ce='Celeres:BAABNQAECn84AAIMAAkKNRsLDQDUAgAMAAkKNRsLDQDUAgAAAA==.Celesdria:BAAANQADCgMIAwABNQAECgkJOAAMADUbAA==.Celys:BAAANQADCgIIAgAAAA==.Ceo:BAABNQAECn8ZAAMDAAcKEx4MRABTAgADAAcKEx4MRABTAgALAAUKCQ/0QgDkAAAAAA==.',
Ch='Chios:BAAANQAECgcIBwABNQABCgIIAwAEAAAAAA==.',
De='Deadcell:BAAANQAFFAEIAQAAAA==.Denamage:BAACNQAFFH8PAAMNAAUKDg0cJABeAQANAAUKDg0cJABeAQAOAAEKuwTRFQA8AAA1AAQKfyoAAw0ACQrVGIN8AIUCAA0ACQrVGIN8AIUCAA4ABQoiCbQmALkAAAAA.Denarrage:BAAANQAFFAEIAQAAAA==.',
Di='Disconnect:BAAANQABCgIJAwAAAA==.',
Do='Dontnerfspls:BAAANQAECgEIAQABNQAECgkJMQAHAKIgAA==.Doomtickle:BAAANQADCgYIBgAAAA==.',
Dr='Drakussy:BAAANQABCgMIAwABNQAECgYIEwAEAAAAAA==.',
Ea='Earthigga:BAAANQAECgUIBQAAAA==.',
Ei='Eichmann:BAAANQAECgIIAgAAAA==.',
El='Eldruida:BAACNQAFFH8FAAIPAAIKTgqqHwCSAAAPAAIKTgqqHwCSAAA1AAQKfy8AAg8ACQqkE/AzAEQCAA8ACQqkE/AzAEQCAAAA.Elixxi:BAAANQADCgYIBgAAAA==.Ellipsoro:BAAANQAECgUIEQAAAA==.Eltrol:BAAANQAECgEIAwAAAA==.',
En='Enoc:BAAANQADCgYIBgAAAA==.',
Er='Erale:BAAANQAECgEIAgAAAA==.',
Fa='Faeris:BAACNQAFFH8IAAIQAAUKEg2qEwBmAQAQAAUKEg2qEwBmAQA1AAQKfyMAAxAACQqFIdscAPwCABAACQqFIdscAPwCABEABAq/GXwPADEBAAAA.Fatalis:BAACNQAFFH8JAAMSAAQK7ASXFwD6AAASAAQK7ASXFwD6AAABAAEKAAB9KAAeAAA1AAQKfzAAAxIACQqeF4JKAIsCABIACQqeF4JKAIsCAAEAAQoAAHCWACgAAAAA.',
Fe='Fedqt:BAAANQAECgIIBAAAAA==.Felko:BAAANQADCgIIAgAAAA==.',
Fi='Fiestykitten:BAAANQAECgEJAQAAAA==.Fizaw:BAABNQAECn8jAAITAAkKTw1TGwDJAQATAAkKTw1TGwDJAQAAAA==.',
Fl='Floydmagussy:BAACNQAFFH8MAAINAAUKESBcGACwAQANAAUKESBcGACwAQA1AAQKfx8AAg0ACQphI4c2ABwDAA0ACQphI4c2ABwDAAAA.',
Fo='Foamdk:BAAANQADCggIBAAAAA==.',
Fr='Freezypuff:BAAANQADCggICAAAAA==.Frostee:BAAANQAECgEIAQAAAA==.Frøzen:BAAANQAECgQICwAAAA==.',
Fu='Fuzzydots:BAAANQADCgYIDQABNQAECgkJJgAUAB4cAA==.',
Ga='Gamu:BAAANQADCgMIAwAAAA==.Gaurr:BAABNQAECn8aAAIIAAcKbhPnagDcAQAIAAcKbhPnagDcAQAAAA==.',
Ge='Geneviere:BAAANQADCgMIAwAAAA==.',
Gi='Gianna:BAAANQAECgYICQAAAA==.Gislain:BAAANQADCgcIDQAAAA==.',
Go='Goldeye:BAAANQADCgYIEwAAAA==.',
Gr='Greyspirit:BAABNQAECn8sAAIVAAkKiyJBAwCFAwAVAAkKiyJBAwCFAwAAAA==.Grimothy:BAAANQAECggIEQAAAA==.',
Ha='Halcoldrek:BAAANQADCgQJBAAAAA==.',
Hb='Hbc:BAAANQAECgcIDAABNQABCgIIAwAEAAAAAA==.',
He='Healarious:BAAANQAECgYIBwAAAA==.Hembrota:BAAANQADCgcIEgAAAA==.Heyz:BAAANQAECgYIBwABNQAECgcIDQAEAAAAAA==.',
Hi='Himbo:BAAANQAECgUIEQAAAA==.',
Ho='Hogs:BAAANQAECgQIDgABNQAECgkJGwAIAMYdAA==.Holypoopp:BAABNQAECn8aAAMDAAkKLhv5JADVAgADAAkKLhv5JADVAgAUAAIKVwy+awFtAAAAAA==.Holyreturn:BAABNQAECn8mAAIDAAgKThxDLwCnAgADAAgKThxDLwCnAgAAAA==.',
Hw='Hwasin:BAAANQADCgQJBAABNQAECgcIDQAEAAAAAA==.',
Il='Illanyth:BAAANQADCgUIBQAAAA==.Illidaldin:BAAANQADCgYIBgABNQAECgkJKAAWAPcTAA==.',
Im='Imran:BAACNQAFFH8LAAILAAMK4xvuBwDjAAALAAMK4xvuBwDjAAA1AAQKfzYAAgsACQqyISIKAPcCAAsACQqyISIKAPcCAAAA.',
In='Inphyy:BAAANQAECgQIBgAAAA==.Inthelayer:BAAANQADCgYIBgABNQAECgkJGwAIAMYdAA==.',
Je='Jether:BAAANQAECgEIAQAAAA==.',
Jo='Jojobaggins:BAABNQAECn8iAAQXAAgK5B7NFgDCAgAXAAgK5B7NFgDCAgAYAAQKzxWrEAANAQAZAAEKYw/4TgA/AAAAAA==.',
Kc='Kcthegreat:BAAANQADCgQIBQAAAA==.',
Ke='Keyholes:BAACNQAFFH8bAAIaAAcKehwiAwBgAgAaAAcKehwiAwBgAgA1AAQKfx0AAhoACQrvIjIUAAgDABoACQrvIjIUAAgDAAE1AAEKAggDAAQAAAAA.Keyohs:BAAANQADCgcICAABNQABCgIIAwAEAAAAAA==.',
Ki='Kirky:BAAANQADCgUIBgAAAA==.',
Kk='Kkoda:BAAANQAECgIIAgAAAA==.',
Ko='Koal:BAABNQAECn8hAAISAAYK7RixogC8AQASAAYK7RixogC8AQAAAA==.Kodabear:BAAANQADCggICAAAAA==.',
Kr='Kraz:BAAANQADCgQJBAAAAA==.Kronos:BAAANQADCgYIBgABNQAECggIEgAEAAAAAA==.',
Ku='Kushage:BAAANQADCgMIAwAAAA==.',
['Kí']='Kírky:BAAANQADCgIIAwABNQADCgUIBgAEAAAAAA==.',
Le='Lettussy:BAACNQAFFH8RAAIXAAUK+CRHBQDWAQAXAAUK+CRHBQDWAQA1AAQKfywAAhcACQogJjgCALsDABcACQogJjgCALsDAAAA.',
Li='Lixxi:BAABNQAECn8pAAIQAAkKUxywJgDNAgAQAAkKUxywJgDNAgAAAA==.',
Lu='Luminyssa:BAAANQAECgQIBwAAAA==.',
['Lú']='Lúthien:BAAANQAECggIEQAAAA==.',
Ma='Maeby:BAAANQADCgYIBgAAAA==.Magicwater:BAACNQAFFH8SAAINAAUKECBMEwDYAQANAAUKECBMEwDYAQA1AAQKfykAAg0ACQr1IzYdAGMDAA0ACQr1IzYdAGMDAAAA.',
Me='Meeoowzer:BAABNQAECn8nAAIDAAgKehtKNgCIAgADAAgKehtKNgCIAgAAAA==.Meloo:BAAANQAECgYIEwAAAA==.',
Mo='Mollyflo:BAAANQAECgQICQAAAA==.Mollymauk:BAABNQAECn8nAAMDAAgKiBEJZgDjAQADAAgKiBEJZgDjAQAUAAgKHw0arADCAQAAAA==.Moorality:BAAANQAFFAIIAwABNQABCgIIAwAEAAAAAA==.Moretino:BAAANQADCgEIAQAAAA==.Morgane:BAAANQADCgEIAQAAAA==.Mothra:BAAANQAECgYIDQABNQAFFAQICAABAMIMAA==.',
Mu='Muhjo:BAAANQADCgYIDQAAAA==.Muppet:BAAANQAECgcICQAAAA==.Murryjane:BAAANQAECgYIDQABNQAECgcIDQAEAAAAAA==.Muufarmer:BAAANQAECgYICQAAAA==.',
Na='Natedk:BAAANQADCgUIBQAAAA==.',
Ne='Neyt:BAABNQAECn8oAAMbAAkKLh5VDAAaAwAbAAkKLh5VDAAaAwAcAAMKahEGcACzAAAAAA==.',
Ni='Nitesrider:BAAANQADCgcIBwAAAA==.',
No='Nora:BAACNQAFFH8eAAMUAAgKsh9xAAD5AgAUAAgKsh9xAAD5AgALAAEKAAD6DQBiAAA1AAQKfzkABBQACQrgJlUDAOIDABQACQreJlUDAOIDAAsABwqiJuwIAA0DAAMABwrJH0k7AHUCAAAA.Nostrodom:BAAANQADCgcIEQAAAA==.',
Nu='Nubbs:BAAANQAECgQICQAAAA==.Nubheala:BAAANQAECggIEgAAAA==.Nuri:BAABNQAECn8gAAINAAkK4h7GOgARAwANAAkK4h7GOgARAwAAAA==.',
Od='Odylight:BAAANQADCggICQAAAA==.',
Or='Orcazmo:BAAANQAECgcIDAAAAA==.',
Pa='Pandalorenzo:BAAANQADCgYIBwAAAA==.',
Pe='Peluij:BAAANQAECgQIBgAAAA==.',
Pi='Pingopango:BAAANQAECgYIDAABNQAECgkJGQADAMMZAA==.Pinkdefender:BAAANQAECgIIAgABNQAECgkJMQAHAKIgAA==.Pinpanpum:BAAANQAECgEIAQAAAA==.',
Po='Pokeumon:BAAANQADCggIEwAAAA==.Poosistrox:BAABNQAECn8xAAQHAAkKoiC2GgDqAgAHAAkKoiC2GgDqAgAdAAkKihFqPADXAQAaAAUK8hCMcwAkAQAAAA==.',
Ps='Pspspspsps:BAAANQAECgQIEQAAAA==.',
Pt='Ptheve:BAACNQAFFH8eAAIcAAgK2CVtAAA5AwAcAAgK2CVtAAA5AwA1AAQKfycAAhwACQr6Jl0CANADABwACQr6Jl0CANADAAAA.',
Qs='Qsham:BAAANQAECgUICAAAAA==.',
Qw='Qwarlock:BAABNQAECn8iAAMeAAgKuBcnggDcAQAeAAcKFRYnggDcAQAWAAEK5x/VYgBeAAAAAA==.',
Ra='Raela:BAACNQAFFH8HAAIdAAMK9RiyEQC5AAAdAAMK9RiyEQC5AAA1AAQKfyoAAh0ACAoGISwdAJ0CAB0ACAoGISwdAJ0CAAAA.Rahnarmight:BAAANQADCgMIAwAAAA==.Raygor:BAAANQAECgUIDAAAAA==.Razzle:BAAANQADCgIIAgABNQAECgkJIAANAOIeAA==.',
Ri='Rickthyr:BAAANQAECgUIDAAAAA==.Rigger:BAAANQADCgYJBgABNQAECgQIBQAEAAAAAA==.Rizzerz:BAAANQADCgcIBwAAAA==.',
Ro='Rosewalker:BAAANQAECgYIEAABNQAFFAUIEgANABAgAA==.Rosewall:BAAANQADCgIIAgABNQAFFAUIEgANABAgAA==.Rottgut:BAAANQADCgEIAQAAAA==.',
Ru='Rumog:BAAANQAECgUIDAAAAA==.',
Ry='Rykix:BAAANQADCgEIAQAAAA==.Rykò:BAABNQAECn8aAAISAAYKeBt5jgDpAQASAAYKeBt5jgDpAQAAAA==.',
Sa='Salmorg:BAABNQAECn8yAAMbAAkKXR/WEgDRAgAbAAgKax3WEgDRAgAcAAgK8h2WKQBPAgAAAA==.Sayafaed:BAABNQAECn8kAAIbAAkKgwpQKAD+AQAbAAkKgwpQKAD+AQAAAA==.',
Sc='Scalen:BAAANQADCgYIBgAAAA==.Scatback:BAABNQAECn8gAAIQAAkKmRyEHgD0AgAQAAkKmRyEHgD0AgAAAA==.Schwarzmagic:BAAANQADCggIEgAAAA==.',
Sh='Shilor:BAAANQAECgYIEAAAAA==.Shogun:BAAANQAECgIIBAAAAA==.Shortsnack:BAAANQABCgMJAwAAAA==.',
Si='Sicarii:BAAANQAECgcJEAAAAA==.Sicarrious:BAAANQADCggIEQABNQAECgcJEAAEAAAAAA==.Sinatra:BAABNQAECn8lAAIfAAkKAh4WCwAVAwAfAAkKAh4WCwAVAwAAAA==.',
Sk='Skyarc:BAAANQAECgIIBAABNQAECggIEwAEAAAAAA==.Skybolt:BAAANQAECgIIAgABNQAECggIEwAEAAAAAA==.Skylite:BAAANQAECggIEwAAAA==.Skyrak:BAAANQADCgQIBAABNQAECggIEwAEAAAAAA==.Skyrun:BAAANQAECgMIAQABNQAECggIEwAEAAAAAA==.',
Sn='Sneaksnstabs:BAAANQADCggICAABNQAECgkJMQAHAKIgAA==.',
So='Soulpurge:BAAANQADCgEIAQAAAA==.',
Sp='Splat:BAAANQAECgUIBgABNQAECgkJGgADAC4bAA==.Spoopy:BAAANQADCggICAAAAA==.Spënny:BAAANQAECgQIBQAAAA==.',
St='Stélle:BAABNQAECn8rAAIBAAgKng7ULgDTAQABAAgKng7ULgDTAQAAAA==.',
Su='Supdude:BAABNQAECn8oAAIZAAkKCRzLBwD9AgAZAAkKCRzLBwD9AgAAAA==.',
Sy='Sycoraxx:BAAANQABCgIIAgAAAA==.Sypha:BAAANQAECgQIBgAAAA==.',
Ta='Tatorz:BAAANQAECgQICAAAAA==.Tazbirkloa:BAAANQADCgUIDwAAAA==.',
Ti='Tigas:BAABNQAECn8fAAMFAAkKLB12PwDJAgAFAAkKLB12PwDJAgAKAAIKUSKGJACJAAAAAA==.',
To='Tooth:BAAANQADCgQIBQAAAA==.',
Tr='Trashdragon:BAABNQAECn8dAAICAAgKXh5fDACcAgACAAgKXh5fDACcAgAAAA==.Trashshaman:BAAANQAECgMIAwAAAA==.Trauma:BAAANQAECgEIAQAAAA==.',
Ty='Typhoonz:BAAANQADCgYIBgAAAA==.',
Ur='Uróboros:BAAANQADCgEIAQAAAA==.',
Vi='Vipex:BAAANQAECgEIAQAAAA==.',
Vo='Vore:BAAANQADCgYIBgAAAA==.',
Vy='Vynii:BAABNQAECn8eAAMcAAkKCBfxHgCeAgAcAAkKCBfxHgCeAgAbAAIK9gPzYwBTAAAAAA==.',
Wa='Wallofstars:BAAANQADCgQIBQAAAA==.Wardamage:BAAANQABCgEIAQAAAA==.Wasabi:BAAANQAECgUIEQAAAA==.',
Xa='Xaida:BAAANQAECgYICgABNQAFFAkJLQAMAL4QAA==.Xalant:BAAANQADCggICQAAAA==.',
Yo='Yourhammy:BAAANQADCgMIAwAAAA==.Yoyo:BAAANQAECgIJAgAAAA==.',
Yt='Ytteriul:BAAANQADCgYIEgAAAA==.',
Za='Zangyaku:BAABNQAECn8jAAIaAAgK7yVuCgBgAwAaAAgK7yVuCgBgAwAAAA==.',
Ze='Zenis:BAABNQAECn8ZAAIDAAkKwxkeJgDPAgADAAkKwxkeJgDPAgAAAA==.Zerocool:BAAANQADCgYIBgAAAA==.Zerø:BAAANQADCgIIAgAAAA==.Zetsuï:BAAANQAECgcIEgAAAA==.',
['ßa']='ßadfish:BAABNQAECn8dAAIUAAkKtiQxDgCTAwAUAAkKtiQxDgCTAwAAAA==.',
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
