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

local lookup = {'Hunter-BeastMastery','DemonHunter-Devourer','DeathKnight-Frost','DeathKnight-Unholy','Shaman-Elemental','Shaman-Restoration','DeathKnight-Blood','Monk-Brewmaster','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Paladin-Holy','Unknown-Unknown','Druid-Restoration','Druid-Balance','DemonHunter-Havoc','Rogue-Assassination','Paladin-Protection','Monk-Mistweaver','Warrior-Arms','Rogue-Outlaw','Mage-Arcane','Warrior-Fury','Paladin-Retribution','Warrior-Protection','Priest-Shadow','Priest-Discipline','Evoker-Preservation','Priest-Holy','Mage-Fire','Druid-Guardian','Shaman-Enhancement','Mage-Frost','Evoker-Augmentation','Evoker-Devastation','Druid-Feral','Rogue-Subtlety','Hunter-Marksmanship','DemonHunter-Vengeance','Monk-Windwalker',}
local provider = {region='US',realm='Stonemaul',name='US',type='weekly',zone=53,date='2026-10-06',data={Ad='Addalar:BAAANQAECgUICAAAAA==.',
Ai='Airvis:BAAANQAECgYIDAAAAA==.',
Ak='Akar:BAAANQADCgMIAwAAAA==.',
Al='Alacia:BAAANQADCgQIBAABNQAECggIIAABAPcQAA==.',
Am='Amaira:BAAANQADCgQIBwAAAA==.Amalakar:BAAANQAECgEIAQAAAA==.Amnezea:BAAANQADCgIIAgAAAA==.',
An='Anankei:BAAANQADCgYIBgAAAA==.Anavere:BAAANQADCgUIBQAAAA==.Annasia:BAAANQAECgEIAQAAAA==.Antte:BAACNQAFFIEYAAICAAYKuRbcAwD5AQACAAYKuRbcAwD5AQA1AAQKgSQAAgIACQoKJGMHAFQDAAIACQoKJGMHAFQDAAAA.',
Ar='Arjun:BAAANQADCggIHgAAAA==.Armindru:BAAANQAECgUIBgAAAA==.',
As='Asmôdeô:BAAANQAECgUICwAAAA==.Astin:BAAANQAECgEIAQAAAA==.',
At='Atom:BAAANQAECgQIDQAAAA==.Atreyu:BAAANQAECgcIEgAAAA==.',
Aw='Awoozehl:BAACNQAFFIEcAAMDAAcKrSMdAADtAgADAAcKrSMdAADtAgAEAAEKaBweHgBDAAA1AAQKgSgAAwMACQqgJr8CAK4DAAMACQqgJr8CAK4DAAQACApEGcdSAJ8BAAAA.',
Az='Azgrodon:BAABNQAECoEfAAMFAAgKAhUJSwAeAgAFAAgKAhUJSwAeAgAGAAcK+gjgjwAyAQAAAA==.',
Ba='Banatok:BAAANQADCgIIAwAAAA==.Barzalie:BAAANQAECgEIAQABNQAFFAIIBQAHAK0NAA==.Bathrezz:BAAANQADCggIFQAAAA==.',
Be='Beandruid:BAAANQADCgEIAQAAAA==.Beanmage:BAAANQAECgUIBQAAAA==.Beanshaman:BAAANQADCgYIBgAAAA==.Bearlyawake:BAAANQADCgUIBQAAAA==.Beerbelly:BAABNQAECoEhAAIIAAkKdyF1AgByAwAIAAkKdyF1AgByAwABNQAFFAIIBQAHAK0NAA==.Beleaves:BAACNQAFFIEaAAIIAAYKcggxAwBnAQAIAAYKcggxAwBnAQA1AAQKgSgAAggACQpjFtUKAEYCAAgACQpjFtUKAEYCAAAA.Bellectra:BAAANQAECgUIBwAAAA==.',
Bi='Bifurious:BAAANQAECgYIDAAAAA==.',
Bl='Blathur:BAAANQADCgcICwAAAA==.Bluereindeer:BAABNQAECoEjAAIHAAgK4QyoUgCIAQAHAAgK4QyoUgCIAQAAAA==.',
Bo='Bobafina:BAAANQADCggICAAAAA==.Bobsstones:BAACNQAFFIETAAQJAAcKOxf6AABRAQAJAAQKzRP6AABRAQAKAAMKbhRGGQD1AAALAAIK+x3SCACtAAA1AAQKgSMABAsACQokJT8UAMUBAAoABQpwJCp1ANgBAAkABQr/IRgJAM0BAAsABQqhHz8UAMUBAAAA.Bobstofu:BAAANQAECgcIEwAAAA==.Bofaðeez:BAAANQADCgQIBAAAAA==.Bonkulo:BAABNQAECoEgAAIHAAgKMhLrRQDCAQAHAAgKMhLrRQDCAQAAAA==.Boofassist:BAACNQAFFIERAAIMAAUKgB9iBgDfAQAMAAUKgB9iBgDfAQA1AAQKgSgAAgwACQooJb8CAL4DAAwACQooJb8CAL4DAAAA.Boomsonic:BAAANQAECgQIBwABNQAECgYIDAANAAAAAA==.Boraga:BAAANQADCgYJBwAAAA==.',
Br='Brienyx:BAAANQADCgUIBwAAAA==.Briezani:BAAANQAECgQIBwAAAA==.Briogan:BAAANQAECgUICQAAAA==.Broccoliz:BAECNQAFFIEcAAIOAAcKmBOjAQBDAgAOAAcKmBOjAQBDAgA1AAQKgSwAAw4ACQq/GycRAKwCAA4ACQq/GycRAKwCAA8AAQpXFmKaAEEAAAAA.Brokan:BAAANQADCggIDgAAAA==.Broke:BAAANQAECgIIAgABNQAFFAYIGQAQAHQlAQ==.',
Bu='Bukhaki:BAAANQAECgcIBAABNQAECgcIGgARADgfAA==.',
['Bõ']='Bõb:BAAANQADCggICgAAAA==.',
Ca='Caden:BAAANQADCgYIBgABNQAECggIIAABAPcQAA==.Cafca:BAAANQAECgcIEAAAAA==.Caké:BAAANQADCgYIDAAAAA==.',
Ch='Chrams:BAABNQAECoEwAAIMAAkKrB+KEgArAwAMAAkKrB+KEgArAwAAAA==.',
Ci='Cialis:BAAANQADCgYIJgAAAA==.Cinnacrunch:BAAANQADCggIDQAAAA==.',
Cl='Clearlyumad:BAAANQAECgQIBwAAAA==.Clèrick:BAABNQAECoEwAAMMAAkKER6KPABVAgAMAAgK9h6KPABVAgASAAcKLQ5GLABPAQAAAA==.',
Co='Coldcrow:BAAANQADCgUICQAAAA==.Combination:BAABNQAECoEmAAITAAkKDyCWBQArAwATAAkKDyCWBQArAwAAAA==.Cowen:BAAANQADCggIEwAAAA==.',
Cr='Crash:BAAANQADCgUIBQABNQAFFAQIBgAUAIMIAA==.Cray:BAAANQADCgIIAgAAAA==.',
Cu='Cursedotter:BAAANQAECgUICwAAAA==.',
Da='Dabbyshatner:BAAANQAECgUIDAAAAA==.Daeneryis:BAAANQAECgMIAwAAAA==.Dankshammy:BAABNQAECoEcAAIGAAgKOx1gJAC1AgAGAAgKOx1gJAC1AgAAAA==.Darkwave:BAABNQAECoEgAAMLAAgKchJwOADVAAAKAAYKWA+3lgB9AQALAAMKeRNwOADVAAAAAA==.Darthdiddyus:BAACNQAFFIEOAAIVAAQK+RIxAQBNAQAVAAQK+RIxAQBNAQA1AAQKgSsAAhUACQrcISACADUDABUACQrcISACADUDAAAA.Dathunter:BAAANQAECgIIAgABNQAECgkJIAAWAJ4TAA==.Dawghawg:BAAANQADCgQIBAAAAA==.Dawnnie:BAABNQAECoEsAAISAAkKPhrADQCbAgASAAkKPhrADQCbAgAAAA==.Dawsonrogers:BAABNQAECoEaAAMXAAgKNBeSCAAvAgAXAAgK7BaSCAAvAgAUAAIKehOFDwGCAAAAAA==.',
De='Deathbanana:BAAANQADCggICAABNQAFFAcIFAAWAPYdAA==.Deathbydk:BAABNQAFFIEFAAIHAAIKrQ0rHgB3AAAHAAIKrQ0rHgB3AAAAAA==.Delema:BAACNQAFFIELAAIYAAUKtQw9CgB3AQAYAAUKtQw9CgB3AQA1AAQKgSEAAxgACQoHHw9QAH0CABgACQoHHw9QAH0CABIAAQruAWRxAB0AAAAA.Derbina:BAAANQABCgIIBAAAAA==.Destructer:BAAANQAECgEIAQAAAA==.',
Di='Dirtydinker:BAAANQAECgcICQAAAA==.Dixsard:BAABNQAECoEaAAIRAAcKOB/LHQBnAgARAAcKOB/LHQBnAgAAAA==.',
Do='Dontblink:BAAANQAECgEIAQABNQAECgkJJgATAA8gAA==.Dorin:BAAANQABCgQIBAAAAA==.Dotore:BAAANQADCgYIBgAAAA==.Dottyflu:BAACNQAFFIEPAAIHAAUKzxakCwBtAQAHAAUKzxakCwBtAQA1AAQKgSQAAgcACQq1IFUQABcDAAcACQq1IFUQABcDAAAA.Dottylawful:BAABNQAFFIEHAAISAAUKbQWiBQALAQASAAUKbQWiBQALAQABNQAFFAUIDwAHAM8WAA==.',
Dr='Drexbear:BAAANQAECgQJBAABNQAFFAUIDwAZAEYQAA==.Drexl:BAACNQAFFIEPAAIZAAUKRhAgAgBRAQAZAAUKRhAgAgBRAQA1AAQKgSAAAxQACQrGEPmUAL8BABQACQp2CPmUAL8BABkAAwqsH/kiAAIBAAAA.',
Dw='Dweams:BAACNQAFFIEbAAIaAAYKSBv/AgAXAgAaAAYKSBv/AgAXAgA1AAQKgSMAAxoACQr0IyoKACoDABoACQr0IyoKACoDABsABgoxGloLAHUBAAAA.Dweamu:BAAANQADCgMIAwABNQAFFAYIGwAaAEgbAA==.',
Ec='Ectonight:BAAANQADCgIIAgAAAA==.',
Eg='Eggfooyung:BAAANQAECggICwABNQAFFAUIEQAMAIAfAA==.Egwene:BAAANQAECgEIAQAAAA==.',
El='Elhonna:BAABNQAECoErAAIBAAkKyB78JwDZAgABAAkKyB78JwDZAgAAAA==.',
En='Endcredits:BAAANQAECgUICgAAAA==.',
Er='Eridyn:BAAANQAECgMIAwAAAA==.',
Ev='Evoulker:BAACNQAFFIEhAAIcAAcK4xw9AgBnAgAcAAcK4xw9AgBnAgA1AAQKgSgAAhwACQrWH2AKAO4CABwACQrWH2AKAO4CAAAA.',
Ez='Ezekielle:BAAANQAECgEIAQAAAA==.',
Fa='Faire:BAAANQADCgIIAgABNQAECgcIDwANAAAAAA==.Fairytale:BAACNQAFFIEcAAIdAAYKNxJXCADkAQAdAAYKNxJXCADkAQA1AAQKgSgAAx0ACQqEIf0cAOUCAB0ACQpxIP0cAOUCABsABwrkHKkFACwCAAAA.Faker:BAAANQADCggIDwAAAA==.',
Fe='Felheim:BAABNQAECoE0AAICAAkKzx8bBgBpAwACAAkKzx8bBgBpAwAAAA==.Fellithà:BAAANQADCgUIBgAAAA==.',
Fi='Fists:BAAANQADCgYJDAABNQAECgkJGwAcAPoZAA==.',
Fl='Flink:BAAANQADCgIJAgAAAA==.Floogi:BAAANQADCgMIAwAAAA==.',
Fo='Foxygal:BAAANQADCggIEwAAAA==.',
Fr='Frostyninja:BAAANQAECgIIAgAAAA==.',
Ga='Garchomp:BAAANQADCgQICAAAAA==.Gawain:BAAANQAECgUIBQABNQAECggIJgABAFcaAA==.',
Ge='Gellina:BAAANQADCgUICAAAAA==.Georg:BAACNQAFFIEYAAIYAAcKqhsDAQCcAgAYAAcKqhsDAQCcAgA1AAQKgSAAAhgACQpxJeESAGsDABgACQpxJeESAGsDAAAA.Geriatric:BAAANQAECgIIAwABNQAFFAcIHAADAK0jAA==.',
Gl='Glathur:BAAANQADCgIIBAAAAA==.Glizzygagger:BAABNQAECoEeAAIaAAkK1CJvCQA1AwAaAAkK1CJvCQA1AwABNQAFFAQIBQAVAHMWAA==.Glizzygorger:BAABNQAECoEVAAICAAcKEx2rHQBIAgACAAcKEx2rHQBIAgABNQAFFAQIBQAVAHMWAA==.',
Go='Goodbye:BAABNQAECoEcAAMWAAgKkh3zfABsAgAWAAgKkh3zfABsAgAeAAEKvQkzDAAzAAAAAA==.Goregazme:BAAANQADCgUIBQAAAA==.',
Gr='Grantoro:BAABNQAECoEeAAIfAAcK1w/AHQBsAQAfAAcK1w/AHQBsAQAAAA==.Grimmblades:BAAANQAECgIIAgAAAA==.Grootbeer:BAAANQAECgUIDQAAAA==.',
Gu='Gulgrimmar:BAACNQAFFIEbAAMFAAcKhBtbBgDpAQAFAAUKZh1bBgDpAQAGAAMKQx+wEAARAQA1AAQKgSMAAwUACQrSJUMFALgDAAUACQrSJUMFALgDAAYABQqMG79sAJYBAAAA.Guwudanielle:BAAANQAECgcIDwAAAA==.',
['Gä']='Gävinräd:BAAANQABCgQIBQAAAA==.',
Ha='Haranguetan:BAAANQADCgYIBgABNQAECggIJQAgAFcNAA==.Hardfeelings:BAAANQAECgUICgAAAA==.Harrharr:BAAANQADCgMIAwAAAA==.',
He='Headache:BAAANQABCgIIAgABNQAECgYIDAANAAAAAA==.Hexappeal:BAAANQADCgMIAwAAAA==.',
Ho='Hodann:BAAANQABCgYJBgAAAA==.',
Hu='Hurjek:BAABNQAECoEXAAIOAAkKvCHKAwB7AwAOAAkKvCHKAwB7AwABNQAECgkJJgATAA8gAA==.',
Ic='Iconicmax:BAAANQAECgQICwAAAA==.',
Ij='Ijustankedu:BAAANQADCgEIAQAAAA==.',
Il='Ilyana:BAABNQAECoEnAAMWAAkKBCEcXwCuAgAWAAgK+x8cXwCuAgAhAAIKKCIvJACrAAAAAA==.',
In='Insights:BAAANQAECgUICgAAAA==.',
Is='Ishtann:BAAANQABCgIIAgAAAA==.',
Ja='Jaqen:BAACNQAFFIEFAAIVAAQKcxYbAQBjAQAVAAQKcxYbAQBjAQA1AAQKgR0AAxUACAo8IsICAAwDABUACAo8IsICAAwDABEAAQrhDfOGADsAAAAA.Jayc:BAABNQAECoEfAAIWAAkKWx4tNAAWAwAWAAkKWx4tNAAWAwAAAA==.',
Je='Jereico:BAACNQAFFIEbAAMiAAcKfyG2AAC2AgAiAAcKfyG2AAC2AgAjAAEKqxpQDQBLAAA1AAQKgSgAAyIACQr/JaEAALkDACIACQr/JaEAALkDACMACAoEFdwWALwBAAAA.Jeryhn:BAACNQAFFIEcAAIMAAUKrBvzBwC7AQAMAAUKrBvzBwC7AQA1AAQKgSgAAgwACQrNImoLAF8DAAwACQrNImoLAF8DAAAA.',
Jo='Joeynodz:BAAANQAECgEIAQAAAA==.Jortshorts:BAABNQAECoEcAAIkAAgKUgegFgBXAQAkAAgKUgegFgBXAQAAAA==.',
Ju='Juggalo:BAACNQAFFIEMAAIjAAUKFBbjAwCPAQAjAAUKFBbjAwCPAQA1AAQKgTMAAyMACQpFI2oDAGIDACMACQpFI2oDAGIDACIAAgoKDaQaAG4AAAAA.June:BAACNQAFFIEaAAITAAcK8xFQAQA7AgATAAcK8xFQAQA7AgA1AAQKgSkAAhMACQqLIPcHAPYCABMACQqLIPcHAPYCAAAA.',
Ka='Kalikin:BAAANQAECgMJBAAAAA==.Kawasuoo:BAAANQADCgQIBAABNQAECgUICwANAAAAAA==.',
Kc='Kcudüm:BAABNQAECoEiAAQLAAgKXRGxDwD3AQALAAgKbxCxDwD3AQAKAAMKtAYZAwGIAAAJAAEKGA/OKQA6AAAAAA==.',
Ke='Keifis:BAAANQADCgEJAQAAAA==.Keifism:BAAANQABCgMIAwAAAA==.',
Kh='Khaotichic:BAAANQAECgEIAQAAAA==.',
Kl='Klrum:BAABNQAECoEkAAMhAAgK+BgbGgD7AAAWAAcKmRmlnwAiAgAhAAUK7A4bGgD7AAAAAA==.',
Ko='Koddin:BAABNQAECoEjAAIYAAgK1hsnUAB8AgAYAAgK1hsnUAB8AgAAAA==.Komui:BAABNQAECoEjAAMGAAgKJxaIWADZAQAGAAgKJxaIWADZAQAFAAYKiQ+ihABoAQAAAA==.Koonlei:BAAANQAECgQIBAAAAA==.Koreth:BAACNQAFFIEcAAMRAAcKTRdYAQBzAgARAAcKTRdYAQBzAgAlAAEK9w79EgBIAAA1AAQKgSkAAxEACQo8I6IHAEUDABEACQo8I6IHAEUDACUACApsGJIWABsCAAAA.Kornholyo:BAAANQAECgIIAwAAAA==.',
Kr='Krakheeta:BAAANQADCgQIBAAAAA==.Krusade:BAAANQAECgUICQAAAA==.',
Ku='Kumo:BAAANQAECgEIAQAAAA==.Kutuzov:BAAANQADCggIIwAAAA==.',
Kw='Kwenny:BAAANQAECgEIAQAAAA==.',
La='Lailaysia:BAAANQADCggICwAAAA==.Lamemoosaur:BAABNQAECoEYAAIfAAkKoR1LBgAAAwAfAAkKoR1LBgAAAwAAAA==.Laríca:BAABNQAECoEsAAIMAAkKASMQBgCRAwAMAAkKASMQBgCRAwAAAA==.Laydout:BAAANQADCgQIBAABNQAECgYIEAANAAAAAA==.Laydoutyota:BAAANQAECgYIEAAAAA==.Laymow:BAAANQAECgQJBAABNQAECgkJGAAfAKEdAA==.',
Le='Levity:BAAANQAECggIBQAAAA==.',
Li='Lilea:BAABNQAECoEgAAMBAAgK9xDTlACsAQABAAYK6hHTlACsAQAmAAYKpwgNQQAaAQAAAA==.Lilfaart:BAAANQAECggIBAAAAA==.Lindisalvia:BAAANQADCgIIAgAAAA==.Lionsmane:BAAANQADCgYIBgAAAA==.',
Lo='Loosemorals:BAABNQAECoEbAAIcAAkK+hmRDgCtAgAcAAkK+hmRDgCtAgAAAA==.Lootgoblin:BAABNQAECoEgAAIWAAkKnhPCiQBRAgAWAAkKnhPCiQBRAgAAAA==.Lortherian:BAAANQAECgQICAAAAA==.',
['Lä']='Läwlbringer:BAAANQAECgcIEAAAAA==.',
Ma='Mabritoe:BAACNQAFFIEHAAIRAAQKZyEFBwBoAQARAAQKZyEFBwBoAQA1AAQKgSEAAxEACQoqIpkKAB0DABEACAqiJJkKAB0DACUACApyCxMfAMIBAAE1AAUUBwgXAA8AFxYA.Magicstick:BAAANQABCgQIBAAAAA==.Magooh:BAAANQADCgcIBwABNQAECgQICQANAAAAAA==.Malison:BAAANQADCgUIBAAAAA==.Mangle:BAAANQADCgUIBQAAAA==.Mania:BAAANQADCgYICgABNQAECgYIDAANAAAAAA==.Mareth:BAAANQADCgIIAgAAAA==.Mathath:BAABNQAECoEZAAMEAAgKmRxNOgAUAgAEAAgKSRlNOgAUAgAHAAMKcyEbcQALAQAAAA==.Mathoras:BAAANQADCgYIBgAAAA==.Maxboom:BAAANQADCggIHQAAAA==.Mayaho:BAAANQAECgQICQAAAA==.Maylee:BAAANQAECgQIBAAAAA==.',
Me='Meandean:BAAANQAECgUIBQAAAA==.Meatier:BAAANQAECgEIAQABNQAECgYIDAANAAAAAA==.Mellinia:BAAANQADCgEIAQAAAA==.Meoverdahill:BAAANQABCgIIAgAAAA==.',
Mi='Miltonroe:BAABNQAECoElAAIgAAgKVw1eEwANAgAgAAgKVw1eEwANAgAAAA==.Miltonroé:BAAANQAECgQIBAABNQAECggIJQAgAFcNAA==.Mixing:BAAANQADCgIJAgAAAA==.',
Mo='Monnz:BAAANQADCgUIBQAAAA==.Monsterskill:BAAANQAECgEIAQAAAA==.Moonerva:BAAANQAECgUICgAAAA==.Morana:BAAANQAECgMIAwAAAA==.',
Mu='Munchinmuff:BAAANQAECgQIBAAAAA==.',
Mv='Mvqchx:BAAANQADCgEIAQAAAA==.',
My='Myrolous:BAAANQADCgQIBAAAAA==.',
['Mã']='Mãrtrydóm:BAAANQABCgQIBAAAAA==.',
['Mì']='Mìssy:BAAANQAECgEIAQAAAA==.',
Na='Namiin:BAAANQADCgUIBQAAAA==.Natara:BAAANQADCgYIBgAAAA==.Naughtye:BAAANQAECgEIAQAAAA==.Nave:BAAANQAECgcICAAAAA==.',
Ne='Nelfsfault:BAAANQADCggJFwAAAA==.Nerotappo:BAAANQABCgIIAgAAAA==.',
Ni='Ninja:BAAANQADCgYJBgAAAA==.',
No='Nobacon:BAAANQADCgIIAgAAAA==.Noshaku:BAAANQAECgIIAwAAAA==.Notanorc:BAABNQAECoEcAAMUAAgKOg3nkQDIAQAUAAgK5AznkQDIAQAXAAUKzQvdFwD+AAAAAA==.',
Od='Odium:BAAANQAECgIIAgAAAA==.',
Oh='Ohrolam:BAABNQAECoElAAMWAAgKpwZV6QCRAQAWAAgKRwZV6QCRAQAhAAEKBAb2QgAwAAAAAA==.',
Ok='Okasan:BAAANQAECgQICAABNQAECgQICgANAAAAAA==.',
Ot='Ottersdemons:BAAANQAECgIIAgAAAA==.',
Pa='Palthur:BAAANQAECgEIAQAAAA==.Paradoxis:BAAANQABCgIIBAAAAA==.Passionate:BAAANQADCgUIBQAAAA==.',
Ph='Phatmidas:BAAANQAECgYIEgAAAA==.Phrozenpally:BAAANQAECgIIAwABNQAECgQICQANAAAAAA==.',
Pi='Pika:BAAANQADCgcIBwABNQAFFAIIBQAHAK0NAA==.Pinkponythug:BAAANQAECgQIBQABNQAECgkJGwAcAPoZAA==.',
Pl='Plagueground:BAACNQAFFIEaAAQDAAcKtyHIAABfAgADAAYK2iPIAABfAgAHAAIKaAvWHwBsAAAEAAEKsA/iHwA7AAA1AAQKgSwABAMACQo5JogCALIDAAMACQo5JogCALIDAAcAAgr4HniPAKUAAAQAAQrJBQDRAC8AAAAA.',
Po='Poc:BAAANQAECgMIBQAAAA==.Porterhaus:BAAANQADCggICAABNQAECgkJIgALAKIYAA==.Pounces:BAABNQAECoEuAAIkAAkKRyUcAQDCAwAkAAkKRyUcAQDCAwAAAA==.',
Pr='Prózak:BAAANQADCgYIBgABNQAECggIGgASABYUAA==.Prôzak:BAABNQAECoEaAAISAAgKFhTNGwDkAQASAAgKFhTNGwDkAQAAAA==.',
Ps='Psychomidget:BAAANQAECgEIAgAAAA==.',
Pu='Puetrid:BAABNQAECoEiAAILAAkKohhVBQC7AgALAAkKohhVBQC7AgAAAA==.Purble:BAAANQADCgIIAgAAAA==.Puufrumslli:BAAANQAECgYIEAAAAA==.',
Ra='Rageinglight:BAAANQAECgMIBQAAAA==.Rakku:BAAANQABCgcJBgAAAA==.Rautha:BAABNQAECoEcAAIYAAgKAxPIigDdAQAYAAgKAxPIigDdAQAAAA==.Rayl:BAAANQAECgEIAQAAAA==.',
Rh='Rhaegon:BAABNQAECoEoAAInAAkK1hl5BQCuAgAnAAkK1hl5BQCuAgAAAA==.',
Ri='Rimath:BAAANQADCggIEAAAAA==.',
Rn='Rng:BAAANQADCggIFAAAAA==.',
Ro='Rodstewart:BAAANQAECggIEwAAAA==.Ronz:BAAANQABCgEJAQAAAA==.Roofeo:BAAANQAECgEIAQABNQAECggIIAAHADISAA==.Rotdaddy:BAAANQAECgYIEwAAAA==.',
Sa='Sabatikus:BAAANQAECgEJAQAAAA==.Salino:BAAANQAECgYICwAAAA==.Sam:BAAANQAECgcIEQAAAA==.Sandorindis:BAAANQADCgYIBwAAAA==.Sarate:BAAANQADCggIEAAAAA==.Satral:BAAANQAECgUIBgAAAA==.Savannah:BAAANQAECgYIBwABNQAECgcIDwANAAAAAA==.Savvtwo:BAAANQADCgEIAQABNQAFFAYIGQAQAHQlAQ==.',
Se='Sezra:BAAANQADCggICAAAAA==.',
Sh='Shaetahn:BAAANQAECgEIAQAAAA==.Shamwowthorn:BAAANQADCgEIAQAAAA==.Shinanigans:BAABNQAECoEgAAIYAAkK9BxJMADpAgAYAAkK9BxJMADpAgAAAA==.Shockbull:BAAANQADCgcJBwAAAA==.',
Si='Silverbäck:BAAANQAECgUIBwABNQADCggIHgANAAAAAA==.Silverslam:BAAANQADCggIFwABNQADCggIHgANAAAAAA==.',
Sk='Skurge:BAAANQAECgQICAAAAA==.',
Sn='Snacks:BAAANQADCgEIAQABNQAECgcIEQANAAAAAA==.',
So='Solstis:BAAANQAECgUICQAAAA==.Soranwena:BAABNQAECoEZAAIfAAgK/Be9EAAUAgAfAAgK/Be9EAAUAgAAAA==.Sorros:BAAANQAECgQIBQAAAA==.',
Sp='Spacegoat:BAAANQAECgMIAwAAAA==.Spfzero:BAAANQADCggICgAAAA==.',
St='Sticksy:BAAANQADCgYIBgAAAA==.Stonebeard:BAAANQAECgQIBgAAAA==.Stârlèss:BAAANQADCgYIBwAAAA==.',
Su='Subtox:BAAANQAECgUIBwAAAA==.',
Sw='Swedishfish:BAAANQAECgEIAQABNQAECgkJHQAaACMdAA==.',
['Sá']='Sálúd:BAAANQAECgcIEQAAAA==.',
Ta='Tarhealeon:BAAANQAECgYIDgAAAA==.Tarvuspls:BAAANQAECgYIDQAAAA==.',
Te='Teemawthy:BAAANQADCgMIAwAAAA==.Temozo:BAAANQADCgIIAgAAAA==.',
Th='Thabigone:BAAANQADCgQICAAAAA==.Theceo:BAAANQADCgYIDgAAAA==.Thorb:BAAANQAECgcIBwABNQAFFAIIBQAHAK0NAA==.',
Ti='Ticklemebutt:BAAANQAECgUIDQAAAA==.Tiewaz:BAAANQADCgUIBQABNQAECgQIBgANAAAAAA==.',
To='Tolun:BAABNQAECoEcAAIhAAkK/RTZCAAeAgAhAAkK/RTZCAAeAgAAAA==.Tosan:BAAANQAECgQICgAAAA==.Toughcookie:BAAANQAECgUIDgAAAA==.',
Tr='Treeplague:BAAANQAECgYIEgAAAA==.',
Tu='Turn:BAACNQAFFIEeAAQLAAcKtRQbAgD8AAAJAAMKpBWWAQAEAQALAAMK7RMbAgD8AAAKAAMKmhHvGQDxAAA1AAQKgScABAsACQr5Io0OAAYCAAsABwpPF40OAAYCAAkABQrnJFMIAOQBAAoABgquH+aNAJUBAAAA.Turtleduck:BAAANQADCgUIBQABNQAECgUIBgANAAAAAA==.',
Ty='Tyla:BAAANQADCggIGwAAAA==.Typhis:BAAANQAECgEIAQAAAA==.',
['Tì']='Tìewaz:BAAANQAECgQIBgAAAA==.',
Um='Umbryx:BAAANQAECgEIAQAAAA==.',
Un='Unagi:BAAANQAECgYIEwAAAA==.',
Va='Valdir:BAAANQAECggIBgAAAA==.Vasomir:BAAANQABCgIIAQAAAA==.',
Ve='Venomstrikes:BAAANQADCgcIBwAAAA==.Venøm:BAAANQAECgEIAQAAAA==.',
Vi='Viscerion:BAAANQAECgYIEAAAAA==.',
Wh='Whoarlock:BAAANQADCgYICAAAAA==.',
Wi='Wizzyy:BAAANQADCgUIBQAAAA==.',
Xe='Xelinia:BAACNQAFFIEMAAMaAAUKgQl0CgATAQAaAAQK4wp0CgATAQAdAAEK8AFzMQA8AAA1AAQKgSEAAxoACQqEHQUVAJcCABoACQqEHQUVAJcCAB0AAQrfAbXsACMAAAAA.Xen:BAEANQAECggICwAAAA==.',
Xu='Xuefeng:BAACNQAFFIEGAAIoAAMKWAyMCgDMAAAoAAMKWAyMCgDMAAA1AAQKgS8AAigACQrdH2wJACUDACgACQrdH2wJACUDAAAA.',
Ya='Yahwae:BAAANQAECgQIBAABNQAECggIIAALAHISAA==.',
Yc='Ycephyre:BAAANQAECgQIBQAAAA==.',
Ye='Yenchmeister:BAACNQAFFIEZAAIUAAcKJxmdBABiAgAUAAcKJxmdBABiAgA1AAQKgSgAAhQACQr9JKQUAF4DABQACQr9JKQUAF4DAAAA.',
Yo='Yomahma:BAAANQAECgUIBgAAAA==.',
Zd='Zdervish:BAAANQAECgcIEgAAAA==.',
Ze='Zeffira:BAAANQAECgQIAwAAAA==.Zellda:BAAANQADCgYIBgAAAA==.',
Zi='Zilvanic:BAAANQAECgUIBQAAAA==.Zilvanion:BAABNQAECoEkAAIKAAkKehTUSwBRAgAKAAkKehTUSwBRAgAAAA==.',
Zl='Zlathur:BAAANQADCgcIDgAAAA==.',
Zo='Zourbeast:BAAANQADCgQIBAAAAA==.Zourknight:BAAANQADCgcICAAAAA==.Zourlight:BAAANQADCgcIDgAAAA==.Zourlock:BAAANQADCggIDwAAAA==.Zourvoid:BAAANQADCgYICQAAAA==.',
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
