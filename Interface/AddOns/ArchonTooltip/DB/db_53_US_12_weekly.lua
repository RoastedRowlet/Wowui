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

local lookup = {'Mage-Frost','Mage-Arcane','Warlock-Demonology','Shaman-Enhancement','Shaman-Restoration','Shaman-Elemental','Priest-Shadow','Priest-Holy','Druid-Restoration','Paladin-Protection','Paladin-Retribution','Warrior-Fury','Warrior-Arms','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','Mage-Fire','DemonHunter-Vengeance','Druid-Balance','Monk-Windwalker','Warlock-Destruction','Druid-Guardian','DeathKnight-Blood','DeathKnight-Frost','Paladin-Holy','Evoker-Preservation','Warlock-Affliction','Unknown-Unknown','Hunter-BeastMastery','Hunter-Survival','Hunter-Marksmanship','Evoker-Devastation','DemonHunter-Devourer','DemonHunter-Havoc','Monk-Mistweaver','Monk-Brewmaster',}
local provider = {region='US',realm='Anetheron',name='US',type='weekly',zone=53,date='2026-11-17',data={Ab='Abcmico:BAABNQAECn9OAAMBAAoKWiVoAAB+AwABAAkKWiVoAAB+AwACAAoKHCLAIwCwAgAAAA==.',
Ae='Aelene:BAAANQABCgMIAwAAAA==.',
Al='Alacracity:BAABNQAECn8mAAIDAAoKEg7wZgCiAQADAAoKEg7wZgCiAQAAAA==.Alysari:BAABNQAECn8eAAICAAoKUBtZVwDRAgACAAoKUBtZVwDRAgAAAA==.',
An='Anoska:BAABNQAECn8eAAMEAAkKFQquFwCZAQAEAAkKFQquFwCZAQAFAAEKqgFyDgEfAAAAAA==.',
At='Atulock:BAAANQADCgUICQAAAA==.',
Av='Aviato:BAABNQAECn9VAAIGAAoKsR+aFQC+AgAGAAoKsR+aFQC+AgAAAA==.',
Az='Azimuth:BAACNQAFFH8LAAMHAAQKmQ4QDADWAAAHAAMKmQ4QDADWAAAIAAMK6g7nKQCNAAA1AAQKfyIAAwgACgpwG0QwAKcCAAgACgpwG0QwAKcCAAcAAwp0F9w4ANQAAAAA.',
Ba='Badaspen:BAABNQAECn8jAAIJAAkKJBooGQBzAgAJAAkKJBooGQBzAgAAAA==.Bankhala:BAACNQAFFH8HAAIKAAMK7A4qCQDAAAAKAAMK7A4qCQDAAAA1AAQKfycAAwoACQoCHa0PAKICAAoACQqmHK0PAKICAAsACQq/FSWSAAACAAAA.',
Be='Beefcake:BAACNQAFFH8IAAMMAAUKvxhHAQDlAAAMAAUKvxhHAQDlAAANAAEKYQlYPwBBAAA1AAQKf0YAAwwACgrOJOcBAHEDAAwACgq2JOcBAHEDAA0ABgpvHTW7AIkBAAAA.Belpep:BAAANQAECgMIAgAAAA==.',
Bi='Bigsneak:BAABNQAECn8eAAQOAAkKTx3NGAC5AgAOAAkKTx3NGAC5AgAPAAUKWBS5IwAQAQAQAAEKAACLGgA8AAAAAA==.',
Bo='Bobthra:BAAANQADCgYIBgAAAA==.Borgor:BAACNQAFFH8PAAICAAUK0xMxGgAjAQACAAUK0xMxGgAjAQA1AAQKfzUABAIACgpfIXFKAO0CAAIACgpfIXFKAO0CAAEAAgoVHlcmAKwAABEAAQp3GbILAEkAAAAA.',
Br='Brorommor:BAABNQAECn8gAAIPAAoKAherFACLAQAPAAoKAherFACLAQAAAA==.',
Bu='Bullvar:BAAANQAECgYIEAAAAA==.Bus:BAABNQAECn8yAAISAAoK/CUSAQCyAwASAAoK/CUSAQCyAwABNQAFFAoKNgAKAGAiAA==.',
Ca='Camarcus:BAAANQADCggJEQAAAA==.Canttoucthis:BAAANQADCggIIgAAAA==.Casaran:BAABNQAECn8uAAITAAoKeiCnEgAzAwATAAoKeiCnEgAzAwAAAA==.',
Ce='Cesio:BAAANQAECgEIBgABNQAFFAgIKgADAKsSAA==.',
Ch='Chukolord:BAAANQADCgIIAgAAAA==.',
Cl='Clapjuice:BAABNQAECn83AAIUAAoK6iAoDAAUAwAUAAoK6iAoDAAUAwAAAA==.',
Co='Cotilliôn:BAAANQAECgQICAAAAA==.Cowfish:BAAANQAECgUIBwAAAA==.',
Cr='Criticaltuna:BAABNQAECn8VAAMDAAgKyBwcYgAyAgADAAgKyBwcYgAyAgAVAAEKQwr9eAA1AAAAAA==.',
Cu='Cujô:BAAANQADCgIIAwABNQAECgoKWAAEAF8eAA==.',
Da='Danimal:BAAANQAECgYICwAAAA==.',
De='Deadmens:BAAANQADCgQIBwABNQAFFAUICAAWAF4WAA==.Deathknìght:BAABNQAECn8UAAMXAAcKsAppTgAEAQAXAAcKsAppTgAEAQAYAAEKSgL7wgAXAAAAAA==.Deathlyholow:BAAANQADCgcIBwAAAA==.Destinie:BAACNQAFFH8OAAIZAAYKHRa7CwChAQAZAAYKHRa7CwChAQA1AAQKfzUAAxkACgpPIAUTADkDABkACgpPIAUTADkDAAsAAwrhFNlGAYYAAAAA.Destiniedrag:BAACNQAFFH8KAAIaAAQKAg4gEQDVAAAaAAQKAg4gEQDVAAA1AAQKfyYAAhoACgq6GN8PAKsCABoACgq6GN8PAKsCAAE1AAUUBggOABkAHRYA.Destiniedrud:BAABNQAECn8YAAMJAAoKjxf4IAAhAgAJAAkKJBn4IAAhAgATAAMKZRGFawB9AAABNQAFFAYIDgAZAB0WAA==.Destiniepves:BAAANQADCgUIBgABNQAFFAYIDgAZAB0WAA==.',
Di='Disbearleaf:BAAANQAFFAIIAwAAAA==.',
Du='Duriniknight:BAAANQADCgUIBQAAAA==.',
Dy='Dynamicentry:BAACNQAFFH8GAAINAAIKmhU3KwCeAAANAAIKmhU3KwCeAAA1AAQKfx0AAg0ACQrdH6M6ANsCAA0ACQrdH6M6ANsCAAAA.',
['Dé']='Déllenna:BAAANQAECgEIAQAAAA==.',
El='Ellasandra:BAAANQAECgQICAAAAA==.Ellin:BAAANQAFFAMIAwAAAA==.Elokyria:BAABNQAECn88AAMDAAoKtCBiKADjAgADAAoKUSBiKADjAgAbAAQKPhqKFAABAQAAAA==.',
Em='Emiira:BAAANQADCgUIBQAAAA==.',
Es='Esme:BAAANQADCggIFwAAAA==.Estoile:BAAANQAECgYIBwAAAA==.',
Fa='Falkion:BAACNQAFFH8PAAINAAUK6hgeDwBXAQANAAUK6hgeDwBXAQA1AAQKfzEAAg0ACgp1IZcsAAoDAA0ACgp1IZcsAAoDAAAA.',
Fo='Folus:BAAANQAECgEIAQAAAA==.Folushunter:BAAANQADCgIIAgABNQAECgEIAQAcAAAAAA==.Foluslock:BAAANQAECgEIAQAAAA==.Foluspriest:BAAANQADCgIIAgABNQAECgEIAQAcAAAAAA==.',
Fu='Fuzzy:BAAANQAECgYIDQAAAA==.',
Go='Goldlight:BAAANQADCgYICAAAAA==.',
Ha='Haluseraph:BAAANQAECgUICwAAAA==.',
He='Hearthvader:BAAANQADCgYJBgAAAA==.Henrycavill:BAAANQADCgMIAwAAAA==.',
Hu='Huntardedd:BAACNQAFFH8LAAIdAAQKxQsqFwDZAAAdAAQKxQsqFwDZAAA1AAQKfzQABB0ACgqVHTwoAPcCAB0ACgqVHTwoAPcCAB4AAwoTCmUQAHMAAB8AAQqkCbmKADQAAAAA.',
Ig='Igorz:BAAANQADCgcIBwAAAA==.',
Io='Io:BAABNQAECn8sAAMHAAoKJxosEwDQAgAHAAoKJxosEwDQAgAIAAEKPwZdBwEkAAAAAA==.',
Ir='Irene:BAABNQAECn8wAAIBAAoKSxyfBQC0AgABAAoKSxyfBQC0AgAAAA==.Ironhawk:BAAANQADCgYIBgAAAA==.',
Is='Isnortcatnip:BAAANQADCgcIBwAAAA==.',
Iw='Iwasbubb:BAAANQADCgQIBAAAAA==.',
Jo='Johnblizard:BAAANQAECgMIBAAAAA==.Jolly:BAABNQAECn9LAAILAAoK1Q0IjQCyAQALAAoK1Q0IjQCyAQAAAA==.',
Jv='Jvblinkerton:BAAANQADCgEIAQAAAA==.',
Ka='Karina:BAAANQAECggICAAAAA==.Kayd:BAAANQADCgEIAQAAAA==.',
Ke='Kelm:BAAANQAECgcIEAAAAA==.',
Ki='Kimari:BAABNQAECn8VAAIUAAcK1hGTLwCaAQAUAAcK1hGTLwCaAQAAAA==.Kimiltonze:BAABNQAECn8kAAIVAAoKPxPcBAC5AQAVAAoKPxPcBAC5AQAAAA==.',
La='Lambpie:BAAANQAECgYICwABNQAFFAUICAAMAL8YAA==.',
Li='Limeaid:BAABNQAECn8oAAMgAAoKTB2CBACRAgAgAAoKTB2CBACRAgAaAAEKLwhIUQArAAABNQAFFAcIGQAIAPkXAA==.Limeylady:BAACNQAFFH8ZAAMIAAcK+Rf/DwCmAQAIAAcK+Rf/DwCmAQAHAAMKGBt4DQD/AAA1AAQKf1wAAwgACgoIInoQAEMDAAgACgoIInoQAEMDAAcACgpdHq4JAMUCAAAA.',
Lo='Loomis:BAABNQAECn8fAAMdAAcKBxRkjQDvAQAdAAcKBxRkjQDvAQAeAAIKAAB3EwA0AAAAAA==.',
Ma='Malvado:BAAANQADCgYICgABNQAFFAUICAAWAF4WAA==.Math:BAACNQAFFH8aAAMdAAgKThXZBQD1AQAdAAcKmxbZBQD1AQAfAAUKcg8zDgBaAQA1AAQKf1wAAx0ACgoQJsEBAOsDAB0ACgoQJsEBAOsDAB8ACAodH6cVALACAAE1AAQKCAgIABwAAAAA.',
Mi='Mini:BAAANQADCgQIBAAAAA==.',
Mo='Moofassa:BAACNQAFFH8IAAIWAAUKXhbzAQAvAQAWAAUKXhbzAQAvAQA1AAQKfxYAAxYABwrrGNEqADQBABYABwrrGNEqADQBABMAAQqRDfOuADgAAAAA.Moonshine:BAAANQAECgUIBwAAAA==.',
Ni='Nignoghvn:BAAANQAECggIDQABNQAECgoKJgADABIOAA==.Nizzie:BAAANQAECgQIBQAAAA==.',
No='Noodles:BAAANQADCgUIBQABNQAECgYIFAALAHUVAA==.',
Pa='Padfoot:BAAANQAECgQIBAABNQAECgYICQAcAAAAAA==.',
Ph='Phantomseal:BAAANQABCgEIAQAAAA==.',
Po='Polthelock:BAAANQABCggICAAAAA==.Polthepally:BAAANQABCggICwAAAA==.',
Pr='Prey:BAAANQAECgEIAQAAAA==.Prinny:BAABNQAECn8fAAMhAAoKwxcdEQBIAgAhAAoKwxcdEQBIAgAiAAIKDQrKgAB0AAAAAA==.',
Py='Pyreyn:BAAANQAECgQIBgAAAA==.',
Qu='Quikhealz:BAAANQAECgQIBAAAAA==.',
Rh='Rheolin:BAAANQAECgYIEgAAAA==.Rheolynx:BAABNQAECn8gAAIZAAoK2B2+KwB3AgAZAAoK2B2+KwB3AgAAAA==.Rheomei:BAAANQAECggIEQAAAA==.Rheomoon:BAABNQAECn9GAAIFAAoKECVDCQB3AwAFAAoKECVDCQB3AwAAAA==.',
Ri='Riptidz:BAABNQAECn9YAAIEAAoKXx5pBQDjAgAEAAoKXx5pBQDjAgAAAA==.',
Ro='Rookhrux:BAAANQAECgEIAQAAAA==.',
['Rø']='Røsenrøt:BAABNQAECn8gAAIUAAoKbhU/IwANAgAUAAoKbhU/IwANAgAAAA==.',
Sa='Saelydera:BAAANQABCggICgAAAA==.Saizan:BAABNQAECn8fAAIHAAoKERJhFwDvAQAHAAoKERJhFwDvAQAAAA==.Sanoth:BAAANQADCgcIGgAAAA==.',
Sh='Shamrock:BAAANQADCggICAAAAA==.',
Si='Silverthorn:BAAANQADCggICAAAAA==.',
Sn='Snöwflake:BAAANQADCgYIBgAAAA==.',
So='Solo:BAAANQAECgQIBQAAAA==.',
Sp='Spicytuna:BAEBNQAECn8pAAICAAoKyxwgSADzAgACAAoKyxwgSADzAgABNQAFFAUIEgAiAN0aAA==.',
St='Stabbed:BAAANQADCgMIAwABNQAFFAQICwAdAMULAA==.Stephanez:BAAANQADCgcIBwAAAA==.',
Sy='Syndara:BAAANQADCgUIBgAAAA==.',
Th='Theeight:BAABNQAECn8mAAIdAAkKah7MOQBmAgAdAAkKah7MOQBmAgAAAA==.',
To='Tornheart:BAABNQAECn8uAAIbAAoKXQ8ECADfAQAbAAoKXQ8ECADfAQAAAA==.',
Tr='Treyni:BAAANQADCgEIAQAAAA==.',
Tu='Tubby:BAABNQAECn8yAAMjAAoKYhcYFQApAgAjAAoKYhcYFQApAgAkAAQKTxOpIwC4AAAAAA==.Tulkas:BAABNQAECn8XAAIEAAgKKQ2iHQBEAQAEAAgKKQ2iHQBEAQAAAA==.',
Va='Vandel:BAAANQAECgEIAQAAAA==.',
Wa='Waynexiao:BAAANQADCgYIAwAAAA==.',
We='Wenddyy:BAAANQADCggICwAAAA==.',
Wy='Wyburn:BAAANQAECgEIAQAAAA==.Wyrm:BAAANQAECgYICQAAAA==.',
['Wå']='Wårlock:BAAANQAECgcIEgAAAA==.',
Yu='Yunibrow:BAAANQADCgMIAwAAAA==.',
['Yø']='Yøriçk:BAAANQAECgUICQAAAA==.',
Za='Zaraelina:BAAANQAECgEIAQAAAA==.',
Zi='Zil:BAAANQAECgQIBwAAAA==.',
['ßê']='ßêästÿßöÿ:BAAANQADCgcICgAAAA==.',
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
