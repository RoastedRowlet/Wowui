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
local provider = {region='US',realm='Frostwolf',name='US',type='weekly',zone=53,date='2026-11-03',data={Aa='Aamodar:BAABNQAECn8gAAIBAAcKUBOBjQBTAQABAAcKUBOBjQBTAQAAAA==.',
Ab='Abadon:BAABNQAECn8iAAICAAgKnhcPTwCvAQACAAgKnhcPTwCvAQAAAA==.',
Ac='Acathisia:BAAANQADCgcIBwAAAA==.',
Ad='Adino:BAABNQAECn8lAAIBAAgKZAwWcQCVAQABAAgKZAwWcQCVAQAAAA==.Adorabell:BAAANQAECggIDwABNQAFFAYIGQABAK8TAA==.Adrassa:BAAANQADCgYIBgABNQAECgoKIQADAJQaAA==.Adric:BAAANQADCgIIAgAAAA==.',
Ae='Aerostar:BAABNQAECn82AAIEAAoKSB1ECgDwAgAEAAoKSB1ECgDwAgAAAA==.Aeryn:BAACNQAFFH8TAAIFAAYKEB4ZBgBSAQAFAAYKEB4ZBgBSAQA1AAQKfzkAAgUACgouI3gSAH4DAAUACgouI3gSAH4DAAAA.Aerís:BAAANQAECgQIBgAAAA==.',
Ag='Aglaia:BAAANQAECggIDgAAAA==.Agrolazor:BAACNQAFFH8KAAIGAAQKpAjqCQDPAAAGAAQKpAjqCQDPAAA1AAQKfywAAgYACgpTFj4dAFgCAAYACgpTFj4dAFgCAAAA.',
Ah='Ahote:BAABNQAECn8YAAIHAAkKEyZ5AACDAwAHAAkKEyZ5AACDAwAAAA==.Ahtee:BAABNQAECn8xAAIFAAoKqBKZZADMAQAFAAoKqBKZZADMAQAAAA==.',
Al='Alara:BAAANQABCgQIBgAAAA==.Albarino:BAAANQADCgYIBgAAAA==.Algodon:BAABNQAECn8dAAIFAAgK/xWFwgCXAQAFAAgK/xWFwgCXAQABNQAFFAMIBQABAKodAA==.Alseena:BAAANQAECgUIDAAAAA==.',
Am='Amun:BAAANQAECgQIBQAAAA==.',
An='Andenarras:BAAANQAECgQIBAABNQAECgYIEAAIAAAAAA==.Anthais:BAAANQAECgUICQAAAA==.Anvar:BAACNQAFFH8HAAIBAAQKvAu9FADFAAABAAQKvAu9FADFAAA1AAQKf0UAAwEACgr4IH8YAMICAAEACgr4IH8YAMICAAkACAqiDn81AKIBAAAA.',
Ar='Arathion:BAABNQAECn8qAAIKAAkKLx2nGQC8AgAKAAkKLx2nGQC8AgAAAA==.Arcanemommy:BAAANQAECggIAgAAAA==.Archistrate:BAAANQADCgQIBAAAAA==.Ariandra:BAAANQADCggICAABNQAECgoKIQADAJQaAA==.Arianrhod:BAACNQAFFH8JAAILAAMKNBa3CwCLAAALAAMKNBa3CwCLAAA1AAQKfyMAAgsACgpzIScIAE0DAAsACgpzIScIAE0DAAAA.Artamir:BAAANQABCgYIBgAAAA==.Arx:BAABNQAECn8lAAMMAAkKch75EQAHAgANAAkKfhaGhwAJAgAMAAcKrSD5EQAHAgAAAA==.',
As='Ashaldrin:BAAANQAECgEIAgAAAA==.Ashleyk:BAAANQAECgEIAQAAAA==.Aska:BAAANQADCgIIAgAAAA==.',
At='Atrumdeus:BAACNQAFFH8PAAIFAAUKpQmSFADBAAAFAAUKpQmSFADBAAA1AAQKf0MAAgUACgq2GnFhAHUCAAUACgq2GnFhAHUCAAAA.',
Au='Audiamer:BAABNQAECn81AAIOAAoKqwt6LABlAQAOAAoKqwt6LABlAQAAAA==.Aufsela:BAAANQAECgEIAQABNQAECgoKIQADAJQaAA==.',
Az='Azraelor:BAACNQAFFH8SAAMPAAYKrhesCAAiAQAPAAYKtxCsCAAiAQAQAAMKSBhEBAACAQA1AAQKf1gAAxAACgo1JOEDAFsDABAACgo1JOEDAFsDAA8ACgoNHidLAEoCAAAA.Azureshal:BAABNQAECn8hAAIDAAoKlBqRBABgAgADAAoKlBqRBABgAgAAAA==.',
Ba='Babydragon:BAACNQAFFH8JAAIRAAMK8QVmDgCqAAARAAMK8QVmDgCqAAA1AAQKfy0AAhEACgp4EoEYADUCABEACgp4EoEYADUCAAAA.Babysaja:BAABNQAECn8bAAINAAkKbAwBaQCMAQANAAkKbAwBaQCMAQAAAA==.Bangerz:BAAANQAECggIDwAAAA==.Bannann:BAABNQAECn8hAAMSAAkK7BxMLQCtAgASAAkK7BxMLQCtAgAPAAEKAABeTgEnAAAAAA==.Baojai:BAAANQAFFAEIAQAAAA==.',
Be='Beaksbigdk:BAABNQAECn8xAAQTAAoK2iSZFQANAwATAAoKPiOZFQANAwAUAAkKzh5XEACrAgAVAAEKYyU3sABrAAAAAA==.Beefÿfridge:BAAANQADCggIFgAAAA==.Belfegor:BAAANQAECgcICwAAAA==.Belldia:BAACNQAFFH8ZAAIBAAYKrxNgBwDZAQABAAYKrxNgBwDZAQA1AAQKf0UAAgEACgq8IgcUAE4DAAEACgq8IgcUAE4DAAAA.Belphaegor:BAABNQAECn9BAAMWAAoKIxf5DgANAgAWAAoKIxf5DgANAgAOAAUKpg0ycAAJAQAAAA==.Beni:BAABNQAECn8iAAINAAkKFxhrSgDwAQANAAkKFxhrSgDwAQAAAA==.Beniaru:BAABNQAECn8tAAICAAkKKx6/HgB1AgACAAkKKx6/HgB1AgAAAA==.Bennyflipz:BAABNQAECn8XAAIXAAoKNA8UJQCmAQAXAAoKNA8UJQCmAQAAAA==.',
Bi='Bigmuzz:BAAANQADCgYICAAAAA==.Bigobuffalo:BAAANQAECgUIEAAAAA==.Bigsneaki:BAAANQADCgUIBQAAAA==.',
Bl='Blightedmilk:BAABNQAECn8cAAQYAAoKhhenBwCjAQAYAAgKqxWnBwCjAQACAAIKJBllygCNAAAZAAMKqBkpGQB6AAABNQAECgoKRAAYAAciAA==.Bloopmasta:BAAANQAECggICAAAAA==.Blufox:BAABNQAECn84AAMFAAoKjRwfMQAGAwAFAAkKGSAfMQAGAwAKAAIKZgC8+wAEAAAAAA==.',
Bo='Bobfresh:BAABNQAECn9MAAIPAAoK9SWoBwCrAwAPAAoK9SWoBwCrAwAAAA==.Bowtugger:BAAANQAECgQICAAAAA==.',
Br='Bracks:BAAANQAECgIIAgAAAA==.Braps:BAAANQAECgIIBgAAAA==.Brett:BAAANQAECgQIBgAAAA==.Brighamyoung:BAAANQAECggIBgAAAA==.Broherum:BAAANQADCgQJBAAAAA==.Bronzetusk:BAAANQABCgIIAgAAAA==.Broozer:BAAANQAECgEIAQAAAA==.Brothalittle:BAAANQADCgIIAgAAAA==.Brush:BAAANQAECgEIAQAAAA==.Brönks:BAAANQAECgIIAgAAAA==.',
Bu='Bubblêosêvên:BAAANQAECgYICwAAAA==.Buc:BAAANQADCgIIBAAAAA==.Buckbeak:BAAANQADCggICAABNQAECgoKMQATANokAA==.Busting:BAABNQAECn82AAIaAAoKuSH6GQDEAgAaAAoKuSH6GQDEAgAAAA==.',
By='Byusoaker:BAAANQAECgEIAQABNQAECggIGQAbAJEOAA==.',
['Bà']='Bàhamut:BAAANQAECgQICgAAAA==.',
['Bå']='Båemax:BAAANQADCgYIBgAAAA==.',
Ca='Camellieva:BAAANQAECgUIDAABNQAECgkJKAAEANAeAA==.Captchaos:BAAANQAECgYIDwAAAA==.Carritha:BAAANQAECgMIAwABNQAECgMIBwAIAAAAAA==.Cayo:BAAANQADCgQIBAAAAA==.',
Ce='Cewkie:BAABNQAECn87AAIcAAoK3hYhBgAtAgAcAAoK3hYhBgAtAgAAAA==.',
Ch='Charlixchix:BAAANQAECgMIAwABNQAECggIGQAbAJEOAA==.Chimneybones:BAABNQAECn8hAAMNAAoKkgvtnwDNAQANAAoKkgvtnwDNAQAcAAEKoQmRKwA1AAAAAA==.Chizz:BAABNQAECn8fAAIaAAkKKgvL0wDfAQAaAAkKKgvL0wDfAQAAAA==.Chriswong:BAAANQAECggIEgAAAA==.Chronoslicer:BAAANQABCgIIAgAAAA==.Chuckfnnoris:BAAANQAECgQIBQAAAA==.Chá:BAAANQADCggIEAABNQAFFAMIBgATAC0TAA==.',
Cl='Clairebenet:BAABNQAECn81AAMBAAoKzRyuMADaAgABAAkK5R2uMADaAgAdAAoKfhYkAwBWAgAAAA==.Claymoor:BAAANQAECgIIBQAAAA==.Cleph:BAAANQAECggIDQAAAA==.Clumzylock:BAAANQAECgcIEgABNQAECgoKdwAVAFoZAA==.Clumzyninja:BAABNQAECn93AAIVAAoKWhnPIQCnAgAVAAoKWhnPIQCnAgAAAA==.',
Co='Colonoscope:BAAANQAECgUICAABNQAECgYIDAAIAAAAAA==.Coolbreez:BAABNQAECn8VAAMTAAkKSAgpRgDIAAAVAAgKngYsfAAJAQATAAUK6QgpRgDIAAAAAA==.Coolynn:BAAANQAECgMIBgAAAA==.Corl:BAAANQADCgIJAgAAAA==.',
Cr='Crazywar:BAEANQADCgYIDAAAAA==.Creams:BAAANQAECgIIBAABNQAECgQIBwAIAAAAAA==.Crew:BAAANQADCggICgAAAA==.Cronoth:BAAANQAECgUIBQAAAA==.',
Cu='Cumb:BAABNQAECn8VAAMXAAgKQhjwKQCAAQAXAAcKhBfwKQCAAQAeAAIKkBp6JACbAAABNQAECgoKTAAPAPUlAA==.',
Cy='Cyrothea:BAAANQAECgUIBgAAAA==.',
['Cä']='Cäldius:BAAANQAECgYIBgAAAA==.',
Da='Daenerys:BAAANQAECgIIAgAAAA==.Daioh:BAAANQAECgYIEQAAAA==.Damacraze:BAABNQAECn80AAIBAAoKZB/dJwD4AgABAAoKZB/dJwD4AgAAAA==.Damien:BAAANQAECgEIAQAAAA==.Danielwu:BAABNQAECn8gAAMYAAkK0wwyGQC/AAACAAkKnQudpgCHAQAYAAQK9Q8yGQC/AAAAAA==.Dawigrund:BAAANQAECgYIDQAAAA==.',
De='Deadroar:BAABNQAECn8XAAIVAAgKfxXzTgC5AQAVAAgKfxXzTgC5AQABNQAFFAEIAQAIAAAAAA==.Deadtomato:BAABNQAECn8kAAMbAAoKUyI6FwCeAgAfAAgKCSAyGAC7AgAbAAkK0R86FwCeAgAAAA==.Deadwill:BAABNQAECn8hAAIbAAcK4A8PagAXAQAbAAcK4A8PagAXAQAAAA==.Deadzug:BAAANQAECgcIDQABNQAFFAQIBwABALwLAA==.Deaminase:BAABNQAECn8kAAIaAAkKaxihkwBZAgAaAAkKaxihkwBZAgAAAA==.Deathknell:BAAANQADCgcIBwAAAA==.Decypher:BAABNQAECn8vAAIgAAoKXBrYLAC1AgAgAAoKXBrYLAC1AgAAAA==.Deggle:BAAANQAECgEIAQAAAA==.Delphoxx:BAABNQAECn8aAAISAAcKnBv/QwDSAQASAAcKnBv/QwDSAQAAAA==.Demidru:BAABNQAECn8iAAIOAAgKShWFKQB6AQAOAAgKShWFKQB6AQAAAA==.Demin:BAAANQAECgEIAQABNQAECgEIAQAIAAAAAA==.Demonshot:BAAANQADCgUIBAAAAA==.Depleterpann:BAAANQADCgQICAABNQAECgMIBgAIAAAAAA==.Derovia:BAAANQAECggIEAAAAA==.Deshojo:BAABNQAECn8VAAIWAAYK8wsPOQCtAAAWAAYK8wsPOQCtAAAAAA==.Desrook:BAAANQAECgQICAAAAA==.',
Dh='Dhqt:BAAANQAECgEIAwABNQAECgQIBwAIAAAAAA==.',
Di='Diablominion:BAAANQAECgYIEAAAAA==.Dingbangow:BAAANQAECgQIBAABNQAECgQIBwAIAAAAAA==.Divinèhero:BAABNQAECn8XAAIXAAcKjgxaTwBcAQAXAAcKjgxaTwBcAQAAAA==.',
Do='Doomgirl:BAAANQAECgIIAgAAAA==.Double:BAAANQAECgYICQAAAA==.Doublelift:BAACNQAFFH8FAAIGAAMK5RXrEQCjAAAGAAMK5RXrEQCjAAA1AAQKfzUAAwYACgruH4wRAOMCAAYACQqWH4wRAOMCACAABArLFmaqABcBAAAA.',
Dr='Draghula:BAAANQAECgEIAQAAAA==.Dragondeznut:BAAANQADCggIDgAAAA==.Drakisara:BAAANQADCggIBgABNQAECgYIEQAIAAAAAA==.Drakuul:BAAANQADCgUIBwAAAA==.Droni:BAABNQAECn8iAAMhAAgKhRWjJwAHAgAhAAgKhRWjJwAHAgAXAAEKAADSjgA9AAAAAA==.Drpumper:BAAANQAECgIIAgABNQAECgQIBwAIAAAAAA==.Drummer:BAAANQADCgIIAgAAAA==.Dröbi:BAACNQAFFH8UAAMiAAcK+hJYBACYAQAiAAUK+BZYBACYAQADAAUKmRB7BgA3AQA1AAQKfy4AAwMACgrMIS4IAPgCAAMACQprIS4IAPgCACIABgo1GtgMAOwAAAAA.',
Du='Duberagon:BAAANQADCgQIBAAAAA==.Dumbledork:BAAANQABCgYICQAAAA==.Dundundun:BAAANQAECggIEgAAAA==.',
Dv='Dvrkwolf:BAAANQADCgcIDAAAAA==.',
['Dâ']='Dârkdune:BAAANQAECggIDAAAAA==.',
Eg='Eggdrop:BAABNQAECn8gAAIcAAkKuh0IBwCOAgAcAAkKuh0IBwCOAgAAAA==.Egufro:BAABNQAECn8jAAMKAAoKpRIVKgBRAgAKAAoKpRIVKgBRAgAFAAQKkATRMQFuAAABNQAECgoKSwAQAK0ZAA==.',
Eh='Ehgu:BAABNQAECn9LAAIQAAoKrRlICgBIAgAQAAoKrRlICgBIAgAAAA==.',
El='Eleaya:BAAANQADCggIDwAAAA==.Eleverclear:BAAANQADCgYIBgAAAA==.Eliizabeth:BAABNQAECn8VAAIFAAcK1gcv8QA6AQAFAAcK1gcv8QA6AQAAAA==.Elynnah:BAAANQAECgEIAwABNQAECgEIBAAIAAAAAA==.Elysiawaters:BAEANQADCggICAAAAA==.',
Em='Emidget:BAAANQAECgEIAQAAAA==.',
En='Endervish:BAAANQADCgIIAgABNQAECgMIBwAIAAAAAA==.Enyalio:BAAANQADCgYICwAAAA==.',
Ep='Epicaecin:BAAANQAECgIIBgAAAA==.',
Er='Erhmer:BAAANQAECggIBgAAAA==.Ericpal:BAAANQAECgEIAQAAAA==.Ericrog:BAAANQAECgEIAQAAAA==.Ericwym:BAAANQAECgEIAgAAAA==.',
Et='Ethersong:BAAANQADCgIIAgAAAA==.Etom:BAAANQAECggIDAAAAA==.',
Ev='Eviae:BAAANQAECgQICQAAAA==.',
Fa='Faaith:BAAANQADCgIIAgAAAA==.Faceroll:BAAANQAECgIIAgAAAA==.Fairyhunter:BAAANQAECgQICAAAAA==.Fairymonk:BAAANQAECgQIBwAAAA==.Fangrat:BAAANQAECgEIAgABNQAECgQIBwAIAAAAAA==.Fatfatfat:BAAANQAECggIDwABNQAFFAEIAQAIAAAAAA==.Fañgrat:BAABNQAECn8dAAMKAAoKYxnJPwBlAgAKAAoKYxnJPwBlAgAFAAUKGQevSQGqAAABNQAECgQIBwAIAAAAAA==.',
Fe='Femboyluvr:BAABNQAECn8UAAINAAgKMhD3lQAdAQANAAgKMhD3lQAdAQAAAA==.',
Fi='Filumena:BAAANQAECgMIBAAAAA==.Finch:BAAANQABCgQIBgAAAA==.',
Fl='Flameblue:BAAANQADCgQIBAAAAA==.Flandia:BAABNQAECn8uAAIBAAoK8x0CNwA7AgABAAoK8x0CNwA7AgAAAA==.Flex:BAAANQAECgYICwAAAA==.Floppiterry:BAABNQAECn8iAAIBAAYKow4ZwwB8AQABAAYKow4ZwwB8AQAAAA==.Floppyterri:BAAANQADCgYIBgAAAA==.Floppyterry:BAAANQAECgIIAgAAAA==.Flow:BAABNQAECn8qAAIjAAoKoxgUCQCTAgAjAAoKoxgUCQCTAgAAAA==.',
Fo='Forduecezero:BAAANQADCgYIBgAAAA==.Fowl:BAABNQAECn8oAAIhAAoK1BkhGgCIAgAhAAoK1BkhGgCIAgAAAA==.Foxyshaman:BAAANQAECgQIBQAAAA==.',
Fr='Fricher:BAABNQAECn8mAAITAAkKPRXjHwCwAQATAAkKPRXjHwCwAQAAAA==.',
Fy='Fylerianprie:BAAANQAECgIIBAAAAA==.Fyleriansham:BAAANQADCgMIAwAAAA==.',
Ga='Gagli:BAAANQAECgUIBgAAAA==.Galathynius:BAAANQAECgQIBgAAAA==.Galelora:BAAANQADCggICAAAAA==.Ganjja:BAAANQADCggIGAAAAA==.Gawk:BAAANQADCgUICwABNQAECgQIBwAIAAAAAA==.',
Ge='Geneman:BAAANQABCgYIDAAAAA==.Getsyouwet:BAAANQAECgIIAwABNQAECgoKMQATANokAA==.Getter:BAAANQADCgkJFQAAAA==.',
Gh='Ghalamir:BAAANQAECgIIAgAAAA==.Ghettomike:BAAANQAECgQIBAAAAA==.',
Gi='Giny:BAABNQAECn8lAAMPAAoK2RT5XwACAgAPAAkK2RT5XwACAgASAAIKRgFKHAE0AAAAAA==.',
Gl='Glowfungus:BAAANQABCgIIAgAAAA==.',
Go='Gobbledeez:BAABNQAECn8jAAISAAkK9CGIDABcAwASAAkK9CGIDABcAwAAAA==.Gobblez:BAAANQAECgUIDgAAAA==.Gorvash:BAAANQADCgIIAgAAAA==.Gosulock:BAAANQAECggIDwABNQAECgoKKAABAHkiAA==.Govinniuur:BAAANQAECgIJAgAAAA==.',
Gr='Grasfedjones:BAAANQAECgQICQAAAA==.Gravelord:BAAANQAECgEIAQAAAA==.Grizzy:BAABNQAECn82AAIXAAoKmh+iCwDEAgAXAAoKmh+iCwDEAgAAAA==.Grue:BAEANQADCggIEAABNQAECgcIGQAPAEIFAA==.Gröthis:BAAANQAECgQIBwAAAA==.',
Gw='Gweilo:BAAANQAECggIBgAAAA==.Gwendilyn:BAAANQAECgIIAgAAAA==.',
Gy='Gyndrinolara:BAAANQAECgMIBgAAAA==.',
Ha='Hafadude:BAAANQAECggIAQAAAA==.Hahgottum:BAABNQAECn8eAAMEAAkKGxKVGgDnAQAEAAkKGxKVGgDnAQAOAAMKVgAwtgAsAAAAAA==.Handsomshlax:BAAANQADCgMIAwAAAA==.Haneo:BAAANQAECgEIAQAAAA==.',
He='Headhuntér:BAABNQAECn8YAAMdAAcK1gweCwBNAQAdAAYKwAgeCwBNAQABAAYKtQp4+wANAQAAAA==.Healgoßyeßye:BAAANQADCgYIBgAAAA==.',
Hi='Hikiru:BAAANQAECggIBgAAAA==.',
Hl='Hlzero:BAAANQAECgIIAwAAAA==.',
Ho='Hollandar:BAAANQADCgcIBwAAAA==.Holyflame:BAAANQAECgEIAQAAAA==.Holypewpewz:BAAANQAECgYICgAAAA==.Holyyshift:BAAANQAECgEIAQABNQAECgYICgAIAAAAAA==.Horhel:BAAANQAECgYIEQAAAA==.Hottstreak:BAAANQADCggICAAAAA==.',
Hu='Huehef:BAAANQADCgEIAQAAAA==.Hungmao:BAAANQADCggICAAAAA==.Huuron:BAAANQAECgIICAAAAA==.',
Hy='Hyperiann:BAAANQAECggIDwAAAA==.Hypnôtoâd:BAAANQAECgEIAQABNQAECgQIBwAIAAAAAA==.',
Ia='Iamfried:BAACNQAFFH8GAAIOAAMK1A1QDwDTAAAOAAMK1A1QDwDTAAA1AAQKfzAAAg4ACgpWHvMdANoCAA4ACgpWHvMdANoCAAAA.',
Ic='Iceyrot:BAAANQADCggIFgAAAA==.',
Ig='Igran:BAAANQAECgIIAgABNQAECgoKIQADAJQaAA==.',
Ih='Ihatemodels:BAAANQAECgYICQAAAA==.',
Il='Illidank:BAAANQADCgYICQAAAA==.Illidigle:BAAANQADCggIDAABNQAECgkJHwAgAKgUAA==.Ilurvyou:BAAANQADCgYIBgAAAA==.',
In='Inamorta:BAABNQAECn82AAMXAAoKKSDtCQDeAgAXAAkKKSDtCQDeAgAhAAgK7RgBJQAeAgAAAA==.Innarius:BAAANQAECgYICwAAAA==.Intothedark:BAAANQAECggICAAAAA==.Inviçtus:BAAANQADCgQIBAAAAA==.Inyadraug:BAAANQAECggIEgAAAA==.',
Ip='Ipurgeu:BAAANQADCgQIBAAAAA==.',
Ir='Ironheãrt:BAABNQAECn9IAAIkAAoKwB24DADPAgAkAAoKwB24DADPAgAAAA==.Ironjaws:BAAANQAECgUIBQAAAA==.Ironsight:BAAANQAECgMIAwAAAA==.Irontaco:BAAANQAECgMIAwAAAA==.Irsa:BAABNQAECn8WAAMKAAgKhBSybwDJAQAKAAgKhBSybwDJAQAkAAMKZwyzZABNAAAAAA==.',
Is='Isaacnewton:BAAANQAECgIIAgAAAA==.',
It='Itai:BAACNQAFFH8GAAITAAMKLRO/BQDuAAATAAMKLRO/BQDuAAA1AAQKf0EAAxMACgqCI2YDAL4DABMACgqCI2YDAL4DABQABQrADJxhANQAAAAA.',
Iv='Iverson:BAAANQAECgIIAgAAAA==.',
Iz='Izayam:BAAANQADCgcIBwABNQAECgkJIwAaAHciAA==.',
Ja='Jac:BAAANQAECgQIBAABNQAFFAgIGgAKACwXAA==.Jackk:BAACNQAFFH8aAAIKAAgKLBeGAwBeAgAKAAgKLBeGAwBeAgA1AAQKfy0AAwoACgrpIpYIAIMDAAoACgrpIpYIAIMDAAUABgrtDse8ABoBAAAA.Jackks:BAAANQAECgcIDwABNQAFFAgIGgAKACwXAA==.Jaddix:BAAANQADCgYICwAAAA==.Jalexandrea:BAAANQAECgQIDQAAAA==.Janzan:BAAANQAECgIIAgAAAA==.Jasmonk:BAABNQAECn8iAAILAAgKyQwNJgAwAQALAAgKyQwNJgAwAQAAAA==.Jaxed:BAAANQAECgEIAQAAAA==.',
Je='Jeeyell:BAAANQADCgUIBQAAAA==.Jellysickle:BAAANQADCgcICAAAAA==.Jemzz:BAABNQAECn8kAAMJAAoKWwjoIwARAQABAAoKrwefjwBOAQAJAAgK9AToIwARAQAAAA==.',
Ji='Jimmyray:BAAANQABCgYIBgAAAA==.Jinkua:BAAANQAECgIIAgABNQAECggIDAAIAAAAAA==.Jinkz:BAAANQAECgUICAAAAA==.',
Jo='Jolfurnuand:BAAANQAECgIIAgAAAA==.Jorhel:BAAANQADCggJDgAAAA==.Josephsmith:BAAANQAECggIBAAAAA==.Joshù:BAAANQAECggIDQABNQAECgoKIQADAJQaAA==.Joshú:BAAANQADCgEIAQABNQAECgoKIQADAJQaAA==.',
Ju='Judgementàl:BAAANQAECgcIDAABNQAFFAMICQARAPEFAA==.Judgevis:BAAANQAECgcIEAAAAA==.Jumbles:BAAANQAECgQIBQAAAA==.Justeene:BAAANQADCgEIAQABNQAECgYIEQAIAAAAAA==.',
Jy='Jynxy:BAAANQAECgQICgAAAA==.',
['Já']='Jáydn:BAAANQAECgMIBAABNQAECgkJMwAFAHsiAA==.',
['Jø']='Jøshu:BAAANQADCgYIBgABNQAECgoKIQADAJQaAA==.',
Ka='Kaeliis:BAABNQAECn8iAAIKAAoKhhVjLABDAgAKAAoKhhVjLABDAgAAAA==.Kagestrasz:BAAANQADCgYIBgAAAA==.Kaneggy:BAABNQAECn8VAAMcAAkK+QuyEQAbAQAcAAgKOQqyEQAbAQANAAUKLQzQqQDwAAAAAA==.Karrona:BAAANQADCggJDAAAAA==.Kazuu:BAABNQAECn8mAAIOAAkKNBe3IQC6AQAOAAkKNBe3IQC6AQAAAA==.',
Kb='Kbeckinsale:BAABNQAECn8rAAQfAAkK6R4CIwBvAgAfAAcKjR0CIwBvAgAbAAcKtx6zRwCVAQAlAAIKLwbJGABXAAAAAA==.',
Ke='Keladun:BAAANQADCgUIDwAAAA==.Kemaro:BAAANQAECggICAAAAA==.Keykey:BAAANQAECgEIAQAAAA==.',
Kh='Khallessi:BAAANQAECgQICQAAAA==.Kharga:BAABNQAECn8VAAISAAkKeBkNVwCFAQASAAkKeBkNVwCFAQAAAA==.Khonan:BAAANQADCgUIBgABNQAFFAEIAgAIAAAAAA==.',
Ki='Kiamar:BAAANQAECgYICwAAAA==.Kidgroove:BAAANQADCggICgAAAA==.Kishu:BAAANQADCggICAAAAA==.',
Kn='Kneecaps:BAAANQADCgcIBwAAAA==.',
Ko='Kolus:BAAANQADCggIEAAAAA==.Konamy:BAABNQAECn8nAAIaAAoK8BLtUgDwAQAaAAoK8BLtUgDwAQAAAA==.Kordarg:BAAANQADCgQIBAAAAA==.Korz:BAABNQAECn8WAAIgAAgKkxXSawDbAQAgAAgKkxXSawDbAQAAAA==.',
Kr='Krex:BAAANQADCgEIAQAAAA==.Kricket:BAAANQAECgEIAgAAAA==.Kriss:BAAANQAECgEIAQAAAA==.Kristeena:BAAANQAECgQIBAAAAA==.Kroldun:BAAANQADCgIIAgAAAA==.Kryptonikk:BAABNQAECn8eAAMGAAkK7gsfRAAUAQAGAAUKDAsfRAAUAQAgAAcKVQzomQDXAAAAAA==.Krystall:BAAANQADCgEIAQAAAA==.Kröw:BAABNQAECn8qAAIQAAkKPg59FgAAAgAQAAkKPg59FgAAAgAAAA==.',
Ku='Kudrix:BAABNQAECn8lAAILAAkKaR5VDwDuAgALAAkKaR5VDwDuAgAAAA==.Kurø:BAAANQAECgYIDgAAAA==.',
La='Lany:BAAANQADCgUIBgAAAA==.Latherfanta:BAAANQAECgMIBAAAAA==.Laurijaydn:BAABNQAECn8zAAIFAAkKeyL/FwDqAgAFAAkKeyL/FwDqAgAAAA==.Laurynn:BAAANQADCggIDQAAAA==.',
Le='Lechampion:BAAANQAECgQIBQAAAA==.Legendaries:BAAANQADCgEIAQAAAA==.Legionremix:BAAANQAECgEIAQAAAA==.Lelink:BAAANQADCgEIAQAAAA==.Levyathan:BAAANQADCgEIAQAAAA==.',
Li='Liath:BAAANQAECgUIDAAAAA==.Likeaglove:BAAANQADCgIIAgABNQAECgkJHwAgAKgUAA==.Lillina:BAAANQADCgIIAgAAAA==.Littlestarz:BAABNQAECn8YAAISAAgKZxu3SQA8AgASAAgKZxu3SQA8AgAAAA==.Lizzieag:BAEANQADCgYICwABNQAECgcINQABAGQXAA==.',
Ll='Llazz:BAACNQAFFH8NAAIKAAYK2xeABgDNAQAKAAYK2xeABgDNAQA1AAQKfywAAgoACgppHm4MAEEDAAoACgppHm4MAEEDAAAA.Llemons:BAAANQAECggIDwABNQAECggIGwAaANoTAA==.',
Lo='Locknlizzie:BAEBNQAECn81AAIBAAcKZBeMaABDAgABAAcKZBeMaABDAgAAAA==.Logic:BAAANQAECgEIAQABNQAECgUIEAAIAAAAAA==.Lohueng:BAAANQAECgMIBAAAAA==.Lolblur:BAAANQAECgQIBAAAAA==.Lolhigh:BAAANQAECgEIAQAAAA==.Lootah:BAAANQADCggIGAAAAA==.Loranoth:BAAANQADCggJIAAAAA==.Lovecox:BAAANQADCggIFAAAAA==.Lox:BAAANQAFFAEIAQAAAA==.',
Lu='Luke:BAABNQAECn8lAAIFAAkKgx3ZTgAKAgAFAAkKgx3ZTgAKAgAAAA==.Luminali:BAABNQAECn8bAAMKAAgK8g1rpAA6AQAKAAcKUAxrpAA6AQAFAAQKCw2pPAG/AAAAAA==.Luminari:BAAANQAECggIDQABNQAECggIGwAKAPINAA==.Lunadari:BAAANQAECgIJAwAAAA==.Lunareva:BAABNQAECn8oAAIEAAkK0B7jCgDhAgAEAAkK0B7jCgDhAgAAAA==.Lunä:BAAANQADCggICAABNQAFFAYIGQABAK8TAA==.',
Ly='Lyrielle:BAAANQADCgQIBQAAAA==.Lyxon:BAABNQAECn8rAAIEAAoKJRWtEwBGAgAEAAoKJRWtEwBGAgAAAA==.',
['Læ']='Lænna:BAAANQADCgUJBQAAAA==.',
['Lé']='Légoläs:BAAANQAECgMIBAAAAA==.',
['Lí']='Lílîth:BAAANQAECgMIAgAAAA==.',
Ma='Machiavellï:BAAANQAECgQIBAAAAA==.Mael:BAAANQADCgYICQABNQADCggICAAIAAAAAA==.Maeltne:BAAANQADCgYIBgAAAA==.Mafoôza:BAACNQAFFH8OAAINAAQKUQ/vGQC8AAANAAQKUQ/vGQC8AAA1AAQKfxoAAg0ACgq8E6uEABACAA0ACgq8E6uEABACAAAA.Magicalama:BAACNQAFFH8HAAIaAAQKGQy3IgDPAAAaAAQKGQy3IgDPAAA1AAQKfzgAAhoACgrsGcB9AIMCABoACgrsGcB9AIMCAAAA.Magiplex:BAAANQAECgYIEQAAAA==.Magnanimity:BAEANQAECgIIAgABNQAECgoKNQABAFoVAA==.Mahboyblu:BAAANQADCgEIAQAAAA==.Mahndoo:BAABNQAECn8bAAIaAAcK2hNX3gDLAQAaAAcK2hNX3gDLAQAAAA==.Makto:BAAANQAECgUIDAAAAA==.Malia:BAAANQAECgQIDwAAAA==.Maliciouso:BAAANQAECggIEwAAAA==.Malédiction:BAAANQAECgQIBgAAAA==.Manydoor:BAAANQADCgIIAgAAAA==.Mariemaya:BAAANQAECgEIAgAAAA==.Marley:BAABNQAECn8oAAIBAAkK3Ak+nADOAQABAAkK3Ak+nADOAQAAAA==.Matua:BAAANQAECgUICwAAAA==.Maximillian:BAAANQAECgQIBAAAAA==.Maymae:BAAANQAECgMIBAABNQAECgcIFwASAOkQAA==.',
Mc='Mcßlood:BAAANQAECggIEwAAAA==.',
Me='Meatsheeld:BAAANQAECgYIBgABNQAFFAQIBwABALwLAA==.Meepz:BAAANQAECgIIBAAAAA==.Megadk:BAAANQAECgUICAABNQAECggIGgAkAFweAA==.Megamacdin:BAABNQAECn8aAAMkAAcKXB63DwD0AQAkAAYKsSK3DwD0AQAFAAEKsgguqgEyAAAAAA==.Mendietta:BAABNQAECn8tAAISAAkKgRRBPgDrAQASAAkKgRRBPgDrAQAAAA==.Meridian:BAABNQAECn8jAAIgAAkKYxn7IgCYAgAgAAkKYxn7IgCYAgAAAA==.Mesna:BAAANQAECgQIBAAAAA==.',
Mi='Miistral:BAABNQAECn8fAAMKAAgKGhI7egCqAQAKAAgKGhI7egCqAQAFAAEKAACrvAEqAAAAAA==.Milkhoof:BAAANQAECgUIEQAAAA==.Mimie:BAAANQAECgUIDAAAAA==.Minki:BAAANQADCggICQAAAA==.Mistyeva:BAAANQAECgYIDAABNQAECgkJKAAEANAeAA==.Miyamoto:BAAANQADCgEIAQAAAA==.Miyoko:BAAANQADCgUIBwAAAA==.',
Mo='Moistooltip:BAABNQAECn8wAAILAAoK7B82BgBsAwALAAoK7B82BgBsAwAAAA==.Mokotrize:BAABNQAECn8qAAIkAAkKyxxLDwD8AQAkAAkKyxxLDwD8AQAAAA==.Mooscifer:BAAANQADCgYIBgAAAA==.Moosh:BAABNQAECn8cAAIWAAYKphL0LwAcAQAWAAYKphL0LwAcAQAAAA==.Morandara:BAAANQAECgEIAQAAAA==.Mordred:BAABNQAECn8ZAAIeAAYKvQUcIADGAAAeAAYKvQUcIADGAAAAAA==.Morria:BAAANQADCgIIAgAAAA==.Mouthkisser:BAAANQAECgQIAwAAAA==.',
Ms='Msfirefly:BAAANQAECgQIBAABNQAECgoKNAASANUeAA==.',
Mu='Mud:BAAANQAECggIDwAAAA==.Mudslinger:BAAANQAECgcICAAAAA==.Munchies:BAABNQAECn8lAAMbAAkK4RkpOQDVAQAbAAcKKRcpOQDVAQAfAAkKAxTPHgAdAQABNQAFFAQICQAUALgJAA==.',
My='Myrolan:BAAANQADCgYICgABNQADCgcICwAIAAAAAA==.Myrrha:BAAANQAECggICQAAAA==.',
['Mø']='Møønwuu:BAABNQAECn8ZAAIfAAoK/ws0EACiAQAfAAoK/ws0EACiAQAAAA==.',
Na='Naarf:BAAANQAECgIIAgABNQAFFAQIBwABALwLAA==.Nanoko:BAAANQAECgIIAgAAAA==.Naora:BAAANQAECgEIAQABNQAECgUIDAAIAAAAAA==.Natedoggydog:BAAANQAECggICQAAAA==.',
Ne='Neckslice:BAACNQAFFH8TAAIPAAgKthN6AwBvAgAPAAgKthN6AwBvAgA1AAQKfzEAAg8ACgqSJMoGADgDAA8ACgqSJMoGADgDAAAA.Nefertm:BAAANQADCgQIAwAAAA==.Nemophilist:BAAANQABCgIIAgAAAA==.Neural:BAAANQAECgcICgAAAA==.Neuro:BAABNQAECn8jAAMaAAkKdyL+MwAiAwAaAAkKdyL+MwAiAwAmAAEKFhicQABDAAAAAA==.',
Ni='Nichdru:BAAANQADCgcICwAAAA==.Nicolico:BAAANQAECgQIBAAAAA==.Nictamom:BAAANQAECgEIAQAAAA==.Nightfaze:BAAANQAECgMIBAABNQAECgYIEQAIAAAAAA==.Nightnite:BAAANQADCgYIDgAAAA==.Nij:BAAANQAECgEIAQAAAA==.Nirri:BAAANQAECgUIDgAAAA==.Nitefall:BAABNQAECn8gAAIBAAkKXBSyhgD+AQABAAkKXBSyhgD+AQAAAA==.Nithon:BAAANQAECggIEAAAAA==.',
No='Nocando:BAABNQAECn8fAAIgAAkKqBSHSgBGAgAgAAkKqBSHSgBGAgAAAA==.Notadk:BAABNQAECn8bAAIUAAgKIBCmPQBnAQAUAAgKIBCmPQBnAQAAAA==.Nott:BAAANQAECgEIAQAAAA==.Noturbudpal:BAAANQADCgQIBgABNQAECgoKdwAVAFoZAA==.',
Nu='Nuggets:BAAANQAECgIIAgAAAA==.Nuriel:BAAANQADCgQIBAAAAA==.',
Ny='Nylinuya:BAAANQAECgUIEAABNQAECgoKRAAYAAciAA==.Nywen:BAAANQADCgUIBQAAAA==.',
Ob='Obligated:BAAANQAECgIIAgAAAA==.Obsydia:BAAANQADCgcIBwAAAA==.',
Oc='Occulus:BAAANQAECgEIAQAAAA==.',
Ok='Okowilly:BAAANQADCggIDQAAAA==.',
Ol='Oline:BAABNQAECn8VAAICAAkKySGAIgD6AgACAAkKySGAIgD6AgAAAA==.',
On='Onijunk:BAAANQADCgQIBAAAAA==.',
Oo='Oonaki:BAABNQAECn8XAAMVAAoKqwdcbgA7AQAVAAcKgAhcbgA7AQAUAAQKMgVwhQBqAAAAAA==.',
Or='Orchideva:BAAANQAECgQICQABNQAECgkJKAAEANAeAA==.Oriphiel:BAAANQAECgUIDQAAAA==.',
Ot='Ottoshock:BAAANQADCgUIBQAAAA==.',
Ow='Owl:BAAANQADCggICQAAAA==.',
Pa='Painloa:BAABNQAECn8WAAMTAAcKIQj9hQAJAQATAAYKGQj9hQAJAQAUAAYK0wUWhgCYAAAAAA==.Pandanimal:BAAANQAECgIIAgAAAA==.Papapally:BAAANQADCgUIBwAAAA==.Paradoxx:BAABNQAECn83AAImAAoKoyS5AgA0AwAmAAoKoyS5AgA0AwAAAA==.',
Pe='Pestelince:BAAANQAECgMIBAAAAA==.',
Ph='Phelefica:BAAANQAECgQIAwAAAA==.Phreyja:BAAANQADCgYICAAAAA==.Phylgon:BAABNQAECn8nAAMgAAgK8xDHVQCqAQAgAAgK8xDHVQCqAQAGAAEKAAAJlgANAAAAAA==.',
Pl='Pleblords:BAAANQAECgIICAAAAA==.',
Pm='Pmac:BAAANQAECgYIDgABNQAECggIGgAkAFweAA==.',
Po='Poggrin:BAAANQAECgUICQAAAA==.Pogrin:BAAANQAECgQICwAAAA==.Pointybrows:BAAANQAECgQIDgAAAA==.',
Pr='Premmier:BAAANQADCgQIBQAAAA==.Prudeix:BAAANQADCgUIBQAAAA==.Pryona:BAAANQAECgEIAQABNQAECgQIBgAIAAAAAA==.',
Pu='Putrescence:BAAANQAECgIIAgAAAA==.',
Pw='Pwnhubb:BAAANQADCgYIBwAAAA==.',
Py='Pyràbànks:BAAANQADCgYIBgAAAA==.',
Qu='Quan:BAAANQAECgEIAQAAAA==.Quelestraza:BAABNQAECn8wAAMRAAkKaxUnDwDZAQARAAkKaxUnDwDZAQADAAEKAACRPgAvAAAAAA==.Quikkmex:BAAANQAECgQIBwAAAA==.',
Ra='Rabbit:BAAANQADCgQIBAAAAA==.Raewyck:BAABNQAECn8rAAIBAAoKKw/ieQAbAgABAAoKKw/ieQAbAgAAAA==.Raginbull:BAABNQAECn85AAMMAAgKihyMDAC3AQAMAAgKihyMDAC3AQANAAMK3Qa6CwE6AAAAAA==.Ragingmaze:BAABNQAECn8mAAQVAAgKbBPUTQC/AQAVAAgKbBPUTQC/AQATAAgKsgTjfwAdAQAUAAIKQAWzngBTAAAAAA==.Rainburrow:BAABNQAECn8wAAMLAAoKORXiEgABAgALAAoKqxHiEgABAgAjAAcK3hjDDQAeAQAAAA==.Raptormortis:BAAANQAECgQIBgAAAA==.Rastlinn:BAAANQAECggICQAAAA==.Raziyya:BAAANQAECgEIAQAAAA==.',
Re='Rebalite:BAAANQABCgEIAQAAAA==.Reinitia:BAAANQADCgcICwAAAA==.Reinnii:BAAANQAECgUIEQAAAA==.Renkagisa:BAAANQADCgUIBQAAAA==.Resurrection:BAAANQAECgEIAQAAAA==.Retana:BAABNQAECn84AAIFAAoKJCNjFQD3AgAFAAoKJCNjFQD3AgAAAA==.Reticence:BAAANQABCgIIAgAAAA==.Retrisan:BAAANQABCgQIBAAAAA==.Retroflex:BAAANQAECgEIAQABNQAECgYIDAAIAAAAAA==.',
Rh='Rhalk:BAAANQADCgEIAQAAAA==.Rhinn:BAABNQAECn8gAAIQAAcKZQW5IgAwAQAQAAcKZQW5IgAwAQAAAA==.',
Ri='Rickypeepee:BAABNQAECn8kAAIFAAkKGx4PRADIAgAFAAkKGx4PRADIAgAAAA==.Rider:BAAANQABCgIIBAAAAA==.Rigatoni:BAAANQAECgIIBAAAAA==.Rizzlybear:BAAANQAECgEIBAAAAA==.',
Ro='Roastedz:BAABNQAECn8jAAIZAAgKfQsTCQALAQAZAAgKfQsTCQALAQAAAA==.Roflmaster:BAAANQAECgEIAQAAAA==.Rojen:BAAANQAECgQIEQAAAA==.Rorthu:BAAANQAECgIIAgAAAA==.',
Ru='Rukélie:BAAANQAECgIIAgAAAA==.',
Ry='Ry:BAAANQAECggIEAAAAA==.Ryanna:BAABNQAECn8jAAIaAAkKygmCgQB3AQAaAAkKygmCgQB3AQAAAA==.',
Sa='Sacrilege:BAAANQABCgIIAgAAAA==.Saevio:BAABNQAECn8xAAQTAAoKAhT1FgAHAgATAAkKXhL1FgAHAgAUAAcKHhJ3RgCmAQAVAAQKqhCyigDWAAAAAA==.Sajin:BAAANQAECgMIAwAAAA==.Salvader:BAABNQAECn8kAAIJAAgKvxTuJgAUAgAJAAgKvxTuJgAUAgAAAA==.Sanctus:BAAANQAECgUICQAAAA==.Sashimi:BAACNQAFFH8JAAMUAAQKuAkLDgDAAAAUAAMKuAkLDgDAAAATAAIK6wM3EwAAAAA1AAQKf0MAAxMACgq4Hw0HAO0CABMACgqCHw0HAO0CABQACgrwGawXAM0CAAAA.Sataves:BAAANQABCgMIAwAAAA==.Satharis:BAAANQAECgUICQAAAA==.',
Sc='Scarlet:BAAANQAECgQIBgABNQAFFAQICQAUALgJAA==.Scarllett:BAABNQAECn8iAAMSAAoKcw/ppAAqAQASAAkKgw7ppAAqAQAPAAcKEhCJtgAlAQAAAA==.Scoot:BAEANQAECggIEAABNQAFFAMIBAAIAAAAAA==.Scrappurr:BAAANQAECgEIAQAAAA==.Scrubiclese:BAAANQAECgUIBQAAAA==.Scrytearia:BAAANQABCgIJAgAAAA==.',
Se='Seldaren:BAAANQAECgMICgAAAA==.Selfward:BAAANQAECgQIBwAAAA==.Seran:BAABNQAECn8YAAIBAAkKlhAoRAAQAgABAAkKlhAoRAAQAgAAAA==.Serenade:BAAANQAECgYIDgAAAA==.Seviana:BAABNQAECn8aAAIKAAoK3R47FwAfAwAKAAoK3R47FwAfAwABNQAFFAcIIgARAEMlAA==.Sevie:BAACNQAFFH8iAAIRAAcKQyX1AQCnAgARAAcKQyX1AQCnAgA1AAQKfz8AAhEACgqTJdEBAKsDABEACgqTJdEBAKsDAAAA.',
Sh='Shabbyy:BAAANQADCgYIDAABNQAECgQIBwAIAAAAAA==.Shadowpump:BAABNQAECn8dAAQGAAcKuRSrOABgAQAGAAYKBxGrOABgAQAgAAUKvhb9mgBEAQAnAAEKzQsDLAAsAAAAAA==.Shalada:BAAANQADCgUIBQAAAA==.Shamsel:BAABNQAECn80AAIGAAkK9hCeFwCsAQAGAAkK9hCeFwCsAQAAAA==.Shellack:BAAANQAECgIIAgAAAA==.Shinnz:BAABNQAECn9YAAMFAAoKrBxWMgBtAgAFAAoKrBxWMgBtAgAKAAMK8QCJHQE5AAAAAA==.Shockcaller:BAAANQAECgYIDQAAAA==.Shockingnut:BAAANQAECgUICQAAAA==.Showtooltip:BAAANQAECgQIAwABNQAECgoKMAALAOwfAA==.Shoöman:BAAANQADCgEIAQAAAA==.Shrabster:BAABNQAECn8WAAIaAAcKXwhF6gCxAAAaAAcKXwhF6gCxAAABNQAECgQIBwAIAAAAAA==.Shweatyballs:BAAANQADCgQIBAAAAA==.',
Si='Silversong:BAABNQAECn8tAAMBAAkKWxyWPAApAgABAAkKWxyWPAApAgAdAAEKqBJyEgBAAAAAAA==.Simmara:BAAANQAECgMIBwAAAA==.Sip:BAAANQAECgQICAABNQAECgYIDAAIAAAAAA==.',
Sk='Skapelijones:BAAANQAECgMIBAAAAA==.Skipper:BAAANQAECgIIBAAAAA==.Skylinelol:BAAANQAECggIEAAAAA==.Skywalkah:BAAANQADCgQIBAABNQAECgEIAgAIAAAAAA==.',
Sm='Smallcurse:BAAANQAECgYICgAAAA==.Smallighting:BAABNQAECn8zAAQSAAoKJhIFYADuAQASAAoKJhIFYADuAQAQAAUKxBRsIwAlAQAPAAQKpxM30ADzAAAAAA==.Smokiemcpot:BAAANQAECgQIBgAAAA==.',
So='Solanthis:BAAANQAECgEJAQAAAA==.Solstica:BAABNQAECn8jAAMnAAoKGBpKAQDxAgAnAAoKGBpKAQDxAgAGAAEKAADEjgAcAAAAAA==.',
Sp='Sparli:BAAANQAECgEIAQAAAA==.Spiritualone:BAABNQAECn8gAAIkAAkK2RLlLAB2AQAkAAkK2RLlLAB2AQAAAA==.',
Sq='Sqwaat:BAAANQAECgIJAwAAAA==.',
St='Steelrib:BAABNQAECn8iAAIVAAcKEAVfXACrAAAVAAcKEAVfXACrAAAAAA==.Stonystark:BAAANQAECgUICAAAAA==.Straam:BAACNQAFFH8PAAISAAQKTAlmEgD1AAASAAQKTAlmEgD1AAA1AAQKf1wAAxIACgpDGyoiAIACABIACgpDGyoiAIACAA8ABwokEKqfAFcBAAAA.Strizzle:BAEBNQAECn8ZAAIPAAcKQgUwpwBGAQAPAAcKQgUwpwBGAQAAAA==.Stupidity:BAAANQADCggICAAAAA==.Støney:BAAANQAECgYIDwAAAA==.',
Su='Subatronic:BAACNQAFFH8iAAIVAAgKsSQiAgCOAgAVAAgKsSQiAgCOAgA1AAQKfz8AAhUACgrnJosAAIoDABUACgrnJosAAIoDAAAA.Subfractal:BAAANQADCgYIBgABNQAFFAgIIgAVALEkAA==.Surealadin:BAAANQADCgYIBgAAAA==.',
Sy='Sylthara:BAABNQAECn8aAAQSAAYKuxIjkQBdAQASAAYKuxIjkQBdAQAPAAMKowGO6gAtAAAQAAEKAABhPAASAAAAAA==.Syrothea:BAAANQADCgUJBQAAAA==.',
Ta='Tacokicker:BAAANQADCgcIBwAAAA==.Tahumm:BAABNQAECn8iAAINAAgKGBUjVgDGAQANAAgKGBUjVgDGAQAAAA==.Takki:BAABNQAECn8ZAAINAAkKehhqjAAzAQANAAkKehhqjAAzAQAAAA==.Talethia:BAABNQAECn8XAAIaAAcKQBG+ngA7AQAaAAcKQBG+ngA7AQAAAA==.Tamsîn:BAABNQAECn81AAIYAAoKORymAwC3AgAYAAoKORymAwC3AgAAAA==.Tazlinmon:BAAANQADCgYIBgABNQAECgYIEQAIAAAAAA==.',
Tb='Tbonez:BAAANQADCgIIAgABNQAECgcIIgAVABAFAA==.',
Te='Teapawt:BAAANQAECgYIBgAAAA==.Teech:BAAANQAECgEIAQAAAA==.Teinuya:BAABNQAECn9EAAQYAAoKByICAgAZAwAYAAkK8CACAgAZAwAZAAUK/SLbDwAAAgACAAEKnwi2CQEqAAAAAA==.Tenderfiddle:BAAANQADCgEIAQAAAA==.Tenochitilan:BAABNQAECn8YAAMSAAgKpQ7XnQA8AQASAAcKdwvXnQA8AQAPAAIK6A8cEgFoAAAAAA==.',
Th='Thedon:BAAANQAECgEIAQAAAA==.Themagi:BAAANQADCgYIBgAAAA==.Theocracy:BAAANQAECgQIDQAAAA==.Thia:BAAANQAECgEIAQAAAA==.Thoorz:BAAANQAECgIIAwAAAA==.Thorimeir:BAAANQAECgUIBQAAAA==.Thorzy:BAAANQAECggIEQABNQAECgIIAwAIAAAAAA==.Thraxacious:BAABNQAECn9MAAIHAAoKdyDCAwDSAgAHAAoKdyDCAwDSAgAAAA==.Thulsadoomm:BAABNQAECn8VAAIVAAYKfh2TQAD8AQAVAAYKfh2TQAD8AQAAAA==.Thundermay:BAABNQAECn8XAAISAAcK6RAGZgBRAQASAAcK6RAGZgBRAQAAAA==.',
Ti='Tiduss:BAABNQAECn8WAAIMAAUKMQupLADSAAAMAAUKMQupLADSAAAAAA==.Tigó:BAAANQAECgcIDQAAAA==.Tigölebittie:BAAANQADCgEIAQAAAA==.Tiik:BAABNQAECn8iAAIoAAcKjxpjDwDdAQAoAAcKjxpjDwDdAQAAAA==.Timorrow:BAAANQADCgcICwAAAA==.Tinkerbel:BAABNQAECn8nAAIKAAkKThxYNQCPAgAKAAkKThxYNQCPAgAAAA==.Tinkerbella:BAAANQAECgQIBQAAAA==.Tinkerrbella:BAAANQAECgEIAQABNQAFFAYIGQABAK8TAA==.Tireliaa:BAAANQADCgUIBgAAAA==.Tisem:BAAANQADCgEIAQAAAA==.',
To='Toe:BAAANQADCgIIAgAAAA==.Tohsaka:BAAANQADCgQICQAAAA==.Torsin:BAAANQADCgIIAgAAAA==.Totamic:BAAANQAECgQIBwAAAA==.',
Tr='Trafalgor:BAAANQAECgQIBwAAAA==.Trafalgour:BAAANQAECgEIAQAAAA==.Trazen:BAAANQAECgEIAgAAAA==.Tribulationz:BAAANQADCgUIBQABNQAECgYIEAAIAAAAAA==.Triplebolt:BAAANQAECgQIBQAAAA==.Try:BAAANQAECggIBAABNQAECggIEAAIAAAAAA==.',
Ts='Tsukinagi:BAAANQAECgIIAgAAAA==.Tsun:BAABNQAECn8iAAMNAAkKWw5pnQDTAQANAAkKWw5pnQDTAQAMAAYKbwZcLABtAAAAAA==.Tsurinoya:BAAANQAECgIIAgAAAA==.',
Tu='Tundal:BAAANQAECgQIBwAAAA==.',
Ty='Tydz:BAAANQAECgEIBAABNQAFFAYIEAAKAIMPAA==.Tyylerdurden:BAAANQAECgEIAQAAAA==.',
Ua='Uafraidofme:BAAANQAECgcICwAAAA==.',
Ud='Uddermishap:BAEANQADCgYIBgABNQAECgoKNQABAFoVAA==.Uddertrouble:BAEBNQAECn81AAIBAAoKWhUCQwAUAgABAAoKWhUCQwAUAgAAAA==.',
Ul='Ulfgrim:BAAANQAECgEIAQAAAA==.',
Un='Unholytiran:BAAANQAECgYIDAAAAA==.',
Ur='Urmada:BAABNQAECn8qAAMmAAkK1RCcDADvAQAmAAgKlhKcDADvAQAaAAEKUwYvTwEpAAAAAA==.Urmami:BAABNQAECn8eAAICAAkKQxNpTQC0AQACAAkKQxNpTQC0AQAAAA==.Urmyenemy:BAAANQADCgEIAQAAAA==.',
Ut='Utterlyaloof:BAAANQAECggICAAAAA==.',
Uz='Uzui:BAAANQAECgIIAgAAAA==.',
Va='Valyne:BAAANQAECgQIBwAAAA==.Vampire:BAABNQAECn8cAAIhAAgKgB8FEQDnAgAhAAgKgB8FEQDnAgAAAA==.Vampyre:BAABNQAECn8VAAIVAAkKlhuJLQBgAgAVAAkKlhuJLQBgAgAAAA==.Vanadie:BAAANQAECgIIAgAAAA==.Vanta:BAAANQAECgEIAQAAAA==.Varekth:BAAANQADCgMIAwAAAA==.Vargmal:BAAANQAECgUIBgAAAA==.',
Vi='Virala:BAAANQAECgQIBwAAAQ==.Visenya:BAAANQAECgMIBQAAAA==.Visquake:BAAANQAECgIIBQAAAA==.Vitamin:BAAANQADCgcIBwABNQAECggIIQAFAGAfAA==.Vitaminn:BAABNQAECn8hAAQFAAgKYB9fdQBDAgAFAAgKYB9fdQBDAgAkAAEKDQr4VwAzAAAKAAEKIQOhKQEsAAAAAA==.',
Vl='Vlaen:BAAANQAECgQIBAAAAA==.',
Vo='Votum:BAAANQADCgkJFgAAAA==.',
Vy='Vyrisa:BAAANQAECgEIAgAAAA==.Vyrma:BAAANQADCgIIAgAAAA==.',
Wa='Warpstorms:BAAANQADCgQIBAAAAA==.Warpwalker:BAAANQADCgEIAQAAAA==.Wasabii:BAAANQAECgYICwABNQAFFAQICQAUALgJAA==.',
Wh='Whisa:BAABNQAECn8mAAIgAAoK+h2HDgBBAwAgAAoK+h2HDgBBAwAAAA==.White:BAAANQADCggICAABNQAFFAgIEwAPALYTAA==.',
Wi='Wildwolff:BAAANQAECgMIAwAAAA==.Wilhedin:BAABNQAECn8rAAINAAgKKCQVJgAhAwANAAgKKCQVJgAhAwAAAA==.Willowwind:BAAANQAECgMIAwABNQAECgkJIgAoAMogAA==.Wing:BAEANQAFFAMIBAAAAA==.',
Wo='Wolfblade:BAAANQADCgQIBQAAAA==.Worm:BAACNQAFFH8SAAINAAgKOxfXBgBUAgANAAgKOxfXBgBUAgA1AAQKfzsAAg0ACgqUIwEOABcDAA0ACgqUIwEOABcDAAAA.',
Wu='Wulfnbolt:BAAANQAECgUJCAAAAA==.',
Ww='Wwoman:BAAANQAECgIIAgAAAA==.',
Wy='Wyon:BAAANQAECgcIKAAAAQ==.',
['Wî']='Wîtçhplz:BAAANQADCggICAAAAA==.',
Ya='Yasnah:BAAANQADCggIEgAAAA==.',
Yu='Yunahpabo:BAABNQAECn88AAINAAoKbSCPHAC6AgANAAoKbSCPHAC6AgAAAA==.Yurna:BAAANQADCgMIAgAAAA==.',
Za='Zaffyl:BAAANQADCggIDAAAAA==.Zandi:BAAANQAECgUIEAAAAA==.Zanikan:BAAANQAECggIDAAAAA==.Zankuza:BAAANQAECggIBAAAAA==.Zathara:BAABNQAECn9EAAIHAAoKzxbhCQD4AQAHAAoKzxbhCQD4AQAAAA==.',
Zi='Zinpan:BAAANQAECgcICAAAAA==.',
Zo='Zodiac:BAABNQAECn8oAAINAAkKkhbQUwDPAQANAAkKkhbQUwDPAQAAAA==.Zoopals:BAAANQADCgcICwAAAA==.',
Zu='Zuggle:BAAANQAECgUIBgAAAA==.Zuluk:BAABNQAECn8ZAAMBAAgKwRERkwDjAQABAAcKGxQRkwDjAQAJAAQKygPAbgB2AAAAAA==.',
['Zö']='Zörö:BAABNQAECn87AAMTAAkKFBfuXQCYAQATAAgKFBfuXQCYAQAVAAkKuAlJRgD7AAAAAA==.',
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
