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

local lookup = {'Unknown-Unknown','DemonHunter-Devourer','DeathKnight-Frost','DeathKnight-Unholy','Monk-Brewmaster','Warlock-Affliction','Warlock-Destruction','Warlock-Demonology','Paladin-Holy','Druid-Restoration','Druid-Balance','Rogue-Assassination','Paladin-Protection','Monk-Mistweaver','Warrior-Arms','Rogue-Outlaw','Warrior-Fury','Mage-Arcane','Paladin-Retribution','DeathKnight-Blood','Warrior-Protection','Priest-Shadow','Priest-Discipline','Hunter-BeastMastery','Evoker-Preservation','Priest-Holy','Mage-Fire','Shaman-Elemental','Shaman-Restoration','Mage-Frost','Evoker-Augmentation','Evoker-Devastation','Rogue-Subtlety','Druid-Feral','DemonHunter-Vengeance','Monk-Windwalker',}
local provider = {region='US',realm='Stonemaul',name='US',type='weekly',zone=53,date='2026-09-22',data={Ad='Addalar:BAAANQAECgMJAwAAAA==.',
Ai='Airvis:BAAANQAECgIIAwAAAA==.',
Ak='Akar:BAAANQADCgMIAwAAAA==.',
Al='Alacia:BAAANQADCgQIBAABNQAECgYIDQABAAAAAA==.',
Am='Amaira:BAAANQADCgQIBwAAAA==.Amalakar:BAAANQAECgEJAQAAAA==.Amnezea:BAAANQADCgIIAgAAAA==.',
An='Anankei:BAAANQADCgYIBgAAAA==.Annasia:BAAANQAECgEIAQAAAA==.Antte:BAACNQAFFIERAAICAAYKMRMTAgAOAgACAAYKMRMTAgAOAgA1AAQKgSQAAgIACQoKJK8DAIwDAAIACQoKJK8DAIwDAAAA.',
Ar='Arjun:BAAANQADCggIFQAAAA==.Armindru:BAAANQADCgcJEgAAAA==.',
As='Asmôdeô:BAAANQAECgUICAAAAA==.Astin:BAAANQAECgEIAQAAAA==.',
At='Atom:BAAANQAECgQIDQAAAA==.Atreyu:BAAANQAECgYICwAAAA==.',
Aw='Awoozehl:BAACNQAFFIERAAMDAAYKah1uAAA/AgADAAYKah1uAAA/AgAEAAEKaBwODgBSAAA1AAQKgSQAAwMACQqgJq8AAOsDAAMACQqgJq8AAOsDAAQACApEGbouAPgBAAAA.',
Az='Azgrodon:BAAANQAECgYJDAAAAA==.',
Ba='Banatok:BAAANQADCgIIAwAAAA==.Barzalie:BAAANQAECgEIAQABNQAFFAEJAQABAAAAAA==.Bathrezz:BAAANQADCgYIBgAAAA==.',
Be='Beanmage:BAAANQAECgQIBAAAAA==.Beerbelly:BAAANQAECgcJDQABNQAFFAEJAQABAAAAAA==.Beleaves:BAACNQAFFIETAAIFAAYKugaRAQBqAQAFAAYKugaRAQBqAQA1AAQKgSQAAgUACQrVFUQHAGQCAAUACQrVFUQHAGQCAAAA.Bellectra:BAAANQADCggJHQAAAA==.',
Bi='Bifurious:BAAANQAECgQJCQAAAA==.',
Bl='Blathur:BAAANQADCgcICQAAAA==.Bluereindeer:BAAANQAECgYJEwAAAA==.',
Bo='Bobafina:BAAANQADCggICAAAAA==.Bobsstones:BAACNQAFFIEQAAQGAAYK6BZaAABeAQAGAAQK6RBaAABeAQAHAAIK+x0FBQC9AAAIAAIK1BffFgCiAAA1AAQKgR8ABAcACQqpI+IQANcBAAgABQoEIi5SANgBAAcABQqhH+IQANcBAAYABApVIqMIAHoBAAAA.Bobstofu:BAAANQAECgcIEwAAAA==.Bofaðeez:BAAANQADCgQIBAAAAA==.Bonkulo:BAAANQAECgYIDAAAAA==.Boofassist:BAACNQAFFIEKAAIJAAQK0h4QBgCGAQAJAAQK0h4QBgCGAQA1AAQKgSIAAgkACQrhJIQBAMcDAAkACQrhJIQBAMcDAAAA.Boomsonic:BAAANQAECgEIAQABNQAECgQJCQABAAAAAA==.Boraga:BAAANQADCgYJBwAAAA==.',
Br='Brienyx:BAAANQADCgUIBwAAAA==.Briezani:BAAANQAECgIJAgAAAA==.Briogan:BAAANQAECgQIBAAAAA==.Broccoliz:BAECNQAFFIERAAIKAAYKUQ9uAQDcAQAKAAYKUQ9uAQDcAQA1AAQKgSYAAwoACQoXG/ELAKwCAAoACQoXG/ELAKwCAAsAAQq1C0d/ADkAAAAA.Brokan:BAAANQADCggIDgAAAA==.',
Bu='Bukhaki:BAAANQAECgcJCAABNQAECgcJFQAMAJEeAA==.',
['Bõ']='Bõb:BAAANQADCggICgAAAA==.',
Ca='Cafca:BAAANQAECgUJCQAAAA==.Caké:BAAANQADCgYIDAAAAA==.',
Ch='Chrams:BAABNQAECoEgAAIJAAgK8R4NFwDVAgAJAAgK8R4NFwDVAgAAAA==.',
Ci='Cialis:BAAANQADCgYIJgAAAA==.Cinnacrunch:BAAANQADCggIDQAAAA==.',
Cl='Clearlyumad:BAAANQAECgQIBwAAAA==.Clèrick:BAABNQAECoEfAAMJAAYK1yHKKwBVAgAJAAYK1yHKKwBVAgANAAEKAgk6UQAmAAAAAA==.',
Co='Coldcrow:BAAANQADCgUICQAAAA==.Combination:BAABNQAECoEbAAIOAAgKXx7gBwDEAgAOAAgKXx7gBwDEAgAAAA==.Cowen:BAAANQADCggIEQAAAA==.',
Cr='Crash:BAAANQADCgUIBQABNQAECgkJIAAPAIAaAA==.Cray:BAAANQADCgIIAgAAAA==.',
Cu='Cursedotter:BAAANQAECgQIBAAAAA==.',
Da='Dabbyshatner:BAAANQAECgQIDAAAAA==.Daeneryis:BAAANQAECgMIAwAAAA==.Dankshammy:BAAANQAECgUICwAAAA==.Darkwave:BAAANQAECgYIDwAAAA==.Darthdiddyus:BAACNQAFFIEIAAIQAAQKzhGcAABaAQAQAAQKzhGcAABaAQA1AAQKgSQAAhAACQqmIVMBAFwDABAACQqmIVMBAFwDAAAA.Dawghawg:BAAANQADCgQIBAAAAA==.Dawnnie:BAABNQAECoEcAAINAAgK0hYSEAAZAgANAAgK0hYSEAAZAgAAAA==.Dawsonrogers:BAABNQAECoEYAAMRAAgK7BbnBABYAgARAAgK7BbnBABYAgAPAAIKoQxr3QB6AAAAAA==.',
De='Deathbanana:BAAANQADCggICAABNQAFFAYIEQASAPocAA==.Deathbydk:BAAANQAFFAEJAQAAAA==.Delema:BAABNQAECoEcAAMTAAkKXR3oOQBsAgATAAkKXR3oOQBsAgANAAEK7gE0VQAgAAAAAA==.Derbina:BAAANQABCgIIBAAAAA==.Destructer:BAAANQADCggIFwAAAA==.',
Di='Dirtydinker:BAAANQAECgcJCQAAAA==.Dixsard:BAABNQAECoEVAAIMAAcKkR69EQB4AgAMAAcKkR69EQB4AgAAAA==.',
Do='Dontblink:BAAANQAECgEIAQABNQAECggIGwAOAF8eAA==.Dorin:BAAANQABCgQIBAAAAA==.Dotore:BAAANQADCgYIBgAAAA==.Dottyflu:BAACNQAFFIELAAIUAAQKiBceCQAfAQAUAAQKiBceCQAfAQA1AAQKgSIAAhQACQq1IGUJAD4DABQACQq1IGUJAD4DAAAA.Dottylawful:BAAANQAECgIJAgABNQAFFAQJCwAUAIgXAA==.',
Dr='Drexbear:BAAANQAECgQJBAABNQAFFAUJDQAVACIPAA==.Drexl:BAACNQAFFIENAAIVAAUKIg/tAABzAQAVAAUKIg/tAABzAQA1AAQKgR8AAw8ACQpIDqtqAM0BAA8ACQp2CKtqAM0BABUAAgofIVgeALoAAAAA.',
Dw='Dweams:BAACNQAFFIEQAAIWAAUK4hiUAgDAAQAWAAUK4hiUAgDAAQA1AAQKgSMAAxYACQr0IxEEAIIDABYACQr0IxEEAIIDABcABgoxGmQIAIIBAAAA.Dweamu:BAAANQADCgMIAwABNQAFFAUJEAAWAOIYAA==.',
Ec='Ectonight:BAAANQADCgIIAgAAAA==.',
Eg='Egwene:BAAANQAECgEIAQAAAA==.',
El='Elhonna:BAABNQAECoEdAAIYAAgKTh4MJwCaAgAYAAgKTh4MJwCaAgAAAA==.',
En='Endcredits:BAAANQAECgIJAgAAAA==.',
Er='Eridyn:BAAANQAECgEIAQAAAA==.',
Ev='Evoulker:BAACNQAFFIEVAAIZAAYKlR25AQA8AgAZAAYKlR25AQA8AgA1AAQKgSQAAhkACQrWHxYHAAYDABkACQrWHxYHAAYDAAAA.',
Ez='Ezekielle:BAAANQAECgEIAQAAAA==.',
Fa='Faire:BAAANQADCgIIAgABNQAECgcIDwABAAAAAA==.Fairytale:BAACNQAFFIESAAIaAAYKExDHAwDzAQAaAAYKExDHAwDzAQA1AAQKgSQAAxoACQqEIdQOAAgDABoACQpxINQOAAgDABcABwrkHAAEADsCAAAA.Faker:BAAANQADCggIDwAAAA==.',
Fe='Felheim:BAABNQAECoEiAAICAAkK1RFiGQBAAgACAAkK1RFiGQBAAgAAAA==.',
Fi='Fists:BAAANQADCgYJDAABNQAECgkJFQAZAFQZAA==.',
Fl='Flink:BAAANQADCgIJAgAAAA==.Floogi:BAAANQADCgMIAwAAAA==.',
Fo='Foxygal:BAAANQADCggIEwAAAA==.',
Fr='Frostyninja:BAAANQAECgIIAgAAAA==.',
Ga='Garchomp:BAAANQADCgQICAAAAA==.Gawain:BAAANQADCggJFAABNQAECgYIEwABAAAAAA==.',
Ge='Gellina:BAAANQADCgIIAgAAAA==.Georg:BAACNQAFFIEMAAITAAUKXhgEAwC9AQATAAUKXhgEAwC9AQA1AAQKgRwAAhMACQpuJQAHAKUDABMACQpuJQAHAKUDAAAA.Geriatric:BAAANQAECgEIAQABNQAFFAYIEQADAGodAA==.',
Gl='Glathur:BAAANQADCgIIAgAAAA==.Glizzygagger:BAABNQAECoEZAAIWAAkKliCNBwA4AwAWAAkKliCNBwA4AwAAAA==.Glizzygorger:BAAANQAECgYIDAABNQAECgkJGQAWAJYgAA==.',
Go='Goodbye:BAABNQAECoEbAAMSAAgKkh0WTACnAgASAAgKkh0WTACnAgAbAAEKvQm5CAA5AAAAAA==.',
Gr='Grantoro:BAAANQAECgYJCQAAAA==.Grimmblades:BAAANQAECgIIAgAAAA==.Grootbeer:BAAANQAECgEJAgAAAA==.',
Gu='Gulgrimmar:BAACNQAFFIEPAAMcAAYK9hVHBACsAQAcAAUKRhVHBACsAQAdAAIKKBpWEACiAAA1AAQKgR8AAxwACQqfJZcLAF4DABwACAqlJZcLAF4DAB0ABQqMG21NALMBAAAA.Guwudanielle:BAAANQAECgcIDwAAAA==.',
Ha='Haranguetan:BAAANQADCgYIBgABNQAECgYIEwABAAAAAA==.Hardfeelings:BAAANQAECgIJAgAAAA==.Harrharr:BAAANQADCgMIAwAAAA==.',
He='Headache:BAAANQABCgIIAgABNQAECgQJCQABAAAAAA==.',
Ho='Hodann:BAAANQABCgYJBgAAAA==.',
Hu='Hurjek:BAAANQAECgQIBAABNQAECggIGwAOAF8eAA==.',
Ic='Iconicmax:BAAANQAECgQIBQAAAA==.',
Ij='Ijustankedu:BAAANQADCgEIAQAAAA==.',
Il='Ilyana:BAABNQAECoEdAAMSAAkK3B8TTQCkAgASAAgKrx4TTQCkAgAeAAIKKCIiGQC6AAAAAA==.',
In='Insights:BAAANQAECgIJAgAAAA==.',
Is='Ishtann:BAAANQABCgIIAgAAAA==.',
Ja='Jaqen:BAAANQAECggIEgABNQAECgkJGQAWAJYgAA==.Jayc:BAABNQAECoEYAAISAAgKWx9UNADwAgASAAgKWx9UNADwAgAAAA==.',
Je='Jereico:BAACNQAFFIESAAMfAAYKQR+4AABEAgAfAAYKQR+4AABEAgAgAAEKqxqXCQBTAAA1AAQKgSQAAx8ACQr3JU8AANMDAB8ACQr3JU8AANMDACAACAoEFSoRAOYBAAAA.Jeryhn:BAACNQAFFIETAAIJAAUKURu1AwDLAQAJAAUKURu1AwDLAQA1AAQKgSQAAgkACQrNIkYGAHIDAAkACQrNIkYGAHIDAAAA.',
Jo='Joeynodz:BAAANQADCggIIwAAAA==.Jortshorts:BAAANQAECgUIDwAAAA==.',
Ju='Juggalo:BAABNQAECoEoAAMgAAkKqSAWAwBYAwAgAAkKciAWAwBYAwAfAAIKCg3VEgB8AAAAAA==.June:BAACNQAFFIEPAAIOAAUKiQ4RAgCOAQAOAAUKiQ4RAgCOAQA1AAQKgSUAAg4ACQoeIMUEABoDAA4ACQoeIMUEABoDAAAA.',
Ka='Kalikin:BAAANQAECgMJBAAAAA==.Kawasuoo:BAAANQADCgQIBAABNQAECgQIBAABAAAAAA==.',
Kc='Kcudüm:BAAANQAECgYJEgAAAA==.',
Ke='Keifis:BAAANQADCgEJAQAAAA==.Keifism:BAAANQABCgMIAwAAAA==.',
Kh='Khaotichic:BAAANQAECgEIAQAAAA==.',
Kl='Klrum:BAABNQAECoEXAAMeAAYK3xSyFgDRAAASAAYKyhT0pwC2AQAeAAQKgg2yFgDRAAAAAA==.',
Ko='Koddin:BAAANQAECgYJEwAAAA==.Komui:BAAANQAECgYJEwAAAA==.Koreth:BAACNQAFFIERAAMMAAYKrBayAAAzAgAMAAYKrBayAAAzAgAhAAEK9w7gDQBJAAA1AAQKgSUAAwwACQodIlEEAFUDAAwACQodIlEEAFUDACEACApsGBERADkCAAAA.Kornholyo:BAAANQAECgIJAwAAAA==.',
Kr='Krakheeta:BAAANQADCgQIBAAAAA==.Krusade:BAAANQAECgQIBAAAAA==.',
Ku='Kumo:BAAANQAECgEIAQAAAA==.Kutuzov:BAAANQADCggJEwAAAA==.',
La='Lamemoosaur:BAAANQAECggIDwAAAA==.Laríca:BAABNQAECoEfAAIJAAgKRSJKDQAlAwAJAAgKRSJKDQAlAwAAAA==.Laydout:BAAANQADCgQIBAABNQAECgUIDgABAAAAAA==.Laydoutyota:BAAANQAECgUIDgAAAA==.Laymow:BAAANQAECgQJBAABNQAECggIDwABAAAAAA==.',
Le='Levity:BAAANQAECggIBQAAAA==.',
Li='Lilea:BAAANQAECgYIDQAAAA==.Lilfaart:BAAANQAECggIBAAAAA==.Lindisalvia:BAAANQADCgIIAgAAAA==.Lionsmane:BAAANQADCgYIBgAAAA==.',
Lo='Loosemorals:BAABNQAECoEVAAIZAAkKVBlKCwCuAgAZAAkKVBlKCwCuAgAAAA==.Lootgoblin:BAAANQAECggIEQAAAA==.Lortherian:BAAANQAECgIIAgAAAA==.',
['Lä']='Läwlbringer:BAAANQAECgUIDQAAAA==.',
Ma='Mabritoe:BAACNQAFFIEGAAIMAAQKZyFVAgCIAQAMAAQKZyFVAgCIAQA1AAQKgR4AAwwACQqzIbMFADUDAAwACAodJLMFADUDACEACApyC5YYANwBAAAA.Malison:BAAANQADCgUIBAAAAA==.Mangle:BAAANQADCgUIBQAAAA==.Mania:BAAANQADCgYICgABNQAECgQJCQABAAAAAA==.Mareth:BAAANQADCgIIAgAAAA==.Mathath:BAAANQAECgUIDgAAAA==.Mathoras:BAAANQADCgYIBgAAAA==.Maxboom:BAAANQADCggIHQAAAA==.Mayaho:BAAANQAECgQIBgAAAA==.',
Me='Meatier:BAAANQAECgEIAQABNQAECgQJCQABAAAAAA==.Meoverdahill:BAAANQABCgIIAgAAAA==.',
Mi='Miltonroe:BAAANQAECgYIEwAAAA==.Miltonroé:BAAANQADCggIDgABNQAECgYIEwABAAAAAA==.Mixing:BAAANQADCgIJAgAAAA==.',
Mo='Monnz:BAAANQADCgUIBQAAAA==.Monsterskill:BAAANQAECgEIAQAAAA==.Moonerva:BAAANQAECgIJAgAAAA==.',
Mv='Mvqchx:BAAANQADCgEIAQAAAA==.',
My='Myrolous:BAAANQADCgQIBAAAAA==.',
['Mã']='Mãrtrydóm:BAAANQABCgQIBAAAAA==.',
['Mì']='Mìssy:BAAANQADCggICgAAAA==.',
Na='Namiin:BAAANQADCgUIBQAAAA==.Naughtye:BAAANQAECgEIAQAAAA==.Nave:BAAANQAECgcICAAAAA==.',
Ne='Nelfsfault:BAAANQADCggJFwAAAA==.Nerotappo:BAAANQABCgIIAgAAAA==.',
Ni='Ninja:BAAANQADCgYJBgAAAA==.',
No='Nobacon:BAAANQADCgIIAgAAAA==.Noshaku:BAAANQAECgIIAgAAAA==.Notanorc:BAAANQAECgYJEwAAAA==.',
Od='Odium:BAAANQAECgIIAgAAAA==.',
Oh='Ohrolam:BAABNQAECoEYAAMSAAgKVwTywQB+AQASAAgK5wPywQB+AQAeAAEKBAaZMQA1AAAAAA==.',
Ot='Ottersdemons:BAAANQAECgIJAgAAAA==.',
Pa='Palthur:BAAANQADCgUIBQAAAA==.Paradoxis:BAAANQABCgIIAgAAAA==.Passionate:BAAANQADCgUIBQAAAA==.',
Ph='Phatmidas:BAAANQAECgQJBwAAAA==.Phrozenpally:BAAANQAECgEIAQABNQAECgQIBgABAAAAAA==.',
Pi='Pika:BAAANQADCgcIBwABNQAFFAEJAQABAAAAAA==.Pinkponythug:BAAANQAECgIJAgABNQAECgkJFQAZAFQZAA==.',
Pl='Plagueground:BAACNQAFFIEPAAQDAAYK/B/JAAD+AQADAAUKfyLJAAD+AQAUAAIKqwpjEwB1AAAEAAEKsA8tEABJAAA1AAQKgSgABAMACQoqJgQBANsDAAMACQoqJgQBANsDABQAAgr4HiFxAK0AAAQAAQrJBWyQADkAAAAA.',
Po='Poc:BAAANQAECgMJAwAAAA==.Pounces:BAABNQAECoEiAAIiAAkKSiTgAACzAwAiAAkKSiTgAACzAwAAAA==.',
Pr='Prózak:BAAANQADCgYIBgABNQAECgYJCwABAAAAAA==.Prôzak:BAAANQAECgYJCwAAAA==.',
Ps='Psychomidget:BAAANQADCgIJAgAAAA==.',
Pu='Puetrid:BAABNQAECoEZAAIHAAkKoRd5BADDAgAHAAkKoRd5BADDAgAAAA==.Purble:BAAANQADCgIIAgAAAA==.Puufrumslli:BAAANQAECgUJDgAAAA==.',
Ra='Rageinglight:BAAANQAECgIJAgAAAA==.Rakku:BAAANQABCgcJBgAAAA==.Rautha:BAABNQAECoEWAAITAAgKgxLAWgDwAQATAAgKgxLAWgDwAQAAAA==.',
Rh='Rhaegon:BAABNQAECoEYAAIjAAgKAhU9BgAiAgAjAAgKAhU9BgAiAgAAAA==.',
Ri='Rimath:BAAANQADCggJEAAAAA==.',
Rn='Rng:BAAANQADCggIFAAAAA==.',
Ro='Rodstewart:BAAANQAECggIEwAAAA==.Ronz:BAAANQABCgEJAQAAAA==.Rotdaddy:BAAANQAECgQJCAAAAA==.',
Sa='Sabatikus:BAAANQAECgEJAQAAAA==.Salino:BAAANQAECgQJBAAAAA==.Sam:BAAANQAECgUICgAAAA==.Sandorindis:BAAANQADCgEJAQAAAA==.Sarate:BAAANQADCggIEAAAAA==.Satral:BAAANQAECgUJBgAAAA==.Savannah:BAAANQAECgYIBwABNQAECgcIDwABAAAAAA==.Savvtwo:BAAANQADCgEIAQABNQAFFAUJDQACAMsiAQ==.',
Se='Sezra:BAAANQADCggICAAAAA==.',
Sh='Shaetahn:BAAANQAECgEIAQAAAA==.Shamwowthorn:BAAANQADCgEIAQAAAA==.Shinanigans:BAAANQAECggIEgAAAA==.Shockbull:BAAANQADCgcJBwAAAA==.',
Si='Silverbäck:BAAANQADCggIEwABNQADCggIFQABAAAAAA==.Silverslam:BAAANQADCgcJDwABNQADCggIFQABAAAAAA==.',
Sk='Skurge:BAAANQAECgIIAgAAAA==.',
So='Solstis:BAAANQAECgUICQAAAA==.Soranwena:BAAANQAECgUJEAAAAA==.',
Sp='Spacegoat:BAAANQAECgMIAwAAAA==.Spfzero:BAAANQADCgQIAwAAAA==.',
St='Sticksy:BAAANQADCgYIBgAAAA==.Stonebeard:BAAANQAECgQIBgAAAA==.Stârlèss:BAAANQADCgYJBwAAAA==.',
Su='Subtox:BAAANQAECgQIBgAAAA==.',
Sw='Swedishfish:BAAANQAECgEIAQABNQAECgkJGgAWAF8aAA==.',
['Sá']='Sálúd:BAAANQAECgcIEQAAAA==.',
Ta='Tarhealeon:BAAANQAECgUJCgAAAA==.Tarvuspls:BAAANQAECgIIAgAAAA==.',
Te='Temozo:BAAANQADCgIIAgAAAA==.',
Th='Thabigone:BAAANQADCgQICAAAAA==.Theceo:BAAANQADCgYIDgAAAA==.',
Ti='Tiewaz:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.',
To='Tolun:BAABNQAECoEYAAIeAAgKEBbQBQApAgAeAAgKEBbQBQApAgAAAA==.Tosan:BAAANQAECgIJBAAAAA==.Toughcookie:BAAANQAECgQJBAAAAA==.',
Tr='Treeplague:BAAANQAECgUICwAAAA==.',
Tu='Turn:BAACNQAFFIETAAQHAAUK0xd2AQAKAQAHAAMKTxN2AQAKAQAGAAIKhx1LAQC3AAAIAAIKWRFuGQCYAAA1AAQKgSUABAcACQr5IkILACMCAAcABwpPF0ILACMCAAYABQrnJCAFAAECAAgABQrPG5ZeAK0BAAAA.Turtleduck:BAAANQADCgUIBQABNQADCgcJEgABAAAAAA==.',
Ty='Tyla:BAAANQADCggIGwAAAA==.Typhis:BAAANQADCgYIBgAAAA==.',
['Tì']='Tìewaz:BAAANQAECgIIAgAAAA==.',
Um='Umbryx:BAAANQADCgYICwAAAA==.',
Un='Unagi:BAAANQAECgUICAAAAA==.',
Va='Valdir:BAAANQAECggIBgAAAA==.Vasomir:BAAANQABCgIIAQAAAA==.',
Ve='Venøm:BAAANQAECgEIAQAAAA==.',
Vi='Viscerion:BAAANQAECgQJBwAAAA==.',
Wh='Whoarlock:BAAANQADCgYICAAAAA==.',
Wi='Wizzyy:BAAANQADCgUIBQAAAA==.',
Wr='Wrathira:BAAANQADCgYIBgAAAA==.',
Xe='Xelinia:BAABNQAECoEcAAMWAAkKTRw/DQDNAgAWAAkKTRw/DQDNAgAaAAEK3wENtAAlAAAAAA==.Xen:BAAANQAECgcICAAAAA==.',
Xu='Xuefeng:BAABNQAECoEfAAIkAAkKjh1YCQD3AgAkAAkKjh1YCQD3AgAAAA==.',
Ya='Yahwae:BAAANQADCggICAABNQAECgYIDwABAAAAAA==.',
Yc='Ycephyre:BAAANQAECgIIAwAAAA==.',
Ye='Yenchmeister:BAACNQAFFIESAAIPAAYKdxZMBAD4AQAPAAYKdxZMBAD4AQA1AAQKgSQAAg8ACQrZJF8KAIcDAA8ACQrZJF8KAIcDAAAA.',
Zd='Zdervish:BAAANQAECgUIBQAAAA==.',
Ze='Zeffira:BAAANQAECgQIAwAAAA==.Zellda:BAAANQADCgYIBgAAAA==.',
Zi='Zilvanion:BAABNQAECoEXAAIIAAkKKRKiMQBYAgAIAAkKKRKiMQBYAgAAAA==.',
Zl='Zlathur:BAAANQADCgcIDgAAAA==.',
Zo='Zourknight:BAAANQADCgcJBwAAAA==.Zourlight:BAAANQADCgcIBwAAAA==.Zourlock:BAAANQADCgUJBgAAAA==.Zourvoid:BAAANQADCgUIBQAAAA==.',
['Ðr']='Ðrèamless:BAAANQAECgQICgAAAA==.',
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
