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

local lookup = {'Hunter-Marksmanship','Evoker-Devastation','Paladin-Holy','DeathKnight-Unholy','Shaman-Elemental','Shaman-Restoration','Warrior-Arms','Warrior-Fury','Paladin-Protection','Evoker-Preservation','Unknown-Unknown','Mage-Arcane','Mage-Frost','Druid-Balance','Priest-Holy','Hunter-BeastMastery','Monk-Mistweaver','Paladin-Retribution','Druid-Guardian','Warlock-Destruction','Rogue-Assassination','Rogue-Outlaw','DeathKnight-Blood','DemonHunter-Devourer','DemonHunter-Havoc','DeathKnight-Frost','Warlock-Demonology','Druid-Restoration','Rogue-Subtlety',}
local provider = {region='US',realm='Onyxia',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abrams:BAAANQAECgQIDAAAAA==.',
Ad='Addý:BAAANQAECgcIDgAAAA==.',
Ae='Aethyra:BAAANQAECgUICQAAAA==.',
Ah='Ahimsa:BAABNQAECoEcAAIBAAgKoxTgIwAOAgABAAgKoxTgIwAOAgAAAA==.',
Ai='Ailisuuith:BAAANQAECgcIDgAAAA==.',
Al='Almamun:BAAANQADCgYICAAAAA==.',
Ar='Arcanemommy:BAAANQAECgEIAQAAAA==.Arcz:BAAANQAECgcIDAAAAA==.',
As='Ashenclaw:BAABNQAECoEiAAICAAkKQBiECgCsAgACAAkKQBiECgCsAgAAAA==.',
At='Athalena:BAAANQAECgQIBgABNQAECggIGgADAIgRAA==.',
Au='Auzatryx:BAAANQADCgQIBAAAAA==.',
Ba='Babyboo:BAAANQADCgcIEwAAAA==.Bamboom:BAAANQAECgEIAwAAAA==.',
Bi='Biggrnmonstr:BAAANQAECgQICwABNQAECgkJLQAEAD4fAA==.Bigxthezug:BAABNQAECoEbAAMFAAkK4Ry6KAC8AgAFAAkK4Ry6KAC8AgAGAAMKowW23wB9AAAAAA==.',
Bl='Blaine:BAAANQADCgcIEgAAAA==.',
Bo='Bongripa:BAAANQABCgEIAQAAAA==.Bonquiqui:BAAANQADCgcIDAAAAA==.Boypartz:BAABNQAECoEZAAIHAAcKJBhwfAABAgAHAAcKJBhwfAABAgAAAA==.',
Br='Braidedbewbs:BAAANQAECgEIAQAAAA==.Breakfast:BAAANQADCgMIAwABNQAECgkJGwAFAOEcAA==.Brittinia:BAAANQAECgIIBAAAAA==.',
Bu='Bulbasaurus:BAABNQAECoErAAIIAAkKeCYoAAD9AwAIAAkKeCYoAAD9AwAAAA==.Bus:BAACNQAFFIEVAAIJAAYKpiFpAQA4AgAJAAYKpiFpAQA4AgA1AAQKgRsAAgkACQpWJVQCAJ4DAAkACQpWJVQCAJ4DAAAA.',
Ca='Cactusjuicee:BAAANQAECgEIAQAAAA==.',
Ce='Celeres:BAABNQAECoEoAAIKAAkKsRlJDQC/AgAKAAkKsRlJDQC/AgAAAA==.Celesdria:BAAANQADCgMIAwABNQAECgkJKAAKALEZAA==.Celys:BAAANQADCgIIAgAAAA==.Ceo:BAABNQAECoEZAAMDAAcKEx4cOgBfAgADAAcKEx4cOgBfAgAJAAUKLQ2sOgDuAAAAAA==.',
Ch='Chios:BAAANQAECgYIBwABNQABCgIIAwALAAAAAA==.',
De='Deadcell:BAAANQAECggICwAAAA==.Denamage:BAACNQAFFIELAAMMAAUKvge8HgBPAQAMAAUKvge8HgBPAQANAAEKuwTfEQA+AAA1AAQKgSkAAwwACQqFGQlmAJ4CAAwACQqFGQlmAJ4CAA0ABQr9BqIhALwAAAAA.Denarrage:BAAANQAECgcIDQAAAA==.',
Di='Disconnect:BAAANQABCgIJAwAAAA==.',
Do='Dontnerfspls:BAAANQAECgEIAQABNQAECgkJLQAEAD4fAA==.Doomtickle:BAAANQADCgYIBgAAAA==.',
Dr='Drakussy:BAAANQABCgMIAwABNQAECgUIDQALAAAAAA==.',
Ea='Earthigga:BAAANQADCggIDAAAAA==.',
Ei='Eichmann:BAAANQAECgIIAgAAAA==.',
El='Eldruida:BAABNQAECoEqAAIOAAkKMBEMMQA0AgAOAAkKMBEMMQA0AgAAAA==.Elixxi:BAAANQADCgYIBgAAAA==.Ellipsoro:BAAANQAECgUIDQAAAA==.Eltrol:BAAANQAECgEIAwAAAA==.',
Er='Erale:BAAANQAECgEIAgAAAA==.',
Fa='Faeris:BAACNQAFFIEIAAIPAAUKEg0fDwB4AQAPAAUKEg0fDwB4AQA1AAQKgR4AAg8ACQqFIV8WAAkDAA8ACQqFIV8WAAkDAAAA.Fatalis:BAABNQAECoEtAAMQAAkKWBb4OwCSAgAQAAkKWBb4OwCSAgABAAEKngQuhgAoAAAAAA==.',
Fe='Fedqt:BAAANQAECgIIAgAAAA==.Felko:BAAANQADCgIIAgAAAA==.',
Fi='Fiestykitten:BAAANQAECgEJAQAAAA==.Fizaw:BAABNQAECoEgAAIRAAkKBQ1ZGADHAQARAAkKBQ1ZGADHAQAAAA==.',
Fl='Floydmagussy:BAACNQAFFIEKAAIMAAUKHx04EQDFAQAMAAUKHx04EQDFAQA1AAQKgR8AAgwACQqkIW4oADYDAAwACQqkIW4oADYDAAAA.',
Fo='Foamdk:BAAANQADCggIBAAAAA==.',
Fr='Freezypuff:BAAANQADCggICAAAAA==.Frostee:BAAANQAECgEIAQAAAA==.Frøzen:BAAANQAECgQICAAAAA==.',
Fu='Fuzzydots:BAAANQADCgYICQABNQAECggIIAASAKoUAA==.',
Ga='Gamu:BAAANQADCgMIAwAAAA==.Gaurr:BAAANQAECgYIEQAAAA==.',
Ge='Geneviere:BAAANQADCgMIAwAAAA==.',
Gi='Gianna:BAAANQAECgMIAwAAAA==.Gislain:BAAANQADCgcIDQAAAA==.',
Go='Goldeye:BAAANQADCgYIEwAAAA==.',
Gr='Greyspirit:BAABNQAECoEpAAITAAkKviKDAgCLAwATAAkKviKDAgCLAwAAAA==.Grimothy:BAAANQAECgcIDgAAAA==.',
Ha='Halcoldrek:BAAANQADCgQJBAAAAA==.',
Hb='Hbc:BAAANQAECgYICwABNQABCgIIAwALAAAAAA==.',
He='Healarious:BAAANQAECgEIAQAAAA==.Hembrota:BAAANQADCgcIEgAAAA==.Heyz:BAAANQAECgEIAQABNQAECgcIDAALAAAAAA==.',
Hi='Himbo:BAAANQAECgUIEQAAAA==.',
Ho='Hogs:BAAANQAECgQIDgABNQAECgkJGwAFAOEcAA==.Holypoopp:BAABNQAECoEYAAMDAAkKMxreHgDfAgADAAkKMxreHgDfAgASAAIKKA4SRAFvAAAAAA==.Holyreturn:BAABNQAECoEdAAIDAAcKtR1MNQBzAgADAAcKtR1MNQBzAgAAAA==.',
Hw='Hwasin:BAAANQADCgQJBAABNQAECgcIDAALAAAAAA==.',
Il='Illanyth:BAAANQADCgUIBQAAAA==.Illidaldin:BAAANQADCgYIBgABNQAECgkJIQAUAL8TAA==.',
Im='Imran:BAACNQAFFIEIAAIJAAMKfxZcBgDiAAAJAAMKfxZcBgDiAAA1AAQKgTIAAgkACQqUIJYHABADAAkACQqUIJYHABADAAAA.',
In='Inphyy:BAAANQAECgQIBAAAAA==.Inthelayer:BAAANQADCgYIBgABNQAECgkJGwAFAOEcAA==.',
Je='Jether:BAAANQAECgEIAQAAAA==.',
Jo='Jojobaggins:BAABNQAECoEaAAMVAAgKuhy6FgChAgAVAAgKuhy6FgChAgAWAAEKCQ5WGQA3AAAAAA==.',
Kc='Kcthegreat:BAAANQADCgQIBQAAAA==.',
Ke='Keyholes:BAACNQAFFIEaAAIXAAcKEh/UAQB3AgAXAAcKEh/UAQB3AgA1AAQKgRwAAhcACQr2IT8QABgDABcACQr2IT8QABgDAAE1AAEKAggDAAsAAAAA.Keyohs:BAAANQADCgcICAABNQABCgIIAwALAAAAAA==.',
Ki='Kirky:BAAANQADCgUIBgAAAA==.',
Kk='Kkoda:BAAANQAECgIIAgAAAA==.',
Ko='Koal:BAABNQAECoEbAAIQAAYKLRboiwDBAQAQAAYKLRboiwDBAQAAAA==.Kodabear:BAAANQADCggICAAAAA==.',
Kr='Kraz:BAAANQADCgQJBAAAAA==.Kronos:BAAANQADCgYIBgABNQAECgYICgALAAAAAA==.',
Ku='Kushage:BAAANQADCgMIAwAAAA==.',
['Kí']='Kírky:BAAANQADCgIIAgABNQADCgUIBgALAAAAAA==.',
Le='Lettussy:BAACNQAFFIENAAIVAAUKESFHAwDuAQAVAAUKESFHAwDuAQA1AAQKgSwAAhUACQolJloBAMwDABUACQolJloBAMwDAAAA.',
Li='Lixxi:BAABNQAECoElAAIPAAgKLR12LgCOAgAPAAgKLR12LgCOAgAAAA==.',
Lu='Luminyssa:BAAANQAECgQIBwAAAA==.',
['Lú']='Lúthien:BAAANQAECggIEAAAAA==.',
Ma='Madoka:BAAANQAECggIEQAAAA==.Maeby:BAAANQADCgYIBgAAAA==.Magicwater:BAACNQAFFIEOAAIMAAUKKR1cDwDXAQAMAAUKKR1cDwDXAQA1AAQKgSYAAgwACQqjI1MUAHwDAAwACQqjI1MUAHwDAAAA.',
Me='Meeoowzer:BAABNQAECoEiAAIDAAgKhBhSNgBvAgADAAgKhBhSNgBvAgAAAA==.Meloo:BAAANQAECgUIDQAAAA==.',
Mi='Mio:BAAANQAECgQIBAAAAA==.',
Mo='Mollyflo:BAAANQAECgQIBQAAAA==.Mollymauk:BAABNQAECoEaAAMDAAgKiBFKWADvAQADAAgKiBFKWADvAQASAAcKGgyPtQB6AQAAAA==.Moorality:BAAANQAFFAIIAwABNQABCgIIAwALAAAAAA==.Moretino:BAAANQADCgEIAQAAAA==.Morgane:BAAANQADCgEIAQAAAA==.Mothra:BAAANQAECgYICwABNQAECggIGQABABAUAA==.',
Mu='Muhjo:BAAANQADCgYIDQAAAA==.Muppet:BAAANQAECgIIAgAAAA==.Murryjane:BAAANQAECgYIDQABNQAECgcIDAALAAAAAA==.Muufarmer:BAAANQAECgQIBQAAAA==.',
Na='Natedk:BAAANQADCgUIBQAAAA==.',
Ne='Neyt:BAABNQAECoEhAAMYAAgKjx68FACpAgAYAAgKcx68FACpAgAZAAIKahF/cwBvAAAAAA==.',
Ni='Nitesrider:BAAANQADCgcIBwAAAA==.',
No='Nora:BAACNQAFFIEdAAMSAAgK/iArAAAMAwASAAgK/iArAAAMAwAJAAEK+COJCwBkAAA1AAQKgTEABBIACQrXJhQGAMADABIACQrKJhQGAMADAAkABwqdJkgHABYDAAMABwrJH1kzAHsCAAAA.Nostrodom:BAAANQADCgcIEQAAAA==.',
Nu='Nubbs:BAAANQAECgQICQAAAA==.Nubheala:BAAANQAECgcICgAAAA==.Nuri:BAABNQAECoEdAAIMAAgKgx8XUgDMAgAMAAgKgx8XUgDMAgAAAA==.',
Od='Odylight:BAAANQADCggICQAAAA==.',
Or='Orcazmo:BAAANQAECgUIBQAAAA==.',
Pa='Pandalorenzo:BAAANQADCgIIAgAAAA==.',
Pe='Peluij:BAAANQAECgQIBgAAAA==.',
Pi='Pingopango:BAAANQAECgYICwABNQAECgkJGQADAMMZAA==.Pinkdefender:BAAANQAECgEIAQABNQAECgkJLQAEAD4fAA==.Pinpanpum:BAAANQAECgEIAQAAAA==.',
Po='Pokeumon:BAAANQADCggIEwAAAA==.Poosistrox:BAABNQAECoEtAAQEAAkKPh+vFQD1AgAEAAkKgB2vFQD1AgAaAAkKnhE+MADrAQAXAAQKkg/ZiAC4AAAAAA==.',
Ps='Pspspspsps:BAAANQAECgQIDQAAAA==.',
Pt='Ptheve:BAACNQAFFIEdAAIZAAgK4CUsAABTAwAZAAgK4CUsAABTAwA1AAQKgSUAAhkACQr4JngBAN8DABkACQr4JngBAN8DAAAA.',
Qs='Qsham:BAAANQAECgUICAAAAA==.',
Qw='Qwarlock:BAABNQAECoEaAAMbAAgKLhRqeQDMAQAbAAcK8xNqeQDMAQAUAAEKyxVEagBBAAAAAA==.',
Ra='Raela:BAABNQAECoElAAIaAAgKeCCUFgCzAgAaAAgKeCCUFgCzAgAAAA==.Rahnarmight:BAAANQADCgMIAwAAAA==.Raygor:BAAANQAECgUIDAAAAA==.Razzle:BAAANQADCgIIAgABNQAECggIHQAMAIMfAA==.',
Ri='Rickthyr:BAAANQAECgUIDAAAAA==.Rigger:BAAANQADCgYJBgABNQAECgQIBQALAAAAAA==.Rizzerz:BAAANQADCgcIBwAAAA==.',
Ro='Rosewalker:BAAANQAECgYIEAABNQAFFAUIDgAMACkdAA==.Rosewall:BAAANQADCgIIAgABNQAFFAUIDgAMACkdAA==.Rottgut:BAAANQADCgEIAQAAAA==.',
Ru='Rumog:BAAANQAECgUIBwAAAA==.',
Ry='Rykix:BAAANQADCgEIAQAAAA==.Rykò:BAABNQAECoEaAAIQAAYKxxzJdQD2AQAQAAYKxxzJdQD2AQAAAA==.',
Sa='Salmorg:BAABNQAECoEqAAMZAAkK0B4SIgBkAgAZAAgKWB8SIgBkAgAYAAYKbhk7KgDQAQAAAA==.Sayafaed:BAABNQAECoEhAAIYAAkKQgzEIgAUAgAYAAkKQgzEIgAUAgAAAA==.',
Sc='Scalen:BAAANQADCgYIBgAAAA==.Scatback:BAABNQAECoEXAAIPAAgKqhtjMgB+AgAPAAgKqhtjMgB+AgAAAA==.Schwarzmagic:BAAANQADCggIEgAAAA==.',
Sh='Shilor:BAAANQAECgUIDAAAAA==.Shogun:BAAANQAECgIIAgAAAA==.Shortsnack:BAAANQABCgMJAwAAAA==.',
Si='Sicarii:BAAANQAECgcJEAAAAA==.Sicarrious:BAAANQADCggIEQABNQAECgcJEAALAAAAAA==.Sinatra:BAABNQAECoEbAAIcAAkKRBo5DQDfAgAcAAkKRBo5DQDfAgAAAA==.',
Sk='Skyarc:BAAANQAECgEIAwABNQAECggIEwALAAAAAA==.Skybolt:BAAANQAECgIIAgABNQAECggIEwALAAAAAA==.Skylite:BAAANQAECggIEwAAAA==.Skyrak:BAAANQADCgQIBAABNQAECggIEwALAAAAAA==.Skyrun:BAAANQAECgMIAQABNQAECggIEwALAAAAAA==.',
Sn='Sneaksnstabs:BAAANQADCggICAABNQAECgkJLQAEAD4fAA==.',
So='Soulpurge:BAAANQADCgEIAQAAAA==.',
Sp='Splat:BAAANQAECgUIBgABNQAECgkJGAADADMaAA==.Spënny:BAAANQAECgQIBQAAAA==.',
St='Stélle:BAABNQAECoEkAAIBAAgKDQ3jKwDIAQABAAgKDQ3jKwDIAQAAAA==.',
Su='Supdude:BAABNQAECoEhAAIdAAgKbx2bCwCsAgAdAAgKbx2bCwCsAgAAAA==.',
Sy='Sycoraxx:BAAANQABCgIIAgAAAA==.Sypha:BAAANQAECgMIAwAAAA==.',
Ta='Tatorz:BAAANQAECgQICAAAAA==.Tazbirkloa:BAAANQADCgUIDwAAAA==.',
Ti='Tigas:BAABNQAECoEeAAMHAAkKyBx7NQDWAgAHAAkKyBx7NQDWAgAIAAIKVxuiIACMAAAAAA==.',
To='Tooth:BAAANQADCgQIBQAAAA==.',
Tr='Trashdragon:BAABNQAECoEYAAICAAcK2R1bDgBdAgACAAcK2R1bDgBdAgAAAA==.Trauma:BAAANQAECgEIAQAAAA==.',
Ty='Typhoonz:BAAANQADCgYIBgAAAA==.',
Vi='Vipex:BAAANQAECgEIAQAAAA==.',
Vo='Vore:BAAANQADCgYIBgAAAA==.',
Vy='Vynii:BAABNQAECoEbAAMZAAkKdxiTGwCZAgAZAAkKdxiTGwCZAgAYAAIKxwRWWQBUAAAAAA==.',
Wa='Wallofstars:BAAANQADCgQIBQAAAA==.Wardamage:BAAANQABCgEIAQAAAA==.Wasabi:BAAANQAECgUIDAAAAA==.',
Xa='Xaida:BAAANQAECgYICgABNQAFFAgIKwAKAIwSAA==.Xalant:BAAANQADCggICQAAAA==.',
Yo='Yourhammy:BAAANQADCgMIAwAAAA==.Yoyo:BAAANQAECgIJAgAAAA==.',
Yt='Ytteriul:BAAANQADCgYIEgAAAA==.',
Za='Zangyaku:BAABNQAECoEbAAIXAAcKSSQvFwDdAgAXAAcKSSQvFwDdAgAAAA==.',
Ze='Zenis:BAABNQAECoEZAAIDAAkKwxm+HgDgAgADAAkKwxm+HgDgAgAAAA==.Zerocool:BAAANQADCgYIBgAAAA==.Zerø:BAAANQADCgIIAgAAAA==.Zetsuï:BAAANQAECgcIEgAAAA==.',
['ßa']='ßadfish:BAABNQAECoEcAAISAAgKNSV/GQBKAwASAAgKNSV/GQBKAwAAAA==.',
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
