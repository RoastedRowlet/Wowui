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

local lookup = {'Druid-Restoration','Monk-Mistweaver','Unknown-Unknown','DeathKnight-Blood','Paladin-Protection','Paladin-Retribution','Warrior-Arms','Hunter-Marksmanship','Hunter-BeastMastery','Warlock-Destruction','Warlock-Demonology','Monk-Brewmaster','Mage-Fire','Mage-Arcane','DeathKnight-Frost','Priest-Holy','Priest-Shadow','DemonHunter-Havoc','Paladin-Holy','DeathKnight-Unholy','Druid-Feral','Mage-Frost','Shaman-Elemental','Warrior-Fury','Warrior-Protection','Druid-Balance','Shaman-Restoration','Shaman-Enhancement','Rogue-Assassination','Druid-Guardian','Warlock-Affliction','Rogue-Subtlety','DemonHunter-Devourer','Evoker-Augmentation','Monk-Windwalker','Priest-Discipline','Hunter-Survival',}
local provider = {region='US',realm='Gorefiend',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Abracanoobra:BAABNQAECn8aAAIBAAoKTxb5IAAhAgABAAoKTxb5IAAhAgAAAA==.Abuki:BAACNQAFFH8NAAICAAUKnhTzAgBbAQACAAUKnhTzAgBbAQA1AAQKfykAAgIACgrzH28JAPQCAAIACgrzH28JAPQCAAAA.',
Ai='Aiforix:BAAANQADCgcJBwAAAA==.',
Ak='Akagane:BAAANQADCgYIDAAAAA==.Akalla:BAAANQAECgYIDAAAAA==.',
Al='Alfuric:BAAANQAECgUICgAAAA==.Aliviana:BAAANQADCgYIBgABNQAECgQIDwADAAAAAA==.Althraniir:BAAANQAECgEIAgAAAA==.Altrois:BAABNQAECn84AAIEAAoK8yAPCgBlAwAEAAoK8yAPCgBlAwAAAA==.',
Am='Amatrake:BAACNQAFFH8WAAIFAAcKdxR5AwDKAQAFAAcKdxR5AwDKAQA1AAQKfzAAAgUACgoQHtUNAL0CAAUACgoQHtUNAL0CAAAA.Amatsano:BAEANQAECgUIDQAAAA==.Amorsith:BAABNQAECn8uAAMFAAoK6RxHBgCMAgAFAAoK6RxHBgCMAgAGAAYKwQxS9AA0AQAAAA==.Amurine:BAAANQAECgYICAAAAA==.Amyst:BAABNQAECn8jAAIHAAgKbSFHSQCuAgAHAAgKbSFHSQCuAgAAAA==.',
An='Anahita:BAAANQAECgEIAQAAAA==.Angrycrack:BAAANQAECgcIEQAAAA==.Angusill:BAAANQAECgEIAQAAAA==.Animuggus:BAEANQAECgUICAAAAA==.Anjunabeets:BAACNQAFFH8ZAAMIAAgKrBNyBgDuAQAIAAcKwRNyBgDuAQAJAAEKRBNEMABeAAA1AAQKfyAAAwgACgpcJEMaAIMCAAgACQoiJEMaAIMCAAkAAgoTGnQuAZAAAAAA.Anthran:BAABNQAECn8lAAMKAAoKqw0nKgArAQAKAAUKaRAnKgArAQALAAcKoQj04QAFAQAAAA==.',
Ao='Ao:BAAANQAECgIIBAAAAA==.',
Ap='Apexlegend:BAAANQAECgQIBAAAAA==.',
Ar='Arakin:BAAANQABCggJCgAAAA==.Arcon:BAAANQAECgQICgABNQAECgoKHwAMAJwYAA==.Arcscythe:BAABNQAECn8gAAMNAAoKVhE4AgA8AgANAAgK0BQ4AgA8AgAOAAIK5wYY/wBmAAAAAA==.Arctron:BAAANQAECgYIDAABNQAECgoKHwAMAJwYAA==.Arthanos:BAAANQADCgcIAQABNQAECgYICAADAAAAAA==.Artoo:BAAANQAECggIDQAAAA==.',
As='Ashesonly:BAABNQAECn87AAIPAAoKRxsyEwBDAgAPAAoKRxsyEwBDAgAAAA==.Assaulter:BAAANQADCgIIAgABNQAECgoKOgAJABwhAA==.',
Au='Auramis:BAABNQAECn82AAMQAAoK0CFrGAAUAwAQAAoK0CFrGAAUAwARAAIKsQc3NgB0AAAAAA==.',
Az='Azariel:BAACNQAFFH8GAAISAAMKMxY0DACbAAASAAMKMxY0DACbAAA1AAQKfzMAAhIACgosH2wQAB0DABIACgosH2wQAB0DAAAA.Azrayel:BAAANQADCgUIBQAAAA==.',
Ba='Babydilla:BAACNQAFFH8WAAIEAAcKEiM0AwBkAgAEAAcKEiM0AwBkAgA1AAQKfy4AAgQACgqYJBsLAFsDAAQACgqYJBsLAFsDAAAA.Balgith:BAABNQAECn8fAAMTAAcKKg4NZQASAQATAAcKKg4NZQASAQAGAAEKAABzzAEhAAAAAA==.Balrus:BAAANQADCgEJAQAAAA==.Bam:BAAANQADCggICAAAAA==.Bannagad:BAABNQAECn8cAAMGAAkKuQkyuQCrAQAGAAkKuQkyuQCrAQATAAUKhAl3vQABAQAAAA==.Barthoun:BAABNQAECn8WAAIHAAoKCA2hRQC4AQAHAAoKCA2hRQC4AQAAAA==.Battleburger:BAAANQAECgEIAwAAAA==.Bauchelaine:BAAANQAECgEIAgAAAA==.Bawitaba:BAAANQAECgUJEAAAAA==.',
Be='Benchknight:BAACNQAFFH8OAAQPAAcKXQ55DQAGAQAPAAUKwQt5DQAGAQAUAAEKzRgbHQBfAAAEAAEKAABcMwAuAAA1AAQKfz8ABA8ACgpwH1sSAPoCAA8ACgo3H1sSAPoCABQACQp/Gv9IAPMBAAQABQqRHYAsAD8BAAAA.Beoron:BAACNQAFFH8JAAIVAAUKhRoQAgAVAQAVAAUKhRoQAgAVAQA1AAQKf0EAAhUACgp8JcAAAF0DABUACgp8JcAAAF0DAAAA.Bettyßastion:BAABNQAECn8rAAIGAAkKGxRfUwC8AQAGAAkKGxRfUwC8AQAAAA==.',
Bi='Big:BAAANQAECgQIBwAAAA==.Bigflex:BAAANQAECggIEAAAAA==.Bio:BAAANQAECggICwAAAA==.Bioenergy:BAAANQAECgEIBAABNQAECggICwADAAAAAA==.Biolysis:BAAANQAECgQIBgABNQAECggICwADAAAAAA==.',
Bl='Blesus:BAAANQAECgQIBQAAAA==.Blowtortch:BAABNQAECn8mAAMOAAoKlwgLdQBaAQAOAAoK+wcLdQBaAQAWAAEKggalRwA1AAAAAA==.',
Bo='Bolverkr:BAAANQAECgEIAQAAAA==.',
Br='Brageus:BAABNQAECn8cAAIXAAoKBw8nRwA6AQAXAAoKBw8nRwA6AQAAAA==.Brainmatter:BAAANQADCgMIBAAAAA==.Braintumor:BAABNQAECn8eAAIUAAcKIgkGfgAkAQAUAAcKIgkGfgAkAQAAAA==.Brontag:BAABNQAECn8qAAQYAAoK8B1gBwCDAgAYAAkKRiBgBwCDAgAHAAgKeBY6oADMAQAZAAEKAACPQQA5AAAAAA==.Bruus:BAAANQADCggIEAAAAA==.',
Bu='Bugles:BAAANQAECgEIAQAAAA==.Buns:BAAANQAECgEIAgAAAA==.Butternutter:BAAANQAECgEIAQABNQAECgYICAADAAAAAA==.',
['Bé']='Béllas:BAAANQADCgYIBgAAAA==.',
Ca='Caissa:BAAANQADCgYIBgAAAA==.Caliboy:BAAANQAECgEIAgABNQAECgIIBQADAAAAAA==.Calißoy:BAAANQAECgIIBQAAAA==.Caneki:BAABNQAECn8aAAMQAAkKGRjXUQAuAgAQAAkKGRjXUQAuAgARAAEKAAA+lAATAAAAAA==.Canekii:BAABNQAECn8VAAMTAAcKoxdGZQDoAQATAAcKoxdGZQDoAQAGAAEKAAChrAExAAABNQAECgkJGgAQABkYAA==.Casini:BAAANQAECgcIBwAAAA==.Cathrîne:BAAANQADCggICAAAAA==.',
Ce='Celeice:BAAANQADCgUIBQAAAA==.Celticankou:BAAANQAECgUIBQAAAA==.Cerberus:BAACNQAFFH8JAAIJAAQK/R2ZFAAdAQAJAAQK/R2ZFAAdAQA1AAQKfy4AAgkACgqvIzENAHUDAAkACgqvIzENAHUDAAAA.Ceruledge:BAAANQAECgEIAgABNQAECgoKLAARAPscAA==.',
Ch='Chaboomy:BAECNQAFFH8VAAIaAAcKcRWUCgDMAQAaAAcKcRWUCgDMAQA1AAQKfzgAAhoACgrKIvENAFsDABoACgrKIvENAFsDAAAA.Chevron:BAAANQAECgEIAQAAAA==.Chidori:BAAANQADCgUIBQAAAA==.Chips:BAABNQAECn8tAAIHAAgKRhB0nADVAQAHAAgKRhB0nADVAQAAAA==.Chloeswift:BAAANQAECgEIAQAAAA==.',
Co='Cobblerjr:BAAANQAECgIIAgAAAA==.Coffeemaker:BAABNQAECn8nAAQOAAoKqhjvjgBhAgAOAAoKqhjvjgBhAgANAAYKzQ/gBABMAQAWAAEKjh0mSAA0AAAAAA==.Conyay:BAAANQAECggIEQAAAA==.Cowploww:BAAANQADCggIEAAAAA==.',
Cr='Croissant:BAABNQAECn8iAAILAAgKwx7aOACpAgALAAgKwx7aOACpAgAAAA==.Cräsh:BAAANQADCgMIAwAAAA==.',
Cy='Cycko:BAAANQADCgUIBQAAAA==.Cytheria:BAAANQADCgYIBwABNQAECgYICAADAAAAAA==.',
Da='Dalidan:BAAANQAECgUIBgABNQAFFAEIAQADAAAAAA==.Dalórien:BAAANQADCgUICgABNQAECgMIBgADAAAAAA==.Damaerin:BAAANQAECgUIEQAAAA==.Darkis:BAABNQAECn8YAAMBAAoKLQpxOgBMAQABAAkK/AZxOgBMAQAaAAgKJgQQbgASAQAAAA==.Darkseph:BAAANQAECgcIDgAAAA==.Darthjarjar:BAAANQADCgMIAwAAAA==.Dayy:BAACNQAFFH8SAAMXAAcKBBpuCgDEAQAXAAUKhhtuCgDEAQAbAAMKfAmHFQCbAAA1AAQKfz4ABBcACgowJt4GALIDABcACgowJt4GALIDABsAAgoYDPD5AHcAABwAAQphBtgpADkAAAAA.',
De='Deathsteak:BAAANQADCggIDQAAAA==.Deepman:BAABNQAECn8sAAIdAAoKMRVKCwDMAQAdAAoKMRVKCwDMAQABNQAECgoKOgAJABwhAA==.Delessia:BAAANQAECgcICAAAAA==.Demonesque:BAAANQAECgEIAgAAAA==.Desy:BAAANQAECgYIDQAAAA==.',
Di='Diggersby:BAACNQAFFH8NAAIeAAUKJyKSAAB+AQAeAAUKJyKSAAB+AQA1AAQKfyMAAh4ACgr6ILwHAAcDAB4ACgr6ILwHAAcDAAAA.Disastrous:BAACNQAFFH8MAAIJAAQKXQ0qDgDiAAAJAAQKXQ0qDgDiAAA1AAQKfzAAAgkACgrAFMs2AAUCAAkACgrAFMs2AAUCAAAA.',
Do='Doomangel:BAAANQAECgUIBgAAAA==.Doson:BAAANQAECgYICQAAAA==.',
Dr='Dracthyr:BAAANQAECgEIAQABNQAECggICwADAAAAAA==.Drago:BAAANQAECgEIAQABNQAECgQIBQADAAAAAA==.Dragonbison:BAAANQAECgUICgAAAA==.Druidtime:BAAANQADCggIFQAAAA==.Drunkenmasta:BAAANQADCgIIAgABNQAECgoKOgAJABwhAA==.',
['Dø']='Døc:BAABNQAECn9BAAMbAAoKVRn5JQAeAgAbAAoKVRn5JQAeAgAXAAkKJRP1MwCHAQAAAA==.',
Eg='Eggland:BAAANQAECgUICgAAAA==.',
Ei='Eielmolate:BAACNQAFFH8UAAILAAcKEQ1zCQDSAQALAAcKEQ1zCQDSAQA1AAQKfy4AAwsACgruHo8fAAYDAAsACgruHo8fAAYDAAoAAgrqDl1hAGIAAAAA.',
El='Eldranus:BAAANQAECgUIDAAAAA==.',
En='Enimed:BAABNQAECn87AAIEAAoKpx0HCwCZAgAEAAoKpx0HCwCZAgAAAA==.',
Er='Erutan:BAAANQAECgEIAQAAAA==.',
Eu='Eugenn:BAAANQADCggIEwAAAA==.',
Ev='Evil:BAACNQAFFH8JAAQKAAQKnxYSDwCXAAAKAAIKIhASDwCXAAALAAIKPBcCHwBpAAAfAAEKAADqCgAAAAA1AAQKfysABAoACgp+IDMbAJMBAAsABwp4HkpkAC0CAAoABQpBIDMbAJMBAB8ABAp8HK8SAB8BAAAA.',
Fa='Falarion:BAAANQAECgYIBwAAAA==.Fam:BAABNQAECn81AAIOAAkKgyKYJgBGAwAOAAkKgyKYJgBGAwAAAA==.Fatherseph:BAAANQAECgUIDAABNQAECgcIDgADAAAAAA==.',
Fi='Finkymcbinky:BAABNQAECn8ZAAIOAAkK7wyvWwCaAQAOAAkK7wyvWwCaAQAAAA==.Finroz:BAAANQADCgQIBAAAAA==.Fisterdobble:BAABNQAECn85AAIWAAoKHhpWBgCeAgAWAAoKHhpWBgCeAgAAAA==.',
Fl='Fleurdelys:BAAANQADCggIPQAAAA==.Florella:BAAANQADCgUIBwAAAA==.',
Fo='Foidhater:BAAANQADCgEIAQAAAA==.Forestpump:BAAANQAECgEIAQABNQAECgEIAQADAAAAAA==.Forgedd:BAAANQAECgUIBQAAAA==.Forgeddemon:BAABNQAECn8zAAIMAAoKOAsuBwCJAQAMAAoKOAsuBwCJAQAAAA==.',
Fr='Frogkid:BAAANQAECgQIBAAAAA==.Frostborne:BAABNQAECn8qAAIUAAkKJhsoEgACAgAUAAkKJhsoEgACAgAAAA==.Frostheart:BAAANQABCgYIDAAAAA==.Frostystomp:BAAANQAECgcIDwABNQAFFAUICQAVAIUaAA==.Frozenpickle:BAAANQADCgYIBwABNQAECgQIDAADAAAAAA==.',
Fu='Funeral:BAABNQAECn8dAAILAAoKcQt4QACoAQALAAoKcQt4QACoAQABNQAECgoKOgAJABwhAA==.',
Ga='Gamjee:BAAANQAECgUIDAAAAA==.',
Ge='Gerkindk:BAAANQADCggICAAAAA==.',
Gh='Ghostly:BAAANQAECgEIAQAAAA==.',
Gl='Glyndin:BAAANQADCgcIEQAAAA==.',
Go='Goodboy:BAAANQAECgMIAwABNQAFFAUIDQAeACciAA==.Goodolrúss:BAAANQADCgYJEAAAAA==.',
Gr='Grackalackin:BAAANQAECgQIDgAAAA==.Grassfedgeez:BAAANQAECgIIAgAAAA==.Greenxgoblin:BAAANQADCgEJAQAAAA==.Grizmaus:BAABNQAECn8VAAISAAkKOQnTJQBnAQASAAkKOQnTJQBnAQAAAA==.',
Gu='Guilliman:BAABNQAECn8kAAIHAAkKvBxCXQB0AgAHAAkKvBxCXQB0AgAAAA==.Gulaj:BAABNQAECn8pAAIJAAkKpBO9dwAgAgAJAAkKpBO9dwAgAgAAAA==.Guldaniel:BAAANQADCggIDQAAAA==.',
['Gë']='Gënesis:BAAANQAECgYIDwAAAA==.',
Ha='Haloro:BAAANQADCgEIAQAAAA==.Ham:BAAANQAECgcICwAAAA==.',
He='Healgimp:BAABNQAECn8wAAIQAAoKwB3bLgCtAgAQAAoKwB3bLgCtAgAAAA==.',
Hi='Hiruken:BAAANQADCgcIEAAAAA==.',
Ho='Hope:BAEBNQAECn8eAAMeAAoK9BmUCQAxAgAeAAgKpRuUCQAxAgABAAoKcBKnHwAvAgABNQAFFAcIGQAQAKQTAA==.Hortzel:BAAANQAECgUIDAAAAA==.Hotrollz:BAAANQADCgUIBQABNQAECgcIKgAQAEUZAA==.Howdoidie:BAAANQAECgQIBgAAAA==.Howdoitotem:BAABNQAECn8jAAMXAAoKiBl6MgCwAgAXAAoKiBl6MgCwAgAbAAMK3geW+QB3AAAAAA==.',
Hu='Hulkx:BAAANQAECgQICwAAAA==.Humaa:BAABNQAECn8tAAIGAAgKbhkxfQAwAgAGAAgKbhkxfQAwAgAAAA==.Huntus:BAABNQAECn8yAAIJAAkKdh2ZOwC3AgAJAAkKdh2ZOwC3AgAAAA==.',
Hy='Hyperiøn:BAAANQADCgIIAgAAAA==.',
Ib='Ibcrootbeer:BAAANQAECgEIAQAAAA==.',
Ic='Icenaria:BAAANQADCggICAAAAA==.Icewiz:BAAANQABCgUIBQABNQAECgUIDQADAAAAAA==.Icy:BAABNQAECn8eAAIHAAkKYReFYwBkAgAHAAkKYReFYwBkAgAAAA==.',
Im='Impale:BAAANQADCgMIAwAAAA==.Imperio:BAAANQAECgMIBQAAAA==.Impostor:BAABNQAECn86AAIRAAoKah84BgC1AgARAAoKah84BgC1AgAAAA==.',
Iz='Izuu:BAABNQAECn8VAAIJAAcKrw4hfgA3AQAJAAcKrw4hfgA3AQAAAA==.',
['Iç']='Içyhot:BAAANQADCgEIAQAAAA==.',
Ja='Jabrick:BAAANQAECgQIBQAAAA==.Jattin:BAAANQADCgYIDAAAAA==.Jawnski:BAAANQADCgUICQAAAA==.',
Ji='Jibjabjibjab:BAACNQAFFH8FAAMgAAMKnxHKDQDZAAAgAAMKnxHKDQDZAAAdAAEKIwtJIABIAAA1AAQKfzAAAx0ACgo0HQEeABEBACAACgovHBYbAP4BAB0ABQrdGgEeABEBAAAA.',
Jo='Joey:BAAANQADCgcIBwAAAA==.Joharin:BAABNQAECn8fAAILAAcKRw4ecgAXAQALAAcKRw4ecgAXAQAAAA==.',
Jt='Jtabb:BAAANQABCgYICQAAAA==.',
Ju='Juroda:BAAANQADCgYIBgABNQAECgcIDgADAAAAAA==.',
Ka='Kankiro:BAAANQAECgUICAAAAA==.Kanstentin:BAAANQADCggICAAAAA==.Karram:BAAANQADCgQIBAAAAA==.',
Kc='Kcup:BAAANQADCgYIBgAAAA==.',
Ke='Kelamess:BAABNQAECn8XAAMBAAYKWAc6UQDEAAABAAYKWAc6UQDEAAAaAAUKrgSkhAC/AAAAAA==.Kelemvor:BAABNQAECn8WAAIhAAoK+wxaLwDHAQAhAAoK+wxaLwDHAQAAAA==.Ken:BAAANQADCgYIBgAAAA==.Keyzer:BAAANQAECgEIAQAAAA==.',
Kf='Kfp:BAAANQABCgEIAQAAAA==.',
Kh='Khandak:BAACNQAFFH8FAAIEAAMKSgpsDwCqAAAEAAMKSgpsDwCqAAA1AAQKfyEAAgQACgp9GegzAD0CAAQACgp9GegzAD0CAAAA.',
Ki='Kimmy:BAAANQAECgYIDwAAAA==.',
Kl='Kleenex:BAABNQAECn8sAAIWAAoK+Rb3BAAUAgAWAAoK+Rb3BAAUAgAAAA==.',
Ko='Koldiss:BAAANQAECgEIAQAAAA==.',
Kr='Krueger:BAAANQAECggIEAAAAA==.',
Ku='Kurisutina:BAAANQAECgYIDwABNQAFFAQICQAbAHcMAA==.Kushiel:BAAANQAECgEIAQAAAA==.',
Le='Leadblaster:BAABNQAECn86AAIJAAoKHCG/FgBAAwAJAAoKHCG/FgBAAwAAAA==.Leethalfu:BAABNQAECn8bAAIMAAoKuhaqCQCEAgAMAAoKuhaqCQCEAgAAAA==.Leethalrot:BAAANQAECgEIAQABNQAECgoKGwAMALoWAA==.Legosi:BAABNQAECn8fAAILAAgK+w3NdwAJAQALAAgK+w3NdwAJAQAAAA==.Leighroy:BAAANQAECgEIAQAAAA==.Lemegegen:BAABNQAECn84AAILAAoKGiA+DQDBAgALAAoKGiA+DQDBAgAAAA==.Leviosa:BAAANQAECggIEQAAAA==.',
Lh='Lhux:BAACNQAFFH8FAAIJAAEKPxKxIwBQAAAJAAEKPxKxIwBQAAA1AAQKfz0AAgkACgq8HkgSAL0CAAkACgq8HkgSAL0CAAE1AAQKCgokACIAtA4A.Lhuxi:BAABNQAECn8kAAIiAAoKtA5dBQCmAQAiAAoKtA5dBQCmAQAAAA==.',
Li='Lilbokchoy:BAAANQABCgQIBAAAAA==.Linkin:BAAANQABCgMIAwAAAA==.',
Lo='Loneassassin:BAAANQADCgQIBAAAAA==.Lorani:BAACNQAFFH8HAAIaAAUKhSDlFwDsAAAaAAUKhSDlFwDsAAA1AAQKfy0AAhoACgr1JCQMAGoDABoACgr1JCQMAGoDAAAA.',
Lu='Lurth:BAAANQADCgIIAgABNQAECgMIAwADAAAAAA==.',
Ly='Lyxxie:BAABNQAECn8sAAMPAAoKPxqyJQBmAgAPAAoKPxqyJQBmAgAUAAUKCQvPjQDuAAAAAA==.',
Ma='Maelle:BAAANQAECgQIBAAAAA==.Mageus:BAAANQAECgYICgAAAA==.Manafart:BAAANQADCgYIBgABNQAECggILQAHAEYQAA==.Manbearpïg:BAABNQAECn8VAAMVAAcKBhEqEgAMAQAVAAcKBhEqEgAMAQAaAAQKJwt7TQCQAAABNQAECgoKFwAIAAwmAA==.Matsumushi:BAABNQAECn8uAAMMAAkKzxPKDgAGAgAMAAgKWBbKDgAGAgAjAAgKdwYCJQD8AAAAAA==.',
Mc='Mcnastyy:BAAANQADCgYICgAAAA==.',
Me='Mefesto:BAABNQAECn8dAAIOAAkKvg+DtgAWAgAOAAkKvg+DtgAWAgABNQABCgQIBgADAAAAAA==.Mellore:BAAANQAECgIIAwABNQAFFAUIBwAaAIUgAA==.Metsutan:BAACNQAFFH8IAAIgAAYKqRZcBgBKAQAgAAYKqRZcBgBKAQA1AAQKfzkAAiAACQplIaYJAPMCACAACQplIaYJAPMCAAAA.',
Mi='Minphoria:BAAANQAECgEIAwAAAA==.Misfitgrimmy:BAAANQAECgMIBAAAAA==.',
Mo='Mogged:BAAANQAECgEIAgAAAA==.Molathom:BAAANQAECgUICgAAAA==.Moonster:BAAANQAECgUIDAAAAA==.Moppit:BAAANQAECgEIAQAAAA==.',
['Mâ']='Mâtthêw:BAAANQAECgMICgAAAA==.',
Na='Naes:BAAANQADCgYIDAAAAA==.Nazuresh:BAAANQADCggICAABNQAECgUIFgAQAFEiAA==.',
Ne='Necrodamus:BAAANQAECgUICAAAAA==.Nekcrotic:BAABNQAECn8VAAMLAAgKshNunACfAQALAAcKuRJunACfAQAKAAIKIxClWAB2AAAAAA==.Nekromant:BAABNQAECn8gAAMKAAcKRA27SACmAAALAAYK2gm6xwA6AQAKAAMKiA27SACmAAAAAA==.Nelle:BAAANQABCggIDgAAAA==.Nemriel:BAAANQAECgUICAAAAA==.',
Ni='Nibbles:BAAANQAECgQJBgAAAA==.Nighthoe:BAAANQAECgQIBgAAAA==.Nintales:BAAANQAECgQIBgAAAA==.',
No='Nohric:BAAANQAECgcIEwAAAA==.Noobieone:BAAANQAECgIIAgAAAA==.Norsem:BAAANQAECgYIEQAAAA==.',
Ny='Nymera:BAAANQAECgMIAwABNQAECgYICAADAAAAAA==.',
['Nä']='Nämeless:BAAANQAECgMIBAAAAA==.',
Oh='Ohlorn:BAACNQAFFH8JAAIcAAcK/gyhAwA9AQAcAAcK/gyhAwA9AQA1AAQKfzUAAhwACgq3JJ0AAF8DABwACgq3JJ0AAF8DAAAA.',
Ok='Oktar:BAAANQADCgUIBQAAAA==.',
On='Onenightstab:BAAANQAECgEIAQAAAA==.Onfleek:BAAANQAECgQICgAAAA==.',
Or='Orakrak:BAAANQADCgQIBAAAAA==.Oroku:BAAANQADCgQICAAAAA==.',
Ox='Oxtails:BAAANQADCgMIAwAAAA==.',
Oz='Ozzmodius:BAAANQAECgYIDQAAAA==.',
Pa='Pakapunch:BAAANQADCgIIAgABNQAECgQIBQADAAAAAA==.Palysuk:BAAANQADCggIFQAAAA==.Papier:BAAANQAECgYICAAAAA==.Parsephone:BAACNQAFFH8VAAMBAAYKMh/eBADWAQABAAUKYx/eBADWAQAaAAQKgg5iCwDgAAA1AAQKfzYABAEACgo9JfIAANIDAAEACQpWJvIAANIDABoABQprHnckAGEBABUAAQoAAEhCADUAAAE1AAQKCAgSAAMAAAAA.Parstout:BAAANQAECggIEgAAAA==.Pawsitivity:BAABNQAECn8yAAIXAAoKrCIKEgCAAgAXAAoKrCIKEgCAAgAAAA==.',
Pd='Pdbm:BAABNQAECn8gAAIGAAoKThpGUACkAgAGAAoKThpGUACkAgAAAA==.',
Pe='Petr:BAABNQAECn84AAMQAAoKHBrlMACkAgAQAAoKHBrlMACkAgARAAEKAADqjgAcAAAAAA==.Pettigrew:BAAANQAECgYIBgAAAA==.Peut:BAABNQAECn8oAAITAAoK0Ro6LwCpAgATAAoK0Ro6LwCpAgAAAA==.',
Ph='Physix:BAAANQAECgUIBgAAAA==.',
Pi='Pipsqueak:BAAANQADCgcJCwAAAA==.Pitchntents:BAAANQAECgcJCwAAAA==.',
Po='Popped:BAAANQAECgQIDAAAAA==.Porkins:BAABNQAECn81AAMPAAoKKR/KDQCKAgAPAAoKzx7KDQCKAgAUAAYKdxMMZgB5AQAAAA==.',
Pr='Priestus:BAAANQAECgEIBAAAAA==.',
Ps='Psyndra:BAEANQAFFAEIAQABNQAECgoKHwAbAEkhAA==.',
Py='Pyraxx:BAABNQAECn9AAAIWAAoK/x/JAACwAwAWAAoK/x/JAACwAwAAAA==.',
Qt='Qtwithabooty:BAACNQAFFH8YAAIhAAcKkRoBBAALAgAhAAcKkRoBBAALAgA1AAQKfzEAAiEACgqjJZECACUDACEACgqjJZECACUDAAAA.',
Qu='Quatermaine:BAAANQAECgUIEgAAAA==.',
Ra='Radovan:BAACNQAFFH8QAAMLAAYKgx/EFQBIAQALAAUKAiLEFQBIAQAKAAEKCBiBGgBQAAA1AAQKf0kAAwsACgovJgQHAAIDAAsACQoSJgQHAAIDAAoABQpDIM4aAJYBAAAA.Rayael:BAAANQAECgQIDwABNQAECgoKOQAWAF4bAA==.Rayjax:BAAANQAECgQIAwAAAA==.Raìdèn:BAABNQAECn8WAAIQAAUKUSK4SgCGAQAQAAUKUSK4SgCGAQAAAA==.',
Re='Replicate:BAAANQAECgIIAgAAAA==.',
Rh='Rhinne:BAABNQAECn8lAAMbAAkK6hL3lgBOAQAbAAgKJhH3lgBOAQAXAAYKBAiVxgAFAQAAAA==.',
Ri='Riddic:BAAANQADCgEIAQAAAA==.',
Ro='Roktar:BAAANQADCgcIDQABNQAECgYICAADAAAAAA==.Rosaelyia:BAAANQADCgYIBwABNQAECgcIHwAJAGIdAA==.',
Ry='Ryanqt:BAAANQADCggIDQAAAA==.Ryanvoker:BAAANQADCgcIBwAAAA==.Ryanx:BAABNQAECn8cAAITAAgK4SDqJADXAgATAAgK4SDqJADXAgAAAA==.',
Sa='Samavati:BAABNQAECn8bAAICAAcKfQ7DJQBLAQACAAcKfQ7DJQBLAQAAAA==.Sarah:BAABNQAECn8wAAMQAAkKXiQBBACvAwAQAAkKXiQBBACvAwAkAAMKngv6GwCHAAAAAA==.Saross:BAAANQADCggICAAAAA==.Sasori:BAACNQAFFH8MAAIgAAUKaghtCABwAQAgAAUKaghtCABwAQA1AAQKfygAAiAACQotHAQNAKUCACAACQotHAQNAKUCAAAA.Sassyface:BAABNQAECn87AAIKAAoKVQ/YAgCxAQAKAAoKVQ/YAgCxAQAAAA==.',
Se='Sellit:BAAANQAECgYIBwAAAA==.Seman:BAAANQADCgIIAgAAAA==.Semperfi:BAAANQAECgEIAQAAAA==.',
Sh='Shadowbourne:BAAANQAECggICQABNQAFFAMIBgASADMWAA==.Shadowdin:BAABNQAECn8uAAITAAoKjxsQJwDNAgATAAoKjxsQJwDNAgAAAA==.Shamzilla:BAABNQAECn8oAAIXAAgKABtRNACnAgAXAAgKABtRNACnAgAAAA==.Sherria:BAAANQAECgEIAQAAAA==.Shockblast:BAAANQAECgEIAgAAAA==.Shriike:BAAANQADCgYIBgAAAA==.Shuyinn:BAAANQAECggICAABNQAECgoKJQAKAKsNAA==.',
Si='Sibbrena:BAABNQAECn8sAAIRAAoK+xyjEwDKAgARAAoK+xyjEwDKAgAAAA==.Sillygoose:BAAANQADCgcIGQAAAA==.Simpin:BAABNQAECn8VAAMLAAcKMxLlywAyAQALAAYKFhDlywAyAQAKAAEKpxo7agBMAAAAAA==.Sinemon:BAAANQAECgUIDAAAAA==.Sinz:BAAANQAECgEIAQAAAA==.',
Sk='Skn:BAABNQAECn8uAAMTAAoKyCLVCgByAwATAAoKyCLVCgByAwAGAAQKNR/z4QBYAQAAAA==.',
Sl='Slam:BAAANQAECgIIAgAAAA==.Slaughter:BAAANQAECgQIEQAAAA==.Slycedyce:BAAANQAECgMIAwABNQAFFAYIEAALAIMfAA==.',
Sm='Smartlurth:BAAANQAECgMIAwAAAA==.',
Sn='Snowjob:BAABNQAECn8WAAIOAAcKjRYAygDxAQAOAAcKjRYAygDxAQAAAA==.',
So='Solatic:BAAANQAECgUIBQAAAA==.Sonal:BAAANQADCgYIBgABNQAECgcIJQAKAMsYAA==.Sourdiesal:BAAANQABCgIIAgAAAA==.',
Sp='Spewns:BAAANQADCgMIAwAAAA==.Sporki:BAAANQAECgUIDAAAAA==.Spron:BAAANQADCgUIBQAAAA==.',
Sq='Squanchy:BAAANQADCgMIAwAAAA==.',
St='Stackz:BAAANQAECgEIAgAAAA==.Stead:BAAANQAECggIEgAAAA==.Stealthus:BAAANQADCggIDAAAAA==.Steamlock:BAABNQAECn8XAAQfAAoKzgzeDQB4AQAfAAcKrAreDQB4AQAKAAQKtxB4NwDjAAALAAUKdQiyCQG4AAAAAA==.Stellar:BAAANQAECgQIDAABNQAECgoKUgAgAIAkAA==.Stelthme:BAABNQAECn8pAAMgAAkKkhnTGABWAgAgAAkK5hfTGABWAgAdAAcK9hPxPQDXAQABNQAECgoKUgAgAIAkAA==.Strongman:BAAANQAECgIIAwAAAA==.',
Sw='Sweetie:BAAANQAECgEIAQAAAA==.',
Ta='Takeshì:BAAANQADCgcIBwABNQAECgUIFgAQAFEiAA==.Tanìs:BAAANQAECggIDQAAAA==.Tarle:BAABNQAECn8cAAIFAAcKWBcOIgDSAQAFAAcKWBcOIgDSAQAAAA==.Tazath:BAAANQAECgUICgABNQAFFAUICQAVAIUaAA==.',
Te='Tendroni:BAAANQAECgEIAgAAAA==.Tenten:BAAANQADCgYIBgAAAA==.',
Th='Theory:BAABNQAECn8iAAIEAAoKoRbiNwApAgAEAAoKoRbiNwApAgAAAA==.Thraxsus:BAAANQABCgIIAgAAAA==.',
To='Tonhãotrovão:BAAANQAECgQIBAABNQAECgoKFwAIAAwmAA==.',
Tr='Trashii:BAABNQAECn8rAAMlAAoKGw5RBwAIAgAlAAoKGw5RBwAIAgAIAAMKHwLNcgBrAAAAAA==.Treevive:BAAANQAECgYICwABNQAFFAMICQAQAMcYAA==.Trencough:BAAANQAECgYIBgAAAA==.Trenlight:BAAANQAECgQIBAAAAA==.Trentotem:BAACNQAFFH8GAAIXAAMK3gIRHwC8AAAXAAMK3gIRHwC8AAA1AAQKfyEAAhcACQrxHbY0AKUCABcACQrxHbY0AKUCAAAA.Trystan:BAABNQAECn8xAAIGAAoKehAnTwDIAQAGAAoKehAnTwDIAQAAAA==.',
Ts='Tsinga:BAAANQAECgUIBwAAAA==.Tsla:BAAANQADCgEIAQAAAA==.',
Tu='Turlo:BAAANQADCggJCwAAAA==.',
Tw='Twobrews:BAACNQAFFH8GAAIMAAMKSRazBgDqAAAMAAMKSRazBgDqAAA1AAQKfyoAAwwACgqcG1IFAA0DAAwACQohH1IFAA0DACMABAriCB4rAM0AAAAA.Twohammered:BAAANQADCgcICwABNQAFFAMIBgAMAEkWAA==.Twojoints:BAAANQAECgYIBwABNQAFFAMIBgAMAEkWAA==.',
['Tì']='Tìnktìnk:BAAANQADCgYIBgABNQAECgUIFgAQAFEiAA==.',
['Tø']='Tøm:BAACNQAFFH8UAAIGAAcKvRp3BQADAgAGAAcKvRp3BQADAgA1AAQKfzUAAgYACgqKI20iADoDAAYACgqKI20iADoDAAAA.',
Ul='Ullirus:BAAANQAECgEIAgAAAA==.Ultimatefury:BAAANQAECgQIBQAAAA==.',
Un='Unb:BAAANQAECgEIBgAAAA==.Unbiased:BAABNQAECn8sAAMUAAoK+hk4NQBUAgAUAAgKGxg4NQBUAgAPAAoKmhemNQADAgAAAA==.Unholyblodd:BAAANQADCggIIAAAAA==.Unshookable:BAABNQAECn80AAICAAoKaCJGBQBNAwACAAoKaCJGBQBNAwAAAA==.',
Ur='Ursos:BAAANQAECgYICAAAAA==.Urìko:BAAANQAECgQIBAAAAA==.',
Ut='Utrig:BAAANQAECgYIBgABNQAECgYICAADAAAAAA==.',
Va='Vaelor:BAAANQADCgQIBAABNQAECgYICAADAAAAAA==.Valsande:BAAANQADCgIIAgAAAA==.',
Ve='Vecnah:BAAANQADCgMIAwAAAA==.Vermax:BAAANQAECgYICwAAAA==.',
Vi='Vika:BAAANQADCggIEQABNQAECgYICAADAAAAAA==.Vita:BAAANQADCgMJAwAAAA==.',
Vo='Voidh:BAABNQAECn8UAAMSAAgKowzQRwCoAAAhAAYK3wtDTAD3AAASAAMKFAzQRwCoAAAAAA==.Voidlockus:BAAANQAECggIDgAAAA==.Voorhees:BAAANQABCgQIBAAAAA==.',
Vu='Vulcin:BAABNQAECn8hAAITAAoKOxtyJgDQAgATAAoKOxtyJgDQAgABNQAECgoKQAAWAP8fAA==.',
Wa='War:BAAANQADCgQIBAABNQAFFAQICQAKAJ8WAA==.Wariuus:BAAANQAECgUIBgAAAA==.Watercupp:BAAANQAECgUIDQAAAA==.',
Wh='Whiskie:BAAANQADCgQIBAAAAA==.Whitelïght:BAAANQAECgUIBgAAAA==.Whsprngihntr:BAAANQADCggICAAAAA==.',
Wi='Wibblës:BAABNQAECn8lAAMbAAgKJB8SMQCdAgAbAAgKJB8SMQCdAgAXAAMKRhm+5gDKAAAAAA==.Windsor:BAAANQAECgIIAgAAAA==.',
Wr='Wrathtiger:BAAANQADCgIIAgAAAA==.',
Xi='Xial:BAAANQAECgEIAQABNQAECgEIAgADAAAAAA==.Xingcai:BAAANQADCgQIBAAAAA==.',
Xy='Xyfin:BAAANQADCggIDwAAAA==.',
Yd='Ydehhteb:BAAANQADCgEIAQABNQAECgIIAgADAAAAAA==.',
Za='Zandramadas:BAABNQAECn8rAAMBAAoKnhlHGQByAgABAAoKnhlHGQByAgAaAAgKGA8DSgC/AQAAAA==.Zaraline:BAABNQAECn8fAAIJAAcKYh2mbQA3AgAJAAcKYh2mbQA3AgAAAA==.',
Ze='Zeakz:BAAANQAECgEIAgAAAA==.',
Zi='Zinyak:BAAANQAECgUIDAAAAA==.',
Zo='Zoomiez:BAAANQAECgQICgAAAA==.',
Zp='Zpai:BAABNQAECn8fAAMMAAoKnBhDDwD8AQAMAAoKnBhDDwD8AQAjAAYKbAWxTADFAAAAAA==.',
Zy='Zyfae:BAAANQAECggIBAAAAA==.Zyyn:BAAANQAECgYICgAAAA==.',
['Äc']='Ächilles:BAAANQAECgEIAQAAAA==.',
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
