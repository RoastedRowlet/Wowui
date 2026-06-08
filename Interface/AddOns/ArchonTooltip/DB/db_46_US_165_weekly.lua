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

local lookup = {'Mage-Frost','Unknown-Unknown','Shaman-Elemental','Druid-Guardian','Priest-Discipline','DemonHunter-Devourer','Evoker-Preservation','Evoker-Augmentation','Priest-Shadow','Paladin-Retribution','Shaman-Restoration','Hunter-Marksmanship','Warrior-Arms','Warrior-Fury','DemonHunter-Vengeance','Druid-Restoration','DemonHunter-Havoc','Hunter-BeastMastery','Druid-Balance','Hunter-Survival','DeathKnight-Unholy','DeathKnight-Frost','Monk-Mistweaver','Monk-Windwalker','Warlock-Affliction','DeathKnight-Blood','Monk-Brewmaster','Warlock-Demonology','Warlock-Destruction','Evoker-Devastation','Shaman-Enhancement','Druid-Feral','Rogue-Subtlety','Rogue-Assassination','Paladin-Protection','Paladin-Holy','Priest-Holy','Mage-Arcane','Mage-Fire','Warrior-Protection',}
local provider = {region='US',realm='Nazjatar',name='US',type='weekly',zone=46,date='2026-06-06',data={Aa='Aaela:BAAALgADCgUJBQAAAA==.',
Ab='Abrasaxs:BAABLgAECn8qAAIBAAgJQhjzVQDUAQABAAgJQhjzVQDUAQAAAA==.Absylus:BAAALgAECgQJBAABLgAFFAMJBAACAAAAAA==.',
Ac='Ackerman:BAAALgAECgYJCgABLgAECggJEgACAAAAAA==.Acraea:BAABLgAECn8eAAIBAAgJmwzbewB6AQABAAgJmwzbewB6AQAAAA==.Acslater:BAAALgAECgMJDAAAAA==.Actionman:BAAALgAECgkJBwAAAA==.',
Ag='Agoobagoo:BAACLgAFFH8TAAIDAAQJnSKwEwBoAQADAAQJnSKwEwBoAQAuAAQKfx8AAgMACQnZIpAEAFIDAAMACQnZIpAEAFIDAAEuAAUUBQkOAAQAwBYA.',
Ai='Aionn:BAAALgAECgMJAwAAAA==.Airrow:BAABLgAECn8UAAIFAAkJEhncDgB1AgAFAAkJEhncDgB1AgAAAA==.Aissae:BAACLgAFFH8NAAIGAAQJ7hy0MABKAQAGAAQJ7hy0MABKAQAuAAQKfykAAgYACAlAJHYLACYDAAYACAlAJHYLACYDAAAA.Aiyama:BAAALgADCgQJBAAAAA==.',
Ak='Akiio:BAAALgAECgMJAwAAAA==.Akumaxl:BAAALgAECgYJBwAAAA==.',
Al='Alexia:BAAALgAECgEJAQAAAA==.Alfrank:BAAALgAECgIJAwAAAA==.Aliasx:BAAALgAECgMJBAAAAA==.Allwrong:BAAALgAECgEJAQAAAA==.Alphrank:BAAALgAECgEJAgAAAA==.Alurie:BAAALgAECgUJBgAAAA==.',
Am='Amandrada:BAAALgAECgEJAQAAAA==.Ambros:BAAALgADCgYJBgAAAA==.Aminatou:BAAALgAECgYJBwAAAA==.',
An='Anheeboan:BAAALgAECgYJCwAAAA==.Anihilated:BAAALgADCgYJBwAAAA==.',
Ar='Aradiax:BAAALgADCgYJBgAAAA==.Arcadavia:BAAALgADCgMJAwAAAA==.Ariaprime:BAAALgAECgcJDQAAAA==.Arjentheilus:BAAALgAECgMJAwAAAA==.Arthasl:BAAALgADCgMJAgAAAA==.Arthur:BAAALgAECgQJDgAAAA==.',
As='Asasda:BAAALgADCgMJBAAAAA==.Ashaelra:BAAALgAECgYJCAAAAA==.Astravaritan:BAAALgADCgMJAwAAAA==.',
At='Atherya:BAAALgAECgYJCAAAAA==.Atomixblonde:BAAALgAECgEJAQAAAA==.',
Au='Augonly:BAACLgAFFH8dAAIHAAYJHhcHDQC2AQAHAAYJHhcHDQC2AQAuAAQKfyMAAgcACQnpIC4GAOECAAcACQnpIC4GAOECAAAA.Augy:BAACLgAFFH8NAAIIAAQJMg1QMAD1AAAIAAQJMg1QMAD1AAAuAAQKfxsAAggACAk1F5QeANoBAAgACAk1F5QeANoBAAAA.Autoshot:BAAALgAFFAIJAgAAAA==.',
Av='Averisbelia:BAAALgAECgQJCQAAAA==.',
Ay='Ayowamsley:BAAALgADCgMJAwAAAA==.',
Az='Azalea:BAAALgAECggJEAAAAA==.',
Ba='Babycrock:BAAALgADCgYJBgAAAA==.Back:BAAALgADCgcJDAAAAA==.Bakihanma:BAAALgAECgQJBgAAAA==.Balash:BAAALgADCgUJBQAAAA==.Balerion:BAAALgADCgEJAQABLgADCgMJAwACAAAAAA==.Balthasar:BAABLgAECn8nAAIJAAkJExozDgBsAgAJAAkJExozDgBsAgAAAA==.Banjobits:BAAALgADCgIJAgAAAA==.Barhead:BAAALgAECgYJDAAAAA==.Barlow:BAAALgAECggJEQAAAA==.Barqose:BAAALgADCgMJAwAAAA==.Barryberry:BAABLgAECn8fAAIKAAkJDREJdgB3AQAKAAkJDREJdgB3AQAAAA==.Barryx:BAAALgAECgIJAgAAAA==.',
Bb='Bbldrizzy:BAABLgAFFH8FAAILAAMJjR5BNgDyAAALAAMJjR5BNgDyAAAAAA==.',
Be='Beastlieduke:BAAALgAECgMJAwABLgAFFAUJFQAJAKgNAA==.Beastlièduke:BAACLgAFFH8VAAIJAAUJqA0JGwACAQAJAAUJqA0JGwACAQAuAAQKfy4AAgkACAnwHvQOAJQCAAkACAnwHvQOAJQCAAAA.Beauslay:BAAALgAECgEJAQAAAA==.Belephon:BAAALgAECgYJEAAAAA==.Bellaruhbz:BAABLgAECn8eAAIMAAkJjA9UFgD3AAAMAAkJjA9UFgD3AAAAAA==.Berenstain:BAABLgAECn8nAAIEAAkJShPyFQCSAQAEAAkJShPyFQCSAQAAAA==.Bergmire:BAAALgAECgQJCgAAAA==.Berple:BAAALgADCgUJBQABLgAFFAcJGAABANsiAA==.Bestoresto:BAABLgAECn8XAAILAAkJBQxAQACfAQALAAkJBQxAQACfAQAAAA==.',
Bh='Bhori:BAAALgAECgEJAwAAAA==.',
Bi='Bibahabibi:BAABLgAECn8dAAMNAAYJxhtkIwA9AQANAAYJxhtkIwA9AQAOAAMJzQiVhwChAAAAAA==.Bigddk:BAAALgAECgcJDQAAAA==.Bigpapax:BAAALgAECgEJAQAAAA==.Bigtac:BAABLgAECn8vAAMNAAkJlBygCABcAgANAAkJlBygCABcAgAOAAIJ3gc5mQBcAAAAAA==.Bimmylee:BAAALgADCgEJAQAAAA==.Binggus:BAAALgAECgUJCgABLgAECgkJHQAPAEQjAA==.Bipolaire:BAAALgADCgEJAQAAAA==.',
Bl='Blabbybootze:BAAALgAECgYJBgAAAA==.Bladelight:BAAALgAECgUJBgAAAA==.Blighte:BAAALgADCgQJBAABLgAECggJIQAQAIIkAA==.Blightfangs:BAACLgAFFH8FAAIBAAMJZQrsfQDVAAABAAMJZQrsfQDVAAAuAAQKfz4AAgEACAkDGic6ACoCAAEACAkDGic6ACoCAAAA.Blindnautdef:BAABLgAECn80AAMGAAgJ7RCVZQBPAQAGAAgJ7RCVZQBPAQARAAEJ9gPYdAAhAAAAAA==.Bloodluna:BAAALgADCgUJBQAAAA==.',
Bo='Bobman:BAAALgAECgUJCAAAAA==.Bodakye:BAACLgAFFH8HAAISAAMJ8AmjXQDUAAASAAMJ8AmjXQDUAAAuAAQKfyQAAxIACQlBGwAqACsCABIACQlBGwAqACsCAAwAAgm0ARCBAEMAAAAA.Bonargrowrod:BAAALgAECgQJBwAAAA==.Bonkz:BAAALgAECgMJAwAAAA==.Boomtip:BAAALgADCgMJAwAAAA==.Boon:BAAALgADCgYJCQAAAA==.Bordolor:BAAALgAECgEJAQAAAA==.Bowsa:BAAALgAECgkJAQAAAA==.',
Br='Brethathes:BAAALgAECgkJEgAAAA==.Brudda:BAAALgADCgUJBQAAAA==.',
Bu='Bubbaray:BAAALgAECgMJAwAAAA==.Bubblebun:BAAALgAECgMJBgAAAA==.Bungerhole:BAABLgAECn8VAAMQAAgJhhqzLgDhAQAQAAgJhhqzLgDhAQATAAEJEQk+kwAmAAAAAA==.Butane:BAAALgADCgIJAgAAAA==.Buzzbuzz:BAAALgAECgIJBwAAAA==.',
Ca='Cainn:BAAALgAECgYJBwAAAA==.Cap:BAAALgADCgEJAQABLgAFFAQJFAABAGIeAA==.Capriestsun:BAAALgAFFAIJAgAAAA==.Captyn:BAAALgAECggJEQAAAA==.Carridin:BAAALgADCgMJAwAAAA==.Cass:BAAALgAECgEJAQAAAA==.',
Ce='Cernunon:BAAALgADCgEJAQAAAA==.',
Ch='Chaosdemon:BAABLgAECn81AAIGAAkJPRCnQgC0AQAGAAkJPRCnQgC0AQAAAA==.Chaosraven:BAAALgADCgkJCQAAAA==.Chapelgnome:BAAALgAECgQJBQABLgAFFAYJBwAIAIUCAA==.Charlottea:BAAALgAECgYJDQAAAA==.Chemdra:BAAALgAECgcJEwAAAA==.Chiling:BAAALgAECgEJAQAAAA==.Chipmonkey:BAAALgAECgEJAgABLgAECgkJKAAQAIEPAA==.Chiptime:BAABLgAECn8oAAIQAAkJgQ9rNgC2AQAQAAkJgQ9rNgC2AQABLgAECgkJKAAQAIEPAA==.Chomby:BAAALgAECgQJAwAAAA==.Chriifrio:BAAALgADCgUJBgAAAA==.Chromosomes:BAAALgAECgQJBAAAAA==.Chud:BAAALgAECgQJCQAAAA==.Chudsworth:BAAALgADCgYJCQAAAA==.Chunguhlumpo:BAAALgAECgEJBAAAAA==.Chzburger:BAAALgAECgIJAgAAAA==.',
Ci='Cinnamóróll:BAABLgAECn80AAIUAAkJdQ9+EwAHAgAUAAkJdQ9+EwAHAgAAAA==.',
Cl='Clairity:BAAALgAECgMJAwAAAA==.Cleru:BAABLgAECn8fAAMVAAgJxhOlcwB0AQAVAAgJxhOlcwB0AQAWAAEJpwMVGgAlAAAAAA==.Cletus:BAAALgADCgcJAgAAAA==.',
Co='Coa:BAAALgAECgkJDAAAAA==.Cocoon:BAABLgAFFH8PAAMXAAYJIhoQEwDAAQAXAAYJIhoQEwDAAQAYAAIJ+xZBKQCYAAAAAA==.Coldsoul:BAAALgAECgEJAQAAAA==.Comanderkush:BAAALgADCgMJAwAAAA==.Coran:BAAALgAECgIJAwABLgAECgkJJAAZAG0bAA==.Corita:BAAALgAECgIJAgAAAA==.Cowboi:BAAALgADCgMJAwAAAA==.Cowhealer:BAABLgAECn8hAAMQAAgJgiRkCAAIAwAQAAgJgiRkCAAIAwATAAEJTwUTgQAvAAAAAA==.',
Cr='Creamypies:BAAALgAECgEJAQAAAA==.Criticaltwo:BAAALgADCgIJAgAAAA==.Crockknight:BAAALgADCgYJBgAAAA==.Crossways:BAAALgAECgYJCQAAAA==.Cræftig:BAABLgAECn8fAAIBAAgJbBzPMABPAgABAAgJbBzPMABPAgAAAA==.',
Cu='Cursecthree:BAAALgADCgEJAQAAAA==.Curseword:BAAALgAECgEJAQAAAA==.Cutestxx:BAAALgAECgkJCwAAAA==.',
Cy='Cyxo:BAAALgADCgEJAQABLgAECgEJAQACAAAAAA==.',
Da='Daftxshade:BAAALgAECgYJDwAAAA==.Dandandan:BAAALgADCgMJAwAAAA==.Dapan:BAAALgADCgcJDQAAAA==.Dariaa:BAAALgAECgQJDwAAAA==.Darkcrusader:BAAALgAECgcJEAAAAA==.Darkheal:BAAALgADCgUJBQAAAA==.Darkladie:BAAALgADCgEJAQAAAA==.Darkshadows:BAAALgAECgUJCgAAAA==.Darthsyde:BAABLgAECn8ZAAIaAAgJShHHHABnAQAaAAgJShHHHABnAQAAAA==.Dasdk:BAABLgAFFH8QAAIVAAQJzCKILgCQAQAVAAQJzCKILgCQAQAAAA==.Daspriest:BAAALgADCgYJDQABLgAFFAQJEAAVAMwiAA==.',
De='Deadergriff:BAAALgAECggJDAAAAA==.Deadhippycb:BAAALgAECgQJBAAAAA==.Deadhippyxy:BAAALgAECgEJAgAAAA==.Deadicated:BAABLgAECn8eAAQbAAcJpQefQwDjAAAbAAcJLAafQwDjAAAYAAYJKAinWgCbAAAXAAUJaQVfgQB8AAAAAA==.Deadsies:BAAALgADCgIJAgABLgAFFAIJAgACAAAAAA==.Deeds:BAAALgAECgMJAwAAAA==.Delan:BAAALgAECgQJBQAAAA==.Delveknight:BAAALgADCgYJBgABLgAECgcJFwAVAHUdAA==.Demoncox:BAAALgADCgMJAgAAAA==.Demondoc:BAACLgAFFH8KAAIGAAQJDgdwXADGAAAGAAQJDgdwXADGAAAuAAQKfx0AAgYACAlpFywyAPIBAAYACAlpFywyAPIBAAAA.Desunaito:BAACLgAFFH8bAAMWAAYJniE9AACGAQAWAAYJniE9AACGAQAaAAEJAAAQUwAAAAAuAAQKfy0AAhYACQlUJSsBADADABYACQlUJSsBADADAAAA.Devious:BAAALgADCgEJAQAAAA==.',
Dh='Dhzilong:BAACLgAFFH8PAAIGAAUJARprPQAeAQAGAAUJARprPQAeAQAuAAQKfx0AAwYACAlHIU84ABQCAAYACAkzHk84ABQCABEABQmNJJEeAMoBAAAA.',
Di='Diddlefiddle:BAAALgAFFAIJBAAAAA==.Dihcum:BAAALgAFFAIJAwAAAA==.Dimonologist:BAAALgAECgEJAQAAAA==.Dirtycow:BAAALgAECgQJBAAAAA==.',
Dk='Dkzilong:BAAALgAFFAIJBAABLgAFFAUJDwAGAAEaAA==.',
Do='Docholy:BAAALgAECgYJCAABLgAFFAQJCgAGAA4HAA==.Dockson:BAAALgAECgMJAwAAAA==.Docwyle:BAABLgAECn8XAAMcAAgJnxHsawBfAQAcAAgJnxHsawBfAQAdAAEJtgLUcgAzAAABLgAFFAQJCgAGAA4HAA==.Doobyia:BAAALgADCgEJAQAAAA==.Dorki:BAAALgAECgEJAgAAAA==.Dorlanlemeth:BAABLgAECn8VAAIGAAcJBwwKfgAXAQAGAAcJBwwKfgAXAQAAAA==.Dormist:BAAALgAECgMJBAABLgAECgkJJAAZAG0bAA==.Dotti:BAAALgAFFAEJAQAAAA==.',
Dr='Dracnogard:BAAALgAECgcJDgAAAA==.Dracowulf:BAABLgAECn8eAAISAAgJbRAPUgCgAQASAAgJbRAPUgCgAQAAAA==.Dragonx:BAABLgAECn8yAAMSAAgJJhObXgB+AQASAAgJJhObXgB+AQAUAAMJaQ2gQgCuAAAAAA==.Drakos:BAAALgAECgEJAQAAAA==.Drakowolf:BAABLgAECn89AAIeAAgJWQXoDwAAAQAeAAgJWQXoDwAAAQAAAA==.Drenz:BAAALgADCgEJAQAAAA==.Dreorge:BAABLgAFFH8GAAIIAAMJcxGOOwDHAAAIAAMJcxGOOwDHAAAAAA==.Dreuceratops:BAAALgAECgMJAwAAAA==.Drewceratops:BAABLgAECn8oAAIKAAkJtRR9QQD3AQAKAAkJtRR9QQD3AQAAAA==.Driis:BAAALgADCgcJBwAAAA==.Drimchi:BAABLgAFFH8JAAIIAAQJXRR1KQAPAQAIAAQJXRR1KQAPAQAAAA==.Drizro:BAAALgADCgIJAgAAAA==.Drk:BAAALgAECgEJAQAAAA==.Dromash:BAABLgAECn8kAAMZAAkJbRskAwB/AgAZAAkJbRskAwB/AgAdAAgJLhNiCwB7AQAAAA==.Dromgar:BAAALgAFFAIJBAABLgAFFAMJCAAfAAojAA==.Druidyhealz:BAAALgAECgMJAwABLgAECgcJDwACAAAAAA==.',
['Då']='Dårius:BAAALgAECgYJEQAAAA==.',
Ea='Eaterofpaint:BAAALgAECgYJDgAAAA==.',
Ed='Edgeylord:BAAALgAECgEJAQAAAA==.',
Ef='Effloria:BAABLgAECn8lAAIQAAkJEx0PDAD4AgAQAAkJEx0PDAD4AgAAAA==.Efrideet:BAAALgADCgEJAQAAAA==.',
Ei='Eisha:BAAALgADCgUJBQAAAA==.',
El='Elegia:BAACLgAFFH8UAAIcAAUJyBWOQAA6AQAcAAUJyBWOQAA6AQAuAAQKfy8AAxwACQlWGyIZAL4CABwACQlWGyIZAL4CAB0AAQkAAAdmAEMAAAAA.Elerianor:BAAALgAECgYJEgAAAA==.Ellektra:BAAALgADCgUJBQAAAA==.',
Em='Emadiropilo:BAAALgAECgEJAQAAAA==.Emakaa:BAAALgAECgYJCAAAAA==.Embrohunter:BAAALgAECgQJBQAAAA==.',
En='Enash:BAAALgAECgQJBwAAAA==.Engvald:BAAALgADCgUJBQAAAA==.Enhua:BAAALgADCgUJBQAAAA==.Ennet:BAAALgAECgEJAgAAAA==.',
Er='Eretin:BAAALgADCgEJAQAAAA==.Erismorn:BAABLgAECn8iAAQPAAcJNR5cCwCpAQAPAAYJnBtcCwCpAQAGAAYJiBhLVgB4AQARAAEJ4RAEcAA1AAAAAA==.',
Eu='Eudi:BAAALgAECgEJAgAAAA==.',
Ev='Eventhorizòn:BAAALgAECggJEwAAAA==.Evilhoe:BAAALgADCgUJBQAAAA==.Evocation:BAAALgAECggJEgAAAA==.Evoextoons:BAAALgADCggJIgAAAA==.',
Fa='Fallen:BAABLgAECn8XAAMVAAkJfyRdOgAPAgAVAAkJfyRdOgAPAgAaAAMJ7wtcQQB+AAAAAA==.Fallingvoid:BAABLgAECn9iAAMGAAkJJiUaAgC3AwAGAAkJJiQaAgC3AwARAAIJpiVKMwDfAAAAAA==.Fast:BAAALgAECgEJAgABLgAECgIJAgACAAAAAA==.Fatchungus:BAAALgAFFAMJBAAAAA==.Fatherben:BAABLgAECn8XAAIGAAYJVBUoegAfAQAGAAYJVBUoegAfAQAAAA==.Fatmagus:BAAALgAECgcJBgAAAA==.Favio:BAAALgAECggJCwAAAA==.',
Fe='Fellbian:BAAALgADCgcJDgAAAA==.Fentanyahu:BAAALgAECgYJBgAAAA==.Ferozz:BAACLgAFFH8LAAIMAAMJSw48GgDIAAAMAAMJSw48GgDIAAAuAAQKfzEAAgwACAm7HroGABcCAAwACAm7HroGABcCAAAA.',
Fi='Fiercetaco:BAAALgADCgEJAQAAAA==.Finaliter:BAACLgAFFH8OAAIKAAQJZBphLwBBAQAKAAQJZBphLwBBAQAuAAQKfyoAAgoACQk7IIUiAHICAAoACQk7IIUiAHICAAAA.Finatar:BAAALgADCgcJCwAAAA==.Fiora:BAABLgAECn8SAAIGAAcJKx87KQBdAgAGAAcJKx87KQBdAgAAAA==.Fitz:BAAALgADCgEJAQAAAA==.Fiveyears:BAAALgADCgEJAQAAAA==.',
Fk='Fknutmcgee:BAAALgAECgUJBQAAAA==.',
Fl='Flamingdrago:BAAALgAECgIJAgAAAA==.Flinti:BAAALgAECgUJCQAAAA==.Floggy:BAABLgAECn8eAAIBAAgJNgh0kgBNAQABAAgJNgh0kgBNAQAAAA==.',
Fo='Forsight:BAABLgAECn8YAAIVAAgJUhWaeABqAQAVAAgJUhWaeABqAQAAAA==.',
Fr='Fracker:BAAALgAECgcJCAAAAA==.Frankzzorz:BAACLgAFFH8IAAIXAAMJZgoLPQCPAAAXAAMJZgoLPQCPAAAuAAQKfzQAAxcACQk1HLQMAIcCABcACQk1HLQMAIcCABgAAglFIGNTALAAAAAA.Fremder:BAACLgAFFH8VAAIHAAQJyRV0FQAnAQAHAAQJyRV0FQAnAQAuAAQKfzwAAgcACQmqHG0EAN0CAAcACQmqHG0EAN0CAAAA.Fresher:BAABLgAECn8VAAIVAAUJyxzLrAAPAQAVAAUJyxzLrAAPAQAAAA==.Freyjen:BAAALgADCgkJGAABLgAECgcJCgACAAAAAA==.Froboz:BAAALgADCgYJCQAAAA==.Frogevil:BAAALgAECgcJEQAAAA==.Frogtoad:BAAALgAECgUJBQAAAA==.Frogtree:BAAALgADCgUJBQAAAA==.Frostmoth:BAAALgADCgQJBAABLgAECggJGAAVAFIVAA==.Frostygirl:BAABLgAECn8vAAIBAAgJghR0VQDWAQABAAgJghR0VQDWAQAAAA==.Frumentarii:BAAALgAECgQJBAAAAA==.',
Fu='Funeral:BAACLgAFFH8rAAQdAAgJcBmvAwBtAQAdAAUJ/R2vAwBtAQAZAAMJOhpzBQAhAQAcAAMJQxV4MACyAAAuAAQKfzUABB0ACQnmIz4EAKECAB0ABwnSID4EAKECABkABwmUIi8EAFECABwACAkxGetEAP0BAAAA.',
['Fà']='Fàstïk:BAAALgAECgEJAQAAAA==.',
Ga='Galladin:BAAALgAECgMJBQABLgAECgYJDQACAAAAAA==.Gallory:BAAALgAECgcJDQAAAA==.Gareeshala:BAAALgAECgIJAgAAAA==.',
Gd='Gdk:BAAALgAECgIJAwAAAA==.Gdkdrake:BAAALgAECgEJAQAAAA==.Gdkmage:BAAALgAECgkJCQAAAA==.',
Ge='Geomancer:BAAALgADCgQJBAAAAA==.',
Gh='Ghadius:BAAALgAECgQJBAAAAA==.',
Gi='Gimmedatmouf:BAABLgAECn8XAAQQAAgJoyHjCAABAwAQAAgJoyHjCAABAwAgAAMJph6rKgCsAAATAAQJexZZXACUAAAAAA==.Gimmedatneck:BAABLgAECn8XAAMhAAgJVSNhGABEAgAhAAgJVSNhGABEAgAiAAEJNhLgHABDAAAAAA==.Gingy:BAAALgAECgUJBgAAAA==.',
Gl='Glead:BAABLgAECn8YAAIOAAkJ6ReNLQD9AQAOAAkJ6ReNLQD9AQAAAA==.Glizzymguire:BAAALgAECggJCAABLgAFFAMJDAAcACQGAA==.',
Gn='Gneeduh:BAAALgAECgIJAwAAAA==.',
Go='Gobknight:BAAALgADCggJCAAAAA==.Goldina:BAAALgAECgEJAQAAAA==.Gooklover:BAAALgAECgQJCQAAAA==.Gosupal:BAAALgADCgYJBgAAAA==.',
Gr='Gracious:BAAALgAECgEJAQAAAA==.Graegor:BAAALgADCgYJBwAAAA==.Grastim:BAAALgAECgUJCgAAAA==.Graylight:BAAALgADCgUJBQAAAA==.Greenfanta:BAAALgADCgYJEAAAAA==.Grill:BAAALgADCgEJAQAAAA==.Grinkle:BAACLgAFFH8FAAILAAMJjwWKVgCPAAALAAMJjwWKVgCPAAAuAAQKfysAAgsACQkjEVc5ALwBAAsACQkjEVc5ALwBAAAA.Gripopotamus:BAAALgADCgkJDQAAAA==.Gristle:BAAALgADCgkJJwAAAA==.',
Gu='Guldangg:BAAALgAECgcJEAAAAA==.Gunner:BAACLgAFFH8HAAISAAQJUhTsKwBMAQASAAQJUhTsKwBMAQAuAAQKfxsAAhIACQm5IqsFADADABIACQm5IqsFADADAAAA.',
Ha='Hakaishaz:BAAALgADCgUJBgAAAA==.Halfwatt:BAAALgAECgYJDQAAAA==.Hamaddor:BAAALgAECgYJBgAAAA==.Handen:BAAALgADCggJCAAAAA==.Haraldsson:BAABLgAECn8cAAIKAAgJyRRjaQCRAQAKAAgJyRRjaQCRAQAAAA==.Harmony:BAAALgADCgcJCgAAAA==.Harrin:BAAALgADCgYJDAAAAA==.Harrydabs:BAABLgAECn8dAAMPAAkJRCNNAACDAwAPAAkJRCNNAACDAwARAAQJJRB3PwD+AAAAAA==.Haru:BAABLgAECn8dAAIUAAgJfRMdGgDJAQAUAAgJfRMdGgDJAQAAAA==.Harvaal:BAAALgAECgUJBQAAAA==.Hasaro:BAACLgAFFH8LAAIEAAMJuhUgFgC+AAAEAAMJuhUgFgC+AAAuAAQKfysAAgQACQmNGxIHAHkCAAQACQmNGxIHAHkCAAAA.Hashimi:BAAALgAECgcJBwAAAA==.Havokvacano:BAABLgAECn8fAAIKAAkJjxMRRADvAQAKAAkJjxMRRADvAQAAAA==.',
He='Healmachine:BAAALgAECgYJEAAAAA==.Hellbrringer:BAAALgAFFAMJAwAAAA==.Helzerx:BAABLgAECn8hAAIhAAkJfBwICACbAgAhAAkJfBwICACbAgABLgAFFAIJAgACAAAAAA==.Herpstrike:BAAALgAECgIJAwAAAA==.',
Ho='Hoely:BAAALgAECgEJAQAAAA==.Hogmanjr:BAAALgADCgQJBgAAAA==.Holycrappala:BAAALgADCgEJAQAAAA==.Hotsordots:BAAALgAECggJCwAAAA==.Hounskul:BAABLgAECn8gAAIcAAkJogeJdgBHAQAcAAkJogeJdgBHAQAAAA==.',
Hu='Hugealien:BAAALgADCgIJAgAAAA==.Hungchungus:BAAALgAECgEJAgAAAA==.Hungwaylo:BAAALgADCgIJAgAAAA==.',
Hw='Hwere:BAAALgAECgUJBgAAAA==.',
Hy='Hypnoticpal:BAAALgAECgkJBwAAAA==.Hystëria:BAACLgAFFH8TAAMWAAQJ9yCbBQB4AQAWAAQJ9yCbBQB4AQAVAAMJaRWHmwDOAAAuAAQKf1IAAxYACQmQIz0BACoDABYACQmhIj0BACoDABUACAkJIWglAGYCAAAA.Hyunlix:BAAALgADCgUJBQAAAA==.',
Ia='Iammoo:BAAALgAECgcJEgAAAA==.',
Id='Idasie:BAAALgADCgcJBwAAAA==.',
Ig='Igotkappa:BAAALgADCgMJAwAAAA==.Igotyourback:BAAALgAECggJCAAAAA==.Igriss:BAAALgAECgMJBgAAAA==.',
Il='Ilydris:BAAALgADCgQJBAAAAA==.',
Im='Imadruid:BAAALgADCgQJBAAAAA==.',
Io='Iolyte:BAAALgAECgYJDQAAAA==.',
Ir='Iridellis:BAACLgAFFH8LAAIFAAQJjAfNJwDyAAAFAAQJjAfNJwDyAAAuAAQKfyEAAgUACQnQEvsVABwCAAUACQnQEvsVABwCAAAA.',
Is='Ispankutank:BAAALgAECgYJCQAAAA==.',
It='Itssofluffy:BAABLgAECn8vAAQgAAkJlBjoBwBDAgAgAAkJDRjoBwBDAgAEAAUJBhfbEwAyAQATAAIJUgkFjgAqAAAAAA==.Itwon:BAAALgAECgQJCAAAAA==.',
Iz='Izzelda:BAAALgAECgEJAgAAAA==.',
Ja='Jacus:BAAALgAECgQJCQAAAA==.Jahumc:BAAALgAECgEJAQAAAA==.Janeoftrades:BAAALgAECgYJDAAAAA==.Jaycers:BAABLgAECn8iAAQjAAkJ9SCgBAClAgAjAAkJ8B+gBAClAgAKAAUJERzgkgBBAQAkAAEJ2AIAnwAqAAAAAA==.Jayclark:BAAALgADCgcJCgAAAA==.',
Je='Jessiriusrex:BAAALgADCgEJAQAAAA==.',
Jo='Joemomma:BAABLgAECn8UAAIBAAYJIw2BxQD8AAABAAYJIw2BxQD8AAAAAA==.Jokestarfist:BAABLgAECn8ZAAIKAAQJgRh3swAOAQAKAAQJgRh3swAOAQAAAA==.',
Jr='Jr:BAAALgADCgMJBAAAAA==.',
Jt='Jtheshadow:BAAALgAECgEJAQAAAA==.',
Ju='Junachan:BAAALgAECgMJBQAAAA==.Jurichan:BAAALgAECgMJCQAAAA==.',
['Jä']='Jägernaut:BAAALgADCgEJAQAAAA==.',
Ka='Kaitokit:BAAALgAFFAIJAgAAAA==.Kajamando:BAABLgAECn8eAAIRAAgJ7wdyKwARAQARAAgJ7wdyKwARAQAAAA==.Kalith:BAABLgAECn8YAAIUAAkJCgN1LgAuAQAUAAkJCgN1LgAuAQAAAA==.Kallydots:BAAALgADCgcJDQAAAA==.Kayllina:BAABLgAECn8lAAIVAAgJnwYomQAuAQAVAAgJnwYomQAuAQAAAA==.Kayotic:BAABLgAECn8jAAIRAAgJFQagMADwAAARAAgJFQagMADwAAAAAA==.Kayww:BAAALgAECgQJBgAAAA==.',
Ke='Keinarra:BAAALgADCgMJBgAAAA==.Kell:BAAALgADCgcJCAAAAA==.Kelmorphic:BAABLgAECn8tAAMPAAkJMyHJAQD1AgAPAAkJMyHJAQD1AgARAAEJ7Qp5aQAsAAAAAA==.Keropikapika:BAAALgADCgUJBQAAAA==.',
Kh='Khaali:BAAALgAECgEJBAAAAA==.Khristina:BAAALgAECgEJAgAAAA==.',
Ki='Kikiana:BAAALgAECgQJCAABLgAECggJLgAlAKQhAA==.Kikstyx:BAAALgADCgYJCAAAAA==.Killerxd:BAABLgAECn8WAAIKAAgJJRhGZACcAQAKAAgJJRhGZACcAQAAAA==.Killesea:BAAALgADCgcJDAAAAA==.Kittfisto:BAABLgAECn8iAAQPAAkJmhUMFAACAQAGAAkJiBStXgCFAQAPAAQJ4BQMFAACAQARAAYJmAz7MgDhAAAAAA==.',
Kn='Knitemare:BAAALgAECgEJAQAAAA==.',
Ko='Korivos:BAAALgADCgMJAwAAAA==.Kosmas:BAABLgAECn8eAAMOAAgJJiFsHwDuAQAOAAgJ3B5sHwDuAQANAAYJlRzhGACJAQAAAA==.',
Kr='Krushgar:BAABLgAECn8UAAMVAAcJsRcIXQDbAQAVAAcJsRcIXQDbAQAWAAEJsxAZOAAsAAAAAA==.',
Ku='Kuchikopii:BAAALgADCgYJBgAAAA==.Kungfuelf:BAAALgADCgEJAQAAAA==.Kurookami:BAAALgAECgEJAQAAAA==.',
La='Lackluster:BAACLgAFFH8IAAIBAAMJYwGjjwCfAAABAAMJYwGjjwCfAAAuAAQKfyYAAgEACAk0Ck25AG4BAAEACAk0Ck25AG4BAAAA.Lamatrick:BAAALgAECgUJBwAAAA==.Lanadelslayy:BAAALgAECgYJDwAAAA==.Lasenza:BAAALgADCgQJBAAAAA==.Lavacoomer:BAAALgADCgYJBQAAAA==.',
Ld='Ldg:BAAALgAECgEJAQAAAA==.',
Le='Ledana:BAAALgAECgIJAgAAAA==.Lejosh:BAAALgAECgIJAgAAAA==.Lennon:BAAALgAECgkJBgAAAA==.Leona:BAAALgAECgYJCgAAAA==.Leonesk:BAAALgADCgQJAwAAAA==.Lethee:BAAALgAECgEJAgAAAA==.Letusgiveita:BAAALgADCgEJAQAAAA==.Lexazshara:BAAALgAECgEJAgAAAA==.',
Li='Lightingbolt:BAAALgAECgUJDAAAAA==.Lightlybaked:BAAALgAFFAEJAQAAAA==.Lilithamy:BAAALgADCgYJBgAAAA==.Lilthin:BAABLgAECn8bAAIBAAkJBQc7gQBvAQABAAkJBQc7gQBvAQAAAA==.Liore:BAAALgAECgQJBgAAAA==.Lisathe:BAAALgAECgYJEgAAAA==.Lithdrae:BAAALgADCgYJBgAAAA==.Littledude:BAAALgADCgQJBQAAAA==.Littlemorsel:BAABLgAECn8eAAISAAkJNxPIMQAKAgASAAkJNxPIMQAKAgAAAA==.Livelaughlov:BAAALgAECgEJAQAAAA==.',
Lo='Louthar:BAAALgADCgcJAQAAAA==.',
Ls='Lselec:BAAALgADCgYJBgAAAA==.',
Lt='Ltdapperdan:BAAALgAECgEJAQAAAA==.',
Lu='Lucens:BAABLgAECn8oAAIkAAgJSRNzHwD8AQAkAAgJSRNzHwD8AQAAAA==.Lunagreed:BAAALgADCgUJBQAAAA==.Lurchlock:BAAALgAECgYJBgABLgAECgkJVAABAG4RAA==.Lurchn:BAABLgAECn9UAAIBAAkJbhEuWADOAQABAAkJbhEuWADOAQAAAA==.',
Ly='Lysariax:BAAALgADCgQJBAAAAA==.',
['Lï']='Lïght:BAACLgAFFH8FAAIKAAQJWiAjIABxAQAKAAQJWiAjIABxAQAuAAQKfxUAAgoACAn4JH4NAPACAAoACAn4JH4NAPACAAEuAAUUBAkTABYA9yAA.',
['Lú']='Lúná:BAAALgAECgYJBwAAAA==.',
Ma='Maemae:BAAALgAECgcJBwAAAA==.Maggieaugers:BAACLgAFFH8HAAIIAAYJhQK8MAD0AAAIAAYJhQK8MAD0AAAuAAQKfykAAwgACAn3D2YtAHwBAAgACAn3D2YtAHwBAAcABAmPBXgtAHEAAAAA.Magicmech:BAAALgADCgcJDAAAAA==.Magivacano:BAAALgAECggJEgAAAA==.Mahnon:BAABLgAECn8aAAISAAkJowhebQBaAQASAAkJowhebQBaAQAAAA==.Mandril:BAAALgADCgEJAQAAAA==.Matas:BAABLgAECn8UAAIbAAgJDgSnQADvAAAbAAgJDgSnQADvAAAAAA==.Matias:BAAALgAECgEJAQAAAA==.Mazzikane:BAAALgAECgMJAwAAAA==.',
Mc='Mcdeath:BAAALgADCgIJAgAAAA==.',
Me='Medzly:BAAALgADCgYJBgAAAA==.Metalhedface:BAABLgAECn8iAAMNAAkJqRK7GACKAQANAAgJnhO7GACKAQAOAAYJzhPoQQA1AQAAAA==.',
Mi='Miixx:BAAALgAECgQJBQAAAA==.Mikecoxwall:BAACLgAFFH8HAAIBAAIJSgnmmQCPAAABAAIJSgnmmQCPAAAuAAQKfz4AAwEACQmTFU45AC0CAAEACQmTFU45AC0CACYABgnfCP0KACoBAAAA.Mikuru:BAAALgAECgEJAwAAAA==.Milena:BAAALgAECgEJAgAAAA==.Milov:BAAALgADCgUJBQAAAA==.Minarva:BAAALgAECgcJCgAAAA==.Mirazha:BAAALgADCgkJCQAAAA==.Misary:BAAALgAECgQJBAAAAA==.Mischeif:BAAALgAECgUJCwAAAA==.',
Mo='Mojomon:BAAALgADCgYJBgAAAA==.Moltganus:BAABLgAECn8hAAIcAAYJHANt3QCWAAAcAAYJHANt3QCWAAAAAA==.Monkeli:BAABLgAECn8aAAIOAAcJFxEqPABMAQAOAAcJFxEqPABMAQAAAA==.Monkitard:BAAALgAECgMJAwAAAA==.Monkryn:BAAALgAECgUJCAABLgAFFAcJEwAVAEAbAA==.Monkup:BAABLgAFFH8GAAIbAAQJ3AQzMADcAAAbAAQJ3AQzMADcAAAAAA==.Moocifer:BAAALgAECgEJAQAAAA==.Moocifermoo:BAAALgAECgEJAgAAAA==.Moogrim:BAAALgADCgkJDgAAAA==.Moonsiand:BAACLgAFFH8VAAMSAAYJcQo1MgA+AQASAAYJ9wk1MgA+AQAUAAQJHgM+GwDkAAAuAAQKfysABBIACQk3GtAkAEMCABIACQn+FtAkAEMCABQACAleEysOAOYBAAwAAQmqAV+ZABwAAAAA.Moosafur:BAABLgAECn87AAMEAAkJDCUJAQBSAwAEAAkJDCUJAQBSAwAgAAcJdxaIEwB1AQAAAA==.Mooshoe:BAAALgAECgEJAQAAAA==.Mor:BAAALgADCgUJBgAAAA==.Mordoly:BAAALgAECgYJBgAAAA==.Morphyr:BAAALgAECgYJCAAAAA==.Morrigån:BAAALgAECgIJAgAAAA==.Morvoult:BAAALgAECgEJAQAAAA==.Motgus:BAAALgAECgMJBQAAAA==.',
Ms='Mshottie:BAABLgAECn8WAAIKAAgJsgZJtgAKAQAKAAgJsgZJtgAKAQAAAA==.Msuysu:BAAALgAECgEJAQABLgAECgEJAwACAAAAAA==.',
Mt='Mtngrounds:BAAALgADCgIJAgAAAA==.',
Mu='Murdaa:BAAALgAECgMJBAAAAA==.Murkt:BAAALgAECgEJAQAAAA==.Mutuusami:BAAALgAECgEJAgAAAA==.',
Mx='Mx:BAAALgAECgYJCAAAAA==.',
My='Myraine:BAAALgAECgMJAwAAAA==.Mythlock:BAAALgAECgMJAwAAAA==.Myway:BAAALgADCggJCwAAAA==.',
Na='Naari:BAABLgAECn8aAAMOAAgJNxLzPwA8AQAOAAcJDRHzPwA8AQANAAEJLxmdZwBCAAAAAA==.Naniwa:BAAALgAECgEJAQABLgAFFAMJCgALANgVAA==.Naoya:BAAALgADCgIJAgAAAA==.Narexia:BAABLgAECn9HAAIfAAkJbx4SAwDUAgAfAAkJbx4SAwDUAgAAAA==.Natureboyy:BAAALgAECgEJAQAAAA==.',
Ne='Nekuma:BAAALgAFFAIJAgABLgAFFAYJGwAWAJ4hAA==.Nellaa:BAAALgAECgcJEAAAAA==.',
Ni='Nightfury:BAAALgAECgcJDQAAAA==.Niklous:BAAALgAECgEJAQABLgAECgQJBAACAAAAAA==.Niklus:BAAALgAECgEJAQAAAA==.Nissanaltima:BAAALgADCgYJCQAAAA==.Nithilis:BAABLgAECn8zAAIJAAkJAR53CQCyAgAJAAkJAR53CQCyAgAAAA==.',
No='Noee:BAAALgADCgUJBQAAAA==.Nokkiewae:BAAALgADCgcJEgAAAA==.Nomadic:BAAALgADCgkJCQAAAA==.Nool:BAAALgADCgYJBQAAAA==.Nople:BAABLgAECn8fAAIBAAgJGBbkdQCHAQABAAgJGBbkdQCHAQAAAA==.',
Nu='Nutellaa:BAABLgAFFH8FAAIVAAIJmBf1ugCXAAAVAAIJmBf1ugCXAAAAAA==.',
Ny='Nymueline:BAAALgADCgUJBQAAAA==.',
Ob='Obeastly:BAAALgADCgEJAQAAAA==.Obie:BAAALgAECgUJDAAAAA==.Oborax:BAECLgAFFH8HAAIKAAQJdwmMTgABAQAKAAQJdwmMTgABAQAuAAQKfygAAgoABwmcF5lpAJABAAoABwmcF5lpAJABAAAA.',
Od='Od:BAAALgAECgYJCAAAAA==.',
Ok='Okiro:BAAALgAECgMJAwAAAA==.Okoru:BAAALgADCgIJAgAAAA==.',
Ol='Oluun:BAAALgADCgQJBAAAAA==.',
Or='Orkun:BAAALgAECgEJAQAAAA==.',
Ot='Otmetka:BAAALgADCgcJAQAAAA==.',
Pa='Palapal:BAAALgAECgYJDgAAAA==.Paldi:BAABLgAECn8WAAIKAAgJORnRKwB0AgAKAAgJORnRKwB0AgABLgAFFAMJBAACAAAAAA==.Papaozz:BAABLgAECn8qAAIhAAcJ9g0TJgBVAQAhAAcJ9g0TJgBVAQAAAA==.Parapox:BAAALgAECgEJAgAAAA==.Pariss:BAAALgAECgkJBwAAAA==.Pawcalypse:BAAALgAECgMJAwAAAA==.Paws:BAAALgAECggJEwAAAA==.',
Pe='Perelia:BAABLgAECn8/AAIFAAgJgg6TIQCzAQAFAAgJgg6TIQCzAQAAAA==.Pewpewqt:BAAALgAECgUJBwABLgAECggJOAAQABEXAA==.',
Pi='Piltraja:BAAALgAECgEJAgAAAA==.',
Pl='Plaguehammer:BAABLgAECn8bAAIVAAYJ+Qp6vwD1AAAVAAYJ+Qp6vwD1AAAAAA==.Playstationn:BAAALgADCgUJBQAAAA==.',
Pn='Pnwbambii:BAAALgADCgIJAgAAAA==.',
Po='Polarg:BAAALgAECgEJAgAAAA==.Popcola:BAAALgADCgEJAQABLgAECgUJCQACAAAAAA==.Popopopopopo:BAAALgAFFAQJBAAAAA==.Portholio:BAAALgAECgYJBgAAAA==.',
Pp='Ppc:BAAALgAECgEJAQABLgAFFAYJDwAXACIaAA==.',
Pu='Pubbles:BAABLgAECn8XAAQfAAkJ4SDTBgBaAgAfAAgJrCDTBgBaAgALAAEJ1Qk3ywAxAAADAAEJhgwApgAoAAAAAA==.Punizher:BAAALgAECgMJAwAAAA==.Purerage:BAAALgAECgYJDQAAAA==.',
Pv='Pvc:BAAALgAECgYJCQABLgAFFAYJDwAXACIaAA==.',
Py='Pyrella:BAAALgADCgEJAQABLgAECgcJEAACAAAAAA==.Pyyrha:BAAALgAECgMJAwAAAA==.Pyyrhadrood:BAAALgAECgMJAwAAAA==.Pyyrhanice:BAAALgAECgUJDgAAAA==.Pyyrhaspice:BAAALgADCgUJCQAAAA==.',
Qu='Quetzlcoatl:BAAALgADCgcJBwABLgAECgkJEgACAAAAAA==.',
Ra='Radiantharm:BAAALgAECgUJDwAAAA==.Raevalinaa:BAAALgAECgQJCgABLgAECggJLwABAIIUAA==.Raevelinaa:BAAALgAECgQJBwABLgAECggJLwABAIIUAA==.Randzmannz:BAAALgAECgMJAwAAAA==.Raph:BAAALgAECgIJAgAAAA==.Rarelootboss:BAAALgADCgcJDAAAAA==.',
Re='Reason:BAABLgAECn8VAAMQAAgJQxacUgBcAQAQAAcJzhacUgBcAQATAAEJewjgiwArAAAAAA==.Redbaer:BAAALgADCgUJBQAAAA==.Renair:BAAALgADCgMJAwAAAA==.Renoitukax:BAABLgAECn82AAMJAAkJwxtzCwCSAgAJAAkJwxtzCwCSAgAFAAYJJhumGgDrAQAAAA==.Restorn:BAAALgADCgcJCgAAAA==.Retrobution:BAAALgAECgEJAQAAAA==.Retussy:BAAALgADCgEJAQAAAA==.Reynard:BAABLgAECn8WAAIGAAcJLxHjaABHAQAGAAcJLxHjaABHAQAAAA==.Rezz:BAACLgAFFH8SAAIBAAYJjRHDMQCOAQABAAYJjRHDMQCOAQAuAAQKfyAAAgEACQmQHIgpAM0CAAEACQmQHIgpAM0CAAAA.',
Ri='Ridic:BAAALgADCgMJAwAAAA==.Rigour:BAAALgADCgMJAwAAAA==.Rivers:BAAALgAECgYJDQAAAA==.',
Ro='Rocketpop:BAAALgADCgIJAgAAAA==.Rosiegirl:BAAALgAECgMJAwAAAA==.Roxas:BAAALgAECgcJDQAAAA==.',
Ry='Ryzen:BAAALgAECgIJAgAAAA==.',
Sa='Salaelana:BAAALgADCgcJCQAAAA==.Saltzpyre:BAAALgADCgYJBAAAAA==.Saninar:BAAALgAECgEJAgAAAA==.Sausagepizza:BAAALgADCgYJAwAAAA==.',
Sc='Schezmu:BAAALgAECgIJAgAAAA==.Scruffknight:BAAALgAECgcJDQAAAA==.Scrufies:BAACLgAFFH8JAAIhAAMJqhBJJADuAAAhAAMJqhBJJADuAAAuAAQKfx0AAiEACQmbFmoSAAcCACEACQmbFmoSAAcCAAAA.',
Se='Seisappho:BAAALgADCgMJAwAAAA==.Senorfiesta:BAAALgAECgQJBAAAAA==.Serenade:BAAALgAECgcJDgAAAA==.Serenityboop:BAAALgADCgYJCQAAAA==.Sergnocchi:BAAALgAECgcJEAAAAA==.Serys:BAAALgAECggJEAAAAA==.Sethour:BAAALgADCgQJBAAAAA==.',
Sh='Shaee:BAAALgADCgkJDwAAAA==.Shalthender:BAAALgADCgUJBQAAAA==.Shamans:BAABLgAECn8ZAAIDAAcJ1R6xHgDgAQADAAcJ1R6xHgDgAQAAAA==.Shamncheese:BAABLgAECn8VAAILAAcJ+Q0PXQA1AQALAAcJ+Q0PXQA1AQABLgAECgUJDQACAAAAAA==.Shamorcc:BAAALgADCgQJBAAAAA==.Shasta:BAACLgAFFH8dAAIEAAUJtyX+AwC2AQAEAAUJtyX+AwC2AQAuAAQKfygAAgQACAlZJW8BAEEDAAQACAlZJW8BAEEDAAAA.Shaulthariel:BAAALgAECgEJAQAAAA==.Shioz:BAAALgADCgQJBgAAAA==.Shisuiuchiha:BAABLgAECn8bAAIBAAcJZgWNxwD5AAABAAcJZgWNxwD5AAAAAA==.Shoiz:BAAALgAECgQJBQAAAA==.Shon:BAAALgAECgEJAQAAAA==.Shootumup:BAAALgAECgkJEAAAAA==.Shootybithc:BAAALgADCgEJAQAAAA==.Shuhari:BAAALgAECgkJEwAAAQ==.Shyx:BAABLgAECn8cAAIFAAgJ1Ri5EABaAgAFAAgJ1Ri5EABaAgAAAA==.',
Si='Siilas:BAACLgAFFH8WAAQcAAQJtgjYXgD5AAAcAAQJHQfYXgD5AAAZAAEJhw9wJQBGAAAdAAIJ7QAAKQA3AAAuAAQKfyoAAxwACQljF2MoADQCABwACQljF2MoADQCAB0ABAlQBwFBALEAAAAA.Sinamon:BAABLgAECn8xAAIKAAgJGSF7IQB3AgAKAAgJGSF7IQB3AgAAAA==.Sinani:BAABLgAECn8uAAIBAAkJIwVSkQBPAQABAAkJIwVSkQBPAQAAAA==.Sinista:BAAALgAECgUJBQAAAA==.Sinnamon:BAAALgAECgYJEgABLgAECggJMQAKABkhAA==.',
Sj='Sjdh:BAABLgAECn8XAAIGAAcJnBI0ZwBLAQAGAAcJnBI0ZwBLAQAAAA==.Sjrogue:BAABLgAECn8xAAIhAAkJMBQBEgALAgAhAAkJMBQBEgALAgAAAA==.',
Sk='Skjolvarn:BAEALgAECgMJBwAAAA==.Skram:BAAALgAECgMJBAAAAA==.',
Sl='Slammydooker:BAABLgAECn8fAAMhAAkJ0hUMEgALAgAhAAkJ0hUMEgALAgAiAAEJ1QcMIQAtAAAAAA==.Slammyhole:BAAALgAECgEJAQAAAA==.Sleeptoken:BAAALgAECgMJCAAAAA==.Slyphz:BAAALgAECgYJBgAAAA==.',
Sm='Smallkat:BAAALgAECgEJAQAAAA==.Smightymouse:BAAALgADCgEJAQAAAA==.',
Sn='Snoipuh:BAAALgAECgUJBwAAAA==.',
So='Solas:BAAALgAECgQJBwAAAA==.Soletaken:BAAALgADCggJDwAAAA==.Solio:BAAALgADCgYJFQAAAA==.Solisha:BAAALgADCgkJDgAAAA==.Somberdh:BAAALgADCgcJBwAAAA==.Sonofsand:BAAALgAECgIJAgAAAA==.Soulja:BAAALgADCgEJAgAAAA==.Soulmoethus:BAAALgADCgYJCQAAAA==.',
Sp='Sprayandpray:BAABLgAECn8VAAIBAAUJhBvwlgBGAQABAAUJhBvwlgBGAQAAAA==.Sprinklely:BAAALgADCgcJCgAAAA==.',
Sq='Squidnips:BAAALgAECgEJAQAAAA==.Squirtney:BAAALgADCgMJAwAAAA==.',
Ss='Ss:BAABLgAFFH8MAAIdAAMJjQFHEwCUAAAdAAMJjQFHEwCUAAAAAA==.Ssl:BAAALgADCgQJBAAAAA==.',
St='Starrwood:BAABLgAECn8kAAISAAkJPgkyYgB0AQASAAkJPgkyYgB0AQAAAA==.Statik:BAAALgAECgIJAwAAAA==.Statík:BAAALgAECgEJAQABLgAECgIJAwACAAAAAA==.Stepmonk:BAAALgAECgEJAQAAAA==.Stevesharts:BAAALgADCgYJCwAAAA==.Stonedlock:BAAALgADCgcJCAAAAA==.Stonetusk:BAAALgAECgUJBgAAAA==.Stroya:BAAALgAECgUJBgAAAA==.',
Su='Sumnèr:BAAALgAECgcJBwAAAA==.Sunastiri:BAAALgADCgkJCQAAAA==.Sunpali:BAAALgAECgcJCwAAAA==.',
Sw='Swank:BAAALgADCgEJAQAAAA==.',
Sx='Sx:BAAALgADCgIJAgAAAA==.',
Sy='Syaa:BAAALgAECgYJBQAAAA==.Syberis:BAAALgADCgcJDgAAAA==.',
Ta='Tacholy:BAABLgAECn8VAAIKAAkJzBdDYgChAQAKAAkJzBdDYgChAQABLgAECgkJLwANAJQcAA==.Tacodaboss:BAAALgAECggJEgAAAA==.Talelarissia:BAAALgADCgQJBAAAAA==.Talonflame:BAABLgAECn8fAAIUAAkJBBy6BwB4AgAUAAkJBBy6BwB4AgAAAA==.Tansu:BAAALgAECgYJEwAAAA==.Tapered:BAAALgAECgUJCQAAAA==.Taupo:BAACLgAFFH8RAAIXAAQJqh9THABhAQAXAAQJqh9THABhAQAuAAQKfycAAhcACQlyH6kNAHoCABcACQlyH6kNAHoCAAAA.',
Tb='Tbanger:BAAALgAECgYJDwAAAA==.Tbh:BAAALgAFFAEJAgABLgAFFAYJDwAXACIaAA==.',
Te='Techevo:BAAALgAECgQJBQAAAA==.Techfire:BAABLgAECn8pAAInAAkJ9hoBAgBJAgAnAAkJ9hoBAgBJAgAAAA==.Techsmexx:BAAALgAECgMJBQAAAA==.Tenebron:BAABLgAECn8pAAIoAAYJQBLCJQD2AAAoAAYJQBLCJQD2AAAAAA==.Tenlucis:BAAALgAECggJDAAAAA==.',
Th='Thaelyssa:BAAALgAECgEJAQAAAA==.Tharria:BAAALgADCgcJBwAAAA==.Thearia:BAABLgAECn8bAAMQAAgJrRWBUgBcAQAQAAgJrRWBUgBcAQATAAUJmg7iUQC3AAAAAA==.Thecanmurk:BAAALgADCgkJEgAAAA==.Thedilf:BAAALgADCgEJAQAAAA==.Thicktotem:BAAALgAECgIJAgAAAA==.Thickumz:BAAALgAECgMJCAAAAA==.Thisismeta:BAAALgAECgYJBwAAAA==.Thorenis:BAAALgADCgEJAQAAAA==.Thoryndruid:BAACLgAFFH8TAAIgAAYJBB0JAgCyAQAgAAYJBB0JAgCyAQAuAAQKfzIAAyAACQkWIxEDAA4DACAACQnmIhEDAA4DAAQABwm8HjEMAA0CAAEuAAUUBwkTABUAQBsA.Thorïn:BAAALgADCgMJAwAAAA==.Thorýn:BAACLgAFFH8TAAIVAAcJQBuLEgAeAgAVAAcJQBuLEgAeAgAuAAQKfxoAAhUACAl8HjYoAFkCABUACAl8HjYoAFkCAAAA.Thórin:BAABLgAECn8iAAIjAAgJQxc4DgDTAQAjAAgJQxc4DgDTAQAAAA==.',
Ti='Timakk:BAAALgADCgEJAQAAAA==.Tipsy:BAABLgAECn8uAAMLAAkJWg/MNQDLAQALAAkJWg/MNQDLAQADAAMJpA38cACGAAAAAA==.',
To='Tombraider:BAAALgAECgMJAwAAAA==.Tomfoolary:BAAALgAECgEJAgAAAA==.Toofy:BAAALgAECgEJAQAAAA==.Tot:BAAALgAECgkJCwAAAA==.Total:BAAALgADCgkJDAAAAA==.Totembear:BAAALgAECgEJAgABLgAFFAIJBQATAKIEAA==.',
Tr='Tralleth:BAABLgAECn8gAAMIAAgJ/hDtMABoAQAIAAgJ/hDtMABoAQAHAAEJGggFOwAtAAAAAA==.Trid:BAAALgAECgQJBQAAAA==.Trillbilly:BAAALgAECgEJAQAAAA==.Trinora:BAAALgADCgkJDgAAAA==.Trolltard:BAAALgAECgIJAgABLgAECgMJAwACAAAAAA==.Troxa:BAAALgAECgUJCgAAAA==.',
Tu='Tuckard:BAAALgADCgEJAQAAAA==.Tuskor:BAAALgAECgIJAgAAAA==.',
Tw='Twinklord:BAAALgAECggJDgAAAA==.',
Ty='Tylanar:BAAALgAECgYJBgAAAA==.Tylolight:BAAALgADCgMJAwAAAA==.Tylomist:BAAALgAECgUJBQAAAA==.Tylototem:BAAALgAFFAEJAgAAAA==.',
Ug='Uglyboi:BAAALgAECggJDwAAAA==.',
Uj='Ujcmonk:BAAALgAECgQJBAAAAA==.',
Ul='Ullbian:BAAALgADCgMJAwAAAA==.Ultramar:BAAALgADCgEJAQAAAA==.',
Un='Uncookedham:BAAALgAECgQJCwAAAA==.',
Ur='Urgh:BAABLgAECn8fAAIJAAkJ9RE6IQC1AQAJAAkJ9RE6IQC1AQAAAA==.Urk:BAAALgAECgYJBgAAAA==.Urzaa:BAAALgAECgEJAwAAAA==.',
Ut='Uthur:BAAALgAECgMJAwAAAA==.',
Va='Vaeelrundor:BAAALgAECgMJBAAAAA==.Valethales:BAAALgADCgcJBwAAAA==.Vanillaface:BAABLgAECn8XAAIKAAgJQRnRPQADAgAKAAgJQRnRPQADAgAAAA==.Vape:BAABLgAECn8WAAIcAAcJLg3ldQBJAQAcAAcJLg3ldQBJAQABLgAFFAQJBwASAFIUAA==.',
Ve='Veinripp:BAAALgADCgUJBQABLgAECggJNAAGAO0QAA==.Velarael:BAABLgAECn8dAAIcAAYJzgrgqADrAAAcAAYJzgrgqADrAAAAAA==.Velaryn:BAAALgADCgIJAgAAAA==.Veldar:BAAALgADCgIJAgAAAA==.Velekete:BAAALgADCgUJBQAAAA==.Velethei:BAABLgAECn8YAAIQAAYJlySkGQBrAgAQAAYJlySkGQBrAgAAAA==.Velian:BAAALgADCgMJBAAAAA==.Velielyn:BAAALgADCgQJBAAAAA==.Vellareth:BAAALgAECgEJAQAAAA==.Verdesalsa:BAAALgAECgcJDQAAAA==.Verox:BAAALgADCgMJAwAAAA==.Verzak:BAAALgAECgEJAQAAAA==.',
Vh='Vheckxus:BAABLgAECn8aAAIDAAYJaBQfPAA1AQADAAYJaBQfPAA1AQAAAA==.',
Vi='Vicv:BAABLgAECn8TAAIJAAkJXwwXNABIAQAJAAkJXwwXNABIAQAAAA==.Vivy:BAAALgADCgMJAwAAAA==.',
Vo='Voidberg:BAAALgAECgIJBwAAAA==.',
['Vê']='Vêa:BAAALgADCgkJCQAAAA==.',
Wa='Wachonaso:BAACLgAFFH8QAAIcAAYJRww7SQAnAQAcAAYJRww7SQAnAQAuAAQKfy0AAxwABwlJH6M0ADkCABwABwkrH6M0ADkCAB0ABgl8HlgXAI8BAAAA.Wanbahl:BAAALgADCgMJAwAAAA==.',
We='Wellburt:BAAALgAECgEJAQAAAA==.',
Wh='Whatuphuz:BAAALgADCgQJBQAAAA==.Wheresmyjaw:BAACLgAFFH8eAAQcAAUJ8R+mNwBTAQAcAAUJZh6mNwBTAQAZAAEJWSNlEgBqAAAdAAEJOQJlKQAzAAAuAAQKfycABBwACAnyIU4VAJ8CABwACAnyIU4VAJ8CAB0AAgm6DiRSAHcAABkAAQnAINgrAGAAAAAA.',
Wi='Wildstàr:BAAALgADCgMJAwAAAA==.Wildthree:BAABLgAECn8rAAMYAAkJwh0zCQCmAgAYAAkJwh0zCQCmAgAbAAMJ2RQvYgC5AAAAAA==.Willenda:BAAALgAECgEJAgAAAA==.Willowins:BAAALgAECgEJAQAAAA==.Winterstired:BAACLgAFFH8YAAIlAAQJRibHBwC3AQAlAAQJRibHBwC3AQAuAAQKf0IAAyUACQnuJD4CAHwDACUACQnuJD4CAHwDAAUAAQlKFy9qAEQAAAAA.',
Wo='Woen:BAAALgADCggJCQAAAA==.Wolf:BAAALgAECgQJBwAAAA==.Wollffie:BAAALgAECgQJBAAAAA==.',
Wu='Wuinn:BAAALgAFFAEJAQABLgAFFAQJEQAQAJQgAA==.Wut:BAAALgADCgcJBwAAAA==.',
Wy='Wynterswrath:BAAALgAECgYJCwAAAA==.',
['Wõ']='Wõnderful:BAABLgAECn8ZAAIQAAcJPhtrIwAlAgAQAAcJPhtrIwAlAgABLgAFFAQJEwAWAPcgAA==.',
Xc='Xclobber:BAAALgADCgIJAgAAAA==.',
Xe='Xemnass:BAAALgAECgUJBwAAAA==.',
Xi='Xillas:BAAALgADCgUJBQAAAA==.',
Xo='Xoverkll:BAAALgAECgYJDAAAAA==.',
Xy='Xylina:BAAALgADCgEJAQAAAA==.Xyrii:BAAALgADCgEJAQAAAA==.',
Ya='Yadder:BAAALgAECgIJBAAAAA==.Yahro:BAACLgAFFH8QAAIKAAUJBRPNOgAmAQAKAAUJBRPNOgAmAQAuAAQKfykAAgoACQmZHQAmAGECAAoACQmZHQAmAGECAAAA.Yamelow:BAAALgAECgQJBgAAAA==.',
Ye='Yeahiknow:BAAALgADCgkJDgAAAA==.Yeling:BAAALgAECgEJAQAAAA==.Yep:BAAALgAECgcJBwAAAA==.',
Yi='Yiska:BAAALgADCgcJBwAAAA==.',
Yo='Yoriale:BAAALgAECgYJDgAAAA==.Yotoymuerto:BAAALgAECgMJAwAAAA==.',
Za='Zafra:BAAALgADCgEJAQAAAA==.Zaimara:BAAALgAECgEJBQAAAA==.Zalind:BAABLgAECn8VAAIcAAkJCxJoZgCYAQAcAAkJCxJoZgCYAQAAAA==.Zalvianna:BAABLgAECn8dAAMBAAcJGgTM1QDjAAABAAcJGgTM1QDjAAAmAAEJXQHIIgAYAAAAAA==.Zarindlina:BAAALgADCgUJBQAAAA==.Zarshx:BAAALgAECgYJCwABLgAFFAMJBAACAAAAAA==.',
Ze='Zemonk:BAAALgAECgYJBgAAAA==.',
Zi='Zilong:BAAALgAFFAEJAQABLgAFFAUJDwAGAAEaAA==.Zilongmage:BAAALgAFFAIJAwABLgAFFAUJDwAGAAEaAA==.Zilongwar:BAAALgAFFAMJAwABLgAFFAUJDwAGAAEaAA==.Zinnia:BAAALgADCgEJAgAAAA==.',
Zo='Zonedk:BAABLgAECn8WAAQWAAYJfB/qEQBGAQAaAAUJQCHSHQBdAQAWAAYJLBbqEQBGAQAVAAEJxBcsTQFBAAAAAA==.Zonerg:BAAALgADCgEJAgABLgAECgYJFgAWAHwfAA==.Zonevn:BAAALgAECgMJAwABLgAECgYJFgAWAHwfAA==.Zordak:BAAALgADCgcJCAAAAA==.Zosin:BAAALgAECgEJAQAAAA==.',
Zu='Zugzugzapzap:BAAALgADCgEJAQAAAA==.',
Zy='Zylphanae:BAAALgAECgQJBAAAAA==.',
['Ør']='Ørsted:BAAALgAECgEJAgABLgAFFAQJEQAXAKofAA==.',
['ßi']='ßish:BAAALgAECgEJAgAAAA==.',
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
