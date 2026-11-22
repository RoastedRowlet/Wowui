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

local lookup = {'Shaman-Restoration','Mage-Frost','Mage-Arcane','Unknown-Unknown','Hunter-Marksmanship','DemonHunter-Devourer','Shaman-Enhancement','Shaman-Elemental','Druid-Restoration','DeathKnight-Blood','DemonHunter-Vengeance','Hunter-BeastMastery','Warrior-Arms','DeathKnight-Frost','DeathKnight-Unholy','Evoker-Devastation','Paladin-Holy','Paladin-Retribution','Monk-Brewmaster','Mage-Fire','Warrior-Fury','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Evoker-Preservation','Druid-Balance','Rogue-Assassination','Rogue-Subtlety','DemonHunter-Havoc','Paladin-Protection','Monk-Mistweaver','Rogue-Outlaw','Warrior-Protection','Priest-Shadow','Priest-Discipline','Priest-Holy','Druid-Guardian','Evoker-Augmentation','Druid-Feral','Monk-Windwalker',}
local provider = {region='US',realm='Stonemaul',name='US',type='weekly',zone=53,date='2026-11-17',data={Ad='Addalar:BAABNQAECn8lAAIBAAkKZxoHJgCXAgABAAkKZxoHJgCXAgAAAA==.',
Ai='Airvis:BAABNQAECn8pAAMCAAgKPRIADAD8AQACAAgKPRIADAD8AQADAAMKxQYGngGJAAAAAA==.',
Ak='Akamie:BAAANQAECgUIBgABNQAECgcIDwAEAAAAAA==.Akar:BAAANQADCgMIAwAAAA==.',
Al='Alacia:BAAANQADCgQIBAABNQAECgoKPwAFAOkVAA==.Albinomonk:BAAANQADCgMIAwAAAA==.Alundre:BAAANQAECgUIBQAAAA==.',
Am='Amaira:BAAANQAECgEIAQAAAA==.Amalakar:BAAANQAECgEIAQAAAA==.Amnezea:BAAANQADCgIIAgAAAA==.',
An='Anankei:BAAANQADCgYIBgAAAA==.Anavere:BAAANQADCgUIBQAAAA==.Annasia:BAAANQAECgEIAQAAAA==.Antte:BAACNQAFFH8YAAIGAAYKRxWtBQDSAQAGAAYKRxWtBQDSAQA1AAQKfyQAAgYACQquIwYLACwDAAYACQquIwYLACwDAAAA.',
Ar='Arjun:BAABNQAECn8bAAQHAAkKdwuWFwCbAQAHAAgKOAyWFwCbAQABAAgKmg7vZwB9AQAIAAMKEweVwgCFAAAAAA==.Armindru:BAABNQAECn8jAAIJAAoKlRjmFgBmAgAJAAoKlRjmFgBmAgAAAA==.Armingothele:BAAANQAECgEIAQABNQAECgoKIwAJAJUYAA==.Arrol:BAAANQADCgIIAgAAAA==.Arturogh:BAAANQAECggIDwABNQAECgoKOwAKAO0UAA==.',
As='Asmôdeô:BAABNQAECn8lAAMGAAoK0yI9BgD6AgAGAAoK0yI9BgD6AgALAAEK6SLCKgBeAAAAAA==.Astin:BAAANQAECgEIAQAAAA==.',
At='Atom:BAABNQAECn8rAAIMAAoKKw88XgALAgAMAAoKKw88XgALAgAAAA==.Atreyu:BAABNQAECn8tAAINAAgKfw3leQCYAQANAAgKfw3leQCYAQAAAA==.',
Au='Aureille:BAAANQAECgQIAwAAAA==.',
Aw='Awoozehl:BAACNQAFFH8gAAMOAAkKpB9vAADLAgAOAAgK1yFvAADLAgAPAAIKbhdeEgBSAAA1AAQKf0IAAw4ACgq9JiABAIcDAA4ACgq9JiABAIcDAA8ACAoiG31cAJ4BAAAA.',
Az='Azgrodon:BAABNQAECn81AAMIAAoKyxltTQBBAgAIAAoKyxltTQBBAgABAAgKEgoLjABrAQAAAA==.',
Ba='Banatok:BAAANQADCgIIAwAAAA==.Bangungot:BAAANQAECgYIBgABNQAFFAkJIwAQADUhAA==.Barnabus:BAAANQAECgMIAwAAAA==.Barristan:BAAANQADCgMIBQAAAA==.Barzalie:BAAANQAECgEIAQABNQAFFAYIGQAKAEAbAA==.Bathrezz:BAABNQAECn8XAAMRAAgK0Bf5TgDYAQARAAcKWxb5TgDYAQASAAUKygpkMwGfAAAAAA==.',
Be='Beandruid:BAAANQAECgYIBwAAAA==.Beanmage:BAAANQAECgUIBQAAAA==.Beanshaman:BAAANQADCgYIBgAAAA==.Bearlyawake:BAAANQADCgUIBQAAAA==.Beerbelly:BAABNQAECn88AAITAAoKZCAnAwBlAwATAAoKZCAnAwBlAwABNQAFFAYIGQAKAEAbAA==.Beleaves:BAACNQAFFH8cAAITAAYK9ggiBABkAQATAAYK9ggiBABkAQA1AAQKfzUAAhMACgo6F18HAPYBABMACgo6F18HAPYBAAAA.Bellectra:BAABNQAECn8pAAQDAAkKkgfGqABSAQADAAkKkgfGqABSAQACAAIKxgZhPQBLAAAUAAEK9wSXDwATAAAAAA==.',
Bi='Bifurious:BAABNQAECn8aAAIVAAkKIhvQCgAZAgAVAAkKIhvQCgAZAgAAAA==.',
Bl='Blathur:BAAANQAECgQIBAAAAA==.Bluereindeer:BAABNQAECn80AAIKAAoKyRCwMwB7AQAKAAoKyRCwMwB7AQAAAA==.',
Bo='Bobafina:BAAANQADCggICAAAAA==.Bobsstones:BAACNQAFFH8WAAQWAAgKQhlgAQBLAQAWAAUKxRRgAQBLAQAXAAMKKxdjIQDsAAAYAAIK+x3wCgCjAAA1AAQKfzIABBYACgrvJfADAGcCABYACgrTIPADAGcCABcABgrNJLiMAMcBABgABQqhHw8WALwBAAAA.Bobstofu:BAAANQAECgcIEwAAAA==.Bofaðeez:BAAANQADCgQIBAAAAA==.Bombtimer:BAAANQADCgQIBgABNQADCgUICQAEAAAAAA==.Bonkulo:BAABNQAECn87AAQKAAoK7RTaJQDNAQAKAAoK7RTaJQDNAQAOAAMKCwmfiACVAAAPAAQKZQVjYwB/AAAAAA==.Boofassist:BAACNQAFFH8YAAIRAAgKFR3qAwBOAgARAAgKFR3qAwBOAgA1AAQKfzcAAhEACgoyJccDALYDABEACgoyJccDALYDAAAA.Boomsonic:BAAANQAECgQIBwABNQAECgkJGgAVACIbAA==.Bophadeez:BAAANQAECgEIAQABNQAFFAUIDAAZAKULAA==.Boraga:BAAANQADCgYJBwAAAA==.',
Br='Brienyx:BAAANQADCgUIBwAAAA==.Brietemis:BAABNQAECn8bAAIMAAkKDA1aagDuAQAMAAkKDA1aagDuAQAAAA==.Briezani:BAABNQAECn8uAAMIAAoKxA3ESwCnAQAIAAoKxA3ESwCnAQABAAIKowKoJAEoAAAAAA==.Briogan:BAAANQAECgUICQAAAA==.Broccoliz:BAECNQAFFH8gAAIJAAkKNxHbAgApAgAJAAkKNxHbAgApAgA1AAQKf00AAwkACgp4HukKAB8DAAkACgp4HukKAB8DABoAAQpXFsmqAEEAAAAA.Brokan:BAABNQAECn8cAAMbAAoK1whuLgDUAAAcAAcKSQu1iAANAQAbAAgKRAVuLgDUAAAAAA==.Broke:BAAANQAECgIIAgABNQAFFAgIIgAdAH4jAQ==.',
Bu='Bukhaki:BAAANQAECggIDgABNQAECgoKLwAbAOUdAA==.',
['Bõ']='Bõb:BAAANQAECgEIAQAAAA==.',
Ca='Caden:BAAANQAECgYICwABNQAECgoKPwAFAOkVAA==.Cafca:BAABNQAECn9DAAIWAAoKGRRLBgAOAgAWAAoKGRRLBgAOAgAAAA==.Caké:BAAANQADCgYIDAAAAA==.Caldrr:BAAANQAECgEIAQAAAA==.Caylva:BAABNQAECn8gAAMDAAoKNx43IwCyAgADAAoKjhw3IwCyAgACAAEKDxX+OQBHAAABNQAFFAYIGQAKAEAbAA==.',
Ch='Chrams:BAABNQAECn9JAAIRAAoK7R8OFwAgAwARAAoK7R8OFwAgAwAAAA==.',
Ci='Cialis:BAAANQADCgYIJgAAAA==.',
Cl='Clearlyumad:BAAANQAECgQIBwAAAA==.Clèrick:BAABNQAECn9FAAMRAAoK0CJSIwDeAgARAAoK0CJSIwDeAgAeAAcKhw0YMgBQAQAAAA==.',
Co='Coldcrow:BAAANQADCgUICQAAAA==.Combination:BAABNQAECn8vAAIfAAoKiCCHBwAaAwAfAAoKiCCHBwAaAwABNQAFFAUIDAAJAOcYAA==.Cowen:BAAANQADCggIEwAAAA==.',
Cr='Crash:BAAANQADCgUIBQABNQAFFAYIDgAEAAAAAA==.Cray:BAAANQAECggIEwABNQAECgkJGwAeAG8UAA==.',
Cu='Cursedotter:BAAANQAECgcIDwAAAA==.Cursewords:BAAANQAECggICgAAAA==.',
Da='Dabbyshatner:BAABNQAECn8WAAMIAAcKZAnWtgAlAQAIAAcKZAnWtgAlAQABAAEKIgJhKAElAAAAAA==.Daeneryis:BAAANQAECgQIAwAAAA==.Dankshammy:BAABNQAECn88AAIBAAoKWR2xEgAjAwABAAoKWR2xEgAjAwAAAA==.Darkwave:BAACNQAFFH8FAAMXAAMKxQlPKgCJAAAXAAIK8ghPKgCJAAAYAAEKbQvWFABCAAA1AAQKfzcAAxgACgrOFVQ8ANAAABcACArTE+auAHMBABgAAwp5E1Q8ANAAAAAA.Darthdiddyus:BAACNQAFFH8PAAIgAAQKaBdyAQBCAQAgAAQKaBdyAQBCAQA1AAQKfysAAiAACQpUIbkCACMDACAACQpUIbkCACMDAAAA.Dathunter:BAAANQAECgIIAgABNQAECgkJKgADADwZAA==.Datshammy:BAAANQAECgEIAQABNQAECgkJKgADADwZAA==.Dawghawg:BAAANQADCgUIBgAAAA==.Dawnnie:BAACNQAFFH8MAAIeAAQKTA0bCACvAAAeAAQKTA0bCACvAAA1AAQKfzgAAh4ACgqtHDkOALcCAB4ACgqtHDkOALcCAAAA.Dawsonrogers:BAABNQAECn8dAAMVAAkKhxSnCgAeAgAVAAgKMRenCgAeAgANAAMKvg0cKQGEAAAAAA==.Dazshir:BAAANQAECgEIAQAAAA==.',
De='Deathbanana:BAAANQADCggICAABNQAFFAkJIAADAFUgAA==.Deathbydk:BAACNQAFFH8ZAAIKAAYKQBvuCwBOAQAKAAYKQBvuCwBOAQA1AAQKfzIAAgoACgpXJAoHABYDAAoACgpXJAoHABYDAAAA.Deathkow:BAAANQAECggIAwAAAA==.Deaththreat:BAAANQABCgEIAQABNQAECgoKLwASAEEZAA==.Delema:BAACNQAFFH8PAAISAAYKRg3QCAC9AQASAAYKRg3QCAC9AQA1AAQKfzYAAxIACgp6H4VfAHoCABIACgp6H4VfAHoCAB4ABQpWDU8+ALEAAAAA.Derbina:BAAANQABCgIIBAAAAA==.Destructer:BAAANQAECgUIEgAAAA==.',
Di='Dicey:BAAANQAECgEIAgABNQAECgkJGgAVACIbAA==.Dirtydinker:BAAANQAECgcICQAAAA==.Dixsard:BAABNQAECn8vAAMbAAoK5R3DGQCvAgAbAAkKLBvDGQCvAgAcAAgKvhjsUADAAQAAAA==.',
Do='Docmcstuffin:BAAANQADCgMIAwAAAA==.Dontblink:BAAANQAECgEIAQABNQAFFAUIDAAJAOcYAA==.Dorin:BAAANQABCgQIBAAAAA==.Dotore:BAAANQADCgYIBgAAAA==.Dottyflu:BAACNQAFFH8SAAIKAAYKkxV2DwBdAQAKAAYKkxV2DwBdAQA1AAQKfzsAAgoACgoQJGcEAD4DAAoACgoQJGcEAD4DAAAA.Dottylawful:BAABNQAFFH8IAAIeAAYKbQZXBwADAQAeAAYKbQZXBwADAQABNQAFFAYIEgAKAJMVAA==.',
Dr='Drexbear:BAAANQAECgQJBAABNQAFFAYIEAAhALQNAA==.Drexl:BAACNQAFFH8QAAIhAAYKtA0DAwBJAQAhAAYKtA0DAwBJAQA1AAQKfzIAAyEACgoPHw8GAKYCACEACgoPHw8GAKYCAA0ACQpGCMCsAK0BAAAA.',
Dw='Dweams:BAACNQAFFH8fAAIiAAgKuRR6BAAEAgAiAAgKuRR6BAAEAgA1AAQKfzoAAyIACgqqJYEEADIDACIACgqqJYEEADIDACMABgoxGqcMAG0BAAAA.Dweamu:BAAANQAECgEIAQABNQAFFAgIHwAiALkUAA==.',
Ec='Ectonight:BAAANQADCgIIAgAAAA==.',
Eg='Eggfooyung:BAAANQAFFAIIAgABNQAFFAgIGAARABUdAA==.Egwene:BAAANQAECgEIAQAAAA==.',
El='Elbowdeep:BAAANQADCgEIAQAAAA==.Elhonna:BAACNQAFFH8JAAIMAAQKsg/oFwDUAAAMAAQKsg/oFwDUAAA1AAQKf0wAAgwACgoZIKYpAPICAAwACgoZIKYpAPICAAAA.',
En='Endcredits:BAABNQAECn8xAAIKAAkKYBbBJQDOAQAKAAkKYBbBJQDOAQAAAA==.',
Er='Eridyn:BAABNQAECn8VAAIRAAcK+BpOQAATAgARAAcK+BpOQAATAgAAAA==.',
Ev='Evoulker:BAACNQAFFH8lAAIZAAkK5BltAwBaAgAZAAkK5BltAwBaAgA1AAQKf0MAAhkACgp4Hy8LAPACABkACgp4Hy8LAPACAAAA.',
Ey='Eyyosmite:BAAANQABCgIIAgAAAA==.',
Ez='Ezekielle:BAAANQAECgEIAQAAAA==.',
Fa='Faire:BAAANQADCgIIAgABNQAECgcIDwAEAAAAAA==.Fairytale:BAACNQAFFH8fAAIkAAcKABDfCwDLAQAkAAcKABDfCwDLAQA1AAQKf0IAAyMACgqUIJQGACACACQACgqdH+klANMCACMABwrkHJQGACACAAAA.Faker:BAAANQADCggIDwAAAA==.Favijina:BAAANQABCggIEgAAAA==.',
Fe='Felheim:BAACNQAFFH8XAAIGAAcKLRIoBABQAQAGAAcKLRIoBABQAQA1AAQKf1sAAgYACgobIkoGAG0DAAYACgobIkoGAG0DAAAA.Fellithà:BAAANQADCgUIBgAAAA==.',
Fi='Fists:BAAANQADCgYIDAABNQAFFAUIDAAZAKULAA==.',
Fl='Flink:BAAANQADCgIJAgAAAA==.Floogi:BAAANQADCgMIAwAAAA==.',
Fo='Foeshammer:BAAANQADCgcIBwAAAA==.Foxygal:BAAANQADCggIEwAAAA==.',
Fr='Frostyninja:BAAANQAECgIIAgAAAA==.',
Ga='Garchomp:BAAANQADCgQICAAAAA==.Gawain:BAAANQAECgYICwABNQAECgoKRAAMADYfAA==.',
Ge='Gellina:BAAANQADCgUICAAAAA==.Georg:BAACNQAFFH8cAAISAAkKdBkWAgB9AgASAAkKdBkWAgB9AgA1AAQKfzoAAhIACgqDJtoCAIADABIACgqDJtoCAIADAAAA.Geriatric:BAAANQAECgIIBQABNQAFFAkJIAAOAKQfAA==.',
Gl='Glathur:BAAANQADCgIIBAAAAA==.Glizzygagger:BAACNQAFFH8HAAMiAAMKhyBSEADJAAAiAAMKhyBSEADJAAAjAAIKsxZpAgCoAAA1AAQKfyQAAyIACgpsIr4MAB4DACIACQpSIr4MAB4DACMAAgpcIBANALsAAAE1AAUUBQgGACAAJRQA.Glizzygorger:BAABNQAECn8eAAIGAAgKVR5kIQBBAgAGAAgKVR5kIQBBAgABNQAFFAUIBgAgACUUAA==.',
Go='Goodbye:BAABNQAECn8eAAMDAAkKzhlGeQCLAgADAAkKzhlGeQCLAgAUAAEKAAD+DQAzAAAAAA==.Goregazme:BAAANQAECgYICwAAAA==.',
Gr='Grantoro:BAABNQAECn86AAIlAAoKQhErHQC4AQAlAAoKQhErHQC4AQAAAA==.Grimmblades:BAAANQAECgIIAgAAAA==.Grootbeer:BAABNQAECn8xAAIMAAoKnRMobwDjAQAMAAoKnRMobwDjAQAAAA==.',
Gu='Gulgrimmar:BAACNQAFFH8fAAQIAAkKAxvrCADhAQAIAAYKlRvrCADhAQABAAQK3RoCFQAKAQAHAAEKAABTCgAAAAA1AAQKfzoAAwgACgq5JgsBAIoDAAgACgq5JgsBAIoDAAEABgpwHWt8AJYBAAAA.Guwudanielle:BAAANQAECgcIDwAAAA==.',
['Gä']='Gävinräd:BAAANQADCgUIBQAAAA==.',
Ha='Haranguetan:BAAANQADCgYIBgABNQAECgoKNAAHAIEMAA==.Hardfeelings:BAABNQAECn8vAAISAAoKQRnHSABQAgASAAoKQRnHSABQAgAAAA==.Harrharr:BAAANQADCgMIAwAAAA==.',
He='Headache:BAAANQABCgIIAgABNQAECgkJGgAVACIbAA==.Hexappeal:BAAANQAECgcIBgAAAA==.',
Hu='Hurjek:BAACNQAFFH8MAAIJAAUK5xjoBgCJAQAJAAUK5xjoBgCJAQA1AAQKf0QAAgkACgrqI8MDAIsDAAkACgrqI8MDAIsDAAAA.',
Ic='Iconicmax:BAAANQAECgQICwAAAA==.',
Ij='Ijustankedu:BAAANQADCgEIAQAAAA==.',
Il='Ilyana:BAABNQAECn82AAMDAAoKICJuTgAkAgADAAkKGiFuTgAkAgACAAIKKCIZKgCnAAAAAA==.',
In='Insights:BAABNQAECn8nAAIMAAkKWhKgdADWAQAMAAkKWhKgdADWAQAAAA==.',
Ja='Jaqen:BAACNQAFFH8GAAIgAAUKJRRcAQBPAQAgAAUKJRRcAQBPAQA1AAQKfykABCAACQolJNICAB4DACAACQolJNICAB4DABwAAQqsHUHJAFkAABsAAQrBGchZAEoAAAAA.Jayc:BAACNQAFFH8KAAIDAAYKfRHwGQAlAQADAAYKfRHwGQAlAQA1AAQKfyoAAgMACgrbH641AB4DAAMACgrbH641AB4DAAAA.',
Je='Jereico:BAACNQAFFH8fAAMmAAkK+RtKAQCVAgAmAAkK+RtKAQCVAgAQAAEKqxojDwBHAAA1AAQKf0IAAyYACgo9JlgAAHMDACYACgo9JlgAAHMDABAACAr5EkwZALQBAAAA.Jeryhn:BAACNQAFFH8gAAIRAAcKYBXMCgCwAQARAAcKYBXMCgCwAQA1AAQKfz0AAhEACgpnI84OAFQDABEACgpnI84OAFQDAAAA.',
Jo='Joeynodz:BAAANQAECgEIAQAAAA==.Jortshorts:BAABNQAECn8sAAInAAoKdQkXGAB4AQAnAAoKdQkXGAB4AQAAAA==.',
Ju='Juggalo:BAACNQAFFH8UAAMQAAcK4BLZBAB7AQAQAAYKuRXZBAB7AQAmAAEKeQd/DwBDAAA1AAQKf1gAAxAACgqeJMwAAF0DABAACgqeJMwAAF0DACYAAgoKDWYeAG4AAAAA.June:BAACNQAFFH8cAAIfAAgKGBArAgAXAgAfAAgKGBArAgAXAgA1AAQKf0MAAx8ACgpzITIHAAYDAB8ACgpzITIHAAYDACgAAQo3DsxbADkAAAAA.',
Ka='Kalikin:BAAANQAECgMJBAAAAA==.Kawasuoo:BAAANQADCgQIBAABNQAECgcIDwAEAAAAAA==.',
Kc='Kcudüm:BAABNQAECn80AAQYAAoKSxIoDgAXAgAYAAgK0xUoDgAXAgAXAAYK6AYM/ADTAAAWAAIKNAMILwA4AAAAAA==.',
Ke='Keifis:BAAANQADCgEJAQAAAA==.Keifism:BAAANQABCgMIAwAAAA==.',
Kh='Khaotichic:BAAANQAECgEIAQAAAA==.',
Kl='Klrum:BAABNQAECn8kAAMCAAgKrxdxHgD4AAADAAcKThgCvAAMAgACAAUKqBBxHgD4AAAAAA==.',
Ko='Koddin:BAABNQAECn84AAISAAoKlRsMPwDYAgASAAoKlRsMPwDYAgAAAA==.Komui:BAABNQAECn84AAMBAAoKkBZETgArAgABAAoKkBZETgArAgAIAAcKeQ/lggCdAQAAAA==.Koonlei:BAAANQAECgQIBAAAAA==.Koraxx:BAAANQADCgUIAwAAAA==.Koreth:BAACNQAFFH8gAAMbAAkKZhCJAgBcAgAbAAkKZhCJAgBcAgAcAAIK9w67FQBCAAA1AAQKfzsAAxwACgosJWcIADcDABwACgpqImcIADcDABsACgptIvkKADIDAAAA.Kornholyo:BAAANQAECgIIAwAAAA==.',
Kr='Krakheeta:BAAANQADCgQIBAAAAA==.Krusade:BAAANQAECgUICQAAAA==.',
Ku='Kumo:BAAANQAECgEIAQAAAA==.Kutuzov:BAAANQAECgUIDgAAAA==.',
Kw='Kwenny:BAAANQAECgEIAQAAAA==.',
La='Lailaysia:BAABNQAECn8hAAIkAAoKGSLbBwC2AwAkAAoKGSLbBwC2AwAAAA==.Lamemoosaur:BAABNQAECn8YAAIlAAkKOxxgCAD2AgAlAAkKOxxgCAD2AgAAAA==.Laríca:BAACNQAFFH8SAAIRAAQKaR3fDwBEAQARAAQKaR3fDwBEAQA1AAQKfz8AAhEACgpOI3sIAIQDABEACgpOI3sIAIQDAAAA.Lavabursting:BAAANQAECggIDwABNQAFFAUIBgAgACUUAA==.Laydout:BAAANQADCgQIBAABNQAECgkJFAAMAHccAA==.Laydoutyota:BAABNQAECn8UAAIMAAkKdxy9WABpAgAMAAkKdxy9WABpAgAAAA==.Laymow:BAAANQAECgQJBAABNQAECgkJGAAlADscAA==.',
Le='Levity:BAAANQAECggIBQAAAA==.',
Li='Lilea:BAABNQAECn8/AAMFAAoK6RUjLQADAQAMAAcKiRU3qAC1AQAFAAkKEg4jLQADAQAAAA==.Lilfaart:BAAANQAECggIBAAAAA==.Lilotterine:BAAANQAECgYIBwAAAA==.Lindisalvia:BAAANQADCggIEQAAAA==.Lionsmane:BAAANQADCgYIBgAAAA==.',
Lo='Loosemorals:BAACNQAFFH8MAAIZAAUKpQvtCwBAAQAZAAUKpQvtCwBAAQA1AAQKfzQAAxkACgrnGLkQAJ8CABkACgrnGLkQAJ8CABAAAQoQFHI6ADwAAAAA.Lootgoblin:BAABNQAECn8qAAIDAAkKPBmCkQBdAgADAAkKPBmCkQBdAgAAAA==.Lortherian:BAABNQAECn8dAAIhAAoKeBO0EACrAQAhAAoKeBO0EACrAQAAAA==.',
Lu='Lunatique:BAAANQADCgQIBAAAAA==.',
['Lä']='Läwlbringer:BAABNQAECn8cAAISAAoK9A8plwD1AQASAAoK9A8plwD1AQAAAA==.',
Ma='Mabritoe:BAACNQAFFH8HAAIbAAQK1SN3CgBZAQAbAAQK1SN3CgBZAQA1AAQKfyMAAxsACQrMJJwPAAQDABsACArMJJwPAAQDABwACAqSCa4iALQBAAE1AAUUBwgYABoAhRUA.Maccabee:BAAANQAECgEIAQAAAA==.Magicstick:BAAANQAECgEIAQAAAA==.Magooh:BAAANQADCgcIBwABNQAECgcIFgAlAFIYAA==.Malison:BAAANQADCgUIBAAAAA==.Mangle:BAAANQADCgUIBQAAAA==.Mania:BAAANQADCgYICgABNQAECgkJGgAVACIbAA==.Mareth:BAAANQADCgIIAgAAAA==.Mathath:BAABNQAECn8tAAMPAAkK8xydPwAfAgAPAAkKlhydPwAfAgAKAAMKYx92fQAEAQAAAA==.Mathoras:BAAANQADCgYIBgAAAA==.Maxboom:BAAANQAECgMIAwAAAA==.Mayaho:BAAANQAECgQIEwABNQAECgcIFgAlAFIYAA==.Maylee:BAABNQAECn8jAAIJAAoKDQ9sJADTAQAJAAoKDQ9sJADTAQAAAA==.',
Me='Meandean:BAAANQAECgYICgAAAA==.Meatier:BAAANQAECgUICwABNQAECgkJGgAVACIbAA==.Meenako:BAAANQAECgEIAQAAAA==.Mellinia:BAAANQADCgEIAQAAAA==.',
Mi='Miltonroe:BAABNQAECn80AAIHAAoKgQwAGADoAQAHAAoKgQwAGADoAQAAAA==.Miltonroé:BAAANQAECgQICQABNQAECgoKNAAHAIEMAA==.Mixing:BAAANQADCgIJAgAAAA==.',
Mo='Monnz:BAAANQADCgUIBQAAAA==.Monsterskill:BAABNQAECn8aAAIXAAkKqBdTSgD1AQAXAAkKqBdTSgD1AQAAAA==.Moonerva:BAABNQAECn8sAAIaAAkKHw56MQB9AQAaAAkKHw56MQB9AQAAAA==.Morana:BAAANQAECgMIBQAAAA==.',
Mu='Munchinmuff:BAAANQAECgQIBQAAAA==.',
Mv='Mvqchx:BAAANQADCgEIAQAAAA==.',
My='Myrolous:BAAANQADCgQIBAAAAA==.',
['Mã']='Mãrtrydóm:BAAANQAECgEIAQAAAA==.',
['Mì']='Mìssy:BAAANQAECgUIAgAAAA==.',
Na='Namiin:BAAANQADCgUIBQAAAA==.Namikaze:BAAANQAECgIIBgAAAA==.Natara:BAAANQADCgYICgAAAA==.Naughtye:BAAANQAECgQICAAAAA==.Nave:BAAANQAECgcICAAAAA==.',
Ne='Nelfsfault:BAAANQADCggJFwAAAA==.Nerotappo:BAAANQABCgIIAgAAAA==.',
Ni='Ninja:BAAANQADCgYJBgAAAA==.',
No='Nobacon:BAAANQADCgIIAgAAAA==.Noshaku:BAAANQAECgYICgAAAA==.Notanorc:BAABNQAECn8xAAMVAAoKBhC4FQBAAQANAAoK7QwNkgDvAQAVAAUKMRO4FQBAAQAAAA==.',
Oh='Ohrolam:BAABNQAECn85AAMDAAoKTwrb4gDDAQADAAoKAwjb4gDDAQACAAUKEgwLJgCuAAAAAA==.',
Ok='Okasan:BAAANQAECgQICAABNQAECgcIGwAfAAMTAA==.',
Or='Oromis:BAAANQAECgYIEAABNQAFFAUIBgAgACUUAA==.',
Ot='Ottersdemons:BAAANQAECgMIAwAAAA==.',
Pa='Palthur:BAAANQAECgUIEAAAAA==.Panzer:BAAANQAECgIIAgABNQAECggIAwAEAAAAAA==.Passionate:BAAANQAECgEIAQAAAA==.',
Ph='Phatmidas:BAABNQAECn82AAISAAoK5RdSVAAwAgASAAoK5RdSVAAwAgAAAA==.Phleat:BAAANQAECgUIBQABNQAECgoKSQASAMYWAA==.Phrozenpally:BAAANQAECgQICwABNQAECgcIFgAlAFIYAA==.',
Pi='Pika:BAAANQAECgMIBgABNQAFFAYIGQAKAEAbAA==.Pinbull:BAAANQADCgEIAQAAAA==.Pinkponythug:BAAANQAECgYICQABNQAFFAUIDAAZAKULAA==.',
Pl='Plagueground:BAACNQAFFH8dAAQOAAgKqiD8AQA9AgAOAAcKBCP8AQA9AgAKAAIK5xRpJQBmAAAPAAEKsA9hJAA7AAA1AAQKf0kABA8ACgqIJnoBAHUDAA4ACgqBJnkCAMEDAA8ACgrKJXoBAHUDAAoAAgrlJZGcAKEAAAAA.Plutonyus:BAAANQAECgQIBgAAAA==.',
Po='Poc:BAAANQAECgUICQAAAA==.Porterhaus:BAAANQADCggICAABNQAFFAYIDgAXAGEQAA==.Pounces:BAABNQAECn9FAAInAAoKCiZiAQDBAwAnAAoKCiZiAQDBAwAAAA==.',
Pr='Prózak:BAAANQADCgYIBgABNQAECgoKRwAeAF8ZAA==.Prôzak:BAABNQAECn9HAAIeAAoKXxn3DQBMAgAeAAoKXxn3DQBMAgAAAA==.',
Ps='Psychomidget:BAABNQAECn8fAAQjAAoKjRJxAwBLAgAjAAoKjRJxAwBLAgAkAAEK0gEBAwEdAAAiAAEKPgEpkwAWAAAAAA==.',
Pu='Puetrid:BAACNQAFFH8OAAMXAAYKYRAdEgAZAQAXAAYKORAdEgAZAQAYAAIKRA/+DwCUAAA1AAQKfzkAAxgACgrAG/IFALICABgACQrXFfIFALICABcACQqJGUcsAF0CAAAA.Purble:BAAANQADCgIIAgAAAA==.Puufrumslli:BAABNQAECn8UAAIMAAkKLA8liAD6AQAMAAkKLA8liAD6AQAAAA==.',
Ra='Rageinglight:BAAANQAECgMIBQAAAA==.Rakku:BAAANQABCgcJBgAAAA==.Rautha:BAABNQAECn8cAAISAAgKBBJDqQDNAQASAAgKBBJDqQDNAQAAAA==.Rayl:BAAANQAECgEIAQAAAA==.',
Re='Rekt:BAABNQAECn8aAAIQAAoKsBRpCAD8AQAQAAoKsBRpCAD8AQAAAA==.',
Rh='Rhaegon:BAABNQAECn8tAAILAAkKCBxGBQDeAgALAAkKCBxGBQDeAgAAAA==.',
Ri='Rimath:BAAANQADCggIEAAAAA==.Riverpaw:BAAANQAECgIIAgAAAA==.',
Rn='Rng:BAABNQAECn8bAAIeAAkKbxQjEwD7AQAeAAkKbxQjEwD7AQAAAA==.',
Ro='Rodstewart:BAABNQAECn8VAAMMAAkKZBQolADgAQAMAAgKhRUolADgAQAFAAMKsQsadQBmAAAAAA==.Ronz:BAAANQABCgEJAQAAAA==.Roofeo:BAAANQAECgEIAQABNQAECgoKOwAKAO0UAA==.Rotdaddy:BAABNQAECn8wAAIPAAoK8AgiMgBeAQAPAAoK8AgiMgBeAQAAAA==.',
Sa='Sabatikus:BAAANQAECgEIAQAAAA==.Salino:BAABNQAECn8pAAIaAAkKxxBnKwCmAQAaAAkKxxBnKwCmAQAAAA==.Salinoster:BAAANQAECgYICwABNQAECgkJKQAaAMcQAA==.Sam:BAAANQAECgcIEQAAAA==.Sandorindis:BAAANQADCgYIBwAAAA==.Sarate:BAAANQADCggIEAAAAA==.Satral:BAAANQAECgYIBwAAAA==.Savannah:BAAANQAECgYIBwABNQAECgcIDwAEAAAAAA==.Savvtwo:BAAANQADCgEIAQABNQAFFAgIIgAdAH4jAQ==.',
Se='Sezra:BAAANQADCggICAAAAA==.',
Sh='Shaetahn:BAAANQAECgEIAQAAAA==.Shamwowthorn:BAAANQADCgEIAQAAAA==.Shinanigans:BAABNQAECn89AAISAAkKix+ZNwDxAgASAAkKix+ZNwDxAgAAAA==.Shockbull:BAAANQADCgcJBwAAAA==.',
Si='Silverbäck:BAAANQAECgYIDAABNQAECgkJGwAHAHcLAA==.Silverslam:BAAANQAECgIIAgABNQAECgkJGwAHAHcLAA==.',
Sk='Skippitypaps:BAAANQADCgIIAgAAAA==.Skullflux:BAAANQADCgIIAgABNQAFFAMIBQAXAMUJAA==.Skurge:BAABNQAECn8kAAMOAAoKRQ2rOQC5AQAOAAoKRQ2rOQC5AQAKAAEK2APcsQAfAAAAAA==.',
Sn='Snacks:BAAANQADCgEIAQABNQAECgcIEQAEAAAAAA==.Snuffles:BAAANQADCggIDgAAAA==.',
So='Solstis:BAAANQAECgUICQAAAA==.Soranwena:BAABNQAECn8uAAIlAAoKfBeHGADFAQAlAAoKfBeHGADFAQAAAA==.Sorros:BAAANQAECgQIBQAAAA==.',
Sp='Spacegoat:BAAANQAECgMIAwAAAA==.Spfzero:BAAANQAECgEIAQAAAA==.Spookybuns:BAAANQAECggIEAAAAA==.',
St='Sticksy:BAAANQADCgYIBgAAAA==.Stonebeard:BAAANQAECgQIBgAAAA==.Stârlèss:BAAANQADCgYIBwAAAA==.',
Su='Subtox:BAABNQAECn8VAAIcAAoKsRJgOwAOAgAcAAoKsRJgOwAOAgAAAA==.',
Sw='Swedishfish:BAAANQAECgEIAQABNQAECgkJHQAiAP4dAA==.',
['Sá']='Sálúd:BAAANQAECgcIEQAAAA==.',
['Sê']='Sêp:BAAANQAECgIIAgAAAA==.',
Ta='Taranith:BAAANQAECggIBQAAAA==.Tarhealeon:BAAANQAECgYIDgAAAA==.Tarvuspls:BAABNQAECn8dAAMMAAgKZBNSiAD6AQAMAAgKZBNSiAD6AQAFAAUK7QU+VgDNAAAAAA==.',
Te='Teemawthy:BAAANQADCgYICgAAAA==.Temozo:BAAANQADCgIIAgAAAA==.Terranox:BAAANQAECgEIAQAAAA==.',
Th='Thabigone:BAAANQAECgIIAgAAAA==.Theceo:BAAANQADCgYIDgAAAA==.Thorb:BAABNQAECn8ZAAIeAAkKRBvjIABoAQAeAAkKRBvjIABoAQABNQAFFAYIGQAKAEAbAA==.',
Ti='Ticklemebutt:BAAANQAECgcIEgAAAA==.Tiewaz:BAABNQAECn8UAAISAAgKpwrS2AApAQASAAgKpwrS2AApAQAAAA==.',
To='Tolun:BAABNQAECn8xAAICAAoKfBvxBQBvAgACAAoKfBvxBQBvAgAAAA==.Tonarui:BAAANQAECgUICgAAAA==.Tosan:BAABNQAECn8bAAIfAAcKAxMaGAB/AQAfAAcKAxMaGAB/AQAAAA==.Toughcookie:BAABNQAECn8lAAMSAAoKDAucrwBxAQASAAoKDAucrwBxAQARAAIKPgR2FwFGAAAAAA==.',
Tr='Treeplague:BAABNQAECn8kAAMjAAgKsw48CwCOAQAjAAgKsw48CwCOAQAiAAIK4QQ3bQBQAAAAAA==.',
Tu='Turn:BAACNQAFFH8iAAQYAAkK3Q6DAgD1AAAWAAQK+g00AgAAAQAYAAMK7RODAgD1AAAXAAQKowtfIgDnAAA1AAQKfzUABBgACgpBI9wPAAACABcABwqFIM11AAECABgABwpPF9wPAAACABYABQqFJS4KANcBAAAA.Turtleduck:BAAANQAECgIIAgABNQAECgoKIwAJAJUYAA==.',
Ty='Tyla:BAAANQAECggICAAAAA==.Typhis:BAAANQAECgQIBAAAAA==.',
['Tì']='Tìewaz:BAAANQAECgQIBgABNQAECggIFAASAKcKAA==.',
Um='Umbryx:BAAANQAECgEIAQAAAA==.',
Un='Unagi:BAABNQAECn82AAIHAAoKDxGrEgA/AgAHAAoKDxGrEgA/AgAAAA==.',
Va='Valdir:BAAANQAECggIBgAAAA==.Vasomir:BAAANQABCgIIAQAAAA==.',
Ve='Venomstrikes:BAAANQADCgcIBwAAAA==.Venøm:BAAANQAECgEIAQAAAA==.Vexxen:BAAANQAECgIIAwAAAA==.',
Vi='Viscerion:BAAANQAECgYIEAAAAA==.',
Vo='Voids:BAAANQAECgUIBQAAAA==.',
Wh='Whoarlock:BAAANQAECgEIAQAAAA==.',
Wi='Wizzyy:BAAANQADCgUIBQAAAA==.',
Wo='Wo:BAAANQADCgEIAQABNQAECgkJGwAeAG8UAA==.',
Xe='Xelinia:BAACNQAFFH8RAAMiAAUKoQd6DAAcAQAiAAQKoQd6DAAcAQAkAAEK9AIIOAA/AAA1AAQKfzMAAyIACgo4HeUTAB4CACIACgo4HeUTAB4CACQAAQrfAV8KAR8AAAAA.',
Xi='Xiboute:BAAANQAECgQIBAAAAA==.',
Xu='Xuefeng:BAACNQAFFH8VAAIoAAUKLhBBCgAiAQAoAAUKLhBBCgAiAQA1AAQKf0kAAigACgp6H+0LABcDACgACgp6H+0LABcDAAAA.',
Ya='Yahwae:BAAANQAECgcIEQABNQAFFAMIBQAXAMUJAA==.',
Yc='Ycephyre:BAAANQAECgcICQAAAA==.',
Ye='Yenchmeister:BAACNQAFFH8aAAINAAcKDBfvBgBSAgANAAcKDBfvBgBSAgA1AAQKfzIAAg0ACgq3JEcdAEIDAA0ACgq3JEcdAEIDAAAA.',
Yo='Yomahma:BAAANQAECgUIBgAAAA==.',
Yu='Yuta:BAAANQADCgQIBAAAAA==.',
Zd='Zdervish:BAABNQAECn8cAAIbAAgKmBkjKQBKAgAbAAgKmBkjKQBKAgAAAA==.',
Ze='Zeffira:BAAANQAECgUIBQAAAA==.Zellda:BAAANQAECgcIDwABNQAECgoKRAAMADYfAA==.',
Zi='Zilvanic:BAABNQAECn8tAAQeAAkKBw2IMQDzAAAeAAgK1A6IMQDzAAARAAUK8QYtsAC8AAASAAEKAADl1QEAAAAAAA==.Zilvanion:BAACNQAFFH8HAAMXAAQKGgfVHgC7AAAXAAQKjwbVHgC7AAAWAAEKbAV4GgA/AAA1AAQKf0QAAhcACgrGF6ZBABECABcACgrGF6ZBABECAAAA.',
Zl='Zlathur:BAAANQADCgcIDgAAAA==.',
Zo='Zourbeast:BAAANQADCgQIBAAAAA==.Zourknight:BAAANQADCgcICAAAAA==.Zourlight:BAAANQADCgcIEgAAAA==.Zourlock:BAAANQADCggIEAAAAA==.Zourstorm:BAAANQADCgUIBQAAAA==.Zourvoid:BAAANQADCggIGAAAAA==.',
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
