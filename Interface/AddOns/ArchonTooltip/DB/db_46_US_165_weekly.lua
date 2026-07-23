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

local lookup = {'Mage-Frost','Unknown-Unknown','Shaman-Elemental','Shaman-Restoration','Priest-Discipline','DemonHunter-Devourer','Hunter-BeastMastery','Paladin-Retribution','Evoker-Preservation','Evoker-Augmentation','Priest-Shadow','Hunter-Marksmanship','Rogue-Subtlety','Druid-Guardian','Warrior-Arms','Warrior-Fury','Druid-Restoration','DemonHunter-Havoc','Druid-Balance','Paladin-Protection','Hunter-Survival','DeathKnight-Unholy','DeathKnight-Frost','Monk-Mistweaver','Monk-Windwalker','Warlock-Affliction','DeathKnight-Blood','Monk-Brewmaster','Warlock-Demonology','Warlock-Destruction','Evoker-Devastation','Shaman-Enhancement','DemonHunter-Vengeance','Druid-Feral','Rogue-Assassination','Paladin-Holy','Priest-Holy','Mage-Arcane','Mage-Fire','Warrior-Protection',}
local provider = {region='US',realm='Nazjatar',name='US',type='weekly',zone=46,date='2026-07-19',data={Aa='Aaela:BAAALgADCgUJBQAAAA==.',
Ab='Abrasaxs:BAABLgAECn8qAAIBAAgJQhijWQDQAQABAAgJQhijWQDQAQAAAA==.Absylus:BAAALgAECgQJBAABLgAFFAMJBAACAAAAAA==.',
Ac='Accoli:BAAALgAFFAEJAQAAAA==.Ackerman:BAAALgAECgYJCgABLgAECggJEgACAAAAAA==.Acraea:BAABLgAECn8hAAIBAAgJmwwuhABvAQABAAgJmwwuhABvAQAAAA==.Acràea:BAAALgAFFAEJAQAAAA==.Acslater:BAAALgAECgQJDQAAAA==.Actionman:BAAALgAECgkJBwAAAA==.',
Ad='Adversary:BAAALgAFFAIJAgAAAA==.',
Ag='Agoobagoo:BAACLgAFFH8gAAMDAAcJnB3MDQDOAQADAAcJnB3MDQDOAQAEAAEJ6yERNQBlAAAuAAQKfyMAAgMACQnZIpAEAFIDAAMACQnZIpAEAFIDAAAA.',
Ai='Aionn:BAAALgAECgMJAwAAAA==.Airrow:BAABLgAECn8UAAIFAAkJEhk3EABuAgAFAAkJEhk3EABuAgAAAA==.Aissae:BAACLgAFFH8PAAIGAAQJ7hwUOQBAAQAGAAQJ7hwUOQBAAQAuAAQKfy0AAgYACAlEJHYLACYDAAYACAlEJHYLACYDAAAA.Aiyama:BAAALgADCgQJBAAAAA==.',
Ak='Akiio:BAAALgAECgMJAwAAAA==.Akumaxl:BAAALgAECgYJBwAAAA==.',
Al='Alexia:BAAALgAECgEJAQAAAA==.Alfrank:BAAALgAECgIJAwAAAA==.Aliasx:BAAALgAECgMJBAAAAA==.Allwrong:BAAALgAECgUJBgAAAA==.Alphadog:BAEBLgAFFH8FAAIHAAMJ4wp9MADOAAAHAAMJ4wp9MADOAAABLgAFFAUJDgAIALkMAA==.Alphrank:BAAALgAECgEJAgAAAA==.Alurie:BAAALgAECgcJDAAAAA==.Alustre:BAAALgAFFAEJAQAAAA==.',
Am='Amahlfarouk:BAAALgAECgEJAQAAAA==.Amandrada:BAAALgAFFAEJAQAAAA==.Ambros:BAAALgADCgYJBgAAAA==.Aminatou:BAAALgAECgYJBwAAAA==.',
An='Angerfang:BAAALgADCgUJCgAAAA==.Angriff:BAAALgAECgEJAgAAAA==.Anheeboan:BAAALgAECgYJCwAAAA==.Anihilated:BAAALgADCgYJBwAAAA==.',
Ar='Aradiax:BAAALgADCgYJBgAAAA==.Arathion:BAAALgAECgIJAgAAAA==.Arcadavia:BAAALgADCgMJAwAAAA==.Aren:BAAALgAECgYJEgAAAA==.Ariaprime:BAABLgAECn8cAAIBAAcJQRZ2DQBVAQABAAcJQRZ2DQBVAQAAAA==.Ariseigris:BAAALgAECgIJAgAAAA==.Arjentheilus:BAAALgAECgMJAwAAAA==.Armandox:BAAALgAECgEJAQAAAA==.Arthasl:BAAALgADCgMJAgAAAA==.Arthur:BAAALgAECgQJDgAAAA==.',
As='Asasda:BAAALgADCgMJBAAAAA==.Ashaelra:BAAALgAECgYJCAAAAA==.Astravaritan:BAAALgADCgMJAwAAAA==.Astrá:BAAALgAECgYJEQABLgAECgUJEQACAAAAAA==.',
At='Atherya:BAAALgAECgYJCAAAAA==.Atomixblonde:BAAALgAECgQJBAAAAA==.',
Au='Augonly:BAACLgAFFH8eAAIJAAcJQxdhCgAFAgAJAAcJQxdhCgAFAgAuAAQKfyMAAgkACQnpIC4GAOECAAkACQnpIC4GAOECAAAA.Augy:BAACLgAFFH8OAAIKAAQJMg0rNwDoAAAKAAQJMg0rNwDoAAAuAAQKfx0AAwoACQkyGvMcAO8BAAoACAnlGPMcAO8BAAkAAQmSBOk+ACkAAAAA.Autoshot:BAAALgAFFAIJAgAAAA==.',
Av='Averisbelia:BAAALgAECgYJCwAAAA==.',
Ay='Ayowamsley:BAAALgADCgMJAwAAAA==.',
Az='Azalea:BAAALgAECggJEAABLgAECgkJCgACAAAAAA==.',
Ba='Babycrock:BAAALgADCgYJBgAAAA==.Back:BAAALgADCgcJDAAAAA==.Bakihanma:BAAALgAECgQJBgAAAA==.Balash:BAAALgADCgUJBQAAAA==.Balerion:BAAALgADCgEJAQABLgADCgMJAwACAAAAAA==.Balthasar:BAABLgAECn8nAAILAAkJExpYDwBkAgALAAkJExpYDwBkAgAAAA==.Banjobits:BAAALgADCgIJAgAAAA==.Barhead:BAAALgAECgYJDAAAAA==.Barlow:BAABLgAECn8UAAIMAAkJUQhUFwD5AAAMAAkJUQhUFwD5AAAAAA==.Barqose:BAAALgADCgMJAwAAAA==.Barryberry:BAABLgAECn8fAAIIAAkJDRE0fgByAQAIAAkJDRE0fgByAQAAAA==.Barryx:BAAALgAECgIJAgAAAA==.',
Bb='Bbldrizzy:BAABLgAFFH8GAAMEAAMJjR5+PQDuAAAEAAMJjR5+PQDuAAADAAEJyRD3LwA9AAABLgAFFAQJDAANAGQRAA==.',
Be='Bearful:BAAALgADCgMJAwAAAA==.Beastlieduke:BAAALgAECgMJAwABLgAFFAcJFwALAKQNAA==.Beastlièduke:BAACLgAFFH8XAAILAAcJpA0dEgBXAQALAAcJpA0dEgBXAQAuAAQKfzQAAgsACQkfIE8MAIsCAAsACQkfIE8MAIsCAAAA.Beauslay:BAAALgAECgEJAQAAAA==.Belephon:BAAALgAECgYJEAAAAA==.Belinda:BAAALgAECgUJBQAAAA==.Bellaruhbz:BAABLgAECn8eAAIMAAkJjA+0FwD1AAAMAAkJjA+0FwD1AAAAAA==.Berenstain:BAABLgAECn8nAAIOAAkJShP8FwCSAQAOAAkJShP8FwCSAQAAAA==.Bergmire:BAAALgAECgQJCwAAAA==.Berple:BAAALgADCgUJBQABLgAFFAkJGwABAMghAA==.Bestoresto:BAABLgAECn8XAAIEAAkJBQwTRACdAQAEAAkJBQwTRACdAQAAAA==.',
Bh='Bhori:BAAALgAECgEJAwAAAA==.',
Bi='Bibahabibi:BAABLgAECn8dAAMPAAYJxhvpJQA5AQAPAAYJxhvpJQA5AQAQAAMJzQiVhwChAAAAAA==.Bighunt:BAAALgAECgEJAQAAAA==.Bigpapax:BAAALgAECgEJAQAAAA==.Bigtac:BAABLgAECn8vAAMPAAkJlBxYCQBbAgAPAAkJlBxYCQBbAgAQAAIJ3gc5mQBcAAAAAA==.Bimmylee:BAAALgAFFAEJAgAAAA==.Binggus:BAAALgAFFAEJAQAAAA==.Bipolaire:BAAALgADCgEJAQAAAA==.',
Bl='Blabbybootze:BAAALgAECgkJDwAAAA==.Bladelight:BAAALgAECgYJCAAAAA==.Blighte:BAAALgADCgQJBAABLgAECggJIQARAIIkAA==.Blightfangs:BAACLgAFFH8MAAIBAAMJjBBQNgDUAAABAAMJjBBQNgDUAAAuAAQKf0kAAgEACQnyGo80AEYCAAEACQnyGo80AEYCAAAA.Blindnautdef:BAABLgAECn80AAMGAAgJ7RAeagBRAQAGAAgJ7RAeagBRAQASAAEJ9gPefgAhAAAAAA==.Bloodluna:BAAALgADCgUJBQAAAA==.',
Bo='Bobman:BAAALgAECgUJCAAAAA==.Bodakye:BAACLgAFFH8QAAIHAAMJOhLeaADTAAAHAAMJOhLeaADTAAAuAAQKfyYAAwcACQlBG1IuACMCAAcACQlBG1IuACMCAAwAAgm0ARCBAEMAAAAA.Bonargrowrod:BAABLgAECn8cAAIIAAkJCAffFQD6AAAIAAkJCAffFQD6AAAAAA==.Bonkz:BAAALgAECgMJAwAAAA==.Boomtip:BAAALgADCgMJAwAAAA==.Boon:BAAALgADCgYJCQAAAA==.Bordolor:BAAALgAECgEJAQAAAA==.Bowsa:BAAALgAECgkJAQAAAA==.',
Br='Bracalina:BAAALgAECgcJDAABLgAFFAIJCgABAEUOAA==.Brethathes:BAAALgAECgkJEgAAAA==.Brudda:BAAALgADCgUJBQAAAA==.',
Bu='Bubbaray:BAAALgAECgMJAwAAAA==.Bubblebun:BAAALgAECgMJBgAAAA==.Bungerhole:BAABLgAECn8WAAMRAAgJxRtRMADhAQARAAgJxRtRMADhAQATAAEJEQllmwAmAAAAAA==.Butane:BAAALgADCgIJAgAAAA==.Buzzbuzz:BAAALgAECgIJBwAAAA==.',
Ca='Caeruleus:BAAALgAECgEJAgAAAA==.Cainn:BAAALgAECgYJBwAAAA==.Cap:BAAALgADCgEJAQABLgAFFAUJGwABAGIeAA==.Capriestsun:BAAALgAFFAMJAwABLgAFFAQJDAANAGQRAA==.Captyn:BAABLgAECn8cAAIUAAgJug2FGgBEAQAUAAgJug2FGgBEAQAAAA==.Carridin:BAAALgADCgMJAwAAAA==.Cass:BAAALgAECgEJAQAAAA==.',
Ce='Cernunon:BAAALgADCgEJAQAAAA==.Ceroquel:BAAALgAECgMJAwAAAA==.',
Ch='Chaosdemon:BAABLgAECn81AAIGAAkJPRDIRQC1AQAGAAkJPRDIRQC1AQAAAA==.Chaosraven:BAAALgADCgkJCQAAAA==.Chapelgnome:BAAALgAECgUJCQABLgAFFAYJBwAKAIUCAA==.Charizardx:BAAALgAECgEJAQAAAA==.Charlottea:BAAALgAECgYJDwAAAA==.Chemdra:BAAALgAECgcJEwAAAA==.Chiling:BAAALgAECgEJAQAAAA==.Chipmonkey:BAAALgAECgEJAgABLgAECgkJNAARAMEPAA==.Chiptime:BAABLgAECn80AAIRAAkJwQ94NwC6AQARAAkJwQ94NwC6AQABLgAECgkJNAARAMEPAA==.Chomby:BAAALgAECgQJAwAAAA==.Chromosomes:BAAALgAECgQJBAAAAA==.Chud:BAAALgAECgQJCQAAAA==.Chudsworth:BAAALgADCgYJCQAAAA==.Chunguhlumpo:BAAALgAECgEJBAAAAA==.Chzburger:BAAALgAFFAEJAQAAAA==.',
Ci='Cinnamóróll:BAABLgAECn9SAAIVAAkJbxSKAQAJAgAVAAkJbxSKAQAJAgAAAA==.',
Cl='Clairity:BAAALgAECgMJAwAAAA==.Clare:BAAALgAFFAEJAQAAAA==.Cleru:BAABLgAECn8fAAMWAAgJxhNYfABrAQAWAAgJxhNYfABrAQAXAAEJpwMVGgAlAAAAAA==.Cletus:BAAALgADCgcJAgAAAA==.',
Co='Coa:BAAALgAECgkJDAAAAA==.Cocoon:BAABLgAFFH8XAAMYAAgJ7RoLEAARAgAYAAcJdRwLEAARAgAZAAQJmw4tEwB0AAAAAA==.Coldsoul:BAAALgAECgcJDwAAAA==.Comanderkush:BAAALgADCgMJAwAAAA==.Coran:BAAALgAECgIJAwABLgAECgkJJAAaAG0bAA==.Corita:BAAALgAECgIJAgAAAA==.Cowboi:BAAALgADCgMJAwAAAA==.Cowhealer:BAABLgAECn8hAAMRAAgJgiRkCAAIAwARAAgJgiRkCAAIAwATAAEJTwUTgQAvAAAAAA==.Cozak:BAAALgAECgEJAQAAAA==.',
Cr='Craeftigdh:BAAALgAECgEJAQABLgAECgkJOwABAHEfAA==.Craeftigdk:BAAALgAECgYJCQABLgAECgkJOwABAHEfAA==.Creamypies:BAAALgAECgEJAQAAAA==.Criticaltwo:BAAALgADCgIJAgAAAA==.Crockknight:BAAALgADCgYJBgAAAA==.Crossways:BAAALgAECgYJCQAAAA==.Cryochri:BAAALgAECgEJAQAAAA==.Cræftig:BAABLgAECn87AAIBAAkJcR8SAwCrAgABAAkJcR8SAwCrAgAAAA==.',
Cu='Cursecthree:BAAALgADCgEJAQAAAA==.Curseword:BAAALgAECgEJAQAAAA==.Cutestxx:BAAALgAECgkJCwAAAA==.',
Cy='Cyxo:BAAALgADCgEJAQABLgAECgEJAQACAAAAAA==.',
Da='Dadune:BAAALgAECgEJAQABLgAECgUJCgACAAAAAA==.Daftxshade:BAABLgAECn8UAAINAAYJpxGtBgD0AAANAAYJpxGtBgD0AAAAAA==.Danasatral:BAAALgADCgEJAQAAAA==.Dandandan:BAAALgADCgMJAwAAAA==.Dapan:BAAALgADCgcJDQAAAA==.Dariaa:BAABLgAECn8UAAIHAAUJew0EsQDiAAAHAAUJew0EsQDiAAAAAA==.Darkcrusader:BAAALgAECgcJEAAAAA==.Darkheal:BAAALgADCgUJBQAAAA==.Darkladie:BAAALgADCgEJAQAAAA==.Darkshadows:BAAALgAECgUJEAAAAA==.Darktank:BAAALgAECgIJAgAAAA==.Darthsyde:BAABLgAECn8hAAIbAAkJzBKAHAB2AQAbAAkJzBKAHAB2AQAAAA==.Dasdk:BAABLgAFFH8SAAIWAAQJzCK5OwCCAQAWAAQJzCK5OwCCAQAAAA==.Daspriest:BAAALgADCgYJDQABLgAFFAQJEgAWAMwiAA==.Dayanna:BAAALgAECgIJAgAAAA==.',
De='Deadergriff:BAAALgAECgkJDQAAAA==.Deadhippycb:BAAALgAECgQJBAAAAA==.Deadhippyxy:BAAALgAECgEJAwAAAA==.Deadicated:BAABLgAECn8gAAQcAAgJzgdlRgDhAAAcAAcJLAZlRgDhAAAZAAcJQgidYACZAAAYAAUJaQURjwB8AAAAAA==.Deadsies:BAAALgADCgIJAgABLgAFFAIJAwACAAAAAA==.Deeds:BAAALgAECgMJAwAAAA==.Delan:BAAALgAECgQJBQAAAA==.Delveknight:BAAALgADCgYJBgABLgAECgcJFwAWAHUdAA==.Demoncox:BAAALgADCgMJAgAAAA==.Demondoc:BAACLgAFFH8SAAIGAAYJgQ3JTAAEAQAGAAYJgQ3JTAAEAQAuAAQKfx8AAgYACAlpF+E0APMBAAYACAlpF+E0APMBAAAA.Desunaito:BAACLgAFFH8nAAMXAAgJTBziAgAIAgAXAAgJTBziAgAIAgAbAAEJAACHXAAAAAAuAAQKfy0AAhcACQlUJWkBACcDABcACQlUJWkBACcDAAAA.Devious:BAAALgADCgEJAQAAAA==.Dexter:BAAALgAECgMJBAAAAA==.',
Dh='Dhzilong:BAACLgAFFH8PAAIGAAUJARoZRgAVAQAGAAUJARoZRgAVAQAuAAQKfx0AAwYACAlHIU84ABQCAAYACAkzHk84ABQCABIABQmNJJEeAMoBAAAA.',
Di='Diddlefiddle:BAACLgAFFH8LAAMVAAUJjSB2CQB/AQAVAAUJjSB2CQB/AQAMAAEJ7ByHLQBWAAAuAAQKfxYABBUACAn5Hx8JAIwCABUABwn5Hx8JAIwCAAwAAwlmIU0fALQAAAcAAQkgHGi3AFQAAAAA.Dihcum:BAABLgAFFH8GAAIWAAIJyAvM+wBxAAAWAAIJyAvM+wBxAAAAAA==.Dimonologist:BAAALgAECgEJAQAAAA==.Dinzarn:BAAALgADCgEJAQAAAA==.Dirtycow:BAAALgAECgQJBAAAAA==.',
Dk='Dkzilong:BAAALgAFFAIJBAABLgAFFAUJDwAGAAEaAA==.',
Dm='Dmeo:BAAALgAECgcJBwAAAA==.',
Do='Docarcanis:BAAALgAFFAIJAgAAAA==.Docholy:BAAALgAECgYJCAABLgAFFAYJEgAGAIENAA==.Dockson:BAAALgAECgMJAwAAAA==.Docwyle:BAABLgAECn8XAAMdAAgJnxEecwBUAQAdAAgJnxEecwBUAQAeAAEJtgLUcgAzAAABLgAFFAYJEgAGAIENAA==.Doktorfaust:BAAALgAECgEJAQABLgAECgMJBAACAAAAAA==.Doobyia:BAAALgADCgEJAQAAAA==.Dorki:BAAALgAECgEJAgAAAA==.Dorlanlemeth:BAABLgAECn8VAAIGAAcJBwwyhAAXAQAGAAcJBwwyhAAXAQAAAA==.Dormist:BAAALgAECgMJBAABLgAECgkJJAAaAG0bAA==.Dortrak:BAAALgAECgcJBwAAAA==.Dotti:BAAALgAFFAEJAQAAAA==.',
Dr='Dracnogard:BAAALgAECggJDwAAAA==.Dracowulf:BAABLgAECn8nAAIHAAkJPhG4PgDmAQAHAAkJPhG4PgDmAQAAAA==.Dragonx:BAABLgAECn8yAAMHAAgJJhOnZQB5AQAHAAgJJhOnZQB5AQAVAAMJaQ3YRACtAAAAAA==.Drakos:BAAALgAECgEJAQAAAA==.Drakowolf:BAABLgAECn9PAAIfAAkJ/wegDwARAQAfAAkJ/wegDwARAQAAAA==.Dreadful:BAAALgAECgQJBQABLgAFFAUJGAAFAO8KAA==.Drenz:BAAALgADCgEJAQAAAA==.Dreorge:BAABLgAFFH8HAAMKAAMJcxENQgC/AAAKAAMJcxENQgC/AAAJAAEJdAkuFwAyAAAAAA==.Dreuceratops:BAAALgAECgMJAwAAAA==.Dreux:BAAALgAECgMJAwAAAA==.Drewceratops:BAABLgAECn8pAAIIAAkJLhXpRQD0AQAIAAkJLhXpRQD0AQAAAA==.Driis:BAAALgAECgEJAQAAAA==.Drimchi:BAABLgAFFH8SAAMKAAUJixo0LAAUAQAKAAUJYhY0LAAUAQAfAAMJChmVAwClAAAAAA==.Drimveil:BAAALgAFFAQJBAAAAA==.Drizro:BAAALgADCgIJAgAAAA==.Drk:BAAALgAECgEJAQAAAA==.Drkundead:BAAALgAECgEJAQAAAA==.Dromash:BAABLgAECn8kAAMaAAkJbRuXAwB6AgAaAAkJbRuXAwB6AgAeAAgJLhN3DAB4AQAAAA==.Dromgar:BAABLgAFFH8FAAIDAAIJah4AOwCkAAADAAIJah4AOwCkAAABLgAFFAMJCgAgAAojAA==.Drpepperz:BAAALgAECgMJAwAAAA==.Druidyhealz:BAAALgAECgMJAwABLgAECgcJDwACAAAAAA==.',
Du='Duuke:BAAALgAECgEJAQAAAA==.',
['Då']='Dårius:BAAALgAECgYJEQAAAA==.',
['Dö']='Dööd:BAAALgAECgQJBAAAAA==.',
Ea='Eaterofpaint:BAAALgAECgYJDgAAAA==.',
Ed='Edgeylord:BAAALgAECgEJAQABLgAECgMJBAACAAAAAA==.',
Ef='Effloria:BAABLgAECn8lAAIRAAkJEx3TDAD3AgARAAkJEx3TDAD3AgAAAA==.Efrideet:BAAALgADCgEJAQAAAA==.',
Ei='Eisha:BAAALgADCgUJBQAAAA==.',
El='Elegia:BAACLgAFFH8aAAIdAAUJGBavSQA0AQAdAAUJGBavSQA0AQAuAAQKfy8AAx0ACQlWGyIZAL4CAB0ACQlWGyIZAL4CAB4AAQkAAAdmAEMAAAAA.Elerianor:BAABLgAECn8VAAMHAAYJdQYgNgBaAAAHAAYJyAQgNgBaAAAMAAQJBgX5MgBPAAAAAA==.Ellektra:BAAALgADCgUJBQAAAA==.Elsocio:BAAALgADCgEJAQAAAA==.',
Em='Emadiropilo:BAAALgAECgEJAQAAAA==.Emakaa:BAAALgAECgYJCAAAAA==.Embrohunter:BAAALgAECgQJBQAAAA==.',
En='Enash:BAAALgAECgQJBwAAAA==.Engvald:BAAALgADCgUJBQAAAA==.Enhua:BAAALgADCgUJBQAAAA==.Ennet:BAAALgAECgQJBgAAAA==.',
Er='Erchendor:BAAALgADCgUJBQAAAA==.Eretin:BAAALgADCgEJAQAAAA==.Erismorn:BAABLgAECn8iAAQhAAcJNR5cCwCpAQAhAAYJnBtcCwCpAQAGAAYJiBidWgB4AQASAAEJ4RAEcAA1AAAAAA==.Erulious:BAAALgADCgIJAgAAAA==.',
Eu='Eudi:BAAALgAECgEJAgAAAA==.',
Ev='Eventhorizòn:BAABLgAECn8UAAIGAAgJ8hkYMgAyAgAGAAgJ8hkYMgAyAgAAAA==.Evilhoe:BAAALgADCgUJBQAAAA==.Eviscerated:BAAALgAECgYJCQAAAA==.Evocation:BAAALgAECggJEgAAAA==.Evoextoons:BAAALgAECgUJDQAAAA==.',
Fa='Fallen:BAABLgAECn8YAAMWAAkJiCSAPAAPAgAWAAkJiCSAPAAPAgAbAAMJ7wvARAB8AAAAAA==.Fallingvoid:BAABLgAECn9oAAMGAAkJvyUaAgC3AwAGAAkJJiQaAgC3AwASAAgJpCQqAgAZAgAAAA==.Fast:BAAALgAECgEJAgABLgAECgIJAgACAAAAAA==.Fatchungus:BAAALgAFFAMJBAAAAA==.Fatherben:BAABLgAECn8XAAIGAAYJVBURgAAgAQAGAAYJVBURgAAgAQAAAA==.Fatmagus:BAAALgAECgcJBgAAAA==.Favio:BAAALgAECggJCwAAAA==.',
Fe='Fellbian:BAAALgADCgcJDgAAAA==.Fentanyahu:BAAALgAECgYJBgAAAA==.Feor:BAAALgAFFAEJAQABLgAECgYJGAAXAOofAA==.Ferozz:BAACLgAFFH8LAAIMAAMJSw70HQC8AAAMAAMJSw70HQC8AAAuAAQKfzEAAgwACAm7HmIHABECAAwACAm7HmIHABECAAAA.',
Fi='Fiercetaco:BAAALgADCgEJAQAAAA==.Finaliter:BAACLgAFFH8aAAIIAAUJZBqiOQA5AQAIAAUJZBqiOQA5AQAuAAQKfy8AAggACQk7IJslAG4CAAgACQk7IJslAG4CAAAA.Finatar:BAAALgADCgcJCwAAAA==.Fiora:BAABLgAECn8SAAIGAAcJKx87KQBdAgAGAAcJKx87KQBdAgAAAA==.Fitz:BAAALgADCgEJAQAAAA==.Fiveyears:BAAALgADCgEJAQAAAA==.',
Fk='Fknutmcgee:BAAALgAECgUJBQAAAA==.',
Fl='Flamingdrago:BAAALgAECgMJBQAAAA==.Flinti:BAAALgAECgUJCQAAAA==.Flirtyflurry:BAACLgAFFH8KAAIBAAIJRQ7HSQCPAAABAAIJRQ7HSQCPAAAuAAQKf0kAAgEACAlKGxAFACkCAAEACAlKGxAFACkCAAAA.Floggy:BAABLgAECn8eAAIBAAgJNgilmgBEAQABAAgJNgilmgBEAQAAAA==.',
Fo='Forsight:BAABLgAECn8ZAAIWAAgJZhWEgABiAQAWAAgJZhWEgABiAQAAAA==.',
Fr='Fracker:BAAALgAECgcJCAAAAA==.Frankzzorz:BAACLgAFFH8JAAIYAAMJZgpiRwCHAAAYAAMJZgpiRwCHAAAuAAQKfzQAAxgACQk1HLQMAIcCABgACQk1HLQMAIcCABkAAglFIFtYAK8AAAAA.Fremder:BAACLgAFFH8gAAIJAAQJYRnQBwA4AQAJAAQJYRnQBwA4AQAuAAQKfz0AAgkACQmqHLwEANoCAAkACQmqHLwEANoCAAAA.Fresher:BAACLgAFFH8IAAIWAAIJGCPdqADLAAAWAAIJGCPdqADLAAAuAAQKfxUAAhYABQnLHDK1AA0BABYABQnLHDK1AA0BAAEuAAUUBAkMAA0AZBEA.Freyjen:BAAALgADCgkJGAABLgAECgcJCgACAAAAAA==.Froboz:BAAALgADCgYJCQAAAA==.Frogevil:BAAALgAECggJEgAAAA==.Frogtoad:BAAALgAECgYJBgAAAA==.Frogtree:BAAALgADCgUJBQAAAA==.Frostmoth:BAAALgAECgYJBgABLgAECggJGQAWAGYVAA==.Frumentarii:BAAALgAECgQJBAAAAA==.',
Fu='Funeral:BAACLgAFFH84AAQeAAkJFByzBABgAQAdAAcJ7xQbCwDnAQAeAAUJ/R2zBABgAQAaAAMJOhqABgAYAQAuAAQKfzUABB4ACQnmIz4EAKECAB4ABwnSID4EAKECABoABwmUIrUEAE4CAB0ACAkxGetEAP0BAAAA.',
['Fà']='Fàstïk:BAAALgAECgEJAQAAAA==.',
Ga='Galladin:BAAALgAECgMJBQABLgAECgYJDQACAAAAAA==.Gallory:BAAALgAECgkJEAAAAA==.Gareeshala:BAAALgAECgIJAgAAAA==.',
Gd='Gdk:BAAALgAECgYJCAAAAA==.Gdkdemon:BAAALgAECgQJBAAAAA==.Gdkdrake:BAAALgAECgcJBwAAAA==.Gdkhunter:BAAALgAECgYJAwAAAA==.Gdkmage:BAAALgAECgkJEwAAAA==.Gdkman:BAAALgAECgcJAwAAAA==.Gdkmonk:BAAALgAECgEJAQAAAA==.Gdkpally:BAAALgAECgEJAQAAAA==.Gdkwar:BAAALgAECgUJBAAAAA==.',
Ge='Geomancer:BAAALgADCgQJBAAAAA==.',
Gh='Ghadius:BAAALgAECgcJCgAAAA==.',
Gi='Gimmedatmouf:BAACLgAFFH8FAAITAAMJjxORLADZAAATAAMJjxORLADZAAAuAAQKfxcABBEACAmjIeMIAAEDABEACAmjIeMIAAEDACIAAwmmHowuAKoAABMABAl7FlNhAJQAAAEuAAUUBAkMAA0AZBEA.Gimmedatneck:BAACLgAFFH8MAAINAAQJZBGDJAAAAQANAAQJZBGDJAAAAQAuAAQKfxcAAw0ACAlVI2EYAEQCAA0ACAlVI2EYAEQCACMAAQk2EuAcAEMAAAAA.Ginga:BAAALgAECgEJAQAAAA==.Gingy:BAAALgAECgUJBgAAAA==.',
Gl='Glead:BAABLgAECn8aAAIQAAkJ6ReNLQD9AQAQAAkJ6ReNLQD9AQAAAA==.Glizzymguire:BAAALgAECggJCAABLgAFFAMJDAAdACQGAA==.',
Gn='Gneeduh:BAAALgAECgIJAwAAAA==.Gnort:BAAALgAECgEJAgAAAA==.',
Go='Gobknight:BAAALgADCggJCAAAAA==.Goldina:BAAALgAECgEJAQAAAA==.Gooklover:BAAALgAECgQJCQAAAA==.Gosupal:BAAALgADCgYJBgAAAA==.',
Gr='Gracious:BAAALgAECgEJAQAAAA==.Graegor:BAAALgADCgYJBwAAAA==.Grastim:BAAALgAECgUJCgAAAA==.Graylight:BAAALgADCgUJBQAAAA==.Greenfanta:BAAALgADCgYJEAAAAA==.Grill:BAAALgADCgEJAQAAAA==.Grinkle:BAACLgAFFH8GAAIEAAMJFAYyYACKAAAEAAMJFAYyYACKAAAuAAQKfysAAgQACQkjEcs8ALsBAAQACQkjEcs8ALsBAAAA.Gripopotamus:BAAALgAECgIJAgAAAA==.Gristle:BAAALgADCgkJJwAAAA==.Gross:BAAALgAECgUJBQAAAA==.',
Gu='Guldangg:BAAALgAECgcJEAAAAA==.Gunner:BAACLgAFFH8SAAIHAAUJxhsTHgAfAQAHAAUJxhsTHgAfAQAuAAQKfx4AAwcACQnuItwGACgDAAcACQm5ItwGACgDABUAAwnWIcIGAMEAAAAA.',
Ha='Hahararandir:BAAALgAECgEJAQAAAA==.Hakaishaz:BAAALgADCgUJBgAAAA==.Halfwatt:BAAALgAECgYJDQAAAA==.Hamaddor:BAAALgAECgYJBgAAAA==.Hamberger:BAAALgADCgEJAQAAAA==.Hammaridge:BAAALgAECgcJCgAAAA==.Hammerfire:BAAALgADCgMJAwAAAA==.Handen:BAABLgAECn8WAAMkAAkJpRS4PABUAQAkAAcJ+w+4PABUAQAIAAUJKxAZEwAUAQAAAA==.Haraldsson:BAABLgAECn8gAAIIAAgJkRaMUQDUAQAIAAgJkRaMUQDUAQAAAA==.Harmony:BAAALgADCgcJCgAAAA==.Harrin:BAAALgADCgYJDAAAAA==.Harrydabs:BAABLgAECn8dAAMhAAkJRCNNAACDAwAhAAkJRCNNAACDAwASAAQJJRB3PwD+AAABLgAFFAEJAQACAAAAAA==.Haru:BAABLgAECn8nAAIVAAkJTBh4GADdAQAVAAkJTBh4GADdAQAAAA==.Harvaal:BAAALgAECgUJBQAAAA==.Hasaro:BAACLgAFFH8NAAIOAAMJzRU0GgC5AAAOAAMJzRU0GgC5AAAuAAQKfysAAg4ACQmNG7QHAHkCAA4ACQmNG7QHAHkCAAAA.Hashimi:BAAALgAECgcJBwAAAA==.Hashiramaa:BAAALgAECgcJDwAAAA==.Havokvacano:BAABLgAECn8gAAIIAAkJjxPsSADrAQAIAAkJjxPsSADrAQAAAA==.',
He='Healmachine:BAABLgAECn8UAAIlAAgJHAlBOwAJAQAlAAgJHAlBOwAJAQAAAA==.Hellbrringer:BAABLgAECn8XAAIBAAYJRQxm1ADrAAABAAYJRQxm1ADrAAAAAA==.Helzer:BAAALgAECgQJBgABLgAFFAMJBQAWAG0PAA==.Helzerx:BAABLgAECn8yAAINAAkJjR4ACACnAgANAAkJjR4ACACnAgABLgAFFAMJBQAWAG0PAA==.Herpstrike:BAAALgAECgIJAwAAAA==.',
Hi='Hierophant:BAAALgAECgYJBgABLgAFFAQJIAAJAGEZAA==.',
Ho='Hoely:BAAALgAECgEJAQAAAA==.Hogmanjr:BAAALgADCgQJBgAAAA==.Holycrappala:BAAALgADCgEJAQAAAA==.Hotsordots:BAAALgAECggJCwAAAA==.Hounskul:BAABLgAECn8gAAIdAAkJogfAfQA9AQAdAAkJogfAfQA9AQAAAA==.How:BAAALgADCgYJBgABLgAFFAUJEgAHAMYbAA==.',
Hu='Hugealien:BAAALgADCgIJAgAAAA==.Hulksmash:BAAALgAECgEJAQAAAA==.Hungchungus:BAAALgAECgEJAgAAAA==.Hungwaylo:BAAALgADCgIJAgAAAA==.',
Hw='Hwere:BAAALgAECgUJBgAAAA==.',
Hx='Hx:BAAALgADCgUJBgAAAA==.',
Hy='Hypnoticpal:BAAALgAECgkJBwAAAA==.Hystëria:BAACLgAFFH8dAAMXAAUJLCItBAB4AQAXAAUJLCItBAB4AQAWAAUJUBgbrQDGAAAuAAQKf1cAAxcACQmsI3wBACIDABcACQnLInwBACIDABYACAkJIV0oAGACAAEuAAUUBgkGABgAZhYA.Hyunlix:BAAALgADCgUJBQAAAA==.',
['Hõ']='Hõnor:BAAALgAECgYJBgABLgAFFAYJBgAYAGYWAA==.',
Ia='Iammoo:BAABLgAECn8UAAIIAAcJKhxCaACeAQAIAAcJKhxCaACeAQAAAA==.',
Ic='Ichorus:BAAALgADCgEJAQAAAA==.',
Id='Idasie:BAAALgADCgcJDQAAAA==.',
Ig='Igotkappa:BAAALgADCgMJAwAAAA==.Igotyourback:BAAALgAECggJCAAAAA==.Igriss:BAAALgAECgQJBgAAAA==.',
Il='Illuminaughd:BAAALgAECgQJAQAAAA==.Ilydris:BAAALgADCgQJBAAAAA==.',
Im='Imadruid:BAAALgADCgQJBAAAAA==.',
In='Infinitepain:BAAALgAECgQJBAABLgAFFAYJJAATAHUUAA==.',
Io='Iolyte:BAABLgAECn8XAAIBAAYJUQ33IwCeAAABAAYJUQ33IwCeAAAAAA==.',
Ir='Iridellis:BAACLgAFFH8YAAIFAAUJ7wqVIwAxAQAFAAUJ7wqVIwAxAQAuAAQKfyIAAgUACQn3Eo8XABkCAAUACQn3Eo8XABkCAAAA.',
Is='Ispankutank:BAAALgAFFAMJAgAAAA==.',
It='Itssofluffy:BAABLgAECn8vAAQiAAkJlBiLCABDAgAiAAkJDRiLCABDAgAOAAUJBhfbEwAyAQATAAIJUgnYlQAqAAAAAA==.Itwon:BAAALgAECgUJEgAAAA==.',
Iz='Izzelda:BAAALgAECgEJAgAAAA==.',
Ja='Jacus:BAAALgAECgQJCQAAAA==.Jadaruk:BAAALgAFFAEJAQAAAA==.Jahumc:BAAALgAECgEJAQAAAA==.Janeoftrades:BAAALgAECgYJDAAAAA==.Jaycers:BAABLgAECn8iAAQUAAkJ9SAZBQCiAgAUAAkJ8B8ZBQCiAgAIAAUJERzKmgBAAQAkAAEJ2AIAnwAqAAAAAA==.Jayclark:BAAALgADCgcJCgAAAA==.',
Je='Jessiriusrex:BAAALgADCgEJAQAAAA==.',
Jo='Joemomma:BAACLgAFFH8FAAIBAAQJ6gMtOADNAAABAAQJ6gMtOADNAAAuAAQKfxkAAgEABwk/EFAgALQAAAEABwk/EFAgALQAAAAA.Jokestarfist:BAABLgAECn8ZAAIIAAQJgRjSvAANAQAIAAQJgRjSvAANAQAAAA==.',
Jr='Jr:BAAALgAECgIJAgAAAA==.',
Jt='Jtheshadow:BAAALgAECgEJAQAAAA==.',
Ju='Juicebox:BAAALgADCgEJAQAAAA==.Jumpercables:BAAALgAECggJCQAAAA==.Junachan:BAAALgAECgMJBQAAAA==.Junior:BAAALgADCgEJAQAAAA==.Jurichan:BAAALgAECgMJCQAAAA==.',
['Jä']='Jägernaut:BAAALgADCgEJAQAAAA==.',
Ka='Kaitokit:BAAALgAFFAIJAwAAAA==.Kajamando:BAABLgAECn8eAAISAAgJ7wcXLwANAQASAAgJ7wcXLwANAQAAAA==.Kalia:BAAALgAECgQJBAAAAA==.Kalith:BAABLgAECn8YAAIVAAkJCgObMAAmAQAVAAkJCgObMAAmAQAAAA==.Kallydots:BAAALgADCgcJDQABLgAECgkJBwACAAAAAA==.Karmacide:BAAALgAECgMJBAAAAA==.Kayllina:BAABLgAECn8qAAIWAAgJTwe1pAAlAQAWAAgJTwe1pAAlAQAAAA==.Kayotic:BAABLgAECn8nAAISAAkJlgfQLQAUAQASAAkJlgfQLQAUAQAAAA==.Kayww:BAAALgAECgQJBwAAAA==.',
Ke='Keinarra:BAAALgADCgMJBgAAAA==.Kell:BAAALgADCgcJCAAAAA==.Kelmorphic:BAABLgAECn8tAAMhAAkJMyEAAgDyAgAhAAkJMyEAAgDyAgASAAEJ7QoPcgAsAAAAAA==.Keropikapika:BAAALgADCgUJBQAAAA==.Keynerashz:BAAALgADCgIJAgAAAA==.',
Kh='Khaali:BAAALgAECgEJBAAAAA==.Khristina:BAAALgAECgMJBAAAAA==.',
Ki='Kikiana:BAAALgAECgUJDAABLgAECggJMAAlAKQhAA==.Kikstyx:BAAALgADCgYJCAAAAA==.Killcommand:BAABLgAFFH8FAAQHAAQJEg7KQgCQAAAHAAIJ7gzKQgCQAAAVAAEJcBkOFgBOAAAMAAEJ+QTzHQA3AAABLgAFFAgJFwAYAO0aAA==.Killerxd:BAABLgAECn8WAAIIAAgJJRhFagCaAQAIAAgJJRhFagCaAQAAAA==.Killesea:BAAALgADCgcJDAAAAA==.Kittfisto:BAABLgAECn8iAAQhAAkJmhVYFQACAQAGAAkJiBStXgCFAQAhAAQJ4BRYFQACAQASAAYJmAweNwDeAAAAAA==.',
Kn='Knitemare:BAAALgAECgEJAQAAAA==.',
Ko='Korivos:BAAALgADCgMJAwAAAA==.Kosmas:BAABLgAECn8hAAMQAAkJJSLXEwBTAgAQAAkJbh/XEwBTAgAPAAYJuB1xGgCHAQAAAA==.',
Kr='Kromwarr:BAAALgAECgcJBwAAAA==.Krushgar:BAABLgAECn8UAAMWAAcJsRcIXQDbAQAWAAcJsRcIXQDbAQAXAAEJsxCDPQArAAAAAA==.',
Ku='Kuchikopii:BAAALgADCgYJBgAAAA==.Kungfuelf:BAAALgADCgEJAQAAAA==.Kungpowchikn:BAAALgAECgIJAgAAAA==.Kurookami:BAAALgAECgUJBwAAAA==.Kuukwa:BAAALgADCgMJBAAAAA==.',
Ky='Kyana:BAAALgADCgEJAQAAAA==.Kylina:BAAALgAECgEJAQAAAA==.',
La='Lackluster:BAACLgAFFH8IAAIBAAMJYwHAmgCVAAABAAMJYwHAmgCVAAAuAAQKfykAAgEACQmuCeCnAC4BAAEACQmuCeCnAC4BAAAA.Lagg:BAAALgAECgIJAwABLgAECgUJEQACAAAAAA==.Lamatrick:BAAALgAECgUJBwAAAA==.Lanadelslayy:BAAALgAECgYJDwAAAA==.Laosman:BAAALgAECgEJAQAAAA==.Lasenza:BAAALgADCgQJBAAAAA==.Lavacoomer:BAAALgADCgYJBQAAAA==.',
Ld='Ldg:BAAALgAFFAIJAgAAAA==.',
Le='Leafdaddy:BAABLgAFFH8JAAIOAAMJcQ9EDgCpAAAOAAMJcQ9EDgCpAAAAAA==.Ledana:BAAALgAECggJCAAAAA==.Leenale:BAAALgAECgEJAQAAAA==.Lejosh:BAAALgAECgIJAgAAAA==.Lennon:BAAALgAECgkJBgAAAA==.Leona:BAAALgAECgYJCgAAAA==.Leonesk:BAAALgADCgQJAwAAAA==.Lethee:BAAALgAECgEJAgAAAA==.Lexazshara:BAAALgAECgEJAwAAAA==.',
Li='Lightingbolt:BAAALgAECgUJDAAAAA==.Lightlybaked:BAAALgAFFAEJAQAAAA==.Lights:BAAALgAECgMJAwAAAA==.Lilithamy:BAAALgADCgYJBgAAAA==.Lilthin:BAABLgAECn8cAAIBAAkJHgfWiABlAQABAAkJHgfWiABlAQAAAA==.Lindvianne:BAAALgADCgcJBwAAAA==.Liore:BAAALgAECgQJBgAAAA==.Lisathe:BAAALgAECgYJEgAAAA==.Lithdrae:BAAALgADCgYJBgAAAA==.Littleddk:BAABLgAECn8UAAIWAAcJYRqCTgDXAQAWAAcJYRqCTgDXAQAAAA==.Littledude:BAAALgADCgQJBQAAAA==.Littlemorsel:BAABLgAECn8eAAIHAAkJNxPoNgACAgAHAAkJNxPoNgACAgAAAA==.Livelaughlov:BAAALgAECgEJAQAAAA==.',
Lo='Lockenload:BAAALgADCggJDQAAAA==.Lockme:BAAALgADCggJCAAAAA==.Lombardio:BAAALgAECgEJAwAAAA==.Louthar:BAAALgADCgcJAQAAAA==.',
Ls='Lselec:BAAALgAECgUJDAAAAA==.',
Lt='Ltdapperdan:BAAALgAECgEJAQAAAA==.',
Lu='Lucens:BAACLgAFFH8FAAIkAAIJ7gz2GgBlAAAkAAIJ7gz2GgBlAAAuAAQKfzUAAiQACAnXGi8CABoCACQACAnXGi8CABoCAAAA.Lunagreed:BAAALgADCgUJBQAAAA==.Lurchdh:BAAALgAFFAMJAgABLgAFFAUJFAABAOYNAA==.Lurchmage:BAAALgAECgEJAQAAAA==.Lurchn:BAACLgAFFH8UAAIBAAUJ5g05KgANAQABAAUJ5g05KgANAQAuAAQKf1gAAgEACQk/ExlcAMoBAAEACQk/ExlcAMoBAAAA.',
Ly='Lysariax:BAAALgAECgUJBQAAAA==.',
['Lï']='Lïght:BAACLgAFFH8HAAIIAAQJWiB3KABpAQAIAAQJWiB3KABpAQAuAAQKfxsAAggACAmDJQ0NAPwCAAgACAmDJQ0NAPwCAAEuAAUUBgkGABgAZhYA.',
['Lú']='Lúná:BAAALgAECgYJBwAAAA==.',
Ma='Maccoroni:BAAALgAECgMJCAAAAA==.Maemae:BAAALgAECgcJDQAAAA==.Maggieaugers:BAACLgAFFH8HAAIKAAYJhQLcNgDoAAAKAAYJhQLcNgDoAAAuAAQKfykAAwoACAn3D8EwAHQBAAoACAn3D8EwAHQBAAkABAmPBbAvAG4AAAAA.Magicmech:BAAALgADCgcJDAAAAA==.Magivacano:BAAALgAECggJEgAAAA==.Mahnon:BAABLgAECn8aAAIHAAkJowjGdQBUAQAHAAkJowjGdQBUAQAAAA==.Mandril:BAAALgADCgEJAQAAAA==.Matas:BAABLgAECn8YAAIcAAkJ+gOWOQAWAQAcAAkJ+gOWOQAWAQAAAA==.Matias:BAAALgAECgEJAQAAAA==.Mazzikane:BAAALgAECgMJAwAAAA==.',
Mc='Mcdeath:BAAALgADCgIJAgAAAA==.',
Me='Mebo:BAAALgAECgEJAQAAAA==.Medzly:BAAALgADCgYJEAAAAA==.Metalhedface:BAABLgAECn8iAAMPAAkJqRJcGgCHAQAPAAgJnhNcGgCHAQAQAAYJzhNURQAwAQAAAA==.',
Mi='Miixx:BAAALgAECgQJBQAAAA==.Mikecoxwall:BAACLgAFFH8HAAIBAAIJSgn3pwCDAAABAAIJSgn3pwCDAAAuAAQKfz4AAwEACQmTFVU8ACkCAAEACQmTFVU8ACkCACYABgnfCP0KACoBAAAA.Mikuru:BAAALgAECgEJAwAAAA==.Milena:BAAALgAECgEJAgAAAA==.Milkordeath:BAAALgADCgEJAQAAAA==.Milov:BAAALgADCgUJBQAAAA==.Minarva:BAAALgAECgcJCgAAAA==.Mirazha:BAAALgADCgkJCQAAAA==.Misary:BAAALgAECgQJBwAAAA==.Mischeif:BAAALgAECgUJCwAAAA==.',
Mo='Mojomon:BAAALgADCgYJBgAAAA==.Moltalgol:BAABLgAECn8jAAIdAAYJkgR15gCRAAAdAAYJkgR15gCRAAAAAA==.Monkeli:BAABLgAECn8cAAIQAAcJFxEUPwBIAQAQAAcJFxEUPwBIAQAAAA==.Monkitard:BAAALgAECgMJAwABLgAECgUJCAACAAAAAA==.Monkryn:BAAALgAECgUJCAABLgAFFAgJHgAWAOcZAA==.Monkup:BAABLgAFFH8MAAIcAAQJtwVaMgDfAAAcAAQJtwVaMgDfAAAAAA==.Moocifer:BAAALgAECgEJAQAAAA==.Moocifermoo:BAAALgAECgEJAgAAAA==.Moogrim:BAAALgADCgkJDgAAAA==.Moonsiand:BAACLgAFFH8fAAMHAAgJjQ1RDAC4AQAHAAgJjQ1RDAC4AQAVAAQJHgPnHQDjAAAuAAQKfysABAcACQk3GqYoADwCAAcACQn+FqYoADwCABUACAleEysOAOYBAAwAAQmqAV+ZABwAAAAA.Moosafur:BAACLgAFFH8HAAIOAAMJwCQbCwBBAQAOAAMJwCQbCwBBAQAuAAQKf0IAAw4ACQkMJTcBAFADAA4ACQkMJTcBAFADACIACQlbGgQIAFICAAAA.Mooshoe:BAAALgAECgEJAQAAAA==.Mor:BAAALgAECgIJBQAAAA==.Mordoly:BAAALgAECgYJBgAAAA==.Moreldwiddle:BAAALgAECgEJAgAAAA==.Morphyr:BAAALgAECgYJCAAAAA==.Morrigån:BAAALgAECgIJAgAAAA==.Morvoult:BAAALgAECgEJAQAAAA==.Motgus:BAAALgAECgMJBQAAAA==.Mozzsticks:BAAALgAECgYJDwAAAA==.',
Ms='Mshottie:BAABLgAECn8fAAIIAAkJVQg4FAAJAQAIAAkJVQg4FAAJAQAAAA==.Msuysu:BAAALgAECgEJAQABLgAECgEJAwACAAAAAA==.',
Mt='Mtngrounds:BAAALgADCgIJAgAAAA==.',
Mu='Murdaa:BAAALgAECgMJBAAAAA==.Murkt:BAAALgAECgEJAQAAAA==.Mutuusami:BAAALgAECgEJAgAAAA==.',
Mx='Mx:BAAALgAECgcJDAAAAA==.',
My='Myraine:BAAALgAECgMJAwAAAA==.Mythdath:BAAALgADCgMJAwAAAA==.Mythlock:BAAALgAECgMJAwAAAA==.Myway:BAAALgADCggJCwAAAA==.',
Na='Naari:BAABLgAECn8aAAMQAAgJNxIvRQAxAQAQAAcJDREvRQAxAQAPAAEJLxl3bwBCAAAAAA==.Naniwa:BAAALgAECgEJAQABLgAFFAMJCwAEANgVAA==.Naoya:BAAALgADCgIJAgAAAA==.Narexia:BAABLgAECn9OAAIgAAkJSx83AwDXAgAgAAkJSx83AwDXAgAAAA==.Natureboyy:BAAALgAECgIJAwAAAA==.',
Ne='Nekuma:BAAALgAFFAIJAgABLgAFFAgJJwAXAEwcAA==.Nellaa:BAAALgAECgcJEgAAAA==.',
Ni='Nightfury:BAAALgAECgcJDQAAAA==.Nightrage:BAAALgADCgYJBgAAAA==.Niklous:BAAALgAECgEJAQABLgAECgQJBAACAAAAAA==.Niklus:BAAALgAECgEJAQAAAA==.Nissanaltima:BAAALgADCgYJCQAAAA==.Nithilis:BAABLgAECn8zAAILAAkJAR5cCgCpAgALAAkJAR5cCgCpAgAAAA==.',
No='Noee:BAAALgADCgUJBQAAAA==.Nokkiewae:BAAALgADCgcJEgAAAA==.Nomadic:BAAALgADCgkJCQAAAA==.Nool:BAAALgADCgYJBQAAAA==.Nople:BAABLgAECn8fAAIBAAgJGBZQewCBAQABAAgJGBZQewCBAQAAAA==.',
Nu='Nutellaa:BAABLgAFFH8FAAIWAAIJmBd/0ACQAAAWAAIJmBd/0ACQAAAAAA==.',
Ny='Nymueline:BAAALgADCgUJBQAAAA==.',
Ob='Obeastly:BAAALgAECgUJBgAAAA==.Obie:BAAALgAECgUJEQAAAA==.Oborax:BAECLgAFFH8OAAIIAAUJuQwJUgALAQAIAAUJuQwJUgALAQAuAAQKfygAAggABwmcFw1wAI4BAAgABwmcFw1wAI4BAAAA.',
Od='Od:BAAALgAECgYJCAAAAA==.',
Ok='Okidokidrood:BAAALgADCgcJBwABLgAFFAgJKQAEAJogAA==.Okidokidude:BAAALgADCgkJDwABLgAFFAgJKQAEAJogAA==.Okiro:BAAALgAECgMJAwAAAA==.Okoru:BAAALgADCgIJAgAAAA==.',
Ol='Oliviabenson:BAAALgAFFAEJAQAAAA==.Oluun:BAAALgADCgQJBAAAAA==.',
Or='Orkun:BAAALgAECgEJAQAAAA==.',
Ot='Otmetka:BAAALgADCgcJAQAAAA==.',
Ow='Owensbeast:BAAALgADCgUJBQAAAA==.',
Pa='Palapal:BAAALgAECgYJDgAAAA==.Paldi:BAABLgAECn8WAAIIAAgJORnRKwB0AgAIAAgJORnRKwB0AgABLgAFFAMJBAACAAAAAA==.Paliboos:BAABLgAECn8UAAIIAAYJGQ+9FgDzAAAIAAYJGQ+9FgDzAAAAAA==.Papaozz:BAABLgAECn8qAAINAAcJ9Q01KABVAQANAAcJ9Q01KABVAQAAAA==.Parapox:BAAALgAECgEJAgAAAA==.Pariss:BAAALgAECgkJBwAAAA==.Pawcalypse:BAAALgAECgMJAwAAAA==.Paws:BAABLgAECn8ZAAITAAkJwg57JgCaAQATAAkJwg57JgCaAQAAAA==.',
Pe='Peaky:BAAALgAECgMJBgAAAA==.Perelia:BAABLgAECn91AAIFAAkJkxULAgBRAgAFAAkJkxULAgBRAgAAAA==.Pewpewqt:BAAALgAECgUJBwABLgAFFAEJAQACAAAAAA==.',
Pi='Piltraja:BAAALgAECgEJAgAAAA==.',
Pl='Plaguehammer:BAABLgAECn8eAAIWAAYJ6Av4wgD6AAAWAAYJ6Av4wgD6AAAAAA==.Playstationn:BAAALgADCgUJBQAAAA==.Pleiades:BAAALgAECgEJAQAAAA==.',
Pn='Pnwbambii:BAAALgADCgIJAgAAAA==.',
Po='Polarg:BAAALgAECgEJAgAAAA==.Pomni:BAAALgAECgMJAwAAAA==.Popcola:BAAALgADCgEJAQABLgAECgUJCQACAAAAAA==.Popopopopopo:BAAALgAFFAQJBAAAAA==.Portholio:BAAALgAECgYJBgAAAA==.',
Pp='Ppc:BAAALgAFFAEJAgABLgAFFAgJFwAYAO0aAA==.',
Pr='Prophofdoom:BAAALgAECgYJBgAAAA==.',
Pu='Pubbles:BAABLgAECn8XAAQgAAkJ4SB6BwBVAgAgAAgJrCB6BwBVAgAEAAEJ1Qk42AAxAAADAAEJhgx3swAnAAAAAA==.Punizher:BAAALgAECgQJBQAAAA==.Purerage:BAAALgAECgYJDQAAAA==.',
Pv='Pvc:BAAALgAECgYJCQABLgAFFAgJFwAYAO0aAA==.',
Py='Pyrella:BAAALgADCgEJAQABLgAECgcJEgACAAAAAA==.Pyyrha:BAAALgAECgMJAwAAAA==.Pyyrhadrood:BAAALgAECgMJAwAAAA==.Pyyrhanice:BAAALgAECgUJDgAAAA==.Pyyrhaspice:BAAALgADCgUJCQAAAA==.',
Qu='Quetzlcoatl:BAAALgADCgcJBwABLgAECgkJEgACAAAAAA==.',
Ra='Radiantharm:BAABLgAECn8WAAMkAAcJyhJTBgA1AQAkAAcJyhJTBgA1AQAUAAEJlApnFQAfAAAAAA==.Raevalinaa:BAAALgAECgQJCwABLgAFFAIJCgABAEUOAA==.Raevelina:BAAALgAECgEJAQABLgAFFAIJCgABAEUOAA==.Raevelinaa:BAAALgAECgQJBwABLgAFFAIJCgABAEUOAA==.Rafeh:BAAALgAECgUJBwAAAA==.Rageaholic:BAAALgAECgMJBAAAAA==.Raisedead:BAAALgAECgQJBgAAAA==.Ramian:BAAALgADCgkJCgAAAA==.Randzmannz:BAAALgAECgMJAwAAAA==.Raph:BAAALgAECgIJAgAAAA==.Rarelootboss:BAAALgADCgcJDAAAAA==.',
Re='Reason:BAABLgAECn8VAAMRAAgJQxacUgBcAQARAAcJzhacUgBcAQATAAEJewjAkwArAAAAAA==.Redbaer:BAAALgADCgUJBQAAAA==.Renair:BAAALgADCgMJAwAAAA==.Renoitukax:BAABLgAECn82AAMLAAkJwxt+DACKAgALAAkJwxt+DACKAgAFAAYJJhuXHADpAQAAAA==.Restorn:BAAALgADCgcJCgAAAA==.Retrobution:BAAALgAECgQJCAAAAA==.Retussy:BAAALgADCgEJAQAAAA==.Reynard:BAABLgAECn8WAAIGAAcJLxHYbQBHAQAGAAcJLxHYbQBHAQAAAA==.Rezz:BAACLgAFFH8TAAIBAAcJLg/tPAB5AQABAAcJLg/tPAB5AQAuAAQKfyAAAgEACQmQHIgpAM0CAAEACQmQHIgpAM0CAAAA.',
Rh='Rhode:BAAALgAECgQJCQAAAA==.Rhohir:BAAALgADCgIJAgAAAA==.',
Ri='Ridic:BAAALgADCgMJAwAAAA==.Rigour:BAAALgADCgMJAwAAAA==.Rishiun:BAAALgADCgEJAQAAAA==.Rivers:BAABLgAECn8UAAIPAAcJhQpgNQDwAAAPAAcJhQpgNQDwAAAAAA==.',
Ro='Rocketpop:BAAALgADCgIJAgAAAA==.Roopall:BAAALgAECgMJBAAAAA==.Rosiegirl:BAAALgAECgMJAwAAAA==.Roxas:BAAALgAECgcJDQAAAA==.',
Ry='Ryzen:BAAALgAECgYJDQAAAA==.',
Sa='Sabomnim:BAAALgAECgEJAQAAAA==.Saggi:BAAALgAECgYJCAAAAA==.Salaelana:BAAALgADCgcJCQAAAA==.Saltzpyre:BAAALgADCgYJBAAAAA==.Sanasrindis:BAABLgAECn8dAAMQAAgJWQq0CAAXAQAQAAgJWQq0CAAXAQAPAAEJnAbYFQAjAAAAAA==.Saninar:BAAALgAFFAIJAwAAAA==.Sausagepizza:BAAALgADCgYJAwAAAA==.',
Sc='Schezmu:BAAALgAECgIJAgAAAA==.Scruffknight:BAAALgAECgcJDQAAAA==.Scrufies:BAACLgAFFH8UAAINAAQJkhTpGgBBAQANAAQJkhTpGgBBAQAuAAQKfx4AAg0ACQmyFuETAAQCAA0ACQmyFuETAAQCAAAA.',
Se='Seisappho:BAAALgADCgMJAwAAAA==.Senorfiesta:BAAALgAECgQJBAAAAA==.Sephiroth:BAAALgADCgEJAQAAAA==.Serenade:BAABLgAECn8WAAMGAAcJAw97eAAwAQAGAAcJAw97eAAwAQAhAAEJwgZJPQAaAAAAAA==.Serenityboop:BAAALgADCgYJCQAAAA==.Sergnocchi:BAAALgAECgcJEAAAAA==.Serys:BAABLgAECn8gAAIeAAkJKQ5mAgBaAQAeAAkJKQ5mAgBaAQAAAA==.Sethour:BAAALgADCgQJBAAAAA==.',
Sh='Shaboing:BAAALgADCgYJBgAAAA==.Shadowfangs:BAAALgAECgMJAwAAAA==.Shaee:BAAALgADCgkJDwAAAA==.Shalthender:BAAALgADCgUJBQAAAA==.Shamans:BAABLgAECn8fAAIDAAgJ1hukHAD8AQADAAgJ1hukHAD8AQAAAA==.Shamncheese:BAABLgAECn8WAAIEAAgJ6QxXYgA1AQAEAAgJ6QxXYgA1AQABLgAECgUJEQACAAAAAA==.Shamorcc:BAAALgADCgQJBAAAAA==.Shasta:BAACLgAFFH8qAAIOAAcJ/CKdAgAXAgAOAAcJ/CKdAgAXAgAuAAQKfygAAg4ACAlZJW8BAEEDAA4ACAlZJW8BAEEDAAAA.Shaulthariel:BAAALgAECgEJAQAAAA==.Shioz:BAAALgADCgQJBgAAAA==.Shisuiuchiha:BAABLgAECn8oAAIBAAgJrQmhHQDDAAABAAgJrQmhHQDDAAAAAA==.Shoccymilk:BAAALgAECgEJAQAAAA==.Shoiz:BAAALgAECgQJBQAAAA==.Shon:BAAALgAECgEJAQAAAA==.Shootumup:BAAALgAECgkJEgAAAA==.Shootybithc:BAAALgADCgEJAQAAAA==.Shuhari:BAAALgAECgkJEwAAAQ==.Shyx:BAABLgAECn81AAIFAAkJ4B34AAD6AgAFAAkJ4B34AAD6AgAAAA==.',
Si='Siilas:BAACLgAFFH8aAAQdAAQJNgkbZgD6AAAdAAQJnQcbZgD6AAAaAAEJhw9oKQBEAAAeAAIJ7QC3LAAyAAAuAAQKfyoAAx0ACQljF7YqAC8CAB0ACQljF7YqAC8CAB4ABAlQBwFBALEAAAAA.Simplèjack:BAAALgAECgMJAwABLgAFFAMJBgAEABQGAA==.Sinamon:BAABLgAECn8xAAIIAAgJGSGyJAByAgAIAAgJGSGyJAByAgAAAA==.Sinani:BAABLgAECn83AAIBAAkJFAcgiABnAQABAAkJFAcgiABnAQAAAA==.Sinista:BAAALgAECgUJBQAAAA==.Sinnamon:BAAALgAECgYJEgABLgAECggJMQAIABkhAA==.Sipnspin:BAAALgAECgEJAgAAAA==.',
Sj='Sjdh:BAACLgAFFH8FAAIGAAMJZAiXMQCcAAAGAAMJZAiXMQCcAAAuAAQKfxcAAgYABwmcEtVrAEwBAAYABwmcEtVrAEwBAAAA.Sjrogue:BAABLgAECn8xAAINAAkJMBRhEwAJAgANAAkJMBRhEwAJAgABLgAFFAMJBQAGAGQIAA==.',
Sk='Skjolvarn:BAEALgAECgMJBwAAAA==.Skram:BAAALgAECgMJBAAAAA==.',
Sl='Slammydooker:BAABLgAECn8fAAMNAAkJ0hV2EwAIAgANAAkJ0hV2EwAIAgAjAAEJ1QcMIQAtAAAAAA==.Slammyhole:BAAALgAECgEJAQAAAA==.Sleeptoken:BAAALgAECgMJCAAAAA==.Slyphz:BAAALgAECgYJBgAAAA==.',
Sm='Smallkat:BAAALgAECgEJAQAAAA==.Smightymouse:BAAALgAECgEJAQAAAA==.',
Sn='Snoipuh:BAAALgAECgUJBwAAAA==.',
So='Solas:BAAALgAECgQJBwAAAA==.Soletaken:BAAALgADCggJDwAAAA==.Solio:BAAALgADCgYJFQAAAA==.Solisha:BAAALgAECgQJBAAAAA==.Sololeveling:BAAALgAECgQJCgAAAA==.Somberdh:BAAALgADCgcJBwAAAA==.Sonofsand:BAAALgAECgIJAgAAAA==.Sorni:BAAALgAECgEJAQAAAA==.Soulja:BAAALgADCgEJAgAAAA==.Soulmoethus:BAAALgADCgYJCQAAAA==.',
Sp='Sprayandpray:BAABLgAECn8aAAIBAAUJqh3GjgBaAQABAAUJqh3GjgBaAQAAAA==.Sprinklely:BAAALgADCgcJCgAAAA==.',
Sq='Squidnips:BAAALgAECgEJAgAAAA==.Squirtney:BAAALgADCgMJAwAAAA==.',
Ss='Ss:BAACLgAFFH8PAAIeAAMJjQGaFQCPAAAeAAMJjQGaFQCPAAAuAAQKfxUAAh4ABwlxDOEWAO0AAB4ABwlxDOEWAO0AAAAA.Ssl:BAAALgADCgQJBAAAAA==.',
St='Starrwood:BAABLgAECn8pAAIHAAkJhQz4GQDkAAAHAAkJhQz4GQDkAAAAAA==.Statik:BAAALgAECgIJAwAAAA==.Statík:BAAALgAECgEJAQABLgAECgIJAwACAAAAAA==.Stepmonk:BAAALgAECgEJAQAAAA==.Stevesharts:BAAALgADCgYJCwAAAA==.Stonedlock:BAAALgADCgcJCAAAAA==.Stonetusk:BAAALgAECgUJCQAAAA==.Stormkeg:BAAALgAECgQJCAAAAA==.Stroya:BAAALgAECgUJBgAAAA==.',
Su='Sumnèr:BAAALgAECgcJBwAAAA==.Sunastiri:BAAALgADCgkJDQAAAA==.Sunpali:BAAALgAECgcJCwAAAA==.',
Sw='Swank:BAAALgADCgEJAQAAAA==.',
Sx='Sx:BAAALgADCgIJAgAAAA==.',
Sy='Syaa:BAAALgAECgYJBQAAAA==.Syberis:BAAALgADCgcJDgAAAA==.Sylauda:BAAALgAECgYJEAAAAA==.',
Ta='Tacholy:BAABLgAECn8VAAIIAAkJzBdQaACeAQAIAAkJzBdQaACeAQABLgAECgkJLwAPAJQcAA==.Tacodaboss:BAABLgAECn8XAAISAAYJLw+bMwDzAAASAAYJLw+bMwDzAAAAAA==.Talelarissia:BAAALgADCgQJBAAAAA==.Talonflame:BAABLgAECn8fAAIVAAkJBBy6BwB4AgAVAAkJBBy6BwB4AgAAAA==.Tansu:BAAALgAECgYJEwAAAA==.Tapered:BAAALgAECgUJCQAAAA==.Taupo:BAACLgAFFH8fAAIYAAUJTh0EIgBeAQAYAAUJTh0EIgBeAQAuAAQKfycAAhgACQlyH6kNAHoCABgACQlyH6kNAHoCAAAA.',
Tb='Tbanger:BAAALgAECgYJDwAAAA==.Tbh:BAAALgAFFAEJAgABLgAFFAgJFwAYAO0aAA==.',
Te='Techevo:BAAALgAECgQJBQAAAA==.Techfire:BAABLgAECn8pAAInAAkJ9hpAAgBFAgAnAAkJ9hpAAgBFAgAAAA==.Techsmexx:BAAALgAECgMJBQAAAA==.Tempina:BAAALgADCgkJCwAAAA==.Tenebron:BAABLgAECn80AAIoAAYJ/RISJwD6AAAoAAYJ/RISJwD6AAAAAA==.Tenlucis:BAAALgAECggJDAAAAA==.',
Th='Thaelyssa:BAAALgAECgEJAQAAAA==.Tharria:BAAALgADCgcJBwAAAA==.Thearia:BAABLgAECn8bAAMRAAgJrRWBUgBcAQARAAgJrRWBUgBcAQATAAUJmg5nVgC3AAAAAA==.Thecanmurk:BAAALgADCgkJEgAAAA==.Thedilf:BAAALgADCgEJAQAAAA==.Thicktotem:BAAALgAECgIJAgAAAA==.Thickumz:BAAALgAECgMJCgAAAA==.Thisismeta:BAAALgAECgYJDQAAAA==.Thoht:BAAALgADCgYJBwAAAA==.Thorenis:BAAALgADCgEJAQAAAA==.Thoryndruid:BAACLgAFFH8TAAIiAAYJBB3GAgCoAQAiAAYJBB3GAgCoAQAuAAQKfzIAAyIACQkWIxEDAA4DACIACQnmIhEDAA4DAA4ABwm8HlYNAAwCAAEuAAUUCAkeABYA5xkA.Thorïn:BAAALgADCgMJAwAAAA==.Thorýn:BAACLgAFFH8eAAIWAAgJ5xnKFwAhAgAWAAgJ5xnKFwAhAgAuAAQKfxoAAhYACAl8HuMqAFUCABYACAl8HuMqAFUCAAAA.Thórin:BAABLgAECn8tAAIUAAgJ4xciDwDRAQAUAAgJ4xciDwDRAQAAAA==.',
Ti='Timakk:BAAALgADCgEJAQAAAA==.Tipsy:BAABLgAECn8uAAMEAAkJWg/0OADMAQAEAAkJWg/0OADMAQADAAMJpA3ddwCGAAAAAA==.',
To='Tombraider:BAAALgAECgUJCAAAAA==.Tomfoolary:BAAALgAECgEJAwAAAA==.Toofy:BAAALgAECgEJAQAAAA==.Tot:BAAALgAECgkJDQAAAA==.Total:BAAALgADCgkJDAAAAA==.Totembear:BAAALgAECgYJCwABLgAFFAIJBwATABUFAA==.',
Tr='Trallanir:BAAALgAECgQJBAAAAA==.Tralleth:BAABLgAECn8nAAMKAAkJIRWSBABEAQAKAAgJCRSSBABEAQAJAAIJvQ3mMABmAAAAAA==.Trenazath:BAAALgAECgYJBwAAAA==.Trid:BAAALgAECgQJBgAAAA==.Trillbilly:BAAALgAECgEJAQAAAA==.Trinora:BAAALgADCgkJDgAAAA==.Troginator:BAAALgAECgEJAQAAAA==.Trolltard:BAAALgAECgIJAgABLgAECgUJCAACAAAAAA==.Troxa:BAAALgAECgUJCgAAAA==.',
Tu='Tuckard:BAAALgADCgEJAQAAAA==.Turock:BAAALgADCgIJAgAAAA==.Tuskor:BAAALgAFFAIJAgAAAA==.',
Tw='Twinklord:BAAALgAECgkJDwAAAA==.',
Ty='Tylanar:BAAALgAECgYJBgAAAA==.Tylolight:BAAALgADCgMJAwAAAA==.Tylomist:BAAALgAECgUJBQAAAA==.Tylototem:BAAALgAFFAEJAgAAAA==.',
['Tö']='Tötem:BAAALgAFFAEJAQABLgAFFAYJBgAYAGYWAA==.',
Ug='Uglyboi:BAAALgAECggJDwAAAA==.',
Uj='Ujcmonk:BAAALgAECgQJBAAAAA==.',
Ul='Ullbian:BAAALgADCgMJAwAAAA==.Ultramar:BAAALgADCgEJAQAAAA==.',
Un='Uncookedham:BAAALgAECgQJCwAAAA==.Unholyghost:BAAALgAECgQJBwAAAA==.',
Ur='Urgh:BAABLgAECn8fAAILAAkJ9RHLIwCrAQALAAkJ9RHLIwCrAQAAAA==.Urk:BAAALgAECgYJBgAAAA==.Urzaa:BAAALgAECgEJAwABLgAECgMJBAACAAAAAA==.',
Ut='Uthur:BAAALgAECgMJAwAAAA==.',
Va='Vaeelrundor:BAABLgAECn8YAAIHAAcJbAwCEgAtAQAHAAcJbAwCEgAtAQAAAA==.Valethales:BAAALgADCgcJBwAAAA==.Valyr:BAAALgAECgEJAQAAAA==.Vanillaface:BAACLgAFFH8HAAIIAAMJnxg0IAD4AAAIAAMJnxg0IAD4AAAuAAQKfxkAAggACQnvHNYdAJMCAAgACQnvHNYdAJMCAAAA.Vape:BAABLgAECn8XAAIdAAcJXA+0egBEAQAdAAcJXA+0egBEAQABLgAFFAUJEgAHAMYbAA==.',
Ve='Veinripp:BAAALgADCgUJBQABLgAECggJNAAGAO0QAA==.Velarael:BAABLgAECn8zAAIdAAgJQhDpCQA2AQAdAAgJQhDpCQA2AQAAAA==.Velaryn:BAAALgADCgIJAgAAAA==.Veldar:BAAALgADCgIJAgABLgAECgUJDAACAAAAAA==.Velekete:BAAALgADCgUJBQAAAA==.Velethei:BAABLgAECn8YAAIRAAYJlySkGQBrAgARAAYJlySkGQBrAgAAAA==.Velian:BAAALgADCgMJBAAAAA==.Velielyn:BAAALgADCgQJBAAAAA==.Vellareth:BAAALgAECgEJAQAAAA==.Vellarria:BAAALgADCgcJBwAAAA==.Verdesalsa:BAAALgAECgcJDQAAAA==.Verox:BAAALgADCgMJAwAAAA==.Verzak:BAAALgAECgUJBQAAAA==.Vexoris:BAAALgAECgIJAgAAAA==.',
Vh='Vheckxus:BAACLgAFFH8IAAIDAAMJwgxzHACiAAADAAMJwgxzHACiAAAuAAQKfxoAAgMABgloFAJAADQBAAMABgloFAJAADQBAAAA.',
Vi='Vicv:BAABLgAECn8TAAILAAkJXwwXNABIAQALAAkJXwwXNABIAQAAAA==.Vivy:BAAALgAECgcJBwAAAA==.',
Vo='Voidberg:BAABLgAECn8YAAIaAAkJAxpsBwD6AQAaAAkJAxpsBwD6AQAAAA==.',
['Vê']='Vêa:BAAALgADCgkJCQAAAA==.',
['Vø']='Vøidtacø:BAAALgAFFAEJAQAAAA==.',
Wa='Wachonaso:BAACLgAFFH8TAAIdAAcJagynNgBuAQAdAAcJagynNgBuAQAuAAQKfy0AAx0ABwlJH6M0ADkCAB0ABwkrH6M0ADkCAB4ABgl8HlgXAI8BAAAA.Wanbahl:BAAALgADCgMJAwAAAA==.',
We='Wegovy:BAAALgAECgQJBAAAAA==.Wellburt:BAAALgAECgEJAQAAAA==.',
Wh='Whatheheck:BAAALgAECgEJAQAAAA==.Whatuphuz:BAAALgADCgQJBQAAAA==.Wheresmyjaw:BAACLgAFFH8jAAQdAAYJMR4ZPgBVAQAdAAYJ9RwZPgBVAQAaAAEJWSPAFQBnAAAeAAEJOQLaLAAxAAAuAAQKfycABB0ACAnyIe0WAJoCAB0ACAnyIe0WAJoCAB4AAgm6DiRSAHcAABoAAQnAILYvAF8AAAAA.',
Wi='Wield:BAAALgAECgEJAQAAAA==.Wildstàr:BAAALgADCgMJAwAAAA==.Wildthree:BAABLgAECn8rAAMZAAkJwh0HCgCjAgAZAAkJwh0HCgCjAgAcAAMJ2RQvYgC5AAAAAA==.Willenda:BAAALgAECgEJAwAAAA==.Willowins:BAAALgAECgEJAQAAAA==.Winterstired:BAACLgAFFH8wAAIlAAYJ7iTLAgDiAQAlAAYJ7iTLAgDiAQAuAAQKf0IAAyUACQnuJIMCAHkDACUACQnuJIMCAHkDAAUAAQlKF1xyAEQAAAAA.Wintesbuffs:BAAALgAFFAEJAQABLgAFFAYJMAAlAO4kAA==.',
Wo='Woen:BAAALgADCggJCQAAAA==.Wolf:BAAALgAECgQJBwAAAA==.Wollffie:BAAALgAECgQJBAAAAA==.',
Wu='Wuinn:BAAALgAFFAEJAQABLgAFFAkJGgARAFkPAA==.Wut:BAAALgADCgcJBwAAAA==.',
Wy='Wynterswrath:BAAALgAECgcJDQAAAA==.',
['Wõ']='Wõnderful:BAACLgAFFH8IAAIRAAUJthJSDgAaAQARAAUJthJSDgAaAQAuAAQKfxoAAhEABwk+G9skACUCABEABwk+G9skACUCAAEuAAUUBgkGABgAZhYA.',
Xc='Xclobber:BAAALgADCgIJAgAAAA==.',
Xe='Xemnass:BAAALgAECgUJBwAAAA==.Xexus:BAAALgAECgEJAQAAAA==.',
Xi='Xillas:BAAALgADCgUJBQAAAA==.Xinadmh:BAAALgAECgMJAwAAAA==.',
Xo='Xoverkll:BAAALgAECgYJDAAAAA==.',
Xy='Xylina:BAAALgADCgEJAQAAAA==.Xyrii:BAAALgADCgEJAQAAAA==.',
Ya='Yadder:BAAALgAECgIJBAABLgAFFAQJDAANAGQRAA==.Yahro:BAACLgAFFH8VAAIIAAYJ2hMBGQAbAQAIAAYJ2hMBGQAbAQAuAAQKfzMAAggACQkqIKoOAPACAAgACQkqIKoOAPACAAAA.Yamelow:BAAALgAECgQJBwAAAA==.',
Ye='Yeahiknow:BAAALgADCgkJDgAAAA==.Yeling:BAAALgAECgIJAgAAAA==.Yep:BAAALgAECgcJBwAAAA==.',
Yi='Yiska:BAAALgADCgcJBwAAAA==.',
Yn='Ynaguinid:BAAALgADCgEJAQAAAA==.',
Yo='Yoriale:BAAALgAECgYJDgAAAA==.Yotoymuerto:BAAALgAECgQJBAAAAA==.',
Za='Zafra:BAAALgADCgEJAQAAAA==.Zaimara:BAAALgAECgEJBgAAAA==.Zalind:BAABLgAECn8VAAIdAAkJCxJoZgCYAQAdAAkJCxJoZgCYAQAAAA==.Zalvianna:BAABLgAECn8iAAMBAAgJLQRRxAADAQABAAgJLQRRxAADAQAmAAEJXQHIIgAYAAAAAA==.Zarathoz:BAAALgAECgEJAgAAAA==.Zarindlina:BAAALgADCgUJBQAAAA==.Zarshx:BAAALgAECgYJCwABLgAFFAMJBAACAAAAAA==.',
Ze='Zemonk:BAAALgAECgYJBgAAAA==.',
Zi='Zilong:BAAALgAFFAEJAQABLgAFFAUJDwAGAAEaAA==.Zilongmage:BAAALgAFFAIJAwABLgAFFAUJDwAGAAEaAA==.Zilongwar:BAAALgAFFAMJAwABLgAFFAUJDwAGAAEaAA==.Zinnia:BAAALgADCgEJAgAAAA==.',
Zo='Zonecw:BAAALgAECgQJAwABLgAFFAIJBwAhABsRAA==.Zonedk:BAABLgAECn8eAAQbAAkJnB0+BABeAQAbAAkJ8Rs+BABeAQAXAAcJZhi8BAD0AAAWAAEJxBc3YgFBAAABLgAFFAIJBwAhABsRAA==.Zonerg:BAAALgADCgEJAgABLgAFFAIJBwAhABsRAA==.Zonevn:BAABLgAFFH8HAAIhAAIJGxF7BgB2AAAhAAIJGxF7BgB2AAAAAA==.Zordak:BAAALgADCgcJCAAAAA==.Zosin:BAAALgAECgIJAwAAAA==.',
Zu='Zugzugzapzap:BAAALgADCgEJAQAAAA==.',
Zx='Zx:BAAALgAECgUJBgAAAA==.',
Zy='Zylphanae:BAAALgAECgQJBAAAAA==.',
['Øl']='Ølaf:BAAALgAECgEJAQABLgAFFAUJHwAYAE4dAA==.',
['Ør']='Ørsted:BAAALgAECgEJAgABLgAFFAUJHwAYAE4dAA==.',
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
