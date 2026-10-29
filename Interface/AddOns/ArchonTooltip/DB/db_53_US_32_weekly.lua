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

local lookup = {'Priest-Holy','Druid-Balance','Paladin-Holy','Paladin-Retribution','DemonHunter-Devourer','Warlock-Demonology','Warlock-Destruction','Evoker-Devastation','Warrior-Arms','Shaman-Restoration','Hunter-BeastMastery','Mage-Arcane','DeathKnight-Blood','Shaman-Enhancement','DeathKnight-Unholy','Druid-Restoration','Unknown-Unknown','Monk-Windwalker','Paladin-Protection','Rogue-Assassination','Warrior-Fury','Mage-Frost','Warlock-Affliction','Hunter-Marksmanship','Druid-Guardian','DemonHunter-Havoc','Priest-Discipline','DemonHunter-Vengeance','Shaman-Elemental','Priest-Shadow','Evoker-Preservation','Evoker-Augmentation','Hunter-Survival','Rogue-Outlaw','Druid-Feral','Rogue-Subtlety','Monk-Mistweaver','Mage-Fire','Warrior-Protection','Monk-Brewmaster',}
local provider = {region='US',realm='Blackhand',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Absorbency:BAABNQAECn8VAAIBAAgKBRVmQgCpAQABAAgKBRVmQgCpAQABNQAFFAUICgACAGwDAA==.',
Ae='Aeris:BAABNQAECn8bAAMDAAcKKQi/vQABAQADAAYKfQe/vQABAQAEAAcKVw1EzADJAAAAAA==.Aethwyn:BAAANQAECgUIDAAAAA==.',
Ag='Agandaur:BAAANQAECgQICQAAAA==.',
Ah='Ahnkala:BAAANQAECgQIDAAAAA==.Ahzi:BAAANQAECgMIAwAAAA==.',
Ai='Aigirlfriend:BAABNQAECn9IAAIFAAoKIhGOFAClAQAFAAoKIhGOFAClAQAAAA==.Aimdablame:BAAANQAECgMIBQAAAA==.',
Al='Allupcreepy:BAABNQAECn8qAAIBAAcKXxeUSACOAQABAAcKXxeUSACOAQAAAA==.',
Am='Amalyndi:BAAANQAECggIDgAAAA==.Ambewlance:BAABNQAECn8fAAMGAAkKkRVohgDWAQAGAAcK9BRohgDWAQAHAAMKHxUGPgDKAAAAAA==.Amethystra:BAABNQAECn8oAAIIAAoKLge7DAARAQAIAAoKLge7DAARAQAAAA==.Amlu:BAAANQAECgcIEQABNQAECgoKJwAEAC8eAA==.Amorathon:BAAANQAECgYICgAAAA==.',
An='Andaconda:BAABNQAECn8eAAIJAAkKZRjrQQDHAQAJAAkKZRjrQQDHAQAAAA==.Annimosity:BAAANQAECgEIAQAAAA==.Ansem:BAAANQAECgEIAgAAAA==.Anthesis:BAAANQAECgcIEgABNQAFFAQIDQAKAHsVAA==.Anúbis:BAAANQADCggIFQAAAA==.',
Ap='Apawllo:BAAANQAECgEIAQAAAA==.Apep:BAAANQAECgYIEwAAAA==.Apostle:BAABNQAECn8bAAIBAAkKIB4UIQDrAgABAAkKIB4UIQDrAgAAAA==.',
Ar='Aramìs:BAAANQAECgQIBgAAAA==.Arcaya:BAAANQADCggIHgAAAA==.Ariaka:BAAANQADCgEIAQAAAA==.Arleen:BAABNQAECn8UAAILAAUKYgdX8gAdAQALAAUKYgdX8gAdAQAAAA==.Arlida:BAABNQAECn8aAAIKAAkK2BdIXQD3AQAKAAkK2BdIXQD3AQAAAA==.Artemys:BAABNQAECn8jAAILAAkKyhhHRQCcAgALAAkKyhhHRQCcAgAAAA==.Aryto:BAAANQADCgUIBQAAAA==.',
As='Ashlar:BAAANQADCgEIAQAAAA==.Asketill:BAAANQAECgUIBQAAAA==.Asmodee:BAABNQAECn8aAAIMAAgK+Qzq8wCjAQAMAAgK+Qzq8wCjAQAAAA==.',
Au='Aure:BAAANQADCgYIDAAAAA==.Auren:BAAANQADCgIIAgAAAA==.',
Az='Azonya:BAAANQABCgQIBAAAAA==.',
Ba='Bainne:BAAANQADCgUICAAAAA==.Baitken:BAAANQAECgUIDAABNQAECgcIJwANANIWAA==.Barfy:BAAANQAECgMIBAAAAA==.Barktea:BAAANQAECgYIDwAAAA==.Batharel:BAABNQAECn8aAAILAAcKqA79nAD1AAALAAcKqA79nAD1AAAAAA==.Battcantdps:BAABNQAECn8UAAIDAAgKigtHrQAmAQADAAgKigtHrQAmAQAAAA==.Battleground:BAAANQADCgMIAwAAAA==.',
Be='Beam:BAAANQADCgEIAQAAAA==.Bearen:BAABNQAECn8aAAIOAAkK3wMPHQCSAQAOAAkK3wMPHQCSAQAAAA==.Beertrain:BAABNQAECn9EAAIPAAoKxRPtEwDqAQAPAAoKxRPtEwDqAQAAAA==.Beesechurger:BAABNQAECn8fAAIMAAgKWxvbigBpAgAMAAgKWxvbigBpAgAAAA==.Belladue:BAAANQADCggILgAAAA==.Bellezza:BAABNQAECn9IAAIQAAoKVhl0CADJAgAQAAoKVhl0CADJAgAAAA==.Belphoebe:BAEANQABCgIIAgABNQAECgcIEwARAAAAAA==.',
Bh='Bhikku:BAABNQAECn8WAAISAAoK2xKVKgDIAQASAAoK2xKVKgDIAQABNQAECgoKJwAEAC8eAA==.Bhilly:BAAANQAECgIIAgAAAA==.',
Bi='Bigdumbcatqt:BAABNQAECn80AAITAAoKSyZhAAD8AwATAAoKSyZhAAD8AwAAAA==.Bigdumbkatqt:BAACNQAFFH8TAAINAAYKRCJxBAA6AgANAAYKRCJxBAA6AgA1AAQKfx8AAg0ACgrdJigAAAsEAA0ACgrdJigAAAsEAAAA.Bignjuicy:BAABNQAECn8gAAIJAAoKZBiAXwBvAgAJAAoKZBiAXwBvAgAAAA==.Bimisi:BAABNQAECn8bAAIUAAoKGBBzMAAgAgAUAAoKGBBzMAAgAgAAAA==.',
Bl='Blades:BAAANQADCgMIBgAAAA==.Bloodshhot:BAABNQAECn86AAILAAkKYh/pJgD8AgALAAkKYh/pJgD8AgAAAA==.Bloodthorne:BAAANQADCggIFgAAAA==.Blueragebar:BAAANQAECgcIEAAAAA==.',
Bo='Bobadasmash:BAABNQAECn81AAMJAAoKVRmaNwD0AQAJAAoKohaaNwD0AQAVAAQKnxauLwBCAAAAAA==.Bobitt:BAAANQAECgUIEAAAAA==.Boddyknocker:BAABNQAECn8cAAIHAAgKHxb6AwBxAQAHAAgKHxb6AwBxAQAAAA==.Bonkler:BAAANQAECgMIAwAAAA==.Boombox:BAAANQADCgYIBgAAAA==.Boomvoker:BAAANQAECgEIAQABNQAFFAUICAACAIUdAA==.Boonerichard:BAAANQAECgUIDgAAAA==.Boopdoctor:BAAANQADCgQIBAAAAA==.Bouchewager:BAAANQADCgYIBgAAAA==.',
Br='Braina:BAABNQAECn8gAAMMAAkKxgyEZACBAQAMAAkKxgyEZACBAQAWAAMKcAZBMQB3AAAAAA==.Brandy:BAAANQAECgUIBQABNQAECgoKPAAXAFQYAA==.Branwin:BAAANQADCggIHAAAAA==.Braver:BAACNQAFFH8YAAIYAAcKNhMUBQAsAQAYAAcKNhMUBQAsAQA1AAQKfzQAAxgACgpGH7EGAJUCABgACgpGH7EGAJUCAAsAAQq4C9FaATgAAAAA.Braverwar:BAAANQAECgIIAwABNQAFFAcIGAAYADYTAA==.Brayedine:BAAANQADCgcIFwAAAA==.Break:BAACNQAFFH8fAAIEAAcKriW9AADfAgAEAAcKriW9AADfAgA1AAQKfywAAgQACgpuJggTAHoDAAQACgpuJggTAHoDAAE1AAUUBwofAAQAriUA.Bromungandr:BAAANQADCgYIDgAAAA==.',
Bu='Buligerent:BAAANQADCggIGAABNQAECgoKSAAZAI4cAA==.',
By='Bynnyy:BAAANQAECgIIAgAAAA==.',
['Bù']='Bùbbles:BAAANQAECgUIEQAAAA==.',
Ca='Cadelsaya:BAABNQAECn8+AAQDAAoKgQ47XAAEAgADAAoKgQ47XAAEAgAEAAUKEQqwKwHYAAATAAEKAADfaQA/AAAAAA==.Camandah:BAABNQAECn8qAAICAAoKsROZMwBJAgACAAoKsROZMwBJAgABNQAECgQICAARAAAAAA==.Cammandzar:BAAANQAECgUIBwABNQAECgQICAARAAAAAA==.Candy:BAAANQABCgQIAgAAAA==.Canman:BAAANQAECgIIAgAAAA==.Carlo:BAAANQAECgEIAwAAAA==.Carryout:BAAANQAECggICwAAAA==.Caskca:BAAANQADCgEIAQAAAA==.Cassecs:BAAANQAECgEIAQAAAA==.Cassei:BAAANQAECgYIEAAAAA==.Cassiell:BAAANQAECgQIBQAAAA==.Castertroy:BAABNQAECn8aAAMWAAgKnAQNHAAQAQAWAAcKRwUNHAAQAQAMAAcKpgFnfQHHAAAAAA==.',
Cb='Cbtx:BAAANQADCgUIBQAAAA==.',
Ce='Celenia:BAAANQAECgQIBAAAAA==.',
Ch='Chainari:BAAANQAECgIIAgAAAA==.Charmless:BAAANQADCgcIEwABNQAECgoKRgAaALEgAA==.Chaíner:BAAANQADCgMIAwAAAA==.Chee:BAAANQAECggIEAAAAA==.Cheeksdakota:BAAANQAECgEIAQAAAA==.Cheetopaly:BAABNQAECn8eAAMDAAgKTBppYAD3AQADAAgKTBppYAD3AQAEAAYKiwcNDQEJAQAAAA==.Chuga:BAAANQAECgUICwABNQAECgkJGAABAO8iAA==.Chìgusa:BAABNQAECn9JAAMBAAoKISWOAwC9AwABAAoKISWOAwC9AwAbAAUKcxVrDwA1AQAAAA==.',
Ci='Cilenzer:BAAANQAECgIIAgABNQAECgYILQACAFMTAA==.Circa:BAAANQADCgEIAQAAAA==.',
Cl='Clarimonde:BAAANQADCgEIAQAAAA==.Cleaveradius:BAAANQADCggICAABNQAECgkJJAAKAI0fAA==.Clumonk:BAABNQAECn8oAAISAAkKDRmjGwBfAgASAAkKDRmjGwBfAgAAAA==.',
Co='Coleric:BAAANQAECgYIBgAAAA==.Convoke:BAAANQADCggIEAABNQAECgkJGwABACAeAA==.Coosar:BAAANQAECgQICgAAAA==.Coosedaplug:BAAANQAECggICgABNQAECgkJGAABAO8iAA==.Cooseyloosey:BAABNQAECn8YAAIBAAkK7yLzHgD0AgABAAkK7yLzHgD0AgAAAA==.Coosinator:BAAANQAECgYIDgABNQAECgkJGAABAO8iAA==.Cooterray:BAAANQAECgUICAAAAA==.Corellon:BAABNQAECn8jAAMEAAgK9Q/epwDQAQAEAAgK9Q/epwDQAQATAAIKqA2jXwBdAAAAAA==.Corinth:BAABNQAECn8UAAIMAAcKYQhcFwFlAQAMAAcKYQhcFwFlAQAAAA==.',
Cr='Cratoz:BAABNQAECn8oAAIEAAgKeB5bVACZAgAEAAgKeB5bVACZAgAAAA==.Crosstero:BAAANQADCgUIBQAAAA==.Crosswind:BAAANQAFFAIIAgAAAA==.Croswind:BAABNQAECn89AAILAAoKuhghMADcAgALAAoKuhghMADcAgAAAA==.',
Cu='Curandero:BAAANQADCgUIDQABNQAECgEIAgARAAAAAA==.',
Cy='Cyndrine:BAACNQAFFH8HAAIcAAMKWxueAgAJAQAcAAMKWxueAgAJAQA1AAQKf0MAAhwACgq/JYQAANcDABwACgq/JYQAANcDAAAA.Cynex:BAAANQAECggIBAAAAA==.Cyrani:BAABNQAECn9EAAMdAAoKjiWrAgDeAwAdAAoKjiWrAgDeAwAKAAYKrCTvPABsAgAAAA==.',
Da='Dadipps:BAABNQAECn8oAAIKAAkKKiD4NwB/AgAKAAkKKiD4NwB/AgAAAA==.Daggumit:BAAANQADCggIHgAAAA==.Dagnei:BAAANQAECgQIBwAAAA==.Daltina:BAABNQAECn8eAAMeAAYK3RuXLQC4AQAeAAYK3RuXLQC4AQABAAUKBxU4ngA6AQAAAA==.Damage:BAAANQAECggIAgAAAA==.Dannyboone:BAAANQADCggICAABNQAECgoKOQANADkcAA==.Dareael:BAABNQAECn8uAAIEAAgKCBezdwA9AgAEAAgKCBezdwA9AgAAAA==.Darklighete:BAAANQABCgUIBQAAAA==.Daurgoth:BAABNQAECn8WAAMfAAkKTgmnKwBNAQAfAAcKIAmnKwBNAQAgAAYKFwOOGQClAAAAAA==.Dazoner:BAAANQADCggILAAAAA==.',
De='Deadbydrand:BAAANQAECggICwAAAA==.Deadrus:BAAANQAECggIBgAAAA==.Deathndspark:BAABNQAECn8wAAINAAkKkg5IXwB1AQANAAkKkg5IXwB1AQAAAA==.Deathpuma:BAABNQAECn8xAAINAAoKgR/0FgD1AgANAAoKgR/0FgD1AgAAAA==.Deathrowe:BAABNQAECn8vAAIPAAoKihvYIwCzAgAPAAoKihvYIwCzAgAAAA==.Ded:BAAANQAECgEIAQAAAA==.Dednevoker:BAAANQAECgEIAQABNQAECgoKGQAGANEVAA==.Deelyte:BAAANQAECgIIAgAAAA==.Demonvann:BAAANQADCggICAAAAA==.Demítrá:BAAANQADCgIIAgABNQAECgkJMwAdABEcAA==.Denouncer:BAAANQAECgcIDQABNQAECgkJJAAKAI0fAA==.Derca:BAABNQAECn8eAAMcAAYKmRejGQAaAQAaAAYKexQzSACIAQAcAAUKpBWjGQAaAQAAAA==.Dethork:BAAANQADCgcIDAAAAA==.',
Di='Dieds:BAAANQADCgYIBgABNQAECgoKGQAGANEVAA==.Dienne:BAAANQAECgEIAQAAAA==.Dietunicorn:BAAANQAECggIDgAAAA==.Dinarra:BAAANQADCgUIBgAAAA==.Diosdelaluna:BAAANQADCgcIEgAAAA==.Dirtybyrd:BAAANQAECgEIAQAAAA==.Disahzter:BAABNQAECn8qAAQHAAkKAQ4TIgBgAQAHAAYKlA0TIgBgAQAGAAkKdQqLegACAQAXAAEKAADkIQAAAAAAAA==.Divona:BAAANQABCgMIAQAAAA==.',
Do='Docbledore:BAABNQAECn8dAAIMAAoKIwv3VgCnAQAMAAoKIwv3VgCnAQAAAA==.Docdrood:BAAANQADCgcIBwABNQAECgoKHQAMACMLAA==.Docmonk:BAAANQAECgEIAQABNQAECgoKHQAMACMLAA==.Docpriest:BAABNQAECn8YAAIeAAcKAgzINQB2AQAeAAcKAgzINQB2AQABNQAECgoKHQAMACMLAA==.Donlazul:BAAANQAECgMIAQAAAA==.Dotlotto:BAAANQAECgEJAgAAAA==.',
Dr='Draconoth:BAABNQAECn8fAAIPAAcKfQ6YLwANAQAPAAcKfQ6YLwANAQAAAA==.Dragfin:BAAANQAECgEIAQAAAA==.Dragonir:BAABNQAECn8cAAMaAAoKTw4UPQDPAQAaAAkKAw8UPQDPAQAcAAMKlQrdFgCBAAABNQAECgoKJwAEAC8eAA==.Dranddrand:BAAANQAECgcIDgAAAA==.Dreadborn:BAAANQADCgMIBAAAAA==.',
Du='Dungard:BAAANQAECgcIDQABNQAECgoKPgADAIEOAA==.Dunstird:BAAANQAECgIIAgABNQAFFAUICAACAIUdAA==.',
Dy='Dyami:BAAANQAECgUIEAAAAA==.',
['Dè']='Dèadèyè:BAAANQADCggJDgAAAA==.',
Ea='Eatmorechkn:BAABNQAECn80AAIEAAoKwhC9ewAzAgAEAAoKwhC9ewAzAgAAAA==.',
Ee='Eellonwy:BAAANQAECgMIBQAAAA==.Eemerald:BAAANQAECgUIDwAAAA==.',
Eg='Egna:BAABNQAECn8mAAIdAAoKnw2DRABDAQAdAAoKnw2DRABDAQAAAA==.',
El='Electricblu:BAAANQAECgQIDAAAAA==.Elijx:BAAANQAECgQICAAAAA==.Elizaa:BAABNQAECn8pAAMKAAoKGBIUbADHAQAKAAkKlxEUbADHAQAdAAYKYg4uXQD1AAAAAA==.',
Em='Emaya:BAAANQAECgUIDAAAAA==.Emmadar:BAAANQAECgQIBAABNQAECgoKQwAGAJYSAA==.',
En='Engaa:BAAANQADCggICwAAAA==.',
Er='Erioch:BAAANQAECgEIAgAAAA==.',
Eu='Euripidus:BAAANQADCgEIAQAAAA==.',
Ev='Evilclared:BAAANQADCgUICgABNQAFFAYIEQAJAKsWAA==.Evildean:BAAANQAECgQIBAAAAA==.',
Ex='Execute:BAAANQADCgUICQAAAA==.',
Ey='Eyllian:BAAANQADCgYIBgABNQAECgkJMQANANYOAA==.',
Fa='Fanya:BAAANQADCgYIBgABNQAECgoKOAAeAHQcAA==.Fathernatur:BAAANQADCgYICQAAAA==.Fatherpain:BAAANQABCgYIEQAAAA==.',
Fe='Fenrigaar:BAABNQAECn8yAAICAAoK6x8eFAAmAwACAAoK6x8eFAAmAwAAAA==.',
Ff='Ffsa:BAABNQAECn84AAQLAAoKnhwRMgDWAgALAAkKXBoRMgDWAgAYAAkKiRrDGgB+AgAhAAEKAAAJEwA5AAAAAA==.',
Fi='Fillin:BAAANQAECgEIAgAAAA==.Filô:BAABNQAECn8ZAAIeAAkKbRvgGQB+AgAeAAkKbRvgGQB+AgAAAA==.Findinnan:BAAANQADCgUIBgAAAA==.',
Fl='Flame:BAAANQADCgQIBAAAAA==.Flanker:BAAANQADCgYIBgABNQAECggIHwAMAFsbAA==.Flintmini:BAAANQADCgQJBAAAAA==.Flossylock:BAAANQAECgUIBgAAAA==.',
Fo='Forsakenly:BAAANQADCggIGAAAAA==.',
Fr='Frasti:BAAANQAECgIIAgAAAA==.Freshstart:BAAANQAECgEIAQAAAA==.Frodes:BAAANQABCgYJBwAAAA==.Frostmage:BAABNQAECn9EAAIMAAoKOBVYPQD/AQAMAAoKOBVYPQD/AQAAAA==.',
Fu='Fuegoblazeit:BAAANQABCgIIAgAAAA==.Furbucket:BAAANQAECgYICwAAAA==.Futonhunts:BAABNQAECn9FAAILAAoK4iGFDAB6AwALAAoK4iGFDAB6AwAAAA==.Futontotems:BAAANQAECgUIBQAAAA==.',
Fy='Fylerw:BAABNQAECn8vAAIFAAkKDRE/JgATAgAFAAkKDRE/JgATAgAAAA==.',
Ga='Gailyn:BAAANQADCgYICgAAAA==.Galebb:BAAANQAECgEIAQABNQAECgcIHgAZACYPAA==.Gardros:BAAANQABCgQIBAAAAA==.',
Gh='Ghostrideher:BAABNQAECn8wAAILAAoKfBdmJQBNAgALAAoKfBdmJQBNAgAAAA==.',
Gi='Gigadad:BAACNQAFFH8FAAILAAMKHBmCFgAHAQALAAMKHBmCFgAHAQA1AAQKfzsAAgsACgp3JD4LAIMDAAsACgp3JD4LAIMDAAAA.Gigafather:BAAANQAECgUICQAAAA==.',
Gl='Gladiuz:BAAANQAECgUICQABNQAECgoKJwAEAC8eAA==.',
Go='Gornthemonki:BAAANQADCgcICgAAAA==.Goyahokasinj:BAAANQADCgYIFwAAAA==.',
Gr='Griannee:BAABNQAECn8+AAIaAAoKbBl9DgBkAgAaAAoKbBl9DgBkAgAAAA==.Grimtoetem:BAAANQABCgYJCQAAAA==.Grislix:BAABNQAECn88AAQXAAoKVBj4BAB/AgAXAAkKQxn4BAB/AgAGAAcKeg4IrwBzAQAHAAIKgRZ0EwB+AAAAAA==.Grismistea:BAAANQAECgEIAQABNQAECgoKPAAXAFQYAA==.Grismunch:BAAANQABCggICAABNQAECgoKPAAXAFQYAA==.Gryffin:BAABNQAECn8eAAMWAAkKIxDKDQDSAQAWAAkKIxDKDQDSAQAMAAEKPwW8ygEyAAAAAA==.',
Gu='Guidance:BAAANQADCgcIBwAAAA==.Gulan:BAAANQADCgMIAwAAAA==.Gummies:BAAANQABCgYIDgAAAA==.',
['Gâ']='Gânk:BAABNQAECn8wAAIJAAoKhAv6kADyAQAJAAoKhAv6kADyAQAAAA==.',
Ha='Hanrekt:BAAANQAECgUICwAAAA==.Happiness:BAABNQAECn8hAAIJAAgKSw5zUACSAQAJAAgKSw5zUACSAQABNQAECgoKNAALANggAA==.',
He='Heavensbliss:BAAANQAECgUIBQABNQAECgoKRAAMADgVAA==.Heavychevy:BAABNQAECn8gAAIVAAkKSRQZDQDmAQAVAAkKSRQZDQDmAQAAAA==.Hellvenger:BAAANQADCggIDAAAAA==.Heriel:BAABNQAECn8gAAIMAAkKqA9RdABbAQAMAAkKqA9RdABbAQABNQAECgoKJwAEAC8eAA==.Hexquisite:BAAANQAECgUIBQABNQAECgkJGwABACAeAA==.',
Hi='Hildoehealz:BAABNQAECn8dAAMBAAoKKR1hCABYAwABAAoKKR1hCABYAwAbAAEKliHnHwBiAAAAAA==.Hinatachan:BAAANQADCgMIAwAAAA==.',
Ho='Holybit:BAAANQAECgYIDQAAAA==.Homgar:BAAANQADCgMIBAAAAA==.Horrni:BAAANQADCggIDAAAAA==.Hotsjkpurge:BAAANQADCgQIBAAAAA==.',
Hu='Humphrees:BAABNQAECn9IAAIUAAoK3hW5CAACAgAUAAoK3hW5CAACAgAAAA==.',
Hy='Hydrospin:BAAANQADCgQIBAAAAA==.Hypocrisy:BAAANQAECgYIBgAAAA==.',
['Hà']='Hàtos:BAABNQAECn8mAAIMAAkKMxcPqAAyAgAMAAkKMxcPqAAyAgAAAA==.',
Ic='Ickis:BAAANQAECgIIAgAAAA==.',
Id='Idot:BAAANQADCgUJDgABNQAECgcIIQAcAJ0FAA==.Iduni:BAAANQADCgIIAgAAAA==.',
Ii='Iironrod:BAAANQADCgUIBQAAAA==.',
Il='Illidave:BAAANQADCgYIBwABNQAECgcIHQAYAGcEAA==.',
In='Incubus:BAAANQAECggIEQABNQAECgoKJwAEAC8eAA==.Inebriatas:BAAANQAECgEIAQABNQAECgcIKQAfAO0jAA==.Inu:BAAANQABCgIJAgAAAA==.Invissibill:BAABNQAECn8uAAIiAAkK6wk7AwBeAQAiAAkK6wk7AwBeAQAAAA==.',
Ir='Ironbark:BAAANQADCgUICAAAAA==.Irôh:BAAANQADCgYIBgAAAA==.',
Is='Ishaa:BAABNQAECn8iAAMQAAoKHB63EgC4AgAQAAoKHB63EgC4AgACAAMK3xByigCrAAAAAA==.',
Iv='Ivanä:BAABNQAECn8jAAMBAAgKSB8mKwAaAgABAAgKSB8mKwAaAgAbAAEKXgy8EQAyAAAAAA==.',
Iz='Izax:BAABNQAECn9CAAQGAAkKSA7XWABYAQAGAAgKrQ3XWABYAQAHAAEK5xHGcQA9AAAXAAEKYwZEMwAtAAAAAA==.',
Ja='Jaddzia:BAAANQABCgQIBAAAAA==.Jadestone:BAAANQAECgUIDQAAAA==.Jaemarie:BAAANQABCggIEAAAAA==.Jaguarkick:BAAANQADCggIIAAAAA==.Jamestown:BAAANQADCggIDAAAAA==.',
Je='Jeffray:BAAANQAECgIIAgAAAA==.Jessi:BAAANQAECgcIEQAAAA==.',
Jo='Johnnyhildoe:BAAANQADCgQIBAAAAA==.Jonsneew:BAAANQADCgYICgAAAA==.',
Ju='Judgment:BAAANQADCgMIBwAAAA==.Junglefu:BAAANQADCgIIAgAAAA==.Jupitus:BAABNQAECn8YAAIEAAcK5xFprADHAQAEAAcK5xFprADHAQAAAA==.Justin:BAAANQAECgUIBwABNQAECgYIBgARAAAAAA==.',
['Jù']='Jùstin:BAAANQADCgMIAwABNQAFFAYIDwACAEAWAA==.',
['Jû']='Jûstin:BAAANQAECgcICQABNQAFFAYIDwACAEAWAA==.',
Ka='Kabroz:BAABNQAECn8bAAIMAAoKShS/SgDRAQAMAAoKShS/SgDRAQAAAA==.Kale:BAAANQABCgcICwAAAA==.Karma:BAAANQAECgYIEgAAAA==.Katalania:BAABNQAECn8ZAAMDAAgKsA4ZiwB7AQADAAcK+g0ZiwB7AQAEAAUKGgTYQAG4AAAAAA==.',
Ke='Keeincar:BAAANQADCgIIAgAAAA==.Keeshama:BAAANQAECgEIAgAAAA==.Kegna:BAAANQADCggIJgAAAA==.Keiwhenua:BAABNQAECn8qAAMQAAgKLBOGJgDtAQAQAAgKLBOGJgDtAQAjAAEK6AOlTQAcAAAAAA==.Kelinn:BAAANQAECgUIDQAAAA==.Kelzier:BAAANQAECgUIEAABNQAECgoKJwAEAC8eAA==.Kenthel:BAABNQAECn8qAAMkAAkKzhn0JwDpAQAkAAgKlRn0JwDpAQAUAAQKLBqScADuAAAAAA==.Kenthels:BAAANQAECgQICgABNQAECgkJKgAkAM4ZAA==.Kezt:BAAANQAECgIIAgABNQAECgYIDQARAAAAAA==.',
Ki='Kikspally:BAAANQABCgQIBAAAAA==.Kiplander:BAABNQAECn8tAAMCAAYKUxM3WwBmAQACAAYKUxM3WwBmAQAZAAEKAABBZQAqAAAAAA==.Kiplandr:BAAANQAECgMIAgAAAA==.Kitheryn:BAAANQAECgcICAAAAA==.',
Kl='Klitt:BAAANQAECgYICgAAAA==.',
Ko='Komosky:BAACNQAFFH8fAAISAAcKrAdCAwBCAQASAAcKrAdCAwBCAQA1AAQKfzoAAhIACgpCHPMHAJcCABIACgpCHPMHAJcCAAE1AAQKBAgEABEAAAAA.Konas:BAAANQADCggICAABNQAECgkJLQATAH8fAA==.Korry:BAAANQAECgUIDwAAAA==.Kortanis:BAABNQAECn8YAAILAAcKCwOzBwH3AAALAAcKCwOzBwH3AAAAAA==.',
Kr='Krakìn:BAAANQAECgQICgAAAA==.',
Ku='Kush:BAABNQAECn8fAAQHAAkKfBOpDQAeAgAHAAgKgROpDQAeAgAGAAcKrAo43wALAQAXAAEKAAAMLwA4AAAAAA==.',
Ky='Kyana:BAAANQADCgYICgAAAA==.Kyrianna:BAAANQAECgUIDAAAAA==.Kyäk:BAAANQAECgUICwAAAA==.',
['Kü']='Küngfury:BAAANQADCgUIBQAAAA==.',
La='Laerik:BAAANQABCgEIAQAAAA==.Landissa:BAABNQAECn8cAAIkAAkKkxS9GAAVAgAkAAkKkxS9GAAVAgAAAA==.Larcenciel:BAAANQAECgcIEAAAAA==.Larryholmes:BAAANQABCgQIBAABNQADCggICAARAAAAAA==.',
Le='Leen:BAAANQABCgYICQAAAA==.Letmehelpyou:BAABNQAECn8kAAIKAAkKjR+VNQCJAgAKAAkKjR+VNQCJAgAAAA==.',
Li='Licky:BAAANQAECggIEgAAAA==.Lihan:BAABNQAECn8jAAIVAAcKYxe6DgDCAQAVAAcKYxe6DgDCAQAAAA==.Lilieth:BAAANQADCggIDAAAAA==.Lily:BAABNQAECn9NAAIPAAoK3x/uBwCsAgAPAAoK3x/uBwCsAgAAAA==.Lively:BAABNQAECn8YAAMeAAYKXxOYNQB3AQAeAAYKXxOYNQB3AQABAAMKzhLv6ABrAAAAAA==.',
Lo='Lockedtoit:BAAANQAECgIIAgAAAA==.Loveg:BAAANQADCgYIDAAAAA==.Loverocket:BAABNQAECn88AAITAAoKJx59BgCEAgATAAoKJx59BgCEAgAAAA==.',
Lp='Lpfan:BAAANQABCgUIBQAAAA==.',
Lu='Luna:BAAANQAECgUIBQABNQAECgYICgARAAAAAA==.Lunastorm:BAAANQADCgQIBAAAAA==.',
Ly='Lyshia:BAABNQAECn8+AAMMAAoK8h6cOwAQAwAMAAoK7h6cOwAQAwAWAAMKuh4lEwDfAAAAAA==.',
['Lí']='Líghthand:BAABNQAECn8WAAMTAAgKChp1HAAIAgATAAgKChp1HAAIAgAEAAEK/wGj3AETAAAAAA==.',
['Lý']='Lýght:BAAANQADCgcIDQAAAA==.',
Ma='Magdaanii:BAAANQAECgIIAgAAAA==.Magedown:BAABNQAECn8vAAMMAAoKlxROhwBwAgAMAAoKlxROhwBwAgAWAAEKkAVZUwAfAAAAAA==.Magician:BAAANQADCggICAAAAA==.Mamachula:BAAANQADCgYIDQAAAA==.Manapali:BAAANQAECgYIDAABNQAECgoKQgAOACMeAA==.Manpumper:BAAANQAECgYICgAAAA==.Margor:BAABNQAECn8ZAAIGAAYKzw9YiwDaAAAGAAYKzw9YiwDaAAABNQAECggIKAAdAIkXAA==.Mariella:BAAANQAECgcIDAABNQAECggIEAARAAAAAA==.Marne:BAAANQADCgUIBQAAAA==.Mattdemon:BAABNQAECn9GAAMaAAoKsSCmCQC4AgAaAAoKsSCmCQC4AgAFAAcKuxKuNQCWAQAAAA==.',
Me='Meanzy:BAAANQADCgQIBAAAAA==.Meatsack:BAAANQADCgMIAwAAAA==.Meliany:BAAANQAECgUICwAAAA==.Meliorate:BAACNQAFFH8KAAMCAAUKbANGHAC4AAACAAQKbANGHAC4AAAQAAIKMgPxFQBFAAA1AAQKfzEAAwIACgr/FAw5ACcCAAIACQqvFQw5ACcCABAACArHD40eAGwBAAAA.Meowch:BAABNQAECn8xAAIjAAoKuR4MBABVAwAjAAoKuR4MBABVAwAAAA==.Meríin:BAAANQADCgEIAQAAAA==.',
Mi='Mikachu:BAABNQAECn9VAAIOAAoK0iW2AADPAwAOAAoK0iW2AADPAwABNQAFFAYIEAAEAFEaAA==.Miksi:BAAANQAECgEIAQAAAA==.Miradele:BAABNQAECn8qAAIQAAcKIArCLAD9AAAQAAcKIArCLAD9AAAAAA==.Miraxx:BAAANQAECgEIAgAAAA==.Misscleö:BAABNQAECn8cAAIEAAkKahV+hgAaAgAEAAkKahV+hgAaAgAAAA==.Miyoshi:BAABNQAECn8uAAIkAAkKTAplIADLAQAkAAkKTAplIADLAQAAAA==.',
Mo='Mobius:BAAANQABCgIIBQAAAA==.Monoka:BAAANQAECgIIAgAAAA==.Moonshíne:BAAANQADCgIIAgAAAA==.Moosakka:BAABNQAECn83AAIlAAkKcBKrGQDlAQAlAAkKcBKrGQDlAQAAAA==.Moosesiah:BAAANQABCgYICgABNQAECgoKNAAlABQYAA==.Moovinthru:BAAANQAECgQIBgAAAA==.Moraxes:BAAANQAECgUIBgAAAA==.Mordenkainen:BAAANQAECgUIDAAAAA==.Morgax:BAABNQAECn8nAAQdAAoKnhTRRwBXAgAdAAkKIhXRRwBXAgAKAAoK4BnUSgA4AgAOAAEKqwPINgA0AAAAAA==.Morgona:BAAANQADCgUICQAAAA==.Morphidmage:BAAANQADCgUIBQAAAA==.Motoko:BAAANQAECgEIAQAAAA==.Motolei:BAAANQADCgUIBQABNQAECgoKPQALALoYAA==.',
Mu='Muaadib:BAABNQAECn8cAAIZAAgKjhzFDQDTAQAZAAgKjhzFDQDTAQABNQAECgoKPQALALoYAA==.',
My='Mydin:BAABNQAECn8mAAIEAAoKoRJxmwDsAQAEAAoKoRJxmwDsAQAAAA==.Myssaphra:BAACNQAFFH8NAAIKAAQKexXJDAAVAQAKAAQKexXJDAAVAQA1AAQKfy0AAwoACgoNGz8wAKACAAoACgoNGz8wAKACAB0AAQoAAORLASgAAAAA.',
['Mì']='Mìsawa:BAABNQAECn8iAAMGAAkKcwsKpQCKAQAGAAgKMgsKpQCKAQAHAAQKBwg5QQC+AAAAAA==.',
Na='Nakai:BAABNQAECn87AAILAAoKZhv8JwD4AgALAAoKZhv8JwD4AgAAAA==.Nasatra:BAAANQADCggIGgAAAA==.Nastijiggle:BAABNQAECn8cAAIeAAoKVBfWIAAyAgAeAAoKVBfWIAAyAgAAAA==.Nazrien:BAAANQABCgUJBQAAAA==.Nazrion:BAAANQABCgEIAQAAAA==.',
Nc='Nc:BAABNQAECn8YAAIZAAkK9R9hCgDKAgAZAAkK9R9hCgDKAgAAAA==.',
Ne='Nexxa:BAABNQAECn8oAAILAAgKkgtNjQDvAQALAAgKkgtNjQDvAQAAAA==.',
Ni='Nightfall:BAAANQAECggICAAAAA==.Nightshadow:BAAANQADCgQIBAAAAA==.Nightsongs:BAAANQABCgIIAgAAAA==.Niqkle:BAABNQAECn82AAMKAAoKNRW3cQC3AQAKAAkKEhS3cQC3AQAdAAoKTROtKgC1AQAAAA==.Nitebane:BAABNQAECn8dAAIUAAkK2Qm1QADJAQAUAAkK2Qm1QADJAQAAAA==.',
No='Nohurtscooby:BAAANQAECgIIAQAAAA==.Notadh:BAAANQADCggIEAAAAA==.Notadruid:BAAANQADCgQIBAAAAA==.Notawrlock:BAAANQAECgEIAQABNQAFFAUICAACAIUdAA==.',
Ns='Nstagatr:BAABNQAECn8dAAIYAAcKZwRpRwAhAQAYAAcKZwRpRwAhAQAAAA==.',
Ny='Nyara:BAAANQAECgUIBQAAAA==.Nyxandria:BAAANQABCgQIBAAAAA==.Nyxi:BAAANQABCgQIBAAAAA==.',
['Né']='Nécrömancer:BAAANQADCgMIAwAAAA==.',
Oa='Oak:BAAANQAECgIIAgAAAA==.',
Oc='Occidius:BAAANQAECgYIEQAAAA==.',
Ol='Olari:BAAANQAECgEIAQAAAA==.Oldfox:BAAANQAECgIIAwAAAA==.Oldoriel:BAAANQADCgYICwAAAA==.Olehanna:BAABNQAECn9FAAIEAAoKSA5/WwClAQAEAAoKSA5/WwClAQAAAA==.Olestrid:BAAANQADCggILgABNQAECgoKRQAEAEgOAA==.',
On='Oni:BAAANQADCgYICAAAAA==.',
Op='Opioid:BAAANQAECgMIAwAAAA==.Opsec:BAAANQAECgIJAgABNQAECgcIHAAFAM4WAA==.Opsèc:BAABNQAECn8cAAIFAAcKzhaGLwDGAQAFAAcKzhaGLwDGAQAAAA==.',
Or='Oriicc:BAAANQAECgEIAQAAAA==.Orochimaru:BAAANQADCgMIAwAAAA==.Orsa:BAAANQADCggICAAAAA==.',
Pe='Peachcider:BAEANQAECgMIBwABNQAFFAcIIAAKAOsdAA==.Peachshock:BAECNQAFFH8gAAMKAAcK6x1AAgCLAgAKAAcK6x1AAgCLAgAdAAMKSA9dHADeAAA1AAQKfygAAwoACgqJIw4KAHEDAAoACgqJIw4KAHEDAB0ABApaIQ6pAEIBAAAA.Peachyknight:BAAANQAECgQIBAAAAA==.Peebee:BAAANQAECgMIAwABNQAECgoKYgAJAHoiAA==.Perfectlock:BAABNQAECn8oAAIGAAoKTRcyQQCPAgAGAAoKTRcyQQCPAgAAAA==.Peri:BAAANQAECgMIAwAAAA==.',
Pi='Pigog:BAABNQAECn8fAAILAAgKnwU7wgB+AQALAAgKnwU7wgB+AQAAAA==.',
Po='Pooskbuddy:BAAANQADCgcIFAAAAA==.Popcorners:BAAANQADCggIDwABNQAECgoKMQAOACclAA==.Pordgio:BAAANQAECggIDwAAAA==.Pozzi:BAAANQAECggIEgAAAA==.',
Pr='Praypal:BAAANQADCgQIBAAAAA==.Primoss:BAAANQAECgEIAQABNQAECgcIHAAFAM4WAA==.',
Ps='Psuedolus:BAAANQAECgUIDwAAAA==.Psålm:BAABNQAECn8wAAIeAAoKixc9FwCeAgAeAAoKixc9FwCeAgAAAA==.',
Pu='Pulshadow:BAACNQAFFH8SAAIeAAYK9BEiBAAnAQAeAAYK9BEiBAAnAQA1AAQKfzMAAh4ACgobI6kEAOcCAB4ACgobI6kEAOcCAAAA.Pumah:BAAANQAECgEIAgAAAA==.',
Qt='Qtclaps:BAAANQADCggIHwAAAA==.',
Qu='Quartzecoatl:BAAANQADCgUICQAAAA==.',
Ra='Raahhzi:BAAANQADCgYIDAAAAA==.Raamen:BAAANQAECgEIAQABNQAECgEIAQARAAAAAA==.Raellia:BAABNQAECn9DAAQGAAoKlhJ/TQB8AQAGAAkK1RF/TQB8AQAHAAMKLRG/QQC9AAAXAAEKTghLMQAyAAAAAA==.Raimmey:BAAANQAECgQIBQAAAA==.Rajia:BAAANQAECgMIAgABNQAECgkJLQAHAFsKAA==.Ralune:BAABNQAECn8qAAICAAkK4QgQKgA5AQACAAkK4QgQKgA5AQAAAA==.Randomshaman:BAAANQADCgUIBgAAAA==.Ranes:BAABNQAECn9IAAMkAAoKkB7GFwBfAgAUAAgKbR2TGQCwAgAkAAoKvxrGFwBfAgAAAA==.Razagual:BAAANQAECggIEgABNQAECggIBgARAAAAAA==.',
Re='Reaperss:BAAANQAECgIIAQAAAA==.Redback:BAAANQABCgMIBgAAAA==.Redxelementz:BAABNQAECn9JAAMKAAoKiCaYAADnAwAKAAoKiCaYAADnAwAdAAgKPiEgDgCvAgAAAA==.Redxpastakan:BAAANQADCgUIBQABNQAECgoKSQAKAIgmAA==.Redxyara:BAABNQAECn8XAAIGAAoKDhwUNQDWAQAGAAoKDhwUNQDWAQAAAA==.Renasen:BAABNQAECn8qAAIJAAgKZCEDNgDqAgAJAAgKZCEDNgDqAgAAAA==.Reno:BAABNQAECn8tAAMDAAgK6xjeTQAzAgADAAgK6xjeTQAzAgAEAAcKDg/8vwCcAQAAAA==.Replacegamy:BAAANQAECgMICAABNQAFFAUICAACAIUdAA==.Resiretha:BAABNQAECn8cAAMGAAgKLARf0QAnAQAGAAgKGgRf0QAnAQAHAAIK6AKZawBJAAAAAA==.Revelynn:BAABNQAECn82AAMcAAoKnhk5DAAEAgAFAAoKFBlnHAByAgAcAAoKuRE5DAAEAgAAAA==.Rexkwondo:BAAANQAECgQJBAAAAA==.',
Rh='Rhyssyn:BAAANQADCgUIBQAAAA==.',
Ri='Rilerich:BAAANQAECgEIAQAAAA==.Rivliam:BAABNQAECn8kAAMHAAgKyxALJABSAQAGAAgKTw4tVwBdAQAHAAYKIw4LJABSAQAAAA==.Rizzn:BAAANQAECgQIBwABNQAECgkJKgAkAM4ZAA==.',
Ro='Rook:BAAANQAECgIIAgAAAA==.Rooxxy:BAABNQAECn8ZAAMMAAcKoBdgwgD/AQAMAAcKoBdgwgD/AQAWAAEK5QiGTwAoAAAAAA==.Rotawna:BAAANQADCgcIHwAAAA==.Roxxyyzz:BAAANQAECgQICAABNQAECgcIGQAMAKAXAA==.Roûge:BAAANQAECgMIAwABNQAECgoKYgAJAHoiAA==.',
Ru='Rumikang:BAAANQADCgIIAgABNQAECgoKQwAGAJYSAA==.',
Ry='Rybeorn:BAAANQAECgEIBQAAAA==.Rynoh:BAAANQAECgcIEAAAAA==.Rythrik:BAABNQAECn8kAAMDAAoK4hTeGQB0AgADAAoK4hTeGQB0AgAEAAIKYguYdQFnAAAAAA==.',
Sa='Sainted:BAACNQAFFH8aAAIDAAcKPxi3AwBXAgADAAcKPxi3AwBXAgA1AAQKfzMAAwMACgqNG78VAJYCAAMACgqNG78VAJYCAAQABwqAFMPNAIABAAAA.Sanoks:BAABNQAECn8tAAMTAAkKfx/SCQD/AgATAAkKfx/SCQD/AgAEAAIKbQZJjQFHAAAAAA==.Sanokz:BAAANQAECgUIBgABNQAECgkJLQATAH8fAA==.Santar:BAAANQADCgcIBwAAAA==.Sassafraz:BAAANQADCggICAABNQAECgoKPAATACceAA==.Savira:BAABNQAECn8cAAIQAAcK0A5cNgBpAQAQAAcK0A5cNgBpAQAAAA==.',
Sc='Scaleorva:BAABNQAECn8nAAMIAAcKWxD4CwAiAQAIAAcKWxD4CwAiAQAgAAQKiQhbGgCbAAAAAA==.Scarlit:BAAANQABCgYIBgAAAA==.',
Se='Sentharis:BAAANQADCggIDgAAAA==.Seraphìm:BAABNQAECn8mAAIEAAkKDgmg1wBsAQAEAAkKDgmg1wBsAQAAAA==.Seïnaru:BAAANQAECgQIBwAAAA==.',
Sh='Shadefu:BAAANQADCgcIBwABNQAECgkJJgAMAJEPAA==.Shadenova:BAAANQADCgUIBgABNQAECgkJJgAMAJEPAA==.Shadezilla:BAAANQADCgYIBgABNQAECgkJJgAMAJEPAA==.Shadostalkrr:BAAANQAECggICQABNQAFFAUICAACAIUdAA==.Shadowpath:BAAANQABCgQIBAAAAA==.Shadowypete:BAAANQAECgUIBQAAAA==.Shadyballs:BAABNQAECn8mAAQMAAkKkQ8zYgCIAQAMAAkKkQ8zYgCIAQAmAAMKVw/JBwC1AAAWAAIKeAyqNABoAAAAAA==.Shakypete:BAAANQAECgUICwABNQAECgYILQACAFMTAA==.Shamken:BAAANQADCgYIBgAAAA==.Shamysosa:BAABNQAECn8oAAMdAAgKiRcrNwB5AQAdAAgKiRcrNwB5AQAKAAIKzA82xgA2AAAAAA==.Shiionknow:BAAANQADCgQIBAAAAA==.Shinjí:BAABNQAECn8hAAIPAAkKYRy9IQDAAgAPAAkKYRy9IQDAAgAAAA==.Shmob:BAAANQAECgEIAgAAAA==.Shnappz:BAABNQAECn8sAAMGAAcK9gn/fAD9AAAGAAcK9gn/fAD9AAAHAAEKbQLLhgAhAAAAAA==.Shwillarou:BAABNQAECn8/AAIPAAoKBg2rKwAkAQAPAAoKBg2rKwAkAQAAAA==.Shádôws:BAAANQADCgYICwAAAA==.',
Si='Sinergee:BAABNQAECn8ZAAILAAgK+AxAhwD8AQALAAgK+AxAhwD8AQAAAA==.Sinnj:BAAANQAECgIIAgAAAA==.Sinona:BAAANQADCgQIBAAAAA==.Sipholice:BAAANQAECgEIAQABNQAECgYIFAAZAJAeAA==.',
Sk='Skinzey:BAAANQAECgUIBwAAAA==.Skycrush:BAAANQADCgUICQAAAA==.',
Sl='Slanie:BAABNQAECn8dAAIBAAgK4wZumwBDAQABAAgK4wZumwBDAQAAAA==.Slingerz:BAABNQAECn9GAAMnAAoKMRkdBgAdAgAnAAoKMRkdBgAdAgAVAAEKAABtOQAjAAAAAA==.Slingr:BAAANQAECgUIBQAAAA==.',
Sm='Smalldragon:BAAANQAECggICQAAAA==.Smoky:BAABNQAECn8nAAQGAAoK7Ro7TABvAgAGAAkKVho7TABvAgAXAAMKahE0GwCpAAAHAAEKURYEbwBBAAAAAA==.',
Sn='Sneakpastya:BAAANQADCgIIAgAAAA==.Sneakyg:BAABNQAECn8dAAIkAAkKKhPhNgCOAQAkAAkKKhPhNgCOAQABNQAECgoKJwAEAC8eAA==.Snoochie:BAABNQAECn8iAAIdAAgK9xPnYgD4AQAdAAgK9xPnYgD4AQAAAA==.',
So='Sol:BAACNQAFFH8OAAIiAAUKOx3oAACsAQAiAAUKOx3oAACsAQA1AAQKf0MAAyIACgqyI8QAAKYDACIACgqyI8QAAKYDACQABgpnHeMvALUBAAAA.Solkar:BAAANQAECgMIAgABNQAECgoKOQANADkcAA==.Sollis:BAABNQAECn8cAAIMAAYKSwNU1ACoAAAMAAYKSwNU1ACoAAAAAA==.Sonastii:BAAANQADCgYIBgABNQAECgoKHAAeAFQXAA==.Soulcoil:BAAANQAECgQICQABNQAECgYIFgAaAIMTAA==.Soulfury:BAAANQABCgUIBgABNQAECgYIFgAaAIMTAA==.Soulreaper:BAABNQAECn8WAAIaAAYKgxPATABrAQAaAAYKgxPATABrAQAAAA==.Soulshock:BAAANQAECgQICQABNQAECgYIFgAaAIMTAA==.Soulstorm:BAAANQADCgYIBgABNQAECgYIFgAaAIMTAA==.',
Sp='Sparnak:BAABNQAECn8wAAIMAAgK5wJcxgC+AAAMAAgK5wJcxgC+AAAAAA==.Spawntier:BAAANQADCgUIBQABNQADCggICAARAAAAAA==.Spazzchel:BAAANQAECgUIBQAAAA==.Spiritbox:BAACNQAFFH8KAAIKAAYKdRqIBwDgAQAKAAYKdRqIBwDgAQA1AAQKfyMAAgoACQqxJJINAFQDAAoACQqxJJINAFQDAAE1AAQKCQkbAAEAIB4A.Spruce:BAAANQADCggIMAAAAA==.Sprucemoose:BAAANQADCgUICwABNQADCggIGgARAAAAAA==.',
St='Stahlman:BAABNQAECn8+AAMKAAkKxBrbGwBiAgAKAAkKxBrbGwBiAgAdAAIK+AbwGgFaAAAAAA==.Stalpho:BAABNQAECn80AAIVAAoKxBddBgCmAgAVAAoKxBddBgCmAgAAAA==.Starblessed:BAAANQAECgEIAQABNQAECggIIwAKAB4KAA==.Starflare:BAAANQADCgUIBQABNQAECggIIwAKAB4KAA==.Starkind:BAABNQAECn8jAAIKAAgKHgp2UABVAQAKAAgKHgp2UABVAQAAAA==.Starliner:BAABNQAECn8xAAIOAAoKJyWdAQAqAwAOAAoKJyWdAQAqAwAAAA==.Stasis:BAAANQAECgUICAABNQAECgkJGwABACAeAA==.Stealbreath:BAAANQADCggICgAAAA==.Stormyknight:BAAANQADCgUIDgAAAA==.Strahd:BAAANQADCgYIFAAAAA==.Styrke:BAAANQADCgYIBgAAAA==.Styrmir:BAAANQAECgQIBAAAAA==.',
Su='Subza:BAABNQAECn9GAAMMAAoKKhz9IwBnAgAMAAoKKhz9IwBnAgAWAAEK1RPGQwA8AAAAAA==.',
Sw='Swagadin:BAAANQADCgcIBwABNQAECggIEQARAAAAAA==.Swagikal:BAAANQAECggIEQAAAA==.Swagtistic:BAAANQAECggIDAAAAA==.',
Ta='Tahra:BAAANQADCgcICgAAAA==.Taliss:BAABNQAECn8+AAIBAAoKDx0MEgDaAgABAAoKDx0MEgDaAgAAAA==.Tankmedaddy:BAACNQAFFH8FAAISAAIKtREdCgCEAAASAAIKtREdCgCEAAA1AAQKfz0AAxIACgrPGIALAEACABIACgrPGIALAEACACUABApLF6MvAOwAAAAA.Tappuccino:BAAANQAECgUIDgAAAA==.Taras:BAACNQAFFH8IAAIJAAIKNRAVKQCzAAAJAAIKNRAVKQCzAAA1AAQKfyoAAwkACgrbJNREALsCAAkACQo8JNREALsCABUABgqKGJoQAJwBAAAA.Taraxist:BAABNQAECn8jAAIHAAoKQBrrBQCzAgAHAAoKQBrrBQCzAgAAAA==.Tautology:BAABNQAECn8eAAIeAAoKDRS6HABeAgAeAAoKDRS6HABeAgAAAA==.Tazajin:BAAANQADCgYIBgAAAA==.',
Tc='Tchala:BAABNQAECn8nAAIEAAoKLx5jPgDaAgAEAAoKLx5jPgDaAgAAAA==.Tchallah:BAAANQAECgYICAAAAA==.Tchaumb:BAAANQADCgEIAQAAAA==.',
Td='Tdog:BAAANQADCgcJBwAAAA==.',
Te='Teacup:BAAANQADCgYIBgABNQAECgkJGAAZAPUfAA==.Teks:BAABNQAECn8eAAMDAAkKHRjYUwAeAgADAAkKHRjYUwAeAgATAAYKKRgFMABeAQAAAA==.Teksara:BAAANQAECgQIAwABNQAECgkJHgADAB0YAA==.Teksdyne:BAAANQABCgIIAgABNQAECgkJHgADAB0YAA==.Teksynoth:BAAANQADCgQIBAABNQAECgkJHgADAB0YAA==.Tekszen:BAAANQABCgIIAgABNQAECgkJHgADAB0YAA==.Telian:BAAANQADCgUIBQAAAA==.Terracustode:BAAANQABCgIJAgAAAA==.Teth:BAABNQAECn8hAAMHAAgKmRLoDgAMAgAHAAgKmRLoDgAMAgAGAAEKAADCVwEgAAAAAA==.Tevildo:BAAANQABCgIIAgAAAA==.',
Th='Thaine:BAABNQAECn9GAAIEAAoKSSQ3DACgAwAEAAoKSSQ3DACgAwAAAA==.Theoalthor:BAAANQAECgQIAwAAAA==.Theundeadone:BAABNQAECn84AAIeAAoKdBw0CwAxAwAeAAoKdBw0CwAxAwAAAA==.Thndrwzrd:BAAANQAECgQICAAAAA==.Thorphan:BAABNQAECn86AAQOAAoKXiOxAQCeAwAOAAoKXiOxAQCeAwAdAAUKARefuAAhAQAKAAUKcAu3zwDIAAAAAA==.',
Ti='Ticho:BAAANQAECgUICwAAAA==.',
To='Torez:BAAANQAECgUIDgABNQAECgoKRgAaALEgAA==.Torodisilis:BAAANQAECgYIDQABNQAECgoKJwAEAC8eAA==.Torteeny:BAAANQADCgIIAgABNQAECgYICQARAAAAAA==.Torukia:BAAANQAECgcIDAAAAA==.Toxicavenger:BAAANQAECggIDgAAAA==.',
Tr='Treygec:BAAANQAECgUICgAAAA==.Tribolonotus:BAAANQAECgQICAAAAA==.Trickette:BAAANQADCgcICAABNQAECggIDwARAAAAAA==.Trilleong:BAAANQADCgIIAgAAAA==.Trina:BAAANQADCggICAAAAA==.Trisilla:BAAANQADCggIFQABNQAECgoKNQAoAPcNAA==.Troubleshot:BAAANQAECggICAAAAA==.Truelock:BAAANQADCgEIAQAAAA==.Trujal:BAABNQAECn8oAAINAAoKyxcILwBXAgANAAoKyxcILwBXAgAAAA==.',
Tu='Turdmonk:BAABNQAECn9QAAISAAoKAyF1BQDbAgASAAoKAyF1BQDbAgAAAA==.',
Ty='Tylandon:BAAANQABCgQIEAAAAA==.Tyndal:BAAANQADCgcIDwAAAA==.Typhon:BAABNQAECn81AAMeAAoKxRuyGACMAgAeAAkKTxqyGACMAgABAAgKXBpKVgAgAgAAAA==.',
Tz='Tzaim:BAAANQAECgUIBQAAAA==.',
Um='Umen:BAAANQADCgUIBQAAAA==.',
Un='Unclebób:BAAANQADCgYIDAABNQAECgUICAARAAAAAA==.Unshady:BAAANQADCggIDgABNQAECgkJJgAMAJEPAA==.',
Va='Vaeshta:BAABNQAECn8rAAIOAAkKmgNpFgAkAQAOAAkKmgNpFgAkAQAAAA==.Vaku:BAAANQADCgYIBgAAAA==.Valhallarama:BAABNQAECn8xAAIKAAoKLBtEQABfAgAKAAoKLBtEQABfAgAAAA==.Valika:BAAANQABCgYIBgAAAA==.Vampy:BAAANQAECgQIBAAAAA==.Vandragon:BAAANQADCggIGAAAAA==.Vannida:BAAANQAECgQICAAAAA==.Vardanis:BAAANQAECgQIBAABNQAECgcIIQAbAEMaAA==.',
Ve='Vengencedawg:BAABNQAECn8sAAIEAAoKyggzwACcAQAEAAoKyggzwACcAQAAAA==.Vexxya:BAAANQADCgQIAwAAAA==.',
Vl='Vladus:BAABNQAECn85AAINAAoKORyGEAA9AgANAAoKORyGEAA9AgAAAA==.',
Vo='Voltroñ:BAAANQADCgMIAwABNQAFFAUIEgAMAHEZAA==.Voodoo:BAAANQAECgQIBAAAAA==.',
Vs='Vsegda:BAAANQAECgcIEwABNQAFFAQIDQAKAHsVAA==.',
Vy='Vyllian:BAABNQAECn8xAAINAAkK1g4ZUgCsAQANAAkK1g4ZUgCsAQAAAA==.',
Wa='Wangwang:BAAANQAECgQICAAAAA==.Wardrag:BAAANQABCgQIBAAAAA==.Wareshesh:BAAANQADCgUIBQAAAA==.Warlakaflaka:BAABNQAECn8ZAAQXAAYKbRNQDQCGAQAXAAYKbRNQDQCGAQAHAAMKYQhIUACPAAAGAAEKAAB4RAEyAAABNQAECgkJJgAMAJEPAA==.Warsha:BAAANQADCgEIAQAAAA==.',
Wh='Whale:BAABNQAECn8WAAInAAkKJRuVDABrAgAnAAkKJRuVDABrAgAAAA==.',
Wi='Wickðaddy:BAAANQABCgMIAwAAAA==.Windfury:BAABNQAECn8kAAIOAAoKbRFtFQARAgAOAAoKbRFtFQARAgAAAA==.Windfuryous:BAAANQADCgUICQAAAA==.Winston:BAAANQADCggIKQAAAA==.',
Wo='Wolfsbane:BAAANQADCgYIBgAAAA==.Wolfson:BAAANQADCggICAAAAA==.Wonpiece:BAAANQAECggIEgABNQAFFAUICgACAGwDAA==.',
Wu='Wulfnir:BAAANQADCgcIBwAAAA==.',
Wy='Wylestrean:BAACNQAFFH8FAAILAAIKGBm2GACOAAALAAIKGBm2GACOAAA1AAQKfysAAgsACgqjH0EyANUCAAsACgqjH0EyANUCAAAA.',
Xa='Xanokz:BAAANQADCgEIAQABNQAECgkJLQATAH8fAA==.Xarytha:BAAANQAECgUIBQABNQAECgoKGgAMAFIWAA==.',
Xi='Xiaomao:BAAANQADCgcIBwABNQAECgEIAQARAAAAAA==.',
Xy='Xyrathul:BAAANQAECggICgAAAA==.',
Ye='Yeinn:BAABNQAECn9iAAMJAAoKeiIWHABHAwAJAAoKeiIWHABHAwAVAAYKhh02DQDkAQAAAA==.',
Yo='Yorshka:BAABNQAECn8+AAIBAAoK+xmQOACGAgABAAoK+xmQOACGAgAAAA==.',
Za='Zandalarthas:BAABNQAECn8nAAINAAcK0hYuNAAYAQANAAcK0hYuNAAYAQAAAA==.Zanthor:BAAANQADCgcIBwABNQAFFAIIBQASALURAA==.Zarbok:BAAANQADCgQIBAABNQAECggIKAAdAIkXAA==.',
Zc='Zcredo:BAABNQAECn9FAAIJAAoKgyCxFQC5AgAJAAoKgyCxFQC5AgAAAA==.',
Ze='Zel:BAAANQAECgUICwAAAA==.Zentradei:BAAANQADCgQIBAAAAA==.Zephariel:BAAANQADCggIGAAAAA==.Zerus:BAAANQABCgMIBAAAAA==.',
Zi='Ziconik:BAAANQADCgYIBgAAAA==.Zieganfuss:BAABNQAECn8aAAMMAAoKUhYnqgAuAgAMAAoKHhUnqgAuAgAWAAMK+BU9FQDLAAAAAA==.Zinrozlek:BAABNQAECn8eAAINAAcKWweYegAOAQANAAcKWweYegAOAQAAAA==.',
Zo='Zoho:BAABNQAECn81AAIoAAoK9w16BgCiAQAoAAoK9w16BgCiAQAAAA==.Zorrander:BAAANQADCgQIBAABNQAECgQIBQARAAAAAA==.',
Zy='Zynvar:BAAANQADCggICAAAAA==.',
['Ðj']='Ðjay:BAAANQABCgUIBQAAAA==.',
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
