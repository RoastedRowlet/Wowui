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

local lookup = {'Hunter-BeastMastery','Warlock-Demonology','Evoker-Devastation','Druid-Restoration','Paladin-Retribution','Priest-Shadow','Druid-Feral','Unknown-Unknown','Hunter-Marksmanship','Paladin-Holy','Monk-Windwalker','Warrior-Protection','Warrior-Arms','Druid-Balance','Shaman-Elemental','Shaman-Enhancement','Evoker-Preservation','Shaman-Restoration','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Druid-Guardian','DemonHunter-Havoc','Warlock-Affliction','Warlock-Destruction','Mage-Arcane','Rogue-Subtlety','Warrior-Fury','Hunter-Survival','DemonHunter-Vengeance','Rogue-Assassination','Priest-Holy','DemonHunter-Devourer','Evoker-Augmentation','Monk-Brewmaster','Paladin-Protection','Rogue-Outlaw','Mage-Frost','Priest-Discipline','Monk-Mistweaver',}
local provider = {region='US',realm='Frostwolf',name='US',type='weekly',zone=53,date='2026-11-10',data={Aa='Aamodar:BAABNQAECn8hAAIBAAgKbRQKfwChAQABAAgKbRQKfwChAQAAAA==.',
Ab='Abadon:BAABNQAECn8qAAICAAkKXRebQAADAgACAAkKXRebQAADAgAAAA==.',
Ac='Acathisia:BAAANQADCgcIBwAAAA==.',
Ad='Adino:BAABNQAECn8sAAIBAAgKSA1IdwCzAQABAAgKSA1IdwCzAQAAAA==.Adorabell:BAAANQAECggIDQABNQAFFAYIGgABALUZAA==.Adrassa:BAAANQADCgYIBgABNQAECgoKJQADANIaAA==.Adric:BAAANQADCgIIAgAAAA==.',
Ae='Aerostar:BAABNQAECn88AAIEAAoKbx4wCgAXAwAEAAoKbx4wCgAXAwAAAA==.Aeryn:BAACNQAFFH8TAAIFAAYKEB4bCABLAQAFAAYKEB4bCABLAQA1AAQKfz4AAgUACgouI3gSAH4DAAUACgouI3gSAH4DAAAA.Aerís:BAAANQAECgQIBgAAAA==.',
Ag='Aggranak:BAAANQAECggICAAAAA==.Aglaia:BAAANQAECgcIEwAAAA==.Agrolazor:BAACNQAFFH8KAAIGAAQKpAh8CwDKAAAGAAQKpAh8CwDKAAA1AAQKfywAAgYACgpTFj4dAFgCAAYACgpTFj4dAFgCAAAA.',
Ah='Ahote:BAABNQAECn8dAAIHAAkKSyZ+AACHAwAHAAkKSyZ+AACHAwAAAA==.Ahtee:BAABNQAECn82AAIFAAoK8xJqbgDfAQAFAAoK8xJqbgDfAQAAAA==.',
Al='Alara:BAAANQABCgQIBgAAAA==.Albarino:BAAANQADCgYIBgAAAA==.Algodon:BAABNQAECn8gAAIFAAgK/xWFwgCXAQAFAAgK/xWFwgCXAQABNQAFFAMIBQABAKodAA==.Alseena:BAAANQAECgUIDAAAAA==.',
Am='Amun:BAAANQAECgcICwAAAA==.',
An='Andenarras:BAAANQAECgQIBAABNQAECgYIEAAIAAAAAA==.Anthais:BAAANQAECgUIBwAAAA==.Anvar:BAACNQAFFH8HAAIBAAQKvAvYFwDBAAABAAQKvAvYFwDBAAA1AAQKf0gAAwEACgr4IO0dAL0CAAEACgr4IO0dAL0CAAkACAqiDn81AKIBAAAA.',
Ar='Arathion:BAABNQAECn8xAAIKAAkKLB9kFAAFAwAKAAkKLB9kFAAFAwAAAA==.Arcanemommy:BAAANQAECggIAgAAAA==.Archistrate:BAAANQADCgQIBAAAAA==.Ariandra:BAAANQADCggICAABNQAECgoKJQADANIaAA==.Arianrhod:BAACNQAFFH8JAAILAAMKNBZ6DQCLAAALAAMKNBZ6DQCLAAA1AAQKfyMAAgsACgpzIScIAE0DAAsACgpzIScIAE0DAAAA.Artamir:BAAANQABCgYIBgAAAA==.Arx:BAABNQAECn8lAAMMAAkKch75EQAHAgANAAkKfhaGhwAJAgAMAAcKrSD5EQAHAgAAAA==.',
As='Ashaldrin:BAAANQAECgEIAgAAAA==.Ashleyk:BAAANQAECgEIAQAAAA==.Aska:BAAANQADCgIIAgAAAA==.',
At='Atrumdeus:BAACNQAFFH8PAAIFAAUKpQkhGAC/AAAFAAUKpQkhGAC/AAA1AAQKf0cAAgUACgq2GnFhAHUCAAUACgq2GnFhAHUCAAAA.',
Au='Audiamer:BAABNQAECn89AAIOAAoKvgz+LgB2AQAOAAoKvgz+LgB2AQAAAA==.Aufsela:BAAANQAECgEIAQABNQAECgoKJQADANIaAA==.',
Az='Azraelor:BAACNQAFFH8SAAMPAAYKrheDCgAbAQAPAAYKtxCDCgAbAQAQAAMKSBhEBAACAQA1AAQKf2AAAxAACgqcJEUCADUDABAACgqcJEUCADUDAA8ACgoNHidLAEoCAAAA.Azureshal:BAABNQAECn8lAAIDAAoK0hoKBQBmAgADAAoK0hoKBQBmAgAAAA==.',
Ba='Babydragon:BAACNQAFFH8NAAIRAAQKewXxDQDkAAARAAQKewXxDQDkAAA1AAQKfy4AAhEACgp4EoEYADUCABEACgp4EoEYADUCAAAA.Babysaja:BAABNQAECn8gAAINAAoKbQwtZAC+AQANAAoKbQwtZAC+AQAAAA==.Bangerz:BAAANQAECggIDgAAAA==.Bannann:BAABNQAECn8hAAMSAAkK7BxMLQCtAgASAAkK7BxMLQCtAgAPAAEKAABeTgEnAAAAAA==.Baojai:BAAANQAFFAEIAQAAAA==.',
Be='Beaksbigdk:BAABNQAECn8zAAQTAAoK2iSZFQANAwATAAoKPiOZFQANAwAUAAkK7R5sEADBAgAVAAEKYyU3sABrAAAAAA==.Beamkin:BAAANQAECgEIAQAAAA==.Beefÿfridge:BAAANQADCggIFgAAAA==.Belfegor:BAAANQAECgcICwAAAA==.Belldia:BAACNQAFFH8aAAIBAAYKtRlgBwDZAQABAAYKtRlgBwDZAQA1AAQKf0oAAgEACgq8IgcUAE4DAAEACgq8IgcUAE4DAAAA.Belphaegor:BAABNQAECn9LAAMWAAoKYRitDwAoAgAWAAoKYRitDwAoAgAOAAUKpg0ycAAJAQAAAA==.Beni:BAABNQAECn8oAAINAAkKrx1/IwCpAgANAAkKrx1/IwCpAgAAAA==.Beniaru:BAABNQAECn8yAAICAAkKih6eIACEAgACAAkKih6eIACEAgAAAA==.Bennyflipz:BAABNQAECn8bAAIXAAoKjhBjJADSAQAXAAoKjhBjJADSAQAAAA==.',
Bi='Bigmuzz:BAAANQADCgYICAAAAA==.Bigobuffalo:BAAANQAECgQIDQAAAA==.Bigsneaki:BAAANQADCgUIBQAAAA==.',
Bl='Blightedmilk:BAABNQAECn8kAAQYAAoKMxh6BQAWAgAYAAoKjhN6BQAWAgACAAIKJBmw2ACOAAAZAAMKqBkCHAB5AAABNQAECgoKSAAYAK4iAA==.Bloopmasta:BAAANQAECggICAAAAA==.Blufox:BAABNQAECn9AAAMFAAoKTyUKCABXAwAFAAoKTyUKCABXAwAKAAIKZgCSCwEEAAAAAA==.',
Bo='Bobfresh:BAABNQAECn9MAAIPAAoK9SWoBwCrAwAPAAoK9SWoBwCrAwAAAA==.Bowtugger:BAAANQAECgQICAAAAA==.',
Br='Bracks:BAAANQAECgIIAgAAAA==.Brett:BAAANQAECgQIBgAAAA==.Brighamyoung:BAAANQAECggIBQAAAA==.Broherum:BAAANQADCgQJBAAAAA==.Bronzetusk:BAAANQABCgIIAgAAAA==.Brothalittle:BAAANQADCgIIAgAAAA==.Brush:BAAANQAECgEIAQAAAA==.',
Bu='Bubblêosêvên:BAAANQAECgYICwAAAA==.Buc:BAAANQADCgIIBAAAAA==.Buckbeak:BAAANQADCggICAABNQAECgoKMwATANokAA==.Busting:BAABNQAECn82AAIaAAoKuSGcJQBJAwAaAAoKuSGcJQBJAwAAAA==.Buttmucker:BAAANQAECggICAAAAA==.',
By='Byusoaker:BAAANQABCgEIAQABNQAECggIGQAbAJEOAA==.',
['Bà']='Bàhamut:BAAANQAECgQICgAAAA==.',
['Bå']='Båemax:BAAANQADCgYIBgAAAA==.',
Ca='Camellieva:BAAANQAECgUIDQABNQAECgoKMAAEAF4gAA==.Captchaos:BAAANQAECggIDwAAAA==.Carritha:BAAANQAECgMIAwABNQAECgMIBwAIAAAAAA==.Cayo:BAAANQADCgQIBAAAAA==.',
Ce='Cewkie:BAABNQAECn9CAAIcAAoKMBmnBQBkAgAcAAoKMBmnBQBkAgAAAA==.',
Ch='Charlixchix:BAAANQAECgMIAwABNQAECggIGQAbAJEOAA==.Chimneybones:BAABNQAECn8hAAMNAAoKkgvtnwDNAQANAAoKkgvtnwDNAQAcAAEKoQmcMQA0AAAAAA==.Chizz:BAABNQAECn8fAAIaAAkKKgvL0wDfAQAaAAkKKgvL0wDfAQAAAA==.Chriswong:BAABNQAECn8YAAMBAAkK5xIkfQClAQABAAkK5xIkfQClAQAJAAEKvgMvcwAgAAAAAA==.Chronoslicer:BAAANQABCgIIAgAAAA==.Chuckfnnoris:BAAANQAECgQIBAAAAA==.Chá:BAAANQADCggIEAABNQAFFAQIBwATAC0TAA==.',
Cl='Clairebenet:BAABNQAECn85AAMBAAoKVB2uMADaAgABAAkK5R2uMADaAgAdAAoK4xkyAwBqAgAAAA==.Claymoor:BAAANQAECgIIAgAAAA==.Cleph:BAAANQAECggIDAAAAA==.Clumzylock:BAAANQAECgcIEgABNQAECgoKhwAVAFoZAA==.Clumzyninja:BAABNQAECn+HAAIVAAoKWhnPIQCnAgAVAAoKWhnPIQCnAgAAAA==.',
Co='Colonoscope:BAAANQAECgYICAABNQAECgYIDgAIAAAAAA==.Coolbreez:BAABNQAECn8XAAMTAAkKSAhQTADFAAAVAAgK5AYsfAAJAQATAAUK6QhQTADFAAAAAA==.Coolynn:BAAANQAECgMIBgAAAA==.Corl:BAAANQADCgIJAgAAAA==.',
Cr='Crazywar:BAEANQADCgYIDAAAAA==.Creams:BAAANQAECgIIAgABNQAECgQIBQAIAAAAAA==.Crew:BAAANQADCggICgAAAA==.Cronoth:BAAANQAECgUIBQAAAA==.Croy:BAAANQADCgYIBgAAAA==.',
Cu='Cumb:BAABNQAECn8VAAMXAAgKQhieMAB7AQAXAAcKhBeeMAB7AQAeAAIKkBp6JACbAAABNQAECgoKTAAPAPUlAA==.',
Cw='Cwod:BAAANQAECgQIBAABNQADCgYJBwAIAAAAAA==.',
Cy='Cyrothea:BAAANQAECgYICgAAAA==.',
['Cä']='Cäldius:BAAANQAECgYIBgAAAA==.',
Da='Daenerys:BAAANQAECgIIAgAAAA==.Daioh:BAABNQAECn8ZAAIFAAgKBQqFxQAzAQAFAAgKBQqFxQAzAQAAAA==.Damacraze:BAABNQAECn88AAIBAAoKXiHdJwD4AgABAAoKXiHdJwD4AgAAAA==.Damien:BAAANQABCggIDQAAAA==.Danielwu:BAABNQAECn8mAAMYAAkKVw0yGQC/AAACAAkKEQydpgCHAQAYAAQKHRAyGQC/AAAAAA==.Dawigrund:BAAANQAECgYIDQAAAA==.',
De='Deadroar:BAABNQAECn8XAAIVAAgKfxXzTgC5AQAVAAgKfxXzTgC5AQABNQAFFAEIAQAIAAAAAA==.Deadtomato:BAABNQAECn8sAAMbAAoK9iLACQAkAwAbAAoKkSHACQAkAwAfAAkK+B0yGAC7AgAAAA==.Deadwill:BAABNQAECn8hAAIbAAcK4A8kdwAiAQAbAAcK4A8kdwAiAQAAAA==.Deadzug:BAAANQAECgcIDAABNQAFFAQIBwABALwLAA==.Deaminase:BAABNQAECn8qAAIaAAoKFxfRZwDUAQAaAAoKFxfRZwDUAQAAAA==.Deathknell:BAAANQADCgcIBwAAAA==.Decypher:BAABNQAECn83AAIgAAoKUhvYLAC1AgAgAAoKUhvYLAC1AgAAAA==.Deggle:BAAANQADCgIIAgAAAA==.Delphoxx:BAABNQAECn8bAAISAAgKQRqdQAD7AQASAAgKQRqdQAD7AQAAAA==.Demidru:BAABNQAECn8jAAIOAAgKShXvLgB3AQAOAAgKShXvLgB3AQAAAA==.Demin:BAAANQABCgEIAQAAAA==.Demonshot:BAAANQADCgUIBAAAAA==.Depleterpann:BAAANQADCgQICAABNQAECgMIBgAIAAAAAA==.Derovia:BAAANQAECggIDgAAAA==.Deshojo:BAABNQAECn8XAAIWAAYKpg3mPQC1AAAWAAYKpg3mPQC1AAAAAA==.Desrook:BAAANQAECgQIBgAAAA==.',
Dh='Dhqt:BAAANQAECgEIAgABNQAECgQIBQAIAAAAAA==.',
Di='Diablominion:BAAANQAECgYIDgAAAA==.Dingbangow:BAAANQAECgQIBAABNQAECgQIBQAIAAAAAA==.Divinèhero:BAABNQAECn8XAAIXAAcKjgxaTwBcAQAXAAcKjgxaTwBcAQAAAA==.',
Do='Doomgirl:BAAANQAECgIIAgAAAA==.Double:BAAANQAECgYIBwAAAA==.Doublelift:BAACNQAFFH8HAAIGAAMKwxfrEQCjAAAGAAMKwxfrEQCjAAA1AAQKfzkAAwYACgqIIIwRAOMCAAYACQpHIIwRAOMCACAABArLFmaqABcBAAAA.',
Dr='Draghula:BAAANQADCgQIBQAAAA==.Dragondeznut:BAAANQADCggIDgAAAA==.Drakisara:BAAANQADCggIBgABNQAECgYIEAAIAAAAAA==.Drakuul:BAAANQADCgUIBwAAAA==.Droni:BAABNQAECn8jAAMhAAkK5hSjJwAHAgAhAAkK5hSjJwAHAgAXAAEKAADSjgA9AAAAAA==.Drpumper:BAAANQAECgIIAgABNQAECgQIBQAIAAAAAA==.Drummer:BAAANQADCgIIAgAAAA==.Dröbi:BAACNQAFFH8UAAMiAAcK+hJYBACYAQAiAAUK+BZYBACYAQADAAUKmRB7BgA3AQA1AAQKfy4AAwMACgrMIS4IAPgCAAMACQprIS4IAPgCACIABgo1Gm4SAAwBAAAA.',
Du='Duberagon:BAAANQADCgQIBAAAAA==.Dumbledork:BAAANQABCgYICQAAAA==.Dundundun:BAAANQAECggIEgAAAA==.',
Dv='Dvrkwolf:BAAANQADCgcIDAAAAA==.',
['Dâ']='Dârkdune:BAAANQAECggICgAAAA==.',
Eg='Eggdrop:BAABNQAECn8nAAIcAAkKuh0IBwCOAgAcAAkKuh0IBwCOAgAAAA==.Egufro:BAABNQAECn8jAAMKAAoKpRJJMQBJAgAKAAoKpRJJMQBJAgAFAAQKkAShTgFsAAABNQAECgoKUAAQAK0ZAA==.',
Eh='Ehgu:BAABNQAECn9QAAIQAAoKrRmaCwBNAgAQAAoKrRmaCwBNAgAAAA==.',
El='Eleaya:BAAANQADCggIDwAAAA==.Eleverclear:BAAANQADCgYIBgAAAA==.Eliizabeth:BAABNQAECn8YAAIFAAcK1gcv8QA6AQAFAAcK1gcv8QA6AQAAAA==.Elynnah:BAAANQAECgEIAQAAAA==.Elysiawaters:BAEANQADCggICAAAAA==.',
Em='Emidget:BAAANQAECgEIAQAAAA==.',
En='Endervish:BAAANQADCgIIAgABNQAECgMIBwAIAAAAAA==.Enyalio:BAAANQADCgYICwAAAA==.',
Er='Erhmer:BAAANQAECggIBQAAAA==.Ericpal:BAAANQAECggIBwAAAA==.Ericrog:BAAANQABCgYICQAAAA==.Ericwym:BAAANQAECgEIAQAAAA==.',
Et='Ethersong:BAAANQADCgIIAgAAAA==.Etom:BAAANQAFFAEIAQAAAA==.',
Ev='Eviae:BAAANQAECgQICAAAAA==.',
Fa='Faaith:BAAANQADCgIIAgAAAA==.Faceroll:BAAANQAECgIIAgAAAA==.Fairyhunter:BAAANQAECgQICAAAAA==.Fairymonk:BAAANQAECgQIBwAAAA==.Fangrat:BAAANQAECgMIAwABNQAECgQIBQAIAAAAAA==.Fatfatfat:BAAANQAECggIDgABNQAFFAEIAQAIAAAAAA==.Fañgrat:BAABNQAECn8eAAMKAAoKeRnJPwBlAgAKAAoKeRnJPwBlAgAFAAUKGQevSQGqAAABNQAECgQIBQAIAAAAAA==.',
Fe='Femboyluvr:BAABNQAECn8UAAINAAgKMhBCpQAdAQANAAgKMhBCpQAdAQAAAA==.',
Fi='Filumena:BAAANQAECgMIBAAAAA==.Finch:BAAANQABCgQIBgAAAA==.',
Fl='Flameblue:BAAANQADCgQIBAAAAA==.Flandia:BAABNQAECn82AAIBAAoKJR5kIwCkAgABAAoKJR5kIwCkAgAAAA==.Flex:BAAANQAECgYIDgAAAA==.Floppiterry:BAABNQAECn8kAAIBAAYKow4ZwwB8AQABAAYKow4ZwwB8AQAAAA==.Floppyterri:BAAANQADCgYIBgAAAA==.Floppyterry:BAAANQAECgIIAgAAAA==.Flow:BAACNQAFFH8GAAIjAAMKGgq1BQCyAAAjAAMKGgq1BQCyAAA1AAQKfysAAiMACgqjGBQJAJMCACMACgqjGBQJAJMCAAAA.',
Fo='Forduecezero:BAAANQADCgYIBgAAAA==.Fowl:BAABNQAECn8oAAIhAAoK1BkhGgCIAgAhAAoK1BkhGgCIAgAAAA==.Foxyshaman:BAAANQAECgQIBQAAAA==.',
Fr='Fricher:BAABNQAECn8tAAITAAkKkBVxHwDRAQATAAkKkBVxHwDRAQAAAA==.',
Fy='Fylerianprie:BAAANQAECgIIBAAAAA==.Fyleriansham:BAAANQADCgMIAwAAAA==.',
Ga='Gagli:BAAANQAECgQIBQAAAA==.Galathynius:BAAANQAECgQIBQAAAA==.Galelora:BAAANQADCggICAAAAA==.Ganjja:BAAANQADCggIGAAAAA==.Gawk:BAAANQADCgUICwABNQAECgQIBQAIAAAAAA==.',
Ge='Geneman:BAAANQABCgYIDAAAAA==.Getsyouwet:BAAANQAECgMIAgABNQAECgoKMwATANokAA==.Getter:BAAANQADCgkJFQAAAA==.',
Gh='Ghalamir:BAAANQAECgIIAgAAAA==.Ghettomike:BAAANQAECgQIBAAAAA==.',
Gi='Giny:BAABNQAECn8sAAMPAAoKGBUFSACeAQAPAAoKGBUFSACeAQASAAIKRgFKHAE0AAAAAA==.',
Gl='Glowfungus:BAAANQABCgIIAgAAAA==.',
Go='Gobbledeez:BAABNQAECn8pAAISAAoK5yKIDABcAwASAAoK5yKIDABcAwAAAA==.Gobblez:BAAANQAECgQICwAAAA==.Gorvash:BAAANQADCgIIAgAAAA==.Gosulock:BAEBNQAECn8UAAICAAkKuQohgQBJAQACAAkKuQohgQBJAQABNQAECgoKLAABAHkiAA==.Govinniuur:BAAANQAECgIJAgAAAA==.',
Gr='Grasfedjones:BAAANQAECgQIBwAAAA==.Gravelord:BAAANQAECgEIAQAAAA==.Grizzy:BAABNQAECn83AAIXAAoKMCC+DQC8AgAXAAoKMCC+DQC8AgAAAA==.Grue:BAEANQADCggIEAABNQAECgcIGQAPAEIFAA==.Gröthis:BAAANQAECgQIBQAAAA==.',
Gw='Gweilo:BAAANQAECggIBgAAAA==.Gwendilyn:BAAANQAECgIIAgAAAA==.',
Gy='Gyndrinolara:BAAANQAECgMIBgAAAA==.',
Ha='Hafadude:BAAANQAECggIAQAAAA==.Hahgottum:BAABNQAECn8mAAMEAAoK8BSUFQBcAgAEAAoK8BSUFQBcAgAOAAMKVgAwtgAsAAAAAA==.Handsomshlax:BAAANQADCgMIAwAAAA==.',
He='Headhuntér:BAABNQAECn8YAAMdAAcK1gweCwBNAQAdAAYKwAgeCwBNAQABAAYKtQp4+wANAQAAAA==.Healgoßyeßye:BAAANQADCgYIBgAAAA==.',
Hi='Hikiru:BAAANQAECggIBgAAAA==.',
Hl='Hlzero:BAAANQAECggIAgAAAA==.',
Ho='Hollandar:BAAANQADCgcIBwAAAA==.Holyflame:BAAANQAECgEIAQAAAA==.Holypewpewz:BAAANQAECgYICwAAAA==.Holyyshift:BAAANQAECgEIAQABNQAECgYICwAIAAAAAA==.Horhel:BAAANQAECgYIEAAAAA==.Hottstreak:BAAANQADCggICAAAAA==.',
Hu='Huehef:BAAANQADCgEIAQAAAA==.Hungmao:BAAANQADCggICAAAAA==.Huuron:BAAANQAECgIICAAAAA==.',
Hy='Hyperiann:BAAANQAECggIDQAAAA==.Hypnôtoâd:BAAANQAECgEIAQABNQAECgQIBQAIAAAAAA==.',
Ia='Iamfried:BAACNQAFFH8JAAIOAAMKnRJcEADhAAAOAAMKnRJcEADhAAA1AAQKfzEAAg4ACgpWHvMdANoCAA4ACgpWHvMdANoCAAAA.',
Ic='Iceyrot:BAAANQADCggIFgAAAA==.',
Ig='Igran:BAAANQAECgIIAgABNQAECgoKJQADANIaAA==.',
Ih='Ihatemodels:BAAANQAECgYICgAAAA==.',
Il='Illidank:BAAANQADCgYICQAAAA==.Illidigle:BAAANQADCggIDAABNQAECgkJHwAgAKgUAA==.Ilurvyou:BAAANQADCgYIBgAAAA==.',
In='Inamorta:BAABNQAECn82AAMXAAoKKSDYCwDWAgAXAAkKKSDYCwDWAgAhAAgK7RgBJQAeAgAAAA==.Innarius:BAAANQAECgYICwAAAA==.Intothedark:BAAANQAECggIAgAAAA==.Inviçtus:BAAANQADCgQIBAAAAA==.Inyadraug:BAAANQAECggIDwAAAA==.',
Ip='Ipurgeu:BAAANQAECgEIAQAAAA==.',
Ir='Ironheãrt:BAABNQAECn9MAAIkAAoKER64DADPAgAkAAoKER64DADPAgAAAA==.Ironjaws:BAAANQAECgUIBQAAAA==.Ironsight:BAAANQAECgMIAwAAAA==.Irontaco:BAAANQAECgMIAwAAAA==.Irsa:BAAANQAECggIEgAAAA==.',
Is='Isaacnewton:BAAANQAECgIIAgAAAA==.',
It='Itai:BAACNQAFFH8HAAMTAAQKLRO+BgDpAAATAAMKLRO+BgDpAAAUAAEKAABJIAAAAAA1AAQKf1MAAxMACgqRJGYDAL4DABMACgqRJGYDAL4DABQACAokG30gADcCAAAA.',
Iv='Iverson:BAAANQAECgMIAgAAAA==.',
Iz='Izayam:BAAANQADCgcIBwABNQAECgkJIwAaAHciAA==.',
Ja='Jac:BAAANQAECgMIAwABNQAFFAgIGgAKACwXAA==.Jackk:BAACNQAFFH8aAAIKAAgKLBeGAwBeAgAKAAgKLBeGAwBeAgA1AAQKfy0AAwoACgrpIpYIAIMDAAoACgrpIpYIAIMDAAUABgrtDiHYABQBAAAA.Jackks:BAAANQAECgcIDwABNQAFFAgIGgAKACwXAA==.Jaddix:BAAANQADCgYICwAAAA==.Jalexandrea:BAAANQAECgUIDAAAAA==.Janzan:BAAANQAECgIIAgAAAA==.Jasmonk:BAABNQAECn8pAAILAAkKiw1cIgBxAQALAAkKiw1cIgBxAQAAAA==.Jaxed:BAAANQAECgEIAQAAAA==.',
Je='Jeeyell:BAAANQADCgUIBQAAAA==.Jellysickle:BAAANQADCgcICAAAAA==.Jemzz:BAABNQAECn8tAAMJAAoKigjzJQAmAQABAAoKrwfwnwBXAQAJAAkKQAbzJQAmAQAAAA==.',
Ji='Jimmyray:BAAANQABCgYIBgAAAA==.Jinkua:BAAANQAECgIIAgABNQAFFAEIAQAIAAAAAA==.Jinkz:BAAANQAECgUICAAAAA==.',
Jo='Jolfurnuand:BAAANQAECgIIAgAAAA==.Jorhel:BAAANQADCggJDgAAAA==.Josephsmith:BAAANQAECggIBAAAAA==.Joshù:BAAANQAECggIEQABNQAECgoKJQADANIaAA==.Joshú:BAAANQADCgEIAQABNQAECgoKJQADANIaAA==.',
Ju='Judgementàl:BAAANQAECgcICwABNQAFFAQIDQARAHsFAA==.Judgevis:BAAANQAECgcIEAAAAA==.Jumbles:BAAANQAECgQIBQAAAA==.Justeene:BAAANQADCgEIAQABNQAECgYIEAAIAAAAAA==.',
Jy='Jynxy:BAAANQAECgYIBgAAAA==.',
['Já']='Jáydn:BAAANQAECgUIBwABNQAECgkJNwAFAHsiAA==.',
['Jø']='Jøshu:BAAANQADCgYIBgABNQAECgoKJQADANIaAA==.',
Ka='Kaeliis:BAABNQAECn8mAAIKAAoK1RUpMwBAAgAKAAoK1RUpMwBAAgAAAA==.Kagestrasz:BAAANQADCgYIBgAAAA==.Kaneggy:BAABNQAECn8WAAMcAAkKhgx8FAAZAQANAAYKdAsNowAiAQAcAAgKOQp8FAAZAQAAAA==.Karren:BAAANQADCgIIBAAAAA==.Karrona:BAAANQADCggJDAAAAA==.Kazuu:BAABNQAECn8tAAIOAAkKjBeDIgDTAQAOAAkKjBeDIgDTAQAAAA==.',
Kb='Kbeckinsale:BAABNQAECn8yAAQbAAkK6R75KwA8AgAfAAcKjR0CIwBvAgAbAAgKch35KwA8AgAlAAIKLwbJGABXAAAAAA==.',
Ke='Keladun:BAAANQADCgUIDwAAAA==.Kemaro:BAAANQAECggICQAAAA==.Keykey:BAAANQAECgEIAQAAAA==.',
Kh='Khallessi:BAAANQAECgYICQAAAA==.Kharga:BAAANQAECgcIEAAAAA==.Khonan:BAAANQADCgUIBgABNQAFFAgIDAAaAJMXAA==.',
Ki='Kiamar:BAAANQAECgYICAAAAA==.Kidgroove:BAAANQADCggICgAAAA==.Kishu:BAAANQADCggICAAAAA==.',
Kn='Kneecaps:BAAANQADCgcIBwAAAA==.',
Ko='Kolus:BAAANQADCggIEAAAAA==.Konamy:BAABNQAECn8qAAIaAAoKIRNKWgD2AQAaAAoKIRNKWgD2AQAAAA==.Kordarg:BAAANQADCgQIBAAAAA==.Korz:BAABNQAECn8WAAIgAAgKkxXSawDbAQAgAAgKkxXSawDbAQAAAA==.',
Kr='Krex:BAAANQADCgEIAQAAAA==.Kriss:BAAANQADCggICQAAAA==.Kristeena:BAAANQAECgQIBAAAAA==.Kroldun:BAAANQADCgIIAgAAAA==.Kryptonikk:BAABNQAECn8eAAMGAAkK7gsfRAAUAQAGAAUKDAsfRAAUAQAgAAcKVQyDpgDWAAAAAA==.Krystall:BAAANQADCgEIAQAAAA==.Kröw:BAABNQAECn8rAAIQAAkKPg59FgAAAgAQAAkKPg59FgAAAgAAAA==.',
Ku='Kudrix:BAABNQAECn8oAAILAAoKZh1VDwDuAgALAAoKZh1VDwDuAgAAAA==.Kurø:BAAANQAECgcIDQAAAA==.',
La='Lany:BAAANQADCgUIBgAAAA==.Latherfanta:BAAANQAECgMIBAAAAA==.Laurijaydn:BAABNQAECn83AAIFAAkKeyJUHwDbAgAFAAkKeyJUHwDbAgAAAA==.Laurynn:BAAANQADCggIDQAAAA==.Lauríe:BAAANQADCgMIAwABNQAECgkJNwAFAHsiAA==.',
Le='Lechampion:BAAANQAECgQIBAAAAA==.Legendaries:BAAANQADCgEIAQAAAA==.Legionremix:BAAANQADCggICQAAAA==.Lelink:BAAANQADCgEIAQAAAA==.Levyathan:BAAANQADCgEIAQAAAA==.',
Li='Liath:BAAANQAECgUICgAAAA==.Likeaglove:BAAANQADCgIIAgABNQAECgkJHwAgAKgUAA==.Lillina:BAAANQADCgIIAgAAAA==.Littlestarz:BAABNQAECn8cAAISAAgKsxu3SQA8AgASAAgKsxu3SQA8AgAAAA==.Lizzieag:BAEANQADCgYICwABNQAECgcINQABAGQXAA==.',
Ll='Llazz:BAACNQAFFH8NAAIKAAYK2xdMCADFAQAKAAYK2xdMCADFAQA1AAQKfzcAAwoACgrMHnMOAEEDAAoACgrMHnMOAEEDAAUAAwqdEKoSAbgAAAAA.Llemons:BAAANQAECggIDwABNQAECggIGwAaANoTAA==.',
Lo='Locknlizzie:BAEBNQAECn81AAIBAAcKZBeMaABDAgABAAcKZBeMaABDAgAAAA==.Lohueng:BAAANQAECgMIBAAAAA==.Lolblur:BAAANQAECgQIBAAAAA==.Lolhigh:BAAANQAECgEIAQAAAA==.Lootah:BAAANQADCggIGAAAAA==.Loranoth:BAAANQADCggJIAAAAA==.Lovecox:BAAANQADCggIFAAAAA==.Lox:BAABNQAECn8VAAMZAAoKngqkBgBdAQAZAAoKngqkBgBdAQACAAcKPgN2yQCsAAAAAA==.',
Lu='Luke:BAABNQAECn8nAAIFAAkKgx1hYAABAgAFAAkKgx1hYAABAgAAAA==.Luminali:BAABNQAECn8cAAMKAAgKMQ5rpAA6AQAKAAcKmAxrpAA6AQAFAAQKCw2pPAG/AAAAAA==.Luminari:BAAANQAECggIDQABNQAECggIHAAKADEOAA==.Lunadari:BAAANQAECgIJAwAAAA==.Lunareva:BAABNQAECn8wAAIEAAoKXiBgBQCHAwAEAAoKXiBgBQCHAwAAAA==.Lunä:BAAANQADCggICAABNQAFFAYIGgABALUZAA==.',
Ly='Lyrielle:BAAANQADCgQIBQAAAA==.Lyxon:BAABNQAECn8xAAIEAAoKmBUhFgBUAgAEAAoKmBUhFgBUAgAAAA==.',
['Læ']='Lænna:BAAANQADCgUJBQAAAA==.',
['Lé']='Légoläs:BAAANQAECgMIAwAAAA==.',
['Lí']='Lílîth:BAAANQAECgMIAgAAAA==.',
Ma='Machiavellï:BAAANQAECgQIBAAAAA==.Mael:BAAANQADCgYICQABNQADCggICAAIAAAAAA==.Maeltne:BAAANQADCgYIBgAAAA==.Mafoôza:BAACNQAFFH8PAAINAAUKUQ8dIgDsAAANAAUKUQ8dIgDsAAA1AAQKfyIAAg0ACgprHe4eAMACAA0ACgprHe4eAMACAAAA.Magicalama:BAACNQAFFH8JAAIaAAYKsA4iFwAhAQAaAAYKsA4iFwAhAQA1AAQKfzkAAhoACgpAGsB9AIMCABoACgpAGsB9AIMCAAAA.Magiplex:BAAANQAECgUIDgAAAA==.Magnanimity:BAEANQAECgIIAgABNQAECgoKNQABAFoVAA==.Mahboyblu:BAAANQADCgEIAQAAAA==.Mahndoo:BAABNQAECn8bAAIaAAcK2hNX3gDLAQAaAAcK2hNX3gDLAQAAAA==.Makto:BAAANQAECgUICwAAAA==.Malia:BAAANQAECgQIDAAAAA==.Maliciouso:BAAANQAECggIEwAAAA==.Malédiction:BAAANQAECgQIBAAAAA==.Manydoor:BAAANQADCgIIAgAAAA==.Marley:BAABNQAECn8oAAIBAAkK3Ak+nADOAQABAAkK3Ak+nADOAQAAAA==.Matua:BAAANQAECgUICwAAAA==.Maximillian:BAAANQAECgQIBAAAAA==.Maymae:BAAANQAECgMIBAABNQAECgYIEwAIAAAAAA==.',
Mc='Mcßlood:BAABNQAECn8cAAMVAAkKKCAoCQDzAgAVAAkKKCAoCQDzAgAUAAEKbADHwgADAAAAAA==.',
Me='Meatsheeld:BAAANQAECgYIBgABNQAFFAQIBwABALwLAA==.Meepz:BAAANQAECgQIBAAAAA==.Megadk:BAAANQAECgUIBwABNQAECggIGgAkAFweAA==.Megamacdin:BAABNQAECn8aAAMkAAcKXB5QEgDvAQAkAAYKsSJQEgDvAQAFAAEKsgguqgEyAAAAAA==.Mendietta:BAABNQAECn8zAAISAAkKiBW1QQD3AQASAAkKiBW1QQD3AQAAAA==.Meridian:BAABNQAECn8rAAIgAAkKMxpaKgCNAgAgAAkKMxpaKgCNAgAAAA==.Mesna:BAAANQAECgQIBAAAAA==.',
Mi='Miistral:BAABNQAECn8kAAMKAAoK+w87egCqAQAKAAoK+w87egCqAQAFAAEKAACrvAEqAAAAAA==.Milkhoof:BAABNQAECn8VAAIUAAYK5BQtTQBKAQAUAAYK5BQtTQBKAQAAAA==.Mimie:BAAANQAECgUIDAAAAA==.Minki:BAAANQADCggICQAAAA==.Mistyeva:BAAANQAECgYICgABNQAECgoKMAAEAF4gAA==.Miyamoto:BAAANQADCgEIAQAAAA==.Miyoko:BAAANQADCgUIBwAAAA==.',
Mo='Moistooltip:BAABNQAECn8wAAILAAoK7B82BgBsAwALAAoK7B82BgBsAwAAAA==.Mokotrize:BAABNQAECn8xAAIkAAkK4BxTDwAfAgAkAAkK4BxTDwAfAgAAAA==.Mooscifer:BAAANQADCgYIBgAAAA==.Moosh:BAABNQAECn8jAAIWAAgKcBD+KQAkAQAWAAgKcBD+KQAkAQAAAA==.Morandara:BAAANQABCgUIBwAAAA==.Mordred:BAABNQAECn8ZAAIeAAYKvQUcIADGAAAeAAYKvQUcIADGAAAAAA==.Morria:BAAANQADCgIIAgAAAA==.Mouthkisser:BAAANQAECgQIAwAAAA==.',
Ms='Msfirefly:BAAANQAECgQIBAABNQAECggIFQAZAOAbAA==.',
Mu='Mud:BAAANQAECggIDwAAAA==.Mudslinger:BAAANQAECgcICAAAAA==.Munchies:BAABNQAECn8lAAMfAAkK4RkXMgAWAgAfAAkKAxQXMgAWAgAbAAcKKRfGQwDWAQABNQAFFAQICQAUALgJAA==.',
My='Myrolan:BAAANQADCgYICgABNQADCgcICwAIAAAAAA==.Myrrha:BAAANQAECggICAAAAA==.',
['Mø']='Møønwuu:BAABNQAECn8ZAAIfAAoK/wv1EQCfAQAfAAoK/wv1EQCfAQAAAA==.',
Na='Naarf:BAAANQAECgIIAgABNQAFFAQIBwABALwLAA==.Nanoko:BAAANQAECgIIAgAAAA==.Naora:BAAANQAECgEIAQABNQAECgUIDAAIAAAAAA==.Natedoggydog:BAAANQAECggICAAAAA==.',
Ne='Neckslice:BAACNQAFFH8TAAIPAAgKthN6AwBvAgAPAAgKthN6AwBvAgA1AAQKfzEAAg8ACgqSJCgIADIDAA8ACgqSJCgIADIDAAAA.Nefertm:BAAANQADCgQIAwAAAA==.Nemophilist:BAAANQABCgIIAgAAAA==.Neural:BAAANQAECgcIBwAAAA==.Neuro:BAABNQAECn8jAAMaAAkKdyL+MwAiAwAaAAkKdyL+MwAiAwAmAAEKFhicQABDAAAAAA==.',
Ni='Nichdru:BAAANQADCgcICwAAAA==.Nicolico:BAAANQAECgQIBAAAAA==.Nictamom:BAAANQAECgEIAQAAAA==.Nightfaze:BAAANQAECgMIBAABNQAECgYIEAAIAAAAAA==.Nightnite:BAAANQADCgYIDgAAAA==.Nij:BAAANQAECgEIAQAAAA==.Nirri:BAAANQAECgYIDwAAAA==.Nitefall:BAABNQAECn8lAAIBAAkKtxSyhgD+AQABAAkKtxSyhgD+AQAAAA==.Nithon:BAAANQAECggIEwAAAA==.',
No='Nocando:BAABNQAECn8fAAIgAAkKqBSHSgBGAgAgAAkKqBSHSgBGAgAAAA==.Nota:BAAANQAECgQIBAABNQAECggIIAAUAEgQAA==.Notadk:BAABNQAECn8gAAIUAAgKSBBSRgBoAQAUAAgKSBBSRgBoAQAAAA==.Nott:BAAANQAECgEIAQAAAA==.Noturbudpal:BAAANQADCgQIBgABNQAECgoKhwAVAFoZAA==.',
Nu='Nuggets:BAAANQAECgIIAgAAAA==.Nuriel:BAAANQADCgQIBAAAAA==.',
Ny='Nylinuya:BAAANQAECgUIEAABNQAECgoKSAAYAK4iAA==.Nywen:BAAANQADCgUIBQAAAA==.',
Ob='Obligated:BAAANQAECgIIAgAAAA==.Obsydia:BAAANQADCgcIBwAAAA==.',
Ok='Okowilly:BAAANQADCggIDQAAAA==.',
Ol='Oline:BAABNQAECn8VAAICAAkKySGAIgD6AgACAAkKySGAIgD6AgAAAA==.',
On='Onijunk:BAAANQADCgQIBAAAAA==.',
Oo='Oonaki:BAABNQAECn8YAAMVAAoK6gdcbgA7AQAVAAcKgAhcbgA7AQAUAAQKsQWkjwBvAAAAAA==.',
Or='Orchideva:BAAANQAECgQIBwABNQAECgoKMAAEAF4gAA==.Oriphiel:BAAANQAECgUIDAAAAA==.',
Ot='Ottoshock:BAAANQADCgUIBQAAAA==.',
Ow='Owl:BAAANQADCggICQAAAA==.',
Pa='Painloa:BAABNQAECn8WAAMTAAcKIQj9hQAJAQATAAYKGQj9hQAJAQAUAAYK0wUWhgCYAAAAAA==.Pandanimal:BAAANQAECgIIAgAAAA==.Papapally:BAAANQADCgUIBwAAAA==.Paradoxx:BAABNQAECn83AAImAAoKoyS5AgA0AwAmAAoKoyS5AgA0AwAAAA==.',
Pe='Pestelince:BAAANQAECgUICAAAAA==.',
Ph='Phelefica:BAAANQAECgQIAwAAAA==.Phreyja:BAAANQADCgYICAAAAA==.Phylgon:BAABNQAECn8nAAMgAAgK8xD0YgCfAQAgAAgK8xD0YgCfAQAGAAEKAAAJlgANAAAAAA==.',
Pl='Pleblords:BAAANQAECgIIBgAAAA==.',
Pm='Pmac:BAAANQAECgUICwABNQAECggIGgAkAFweAA==.',
Po='Poggrin:BAAANQAECgUICQAAAA==.Pogrin:BAAANQAECgQICwAAAA==.Pointybrows:BAAANQAECgQICQAAAA==.',
Pr='Premmier:BAAANQADCgcIDgAAAA==.Prudeix:BAAANQADCgUIBQAAAA==.Pryona:BAAANQAECgIIAQABNQAECgQIBQAIAAAAAA==.',
Pu='Putrescence:BAAANQAECgIIAgAAAA==.',
Pw='Pwnhubb:BAAANQADCgYIBwAAAA==.',
Py='Pyràbànks:BAAANQADCgYIBgAAAA==.',
Qu='Quan:BAAANQABCggIDwAAAA==.Quelestraza:BAABNQAECn8wAAMRAAkKaxU0EQDXAQARAAkKaxU0EQDXAQADAAEKAACRPgAvAAAAAA==.Quikkmex:BAAANQAECgQIBwAAAA==.',
Ra='Rabbit:BAAANQADCgQIBAAAAA==.Raewyck:BAABNQAECn8rAAIBAAoKKw/ieQAbAgABAAoKKw/ieQAbAgAAAA==.Raginbull:BAABNQAECn87AAMMAAgKihwMDwCuAQAMAAgKihwMDwCuAQANAAMK3QYxHAE6AAAAAA==.Ragingmaze:BAABNQAECn8mAAQVAAgKbBPUTQC/AQAVAAgKbBPUTQC/AQATAAgKsgTjfwAdAQAUAAIKQAWzngBTAAAAAA==.Rainburrow:BAABNQAECn80AAMLAAoKoBc1EwAcAgALAAoKkhQ1EwAcAgAjAAcK3hgVEwCyAQAAAA==.Raptormortis:BAAANQAECgQIBQAAAA==.Rastlinn:BAAANQAECggIDQAAAA==.Raziyya:BAAANQADCgEIAQAAAA==.',
Re='Rebalite:BAAANQABCgEIAQAAAA==.Reinitia:BAAANQADCgcICwAAAA==.Reinnii:BAAANQAECgQIDwAAAA==.Renkagisa:BAAANQAECgEIAQAAAA==.Resurrection:BAAANQAECgMIBgAAAA==.Retana:BAABNQAECn85AAIFAAoKJCM1GwDtAgAFAAoKJCM1GwDtAgAAAA==.Reticence:BAAANQABCgIIAgAAAA==.Retrisan:BAAANQABCgQIBAAAAA==.Retroflex:BAAANQAECgEIAQABNQAECgYIDgAIAAAAAA==.',
Rh='Rhalk:BAAANQADCgEIAQAAAA==.Rhinn:BAABNQAECn8hAAIQAAgK9wXwHgAZAQAQAAgK9wXwHgAZAQAAAA==.',
Ri='Rickypeepee:BAABNQAECn8rAAIFAAkKah8PRADIAgAFAAkKah8PRADIAgAAAA==.Rider:BAAANQABCgIIBAAAAA==.Rigatoni:BAAANQAECgIIAgAAAA==.Rizzlybear:BAAANQAECgEIAQABNQAECgEIAQAIAAAAAA==.',
Ro='Roastedz:BAABNQAECn8qAAIZAAkK6AqPCAAvAQAZAAkK6AqPCAAvAQAAAA==.Roflmaster:BAAANQAECgEIAQAAAA==.Rojen:BAAANQAECgQIDgAAAA==.Rorthu:BAAANQAECgIIAgAAAA==.',
Ru='Rukélie:BAAANQAECgIIAgAAAA==.',
Ry='Ry:BAAANQAECggIEAAAAA==.Ryanna:BAABNQAECn8mAAIaAAkKygkIjwB1AQAaAAkKygkIjwB1AQAAAA==.',
Sa='Sacrilege:BAAANQABCgMIAwAAAA==.Saevio:BAABNQAECn88AAQTAAoK/hRLGAAVAgATAAkKWhNLGAAVAgAUAAcKHhJ3RgCmAQAVAAQKqhCyigDWAAAAAA==.Sajin:BAAANQAECgMIAwAAAA==.Salvader:BAABNQAECn8mAAIJAAgKchXuJgAUAgAJAAgKchXuJgAUAgAAAA==.Sanctus:BAAANQAECgUICAAAAA==.Sashimi:BAACNQAFFH8JAAMUAAQKuAmDEAC8AAAUAAMKuAmDEAC8AAATAAIK6wOCFQAAAAA1AAQKf0MAAxMACgq4H9YIAN8CABMACgqCH9YIAN8CABQACgrwGawXAM0CAAAA.Sataves:BAAANQABCgMIAwAAAA==.Satharis:BAAANQAECgUICQAAAA==.',
Sc='Scarlet:BAAANQAECgQIBgABNQAFFAQICQAUALgJAA==.Scarllett:BAABNQAECn8kAAMSAAoKcw/ppAAqAQASAAkKgw7ppAAqAQAPAAcKEhCJtgAlAQAAAA==.Scoot:BAEANQAECggIEQABNQAFFAQIBgAKALsFAA==.Scrappurr:BAAANQABCggIFwAAAA==.Scrubiclese:BAAANQAECgUIBQAAAA==.Scrytearia:BAAANQABCgIJAgAAAA==.',
Se='Seldaren:BAAANQAECgMIBwAAAA==.Selfward:BAAANQAECgQIBwAAAA==.Seran:BAABNQAECn8gAAIBAAkKBRXiPABMAgABAAkKBRXiPABMAgAAAA==.Serenade:BAAANQAECgcIDQAAAA==.Seviana:BAABNQAECn8aAAIKAAoK3R47FwAfAwAKAAoK3R47FwAfAwABNQAFFAcIIwARAJsmAA==.Sevie:BAACNQAFFH8jAAIRAAcKmyb1AQCnAgARAAcKmyb1AQCnAgA1AAQKf0AAAhEACgqTJdEBAKsDABEACgqTJdEBAKsDAAAA.',
Sh='Shabbyy:BAAANQADCgYIDAABNQAECgQIBwAIAAAAAA==.Shadowpump:BAABNQAECn8dAAQGAAcKuRSrOABgAQAGAAYKBxGrOABgAQAgAAUKvhb9mgBEAQAnAAEKzQsDLAAsAAAAAA==.Shalada:BAAANQADCgUIBQAAAA==.Shamsel:BAABNQAECn8+AAIGAAoKKxOJEwANAgAGAAoKKxOJEwANAgAAAA==.Shinnz:BAABNQAECn9jAAMFAAoKxxzYMQCNAgAFAAoKxxzYMQCNAgAKAAMK8QCJHQE5AAAAAA==.Shockcaller:BAAANQAECgYIDQAAAA==.Shockingnut:BAAANQAECgUICQAAAA==.Showtooltip:BAAANQAECgQIAwABNQAECgoKMAALAOwfAA==.Shoöman:BAAANQADCgEIAQAAAA==.Shrabster:BAABNQAECn8YAAIaAAcKqgg78QC8AAAaAAcKqgg78QC8AAABNQAECgQIBQAIAAAAAA==.Shweatyballs:BAAANQADCgQIBAAAAA==.',
Si='Silversong:BAABNQAECn8vAAMBAAkKWxzQSgCNAgABAAkKWxzQSgCNAgAdAAEKqBJyEgBAAAAAAA==.Simmara:BAAANQAECgMIBwAAAA==.Sip:BAAANQAECgYIDgAAAA==.',
Sk='Skapelijones:BAAANQAECgMIAQAAAA==.Skipper:BAAANQABCgYIBgAAAA==.Skylinelol:BAAANQAECggICwAAAA==.Skywalkah:BAAANQADCgQIBAABNQAECgEIAgAIAAAAAA==.',
Sm='Smallcurse:BAAANQAECgYICgAAAA==.Smallighting:BAABNQAECn80AAQSAAoKJhIFYADuAQASAAoKJhIFYADuAQAQAAUKxBRsIwAlAQAPAAQKpxM30ADzAAAAAA==.Smokiemcpot:BAAANQAECgQIBAAAAA==.',
So='Solanthis:BAAANQAECgEJAQAAAA==.Solstica:BAABNQAECn8jAAMnAAoKGBqfAQDwAgAnAAoKGBqfAQDwAgAGAAEKAADEjgAcAAAAAA==.Solsticata:BAAANQAECgEIAQABNQAECgoKIwAnABgaAA==.',
Sp='Sparli:BAAANQABCgQIBAAAAA==.Spiritualone:BAABNQAECn8mAAIkAAkK2RJEJQAwAQAkAAkK2RJEJQAwAQAAAA==.',
Sq='Sqwaat:BAAANQAECgIJAwAAAA==.',
St='Steelrib:BAABNQAECn8kAAIVAAgK6QW7VgDWAAAVAAgK6QW7VgDWAAAAAA==.Stonystark:BAAANQAECgUIAQAAAA==.Straam:BAACNQAFFH8PAAISAAQKTAlOFQD1AAASAAQKTAlOFQD1AAA1AAQKf14AAxIACgpDG5UqALkCABIACgpDG5UqALkCAA8ACAqlD6qfAFcBAAAA.Strizzle:BAEBNQAECn8ZAAIPAAcKQgUwpwBGAQAPAAcKQgUwpwBGAQAAAA==.Stupidity:BAAANQADCggICAAAAA==.Støney:BAAANQAECgcIEgAAAA==.',
Su='Subatronic:BAACNQAFFH8iAAIVAAgKsSQiAgCOAgAVAAgKsSQiAgCOAgA1AAQKf0kAAhUACgrpJlUAAJcDABUACgrpJlUAAJcDAAAA.Subfractal:BAAANQADCgYIBgABNQAFFAgIIgAVALEkAA==.Surealadin:BAAANQADCgYIBgAAAA==.',
Sy='Sylthara:BAABNQAECn8aAAQSAAYKuxIjkQBdAQASAAYKuxIjkQBdAQAPAAMKowFA/AAtAAAQAAEKAABhPAASAAAAAA==.Syrothea:BAAANQADCgUJBQAAAA==.',
Ta='Tacokicker:BAAANQADCgcIBwAAAA==.Tahumm:BAABNQAECn8pAAINAAgKohXkWADgAQANAAgKohXkWADgAQAAAA==.Takki:BAABNQAECn8aAAINAAkKehhvrQCrAQANAAkKehhvrQCrAQAAAA==.Talethia:BAABNQAECn8XAAIaAAcKQBFysAAxAQAaAAcKQBFysAAxAQAAAA==.Tamsîn:BAABNQAECn82AAIYAAoKORymAwC3AgAYAAoKORymAwC3AgAAAA==.Tap:BAABNQAFFH8FAAIbAAUKpxPdCQBZAQAbAAUKpxPdCQBZAQAAAA==.Tazlinmon:BAAANQADCgYIBgABNQAECgYIEAAIAAAAAA==.',
Tb='Tbonez:BAAANQADCgIIAgABNQAECggIJAAVAOkFAA==.',
Te='Teapawt:BAAANQAECgUIBgAAAA==.Teech:BAAANQAECgQIBAAAAA==.Teinuya:BAABNQAECn9IAAQYAAoKriICAgAZAwAYAAkKLSICAgAZAwAZAAUK/SLbDwAAAgACAAEKnwjsDwE1AAAAAA==.Temparia:BAAANQAECgMIAwAAAA==.Tenderfiddle:BAAANQADCgEIAQAAAA==.Tenochitilan:BAABNQAECn8bAAMSAAgK1w7XnQA8AQASAAcKdwvXnQA8AQAPAAMK8Ak7yABqAAAAAA==.',
Th='Thedon:BAAANQAECgEIAQAAAA==.Themagi:BAAANQADCgYIBgAAAA==.Theocracy:BAAANQAECgQIDQAAAA==.Thia:BAAANQABCgQIAwAAAA==.Thoorz:BAAANQAECgIIAwAAAA==.Thorimeir:BAAANQAECgUIBQAAAA==.Thorzy:BAAANQAECggIDwABNQAECgIIAwAIAAAAAA==.Thraxacious:BAABNQAECn9QAAIHAAoKpiCCBADQAgAHAAoKpiCCBADQAgAAAA==.Thulsadoomm:BAABNQAECn8VAAIVAAYKfh2TQAD8AQAVAAYKfh2TQAD8AQAAAA==.Thundermay:BAAANQAECgYIEwAAAA==.',
Ti='Tiduss:BAABNQAECn8WAAIMAAUKMQupLADSAAAMAAUKMQupLADSAAAAAA==.Tigó:BAAANQAECgcIDAAAAA==.Tigölebittie:BAAANQADCgEIAQAAAA==.Tiik:BAABNQAECn8jAAIoAAgK4BhpDwAHAgAoAAgK4BhpDwAHAgAAAA==.Timorrow:BAAANQADCgcICwAAAA==.Tinkerbel:BAABNQAECn8oAAIKAAkKZRxYNQCPAgAKAAkKZRxYNQCPAgAAAA==.Tinkerbella:BAAANQAECgQIBQAAAA==.Tinkerrbella:BAAANQAECgEIAQABNQAFFAYIGgABALUZAA==.Tireliaa:BAAANQADCgUIBgAAAA==.Tisem:BAAANQADCgEIAQAAAA==.',
To='Toe:BAAANQADCgIIAgAAAA==.Tohsaka:BAAANQADCgQICQAAAA==.Torsin:BAAANQADCgIIAgAAAA==.Totamic:BAAANQAECgQIBgAAAA==.',
Tr='Trafalgor:BAAANQAECgQIBgAAAA==.Trafalgour:BAAANQAECgEIAQAAAA==.Trazen:BAAANQAECgEIAQAAAA==.Tribulationz:BAAANQADCgUIBQABNQAECgYIEAAIAAAAAA==.Triplebolt:BAAANQAECgQIBAAAAA==.Try:BAAANQAECggIBAABNQAECggIEAAIAAAAAA==.',
Ts='Tsukinagi:BAAANQAECgIIAgAAAA==.Tsun:BAABNQAECn8pAAMNAAkKNQ9pnQDTAQANAAkKNQ9pnQDTAQAMAAYKIwjbKQCbAAAAAA==.Tsurinoya:BAAANQAECgIIAgAAAA==.',
Tu='Tundal:BAAANQAECgQIBwAAAA==.',
Ty='Tydz:BAAANQAECgEIAwABNQAFFAYIEAAKAIMPAA==.Tyylerdurden:BAAANQAECgIIAQAAAA==.',
Ua='Uafraidofme:BAAANQAECgcIDgAAAA==.',
Ud='Uddermishap:BAEANQADCgYIBgABNQAECgoKNQABAFoVAA==.Uddertrouble:BAEBNQAECn81AAIBAAoKWhXETQAeAgABAAoKWhXETQAeAgAAAA==.',
Ul='Ulfgrim:BAAANQADCgYIDwAAAA==.',
Un='Unholytiran:BAAANQAECgYICQAAAA==.',
Ur='Urmada:BAABNQAECn8xAAMmAAkKPhKcDADvAQAmAAgKOhScDADvAQAaAAEKUwZcXQEpAAAAAA==.Urmami:BAABNQAECn8lAAICAAkKqxRrTwDTAQACAAkKqxRrTwDTAQAAAA==.Urmyenemy:BAAANQADCgEIAQAAAA==.',
Ut='Utterlyaloof:BAAANQAECggIBgAAAA==.',
Uz='Uzui:BAAANQAECgIIAgAAAA==.',
Va='Valyne:BAAANQAECgQIBQAAAA==.Vampire:BAABNQAECn8cAAIhAAgKgB8FEQDnAgAhAAgKgB8FEQDnAgAAAA==.Vampyre:BAABNQAECn8VAAIVAAkKlhuJLQBgAgAVAAkKlhuJLQBgAgAAAA==.Vanadie:BAAANQAECgIIAgAAAA==.Vanta:BAAANQAECgEIAQAAAA==.Varekth:BAAANQADCgMIAwAAAA==.Vargmal:BAAANQAECgcIBwAAAA==.',
Vi='Virala:BAAANQAECgQIBQAAAQ==.Visenya:BAAANQAECgMIBQAAAA==.Visquake:BAAANQAECgIIBQAAAA==.Vitamin:BAAANQADCgcIBwABNQAECggIKAAFABwgAA==.Vitaminn:BAABNQAECn8oAAQFAAgKHCC7bQDhAQAFAAgKHCC7bQDhAQAkAAEKDQoNYAAyAAAKAAEKIQOhKQEsAAAAAA==.',
Vl='Vlaen:BAAANQAECgQIBAAAAA==.',
Vo='Votum:BAAANQADCgkJFgAAAA==.',
Vy='Vyrisa:BAAANQAECgEIAgAAAA==.Vyrma:BAAANQADCgIIAgAAAA==.',
Wa='Warpstorms:BAAANQADCgQIBAAAAA==.Warpwalker:BAAANQADCgEIAQAAAA==.Wasabii:BAAANQAECgYICgABNQAFFAQICQAUALgJAA==.',
Wh='Whisa:BAABNQAECn8rAAIgAAoKyx98DQBkAwAgAAoKyx98DQBkAwAAAA==.White:BAAANQADCggICAABNQAFFAgIEwAPALYTAA==.',
Wi='Wildwolff:BAAANQAECgMIAgAAAA==.Wilhedin:BAABNQAECn8rAAINAAgKKCQVJgAhAwANAAgKKCQVJgAhAwAAAA==.Willowwind:BAAANQAECgMIAwABNQAECgoKKQAoAI4gAA==.Wing:BAEBNQAFFH8GAAIKAAQKuwWxFQAHAQAKAAQKuwWxFQAHAQAAAA==.',
Wo='Wolfblade:BAAANQADCgQIBQAAAA==.Worm:BAACNQAFFH8SAAINAAgKOxfXBgBUAgANAAgKOxfXBgBUAgA1AAQKfz4AAg0ACgrXI38OABwDAA0ACgrXI38OABwDAAAA.',
Wu='Wulfnbolt:BAAANQAECgUJCAAAAA==.',
Ww='Wwoman:BAAANQAECgIIAgAAAA==.',
Wy='Wyon:BAAANQAECggILwAAAQ==.',
['Wî']='Wîtçhplz:BAAANQADCggICAAAAA==.',
Ya='Yasnah:BAAANQADCggIEgAAAA==.',
Yu='Yunahpabo:BAABNQAECn9DAAINAAoKsyCiGgDWAgANAAoKsyCiGgDWAgAAAA==.Yurna:BAAANQADCgMIAgAAAA==.',
Za='Zaffyl:BAAANQADCggIDAAAAA==.Zandi:BAAANQAECgUIDwAAAA==.Zanikan:BAAANQAECggICgAAAA==.Zankuza:BAAANQAECggIAwAAAA==.Zathara:BAABNQAECn9FAAIHAAoKzxYsDADxAQAHAAoKzxYsDADxAQAAAA==.',
Zi='Zinpan:BAAANQAECgcIDwAAAA==.',
Zo='Zodiac:BAABNQAECn8vAAINAAkKJBnmSwAKAgANAAkKJBnmSwAKAgAAAA==.Zoopals:BAAANQADCgcICwAAAA==.',
Zu='Zuggle:BAAANQAECgUIBgAAAA==.Zuluk:BAABNQAECn8ZAAMBAAgKwRERkwDjAQABAAcKGxQRkwDjAQAJAAQKygPAbgB2AAAAAA==.',
['Zö']='Zörö:BAABNQAECn8+AAMVAAkKFBf+NwBWAQATAAgKFBfuXQCYAQAVAAkKHA3+NwBWAQAAAA==.',
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
