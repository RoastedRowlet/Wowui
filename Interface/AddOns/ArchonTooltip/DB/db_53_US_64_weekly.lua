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

local lookup = {'Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Monk-Windwalker','Hunter-BeastMastery','Priest-Holy','Unknown-Unknown','Druid-Feral','DemonHunter-Havoc','Shaman-Restoration','Shaman-Elemental','Shaman-Enhancement','Priest-Shadow','Mage-Arcane','Warrior-Protection','Mage-Frost','Warrior-Arms','DemonHunter-Devourer','Paladin-Protection','Paladin-Retribution','Evoker-Devastation','Druid-Balance','Monk-Brewmaster','DeathKnight-Blood','Paladin-Holy','DeathKnight-Frost','DeathKnight-Unholy','DemonHunter-Vengeance','Rogue-Outlaw','Druid-Guardian','Rogue-Assassination','Hunter-Marksmanship','Priest-Discipline','Evoker-Preservation','Hunter-Survival','Druid-Restoration','Warrior-Fury','Monk-Mistweaver',}
local provider = {region='US',realm='Deathwing',name='US',type='weekly',zone=53,date='2026-10-20',data={Aa='Aamix:BAACNQAFFH8RAAQBAAYKWAuUJQDWAAABAAQKQQ6UJQDWAAACAAEKAABZEABEAAADAAEKnQLkIwBBAAA1AAQKf0cAAwEACgoDHaouAMwCAAEACQoDHKouAMwCAAMABgo0DjUhAGcBAAAA.Aarom:BAACNQAFFH8XAAIEAAcK8xkyAwA7AgAEAAcK8xkyAwA7AgA1AAQKfyYAAgQACgpfI4MHAJcBAAQACgpfI4MHAJcBAAAA.Aaronk:BAAANQADCggIDwAAAA==.',
Ab='Abdltdoc:BAABNQAECn8ZAAIFAAgKpR/ELADnAgAFAAgKpR/ELADnAgAAAA==.Abrakastaba:BAAANQAECgcIBwABNQAFFAUIEwAGALweAA==.',
Ae='Aelyn:BAAANQADCgQIBAAAAA==.Aelyndra:BAAANQAECgcIDAAAAA==.Aequitas:BAAANQADCgcIDAAAAA==.Aerius:BAAANQAECgUICQAAAA==.',
Af='Affliclock:BAACNQAFFH8LAAICAAUKOBnhAAChAQACAAUKOBnhAAChAQA1AAQKfxwAAgIACQpkIasCAOsCAAIACQpkIasCAOsCAAAA.',
Ai='Aingerfal:BAAANQAECgUIBgABNQAECgcIDAAHAAAAAA==.',
Aj='Aj:BAAANQAFFAEIAQAAAA==.',
Ak='Akasori:BAABNQAECn87AAIIAAoKhyGBAgCMAwAIAAoKhyGBAgCMAwAAAA==.Akisori:BAAANQAECggIDAABNQAECgoKOwAIAIchAA==.Akosori:BAAANQAECgMIBAABNQAECgoKOwAIAIchAA==.',
Al='Alistaier:BAAANQAECgEIAQABNQAECgoKNQAJAGEaAA==.Allnaturale:BAAANQAECgQIBAAAAA==.Alterboyy:BAAANQAECgUIEAAAAA==.Alîsonshammy:BAACNQAFFH8QAAMKAAUKNR0FCADUAQAKAAUKNR0FCADUAQALAAMKtgYEHgDKAAA1AAQKfyQAAwoACgp4I5gQAEADAAoACgp4I5gQAEADAAsACArlG6dPADkCAAAA.',
Am='Ambersulfr:BAABNQAECn8bAAIMAAcKKxzZFgD7AQAMAAcKKxzZFgD7AQAAAA==.Ambrus:BAAANQADCgYIBgAAAA==.Amrazz:BAABNQAECn8cAAMGAAkKbhktKADJAgAGAAkKbhktKADJAgANAAIKQweFaQBbAAAAAA==.Amzey:BAEBNQAECn8wAAIOAAkKnh+YMQAoAwAOAAkKnh+YMQAoAwAAAA==.',
An='Anahata:BAAANQADCgEIAgABNQADCgcICwAHAAAAAA==.Andromeda:BAABNQAECn8yAAIPAAoKRxnkBwDXAgAPAAoKRxnkBwDXAgAAAA==.Anneaux:BAAANQAECgIJAgAAAA==.',
Ar='Arcaneråge:BAAANQADCgEIAQABNQADCgQIBQAHAAAAAA==.Aridillo:BAAANQAECgEIAQAAAA==.Armani:BAAANQADCgIIAgAAAA==.',
As='Ashaea:BAAANQAECgEIAQAAAA==.Ashaka:BAAANQAECgUICwAAAA==.Astralus:BAABNQAECn8VAAIQAAYKmRtsDgDEAQAQAAYKmRtsDgDEAQAAAA==.Astramis:BAABNQAECn8fAAIQAAcKrQiqFgBIAQAQAAcKrQiqFgBIAQAAAA==.',
At='Athennaa:BAAANQADCgYIBgAAAA==.Atomicbarbie:BAABNQAECn8jAAIRAAkKMRkBSwCoAgARAAkKMRkBSwCoAgABNQAFFAUIEAAKADUdAA==.Atriøx:BAAANQAECgIIAwAAAA==.Atziri:BAABNQAECn8vAAILAAoKgBcINwCbAgALAAoKgBcINwCbAgAAAA==.',
Av='Avalinia:BAAANQADCgIIAgAAAA==.',
Az='Azamia:BAAANQAECgUIEQABNQABCgIIAwAHAAAAAA==.',
Ba='Babyknife:BAAANQAECgIIAgABNQAFFAcIFwAEAPMZAA==.Backlash:BAABNQAECn8fAAISAAkKgRWMHgBcAgASAAkKgRWMHgBcAgAAAA==.Balzhac:BAABNQAECn8hAAMTAAoKdB0UAgA/AgATAAgK7yEUAgA/AgAUAAQK7Rd9CgENAQAAAA==.Bam:BAAANQADCggICAABNQAFFAcIHAAJABEYAA==.Bamplify:BAABNQAECn8ZAAIOAAoKox6dTwDiAgAOAAoKox6dTwDiAgABNQAFFAcIHAAJABEYAA==.Barrierbobo:BAABNQAECn8gAAIGAAgK3BJ/FADOAQAGAAgK3BJ/FADOAQAAAA==.Barthold:BAAANQADCggIHAAAAA==.',
Be='Beleaf:BAAANQAECggIDQAAAA==.Bellmonte:BAAANQADCgYIDwABNQAECggIJQAVAJsZAA==.Belmonk:BAAANQAECgQIBQAAAA==.Berdron:BAABNQAECn84AAQDAAoKnREdCgBVAgADAAoKnREdCgBVAgABAAMKBQZjmgBaAAACAAEKAAB4MwAsAAAAAA==.',
Bi='Biden:BAAANQAECgMIBAAAAA==.',
Bl='Bladeliger:BAABNQAECn8yAAIWAAoKIRlGHgDYAgAWAAoKIRlGHgDYAgAAAA==.Blazin:BAAANQAECgEIAQAAAA==.Bledsmasher:BAAANQADCgUIBQAAAA==.Blouses:BAABNQAECn8hAAIRAAkKiyRxHwA6AwARAAkKiyRxHwA6AwAAAA==.',
Bo='Boltsgobrr:BAAANQADCgIIAgAAAA==.Boned:BAABNQAECn8cAAMXAAgKrBsKCwBeAgAXAAcK/B0KCwBeAgAEAAIKIBA2NAA+AAAAAA==.Bonemair:BAACNQAFFH8iAAIYAAYK7huOCQDBAQAYAAYK7huOCQDBAQA1AAQKfzMAAhgACgqDIIoSABgDABgACgqDIIoSABgDAAAA.Boomguy:BAAANQADCgQIBAABNQAECgoKKAAZAFkRAA==.Boredasf:BAAANQADCgYIBgAAAA==.Boricuazo:BAAANQADCgYIBgAAAA==.',
Br='Bradocks:BAAANQADCggIJQAAAA==.Breezeblocks:BAAANQADCgEIAQAAAA==.Bryteblade:BAAANQADCgMIAwABNQAECggIDAAHAAAAAA==.',
Bu='Bubblehooker:BAAANQAECggIAgAAAA==.Buffnbeers:BAAANQADCgYICwABNQAFFAUIEwAGALweAA==.Bullteesta:BAAANQAECgUICwAAAA==.Burkhard:BAAANQADCggIBwAAAA==.',
Bw='Bwonurjor:BAAANQADCgQIBAAAAA==.',
['Bó']='Bónes:BAAANQAECgMIBQAAAA==.',
Ca='Caldec:BAACNQAFFH8jAAMaAAcKGiSFAAC/AgAaAAcKGiSFAAC/AgAbAAUKig+QBwChAQA1AAQKfzQAAhoACgqtJOIFAIIDABoACgqtJOIFAIIDAAAA.',
Ch='Chainizard:BAAANQAECggIDAAAAA==.Chainpwn:BAAANQAECgUIBQABNQAECggIDAAHAAAAAA==.Chaosofelune:BAAANQAECgIIAgAAAA==.Chaosoflife:BAAANQAECgIJAgAAAA==.Chaosoflight:BAAANQAECgUIBQAAAA==.Cheeno:BAABNQAECn8qAAMSAAoKsySPAgC0AwASAAoKsySPAgC0AwAcAAEKPSKLKwBYAAAAAA==.Chihiro:BAAANQAECgUIEgAAAA==.Chillay:BAAANQADCgEIAQAAAA==.Chillyblinks:BAABNQAFFH8HAAMQAAMKCRDpAgCaAAAQAAIKyg/pAgCaAAAOAAEKhxBiJgBOAAAAAA==.Chillyfists:BAAANQADCgUIBQAAAA==.Chillygowosh:BAAANQAECgEIAQABNQAFFAMIBwAQAAkQAA==.Chloris:BAAANQADCgMIAwABNQAECgQIBQAHAAAAAA==.Chuffed:BAAANQAECgEIAQAAAA==.',
Ci='Cinderheart:BAAANQABCgYIBgAAAA==.Ciymi:BAAANQAECgcICAABNQAFFAcICwAOAP8SAA==.',
Cl='Clarabelle:BAACNQAFFH8LAAMOAAcK/xLREADxAQAOAAYKABXREADxAQAQAAEK+QoYDgBUAAA1AAQKfyMAAw4ACgpMIX4gAFgDAA4ACgoEIX4gAFgDABAAAgo4IwUkAM0AAAAA.Clisholder:BAAANQADCgQIBAAAAA==.',
Co='Coaltaine:BAAANQADCgMJAwABNQAECggIDAAHAAAAAA==.Computer:BAACNQAFFH8FAAIBAAQK6w73GgAfAQABAAQK6w73GgAfAQA1AAQKfyMAAwMACQqCH/8EANECAAMACArtIf8EANECAAEACAq8HBpSAF8CAAAA.Cootin:BAAANQAECggIEAAAAA==.',
Cp='Cpteddie:BAABNQAECn8eAAMTAAkKUR4UEgCAAgATAAkKUR4UEgCAAgAUAAMKahFpUQGeAAABNQAFFAYIEwAYAEAaAA==.',
Cr='Craigg:BAAANQADCgYIBgAAAA==.Crate:BAAANQADCgQIBAABNQAECgEIAQAHAAAAAA==.Crelam:BAACNQAFFH8kAAIMAAcKpA5NAACIAQAMAAcKpA5NAACIAQA1AAQKfzMAAgwACgqtG0YMAKsCAAwACgqtG0YMAKsCAAAA.Critherine:BAAANQAECgUIDgAAAA==.Cronatherus:BAAANQAECgMIBAAAAA==.Cruentis:BAABNQAECn8rAAIdAAkKrBZ0BwA/AgAdAAkKrBZ0BwA/AgAAAA==.Crysuh:BAAANQAECgMIAwABNQAECgcIDwAHAAAAAA==.Crysus:BAAANQAECgcIDwAAAA==.',
Da='Dabo:BAABNQAECn8jAAIWAAoKmB50GgD1AgAWAAoKmB50GgD1AgAAAA==.Damarisalynn:BAAANQADCgUIBQAAAA==.Darkurgekris:BAAANQADCggICAABNQAECgkJIQARAIskAA==.Darwin:BAABNQAECn8hAAMbAAgK4hXdVQC6AQAbAAYKIRzdVQC6AQAaAAgKbw2kTwB1AQAAAA==.Dasmoodhayn:BAAANQAECgUICgAAAA==.Davalanch:BAABNQAECn8fAAILAAkKxRZARABlAgALAAkKxRZARABlAgAAAA==.Dazizejr:BAACNQAFFH8LAAIYAAQKuB0uBgD2AAAYAAQKuB0uBgD2AAA1AAQKfzIAAhgACgpdIyYFAKADABgACgpdIyYFAKADAAAA.',
De='Deathisbrew:BAAANQAECggIEAAAAA==.Deathxrage:BAAANQADCgcIDwAAAA==.Decor:BAAANQADCgYICgAAAA==.Deerhunter:BAAANQAECggICAAAAA==.Denïed:BAAANQADCgYICgAAAA==.Deonand:BAAANQADCggIDAAAAA==.Deramooke:BAAANQADCgcIBwAAAA==.Dethkløk:BAAANQADCggIEQAAAA==.',
Di='Dibstrum:BAABNQAECn8YAAIOAAYKqAwtXgABAQAOAAYKqAwtXgABAQAAAA==.Digduug:BAABNQAECn8XAAIBAAYKLw/JwABKAQABAAYKLw/JwABKAQAAAA==.Dixqt:BAAANQAECgcIDgAAAA==.',
Do='Dogfight:BAACNQAFFH8WAAQbAAYKDxWfCQB7AQAbAAUKDxWfCQB7AQAaAAEKYQDxIgAqAAAYAAEKAADCNQAoAAA1AAQKfy0ABBsACgqLG54oAJcCABsACgrIGZ4oAJcCABoAAgpHC/WdAFUAABgAAQoAAMbNAC8AAAAA.Doilookfatou:BAABNQAECn8aAAMeAAkKrhs9DAClAgAeAAgKDB89DAClAgAWAAYKKge0cAAHAQAAAA==.',
Dr='Draxus:BAABNQAECn8aAAIfAAcKuAaDVgBgAQAfAAcKuAaDVgBgAQAAAA==.Dresel:BAABNQAECn8dAAIFAAkKNRjsNwDCAgAFAAkKNRjsNwDCAgAAAA==.Drewpeebahlz:BAABNQAECn8aAAIZAAkKrBnlNACQAgAZAAkKrBnlNACQAgABNQABCgIIAgAHAAAAAA==.Drshakaloo:BAAANQADCggIHQAAAA==.',
Du='Dunnome:BAAANQAECgIIAgAAAA==.Durto:BAAANQADCgcIDQAAAA==.',
Dy='Dyami:BAABNQAECn8wAAMFAAoK9iPkCgAfAgAFAAkKbSTkCgAfAgAgAAYKZBthMADLAQAAAA==.Dynas:BAABNQAECn8fAAQhAAcKkApsEAAiAQAhAAYK/QtsEAAiAQAGAAUKkwRexgDMAAANAAYKjAPKIgB3AAAAAA==.',
Ea='Earthcake:BAACNQAFFH8IAAMLAAMKKRAhDACYAAALAAIKKRAhDACYAAAKAAEKHwYDLgA/AAA1AAQKfzAAAwsACgp1HlkVAEkDAAsACQpXIVkVAEkDAAoABgqlCPRTALUAAAAA.',
Ed='Eddielich:BAACNQAFFH8TAAIYAAYKQBoGBwD4AQAYAAYKQBoGBwD4AQA1AAQKfyUAAhgACgqGIqQJAGoDABgACgqGIqQJAGoDAAAA.Eddieteddie:BAAANQAECggICwABNQAFFAYIEwAYAEAaAA==.',
Eg='Eggfumonk:BAAANQAECggIDAAAAA==.',
Eh='Ehlo:BAAANQADCgEIAQABNQADCgcIBwAHAAAAAA==.',
El='Elasmon:BAABNQAECn8UAAIdAAgKuBUsCQD+AQAdAAgKuBUsCQD+AQAAAA==.Elbodeep:BAAANQADCgQIBAAAAA==.Elfpen:BAAANQAECgUIBwAAAA==.Ellan:BAABNQAECn8fAAMOAAoKdRVHmQBOAgAOAAkK3BZHmQBOAgAQAAEKqQsKGQBAAAAAAA==.',
Em='Emongalkar:BAAANQADCgQIBAAAAA==.',
Er='Erragal:BAAANQAECgUIBwAAAA==.',
Es='Escanõr:BAABNQAECn8XAAIUAAkK1hLohQAbAgAUAAkK1hLohQAbAgAAAA==.',
Ez='Ezindrozar:BAAANQADCggICwAAAA==.',
Fa='Falek:BAAANQAECgEIAQAAAA==.Faustyne:BAABNQAECn8YAAIBAAcKpQf5NgAlAQABAAcKpQf5NgAlAQABNQAFFAYIDQAFAMsUAA==.',
Fe='Felir:BAAANQADCggICAAAAA==.Felover:BAAANQAECgcICQAAAA==.Felurián:BAAANQAECgYICwABNQADCgcIGgAHAAAAAA==.Fexli:BAAANQAECgUIBQAAAA==.',
Fi='Fireteeth:BAAANQADCggIEwAAAA==.Fiverunner:BAAANQADCgYICgAAAA==.Fizc:BAAANQAECgEIAQAAAA==.',
Fl='Flurtty:BAAANQADCgYIDwAAAA==.',
Fo='Folklore:BAABNQAECn8aAAIeAAcKcRSWHwCgAQAeAAcKcRSWHwCgAQAAAA==.Forklift:BAAANQAECgIIAwABNQAECgoKLAAiAC4gAA==.Foxrocks:BAAANQABCgMIAwAAAA==.',
Fr='Frighrish:BAAANQAECgEIAQAAAA==.Frigomortis:BAAANQAECgUICwABNQAECgYIFQALACMIAA==.Frozown:BAABNQAECn8jAAIOAAcK6hVZ3QDNAQAOAAcK6hVZ3QDNAQAAAA==.Fruits:BAAANQAECgUICgAAAA==.Fruitsack:BAAANQAECgcIEwABNQAECgUICgAHAAAAAA==.',
Ft='Ftfw:BAAANQAECgYIDgAAAA==.',
Fu='Funfanfare:BAAANQAECgYICAAAAA==.Furrybunz:BAAANQAECgEIAQAAAA==.Furrylife:BAAANQAECgIIAgAAAA==.Fusebawx:BAAANQADCgUIBgABNQAECgEIAQAHAAAAAA==.Fuzzychin:BAAANQAECgYIDQABNQAFFAMIBwAQAAkQAA==.',
['Fò']='Fòrlorn:BAAANQABCgEIAQAAAA==.',
Ga='Galram:BAABNQAECn8nAAIjAAgKdhMFAgCXAQAjAAgKdhMFAgCXAQABNQAFFAcIJAAMAKQOAA==.Gardettos:BAABNQAECn8sAAIiAAoKLiDNCQAGAwAiAAoKLiDNCQAGAwAAAA==.Gargingoyles:BAAANQADCgIJAgAAAA==.',
Gh='Gharghael:BAAANQAECgUICgAAAA==.Ghostthunter:BAAANQADCgQIBAABNQAECggIFgAaAFYdAA==.',
Gi='Gip:BAAANQADCggICAAAAA==.',
Gl='Glimmair:BAABNQAECn8YAAITAAgKmRpoGAA0AgATAAgKmRpoGAA0AgABNQAFFAYIIgAYAO4bAA==.Glimmer:BAAANQADCggIDQAAAQ==.',
Gn='Gnxrli:BAEANQADCgIIAgABNQAFFAIIBgAEALsiAA==.Gnxrly:BAEANQAECgEIAgABNQAFFAIIBgAEALsiAA==.Gnxrr:BAECNQAFFH8GAAIEAAIKuyI4DQDKAAAEAAIKuyI4DQDKAAA1AAQKfy4AAgQACgrmJF0DAKEDAAQACgrmJF0DAKEDAAAA.',
Go='Gooncaine:BAAANQAECgYICgAAAA==.Gorammasta:BAAANQAECgcICQABNQAECggIFAAdALgVAA==.Gorbstrasz:BAAANQAECgIIAQAAAA==.Gorpse:BAAANQAECgUICwAAAA==.',
Gr='Gregorz:BAAANQAECgUIBQAAAA==.Greyanna:BAABNQAECn8dAAIFAAgKhAb7PwA2AQAFAAgKhAb7PwA2AQAAAA==.Gridon:BAAANQADCgYIBgAAAA==.Gripguy:BAAANQADCggICAABNQAECgoKKAAZAFkRAA==.Gromthrall:BAAANQAECggIEgAAAA==.',
Gw='Gwaea:BAAANQADCgIIAgAAAA==.Gworp:BAAANQAECgIJAwAAAA==.Gwynhwyfar:BAAANQAECgMIBQABNQAECgkJHwAFACYXAA==.',
['Gú']='Gúi:BAAANQAECgEIAQAAAA==.',
Ha='Hailin:BAAANQADCgYIBgAAAA==.Hammersplash:BAAANQADCgQIBAAAAA==.Hangsut:BAAANQABCgQICgAAAA==.',
Hb='Hbhealthen:BAACNQAFFH8eAAIiAAcKNxtFAwBiAgAiAAcKNxtFAwBiAgA1AAQKf0EAAyIACgo/I2EDAIIDACIACgo/I2EDAIIDABUAAgrnEIUzAHEAAAAA.',
He='Hellhore:BAAANQAECgMICwAAAA==.Hemila:BAAANQAECgYIDAABNQAECggIFQAIAOUNAQ==.Hetamala:BAAANQADCgMIAwAAAA==.',
Hi='Highego:BAAANQAECggIEgAAAA==.',
Ho='Holdenc:BAAANQAECgQIBgABNQAECgoKLwAKAEUfAA==.Hoodz:BAABNQAECn8vAAIRAAoK8yKDEwBuAwARAAoK8yKDEwBuAwAAAA==.Houseplant:BAAANQAECgUIBQAAAA==.Howard:BAAANQAECgUIDwAAAA==.',
Hu='Huatli:BAAANQADCggIEgAAAA==.Huzzarr:BAAANQABCgIIAgAAAA==.',
Hy='Hypnos:BAAANQADCgEIAQAAAA==.',
Ib='Ibearprofen:BAAANQAECgQICAAAAA==.',
Ic='Icerod:BAAANQADCgUIBQABNQAECgUICgAHAAAAAA==.',
Id='Idtrapdat:BAACNQAFFH8HAAMFAAMKoh/3HwCzAAAFAAIKoh/3HwCzAAAgAAIKIQ6qHACMAAA1AAQKfzQAAwUACgq6IyQRAF0DAAUACgq6IyQRAF0DACAABQpcGJ4QAAMBAAAA.',
Il='Illyana:BAABNQAECn8ZAAMaAAoKCiNoEAAMAwAaAAoKqyFoEAAMAwAbAAYK5yHbNABWAgAAAA==.Ilse:BAABNQAECn8wAAIZAAoKWR5eGQATAwAZAAoKWR5eGQATAwAAAA==.',
Im='Imagined:BAACNQAFFH8kAAMOAAcKORXhBQBlAgAOAAcKORXhBQBlAgAQAAIK/QfBCQB9AAA1AAQKfzEAAg4ACgqsHnNXANECAA4ACgqsHnNXANECAAAA.',
In='Indihunter:BAAANQADCgEIAQAAAA==.Infernis:BAAANQADCgcIDAAAAA==.Infidelic:BAAANQADCgYICwABNQAECgUIDwAHAAAAAA==.',
Ir='Ironchords:BAAANQADCgEIAQAAAA==.',
Iv='Ivank:BAABNQAECn8iAAIBAAoKgQ38XwA4AgABAAoKgQ38XwA4AgAAAA==.Ivracha:BAAANQAECgEJAQAAAA==.',
Ja='Jage:BAAANQAECgcICwAAAA==.Jararacuh:BAAANQAECgIIAgABNQAECgoKMAAOAGIZAA==.Jarsham:BAABNQAECn8VAAILAAYKIwgmrQA5AQALAAYKIwgmrQA5AQAAAA==.Jaràdan:BAABNQAECn8UAAIBAAoKNw1DbgAUAgABAAoKNw1DbgAUAgABNQAECgoKMAAOAGIZAA==.Jawshua:BAAANQAECgEIAQAAAA==.',
Je='Jeff:BAABNQAECn80AAIRAAoKyx1iLAALAwARAAoKyx1iLAALAwAAAA==.',
Jo='Joran:BAABNQAECn8UAAIJAAYKhgaxLwCtAAAJAAYKhgaxLwCtAAAAAA==.Jord:BAAANQAECgEIAQAAAA==.Jordie:BAAANQADCgIIAgAAAA==.Joredin:BAAANQADCgcIBwAAAA==.Jorlannee:BAAANQADCgEIAQABNQADCgcIGgAHAAAAAA==.',
Jr='Jroc:BAAANQAFFAEIAQAAAA==.',
Ju='Judelene:BAAANQAECgQIBgAAAA==.',
Jw='Jwrs:BAABNQAECn8fAAIRAAgKuREApgC+AQARAAgKuREApgC+AQAAAA==.',
['Jï']='Jïbril:BAABNQAECn8kAAIYAAoKMxfcLwBSAgAYAAoKMxfcLwBSAgAAAA==.',
Ka='Kabbala:BAABNQAECn8XAAIBAAgK2wyCKgBJAQABAAgK2wyCKgBJAQABNQAFFAcIJAAOADkVAA==.Kahlani:BAABNQAECn8yAAIKAAoKhRDEVgANAgAKAAoKhRDEVgANAgAAAA==.Kahlua:BAAANQAECgYICQAAAA==.Kailan:BAABNQAECn8ZAAISAAYKXxr5KAD8AQASAAYKXxr5KAD8AQABNQAECgoKNQANAEsgAA==.Kalathios:BAAANQABCgIIAgABNQAECgQIBQAHAAAAAA==.Kaldro:BAAANQAECgcIDAAAAA==.Kaliae:BAAANQADCgYIBAAAAA==.Kaly:BAABNQAECn8wAAIXAAoKSAwMEgDFAQAXAAoKSAwMEgDFAQAAAA==.Kano:BAAANQAECgMIBAAAAA==.Kariana:BAABNQAECn81AAMLAAoKahX4FwBiAQALAAoKahX4FwBiAQAKAAgKyQTcowAsAQAAAA==.Kathry:BAAANQADCggIGgAAAA==.',
Ke='Keelzya:BAAANQAECggICAAAAA==.Keepdreaming:BAABNQAECn8wAAIkAAoKaRMIDwBTAQAkAAoKaRMIDwBTAQAAAA==.Kefkka:BAAANQADCgEIAQAAAA==.Keme:BAAANQAECgEIAQABNQAECggIEQAHAAAAAA==.Keybricker:BAAANQAECgYIBgABNQAFFAUIEwAGALweAA==.Keymebrah:BAABNQAECn8bAAMOAAkKmhLpxAD6AQAOAAkKHBLpxAD6AQAQAAMKnRHTLgCIAAAAAA==.',
Ki='Killeh:BAAANQADCggIFAAAAA==.',
Ko='Korda:BAAANQAECgIIAgAAAA==.Korinä:BAABNQAECn8hAAIfAAgKRxCtCgB5AQAfAAgKRxCtCgB5AQAAAA==.Kosh:BAAANQAECgUIBwAAAA==.Koyra:BAACNQAFFH8fAAIVAAcKpSUeAAD+AgAVAAcKpSUeAAD+AgA1AAQKfzEAAhUACgoiJgUCAJ0DABUACgoiJgUCAJ0DAAAA.',
Kr='Kreyden:BAAANQAECgMIAwAAAA==.Krump:BAAANQAECgUIBgAAAA==.',
Ku='Kubbles:BAAANQADCggICAAAAA==.Kubs:BAAANQADCgcIDAAAAA==.Kubwa:BAAANQABCgcIDwAAAA==.Kungfugimp:BAAANQAECgcIDwAAAA==.Kurral:BAACNQAFFH8jAAMWAAcK0RF0BwAVAgAWAAcK0RF0BwAVAgAkAAcK/gALBgC8AAA1AAQKfy8AAxYACgrmHSUcAOcCABYACgrmHSUcAOcCACQABArrBO1bAJgAAAAA.Kurralium:BAABNQAECn8hAAIQAAgKxQ82BABxAQAQAAgKxQ82BABxAQABNQAFFAcIIwAWANERAA==.Kurstina:BAAANQADCgYICQAAAA==.Kuzushi:BAABNQAECn8YAAIUAAkKRwdUdQDdAAAUAAkKRwdUdQDdAAAAAA==.',
Ky='Kyramus:BAABNQAECn8fAAIPAAgKUCUYAQB3AgAPAAgKUCUYAQB3AgAAAA==.',
La='Laconia:BAABNQAECn8lAAIVAAgKmxnYDQCCAgAVAAgKmxnYDQCCAgAAAA==.Lashstorm:BAAANQAECggIDgAAAA==.Lattsatnar:BAAANQAECgQICwAAAA==.',
Le='Lebron:BAAANQAECggIDgAAAA==.Lelesobi:BAAANQADCgUIBgAAAA==.Lennel:BAAANQAECgQICQAAAA==.Lewd:BAAANQAECggIAgAAAA==.',
Lg='Lga:BAAANQADCgYIEAAAAA==.',
Li='Lilsnick:BAAANQAECgUIEgAAAA==.Lisaluv:BAAANQAECggICAAAAA==.Litterbawx:BAAANQADCgYIBgABNQAECgEIAQAHAAAAAA==.',
Ll='Llanthyl:BAABNQAECn8iAAIlAAkKnxHxAQDWAQAlAAkKnxHxAQDWAQAAAA==.',
Lo='Lockbawx:BAAANQAECgEIAQABNQAECgEIAQAHAAAAAA==.Loktardogard:BAAANQADCgUIBQAAAA==.Loku:BAAANQABCggICQAAAA==.',
Lu='Lucía:BAABNQAFFH8HAAIYAAYKMhRGDwBhAQAYAAYKMhRGDwBhAQAAAA==.Luecien:BAAANQADCgUIBQAAAA==.Luithica:BAAANQAECgEIAQAAAA==.Lunafalia:BAABNQAECn8yAAIQAAoKWRfqBQCrAgAQAAoKWRfqBQCrAgAAAA==.Lupon:BAAANQAECggICAAAAA==.Lurosa:BAACNQAFFH8NAAIkAAYK+B7mBADUAQAkAAYK+B7mBADUAQA1AAQKfyoAAyQACgoMJXoAAOUDACQACgoMJXoAAOUDABYAAgqABqhEAFYAAAAA.Luxeria:BAAANQAECgcIDQAAAA==.Luxray:BAAANQABCggIFQAAAA==.',
Lv='Lvck:BAEANQAECgcICAABNQAFFAIIBgAEALsiAA==.',
Ly='Lyrae:BAAANQADCgYIBwAAAA==.',
['Lî']='Lîlydan:BAAANQADCgUIBwAAAA==.',
['Lï']='Lïchkinged:BAAANQAECgcICwAAAA==.',
Ma='Macready:BAACNQAFFH8MAAIPAAQK5yFdAwArAQAPAAQK5yFdAwArAQA1AAQKfy4AAg8ACgpUJM4GAPQCAA8ACgpUJM4GAPQCAAAA.Madmimm:BAAANQADCgcIBwAAAA==.Magenin:BAAANQAECgYICAAAAA==.Maggotgut:BAAANQAECgUICQAAAA==.Magoren:BAAANQADCgUIBgAAAA==.Mairbear:BAAANQAECggIBwABNQAFFAYIIgAYAO4bAA==.Mairiachi:BAAANQAECgYIBwABNQAFFAYIIgAYAO4bAA==.Maltessa:BAAANQADCgUICgABNQAECgoKNQANAEsgAA==.Marload:BAACNQAFFH8PAAMFAAYKURICFAAmAQAFAAUKURICFAAmAQAgAAQK3w2DFAD4AAA1AAQKfzcAAyAACgopHkcaAIMCACAACQpGFkcaAIMCAAUACgp9HTdPAIECAAAA.Mathy:BAABNQAECn8VAAMMAAkKhBI+EgBGAgAMAAkKhBI+EgBGAgAKAAIKJAP+CwFQAAAAAA==.',
Me='Melath:BAAANQADCggIFQAAAA==.Melreu:BAAANQADCgEIAQABNQAECgoKKgASALMkAA==.',
Mi='Midletons:BAAANQAECgYIDgAAAA==.Minikub:BAABNQAECn8lAAIEAAgK0wv5DQBCAQAEAAgK0wv5DQBCAQAAAA==.Mischievous:BAAANQAECggIEgAAAA==.Mixxy:BAAANQAECgUICAABNQAFFAcIFwAEAOAXAA==.Mizu:BAAANQAECggIEQAAAA==.',
Mn='Mnzn:BAAANQADCggIGgAAAA==.',
Mo='Moobubble:BAABNQAECn8VAAIUAAoKxBWodABEAgAUAAoKxBWodABEAgABNQAFFAMICAALACkQAA==.Moodroo:BAAANQAECgUIEAAAAA==.Moonanoke:BAAANQAECgUICwAAAA==.Moovoker:BAABNQAECn84AAIiAAoKfiLdAAD0AgAiAAoKfiLdAAD0AgAAAA==.Morseques:BAABNQAECn8uAAMbAAoKkCJIDABYAwAbAAoKkCJIDABYAwAYAAEKAAAXtABhAAAAAA==.Mortimer:BAAANQAECgMIBQAAAA==.Mothra:BAAANQADCggICAAAAA==.Moz:BAAANQADCgMIAwAAAA==.',
Mu='Muggy:BAACNQAFFH8QAAQbAAcKlBo5BgC8AQAbAAUKyho5BgC8AQAYAAEKAADkIwBuAAAaAAEKvRkGDABfAAA1AAQKfzkAAxsACgrXJUkEALADABsACQpjJkkEALADABoACQpWIKsCAHYCAAAA.Muguda:BAAANQADCgMIAwAAAA==.',
Mx='Mxkebfistin:BAACNQAFFH8XAAIEAAcK4BddAwA0AgAEAAcK4BddAwA0AgA1AAQKfysAAgQACgoPIAUMABUDAAQACgoPIAUMABUDAAAA.Mxkebspinnin:BAAANQADCggICAABNQAFFAcIFwAEAOAXAA==.',
Na='Narama:BAACNQAFFH8dAAMBAAcKGAY3BgAEAQABAAYKUAY3BgAEAQADAAIKZQMzEwB7AAA1AAQKfzEABAMACgqZEXslAEgBAAEACgpuEDNmACgCAAMABgpMDnslAEgBAAIAAQoAABg1ACYAAAAA.',
Ne='Nekka:BAABNQAECn8aAAIKAAcKyxZXEgDDAQAKAAcKyxZXEgDDAQAAAA==.Nethanos:BAAANQAECgUICwAAAA==.Neverrmore:BAAANQAECgEIAQAAAA==.Nexotic:BAAANQADCgcICAABNQAECgQIDAAHAAAAAA==.',
Ni='Ninæ:BAACNQAFFH8RAAIiAAYKuBV2CQCaAQAiAAYKuBV2CQCaAQA1AAQKfysAAiIACgoLIzYFAFgDACIACgoLIzYFAFgDAAAA.Nitewïng:BAAANQAECggIGwABNQADCggIDQAHAAAAAQ==.',
No='Nofeet:BAAANQADCgYICwABNQAECgQICQAHAAAAAA==.Nohomoh:BAAANQADCgUIBgAAAA==.Nootau:BAABNQAECn8YAAIOAAcKkR0itQAZAgAOAAcKkR0itQAZAgAAAA==.',
Ny='Nyoz:BAAANQAECgYIDAAAAA==.Nyxxadra:BAABNQAECn80AAIBAAkKMhBRJQBaAQABAAkKMhBRJQBaAQAAAA==.',
Oa='Oakshion:BAAANQAECgEIAQAAAA==.',
Om='Omegadeed:BAABNQAECn8tAAMBAAoKvBUQUwBcAgABAAoKvBUQUwBcAgADAAEKAACnawBJAAAAAA==.Omie:BAAANQAECgEIAQAAAA==.',
On='Onne:BAAANQAECgUIBwAAAA==.',
Or='Orcinus:BAACNQAFFH8IAAIiAAMK6wJaCACXAAAiAAMK6wJaCACXAAA1AAQKfycAAiIACgrnDykYADoCACIACgrnDykYADoCAAAA.Orcishfist:BAAANQAECgcIDgAAAA==.Orvar:BAAANQAECgQIBQABNQABCgIIAgAHAAAAAA==.',
Pa='Pakaru:BAABNQAECn8pAAIUAAoK9BihVQCVAgAUAAoK9BihVQCVAgAAAA==.Pam:BAACNQAFFH8cAAIJAAcKERhKAgBbAQAJAAcKERhKAgBbAQA1AAQKfykAAwkACgrzI/0PACIDAAkACgrzI/0PACIDABIAAgpdHg1YAKkAAAAA.Parathin:BAAANQADCggIFAAAAA==.',
Pe='Peorä:BAABNQAECn8nAAMGAAgKPQ+KHgCMAQAGAAgKPQ+KHgCMAQANAAcKZwOKSgDuAAAAAA==.Perfectdark:BAACNQAFFH8jAAISAAcK2B1GAQCRAgASAAcK2B1GAQCRAgA1AAQKfzUAAxIACgowI6cGAGgDABIACgowI6cGAGgDAAkAAgrCIOpvALoAAAAA.Perse:BAAANQAECgYIBwAAAA==.',
Ph='Phathottie:BAAANQABCgMIBAABNQAECgYIFQALACMIAA==.Pheadas:BAAANQADCgUJBQAAAA==.Phleez:BAAANQADCggICwABNQAECgIIAgAHAAAAAA==.',
Pi='Picklesnrye:BAAANQADCggICwAAAA==.Pieper:BAABNQAECn8fAAIFAAkKJhdJPgA7AQAFAAkKJhdJPgA7AQAAAA==.Pinkee:BAAANQAECggICAAAAA==.Pipa:BAABNQAECn83AAIKAAoKxiRWBQCdAwAKAAoKxiRWBQCdAwAAAA==.Pippit:BAABNQAECn8hAAIZAAgK3xJvYAD3AQAZAAgK3xJvYAD3AQABNQAECgoKNwAKAMYkAA==.',
Pl='Plokane:BAABNQAECn8uAAMBAAkKASAtFACnAQABAAgKLx4tFACnAQADAAIK9CPlBgC1AAAAAA==.',
Po='Poacher:BAAANQADCgMIBAAAAA==.Poppapally:BAAANQADCgYICQAAAA==.Porque:BAAANQAECgQIBgABNQAECggIDgAHAAAAAA==.Powar:BAAANQAECggIEwAAAA==.',
Pr='Provence:BAAANQAECgMIAgAAAA==.',
Py='Pyreynna:BAABNQAECn8VAAIBAAYKBhdGugBZAQABAAYKBhdGugBZAQAAAA==.',
['Pè']='Pèppèr:BAABNQAECn8ZAAIUAAcKTRXlowDZAQAUAAcKTRXlowDZAQABNQAECgoKMgAPAEcZAA==.',
Qs='Qsteve:BAAANQADCgYIBgAAAA==.',
Ra='Ragarn:BAAANQAECgEIAQABNQAECgoKLwAKAEUfAA==.Rainier:BAAANQADCgIIAgAAAA==.Ralnorin:BAABNQAECn8dAAIKAAcKTBZaOwD7AAAKAAcKTBZaOwD7AAAAAA==.Rapsodia:BAAANQAECgcIDQABNQAFFAcICwAOAP8SAA==.Raschild:BAAANQAECgcIEgAAAA==.',
Re='Realfrojd:BAABNQAECn80AAIYAAoKxAdAYgBpAQAYAAoKxAdAYgBpAQAAAA==.Regginunchuk:BAABNQAECn8yAAIEAAoK+h24CgAoAwAEAAoK+h24CgAoAwAAAA==.Releronastus:BAAANQAECgUICAAAAA==.Reliquary:BAAANQAECgEIAQAAAA==.Rextallion:BAABNQAECn87AAMUAAoK3R5qQADTAgAUAAoKOBxqQADTAgATAAgKpx5iEgB8AgAAAA==.Reyson:BAABNQAECn8xAAIOAAoKuwwJRAA0AQAOAAoKuwwJRAA0AQAAAA==.',
Rh='Rhunon:BAABNQAECn8/AAIYAAkKnx5EGgDcAgAYAAkKnx5EGgDcAgAAAA==.Rhythma:BAAANQADCgYIBAAAAA==.',
Ri='Rimlaol:BAAANQAECgUIBQAAAA==.Rinchi:BAAANQADCgYIDAAAAA==.Rinthia:BAABNQAECn81AAMNAAoKSyB5BgBwAwANAAoKSyB5BgBwAwAGAAEKhwVzlwA4AAAAAA==.Ripyeet:BAABNQAECn8cAAIUAAgKchg8hAAfAgAUAAgKchg8hAAfAgAAAA==.',
Ro='Rol:BAABNQAECn8WAAIKAAoKUBY3GgCKAQAKAAoKUBY3GgCKAQAAAA==.Rolden:BAAANQAECgEIAQAAAA==.',
Ru='Rukaji:BAABNQAECn8fAAIRAAcK1BfvlADnAQARAAcK1BfvlADnAQAAAA==.',
['Rå']='Rågeadin:BAAANQADCgYIFQABNQADCgQIBQAHAAAAAA==.Rågè:BAAANQADCgQIBQAAAA==.',
Sa='Saetheline:BAABNQAECn8wAAIRAAoKFxaUWwB5AgARAAoKFxaUWwB5AgAAAA==.Samayel:BAAANQAECgYICgAAAA==.Sarkang:BAABNQAECn8yAAMYAAgKxRaHFgAzAQAbAAgKng5FXQCaAQAYAAYKER6HFgAzAQAAAA==.Satdurrday:BAAANQADCgQIBAABNQAECgoKMgAPAEcZAA==.',
Sc='Schecter:BAAANQAECgQIBAAAAA==.Schmeebie:BAAANQAECgIIAgABNQAECgUICQAHAAAAAA==.Schutze:BAACNQAFFH8IAAIjAAUK7xHlAABiAQAjAAUK7xHlAABiAQA1AAQKfygAAyMACgq5I2UCABkDACMACgq5I2UCABkDACAABgqeCyMNACUBAAAA.',
Sd='Sdadfeg:BAABNQAECn8tAAIMAAoK/yTtAADAAwAMAAoK/yTtAADAAwAAAA==.',
Se='Sebastien:BAAANQADCggICAABNQAECgkJLQAgAPEZAA==.Senco:BAAANQAECgYICgAAAA==.Sephroth:BAAANQAECgEIAQABNQAECgIIAgAHAAAAAA==.',
Sh='Shabobado:BAABNQAECn8ZAAIOAAgKxxf7nABHAgAOAAgKxxf7nABHAgAAAA==.Shadowleaf:BAAANQADCgQIBAAAAA==.Shammin:BAAANQAECgUICgAAAA==.Shampyre:BAAANQADCgUIBQAAAA==.Shayder:BAAANQAFFAEIAQAAAA==.Shiipo:BAAANQADCggIEgAAAA==.Shura:BAAANQAFFAEIAgAAAA==.Shuten:BAAANQAECggICwAAAA==.Shxdow:BAAANQADCgEJAQAAAA==.Shøck:BAAANQAECgMIAwAAAA==.',
Si='Sibble:BAAANQADCgYIDAAAAA==.Siegfried:BAAANQAECgcICgAAAA==.Siff:BAAANQAECgEIAQAAAA==.Silbanuz:BAAANQAECgQIBQAAAA==.Silverie:BAAANQAECgQICAABNQAECgoKNwAKAMYkAA==.Simplejakk:BAAANQAECgcIBwAAAA==.Sinill:BAAANQADCggIDwAAAA==.Sinterklaas:BAABNQAECn8kAAIKAAoKqxQXHQB3AQAKAAoKqxQXHQB3AQAAAA==.',
Sk='Skjald:BAAANQAECgQIBAABNQAFFAUIEwAGALweAA==.Skylee:BAABNQAECn8gAAMOAAoKABilMgBbAQAOAAkKzBilMgBbAQAQAAEKahLYQQBAAAAAAA==.',
Sl='Slark:BAABNQAECn8WAAMXAAgKAgZoHAAgAQAXAAcKAgZoHAAgAQAmAAUKYQuMMgDVAAAAAA==.Slawth:BAABNQAECn8ZAAMbAAkKFQ9rWACvAQAbAAkKFQ9rWACvAQAYAAEKEQSszQAwAAAAAA==.Slayermonde:BAAANQAECgUIBgAAAA==.Sleepel:BAAANQADCgYICgAAAA==.',
Sm='Smexytimes:BAABNQAECn8iAAIRAAkKqRqOCAAzAgARAAkKqRqOCAAzAgAAAA==.Smeyplus:BAACNQAFFH8VAAMUAAcKAiAuAwA1AQAUAAYKAiAuAwA1AQATAAEKAAAuDQBxAAA1AAQKfy4AAxQACgqlJCgFANADABQACgqlJCgFANADABMAAQoAADZbAG8AAAAA.',
Sn='Snaccident:BAAANQAECggIDwAAAA==.Snickeris:BAAANQAECgUIDwABNQAECgUIEgAHAAAAAA==.Snofawl:BAAANQAECgYIDQAAAA==.Snoranir:BAAANQAECgcIEQAAAA==.Snurchbasher:BAABNQAECn8YAAIiAAYKLxSnDAD6AAAiAAYKLxSnDAD6AAAAAA==.',
Sp='Spanfrontals:BAAANQAECggIDAABNQAFFAUIEwAGALweAA==.Sparrowhawk:BAAANQABCgQIBAAAAA==.Speedpuss:BAAANQADCgUIBQAAAA==.Spiko:BAABNQAECn8vAAIKAAoKRR/MJADSAgAKAAoKRR/MJADSAgAAAA==.Spratticus:BAAANQADCgYICgAAAA==.',
Sq='Squidd:BAAANQADCgMIBAAAAA==.',
St='Stars:BAABNQAECn8bAAMJAAkKzhjXKwBEAgAJAAkKzhjXKwBEAgASAAYK+QnRQgA5AQABNQAFFAMIBwAFAKIfAA==.Sterra:BAAANQADCgcIDAAAAA==.Stinkiepete:BAAANQAECgIIAgAAAA==.',
Su='Sureno:BAABNQAECn8YAAIUAAoKDB1vcgBKAgAUAAoKDB1vcgBKAgAAAA==.',
Sw='Swaglordxtqt:BAAANQAECgMIAgAAAA==.',
Sx='Sxyhealz:BAAANQAECgUIBgAAAA==.Sxyheålz:BAACNQAFFH8HAAIGAAUK7AYxGwARAQAGAAUK7AYxGwARAQA1AAQKfzEAAgYACgrHGFg0AJYCAAYACgrHGFg0AJYCAAAA.',
Ta='Taffybonkins:BAAANQAECgcICgAAAA==.Taliä:BAAANQADCgcIDAAAAA==.Tanndari:BAAANQADCgcIHQAAAA==.Tartare:BAAANQAECggIEAAAAA==.Tashaman:BAACNQAFFH8MAAMKAAUKOw0XDwBeAQAKAAUKOw0XDwBeAQALAAEKAABdNwAzAAA1AAQKfzwAAwoACgq+E6NWAA4CAAoACgq+E6NWAA4CAAsABQq7BavZAOEAAAAA.',
Te='Teajuan:BAAANQADCgcIBwAAAA==.Tenderheart:BAAANQABCgIIAgAAAA==.Tenzin:BAAANQADCggIDwAAAA==.Teriheals:BAAANQAECgUICQAAAA==.',
Th='Thebishop:BAAANQADCgIIAgAAAA==.Thejorlane:BAAANQADCgcIGgAAAA==.Thiccholy:BAACNQAFFH8NAAMZAAUKwgq1DgB4AQAZAAUKwgq1DgB4AQATAAIKfwKODwBNAAA1AAQKfykABBkACgrTFg1UAB4CABkACQrVFQ1UAB4CABMACQrdDCQrAIQBABQABgpBCRcZAfUAAAAA.Thiccshields:BAAANQADCgQIBAABNQAFFAUIDQAZAMIKAA==.Thicctotemz:BAAANQAECgUICwABNQAFFAUIDQAZAMIKAA==.Thickkicks:BAAANQAECgMIAwABNQAFFAUIDQAZAMIKAA==.Thogo:BAABNQAECn8vAAIlAAoKkh/QAgBBAwAlAAoKkh/QAgBBAwAAAA==.',
Ti='Tikaa:BAAANQAECgYIDAAAAA==.Tinycups:BAAANQAECgEIAQAAAA==.Tipnontotems:BAAANQADCgUIBQAAAA==.',
To='Tokiya:BAABNQAECn8rAAITAAoKCCMFAwCWAwATAAoKCCMFAwCWAwABNQAFFAYIBwAYADIUAA==.Tomerto:BAABNQAECn8zAAMZAAoKYCCBBwBOAgAZAAoKYCCBBwBOAgAUAAUK/Qw4GgHzAAAAAA==.Toobeastly:BAABNQAECn8mAAQMAAoK/B0FAQCYAgALAAgKuyDDJgDoAgAMAAkKjBsFAQCYAgAKAAEKRhUWHgExAAAAAA==.Toonerdin:BAAANQAECgUIDgAAAA==.Toymonkey:BAAANQADCggIDQAAAA==.',
Tr='Treej:BAAANQAECgIIAgAAAA==.Tril:BAAANQAECgIJAwAAAA==.Trolazo:BAAANQADCggICgAAAA==.Trox:BAAANQADCgcIEwAAAA==.Trydrodruid:BAABNQAECn8VAAQIAAcK5Q3VLACrAAAWAAUKFw5UdAD5AAAIAAUKCAnVLACrAAAeAAEKnBuhNQBAAAAAAA==.Tryingmybest:BAACNQAFFH8TAAIGAAUKvB6bCQDvAQAGAAUKvB6bCQDvAQA1AAQKfykABAYACQpIJdEFAJkDAAYACQpIJdEFAJkDACEABwpeGgMHAA8CAA0AAQoAAH2GACMAAAAA.',
Ts='Tsugi:BAAANQAECgIIAgAAAA==.',
Tw='Twozero:BAAANQADCggICQABNQAECgIIAgAHAAAAAA==.',
Ty='Tydrodh:BAAANQAECggICQABNQAECggIFQAIAOUNAQ==.Tydropally:BAAANQAECggIDQABNQAECggIFQAIAOUNAA==.Tydroshaman:BAAANQADCgUIBQAAAA==.Tyestaumin:BAAANQADCgcIBwABNQAECgUICAAHAAAAAA==.Tyralen:BAABNQAECn81AAIFAAoKVhjMFwC7AQAFAAoKVhjMFwC7AQAAAA==.Tyrandras:BAABNQAECn8wAAIeAAoK3hCDFgADAgAeAAoK3hCDFgADAgABNQAECgoKNQAFAFYYAA==.Tyronnius:BAABNQAECn8UAAMDAAgKvRKtAQBzAQADAAgKvRKtAQBzAQABAAQKWwTEEgGlAAAAAA==.Tyrïon:BAABNQAECn8zAAIRAAoKHiIQGwBLAwARAAoKHiIQGwBLAwAAAA==.',
Un='Unforgiven:BAAANQAECggIBgAAAA==.Unlyfe:BAAANQAECgQIBQAAAA==.Unnamed:BAAANQAECgEIAQABNQAFFAUIEwAGALweAA==.',
Va='Vaero:BAABNQAECn8sAAISAAoKlB9xCABMAwASAAoKlB9xCABMAwAAAA==.Vampirate:BAAANQADCgcIBwAAAA==.Vandenar:BAAANQAECgQIBQAAAA==.',
Vd='Vdarkadin:BAAANQADCgEIAQAAAA==.',
Ve='Vee:BAAANQADCgEIAQABNQAFFAcIFwAVAKgJAA==.Velyssa:BAABNQAECn8hAAIFAAgKrx9ODwD2AQAFAAgKrx9ODwD2AQAAAA==.',
Vi='Vibez:BAAANQAECggIDQABNQAECgoKLAAiADsdAA==.Vibin:BAABNQAECn8sAAIiAAoKOx0IBQCSAQAiAAoKOx0IBQCSAQAAAA==.Vineeshewah:BAABNQAECn8hAAICAAgKNhvzAADlAQACAAgKNhvzAADlAQAAAA==.',
Vo='Voidguy:BAAANQAECgcIDwABNQAECgoKKAAZAFkRAA==.',
Vu='Vulsted:BAAANQADCggIFwAAAA==.',
Vy='Vykx:BAAANQADCgMIBQAAAA==.',
['Vî']='Vîctorîe:BAAANQADCggICAAAAA==.',
Wa='Wantedd:BAABNQAECn8aAAIGAAoKQxaUDgAIAgAGAAoKQxaUDgAIAgABNQAECgoKLwAKAEUfAA==.Warriorguy:BAAANQABCgIIAgABNQAECgoKKAAZAFkRAA==.',
Wh='Whalend:BAAANQADCgYIBgAAAA==.Whatapal:BAAANQAECgUIDQAAAA==.',
Wi='Wilbo:BAABNQAECn8YAAILAAoKZhnYRABiAgALAAoKZhnYRABiAgABNQAFFAYIFgAbAA8VAA==.Wily:BAAANQAECgMIBAAAAA==.Wisperwing:BAABNQAECn8aAAIFAAcKwgR/zgBkAQAFAAcKwgR/zgBkAQAAAA==.',
Wo='Wolfdrudu:BAAANQAECgYIDgAAAA==.Wordbet:BAAANQADCgcIBwAAAA==.Worldfire:BAAANQAECgYICQAAAA==.Wormadina:BAAANQAECgUICgAAAA==.Wormszer:BAAANQAECgcIEAAAAA==.Wotan:BAAANQADCgIJAgAAAA==.Woth:BAAANQADCggIDgAAAA==.',
Wr='Wrâîth:BAAANQADCgYICwABNQAECgYIFQALACMIAA==.',
Wy='Wynds:BAACNQAFFH8fAAIiAAcK7ia1AAAeAwAiAAcK7ia1AAAeAwA1AAQKfzgAAiIACgrMJhAAAA0EACIACgrMJhAAAA0EAAAA.Wyngs:BAABNQAECn8bAAIZAAgKeSU/AwDUAgAZAAgKeSU/AwDUAgABNQAFFAcIHwAiAO4mAA==.',
Xe='Xeres:BAAANQABCgIJBAAAAA==.',
Xi='Xi:BAABNQAECn8wAAIiAAoKVg2MCgAaAQAiAAoKVg2MCgAaAQAAAA==.Xiaozhi:BAEBNQAECn8hAAMmAAgKEh+eAQCbAgAmAAgKEh+eAQCbAgAEAAMK8g6mVACbAAAAAA==.',
Xt='Xtend:BAAANQAECgEIAQAAAA==.',
Xz='Xzariana:BAABNQAECn8VAAIFAAcK4QiDugCOAQAFAAcK4QiDugCOAQAAAA==.',
Yo='Yodda:BAAANQADCgUIBQAAAA==.Yoirr:BAABNQAECn8VAAIGAAkKbyOJAgA5AwAGAAkKbyOJAgA5AwAAAA==.',
['Yë']='Yëëter:BAAANQADCgUICQAAAA==.',
Za='Zach:BAAANQAECgEIAQABNQAECggIGQAFAKUfAA==.Zanori:BAABNQAECn8xAAQaAAoKkhJ7LwAoAgAaAAkKGxR7LwAoAgAbAAYKhgbejADxAAAYAAUKWAd7LgC7AAAAAA==.Zansijo:BAAANQADCgUIBQABNQAECgoKMQAaAJISAA==.',
Ze='Zellyne:BAAANQAECggIEgABNQAFFAYIEQAiALgVAA==.',
Zo='Zolajin:BAAANQADCgYICQAAAA==.Zorriya:BAACNQAFFH8NAAIFAAYKyxQiAgBhAQAFAAYKyxQiAgBhAQA1AAQKfzkAAgUACgpkIzQUAE0DAAUACgpkIzQUAE0DAAAA.Zoyn:BAAANQAECgUIBAAAAA==.',
Zy='Zygo:BAAANQAECgIIAgAAAA==.',
['Ár']='Áries:BAAANQAECgMIBwAAAA==.',
['Åm']='Åmnèsia:BAAANQADCgUIBQAAAA==.',
['Êv']='Êvelyn:BAAANQAECgMIAwAAAA==.',
['Ít']='Ítsaßünny:BAAANQADCgQIBQAAAA==.',
['Ðe']='Ðemonic:BAAANQAECgEIAQABNQAECgEIAQAHAAAAAA==.Ðemonicßlaze:BAAANQADCggIEAABNQAECgEIAQAHAAAAAA==.',
['Ýu']='Ýuno:BAAANQADCgYIDgAAAA==.',
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
