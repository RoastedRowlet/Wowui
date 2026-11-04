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

local lookup = {'Shaman-Restoration','Mage-Frost','Mage-Arcane','Unknown-Unknown','Hunter-Marksmanship','DemonHunter-Devourer','Druid-Restoration','DeathKnight-Blood','DemonHunter-Vengeance','Hunter-BeastMastery','Warrior-Arms','DeathKnight-Frost','DeathKnight-Unholy','Shaman-Elemental','Evoker-Preservation','Monk-Brewmaster','Warrior-Fury','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Paladin-Holy','Druid-Balance','Rogue-Assassination','Rogue-Subtlety','DemonHunter-Havoc','Paladin-Protection','Monk-Mistweaver','Rogue-Outlaw','Paladin-Retribution','Warrior-Protection','Priest-Shadow','Priest-Discipline','Priest-Holy','Mage-Fire','Druid-Guardian','Shaman-Enhancement','Evoker-Augmentation','Evoker-Devastation','Druid-Feral','Monk-Windwalker',}
local provider = {region='US',realm='Stonemaul',name='US',type='weekly',zone=53,date='2026-11-03',data={Ad='Addalar:BAABNQAECn8VAAIBAAgKixKRVACPAQABAAgKixKRVACPAQAAAA==.',
Ai='Airvis:BAABNQAECn8iAAMCAAgKPRIADAD8AQACAAgKPRIADAD8AQADAAMKxQYGngGJAAAAAA==.',
Ak='Akamie:BAAANQAECgUIBwABNQAECgcIDwAEAAAAAA==.Akar:BAAANQADCgMIAwAAAA==.',
Al='Alacia:BAAANQADCgQIBAABNQAECgoKNgAFAMgTAA==.Albinomonk:BAAANQADCgMIAwAAAA==.Alundre:BAAANQAECgUIBQAAAA==.',
Am='Amaira:BAAANQAECgEIAQAAAA==.Amalakar:BAAANQAECgEIAQAAAA==.Amnezea:BAAANQADCgIIAgAAAA==.',
An='Anankei:BAAANQADCgYIBgAAAA==.Anavere:BAAANQADCgUIBQAAAA==.Annasia:BAAANQAECgEIAQAAAA==.Antte:BAACNQAFFH8YAAIGAAYKRxWtBQDSAQAGAAYKRxWtBQDSAQA1AAQKfyQAAgYACQquIwYLACwDAAYACQquIwYLACwDAAAA.',
Ar='Ariain:BAAANQADCgEIAQAAAA==.Arithorn:BAAANQADCgEIAgAAAA==.Arjun:BAAANQAECgcIDgAAAA==.Armindru:BAABNQAECn8fAAIHAAoK9hVLFgAfAgAHAAoK9hVLFgAfAgAAAA==.Armingothele:BAAANQAECgEIAQABNQAECgoKHwAHAPYVAA==.Arrol:BAAANQADCgIIAgAAAA==.Arturogh:BAAANQAECgcIBwABNQAECgoKMQAIAKwSAA==.',
As='Asmôdeô:BAABNQAECn8cAAMGAAoKLiLWCQCYAgAGAAoKLiLWCQCYAgAJAAEK6SLCKgBeAAAAAA==.Astin:BAAANQAECgEIAQAAAA==.',
At='Atom:BAABNQAECn8rAAIKAAoKKw8YRwAHAgAKAAoKKw8YRwAHAgAAAA==.Atreyu:BAABNQAECn8nAAILAAcKsgzvewBaAQALAAcKsgzvewBaAQAAAA==.',
Au='Aureille:BAAANQAECgQIBAAAAA==.',
Aw='Awoozehl:BAACNQAFFH8eAAMMAAgKmCBvAADLAgAMAAcKbCNvAADLAgANAAIKbhciDgBbAAA1AAQKf0EAAwwACgq9JocAAJEDAAwACgq9JocAAJEDAA0ACAoiG31cAJ4BAAAA.',
Az='Azgrodon:BAABNQAECn81AAMOAAoKyxltTQBBAgAOAAoKyxltTQBBAgABAAgKEgoLjABrAQAAAA==.',
Ba='Banatok:BAAANQADCgIIAwAAAA==.Bangungot:BAAANQAECgEIAQABNQAFFAgIGAAPABEVAA==.Barnabus:BAAANQAECgMIAwAAAA==.Barristan:BAAANQADCgMIBAAAAA==.Barzalie:BAAANQAECgEIAQABNQAFFAUIFAAIAPMbAA==.Bathrezz:BAAANQAECgQIDQAAAA==.',
Be='Beandruid:BAAANQAECgYIBwAAAA==.Beanmage:BAAANQAECgUIBQAAAA==.Beanshaman:BAAANQADCgYIBgAAAA==.Bearlyawake:BAAANQADCgUIBQAAAA==.Beerbelly:BAABNQAECn81AAIQAAoKZCAnAwBlAwAQAAoKZCAnAwBlAwABNQAFFAUIFAAIAPMbAA==.Beleaves:BAACNQAFFH8bAAIQAAYK9ggiBABkAQAQAAYK9ggiBABkAQA1AAQKfzQAAhAACgo6F9oFAPwBABAACgo6F9oFAPwBAAAA.Bellectra:BAABNQAECn8fAAMDAAcKFAgUwAD9AAADAAcKFAgUwAD9AAACAAIKxgZhPQBLAAAAAA==.',
Bi='Bifurious:BAABNQAECn8ZAAIRAAkK6RrQCgAZAgARAAkK6RrQCgAZAgAAAA==.',
Bl='Blathur:BAAANQAECgMIAwAAAA==.Bluereindeer:BAABNQAECn80AAIIAAoKyRB2KgCGAQAIAAoKyRB2KgCGAQAAAA==.',
Bo='Bobafina:BAAANQADCggICAAAAA==.Bobsstones:BAACNQAFFH8WAAQSAAgKQhlgAQBLAQASAAUKxRRgAQBLAQATAAMKKxdjIQDsAAAUAAIK+x3wCgCjAAA1AAQKfzIABBIACgrvJZICAH0CABIACgrTIJICAH0CABMABgrNJLiMAMcBABQABQqhHw8WALwBAAAA.Bobstofu:BAAANQAECgcIEwAAAA==.Bofaðeez:BAAANQADCgQIBAAAAA==.Bombtimer:BAAANQADCgQICAABNQADCgUICQAEAAAAAA==.Bonkulo:BAABNQAECn8xAAQIAAoKrBIvRgDhAQAIAAoKrBIvRgDhAQAMAAMKCwmIdACZAAANAAQKZQV9WACBAAAAAA==.Boofassist:BAACNQAFFH8WAAIVAAcKOR7qAwBOAgAVAAcKOR7qAwBOAgA1AAQKfzcAAhUACgoyJccDALYDABUACgoyJccDALYDAAAA.Boomboomm:BAAANQAECgEIAQABNQAFFAQICwAPAOYNAA==.Boomsonic:BAAANQAECgQIBwABNQAECgkJGQARAOkaAA==.Bophadeez:BAAANQAECgEIAQABNQAFFAQICwAPAOYNAA==.Boraga:BAAANQADCgYJCAAAAA==.',
Br='Bricelar:BAAANQADCgEIAQAAAA==.Brienyx:BAAANQADCgUIBwAAAA==.Brietemis:BAAANQAECgUIDQAAAA==.Briezani:BAABNQAECn8iAAMOAAgKPQzaXgAvAQAOAAgKPQzaXgAvAQABAAIKowKoJAEoAAAAAA==.Briogan:BAAANQAECgUICQAAAA==.Broccoliz:BAECNQAFFH8eAAIHAAgKdRHbAgApAgAHAAgKdRHbAgApAgA1AAQKf0YAAwcACgqtHFwOAJ4CAAcACgqtHFwOAJ4CABYAAQpXFsmqAEEAAAAA.Brokan:BAABNQAECn8UAAMXAAoK1gYXKgDYAAAXAAgKRAUXKgDYAAAYAAYKHAjhhAC+AAAAAA==.Broke:BAAANQAECgIIAgABNQAFFAgIIgAZAH4jAQ==.',
Bu='Bukhaki:BAAANQAECggIEgABNQAECgoKLwAXAOUdAA==.Bullblaster:BAAANQAECgEIAgAAAA==.',
['Bõ']='Bõb:BAAANQAECgEIAQAAAA==.',
Ca='Caden:BAAANQAECgUIBQABNQAECgoKNgAFAMgTAA==.Cafca:BAABNQAECn8wAAISAAoKqRHfBQDdAQASAAoKqRHfBQDdAQAAAA==.Caké:BAAANQADCgYIDAAAAA==.Caldrr:BAAANQAECgEIAQAAAA==.Caylva:BAABNQAECn8YAAMDAAoKnhsRJACTAgADAAoK9RkRJACTAgACAAEKDxXcMABJAAABNQAFFAUIFAAIAPMbAA==.',
Ch='Chrams:BAABNQAECn9JAAIVAAoK7R8OFwAgAwAVAAoK7R8OFwAgAwAAAA==.',
Ci='Cialis:BAAANQADCgYIJgAAAA==.Cinnacrunch:BAAANQAECgEIAgAAAA==.',
Cl='Clearlyumad:BAAANQAECgQIBwAAAA==.Clèrick:BAABNQAECn9AAAMVAAoKzyFSIwDeAgAVAAkKpCJSIwDeAgAaAAcKhw0YMgBQAQAAAA==.',
Co='Coldcrow:BAAANQADCgUICQAAAA==.Combination:BAABNQAECn8vAAIbAAoKiCCHBwAaAwAbAAoKiCCHBwAaAwABNQAFFAQIBwAHAGgZAA==.Contague:BAAANQADCgEIAQAAAA==.Cowen:BAAANQADCggIFAAAAA==.',
Cr='Crash:BAAANQADCgUIBQABNQAFFAUIDgAEAAAAAA==.Cray:BAAANQAECgcICAABNQAECggIEQAEAAAAAA==.Cromuk:BAAANQAECgIIAgAAAA==.',
Cu='Cursedotter:BAAANQAECgcIDwAAAA==.Cursewords:BAAANQAECggICQAAAA==.',
Da='Dabbyshatner:BAAANQAECggIDwAAAA==.Daeneryis:BAAANQAECgQIAwAAAA==.Dankshammy:BAABNQAECn85AAIBAAoKKh0uDgAqAwABAAoKKh0uDgAqAwAAAA==.Darkwave:BAABNQAECn8zAAMUAAoK6hNUPADQAAATAAgKTRHmrgBzAQAUAAMKeRNUPADQAAAAAA==.Darthdiddyus:BAACNQAFFH8PAAIcAAQKaBdyAQBCAQAcAAQKaBdyAQBCAQA1AAQKfysAAhwACQpUIbkCACMDABwACQpUIbkCACMDAAAA.Dathunter:BAAANQAECgIIAgABNQAECgkJKgADADwZAA==.Datshammy:BAAANQAECgEIAQABNQAECgkJKgADADwZAA==.Dawghawg:BAAANQADCgUIBgAAAA==.Dawnnie:BAACNQAFFH8IAAIaAAMKdAu+BgClAAAaAAMKdAu+BgClAAA1AAQKfzcAAhoACgqtHDkOALcCABoACgqtHDkOALcCAAAA.Dawsonrogers:BAABNQAECn8dAAMRAAkKhxSnCgAeAgARAAgKMRenCgAeAgALAAMKvg0cKQGEAAAAAA==.',
De='Deathbanana:BAAANQADCggICAABNQAFFAgIFwADAIgdAA==.Deathbydk:BAACNQAFFH8UAAIIAAUK8xs4DQDtAAAIAAUK8xs4DQDtAAA1AAQKfy4AAggACgprIgMIAPgCAAgACgprIgMIAPgCAAAA.Deathkow:BAAANQAECggIAgAAAA==.Deaththreat:BAAANQADCgEIAQABNQAECggIIAAdAM0UAA==.Delema:BAACNQAFFH8PAAIdAAYKRg3QCAC9AQAdAAYKRg3QCAC9AQA1AAQKfzUAAx0ACgp6H4VfAHoCAB0ACgp6H4VfAHoCABoABQpWDWc0ALQAAAAA.Derbina:BAAANQABCgIIBAAAAA==.Destructer:BAAANQAECgMIDAAAAA==.',
Di='Dicey:BAAANQAECgEIAgABNQAECgkJGQARAOkaAA==.Dirtydinker:BAAANQAECgcICQAAAA==.Dixsard:BAABNQAECn8vAAMXAAoK5R3DGQCvAgAXAAkKLBvDGQCvAgAYAAgKvhgSPgC/AQAAAA==.',
Do='Docmcstuffin:BAAANQADCgMIAwAAAA==.Dontblink:BAAANQAECgEIAQABNQAFFAQIBwAHAGgZAA==.Dorin:BAAANQADCgEIAQAAAA==.Dotore:BAAANQADCgYIBgAAAA==.Dottyflu:BAACNQAFFH8QAAIIAAUKrRR2DwBdAQAIAAUKrRR2DwBdAQA1AAQKfzoAAggACgoQJHQDAEYDAAgACgoQJHQDAEYDAAE1AAUUBggIABoAbQYA.Dottylawful:BAABNQAFFH8IAAIaAAYKbQZXBwADAQAaAAYKbQZXBwADAQAAAA==.',
Dr='Drexbear:BAAANQAECgQJBAABNQAFFAYIEAAeALQNAA==.Drexl:BAACNQAFFH8QAAIeAAYKtA0DAwBJAQAeAAYKtA0DAwBJAQA1AAQKfykAAx4ACgpCFP8XABMBAAsACQpGCMCsAK0BAB4ABgrFG/8XABMBAAAA.',
Dw='Dweams:BAACNQAFFH8dAAIfAAcKZxV6BAAEAgAfAAcKZxV6BAAEAgA1AAQKfzoAAx8ACgqqJXUDADcDAB8ACgqqJXUDADcDACAABgoxGqcMAG0BAAAA.Dweamu:BAAANQAECgEIAgABNQAFFAcIHQAfAGcVAA==.',
Ec='Ectonight:BAAANQADCgIIAgAAAA==.',
Eg='Eggfooyung:BAABNQAECn8WAAIbAAoKSR9MBQBMAwAbAAoKSR9MBQBMAwABNQAFFAcIFgAVADkeAA==.Egwene:BAAANQAECgEIAQAAAA==.',
El='Elbowdeep:BAAANQADCgEIAQAAAA==.Elhonna:BAACNQAFFH8IAAIKAAMKsg+gEgDbAAAKAAMKsg+gEgDbAAA1AAQKf0UAAgoACgoRIKYpAPICAAoACgoRIKYpAPICAAAA.',
Em='Emwen:BAAANQADCgEIAQAAAA==.',
En='Endcredits:BAABNQAECn8jAAIIAAgKoBOwMQBbAQAIAAgKoBOwMQBbAQAAAA==.',
Er='Eridyn:BAAANQAECgcIEwAAAA==.',
Ev='Evoulker:BAACNQAFFH8jAAIPAAgKuBltAwBaAgAPAAgKuBltAwBaAgA1AAQKf0IAAg8ACgp4Hy8LAPACAA8ACgp4Hy8LAPACAAAA.',
Ey='Eyyosmite:BAAANQAECgEIAQAAAA==.',
Ez='Ezekielle:BAAANQAECgEIAQAAAA==.',
Fa='Faire:BAAANQADCgIIAgABNQAECgcIDwAEAAAAAA==.Fairytale:BAACNQAFFH8eAAIhAAcKABDfCwDLAQAhAAcKABDfCwDLAQA1AAQKf0EAAyAACgqUIJQGACACACEACgqdH+klANMCACAABwrkHJQGACACAAAA.Faker:BAAANQADCggIDwAAAA==.',
Fe='Felheim:BAACNQAFFH8VAAIGAAYKohVRBAAdAQAGAAYKohVRBAAdAQA1AAQKf1cAAgYACgr8IUoGAG0DAAYACgr8IUoGAG0DAAAA.Fellithà:BAAANQADCgUIBgAAAA==.',
Fi='Fists:BAAANQADCgYJDAABNQAFFAQICwAPAOYNAA==.',
Fl='Flink:BAAANQADCgIJAgAAAA==.Floogi:BAAANQADCgMIAwAAAA==.Flókì:BAAANQADCgEIAQAAAA==.',
Fo='Foxygal:BAAANQADCggIFAAAAA==.',
Fr='Frostyninja:BAAANQAECgIIAgAAAA==.',
Ga='Garchomp:BAAANQADCgQICAAAAA==.Gawain:BAAANQAECgYICwABNQAECgoKOwAKAL8cAA==.',
Ge='Gellina:BAAANQAECgEIAQAAAA==.Georg:BAACNQAFFH8aAAIdAAgKLRgWAgB9AgAdAAgKLRgWAgB9AgA1AAQKfzkAAh0ACgqDJoUBAIUDAB0ACgqDJoUBAIUDAAAA.Geriatric:BAAANQAECgIIBQABNQAFFAgIHgAMAJggAA==.',
Gl='Glathur:BAAANQADCgIIBAAAAA==.Glizzygagger:BAACNQAFFH8HAAMfAAMKhyBSEADJAAAfAAMKhyBSEADJAAAgAAIKsxZpAgCoAAA1AAQKfyQAAx8ACgpsIr4MAB4DAB8ACQpSIr4MAB4DACAAAgpcIN4KALsAAAE1AAUUBQgGABwAJRQA.Glizzygorger:BAABNQAECn8cAAIGAAgKVR5kIQBBAgAGAAgKVR5kIQBBAgABNQAFFAUIBgAcACUUAA==.',
Go='Goodbye:BAABNQAECn8eAAMDAAkKzhlGeQCLAgADAAkKzhlGeQCLAgAiAAEKAAD+DQAzAAAAAA==.Goregazme:BAAANQAECgcIDAAAAA==.',
Gr='Grantoro:BAABNQAECn80AAIjAAoKTBArHQC4AQAjAAoKTBArHQC4AQAAAA==.Grimmblades:BAAANQAECgIIAgAAAA==.Grootbeer:BAABNQAECn8rAAIKAAoKKxICcwCQAQAKAAoKKxICcwCQAQAAAA==.',
Gu='Gulgrimmar:BAACNQAFFH8dAAMOAAgKrhvrCADhAQAOAAUKuxzrCADhAQABAAQK3RoCFQAKAQA1AAQKfzoAAw4ACgq5JrQAAI0DAA4ACgq5JrQAAI0DAAEABgpwHWt8AJYBAAAA.Guwudanielle:BAAANQAECgcIDwAAAA==.',
['Gä']='Gävinräd:BAAANQADCgUIBgAAAA==.',
Ha='Haranguetan:BAAANQADCgYIBgABNQAECgkJLwAkAGgMAA==.Hardfeelings:BAABNQAECn8gAAIdAAgKzRRVmABbAQAdAAgKzRRVmABbAQAAAA==.Harrharr:BAAANQADCgMIAwAAAA==.',
He='Headache:BAAANQADCgEIAQABNQAECgkJGQARAOkaAA==.Hensley:BAAANQADCgEIAQAAAA==.Hexappeal:BAAANQAECgcIBgAAAA==.',
Ho='Hodann:BAAANQAECgEIAQAAAA==.',
Hu='Hurjek:BAACNQAFFH8HAAIHAAQKaBkNBwBKAQAHAAQKaBkNBwBKAQA1AAQKfzcAAgcACgrqIzYDALADAAcACgrqIzYDALADAAAA.',
Ic='Iconicmax:BAAANQAECgQIDAAAAA==.',
Ij='Ijustankedu:BAAANQADCgEIAwAAAA==.',
Il='Ilyana:BAABNQAECn81AAMDAAoKICKUPAA0AgADAAkKGiGUPAA0AgACAAIKKCIZKgCnAAAAAA==.',
In='Insights:BAABNQAECn8fAAIKAAcKABMWkQBLAQAKAAcKABMWkQBLAQAAAA==.',
Is='Ishtann:BAAANQAECggIAQAAAA==.',
Ja='Jaqen:BAACNQAFFH8GAAIcAAUKJRRcAQBPAQAcAAUKJRRcAQBPAQA1AAQKfygAAxwACQolJNICAB4DABwACQolJNICAB4DABcAAQrBGUFUAEoAAAAA.Jayc:BAACNQAFFH8KAAIDAAYKfRF4EAA3AQADAAYKfRF4EAA3AQA1AAQKfykAAgMACgpxH641AB4DAAMACgpxH641AB4DAAAA.',
Je='Jereico:BAACNQAFFH8dAAMlAAgKdSBKAQCVAgAlAAgKdSBKAQCVAgAmAAEKqxojDwBHAAA1AAQKf0IAAyUACgo9Jj4AAHYDACUACgo9Jj4AAHYDACYACAr5EkwZALQBAAAA.Jeryhn:BAACNQAFFH8eAAIVAAYKMBjMCgCwAQAVAAYKMBjMCgCwAQA1AAQKfzwAAhUACgpnI84OAFQDABUACgpnI84OAFQDAAAA.',
Jo='Joeynodz:BAAANQAECgEIAQAAAA==.Jortshorts:BAABNQAECn8rAAInAAoKdQkXGAB4AQAnAAoKdQkXGAB4AQAAAA==.',
Ju='Juggalo:BAACNQAFFH8UAAMmAAcK4BLZBAB7AQAmAAYKuRXZBAB7AQAlAAEKeQfyCwBIAAA1AAQKf0YAAyYACgpTJAYBADsDACYACgpTJAYBADsDACUAAgoKDWYeAG4AAAAA.June:BAACNQAFFH8aAAIbAAcK8xErAgAXAgAbAAcK8xErAgAXAgA1AAQKf0IAAhsACgpzIZUFABQDABsACgpzIZUFABQDAAAA.',
Ka='Kaldriss:BAAANQAECgIIAwAAAA==.Kalikin:BAAANQAECgMJBAAAAA==.Kawasuoo:BAAANQADCgQIBAABNQAECgcIDwAEAAAAAA==.',
Kc='Kcudüm:BAABNQAECn80AAQUAAoKSxIoDgAXAgAUAAgK0xUoDgAXAgATAAYK6AYM/ADTAAASAAIKNAMILwA4AAAAAA==.',
Ke='Keifis:BAAANQADCgEJAgAAAA==.Keifism:BAAANQABCgMIAwAAAA==.',
Kh='Khaotichic:BAAANQAECgEIAQAAAA==.',
Ki='Kiragar:BAAANQADCgEIAQAAAA==.',
Kl='Klrum:BAABNQAECn8kAAMCAAgKrxdxHgD4AAADAAcKThgCvAAMAgACAAUKqBBxHgD4AAAAAA==.',
Ko='Koddin:BAABNQAECn84AAIdAAoKlRsMPwDYAgAdAAoKlRsMPwDYAgAAAA==.Komui:BAABNQAECn84AAMBAAoKkBZETgArAgABAAoKkBZETgArAgAOAAcKeQ/RXAA0AQAAAA==.Koonlei:BAAANQAECgQIBAAAAA==.Koraxx:BAAANQADCgUIAwAAAA==.Koreth:BAACNQAFFH8eAAMXAAgKJxKJAgBcAgAXAAgKJxKJAgBcAgAYAAIK9w67FQBCAAA1AAQKfzsAAxgACgosJfQGADQDABgACgpqIvQGADQDABcACgptIvkKADIDAAAA.Kornholyo:BAAANQAECgIIBAAAAA==.',
Kr='Krakheeta:BAAANQADCgQIBQAAAA==.Krusade:BAAANQAECgUICQAAAA==.',
Ku='Kumo:BAAANQAECgEIAQAAAA==.Kutuzov:BAAANQAECgUICQAAAA==.',
Kw='Kwenny:BAAANQAECgEIAQAAAA==.',
La='Lailaysia:BAABNQAECn8eAAIhAAoKGSL5BADKAwAhAAoKGSL5BADKAwAAAA==.Lamemoosaur:BAABNQAECn8YAAIjAAkKOxxgCAD2AgAjAAkKOxxgCAD2AgAAAA==.Landfilltwo:BAAANQAECgEIAQAAAA==.Laríca:BAACNQAFFH8NAAIVAAQKaR3oCwBQAQAVAAQKaR3oCwBQAQA1AAQKfzoAAhUACgpOI3sIAIQDABUACgpOI3sIAIQDAAAA.Lavabursting:BAAANQAECgQICAABNQAFFAUIBgAcACUUAA==.Laydout:BAAANQADCgQIBAABNQAECggIEgAEAAAAAA==.Laydoutyota:BAAANQAECggIEgAAAA==.Laymow:BAAANQAECgQJBAABNQAECgkJGAAjADscAA==.',
Le='Levity:BAAANQAECggIBQAAAA==.',
Li='Lilea:BAABNQAECn82AAMFAAoKyBMGKQDoAAAKAAcKyhM3qAC1AQAFAAkKfAwGKQDoAAAAAA==.Lilfaart:BAAANQAECggIBAAAAA==.Lilotterine:BAAANQAECgQIBgAAAA==.Lindisalvia:BAAANQADCggIEQAAAA==.Lionsmane:BAAANQADCgYIBgAAAA==.',
Lo='Loosemorals:BAACNQAFFH8LAAIPAAQK5g3rCgAFAQAPAAQK5g3rCgAFAQA1AAQKfywAAw8ACgrnGLkQAJ8CAA8ACgrnGLkQAJ8CACYAAQoQFHI6ADwAAAAA.Lootgoblin:BAABNQAECn8qAAIDAAkKPBmCkQBdAgADAAkKPBmCkQBdAgAAAA==.Lortherian:BAAANQAECgYIEwAAAA==.',
Lu='Lucila:BAAANQAECgIIAgAAAA==.Lunatique:BAAANQADCgQIBAAAAA==.',
['Lä']='Läwlbringer:BAABNQAECn8aAAIdAAkKyRAplwD1AQAdAAkKyRAplwD1AQAAAA==.',
Ma='Mabritoe:BAACNQAFFH8HAAIXAAQK1SN3CgBZAQAXAAQK1SN3CgBZAQA1AAQKfyMAAxcACQrMJJwPAAQDABcACArMJJwPAAQDABgACAqSCa4iALQBAAE1AAUUBwgYABYAhRUA.Maccabee:BAAANQAECgEIAQAAAA==.Magicstick:BAAANQAECgIIAQAAAA==.Magooh:BAAANQADCgcIBwABNQAECgcIEAAEAAAAAA==.Malison:BAAANQAECgEIAQAAAA==.Mangle:BAAANQADCgUIBQAAAA==.Mania:BAAANQADCgYICwABNQAECgkJGQARAOkaAA==.Mareth:BAAANQADCgIIAgAAAA==.Mathath:BAABNQAECn8nAAMNAAkKjxydPwAfAgANAAkKQBudPwAfAgAIAAMKYx92fQAEAQAAAA==.Mathoras:BAAANQADCgYIBgAAAA==.Maxboom:BAAANQAECgMIAwAAAA==.Mayaho:BAAANQAECgQIEwABNQAECgcIEAAEAAAAAA==.Maylee:BAABNQAECn8iAAIHAAoK4A6fHADRAQAHAAoK4A6fHADRAQAAAA==.',
Me='Meandean:BAAANQAECgYIDQAAAA==.Meatier:BAAANQAECgQICQABNQAECgkJGQARAOkaAA==.Meenako:BAAANQAECgEIAQAAAA==.Mellinia:BAAANQADCgEIAQAAAA==.Meoverdahill:BAAANQADCgEIAQAAAA==.',
Mi='Miltonroe:BAABNQAECn8vAAIkAAkKaAwAGADoAQAkAAkKaAwAGADoAQAAAA==.Miltonroé:BAAANQAECgQICQABNQAECgkJLwAkAGgMAA==.Mixing:BAAANQADCgIJAgAAAA==.',
Mo='Monnz:BAAANQADCgUIBQAAAA==.Monsterskill:BAAANQAECgUIDAAAAA==.Moonerva:BAABNQAECn8iAAIWAAcKKA4lPAAJAQAWAAcKKA4lPAAJAQAAAA==.Morana:BAAANQAECgMIBQAAAA==.',
Mu='Munchinmuff:BAAANQAECgQIBQAAAA==.',
Mv='Mvqchx:BAAANQADCgEIAQAAAA==.',
My='Myo:BAAANQADCgEIAQAAAA==.Myrolous:BAAANQADCgQIBAAAAA==.',
['Mã']='Mãrtrydóm:BAAANQAECgEIAgAAAA==.',
['Mì']='Mìssy:BAAANQAECgUIAwAAAA==.',
Na='Namiin:BAAANQADCgUIBQAAAA==.Namikaze:BAAANQAECgMICAAAAA==.Natara:BAAANQADCgYICgAAAA==.Naughtye:BAAANQAECgQICAAAAA==.Nave:BAAANQAECgcICAAAAA==.',
Ne='Nelfsfault:BAAANQADCggJFwAAAA==.Nerotappo:BAAANQADCgEIAQAAAA==.',
Ni='Ninja:BAAANQADCgYJBgAAAA==.',
No='Nobacon:BAAANQADCgIIAgAAAA==.Noshaku:BAAANQAECgYICQAAAA==.Notanorc:BAABNQAECn8xAAMRAAoKBhC4FQBAAQALAAoK7QyDbACCAQARAAUKMRO4FQBAAQAAAA==.Novi:BAAANQADCgEIAgAAAA==.Novix:BAAANQADCgEIAQAAAA==.',
Oh='Ohrolam:BAABNQAECn81AAMDAAoKIArb4gDDAQADAAoKAwjb4gDDAQACAAQKKgysKgCkAAAAAA==.',
Ok='Okasan:BAAANQAECgQICAABNQAECgcIGwAbAAMTAA==.',
Or='Oromis:BAAANQAECgcICwABNQAFFAUIBgAcACUUAA==.',
Ot='Ottersdemons:BAAANQAECgMIAwAAAA==.',
Pa='Palthur:BAAANQAECgUICwAAAA==.Paradoxis:BAAANQAECgEIAwAAAA==.Passionate:BAAANQAECgEIAQAAAA==.',
Ph='Phatmidas:BAABNQAECn8xAAIdAAoKARfpVwDvAQAdAAoKARfpVwDvAQAAAA==.Phleat:BAAANQADCgYIBgABNQAECgoKOwAdABcTAA==.Phrozenpally:BAAANQAECgQIDAABNQAECgcIEAAEAAAAAA==.',
Pi='Pika:BAAANQAECgMIBAABNQAFFAUIFAAIAPMbAA==.Pinbull:BAAANQADCgEIAQAAAA==.Pinkponythug:BAAANQAECgcICgABNQAFFAQICwAPAOYNAA==.',
Pl='Plagueground:BAACNQAFFH8bAAQMAAcKeCD8AQA9AgAMAAYKXCP8AQA9AgAIAAIK5xRpJQBmAAANAAEKsA9hJAA7AAA1AAQKf0cABA0ACgqGJtoAAH4DAAwACgoxJnkCAMEDAA0ACgrKJdoAAH4DAAgAAgrlJZGcAKEAAAAA.Plutonyus:BAAANQAECgQIBwAAAA==.',
Po='Poc:BAAANQAECgUIDQAAAA==.Porterhaus:BAAANQADCggICAABNQAFFAYIDgATAGEQAA==.Pounces:BAABNQAECn9EAAInAAoKCCZiAQDBAwAnAAoKCCZiAQDBAwAAAA==.',
Pr='Prayforpain:BAAANQADCgEIAQAAAA==.Prózak:BAAANQADCgYIBwABNQAECgoKNQAaAOYWAA==.Prôzak:BAABNQAECn81AAIaAAoK5hbDDwDzAQAaAAoK5hbDDwDzAQAAAA==.',
Ps='Psychomidget:BAABNQAECn8aAAMgAAoKPxHNAgA7AgAgAAoKPxHNAgA7AgAfAAEKPgEpkwAWAAAAAA==.',
Pu='Puetrid:BAACNQAFFH8OAAMTAAYKYRBiCwAqAQATAAYKORBiCwAqAQAUAAIKRA/+DwCUAAA1AAQKfzkAAxQACgrAG/IFALICABQACQrXFfIFALICABMACQqJGZogAGsCAAAA.Purble:BAAANQADCgIIAgAAAA==.Puufrumslli:BAAANQAECggIEgAAAA==.',
Ra='Rageinglight:BAAANQAECgMIBQAAAA==.Rakku:BAAANQABCgcJBgAAAA==.Rautha:BAABNQAECn8cAAIdAAgKBBJDqQDNAQAdAAgKBBJDqQDNAQAAAA==.Rayl:BAAANQAECgEIAQAAAA==.',
Re='Rekt:BAABNQAECn8aAAImAAoKsBTzBgD/AQAmAAoKsBTzBgD/AQAAAA==.',
Rh='Rhaegon:BAABNQAECn8tAAIJAAkKCBxGBQDeAgAJAAkKCBxGBQDeAgAAAA==.',
Ri='Rimath:BAAANQADCggIEAAAAA==.Riverpaw:BAAANQAECgEIAQAAAA==.',
Rn='Rng:BAAANQAECggIEQAAAA==.',
Ro='Rodstewart:BAABNQAECn8VAAMKAAkKZBQolADgAQAKAAgKhRUolADgAQAFAAMKsQsadQBmAAAAAA==.Ronz:BAAANQADCgEIAQAAAA==.Roofeo:BAAANQAECgEIAQABNQAECgoKMQAIAKwSAA==.Rotdaddy:BAABNQAECn8wAAINAAoK8AgEKgBiAQANAAoK8AgEKgBiAQAAAA==.',
Sa='Sabatikus:BAAANQAECgEIAQAAAA==.Salino:BAABNQAECn8cAAIWAAcK5wkWWwBmAQAWAAcK5wkWWwBmAQAAAA==.Salinoster:BAAANQAECgMIBgABNQAECgcIHAAWAOcJAA==.Sam:BAAANQAECgcIEQAAAA==.Sandorindis:BAAANQADCgYIBwAAAA==.Sarate:BAAANQADCggIEgAAAA==.Satral:BAAANQAECgYIBwAAAA==.Savannah:BAAANQAECgYIBwABNQAECgcIDwAEAAAAAA==.Savarra:BAAANQAECgEIAQAAAA==.Savvtwo:BAAANQADCgEIAQABNQAFFAgIIgAZAH4jAQ==.',
Se='Sezra:BAAANQADCggICAAAAA==.',
Sh='Shaetahn:BAAANQAECgEIAQAAAA==.Shamwowthorn:BAAANQADCgEIAQAAAA==.Shaokauhn:BAAANQADCgEIAQAAAA==.Shinanigans:BAABNQAECn89AAIdAAkKix+ZNwDxAgAdAAkKix+ZNwDxAgAAAA==.Shockbull:BAAANQADCgcJBwAAAA==.',
Si='Silverbäck:BAAANQAECgYIDQABNQAECgcIDgAEAAAAAA==.Silverslam:BAAANQAECgIIAgABNQAECgcIDgAEAAAAAA==.',
Sk='Skippitypaps:BAAANQADCgIIAgAAAA==.Skurge:BAABNQAECn8aAAIMAAcKrA67QgBPAQAMAAcKrA67QgBPAQAAAA==.',
Sn='Snacks:BAAANQADCgEIAQABNQAECgcIEQAEAAAAAA==.Snuffles:BAAANQADCgYIBgAAAA==.',
So='Solstis:BAAANQAECgUICQAAAA==.Soranwena:BAABNQAECn8nAAIjAAoKfBfhEgDNAQAjAAoKfBfhEgDNAQAAAA==.Sorros:BAAANQAECgQIBQAAAA==.',
Sp='Spacegoat:BAAANQAECgMIAwAAAA==.Spfzero:BAAANQAECgEIAQAAAA==.Spookybuns:BAAANQAECggIEAAAAA==.',
St='Sticksy:BAAANQADCgYIBgAAAA==.Stonebeard:BAAANQAECgQIBgAAAA==.Stârlèss:BAAANQADCgYIBwAAAA==.',
Su='Subtox:BAABNQAECn8VAAIYAAoKsRKMLwAEAgAYAAoKsRKMLwAEAgAAAA==.Suhh:BAAANQADCgEIAgAAAA==.',
Sw='Swedishfish:BAAANQAECgEIAQABNQAECgkJHQAfAP4dAA==.',
['Sá']='Sálúd:BAAANQAECgcIEQAAAA==.',
['Sê']='Sêp:BAAANQAECgIIAgAAAA==.',
Ta='Tarhealeon:BAAANQAECgYIDgAAAA==.Tarvuspls:BAABNQAECn8dAAMKAAgKZBNSiAD6AQAKAAgKZBNSiAD6AQAFAAUK7QU+VgDNAAAAAA==.',
Te='Teemawthy:BAAANQADCgYICgAAAA==.Temozo:BAAANQADCgIIAgAAAA==.',
Th='Thabigone:BAAANQAECgIIAgAAAA==.Theceo:BAAANQADCgYIDgAAAA==.Thorb:BAAANQAECgcIEwABNQAFFAUIFAAIAPMbAA==.',
Ti='Ticklemebutt:BAAANQAECgcIEwAAAA==.Tiewaz:BAABNQAECn8UAAIdAAgKpwrRtQAlAQAdAAgKpwrRtQAlAQAAAA==.',
To='Tolun:BAABNQAECn8vAAICAAoKfBsVBACBAgACAAoKfBsVBACBAgAAAA==.Tonarui:BAAANQAECgQICwAAAA==.Tosan:BAABNQAECn8bAAIbAAcKAxO0EwCIAQAbAAcKAxO0EwCIAQAAAA==.Toughcookie:BAABNQAECn8gAAMdAAoKwAoymABbAQAdAAoKwAoymABbAQAVAAIKPgR2FwFGAAAAAA==.',
Tr='Treeplague:BAABNQAECn8kAAMgAAgKsw6pBQBqAQAgAAgKsw6pBQBqAQAfAAIK4QQ3bQBQAAAAAA==.',
Tu='Turn:BAACNQAFFH8gAAQUAAgKCBGDAgD1AAASAAQK+g00AgAAAQAUAAMK7RODAgD1AAATAAMKhhBfIgDnAAA1AAQKfzIABBQACgpBI9wPAAACABMABwqFIM11AAECABQABwpPF9wPAAACABIABQqFJS4KANcBAAAA.Turtleduck:BAAANQAECgEIAQABNQAECgoKHwAHAPYVAA==.',
Ty='Tyla:BAAANQAECggICAAAAA==.Typhis:BAAANQAECgQIBAAAAA==.',
['Tì']='Tìewaz:BAAANQAECgQIBgABNQAECggIFAAdAKcKAA==.',
Um='Umbryx:BAAANQAECgEIAQAAAA==.',
Un='Unagi:BAABNQAECn82AAIkAAoKDxGKDwDhAQAkAAoKDxGKDwDhAQAAAA==.',
Va='Valdir:BAAANQAECggIBgAAAA==.Vasomir:BAAANQADCgEIAQAAAA==.',
Ve='Venomstrikes:BAAANQADCgcIBwAAAA==.Venøm:BAAANQAECgEIAQAAAA==.Vexxen:BAAANQAECgIIBAAAAA==.',
Vi='Viscerion:BAAANQAECgYIEAAAAA==.',
Vo='Voids:BAAANQAECgUIBQAAAA==.',
Wh='Whoarlock:BAAANQAECgEIAQAAAA==.',
Wi='Wizzyy:BAAANQADCgUIBQAAAA==.',
Wo='Wo:BAAANQADCgEIAQABNQAECggIEQAEAAAAAA==.',
Xa='Xandor:BAAANQAECgEIAQAAAA==.',
Xe='Xelinia:BAACNQAFFH8RAAMfAAUKoQd6DAAcAQAfAAQKoQd6DAAcAQAhAAEK9AIIOAA/AAA1AAQKfzIAAx8ACgo4HTQQACECAB8ACgo4HTQQACECACEAAQrfAV8KAR8AAAAA.Xen:BAAANQAFFAEIAQAAAA==.',
Xi='Xiboute:BAAANQAECgQIBAAAAA==.',
Xu='Xuefeng:BAACNQAFFH8QAAIoAAUKChBBCgAiAQAoAAUKChBBCgAiAQA1AAQKf0AAAigACgptH+0LABcDACgACgptH+0LABcDAAAA.',
Ya='Yahwae:BAAANQAECgcIEQABNQAECgoKMwAUAOoTAA==.',
Yc='Ycephyre:BAAANQAECgcICQAAAA==.',
Ye='Yenchmeister:BAACNQAFFH8aAAILAAcKDBfvBgBSAgALAAcKDBfvBgBSAgA1AAQKfzEAAgsACgpoJEcdAEIDAAsACgpoJEcdAEIDAAAA.',
Yo='Yomahma:BAAANQAECgUIBgAAAA==.',
Yu='Yuta:BAAANQADCgQIBAAAAA==.',
Za='Zanin:BAAANQAECgEIAQABNQAECgcIHAAWAOcJAA==.',
Zd='Zdervish:BAABNQAECn8cAAIXAAgKmBkjKQBKAgAXAAgKmBkjKQBKAgAAAA==.',
Ze='Zeffira:BAAANQAECgUIBwAAAA==.Zellda:BAAANQAECgUICgABNQAECgoKOwAKAL8cAA==.',
Zi='Zilvanic:BAABNQAECn8hAAQaAAkKjwvBNQA5AQAaAAgKHQ3BNQA5AQAVAAUKxAZ6mwC/AAAdAAEKAADDpgEAAAAAAA==.Zilvanion:BAACNQAFFH8FAAMTAAQKXQVkJAB6AAATAAMKVQVkJAB6AAASAAEKbAVKEAA/AAA1AAQKf0AAAhMACgrGF9g7APIBABMACgrGF9g7APIBAAAA.',
Zl='Zlathur:BAAANQADCgcIEQAAAA==.',
Zo='Zourbeast:BAAANQADCgQIBAAAAA==.Zourknight:BAAANQADCgcICAAAAA==.Zourlight:BAAANQADCgcIEgAAAA==.Zourlock:BAAANQADCggIEAAAAA==.Zourstorm:BAAANQADCgUIBQAAAA==.Zourvoid:BAAANQADCggIGgAAAA==.',
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
