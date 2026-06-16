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

local lookup = {'Mage-Frost','Unknown-Unknown','Shaman-Elemental','Priest-Discipline','DemonHunter-Devourer','Evoker-Preservation','Evoker-Augmentation','Priest-Shadow','Paladin-Retribution','Shaman-Restoration','Hunter-Marksmanship','Druid-Guardian','Warrior-Arms','Warrior-Fury','Druid-Restoration','DemonHunter-Havoc','Hunter-BeastMastery','Druid-Balance','Paladin-Protection','Hunter-Survival','DeathKnight-Unholy','DeathKnight-Frost','Monk-Mistweaver','Monk-Windwalker','Warlock-Affliction','DeathKnight-Blood','Monk-Brewmaster','Warlock-Demonology','Warlock-Destruction','Evoker-Devastation','Shaman-Enhancement','DemonHunter-Vengeance','Druid-Feral','Rogue-Subtlety','Paladin-Holy','Priest-Holy','Mage-Arcane','Rogue-Assassination','Mage-Fire','Warrior-Protection',}
local provider = {region='US',realm='Nazjatar',name='US',type='weekly',zone=46,date='2026-06-13',data={Aa='Aaela:BAAALgADCgUJBQAAAA==.',
Ab='Abrasaxs:BAABLgAECn8qAAIBAAgJQhgrWADRAQABAAgJQhgrWADRAQAAAA==.Absylus:BAAALgAECgQJBAABLgAFFAMJBAACAAAAAA==.',
Ac='Ackerman:BAAALgAECgYJCgABLgAECggJEgACAAAAAA==.Acraea:BAABLgAECn8hAAIBAAgJmww9ggBwAQABAAgJmww9ggBwAQAAAA==.Acràea:BAAALgAFFAEJAQAAAA==.Acslater:BAAALgAECgMJDAAAAA==.Actionman:BAAALgAECgkJBwAAAA==.',
Ad='Adversary:BAAALgAECgEJAQAAAA==.',
Ag='Agoobagoo:BAACLgAFFH8VAAIDAAUJWCGGDgCzAQADAAUJWCGGDgCzAQAuAAQKfx8AAgMACQnZIpAEAFIDAAMACQnZIpAEAFIDAAAA.',
Ai='Aionn:BAAALgAECgMJAwAAAA==.Airrow:BAABLgAECn8UAAIEAAkJEhmgDwBzAgAEAAkJEhmgDwBzAgAAAA==.Aissae:BAACLgAFFH8OAAIFAAQJ7hxkNgBDAQAFAAQJ7hxkNgBDAQAuAAQKfykAAgUACAlAJHYLACYDAAUACAlAJHYLACYDAAAA.Aiyama:BAAALgADCgQJBAAAAA==.',
Ak='Akiio:BAAALgAECgMJAwAAAA==.Akumaxl:BAAALgAECgYJBwAAAA==.',
Al='Alexia:BAAALgAECgEJAQAAAA==.Alfrank:BAAALgAECgIJAwAAAA==.Aliasx:BAAALgAECgMJBAAAAA==.Allwrong:BAAALgAECgUJBgAAAA==.Alphrank:BAAALgAECgEJAgAAAA==.Alurie:BAAALgAECgUJBgAAAA==.',
Am='Amandrada:BAAALgAECgYJBwAAAA==.Ambros:BAAALgADCgYJBgAAAA==.Aminatou:BAAALgAECgYJBwAAAA==.',
An='Anheeboan:BAAALgAECgYJCwAAAA==.Anihilated:BAAALgADCgYJBwAAAA==.',
Ar='Aradiax:BAAALgADCgYJBgAAAA==.Arcadavia:BAAALgADCgMJAwAAAA==.Ariaprime:BAAALgAECgcJEQAAAA==.Arjentheilus:BAAALgAECgMJAwAAAA==.Armandox:BAAALgAECgEJAQAAAA==.Arthasl:BAAALgADCgMJAgAAAA==.Arthur:BAAALgAECgQJDgAAAA==.',
As='Asasda:BAAALgADCgMJBAAAAA==.Ashaelra:BAAALgAECgYJCAAAAA==.Astravaritan:BAAALgADCgMJAwAAAA==.Astrá:BAAALgAECgUJDQAAAA==.',
At='Atherya:BAAALgAECgYJCAAAAA==.Atomixblonde:BAAALgAECgMJAwAAAA==.',
Au='Augonly:BAACLgAFFH8eAAIGAAcJQxfcCQAFAgAGAAcJQxfcCQAFAgAuAAQKfyMAAgYACQnpIC4GAOECAAYACQnpIC4GAOECAAAA.Augy:BAACLgAFFH8OAAIHAAQJMg3mNADtAAAHAAQJMg3mNADtAAAuAAQKfx0AAwcACQkyGqccAO8BAAcACAnlGKccAO8BAAYAAQmSBBI+ACkAAAAA.Autoshot:BAAALgAFFAIJAgAAAA==.',
Av='Averisbelia:BAAALgAECgYJCwAAAA==.',
Ay='Ayowamsley:BAAALgADCgMJAwAAAA==.',
Az='Azalea:BAAALgAECggJEAAAAA==.',
Ba='Babycrock:BAAALgADCgYJBgAAAA==.Back:BAAALgADCgcJDAAAAA==.Bakihanma:BAAALgAECgQJBgAAAA==.Balash:BAAALgADCgUJBQAAAA==.Balerion:BAAALgADCgEJAQABLgADCgMJAwACAAAAAA==.Balthasar:BAABLgAECn8nAAIIAAkJExonDwBmAgAIAAkJExonDwBmAgAAAA==.Banjobits:BAAALgADCgIJAgAAAA==.Barhead:BAAALgAECgYJDAAAAA==.Barlow:BAAALgAECggJEQAAAA==.Barqose:BAAALgADCgMJAwAAAA==.Barryberry:BAABLgAECn8fAAIJAAkJDRGGewB1AQAJAAkJDRGGewB1AQAAAA==.Barryx:BAAALgAECgIJAgAAAA==.',
Bb='Bbldrizzy:BAABLgAFFH8FAAIKAAMJjR5ROwDuAAAKAAMJjR5ROwDuAAAAAA==.',
Be='Beastlieduke:BAAALgAECgMJAwABLgAFFAYJFgAIAOwOAA==.Beastlièduke:BAACLgAFFH8WAAIIAAYJ7A5JEQBZAQAIAAYJ7A5JEQBZAQAuAAQKfzAAAggACQkfIEIMAIwCAAgACQkfIEIMAIwCAAAA.Beauslay:BAAALgAECgEJAQAAAA==.Belephon:BAAALgAECgYJEAAAAA==.Bellaruhbz:BAABLgAECn8eAAILAAkJjA9YFwD1AAALAAkJjA9YFwD1AAAAAA==.Berenstain:BAABLgAECn8nAAIMAAkJShNUFwCRAQAMAAkJShNUFwCRAQAAAA==.Bergmire:BAAALgAECgQJCgAAAA==.Berple:BAAALgADCgUJBQABLgAFFAgJGQABAK0iAA==.Bestoresto:BAABLgAECn8XAAIKAAkJBQzvQgCeAQAKAAkJBQzvQgCeAQAAAA==.',
Bh='Bhori:BAAALgAECgEJAwAAAA==.',
Bi='Bibahabibi:BAABLgAECn8dAAMNAAYJxhsbJQA5AQANAAYJxhsbJQA5AQAOAAMJzQiVhwChAAAAAA==.Bigpapax:BAAALgAECgEJAQAAAA==.Bigtac:BAABLgAECn8vAAMNAAkJlBwjCQBbAgANAAkJlBwjCQBbAgAOAAIJ3gc5mQBcAAAAAA==.Bimmylee:BAAALgADCgEJAQAAAA==.Binggus:BAAALgAFFAEJAQAAAA==.Bipolaire:BAAALgADCgEJAQAAAA==.',
Bl='Blabbybootze:BAAALgAECggJDgAAAA==.Bladelight:BAAALgAECgYJCAAAAA==.Blighte:BAAALgADCgQJBAABLgAECggJIQAPAIIkAA==.Blightfangs:BAACLgAFFH8GAAIBAAMJZQr2hADVAAABAAMJZQr2hADVAAAuAAQKf0MAAgEACAlCG8szAEcCAAEACAlCG8szAEcCAAAA.Blindnautdef:BAABLgAECn80AAMFAAgJ7RC/aABQAQAFAAgJ7RC/aABQAQAQAAEJ9gOrewAhAAAAAA==.Bloodluna:BAAALgADCgUJBQAAAA==.',
Bo='Bobman:BAAALgAECgUJCAAAAA==.Bodakye:BAACLgAFFH8KAAIRAAMJ8AnZZQDQAAARAAMJ8AnZZQDQAAAuAAQKfyQAAxEACQlBGzEtACQCABEACQlBGzEtACQCAAsAAgm0ARCBAEMAAAAA.Bonargrowrod:BAAALgAECgUJDAAAAA==.Bonkz:BAAALgAECgMJAwAAAA==.Boomtip:BAAALgADCgMJAwAAAA==.Boon:BAAALgADCgYJCQAAAA==.Bordolor:BAAALgAECgEJAQAAAA==.Bowsa:BAAALgAECgkJAQAAAA==.',
Br='Brethathes:BAAALgAECgkJEgAAAA==.Brudda:BAAALgADCgUJBQAAAA==.',
Bu='Bubbaray:BAAALgAECgMJAwAAAA==.Bubblebun:BAAALgAECgMJBgAAAA==.Bungerhole:BAABLgAECn8VAAMPAAgJhhoAMADgAQAPAAgJhhoAMADgAQASAAEJEQmfmAAmAAAAAA==.Butane:BAAALgADCgIJAgAAAA==.Buzzbuzz:BAAALgAECgIJBwAAAA==.',
Ca='Caeruleus:BAAALgAECgEJAQAAAA==.Cainn:BAAALgAECgYJBwAAAA==.Cap:BAAALgADCgEJAQABLgAFFAQJFAABAGIeAA==.Capriestsun:BAAALgAFFAIJAgABLgAFFAMJBQAKAI0eAA==.Captyn:BAABLgAECn8bAAITAAgJug0mGgBEAQATAAgJug0mGgBEAQAAAA==.Carridin:BAAALgADCgMJAwAAAA==.Cass:BAAALgAECgEJAQAAAA==.',
Ce='Cernunon:BAAALgADCgEJAQAAAA==.',
Ch='Chaosdemon:BAABLgAECn81AAIFAAkJPRDiRAC1AQAFAAkJPRDiRAC1AQAAAA==.Chaosraven:BAAALgADCgkJCQAAAA==.Chapelgnome:BAAALgAECgUJCQABLgAFFAYJBwAHAIUCAA==.Charlottea:BAAALgAECgYJDQAAAA==.Chemdra:BAAALgAECgcJEwAAAA==.Chiling:BAAALgAECgEJAQAAAA==.Chipmonkey:BAAALgAECgEJAgABLgAECgkJMQAPAMEPAA==.Chiptime:BAABLgAECn8xAAIPAAkJwQ/iNgC6AQAPAAkJwQ/iNgC6AQABLgAECgkJMQAPAMEPAA==.Chomby:BAAALgAECgQJAwAAAA==.Chriifrio:BAAALgADCgUJBgAAAA==.Chromosomes:BAAALgAECgQJBAAAAA==.Chud:BAAALgAECgQJCQAAAA==.Chudsworth:BAAALgADCgYJCQAAAA==.Chunguhlumpo:BAAALgAECgEJBAAAAA==.Chzburger:BAAALgAECgIJAgAAAA==.',
Ci='Cinnamóróll:BAABLgAECn89AAIUAAkJMhIHEgAaAgAUAAkJMhIHEgAaAgAAAA==.',
Cl='Clairity:BAAALgAECgMJAwAAAA==.Cleru:BAABLgAECn8fAAMVAAgJxhObeQBtAQAVAAgJxhObeQBtAQAWAAEJpwMVGgAlAAAAAA==.Cletus:BAAALgADCgcJAgAAAA==.',
Co='Coa:BAAALgAECgkJDAAAAA==.Cocoon:BAABLgAFFH8QAAMXAAcJdxrXDgARAgAXAAcJdxrXDgARAgAYAAIJ+xYJLACUAAAAAA==.Coldsoul:BAAALgAECgIJAwAAAA==.Comanderkush:BAAALgADCgMJAwAAAA==.Coran:BAAALgAECgIJAwABLgAECgkJJAAZAG0bAA==.Corita:BAAALgAECgIJAgAAAA==.Cowboi:BAAALgADCgMJAwAAAA==.Cowhealer:BAABLgAECn8hAAMPAAgJgiRkCAAIAwAPAAgJgiRkCAAIAwASAAEJTwUTgQAvAAAAAA==.',
Cr='Creamypies:BAAALgAECgEJAQAAAA==.Criticaltwo:BAAALgADCgIJAgAAAA==.Crockknight:BAAALgADCgYJBgAAAA==.Crossways:BAAALgAECgYJCQAAAA==.Cræftig:BAABLgAECn8oAAIBAAgJ2R4PJwB8AgABAAgJ2R4PJwB8AgAAAA==.',
Cu='Cursecthree:BAAALgADCgEJAQAAAA==.Curseword:BAAALgAECgEJAQAAAA==.Cutestxx:BAAALgAECgkJCwAAAA==.',
Cy='Cyxo:BAAALgADCgEJAQABLgAECgEJAQACAAAAAA==.',
Da='Daftxshade:BAAALgAECgYJDwAAAA==.Dandandan:BAAALgADCgMJAwAAAA==.Dapan:BAAALgADCgcJDQAAAA==.Dariaa:BAABLgAECn8UAAIRAAUJew2orQDiAAARAAUJew2orQDiAAAAAA==.Darkcrusader:BAAALgAECgcJEAAAAA==.Darkheal:BAAALgADCgUJBQAAAA==.Darkladie:BAAALgADCgEJAQAAAA==.Darkshadows:BAAALgAECgUJCgAAAA==.Darktank:BAAALgAECgIJAgAAAA==.Darthsyde:BAABLgAECn8bAAIaAAgJ6xIJHAB4AQAaAAgJ6xIJHAB4AQAAAA==.Dasdk:BAABLgAFFH8RAAIVAAQJzCKRNwCGAQAVAAQJzCKRNwCGAQAAAA==.Daspriest:BAAALgADCgYJDQABLgAFFAQJEQAVAMwiAA==.',
De='Deadergriff:BAAALgAECgkJDQAAAA==.Deadhippycb:BAAALgAECgQJBAAAAA==.Deadhippyxy:BAAALgAECgEJAgAAAA==.Deadicated:BAABLgAECn8eAAQbAAcJpQevRQDhAAAbAAcJLAavRQDhAAAYAAYJKAhaXgCbAAAXAAUJaQWIigB8AAAAAA==.Deadsies:BAAALgADCgIJAgABLgAFFAIJAgACAAAAAA==.Deeds:BAAALgAECgMJAwAAAA==.Delan:BAAALgAECgQJBQAAAA==.Delveknight:BAAALgADCgYJBgABLgAECgcJFwAVAHUdAA==.Demoncox:BAAALgADCgMJAgAAAA==.Demondoc:BAACLgAFFH8MAAIFAAQJmgtkWgDZAAAFAAQJmgtkWgDZAAAuAAQKfx8AAgUACAlpFzk0APIBAAUACAlpFzk0APIBAAAA.Desunaito:BAACLgAFFH8dAAMWAAcJEB2/AgDzAQAWAAcJEB2/AgDzAQAaAAEJAABbWQAAAAAuAAQKfy0AAhYACQlUJVkBACoDABYACQlUJVkBACoDAAAA.Devious:BAAALgADCgEJAQAAAA==.',
Dh='Dhzilong:BAACLgAFFH8PAAIFAAUJARrfQwAVAQAFAAUJARrfQwAVAQAuAAQKfx0AAwUACAlHIU84ABQCAAUACAkzHk84ABQCABAABQmNJJEeAMoBAAAA.',
Di='Diddlefiddle:BAACLgAFFH8KAAIUAAUJjSDgCACBAQAUAAUJjSDgCACBAQAuAAQKfxUABBQACAn5H+YIAI8CABQABwn5H+YIAI8CABEAAQkgHGi3AFQAAAsAAgkAHv0zAEoAAAAA.Dihcum:BAAALgAFFAIJBAAAAA==.Dimonologist:BAAALgAECgEJAQAAAA==.Dirtycow:BAAALgAECgQJBAAAAA==.',
Dk='Dkzilong:BAAALgAFFAIJBAABLgAFFAUJDwAFAAEaAA==.',
Do='Docholy:BAAALgAECgYJCAABLgAFFAQJDAAFAJoLAA==.Dockson:BAAALgAECgMJAwAAAA==.Docwyle:BAABLgAECn8XAAMcAAgJnxHUcABYAQAcAAgJnxHUcABYAQAdAAEJtgLUcgAzAAABLgAFFAQJDAAFAJoLAA==.Doobyia:BAAALgADCgEJAQAAAA==.Dorki:BAAALgAECgEJAgAAAA==.Dorlanlemeth:BAABLgAECn8VAAIFAAcJBwxRggAXAQAFAAcJBwxRggAXAQAAAA==.Dormist:BAAALgAECgMJBAABLgAECgkJJAAZAG0bAA==.Dotti:BAAALgAFFAEJAQAAAA==.',
Dr='Dracnogard:BAAALgAECgcJDgAAAA==.Dracowulf:BAABLgAECn8iAAIRAAkJmA9ZPQDnAQARAAkJmA9ZPQDnAQAAAA==.Dragonx:BAABLgAECn8yAAMRAAgJJhOWYwB5AQARAAgJJhOWYwB5AQAUAAMJaQ1VRACtAAAAAA==.Drakos:BAAALgAECgEJAQAAAA==.Drakowolf:BAABLgAECn9FAAIeAAgJFwbaDwAJAQAeAAgJFwbaDwAJAQAAAA==.Drenz:BAAALgADCgEJAQAAAA==.Dreorge:BAABLgAFFH8GAAIHAAMJcxHGPwDDAAAHAAMJcxHGPwDDAAAAAA==.Dreuceratops:BAAALgAECgMJAwAAAA==.Drewceratops:BAABLgAECn8oAAIJAAkJtRTdRAD1AQAJAAkJtRTdRAD1AQAAAA==.Driis:BAAALgADCgcJBwAAAA==.Drimchi:BAABLgAFFH8MAAIHAAQJYhabKgAYAQAHAAQJYhabKgAYAQAAAA==.Drizro:BAAALgADCgIJAgAAAA==.Drk:BAAALgAECgEJAQAAAA==.Drkundead:BAAALgAECgEJAQAAAA==.Dromash:BAABLgAECn8kAAMZAAkJbRt3AwB8AgAZAAkJbRt3AwB8AgAdAAgJLhM4DAB4AQAAAA==.Dromgar:BAAALgAFFAIJBAABLgAFFAMJCAAfAAojAA==.Druidyhealz:BAAALgAECgMJAwABLgAECgcJDwACAAAAAA==.',
Du='Duuke:BAAALgAECgEJAQAAAA==.',
['Då']='Dårius:BAAALgAECgYJEQAAAA==.',
Ea='Eaterofpaint:BAAALgAECgYJDgAAAA==.',
Ed='Edgeylord:BAAALgAECgEJAQABLgAECgMJBAACAAAAAA==.',
Ef='Effloria:BAABLgAECn8lAAIPAAkJEx2hDAD3AgAPAAkJEx2hDAD3AgAAAA==.Efrideet:BAAALgADCgEJAQAAAA==.',
Ei='Eisha:BAAALgADCgUJBQAAAA==.',
El='Elegia:BAACLgAFFH8WAAIcAAUJyBU6RwA1AQAcAAUJyBU6RwA1AQAuAAQKfy8AAxwACQlWGyIZAL4CABwACQlWGyIZAL4CAB0AAQkAAAdmAEMAAAAA.Elerianor:BAAALgAECgYJEgAAAA==.Ellektra:BAAALgADCgUJBQAAAA==.',
Em='Emadiropilo:BAAALgAECgEJAQAAAA==.Emakaa:BAAALgAECgYJCAAAAA==.Embrohunter:BAAALgAECgQJBQAAAA==.',
En='Enash:BAAALgAECgQJBwAAAA==.Engvald:BAAALgADCgUJBQAAAA==.Enhua:BAAALgADCgUJBQAAAA==.Ennet:BAAALgAECgQJBgAAAA==.',
Er='Eretin:BAAALgADCgEJAQAAAA==.Erismorn:BAABLgAECn8iAAQgAAcJNR5cCwCpAQAgAAYJnBtcCwCpAQAFAAYJiBhoWQB4AQAQAAEJ4RAEcAA1AAAAAA==.Erulious:BAAALgADCgIJAgAAAA==.',
Eu='Eudi:BAAALgAECgEJAgAAAA==.',
Ev='Eventhorizòn:BAAALgAECggJEwAAAA==.Evilhoe:BAAALgADCgUJBQAAAA==.Evocation:BAAALgAECggJEgAAAA==.Evoextoons:BAAALgAECgEJAQAAAA==.',
Fa='Fallen:BAABLgAECn8XAAMVAAkJfyTEPAAMAgAVAAkJfyTEPAAMAgAaAAMJ7wvtQwB8AAAAAA==.Fallingvoid:BAABLgAECn9iAAMFAAkJJiUaAgC3AwAFAAkJJiQaAgC3AwAQAAIJpiVANgDeAAAAAA==.Fast:BAAALgAECgEJAgABLgAECgIJAgACAAAAAA==.Fatchungus:BAAALgAFFAMJBAAAAA==.Fatherben:BAABLgAECn8XAAIFAAYJVBVWfgAfAQAFAAYJVBVWfgAfAQAAAA==.Fatmagus:BAAALgAECgcJBgAAAA==.Favio:BAAALgAECggJCwAAAA==.',
Fe='Fellbian:BAAALgADCgcJDgAAAA==.Fentanyahu:BAAALgAECgYJBgAAAA==.Ferozz:BAACLgAFFH8LAAILAAMJSw7MHADBAAALAAMJSw7MHADBAAAuAAQKfzEAAgsACAm7HjUHABICAAsACAm7HjUHABICAAAA.',
Fi='Fiercetaco:BAAALgADCgEJAQAAAA==.Finaliter:BAACLgAFFH8SAAIJAAQJZBquNgA6AQAJAAQJZBquNgA6AQAuAAQKfyoAAgkACQk7IOQkAG8CAAkACQk7IOQkAG8CAAAA.Finatar:BAAALgADCgcJCwAAAA==.Fiora:BAABLgAECn8SAAIFAAcJKx87KQBdAgAFAAcJKx87KQBdAgAAAA==.Fitz:BAAALgADCgEJAQAAAA==.Fiveyears:BAAALgADCgEJAQAAAA==.',
Fk='Fknutmcgee:BAAALgAECgUJBQAAAA==.',
Fl='Flamingdrago:BAAALgAECgMJBAAAAA==.Flinti:BAAALgAECgUJCQAAAA==.Flirtyflurry:BAABLgAECn81AAIBAAgJhBasSQD7AQABAAgJhBasSQD7AQAAAA==.Floggy:BAABLgAECn8eAAIBAAgJNghdmABFAQABAAgJNghdmABFAQAAAA==.',
Fo='Forsight:BAABLgAECn8YAAIVAAgJUhXVfQBlAQAVAAgJUhXVfQBlAQAAAA==.',
Fr='Fracker:BAAALgAECgcJCAAAAA==.Frankzzorz:BAACLgAFFH8IAAIXAAMJZgpaRACHAAAXAAMJZgpaRACHAAAuAAQKfzQAAxcACQk1HLQMAIcCABcACQk1HLQMAIcCABgAAglFIDFXAK8AAAAA.Fremder:BAACLgAFFH8VAAIGAAQJyRXtFgAeAQAGAAQJyRXtFgAeAQAuAAQKfzwAAgYACQmqHKoEANoCAAYACQmqHKoEANoCAAAA.Fresher:BAABLgAECn8VAAIVAAUJyxwdswANAQAVAAUJyxwdswANAQABLgAFFAMJBQAKAI0eAA==.Freyjen:BAAALgADCgkJGAABLgAECgcJCgACAAAAAA==.Froboz:BAAALgADCgYJCQAAAA==.Frogevil:BAAALgAECgcJEQAAAA==.Frogtoad:BAAALgAECgYJBgAAAA==.Frogtree:BAAALgADCgUJBQAAAA==.Frostmoth:BAAALgADCgQJBAABLgAECggJGAAVAFIVAA==.Frumentarii:BAAALgAECgQJBAAAAA==.',
Fu='Funeral:BAACLgAFFH8rAAQdAAgJcBlgBABlAQAdAAUJ/R1gBABlAQAZAAMJOho8BgAZAQAcAAMJQxV4MACyAAAuAAQKfzUABB0ACQnmIz4EAKECAB0ABwnSID4EAKECABkABwmUIpQEAE8CABwACAkxGetEAP0BAAAA.',
['Fà']='Fàstïk:BAAALgAECgEJAQAAAA==.',
Ga='Galladin:BAAALgAECgMJBQABLgAECgYJDQACAAAAAA==.Gallory:BAAALgAECgkJDQAAAA==.Gareeshala:BAAALgAECgIJAgAAAA==.',
Gd='Gdk:BAAALgAECgYJCAAAAA==.Gdkdrake:BAAALgAECgYJBgAAAA==.Gdkmage:BAAALgAECgkJEwAAAA==.Gdkman:BAAALgAECgcJAQAAAA==.',
Ge='Geomancer:BAAALgADCgQJBAAAAA==.',
Gh='Ghadius:BAAALgAECgUJBQAAAA==.',
Gi='Gimmedatmouf:BAABLgAECn8XAAQPAAgJoyHjCAABAwAPAAgJoyHjCAABAwAhAAMJph5xLQCqAAASAAQJexbIXwCUAAABLgAFFAMJBQAKAI0eAA==.Ginga:BAAALgAECgEJAQAAAA==.Gingy:BAAALgAECgUJBgAAAA==.',
Gl='Glead:BAABLgAECn8aAAIOAAkJ6ReNLQD9AQAOAAkJ6ReNLQD9AQAAAA==.Glizzymguire:BAAALgAECggJCAABLgAFFAMJDAAcACQGAA==.',
Gn='Gneeduh:BAAALgAECgIJAwAAAA==.',
Go='Gobknight:BAAALgADCggJCAAAAA==.Goldina:BAAALgAECgEJAQAAAA==.Gooklover:BAAALgAECgQJCQAAAA==.Gosupal:BAAALgADCgYJBgAAAA==.',
Gr='Gracious:BAAALgAECgEJAQAAAA==.Graegor:BAAALgADCgYJBwAAAA==.Grastim:BAAALgAECgUJCgAAAA==.Graylight:BAAALgADCgUJBQAAAA==.Greenfanta:BAAALgADCgYJEAAAAA==.Grill:BAAALgADCgEJAQAAAA==.Grinkle:BAACLgAFFH8FAAIKAAMJjwV3XQCKAAAKAAMJjwV3XQCKAAAuAAQKfysAAgoACQkjEcc7ALsBAAoACQkjEcc7ALsBAAAA.Gripopotamus:BAAALgADCgkJDQAAAA==.Gristle:BAAALgADCgkJJwAAAA==.',
Gu='Guldangg:BAAALgAECgcJEAAAAA==.Gunner:BAACLgAFFH8MAAIRAAUJxhscKgBYAQARAAUJxhscKgBYAQAuAAQKfxsAAhEACQm5InwGACoDABEACQm5InwGACoDAAAA.',
Ha='Hakaishaz:BAAALgADCgUJBgAAAA==.Halfwatt:BAAALgAECgYJDQAAAA==.Hamaddor:BAAALgAECgYJBgAAAA==.Handen:BAAALgADCggJCAAAAA==.Haraldsson:BAABLgAECn8fAAIJAAgJ3hVuVADKAQAJAAgJ3hVuVADKAQAAAA==.Harmony:BAAALgADCgcJCgAAAA==.Harrin:BAAALgADCgYJDAAAAA==.Harrydabs:BAABLgAECn8dAAMgAAkJRCNNAACDAwAgAAkJRCNNAACDAwAQAAQJJRB3PwD+AAABLgAFFAEJAQACAAAAAA==.Haru:BAABLgAECn8lAAIUAAgJHhX3FwDiAQAUAAgJHhX3FwDiAQAAAA==.Harvaal:BAAALgAECgUJBQAAAA==.Hasaro:BAACLgAFFH8LAAIMAAMJuhUgGQC7AAAMAAMJuhUgGQC7AAAuAAQKfysAAgwACQmNG4MHAHgCAAwACQmNG4MHAHgCAAAA.Hashimi:BAAALgAECgcJBwAAAA==.Havokvacano:BAABLgAECn8fAAIJAAkJjxPNRwDsAQAJAAkJjxPNRwDsAQAAAA==.',
He='Healmachine:BAAALgAECgYJEQAAAA==.Hellbrringer:BAABLgAECn8XAAIBAAYJRgy/0QDrAAABAAYJRgy/0QDrAAAAAA==.Helzerx:BAABLgAECn8qAAIiAAkJPB3KBwCqAgAiAAkJPB3KBwCqAgABLgAFFAIJAgACAAAAAA==.Herpstrike:BAAALgAECgIJAwAAAA==.',
Ho='Hoely:BAAALgAECgEJAQAAAA==.Hogmanjr:BAAALgADCgQJBgAAAA==.Holycrappala:BAAALgADCgEJAQAAAA==.Hotsordots:BAAALgAECggJCwAAAA==.Hounskul:BAABLgAECn8gAAIcAAkJogeeewBBAQAcAAkJogeeewBBAQAAAA==.How:BAAALgADCgEJAQABLgAFFAUJDAARAMYbAA==.',
Hu='Hugealien:BAAALgADCgIJAgAAAA==.Hungchungus:BAAALgAECgEJAgAAAA==.Hungwaylo:BAAALgADCgIJAgAAAA==.',
Hw='Hwere:BAAALgAECgUJBgAAAA==.',
Hy='Hypnoticpal:BAAALgAECgkJBwAAAA==.Hystëria:BAACLgAFFH8UAAMWAAUJ9yBgBwBuAQAWAAQJ9yBgBwBuAQAVAAQJaRXPpwDKAAAuAAQKf1IAAxYACQmQI2oBACUDABYACQmhImoBACUDABUACAkJIYsnAGICAAAA.Hyunlix:BAAALgADCgUJBQAAAA==.',
Ia='Iammoo:BAAALgAECgcJEgAAAA==.',
Ic='Ichorus:BAAALgADCgEJAQAAAA==.',
Id='Idasie:BAAALgADCgcJDQAAAA==.',
Ig='Igotkappa:BAAALgADCgMJAwAAAA==.Igotyourback:BAAALgAECggJCAAAAA==.Igriss:BAAALgAECgMJBgAAAA==.',
Il='Ilydris:BAAALgADCgQJBAAAAA==.',
Im='Imadruid:BAAALgADCgQJBAAAAA==.',
Io='Iolyte:BAAALgAECgYJEwAAAA==.',
Ir='Iridellis:BAACLgAFFH8NAAIEAAUJWAdbIgAyAQAEAAUJWAdbIgAyAQAuAAQKfyIAAgQACQn3EvsWABsCAAQACQn3EvsWABsCAAAA.',
Is='Ispankutank:BAAALgAECgYJCgAAAA==.',
It='Itssofluffy:BAABLgAECn8vAAQhAAkJlBhsCABCAgAhAAkJDRhsCABCAgAMAAUJBhfbEwAyAQASAAIJUgktkwAqAAAAAA==.Itwon:BAAALgAECgQJCAAAAA==.',
Iz='Izzelda:BAAALgAECgEJAgAAAA==.',
Ja='Jacus:BAAALgAECgQJCQAAAA==.Jadaruk:BAAALgADCgEJAQAAAA==.Jahumc:BAAALgAECgEJAQAAAA==.Janeoftrades:BAAALgAECgYJDAAAAA==.Jaycers:BAABLgAECn8iAAQTAAkJ9SD3BACjAgATAAkJ8B/3BACjAgAJAAUJERzAmABAAQAjAAEJ2AIAnwAqAAAAAA==.Jayclark:BAAALgADCgcJCgAAAA==.',
Je='Jessiriusrex:BAAALgADCgEJAQAAAA==.',
Jo='Joemomma:BAABLgAECn8UAAIBAAYJIw2fzADzAAABAAYJIw2fzADzAAAAAA==.Jokestarfist:BAABLgAECn8ZAAIJAAQJgRiwugANAQAJAAQJgRiwugANAQAAAA==.',
Jr='Jr:BAAALgADCgYJCgAAAA==.',
Jt='Jtheshadow:BAAALgAECgEJAQAAAA==.',
Ju='Jumpercables:BAAALgAECgUJBQAAAA==.Junachan:BAAALgAECgMJBQAAAA==.Jurichan:BAAALgAECgMJCQAAAA==.',
['Jä']='Jägernaut:BAAALgADCgEJAQAAAA==.',
Ka='Kaitokit:BAAALgAFFAIJAgAAAA==.Kajamando:BAABLgAECn8eAAIQAAgJ7wfFLQAQAQAQAAgJ7wfFLQAQAQAAAA==.Kalith:BAABLgAECn8YAAIUAAkJCgMOMAApAQAUAAkJCgMOMAApAQAAAA==.Kallydots:BAAALgADCgcJDQAAAA==.Kayllina:BAABLgAECn8lAAIVAAgJnwYRoQAnAQAVAAgJnwYRoQAnAQAAAA==.Kayotic:BAABLgAECn8kAAIQAAkJPQaILAAXAQAQAAkJPQaILAAXAQAAAA==.Kayww:BAAALgAECgQJBgAAAA==.',
Ke='Keinarra:BAAALgADCgMJBgAAAA==.Kell:BAAALgADCgcJCAAAAA==.Kelmorphic:BAABLgAECn8tAAMgAAkJMyH1AQDzAgAgAAkJMyH1AQDzAgAQAAEJ7QqabwAsAAAAAA==.Keropikapika:BAAALgADCgUJBQAAAA==.',
Kh='Khaali:BAAALgAECgEJBAAAAA==.Khristina:BAAALgAECgMJBAAAAA==.',
Ki='Kikiana:BAAALgAECgQJCAABLgAECggJLgAkAKQhAA==.Kikstyx:BAAALgADCgYJCAAAAA==.Killerxd:BAABLgAECn8WAAIJAAgJJRgKaQCaAQAJAAgJJRgKaQCaAQAAAA==.Killesea:BAAALgADCgcJDAAAAA==.Kittfisto:BAABLgAECn8iAAQgAAkJmhUJFQACAQAFAAkJiBStXgCFAQAgAAQJ4BQJFQACAQAQAAYJmAy/NQDhAAAAAA==.',
Kn='Knitemare:BAAALgAECgEJAQAAAA==.',
Ko='Korivos:BAAALgADCgMJAwAAAA==.Kosmas:BAABLgAECn8fAAMOAAgJJiF8IADrAQAOAAgJ3B58IADrAQANAAYJlRzyGQCHAQAAAA==.',
Kr='Krushgar:BAABLgAECn8UAAMVAAcJsRcIXQDbAQAVAAcJsRcIXQDbAQAWAAEJsxDGOwAsAAAAAA==.',
Ku='Kuchikopii:BAAALgADCgYJBgAAAA==.Kungfuelf:BAAALgADCgEJAQAAAA==.Kurookami:BAAALgAECgEJAQAAAA==.',
La='Lackluster:BAACLgAFFH8IAAIBAAMJYwEolwCeAAABAAMJYwEolwCeAAAuAAQKfykAAgEACQmuCdGlAC4BAAEACQmuCdGlAC4BAAAA.Lagg:BAAALgAECgIJAwAAAA==.Lamatrick:BAAALgAECgUJBwAAAA==.Lanadelslayy:BAAALgAECgYJDwAAAA==.Lasenza:BAAALgADCgQJBAAAAA==.Lavacoomer:BAAALgADCgYJBQAAAA==.',
Ld='Ldg:BAAALgAECgEJAQAAAA==.',
Le='Ledana:BAAALgAECgIJAgAAAA==.Lejosh:BAAALgAECgIJAgAAAA==.Lennon:BAAALgAECgkJBgAAAA==.Leona:BAAALgAECgYJCgAAAA==.Leonesk:BAAALgADCgQJAwAAAA==.Lethee:BAAALgAECgEJAgAAAA==.Lexazshara:BAAALgAECgEJAgAAAA==.',
Li='Lightingbolt:BAAALgAECgUJDAAAAA==.Lightlybaked:BAAALgAFFAEJAQAAAA==.Lilithamy:BAAALgADCgYJBgAAAA==.Lilthin:BAABLgAECn8bAAIBAAkJBQdDhwBlAQABAAkJBQdDhwBlAQAAAA==.Liore:BAAALgAECgQJBgAAAA==.Lisathe:BAAALgAECgYJEgAAAA==.Lithdrae:BAAALgADCgYJBgAAAA==.Littleddk:BAABLgAECn8UAAIVAAcJYRqBTQDXAQAVAAcJYRqBTQDXAQAAAA==.Littledude:BAAALgADCgQJBQAAAA==.Littlemorsel:BAABLgAECn8eAAIRAAkJNxOfNQACAgARAAkJNxOfNQACAgAAAA==.Livelaughlov:BAAALgAECgEJAQAAAA==.',
Lo='Louthar:BAAALgADCgcJAQAAAA==.',
Ls='Lselec:BAAALgAECgQJBAAAAA==.',
Lt='Ltdapperdan:BAAALgAECgEJAQAAAA==.',
Lu='Lucens:BAABLgAECn8oAAIjAAgJSRO7IAD7AQAjAAgJSRO7IAD7AQAAAA==.Lunagreed:BAAALgADCgUJBQAAAA==.Lurchlock:BAAALgAECgYJBgABLgAFFAIJBgABACsGAA==.Lurchn:BAACLgAFFH8GAAIBAAIJKwazqACFAAABAAIJKwazqACFAAAuAAQKf1QAAgEACQluEZ5aAMoBAAEACQluEZ5aAMoBAAAA.',
Ly='Lysariax:BAAALgAECgMJAwAAAA==.',
['Lï']='Lïght:BAACLgAFFH8FAAIJAAQJWiDNJQBrAQAJAAQJWiDNJQBrAQAuAAQKfxoAAgkACAmEJakMAP4CAAkACAmEJakMAP4CAAEuAAUUBQkUABYA9yAA.',
['Lú']='Lúná:BAAALgAECgYJBwAAAA==.',
Ma='Maemae:BAAALgAECgcJCwAAAA==.Maggieaugers:BAACLgAFFH8HAAIHAAYJhQIbNQDtAAAHAAYJhQIbNQDtAAAuAAQKfykAAwcACAn3D5YvAHcBAAcACAn3D5YvAHcBAAYABAmPBQ4vAG4AAAAA.Magicmech:BAAALgADCgcJDAAAAA==.Magivacano:BAAALgAECggJEgAAAA==.Mahnon:BAABLgAECn8aAAIRAAkJowiLcwBUAQARAAkJowiLcwBUAQAAAA==.Mandril:BAAALgADCgEJAQAAAA==.Matas:BAABLgAECn8WAAIbAAkJxAMMOQAWAQAbAAkJxAMMOQAWAQAAAA==.Matias:BAAALgAECgEJAQAAAA==.Mazzikane:BAAALgAECgMJAwAAAA==.',
Mc='Mcdeath:BAAALgADCgIJAgAAAA==.',
Me='Medzly:BAAALgADCgYJBgAAAA==.Metalhedface:BAABLgAECn8iAAMNAAkJqRLGGQCJAQANAAgJnhPGGQCJAQAOAAYJzhMrRAA0AQAAAA==.',
Mi='Miixx:BAAALgAECgQJBQAAAA==.Mikecoxwall:BAACLgAFFH8HAAIBAAIJSgmjoQCPAAABAAIJSgmjoQCPAAAuAAQKfz4AAwEACQmTFZM7ACkCAAEACQmTFZM7ACkCACUABgnfCP0KACoBAAAA.Mikuru:BAAALgAECgEJAwAAAA==.Milena:BAAALgAECgEJAgAAAA==.Milov:BAAALgADCgUJBQAAAA==.Minarva:BAAALgAECgcJCgAAAA==.Mirazha:BAAALgADCgkJCQAAAA==.Misary:BAAALgAECgQJBQAAAA==.Mischeif:BAAALgAECgUJCwAAAA==.',
Mo='Mojomon:BAAALgADCgYJBgAAAA==.Moltganus:BAABLgAECn8hAAIcAAYJHANV4wCUAAAcAAYJHANV4wCUAAAAAA==.Monkeli:BAABLgAECn8aAAIOAAcJFxFYPgBLAQAOAAcJFxFYPgBLAQAAAA==.Monkitard:BAAALgAECgMJAwAAAA==.Monkryn:BAAALgAECgUJCAABLgAFFAcJEwAVAEAbAA==.Monkup:BAABLgAFFH8KAAIbAAQJtwVsMQDfAAAbAAQJtwVsMQDfAAAAAA==.Moocifer:BAAALgAECgEJAQAAAA==.Moocifermoo:BAAALgAECgEJAgAAAA==.Moogrim:BAAALgADCgkJDgAAAA==.Moonsiand:BAACLgAFFH8XAAMRAAYJcQp0NwA4AQARAAYJ9wl0NwA4AQAUAAQJHgMoHQDjAAAuAAQKfysABBEACQk3Go4nAD0CABEACQn+Fo4nAD0CABQACAleEysOAOYBAAsAAQmqAV+ZABwAAAAA.Moosafur:BAACLgAFFH8FAAIMAAMJwCRnCgBEAQAMAAMJwCRnCgBEAQAuAAQKf0IAAwwACQkMJSoBAFEDAAwACQkMJSoBAFEDACEACQlbGtYHAFMCAAAA.Mooshoe:BAAALgAECgEJAQAAAA==.Mor:BAAALgAECgEJAgAAAA==.Mordoly:BAAALgAECgYJBgAAAA==.Morphyr:BAAALgAECgYJCAAAAA==.Morrigån:BAAALgAECgIJAgAAAA==.Morvoult:BAAALgAECgEJAQAAAA==.Motgus:BAAALgAECgMJBQAAAA==.',
Ms='Mshottie:BAABLgAECn8WAAIJAAgJsgaCvgAIAQAJAAgJsgaCvgAIAQAAAA==.Msuysu:BAAALgAECgEJAQABLgAECgEJAwACAAAAAA==.',
Mt='Mtngrounds:BAAALgADCgIJAgAAAA==.',
Mu='Murdaa:BAAALgAECgMJBAAAAA==.Murkt:BAAALgAECgEJAQAAAA==.Mutuusami:BAAALgAECgEJAgAAAA==.',
Mx='Mx:BAAALgAECgcJDAAAAA==.',
My='Myraine:BAAALgAECgMJAwAAAA==.Mythdath:BAAALgADCgMJAwAAAA==.Mythlock:BAAALgAECgMJAwAAAA==.Myway:BAAALgADCggJCwAAAA==.',
Na='Naari:BAABLgAECn8aAAMOAAgJNxIYQwA4AQAOAAcJDREYQwA4AQANAAEJLxm5bABCAAAAAA==.Naniwa:BAAALgAECgEJAQABLgAFFAMJCgAKANgVAA==.Naoya:BAAALgADCgIJAgAAAA==.Narexia:BAABLgAECn9JAAIfAAkJrR4pAwDWAgAfAAkJrR4pAwDWAgAAAA==.Natureboyy:BAAALgAECgIJAwAAAA==.',
Ne='Nekuma:BAAALgAFFAIJAgABLgAFFAcJHQAWABAdAA==.Nellaa:BAAALgAECgcJEAAAAA==.',
Ni='Nightfury:BAAALgAECgcJDQAAAA==.Nightrage:BAAALgADCgYJBgAAAA==.Niklous:BAAALgAECgEJAQABLgAECgQJBAACAAAAAA==.Niklus:BAAALgAECgEJAQAAAA==.Nissanaltima:BAAALgADCgYJCQAAAA==.Nithilis:BAABLgAECn8zAAIIAAkJAR71CQCvAgAIAAkJAR71CQCvAgAAAA==.',
No='Noee:BAAALgADCgUJBQAAAA==.Nokkiewae:BAAALgADCgcJEgAAAA==.Nomadic:BAAALgADCgkJCQAAAA==.Nool:BAAALgADCgYJBQAAAA==.Nople:BAABLgAECn8fAAIBAAgJGBaseQCCAQABAAgJGBaseQCCAQAAAA==.',
Nu='Nutellaa:BAABLgAFFH8FAAIVAAIJmBdbyQCVAAAVAAIJmBdbyQCVAAAAAA==.',
Ny='Nymueline:BAAALgADCgUJBQAAAA==.',
Ob='Obeastly:BAAALgADCgEJAQAAAA==.Obie:BAAALgAECgUJEQAAAA==.Oborax:BAECLgAFFH8OAAIJAAUJuQwFTwALAQAJAAUJuQwFTwALAQAuAAQKfygAAgkABwmcF2duAI8BAAkABwmcF2duAI8BAAAA.',
Od='Od:BAAALgAECgYJCAAAAA==.',
Ok='Okiro:BAAALgAECgMJAwAAAA==.Okoru:BAAALgADCgIJAgAAAA==.',
Ol='Oliviabenson:BAAALgAFFAEJAQAAAA==.Oluun:BAAALgADCgQJBAAAAA==.',
Or='Orkun:BAAALgAECgEJAQAAAA==.',
Ot='Otmetka:BAAALgADCgcJAQAAAA==.',
Ow='Owensbeast:BAAALgADCgUJBQAAAA==.',
Pa='Palapal:BAAALgAECgYJDgAAAA==.Paldi:BAABLgAECn8WAAIJAAgJORnRKwB0AgAJAAgJORnRKwB0AgABLgAFFAMJBAACAAAAAA==.Papaozz:BAABLgAECn8qAAIiAAcJ9Q2RJwBVAQAiAAcJ9Q2RJwBVAQAAAA==.Parapox:BAAALgAECgEJAgAAAA==.Pariss:BAAALgAECgkJBwAAAA==.Pawcalypse:BAAALgAECgMJAwAAAA==.Paws:BAABLgAECn8XAAISAAkJGA1oJQCdAQASAAkJGA1oJQCdAQAAAA==.',
Pe='Perelia:BAABLgAECn9IAAIEAAkJ/w2rHADmAQAEAAkJ/w2rHADmAQAAAA==.Pewpewqt:BAAALgAECgUJBwABLgAECggJOQAPABEXAA==.',
Pi='Piltraja:BAAALgAECgEJAgAAAA==.',
Pl='Plaguehammer:BAABLgAECn8bAAIVAAYJ+QozxwDxAAAVAAYJ+QozxwDxAAAAAA==.Playstationn:BAAALgADCgUJBQAAAA==.',
Pn='Pnwbambii:BAAALgADCgIJAgAAAA==.',
Po='Polarg:BAAALgAECgEJAgAAAA==.Popcola:BAAALgADCgEJAQABLgAECgUJCQACAAAAAA==.Popopopopopo:BAAALgAFFAQJBAAAAA==.Portholio:BAAALgAECgYJBgAAAA==.',
Pp='Ppc:BAAALgAFFAEJAQABLgAFFAcJEAAXAHcaAA==.',
Pu='Pubbles:BAABLgAECn8XAAQfAAkJ4SBDBwBWAgAfAAgJrCBDBwBWAgAKAAEJ1Qkx1AAxAAADAAEJhgwWrgAoAAAAAA==.Punizher:BAAALgAECgMJAwAAAA==.Purerage:BAAALgAECgYJDQAAAA==.',
Pv='Pvc:BAAALgAECgYJCQABLgAFFAcJEAAXAHcaAA==.',
Py='Pyrella:BAAALgADCgEJAQABLgAECgcJEAACAAAAAA==.Pyyrha:BAAALgAECgMJAwAAAA==.Pyyrhadrood:BAAALgAECgMJAwAAAA==.Pyyrhanice:BAAALgAECgUJDgAAAA==.Pyyrhaspice:BAAALgADCgUJCQAAAA==.',
Qu='Quetzlcoatl:BAAALgADCgcJBwABLgAECgkJEgACAAAAAA==.',
Ra='Radiantharm:BAAALgAECgUJDwAAAA==.Raevalinaa:BAAALgAECgQJCgABLgAECggJNQABAIQWAA==.Raevelinaa:BAAALgAECgQJBwABLgAECggJNQABAIQWAA==.Rafeh:BAAALgAECgIJAgAAAA==.Randzmannz:BAAALgAECgMJAwAAAA==.Raph:BAAALgAECgIJAgAAAA==.Rarelootboss:BAAALgADCgcJDAAAAA==.',
Re='Reason:BAABLgAECn8VAAMPAAgJQxacUgBcAQAPAAcJzhacUgBcAQASAAEJewgFkQArAAAAAA==.Redbaer:BAAALgADCgUJBQAAAA==.Renair:BAAALgADCgMJAwAAAA==.Renoitukax:BAABLgAECn82AAMIAAkJwxsODACPAgAIAAkJwxsODACPAgAEAAYJJhsYHADqAQAAAA==.Restorn:BAAALgADCgcJCgAAAA==.Retrobution:BAAALgAECgEJAgAAAA==.Retussy:BAAALgADCgEJAQAAAA==.Reynard:BAABLgAECn8WAAIFAAcJLxFObABHAQAFAAcJLxFObABHAQAAAA==.Rezz:BAACLgAFFH8SAAIBAAYJjRFzOACLAQABAAYJjRFzOACLAQAuAAQKfyAAAgEACQmQHIgpAM0CAAEACQmQHIgpAM0CAAAA.',
Ri='Ridic:BAAALgADCgMJAwAAAA==.Rigour:BAAALgADCgMJAwAAAA==.Rivers:BAABLgAECn8UAAINAAcJhQoTNADxAAANAAcJhQoTNADxAAAAAA==.',
Ro='Rocketpop:BAAALgADCgIJAgAAAA==.Rosiegirl:BAAALgAECgMJAwAAAA==.Roxas:BAAALgAECgcJDQAAAA==.',
Ry='Ryzen:BAAALgAECgIJAgAAAA==.',
Sa='Salaelana:BAAALgADCgcJCQAAAA==.Saltzpyre:BAAALgADCgYJBAAAAA==.Saninar:BAAALgAECgEJAgAAAA==.Sausagepizza:BAAALgADCgYJAwAAAA==.',
Sc='Schezmu:BAAALgAECgIJAgAAAA==.Scruffknight:BAAALgAECgcJDQAAAA==.Scrufies:BAACLgAFFH8NAAIiAAQJ4RLtGQBBAQAiAAQJ4RLtGQBBAQAuAAQKfx0AAiIACQmbFlkTAAYCACIACQmbFlkTAAYCAAAA.',
Se='Seisappho:BAAALgADCgMJAwAAAA==.Senorfiesta:BAAALgAECgQJBAAAAA==.Serenade:BAAALgAECgcJEQAAAA==.Serenityboop:BAAALgADCgYJCQAAAA==.Sergnocchi:BAAALgAECgcJEAAAAA==.Serys:BAAALgAECggJEAAAAA==.Sethour:BAAALgADCgQJBAAAAA==.',
Sh='Shaee:BAAALgADCgkJDwAAAA==.Shalthender:BAAALgADCgUJBQAAAA==.Shamans:BAABLgAECn8dAAIDAAcJLx8rHAD9AQADAAcJLx8rHAD9AQAAAA==.Shamncheese:BAABLgAECn8VAAIKAAcJ+Q22YAA0AQAKAAcJ+Q22YAA0AQABLgAECgUJDQACAAAAAA==.Shamorcc:BAAALgADCgQJBAAAAA==.Shasta:BAACLgAFFH8fAAIMAAYJSCVeAgAaAgAMAAYJSCVeAgAaAgAuAAQKfygAAgwACAlZJW8BAEEDAAwACAlZJW8BAEEDAAAA.Shaulthariel:BAAALgAECgEJAQAAAA==.Shioz:BAAALgADCgQJBgAAAA==.Shisuiuchiha:BAABLgAECn8fAAIBAAcJpQWFzADzAAABAAcJpQWFzADzAAAAAA==.Shoiz:BAAALgAECgQJBQAAAA==.Shon:BAAALgAECgEJAQAAAA==.Shootumup:BAAALgAECgkJEQAAAA==.Shootybithc:BAAALgADCgEJAQAAAA==.Shuhari:BAAALgAECgkJEwAAAQ==.Shyx:BAABLgAECn8lAAIEAAgJ1Rh3EQBaAgAEAAgJ1Rh3EQBaAgAAAA==.',
Si='Siilas:BAACLgAFFH8aAAQcAAQJNgmzYwD6AAAcAAQJnQezYwD6AAAZAAEJhw9MKABEAAAdAAIJ7QBGKwA2AAAuAAQKfyoAAxwACQljFwIqADACABwACQljFwIqADACAB0ABAlQBwFBALEAAAAA.Sinamon:BAABLgAECn8xAAIJAAgJGSHxIwBzAgAJAAgJGSHxIwBzAgAAAA==.Sinani:BAABLgAECn83AAIBAAkJFAcyhgBnAQABAAkJFAcyhgBnAQAAAA==.Sinista:BAAALgAECgUJBQAAAA==.Sinnamon:BAAALgAECgYJEgABLgAECggJMQAJABkhAA==.',
Sj='Sjdh:BAABLgAECn8XAAIFAAcJnBJvagBMAQAFAAcJnBJvagBMAQAAAA==.Sjrogue:BAABLgAECn8xAAIiAAkJMBTwEgAKAgAiAAkJMBTwEgAKAgAAAA==.',
Sk='Skjolvarn:BAEALgAECgMJBwAAAA==.Skram:BAAALgAECgMJBAAAAA==.',
Sl='Slammydooker:BAABLgAECn8fAAMiAAkJ0hX5EgAKAgAiAAkJ0hX5EgAKAgAmAAEJ1QcMIQAtAAAAAA==.Slammyhole:BAAALgAECgEJAQAAAA==.Sleeptoken:BAAALgAECgMJCAAAAA==.Slyphz:BAAALgAECgYJBgAAAA==.',
Sm='Smallkat:BAAALgAECgEJAQAAAA==.Smightymouse:BAAALgADCgEJAQAAAA==.',
Sn='Snoipuh:BAAALgAECgUJBwAAAA==.',
So='Solas:BAAALgAECgQJBwAAAA==.Soletaken:BAAALgADCggJDwAAAA==.Solio:BAAALgADCgYJFQAAAA==.Solisha:BAAALgAECgEJAQAAAA==.Somberdh:BAAALgADCgcJBwAAAA==.Sonofsand:BAAALgAECgIJAgAAAA==.Soulja:BAAALgADCgEJAgAAAA==.Soulmoethus:BAAALgADCgYJCQAAAA==.',
Sp='Sprayandpray:BAABLgAECn8ZAAIBAAUJqh3OjABaAQABAAUJqh3OjABaAQAAAA==.Sprinklely:BAAALgADCgcJCgAAAA==.',
Sq='Squidnips:BAAALgAECgEJAQAAAA==.Squirtney:BAAALgADCgMJAwAAAA==.',
Ss='Ss:BAACLgAFFH8PAAIdAAMJjQGtFACTAAAdAAMJjQGtFACTAAAuAAQKfxUAAh0ABwlxDGoWAO0AAB0ABwlxDGoWAO0AAAAA.Ssl:BAAALgADCgQJBAAAAA==.',
St='Starrwood:BAABLgAECn8kAAIRAAkJPgnWZwBuAQARAAkJPgnWZwBuAQAAAA==.Statik:BAAALgAECgIJAwAAAA==.Statík:BAAALgAECgEJAQABLgAECgIJAwACAAAAAA==.Stepmonk:BAAALgAECgEJAQAAAA==.Stevesharts:BAAALgADCgYJCwAAAA==.Stonedlock:BAAALgADCgcJCAAAAA==.Stonetusk:BAAALgAECgUJCAAAAA==.Stroya:BAAALgAECgUJBgAAAA==.',
Su='Sumnèr:BAAALgAECgcJBwAAAA==.Sunastiri:BAAALgADCgkJCQAAAA==.Sunpali:BAAALgAECgcJCwAAAA==.',
Sw='Swank:BAAALgADCgEJAQAAAA==.',
Sx='Sx:BAAALgADCgIJAgAAAA==.',
Sy='Syaa:BAAALgAECgYJBQAAAA==.Syberis:BAAALgADCgcJDgAAAA==.',
Ta='Tacholy:BAABLgAECn8VAAIJAAkJzBfeZgCfAQAJAAkJzBfeZgCfAQABLgAECgkJLwANAJQcAA==.Tacodaboss:BAABLgAECn8XAAIQAAYJLw+ZMgD0AAAQAAYJLw+ZMgD0AAAAAA==.Talelarissia:BAAALgADCgQJBAAAAA==.Talonflame:BAABLgAECn8fAAIUAAkJBBy6BwB4AgAUAAkJBBy6BwB4AgAAAA==.Tansu:BAAALgAECgYJEwAAAA==.Tapered:BAAALgAECgUJCQAAAA==.Taupo:BAACLgAFFH8VAAIXAAQJ6x8NIABfAQAXAAQJ6x8NIABfAQAuAAQKfycAAhcACQlyH6kNAHoCABcACQlyH6kNAHoCAAAA.',
Tb='Tbanger:BAAALgAECgYJDwAAAA==.Tbh:BAAALgAFFAEJAgABLgAFFAcJEAAXAHcaAA==.',
Te='Techevo:BAAALgAECgQJBQAAAA==.Techfire:BAABLgAECn8pAAInAAkJ9hoyAgBFAgAnAAkJ9hoyAgBFAgAAAA==.Techsmexx:BAAALgAECgMJBQAAAA==.Tenebron:BAABLgAECn8vAAIoAAYJQBJ/JgD6AAAoAAYJQBJ/JgD6AAAAAA==.Tenlucis:BAAALgAECggJDAAAAA==.',
Th='Thaelyssa:BAAALgAECgEJAQAAAA==.Tharria:BAAALgADCgcJBwAAAA==.Thearia:BAABLgAECn8bAAMPAAgJrRWBUgBcAQAPAAgJrRWBUgBcAQASAAUJmg4DVQC2AAAAAA==.Thecanmurk:BAAALgADCgkJEgAAAA==.Thedilf:BAAALgADCgEJAQAAAA==.Thicktotem:BAAALgAECgIJAgAAAA==.Thickumz:BAAALgAECgMJCgAAAA==.Thisismeta:BAAALgAECgYJCwAAAA==.Thorenis:BAAALgADCgEJAQAAAA==.Thoryndruid:BAACLgAFFH8TAAIhAAYJBB2TAgCoAQAhAAYJBB2TAgCoAQAuAAQKfzIAAyEACQkWIxEDAA4DACEACQnmIhEDAA4DAAwABwm8HgMNAAwCAAEuAAUUBwkTABUAQBsA.Thorïn:BAAALgADCgMJAwAAAA==.Thorýn:BAACLgAFFH8TAAIVAAcJQBtLGAAQAgAVAAcJQBtLGAAQAgAuAAQKfxoAAhUACAl8HhwqAFYCABUACAl8HhwqAFYCAAAA.Thórin:BAABLgAECn8iAAITAAgJQxfdDgDRAQATAAgJQxfdDgDRAQAAAA==.',
Ti='Timakk:BAAALgADCgEJAQAAAA==.Tipsy:BAABLgAECn8uAAMKAAkJWg8DOADLAQAKAAkJWg8DOADLAQADAAMJpA3edQCGAAAAAA==.',
To='Tombraider:BAAALgAECgUJCAAAAA==.Tomfoolary:BAAALgAECgEJAwAAAA==.Toofy:BAAALgAECgEJAQAAAA==.Tot:BAAALgAECgkJCwAAAA==.Total:BAAALgADCgkJDAAAAA==.Totembear:BAAALgAECgEJAgABLgAFFAIJBwASABUFAA==.',
Tr='Tralleth:BAABLgAECn8gAAMHAAgJ/hBSMwBkAQAHAAgJ/hBSMwBkAQAGAAEJGghlPQArAAAAAA==.Trid:BAAALgAECgQJBQAAAA==.Trillbilly:BAAALgAECgEJAQAAAA==.Trinora:BAAALgADCgkJDgAAAA==.Troginator:BAAALgAECgEJAQAAAA==.Trolltard:BAAALgAECgIJAgABLgAECgMJAwACAAAAAA==.Troxa:BAAALgAECgUJCgAAAA==.',
Tu='Tuckard:BAAALgADCgEJAQAAAA==.Tuskor:BAAALgAFFAEJAQAAAA==.',
Tw='Twinklord:BAAALgAECggJDgAAAA==.',
Ty='Tylanar:BAAALgAECgYJBgAAAA==.Tylolight:BAAALgADCgMJAwAAAA==.Tylomist:BAAALgAECgUJBQAAAA==.Tylototem:BAAALgAFFAEJAgAAAA==.',
Ug='Uglyboi:BAAALgAECggJDwAAAA==.',
Uj='Ujcmonk:BAAALgAECgQJBAAAAA==.',
Ul='Ullbian:BAAALgADCgMJAwAAAA==.Ultramar:BAAALgADCgEJAQAAAA==.',
Un='Uncookedham:BAAALgAECgQJCwAAAA==.',
Ur='Urgh:BAABLgAECn8fAAIIAAkJ9RHiIgCwAQAIAAkJ9RHiIgCwAQAAAA==.Urk:BAAALgAECgYJBgAAAA==.Urzaa:BAAALgAECgEJAwABLgAECgMJBAACAAAAAA==.',
Ut='Uthur:BAAALgAECgMJAwAAAA==.',
Va='Vaeelrundor:BAAALgAECgYJCgAAAA==.Valethales:BAAALgADCgcJBwAAAA==.Valyr:BAAALgAECgEJAQAAAA==.Vanillaface:BAABLgAECn8ZAAIJAAkJ7xwpHQCUAgAJAAkJ7xwpHQCUAgAAAA==.Vape:BAABLgAECn8WAAIcAAcJLg0qeABIAQAcAAcJLg0qeABIAQABLgAFFAUJDAARAMYbAA==.',
Ve='Veinripp:BAAALgADCgUJBQABLgAECggJNAAFAO0QAA==.Velarael:BAABLgAECn8rAAIcAAcJ8wtHiQAnAQAcAAcJ8wtHiQAnAQAAAA==.Velaryn:BAAALgADCgIJAgAAAA==.Veldar:BAAALgADCgIJAgAAAA==.Velekete:BAAALgADCgUJBQAAAA==.Velethei:BAABLgAECn8YAAIPAAYJlySkGQBrAgAPAAYJlySkGQBrAgAAAA==.Velian:BAAALgADCgMJBAAAAA==.Velielyn:BAAALgADCgQJBAAAAA==.Vellareth:BAAALgAECgEJAQAAAA==.Verdesalsa:BAAALgAECgcJDQAAAA==.Verox:BAAALgADCgMJAwAAAA==.Verzak:BAAALgAECgEJAQAAAA==.',
Vh='Vheckxus:BAABLgAECn8aAAIDAAYJaBTrPgA0AQADAAYJaBTrPgA0AQAAAA==.',
Vi='Vicv:BAABLgAECn8TAAIIAAkJXwwXNABIAQAIAAkJXwwXNABIAQAAAA==.Vivy:BAAALgAECgcJBwAAAA==.',
Vo='Voidberg:BAAALgAECgUJCwAAAA==.',
['Vê']='Vêa:BAAALgADCgkJCQAAAA==.',
Wa='Wachonaso:BAACLgAFFH8QAAIcAAYJRwxJTwAjAQAcAAYJRwxJTwAjAQAuAAQKfy0AAxwABwlJH6M0ADkCABwABwkrH6M0ADkCAB0ABgl8HlgXAI8BAAAA.Wanbahl:BAAALgADCgMJAwAAAA==.',
We='Wellburt:BAAALgAECgEJAQAAAA==.',
Wh='Whatuphuz:BAAALgADCgQJBQAAAA==.Wheresmyjaw:BAACLgAFFH8iAAQcAAUJJSCmOwBWAQAcAAUJmh6mOwBWAQAZAAEJWSPWFABnAAAdAAEJOQLKKwAyAAAuAAQKfycABBwACAnyIWAWAJwCABwACAnyIWAWAJwCAB0AAgm6DiRSAHcAABkAAQnAIH8uAF8AAAAA.',
Wi='Wildstàr:BAAALgADCgMJAwAAAA==.Wildthree:BAABLgAECn8rAAMYAAkJwh3RCQCjAgAYAAkJwh3RCQCjAgAbAAMJ2RQvYgC5AAAAAA==.Willenda:BAAALgAECgEJAwAAAA==.Willowins:BAAALgAECgEJAQAAAA==.Winterstired:BAACLgAFFH8cAAIkAAQJRiYYCQCzAQAkAAQJRiYYCQCzAQAuAAQKf0IAAyQACQnuJHUCAHoDACQACQnuJHUCAHoDAAQAAQlKF7dvAEQAAAAA.',
Wo='Woen:BAAALgADCggJCQAAAA==.Wolf:BAAALgAECgQJBwAAAA==.Wollffie:BAAALgAECgQJBAAAAA==.',
Wu='Wuinn:BAAALgAFFAEJAQABLgAFFAQJEQAPAJQgAA==.Wut:BAAALgADCgcJBwAAAA==.',
Wy='Wynterswrath:BAAALgAECgYJCwAAAA==.',
['Wõ']='Wõnderful:BAABLgAECn8aAAIPAAcJPhtyJAAlAgAPAAcJPhtyJAAlAgABLgAFFAUJFAAWAPcgAA==.',
Xc='Xclobber:BAAALgADCgIJAgAAAA==.',
Xe='Xemnass:BAAALgAECgUJBwAAAA==.',
Xi='Xillas:BAAALgADCgUJBQAAAA==.',
Xo='Xoverkll:BAAALgAECgYJDAAAAA==.',
Xy='Xylina:BAAALgADCgEJAQAAAA==.Xyrii:BAAALgADCgEJAQAAAA==.',
Ya='Yadder:BAAALgAECgIJBAABLgAFFAMJBQAKAI0eAA==.Yahro:BAACLgAFFH8QAAIJAAUJBRPiQAAkAQAJAAUJBRPiQAAkAQAuAAQKfy4AAgkACQkdHzkVAMECAAkACQkdHzkVAMECAAAA.Yamelow:BAAALgAECgQJBwAAAA==.',
Ye='Yeahiknow:BAAALgADCgkJDgAAAA==.Yeling:BAAALgAECgIJAgAAAA==.Yep:BAAALgAECgcJBwAAAA==.',
Yi='Yiska:BAAALgADCgcJBwAAAA==.',
Yo='Yoriale:BAAALgAECgYJDgAAAA==.Yotoymuerto:BAAALgAECgQJBAAAAA==.',
Za='Zafra:BAAALgADCgEJAQAAAA==.Zaimara:BAAALgAECgEJBgAAAA==.Zalind:BAABLgAECn8VAAIcAAkJCxJoZgCYAQAcAAkJCxJoZgCYAQAAAA==.Zalvianna:BAABLgAECn8iAAMBAAgJLQTJwQADAQABAAgJLQTJwQADAQAlAAEJXQHIIgAYAAAAAA==.Zarindlina:BAAALgADCgUJBQAAAA==.Zarshx:BAAALgAECgYJCwABLgAFFAMJBAACAAAAAA==.',
Ze='Zemonk:BAAALgAECgYJBgAAAA==.',
Zi='Zilong:BAAALgAFFAEJAQABLgAFFAUJDwAFAAEaAA==.Zilongmage:BAAALgAFFAIJAwABLgAFFAUJDwAFAAEaAA==.Zilongwar:BAAALgAFFAMJAwABLgAFFAUJDwAFAAEaAA==.Zinnia:BAAALgADCgEJAgAAAA==.',
Zo='Zonedk:BAABLgAECn8WAAQWAAYJfB8WEwBFAQAaAAUJQCHzHgBbAQAWAAYJLBYWEwBFAQAVAAEJxBdiWwFBAAAAAA==.Zonerg:BAAALgADCgEJAgABLgAECgYJFgAWAHwfAA==.Zonevn:BAAALgAECgMJAwABLgAECgYJFgAWAHwfAA==.Zordak:BAAALgADCgcJCAAAAA==.Zosin:BAAALgAECgEJAQAAAA==.',
Zu='Zugzugzapzap:BAAALgADCgEJAQAAAA==.',
Zy='Zylphanae:BAAALgAECgQJBAAAAA==.',
['Øl']='Ølaf:BAAALgAECgEJAQABLgAFFAQJFQAXAOsfAA==.',
['Ør']='Ørsted:BAAALgAECgEJAgABLgAFFAQJFQAXAOsfAA==.',
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
