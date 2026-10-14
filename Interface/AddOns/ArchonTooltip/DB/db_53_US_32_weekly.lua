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

local lookup = {'Druid-Balance','DemonHunter-Devourer','Priest-Holy','Warlock-Demonology','Warlock-Destruction','Evoker-Devastation','Paladin-Retribution','Shaman-Restoration','Hunter-BeastMastery','Unknown-Unknown','DeathKnight-Blood','Shaman-Enhancement','DeathKnight-Unholy','Mage-Arcane','Druid-Restoration','Paladin-Protection','Warrior-Arms','Rogue-Assassination','Warrior-Fury','Warlock-Affliction','Hunter-Marksmanship','Druid-Guardian','Paladin-Holy','Mage-Frost','DemonHunter-Havoc','Priest-Discipline','Monk-Windwalker','DemonHunter-Vengeance','Shaman-Elemental','Priest-Shadow','Hunter-Survival','Evoker-Preservation','Rogue-Outlaw','Druid-Feral','Rogue-Subtlety','Monk-Mistweaver','Evoker-Augmentation','Mage-Fire','Warrior-Protection','Monk-Brewmaster',}
local provider = {region='US',realm='Blackhand',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Absorbency:BAAANQAECgYICAABNQAFFAMICAABAGwDAA==.',
Ae='Aeris:BAAANQAECgUIEQAAAA==.Aethwyn:BAAANQAECgUIDAAAAA==.',
Ag='Agandaur:BAAANQAECgQICAAAAA==.',
Ah='Ahnkala:BAAANQAECgIIAgAAAA==.',
Ai='Aigirlfriend:BAABNQAECn83AAICAAgKDBMkKAD/AQACAAgKDBMkKAD/AQAAAA==.Aimdablame:BAAANQAECgMIAwAAAA==.',
Al='Allupcreepy:BAABNQAECn8eAAIDAAcK5BTqdAC4AQADAAcK5BTqdAC4AQAAAA==.',
Am='Amalyndi:BAAANQAECgcIDQAAAA==.Ambewlance:BAABNQAECn8bAAMEAAkKkRVqhADWAQAEAAcK9BRqhADWAQAFAAMKHxWpPQDKAAAAAA==.Amethystra:BAABNQAECn8eAAIGAAgKqgakHgBmAQAGAAgKqgakHgBmAQAAAA==.Amlu:BAAANQAECgYIBwABNQAECgkJIwAHADAhAA==.Amorathon:BAAANQADCgMIAwAAAA==.',
An='Andaconda:BAAANQAECgYIDQAAAA==.Annimosity:BAAANQAECgEIAQAAAA==.Ansem:BAAANQAECgEIAQAAAA==.Anthesis:BAAANQAECgUIDAABNQAFFAMIBgAIALMZAA==.Anúbis:BAAANQADCggIFQAAAA==.',
Ap='Apawllo:BAAANQAECgEIAQAAAA==.Apep:BAAANQAECgQICgAAAA==.Apostle:BAABNQAECn8bAAIDAAkKIB55IADrAgADAAkKIB55IADrAgAAAA==.',
Ar='Aramìs:BAAANQAECgIIAgAAAA==.Arcaya:BAAANQADCggIHgAAAA==.Ariaka:BAAANQADCgEIAQAAAA==.Arleen:BAAANQAECgQIDwAAAA==.Arlida:BAABNQAECn8ZAAIIAAgK+xYuXAD3AQAIAAgK+xYuXAD3AQAAAA==.Artemys:BAABNQAECn8jAAIJAAkKyhj5QwCeAgAJAAkKyhj5QwCeAgAAAA==.Aryto:BAAANQADCgUIBQAAAA==.',
As='Ashlar:BAAANQADCgEIAQAAAA==.Asketill:BAAANQADCgYIDwAAAA==.Asmodee:BAAANQAECgYIDwAAAA==.',
Au='Aure:BAAANQADCgYIDAAAAA==.Auren:BAAANQADCgIIAgAAAA==.',
Az='Azkadellia:BAAANQABCgQJCAAAAA==.Azonya:BAAANQABCgQIBAAAAA==.',
Ba='Baaloo:BAAANQADCgYICQABNQAECgEIAQAKAAAAAA==.Bainne:BAAANQADCgUJCAAAAA==.Baitken:BAAANQAECgQICwABNQAECgcIGwALANIWAA==.Barktea:BAAANQAECgYIDwAAAA==.Batharel:BAAANQAECgQIDwAAAA==.Battcantdps:BAAANQAECggIDwAAAA==.Battleground:BAAANQADCgMIAwAAAA==.',
Be='Bearen:BAABNQAECn8aAAIMAAkK3wO6HACSAQAMAAkK3wO6HACSAQAAAA==.Beertrain:BAABNQAECn8vAAINAAkKgBQ8OgA3AgANAAkKgBQ8OgA3AgAAAA==.Beesechurger:BAABNQAECn8ZAAIOAAgKWxtsiQBsAgAOAAgKWxtsiQBsAgAAAA==.Belladue:BAAANQADCgcIKAAAAA==.Bellezza:BAABNQAECn82AAIPAAkK0RLqIAAdAgAPAAkK0RLqIAAdAgAAAA==.Belphoebe:BAEANQABCgIIAgABNQAECgYIDQAKAAAAAA==.',
Bh='Bhikku:BAAANQAECgcIEQABNQAECgkJIwAHADAhAA==.Bhilly:BAAANQADCggIKAAAAA==.',
Bi='Bigdumbcatqt:BAABNQAECn8lAAIQAAkKfSZhAAD8AwAQAAkKfSZhAAD8AwAAAA==.Bigdumbkatqt:BAACNQAFFH8TAAILAAYKRCIzBAA5AgALAAYKRCIzBAA5AgA1AAQKfx4AAgsACQrjJiUAAAsEAAsACQrjJiUAAAsEAAAA.Bignjuicy:BAABNQAECn8bAAIRAAkKRBkqXgBvAgARAAkKRBkqXgBvAgAAAA==.Bimisi:BAABNQAECn8WAAISAAkK6g5/LwAgAgASAAkK6g5/LwAgAgAAAA==.',
Bl='Blades:BAAANQADCgMIBgAAAA==.Bloodshhot:BAABNQAECn8vAAIJAAgKJx9rJgD8AgAJAAgKJx9rJgD8AgAAAA==.Bloodthorne:BAAANQADCgcICwAAAA==.Blueragebar:BAAANQAECgUICwAAAA==.',
Bo='Bobadasmash:BAABNQAECn8nAAMRAAgK7RTrigD9AQARAAgKChTrigD9AQATAAEKvhUKLwBCAAAAAA==.Bobitt:BAAANQAECgUIBgAAAA==.Boddyknocker:BAAANQAECgYIDQAAAA==.Boombox:BAAANQADCgYIBgAAAA==.Boomvoker:BAAANQAECgEIAQABNQAFFAIIBAAKAAAAAA==.Boonerichard:BAAANQAECgQICQAAAA==.Boopdoctor:BAAANQADCgQIBAAAAA==.Bouchewager:BAAANQADCgYIBgAAAA==.',
Br='Braina:BAAANQAECgcIEwAAAA==.Brandy:BAAANQAECgUIBQABNQAECgkJKQAUAJwXAA==.Branwin:BAAANQADCgcIGwAAAA==.Braver:BAACNQAFFH8UAAIVAAYKaRJcCgCWAQAVAAYKaRJcCgCWAQA1AAQKfyoAAxUACQqbH/sUALQCABUACQqbH/sUALQCAAkAAQq4C2dWATgAAAAA.Braverwar:BAAANQAECgIIAwABNQAFFAYIFAAVAGkSAA==.Break:BAACNQAFFH8ZAAIHAAcKriWxAADgAgAHAAcKriWxAADgAgA1AAQKfyMAAgcACQp/JoQSAHwDAAcACQp/JoQSAHwDAAE1AAUUBwoZAAcAriUA.Bromungandr:BAAANQADCgYIDgAAAA==.',
Bu='Buligerent:BAAANQADCggIGAABNQAECggINwAWAAUbAA==.',
By='Bynnyy:BAAANQAECgIIAgAAAA==.',
['Bù']='Bùbbles:BAAANQAECgUIDAAAAA==.',
Ca='Cadelsaya:BAABNQAECn81AAQXAAkKcw4LWwAFAgAXAAkKcw4LWwAFAgAHAAUKEQpdJwHYAAAQAAEKAACZaAA/AAAAAA==.Camandah:BAABNQAECn8lAAIBAAkKFxMYMwBJAgABAAkKFxMYMwBJAgABNQAECgIIAQAKAAAAAA==.Cammandzar:BAAANQAECgIIAgABNQAECgIIAQAKAAAAAA==.Candy:BAAANQABCgQIAgAAAA==.Canman:BAAANQAECgEIAQAAAA==.Carlo:BAAANQAECgEIAwAAAA==.Carryout:BAAANQAECggICwAAAA==.Caskca:BAAANQADCgEIAQAAAA==.Cassei:BAAANQAECgYIDAAAAA==.Cassiell:BAAANQAECgEIAQAAAA==.Castertroy:BAABNQAECn8aAAMYAAgKnAS4GwAQAQAYAAcKRwW4GwAQAQAOAAcKpgH2eQHIAAAAAA==.',
Ce='Celenia:BAAANQAECgIIAwAAAA==.',
Ch='Chainari:BAAANQAECgIIAgAAAA==.Charmless:BAAANQADCgcIDAABNQAECgkJNgAZAKAdAA==.Chee:BAAANQAECgUIBgAAAA==.Cheeksdakota:BAAANQAECgEIAQAAAA==.Cheetopaly:BAABNQAECn8ZAAMXAAcKrRaEXwD3AQAXAAcKrRaEXwD3AQAHAAYKiwciCQEJAQAAAA==.Chuga:BAAANQAECgQIBgABNQAECgcIEgAKAAAAAA==.Chìgusa:BAABNQAECn8zAAMDAAkKqiL1BgCMAwADAAkKqiL1BgCMAwAaAAUKcxVVDwA0AQAAAA==.',
Ci='Cilenzer:BAAANQAECgMIAgABNQAECgYIKQABAFMTAA==.Circa:BAAANQADCgEIAQAAAA==.',
Cl='Clarimonde:BAAANQADCgEIAQAAAA==.Cleaveradius:BAAANQADCggICAABNQAECggIIAAIAGwfAA==.Clumonk:BAABNQAECn8bAAIbAAgKphpAGwBfAgAbAAgKphpAGwBfAgAAAA==.',
Co='Coleric:BAAANQAECgYIBgAAAA==.Convoke:BAAANQADCggIEAABNQAECgkJGwADACAeAA==.Coosar:BAAANQAECgQICAAAAA==.Coosedaplug:BAAANQADCgQIBAABNQAECgcIEgAKAAAAAA==.Cooseyloosey:BAAANQAECgcIEgAAAA==.Coosinator:BAAANQAECgYICwABNQAECgcIEgAKAAAAAA==.Cooterray:BAAANQAECgUICAAAAA==.Corellon:BAABNQAECn8bAAMHAAgK2Q5epQDQAQAHAAgK2Q5epQDQAQAQAAIKqA2BXgBdAAAAAA==.Corinth:BAAANQAECgYJEAAAAA==.',
Cr='Cratoz:BAABNQAECn8oAAIHAAgKeB51UgCaAgAHAAgKeB51UgCaAgAAAA==.Croswind:BAABNQAECn8zAAIJAAkKDRpFLwDdAgAJAAkKDRpFLwDdAgAAAA==.',
Cu='Curandero:BAAANQADCgUICAABNQAECgEIAQAKAAAAAA==.',
Cy='Cyndrine:BAACNQAFFH8HAAIcAAMKWxuOAgAJAQAcAAMKWxuOAgAJAQA1AAQKfy8AAhwACQroJYUAANcDABwACQroJYUAANcDAAAA.Cyrani:BAABNQAECn80AAMdAAkKliWYAgDeAwAdAAkKliWYAgDeAwAIAAYKrCQ5PABsAgAAAA==.',
Da='Dadipps:BAABNQAECn8hAAIIAAgKXB9FNwCAAgAIAAgKXB9FNwCAAgAAAA==.Daggumit:BAAANQADCggIGQAAAA==.Dagnei:BAAANQAECgIIAgAAAA==.Daltina:BAABNQAECn8bAAMeAAYK3RsbLQC5AQAeAAYK3RsbLQC5AQADAAUK3xNxnAA7AQAAAA==.Damage:BAAANQAECggIAgAAAA==.Dannyboone:BAAANQADCggICAABNQAECgkJKQALAGIaAA==.Dareael:BAABNQAECn8iAAIHAAgKahWudQA+AgAHAAgKahWudQA+AgAAAA==.Darklighete:BAAANQABCgEIAQAAAA==.Daurgoth:BAAANQAECggIEwAAAA==.Dazoner:BAAANQADCggIHQAAAA==.',
De='Deadbydrand:BAAANQAECggICwAAAA==.Deadrus:BAAANQAECgYIBgAAAA==.Deathndspark:BAABNQAECn8nAAILAAgKsA2HXgB1AQALAAgKsA2HXgB1AQAAAA==.Deathpuma:BAABNQAECn8mAAILAAkK4h2pFgD2AgALAAkK4h2pFgD2AgAAAA==.Deathrowe:BAABNQAECn8lAAINAAgKKB92IwCzAgANAAgKKB92IwCzAgAAAA==.Dednevoker:BAAANQAECgEIAQABNQAECggIEgAKAAAAAA==.Deelyte:BAAANQAECgIIAgAAAA==.Demonvann:BAAANQADCggICAAAAA==.Demítrá:BAAANQADCgIIAgABNQAECgkJMQAdABEcAA==.Denouncer:BAAANQAECgUICgABNQAECggIIAAIAGwfAA==.Derca:BAAANQAECgUIEgAAAA==.Dethork:BAAANQADCgcIDAAAAA==.',
Di='Dieds:BAAANQADCgYIBgABNQAECggIEgAKAAAAAA==.Dienne:BAAANQAECgEIAQAAAA==.Dietunicorn:BAAANQADCggINAABNQAECgkJPgAeADshAA==.Dinarra:BAAANQADCgUIBgAAAA==.Diosdelaluna:BAAANQADCgYICQAAAA==.Dirtybyrd:BAAANQAECgEIAQAAAA==.Disahzter:BAABNQAECn8hAAMFAAgK6Q3mIQBhAQAEAAcKJQrVrQBwAQAFAAYKlA3mIQBhAQAAAA==.',
Do='Docbledore:BAAANQAECggIDwAAAA==.Docdrood:BAAANQADCgcIBwABNQAECggIDwAKAAAAAA==.Docmonk:BAAANQAECgEIAQABNQAECggIDwAKAAAAAA==.Docpriest:BAABNQAECn8YAAIeAAcKAgxBNQB2AQAeAAcKAgxBNQB2AQABNQAECggIDwAKAAAAAA==.Donlazul:BAAANQAECgIIAQAAAA==.Dotlotto:BAAANQAECgEJAgAAAA==.',
Dr='Draconoth:BAAANQAECgYIEAAAAA==.Dragfin:BAAANQAECgEIAQAAAA==.Dragonir:BAABNQAECn8WAAIZAAgKHRBaPADPAQAZAAgKHRBaPADPAQABNQAECgkJIwAHADAhAA==.Dranddrand:BAAANQAECgcIBwAAAA==.Dreadborn:BAAANQADCgMIBAAAAA==.',
Du='Dungard:BAAANQAECgEIAQABNQAECgkJNQAXAHMOAA==.Dunstird:BAAANQAECgIIAgABNQAFFAIIBAAKAAAAAA==.',
Dy='Dyami:BAAANQAECgUIEAAAAA==.',
['Dè']='Dèadèyè:BAAANQADCggJDgAAAA==.',
Ea='Eatmorechkn:BAABNQAECn8sAAIHAAkK7BHBeQA0AgAHAAkK7BHBeQA0AgAAAA==.',
Ee='Eellonwy:BAAANQADCggIGgAAAA==.Eemerald:BAAANQAECgQICgAAAA==.',
Eg='Egna:BAABNQAECn8cAAIdAAgKgAwCbQDVAQAdAAgKgAwCbQDVAQAAAA==.',
El='Electricblu:BAAANQAECgUICAAAAA==.Elizaa:BAABNQAECn8hAAMIAAcK4RTUagDHAQAIAAcK4RTUagDHAQAdAAIKbAIAIgFFAAAAAA==.',
Em='Emaya:BAAANQAECgMIBAAAAA==.Emmadar:BAAANQAECgMIAwABNQAECggINAAEAOURAA==.',
Er='Erioch:BAAANQAECgEIAQAAAA==.',
Eu='Euripidus:BAAANQADCgEIAQAAAA==.',
Ev='Evilclared:BAAANQADCgUICgABNQAFFAQIDwARAL4gAA==.Evildean:BAAANQAECgQIBAAAAA==.',
Ex='Execute:BAAANQADCgUICQAAAA==.',
Fa='Fanya:BAAANQADCgYIBgABNQAECgkJLgAeAA4dAA==.Fathernatur:BAAANQADCgYICQAAAA==.Fatherpain:BAAANQABCgYIEQAAAA==.',
Fe='Fenrigaar:BAABNQAECn8uAAIBAAkKBh/YEwAnAwABAAkKBh/YEwAnAwAAAA==.',
Ff='Ffsa:BAABNQAECn8yAAQJAAkKJB8cMQDXAgAJAAkKXBocMQDXAgAVAAgKIh1rGgB/AgAfAAEKAADPEgA5AAAAAA==.',
Fi='Fillin:BAAANQAECgEIAQAAAA==.Filô:BAABNQAECn8ZAAIeAAkKbRuvGQB+AgAeAAkKbRuvGQB+AgAAAA==.Findinnan:BAAANQADCgUIBgAAAA==.',
Fl='Flame:BAAANQADCgQIBAAAAA==.Flanker:BAAANQADCgYIBgABNQAECggIGQAOAFsbAA==.Flintmini:BAAANQADCgQJBAAAAA==.Flossylock:BAAANQAECgUIBgAAAA==.',
Fo='Forsakenly:BAAANQADCggIEAAAAA==.',
Fr='Frasti:BAAANQAECgEIAQAAAA==.Freshstart:BAAANQAECgEIAQAAAA==.Frodes:BAAANQABCgYJBwAAAA==.Frostmage:BAABNQAECn82AAIOAAgK+xT/qAAvAgAOAAgK+xT/qAAvAgAAAA==.',
Fu='Fuegoblazeit:BAAANQABCgIIAgAAAA==.Furbucket:BAAANQAECgQICwAAAA==.Futonhunts:BAABNQAECn82AAIJAAkKoyJTDAB6AwAJAAkKoyJTDAB6AwAAAA==.',
Fy='Fylerw:BAABNQAECn8mAAICAAgK2BHOJQAUAgACAAgK2BHOJQAUAgAAAA==.',
Ga='Gailyn:BAAANQADCgYICgAAAA==.Galebb:BAAANQAECgEIAQABNQAECgUIDwAKAAAAAA==.Gardros:BAAANQABCgQIBAAAAA==.',
Gh='Ghostrideher:BAABNQAECn8fAAIJAAgKMhixRACcAgAJAAgKMhixRACcAgAAAA==.',
Gi='Gigadad:BAACNQAFFH8FAAIJAAMKHBnpFQAHAQAJAAMKHBnpFQAHAQA1AAQKfywAAgkACQonJQILAIQDAAkACQonJQILAIQDAAAA.Gigafather:BAAANQADCgQIBAAAAA==.',
Gl='Gladiuz:BAAANQAECgQIBAABNQAECgkJIwAHADAhAA==.',
Go='Gornthemonki:BAAANQADCgcICgAAAA==.Goyahokasinj:BAAANQADCgYIFwAAAA==.',
Gr='Griannee:BAABNQAECn8sAAIZAAkK6xQvKQBSAgAZAAkK6xQvKQBSAgAAAA==.Grimtoetem:BAAANQABCgYJCQAAAA==.Grislix:BAABNQAECn8pAAQUAAkKnBfqBACAAgAUAAgKHxjqBACAAgAEAAcKjw26rABzAQAFAAEKLxnGaQBMAAAAAA==.Grismistea:BAAANQAECgEIAQABNQAECgkJKQAUAJwXAA==.Grismunch:BAAANQABCggICAAAAA==.Gryffin:BAABNQAECn8dAAMYAAgKaBCgDQDSAQAYAAgKaBCgDQDSAQAOAAEKPwWaxgEyAAAAAA==.',
Gu='Guidance:BAAANQADCgcIBwAAAA==.Gulan:BAAANQADCgMIAwAAAA==.Gummies:BAAANQABCgYIDgAAAA==.',
['Gâ']='Gânk:BAABNQAECn8rAAIRAAkK+ws6jwDyAQARAAkK+ws6jwDyAQAAAA==.',
Ha='Hanrekt:BAAANQAECgUICwAAAA==.Happiness:BAABNQAECn8UAAIRAAUKmwy34wAZAQARAAUKmwy34wAZAQABNQAECgkJLAAJANIgAA==.',
He='Heavensbliss:BAAANQAECgUIBQABNQAECggINgAOAPsUAA==.Heavychevy:BAABNQAECn8YAAITAAgKSRQFDQDlAQATAAgKSRQFDQDlAQAAAA==.Hellvenger:BAAANQADCggICwAAAA==.Heriel:BAABNQAECn8XAAIOAAcKExEk7ACuAQAOAAcKExEk7ACuAQABNQAECgkJIwAHADAhAA==.Hexquisite:BAAANQAECgUIBQABNQAECgkJGwADACAeAA==.',
Hi='Hildoehealz:BAAANQAFFAEIAQAAAA==.',
Ho='Holybit:BAAANQAECgQIBgAAAA==.Homgar:BAAANQADCgMIBAAAAA==.Horrni:BAAANQADCgQIBgAAAA==.Hotsjkpurge:BAAANQADCgQIBAAAAA==.',
Hu='Humphrees:BAABNQAECn83AAISAAgKlhfGIwBlAgASAAgKlhfGIwBlAgAAAA==.',
Hy='Hydrospin:BAAANQADCgQIBAAAAA==.Hypocrisy:BAAANQADCgcIFgAAAA==.',
['Hà']='Hàtos:BAABNQAECn8fAAIOAAgKNxULpQA2AgAOAAgKNxULpQA2AgAAAA==.',
Id='Idot:BAAANQADCgUJDgABNQAECgcIIAAcAJ0FAA==.Iduni:BAAANQADCgIIAgAAAA==.',
Ii='Iironrod:BAAANQADCgUIBQAAAA==.',
Il='Illidave:BAAANQADCgYIBwABNQAECgcIGAAVAGcEAA==.',
In='Incubus:BAAANQAECgUICAABNQAECgkJIwAHADAhAA==.Inebriatas:BAAANQAECgEIAQABNQAECgcIHgAgANoiAA==.Inu:BAAANQABCgIJAgAAAA==.Invissibill:BAABNQAECn8fAAIhAAcKZwn3DQBdAQAhAAcKZwn3DQBdAQAAAA==.',
Ir='Ironbark:BAAANQADCgUICAAAAA==.Irôh:BAAANQADCgYIBgAAAA==.',
Is='Ishaa:BAAANQAFFAEIAQAAAA==.',
Iv='Ivanä:BAABNQAECn8bAAIDAAgKWBivSwA/AgADAAgKWBivSwA/AgAAAA==.',
Iz='Izax:BAABNQAECn8vAAQEAAgKCQ7skgCyAQAEAAcKQw3skgCyAQAFAAEK5xExcQA9AAAUAAEKYwbPMgAtAAAAAA==.',
Ja='Jaddzia:BAAANQABCgQIBAAAAA==.Jadestone:BAAANQAECgQIBAAAAA==.Jaguarkick:BAAANQADCggIGAAAAA==.Jamestown:BAAANQADCgYIBAAAAA==.Jarcor:BAAANQABCgQIBAAAAA==.',
Je='Jeffray:BAAANQABCgQIBAAAAA==.Jessi:BAAANQAECgcIEAAAAA==.',
Jo='Johnnyhildoe:BAAANQADCgQIBAAAAA==.Jonsneew:BAAANQADCgYICgAAAA==.',
Ju='Judgment:BAAANQADCgMIBwAAAA==.Junglefu:BAAANQADCgIIAgAAAA==.Jupitus:BAAANQAECgYICgAAAA==.Justin:BAAANQAECgUIBwABNQAECgYIBgAKAAAAAA==.',
['Jù']='Jùstin:BAAANQADCgMIAwABNQAFFAUIDgABAGQYAA==.',
['Jû']='Jûstin:BAAANQAECgYICQABNQAFFAUIDgABAGQYAA==.',
Ka='Kabroz:BAAANQAECgYIDQAAAA==.Kale:BAAANQABCgYIBwAAAA==.Karma:BAAANQAECgUIEQAAAA==.Katalania:BAABNQAECn8YAAMXAAgKgw7kiQB7AQAXAAcKxg3kiQB7AQAHAAUKGgQ/PAG4AAAAAA==.',
Ke='Keeincar:BAAANQADCgIIAgAAAA==.Keeshama:BAAANQAECgEIAQAAAA==.Kegna:BAAANQADCggIHwAAAA==.Keiwhenua:BAABNQAECn8iAAMPAAgKfxI7JgDtAQAPAAgKfxI7JgDtAQAiAAEK6AORSwAcAAAAAA==.Kelinn:BAAANQAECgQICAAAAA==.Kelzier:BAAANQAECgUIDAABNQAECgkJIwAHADAhAA==.Kenthel:BAABNQAECn8cAAMjAAcKqxaJGgABAgAjAAcKfxaJGgABAgASAAMKGRpubgDuAAAAAA==.Kenthels:BAAANQAECgIIAgABNQAECgcIHAAjAKsWAA==.Kezt:BAAANQAECgIIAgABNQAECgQIBgAKAAAAAA==.',
Ki='Kiplander:BAABNQAECn8pAAMBAAYKUxP7WQBoAQABAAYKUxP7WQBoAQAWAAEKAADOYgAqAAAAAA==.Kiplandr:BAAANQAECgIIAgAAAA==.Kitheryn:BAAANQAECgYIBwAAAA==.',
Kl='Klitt:BAAANQAECgQIBAAAAA==.',
Ko='Komosky:BAACNQAFFH8ZAAIbAAcKagWZBQC8AQAbAAcKagWZBQC8AQA1AAQKfyoAAhsACQoXFyAgACkCABsACQoXFyAgACkCAAAA.Konas:BAAANQADCggICAABNQAECgkJLQAQAH8fAA==.Korry:BAAANQAECgQICgAAAA==.Kortanis:BAAANQAECgUIEQAAAA==.',
Kr='Krakìn:BAAANQAECgQICgAAAA==.',
Ku='Kush:BAABNQAECn8dAAQFAAgKiBWVDQAfAgAFAAgKgROVDQAfAgAEAAUKiguZ3AALAQAUAAEKAACTLgA4AAAAAA==.',
Ky='Kyana:BAAANQADCgYICgAAAA==.Kyrianna:BAAANQAECgMIBAAAAA==.Kyäk:BAAANQADCgQIBAAAAA==.',
['Kü']='Küngfury:BAAANQADCgUIBQAAAA==.',
La='Laerik:BAAANQABCgEIAQAAAA==.Landissa:BAABNQAECn8bAAIjAAgKdBNzGAAWAgAjAAgKdBNzGAAWAgAAAA==.Larcenciel:BAAANQAECgUICwAAAA==.Larryholmes:BAAANQABCgQIBAABNQADCggICAAKAAAAAA==.',
Le='Leen:BAAANQABCgYICQAAAA==.Letmehelpyou:BAABNQAECn8gAAIIAAgKbB/oNACJAgAIAAgKbB/oNACJAgAAAA==.',
Li='Licky:BAAANQAECggIEgAAAA==.Lihan:BAAANQAECgYIEgAAAA==.Lilieth:BAAANQADCggIDAAAAA==.Lily:BAABNQAECn83AAINAAkKPx8MEQAtAwANAAkKPx8MEQAtAwAAAA==.Lively:BAABNQAECn8XAAMeAAYKXxMPNQB3AQAeAAYKXxMPNQB3AQADAAIKjRC35QBrAAAAAA==.',
Lo='Lockedtoit:BAAANQAECgIIAgAAAA==.Loveg:BAAANQADCgYIBgAAAA==.Loverocket:BAABNQAECn8rAAIQAAgK2x0CEACbAgAQAAgK2x0CEACbAgAAAA==.',
Lu='Luna:BAAANQAECgUIBQABNQAECgYICgAKAAAAAA==.Lunastorm:BAAANQADCgQIBAAAAA==.',
Ly='Lyshia:BAABNQAECn81AAMOAAkKGR+vOQAUAwAOAAkKGR+vOQAUAwAYAAIKkB5YKACvAAAAAA==.',
['Lí']='Líghthand:BAABNQAECn8WAAMQAAgKChoYHAAJAgAQAAgKChoYHAAJAgAHAAEK/wGu1QETAAAAAA==.',
['Lý']='Lýght:BAAANQADCgcIDQAAAA==.',
Ma='Magedown:BAABNQAECn8pAAMOAAkKlhW0hAB0AgAOAAkKlhW0hAB0AgAYAAEKkAVZUgAfAAAAAA==.Magician:BAAANQADCggICAAAAA==.Mamachula:BAAANQADCgYIDQAAAA==.Manapali:BAAANQAECgQIBgABNQAECgkJMAAMAD4gAA==.Manpumper:BAAANQAECgYICgAAAA==.Margor:BAAANQAECgUIDwABNQAECgcIGwAdAJUVAA==.Mariella:BAAANQAECgcIBwAAAA==.Mattdemon:BAABNQAECn82AAMZAAkKoB0uEgAKAwAZAAkKoB0uEgAKAwACAAcKuxIRNQCWAQAAAA==.',
Me='Meanzy:BAAANQADCgQIBAAAAA==.Meliany:BAAANQAECgUICwAAAA==.Meliorate:BAACNQAFFH8IAAMBAAMKbAPWGwC4AAABAAMKbAPWGwC4AAAPAAEKdgJ0FQBFAAA1AAQKfyQAAwEACQrKFHY4ACcCAAEACQrKFHY4ACcCAA8ABgqbDKE6AEYBAAAA.Meowch:BAABNQAECn8qAAIiAAkKSB/7AwBVAwAiAAkKSB/7AwBVAwAAAA==.Meríin:BAAANQADCgEIAQAAAA==.',
Mi='Mikachu:BAABNQAECn9IAAIMAAkKpSauAADRAwAMAAkKpSauAADRAwABNQAFFAYIEAAHAFEaAA==.Miksi:BAAANQADCgYIDgABNQAECgEIAQAKAAAAAA==.Miradele:BAABNQAECn8eAAIPAAcKMQeXQQAWAQAPAAcKMQeXQQAWAQAAAA==.Miraxx:BAAANQAECgEIAQAAAA==.Misscleö:BAABNQAECn8bAAIHAAgKeBYZhAAbAgAHAAgKeBYZhAAbAgAAAA==.Miyoshi:BAABNQAECn8qAAIjAAgKAwoJIADLAQAjAAgKAwoJIADLAQAAAA==.',
Mo='Mobius:BAAANQABCgIIBQAAAA==.Moonshíne:BAAANQADCgIIAgAAAA==.Moosakka:BAABNQAECn8xAAIkAAgKAxRgGQDlAQAkAAgKAxRgGQDlAQAAAA==.Moosesiah:BAAANQABCgYICgABNQAECgkJJgAkALQYAA==.Moovinthru:BAAANQAECgIIAgAAAA==.Moraxes:BAAANQAECgUIBgAAAA==.Mordenkainen:BAAANQAECgUIDAAAAA==.Morgax:BAABNQAECn8fAAQdAAkKLxXORgBYAgAdAAkKIhXORgBYAgAIAAgKexfgSQA4AgAMAAEKqwMlNgA0AAAAAA==.Morgona:BAAANQADCgUICQAAAA==.Morphidmage:BAAANQADCgUIBQAAAA==.Motoko:BAAANQAECgEIAQAAAA==.',
Mu='Muaadib:BAAANQAECggIEgABNQAECgkJMwAJAA0aAA==.',
My='Mydin:BAABNQAECn8fAAIHAAgK0hT7mADsAQAHAAgK0hT7mADsAQAAAA==.Myssaphra:BAACNQAFFH8GAAIIAAMKsxmCFQD8AAAIAAMKsxmCFQD8AAA1AAQKfykAAwgACQomG6IvAKECAAgACQomG6IvAKECAB0AAQoAAGBHASgAAAAA.',
['Mì']='Mìsawa:BAABNQAECn8aAAMEAAkKFQvUogCKAQAEAAgKkQrUogCKAQAFAAQKBwjiQAC+AAAAAA==.',
Na='Nakai:BAABNQAECn8lAAIJAAkK/xwtJwD5AgAJAAkK/xwtJwD5AgAAAA==.Nasatra:BAAANQADCgcIFAAAAA==.Nastijiggle:BAABNQAECn8ZAAIeAAgKpBp8IAAyAgAeAAgKpBp8IAAyAgAAAA==.Nazrien:BAAANQABCgUJBQAAAA==.Nazrion:BAAANQABCgEIAQAAAA==.',
Nc='Nc:BAABNQAECn8XAAIWAAgK1x8+CgDKAgAWAAgK1x8+CgDKAgAAAA==.',
Ne='Nexxa:BAABNQAECn8iAAIJAAgKkgtNiwDwAQAJAAgKkgtNiwDwAQAAAA==.',
Ni='Nightfall:BAAANQAECggICAAAAA==.Nightshadow:BAAANQADCgQIBAAAAA==.Nightsongs:BAAANQABCgIIAgAAAA==.Niqkle:BAABNQAECn8mAAMIAAkKZRFccAC3AQAIAAgK2Q9ccAC3AQAdAAgKVw7vegCuAQAAAA==.Nitebane:BAABNQAECn8cAAISAAgKRQqYPwDJAQASAAgKRQqYPwDJAQAAAA==.',
No='Nohurtscooby:BAAANQAECgEIAQAAAA==.Notadh:BAAANQADCggIEAAAAA==.Notadruid:BAAANQADCgQIBAAAAA==.Notawrlock:BAAANQAECgEIAQABNQAFFAIIBAAKAAAAAA==.',
Ns='Nstagatr:BAABNQAECn8YAAIVAAcKZwSsRgAhAQAVAAcKZwSsRgAhAQAAAA==.',
Ny='Nyxandria:BAAANQABCgQIBAAAAA==.Nyxi:BAAANQABCgQIBAAAAA==.',
['Né']='Nécrömancer:BAAANQADCgMIAwAAAA==.',
Oa='Oak:BAAANQAECgIIAgAAAA==.',
Oc='Occidius:BAAANQAECgQICQAAAA==.',
Ol='Olari:BAAANQAECgEIAQAAAA==.Oldfox:BAAANQAECgEIAgAAAA==.Oldoriel:BAAANQADCgYICwAAAA==.Olehanna:BAABNQAECn80AAIHAAgK9g4soADcAQAHAAgK9g4soADcAQAAAA==.Olestrid:BAAANQADCggIJgABNQAECggINAAHAPYOAA==.',
On='Oni:BAAANQADCgYICAAAAA==.',
Op='Opioid:BAAANQAECgMIAwAAAA==.Opsec:BAAANQAECgIJAgABNQAECgcIHAACAM4WAA==.Opsèc:BAABNQAECn8cAAICAAcKzhbzLgDGAQACAAcKzhbzLgDGAQAAAA==.',
Or='Orsa:BAAANQADCggICAAAAA==.',
Pe='Peachcider:BAEANQAECgMIBAABNQAFFAcIIAAIAOsdAA==.Peachshock:BAECNQAFFH8gAAMIAAcK6x0YAgCOAgAIAAcK6x0YAgCOAgAdAAMKSA/SGwDeAAA1AAQKfyAAAwgACQrQJc0JAHEDAAgACQrQJc0JAHEDAB0ABApaIeWmAEIBAAAA.Peachyknight:BAAANQAECgQIBAAAAA==.Peebee:BAAANQAECgMIAwABNQAECggIUAARAAskAA==.Perfectlock:BAABNQAECn8mAAIEAAkKjhjmPwCPAgAEAAkKjhjmPwCPAgAAAA==.',
Pi='Pigog:BAAANQAECgYIEgAAAA==.',
Po='Pooskbuddy:BAAANQADCgcIDQAAAA==.Popcorners:BAAANQADCgcIBwABNQAECgkJIgAMADkjAA==.Pordgio:BAAANQAECgcIDgAAAA==.Pozzi:BAAANQAECggICQAAAA==.',
Pr='Praypal:BAAANQADCgQIBAAAAA==.Primoss:BAAANQADCgYIBgABNQAECgcIHAACAM4WAA==.',
Ps='Psuedolus:BAAANQAECgUIDAAAAA==.Psålm:BAABNQAECn8nAAIeAAkKzhgNFwCfAgAeAAkKzhgNFwCfAgAAAA==.',
Pu='Pulshadow:BAACNQAFFH8MAAIeAAUKMBTnBgCqAQAeAAUKMBTnBgCqAQA1AAQKfyYAAh4ACQpHJE0JAEcDAB4ACQpHJE0JAEcDAAAA.Pumah:BAAANQAECgEIAQAAAA==.',
Qt='Qtclaps:BAAANQADCggIHwAAAA==.',
Qu='Quartzecoatl:BAAANQADCgUICQAAAA==.',
Ra='Raahhzi:BAAANQADCgYIBgAAAA==.Raamen:BAAANQAECgEIAQAAAA==.Raellia:BAABNQAECn80AAQEAAgK5RHHpACGAQAEAAYK7Q7HpACGAQAFAAMKLRFjQQC9AAAUAAEKTgjXMAAyAAAAAA==.Raimmey:BAAANQAECgQIBAAAAA==.Rajia:BAAANQAECgIJAgABNQAECgcIHgAFAJkEAA==.Ralune:BAABNQAECn8eAAIBAAcKEwgkYgBCAQABAAcKEwgkYgBCAQAAAA==.Randomshaman:BAAANQADCgUIBQAAAA==.Ranes:BAABNQAECn83AAISAAgKbR0EGQCwAgASAAgKbR0EGQCwAgAAAA==.Razagual:BAAANQAECggIEgABNQAECggIBgAKAAAAAA==.',
Re='Redback:BAAANQABCgMIBgAAAA==.Redxelementz:BAABNQAECn82AAIIAAkKnCaTAADnAwAIAAkKnCaTAADnAwAAAA==.Redxpastakan:BAAANQADCgUIBQABNQAECgkJNgAIAJwmAA==.Redxyara:BAAANQAECgYIDwAAAA==.Renasen:BAABNQAECn8iAAIRAAgKPiHYNADsAgARAAgKPiHYNADsAgAAAA==.Reno:BAABNQAECn8jAAMXAAgKVxcoTQAzAgAXAAgKVxcoTQAzAgAHAAcKDg/nvACdAQAAAA==.Replacegamy:BAAANQAECgEIAQABNQAFFAIIBAAKAAAAAA==.Resiretha:BAAANQAECggIEwAAAA==.Revelynn:BAABNQAECn8uAAMcAAkKqRgXDAADAgACAAgKshgAHABzAgAcAAkKGRMXDAADAgAAAA==.Rexkwondo:BAAANQAECgQJBAAAAA==.',
Rh='Rhyssyn:BAAANQADCgUIBQAAAA==.',
Ri='Rilerich:BAAANQAECgEIAQAAAA==.Rivliam:BAABNQAECn8bAAMFAAgKyw7cIwBSAQAEAAgKAQpBngCVAQAFAAYKIw7cIwBSAQAAAA==.Rizzn:BAAANQAECgIIAgABNQAECgcIHAAjAKsWAA==.',
Ro='Rook:BAAANQAECgIIAgAAAA==.Rooxxy:BAABNQAECn8ZAAMOAAcKoBeAwAABAgAOAAcKoBeAwAABAgAYAAEK5QiOTgAoAAAAAA==.Rotawna:BAAANQADCgcIGQAAAA==.Roxxyyzz:BAAANQAECgQICAABNQAECgcIGQAOAKAXAA==.Roûge:BAAANQAECgIIAgABNQAECggIUAARAAskAA==.',
Ru='Rumikang:BAAANQADCgIIAgABNQAECggINAAEAOURAA==.',
Ry='Rybeorn:BAAANQAECgEIAwAAAA==.Rynoh:BAAANQAECgcICwAAAA==.Rythrik:BAABNQAECn8VAAMXAAkK0Al7bADPAQAXAAkK0Al7bADPAQAHAAIKMgsrcAFnAAAAAA==.',
Sa='Sainted:BAACNQAFFH8VAAIXAAcKWReQAwBXAgAXAAcKWReQAwBXAgA1AAQKfyoAAxcACQrjFLpCAFgCABcACQrjFLpCAFgCAAcABwqAFIDKAIABAAAA.Sanoks:BAABNQAECn8tAAMQAAkKfx+xCQAAAwAQAAkKfx+xCQAAAwAHAAIKbQZvhwFHAAAAAA==.Sanokz:BAAANQAECgEIAQABNQAECgkJLQAQAH8fAA==.Santar:BAAANQADCgcIBwAAAA==.Sassafraz:BAAANQADCggICAABNQAECggIKwAQANsdAA==.Savira:BAABNQAECn8cAAIPAAcK0A7ONQBoAQAPAAcK0A7ONQBoAQAAAA==.',
Sc='Scaleorva:BAABNQAECn8bAAMGAAcKMBBQGgCiAQAGAAcKMBBQGgCiAQAlAAQKiQgNGgCbAAAAAA==.Scarlit:BAAANQABCgYIBgAAAA==.',
Se='Sentharis:BAAANQADCgcIDQAAAA==.Seraphìm:BAABNQAECn8hAAIHAAcKpgkj1ABtAQAHAAcKpgkj1ABtAQAAAA==.Seïnaru:BAAANQAECgQIBwAAAA==.',
Sh='Shadenova:BAAANQADCgUIBgABNQAECgcIHQAOABQTAA==.Shadezilla:BAAANQADCgYIBgABNQAECgcIHQAOABQTAA==.Shadowpath:BAAANQABCgQIAgAAAA==.Shadowypete:BAAANQAECgUIBQAAAA==.Shadyballs:BAABNQAECn8dAAQOAAcKFBMi4QDDAQAOAAcK6hIi4QDDAQAmAAMKVw+yBwC1AAAYAAIKeAwWNABoAAAAAA==.Shakypete:BAAANQAECgQICwABNQAECgYIKQABAFMTAA==.Shamken:BAAANQADCgYIBgAAAA==.Shamysosa:BAABNQAECn8bAAMdAAcKlRXyYAD7AQAdAAcKlRXyYAD7AQAIAAEKMBIgFwE3AAAAAA==.Shiionknow:BAAANQADCgQIBAAAAA==.Shinjí:BAABNQAECn8cAAINAAgKlR5nIQDAAgANAAgKlR5nIQDAAgABNQAFFAcIEQANAAIVAA==.Shizens:BAAANQADCgYIBgAAAA==.Shmob:BAAANQAECgEIAgAAAA==.Shnappz:BAABNQAECn8gAAMEAAcKGQhmvABPAQAEAAcKGQhmvABPAQAFAAEKbQIUhgAhAAAAAA==.Shwillarou:BAABNQAECn80AAINAAgKcQ6MWQCmAQANAAgKcQ6MWQCmAQAAAA==.Shádôws:BAAANQADCgYICwAAAA==.',
Si='Sinergee:BAAANQAECgcIDwAAAA==.Sinnj:BAAANQADCgcIDQAAAA==.Sinona:BAAANQADCgQIBAAAAA==.Sipholice:BAAANQADCgUIBQABNQAECgUIDQAKAAAAAA==.',
Sk='Skinzey:BAAANQAECgQIBwAAAA==.Skinzy:BAAANQADCgUIBwAAAA==.Skycrush:BAAANQADCgUICQAAAA==.',
Sl='Slanie:BAABNQAECn8cAAIDAAcKTwfDmQBDAQADAAcKTwfDmQBDAQAAAA==.Slingerz:BAABNQAECn82AAMnAAkKaBc3DgBJAgAnAAkKaBc3DgBJAgATAAEKAACUOAAjAAAAAA==.Slingr:BAAANQADCgcIBwAAAA==.Slowmeaux:BAAANQADCgEIAQAAAA==.',
Sm='Smalldragon:BAAANQAECggIBQAAAA==.Smoky:BAABNQAECn8gAAQEAAkK/hvkSgBvAgAEAAgK7xvkSgBvAgAUAAIKKhL2GgCpAAAFAAEKURZybgBBAAAAAA==.',
Sn='Sneakpastya:BAAANQADCgIIAgAAAA==.Sneakyg:BAAANQAECgYIEgABNQAECgkJIwAHADAhAA==.Snoochie:BAABNQAECn8iAAIdAAgK9xOOYQD5AQAdAAgK9xOOYQD5AQAAAA==.',
So='Sol:BAACNQAFFH8OAAIhAAUKOx3jAACsAQAhAAUKOx3jAACsAQA1AAQKfzgAAiEACQr/I8AAAKYDACEACQr/I8AAAKYDAAAA.Solkar:BAAANQADCgUIBQABNQAECgkJKQALAGIaAA==.Sollis:BAAANQAECgYIEQAAAA==.Sonastii:BAAANQADCgYIBgABNQAECggIGQAeAKQaAA==.Soulcoil:BAAANQAECgQICQABNQAECgUICgAKAAAAAA==.Soulfury:BAAANQABCgUIBgABNQAECgUICgAKAAAAAA==.Soulreaper:BAAANQAECgUICgAAAA==.Soulshock:BAAANQAECgQICQABNQAECgUICgAKAAAAAA==.Soulstorm:BAAANQADCgYIBgABNQAECgUICgAKAAAAAA==.',
Sp='Sparnak:BAABNQAECn8iAAIOAAgKtALfPgEgAQAOAAgKtALfPgEgAQAAAA==.Spawntier:BAAANQADCgUIBQABNQADCggICAAKAAAAAA==.Spazzchel:BAAANQADCggIIAAAAA==.Spiritbox:BAACNQAFFH8KAAIIAAYKdRpOBwDgAQAIAAYKdRpOBwDgAQA1AAQKfyMAAggACQqxJFYNAFUDAAgACQqxJFYNAFUDAAE1AAQKCQkbAAMAIB4A.Spruce:BAAANQADCggIKAAAAA==.Sprucemoose:BAAANQADCgYICwABNQADCgcIFAAKAAAAAA==.',
St='Stahlman:BAABNQAECn8uAAMIAAgKXBeKTgAnAgAIAAgKXBeKTgAnAgAdAAIK+AYPFwFaAAAAAA==.Stalpho:BAABNQAECn8sAAITAAkKmBdTBgCmAgATAAkKmBdTBgCmAgAAAA==.Starblessed:BAAANQAECgEIAQABNQAECggIGgAIAFgEAA==.Starflare:BAAANQADCgUIBQABNQAECggIGgAIAFgEAA==.Starkind:BAABNQAECn8aAAIIAAgKWARcogAsAQAIAAgKWARcogAsAQAAAA==.Starliner:BAABNQAECn8iAAIMAAkKOSN/AwBkAwAMAAkKOSN/AwBkAwAAAA==.Stasis:BAAANQAECgUICAABNQAECgkJGwADACAeAA==.Stealbreath:BAAANQADCgcICQAAAA==.Stormyknight:BAAANQADCgUICQAAAA==.Strahd:BAAANQADCgYIFAAAAA==.Styrke:BAAANQADCgYIBgAAAA==.Styrmir:BAAANQAECgQIBAAAAA==.',
Su='Subza:BAABNQAECn82AAMOAAkKGhngXADGAgAOAAkKGhngXADGAgAYAAEK1RPuQgA8AAAAAA==.Suurik:BAAANQABCgIIAgAAAA==.',
Sw='Swagadin:BAAANQADCgcIBwABNQAECggIEAAKAAAAAA==.Swagikal:BAAANQAECggIEAAAAA==.Swagtistic:BAAANQADCggIFAAAAA==.',
Ta='Tahra:BAAANQADCgcICgAAAA==.Taliss:BAABNQAECn8qAAIDAAgK3RokPAB2AgADAAgK3RokPAB2AgAAAA==.Tankmedaddy:BAABNQAECn8pAAMbAAkK/BFqIAAmAgAbAAkK/BFqIAAmAgAkAAQKSxcXLwDsAAAAAA==.Tappuccino:BAAANQAECgUICQAAAA==.Taras:BAABNQAECn8oAAMRAAkKpyS1QwC7AgARAAgK8SO1QwC7AgATAAYKihh4EACcAQAAAA==.Taraxist:BAABNQAECn8eAAIFAAgK0BzkBQCzAgAFAAgK0BzkBQCzAgAAAA==.Tautology:BAABNQAECn8aAAIeAAkKQRRvHABeAgAeAAkKQRRvHABeAgAAAA==.Tazajin:BAAANQADCgYIBgAAAA==.',
Tc='Tchala:BAABNQAECn8jAAIHAAkKMCFKPQDaAgAHAAkKMCFKPQDaAgAAAA==.Tchallah:BAAANQAECgQIBwAAAA==.Tchaumb:BAAANQADCgEIAQAAAA==.',
Td='Tdog:BAAANQADCgcJBwAAAA==.',
Te='Teacup:BAAANQADCgYIBgABNQAECggIFwAWANcfAA==.Teks:BAABNQAECn8dAAMXAAgKtBcIUwAeAgAXAAgKtBcIUwAeAgAQAAYKKRhrLwBfAQAAAA==.Teksara:BAAANQAECgQIAwABNQAECggIHQAXALQXAA==.Teksynoth:BAAANQADCgQIBAABNQAECggIHQAXALQXAA==.Telian:BAAANQADCgUIBQAAAA==.Terracustode:BAAANQABCgIJAgAAAA==.Teth:BAAANQAECgYIEQAAAA==.Tevildo:BAAANQABCgIIAgAAAA==.',
Th='Thaine:BAABNQAECn82AAIHAAkKmiPjCwCgAwAHAAkKmiPjCwCgAwAAAA==.Theundeadone:BAABNQAECn8uAAIeAAkKDh0LCwAxAwAeAAkKDh0LCwAxAwAAAA==.Thndrwzrd:BAAANQAECgQICAAAAA==.Thorphan:BAABNQAECn80AAQMAAkKYiSmAQCfAwAMAAkKYiSmAQCfAwAdAAUKARc7tgAhAQAIAAUKcAuHzQDIAAAAAA==.',
Ti='Ticho:BAAANQAECgQIBgAAAA==.',
To='Torez:BAAANQAECgUICQABNQAECgkJNgAZAKAdAA==.Torodisilis:BAAANQAECgUICwABNQAECgkJIwAHADAhAA==.Toxicavenger:BAAANQAECggICgAAAA==.',
Tr='Treygec:BAAANQAECgUIBwAAAA==.Tribolonotus:BAAANQAECgIIAgAAAA==.Trickette:BAAANQADCgcICAABNQAECggIDwAKAAAAAA==.Trilleong:BAAANQADCgIIAgAAAA==.Trina:BAAANQADCggICAAAAA==.Trisilla:BAAANQADCggIFQABNQAECgkJKQAoAIQNAA==.Troubleshot:BAAANQAECggICAAAAA==.Trujal:BAABNQAECn8kAAILAAgKuxl+LgBYAgALAAgKuxl+LgBYAgAAAA==.',
Tu='Turdmonk:BAABNQAECn88AAIbAAkKLCDwCQAwAwAbAAkKLCDwCQAwAwAAAA==.',
Ty='Tylandon:BAAANQABCgQIDQAAAA==.Tyndal:BAAANQADCgcIDwAAAA==.Typhon:BAABNQAECn8tAAMeAAkKARxxGACMAgAeAAgKiRtxGACMAgADAAYKviAkVQAgAgAAAA==.',
Tz='Tzaim:BAAANQADCggIBwAAAA==.',
Un='Unclebób:BAAANQADCgYIDAABNQAECgUICAAKAAAAAA==.Unshady:BAAANQADCgYIBgABNQAECgcIHQAOABQTAA==.',
Va='Vaeshta:BAABNQAECn8dAAIMAAcKXANRIgAwAQAMAAcKXANRIgAwAQAAAA==.Vaku:BAAANQADCgYIBgAAAA==.Valhallarama:BAABNQAECn8mAAIIAAkKhRmAPwBfAgAIAAkKhRmAPwBfAgAAAA==.Valika:BAAANQABCgYIBgAAAA==.Vampy:BAAANQAECgQIBAAAAA==.Vandragon:BAAANQADCggIGAAAAA==.Vannida:BAAANQAECgIIAQAAAA==.Vardanis:BAAANQAECgQIBAABNQAECgcIIQAaAEMaAA==.',
Ve='Vengencedawg:BAABNQAECn8kAAIHAAkKrwhMvQCcAQAHAAkKrwhMvQCcAQAAAA==.Vexxya:BAAANQADCgQIAwAAAA==.',
Vl='Vladus:BAABNQAECn8pAAILAAkKYhqiIQCmAgALAAkKYhqiIQCmAgAAAA==.',
Vo='Voltroñ:BAAANQADCgMIAwABNQAFFAQIDgAOAHEZAA==.Voodoo:BAAANQAECgQIBAAAAA==.',
Vs='Vsegda:BAAANQAECgUIBwABNQAFFAMIBgAIALMZAA==.',
Vy='Vyllian:BAABNQAECn8jAAILAAgKtQ9iUQCtAQALAAgKtQ9iUQCtAQAAAA==.',
Wa='Wangwang:BAAANQAECgIIAgAAAA==.Wardrag:BAAANQABCgQIBAAAAA==.Wareshesh:BAAANQADCgUIBQAAAA==.Warlakaflaka:BAAANQAECgUIDwABNQAECgcIHQAOABQTAA==.',
Wh='Whale:BAAANQAECggIEgAAAA==.',
Wi='Wickðaddy:BAAANQABCgMIAwAAAA==.Windfury:BAABNQAECn8gAAIMAAgKpRQjFQASAgAMAAgKpRQjFQASAgAAAA==.Windfuryous:BAAANQADCgUICQAAAA==.Winston:BAAANQADCggIIQAAAA==.',
Wo='Wolfsbane:BAAANQADCgYIBgAAAA==.Wonpiece:BAAANQAECgYIDAABNQAFFAMICAABAGwDAA==.',
Wu='Wulfnir:BAAANQADCgcIBwAAAA==.',
Wy='Wylestrean:BAABNQAECn8kAAIJAAkKcR0mMQDXAgAJAAkKcR0mMQDXAgAAAA==.',
Xa='Xanokz:BAAANQADCgEIAQABNQAECgkJLQAQAH8fAA==.Xarytha:BAAANQABCgMJAwABNQAECggIDAAKAAAAAA==.',
Xi='Xiaomao:BAAANQADCgcIBwABNQAECgEIAQAKAAAAAA==.',
Ye='Yeinn:BAABNQAECn9QAAMRAAgKCySLGwBIAwARAAgKCySLGwBIAwATAAUKuiEYDQDkAQAAAA==.',
Za='Zandalarthas:BAABNQAECn8bAAILAAcK0hY1TwC1AQALAAcK0hY1TwC1AQAAAA==.Zarbok:BAAANQADCgQIBAABNQAECgcIGwAdAJUVAA==.',
Zc='Zcredo:BAABNQAECn8xAAIRAAkKax/0JAAjAwARAAkKax/0JAAjAwAAAA==.',
Ze='Zel:BAAANQAECgQIBgAAAA==.Zentradei:BAAANQADCgQIBAAAAA==.Zephariel:BAAANQADCgcIGAAAAA==.Zerus:BAAANQABCgMIBAAAAA==.',
Zi='Ziconik:BAAANQADCgYIBgAAAA==.Zieganfuss:BAAANQAECggIDAAAAA==.Zinrozlek:BAABNQAECn8dAAILAAcK5wWTeQAOAQALAAcK5wWTeQAOAQAAAA==.',
Zo='Zoho:BAABNQAECn8pAAIoAAkKhA3REgC0AQAoAAkKhA3REgC0AQAAAA==.Zorrander:BAAANQADCgQIBAABNQAECgQIBAAKAAAAAA==.',
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
