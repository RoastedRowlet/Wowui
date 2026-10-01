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

local lookup = {'Hunter-BeastMastery','DemonHunter-Devourer','DeathKnight-Frost','DeathKnight-Unholy','Unknown-Unknown','Monk-Brewmaster','DeathKnight-Blood','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Paladin-Holy','Druid-Restoration','Druid-Balance','DemonHunter-Havoc','Rogue-Assassination','Paladin-Protection','Monk-Mistweaver','Warrior-Arms','Rogue-Outlaw','Mage-Arcane','Warrior-Fury','Paladin-Retribution','Warrior-Protection','Priest-Shadow','Priest-Discipline','Evoker-Preservation','Priest-Holy','Mage-Fire','Shaman-Elemental','Shaman-Restoration','Shaman-Enhancement','Mage-Frost','Evoker-Augmentation','Evoker-Devastation','Druid-Feral','Rogue-Subtlety','Druid-Guardian','Hunter-Marksmanship','DemonHunter-Vengeance','Monk-Windwalker',}
local provider = {region='US',realm='Stonemaul',name='US',type='weekly',zone=53,date='2026-09-29',data={Ad='Addalar:BAAANQAECgQIBgAAAA==.',
Ai='Airvis:BAAANQAECgMIBgAAAA==.',
Ak='Akar:BAAANQADCgMIAwAAAA==.',
Al='Alacia:BAAANQADCgQIBAABNQAECggIGAABAOoNAA==.',
Am='Amaira:BAAANQADCgQIBwAAAA==.Amalakar:BAAANQAECgEIAQAAAA==.Amnezea:BAAANQADCgIIAgAAAA==.',
An='Anankei:BAAANQADCgYIBgAAAA==.Anavere:BAAANQADCgUIBQAAAA==.Annasia:BAAANQAECgEIAQAAAA==.Antte:BAACNQAFFIEUAAICAAYKuRbVAgAKAgACAAYKuRbVAgAKAgA1AAQKgSQAAgIACQoKJJsFAGkDAAIACQoKJJsFAGkDAAAA.',
Ar='Arjun:BAAANQADCggIHAAAAA==.Armindru:BAAANQADCggIGgAAAA==.',
As='Asmôdeô:BAAANQAECgUICgAAAA==.Astin:BAAANQAECgEIAQAAAA==.',
At='Atom:BAAANQAECgQIDQAAAA==.Atreyu:BAAANQAECgYICwAAAA==.',
Aw='Awoozehl:BAACNQAFFIEVAAMDAAcKah1iAAB9AgADAAcKah1iAAB9AgAEAAEKaBx8FgBDAAA1AAQKgSYAAwMACQqgJqMBAMMDAAMACQqgJqMBAMMDAAQACApEGaJCAKsBAAAA.',
Az='Azgrodon:BAAANQAECgcIEwAAAA==.',
Ba='Banatok:BAAANQADCgIIAwAAAA==.Barzalie:BAAANQAECgEIAQABNQAFFAIIAwAFAAAAAA==.Bathrezz:BAAANQADCggIDgAAAA==.',
Be='Beanmage:BAAANQAECgUIBQAAAA==.Beerbelly:BAABNQAECoEYAAIGAAkKDhP2CwAFAgAGAAkKDhP2CwAFAgABNQAFFAIIAwAFAAAAAA==.Beleaves:BAACNQAFFIEWAAIGAAYKtQdYAgBrAQAGAAYKtQdYAgBrAQA1AAQKgSYAAgYACQowFk0JAE8CAAYACQowFk0JAE8CAAAA.Bellectra:BAAANQAECgMIAwAAAA==.',
Bi='Bifurious:BAAANQAECgUICgAAAA==.',
Bl='Blathur:BAAANQADCgcICQAAAA==.Bluereindeer:BAABNQAECoEcAAIHAAgKWQwoSwCHAQAHAAgKWQwoSwCHAQAAAA==.',
Bo='Bobafina:BAAANQADCggICAAAAA==.Bobsstones:BAACNQAFFIESAAQIAAcKlBWcAABWAQAIAAQK6RCcAABWAQAJAAMKbhQJEgD+AAAKAAIK+x36BgC2AAA1AAQKgSEABAoACQoCJcUSAM4BAAkABQpwJLpfAOkBAAoABQqhH8USAM4BAAgABApVIhILAGwBAAAA.Bobstofu:BAAANQAECgcIEwAAAA==.Bofaðeez:BAAANQADCgQIBAAAAA==.Bonkulo:BAAANQAECgYIEgAAAA==.Boofassist:BAACNQAFFIENAAILAAQK0h4XCQB8AQALAAQK0h4XCQB8AQA1AAQKgSQAAgsACQrhJDICAMADAAsACQrhJDICAMADAAAA.Boomsonic:BAAANQAECgIIAwABNQAECgUICgAFAAAAAA==.Boraga:BAAANQADCgYJBwAAAA==.',
Br='Brienyx:BAAANQADCgUIBwAAAA==.Briezani:BAAANQAECgIIAwAAAA==.Briogan:BAAANQAECgUICQAAAA==.Broccoliz:BAECNQAFFIEWAAIMAAcKJg4rAQA2AgAMAAcKJg4rAQA2AgA1AAQKgSkAAwwACQoXGwsQAJwCAAwACQoXGwsQAJwCAA0AAQpXFuqKAEYAAAAA.Brokan:BAAANQADCggIDgAAAA==.Broke:BAAANQAECgIIAgABNQAFFAYIEwAOALIjAQ==.',
Bu='Bukhaki:BAAANQAECgcIAwABNQAECgcIGgAPADgfAA==.',
['Bõ']='Bõb:BAAANQADCggICgAAAA==.',
Ca='Cafca:BAAANQAECgUJCQAAAA==.Caké:BAAANQADCgYIDAAAAA==.',
Ch='Chrams:BAABNQAECoEnAAILAAgK8R5PHgDJAgALAAgK8R5PHgDJAgAAAA==.',
Ci='Cialis:BAAANQADCgYIJgAAAA==.Cinnacrunch:BAAANQADCggIDQAAAA==.',
Cl='Clearlyumad:BAAANQAECgQIBwAAAA==.Clèrick:BAABNQAECoEoAAMLAAcKRyBWNgBOAgALAAYK1yFWNgBOAgAQAAcKLQ4cJQBbAQAAAA==.',
Co='Coldcrow:BAAANQADCgUICQAAAA==.Combination:BAABNQAECoEkAAIRAAkKsB7nBAAuAwARAAkKsB7nBAAuAwAAAA==.Cowen:BAAANQADCggIEQAAAA==.',
Cr='Crash:BAAANQADCgUIBQABNQAECgkJIwASAOsaAA==.Cray:BAAANQADCgIIAgAAAA==.',
Cu='Cursedotter:BAAANQAECgUIBwAAAA==.',
Da='Dabbyshatner:BAAANQAECgUIDAAAAA==.Daeneryis:BAAANQAECgMIAwAAAA==.Dankshammy:BAAANQAECggIEgAAAA==.Darkwave:BAABNQAECoEYAAMKAAcK8wx6PwCwAAAJAAUKigqvpwAfAQAKAAMKng16PwCwAAAAAA==.Darthdiddyus:BAACNQAFFIEMAAITAAQK+RLlAABTAQATAAQK+RLlAABTAQA1AAQKgScAAhMACQqwIcwBAD8DABMACQqwIcwBAD8DAAAA.Dathunter:BAAANQAECgIIAgABNQAECgkJGgAUAJoTAA==.Dawghawg:BAAANQADCgQIBAAAAA==.Dawnnie:BAABNQAECoEkAAIQAAkKqhkPCwCqAgAQAAkKqhkPCwCqAgAAAA==.Dawsonrogers:BAABNQAECoEaAAMVAAgKNBffBgA9AgAVAAgK7BbfBgA9AgASAAIKehOB9QCFAAAAAA==.',
De='Deathbanana:BAAANQADCggICAABNQAFFAcIEwAUAPYdAA==.Deathbydk:BAAANQAFFAIIAwAAAA==.Delema:BAACNQAFFIEIAAIWAAUKjgtTBwB7AQAWAAUKjgtTBwB7AQA1AAQKgR8AAxYACQoOHl9EAHwCABYACQoOHl9EAHwCABAAAQruAalkAB4AAAAA.Derbina:BAAANQABCgIIBAAAAA==.Destructer:BAAANQADCggIHwAAAA==.',
Di='Dirtydinker:BAAANQAECgcICQAAAA==.Dixsard:BAABNQAECoEaAAIPAAcKOB+BFgB6AgAPAAcKOB+BFgB6AgAAAA==.',
Do='Dontblink:BAAANQAECgEIAQABNQAECgkJJAARALAeAA==.Dorin:BAAANQABCgQIBAAAAA==.Dotore:BAAANQADCgYIBgAAAA==.Dottyflu:BAACNQAFFIELAAIHAAQKiBcQDQAdAQAHAAQKiBcQDQAdAQA1AAQKgSMAAgcACQq1IMMMACkDAAcACQq1IMMMACkDAAE1AAUUBQgFABAAigMA.Dottylawful:BAABNQAFFIEFAAIQAAUKigOYBAACAQAQAAUKigOYBAACAQAAAA==.',
Dr='Drexbear:BAAANQAECgQJBAABNQAFFAUIDwAXAEYQAA==.Drexl:BAACNQAFFIEPAAIXAAUKRhCUAQBUAQAXAAUKRhCUAQBUAQA1AAQKgR8AAxIACQpIDpeCAL8BABIACQp2CJeCAL8BABcAAgofISclALMAAAAA.',
Dw='Dweams:BAACNQAFFIEVAAIYAAYKPhohAgAZAgAYAAYKPhohAgAZAgA1AAQKgSMAAxgACQr0IzUHAEkDABgACQr0IzUHAEkDABkABgoxGvgJAHsBAAAA.Dweamu:BAAANQADCgMIAwABNQAFFAYIFQAYAD4aAA==.',
Ec='Ectonight:BAAANQADCgIIAgAAAA==.',
Eg='Eggfooyung:BAAANQAECgMIAwABNQAFFAQIDQALANIeAA==.Egwene:BAAANQAECgEIAQAAAA==.',
El='Elhonna:BAABNQAECoEjAAIBAAkKyB5THgDoAgABAAkKyB5THgDoAgAAAA==.',
En='Endcredits:BAAANQAECgMIBQAAAA==.',
Er='Eridyn:BAAANQAECgMIAwAAAA==.',
Ev='Evoulker:BAACNQAFFIEbAAIaAAcKthteAQCBAgAaAAcKthteAQCBAgA1AAQKgSYAAhoACQrWH8EIAPkCABoACQrWH8EIAPkCAAAA.',
Ez='Ezekielle:BAAANQAECgEIAQAAAA==.',
Fa='Faire:BAAANQADCgIIAgABNQAECgcIDwAFAAAAAA==.Fairytale:BAACNQAFFIEWAAIbAAYKXBEDBgDvAQAbAAYKXBEDBgDvAQA1AAQKgSYAAxsACQqEIegVAPUCABsACQpxIOgVAPUCABkABwrkHNUEADUCAAAA.Faker:BAAANQADCggIDwAAAA==.',
Fe='Felheim:BAABNQAECoElAAICAAkKNxRBGwBGAgACAAkKNxRBGwBGAgAAAA==.',
Fi='Fists:BAAANQADCgYJDAABNQAECgkJGAAaAPoZAA==.',
Fl='Flink:BAAANQADCgIJAgAAAA==.Floogi:BAAANQADCgMIAwAAAA==.',
Fo='Foxygal:BAAANQADCggIEwAAAA==.',
Fr='Frostyninja:BAAANQAECgIIAgAAAA==.',
Ga='Garchomp:BAAANQADCgQICAAAAA==.Gawain:BAAANQADCggJFAABNQAECggIHgABAOYZAA==.',
Ge='Gellina:BAAANQADCgMIAwAAAA==.Georg:BAACNQAFFIERAAIWAAcKLBcBAQByAgAWAAcKLBcBAQByAgA1AAQKgR4AAhYACQpxJccLAIkDABYACQpxJccLAIkDAAAA.Geriatric:BAAANQAECgIIAgABNQAFFAcIFQADAGodAA==.',
Gl='Glathur:BAAANQADCgIIBAAAAA==.Glizzygagger:BAABNQAECoEdAAIYAAkK1CKqBgBSAwAYAAkK1CKqBgBSAwABNQAECggIGgATAIggAA==.Glizzygorger:BAAANQAECgYIDQABNQAECggIGgATAIggAA==.',
Go='Goodbye:BAABNQAECoEcAAMUAAgKkh07ZACGAgAUAAgKkh07ZACGAgAcAAEKvQlgCgA4AAAAAA==.',
Gr='Grantoro:BAAANQAECgYIDwAAAA==.Grimmblades:BAAANQAECgIIAgAAAA==.Grootbeer:BAAANQAECgQIBwAAAA==.',
Gu='Gulgrimmar:BAACNQAFFIEUAAMdAAcK8BiPBQDKAQAdAAUKfxqPBQDKAQAeAAMKZh0uDQAMAQA1AAQKgSEAAx0ACQpiJXsEALwDAB0ACQpiJXsEALwDAB4ABQqMGwFfAJsBAAAA.Guwudanielle:BAAANQAECgcIDwAAAA==.',
['Gä']='Gävinräd:BAAANQABCgQIBQAAAA==.',
Ha='Haranguetan:BAAANQADCgYIBgABNQAECggIHQAfAOoMAA==.Hardfeelings:BAAANQAECgMIBQAAAA==.Harrharr:BAAANQADCgMIAwAAAA==.',
He='Headache:BAAANQABCgIIAgABNQAECgUICgAFAAAAAA==.',
Ho='Hodann:BAAANQABCgYJBgAAAA==.',
Hu='Hurjek:BAAANQAECgUICQABNQAECgkJJAARALAeAA==.',
Ic='Iconicmax:BAAANQAECgQIBwAAAA==.',
Ij='Ijustankedu:BAAANQADCgEIAQAAAA==.',
Il='Ilyana:BAABNQAECoElAAMUAAkKKiDbVwCmAgAUAAgKBh/bVwCmAgAgAAIKKCIRHwC0AAAAAA==.',
In='Insights:BAAANQAECgMIBQAAAA==.',
Is='Ishtann:BAAANQABCgIIAgAAAA==.',
Ja='Jaqen:BAABNQAECoEaAAMTAAgKiCDVAgDzAgATAAgKiCDVAgDzAgAPAAEK4Q1YcwA8AAAAAA==.Jayc:BAABNQAECoEcAAIUAAgKeR98QQDhAgAUAAgKeR98QQDhAgAAAA==.',
Je='Jereico:BAACNQAFFIEWAAMhAAcKfiB+AAC4AgAhAAcKfiB+AAC4AgAiAAEKqxq3CwBMAAA1AAQKgSYAAyEACQr/JYIAAL4DACEACQr/JYIAAL4DACIACAoEFWEUAMUBAAAA.Jeryhn:BAACNQAFFIEXAAILAAUKrBuvBQDAAQALAAUKrBuvBQDAAQA1AAQKgSYAAgsACQrNIqwIAGgDAAsACQrNIqwIAGgDAAAA.',
Jo='Joeynodz:BAAANQADCggIIwAAAA==.Jortshorts:BAABNQAECoEZAAIjAAgKFwf5EgBZAQAjAAgKFwf5EgBZAQAAAA==.',
Ju='Juggalo:BAACNQAFFIEIAAIiAAQKHhatBABCAQAiAAQKHhatBABCAQA1AAQKgTEAAyIACQpFI2cCAHkDACIACQpFI2cCAHkDACEAAgoKDd8WAHIAAAAA.June:BAACNQAFFIEUAAIRAAcK1xG7AABCAgARAAcK1xG7AABCAgA1AAQKgScAAhEACQoeIOEGAPsCABEACQoeIOEGAPsCAAAA.',
Ka='Kalikin:BAAANQAECgMJBAAAAA==.Kawasuoo:BAAANQADCgQIBAABNQAECgUIBwAFAAAAAA==.',
Kc='Kcudüm:BAABNQAECoEbAAQKAAgKFBAREADtAQAKAAgKJg8READtAQAJAAMKtAa35QCLAAAIAAEKGA+hJQA6AAAAAA==.',
Ke='Keifis:BAAANQADCgEJAQAAAA==.Keifism:BAAANQABCgMIAwAAAA==.',
Kh='Khaotichic:BAAANQAECgEIAQAAAA==.',
Kl='Klrum:BAABNQAECoEeAAMUAAcKBxgplwAOAgAUAAcK9RcplwAOAgAgAAQKgg1NHADJAAAAAA==.',
Ko='Koddin:BAABNQAECoEcAAIWAAgKLRpxVwA9AgAWAAgKLRpxVwA9AgAAAA==.Komui:BAABNQAECoEcAAMeAAgKJxYwTADiAQAeAAgKJxYwTADiAQAdAAYK4wqUfQBUAQAAAA==.Koreth:BAACNQAFFIEWAAMPAAcKGRXNAAB3AgAPAAcKGRXNAAB3AgAkAAEK9w62EABJAAA1AAQKgScAAw8ACQo8I+IEAGADAA8ACQo8I+IEAGADACQACApsGOUTACgCAAAA.Kornholyo:BAAANQAECgIIAwAAAA==.',
Kr='Krakheeta:BAAANQADCgQIBAAAAA==.Krusade:BAAANQAECgUICQAAAA==.',
Ku='Kumo:BAAANQAECgEIAQAAAA==.Kutuzov:BAAANQADCggIGwAAAA==.',
Kw='Kwenny:BAAANQADCgUIBQAAAA==.',
La='Lailaysia:BAAANQADCggICAAAAA==.Lamemoosaur:BAABNQAECoEWAAIlAAkKhh2/BAAGAwAlAAkKhh2/BAAGAwAAAA==.Laríca:BAABNQAECoEoAAILAAkKASOFBACZAwALAAkKASOFBACZAwAAAA==.Laydout:BAAANQADCgQIBAABNQAECgYIEAAFAAAAAA==.Laydoutyota:BAAANQAECgYIEAAAAA==.Laymow:BAAANQAECgQJBAABNQAECgkJFgAlAIYdAA==.',
Le='Levity:BAAANQAECggIBQAAAA==.',
Li='Lilea:BAABNQAECoEYAAMBAAgK6g0OkQCBAQABAAYK/gwOkQCBAQAmAAUKaglOQADoAAAAAA==.Lilfaart:BAAANQAECggIBAAAAA==.Lindisalvia:BAAANQADCgIIAgAAAA==.Lionsmane:BAAANQADCgYIBgAAAA==.',
Lo='Loosemorals:BAABNQAECoEYAAIaAAkK+hlaDAC5AgAaAAkK+hlaDAC5AgAAAA==.Lootgoblin:BAABNQAECoEaAAIUAAkKmhOFcQBmAgAUAAkKmhOFcQBmAgAAAA==.Lortherian:BAAANQAECgIIBAAAAA==.',
['Lä']='Läwlbringer:BAAANQAECgYIDgAAAA==.',
Ma='Mabritoe:BAACNQAFFIEHAAIPAAQKZyFcBABzAQAPAAQKZyFcBABzAQA1AAQKgR4AAw8ACQqzIfEIABoDAA8ACAodJPEIABoDACQACApyCz8cAMwBAAE1AAUUBwgRAA0A7BMA.Malison:BAAANQADCgUIBAAAAA==.Mangle:BAAANQADCgUIBQAAAA==.Mania:BAAANQADCgYICgABNQAECgUICgAFAAAAAA==.Mareth:BAAANQADCgIIAgAAAA==.Mathath:BAABNQAECoEVAAMEAAgKmRzVLgAbAgAEAAgKtxfVLgAbAgAHAAMKcyFdZQATAQAAAA==.Mathoras:BAAANQADCgYIBgAAAA==.Maxboom:BAAANQADCggIHQAAAA==.Mayaho:BAAANQAECgQICQAAAA==.',
Me='Meatier:BAAANQAECgEIAQABNQAECgUICgAFAAAAAA==.Mellinia:BAAANQADCgEIAQAAAA==.Meoverdahill:BAAANQABCgIIAgAAAA==.',
Mi='Miltonroe:BAABNQAECoEdAAIfAAgK6gy9EAAVAgAfAAgK6gy9EAAVAgAAAA==.Miltonroé:BAAANQAECgQIBAABNQAECggIHQAfAOoMAA==.Mixing:BAAANQADCgIJAgAAAA==.',
Mo='Monnz:BAAANQADCgUIBQAAAA==.Monsterskill:BAAANQAECgEIAQAAAA==.Moonerva:BAAANQAECgMIBQAAAA==.Morana:BAAANQADCgQIBAAAAA==.',
Mv='Mvqchx:BAAANQADCgEIAQAAAA==.',
My='Myrolous:BAAANQADCgQIBAAAAA==.',
['Mã']='Mãrtrydóm:BAAANQABCgQIBAAAAA==.',
['Mì']='Mìssy:BAAANQADCggICwAAAA==.',
Na='Namiin:BAAANQADCgUIBQAAAA==.Naughtye:BAAANQAECgEIAQAAAA==.Nave:BAAANQAECgcICAAAAA==.',
Ne='Nelfsfault:BAAANQADCggJFwAAAA==.Nerotappo:BAAANQABCgIIAgAAAA==.',
Ni='Ninja:BAAANQADCgYJBgAAAA==.',
No='Nobacon:BAAANQADCgIIAgAAAA==.Noshaku:BAAANQAECgIIAgAAAA==.Notanorc:BAAANQAECgYIEwAAAA==.',
Od='Odium:BAAANQAECgIIAgAAAA==.',
Oh='Ohrolam:BAABNQAECoEeAAMUAAgKPwVz2wB/AQAUAAgKzgRz2wB/AQAgAAEKBAakOgA0AAAAAA==.',
Ok='Okasan:BAAANQAECgQIBAABNQAECgQICAAFAAAAAA==.',
Ot='Ottersdemons:BAAANQAECgIIAgAAAA==.',
Pa='Palthur:BAAANQADCggICwAAAA==.Paradoxis:BAAANQABCgIIAgAAAA==.Passionate:BAAANQADCgUIBQAAAA==.',
Ph='Phatmidas:BAAANQAECgYIDQAAAA==.Phrozenpally:BAAANQAECgIIAwABNQAECgQICQAFAAAAAA==.',
Pi='Pika:BAAANQADCgcIBwABNQAFFAIIAwAFAAAAAA==.Pinkponythug:BAAANQAECgIJAgABNQAECgkJGAAaAPoZAA==.',
Pl='Plagueground:BAACNQAFFIEUAAQDAAcKRCF+AABkAgADAAYKVCN+AABkAgAHAAIKaAthGgBvAAAEAAEKsA84GAA7AAA1AAQKgSoABAMACQo0JqkBAMMDAAMACQo0JqkBAMMDAAcAAgr4Ht2BAKkAAAQAAQrJBaixADAAAAAA.',
Po='Poc:BAAANQAECgMIBAAAAA==.Pounces:BAABNQAECoErAAIjAAkKRyW2AADPAwAjAAkKRyW2AADPAwAAAA==.',
Pr='Prózak:BAAANQADCgYIBgABNQAECgYIEQAFAAAAAA==.Prôzak:BAAANQAECgYIEQAAAA==.',
Ps='Psychomidget:BAAANQAECgEIAQAAAA==.',
Pu='Puetrid:BAABNQAECoEcAAIKAAkK5RdFBQC2AgAKAAkK5RdFBQC2AgAAAA==.Purble:BAAANQADCgIIAgAAAA==.Puufrumslli:BAAANQAECgYIEAAAAA==.',
Ra='Rageinglight:BAAANQAECgMIBQAAAA==.Rakku:BAAANQABCgcJBgAAAA==.Rautha:BAABNQAECoEcAAIWAAgKAxPgcQDtAQAWAAgKAxPgcQDtAQAAAA==.Rayl:BAAANQAECgEIAQAAAA==.',
Rh='Rhaegon:BAABNQAECoEfAAInAAgKERoRBgBqAgAnAAgKERoRBgBqAgAAAA==.',
Ri='Rimath:BAAANQADCggIEAAAAA==.',
Rn='Rng:BAAANQADCggIFAAAAA==.',
Ro='Rodstewart:BAAANQAECggIEwAAAA==.Ronz:BAAANQABCgEJAQAAAA==.Rotdaddy:BAAANQAECgYIDgAAAA==.',
Sa='Sabatikus:BAAANQAECgEJAQAAAA==.Salino:BAAANQAECgUICAAAAA==.Sam:BAAANQAECgcIEAAAAA==.Sandorindis:BAAANQADCgYIBwAAAA==.Sarate:BAAANQADCggIEAAAAA==.Satral:BAAANQAECgUJBgAAAA==.Savannah:BAAANQAECgYIBwABNQAECgcIDwAFAAAAAA==.Savvtwo:BAAANQADCgEIAQABNQAFFAYIEwAOALIjAQ==.',
Se='Sezra:BAAANQADCggICAAAAA==.',
Sh='Shaetahn:BAAANQAECgEIAQAAAA==.Shamwowthorn:BAAANQADCgEIAQAAAA==.Shinanigans:BAABNQAECoEaAAIWAAkKORu/LgDQAgAWAAkKORu/LgDQAgAAAA==.Shockbull:BAAANQADCgcJBwAAAA==.',
Si='Silverbäck:BAAANQAECgIIAgABNQADCggIHAAFAAAAAA==.Silverslam:BAAANQADCggIFwABNQADCggIHAAFAAAAAA==.',
Sk='Skurge:BAAANQAECgIIBAAAAA==.',
Sn='Snacks:BAAANQADCgEIAQABNQAECgcIEAAFAAAAAA==.',
So='Solstis:BAAANQAECgUICQAAAA==.Soranwena:BAABNQAECoEYAAIlAAcKnxhsDwDoAQAlAAcKnxhsDwDoAQAAAA==.Sorros:BAAANQAECgEIAQAAAA==.',
Sp='Spacegoat:BAAANQAECgMIAwAAAA==.Spfzero:BAAANQADCggICgAAAA==.',
St='Sticksy:BAAANQADCgYIBgAAAA==.Stonebeard:BAAANQAECgQIBgAAAA==.Stârlèss:BAAANQADCgYIBwAAAA==.',
Su='Subtox:BAAANQAECgUIBwAAAA==.',
Sw='Swedishfish:BAAANQAECgEIAQABNQAECgkJHQAYACMdAA==.',
['Sá']='Sálúd:BAAANQAECgcIEQAAAA==.',
Ta='Tarhealeon:BAAANQAECgUIDQAAAA==.Tarvuspls:BAAANQAECgYICAAAAA==.',
Te='Teemawthy:BAAANQADCgMIAwAAAA==.Temozo:BAAANQADCgIIAgAAAA==.',
Th='Thabigone:BAAANQADCgQICAAAAA==.Theceo:BAAANQADCgYIDgAAAA==.',
Ti='Ticklemebutt:BAAANQAECgUIBQAAAA==.Tiewaz:BAAANQADCgUIBQABNQAECgQIBgAFAAAAAA==.',
To='Tolun:BAABNQAECoEaAAIgAAkK/RSLBgBOAgAgAAkK/RSLBgBOAgAAAA==.Tosan:BAAANQAECgQICAAAAA==.Toughcookie:BAAANQAECgUICQAAAA==.',
Tr='Treeplague:BAAANQAECgYIDAAAAA==.',
Tu='Turn:BAACNQAFFIEYAAQKAAcKAxOrAQAGAQAIAAMKpBUfAQAIAQAKAAMK7ROrAQAGAQAJAAMKpQ3yEwDwAAA1AAQKgSUABAoACQr5ItoMABgCAAoABwpPF9oMABgCAAgABQrnJMIGAPQBAAkABQrPG/93AJ8BAAAA.Turtleduck:BAAANQADCgUIBQABNQADCggIGgAFAAAAAA==.',
Ty='Tyla:BAAANQADCggIGwAAAA==.Typhis:BAAANQADCgYIBgAAAA==.',
['Tì']='Tìewaz:BAAANQAECgQIBgAAAA==.',
Um='Umbryx:BAAANQADCgYICwAAAA==.',
Un='Unagi:BAAANQAECgUIDQAAAA==.',
Va='Valdir:BAAANQAECggIBgAAAA==.Vasomir:BAAANQABCgIIAQAAAA==.',
Ve='Venøm:BAAANQAECgEIAQAAAA==.',
Vi='Viscerion:BAAANQAECgQIBwAAAA==.',
Wh='Whoarlock:BAAANQADCgYICAAAAA==.',
Wi='Wizzyy:BAAANQADCgUIBQAAAA==.',
Xe='Xelinia:BAACNQAFFIEJAAMYAAUKJglbCAAZAQAYAAQKcQpbCAAZAQAbAAEK8AE+KABGAAA1AAQKgR8AAxgACQqEHekQALECABgACQqEHekQALECABsAAQrfAdDSACMAAAAA.Xen:BAAANQAECggICwAAAA==.',
Xu='Xuefeng:BAABNQAECoEnAAIoAAkK6B7ICQAMAwAoAAkK6B7ICQAMAwAAAA==.',
Ya='Yahwae:BAAANQAECgQIBAABNQAECgcIGAAKAPMMAA==.',
Yc='Ycephyre:BAAANQAECgIIAwAAAA==.',
Ye='Yenchmeister:BAACNQAFFIEVAAISAAYKdxbvBgDtAQASAAYKdxbvBgDtAQA1AAQKgSYAAhIACQrZJDoPAG8DABIACQrZJDoPAG8DAAAA.',
Zd='Zdervish:BAAANQAECgYICwAAAA==.',
Ze='Zeffira:BAAANQAECgQIAwAAAA==.Zellda:BAAANQADCgYIBgAAAA==.',
Zi='Zilvanion:BAABNQAECoEeAAIJAAkK+RIyQgBLAgAJAAkK+RIyQgBLAgAAAA==.',
Zl='Zlathur:BAAANQADCgcIDgAAAA==.',
Zo='Zourknight:BAAANQADCgcIBwAAAA==.Zourlight:BAAANQADCgcICAAAAA==.Zourlock:BAAANQADCggIDgAAAA==.Zourvoid:BAAANQADCgUICAAAAA==.',
['Ðr']='Ðrèamless:BAAANQAECgUICwAAAA==.',
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
