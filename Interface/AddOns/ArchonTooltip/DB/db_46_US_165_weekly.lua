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

local lookup = {'Mage-Frost','Unknown-Unknown','Shaman-Elemental','Shaman-Restoration','Priest-Discipline','DemonHunter-Devourer','Hunter-BeastMastery','Evoker-Preservation','Evoker-Augmentation','Warrior-Arms','Priest-Shadow','Hunter-Marksmanship','Paladin-Retribution','Rogue-Subtlety','Druid-Guardian','Warrior-Fury','Druid-Restoration','DemonHunter-Havoc','Druid-Balance','Paladin-Protection','Paladin-Holy','Hunter-Survival','DeathKnight-Unholy','DeathKnight-Frost','Monk-Mistweaver','Monk-Windwalker','Warlock-Affliction','DeathKnight-Blood','Monk-Brewmaster','Warlock-Demonology','Warlock-Destruction','Evoker-Devastation','Shaman-Enhancement','DemonHunter-Vengeance','Druid-Feral','Rogue-Assassination','Priest-Holy','Mage-Arcane','Mage-Fire','Warrior-Protection',}
local provider = {region='US',realm='Nazjatar',name='US',type='weekly',zone=46,date='2026-08-04',data={Aa='Aaela:BAAALgADCgUJBQAAAA==.',
Ab='Abrasaxs:BAABLgAECn8qAAIBAAgJQhijWQDQAQABAAgJQhijWQDQAQAAAA==.Absylus:BAAALgAECgQJBAABLgAFFAMJBAACAAAAAA==.',
Ac='Accoli:BAAALgAFFAEJAQAAAA==.Ackerman:BAAALgAECgYJCgABLgAECggJEgACAAAAAA==.Acoli:BAAALgADCgYJBgAAAA==.Acraea:BAABLgAECn8hAAIBAAgJmwwuhABvAQABAAgJmwwuhABvAQAAAA==.Acràea:BAAALgAFFAEJAQAAAA==.Acslater:BAAALgAECgQJDQAAAA==.Actionman:BAAALgAECgkJBwAAAA==.',
Ad='Adversary:BAAALgAFFAIJAgAAAA==.',
Ag='Agoobagoo:BAACLgAFFH8gAAMDAAcJnB3MDQDOAQADAAcJnB3MDQDOAQAEAAEJ6yFfOgBjAAAuAAQKfyMAAgMACQnZIpAEAFIDAAMACQnZIpAEAFIDAAAA.',
Ai='Aionn:BAAALgAECgMJAwAAAA==.Airrow:BAABLgAECn8UAAIFAAkJEhk3EABuAgAFAAkJEhk3EABuAgAAAA==.Aissae:BAACLgAFFH8PAAIGAAQJ7hwUOQBAAQAGAAQJ7hwUOQBAAQAuAAQKfy0AAgYACAlEJHYLACYDAAYACAlEJHYLACYDAAAA.Aiyama:BAAALgADCgQJBAAAAA==.',
Ak='Akiio:BAAALgAECgMJAwAAAA==.Akumaxl:BAAALgAECgYJBwAAAA==.',
Al='Alexia:BAAALgAECgEJAQAAAA==.Alfrank:BAAALgAECgIJAwAAAA==.Aliasx:BAAALgAECgMJBAAAAA==.Allwrong:BAAALgAECgUJBgAAAA==.Alphadog:BAEBLgAFFH8LAAIHAAYJFRFWFAB5AQAHAAYJFRFWFAB5AQABLgAFFAgJHwAHAI0NAA==.Alphrank:BAAALgAECgEJAgAAAA==.Alurie:BAAALgAECgcJDAAAAA==.Alustre:BAAALgAFFAEJAQAAAA==.',
Am='Amahlfarouk:BAAALgAECgYJDgAAAA==.Amandrada:BAAALgAFFAEJAQAAAA==.Ambros:BAAALgADCgYJBgAAAA==.Aminatou:BAAALgAECgYJBwAAAA==.',
An='Angerfang:BAAALgADCgUJCgAAAA==.Angriff:BAAALgAECgEJAgAAAA==.Anheeboan:BAAALgAECgYJCwAAAA==.Anihilated:BAAALgADCgYJBwAAAA==.',
Ar='Aradiax:BAAALgADCgYJBgAAAA==.Arathion:BAAALgAECgIJAgAAAA==.Arcadavia:BAAALgADCgMJAwAAAA==.Aren:BAABLgAECn8WAAIBAAYJ0Re0DwBgAQABAAYJ0Re0DwBgAQAAAA==.Ariaprime:BAABLgAECn8dAAIBAAcJQRbPEABRAQABAAcJQRbPEABRAQAAAA==.Ariseigris:BAAALgAECgYJCAAAAA==.Arjentheilus:BAAALgAECgMJAwAAAA==.Armandox:BAAALgAECgEJAQAAAA==.Arthasl:BAAALgADCgMJAgAAAA==.Arthur:BAAALgAECgQJDgAAAA==.',
As='Asasda:BAAALgADCgMJBAAAAA==.Ashaelra:BAAALgAECgYJCAAAAA==.Astravaritan:BAAALgADCgMJAwAAAA==.Astrá:BAAALgAECgYJEQAAAA==.',
At='Atherya:BAAALgAECgYJCAAAAA==.Atomixblonde:BAAALgAECgQJBAAAAA==.',
Au='Augonly:BAACLgAFFH8eAAIIAAcJQxdhCgAFAgAIAAcJQxdhCgAFAgAuAAQKfyMAAggACQnpIC4GAOECAAgACQnpIC4GAOECAAAA.Augy:BAACLgAFFH8OAAIJAAQJMg0rNwDoAAAJAAQJMg0rNwDoAAAuAAQKfx0AAwkACQkyGvMcAO8BAAkACAnlGPMcAO8BAAgAAQmSBOk+ACkAAAAA.Autoshot:BAAALgAFFAIJAgAAAA==.',
Av='Averisbelia:BAABLgAECn8ZAAIKAAYJ5gf8DQB7AAAKAAYJ5gf8DQB7AAAAAA==.',
Ay='Ayowamsley:BAAALgADCgMJAwAAAA==.',
Az='Azalea:BAAALgAECggJEAABLgAECgkJCgACAAAAAA==.',
Ba='Babycrock:BAAALgADCgYJBgAAAA==.Back:BAAALgADCgcJDAAAAA==.Bakihanma:BAAALgAECgQJBgAAAA==.Balash:BAAALgADCgUJBQAAAA==.Balerion:BAAALgADCgEJAQABLgADCgMJAwACAAAAAA==.Balthasar:BAABLgAECn8rAAILAAkJ/xpYDwBkAgALAAkJ/xpYDwBkAgAAAA==.Banjobits:BAAALgADCgIJAgAAAA==.Barhead:BAAALgAECgYJDAAAAA==.Barlow:BAABLgAECn8WAAIMAAkJUQhUFwD5AAAMAAkJUQhUFwD5AAAAAA==.Barqose:BAAALgADCgMJAwAAAA==.Barryberry:BAABLgAECn8fAAINAAkJDRE0fgByAQANAAkJDRE0fgByAQAAAA==.Barryx:BAAALgAECgIJAgAAAA==.Baumert:BAAALgADCgEJAQAAAA==.',
Bb='Bbldrizzy:BAABLgAFFH8GAAMEAAMJjR5+PQDuAAAEAAMJjR5+PQDuAAADAAEJyRCpNwA5AAABLgAFFAQJDAAOAGQRAA==.',
Be='Beandipp:BAAALgAECgQJBwAAAA==.Bearful:BAAALgADCgMJAwAAAA==.Beastlieduke:BAAALgAECgMJAwABLgAFFAgJGAALAMMMAA==.Beastlièduke:BAACLgAFFH8YAAILAAgJwwwdEgBXAQALAAgJwwwdEgBXAQAuAAQKfzQAAgsACQkfIE8MAIsCAAsACQkfIE8MAIsCAAAA.Beauslay:BAAALgAECgEJAQAAAA==.Belephon:BAAALgAECgYJEAAAAA==.Belinda:BAAALgAECgUJBQAAAA==.Bellaruhbz:BAABLgAECn8eAAIMAAkJjA+0FwD1AAAMAAkJjA+0FwD1AAAAAA==.Berenstain:BAABLgAECn8nAAIPAAkJShP8FwCSAQAPAAkJShP8FwCSAQAAAA==.Bergmire:BAAALgAECgQJCwAAAA==.Berple:BAAALgADCgUJBQABLgAFFAkJJAABACMjAA==.Bestoresto:BAABLgAECn8XAAIEAAkJBQwTRACdAQAEAAkJBQwTRACdAQAAAA==.',
Bh='Bhori:BAAALgAECgEJAwAAAA==.',
Bi='Bibahabibi:BAABLgAECn8dAAMKAAYJxhvpJQA5AQAKAAYJxhvpJQA5AQAQAAMJzQiVhwChAAAAAA==.Bighunt:BAAALgAECgEJAQAAAA==.Bigpapax:BAAALgAECgEJAQAAAA==.Bigtac:BAABLgAECn8vAAMKAAkJlBxYCQBbAgAKAAkJlBxYCQBbAgAQAAIJ3gc5mQBcAAAAAA==.Bimmylee:BAAALgAFFAEJAgAAAA==.Binggus:BAAALgAFFAEJAQAAAA==.Bipolaire:BAAALgADCgEJAQAAAA==.',
Bl='Blabbybootze:BAAALgAECgkJDwAAAA==.Bladelight:BAAALgAECgYJCAAAAA==.Blighte:BAAALgADCgQJBAABLgAECggJIQARAIIkAA==.Blightfangs:BAACLgAFFH8MAAIBAAMJjBAgPQDQAAABAAMJjBAgPQDQAAAuAAQKf0kAAgEACQnyGo80AEYCAAEACQnyGo80AEYCAAAA.Blindnautdef:BAABLgAECn80AAMGAAgJ7RAeagBRAQAGAAgJ7RAeagBRAQASAAEJ9gPefgAhAAAAAA==.Bloodluna:BAAALgADCgUJBQAAAA==.',
Bo='Bobman:BAAALgAECgUJCAAAAA==.Bodakye:BAACLgAFFH8QAAIHAAMJOhLeaADTAAAHAAMJOhLeaADTAAAuAAQKfygAAwcACQmYG1IuACMCAAcACQmYG1IuACMCAAwAAgm0ARCBAEMAAAAA.Bonargrowrod:BAABLgAECn8cAAINAAkJCAdAHQDnAAANAAkJCAdAHQDnAAAAAA==.Bonkz:BAAALgAECgMJAwAAAA==.Boomiekins:BAAALgADCgIJAgAAAA==.Boomtip:BAAALgADCgMJAwAAAA==.Boon:BAAALgADCgYJCQAAAA==.Boow:BAAALgAECgMJAwAAAA==.Bordolor:BAAALgAECgEJAQAAAA==.Bowsa:BAAALgAECgkJAQAAAA==.',
Br='Bracalina:BAAALgAECgcJDQABLgAFFAIJDAABAEUOAA==.Brethathes:BAAALgAECgkJEgAAAA==.Brudda:BAAALgADCgUJBQAAAA==.',
Bu='Bubbaray:BAAALgAECgMJAwAAAA==.Bubblebun:BAAALgAECgMJBgAAAA==.Bungerhole:BAABLgAECn8WAAMRAAgJxRtRMADhAQARAAgJxRtRMADhAQATAAEJEQllmwAmAAAAAA==.Butane:BAAALgADCgIJAgAAAA==.Buzzbuzz:BAAALgAECgIJBwAAAA==.',
Ca='Caeruleus:BAAALgAECgEJAgAAAA==.Cainn:BAAALgAECgYJBwAAAA==.Cameltotem:BAAALgAECgIJAQABLgAFFAYJBwAJAIUCAA==.Cap:BAAALgADCgEJAQABLgAFFAUJGwABAGIeAA==.Capnstabr:BAAALgADCgIJAgAAAA==.Capriestsun:BAAALgAFFAMJAwABLgAFFAQJDAAOAGQRAA==.Captyn:BAABLgAECn8hAAIUAAgJixCFGgBEAQAUAAgJixCFGgBEAQAAAA==.Carridin:BAAALgADCgMJAwAAAA==.Cass:BAAALgAECgEJAQAAAA==.',
Ce='Cernunon:BAAALgADCgEJAQAAAA==.Ceroquel:BAAALgAECgMJAwAAAA==.',
Ch='Chaosdemon:BAABLgAECn81AAIGAAkJPRDIRQC1AQAGAAkJPRDIRQC1AQAAAA==.Chaosraven:BAAALgADCgkJCQAAAA==.Chapelgnome:BAAALgAECgUJCQABLgAFFAYJBwAJAIUCAA==.Charizardx:BAAALgAECgEJAgAAAA==.Charlottea:BAAALgAECgYJDwAAAA==.Chemdra:BAAALgAECgcJEwAAAA==.Chewthymight:BAABLgAECn8YAAMVAAkJpRS4PABUAQAVAAcJ+w+4PABUAQANAAUJKxA6GAANAQAAAA==.Chiling:BAAALgAECgEJAQAAAA==.Chipmonkey:BAAALgAECgEJAgABLgAECgkJNAARAMEPAA==.Chiptime:BAABLgAECn80AAIRAAkJwQ94NwC6AQARAAkJwQ94NwC6AQABLgAECgkJNAARAMEPAA==.Chomby:BAAALgAECgQJAwAAAA==.Chromosomes:BAAALgAECgQJBAAAAA==.Chud:BAAALgAECgQJCQAAAA==.Chudsworth:BAAALgADCgYJCQAAAA==.Chukk:BAAALgADCgYJBgAAAA==.Chunguhlumpo:BAAALgAECgEJBAAAAA==.Chzburger:BAAALgAFFAEJAQAAAA==.',
Ci='Cinnamóróll:BAABLgAECn9WAAIWAAkJbxQNAgDtAQAWAAkJbxQNAgDtAQAAAA==.',
Cl='Clairity:BAAALgAECgMJAwAAAA==.Clare:BAAALgAFFAEJAQAAAA==.Cleru:BAABLgAECn8fAAMXAAgJxhNYfABrAQAXAAgJxhNYfABrAQAYAAEJpwMVGgAlAAAAAA==.Cletus:BAAALgADCgcJAgAAAA==.',
Co='Coa:BAAALgAECgkJDAAAAA==.Cocoon:BAABLgAFFH8XAAMZAAgJ7RoLEAARAgAZAAcJdRwLEAARAgAaAAQJmw5lFgBvAAAAAA==.Coldsoul:BAAALgAECggJEQAAAA==.Comanderkush:BAAALgADCgMJAwAAAA==.Coran:BAAALgAECgIJAwABLgAECgkJJAAbAG0bAA==.Corita:BAAALgAECgIJAgAAAA==.Cowboi:BAAALgADCgMJAwAAAA==.Cowhealer:BAABLgAECn8hAAMRAAgJgiRkCAAIAwARAAgJgiRkCAAIAwATAAEJTwUTgQAvAAAAAA==.Cozak:BAAALgAECgEJAQAAAA==.',
Cr='Craeftigdh:BAAALgAECgEJAQABLgAECgkJOwABAHEfAA==.Craeftigdk:BAAALgAECgYJCQABLgAECgkJOwABAHEfAA==.Creamypies:BAAALgAECgEJAQAAAA==.Crepitus:BAAALgADCgIJAQAAAA==.Criticaltwo:BAAALgADCgIJAgAAAA==.Crockknight:BAAALgADCgYJBgAAAA==.Crossways:BAAALgAECgYJCQAAAA==.Crusabull:BAAALgADCgUJBQAAAA==.Cryochri:BAAALgAECgEJAQAAAA==.Cræftig:BAABLgAECn87AAIBAAkJcR/mAwCjAgABAAkJcR/mAwCjAgAAAA==.',
Cu='Cursecthree:BAAALgADCgEJAQAAAA==.Curseword:BAAALgAECgEJAQAAAA==.Cutestxx:BAAALgAECgkJCwAAAA==.',
Cy='Cynnithice:BAAALgADCgYJBgABLgAFFAIJDAABAEUOAA==.Cyxo:BAAALgADCgEJAQABLgAECgEJAQACAAAAAA==.',
Da='Dadune:BAAALgAECgEJAQABLgAECgUJCgACAAAAAA==.Daftxshade:BAABLgAECn8UAAIOAAYJpxEwCADtAAAOAAYJpxEwCADtAAAAAA==.Danasatral:BAAALgADCgEJAQAAAA==.Dandandan:BAAALgADCgMJAwAAAA==.Dapan:BAAALgADCgcJDQAAAA==.Dariaa:BAABLgAECn8UAAIHAAUJew0EsQDiAAAHAAUJew0EsQDiAAAAAA==.Darkcrusader:BAAALgAECgcJEAAAAA==.Darkheal:BAAALgADCgUJBQAAAA==.Darkladie:BAAALgADCgEJAQAAAA==.Darkshadows:BAAALgAECgUJEAAAAA==.Darktank:BAAALgAECgIJAgAAAA==.Darthsyde:BAABLgAECn8iAAIcAAkJzBKAHAB2AQAcAAkJzBKAHAB2AQAAAA==.Dasdk:BAABLgAFFH8SAAIXAAQJzCK5OwCCAQAXAAQJzCK5OwCCAQAAAA==.Daspriest:BAAALgADCgYJDQABLgAFFAQJEgAXAMwiAA==.Dayanna:BAAALgAECgIJAgAAAA==.',
De='Deadergriff:BAAALgAECgkJDQAAAA==.Deadhippycb:BAAALgAECgQJBAAAAA==.Deadhippyxy:BAAALgAECgEJAwAAAA==.Deadicated:BAABLgAECn8gAAQdAAgJzgdlRgDhAAAdAAcJLAZlRgDhAAAaAAcJQgidYACZAAAZAAUJaQURjwB8AAAAAA==.Deadsies:BAAALgADCgIJAgABLgAFFAMJBQAcAPsIAA==.Deeds:BAAALgAECgMJAwAAAA==.Delan:BAAALgAECgQJBQAAAA==.Delveknight:BAAALgADCgYJBgABLgAECgcJFwAXAHUdAA==.Demoncox:BAAALgADCgMJAgAAAA==.Demondoc:BAACLgAFFH8SAAIGAAYJgQ3JTAAEAQAGAAYJgQ3JTAAEAQAuAAQKfx8AAgYACAlpF+E0APMBAAYACAlpF+E0APMBAAAA.Desunaito:BAACLgAFFH8nAAMYAAgJTBziAgAIAgAYAAgJTBziAgAIAgAcAAEJAACHXAAAAAAuAAQKfy0AAhgACQlUJWkBACcDABgACQlUJWkBACcDAAAA.Devious:BAAALgADCgEJAQAAAA==.Dexter:BAAALgAECgMJBAAAAA==.',
Dh='Dhzilong:BAACLgAFFH8QAAIGAAUJARoZRgAVAQAGAAUJARoZRgAVAQAuAAQKfx0AAwYACAlHIU84ABQCAAYACAkzHk84ABQCABIABQmNJJEeAMoBAAAA.',
Di='Diddlefiddle:BAACLgAFFH8PAAMWAAUJjSB2CQB/AQAWAAUJjSB2CQB/AQAMAAIJKBCHLQBWAAAuAAQKfxYABBYACAn5Hx8JAIwCABYABwn5Hx8JAIwCAAwAAwlmIU0fALQAAAcAAQkgHGi3AFQAAAAA.Dihcum:BAABLgAFFH8GAAIXAAIJyAvM+wBxAAAXAAIJyAvM+wBxAAAAAA==.Dimonologist:BAAALgAECgEJAQAAAA==.Dinzarn:BAAALgADCgEJAQAAAA==.Dirtycow:BAAALgAECgQJBAAAAA==.',
Dk='Dkzilong:BAAALgAFFAIJBAABLgAFFAUJEAAGAAEaAA==.',
Dm='Dmeo:BAAALgAECgcJCQAAAA==.',
Do='Docarcanis:BAAALgAFFAIJAgAAAA==.Docholy:BAAALgAECgYJCAABLgAFFAYJEgAGAIENAA==.Dockson:BAAALgAECgMJAwAAAA==.Docwyle:BAABLgAECn8XAAMeAAgJnxEecwBUAQAeAAgJnxEecwBUAQAfAAEJtgLUcgAzAAABLgAFFAYJEgAGAIENAA==.Doktorfaust:BAAALgAECgEJAQABLgAECgMJBAACAAAAAA==.Doobyia:BAAALgADCgEJAQAAAA==.Dorki:BAAALgAECgEJAgAAAA==.Dorlanlemeth:BAABLgAECn8VAAIGAAcJBwwyhAAXAQAGAAcJBwwyhAAXAQAAAA==.Dormist:BAAALgAECgMJBAABLgAECgkJJAAbAG0bAA==.Dortrak:BAAALgAECgcJBwAAAA==.Dotti:BAAALgAFFAEJAQAAAA==.',
Dr='Dracnogard:BAAALgAECggJDwAAAA==.Dracowulf:BAABLgAECn8nAAIHAAkJPhG4PgDmAQAHAAkJPhG4PgDmAQAAAA==.Dragonx:BAABLgAECn86AAMHAAkJoBfKCADmAQAHAAkJoBfKCADmAQAWAAMJaQ3YRACtAAAAAA==.Drakos:BAAALgAECgEJAQAAAA==.Drakowolf:BAABLgAECn9PAAIgAAkJ/wegDwARAQAgAAkJ/wegDwARAQAAAA==.Dreadful:BAAALgAECgQJBQABLgAFFAUJGAAFAO8KAA==.Drenz:BAAALgADCgEJAQAAAA==.Dreorge:BAABLgAFFH8HAAMJAAMJcxENQgC/AAAJAAMJcxENQgC/AAAIAAEJdAm2GQAyAAAAAA==.Dreuceratops:BAAALgAECgMJAwAAAA==.Dreux:BAAALgAECgMJAwAAAA==.Drewceratops:BAABLgAECn8pAAINAAkJLhXpRQD0AQANAAkJLhXpRQD0AQAAAA==.Driis:BAAALgAECgEJAQAAAA==.Drimchi:BAABLgAFFH8TAAMJAAYJJBk0LAAUAQAJAAYJ0BU0LAAUAQAgAAMJChlqBACeAAAAAA==.Drimveil:BAAALgAFFAQJBAAAAA==.Drizro:BAAALgADCgIJAgAAAA==.Drk:BAAALgAECgEJAQAAAA==.Drkundead:BAAALgAECgEJAQAAAA==.Dromash:BAABLgAECn8kAAMbAAkJbRuXAwB6AgAbAAkJbRuXAwB6AgAfAAgJLhN3DAB4AQAAAA==.Dromgar:BAABLgAFFH8FAAIDAAIJah4AOwCkAAADAAIJah4AOwCkAAABLgAFFAMJCgAhAAojAA==.Drpepperz:BAAALgAECgMJAwAAAA==.Druidyhealz:BAAALgAECgMJAwABLgAECgcJDwACAAAAAA==.',
Du='Duuke:BAAALgAECgEJAQAAAA==.',
['Då']='Dårius:BAAALgAECgYJEQAAAA==.',
['Dö']='Dööd:BAAALgAECgQJBAAAAA==.',
Ea='Eaterofpaint:BAAALgAECgYJDgAAAA==.',
Ed='Edgeylord:BAAALgAECgEJAQABLgAECgMJBAACAAAAAA==.',
Ef='Effloria:BAABLgAECn8lAAIRAAkJEx3TDAD3AgARAAkJEx3TDAD3AgAAAA==.Efrideet:BAAALgADCgEJAQAAAA==.',
Ei='Eisha:BAAALgADCgUJBQAAAA==.',
El='Elegia:BAACLgAFFH8cAAIeAAcJTg/LIwAJAQAeAAcJTg/LIwAJAQAuAAQKfy8AAx4ACQlWGyIZAL4CAB4ACQlWGyIZAL4CAB8AAQkAAAdmAEMAAAAA.Elerianor:BAABLgAECn8VAAMHAAYJdQZyQQBWAAAHAAYJyARyQQBWAAAMAAQJBgX5MgBPAAAAAA==.Ellektra:BAAALgADCgUJBQAAAA==.Elsocio:BAAALgADCgEJAQAAAA==.',
Em='Emadiropilo:BAAALgAECgEJAQAAAA==.Emakaa:BAAALgAECgYJCAAAAA==.Embrohunter:BAAALgAECgQJBQAAAA==.',
En='Enash:BAAALgAECgQJBwAAAA==.Encoree:BAAALgAECgIJAgAAAA==.Engvald:BAAALgADCgUJBQAAAA==.Enhua:BAAALgADCgUJBQAAAA==.Ennet:BAAALgAECgQJBgAAAA==.',
Er='Erchendor:BAAALgADCgUJBQAAAA==.Eretin:BAAALgADCgEJAQAAAA==.Erismorn:BAABLgAECn8iAAQiAAcJNR5cCwCpAQAiAAYJnBtcCwCpAQAGAAYJiBidWgB4AQASAAEJ4RAEcAA1AAAAAA==.Erulious:BAAALgADCgIJAgAAAA==.',
Eu='Eudi:BAAALgAECgEJAgAAAA==.',
Ev='Eventhorizòn:BAABLgAECn8UAAIGAAgJ8hkYMgAyAgAGAAgJ8hkYMgAyAgAAAA==.Evilhoe:BAAALgADCgUJBQAAAA==.Eviscerated:BAAALgAECgYJCQAAAA==.Evocation:BAAALgAECggJEgAAAA==.Evoextoons:BAAALgAECgUJEQAAAA==.',
Fa='Faith:BAAALgAECgIJAgAAAA==.Fallen:BAABLgAECn8YAAMXAAkJiCSAPAAPAgAXAAkJiCSAPAAPAgAcAAMJ7wvARAB8AAAAAA==.Fallingvoid:BAABLgAECn9oAAMGAAkJvyUaAgC3AwAGAAkJJiQaAgC3AwASAAgJpCTKAgAQAgAAAA==.Fast:BAAALgAECgEJAgABLgAECgIJAgACAAAAAA==.Fatchungus:BAAALgAFFAMJBAAAAA==.Fatherben:BAABLgAECn8XAAIGAAYJVBURgAAgAQAGAAYJVBURgAAgAQAAAA==.Fatmagus:BAAALgAECgcJBgAAAA==.Favio:BAAALgAECggJCwAAAA==.',
Fe='Fellbian:BAAALgADCgcJDgAAAA==.Fentanyahu:BAAALgAECgYJBgAAAA==.Feor:BAAALgAFFAEJAQABLgAECgYJGAAYAOofAA==.Ferozz:BAACLgAFFH8LAAIMAAMJSw70HQC8AAAMAAMJSw70HQC8AAAuAAQKfzEAAgwACAm7HmIHABECAAwACAm7HmIHABECAAAA.',
Fi='Fiercetaco:BAAALgADCgEJAQAAAA==.Finaliter:BAACLgAFFH8eAAINAAUJvxuiOQA5AQANAAUJvxuiOQA5AQAuAAQKfy8AAg0ACQk7IJslAG4CAA0ACQk7IJslAG4CAAAA.Finatar:BAAALgADCgcJCwAAAA==.Fiora:BAABLgAECn8SAAIGAAcJKx87KQBdAgAGAAcJKx87KQBdAgAAAA==.Fitz:BAAALgADCgEJAQAAAA==.Fiveyears:BAAALgADCgEJAQAAAA==.',
Fk='Fknutmcgee:BAAALgAECgUJBQAAAA==.',
Fl='Flamingdrago:BAAALgAECgMJBQAAAA==.Flinti:BAAALgAECgUJCQAAAA==.Flirtyflurry:BAACLgAFFH8MAAIBAAIJRQ7pUQCMAAABAAIJRQ7pUQCMAAAuAAQKf0kAAgEACAlKG30GACMCAAEACAlKG30GACMCAAAA.Floggy:BAABLgAECn8eAAIBAAgJNgilmgBEAQABAAgJNgilmgBEAQAAAA==.',
Fo='Forsight:BAABLgAECn8aAAMXAAgJZhWEgABiAQAXAAgJZhWEgABiAQAcAAEJHRBuGQAtAAAAAA==.',
Fr='Fracker:BAAALgAECgcJCAAAAA==.Frankzzorz:BAACLgAFFH8JAAIZAAMJZgpiRwCHAAAZAAMJZgpiRwCHAAAuAAQKfzQAAxkACQk1HLQMAIcCABkACQk1HLQMAIcCABoAAglFIFtYAK8AAAAA.Freezerbúrnt:BAAALgAECgEJAQAAAA==.Fremder:BAACLgAFFH8hAAIIAAUJuRaRBwBmAQAIAAUJuRaRBwBmAQAuAAQKfz0AAggACQmqHLwEANoCAAgACQmqHLwEANoCAAAA.Fresher:BAACLgAFFH8IAAIXAAIJGCPdqADLAAAXAAIJGCPdqADLAAAuAAQKfxUAAhcABQnLHDK1AA0BABcABQnLHDK1AA0BAAEuAAUUBAkMAA4AZBEA.Freyjen:BAAALgADCgkJGAABLgAECgcJCgACAAAAAA==.Froboz:BAAALgADCgYJCQAAAA==.Frogevil:BAAALgAECggJEgAAAA==.Frogtoad:BAAALgAECgYJBgAAAA==.Frogtree:BAAALgADCgUJBQAAAA==.Frostmoth:BAAALgAECgYJBgABLgAECggJGgAXAGYVAA==.Frumentarii:BAAALgAECgQJBAAAAA==.',
Fu='Funeral:BAACLgAFFH8/AAQfAAkJdx2zBABgAQAeAAcJ2heTDQDmAQAfAAUJ/R2zBABgAQAbAAMJOhqABgAYAQAuAAQKfzUABB8ACQnmIz4EAKECAB8ABwnSID4EAKECABsABwmUIrUEAE4CAB4ACAkxGetEAP0BAAAA.',
['Fà']='Fàstïk:BAAALgAECgEJAQAAAA==.',
Ga='Galladin:BAAALgAECgMJBQABLgAECgYJDQACAAAAAA==.Gallory:BAAALgAECgkJEQAAAA==.Gareeshala:BAAALgAECgIJAgAAAA==.',
Gd='Gdk:BAAALgAECgYJCAAAAA==.Gdkdemon:BAAALgAECgQJBAAAAA==.Gdkdrake:BAAALgAECgcJBwAAAA==.Gdkhunter:BAAALgAECgYJAwAAAA==.Gdkmage:BAAALgAECgkJEwAAAA==.Gdkman:BAAALgAECgcJAwAAAA==.Gdkmonk:BAAALgAECgEJAQAAAA==.Gdkpally:BAAALgAECgEJAQAAAA==.Gdkwar:BAAALgAECgUJBAAAAA==.',
Ge='Geomancer:BAAALgADCgQJBAAAAA==.',
Gh='Ghadius:BAAALgAECgcJDAAAAA==.',
Gi='Gimmedatmouf:BAACLgAFFH8FAAITAAMJjxORLADZAAATAAMJjxORLADZAAAuAAQKfxcABBEACAmjIeMIAAEDABEACAmjIeMIAAEDACMAAwmmHowuAKoAABMABAl7FlNhAJQAAAEuAAUUBAkMAA4AZBEA.Gimmedatneck:BAACLgAFFH8MAAIOAAQJZBGDJAAAAQAOAAQJZBGDJAAAAQAuAAQKfxcAAw4ACAlVI2EYAEQCAA4ACAlVI2EYAEQCACQAAQk2EuAcAEMAAAAA.Ginga:BAAALgAECgIJAgAAAA==.Gingy:BAAALgAECgUJBwAAAA==.',
Gl='Glead:BAABLgAECn8aAAIQAAkJ6ReNLQD9AQAQAAkJ6ReNLQD9AQAAAA==.Glizzymguire:BAAALgAECggJCAABLgAFFAMJDAAeACQGAA==.',
Gn='Gneeduh:BAAALgAECgIJAwAAAA==.Gnort:BAAALgAECgEJAgAAAA==.',
Go='Gobknight:BAAALgADCggJCAAAAA==.Goldina:BAAALgAECgEJAQAAAA==.Gooklover:BAAALgAECgQJCQAAAA==.Gosupal:BAAALgADCgYJBgAAAA==.',
Gr='Gracious:BAAALgAECgEJAQAAAA==.Graegor:BAAALgADCgYJBwAAAA==.Grastim:BAAALgAECgUJCgAAAA==.Graylight:BAAALgADCgUJBQAAAA==.Greenfanta:BAAALgADCgYJEAAAAA==.Grill:BAAALgADCgEJAQAAAA==.Grinkle:BAACLgAFFH8GAAIEAAMJFAYyYACKAAAEAAMJFAYyYACKAAAuAAQKfysAAgQACQkjEcs8ALsBAAQACQkjEcs8ALsBAAAA.Gripopotamus:BAAALgAECgIJAgAAAA==.Gristle:BAAALgADCgkJJwAAAA==.Gross:BAAALgAECgUJBQAAAA==.',
Gu='Guldangg:BAAALgAECgcJEAAAAA==.Gunner:BAACLgAFFH8SAAIHAAUJxhuJLQBWAQAHAAUJxhuJLQBWAQAuAAQKfx4AAwcACQnuItwGACgDAAcACQm5ItwGACgDABYAAwnWIeoHALsAAAAA.',
Ha='Hahararandir:BAAALgAECgEJAQAAAA==.Hakaishaz:BAAALgADCgUJBgAAAA==.Halfwatt:BAAALgAECgYJDQAAAA==.Hamaddor:BAAALgAECgYJBgAAAA==.Hamberger:BAAALgADCgEJAQAAAA==.Hammaridge:BAAALgAECgcJCgAAAA==.Hammerfire:BAAALgADCgMJAwAAAA==.Haraldsson:BAABLgAECn8gAAINAAgJkRaMUQDUAQANAAgJkRaMUQDUAQAAAA==.Hargrumn:BAAALgAECgEJAQAAAA==.Harmony:BAAALgADCgcJCgAAAA==.Harrin:BAAALgADCgYJDAAAAA==.Harrydabs:BAABLgAECn8dAAMiAAkJRCNNAACDAwAiAAkJRCNNAACDAwASAAQJJRB3PwD+AAABLgAFFAEJAQACAAAAAA==.Haru:BAABLgAECn8nAAIWAAkJTBh4GADdAQAWAAkJTBh4GADdAQAAAA==.Harvaal:BAAALgAECgUJBQAAAA==.Hasaro:BAACLgAFFH8SAAIPAAQJdxTlDwCnAAAPAAQJdxTlDwCnAAAuAAQKfysAAg8ACQmNG7QHAHkCAA8ACQmNG7QHAHkCAAAA.Hashimi:BAAALgAECgcJBwAAAA==.Hashiramaa:BAAALgAECgcJDwAAAA==.Hatcho:BAAALgAECgMJAwAAAA==.Havokvacano:BAABLgAECn8gAAINAAkJjxPsSADrAQANAAkJjxPsSADrAQAAAA==.',
He='Healmachine:BAABLgAECn8UAAIlAAgJHAlBOwAJAQAlAAgJHAlBOwAJAQAAAA==.Hellbrringer:BAACLgAFFH8GAAIBAAQJYwSbjADAAAABAAQJYwSbjADAAAAuAAQKfxcAAgEABglFDGbUAOsAAAEABglFDGbUAOsAAAAA.Helzer:BAAALgAECgQJBgABLgAFFAMJBQAXAG0PAA==.Helzerx:BAABLgAECn8yAAIOAAkJjR4ACACnAgAOAAkJjR4ACACnAgABLgAFFAMJBQAXAG0PAA==.Herpstrike:BAAALgAECgIJAwAAAA==.',
Hi='Hierophant:BAAALgAECgYJBgABLgAFFAUJIQAIALkWAA==.',
Ho='Hoely:BAAALgAECgEJAQAAAA==.Hogmanjr:BAAALgADCgQJBgAAAA==.Holycrappala:BAAALgADCgEJAQAAAA==.Hotsordots:BAAALgAECggJCwAAAA==.Hounskul:BAABLgAECn8gAAIeAAkJogfAfQA9AQAeAAkJogfAfQA9AQAAAA==.How:BAAALgADCgYJBgABLgAFFAUJEgAHAMYbAA==.',
Hu='Hugealien:BAAALgADCgIJAgAAAA==.Hulksmash:BAAALgAECgEJAQAAAA==.Hungchungus:BAAALgAECgEJAgAAAA==.Hungwaylo:BAAALgADCgIJAgAAAA==.Hunterkiller:BAAALgAECgUJBQAAAA==.',
Hw='Hwere:BAAALgAECgUJBgAAAA==.',
Hx='Hx:BAAALgAECgYJCQAAAA==.',
Hy='Hypnoticpal:BAAALgAECgkJBwAAAA==.Hystëria:BAACLgAFFH8dAAMYAAUJLCJIBQBvAQAYAAUJLCJIBQBvAQAXAAUJUBgbrQDGAAAuAAQKf14AAxgACQmsJHwBACIDABgACQlPJHwBACIDABcACAkJIV0oAGACAAEuAAUUBgkGABkAZhYA.Hyunlix:BAAALgADCgUJBQAAAA==.',
['Hõ']='Hõnor:BAAALgAECgYJBgABLgAFFAYJBgAZAGYWAA==.',
Ia='Iammoo:BAABLgAECn8UAAINAAcJKhxCaACeAQANAAcJKhxCaACeAQAAAA==.',
Ic='Ichorus:BAAALgADCgEJAQAAAA==.',
Id='Idasie:BAAALgADCgcJDQAAAA==.',
Ig='Igotkappa:BAAALgADCgMJAwAAAA==.Igotyourback:BAAALgAECggJCAAAAA==.Igriss:BAAALgAECgYJBgAAAA==.',
Il='Illuminaughd:BAAALgAECgQJAQAAAA==.Ilydris:BAAALgADCgQJBAAAAA==.',
Im='Imadruid:BAAALgADCgQJBAAAAA==.',
In='Infinitepain:BAAALgAECgcJDgABLgAFFAYJJAATAHUUAA==.',
Io='Iolyte:BAABLgAECn8XAAIBAAYJUQ0jLACaAAABAAYJUQ0jLACaAAAAAA==.',
Ir='Iridellis:BAACLgAFFH8YAAIFAAUJ7wqVIwAxAQAFAAUJ7wqVIwAxAQAuAAQKfyIAAgUACQn3Eo8XABkCAAUACQn3Eo8XABkCAAAA.',
Is='Ispankutank:BAAALgAFFAMJAwAAAA==.',
It='Itssofluffy:BAABLgAECn8vAAQjAAkJlBiLCABDAgAjAAkJDRiLCABDAgAPAAUJBhfbEwAyAQATAAIJUgnYlQAqAAAAAA==.Itwon:BAAALgAECgUJEgAAAA==.',
Iz='Izzelda:BAAALgAECgEJAgAAAA==.',
Ja='Jacus:BAAALgAECgQJCQAAAA==.Jadaruk:BAAALgAFFAEJAQAAAA==.Jahumc:BAAALgAECgEJAQAAAA==.Janeoftrades:BAAALgAECgYJDAAAAA==.Jaycers:BAABLgAECn8iAAQUAAkJ9SAZBQCiAgAUAAkJ8B8ZBQCiAgANAAUJERzKmgBAAQAVAAEJ2AIAnwAqAAAAAA==.Jayclark:BAAALgADCgcJCgAAAA==.',
Je='Jessiriusrex:BAAALgADCgEJAQAAAA==.',
Jo='Joemomma:BAACLgAFFH8FAAIBAAQJ6gP5PgDKAAABAAQJ6gP5PgDKAAAuAAQKfxkAAgEABwk/EFYnALIAAAEABwk/EFYnALIAAAAA.Johndom:BAAALgAECgYJBgAAAA==.Jokestarfist:BAABLgAECn8ZAAINAAQJgRjSvAANAQANAAQJgRjSvAANAQAAAA==.',
Jr='Jr:BAAALgAECgcJCQAAAA==.',
Jt='Jtheshadow:BAAALgAECgEJAQAAAA==.',
Ju='Juicebox:BAAALgADCgEJAQAAAA==.Jumpercables:BAAALgAECggJCQAAAA==.Junachan:BAAALgAECgMJBQAAAA==.Junior:BAAALgAECgEJAQAAAA==.Jurichan:BAAALgAECgMJCQAAAA==.',
['Jä']='Jägernaut:BAAALgADCgEJAQAAAA==.',
Ka='Kaitokit:BAACLgAFFH8FAAMcAAMJ+wiTNQBgAAAXAAIJOAVidABsAAAcAAIJoQmTNQBgAAAuAAQKfxkAAhwACQkSHowBAJECABwACQkSHowBAJECAAAA.Kajamando:BAABLgAECn8eAAISAAgJ7wcXLwANAQASAAgJ7wcXLwANAQAAAA==.Kalia:BAAALgAECgQJBAAAAA==.Kalith:BAABLgAECn8YAAIWAAkJCgObMAAmAQAWAAkJCgObMAAmAQAAAA==.Kallydots:BAAALgADCgcJDQABLgAECgkJBwACAAAAAA==.Karmacide:BAAALgAECgQJBAAAAA==.Kawfee:BAAALgAECgEJAQAAAA==.Kayllina:BAABLgAECn8tAAIXAAgJ3AcbHADMAAAXAAgJ3AcbHADMAAAAAA==.Kayotic:BAABLgAECn8nAAISAAkJlgfQLQAUAQASAAkJlgfQLQAUAQAAAA==.Kayww:BAAALgAECgQJBwAAAA==.',
Ke='Keinarra:BAAALgADCgMJBgAAAA==.Kell:BAAALgADCgcJCAAAAA==.Kelmorphic:BAABLgAECn8tAAMiAAkJMyEAAgDyAgAiAAkJMyEAAgDyAgASAAEJ7QoPcgAsAAAAAA==.Keropikapika:BAAALgADCgUJBQAAAA==.Keynerashz:BAAALgADCgIJAgAAAA==.',
Kh='Khaali:BAAALgAECgEJBAAAAA==.Khristina:BAAALgAECgMJBAAAAA==.',
Ki='Kikiana:BAAALgAECgcJDgABLgAECggJMAAlAKQhAA==.Kikstyx:BAAALgADCgYJCAAAAA==.Killcommand:BAABLgAFFH8FAAQHAAQJEg7NSwCJAAAHAAIJ7gzNSwCJAAAWAAEJcBl4FwBOAAAMAAEJ+QTqIAA3AAABLgAFFAgJFwAZAO0aAA==.Killerxd:BAABLgAECn8WAAINAAgJJRhFagCaAQANAAgJJRhFagCaAQAAAA==.Killesea:BAAALgADCgcJDAAAAA==.Kittfisto:BAABLgAECn8iAAQiAAkJmhVYFQACAQAGAAkJiBStXgCFAQAiAAQJ4BRYFQACAQASAAYJmAweNwDeAAAAAA==.',
Kn='Knitemare:BAAALgAECgEJAQAAAA==.',
Ko='Korivos:BAAALgADCgMJAwAAAA==.Kosmas:BAABLgAECn8lAAMKAAkJJSLjAgB/AQAQAAkJbh/XEwBTAgAKAAgJrR7jAgB/AQAAAA==.',
Kr='Kromwarr:BAAALgAECgcJBwAAAA==.Krushgar:BAABLgAECn8UAAMXAAcJsRcIXQDbAQAXAAcJsRcIXQDbAQAYAAEJsxCDPQArAAAAAA==.',
Ku='Kuchikopii:BAAALgADCgYJBgAAAA==.Kungfuelf:BAAALgADCgEJAQAAAA==.Kungpowchikn:BAAALgAECgIJAgAAAA==.Kurookami:BAAALgAECgUJDAAAAA==.Kuukwa:BAAALgADCgQJBgAAAA==.',
Ky='Kyana:BAAALgADCgEJAQAAAA==.Kylina:BAAALgAECgQJBgAAAA==.',
['Kí']='Kíller:BAAALgAECgEJAQAAAA==.',
La='Lackluster:BAACLgAFFH8IAAIBAAMJYwHAmgCVAAABAAMJYwHAmgCVAAAuAAQKfykAAgEACQmuCeCnAC4BAAEACQmuCeCnAC4BAAAA.Lagg:BAAALgAECgIJAwABLgAECgUJEQACAAAAAA==.Lamatrick:BAAALgAECgUJBwAAAA==.Lanadelslayy:BAAALgAECgYJDwAAAA==.Laosman:BAAALgAECgEJAQAAAA==.Lasenza:BAAALgADCgQJBAAAAA==.Lavacoomer:BAAALgADCgYJBQAAAA==.',
Ld='Ldg:BAAALgAFFAIJAgAAAA==.',
Le='Leafdaddy:BAABLgAFFH8LAAIPAAMJlxA5DwCtAAAPAAMJlxA5DwCtAAAAAA==.Ledana:BAAALgAECggJCAAAAA==.Leenale:BAAALgAECgEJAQAAAA==.Lejosh:BAAALgAECgIJAgAAAA==.Lennon:BAAALgAECgkJBgAAAA==.Leona:BAAALgAECgYJCgAAAA==.Leonesk:BAAALgADCgQJAwAAAA==.Lethee:BAAALgAECgEJAgAAAA==.Lexazshara:BAAALgAECgEJAwAAAA==.',
Li='Lightingbolt:BAAALgAECgUJDAAAAA==.Lightlybaked:BAAALgAFFAEJAQAAAA==.Lights:BAAALgAECgMJAwAAAA==.Lilithamy:BAAALgADCgYJBgAAAA==.Lilthin:BAABLgAECn8cAAIBAAkJHgfWiABlAQABAAkJHgfWiABlAQAAAA==.Lindvianne:BAAALgADCgcJBwAAAA==.Liore:BAAALgAECgQJBgAAAA==.Lisathe:BAAALgAECgYJEgAAAA==.Lithdrae:BAAALgADCgYJBgAAAA==.Littleddk:BAABLgAECn8UAAIXAAcJYRqCTgDXAQAXAAcJYRqCTgDXAQAAAA==.Littledude:BAAALgADCgQJBQAAAA==.Littlemorsel:BAABLgAECn8eAAIHAAkJNxPoNgACAgAHAAkJNxPoNgACAgAAAA==.Livelaughlov:BAAALgAECgEJAQAAAA==.',
Lo='Lockenload:BAAALgAECgEJAQAAAA==.Lockme:BAAALgADCggJCAAAAA==.Lombardio:BAAALgAECgEJAwAAAA==.Louthar:BAAALgADCgcJAQAAAA==.',
Ls='Lselec:BAAALgAECgUJEwAAAA==.',
Lt='Ltdapperdan:BAAALgAECgEJAQAAAA==.',
Lu='Lucens:BAACLgAFFH8HAAIVAAIJRA/KGwBwAAAVAAIJRA/KGwBwAAAuAAQKfzUAAhUACAnXGsYCAB4CABUACAnXGsYCAB4CAAAA.Lunagreed:BAAALgADCgUJBQAAAA==.Lurchdh:BAAALgAFFAMJAgABLgAFFAUJFwABAK8PAA==.Lurchdruid:BAAALgADCgEJAQAAAA==.Lurchn:BAACLgAFFH8XAAIBAAUJrw+iLAAaAQABAAUJrw+iLAAaAQAuAAQKf1oAAgEACQmpFRlcAMoBAAEACQmpFRlcAMoBAAAA.',
Ly='Lysariax:BAAALgAECgUJBQAAAA==.',
['Lï']='Lïght:BAACLgAFFH8HAAINAAQJWiB3KABpAQANAAQJWiB3KABpAQAuAAQKfxsAAg0ACAmDJQ0NAPwCAA0ACAmDJQ0NAPwCAAEuAAUUBgkGABkAZhYA.',
['Lú']='Lúná:BAAALgAECgYJBwAAAA==.',
Ma='Maccoroni:BAAALgAECgMJCAAAAA==.Maemae:BAAALgAECgcJDQAAAA==.Maggieaugers:BAACLgAFFH8HAAIJAAYJhQLcNgDoAAAJAAYJhQLcNgDoAAAuAAQKfykAAwkACAn3D8EwAHQBAAkACAn3D8EwAHQBAAgABAmPBbAvAG4AAAAA.Magicmech:BAAALgADCgcJDAAAAA==.Magivacano:BAAALgAECggJEgAAAA==.Mahnon:BAABLgAECn8aAAIHAAkJowjGdQBUAQAHAAkJowjGdQBUAQAAAA==.Mandril:BAAALgADCgEJAQAAAA==.Matas:BAABLgAECn8YAAIdAAkJ+gOWOQAWAQAdAAkJ+gOWOQAWAQAAAA==.Matias:BAAALgAECgEJAQAAAA==.Mazzikane:BAAALgAECgMJAwAAAA==.',
Mc='Mcdeath:BAAALgADCgIJAgAAAA==.',
Me='Mebo:BAAALgAECgEJAQAAAA==.Medzly:BAAALgADCgYJEAAAAA==.Metalhedface:BAABLgAECn8pAAMQAAkJLRm4AwDrAQAQAAcJ/Ry4AwDrAQAKAAgJnhNcGgCHAQAAAA==.',
Mi='Miixx:BAAALgAECgQJBQAAAA==.Mikecoxwall:BAACLgAFFH8HAAIBAAIJSgn3pwCDAAABAAIJSgn3pwCDAAAuAAQKfz4AAwEACQmTFVU8ACkCAAEACQmTFVU8ACkCACYABgnfCP0KACoBAAAA.Mikuru:BAAALgAECgEJAwAAAA==.Milena:BAAALgAECgEJAgAAAA==.Milkordeath:BAAALgADCgEJAQAAAA==.Milov:BAAALgADCgUJBQAAAA==.Minarva:BAAALgAECgcJCgAAAA==.Minbyungyu:BAAALgAECgEJAQAAAA==.Minichri:BAAALgAECgIJAgAAAA==.Mirazha:BAAALgADCgkJCQAAAA==.Misary:BAAALgAECgQJBwAAAA==.Mischeif:BAAALgAECgUJCwAAAA==.',
Mo='Mojomon:BAAALgADCgYJBgAAAA==.Moltalgol:BAABLgAECn8jAAIeAAYJkgR15gCRAAAeAAYJkgR15gCRAAAAAA==.Monkeli:BAABLgAECn8cAAIQAAcJFxEUPwBIAQAQAAcJFxEUPwBIAQAAAA==.Monkitard:BAAALgAECgMJAwABLgAECgUJCAACAAAAAA==.Monkryn:BAAALgAECgUJCAABLgAFFAgJHgAXAOcZAA==.Monkup:BAABLgAFFH8MAAIdAAQJtwVaMgDfAAAdAAQJtwVaMgDfAAAAAA==.Moocifer:BAAALgAECgEJAQAAAA==.Moocifermoo:BAAALgAECgEJAgAAAA==.Moogrim:BAAALgADCgkJDgAAAA==.Moonsiand:BAECLgAFFH8fAAMHAAgJjQ19EACiAQAHAAgJjQ19EACiAQAWAAQJHgPnHQDjAAAuAAQKfysABAcACQk3GqYoADwCAAcACQn+FqYoADwCABYACAleEysOAOYBAAwAAQmqAV+ZABwAAAAA.Moosafur:BAACLgAFFH8HAAIPAAMJwCQbCwBBAQAPAAMJwCQbCwBBAQAuAAQKf0IAAw8ACQkMJTcBAFADAA8ACQkMJTcBAFADACMACQlbGgQIAFICAAAA.Mooshoe:BAAALgAECgEJAQAAAA==.Mor:BAAALgAECgIJBQAAAA==.Mordoly:BAAALgAECgYJBgAAAA==.Moreldwiddle:BAAALgAECgEJBAAAAA==.Morphyr:BAAALgAECgYJCAAAAA==.Morrigån:BAAALgAECgIJAgAAAA==.Morvoult:BAAALgAECgEJAQAAAA==.Motgus:BAAALgAECgMJBQAAAA==.Mozzsticks:BAAALgAECgYJDwAAAA==.',
Ms='Mshottie:BAABLgAECn8fAAINAAkJVQgDGwD3AAANAAkJVQgDGwD3AAAAAA==.Msuysu:BAAALgAECgEJAQABLgAECgEJAwACAAAAAA==.',
Mt='Mtngrounds:BAAALgADCgIJAgAAAA==.',
Mu='Murdaa:BAAALgAECgMJBAAAAA==.Murkt:BAAALgAECgEJAQAAAA==.Mutuusami:BAAALgAECgEJAgAAAA==.',
Mx='Mx:BAAALgAECgcJDAAAAA==.',
My='Myraine:BAAALgAECgMJAwAAAA==.Mythdath:BAAALgADCgMJAwAAAA==.Mythlock:BAAALgAECgMJAwAAAA==.Myway:BAAALgADCggJCwAAAA==.',
Na='Naari:BAABLgAECn8aAAMQAAgJNxIvRQAxAQAQAAcJDREvRQAxAQAKAAEJLxl3bwBCAAAAAA==.Naniwa:BAAALgAECgEJAQABLgAFFAMJDQAEANgVAA==.Naoya:BAAALgADCgIJAgAAAA==.Narexia:BAABLgAECn9OAAIhAAkJSx83AwDXAgAhAAkJSx83AwDXAgAAAA==.Natureboyy:BAAALgAECgIJAwAAAA==.',
Ne='Nekuma:BAAALgAFFAIJAgABLgAFFAgJJwAYAEwcAA==.Nellaa:BAABLgAECn8ZAAMFAAcJ3RBZDAAHAQAFAAcJ3RBZDAAHAQAlAAIJ5gY5dABYAAAAAA==.Netalanot:BAAALgAECgYJCAAAAA==.Newdles:BAAALgAECgEJAQAAAA==.',
Ni='Nightfury:BAAALgAECgcJDQAAAA==.Nightrage:BAAALgADCgYJBgAAAA==.Niklous:BAAALgAECgEJAQABLgAECgQJBAACAAAAAA==.Niklus:BAAALgAECgEJAQAAAA==.Nissanaltima:BAAALgADCgYJCQAAAA==.Nithilis:BAABLgAECn8zAAILAAkJAR5cCgCpAgALAAkJAR5cCgCpAgAAAA==.',
No='Noee:BAAALgADCgUJBQAAAA==.Nokkiewae:BAAALgADCgcJEgAAAA==.Nool:BAAALgADCgYJBQAAAA==.Nople:BAABLgAECn8fAAIBAAgJGBZQewCBAQABAAgJGBZQewCBAQAAAA==.',
Nu='Nutellaa:BAABLgAFFH8FAAIXAAIJmBd/0ACQAAAXAAIJmBd/0ACQAAAAAA==.',
Ny='Nymueline:BAAALgADCgUJBQAAAA==.',
Ob='Obeastly:BAAALgAECgUJBgAAAA==.Obie:BAAALgAECgUJEQAAAA==.Oborax:BAECLgAFFH8QAAINAAUJuQwJUgALAQANAAUJuQwJUgALAQAuAAQKfygAAg0ABwmcFw1wAI4BAA0ABwmcFw1wAI4BAAEuAAUUCAkfAAcAjQ0A.',
Od='Od:BAAALgAECgYJCAAAAA==.',
Ok='Okidokidrood:BAAALgADCgcJBwABLgAFFAgJKgAEAPUjAA==.Okidokidude:BAAALgADCgkJDwABLgAFFAgJKgAEAPUjAA==.Okiro:BAAALgAECgMJAwAAAA==.Okoru:BAAALgADCgIJAgAAAA==.',
Ol='Oliviabenson:BAAALgAFFAEJAQAAAA==.Oluun:BAAALgADCgQJBAAAAA==.',
Or='Orkun:BAAALgAECgEJAQAAAA==.',
Ot='Otmetka:BAAALgADCgcJAQAAAA==.',
Ow='Owensbeast:BAAALgADCgUJBQAAAA==.',
Pa='Palapal:BAAALgAECgYJDgAAAA==.Palatard:BAAALgAECgEJAQABLgAECgUJCAACAAAAAA==.Paldi:BAABLgAECn8WAAINAAgJORnRKwB0AgANAAgJORnRKwB0AgABLgAFFAMJBAACAAAAAA==.Paliboos:BAABLgAECn8UAAINAAYJGQ8gHADuAAANAAYJGQ8gHADuAAAAAA==.Papaozz:BAABLgAECn8qAAIOAAcJ9Q01KABVAQAOAAcJ9Q01KABVAQAAAA==.Parapox:BAAALgAECgEJAgAAAA==.Pariss:BAAALgAECgkJBwAAAA==.Pawcalypse:BAAALgAECgMJAwAAAA==.Paws:BAABLgAECn8ZAAITAAkJwg57JgCaAQATAAkJwg57JgCaAQAAAA==.',
Pe='Peaky:BAAALgAECgcJEgAAAA==.Perelia:BAABLgAECn+FAAIFAAkJVxc4AgBvAgAFAAkJVxc4AgBvAgAAAA==.Pewpewqt:BAAALgAECgUJBwABLgAFFAEJAQACAAAAAA==.',
Pi='Piltraja:BAAALgAECgEJAgAAAA==.',
Pl='Plaguehammer:BAABLgAECn8eAAIXAAYJ6Av4wgD6AAAXAAYJ6Av4wgD6AAAAAA==.Playstationn:BAAALgADCgUJBQAAAA==.Pleiades:BAAALgAECgEJAQAAAA==.',
Po='Polarg:BAAALgAECgEJAgAAAA==.Polarity:BAAALgAECgMJAwAAAA==.Pomni:BAAALgAECgMJAwAAAA==.Popcola:BAAALgADCgEJAQABLgAECgUJCQACAAAAAA==.Popopopopopo:BAAALgAFFAQJBAAAAA==.Portholio:BAAALgAECgYJBgAAAA==.',
Pp='Ppc:BAAALgAFFAEJAgABLgAFFAgJFwAZAO0aAA==.',
Pr='Prophofdoom:BAAALgAECggJCAAAAA==.',
Pu='Pubbles:BAABLgAECn8XAAQhAAkJ4SB6BwBVAgAhAAgJrCB6BwBVAgAEAAEJ1Qk42AAxAAADAAEJhgx3swAnAAAAAA==.Punizher:BAAALgAECgQJBQAAAA==.Purerage:BAAALgAECgYJDQAAAA==.',
Pv='Pvc:BAAALgAECgYJCQABLgAFFAgJFwAZAO0aAA==.',
Py='Pyrella:BAAALgADCgEJAQABLgAECgcJGQAFAN0QAA==.Pyyrha:BAAALgAECgMJAwAAAA==.Pyyrhadrood:BAAALgAECgMJAwAAAA==.Pyyrhanice:BAAALgAECgUJDgAAAA==.Pyyrhaspice:BAAALgADCgUJCQAAAA==.',
Qu='Quetzlcoatl:BAAALgADCgcJBwABLgAECgkJEgACAAAAAA==.',
Ra='Radiantharm:BAABLgAECn8WAAMVAAcJyhInCAA2AQAVAAcJyhInCAA2AQAUAAEJlApvGgAfAAAAAA==.Raevalinaa:BAAALgAECgQJCwABLgAFFAIJDAABAEUOAA==.Raevelina:BAAALgAECgEJAQABLgAFFAIJDAABAEUOAA==.Raevelinaa:BAAALgAECgQJBwABLgAFFAIJDAABAEUOAA==.Rafeh:BAAALgAECgUJBwAAAA==.Rageaholic:BAAALgAECgMJBAAAAA==.Raisedead:BAAALgAECgQJBgAAAA==.Ralet:BAAALgAECgMJAwAAAA==.Ramian:BAAALgADCgkJCgAAAA==.Randzmannz:BAAALgAECgMJAwAAAA==.Raph:BAAALgAECgIJAgAAAA==.Rarelootboss:BAAALgADCgcJDAAAAA==.',
Re='Reason:BAABLgAECn8VAAMRAAgJQxacUgBcAQARAAcJzhacUgBcAQATAAEJewjAkwArAAAAAA==.Redbaer:BAAALgADCgUJBQAAAA==.Renair:BAAALgADCgMJAwAAAA==.Renoitukax:BAABLgAECn82AAMLAAkJwxt+DACKAgALAAkJwxt+DACKAgAFAAYJJhuXHADpAQAAAA==.Restorn:BAAALgADCgcJCgAAAA==.Retrobution:BAAALgAECgQJCAAAAA==.Retussy:BAAALgADCgEJAQAAAA==.Reynard:BAABLgAECn8WAAIGAAcJLxHYbQBHAQAGAAcJLxHYbQBHAQAAAA==.Rezz:BAACLgAFFH8TAAIBAAcJLg/tPAB5AQABAAcJLg/tPAB5AQAuAAQKfyAAAgEACQmQHIgpAM0CAAEACQmQHIgpAM0CAAAA.',
Rh='Rhode:BAAALgAECgQJCwAAAA==.Rhohir:BAAALgADCgIJAgAAAA==.',
Ri='Ridic:BAAALgADCgMJAwAAAA==.Rigour:BAAALgADCgMJAwAAAA==.Rishiun:BAAALgADCgEJAQAAAA==.Rivers:BAABLgAECn8UAAIKAAcJhQpgNQDwAAAKAAcJhQpgNQDwAAAAAA==.',
Ro='Rocketpop:BAAALgADCgIJAgAAAA==.Roopall:BAAALgAECgQJBQAAAA==.Rosiegirl:BAAALgAECgMJAwAAAA==.Roxas:BAAALgAECgcJDQAAAA==.',
Ry='Ryzen:BAAALgAECgYJDQAAAA==.',
Sa='Sabomnim:BAAALgAECgEJAQAAAA==.Saggi:BAAALgAECgYJCAAAAA==.Salaelana:BAAALgADCgcJCQAAAA==.Saltzpyre:BAAALgADCgYJBAAAAA==.Sanasrindis:BAABLgAECn8dAAMQAAgJWQoICwAQAQAQAAgJWQoICwAQAQAKAAEJnAY+HAAgAAAAAA==.Saninar:BAABLgAECn8bAAMUAAkJ1w+CAwCPAQAUAAkJ1w+CAwCPAQANAAEJ3wHLcwAQAAAAAA==.Sausagepizza:BAAALgADCgYJAwAAAA==.',
Sc='Scarletwidow:BAAALgADCgQJBAAAAA==.Schezmu:BAAALgAECgIJAgAAAA==.Scruffknight:BAAALgAECgcJDQAAAA==.Scrufies:BAACLgAFFH8UAAIOAAQJkhTpGgBBAQAOAAQJkhTpGgBBAQAuAAQKfx4AAg4ACQmyFuETAAQCAA4ACQmyFuETAAQCAAAA.',
Se='Seisappho:BAAALgADCgMJAwAAAA==.Senorfiesta:BAAALgAECgQJBAAAAA==.Sephiroth:BAAALgADCgEJAQAAAA==.Serenade:BAABLgAECn8WAAMGAAcJAw97eAAwAQAGAAcJAw97eAAwAQAiAAEJwgZJPQAaAAAAAA==.Serenityboop:BAAALgADCgYJCQAAAA==.Sergnocchi:BAAALgAECgcJEAAAAA==.Serys:BAABLgAECn8gAAIfAAkJKQ4BAwBjAQAfAAkJKQ4BAwBjAQAAAA==.Sethour:BAAALgADCgQJBAAAAA==.',
Sh='Shaboing:BAAALgADCgYJBgAAAA==.Shadowfangs:BAAALgAECgMJAwAAAA==.Shaee:BAAALgADCgkJDwAAAA==.Shalthender:BAAALgADCgUJBQAAAA==.Shamans:BAABLgAECn8fAAIDAAgJ1hukHAD8AQADAAgJ1hukHAD8AQAAAA==.Shamncheese:BAABLgAECn8WAAIEAAgJ6QxXYgA1AQAEAAgJ6QxXYgA1AQABLgAECgUJEQACAAAAAA==.Shamorcc:BAAALgADCgQJBAAAAA==.Shasta:BAACLgAFFH8rAAIPAAgJCCPDAQBBAgAPAAgJCCPDAQBBAgAuAAQKfygAAg8ACAlZJW8BAEEDAA8ACAlZJW8BAEEDAAAA.Shaulthariel:BAAALgAECgEJAQAAAA==.Shioz:BAAALgADCgQJBgAAAA==.Shisuiuchiha:BAABLgAECn8oAAIBAAgJrQm0JAC+AAABAAgJrQm0JAC+AAAAAA==.Shoccymilk:BAAALgAECgEJAgAAAA==.Shoiz:BAAALgAECgQJBQAAAA==.Shon:BAAALgAECgEJAQAAAA==.Shootumup:BAAALgAECgkJEgAAAA==.Shootybithc:BAAALgADCgEJAQAAAA==.Shuhari:BAAALgAECgkJEwAAAQ==.Shyx:BAABLgAECn81AAIFAAkJ4B01AQD4AgAFAAkJ4B01AQD4AgAAAA==.',
Si='Siilas:BAACLgAFFH8aAAQeAAQJNgkbZgD6AAAeAAQJnQcbZgD6AAAbAAEJhw9oKQBEAAAfAAIJ7QC3LAAyAAAuAAQKfyoAAx4ACQljF7YqAC8CAB4ACQljF7YqAC8CAB8ABAlQBwFBALEAAAAA.Simplèjack:BAAALgAECgMJAwABLgAFFAMJBgAEABQGAA==.Sinamon:BAABLgAECn8xAAINAAgJGSGyJAByAgANAAgJGSGyJAByAgAAAA==.Sinani:BAABLgAECn83AAIBAAkJFAcgiABnAQABAAkJFAcgiABnAQAAAA==.Sinista:BAAALgAECgUJBQAAAA==.Sinnamon:BAAALgAECgYJEgABLgAECggJMQANABkhAA==.Sipnspin:BAAALgAECgEJAgAAAA==.',
Sj='Sjdh:BAACLgAFFH8HAAIGAAMJ/wx1MwCnAAAGAAMJ/wx1MwCnAAAuAAQKfx4AAgYACAkrHJADABwCAAYACAkrHJADABwCAAAA.Sjrogue:BAABLgAECn8xAAIOAAkJMBRhEwAJAgAOAAkJMBRhEwAJAgABLgAFFAMJBwAGAP8MAA==.',
Sk='Skjolvarn:BAEALgAECgMJBwAAAA==.Skram:BAAALgAECgMJBAAAAA==.',
Sl='Slammydooker:BAABLgAECn8fAAMOAAkJ0hV2EwAIAgAOAAkJ0hV2EwAIAgAkAAEJ1QcMIQAtAAAAAA==.Slammyhole:BAAALgAECgEJAQAAAA==.Sleeptoken:BAAALgAECgMJCAAAAA==.Slyphz:BAAALgAECgYJBgAAAA==.',
Sm='Smallkat:BAAALgAECgEJAQAAAA==.Smightymouse:BAAALgAECgEJAQAAAA==.',
Sn='Snoipuh:BAAALgAECgUJBwAAAA==.',
So='Solas:BAAALgAECgQJBwAAAA==.Soletaken:BAAALgADCggJDwAAAA==.Solio:BAAALgADCgYJFQAAAA==.Solisha:BAAALgAECgQJBAAAAA==.Sololeveling:BAAALgAECgQJCgAAAA==.Somberdh:BAAALgADCgcJBwAAAA==.Sonofsand:BAAALgAECgIJAgAAAA==.Sorni:BAAALgAECgYJDAAAAA==.Soulja:BAAALgADCgEJAgAAAA==.Soulmoethus:BAAALgADCgYJCQAAAA==.',
Sp='Spitondagrav:BAAALgAECgEJAQAAAA==.Sprayandpray:BAABLgAECn8aAAIBAAUJqh3GjgBaAQABAAUJqh3GjgBaAQAAAA==.Sprinklely:BAAALgADCgcJCgAAAA==.',
Sq='Squidnips:BAAALgAECgEJAgAAAA==.Squirtney:BAAALgADCgMJAwAAAA==.',
Ss='Ss:BAACLgAFFH8PAAIfAAMJjQGaFQCPAAAfAAMJjQGaFQCPAAAuAAQKfxUAAh8ABwlxDOEWAO0AAB8ABwlxDOEWAO0AAAAA.Ssl:BAAALgADCgQJBAAAAA==.',
St='Starrwood:BAABLgAECn8pAAIHAAkJhQx7HwDbAAAHAAkJhQx7HwDbAAAAAA==.Statik:BAAALgAECgIJAwAAAA==.Statík:BAAALgAECgEJAQABLgAECgIJAwACAAAAAA==.Stepmonk:BAAALgAECgEJAQAAAA==.Stevesharts:BAAALgADCgYJCwAAAA==.Stonedlock:BAAALgADCgcJCAAAAA==.Stonetusk:BAAALgAECgUJCQAAAA==.Stormkeg:BAAALgAECgQJCQAAAA==.Stroya:BAAALgAECgUJBgAAAA==.',
Su='Sumnèr:BAAALgAECgcJBwAAAA==.Sunastiri:BAAALgADCgkJDQAAAA==.Sunpali:BAAALgAECgcJCwAAAA==.',
Sw='Swank:BAAALgADCgEJAQAAAA==.',
Sx='Sx:BAAALgADCgIJAgAAAA==.',
Sy='Syaa:BAAALgAECgYJBQAAAA==.Syberis:BAAALgADCgcJDgAAAA==.Sylauda:BAAALgAECgYJEAAAAA==.',
Ta='Tacholy:BAABLgAECn8VAAINAAkJzBdQaACeAQANAAkJzBdQaACeAQABLgAECgkJLwAKAJQcAA==.Tacodaboss:BAABLgAECn8XAAISAAYJLw+bMwDzAAASAAYJLw+bMwDzAAAAAA==.Talelarissia:BAAALgADCgQJBAAAAA==.Talonflame:BAABLgAECn8fAAIWAAkJBBy6BwB4AgAWAAkJBBy6BwB4AgAAAA==.Tansu:BAAALgAECgYJEwAAAA==.Tapered:BAAALgAECgUJCQAAAA==.Taupo:BAACLgAFFH8gAAIZAAYJPx2cEgBaAQAZAAYJPx2cEgBaAQAuAAQKfycAAhkACQlyH6kNAHoCABkACQlyH6kNAHoCAAAA.',
Tb='Tbanger:BAAALgAECgYJDwAAAA==.Tbh:BAAALgAFFAEJAgABLgAFFAgJFwAZAO0aAA==.',
Te='Techevo:BAAALgAECgQJBQAAAA==.Techfire:BAABLgAECn8pAAInAAkJ9hpAAgBFAgAnAAkJ9hpAAgBFAgAAAA==.Techsmexx:BAAALgAECgMJBQAAAA==.Tempina:BAAALgADCgkJCwAAAA==.Tenebron:BAABLgAECn80AAIoAAYJ/RISJwD6AAAoAAYJ/RISJwD6AAAAAA==.Tenlucis:BAAALgAECggJDAAAAA==.',
Th='Thaelyssa:BAAALgAECgEJAQAAAA==.Tharria:BAAALgADCgcJBwAAAA==.Thearia:BAABLgAECn8bAAMRAAgJrRWBUgBcAQARAAgJrRWBUgBcAQATAAUJmg5nVgC3AAAAAA==.Thecanmurk:BAAALgADCgkJEgAAAA==.Thedilf:BAAALgADCgEJAQAAAA==.Thicktotem:BAAALgAECgIJAgAAAA==.Thickumz:BAAALgAECgMJCgAAAA==.Thisismeta:BAAALgAECgcJDgAAAA==.Thoht:BAAALgADCgYJBwAAAA==.Thorenis:BAAALgADCgEJAQAAAA==.Thoryndruid:BAACLgAFFH8TAAIjAAYJBB3GAgCoAQAjAAYJBB3GAgCoAQAuAAQKfzIAAyMACQkWIxEDAA4DACMACQnmIhEDAA4DAA8ABwm8HlYNAAwCAAEuAAUUCAkeABcA5xkA.Thorïn:BAAALgADCgMJAwAAAA==.Thorýn:BAACLgAFFH8eAAIXAAgJ5xnKFwAhAgAXAAgJ5xnKFwAhAgAuAAQKfxoAAhcACAl8HuMqAFUCABcACAl8HuMqAFUCAAAA.Thórin:BAABLgAECn8tAAIUAAgJ4xciDwDRAQAUAAgJ4xciDwDRAQAAAA==.',
Ti='Timakk:BAAALgADCgEJAQAAAA==.Tipsy:BAABLgAECn8uAAMEAAkJWg/0OADMAQAEAAkJWg/0OADMAQADAAMJpA3ddwCGAAAAAA==.',
To='Tombraider:BAAALgAECgUJCAAAAA==.Tomfoolary:BAAALgAECgEJAwAAAA==.Toofy:BAAALgAECgEJAQAAAA==.Tot:BAAALgAECgkJDQAAAA==.Total:BAAALgADCgkJDAAAAA==.Totembear:BAAALgAECgYJEAABLgAFFAIJBwATABUFAA==.',
Tr='Trallanir:BAAALgAECgQJBAAAAA==.Tralleth:BAABLgAECn8nAAMJAAkJIRV9BQA9AQAJAAgJCRR9BQA9AQAIAAIJvQ3mMABmAAAAAA==.Traumatized:BAAALgADCgEJAQAAAA==.Trenazath:BAAALgAECgYJBwAAAA==.Trid:BAAALgAECgQJBgAAAA==.Trillbilly:BAAALgAECgEJAQAAAA==.Trinora:BAAALgADCgkJDgAAAA==.Troginator:BAAALgAECgEJAQAAAA==.Trolltard:BAAALgAECgIJAgABLgAECgUJCAACAAAAAA==.Troxa:BAAALgAECgUJCgAAAA==.',
Tu='Tuckard:BAAALgADCgEJAQAAAA==.Turock:BAAALgADCgIJAgAAAA==.Tuskor:BAAALgAFFAIJAgAAAA==.Tuskyrex:BAAALgADCgYJBgAAAA==.',
Tw='Twinklord:BAAALgAECgkJDwAAAA==.',
Ty='Tylanar:BAAALgAECgYJBgAAAA==.Tylolight:BAAALgADCgMJAwAAAA==.Tylomist:BAAALgAECgUJBQAAAA==.Tylototem:BAAALgAFFAEJAgAAAA==.',
['Tö']='Tötem:BAAALgAFFAEJAQABLgAFFAYJBgAZAGYWAA==.',
Ug='Uglyboi:BAAALgAECggJDwAAAA==.',
Uj='Ujcmonk:BAAALgAECgQJBAAAAA==.',
Ul='Ullbian:BAAALgADCgMJAwAAAA==.Ultramar:BAAALgADCgEJAQAAAA==.',
Un='Uncookedham:BAAALgAECgQJCwAAAA==.Unholyghost:BAAALgAECgQJBwAAAA==.',
Ur='Urgh:BAABLgAECn8fAAILAAkJ9RHLIwCrAQALAAkJ9RHLIwCrAQAAAA==.Urk:BAAALgAECgYJBgAAAA==.Urzaa:BAAALgAECgEJAwABLgAECgMJBAACAAAAAA==.',
Ut='Uthur:BAAALgAECgMJAwAAAA==.',
Ux='Ux:BAAALgADCgUJBQAAAA==.',
Va='Vaeelrundor:BAABLgAECn8bAAIHAAcJowycFgAiAQAHAAcJowycFgAiAQAAAA==.Valethales:BAAALgADCgcJBwAAAA==.Valyr:BAAALgAECgEJAQAAAA==.Vanillaface:BAACLgAFFH8IAAINAAMJnxhDJQD1AAANAAMJnxhDJQD1AAAuAAQKfxkAAg0ACQnvHNYdAJMCAA0ACQnvHNYdAJMCAAAA.Vape:BAABLgAECn8XAAIeAAcJXA+0egBEAQAeAAcJXA+0egBEAQABLgAFFAUJEgAHAMYbAA==.',
Ve='Vedexd:BAAALgADCgQJBAAAAA==.Veinripp:BAAALgADCgUJBQABLgAECggJNAAGAO0QAA==.Velarael:BAABLgAECn8zAAIeAAgJQhAODAA0AQAeAAgJQhAODAA0AQAAAA==.Velaryn:BAAALgADCgIJAgAAAA==.Veldar:BAAALgADCgIJAgABLgAECgUJDAACAAAAAA==.Velekete:BAAALgADCgUJBQAAAA==.Velethei:BAABLgAECn8YAAIRAAYJlySkGQBrAgARAAYJlySkGQBrAgAAAA==.Velian:BAAALgADCgMJBAAAAA==.Velielyn:BAAALgADCgQJBAAAAA==.Vellareth:BAAALgAECgEJAQAAAA==.Vellarria:BAAALgADCgcJBwAAAA==.Verdesalsa:BAAALgAECgcJDQAAAA==.Verox:BAAALgADCgMJAwAAAA==.Verzak:BAAALgAECgUJBQAAAA==.Vexoris:BAAALgAECgIJAgAAAA==.',
Vh='Vheckxus:BAACLgAFFH8IAAIDAAMJwgyWIQCYAAADAAMJwgyWIQCYAAAuAAQKfxoAAgMABgloFAJAADQBAAMABgloFAJAADQBAAAA.',
Vi='Vicv:BAABLgAECn8TAAILAAkJXwwXNABIAQALAAkJXwwXNABIAQAAAA==.Vivy:BAAALgAECgcJBwAAAA==.',
Vo='Voidberg:BAABLgAECn8YAAIbAAkJAxpsBwD6AQAbAAkJAxpsBwD6AQAAAA==.',
['Vê']='Vêa:BAAALgADCgkJCQAAAA==.',
['Vø']='Vøidtacø:BAAALgAFFAIJAgAAAA==.',
Wa='Wachonaso:BAACLgAFFH8TAAIeAAcJagynNgBuAQAeAAcJagynNgBuAQAuAAQKfy0AAx4ABwlJH6M0ADkCAB4ABwkrH6M0ADkCAB8ABgl8HlgXAI8BAAAA.Wakefull:BAAALgAECgEJAQAAAA==.Wanbahl:BAAALgADCgMJAwAAAA==.',
We='Wegovy:BAAALgAECgQJBAAAAA==.Wellburt:BAAALgAECgEJAQAAAA==.',
Wh='Whatheheck:BAAALgAECgEJAQAAAA==.Whatuphuz:BAAALgADCgQJBQAAAA==.Wheresmyjaw:BAACLgAFFH8jAAQeAAYJMR4ZPgBVAQAeAAYJ9RwZPgBVAQAbAAEJWSPAFQBnAAAfAAEJOQLaLAAxAAAuAAQKfycABB4ACAnyIe0WAJoCAB4ACAnyIe0WAJoCAB8AAgm6DiRSAHcAABsAAQnAILYvAF8AAAAA.',
Wi='Wield:BAAALgAECgEJAQAAAA==.Wildstàr:BAAALgADCgMJAwAAAA==.Wildthree:BAABLgAECn8rAAMaAAkJwh0HCgCjAgAaAAkJwh0HCgCjAgAdAAMJ2RQvYgC5AAAAAA==.Willenda:BAAALgAECgEJAwAAAA==.Willowins:BAAALgAECgEJAQAAAA==.Winterstired:BAACLgAFFH8wAAIlAAYJ7iSBAwDUAQAlAAYJ7iSBAwDUAQAuAAQKf0IAAyUACQnuJIMCAHkDACUACQnuJIMCAHkDAAUAAQlKF1xyAEQAAAAA.Wintesbuffs:BAAALgAFFAEJAQABLgAFFAYJMAAlAO4kAA==.',
Wo='Woen:BAAALgADCggJCQAAAA==.Wolf:BAAALgAECgQJBwAAAA==.Wollffie:BAAALgAECgQJBAAAAA==.',
Wu='Wuinn:BAABLgAFFH8GAAIIAAUJmgg+CwDrAAAIAAUJmgg+CwDrAAABLgAFFAkJGgARAFkPAA==.Wut:BAAALgADCgcJBwAAAA==.',
Wy='Wynterswrath:BAAALgAECgcJDQAAAA==.',
['Wõ']='Wõnderful:BAACLgAFFH8IAAIRAAUJthKQEAAQAQARAAUJthKQEAAQAQAuAAQKfxoAAhEABwk+G9skACUCABEABwk+G9skACUCAAEuAAUUBgkGABkAZhYA.',
Xc='Xclobber:BAAALgADCgIJAgAAAA==.',
Xe='Xemnass:BAAALgAECgUJBwAAAA==.Xerexia:BAAALgAECgUJBQAAAA==.Xexus:BAAALgAECgEJAQAAAA==.',
Xi='Xillas:BAAALgADCgUJBQAAAA==.Xinadmh:BAAALgAECgMJAwAAAA==.',
Xo='Xoverkll:BAAALgAECgYJDAAAAA==.',
Xy='Xylina:BAAALgADCgEJAQAAAA==.Xyrii:BAAALgADCgEJAQAAAA==.',
Ya='Yadder:BAAALgAECgIJBAABLgAFFAQJDAAOAGQRAA==.Yahro:BAACLgAFFH8VAAINAAYJ2hMDHgAWAQANAAYJ2hMDHgAWAQAuAAQKfzMAAg0ACQkqIKoOAPACAA0ACQkqIKoOAPACAAAA.Yamelow:BAAALgAECgQJBwAAAA==.',
Ye='Yeahiknow:BAAALgADCgkJDgAAAA==.Yeling:BAAALgAECgIJAgAAAA==.Yep:BAAALgAECgcJBwAAAA==.',
Yi='Yiska:BAAALgADCgcJBwAAAA==.',
Yn='Ynaguinid:BAAALgADCgEJAQAAAA==.',
Yo='Yoriale:BAAALgAECgYJDgAAAA==.Yotoymuerto:BAAALgAECgQJBAAAAA==.',
['Yù']='Yùè:BAAALgADCgEJAQAAAA==.',
Za='Zafra:BAAALgADCgEJAQAAAA==.Zaimara:BAAALgAECgEJBgAAAA==.Zalind:BAABLgAECn8VAAIeAAkJCxJoZgCYAQAeAAkJCxJoZgCYAQAAAA==.Zalvianna:BAABLgAECn8jAAMBAAgJAQVRxAADAQABAAgJAQVRxAADAQAmAAEJXQHIIgAYAAAAAA==.Zarathoz:BAAALgAECgEJAgAAAA==.Zarindlina:BAAALgADCgUJBQAAAA==.Zarshx:BAAALgAECgYJCwABLgAFFAMJBAACAAAAAA==.',
Ze='Zemonk:BAAALgAECgYJBgAAAA==.',
Zi='Zilong:BAAALgAFFAEJAQABLgAFFAUJEAAGAAEaAA==.Zilongmage:BAAALgAFFAIJAwABLgAFFAUJEAAGAAEaAA==.Zilongwar:BAAALgAFFAMJAwABLgAFFAUJEAAGAAEaAA==.Zinnia:BAAALgADCgEJAgAAAA==.',
Zo='Zonecw:BAAALgAFFAIJAwABLgAFFAIJBwAiABsRAA==.Zonedk:BAABLgAECn8eAAQcAAkJnB14BQBUAQAcAAkJ8Rt4BQBUAQAYAAcJZhgWBgD3AAAXAAEJxBc3YgFBAAABLgAFFAIJBwAiABsRAA==.Zonerg:BAAALgADCgEJAgABLgAFFAIJBwAiABsRAA==.Zonevn:BAABLgAFFH8HAAIiAAIJGxGDBwB0AAAiAAIJGxGDBwB0AAAAAA==.Zordak:BAAALgADCgcJCAAAAA==.Zosin:BAAALgAECgIJAwAAAA==.',
Zu='Zugzugzapzap:BAAALgADCgEJAQAAAA==.',
Zx='Zx:BAAALgAECgUJBgAAAA==.',
Zy='Zylphanae:BAAALgAECgQJBAAAAA==.',
['Øl']='Ølaf:BAAALgAECgEJAQABLgAFFAYJIAAZAD8dAA==.',
['Ør']='Ørsted:BAAALgAECgEJAgABLgAFFAYJIAAZAD8dAA==.',
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
