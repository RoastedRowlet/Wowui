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

local lookup = {'Druid-Balance','Paladin-Holy','Paladin-Retribution','DemonHunter-Devourer','Priest-Holy','Warlock-Demonology','Warlock-Destruction','Evoker-Devastation','Warrior-Arms','Shaman-Restoration','Hunter-BeastMastery','Mage-Arcane','Unknown-Unknown','DeathKnight-Blood','Shaman-Enhancement','DeathKnight-Unholy','Druid-Restoration','Paladin-Protection','Rogue-Assassination','Warrior-Fury','Mage-Frost','Warlock-Affliction','Hunter-Marksmanship','Druid-Guardian','DemonHunter-Havoc','Priest-Discipline','Monk-Windwalker','DemonHunter-Vengeance','Shaman-Elemental','Priest-Shadow','Hunter-Survival','Evoker-Preservation','Rogue-Outlaw','Druid-Feral','Rogue-Subtlety','Monk-Mistweaver','Evoker-Augmentation','Mage-Fire','Warrior-Protection','Monk-Brewmaster',}
local provider = {region='US',realm='Blackhand',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Absorbency:BAAANQAECgYIDgABNQAFFAQICQABAGwDAA==.',
Ac='Achean:BAAANQADCgEIAQAAAA==.',
Ae='Aeris:BAABNQAECn8aAAMCAAYKfQe/vQABAQACAAYKfQe/vQABAQADAAYK3g79mQCnAAAAAA==.Aethwyn:BAAANQAECgUIDAAAAA==.',
Ag='Agandaur:BAAANQAECgUICgAAAA==.',
Ah='Ahnkala:BAAANQAECgMIBAAAAA==.',
Ai='Aigirlfriend:BAABNQAECn9AAAIEAAkKOxKgCACGAQAEAAkKOxKgCACGAQAAAA==.Aimdablame:BAAANQAECgMIBQAAAA==.',
Al='Aldoraine:BAAANQAECgEIAQAAAA==.Allupcreepy:BAABNQAECn8kAAIFAAcKXxePFwC1AQAFAAcKXxePFwC1AQAAAA==.',
Am='Amalyndi:BAAANQAECggIDgAAAA==.Ambewlance:BAABNQAECn8fAAMGAAkKkRVohgDWAQAGAAcK9BRohgDWAQAHAAMKHxUGPgDKAAAAAA==.Amethystra:BAABNQAECn8gAAIIAAgKqgbkHgBmAQAIAAgKqgbkHgBmAQAAAA==.Amlu:BAAANQAECgYIDAABNQAECgkJJQADADAhAA==.Amorathon:BAAANQADCggICAAAAA==.',
An='Andaconda:BAABNQAECn8WAAIJAAkKpBREQAAjAQAJAAkKpBREQAAjAQAAAA==.Annimosity:BAAANQAECgEIAQAAAA==.Ansem:BAAANQAECgEIAwAAAA==.Anthesis:BAAANQAECgcIDwABNQAFFAMICQAKACUaAA==.Anúbis:BAAANQADCggIFQAAAA==.',
Ap='Apawllo:BAAANQAECgEIAQAAAA==.Apep:BAAANQAECgQIDwAAAA==.Apostle:BAABNQAECn8bAAIFAAkKIB4UIQDrAgAFAAkKIB4UIQDrAgAAAA==.',
Ar='Aramìs:BAAANQAECgIIAgAAAA==.Arcaya:BAAANQADCggIHwAAAA==.Ariaka:BAAANQADCgEIAQAAAA==.Arleen:BAABNQAECn8UAAILAAUKYgdX8gAdAQALAAUKYgdX8gAdAQAAAA==.Arlida:BAABNQAECn8ZAAIKAAgK+xZIXQD3AQAKAAgK+xZIXQD3AQAAAA==.Artemys:BAABNQAECn8jAAILAAkKyhhHRQCcAgALAAkKyhhHRQCcAgAAAA==.Aryto:BAAANQADCgUIBgAAAA==.',
As='Ashlar:BAAANQADCgEIAQAAAA==.Asketill:BAAANQADCgYIEAAAAA==.Asmodee:BAABNQAECn8ZAAIMAAgK+Qzq8wCjAQAMAAgK+Qzq8wCjAQAAAA==.',
Au='Aure:BAAANQADCgYIDAAAAA==.Auren:BAAANQADCgIIAgAAAA==.',
Az='Azonya:BAAANQADCgEIAQAAAA==.',
Ba='Baaloo:BAAANQADCgYICQABNQAECgIIAQANAAAAAA==.Bainne:BAAANQADCgUJDQAAAA==.Baitken:BAAANQAECgUIDAABNQAECgcIIQAOANIWAA==.Balla:BAAANQADCgEIAQABNQAECgQIBwANAAAAAA==.Barfy:BAAANQAECgMIAwAAAA==.Barktea:BAAANQAECgYIDwAAAA==.Batharel:BAAANQAECgYIEQAAAA==.Battcantdps:BAAANQAECggIEwAAAA==.Battleground:BAAANQADCgMIAwAAAA==.',
Be='Bearen:BAABNQAECn8aAAIPAAkK3wMPHQCSAQAPAAkK3wMPHQCSAQAAAA==.Beertrain:BAABNQAECn85AAIQAAoKxROxAwASAgAQAAoKxROxAwASAgAAAA==.Beesechurger:BAABNQAECn8bAAIMAAgKWxvbigBpAgAMAAgKWxvbigBpAgAAAA==.Belladue:BAAANQADCggILwAAAA==.Bellezza:BAABNQAECn9AAAIRAAoKAxnOAQDqAgARAAoKAxnOAQDqAgAAAA==.Belphoebe:BAEANQABCgIIAgABNQAECgYIDQANAAAAAA==.',
Bh='Bhikku:BAAANQAECggIEwABNQAECgkJJQADADAhAA==.Bhilly:BAAANQAECgIIAgAAAA==.',
Bi='Bigdumbcatqt:BAABNQAECn8uAAISAAoKOSZhAAD8AwASAAoKOSZhAAD8AwAAAA==.Bigdumbkatqt:BAACNQAFFH8TAAIOAAYKRCJxBAA6AgAOAAYKRCJxBAA6AgA1AAQKfx4AAg4ACQrjJigAAAsEAA4ACQrjJigAAAsEAAAA.Bignjuicy:BAABNQAECn8eAAIJAAoKTRiAXwBvAgAJAAoKTRiAXwBvAgAAAA==.Bimisi:BAABNQAECn8XAAITAAoKUg5zMAAgAgATAAoKUg5zMAAgAgAAAA==.',
Bl='Blades:BAAANQADCgMIBgAAAA==.Bloodshhot:BAABNQAECn80AAILAAgKdh/pJgD8AgALAAgKdh/pJgD8AgAAAA==.Bloodthorne:BAAANQADCggIFAAAAA==.Blueragebar:BAAANQAECgYIDAAAAA==.',
Bo='Bobadasmash:BAABNQAECn8wAAMJAAkKVhc/CQAnAgAJAAkKlBY/CQAnAgAUAAEKvhWuLwBCAAAAAA==.Bobitt:BAAANQAECgUIDQAAAA==.Boddyknocker:BAAANQAECgYIEwAAAA==.Boombox:BAAANQADCgYIBwAAAA==.Boomvoker:BAAANQAECgEIAQABNQAFFAUICAABAIUdAA==.Boonerichard:BAAANQAECgQICQAAAA==.Boopdoctor:BAAANQADCgQIBAAAAA==.Bouchewager:BAAANQADCgYIBgAAAA==.',
Br='Braina:BAABNQAECn8YAAMMAAkKnAro8ACpAQAMAAkKnAro8ACpAQAVAAMKcAZBMQB3AAAAAA==.Brandy:BAAANQAECgUIBQABNQAECgoKNgAWAFQYAA==.Branwin:BAAANQADCggIIAAAAA==.Braver:BAACNQAFFH8YAAIXAAcKNhO7AgA1AQAXAAcKNhO7AgA1AQA1AAQKfysAAxcACgrJHU4VALQCABcACgrJHU4VALQCAAsAAQq4C9FaATgAAAAA.Braverwar:BAAANQAECgIIAwABNQAFFAcIGAAXADYTAA==.Brayedine:BAAANQADCgcIGAAAAA==.Break:BAACNQAFFH8fAAIDAAcKriW9AADfAgADAAcKriW9AADfAgA1AAQKfyQAAgMACgpZJggTAHoDAAMACgpZJggTAHoDAAE1AAUUBwofAAMAriUA.Bromungandr:BAAANQADCgYIDwAAAA==.',
Bu='Buligerent:BAAANQADCggIHAABNQAECgkJQAAYAMQbAA==.',
By='Bynnyy:BAAANQAECgIIAgAAAA==.',
['Bù']='Bùbbles:BAAANQAECgUIEAAAAA==.',
Ca='Cadelsaya:BAABNQAECn83AAQCAAoKPg47XAAEAgACAAoKPg47XAAEAgADAAUKEQqwKwHYAAASAAEKAADfaQA/AAAAAA==.Camandah:BAABNQAECn8oAAIBAAoKQxKZMwBJAgABAAoKQxKZMwBJAgABNQAECgMIBgANAAAAAA==.Cammandzar:BAAANQAECgUIBwABNQAECgMIBgANAAAAAA==.Candy:BAAANQADCgEIAQAAAA==.Canman:BAAANQAECgIIAQAAAA==.Carlo:BAAANQAECgEIAwAAAA==.Carryout:BAAANQAECggICwAAAA==.Caskca:BAAANQADCgEIAQAAAA==.Cassei:BAAANQAECgYIDQAAAA==.Cassiell:BAAANQAECgQIBQAAAA==.Castertroy:BAABNQAECn8aAAMVAAgKnAQNHAAQAQAVAAcKRwUNHAAQAQAMAAcKpgFnfQHHAAAAAA==.',
Ce='Celenia:BAAANQAECgMIAwAAAA==.',
Ch='Chainari:BAAANQAECgIIAgAAAA==.Charmless:BAAANQADCgcIFAABNQAECgoKPwAZAGkdAA==.Chaíner:BAAANQADCgMIAwAAAA==.Chee:BAAANQAECgUIDAAAAA==.Cheeksdakota:BAAANQAECgEIAQAAAA==.Cheetopaly:BAABNQAECn8cAAMCAAcK/ByXKgA4AQACAAcK/ByXKgA4AQADAAYKiwcNDQEJAQAAAA==.Chuga:BAAANQAECgUICwABNQAECgkJFwAFAO8iAA==.Chìgusa:BAABNQAECn89AAMFAAoKCSXVAADQAwAFAAoKCSXVAADQAwAaAAUKcxVrDwA1AQAAAA==.',
Ci='Cilenzer:BAAANQAECgMIAgABNQAECgYIKwABAFMTAA==.Circa:BAAANQADCgEIAQAAAA==.',
Cl='Clarimonde:BAAANQADCgEIAQAAAA==.Cleaveradius:BAAANQADCggICAABNQAECgkJIwAKAHUfAA==.Clumonk:BAABNQAECn8hAAIbAAgKBxujGwBfAgAbAAgKBxujGwBfAgAAAA==.',
Co='Coleric:BAAANQAECgYIBgAAAA==.Convoke:BAAANQADCggIEQABNQAECgkJGwAFACAeAA==.Coosar:BAAANQAECgQICgAAAA==.Coosedaplug:BAAANQAECgMIAwABNQAECgkJFwAFAO8iAA==.Cooseyloosey:BAABNQAECn8XAAIFAAkK7yLzHgD0AgAFAAkK7yLzHgD0AgAAAA==.Coosinator:BAAANQAECgYIDgABNQAECgkJFwAFAO8iAA==.Cooterray:BAAANQAECgUICAAAAA==.Corellon:BAABNQAECn8bAAMDAAgK2Q7epwDQAQADAAgK2Q7epwDQAQASAAIKqA2jXwBdAAAAAA==.Corinth:BAABNQAECn8UAAIMAAcKYQhcFwFlAQAMAAcKYQhcFwFlAQAAAA==.',
Cr='Crankypete:BAAANQADCgEIAQAAAA==.Cratoz:BAABNQAECn8oAAIDAAgKeB5bVACZAgADAAgKeB5bVACZAgAAAA==.Croswind:BAABNQAECn89AAILAAoKuhhkBQB6AgALAAoKuhhkBQB6AgAAAA==.',
Cu='Curandero:BAAANQADCgUICQABNQAECgEIAQANAAAAAA==.Curonious:BAAANQADCgEIAQAAAA==.',
Cy='Cyndrine:BAACNQAFFH8HAAIcAAMKWxueAgAJAQAcAAMKWxueAgAJAQA1AAQKfzkAAhwACgpHJYQAANcDABwACgpHJYQAANcDAAAA.Cyrani:BAABNQAECn89AAMdAAoKWSXXAAAvAwAdAAoKWSXXAAAvAwAKAAYKrCTvPABsAgAAAA==.',
Da='Dadipps:BAABNQAECn8iAAIKAAkKKiD4NwB/AgAKAAkKKiD4NwB/AgAAAA==.Daggumit:BAAANQADCggIGQAAAA==.Dagnei:BAAANQAECgMIBAAAAA==.Daltina:BAABNQAECn8eAAMeAAYK3RuXLQC4AQAeAAYK3RuXLQC4AQAFAAUKBxVHXQC4AAAAAA==.Damage:BAAANQAECggIAgAAAA==.Dannyboone:BAAANQADCggICAABNQAECgoKMAAOAHMbAA==.Dareael:BAABNQAECn8oAAIDAAgKCBezdwA9AgADAAgKCBezdwA9AgAAAA==.Darklighete:BAAANQADCgEIAQAAAA==.Daurgoth:BAAANQAECgcIEwAAAA==.Dazoner:BAAANQADCggIJAAAAA==.',
De='Deadbydrand:BAAANQAECggIDAAAAA==.Deadrus:BAAANQAECggIBgAAAA==.Deathndspark:BAABNQAECn8pAAIOAAgKsA1IXwB1AQAOAAgKsA1IXwB1AQAAAA==.Deathpuma:BAABNQAECn8qAAIOAAoK8Bz0FgD1AgAOAAoK8Bz0FgD1AgAAAA==.Deathrowe:BAABNQAECn8nAAIQAAgKKB/YIwCzAgAQAAgKKB/YIwCzAgAAAA==.Ded:BAAANQAECgEIAQAAAA==.Dednevoker:BAAANQAECgEIAQABNQAECgoKGAAGAKIVAA==.Deelyte:BAAANQAECgIIAgAAAA==.Demonvann:BAAANQADCggICQAAAA==.Demítrá:BAAANQADCgIIAgABNQAECgkJMwAdABEcAA==.Denouncer:BAAANQAECgUICgABNQAECgkJIwAKAHUfAA==.Derca:BAABNQAECn8ZAAMcAAYKmRejGQAaAQAZAAYKexQzSACIAQAcAAUKpBWjGQAaAQAAAA==.Dethork:BAAANQADCgcIDAAAAA==.',
Di='Dieds:BAAANQADCgYIBwABNQAECgoKGAAGAKIVAA==.Dienne:BAAANQAECgEIAQAAAA==.Dietunicorn:BAAANQAECggICAAAAA==.Dinarra:BAAANQADCgUIBgAAAA==.Diosdelaluna:BAAANQADCgcIEAAAAA==.Dirtybyrd:BAAANQAECgEIAQAAAA==.Disahzter:BAABNQAECn8oAAQHAAkKJQ0TIgBgAQAHAAYKlA0TIgBgAQAGAAkKmQnzSQD1AAAWAAEKAADiFgAAAAAAAA==.Divona:BAAANQADCgEIAQAAAA==.',
Do='Docbledore:BAABNQAECn8bAAIMAAoKIwuyEwDJAQAMAAoKIwuyEwDJAQAAAA==.Docdrood:BAAANQADCggICAABNQAECgoKGwAMACMLAA==.Docmonk:BAAANQAECgEIAQABNQAECgoKGwAMACMLAA==.Docpriest:BAABNQAECn8YAAIeAAcKAgzINQB2AQAeAAcKAgzINQB2AQABNQAECgoKGwAMACMLAA==.Dominusmorte:BAAANQADCgEIAQAAAA==.Donlazul:BAAANQAECgMIAwAAAA==.Dotlotto:BAAANQAECgEJAgAAAA==.',
Dr='Draconoth:BAABNQAECn8ZAAIQAAcKVQ7JGwAJAQAQAAcKVQ7JGwAJAQAAAA==.Dragfin:BAAANQAECgEIAQAAAA==.Dragonir:BAABNQAECn8ZAAIZAAkKAw8UPQDPAQAZAAkKAw8UPQDPAQABNQAECgkJJQADADAhAA==.Dranddrand:BAAANQAECgcIDgAAAA==.Dreadborn:BAAANQADCgMIBAAAAA==.',
Du='Dungard:BAAANQAECgcICAABNQAECgoKNwACAD4OAA==.Dunstird:BAAANQAECgIIAgABNQAFFAUICAABAIUdAA==.',
Dy='Dyami:BAAANQAECgUIEAAAAA==.',
['Dè']='Dèadèyè:BAAANQADCggJEAAAAA==.',
Ea='Eatmorechkn:BAABNQAECn8wAAIDAAoKwhC9ewAzAgADAAoKwhC9ewAzAgAAAA==.',
Ee='Eellonwy:BAAANQAECgIIAgAAAA==.Eemerald:BAAANQAECgUICgAAAA==.',
Eg='Egna:BAABNQAECn8fAAIdAAkKFAuGbgDUAQAdAAkKFAuGbgDUAQAAAA==.',
El='Electricblu:BAAANQAECgUICQAAAA==.Elijx:BAAANQAECgQIBAAAAA==.Elizaa:BAABNQAECn8kAAMKAAkKlxEUbADHAQAKAAkKlxEUbADHAQAdAAIKbAImJgFFAAAAAA==.',
Em='Emaya:BAAANQAECgQICAAAAA==.Emmadar:BAAANQAECgQIBAABNQAECgkJPAAHAA8RAA==.',
En='Engaa:BAAANQADCggICAAAAA==.',
Er='Erioch:BAAANQAECgIIAQAAAA==.',
Eu='Euripidus:BAAANQADCgEIAQAAAA==.',
Ev='Evilclared:BAAANQADCgUICgABNQAFFAUIEAAJAP4YAA==.Evildean:BAAANQAECgQIBAAAAA==.',
Ex='Execute:BAAANQADCgUICQAAAA==.',
Fa='Fanya:BAAANQADCgYIBwABNQAECgoKMQAeACIcAA==.Fathernatur:BAAANQAECgEIAQAAAA==.Fatherpain:BAAANQADCgEIAQAAAA==.',
Fe='Feldoray:BAAANQADCgEIAgAAAA==.Feluriaan:BAAANQADCgEIAQAAAA==.Fenrigaar:BAABNQAECn8wAAIBAAoKFB4eFAAmAwABAAoKFB4eFAAmAwAAAA==.',
Ff='Ffsa:BAABNQAECn80AAQLAAoKORwRMgDWAgALAAkKXBoRMgDWAgAXAAkKFhrDGgB+AgAfAAEKAAAJEwA5AAAAAA==.',
Fi='Fillin:BAAANQAECgIIAQAAAA==.Filô:BAABNQAECn8ZAAIeAAkKbRvgGQB+AgAeAAkKbRvgGQB+AgAAAA==.Findinnan:BAAANQADCgUIBgAAAA==.',
Fl='Flame:BAAANQADCgQIBAAAAA==.Flanker:BAAANQADCgYIBwABNQAECggIGwAMAFsbAA==.Flintmini:BAAANQADCgQJBAAAAA==.Flossylock:BAAANQAECgUIBgAAAA==.',
Fo='Forsakenly:BAAANQADCggIEgAAAA==.',
Fr='Frasti:BAAANQAECgIIAgAAAA==.Freshstart:BAAANQAECgEIAgAAAA==.Frodes:BAAANQADCgEIAQAAAA==.Frostmage:BAABNQAECn88AAIMAAkKRROdKgBwAQAMAAkKRROdKgBwAQAAAA==.',
Fu='Fuegoblazeit:BAAANQADCgEIAQAAAA==.Furbucket:BAAANQAECgYIDQAAAA==.Futonhunts:BAABNQAECn8/AAILAAoK4iHlAgDEAgALAAoK4iHlAgDEAgAAAA==.Futontotems:BAAANQADCggICAAAAA==.',
Fy='Fylerw:BAABNQAECn8oAAIEAAgK2BE/JgATAgAEAAgK2BE/JgATAgAAAA==.',
Ga='Gailyn:BAAANQADCgYIDQAAAA==.Galebb:BAAANQAECgEIAQABNQAECgcIGAAYACYPAA==.Gardros:BAAANQADCgEIAQAAAA==.',
Gh='Ghostrideher:BAABNQAECn8oAAILAAkK0hfLCgAgAgALAAkK0hfLCgAgAgAAAA==.',
Gi='Gigadad:BAACNQAFFH8FAAILAAMKHBmCFgAHAQALAAMKHBmCFgAHAQA1AAQKfzMAAgsACgpDJD4LAIMDAAsACgpDJD4LAIMDAAAA.Gigafather:BAAANQAECgYIBgAAAA==.',
Gl='Gladiuz:BAAANQAECgUICQABNQAECgkJJQADADAhAA==.',
Go='Gornthemonki:BAAANQADCgcICgAAAA==.Gothmog:BAAANQAECgEIAQAAAA==.Goyahokasinj:BAAANQADCgYIGAAAAA==.',
Gr='Griannee:BAABNQAECn80AAIZAAoKKRbaEgBUAQAZAAoKKRbaEgBUAQAAAA==.Grimtoetem:BAAANQADCgEIAQAAAA==.Grislix:BAABNQAECn82AAQWAAoKVBicAQCcAQAWAAkKQxmcAQCcAQAGAAcKeg4IrwBzAQAHAAIK+xVzCQCHAAAAAA==.Grismistea:BAAANQAECgIIAQABNQAECgoKNgAWAFQYAA==.Grismunch:BAAANQADCgEIAQAAAA==.Gryffin:BAABNQAECn8dAAMVAAgKaBDKDQDSAQAVAAgKaBDKDQDSAQAMAAEKPwW8ygEyAAAAAA==.',
Gu='Guidance:BAAANQADCgcIBwAAAA==.Gulan:BAAANQADCgMIAwAAAA==.Gummies:BAAANQADCgEIAQAAAA==.',
['Gâ']='Gânk:BAABNQAECn8sAAIJAAoKhAv6kADyAQAJAAoKhAv6kADyAQAAAA==.',
Ha='Hanrekt:BAAANQAECgUICwAAAA==.Happiness:BAABNQAECn8eAAIJAAgKAw6vGwCVAQAJAAgKAw6vGwCVAQABNQAECgoKMQALANggAA==.',
He='Heavensbliss:BAAANQAECgUIBQABNQAECgkJPAAMAEUTAA==.Heavychevy:BAABNQAECn8aAAIUAAgKSRQZDQDmAQAUAAgKSRQZDQDmAQAAAA==.Hellvenger:BAAANQADCggICwAAAA==.Heriel:BAABNQAECn8dAAIMAAcKXBFiXgABAQAMAAcKXBFiXgABAQABNQAECgkJJQADADAhAA==.Hexquisite:BAAANQAECgUIBQABNQAECgkJGwAFACAeAA==.',
Hi='Hildoehealz:BAAANQAFFAEIAQAAAA==.Hinatachan:BAAANQADCgMIAwAAAA==.',
Ho='Holybit:BAAANQAECgUIBgAAAA==.Homgar:BAAANQADCgMIBAAAAA==.Horrni:BAAANQADCgUIBwAAAA==.Hotsjkpurge:BAAANQADCgQIBQAAAA==.',
Hu='Humphrees:BAABNQAECn9AAAITAAkK8xbJBADaAQATAAkK8xbJBADaAQAAAA==.',
Hy='Hydrospin:BAAANQADCgQIBAAAAA==.Hypocrisy:BAAANQAECgUIBgAAAA==.',
['Hà']='Hàtos:BAABNQAECn8jAAIMAAgKNxUPqAAyAgAMAAgKNxUPqAAyAgAAAA==.',
Ic='Ickis:BAAANQAECgMIAwAAAA==.',
Id='Idot:BAAANQADCgUJDwABNQAECgcIIQAcAJ0FAA==.Iduni:BAAANQADCgIIAgAAAA==.',
Ii='Iironrod:BAAANQADCgUIBgAAAA==.',
Il='Illidave:BAAANQADCgYIBwABNQAECgcIHQAXAGcEAA==.',
In='Incubus:BAAANQAECgUICgABNQAECgkJJQADADAhAA==.Inebriatas:BAAANQAECgEIAQABNQAECgcIJAAgAO0jAA==.Inu:BAAANQADCgEIAQAAAA==.Inujosha:BAAANQADCgEIAQAAAA==.Invissibill:BAABNQAECn8mAAIhAAgKTwlKAgA9AQAhAAgKTwlKAgA9AQAAAA==.',
Ip='Ipatez:BAAANQADCgEIAQAAAA==.',
Ir='Ironbark:BAAANQADCgUICQAAAA==.Irôh:BAAANQADCgYIBwAAAA==.',
Is='Ishaa:BAABNQAECn8aAAMRAAoKfBu3EgC4AgARAAoKfBu3EgC4AgABAAMK3xByigCrAAAAAA==.',
Iv='Ivanä:BAABNQAECn8bAAIFAAgKWBjfTAA+AgAFAAgKWBjfTAA+AgAAAA==.',
Iz='Izax:BAABNQAECn84AAQGAAgKCQ6ORQAAAQAGAAcKQw2ORQAAAQAHAAEK5xG8FQA6AAAWAAEKYwZEMwAtAAAAAA==.',
Ja='Jaddzia:BAAANQADCgEIAQAAAA==.Jadestone:BAAANQAECgQICQAAAA==.Jaemarie:BAAANQABCggIEAAAAA==.Jaguarkick:BAAANQADCggIIwAAAA==.Jamestown:BAAANQADCgYIBAAAAA==.',
Je='Jeffray:BAAANQAECgEIAQAAAA==.Jessi:BAAANQAECgcIEQAAAA==.',
Ji='Jimbobraynor:BAAANQADCgEIAQAAAA==.',
Jo='Johnnyhildoe:BAAANQADCgQIBQAAAA==.Jonsneew:BAAANQADCgYICgAAAA==.',
Ju='Judgment:BAAANQADCgMIBwAAAA==.Junglefu:BAAANQADCgIIAgAAAA==.Jupitus:BAAANQAECgYIEAAAAA==.Justin:BAAANQAECgUIBwABNQAECgYIBgANAAAAAA==.',
['Jù']='Jùstin:BAAANQADCgMIAwABNQAFFAYIDwABAEAWAA==.',
['Jû']='Jûstin:BAAANQAECgcICQABNQAFFAYIDwABAEAWAA==.',
Ka='Kabroz:BAABNQAECn8XAAIMAAgK7BVxKAB3AQAMAAgK7BVxKAB3AQAAAA==.Kale:BAAANQADCgEIAQAAAA==.Karlock:BAAANQADCgEIAQAAAA==.Karma:BAAANQAECgYIEgAAAA==.Katalania:BAABNQAECn8ZAAMCAAgKsA4ZiwB7AQACAAcK+g0ZiwB7AQADAAUKGgTYQAG4AAAAAA==.',
Ke='Keeincar:BAAANQAECgEIAQAAAA==.Keeshama:BAAANQAECgEIAgAAAA==.Kegna:BAAANQADCggIIgAAAA==.Keiwhenua:BAABNQAECn8oAAMRAAgKIBNjDQBmAQARAAgKIBNjDQBmAQAiAAEK6AOlTQAcAAAAAA==.Kelinn:BAAANQAECgQICAAAAA==.Kelzier:BAAANQAECgUIDgABNQAECgkJJQADADAhAA==.Kenthel:BAABNQAECn8gAAMjAAkKzRbhGgAAAgAjAAgKJxbhGgAAAgATAAQKLBqScADuAAAAAA==.Kenthels:BAAANQAECgQIBgABNQAECgkJIAAjAM0WAA==.Kezt:BAAANQAECgIIAgABNQAECgUIBgANAAAAAA==.',
Ki='Kikspally:BAAANQAECgEIAQAAAA==.Kiplander:BAABNQAECn8rAAMBAAYKUxM3WwBmAQABAAYKUxM3WwBmAQAYAAEKAABBZQAqAAAAAA==.Kiplandr:BAAANQAECgMIAwAAAA==.Kitheryn:BAAANQAECgcICQAAAA==.',
Kl='Klitt:BAAANQAECgQIBAAAAA==.',
Ko='Komosky:BAACNQAFFH8fAAIbAAcKrAfSAQBVAQAbAAcKrAfSAQBVAQA1AAQKfy4AAhsACgqYFnMgACoCABsACgqYFnMgACoCAAE1AAQKBAgEAA0AAAAA.Konas:BAAANQADCggICAABNQAECgkJLQASAH8fAA==.Korry:BAAANQAECgQICgAAAA==.Kortanis:BAABNQAECn8WAAILAAYKzwKzBwH3AAALAAYKzwKzBwH3AAAAAA==.',
Kr='Krakìn:BAAANQAECgQICgAAAA==.',
Ku='Kush:BAABNQAECn8dAAQHAAgKiBWpDQAeAgAHAAgKgROpDQAeAgAGAAUKigs43wALAQAWAAEKAAAMLwA4AAAAAA==.',
Ky='Kyana:BAAANQADCgYICgAAAA==.Kyrianna:BAAANQAECgQICAAAAA==.Kyäk:BAAANQAECgUICAAAAA==.',
['Kü']='Küngfury:BAAANQADCgUIBQAAAA==.',
La='Laerik:BAAANQADCgEIAQAAAA==.Lamunå:BAAANQADCgEIAQAAAA==.Landissa:BAABNQAECn8bAAIjAAgKdBO9GAAVAgAjAAgKdBO9GAAVAgAAAA==.Larcenciel:BAAANQAECgUIDQAAAA==.Larryholmes:BAAANQADCgEIAQABNQADCggICAANAAAAAA==.',
Le='Leen:BAAANQABCgYICQAAAA==.Letmehelpyou:BAABNQAECn8jAAIKAAkKdR+VNQCJAgAKAAkKdR+VNQCJAgAAAA==.',
Li='Licky:BAAANQAECggIEgAAAA==.Lightninfury:BAAANQADCgEIAQAAAA==.Lihan:BAABNQAECn8dAAIUAAcKmxTYBgAuAQAUAAcKmxTYBgAuAQAAAA==.Lilieth:BAAANQADCggIDAAAAA==.Lily:BAABNQAECn9BAAIQAAoKph9WAQCgAgAQAAoKph9WAQCgAgAAAA==.Lively:BAABNQAECn8XAAMeAAYKXxOYNQB3AQAeAAYKXxOYNQB3AQAFAAIKjRDv6ABrAAAAAA==.',
Lo='Lockedtoit:BAAANQAECgIIAgAAAA==.Loveg:BAAANQADCgYIBwAAAA==.Loverocket:BAABNQAECn80AAISAAkKdx7fAQBPAgASAAkKdx7fAQBPAgAAAA==.',
Lu='Luna:BAAANQAECgUIBQABNQAECgYICgANAAAAAA==.Lunastorm:BAAANQADCgQIBQAAAA==.',
Ly='Lyshia:BAABNQAECn8+AAMMAAoK8h6cOwAQAwAMAAoK7h6cOwAQAwAVAAMKuh6iCAADAQAAAA==.',
['Lí']='Líghthand:BAABNQAECn8WAAMSAAgKChp1HAAIAgASAAgKChp1HAAIAgADAAEK/wGj3AETAAAAAA==.',
['Lý']='Lýght:BAAANQADCgcIDQAAAA==.',
Ma='Magedown:BAABNQAECn8rAAMMAAkKlhVOhwBwAgAMAAkKlhVOhwBwAgAVAAEKkAVZUwAfAAAAAA==.Magician:BAAANQADCggICAAAAA==.Malare:BAAANQADCgEIAQAAAA==.Mamachula:BAAANQADCgYIDgAAAA==.Manapali:BAAANQAECgUICQABNQAECgoKOQAPAJkdAA==.Mandos:BAAANQAECgEIAQAAAA==.Manpumper:BAAANQAECgYICgAAAA==.Margor:BAAANQAECgYIEwABNQAECggIIgAdAD8XAA==.Mariella:BAAANQAECgcIDAAAAA==.Mattdemon:BAABNQAECn8/AAMZAAoKaR2nAgB/AgAZAAoKaR2nAgB/AgAEAAcKuxKuNQCWAQAAAA==.',
Me='Meanzy:BAAANQADCgQIBAAAAA==.Meatsack:BAAANQADCgMIAwAAAA==.Meliany:BAAANQAECgYICwAAAA==.Meliorate:BAACNQAFFH8JAAMBAAQKbANGHAC4AAABAAMKbANGHAC4AAARAAIKMgPxFQBFAAA1AAQKfygAAwEACgpmEww5ACcCAAEACQrKFAw5ACcCABEACAqCD2cVABcBAAAA.Meowch:BAABNQAECn8tAAIiAAoKKh0MBABVAwAiAAoKKh0MBABVAwAAAA==.Meríin:BAAANQADCgEIAQAAAA==.',
Mi='Mikachu:BAABNQAECn9UAAIPAAoKZCU1AABEAwAPAAoKZCU1AABEAwABNQAFFAYIEAADAFEaAA==.Miksi:BAAANQADCgYIEAABNQAECgIIAQANAAAAAA==.Miniwizko:BAAANQADCgEIAQAAAA==.Miradele:BAABNQAECn8kAAIRAAcKrwekGgDvAAARAAcKrwekGgDvAAAAAA==.Miraxx:BAAANQAECgEIAQAAAA==.Misscleö:BAABNQAECn8bAAIDAAgKeBZ+hgAaAgADAAgKeBZ+hgAaAgAAAA==.Miyoshi:BAABNQAECn8sAAIjAAkKngllIADLAQAjAAkKngllIADLAQAAAA==.',
Mo='Mobius:BAAANQABCgIIBQAAAA==.Monoka:BAAANQAECgEIAQAAAA==.Moonshíne:BAAANQADCgIIAwAAAA==.Moosakka:BAABNQAECn83AAIkAAkKcBKrGQDlAQAkAAkKcBKrGQDlAQAAAA==.Moosesiah:BAAANQADCgEIAQABNQAECgkJLQAkALQYAA==.Moovinthru:BAAANQAECgIIAgAAAA==.Moraxes:BAAANQAECgUIBgAAAA==.Mordenkainen:BAAANQAECgUIDAAAAA==.Morgax:BAABNQAECn8jAAQdAAoKnhTRRwBXAgAdAAkKIhXRRwBXAgAKAAkK/hfUSgA4AgAPAAEKqwPINgA0AAAAAA==.Morgona:BAAANQADCgUICQAAAA==.Morphidmage:BAAANQADCgUIBQAAAA==.Motoko:BAAANQAECgEIAQAAAA==.Motolei:BAAANQADCgUIBQABNQAECgoKPQALALoYAA==.',
Mu='Muaadib:BAABNQAECn8UAAIYAAgKThfvEgA0AgAYAAgKThfvEgA0AgABNQAECgoKPQALALoYAA==.',
My='Mydin:BAABNQAECn8iAAIDAAoKQRJxmwDsAQADAAoKQRJxmwDsAQAAAA==.Myssaphra:BAACNQAFFH8JAAIKAAMKJRofCgDeAAAKAAMKJRofCgDeAAA1AAQKfysAAwoACQomGz8wAKACAAoACQomGz8wAKACAB0AAQoAAORLASgAAAAA.',
['Mì']='Mìsawa:BAABNQAECn8eAAMGAAkKFQsKpQCKAQAGAAgKxAoKpQCKAQAHAAQKBwg5QQC+AAAAAA==.',
Na='Nakai:BAABNQAECn8uAAILAAoKZhv8JwD4AgALAAoKZhv8JwD4AgAAAA==.Nasatra:BAAANQADCggIGAAAAA==.Nastijiggle:BAABNQAECn8bAAIeAAoKVBfWIAAyAgAeAAoKVBfWIAAyAgAAAA==.Nazrien:BAAANQADCgEIAQAAAA==.Nazrion:BAAANQADCgEIAQAAAA==.',
Nc='Nc:BAABNQAECn8XAAIYAAgK1x9hCgDKAgAYAAgK1x9hCgDKAgAAAA==.',
Ne='Nexxa:BAABNQAECn8oAAILAAgKkgtNjQDvAQALAAgKkgtNjQDvAQAAAA==.',
Ni='Nightfall:BAAANQAECggICAAAAA==.Nightshadow:BAAANQADCgQIBAAAAA==.Nightsongs:BAAANQADCgEIAQAAAA==.Niqkle:BAABNQAECn8vAAMKAAoKEBW3cQC3AQAKAAkKEhS3cQC3AQAdAAgK0BMbGwBQAQAAAA==.Nitebane:BAABNQAECn8cAAITAAgKRQq1QADJAQATAAgKRQq1QADJAQAAAA==.',
No='Nohurtscooby:BAAANQAECgIIAQAAAA==.Notadh:BAAANQADCggIEAAAAA==.Notadruid:BAAANQADCgQIBQAAAA==.Notawrlock:BAAANQAECgEIAQABNQAFFAUICAABAIUdAA==.',
Ns='Nstagatr:BAABNQAECn8dAAIXAAcKZwRpRwAhAQAXAAcKZwRpRwAhAQAAAA==.',
Ny='Nyxandria:BAAANQADCgEIAQAAAA==.Nyxi:BAAANQADCgEIAgAAAA==.',
['Né']='Nécrömancer:BAAANQADCgMIAwAAAA==.',
Oa='Oak:BAAANQAECgIIAwAAAA==.',
Oc='Occidius:BAAANQAECgYIEAAAAA==.',
Ol='Olari:BAAANQAECgEIAQAAAA==.Oldfox:BAAANQAECgIIAwAAAA==.Oldoriel:BAAANQADCgYIDQAAAA==.Olehanna:BAABNQAECn89AAIDAAkKjQ6EKQCDAQADAAkKjQ6EKQCDAQAAAA==.Olestrid:BAAANQADCggIMwABNQAECgkJPQADAI0OAA==.',
On='Oni:BAAANQADCgYICgAAAA==.',
Op='Opioid:BAAANQAECgMIAwAAAA==.Opsec:BAAANQAECgIJAgABNQAECgcIHAAEAM4WAA==.Opsèc:BAABNQAECn8cAAIEAAcKzhaGLwDGAQAEAAcKzhaGLwDGAQAAAA==.',
Or='Oriicc:BAAANQAECgEIAQAAAA==.Orsa:BAAANQADCggICAAAAA==.',
Pa='Pallywalnuts:BAAANQAECgEIAQAAAA==.',
Pe='Peachcider:BAEANQAECgMIBgABNQAFFAcIIAAKAOsdAA==.Peachshock:BAECNQAFFH8gAAMKAAcK6x1AAgCLAgAKAAcK6x1AAgCLAgAdAAMKSA9dHADeAAA1AAQKfyEAAwoACgqHIw4KAHEDAAoACgqHIw4KAHEDAB0ABApaIQ6pAEIBAAAA.Peachyknight:BAAANQAECgQIBAAAAA==.Peebee:BAAANQAECgMIAwABNQAECgkJWgAJAOAjAA==.Perfectlock:BAABNQAECn8oAAIGAAoKTRcyQQCPAgAGAAoKTRcyQQCPAgAAAA==.Peri:BAAANQAECgMIAwAAAA==.',
Pi='Pigog:BAABNQAECn8YAAILAAcKnAQ7wgB+AQALAAcKnAQ7wgB+AQAAAA==.',
Po='Pooskbuddy:BAAANQADCgcIDgAAAA==.Popcorners:BAAANQADCggIDwABNQAECgoKKgAPAF8iAA==.Pordgio:BAAANQAECggIDwAAAA==.Pozzi:BAAANQAECggIDAAAAA==.',
Pr='Praypal:BAAANQADCgQIBAAAAA==.Primoss:BAAANQADCgYIBgABNQAECgcIHAAEAM4WAA==.',
Ps='Psuedolus:BAAANQAECgUIDwAAAA==.Psålm:BAABNQAECn8tAAIeAAkKzhg9FwCeAgAeAAkKzhg9FwCeAgAAAA==.',
Pu='Pulshadow:BAACNQAFFH8RAAIeAAUKMBQRBwCpAQAeAAUKMBQRBwCpAQA1AAQKfyoAAh4ACgrtIn8JAEcDAB4ACgrtIn8JAEcDAAAA.Pumah:BAAANQAECgEIAQAAAA==.',
Qt='Qtclaps:BAAANQADCggIIwAAAA==.',
Qu='Quartzecoatl:BAAANQADCgUIDAAAAA==.',
Ra='Raahhzi:BAAANQADCgYIBwAAAA==.Raamen:BAAANQAECgIIAQAAAA==.Raellia:BAABNQAECn88AAQHAAkKDxFtCgB3AAAGAAcKXA/3YADAAAAHAAMKLRFtCgB3AAAWAAEKTghLMQAyAAAAAA==.Raimmey:BAAANQAECgQIBAAAAA==.Rajia:BAAANQAECgIJAgABNQAECggIJQAHAE8HAA==.Ralune:BAABNQAECn8kAAIBAAgKiweYJQDPAAABAAgKiweYJQDPAAAAAA==.Randomshaman:BAAANQADCgUIBgAAAA==.Ranes:BAABNQAECn9AAAMjAAkKsh2KAwAiAgATAAgKbR2TGQCwAgAjAAkKqxaKAwAiAgAAAA==.Ranlin:BAAANQADCgEIAQAAAA==.Razagual:BAAANQAECggIEgABNQAECggIBgANAAAAAA==.',
Re='Redback:BAAANQADCgEIAQAAAA==.Redxelementz:BAABNQAECn8+AAIKAAoKgSaYAADnAwAKAAoKgSaYAADnAwAAAA==.Redxpastakan:BAAANQADCgUIBgABNQAECgoKPgAKAIEmAA==.Redxyara:BAABNQAECn8XAAIGAAoKDhyLCgAAAgAGAAoKDhyLCgAAAgAAAA==.Renasen:BAABNQAECn8kAAIJAAgKPiEDNgDqAgAJAAgKPiEDNgDqAgAAAA==.Renayra:BAAANQADCgEIAQAAAA==.Reno:BAABNQAECn8mAAMCAAgK4xjeTQAzAgACAAgK4xjeTQAzAgADAAcKDg/8vwCcAQAAAA==.Replacegamy:BAAANQAECgQICQABNQAFFAUICAABAIUdAA==.Resiretha:BAABNQAECn8WAAMGAAgK8ANf0QAnAQAGAAgK3gNf0QAnAQAHAAIK6AKZawBJAAAAAA==.Revelynn:BAABNQAECn8yAAMcAAoK/xY5DAAEAgAEAAgK/hlnHAByAgAcAAoKuRE5DAAEAgAAAA==.Rexkwondo:BAAANQAECgQJBAAAAA==.',
Rh='Rhyssyn:BAAANQADCgUIBQAAAA==.',
Ri='Rilerich:BAAANQAECgEIAQAAAA==.Rivliam:BAABNQAECn8bAAMHAAgKyw4LJABSAQAGAAgKAQpzoACVAQAHAAYKIw4LJABSAQAAAA==.Rizzn:BAAANQAECgMIBAABNQAECgkJIAAjAM0WAA==.',
Ro='Rook:BAAANQAECgIIAgAAAA==.Rooxxy:BAABNQAECn8ZAAMMAAcKoBdgwgD/AQAMAAcKoBdgwgD/AQAVAAEK5QiGTwAoAAAAAA==.Rotawna:BAAANQADCgcIIAAAAA==.Roxxyyzz:BAAANQAECgQICAABNQAECgcIGQAMAKAXAA==.Roûge:BAAANQAECgMIAwABNQAECgkJWgAJAOAjAA==.',
Ru='Rumikang:BAAANQADCgIIAwABNQAECgkJPAAHAA8RAA==.',
Ry='Rybeorn:BAAANQAECgEIBAAAAA==.Rynoh:BAAANQAECgcIEAAAAA==.Rythrik:BAABNQAECn8XAAMCAAoK4Q22bQDOAQACAAoK4Q22bQDOAQADAAIKMguYdQFnAAAAAA==.',
Sa='Sainted:BAACNQAFFH8aAAICAAcKPxi3AwBXAgACAAcKPxi3AwBXAgA1AAQKfzIAAwIACgraGe8EAJACAAIACgraGe8EAJACAAMABwqAFMPNAIABAAAA.Samarri:BAAANQADCgEIAQABNQAECgoKMgAbADgSAA==.Sanoks:BAABNQAECn8tAAMSAAkKfx/SCQD/AgASAAkKfx/SCQD/AgADAAIKbQZJjQFHAAAAAA==.Sanokz:BAAANQAECgIIBQABNQAECgkJLQASAH8fAA==.Santar:BAAANQADCgcIBwAAAA==.Sassafraz:BAAANQADCggICQABNQAECgkJNAASAHceAA==.Savira:BAABNQAECn8cAAIRAAcK0A5cNgBpAQARAAcK0A5cNgBpAQAAAA==.',
Sc='Scaleorva:BAABNQAECn8hAAMIAAcKSRDkBQApAQAIAAcKSRDkBQApAQAlAAQKiQhbGgCbAAAAAA==.Scarlit:BAAANQAECgEIAQAAAA==.',
Se='Sentharis:BAAANQADCggIDgAAAA==.Seraphìm:BAABNQAECn8kAAIDAAkKeQig1wBsAQADAAkKeQig1wBsAQAAAA==.Seïnaru:BAAANQAECgQIBwAAAA==.',
Sh='Shadenova:BAAANQADCgUIBgABNQAECggIJAAMAFIRAA==.Shadezilla:BAAANQADCgYIBgABNQAECggIJAAMAFIRAA==.Shadostalkrr:BAAANQAECgYIBgABNQAFFAUICAABAIUdAA==.Shadowpath:BAAANQADCgEIAgAAAA==.Shadowypete:BAAANQAECgUIBQAAAA==.Shadyballs:BAABNQAECn8kAAQMAAgKUhFsKQB0AQAMAAgKUhFsKQB0AQAmAAMKVw/JBwC1AAAVAAIKeAyqNABoAAAAAA==.Shakypete:BAAANQAECgUIDAABNQAECgYIKwABAFMTAA==.Shamken:BAAANQADCgYIBwAAAA==.Shamysosa:BAABNQAECn8iAAMdAAgKPxeEDwCYAQAdAAgKPxeEDwCYAQAKAAEKMBJCGgE3AAAAAA==.Shiionknow:BAAANQADCgQIBAAAAA==.Shinjí:BAABNQAECn8fAAIQAAkKYRy9IQDAAgAQAAkKYRy9IQDAAgABNQAFFAcIFQAQAAIVAA==.Shizens:BAAANQAECgEIAQAAAA==.Shmob:BAAANQAECgEIAgAAAA==.Shnappz:BAABNQAECn8mAAMGAAcKkghlSwDxAAAGAAcKkghlSwDxAAAHAAEKbQLLhgAhAAAAAA==.Shwillarou:BAABNQAECn83AAIQAAgKcQ5yWgCmAQAQAAgKcQ5yWgCmAQAAAA==.Shádôws:BAAANQADCgYICwAAAA==.',
Si='Silmarilidan:BAAANQAECgEIAQAAAA==.Sinergee:BAAANQAECgcIDwAAAA==.Sinnj:BAAANQADCgcIDQAAAA==.Sinona:BAAANQADCgQIBAAAAA==.Sipholice:BAAANQAECgEIAQABNQAECgQIEQANAAAAAA==.',
Sk='Skinsey:BAAANQAECgEIAQAAAA==.Skinzey:BAAANQAECgUICAAAAA==.Skinzy:BAAANQAECgEIAQAAAA==.Skycrush:BAAANQADCgUICQAAAA==.',
Sl='Slanie:BAABNQAECn8cAAIFAAcKTwdumwBDAQAFAAcKTwdumwBDAQAAAA==.Slingerz:BAABNQAECn8/AAMnAAoKVBcaAgD8AQAnAAoKVBcaAgD8AQAUAAEKAABtOQAjAAAAAA==.Slingr:BAAANQADCgcIBwAAAA==.',
Sm='Smalldragon:BAAANQAECggICgAAAA==.Smoky:BAABNQAECn8jAAQGAAoKlBo7TABvAgAGAAkK/hk7TABvAgAWAAMKahE0GwCpAAAHAAEKURYEbwBBAAAAAA==.',
Sn='Sneakpastya:BAAANQADCgIIAwAAAA==.Sneakyg:BAABNQAECn8ZAAIjAAcKjxLJHQD4AAAjAAcKjxLJHQD4AAABNQAECgkJJQADADAhAA==.Snoochie:BAABNQAECn8iAAIdAAgK9xPnYgD4AQAdAAgK9xPnYgD4AQAAAA==.',
So='Sol:BAACNQAFFH8OAAIhAAUKOx3oAACsAQAhAAUKOx3oAACsAQA1AAQKfzwAAiEACgqyI8QAAKYDACEACgqyI8QAAKYDAAAA.Solkar:BAAANQAECgMIAwABNQAECgoKMAAOAHMbAA==.Sollis:BAABNQAECn8XAAIMAAYKGgMbWgH8AAAMAAYKGgMbWgH8AAAAAA==.Sonastii:BAAANQADCgYIBgABNQAECgoKGwAeAFQXAA==.Soulcoil:BAAANQAECgQICQABNQAECgUIDwANAAAAAA==.Soulfury:BAAANQABCgUIBgABNQAECgUIDwANAAAAAA==.Soulreaper:BAAANQAECgUIDwAAAA==.Soulshock:BAAANQAECgQICQABNQAECgUIDwANAAAAAA==.Soulstorm:BAAANQADCgYIBgABNQAECgUIDwANAAAAAA==.',
Sp='Sparnak:BAABNQAECn8pAAIMAAgK5gKEdwDPAAAMAAgK5gKEdwDPAAAAAA==.Spawntier:BAAANQADCgUIBQABNQADCggICAANAAAAAA==.Spazzchel:BAAANQADCggIIAAAAA==.Spiritbox:BAACNQAFFH8KAAIKAAYKdRqIBwDgAQAKAAYKdRqIBwDgAQA1AAQKfyMAAgoACQqxJJINAFQDAAoACQqxJJINAFQDAAE1AAQKCQkbAAUAIB4A.Spruce:BAAANQADCggINQAAAA==.Sprucemoose:BAAANQADCgYIDQABNQADCggIGAANAAAAAA==.',
St='Stahlman:BAABNQAECn83AAMKAAkKZBdEDQD3AQAKAAkKZBdEDQD3AQAdAAIK+AbwGgFaAAAAAA==.Stalpho:BAABNQAECn8wAAIUAAoKsRZdBgCmAgAUAAoKsRZdBgCmAgAAAA==.Starblessed:BAAANQAECgEIAQABNQAECggIGwAKAI0FAA==.Starflare:BAAANQADCgUIBgABNQAECggIGwAKAI0FAA==.Starkind:BAABNQAECn8bAAIKAAgKjQUSpAAsAQAKAAgKjQUSpAAsAQAAAA==.Starliner:BAABNQAECn8qAAIPAAoKXyLuAACiAgAPAAoKXyLuAACiAgAAAA==.Stasis:BAAANQAECgUICAABNQAECgkJGwAFACAeAA==.Stealbreath:BAAANQADCggICgAAAA==.Stormyknight:BAAANQADCgUICQAAAA==.Strahd:BAAANQADCgYIFAAAAA==.Styrke:BAAANQADCgYIBgAAAA==.Styrmir:BAAANQAECgQIBAAAAA==.',
Su='Subza:BAABNQAECn8/AAMMAAoKwBb0CwARAgAMAAoKwBb0CwARAgAVAAEK1RPGQwA8AAAAAA==.',
Sw='Swagadin:BAAANQADCgcIBwABNQAECggIEQANAAAAAA==.Swagikal:BAAANQAECggIEQAAAA==.Swagtistic:BAAANQAECgcICAAAAA==.',
Ta='Tahra:BAAANQADCgcICgAAAA==.Taliss:BAABNQAECn81AAIFAAoKDx1SAwAMAwAFAAoKDx1SAwAMAwAAAA==.Tankmedaddy:BAABNQAECn8yAAMbAAoKOBLyBADFAQAbAAoKOBLyBADFAQAkAAQKSxejLwDsAAAAAA==.Tappuccino:BAAANQAECgUICQAAAA==.Taras:BAACNQAFFH8HAAIJAAIKNRAVKQCzAAAJAAIKNRAVKQCzAAA1AAQKfykAAwkACgqiJNREALsCAAkACQoDJNREALsCABQABgqKGJoQAJwBAAAA.Taraxist:BAABNQAECn8hAAIHAAgK0BzrBQCzAgAHAAgK0BzrBQCzAgAAAA==.Tautology:BAABNQAECn8aAAIeAAkKQRS6HABeAgAeAAkKQRS6HABeAgAAAA==.Tazajin:BAAANQAECgEIAQAAAA==.',
Tc='Tchala:BAABNQAECn8lAAIDAAkKMCFjPgDaAgADAAkKMCFjPgDaAgAAAA==.Tchallah:BAAANQAECgYICQAAAA==.Tchaumb:BAAANQADCgEIAQAAAA==.',
Td='Tdog:BAAANQADCgcJBwAAAA==.',
Te='Teacup:BAAANQADCgYIBgABNQAECggIFwAYANcfAA==.Teks:BAABNQAECn8dAAMCAAgKtBfYUwAeAgACAAgKtBfYUwAeAgASAAYKKRgFMABeAQAAAA==.Teksara:BAAANQAECgQIAwABNQAECggIHQACALQXAA==.Teksynoth:BAAANQADCgQIBAABNQAECggIHQACALQXAA==.Telian:BAAANQADCgUIBQAAAA==.Terracustode:BAAANQABCgIJAgAAAA==.Teth:BAABNQAECn8aAAMHAAcKDBLoDgAMAgAHAAcKDBLoDgAMAgAGAAEKAADCVwEgAAAAAA==.Tevildo:BAAANQADCgEIAQAAAA==.',
Th='Thaine:BAABNQAECn8/AAIDAAoKKyPtAQAaAwADAAoKKyPtAQAaAwAAAA==.Theoalthor:BAAANQAECgMIAgAAAA==.Theundeadone:BAABNQAECn8xAAIeAAoKIhw0CwAxAwAeAAoKIhw0CwAxAwAAAA==.Thndrwzrd:BAAANQAECgQICAAAAA==.Thorphan:BAABNQAECn86AAQPAAoKXiOxAQCeAwAPAAoKXiOxAQCeAwAdAAUKARefuAAhAQAKAAUKcAu3zwDIAAAAAA==.',
Ti='Ticho:BAAANQAECgQIBgAAAA==.',
To='Torez:BAAANQAECgUICQABNQAECgoKPwAZAGkdAA==.Torodisilis:BAAANQAECgUICwABNQAECgkJJQADADAhAA==.Tosic:BAAANQADCgEIAQAAAA==.Toxicavenger:BAAANQAECggIDAAAAA==.',
Tr='Treygec:BAAANQAECgUIBwAAAA==.Tribolonotus:BAAANQAECgMIBAAAAA==.Trickette:BAAANQADCgcICAABNQAECggIDwANAAAAAA==.Trilleong:BAAANQAECgEIAQAAAA==.Trina:BAAANQADCggICQAAAA==.Trisilla:BAAANQADCggIFQABNQAECgkJLAAoAIQNAA==.Troubleshot:BAAANQAECggICAAAAA==.Trujal:BAABNQAECn8kAAIOAAgKuxkILwBXAgAOAAgKuxkILwBXAgAAAA==.',
Tu='Turdmonk:BAABNQAECn9GAAIbAAoKbSALAwAUAgAbAAoKbSALAwAUAgAAAA==.',
Ty='Tylandon:BAAANQADCgEIAgAAAA==.Tyndal:BAAANQADCgcIDwAAAA==.Typhon:BAABNQAECn8xAAMeAAoK3xqyGACMAgAeAAkKTxqyGACMAgAFAAYKviBKVgAgAgAAAA==.',
Tz='Tzaim:BAAANQADCggIDgAAAA==.',
Un='Unclebób:BAAANQADCgYIDAABNQAECgUICAANAAAAAA==.Unshady:BAAANQADCggIDgABNQAECggIJAAMAFIRAA==.',
Va='Vaeshta:BAABNQAECn8jAAIPAAcKXAPQEwDNAAAPAAcKXAPQEwDNAAAAAA==.Vaku:BAAANQAECgEIAQAAAA==.Valhallarama:BAABNQAECn8qAAIKAAoKKRtEQABfAgAKAAoKKRtEQABfAgAAAA==.Valika:BAAANQADCgEIAQAAAA==.Vampy:BAAANQAECgQIBAAAAA==.Vandragon:BAAANQADCggIHAAAAA==.Vannida:BAAANQAECgMIBgAAAA==.Vardanis:BAAANQAECgQIBAABNQAECgcIIQAaAEMaAA==.',
Ve='Vengencedawg:BAABNQAECn8oAAIDAAoKFAgzwACcAQADAAoKFAgzwACcAQAAAA==.Vexxya:BAAANQADCgQIAwAAAA==.',
Vl='Vladus:BAABNQAECn8wAAIOAAoKcxu3CACtAQAOAAoKcxu3CACtAQAAAA==.',
Vo='Voltroñ:BAAANQADCgMIAwABNQAFFAQIEQAMAHEZAA==.Voodoo:BAAANQAECgQIBAAAAA==.',
Vs='Vsegda:BAAANQAECgcIDgABNQAFFAMICQAKACUaAA==.',
Vy='Vyllian:BAABNQAECn8pAAIOAAgKtQ8ZUgCsAQAOAAgKtQ8ZUgCsAQAAAA==.',
Wa='Wangwang:BAAANQAECgMIBAAAAA==.Wardrag:BAAANQABCgQIBAAAAA==.Wareshesh:BAAANQADCgUIBQAAAA==.Warlakaflaka:BAABNQAECn8UAAQWAAYKbRNQDQCGAQAWAAYKbRNQDQCGAQAHAAMKYQhIUACPAAAGAAEKAAB4RAEyAAABNQAECggIJAAMAFIRAA==.',
Wh='Whale:BAABNQAECn8WAAInAAkKJRuVDABrAgAnAAkKJRuVDABrAgAAAA==.',
Wi='Wickðaddy:BAAANQADCgEIAQAAAA==.Windfury:BAABNQAECn8jAAIPAAoKExFtFQARAgAPAAoKExFtFQARAgAAAA==.Windfuryous:BAAANQADCgUICQAAAA==.Winston:BAAANQADCggIJQAAAA==.',
Wo='Wolfsbane:BAAANQADCgYIBgAAAA==.Wonpiece:BAAANQAECgYIEAABNQAFFAQICQABAGwDAA==.',
Wu='Wulfnir:BAAANQADCgcIBwAAAA==.',
Wy='Wylestrean:BAABNQAECn8nAAILAAoKDB5BMgDVAgALAAoKDB5BMgDVAgAAAA==.',
Xa='Xanokz:BAAANQADCgEIAgABNQAECgkJLQASAH8fAA==.Xarytha:BAAANQADCgEIAQABNQAECggIEAANAAAAAA==.',
Xi='Xiaomao:BAAANQADCgcICAABNQAECgEIAQANAAAAAA==.',
Xy='Xyrathul:BAAANQAECggICgAAAA==.',
Ye='Yeinn:BAABNQAECn9aAAMJAAkK4CPOBgBaAgAJAAkK4CPOBgBaAgAUAAUKuiE2DQDkAQAAAA==.',
Za='Zandalarthas:BAABNQAECn8hAAIOAAcK0haMGwAVAQAOAAcK0haMGwAVAQAAAA==.Zanthor:BAAANQADCgcIBwABNQAECgoKMgAbADgSAA==.Zarbok:BAAANQADCgQIBAABNQAECggIIgAdAD8XAA==.Zarred:BAAANQADCgEIAQAAAA==.',
Zc='Zcredo:BAABNQAECn86AAIJAAoK/h9CBQCFAgAJAAoK/h9CBQCFAgAAAA==.',
Ze='Zel:BAAANQAECgQIBgAAAA==.Zentradei:BAAANQADCgQIBAAAAA==.Zephariel:BAAANQADCggIGgAAAA==.Zerus:BAAANQADCgEIAQAAAA==.',
Zi='Ziconik:BAAANQADCgYIBgAAAA==.Zieganfuss:BAAANQAECggIEAAAAA==.Zilly:BAAANQADCgEIAQAAAA==.Zinrozlek:BAABNQAECn8dAAIOAAcK5wWYegAOAQAOAAcK5wWYegAOAQAAAA==.',
Zo='Zoho:BAABNQAECn8sAAIoAAkKhA0IEwCzAQAoAAkKhA0IEwCzAQAAAA==.Zorrander:BAAANQADCgQIBAABNQAECgQIBAANAAAAAA==.',
Zy='Zynvar:BAAANQADCggICAAAAA==.',
['Ðj']='Ðjay:BAAANQADCgEIAQAAAA==.',
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
