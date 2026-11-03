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

local lookup = {'Druid-Restoration','Monk-Mistweaver','Unknown-Unknown','DeathKnight-Blood','Paladin-Protection','Paladin-Retribution','Warrior-Arms','Hunter-Marksmanship','Hunter-BeastMastery','Warlock-Destruction','Warlock-Demonology','Monk-Brewmaster','Mage-Fire','Mage-Arcane','Rogue-Subtlety','DeathKnight-Frost','Priest-Holy','Priest-Shadow','DemonHunter-Havoc','Paladin-Holy','DeathKnight-Unholy','Druid-Feral','Mage-Frost','Shaman-Elemental','Warrior-Fury','Warrior-Protection','Druid-Balance','Shaman-Restoration','Shaman-Enhancement','Rogue-Assassination','Druid-Guardian','Warlock-Affliction','DemonHunter-Devourer','Evoker-Augmentation','Monk-Windwalker','Priest-Discipline','Hunter-Survival',}
local provider = {region='US',realm='Gorefiend',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Abracanoobra:BAABNQAECn8bAAIBAAoKTxb5IAAhAgABAAoKTxb5IAAhAgAAAA==.Abuki:BAACNQAFFH8OAAICAAYKuRHeAgCaAQACAAYKuRHeAgCaAQA1AAQKfysAAgIACgrzH28JAPQCAAIACgrzH28JAPQCAAAA.',
Ai='Aiforix:BAAANQADCgcJBwAAAA==.',
Ak='Akagane:BAAANQADCgYIDAAAAA==.Akalla:BAAANQAECgcIDQAAAA==.',
Al='Alfuric:BAAANQAECgQIBwAAAA==.Aliviana:BAAANQADCgYIBgABNQAECgQIEAADAAAAAA==.Althraniir:BAAANQAECgEIAwAAAA==.Altrois:BAABNQAECn88AAIEAAoKcSEPCgBlAwAEAAoKcSEPCgBlAwAAAA==.',
Am='Amatrake:BAACNQAFFH8WAAIFAAcKdxR5AwDKAQAFAAcKdxR5AwDKAQA1AAQKfzEAAgUACgp5HtUNAL0CAAUACgp5HtUNAL0CAAAA.Amatsano:BAEANQAECgcIDQAAAA==.Amorsith:BAABNQAECn8yAAMFAAoK6RxdCQB5AgAFAAoK6RxdCQB5AgAGAAYKwQxS9AA0AQAAAA==.Amurine:BAAANQAECgcICQAAAA==.Amyst:BAABNQAECn8jAAIHAAgKbSFHSQCuAgAHAAgKbSFHSQCuAgAAAA==.',
An='Anahita:BAAANQAECgEIAgAAAA==.Angrycrack:BAAANQAECgcIEAAAAA==.Angryspace:BAAANQADCgQIBAAAAA==.Angusill:BAAANQADCggIFQAAAA==.Animuggus:BAEANQAECgcICQAAAA==.Anjunabeets:BAACNQAFFH8ZAAMIAAgKrBNyBgDuAQAIAAcKwRNyBgDuAQAJAAEKRBNEMABeAAA1AAQKfyEAAwgACgpcJEMaAIMCAAgACQoiJEMaAIMCAAkAAgoTGnQuAZAAAAAA.Anthran:BAABNQAECn8lAAMKAAoKqw0nKgArAQAKAAUKaRAnKgArAQALAAcKoQj04QAFAQAAAA==.',
Ao='Ao:BAAANQAECgIIAwAAAA==.',
Ap='Apexlegend:BAAANQAECgQIBAAAAA==.',
Ar='Arakin:BAAANQABCggJCgAAAA==.Arcon:BAAANQAECgQICQABNQAECgoKHwAMAJwYAA==.Arcscythe:BAABNQAECn8gAAMNAAoKVhE4AgA8AgANAAgK0BQ4AgA8AgAOAAIK5wZ7HAFjAAAAAA==.Arctron:BAAANQAECgYIDgABNQAECgoKHwAMAJwYAA==.Arthanos:BAAANQADCgcIBgABNQAECggIEAADAAAAAA==.Artoo:BAABNQAECn8WAAIPAAoKcxZWJQA8AgAPAAoKcxZWJQA8AgAAAA==.',
As='Ashesonly:BAABNQAECn9FAAIQAAoKAByCGQBMAgAQAAoKAByCGQBMAgAAAA==.Assaulter:BAAANQADCgIIAgABNQAECgoKQQAJABwhAA==.',
Au='Auramis:BAABNQAECn83AAMRAAoK9iFrGAAUAwARAAoK9iFrGAAUAwASAAIKsQfxQgBwAAAAAA==.',
Az='Azariel:BAACNQAFFH8GAAITAAMKMxajDwCYAAATAAMKMxajDwCYAAA1AAQKfzwAAhMACgrkIdMGAA0DABMACgrkIdMGAA0DAAAA.Azrayel:BAAANQADCgUIBQAAAA==.',
Ba='Babydilla:BAACNQAFFH8WAAIEAAcKEiM0AwBkAgAEAAcKEiM0AwBkAgA1AAQKfy8AAgQACgqYJBsLAFsDAAQACgqYJBsLAFsDAAAA.Balgith:BAABNQAECn8mAAMUAAgKIQ3rbwA0AQAUAAgKIQ3rbwA0AQAGAAMKcgMeXgE+AAAAAA==.Balrus:BAAANQADCgEJAQAAAA==.Bam:BAAANQADCggICAAAAA==.Bannagad:BAABNQAECn8cAAMGAAkKuQkyuQCrAQAGAAkKuQkyuQCrAQAUAAUKhAl3vQABAQAAAA==.Barthoun:BAABNQAECn8WAAIHAAoKCA1TXACxAQAHAAoKCA1TXACxAQAAAA==.Battleburger:BAAANQAECgEIAQAAAA==.Bauchelaine:BAAANQAECgEIAQAAAA==.Bawitaba:BAAANQAECgUJDQAAAA==.',
Be='Benchknight:BAACNQAFFH8OAAQQAAcKXQ55DQAGAQAQAAUKwQt5DQAGAQAVAAEKzRgbHQBfAAAEAAEKAABcMwAuAAA1AAQKf0AABBAACgpwH1sSAPoCABAACgo3H1sSAPoCABUACQp/Gv9IAPMBAAQABQqRHZA5ADMBAAAA.Beoron:BAACNQAFFH8KAAIWAAYKbBwQAgAVAQAWAAYKbBwQAgAVAQA1AAQKf0MAAhYACgpMJkIBAFMDABYACgpMJkIBAFMDAAAA.Bettyßastion:BAABNQAECn8uAAIGAAkKKRYAbAC6AQAGAAkKKRYAbAC6AQAAAA==.Bettyßlithe:BAAANQAECgUIBQABNQAECgkJLgAGACkWAA==.',
Bi='Big:BAAANQAECgQIBwAAAA==.Bigflex:BAAANQAECggIDwAAAA==.Bio:BAAANQAECggICwAAAA==.Bioenergy:BAAANQAECgEIAgABNQAECggICwADAAAAAA==.Biolysis:BAAANQAECgQIBAABNQAECggICwADAAAAAA==.',
Bl='Blesus:BAAANQAECgQIBAAAAA==.Blowtortch:BAABNQAECn8uAAMXAAoK4AnAEgAjAQAOAAoK+wcilQBOAQAXAAgKngjAEgAjAQAAAA==.',
Bo='Bolverkr:BAAANQAECgEIAQAAAA==.',
Br='Brageus:BAABNQAECn8fAAIYAAoKnhFbVgBJAQAYAAoKnhFbVgBJAQAAAA==.Brainmatter:BAAANQADCgMIBAAAAA==.Brainstorm:BAAANQAECgQIBAAAAA==.Braintumor:BAABNQAECn8eAAIVAAcKIgkGfgAkAQAVAAcKIgkGfgAkAQAAAA==.Brontag:BAABNQAECn8qAAQZAAoK8B1gBwCDAgAZAAkKRiBgBwCDAgAHAAgKeBY6oADMAQAaAAEKAACPQQA5AAAAAA==.Bruus:BAAANQAECgEIAQAAAA==.',
Bu='Bugles:BAAANQAECgEIAQAAAA==.Buns:BAAANQAECgEIAQAAAA==.Butternutter:BAAANQADCggIDQABNQAECgYIBgADAAAAAA==.',
['Bé']='Béllas:BAAANQADCgYIBgAAAA==.',
Ca='Caissa:BAAANQADCgYIBgAAAA==.Caliboy:BAAANQAECgEIAQABNQAECgIIBAADAAAAAA==.Calißoy:BAAANQAECgIIBAAAAA==.Caneki:BAABNQAECn8aAAMRAAkKGRjXUQAuAgARAAkKGRjXUQAuAgASAAEKAAA+lAATAAAAAA==.Canekii:BAAANQAECgYIEQABNQAECgkJGgARABkYAA==.Cannyon:BAAANQADCgQIBAAAAA==.Casini:BAAANQAECgcIBwAAAA==.Cathrîne:BAAANQADCggICAAAAA==.',
Ce='Celeice:BAAANQADCgUIBQAAAA==.Celticankou:BAAANQAECgUIBQAAAA==.Cerberus:BAACNQAFFH8JAAIJAAQK/R2ZFAAdAQAJAAQK/R2ZFAAdAQA1AAQKfzcAAgkACgqKJTIIADcDAAkACgqKJTIIADcDAAAA.Ceruledge:BAAANQAECgEIAgABNQAECgoKNQASAMofAA==.',
Ch='Chaboomy:BAECNQAFFH8VAAIbAAcKcRWUCgDMAQAbAAcKcRWUCgDMAQA1AAQKf0EAAhsACgrOJPICAFYDABsACgrOJPICAFYDAAAA.Chidori:BAAANQADCgUIBQAAAA==.Chips:BAABNQAECn81AAMHAAkKHBB0nADVAQAHAAkKwg90nADVAQAaAAUKtgoXIgC1AAAAAA==.',
Co='Cobblerjr:BAAANQAECgIIAgAAAA==.Coffeemaker:BAABNQAECn8nAAQOAAoKqhjvjgBhAgAOAAoKqhjvjgBhAgANAAYKzQ/gBABMAQAXAAEKjh0mSAA0AAAAAA==.Conyay:BAAANQAECggIEAAAAA==.Cowploww:BAAANQAECgMIAwAAAA==.',
Cr='Croissant:BAABNQAECn8iAAILAAgKwx7aOACpAgALAAgKwx7aOACpAgAAAA==.Cräsh:BAAANQADCgMIAwAAAA==.',
Cy='Cycko:BAAANQADCgUIBQAAAA==.Cytheria:BAAANQADCggIDwABNQAECggIEAADAAAAAA==.',
Da='Dalidan:BAAANQAECgUIBgABNQAFFAEIAQADAAAAAA==.Dalórien:BAAANQADCgUICgABNQAECgMIBAADAAAAAA==.Damaerin:BAAANQAECgUIDwAAAA==.Darkis:BAABNQAECn8YAAMBAAoKLQpxOgBMAQABAAkK/AZxOgBMAQAbAAgKJgQQbgASAQAAAA==.Darkseph:BAAANQAECgYIEgAAAA==.Darthjarjar:BAAANQADCgMIAwAAAA==.Dayy:BAACNQAFFH8SAAMYAAcKBBpuCgDEAQAYAAUKhhtuCgDEAQAcAAMKfAk/GwCVAAA1AAQKf0UABBgACgpEJt4GALIDABgACgpEJt4GALIDABwAAgoYDPD5AHcAAB0AAQphBhYwADgAAAAA.',
De='Deathsteak:BAAANQADCggIDQAAAA==.Deepman:BAABNQAECn8wAAIeAAoKWhUpDQDTAQAeAAoKWhUpDQDTAQABNQAECgoKQQAJABwhAA==.Delessia:BAAANQAECggICAAAAA==.Demonesque:BAAANQAECgEIAQAAAA==.Desy:BAAANQAECgYIDQAAAA==.',
Di='Diggersby:BAACNQAFFH8OAAIfAAYKdCBiAADSAQAfAAYKdCBiAADSAQA1AAQKfyMAAh8ACgr6ILwHAAcDAB8ACgr6ILwHAAcDAAAA.Disastrous:BAACNQAFFH8NAAIJAAUKXQ1/EgDcAAAJAAUKXQ1/EgDcAAA1AAQKfzIAAgkACgq4FpZIAAMCAAkACgq4FpZIAAMCAAAA.',
Do='Doomangel:BAAANQAECgcIBwAAAA==.Doson:BAAANQAECgUIDAAAAA==.',
Dr='Dracthyr:BAAANQAECgQIBQABNQAECggICwADAAAAAA==.Drago:BAAANQAECgEIAQABNQAECgQIBAADAAAAAA==.Dragonbison:BAAANQAECgYICwAAAA==.Druidtime:BAAANQADCggIFQAAAA==.Drunkenmasta:BAAANQADCgIIAgABNQAECgoKQQAJABwhAA==.',
['Dø']='Døc:BAABNQAECn9DAAMcAAoKVRlSNgAQAgAcAAoKVRlSNgAQAgAYAAkKJROORwB9AQAAAA==.',
Eg='Eggland:BAAANQAECgUICAAAAA==.',
Ei='Eielmolate:BAACNQAFFH8UAAILAAcKEQ1zCQDSAQALAAcKEQ1zCQDSAQA1AAQKfy8AAwsACgoVH48fAAYDAAsACgoVH48fAAYDAAoAAgrqDl1hAGIAAAAA.',
El='Eldranus:BAAANQAECgcIDQAAAA==.',
En='Enimed:BAABNQAECn8+AAIEAAoK8R12DwCIAgAEAAoK8R12DwCIAgAAAA==.',
Eu='Eugenn:BAAANQADCggIEwAAAA==.',
Ev='Evil:BAACNQAFFH8JAAQKAAQKnxYSDwCXAAALAAIKPBdfLgCdAAAKAAIKIhASDwCXAAAgAAEKAAC0EAAAAAA1AAQKfywABAoACgp+IDMbAJMBAAsABwp4HkpkAC0CAAoABQpBIDMbAJMBACAABAp8HK8SAB8BAAAA.',
Fa='Falarion:BAAANQAECgcICwAAAA==.Fam:BAABNQAECn81AAIOAAkKgyKYJgBGAwAOAAkKgyKYJgBGAwAAAA==.Fatherseph:BAAANQAECgUICwABNQAECgYIEgADAAAAAA==.',
Fi='Finkymcbinky:BAABNQAECn8cAAIOAAkKgA37cwCXAQAOAAkKgA37cwCXAQAAAA==.Finroz:BAAANQADCgQIBAAAAA==.Fisterdobble:BAABNQAECn87AAIXAAoKHhpWBgCeAgAXAAoKHhpWBgCeAgAAAA==.',
Fl='Fleurdelys:BAAANQADCggIPQAAAA==.Florella:BAAANQADCgUIBwAAAA==.',
Fo='Foidhater:BAAANQADCgEIAQAAAA==.Forestpump:BAAANQAECgEIAQABNQAECgcICQADAAAAAA==.Forgedd:BAAANQAECgUIBQAAAA==.Forgeddemon:BAABNQAECn82AAIMAAoKOgyOCQB+AQAMAAoKOgyOCQB+AQAAAA==.',
Fr='Frogkid:BAAANQAECgQIBAAAAA==.Frostborne:BAABNQAECn8uAAIVAAkKJhtSGQDuAQAVAAkKJhtSGQDuAQAAAA==.Frostheart:BAAANQABCgYIDAAAAA==.Frostystomp:BAAANQAECgcIDwABNQAFFAYICgAWAGwcAA==.Frozenpickle:BAAANQADCgYIBwABNQAECgQICAADAAAAAA==.',
Fu='Funeral:BAABNQAECn8fAAILAAoKUwwlVQCbAQALAAoKUwwlVQCbAQABNQAECgoKQQAJABwhAA==.',
Ga='Gamjee:BAAANQAECgcIDQAAAA==.',
Ge='Gerkindk:BAAANQADCggICAABNQAECgEIAgADAAAAAA==.Gerkindrd:BAAANQAECgEIAgAAAA==.',
Gh='Ghostly:BAAANQADCggJCQAAAA==.',
Gl='Glyndin:BAAANQAECgcIBwAAAA==.',
Go='Goodboy:BAAANQAECgMIAwABNQAFFAYIDgAfAHQgAA==.Goodolrúss:BAAANQADCgYIEAAAAA==.',
Gr='Grackalackin:BAAANQAECgUIEwAAAA==.Grassfedgeez:BAAANQAECgIIAgAAAA==.Greenxgoblin:BAAANQADCgEJAQAAAA==.Grizmaus:BAABNQAECn8cAAITAAkKOQnKMQBNAQATAAkKOQnKMQBNAQAAAA==.',
Gu='Guilliman:BAABNQAECn8pAAIHAAkKvBxCXQB0AgAHAAkKvBxCXQB0AgAAAA==.Gulaj:BAABNQAECn8sAAIJAAoKhxO9dwAgAgAJAAoKhxO9dwAgAgAAAA==.Guldaniel:BAAANQADCggIDQAAAA==.',
['Gë']='Gënesis:BAAANQAECgYICwAAAA==.',
Ha='Haloro:BAAANQADCgEIAQAAAA==.Ham:BAAANQAECgcICwAAAA==.',
He='Healgimp:BAABNQAECn81AAIRAAoKPx8YKAB5AgARAAoKPx8YKAB5AgAAAA==.',
Hi='Hiruken:BAAANQADCgYIFAAAAA==.',
Ho='Hope:BAEBNQAECn8nAAMfAAoKMh45BwCwAgAfAAoKMh45BwCwAgABAAoKcBKnHwAvAgABNQAFFAcIGQARAKQTAA==.Hortzel:BAAANQAECgcIDQAAAA==.Hotrollz:BAAANQADCgUIBQABNQAECggILgASACAVAA==.Howdoidie:BAAANQAECggIDwAAAA==.Howdoitotem:BAABNQAECn8jAAMYAAoKiBl6MgCwAgAYAAoKiBl6MgCwAgAcAAMK3geW+QB3AAAAAA==.',
Hu='Hulkx:BAAANQAECgQICgAAAA==.Humaa:BAABNQAECn85AAIGAAoKMhluVgDzAQAGAAoKMhluVgDzAQAAAA==.Huntus:BAABNQAECn8zAAIJAAkKdh2ZOwC3AgAJAAkKdh2ZOwC3AgAAAA==.',
Hy='Hyperiøn:BAAANQADCgIIAgAAAA==.',
Ib='Ibcrootbeer:BAAANQAECgEIAQAAAA==.',
Ic='Icenaria:BAAANQADCggICAAAAA==.Icewiz:BAAANQABCgUIBQABNQAECgUIDAADAAAAAA==.Icy:BAABNQAECn8eAAIHAAkKYReFYwBkAgAHAAkKYReFYwBkAgAAAA==.',
Im='Impale:BAAANQADCgQIBwAAAA==.Imperio:BAAANQAECgMIBQAAAA==.Impostor:BAABNQAECn89AAISAAoKmR9HCQCpAgASAAoKmR9HCQCpAgAAAA==.',
Iz='Izuu:BAABNQAECn8dAAIJAAkKlhCwWgDPAQAJAAkKlhCwWgDPAQAAAA==.',
['Iç']='Içyhot:BAAANQADCgEIAQAAAA==.',
Ja='Jabrick:BAAANQAECgQIBAAAAA==.Jattin:BAAANQADCgYIDAAAAA==.Jawnski:BAAANQADCgUICQAAAA==.',
Ji='Jibjabjibjab:BAACNQAFFH8GAAMPAAQKnxGKEQDYAAAPAAQKnxGKEQDYAAAeAAEKIwtJIABIAAA1AAQKfzQAAx4ACgo0HQciAAkBAA8ACgovHBYbAP4BAB4ABQrdGgciAAkBAAAA.',
Jo='Joey:BAAANQADCgcIBwAAAA==.Joharin:BAABNQAECn8mAAILAAgKPw3udQBBAQALAAgKPw3udQBBAQAAAA==.',
Jt='Jtabb:BAAANQABCgYICQAAAA==.',
Ju='Juroda:BAAANQADCgYIBgABNQAECgYIEgADAAAAAA==.',
Ka='Kankiro:BAAANQAECgUICAAAAA==.Kanstentin:BAAANQADCggICAAAAA==.Karram:BAAANQADCgQIBAAAAA==.',
Kc='Kcup:BAAANQADCgYIBgAAAA==.',
Ke='Kelamess:BAABNQAECn8bAAMBAAYKrgg6UQDEAAABAAYKrgg6UQDEAAAbAAUKrgSkhAC/AAAAAA==.Kelemvor:BAABNQAECn8WAAIhAAoK+wxaLwDHAQAhAAoK+wxaLwDHAQAAAA==.Ken:BAAANQADCgYIBgAAAA==.Keyzer:BAAANQAECggICQAAAA==.',
Kf='Kfp:BAAANQABCgEIAQAAAA==.',
Kh='Khandak:BAACNQAFFH8GAAIEAAQKSgoVFAChAAAEAAQKSgoVFAChAAA1AAQKfyUAAgQACgq9GugzAD0CAAQACgq9GugzAD0CAAAA.',
Ki='Kimmy:BAAANQAECgYICwAAAA==.',
Kl='Kleenex:BAABNQAECn8sAAIXAAoK+RZWCABeAgAXAAoK+RZWCABeAgAAAA==.',
Ko='Koldiss:BAAANQAECgIIAgAAAA==.',
Kr='Krueger:BAAANQAECgcIDgABNQAECgoKHAAQAGQTAA==.',
Ku='Kurisutina:BAAANQAECgYIDAABNQAFFAQICQAcAHcMAA==.Kushiel:BAAANQAECgEIAQAAAA==.',
Le='Leadblaster:BAABNQAECn9BAAIJAAoKHCG/FgBAAwAJAAoKHCG/FgBAAwAAAA==.Leethalfu:BAABNQAECn8cAAIMAAoKVBeqCQCEAgAMAAoKVBeqCQCEAgAAAA==.Leethalrot:BAAANQAECgEIAgABNQAECgoKHAAMAFQXAA==.Legosi:BAABNQAECn8hAAILAAoKGw09awBcAQALAAoKGw09awBcAQAAAA==.Leighroy:BAAANQABCgIIAgAAAA==.Lemegegen:BAABNQAECn84AAILAAoKGiC9FgCkAgALAAoKGiC9FgCkAgAAAA==.Leviosa:BAABNQAECn8YAAIhAAoKVh1YCwB8AgAhAAoKVh1YCwB8AgAAAA==.',
Lh='Lhux:BAACNQAFFH8HAAIJAAIKmApnHwCIAAAJAAIKmApnHwCIAAA1AAQKf0YAAgkACgowIGoUANkCAAkACgowIGoUANkCAAE1AAQKCgorACIAsBEA.Lhuxi:BAABNQAECn8rAAIiAAoKsBHRBQDaAQAiAAoKsBHRBQDaAQAAAA==.',
Li='Lilbokchoy:BAAANQABCgQIBAAAAA==.Linkin:BAAANQABCgMIAwAAAA==.',
Lo='Loneassassin:BAAANQADCgQIBAAAAA==.Lorani:BAACNQAFFH8HAAIbAAUKhSDlFwDsAAAbAAUKhSDlFwDsAAA1AAQKfzMAAhsACgr5JCQMAGoDABsACgr5JCQMAGoDAAAA.',
Lu='Luceean:BAAANQAECgIIAgAAAA==.Lurth:BAAANQADCgIIAgABNQAECgIIBAADAAAAAA==.',
Ly='Lyxxie:BAABNQAECn81AAMQAAoKbBvhIAAQAgAQAAoKbBvhIAAQAgAVAAUKCQvPjQDuAAAAAA==.',
Ma='Maelle:BAAANQAECgQIBAAAAA==.Mageus:BAAANQAECggICgAAAA==.Manafart:BAAANQADCgYIBgABNQAECgkJNQAHABwQAA==.Manbearpïg:BAABNQAECn8bAAMWAAgK3BJtEgBUAQAWAAgK3BJtEgBUAQAbAAQKJwtJXACHAAABNQAECgoKGAAIAAwmAA==.Matsumushi:BAABNQAECn8uAAMMAAkKzxPKDgAGAgAMAAgKWBbKDgAGAgAjAAgKdwa9LQD2AAAAAA==.',
Mc='Mcnastyy:BAAANQADCgYICgAAAA==.',
Me='Mefesto:BAABNQAECn8dAAIOAAkKvg+DtgAWAgAOAAkKvg+DtgAWAgABNQABCgQIBgADAAAAAA==.Mellore:BAAANQAECgIIAgABNQAFFAUIBwAbAIUgAA==.Melyna:BAAANQAECgIIAgABNQAECgcIHwAFAFgXAA==.Metsutan:BAACNQAFFH8IAAIPAAYKqRbMCABKAQAPAAYKqRbMCABKAQA1AAQKfz0AAg8ACQplIWIMAPsCAA8ACQplIWIMAPsCAAAA.',
Mi='Minphoria:BAAANQAECgEIAQAAAA==.Misfitgrimmy:BAAANQAECgMIAwAAAA==.',
Mo='Molathom:BAAANQAECgUICAAAAA==.Moonster:BAAANQAECgUICwAAAA==.Moppit:BAAANQAECgEIAQAAAA==.',
['Mâ']='Mâtthêw:BAAANQAECgMIBgAAAA==.',
Na='Naes:BAAANQADCgYIDAAAAA==.Nazuresh:BAAANQAECgEIAQABNQAECgcIHAARAPsfAA==.',
Ne='Necrodamus:BAAANQAECgYIEAAAAA==.Nekcrotic:BAABNQAECn8VAAMLAAgKshNunACfAQALAAcKuRJunACfAQAKAAIKIxClWAB2AAAAAA==.Nekromant:BAABNQAECn8gAAMKAAcKRA27SACmAAALAAYK2gm6xwA6AQAKAAMKiA27SACmAAAAAA==.Nelle:BAAANQABCggIDgAAAA==.Nemriel:BAAANQAECgUICAAAAA==.',
Ni='Nibbles:BAAANQAECgQJBgAAAA==.Nighthoe:BAAANQAECgQIBQAAAA==.Nintales:BAAANQAECgQICwAAAA==.',
No='Nohric:BAAANQAECgcIEwAAAA==.Nohshim:BAAANQAECgcICAAAAA==.Noobieone:BAAANQAECgIIAgAAAA==.Norsem:BAAANQAECgUIDgAAAA==.',
Nu='Nullmortis:BAAANQAECgEIAQAAAA==.',
Ny='Nymera:BAAANQAECgYICgABNQAECggIEAADAAAAAA==.',
['Nä']='Nämeless:BAAANQAECgMIBAAAAA==.',
Oh='Ohlorn:BAACNQAFFH8JAAIdAAcK/gyhAwA9AQAdAAcK/gyhAwA9AQA1AAQKfzoAAh0ACgoOJQwBAFoDAB0ACgoOJQwBAFoDAAAA.',
Ok='Oktar:BAAANQADCgUIBQAAAA==.',
On='Onenightstab:BAAANQAECgcICQAAAA==.Onfleek:BAAANQAECgUIEQAAAA==.',
Or='Orakrak:BAAANQADCgQIBAAAAA==.Oroku:BAAANQADCgQICAAAAA==.',
Ox='Oxtails:BAAANQADCgMIAwAAAA==.',
Oz='Ozzmodius:BAAANQAECgYICgAAAA==.',
Pa='Pakapunch:BAAANQADCgIIAgABNQAECgQIBAADAAAAAA==.Palysuk:BAAANQAECgEIAQAAAA==.Papier:BAAANQAECgYIBgAAAA==.Parsephone:BAACNQAFFH8VAAMBAAYKMh/eBADWAQABAAUKYx/eBADWAQAbAAQKgg7XDgDXAAA1AAQKf0IABAEACgp3JfIAANIDAAEACQpWJvIAANIDABsACgpMHB4NALICABYAAQoAAEhCADUAAAE1AAQKCgocAAIA/BQA.Parstout:BAABNQAECn8cAAICAAoK/BQXCwBMAgACAAoK/BQXCwBMAgAAAA==.Pawsitivity:BAABNQAECn81AAIYAAoK6SK0IAAIAwAYAAoK6SK0IAAIAwAAAA==.',
Pd='Pdbm:BAABNQAECn8gAAIGAAoKThpGUACkAgAGAAoKThpGUACkAgAAAA==.',
Pe='Petr:BAABNQAECn84AAMRAAoKHBrlMACkAgARAAoKHBrlMACkAgASAAEKAADqjgAcAAAAAA==.Pettigrew:BAAANQAECgYIBgAAAA==.Peut:BAABNQAECn8rAAIUAAoK6xs6LwCpAgAUAAoK6xs6LwCpAgAAAA==.',
Ph='Physix:BAAANQAECgUIBgAAAA==.',
Pi='Pipsqueak:BAAANQADCgcJCwAAAA==.Pitchntents:BAAANQAECgcJCwAAAA==.',
Po='Popped:BAAANQAECgQICAAAAA==.Porkins:BAABNQAECn84AAMQAAoKKR8cFgDaAgAQAAoKzx4cFgDaAgAVAAYKdxMMZgB5AQAAAA==.',
Pr='Priestus:BAAANQAECgIIAwAAAA==.',
Ps='Psyndra:BAEANQAFFAEIAQABNQAECgoKHwAcAEkhAA==.',
Py='Pyraxx:BAABNQAECn9EAAIXAAoKaSPJAACwAwAXAAoKaSPJAACwAwAAAA==.',
Qt='Qtwithabooty:BAACNQAFFH8YAAIhAAcKkRoBBAALAgAhAAcKkRoBBAALAgA1AAQKfzIAAiEACgqjJeIEAAMDACEACgqjJeIEAAMDAAAA.',
Qu='Quatermaine:BAAANQAECgUIDgAAAA==.',
Ra='Radovan:BAACNQAFFH8QAAMLAAYKgx/EFQBIAQALAAUKAiLEFQBIAQAKAAEKCBiBGgBQAAA1AAQKf1IAAwsACgovJh8LAPgCAAsACQoSJh8LAPgCAAoABQpDIM4aAJYBAAAA.Rayael:BAAANQAECgQIEgABNQAECgoKQwAOABIcAA==.Rayjax:BAAANQAECgQIAwAAAA==.Raìdèn:BAABNQAECn8cAAIRAAcK+x9lOwAVAgARAAcK+x9lOwAVAgAAAA==.',
Re='Replicate:BAAANQAECgIIAgAAAA==.',
Rh='Rhinne:BAABNQAECn8oAAMcAAkK6hL3lgBOAQAcAAgKJhH3lgBOAQAYAAYKBAiVxgAFAQAAAA==.',
Ri='Riddic:BAAANQADCgEIAQAAAA==.',
Ro='Roktar:BAAANQADCgcIDgABNQAECggIEAADAAAAAA==.Rosaelyia:BAAANQADCgYIBwABNQAECggIJgAJAA8bAA==.',
Ry='Ryanqt:BAAANQADCggIDQAAAA==.Ryanvoker:BAAANQADCgcIBwAAAA==.Ryanx:BAABNQAECn8cAAIUAAgK4SDqJADXAgAUAAgK4SDqJADXAgAAAA==.',
Sa='Samavati:BAABNQAECn8bAAICAAcKfQ7DJQBLAQACAAcKfQ7DJQBLAQAAAA==.Sarah:BAABNQAECn8wAAMRAAkKXiQBBACvAwARAAkKXiQBBACvAwAkAAMKngv6GwCHAAAAAA==.Saross:BAAANQADCggICAAAAA==.Sasori:BAACNQAFFH8MAAIPAAUKaghtCABwAQAPAAUKaghtCABwAQA1AAQKfygAAg8ACQotHAQNAKUCAA8ACQotHAQNAKUCAAAA.Sassyface:BAABNQAECn8+AAIKAAoK3A/4AwCtAQAKAAoK3A/4AwCtAQAAAA==.',
Sc='Scaledia:BAAANQAECgEIAQAAAA==.',
Se='Sellit:BAAANQAECgUIBgAAAA==.Seman:BAAANQADCgIIAgAAAA==.Semperfi:BAAANQABCgIIAgAAAA==.',
Sh='Shadowbourne:BAAANQAECggIBwABNQAFFAMIBgATADMWAA==.Shadowdin:BAABNQAECn8yAAIUAAoKtxwQJwDNAgAUAAoKtxwQJwDNAgAAAA==.Shamzilla:BAABNQAECn8oAAIYAAgKABtRNACnAgAYAAgKABtRNACnAgAAAA==.Shockblast:BAAANQAECgEIAQAAAA==.Shriike:BAAANQADCgYIBgAAAA==.Shuyinn:BAAANQAECggICAABNQAECgoKJQAKAKsNAA==.',
Si='Sibbrena:BAABNQAECn81AAISAAoKyh+XBgDnAgASAAoKyh+XBgDnAgAAAA==.Sillygoose:BAAANQADCgcIGQAAAA==.Simpin:BAABNQAECn8VAAMLAAcKMxLlywAyAQALAAYKFhDlywAyAQAKAAEKpxo7agBMAAAAAA==.Sinemon:BAAANQAECgUIDAAAAA==.Sinz:BAAANQAECgEIAQAAAA==.',
Sk='Skn:BAABNQAECn8vAAMUAAoKyCLVCgByAwAUAAoKyCLVCgByAwAGAAUKhRvz4QBYAQAAAA==.',
Sl='Slam:BAAANQAECgIIAgAAAA==.Slaughter:BAABNQAECn8XAAMaAAUKWQPCOQBjAAAaAAUKWQPCOQBjAAAHAAQKxwE7/ABPAAAAAA==.Slycedyce:BAAANQAECgMIAwABNQAFFAYIEAALAIMfAA==.',
Sm='Smartlurth:BAAANQAECgIIBAAAAA==.',
Sn='Snowjob:BAABNQAECn8WAAIOAAcKjRYAygDxAQAOAAcKjRYAygDxAQAAAA==.',
So='Solatic:BAAANQAECgUIBQAAAA==.Sonal:BAAANQADCgYIBgABNQAECgcIKwAKAN4YAA==.Sourdiesal:BAAANQABCgIIAgAAAA==.',
Sp='Spewns:BAAANQADCgMIAwAAAA==.Sporki:BAAANQAECgcIDQAAAA==.Spron:BAAANQADCgUIBQAAAA==.',
Sq='Squanchy:BAAANQADCgMIAwAAAA==.',
St='Stackz:BAAANQAECgEIAQAAAA==.Stead:BAAANQAECggIEQAAAA==.Stealthus:BAAANQADCggIDAAAAA==.Steamlock:BAABNQAECn8XAAQgAAoKzgzeDQB4AQAgAAcKrAreDQB4AQAKAAQKtxB4NwDjAAALAAUKdQiyCQG4AAAAAA==.Stellar:BAAANQAECgUIEQABNQAECgoKXAAPAIAkAA==.Stelthme:BAABNQAECn8vAAMPAAkKFBoQIABeAgAPAAkK5hcQIABeAgAeAAcKiRbxPQDXAQABNQAECgoKXAAPAIAkAA==.Strongman:BAAANQAECgIIAgAAAA==.',
Sw='Sweetie:BAAANQABCgYICAAAAA==.',
Ta='Takeshì:BAAANQADCgcIBwABNQAECgcIHAARAPsfAA==.Tanìs:BAAANQAECggIDQAAAA==.Tarle:BAABNQAECn8fAAIFAAcKWBcOIgDSAQAFAAcKWBcOIgDSAQAAAA==.Tazath:BAAANQAECgUICQABNQAFFAYICgAWAGwcAA==.',
Te='Tendroni:BAAANQAECgEIAQAAAA==.Tenten:BAAANQADCgYIBgAAAA==.',
Th='Theory:BAABNQAECn8oAAMEAAoKQBfiNwApAgAEAAoKQBfiNwApAgAVAAIKkwasfwAvAAAAAA==.Thraxsus:BAAANQABCgIIAgAAAA==.',
To='Tonhãotrovão:BAAANQAECgQIBAABNQAECgoKGAAIAAwmAA==.',
Tr='Trashii:BAABNQAECn8vAAMlAAoKZA5RBwAIAgAlAAoKZA5RBwAIAgAIAAMKHwLNcgBrAAAAAA==.Treevive:BAAANQAECgYICAABNQAFFAQICgARAOkVAA==.Trencough:BAAANQAECgYIBgAAAA==.Trenlight:BAAANQAECgQIBAAAAA==.Trentotem:BAACNQAFFH8GAAIYAAMK3gIRHwC8AAAYAAMK3gIRHwC8AAA1AAQKfyEAAhgACQrxHbY0AKUCABgACQrxHbY0AKUCAAAA.Trystan:BAABNQAECn8xAAIGAAoKehDTcACuAQAGAAoKehDTcACuAQAAAA==.',
Ts='Tsinga:BAAANQAECgUICgAAAA==.Tsla:BAAANQADCgEIAQAAAA==.',
Tu='Turlo:BAAANQADCggJCwAAAA==.',
Tw='Twobrews:BAACNQAFFH8GAAIMAAMKSRazBgDqAAAMAAMKSRazBgDqAAA1AAQKfyoAAwwACgqcG1IFAA0DAAwACQohH1IFAA0DACMABAriCD40AMcAAAAA.Twohammered:BAAANQADCgcICwABNQAFFAMIBgAMAEkWAA==.Twojoints:BAAANQAECgYICAABNQAFFAMIBgAMAEkWAA==.',
['Tì']='Tìnktìnk:BAAANQADCggIDgABNQAECgcIHAARAPsfAA==.',
['Tø']='Tøm:BAACNQAFFH8UAAIGAAcKvRp3BQADAgAGAAcKvRp3BQADAgA1AAQKfz0AAgYACgo7JUAIAEoDAAYACgo7JUAIAEoDAAAA.',
Ul='Ullirus:BAAANQAECgIIAwAAAA==.Ultimatefury:BAAANQAECgQIBAAAAA==.',
Un='Unb:BAAANQAECgEIAQAAAA==.Unbiased:BAABNQAECn8yAAMVAAoKpxo4NQBUAgAVAAgKGxg4NQBUAgAQAAoKGxmmNQADAgAAAA==.Unholyblodd:BAAANQAECgEIAQAAAA==.Unshookable:BAABNQAECn80AAICAAoKaCJGBQBNAwACAAoKaCJGBQBNAwAAAA==.',
Ur='Ursos:BAAANQAECggIEAAAAA==.Urìko:BAAANQAECgQIBAAAAA==.',
Ut='Utrig:BAAANQAECgYIDQABNQAECggIEAADAAAAAA==.',
Va='Vaelor:BAAANQADCgQIBAABNQAECggIEAADAAAAAA==.Valsande:BAAANQADCgIIAgAAAA==.',
Ve='Vecnah:BAAANQADCgMIAwAAAA==.Vermax:BAAANQAECgcICgAAAA==.',
Vi='Vika:BAAANQADCggIEQABNQAECggIEAADAAAAAA==.Vita:BAAANQADCgMJAwAAAA==.',
Vo='Voidh:BAABNQAECn8YAAMTAAgKEw+cQwDmAAAhAAYK3wtDTAD3AAATAAQKjxCcQwDmAAAAAA==.Voidlockus:BAAANQAECggIDAAAAA==.Voorhees:BAAANQABCgQIBAAAAA==.',
Vu='Vulcin:BAABNQAECn8hAAIUAAoKOxtyJgDQAgAUAAoKOxtyJgDQAgABNQAECgoKRAAXAGkjAA==.',
Wa='War:BAAANQADCgQIBAABNQAFFAQICQAKAJ8WAA==.Wariuus:BAAANQAECgUIBwAAAA==.Watercupp:BAAANQAECgUIDAAAAA==.',
Wh='Whiskie:BAAANQADCgQIBAAAAA==.Whitelïght:BAAANQAECgUIBgAAAA==.Whsprngihntr:BAAANQADCggICAAAAA==.',
Wi='Wibblës:BAABNQAECn8nAAMcAAgKJB8SMQCdAgAcAAgKJB8SMQCdAgAYAAMKRhm+5gDKAAAAAA==.Windsor:BAAANQAECgMIAgAAAA==.',
Wr='Wrathtiger:BAAANQADCgIIAgAAAA==.',
Xi='Xial:BAAANQADCggIFQABNQAECgEIAwADAAAAAA==.',
Xy='Xyfin:BAAANQADCggIDwAAAA==.',
Yd='Ydehhteb:BAAANQADCgEIAQABNQAECgIIAgADAAAAAA==.',
Za='Zandramadas:BAABNQAECn8rAAMBAAoKnhlHGQByAgABAAoKnhlHGQByAgAbAAgKGA8DSgC/AQAAAA==.Zaraline:BAABNQAECn8mAAIJAAgKDxumbQA3AgAJAAgKDxumbQA3AgAAAA==.',
Ze='Zeakz:BAAANQAECgEIAgAAAA==.',
Zi='Zinyak:BAAANQAECgcIDQAAAA==.',
Zo='Zoomiez:BAAANQAECgUIDwAAAA==.',
Zp='Zpai:BAABNQAECn8fAAMMAAoKnBhDDwD8AQAMAAoKnBhDDwD8AQAjAAYKbAWxTADFAAAAAA==.',
Zy='Zyfae:BAAANQAECggIBAAAAA==.Zynos:BAAANQADCgcIBwAAAA==.Zyyn:BAAANQAECgYICgAAAA==.',
['Äc']='Ächilles:BAAANQABCgIIAgAAAA==.',
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
