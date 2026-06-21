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

local lookup = {'Mage-Frost','Unknown-Unknown','Shaman-Elemental','Shaman-Restoration','Priest-Discipline','DemonHunter-Devourer','Evoker-Preservation','Evoker-Augmentation','Priest-Shadow','Paladin-Retribution','Hunter-Marksmanship','Druid-Guardian','Warrior-Arms','Warrior-Fury','Druid-Restoration','DemonHunter-Havoc','Hunter-BeastMastery','Druid-Balance','Paladin-Protection','Hunter-Survival','DeathKnight-Unholy','DeathKnight-Frost','Monk-Mistweaver','Monk-Windwalker','Warlock-Affliction','Rogue-Subtlety','DeathKnight-Blood','Monk-Brewmaster','Warlock-Demonology','Warlock-Destruction','Evoker-Devastation','Shaman-Enhancement','DemonHunter-Vengeance','Druid-Feral','Paladin-Holy','Priest-Holy','Mage-Arcane','Rogue-Assassination','Mage-Fire','Warrior-Protection',}
local provider = {region='US',realm='Nazjatar',name='US',type='weekly',zone=46,date='2026-06-20',data={Aa='Aaela:BAAALgADCgUJBQAAAA==.',
Ab='Abrasaxs:BAABLgAECn8qAAIBAAgJQhikWQDQAQABAAgJQhikWQDQAQAAAA==.Absylus:BAAALgAECgQJBAABLgAFFAMJBAACAAAAAA==.',
Ac='Ackerman:BAAALgAECgYJCgABLgAECggJEgACAAAAAA==.Acraea:BAABLgAECn8hAAIBAAgJmwwshABvAQABAAgJmwwshABvAQAAAA==.Acràea:BAAALgAFFAEJAQAAAA==.Acslater:BAAALgAECgQJDQAAAA==.Actionman:BAAALgAECgkJBwAAAA==.',
Ad='Adversary:BAAALgAECgEJAQAAAA==.',
Ag='Agoobagoo:BAACLgAFFH8aAAMDAAYJwiHODQDOAQADAAYJwiHODQDOAQAEAAEJ6yEbCQBrAAAuAAQKfx8AAgMACQnZIpAEAFIDAAMACQnZIpAEAFIDAAAA.',
Ai='Aionn:BAAALgAECgMJAwAAAA==.Airrow:BAABLgAECn8UAAIFAAkJEhk5EABuAgAFAAkJEhk5EABuAgAAAA==.Aissae:BAACLgAFFH8OAAIGAAQJ7hwhOQBAAQAGAAQJ7hwhOQBAAQAuAAQKfyoAAgYACAlAJHYLACYDAAYACAlAJHYLACYDAAAA.Aiyama:BAAALgADCgQJBAAAAA==.',
Ak='Akiio:BAAALgAECgMJAwAAAA==.Akumaxl:BAAALgAECgYJBwAAAA==.',
Al='Alexia:BAAALgAECgEJAQAAAA==.Alfrank:BAAALgAECgIJAwAAAA==.Aliasx:BAAALgAECgMJBAAAAA==.Allwrong:BAAALgAECgUJBgAAAA==.Alphrank:BAAALgAECgEJAgAAAA==.Alurie:BAAALgAECgUJBgAAAA==.',
Am='Amandrada:BAAALgAECgYJBwAAAA==.Ambros:BAAALgADCgYJBgAAAA==.Aminatou:BAAALgAECgYJBwAAAA==.',
An='Angerfang:BAAALgADCgQJBQAAAA==.Angriff:BAAALgAECgEJAQAAAA==.Anheeboan:BAAALgAECgYJCwAAAA==.Anihilated:BAAALgADCgYJBwAAAA==.',
Ar='Aradiax:BAAALgADCgYJBgAAAA==.Arcadavia:BAAALgADCgMJAwAAAA==.Ariaprime:BAABLgAECn8WAAIBAAcJdAm+sAAgAQABAAcJdAm+sAAgAQAAAA==.Arjentheilus:BAAALgAECgMJAwAAAA==.Armandox:BAAALgAECgEJAQAAAA==.Arthasl:BAAALgADCgMJAgAAAA==.Arthur:BAAALgAECgQJDgAAAA==.',
As='Asasda:BAAALgADCgMJBAAAAA==.Ashaelra:BAAALgAECgYJCAAAAA==.Astravaritan:BAAALgADCgMJAwAAAA==.Astrá:BAAALgAECgYJDQABLgAECgUJDQACAAAAAA==.',
At='Atherya:BAAALgAECgYJCAAAAA==.Atomixblonde:BAAALgAECgQJBAAAAA==.',
Au='Augonly:BAACLgAFFH8eAAIHAAcJQxdsCgAFAgAHAAcJQxdsCgAFAgAuAAQKfyMAAgcACQnpIC4GAOECAAcACQnpIC4GAOECAAAA.Augy:BAACLgAFFH8OAAIIAAQJMg0pNwDoAAAIAAQJMg0pNwDoAAAuAAQKfx0AAwgACQkyGvQcAO8BAAgACAnlGPQcAO8BAAcAAQmSBOs+ACkAAAAA.Autoshot:BAAALgAFFAIJAgAAAA==.',
Av='Averisbelia:BAAALgAECgYJCwAAAA==.',
Ay='Ayowamsley:BAAALgADCgMJAwAAAA==.',
Az='Azalea:BAAALgAECggJEAAAAA==.',
Ba='Babycrock:BAAALgADCgYJBgAAAA==.Back:BAAALgADCgcJDAAAAA==.Bakihanma:BAAALgAECgQJBgAAAA==.Balash:BAAALgADCgUJBQAAAA==.Balerion:BAAALgADCgEJAQABLgADCgMJAwACAAAAAA==.Balthasar:BAABLgAECn8nAAIJAAkJExpZDwBkAgAJAAkJExpZDwBkAgAAAA==.Banjobits:BAAALgADCgIJAgAAAA==.Barhead:BAAALgAECgYJDAAAAA==.Barlow:BAAALgAECggJEQAAAA==.Barqose:BAAALgADCgMJAwAAAA==.Barryberry:BAABLgAECn8fAAIKAAkJDRE3fgByAQAKAAkJDRE3fgByAQAAAA==.Barryx:BAAALgAECgIJAgAAAA==.',
Bb='Bbldrizzy:BAABLgAFFH8FAAIEAAMJjR6APQDuAAAEAAMJjR6APQDuAAAAAA==.',
Be='Beastlieduke:BAAALgAECgMJAwABLgAFFAYJFgAJAOwOAA==.Beastlièduke:BAACLgAFFH8WAAIJAAYJ7A4dEgBXAQAJAAYJ7A4dEgBXAQAuAAQKfzQAAgkACQkfIFAMAIsCAAkACQkfIFAMAIsCAAAA.Beauslay:BAAALgAECgEJAQAAAA==.Belephon:BAAALgAECgYJEAAAAA==.Bellaruhbz:BAABLgAECn8eAAILAAkJjA+0FwD1AAALAAkJjA+0FwD1AAAAAA==.Berenstain:BAABLgAECn8nAAIMAAkJShP8FwCRAQAMAAkJShP8FwCRAQAAAA==.Bergmire:BAAALgAECgQJCgAAAA==.Berple:BAAALgADCgUJBQABLgAFFAgJGQABAK0iAA==.Bestoresto:BAABLgAECn8XAAIEAAkJBQwRRACdAQAEAAkJBQwRRACdAQAAAA==.',
Bh='Bhori:BAAALgAECgEJAwAAAA==.',
Bi='Bibahabibi:BAABLgAECn8dAAMNAAYJxhvpJQA5AQANAAYJxhvpJQA5AQAOAAMJzQiVhwChAAAAAA==.Bighunt:BAAALgAECgEJAQAAAA==.Bigpapax:BAAALgAECgEJAQAAAA==.Bigtac:BAABLgAECn8vAAMNAAkJlBxZCQBbAgANAAkJlBxZCQBbAgAOAAIJ3gc5mQBcAAAAAA==.Bimmylee:BAAALgADCgEJAQAAAA==.Binggus:BAAALgAFFAEJAQAAAA==.Bipolaire:BAAALgADCgEJAQAAAA==.',
Bl='Blabbybootze:BAAALgAECggJDgAAAA==.Bladelight:BAAALgAECgYJCAAAAA==.Blighte:BAAALgADCgQJBAABLgAECggJIQAPAIIkAA==.Blightfangs:BAACLgAFFH8HAAIBAAMJkgsQiADJAAABAAMJkgsQiADJAAAuAAQKf0QAAgEACAlCG5I0AEYCAAEACAlCG5I0AEYCAAAA.Blindnautdef:BAABLgAECn80AAMGAAgJ7RAcagBRAQAGAAgJ7RAcagBRAQAQAAEJ9gPcfgAhAAAAAA==.Bloodluna:BAAALgADCgUJBQAAAA==.',
Bo='Bobman:BAAALgAECgUJCAAAAA==.Bodakye:BAACLgAFFH8NAAIRAAMJfArdaADTAAARAAMJfArdaADTAAAuAAQKfyQAAxEACQlBG1MuACMCABEACQlBG1MuACMCAAsAAgm0ARCBAEMAAAAA.Bonargrowrod:BAAALgAECgcJEwAAAA==.Bonkz:BAAALgAECgMJAwAAAA==.Boomtip:BAAALgADCgMJAwAAAA==.Boon:BAAALgADCgYJCQAAAA==.Bordolor:BAAALgAECgEJAQAAAA==.Bowsa:BAAALgAECgkJAQAAAA==.',
Br='Brabbit:BAAALgAECgQJCQAAAA==.Brethathes:BAAALgAECgkJEgAAAA==.Brudda:BAAALgADCgUJBQAAAA==.',
Bu='Bubbaray:BAAALgAECgMJAwAAAA==.Bubblebun:BAAALgAECgMJBgAAAA==.Bungerhole:BAABLgAECn8VAAMPAAgJhhpSMADhAQAPAAgJhhpSMADhAQASAAEJEQlgmwAmAAAAAA==.Butane:BAAALgADCgIJAgAAAA==.Buzzbuzz:BAAALgAECgIJBwAAAA==.',
Ca='Caeruleus:BAAALgAECgEJAgAAAA==.Cainn:BAAALgAECgYJBwAAAA==.Cap:BAAALgADCgEJAQABLgAFFAQJFAABAGIeAA==.Capriestsun:BAAALgAFFAMJAwABLgAFFAMJBQAEAI0eAA==.Captyn:BAABLgAECn8cAAITAAgJug2FGgBEAQATAAgJug2FGgBEAQAAAA==.Carridin:BAAALgADCgMJAwAAAA==.Cass:BAAALgAECgEJAQAAAA==.',
Ce='Cernunon:BAAALgADCgEJAQAAAA==.Ceroquel:BAAALgAECgMJAwAAAA==.',
Ch='Chaosdemon:BAABLgAECn81AAIGAAkJPRDHRQC1AQAGAAkJPRDHRQC1AQAAAA==.Chaosraven:BAAALgADCgkJCQAAAA==.Chapelgnome:BAAALgAECgUJCQABLgAFFAYJBwAIAIUCAA==.Charlottea:BAAALgAECgYJDQAAAA==.Chemdra:BAAALgAECgcJEwAAAA==.Chiling:BAAALgAECgEJAQAAAA==.Chipmonkey:BAAALgAECgEJAgABLgAECgkJNAAPAMEPAA==.Chiptime:BAABLgAECn80AAIPAAkJwQ96NwC6AQAPAAkJwQ96NwC6AQABLgAECgkJNAAPAMEPAA==.Chomby:BAAALgAECgQJAwAAAA==.Chriifrio:BAAALgADCgUJBgAAAA==.Chromosomes:BAAALgAECgQJBAAAAA==.Chud:BAAALgAECgQJCQAAAA==.Chudsworth:BAAALgADCgYJCQAAAA==.Chunguhlumpo:BAAALgAECgEJBAAAAA==.Chzburger:BAAALgAECgIJAgAAAA==.',
Ci='Cinnamóróll:BAABLgAECn9FAAIUAAkJPxSGAACYAQAUAAkJPxSGAACYAQAAAA==.',
Cl='Clairity:BAAALgAECgMJAwAAAA==.Cleru:BAABLgAECn8fAAMVAAgJxhNVfABrAQAVAAgJxhNVfABrAQAWAAEJpwMVGgAlAAAAAA==.Cletus:BAAALgADCgcJAgAAAA==.',
Co='Coa:BAAALgAECgkJDAAAAA==.Cocoon:BAABLgAFFH8VAAMXAAcJCxwOEAARAgAXAAcJCxwOEAARAgAYAAMJEBGMLQCTAAAAAA==.Coldsoul:BAAALgAECgMJBAAAAA==.Comanderkush:BAAALgADCgMJAwAAAA==.Coran:BAAALgAECgIJAwABLgAECgkJJAAZAG0bAA==.Corita:BAAALgAECgIJAgAAAA==.Cowboi:BAAALgADCgMJAwAAAA==.Cowhealer:BAABLgAECn8hAAMPAAgJgiRkCAAIAwAPAAgJgiRkCAAIAwASAAEJTwUTgQAvAAAAAA==.',
Cr='Creamypies:BAAALgAECgEJAQAAAA==.Criticaltwo:BAAALgADCgIJAgAAAA==.Crockknight:BAAALgADCgYJBgAAAA==.Crossways:BAAALgAECgYJCQAAAA==.Cræftig:BAABLgAECn8vAAIBAAgJqR/pAAAPAgABAAgJqR/pAAAPAgAAAA==.',
Cu='Cursecthree:BAAALgADCgEJAQAAAA==.Curseword:BAAALgAECgEJAQAAAA==.Cutestxx:BAAALgAECgkJCwAAAA==.',
Cy='Cyxo:BAAALgADCgEJAQABLgAECgEJAQACAAAAAA==.',
Da='Dadune:BAAALgAECgEJAQABLgAECgUJCgACAAAAAA==.Daftxshade:BAABLgAECn8UAAIaAAYJpxEhAQAPAQAaAAYJpxEhAQAPAQAAAA==.Dandandan:BAAALgADCgMJAwAAAA==.Dapan:BAAALgADCgcJDQAAAA==.Dariaa:BAABLgAECn8UAAIRAAUJew0AsQDiAAARAAUJew0AsQDiAAAAAA==.Darkcrusader:BAAALgAECgcJEAAAAA==.Darkheal:BAAALgADCgUJBQAAAA==.Darkladie:BAAALgADCgEJAQAAAA==.Darkshadows:BAAALgAECgUJDgAAAA==.Darktank:BAAALgAECgIJAgAAAA==.Darthsyde:BAABLgAECn8eAAIbAAkJDxJ+HAB2AQAbAAkJDxJ+HAB2AQAAAA==.Dasdk:BAABLgAFFH8SAAIVAAQJzCLGOwCCAQAVAAQJzCLGOwCCAQAAAA==.Daspriest:BAAALgADCgYJDQABLgAFFAQJEgAVAMwiAA==.',
De='Deadergriff:BAAALgAECgkJDQAAAA==.Deadhippycb:BAAALgAECgQJBAAAAA==.Deadhippyxy:BAAALgAECgEJAwAAAA==.Deadicated:BAABLgAECn8eAAQcAAcJpQdlRgDhAAAcAAcJLAZlRgDhAAAYAAYJKAieYACZAAAXAAUJaQUMjwB8AAAAAA==.Deadsies:BAAALgADCgIJAgABLgAFFAIJAgACAAAAAA==.Deeds:BAAALgAECgMJAwAAAA==.Delan:BAAALgAECgQJBQAAAA==.Delveknight:BAAALgADCgYJBgABLgAECgcJFwAVAHUdAA==.Demoncox:BAAALgADCgMJAgAAAA==.Demondoc:BAACLgAFFH8OAAIGAAQJ7g/YTAAEAQAGAAQJ7g/YTAAEAQAuAAQKfx8AAgYACAlpF+M0APMBAAYACAlpF+M0APMBAAAA.Desunaito:BAACLgAFFH8gAAMWAAcJEB3lAgAIAgAWAAcJEB3lAgAIAgAbAAEJAACIXAAAAAAuAAQKfy0AAhYACQlUJWkBACcDABYACQlUJWkBACcDAAAA.Devious:BAAALgADCgEJAQAAAA==.Dexter:BAAALgAECgIJAgAAAA==.',
Dh='Dhzilong:BAACLgAFFH8PAAIGAAUJARoiRgAVAQAGAAUJARoiRgAVAQAuAAQKfx0AAwYACAlHIU84ABQCAAYACAkzHk84ABQCABAABQmNJJEeAMoBAAAA.',
Di='Diddlefiddle:BAACLgAFFH8LAAMUAAUJjSB0CQB/AQAUAAUJjSB0CQB/AQALAAEJ7BybLQBWAAAuAAQKfxYABBQACAn5HyAJAIwCABQABwn5HyAJAIwCAAsAAwlmIU0fALQAABEAAQkgHGi3AFQAAAAA.Dihcum:BAABLgAFFH8FAAIVAAIJ2QfP+wBxAAAVAAIJ2QfP+wBxAAAAAA==.Dimonologist:BAAALgAECgEJAQAAAA==.Dirtycow:BAAALgAECgQJBAAAAA==.',
Dk='Dkzilong:BAAALgAFFAIJBAABLgAFFAUJDwAGAAEaAA==.',
Do='Docholy:BAAALgAECgYJCAABLgAFFAQJDgAGAO4PAA==.Dockson:BAAALgAECgMJAwAAAA==.Docwyle:BAABLgAECn8XAAMdAAgJnxEfcwBUAQAdAAgJnxEfcwBUAQAeAAEJtgLUcgAzAAABLgAFFAQJDgAGAO4PAA==.Doobyia:BAAALgADCgEJAQAAAA==.Dorki:BAAALgAECgEJAgAAAA==.Dorlanlemeth:BAABLgAECn8VAAIGAAcJBwwxhAAXAQAGAAcJBwwxhAAXAQAAAA==.Dormist:BAAALgAECgMJBAABLgAECgkJJAAZAG0bAA==.Dotti:BAAALgAFFAEJAQAAAA==.',
Dr='Dracnogard:BAAALgAECgcJDgAAAA==.Dracowulf:BAABLgAECn8kAAIRAAkJPRC4PgDmAQARAAkJPRC4PgDmAQAAAA==.Dragonx:BAABLgAECn8yAAMRAAgJJhOoZQB5AQARAAgJJhOoZQB5AQAUAAMJaQ3XRACtAAAAAA==.Drakos:BAAALgAECgEJAQAAAA==.Drakowolf:BAABLgAECn9NAAIfAAkJNAagDwARAQAfAAkJNAagDwARAQAAAA==.Drenz:BAAALgADCgEJAQAAAA==.Dreorge:BAABLgAFFH8GAAIIAAMJcxEJQgC/AAAIAAMJcxEJQgC/AAAAAA==.Dreuceratops:BAAALgAECgMJAwAAAA==.Drewceratops:BAABLgAECn8oAAIKAAkJtRTrRQD0AQAKAAkJtRTrRQD0AQAAAA==.Driis:BAAALgADCgcJBwAAAA==.Drimchi:BAABLgAFFH8RAAMfAAQJixqJAAC3AAAIAAQJYhY2LAAUAQAfAAMJChmJAAC3AAAAAA==.Drimveil:BAAALgAFFAEJAQAAAA==.Drizro:BAAALgADCgIJAgAAAA==.Drk:BAAALgAECgEJAQAAAA==.Drkundead:BAAALgAECgEJAQAAAA==.Dromash:BAABLgAECn8kAAMZAAkJbRuYAwB6AgAZAAkJbRuYAwB6AgAeAAgJLhN3DAB4AQAAAA==.Dromgar:BAAALgAFFAIJBAABLgAFFAMJCAAgAAojAA==.Druidyhealz:BAAALgAECgMJAwABLgAECgcJDwACAAAAAA==.',
Du='Duuke:BAAALgAECgEJAQAAAA==.',
['Då']='Dårius:BAAALgAECgYJEQAAAA==.',
Ea='Eaterofpaint:BAAALgAECgYJDgAAAA==.',
Ed='Edgeylord:BAAALgAECgEJAQABLgAECgMJBAACAAAAAA==.',
Ef='Effloria:BAABLgAECn8lAAIPAAkJEx3TDAD3AgAPAAkJEx3TDAD3AgAAAA==.Efrideet:BAAALgADCgEJAQAAAA==.',
Ei='Eisha:BAAALgADCgUJBQAAAA==.',
El='Elegia:BAACLgAFFH8aAAIdAAUJGBYXBgDqAAAdAAUJGBYXBgDqAAAuAAQKfy8AAx0ACQlWGyIZAL4CAB0ACQlWGyIZAL4CAB4AAQkAAAdmAEMAAAAA.Elerianor:BAAALgAECgYJEgAAAA==.Ellektra:BAAALgADCgUJBQAAAA==.',
Em='Emadiropilo:BAAALgAECgEJAQAAAA==.Emakaa:BAAALgAECgYJCAAAAA==.Embrohunter:BAAALgAECgQJBQAAAA==.',
En='Enash:BAAALgAECgQJBwAAAA==.Engvald:BAAALgADCgUJBQAAAA==.Enhua:BAAALgADCgUJBQAAAA==.Ennet:BAAALgAECgQJBgAAAA==.',
Er='Eretin:BAAALgADCgEJAQAAAA==.Erismorn:BAABLgAECn8iAAQhAAcJNR5cCwCpAQAhAAYJnBtcCwCpAQAGAAYJiBifWgB4AQAQAAEJ4RAEcAA1AAAAAA==.Erulious:BAAALgADCgIJAgAAAA==.',
Eu='Eudi:BAAALgAECgEJAgAAAA==.',
Ev='Eventhorizòn:BAAALgAECggJEwAAAA==.Evilhoe:BAAALgADCgUJBQAAAA==.Evocation:BAAALgAECggJEgAAAA==.Evoextoons:BAAALgAECgIJAgAAAA==.',
Fa='Fallen:BAABLgAECn8YAAMVAAkJiCR9PAAPAgAVAAkJiCR9PAAPAgAbAAMJ7wu+RAB8AAAAAA==.Fallingvoid:BAABLgAECn9iAAMGAAkJJiUaAgC3AwAGAAkJJiQaAgC3AwAQAAIJpiUtNwDeAAAAAA==.Fast:BAAALgAECgEJAgABLgAECgIJAgACAAAAAA==.Fatchungus:BAAALgAFFAMJBAAAAA==.Fatherben:BAABLgAECn8XAAIGAAYJVBUSgAAgAQAGAAYJVBUSgAAgAQAAAA==.Fatmagus:BAAALgAECgcJBgAAAA==.Favio:BAAALgAECggJCwAAAA==.',
Fe='Fellbian:BAAALgADCgcJDgAAAA==.Fentanyahu:BAAALgAECgYJBgAAAA==.Ferozz:BAACLgAFFH8LAAILAAMJSw4AHgC8AAALAAMJSw4AHgC8AAAuAAQKfzEAAgsACAm7HmIHABECAAsACAm7HmIHABECAAAA.',
Fi='Fiercetaco:BAAALgADCgEJAQAAAA==.Finaliter:BAACLgAFFH8SAAIKAAQJZBq1OQA5AQAKAAQJZBq1OQA5AQAuAAQKfyoAAgoACQk7IJslAG4CAAoACQk7IJslAG4CAAAA.Finatar:BAAALgADCgcJCwAAAA==.Fiora:BAABLgAECn8SAAIGAAcJKx87KQBdAgAGAAcJKx87KQBdAgAAAA==.Fitz:BAAALgADCgEJAQAAAA==.Fiveyears:BAAALgADCgEJAQAAAA==.',
Fk='Fknutmcgee:BAAALgAECgUJBQAAAA==.',
Fl='Flamingdrago:BAAALgAECgMJBAAAAA==.Flinti:BAAALgAECgUJCQAAAA==.Flirtyflurry:BAABLgAECn87AAIBAAgJChe6AgA+AQABAAgJChe6AgA+AQAAAA==.Floggy:BAABLgAECn8eAAIBAAgJNgijmgBEAQABAAgJNgijmgBEAQAAAA==.',
Fo='Forsight:BAABLgAECn8YAAIVAAgJUhWBgABiAQAVAAgJUhWBgABiAQAAAA==.',
Fr='Fracker:BAAALgAECgcJCAAAAA==.Frankzzorz:BAACLgAFFH8IAAIXAAMJZgpfRwCHAAAXAAMJZgpfRwCHAAAuAAQKfzQAAxcACQk1HLQMAIcCABcACQk1HLQMAIcCABgAAglFIFtYAK4AAAAA.Fremder:BAACLgAFFH8XAAIHAAQJyRV9FwAeAQAHAAQJyRV9FwAeAQAuAAQKfzwAAgcACQmqHLwEANoCAAcACQmqHLwEANoCAAAA.Fresher:BAABLgAECn8VAAIVAAUJyxwstQANAQAVAAUJyxwstQANAQABLgAFFAMJBQAEAI0eAA==.Freyjen:BAAALgADCgkJGAABLgAECgcJCgACAAAAAA==.Froboz:BAAALgADCgYJCQAAAA==.Frogevil:BAAALgAECgcJEQAAAA==.Frogtoad:BAAALgAECgYJBgAAAA==.Frogtree:BAAALgADCgUJBQAAAA==.Frostmoth:BAAALgADCgQJBAABLgAECggJGAAVAFIVAA==.Frumentarii:BAAALgAECgQJBAAAAA==.',
Fu='Funeral:BAACLgAFFH8rAAQeAAgJcBm0BABgAQAeAAUJ/R20BABgAQAZAAMJOhqABgAYAQAdAAMJQxV4MACyAAAuAAQKfzUABB4ACQnmIz4EAKECAB4ABwnSID4EAKECABkABwmUIrUEAE4CAB0ACAkxGetEAP0BAAAA.',
['Fà']='Fàstïk:BAAALgAECgEJAQAAAA==.',
Ga='Galladin:BAAALgAECgMJBQABLgAECgYJDQACAAAAAA==.Gallory:BAAALgAECgkJDQAAAA==.Gareeshala:BAAALgAECgIJAgAAAA==.',
Gd='Gdk:BAAALgAECgYJCAAAAA==.Gdkdrake:BAAALgAECgcJBwAAAA==.Gdkmage:BAAALgAECgkJEwAAAA==.Gdkman:BAAALgAECgcJAQAAAA==.Gdkwar:BAAALgAECgUJBAAAAA==.',
Ge='Geomancer:BAAALgADCgQJBAAAAA==.',
Gh='Ghadius:BAAALgAECgcJCgAAAA==.',
Gi='Gimmedatmouf:BAABLgAECn8XAAQPAAgJoyHjCAABAwAPAAgJoyHjCAABAwAiAAMJph6MLgCqAAASAAQJexZMYQCUAAABLgAFFAMJBQAEAI0eAA==.Ginga:BAAALgAECgEJAQAAAA==.Gingy:BAAALgAECgUJBgAAAA==.',
Gl='Glead:BAABLgAECn8aAAIOAAkJ6ReNLQD9AQAOAAkJ6ReNLQD9AQAAAA==.Glizzymguire:BAAALgAECggJCAABLgAFFAMJDAAdACQGAA==.',
Gn='Gneeduh:BAAALgAECgIJAwAAAA==.',
Go='Gobknight:BAAALgADCggJCAAAAA==.Goldina:BAAALgAECgEJAQAAAA==.Gooklover:BAAALgAECgQJCQAAAA==.Gosupal:BAAALgADCgYJBgAAAA==.',
Gr='Gracious:BAAALgAECgEJAQAAAA==.Graegor:BAAALgADCgYJBwAAAA==.Grastim:BAAALgAECgUJCgAAAA==.Graylight:BAAALgADCgUJBQAAAA==.Greenfanta:BAAALgADCgYJEAAAAA==.Grill:BAAALgADCgEJAQAAAA==.Grinkle:BAACLgAFFH8FAAIEAAMJjwUwYACKAAAEAAMJjwUwYACKAAAuAAQKfysAAgQACQkjEck8ALsBAAQACQkjEck8ALsBAAAA.Gripopotamus:BAAALgAECgEJAQAAAA==.Gristle:BAAALgADCgkJJwAAAA==.',
Gu='Guldangg:BAAALgAECgcJEAAAAA==.Gunner:BAACLgAFFH8QAAIRAAUJxhuoAwA/AQARAAUJxhuoAwA/AQAuAAQKfx4AAxEACQnuIt4GACgDABEACQm5It4GACgDABQAAwnWIWMBAMkAAAAA.',
Ha='Hakaishaz:BAAALgADCgUJBgAAAA==.Halfwatt:BAAALgAECgYJDQAAAA==.Hamaddor:BAAALgAECgYJBgAAAA==.Hammerfire:BAAALgADCgMJAwAAAA==.Handen:BAAALgAECgYJBwAAAA==.Haraldsson:BAABLgAECn8gAAIKAAgJkRaQUQDUAQAKAAgJkRaQUQDUAQAAAA==.Harmony:BAAALgADCgcJCgAAAA==.Harrin:BAAALgADCgYJDAAAAA==.Harrydabs:BAABLgAECn8dAAMhAAkJRCNNAACDAwAhAAkJRCNNAACDAwAQAAQJJRB3PwD+AAABLgAFFAEJAQACAAAAAA==.Haru:BAABLgAECn8mAAIUAAgJHxh7GADdAQAUAAgJHxh7GADdAQAAAA==.Harvaal:BAAALgAECgUJBQAAAA==.Hasaro:BAACLgAFFH8LAAIMAAMJuhUxGgC5AAAMAAMJuhUxGgC5AAAuAAQKfysAAgwACQmNG7QHAHkCAAwACQmNG7QHAHkCAAAA.Hashimi:BAAALgAECgcJBwAAAA==.Hashiramaa:BAAALgAECgYJBgAAAA==.Havokvacano:BAABLgAECn8fAAIKAAkJjxPtSADrAQAKAAkJjxPtSADrAQAAAA==.',
He='Healmachine:BAAALgAECgcJEwAAAA==.Hellbrringer:BAABLgAECn8XAAIBAAYJRQxh1ADrAAABAAYJRQxh1ADrAAAAAA==.Helzerx:BAABLgAECn8qAAIaAAkJPB3/BwCnAgAaAAkJPB3/BwCnAgABLgAFFAIJAgACAAAAAA==.Herpstrike:BAAALgAECgIJAwAAAA==.',
Hi='Highlanchrii:BAAALgAECgEJAQAAAA==.',
Ho='Hoely:BAAALgAECgEJAQAAAA==.Hogmanjr:BAAALgADCgQJBgAAAA==.Holycrappala:BAAALgADCgEJAQAAAA==.Hotsordots:BAAALgAECggJCwAAAA==.Hounskul:BAABLgAECn8gAAIdAAkJoge9fQA9AQAdAAkJoge9fQA9AQAAAA==.How:BAAALgADCgYJBgABLgAFFAUJEAARAMYbAA==.',
Hu='Hugealien:BAAALgADCgIJAgAAAA==.Hulksmash:BAAALgAECgEJAQAAAA==.Hungchungus:BAAALgAECgEJAgAAAA==.Hungwaylo:BAAALgADCgIJAgAAAA==.',
Hw='Hwere:BAAALgAECgUJBgAAAA==.',
Hy='Hypnoticpal:BAAALgAECgkJBwAAAA==.Hystëria:BAACLgAFFH8UAAMWAAUJ9yA6CABqAQAWAAQJ9yA6CABqAQAVAAQJaRUhrQDGAAAuAAQKf1IAAxYACQmQI3wBACIDABYACQmhInwBACIDABUACAkJIVwoAGACAAAA.Hyunlix:BAAALgADCgUJBQAAAA==.',
Ia='Iammoo:BAAALgAECgcJEwAAAA==.',
Ic='Ichorus:BAAALgADCgEJAQAAAA==.',
Id='Idasie:BAAALgADCgcJDQAAAA==.',
Ig='Igotkappa:BAAALgADCgMJAwAAAA==.Igotyourback:BAAALgAECggJCAAAAA==.Igriss:BAAALgAECgMJBgAAAA==.',
Il='Ilydris:BAAALgADCgQJBAAAAA==.',
Im='Imadruid:BAAALgADCgQJBAAAAA==.',
Io='Iolyte:BAAALgAECgYJEwAAAA==.',
Ir='Iridellis:BAACLgAFFH8PAAIFAAUJmgehIwAxAQAFAAUJmgehIwAxAQAuAAQKfyIAAgUACQn3Eo0XABkCAAUACQn3Eo0XABkCAAAA.',
Is='Ispankutank:BAAALgAECgYJCgAAAA==.',
It='Itssofluffy:BAABLgAECn8vAAQiAAkJlBiKCABDAgAiAAkJDRiKCABDAgAMAAUJBhfbEwAyAQASAAIJUgnTlQAqAAAAAA==.Itwon:BAAALgAECgQJCgAAAA==.',
Iz='Izzelda:BAAALgAECgEJAgAAAA==.',
Ja='Jacus:BAAALgAECgQJCQAAAA==.Jadaruk:BAAALgADCgEJAQAAAA==.Jahumc:BAAALgAECgEJAQAAAA==.Janeoftrades:BAAALgAECgYJDAAAAA==.Jaycers:BAABLgAECn8iAAQTAAkJ9SAZBQCiAgATAAkJ8B8ZBQCiAgAKAAUJERzMmgBAAQAjAAEJ2AIAnwAqAAAAAA==.Jayclark:BAAALgADCgcJCgAAAA==.',
Je='Jessiriusrex:BAAALgADCgEJAQAAAA==.',
Jo='Joemomma:BAABLgAECn8UAAIBAAYJIw0YzwDzAAABAAYJIw0YzwDzAAAAAA==.Jokestarfist:BAABLgAECn8ZAAIKAAQJgRjTvAANAQAKAAQJgRjTvAANAQAAAA==.',
Jr='Jr:BAAALgADCgYJCgAAAA==.',
Jt='Jtheshadow:BAAALgAECgEJAQAAAA==.',
Ju='Jumpercables:BAAALgAECgcJCAAAAA==.Junachan:BAAALgAECgMJBQAAAA==.Jurichan:BAAALgAECgMJCQAAAA==.',
['Jä']='Jägernaut:BAAALgADCgEJAQAAAA==.',
Ka='Kaitokit:BAAALgAFFAIJAgAAAA==.Kajamando:BAABLgAECn8eAAIQAAgJ7wcTLwANAQAQAAgJ7wcTLwANAQAAAA==.Kalith:BAABLgAECn8YAAIUAAkJCgOWMAAmAQAUAAkJCgOWMAAmAQAAAA==.Kallydots:BAAALgADCgcJDQAAAA==.Kayllina:BAABLgAECn8lAAIVAAgJnwawpAAlAQAVAAgJnwawpAAlAQAAAA==.Kayotic:BAABLgAECn8kAAIQAAkJPQbLLQAUAQAQAAkJPQbLLQAUAQAAAA==.Kayww:BAAALgAECgQJBgAAAA==.',
Ke='Keinarra:BAAALgADCgMJBgAAAA==.Kell:BAAALgADCgcJCAAAAA==.Kelmorphic:BAABLgAECn8tAAMhAAkJMyEAAgDyAgAhAAkJMyEAAgDyAgAQAAEJ7QoLcgAsAAAAAA==.Keropikapika:BAAALgADCgUJBQAAAA==.Keynerashz:BAAALgADCgIJAgAAAA==.',
Kh='Khaali:BAAALgAECgEJBAAAAA==.Khristina:BAAALgAECgMJBAAAAA==.',
Ki='Kikiana:BAAALgAECgQJCAABLgAECggJLgAkAKQhAA==.Kikstyx:BAAALgADCgYJCAAAAA==.Killerxd:BAABLgAECn8WAAIKAAgJJRhHagCaAQAKAAgJJRhHagCaAQAAAA==.Killesea:BAAALgADCgcJDAAAAA==.Kittfisto:BAABLgAECn8iAAQhAAkJmhVYFQACAQAGAAkJiBStXgCFAQAhAAQJ4BRYFQACAQAQAAYJmAwbNwDeAAAAAA==.',
Kn='Knitemare:BAAALgAECgEJAQAAAA==.',
Ko='Korivos:BAAALgADCgMJAwAAAA==.Kosmas:BAABLgAECn8gAAMOAAkJbiHYEwBTAgAOAAkJbh/YEwBTAgANAAYJlRxwGgCHAQAAAA==.',
Kr='Kromwarr:BAAALgAECgcJBwAAAA==.Krushgar:BAABLgAECn8UAAMVAAcJsRcIXQDbAQAVAAcJsRcIXQDbAQAWAAEJsxCDPQArAAAAAA==.',
Ku='Kuchikopii:BAAALgADCgYJBgAAAA==.Kungfuelf:BAAALgADCgEJAQAAAA==.Kungpowchikn:BAAALgADCgUJBQAAAA==.Kurookami:BAAALgAECgEJAQAAAA==.',
La='Lackluster:BAACLgAFFH8IAAIBAAMJYwHPmgCVAAABAAMJYwHPmgCVAAAuAAQKfykAAgEACQmuCd2nAC4BAAEACQmuCd2nAC4BAAAA.Lagg:BAAALgAECgIJAwABLgAECgUJEQACAAAAAA==.Lamatrick:BAAALgAECgUJBwAAAA==.Lanadelslayy:BAAALgAECgYJDwAAAA==.Lasenza:BAAALgADCgQJBAAAAA==.Lavacoomer:BAAALgADCgYJBQAAAA==.',
Ld='Ldg:BAAALgAFFAIJAgAAAA==.',
Le='Ledana:BAAALgAECgIJAgAAAA==.Leenale:BAAALgAECgEJAQAAAA==.Lejosh:BAAALgAECgIJAgAAAA==.Lennon:BAAALgAECgkJBgAAAA==.Leona:BAAALgAECgYJCgAAAA==.Leonesk:BAAALgADCgQJAwAAAA==.Lethee:BAAALgAECgEJAgAAAA==.Lexazshara:BAAALgAECgEJAwAAAA==.',
Li='Lightingbolt:BAAALgAECgUJDAAAAA==.Lightlybaked:BAAALgAFFAEJAQAAAA==.Lilithamy:BAAALgADCgYJBgAAAA==.Lilthin:BAABLgAECn8cAAIBAAkJHgfTiABlAQABAAkJHgfTiABlAQAAAA==.Liore:BAAALgAECgQJBgAAAA==.Lisathe:BAAALgAECgYJEgAAAA==.Lithdrae:BAAALgADCgYJBgAAAA==.Littleddk:BAABLgAECn8UAAIVAAcJYRp9TgDXAQAVAAcJYRp9TgDXAQAAAA==.Littledude:BAAALgADCgQJBQAAAA==.Littlemorsel:BAABLgAECn8eAAIRAAkJNxPqNgACAgARAAkJNxPqNgACAgAAAA==.Livelaughlov:BAAALgAECgEJAQAAAA==.',
Lo='Louthar:BAAALgADCgcJAQAAAA==.',
Ls='Lselec:BAAALgAECgQJBAAAAA==.',
Lt='Ltdapperdan:BAAALgAECgEJAQAAAA==.',
Lu='Lucens:BAABLgAECn8tAAIjAAgJSRcXAQBOAQAjAAgJSRcXAQBOAQAAAA==.Lunagreed:BAAALgADCgUJBQAAAA==.Lurchlock:BAAALgAECgYJBgABLgAFFAIJBgABACsGAA==.Lurchn:BAACLgAFFH8GAAIBAAIJKwbgqwB+AAABAAIJKwbgqwB+AAAuAAQKf1QAAgEACQluERpcAMoBAAEACQluERpcAMoBAAAA.',
Ly='Lysariax:BAAALgAECgMJAwAAAA==.',
['Lï']='Lïght:BAACLgAFFH8HAAIKAAQJWiCLKABpAQAKAAQJWiCLKABpAQAuAAQKfxoAAgoACAmDJQoNAPwCAAoACAmDJQoNAPwCAAEuAAUUBQkUABYA9yAA.',
['Lú']='Lúná:BAAALgAECgYJBwAAAA==.',
Ma='Maemae:BAAALgAECgcJCwAAAA==.Maggieaugers:BAACLgAFFH8HAAIIAAYJhQLWNgDoAAAIAAYJhQLWNgDoAAAuAAQKfykAAwgACAn3D8AwAHQBAAgACAn3D8AwAHQBAAcABAmPBbAvAG4AAAAA.Magicmech:BAAALgADCgcJDAAAAA==.Magivacano:BAAALgAECggJEgAAAA==.Mahnon:BAABLgAECn8aAAIRAAkJowjLdQBUAQARAAkJowjLdQBUAQAAAA==.Mandril:BAAALgADCgEJAQAAAA==.Matas:BAABLgAECn8WAAIcAAkJxAOTOQAWAQAcAAkJxAOTOQAWAQAAAA==.Matias:BAAALgAECgEJAQAAAA==.Mazzikane:BAAALgAECgMJAwAAAA==.',
Mc='Mcdeath:BAAALgADCgIJAgAAAA==.',
Me='Medzly:BAAALgADCgYJEAAAAA==.Metalhedface:BAABLgAECn8iAAMNAAkJqRJcGgCHAQANAAgJnhNcGgCHAQAOAAYJzhNSRQAwAQAAAA==.',
Mi='Miixx:BAAALgAECgQJBQAAAA==.Mikecoxwall:BAACLgAFFH8HAAIBAAIJSgkGqACDAAABAAIJSgkGqACDAAAuAAQKfz4AAwEACQmTFVg8ACkCAAEACQmTFVg8ACkCACUABgnfCP0KACoBAAAA.Mikuru:BAAALgAECgEJAwAAAA==.Milena:BAAALgAECgEJAgAAAA==.Milov:BAAALgADCgUJBQAAAA==.Minarva:BAAALgAECgcJCgAAAA==.Mirazha:BAAALgADCgkJCQAAAA==.Misary:BAAALgAECgQJBwAAAA==.Mischeif:BAAALgAECgUJCwAAAA==.',
Mo='Mojomon:BAAALgADCgYJBgAAAA==.Moltganus:BAABLgAECn8hAAIdAAYJHANz5gCRAAAdAAYJHANz5gCRAAAAAA==.Monkeli:BAABLgAECn8cAAIOAAcJFxETPwBIAQAOAAcJFxETPwBIAQAAAA==.Monkitard:BAAALgAECgMJAwABLgAECgQJBAACAAAAAA==.Monkryn:BAAALgAECgUJCAABLgAFFAgJHAAVAJMZAA==.Monkup:BAABLgAFFH8KAAIcAAQJtwVkMgDfAAAcAAQJtwVkMgDfAAAAAA==.Moocifer:BAAALgAECgEJAQAAAA==.Moocifermoo:BAAALgAECgEJAgAAAA==.Moogrim:BAAALgADCgkJDgAAAA==.Moonsiand:BAACLgAFFH8XAAMRAAYJcQpzOgA4AQARAAYJ9wlzOgA4AQAUAAQJHgPnHQDjAAAuAAQKfysABBEACQk3GqcoADwCABEACQn+FqcoADwCABQACAleEysOAOYBAAsAAQmqAV+ZABwAAAAA.Moosafur:BAACLgAFFH8HAAIMAAMJwCQbCwBBAQAMAAMJwCQbCwBBAQAuAAQKf0IAAwwACQkMJTcBAFADAAwACQkMJTcBAFADACIACQlbGgMIAFICAAAA.Mooshoe:BAAALgAECgEJAQAAAA==.Mor:BAAALgAECgEJAwAAAA==.Mordoly:BAAALgAECgYJBgAAAA==.Morphyr:BAAALgAECgYJCAAAAA==.Morrigån:BAAALgAECgIJAgAAAA==.Morvoult:BAAALgAECgEJAQAAAA==.Motgus:BAAALgAECgMJBQAAAA==.',
Ms='Mshottie:BAABLgAECn8WAAIKAAgJsgbowQAGAQAKAAgJsgbowQAGAQAAAA==.Msuysu:BAAALgAECgEJAQABLgAECgEJAwACAAAAAA==.',
Mt='Mtngrounds:BAAALgADCgIJAgAAAA==.',
Mu='Murdaa:BAAALgAECgMJBAAAAA==.Murkt:BAAALgAECgEJAQAAAA==.Mutuusami:BAAALgAECgEJAgAAAA==.',
Mx='Mx:BAAALgAECgcJDAAAAA==.',
My='Myraine:BAAALgAECgMJAwAAAA==.Mythdath:BAAALgADCgMJAwAAAA==.Mythlock:BAAALgAECgMJAwAAAA==.Myway:BAAALgADCggJCwAAAA==.',
Na='Naari:BAABLgAECn8aAAMOAAgJNxIvRQAxAQAOAAcJDREvRQAxAQANAAEJLxl3bwBCAAAAAA==.Naniwa:BAAALgAECgEJAQABLgAFFAMJCgAEANgVAA==.Naoya:BAAALgADCgIJAgAAAA==.Narexia:BAABLgAECn9LAAIgAAkJAR84AwDXAgAgAAkJAR84AwDXAgAAAA==.Natureboyy:BAAALgAECgIJAwAAAA==.',
Ne='Nekuma:BAAALgAFFAIJAgABLgAFFAcJIAAWABAdAA==.Nellaa:BAAALgAECgcJEAAAAA==.',
Ni='Nightfury:BAAALgAECgcJDQAAAA==.Nightrage:BAAALgADCgYJBgAAAA==.Niklous:BAAALgAECgEJAQABLgAECgQJBAACAAAAAA==.Niklus:BAAALgAECgEJAQAAAA==.Nissanaltima:BAAALgADCgYJCQAAAA==.Nithilis:BAABLgAECn8zAAIJAAkJAR5cCgCpAgAJAAkJAR5cCgCpAgAAAA==.',
No='Noee:BAAALgADCgUJBQAAAA==.Nokkiewae:BAAALgADCgcJEgAAAA==.Nomadic:BAAALgADCgkJCQAAAA==.Nool:BAAALgADCgYJBQAAAA==.Nople:BAABLgAECn8fAAIBAAgJGBZTewCBAQABAAgJGBZTewCBAQAAAA==.',
Nu='Nutellaa:BAABLgAFFH8FAAIVAAIJmBeG0ACQAAAVAAIJmBeG0ACQAAAAAA==.',
Ny='Nymueline:BAAALgADCgUJBQAAAA==.',
Ob='Obeastly:BAAALgAECgUJBQAAAA==.Obie:BAAALgAECgUJEQAAAA==.Oborax:BAECLgAFFH8OAAIKAAUJuQwXUgALAQAKAAUJuQwXUgALAQAuAAQKfygAAgoABwmcFxFwAI4BAAoABwmcFxFwAI4BAAAA.',
Od='Od:BAAALgAECgYJCAAAAA==.',
Ok='Okiro:BAAALgAECgMJAwAAAA==.Okoru:BAAALgADCgIJAgAAAA==.',
Ol='Oliviabenson:BAAALgAFFAEJAQAAAA==.Oluun:BAAALgADCgQJBAAAAA==.',
Or='Orkun:BAAALgAECgEJAQAAAA==.',
Ot='Otmetka:BAAALgADCgcJAQAAAA==.',
Ow='Owensbeast:BAAALgADCgUJBQAAAA==.',
Pa='Palapal:BAAALgAECgYJDgAAAA==.Paldi:BAABLgAECn8WAAIKAAgJORnRKwB0AgAKAAgJORnRKwB0AgABLgAFFAMJBAACAAAAAA==.Paliboos:BAAALgAECgQJCwAAAA==.Papaozz:BAABLgAECn8qAAIaAAcJ9Q00KABVAQAaAAcJ9Q00KABVAQAAAA==.Parapox:BAAALgAECgEJAgAAAA==.Pariss:BAAALgAECgkJBwAAAA==.Pawcalypse:BAAALgAECgMJAwAAAA==.Paws:BAABLgAECn8ZAAISAAkJwg53JgCaAQASAAkJwg53JgCaAQAAAA==.',
Pe='Perelia:BAABLgAECn9RAAIFAAkJOQ+YAADBAQAFAAkJOQ+YAADBAQAAAA==.Pewpewqt:BAAALgAECgUJBwABLgAECggJOQAPABEXAA==.',
Pi='Piltraja:BAAALgAECgEJAgAAAA==.',
Pl='Plaguehammer:BAABLgAECn8eAAIVAAYJ6AvRygDvAAAVAAYJ6AvRygDvAAAAAA==.Playstationn:BAAALgADCgUJBQAAAA==.',
Pn='Pnwbambii:BAAALgADCgIJAgAAAA==.',
Po='Polarg:BAAALgAECgEJAgAAAA==.Popcola:BAAALgADCgEJAQABLgAECgUJCQACAAAAAA==.Popopopopopo:BAAALgAFFAQJBAAAAA==.Portholio:BAAALgAECgYJBgAAAA==.',
Pp='Ppc:BAAALgAFFAEJAQABLgAFFAcJFQAXAAscAA==.',
Pu='Pubbles:BAABLgAECn8XAAQgAAkJ4SB6BwBVAgAgAAgJrCB6BwBVAgAEAAEJ1Qk22AAxAAADAAEJhgxzswAnAAAAAA==.Punizher:BAAALgAECgMJAwAAAA==.Purerage:BAAALgAECgYJDQAAAA==.',
Pv='Pvc:BAAALgAECgYJCQABLgAFFAcJFQAXAAscAA==.',
Py='Pyrella:BAAALgADCgEJAQABLgAECgcJEAACAAAAAA==.Pyyrha:BAAALgAECgMJAwAAAA==.Pyyrhadrood:BAAALgAECgMJAwAAAA==.Pyyrhanice:BAAALgAECgUJDgAAAA==.Pyyrhaspice:BAAALgADCgUJCQAAAA==.',
Qu='Quetzlcoatl:BAAALgADCgcJBwABLgAECgkJEgACAAAAAA==.',
Ra='Radiantharm:BAAALgAECgUJDwAAAA==.Raevalinaa:BAAALgAECgQJCgABLgAECggJOwABAAoXAA==.Raevelinaa:BAAALgAECgQJBwABLgAECggJOwABAAoXAA==.Rafeh:BAAALgAECgUJBwAAAA==.Raisedead:BAAALgAECgQJBgAAAA==.Randzmannz:BAAALgAECgMJAwAAAA==.Raph:BAAALgAECgIJAgAAAA==.Rarelootboss:BAAALgADCgcJDAAAAA==.',
Re='Reason:BAABLgAECn8VAAMPAAgJQxacUgBcAQAPAAcJzhacUgBcAQASAAEJewi7kwArAAAAAA==.Redbaer:BAAALgADCgUJBQAAAA==.Renair:BAAALgADCgMJAwAAAA==.Renoitukax:BAABLgAECn82AAMJAAkJwxt/DACKAgAJAAkJwxt/DACKAgAFAAYJJhuWHADpAQAAAA==.Restorn:BAAALgADCgcJCgAAAA==.Retrobution:BAAALgAECgEJBAAAAA==.Retussy:BAAALgADCgEJAQAAAA==.Reynard:BAABLgAECn8WAAIGAAcJLxHYbQBHAQAGAAcJLxHYbQBHAQAAAA==.Rezz:BAACLgAFFH8SAAIBAAYJjRENPQB5AQABAAYJjRENPQB5AQAuAAQKfyAAAgEACQmQHIgpAM0CAAEACQmQHIgpAM0CAAAA.',
Rh='Rhode:BAAALgAECgEJAQAAAA==.',
Ri='Ridic:BAAALgADCgMJAwAAAA==.Rigour:BAAALgADCgMJAwAAAA==.Rivers:BAABLgAECn8UAAINAAcJhQpgNQDwAAANAAcJhQpgNQDwAAAAAA==.',
Ro='Rocketpop:BAAALgADCgIJAgAAAA==.Rosiegirl:BAAALgAECgMJAwAAAA==.Roxas:BAAALgAECgcJDQAAAA==.',
Ry='Ryzen:BAAALgAECgIJAgAAAA==.',
Sa='Salaelana:BAAALgADCgcJCQAAAA==.Saltzpyre:BAAALgADCgYJBAAAAA==.Saninar:BAAALgAECgIJBQAAAA==.Sausagepizza:BAAALgADCgYJAwAAAA==.',
Sc='Schezmu:BAAALgAECgIJAgAAAA==.Scruffknight:BAAALgAECgcJDQAAAA==.Scrufies:BAACLgAFFH8NAAIaAAQJ4RLsGgBBAQAaAAQJ4RLsGgBBAQAuAAQKfx0AAhoACQmbFuETAAQCABoACQmbFuETAAQCAAAA.',
Se='Seisappho:BAAALgADCgMJAwAAAA==.Senorfiesta:BAAALgAECgQJBAAAAA==.Serenade:BAABLgAECn8WAAMGAAcJAw99eAAwAQAGAAcJAw99eAAwAQAhAAEJwgZGPQAaAAAAAA==.Serenityboop:BAAALgADCgYJCQAAAA==.Sergnocchi:BAAALgAECgcJEAAAAA==.Serys:BAAALgAECggJEAAAAA==.Sethour:BAAALgADCgQJBAAAAA==.',
Sh='Shadowfangs:BAAALgAECgMJAwAAAA==.Shaee:BAAALgADCgkJDwAAAA==.Shalthender:BAAALgADCgUJBQAAAA==.Shamans:BAABLgAECn8dAAIDAAcJLx+lHAD8AQADAAcJLx+lHAD8AQAAAA==.Shamncheese:BAABLgAECn8WAAIEAAgJ6gxQYgA1AQAEAAgJ6gxQYgA1AQABLgAECgUJDQACAAAAAA==.Shamorcc:BAAALgADCgQJBAAAAA==.Shasta:BAACLgAFFH8kAAIMAAYJSCWeAgAXAgAMAAYJSCWeAgAXAgAuAAQKfygAAgwACAlZJW8BAEEDAAwACAlZJW8BAEEDAAAA.Shaulthariel:BAAALgAECgEJAQAAAA==.Shioz:BAAALgADCgQJBgAAAA==.Shisuiuchiha:BAABLgAECn8lAAIBAAgJewhdBwCgAAABAAgJewhdBwCgAAAAAA==.Shoiz:BAAALgAECgQJBQAAAA==.Shon:BAAALgAECgEJAQAAAA==.Shootumup:BAAALgAECgkJEgAAAA==.Shootybithc:BAAALgADCgEJAQAAAA==.Shuhari:BAAALgAECgkJEwAAAQ==.Shyx:BAABLgAECn8sAAIFAAgJxhpxAAACAgAFAAgJxhpxAAACAgAAAA==.',
Si='Siilas:BAACLgAFFH8aAAQdAAQJNgkxZgD6AAAdAAQJnQcxZgD6AAAZAAEJhw9mKQBEAAAeAAIJ7QC4LAAyAAAuAAQKfyoAAx0ACQljF7YqAC8CAB0ACQljF7YqAC8CAB4ABAlQBwFBALEAAAAA.Sinamon:BAABLgAECn8xAAIKAAgJGSGyJAByAgAKAAgJGSGyJAByAgAAAA==.Sinani:BAABLgAECn83AAIBAAkJFAcfiABnAQABAAkJFAcfiABnAQAAAA==.Sinista:BAAALgAECgUJBQAAAA==.Sinnamon:BAAALgAECgYJEgABLgAECggJMQAKABkhAA==.Sipnspin:BAAALgAECgEJAgAAAA==.',
Sj='Sjdh:BAABLgAECn8XAAIGAAcJnBLWawBMAQAGAAcJnBLWawBMAQABLgAECgkJMQAaADAUAA==.Sjrogue:BAABLgAECn8xAAIaAAkJMBRfEwAJAgAaAAkJMBRfEwAJAgAAAA==.',
Sk='Skjolvarn:BAEALgAECgMJBwAAAA==.Skram:BAAALgAECgMJBAAAAA==.',
Sl='Slammydooker:BAABLgAECn8fAAMaAAkJ0hV1EwAIAgAaAAkJ0hV1EwAIAgAmAAEJ1QcMIQAtAAAAAA==.Slammyhole:BAAALgAECgEJAQAAAA==.Sleeptoken:BAAALgAECgMJCAAAAA==.Slyphz:BAAALgAECgYJBgAAAA==.',
Sm='Smallkat:BAAALgAECgEJAQAAAA==.Smightymouse:BAAALgAECgEJAQAAAA==.',
Sn='Snoipuh:BAAALgAECgUJBwAAAA==.',
So='Solas:BAAALgAECgQJBwAAAA==.Soletaken:BAAALgADCggJDwAAAA==.Solio:BAAALgADCgYJFQAAAA==.Solisha:BAAALgAECgQJBAAAAA==.Somberdh:BAAALgADCgcJBwAAAA==.Sonofsand:BAAALgAECgIJAgAAAA==.Soulja:BAAALgADCgEJAgAAAA==.Soulmoethus:BAAALgADCgYJCQAAAA==.',
Sp='Sprayandpray:BAABLgAECn8aAAIBAAUJqh3DjgBaAQABAAUJqh3DjgBaAQAAAA==.Sprinklely:BAAALgADCgcJCgAAAA==.',
Sq='Squidnips:BAAALgAECgEJAgAAAA==.Squirtney:BAAALgADCgMJAwAAAA==.',
Ss='Ss:BAACLgAFFH8PAAIeAAMJjQGiFQCPAAAeAAMJjQGiFQCPAAAuAAQKfxUAAh4ABwlxDN4WAO0AAB4ABwlxDN4WAO0AAAAA.Ssl:BAAALgADCgQJBAAAAA==.',
St='Starrwood:BAABLgAECn8kAAIRAAkJPgnoaQBuAQARAAkJPgnoaQBuAQAAAA==.Statik:BAAALgAECgIJAwAAAA==.Statík:BAAALgAECgEJAQABLgAECgIJAwACAAAAAA==.Stepmonk:BAAALgAECgEJAQAAAA==.Stevesharts:BAAALgADCgYJCwAAAA==.Stonedlock:BAAALgADCgcJCAAAAA==.Stonetusk:BAAALgAECgUJCQAAAA==.Stroya:BAAALgAECgUJBgAAAA==.',
Su='Sumnèr:BAAALgAECgcJBwAAAA==.Sunastiri:BAAALgADCgkJCQAAAA==.Sunpali:BAAALgAECgcJCwAAAA==.',
Sw='Swank:BAAALgADCgEJAQAAAA==.',
Sx='Sx:BAAALgADCgIJAgAAAA==.',
Sy='Syaa:BAAALgAECgYJBQAAAA==.Syberis:BAAALgADCgcJDgAAAA==.',
Ta='Tacholy:BAABLgAECn8VAAIKAAkJzBdSaACeAQAKAAkJzBdSaACeAQABLgAECgkJLwANAJQcAA==.Tacodaboss:BAABLgAECn8XAAIQAAYJLw+YMwDzAAAQAAYJLw+YMwDzAAAAAA==.Talelarissia:BAAALgADCgQJBAAAAA==.Talonflame:BAABLgAECn8fAAIUAAkJBBy6BwB4AgAUAAkJBBy6BwB4AgAAAA==.Tansu:BAAALgAECgYJEwAAAA==.Tapered:BAAALgAECgUJCQAAAA==.Taupo:BAACLgAFFH8ZAAIXAAQJ6x//IQBeAQAXAAQJ6x//IQBeAQAuAAQKfycAAhcACQlyH6kNAHoCABcACQlyH6kNAHoCAAAA.',
Tb='Tbanger:BAAALgAECgYJDwAAAA==.Tbh:BAAALgAFFAEJAgABLgAFFAcJFQAXAAscAA==.',
Te='Techevo:BAAALgAECgQJBQAAAA==.Techfire:BAABLgAECn8pAAInAAkJ9hpBAgBFAgAnAAkJ9hpBAgBFAgAAAA==.Techsmexx:BAAALgAECgMJBQAAAA==.Tempina:BAAALgADCgkJCwAAAA==.Tenebron:BAABLgAECn8vAAIoAAYJQBISJwD6AAAoAAYJQBISJwD6AAAAAA==.Tenlucis:BAAALgAECggJDAAAAA==.',
Th='Thaelyssa:BAAALgAECgEJAQAAAA==.Tharria:BAAALgADCgcJBwAAAA==.Thearia:BAABLgAECn8bAAMPAAgJrRWBUgBcAQAPAAgJrRWBUgBcAQASAAUJmg5hVgC3AAAAAA==.Thecanmurk:BAAALgADCgkJEgAAAA==.Thedilf:BAAALgADCgEJAQAAAA==.Thicktotem:BAAALgAECgIJAgAAAA==.Thickumz:BAAALgAECgMJCgAAAA==.Thisismeta:BAAALgAECgYJDAAAAA==.Thorenis:BAAALgADCgEJAQAAAA==.Thoryndruid:BAACLgAFFH8TAAIiAAYJBB3FAgCoAQAiAAYJBB3FAgCoAQAuAAQKfzIAAyIACQkWIxEDAA4DACIACQnmIhEDAA4DAAwABwm8HlYNAAwCAAEuAAUUCAkcABUAkxkA.Thorïn:BAAALgADCgMJAwAAAA==.Thorýn:BAACLgAFFH8cAAIVAAgJkxncFwAhAgAVAAgJkxncFwAhAgAuAAQKfxoAAhUACAl8HuIqAFUCABUACAl8HuIqAFUCAAAA.Thórin:BAABLgAECn8oAAITAAgJQxciDwDRAQATAAgJQxciDwDRAQAAAA==.',
Ti='Timakk:BAAALgADCgEJAQAAAA==.Tipsy:BAABLgAECn8uAAMEAAkJWg/vOADMAQAEAAkJWg/vOADMAQADAAMJpA3adwCGAAAAAA==.',
To='Tombraider:BAAALgAECgUJCAAAAA==.Tomfoolary:BAAALgAECgEJAwAAAA==.Toofy:BAAALgAECgEJAQAAAA==.Tot:BAAALgAECgkJCwAAAA==.Total:BAAALgADCgkJDAAAAA==.Totembear:BAAALgAECgEJAwABLgAFFAIJBwASABUFAA==.',
Tr='Tralleth:BAABLgAECn8nAAMIAAkJIRWvAABdAQAIAAgJCRSvAABdAQAHAAIJvQ3oMABmAAAAAA==.Trid:BAAALgAECgQJBQAAAA==.Trillbilly:BAAALgAECgEJAQAAAA==.Trinora:BAAALgADCgkJDgAAAA==.Troginator:BAAALgAECgEJAQAAAA==.Trolltard:BAAALgAECgIJAgABLgAECgQJBAACAAAAAA==.Troxa:BAAALgAECgUJCgAAAA==.',
Tu='Tuckard:BAAALgADCgEJAQAAAA==.Tuskor:BAAALgAFFAEJAQAAAA==.',
Tw='Twinklord:BAAALgAECgkJDwAAAA==.',
Ty='Tylanar:BAAALgAECgYJBgAAAA==.Tylolight:BAAALgADCgMJAwAAAA==.Tylomist:BAAALgAECgUJBQAAAA==.Tylototem:BAAALgAFFAEJAgAAAA==.',
['Tö']='Tötem:BAAALgAFFAEJAQABLgAFFAUJFAAWAPcgAA==.',
Ug='Uglyboi:BAAALgAECggJDwAAAA==.',
Uj='Ujcmonk:BAAALgAECgQJBAAAAA==.',
Ul='Ullbian:BAAALgADCgMJAwAAAA==.Ultramar:BAAALgADCgEJAQAAAA==.',
Un='Uncookedham:BAAALgAECgQJCwAAAA==.',
Ur='Urgh:BAABLgAECn8fAAIJAAkJ9RHKIwCrAQAJAAkJ9RHKIwCrAQAAAA==.Urk:BAAALgAECgYJBgAAAA==.Urzaa:BAAALgAECgEJAwABLgAECgMJBAACAAAAAA==.',
Ut='Uthur:BAAALgAECgMJAwAAAA==.',
Va='Vaeelrundor:BAAALgAECgcJDwAAAA==.Valethales:BAAALgADCgcJBwAAAA==.Valyr:BAAALgAECgEJAQAAAA==.Vanillaface:BAABLgAECn8ZAAIKAAkJ7xzVHQCTAgAKAAkJ7xzVHQCTAgAAAA==.Vape:BAABLgAECn8WAAIdAAcJLg2yegBEAQAdAAcJLg2yegBEAQABLgAFFAUJEAARAMYbAA==.',
Ve='Veinripp:BAAALgADCgUJBQABLgAECggJNAAGAO0QAA==.Velarael:BAABLgAECn8rAAIdAAcJ9QsEjAAiAQAdAAcJ9QsEjAAiAQAAAA==.Velaryn:BAAALgADCgIJAgAAAA==.Veldar:BAAALgADCgIJAgABLgAECgUJBgACAAAAAA==.Velekete:BAAALgADCgUJBQAAAA==.Velethei:BAABLgAECn8YAAIPAAYJlySkGQBrAgAPAAYJlySkGQBrAgAAAA==.Velian:BAAALgADCgMJBAAAAA==.Velielyn:BAAALgADCgQJBAAAAA==.Vellareth:BAAALgAECgEJAQAAAA==.Verdesalsa:BAAALgAECgcJDQAAAA==.Verox:BAAALgADCgMJAwAAAA==.Verzak:BAAALgAECgUJBQAAAA==.',
Vh='Vheckxus:BAACLgAFFH8FAAIDAAIJAA1bSABtAAADAAIJAA1bSABtAAAuAAQKfxoAAgMABgloFABAADQBAAMABgloFABAADQBAAAA.',
Vi='Vicv:BAABLgAECn8TAAIJAAkJXwwXNABIAQAJAAkJXwwXNABIAQAAAA==.Vivy:BAAALgAECgcJBwAAAA==.',
Vo='Voidberg:BAAALgAECgkJEwAAAA==.',
['Vê']='Vêa:BAAALgADCgkJCQAAAA==.',
Wa='Wachonaso:BAACLgAFFH8TAAIdAAcJwwzKNgBuAQAdAAcJwwzKNgBuAQAuAAQKfy0AAx0ABwlJH6M0ADkCAB0ABwkrH6M0ADkCAB4ABgl8HlgXAI8BAAAA.Wanbahl:BAAALgADCgMJAwAAAA==.',
We='Wellburt:BAAALgAECgEJAQAAAA==.',
Wh='Whatuphuz:BAAALgADCgQJBQAAAA==.Wheresmyjaw:BAACLgAFFH8iAAQdAAUJJSA4PgBVAQAdAAUJmh44PgBVAQAZAAEJWSO+FQBnAAAeAAEJOQLbLAAxAAAuAAQKfycABB0ACAnyIe0WAJoCAB0ACAnyIe0WAJoCAB4AAgm6DiRSAHcAABkAAQnAILYvAF8AAAAA.',
Wi='Wildstàr:BAAALgADCgMJAwAAAA==.Wildthree:BAABLgAECn8rAAMYAAkJwh0HCgCjAgAYAAkJwh0HCgCjAgAcAAMJ2RQvYgC5AAAAAA==.Willenda:BAAALgAECgEJAwAAAA==.Willowins:BAAALgAECgEJAQAAAA==.Winterstired:BAACLgAFFH8gAAIkAAQJRiYOAQAmAQAkAAQJRiYOAQAmAQAuAAQKf0IAAyQACQnuJIQCAHkDACQACQnuJIQCAHkDAAUAAQlKF1pyAEQAAAAA.',
Wo='Woen:BAAALgADCggJCQAAAA==.Wolf:BAAALgAECgQJBwAAAA==.Wollffie:BAAALgAECgQJBAAAAA==.',
Wu='Wuinn:BAAALgAFFAEJAQABLgAFFAIJAgACAAAAAA==.Wut:BAAALgADCgcJBwAAAA==.',
Wy='Wynterswrath:BAAALgAECgcJDQAAAA==.',
['Wõ']='Wõnderful:BAABLgAECn8aAAIPAAcJPhvdJAAlAgAPAAcJPhvdJAAlAgABLgAFFAUJFAAWAPcgAA==.',
Xc='Xclobber:BAAALgADCgIJAgAAAA==.',
Xe='Xemnass:BAAALgAECgUJBwAAAA==.',
Xi='Xillas:BAAALgADCgUJBQAAAA==.',
Xo='Xoverkll:BAAALgAECgYJDAAAAA==.',
Xy='Xylina:BAAALgADCgEJAQAAAA==.Xyrii:BAAALgADCgEJAQAAAA==.',
Ya='Yadder:BAAALgAECgIJBAABLgAFFAMJBQAEAI0eAA==.Yahro:BAACLgAFFH8RAAIKAAYJtQ8pRAAjAQAKAAYJtQ8pRAAjAQAuAAQKfzMAAgoACQkqIKcOAPACAAoACQkqIKcOAPACAAAA.Yamelow:BAAALgAECgQJBwAAAA==.',
Ye='Yeahiknow:BAAALgADCgkJDgAAAA==.Yeling:BAAALgAECgIJAgAAAA==.Yep:BAAALgAECgcJBwAAAA==.',
Yi='Yiska:BAAALgADCgcJBwAAAA==.',
Yo='Yoriale:BAAALgAECgYJDgAAAA==.Yotoymuerto:BAAALgAECgQJBAAAAA==.',
Za='Zafra:BAAALgADCgEJAQAAAA==.Zaimara:BAAALgAECgEJBgAAAA==.Zalind:BAABLgAECn8VAAIdAAkJCxJoZgCYAQAdAAkJCxJoZgCYAQAAAA==.Zalvianna:BAABLgAECn8iAAMBAAgJLQRJxAADAQABAAgJLQRJxAADAQAlAAEJXQHIIgAYAAAAAA==.Zarindlina:BAAALgADCgUJBQAAAA==.Zarshx:BAAALgAECgYJCwABLgAFFAMJBAACAAAAAA==.',
Ze='Zemonk:BAAALgAECgYJBgAAAA==.',
Zi='Zilong:BAAALgAFFAEJAQABLgAFFAUJDwAGAAEaAA==.Zilongmage:BAAALgAFFAIJAwABLgAFFAUJDwAGAAEaAA==.Zilongwar:BAAALgAFFAMJAwABLgAFFAUJDwAGAAEaAA==.Zinnia:BAAALgADCgEJAgAAAA==.',
Zo='Zonedk:BAABLgAECn8WAAQWAAYJfB92EwBEAQAbAAUJQCFmHwBaAQAWAAYJLBZ2EwBEAQAVAAEJxBcyYgFBAAABLgAFFAIJAgACAAAAAA==.Zonerg:BAAALgADCgEJAgABLgAFFAIJAgACAAAAAA==.Zonevn:BAAALgAFFAIJAgAAAA==.Zordak:BAAALgADCgcJCAAAAA==.Zosin:BAAALgAECgIJAgAAAA==.',
Zu='Zugzugzapzap:BAAALgADCgEJAQAAAA==.',
Zy='Zylphanae:BAAALgAECgQJBAAAAA==.',
['Øl']='Ølaf:BAAALgAECgEJAQABLgAFFAQJGQAXAOsfAA==.',
['Ør']='Ørsted:BAAALgAECgEJAgABLgAFFAQJGQAXAOsfAA==.',
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
