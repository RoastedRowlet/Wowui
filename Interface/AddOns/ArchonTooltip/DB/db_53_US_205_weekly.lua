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

local lookup = {'Mage-Frost','Mage-Arcane','Unknown-Unknown','Hunter-Marksmanship','DemonHunter-Devourer','Druid-Restoration','DeathKnight-Blood','DemonHunter-Vengeance','Hunter-BeastMastery','Warrior-Arms','DeathKnight-Frost','DeathKnight-Unholy','Shaman-Elemental','Shaman-Restoration','Evoker-Preservation','Monk-Brewmaster','Warrior-Fury','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Paladin-Holy','Druid-Balance','DemonHunter-Havoc','Rogue-Assassination','Paladin-Protection','Monk-Mistweaver','Rogue-Outlaw','Paladin-Retribution','Rogue-Subtlety','Warrior-Protection','Priest-Shadow','Priest-Discipline','Priest-Holy','Mage-Fire','Druid-Guardian','Shaman-Enhancement','Evoker-Augmentation','Evoker-Devastation','Druid-Feral','Monk-Windwalker',}
local provider = {region='US',realm='Stonemaul',name='US',type='weekly',zone=53,date='2026-10-27',data={Ad='Addalar:BAAANQAECgcIEAAAAA==.',
Ai='Airvis:BAABNQAECn8cAAMBAAgKPRIADAD8AQABAAgKPRIADAD8AQACAAMKxQYGngGJAAAAAA==.',
Ak='Akamie:BAAANQAECgIIAgABNQAECgcIDwADAAAAAA==.Akar:BAAANQADCgMIAwAAAA==.',
Al='Alacia:BAAANQADCgQIBAABNQAECgoKMgAEAEkSAA==.Albinomonk:BAAANQADCgMIAwAAAA==.',
Am='Amaira:BAAANQAECgEIAQAAAA==.Amalakar:BAAANQAECgEIAQAAAA==.Amnezea:BAAANQADCgIIAgAAAA==.',
An='Anankei:BAAANQADCgYIBgAAAA==.Anavere:BAAANQADCgUIBQAAAA==.Annasia:BAAANQAECgEIAQAAAA==.Antte:BAACNQAFFH8YAAIFAAYKRxWtBQDSAQAFAAYKRxWtBQDSAQA1AAQKfyQAAgUACQquIwYLACwDAAUACQquIwYLACwDAAAA.',
Ar='Arjun:BAAANQAECgYIBgAAAA==.Armindru:BAABNQAECn8bAAIGAAoK9hU+DwA2AgAGAAoK9hU+DwA2AgAAAA==.Armingothele:BAAANQAECgEIAQABNQAECgoKGwAGAPYVAA==.Arturogh:BAAANQADCggICAABNQAECgkJLQAHAFcTAA==.',
As='Asmôdeô:BAABNQAECn8XAAMFAAoK9iCYCAB4AgAFAAoK9iCYCAB4AgAIAAEK6SLCKgBeAAAAAA==.Astin:BAAANQAECgEIAQAAAA==.',
At='Atom:BAABNQAECn8jAAIJAAoK4QyiOAD+AQAJAAoK4QyiOAD+AQAAAA==.Atreyu:BAABNQAECn8nAAIKAAcKsgzYYQBdAQAKAAcKsgzYYQBdAQAAAA==.',
Au='Aureille:BAAANQAECgMIAwAAAA==.',
Aw='Awoozehl:BAACNQAFFH8eAAMLAAgKmCBvAADLAgALAAcKbCNvAADLAgAMAAIKbheyCwBbAAA1AAQKfzcAAwsACgp7JUYFAIwDAAsACgp7JUYFAIwDAAwACAoiG31cAJ4BAAAA.',
Az='Azgrodon:BAABNQAECn8wAAMNAAoKTBltTQBBAgANAAoKTBltTQBBAgAOAAgKEgoLjABrAQAAAA==.',
Ba='Banatok:BAAANQADCgIIAwAAAA==.Bangungot:BAAANQAECgEIAQABNQAFFAgIFwAPABEVAA==.Barnabus:BAAANQAECgMIAwAAAA==.Barristan:BAAANQADCgIIAgAAAA==.Barzalie:BAAANQAECgEIAQABNQAFFAUIEAAHAGYXAA==.Bathrezz:BAAANQAECgQICwAAAA==.',
Be='Beandruid:BAAANQAECgYIBwAAAA==.Beanmage:BAAANQAECgUIBQAAAA==.Beanshaman:BAAANQADCgYIBgAAAA==.Bearlyawake:BAAANQADCgUIBQAAAA==.Beerbelly:BAABNQAECn80AAIQAAoKZCAnAwBlAwAQAAoKZCAnAwBlAwABNQAFFAUIEAAHAGYXAA==.Beleaves:BAACNQAFFH8bAAIQAAYK9ggiBABkAQAQAAYK9ggiBABkAQA1AAQKfyoAAhAACQqqFHwMADsCABAACQqqFHwMADsCAAAA.Bellectra:BAABNQAECn8ZAAMCAAcK2QcCqwDxAAACAAcK2QcCqwDxAAABAAIKxgZhPQBLAAAAAA==.',
Bi='Bifurious:BAABNQAECn8XAAIRAAkK8RnQCgAZAgARAAkK8RnQCgAZAgAAAA==.',
Bl='Blathur:BAAANQADCgcIDQAAAA==.Bluereindeer:BAABNQAECn80AAIHAAoKyRAEIACSAQAHAAoKyRAEIACSAQAAAA==.',
Bo='Bobafina:BAAANQADCggICAAAAA==.Bobsstones:BAACNQAFFH8WAAQSAAgKQhlgAQBLAQASAAUKxRRgAQBLAQATAAMKKxdjIQDsAAAUAAIK+x3wCgCjAAA1AAQKfzIABBIACgrvJQQBAMICABIACgrTIAQBAMICABMABgrNJLiMAMcBABQABQqhHw8WALwBAAAA.Bobstofu:BAAANQAECgcIEwAAAA==.Bofaðeez:BAAANQADCgQIBAAAAA==.Bombtimer:BAAANQADCgMIBAABNQADCgUICQADAAAAAA==.Bonkulo:BAABNQAECn8tAAQHAAkKVxMvRgDhAQAHAAkKVxMvRgDhAQALAAMKCwlXYQCdAAAMAAQKZQVATACHAAAAAA==.Boofassist:BAACNQAFFH8WAAIVAAcKOR7qAwBOAgAVAAcKOR7qAwBOAgA1AAQKfy4AAhUACgpAI8cDALYDABUACgpAI8cDALYDAAAA.Boomsonic:BAAANQAECgQIBwABNQAECgkJFwARAPEZAA==.Bophadeez:BAAANQAECgEIAQABNQAFFAQICwAPAOYNAA==.Boraga:BAAANQADCgYJBwAAAA==.',
Br='Brienyx:BAAANQADCgUIBwAAAA==.Brietemis:BAAANQAECgQICAAAAA==.Briezani:BAABNQAECn8bAAMNAAgKvgtqTQAlAQANAAgKvgtqTQAlAQAOAAIKowKoJAEoAAAAAA==.Briogan:BAAANQAECgUICQAAAA==.Broccoliz:BAECNQAFFH8eAAIGAAgKdRHbAgApAgAGAAgKdRHbAgApAgA1AAQKfzwAAwYACgqtHPMJAKMCAAYACgqtHPMJAKMCABYAAQpXFsmqAEEAAAAA.Brokan:BAAANQAECggICwAAAA==.Broke:BAAANQAECgIIAgABNQAFFAcIIAAXANckAQ==.',
Bu='Bukhaki:BAAANQAECggIDgABNQAECgoKKAAYAHIdAA==.',
['Bõ']='Bõb:BAAANQAECgEIAQAAAA==.',
Ca='Caden:BAAANQADCgYIBgABNQAECgoKMgAEAEkSAA==.Cafca:BAABNQAECn8mAAISAAoKdA+JBACuAQASAAoKdA+JBACuAQAAAA==.Caké:BAAANQADCgYIDAAAAA==.Caldrr:BAAANQAECgEIAQAAAA==.Caylva:BAAANQAECgYICQABNQAFFAUIEAAHAGYXAA==.',
Ch='Chrams:BAABNQAECn9JAAIVAAoK9R8OFwAgAwAVAAoK9R8OFwAgAwAAAA==.',
Ci='Cialis:BAAANQADCgYIJgAAAA==.Cinnacrunch:BAAANQADCggIDgAAAA==.',
Cl='Clearlyumad:BAAANQAECgQIBwAAAA==.Clèrick:BAABNQAECn8+AAMVAAoKzyFSIwDeAgAVAAkKpCJSIwDeAgAZAAcKhw0YMgBQAQAAAA==.',
Co='Coldcrow:BAAANQADCgUICQAAAA==.Combination:BAABNQAECn8vAAIaAAoKiCCHBwAaAwAaAAoKiCCHBwAaAwABNQAFFAIIBQAGAHYbAA==.Cowen:BAAANQADCggIEwAAAA==.',
Cr='Crash:BAAANQADCgUIBQABNQAFFAQIDAADAAAAAA==.Cray:BAAANQADCgQIBQABNQAECgcICQADAAAAAA==.',
Cu='Cursedotter:BAAANQAECgcIDwAAAA==.',
Da='Dabbyshatner:BAAANQAECgYIDQAAAA==.Daeneryis:BAAANQAECgQIAwAAAA==.Dankshammy:BAABNQAECn8yAAIOAAoKSxzoIQDgAgAOAAoKSxzoIQDgAgAAAA==.Darkwave:BAABNQAECn8zAAMUAAoK6hMSFQByAAATAAgKTRFwbwAeAQAUAAMKeRMSFQByAAAAAA==.Darthdiddyus:BAACNQAFFH8PAAIbAAQKaBdyAQBCAQAbAAQKaBdyAQBCAQA1AAQKfysAAhsACQpUIbkCACMDABsACQpUIbkCACMDAAAA.Dathunter:BAAANQAECgIIAgABNQAECgkJKgACADwZAA==.Datshammy:BAAANQAECgEIAQABNQAECgkJKgACADwZAA==.Dawghawg:BAAANQADCgUIBgAAAA==.Dawnnie:BAACNQAFFH8IAAIZAAMKdAs+BQCvAAAZAAMKdAs+BQCvAAA1AAQKfzcAAhkACgqtHDkOALcCABkACgqtHDkOALcCAAAA.Dawsonrogers:BAABNQAECn8dAAMRAAkKhxSnCgAeAgARAAgKMRenCgAeAgAKAAMKvg0cKQGEAAAAAA==.',
De='Deathbanana:BAAANQADCggICAABNQAFFAgIFwACAIgdAA==.Deathbydk:BAACNQAFFH8QAAIHAAUKZhe9DADIAAAHAAUKZhe9DADIAAA1AAQKfy0AAgcACgpLIpsFAAIDAAcACgpLIpsFAAIDAAAA.Delema:BAACNQAFFH8PAAIcAAYKRg3QCAC9AQAcAAYKRg3QCAC9AQA1AAQKfy8AAxwACgp6H4VfAHoCABwACgp6H4VfAHoCABkABQpWDWIqALcAAAAA.Derbina:BAAANQABCgIIBAAAAA==.Destructer:BAAANQAECgMICQAAAA==.',
Di='Dirtydinker:BAAANQAECgcICQAAAA==.Dixsard:BAABNQAECn8oAAMYAAoKch3DGQCvAgAYAAkKLBvDGQCvAgAdAAgK/BNVOgB8AQAAAA==.',
Do='Docmcstuffin:BAAANQADCgMIAwAAAA==.Dontblink:BAAANQAECgEIAQABNQAFFAIIBQAGAHYbAA==.Dorin:BAAANQABCgQIBAAAAA==.Dotore:BAAANQADCgYIBgAAAA==.Dottyflu:BAACNQAFFH8QAAIHAAUKrRR2DwBdAQAHAAUKrRR2DwBdAQA1AAQKfzAAAgcACgoMI28FAAYDAAcACgoMI28FAAYDAAE1AAUUBggIABkAbQYA.Dottylawful:BAABNQAFFH8IAAIZAAYKbQZXBwADAQAZAAYKbQZXBwADAQAAAA==.',
Dr='Drexbear:BAAANQAECgQJBAABNQAFFAYIEAAeALQNAA==.Drexl:BAACNQAFFH8QAAIeAAYKtA0DAwBJAQAeAAYKtA0DAwBJAQA1AAQKfyUAAx4ACgo8FDoTAAsBAAoACQpGCMCsAK0BAB4ABgovGzoTAAsBAAAA.',
Dw='Dweams:BAACNQAFFH8dAAIfAAcKZxV6BAAEAgAfAAcKZxV6BAAEAgA1AAQKfzAAAx8ACgqOJH0DAAwDAB8ACgqOJH0DAAwDACAABgoxGqcMAG0BAAAA.Dweamu:BAAANQADCgMIAwABNQAFFAcIHQAfAGcVAA==.',
Ec='Ectonight:BAAANQADCgIIAgAAAA==.',
Eg='Eggfooyung:BAAANQAFFAIIAgABNQAFFAcIFgAVADkeAA==.Egwene:BAAANQAECgEIAQAAAA==.',
El='Elhonna:BAACNQAFFH8HAAIJAAMKpQwaEADLAAAJAAMKpQwaEADLAAA1AAQKf0QAAgkACgoRIKYpAPICAAkACgoRIKYpAPICAAAA.',
En='Endcredits:BAABNQAECn8cAAIHAAcKrhO/NAAVAQAHAAcKrhO/NAAVAQAAAA==.',
Er='Eridyn:BAAANQAECgYIDgAAAA==.',
Ev='Evoulker:BAACNQAFFH8jAAIPAAgKuBltAwBaAgAPAAgKuBltAwBaAgA1AAQKfzgAAg8ACgogHy8LAPACAA8ACgogHy8LAPACAAAA.',
Ey='Eyyosmite:BAAANQABCgIIAgAAAA==.',
Ez='Ezekielle:BAAANQAECgEIAQAAAA==.',
Fa='Faire:BAAANQADCgIIAgABNQAECgcIDwADAAAAAA==.Fairytale:BAACNQAFFH8eAAIhAAcKABDfCwDLAQAhAAcKABDfCwDLAQA1AAQKfzcAAyAACgoGIJQGACACACEACgoPH+klANMCACAABwrkHJQGACACAAAA.Faker:BAAANQADCggIDwAAAA==.',
Fe='Felheim:BAACNQAFFH8VAAIFAAYKohUgAwAtAQAFAAYKohUgAwAtAQA1AAQKf00AAgUACgr8IUoGAG0DAAUACgr8IUoGAG0DAAAA.Fellithà:BAAANQADCgUIBgAAAA==.',
Fi='Fists:BAAANQADCgYJDAABNQAFFAQICwAPAOYNAA==.',
Fl='Flink:BAAANQADCgIJAgAAAA==.Floogi:BAAANQADCgMIAwAAAA==.',
Fo='Foxygal:BAAANQADCggIEwAAAA==.',
Fr='Frostyninja:BAAANQAECgIIAgAAAA==.',
Ga='Garchomp:BAAANQADCgQICAAAAA==.Gawain:BAAANQAECgYICwABNQAECgoKNwAJAL8cAA==.',
Ge='Gellina:BAAANQADCgUICAAAAA==.Georg:BAACNQAFFH8aAAIcAAgKLRgWAgB9AgAcAAgKLRgWAgB9AgA1AAQKfy8AAhwACgqkJWIEAF4DABwACgqkJWIEAF4DAAAA.Geriatric:BAAANQAECgIIBQABNQAFFAgIHgALAJggAA==.',
Gl='Glathur:BAAANQADCgIIBAAAAA==.Glizzygagger:BAACNQAFFH8HAAMfAAMKhyBSEADJAAAfAAMKhyBSEADJAAAgAAIKsxZpAgCoAAA1AAQKfyIAAx8ACgpsIr4MAB4DAB8ACQpSIr4MAB4DACAAAgpKIHMIALwAAAE1AAUUBQgGABsAJRQA.Glizzygorger:BAABNQAECn8ZAAIFAAgKVR5kIQBBAgAFAAgKVR5kIQBBAgABNQAFFAUIBgAbACUUAA==.',
Go='Goodbye:BAABNQAECn8eAAMCAAkKzhlGeQCLAgACAAkKzhlGeQCLAgAiAAEKAAD+DQAzAAAAAA==.Goregazme:BAAANQAECgYICwAAAA==.',
Gr='Grantoro:BAABNQAECn8uAAIjAAoK+g4rHQC4AQAjAAoK+g4rHQC4AQAAAA==.Grimmblades:BAAANQAECgIIAgAAAA==.Grootbeer:BAABNQAECn8lAAIJAAkKjhFzhwD8AQAJAAkKjhFzhwD8AQAAAA==.',
Gu='Gulgrimmar:BAACNQAFFH8dAAMNAAgKrhvrCADhAQANAAUKuxzrCADhAQAOAAQK3RoCFQAKAQA1AAQKfzAAAw0ACgp5JcsGALMDAA0ACQpSJssGALMDAA4ABgpwHWt8AJYBAAAA.Guwudanielle:BAAANQAECgcIDwAAAA==.',
['Gä']='Gävinräd:BAAANQADCgUIBQAAAA==.',
Ha='Haranguetan:BAAANQADCgYIBgABNQAECgkJKwAkAGgMAA==.Hardfeelings:BAABNQAECn8aAAIcAAYKNBlKtAC2AQAcAAYKNBlKtAC2AQAAAA==.Harrharr:BAAANQADCgMIAwAAAA==.',
He='Headache:BAAANQABCgIIAgABNQAECgkJFwARAPEZAA==.Hexappeal:BAAANQAECgcIBgAAAA==.',
Ho='Hodann:BAAANQABCgYIBgAAAA==.',
Hu='Hurjek:BAACNQAFFH8FAAIGAAIKdhvCCgCYAAAGAAIKdhvCCgCYAAA1AAQKfzQAAgYACgrqIz8CAKMDAAYACgrqIz8CAKMDAAAA.',
Ic='Iconicmax:BAAANQAECgQICwAAAA==.',
Ij='Ijustankedu:BAAANQADCgEIAQAAAA==.',
Il='Ilyana:BAABNQAECn8sAAMCAAoK0CAKagCqAgACAAkKmh8KagCqAgABAAIKKCIZKgCnAAAAAA==.',
In='Insights:BAABNQAECn8cAAIJAAcKVhI5dwBGAQAJAAcKVhI5dwBGAQAAAA==.',
Is='Ishtann:BAAANQABCgIIAgAAAA==.',
Ja='Jaqen:BAACNQAFFH8GAAIbAAUKJRRcAQBPAQAbAAUKJRRcAQBPAQA1AAQKfyYAAxsACQpWI9ICAB4DABsACQpWI9ICAB4DABgAAQrBGcNOAEwAAAAA.Jayc:BAACNQAFFH8JAAICAAUKbBYyEwD+AAACAAUKbBYyEwD+AAA1AAQKfygAAgIACgpxH641AB4DAAIACgpxH641AB4DAAAA.',
Je='Jereico:BAACNQAFFH8dAAMlAAgKdSBKAQCVAgAlAAgKdSBKAQCVAgAmAAEKqxojDwBHAAA1AAQKfzgAAyUACgr9JTUAAG8DACUACgr9JTUAAG8DACYACAr5EkwZALQBAAAA.Jeryhn:BAACNQAFFH8eAAIVAAYKMBjMCgCwAQAVAAYKMBjMCgCwAQA1AAQKfzIAAhUACgo4I84OAFQDABUACgo4I84OAFQDAAAA.',
Jo='Joeynodz:BAAANQAECgEIAQAAAA==.Jortshorts:BAABNQAECn8mAAInAAoKdwcXGAB4AQAnAAoKdwcXGAB4AQAAAA==.',
Ju='Juggalo:BAACNQAFFH8UAAMmAAcK4BLZBAB7AQAmAAYKuRXZBAB7AQAlAAEKeQdRCQBIAAA1AAQKfz0AAyYACgrjI5YEAFEDACYACgrjI5YEAFEDACUAAgoKDWYeAG4AAAAA.June:BAACNQAFFH8aAAIaAAcK8xErAgAXAgAaAAcK8xErAgAXAgA1AAQKfzgAAhoACgpYIEIKAOQCABoACgpYIEIKAOQCAAAA.',
Ka='Kalikin:BAAANQAECgMJBAAAAA==.Kawasuoo:BAAANQADCgQIBAABNQAECgcIDwADAAAAAA==.',
Kc='Kcudüm:BAABNQAECn80AAQUAAoKSxIoDgAXAgAUAAgK0xUoDgAXAgATAAYK6AYM/ADTAAASAAIKNAMILwA4AAAAAA==.',
Ke='Keifis:BAAANQADCgEJAQAAAA==.Keifism:BAAANQABCgMIAwAAAA==.',
Kh='Khaotichic:BAAANQAECgEIAQAAAA==.',
Kl='Klrum:BAABNQAECn8kAAMBAAgKrxdxHgD4AAACAAcKThgCvAAMAgABAAUKqBBxHgD4AAAAAA==.',
Ko='Koddin:BAABNQAECn84AAIcAAoKlRsMPwDYAgAcAAoKlRsMPwDYAgAAAA==.Komui:BAABNQAECn84AAMOAAoKkBZETgArAgAOAAoKkBZETgArAgANAAcKeQ/0RwA3AQAAAA==.Koonlei:BAAANQAECgQIBAAAAA==.Koraxx:BAAANQADCgUIAwAAAA==.Koreth:BAACNQAFFH8eAAMYAAgKJxKJAgBcAgAYAAgKJxKJAgBcAgAdAAIK9w67FQBCAAA1AAQKfzoAAx0ACgosJVcFAC0DABgACgptIvkKADIDAB0ACgpqIlcFAC0DAAAA.Kornholyo:BAAANQAECgIIAwAAAA==.',
Kr='Krakheeta:BAAANQADCgQIBAAAAA==.Krusade:BAAANQAECgUICQAAAA==.',
Ku='Kumo:BAAANQAECgEIAQAAAA==.Kutuzov:BAAANQAECgUIBwAAAA==.',
Kw='Kwenny:BAAANQAECgEIAQAAAA==.',
La='Lailaysia:BAAANQAECggIDwAAAA==.Lamemoosaur:BAABNQAECn8YAAIjAAkKOxxgCAD2AgAjAAkKOxxgCAD2AgAAAA==.Landfilltwo:BAAANQABCgQIBAAAAA==.Laríca:BAACNQAFFH8JAAIVAAMKtx7oDAAFAQAVAAMKtx7oDAAFAQA1AAQKfzYAAhUACgpOI3sIAIQDABUACgpOI3sIAIQDAAAA.Lavabursting:BAAANQAECgMIAwABNQAFFAUIBgAbACUUAA==.Laydout:BAAANQADCgQIBAABNQAECgcIEQADAAAAAA==.Laydoutyota:BAAANQAECgcIEQAAAA==.Laymow:BAAANQAECgQJBAABNQAECgkJGAAjADscAA==.',
Le='Levity:BAAANQAECggIBQAAAA==.',
Li='Lilea:BAABNQAECn8yAAMEAAoKSRJjPgBgAQAJAAcKyhM3qAC1AQAEAAcKPgpjPgBgAQAAAA==.Lilfaart:BAAANQAECggIBAAAAA==.Lilotterine:BAAANQAECgMIAwAAAA==.Lindisalvia:BAAANQADCggIEQAAAA==.Lionsmane:BAAANQADCgYIBgAAAA==.',
Lo='Loosemorals:BAACNQAFFH8LAAIPAAQK5g2PCAAFAQAPAAQK5g2PCAAFAQA1AAQKfygAAw8ACgqNGLkQAJ8CAA8ACgqNGLkQAJ8CACYAAQoQFHI6ADwAAAAA.Lootgoblin:BAABNQAECn8qAAICAAkKPBmCkQBdAgACAAkKPBmCkQBdAgAAAA==.Lortherian:BAAANQAECgYIEwAAAA==.',
Lu='Lunatique:BAAANQADCgQIBAAAAA==.',
['Lä']='Läwlbringer:BAABNQAECn8aAAIcAAkKyRAplwD1AQAcAAkKyRAplwD1AQAAAA==.',
Ma='Mabritoe:BAACNQAFFH8HAAIYAAQK1SN3CgBZAQAYAAQK1SN3CgBZAQA1AAQKfyMAAxgACQrMJJwPAAQDABgACArMJJwPAAQDAB0ACAqSCa4iALQBAAE1AAUUBwgYABYAhRUA.Maccabee:BAAANQAECgEIAQAAAA==.Magooh:BAAANQADCgcIBwABNQAECgcICQADAAAAAA==.Malison:BAAANQADCgUIBAAAAA==.Mangle:BAAANQADCgUIBQAAAA==.Mania:BAAANQADCgYICgABNQAECgkJFwARAPEZAA==.Mareth:BAAANQADCgIIAgAAAA==.Mathath:BAABNQAECn8lAAMMAAkKJBudPwAfAgAMAAkK1BmdPwAfAgAHAAMKYx92fQAEAQAAAA==.Mathoras:BAAANQADCgYIBgAAAA==.Maxboom:BAAANQAECgMIAwAAAA==.Mayaho:BAAANQAECgQIEQABNQAECgcICQADAAAAAA==.Maylee:BAABNQAECn8gAAIGAAoKPQ5YFQDVAQAGAAoKPQ5YFQDVAQAAAA==.',
Me='Meandean:BAAANQAECgUICgAAAA==.Meatier:BAAANQAECgQICQABNQAECgkJFwARAPEZAA==.Meenako:BAAANQAECgEIAQAAAA==.Mellinia:BAAANQADCgEIAQAAAA==.',
Mi='Miltonroe:BAABNQAECn8rAAIkAAkKaAwAGADoAQAkAAkKaAwAGADoAQAAAA==.Miltonroé:BAAANQAECgQIBAABNQAECgkJKwAkAGgMAA==.Mixing:BAAANQADCgIJAgAAAA==.',
Mo='Monnz:BAAANQADCgUIBQAAAA==.Monsterskill:BAAANQAECgYIBwAAAA==.Moonerva:BAABNQAECn8cAAIWAAcKHQyiNgDxAAAWAAcKHQyiNgDxAAAAAA==.Morana:BAAANQAECgMIBQAAAA==.',
Mu='Munchinmuff:BAAANQAECgQIBQAAAA==.',
Mv='Mvqchx:BAAANQADCgEIAQAAAA==.',
My='Myrolous:BAAANQADCgQIBAAAAA==.',
['Mã']='Mãrtrydóm:BAAANQAECgEIAQAAAA==.',
['Mì']='Mìssy:BAAANQAECgEIAQAAAA==.',
Na='Namiin:BAAANQADCgUIBQAAAA==.Namikaze:BAAANQAECgIIBAAAAA==.Natara:BAAANQADCgYICgAAAA==.Naughtye:BAAANQAECgQIBQAAAA==.Nave:BAAANQAECgcICAAAAA==.',
Ne='Nelfsfault:BAAANQADCggJFwAAAA==.Nerotappo:BAAANQABCgIIAgAAAA==.',
Ni='Ninja:BAAANQADCgYJBgAAAA==.',
No='Nobacon:BAAANQADCgIIAgAAAA==.Noshaku:BAAANQAECgUICAAAAA==.Notanorc:BAABNQAECn8xAAMKAAoKBhDxUgCKAQAKAAoK7QzxUgCKAQARAAUKMRO4FQBAAQAAAA==.',
Od='Odium:BAAANQAECgIIAgAAAA==.',
Oh='Ohrolam:BAABNQAECn8xAAMCAAoKNwnb4gDDAQACAAoKnwfb4gDDAQABAAQKxwqsKgCkAAAAAA==.',
Ok='Okasan:BAAANQAECgQICAABNQAECgYIFgAaAMQRAA==.',
Or='Oromis:BAAANQAECgYIBgABNQAFFAUIBgAbACUUAA==.',
Ot='Ottersdemons:BAAANQAECgMIAwAAAA==.',
Pa='Palthur:BAAANQAECgMICQAAAA==.Paradoxis:BAAANQABCgIIBAAAAA==.Passionate:BAAANQAECgEIAQAAAA==.',
Ph='Phatmidas:BAABNQAECn8tAAIcAAoKARekOwAMAgAcAAoKARekOwAMAgAAAA==.Phrozenpally:BAAANQAECgQICwABNQAECgcICQADAAAAAA==.',
Pi='Pika:BAAANQAECgEIAQABNQAFFAUIEAAHAGYXAA==.Pinbull:BAAANQADCgEIAQAAAA==.Pinkponythug:BAAANQAECgcICQABNQAFFAQICwAPAOYNAA==.',
Pl='Plagueground:BAACNQAFFH8bAAQLAAcKeCD8AQA9AgALAAYKXCP8AQA9AgAHAAIK5xRpJQBmAAAMAAEKsA9hJAA7AAA1AAQKfz0ABAsACgoxJnkCAMEDAAsACgoxJnkCAMEDAAcAAgrlJZGcAKEAAAwAAQpDFmdgAEsAAAAA.Plutonyus:BAAANQAECgMIBAAAAA==.',
Po='Poc:BAAANQAECgUICQAAAA==.Porterhaus:BAAANQADCggICAABNQAFFAUICQATAJ8NAA==.Pounces:BAABNQAECn9CAAInAAoKnyX2AABNAwAnAAoKnyX2AABNAwAAAA==.',
Pr='Prózak:BAAANQADCgYIBgABNQAECgoKKwAZAJUVAA==.Prôzak:BAABNQAECn8rAAIZAAoKlRXRFgBGAgAZAAoKlRXRFgBGAgAAAA==.',
Ps='Psychomidget:BAAANQAECggIDgAAAA==.',
Pu='Puetrid:BAACNQAFFH8JAAMTAAUKnw19DwDXAAATAAUKGwp9DwDXAAAUAAIKRA/+DwCUAAA1AAQKfygAAxQACgpgGPIFALICABQACQrXFfIFALICABMABArfGNpkADgBAAAA.Purble:BAAANQADCgIIAgAAAA==.Puufrumslli:BAAANQAECgcIEQAAAA==.',
Ra='Rageinglight:BAAANQAECgMIBQAAAA==.Rakku:BAAANQABCgcJBgAAAA==.Rautha:BAABNQAECn8cAAIcAAgKBBJDqQDNAQAcAAgKBBJDqQDNAQAAAA==.Rayl:BAAANQAECgEIAQAAAA==.',
Re='Rekt:BAABNQAECn8XAAImAAkKNBEmBgDbAQAmAAkKNBEmBgDbAQAAAA==.',
Rh='Rhaegon:BAABNQAECn8tAAIIAAkKCBxGBQDeAgAIAAkKCBxGBQDeAgAAAA==.',
Ri='Rimath:BAAANQADCggIEAAAAA==.',
Rn='Rng:BAAANQAECgcICQAAAA==.',
Ro='Rodstewart:BAABNQAECn8VAAMJAAkKZBQolADgAQAJAAgKhRUolADgAQAEAAMKsQsadQBmAAAAAA==.Ronz:BAAANQABCgEJAQAAAA==.Roofeo:BAAANQAECgEIAQABNQAECgkJLQAHAFcTAA==.Rotdaddy:BAABNQAECn8vAAIMAAoK8Ai4IABuAQAMAAoK8Ai4IABuAQAAAA==.',
Sa='Sabatikus:BAAANQAECgEIAQAAAA==.Salino:BAABNQAECn8cAAIWAAcK5wkWWwBmAQAWAAcK5wkWWwBmAQAAAA==.Salinoster:BAAANQAECgEIAQABNQAECgcIHAAWAOcJAA==.Sam:BAAANQAECgcIEQAAAA==.Sandorindis:BAAANQADCgYIBwAAAA==.Sarate:BAAANQADCggIEAAAAA==.Satral:BAAANQAECgYIBwAAAA==.Savannah:BAAANQAECgYIBwABNQAECgcIDwADAAAAAA==.Savvtwo:BAAANQADCgEIAQABNQAFFAcIIAAXANckAQ==.',
Se='Sezra:BAAANQADCggICAAAAA==.',
Sh='Shaetahn:BAAANQAECgEIAQAAAA==.Shamwowthorn:BAAANQADCgEIAQAAAA==.Shinanigans:BAABNQAECn82AAIcAAkKPB+ZNwDxAgAcAAkKPB+ZNwDxAgAAAA==.Shockbull:BAAANQADCgcJBwAAAA==.',
Si='Silverbäck:BAAANQAECgYIDAABNQAECgYIBgADAAAAAA==.Silverslam:BAAANQAECgIIAgABNQAECgYIBgADAAAAAA==.',
Sk='Skurge:BAAANQAECgYIEwAAAA==.',
Sn='Snacks:BAAANQADCgEIAQABNQAECgcIEQADAAAAAA==.Snuffles:BAAANQADCgYIBgAAAA==.',
So='Solstis:BAAANQAECgUICQAAAA==.Soranwena:BAABNQAECn8fAAIjAAoKlRVaFgAEAgAjAAoKlRVaFgAEAgAAAA==.Sorros:BAAANQAECgQIBQAAAA==.',
Sp='Spacegoat:BAAANQAECgMIAwAAAA==.Spfzero:BAAANQAECgEIAQAAAA==.Spookybuns:BAAANQAECggIBQAAAA==.',
St='Sticksy:BAAANQADCgYIBgAAAA==.Stonebeard:BAAANQAECgQIBgAAAA==.Stârlèss:BAAANQADCgYIBwAAAA==.',
Su='Subtox:BAAANQAECgcIDQAAAA==.',
Sw='Swedishfish:BAAANQAECgEIAQABNQAECgkJHQAfAP4dAA==.',
['Sá']='Sálúd:BAAANQAECgcIEQAAAA==.',
['Sê']='Sêp:BAAANQAECgIIAgAAAA==.',
Ta='Tarhealeon:BAAANQAECgYIDgAAAA==.Tarvuspls:BAABNQAECn8dAAMJAAgKZBNzWgCOAQAJAAgKZBNzWgCOAQAEAAUK7QU+VgDNAAAAAA==.',
Te='Teemawthy:BAAANQADCgYIBgAAAA==.Temozo:BAAANQADCgIIAgAAAA==.',
Th='Thabigone:BAAANQAECgIIAgAAAA==.Theceo:BAAANQADCgYIDgAAAA==.Thorb:BAAANQAECgcIDgABNQAFFAUIEAAHAGYXAA==.',
Ti='Ticklemebutt:BAAANQAECgcIEgAAAA==.Tiewaz:BAAANQAECggIEgAAAA==.',
To='Tolun:BAABNQAECn8rAAIBAAoKfBtWAgCfAgABAAoKfBtWAgCfAgAAAA==.Tonarui:BAAANQAECgQICgAAAA==.Tosan:BAABNQAECn8WAAIaAAYKxBEfFQAnAQAaAAYKxBEfFQAnAQAAAA==.Toughcookie:BAABNQAECn8gAAMcAAoKwApqbwB1AQAcAAoKwApqbwB1AQAVAAIKPgR2FwFGAAAAAA==.',
Tr='Treeplague:BAABNQAECn8kAAMgAAgKsw4/BABsAQAgAAgKsw4/BABsAQAfAAIK4QQ3bQBQAAAAAA==.',
Tu='Turn:BAACNQAFFH8gAAQUAAgKCBGDAgD1AAASAAQK+g00AgAAAQAUAAMK7RODAgD1AAATAAMKhhBfIgDnAAA1AAQKfzEABBQACgpwItwPAAACABMABwpuH811AAECABQABwpPF9wPAAACABIABQqFJS4KANcBAAAA.Turtleduck:BAAANQADCgcIDAABNQAECgoKGwAGAPYVAA==.',
Ty='Tyla:BAAANQAECggICAAAAA==.Typhis:BAAANQAECgQIBAAAAA==.',
['Tì']='Tìewaz:BAAANQAECgQIBgABNQAECggIEgADAAAAAA==.',
Um='Umbryx:BAAANQAECgEIAQAAAA==.',
Un='Unagi:BAABNQAECn8tAAIkAAoKQg05DgCrAQAkAAoKQg05DgCrAQAAAA==.',
Va='Valdir:BAAANQAECggIBgAAAA==.Vasomir:BAAANQABCgIIAQAAAA==.',
Ve='Venomstrikes:BAAANQADCgcIBwAAAA==.Venøm:BAAANQAECgEIAQAAAA==.Vexxen:BAAANQAECgIIAgAAAA==.',
Vi='Viscerion:BAAANQAECgYIEAAAAA==.',
Wh='Whoarlock:BAAANQAECgEIAQAAAA==.',
Wi='Wizzyy:BAAANQADCgUIBQAAAA==.',
Wo='Wo:BAAANQADCgEIAQABNQAECgcICQADAAAAAA==.',
Xe='Xelinia:BAACNQAFFH8RAAMfAAUKoQd6DAAcAQAfAAQKoQd6DAAcAQAhAAEK9AIIOAA/AAA1AAQKfy4AAx8ACgr4HAcMACQCAB8ACgr4HAcMACQCACEAAQrfAV8KAR8AAAAA.',
Xu='Xuefeng:BAACNQAFFH8QAAIoAAUKChBBCgAiAQAoAAUKChBBCgAiAQA1AAQKf0AAAigACgptH+0LABcDACgACgptH+0LABcDAAAA.',
Ya='Yahwae:BAAANQAECgQICwABNQAECgoKMwAUAOoTAA==.',
Yc='Ycephyre:BAAANQAECgcICQAAAA==.',
Ye='Yenchmeister:BAACNQAFFH8aAAIKAAcKDBfvBgBSAgAKAAcKDBfvBgBSAgA1AAQKfy0AAgoACgpSJEcdAEIDAAoACgpSJEcdAEIDAAAA.',
Yo='Yomahma:BAAANQAECgUIBgAAAA==.',
Yu='Yuta:BAAANQADCgQIBAAAAA==.',
Zd='Zdervish:BAABNQAECn8bAAIYAAcKihojKQBKAgAYAAcKihojKQBKAgAAAA==.',
Ze='Zeffira:BAAANQAECgUIAwAAAA==.Zellda:BAAANQAECgQIBAABNQAECgoKNwAJAL8cAA==.',
Zi='Zilvanic:BAABNQAECn8aAAQZAAkKjwuSIgDoAAAZAAgKHQ2SIgDoAAAVAAMK9wZupABuAAAcAAEKAABodgEAAAAAAA==.Zilvanion:BAACNQAFFH8FAAMTAAQKXQVbHQB8AAATAAMKVQVbHQB8AAASAAEKbAV6CgBFAAA1AAQKfzoAAhMACgpgFhsvAPIBABMACgpgFhsvAPIBAAAA.',
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
