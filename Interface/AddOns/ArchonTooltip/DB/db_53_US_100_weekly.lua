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

local lookup = {'Hunter-BeastMastery','Warlock-Demonology','Evoker-Devastation','Druid-Restoration','Paladin-Retribution','Priest-Shadow','Druid-Feral','Paladin-Protection','Unknown-Unknown','Hunter-Marksmanship','Paladin-Holy','Monk-Windwalker','Warrior-Protection','Warrior-Arms','Druid-Balance','Shaman-Elemental','Shaman-Enhancement','Evoker-Preservation','Shaman-Restoration','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Druid-Guardian','DemonHunter-Havoc','Warlock-Destruction','Warlock-Affliction','Mage-Arcane','Rogue-Subtlety','Warrior-Fury','Hunter-Survival','DemonHunter-Vengeance','Rogue-Assassination','Priest-Holy','DemonHunter-Devourer','Evoker-Augmentation','Monk-Brewmaster','Rogue-Outlaw','Mage-Frost','Priest-Discipline','Monk-Mistweaver',}
local provider = {region='US',realm='Frostwolf',name='US',type='weekly',zone=53,date='2026-11-17',data={Aa='Aamodar:BAABNQAECn8hAAIBAAgKbRTEiwCgAQABAAgKbRTEiwCgAQAAAA==.',
Ab='Abadon:BAABNQAECn8zAAICAAoKkRmPKgBlAgACAAoKkRmPKgBlAgAAAA==.',
Ac='Acathisia:BAAANQADCgcIBwAAAA==.',
Ad='Adino:BAABNQAECn8sAAIBAAgKSA3mgwCxAQABAAgKSA3mgwCxAQAAAA==.Adorabell:BAAANQAECggIDQABNQAFFAYIGgABALUZAA==.Adrassa:BAAANQADCgYIBgABNQAECgoKJwADANIaAA==.Adric:BAAANQADCgIIAgAAAA==.',
Ae='Aerostar:BAABNQAECn9CAAIEAAoKbx6ECwAUAwAEAAoKbx6ECwAUAwAAAA==.Aeryn:BAACNQAFFH8TAAIFAAYKEB45CgBEAQAFAAYKEB45CgBEAQA1AAQKf0QAAgUACgouI3gSAH4DAAUACgouI3gSAH4DAAAA.Aerís:BAAANQAECgQIBgAAAA==.',
Ag='Aggranak:BAAANQAECggICAAAAA==.Aglaia:BAAANQAECgcIEwAAAA==.Agrolazor:BAACNQAFFH8KAAIGAAQKpAjbDADKAAAGAAQKpAjbDADKAAA1AAQKfywAAgYACgpTFj4dAFgCAAYACgpTFj4dAFgCAAAA.',
Ah='Ahote:BAABNQAECn8eAAIHAAkKSyahAACFAwAHAAkKSyahAACFAwAAAA==.Ahtee:BAABNQAECn86AAMFAAoKMRROcgDqAQAFAAoKMRROcgDqAQAIAAEKAACffwAAAAAAAA==.',
Al='Alara:BAAANQABCgQIBgAAAA==.Albarino:BAAANQADCgYIBgAAAA==.Algodon:BAABNQAECn8hAAIFAAgK/xWFwgCXAQAFAAgK/xWFwgCXAQABNQAFFAMIBQABAKodAA==.Alseena:BAAANQAECgUIDAAAAA==.',
Am='Amun:BAAANQAECggIEQAAAA==.',
An='Andenarras:BAAANQAECgQIBAABNQAECgYIEAAJAAAAAA==.Anthais:BAAANQAECgUIBwAAAA==.Anvar:BAACNQAFFH8HAAIBAAQKvAuPGgC/AAABAAQKvAuPGgC/AAA1AAQKf0gAAwEACgr4ILYiALQCAAEACgr4ILYiALQCAAoACAqiDn81AKIBAAAA.',
Ar='Arathion:BAABNQAECn8xAAILAAkKLB8zFwD+AgALAAkKLB8zFwD+AgAAAA==.Arcanemommy:BAAANQAECggIAgAAAA==.Archistrate:BAAANQADCgQIBAAAAA==.Ariandra:BAAANQADCggICAABNQAECgoKJwADANIaAA==.Arianrhod:BAACNQAFFH8MAAIMAAQK9xMYCgDTAAAMAAQK9xMYCgDTAAA1AAQKfyMAAgwACgpzIScIAE0DAAwACgpzIScIAE0DAAAA.Artamir:BAAANQABCgYIBgAAAA==.Arx:BAABNQAECn8lAAMNAAkKch75EQAHAgAOAAkKfhaGhwAJAgANAAcKrSD5EQAHAgAAAA==.',
As='Ashaldrin:BAAANQAECgEIAgAAAA==.Ashleyk:BAAANQAECgEIAQAAAA==.Aska:BAAANQADCgIIAgAAAA==.',
At='Atrumdeus:BAACNQAFFH8PAAIFAAUKpQk0GwC8AAAFAAUKpQk0GwC8AAA1AAQKf0wAAgUACgq2GnFhAHUCAAUACgq2GnFhAHUCAAAA.',
Au='Audiamer:BAABNQAECn9EAAIPAAoKhQ2NKQCzAQAPAAoKhQ2NKQCzAQAAAA==.Aufsela:BAAANQAECgEIAQABNQAECgoKJwADANIaAA==.',
Az='Azraelor:BAACNQAFFH8SAAMQAAYKrhdLDAAZAQAQAAYKtxBLDAAZAQARAAMKSBhEBAACAQA1AAQKf2EAAxEACgqcJKECADADABEACgqcJKECADADABAACgoNHidLAEoCAAAA.Azureshal:BAABNQAECn8nAAIDAAoK0hqIBQBlAgADAAoK0hqIBQBlAgAAAA==.',
Ba='Babydragon:BAACNQAFFH8OAAMSAAUKSQuRDwDiAAASAAQKewWRDwDiAAADAAEKAABsCwAAAAA1AAQKfy8AAxIACgp4EoEYADUCABIACgp4EoEYADUCAAMAAQqiBo0oACcAAAAA.Babysaja:BAABNQAECn8gAAIOAAoKbQyJbAC8AQAOAAoKbQyJbAC8AQAAAA==.Bangerz:BAAANQAECggIDgAAAA==.Bannann:BAABNQAECn8hAAMTAAkK7BxMLQCtAgATAAkK7BxMLQCtAgAQAAEKAABeTgEnAAAAAA==.Baojai:BAAANQAFFAEIAQAAAA==.',
Be='Beaksbigdk:BAABNQAECn8zAAQUAAoK2iSZFQANAwAUAAoKPiOZFQANAwAVAAkK7R6/EgC5AgAWAAEKYyU3sABrAAAAAA==.Beamkin:BAAANQAECgEIAQAAAA==.Beefÿfridge:BAAANQADCggIFgAAAA==.Belfegor:BAAANQAECgcICwAAAA==.Belldia:BAACNQAFFH8aAAIBAAYKtRlgBwDZAQABAAYKtRlgBwDZAQA1AAQKf0oAAgEACgq8IgcUAE4DAAEACgq8IgcUAE4DAAAA.Belphaegor:BAABNQAECn9VAAMXAAoKbht5DABwAgAXAAoKbht5DABwAgAPAAUKpg0ycAAJAQAAAA==.Beni:BAABNQAECn8oAAIOAAkKrx3RJwCgAgAOAAkKrx3RJwCgAgAAAA==.Beniaru:BAABNQAECn8yAAICAAkKih7nJAB+AgACAAkKih7nJAB+AgAAAA==.Bennyflipz:BAABNQAECn8bAAIYAAoKjhCvJwDPAQAYAAoKjhCvJwDPAQAAAA==.',
Bi='Bigmuzz:BAAANQADCgYICAAAAA==.Bigobuffalo:BAAANQAECgQIDQAAAA==.Bigsneaki:BAAANQADCgUIBQAAAA==.',
Bl='Blightedmilk:BAABNQAECn8sAAQZAAoKjxoxBwBiAQAaAAoKmhTkBQAaAgAZAAYKURkxBwBiAQACAAMKtxGWzQC2AAABNQAFFAQIBQAaANcQAA==.Bloopmasta:BAAANQAECggICAAAAA==.Blufox:BAABNQAECn9EAAMFAAoKTyXZCQBPAwAFAAoKTyXZCQBPAwALAAIKZgA5FQEEAAAAAA==.',
Bo='Bobfresh:BAABNQAECn9MAAIQAAoK9SWoBwCrAwAQAAoK9SWoBwCrAwAAAA==.Bowtugger:BAAANQAECgQICAAAAA==.',
Br='Brackenreid:BAAANQADCgUIBQAAAA==.Bracks:BAAANQAECgIIAgAAAA==.Brett:BAAANQAECgQIBgAAAA==.Brighamyoung:BAAANQAECggIBQAAAA==.Broherum:BAAANQADCgQJBAAAAA==.Bronzetusk:BAAANQABCgIIAgAAAA==.Brothalittle:BAAANQADCgIIAgAAAA==.Brush:BAAANQAECgEIAQAAAA==.',
Bu='Bubblêosêvên:BAAANQAECgYICwAAAA==.Buc:BAAANQADCgIIBAAAAA==.Buckbeak:BAAANQADCggICAABNQAECgoKMwAUANokAA==.Busting:BAABNQAECn82AAIbAAoKuSGcJQBJAwAbAAoKuSGcJQBJAwAAAA==.Buttmucker:BAAANQAECggICAAAAA==.',
By='Byusoaker:BAAANQABCgEIAQABNQAECggIGQAcAJEOAA==.',
['Bà']='Bàhamut:BAAANQAECgQICgAAAA==.',
['Bå']='Båemax:BAAANQADCgYIBgAAAA==.',
Ca='Camellieva:BAAANQAECggIEAABNQAECgoKMAAEAF4gAA==.Captchaos:BAAANQAECggIDwAAAA==.Carritha:BAAANQAECgMIAwABNQAECgMIBwAJAAAAAA==.Cayo:BAAANQADCgQIBAAAAA==.',
Ce='Cewkie:BAABNQAECn9EAAIdAAoKMBmABgBaAgAdAAoKMBmABgBaAgAAAA==.',
Ch='Charlixchix:BAAANQAECgMIAwABNQAECggIGQAcAJEOAA==.Chimneybones:BAABNQAECn8hAAMOAAoKkgvtnwDNAQAOAAoKkgvtnwDNAQAdAAEKoQnyNQA0AAAAAA==.Chizz:BAABNQAECn8fAAIbAAkKKgvL0wDfAQAbAAkKKgvL0wDfAQAAAA==.Chriswong:BAABNQAECn8YAAMBAAkK5xKGhwD8AQABAAkK5xKGhwD8AQAKAAEKvgMHeAAgAAAAAA==.Chronoslicer:BAAANQABCgIIAgAAAA==.Chuckfnnoris:BAAANQAECgQIBAAAAA==.Chá:BAAANQADCggIEAABNQAFFAUICAAUAIwTAA==.',
Cl='Clairebenet:BAABNQAECn85AAMBAAoKVB2uMADaAgABAAkK5R2uMADaAgAeAAoK4xmbAwBpAgAAAA==.Claymoor:BAAANQAECgIIAgAAAA==.Cleph:BAAANQAECggIEAAAAA==.Clumzylock:BAAANQAECgcIEgABNQAECgoKjwAWANAZAA==.Clumzyninja:BAABNQAECn+PAAIWAAoK0BnPIQCnAgAWAAoK0BnPIQCnAgAAAA==.',
Co='Colonoscope:BAAANQAECgYICAABNQAECgYIDgAJAAAAAA==.Coolbreez:BAABNQAECn8bAAMWAAoKegi4VADqAAAWAAoK5we4VADqAAAUAAUK6Qj3TwDFAAAAAA==.Coolynn:BAAANQAECgMIBgAAAA==.Corl:BAAANQADCgIJAgAAAA==.',
Cr='Crazywar:BAEANQADCgYIDAAAAA==.Creams:BAAANQAECgIIAgABNQAECgQIBQAJAAAAAA==.Crew:BAAANQADCggICgAAAA==.Cronoth:BAAANQAECgUIBQAAAA==.Croy:BAAANQAECgQIAgAAAA==.',
Cu='Cumb:BAABNQAECn8VAAMYAAgKQhjGNAB6AQAYAAcKhBfGNAB6AQAfAAIKkBp6JACbAAABNQAECgoKTAAQAPUlAA==.',
Cw='Cwod:BAAANQAECgQIBAABNQADCgYJBwAJAAAAAA==.',
Cy='Cyrothea:BAAANQAECgYICgAAAA==.',
['Cä']='Cäldius:BAAANQAECgYIBgAAAA==.',
Da='Daenerys:BAAANQAECgIIAgAAAA==.Daioh:BAABNQAECn8iAAIFAAoKBQtfkQCpAQAFAAoKBQtfkQCpAQAAAA==.Damacraze:BAABNQAECn89AAIBAAoKXiHdJwD4AgABAAoKXiHdJwD4AgAAAA==.Damien:BAAANQABCggIDQAAAA==.Danielwu:BAABNQAECn8pAAMaAAkK/Q0yGQC/AAACAAkK5QydpgCHAQAaAAQKHRAyGQC/AAAAAA==.Dawigrund:BAAANQAECgcIDgAAAA==.',
De='Deadroar:BAABNQAECn8XAAIWAAgKfxXzTgC5AQAWAAgKfxXzTgC5AQABNQAFFAEIAQAJAAAAAA==.Deadtomato:BAABNQAECn82AAMcAAoK2yNdCAA3AwAcAAoKdyJdCAA3AwAgAAkK+B0yGAC7AgAAAA==.Deadwill:BAABNQAECn8hAAIcAAcK4A8PggAiAQAcAAcK4A8PggAiAQAAAA==.Deadzug:BAAANQAECgcIDAABNQAFFAQIBwABALwLAA==.Deaminase:BAABNQAECn8wAAIbAAoKzxgqWgAGAgAbAAoKzxgqWgAGAgAAAA==.Deathknell:BAAANQADCgcIBwAAAA==.Decypher:BAABNQAECn83AAIhAAoKUhvYLAC1AgAhAAoKUhvYLAC1AgAAAA==.Deggle:BAAANQADCgIIAgAAAA==.Delphoxx:BAABNQAECn8bAAITAAgKQRpsRwD2AQATAAgKQRpsRwD2AQAAAA==.Demidru:BAABNQAECn8jAAIPAAgKShW9MgB2AQAPAAgKShW9MgB2AQAAAA==.Demin:BAAANQABCgEIAQAAAA==.Demonshot:BAAANQADCgUIBAAAAA==.Depleterpann:BAAANQADCgQICAABNQAECgMIBgAJAAAAAA==.Derovia:BAAANQAECggIDgAAAA==.Deshojo:BAABNQAECn8YAAIXAAcKTA74NwDlAAAXAAcKTA74NwDlAAAAAA==.Desrook:BAAANQAECgQIBgAAAA==.',
Dh='Dhqt:BAAANQAECgEIAgABNQAECgQIBQAJAAAAAA==.',
Di='Diablominion:BAAANQAECgYIDgAAAA==.Dingbangow:BAAANQAECgQIBAABNQAECgQIBQAJAAAAAA==.Divinèhero:BAABNQAECn8XAAIYAAcKjgxaTwBcAQAYAAcKjgxaTwBcAQAAAA==.',
Do='Doomgirl:BAAANQAECgIIAgAAAA==.Double:BAAANQAECgYIBwAAAA==.Doublelift:BAACNQAFFH8IAAIGAAMKwxfrEQCjAAAGAAMKwxfrEQCjAAA1AAQKfzkAAwYACgqIIIwRAOMCAAYACQpHIIwRAOMCACEABArLFmaqABcBAAAA.',
Dr='Draghula:BAAANQADCgQIBQAAAA==.Dragondeznut:BAAANQADCggIDgAAAA==.Drakisara:BAAANQADCggIBgABNQAECgYIEAAJAAAAAA==.Drakuul:BAAANQADCgUIBwAAAA==.Droni:BAABNQAECn8mAAMiAAoKNRWjJwAHAgAiAAoKNRWjJwAHAgAYAAEKAADSjgA9AAAAAA==.Drpumper:BAAANQAECgIIAgABNQAECgQIBQAJAAAAAA==.Drummer:BAAANQADCgIIAgAAAA==.Dröbi:BAACNQAFFH8WAAMjAAgK3BJYBACYAQAjAAYKyxVYBACYAQADAAUKmRB7BgA3AQA1AAQKfzQAAwMACgrMIS4IAPgCAAMACQprIS4IAPgCACMACAoxHasHAL8BAAAA.',
Du='Duberagon:BAAANQADCgQIBAAAAA==.Dumbledork:BAAANQABCgYICQAAAA==.Dundundun:BAAANQAECggIEgAAAA==.',
Dv='Dvrkwolf:BAAANQADCgcIDAAAAA==.',
['Dâ']='Dârkdune:BAAANQAECggICgAAAA==.',
Eg='Eggdrop:BAABNQAECn8sAAIdAAoKjR54BQCBAgAdAAoKjR54BQCBAgAAAA==.Egufro:BAABNQAECn8jAAMLAAoKpRKXNwA9AgALAAoKpRKXNwA9AgAFAAQKkATbXgFrAAABNQAECgoKUAARAK0ZAA==.',
Eh='Ehgu:BAABNQAECn9QAAIRAAoKrRnCDABKAgARAAoKrRnCDABKAgAAAA==.',
El='Eleaya:BAAANQADCggIDwAAAA==.Eleverclear:BAAANQADCgYIBgAAAA==.Eliizabeth:BAABNQAECn8YAAIFAAcK1gcv8QA6AQAFAAcK1gcv8QA6AQAAAA==.Elynnah:BAAANQAECgEIAQAAAA==.Elysiawaters:BAEANQADCggICAAAAA==.',
Em='Emidget:BAAANQAECgEIAQAAAA==.',
En='Endervish:BAAANQADCgIIAgABNQAECgMIBwAJAAAAAA==.Enyalio:BAAANQADCgYICwAAAA==.',
Er='Erhmer:BAAANQAECggIBQAAAA==.Ericdh:BAAANQADCgUICgAAAA==.Ericpal:BAAANQAECgcICAAAAA==.Ericrog:BAAANQABCgYICQAAAA==.Ericwym:BAAANQAECgEIAQAAAA==.',
Et='Ethersong:BAAANQADCgIIAgAAAA==.Etom:BAAANQAFFAEIAQAAAA==.',
Ev='Eviae:BAAANQAECgQICAAAAA==.',
Fa='Faaith:BAAANQADCgIIAgAAAA==.Faceroll:BAAANQAECgIIAgAAAA==.Fairyhunter:BAAANQAECgQICAAAAA==.Fairymonk:BAAANQAECgQIBwAAAA==.Fangrat:BAAANQAECgMIBQABNQAECgQIBQAJAAAAAA==.Fatfatfat:BAAANQAECggIDgABNQAFFAEIAQAJAAAAAA==.Fañgrat:BAABNQAECn8gAAMLAAoKeRnJPwBlAgALAAoKeRnJPwBlAgAFAAUKGQevSQGqAAABNQAECgQIBQAJAAAAAA==.',
Fe='Fellriaris:BAAANQADCgIIAgAAAA==.Femboyluvr:BAABNQAECn8UAAIOAAgKMhBMrwAbAQAOAAgKMhBMrwAbAQAAAA==.',
Fi='Filumena:BAAANQAECgMIBAAAAA==.Finch:BAAANQABCgQIBgAAAA==.',
Fl='Flameblue:BAAANQADCgQIBAAAAA==.Flandia:BAABNQAECn85AAIBAAoKJR46KQCbAgABAAoKJR46KQCbAgAAAA==.Flex:BAAANQAECgcIEAAAAA==.Floppiterry:BAABNQAECn8kAAIBAAYKow4ZwwB8AQABAAYKow4ZwwB8AQAAAA==.Floppyterri:BAAANQADCgYIBgAAAA==.Floppyterry:BAAANQAECgIIAgAAAA==.Flow:BAACNQAFFH8GAAIkAAMKGgqdBgCoAAAkAAMKGgqdBgCoAAA1AAQKfysAAiQACgqjGBQJAJMCACQACgqjGBQJAJMCAAAA.',
Fo='Forduecezero:BAAANQADCgYIBgAAAA==.Fowl:BAABNQAECn8oAAIiAAoK1BkhGgCIAgAiAAoK1BkhGgCIAgAAAA==.Foxyshaman:BAAANQAECgQIBQAAAA==.',
Fr='Fricher:BAABNQAECn8tAAIUAAkKkBX8IQDQAQAUAAkKkBX8IQDQAQAAAA==.',
Fy='Fylerianprie:BAAANQAECgIIBAAAAA==.Fyleriansham:BAAANQADCgMIAwAAAA==.',
Ga='Gagli:BAAANQAECgQIBQAAAA==.Galathynius:BAAANQAECgQIBQAAAA==.Galelora:BAAANQADCggICAAAAA==.Ganjja:BAAANQADCggIGAAAAA==.Gawk:BAAANQADCgUICwABNQAECgQIBQAJAAAAAA==.',
Ge='Geneman:BAAANQABCgYIDAAAAA==.Getsyouwet:BAAANQAECgMIAgABNQAECgoKMwAUANokAA==.Getter:BAAANQADCgkJFQAAAA==.',
Gh='Ghalamir:BAAANQAECgIIAgAAAA==.Ghettomike:BAAANQAECgQIBAAAAA==.',
Gi='Giny:BAABNQAECn8vAAMQAAoKXBaDRgC7AQAQAAoKXBaDRgC7AQATAAIKRgFKHAE0AAAAAA==.',
Gl='Glowfungus:BAAANQABCgIIAgAAAA==.',
Go='Gobbledeez:BAABNQAECn8pAAITAAoK5yKIDABcAwATAAoK5yKIDABcAwAAAA==.Gobblez:BAAANQAECgQICwAAAA==.Gorvash:BAAANQADCgIIAgAAAA==.Gosulock:BAEBNQAECn8UAAICAAkKuQpQiwBGAQACAAkKuQpQiwBGAQABNQAFFAEIAQAJAAAAAA==.Govinniuur:BAAANQAECgIJAgAAAA==.',
Gr='Grasfedjones:BAAANQAECgQIBwAAAA==.Gravelord:BAAANQAECgEIAQAAAA==.Grizzy:BAABNQAECn84AAIYAAoKqCAVDQDTAgAYAAoKqCAVDQDTAgAAAA==.Grue:BAEANQADCggIEAABNQAECgcIGQAQAEIFAA==.Gröthis:BAAANQAECgQIBQAAAA==.',
Gw='Gweilo:BAAANQAECggIBgAAAA==.Gwendilyn:BAAANQAECgIIAgAAAA==.',
Gy='Gyndrinolara:BAAANQAECgMIBgAAAA==.',
Ha='Hafadude:BAAANQAECggIAQAAAA==.Hahgottum:BAABNQAECn8mAAMEAAoK8BTpFwBZAgAEAAoK8BTpFwBZAgAPAAMKVgAwtgAsAAAAAA==.Handsomshlax:BAAANQADCgMIAwAAAA==.',
He='Headhuntér:BAABNQAECn8YAAMeAAcK1gweCwBNAQAeAAYKwAgeCwBNAQABAAYKtQp4+wANAQAAAA==.Healgoßyeßye:BAAANQADCgYIBgAAAA==.',
Hi='Hikiru:BAAANQAECggIBgAAAA==.',
Hl='Hlzero:BAAANQAECggIAgAAAA==.',
Ho='Hollandar:BAAANQADCgcIBwAAAA==.Holyflame:BAAANQAECgEIAQAAAA==.Holypewpewz:BAAANQAECgcIDAAAAA==.Holyyshift:BAAANQAECgEIAQABNQAECgcIDAAJAAAAAA==.Horhel:BAAANQAECgYIEAAAAA==.Hottstreak:BAAANQADCggICAAAAA==.',
Hu='Huehef:BAAANQADCgEIAQAAAA==.Hungmao:BAAANQADCggICAAAAA==.Huuron:BAAANQAECgIICAAAAA==.',
Hy='Hyperiann:BAABNQAECn8ZAAIIAAkKywjgKgAfAQAIAAkKywjgKgAfAQAAAA==.Hypnôtoâd:BAAANQAECgEIAQABNQAECgQIBQAJAAAAAA==.',
Ia='Iamfried:BAACNQAFFH8JAAIPAAMKnRLJEgDfAAAPAAMKnRLJEgDfAAA1AAQKfzEAAg8ACgpWHvMdANoCAA8ACgpWHvMdANoCAAAA.',
Ic='Iceyrot:BAAANQADCggIFgAAAA==.',
Ig='Igran:BAAANQAECgIIAgABNQAECgoKJwADANIaAA==.',
Ih='Ihatemodels:BAAANQAECgYICgAAAA==.',
Il='Illidank:BAAANQADCgYICQAAAA==.Illidigle:BAAANQADCggIDAABNQAECgkJHwAhAKgUAA==.Ilurvyou:BAAANQADCgYIBgAAAA==.',
In='Inamorta:BAABNQAECn82AAMYAAoKKSA3DQDRAgAYAAkKKSA3DQDRAgAiAAgK7RgBJQAeAgAAAA==.Innarius:BAAANQAECgYICwAAAA==.Intothedark:BAAANQAECggIAgAAAA==.Inviçtus:BAAANQADCgQIBAAAAA==.Inyadraug:BAAANQAECggIDwAAAA==.',
Ip='Ipurgeu:BAAANQAECgMIBAAAAA==.',
Ir='Ironheãrt:BAACNQAFFH8FAAIIAAQKOwkXCQCcAAAIAAQKOwkXCQCcAAA1AAQKf00AAggACgoRHrgMAM8CAAgACgoRHrgMAM8CAAAA.Ironjaws:BAAANQAECgUIBQAAAA==.Ironsight:BAAANQAECgMIAwAAAA==.Irontaco:BAAANQAECgMIAwAAAA==.Irsa:BAAANQAECggIEgAAAA==.',
Is='Isaacnewton:BAAANQAECgIIAgAAAA==.',
It='Itai:BAACNQAFFH8IAAMUAAUKjBNFBAA6AQAUAAQKjBNFBAA6AQAVAAEKAAAqIwAAAAA1AAQKf1wAAxQACgqRJGYDAL4DABQACgqRJGYDAL4DABUACApnHBcgAEwCAAAA.',
Iv='Iverson:BAAANQAECgMIAgAAAA==.',
Iz='Izayam:BAAANQADCgcIBwABNQAECgkJIwAbAHciAA==.',
Ja='Jac:BAAANQAECgMIAwABNQAFFAgIGgALACwXAA==.Jackk:BAACNQAFFH8aAAILAAgKLBeGAwBeAgALAAgKLBeGAwBeAgA1AAQKfy0AAwsACgrpIpYIAIMDAAsACgrpIpYIAIMDAAUABgrtDs3nABEBAAAA.Jackks:BAAANQAECgcIDwABNQAFFAgIGgALACwXAA==.Jaddix:BAAANQADCgYICwAAAA==.Jalexandrea:BAABNQAECn8VAAIFAAUK6gJeaAFhAAAFAAUK6gJeaAFhAAAAAA==.Janzan:BAAANQAECgIIAgAAAA==.Jasmonk:BAABNQAECn8pAAIMAAkKiw0kJQBxAQAMAAkKiw0kJQBxAQAAAA==.Jaxed:BAAANQAECgEIAQAAAA==.',
Je='Jeeyell:BAAANQADCgUIBQAAAA==.Jellysickle:BAAANQADCgcICAAAAA==.Jemzz:BAABNQAECn80AAMKAAoKmQgMIgBbAQAKAAoKXgYMIgBbAQABAAoKrwdRrgBVAQAAAA==.',
Ji='Jimmyray:BAAANQABCgYIBgAAAA==.Jinkua:BAAANQAECgIIAgABNQAFFAEIAQAJAAAAAA==.Jinkz:BAAANQAECgUICAAAAA==.',
Jo='Jolfurnuand:BAAANQAECgIIAgAAAA==.Jorhel:BAAANQADCggJDgAAAA==.Josephsmith:BAAANQAECggIBAAAAA==.Joshù:BAABNQAECn8XAAIRAAkKoxMaDgAzAgARAAkKoxMaDgAzAgABNQAECgoKJwADANIaAA==.Joshú:BAAANQADCgEIAQABNQAECgoKJwADANIaAA==.',
Ju='Judgementàl:BAAANQAECgcICwABNQAFFAUIDgASAEkLAA==.Judgevis:BAAANQAECgcIEAAAAA==.Jumbles:BAAANQAECgQIBQAAAA==.Justeene:BAAANQADCgEIAQABNQAECgYIEAAJAAAAAA==.',
Jy='Jynxy:BAAANQAECgQICAAAAA==.',
['Já']='Jáydn:BAAANQAECgQICgABNQAECgkJOAAFAHsiAA==.',
['Jø']='Jøshu:BAAANQADCgYIBgABNQAECgoKJwADANIaAA==.',
Ka='Kaeliis:BAABNQAECn8nAAILAAoKjxbJNgBAAgALAAoKjxbJNgBAAgAAAA==.Kagestrasz:BAAANQADCgYIBgAAAA==.Kaneggy:BAABNQAECn8WAAMdAAkKhgyhFgAVAQAOAAYKdAuFrAAhAQAdAAgKOQqhFgAVAQAAAA==.Karren:BAAANQADCgIIBAAAAA==.Karrona:BAAANQADCggJDAAAAA==.Kazuu:BAABNQAECn83AAIPAAkKnxmVHQAWAgAPAAkKnxmVHQAWAgAAAA==.',
Kb='Kbeckinsale:BAABNQAECn80AAQcAAkK6R5MLABNAgAgAAcKjR0CIwBvAgAcAAgKsx1MLABNAgAlAAIKLwbJGABXAAAAAA==.',
Ke='Keladun:BAAANQADCgUIDwAAAA==.Kemaro:BAAANQAECggICQAAAA==.Keykey:BAAANQAECgEIAQAAAA==.',
Kh='Khallessi:BAAANQAECgQIDQAAAA==.Kharga:BAAANQAECgcIEAAAAA==.Khonan:BAAANQADCgUIBgABNQAFFAgIDAAbAJMXAA==.',
Ki='Kiamar:BAAANQAECgYICAAAAA==.Kidgroove:BAAANQADCggICgAAAA==.Kishu:BAAANQADCggICAAAAA==.',
Kn='Kneecaps:BAAANQADCgcIBwAAAA==.',
Ko='Kolus:BAAANQADCggIEgAAAA==.Konamy:BAABNQAECn8xAAIbAAoK3BRhUwAYAgAbAAoK3BRhUwAYAgAAAA==.Kordarg:BAAANQADCgQIBAAAAA==.Korz:BAABNQAECn8WAAIhAAgKkxXSawDbAQAhAAgKkxXSawDbAQAAAA==.',
Kr='Krex:BAAANQADCgEIAQAAAA==.Kriss:BAAANQADCggICQAAAA==.Kristeena:BAAANQAECgQIBAAAAA==.Kroldun:BAAANQADCgIIAgAAAA==.Kryptonikk:BAABNQAECn8hAAMGAAkK7gsfRAAUAQAGAAUKDAsfRAAUAQAhAAcKbg7xmwAIAQAAAA==.Krystall:BAAANQADCgEIAQAAAA==.Kröw:BAABNQAECn8rAAIRAAkKPg59FgAAAgARAAkKPg59FgAAAgAAAA==.',
Ku='Kudrix:BAABNQAECn8sAAIMAAoKnx9VDwDuAgAMAAoKnx9VDwDuAgAAAA==.Kurø:BAAANQAECgcIDQAAAA==.',
La='Lany:BAAANQADCgUIBgAAAA==.Latherfanta:BAAANQAECgMIBAAAAA==.Laurijaydn:BAABNQAECn84AAIFAAkKeyIaIwDUAgAFAAkKeyIaIwDUAgAAAA==.Laurynn:BAAANQADCggIDQAAAA==.Lauríe:BAAANQADCgMIAwABNQAECgkJOAAFAHsiAA==.',
Le='Lechampion:BAAANQAECgQIBAAAAA==.Legendaries:BAAANQADCgEIAQAAAA==.Legionremix:BAAANQADCggICQAAAA==.Lelink:BAAANQADCgEIAQAAAA==.Levyathan:BAAANQADCgEIAQAAAA==.',
Li='Liath:BAAANQAECgUICgAAAA==.Likeaglove:BAAANQADCgIIAgABNQAECgkJHwAhAKgUAA==.Lillina:BAAANQADCgIIAgAAAA==.Littlestarz:BAABNQAECn8cAAITAAgKsxu3SQA8AgATAAgKsxu3SQA8AgAAAA==.Lizzieag:BAEANQADCgYICwABNQAECgkJPQABAFoUAA==.',
Ll='Llazz:BAACNQAFFH8OAAMLAAcKgBnlCQC+AQALAAYK2xflCQC+AQAIAAEKCxemDgBLAAA1AAQKf0EAAwsACgpJH/ELAGsDAAsACgpJH/ELAGsDAAUAAwqdENIhAbcAAAAA.Llemons:BAAANQAECggIDwABNQAECggIGwAbANoTAA==.',
Lo='Locknlizzie:BAEBNQAECn89AAIBAAkKWhSMaABDAgABAAkKWhSMaABDAgAAAA==.Lohueng:BAAANQAECgMIBAAAAA==.Lolblur:BAAANQAECgQIBAAAAA==.Lolhigh:BAAANQAECgEIAQAAAA==.Lootah:BAAANQADCggIGAAAAA==.Loranoth:BAAANQADCggJIAAAAA==.Lovecox:BAAANQADCggIFAAAAA==.Lox:BAABNQAECn8VAAMZAAoKngqbBwBYAQAZAAoKngqbBwBYAQACAAcKPgO/0wCqAAAAAA==.',
Lu='Luke:BAABNQAECn8oAAIFAAkKgx1QawD5AQAFAAkKgx1QawD5AQAAAA==.Luminali:BAABNQAECn8cAAMLAAgKMQ5rpAA6AQALAAcKmAxrpAA6AQAFAAQKCw2pPAG/AAAAAA==.Luminari:BAAANQAECggIDQABNQAECggIHAALADEOAA==.Lunadari:BAAANQAECgIJAwAAAA==.Lunareva:BAABNQAECn8wAAIEAAoKXiAiBgCDAwAEAAoKXiAiBgCDAwAAAA==.Lunä:BAAANQADCggICAABNQAFFAYIGgABALUZAA==.',
Ly='Lyrielle:BAAANQADCgQIBQAAAA==.Lyxon:BAABNQAECn8yAAIEAAoKCRaYGABQAgAEAAoKCRaYGABQAgAAAA==.',
['Læ']='Lænna:BAAANQADCgUJBQAAAA==.',
['Lé']='Légoläs:BAAANQAECgMIAwAAAA==.',
['Lí']='Lílîth:BAAANQAECgMIAgAAAA==.',
Ma='Machiavellï:BAAANQAECgQIBAAAAA==.Mael:BAAANQADCgYICQABNQADCggICAAJAAAAAA==.Maeltne:BAAANQADCgYIBgAAAA==.Mafoôza:BAACNQAFFH8PAAIOAAUKUQ8dIgDsAAAOAAUKUQ8dIgDsAAA1AAQKfyIAAg4ACgprHa4iALcCAA4ACgprHa4iALcCAAAA.Magicalama:BAACNQAFFH8JAAIbAAYKsA63GwAYAQAbAAYKsA63GwAYAQA1AAQKfzkAAhsACgpAGsB9AIMCABsACgpAGsB9AIMCAAAA.Magiplex:BAAANQAECgUIDgAAAA==.Magnanimity:BAEANQAECgIIAgABNQAECgoKOgABAAMYAA==.Mahboyblu:BAAANQADCgEIAQAAAA==.Mahndoo:BAABNQAECn8bAAIbAAcK2hNX3gDLAQAbAAcK2hNX3gDLAQAAAA==.Makto:BAAANQAECgUIDQAAAA==.Malia:BAAANQAECgQIDwAAAA==.Maliciouso:BAAANQAECggIEwAAAA==.Malédiction:BAAANQAECgQIBAAAAA==.Manydoor:BAAANQADCgIIAgAAAA==.Marley:BAABNQAECn8oAAIBAAkK3Ak+nADOAQABAAkK3Ak+nADOAQAAAA==.Matua:BAAANQAECgUICwAAAA==.Maximillian:BAAANQAECgQIBAAAAA==.Maymae:BAAANQAECgMIBAABNQAECgYIEwAJAAAAAA==.',
Mc='Mcßlood:BAABNQAECn8cAAMWAAkKKCAiCgDtAgAWAAkKKCAiCgDtAgAVAAEKbAAHzQACAAAAAA==.',
Me='Meatsheeld:BAAANQAECgYIBgABNQAFFAQIBwABALwLAA==.Meepz:BAAANQAECgUIBgAAAA==.Megadk:BAAANQAECgUIBwABNQAECggIGgAIAFweAA==.Megamacdin:BAABNQAECn8aAAMIAAcKXB4AFADtAQAIAAYKsSIAFADtAQAFAAEKsgguqgEyAAAAAA==.Mendietta:BAABNQAECn89AAITAAkKlBehNgA/AgATAAkKlBehNgA/AgAAAA==.Meridian:BAABNQAECn8rAAIhAAkKMxphMACCAgAhAAkKMxphMACCAgAAAA==.Mesna:BAAANQAECgQIBAAAAA==.',
Mi='Miistral:BAABNQAECn8kAAMLAAoK+w87egCqAQALAAoK+w87egCqAQAFAAEKAACrvAEqAAAAAA==.Milkhoof:BAABNQAECn8WAAIVAAYK5BTdUwBGAQAVAAYK5BTdUwBGAQAAAA==.Mimie:BAAANQAECgUIDAAAAA==.Minki:BAAANQADCggICQAAAA==.Mistyeva:BAAANQAECgcIDQABNQAECgoKMAAEAF4gAA==.Miyamoto:BAAANQADCgEIAQAAAA==.Miyoko:BAAANQAECgYIBgAAAA==.',
Mo='Moistooltip:BAABNQAECn8wAAIMAAoK7B82BgBsAwAMAAoK7B82BgBsAwAAAA==.Mokotrize:BAABNQAECn8xAAIIAAkK4BwZEQAZAgAIAAkK4BwZEQAZAgAAAA==.Mooscifer:BAAANQADCgYIBgAAAA==.Moosh:BAABNQAECn8jAAIXAAgKcBAmLgAgAQAXAAgKcBAmLgAgAQAAAA==.Morandara:BAAANQABCgUIBwAAAA==.Mordred:BAABNQAECn8ZAAIfAAYKvQUcIADGAAAfAAYKvQUcIADGAAAAAA==.Morria:BAAANQADCgQIBgAAAA==.Mouthkisser:BAAANQAECgMIAwAAAA==.',
Ms='Msfirefly:BAAANQAECgQIBAABNQAECggIFQAZAOAbAA==.',
Mu='Mud:BAAANQAECggIDwAAAA==.Mudslinger:BAAANQAECgcICAAAAA==.Munchies:BAABNQAECn8lAAMgAAkK4RkXMgAWAgAgAAkKAxQXMgAWAgAcAAcKKRfxSgDVAQABNQAFFAQICQAVALgJAA==.',
My='Myrolan:BAAANQADCgYICgABNQADCgcICwAJAAAAAA==.Myrrha:BAAANQAECggICgAAAA==.',
['Mø']='Møønwuu:BAABNQAECn8aAAIgAAoKeQ0VEgCrAQAgAAoKeQ0VEgCrAQAAAA==.',
Na='Naarf:BAAANQAECgIIAgABNQAFFAQIBwABALwLAA==.Nanoko:BAAANQAECgIIAgAAAA==.Naora:BAAANQAECgEIAQABNQAECgUIDAAJAAAAAA==.Natedoggydog:BAAANQAECggICAAAAA==.',
Ne='Neckslice:BAACNQAFFH8TAAIQAAgKthN6AwBvAgAQAAgKthN6AwBvAgA1AAQKfzEAAhAACgqSJAYJAC8DABAACgqSJAYJAC8DAAAA.Nefertm:BAAANQADCgQIAwAAAA==.Nemophilist:BAAANQABCgIIAgAAAA==.Neural:BAAANQAECgcIBwAAAA==.Neuro:BAABNQAECn8jAAMbAAkKdyL+MwAiAwAbAAkKdyL+MwAiAwAmAAEKFhicQABDAAAAAA==.',
Ni='Nichdru:BAAANQADCgcICwAAAA==.Nicolico:BAAANQAECgQIBAAAAA==.Nictamom:BAAANQAECgEIAQAAAA==.Nightfaze:BAAANQAECgMIBAABNQAECgYIEAAJAAAAAA==.Nightnite:BAAANQADCgYIDgAAAA==.Nij:BAAANQAECgEIAQAAAA==.Nirri:BAAANQAECgcIEQAAAA==.Nitefall:BAABNQAECn8pAAIBAAkKKxXPRwBBAgABAAkKKxXPRwBBAgAAAA==.Nithon:BAAANQAECggIEwAAAA==.',
No='Nocando:BAABNQAECn8fAAIhAAkKqBSHSgBGAgAhAAkKqBSHSgBGAgAAAA==.Nota:BAAANQAECgcIDAABNQAECggIJwAVAAMTAA==.Notadk:BAABNQAECn8nAAIVAAgKAxPTQwCKAQAVAAgKAxPTQwCKAQAAAA==.Nott:BAAANQAECgEIAQAAAA==.Noturbudpal:BAAANQADCgQIBgABNQAECgoKjwAWANAZAA==.',
Nu='Nuggets:BAAANQAECgIIAgAAAA==.Nuriel:BAAANQADCgQIBAAAAA==.',
Ny='Nylinuya:BAAANQAECgUIEAABNQAFFAQIBQAaANcQAA==.Nywen:BAAANQADCgUIBQAAAA==.',
Ob='Obligated:BAAANQAECgIIAgAAAA==.Obsydia:BAAANQADCgcIBwAAAA==.',
Ok='Okowilly:BAAANQADCggIDQAAAA==.',
Ol='Oline:BAABNQAECn8VAAICAAkKySGAIgD6AgACAAkKySGAIgD6AgAAAA==.',
On='Onijunk:BAAANQADCgQIBAAAAA==.',
Oo='Oonaki:BAABNQAECn8YAAMWAAoK6gdcbgA7AQAWAAcKgAhcbgA7AQAVAAQKsQWnmABsAAAAAA==.',
Or='Orchideva:BAAANQAECggIDwABNQAECgoKMAAEAF4gAA==.Oriphiel:BAAANQAECgUIDAAAAA==.',
Ot='Ottoshock:BAAANQADCgUIBQAAAA==.',
Ow='Owl:BAAANQADCggICQAAAA==.',
Pa='Painloa:BAABNQAECn8WAAMUAAcKIQj9hQAJAQAUAAYKGQj9hQAJAQAVAAYK0wUWhgCYAAAAAA==.Pandanimal:BAAANQAECgIIAgAAAA==.Papapally:BAAANQADCgUIBwAAAA==.Paradoxx:BAABNQAECn83AAImAAoKoyS5AgA0AwAmAAoKoyS5AgA0AwAAAA==.',
Pe='Pestelince:BAAANQAECgcICQAAAA==.',
Ph='Phelefica:BAAANQAECgQIAwAAAA==.Phreyja:BAAANQADCgYICAAAAA==.Phylgon:BAABNQAECn8nAAMhAAgK8xAybACYAQAhAAgK8xAybACYAQAGAAEKAAAJlgANAAAAAA==.',
Pl='Pleblords:BAAANQAECgQICAAAAA==.',
Pm='Pmac:BAAANQAECgUICwABNQAECggIGgAIAFweAA==.',
Po='Poggrin:BAAANQAECgUICgAAAA==.Pogrin:BAAANQAECgQICwAAAA==.Pointybrows:BAAANQAECgQICQAAAA==.',
Pr='Premmier:BAAANQADCgcIDgAAAA==.Pryona:BAAANQAECgIIAQABNQAECgQIBQAJAAAAAA==.',
Pu='Putrescence:BAAANQAECgIIAgAAAA==.',
Pw='Pwnhubb:BAAANQADCgYIBwAAAA==.',
Py='Pyràbànks:BAAANQADCgYIBgAAAA==.',
Qu='Quelestraza:BAABNQAECn82AAMSAAoKHRQqEAAFAgASAAoKHRQqEAAFAgADAAEKAACRPgAvAAAAAA==.Quikkmex:BAAANQAECgQIBwAAAA==.',
Ra='Rabbit:BAAANQADCgQIBAAAAA==.Raewyck:BAABNQAECn8rAAIBAAoKKw/ieQAbAgABAAoKKw/ieQAbAgAAAA==.Raginbull:BAABNQAECn8+AAMNAAkKXBvADAD0AQANAAkKXBvADAD0AQAOAAMK3QY4JwE6AAAAAA==.Ragingmaze:BAABNQAECn8mAAQWAAgKbBPUTQC/AQAWAAgKbBPUTQC/AQAUAAgKsgTjfwAdAQAVAAIKQAWzngBTAAAAAA==.Rainburrow:BAABNQAECn81AAMMAAoKoBf1FAAbAgAMAAoKkhT1FAAbAgAkAAcK3hgVEwCyAQAAAA==.Raptormortis:BAAANQAECgQIBQAAAA==.Rastlinn:BAABNQAECn8XAAIbAAoKewQPrABMAQAbAAoKewQPrABMAQAAAA==.Raziyya:BAAANQADCgEIAQAAAA==.',
Re='Rebalite:BAAANQABCgEIAQAAAA==.Reinitia:BAAANQADCgcICwAAAA==.Reinnii:BAAANQAECgUIDwAAAA==.Renkagisa:BAAANQAECgIIAwAAAA==.Resurrection:BAAANQAECgYIDAAAAA==.Retana:BAABNQAECn85AAIFAAoKJCNJHwDjAgAFAAoKJCNJHwDjAgAAAA==.Reticence:BAAANQABCgIIAgAAAA==.Retrisan:BAAANQABCgQIBAAAAA==.Retroflex:BAAANQAECgEIAQABNQAECgYIDgAJAAAAAA==.',
Rh='Rhalk:BAAANQADCgEIAQAAAA==.Rhinn:BAABNQAECn8hAAIRAAgK9wU5IQAXAQARAAgK9wU5IQAXAQAAAA==.',
Ri='Rickypeepee:BAABNQAECn8rAAIFAAkKah8PRADIAgAFAAkKah8PRADIAgAAAA==.Rider:BAAANQABCgIIBAAAAA==.Rigatoni:BAAANQAECgIIAgAAAA==.Rizzlybear:BAAANQAECgEIAQABNQAECgEIAQAJAAAAAA==.',
Ro='Roastedz:BAABNQAECn81AAIZAAkKaQtACQA0AQAZAAkKaQtACQA0AQAAAA==.Roflmaster:BAAANQAECgEIAQAAAA==.Rojen:BAAANQAECgYIEgAAAA==.Rorthu:BAAANQAECgIIAgAAAA==.',
Ru='Rukélie:BAAANQAECgIIAgAAAA==.',
Ry='Ry:BAAANQAECggIEAAAAA==.Ryanna:BAABNQAECn8sAAIbAAoKpwmygACoAQAbAAoKpwmygACoAQAAAA==.',
Sa='Sacrilege:BAAANQABCgMIAwAAAA==.Saevio:BAABNQAECn9DAAQUAAoKFRbLFwAtAgAUAAkKhxTLFwAtAgAVAAcKHhJ3RgCmAQAWAAQKqhCyigDWAAAAAA==.Sajin:BAAANQAECgMIAwAAAA==.Salvader:BAABNQAECn8qAAIKAAoKahPuJgAUAgAKAAoKahPuJgAUAgAAAA==.Sanctus:BAAANQAECgUIDAAAAA==.Sashimi:BAACNQAFFH8JAAMVAAQKuAm0EgC5AAAVAAMKuAm0EgC5AAAUAAIK6wNkFwAAAAA1AAQKf0MAAxQACgq4HwAKANkCABQACgqCHwAKANkCABUACgrwGawXAM0CAAAA.Sataves:BAAANQABCgMIAwAAAA==.Satharis:BAAANQAECgUICQAAAA==.',
Sc='Scarlet:BAAANQAECgQIBgABNQAFFAQICQAVALgJAA==.Scarllett:BAABNQAECn8mAAMTAAoKzA/ppAAqAQATAAkK5g7ppAAqAQAQAAcKEhCJtgAlAQAAAA==.Scoot:BAEANQAECggIEQABNQAFFAQIBgALALsFAA==.Scrappurr:BAAANQABCggIFwAAAA==.Scrubiclese:BAAANQAECgUIBQAAAA==.Scrytearia:BAAANQABCgIJAgAAAA==.',
Se='Seldaren:BAAANQAECgMIBwAAAA==.Selfward:BAAANQAECgQIBwAAAA==.Seran:BAABNQAECn8pAAIBAAkKZRhANAB3AgABAAkKZRhANAB3AgAAAA==.Serenade:BAAANQAECgcIDQAAAA==.Seviana:BAABNQAECn8aAAILAAoK3R47FwAfAwALAAoK3R47FwAfAwABNQAFFAcIIwASAJsmAA==.Sevie:BAACNQAFFH8jAAISAAcKmyb1AQCnAgASAAcKmyb1AQCnAgA1AAQKf0IAAhIACgqTJdEBAKsDABIACgqTJdEBAKsDAAAA.',
Sh='Shabbyy:BAAANQADCgYIDAABNQAECgQIBwAJAAAAAA==.Shadowpump:BAABNQAECn8dAAQGAAcKuRSrOABgAQAGAAYKBxGrOABgAQAhAAUKvhb9mgBEAQAnAAEKzQsDLAAsAAAAAA==.Shalada:BAAANQADCgUIBQAAAA==.Shamsel:BAABNQAECn9BAAIGAAoK6xNXFAAYAgAGAAoK6xNXFAAYAgAAAA==.Shinnz:BAACNQAFFH8GAAIFAAQKtRFKFgDYAAAFAAQKtRFKFgDYAAA1AAQKf3EAAwUACgp1Ho8oAL8CAAUACgp1Ho8oAL8CAAsAAwrxAIkdATkAAAAA.Shockcaller:BAAANQAECgYIDQAAAA==.Shockingnut:BAAANQAECgUICQAAAA==.Showtooltip:BAAANQAECgQIAwABNQAECgoKMAAMAOwfAA==.Shoöman:BAAANQADCgEIAQAAAA==.Shrabster:BAABNQAECn8YAAIbAAcKqghj+wC7AAAbAAcKqghj+wC7AAABNQAECgQIBQAJAAAAAA==.Shweatyballs:BAAANQADCgQIBAAAAA==.',
Si='Silversong:BAABNQAECn8xAAMBAAkKPh3QSgCNAgABAAkKPh3QSgCNAgAeAAEKqBJyEgBAAAAAAA==.Simmara:BAAANQAECgMIBwAAAA==.Sip:BAAANQAECgYIDgAAAA==.',
Sk='Skapelijones:BAAANQAECgEIAQAAAA==.Skipper:BAAANQABCgYIBgAAAA==.Skylinelol:BAAANQAECggICwAAAA==.Skywalkah:BAAANQADCgQIBAABNQAECgEIAgAJAAAAAA==.',
Sm='Smallcurse:BAAANQAECgYICgAAAA==.Smallighting:BAABNQAECn80AAQTAAoKJhIFYADuAQATAAoKJhIFYADuAQARAAUKxBRsIwAlAQAQAAQKpxM30ADzAAAAAA==.Smokiemcpot:BAAANQAECgQIBAAAAA==.',
So='Solanthis:BAAANQAECgEJAQAAAA==.Solstica:BAABNQAECn8nAAMnAAoKwxtTAQAiAwAnAAoKwxtTAQAiAwAGAAEKAADEjgAcAAAAAA==.Solsticata:BAAANQAECgIIAwABNQAECgoKJwAnAMMbAA==.',
Sp='Sparrå:BAAANQADCgYIBgAAAA==.Spiritualone:BAABNQAECn8mAAIIAAkK2RKJKAAuAQAIAAkK2RKJKAAuAQAAAA==.',
Sq='Sqwaat:BAAANQAECgIJAwAAAA==.',
St='Steelrib:BAABNQAECn8kAAIWAAgK6QVDXADQAAAWAAgK6QVDXADQAAAAAA==.Stonystark:BAAANQAECgUIAQAAAA==.Straam:BAACNQAFFH8PAAITAAQKTAm+FwD1AAATAAQKTAm+FwD1AAA1AAQKf14AAxMACgpDG5UqALkCABMACgpDG5UqALkCABAACAqlD6qfAFcBAAAA.Strizzle:BAEBNQAECn8ZAAIQAAcKQgUwpwBGAQAQAAcKQgUwpwBGAQAAAA==.Stupidity:BAAANQADCggICAAAAA==.Støney:BAAANQAECgcIEgAAAA==.',
Su='Subatronic:BAACNQAFFH8iAAIWAAgKsSQiAgCOAgAWAAgKsSQiAgCOAgA1AAQKf1MAAhYACgrpJi0AAJwDABYACgrpJi0AAJwDAAAA.Subfractal:BAAANQADCgYIBgABNQAFFAgIIgAWALEkAA==.Surealadin:BAAANQADCgYIBgAAAA==.',
Sy='Sylthara:BAABNQAECn8aAAQTAAYKuxIjkQBdAQATAAYKuxIjkQBdAQAQAAMKowH8BwEtAAARAAEKAABhPAASAAAAAA==.Syrothea:BAAANQADCgUJBQAAAA==.',
Ta='Tacokicker:BAAANQADCgcIBwAAAA==.Tahumm:BAABNQAECn8pAAIOAAgKohXdYADcAQAOAAgKohXdYADcAQAAAA==.Takki:BAABNQAECn8aAAIOAAkKehhvrQCrAQAOAAkKehhvrQCrAQAAAA==.Talethia:BAABNQAECn8XAAIbAAcKQBHwuQAxAQAbAAcKQBHwuQAxAQAAAA==.Tamsîn:BAABNQAECn82AAIaAAoKORymAwC3AgAaAAoKORymAwC3AgAAAA==.Tap:BAABNQAFFH8GAAIcAAYKKRSCBwC1AQAcAAYKKRSCBwC1AQAAAA==.Tazlinmon:BAAANQADCgYIBgABNQAECgYIEAAJAAAAAA==.',
Tb='Tbonez:BAAANQADCgIIAgABNQAECggIJAAWAOkFAA==.',
Te='Teapawt:BAAANQAECgUIBgAAAA==.Teech:BAAANQAECgQIBAAAAA==.Teinuya:BAACNQAFFH8FAAMaAAQK1xAeBwCYAAAaAAMKjBAeBwCYAAAZAAEKbBEeEgBKAAA1AAQKf0kABBoACgquIgICABkDABoACQotIgICABkDABkABQr9ItsPAAACAAIAAQqfCM0ZATQAAAAA.Temparia:BAAANQAECgMIAwAAAA==.Tenderfiddle:BAAANQADCgEIAQAAAA==.Tenochitilan:BAABNQAECn8bAAMTAAgK1w7XnQA8AQATAAcKdwvXnQA8AQAQAAMK8An10gBqAAAAAA==.',
Th='Thedon:BAAANQAECgEIAQAAAA==.Themagi:BAAANQADCgYIBgAAAA==.Theocracy:BAAANQAECgQIDQAAAA==.Thia:BAAANQABCgQIAwAAAA==.Thoorz:BAAANQAECgIIAwAAAA==.Thorimeir:BAAANQAECgUIBQAAAA==.Thorzy:BAAANQAECggIDwABNQAECgIIAwAJAAAAAA==.Thraxacious:BAABNQAECn9ZAAIHAAoKuiDSBADVAgAHAAoKuiDSBADVAgAAAA==.Thulsadoomm:BAABNQAECn8VAAIWAAYKfh2TQAD8AQAWAAYKfh2TQAD8AQAAAA==.Thundermay:BAAANQAECgYIEwAAAA==.',
Ti='Tiduss:BAABNQAECn8WAAINAAUKMQupLADSAAANAAUKMQupLADSAAAAAA==.Tigó:BAAANQAECgcIDAAAAA==.Tigölebittie:BAAANQADCgEIAQAAAA==.Tiik:BAABNQAECn8jAAIoAAgK4BjaEAACAgAoAAgK4BjaEAACAgAAAA==.Timorrow:BAAANQADCgcICwAAAA==.Tinkerbel:BAABNQAECn8oAAILAAkKZRxYNQCPAgALAAkKZRxYNQCPAgAAAA==.Tinkerbella:BAAANQAECgQIBQAAAA==.Tinkerrbella:BAAANQAECgEIAQABNQAFFAYIGgABALUZAA==.Tireliaa:BAAANQADCgUIBgAAAA==.Tisem:BAAANQADCgEIAQAAAA==.',
To='Toe:BAAANQADCgIIAgAAAA==.Tohsaka:BAAANQADCgQICQAAAA==.Torsin:BAAANQADCgIIAgAAAA==.Totamic:BAAANQAECgQIBgAAAA==.',
Tr='Trafalgor:BAAANQAECgQIBgAAAA==.Trafalgour:BAAANQAECgEIAQAAAA==.Trazen:BAAANQAECgEIAQAAAA==.Tribulationz:BAAANQADCgUIBQABNQAECgYIEAAJAAAAAA==.Triplebolt:BAAANQAECgQIBAAAAA==.Try:BAAANQAECggIBAABNQAECggIEAAJAAAAAA==.',
Ts='Tsukinagi:BAAANQAECgIIAgAAAA==.Tsun:BAABNQAECn8pAAMOAAkKNQ9pnQDTAQAOAAkKNQ9pnQDTAQANAAYKIwgfLQCbAAAAAA==.Tsurinoya:BAAANQAECgIIAgAAAA==.',
Tu='Tundal:BAAANQAECgQIBwAAAA==.',
Ty='Tydz:BAAANQAECgEIAwABNQAFFAYIEAALAIMPAA==.Tyylerdurden:BAAANQAECgQIBAAAAA==.',
Ua='Uafraidofme:BAABNQAECn8VAAIFAAgKCg+itQBlAQAFAAgKCg+itQBlAQAAAA==.',
Ud='Uddermishap:BAEANQADCgYIBgABNQAECgoKOgABAAMYAA==.Uddertrouble:BAEBNQAECn86AAIBAAoKAxiuPgBZAgABAAoKAxiuPgBZAgAAAA==.',
Ul='Ulfgrim:BAAANQADCgYIDwAAAA==.',
Un='Unholytiran:BAAANQAECgYICQAAAA==.',
Ur='Urmada:BAABNQAECn8xAAMmAAkKPhKcDADvAQAmAAgKOhScDADvAQAbAAEKUwbPZgEpAAAAAA==.Urmami:BAABNQAECn8lAAICAAkKqxSLVgDQAQACAAkKqxSLVgDQAQAAAA==.Urmyenemy:BAAANQADCgEIAQAAAA==.',
Ut='Utterlyaloof:BAAANQAECgYIBwAAAA==.',
Uz='Uzui:BAAANQAECgIIAgAAAA==.',
Va='Valyne:BAAANQAECgQIBQAAAA==.Vampire:BAABNQAECn8cAAIiAAgKgB8FEQDnAgAiAAgKgB8FEQDnAgAAAA==.Vampyre:BAABNQAECn8VAAIWAAkKlhuJLQBgAgAWAAkKlhuJLQBgAgAAAA==.Vanadie:BAAANQAECgIIAgAAAA==.Vanta:BAAANQAECgEIAQAAAA==.Varekth:BAAANQADCgMIAwAAAA==.Vargmal:BAAANQAECgcIBwAAAA==.',
Vi='Virala:BAAANQAECgQIBQAAAQ==.Visenya:BAAANQAECgMIBQAAAA==.Visquake:BAAANQAECgIIBQAAAA==.Vitamin:BAAANQADCgcIBwABNQAECggIKAAFABwgAA==.Vitaminn:BAABNQAECn8oAAQFAAgKHCBfdQBDAgAFAAgKHCBfdQBDAgAIAAEKDQp+ZQAyAAALAAEKIQOhKQEsAAAAAA==.',
Vl='Vlaen:BAAANQAECgQIBAAAAA==.',
Vo='Votum:BAAANQADCgkJFgAAAA==.',
Vy='Vyrisa:BAAANQAECgEIAgAAAA==.Vyrma:BAAANQADCgIIAgAAAA==.',
Wa='Warpstorms:BAAANQADCgQIBAAAAA==.Warpwalker:BAAANQADCgEIAQAAAA==.Wasabii:BAAANQAECgYICgABNQAFFAQICQAVALgJAA==.',
Wh='Whisa:BAABNQAECn8xAAIhAAoKsiB4DAB9AwAhAAoKsiB4DAB9AwAAAA==.White:BAAANQADCggICAABNQAFFAgIEwAQALYTAA==.',
Wi='Wildwolff:BAAANQAECgQIBgAAAA==.Wilhedin:BAABNQAECn8rAAIOAAgKKCQVJgAhAwAOAAgKKCQVJgAhAwAAAA==.Willowwind:BAAANQAECgMIAwABNQAECgoKKQAoAI4gAA==.Wing:BAEBNQAFFH8GAAILAAQKuwWxFQAHAQALAAQKuwWxFQAHAQAAAA==.',
Wo='Wolfblade:BAAANQADCgQIBQAAAA==.Worm:BAACNQAFFH8SAAIOAAgKOxfXBgBUAgAOAAgKOxfXBgBUAgA1AAQKfz4AAg4ACgrXI60QABQDAA4ACgrXI60QABQDAAAA.',
Wu='Wulfnbolt:BAAANQAECgUJCAAAAA==.',
Ww='Wwoman:BAAANQAECgIIAgAAAA==.',
Wy='Wyon:BAAANQAECggINAAAAQ==.',
['Wî']='Wîtçhplz:BAAANQADCggICAAAAA==.',
Ya='Yasnah:BAAANQADCggIEgAAAA==.',
Yu='Yunahpabo:BAABNQAECn9EAAIOAAoKsyDqHQDPAgAOAAoKsyDqHQDPAgAAAA==.Yurna:BAAANQADCgMIAgAAAA==.',
Za='Zaffyl:BAAANQADCggIDAAAAA==.Zandi:BAAANQAECgUIDwAAAA==.Zanikan:BAAANQAECggICgAAAA==.Zankuza:BAAANQAECggIAwAAAA==.Zathara:BAABNQAECn9FAAIHAAoKzxbBDQDwAQAHAAoKzxbBDQDwAQAAAA==.',
Zi='Zinpan:BAAANQAECgcIDwAAAA==.',
Zo='Zodiac:BAABNQAECn8vAAIOAAkKJBnLUgAGAgAOAAkKJBnLUgAGAgAAAA==.Zoopals:BAAANQADCgcICwAAAA==.',
Zu='Zuggle:BAAANQAECgUIBgAAAA==.Zuluk:BAABNQAECn8ZAAMBAAgKwRERkwDjAQABAAcKGxQRkwDjAQAKAAQKygPAbgB2AAAAAA==.',
['Zö']='Zörö:BAABNQAECn8+AAMWAAkKFBd2PABOAQAUAAgKFBfuXQCYAQAWAAkKHA12PABOAQAAAA==.',
['ßr']='ßruise:BAAANQAECggIAgAAAA==.',
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
