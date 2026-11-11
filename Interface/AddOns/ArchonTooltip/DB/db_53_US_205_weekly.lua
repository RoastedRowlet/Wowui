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

local lookup = {'Shaman-Restoration','Mage-Frost','Mage-Arcane','Unknown-Unknown','Hunter-Marksmanship','DemonHunter-Devourer','Shaman-Enhancement','Druid-Restoration','DeathKnight-Blood','DemonHunter-Vengeance','Hunter-BeastMastery','Warrior-Arms','DeathKnight-Frost','DeathKnight-Unholy','Shaman-Elemental','Evoker-Preservation','Monk-Brewmaster','Mage-Fire','Warrior-Fury','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Paladin-Holy','Druid-Balance','Rogue-Assassination','Rogue-Subtlety','Paladin-Protection','Monk-Mistweaver','Rogue-Outlaw','Paladin-Retribution','Warrior-Protection','Priest-Shadow','Priest-Discipline','Priest-Holy','Druid-Guardian','Evoker-Augmentation','Evoker-Devastation','Druid-Feral','Monk-Windwalker',}
local provider = {region='US',realm='Stonemaul',name='US',type='weekly',zone=53,date='2026-11-10',data={Ad='Addalar:BAABNQAECn8cAAIBAAkKZxrNIQCdAgABAAkKZxrNIQCdAgAAAA==.',
Ai='Airvis:BAABNQAECn8pAAMCAAgKPRIADAD8AQACAAgKPRIADAD8AQADAAMKxQYGngGJAAAAAA==.',
Ak='Akamie:BAAANQAECgUIBgABNQAECgcIDwAEAAAAAA==.Akar:BAAANQADCgMIAwAAAA==.',
Al='Alacia:BAAANQADCgQIBAABNQAECgoKOwAFAFEVAA==.Albinomonk:BAAANQADCgMIAwAAAA==.Alundre:BAAANQAECgUIBQAAAA==.',
Am='Amaira:BAAANQAECgEIAQAAAA==.Amalakar:BAAANQAECgEIAQAAAA==.Amnezea:BAAANQADCgIIAgAAAA==.',
An='Anankei:BAAANQADCgYIBgAAAA==.Anavere:BAAANQADCgUIBQAAAA==.Annasia:BAAANQAECgEIAQAAAA==.Antte:BAACNQAFFH8YAAIGAAYKRxWtBQDSAQAGAAYKRxWtBQDSAQA1AAQKfyQAAgYACQquIwYLACwDAAYACQquIwYLACwDAAAA.',
Ar='Arjun:BAABNQAECn8VAAMHAAgKOAzQFQCdAQAHAAgKOAzQFQCdAQABAAcK0g3bcABKAQAAAA==.Armindru:BAABNQAECn8jAAIIAAoKlRi0FABoAgAIAAoKlRi0FABoAgAAAA==.Armingothele:BAAANQAECgEIAQABNQAECgoKIwAIAJUYAA==.Arrol:BAAANQADCgIIAgAAAA==.Arturogh:BAAANQAECggIDwABNQAECgoKMQAJAKwSAA==.',
As='Asmôdeô:BAABNQAECn8jAAMGAAoKzCLiBQD6AgAGAAoKzCLiBQD6AgAKAAEK6SLCKgBeAAAAAA==.Astin:BAAANQAECgEIAQAAAA==.',
At='Atom:BAABNQAECn8rAAILAAoKKw/uUwAOAgALAAoKKw/uUwAOAgAAAA==.Atreyu:BAABNQAECn8qAAIMAAgKTw2ycQCXAQAMAAgKTw2ycQCXAQAAAA==.',
Au='Aureille:BAAANQAECgQIAwAAAA==.',
Aw='Awoozehl:BAACNQAFFH8gAAMNAAkKpB9vAADLAgANAAgK1yFvAADLAgAOAAIKbheAEABXAAA1AAQKf0IAAw0ACgq9Jt8AAIwDAA0ACgq9Jt8AAIwDAA4ACAoiG31cAJ4BAAAA.',
Az='Azgrodon:BAABNQAECn81AAMPAAoKyxltTQBBAgAPAAoKyxltTQBBAgABAAgKEgoLjABrAQAAAA==.',
Ba='Banatok:BAAANQADCgIIAwAAAA==.Bangungot:BAAANQAECgMIAwABNQAFFAkJGgAQACQUAA==.Barnabus:BAAANQAECgMIAwAAAA==.Barristan:BAAANQADCgMIBQAAAA==.Barzalie:BAAANQAECgEIAQABNQAFFAUIGAAJAN4eAA==.Bathrezz:BAAANQAECgUIDwAAAA==.',
Be='Beandruid:BAAANQAECgYIBwAAAA==.Beanmage:BAAANQAECgUIBQAAAA==.Beanshaman:BAAANQADCgYIBgAAAA==.Bearlyawake:BAAANQADCgUIBQAAAA==.Beerbelly:BAABNQAECn88AAIRAAoKZCAnAwBlAwARAAoKZCAnAwBlAwABNQAFFAUIGAAJAN4eAA==.Beleaves:BAACNQAFFH8cAAIRAAYK9ggiBABkAQARAAYK9ggiBABkAQA1AAQKfzUAAhEACgo6F8kGAPcBABEACgo6F8kGAPcBAAAA.Bellectra:BAABNQAECn8mAAQDAAgKjwcY0QD2AAADAAcKFAgY0QD2AAACAAIKxgZhPQBLAAASAAEK9wQFDgAUAAAAAA==.',
Bi='Bifurious:BAABNQAECn8aAAITAAkKIhvQCgAZAgATAAkKIhvQCgAZAgAAAA==.',
Bl='Blathur:BAAANQAECgMIAwAAAA==.Bluereindeer:BAABNQAECn80AAIJAAoKyRCgLwCDAQAJAAoKyRCgLwCDAQAAAA==.',
Bo='Bobafina:BAAANQADCggICAAAAA==.Bobsstones:BAACNQAFFH8WAAQUAAgKQhlgAQBLAQAUAAUKxRRgAQBLAQAVAAMKKxdjIQDsAAAWAAIK+x3wCgCjAAA1AAQKfzIABBQACgrvJWkDAHACABQACgrTIGkDAHACABUABgrNJLiMAMcBABYABQqhHw8WALwBAAAA.Bobstofu:BAAANQAECgcIEwAAAA==.Bofaðeez:BAAANQADCgQIBAAAAA==.Bombtimer:BAAANQADCgQIBgABNQADCgUICQAEAAAAAA==.Bonkulo:BAABNQAECn8xAAQJAAoKrBIvRgDhAQAJAAoKrBIvRgDhAQANAAMKCwnXfwCaAAAOAAQKZQX9XgCAAAAAAA==.Boofassist:BAACNQAFFH8YAAIXAAgKFR3qAwBOAgAXAAgKFR3qAwBOAgA1AAQKfzcAAhcACgoyJccDALYDABcACgoyJccDALYDAAAA.Boomsonic:BAAANQAECgQIBwABNQAECgkJGgATACIbAA==.Bophadeez:BAAANQAECgEIAQABNQAFFAUIDAAQAKULAA==.Boraga:BAAANQADCgYJBwAAAA==.',
Br='Brienyx:BAAANQADCgUIBwAAAA==.Brietemis:BAAANQAECgcIEgAAAA==.Briezani:BAABNQAECn8oAAMPAAkKJQyoWwBcAQAPAAkKJQyoWwBcAQABAAIKowKoJAEoAAAAAA==.Briogan:BAAANQAECgUICQAAAA==.Broccoliz:BAECNQAFFH8gAAIIAAkKNxHbAgApAgAIAAkKNxHbAgApAgA1AAQKf00AAwgACgp4HqILAPoCAAgACgp4HqILAPoCABgAAQpXFsmqAEEAAAAA.Brokan:BAABNQAECn8ZAAMZAAoKWQiDLADXAAAaAAcKfwoQgQACAQAZAAgKRAWDLADXAAAAAA==.Broke:BAAANQAECgIIAgAAAQ==.',
Bu='Bukhaki:BAAANQAECggIDgABNQAECgoKLwAZAOUdAA==.',
['Bõ']='Bõb:BAAANQAECgEIAQAAAA==.',
Ca='Caden:BAAANQAECgYICwABNQAECgoKOwAFAFEVAA==.Cafca:BAABNQAECn86AAIUAAoKFRMPBgAEAgAUAAoKFRMPBgAEAgAAAA==.Caké:BAAANQADCgYIDAAAAA==.Caldrr:BAAANQAECgEIAQAAAA==.Caylva:BAABNQAECn8gAAMDAAoKNx51HwC5AgADAAoKjhx1HwC5AgACAAEKDxV7NgBHAAABNQAFFAUIGAAJAN4eAA==.',
Ch='Chrams:BAABNQAECn9JAAIXAAoK7R8OFwAgAwAXAAoK7R8OFwAgAwAAAA==.',
Ci='Cialis:BAAANQADCgYIJgAAAA==.',
Cl='Clearlyumad:BAAANQAECgQIBwAAAA==.Clèrick:BAABNQAECn9FAAMXAAoK0CJSIwDeAgAXAAoK0CJSIwDeAgAbAAcKhw0YMgBQAQAAAA==.',
Co='Coldcrow:BAAANQADCgUICQAAAA==.Combination:BAABNQAECn8vAAIcAAoKiCCHBwAaAwAcAAoKiCCHBwAaAwABNQAFFAUIDAAIAOcYAA==.Cowen:BAAANQADCggIEwAAAA==.',
Cr='Crash:BAAANQADCgUIBQABNQAFFAUIDQAEAAAAAA==.Cray:BAAANQAECgcIEgABNQAECggIEQAEAAAAAA==.',
Cu='Cursedotter:BAAANQAECgcIDwAAAA==.Cursewords:BAAANQAECgcICQAAAA==.',
Da='Dabbyshatner:BAABNQAECn8VAAMPAAcKZAnWtgAlAQAPAAcKZAnWtgAlAQABAAEKIgJhKAElAAAAAA==.Daeneryis:BAAANQAECgQIAwAAAA==.Dankshammy:BAABNQAECn88AAIBAAoKWR1HEAApAwABAAoKWR1HEAApAwAAAA==.Darkwave:BAACNQAFFH8FAAMVAAMKxQlEJgCMAAAVAAIK8ghEJgCMAAAWAAEKbQt6EwBDAAA1AAQKfzcAAxYACgrOFVQ8ANAAABUACArTE+KRACIBABYAAwp5E1Q8ANAAAAAA.Darthdiddyus:BAACNQAFFH8PAAIdAAQKaBdyAQBCAQAdAAQKaBdyAQBCAQA1AAQKfysAAh0ACQpUIbkCACMDAB0ACQpUIbkCACMDAAAA.Dathunter:BAAANQAECgIIAgABNQAECgkJKgADADwZAA==.Datshammy:BAAANQAECgEIAQABNQAECgkJKgADADwZAA==.Dawghawg:BAAANQADCgUIBgAAAA==.Dawnnie:BAACNQAFFH8MAAIbAAQKTA1OBwCvAAAbAAQKTA1OBwCvAAA1AAQKfzgAAhsACgqtHDkOALcCABsACgqtHDkOALcCAAAA.Dawsonrogers:BAABNQAECn8dAAMTAAkKhxSnCgAeAgATAAgKMRenCgAeAgAMAAMKvg0cKQGEAAAAAA==.',
De='Deathbanana:BAAANQADCggICAABNQAFFAkJGAADAIwcAA==.Deathbydk:BAACNQAFFH8YAAIJAAUK3h6sDQALAQAJAAUK3h6sDQALAQA1AAQKfzIAAgkACgpXJFIGAB0DAAkACgpXJFIGAB0DAAAA.Deathkow:BAAANQAECggIAwAAAA==.Delema:BAACNQAFFH8PAAIeAAYKRg3QCAC9AQAeAAYKRg3QCAC9AQA1AAQKfzYAAx4ACgp6H4VfAHoCAB4ACgp6H4VfAHoCABsABQpWDT86ALEAAAAA.Derbina:BAAANQABCgIIBAAAAA==.Destructer:BAAANQAECgQIEAAAAA==.',
Di='Dicey:BAAANQAECgEIAgABNQAECgkJGgATACIbAA==.Dirtydinker:BAAANQAECgcICQAAAA==.Dixsard:BAABNQAECn8vAAMZAAoK5R3DGQCvAgAZAAkKLBvDGQCvAgAaAAgKvhgNSQDBAQAAAA==.',
Do='Docmcstuffin:BAAANQADCgMIAwAAAA==.Dontblink:BAAANQAECgEIAQABNQAFFAUIDAAIAOcYAA==.Dorin:BAAANQABCgQIBAAAAA==.Dotore:BAAANQADCgYIBgAAAA==.Dottyflu:BAACNQAFFH8SAAIJAAYKkxV2DwBdAQAJAAYKkxV2DwBdAQA1AAQKfzsAAgkACgoQJAQEAEIDAAkACgoQJAQEAEIDAAAA.Dottylawful:BAABNQAFFH8IAAIbAAYKbQZXBwADAQAbAAYKbQZXBwADAQABNQAFFAYIEgAJAJMVAA==.',
Dr='Drexbear:BAAANQAECgQJBAABNQAFFAYIEAAfALQNAA==.Drexl:BAACNQAFFH8QAAIfAAYKtA0DAwBJAQAfAAYKtA0DAwBJAQA1AAQKfzIAAx8ACgoPH3QFAKwCAB8ACgoPH3QFAKwCAAwACQpGCMCsAK0BAAAA.',
Dw='Dweams:BAACNQAFFH8fAAIgAAgKuRR6BAAEAgAgAAgKuRR6BAAEAgA1AAQKfzoAAyAACgqqJRQEADMDACAACgqqJRQEADMDACEABgoxGqcMAG0BAAAA.Dweamu:BAAANQAECgEIAQABNQAFFAgIHwAgALkUAA==.',
Ec='Ectonight:BAAANQADCgIIAgAAAA==.',
Eg='Eggfooyung:BAAANQAFFAIIAgABNQAFFAgIGAAXABUdAA==.Egwene:BAAANQAECgEIAQAAAA==.',
El='Elbowdeep:BAAANQADCgEIAQAAAA==.Elhonna:BAACNQAFFH8JAAILAAQKsg90FQDXAAALAAQKsg90FQDXAAA1AAQKf0wAAgsACgoZIKYpAPICAAsACgoZIKYpAPICAAAA.',
En='Endcredits:BAABNQAECn8qAAIJAAgKshOjNgBdAQAJAAgKshOjNgBdAQAAAA==.',
Er='Eridyn:BAABNQAECn8VAAIXAAcK+BrwOgAZAgAXAAcK+BrwOgAZAgAAAA==.',
Ev='Evoulker:BAACNQAFFH8lAAIQAAkK5BltAwBaAgAQAAkK5BltAwBaAgA1AAQKf0MAAhAACgp4Hy8LAPACABAACgp4Hy8LAPACAAAA.',
Ey='Eyyosmite:BAAANQABCgIIAgAAAA==.',
Ez='Ezekielle:BAAANQAECgEIAQAAAA==.',
Fa='Faire:BAAANQADCgIIAgABNQAECgcIDwAEAAAAAA==.Fairytale:BAACNQAFFH8fAAIiAAcKABDfCwDLAQAiAAcKABDfCwDLAQA1AAQKf0IAAyEACgqUIJQGACACACIACgqdH+klANMCACEABwrkHJQGACACAAAA.Faker:BAAANQADCggIDwAAAA==.',
Fe='Felheim:BAACNQAFFH8VAAIGAAYKohUpBQAZAQAGAAYKohUpBQAZAQA1AAQKf1sAAgYACgobIkoGAG0DAAYACgobIkoGAG0DAAAA.Fellithà:BAAANQADCgUIBgAAAA==.',
Fi='Fists:BAAANQADCgYIDAABNQAFFAUIDAAQAKULAA==.',
Fl='Flink:BAAANQADCgIJAgAAAA==.Floogi:BAAANQADCgMIAwAAAA==.',
Fo='Foeshammer:BAAANQADCgcIBwAAAA==.Foxygal:BAAANQADCggIEwAAAA==.',
Fr='Frostyninja:BAAANQAECgIIAgAAAA==.',
Ga='Garchomp:BAAANQADCgQICAAAAA==.Gawain:BAAANQAECgYICwABNQAECgoKQAALAOEcAA==.',
Ge='Gellina:BAAANQADCgUICAAAAA==.Georg:BAACNQAFFH8cAAIeAAkKdBkWAgB9AgAeAAkKdBkWAgB9AgA1AAQKfzoAAh4ACgqDJkMCAIUDAB4ACgqDJkMCAIUDAAAA.Geriatric:BAAANQAECgIIBQABNQAFFAkJIAANAKQfAA==.',
Gl='Glathur:BAAANQADCgIIBAAAAA==.Glizzygagger:BAACNQAFFH8HAAMgAAMKhyBSEADJAAAgAAMKhyBSEADJAAAhAAIKsxZpAgCoAAA1AAQKfyQAAyAACgpsIr4MAB4DACAACQpSIr4MAB4DACEAAgpcIEQMALsAAAE1AAUUBQgGAB0AJRQA.Glizzygorger:BAABNQAECn8eAAIGAAgKVR5kIQBBAgAGAAgKVR5kIQBBAgABNQAFFAUIBgAdACUUAA==.',
Go='Goodbye:BAABNQAECn8eAAMDAAkKzhlGeQCLAgADAAkKzhlGeQCLAgASAAEKAAD+DQAzAAAAAA==.Goregazme:BAAANQAECgcICwAAAA==.',
Gr='Grantoro:BAABNQAECn86AAIjAAoKQhErHQC4AQAjAAoKQhErHQC4AQAAAA==.Grimmblades:BAAANQAECgIIAgAAAA==.Grootbeer:BAABNQAECn8wAAILAAoKkBPfZADiAQALAAoKkBPfZADiAQAAAA==.',
Gu='Gulgrimmar:BAACNQAFFH8fAAQPAAkKAxvrCADhAQAPAAYKlRvrCADhAQABAAQK3RoCFQAKAQAHAAEKAACYCQAAAAA1AAQKfzoAAw8ACgq5Jt8AAIsDAA8ACgq5Jt8AAIsDAAEABgpwHWt8AJYBAAAA.Guwudanielle:BAAANQAECgcIDwAAAA==.',
['Gä']='Gävinräd:BAAANQADCgUIBQAAAA==.',
Ha='Haranguetan:BAAANQADCgYIBgABNQAECgoKMQAHAB0MAA==.Hardfeelings:BAABNQAECn8pAAIeAAkKkhjVXwACAgAeAAkKkhjVXwACAgAAAA==.Harrharr:BAAANQADCgMIAwAAAA==.',
He='Headache:BAAANQABCgIIAgABNQAECgkJGgATACIbAA==.Hexappeal:BAAANQAECgcIBgAAAA==.',
Ho='Hodann:BAAANQABCgYIBgAAAA==.',
Hu='Hurjek:BAACNQAFFH8MAAIIAAUK5xj1BQCOAQAIAAUK5xj1BQCOAQA1AAQKf0AAAggACgrqI8MDAIsDAAgACgrqI8MDAIsDAAAA.',
Ic='Iconicmax:BAAANQAECgQICwAAAA==.',
Ij='Ijustankedu:BAAANQADCgEIAQAAAA==.',
Il='Ilyana:BAABNQAECn82AAMDAAoKICIlRwAqAgADAAkKGiElRwAqAgACAAIKKCIZKgCnAAAAAA==.',
In='Insights:BAABNQAECn8kAAILAAgKaxPafwCfAQALAAgKaxPafwCfAQAAAA==.',
Ja='Jaqen:BAACNQAFFH8GAAIdAAUKJRRcAQBPAQAdAAUKJRRcAQBPAQA1AAQKfygAAx0ACQolJNICAB4DAB0ACQolJNICAB4DABkAAQrBGaBXAEoAAAAA.Jayc:BAACNQAFFH8KAAIDAAYKfRFpFQAvAQADAAYKfRFpFQAvAQA1AAQKfyoAAgMACgrbH641AB4DAAMACgrbH641AB4DAAAA.',
Je='Jereico:BAACNQAFFH8fAAMkAAkK+RtKAQCVAgAkAAkK+RtKAQCVAgAlAAEKqxojDwBHAAA1AAQKf0IAAyQACgo9JlEAAHQDACQACgo9JlEAAHQDACUACAr5EkwZALQBAAAA.Jeryhn:BAACNQAFFH8gAAIXAAcKYBXMCgCwAQAXAAcKYBXMCgCwAQA1AAQKfz0AAhcACgpnI84OAFQDABcACgpnI84OAFQDAAAA.',
Jo='Joeynodz:BAAANQAECgEIAQAAAA==.Jortshorts:BAABNQAECn8sAAImAAoKdQkXGAB4AQAmAAoKdQkXGAB4AQAAAA==.',
Ju='Juggalo:BAACNQAFFH8UAAMlAAcK4BLZBAB7AQAlAAYKuRXZBAB7AQAkAAEKeQfoDQBEAAA1AAQKf08AAyUACgqaJPUAAEoDACUACgqaJPUAAEoDACQAAgoKDWYeAG4AAAAA.June:BAACNQAFFH8cAAIcAAgKGBArAgAXAgAcAAgKGBArAgAXAgA1AAQKf0MAAxwACgpzIZwGAAsDABwACgpzIZwGAAsDACcAAQo3DjRXADkAAAAA.',
Ka='Kalikin:BAAANQAECgMJBAAAAA==.Kawasuoo:BAAANQADCgQIBAABNQAECgcIDwAEAAAAAA==.',
Kc='Kcudüm:BAABNQAECn80AAQWAAoKSxIoDgAXAgAWAAgK0xUoDgAXAgAVAAYK6AYM/ADTAAAUAAIKNAMILwA4AAAAAA==.',
Ke='Keifis:BAAANQADCgEJAQAAAA==.Keifism:BAAANQABCgMIAwAAAA==.',
Kh='Khaotichic:BAAANQAECgEIAQAAAA==.',
Kl='Klrum:BAABNQAECn8kAAMCAAgKrxdxHgD4AAADAAcKThgCvAAMAgACAAUKqBBxHgD4AAAAAA==.',
Ko='Koddin:BAABNQAECn84AAIeAAoKlRsMPwDYAgAeAAoKlRsMPwDYAgAAAA==.Komui:BAABNQAECn84AAMBAAoKkBZETgArAgABAAoKkBZETgArAgAPAAcKeQ/lggCdAQAAAA==.Koonlei:BAAANQAECgQIBAAAAA==.Koraxx:BAAANQADCgUIAwAAAA==.Koreth:BAACNQAFFH8gAAMZAAkKZhCJAgBcAgAZAAkKZhCJAgBcAgAaAAIK9w67FQBCAAA1AAQKfzsAAxoACgosJbkHADgDABoACgpqIrkHADgDABkACgptIvkKADIDAAAA.Kornholyo:BAAANQAECgIIAwAAAA==.',
Kr='Krakheeta:BAAANQADCgQIBAAAAA==.Krusade:BAAANQAECgUICQAAAA==.',
Ku='Kumo:BAAANQAECgEIAQAAAA==.Kutuzov:BAAANQAECgUIDQAAAA==.',
Kw='Kwenny:BAAANQAECgEIAQAAAA==.',
La='Lailaysia:BAABNQAECn8gAAIiAAoKGSKbBgC7AwAiAAoKGSKbBgC7AwAAAA==.Lamemoosaur:BAABNQAECn8YAAIjAAkKOxxgCAD2AgAjAAkKOxxgCAD2AgAAAA==.Landfilltwo:BAAANQADCgEIAQAAAA==.Laríca:BAACNQAFFH8PAAIXAAQKaR0ADgBLAQAXAAQKaR0ADgBLAQA1AAQKfz4AAhcACgpOI3sIAIQDABcACgpOI3sIAIQDAAAA.Lavabursting:BAAANQAECgQIBwABNQAFFAUIBgAdACUUAA==.Laydout:BAAANQADCgQIBAABNQAECgkJFAALAHccAA==.Laydoutyota:BAABNQAECn8UAAILAAkKdxy9WABpAgALAAkKdxy9WABpAgAAAA==.Laymow:BAAANQAECgQJBAABNQAECgkJGAAjADscAA==.',
Le='Levity:BAAANQAECggIBQAAAA==.',
Li='Lilea:BAABNQAECn87AAMFAAoKURXRKwD4AAALAAcKiRU3qAC1AQAFAAkKZA3RKwD4AAAAAA==.Lilfaart:BAAANQAECggIBAAAAA==.Lilotterine:BAAANQAECgYIBwAAAA==.Lindisalvia:BAAANQADCggIEQAAAA==.Lionsmane:BAAANQADCgYIBgAAAA==.',
Lo='Loosemorals:BAACNQAFFH8MAAIQAAUKpQt0CgBFAQAQAAUKpQt0CgBFAQA1AAQKfzQAAxAACgrnGLkQAJ8CABAACgrnGLkQAJ8CACUAAQoQFHI6ADwAAAAA.Lootgoblin:BAABNQAECn8qAAIDAAkKPBmCkQBdAgADAAkKPBmCkQBdAgAAAA==.Lortherian:BAABNQAECn8VAAIfAAgKbRXkFQBMAQAfAAgKbRXkFQBMAQAAAA==.',
Lu='Lunatique:BAAANQADCgQIBAAAAA==.',
['Lä']='Läwlbringer:BAABNQAECn8aAAIeAAkKyRAplwD1AQAeAAkKyRAplwD1AQAAAA==.',
Ma='Mabritoe:BAACNQAFFH8HAAIZAAQK1SN3CgBZAQAZAAQK1SN3CgBZAQA1AAQKfyMAAxkACQrMJJwPAAQDABkACArMJJwPAAQDABoACAqSCa4iALQBAAE1AAUUBwgYABgAhRUA.Maccabee:BAAANQAECgEIAQAAAA==.Magicstick:BAAANQAECgIIAQAAAA==.Magooh:BAAANQADCgcIBwABNQAECgcIFgAjAFIYAA==.Malison:BAAANQADCgUIBAAAAA==.Mangle:BAAANQADCgUIBQAAAA==.Mania:BAAANQADCgYICgABNQAECgkJGgATACIbAA==.Mareth:BAAANQADCgIIAgAAAA==.Mathath:BAABNQAECn8pAAMOAAkKjxydPwAfAgAOAAkKQBudPwAfAgAJAAMKYx92fQAEAQAAAA==.Mathoras:BAAANQADCgYIBgAAAA==.Maxboom:BAAANQAECgMIAwAAAA==.Mayaho:BAAANQAECgQIEwABNQAECgcIFgAjAFIYAA==.Maylee:BAABNQAECn8iAAIIAAoK4A5OIQDSAQAIAAoK4A5OIQDSAQAAAA==.',
Me='Meandean:BAAANQAECgYICgAAAA==.Meatier:BAAANQAECgUICwABNQAECgkJGgATACIbAA==.Meenako:BAAANQAECgEIAQAAAA==.Mellinia:BAAANQADCgEIAQAAAA==.',
Mi='Miltonroe:BAABNQAECn8xAAIHAAoKHQwAGADoAQAHAAoKHQwAGADoAQAAAA==.Miltonroé:BAAANQAECgQICQABNQAECgoKMQAHAB0MAA==.Mixing:BAAANQADCgIJAgAAAA==.',
Mo='Monnz:BAAANQADCgUIBQAAAA==.Monsterskill:BAAANQAECgcIDwAAAA==.Moonerva:BAABNQAECn8pAAIYAAgKVQ7cNQBKAQAYAAgKVQ7cNQBKAQAAAA==.Morana:BAAANQAECgMIBQAAAA==.',
Mu='Munchinmuff:BAAANQAECgQIBQAAAA==.',
Mv='Mvqchx:BAAANQADCgEIAQAAAA==.',
My='Myrolous:BAAANQADCgQIBAAAAA==.',
['Mã']='Mãrtrydóm:BAAANQAECgEIAQAAAA==.',
['Mì']='Mìssy:BAAANQAECgUIAgAAAA==.',
Na='Namiin:BAAANQADCgUIBQAAAA==.Namikaze:BAAANQAECgIIBgAAAA==.Natara:BAAANQADCgYICgAAAA==.Naughtye:BAAANQAECgQIBwAAAA==.Nave:BAAANQAECgcICAAAAA==.',
Ne='Nelfsfault:BAAANQADCggJFwAAAA==.Nerotappo:BAAANQABCgIIAgAAAA==.',
Ni='Ninja:BAAANQADCgYJBgAAAA==.',
No='Nobacon:BAAANQADCgIIAgAAAA==.Noshaku:BAAANQAECgYICQAAAA==.Notanorc:BAABNQAECn8xAAMTAAoKBhC4FQBAAQAMAAoK7QypegCAAQATAAUKMRO4FQBAAQAAAA==.',
Oh='Ohrolam:BAABNQAECn85AAMDAAoKTwrb4gDDAQADAAoKAwjb4gDDAQACAAUKEgw2IwCuAAAAAA==.',
Ok='Okasan:BAAANQAECgQICAABNQAECgcIGwAcAAMTAA==.',
Or='Oromis:BAAANQAECgYIDgABNQAFFAUIBgAdACUUAA==.',
Ot='Ottersdemons:BAAANQAECgMIAwAAAA==.',
Pa='Palthur:BAAANQAECgUIDwAAAA==.Panzer:BAAANQAECgIIAgABNQAECggIAwAEAAAAAA==.Passionate:BAAANQAECgEIAQAAAA==.',
Ph='Phatmidas:BAABNQAECn82AAIeAAoK5RebSwA3AgAeAAoK5RebSwA3AgAAAA==.Phleat:BAAANQADCgYIBgABNQAECgoKRQAeAMYVAA==.Phrozenpally:BAAANQAECgQICwABNQAECgcIFgAjAFIYAA==.',
Pi='Pika:BAAANQAECgMIBgABNQAFFAUIGAAJAN4eAA==.Pinbull:BAAANQADCgEIAQAAAA==.Pinkponythug:BAAANQAECgYICQABNQAFFAUIDAAQAKULAA==.',
Pl='Plagueground:BAACNQAFFH8dAAQNAAgKqiD8AQA9AgANAAcKBCP8AQA9AgAJAAIK5xRpJQBmAAAOAAEKsA9hJAA7AAA1AAQKf0kABA4ACgqIJi8BAHgDAA0ACgqBJnkCAMEDAA4ACgrKJS8BAHgDAAkAAgrlJZGcAKEAAAAA.Plutonyus:BAAANQAECgUIBgAAAA==.',
Po='Poc:BAAANQAECgUICQAAAA==.Porterhaus:BAAANQADCggICAABNQAFFAYIDgAVAGEQAA==.Pounces:BAABNQAECn9FAAImAAoKCiZiAQDBAwAmAAoKCiZiAQDBAwAAAA==.',
Pr='Prózak:BAAANQADCgYIBgABNQAECgoKPQAbAOYXAA==.Prôzak:BAABNQAECn89AAIbAAoK5hciDwAjAgAbAAoK5hciDwAjAgAAAA==.',
Ps='Psychomidget:BAABNQAECn8fAAQhAAoKjRIXAwBTAgAhAAoKjRIXAwBTAgAiAAEK0gH59wAfAAAgAAEKPgEpkwAWAAAAAA==.',
Pu='Puetrid:BAACNQAFFH8OAAMVAAYKYRDcDgAhAQAVAAYKORDcDgAhAQAWAAIKRA/+DwCUAAA1AAQKfzkAAxYACgrAG/IFALICABYACQrXFfIFALICABUACQqJGXAnAGMCAAAA.Purble:BAAANQADCgIIAgAAAA==.Puufrumslli:BAABNQAECn8UAAILAAkKLA8liAD6AQALAAkKLA8liAD6AQAAAA==.',
Ra='Rageinglight:BAAANQAECgMIBQAAAA==.Rakku:BAAANQABCgcJBgAAAA==.Rautha:BAABNQAECn8cAAIeAAgKBBJDqQDNAQAeAAgKBBJDqQDNAQAAAA==.Rayl:BAAANQAECgEIAQAAAA==.',
Re='Rekt:BAABNQAECn8aAAIlAAoKsBTbBwD8AQAlAAoKsBTbBwD8AQAAAA==.',
Rh='Rhaegon:BAABNQAECn8tAAIKAAkKCBxGBQDeAgAKAAkKCBxGBQDeAgAAAA==.',
Ri='Rimath:BAAANQADCggIEAAAAA==.Riverpaw:BAAANQAECgIIAgAAAA==.',
Rn='Rng:BAAANQAECggIEQAAAA==.',
Ro='Rodstewart:BAABNQAECn8VAAMLAAkKZBQolADgAQALAAgKhRUolADgAQAFAAMKsQsadQBmAAAAAA==.Ronz:BAAANQABCgEJAQAAAA==.Roofeo:BAAANQAECgEIAQABNQAECgoKMQAJAKwSAA==.Rotdaddy:BAABNQAECn8wAAIOAAoK8AgOLwBfAQAOAAoK8AgOLwBfAQAAAA==.',
Sa='Sabatikus:BAAANQAECgEIAQAAAA==.Salino:BAABNQAECn8iAAIYAAkKtwu4MwBXAQAYAAkKtwu4MwBXAQAAAA==.Salinoster:BAAANQAECgMIBAABNQAECgkJIgAYALcLAA==.Sam:BAAANQAECgcIEQAAAA==.Sandorindis:BAAANQADCgYIBwAAAA==.Sarate:BAAANQADCggIEAAAAA==.Satral:BAAANQAECgYIBwAAAA==.Savannah:BAAANQAECgYIBwABNQAECgcIDwAEAAAAAA==.Savvtwo:BAAANQADCgEIAQABNQAECgIIAgAEAAAAAQ==.',
Se='Sezra:BAAANQADCggICAAAAA==.',
Sh='Shaetahn:BAAANQAECgEIAQAAAA==.Shamwowthorn:BAAANQADCgEIAQAAAA==.Shinanigans:BAABNQAECn89AAIeAAkKix+ZNwDxAgAeAAkKix+ZNwDxAgAAAA==.Shockbull:BAAANQADCgcJBwAAAA==.',
Si='Silverbäck:BAAANQAECgYIDAABNQAECggIFQAHADgMAA==.Silverslam:BAAANQAECgIIAgABNQAECggIFQAHADgMAA==.',
Sk='Skippitypaps:BAAANQADCgIIAgAAAA==.Skullflux:BAAANQADCgIIAgABNQAFFAMIBQAVAMUJAA==.Skurge:BAABNQAECn8cAAINAAkKqg15QwB1AQANAAkKqg15QwB1AQAAAA==.',
Sn='Snacks:BAAANQADCgEIAQABNQAECgcIEQAEAAAAAA==.Snuffles:BAAANQADCggIDgAAAA==.',
So='Solstis:BAAANQAECgUICQAAAA==.Soranwena:BAABNQAECn8pAAIjAAoKfBddFgDFAQAjAAoKfBddFgDFAQAAAA==.Sorros:BAAANQAECgQIBQAAAA==.',
Sp='Spacegoat:BAAANQAECgMIAwAAAA==.Spfzero:BAAANQAECgEIAQAAAA==.Spookybuns:BAAANQAECggIEAAAAA==.',
St='Sticksy:BAAANQADCgYIBgAAAA==.Stonebeard:BAAANQAECgQIBgAAAA==.Stârlèss:BAAANQADCgYIBwAAAA==.',
Su='Subtox:BAABNQAECn8VAAIaAAoKsRLlNQAPAgAaAAoKsRLlNQAPAgAAAA==.',
Sw='Swedishfish:BAAANQAECgEIAQABNQAECgkJHQAgAP4dAA==.',
['Sá']='Sálúd:BAAANQAECgcIEQAAAA==.',
['Sê']='Sêp:BAAANQAECgIIAgAAAA==.',
Ta='Taranith:BAAANQAECggIAwAAAA==.Tarhealeon:BAAANQAECgYIDgAAAA==.Tarvuspls:BAABNQAECn8dAAMLAAgKZBNSiAD6AQALAAgKZBNSiAD6AQAFAAUK7QU+VgDNAAAAAA==.',
Te='Teemawthy:BAAANQADCgYICgAAAA==.Temozo:BAAANQADCgIIAgAAAA==.',
Th='Thabigone:BAAANQAECgIIAgAAAA==.Theceo:BAAANQADCgYIDgAAAA==.Thorb:BAABNQAECn8XAAIbAAkKRBv7HQBpAQAbAAkKRBv7HQBpAQABNQAFFAUIGAAJAN4eAA==.',
Ti='Ticklemebutt:BAAANQAECgcIEgAAAA==.Tiewaz:BAABNQAECn8UAAIeAAgKpwrwyAAtAQAeAAgKpwrwyAAtAQAAAA==.',
To='Tolun:BAABNQAECn8wAAICAAoKfBssBQB2AgACAAoKfBssBQB2AgAAAA==.Tonarui:BAAANQAECgUICgAAAA==.Tosan:BAABNQAECn8bAAIcAAcKAxNkFgCCAQAcAAcKAxNkFgCCAQAAAA==.Toughcookie:BAABNQAECn8lAAMeAAoKDAtuoQB1AQAeAAoKDAtuoQB1AQAXAAIKPgR2FwFGAAAAAA==.',
Tr='Treeplague:BAABNQAECn8kAAMhAAgKsw5/BgBqAQAhAAgKsw5/BgBqAQAgAAIK4QQ3bQBQAAAAAA==.',
Tu='Turn:BAACNQAFFH8iAAQWAAkK3Q6DAgD1AAAUAAQK+g00AgAAAQAWAAMK7RODAgD1AAAVAAQKowtfIgDnAAA1AAQKfzMABBYACgpBI9wPAAACABUABwqFIM11AAECABYABwpPF9wPAAACABQABQqFJS4KANcBAAAA.Turtleduck:BAAANQAECgIIAgABNQAECgoKIwAIAJUYAA==.',
Ty='Tyla:BAAANQAECggICAAAAA==.Typhis:BAAANQAECgQIBAAAAA==.',
['Tì']='Tìewaz:BAAANQAECgQIBgABNQAECggIFAAeAKcKAA==.',
Um='Umbryx:BAAANQAECgEIAQAAAA==.',
Un='Unagi:BAABNQAECn82AAIHAAoKDxH7EQDfAQAHAAoKDxH7EQDfAQAAAA==.',
Va='Valdir:BAAANQAECggIBgAAAA==.Vasomir:BAAANQABCgIIAQAAAA==.',
Ve='Venomstrikes:BAAANQADCgcIBwAAAA==.Venøm:BAAANQAECgEIAQAAAA==.Vexxen:BAAANQAECgIIAwAAAA==.',
Vi='Viscerion:BAAANQAECgYIEAAAAA==.',
Vo='Voids:BAAANQAECgUIBQAAAA==.',
Wh='Whoarlock:BAAANQAECgEIAQAAAA==.',
Wi='Wizzyy:BAAANQADCgUIBQAAAA==.',
Wo='Wo:BAAANQADCgEIAQABNQAECggIEQAEAAAAAA==.',
Xe='Xelinia:BAACNQAFFH8RAAMgAAUKoQd6DAAcAQAgAAQKoQd6DAAcAQAiAAEK9AIIOAA/AAA1AAQKfzMAAyAACgo4HW0SAB4CACAACgo4HW0SAB4CACIAAQrfAV8KAR8AAAAA.',
Xi='Xiboute:BAAANQAECgQIBAAAAA==.',
Xu='Xuefeng:BAACNQAFFH8QAAInAAUKChBBCgAiAQAnAAUKChBBCgAiAQA1AAQKf0kAAicACgp6H+0LABcDACcACgp6H+0LABcDAAAA.',
Ya='Yahwae:BAAANQAECgcIEQABNQAFFAMIBQAVAMUJAA==.',
Yc='Ycephyre:BAAANQAECgcICQAAAA==.',
Ye='Yenchmeister:BAACNQAFFH8aAAIMAAcKDBfvBgBSAgAMAAcKDBfvBgBSAgA1AAQKfzIAAgwACgq3JEcdAEIDAAwACgq3JEcdAEIDAAAA.',
Yo='Yomahma:BAAANQAECgUIBgAAAA==.',
Yu='Yuta:BAAANQADCgQIBAAAAA==.',
Zd='Zdervish:BAABNQAECn8cAAIZAAgKmBkjKQBKAgAZAAgKmBkjKQBKAgAAAA==.',
Ze='Zeffira:BAAANQAECgUIBQAAAA==.Zellda:BAAANQAECgYIDwABNQAECgoKQAALAOEcAA==.',
Zi='Zilvanic:BAABNQAECn8mAAQbAAkK1QxxLwDrAAAbAAgKmg5xLwDrAAAXAAUKxAYLpwC/AAAeAAEKAADxwgEAAAAAAA==.Zilvanion:BAACNQAFFH8HAAMVAAQKGgcoGwC+AAAVAAQKjwYoGwC+AAAUAAEKbAUAFgA/AAA1AAQKf0QAAhUACgrGF3g7ABUCABUACgrGF3g7ABUCAAAA.',
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
