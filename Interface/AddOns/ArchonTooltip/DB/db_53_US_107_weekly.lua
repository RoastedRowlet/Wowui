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

local lookup = {'Paladin-Protection','Paladin-Retribution','Paladin-Holy','Priest-Shadow','Priest-Discipline','Priest-Holy','Hunter-BeastMastery','DemonHunter-Havoc','DemonHunter-Devourer','DemonHunter-Vengeance','Warrior-Protection','Warrior-Fury','Warrior-Arms','DeathKnight-Blood','DeathKnight-Unholy','Druid-Balance','Druid-Guardian','Druid-Restoration','Unknown-Unknown','Warlock-Destruction','Warlock-Demonology','Mage-Arcane','DeathKnight-Frost','Druid-Feral','Shaman-Restoration','Evoker-Preservation','Rogue-Assassination','Hunter-Marksmanship','Shaman-Elemental','Shaman-Enhancement','Monk-Brewmaster','Monk-Mistweaver','Monk-Windwalker','Mage-Frost','Rogue-Subtlety','Warlock-Affliction',}
local provider = {region='US',realm='Gilneas',name='US',type='weekly',zone=53,date='2026-10-13',data={Ac='Acks:BAAANQADCgYICgABNQAFFAUIBwABALsGAA==.',
Ae='Aedra:BAAANQAECgIIAgAAAA==.Aeowyyn:BAABNQAECn8VAAMCAAgKjgqG+QAlAQACAAcKVQaG+QAlAQADAAIKgQWZCQFeAAAAAA==.Aex:BAAANQAECgcIEgABNQAFFAUIBwABALsGAA==.',
Af='Afib:BAAANQADCgQIBAAAAA==.',
Ah='Ahnkhano:BAAANQAECgYIBgAAAA==.',
Ai='Ainge:BAAANQAECgEIAQAAAA==.Airiistra:BAAANQADCgMIAwAAAA==.',
Ak='Akbartheiiv:BAACNQAFFH8XAAMEAAcK7xslAgByAgAEAAcK7xslAgByAgAFAAEKFgJJBABEAAA1AAQKf0IAAwQACQpsJpgAAPMDAAQACQpsJpgAAPMDAAUACArUJBcBAFkDAAAA.Akorius:BAAANQAECgIIAgAAAA==.',
Al='Alarion:BAAANQABCgYICAAAAA==.Allistrana:BAABNQAECn8cAAIGAAcK/B4XQQBjAgAGAAcK/B4XQQBjAgAAAA==.Allpower:BAAANQADCgYIDgAAAA==.Alpacalyptic:BAAANQAECgYIBgAAAA==.Alyx:BAAANQADCgcIBwAAAA==.',
Am='Amadeux:BAAANQADCgIIAgABNQAECgcIGgAHABoeAA==.Amairis:BAAANQAECgQIDQAAAA==.Ambiorix:BAAANQABCgIIAgAAAA==.',
An='Anrion:BAABNQAECn8vAAQIAAkKdB+rEAAYAwAIAAkKXR+rEAAYAwAJAAYKohZqOwBmAQAKAAIKZCPtIQCvAAAAAA==.Antiflag:BAAANQAECgYIBgAAAA==.Anzania:BAAANQADCgEIAQAAAA==.',
Ar='Arolz:BAAANQADCgYIBgAAAA==.',
At='Ataliya:BAAANQAECgUIDQAAAA==.',
Au='Auranar:BAAANQAECgQICgAAAA==.Aurelya:BAABNQAECn8kAAIGAAcKsw5FgQCPAQAGAAcKsw5FgQCPAQAAAA==.Aurilia:BAAANQAECgIIBQAAAA==.',
Av='Avanicus:BAAANQAECgYIEwAAAA==.Aven:BAAANQAECgEIAQAAAA==.Avernas:BAAANQAECgQIBAAAAA==.Avé:BAABNQAECn8dAAMCAAgKhQ5BtQCuAQACAAgKvQ1BtQCuAQABAAQKRA0fTQCwAAAAAA==.',
Ax='Axellent:BAACNQAFFH8GAAILAAMKvhDnBAC/AAALAAMKvhDnBAC/AAA1AAQKfxsABAwACApDHB4SAH8BAAwABQq/Gh4SAH8BAA0ABQoDGU/HAGQBAAsABQrtGDYeAF4BAAE1AAUUBQgHAAEAuwYA.Axiomlegacy:BAABNQAECn8lAAMOAAkKhyHcDQBAAwAOAAkKhyHcDQBAAwAPAAEKpwiX4wAuAAAAAA==.',
Az='Azraith:BAAANQADCgcIBgAAAA==.Azulien:BAAANQAECgYIDQAAAA==.Azulin:BAAANQADCgUJBQAAAA==.',
Ba='Banderblitz:BAABNQAECn8gAAMMAAgKdxbxDQDSAQANAAgKLhL1iwD6AQAMAAYKyBrxDQDSAQAAAA==.Banzgrave:BAAANQADCgcIBwAAAA==.Bar:BAABNQAECn8dAAMEAAkKZRlRJAALAgAEAAgKjBhRJAALAgAGAAgKTQsfhwB9AQAAAA==.',
Be='Bearlyshady:BAABNQAECn8wAAQQAAkKHhqUHgDTAgAQAAkKHhqUHgDTAgARAAQK9gk8QQCrAAASAAEKugNIdwAsAAABNQADCgYIBgATAAAAAA==.Bellarina:BAAANQAECgQIBgAAAA==.Bellatrixie:BAAANQAECgQIDwAAAA==.Bennitely:BAAANQADCgEIAQAAAA==.Beriadhwen:BAAANQADCggIEQAAAA==.Bermy:BAABNQAECn8aAAMUAAgKrQnTFgC1AQAUAAgKrQnTFgC1AQAVAAQKrgU1DwGmAAAAAA==.Berzerkercow:BAAANQADCgYIBwAAAA==.Bewildert:BAAANQADCgMIBAAAAA==.',
Bh='Bhawkwco:BAAANQADCgUIBQAAAA==.',
Bi='Bigjaina:BAABNQAECn8uAAIWAAkKxRzTWADOAgAWAAkKxRzTWADOAgAAAA==.Biku:BAAANQAECgMIBgAAAA==.Bitesthesky:BAAANQAECgUIBQAAAA==.',
Bl='Blackhawkdk:BAABNQAECn8mAAMPAAkK4xq+KgCJAgAPAAkK4xq+KgCJAgAOAAEKAADmwwA9AAAAAA==.Blackhawkm:BAAANQADCgcIBwAAAA==.Blende:BAAANQAECgQIBQAAAA==.Blindwarrior:BAAANQAECgIIAgAAAA==.Bloodshadow:BAAANQAECgYIEwAAAA==.',
Bo='Boraffe:BAAANQADCgMJAgAAAA==.Bovinity:BAAANQABCgcICgAAAA==.',
Br='Breakcooloz:BAAANQAECgQIBgABNQAFFAUIBQAPAJoTAA==.Bretcoe:BAAANQADCgYIDAABNQAECgIJAgATAAAAAA==.Bronzamdee:BAAANQADCggJCAAAAA==.Brooce:BAABNQAECn8iAAICAAgKLRu6XgB5AgACAAgKLRu6XgB5AgAAAA==.Broom:BAAANQAECgQIBQABNQAECgkJLgAWAMUcAA==.Brozken:BAAANQADCgUICAAAAA==.Brutak:BAAANQADCggICAAAAA==.',
Bu='Burstinurass:BAACNQAFFH8FAAIPAAUKmhOkCACMAQAPAAUKmhOkCACMAQA1AAQKfxcAAg8ACQpbHgkcAOICAA8ACQpbHgkcAOICAAAA.Buzzliteyear:BAAANQADCgUIBQAAAA==.',
['Bä']='Bängbäng:BAAANQADCgYICgAAAA==.',
Ca='Caelix:BAAANQAECgMIAwAAAA==.Canadiana:BAAANQADCgYIBgAAAA==.Carafe:BAAANQADCgEIAQABNQAECggIFgAXAGUZAA==.Carbo:BAAANQAECgYIBgABNQAECgkJIwAYABQkAA==.Carbonight:BAABNQAECn8jAAIYAAkKFCS6AwBeAwAYAAkKFCS6AwBeAwAAAA==.',
Ce='Celani:BAAANQADCggICAABNQAECggIFgAZACENAA==.Celintha:BAAANQADCgEIAQAAAA==.Cellyne:BAAANQAECgQICQAAAA==.',
Ch='Chaoswind:BAABNQAECn8uAAIZAAkK7hoYLQCrAgAZAAkK7hoYLQCrAgAAAA==.Charlee:BAAANQAECgYIBgAAAA==.Chaz:BAAANQAECgIIAgAAAA==.Cheeb:BAAANQADCgcIBwAAAA==.Cheebie:BAAANQABCgYIBgABNQADCgcIBwATAAAAAA==.Chelives:BAEANQAECgUIEAAAAA==.Chromus:BAACNQAFFH8SAAIaAAYK9BMcBwDYAQAaAAYK9BMcBwDYAQA1AAQKfyUAAhoACQqLHFMNANACABoACQqLHFMNANACAAAA.',
Ci='Cires:BAABNQAECn8fAAIbAAgK5RGFLwAgAgAbAAgK5RGFLwAgAgAAAA==.',
Co='Colanasou:BAAANQAECgIIBAAAAA==.Coldbattler:BAAANQAECgQIBwAAAA==.Convictions:BAAANQAECgYICwABNQAFFAcIFgANAMQeAA==.Corrick:BAAANQAECgIIBAAAAA==.Cowpatty:BAAANQADCgQIBAAAAA==.',
Cr='Crow:BAAANQAFFAUIDgAAAQ==.',
Cy='Cydric:BAAANQAECggIEwAAAA==.',
Da='Daarrkstar:BAAANQAECgQIBAABNQAECgQIBQATAAAAAA==.Dakaryn:BAAANQADCggIDQAAAA==.Damageguy:BAAANQAECgYIBgABNQAFFAYIFAANAJwfAA==.',
De='Deadskvll:BAAANQADCgYIBgAAAA==.Deathbattler:BAAANQADCgcIEQAAAA==.Deathrival:BAAANQADCggICAAAAA==.Dehnis:BAAANQADCgQIBAAAAA==.Delta:BAAANQADCgYICwAAAA==.Demonkare:BAAANQAECgUICgABNQAECgkJJQABABokAA==.Demoray:BAACNQAFFH8kAAMcAAcKryFZBAAqAgAcAAYKdSFZBAAqAgAHAAEKmSJKLQBmAAA1AAQKfyUAAxwACQraJUUGAGsDABwACQraJUUGAGsDAAcAAQr5GLFJAUUAAAAA.Demvinity:BAAANQAECgIIAwAAAA==.Dethrone:BAABNQAECn8YAAMVAAkKahcGXwA3AgAVAAgKQBYGXwA3AgAUAAIKnRo/TACZAAAAAA==.Deus:BAABNQAECn80AAMEAAcKXhOyKgDOAQAEAAcKXhOyKgDOAQAFAAUKNhXZDgA9AQAAAA==.',
Di='Dinosocks:BAACNQAFFH8PAAMHAAcK8AwyEABSAQAHAAQKwhIyEABSAQAcAAQKPAMOFAD5AAA1AAQKfywAAwcACQr7FvZyACgCAAcABwoAG/ZyACgCABwACAq7Dzc0AKgBAAAA.Dirtydragon:BAABNQAECn8cAAIaAAgKHBz3EACZAgAaAAgKHBz3EACZAgAAAA==.Divinedecay:BAAANQAECgUIDQABNQAECgkJKgAHAL4cAA==.',
Dj='Djaequitas:BAAANQABCgQIBgAAAA==.Djmelisandra:BAAANQABCgQIBAAAAA==.Djshamy:BAAANQABCgUICAAAAA==.',
Do='Dok:BAAANQADCgYICQAAAA==.Donoraginn:BAAANQADCggINAAAAA==.Donos:BAAANQADCggIKgABNQADCggINAATAAAAAA==.Dontkare:BAAANQADCgMIAwABNQAECgkJJQABABokAA==.Dorsai:BAAANQADCgUIBQAAAA==.Dotgenerate:BAAANQAECgQIBQAAAA==.',
Dr='Dracorex:BAAANQABCgIIAgAAAA==.Drark:BAAANQAECgEIAQAAAA==.Drathiel:BAAANQAECgEIAQAAAA==.Drwho:BAAANQAECgYIDwAAAA==.Dräëxx:BAAANQADCgcIBwAAAA==.Drëëxx:BAAANQAECgEIAQAAAA==.',
Du='Duckymet:BAAANQADCggIDwAAAA==.',
Dy='Dyane:BAAANQADCgQIBAAAAA==.',
['Dî']='Dîxon:BAAANQAECgIIAgABNQAFFAUIBQAPAJoTAA==.',
['Dô']='Dôz:BAAANQAECgQIBwAAAA==.',
Ed='Edoaldor:BAAANQADCgUIBgAAAA==.',
El='Ellery:BAAANQADCgUJBQAAAA==.',
Em='Empyrean:BAAANQAECgQIBQAAAA==.',
Ex='Exhumina:BAAANQAECgMIBwAAAA==.',
Fa='Facestealerr:BAAANQAECgIIAwAAAA==.',
Fe='Felgibson:BAAANQADCgYIDQAAAA==.Fenmoon:BAABNQAECn8ZAAIQAAcK9gzhaQAgAQAQAAcK9gzhaQAgAQAAAA==.',
Fi='Finneaa:BAAANQADCgUIBQAAAA==.',
Fl='Flairrick:BAAANQAECgUIDQAAAA==.Flars:BAABNQAECn8kAAIXAAkKeyMdBgB+AwAXAAkKeyMdBgB+AwAAAA==.Flatliner:BAABNQAECn8ZAAIDAAgKPgdviAB/AQADAAgKPgdviAB/AQAAAA==.Flik:BAAANQAECgYIEQABNQAFFAUIBwABALsGAA==.',
Fo='Forq:BAAANQADCgcICAAAAA==.',
Fr='Frakz:BAAANQADCgUIBQAAAA==.Fran:BAAANQADCgYIBgABNQAECgkJLgAWAMUcAA==.Frankzappn:BAABNQAECn8dAAQdAAgKJBzqOQCLAgAdAAgKJBzqOQCLAgAeAAIKcBMzLQCNAAAZAAIK6AEkEgE/AAAAAA==.Fray:BAAANQADCggICAAAAA==.Freeguy:BAABNQAECn8nAAIJAAgK2BerIABFAgAJAAgK2BerIABFAgAAAA==.Fruitcakes:BAABNQAECn8XAAQfAAYKngR1IwC2AAAfAAUKywN1IwC2AAAgAAUKLwVcNwCtAAAhAAQK4gMYWQB8AAAAAA==.',
Fu='Fuddicus:BAAANQAECgEIAQAAAA==.Fuddrael:BAABNQAECn8aAAIKAAgKmAr9FQBIAQAKAAgKmAr9FQBIAQAAAA==.Fuddrucker:BAAANQAECgIIAgAAAA==.Fuddster:BAAANQADCgQIBAAAAA==.',
Ga='Gaddess:BAAANQAECgUIEAAAAA==.Gandàlf:BAAANQADCgYIBgAAAA==.Ganymede:BAAANQAECgMIAwAAAA==.Garan:BAAANQADCgMIAwAAAA==.',
Ge='Geilamaine:BAABNQAECn8bAAIDAAgK5hUfVAAbAgADAAgK5hUfVAAbAgAAAA==.',
Gl='Glimagi:BAAANQAECgIIBQAAAA==.',
Gn='Gnxr:BAEANQAECgIIAgABNQAFFAIIBgAhALsiAA==.',
Go='Gonefishing:BAAANQADCgYIBgABNQAECgkJMAAHAP8ZAA==.Gotêtsu:BAAANQADCggIEQAAAA==.',
Gr='Grimjawz:BAABNQAECn8nAAISAAkKBRvaEQC/AgASAAkKBRvaEQC/AgAAAA==.Grippysocks:BAAANQAFFAIIAgABNQAFFAcIDwAHAPAMAA==.',
Gu='Gummibear:BAABNQAECn8VAAMLAAUK6AwtKQDtAAALAAUK6AwtKQDtAAANAAEK+wTNUAExAAAAAA==.',
Gw='Gwiyomi:BAAANQAECgIIAgABNQAECggIEQATAAAAAA==.',
Gy='Gyr:BAAANQAECgIIAgAAAA==.',
Ha='Hanbor:BAAANQADCgcIBwAAAA==.Haniku:BAAANQAECgYIEQAAAA==.Harthoon:BAACNQAFFH8RAAIWAAYKNAcWFwC6AQAWAAYKNAcWFwC6AQA1AAQKfywAAyIACQpzHPMKABMCABYACQpLEKabAEgCACIACAqAHvMKABMCAAAA.',
He='Henos:BAAANQADCgMIAwAAAA==.',
Ho='Hobomatt:BAAANQADCggICAAAAA==.Holiebelle:BAAANQAECgUIDQAAAA==.Holyhutch:BAAANQAECgQIBAABNQAECgkJHgAVAIMWAA==.Holyshield:BAAANQADCgEIAQABNQAECgkJJQAGAIocAA==.Honeynoats:BAABNQAECn8lAAIGAAgKiQlfgwCIAQAGAAgKiQlfgwCIAQAAAA==.Hotdwarf:BAABNQAECn8XAAMDAAYKAA72uQAEAQADAAUKbQv2uQAEAQABAAUKlAe5RwDLAAAAAA==.',
Hr='Hrumm:BAACNQAFFH8RAAIcAAYKJQ5bCAC/AQAcAAYKJQ5bCAC/AQA1AAQKfyUAAxwACQo4GqIYAJACABwACQo4GqIYAJACAAcABQpuCh8JAe4AAAAA.',
Hu='Hullkk:BAACNQAFFH8UAAINAAYKnB+fBgBTAgANAAYKnB+fBgBTAgA1AAQKfykAAg0ACQqdJekPAH4DAA0ACQqdJekPAH4DAAAA.Hush:BAAANQAECgMIAgAAAA==.Hutchadina:BAAANQADCgIIAgAAAA==.Hutchkins:BAABNQAECn8eAAIVAAkKgxYVOQCmAgAVAAkKgxYVOQCmAgAAAA==.Hutchknight:BAAANQAECgYICAABNQAECgkJHgAVAIMWAA==.Hutchyo:BAAANQADCgUIBQABNQAECgkJHgAVAIMWAA==.',
Hy='Hydro:BAAANQADCgcICQAAAA==.',
['Hä']='Häwtz:BAAANQAECgIIAgAAAA==.',
Ic='Icerus:BAAANQADCgcIBwAAAA==.Icirus:BAABNQAECn8yAAMDAAkKiB6tFwAbAwADAAkKiB6tFwAbAwACAAQKkQq+RAGqAAAAAA==.',
Il='Illaandra:BAAANQADCgUIBQABNQAECgEIAQATAAAAAA==.',
Im='Imsanity:BAAANQADCgQIBAAAAA==.',
In='Inseng:BAAANQAECggIEQAAAA==.',
It='Itzal:BAAANQAECgYIBgAAAA==.',
Ja='Jagere:BAABNQAECn8cAAIHAAkKvg0FdQAjAgAHAAkKvg0FdQAjAgAAAA==.Jahde:BAAANQAECgQIDQAAAA==.Jaina:BAAANQAECgQICQAAAA==.Jandrae:BAABNQAECn8tAAQXAAkKJRzaGQC5AgAXAAkKdxraGQC5AgAPAAUKFx7BXwCNAQAOAAIKqwdIugBQAAAAAA==.Jassykins:BAAANQAECgUICwAAAA==.',
Je='Jessecuster:BAAANQADCgQJBAAAAA==.',
Ji='Jiffypop:BAAANQADCgMIAwABNQAECgMIAgATAAAAAA==.Jillotty:BAAANQADCgUIBAAAAA==.Jirachii:BAAANQADCgcICQABNQAECggIJwAQAF4XAA==.',
Jo='Joanofarc:BAAANQADCgUJBQAAAA==.Joloc:BAABNQAECn8fAAIUAAcKIg2IGACmAQAUAAcKIg2IGACmAQAAAA==.',
Ju='Jueles:BAAANQADCgMIAwABNQAECgQIDQATAAAAAA==.',
['Jì']='Jìnx:BAAANQADCgQIBQAAAA==.',
Ka='Kalrosa:BAAANQAECgQIDAABNQAECggIIAAMAHcWAA==.Kare:BAAANQAECgYIDQABNQAECgkJJQABABokAA==.Karee:BAABNQAECn8lAAIBAAkKGiQuAgCuAwABAAkKGiQuAgCuAwAAAA==.Karfren:BAAANQAECgEJAQAAAA==.Kauko:BAAANQAECggICAAAAA==.Kazer:BAAANQADCgYJBgAAAA==.',
Ke='Kermodk:BAABNQAECn8gAAIOAAgK/SCSFgD2AgAOAAgK/SCSFgD2AgAAAA==.',
Kh='Khold:BAABNQAECn8ZAAIBAAcKEBAiLAB4AQABAAcKEBAiLAB4AQAAAA==.',
Ki='Kissofdeath:BAAANQADCgIIAgAAAA==.',
Ko='Koltara:BAABNQAECn8ZAAIJAAgKyR+4FwCdAgAJAAgKyR+4FwCdAgABNQAFFAYIFAAcAH4TAA==.Koltarax:BAAANQAECgEIAQABNQAFFAYIFAAcAH4TAA==.Koltarian:BAAANQAECgYIBgABNQAFFAYIFAAcAH4TAA==.Koltaros:BAAANQAECgQIBAABNQAFFAYIFAAcAH4TAA==.Konshis:BAABNQAECn8sAAIgAAgKUyBUCgDgAgAgAAgKUyBUCgDgAgAAAA==.Kookymonster:BAABNQAECn80AAMVAAkKoSKKBwCPAwAVAAkKoSKKBwCPAwAUAAIK+R9MRgCsAAAAAA==.Kos:BAACNQAFFH8SAAQXAAYK0BUCBQC7AQAXAAYKow8CBQC7AQAPAAQKqRyJCwBSAQAOAAEKAADwPAAYAAA1AAQKfy4AAxcACQp5IPwbAKcCABcACQqeH/wbAKcCAA8ABQppHXdXAK8BAAAA.',
Kr='Krathos:BAAANQADCgYJCAAAAA==.Krax:BAAANQADCgEIAQAAAA==.Kruk:BAAANQADCgcIEAAAAA==.',
Ku='Kuragaru:BAACNQAFFH8SAAIjAAUK1RqMBQDCAQAjAAUK1RqMBQDCAQA1AAQKfywAAiMACQqrILsEAEIDACMACQqrILsEAEIDAAAA.',
La='Lala:BAAANQADCgYIBgAAAA==.Lapis:BAABNQAECn8hAAIZAAkKhB4wFwAXAwAZAAkKhB4wFwAXAwAAAA==.',
Le='Lester:BAABNQAECn8eAAIEAAcK1BmeHwA7AgAEAAcK1BmeHwA7AgAAAA==.Levina:BAABNQAECn8rAAMRAAkKWBYqHAC8AQAQAAkKUhVuNQA7AgARAAgKChUqHAC8AQAAAA==.Lexysady:BAAANQAECgcIDgAAAA==.',
Li='Lidrael:BAAANQADCgYIBgABNQAECgkJMAAOALYhAA==.Lidrahl:BAABNQAECn8wAAIOAAkKtiHbCwBSAwAOAAkKtiHbCwBSAwAAAA==.Lilihunt:BAAANQADCgYIBgAAAA==.Liliria:BAABNQAECn8oAAIGAAkKHgzCZgDnAQAGAAkKHgzCZgDnAQAAAA==.Lillidân:BAAANQADCgUIBgABNQAECgkJLgAWAAodAA==.',
Lj='Ljaeì:BAAANQADCggICAAAAA==.',
Ll='Lloreth:BAABNQAECn8aAAISAAcKGAq6OwA+AQASAAcKGAq6OwA+AQAAAA==.',
Ln='Lnpoop:BAABNQAECn8rAAISAAkK4xsSDwDhAgASAAkK4xsSDwDhAgAAAA==.',
Lo='Loafs:BAAANQAECgcIBwAAAA==.Lockjauz:BAAANQADCgQIBgAAAA==.Lonaki:BAAANQADCgIIAgAAAA==.Lorelei:BAAANQAECgUICAAAAA==.Lovekiller:BAAANQADCgEIAQAAAA==.',
Lu='Luc:BAABNQAECn8pAAIaAAkK8xpQDADeAgAaAAkK8xpQDADeAgAAAA==.Lucariõ:BAACNQAFFH8XAAIGAAYK9R1vBQBCAgAGAAYK9R1vBQBCAgA1AAQKfywAAgYACQoMJBQYABUDAAYACQoMJBQYABUDAAAA.Lumina:BAAANQAECgUIBgAAAA==.',
Ly='Lyllies:BAABNQAECn8nAAIHAAkKFSAbLADoAgAHAAkKFSAbLADoAgAAAA==.Lyv:BAAANQADCgYIBgABNQAECgEIAQATAAAAAA==.',
Ma='Mafia:BAAANQADCggIEQAAAA==.Magnumrex:BAAANQADCgUIBQAAAA==.Maharette:BAAANQADCgMIAwAAAA==.Makkazul:BAABNQAECn8jAAIXAAgK6hFbOgDiAQAXAAgK6hFbOgDiAQAAAA==.Malgus:BAAANQADCgYIBgAAAA==.Matcauthon:BAAANQAECgEIAQAAAA==.Matrim:BAAANQADCggIEQAAAA==.Mattdæmon:BAABNQAECn8gAAMKAAcKnQUIHgDcAAAIAAYKcgblWgATAQAKAAcKMQMIHgDcAAAAAA==.',
Me='Meekogaia:BAABNQAECn9TAAMZAAkK1hWGRwBBAgAZAAkK1hWGRwBBAgAdAAYKeBERngBXAQAAAA==.Meekosan:BAAANQADCgcIBwAAAA==.',
Mi='Mijime:BAAANQADCgYIBgABNQADCggICAATAAAAAA==.Millerowntoo:BAACNQAFFH8RAAMPAAYKJiLHAgAWAgAPAAUKJiLHAgAWAgAOAAEKAACXOgAcAAA1AAQKfx8AAg8ACAqhJtMLAFsDAA8ACAqhJtMLAFsDAAAA.Millions:BAABNQAFFH8HAAIBAAUKuwacBgAaAQABAAUKuwacBgAaAQAAAA==.Mimzy:BAAANQADCgIIAgAAAA==.Mingzi:BAAANQADCgMIAwAAAA==.Minivan:BAAANQADCggICQAAAA==.Mital:BAAANQABCgYICwAAAA==.',
Mj='Mjoln:BAAANQADCggICAAAAA==.',
Mo='Mobius:BAAANQADCggIFQABNQAECgUIEAATAAAAAA==.Molvnma:BAAANQAECggIAQAAAA==.Monkeycoke:BAAANQAECgUIEAAAAA==.Montkriege:BAAANQAECgIIAgAAAA==.',
Mu='Murfie:BAABNQAECn8aAAIEAAgKDxbgIQAjAgAEAAgKDxbgIQAjAgAAAA==.Murica:BAAANQADCgYICgABNQAECgkJLgAWAMUcAA==.',
My='Mythosrex:BAAANQADCgMIAwAAAA==.',
Na='Nashira:BAABNQAECn8dAAIZAAkKaxfmPQBmAgAZAAkKaxfmPQBmAgAAAA==.Nashness:BAABNQAECn8mAAMXAAkKXB/YGwCoAgAXAAkK4RjYGwCoAgAPAAgKayCkNgBKAgAAAA==.Naturdimund:BAAANQADCgMIAwAAAA==.Natures:BAAANQADCgEIAQAAAA==.',
Ne='Nerdvader:BAAANQADCgEJAQABNQAECgcIIAAKAJ0FAA==.Nesquík:BAAANQADCgUIFgAAAA==.Nezar:BAAANQAECgUICwAAAA==.',
Ni='Nicokira:BAAANQAECgEIAQAAAA==.Niis:BAABNQAECn8YAAMMAAgKSRDvDADnAQAMAAgKSRDvDADnAQALAAcKRwuCIABFAQAAAA==.Niterage:BAABNQAECn8eAAIIAAcKSQQPWgAXAQAIAAcKSQQPWgAXAQAAAA==.',
Nn='Nn:BAAANQAECgUIDQAAAA==.',
No='Noseheirs:BAAANQADCgQIBAAAAA==.Notoriuspab:BAAANQAECgIJAwAAAA==.Noyar:BAAANQADCgMIAwAAAA==.',
Nu='Nuckinphutz:BAAANQADCgEIAQAAAA==.',
['Nè']='Nègan:BAABNQAECn8cAAIHAAgKQRRtYQBRAgAHAAgKQRRtYQBRAgAAAA==.',
['Nì']='Nìr:BAABNQAFFH8JAAIIAAYKvxECBwDLAQAIAAYKvxECBwDLAQAAAA==.',
Od='Odinrex:BAAANQAECggIEgAAAA==.',
Op='Opuntia:BAAANQAECgIIBQAAAA==.',
Or='Orexion:BAAANQADCgUIBQAAAA==.',
Ow='Ownham:BAAANQAECggIEgABNQAFFAYIEQAPACYiAA==.',
Pa='Paddingidiot:BAACNQAFFH8UAAIcAAYKfhPMBwDKAQAcAAYKfhPMBwDKAQA1AAQKfxgAAhwACQp4GxUWAKgCABwACQp4GxUWAKgCAAAA.Pakez:BAAANQADCgIIAgAAAA==.Paladinheal:BAABNQAECn8YAAIDAAcKHxOUcADDAQADAAcKHxOUcADDAQAAAA==.Pallypaladin:BAACNQAFFH8QAAICAAUKXRRwCwCOAQACAAUKXRRwCwCOAQA1AAQKfzgAAgIACQovI9sYAF8DAAIACQovI9sYAF8DAAAA.Pardsz:BAAANQADCgYICAAAAA==.Partywolf:BAAANQAECgQICQAAAA==.',
Ph='Phatzero:BAABNQAECn8qAAIHAAkKvhwTGgAvAwAHAAkKvhwTGgAvAwAAAA==.',
Pi='Pinjo:BAAANQAECgcIDAAAAA==.',
Po='Polard:BAABNQAECn8bAAMRAAgKjSM5BgArAwARAAgKjSM5BgArAwAYAAEK5AFCTgASAAAAAA==.Pownown:BAAANQAECgYICAABNQAFFAYIEQAPACYiAA==.',
Pr='Procreeper:BAAANQAECgEIAQABNQAECgkJIwAYABQkAA==.',
Ps='Pseudonym:BAAANQABCgMIAwAAAA==.',
Pu='Pupper:BAAANQAECgcIDwABNQAECgkJHQANAK0cAA==.',
Ra='Rabit:BAAANQAECgEIAQAAAA==.Radio:BAAANQAECgQIBAAAAA==.Raennt:BAAANQADCgEIAQAAAA==.Rafïki:BAAANQADCgYIBgAAAA==.Rainstorm:BAAANQADCgcIBwAAAA==.Rainyblu:BAAANQAECgQIBAAAAA==.Rawrshåk:BAABNQAECn8nAAINAAgKER+SQQDCAgANAAgKER+SQQDCAgAAAA==.',
Rb='Rb:BAAANQAECgEIAwAAAA==.',
Rc='Rc:BAABNQAECn8fAAIaAAcKBhvgFwA7AgAaAAcKBhvgFwA7AgAAAA==.',
Rh='Rhodraco:BAAANQAECgUIDQAAAA==.Rhownyn:BAAANQADCgQIBgAAAA==.Rhoxy:BAAANQADCggIEwAAAA==.',
Ri='Rikku:BAAANQADCgEIAQAAAA==.Ripforged:BAABNQAECn8hAAINAAgKThcGhAAOAgANAAgKThcGhAAOAgABNQAECggKIQANAE4XAA==.',
Rn='Rn:BAAANQAECgIIAgAAAA==.',
Ro='Rolgar:BAAANQADCgYIBwAAAA==.',
Rq='Rq:BAAANQAECgcICgAAAA==.',
Ry='Ryyukken:BAAANQAECgIIAwAAAA==.',
['Rà']='Ràwrshåk:BAAANQAECgEIAQAAAA==.',
Sa='Saella:BAAANQAECgEIAQAAAA==.Sakarja:BAAANQADCgQIBAAAAA==.Saluda:BAAANQAECgIIAgAAAA==.Samesde:BAAANQAECgQICAAAAA==.Samras:BAAANQAECgQIBQAAAA==.Saphyria:BAAANQABCgIIAgAAAA==.Sarentu:BAACNQAFFH8GAAIhAAMKSxBJDADZAAAhAAMKSxBJDADZAAA1AAQKfyIAAiEACQr+HfoQANcCACEACQr+HfoQANcCAAAA.Satoru:BAAANQADCgUIBQAAAA==.',
Se='Seanjohn:BAAANQADCgUIBgAAAA==.Senile:BAAANQAECgUIDQAAAA==.Sertia:BAAANQADCgEIAQAAAA==.Sesnic:BAAANQAECgQIBwAAAA==.',
Sh='Shadesoflife:BAAANQABCgMIAwAAAA==.Shadydice:BAAANQADCgYICwABNQADCgYIBgATAAAAAA==.Shadydk:BAAANQADCgYIBwABNQADCgYIBgATAAAAAA==.Shadylid:BAAANQADCgYIBgAAAA==.Shadysmash:BAAANQADCggIDwAAAA==.Shadyvoid:BAAANQAECgQIBgABNQADCgYIBgATAAAAAA==.Shadówglider:BAAANQAECgIIBQAAAA==.Shaelia:BAAANQADCgIIAgAAAA==.Shale:BAABNQAECn8YAAIJAAgK8x5JGQCOAgAJAAgK8x5JGQCOAgAAAA==.Shamallaman:BAAANQAECgUJCAABNQAECgkJGwACACgjAA==.Sharkweek:BAAANQAECgMIAwAAAA==.Shazám:BAAANQAECgIIAgAAAA==.Sheol:BAAANQADCggIFQAAAA==.Sheyoni:BAAANQADCggJGgAAAA==.Shydestroyer:BAAANQADCgMIAwAAAA==.',
Si='Siersha:BAAANQADCgEIAQAAAA==.Sinfulness:BAAANQAECgQIDAAAAA==.',
Sk='Skikette:BAABNQAECn8hAAIVAAcKhgdqvwBIAQAVAAcKhgdqvwBIAQAAAA==.Skinrot:BAABNQAECn8iAAISAAkK3AseLAC4AQASAAkK3AseLAC4AQAAAA==.',
Sm='Smig:BAAANQAECgQICgAAAA==.',
Sn='Snowball:BAAANQAECgUIDwAAAA==.',
So='Soeki:BAAANQAECgUICwAAAA==.Soluthon:BAAANQADCgQIBAAAAA==.Sonyaa:BAAANQADCgcICQAAAA==.Soullove:BAABNQAECn8gAAIUAAcKRRX6DgAKAgAUAAcKRRX6DgAKAgABNQAECggIIAASAJMYAA==.Soullovez:BAABNQAECn8gAAMSAAgKkxh1HABNAgASAAgKkxh1HABNAgAQAAQKJQSCjwCTAAAAAA==.Soulshocks:BAABNQAECn8eAAIdAAcKDQssjgB9AQAdAAcKDQssjgB9AQABNQAECggIIAASAJMYAA==.Soulviver:BAABNQAECn8oAAIGAAgK7hJQYwDyAQAGAAgK7hJQYwDyAQAAAA==.',
Sp='Spiritwarden:BAABNQAECn8eAAIhAAgK9R9cEADfAgAhAAgK9R9cEADfAgAAAA==.Spliffy:BAAANQADCgQIBAAAAA==.Splootz:BAAANQADCggIEAABNQAFFAEIAQATAAAAAA==.Spoiledbratt:BAAANQABCgUIBQAAAA==.',
Sq='Squirtdadday:BAAANQAECgIJAgAAAA==.',
St='Stargasm:BAAANQAECgEIAQAAAA==.Stimer:BAABNQAECn80AAQNAAkKTCVyCACvAwANAAkKQSNyCACvAwALAAcKQiRTCADMAgAMAAYKWSGtDQDXAQAAAA==.Stori:BAAANQADCggIEQAAAA==.',
Su='Suxor:BAAANQAECgQIDgAAAA==.',
Sw='Swordboardal:BAACNQAFFH8GAAILAAMKMQ1pBQCoAAALAAMKMQ1pBQCoAAA1AAQKfygAAgsACQqlFoAQAB0CAAsACQqlFoAQAB0CAAAA.',
Sy='Sybius:BAAANQAECgQJCAAAAA==.Symptom:BAAANQAECgEIAQAAAA==.Syncophat:BAAANQAECgYIEAAAAA==.',
Ta='Tad:BAAANQAECgMIAwAAAA==.Taint:BAAANQADCgUICQAAAA==.Takia:BAAANQAECgIIBQAAAA==.Talanzen:BAABNQAECn8ZAAIWAAgK9iMfQQACAwAWAAgK9iMfQQACAwAAAA==.Talonia:BAAANQADCggICAABNQAECgcIGAAHAPYfAA==.Tanakiko:BAAANQADCgUIBQAAAA==.Tarrzok:BAAANQADCgcICAABNQADCgYIBgATAAAAAA==.',
Te='Teacup:BAAANQAECgIIBgABNQAECggIFgAXAGUZAA==.',
Th='Thrakara:BAACNQAFFH8UAAMgAAYKjwS8BACCAQAgAAYKjwS8BACCAQAhAAMKPQzaDADNAAA1AAQKfy8AAyAACQp/GZMRAGECACAACQp/GZMRAGECACEABApJHpc3AFMBAAAA.Thrakaru:BAABNQAECn8eAAIWAAkKihKQlwBRAgAWAAkKihKQlwBRAgAAAA==.Thrakumi:BAAANQADCgcIBwAAAA==.Thunderhorns:BAAANQAECgUIBgAAAA==.Thundrall:BAAANQAECgMIBgAAAA==.',
Ti='Tightspaces:BAAANQABCgMIAwAAAA==.Tiltéd:BAABNQAECn8bAAIbAAgKeR1rGQCtAgAbAAgKeR1rGQCtAgAAAA==.Tioshadow:BAAANQAECgIIAwABNQAFFAQIBwAhADkSAA==.',
To='Todem:BAAANQADCgEIAQAAAA==.Torches:BAAANQADCgcIBwAAAA==.Totemissues:BAAANQABCgMIAwABNQAECgkJKgAHAL4cAA==.',
Tr='Trayleen:BAAANQADCgUJBQAAAA==.Triad:BAAANQADCgYJBgAAAA==.Truths:BAACNQAFFH8WAAINAAcKxB7pBAB9AgANAAcKxB7pBAB9AgA1AAQKfxsAAg0ACQqSI4M0AO0CAA0ACQqSI4M0AO0CAAAA.Trystrom:BAAANQADCgYIDAAAAA==.',
Ts='Tsuo:BAAANQAECgcIDQAAAA==.Tsuoshock:BAAANQAECgUIBQAAAA==.',
Tx='Txblood:BAAANQADCgcJCAAAAA==.Txgunny:BAAANQAECgUIEAAAAA==.Txstormin:BAAANQADCgMJAwAAAA==.',
Ty='Tymptriss:BAAANQAECgMIBwAAAA==.',
['Tí']='Títus:BAAANQAECgIIAgAAAA==.',
Um='Umbrage:BAAANQAECggIDgABNQAFFAYIEgAaAPQTAA==.Umbren:BAABNQAECn8YAAMHAAcK9h+PWQBkAgAHAAcK9h+PWQBkAgAcAAEK3ADpngAXAAAAAA==.',
Ur='Urabadkity:BAAANQADCgYICwAAAA==.',
Us='Usefulmelee:BAAANQAECggIDQABNQAFFAYIFAAcAH4TAA==.',
Va='Valartha:BAAANQAECgIIBQAAAA==.Variste:BAAANQADCgMIAwAAAA==.',
Ve='Veil:BAAANQADCggJCAAAAA==.Velkån:BAAANQAECgEIAQAAAA==.Vellmora:BAAANQADCgUJBgAAAA==.Velsea:BAAANQAECgQIBQAAAA==.Velstadt:BAABNQAECn8gAAMhAAcKFhxrHQBHAgAhAAcKFhxrHQBHAgAfAAQKdxQ0HwDuAAAAAA==.Venhance:BAAANQAECgcJEAAAAA==.Venotu:BAABNQAECn8hAAIBAAkK7hssDADVAgABAAkK7hssDADVAgAAAA==.Vermilion:BAAANQAECgIIAwAAAA==.Vertebrae:BAAANQADCgEIAQAAAA==.',
Vh='Vholatile:BAABNQAECn8WAAMkAAgKLw+tCAAAAgAkAAgKLw+tCAAAAgAUAAIKGgR+cgA8AAAAAA==.',
Vi='Violence:BAAANQADCgYIBgAAAA==.Viviel:BAAANQAECgYIFQAAAQ==.',
Vo='Voidherron:BAAANQAECgMICQAAAA==.Voidknight:BAAANQADCgcICQAAAA==.Voodoomama:BAAANQADCgYIEQAAAA==.',
Wa='Waq:BAAANQADCgUIBQAAAA==.Warlockbot:BAACNQAFFH8PAAIVAAUK1xJLEACEAQAVAAUK1xJLEACEAQA1AAQKfyIAAhUACQpTH1EyALwCABUACQpTH1EyALwCAAAA.Warmongral:BAAANQADCgYIDwAAAA==.Waterboot:BAAANQADCgQIBwAAAA==.Wattheyneed:BAAANQAECgEIAgAAAA==.',
We='Wendi:BAAANQAECgYIEQAAAA==.',
Wh='Wholesome:BAAANQADCgcICwAAAA==.',
Wi='Wig:BAAANQADCggIEgABNQAECggIGwAbAHkdAA==.Wildbill:BAAANQADCgYIBwAAAA==.Windcrow:BAAANQADCggICAAAAA==.Withher:BAAANQADCggICAAAAA==.',
Wo='Wombo:BAAANQAECgMIAwAAAA==.Woolala:BAABNQAECn8wAAIHAAkK/xmxNgDEAgAHAAkK/xmxNgDEAgAAAA==.',
Wr='Wrahirn:BAAANQABCgYIBgAAAA==.Wrathran:BAAANQAECgIJAgAAAA==.',
Wu='Wut:BAAANQAECgcIBwABNQAECgkJKQAaAPMaAA==.',
Xa='Xahiri:BAAANQADCgYIBgAAAA==.Xalisto:BAAANQADCgYICQAAAA==.',
Xl='Xlia:BAAANQAECgMIAwAAAA==.',
Ya='Yaana:BAAANQADCggIDwAAAA==.Yazmyn:BAAANQAECgcIEwAAAA==.',
Ye='Yerehmi:BAAANQADCgYICQAAAA==.',
Yu='Yuny:BAABNQAECn8fAAIgAAgKuxJAGQDmAQAgAAgKuxJAGQDmAQAAAA==.',
Za='Zaier:BAABNQAECn8yAAMDAAkKvhqPKQC/AgADAAkKvhqPKQC/AgACAAUKfhDb+gAiAQAAAA==.',
Ze='Zeltan:BAABNQAECn9PAAIDAAkKeB8qEQBDAwADAAkKeB8qEQBDAwAAAA==.',
Zh='Zhundrenga:BAAANQAECgIIBQAAAA==.',
Zo='Zoma:BAAANQADCgEIAQAAAA==.',
['År']='Åres:BAAANQADCgEIAQAAAA==.',
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
