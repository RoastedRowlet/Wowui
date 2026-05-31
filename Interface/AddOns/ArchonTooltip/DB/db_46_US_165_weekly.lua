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

local lookup = {'Mage-Frost','Unknown-Unknown','Shaman-Elemental','Monk-Brewmaster','DemonHunter-Devourer','Evoker-Preservation','Evoker-Augmentation','Priest-Shadow','Paladin-Retribution','Shaman-Restoration','Hunter-Marksmanship','Druid-Guardian','Warrior-Arms','Warrior-Fury','DemonHunter-Vengeance','Druid-Restoration','DemonHunter-Havoc','Hunter-BeastMastery','Druid-Balance','Hunter-Survival','DeathKnight-Unholy','DeathKnight-Frost','Monk-Mistweaver','Monk-Windwalker','Warlock-Affliction','DeathKnight-Blood','Warlock-Demonology','Warlock-Destruction','Evoker-Devastation','Shaman-Enhancement','Druid-Feral','Rogue-Subtlety','Rogue-Assassination','Priest-Discipline','Paladin-Protection','Paladin-Holy','Priest-Holy','Mage-Arcane','Mage-Fire','Warrior-Protection',}
local provider = {region='US',realm='Nazjatar',name='US',type='weekly',zone=46,date='2026-05-30',data={Aa='Aaela:BAAALgADCgUJBQAAAA==.',
Ab='Abrasaxs:BAABLgAECn8qAAIBAAgJQhgoUQDQAQABAAgJQhgoUQDQAQAAAA==.Absylus:BAAALgAECgQJBAABLgAFFAMJBAACAAAAAA==.',
Ac='Ackerman:BAAALgAECgYJCgABLgAECggJEgACAAAAAA==.Acraea:BAABLgAECn8eAAIBAAgJmwywewBmAQABAAgJmwywewBmAQAAAA==.Acslater:BAAALgAECgMJCQAAAA==.Actionman:BAAALgAECgkJBwAAAA==.',
Ag='Agoobagoo:BAACLgAFFH8SAAIDAAQJnSL8DwB0AQADAAQJnSL8DwB0AQAuAAQKfx8AAgMACQnZIpAEAFIDAAMACQnZIpAEAFIDAAEuAAUUBQkMAAQAmxQA.',
Ai='Aionn:BAAALgAECgMJAwAAAA==.Airrow:BAAALgAFFAEJAQAAAA==.Aissae:BAACLgAFFH8NAAIFAAQJ7hyhKABYAQAFAAQJ7hyhKABYAQAuAAQKfykAAgUACAlAJHYLACYDAAUACAlAJHYLACYDAAAA.Aiyama:BAAALgADCgQJBAAAAA==.',
Ak='Akiio:BAAALgAECgMJAwAAAA==.Akumaxl:BAAALgAECgYJBwAAAA==.',
Al='Alexia:BAAALgAECgEJAQAAAA==.Alfrank:BAAALgAECgIJAwAAAA==.Aliasx:BAAALgAECgMJBAAAAA==.Allwrong:BAAALgAECgEJAQAAAA==.Alphrank:BAAALgAECgEJAgAAAA==.Alurie:BAAALgAECgUJBgAAAA==.',
Am='Ambros:BAAALgADCgYJBgAAAA==.Aminatou:BAAALgAECgYJBgAAAA==.',
An='Anheeboan:BAAALgAECgYJCwAAAA==.Anihilated:BAAALgADCgYJBwAAAA==.',
Ar='Aradiax:BAAALgADCgYJBgAAAA==.Arcadavia:BAAALgADCgMJAwAAAA==.Ariaprime:BAAALgAECgUJBQAAAA==.Arjentheilus:BAAALgAECgMJAwAAAA==.Arthasl:BAAALgADCgMJAgAAAA==.Arthur:BAAALgAECgQJDgAAAA==.',
As='Asasda:BAAALgADCgMJBAAAAA==.Ashaelra:BAAALgAECgYJCAAAAA==.Astravaritan:BAAALgADCgMJAwAAAA==.',
At='Atherya:BAAALgAECgYJCAAAAA==.Atomixblonde:BAAALgAECgEJAQAAAA==.',
Au='Augonly:BAACLgAFFH8dAAIGAAYJHhdGCwDHAQAGAAYJHhdGCwDHAQAuAAQKfyMAAgYACQnpIC4GAOECAAYACQnpIC4GAOECAAAA.Augy:BAACLgAFFH8MAAIHAAQJKAxjLAD2AAAHAAQJKAxjLAD2AAAuAAQKfxsAAgcACAk1F+gcANYBAAcACAk1F+gcANYBAAAA.Autoshot:BAAALgAFFAIJAgAAAA==.',
Av='Averisbelia:BAAALgADCggJDQAAAA==.',
Ay='Ayowamsley:BAAALgADCgMJAwAAAA==.',
Az='Azalea:BAAALgAECggJEAAAAA==.',
Ba='Babycrock:BAAALgADCgYJBgAAAA==.Back:BAAALgADCgcJDAAAAA==.Bakihanma:BAAALgAECgQJBgAAAA==.Balash:BAAALgADCgUJBQAAAA==.Balerion:BAAALgADCgEJAQABLgADCgMJAwACAAAAAA==.Balthasar:BAABLgAECn8hAAIIAAkJdxkgDgBZAgAIAAkJdxkgDgBZAgAAAA==.Banjobits:BAAALgADCgIJAgAAAA==.Barhead:BAAALgAECgYJDAAAAA==.Barlow:BAAALgAECggJEQAAAA==.Barqose:BAAALgADCgMJAwAAAA==.Barryberry:BAABLgAECn8fAAIJAAkJDREgcgBvAQAJAAkJDREgcgBvAQAAAA==.Barryx:BAAALgAECgIJAgAAAA==.',
Bb='Bbldrizzy:BAABLgAFFH8FAAIKAAMJjR5FMQD7AAAKAAMJjR5FMQD7AAAAAA==.',
Be='Beastlieduke:BAAALgAECgMJAwABLgAFFAQJFAAIAKgNAA==.Beastlièduke:BAACLgAFFH8UAAIIAAQJqA0oGAASAQAIAAQJqA0oGAASAQAuAAQKfy4AAggACAnwHvQOAJQCAAgACAnwHvQOAJQCAAAA.Beauslay:BAAALgAECgEJAQAAAA==.Belephon:BAAALgAECgYJEAAAAA==.Bellaruhbz:BAABLgAECn8eAAILAAkJjA/rFAD+AAALAAkJjA/rFAD+AAAAAA==.Berenstain:BAABLgAECn8nAAIMAAkJShOxEwCZAQAMAAkJShOxEwCZAQAAAA==.Bergmire:BAAALgAECgQJCQAAAA==.Berple:BAAALgADCgUJBQABLgAFFAcJGAABANsiAA==.Bestoresto:BAABLgAECn8XAAIKAAkJBQxvPACgAQAKAAkJBQxvPACgAQAAAA==.',
Bh='Bhori:BAAALgAECgEJAwAAAA==.',
Bi='Bibahabibi:BAABLgAECn8dAAMNAAYJxhvDIAA/AQANAAYJxhvDIAA/AQAOAAMJzQiVhwChAAAAAA==.Bigddk:BAAALgAECgQJBwAAAA==.Bigpapax:BAAALgAECgEJAQAAAA==.Bigtac:BAABLgAECn8vAAMNAAkJlBzqBwBgAgANAAkJlBzqBwBgAgAOAAIJ3gc5mQBcAAAAAA==.Binggus:BAAALgAECgUJCgABLgAECgkJHQAPAEQjAA==.',
Bl='Blabbybootze:BAAALgAECgYJBgAAAA==.Bladelight:BAAALgAECgUJBgAAAA==.Blighte:BAAALgADCgQJBAABLgAECggJIQAQAIIkAA==.Blightfangs:BAABLgAECn83AAIBAAgJehkEOwAXAgABAAgJehkEOwAXAgAAAA==.Blindnautdef:BAABLgAECn80AAMFAAgJ7RBbXwBSAQAFAAgJ7RBbXwBSAQARAAEJ9gPEbQAhAAAAAA==.Bloodluna:BAAALgADCgUJBQAAAA==.',
Bo='Bobman:BAAALgAECgQJBgAAAA==.Bodakye:BAABLgAECn8kAAMSAAkJQRsJJgAyAgASAAkJQRsJJgAyAgALAAIJtAEQgQBDAAAAAA==.Bonargrowrod:BAAALgAECgMJAwAAAA==.Bonkz:BAAALgAECgMJAwAAAA==.Boomtip:BAAALgADCgMJAwAAAA==.Boon:BAAALgADCgYJCQAAAA==.Bordolor:BAAALgADCgYJCwAAAA==.Bowsa:BAAALgAECgkJAQAAAA==.',
Br='Brethathes:BAAALgAECgkJEgAAAA==.Brudda:BAAALgADCgUJBQAAAA==.',
Bu='Bubbaray:BAAALgAECgMJAwAAAA==.Bubblebun:BAAALgAECgMJBgAAAA==.Bungerhole:BAABLgAECn8VAAMQAAgJhhrwLADhAQAQAAgJhhrwLADhAQATAAEJEQnniwAmAAAAAA==.Butane:BAAALgADCgIJAgAAAA==.Buzzbuzz:BAAALgAECgIJBgAAAA==.',
Ca='Cainn:BAAALgAECgYJBwAAAA==.Cap:BAAALgADCgEJAQABLgAFFAQJFAABAGIeAA==.Capriestsun:BAAALgAFFAIJAgAAAA==.Captyn:BAAALgAECgQJDAAAAA==.Carridin:BAAALgADCgMJAwAAAA==.Cass:BAAALgAECgEJAQAAAA==.',
Ce='Cernunon:BAAALgADCgEJAQAAAA==.',
Ch='Chaosdemon:BAABLgAECn81AAIFAAkJPRCjPgC2AQAFAAkJPRCjPgC2AQAAAA==.Chaosraven:BAAALgADCgkJCQAAAA==.Chapelgnome:BAAALgAECgIJAgABLgAFFAYJBwAHAIUCAA==.Charlottea:BAAALgAECgYJDQAAAA==.Chemdra:BAAALgAECgcJEwAAAA==.Chiling:BAAALgAECgEJAQAAAA==.Chipmonkey:BAAALgAECgEJAgABLgAECggJJwAQAL4QAA==.Chiptime:BAABLgAECn8nAAIQAAgJvhD3PACNAQAQAAgJvhD3PACNAQABLgAECggJJwAQAL4QAA==.Chomby:BAAALgAECgQJAwAAAA==.Chriifrio:BAAALgADCgUJBgAAAA==.Chromosomes:BAAALgAECgQJBAAAAA==.Chud:BAAALgAECgQJCAAAAA==.Chudsworth:BAAALgADCgYJCQAAAA==.Chunguhlumpo:BAAALgAECgEJBAAAAA==.Chzburger:BAAALgAECgIJAgAAAA==.',
Ci='Cinnamóróll:BAABLgAECn8qAAIUAAgJ/woQIQCGAQAUAAgJ/woQIQCGAQAAAA==.',
Cl='Clairity:BAAALgAECgMJAwAAAA==.Cleru:BAABLgAECn8eAAMVAAgJlBIHdABnAQAVAAgJlBIHdABnAQAWAAEJpwMVGgAlAAAAAA==.Cletus:BAAALgADCgcJAgAAAA==.',
Co='Coa:BAAALgAECgkJDAAAAA==.Cocoon:BAABLgAFFH8PAAMXAAYJIhoADwDMAQAXAAYJIhoADwDMAQAYAAIJ+xbAJACeAAAAAA==.Coldsoul:BAAALgADCgUJBQAAAA==.Comanderkush:BAAALgADCgMJAwAAAA==.Coran:BAAALgAECgIJAwABLgAECgkJJAAZAG0bAA==.Corita:BAAALgAECgIJAgAAAA==.Cowboi:BAAALgADCgMJAwAAAA==.Cowhealer:BAABLgAECn8hAAMQAAgJgiRkCAAIAwAQAAgJgiRkCAAIAwATAAEJTwUTgQAvAAAAAA==.',
Cr='Creamypies:BAAALgAECgEJAQAAAA==.Criticaltwo:BAAALgADCgIJAgAAAA==.Crockknight:BAAALgADCgYJBgAAAA==.Crossways:BAAALgAECgYJCQAAAA==.Cræftig:BAAALgAECgYJDAAAAA==.',
Cu='Cursecthree:BAAALgADCgEJAQAAAA==.Curseword:BAAALgAECgEJAQAAAA==.Cutestxx:BAAALgAECgkJCwAAAA==.',
Cy='Cyxo:BAAALgADCgEJAQABLgAECgEJAQACAAAAAA==.',
Da='Daftxshade:BAAALgAECgYJDgAAAA==.Dandandan:BAAALgADCgMJAwAAAA==.Dapan:BAAALgADCgcJDQAAAA==.Dariaa:BAAALgAECgQJDQAAAA==.Darkcrusader:BAAALgAECgcJEAAAAA==.Darkheal:BAAALgADCgUJBQAAAA==.Darkladie:BAAALgADCgEJAQAAAA==.Darkshadows:BAAALgAECgEJAgAAAA==.Darthsyde:BAABLgAECn8WAAIaAAgJShHzGgBqAQAaAAgJShHzGgBqAQAAAA==.Dasdk:BAABLgAFFH8NAAIVAAQJeBrXNwBjAQAVAAQJeBrXNwBjAQAAAA==.Daspriest:BAAALgADCgYJDQABLgAFFAQJDQAVAHgaAA==.',
De='Deadergriff:BAAALgAECggJDAAAAA==.Deadhippycb:BAAALgAECgQJBAAAAA==.Deadhippyxy:BAAALgAECgEJAgAAAA==.Deadicated:BAABLgAECn8eAAQEAAcJpQdKQQDkAAAEAAcJLAZKQQDkAAAYAAYJKAgBVQCgAAAXAAUJaQUvdgB8AAAAAA==.Deadsies:BAAALgADCgIJAgABLgAFFAIJAgACAAAAAA==.Deeds:BAAALgAECgMJAwAAAA==.Delan:BAAALgAECgQJBQAAAA==.Delveknight:BAAALgADCgYJBgABLgAECgcJFwAVAHUdAA==.Demoncox:BAAALgADCgMJAgAAAA==.Demondoc:BAACLgAFFH8HAAIFAAQJzQXhVQDLAAAFAAQJzQXhVQDLAAAuAAQKfx0AAgUACAlpF0IvAPQBAAUACAlpF0IvAPQBAAAA.Desunaito:BAACLgAFFH8aAAMWAAYJniEpAgC7AQAWAAYJniEpAgC7AQAaAAEJAABySwAAAAAuAAQKfy0AAhYACQlUJfMAAC0DABYACQlUJfMAAC0DAAAA.Devious:BAAALgADCgEJAQAAAA==.',
Dh='Dhzilong:BAACLgAFFH8PAAIFAAUJARrGNQAnAQAFAAUJARrGNQAnAQAuAAQKfx0AAwUACAlHIU84ABQCAAUACAkzHk84ABQCABEABQmNJJEeAMoBAAAA.',
Di='Diddlefiddle:BAAALgAFFAIJBAAAAA==.Dihcum:BAAALgAFFAIJAgAAAA==.Dimonologist:BAAALgAECgEJAQAAAA==.Dinpala:BAAALgADCgUJBQABLgAECgcJHgAXAKoXAA==.Dirtycow:BAAALgAECgQJBAAAAA==.',
Dk='Dkzilong:BAAALgAFFAIJBAABLgAFFAUJDwAFAAEaAA==.',
Do='Docholy:BAAALgAECgYJCAABLgAFFAQJBwAFAM0FAA==.Dockson:BAAALgAECgMJAwAAAA==.Docwyle:BAABLgAECn8XAAMbAAgJnxGOZgBmAQAbAAgJnxGOZgBmAQAcAAEJtgLUcgAzAAABLgAFFAQJBwAFAM0FAA==.Doobyia:BAAALgADCgEJAQAAAA==.Dorki:BAAALgAECgEJAgAAAA==.Dorlanlemeth:BAABLgAECn8VAAIFAAcJBwx2eAAUAQAFAAcJBwx2eAAUAQAAAA==.Dormist:BAAALgAECgMJBAABLgAECgkJJAAZAG0bAA==.Dotti:BAAALgAFFAEJAQAAAA==.',
Dr='Dracnogard:BAAALgAECgYJDQAAAA==.Dracowulf:BAABLgAECn8eAAISAAgJbRBGTACkAQASAAgJbRBGTACkAQAAAA==.Dragonx:BAABLgAECn8uAAMSAAgJchHqQwCgAQASAAgJchHqQwCgAQAUAAMJaQ0aQACvAAAAAA==.Drakos:BAAALgAECgEJAQAAAA==.Drakowolf:BAABLgAECn89AAIdAAgJWQUgDwAIAQAdAAgJWQUgDwAIAQAAAA==.Drenz:BAAALgADCgEJAQAAAA==.Dreorge:BAABLgAFFH8GAAIHAAMJcxFCNgDKAAAHAAMJcxFCNgDKAAAAAA==.Dreuceratops:BAAALgAECgMJAwAAAA==.Drewceratops:BAABLgAECn8oAAIJAAkJtRRfPAD6AQAJAAkJtRRfPAD6AQAAAA==.Driis:BAAALgADCgcJBwAAAA==.Drimchi:BAABLgAFFH8FAAIHAAMJhBBoOADCAAAHAAMJhBBoOADCAAAAAA==.Drizro:BAAALgADCgIJAgAAAA==.Drk:BAAALgAECgEJAQAAAA==.Dromash:BAABLgAECn8kAAMZAAkJbRuUAgCKAgAZAAkJbRuUAgCKAgAcAAgJLhOaCgB8AQAAAA==.Dromgar:BAAALgAFFAIJBAABLgAFFAMJCAAeAAojAA==.Druidyhealz:BAAALgAECgMJAwABLgAECgcJDwACAAAAAA==.',
['Då']='Dårius:BAAALgAECgYJEQAAAA==.',
Ea='Eaterofpaint:BAAALgAECgYJDgAAAA==.',
Ed='Edgeylord:BAAALgAECgEJAQAAAA==.',
Ef='Effloria:BAABLgAECn8lAAIQAAkJEx1WCwD4AgAQAAkJEx1WCwD4AgAAAA==.Efrideet:BAAALgADCgEJAQAAAA==.',
Ei='Eisha:BAAALgADCgUJBQAAAA==.',
El='Elegia:BAACLgAFFH8RAAIbAAUJsw9USgAgAQAbAAUJsw9USgAgAQAuAAQKfywAAxsACQlJGyIZAL4CABsACQlJGyIZAL4CABwAAQkAAAdmAEMAAAAA.Elerianor:BAAALgAECgYJEQAAAA==.Ellektra:BAAALgADCgUJBQAAAA==.',
Em='Emadiropilo:BAAALgAECgEJAQAAAA==.Emakaa:BAAALgAECgYJCAAAAA==.Embrohunter:BAAALgAECgQJBAAAAA==.',
En='Enash:BAAALgAECgQJBwAAAA==.Engvald:BAAALgADCgUJBQAAAA==.Enhua:BAAALgADCgUJBQAAAA==.Ennet:BAAALgAECgEJAQAAAA==.',
Er='Eretin:BAAALgADCgEJAQAAAA==.Erismorn:BAABLgAECn8iAAQPAAcJNR5cCwCpAQAPAAYJnBtcCwCpAQAFAAYJiBjLUgB2AQARAAEJ4RAEcAA1AAAAAA==.',
Eu='Eudi:BAAALgAECgEJAgAAAA==.',
Ev='Eventhorizòn:BAAALgAECggJEwAAAA==.Evilhoe:BAAALgADCgUJBQAAAA==.Evocation:BAAALgAECggJEgAAAA==.Evoextoons:BAAALgADCgcJGQAAAA==.',
Fa='Fallen:BAABLgAECn8XAAMVAAkJfySKNgARAgAVAAkJfySKNgARAgAaAAMJ7wvBPQCAAAAAAA==.Fallingvoid:BAABLgAECn9gAAIFAAkJJiQaAgC3AwAFAAkJJiQaAgC3AwAAAA==.Fast:BAAALgAECgEJAgABLgAECgIJAgACAAAAAA==.Fatchungus:BAAALgAFFAMJBAAAAA==.Fatherben:BAABLgAECn8XAAIFAAYJVBXVdAAcAQAFAAYJVBXVdAAcAQAAAA==.Fatmagus:BAAALgAECgcJBgAAAA==.Favio:BAAALgAECggJCwAAAA==.',
Fe='Fellbian:BAAALgADCgcJDgAAAA==.Fentanyahu:BAAALgAECgYJBgAAAA==.Ferozz:BAACLgAFFH8LAAILAAMJSw7KFwDIAAALAAMJSw7KFwDIAAAuAAQKfzEAAgsACAm7HjgGABwCAAsACAm7HjgGABwCAAAA.',
Fi='Fiercetaco:BAAALgADCgEJAQAAAA==.Finaliter:BAACLgAFFH8KAAIJAAMJYBR8VQDiAAAJAAMJYBR8VQDiAAAuAAQKfyoAAgkACQk7IEEfAHQCAAkACQk7IEEfAHQCAAAA.Finatar:BAAALgADCgcJCwAAAA==.Fiora:BAABLgAECn8SAAIFAAcJKx87KQBdAgAFAAcJKx87KQBdAgAAAA==.Fitz:BAAALgADCgEJAQAAAA==.Fiveyears:BAAALgADCgEJAQAAAA==.',
Fk='Fknutmcgee:BAAALgAECgUJBQAAAA==.',
Fl='Flamingdrago:BAAALgADCgkJEwAAAA==.Flinti:BAAALgAECgUJCQAAAA==.Floggy:BAABLgAECn8eAAIBAAgJNghlkQA6AQABAAgJNghlkQA6AQAAAA==.',
Fo='Forsight:BAABLgAECn8YAAIVAAgJUhWicgBqAQAVAAgJUhWicgBqAQAAAA==.',
Fr='Fracker:BAAALgAECgcJCAAAAA==.Frankzzorz:BAACLgAFFH8IAAIXAAMJZgobNQCSAAAXAAMJZgobNQCSAAAuAAQKfzQAAxcACQk1HLQMAIcCABcACQk1HLQMAIcCABgAAglFIL9PALEAAAAA.Fremder:BAACLgAFFH8SAAIGAAQJqBNZFAAuAQAGAAQJqBNZFAAuAQAuAAQKfzkAAgYACQmqHDUEAN4CAAYACQmqHDUEAN4CAAAA.Fresher:BAABLgAECn8VAAIVAAUJyxwYpAAQAQAVAAUJyxwYpAAQAQAAAA==.Freyjen:BAAALgADCgkJGAABLgAECgcJCgACAAAAAA==.Froboz:BAAALgADCgYJCQAAAA==.Frogevil:BAAALgAECgYJEAAAAA==.Frogtree:BAAALgADCgUJBQAAAA==.Frostygirl:BAABLgAECn8qAAIBAAgJMBShUgDMAQABAAgJMBShUgDMAQAAAA==.Frumentarii:BAAALgAECgQJBAAAAA==.',
Fu='Funeral:BAACLgAFFH8rAAQcAAgJcBnpAgB5AQAcAAUJ/R3pAgB5AQAZAAMJOhp0BAAnAQAbAAMJQxV4MACyAAAuAAQKfzMABBwACQmyIz4EAKECABwABwnSID4EAKECABkABwkrIhAEAEMCABsACAn9GOtEAP0BAAAA.',
['Fà']='Fàstïk:BAAALgAECgEJAQAAAA==.',
Ga='Galladin:BAAALgAECgMJBQABLgAECgYJDQACAAAAAA==.Gallory:BAAALgAECgcJDQAAAA==.Gareeshala:BAAALgAECgIJAgAAAA==.',
Gd='Gdk:BAAALgAECgIJAgAAAA==.Gdkmage:BAAALgAECgkJCQAAAA==.',
Ge='Geomancer:BAAALgADCgQJBAAAAA==.',
Gh='Ghadius:BAAALgAECgQJBAAAAA==.',
Gi='Gimmedatmouf:BAABLgAECn8XAAQQAAgJoyHjCAABAwAQAAgJoyHjCAABAwAfAAMJph5vJwCtAAATAAQJexYCWACVAAAAAA==.Gimmedatneck:BAABLgAECn8XAAMgAAgJVSNhGABEAgAgAAgJVSNhGABEAgAhAAEJNhLgHABDAAAAAA==.Gingy:BAAALgAECgEJAQAAAA==.',
Gl='Glead:BAABLgAECn8YAAIOAAkJ6ReNLQD9AQAOAAkJ6ReNLQD9AQAAAA==.Glizzymguire:BAAALgAECggJCAABLgAFFAIJCQAbAG0DAA==.',
Gn='Gneeduh:BAAALgAECgIJAwAAAA==.',
Go='Gobknight:BAAALgADCggJCAAAAA==.Goldina:BAAALgAECgEJAQAAAA==.Gooklover:BAAALgAECgQJCQAAAA==.Gosupal:BAAALgADCgYJBgAAAA==.',
Gr='Gracious:BAAALgAECgEJAQAAAA==.Graegor:BAAALgADCgYJBwAAAA==.Grastim:BAAALgAECgUJCgAAAA==.Greenfanta:BAAALgADCgYJEAAAAA==.Grill:BAAALgADCgEJAQAAAA==.Grinkle:BAACLgAFFH8FAAIKAAMJjwU3TACjAAAKAAMJjwU3TACjAAAuAAQKfysAAgoACQkjEQw2AL0BAAoACQkjEQw2AL0BAAAA.Gripopotamus:BAAALgADCgkJDQAAAA==.Gristle:BAAALgADCgkJJwAAAA==.',
Gu='Guldangg:BAAALgAECgUJCQAAAA==.Gunner:BAABLgAECn8aAAISAAkJuSK/BAA2AwASAAkJuSK/BAA2AwAAAA==.',
Ha='Hakaishaz:BAAALgADCgUJBgAAAA==.Halfwatt:BAAALgAECgYJDQAAAA==.Hamaddor:BAAALgAECgYJBgAAAA==.Handen:BAAALgADCggJCAAAAA==.Haraldsson:BAABLgAECn8cAAIJAAgJyRTXYgCRAQAJAAgJyRTXYgCRAQAAAA==.Harmony:BAAALgADCgcJCgAAAA==.Harrin:BAAALgADCgYJDAAAAA==.Harrydabs:BAABLgAECn8dAAMPAAkJRCNNAACDAwAPAAkJRCNNAACDAwARAAQJJRB3PwD+AAAAAA==.Haru:BAABLgAECn8dAAIUAAgJfRPDGADLAQAUAAgJfRPDGADLAQAAAA==.Harvaal:BAAALgAECgUJBQAAAA==.Hasaro:BAACLgAFFH8IAAIMAAMJpBETFgCuAAAMAAMJpBETFgCuAAAuAAQKfyUAAgwACQmXGR4IAFECAAwACQmXGR4IAFECAAAA.Hashimi:BAAALgAECgcJBwAAAA==.Havokvacano:BAABLgAECn8fAAIJAAkJjxNyPwDwAQAJAAkJjxNyPwDwAQAAAA==.',
He='Healmachine:BAAALgAECgYJDwAAAA==.Hellbrringer:BAAALgAECgYJDgAAAA==.Helzerx:BAABLgAECn8hAAIgAAkJfBxDBwCgAgAgAAkJfBxDBwCgAgABLgAFFAIJAgACAAAAAA==.Herpstrike:BAAALgAECgIJAgAAAA==.',
Ho='Hoely:BAAALgAECgEJAQAAAA==.Hogmanjr:BAAALgADCgEJAwAAAA==.Hotsordots:BAAALgAECggJCwAAAA==.Hounskul:BAABLgAECn8gAAIbAAkJogdecQBMAQAbAAkJogdecQBMAQAAAA==.',
Hu='Hugealien:BAAALgADCgIJAgAAAA==.Hungchungus:BAAALgAECgEJAgAAAA==.Hungwaylo:BAAALgADCgIJAgAAAA==.',
Hw='Hwere:BAAALgAECgUJBgAAAA==.',
Hy='Hypnoticpal:BAAALgAECgkJBwAAAA==.Hystëria:BAACLgAFFH8TAAMWAAQJ9yATBACFAQAWAAQJ9yATBACFAQAVAAMJaRVPjQDPAAAuAAQKf1IAAxYACQmQIwEBACYDABYACQmhIgEBACYDABUACAkJIawiAGgCAAAA.Hyunlix:BAAALgADCgUJBQAAAA==.',
Ia='Iammoo:BAAALgAECgcJEgAAAA==.',
Id='Idasie:BAAALgADCgcJBwAAAA==.',
Ig='Igotkappa:BAAALgADCgMJAwAAAA==.Igotyourback:BAAALgAECggJCAAAAA==.',
Il='Ilydris:BAAALgADCgQJBAAAAA==.',
Im='Imadruid:BAAALgADCgQJBAAAAA==.',
Io='Iolyte:BAAALgAECgYJDQAAAA==.',
Ir='Iridellis:BAACLgAFFH8LAAIiAAQJjAebIwD9AAAiAAQJjAebIwD9AAAuAAQKfyEAAiIACQnQEjEUABwCACIACQnQEjEUABwCAAAA.',
Is='Ispankutank:BAAALgAECgYJCQAAAA==.',
It='Itssofluffy:BAABLgAECn8vAAQfAAkJlBhDBwBFAgAfAAkJDRhDBwBFAgAMAAUJBhfbEwAyAQATAAIJUgnshgAqAAAAAA==.Itwon:BAAALgAECgMJAwAAAA==.',
Iz='Izzelda:BAAALgAECgEJAQAAAA==.',
Ja='Jacus:BAAALgAECgQJCAAAAA==.Jahumc:BAAALgAECgEJAQAAAA==.Janeoftrades:BAAALgAECgYJDAAAAA==.Jaycers:BAABLgAECn8iAAQjAAkJ9SAvBACpAgAjAAkJ8B8vBACpAgAJAAUJERz2igBAAQAkAAEJ2AIAnwAqAAAAAA==.Jayclark:BAAALgADCgcJCgAAAA==.',
Je='Jessiriusrex:BAAALgADCgEJAQAAAA==.',
Jo='Joemomma:BAABLgAECn8UAAIBAAYJIw1wxADkAAABAAYJIw1wxADkAAAAAA==.Jokestarfist:BAABLgAECn8ZAAIJAAQJgRjnqwAJAQAJAAQJgRjnqwAJAQAAAA==.',
Jr='Jr:BAAALgADCgMJBAAAAA==.',
Jt='Jtheshadow:BAAALgAECgEJAQAAAA==.',
Ju='Junachan:BAAALgAECgMJBQAAAA==.Jurichan:BAAALgAECgMJCQAAAA==.',
['Jä']='Jägernaut:BAAALgADCgEJAQAAAA==.',
Ka='Kaitokit:BAAALgAFFAIJAgAAAA==.Kajamando:BAABLgAECn8eAAIRAAgJ7wcHKAAVAQARAAgJ7wcHKAAVAQAAAA==.Kalith:BAABLgAECn8YAAIUAAkJCgNxLAAwAQAUAAkJCgNxLAAwAQAAAA==.Kallydots:BAAALgADCgcJDQAAAA==.Kayllina:BAABLgAECn8kAAIVAAgJLwaLlAApAQAVAAgJLwaLlAApAQAAAA==.Kayotic:BAABLgAECn8hAAIRAAcJ2QQ/NgC/AAARAAcJ2QQ/NgC/AAAAAA==.Kayww:BAAALgAECgQJBgAAAA==.',
Ke='Keinarra:BAAALgADCgMJBgAAAA==.Kell:BAAALgADCgcJCAAAAA==.Kelmorphic:BAABLgAECn8tAAMPAAkJMyGQAQD8AgAPAAkJMyGQAQD8AgARAAEJ7QoGZQAsAAAAAA==.Keropikapika:BAAALgADCgUJBQAAAA==.',
Kh='Khaali:BAAALgAECgEJBAAAAA==.Khristina:BAAALgAECgEJAgAAAA==.',
Ki='Kikiana:BAAALgAECgQJCAABLgAECggJLgAlAKQhAA==.Kikstyx:BAAALgADCgYJCAAAAA==.Killerxd:BAABLgAECn8WAAIJAAgJJRiqXQCdAQAJAAgJJRiqXQCdAQAAAA==.Killesea:BAAALgADCgcJDAAAAA==.Kittfisto:BAABLgAECn8iAAQPAAkJmhUMEwADAQAFAAkJiBStXgCFAQAPAAQJ4BQMEwADAQARAAYJmAyPLwDlAAAAAA==.',
Kn='Knitemare:BAAALgAECgEJAQAAAA==.',
Ko='Korivos:BAAALgADCgMJAwAAAA==.Kosmas:BAABLgAECn8eAAMOAAgJJiE/HQDwAQAOAAgJ3B4/HQDwAQANAAYJlRz+FgCLAQAAAA==.',
Kr='Krushgar:BAABLgAECn8UAAMVAAcJsRcIXQDbAQAVAAcJsRcIXQDbAQAWAAEJsxAPMgAtAAAAAA==.',
Ku='Kuchikopii:BAAALgADCgYJBgAAAA==.Kungfuelf:BAAALgADCgEJAQAAAA==.Kurookami:BAAALgAECgEJAQAAAA==.',
La='Lackluster:BAACLgAFFH8FAAIBAAMJMwFGkgCPAAABAAMJMwFGkgCPAAAuAAQKfyQAAgEACAlNCU25AG4BAAEACAlNCU25AG4BAAAA.Lamatrick:BAAALgAECgUJBwAAAA==.Lanadelslayy:BAAALgAECgQJBwAAAA==.Lasenza:BAAALgADCgQJBAAAAA==.Lavacoomer:BAAALgADCgYJBQAAAA==.',
Ld='Ldg:BAAALgAECgEJAQAAAA==.',
Le='Ledana:BAAALgAECgIJAgAAAA==.Lejosh:BAAALgAECgIJAgAAAA==.Lennon:BAAALgAECgkJBgAAAA==.Leona:BAAALgAECgYJCgAAAA==.Lethee:BAAALgAECgEJAgAAAA==.Letusgiveita:BAAALgADCgEJAQAAAA==.Lexazshara:BAAALgAECgEJAQAAAA==.',
Li='Lightingbolt:BAAALgAECgUJCgAAAA==.Lightlybaked:BAAALgAFFAEJAQAAAA==.Lilithamy:BAAALgADCgYJBgAAAA==.Lilthin:BAAALgAECggJEQAAAA==.Liore:BAAALgAECgQJBgAAAA==.Lisathe:BAAALgAECgYJEgAAAA==.Lithdrae:BAAALgADCgYJBgAAAA==.Littledude:BAAALgADCgQJBQAAAA==.Littlemorsel:BAABLgAECn8eAAISAAkJNxOILQAQAgASAAkJNxOILQAQAgAAAA==.Livelaughlov:BAAALgAECgEJAQAAAA==.',
Lo='Louthar:BAAALgADCgcJAQAAAA==.',
Ls='Lselec:BAAALgADCgYJBgAAAA==.',
Lt='Ltdapperdan:BAAALgAECgEJAQAAAA==.',
Lu='Lucens:BAABLgAECn8oAAIkAAgJSRPTHQD+AQAkAAgJSRPTHQD+AQAAAA==.Lunagreed:BAAALgADCgUJBQAAAA==.Lurchn:BAABLgAECn9MAAIBAAkJwg+GWwCzAQABAAkJwg+GWwCzAQAAAA==.',
Ly='Lysariax:BAAALgADCgMJAwAAAA==.',
['Lï']='Lïght:BAABLgAFFH8FAAIJAAQJWiCjGQB7AQAJAAQJWiCjGQB7AQABLgAFFAQJEwAWAPcgAA==.',
['Lú']='Lúná:BAAALgAECgYJBwAAAA==.',
Ma='Maemae:BAAALgAECgcJBwAAAA==.Maggieaugers:BAACLgAFFH8HAAIHAAYJhQI/KwD6AAAHAAYJhQI/KwD6AAAuAAQKfykAAwcACAn3D2EtAGgBAAcACAn3D2EtAGgBAAYABAmPBbMrAHIAAAAA.Magicmech:BAAALgADCgcJDAAAAA==.Magivacano:BAAALgAECggJEgAAAA==.Mahnon:BAABLgAECn8aAAISAAkJowijZgBeAQASAAkJowijZgBeAQAAAA==.Mandril:BAAALgADCgEJAQAAAA==.Matas:BAABLgAECn8UAAIEAAgJDgRTPgDwAAAEAAgJDgRTPgDwAAAAAA==.Matias:BAAALgAECgEJAQAAAA==.Mazzikane:BAAALgAECgMJAwAAAA==.',
Mc='Mcdeath:BAAALgADCgIJAgAAAA==.',
Me='Metalhedface:BAABLgAECn8hAAMNAAgJ4BKRHwBIAQANAAcJBxSRHwBIAQAOAAYJzhNHPgA2AQAAAA==.',
Mi='Miixx:BAAALgAECgQJBQAAAA==.Mikecoxwall:BAACLgAFFH8FAAIBAAIJSgkKkgCPAAABAAIJSgkKkgCPAAAuAAQKfz4AAwEACQmTFdM1ACkCAAEACQmTFdM1ACkCACYABgnfCP0KACoBAAAA.Mikuru:BAAALgAECgEJAwAAAA==.Milena:BAAALgAECgEJAgAAAA==.Milov:BAAALgADCgUJBQAAAA==.Minarva:BAAALgAECgcJCgAAAA==.Misary:BAAALgAECgQJBAAAAA==.Mischeif:BAAALgAECgUJCwAAAA==.',
Mo='Mojomon:BAAALgADCgYJBgAAAA==.Moltganus:BAABLgAECn8hAAIbAAYJHAN+1QCZAAAbAAYJHAN+1QCZAAAAAA==.Monkeli:BAABLgAECn8XAAIOAAcJWhCkOwBBAQAOAAcJWhCkOwBBAQAAAA==.Monkitard:BAAALgAECgMJAwAAAA==.Monkryn:BAAALgAECgUJCAABLgAFFAYJEwAfAAQdAA==.Monkup:BAAALgAFFAEJAQAAAA==.Moocifer:BAAALgAECgEJAQAAAA==.Moocifermoo:BAAALgAECgEJAQAAAA==.Moogrim:BAAALgADCgkJDgAAAA==.Moonsiand:BAACLgAFFH8UAAMUAAUJsgndGADyAAAUAAQJHgPdGADyAAASAAUJGQmjSwDqAAAuAAQKfysABBIACQk3GoMhAEkCABIACQn+FoMhAEkCABQACAleEysOAOYBAAsAAQmqAV+ZABwAAAAA.Moosafur:BAABLgAECn8wAAMMAAkJqSQVAQBMAwAMAAkJqSQVAQBMAwAfAAQJ4APHNQAuAAAAAA==.Mooshoe:BAAALgAECgEJAQAAAA==.Mor:BAAALgADCgUJBQAAAA==.Mordoly:BAAALgAECgYJBgAAAA==.Morphyr:BAAALgAECgYJBgAAAA==.Morrigån:BAAALgAECgIJAgAAAA==.Morvoult:BAAALgAECgEJAQAAAA==.Motgus:BAAALgAECgMJBQAAAA==.',
Ms='Mshottie:BAAALgAECgcJEQAAAA==.Msuysu:BAAALgAECgEJAQABLgAECgEJAwACAAAAAA==.',
Mt='Mtngrounds:BAAALgADCgIJAgAAAA==.',
Mu='Murdaa:BAAALgAECgEJAgAAAA==.Murkt:BAAALgAECgEJAQAAAA==.Mutuusami:BAAALgAECgEJAgAAAA==.',
Mx='Mx:BAAALgAECgYJCAAAAA==.',
My='Myraine:BAAALgAECgMJAwAAAA==.Mythlock:BAAALgAECgMJAwAAAA==.Myway:BAAALgADCggJCwAAAA==.',
Na='Naari:BAABLgAECn8ZAAMOAAcJ/xJPSwACAQAOAAYJwhFPSwACAQANAAEJLxmuYABCAAAAAA==.Naniwa:BAAALgAECgEJAQABLgAFFAMJBwAKANgVAA==.Naoya:BAAALgADCgIJAgAAAA==.Narexia:BAABLgAECn9BAAIeAAkJbx6pAgDaAgAeAAkJbx6pAgDaAgAAAA==.Natureboyy:BAAALgAECgEJAQAAAA==.',
Ne='Nekuma:BAAALgAFFAIJAgABLgAFFAYJGgAWAJ4hAA==.Nellaa:BAAALgAECgcJEAAAAA==.',
Ni='Nightfury:BAAALgAECgcJDQAAAA==.Niklus:BAAALgAECgEJAQAAAA==.Nissanaltima:BAAALgADCgYJCQAAAA==.Nithilis:BAABLgAECn8zAAIIAAkJAR60CACrAgAIAAkJAR60CACrAgAAAA==.',
No='Noee:BAAALgADCgUJBQAAAA==.Nokkiewae:BAAALgADCgcJEgAAAA==.Nomadic:BAAALgADCgkJCQAAAA==.Nool:BAAALgADCgYJBQAAAA==.Nople:BAABLgAECn8fAAIBAAgJGBY4bwCCAQABAAgJGBY4bwCCAQAAAA==.',
Nu='Nutellaa:BAABLgAFFH8FAAIVAAIJmBeDqQCaAAAVAAIJmBeDqQCaAAAAAA==.',
Ny='Nymueline:BAAALgADCgUJBQAAAA==.',
Ob='Obie:BAAALgAECgUJDAAAAA==.Oborax:BAEBLgAECn8oAAIJAAcJnBe2YgCRAQAJAAcJnBe2YgCRAQAAAA==.',
Od='Od:BAAALgAECgYJCAAAAA==.',
Ok='Okiro:BAAALgAECgMJAwAAAA==.Okoru:BAAALgADCgIJAgAAAA==.',
Ol='Oluun:BAAALgADCgQJBAAAAA==.',
Or='Orkun:BAAALgAECgEJAQAAAA==.',
Ot='Otmetka:BAAALgADCgcJAQAAAA==.',
Pa='Palapal:BAAALgAECgYJDgAAAA==.Paldi:BAABLgAECn8WAAIJAAgJORnRKwB0AgAJAAgJORnRKwB0AgABLgAFFAMJBAACAAAAAA==.Papaozz:BAABLgAECn8fAAIgAAcJngYCNgDfAAAgAAcJngYCNgDfAAAAAA==.Parapox:BAAALgAECgEJAgAAAA==.Pariss:BAAALgAECgkJBwAAAA==.Pawcalypse:BAAALgAECgMJAwAAAA==.Paws:BAAALgAECggJEwAAAA==.',
Pe='Perelia:BAABLgAECn83AAIiAAgJSg47HwCwAQAiAAgJSg47HwCwAQAAAA==.Pewpewqt:BAAALgAECgUJBwABLgAECggJNwAQABEXAA==.',
Pi='Piltraja:BAAALgAECgEJAQAAAA==.',
Pl='Plaguehammer:BAABLgAECn8bAAIVAAYJ+Qr1tQD1AAAVAAYJ+Qr1tQD1AAAAAA==.Playstationn:BAAALgADCgUJBQAAAA==.',
Pn='Pnwbambii:BAAALgADCgIJAgAAAA==.',
Po='Polarg:BAAALgAECgEJAQAAAA==.Popcola:BAAALgADCgEJAQABLgAECgUJCAACAAAAAA==.Popopopopopo:BAAALgAFFAQJBAAAAA==.Portholio:BAAALgAECgYJBgAAAA==.',
Pu='Pubbles:BAABLgAECn8XAAQeAAkJ4SBBBgBdAgAeAAgJrCBBBgBdAgAKAAEJ1QmMwAAxAAADAAEJhgwjngAoAAAAAA==.Punizher:BAAALgAECgMJAwAAAA==.Purerage:BAAALgAECgYJDQAAAA==.',
Pv='Pvc:BAAALgAECgYJCQABLgAFFAYJDwAXACIaAA==.',
Py='Pyrella:BAAALgADCgEJAQABLgAECgcJEAACAAAAAA==.Pyyrha:BAAALgAECgMJAwAAAA==.Pyyrhadrood:BAAALgAECgMJAwAAAA==.Pyyrhanice:BAAALgAECgUJDgAAAA==.Pyyrhaspice:BAAALgADCgUJCQAAAA==.',
Qu='Quetzlcoatl:BAAALgADCgcJBwABLgAECggJEAACAAAAAA==.',
Ra='Radiantharm:BAAALgAECgUJDwAAAA==.Raevalinaa:BAAALgAECgQJCAABLgAECggJKgABADAUAA==.Raevelinaa:BAAALgAECgIJBAABLgAECggJKgABADAUAA==.Randzmannz:BAAALgAECgMJAwAAAA==.Raph:BAAALgAECgIJAgAAAA==.Rarelootboss:BAAALgADCgcJDAAAAA==.',
Re='Reason:BAABLgAECn8VAAMQAAgJQxacUgBcAQAQAAcJzhacUgBcAQATAAEJewjrhAArAAAAAA==.Redbaer:BAAALgADCgUJBQAAAA==.Renair:BAAALgADCgMJAwAAAA==.Renoitukax:BAABLgAECn82AAMIAAkJwxuICgCMAgAIAAkJwxuICgCMAgAiAAYJJhtTGADuAQAAAA==.Restorn:BAAALgADCgcJCgAAAA==.Retussy:BAAALgADCgEJAQAAAA==.Reynard:BAABLgAECn8WAAIFAAcJLxEjZABFAQAFAAcJLxEjZABFAQAAAA==.Rezz:BAACLgAFFH8SAAIBAAYJjRHpKQCTAQABAAYJjRHpKQCTAQAuAAQKfyAAAgEACQmQHIgpAM0CAAEACQmQHIgpAM0CAAAA.',
Ri='Ridic:BAAALgADCgMJAwAAAA==.Rigour:BAAALgADCgMJAwAAAA==.',
Ro='Rocketpop:BAAALgADCgIJAgAAAA==.Rosiegirl:BAAALgAECgMJAwAAAA==.Roxas:BAAALgAECgcJDQAAAA==.',
Ry='Ryzen:BAAALgAECgIJAgAAAA==.',
Sa='Salaelana:BAAALgADCgcJCQAAAA==.Saltzpyre:BAAALgADCgYJBAAAAA==.Saninar:BAAALgAECgEJAgAAAA==.',
Sc='Schezmu:BAAALgAECgIJAgAAAA==.Scruffknight:BAAALgAECgcJDQAAAA==.Scrufies:BAACLgAFFH8GAAIgAAMJWwqpIwDeAAAgAAMJWwqpIwDeAAAuAAQKfxoAAiAACAngFScaAK4BACAACAngFScaAK4BAAAA.',
Se='Seisappho:BAAALgADCgMJAwAAAA==.Senorfiesta:BAAALgAECgQJBAAAAA==.Serenade:BAAALgAECgUJBQAAAA==.Serenityboop:BAAALgADCgYJCQAAAA==.Sergnocchi:BAAALgAECgcJEAAAAA==.Serys:BAAALgAECggJCAAAAA==.Sethour:BAAALgADCgQJBAAAAA==.',
Sh='Shaee:BAAALgADCgkJDwAAAA==.Shalthender:BAAALgADCgUJBQAAAA==.Shamans:BAABLgAECn8ZAAIDAAcJ1R6uHADjAQADAAcJ1R6uHADjAQAAAA==.Shamncheese:BAABLgAECn8VAAIKAAcJ+Q08WAA2AQAKAAcJ+Q08WAA2AQABLgAECgUJBgACAAAAAA==.Shamorcc:BAAALgADCgQJBAAAAA==.Shasta:BAACLgAFFH8cAAIMAAUJtyUnAwC8AQAMAAUJtyUnAwC8AQAuAAQKfygAAgwACAlZJW8BAEEDAAwACAlZJW8BAEEDAAAA.Shaulthariel:BAAALgAECgEJAQAAAA==.Shioz:BAAALgADCgQJBgAAAA==.Shisuiuchiha:BAABLgAECn8YAAIBAAcJaQT3zgDTAAABAAcJaQT3zgDTAAAAAA==.Shoiz:BAAALgAECgQJBQAAAA==.Shon:BAAALgAECgEJAQAAAA==.Shootumup:BAAALgAECgkJDwAAAA==.Shootybithc:BAAALgADCgEJAQAAAA==.Shuhari:BAAALgAECgkJEwAAAQ==.Shyx:BAAALgAECgYJDAAAAA==.',
Si='Siilas:BAACLgAFFH8WAAQbAAQJtgjvVgADAQAbAAQJHQfvVgADAQAZAAEJhw+gIABIAAAcAAIJ7QD4JQA3AAAuAAQKfyoAAxsACQljFxUmADgCABsACQljFxUmADgCABwABAlQBwFBALEAAAAA.Simplèjack:BAAALgADCgMJAwABLgAFFAMJBQAKAI8FAA==.Sinamon:BAABLgAECn8xAAIJAAgJGSFCHgB5AgAJAAgJGSFCHgB5AgAAAA==.Sinani:BAABLgAECn8uAAIBAAkJIwUmkQA7AQABAAkJIwUmkQA7AQAAAA==.Sinista:BAAALgAECgUJBQAAAA==.Sinnamon:BAAALgAECgYJEgABLgAECggJMQAJABkhAA==.',
Sj='Sjdh:BAABLgAECn8XAAIFAAcJnBJmYQBNAQAFAAcJnBJmYQBNAQAAAA==.Sjrogue:BAABLgAECn8vAAIgAAgJ+hW9FgDPAQAgAAgJ+hW9FgDPAQAAAA==.',
Sk='Skjolvarn:BAEALgAECgMJBwAAAA==.Skram:BAAALgAECgMJBAAAAA==.',
Sl='Slammydooker:BAABLgAECn8fAAMgAAkJ0hWmEAAQAgAgAAkJ0hWmEAAQAgAhAAEJ1QcMIQAtAAAAAA==.Slammyhole:BAAALgAECgEJAQAAAA==.Sleeptoken:BAAALgAECgMJCAAAAA==.Slyphz:BAAALgAECgYJBgAAAA==.',
Sm='Smallkat:BAAALgAECgEJAQAAAA==.Smightymouse:BAAALgADCgEJAQAAAA==.',
Sn='Snoipuh:BAAALgAECgUJBwAAAA==.',
So='Solas:BAAALgAECgQJBwAAAA==.Soletaken:BAAALgADCggJDwAAAA==.Solio:BAAALgADCgYJFQAAAA==.Solisha:BAAALgADCgkJDgAAAA==.Somberdh:BAAALgADCgcJBwAAAA==.Sonofsand:BAAALgAECgIJAgAAAA==.Soulja:BAAALgADCgEJAgAAAA==.Soulmoethus:BAAALgADCgYJCQAAAA==.',
Sp='Sprayandpray:BAABLgAECn8VAAIBAAUJhBvxjQBBAQABAAUJhBvxjQBBAQAAAA==.Sprinklely:BAAALgADCgcJCgAAAA==.',
Sq='Squidnips:BAAALgADCgEJAgAAAA==.Squirtney:BAAALgADCgMJAwAAAA==.',
Ss='Ss:BAABLgAFFH8MAAIcAAMJjQEgEQCWAAAcAAMJjQEgEQCWAAAAAA==.Ssl:BAAALgADCgQJBAAAAA==.',
St='Starrwood:BAABLgAECn8kAAISAAkJPgn0WwB4AQASAAkJPgn0WwB4AQAAAA==.Statik:BAAALgAECgEJAQAAAA==.Statík:BAAALgAECgEJAQABLgAECgEJAQACAAAAAA==.Stepmonk:BAAALgADCgEJAgAAAA==.Stevesharts:BAAALgADCgYJCwAAAA==.Stonedlock:BAAALgADCgcJCAAAAA==.Stonetusk:BAAALgAECgEJAQAAAA==.Stroya:BAAALgAECgUJBgAAAA==.',
Su='Sumnèr:BAAALgAECgIJAgAAAA==.Sunpali:BAAALgAECgcJCwAAAA==.',
Sw='Swank:BAAALgADCgEJAQAAAA==.',
Sx='Sx:BAAALgADCgIJAgAAAA==.',
Sy='Syaa:BAAALgAECgYJBQAAAA==.Syberis:BAAALgADCgcJDgAAAA==.',
Ta='Tacholy:BAAALgAECggJDAABLgAECgkJLwANAJQcAA==.Tacodaboss:BAAALgAECggJEgAAAA==.Talelarissia:BAAALgADCgQJBAAAAA==.Talonflame:BAABLgAECn8fAAIUAAkJBBy6BwB4AgAUAAkJBBy6BwB4AgAAAA==.Tansu:BAAALgAECgYJEwAAAA==.Tapered:BAAALgAECgUJCAAAAA==.Taupo:BAACLgAFFH8NAAIXAAQJmx7YGABcAQAXAAQJmx7YGABcAQAuAAQKfycAAhcACQlyH6kNAHoCABcACQlyH6kNAHoCAAAA.',
Tb='Tbanger:BAAALgAECgYJDwAAAA==.Tbh:BAAALgAFFAEJAgABLgAFFAYJDwAXACIaAA==.',
Te='Techevo:BAAALgAECgQJBQAAAA==.Techfire:BAABLgAECn8pAAInAAkJ9hqgAQBjAgAnAAkJ9hqgAQBjAgAAAA==.Techsmexx:BAAALgAECgMJBQAAAA==.Tenebron:BAABLgAECn8kAAIoAAYJQBKiIwD6AAAoAAYJQBKiIwD6AAAAAA==.Tenlucis:BAAALgAECgcJCgAAAA==.',
Th='Thaelyssa:BAAALgAECgEJAQAAAA==.Tharria:BAAALgADCgcJBwAAAA==.Thearia:BAABLgAECn8aAAMQAAgJoRSBUgBcAQAQAAgJoRSBUgBcAQATAAUJmg4WTgC3AAAAAA==.Thecanmurk:BAAALgADCgkJEgAAAA==.Thedilf:BAAALgADCgEJAQAAAA==.Thicktotem:BAAALgAECgIJAgAAAA==.Thickumz:BAAALgAECgMJBgAAAA==.Thisismeta:BAAALgAECgIJAgAAAA==.Thorenis:BAAALgADCgEJAQAAAA==.Thoryndruid:BAACLgAFFH8TAAIfAAYJBB1YAQC9AQAfAAYJBB1YAQC9AQAuAAQKfzIAAx8ACQkWIxEDAA4DAB8ACQnmIhEDAA4DAAwABwm8HjgLAA8CAAAA.Thorïn:BAAALgADCgMJAwAAAA==.Thorýn:BAACLgAFFH8PAAIVAAUJ0BteHwCuAQAVAAUJ0BteHwCuAQAuAAQKfxoAAhUACAl8HlUlAFsCABUACAl8HlUlAFsCAAEuAAUUBgkTAB8ABB0A.Thórin:BAABLgAECn8aAAIjAAcJsBc9EgCKAQAjAAcJsBc9EgCKAQAAAA==.',
Ti='Timakk:BAAALgADCgEJAQAAAA==.Tipsy:BAABLgAECn8uAAMKAAkJWg+VMgDNAQAKAAkJWg+VMgDNAQADAAMJpA3oaACNAAAAAA==.',
To='Tombraider:BAAALgAECgMJAwAAAA==.Tomfoolary:BAAALgAECgEJAgAAAA==.Toofy:BAAALgAECgEJAQAAAA==.Tot:BAAALgAECgIJAgAAAA==.Total:BAAALgADCgkJDAAAAA==.Totembear:BAAALgAECgEJAgABLgAECggJCgACAAAAAA==.',
Tr='Tralleth:BAABLgAECn8gAAMHAAgJ/hBfLwBdAQAHAAgJ/hBfLwBdAQAGAAEJGgjIOAAtAAAAAA==.Trid:BAAALgAECgQJBAAAAA==.Trillbilly:BAAALgAECgEJAQAAAA==.Trinora:BAAALgADCgkJDgAAAA==.Trolltard:BAAALgAECgIJAgABLgAECgMJAwACAAAAAA==.Troxa:BAAALgAECgUJCgAAAA==.',
Tu='Tuckard:BAAALgADCgEJAQAAAA==.Tuskor:BAAALgADCgkJDQAAAA==.',
Tw='Twinklord:BAAALgAECggJDgAAAA==.',
Ty='Tylanar:BAAALgAECgYJBgAAAA==.Tylolight:BAAALgADCgMJAwAAAA==.Tylomist:BAAALgAECgUJBQAAAA==.Tylototem:BAAALgAFFAEJAgAAAA==.',
Ug='Uglyboi:BAAALgAECggJDwAAAA==.',
Uj='Ujcmonk:BAAALgAECgQJBAAAAA==.',
Ul='Ullbian:BAAALgADCgMJAwAAAA==.Ultramar:BAAALgADCgEJAQAAAA==.',
Un='Uncookedham:BAAALgAECgQJCwAAAA==.',
Ur='Urgh:BAABLgAECn8fAAIIAAkJ9RG/HgCwAQAIAAkJ9RG/HgCwAQAAAA==.Urk:BAAALgAECgYJBgAAAA==.Urzaa:BAAALgAECgEJAwAAAA==.',
Ut='Uthur:BAAALgAECgMJAwAAAA==.',
Va='Vaeelrundor:BAAALgADCgMJAwAAAA==.Valethales:BAAALgADCgcJBwAAAA==.Vanillaface:BAABLgAECn8XAAIJAAgJQRl6OQAEAgAJAAgJQRl6OQAEAgAAAA==.Vape:BAAALgAECgUJDAABLgAECgkJGgASALkiAA==.',
Ve='Veinripp:BAAALgADCgUJBQABLgAECggJNAAFAO0QAA==.Velarael:BAABLgAECn8aAAIbAAYJlAqlsgDUAAAbAAYJlAqlsgDUAAAAAA==.Velaryn:BAAALgADCgIJAgAAAA==.Veldar:BAAALgADCgIJAgAAAA==.Velekete:BAAALgADCgUJBQAAAA==.Velethei:BAABLgAECn8YAAIQAAYJlySkGQBrAgAQAAYJlySkGQBrAgAAAA==.Velian:BAAALgADCgMJBAAAAA==.Velielyn:BAAALgADCgQJBAAAAA==.Vellareth:BAAALgAECgEJAQAAAA==.Verdesalsa:BAAALgAECgcJDQAAAA==.Verox:BAAALgADCgMJAwAAAA==.',
Vh='Vheckxus:BAABLgAECn8XAAIDAAYJXxIbQgAPAQADAAYJXxIbQgAPAQAAAA==.',
Vi='Vicv:BAABLgAECn8TAAIIAAkJXwwXNABIAQAIAAkJXwwXNABIAQAAAA==.Vivy:BAAALgADCgMJAwAAAA==.',
Vo='Voidberg:BAAALgAECgIJBAAAAA==.',
['Vê']='Vêa:BAAALgADCgkJCQAAAA==.',
Wa='Wachonaso:BAACLgAFFH8QAAIbAAYJRwwIQQAyAQAbAAYJRwwIQQAyAQAuAAQKfy0AAxsABwlJH6M0ADkCABsABwkrH6M0ADkCABwABgl8HlgXAI8BAAAA.Wanbahl:BAAALgADCgMJAwAAAA==.',
We='Wellburt:BAAALgAECgEJAQAAAA==.',
Wh='Whatuphuz:BAAALgADCgQJBQAAAA==.Wheresmyjaw:BAACLgAFFH8aAAQbAAUJ1Bx7MgBVAQAbAAUJ1Bx7MgBVAQAZAAEJTAu6IABIAAAcAAEJOQInJgA1AAAuAAQKfycABBsACAnyIcQTAKMCABsACAnyIcQTAKMCABwAAgm6DiRSAHcAABkAAQnAIL4oAGEAAAAA.',
Wi='Wildstàr:BAAALgADCgMJAwAAAA==.Wildthree:BAABLgAECn8oAAMYAAgJHR6EDQBYAgAYAAgJHR6EDQBYAgAEAAMJ2RQvYgC5AAAAAA==.Willenda:BAAALgAECgEJAgAAAA==.Willowins:BAAALgAECgEJAQAAAA==.Winterstired:BAACLgAFFH8UAAIlAAQJRiZ1BgC+AQAlAAQJRiZ1BgC+AQAuAAQKf0IAAyUACQnuJAQCAIIDACUACQnuJAQCAIIDACIAAQlKFxZjAEUAAAAA.',
Wo='Woen:BAAALgADCggJCQAAAA==.Wolf:BAAALgAECgQJBwAAAA==.Wollffie:BAAALgAECgQJBAAAAA==.',
Wu='Wuinn:BAAALgAFFAEJAQABLgAFFAQJEQAQAJQgAA==.Wut:BAAALgADCgcJBwAAAA==.',
Wy='Wynterswrath:BAAALgAECgYJCwAAAA==.',
['Wõ']='Wõnderful:BAABLgAECn8YAAIQAAYJRxvyLgDWAQAQAAYJRxvyLgDWAQABLgAFFAQJEwAWAPcgAA==.',
Xc='Xclobber:BAAALgADCgIJAgAAAA==.',
Xe='Xemnass:BAAALgAECgUJBwAAAA==.',
Xi='Xillas:BAAALgADCgUJBQAAAA==.',
Xo='Xoverkll:BAAALgAECgYJDAAAAA==.',
Xy='Xylina:BAAALgADCgEJAQAAAA==.Xyrii:BAAALgADCgEJAQAAAA==.',
Ya='Yadder:BAAALgAECgIJBAAAAA==.Yahro:BAACLgAFFH8OAAIJAAQJHA9cPgAYAQAJAAQJHA9cPgAYAQAuAAQKfycAAgkACAnDHqMmAIsCAAkACAnDHqMmAIsCAAAA.Yamelow:BAAALgAECgQJBQAAAA==.',
Ye='Yeahiknow:BAAALgADCgkJDgAAAA==.Yeling:BAAALgAECgEJAQAAAA==.Yep:BAAALgAECgcJBwAAAA==.',
Yi='Yiska:BAAALgADCgcJBwAAAA==.',
Yo='Yoriale:BAAALgAECgYJDgAAAA==.Yotoymuerto:BAAALgAECgMJAwAAAA==.',
Za='Zafra:BAAALgADCgEJAQAAAA==.Zaimara:BAAALgAECgEJBQAAAA==.Zalind:BAABLgAECn8VAAIbAAkJCxJoZgCYAQAbAAkJCxJoZgCYAQAAAA==.Zalvianna:BAABLgAECn8bAAMBAAYJ2gPa8gCbAAABAAYJ0wPa8gCbAAAmAAEJXQHIIgAYAAAAAA==.Zarindlina:BAAALgADCgUJBQAAAA==.Zarshx:BAAALgAECgYJCwABLgAFFAMJBAACAAAAAA==.',
Ze='Zemonk:BAAALgAECgYJBgAAAA==.',
Zi='Zilong:BAAALgAFFAEJAQABLgAFFAUJDwAFAAEaAA==.Zilongmage:BAAALgAFFAIJAwABLgAFFAUJDwAFAAEaAA==.Zilongwar:BAAALgAFFAMJAwABLgAFFAUJDwAFAAEaAA==.Zinnia:BAAALgADCgEJAgAAAA==.',
Zo='Zonedk:BAABLgAECn8WAAQWAAYJfB8hEABAAQAaAAUJQCHcGwBhAQAWAAYJLBYhEABAAQAVAAEJxBcAPAFBAAAAAA==.Zonerg:BAAALgADCgEJAgABLgAECgYJFgAWAHwfAA==.Zordak:BAAALgADCgcJCAAAAA==.Zosin:BAAALgAECgEJAQAAAA==.',
Zu='Zugzugzapzap:BAAALgADCgEJAQAAAA==.',
Zy='Zylphanae:BAAALgAECgQJBAAAAA==.',
['Ør']='Ørsted:BAAALgAECgEJAgABLgAFFAQJDQAXAJseAA==.',
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
