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

local lookup = {'Hunter-BeastMastery','DeathKnight-Blood','Unknown-Unknown','Mage-Arcane','Monk-Windwalker','Monk-Brewmaster','Shaman-Restoration','Paladin-Retribution','Warrior-Protection','Warrior-Arms','Warrior-Fury','Shaman-Elemental','Hunter-Marksmanship','Rogue-Subtlety','Rogue-Assassination','Priest-Holy','Warlock-Demonology','Hunter-Survival','Priest-Shadow','Paladin-Holy','DemonHunter-Havoc','DemonHunter-Devourer','DeathKnight-Unholy','Druid-Balance','Druid-Restoration','Druid-Guardian','Warlock-Affliction','Warlock-Destruction','Paladin-Protection','Evoker-Preservation','Shaman-Enhancement','DemonHunter-Vengeance','Monk-Mistweaver','Mage-Frost','Druid-Feral',}
local provider = {region='US',realm='Nesingwary',name='US',type='weekly',zone=53,date='2026-10-27',data={Al='Aldrik:BAAANQABCgQIBAAAAA==.Allunnadora:BAAANQADCgcIBwAAAA==.',
Am='Amarantha:BAAANQADCgEIAQAAAA==.Amellwind:BAABNQAECn8qAAIBAAoKjBj8OwDxAQABAAoKjBj8OwDxAQAAAA==.',
An='Antiosto:BAEBNQAECn82AAICAAoKRhVuOQAhAgACAAoKRhVuOQAhAgAAAA==.',
Ar='Ariosto:BAEANQAECgEIBgABNQAECgoKNgACAEYVAA==.Arkadias:BAAANQABCgIIAgAAAA==.Arthea:BAAANQAECgcIDAAAAA==.',
As='Asmmina:BAABNQAECn8XAAIBAAkKbghuuwCNAQABAAkKbghuuwCNAQAAAA==.',
Ay='Ayrwen:BAAANQAECgcIDgAAAA==.',
Az='Azarit:BAAANQADCgQIBAAAAA==.',
Ba='Babyluvv:BAAANQADCgIIAgAAAA==.Badgerbadger:BAAANQADCggIDwAAAA==.Baldr:BAAANQAECgQIBQABNQAFFAIIAgADAAAAAA==.',
Be='Beatrixx:BAAANQAECgcIBgAAAA==.',
Bi='Bitterman:BAABNQAECn8lAAIEAAoKvxlahgBxAgAEAAoKvxlahgBxAgAAAA==.',
Bl='Bloodhardt:BAABNQAECn8kAAICAAkKohjCIgB+AQACAAkKohjCIgB+AQAAAA==.Bluekoolaid:BAABNQAECn8rAAMFAAgKOxyYFwCOAgAFAAgKOxyYFwCOAgAGAAUKqBNyDQDpAAAAAA==.',
Br='Bringbackbfa:BAAANQAECgQIBAAAAA==.Brynfyre:BAAANQABCgUIBQAAAA==.',
Bu='Buglord:BAABNQAECn8kAAIBAAgKZBV9bwBYAQABAAgKZBV9bwBYAQAAAA==.',
Bw='Bwonsamedí:BAAANQAECgIIAgAAAA==.',
Ce='Cellas:BAAANQADCgcIBwAAAA==.Cemeron:BAAANQABCgYIEAAAAA==.',
Ch='Cheba:BAABNQAECn8qAAIHAAoKChAAcQC4AQAHAAoKChAAcQC4AQAAAA==.Chesleigh:BAAANQADCgYIJQAAAA==.',
Ci='Cinderlight:BAABNQAECn8hAAIIAAgKNwdc7QBBAQAIAAgKNwdc7QBBAQAAAA==.',
Cl='Clydas:BAAANQADCgQIBAAAAA==.',
Co='Cortock:BAABNQAECn88AAQJAAoK+BZvFwC1AQAKAAoK6w5TnQDTAQAJAAcKjxhvFwC1AQALAAQKZRBtDwD4AAAAAA==.Corvell:BAABNQAECn8eAAIIAAkKaBXuhgAZAgAIAAkKaBXuhgAZAgAAAA==.',
Cy='Cyssor:BAAANQADCgYIJAAAAA==.',
Da='Dagget:BAAANQAECgEIAQAAAA==.Dancingfox:BAAANQADCgYIJQAAAA==.Dathdeath:BAAANQAECgIIBwAAAA==.Davlindhag:BAAANQAECgIIAgAAAA==.',
De='Deadquick:BAAANQADCgUIBQAAAA==.Demo:BAAANQADCgMIBQABNQAECgUICQADAAAAAA==.Demonhunted:BAAANQADCgIIAwAAAA==.Deros:BAAANQADCgMIAwAAAA==.Dezzii:BAAANQAECgUIDgAAAA==.',
Di='Dimitri:BAAANQABCgIIAgAAAA==.Dirtnappzz:BAABNQAECn8UAAIMAAUKyRWKrwA0AQAMAAUKyRWKrwA0AQAAAA==.Divanna:BAAANQAECgYIBgAAAA==.',
Do='Doroga:BAAANQABCgYIBgAAAA==.Dotdotded:BAAANQAECgMIAwAAAA==.',
Dr='Dragonkiller:BAABNQAECn8pAAINAAgKwxU1JgAaAgANAAgKwxU1JgAaAgAAAA==.Draik:BAAANQADCgMIAwABNQAECgUICQADAAAAAA==.Driftless:BAABNQAECn8jAAMOAAgKnhXYFwAfAgAOAAgKnhXYFwAfAgAPAAEKyQNYqgAnAAAAAA==.',
Du='Dunce:BAAANQAECgUICgAAAA==.',
Eb='Ebsteen:BAAANQADCgcIBwABNQAECggILQAQANwWAA==.',
Ec='Eccentricity:BAAANQADCggICAAAAA==.',
El='Eladamir:BAAANQAECgIIAgABNQAECggIIwAOAJ4VAA==.Elementalhro:BAABNQAECn8gAAMHAAkKohfGHQBVAgAHAAkKohfGHQBVAgAMAAIKwQLYSgEpAAAAAA==.Ellzik:BAAANQAECgUICgAAAA==.',
Es='Escanorr:BAAANQAECggICAABNQAECgoKJQAEAL8ZAA==.Esthero:BAAANQADCgYIBgABNQAFFAIIAgADAAAAAA==.',
Ev='Eviaris:BAAANQABCgEIAQAAAA==.',
Fa='Falorien:BAAANQAECgMIBQAAAA==.',
Fe='Felray:BAAANQAECgcIEQAAAA==.',
Fl='Flamingpax:BAAANQAECgUICQAAAA==.Floinhunt:BAAANQAECgEIAQAAAA==.Fluffinbaked:BAAANQAECgUICAAAAA==.Fluffybúnny:BAAANQADCgYIIQAAAA==.',
Fr='Frankenberry:BAEANQAECgQIBQABNQAECgoKNgACAEYVAA==.Freakadeek:BAAANQADCgYICwAAAA==.',
Fu='Furrious:BAAANQAECgQIBAAAAA==.',
Ga='Galekk:BAAANQAECgYIAQAAAA==.',
Gh='Ghostwolfer:BAAANQAECgEIAQAAAA==.Ghpwarlock:BAABNQAECn8wAAIRAAoKcRQfYwAwAgARAAoKcRQfYwAwAgAAAA==.',
Gl='Glasc:BAAANQAECgUICgAAAA==.Glideyboi:BAAANQADCgcJBwAAAA==.',
Gn='Gnomagician:BAAANQAECgQIBgAAAA==.Gnowances:BAAANQADCgcIBwAAAA==.',
Go='Gorakk:BAABNQAECn8jAAIKAAgKXhbtfgAeAgAKAAgKXhbtfgAeAgAAAA==.',
Gr='Greenknight:BAAANQADCgUIBQAAAA==.Grimli:BAAANQADCgUIBQAAAA==.Grimstone:BAAANQAECgcICgAAAA==.Groggu:BAAANQADCgcIFgAAAA==.',
Gs='Gsnviper:BAAANQAECgIIAgAAAA==.',
Ha='Hanakala:BAAANQAECgIIAQAAAA==.',
Hi='Hintou:BAAANQAECgMIAwAAAA==.',
Ho='Hodart:BAABNQAECn8YAAMPAAkKdA4sFwBCAQAPAAgKJQ8sFwBCAQAOAAEKTwq+mwA0AAAAAA==.Hotsauce:BAAANQADCgEIAQAAAA==.',
Hu='Hurt:BAAANQAECgEIAQABNQAFFAIIBwABAKcLAA==.',
If='Ifucmeurdead:BAAANQADCgMIAwAAAA==.',
Ij='Ijudgethat:BAAANQAECgIIAwABNQAECgcIGgASAHETAA==.',
It='Itzli:BAABNQAECn8fAAMNAAoKAhzRFgCkAgANAAoKAhzRFgCkAgABAAEKAABeJgEAAAABNQAFFAIIAgADAAAAAA==.',
Iv='Ivee:BAAANQADCgEIAQABNQAFFAIIAgADAAAAAA==.',
Ja='Jaser:BAAANQAECgYICQAAAA==.',
Je='Jellybeane:BAAANQADCgYIHwAAAA==.',
Jg='Jgwentworth:BAACNQAFFH8QAAIIAAYKNA4dCgD2AAAIAAYKNA4dCgD2AAA1AAQKfywAAggACgrfHrhfAHoCAAgACgrfHrhfAHoCAAAA.',
Jo='Jojen:BAABNQAECn8tAAMQAAgK3BaETQA8AgAQAAgK3BaETQA8AgATAAYKiwhPKQC/AAAAAA==.Jorj:BAABNQAECn83AAIBAAoKjB3LHAB7AgABAAoKjB3LHAB7AgAAAA==.',
Ka='Katrex:BAAANQADCgYIHwAAAA==.Kavax:BAABNQAECn8vAAIUAAgKzxmSPQBuAgAUAAgKzxmSPQBuAgAAAA==.Kayos:BAABNQAECn8/AAMVAAoKdxZREwAdAgAVAAoKdxZREwAdAgAWAAgKxAmgNACeAQAAAA==.',
Ke='Kefan:BAAANQAECgMIAwABNQAECgoKPwAVAHcWAA==.Kelz:BAABNQAECn8XAAIXAAcKswr/bABfAQAXAAcKswr/bABfAQAAAA==.Keokea:BAAANQADCgQIBQABNQAECgMIBwADAAAAAA==.',
Kh='Khorne:BAABNQAECn8fAAICAAgKGhByUQCvAQACAAgKGhByUQCvAQAAAA==.',
Ki='Killdoom:BAAANQABCgcIBwAAAA==.Kimarah:BAAANQAFFAIIAgAAAA==.',
Kr='Kraven:BAAANQAECgQIBAAAAA==.Krica:BAAANQADCgMIBAAAAA==.Krillian:BAAANQAECgMIAwAAAA==.Kronnah:BAAANQABCgYIBgAAAA==.',
Ku='Kula:BAAANQAECgMIBwAAAA==.Kuwata:BAAANQADCgMIAwAAAA==.',
La='Largetha:BAAANQAECgQIBAABNQAFFAIIAgADAAAAAA==.Latro:BAACNQAFFH8HAAIBAAIKpwtfGACRAAABAAIKpwtfGACRAAA1AAQKfzYAAwEACgooIM0YADYDAAEACgooIM0YADYDAA0AAQoYDJaMADIAAAAA.',
Le='Leenex:BAAANQADCggIDQAAAA==.Lemiranas:BAABNQAECn8aAAIRAAgKJBCaiwDKAQARAAgKJBCaiwDKAQAAAA==.Lepo:BAABNQAECn8qAAIOAAgKbA6cHADvAQAOAAgKbA6cHADvAQAAAA==.',
Lo='Lochnessy:BAAANQADCgEIAQABNQAECgkJKAABAA4aAA==.',
Lu='Luciá:BAAANQADCgcIBwABNQAFFAIIAgADAAAAAA==.Lunden:BAABNQAECn8kAAQYAAgKSRU6KQA+AQAYAAgKSRU6KQA+AQAZAAMKchOwVQCxAAAaAAEKuwlgYAA0AAAAAA==.Luvalee:BAABNQAECn8VAAQbAAUKyQI0HQCUAAAbAAQKyQI0HQCUAAARAAUKuwHg1ABPAAAcAAEKAACIiAAbAAAAAA==.',
Ma='Magdalena:BAAANQAECgMIBQABNQAFFAIIAgADAAAAAA==.Magdaz:BAAANQABCgMIAgAAAA==.Magnificence:BAABNQAECn8iAAIIAAgKmgvBzgB+AQAIAAgKmgvBzgB+AQAAAA==.Maladroit:BAAANQAECgEIAQABNQAFFAIIAgADAAAAAA==.Maldus:BAABNQAECn8jAAITAAoKMxsjEgDdAgATAAoKMxsjEgDdAgABNQAFFAIIAgADAAAAAA==.Mallacath:BAABNQAECn8cAAIJAAkKHhTGEwDpAQAJAAkKHhTGEwDpAQAAAA==.Marabet:BAAANQADCgEIAQAAAA==.Marloak:BAAANQAECgQIEgAAAA==.Matalan:BAAANQADCgIIAgAAAA==.Maxxpower:BAAANQADCgUIBQAAAA==.',
Mc='Mcbain:BAAANQADCgcIBwAAAA==.Mccormick:BAAANQAECgIIAgABNQAFFAIIAgADAAAAAA==.',
Me='Merrymanalow:BAAANQAECgMIAgAAAA==.Metaocalypse:BAAANQAECgQIBgAAAA==.',
Mi='Milough:BAABNQAECn8VAAMKAAkKFyCmUQCVAgAKAAkKFyCmUQCVAgALAAIKtRvnEwCvAAAAAA==.',
Mo='Moreraz:BAAANQADCgYICAAAAA==.Mortdavol:BAAANQAECgEIAQAAAA==.',
Mu='Muteknight:BAAANQADCgYIDAABNQAECggIHgAMAM8RAA==.',
My='Myhealsuck:BAAANQAECgQIBAAAAA==.Mysweetheals:BAAANQAECgIIAgAAAA==.',
Na='Nathali:BAAANQAECgUIBQAAAA==.',
Ne='Nergigante:BAAANQAECgEIAQAAAA==.Nessy:BAABNQAECn8oAAIBAAkKDhovTQCHAgABAAkKDhovTQCHAgAAAA==.',
Ni='Nicksamurai:BAABNQAECn8qAAIdAAgK6xW6HAAFAgAdAAgK6xW6HAAFAgAAAA==.Nikage:BAAANQADCggICAAAAA==.',
Nu='Nuggles:BAAANQADCgEIAQAAAA==.',
Ny='Nynaève:BAAANQADCgcIGQAAAA==.',
Om='Ombos:BAABNQAECn8vAAIeAAoKViIQBQBcAwAeAAoKViIQBQBcAwAAAA==.',
Or='Ormeichi:BAAANQAECgUIDQAAAA==.Orticia:BAAANQAECgUIDwAAAA==.',
Oz='Ozone:BAABNQAECn83AAQfAAoKDQdqDgCnAQAfAAoKjwZqDgCnAQAMAAcKWwVrqABDAQAHAAQKugOwvQBAAAAAAA==.',
Pa='Palii:BAAANQADCgUIBQAAAA==.Pallypocket:BAABNQAECn8qAAIUAAoKfRoNQwBZAgAUAAoKfRoNQwBZAgAAAA==.Pandahalf:BAAANQADCgYIIQAAAA==.Partyrocker:BAAANQADCgQIBAABNQAECgcIGgASAHETAA==.',
Ph='Pheldorai:BAABNQAECn8YAAIRAAkKwQ3QVgBeAQARAAkKwQ3QVgBeAQABNQABCgEIAQADAAAAAA==.Pheldrid:BAAANQADCgUIBQABNQABCgEIAQADAAAAAA==.Phelnomie:BAABNQAECn8ZAAIBAAoKsgwRlQDeAQABAAoKsgwRlQDeAQABNQABCgEIAQADAAAAAA==.Phàntoms:BAAANQADCgYIFQAAAA==.',
Pr='Pream:BAAANQAECgQIBQABNQAECggIHgAMAM8RAA==.Precipitus:BAAANQAECgYICwAAAA==.Property:BAAANQAECgQICAABNQAFFAcIGgAgAHQeAA==.',
Pu='Puma:BAAANQAECgIIAwAAAA==.',
Ra='Radiance:BAAANQADCgcIBwAAAA==.Raerion:BAAANQADCggIDgAAAA==.Raevynn:BAABNQAECn80AAIQAAoKtQ5lYQD9AQAQAAoKtQ5lYQD9AQAAAA==.Raiinzen:BAABNQAECn8kAAIhAAgKTRwnFAA4AgAhAAgKTRwnFAA4AgAAAA==.Rajun:BAAANQABCgYIBwAAAA==.Rawrgrr:BAAANQAECgQICQAAAA==.Razelka:BAABNQAECn8bAAILAAgKug6qEgB3AQALAAgKug6qEgB3AQAAAA==.',
Re='Redearslider:BAAANQAECgUICQAAAA==.Rellix:BAAANQAECgQICQAAAA==.Remmulas:BAABNQAECn8nAAIiAAgKVh4LBQDMAgAiAAgKVh4LBQDMAgAAAA==.Repunzel:BAABNQAECn8cAAIIAAUKtgY34QCqAAAIAAUKtgY34QCqAAAAAA==.',
Rh='Rhoku:BAAANQADCgYIBgAAAA==.',
Ri='Rightmeow:BAAANQAECgQICAABNQAECgcIEQADAAAAAA==.',
Ro='Rozco:BAAANQAECgQIDgAAAA==.',
Ru='Rubmywolf:BAAANQAECgIIBQAAAA==.Rumichan:BAAANQADCgcIBwAAAA==.',
['Rä']='Rägnär:BAAANQABCgUIBgAAAA==.',
Sc='Scrapshot:BAAANQADCgMIBAAAAA==.',
Se='Serina:BAABNQAECn8kAAIBAAgKwxO/hQAAAgABAAgKwxO/hQAAAgAAAA==.',
Sh='Shadowmisty:BAAANQAECgQICgAAAA==.Shame:BAABNQAECn8qAAMHAAkK8BnbIAA/AgAHAAkK8BnbIAA/AgAMAAEK2wZuygAvAAAAAA==.Shammu:BAAANQAECgIIAwABNQAECgUICQADAAAAAA==.Shamocalypse:BAAANQADCggIDQAAAA==.Shevah:BAABNQAECn8gAAIjAAgKsRlLCwB6AgAjAAgKsRlLCwB6AgAAAA==.',
Si='Sid:BAECNQAFFH8JAAMEAAYKqhj3JQBYAQAEAAUKrRn3JQBYAQAiAAEKnxTnCABbAAA1AAQKf0kAAwQACgqPJaQEANQDAAQACgqPJaQEANQDACIABQqeIlYJAIEBAAAA.',
So='Sophié:BAABNQAECn8UAAIcAAgKVROmGgCXAQAcAAgKVROmGgCXAQABNQAFFAIIAgADAAAAAA==.Souxie:BAAANQADCgYIIAAAAA==.',
Sp='Sprout:BAAANQAECgIIBwAAAA==.',
St='Stabittha:BAAANQAECgIIAQAAAA==.Starislost:BAAANQADCgcIBwAAAA==.Stormcreaux:BAAANQAECgMIBwAAAA==.Stàrwish:BAAANQADCgQIBAAAAA==.',
Su='Suelock:BAAANQAECgIIBwAAAA==.Suldes:BAAANQADCggIKwAAAA==.',
Sy='Syn:BAAANQADCggICAAAAA==.Synapse:BAAANQAECgQIEgAAAA==.',
Ta='Taali:BAAANQAECgIIBgAAAA==.Tala:BAAANQADCgEIAQAAAA==.Tarrant:BAAANQAECgMIAwAAAA==.Tarvil:BAABNQAECn8cAAQbAAgKEQw+CgD1AAARAAcKVwdbtgBiAQAbAAQKjQ4+CgD1AAAcAAIKqARnZQBZAAAAAA==.',
Te='Teakat:BAAANQADCggICAAAAA==.Tesshi:BAAANQADCgYIBgAAAA==.',
Th='Thampe:BAAANQADCgEIAgAAAA==.Thjazi:BAABNQAECn8mAAIMAAgKZRS1XQAJAgAMAAgKZRS1XQAJAgAAAA==.Thomasten:BAABNQAECn8kAAIWAAoKSya+AQDMAwAWAAoKSya+AQDMAwAAAA==.Thomasthree:BAAANQAECgYIBgABNQAECgoKJAAWAEsmAA==.',
Tj='Tjorvi:BAEANQAECgEIAQABNQAECgUIBQADAAAAAA==.',
Tr='Trampozo:BAAANQADCgQIBgAAAA==.Trenady:BAAANQAECgUIBwAAAA==.Trent:BAAANQAECgUICAABNQAECgoKJQAEAL8ZAA==.Tricksï:BAAANQAECgEIAQAAAA==.',
Um='Umami:BAABNQAECn8cAAIHAAgKaxE8RgB8AQAHAAgKaxE8RgB8AQAAAA==.',
Ur='Urielseptim:BAAANQADCgEIAQAAAA==.',
Va='Vanderlay:BAABNQAECn8WAAIiAAUKZRkEEQCWAQAiAAUKZRkEEQCWAQAAAA==.',
Ve='Vellisara:BAAANQAECggIDAAAAA==.',
Vi='Viddar:BAAANQAECgUICQAAAA==.Viroqua:BAACNQAFFH8JAAITAAQKWwruBwDWAAATAAQKWwruBwDWAAA1AAQKfy8AAhMACgoTFhgcAGQCABMACgoTFhgcAGQCAAAA.',
Vo='Voxs:BAAANQADCgMIBgAAAA==.',
['Ví']='Ví:BAACNQAFFH8KAAIKAAQKHBTZGgA+AQAKAAQKHBTZGgA+AQA1AAQKfyoAAgoACgrsH/ceADwDAAoACgrsH/ceADwDAAAA.',
Wi='Wiccamaster:BAAANQADCgUIBQAAAA==.Wickerchickn:BAAANQADCgIIAgAAAA==.Wildfire:BAAANQADCgcICAAAAA==.Winkelsmom:BAABNQAECn8kAAIaAAgKHw4sIwDwAAAaAAgKHw4sIwDwAAAAAA==.',
Wo='Woobers:BAAANQAECgMIAwABNQAECgoKKgAEADMeAA==.Woru:BAAANQAECgIIBwAAAA==.',
Wr='Wrathofangus:BAAANQAECgUIBQAAAA==.',
Xa='Xarava:BAABNQAECn8aAAIHAAgKsg+AkQBdAQAHAAgKsg+AkQBdAQAAAA==.',
Ye='Yeetmachine:BAAANQAECgMIBQABNQAECgoKJQAEAL8ZAA==.',
Yo='Yogisa:BAAANQAECgEIAQAAAA==.',
Yu='Yuna:BAAANQAECgQIBgAAAA==.',
Za='Zarihanna:BAAANQAECgIIAgAAAA==.Zarijanna:BAAANQADCgcIBwAAAA==.Zarilenna:BAAANQADCgYICAAAAA==.Zarkanna:BAAANQADCgYIBwAAAA==.',
Ze='Zenogias:BAAANQAECgYIDgAAAA==.',
Zo='Zote:BAABNQAECn8tAAISAAgK4BwsBACtAgASAAgK4BwsBACtAgAAAA==.',
['ße']='ßenzyte:BAAANQAECgQIBwAAAA==.',
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
