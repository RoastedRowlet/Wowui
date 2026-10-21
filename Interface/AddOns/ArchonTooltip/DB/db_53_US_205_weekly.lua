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

local lookup = {'Mage-Frost','Mage-Arcane','Unknown-Unknown','Hunter-Marksmanship','DemonHunter-Devourer','DeathKnight-Blood','Hunter-BeastMastery','Warrior-Arms','DeathKnight-Frost','DeathKnight-Unholy','Shaman-Elemental','Shaman-Restoration','Evoker-Preservation','Monk-Brewmaster','Warrior-Fury','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Paladin-Holy','Druid-Restoration','Druid-Balance','DemonHunter-Havoc','Rogue-Assassination','Paladin-Protection','Monk-Mistweaver','Rogue-Outlaw','Paladin-Retribution','Rogue-Subtlety','Warrior-Protection','Priest-Shadow','Priest-Discipline','Priest-Holy','Mage-Fire','Druid-Guardian','Shaman-Enhancement','Evoker-Augmentation','Evoker-Devastation','Druid-Feral','DemonHunter-Vengeance','Monk-Windwalker',}
local provider = {region='US',realm='Stonemaul',name='US',type='weekly',zone=53,date='2026-10-20',data={Ad='Addalar:BAAANQAECgcICgAAAA==.',
Ai='Airvis:BAABNQAECn8WAAMBAAgKPRIADAD8AQABAAgKPRIADAD8AQACAAMKxQYGngGJAAAAAA==.',
Ak='Akamie:BAAANQAECgIIAQABNQAECgcIDwADAAAAAA==.Akar:BAAANQADCgMIAwAAAA==.',
Al='Alacia:BAAANQADCgQIBAABNQAECgoKLAAEAB8RAA==.Albinomonk:BAAANQADCgMIAwAAAA==.',
Am='Amaira:BAAANQAECgEIAQAAAA==.Amalakar:BAAANQAECgEIAQAAAA==.Amnezea:BAAANQADCgIIAgAAAA==.',
An='Anankei:BAAANQADCgYIBgAAAA==.Anavere:BAAANQADCgUIBQAAAA==.Annasia:BAAANQAECgEIAQAAAA==.Antte:BAACNQAFFH8YAAIFAAYKRxWtBQDSAQAFAAYKRxWtBQDSAQA1AAQKfyQAAgUACQquIwYLACwDAAUACQquIwYLACwDAAAA.',
Ar='Arjun:BAAANQADCggIHgAAAA==.Armindru:BAAANQAECgYIEAAAAA==.Armingothele:BAAANQAECgEIAQABNQAECgYIEAADAAAAAA==.Arturogh:BAAANQADCggICAABNQAECgkJLAAGAP0SAA==.',
As='Asmôdeô:BAAANQAECgYIDAAAAA==.Astin:BAAANQAECgEIAQAAAA==.',
At='Atom:BAABNQAECn8ZAAIHAAgK8gyYhgD+AQAHAAgK8gyYhgD+AQAAAA==.Atreyu:BAABNQAECn8gAAIIAAcKsQtbRAAZAQAIAAcKsQtbRAAZAQAAAA==.',
Aw='Awoozehl:BAACNQAFFH8cAAMJAAcKbCNvAADLAgAJAAcKbCNvAADLAgAKAAEKaBxbIgBDAAA1AAQKfy4AAwkACgoTJUYFAIwDAAkACgoTJUYFAIwDAAoACAoiG31cAJ4BAAAA.',
Az='Azgrodon:BAABNQAECn8rAAMLAAoK8BdtTQBBAgALAAoK8BdtTQBBAgAMAAgKEgoLjABrAQAAAA==.',
Ba='Banatok:BAAANQADCgIIAwAAAA==.Bangungot:BAAANQAECgEIAQABNQAFFAgIFgANABEVAA==.Barnabus:BAAANQAECgMIAwAAAA==.Barristan:BAAANQADCgIIAgAAAA==.Barzalie:BAAANQAECgEIAQABNQAFFAMICwAGAKoTAA==.Bathrezz:BAAANQAECgQICQAAAA==.',
Be='Beandruid:BAAANQAECgEIAQAAAA==.Beanmage:BAAANQAECgUIBQAAAA==.Beanshaman:BAAANQADCgYIBgAAAA==.Bearlyawake:BAAANQADCgUIBQAAAA==.Beerbelly:BAABNQAECn8sAAIOAAoKUCABAQAwAgAOAAoKUCABAQAwAgABNQAFFAMICwAGAKoTAA==.Beleaves:BAACNQAFFH8aAAIOAAYK9ggiBABkAQAOAAYK9ggiBABkAQA1AAQKfyoAAg4ACQqqFHwMADsCAA4ACQqqFHwMADsCAAAA.Bellectra:BAAANQAECgUIEAAAAA==.',
Bi='Bifurious:BAABNQAECn8UAAIPAAgKchjQCgAZAgAPAAgKchjQCgAZAgAAAA==.',
Bl='Blathur:BAAANQADCgcIDQAAAA==.Bluereindeer:BAABNQAECn80AAIGAAoKyRDVCACsAQAGAAoKyRDVCACsAQAAAA==.',
Bo='Bobafina:BAAANQADCggICAAAAA==.Bobsstones:BAACNQAFFH8WAAQQAAgKQhlgAQBLAQAQAAUKxRRgAQBLAQARAAMKKxdjIQDsAAASAAIK+x3wCgCjAAA1AAQKfygABBIACgq7JQ8WALwBABEABgrNJLiMAMcBABAABQrwIdcKAMUBABIABQqhHw8WALwBAAAA.Bobstofu:BAAANQAECgcIEwAAAA==.Bofaðeez:BAAANQADCgQIBAAAAA==.Bombtimer:BAAANQADCgIIAwABNQADCgUICQADAAAAAA==.Bonkulo:BAABNQAECn8sAAQGAAkK/RIvRgDhAQAGAAkK/RIvRgDhAQAJAAMKCwl6PgCqAAAKAAQKZQUDMwCQAAAAAA==.Boofassist:BAACNQAFFH8WAAITAAcKOR7qAwBOAgATAAcKOR7qAwBOAgA1AAQKfywAAhMACgpAI8cDALYDABMACgpAI8cDALYDAAAA.Boomsonic:BAAANQAECgQIBwABNQAECggIFAAPAHIYAA==.Boraga:BAAANQADCgYJBwAAAA==.',
Br='Brienyx:BAAANQADCgUIBwAAAA==.Brietemis:BAAANQAECgQIBAAAAA==.Briezani:BAAANQAECgYIDQAAAA==.Briogan:BAAANQAECgUICQAAAA==.Broccoliz:BAECNQAFFH8cAAIUAAcKmBPbAgApAgAUAAcKmBPbAgApAgA1AAQKfzIAAxQACgq+GXgVAJoCABQACgq+GXgVAJoCABUAAQpXFsmqAEEAAAAA.Brokan:BAAANQAECgYIBgAAAA==.Broke:BAAANQAECgIIAgABNQAFFAcIIAAWANckAQ==.',
Bu='Bukhaki:BAAANQAECggIDAABNQAECgkJIgAXACwbAA==.',
['Bõ']='Bõb:BAAANQAECgEIAQAAAA==.',
Ca='Caden:BAAANQADCgYIBgABNQAECgoKLAAEAB8RAA==.Cafca:BAABNQAECn8iAAIQAAkKnw9MAgBoAQAQAAkKnw9MAgBoAQAAAA==.Caké:BAAANQADCgYIDAAAAA==.Caldrr:BAAANQAECgEIAQAAAA==.Caylva:BAAANQAECgcIBwABNQAFFAMICwAGAKoTAA==.',
Ch='Chrams:BAABNQAECn8/AAITAAoKdh4OFwAgAwATAAoKdh4OFwAgAwAAAA==.',
Ci='Cialis:BAAANQADCgYIJgAAAA==.Cinnacrunch:BAAANQADCggIDgAAAA==.',
Cl='Clearlyumad:BAAANQAECgQIBwAAAA==.Clèrick:BAABNQAECn89AAMTAAoKtSFSIwDeAgATAAkKhiJSIwDeAgAYAAcKhw1qFgDWAAAAAA==.',
Co='Coldcrow:BAAANQADCgUICQAAAA==.Combination:BAABNQAECn8vAAIZAAoKiCA5AQDnAgAZAAoKiCA5AQDnAgABNQAECgoKKQAUANEiAA==.Cowen:BAAANQADCggIEwAAAA==.',
Cr='Crash:BAAANQADCgUIBQABNQAFFAQIDAADAAAAAA==.Cray:BAAANQADCgIIAgAAAA==.',
Cu='Cursedotter:BAAANQAECgcIDwAAAA==.',
Da='Dabbyshatner:BAAANQAECgYIDQAAAA==.Daeneryis:BAAANQAECgMIAwAAAA==.Dankshammy:BAABNQAECn8qAAIMAAoKChroIQDgAgAMAAoKChroIQDgAgAAAA==.Darkwave:BAABNQAECn8tAAMRAAoKgxNQQAANAQARAAgKxBBQQAANAQASAAMKeRNXCQCJAAAAAA==.Darthdiddyus:BAACNQAFFH8PAAIaAAQKaBdyAQBCAQAaAAQKaBdyAQBCAQA1AAQKfysAAhoACQpUIbkCACMDABoACQpUIbkCACMDAAAA.Dathunter:BAAANQAECgIIAgABNQAECgkJKgACADwZAA==.Datshammy:BAAANQAECgEIAQABNQAECgkJKgACADwZAA==.Dawghawg:BAAANQADCgUIBgAAAA==.Dawnnie:BAACNQAFFH8FAAIYAAIKQQ56BACJAAAYAAIKQQ56BACJAAA1AAQKfzQAAhgACgrcGzkOALcCABgACgrcGzkOALcCAAAA.Dawsonrogers:BAABNQAECn8dAAMPAAkKhxSnCgAeAgAPAAgKMRenCgAeAgAIAAMKvg0cKQGEAAAAAA==.',
De='Deathbanana:BAAANQADCggICAABNQAFFAgIFwACAIgdAA==.Deathbydk:BAACNQAFFH8LAAIGAAMKqhM9HgCcAAAGAAMKqhM9HgCcAAA1AAQKfyUAAgYACgqYIKoMAE0DAAYACgqYIKoMAE0DAAAA.Delema:BAACNQAFFH8PAAIbAAYKRg3QCAC9AQAbAAYKRg3QCAC9AQA1AAQKfyUAAxsACgo2HoVfAHoCABsACgo2HoVfAHoCABgAAQoAAD2AABwAAAAA.Derbina:BAAANQABCgIIBAAAAA==.Destructer:BAAANQAECgMIBgAAAA==.',
Di='Dirtydinker:BAAANQAECgcICQAAAA==.Dixsard:BAABNQAECn8iAAMXAAkKLBvDGQCvAgAXAAkKLBvDGQCvAgAcAAIKzwL2VgAiAAAAAA==.',
Do='Docmcstuffin:BAAANQADCgMIAwAAAA==.Dontblink:BAAANQAECgEIAQABNQAECgoKKQAUANEiAA==.Dorin:BAAANQABCgQIBAAAAA==.Dotore:BAAANQADCgYIBgAAAA==.Dottyflu:BAACNQAFFH8PAAIGAAUKrRR2DwBdAQAGAAUKrRR2DwBdAQA1AAQKfyYAAgYACgr6H/4UAAQDAAYACgr6H/4UAAQDAAAA.Dottylawful:BAABNQAFFH8HAAIYAAUKSwZXBwADAQAYAAUKSwZXBwADAQABNQAFFAUIDwAGAK0UAA==.',
Dr='Drexbear:BAAANQAECgQJBAABNQAFFAUIDwAdAA4PAA==.Drexl:BAACNQAFFH8PAAIdAAUKDg8DAwBJAQAdAAUKDg8DAwBJAQA1AAQKfyMAAwgACQpfE8CsAK0BAAgACQpGCMCsAK0BAB0ABAr+IAYUAJQAAAAA.',
Dw='Dweams:BAACNQAFFH8bAAIeAAYK9xl6BAAEAgAeAAYK9xl6BAAEAgA1AAQKfyYAAx4ACgpkI4QNABQDAB4ACgpkI4QNABQDAB8ABgoxGqcMAG0BAAAA.Dweamu:BAAANQADCgMIAwABNQAFFAYIGwAeAPcZAA==.',
Ec='Ectonight:BAAANQADCgIIAgAAAA==.',
Eg='Eggfooyung:BAAANQAFFAIIAgABNQAFFAcIFgATADkeAA==.Egwene:BAAANQAECgEIAQAAAA==.',
El='Elhonna:BAABNQAECn9AAAIHAAoK/R2FDgD9AQAHAAoK/R2FDgD9AQAAAA==.',
En='Endcredits:BAABNQAECn8WAAIGAAYK6BR+IwDpAAAGAAYK6BR+IwDpAAAAAA==.',
Er='Eridyn:BAAANQAECgYICgAAAA==.',
Ev='Evoulker:BAACNQAFFH8hAAINAAcK4xxtAwBaAgANAAcK4xxtAwBaAgA1AAQKfy4AAg0ACgogHy8LAPACAA0ACgogHy8LAPACAAAA.',
Ey='Eyyosmite:BAAANQABCgIIAgAAAA==.',
Ez='Ezekielle:BAAANQAECgEIAQAAAA==.',
Fa='Faire:BAAANQADCgIIAgABNQAECgcIDwADAAAAAA==.Fairytale:BAACNQAFFH8cAAIgAAYKNxLfCwDLAQAgAAYKNxLfCwDLAQA1AAQKfy0AAx8ACgoGIJQGACACACAACgoPH+klANMCAB8ABwrkHJQGACACAAAA.Faker:BAAANQADCggIDwAAAA==.',
Fe='Felheim:BAACNQAFFH8QAAIFAAYKvhH8AwDeAAAFAAYKvhH8AwDeAAA1AAQKf0MAAgUACgpLHUoGAG0DAAUACgpLHUoGAG0DAAAA.Fellithà:BAAANQADCgUIBgAAAA==.',
Fi='Fists:BAAANQADCgYJDAABNQAFFAMICgANACQQAA==.',
Fl='Flink:BAAANQADCgIJAgAAAA==.Floogi:BAAANQADCgMIAwAAAA==.',
Fo='Foxygal:BAAANQADCggIEwAAAA==.',
Fr='Frostyninja:BAAANQAECgIIAgAAAA==.',
Ga='Garchomp:BAAANQADCgQICAAAAA==.Gawain:BAAANQAECgYICwABNQAECgoKMQAHAL8cAA==.',
Ge='Gellina:BAAANQADCgUICAAAAA==.Georg:BAACNQAFFH8YAAIbAAcKshsWAgB9AgAbAAcKshsWAgB9AgA1AAQKfyUAAhsACgofJSUbAFcDABsACgofJSUbAFcDAAAA.Geriatric:BAAANQAECgIIBQABNQAFFAcIHAAJAGwjAA==.',
Gl='Glathur:BAAANQADCgIIBAAAAA==.Glizzygagger:BAACNQAFFH8GAAMeAAIKhyBSEADJAAAeAAIKhyBSEADJAAAfAAIKsxZpAgCoAAA1AAQKfyAAAx4ACgpsIr4MAB4DAB4ACQpSIr4MAB4DAB8AAgr1HB8FAKwAAAE1AAUUBQgGABoAJRQA.Glizzygorger:BAABNQAECn8XAAIFAAgKwR1kIQBBAgAFAAgKwR1kIQBBAgABNQAFFAUIBgAaACUUAA==.',
Go='Goodbye:BAABNQAECn8eAAMCAAkKzhlGeQCLAgACAAkKzhlGeQCLAgAhAAEKAAD+DQAzAAAAAA==.Goregazme:BAAANQAECgYIBwAAAA==.',
Gr='Grantoro:BAABNQAECn8nAAIiAAkKZQ8rHQC4AQAiAAkKZQ8rHQC4AQAAAA==.Grimmblades:BAAANQAECgIIAgAAAA==.Grootbeer:BAABNQAECn8cAAIHAAcKcRJzhwD8AQAHAAcKcRJzhwD8AQAAAA==.',
Gu='Gulgrimmar:BAACNQAFFH8bAAMLAAcKUhrrCADhAQALAAUKuxzrCADhAQAMAAMKQx8CFQAKAQA1AAQKfyYAAwsACgrMJMsGALMDAAsACQq/JcsGALMDAAwABgrKHGt8AJYBAAAA.Guwudanielle:BAAANQAECgcIDwAAAA==.',
['Gä']='Gävinräd:BAAANQADCgUIBQAAAA==.',
Ha='Haranguetan:BAAANQADCgYIBgABNQAECgkJKAAjABULAA==.Hardfeelings:BAABNQAECn8VAAIbAAYKWBg+UgAgAQAbAAYKWBg+UgAgAQAAAA==.Harrharr:BAAANQADCgMIAwAAAA==.',
He='Headache:BAAANQABCgIIAgABNQAECggIFAAPAHIYAA==.Hexappeal:BAAANQAECgYIBgAAAA==.',
Ho='Hodann:BAAANQABCgYIBgAAAA==.',
Hu='Hurjek:BAABNQAECn8pAAIUAAoK0SL1AABiAwAUAAoK0SL1AABiAwAAAA==.',
Ic='Iconicmax:BAAANQAECgQICwAAAA==.',
Ij='Ijustankedu:BAAANQADCgEIAQAAAA==.',
Il='Ilyana:BAABNQAECn8rAAMCAAoKFiAKagCqAgACAAkKxR4KagCqAgABAAIKKCIZKgCnAAAAAA==.',
In='Insights:BAABNQAECn8WAAIHAAYKxBSGSwAcAQAHAAYKxBSGSwAcAQAAAA==.',
Is='Ishtann:BAAANQABCgIIAgAAAA==.',
Ja='Jaqen:BAACNQAFFH8GAAIaAAUKJRRcAQBPAQAaAAUKJRRcAQBPAQA1AAQKfyMAAxoACQp/ItICAB4DABoACQp/ItICAB4DABcAAQrBGQxEAE8AAAAA.Jayc:BAACNQAFFH8GAAICAAQKrhFVDQDxAAACAAQKrhFVDQDxAAA1AAQKfyUAAgIACgrYHq41AB4DAAIACgrYHq41AB4DAAAA.',
Je='Jereico:BAACNQAFFH8bAAMkAAcKcCFKAQCVAgAkAAcKcCFKAQCVAgAlAAEKqxojDwBHAAA1AAQKfy4AAyQACgpAJdAAALMDACQACgpAJdAAALMDACUACAr5EkwZALQBAAAA.Jeryhn:BAACNQAFFH8cAAITAAUKrBvMCgCwAQATAAUKrBvMCgCwAQA1AAQKfy0AAhMACgriIs4OAFQDABMACgriIs4OAFQDAAAA.',
Jo='Joeynodz:BAAANQAECgEIAQAAAA==.Jortshorts:BAABNQAECn8kAAImAAoKdwcXGAB4AQAmAAoKdwcXGAB4AQAAAA==.',
Ju='Juggalo:BAACNQAFFH8SAAMlAAYKAxXZBAB7AQAlAAUKhxnZBAB7AQAkAAEKeQeRBQBRAAA1AAQKfzcAAyUACgoKI5YEAFEDACUACgoKI5YEAFEDACQAAgoKDWYeAG4AAAAA.June:BAACNQAFFH8aAAIZAAcK8xErAgAXAgAZAAcK8xErAgAXAgA1AAQKfy4AAhkACgrlH0IKAOQCABkACgrlH0IKAOQCAAAA.',
Ka='Kalikin:BAAANQAECgMJBAAAAA==.Kawasuoo:BAAANQADCgQIBAABNQAECgcIDwADAAAAAA==.',
Kc='Kcudüm:BAABNQAECn8yAAQSAAoKJhEoDgAXAgASAAgKahQoDgAXAgARAAYKxgYM/ADTAAAQAAIKNAMILwA4AAAAAA==.',
Ke='Keifis:BAAANQADCgEJAQAAAA==.Keifism:BAAANQABCgMIAwAAAA==.',
Kh='Khaotichic:BAAANQAECgEIAQAAAA==.',
Kl='Klrum:BAABNQAECn8kAAMBAAgKrxdxHgD4AAACAAcKThgCvAAMAgABAAUKqBBxHgD4AAAAAA==.',
Ko='Koddin:BAABNQAECn80AAIbAAoKtRozBwByAgAbAAoKtRozBwByAgAAAA==.Komui:BAABNQAECn80AAMMAAoKkBZETgArAgAMAAoKkBZETgArAgALAAcKeQ9xGABeAQAAAA==.Koonlei:BAAANQAECgQIBAAAAA==.Koreth:BAACNQAFFH8cAAMXAAcKOhOJAgBcAgAXAAcKOhOJAgBcAgAcAAEK9w67FQBCAAA1AAQKfy8AAxcACgpiJPkKADIDABcACgptIvkKADIDABwACgpGHp0SAEEBAAAA.Kornholyo:BAAANQAECgIIAwAAAA==.',
Kr='Krakheeta:BAAANQADCgQIBAAAAA==.Krusade:BAAANQAECgUICQAAAA==.',
Ku='Kumo:BAAANQAECgEIAQAAAA==.Kutuzov:BAAANQAECgUIBQAAAA==.',
Kw='Kwenny:BAAANQAECgEIAQAAAA==.',
La='Lailaysia:BAAANQAECggICQAAAA==.Lamemoosaur:BAABNQAECn8YAAIiAAkKOxxgCAD2AgAiAAkKOxxgCAD2AgAAAA==.Laríca:BAACNQAFFH8HAAITAAMKtx7dBwAOAQATAAMKtx7dBwAOAQA1AAQKfzIAAhMACgrwIXsIAIQDABMACgrwIXsIAIQDAAAA.Laydout:BAAANQADCgQIBAABNQAECgcIEQADAAAAAA==.Laydoutyota:BAAANQAECgcIEQAAAA==.Laymow:BAAANQAECgQJBAABNQAECgkJGAAiADscAA==.',
Le='Levity:BAAANQAECggIBQAAAA==.',
Li='Lilea:BAABNQAECn8sAAMEAAoKHxFjPgBgAQAHAAcKhxI3qAC1AQAEAAcK5QljPgBgAQAAAA==.Lilfaart:BAAANQAECggIBAAAAA==.Lilotterine:BAAANQADCgcIBwAAAA==.Lindisalvia:BAAANQADCggIEQAAAA==.Lionsmane:BAAANQADCgYIBgAAAA==.',
Lo='Loosemorals:BAACNQAFFH8KAAINAAMKJBDIBgDKAAANAAMKJBDIBgDKAAA1AAQKfyEAAw0ACgqNGLkQAJ8CAA0ACgqNGLkQAJ8CACUAAQoQFHI6ADwAAAAA.Lootgoblin:BAABNQAECn8qAAICAAkKPBmCkQBdAgACAAkKPBmCkQBdAgAAAA==.Lortherian:BAAANQAECgUIEgAAAA==.',
Lu='Lunatique:BAAANQADCgQIBAAAAA==.',
['Lä']='Läwlbringer:BAABNQAECn8aAAIbAAkKyRAplwD1AQAbAAkKyRAplwD1AQAAAA==.',
Ma='Mabritoe:BAACNQAFFH8HAAIXAAQK1SN3CgBZAQAXAAQK1SN3CgBZAQA1AAQKfyMAAxcACQrMJJwPAAQDABcACArMJJwPAAQDABwACAqSCa4iALQBAAE1AAUUBwgYABUAhRUA.Magooh:BAAANQADCgcIBwABNQAECgQIEQADAAAAAA==.Malison:BAAANQADCgUIBAAAAA==.Mangle:BAAANQADCgUIBQAAAA==.Mania:BAAANQADCgYICgABNQAECggIFAAPAHIYAA==.Mareth:BAAANQADCgIIAgAAAA==.Mathath:BAABNQAECn8hAAMKAAkKOxqdPwAfAgAKAAkK6xidPwAfAgAGAAMKYx92fQAEAQAAAA==.Mathoras:BAAANQADCgYIBgAAAA==.Mayaho:BAAANQAECgQIEQAAAA==.Maylee:BAAANQAECgYIDwAAAA==.',
Me='Meandean:BAAANQAECgYIBgAAAA==.Meatier:BAAANQAECgQICQABNQAECggIFAAPAHIYAA==.Meenako:BAAANQAECgEIAQAAAA==.Mellinia:BAAANQADCgEIAQAAAA==.',
Mi='Miltonroe:BAABNQAECn8oAAIjAAkKFQsAGADoAQAjAAkKFQsAGADoAQAAAA==.Miltonroé:BAAANQAECgQIBAABNQAECgkJKAAjABULAA==.Mixing:BAAANQADCgIJAgAAAA==.',
Mo='Monnz:BAAANQADCgUIBQAAAA==.Monsterskill:BAAANQAECgYIBwAAAA==.Moonerva:BAABNQAECn8WAAIVAAYKLwsoKgC7AAAVAAYKLwsoKgC7AAAAAA==.Morana:BAAANQAECgMIAwAAAA==.',
Mu='Munchinmuff:BAAANQAECgQIBQAAAA==.',
Mv='Mvqchx:BAAANQADCgEIAQAAAA==.',
My='Myrolous:BAAANQADCgQIBAAAAA==.',
['Mã']='Mãrtrydóm:BAAANQAECgEIAQAAAA==.',
['Mì']='Mìssy:BAAANQAECgEIAQAAAA==.',
Na='Namiin:BAAANQADCgUIBQAAAA==.Namikaze:BAAANQAECgEIAgAAAA==.Natara:BAAANQADCgYICgAAAA==.Naughtye:BAAANQAECgQIBQAAAA==.Nave:BAAANQAECgcICAAAAA==.',
Ne='Nelfsfault:BAAANQADCggJFwAAAA==.Nerotappo:BAAANQABCgIIAgAAAA==.',
Ni='Ninja:BAAANQADCgYJBgAAAA==.',
No='Nobacon:BAAANQADCgIIAgAAAA==.Noshaku:BAAANQAECgMIBgAAAA==.Notanorc:BAABNQAECn8tAAMIAAoKyA/qKQBgAQAIAAoKogzqKQBgAQAPAAUKMRO4FQBAAQAAAA==.',
Od='Odium:BAAANQAECgIIAgAAAA==.',
Oh='Ohrolam:BAABNQAECn8uAAMCAAoKuQjb4gDDAQACAAoKIQfb4gDDAQABAAQKxwqsKgCkAAAAAA==.',
Ok='Okasan:BAAANQAECgQICAABNQAECgQIEAADAAAAAA==.',
Ot='Ottersdemons:BAAANQAECgMIAwAAAA==.',
Pa='Palthur:BAAANQAECgMIBgAAAA==.Passionate:BAAANQADCgUIBQAAAA==.',
Ph='Phatmidas:BAABNQAECn8lAAIbAAoKARfPcgBJAgAbAAoKARfPcgBJAgAAAA==.Phrozenpally:BAAANQAECgQICwABNQAECgQIEQADAAAAAA==.',
Pi='Pika:BAAANQADCgcIBwABNQAFFAMICwAGAKoTAA==.Pinbull:BAAANQADCgEIAQAAAA==.Pinkponythug:BAAANQAECgUIBgABNQAFFAMICgANACQQAA==.',
Pl='Plagueground:BAACNQAFFH8aAAQJAAcKeCD8AQA9AgAJAAYKXCP8AQA9AgAGAAIK5xRpJQBmAAAKAAEKsA9hJAA7AAA1AAQKfzQABAkACgq2JXkCAMEDAAkACgq2JXkCAMEDAAYAAgrlJZGcAKEAAAoAAQrJBZblAC8AAAAA.Plutonyus:BAAANQAECgMIBAAAAA==.',
Po='Poc:BAAANQAECgQICQAAAA==.Porterhaus:BAAANQADCggICAABNQAFFAMIBQASAEQPAA==.Pounces:BAABNQAECn84AAImAAoKhSViAQDBAwAmAAoKhSViAQDBAwAAAA==.',
Pr='Prózak:BAAANQADCgYIBgABNQAECgoKJwAYAJIUAA==.Prôzak:BAABNQAECn8nAAIYAAoKkhTZCABtAQAYAAoKkhTZCABtAQAAAA==.',
Ps='Psychomidget:BAAANQAECgUIBwAAAA==.',
Pu='Puetrid:BAACNQAFFH8FAAMSAAMKRA/+DwCUAAASAAIKRA/+DwCUAAARAAEKAADsIAAAAAA1AAQKfycAAxIACgpgGPIFALICABIACQrXFfIFALICABEABArfGO4oAE4BAAAA.Purble:BAAANQADCgIIAgAAAA==.Puufrumslli:BAAANQAECgcIEQAAAA==.',
Ra='Rageinglight:BAAANQAECgMIBQAAAA==.Rakku:BAAANQABCgcJBgAAAA==.Rautha:BAABNQAECn8cAAIbAAgKBBJDqQDNAQAbAAgKBBJDqQDNAQAAAA==.Rayl:BAAANQAECgEIAQAAAA==.',
Re='Rekt:BAAANQAECggIDQAAAA==.',
Rh='Rhaegon:BAABNQAECn8tAAInAAkKCBxGBQDeAgAnAAkKCBxGBQDeAgAAAA==.',
Ri='Rimath:BAAANQADCggIEAAAAA==.',
Rn='Rng:BAAANQAECgIIAgABNQAECgcIGAAGAK8LAA==.',
Ro='Rodstewart:BAABNQAECn8VAAMHAAkKZBQolADgAQAHAAgKhRUolADgAQAEAAMKsQsadQBmAAAAAA==.Ronz:BAAANQABCgEJAQAAAA==.Roofeo:BAAANQAECgEIAQABNQAECgkJLAAGAP0SAA==.Rotdaddy:BAABNQAECn8nAAIKAAkKmQgRGAAjAQAKAAkKmQgRGAAjAQAAAA==.',
Sa='Sabatikus:BAAANQAECgEIAQAAAA==.Salino:BAABNQAECn8XAAIVAAcK5wkWWwBmAQAVAAcK5wkWWwBmAQAAAA==.Sam:BAAANQAECgcIEQAAAA==.Sandorindis:BAAANQADCgYIBwAAAA==.Sarate:BAAANQADCggIEAAAAA==.Satral:BAAANQAECgYIBwAAAA==.Savannah:BAAANQAECgYIBwABNQAECgcIDwADAAAAAA==.Savvtwo:BAAANQADCgEIAQABNQAFFAcIIAAWANckAQ==.',
Se='Sezra:BAAANQADCggICAAAAA==.',
Sh='Shaetahn:BAAANQAECgEIAQAAAA==.Shamwowthorn:BAAANQADCgEIAQAAAA==.Shinanigans:BAABNQAECn8uAAIbAAkKPB9CDQAVAgAbAAkKPB9CDQAVAgAAAA==.Shockbull:BAAANQADCgcJBwAAAA==.',
Si='Silverbäck:BAAANQAECgYIDAABNQADCggIHgADAAAAAA==.Silverslam:BAAANQAECgIIAgABNQADCggIHgADAAAAAA==.',
Sk='Skurge:BAAANQAECgUIEgAAAA==.',
Sn='Snacks:BAAANQADCgEIAQABNQAECgcIEQADAAAAAA==.Snuffles:BAAANQADCgYIBgAAAA==.',
So='Solstis:BAAANQAECgUICQAAAA==.Soranwena:BAABNQAECn8fAAIiAAoKlRUvDAA8AQAiAAoKlRUvDAA8AQAAAA==.Sorros:BAAANQAECgQIBQAAAA==.',
Sp='Spacegoat:BAAANQAECgMIAwAAAA==.Spfzero:BAAANQAECgEIAQAAAA==.Spookybuns:BAAANQAECggIBQAAAA==.',
St='Sticksy:BAAANQADCgYIBgAAAA==.Stonebeard:BAAANQAECgQIBgAAAA==.Stârlèss:BAAANQADCgYIBwAAAA==.',
Su='Subtox:BAAANQAECgcICgAAAA==.',
Sw='Swedishfish:BAAANQAECgEIAQABNQAECgkJHQAeAP4dAA==.',
['Sá']='Sálúd:BAAANQAECgcIEQAAAA==.',
['Sê']='Sêp:BAAANQAECgIIAgAAAA==.',
Ta='Tarhealeon:BAAANQAECgYIDgAAAA==.Tarvuspls:BAABNQAECn8WAAMHAAgKRA9SiAD6AQAHAAgKRA9SiAD6AQAEAAUK7QU+VgDNAAAAAA==.',
Te='Teemawthy:BAAANQADCgMIAwAAAA==.Temozo:BAAANQADCgIIAgAAAA==.',
Th='Thabigone:BAAANQAECgIIAgAAAA==.Theceo:BAAANQADCgYIDgAAAA==.Thorb:BAAANQAECggIDAABNQAFFAMICwAGAKoTAA==.',
Ti='Ticklemebutt:BAAANQAECgcIEgAAAA==.Tiewaz:BAAANQAECggICwAAAA==.',
To='Tolun:BAABNQAECn8hAAIBAAoKVhJjCgAjAgABAAoKVhJjCgAjAgAAAA==.Tosan:BAAANQAECgQIEAAAAA==.Toughcookie:BAABNQAECn8YAAMbAAgKhglw1wBtAQAbAAgKhglw1wBtAQATAAIKPgR2FwFGAAAAAA==.',
Tr='Treeplague:BAABNQAECn8dAAMfAAgK0Qw8CwCOAQAfAAgK0Qw8CwCOAQAeAAIK4QQ3bQBQAAAAAA==.',
Tu='Turn:BAACNQAFFH8eAAQSAAcKKhSDAgD1AAAQAAMKRxQ0AgAAAQASAAMK7RODAgD1AAARAAMKhhBfIgDnAAA1AAQKfysABBIACgqrINwPAAACABEABwoSHc11AAECABIABwpPF9wPAAACABAABQqFJS4KANcBAAAA.Turtleduck:BAAANQADCgUIBQABNQAECgYIEAADAAAAAA==.',
Ty='Tyla:BAAANQAECggICAAAAA==.Typhis:BAAANQAECgQIBAAAAA==.',
['Tì']='Tìewaz:BAAANQAECgQIBgABNQAECggICwADAAAAAA==.',
Um='Umbryx:BAAANQAECgEIAQAAAA==.',
Un='Unagi:BAABNQAECn8nAAIjAAoKWQyWBgCPAQAjAAoKWQyWBgCPAQAAAA==.',
Va='Valdir:BAAANQAECggIBgAAAA==.Vasomir:BAAANQABCgIIAQAAAA==.',
Ve='Venomstrikes:BAAANQADCgcIBwAAAA==.Venøm:BAAANQAECgEIAQAAAA==.',
Vi='Viscerion:BAAANQAECgYIEAAAAA==.',
Wh='Whoarlock:BAAANQAECgEIAQAAAA==.',
Wi='Wizzyy:BAAANQADCgUIBQAAAA==.',
Xe='Xelinia:BAACNQAFFH8RAAMeAAUKoQd6DAAcAQAeAAQKoQd6DAAcAQAgAAEK9AIIOAA/AAA1AAQKfyUAAx4ACgr4HN0YAIkCAB4ACgr4HN0YAIkCACAAAQrfAV8KAR8AAAAA.Xen:BAEANQAECggICwAAAA==.',
Xu='Xuefeng:BAACNQAFFH8PAAIoAAUKChDSBADHAAAoAAUKChDSBADHAAA1AAQKfzYAAigACgrcG+0LABcDACgACgrcG+0LABcDAAAA.',
Ya='Yahwae:BAAANQAECgQICwABNQAECgoKLQARAIMTAA==.',
Yc='Ycephyre:BAAANQAECgYICQAAAA==.',
Ye='Yenchmeister:BAACNQAFFH8ZAAIIAAcKDBfvBgBSAgAIAAcKDBfvBgBSAgA1AAQKfy0AAggACgpSJEcdAEIDAAgACgpSJEcdAEIDAAAA.',
Yo='Yomahma:BAAANQAECgUIBgAAAA==.',
Yu='Yuta:BAAANQADCgQIBAAAAA==.',
Zd='Zdervish:BAABNQAECn8aAAIXAAcKihojKQBKAgAXAAcKihojKQBKAgAAAA==.',
Ze='Zeffira:BAAANQAECgUIAwAAAA==.Zellda:BAAANQADCgYIBgAAAA==.',
Zi='Zilvanic:BAABNQAECn8WAAMYAAkKTgfBNQA5AQAYAAgKJwjBNQA5AQATAAMK9wYsbwBvAAAAAA==.Zilvanion:BAABNQAECn8wAAIRAAoKmBMELABEAQARAAoKmBMELABEAQAAAA==.',
Zl='Zlathur:BAAANQADCgcIDgAAAA==.',
Zo='Zourbeast:BAAANQADCgQIBAAAAA==.Zourknight:BAAANQADCgcICAAAAA==.Zourlight:BAAANQADCgcIEQAAAA==.Zourlock:BAAANQADCggIEAAAAA==.Zourvoid:BAAANQADCggIGAAAAA==.',
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
