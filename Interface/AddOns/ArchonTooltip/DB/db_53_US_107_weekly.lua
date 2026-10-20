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

local lookup = {'Paladin-Protection','Paladin-Retribution','Paladin-Holy','Hunter-Marksmanship','Hunter-BeastMastery','Priest-Shadow','Priest-Discipline','Priest-Holy','DemonHunter-Havoc','DemonHunter-Devourer','DemonHunter-Vengeance','Unknown-Unknown','Shaman-Elemental','Warlock-Affliction','Warlock-Demonology','Warrior-Protection','Warrior-Fury','Warrior-Arms','DeathKnight-Blood','DeathKnight-Unholy','Druid-Balance','Druid-Guardian','Druid-Restoration','Warlock-Destruction','Mage-Arcane','Druid-Feral','Shaman-Restoration','Evoker-Preservation','Rogue-Assassination','Mage-Frost','DeathKnight-Frost','Shaman-Enhancement','Monk-Brewmaster','Monk-Mistweaver','Monk-Windwalker','Rogue-Subtlety','Evoker-Devastation','Evoker-Augmentation','Mage-Fire',}
local provider = {region='US',realm='Gilneas',name='US',type='weekly',zone=53,date='2026-10-20',data={Ac='Acks:BAAANQAECgEIAQABNQAFFAUICAABALsGAA==.',
Ae='Aedra:BAAANQAECgIIAgAAAA==.Aeowyyn:BAABNQAECn8VAAMCAAgKjgoR/QAlAQACAAcKVQYR/QAlAQADAAIKgQWgDAFeAAAAAA==.Aex:BAABNQAECn8WAAMEAAgK0BE0PABwAQAEAAcK4RA0PABwAQAFAAMKygkHKAGkAAABNQAFFAUICAABALsGAA==.',
Af='Afib:BAAANQADCgUICAAAAA==.',
Ah='Ahnkhano:BAAANQAECgYIBgAAAA==.',
Ai='Ainge:BAAANQAECgEIAwAAAA==.Airiistra:BAAANQADCgMIAwAAAA==.',
Ak='Akbartheiiv:BAACNQAFFH8XAAMGAAcK7xtIAgBxAgAGAAcK7xtIAgBxAgAHAAEKFgJVBABEAAA1AAQKf1AAAwYACgoAJjkAAGwDAAYACgoAJjkAAGwDAAcACArUJBoBAFkDAAAA.Akorius:BAAANQAECgIIAwAAAA==.',
Al='Alarion:BAAANQADCgEIAQAAAA==.Alexanderson:BAAANQAECgEIAgAAAA==.Allistrana:BAABNQAECn8cAAIIAAcK/B4rQgBjAgAIAAcK/B4rQgBjAgAAAA==.Allpower:BAAANQADCgYIDgAAAA==.Alpacalyptic:BAAANQAECgcICQAAAA==.Alyx:BAAANQADCgcIBwAAAA==.',
Am='Amadeux:BAAANQADCgIIAgABNQAECgkJHwAFAHsbAA==.Amairis:BAABNQAECn8VAAMHAAYKeRBQAwD5AAAHAAYKeRBQAwD5AAAGAAQKcwh1UwDAAAAAAA==.Ambiorix:BAAANQABCgIIAgAAAA==.',
An='Anrion:BAABNQAECn84AAQJAAoKjR4DEQAXAwAJAAoKUB4DEQAXAwAKAAYKsRgsPABmAQALAAIKZCNfIgCvAAAAAA==.Antiflag:BAAANQAECgYIBwAAAA==.Anzania:BAAANQADCgEIAQABNQADCgYIEQAMAAAAAA==.',
Ar='Arolz:BAAANQADCgYIBgAAAA==.',
At='Ataliya:BAABNQAECn8UAAINAAYK5gsKqwA+AQANAAYK5gsKqwA+AQAAAA==.',
Au='Auranar:BAAANQAECgYIEwAAAA==.Aurelya:BAABNQAECn8kAAIIAAcKsw7DggCPAQAIAAcKsw7DggCPAQAAAA==.Aurilia:BAAANQAECgMICwAAAA==.',
Av='Avanicus:BAABNQAECn8YAAMOAAgKcA21CwCsAQAOAAgKcA21CwCsAQAPAAIK8ANeNAFRAAAAAA==.Aven:BAAANQAECgEIAQAAAA==.Avernas:BAAANQAECgQIBgAAAA==.Avé:BAABNQAECn8jAAMCAAgK4w+LSgAwAQACAAgKLg+LSgAwAQABAAQKRA0ZTgCwAAAAAA==.',
Ax='Axellent:BAACNQAFFH8IAAIQAAMKvhAIBQC/AAAQAAMKvhAIBQC/AAA1AAQKfyIABBAACQr3Gk4KAAwBABEABQq/GkwSAH8BABAABgqWF04KAAwBABIABgqBGUtSAPgAAAE1AAUUBQgIAAEAuwYA.Axiomlegacy:BAABNQAECn8nAAMTAAoKUCEKDgBAAwATAAoKUCEKDgBAAwAUAAEKpwgs5gAuAAAAAA==.',
Az='Azraith:BAAANQADCgcIBgAAAA==.Azulien:BAAANQAECgcIEgAAAA==.Azulin:BAAANQADCgUJBQAAAA==.',
Ba='Banderblitz:BAABNQAECn8oAAMRAAkKyRYSDgDSAQARAAcKcRkSDgDSAQASAAgKQxQ1QQAhAQAAAA==.Banzgrave:BAAANQADCgcIBwAAAA==.Bar:BAACNQAFFH8HAAMIAAYKVQMFCQA7AQAIAAUKjgMFCQA7AQAGAAIK8wNpFQBzAAA1AAQKfx4AAwYACgpSF60kAAsCAAYACAqMGK0kAAsCAAgACQrrCqGIAH0BAAAA.',
Be='Bearlyshady:BAABNQAECn85AAQVAAoKVhf1HgDTAgAVAAoKVhf1HgDTAgAWAAQK9gmiQgCsAAAXAAEKugNHeQAsAAABNQADCgYIBgAMAAAAAA==.Bellarina:BAAANQAECgQICAAAAA==.Bellatrixie:BAAANQAECgQIEgAAAA==.Bennitely:BAAANQADCgEIAQAAAA==.Beriadhwen:BAAANQAECgEIAQAAAA==.Bermy:BAABNQAECn8cAAMYAAkKuAn5FgC1AQAYAAkKuAn5FgC1AQAPAAQKrgWUEgGmAAAAAA==.Berzerkercow:BAAANQADCgYIBwAAAA==.Bewildert:BAAANQADCgMIBAAAAA==.',
Bh='Bhawkwco:BAAANQADCgUIBQAAAA==.',
Bi='Bigjaina:BAABNQAECn81AAIZAAkKxRwJEQDeAQAZAAkKxRwJEQDeAQAAAA==.Biku:BAAANQAECgYICwAAAA==.Bitesthesky:BAAANQAECgUIBQAAAA==.',
Bl='Blackhawkdk:BAABNQAECn8pAAMUAAoKHxkoKwCJAgAUAAoKHxkoKwCJAgATAAEKAADExQA9AAAAAA==.Blackhawkm:BAAANQADCgcIBwAAAA==.Blende:BAAANQAECgQIBwABNQAECgcICwAMAAAAAA==.Blindwarrior:BAAANQAECgIIAwAAAA==.Bloodshadow:BAABNQAECn8VAAIFAAYKMQyL1wBRAQAFAAYKMQyL1wBRAQAAAA==.',
Bo='Boraffe:BAAANQADCgMJAgAAAA==.Bovinity:BAAANQABCgcICgAAAA==.',
Br='Breakcooloz:BAAANQAFFAEIAQABNQAFFAUIBQAUAJoTAA==.Bretcoe:BAAANQADCgYIDAABNQAECgIJAgAMAAAAAA==.Bronzamdee:BAAANQADCggJCAAAAA==.Brooce:BAABNQAECn8pAAICAAgKLRvmJQCOAQACAAgKLRvmJQCOAQAAAA==.Broom:BAAANQAECgQIBQABNQAECgkJNQAZAMUcAA==.Brozken:BAAANQADCgUICAAAAA==.Brutak:BAAANQADCggICAAAAA==.',
Bu='Burstinurass:BAACNQAFFH8FAAIUAAUKmhPDCACMAQAUAAUKmhPDCACMAQA1AAQKfxkAAhQACgrpHVYcAOICABQACgrpHVYcAOICAAAA.Buzzliteyear:BAAANQADCgUIBQAAAA==.',
['Bä']='Bängbäng:BAAANQADCgYICgAAAA==.',
Ca='Caelix:BAAANQAECgQIBQAAAA==.Canadiana:BAAANQADCgYIBgAAAA==.Carbo:BAAANQAECgYIBwABNQAECgoKJAAaABckAA==.Carbonight:BAABNQAECn8kAAIaAAoKFyTHAwBeAwAaAAoKFyTHAwBeAwAAAA==.Carlos:BAAANQAECgYIBAABNQAECggIFwACAPgXAA==.',
Ce='Celani:BAAANQADCggICAABNQAECggIFgAbACENAA==.Celintha:BAAANQADCgEIAQAAAA==.Cellyne:BAAANQAECgUIDQAAAA==.',
Ch='Chaoswind:BAABNQAECn8xAAIbAAoK0hm1LQCrAgAbAAoK0hm1LQCrAgAAAA==.Charlee:BAAANQAECgYICwAAAA==.Chaz:BAAANQAECgIIAgAAAA==.Cheeb:BAAANQADCgcIBwAAAA==.Cheebie:BAAANQABCgYIBgABNQADCgcIBwAMAAAAAA==.Chelives:BAEBNQAECn8cAAIQAAcKzAEAFQCLAAAQAAcKzAEAFQCLAAAAAA==.Chromus:BAACNQAFFH8YAAIcAAYKthiBAgDOAQAcAAYKthiBAgDOAQA1AAQKfygAAhwACgrrHHgNAM8CABwACgrrHHgNAM8CAAAA.',
Ci='Cires:BAABNQAECn8kAAIdAAkKZhIsEgAzAQAdAAkKZhIsEgAzAQAAAA==.',
Co='Colanasou:BAAANQAECgMICAAAAA==.Coldbattler:BAAANQAECgQIBwAAAA==.Convictions:BAAANQAECgYIDQABNQAFFAcIFgASAMQeAA==.Corrick:BAAANQAECgIICAAAAA==.Cowpatty:BAAANQADCgQIBAAAAA==.',
Cr='Crow:BAAANQAFFAYIDwAAAQ==.',
Cy='Cydric:BAABNQAECn8XAAICAAoKFhtRUACkAgACAAoKFhtRUACkAgAAAA==.',
Da='Daarrkstar:BAAANQAECgcICwAAAA==.Dakaryn:BAAANQADCggIDQAAAA==.Damageguy:BAAANQAECgYIBwABNQAFFAYIGgASAJwfAA==.',
De='Deadskvll:BAAANQADCgYIBgAAAA==.Deathbattler:BAAANQADCggIFAAAAA==.Deathrival:BAAANQADCggICAAAAA==.Dehnis:BAAANQADCgQIBAAAAA==.Delta:BAAANQADCgYICwAAAA==.Demonkare:BAAANQAECgUICgABNQAECgoKLgABAPsiAA==.Demoray:BAACNQAFFH8kAAMEAAcKryGJBAAqAgAEAAYKdSGJBAAqAgAFAAEKmSI0LgBmAAA1AAQKfyYAAwQACgriJWoGAGoDAAQACgriJWoGAGoDAAUAAQr5GIZOAUQAAAAA.Demvinity:BAAANQAECgMICQAAAA==.Dethrone:BAABNQAECn8cAAMPAAoK4RaaYAA2AgAPAAkKzhWaYAA2AgAYAAIKnRq8TACZAAAAAA==.Deus:BAABNQAECn84AAMGAAcKXhMfKwDOAQAGAAcKXhMfKwDOAQAHAAUKNhXwDgA9AQAAAA==.',
Di='Dinosocks:BAACNQAFFH8PAAMFAAcK8AyyEABSAQAFAAQKwhKyEABSAQAEAAQKPANvFAD5AAA1AAQKfy8AAwUACgoKFnV0ACcCAAUACAoTGXV0ACcCAAQACAotEcY0AKcBAAAA.Dirtydragon:BAABNQAECn8jAAIcAAkKdx2rAgAJAgAcAAkKdx2rAgAJAgAAAA==.Divinedecay:BAABNQAECn8XAAITAAcKUg5vHQAKAQATAAcKUg5vHQAKAQABNQAECgoKLQAFALYaAA==.',
Dj='Djaequitas:BAAANQABCgQIBgAAAA==.Djmelisandra:BAAANQABCgQIBAAAAA==.Djshamy:BAAANQABCgUICAAAAA==.',
Do='Dok:BAAANQAECgMIAwAAAA==.Donoraginn:BAAANQAECgEIAQAAAA==.Donos:BAAANQADCggIKwABNQAECgEIAQAMAAAAAA==.Dontkare:BAAANQADCgMIAwABNQAECgoKLgABAPsiAA==.Dorsai:BAAANQADCgUIBQAAAA==.Dotgenerate:BAAANQAECgQIBQAAAA==.',
Dr='Dracorex:BAAANQABCgIIAgAAAA==.Drark:BAAANQAECgIIBAAAAA==.Drathiel:BAAANQAECgEIAQAAAA==.Drizztknight:BAAANQADCgYIBgAAAA==.Drwho:BAABNQAECn8VAAMeAAcKvhjXDwCqAQAeAAYKwRnXDwCqAQAZAAQKRxWTYQHxAAAAAA==.Drääx:BAAANQADCgQIBAAAAA==.Dräëxx:BAAANQADCgcIBwAAAA==.Drëëxx:BAAANQAECgEIAQAAAA==.',
Du='Duckymet:BAAANQADCggIEwAAAA==.',
Dw='Dwallin:BAAANQADCgQIBAAAAA==.',
Dy='Dyane:BAAANQADCgQIBAAAAA==.',
['Dî']='Dîxon:BAAANQAECgIIAwABNQAFFAUIBQAUAJoTAA==.',
['Dô']='Dôz:BAAANQAECgQICAAAAA==.',
Ed='Edoaldor:BAAANQADCgUICgAAAA==.',
El='Ellery:BAAANQADCgUJBQAAAA==.',
Em='Empyrean:BAAANQAECgQIBQAAAA==.',
Ex='Exhumina:BAAANQAECgQICQAAAA==.',
Fa='Facestealerr:BAAANQAECgMIDQAAAA==.',
Fe='Felgibson:BAAANQADCgYIDQAAAA==.Fenmoon:BAABNQAECn8dAAIVAAgKFQ3cagAgAQAVAAgKFQ3cagAgAQAAAA==.',
Fi='Finneaa:BAAANQADCgUIBQAAAA==.',
Fl='Flairrick:BAABNQAECn8VAAIRAAcKxxVYBgA6AQARAAcKxxVYBgA6AQAAAA==.Flars:BAABNQAECn8qAAIfAAoKFiJOBgB9AwAfAAoKFiJOBgB9AwAAAA==.Flatliner:BAABNQAECn8ZAAIDAAgKPge3iQB/AQADAAgKPge3iQB/AQAAAA==.Flik:BAAANQAECggIEwABNQAFFAUICAABALsGAA==.',
Fo='Forq:BAAANQADCgcICAAAAA==.',
Fr='Frakz:BAAANQADCgUIBQAAAA==.Fran:BAAANQADCgYIBgABNQAECgkJNQAZAMUcAA==.Frankzappn:BAABNQAECn8gAAQNAAkK+hrCOgCLAgANAAgKJBzCOgCLAgAgAAQKMBJyFwCcAAAbAAMKhwFBFQE/AAAAAA==.Fray:BAAANQADCggICAAAAA==.Freeguy:BAABNQAECn8vAAIKAAkKuxbFBgCiAQAKAAkKuxbFBgCiAQAAAA==.Fruitcakes:BAABNQAECn8aAAQhAAYK0QTMIwC2AAAhAAUK/gPMIwC2AAAiAAUKLwUSOACtAAAjAAQK4gNeWgB8AAAAAA==.',
Fu='Fuddicus:BAAANQAECgEIAwAAAA==.Fuddrael:BAABNQAECn8gAAILAAkKKgq5CgC9AAALAAkKKgq5CgC9AAAAAA==.Fuddrucker:BAAANQAECgIIAgAAAA==.Fuddster:BAAANQADCgQIBAAAAA==.',
Ga='Gaddess:BAABNQAECn8cAAIGAAcK3gaiFQDcAAAGAAcK3gaiFQDcAAAAAA==.Gandàlf:BAAANQADCgYIBgAAAA==.Ganymede:BAAANQAECgUIBwAAAA==.Garan:BAAANQAECgEIAwAAAA==.',
Ge='Geilamaine:BAABNQAECn8fAAMDAAoKXhMAVQAbAgADAAoKXhMAVQAbAgACAAEKngqB8gA6AAAAAA==.',
Gl='Glimagi:BAAANQAECgMICwAAAA==.',
Gn='Gnxr:BAEANQAECgIIAgABNQAFFAIIBgAjALsiAA==.',
Go='Gonefishing:BAAANQADCgYIBgABNQAECgkJNgAFAJcaAA==.Gotêtsu:BAAANQAECgEIBQAAAA==.',
Gr='Grimjawz:BAABNQAECn8nAAIXAAkKBRsOEgDAAgAXAAkKBRsOEgDAAgAAAA==.Grippysocks:BAAANQAFFAIIAgABNQAFFAcIDwAFAPAMAA==.',
Gu='Gummibear:BAABNQAECn8YAAMQAAUKWg6sKQDtAAAQAAUKWg6sKQDtAAASAAEK+wQ6VQExAAAAAA==.',
Gw='Gwiyomi:BAAANQAECgIIAgABNQAECgoKGQAfAHAgAA==.',
Gy='Gyr:BAAANQAECgIIBAAAAA==.',
Ha='Hanbor:BAAANQADCgcIBwAAAA==.Haniku:BAABNQAECn8UAAISAAcKXwk2xwBqAQASAAcKXwk2xwBqAQAAAA==.Harthoon:BAACNQAFFH8WAAIZAAYKNAevFwC6AQAZAAYKNAevFwC6AQA1AAQKfzAAAx4ACgokGiULABMCAB4ACAqAHiULABMCABkACgqCD75SABYBAAAA.',
He='Henos:BAAANQADCgMIAwAAAA==.',
Ho='Hobomatt:BAAANQADCggICAAAAA==.Holiebelle:BAABNQAECn8VAAIDAAcKjxYEGQCRAQADAAcKjxYEGQCRAQAAAA==.Holyhutch:BAAANQAECgcICAABNQAECgoKJwAPACQaAA==.Holyshield:BAAANQADCgEIAQABNQAECgoKKgAIAKMcAA==.Honeynoats:BAABNQAECn8lAAIIAAgKiQnjhACIAQAIAAgKiQnjhACIAQAAAA==.Hotdwarf:BAABNQAECn8YAAQDAAYKAA7auwAEAQADAAUKbQvauwAEAQABAAUKlAeRSADLAAACAAEKBwQAAAAAAAAAAA==.',
Hr='Hrumm:BAACNQAFFH8WAAMEAAYK+BKNCAC/AQAEAAYKohCNCAC/AQAFAAEKkw9/FQBdAAA1AAQKfykAAwQACgrOGO4YAJACAAQACgrOGO4YAJACAAUABQpuCj8MAe4AAAAA.',
Hu='Hullkk:BAACNQAFFH8aAAISAAYKnB/zBgBSAgASAAYKnB/zBgBSAgA1AAQKfy0AAhIACgriIlcQAH0DABIACgriIlcQAH0DAAAA.Hun:BAAANQAECggICAAAAA==.Hush:BAAANQAECgMIBAAAAA==.Hutchadina:BAAANQAECgEIAQABNQAECgoKJwAPACQaAA==.Hutchanova:BAAANQAECgQIBQABNQAECgoKJwAPACQaAA==.Hutchi:BAAANQAECgQIBAABNQAECgoKJwAPACQaAA==.Hutchkins:BAABNQAECn8nAAIPAAoKJBrJBwArAgAPAAoKJBrJBwArAgAAAA==.Hutchknight:BAAANQAECgcICwABNQAECgoKJwAPACQaAA==.Hutchyo:BAAANQAECgEIAgABNQAECgoKJwAPACQaAA==.Hutchyr:BAAANQAECgEIAQABNQAECgoKJwAPACQaAA==.',
Hy='Hydro:BAAANQADCgcICQAAAA==.',
['Hä']='Häwtz:BAAANQAECgIIAgAAAA==.',
Ic='Icerus:BAAANQADCgcIBwAAAA==.Icirus:BAABNQAECn86AAMDAAoKzSA1AgARAwADAAoKzSA1AgARAwACAAQKkQqNSQGqAAAAAA==.',
Id='Idraven:BAAANQAECgEIAQAAAA==.',
Il='Illaandra:BAAANQADCgUIBQABNQAECgEIAQAMAAAAAA==.',
Im='Imsanity:BAAANQADCgQIBAAAAA==.',
In='Inseng:BAABNQAECn8ZAAMfAAoKcCCACQBRAwAfAAoKcCCACQBRAwATAAUKjhjGNQCgAAAAAA==.Invasion:BAAANQAECgEIAQAAAA==.',
It='Itzal:BAAANQAECgYIBgAAAA==.',
Ja='Jagere:BAABNQAECn8fAAIFAAkKCQ61dgAiAgAFAAkKCQ61dgAiAgAAAA==.Jahde:BAABNQAECn8UAAIVAAYK6wR0NACLAAAVAAYK6wR0NACLAAAAAA==.Jaina:BAAANQAECgYIEAAAAA==.Jandrae:BAABNQAECn83AAQfAAoKhRvuAgBoAgAfAAoKDRruAgBoAgAUAAUKFx6zYACNAQATAAIKqwfxuwBQAAAAAA==.Jassykins:BAAANQAECgUIDAAAAA==.',
Je='Jessecuster:BAAANQADCgQJBAAAAA==.',
Ji='Jillotty:BAAANQADCgUIBAAAAA==.Jirachii:BAAANQAECgEIAgABNQAECgoKMwAVALsVAA==.',
Jo='Joanofarc:BAAANQADCgUJBQAAAA==.Joloc:BAABNQAECn8fAAIYAAcKIg2zGACmAQAYAAcKIg2zGACmAQAAAA==.Jonpaul:BAAANQABCgEIAQAAAA==.',
Ju='Jueles:BAAANQADCgMIAwABNQAECgYIFAAVAOsEAA==.',
['Jì']='Jìnx:BAAANQADCgQIBQAAAA==.',
Ka='Kalrosa:BAAANQAECgUIEQABNQAECgkJKAARAMkWAA==.Kare:BAAANQAECgYIDgABNQAECgoKLgABAPsiAA==.Karee:BAABNQAECn8uAAIBAAoK+yIyAgCuAwABAAoK+yIyAgCuAwAAAA==.Karfren:BAAANQAECgEJAQAAAA==.Kauko:BAAANQAECggICAAAAA==.Kazer:BAAANQADCgYJBgAAAA==.',
Ke='Kermodk:BAABNQAECn8nAAITAAkKIyGTAwA1AgATAAkKIyGTAwA1AgAAAA==.',
Kh='Khold:BAABNQAECn8bAAIBAAgKCQ+7LAB3AQABAAgKCQ+7LAB3AQAAAA==.',
Ki='Kissofdeath:BAAANQAECgEIAQAAAA==.',
Ko='Koltara:BAABNQAECn8cAAIKAAkK6B0cGACcAgAKAAkK6B0cGACcAgABNQAFFAYIGQAEAO4WAA==.Koltarax:BAAANQAECgEIAQABNQAFFAYIGQAEAO4WAA==.Koltarian:BAAANQAFFAEIAQABNQAFFAYIGQAEAO4WAA==.Koltaros:BAAANQAECgQIBQABNQAFFAYIGQAEAO4WAA==.Konshis:BAABNQAECn8yAAIiAAoK1h8jBADUAQAiAAoK1h8jBADUAQAAAA==.Kookymonster:BAABNQAECn87AAMPAAoKjCDTBwCOAwAPAAoKjCDTBwCOAwAYAAIK+R/JRgCsAAAAAA==.Kos:BAACNQAFFH8YAAQfAAYK0BVFBQC6AQAfAAYKow9FBQC6AQAUAAUKqRywCwBSAQATAAEKAADIPQAYAAA1AAQKfzIAAx8ACgoBH3EcAKYCAB8ACgpBHnEcAKYCABQABQppHTRYALABAAAA.',
Kr='Krathos:BAAANQADCgYJCAAAAA==.Krax:BAAANQADCgEIAQAAAA==.Kruk:BAAANQADCggIGAAAAA==.',
Ku='Kuragaru:BAACNQAFFH8YAAIkAAYKuBXFAwAiAQAkAAYKuBXFAwAiAQA1AAQKfzAAAiQACgr8H78EAEIDACQACgr8H78EAEIDAAAA.',
La='Lala:BAAANQAECgYIBgAAAA==.Lapis:BAABNQAECn8pAAIbAAkK2iBKBQCLAgAbAAkK2iBKBQCLAgAAAA==.',
Le='Lester:BAABNQAECn8fAAIGAAgK7hf3HwA7AgAGAAgK7hf3HwA7AgAAAA==.Levina:BAABNQAECn8sAAMWAAkKWBaoHAC9AQAVAAkKUhX6NQA7AgAWAAgKChWoHAC9AQAAAA==.Lexysady:BAAANQAECggIEgAAAA==.',
Li='Liamsun:BAAANQADCggICAAAAA==.Lidrael:BAAANQADCgYIBgABNQAECgoKOQATAMUfAA==.Lidrahl:BAABNQAECn85AAITAAoKxR8ADABSAwATAAoKxR8ADABSAwAAAA==.Lilihunt:BAAANQADCgYIBgAAAA==.Liliria:BAABNQAECn8xAAIIAAoKLgwBaADnAQAIAAoKLgwBaADnAQAAAA==.Lillidân:BAAANQADCgUIBgABNQAECgoKMgAZABoeAA==.',
Lj='Ljaeì:BAAANQADCggICAAAAA==.',
Ll='Lloreth:BAABNQAECn8gAAIXAAcKYQ41EABHAQAXAAcKYQ41EABHAQAAAA==.',
Ln='Lnpoop:BAABNQAECn8zAAIXAAoKnR16AgCqAgAXAAoKnR16AgCqAgAAAA==.',
Lo='Loafs:BAAANQAECgcIBwAAAA==.Lockjauz:BAAANQADCgQIBgAAAA==.Lonaki:BAAANQADCgIIAgAAAA==.Lorelei:BAAANQAECgcICwAAAA==.Lorrellia:BAAANQADCgcIBwAAAA==.Lovekiller:BAAANQADCgEIAQAAAA==.',
Lu='Luc:BAABNQAECn8wAAIcAAkKtBxtAgAYAgAcAAkKtBxtAgAYAgAAAA==.Lucariõ:BAACNQAFFH8ZAAIIAAcKqhq+BQBCAgAIAAcKqhq+BQBCAgA1AAQKfy0AAggACgoJIYQYABQDAAgACgoJIYQYABQDAAAA.Lumina:BAAANQAECgcICwAAAA==.',
Ly='Lyllies:BAABNQAECn8wAAIFAAoK1B7eLADnAgAFAAoK1B7eLADnAgAAAA==.Lyv:BAAANQADCgYIBgABNQAECgEIAQAMAAAAAA==.',
Ma='Mafia:BAAANQADCggIEQAAAA==.Magnumrex:BAAANQADCgUIBQAAAA==.Maharette:BAAANQADCgMIAwAAAA==.Makkazul:BAABNQAECn8pAAIfAAkK2RB5HwAoAQAfAAkK2RB5HwAoAQAAAA==.Malgus:BAAANQADCgYIBgAAAA==.Matcauthon:BAAANQAECgEIAQAAAA==.Matrim:BAAANQADCggIEgAAAA==.Mattdæmon:BAABNQAECn8hAAMLAAcKnQVgHgDcAAAJAAYKcgYGXAATAQALAAcKMQNgHgDcAAAAAA==.',
Me='Meekogaia:BAABNQAECn9bAAMbAAoK1BVfSABAAgAbAAoK1BVfSABAAgANAAYKeBEyoABWAQAAAA==.Meekosan:BAAANQADCgcIBwAAAA==.',
Mi='Mijime:BAAANQADCgYIBgABNQAECgQIBAAMAAAAAA==.Millerowntoo:BAACNQAFFH8RAAMUAAYKJiLeAgAWAgAUAAUKJiLeAgAWAgATAAEKAABpOwAcAAA1AAQKfyIAAxQACQrRJPYLAFsDABQACAqhJvYLAFsDAB8AAQohGKZbAE8AAAAA.Millions:BAABNQAFFH8IAAIBAAUKuwbHBgAaAQABAAUKuwbHBgAaAQAAAA==.Mimzy:BAAANQADCgIIAgAAAA==.Mingzi:BAAANQADCgMIAwAAAA==.Minivan:BAAANQADCggICQAAAA==.Mital:BAAANQAECgEIAgAAAA==.',
Mj='Mjoln:BAAANQAECgQIBAAAAA==.',
Mo='Mobius:BAAANQADCggIFQABNQAECgcIHAAPAGgWAA==.Molvnma:BAAANQAECggIAQAAAA==.Monkeycoke:BAABNQAECn8cAAMPAAcKaBb3KwBEAQAPAAcKZRP3KwBEAQAOAAQKnxY9FAAHAQAAAA==.Montkriege:BAAANQAECgMIBQAAAA==.Moonwarden:BAAANQAECgEIAQAAAA==.',
Mu='Murfie:BAABNQAECn8cAAIGAAkKwRQtIgAjAgAGAAkKwRQtIgAjAgAAAA==.Murica:BAAANQADCgYICgABNQAECgkJNQAZAMUcAA==.',
My='Mythosrex:BAAANQADCgMIAwAAAA==.',
['Mì']='Mìr:BAAANQAFFAEIAQAAAA==.',
Na='Nashira:BAABNQAECn8jAAIbAAoKmBcsIABoAQAbAAoKmBcsIABoAQAAAA==.Nashness:BAABNQAECn8qAAMfAAoKGx1NHACoAgAfAAoKcBdNHACoAgAUAAgKayBMNwBJAgAAAA==.Naturdimund:BAAANQADCgMIAwAAAA==.Natures:BAAANQADCgEIAQAAAA==.',
Ne='Nerdvader:BAAANQADCgEJAQABNQAECgcIIQALAJ0FAA==.Nesquík:BAAANQADCgUIFgAAAA==.Nezar:BAAANQAECgcIEgAAAA==.',
Ni='Nicokira:BAAANQAECgEIAgAAAA==.Niis:BAABNQAECn8YAAMRAAgKSRANDQDnAQARAAgKSRANDQDnAQAQAAcKRwsAIQBFAQAAAA==.Niterage:BAABNQAECn8kAAIJAAcKxQQuWwAXAQAJAAcKxQQuWwAXAQAAAA==.',
Nn='Nn:BAABNQAECn8VAAIWAAcKmBJDEwDsAAAWAAcKmBJDEwDsAAAAAA==.',
No='Noseheirs:BAAANQADCgQIBAAAAA==.Notoriuspab:BAAANQAECgIJAwAAAA==.Noyar:BAAANQADCgMIAwAAAA==.',
Nu='Nuckinphutz:BAAANQADCgEIAQAAAA==.',
['Nè']='Nègan:BAABNQAECn8iAAIFAAkKehLKMQBbAQAFAAkKehLKMQBbAQAAAA==.',
['Nì']='Nìr:BAACNQAFFH8NAAIJAAYKlRI6BwDLAQAJAAYKlRI6BwDLAQA1AAQKfxQAAgkACAqEG1kMAI4BAAkACAqEG1kMAI4BAAAA.',
Od='Odinrex:BAABNQAECn8bAAIFAAcKvhSkKQB0AQAFAAcKvhSkKQB0AQAAAA==.',
Op='Opuntia:BAAANQAECgQICwAAAA==.',
Or='Orexion:BAAANQADCgUIBQAAAA==.',
Ow='Ownham:BAABNQAECn8VAAMDAAoKvhmTLgCsAgADAAoKvhmTLgCsAgACAAUK5xYX3ABjAQABNQAFFAYIEQAUACYiAA==.',
Pa='Paddingidiot:BAACNQAFFH8ZAAMEAAYK7hb9BwDKAQAEAAYKfhP9BwDKAQAFAAEKQxdLFABiAAA1AAQKfxwAAgQACgpQGGIWAKgCAAQACgpQGGIWAKgCAAAA.Pakez:BAAANQADCgIIAgAAAA==.Paladinheal:BAABNQAECn8gAAIDAAkKeRPbEgC8AQADAAkKeRPbEgC8AQAAAA==.Pallypaladin:BAACNQAFFH8RAAICAAYKdhC+CwCOAQACAAYKdhC+CwCOAQA1AAQKfzsAAgIACgqhIYsZAF4DAAIACgqhIYsZAF4DAAAA.Pardsz:BAAANQADCgYICAAAAA==.Partywolf:BAAANQAECgYIDwAAAA==.',
Ph='Phatzero:BAABNQAECn8tAAIFAAoKthq5GgAuAwAFAAoKthq5GgAuAwAAAA==.',
Pi='Pikas:BAAANQABCgIIAgAAAA==.Pinjo:BAAANQAECgcIDwAAAA==.',
Po='Polard:BAABNQAECn8dAAMWAAkKox5QBgAsAwAWAAgKjSNQBgAsAwAaAAIKiAGAUAASAAAAAA==.Pownown:BAAANQAECggICgABNQAFFAYIEQAUACYiAA==.',
Pr='Procreeper:BAAANQAECgMIAgABNQAECgoKJAAaABckAA==.',
Ps='Pseudonym:BAAANQAECgEIAgAAAA==.',
Pu='Pupper:BAABNQAECn8WAAISAAcKbhmWFwCpAQASAAcKbhmWFwCpAQABNQAECgoKJgASAFYdAA==.',
Ra='Rabit:BAAANQAECgUIBgAAAA==.Radio:BAAANQAECgQIBAAAAA==.Raennt:BAAANQADCgEIAQAAAA==.Rafïki:BAAANQADCgYIBgAAAA==.Rainstorm:BAAANQADCgcIBwAAAA==.Rainyblu:BAAANQAECgQIBAAAAA==.Rawrshåk:BAABNQAECn8qAAMSAAkKFx7cQgDBAgASAAkKUh3cQgDBAgARAAIKhhhTDQCgAAAAAA==.',
Rb='Rb:BAAANQAECgEIAwAAAA==.',
Rc='Rc:BAABNQAECn8fAAIcAAcKBhsHGAA7AgAcAAcKBhsHGAA7AgAAAA==.',
Re='Rennalla:BAAANQADCgcIBwABNQAECgoKOAAJAI0eAA==.',
Rh='Rhodraco:BAABNQAECn8UAAMlAAcK5wWtDQCEAAAlAAYKRgWtDQCEAAAmAAQKmQVCHgBvAAAAAA==.Rhownyn:BAAANQADCgQIBgAAAA==.Rhoxy:BAAANQADCggIEwAAAA==.',
Ri='Rikku:BAAANQADCgEIAQAAAA==.Ripforged:BAABNQAECn8jAAISAAgKThfGhQANAgASAAgKThfGhQANAgABNQAECggKIwASAE4XAA==.',
Rn='Rn:BAAANQAECgIIAgAAAA==.',
Ro='Rolgar:BAAANQADCgYIBwAAAA==.',
Rq='Rq:BAAANQAECgcICgAAAA==.',
Ry='Ryyukken:BAAANQAECgIIBQAAAA==.',
['Rà']='Ràwrshåk:BAAANQAECgEIAQAAAA==.',
Sa='Saella:BAAANQAECgQIBQAAAA==.Sakarja:BAAANQADCgQIBAAAAA==.Saluda:BAAANQAECgUIBwAAAA==.Samesde:BAAANQAECgQIDQAAAA==.Samras:BAAANQAECgQIBgAAAA==.Saphyria:BAAANQAECgEIAQAAAA==.Sarentu:BAACNQAFFH8GAAIjAAMKSxCGDADZAAAjAAMKSxCGDADZAAA1AAQKfyYAAiMACgolHS4RANcCACMACgolHS4RANcCAAAA.Satoru:BAAANQADCgUIBQAAAA==.',
Se='Seanjohn:BAAANQAECgEIAQAAAA==.Senile:BAABNQAECn8VAAInAAcKBBMiAQA3AQAnAAcKBBMiAQA3AQAAAA==.Sertia:BAAANQADCgEIAQAAAA==.Sesnic:BAAANQAECgQIDAAAAA==.',
Sh='Shadesoflife:BAAANQABCgMIAwAAAA==.Shadydice:BAAANQADCgYICwABNQADCgYIBgAMAAAAAA==.Shadydk:BAAANQADCgYIBwABNQADCgYIBgAMAAAAAA==.Shadylid:BAAANQADCgYIBgAAAA==.Shadysmash:BAAANQADCggIEAAAAA==.Shadyvoid:BAAANQAECgUIBwABNQADCgYIBgAMAAAAAA==.Shadówglider:BAAANQAECgMICQAAAA==.Shaelia:BAAANQADCgIIAgAAAA==.Shale:BAABNQAECn8aAAIKAAkKnx2bGQCNAgAKAAkKnx2bGQCNAgAAAA==.Shamallaman:BAAANQAECgUJCQABNQAECgoKHwACAJMgAA==.Shanck:BAAANQAECgUIBQAAAA==.Sharkweek:BAAANQAECgMIBAAAAA==.Shazám:BAAANQAECgIIAgAAAA==.Sheol:BAAANQADCggIFQAAAA==.Sheyoni:BAAANQADCggJGgAAAA==.Shydestroyer:BAAANQAECgEIAQAAAA==.',
Si='Siersha:BAAANQADCgEIAQAAAA==.Sinfulness:BAAANQAECgUIEQAAAA==.',
Sk='Skikette:BAABNQAECn8oAAIPAAkKkAZWYADBAAAPAAkKkAZWYADBAAAAAA==.Skinrot:BAABNQAECn8lAAIXAAoKgwuGLAC4AQAXAAoKgwuGLAC4AQAAAA==.',
Sm='Smig:BAAANQAECgUIDgAAAA==.',
Sn='Snowball:BAABNQAECn8WAAIQAAcKUxZCBQB2AQAQAAcKUxZCBQB2AQAAAA==.',
So='Soeki:BAAANQAECgcIEgAAAA==.Soluthon:BAAANQADCgQIBAAAAA==.Sonyaa:BAAANQADCgcICQAAAA==.Soullove:BAABNQAECn8kAAIYAAgK3xUNDwAKAgAYAAgK3xUNDwAKAgABNQAECgkJKAAXAMgWAA==.Soullovez:BAABNQAECn8oAAMXAAkKyBZMCgCTAQAXAAkKyBZMCgCTAQAVAAQKJQQRkQCTAAAAAA==.Soulshocks:BAABNQAECn8kAAINAAgKGQxUKAAbAQANAAgKGQxUKAAbAQABNQAECgkJKAAXAMgWAA==.Soulviver:BAABNQAECn8vAAIIAAkKXhGwJwBfAQAIAAkKXhGwJwBfAQAAAA==.',
Sp='Spiritwarden:BAABNQAECn8lAAIjAAoK/xqaEADfAgAjAAoK/xqaEADfAgAAAA==.Spliffy:BAAANQADCgQIBAAAAA==.Splootz:BAAANQADCggIEAABNQAFFAEIAQAMAAAAAA==.Spoiledbratt:BAAANQAECgEIAQAAAA==.',
Sq='Squirtdadday:BAAANQAECgIJAgAAAA==.',
St='Stargasm:BAAANQAECgEIAQAAAA==.Stimer:BAABNQAECn87AAQSAAoKaiWjCACuAwASAAoKoSOjCACuAwAQAAcKQiRqCADMAgARAAYKWSHODQDXAQAAAA==.Stori:BAAANQADCggIEQAAAA==.',
Su='Sunshiny:BAAANQADCgcIBwAAAA==.Suxor:BAAANQAECgQIDwAAAA==.',
Sw='Swordboardal:BAACNQAFFH8IAAIQAAMKMQ2JBQCoAAAQAAMKMQ2JBQCoAAA1AAQKfysAAhAACQrGFqkQAB0CABAACQrGFqkQAB0CAAAA.',
Sy='Sybius:BAAANQAECgQJCQAAAA==.Symptom:BAAANQAECgEIAgAAAA==.Syncophat:BAABNQAECn8aAAIFAAcK4xc3RQAqAQAFAAcK4xc3RQAqAQAAAA==.',
Ta='Tad:BAAANQAECgMIAwAAAA==.Taint:BAAANQADCgUICQAAAA==.Takia:BAAANQAECgMICwAAAA==.Talanzen:BAABNQAECn8bAAIZAAkKcyLwQQABAwAZAAkKcyLwQQABAwAAAA==.Talonia:BAAANQADCggICAABNQAECggIGwAFAMocAA==.Tanakiko:BAAANQADCgUIBQAAAA==.Tarrzok:BAAANQADCgcICAABNQADCgYIBgAMAAAAAA==.',
Te='Teacup:BAAANQAECgIICAABNQAECgoKHQAfAPUYAA==.',
Th='Thrakara:BAACNQAFFH8UAAMiAAYKjwTYBACCAQAiAAYKjwTYBACCAQAjAAMKPQwbDQDNAAA1AAQKfy8AAyIACQp/GcYRAGECACIACQp/GcYRAGECACMABApJHiI4AFMBAAAA.Thrakaru:BAABNQAECn8eAAIZAAkKihIymgBMAgAZAAkKihIymgBMAgAAAA==.Thrakumi:BAAANQADCgcIBwAAAA==.Thunderhorns:BAAANQAECgcIDAAAAA==.Thundrall:BAAANQAECgMIBgAAAA==.',
Ti='Tightspaces:BAAANQABCgMIAwAAAA==.Tiltéd:BAABNQAECn8kAAMdAAoKix3AAgAzAgAdAAkKix3AAgAzAgAkAAEKAACaYAAAAAAAAA==.Tioshadow:BAAANQAECgIIAwABNQAFFAQIBwAjADkSAA==.',
To='Tobaeus:BAAANQADCgUIBQAAAA==.Todem:BAAANQADCgEIAQAAAA==.Torches:BAAANQADCgcIBwAAAA==.Totemissues:BAAANQABCgMIAwABNQAECgoKLQAFALYaAA==.',
Tr='Trayleen:BAAANQADCgUJBQAAAA==.Triad:BAAANQADCgYJBgAAAA==.Truths:BAACNQAFFH8WAAISAAcKxB4vBQB8AgASAAcKxB4vBQB8AgA1AAQKfxwAAhIACgqfIYo1AOwCABIACgqfIYo1AOwCAAAA.Trystrom:BAAANQADCgYIDAAAAA==.',
Ts='Tsuo:BAAANQAECgcIDwAAAA==.Tsuoshock:BAAANQAECgUIBQAAAA==.',
Tx='Txblood:BAAANQADCgcICAAAAA==.Txgunny:BAABNQAECn8bAAISAAcKKQc2WADpAAASAAcKKQc2WADpAAAAAA==.Txstormin:BAAANQAECgEIAQAAAA==.',
Ty='Tymptriss:BAAANQAECgQIDQAAAA==.',
['Tí']='Títus:BAAANQAECgIIAgAAAA==.',
Um='Umbrage:BAAANQAECggIDwABNQAFFAYIGAAcALYYAA==.Umbren:BAABNQAECn8bAAMFAAgKyhwnWwBjAgAFAAgKyhwnWwBjAgAEAAEK3ABKoQAXAAAAAA==.',
Ur='Urabadkity:BAAANQADCgYIEQAAAA==.',
Us='Usefulmelee:BAAANQAECggIDwABNQAFFAYIGQAEAO4WAA==.',
Va='Valartha:BAAANQAECgMIDgAAAA==.Variste:BAAANQADCgMIAwAAAA==.',
Ve='Veil:BAAANQADCggJCAAAAA==.Velkån:BAAANQAECgEIAQAAAA==.Vellmora:BAAANQADCgUJBgAAAA==.Velsea:BAAANQAECgQIBQAAAA==.Velstadt:BAABNQAECn8kAAMjAAgKjhnSHQBGAgAjAAgKjhnSHQBGAgAhAAQKdxSAHwDuAAAAAA==.Venhance:BAAANQAECgcJEAAAAA==.Venotu:BAABNQAECn8hAAIBAAkK7htTDADUAgABAAkK7htTDADUAgAAAA==.Vermilion:BAAANQAECgUIBgAAAA==.Vertebrae:BAAANQADCgUIBQAAAA==.',
Vh='Vholatile:BAABNQAECn8WAAMOAAgKLw+/CAAAAgAOAAgKLw+/CAAAAgAYAAIKGgQTcwA8AAAAAA==.',
Vi='Violence:BAAANQADCgYIBgAAAA==.Viviel:BAAANQAECgcIIAAAAQ==.',
Vo='Voidherron:BAAANQAECgYIDwAAAA==.Voidknight:BAAANQAECgEIAQAAAA==.Voodoomama:BAAANQADCgYIEQAAAA==.',
Wa='Waq:BAAANQADCgUIBQAAAA==.Warlockbot:BAACNQAFFH8PAAIPAAUK1xK4EQBxAQAPAAUK1xK4EQBxAQA1AAQKfyMAAg8ACgqjG1czALwCAA8ACgqjG1czALwCAAAA.Warmongral:BAAANQADCgYIDwAAAA==.Waterboot:BAAANQADCgQIBwAAAA==.Wattheyneed:BAAANQAECgEIAwAAAA==.',
We='Wendi:BAABNQAECn8aAAIYAAcKQwc/JwA9AQAYAAcKQwc/JwA9AQAAAA==.',
Wh='Wholesome:BAAANQADCgcICwAAAA==.',
Wi='Wig:BAAANQADCggIEgABNQAECgoKJAAdAIsdAA==.Wildbill:BAAANQADCgYIBwAAAA==.Windcrow:BAAANQADCggICAAAAA==.Withher:BAAANQADCggICAAAAA==.',
Wo='Wombo:BAAANQAECgMIBQAAAA==.Woolala:BAABNQAECn82AAIFAAkKlxrWNwDDAgAFAAkKlxrWNwDDAgAAAA==.',
Wr='Wrahirn:BAAANQABCgYIBgAAAA==.Wrathran:BAAANQAECgIJAgAAAA==.',
Wu='Wut:BAAANQAECgcIBwABNQAECgkJMAAcALQcAA==.',
Xa='Xahiri:BAAANQADCgYIBgAAAA==.Xalisto:BAAANQADCgYICQAAAA==.',
Xl='Xlia:BAAANQAECgMIBQAAAA==.',
Ya='Yaana:BAAANQAECgEIAQAAAA==.Yazmyn:BAABNQAECn8XAAIhAAgK5QxbFgB+AQAhAAgK5QxbFgB+AQAAAA==.',
Ye='Yerehmi:BAAANQAECgEIAQAAAA==.',
Yu='Yuny:BAABNQAECn8nAAIiAAgKzhJGBwBtAQAiAAgKzhJGBwBtAQAAAA==.',
Za='Zaier:BAABNQAECn88AAMDAAoKbx0JKgC/AgADAAoKbx0JKgC/AgACAAYKfhB1/gAiAQAAAA==.',
Ze='Zeltan:BAABNQAECn9TAAIDAAoKgh9fEQBDAwADAAoKgh9fEQBDAwAAAA==.',
Zh='Zhundrenga:BAAANQAECgMICAAAAA==.',
Zo='Zoma:BAAANQADCgEIAQAAAA==.',
Zp='Zpad:BAAANQADCgcIBwAAAA==.',
['År']='Åres:BAAANQAECgEIAwAAAA==.',
['ßl']='ßlastvenom:BAAANQADCgYICQAAAA==.',
['ßä']='ßäbaracus:BAAANQADCgQIBAAAAA==.',
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
