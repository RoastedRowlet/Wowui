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

local lookup = {'Hunter-Marksmanship','DemonHunter-Devourer','DeathKnight-Blood','Hunter-BeastMastery','Warrior-Arms','DeathKnight-Frost','DeathKnight-Unholy','Shaman-Elemental','Shaman-Restoration','Evoker-Preservation','Monk-Brewmaster','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Unknown-Unknown','Paladin-Holy','Druid-Restoration','Druid-Balance','DemonHunter-Havoc','Rogue-Assassination','Paladin-Protection','Monk-Mistweaver','Rogue-Outlaw','Mage-Arcane','Warrior-Fury','Paladin-Retribution','Warrior-Protection','Priest-Shadow','Priest-Discipline','Priest-Holy','Mage-Fire','Druid-Guardian','Shaman-Enhancement','Mage-Frost','Evoker-Augmentation','Evoker-Devastation','Druid-Feral','Rogue-Subtlety','DemonHunter-Vengeance','Monk-Windwalker',}
local provider = {region='US',realm='Stonemaul',name='US',type='weekly',zone=53,date='2026-10-13',data={Ad='Addalar:BAAANQAECgUICAAAAA==.',
Ai='Airvis:BAAANQAECgcIEwAAAA==.',
Ak='Akar:BAAANQADCgMIAwAAAA==.',
Al='Alacia:BAAANQADCgQIBAABNQAECgkJJgABADsQAA==.Albinomonk:BAAANQADCgMIAwAAAA==.',
Am='Amaira:BAAANQADCgQIBwAAAA==.Amalakar:BAAANQAECgEIAQAAAA==.Amnezea:BAAANQADCgIIAgAAAA==.',
An='Anankei:BAAANQADCgYIBgAAAA==.Anavere:BAAANQADCgUIBQAAAA==.Annasia:BAAANQAECgEIAQAAAA==.Antte:BAACNQAFFH8YAAICAAYKRxV+BQDUAQACAAYKRxV+BQDUAQA1AAQKfyQAAgIACQquI98KACwDAAIACQquI98KACwDAAAA.',
Ar='Arjun:BAAANQADCggIHgAAAA==.Armindru:BAAANQAECgYIDgAAAA==.Arturogh:BAAANQADCggICAABNQAECggIJAADAEIVAA==.',
As='Asmôdeô:BAAANQAECgUIDAAAAA==.Astin:BAAANQAECgEIAQAAAA==.',
At='Atom:BAABNQAECn8ZAAIEAAgK8gydhAD/AQAEAAgK8gydhAD/AQAAAA==.Atreyu:BAABNQAECn8ZAAIFAAcKYAvDugCFAQAFAAcKYAvDugCFAQAAAA==.',
Aw='Awoozehl:BAACNQAFFH8cAAMGAAcKbCNoAADMAgAGAAcKbCNoAADMAgAHAAEKaBwAIgBDAAA1AAQKfykAAwYACQqsJhcFAI0DAAYACQqsJhcFAI0DAAcACApgGo9bAJ4BAAAA.',
Az='Azgrodon:BAABNQAECn8nAAMIAAgK/Rh+TABBAgAIAAgK/Rh+TABBAgAJAAgKEgqgigBrAQAAAA==.',
Ba='Banatok:BAAANQADCgIIAwAAAA==.Bangungot:BAAANQAECgEIAQABNQAFFAcIFAAKAB0XAA==.Barnabus:BAAANQAECgMIAwAAAA==.Barzalie:BAAANQAECgEIAQABNQAFFAMICAADAKoTAA==.Bathrezz:BAAANQAECgIIAgAAAA==.',
Be='Beandruid:BAAANQAECgEIAQAAAA==.Beanmage:BAAANQAECgUIBQAAAA==.Beanshaman:BAAANQADCgYIBgAAAA==.Bearlyawake:BAAANQADCgUIBQAAAA==.Beerbelly:BAABNQAECn8kAAILAAkKFCEgAwBlAwALAAkKFCEgAwBlAwABNQAFFAMICAADAKoTAA==.Beleaves:BAACNQAFFH8aAAILAAYK9ggCBABlAQALAAYK9ggCBABlAQA1AAQKfyoAAgsACQqqFFoMADsCAAsACQqqFFoMADsCAAAA.Bellectra:BAAANQAECgUIDAAAAA==.',
Bi='Bifurious:BAAANQAECgcIDgAAAA==.',
Bl='Blathur:BAAANQADCgcIDQAAAA==.Bluereindeer:BAABNQAECn8rAAIDAAkKNhBKSADUAQADAAkKNhBKSADUAQAAAA==.',
Bo='Bobafina:BAAANQADCggICAAAAA==.Bobsstones:BAACNQAFFH8UAAQMAAcK4BhZAQBLAQAMAAQKoxJZAQBLAQANAAMKKxcGIQDxAAAOAAIK+x2xCgCnAAA1AAQKfyUABA4ACQq4JeAVAL0BAA0ABQqNJImKAMcBAAwABQrwIcEKAMUBAA4ABQqhH+AVAL0BAAAA.Bobstofu:BAAANQAECgcIEwAAAA==.Bofaðeez:BAAANQADCgQIBAAAAA==.Bombtimer:BAAANQADCgIIAwABNQADCgUICQAPAAAAAA==.Bonkulo:BAABNQAECn8kAAIDAAgKQhVqRQDiAQADAAgKQhVqRQDiAQAAAA==.Boofassist:BAACNQAFFH8UAAIQAAYKBiDGAwBOAgAQAAYKBiDGAwBOAgA1AAQKfykAAhAACQooJbEDALcDABAACQooJbEDALcDAAAA.Boomsonic:BAAANQAECgQIBwABNQAECgcIDgAPAAAAAA==.Boraga:BAAANQADCgYJBwAAAA==.',
Br='Brienyx:BAAANQADCgUIBwAAAA==.Briezani:BAAANQAECgUICwAAAA==.Briogan:BAAANQAECgUICQAAAA==.Broccoliz:BAECNQAFFH8cAAIRAAcKmBOtAgAsAgARAAcKmBOtAgAsAgA1AAQKfy8AAxEACQq/GzoVAJoCABEACQq/GzoVAJoCABIAAQpXFuqoAEEAAAAA.Brokan:BAAANQADCggIDgAAAA==.Broke:BAAANQAECgIIAgABNQAFFAcIIAATANckAQ==.',
Bu='Bukhaki:BAAANQAECgcICAABNQAECggIHAAUAD4dAA==.',
['Bõ']='Bõb:BAAANQADCggICgAAAA==.',
Ca='Caden:BAAANQADCgYIBgABNQAECgkJJgABADsQAA==.Cafca:BAABNQAECn8aAAIMAAgK8Q+DCAAEAgAMAAgK8Q+DCAAEAgAAAA==.Caké:BAAANQADCgYIDAAAAA==.Caylva:BAAANQAECgQIBAABNQAFFAMICAADAKoTAA==.',
Ch='Chrams:BAABNQAECn87AAIQAAkKrB+wFgAhAwAQAAkKrB+wFgAhAwAAAA==.',
Ci='Cialis:BAAANQADCgYIJgAAAA==.Cinnacrunch:BAAANQADCggIDgAAAA==.',
Cl='Clearlyumad:BAAANQAECgQIBwAAAA==.Clèrick:BAABNQAECn80AAMQAAkKFR61IgDfAgAQAAgK+x61IgDfAgAVAAcKhw16MQBQAQAAAA==.',
Co='Coldcrow:BAAANQADCgUICQAAAA==.Combination:BAABNQAECn8mAAIWAAkKDyBmBwAaAwAWAAkKDyBmBwAaAwAAAA==.Cowen:BAAANQADCggIEwAAAA==.',
Cr='Crash:BAAANQADCgUIBQABNQAFFAQICQAPAAAAAA==.Cray:BAAANQADCgIIAgAAAA==.',
Cu='Cursedotter:BAAANQAECggIDQAAAA==.',
Da='Dabbyshatner:BAAANQAECgYIDQAAAA==.Daeneryis:BAAANQAECgMIAwAAAA==.Dankshammy:BAABNQAECn8jAAIJAAkKpRpjIQDhAgAJAAkKpRpjIQDhAgAAAA==.Darkwave:BAABNQAECn8nAAMOAAgKBBMCPADQAAANAAYKpg58rABzAQAOAAMKeRMCPADQAAAAAA==.Darthdiddyus:BAACNQAFFH8OAAIXAAQKaBdpAQBCAQAXAAQKaBdpAQBCAQA1AAQKfysAAhcACQpUIa8CACMDABcACQpUIa8CACMDAAAA.Dathunter:BAAANQAECgIIAgABNQAECgkJJgAYAGETAA==.Dawghawg:BAAANQADCgUIBgAAAA==.Dawnnie:BAABNQAECn8wAAIVAAkKbhsJDgC4AgAVAAkKbhsJDgC4AgAAAA==.Dawsonrogers:BAABNQAECn8dAAMZAAkKhxSMCgAeAgAZAAgKMReMCgAeAgAFAAMKvg2iJQGEAAAAAA==.',
De='Deathbanana:BAAANQADCggICAABNQAFFAcIFQAYAOkfAA==.Deathbydk:BAACNQAFFH8IAAIDAAMKqhOrHQCcAAADAAMKqhOrHQCcAAA1AAQKfx4AAgMACQoMIIMMAE0DAAMACQoMIIMMAE0DAAAA.Delema:BAACNQAFFH8PAAIaAAYKRg1UCADCAQAaAAYKRg1UCADCAQA1AAQKfyMAAxoACQoHH/xdAHsCABoACQoHH/xdAHsCABUAAQoAANJ+ABwAAAAA.Derbina:BAAANQABCgIIBAAAAA==.Destructer:BAAANQAECgIIAwAAAA==.',
Di='Dirtydinker:BAAANQAECgcICQAAAA==.Dixsard:BAABNQAECn8cAAIUAAgKPh06GQCvAgAUAAgKPh06GQCvAgAAAA==.',
Do='Docmcstuffin:BAAANQADCgMIAwAAAA==.Dontblink:BAAANQAECgEIAQABNQAECgkJJgAWAA8gAA==.Dorin:BAAANQABCgQIBAAAAA==.Dotore:BAAANQADCgYIBgAAAA==.Dottyflu:BAACNQAFFH8PAAIDAAUKrRQTDwBdAQADAAUKrRQTDwBdAQA1AAQKfyUAAgMACQr/H6QUAAUDAAMACQr/H6QUAAUDAAAA.Dottylawful:BAABNQAFFH8HAAIVAAUKSwYqBwADAQAVAAUKSwYqBwADAQABNQAFFAUIDwADAK0UAA==.',
Dr='Drexbear:BAAANQAECgQJBAABNQAFFAUIDwAbAA4PAA==.Drexl:BAACNQAFFH8PAAIbAAUKDg/sAgBJAQAbAAUKDg/sAgBJAQA1AAQKfyEAAwUACQq5D8GqAK0BAAUACQpGCMGqAK0BABsAAwoGIa4lABEBAAAA.',
Dw='Dweams:BAACNQAFFH8bAAIcAAYK9xlABAAGAgAcAAYK9xlABAAGAgA1AAQKfyMAAxwACQrtI1gNABUDABwACQrtI1gNABUDAB0ABgoxGpYMAG0BAAAA.Dweamu:BAAANQADCgMIAwABNQAFFAYIGwAcAPcZAA==.',
Ec='Ectonight:BAAANQADCgIIAgAAAA==.',
Eg='Eggfooyung:BAAANQAFFAIIAgABNQAFFAYIFAAQAAYgAA==.Egwene:BAAANQAECgEIAQAAAA==.',
El='Elhonna:BAABNQAECn80AAIEAAkKex/4KADzAgAEAAkKex/4KADzAgAAAA==.',
En='Endcredits:BAAANQAECgUIDwAAAA==.',
Er='Eridyn:BAAANQAECgMIBAAAAA==.',
Ev='Evoulker:BAACNQAFFH8hAAIKAAcK4xxFAwBaAgAKAAcK4xxFAwBaAgA1AAQKfysAAgoACQrWHwkLAPECAAoACQrWHwkLAPECAAAA.',
Ez='Ezekielle:BAAANQAECgEIAQAAAA==.',
Fa='Faire:BAAANQADCgIIAgABNQAECgcIDwAPAAAAAA==.Fairytale:BAACNQAFFH8cAAIeAAYKNxKGCwDLAQAeAAYKNxKGCwDLAQA1AAQKfyoAAx0ACQqEIX8GACACAB4ACQpxIEAlANQCAB0ABwrkHH8GACACAAAA.Faker:BAAANQADCggIDwAAAA==.',
Fe='Felheim:BAACNQAFFH8KAAICAAQKlRepCQBBAQACAAQKlRepCQBBAQA1AAQKfz4AAgIACQoOISwGAG0DAAIACQoOISwGAG0DAAAA.Fellithà:BAAANQADCgUIBgAAAA==.',
Fi='Fists:BAAANQADCgYJDAABNQAFFAMIBwAKAFYKAA==.',
Fl='Flink:BAAANQADCgIJAgAAAA==.Floogi:BAAANQADCgMIAwAAAA==.',
Fo='Foxygal:BAAANQADCggIEwAAAA==.',
Fr='Frostyninja:BAAANQAECgIIAgAAAA==.',
Ga='Garchomp:BAAANQADCgQICAAAAA==.Gawain:BAAANQAECgYICgABNQAECgkJLAAEAI8cAA==.',
Ge='Gellina:BAAANQADCgUICAAAAA==.Georg:BAACNQAFFH8YAAIaAAcKshvqAQCDAgAaAAcKshvqAQCDAgA1AAQKfyIAAhoACQqXJW4aAFgDABoACQqXJW4aAFgDAAAA.Geriatric:BAAANQAECgIIBQABNQAFFAcIHAAGAGwjAA==.',
Gl='Glathur:BAAANQADCgIIBAAAAA==.Glizzygagger:BAACNQAFFH8GAAMcAAIKhyADEADJAAAcAAIKhyADEADJAAAdAAIKsxZjAgCoAAA1AAQKfx4AAhwACQpSIpAMAB4DABwACQpSIpAMAB4DAAE1AAUUBAgFABcAbxgA.Glizzygorger:BAABNQAECn8VAAICAAcKjR0jIQBAAgACAAcKjR0jIQBAAgABNQAFFAQIBQAXAG8YAA==.',
Go='Goodbye:BAABNQAECn8eAAMYAAkKzhnTdgCQAgAYAAkKzhnTdgCQAgAfAAEKAADQDQAzAAAAAA==.Goregazme:BAAANQAECgYIBwAAAA==.',
Gr='Grantoro:BAABNQAECn8hAAIgAAkKyw6fHAC3AQAgAAkKyw6fHAC3AQAAAA==.Grimmblades:BAAANQAECgIIAgAAAA==.Grootbeer:BAABNQAECn8YAAIEAAcKHxJuhQD9AQAEAAcKHxJuhQD9AQAAAA==.',
Gu='Gulgrimmar:BAACNQAFFH8bAAMIAAcKUhqhCADhAQAIAAUKuxyhCADhAQAJAAMKQx9+FAAKAQA1AAQKfyUAAwgACQq/JZMGALMDAAgACQq/JZMGALMDAAkABQqMGxJ7AJYBAAAA.Guwudanielle:BAAANQAECgcIDwAAAA==.',
['Gä']='Gävinräd:BAAANQADCgUIBQAAAA==.',
Ha='Haranguetan:BAAANQADCgYIBgABNQAECggIJQAhAK8LAA==.Hardfeelings:BAAANQAECgUIDwAAAA==.Harrharr:BAAANQADCgMIAwAAAA==.',
He='Headache:BAAANQABCgIIAgABNQAECgcIDgAPAAAAAA==.Hexappeal:BAAANQAECgYIBgAAAA==.',
Ho='Hodann:BAAANQABCgYIBgAAAA==.',
Hu='Hurjek:BAABNQAECn8gAAIRAAkKkSKwAwCLAwARAAkKkSKwAwCLAwABNQAECgkJJgAWAA8gAA==.',
Ic='Iconicmax:BAAANQAECgQICwAAAA==.',
Ij='Ijustankedu:BAAANQADCgEIAQAAAA==.',
Il='Ilyana:BAABNQAECn8qAAMYAAkKZSB4aQCrAgAYAAgK6R54aQCrAgAiAAIKKCKYKQCoAAAAAA==.',
In='Insights:BAAANQAECgUIDwAAAA==.',
Is='Ishtann:BAAANQABCgIIAgAAAA==.',
Ja='Jaqen:BAACNQAFFH8FAAIXAAQKbxhVAQBOAQAXAAQKbxhVAQBOAQA1AAQKfyAAAxcACAoiI8cCAB4DABcACAoiI8cCAB4DABQAAQrhDVKdADkAAAAA.Jayc:BAABNQAECn8iAAIYAAkKtR9hMwAkAwAYAAkKtR9hMwAkAwAAAA==.',
Je='Jereico:BAACNQAFFH8bAAMjAAcKcCE6AQCWAgAjAAcKcCE6AQCWAgAkAAEKqxq5DgBLAAA1AAQKfyoAAyMACQrbJc0AALMDACMACQrbJc0AALMDACQACAr5EicZALQBAAAA.Jeryhn:BAACNQAFFH8cAAIQAAUKrBt/CgCwAQAQAAUKrBt/CgCwAQA1AAQKfyoAAhAACQrNIpEOAFQDABAACQrNIpEOAFQDAAAA.',
Jo='Joeynodz:BAAANQAECgEIAQAAAA==.Jortshorts:BAABNQAECn8gAAIlAAkK7QfIFwB5AQAlAAkK7QfIFwB5AQAAAA==.',
Ju='Juggalo:BAACNQAFFH8PAAIkAAUKMRjFBACAAQAkAAUKMRjFBACAAQA1AAQKfzMAAyQACQo+I3sEAFIDACQACQo+I3sEAFIDACMAAgoKDQgeAG4AAAAA.June:BAACNQAFFH8aAAIWAAcK8xEXAgAZAgAWAAcK8xEXAgAZAgA1AAQKfysAAhYACQqLIB4KAOQCABYACQqLIB4KAOQCAAAA.',
Ka='Kalikin:BAAANQAECgMJBAAAAA==.Kawasuoo:BAAANQADCgQIBAABNQAECggIDQAPAAAAAA==.',
Kc='Kcudüm:BAABNQAECn8qAAQOAAkKxhEXDgAXAgAOAAgKjhMXDgAXAgANAAUKjwYE+QDTAAAMAAEKAACQLgA4AAAAAA==.',
Ke='Keifis:BAAANQADCgEJAQAAAA==.Keifism:BAAANQABCgMIAwAAAA==.',
Kh='Khaotichic:BAAANQAECgEIAQAAAA==.',
Kl='Klrum:BAABNQAECn8kAAMiAAgKrxcKHgD4AAAYAAcKThimugANAgAiAAUKqBAKHgD4AAAAAA==.',
Ko='Koddin:BAABNQAECn8rAAIaAAkKLRu8PQDZAgAaAAkKLRu8PQDZAgAAAA==.Komui:BAABNQAECn8rAAMJAAkK8xZbTQArAgAJAAkK8xZbTQArAgAIAAcKsw47gQCeAQAAAA==.Koonlei:BAAANQAECgQIBAAAAA==.Koreth:BAACNQAFFH8cAAMUAAcKOhNhAgBcAgAUAAcKOhNhAgBcAgAmAAEK9w5rFQBCAAA1AAQKfysAAxQACQraIsoKADEDABQACQraIsoKADEDACYACArzF1cZAAwCAAAA.Kornholyo:BAAANQAECgIIAwAAAA==.',
Kr='Krakheeta:BAAANQADCgQIBAAAAA==.Krusade:BAAANQAECgUICQAAAA==.',
Ku='Kumo:BAAANQAECgEIAQAAAA==.Kutuzov:BAAANQADCggIJgAAAA==.',
Kw='Kwenny:BAAANQAECgEIAQAAAA==.',
La='Lailaysia:BAAANQAECgEIAQAAAA==.Lamemoosaur:BAABNQAECn8YAAIgAAkKOxxKCAD1AgAgAAkKOxxKCAD1AgAAAA==.Laríca:BAABNQAECn8uAAIQAAkKASNVCACFAwAQAAkKASNVCACFAwAAAA==.Laydout:BAAANQADCgQIBAABNQAECgcIEQAPAAAAAA==.Laydoutyota:BAAANQAECgcIEQAAAA==.Laymow:BAAANQAECgQJBAABNQAECgkJGAAgADscAA==.',
Le='Levity:BAAANQAECggIBQAAAA==.',
Li='Lilea:BAABNQAECn8mAAMBAAkKOxCqPQBgAQAEAAYK3hHXpQC2AQABAAcKlwmqPQBgAQAAAA==.Lilfaart:BAAANQAECggIBAAAAA==.Lindisalvia:BAAANQADCgIIAgAAAA==.Lionsmane:BAAANQADCgYIBgAAAA==.',
Lo='Loosemorals:BAACNQAFFH8HAAIKAAMKVgooEQDOAAAKAAMKVgooEQDOAAA1AAQKfx0AAwoACQr6GYcQAKACAAoACQr6GYcQAKACACQAAQoQFOk5ADwAAAAA.Lootgoblin:BAABNQAECn8mAAIYAAkKYRMQjwBhAgAYAAkKYRMQjwBhAgAAAA==.Lortherian:BAAANQAECgUIDQAAAA==.',
['Lä']='Läwlbringer:BAABNQAECn8ZAAIaAAgKkhK4lAD2AQAaAAgKkhK4lAD2AQAAAA==.',
Ma='Mabritoe:BAACNQAFFH8HAAIUAAQK1SMwCgBZAQAUAAQK1SMwCgBZAQA1AAQKfyMAAxQACQrMJEIPAAQDABQACArMJEIPAAQDACYACAqSCUwiALQBAAE1AAUUBwgYABIAhRUA.Magooh:BAAANQADCgcIBwABNQAECgQIDQAPAAAAAA==.Malison:BAAANQADCgUIBAAAAA==.Mangle:BAAANQADCgUIBQAAAA==.Mania:BAAANQADCgYICgABNQAECgcIDgAPAAAAAA==.Mareth:BAAANQADCgIIAgAAAA==.Mathath:BAABNQAECn8dAAMHAAgKTRsQPwAfAgAHAAgKxRkQPwAfAgADAAMKYx9DfAAEAQAAAA==.Mathoras:BAAANQADCgYIBgAAAA==.Mayaho:BAAANQAECgQIDQAAAA==.Maylee:BAAANQAECgYICgAAAA==.',
Me='Meandean:BAAANQAECgUIBgAAAA==.Meatier:BAAANQAECgQIBQABNQAECgcIDgAPAAAAAA==.Meenako:BAAANQAECgEIAQAAAA==.Mellinia:BAAANQADCgEIAQAAAA==.Meoverdahill:BAAANQABCgIIAgAAAA==.',
Mi='Miltonroe:BAABNQAECn8lAAIhAAgKrwuzFwDoAQAhAAgKrwuzFwDoAQAAAA==.Miltonroé:BAAANQAECgQIBAABNQAECggIJQAhAK8LAA==.Mixing:BAAANQADCgIJAgAAAA==.',
Mo='Monnz:BAAANQADCgUIBQAAAA==.Monsterskill:BAAANQAECgQIBQAAAA==.Moonerva:BAAANQAECgUIDwAAAA==.Morana:BAAANQAECgMIAwAAAA==.',
Mu='Munchinmuff:BAAANQAECgQIBQAAAA==.',
Mv='Mvqchx:BAAANQADCgEIAQAAAA==.',
My='Myrolous:BAAANQADCgQIBAAAAA==.',
['Mã']='Mãrtrydóm:BAAANQABCgQIBAAAAA==.',
['Mì']='Mìssy:BAAANQAECgEIAQAAAA==.',
Na='Namiin:BAAANQADCgUIBQAAAA==.Namikaze:BAAANQAECgEIAQAAAA==.Natara:BAAANQADCgYIBgAAAA==.Naughtye:BAAANQAECgEIAQAAAA==.Nave:BAAANQAECgcICAAAAA==.',
Ne='Nelfsfault:BAAANQADCggJFwAAAA==.Nerotappo:BAAANQABCgIIAgAAAA==.',
Ni='Ninja:BAAANQADCgYJBgAAAA==.',
No='Nobacon:BAAANQADCgIIAgAAAA==.Noshaku:BAAANQAECgIIAwAAAA==.Notanorc:BAABNQAECn8kAAMZAAkKJQ+EFQBAAQAFAAkKjAtCkADvAQAZAAUKMROEFQBAAQAAAA==.',
Od='Odium:BAAANQAECgIIAgAAAA==.',
Oh='Ohrolam:BAABNQAECn8tAAMYAAkKdQlt3wDGAQAYAAkKowdt3wDGAQAiAAQKxwoxKgCkAAAAAA==.',
Ok='Okasan:BAAANQAECgQICAABNQAECgQIDAAPAAAAAA==.',
Ot='Ottersdemons:BAAANQAECgMIAwAAAA==.',
Pa='Palthur:BAAANQAECgIIAwAAAA==.Paradoxis:BAAANQABCgIIBAAAAA==.Passionate:BAAANQADCgUIBQAAAA==.',
Ph='Phatmidas:BAABNQAECn8eAAIaAAgKehazcABKAgAaAAgKehazcABKAgAAAA==.Phrozenpally:BAAANQAECgMIBgABNQAECgQIDQAPAAAAAA==.',
Pi='Pika:BAAANQADCgcIBwABNQAFFAMICAADAKoTAA==.Pinkponythug:BAAANQAECgUIBgABNQAFFAMIBwAKAFYKAA==.',
Pl='Plagueground:BAACNQAFFH8aAAQGAAcKeCDRAQA+AgAGAAYKXCPRAQA+AgADAAIK5xTVJABmAAAHAAEKsA8AJAA7AAA1AAQKfzIABAYACQolJmECAMIDAAYACQolJmECAMIDAAMAAgrlJTKbAKEAAAcAAQrJBfniAC8AAAAA.Plutonyus:BAAANQAECgMIBAAAAA==.',
Po='Poc:BAAANQAECgMIBwAAAA==.Porterhaus:BAAANQADCggICAABNQAECgkJIwAOANcVAA==.Pounces:BAABNQAECn8xAAIlAAkKayVWAQDCAwAlAAkKayVWAQDCAwAAAA==.',
Pr='Prózak:BAAANQADCgYIBgABNQAECgkJHwAVAG0WAA==.Prôzak:BAABNQAECn8fAAIVAAkKbRaDFgBGAgAVAAkKbRaDFgBGAgAAAA==.',
Ps='Psychomidget:BAAANQAECgUIBwAAAA==.',
Pu='Puetrid:BAABNQAECn8jAAMOAAkK1xXsBQCyAgAOAAkK1xXsBQCyAgANAAEKsQoKPgE0AAAAAA==.Purble:BAAANQADCgIIAgAAAA==.Puufrumslli:BAAANQAECgcIEQAAAA==.',
Ra='Rageinglight:BAAANQAECgMIBQAAAA==.Rakku:BAAANQABCgcJBgAAAA==.Rautha:BAABNQAECn8cAAIaAAgKBBKypgDNAQAaAAgKBBKypgDNAQAAAA==.Rayl:BAAANQAECgEIAQAAAA==.',
Re='Rekt:BAAANQAECgQIBQAAAA==.',
Rh='Rhaegon:BAABNQAECn8tAAInAAkKCBw0BQDdAgAnAAkKCBw0BQDdAgAAAA==.',
Ri='Rimath:BAAANQADCggIEAAAAA==.',
Rn='Rng:BAAANQADCggIFAABNQAECgEIAgAPAAAAAA==.',
Ro='Rodstewart:BAAANQAECggIEwAAAA==.Ronz:BAAANQABCgEJAQAAAA==.Roofeo:BAAANQAECgEIAQABNQAECggIJAADAEIVAA==.Rotdaddy:BAABNQAECn8gAAIHAAgKkgjrbABcAQAHAAgKkgjrbABcAQAAAA==.',
Sa='Sabatikus:BAAANQAECgEIAQAAAA==.Salino:BAAANQAECgYIDwAAAA==.Sam:BAAANQAECgcIEQAAAA==.Sandorindis:BAAANQADCgYIBwAAAA==.Sarate:BAAANQADCggIEAAAAA==.Satral:BAAANQAECgYIBwAAAA==.Savannah:BAAANQAECgYIBwABNQAECgcIDwAPAAAAAA==.Savvtwo:BAAANQADCgEIAQABNQAFFAcIIAATANckAQ==.',
Se='Sezra:BAAANQADCggICAAAAA==.',
Sh='Shaetahn:BAAANQAECgEIAQAAAA==.Shamwowthorn:BAAANQADCgEIAQAAAA==.Shinanigans:BAABNQAECn8nAAIaAAkKzh1jNgDyAgAaAAkKzh1jNgDyAgAAAA==.Shockbull:BAAANQADCgcJBwAAAA==.',
Si='Silverbäck:BAAANQAECgUIDAABNQADCggIHgAPAAAAAA==.Silverslam:BAAANQADCggIHwABNQADCggIHgAPAAAAAA==.',
Sk='Skurge:BAAANQAECgUIDQAAAA==.',
Sn='Snacks:BAAANQADCgEIAQABNQAECgcIEQAPAAAAAA==.Snuffles:BAAANQADCgYIBgAAAA==.',
So='Solstis:BAAANQAECgUICQAAAA==.Soranwena:BAABNQAECn8ZAAIgAAgK9Bb5FQADAgAgAAgK9Bb5FQADAgAAAA==.Sorros:BAAANQAECgQIBQAAAA==.',
Sp='Spacegoat:BAAANQAECgMIAwAAAA==.Spfzero:BAAANQAECgEIAQAAAA==.Spookybuns:BAAANQAECggIAQAAAA==.',
St='Sticksy:BAAANQADCgYIBgAAAA==.Stonebeard:BAAANQAECgQIBgAAAA==.Stârlèss:BAAANQADCgYIBwAAAA==.',
Su='Subtox:BAAANQAECgUIBwAAAA==.',
Sw='Swedishfish:BAAANQAECgEIAQABNQAECgkJHQAcAP4dAA==.',
['Sá']='Sálúd:BAAANQAECgcIEQAAAA==.',
Ta='Tarhealeon:BAAANQAECgYIDgAAAA==.Tarvuspls:BAABNQAECn8WAAMEAAgKRA9KhgD7AQAEAAgKRA9KhgD7AQABAAUK7QVFVQDNAAAAAA==.',
Te='Teemawthy:BAAANQADCgMIAwAAAA==.Temozo:BAAANQADCgIIAgAAAA==.',
Th='Thabigone:BAAANQAECgIIAgAAAA==.Theceo:BAAANQADCgYIDgAAAA==.Thorb:BAAANQAECgcICQABNQAFFAMICAADAKoTAA==.',
Ti='Ticklemebutt:BAAANQAECgcIEgAAAA==.Tiewaz:BAAANQADCgUIBQABNQAECgQIBgAPAAAAAA==.',
To='Tolun:BAABNQAECn8eAAIiAAkKnBQ3CgAjAgAiAAkKnBQ3CgAjAgAAAA==.Tosan:BAAANQAECgQIDAAAAA==.Toughcookie:BAAANQAECgYIDwAAAA==.',
Tr='Treeplague:BAABNQAECn8dAAMdAAgK0QwrCwCOAQAdAAgK0QwrCwCOAQAcAAIK4QTkawBQAAAAAA==.',
Tu='Turn:BAACNQAFFH8eAAQOAAcKKhSIAgD2AAAMAAMKRxQmAgAAAQAOAAMK7ROIAgD2AAANAAMKhhD1IQDsAAA1AAQKfycABA4ACQpTIsgPAP8BAA0ABgqrHtlzAAECAA4ABwpPF8gPAP8BAAwABQqFJRYKANgBAAAA.Turtleduck:BAAANQADCgUIBQABNQAECgYIDgAPAAAAAA==.',
Ty='Tyla:BAAANQADCggIGwAAAA==.Typhis:BAAANQAECgQIBAAAAA==.',
['Tì']='Tìewaz:BAAANQAECgQIBgAAAA==.',
Um='Umbryx:BAAANQAECgEIAQAAAA==.',
Un='Unagi:BAABNQAECn8cAAIhAAkKwAxpEgA/AgAhAAkKwAxpEgA/AgAAAA==.',
Va='Valdir:BAAANQAECggIBgAAAA==.Vasomir:BAAANQABCgIIAQAAAA==.',
Ve='Venomstrikes:BAAANQADCgcIBwAAAA==.Venøm:BAAANQAECgEIAQAAAA==.',
Vi='Viscerion:BAAANQAECgYIEAAAAA==.',
Wh='Whoarlock:BAAANQADCgYICAAAAA==.',
Wi='Wizzyy:BAAANQADCgUIBQAAAA==.',
Xe='Xelinia:BAACNQAFFH8RAAMcAAUKoQc6DAAcAQAcAAQKoQc6DAAcAQAeAAEK9AIMNwA/AAA1AAQKfyMAAxwACQrbHKoYAIkCABwACQrbHKoYAIkCAB4AAQrfAY8GAR8AAAAA.Xen:BAEANQAECggICwAAAA==.',
Xu='Xuefeng:BAACNQAFFH8KAAIoAAQKChADCgAiAQAoAAQKChADCgAiAQA1AAQKfzIAAigACQrWHsMLABYDACgACQrWHsMLABYDAAAA.',
Ya='Yahwae:BAAANQAECgQIBwABNQAECggIJwAOAAQTAA==.',
Yc='Ycephyre:BAAANQAECgYICAAAAA==.',
Ye='Yenchmeister:BAACNQAFFH8ZAAIFAAcKDBeeBgBTAgAFAAcKDBeeBgBTAgA1AAQKfyoAAgUACQrlJL4cAEMDAAUACQrlJL4cAEMDAAAA.',
Yo='Yomahma:BAAANQAECgUIBgAAAA==.',
Zd='Zdervish:BAABNQAECn8XAAIUAAcKihpkKABJAgAUAAcKihpkKABJAgAAAA==.',
Ze='Zeffira:BAAANQAECgQIAwAAAA==.Zellda:BAAANQADCgYIBgAAAA==.',
Zi='Zilvanic:BAAANQAECgcIDAAAAA==.Zilvanion:BAABNQAECn8rAAINAAkKYBTWWQBGAgANAAkKYBTWWQBGAgAAAA==.',
Zl='Zlathur:BAAANQADCgcIDgAAAA==.',
Zo='Zourbeast:BAAANQADCgQIBAAAAA==.Zourknight:BAAANQADCgcICAAAAA==.Zourlight:BAAANQADCgcIEAAAAA==.Zourlock:BAAANQADCggIDwAAAA==.Zourvoid:BAAANQADCggIEAAAAA==.',
['Ðr']='Ðrèamless:BAAANQAECgYIEAAAAA==.',
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
