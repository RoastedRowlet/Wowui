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

local lookup = {'Mage-Frost','Unknown-Unknown','Shaman-Elemental','Shaman-Restoration','Priest-Discipline','DemonHunter-Devourer','Evoker-Preservation','Evoker-Augmentation','Priest-Shadow','Paladin-Retribution','Rogue-Subtlety','Hunter-Marksmanship','Druid-Guardian','Warrior-Arms','Warrior-Fury','Druid-Restoration','DemonHunter-Havoc','Hunter-BeastMastery','Druid-Balance','Paladin-Protection','Hunter-Survival','DeathKnight-Unholy','DeathKnight-Frost','Monk-Mistweaver','Monk-Windwalker','Warlock-Affliction','DeathKnight-Blood','Monk-Brewmaster','Warlock-Demonology','Warlock-Destruction','Evoker-Devastation','Shaman-Enhancement','DemonHunter-Vengeance','Druid-Feral','Rogue-Assassination','Paladin-Holy','Priest-Holy','Mage-Arcane','Mage-Fire','Warrior-Protection',}
local provider = {region='US',realm='Nazjatar',name='US',type='weekly',zone=46,date='2026-06-27',data={Aa='Aaela:BAAALgADCgUJBQAAAA==.',
Ab='Abrasaxs:BAABLgAECn8qAAIBAAgJQhijWQDQAQABAAgJQhijWQDQAQAAAA==.Absylus:BAAALgAECgQJBAABLgAFFAMJBAACAAAAAA==.',
Ac='Accoli:BAAALgAFFAEJAQAAAA==.Ackerman:BAAALgAECgYJCgABLgAECggJEgACAAAAAA==.Acraea:BAABLgAECn8hAAIBAAgJmwwuhABvAQABAAgJmwwuhABvAQAAAA==.Acràea:BAAALgAFFAEJAQAAAA==.Acslater:BAAALgAECgQJDQAAAA==.Actionman:BAAALgAECgkJBwAAAA==.',
Ad='Adversary:BAAALgAECgMJBAAAAA==.',
Ag='Agoobagoo:BAACLgAFFH8bAAMDAAYJwiHMDQDOAQADAAYJwiHMDQDOAQAEAAEJ6yHgHQBpAAAuAAQKfyIAAgMACQnZIpAEAFIDAAMACQnZIpAEAFIDAAAA.',
Ai='Aionn:BAAALgAECgMJAwAAAA==.Airrow:BAABLgAECn8UAAIFAAkJEhk3EABuAgAFAAkJEhk3EABuAgAAAA==.Aissae:BAACLgAFFH8PAAIGAAQJ7hwUOQBAAQAGAAQJ7hwUOQBAAQAuAAQKfy0AAgYACAlEJHYLACYDAAYACAlEJHYLACYDAAAA.Aiyama:BAAALgADCgQJBAAAAA==.',
Ak='Akiio:BAAALgAECgMJAwAAAA==.Akumaxl:BAAALgAECgYJBwAAAA==.',
Al='Alexia:BAAALgAECgEJAQAAAA==.Alfrank:BAAALgAECgIJAwAAAA==.Aliasx:BAAALgAECgMJBAAAAA==.Allwrong:BAAALgAECgUJBgAAAA==.Alphrank:BAAALgAECgEJAgAAAA==.Alurie:BAAALgAECgUJCgAAAA==.Alustre:BAAALgAFFAEJAQAAAA==.',
Am='Amandrada:BAAALgAFFAEJAQAAAA==.Ambros:BAAALgADCgYJBgAAAA==.Aminatou:BAAALgAECgYJBwAAAA==.',
An='Angerfang:BAAALgADCgQJBQAAAA==.Angriff:BAAALgAECgEJAgAAAA==.Anheeboan:BAAALgAECgYJCwAAAA==.Anihilated:BAAALgADCgYJBwAAAA==.',
Ar='Aradiax:BAAALgADCgYJBgAAAA==.Arcadavia:BAAALgADCgMJAwAAAA==.Ariaprime:BAABLgAECn8XAAIBAAcJawvDsAAgAQABAAcJawvDsAAgAQAAAA==.Arjentheilus:BAAALgAECgMJAwAAAA==.Armandox:BAAALgAECgEJAQAAAA==.Arthasl:BAAALgADCgMJAgAAAA==.Arthes:BAAALgAECgIJAgAAAA==.Arthur:BAAALgAECgQJDgAAAA==.',
As='Asasda:BAAALgADCgMJBAAAAA==.Ashaelra:BAAALgAECgYJCAAAAA==.Astravaritan:BAAALgADCgMJAwAAAA==.Astrá:BAAALgAECgYJEQABLgAECgUJEQACAAAAAA==.',
At='Atherya:BAAALgAECgYJCAAAAA==.Atomixblonde:BAAALgAECgQJBAAAAA==.',
Au='Augonly:BAACLgAFFH8eAAIHAAcJQxdhCgAFAgAHAAcJQxdhCgAFAgAuAAQKfyMAAgcACQnpIC4GAOECAAcACQnpIC4GAOECAAAA.Augy:BAACLgAFFH8OAAIIAAQJMg0rNwDoAAAIAAQJMg0rNwDoAAAuAAQKfx0AAwgACQkyGvMcAO8BAAgACAnlGPMcAO8BAAcAAQmSBOk+ACkAAAAA.Autoshot:BAAALgAFFAIJAgAAAA==.',
Av='Averisbelia:BAAALgAECgYJCwAAAA==.',
Ay='Ayowamsley:BAAALgADCgMJAwAAAA==.',
Az='Azalea:BAAALgAECggJEAAAAA==.',
Ba='Babycrock:BAAALgADCgYJBgAAAA==.Back:BAAALgADCgcJDAAAAA==.Bakihanma:BAAALgAECgQJBgAAAA==.Balash:BAAALgADCgUJBQAAAA==.Balerion:BAAALgADCgEJAQABLgADCgMJAwACAAAAAA==.Balthasar:BAABLgAECn8nAAIJAAkJExpYDwBkAgAJAAkJExpYDwBkAgAAAA==.Banjobits:BAAALgADCgIJAgAAAA==.Barhead:BAAALgAECgYJDAAAAA==.Barlow:BAAALgAECggJEQAAAA==.Barqose:BAAALgADCgMJAwAAAA==.Barryberry:BAABLgAECn8fAAIKAAkJDRE0fgByAQAKAAkJDRE0fgByAQAAAA==.Barryx:BAAALgAECgIJAgAAAA==.',
Bb='Bbldrizzy:BAABLgAFFH8GAAMEAAMJjR5+PQDuAAAEAAMJjR5+PQDuAAADAAEJyRB7HABDAAABLgAFFAQJCgALAGQRAA==.',
Be='Beastlieduke:BAAALgAECgMJAwABLgAFFAYJFgAJAOwOAA==.Beastlièduke:BAACLgAFFH8WAAIJAAYJ7A4dEgBXAQAJAAYJ7A4dEgBXAQAuAAQKfzQAAgkACQkfIE8MAIsCAAkACQkfIE8MAIsCAAAA.Beauslay:BAAALgAECgEJAQAAAA==.Belephon:BAAALgAECgYJEAAAAA==.Bellaruhbz:BAABLgAECn8eAAIMAAkJjA+0FwD1AAAMAAkJjA+0FwD1AAAAAA==.Berenstain:BAABLgAECn8nAAINAAkJShP8FwCSAQANAAkJShP8FwCSAQAAAA==.Bergmire:BAAALgAECgQJCgAAAA==.Berple:BAAALgADCgUJBQABLgAFFAgJGQABAK0iAA==.Bestoresto:BAABLgAECn8XAAIEAAkJBQwTRACdAQAEAAkJBQwTRACdAQAAAA==.',
Bh='Bhori:BAAALgAECgEJAwAAAA==.',
Bi='Bibahabibi:BAABLgAECn8dAAMOAAYJxhvpJQA5AQAOAAYJxhvpJQA5AQAPAAMJzQiVhwChAAAAAA==.Bighunt:BAAALgAECgEJAQAAAA==.Bigpapax:BAAALgAECgEJAQAAAA==.Bigtac:BAABLgAECn8vAAMOAAkJlBxYCQBbAgAOAAkJlBxYCQBbAgAPAAIJ3gc5mQBcAAAAAA==.Bimmylee:BAAALgADCgEJAQAAAA==.Binggus:BAAALgAFFAEJAQAAAA==.Bipolaire:BAAALgADCgEJAQAAAA==.',
Bl='Blabbybootze:BAAALgAECggJDgAAAA==.Bladelight:BAAALgAECgYJCAAAAA==.Blighte:BAAALgADCgQJBAABLgAECggJIQAQAIIkAA==.Blightfangs:BAACLgAFFH8HAAIBAAMJkgvyhwDJAAABAAMJkgvyhwDJAAAuAAQKf0YAAgEACQmVGo80AEYCAAEACQmVGo80AEYCAAAA.Blindnautdef:BAABLgAECn80AAMGAAgJ7RAeagBRAQAGAAgJ7RAeagBRAQARAAEJ9gPefgAhAAAAAA==.Bloodluna:BAAALgADCgUJBQAAAA==.',
Bo='Bobman:BAAALgAECgUJCAAAAA==.Bodakye:BAACLgAFFH8NAAISAAMJfAreaADTAAASAAMJfAreaADTAAAuAAQKfyQAAxIACQlBG1IuACMCABIACQlBG1IuACMCAAwAAgm0ARCBAEMAAAAA.Bonargrowrod:BAABLgAECn8UAAIKAAcJmAPjGABsAAAKAAcJmAPjGABsAAAAAA==.Bonkz:BAAALgAECgMJAwAAAA==.Boomtip:BAAALgADCgMJAwAAAA==.Boon:BAAALgADCgYJCQAAAA==.Bordolor:BAAALgAECgEJAQAAAA==.Bowsa:BAAALgAECgkJAQAAAA==.',
Br='Brabbit:BAAALgAECgQJCQAAAA==.Brethathes:BAAALgAECgkJEgAAAA==.Brudda:BAAALgADCgUJBQAAAA==.',
Bu='Bubbaray:BAAALgAECgMJAwAAAA==.Bubblebun:BAAALgAECgMJBgAAAA==.Bungerhole:BAABLgAECn8WAAMQAAgJxRtRMADhAQAQAAgJxRtRMADhAQATAAEJEQllmwAmAAAAAA==.Butane:BAAALgADCgIJAgAAAA==.Buzzbuzz:BAAALgAECgIJBwAAAA==.',
Ca='Caeruleus:BAAALgAECgEJAgAAAA==.Cainn:BAAALgAECgYJBwAAAA==.Cap:BAAALgADCgEJAQABLgAFFAQJFwABAGIeAA==.Capriestsun:BAAALgAFFAMJAwABLgAFFAQJCgALAGQRAA==.Captyn:BAABLgAECn8cAAIUAAgJug2FGgBEAQAUAAgJug2FGgBEAQAAAA==.Carridin:BAAALgADCgMJAwAAAA==.Cass:BAAALgAECgEJAQAAAA==.',
Ce='Cernunon:BAAALgADCgEJAQAAAA==.Ceroquel:BAAALgAECgMJAwAAAA==.',
Ch='Chaosdemon:BAABLgAECn81AAIGAAkJPRDIRQC1AQAGAAkJPRDIRQC1AQAAAA==.Chaosraven:BAAALgADCgkJCQAAAA==.Chapelgnome:BAAALgAECgUJCQABLgAFFAYJBwAIAIUCAA==.Charlottea:BAAALgAECgYJDwAAAA==.Chemdra:BAAALgAECgcJEwAAAA==.Chiling:BAAALgAECgEJAQAAAA==.Chipmonkey:BAAALgAECgEJAgABLgAECgkJNAAQAMEPAA==.Chiptime:BAABLgAECn80AAIQAAkJwQ94NwC6AQAQAAkJwQ94NwC6AQABLgAECgkJNAAQAMEPAA==.Chomby:BAAALgAECgQJAwAAAA==.Chriifrio:BAAALgADCgUJBgAAAA==.Chromosomes:BAAALgAECgQJBAAAAA==.Chud:BAAALgAECgQJCQAAAA==.Chudsworth:BAAALgADCgYJCQAAAA==.Chunguhlumpo:BAAALgAECgEJBAAAAA==.Chzburger:BAAALgAECgIJAgAAAA==.',
Ci='Cinnamóróll:BAABLgAECn9HAAIVAAkJVRS5AAATAgAVAAkJVRS5AAATAgAAAA==.',
Cl='Clairity:BAAALgAECgMJAwAAAA==.Clare:BAAALgAFFAEJAQAAAA==.Cleru:BAABLgAECn8fAAMWAAgJxhNYfABrAQAWAAgJxhNYfABrAQAXAAEJpwMVGgAlAAAAAA==.Cletus:BAAALgADCgcJAgAAAA==.',
Co='Coa:BAAALgAECgkJDAAAAA==.Cocoon:BAABLgAFFH8VAAMYAAcJCxwLEAARAgAYAAcJCxwLEAARAgAZAAMJEBGJLQCTAAAAAA==.Coldsoul:BAAALgAECgYJCgAAAA==.Comanderkush:BAAALgADCgMJAwAAAA==.Coran:BAAALgAECgIJAwABLgAECgkJJAAaAG0bAA==.Corita:BAAALgAECgIJAgAAAA==.Cowboi:BAAALgADCgMJAwAAAA==.Cowhealer:BAABLgAECn8hAAMQAAgJgiRkCAAIAwAQAAgJgiRkCAAIAwATAAEJTwUTgQAvAAAAAA==.',
Cr='Craeftigdh:BAAALgAECgEJAQABLgAECggJLwABAKkfAA==.Creamypies:BAAALgAECgEJAQAAAA==.Criticaltwo:BAAALgADCgIJAgAAAA==.Crockknight:BAAALgADCgYJBgAAAA==.Crossways:BAAALgAECgYJCQAAAA==.Cræftig:BAABLgAECn8vAAIBAAgJqR/bAgACAgABAAgJqR/bAgACAgAAAA==.',
Cu='Cursecthree:BAAALgADCgEJAQAAAA==.Curseword:BAAALgAECgEJAQAAAA==.Cutestxx:BAAALgAECgkJCwAAAA==.',
Cy='Cyxo:BAAALgADCgEJAQABLgAECgEJAQACAAAAAA==.',
Da='Dadune:BAAALgAECgEJAQABLgAECgUJCgACAAAAAA==.Daftxshade:BAABLgAECn8UAAILAAYJpxECAwAKAQALAAYJpxECAwAKAQAAAA==.Dandandan:BAAALgADCgMJAwAAAA==.Dapan:BAAALgADCgcJDQAAAA==.Dariaa:BAABLgAECn8UAAISAAUJew0EsQDiAAASAAUJew0EsQDiAAAAAA==.Darkcrusader:BAAALgAECgcJEAAAAA==.Darkheal:BAAALgADCgUJBQAAAA==.Darkladie:BAAALgADCgEJAQAAAA==.Darkshadows:BAAALgAECgUJEAAAAA==.Darktank:BAAALgAECgIJAgAAAA==.Darthsyde:BAABLgAECn8eAAIbAAkJDxKAHAB2AQAbAAkJDxKAHAB2AQAAAA==.Dasdk:BAABLgAFFH8SAAIWAAQJzCK5OwCCAQAWAAQJzCK5OwCCAQAAAA==.Daspriest:BAAALgADCgYJDQABLgAFFAQJEgAWAMwiAA==.',
De='Deadergriff:BAAALgAECgkJDQAAAA==.Deadhippycb:BAAALgAECgQJBAAAAA==.Deadhippyxy:BAAALgAECgEJAwAAAA==.Deadicated:BAABLgAECn8gAAQcAAgJzgdlRgDhAAAcAAcJLAZlRgDhAAAZAAcJQgidYACZAAAYAAUJaQURjwB8AAAAAA==.Deadsies:BAAALgADCgIJAgABLgAFFAIJAwACAAAAAA==.Deeds:BAAALgAECgMJAwAAAA==.Delan:BAAALgAECgQJBQAAAA==.Delveknight:BAAALgADCgYJBgABLgAECgcJFwAWAHUdAA==.Demoncox:BAAALgADCgMJAgAAAA==.Demondoc:BAACLgAFFH8QAAIGAAUJ7g/JTAAEAQAGAAUJ7g/JTAAEAQAuAAQKfx8AAgYACAlpF+E0APMBAAYACAlpF+E0APMBAAAA.Desunaito:BAACLgAFFH8kAAMXAAgJTBziAgAIAgAXAAgJTBziAgAIAgAbAAEJAACHXAAAAAAuAAQKfy0AAhcACQlUJWkBACcDABcACQlUJWkBACcDAAAA.Devious:BAAALgADCgEJAQAAAA==.Dexter:BAAALgAECgIJAgAAAA==.',
Dh='Dhzilong:BAACLgAFFH8PAAIGAAUJARoZRgAVAQAGAAUJARoZRgAVAQAuAAQKfx0AAwYACAlHIU84ABQCAAYACAkzHk84ABQCABEABQmNJJEeAMoBAAAA.',
Di='Diddlefiddle:BAACLgAFFH8LAAMVAAUJjSB2CQB/AQAVAAUJjSB2CQB/AQAMAAEJ7ByHLQBWAAAuAAQKfxYABBUACAn5Hx8JAIwCABUABwn5Hx8JAIwCAAwAAwlmIU0fALQAABIAAQkgHGi3AFQAAAAA.Dihcum:BAABLgAFFH8FAAIWAAIJ2QfM+wBxAAAWAAIJ2QfM+wBxAAAAAA==.Dimonologist:BAAALgAECgEJAQAAAA==.Dinzarn:BAAALgADCgEJAQAAAA==.Dirtycow:BAAALgAECgQJBAAAAA==.',
Dk='Dkzilong:BAAALgAFFAIJBAABLgAFFAUJDwAGAAEaAA==.',
Dm='Dmeo:BAAALgADCgIJAgAAAA==.',
Do='Docholy:BAAALgAECgYJCAABLgAFFAUJEAAGAO4PAA==.Dockson:BAAALgAECgMJAwAAAA==.Docwyle:BAABLgAECn8XAAMdAAgJnxEecwBUAQAdAAgJnxEecwBUAQAeAAEJtgLUcgAzAAABLgAFFAUJEAAGAO4PAA==.Doobyia:BAAALgADCgEJAQAAAA==.Dorki:BAAALgAECgEJAgAAAA==.Dorlanlemeth:BAABLgAECn8VAAIGAAcJBwwyhAAXAQAGAAcJBwwyhAAXAQAAAA==.Dormist:BAAALgAECgMJBAABLgAECgkJJAAaAG0bAA==.Dotti:BAAALgAFFAEJAQAAAA==.',
Dr='Dracnogard:BAAALgAECgcJDgAAAA==.Dracowulf:BAABLgAECn8lAAISAAkJtxC4PgDmAQASAAkJtxC4PgDmAQAAAA==.Dragonx:BAABLgAECn8yAAMSAAgJJhOnZQB5AQASAAgJJhOnZQB5AQAVAAMJaQ3YRACtAAAAAA==.Drakos:BAAALgAECgEJAQAAAA==.Drakowolf:BAABLgAECn9OAAIfAAkJpQegDwARAQAfAAkJpQegDwARAQAAAA==.Drenz:BAAALgADCgEJAQAAAA==.Dreorge:BAABLgAFFH8GAAIIAAMJcxENQgC/AAAIAAMJcxENQgC/AAAAAA==.Dreuceratops:BAAALgAECgMJAwAAAA==.Drewceratops:BAABLgAECn8oAAIKAAkJtRTpRQD0AQAKAAkJtRTpRQD0AQAAAA==.Driis:BAAALgADCgcJBwAAAA==.Drimchi:BAABLgAFFH8RAAMfAAQJixqnAQC2AAAIAAQJYhY0LAAUAQAfAAMJChmnAQC2AAAAAA==.Drimveil:BAAALgAFFAEJAQAAAA==.Drizro:BAAALgADCgIJAgAAAA==.Drk:BAAALgAECgEJAQAAAA==.Drkundead:BAAALgAECgEJAQAAAA==.Dromash:BAABLgAECn8kAAMaAAkJbRuXAwB6AgAaAAkJbRuXAwB6AgAeAAgJLhN3DAB4AQAAAA==.Dromgar:BAAALgAFFAIJBAABLgAFFAMJCQAgAAojAA==.Drpepperz:BAAALgAECgMJAwAAAA==.Druidyhealz:BAAALgAECgMJAwABLgAECgcJDwACAAAAAA==.',
Du='Duuke:BAAALgAECgEJAQAAAA==.',
['Då']='Dårius:BAAALgAECgYJEQAAAA==.',
Ea='Eaterofpaint:BAAALgAECgYJDgAAAA==.',
Ed='Edgeylord:BAAALgAECgEJAQABLgAECgMJBAACAAAAAA==.',
Ef='Effloria:BAABLgAECn8lAAIQAAkJEx3TDAD3AgAQAAkJEx3TDAD3AgAAAA==.Efrideet:BAAALgADCgEJAQAAAA==.',
Ei='Eisha:BAAALgADCgUJBQAAAA==.',
El='Elegia:BAACLgAFFH8aAAIdAAUJGBZGFgDZAAAdAAUJGBZGFgDZAAAuAAQKfy8AAx0ACQlWGyIZAL4CAB0ACQlWGyIZAL4CAB4AAQkAAAdmAEMAAAAA.Elerianor:BAAALgAECgYJEgAAAA==.Ellektra:BAAALgADCgUJBQAAAA==.Elsocio:BAAALgADCgEJAQAAAA==.',
Em='Emadiropilo:BAAALgAECgEJAQAAAA==.Emakaa:BAAALgAECgYJCAAAAA==.Embrohunter:BAAALgAECgQJBQAAAA==.',
En='Enash:BAAALgAECgQJBwAAAA==.Engvald:BAAALgADCgUJBQAAAA==.Enhua:BAAALgADCgUJBQAAAA==.Ennet:BAAALgAECgQJBgAAAA==.',
Er='Eretin:BAAALgADCgEJAQAAAA==.Erismorn:BAABLgAECn8iAAQhAAcJNR5cCwCpAQAhAAYJnBtcCwCpAQAGAAYJiBidWgB4AQARAAEJ4RAEcAA1AAAAAA==.Erulious:BAAALgADCgIJAgAAAA==.',
Eu='Eudi:BAAALgAECgEJAgAAAA==.',
Ev='Eventhorizòn:BAABLgAECn8UAAIGAAgJ8hkYMgAyAgAGAAgJ8hkYMgAyAgAAAA==.Evilhoe:BAAALgADCgUJBQAAAA==.Evocation:BAAALgAECggJEgAAAA==.Evoextoons:BAAALgAECgUJDQAAAA==.',
Fa='Fallen:BAABLgAECn8YAAMWAAkJiCSAPAAPAgAWAAkJiCSAPAAPAgAbAAMJ7wvARAB8AAAAAA==.Fallingvoid:BAABLgAECn9iAAMGAAkJJiUaAgC3AwAGAAkJJiQaAgC3AwARAAIJpiUwNwDeAAAAAA==.Fast:BAAALgAECgEJAgABLgAECgIJAgACAAAAAA==.Fatchungus:BAAALgAFFAMJBAAAAA==.Fatherben:BAABLgAECn8XAAIGAAYJVBURgAAgAQAGAAYJVBURgAAgAQAAAA==.Fatmagus:BAAALgAECgcJBgAAAA==.Favio:BAAALgAECggJCwAAAA==.',
Fe='Fellbian:BAAALgADCgcJDgAAAA==.Fentanyahu:BAAALgAECgYJBgAAAA==.Ferozz:BAACLgAFFH8LAAIMAAMJSw70HQC8AAAMAAMJSw70HQC8AAAuAAQKfzEAAgwACAm7HmIHABECAAwACAm7HmIHABECAAAA.',
Fi='Fiercetaco:BAAALgADCgEJAQAAAA==.Finaliter:BAACLgAFFH8TAAIKAAUJZBqiOQA5AQAKAAUJZBqiOQA5AQAuAAQKfy8AAgoACQk7IJslAG4CAAoACQk7IJslAG4CAAAA.Finatar:BAAALgADCgcJCwAAAA==.Fiora:BAABLgAECn8SAAIGAAcJKx87KQBdAgAGAAcJKx87KQBdAgAAAA==.Fitz:BAAALgADCgEJAQAAAA==.Fiveyears:BAAALgADCgEJAQAAAA==.',
Fk='Fknutmcgee:BAAALgAECgUJBQAAAA==.',
Fl='Flamingdrago:BAAALgAECgMJBAAAAA==.Flinti:BAAALgAECgUJCQAAAA==.Flirtyflurry:BAABLgAECn9DAAIBAAgJ8Bp/AgAkAgABAAgJ8Bp/AgAkAgAAAA==.Floggy:BAABLgAECn8eAAIBAAgJNgilmgBEAQABAAgJNgilmgBEAQAAAA==.',
Fo='Forsight:BAABLgAECn8YAAIWAAgJUhWEgABiAQAWAAgJUhWEgABiAQAAAA==.',
Fr='Fracker:BAAALgAECgcJCAAAAA==.Frankzzorz:BAACLgAFFH8JAAIYAAMJZgpiRwCHAAAYAAMJZgpiRwCHAAAuAAQKfzQAAxgACQk1HLQMAIcCABgACQk1HLQMAIcCABkAAglFIFtYAK8AAAAA.Fremder:BAACLgAFFH8XAAIHAAQJyRV7FwAeAQAHAAQJyRV7FwAeAQAuAAQKfzwAAgcACQmqHLwEANoCAAcACQmqHLwEANoCAAAA.Fresher:BAABLgAECn8VAAIWAAUJyxwytQANAQAWAAUJyxwytQANAQABLgAFFAQJCgALAGQRAA==.Freyjen:BAAALgADCgkJGAABLgAECgcJCgACAAAAAA==.Froboz:BAAALgADCgYJCQAAAA==.Frogevil:BAAALgAECgcJEQAAAA==.Frogtoad:BAAALgAECgYJBgAAAA==.Frogtree:BAAALgADCgUJBQAAAA==.Frostmoth:BAAALgADCgQJBAABLgAECggJGAAWAFIVAA==.Frumentarii:BAAALgAECgQJBAAAAA==.',
Fu='Funeral:BAACLgAFFH8yAAQeAAkJSBmzBABgAQAdAAUJqxT6CQBnAQAeAAUJ/R2zBABgAQAaAAMJOhqABgAYAQAuAAQKfzUABB4ACQnmIz4EAKECAB4ABwnSID4EAKECABoABwmUIrUEAE4CAB0ACAkxGetEAP0BAAAA.',
['Fà']='Fàstïk:BAAALgAECgEJAQAAAA==.',
Ga='Galladin:BAAALgAECgMJBQABLgAECgYJDQACAAAAAA==.Gallory:BAAALgAECgkJDgAAAA==.Gareeshala:BAAALgAECgIJAgAAAA==.',
Gd='Gdk:BAAALgAECgYJCAAAAA==.Gdkdemon:BAAALgAECgMJAwAAAA==.Gdkdrake:BAAALgAECgcJBwAAAA==.Gdkhunter:BAAALgAECgYJAwAAAA==.Gdkmage:BAAALgAECgkJEwAAAA==.Gdkman:BAAALgAECgcJAQAAAA==.Gdkwar:BAAALgAECgUJBAAAAA==.',
Ge='Geomancer:BAAALgADCgQJBAAAAA==.',
Gh='Ghadius:BAAALgAECgcJCgAAAA==.',
Gi='Gimmedatmouf:BAABLgAECn8XAAQQAAgJoyHjCAABAwAQAAgJoyHjCAABAwAiAAMJph6MLgCqAAATAAQJexZTYQCUAAABLgAFFAQJCgALAGQRAA==.Gimmedatneck:BAACLgAFFH8KAAILAAQJZBGDJAAAAQALAAQJZBGDJAAAAQAuAAQKfxcAAwsACAlVI2EYAEQCAAsACAlVI2EYAEQCACMAAQk2EuAcAEMAAAAA.Ginga:BAAALgAECgEJAQAAAA==.Gingy:BAAALgAECgUJBgAAAA==.',
Gl='Glead:BAABLgAECn8aAAIPAAkJ6ReNLQD9AQAPAAkJ6ReNLQD9AQAAAA==.Glizzymguire:BAAALgAECggJCAABLgAFFAMJDAAdACQGAA==.',
Gn='Gneeduh:BAAALgAECgIJAwAAAA==.',
Go='Gobknight:BAAALgADCggJCAAAAA==.Goldina:BAAALgAECgEJAQAAAA==.Gooklover:BAAALgAECgQJCQAAAA==.Gosupal:BAAALgADCgYJBgAAAA==.',
Gr='Gracious:BAAALgAECgEJAQAAAA==.Graegor:BAAALgADCgYJBwAAAA==.Grastim:BAAALgAECgUJCgAAAA==.Graylight:BAAALgADCgUJBQAAAA==.Greenfanta:BAAALgADCgYJEAAAAA==.Grill:BAAALgADCgEJAQAAAA==.Grinkle:BAACLgAFFH8GAAIEAAMJFAYyYACKAAAEAAMJFAYyYACKAAAuAAQKfysAAgQACQkjEcs8ALsBAAQACQkjEcs8ALsBAAAA.Gripopotamus:BAAALgAECgIJAgAAAA==.Gristle:BAAALgADCgkJJwAAAA==.',
Gu='Guldangg:BAAALgAECgcJEAAAAA==.Gunner:BAACLgAFFH8SAAISAAUJxhtzDQAzAQASAAUJxhtzDQAzAQAuAAQKfx4AAxIACQnuItwGACgDABIACQm5ItwGACgDABUAAwnWIXYDAMcAAAAA.',
Ha='Hakaishaz:BAAALgADCgUJBgAAAA==.Halfwatt:BAAALgAECgYJDQAAAA==.Hamaddor:BAAALgAECgYJBgAAAA==.Hamberger:BAAALgADCgEJAQAAAA==.Hammerfire:BAAALgADCgMJAwAAAA==.Handen:BAAALgAECgkJEAAAAA==.Haraldsson:BAABLgAECn8gAAIKAAgJkRaMUQDUAQAKAAgJkRaMUQDUAQAAAA==.Harmony:BAAALgADCgcJCgAAAA==.Harrin:BAAALgADCgYJDAAAAA==.Harrydabs:BAABLgAECn8dAAMhAAkJRCNNAACDAwAhAAkJRCNNAACDAwARAAQJJRB3PwD+AAABLgAFFAEJAQACAAAAAA==.Haru:BAABLgAECn8nAAIVAAkJTRh4GADdAQAVAAkJTRh4GADdAQAAAA==.Harvaal:BAAALgAECgUJBQAAAA==.Hasaro:BAACLgAFFH8LAAINAAMJuhU0GgC5AAANAAMJuhU0GgC5AAAuAAQKfysAAg0ACQmNG7QHAHkCAA0ACQmNG7QHAHkCAAAA.Hashimi:BAAALgAECgcJBwAAAA==.Hashiramaa:BAAALgAECgYJCgAAAA==.Havokvacano:BAABLgAECn8fAAIKAAkJjxPsSADrAQAKAAkJjxPsSADrAQAAAA==.',
He='Healmachine:BAAALgAECgcJEwAAAA==.Hellbrringer:BAABLgAECn8XAAIBAAYJRQxm1ADrAAABAAYJRQxm1ADrAAAAAA==.Helzerx:BAABLgAECn8qAAILAAkJPB0ACACnAgALAAkJPB0ACACnAgABLgAFFAIJAgACAAAAAA==.Herpstrike:BAAALgAECgIJAwAAAA==.',
Hi='Highlanchrii:BAAALgAECgEJAQAAAA==.',
Ho='Hoely:BAAALgAECgEJAQAAAA==.Hogmanjr:BAAALgADCgQJBgAAAA==.Holycrappala:BAAALgADCgEJAQAAAA==.Hotsordots:BAAALgAECggJCwAAAA==.Hounskul:BAABLgAECn8gAAIdAAkJogfAfQA9AQAdAAkJogfAfQA9AQAAAA==.How:BAAALgADCgYJBgABLgAFFAUJEgASAMYbAA==.',
Hu='Hugealien:BAAALgADCgIJAgAAAA==.Hulksmash:BAAALgAECgEJAQAAAA==.Hungchungus:BAAALgAECgEJAgAAAA==.Hungwaylo:BAAALgADCgIJAgAAAA==.',
Hw='Hwere:BAAALgAECgUJBgAAAA==.',
Hy='Hypnoticpal:BAAALgAECgkJBwAAAA==.Hystëria:BAACLgAFFH8YAAMXAAUJliE1CABqAQAXAAUJliE1CABqAQAWAAQJaRUbrQDGAAAuAAQKf1IAAxcACQmQI3wBACIDABcACQmhInwBACIDABYACAkJIV0oAGACAAAA.Hyunlix:BAAALgADCgUJBQAAAA==.',
Ia='Iammoo:BAABLgAECn8UAAIKAAcJKhxCaACeAQAKAAcJKhxCaACeAQAAAA==.',
Ic='Ichorus:BAAALgADCgEJAQAAAA==.',
Id='Idasie:BAAALgADCgcJDQAAAA==.',
Ig='Igotkappa:BAAALgADCgMJAwAAAA==.Igotyourback:BAAALgAECggJCAAAAA==.Igriss:BAAALgAECgMJBgAAAA==.',
Il='Illuminaughd:BAAALgAECgQJAQAAAA==.Ilydris:BAAALgADCgQJBAAAAA==.',
Im='Imadruid:BAAALgADCgQJBAAAAA==.',
In='Infinitepain:BAAALgAECgMJAwABLgAFFAUJIwATANEYAA==.',
Io='Iolyte:BAABLgAECn8XAAIBAAYJUQ0kEgCpAAABAAYJUQ0kEgCpAAAAAA==.',
Ir='Iridellis:BAACLgAFFH8SAAIFAAUJlwmVIwAxAQAFAAUJlwmVIwAxAQAuAAQKfyIAAgUACQn3Eo8XABkCAAUACQn3Eo8XABkCAAAA.',
Is='Ispankutank:BAAALgAFFAIJAgAAAA==.',
It='Itssofluffy:BAABLgAECn8vAAQiAAkJlBiLCABDAgAiAAkJDRiLCABDAgANAAUJBhfbEwAyAQATAAIJUgnYlQAqAAAAAA==.Itwon:BAAALgAECgUJEgAAAA==.',
Iz='Izzelda:BAAALgAECgEJAgAAAA==.',
Ja='Jacus:BAAALgAECgQJCQAAAA==.Jadaruk:BAAALgADCgEJAQAAAA==.Jahumc:BAAALgAECgEJAQAAAA==.Janeoftrades:BAAALgAECgYJDAAAAA==.Jaycers:BAABLgAECn8iAAQUAAkJ9SAZBQCiAgAUAAkJ8B8ZBQCiAgAKAAUJERzKmgBAAQAkAAEJ2AIAnwAqAAAAAA==.Jayclark:BAAALgADCgcJCgAAAA==.',
Je='Jessiriusrex:BAAALgADCgEJAQAAAA==.',
Jo='Joemomma:BAABLgAECn8UAAIBAAYJIw0ezwDzAAABAAYJIw0ezwDzAAAAAA==.Jokestarfist:BAABLgAECn8ZAAIKAAQJgRjSvAANAQAKAAQJgRjSvAANAQAAAA==.',
Jr='Jr:BAAALgAECgIJAgAAAA==.',
Jt='Jtheshadow:BAAALgAECgEJAQAAAA==.',
Ju='Juicebox:BAAALgADCgEJAQAAAA==.Jumpercables:BAAALgAECggJCQAAAA==.Junachan:BAAALgAECgMJBQAAAA==.Junior:BAAALgADCgEJAQAAAA==.Jurichan:BAAALgAECgMJCQAAAA==.',
['Jä']='Jägernaut:BAAALgADCgEJAQAAAA==.',
Ka='Kaitokit:BAAALgAFFAIJAwAAAA==.Kajamando:BAABLgAECn8eAAIRAAgJ7wcXLwANAQARAAgJ7wcXLwANAQAAAA==.Kalith:BAABLgAECn8YAAIVAAkJCgObMAAmAQAVAAkJCgObMAAmAQAAAA==.Kallydots:BAAALgADCgcJDQAAAA==.Kayllina:BAABLgAECn8lAAIWAAgJnwa1pAAlAQAWAAgJnwa1pAAlAQAAAA==.Kayotic:BAABLgAECn8kAAIRAAkJPQbQLQAUAQARAAkJPQbQLQAUAQAAAA==.Kayww:BAAALgAECgQJBwAAAA==.',
Ke='Keinarra:BAAALgADCgMJBgAAAA==.Kell:BAAALgADCgcJCAAAAA==.Kelmorphic:BAABLgAECn8tAAMhAAkJMyEAAgDyAgAhAAkJMyEAAgDyAgARAAEJ7QoPcgAsAAAAAA==.Keropikapika:BAAALgADCgUJBQAAAA==.Keynerashz:BAAALgADCgIJAgAAAA==.',
Kh='Khaali:BAAALgAECgEJBAAAAA==.Khristina:BAAALgAECgMJBAAAAA==.',
Ki='Kikiana:BAAALgAECgUJDAABLgAECggJLwAlAKQhAA==.Kikstyx:BAAALgADCgYJCAAAAA==.Killcommand:BAAALgAFFAIJAgABLgAFFAcJFQAYAAscAA==.Killerxd:BAABLgAECn8WAAIKAAgJJRhFagCaAQAKAAgJJRhFagCaAQAAAA==.Killesea:BAAALgADCgcJDAAAAA==.Kittfisto:BAABLgAECn8iAAQhAAkJmhVYFQACAQAGAAkJiBStXgCFAQAhAAQJ4BRYFQACAQARAAYJmAweNwDeAAAAAA==.',
Kn='Knitemare:BAAALgAECgEJAQAAAA==.',
Ko='Korivos:BAAALgADCgMJAwAAAA==.Kosmas:BAABLgAECn8gAAMPAAkJbiHXEwBTAgAPAAkJbh/XEwBTAgAOAAYJlRxxGgCHAQAAAA==.',
Kr='Kromwarr:BAAALgAECgcJBwAAAA==.Krushgar:BAABLgAECn8UAAMWAAcJsRcIXQDbAQAWAAcJsRcIXQDbAQAXAAEJsxCDPQArAAAAAA==.',
Ku='Kuchikopii:BAAALgADCgYJBgAAAA==.Kungfuelf:BAAALgADCgEJAQAAAA==.Kungpowchikn:BAAALgADCgUJBQAAAA==.Kurookami:BAAALgAECgEJAQAAAA==.',
Ky='Kyana:BAAALgADCgEJAQAAAA==.',
La='Lackluster:BAACLgAFFH8IAAIBAAMJYwHAmgCVAAABAAMJYwHAmgCVAAAuAAQKfykAAgEACQmuCeCnAC4BAAEACQmuCeCnAC4BAAAA.Lagg:BAAALgAECgIJAwABLgAECgUJEQACAAAAAA==.Lamatrick:BAAALgAECgUJBwAAAA==.Lanadelslayy:BAAALgAECgYJDwAAAA==.Lasenza:BAAALgADCgQJBAAAAA==.Lavacoomer:BAAALgADCgYJBQAAAA==.',
Ld='Ldg:BAAALgAFFAIJAgAAAA==.',
Le='Leafdaddy:BAABLgAFFH8IAAINAAMJHQp/CgCJAAANAAMJHQp/CgCJAAAAAA==.Ledana:BAAALgAECgIJAgAAAA==.Leenale:BAAALgAECgEJAQAAAA==.Lejosh:BAAALgAECgIJAgAAAA==.Lennon:BAAALgAECgkJBgAAAA==.Leona:BAAALgAECgYJCgAAAA==.Leonesk:BAAALgADCgQJAwAAAA==.Lethee:BAAALgAECgEJAgAAAA==.Lexazshara:BAAALgAECgEJAwAAAA==.',
Li='Lightingbolt:BAAALgAECgUJDAAAAA==.Lightlybaked:BAAALgAFFAEJAQAAAA==.Lilithamy:BAAALgADCgYJBgAAAA==.Lilthin:BAABLgAECn8cAAIBAAkJHgfWiABlAQABAAkJHgfWiABlAQAAAA==.Liore:BAAALgAECgQJBgAAAA==.Lisathe:BAAALgAECgYJEgAAAA==.Lithdrae:BAAALgADCgYJBgAAAA==.Littleddk:BAABLgAECn8UAAIWAAcJYRqCTgDXAQAWAAcJYRqCTgDXAQAAAA==.Littledude:BAAALgADCgQJBQAAAA==.Littlemorsel:BAABLgAECn8eAAISAAkJNxPoNgACAgASAAkJNxPoNgACAgAAAA==.Livelaughlov:BAAALgAECgEJAQAAAA==.',
Lo='Lombardio:BAAALgAECgEJAgAAAA==.Louthar:BAAALgADCgcJAQAAAA==.',
Ls='Lselec:BAAALgAECgQJBAAAAA==.',
Lt='Ltdapperdan:BAAALgAECgEJAQAAAA==.',
Lu='Lucens:BAABLgAECn8tAAIkAAgJSRcTAwBGAQAkAAgJSRcTAwBGAQAAAA==.Lunagreed:BAAALgADCgUJBQAAAA==.Lurchlock:BAAALgAECgYJBgABLgAFFAQJCQABAC4EAA==.Lurchn:BAACLgAFFH8JAAIBAAQJLgQmLgCJAAABAAQJLgQmLgCJAAAuAAQKf1UAAgEACQluERlcAMoBAAEACQluERlcAMoBAAAA.',
Ly='Lysariax:BAAALgAECgMJAwAAAA==.',
['Lï']='Lïght:BAACLgAFFH8HAAIKAAQJWiB3KABpAQAKAAQJWiB3KABpAQAuAAQKfxoAAgoACAmDJQ0NAPwCAAoACAmDJQ0NAPwCAAEuAAUUBQkYABcAliEA.',
['Lú']='Lúná:BAAALgAECgYJBwAAAA==.',
Ma='Maemae:BAAALgAECgcJDAAAAA==.Maggieaugers:BAACLgAFFH8HAAIIAAYJhQLcNgDoAAAIAAYJhQLcNgDoAAAuAAQKfykAAwgACAn3D8EwAHQBAAgACAn3D8EwAHQBAAcABAmPBbAvAG4AAAAA.Magicmech:BAAALgADCgcJDAAAAA==.Magivacano:BAAALgAECggJEgAAAA==.Mahnon:BAABLgAECn8aAAISAAkJowjGdQBUAQASAAkJowjGdQBUAQAAAA==.Mandril:BAAALgADCgEJAQAAAA==.Matas:BAABLgAECn8XAAIcAAkJxAOWOQAWAQAcAAkJxAOWOQAWAQAAAA==.Matias:BAAALgAECgEJAQAAAA==.Mazzikane:BAAALgAECgMJAwAAAA==.',
Mc='Mcdeath:BAAALgADCgIJAgAAAA==.',
Me='Medzly:BAAALgADCgYJEAAAAA==.Metalhedface:BAABLgAECn8iAAMOAAkJqRJcGgCHAQAOAAgJnhNcGgCHAQAPAAYJzhNURQAwAQAAAA==.',
Mi='Miixx:BAAALgAECgQJBQAAAA==.Mikecoxwall:BAACLgAFFH8HAAIBAAIJSgn3pwCDAAABAAIJSgn3pwCDAAAuAAQKfz4AAwEACQmTFVU8ACkCAAEACQmTFVU8ACkCACYABgnfCP0KACoBAAAA.Mikuru:BAAALgAECgEJAwAAAA==.Milena:BAAALgAECgEJAgAAAA==.Milov:BAAALgADCgUJBQAAAA==.Minarva:BAAALgAECgcJCgAAAA==.Mirazha:BAAALgADCgkJCQAAAA==.Misary:BAAALgAECgQJBwAAAA==.Mischeif:BAAALgAECgUJCwAAAA==.',
Mo='Mojomon:BAAALgADCgYJBgAAAA==.Moltganus:BAABLgAECn8hAAIdAAYJHAN15gCRAAAdAAYJHAN15gCRAAAAAA==.Monkeli:BAABLgAECn8cAAIPAAcJFxEUPwBIAQAPAAcJFxEUPwBIAQAAAA==.Monkitard:BAAALgAECgMJAwABLgAECgUJCAACAAAAAA==.Monkryn:BAAALgAECgUJCAABLgAFFAgJHAAWAJMZAA==.Monkup:BAABLgAFFH8MAAIcAAQJtwVaMgDfAAAcAAQJtwVaMgDfAAAAAA==.Moocifer:BAAALgAECgEJAQAAAA==.Moocifermoo:BAAALgAECgEJAgAAAA==.Moogrim:BAAALgADCgkJDgAAAA==.Moonsiand:BAACLgAFFH8YAAMSAAYJCQtvOgA4AQASAAYJjwpvOgA4AQAVAAQJHgPnHQDjAAAuAAQKfysABBIACQk3GqYoADwCABIACQn+FqYoADwCABUACAleEysOAOYBAAwAAQmqAV+ZABwAAAAA.Moosafur:BAACLgAFFH8HAAINAAMJwCQbCwBBAQANAAMJwCQbCwBBAQAuAAQKf0IAAw0ACQkMJTcBAFADAA0ACQkMJTcBAFADACIACQlbGgQIAFICAAAA.Mooshoe:BAAALgAECgEJAQAAAA==.Mor:BAAALgAECgIJBQAAAA==.Mordoly:BAAALgAECgYJBgAAAA==.Morphyr:BAAALgAECgYJCAAAAA==.Morrigån:BAAALgAECgIJAgAAAA==.Morvoult:BAAALgAECgEJAQAAAA==.Motgus:BAAALgAECgMJBQAAAA==.Mozzsticks:BAAALgAECgQJBAAAAA==.',
Ms='Mshottie:BAABLgAECn8YAAIKAAkJugbpwQAGAQAKAAkJugbpwQAGAQAAAA==.Msuysu:BAAALgAECgEJAQABLgAECgEJAwACAAAAAA==.',
Mt='Mtngrounds:BAAALgADCgIJAgAAAA==.',
Mu='Murdaa:BAAALgAECgMJBAAAAA==.Murkt:BAAALgAECgEJAQAAAA==.Mutuusami:BAAALgAECgEJAgAAAA==.',
Mx='Mx:BAAALgAECgcJDAAAAA==.',
My='Myraine:BAAALgAECgMJAwAAAA==.Mythdath:BAAALgADCgMJAwAAAA==.Mythlock:BAAALgAECgMJAwAAAA==.Myway:BAAALgADCggJCwAAAA==.',
Na='Naari:BAABLgAECn8aAAMPAAgJNxIvRQAxAQAPAAcJDREvRQAxAQAOAAEJLxl3bwBCAAAAAA==.Naniwa:BAAALgAECgEJAQABLgAFFAMJCgAEANgVAA==.Naoya:BAAALgADCgIJAgAAAA==.Narexia:BAABLgAECn9NAAIgAAkJTR83AwDXAgAgAAkJTR83AwDXAgAAAA==.Natureboyy:BAAALgAECgIJAwAAAA==.',
Ne='Nekuma:BAAALgAFFAIJAgABLgAFFAgJJAAXAEwcAA==.Nellaa:BAAALgAECgcJEAAAAA==.',
Ni='Nightfury:BAAALgAECgcJDQAAAA==.Nightrage:BAAALgADCgYJBgAAAA==.Niklous:BAAALgAECgEJAQABLgAECgQJBAACAAAAAA==.Niklus:BAAALgAECgEJAQAAAA==.Nissanaltima:BAAALgADCgYJCQAAAA==.Nithilis:BAABLgAECn8zAAIJAAkJAR5cCgCpAgAJAAkJAR5cCgCpAgAAAA==.',
No='Noee:BAAALgADCgUJBQAAAA==.Nokkiewae:BAAALgADCgcJEgAAAA==.Nomadic:BAAALgADCgkJCQAAAA==.Nool:BAAALgADCgYJBQAAAA==.Nople:BAABLgAECn8fAAIBAAgJGBZQewCBAQABAAgJGBZQewCBAQAAAA==.',
Nu='Nutellaa:BAABLgAFFH8FAAIWAAIJmBd/0ACQAAAWAAIJmBd/0ACQAAAAAA==.',
Ny='Nymueline:BAAALgADCgUJBQAAAA==.',
Ob='Obeastly:BAAALgAECgUJBQAAAA==.Obie:BAAALgAECgUJEQAAAA==.Oborax:BAECLgAFFH8OAAIKAAUJuQwJUgALAQAKAAUJuQwJUgALAQAuAAQKfygAAgoABwmcFw1wAI4BAAoABwmcFw1wAI4BAAAA.',
Od='Od:BAAALgAECgYJCAAAAA==.',
Ok='Okidokidude:BAAALgADCgkJDwABLgAFFAgJKQAEAJogAA==.Okiro:BAAALgAECgMJAwAAAA==.Okoru:BAAALgADCgIJAgAAAA==.',
Ol='Oliviabenson:BAAALgAFFAEJAQAAAA==.Oluun:BAAALgADCgQJBAAAAA==.',
Or='Orkun:BAAALgAECgEJAQAAAA==.',
Ot='Otmetka:BAAALgADCgcJAQAAAA==.',
Ow='Owensbeast:BAAALgADCgUJBQAAAA==.',
Pa='Palapal:BAAALgAECgYJDgAAAA==.Paldi:BAABLgAECn8WAAIKAAgJORnRKwB0AgAKAAgJORnRKwB0AgABLgAFFAMJBAACAAAAAA==.Paliboos:BAABLgAECn8UAAIKAAYJGQ81CgAEAQAKAAYJGQ81CgAEAQAAAA==.Papaozz:BAABLgAECn8qAAILAAcJ9Q01KABVAQALAAcJ9Q01KABVAQAAAA==.Parapox:BAAALgAECgEJAgAAAA==.Pariss:BAAALgAECgkJBwAAAA==.Pawcalypse:BAAALgAECgMJAwAAAA==.Paws:BAABLgAECn8ZAAITAAkJwg57JgCaAQATAAkJwg57JgCaAQAAAA==.',
Pe='Perelia:BAABLgAECn9aAAIFAAkJZhB5AQDiAQAFAAkJZhB5AQDiAQAAAA==.Pewpewqt:BAAALgAECgUJBwABLgAECggJOQAQABEXAA==.',
Pi='Piltraja:BAAALgAECgEJAgAAAA==.',
Pl='Plaguehammer:BAABLgAECn8eAAIWAAYJ6Av4wgD6AAAWAAYJ6Av4wgD6AAAAAA==.Playstationn:BAAALgADCgUJBQAAAA==.',
Pn='Pnwbambii:BAAALgADCgIJAgAAAA==.',
Po='Polarg:BAAALgAECgEJAgAAAA==.Pomni:BAAALgAECgMJAwAAAA==.Popcola:BAAALgADCgEJAQABLgAECgUJCQACAAAAAA==.Popopopopopo:BAAALgAFFAQJBAAAAA==.Portholio:BAAALgAECgYJBgAAAA==.',
Pp='Ppc:BAAALgAFFAEJAgABLgAFFAcJFQAYAAscAA==.',
Pu='Pubbles:BAABLgAECn8XAAQgAAkJ4SB6BwBVAgAgAAgJrCB6BwBVAgAEAAEJ1Qk42AAxAAADAAEJhgx3swAnAAAAAA==.Punizher:BAAALgAECgMJAwAAAA==.Purerage:BAAALgAECgYJDQAAAA==.',
Pv='Pvc:BAAALgAECgYJCQABLgAFFAcJFQAYAAscAA==.',
Py='Pyrella:BAAALgADCgEJAQABLgAECgcJEAACAAAAAA==.Pyyrha:BAAALgAECgMJAwAAAA==.Pyyrhadrood:BAAALgAECgMJAwAAAA==.Pyyrhanice:BAAALgAECgUJDgAAAA==.Pyyrhaspice:BAAALgADCgUJCQAAAA==.',
Qu='Quetzlcoatl:BAAALgADCgcJBwABLgAECgkJEgACAAAAAA==.',
Ra='Radiantharm:BAABLgAECn8VAAIkAAcJ0RLrAgBPAQAkAAcJ0RLrAgBPAQAAAA==.Raevalinaa:BAAALgAECgQJCwABLgAECggJQwABAPAaAA==.Raevelina:BAAALgAECgEJAQABLgAECggJQwABAPAaAA==.Raevelinaa:BAAALgAECgQJBwABLgAECggJQwABAPAaAA==.Rafeh:BAAALgAECgUJBwAAAA==.Raisedead:BAAALgAECgQJBgAAAA==.Ramian:BAAALgADCgMJAwAAAA==.Randzmannz:BAAALgAECgMJAwAAAA==.Raph:BAAALgAECgIJAgAAAA==.Rarelootboss:BAAALgADCgcJDAAAAA==.',
Re='Reason:BAABLgAECn8VAAMQAAgJQxacUgBcAQAQAAcJzhacUgBcAQATAAEJewjAkwArAAAAAA==.Redbaer:BAAALgADCgUJBQAAAA==.Renair:BAAALgADCgMJAwAAAA==.Renoitukax:BAABLgAECn82AAMJAAkJwxt+DACKAgAJAAkJwxt+DACKAgAFAAYJJhuXHADpAQAAAA==.Restorn:BAAALgADCgcJCgAAAA==.Retrobution:BAAALgAECgEJBAAAAA==.Retussy:BAAALgADCgEJAQAAAA==.Reynard:BAABLgAECn8WAAIGAAcJLxHYbQBHAQAGAAcJLxHYbQBHAQAAAA==.Rezz:BAACLgAFFH8TAAIBAAcJLg/tPAB5AQABAAcJLg/tPAB5AQAuAAQKfyAAAgEACQmQHIgpAM0CAAEACQmQHIgpAM0CAAAA.',
Rh='Rhode:BAAALgAECgIJAwAAAA==.Rhohir:BAAALgADCgIJAgAAAA==.',
Ri='Ridic:BAAALgADCgMJAwAAAA==.Rigour:BAAALgADCgMJAwAAAA==.Rishiun:BAAALgADCgEJAQAAAA==.Rivers:BAABLgAECn8UAAIOAAcJhQpgNQDwAAAOAAcJhQpgNQDwAAAAAA==.',
Ro='Rocketpop:BAAALgADCgIJAgAAAA==.Rosiegirl:BAAALgAECgMJAwAAAA==.Roxas:BAAALgAECgcJDQAAAA==.',
Ry='Ryzen:BAAALgAECgYJDQAAAA==.',
Sa='Salaelana:BAAALgADCgcJCQAAAA==.Saltzpyre:BAAALgADCgYJBAAAAA==.Sanasrindis:BAAALgAECgMJBAAAAA==.Saninar:BAAALgAECgcJDAAAAA==.Sausagepizza:BAAALgADCgYJAwAAAA==.',
Sc='Schezmu:BAAALgAECgIJAgAAAA==.Scruffknight:BAAALgAECgcJDQAAAA==.Scrufies:BAACLgAFFH8RAAILAAQJ4RJtCwDZAAALAAQJ4RJtCwDZAAAuAAQKfx0AAgsACQmbFuETAAQCAAsACQmbFuETAAQCAAAA.',
Se='Seisappho:BAAALgADCgMJAwAAAA==.Senorfiesta:BAAALgAECgQJBAAAAA==.Sephiroth:BAAALgADCgEJAQAAAA==.Serenade:BAABLgAECn8WAAMGAAcJAw97eAAwAQAGAAcJAw97eAAwAQAhAAEJwgZJPQAaAAAAAA==.Serenityboop:BAAALgADCgYJCQAAAA==.Sergnocchi:BAAALgAECgcJEAAAAA==.Serys:BAABLgAECn8XAAIeAAgJEAmoAgDUAAAeAAgJEAmoAgDUAAAAAA==.Sethour:BAAALgADCgQJBAAAAA==.',
Sh='Shadowfangs:BAAALgAECgMJAwAAAA==.Shaee:BAAALgADCgkJDwAAAA==.Shalthender:BAAALgADCgUJBQAAAA==.Shamans:BAABLgAECn8dAAIDAAcJLx+kHAD8AQADAAcJLx+kHAD8AQAAAA==.Shamncheese:BAABLgAECn8WAAIEAAgJ6gxXYgA1AQAEAAgJ6gxXYgA1AQABLgAECgUJEQACAAAAAA==.Shamorcc:BAAALgADCgQJBAAAAA==.Shasta:BAACLgAFFH8pAAINAAYJbiWdAgAXAgANAAYJbiWdAgAXAgAuAAQKfygAAg0ACAlZJW8BAEEDAA0ACAlZJW8BAEEDAAAA.Shaulthariel:BAAALgAECgEJAQAAAA==.Shioz:BAAALgADCgQJBgAAAA==.Shisuiuchiha:BAABLgAECn8lAAIBAAgJewhTEwCdAAABAAgJewhTEwCdAAAAAA==.Shoiz:BAAALgAECgQJBQAAAA==.Shon:BAAALgAECgEJAQAAAA==.Shootumup:BAAALgAECgkJEgAAAA==.Shootybithc:BAAALgADCgEJAQAAAA==.Shuhari:BAAALgAECgkJEwAAAQ==.Shyx:BAABLgAECn8tAAIFAAgJ0hoVAQAbAgAFAAgJ0hoVAQAbAgAAAA==.',
Si='Siilas:BAACLgAFFH8aAAQdAAQJNgkbZgD6AAAdAAQJnQcbZgD6AAAaAAEJhw9oKQBEAAAeAAIJ7QC3LAAyAAAuAAQKfyoAAx0ACQljF7YqAC8CAB0ACQljF7YqAC8CAB4ABAlQBwFBALEAAAAA.Simplèjack:BAAALgAECgMJAwABLgAFFAMJBgAEABQGAA==.Sinamon:BAABLgAECn8xAAIKAAgJGSGyJAByAgAKAAgJGSGyJAByAgAAAA==.Sinani:BAABLgAECn83AAIBAAkJFAcgiABnAQABAAkJFAcgiABnAQAAAA==.Sinista:BAAALgAECgUJBQAAAA==.Sinnamon:BAAALgAECgYJEgABLgAECggJMQAKABkhAA==.Sipnspin:BAAALgAECgEJAgAAAA==.',
Sj='Sjdh:BAABLgAECn8XAAIGAAcJnBLVawBMAQAGAAcJnBLVawBMAQABLgAECgkJMQALADAUAA==.Sjrogue:BAABLgAECn8xAAILAAkJMBRhEwAJAgALAAkJMBRhEwAJAgAAAA==.',
Sk='Skjolvarn:BAEALgAECgMJBwAAAA==.Skram:BAAALgAECgMJBAAAAA==.',
Sl='Slammydooker:BAABLgAECn8fAAMLAAkJ0hV2EwAIAgALAAkJ0hV2EwAIAgAjAAEJ1QcMIQAtAAAAAA==.Slammyhole:BAAALgAECgEJAQAAAA==.Sleeptoken:BAAALgAECgMJCAAAAA==.Slyphz:BAAALgAECgYJBgAAAA==.',
Sm='Smallkat:BAAALgAECgEJAQAAAA==.Smightymouse:BAAALgAECgEJAQAAAA==.',
Sn='Snoipuh:BAAALgAECgUJBwAAAA==.',
So='Solas:BAAALgAECgQJBwAAAA==.Soletaken:BAAALgADCggJDwAAAA==.Solio:BAAALgADCgYJFQAAAA==.Solisha:BAAALgAECgQJBAAAAA==.Somberdh:BAAALgADCgcJBwAAAA==.Sonofsand:BAAALgAECgIJAgAAAA==.Soulja:BAAALgADCgEJAgAAAA==.Soulmoethus:BAAALgADCgYJCQAAAA==.',
Sp='Sprayandpray:BAABLgAECn8aAAIBAAUJqh3GjgBaAQABAAUJqh3GjgBaAQAAAA==.Sprinklely:BAAALgADCgcJCgAAAA==.',
Sq='Squidnips:BAAALgAECgEJAgAAAA==.Squirtney:BAAALgADCgMJAwAAAA==.',
Ss='Ss:BAACLgAFFH8PAAIeAAMJjQGaFQCPAAAeAAMJjQGaFQCPAAAuAAQKfxUAAh4ABwlxDOEWAO0AAB4ABwlxDOEWAO0AAAAA.Ssl:BAAALgADCgQJBAAAAA==.',
St='Starrwood:BAABLgAECn8pAAISAAkJhQzdCwD7AAASAAkJhQzdCwD7AAAAAA==.Statik:BAAALgAECgIJAwAAAA==.Statík:BAAALgAECgEJAQABLgAECgIJAwACAAAAAA==.Stepmonk:BAAALgAECgEJAQAAAA==.Stevesharts:BAAALgADCgYJCwAAAA==.Stonedlock:BAAALgADCgcJCAAAAA==.Stonetusk:BAAALgAECgUJCQAAAA==.Stormkeg:BAAALgADCggJCAAAAA==.Stroya:BAAALgAECgUJBgAAAA==.',
Su='Sumnèr:BAAALgAECgcJBwAAAA==.Sunastiri:BAAALgADCgkJDAAAAA==.Sunpali:BAAALgAECgcJCwAAAA==.',
Sw='Swank:BAAALgADCgEJAQAAAA==.',
Sx='Sx:BAAALgADCgIJAgAAAA==.',
Sy='Syaa:BAAALgAECgYJBQAAAA==.Syberis:BAAALgADCgcJDgAAAA==.',
Ta='Tacholy:BAABLgAECn8VAAIKAAkJzBdQaACeAQAKAAkJzBdQaACeAQABLgAECgkJLwAOAJQcAA==.Tacodaboss:BAABLgAECn8XAAIRAAYJLw+bMwDzAAARAAYJLw+bMwDzAAAAAA==.Talelarissia:BAAALgADCgQJBAAAAA==.Talonflame:BAABLgAECn8fAAIVAAkJBBy6BwB4AgAVAAkJBBy6BwB4AgAAAA==.Tansu:BAAALgAECgYJEwAAAA==.Tapered:BAAALgAECgUJCQAAAA==.Taupo:BAACLgAFFH8ZAAIYAAQJ6x8EIgBeAQAYAAQJ6x8EIgBeAQAuAAQKfycAAhgACQlyH6kNAHoCABgACQlyH6kNAHoCAAAA.',
Tb='Tbanger:BAAALgAECgYJDwAAAA==.Tbh:BAAALgAFFAEJAgABLgAFFAcJFQAYAAscAA==.',
Te='Techevo:BAAALgAECgQJBQAAAA==.Techfire:BAABLgAECn8pAAInAAkJ9hpAAgBFAgAnAAkJ9hpAAgBFAgAAAA==.Techsmexx:BAAALgAECgMJBQAAAA==.Tempina:BAAALgADCgkJCwAAAA==.Tenebron:BAABLgAECn8vAAIoAAYJQBISJwD6AAAoAAYJQBISJwD6AAAAAA==.Tenlucis:BAAALgAECggJDAAAAA==.',
Th='Thaelyssa:BAAALgAECgEJAQAAAA==.Tharria:BAAALgADCgcJBwAAAA==.Thearia:BAABLgAECn8bAAMQAAgJrRWBUgBcAQAQAAgJrRWBUgBcAQATAAUJmg5nVgC3AAAAAA==.Thecanmurk:BAAALgADCgkJEgAAAA==.Thedilf:BAAALgADCgEJAQAAAA==.Thicktotem:BAAALgAECgIJAgAAAA==.Thickumz:BAAALgAECgMJCgAAAA==.Thisismeta:BAAALgAECgYJDAAAAA==.Thorenis:BAAALgADCgEJAQAAAA==.Thoryndruid:BAACLgAFFH8TAAIiAAYJBB3GAgCoAQAiAAYJBB3GAgCoAQAuAAQKfzIAAyIACQkWIxEDAA4DACIACQnmIhEDAA4DAA0ABwm8HlYNAAwCAAEuAAUUCAkcABYAkxkA.Thorïn:BAAALgADCgMJAwAAAA==.Thorýn:BAACLgAFFH8cAAIWAAgJkxnKFwAhAgAWAAgJkxnKFwAhAgAuAAQKfxoAAhYACAl8HuMqAFUCABYACAl8HuMqAFUCAAAA.Thórin:BAABLgAECn8oAAIUAAgJQxciDwDRAQAUAAgJQxciDwDRAQAAAA==.',
Ti='Timakk:BAAALgADCgEJAQAAAA==.Tipsy:BAABLgAECn8uAAMEAAkJWg/0OADMAQAEAAkJWg/0OADMAQADAAMJpA3ddwCGAAAAAA==.',
To='Tombraider:BAAALgAECgUJCAAAAA==.Tomfoolary:BAAALgAECgEJAwAAAA==.Toofy:BAAALgAECgEJAQAAAA==.Tot:BAAALgAECgkJDQAAAA==.Total:BAAALgADCgkJDAAAAA==.Totembear:BAAALgAECgYJCQABLgAFFAIJBwATABUFAA==.',
Tr='Trallanir:BAAALgAECgQJBAAAAA==.Tralleth:BAABLgAECn8nAAMIAAkJIRUQAgBMAQAIAAgJCRQQAgBMAQAHAAIJvQ3mMABmAAAAAA==.Trid:BAAALgAECgQJBgAAAA==.Trillbilly:BAAALgAECgEJAQAAAA==.Trinora:BAAALgADCgkJDgAAAA==.Troginator:BAAALgAECgEJAQAAAA==.Trolltard:BAAALgAECgIJAgABLgAECgUJCAACAAAAAA==.Troxa:BAAALgAECgUJCgAAAA==.',
Tu='Tuckard:BAAALgADCgEJAQAAAA==.Tuskor:BAAALgAFFAIJAgAAAA==.',
Tw='Twinklord:BAAALgAECgkJDwAAAA==.',
Ty='Tylanar:BAAALgAECgYJBgAAAA==.Tylolight:BAAALgADCgMJAwAAAA==.Tylomist:BAAALgAECgUJBQAAAA==.Tylototem:BAAALgAFFAEJAgAAAA==.',
['Tö']='Tötem:BAAALgAFFAEJAQABLgAFFAUJGAAXAJYhAA==.',
Ug='Uglyboi:BAAALgAECggJDwAAAA==.',
Uj='Ujcmonk:BAAALgAECgQJBAAAAA==.',
Ul='Ullbian:BAAALgADCgMJAwAAAA==.Ultramar:BAAALgADCgEJAQAAAA==.',
Un='Uncookedham:BAAALgAECgQJCwAAAA==.Unholyghost:BAAALgAECgEJAQAAAA==.',
Ur='Urgh:BAABLgAECn8fAAIJAAkJ9RHLIwCrAQAJAAkJ9RHLIwCrAQAAAA==.Urk:BAAALgAECgYJBgAAAA==.Urzaa:BAAALgAECgEJAwABLgAECgMJBAACAAAAAA==.',
Ut='Uthur:BAAALgAECgMJAwAAAA==.',
Va='Vaeelrundor:BAAALgAECgcJDwAAAA==.Valethales:BAAALgADCgcJBwAAAA==.Valyr:BAAALgAECgEJAQAAAA==.Vanillaface:BAABLgAECn8ZAAIKAAkJ7xzWHQCTAgAKAAkJ7xzWHQCTAgAAAA==.Vape:BAABLgAECn8WAAIdAAcJLg20egBEAQAdAAcJLg20egBEAQABLgAFFAUJEgASAMYbAA==.',
Ve='Veinripp:BAAALgADCgUJBQABLgAECggJNAAGAO0QAA==.Velarael:BAABLgAECn8rAAIdAAcJ9QsIjAAiAQAdAAcJ9QsIjAAiAQAAAA==.Velaryn:BAAALgADCgIJAgAAAA==.Veldar:BAAALgADCgIJAgABLgAECgUJBgACAAAAAA==.Velekete:BAAALgADCgUJBQAAAA==.Velethei:BAABLgAECn8YAAIQAAYJlySkGQBrAgAQAAYJlySkGQBrAgAAAA==.Velian:BAAALgADCgMJBAAAAA==.Velielyn:BAAALgADCgQJBAAAAA==.Vellareth:BAAALgAECgEJAQAAAA==.Vellarria:BAAALgADCgEJAQAAAA==.Verdesalsa:BAAALgAECgcJDQAAAA==.Verox:BAAALgADCgMJAwAAAA==.Verzak:BAAALgAECgUJBQAAAA==.Vexoris:BAAALgAECgIJAgAAAA==.',
Vh='Vheckxus:BAACLgAFFH8FAAIDAAIJAA1YSABtAAADAAIJAA1YSABtAAAuAAQKfxoAAgMABgloFAJAADQBAAMABgloFAJAADQBAAAA.',
Vi='Vicv:BAABLgAECn8TAAIJAAkJXwwXNABIAQAJAAkJXwwXNABIAQAAAA==.Vivy:BAAALgAECgcJBwAAAA==.',
Vo='Voidberg:BAAALgAECgkJEwAAAA==.',
['Vê']='Vêa:BAAALgADCgkJCQAAAA==.',
Wa='Wachonaso:BAACLgAFFH8TAAIdAAcJwwynNgBuAQAdAAcJwwynNgBuAQAuAAQKfy0AAx0ABwlJH6M0ADkCAB0ABwkrH6M0ADkCAB4ABgl8HlgXAI8BAAAA.Wanbahl:BAAALgADCgMJAwAAAA==.',
We='Wellburt:BAAALgAECgEJAQAAAA==.',
Wh='Whatuphuz:BAAALgADCgQJBQAAAA==.Wheresmyjaw:BAACLgAFFH8iAAQdAAUJJSAZPgBVAQAdAAUJmh4ZPgBVAQAaAAEJWSPAFQBnAAAeAAEJOQLaLAAxAAAuAAQKfycABB0ACAnyIe0WAJoCAB0ACAnyIe0WAJoCAB4AAgm6DiRSAHcAABoAAQnAILYvAF8AAAAA.',
Wi='Wildstàr:BAAALgADCgMJAwAAAA==.Wildthree:BAABLgAECn8rAAMZAAkJwh0HCgCjAgAZAAkJwh0HCgCjAgAcAAMJ2RQvYgC5AAAAAA==.Willenda:BAAALgAECgEJAwAAAA==.Willowins:BAAALgAECgEJAQAAAA==.Winterstired:BAACLgAFFH8kAAIlAAQJRiarCQCyAQAlAAQJRiarCQCyAQAuAAQKf0IAAyUACQnuJIMCAHkDACUACQnuJIMCAHkDAAUAAQlKF1xyAEQAAAAA.',
Wo='Woen:BAAALgADCggJCQAAAA==.Wolf:BAAALgAECgQJBwAAAA==.Wollffie:BAAALgAECgQJBAAAAA==.',
Wu='Wuinn:BAAALgAFFAEJAQAAAA==.Wut:BAAALgADCgcJBwAAAA==.',
Wy='Wynterswrath:BAAALgAECgcJDQAAAA==.',
['Wõ']='Wõnderful:BAACLgAFFH8FAAIQAAMJbhTiEgBlAAAQAAMJbhTiEgBlAAAuAAQKfxoAAhAABwk+G9skACUCABAABwk+G9skACUCAAEuAAUUBQkYABcAliEA.',
Xc='Xclobber:BAAALgADCgIJAgAAAA==.',
Xe='Xemnass:BAAALgAECgUJBwAAAA==.Xexus:BAAALgAECgEJAQAAAA==.',
Xi='Xillas:BAAALgADCgUJBQAAAA==.Xinadmh:BAAALgAECgMJAwAAAA==.',
Xo='Xoverkll:BAAALgAECgYJDAAAAA==.',
Xy='Xylina:BAAALgADCgEJAQAAAA==.Xyrii:BAAALgADCgEJAQAAAA==.',
Ya='Yadder:BAAALgAECgIJBAABLgAFFAQJCgALAGQRAA==.Yahro:BAACLgAFFH8RAAIKAAYJtQ8fRAAjAQAKAAYJtQ8fRAAjAQAuAAQKfzMAAgoACQkqIKoOAPACAAoACQkqIKoOAPACAAAA.Yamelow:BAAALgAECgQJBwAAAA==.',
Ye='Yeahiknow:BAAALgADCgkJDgAAAA==.Yeling:BAAALgAECgIJAgAAAA==.Yep:BAAALgAECgcJBwAAAA==.',
Yi='Yiska:BAAALgADCgcJBwAAAA==.',
Yn='Ynaguinid:BAAALgADCgEJAQAAAA==.',
Yo='Yoriale:BAAALgAECgYJDgAAAA==.Yotoymuerto:BAAALgAECgQJBAAAAA==.',
Za='Zafra:BAAALgADCgEJAQAAAA==.Zaimara:BAAALgAECgEJBgAAAA==.Zalind:BAABLgAECn8VAAIdAAkJCxJoZgCYAQAdAAkJCxJoZgCYAQAAAA==.Zalvianna:BAABLgAECn8iAAMBAAgJLQRRxAADAQABAAgJLQRRxAADAQAmAAEJXQHIIgAYAAAAAA==.Zarathoz:BAAALgAECgEJAQAAAA==.Zarindlina:BAAALgADCgUJBQAAAA==.Zarshx:BAAALgAECgYJCwABLgAFFAMJBAACAAAAAA==.',
Ze='Zemonk:BAAALgAECgYJBgAAAA==.',
Zi='Zilong:BAAALgAFFAEJAQABLgAFFAUJDwAGAAEaAA==.Zilongmage:BAAALgAFFAIJAwABLgAFFAUJDwAGAAEaAA==.Zilongwar:BAAALgAFFAMJAwABLgAFFAUJDwAGAAEaAA==.Zinnia:BAAALgADCgEJAgAAAA==.',
Zo='Zonedk:BAABLgAECn8WAAQXAAYJfB92EwBEAQAbAAUJQCFnHwBaAQAXAAYJLBZ2EwBEAQAWAAEJxBc3YgFBAAABLgAFFAIJAwACAAAAAA==.Zonerg:BAAALgADCgEJAgABLgAFFAIJAwACAAAAAA==.Zonevn:BAAALgAFFAIJAwAAAA==.Zordak:BAAALgADCgcJCAAAAA==.Zosin:BAAALgAECgIJAgAAAA==.',
Zu='Zugzugzapzap:BAAALgADCgEJAQAAAA==.',
Zx='Zx:BAAALgAECgUJBgAAAA==.',
Zy='Zylphanae:BAAALgAECgQJBAAAAA==.',
['Øl']='Ølaf:BAAALgAECgEJAQABLgAFFAQJGQAYAOsfAA==.',
['Ør']='Ørsted:BAAALgAECgEJAgABLgAFFAQJGQAYAOsfAA==.',
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
