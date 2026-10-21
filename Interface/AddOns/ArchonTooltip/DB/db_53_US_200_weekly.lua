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

local lookup = {'DeathKnight-Blood','Druid-Restoration','Warrior-Arms','Mage-Arcane','DeathKnight-Unholy','Warlock-Affliction','Shaman-Enhancement','Shaman-Elemental','Shaman-Restoration','Paladin-Retribution','Paladin-Protection','Priest-Holy','Monk-Brewmaster','Monk-Windwalker','Druid-Balance','Paladin-Holy','Hunter-BeastMastery','Warlock-Demonology','DemonHunter-Vengeance','DemonHunter-Havoc','Priest-Shadow','Unknown-Unknown','Evoker-Preservation','Evoker-Augmentation','Rogue-Outlaw','Warrior-Protection','Monk-Mistweaver','Rogue-Assassination','Warrior-Fury','DemonHunter-Devourer',}
local provider = {region='US',realm='Smolderthorn',name='US',type='weekly',zone=53,date='2026-10-20',data={Ai='Aitnd:BAAANQAECgMIAwAAAA==.Aitns:BAAANQADCgUIBgAAAA==.',
Al='Alaszun:BAAANQADCggICQAAAA==.Alorothius:BAAANQAECgYIDgABNQAECgkJHgABAPsFAA==.Alpacalypse:BAAANQADCggICAAAAA==.Altha:BAABNQAECn8yAAICAAoK4w1uKgDLAQACAAoK4w1uKgDLAQAAAA==.',
Am='Amilde:BAAANQADCggICQABNQAECgoKKwADACIbAA==.',
An='Anarisa:BAABNQAECn8sAAIEAAoKLRVXTAAjAQAEAAoKLRVXTAAjAQAAAA==.',
Ap='Appocolypto:BAAANQAECgUIBQAAAA==.',
Ar='Areese:BAAANQADCgUIAgAAAA==.Arës:BAAANQAECgEIAQAAAA==.',
Av='Averse:BAACNQAFFH8FAAIFAAMKTQ56CABVAAAFAAMKTQ56CABVAAA1AAQKfzQAAgUACgpzIl4JAHQDAAUACgpzIl4JAHQDAAAA.',
Ba='Balnor:BAABNQAECn8eAAIDAAcKVAogwQB6AQADAAcKVAogwQB6AQAAAA==.',
Bi='Bigbeef:BAAANQADCgEIAQAAAA==.',
Bo='Borgus:BAAANQAECgUJEgAAAA==.',
Br='Brimstone:BAAANQADCggIEAAAAA==.Brokemav:BAACNQAFFH8FAAIGAAQKIwuDAQA6AQAGAAQKIwuDAQA6AQA1AAQKfzIAAgYACgr9HLQBADIDAAYACgr9HLQBADIDAAAA.Brooklin:BAABNQAECn82AAIEAAoKmxUegQB8AgAEAAoKmxUegQB8AgAAAA==.',
Bu='Busky:BAABNQAECn8aAAQHAAkKxxJMGQDRAQAHAAgKXxFMGQDRAQAIAAUKYAu8ywD7AAAJAAMKCxFwhgBLAAAAAA==.',
Ca='Cao:BAABNQAECn8bAAMKAAoKMQvmqgDKAQAKAAoKMQvmqgDKAQALAAEKAABSgAAcAAAAAA==.Cassiopea:BAABNQAECn8yAAIMAAoKohutCQBLAgAMAAoKohutCQBLAgAAAA==.',
Ce='Cellcept:BAAANQADCgYIEAAAAA==.',
Ch='Chinchillada:BAAANQAECgUIDAAAAA==.Chows:BAAANQADCgYIBgABNQAECgoKKwADACIbAA==.Chre:BAAANQADCggICQAAAA==.',
Cl='Clafoutis:BAAANQAECgYICQAAAA==.Clanker:BAACNQAFFH8VAAINAAYKSxtDAwCVAQANAAYKSxtDAwCVAQA1AAQKfykAAw0ACgqDIaMDAFIDAA0ACgqDIaMDAFIDAA4AAQrAE/IyAEQAAAAA.',
['Cà']='Càss:BAAANQABCgEIAQABNQAECgoKMgAMAKIbAA==.',
Da='Dabajabaza:BAABNQAECn8eAAIBAAkK+wW8YwBjAQABAAkK+wW8YwBjAQAAAA==.Dabergerak:BAACNQAFFH8IAAIDAAMKjRvzIQDtAAADAAMKjRvzIQDtAAA1AAQKfxoAAgMACQpUG/ZSAJECAAMACQpUG/ZSAJECAAAA.Dakrus:BAAANQAECggIEgAAAA==.',
De='Deathntaxes:BAABNQAECn8WAAMFAAoK2hFcUgDJAQAFAAgKdBJcUgDJAQABAAIKoA3ouQBUAAAAAA==.Dejanira:BAABNQAECn8gAAMCAAoKKw45MQCQAQACAAoKKw45MQCQAQAPAAEK6AejuAAoAAAAAA==.Deyedrel:BAABNQAECn8gAAMQAAgKCRbWbADRAQAQAAgKCRbWbADRAQAKAAYKFAwCaQDzAAAAAA==.',
Di='Diddily:BAAANQAECgYICwAAAA==.',
Dr='Dridarok:BAAANQAECggIDwAAAA==.Drixfu:BAAANQADCgcIBwAAAA==.',
['Dé']='Déathkeng:BAAANQAECggICAAAAA==.',
El='Elise:BAAANQADCgUIBQABNQAECggIJwARAAkaAA==.Elstrid:BAABNQAECn8jAAISAAcKIhQ/PAAXAQASAAcKIhQ/PAAXAQAAAA==.',
Er='Eremisa:BAAANQADCggIDgABNQAECgoKLAAEAC0VAA==.Erros:BAAANQADCgQIBwAAAA==.',
Ev='Eve:BAACNQAFFH8UAAITAAYKTw+MAQB6AQATAAYKTw+MAQB6AQA1AAQKfyYAAhMACgqXHXAGALMCABMACgqXHXAGALMCAAAA.Evochre:BAAANQADCgcIDQAAAA==.',
Fa='Fantasy:BAABNQAECn8jAAIIAAkKOCbVDACBAwAIAAkKOCbVDACBAwAAAA==.',
Fe='Felbourn:BAABNQAECn8mAAIUAAoK1h0TAwBmAgAUAAoK1h0TAwBmAgAAAA==.Fendraim:BAAANQADCgMIBgAAAA==.',
Fi='Figurefour:BAAANQAECgIIAgAAAA==.',
Fl='Flaccidmass:BAAANQAECgQIBwAAAA==.',
Fo='Foedris:BAAANQAECgIIAgAAAA==.',
Fr='Frailboosy:BAACNQAFFH8JAAIKAAQKDBs9BwDtAAAKAAQKDBs9BwDtAAA1AAQKfyoAAgoACgq7H0NJALkCAAoACgq7H0NJALkCAAAA.',
Ga='Gaara:BAABNQAECn8XAAIIAAoKkBNVCwC5AQAIAAoKkBNVCwC5AQAAAA==.',
Ge='Gemini:BAABNQAECn8VAAIKAAgKlBUNiwAQAgAKAAgKlBUNiwAQAgAAAA==.',
Gl='Glitz:BAAANQAECgQICAABNQAFFAYIFAATAE8PAA==.',
Gr='Graamps:BAAANQAECgQIBQAAAA==.Gravedigger:BAABNQAECn84AAIBAAoKIR0GFgD9AgABAAoKIR0GFgD9AgAAAA==.',
['Gü']='Güts:BAABNQAECn8yAAIDAAkKKhYoNwA6AQADAAkKKhYoNwA6AQAAAA==.',
Ho='Holywagyu:BAAANQADCgcIBwAAAA==.Howlimer:BAAANQADCgEIAQAAAA==.',
Hu='Huf:BAAANQAECgMIAwABNQAFFAYIFQAVAH8PAA==.Husshh:BAAANQABCgMIAwAAAA==.',
Il='Illidanzs:BAAANQADCgcIBwABNQAECgQIBQAWAAAAAA==.',
Ir='Ironnmonk:BAAANQADCgYIBQABNQAECgUIBQAWAAAAAA==.',
Ja='Java:BAAANQADCgQIBgABNQAECgkJGgAHAMcSAA==.Jawshoeuh:BAAANQAECgEIAQAAAA==.',
Ju='Jujumon:BAAANQADCgYIBgABNQAECgUIBAAWAAAAAA==.Jujuzor:BAAANQAECgQICQAAAA==.Jujuzul:BAAANQAECgUIBAAAAA==.Justimp:BAABNQAECn8uAAISAAoKaxj9BwAoAgASAAoKaxj9BwAoAgAAAA==.',
Ka='Karlek:BAABNQAECn8mAAQKAAoKXg/nqADOAQAKAAgK8RHnqADOAQALAAQKEAXxHACqAAAQAAEK6Qt9HgE4AAAAAA==.Kassamella:BAAANQADCggJCAABNQAECgUIDAAWAAAAAA==.Kassanndra:BAEANQAECggJCAABNQAECgoKKAAKAKMZAA==.Kazeshiní:BAAANQADCgQIBAAAAA==.',
La='Lalana:BAAANQAECgUIBwAAAA==.Lan:BAAANQAECgUICgAAAA==.',
Li='Lilshorty:BAAANQAECgEIAQABNQAECgQIBQAWAAAAAA==.',
Lo='Lofwyr:BAABNQAECn8kAAMXAAoKAAvqJgCCAQAXAAgKIwnqJgCCAQAYAAcKfAgUEQAlAQAAAA==.',
Lu='Lumaie:BAABNQAECn8mAAMCAAoKuR4KDQD+AgACAAoKuR4KDQD+AgAPAAEKAAAhXwAAAAAAAA==.Lumistress:BAEBNQAECn8oAAIKAAoKoxllaQBgAgAKAAoKoxllaQBgAgAAAA==.',
Ly='Lynni:BAAANQADCgUIBQAAAA==.',
Ma='Maelstrom:BAAANQADCgYIBgAAAA==.Malcharion:BAAANQAECgQIBAAAAA==.Mamarue:BAAANQADCgYIBgAAAA==.',
Mc='Mcshâms:BAABNQAECn8fAAQIAAoKyhuWMwCrAgAIAAgKsB2WMwCrAgAHAAQK7g4UEgDjAAAJAAEKDRZ7iQBFAAAAAA==.',
Mu='Munir:BAAANQADCggIIQAAAA==.',
Na='Naeltian:BAABNQAECn8yAAIZAAoK/xvYAgAdAwAZAAoK/xvYAgAdAwAAAA==.',
Ne='Necromachine:BAACNQAFFH8HAAIFAAMKYh+BAQAoAQAFAAMKYh+BAQAoAQA1AAQKfzoAAgUACgrBIo8AABoDAAUACgrBIo8AABoDAAAA.Nevermore:BAABNQAECn8nAAIUAAoKZxvjFgDlAgAUAAoKZxvjFgDlAgAAAA==.',
No='Noctislucis:BAAANQABCgIIAgAAAA==.Noobdk:BAABNQAFFH8PAAIBAAYKiBryDACEAQABAAYKiBryDACEAQAAAA==.Noobmonkey:BAAANQADCgYIBgABNQAFFAYIDwABAIgaAA==.Noobwarr:BAABNQAECn8jAAMaAAkK8iT3AgB6AwAaAAkK8iT3AgB6AwADAAcKcRczmADgAQABNQAFFAYIDwABAIgaAA==.Novax:BAAANQAECgUIBwAAAA==.',
Ny='Nyquil:BAEANQAECggICAABNQAECgoKKAAKAKMZAA==.',
Ol='Oldreligion:BAAANQADCggICAAAAA==.',
Pe='Perugius:BAAANQADCgYICgABNQAECgcIIwASACIUAA==.',
Ph='Phrenulhum:BAAANQADCgcIBwAAAA==.',
Pr='Predmost:BAAANQABCgQIBAAAAA==.Prettypoison:BAABNQAECn8hAAIRAAcKBRLkOQBGAQARAAcKBRLkOQBGAQAAAA==.',
Pu='Pussehfart:BAAANQADCggJDAAAAA==.Putz:BAABNQAECn85AAITAAoK2hh7BgCxAgATAAoK2hh7BgCxAgAAAA==.Putzadin:BAAANQAECgIIAgAAAA==.',
Pw='Pwincess:BAAANQABCgIIAgAAAA==.',
Ra='Rainbow:BAABNQAECn8eAAIbAAkKRBbxFQAdAgAbAAkKRBbxFQAdAgABNQAECgkJIwAIADgmAA==.',
Re='Reialaleigh:BAABNQAECn8hAAIcAAgKSgtJQwC8AQAcAAgKSgtJQwC8AQAAAA==.',
Ry='Ryuk:BAAANQADCgMIAwAAAA==.',
Sa='Saberdiva:BAAANQAECggIDgAAAA==.Sabersidious:BAAANQADCgUIBQAAAA==.Sabpar:BAACNQAFFH8SAAMJAAYKUQlUCwCYAQAJAAYKUQlUCwCYAQAIAAUKlhWTDgCHAQA1AAQKfyIAAggACgrXH2koAOACAAgACgrXH2koAOACAAAA.Sabs:BAABNQAECn8YAAIFAAgKWx9jAQCbAgAFAAgKWx9jAQCbAgABNQAFFAYIEgAJAFEJAA==.Saladin:BAABNQAECn8eAAIDAAkK9xLrggAUAgADAAkK9xLrggAUAgAAAA==.Sanakht:BAABNQAECn8aAAIcAAkKiRbOIwBqAgAcAAkKiRbOIwBqAgAAAA==.',
Sc='Schweitzer:BAAANQAECgUIBAAAAA==.Scribblezz:BAAANQABCgMIBQAAAA==.',
Se='Seditionist:BAAANQADCgYIGAAAAA==.Serafina:BAAANQAECggIDAABNQAFFAYIFAATAE8PAA==.',
Sh='Shakira:BAAANQADCgYICwABNQAECggIIQAcAEoLAA==.Sheepd:BAAANQAECgcIDgABNQAFFAYIDwABAIgaAA==.',
Si='Sidewind:BAAANQAECgMIAwAAAA==.Sidthekid:BAAANQADCggIFwAAAA==.Sinayion:BAAANQAECgUIDAAAAA==.',
Sm='Smokestackz:BAAANQAECgEIAQAAAA==.',
Sn='Snepaí:BAABNQAECn8rAAIDAAoKIhv0NADuAgADAAoKIhv0NADuAgAAAA==.',
So='Sonamis:BAAANQAECgEIAQAAAA==.',
St='Stepdemonh:BAAANQADCgYIBgAAAA==.',
Su='Sunofthewar:BAAANQADCgQIBAAAAA==.',
Ta='Tankobell:BAABNQAECn8bAAIKAAgK+QyFugCoAQAKAAgK+QyFugCoAQAAAA==.',
Te='Terrible:BAEANQAECgEIAQABNQAFFAYICQAdABAOAA==.',
Th='Thañatos:BAABNQAECn8XAAMTAAkKYxUYBwAIAQATAAkKYxUYBwAIAQAeAAYKiwRQGQDiAAABNQAECgoKOAABACEdAA==.',
Tr='Truart:BAABNQAECn8fAAIKAAoKQxCggwAgAgAKAAoKQxCggwAgAgAAAA==.',
Tu='Tuerjoie:BAAANQAECgIIAwAAAA==.',
Va='Valesko:BAAANQADCgUIBQAAAA==.Varfus:BAAANQADCgYIDAABNQAECgoKFgAFANoRAA==.',
Ve='Veinglory:BAABNQAECn8iAAIBAAkKwR06KwBtAgABAAkKwR06KwBtAgAAAA==.Velentre:BAAANQAECgYIBgAAAA==.',
Vi='Vindictress:BAEANQAECggIBQABNQAECgoKKAAKAKMZAA==.',
Vo='Vonka:BAAANQADCgYIDwAAAA==.',
Wa='Walnut:BAAANQAECggICwAAAA==.',
Wi='Wigskid:BAAANQAECgQIBQAAAA==.Winney:BAAANQAECggIDQAAAA==.',
Wo='Wonkz:BAAANQABCgQIBwAAAA==.',
Wr='Wrequiem:BAAANQADCgUIBgAAAA==.',
Xh='Xhiaky:BAAANQADCgQIBAAAAA==.',
Xy='Xyran:BAAANQADCgYICgAAAA==.',
Yo='Yoyomba:BAAANQAECgcICwABNQAECgkJMgADACoWAA==.',
Ze='Zenderal:BAAANQADCgEIAQAAAA==.Zeposo:BAAANQAECgUIDwABNQAECgkJHQAJAFccAA==.Zeptide:BAABNQAECn8dAAMJAAkKVxwARgBJAgAJAAkKVxwARgBJAgAIAAIKPQW8IgFMAAAAAA==.',
['Zë']='Zëp:BAAANQAECgUIEgABNQAECgkJHQAJAFccAA==.',
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
