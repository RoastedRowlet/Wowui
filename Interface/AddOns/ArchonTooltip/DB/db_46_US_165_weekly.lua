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

local lookup = {'Mage-Frost','Unknown-Unknown','Shaman-Elemental','Monk-Mistweaver','DemonHunter-Devourer','Evoker-Preservation','Evoker-Augmentation','Priest-Shadow','Paladin-Retribution','Shaman-Restoration','Hunter-Marksmanship','Druid-Guardian','Warrior-Arms','Warrior-Fury','DemonHunter-Vengeance','Druid-Restoration','DemonHunter-Havoc','Hunter-BeastMastery','Druid-Balance','Hunter-Survival','DeathKnight-Unholy','DeathKnight-Frost','Monk-Windwalker','Warlock-Affliction','DeathKnight-Blood','Warlock-Demonology','Warlock-Destruction','Evoker-Devastation','Shaman-Enhancement','Druid-Feral','Rogue-Subtlety','Rogue-Assassination','Priest-Discipline','Paladin-Protection','Paladin-Holy','Priest-Holy','Mage-Arcane','Mage-Fire','Warrior-Protection','Monk-Brewmaster',}
local provider = {region='US',realm='Nazjatar',name='US',type='weekly',zone=46,date='2026-05-23',data={Aa='Aaela:BAAALgADCgUJBQAAAA==.',
Ab='Abrasaxs:BAABLgAECn8qAAIBAAgJQhiESwDdAQABAAgJQhiESwDdAQAAAA==.Absylus:BAAALgAECgQJBAABLgAFFAMJBAACAAAAAA==.',
Ac='Ackerman:BAAALgAECgYJCgABLgAECggJEgACAAAAAA==.Acraea:BAAALgAECggJEAAAAA==.Acslater:BAAALgAECgMJAwAAAA==.Actionman:BAAALgAECgkJBwAAAA==.',
Ag='Agoobagoo:BAACLgAFFH8RAAIDAAQJnSKUDACDAQADAAQJnSKUDACDAQAuAAQKfx8AAgMACQnZIpAEAFIDAAMACQnZIpAEAFIDAAEuAAUUBQkKAAQAvBEA.',
Ai='Aionn:BAAALgAECgMJAwAAAA==.Airrow:BAAALgAECggJEQAAAA==.Aissae:BAACLgAFFH8NAAIFAAQJ7hxKIABoAQAFAAQJ7hxKIABoAQAuAAQKfykAAgUACAlAJHYLACYDAAUACAlAJHYLACYDAAAA.Aiyama:BAAALgADCgQJBAAAAA==.',
Ak='Akiio:BAAALgAECgMJAwAAAA==.Akumaxl:BAAALgAECgYJBwAAAA==.',
Al='Alexia:BAAALgAECgEJAQAAAA==.Alfrank:BAAALgAECgIJAwAAAA==.Aliasx:BAAALgAECgMJAwAAAA==.Alphrank:BAAALgAECgEJAgAAAA==.Alurie:BAAALgAECgUJBgAAAA==.',
Am='Ambros:BAAALgADCgYJBgAAAA==.Aminatou:BAAALgAECgYJBgAAAA==.',
An='Anheeboan:BAAALgAECgYJCwAAAA==.Anihilated:BAAALgADCgYJBwAAAA==.',
Ar='Aradiax:BAAALgADCgYJBgAAAA==.Arcadavia:BAAALgADCgMJAwAAAA==.Ariaprime:BAAALgADCgkJEAAAAA==.Arjentheilus:BAAALgAECgMJAwAAAA==.Arthasl:BAAALgADCgMJAgAAAA==.Arthur:BAAALgAECgQJDAAAAA==.',
As='Asasda:BAAALgADCgMJBAAAAA==.Ashaelra:BAAALgAECgYJCAAAAA==.Astravaritan:BAAALgADCgMJAwAAAA==.',
At='Atherya:BAAALgAECgYJCAAAAA==.Atomixblonde:BAAALgAECgEJAQAAAA==.',
Au='Augonly:BAACLgAFFH8cAAIGAAUJcBj2DQCAAQAGAAUJcBj2DQCAAQAuAAQKfyMAAgYACQnpIC4GAOECAAYACQnpIC4GAOECAAAA.Augy:BAACLgAFFH8IAAIHAAMJPwkgNgC7AAAHAAMJPwkgNgC7AAAuAAQKfxsAAgcACAk1F68aAOABAAcACAk1F68aAOABAAAA.Autoshot:BAAALgAFFAIJAgAAAA==.',
Av='Averisbelia:BAAALgADCgIJAwAAAA==.',
Ay='Ayowamsley:BAAALgADCgMJAwAAAA==.',
Az='Azalea:BAAALgAECggJEAAAAA==.',
Ba='Babycrock:BAAALgADCgYJBgAAAA==.Back:BAAALgADCgcJDAAAAA==.Bakihanma:BAAALgAECgQJBgAAAA==.Balash:BAAALgADCgUJBQAAAA==.Balerion:BAAALgADCgEJAQABLgADCgMJAwACAAAAAA==.Balthasar:BAABLgAECn8dAAIIAAgJxhZHGADgAQAIAAgJxhZHGADgAQAAAA==.Banjobits:BAAALgADCgIJAgAAAA==.Barhead:BAAALgAECgYJDAAAAA==.Barlow:BAAALgAECgcJDgAAAA==.Barqose:BAAALgADCgMJAwAAAA==.Barryberry:BAABLgAECn8fAAIJAAkJDRHBYACQAQAJAAkJDRHBYACQAQAAAA==.Barryx:BAAALgAECgIJAgAAAA==.',
Bb='Bbldrizzy:BAABLgAFFH8FAAIKAAMJjR61KAAGAQAKAAMJjR61KAAGAQAAAA==.',
Be='Beastlieduke:BAAALgADCgUJCQABLgAFFAQJEgAIAKgNAA==.Beastlièduke:BAACLgAFFH8SAAIIAAQJqA34FAAkAQAIAAQJqA34FAAkAQAuAAQKfy4AAggACAnwHvQOAJQCAAgACAnwHvQOAJQCAAAA.Beauslay:BAAALgAECgEJAQAAAA==.Belephon:BAAALgAECgYJEAAAAA==.Bellaruhbz:BAABLgAECn8eAAILAAkJjA9QEwACAQALAAkJjA9QEwACAQAAAA==.Berenstain:BAABLgAECn8mAAIMAAkJrxHNFQBnAQAMAAkJrxHNFQBnAQAAAA==.Bergmire:BAAALgAECgQJCAAAAA==.Berple:BAAALgADCgUJBQABLgAFFAYJFgABANciAA==.Bestoresto:BAABLgAECn8XAAIKAAkJBQxWNwCiAQAKAAkJBQxWNwCiAQAAAA==.',
Bh='Bhori:BAAALgAECgEJAwAAAA==.',
Bi='Bibahabibi:BAABLgAECn8dAAMNAAYJxhuAHQBCAQANAAYJxhuAHQBCAQAOAAMJzQiVhwChAAAAAA==.Bigddk:BAAALgAECgQJBwAAAA==.Bigpapax:BAAALgAECgEJAQAAAA==.Bigtac:BAABLgAECn8vAAMNAAkJlBzYBgBqAgANAAkJlBzYBgBqAgAOAAIJ3gc5mQBcAAAAAA==.Binggus:BAAALgAECgUJCgABLgAECgkJHQAPAEQjAA==.',
Bl='Blabbybootze:BAAALgAECgYJBgAAAA==.Bladelight:BAAALgAECgUJBgAAAA==.Blighte:BAAALgADCgQJBAABLgAECggJIQAQAIIkAA==.Blightfangs:BAABLgAECn8qAAIBAAgJUBWhTQDWAQABAAgJUBWhTQDWAQAAAA==.Blindnautdef:BAABLgAECn8vAAMFAAgJ7RAqWABbAQAFAAgJ7RAqWABbAQARAAEJ9gPwYgAiAAAAAA==.Bloodluna:BAAALgADCgUJBQAAAA==.',
Bo='Bobman:BAAALgAECgEJAQAAAA==.Bodakye:BAABLgAECn8iAAMSAAgJ6RwWMADyAQASAAgJ6RwWMADyAQALAAIJtAEQgQBDAAAAAA==.Bonkz:BAAALgAECgMJAwAAAA==.Boomtip:BAAALgADCgMJAwAAAA==.Boon:BAAALgADCgYJCQAAAA==.Bordolor:BAAALgADCgYJCQAAAA==.Bowsa:BAAALgAECgkJAQAAAA==.',
Br='Brethathes:BAAALgAECgkJEQAAAA==.Brudda:BAAALgADCgUJBQAAAA==.',
Bu='Bubbaray:BAAALgAECgMJAwAAAA==.Bubblebun:BAAALgAECgMJBgAAAA==.Bungerhole:BAABLgAECn8VAAMQAAgJhhpVKgDhAQAQAAgJhhpVKgDhAQATAAEJEQm6gQAmAAAAAA==.Butane:BAAALgADCgIJAgAAAA==.Buzzbuzz:BAAALgAECgIJBAAAAA==.',
Ca='Cainn:BAAALgAECgYJBwAAAA==.Cap:BAAALgADCgEJAQAAAA==.Capriestsun:BAAALgAFFAIJAgAAAA==.Captyn:BAAALgAECgQJBwAAAA==.Carridin:BAAALgADCgMJAwAAAA==.Cass:BAAALgAECgEJAQAAAA==.',
Ce='Cernunon:BAAALgADCgEJAQAAAA==.',
Ch='Chaosdemon:BAABLgAECn8xAAIFAAkJ1Q9LPQCxAQAFAAkJ1Q9LPQCxAQAAAA==.Chapelgnome:BAAALgAECgIJAgABLgAFFAUJBQAHANUCAA==.Charlottea:BAAALgAECgYJDQAAAA==.Chemdra:BAAALgAECgcJEwAAAA==.Chipmonkey:BAAALgAECgEJAgABLgAECggJJgAQAEgPAA==.Chiptime:BAABLgAECn8mAAIQAAgJSA/lPgB0AQAQAAgJSA/lPgB0AQABLgAECggJJgAQAEgPAA==.Chomby:BAAALgAECgQJAwAAAA==.Chriifrio:BAAALgADCgQJBAAAAA==.Chromosomes:BAAALgAECgQJBAAAAA==.Chud:BAAALgAECgQJBwAAAA==.Chudsworth:BAAALgADCgYJCQAAAA==.Chunguhlumpo:BAAALgAECgEJBAAAAA==.Chzburger:BAAALgAECgIJAgAAAA==.',
Ci='Cinnamóróll:BAABLgAECn8kAAIUAAgJdAltIAB5AQAUAAgJdAltIAB5AQAAAA==.',
Cl='Clairity:BAAALgAECgMJAwAAAA==.Cleru:BAABLgAECn8eAAMVAAgJlBKKawBpAQAVAAgJlBKKawBpAQAWAAEJpwMVGgAlAAAAAA==.Cletus:BAAALgADCgcJAgAAAA==.',
Co='Coa:BAAALgAECgkJDAAAAA==.Cocoon:BAABLgAFFH8NAAMEAAUJYRr5EACOAQAEAAUJYRr5EACOAQAXAAEJrA51MABCAAAAAA==.Comanderkush:BAAALgADCgMJAwAAAA==.Coran:BAAALgAECgIJAgABLgAECgkJJAAYAG0bAA==.Corita:BAAALgAECgIJAgAAAA==.Cowboi:BAAALgADCgMJAwAAAA==.Cowhealer:BAABLgAECn8hAAMQAAgJgiRkCAAIAwAQAAgJgiRkCAAIAwATAAEJTwUTgQAvAAAAAA==.',
Cr='Creamypies:BAAALgAECgEJAQAAAA==.Criticaltwo:BAAALgADCgIJAgAAAA==.Crockknight:BAAALgADCgYJBgAAAA==.Crossways:BAAALgAECgYJCQAAAA==.Cræftig:BAAALgAECgEJAQAAAA==.',
Cu='Cursecthree:BAAALgADCgEJAQAAAA==.Cutestxx:BAAALgAECgkJCwAAAA==.',
Cy='Cyxo:BAAALgADCgEJAQABLgAECgEJAQACAAAAAA==.',
Da='Daftxshade:BAAALgAECgYJCwAAAA==.Dandandan:BAAALgADCgMJAwAAAA==.Dapan:BAAALgADCgcJDQAAAA==.Dariaa:BAAALgAECgQJDAAAAA==.Darkcrusader:BAAALgAECgcJEAAAAA==.Darkheal:BAAALgADCgUJBQAAAA==.Darkladie:BAAALgADCgEJAQAAAA==.Darkshadows:BAAALgADCggJFQAAAA==.Darthsyde:BAAALgAECgcJEAAAAA==.Dasdk:BAABLgAFFH8JAAIVAAMJ4RYAZwD9AAAVAAMJ4RYAZwD9AAAAAA==.Daspriest:BAAALgADCgYJDQABLgAFFAMJCQAVAOEWAA==.',
De='Deadergriff:BAAALgAECgcJCwAAAA==.Deadhippycb:BAAALgAECgQJBAAAAA==.Deadhippyxy:BAAALgAECgEJAgAAAA==.Deadicated:BAAALgAECgYJEgAAAA==.Deadsies:BAAALgADCgIJAgABLgAFFAEJAQACAAAAAA==.Deeds:BAAALgAECgMJAwAAAA==.Delan:BAAALgAECgQJBQAAAA==.Delveknight:BAAALgADCgYJBgABLgAECgcJFwAVAHUdAA==.Demoncox:BAAALgADCgMJAgAAAA==.Demondoc:BAABLgAECn8ZAAIFAAgJVxcWLAD5AQAFAAgJVxcWLAD5AQAAAA==.Desunaito:BAACLgAFFH8YAAMWAAUJTSE9AACGAQAWAAUJTSE9AACGAQAZAAEJAABiQgAAAAAuAAQKfy0AAhYACQlUJcUAADgDABYACQlUJcUAADgDAAAA.Devious:BAAALgADCgEJAQAAAA==.',
Dh='Dhzilong:BAACLgAFFH8PAAIFAAUJARodLQAzAQAFAAUJARodLQAzAQAuAAQKfx0AAwUACAlHIU84ABQCAAUACAkzHk84ABQCABEABQmNJJEeAMoBAAAA.',
Di='Diddlefiddle:BAAALgAECgcJEgAAAA==.Dihcum:BAAALgAECgEJBQAAAA==.Dimonologist:BAAALgAECgEJAQAAAA==.Dinpala:BAAALgADCgUJBQABLgAECgYJFwAEAF4XAA==.Dirtycow:BAAALgAECgQJBAAAAA==.',
Dk='Dkzilong:BAAALgAFFAIJBAABLgAFFAUJDwAFAAEaAA==.',
Do='Docholy:BAAALgAECgYJBwABLgAECggJGQAFAFcXAA==.Dockson:BAAALgAECgMJAwAAAA==.Docwyle:BAABLgAECn8XAAMaAAgJnxE9XwBsAQAaAAgJnxE9XwBsAQAbAAEJtgLUcgAzAAABLgAECggJGQAFAFcXAA==.Doobyia:BAAALgADCgEJAQAAAA==.Dorki:BAAALgAECgEJAgAAAA==.Dorlanlemeth:BAAALgAECgYJEAAAAA==.Dormist:BAAALgAECgEJAQABLgAECgkJJAAYAG0bAA==.Dotti:BAAALgAFFAEJAQAAAA==.',
Dr='Dracnogard:BAAALgAECgYJCgAAAA==.Dracowulf:BAABLgAECn8WAAISAAcJchCWXQBfAQASAAcJchCWXQBfAQAAAA==.Dragonx:BAABLgAECn8uAAMSAAgJchHqQwCgAQASAAgJchHqQwCgAQAUAAMJaQ1HPACvAAAAAA==.Drakos:BAAALgAECgEJAQAAAA==.Drakowolf:BAABLgAECn81AAIcAAgJjwT0DgD8AAAcAAgJjwT0DgD8AAAAAA==.Drenz:BAAALgADCgEJAQAAAA==.Dreorge:BAABLgAFFH8GAAIHAAMJcxHrLwDTAAAHAAMJcxHrLwDTAAAAAA==.Dreuceratops:BAAALgAECgMJAwAAAA==.Drewceratops:BAABLgAECn8mAAIJAAkJlBMePADzAQAJAAkJlBMePADzAQAAAA==.Driis:BAAALgADCgcJBwAAAA==.Drimchi:BAABLgAFFH8FAAIHAAMJhBBwMQDNAAAHAAMJhBBwMQDNAAAAAA==.Drizro:BAAALgADCgIJAgAAAA==.Drk:BAAALgAECgEJAQAAAA==.Dromash:BAABLgAECn8kAAMYAAkJbRsbAgCWAgAYAAkJbRsbAgCWAgAbAAgJLhN8CQCBAQAAAA==.Dromgar:BAAALgAFFAEJAgABLgAFFAMJBwAdAAojAA==.Druidyhealz:BAAALgAECgMJAwABLgAECgcJDwACAAAAAA==.',
['Då']='Dårius:BAAALgAECgYJEQAAAA==.',
Ea='Eaterofpaint:BAAALgAECgYJDgAAAA==.',
Ed='Edgeylord:BAAALgAECgEJAQAAAA==.',
Ef='Effloria:BAABLgAECn8kAAIQAAkJ+hyDCgD1AgAQAAkJ+hyDCgD1AgAAAA==.Efrideet:BAAALgADCgEJAQAAAA==.',
El='Elegia:BAACLgAFFH8OAAIaAAUJrw0xRwAVAQAaAAUJrw0xRwAVAQAuAAQKfywAAxoACQlJGyIZAL4CABoACQlJGyIZAL4CABsAAQkAAAdmAEMAAAAA.Elerianor:BAAALgAECgYJEQAAAA==.Ellektra:BAAALgADCgUJBQAAAA==.',
Em='Emadiropilo:BAAALgAECgEJAQAAAA==.Emakaa:BAAALgAECgYJCAAAAA==.Embrohunter:BAAALgAECgQJBAAAAA==.',
En='Enash:BAAALgAECgQJBwAAAA==.Engvald:BAAALgADCgUJBQAAAA==.Enhua:BAAALgADCgUJBQAAAA==.Enjoi:BAAALgAECgEJAQABLgAECgkJFAAFAIYZAA==.',
Er='Eretin:BAAALgADCgEJAQAAAA==.Erismorn:BAABLgAECn8iAAQPAAcJNR5cCwCpAQAPAAYJnBtcCwCpAQAFAAYJiBh1TQB7AQARAAEJ4RAEcAA1AAAAAA==.',
Eu='Eudi:BAAALgAECgEJAgAAAA==.',
Ev='Eventhorizòn:BAAALgAECggJEwAAAA==.Evilhoe:BAAALgADCgUJBQAAAA==.Evocation:BAAALgAECggJEgAAAA==.Evoextoons:BAAALgADCgcJEwAAAA==.',
Fa='Fallen:BAAALgAECgYJEgAAAA==.Fallingvoid:BAABLgAECn9gAAIFAAkJJiQaAgC3AwAFAAkJJiQaAgC3AwAAAA==.Fatchungus:BAAALgAFFAMJBAAAAA==.Fatherben:BAABLgAECn8XAAIFAAYJVBUzbgAgAQAFAAYJVBUzbgAgAQAAAA==.Fatmagus:BAAALgAECgcJBgAAAA==.Favio:BAAALgAECggJCwAAAA==.',
Fe='Fellbian:BAAALgADCgcJCwAAAA==.Fentanyahu:BAAALgAECgYJBgAAAA==.Ferozz:BAACLgAFFH8GAAILAAIJBhDtGgCQAAALAAIJBhDtGgCQAAAuAAQKfzEAAgsACAm7HpgFACECAAsACAm7HpgFACECAAAA.',
Fi='Fiercetaco:BAAALgADCgEJAQAAAA==.Finaliter:BAACLgAFFH8HAAIJAAMJYBQtSADyAAAJAAMJYBQtSADyAAAuAAQKfyoAAgkACQk7INkaAIUCAAkACQk7INkaAIUCAAAA.Finatar:BAAALgADCgcJCwAAAA==.Fiora:BAABLgAECn8SAAIFAAcJKx87KQBdAgAFAAcJKx87KQBdAgAAAA==.Fitz:BAAALgADCgEJAQAAAA==.Fiveyears:BAAALgADCgEJAQAAAA==.',
Fk='Fknutmcgee:BAAALgAECgUJBQAAAA==.',
Fl='Flamingdrago:BAAALgADCgMJBAAAAA==.Flinti:BAAALgAECgUJCQAAAA==.Floggy:BAABLgAECn8dAAIBAAgJDQgtgwBUAQABAAgJDQgtgwBUAQAAAA==.',
Fo='Forsight:BAABLgAECn8YAAIVAAgJUhVgagBsAQAVAAgJUhVgagBsAQAAAA==.',
Fr='Fracker:BAAALgAECgcJCAAAAA==.Frankzzorz:BAACLgAFFH8GAAIEAAMJ2QfqLACaAAAEAAMJ2QfqLACaAAAuAAQKfzQAAwQACQk1HLQMAIcCAAQACQk1HLQMAIcCABcAAglFIA5JALIAAAAA.Fremder:BAACLgAFFH8OAAIGAAMJ/hYvFwDvAAAGAAMJ/hYvFwDvAAAuAAQKfzkAAgYACQmqHK8DAOYCAAYACQmqHK8DAOYCAAAA.Fresher:BAABLgAECn8VAAIVAAUJyxz/lgAUAQAVAAUJyxz/lgAUAQAAAA==.Freyjen:BAAALgADCgkJGAABLgAECgcJCgACAAAAAA==.Froboz:BAAALgADCgYJCQAAAA==.Frogevil:BAAALgAECgYJDQAAAA==.Frogtree:BAAALgADCgUJBQAAAA==.Frostygirl:BAABLgAECn8nAAIBAAgJZhLgWQCzAQABAAgJZhLgWQCzAQAAAA==.Frumentarii:BAAALgAECgQJBAAAAA==.',
Fu='Funeral:BAACLgAFFH8nAAQbAAgJRhlWAgB7AQAbAAUJ/R1WAgB7AQAYAAIJqRaXBgDGAAAaAAMJQxV4MACyAAAuAAQKfzMABBsACQmyIz4EAKECABsABwnSID4EAKECABgABwkrInMDAEsCABoACAn9GOtEAP0BAAAA.',
['Fà']='Fàstïk:BAAALgAECgEJAQAAAA==.',
Ga='Gallory:BAAALgAECgcJDQAAAA==.Gareeshala:BAAALgAECgIJAgAAAA==.',
Gd='Gdkmage:BAAALgAECgkJCQAAAA==.',
Ge='Geomancer:BAAALgADCgQJBAAAAA==.',
Gi='Gimmedatmouf:BAABLgAECn8WAAQQAAgJciHjCAABAwAQAAgJciHjCAABAwAeAAMJph7pIwCwAAATAAQJexa7UQCWAAAAAA==.Gimmedatneck:BAABLgAECn8XAAMfAAgJVSNhGABEAgAfAAgJVSNhGABEAgAgAAEJNhLgHABDAAAAAA==.Gingy:BAAALgAECgEJAQAAAA==.',
Gl='Glead:BAABLgAECn8XAAIOAAgJ3BWNLQD9AQAOAAgJ3BWNLQD9AQAAAA==.',
Gn='Gneeduh:BAAALgAECgIJAwAAAA==.',
Go='Gobknight:BAAALgADCggJCAAAAA==.Goldina:BAAALgAECgEJAQAAAA==.Gooklover:BAAALgAECgQJCQAAAA==.Gosupal:BAAALgADCgYJBgAAAA==.',
Gr='Gracious:BAAALgAECgEJAQAAAA==.Graegor:BAAALgADCgYJBwAAAA==.Grastim:BAAALgAECgUJCgAAAA==.Greenfanta:BAAALgADCgYJEAAAAA==.Grill:BAAALgADCgEJAQAAAA==.Grinkle:BAABLgAECn8rAAIKAAkJIxGCMQC+AQAKAAkJIxGCMQC+AQAAAA==.Gripopotamus:BAAALgADCggJDAAAAA==.Gristle:BAAALgADCgkJJwAAAA==.',
Gu='Gunner:BAAALgAECggJDgAAAA==.',
Ha='Hakaishaz:BAAALgADCgUJBgAAAA==.Halfwatt:BAAALgAECgYJDQAAAA==.Hamaddor:BAAALgAECgYJBgAAAA==.Handen:BAAALgADCggJCAAAAA==.Haraldsson:BAABLgAECn8cAAIJAAgJyRRQWQChAQAJAAgJyRRQWQChAQAAAA==.Harmony:BAAALgADCgcJCgAAAA==.Harrin:BAAALgADCgYJDAAAAA==.Harrydabs:BAABLgAECn8dAAMPAAkJRCNNAACDAwAPAAkJRCNNAACDAwARAAQJJRB3PwD+AAAAAA==.Haru:BAABLgAECn8aAAIUAAgJfxKRFwDGAQAUAAgJfxKRFwDGAQAAAA==.Harvaal:BAAALgAECgUJBQAAAA==.Hasaro:BAACLgAFFH8FAAIMAAIJBhNEGAB6AAAMAAIJBhNEGAB6AAAuAAQKfyUAAgwACQmXGQYHAFQCAAwACQmXGQYHAFQCAAAA.Hashimi:BAAALgAECgcJBwAAAA==.Havokvacano:BAABLgAECn8eAAIJAAgJohQpTADEAQAJAAgJohQpTADEAQAAAA==.',
He='Healmachine:BAAALgAECgYJDQAAAA==.Hellbrringer:BAAALgAECgQJCAAAAA==.Helzerx:BAABLgAECn8YAAIfAAkJExqtCQBmAgAfAAkJExqtCQBmAgABLgAFFAIJAgACAAAAAA==.',
Ho='Hoely:BAAALgAECgEJAQAAAA==.Hogmanjr:BAAALgADCgEJAgAAAA==.Hotsordots:BAAALgAECggJCwAAAA==.Hounskul:BAABLgAECn8gAAIaAAkJogeOaQBSAQAaAAkJogeOaQBSAQAAAA==.',
Hu='Hugealien:BAAALgADCgIJAgAAAA==.Hungchungus:BAAALgAECgEJAgAAAA==.Hungwaylo:BAAALgADCgIJAgAAAA==.',
Hw='Hwere:BAAALgAECgUJBgAAAA==.',
Hy='Hypnoticpal:BAAALgAECgkJBwAAAA==.Hystëria:BAACLgAFFH8PAAMWAAQJwR7QAwB1AQAWAAQJwR7QAwB1AQAVAAMJaRXrewDaAAAuAAQKf0wAAxYACQmQIi8BAA0DABYACQlvIS8BAA0DABUACAlyIBMiAFwCAAAA.Hyunlix:BAAALgADCgUJBQAAAA==.',
Ia='Iammoo:BAAALgAECgYJCwAAAA==.',
Id='Idasie:BAAALgADCgcJBwAAAA==.',
Ig='Igotkappa:BAAALgADCgMJAwAAAA==.Igotyourback:BAAALgAECggJCAAAAA==.',
Il='Ilydris:BAAALgADCgQJBAAAAA==.',
Im='Imadruid:BAAALgADCgQJBAAAAA==.',
Io='Iolyte:BAAALgAECgYJDQAAAA==.',
Ir='Iridellis:BAACLgAFFH8HAAIhAAQJiQStIAD/AAAhAAQJiQStIAD/AAAuAAQKfxsAAiEACQlEC1kgAJwBACEACQlEC1kgAJwBAAAA.',
Is='Ispankutank:BAAALgAECgYJBgAAAA==.',
It='Itssofluffy:BAABLgAECn8sAAQeAAkJzxfpBgA9AgAeAAkJNRfpBgA9AgAMAAUJBhfbEwAyAQATAAIJUgkUfQAqAAAAAA==.Itwon:BAAALgADCgkJIwAAAA==.',
Iz='Izzelda:BAAALgADCgcJCwAAAA==.',
Ja='Jacus:BAAALgAECgQJBwAAAA==.Jahumc:BAAALgAECgEJAQAAAA==.Janeoftrades:BAAALgAECgYJDAAAAA==.Jaycers:BAABLgAECn8iAAQiAAkJ9SCcAwCuAgAiAAkJ8B+cAwCuAgAJAAUJERzZgwBHAQAjAAEJ2AIAnwAqAAAAAA==.Jayclark:BAAALgADCgcJCgAAAA==.',
Je='Jessiriusrex:BAAALgADCgEJAQAAAA==.',
Jo='Joemomma:BAABLgAECn8UAAIBAAYJIw3FsgACAQABAAYJIw3FsgACAQAAAA==.Jokestarfist:BAABLgAECn8ZAAIJAAQJgRgxnAAcAQAJAAQJgRgxnAAcAQAAAA==.',
Jr='Jr:BAAALgADCgMJBAAAAA==.',
Jt='Jtheshadow:BAAALgAECgEJAQAAAA==.',
Ju='Junachan:BAAALgAECgMJBQAAAA==.Jurichan:BAAALgAECgMJCQAAAA==.',
['Jä']='Jägernaut:BAAALgADCgEJAQAAAA==.',
Ka='Kaitokit:BAAALgAFFAEJAQAAAA==.Kajamando:BAABLgAECn8eAAIRAAgJ7wc9JAAbAQARAAgJ7wc9JAAbAQAAAA==.Kalith:BAABLgAECn8YAAIUAAkJCgOAKQAyAQAUAAkJCgOAKQAyAQAAAA==.Kallydots:BAAALgADCgcJDQAAAA==.Kayllina:BAABLgAECn8hAAIVAAgJvwQblwATAQAVAAgJvwQblwATAQAAAA==.Kayotic:BAABLgAECn8gAAIRAAcJ2QR6MQDDAAARAAcJ2QR6MQDDAAAAAA==.Kayww:BAAALgAECgIJAgAAAA==.',
Ke='Keinarra:BAAALgADCgMJBgAAAA==.Kell:BAAALgADCgcJCAAAAA==.Kelmorphic:BAABLgAECn8nAAIPAAkJ2B/NAQDeAgAPAAkJ2B/NAQDeAgAAAA==.Keropikapika:BAAALgADCgUJBQAAAA==.',
Kh='Khaali:BAAALgAECgEJAgAAAA==.Khristina:BAAALgAECgEJAgAAAA==.',
Ki='Kikiana:BAAALgAECgQJCAABLgAECggJLgAkAKQhAA==.Kikstyx:BAAALgADCgYJCAAAAA==.Killerxd:BAABLgAECn8WAAIJAAgJJhgGXwCTAQAJAAgJJhgGXwCTAQAAAA==.Killesea:BAAALgADCgcJDAAAAA==.Kittfisto:BAABLgAECn8iAAQPAAkJmhWQEQAHAQAFAAkJiBStXgCFAQAPAAQJ4BSQEQAHAQARAAYJmAw7KwDpAAAAAA==.',
Kn='Knitemare:BAAALgAECgEJAQAAAA==.',
Ko='Korivos:BAAALgADCgMJAwAAAA==.Kosmas:BAABLgAECn8eAAMOAAgJJiGbGgD1AQAOAAgJ3B6bGgD1AQANAAYJlRx4FACSAQAAAA==.',
Kr='Krushgar:BAABLgAECn8UAAMVAAcJsRcIXQDbAQAVAAcJsRcIXQDbAQAWAAEJsxD7KwAtAAAAAA==.',
Ku='Kuchikopii:BAAALgADCgYJBgAAAA==.Kungfuelf:BAAALgADCgEJAQAAAA==.Kurookami:BAAALgADCgYJBgAAAA==.',
La='Lackluster:BAABLgAECn8fAAIBAAgJTQlNuQBuAQABAAgJTQlNuQBuAQAAAA==.Lamatrick:BAAALgAECgUJBwAAAA==.Lanadelslayy:BAAALgAECgQJBwAAAA==.Lasenza:BAAALgADCgQJBAAAAA==.Lavacoomer:BAAALgADCgYJBQAAAA==.',
Le='Ledana:BAAALgAECgIJAgAAAA==.Lejosh:BAAALgAECgIJAgAAAA==.Lennon:BAAALgAECgkJBgAAAA==.Leona:BAAALgAECgYJCgAAAA==.Lethee:BAAALgAECgEJAgAAAA==.Letusgiveita:BAAALgADCgEJAQAAAA==.',
Li='Lightingbolt:BAAALgAECgUJCgAAAA==.Lightlybaked:BAAALgAFFAEJAQAAAA==.Lilithamy:BAAALgADCgYJBgAAAA==.Lilthin:BAAALgAECgQJCQAAAA==.Liore:BAAALgAECgQJBgAAAA==.Lisathe:BAAALgAECgYJDgAAAA==.Littledude:BAAALgADCgQJBQAAAA==.Littlemorsel:BAABLgAECn8dAAISAAkJNxO1KAARAgASAAkJNxO1KAARAgAAAA==.',
Lo='Louthar:BAAALgADCgcJAQAAAA==.',
Ls='Lselec:BAAALgADCgQJBAAAAA==.',
Lt='Ltdapperdan:BAAALgAECgEJAQAAAA==.',
Lu='Lucens:BAABLgAECn8lAAIjAAcJSBV3IQDSAQAjAAcJSBV3IQDSAQAAAA==.Lunagreed:BAAALgADCgUJBQAAAA==.Lurchn:BAABLgAECn8/AAIBAAkJygxyaACPAQABAAkJygxyaACPAQAAAA==.',
['Lï']='Lïght:BAAALgAFFAEJAQABLgAFFAQJDwAWAMEeAA==.',
['Lú']='Lúná:BAAALgAECgYJBwAAAA==.',
Ma='Maggieaugers:BAACLgAFFH8FAAIHAAUJ1QLALwDUAAAHAAUJ1QLALwDUAAAuAAQKfykAAwcACAn3D+YnAIIBAAcACAn3D+YnAIIBAAYABAmPBWwpAHIAAAAA.Magicmech:BAAALgADCgcJDAAAAA==.Magivacano:BAAALgAECggJEgAAAA==.Mahnon:BAABLgAECn8aAAISAAkJowgWXwBbAQASAAkJowgWXwBbAQAAAA==.Mandril:BAAALgADCgEJAQAAAA==.Matas:BAAALgAECgcJEQAAAA==.Matias:BAAALgAECgEJAQAAAA==.Mazzikane:BAAALgAECgMJAwAAAA==.',
Mc='Mcdeath:BAAALgADCgIJAgAAAA==.',
Me='Metalhedface:BAABLgAECn8aAAMNAAgJaBEVHABOAQANAAcJ5hMVHABOAQAOAAUJFhHAZAAgAQAAAA==.',
Mi='Mikecoxwall:BAABLgAECn81AAMBAAkJ5hTDMwAsAgABAAkJ5hTDMwAsAgAlAAYJ3wj9CgAqAQAAAA==.Mikuru:BAAALgAECgEJAwAAAA==.Milena:BAAALgAECgEJAgAAAA==.Milov:BAAALgADCgUJBQAAAA==.Minarva:BAAALgAECgcJCgAAAA==.Misary:BAAALgAECgQJBAAAAA==.Mischeif:BAAALgAECgUJCwAAAA==.',
Mo='Mojomon:BAAALgADCgYJBgAAAA==.Moltganus:BAABLgAECn8XAAIaAAUJhgPy0QCMAAAaAAUJhgPy0QCMAAAAAA==.Monkeli:BAAALgAECgcJEQAAAA==.Monkitard:BAAALgAECgMJAwAAAA==.Monkryn:BAAALgAECgUJCAABLgAFFAYJEgAeAAQdAA==.Monkup:BAAALgAECgEJAQAAAA==.Moocifer:BAAALgAECgEJAQAAAA==.Moocifermoo:BAAALgAECgEJAQAAAA==.Moogrim:BAAALgADCgkJDgAAAA==.Moonsiand:BAACLgAFFH8UAAMSAAUJsgkxQADrAAAUAAQJHgPrFQD3AAASAAUJGQkxQADrAAAuAAQKfysABBIACQk3GlAdAEwCABIACQn+FlAdAEwCABQACAleEysOAOYBAAsAAQmqAV+ZABwAAAAA.Moosafur:BAABLgAECn8nAAMMAAkJaiQUAQA/AwAMAAkJaiQUAQA/AwAeAAIJeQPHNQAuAAAAAA==.Mooshoe:BAAALgAECgEJAQAAAA==.Mordoly:BAAALgAECgYJBgAAAA==.Morphyr:BAAALgAECgYJBgAAAA==.Morrigån:BAAALgAECgIJAgAAAA==.Morvoult:BAAALgAECgEJAQAAAA==.Motgus:BAAALgAECgMJBQAAAA==.',
Ms='Mshottie:BAAALgAECgcJEQAAAA==.Msuysu:BAAALgAECgEJAQABLgAECgEJAwACAAAAAA==.',
Mt='Mtngrounds:BAAALgADCgIJAgAAAA==.',
Mu='Murdaa:BAAALgADCgMJAwAAAA==.Murkt:BAAALgAECgEJAQAAAA==.Mutuusami:BAAALgAECgEJAgAAAA==.',
Mx='Mx:BAAALgAECgYJCAAAAA==.',
My='Myraine:BAAALgAECgMJAwAAAA==.Myway:BAAALgADCggJCwAAAA==.',
Na='Naari:BAABLgAECn8ZAAMOAAcJ/xLGRQAFAQAOAAYJwhHGRQAFAQANAAEJLxlMVwBCAAAAAA==.Naniwa:BAAALgAECgEJAQABLgAECggJFwAKAN8UAA==.Naoya:BAAALgADCgIJAgAAAA==.Narexia:BAABLgAECn8wAAIdAAcJkhxWCQD1AQAdAAcJkhxWCQD1AQAAAA==.Natureboyy:BAAALgADCgcJDAAAAA==.',
Ne='Nekuma:BAAALgAFFAIJAgABLgAFFAUJGAAWAE0hAA==.Nellaa:BAAALgAECgcJEAAAAA==.',
Ni='Nightfury:BAAALgAECgcJDQAAAA==.Niklus:BAAALgAECgEJAQAAAA==.Nissanaltima:BAAALgADCgYJCQAAAA==.Nithilis:BAABLgAECn8zAAIIAAkJAR6BBwC7AgAIAAkJAR6BBwC7AgAAAA==.',
No='Noee:BAAALgADCgUJBQAAAA==.Nokkiewae:BAAALgADCgcJEgAAAA==.Nomadic:BAAALgADCgkJCQAAAA==.Nool:BAAALgADCgYJBQAAAA==.Nople:BAABLgAECn8fAAIBAAgJGBZ+aACPAQABAAgJGBZ+aACPAQAAAA==.',
Nu='Nutellaa:BAAALgAFFAIJAwAAAA==.',
Ny='Nymueline:BAAALgADCgUJBQAAAA==.',
Ob='Obie:BAAALgAECgUJCAAAAA==.Oborax:BAEBLgAECn8iAAIJAAcJkxe0XgCUAQAJAAcJkxe0XgCUAQAAAA==.',
Od='Od:BAAALgAECgYJCAAAAA==.',
Ok='Okiro:BAAALgAECgMJAwAAAA==.Okoru:BAAALgADCgIJAgAAAA==.',
Ol='Oluun:BAAALgADCgQJBAAAAA==.',
Or='Orkun:BAAALgADCgIJAwAAAA==.',
Ot='Otmetka:BAAALgADCgcJAQAAAA==.',
Pa='Palapal:BAAALgAECgYJDgAAAA==.Paldi:BAABLgAECn8WAAIJAAgJORnRKwB0AgAJAAgJORnRKwB0AgABLgAFFAMJBAACAAAAAA==.Papaozz:BAABLgAECn8YAAIfAAcJngZVMgDfAAAfAAcJngZVMgDfAAAAAA==.Pawcalypse:BAAALgAECgMJAwAAAA==.Paws:BAAALgAECgcJEgAAAA==.',
Pe='Perelia:BAABLgAECn8vAAIhAAgJPA4kHAC/AQAhAAgJPA4kHAC/AQAAAA==.Pewpewqt:BAAALgAECgUJBwABLgAECgcJMAAQACMZAA==.',
Pl='Plaguehammer:BAABLgAECn8bAAIVAAYJ+QpMqQD1AAAVAAYJ+QpMqQD1AAAAAA==.Playstationn:BAAALgADCgUJBQAAAA==.',
Pn='Pnwbambii:BAAALgADCgIJAgAAAA==.',
Po='Polarg:BAAALgAECgEJAQAAAA==.Popcola:BAAALgADCgEJAQABLgAECgEJAQACAAAAAA==.Popopopopopo:BAAALgAFFAQJBAAAAA==.Portholio:BAAALgAECgYJBgAAAA==.',
Pu='Pubbles:BAABLgAECn8UAAMdAAgJrCBhBQBjAgAdAAgJrCBhBQBjAgADAAEJhgzOkQAoAAAAAA==.Punizher:BAAALgAECgMJAwAAAA==.Purerage:BAAALgAECgYJDQAAAA==.',
Pv='Pvc:BAAALgAECgYJCQABLgAFFAUJDQAEAGEaAA==.',
Py='Pyrella:BAAALgADCgEJAQABLgAECgcJEAACAAAAAA==.Pyyrhadrood:BAAALgAECgMJAwAAAA==.Pyyrhanice:BAAALgAECgUJDgAAAA==.Pyyrhaspice:BAAALgADCgUJCQAAAA==.',
Qu='Quetzlcoatl:BAAALgADCgcJBwABLgAECggJDwACAAAAAA==.',
Ra='Radiantharm:BAAALgAECgUJDgAAAA==.Raevalinaa:BAAALgAECgQJCAABLgAECggJJwABAGYSAA==.Raevelinaa:BAAALgAECgIJAwABLgAECggJJwABAGYSAA==.Randzmannz:BAAALgAECgMJAwAAAA==.Raph:BAAALgAECgIJAgAAAA==.Rarelootboss:BAAALgADCgcJDAAAAA==.',
Re='Reason:BAAALgAECgYJEgAAAA==.Redbaer:BAAALgADCgUJBQAAAA==.Renair:BAAALgADCgMJAwAAAA==.Renoitukax:BAABLgAECn8yAAMIAAkJkhmFDABnAgAIAAkJkhmFDABnAgAhAAYJJhvYFgDxAQAAAA==.Restorn:BAAALgADCgcJCgAAAA==.Retussy:BAAALgADCgEJAQAAAA==.Reynard:BAABLgAECn8WAAIFAAcJLxFDXQBNAQAFAAcJLxFDXQBNAQAAAA==.Rezz:BAACLgAFFH8QAAIBAAUJxA2GUAAnAQABAAUJxA2GUAAnAQAuAAQKfyAAAgEACQmQHIgpAM0CAAEACQmQHIgpAM0CAAAA.',
Ri='Ridic:BAAALgADCgMJAwAAAA==.Rigour:BAAALgADCgMJAwAAAA==.',
Ro='Rocketpop:BAAALgADCgIJAgAAAA==.Rosiegirl:BAAALgADCgkJCgAAAA==.Roxas:BAAALgAECgYJBgAAAA==.',
Ry='Ryzen:BAAALgAECgIJAgAAAA==.',
Sa='Salaelana:BAAALgADCgcJCQAAAA==.Saltzpyre:BAAALgADCgYJBAAAAA==.Saninar:BAAALgAECgEJAQAAAA==.',
Sc='Schezmu:BAAALgAECgIJAgAAAA==.Scruffknight:BAAALgAECgYJCgAAAA==.Scrufies:BAABLgAECn8aAAIfAAgJ4BWQFwC3AQAfAAgJ4BWQFwC3AQAAAA==.',
Se='Seisappho:BAAALgADCgMJAwAAAA==.Senorfiesta:BAAALgAECgQJBAAAAA==.Serenade:BAAALgADCgcJBwAAAA==.Serenityboop:BAAALgADCgYJCQAAAA==.Sergnocchi:BAAALgAECgcJEAAAAA==.Serys:BAAALgAECggJCAAAAA==.Sethour:BAAALgADCgQJBAAAAA==.',
Sh='Shaee:BAAALgADCgkJDwAAAA==.Shalthender:BAAALgADCgUJBQAAAA==.Shamans:BAABLgAECn8ZAAIDAAcJ1R7qGQDmAQADAAcJ1R7qGQDmAQAAAA==.Shamncheese:BAABLgAECn8VAAIKAAcJ+Q0zUQA4AQAKAAcJ+Q0zUQA4AQABLgAECgUJBQACAAAAAA==.Shamorcc:BAAALgADCgQJBAAAAA==.Shasta:BAACLgAFFH8XAAIMAAUJ1SP4AgCpAQAMAAUJ1SP4AgCpAQAuAAQKfygAAgwACAlZJW8BAEEDAAwACAlZJW8BAEEDAAAA.Shaulthariel:BAAALgAECgEJAQAAAA==.Shioz:BAAALgADCgQJBgAAAA==.Shisuiuchiha:BAAALgAECgcJEQAAAA==.Shon:BAAALgAECgEJAQAAAA==.Shootumup:BAAALgAECgQJBQAAAA==.Shootybithc:BAAALgADCgEJAQAAAA==.Shuhari:BAAALgAECgkJEwAAAQ==.Shyx:BAAALgAECgEJAQAAAA==.',
Si='Siilas:BAACLgAFFH8SAAQaAAQJtggOUgD4AAAaAAQJlQUOUgD4AAAYAAEJhw/aGgBIAAAbAAIJ7QA0IgA3AAAuAAQKfyoAAxoACQljF2oiAD8CABoACQljF2oiAD8CABsABAlQBwFBALEAAAAA.Simplèjack:BAAALgADCgMJAwABLgAECgkJKwAKACMRAA==.Sinamon:BAABLgAECn8wAAIJAAgJGSHZGwCAAgAJAAgJGSHZGwCAAgAAAA==.Sinani:BAABLgAECn8lAAIBAAkJvgTRnQAkAQABAAkJvgTRnQAkAQAAAA==.Sinista:BAAALgAECgUJBQAAAA==.Sinnamon:BAAALgAECgYJEgABLgAECggJMAAJABkhAA==.',
Sj='Sjdh:BAABLgAECn8XAAIFAAcJnBJrWwBSAQAFAAcJnBJrWwBSAQAAAA==.Sjrogue:BAABLgAECn8nAAIfAAgJ6hNbGwAmAgAfAAgJ6hNbGwAmAgAAAA==.',
Sk='Skjolvarn:BAEALgAECgMJBwAAAA==.Skram:BAAALgAECgMJBAAAAA==.',
Sl='Slammydooker:BAABLgAECn8fAAMfAAkJ0hWeDgAbAgAfAAkJ0hWeDgAbAgAgAAEJ1QcMIQAtAAAAAA==.Slammyhole:BAAALgAECgEJAQAAAA==.Sleeptoken:BAAALgAECgMJCAAAAA==.Slyphz:BAAALgAECgYJBgAAAA==.',
Sm='Smallkat:BAAALgAECgEJAQAAAA==.Smightymouse:BAAALgADCgEJAQAAAA==.',
Sn='Snoipuh:BAAALgAECgUJBwAAAA==.',
So='Solas:BAAALgAECgQJBwAAAA==.Soletaken:BAAALgADCggJDwAAAA==.Solio:BAAALgADCgYJFQAAAA==.Solisha:BAAALgADCgkJCQAAAA==.Somberdh:BAAALgADCgcJBwAAAA==.Sonofsand:BAAALgAECgIJAgAAAA==.Soulja:BAAALgADCgEJAgAAAA==.Soulmoethus:BAAALgADCgYJCQAAAA==.',
Sp='Sprayandpray:BAAALgAECgUJEQAAAA==.Sprinklely:BAAALgADCgcJCgAAAA==.',
Sq='Squidnips:BAAALgADCgEJAgAAAA==.Squirtney:BAAALgADCgMJAwAAAA==.',
Ss='Ss:BAABLgAFFH8JAAIbAAMJUQHmDgCVAAAbAAMJUQHmDgCVAAAAAA==.Ssl:BAAALgADCgQJBAAAAA==.',
St='Starrwood:BAABLgAECn8kAAISAAkJPgmnUwB6AQASAAkJPgmnUwB6AQAAAA==.Statik:BAAALgAECgEJAQAAAA==.Statík:BAAALgAECgEJAQABLgAECgEJAQACAAAAAA==.Stepmonk:BAAALgADCgEJAgAAAA==.Stevesharts:BAAALgADCgYJCwAAAA==.Stonedlock:BAAALgADCgcJCAAAAA==.Stonetusk:BAAALgAECgEJAQAAAA==.Stroya:BAAALgAECgUJBgAAAA==.',
Su='Sumnèr:BAAALgAECgEJAQAAAA==.Sunpali:BAAALgAECgcJCwAAAA==.',
Sw='Swank:BAAALgADCgEJAQAAAA==.',
Sx='Sx:BAAALgADCgIJAgAAAA==.',
Sy='Syaa:BAAALgAECgYJBQAAAA==.Syberis:BAAALgADCgcJDgAAAA==.',
Ta='Tacholy:BAAALgAECgcJCAABLgAECgkJLwANAJQcAA==.Tacodaboss:BAAALgAECgcJEAAAAA==.Talelarissia:BAAALgADCgQJBAAAAA==.Talonflame:BAABLgAECn8fAAIUAAkJBBy6BwB4AgAUAAkJBBy6BwB4AgAAAA==.Tansu:BAAALgAECgYJEwAAAA==.Tapered:BAAALgAECgEJAQAAAA==.Taupo:BAACLgAFFH8JAAIEAAMJIBwsIQDqAAAEAAMJIBwsIQDqAAAuAAQKfycAAgQACQlyH6kNAHoCAAQACQlyH6kNAHoCAAAA.',
Tb='Tbanger:BAAALgAECgYJDwAAAA==.Tbh:BAAALgAFFAEJAgABLgAFFAUJDQAEAGEaAA==.',
Te='Techevo:BAAALgAECgQJBQAAAA==.Techfire:BAABLgAECn8pAAImAAkJ9hpOAQBzAgAmAAkJ9hpOAQBzAgAAAA==.Techsmexx:BAAALgAECgMJBQAAAA==.Tenebron:BAABLgAECn8iAAInAAYJQBKiIQD7AAAnAAYJQBKiIQD7AAAAAA==.Tenlucis:BAAALgAECgcJCgAAAA==.',
Th='Thaelyssa:BAAALgAECgEJAQAAAA==.Tharria:BAAALgADCgcJBwAAAA==.Thearia:BAABLgAECn8aAAMQAAgJoRSBUgBcAQAQAAgJoRSBUgBcAQATAAUJmg6JSAC3AAAAAA==.Thecanmurk:BAAALgADCgkJEgAAAA==.Thedilf:BAAALgADCgEJAQAAAA==.Thicktotem:BAAALgAECgIJAgAAAA==.Thickumz:BAAALgAECgMJBgAAAA==.Thorenis:BAAALgADCgEJAQAAAA==.Thoryndruid:BAACLgAFFH8SAAIeAAYJBB3WAADUAQAeAAYJBB3WAADUAQAuAAQKfzIAAx4ACQkWIxEDAA4DAB4ACQnmIhEDAA4DAAwABwm8Hr4JABECAAAA.Thorïn:BAAALgADCgMJAwAAAA==.Thorýn:BAACLgAFFH8OAAIVAAQJ5xvZMgBeAQAVAAQJ5xvZMgBeAQAuAAQKfxoAAhUACAl8Ht0hAF0CABUACAl8Ht0hAF0CAAEuAAUUBgkSAB4ABB0A.Thórin:BAABLgAECn8WAAIiAAcJsBedEACNAQAiAAcJsBedEACNAQAAAA==.',
Ti='Timakk:BAAALgADCgEJAQAAAA==.Tipsy:BAABLgAECn8qAAMKAAkJWg8+LgDPAQAKAAkJWg8+LgDPAQADAAIJjQxOcwBZAAAAAA==.',
To='Tombraider:BAAALgAECgMJAwAAAA==.Tomfoolary:BAAALgAECgEJAgAAAA==.Toofy:BAAALgAECgEJAQAAAA==.Total:BAAALgADCgkJDAAAAA==.Totembear:BAAALgAECgEJAgABLgAECggJHQAXAGwIAA==.',
Tr='Tralleth:BAABLgAECn8fAAMHAAgJ/hAaKwBtAQAHAAgJ/hAaKwBtAQAGAAEJGgjJNQAtAAAAAA==.Trid:BAAALgAECgQJBAAAAA==.Trillbilly:BAAALgAECgEJAQAAAA==.Trinora:BAAALgADCgkJDgAAAA==.Trolltard:BAAALgAECgIJAgABLgAECgMJAwACAAAAAA==.Troxa:BAAALgAECgUJCgAAAA==.',
Tu='Tuckard:BAAALgADCgEJAQAAAA==.Tuskor:BAAALgADCggJCgAAAA==.',
Tw='Twinklord:BAAALgAECgcJDAAAAA==.',
Ty='Tylolight:BAAALgADCgMJAwAAAA==.Tylomist:BAAALgAECgUJBQAAAA==.Tylototem:BAAALgAFFAEJAgAAAA==.',
Ug='Uglyboi:BAAALgAECggJDwAAAA==.',
Uj='Ujcmonk:BAAALgAECgQJBAAAAA==.',
Ul='Ullbian:BAAALgADCgMJAwAAAA==.Ultramar:BAAALgADCgEJAQAAAA==.',
Un='Uncookedham:BAAALgAECgQJCwAAAA==.',
Ur='Urgh:BAABLgAECn8fAAIIAAkJ9REaHAC+AQAIAAkJ9REaHAC+AQAAAA==.Urk:BAAALgAECgYJBgAAAA==.Urzaa:BAAALgAECgEJAwAAAA==.',
Ut='Uthur:BAAALgAECgMJAwAAAA==.',
Va='Vaeelrundor:BAAALgADCgIJAgAAAA==.Valethales:BAAALgADCgcJBwAAAA==.Vanillaface:BAABLgAECn8XAAIJAAgJQRm0MgAUAgAJAAgJQRm0MgAUAgAAAA==.Vape:BAAALgAECgUJDAABLgAECggJDgACAAAAAA==.',
Ve='Veinripp:BAAALgADCgUJBQAAAA==.Velarael:BAABLgAECn8aAAIaAAYJlAr7qADYAAAaAAYJlAr7qADYAAAAAA==.Velaryn:BAAALgADCgIJAgAAAA==.Veldar:BAAALgADCgIJAgAAAA==.Velekete:BAAALgADCgUJBQAAAA==.Velethei:BAABLgAECn8UAAIQAAYJWCSkGQBrAgAQAAYJWCSkGQBrAgAAAA==.Velian:BAAALgADCgMJBAAAAA==.Velielyn:BAAALgADCgQJBAAAAA==.Verdesalsa:BAAALgAECgYJCwAAAA==.Verox:BAAALgADCgMJAwAAAA==.',
Vh='Vheckxus:BAABLgAECn8XAAIDAAYJXxInPQAQAQADAAYJXxInPQAQAQAAAA==.',
Vi='Vicv:BAABLgAECn8TAAIIAAkJXwwXNABIAQAIAAkJXwwXNABIAQAAAA==.',
Vo='Voidberg:BAAALgAECgEJAQAAAA==.',
['Vê']='Vêa:BAAALgADCgkJCQAAAA==.',
Wa='Wachonaso:BAACLgAFFH8OAAIaAAUJIQ+BTQAFAQAaAAUJIQ+BTQAFAQAuAAQKfy0AAxoABwlJH6M0ADkCABoABwkrH6M0ADkCABsABgl8HlgXAI8BAAAA.Wanbahl:BAAALgADCgMJAwAAAA==.',
We='Wellburt:BAAALgAECgEJAQAAAA==.',
Wh='Whatuphuz:BAAALgADCgQJBQAAAA==.Wheresmyjaw:BAACLgAFFH8VAAMaAAUJaRwWLwBLAQAaAAUJaRwWLwBLAQAYAAEJTAv7GgBIAAAuAAQKfyAAAxoACAmUIKQ5ACUCABoACAmUIKQ5ACUCABsAAgm6DiRSAHcAAAAA.',
Wi='Wildstàr:BAAALgADCgMJAwAAAA==.Wildthree:BAABLgAECn8hAAMXAAgJ+R13DQBHAgAXAAgJ+R13DQBHAgAoAAMJ2RQvYgC5AAAAAA==.Willenda:BAAALgADCgYJBgAAAA==.Willowins:BAAALgAECgEJAQAAAA==.Winterstired:BAACLgAFFH8QAAIkAAQJ1SOmBwCWAQAkAAQJ1SOmBwCWAQAuAAQKf0AAAyQACQmtJLcBAIMDACQACQmtJLcBAIMDACEAAQlKF0JcAEUAAAAA.',
Wo='Woen:BAAALgADCggJCQAAAA==.Wolf:BAAALgAECgQJBwAAAA==.Wollffie:BAAALgAECgQJBAAAAA==.',
Wu='Wuinn:BAAALgAFFAEJAQABLgAFFAQJDgAQAOYRAA==.Wut:BAAALgADCgcJBwAAAA==.',
Wy='Wynterswrath:BAAALgAECgUJCgAAAA==.',
['Wõ']='Wõnderful:BAABLgAECn8YAAIQAAYJRxtGLADVAQAQAAYJRxtGLADVAQABLgAFFAQJDwAWAMEeAA==.',
Xc='Xclobber:BAAALgADCgIJAgAAAA==.',
Xe='Xemnass:BAAALgAECgUJBwAAAA==.',
Xi='Xillas:BAAALgADCgUJBQAAAA==.',
Xo='Xoverkll:BAAALgAECgYJDAAAAA==.',
Xy='Xylina:BAAALgADCgEJAQAAAA==.Xyrii:BAAALgADCgEJAQAAAA==.',
Ya='Yadder:BAAALgAECgIJBAAAAA==.Yahro:BAACLgAFFH8OAAIJAAQJHA97MwAnAQAJAAQJHA97MwAnAQAuAAQKfycAAgkACAnDHqMmAIsCAAkACAnDHqMmAIsCAAAA.',
Ye='Yeahiknow:BAAALgADCgkJDgAAAA==.Yeling:BAAALgAECgEJAQAAAA==.Yep:BAAALgAECgcJBwAAAA==.',
Yi='Yiska:BAAALgADCgcJBwAAAA==.',
Yo='Yoriale:BAAALgAECgYJDgAAAA==.Yotoymuerto:BAAALgAECgMJAwAAAA==.',
Za='Zafra:BAAALgADCgEJAQAAAA==.Zaimara:BAAALgAECgEJBAAAAA==.Zalind:BAABLgAECn8VAAIaAAkJCxJoZgCYAQAaAAkJCxJoZgCYAQAAAA==.Zalvianna:BAAALgAECgYJEgAAAA==.Zarindlina:BAAALgADCgUJBQAAAA==.Zarshx:BAAALgAECgYJCwABLgAFFAMJBAACAAAAAA==.',
Ze='Zemonk:BAAALgAECgYJBgAAAA==.',
Zi='Zilong:BAAALgAFFAEJAQABLgAFFAUJDwAFAAEaAA==.Zilongmage:BAAALgAFFAIJAwABLgAFFAUJDwAFAAEaAA==.Zilongwar:BAAALgAFFAMJAwABLgAFFAUJDwAFAAEaAA==.Zinnia:BAAALgADCgEJAQAAAA==.',
Zo='Zonedk:BAABLgAECn8WAAQZAAYJfB9IGQBlAQAZAAUJQCFIGQBlAQAWAAYJLBYWDgBHAQAVAAEJxBf9JAFCAAAAAA==.Zonerg:BAAALgADCgEJAgABLgAECgYJFgAZAHwfAA==.Zordak:BAAALgADCgcJCAAAAA==.Zosin:BAAALgAECgEJAQAAAA==.',
Zu='Zugzugzapzap:BAAALgADCgEJAQAAAA==.',
Zy='Zylphanae:BAAALgAECgQJBAAAAA==.',
['Ør']='Ørsted:BAAALgADCgEJAQABLgAFFAMJCQAEACAcAA==.',
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
