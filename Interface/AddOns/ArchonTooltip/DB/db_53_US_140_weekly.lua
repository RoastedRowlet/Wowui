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

local lookup = {'Priest-Holy','Hunter-Survival','Priest-Discipline','DeathKnight-Blood','Druid-Restoration','Druid-Balance','DeathKnight-Unholy','Shaman-Elemental','Shaman-Restoration','Monk-Windwalker','Monk-Mistweaver','Unknown-Unknown','Priest-Shadow','Hunter-BeastMastery','Rogue-Assassination','Warrior-Fury','Warrior-Arms','Druid-Guardian','Druid-Feral','Warlock-Demonology','Monk-Brewmaster','Mage-Arcane','Paladin-Protection','Paladin-Retribution','DeathKnight-Frost','Mage-Frost','Rogue-Subtlety','Paladin-Holy',}
local provider = {region='US',realm='Lethon',name='US',type='weekly',zone=53,date='2026-10-27',data={Ad='Adam:BAAANQAECgIIAgABNQAFFAgIHQABAGUfAA==.',
Ae='Aerith:BAAANQAECgIIAgAAAA==.',
Ah='Ahirman:BAAANQAECgMIBgAAAA==.',
Ai='Aircondition:BAAANQADCgYIBgAAAA==.',
Al='Alilith:BAABNQAECn8qAAICAAoKxBfIAwDFAgACAAoKxBfIAwDFAgAAAA==.Aloha:BAACNQAFFH8dAAIBAAgKZR/LAQC4AgABAAgKZR/LAQC4AgA1AAQKf0AAAwEACgqrIrAHAGQDAAEACgqrIrAHAGQDAAMAAQolHmEhAFkAAAAA.',
Am='Amatsukaze:BAAANQAECgIIBAABNQAECgoKLAAEAB8TAA==.',
As='Asecretbear:BAABNQAECn87AAMFAAoKYR8ADgDxAgAFAAoKYR8ADgDxAgAGAAMKxQ97jgCdAAAAAA==.Asecretwolf:BAAANQADCgYIDgAAAA==.Ashvana:BAABNQAECn87AAIHAAoKuyS/DABUAwAHAAoKuyS/DABUAwAAAA==.',
Aw='Awsika:BAACNQAFFH8dAAMIAAgKoRVHBABUAgAIAAcKjRRHBABUAgAJAAEKZQIMIQBDAAA1AAQKfzEAAggACgoNJQgGACADAAgACgoNJQgGACADAAAA.',
Ba='Babaorhum:BAAANQABCgYIBgAAAA==.',
Be='Bennius:BAAANQAECgYIEwAAAA==.Benwarrior:BAAANQAECgcIDQABNQAFFAcIHAABALEUAA==.',
Br='Bradlee:BAABNQAECn8nAAMKAAoK+hNdHgA/AgAKAAkKzRZdHgA/AgALAAUKagtrIgCTAAAAAA==.Bricksyo:BAAANQAECgIIAgABNQAECgcIDwAMAAAAAA==.Bruycelee:BAAANQADCgUICQAAAA==.',
Bu='Buffÿ:BAAANQAECgEIAQAAAA==.',
Ci='Cinere:BAAANQAECgQIBwABNQAECgoKGgANAK0RAA==.',
Cr='Crazyeyes:BAAANQAECgQIDAAAAA==.Cromwyn:BAAANQAECgIIAQAAAA==.',
Cy='Cynestrya:BAABNQAECn81AAIOAAoKjRoZGACVAgAOAAoKjRoZGACVAgAAAA==.',
Da='Dagolad:BAAANQADCgQIBAAAAA==.Darkxan:BAAANQAECgQICAABNQAECggIKwAPAFYPAA==.',
De='Deadlyfire:BAAANQAECggIDgAAAA==.Decarabia:BAAANQAECggICQAAAA==.',
Do='Dog:BAACNQAFFH8bAAMQAAgKwxhSAAAkAgAQAAYKtx9SAAAkAgARAAYK7wlTKAC6AAA1AAQKf0AAAxEACgoAJmkCAHADABEACQrwJWkCAHADABAACQoNIe0DAAkDAAAA.',
Ev='Evíldead:BAAANQAECgYIDAAAAA==.',
Ex='Exjr:BAAANQAECgIIAwAAAA==.Exzavier:BAAANQAECgUIBQAAAA==.',
Fa='Faeng:BAACNQAFFH8KAAISAAMKMyUAAwBHAQASAAMKMyUAAwBHAQA1AAQKf3IAAxIACgpvJjcAAA8EABIACgpvJjcAAA8EABMABQqzEesoAMgAAAAA.Faengrove:BAAANQAECggIEAAAAA==.Fanah:BAAANQAECgQICgABNQAECgUIBgAMAAAAAA==.',
Fe='Felhoof:BAAANQAECggIEgAAAA==.',
Fl='Flamrage:BAAANQAECgMIBQAAAA==.',
Fr='Frive:BAAANQADCgYIBgAAAA==.Friveway:BAAANQAECgEIAgAAAA==.Frozswarrior:BAAANQAECgUICAAAAA==.',
Fu='Furuion:BAAANQAECgUIDgAAAA==.',
Gl='Gladerbug:BAAANQAECgcICwAAAA==.',
Gr='Grïndelwald:BAAANQAECgYIEwABNQAECgoKJwAKAPoTAA==.',
Gu='Gunz:BAAANQAECgMIBwABNQAECgoKFQAUAIUMAA==.',
Im='Imbesttank:BAAANQAECgEJAgAAAA==.',
In='Insideyuh:BAAANQAECgcIDwAAAA==.',
Is='Ishdragndeez:BAAANQAECgcIEAABNQAFFAgIHQAKAFEgAA==.Ishmonk:BAACNQAFFH8dAAMKAAgKUSCFAgBdAgAKAAgKUSCFAgBdAgAVAAEKAADMCgBLAAA1AAQKfz4AAgoACgoiJs4AAOsDAAoACgoiJs4AAOsDAAAA.',
Jc='Jcole:BAAANQAECgEIAgAAAA==.',
Je='Jenzzul:BAAANQAECgEJAQAAAA==.',
Jo='Jon:BAABNQAECn8qAAIWAAoK3xTfrwAjAgAWAAoK3xTfrwAjAgAAAA==.',
Ka='Kaivasyr:BAAANQADCgIIAgABNQAECgYIIQANAJsbAA==.Kalldroz:BAAANQADCgQIBAAAAA==.Karma:BAABNQAECn8WAAMXAAcKKgylIwDhAAAXAAYKKgylIwDhAAAYAAEKAAAGyAEkAAAAAA==.',
Ke='Kealee:BAABNQAECn8WAAIYAAcKOwuEsQD1AAAYAAcKOwuEsQD1AAAAAA==.',
Ki='Kirito:BAABNQAECn8wAAIRAAoKcgwfdAAvAQARAAoKcgwfdAAvAQAAAA==.',
Ko='Koroz:BAABNQAECn8qAAIEAAoKjRSNRQDkAQAEAAoKjRSNRQDkAQAAAA==.',
Li='Lifax:BAAANQAECgEIAQABNQAECgcICwAMAAAAAA==.Lifepriest:BAAANQAECgcICwAAAA==.Lifetide:BAAANQADCgIIAgAAAA==.Lifevoid:BAAANQADCgQIBwABNQAECgcICwAMAAAAAA==.Lithiria:BAAANQAECgUICAAAAA==.',
Lo='Lostwill:BAABNQAECn8rAAIZAAgKSA+GNABNAQAZAAgKSA+GNABNAQAAAA==.Lowparsepete:BAABNQAECn8oAAIWAAoKvgtcwgD/AQAWAAoKvgtcwgD/AQAAAA==.',
Ma='Maarsin:BAAANQAECgUIBQAAAA==.Malries:BAACNQAFFH8dAAMaAAgKNR+0AAC7AQAWAAUKsiOlEgDiAQAaAAYKLBm0AAC7AQA1AAQKfz0AAxYACgrBJuoOAJcDABYACgqpJeoOAJcDABoABAqnJuwKAFoBAAAA.Malriex:BAAANQAECggIEAABNQAFFAgIHQAaADUfAA==.Malspaladin:BAABNQAECn8VAAMYAAcK3yGMhwAYAgAYAAcKVR6MhwAYAgAXAAQKtyKiKwCAAQABNQAFFAgIHQAaADUfAA==.Markusmaximu:BAAANQADCgQIBAAAAA==.Marselli:BAAANQAECgEIAgAAAA==.',
Mo='Moonkin:BAABNQAECn8qAAIGAAoKagm8UwCLAQAGAAoKagm8UwCLAQAAAA==.',
My='Myrolor:BAAANQADCgYIBgAAAA==.',
Na='Narosar:BAAANQAECgMIBwAAAA==.',
Ne='Neferpitou:BAAANQADCgIIBAAAAA==.Nerodeath:BAAANQADCgMIAwAAAA==.',
Ni='Nick:BAAANQAECgYIEAABNQAFFAgIGwAQAMMYAA==.',
Pa='Padra:BAAANQADCgIIAgAAAA==.Pariston:BAAANQAECgQIBAAAAA==.',
Pe='Pena:BAAANQADCgMIAwAAAA==.Pepe:BAABNQAECn8VAAMOAAYKGiJShwD8AQAOAAYKGiJShwD8AQACAAIKIw8jEQBdAAAAAA==.',
Ph='Phatt:BAABNQAECn8dAAMPAAgKTREfSQCfAQAPAAYKEREfSQCfAQAbAAgK4w9fRwBBAQAAAA==.',
Pr='Priestfrive:BAAANQADCgcIBwAAAA==.',
Pu='Pum:BAABNQAECn9AAAMJAAoKQSR3BQCbAwAJAAoKQSR3BQCbAwAIAAEKAADz3wAAAAAAAA==.Pumdk:BAAANQAECgEIBQAAAA==.Pumdruid:BAAANQAECgMIAwAAAA==.Pumpally:BAAANQAECggIEwAAAA==.',
Pw='Pwnanub:BAABNQAECn8VAAITAAcKpA8UGgBdAQATAAcKpA8UGgBdAQAAAA==.',
Ra='Raffe:BAAANQAECgEIBQAAAA==.Raghnoll:BAABNQAECn8mAAIcAAkKcA/hWQALAgAcAAkKcA/hWQALAgAAAA==.',
Ru='Rustonn:BAAANQADCgcJBwAAAA==.',
Sa='Samon:BAAANQAECgEIAQAAAA==.Sartorius:BAABNQAECn8lAAIGAAkKQAhoWABzAQAGAAkKQAhoWABzAQAAAA==.Satiate:BAAANQADCgYICQAAAA==.',
Sc='Sciel:BAABNQAECn8oAAIIAAoK8x6kMAC4AgAIAAoK8x6kMAC4AgAAAA==.',
Se='Secretpally:BAAANQAECgIIBAAAAA==.',
Sh='Shamchilla:BAAANQAECgQIBAAAAA==.Shamfrive:BAAANQAECgEIAQAAAA==.Shaomei:BAAANQADCgMIAwAAAA==.Shynchan:BAABNQAECn8dAAMKAAoK5AUbOgBDAQAKAAoK5AUbOgBDAQAVAAEKaQMMNgAgAAAAAA==.',
Si='Siyen:BAAANQADCggICAAAAA==.',
So='Sojaslim:BAABNQAECn8aAAIOAAcK8w1YlwACAQAOAAcK8w1YlwACAQAAAA==.Solitjz:BAABNQAECn8aAAMNAAoKrRF5JAANAgANAAgKkhJ5JAANAgABAAUKWxx7fQDgAAAAAA==.',
Sp='Spankmcpp:BAAANQAECgEIAQAAAA==.Spenc:BAAANQADCgIIAQAAAA==.Splinterdikk:BAAANQADCgYIBgAAAA==.',
Su='Supanegroxy:BAAANQAECggIDgAAAA==.',
Ta='Tagmamon:BAAANQAECgMIBAABNQAFFAIIAgAMAAAAAA==.Tarias:BAAANQABCgUIBAAAAA==.',
Th='Thebook:BAAANQAECgMIAgAAAA==.',
To='Top:BAAANQAECgYIBgAAAA==.Topaten:BAABNQAECn8vAAIOAAoK1RLBcwApAgAOAAoK1RLBcwApAgAAAA==.',
Tw='Twerkraptor:BAAANQADCgYJBgAAAA==.',
Un='Unrealleet:BAAANQAECgMIBgAAAA==.',
Va='Valdania:BAAANQADCgEIAQAAAA==.Vap:BAAANQADCgEIAQAAAA==.Varissa:BAABNQAECn8sAAIEAAoKHxNCHgCfAQAEAAoKHxNCHgCfAQAAAA==.',
Vi='Virve:BAAANQAECgIIBQABNQAECgoKGgANAK0RAA==.',
Wa='Wanagargle:BAAANQADCgEIAQAAAA==.Water:BAAANQAECgEIAgAAAA==.',
Wr='Wrathchld:BAAANQAECgMIBwAAAA==.',
Xi='Xinbaobao:BAAANQADCgYIBgAAAA==.',
Za='Zalem:BAAANQAECgEIAQAAAA==.',
Ze='Zeba:BAAANQADCgYIBgAAAA==.',
['Àl']='Àlilith:BAAANQAECgMIAwABNQAECgoKKgACAMQXAA==.',
['Îm']='Îmmörtal:BAAANQAECgQICQAAAA==.',
['ßø']='ßøøm:BAAANQAECgUICQAAAA==.',
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
