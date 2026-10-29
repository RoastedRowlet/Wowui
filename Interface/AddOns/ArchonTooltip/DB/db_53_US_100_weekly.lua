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

local lookup = {'Hunter-BeastMastery','Warlock-Demonology','Druid-Restoration','Paladin-Retribution','Priest-Shadow','Unknown-Unknown','Hunter-Marksmanship','Paladin-Holy','Evoker-Devastation','Monk-Windwalker','Warrior-Protection','Warrior-Arms','Druid-Balance','Shaman-Elemental','Shaman-Enhancement','Evoker-Preservation','Shaman-Restoration','DeathKnight-Frost','DeathKnight-Unholy','DeathKnight-Blood','Druid-Guardian','Warlock-Affliction','Warlock-Destruction','Mage-Arcane','Rogue-Subtlety','Warrior-Fury','Hunter-Survival','DemonHunter-Havoc','DemonHunter-Vengeance','Rogue-Assassination','Priest-Holy','DemonHunter-Devourer','Evoker-Augmentation','Monk-Brewmaster','Paladin-Protection','Rogue-Outlaw','Mage-Frost','Priest-Discipline','Druid-Feral','Monk-Mistweaver',}
local provider = {region='US',realm='Frostwolf',name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aamodar:BAABNQAECn8fAAIBAAYK8BLqkQAOAQABAAYK8BLqkQAOAQAAAA==.',
Ab='Abadon:BAABNQAECn8bAAICAAcKhBkDTQB9AQACAAcKhBkDTQB9AQAAAA==.',
Ac='Acathisia:BAAANQAECgEIAQAAAA==.',
Ad='Adino:BAABNQAECn8jAAIBAAcKuAw8YwB3AQABAAcKuAw8YwB3AQAAAA==.Adorabell:BAAANQAECgcIDQABNQAFFAYIGQABAK8TAA==.Adric:BAAANQADCgIIAgAAAA==.',
Ae='Aerostar:BAABNQAECn8uAAIDAAkKvBpLEQARAgADAAkKvBpLEQARAgAAAA==.Aeryn:BAACNQAFFH8OAAIEAAUKhh2DDwBUAQAEAAUKhh2DDwBUAQA1AAQKfzgAAgQACgouI3gSAH4DAAQACgouI3gSAH4DAAAA.Aerís:BAAANQAECgQICQAAAA==.',
Ag='Aglaia:BAAANQAECgcICAAAAA==.Agrolazor:BAACNQAFFH8HAAIFAAMKwQoICwCUAAAFAAMKwQoICwCUAAA1AAQKfykAAgUACgrfFT4dAFgCAAUACgrfFT4dAFgCAAAA.',
Ah='Ahote:BAAANQAECggIDgAAAA==.Ahtee:BAABNQAECn8pAAIEAAoKRxIpUADFAQAEAAoKRxIpUADFAQAAAA==.',
Al='Alara:BAAANQAECgEIAQAAAA==.Albarino:BAAANQADCgYIBgAAAA==.Algodon:BAABNQAECn8ZAAIEAAgKCxaFwgCXAQAEAAgKCxaFwgCXAQABNQAFFAMIBQABAKodAA==.Alseena:BAAANQAECgQIBwAAAA==.',
Am='Amun:BAAANQAECgQIBQAAAA==.',
An='Andenarras:BAAANQAECgQIBAABNQAECgUIEgAGAAAAAA==.Anthais:BAAANQAECgUICgAAAA==.Anvar:BAACNQAFFH8HAAIBAAQKvAshEADKAAABAAQKvAshEADKAAA1AAQKfzwAAwEACgr4IN0OANgCAAEACgr4IN0OANgCAAcACAqiDn81AKIBAAAA.',
Ar='Arathion:BAABNQAECn8nAAIIAAkK8hxWEQDEAgAIAAkK8hxWEQDEAgAAAA==.Arcanemommy:BAAANQAECggIBAAAAA==.Archistrate:BAAANQADCgQIBAAAAA==.Ariandra:BAAANQADCggICAABNQAECgoKFwAJAMMXAA==.Arianrhod:BAACNQAFFH8GAAIKAAIKNBZwCQCSAAAKAAIKNBZwCQCSAAA1AAQKfx8AAgoACgpaIScIAE0DAAoACgpaIScIAE0DAAAA.Artamir:BAAANQABCgYIBgAAAA==.Arx:BAABNQAECn8lAAMLAAkKch75EQAHAgAMAAkKfhaGhwAJAgALAAcKrSD5EQAHAgAAAA==.',
As='Ashaldrin:BAAANQAECgEIBAAAAA==.Ashleyk:BAAANQAECgEIAQAAAA==.Aska:BAAANQADCgIIAgAAAA==.',
At='Atrumdeus:BAACNQAFFH8MAAIEAAUKpQmuDwDIAAAEAAUKpQmuDwDIAAA1AAQKfz4AAgQACgpTGnFhAHUCAAQACgpTGnFhAHUCAAAA.',
Au='Audiamer:BAABNQAECn8qAAINAAoK6gf1MwD/AAANAAoK6gf1MwD/AAAAAA==.Aufsela:BAAANQAECgEIAgABNQAECgoKFwAJAMMXAA==.',
Az='Azraelor:BAACNQAFFH8OAAMOAAUKXBojDgC/AAAPAAMKSBhEBAACAQAOAAUK2wYjDgC/AAA1AAQKf00AAw8ACgo1JC0CAA8DAA8ACgo1JC0CAA8DAA4ACgpJHCdLAEoCAAAA.Azureshal:BAABNQAECn8XAAIJAAoKwxcTBwC0AQAJAAoKwxcTBwC0AQAAAA==.',
Ba='Babydragon:BAACNQAFFH8GAAIQAAIKGwhYDgBtAAAQAAIKGwhYDgBtAAA1AAQKfykAAhAACgp4EoEYADUCABAACgp4EoEYADUCAAAA.Babysaja:BAAANQAECggIEgAAAA==.Bangerz:BAAANQAECggIDwAAAA==.Bannann:BAABNQAECn8eAAMRAAgKCR9MLQCtAgARAAgKCR9MLQCtAgAOAAEKAABeTgEnAAAAAA==.Baojai:BAAANQAFFAEIAQAAAA==.',
Be='Beaksbigdk:BAABNQAECn8wAAQSAAoKXSPfCQDKAgATAAkKACOZFQANAwASAAkKzh7fCQDKAgAUAAEKYyU3sABrAAAAAA==.Beefÿfridge:BAAANQADCggIFgAAAA==.Belfegor:BAAANQAECgcIDAAAAA==.Belldia:BAACNQAFFH8ZAAIBAAYKrxNgBwDZAQABAAYKrxNgBwDZAQA1AAQKf0AAAgEACgqzIgcUAE4DAAEACgqzIgcUAE4DAAAA.Belphaegor:BAABNQAECn82AAMVAAoK2xaCCgAZAgAVAAoK2xaCCgAZAgANAAUKpg0ycAAJAQAAAA==.Beni:BAABNQAECn8cAAIMAAkKFxjPNwD0AQAMAAkKFxjPNwD0AQAAAA==.Beniaru:BAABNQAECn8nAAICAAkKiBq5JQAgAgACAAkKiBq5JQAgAgAAAA==.Bennyflipz:BAAANQAECgcIEAAAAA==.',
Bi='Bigmuzz:BAAANQAECgEIBQAAAA==.Bigobuffalo:BAAANQAECgQICgAAAA==.Bigsneaki:BAAANQADCgUIBQAAAA==.',
Bl='Blightedmilk:BAABNQAECn8VAAQWAAgKghjhCgDlAAAWAAUKIRfhCgDlAAAXAAMKqBliEwB+AAACAAEKWRq41gBLAAABNQAECgoKQAAWAFYgAA==.Bloopmasta:BAAANQAECggICwAAAA==.Blufox:BAABNQAECn8yAAMEAAoKcxzFJQBtAgAEAAkK/B/FJQBtAgAIAAIKZgBQ3wAEAAAAAA==.',
Bo='Bobfresh:BAABNQAECn9KAAIOAAoK9SWoBwCrAwAOAAoK9SWoBwCrAwAAAA==.Bootwitdafur:BAAANQADCggIEAAAAA==.Bowtugger:BAAANQAECgQICAAAAA==.',
Br='Bracks:BAAANQAECgIIAgAAAA==.Braps:BAAANQAECgIIBgAAAA==.Brett:BAAANQAECgMIBQAAAA==.Brighamyoung:BAAANQAECggIBQAAAA==.Broherum:BAAANQAECgEIAQAAAA==.Bronzetusk:BAAANQAECgEIAgAAAA==.Brothalittle:BAAANQADCgIIAgAAAA==.Brush:BAAANQAECgEIAQAAAA==.',
Bu='Bubblêosêvên:BAAANQAECgYIDAAAAA==.Buc:BAAANQADCgIIBAAAAA==.Buckbeak:BAAANQADCggICAABNQAECgoKMAASAF0jAA==.Busting:BAABNQAECn8uAAIYAAoKqSGcJQBJAwAYAAoKqSGcJQBJAwAAAA==.',
By='Byusoaker:BAAANQAECgEIAQABNQAECggIGQAZAJEOAA==.',
['Bà']='Bàhamut:BAAANQAECgQICgAAAA==.',
['Bå']='Båemax:BAAANQADCgYIBgAAAA==.',
Ca='Camellieva:BAAANQAECgYICgABNQAECgkJJQADAL4eAA==.Captchaos:BAAANQAECgYIDwAAAA==.Carritha:BAAANQAECgMIAwABNQAECgMICgAGAAAAAA==.Cayo:BAAANQADCgQIBAAAAA==.',
Ce='Cewkie:BAABNQAECn8xAAIaAAoKDhNuBwCxAQAaAAoKDhNuBwCxAQAAAA==.',
Ch='Charlixchix:BAAANQADCggICAABNQAECggIGQAZAJEOAA==.Chimneybones:BAABNQAECn8dAAMMAAoKBQvtnwDNAQAMAAoKBQvtnwDNAQAaAAEKoQnRIgA2AAAAAA==.Chizz:BAABNQAECn8fAAIYAAkKKgvL0wDfAQAYAAkKKgvL0wDfAQAAAA==.Chriswong:BAAANQAECggIEAAAAA==.Chronoslicer:BAAANQABCgIIAgAAAA==.Chá:BAAANQADCggIEAABNQAECgoKNgATAEMjAA==.',
Cl='Clairebenet:BAABNQAECn81AAMBAAoKzRyuMADaAgABAAkK5R2uMADaAgAbAAoKfhYnAgBiAgAAAA==.Claymoor:BAAANQAECgQIBQAAAA==.Cleph:BAAANQAECgMICgAAAA==.Clumzylock:BAAANQAECgcIEwABNQAECgoKZQAUAEQYAA==.Clumzyninja:BAABNQAECn9lAAIUAAoKRBjPIQCnAgAUAAoKRBjPIQCnAgAAAA==.',
Co='Colonoscope:BAAANQAECgIIAgABNQAECgYICQAGAAAAAA==.Coolbreez:BAAANQAECgYIEAAAAA==.Coolynn:BAAANQAECgMIBgAAAA==.Corl:BAAANQADCgIJAgAAAA==.',
Cr='Crazywar:BAEANQADCgYIDAAAAA==.Creams:BAAANQAECgIIBAABNQAECgQIBwAGAAAAAA==.Crew:BAAANQADCggICgAAAA==.Cronoth:BAAANQAECgUIBQAAAA==.',
Cu='Cumb:BAABNQAECn8VAAMcAAgKQhgBHwCfAQAcAAcKhBcBHwCfAQAdAAIKkBp6JACbAAABNQAECgoKSgAOAPUlAA==.',
Cy='Cyrothea:BAAANQAECgIIAgAAAA==.',
['Cä']='Cäldius:BAAANQAECgYIBwAAAA==.',
Da='Daenerys:BAAANQADCgEIAQAAAA==.Daioh:BAAANQAECgYIDAAAAA==.Damacraze:BAABNQAECn8yAAIBAAoKyR7dJwD4AgABAAoKyR7dJwD4AgAAAA==.Damien:BAAANQAECgEIAQAAAA==.Danielwu:BAABNQAECn8ZAAMWAAkKQAwyGQC/AAACAAkKkwudpgCHAQAWAAMKcxAyGQC/AAAAAA==.Dawigrund:BAAANQAECgYIEgAAAA==.',
De='Deadroar:BAABNQAECn8XAAIUAAgKfxXzTgC5AQAUAAgKfxXzTgC5AQABNQAFFAEIAQAGAAAAAA==.Deadtomato:BAABNQAECn8aAAMeAAkK4iEyGAC7AgAeAAgKCSAyGAC7AgAZAAcKYxtzKQDeAQAAAA==.Deadwill:BAABNQAECn8eAAIZAAcK4A+iTgAiAQAZAAcK4A+iTgAiAQAAAA==.Deadzug:BAAANQAECgUIBQABNQAFFAQIBwABALwLAA==.Deaminase:BAABNQAECn8kAAIYAAkKaxgCUgC4AQAYAAkKaxgCUgC4AQAAAA==.Deathknell:BAAANQADCgcIBwAAAA==.Decypher:BAABNQAECn8vAAIfAAoKXBrYLAC1AgAfAAoKXBrYLAC1AgAAAA==.Deggle:BAAANQAECgEIAQAAAA==.Delphoxx:BAABNQAECn8ZAAIRAAYKpBzlPQCgAQARAAYKpBzlPQCgAQAAAA==.Demidru:BAABNQAECn8fAAINAAcKnBS5KQA6AQANAAcKnBS5KQA6AQAAAA==.Demonshot:BAAANQADCgUIBAAAAA==.Depleterpann:BAAANQADCgQICAABNQAECgMIBgAGAAAAAA==.Derovia:BAAANQAECggIDgAAAA==.Deshojo:BAAANQAECgUIEQAAAA==.Desrook:BAAANQAECgQIDAAAAA==.',
Dh='Dhqt:BAAANQAECgEIAwABNQAECgQIBwAGAAAAAA==.',
Di='Diablominion:BAAANQAECgUIDgAAAA==.Divinèhero:BAABNQAECn8XAAIcAAcKjgz8NgD6AAAcAAcKjgz8NgD6AAAAAA==.',
Do='Doomgirl:BAAANQAECgIIAgAAAA==.Double:BAAANQAECgUICQAAAA==.Doublelift:BAABNQAECn8wAAMFAAoK9x6MEQDjAgAFAAkKfB6MEQDjAgAfAAQKyxZmqgAXAQAAAA==.',
Dr='Draghula:BAAANQAECgEIAgAAAA==.Dragondeznut:BAAANQADCggJDgAAAA==.Drakisara:BAAANQADCggIBgABNQAECgcIFAAIACEgAA==.Drakuul:BAAANQADCgUIBwAAAA==.Droni:BAABNQAECn8iAAMgAAgKhRWjJwAHAgAgAAgKhRWjJwAHAgAcAAEKAADSjgA9AAAAAA==.Drpumper:BAAANQAECgIIAgABNQAECgQIBwAGAAAAAA==.Drummer:BAAANQADCgIIAgAAAA==.Dröbi:BAACNQAFFH8UAAMhAAcK+hJYBACYAQAhAAUK+BZYBACYAQAJAAUKmRB7BgA3AQA1AAQKfy0AAwkACgqvIS4IAPgCAAkACQprIS4IAPgCACEABgoGGiQKAOsAAAAA.',
Du='Duberagon:BAAANQADCgQIBAAAAA==.Dumbledork:BAAANQAECgEIAQAAAA==.Dundundun:BAAANQAECggIEwAAAA==.',
Dv='Dvrkwolf:BAAANQADCgcIDAAAAA==.',
['Dâ']='Dârkdune:BAAANQAECgcICwAAAA==.',
Eg='Eggdrop:BAABNQAECn8bAAIaAAkKuh0IBwCOAgAaAAkKuh0IBwCOAgAAAA==.Egufro:BAABNQAECn8gAAMIAAoKnRFYHQBZAgAIAAoKnRFYHQBZAgAEAAQKkASKCwFwAAABNQAECgoKQgAPAIUYAA==.',
Eh='Ehgu:BAABNQAECn9CAAIPAAoKhRiFCAAvAgAPAAoKhRiFCAAvAgAAAA==.',
El='Eleaya:BAAANQADCggIDwAAAA==.Eleverclear:BAAANQADCgYIBgAAAA==.Eliizabeth:BAABNQAECn8VAAIEAAcK1gcv8QA6AQAEAAcK1gcv8QA6AQAAAA==.Elynnah:BAAANQAECgIIAgAAAA==.Elysiawaters:BAEANQADCggICAAAAA==.',
Em='Emidget:BAAANQAECgEIAgAAAA==.',
En='Endervish:BAAANQADCgIIAgABNQAECgMICgAGAAAAAA==.Enyalio:BAAANQADCgYICwAAAA==.',
Ep='Epicaecin:BAAANQAECgIICAAAAA==.',
Er='Erhmer:BAAANQAECggIBQAAAA==.Ericrog:BAAANQAECgEIAQAAAA==.Ericwym:BAAANQAECgEIAwAAAA==.',
Et='Ethersong:BAAANQADCgIIAgAAAA==.Etom:BAAANQAECggIDAAAAA==.',
Ev='Eviae:BAAANQAECgQICgAAAA==.',
Fa='Faaith:BAAANQADCgIIAgAAAA==.Faceroll:BAAANQAECgIIAgAAAA==.Fairyhunter:BAAANQAECgQICAAAAA==.Fairymonk:BAAANQAECgQIBwAAAA==.Fangrat:BAAANQAECgEIAgABNQAECgQIBwAGAAAAAA==.Fatfatfat:BAAANQAECgMIBwABNQAFFAEIAQAGAAAAAA==.Fañgrat:BAABNQAECn8aAAMIAAoKYxnJPwBlAgAIAAoKYxnJPwBlAgAEAAQKGQevSQGqAAABNQAECgQIBwAGAAAAAA==.',
Fe='Femboyluvr:BAABNQAECn8UAAIMAAgKMhC5eQAiAQAMAAgKMhC5eQAiAQAAAA==.',
Fi='Filumena:BAAANQAECgMIAwAAAA==.Finch:BAAANQABCgQIBgAAAA==.',
Fl='Flameblue:BAAANQADCgQIBAAAAA==.Flandia:BAABNQAECn8oAAIBAAoKWhnEQQClAgABAAoKWhnEQQClAgAAAA==.Flex:BAAANQAECgQIBAAAAA==.Floppiterry:BAABNQAECn8bAAIBAAYKow4ZwwB8AQABAAYKow4ZwwB8AQAAAA==.Floppyterri:BAAANQADCgYIBgAAAA==.Floppyterry:BAAANQAECgIIAgAAAA==.Flow:BAABNQAECn8qAAIiAAoKoxgUCQCTAgAiAAoKoxgUCQCTAgAAAA==.',
Fo='Forduecezero:BAAANQADCgYIBgAAAA==.Fowl:BAABNQAECn8oAAIgAAoK1BkhGgCIAgAgAAoK1BkhGgCIAgAAAA==.Foxyshaman:BAAANQAECgQIBQAAAA==.',
Fr='Fricher:BAABNQAECn8kAAITAAkKLBOuHACPAQATAAkKLBOuHACPAQAAAA==.',
Fy='Fylerianprie:BAAANQAECgIIBQAAAA==.Fyleriansham:BAAANQADCgMIAwAAAA==.',
Ga='Gagli:BAAANQAECgEIAgAAAA==.Galathynius:BAAANQAECgQIBwAAAA==.Galelora:BAAANQADCggICAAAAA==.Ganjja:BAAANQADCggIGAAAAA==.Gawk:BAAANQADCgUICwABNQAECgQIBwAGAAAAAA==.',
Ge='Geneman:BAAANQABCgYIDAAAAA==.Getsyouwet:BAAANQAECgIIAwABNQAECgoKMAASAF0jAA==.Getter:BAAANQADCgkJFQAAAA==.',
Gh='Ghettomike:BAAANQAECgQIBAAAAA==.',
Gi='Giny:BAABNQAECn8hAAMOAAoK2RT5XwACAgAOAAkK2RT5XwACAgARAAIKRgFKHAE0AAAAAA==.',
Gl='Glowfungus:BAAANQAECgEIAgAAAA==.',
Go='Gobbledeez:BAABNQAECn8cAAIRAAkKmCGIDABcAwARAAkKmCGIDABcAwAAAA==.Gobblez:BAAANQAECgQICgAAAA==.Gorvash:BAAANQADCgIIAgAAAA==.Gosulock:BAAANQAECggICQABNQAECgoKIgABAHkiAA==.Govinniuur:BAAANQAECgIJBAAAAA==.',
Gr='Grasfedjones:BAAANQAECgQIDAAAAA==.Gravelord:BAAANQAECgEIAQAAAA==.Grizzy:BAABNQAECn8vAAIcAAoKPxzfCgCgAgAcAAoKPxzfCgCgAgAAAA==.Grue:BAEANQADCggIEAABNQAECgcIGQAOAEIFAA==.Gröthis:BAAANQAECgQIBwAAAA==.',
Gw='Gweilo:BAAANQAECggIBgAAAA==.Gwendilyn:BAAANQAECgIIAgAAAA==.',
Gy='Gyndrinolara:BAAANQAECgMICAAAAA==.',
Ha='Hafadude:BAAANQAECggIAQAAAA==.Hahgottum:BAABNQAECn8aAAMDAAgKSxBEHACDAQADAAgKSxBEHACDAQANAAMKVgAwtgAsAAAAAA==.Handsomshlax:BAAANQADCgMIAwAAAA==.',
He='Headhuntér:BAABNQAECn8YAAMbAAcK1gweCwBNAQAbAAYKwAgeCwBNAQABAAYKtQp4+wANAQAAAA==.Healgoßyeßye:BAAANQADCgYIBgAAAA==.',
Hi='Hikiru:BAAANQAECggIBgAAAA==.',
Hl='Hlzero:BAAANQAECgIIAwAAAA==.',
Ho='Hollandar:BAAANQADCgcIBwAAAA==.Holyflame:BAAANQAECgEIAQAAAA==.Holypewpewz:BAAANQAECgYICgAAAA==.Holyyshift:BAAANQAECgEJAQABNQAECgYICgAGAAAAAA==.Horhel:BAABNQAECn8UAAMIAAcKISBVHwBKAgAIAAcKISBVHwBKAgAEAAMKEAraUQGdAAAAAA==.Hottstreak:BAAANQADCggICAAAAA==.',
Hu='Huehef:BAAANQADCgEIAQAAAA==.Hungmao:BAAANQADCggICAAAAA==.Huuron:BAAANQAECgIIBwAAAA==.',
Hy='Hyperiann:BAAANQAECgQICQAAAA==.Hypnôtoâd:BAAANQAECgEIAQABNQAECgQIBwAGAAAAAA==.',
Ia='Iamfried:BAABNQAECn8sAAINAAoKuRvzHQDaAgANAAoKuRvzHQDaAgAAAA==.',
Ic='Iceyrot:BAAANQAECgEIAgAAAA==.',
Ig='Igran:BAAANQAECgIIBAABNQAECgoKFwAJAMMXAA==.',
Ih='Ihatemodels:BAAANQAECgYICAAAAA==.',
Il='Illidank:BAAANQADCgMIAwAAAA==.Illidigle:BAAANQADCggIDAABNQAECgkJHwAfAKgUAA==.Ilurvyou:BAAANQADCgYIBgAAAA==.',
In='Inamorta:BAABNQAECn8tAAMcAAoKbBrKEwAYAgAgAAgK7RgBJQAeAgAcAAkKuhnKEwAYAgAAAA==.Innarius:BAAANQAECgUIBwAAAA==.Intothedark:BAAANQAECggIBgAAAA==.Inviçtus:BAAANQADCgQIBAAAAA==.Inyadraug:BAABNQAECn8WAAIRAAgKeBA1lABVAQARAAgKeBA1lABVAQAAAA==.',
Ir='Ironheãrt:BAABNQAECn9EAAIjAAoKpx05CABKAgAjAAoKpx05CABKAgAAAA==.Ironjaws:BAAANQAECgUIBwAAAA==.Ironsight:BAAANQAECgMIBAAAAA==.Irontaco:BAAANQAECgMIBQAAAA==.Irsa:BAABNQAECn8UAAMIAAgKNxGybwDJAQAIAAgKNxGybwDJAQAjAAMKZwyzZABNAAAAAA==.',
Is='Isaacnewton:BAAANQAECgEIAwAAAA==.',
It='Itai:BAABNQAECn82AAMTAAoKQyNmAwC+AwATAAoKQyNmAwC+AwASAAUKvwxsTgDcAAAAAA==.',
Iv='Iverson:BAAANQAECgIIAwAAAA==.',
Iz='Izayam:BAAANQADCgcIBwABNQAECgkJIwAYAHciAA==.',
Ja='Jackk:BAACNQAFFH8ZAAIIAAcKVhmGAwBeAgAIAAcKVhmGAwBeAgA1AAQKfywAAwgACgrpIpYIAIMDAAgACgrpIpYIAIMDAAQABgrtDpeVACcBAAAA.Jackks:BAAANQAECgcIEAABNQAFFAcIGQAIAFYZAA==.Jaddix:BAAANQADCgYICwAAAA==.Jalexandrea:BAAANQAECgIIBQAAAA==.Janzan:BAAANQAECgIIAgAAAA==.Jasmonk:BAABNQAECn8gAAIKAAgKxwy4HwApAQAKAAgKxwy4HwApAQAAAA==.Jaxed:BAAANQAECgEIAgAAAA==.',
Je='Jeeyell:BAAANQADCgUIBQAAAA==.Jellysickle:BAAANQADCgcICAAAAA==.Jemzz:BAABNQAECn8dAAMBAAoKbwcsowDoAAABAAkKrgcsowDoAAAHAAYKSQQsPQBiAAAAAA==.',
Ji='Jimmyray:BAAANQAECgEIAQAAAA==.Jinkua:BAAANQAECgIIAwABNQAECggIDAAGAAAAAA==.Jinkz:BAAANQAECgUICgAAAA==.',
Jo='Jolfurnuand:BAAANQAECgIIBAAAAA==.Jorhel:BAAANQADCggJDgAAAA==.Josephsmith:BAAANQAECggIAQAAAA==.Joshù:BAAANQAECgQIBAABNQAECgoKFwAJAMMXAA==.Joshú:BAAANQADCgEIAQABNQAECgoKFwAJAMMXAA==.',
Ju='Judgementàl:BAAANQAECgYICgABNQAFFAIIBgAQABsIAA==.Judgevis:BAAANQAECgcIEgAAAA==.Jumbles:BAAANQAECgIIAgAAAA==.',
Jy='Jynxy:BAAANQAECgQIDAAAAA==.',
['Já']='Jáydn:BAAANQAECgIIAgABNQAECgkJLQAEADgiAA==.',
['Jø']='Jøshu:BAAANQAECgEIAQABNQAECgoKFwAJAMMXAA==.',
Ka='Kaeliis:BAABNQAECn8ZAAIIAAkKaRKvSgBrAQAIAAkKaRKvSgBrAQAAAA==.Kagestrasz:BAAANQAECgEIAQAAAA==.Kaneggy:BAAANQAECgYIDQAAAA==.Karrona:BAAANQADCggJDAAAAA==.Kazuu:BAABNQAECn8eAAINAAkKNBekGADQAQANAAkKNBekGADQAQAAAA==.',
Kb='Kbeckinsale:BAABNQAECn8pAAQeAAkK6R4CIwBvAgAeAAcKjR0CIwBvAgAZAAcK+Bw1OQCCAQAkAAIKLwbJGABXAAAAAA==.',
Ke='Keelone:BAAANQAECgEIAQAAAA==.Keladun:BAAANQADCgUIDwAAAA==.',
Kh='Khallessi:BAAANQAECgEIAgAAAA==.Kharga:BAAANQAECggIEwAAAA==.Khonan:BAAANQADCgUIBgABNQAFFAcICwAYADoYAA==.',
Ki='Kiamar:BAAANQAECgYICgAAAA==.Kidgroove:BAAANQADCggICgAAAA==.Kishu:BAAANQADCggICAAAAA==.',
Kn='Kneecaps:BAAANQADCgcIBwAAAA==.',
Ko='Kolus:BAAANQADCggIDAAAAA==.Konamy:BAABNQAECn8iAAIYAAoKZhKSPQD+AQAYAAoKZhKSPQD+AQAAAA==.Kordarg:BAAANQADCgQIBAAAAA==.Korz:BAABNQAECn8WAAIfAAgKkxXSawDbAQAfAAgKkxXSawDbAQAAAA==.',
Kr='Krex:BAAANQADCgEIAQAAAA==.Kriss:BAAANQAECgEIAgAAAA==.Kristeena:BAAANQAECgQIBAAAAA==.Kroldun:BAAANQADCgIIAgAAAA==.Kryptonikk:BAABNQAECn8YAAMFAAcKWgsfRAAUAQAFAAUKDAsfRAAUAQAfAAUKywkQxADRAAAAAA==.Krystall:BAAANQADCgEIAQAAAA==.Kröw:BAABNQAECn8pAAIPAAgK0Q99FgAAAgAPAAgK0Q99FgAAAgAAAA==.',
Ku='Kudrix:BAABNQAECn8lAAIKAAkKaR5VDwDuAgAKAAkKaR5VDwDuAgAAAA==.Kurø:BAAANQAECgYIEAAAAA==.',
La='Lany:BAAANQADCgUIBgAAAA==.Latherfanta:BAAANQAECgMIBAAAAA==.Laurijaydn:BAABNQAECn8tAAIEAAkKOCLJEQDqAgAEAAkKOCLJEQDqAgAAAA==.Laurynn:BAAANQAECgEIAwAAAA==.',
Le='Legendaries:BAAANQAECgEIAgAAAA==.Legionremix:BAAANQAECgEIAgAAAA==.Lelink:BAAANQADCgEIAQAAAA==.Levyathan:BAAANQADCgEIAQAAAA==.',
Li='Liath:BAAANQAECgUIDwAAAA==.Likeaglove:BAAANQADCgIIAgABNQAECgkJHwAfAKgUAA==.Lillina:BAAANQADCgIIAgAAAA==.Littlestarz:BAABNQAECn8YAAIRAAgKZxu3SQA8AgARAAgKZxu3SQA8AgAAAA==.Lizzieag:BAEANQADCgcICwABNQAECgcINQABAGQXAA==.',
Ll='Llazz:BAACNQAFFH8NAAIIAAYK2xdqBADaAQAIAAYK2xdqBADaAQA1AAQKfyMAAggACgrbG/oSALICAAgACgrbG/oSALICAAAA.Llemons:BAAANQAECggIDwABNQAECggIGwAYANoTAA==.',
Lo='Lockinaround:BAAANQAECgEIAQAAAA==.Locknlizzie:BAEBNQAECn81AAIBAAcKZBeMaABDAgABAAcKZBeMaABDAgAAAA==.Lohueng:BAAANQAECgMIAwAAAA==.Lolblur:BAAANQAECgQIBAAAAA==.Lolhigh:BAAANQAECgEIAwAAAA==.Lootah:BAAANQADCggIGAAAAA==.Loranoth:BAAANQADCggJIAAAAA==.Lovecox:BAAANQADCggIFAAAAA==.Lox:BAAANQAECgYICAAAAA==.',
Lu='Luke:BAABNQAECn8hAAIEAAgKZBu+hQAcAgAEAAgKZBu+hQAcAgAAAA==.Luminali:BAABNQAECn8YAAMIAAgK8g1rpAA6AQAIAAcKUAxrpAA6AQAEAAQKCw2pPAG/AAAAAA==.Luminari:BAAANQAECggIDQABNQAECggIGAAIAPINAA==.Lunadari:BAAANQAECgIJBQAAAA==.Lunareva:BAABNQAECn8lAAIDAAkKvh7UBgD2AgADAAkKvh7UBgD2AgAAAA==.',
Ly='Lyrielle:BAAANQADCgQIBQAAAA==.Lyxon:BAABNQAECn8lAAIDAAkKrxXCDwAsAgADAAkKrxXCDwAsAgAAAA==.',
['Læ']='Lænna:BAAANQADCgUJBQAAAA==.',
['Lé']='Légoläs:BAAANQAECgMIBAAAAA==.',
['Lí']='Lílîth:BAAANQAECgMIAgAAAA==.',
Ma='Machiavellï:BAAANQAECgQIBAAAAA==.Mael:BAAANQADCgYICQABNQADCggICAAGAAAAAA==.Maeltne:BAAANQADCgcIBgAAAA==.Mafoôza:BAACNQAFFH8KAAIMAAMK8hQdIgDsAAAMAAMK8hQdIgDsAAA1AAQKfxkAAgwACgq8E6uEABACAAwACgq8E6uEABACAAAA.Magicalama:BAACNQAFFH8HAAIYAAQKGQwvGwDWAAAYAAQKGQwvGwDWAAA1AAQKfzYAAhgACgrsGcB9AIMCABgACgrsGcB9AIMCAAAA.Magiplex:BAAANQAECgUIDwAAAA==.Magnanimity:BAEANQAECgIIBQABNQAECgoKLQABAEMUAA==.Mahboyblu:BAAANQADCgEIAQAAAA==.Mahndoo:BAABNQAECn8bAAIYAAcK2hNX3gDLAQAYAAcK2hNX3gDLAQAAAA==.Makto:BAAANQAECgUICAAAAA==.Malia:BAAANQAECgYIDgAAAA==.Maliciouso:BAAANQAECggIEwAAAA==.Malédiction:BAAANQAECgQICgAAAA==.Manydoor:BAAANQADCgIIAgAAAA==.Mariemaya:BAAANQAECgEIBAAAAA==.Marley:BAABNQAECn8oAAIBAAkK3Ak+nADOAQABAAkK3Ak+nADOAQAAAA==.Matua:BAAANQAECgUIDgAAAA==.Maximillian:BAAANQAECgQIBAAAAA==.Maymae:BAAANQAECgMIAwABNQAECgcIFwARAOkQAA==.',
Mc='Mcßlood:BAAANQAECggIEwAAAA==.',
Me='Meatsheeld:BAAANQAECgYIBgABNQAFFAQIBwABALwLAA==.Meepz:BAAANQAECgIIAwAAAA==.Megadk:BAAANQAECgUICAABNQAECggIFAAjAPkYAA==.Megamacdin:BAABNQAECn8UAAMjAAYK+RhFHwABAQAjAAUKCh1FHwABAQAEAAEKsgguqgEyAAAAAA==.Mendietta:BAABNQAECn8pAAIRAAkKIxSpLAD0AQARAAkKIxSpLAD0AQAAAA==.Meridian:BAABNQAECn8aAAIfAAgKthTmNgDdAQAfAAgKthTmNgDdAQAAAA==.',
Mi='Miistral:BAABNQAECn8dAAMIAAgKGhI7egCqAQAIAAgKGhI7egCqAQAEAAEKAACrvAEqAAAAAA==.Milkhoof:BAAANQAECgUICwAAAA==.Mimie:BAAANQAECgUJDAAAAA==.Mistyeva:BAAANQAECgQICAABNQAECgkJJQADAL4eAA==.Miyamoto:BAAANQADCgEIAQAAAA==.Miyoko:BAAANQADCgUIBwAAAA==.',
Mo='Moistooltip:BAABNQAECn8wAAIKAAoK7B82BgBsAwAKAAoK7B82BgBsAwAAAA==.Mokotrize:BAABNQAECn8nAAIjAAkKBRtKDADlAQAjAAkKBRtKDADlAQAAAA==.Mooscifer:BAAANQADCgYIBgAAAA==.Moosh:BAABNQAECn8cAAIVAAYKphL0LwAcAQAVAAYKphL0LwAcAQAAAA==.Mordred:BAABNQAECn8ZAAIdAAYKvQUcIADGAAAdAAYKvQUcIADGAAAAAA==.Morria:BAAANQADCgIIAgAAAA==.Mouthkisser:BAAANQAECgQIBAAAAA==.',
Mu='Mud:BAAANQAECggIDwAAAA==.Mudslinger:BAAANQAECgcICAAAAA==.Munchies:BAABNQAECn8aAAMeAAkKlhQXMgAWAgAeAAkKbxAXMgAWAgAZAAYKGRYkOwB4AQAAAA==.',
My='Myrolan:BAAANQADCgYICgABNQADCgcICwAGAAAAAA==.Myrrha:BAAANQAECgYICAAAAA==.',
['Mø']='Møønwuu:BAAANQAECgUIDwAAAA==.',
Na='Naarf:BAAANQAECgIIAgABNQAFFAQIBwABALwLAA==.Nanoko:BAAANQAECgIIAgAAAA==.Naora:BAAANQAECgEIAQABNQAECgUJDAAGAAAAAA==.Natedoggydog:BAAANQAECggICQAAAA==.',
Ne='Neckslice:BAACNQAFFH8RAAIOAAcKxxV6AwBvAgAOAAcKxxV6AwBvAgA1AAQKfywAAg4ACgqFJEIEAD8DAA4ACgqFJEIEAD8DAAAA.Nefertm:BAAANQADCgMIAwAAAA==.Nemophilist:BAAANQAECgEIAQAAAA==.Neural:BAAANQAECgIIAgAAAA==.Neuro:BAABNQAECn8jAAMYAAkKdyL+MwAiAwAYAAkKdyL+MwAiAwAlAAEKFhicQABDAAAAAA==.',
Ni='Nichdru:BAAANQADCgcICwAAAA==.Nicolico:BAAANQAECgQIBQAAAA==.Nictamom:BAAANQAECgEIAQAAAA==.Nightfaze:BAAANQAECgMIAwABNQAECgcIFAAIACEgAA==.Nightnite:BAAANQAECgEIAQAAAA==.Nij:BAAANQAECgEIAQAAAA==.Nirri:BAAANQAECgQICgAAAA==.Nitefall:BAABNQAECn8cAAIBAAkKxROyhgD+AQABAAkKxROyhgD+AQAAAA==.Nithon:BAAANQAECggIDwAAAA==.',
No='Nocando:BAABNQAECn8fAAIfAAkKqBSHSgBGAgAfAAkKqBSHSgBGAgAAAA==.Notadk:BAABNQAECn8VAAISAAcKFg7sPQAhAQASAAcKFg7sPQAhAQAAAA==.Nott:BAAANQAECgEJAQAAAA==.Noturbudpal:BAAANQADCgQIBgABNQAECgoKZQAUAEQYAA==.',
Nu='Nuggets:BAAANQAECgIIAgAAAA==.Nuriel:BAAANQADCgQIBAAAAA==.',
Ny='Nylinuya:BAAANQAECgUIEgABNQAECgoKQAAWAFYgAA==.Nywen:BAAANQADCgUIBQAAAA==.',
Ob='Obsydia:BAAANQADCgcIBwAAAA==.',
Oc='Occulus:BAAANQAECgEIAgAAAA==.',
Ok='Okowilly:BAAANQADCggIDQAAAA==.',
Ol='Oline:BAABNQAECn8VAAICAAkKySGAIgD6AgACAAkKySGAIgD6AgAAAA==.',
On='Onijunk:BAAANQADCgQIBAAAAA==.',
Oo='Oonaki:BAABNQAECn8WAAMUAAoKLwdcbgA7AQAUAAcKgAhcbgA7AQASAAQKOQR1dwBeAAAAAA==.',
Or='Orchideva:BAAANQAECgQICQABNQAECgkJJQADAL4eAA==.Oriphiel:BAAANQAECgUIDwAAAA==.',
Ot='Ottoshock:BAAANQADCgUIBQAAAA==.',
Ow='Owl:BAAANQADCggICQAAAA==.',
Pa='Painloa:BAABNQAECn8WAAMTAAcKIQj9hQAJAQATAAYKGQj9hQAJAQASAAYK0wUWhgCYAAAAAA==.Pandanimal:BAAANQAECgIIAgAAAA==.Papapally:BAAANQADCgUIBwAAAA==.Paradoxx:BAABNQAECn8xAAIlAAoKLCS5AgA0AwAlAAoKLCS5AgA0AwAAAA==.',
Pe='Pestelince:BAAANQADCggIDQAAAA==.',
Ph='Phelefica:BAAANQAECgQIBQAAAA==.Phreyja:BAAANQADCgcICAAAAA==.Phylgon:BAABNQAECn8nAAMfAAgK8xA2PgC8AQAfAAgK8xA2PgC8AQAFAAEKAAAJlgANAAAAAA==.',
Pl='Pleblords:BAAANQAECgIIBAAAAA==.',
Pm='Pmac:BAAANQAECgYIDQABNQAECggIFAAjAPkYAA==.',
Po='Poggrin:BAAANQAECgUIBgAAAA==.Pogrin:BAAANQAECgQICwAAAA==.Pointybrows:BAAANQAECgQIDQAAAA==.',
Pr='Protect:BAAANQAECgEIAgAAAA==.Pryona:BAAANQAECgEIAQABNQAECgQICAAGAAAAAA==.',
Pu='Putrescence:BAAANQAECgIIAgAAAA==.',
Pw='Pwnhubb:BAAANQADCgQIBAAAAA==.',
Py='Pyràbànks:BAAANQAECgEIAQAAAA==.',
Qu='Quelestraza:BAABNQAECn8pAAMQAAkKaxV7CwDdAQAQAAkKaxV7CwDdAQAJAAEKAACRPgAvAAAAAA==.Quikkmex:BAAANQAECgQIBwAAAA==.',
Ra='Rabbit:BAAANQADCgQIBAAAAA==.Raewyck:BAABNQAECn8pAAIBAAoKBA/ieQAbAgABAAoKBA/ieQAbAgAAAA==.Raginbull:BAABNQAECn8wAAMLAAgK5huWCQCvAQALAAgK5huWCQCvAQAMAAMK3QYQ8gA6AAAAAA==.Ragingmaze:BAABNQAECn8mAAQUAAgKbBPUTQC/AQAUAAgKbBPUTQC/AQATAAgKsgTjfwAdAQASAAIKQAWzngBTAAAAAA==.Rainburrow:BAABNQAECn8eAAMiAAkKwhIVEwCyAQAiAAYKuhcVEwCyAQAKAAMKIwzCLgCzAAAAAA==.Raptormortis:BAAANQAECgQICAAAAA==.',
Re='Rebalite:BAAANQABCgEIAQAAAA==.Reinitia:BAAANQAECgEIAgAAAA==.Reinnii:BAAANQAECgQICgAAAA==.Reinslight:BAAANQAECgEIAQAAAA==.Resurrection:BAAANQAECgEIAwAAAA==.Retana:BAABNQAECn8vAAIEAAoKTx8rXQCBAgAEAAoKTx8rXQCBAgAAAA==.Retrisan:BAAANQABCgQIBAAAAA==.Retroflex:BAAANQAECgEIAQABNQAECgYICQAGAAAAAA==.',
Rh='Rhalk:BAAANQADCgEIAQAAAA==.Rhinn:BAABNQAECn8eAAIPAAYKSAa5IgAwAQAPAAYKSAa5IgAwAQAAAA==.',
Ri='Rickypeepee:BAABNQAECn8eAAIEAAgK+B4PRADIAgAEAAgK+B4PRADIAgAAAA==.Rider:BAAANQAECgEIAQAAAA==.Rigatoni:BAAANQAECgIIBQAAAA==.Rizzlybear:BAAANQAECgEIAwABNQAECgIIAgAGAAAAAA==.',
Ro='Roastedz:BAABNQAECn8bAAIXAAcKWwuACQDZAAAXAAcKWwuACQDZAAAAAA==.Roflmaster:BAAANQAECgEIAQAAAA==.Rojen:BAAANQAECgYIDgAAAA==.Rorthu:BAAANQAECgIIAgAAAA==.',
Ru='Rukélie:BAAANQAECgIIAgAAAA==.',
Ry='Ry:BAAANQAECggIEgAAAA==.Ryanna:BAABNQAECn8fAAIYAAgKHgqQfABJAQAYAAgKHgqQfABJAQAAAA==.',
Sa='Sacrilege:BAAANQABCgIIAgAAAA==.Saevio:BAABNQAECn8oAAQTAAgKqhJmIABxAQASAAcKHhJ3RgCmAQATAAcKDg9mIABxAQAUAAQKqhCyigDWAAAAAA==.Sajin:BAAANQAECgMIBAAAAA==.Salvader:BAABNQAECn8hAAIHAAgKvxTuJgAUAgAHAAgKvxTuJgAUAgAAAA==.Sanctus:BAAANQAECgEIBAAAAA==.Sashimi:BAACNQAFFH8IAAMSAAMKuAmGCgDLAAASAAMKuAmGCgDLAAATAAEK6wNfJAA7AAA1AAQKfykAAxIACgp7G6wXAM0CABIACgrwGawXAM0CABMABQoxDwgwAAoBAAAA.Sataves:BAAANQABCgMIAwAAAA==.Satharis:BAAANQAECgUICQAAAA==.',
Sc='Scarlet:BAAANQAECgQIBgAAAA==.Scarllett:BAABNQAECn8fAAMRAAoKfAzppAAqAQARAAkKOAvppAAqAQAOAAcKEhCJtgAlAQAAAA==.Scoot:BAEANQAECggICQABNQAFFAMIBAAGAAAAAA==.Scrubiclese:BAAANQAECgUIBQAAAA==.Scrytearia:BAAANQAECgEIAQAAAA==.',
Se='Seldaren:BAAANQAECgQICwAAAA==.Selfward:BAAANQAECgQICgAAAA==.Seran:BAABNQAECn8XAAIBAAkKIg/dLwAgAgABAAkKIg/dLwAgAgAAAA==.Serenade:BAAANQAECgYIEAAAAA==.Seviana:BAABNQAECn8aAAIIAAoK3R47FwAfAwAIAAoK3R47FwAfAwABNQAFFAcIHgAQADwlAA==.Sevie:BAACNQAFFH8eAAIQAAcKPCX1AQCnAgAQAAcKPCX1AQCnAgA1AAQKfz4AAhAACgrLJNEBAKsDABAACgrLJNEBAKsDAAAA.',
Sh='Shabbyy:BAAANQADCgYIDAABNQAECgQIBwAGAAAAAA==.Shadowpump:BAABNQAECn8dAAQFAAcKuRSrOABgAQAFAAYKBxGrOABgAQAfAAUKvhb9mgBEAQAmAAEKzQsDLAAsAAAAAA==.Shalada:BAAANQADCgUIBQAAAA==.Shamsel:BAABNQAECn8sAAIFAAkK6w5YFACGAQAFAAkK6w5YFACGAQAAAA==.Shellack:BAAANQAECgEIAgAAAA==.Shinnz:BAABNQAECn9MAAMEAAoKSBuyIgB9AgAEAAoKSBuyIgB9AgAIAAMK8QCJHQE5AAAAAA==.Shockcaller:BAAANQAECgYIDQAAAA==.Shockingnut:BAAANQAECgUICwAAAA==.Showtooltip:BAAANQAECgMIBAABNQAECgoKMAAKAOwfAA==.Shoöman:BAAANQADCgEIAQAAAA==.Shrabster:BAABNQAECn8UAAIYAAcK/wcXzQC0AAAYAAcK/wcXzQC0AAABNQAECgQIBwAGAAAAAA==.Shweatyballs:BAAANQADCgQIBAAAAA==.',
Si='Silversong:BAABNQAECn8sAAMBAAkKWxyUKQA7AgABAAkKWxyUKQA7AgAbAAEKqBJyEgBAAAAAAA==.Simmara:BAAANQAECgMICgAAAA==.Sinh:BAAANQAECgEIAQAAAA==.Sip:BAAANQAECgIIBAABNQAECgYICQAGAAAAAA==.',
Sk='Skapelijones:BAAANQAECgMIBQAAAA==.Skipper:BAAANQAECgIIBQAAAA==.Skylinelol:BAAANQAECggIEAAAAA==.Skywalkah:BAAANQADCgQIBAABNQAECgEIBAAGAAAAAA==.',
Sm='Smallcurse:BAAANQAECgYICwAAAA==.Smallighting:BAABNQAECn8xAAQRAAoKJREFYADuAQARAAoKJREFYADuAQAPAAUKxBRsIwAlAQAOAAQKpxM30ADzAAAAAA==.Smokiemcpot:BAAANQAECgQIBgAAAA==.',
So='Solanthis:BAAANQAECgEJAQAAAA==.Solstica:BAABNQAECn8dAAMmAAgKZxuXAQBvAgAmAAgKZxuXAQBvAgAFAAEKAADEjgAcAAAAAA==.',
Sp='Spiritualone:BAABNQAECn8dAAIjAAkKOhLlLAB2AQAjAAkKOhLlLAB2AQAAAA==.',
Sq='Sqwaat:BAAANQAECgIJAwAAAA==.',
St='Steelrib:BAABNQAECn8gAAIUAAYKlQVViADdAAAUAAYKlQVViADdAAAAAA==.Stonystark:BAAANQAECgMIDgAAAA==.Straam:BAACNQAFFH8LAAIRAAQKawUlDwDtAAARAAQKawUlDwDtAAA1AAQKf1EAAxEACgo2GpUqALkCABEACgo2GpUqALkCAA4ABwokEKqfAFcBAAAA.Strizzle:BAEBNQAECn8ZAAIOAAcKQgUwpwBGAQAOAAcKQgUwpwBGAQAAAA==.Stupidity:BAAANQADCggICAAAAA==.Støney:BAAANQAECgQICQAAAA==.',
Su='Subatronic:BAACNQAFFH8gAAIUAAcKvSQiAgCOAgAUAAcKvSQiAgCOAgA1AAQKfzUAAhQACgqdJpEAAIQDABQACgqdJpEAAIQDAAAA.Subfractal:BAAANQADCgYIBgABNQAFFAcIIAAUAL0kAA==.Surealadin:BAAANQADCgYIBgAAAA==.',
Sy='Sylthara:BAABNQAECn8aAAQRAAYKuxIjkQBdAQARAAYKuxIjkQBdAQAOAAMKowEOzAAtAAAPAAEKAABhPAASAAAAAA==.Syrothea:BAAANQADCgUJBQAAAA==.',
Ta='Tacokicker:BAAANQADCgcIBwAAAA==.Tahumm:BAABNQAECn8fAAIMAAgKaxNHRQC6AQAMAAgKaxNHRQC6AQAAAA==.Takki:BAABNQAECn8YAAIMAAkK2hesdgApAQAMAAkK2hesdgApAQAAAA==.Talethia:BAABNQAECn8XAAIYAAcKQBE4gwA8AQAYAAcKQBE4gwA8AQAAAA==.Tamsîn:BAABNQAECn8yAAIWAAoKCxqmAwC3AgAWAAoKCxqmAwC3AgAAAA==.',
Tb='Tbonez:BAAANQADCgIIAgABNQAECgYIIAAUAJUFAA==.',
Te='Teapawt:BAAANQABCgEIAQAAAA==.Teech:BAAANQAECgEIAQAAAA==.Teinuya:BAABNQAECn9AAAMWAAoKViACAgAZAwAWAAkKAh8CAgAZAwAXAAUK/SLbDwAAAgAAAA==.Tenderfiddle:BAAANQADCgEIAQAAAA==.Tenderloinz:BAAANQAECgEIAQAAAA==.Tenochitilan:BAABNQAECn8WAAMRAAgKUw7XnQA8AQARAAcKdwvXnQA8AQAOAAIK6w0cEgFoAAAAAA==.',
Th='Thedon:BAAANQAECgEIAQAAAA==.Themagi:BAAANQADCgYIBgAAAA==.Theocracy:BAAANQAECgQIDQAAAA==.Thoorz:BAAANQAECgIIAwAAAA==.Thorimeir:BAAANQAECgUIBgAAAA==.Thorzy:BAAANQAECggIEwABNQAECgIIAwAGAAAAAA==.Thraxacious:BAABNQAECn9BAAInAAoKwh3IAwCOAgAnAAoKwh3IAwCOAgAAAA==.Thulsadoomm:BAABNQAECn8VAAIUAAYKfh2TQAD8AQAUAAYKfh2TQAD8AQAAAA==.Thundermay:BAABNQAECn8XAAIRAAcK6RAqTwBZAQARAAcK6RAqTwBZAQAAAA==.',
Ti='Tiduss:BAABNQAECn8WAAILAAUKMQupLADSAAALAAUKMQupLADSAAAAAA==.Tigó:BAAANQAECgcIDQAAAA==.Tigölebittie:BAAANQADCgEIAQAAAA==.Tiik:BAABNQAECn8gAAIoAAYKRBvsDQCoAQAoAAYKRBvsDQCoAQAAAA==.Timorrow:BAAANQADCgUICQAAAA==.Tinkerbel:BAABNQAECn8kAAIIAAkKIxxYNQCPAgAIAAkKIxxYNQCPAgAAAA==.Tinkerbella:BAAANQAECgQIBQAAAA==.Tinkerrbella:BAAANQAECgEIAQABNQAFFAYIGQABAK8TAA==.Tireliaa:BAAANQADCgUIBgAAAA==.',
To='Toe:BAAANQADCgIIAgAAAA==.Tohsaka:BAAANQADCgQICQAAAA==.Torsin:BAAANQADCgIIAgAAAA==.Totamic:BAAANQAECgQICAAAAA==.',
Tr='Trafalgor:BAAANQAECgQICAAAAA==.Trafalgour:BAAANQAECgEIAgAAAA==.Trazen:BAAANQAECgEIAgAAAA==.Tribulationz:BAAANQADCgUIBQABNQAECgUIEgAGAAAAAA==.Triplebolt:BAAANQAECgQIBQAAAA==.Try:BAAANQAECggIBQABNQAECggIEgAGAAAAAA==.',
Ts='Tsukinagi:BAAANQAECgIIAgAAAA==.Tsun:BAABNQAECn8fAAMMAAkKWw5pnQDTAQAMAAkKWw5pnQDTAQALAAQK8AUlMwCeAAAAAA==.Tsurinoya:BAAANQAECgIIAgAAAA==.',
Tu='Tundal:BAAANQAECgQIBwAAAA==.',
Ty='Tydz:BAAANQAECgEIAgABNQAFFAYIEAAIAIMPAA==.Tyylerdurden:BAAANQAECgEIBQAAAA==.',
Ua='Uafraidofme:BAAANQAECgUICAAAAA==.',
Ud='Uddermishap:BAEANQADCgYIBgABNQAECgoKLQABAEMUAA==.Uddertrouble:BAEBNQAECn8tAAIBAAoKQxSqPADuAQABAAoKQxSqPADuAQAAAA==.',
Ul='Ulfgrim:BAAANQADCgYIDAAAAA==.',
Un='Unholytiran:BAAANQAECgQIDQAAAA==.',
Ur='Urmada:BAABNQAECn8lAAMlAAkKWhCcDADvAQAlAAgKBhKcDADvAQAYAAEKUwaOMwErAAAAAA==.Urmami:BAABNQAECn8XAAICAAkKRhGZeAD5AQACAAkKRhGZeAD5AQAAAA==.',
Ut='Utterlyaloof:BAAANQAECgYIBwAAAA==.',
Uz='Uzui:BAAANQAECgIIAwAAAA==.',
Va='Valyne:BAAANQAECgQICAAAAA==.Vampire:BAABNQAECn8cAAIgAAgKgB8FEQDnAgAgAAgKgB8FEQDnAgAAAA==.Vampyre:BAABNQAECn8VAAIUAAkKlhuJLQBgAgAUAAkKlhuJLQBgAgAAAA==.Vanadie:BAAANQAECgIIAgAAAA==.Vanta:BAAANQAECgEIAQAAAA==.Varekth:BAAANQADCgMIAwAAAA==.Vargmal:BAAANQAECgUIBgAAAA==.',
Vi='Virala:BAAANQAECgQIBwAAAQ==.Visenya:BAAANQAECgMIBQAAAA==.Visquake:BAAANQAECgIICAAAAA==.Vitamin:BAAANQADCgcIBwABNQAECggIHgAEAF8fAA==.Vitaminn:BAABNQAECn8eAAQEAAgKXx9fdQBDAgAEAAgKXx9fdQBDAgAjAAEKDQoMSwAzAAAIAAEKIQOhKQEsAAAAAA==.',
Vl='Vlaen:BAAANQAECgQIBQAAAA==.',
Vo='Votum:BAAANQADCgkJFgAAAA==.',
Vy='Vyrisa:BAAANQAECgEIAgAAAA==.Vyrma:BAAANQADCgIIAgAAAA==.',
Wa='Warpstorms:BAAANQADCgQIBAAAAA==.Wasabii:BAAANQAECgYICgAAAA==.',
Wh='Whisa:BAABNQAECn8fAAIfAAoKHBzADgD/AgAfAAoKHBzADgD/AgAAAA==.White:BAAANQADCggICAABNQAFFAcIEQAOAMcVAA==.',
Wi='Wildwolff:BAAANQADCgYICwAAAA==.Wilhedin:BAABNQAECn8rAAIMAAgKKCQVJgAhAwAMAAgKKCQVJgAhAwAAAA==.Willowwind:BAAANQAECgMIBAABNQAECgkJIQAoAD4gAA==.Wing:BAEANQAFFAMIBAAAAA==.',
Wo='Wolfblade:BAAANQADCgQJBQAAAA==.Worm:BAACNQAFFH8QAAIMAAcKKxnXBgBUAgAMAAcKKxnXBgBUAgA1AAQKfzkAAgwACgqUI/kHAC4DAAwACgqUI/kHAC4DAAAA.',
Wu='Wulfnbolt:BAAANQAECgUJCwAAAA==.',
Ww='Wwoman:BAAANQAECgIIAgAAAA==.',
Wy='Wyon:BAAANQAECgcIJgAAAQ==.',
Ya='Yasnah:BAAANQADCggJEgAAAA==.',
Yu='Yunahpabo:BAABNQAECn84AAIMAAoKjx9sFQC7AgAMAAoKjx9sFQC7AgAAAA==.Yurna:BAAANQAECgEIAQAAAA==.',
Za='Zaffyl:BAAANQADCggIDAAAAA==.Zandi:BAAANQAECgUIEAAAAA==.Zanikan:BAAANQAECggICwAAAA==.Zankuza:BAAANQAECggIBAAAAA==.Zathara:BAABNQAECn9CAAInAAoKyhWPBgAEAgAnAAoKyhWPBgAEAgAAAA==.',
Zi='Ziki:BAAANQAECgEIAgAAAA==.Zinpan:BAAANQAECgUIBQAAAA==.',
Zo='Zodiac:BAABNQAECn8mAAIMAAkKbhUURAC+AQAMAAkKbhUURAC+AQAAAA==.Zoopals:BAAANQADCgcICwAAAA==.',
Zu='Zuggle:BAAANQAECgUIBwAAAA==.Zuluk:BAABNQAECn8ZAAMBAAgKwRERkwDjAQABAAcKGxQRkwDjAQAHAAQKygNRQwBNAAAAAA==.',
['Zö']='Zörö:BAABNQAECn86AAMTAAkKFBfuXQCYAQATAAgKFBfuXQCYAQAUAAkKuAmuNwAGAQAAAA==.',
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
