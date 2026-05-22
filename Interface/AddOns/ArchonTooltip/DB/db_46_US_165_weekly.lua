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

local lookup = {'Mage-Frost','Unknown-Unknown','Shaman-Elemental','DemonHunter-Devourer','Evoker-Preservation','Evoker-Augmentation','Priest-Shadow','Paladin-Retribution','Hunter-Marksmanship','Druid-Guardian','Shaman-Restoration','Warrior-Arms','Warrior-Fury','DemonHunter-Vengeance','Druid-Restoration','DemonHunter-Havoc','Hunter-BeastMastery','Druid-Balance','Hunter-Survival','DeathKnight-Unholy','DeathKnight-Frost','Monk-Mistweaver','Monk-Windwalker','DeathKnight-Blood','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Evoker-Devastation','Druid-Feral','Rogue-Subtlety','Rogue-Assassination','Paladin-Protection','Paladin-Holy','Priest-Holy','Mage-Arcane','Shaman-Enhancement','Priest-Discipline','Mage-Fire','Warrior-Protection','Monk-Brewmaster',}
local provider = {region='US',realm='Nazjatar',name='US',type='weekly',zone=46,date='2026-05-16',data={Aa='Aaela:BAAALgADCgUJBQAAAA==.',
Ab='Abrasaxs:BAABLgAECn8qAAIBAAgJQhgNPwDfAQABAAgJQhgNPwDfAQAAAA==.Absylus:BAAALgAECgQJBAABLgAFFAMJBAACAAAAAA==.',
Ac='Ackerman:BAAALgAECgYJCgABLgAECggJEQACAAAAAA==.Acraea:BAAALgAECgEJAQAAAA==.Acslater:BAAALgAECgMJAwAAAA==.Actionman:BAAALgAECgkJBgAAAA==.',
Ag='Agoobagoo:BAACLgAFFH8QAAIDAAQJ3iDVCQB/AQADAAQJ3iDVCQB/AQAuAAQKfx4AAgMACQnSIpAEAFIDAAMACQnSIpAEAFIDAAAA.',
Ai='Aionn:BAAALgAECgMJAwAAAA==.Airrow:BAAALgAECggJEQAAAA==.Aissae:BAACLgAFFH8NAAIEAAQJ7hxsFwBzAQAEAAQJ7hxsFwBzAQAuAAQKfyYAAgQACAlAJHYLACYDAAQACAlAJHYLACYDAAAA.Aiyama:BAAALgADCgQJBAAAAA==.',
Ak='Akiio:BAAALgAECgMJAwAAAA==.Akumaxl:BAAALgAECgYJBwAAAA==.',
Al='Alexia:BAAALgAECgEJAQAAAA==.Alfrank:BAAALgAECgIJAwAAAA==.Aliasx:BAAALgAECgIJAgAAAA==.Alphrank:BAAALgAECgEJAgAAAA==.Alurie:BAAALgAECgUJBgAAAA==.',
Am='Ambros:BAAALgADCgYJBgAAAA==.Aminatou:BAAALgAECgYJBgAAAA==.',
An='Anheeboan:BAAALgAECgYJCwAAAA==.Anihilated:BAAALgADCgYJBwAAAA==.',
Ar='Aradiax:BAAALgADCgYJBgAAAA==.Arcadavia:BAAALgADCgMJAwAAAA==.Ariaprime:BAAALgADCgkJCQAAAA==.Arjentheilus:BAAALgAECgMJAwAAAA==.Arthasl:BAAALgADCgIJAgAAAA==.Arthur:BAAALgAECgQJCQAAAA==.',
As='Asasda:BAAALgADCgMJBAAAAA==.Ashaelra:BAAALgAECgYJCAAAAA==.Astravaritan:BAAALgADCgMJAwAAAA==.',
At='Atherya:BAAALgAECgYJCAAAAA==.Atomixblonde:BAAALgAECgEJAQAAAA==.',
Au='Augonly:BAACLgAFFH8YAAIFAAUJShd5CwB/AQAFAAUJShd5CwB/AQAuAAQKfyMAAgUACQnpIC4GAOECAAUACQnpIC4GAOECAAAA.Augy:BAABLgAFFH8FAAIGAAMJ7AZMLgDDAAAGAAMJ7AZMLgDDAAAAAA==.Autoshot:BAAALgAECgYJCAAAAA==.',
Av='Averisbelia:BAAALgADCgIJAgAAAA==.',
Ay='Ayowamsley:BAAALgADCgMJAwAAAA==.',
Az='Azalea:BAAALgAECggJEAAAAA==.',
Ba='Babycrock:BAAALgADCgYJBgAAAA==.Back:BAAALgADCgcJDAAAAA==.Bakihanma:BAAALgAECgQJBgAAAA==.Balash:BAAALgADCgUJBQAAAA==.Balerion:BAAALgADCgEJAQABLgADCgMJAwACAAAAAA==.Balthasar:BAABLgAECn8WAAIHAAgJGBJAHwB4AQAHAAgJGBJAHwB4AQAAAA==.Banjobits:BAAALgADCgIJAgAAAA==.Barhead:BAAALgAECgYJDAAAAA==.Barlow:BAAALgAECgQJBQAAAA==.Barqose:BAAALgADCgMJAwAAAA==.Barryberry:BAABLgAECn8fAAIIAAkJDRE/UgCKAQAIAAkJDRE/UgCKAQAAAA==.Barryx:BAAALgAECgIJAgAAAA==.',
Bb='Bbldrizzy:BAAALgAFFAMJBAAAAA==.',
Be='Beastlieduke:BAAALgADCgUJCQABLgAFFAQJDgAHAO8MAA==.Beastlièduke:BAACLgAFFH8OAAIHAAQJ7wyuEQAoAQAHAAQJ7wyuEQAoAQAuAAQKfy4AAgcACAnwHrQOACACAAcACAnwHrQOACACAAAA.Beauslay:BAAALgAECgEJAQAAAA==.Belephon:BAAALgAECgYJEAAAAA==.Bellaruhbz:BAABLgAECn8eAAIJAAkJjA9zEQDWAAAJAAkJjA9zEQDWAAAAAA==.Berenstain:BAABLgAECn8lAAIKAAkJsRHFEABtAQAKAAkJsRHFEABtAQAAAA==.Bergmire:BAAALgAECgMJBgAAAA==.Berple:BAAALgADCgUJBQABLgAFFAYJEwABADwhAA==.Bestoresto:BAABLgAECn8UAAILAAkJBAwrLgCkAQALAAkJBAwrLgCkAQAAAA==.',
Bh='Bhori:BAAALgAECgEJAgAAAA==.',
Bi='Bibahabibi:BAABLgAECn8YAAMMAAYJUhikIAD+AAAMAAYJUhikIAD+AAANAAMJzQiVhwChAAAAAA==.Bigpapax:BAAALgAECgEJAQAAAA==.Bigtac:BAABLgAECn8sAAMMAAgJyBwBCAAjAgAMAAgJyBwBCAAjAgANAAIJ3gc5mQBcAAAAAA==.Binggus:BAAALgAECgUJCgABLgAECgkJHQAOAEQjAA==.',
Bl='Blabbybootze:BAAALgADCgEJAQAAAA==.Bladelight:BAAALgAECgUJBgAAAA==.Blighte:BAAALgADCgQJBAABLgAECggJIQAPAIIkAA==.Blightfangs:BAABLgAECn8qAAIBAAgJUhVRQADbAQABAAgJUhVRQADbAQAAAA==.Blindnautdef:BAABLgAECn8vAAMEAAgJ6xDdTABSAQAEAAgJ6xDdTABSAQAQAAEJ9gP8UwAnAAAAAA==.Bloodluna:BAAALgADCgUJBQAAAA==.',
Bo='Bobman:BAAALgADCgEJAQAAAA==.Bodakye:BAABLgAECn8iAAMRAAgJ6BwgJAAEAgARAAgJ6BwgJAAEAgAJAAIJtAEQgQBDAAAAAA==.Bonkz:BAAALgAECgMJAwAAAA==.Boomtip:BAAALgADCgMJAwAAAA==.Boon:BAAALgADCgYJCQAAAA==.Bordolor:BAAALgADCgYJCQAAAA==.Bowsa:BAAALgAECgkJAQAAAA==.',
Br='Brethathes:BAAALgAECgkJEAAAAA==.Brudda:BAAALgADCgUJBQAAAA==.',
Bu='Bubblebun:BAAALgAECgMJBgAAAA==.Bungerhole:BAABLgAECn8VAAMPAAgJhRrRJADhAQAPAAgJhRrRJADhAQASAAEJEQmVcgAmAAAAAA==.Butane:BAAALgADCgIJAgAAAA==.Buzzbuzz:BAAALgAECgEJAQAAAA==.',
Ca='Cainn:BAAALgAECgYJBwAAAA==.Cap:BAAALgADCgEJAQAAAA==.Capriestsun:BAAALgAFFAIJAgAAAA==.Carridin:BAAALgADCgMJAwAAAA==.Cass:BAAALgAECgEJAQAAAA==.',
Ce='Cernunon:BAAALgADCgEJAQAAAA==.',
Ch='Chaosdemon:BAABLgAECn8oAAIEAAkJTw7WPwB+AQAEAAkJTw7WPwB+AQAAAA==.Chapelgnome:BAAALgAECgIJAgABLgAFFAUJBQAGANUCAA==.Charlottea:BAAALgAECgYJDQAAAA==.Chemdra:BAAALgAECgcJEwAAAA==.Chipmonkey:BAAALgADCgcJCAABLgAECggJJgAPAEgPAA==.Chiptime:BAABLgAECn8mAAIPAAgJSA+7NwByAQAPAAgJSA+7NwByAQABLgAECggJJgAPAEgPAA==.Chomby:BAAALgAECgQJAwAAAA==.Chriifrio:BAAALgADCgQJBAAAAA==.Chromosomes:BAAALgAECgQJBAAAAA==.Chud:BAAALgAECgQJBgAAAA==.Chudsworth:BAAALgADCgYJCQAAAA==.Chunguhlumpo:BAAALgAECgEJBAAAAA==.',
Ci='Cinnamóróll:BAABLgAECn8dAAITAAgJQgksHAByAQATAAgJQgksHAByAQAAAA==.',
Cl='Clairity:BAAALgAECgMJAwAAAA==.Cleru:BAABLgAECn8eAAMUAAgJlBIZXABsAQAUAAgJlBIZXABsAQAVAAEJpwMVGgAlAAAAAA==.Cletus:BAAALgADCgcJAgAAAA==.',
Co='Coa:BAAALgAECgkJDAAAAA==.Cocoon:BAABLgAFFH8JAAMWAAUJDxjPDACQAQAWAAUJDxjPDACQAQAXAAEJrA4iKABDAAAAAA==.Comanderkush:BAAALgADCgMJAwAAAA==.Corita:BAAALgAECgIJAgAAAA==.Cowboi:BAAALgADCgMJAwAAAA==.Cowhealer:BAABLgAECn8hAAMPAAgJgiRDBwALAwAPAAgJgiRDBwALAwASAAEJTwUTgQAvAAAAAA==.',
Cr='Creamypies:BAAALgAECgEJAQAAAA==.Criticaltwo:BAAALgADCgIJAgAAAA==.Crockknight:BAAALgADCgYJBgAAAA==.Crossways:BAAALgAECgYJCQAAAA==.Cræftig:BAAALgADCgIJAgAAAA==.',
Cu='Cursecthree:BAAALgADCgEJAQAAAA==.Cutestxx:BAAALgAECgkJCwAAAA==.',
Cy='Cyxo:BAAALgADCgEJAQABLgAECgEJAwACAAAAAA==.',
Da='Daftxshade:BAAALgAECgQJBAAAAA==.Dandandan:BAAALgADCgMJAwAAAA==.Dapan:BAAALgADCgcJDQAAAA==.Dariaa:BAAALgAECgQJDAAAAA==.Darkcrusader:BAAALgAECgcJDQAAAA==.Darkheal:BAAALgADCgUJBQAAAA==.Darkladie:BAAALgADCgEJAQAAAA==.Darkshadows:BAAALgADCgcJCgAAAA==.Darthsyde:BAAALgAECgYJCQAAAA==.Dasdk:BAABLgAFFH8GAAIUAAMJExZrZgCfAAAUAAMJExZrZgCfAAAAAA==.Daspriest:BAAALgADCgYJDQABLgAFFAMJBgAUABMWAA==.',
De='Deadergriff:BAAALgAECgYJCgAAAA==.Deadhippycb:BAAALgAECgQJBAAAAA==.Deadhippyxy:BAAALgAECgEJAQAAAA==.Deadicated:BAAALgAECgYJEgAAAA==.Deadsies:BAAALgADCgIJAgABLgAFFAEJAQACAAAAAA==.Delan:BAAALgAECgQJBQAAAA==.Delveknight:BAAALgADCgYJBgABLgAECgcJFwAUAHUdAA==.Demoncox:BAAALgADCgMJAgAAAA==.Demondoc:BAAALgAECgcJDwAAAA==.Desunaito:BAACLgAFFH8XAAMVAAUJTSE9AACGAQAVAAUJTSE9AACGAQAYAAEJAABUNwAAAAAuAAQKfykAAhUACQk2JcIAAB0DABUACQk2JcIAAB0DAAAA.Devious:BAAALgADCgEJAQAAAA==.',
Dh='Dhzilong:BAACLgAFFH8PAAIEAAUJARqSIgA/AQAEAAUJARqSIgA/AQAuAAQKfx0AAwQACAlHIU84ABQCAAQACAkzHk84ABQCABAABQmNJJEeAMoBAAAA.',
Di='Diddlefiddle:BAAALgAECgcJCwAAAA==.Dihcum:BAAALgAECgEJAQAAAA==.Dimonologist:BAAALgAECgEJAQAAAA==.Dinpala:BAAALgADCgUJBQAAAA==.Dirtycow:BAAALgAECgQJBAAAAA==.',
Dk='Dkzilong:BAAALgAFFAIJAwABLgAFFAUJDwAEAAEaAA==.',
Do='Docholy:BAAALgAECgUJBQAAAA==.Dockson:BAAALgAECgMJAwAAAA==.Docwyle:BAABLgAECn8XAAMZAAgJnxEpUwBlAQAZAAgJnxEpUwBlAQAaAAEJtgLUcgAzAAAAAA==.Doobyia:BAAALgADCgEJAQAAAA==.Dorki:BAAALgAECgEJAgAAAA==.Dorlanlemeth:BAAALgAECgYJCgAAAA==.Dormist:BAAALgADCgcJCgABLgAECgkJHgAbAM4YAA==.Dotti:BAAALgAFFAEJAQAAAA==.',
Dr='Dracnogard:BAAALgAECgYJCgAAAA==.Dracowulf:BAABLgAECn8WAAIRAAcJcRAsTABlAQARAAcJcRAsTABlAQAAAA==.Dragonx:BAABLgAECn8nAAIRAAgJ7Q7qQwCgAQARAAgJ7Q7qQwCgAQAAAA==.Drakos:BAAALgAECgEJAQAAAA==.Drakowolf:BAABLgAECn8nAAIcAAgJCQR5DQDxAAAcAAgJCQR5DQDxAAAAAA==.Drenz:BAAALgADCgEJAQAAAA==.Dreorge:BAABLgAFFH8GAAIGAAMJcxGcKADfAAAGAAMJcxGcKADfAAAAAA==.Dreuceratops:BAAALgAECgMJAwAAAA==.Drewceratops:BAABLgAECn8mAAIIAAkJlBO1LwD6AQAIAAkJlBO1LwD6AQAAAA==.Driis:BAAALgADCgcJBwAAAA==.Drimchi:BAAALgAFFAMJAwAAAA==.Drizro:BAAALgADCgIJAgAAAA==.Drk:BAAALgAECgEJAQAAAA==.Dromash:BAABLgAECn8eAAMbAAkJzhgXAgBkAgAbAAgJ5BcXAgBkAgAaAAgJLxMfCAB+AQAAAA==.Druidyhealz:BAAALgAECgMJAwABLgAECgcJDwACAAAAAA==.',
['Då']='Dårius:BAAALgAECgYJEQAAAA==.',
Ea='Eaterofpaint:BAAALgAECgYJDgAAAA==.',
Ef='Effloria:BAABLgAECn8cAAIPAAkJtRq3CwDHAgAPAAkJtRq3CwDHAgAAAA==.Efrideet:BAAALgADCgEJAQAAAA==.',
El='Elegia:BAACLgAFFH8OAAIZAAUJrw0HOgAaAQAZAAUJrw0HOgAaAQAuAAQKfysAAxkACQlJGyIZAL4CABkACQlJGyIZAL4CABoAAQkAAAdmAEMAAAAA.Elerianor:BAAALgAECgYJDwAAAA==.Ellektra:BAAALgADCgUJBQAAAA==.',
Em='Emadiropilo:BAAALgAECgEJAQAAAA==.Emakaa:BAAALgAECgYJBwAAAA==.',
En='Enash:BAAALgAECgQJBwAAAA==.Engvald:BAAALgADCgUJBQAAAA==.Enhua:BAAALgADCgUJBQAAAA==.Enjoi:BAAALgAECgEJAQABLgAFFAEJAQACAAAAAA==.',
Er='Eretin:BAAALgADCgEJAQAAAA==.Erismorn:BAABLgAECn8iAAQOAAcJNR5cCwCpAQAOAAYJnBtcCwCpAQAEAAYJiBiJPwB/AQAQAAEJ4RAEcAA1AAAAAA==.',
Eu='Eudi:BAAALgAECgEJAgAAAA==.',
Ev='Eventhorizòn:BAAALgAECggJDwAAAA==.Evilhoe:BAAALgADCgUJBQAAAA==.Evocation:BAAALgAECggJDgAAAA==.Evoextoons:BAAALgADCgcJEgAAAA==.',
Fa='Fallen:BAAALgAECgYJEgAAAA==.Fallingvoid:BAABLgAECn9gAAIEAAkJJiQaAgC3AwAEAAkJJiQaAgC3AwAAAA==.Fatchungus:BAAALgAFFAMJBAAAAA==.Fatherben:BAABLgAECn8XAAIEAAYJVBVEXAAjAQAEAAYJVBVEXAAjAQAAAA==.Fatmagus:BAAALgAECgcJBgAAAA==.Favio:BAAALgAECgQJBAAAAA==.',
Fe='Fellbian:BAAALgADCgcJCwAAAA==.Fentanyahu:BAAALgAECgYJBgAAAA==.Ferozz:BAACLgAFFH8FAAIJAAIJBhDZFgCSAAAJAAIJBhDZFgCSAAAuAAQKfzEAAgkACAm9Hn0EANkBAAkACAm9Hn0EANkBAAAA.',
Fi='Fiercetaco:BAAALgADCgEJAQAAAA==.Finaliter:BAABLgAECn8qAAIIAAkJOiBqEwCUAgAIAAkJOiBqEwCUAgAAAA==.Finatar:BAAALgADCgcJCwAAAA==.Fiora:BAABLgAECn8SAAIEAAcJKx87KQBdAgAEAAcJKx87KQBdAgAAAA==.Fitz:BAAALgADCgEJAQAAAA==.Fiveyears:BAAALgADCgEJAQAAAA==.',
Fk='Fknutmcgee:BAAALgAECgUJBQAAAA==.',
Fl='Flamingdrago:BAAALgADCgMJAwAAAA==.Flinti:BAAALgAECgUJCQAAAA==.Floggy:BAABLgAECn8YAAIBAAgJtAZEgwA2AQABAAgJtAZEgwA2AQAAAA==.',
Fo='Forsight:BAABLgAECn8YAAIUAAgJTxWXWgBwAQAUAAgJTxWXWgBwAQAAAA==.',
Fr='Fracker:BAAALgAECgcJCAAAAA==.Frankzzorz:BAABLgAECn80AAMWAAkJNRy0DACHAgAWAAkJNRy0DACHAgAXAAIJRSCrQACxAAAAAA==.Fremder:BAACLgAFFH8LAAIFAAMJdxZ7FADvAAAFAAMJdxZ7FADvAAAuAAQKfzAAAgUACAlTHa4GAFQCAAUACAlTHa4GAFQCAAAA.Fresher:BAABLgAECn8VAAIUAAUJyxwyfwAdAQAUAAUJyxwyfwAdAQAAAA==.Freyjen:BAAALgADCgkJGAABLgAECgcJCgACAAAAAA==.Froboz:BAAALgADCgYJCQAAAA==.Frogevil:BAAALgAECgYJCgAAAA==.Frogtree:BAAALgADCgUJBQAAAA==.Frostygirl:BAABLgAECn8kAAIBAAgJPRDkWACTAQABAAgJPRDkWACTAQAAAA==.',
Fu='Funeral:BAACLgAFFH8iAAQaAAgJmhgtAgBoAQAaAAUJ/R0tAgBoAQAbAAIJdgzxBAC6AAAZAAMJFhN4MACyAAAuAAQKfzMABBoACQmyIz4EAKECABoABwnSID4EAKECABsABwksIjgCAFoCABkACAn9GOtEAP0BAAAA.',
['Fà']='Fàstïk:BAAALgAECgEJAQAAAA==.',
Ga='Gallory:BAAALgAECgcJDQAAAA==.Gareeshala:BAAALgAECgIJAgAAAA==.',
Ge='Geomancer:BAAALgADCgQJBAAAAA==.',
Gi='Gimmedatmouf:BAABLgAECn8UAAQPAAgJciHjCAABAwAPAAgJciHjCAABAwASAAQJexaTRwCZAAAdAAIJoxmOIQCUAAAAAA==.Gimmedatneck:BAABLgAECn8VAAMeAAgJTSNhGABEAgAeAAgJTSNhGABEAgAfAAEJNhLgHABDAAAAAA==.Gingy:BAAALgADCgYJCwAAAA==.',
Gl='Glead:BAABLgAECn8VAAINAAgJchWNLQD9AQANAAgJchWNLQD9AQAAAA==.',
Gn='Gneeduh:BAAALgAECgEJAQAAAA==.',
Go='Gobknight:BAAALgADCggJCAAAAA==.Goldina:BAAALgAECgEJAQAAAA==.Gooklover:BAAALgAECgQJBwAAAA==.Gosupal:BAAALgADCgYJBgAAAA==.',
Gr='Gracious:BAAALgAECgEJAQAAAA==.Graegor:BAAALgADCgEJAQAAAA==.Grastim:BAAALgAECgQJBQAAAA==.Greenfanta:BAAALgADCgYJEAAAAA==.Grill:BAAALgADCgEJAQAAAA==.Grinkle:BAABLgAECn8rAAILAAkJIxEsKQDBAQALAAkJIxEsKQDBAQAAAA==.Gripopotamus:BAAALgADCgYJBwAAAA==.Gristle:BAAALgADCgkJHgAAAA==.',
Gu='Gunner:BAAALgAECgQJBQABLgAECgUJDAACAAAAAA==.',
Ha='Hakaishaz:BAAALgADCgMJAwAAAA==.Halfwatt:BAAALgAECgQJCwAAAA==.Hamaddor:BAAALgAECgYJBgAAAA==.Handen:BAAALgADCggJCAAAAA==.Haraldsson:BAABLgAECn8cAAIIAAgJyRRxSACmAQAIAAgJyRRxSACmAQAAAA==.Harmony:BAAALgADCgcJCgAAAA==.Harrin:BAAALgADCgYJDAAAAA==.Harrydabs:BAABLgAECn8dAAMOAAkJRCNNAACDAwAOAAkJRCNNAACDAwAQAAQJJRB3PwD+AAAAAA==.Haru:BAABLgAECn8WAAITAAcJMxBVHABxAQATAAcJMxBVHABxAQAAAA==.Harvaal:BAAALgAECgUJBQAAAA==.Hasaro:BAABLgAECn8fAAIKAAkJsxVvCAADAgAKAAkJsxVvCAADAgAAAA==.Hashimi:BAAALgAECgcJBwAAAA==.Havokvacano:BAABLgAECn8WAAIIAAgJ/BI9VACFAQAIAAgJ/BI9VACFAQAAAA==.',
He='Healmachine:BAAALgAECgQJBgAAAA==.Hellbrringer:BAAALgAECgQJCAAAAA==.Helzerx:BAAALgAECgkJDwAAAA==.',
Ho='Hoely:BAAALgAECgEJAQAAAA==.Hogmanjr:BAAALgADCgEJAQAAAA==.Hotsordots:BAAALgAECggJCwAAAA==.Hounskul:BAABLgAECn8gAAIZAAkJogehXABMAQAZAAkJogehXABMAQAAAA==.',
Hu='Hugealien:BAAALgADCgIJAgAAAA==.Hungchungus:BAAALgAECgEJAgAAAA==.Hungwaylo:BAAALgADCgIJAgAAAA==.',
Hw='Hwere:BAAALgAECgUJBgAAAA==.',
Hy='Hypnoticpal:BAAALgAECgkJBwAAAA==.Hystëria:BAACLgAFFH8KAAIUAAMJaRVLaQCdAAAUAAMJaRVLaQCdAAAuAAQKfzgAAxQACAnPIPkdAFICABQACAlyIPkdAFICABUABglKIvgEAPwBAAAA.Hyunlix:BAAALgADCgUJBQAAAA==.',
Ia='Iammoo:BAAALgAECgQJBQAAAA==.',
Id='Idasie:BAAALgADCgYJBgAAAA==.',
Ig='Igotkappa:BAAALgADCgMJAwAAAA==.Igotyourback:BAAALgAECggJCAAAAA==.',
Il='Ilydris:BAAALgADCgQJBAAAAA==.',
Im='Imadruid:BAAALgADCgQJBAAAAA==.',
Io='Iolyte:BAAALgAECgYJDQAAAA==.',
Ir='Iridellis:BAAALgAFFAIJAwAAAA==.',
Is='Ispankutank:BAAALgAECgYJBgAAAA==.',
It='Itssofluffy:BAABLgAECn8oAAQdAAkJCxc9BgAoAgAdAAkJchY9BgAoAgAKAAUJBhfbEwAyAQASAAIJUgkxbAAsAAAAAA==.Itwon:BAAALgADCgkJFwAAAA==.',
Iz='Izzelda:BAAALgADCgQJBQAAAA==.',
Ja='Jacus:BAAALgAECgIJAwAAAA==.Jahumc:BAAALgAECgEJAQAAAA==.Jaycers:BAABLgAECn8iAAQgAAkJ9SCdAgC2AgAgAAkJ8B+dAgC2AgAIAAUJERxabQBKAQAhAAEJ2AIAnwAqAAAAAA==.Jayclark:BAAALgADCgcJCgAAAA==.',
Je='Jessiriusrex:BAAALgADCgEJAQAAAA==.',
Jo='Joemomma:BAAALgAECgYJDAAAAA==.Jokestarfist:BAABLgAECn8XAAIIAAQJIxV9kwADAQAIAAQJIxV9kwADAQAAAA==.',
Jt='Jtheshadow:BAAALgAECgEJAQAAAA==.',
Ju='Junachan:BAAALgAECgMJBQAAAA==.Jurichan:BAAALgAECgMJCQAAAA==.',
['Jä']='Jägernaut:BAAALgADCgEJAQAAAA==.',
Ka='Kaitokit:BAAALgAFFAEJAQAAAA==.Kajamando:BAABLgAECn8eAAIQAAgJ7gc7HgAhAQAQAAgJ7gc7HgAhAQAAAA==.Kalith:BAABLgAECn8YAAITAAkJCgMoIwA1AQATAAkJCgMoIwA1AQAAAA==.Kallydots:BAAALgADCgcJDQAAAA==.Kayllina:BAABLgAECn8dAAIUAAgJnwR3hAATAQAUAAgJnwR3hAATAQAAAA==.Kayotic:BAABLgAECn8eAAIQAAcJjAQjKgDIAAAQAAcJjAQjKgDIAAAAAA==.Kayww:BAAALgAECgIJAgAAAA==.',
Ke='Keinarra:BAAALgADCgMJBgAAAA==.Kell:BAAALgADCgcJCAAAAA==.Kelmorphic:BAABLgAECn8eAAIOAAkJMh1pAgCUAgAOAAkJMh1pAgCUAgAAAA==.Keropikapika:BAAALgADCgUJBQAAAA==.',
Kh='Khaali:BAAALgAECgEJAgAAAA==.Khristina:BAAALgAECgEJAQAAAA==.',
Ki='Kikiana:BAAALgAECgQJCAABLgAECggJKQAiAKUhAA==.Kikstyx:BAAALgADCgYJCAAAAA==.Killerxd:BAABLgAECn8VAAIIAAgJbRc3TACbAQAIAAgJbRc3TACbAQAAAA==.Killesea:BAAALgADCgcJDAAAAA==.Kittfisto:BAABLgAECn8eAAMEAAkJiBStXgCFAQAEAAkJiBStXgCFAQAQAAYJmAx9IwD3AAAAAA==.',
Kn='Knitemare:BAAALgAECgEJAQAAAA==.',
Ko='Korivos:BAAALgADCgMJAwAAAA==.Kosmas:BAABLgAECn8dAAMNAAgJJCGGFAADAgANAAgJ2x6GFAADAgAMAAUJexxaFwBGAQAAAA==.',
Kr='Krushgar:BAABLgAECn8UAAMUAAcJsRcIXQDbAQAUAAcJsRcIXQDbAQAVAAEJsxDnIgAwAAAAAA==.',
Ku='Kuchikopii:BAAALgADCgYJBgAAAA==.Kungfuelf:BAAALgADCgEJAQAAAA==.Kurookami:BAAALgADCgYJBgAAAA==.',
La='Lackluster:BAABLgAECn8fAAIBAAgJTQlNuQBuAQABAAgJTQlNuQBuAQAAAA==.Lamatrick:BAAALgAECgUJBwAAAA==.Lanadelslayy:BAAALgAECgQJBwAAAA==.Lasenza:BAAALgADCgQJBAAAAA==.Lavacoomer:BAAALgADCgYJBQAAAA==.',
Le='Ledana:BAAALgADCgIJAgAAAA==.Lejosh:BAAALgAECgIJAgAAAA==.Lennon:BAAALgAECgkJBgAAAA==.Leona:BAAALgAECgYJCgAAAA==.Lethee:BAAALgAECgEJAgAAAA==.',
Li='Lightingbolt:BAAALgAECgUJBQAAAA==.Lilithamy:BAAALgADCgYJBgAAAA==.Lilthin:BAAALgAECgQJCQAAAA==.Liore:BAAALgAECgQJBAAAAA==.Lisathe:BAAALgAECgYJCgAAAA==.Littledude:BAAALgADCgQJBQAAAA==.Littlemorsel:BAABLgAECn8WAAIRAAkJ8xHYIgAKAgARAAkJ8xHYIgAKAgAAAA==.',
Lo='Louthar:BAAALgADCgcJAQAAAA==.',
Lt='Ltdapperdan:BAAALgAECgEJAQAAAA==.',
Lu='Lucens:BAABLgAECn8gAAIhAAcJ3w1NMABJAQAhAAcJ3w1NMABJAQAAAA==.Lunagreed:BAAALgADCgUJBQAAAA==.Lurchn:BAABLgAECn8rAAIBAAkJ9wlzZwBwAQABAAkJ9wlzZwBwAQAAAA==.',
['Lú']='Lúná:BAAALgAECgYJBwAAAA==.',
Ma='Maggieaugers:BAACLgAFFH8FAAIGAAUJ1QKbJwDjAAAGAAUJ1QKbJwDjAAAuAAQKfykAAwYACAn2D88iAHQBAAYACAn2D88iAHQBAAUABAmPBTAlAHQAAAAA.Magicmech:BAAALgADCgcJDAAAAA==.Magivacano:BAAALgAECggJEQAAAA==.Mahnon:BAABLgAECn8aAAIRAAkJowgGTgBfAQARAAkJowgGTgBfAQAAAA==.Mandril:BAAALgADCgEJAQAAAA==.Matas:BAAALgAECgYJDQAAAA==.Matias:BAAALgAECgEJAQAAAA==.Mazzikane:BAAALgAECgMJAwAAAA==.',
Mc='Mcdeath:BAAALgADCgIJAgAAAA==.',
Me='Metalhedface:BAABLgAECn8YAAMMAAgJaBHcFQBVAQAMAAcJ5hPcFQBVAQANAAUJ4BDAZAAgAQAAAA==.',
Mi='Mikecoxwall:BAABLgAECn8wAAMBAAkJuRMgLQAkAgABAAkJuRMgLQAkAgAjAAYJ3wj9CgAqAQAAAA==.Mikuru:BAAALgAECgEJAwAAAA==.Milena:BAAALgAECgEJAQAAAA==.Milov:BAAALgADCgUJBQAAAA==.Minarva:BAAALgAECgcJCgAAAA==.Misary:BAAALgAECgQJBAAAAA==.Mischeif:BAAALgAECgUJCwAAAA==.',
Mo='Mojomon:BAAALgADCgYJBgAAAA==.Moltganus:BAAALgAECgUJDwAAAA==.Monkeli:BAAALgAECgcJEQAAAA==.Monkitard:BAAALgAECgMJAwAAAA==.Monkryn:BAAALgAECgUJCAABLgAFFAUJDAAdAPYSAA==.Monkup:BAAALgAECgEJAQAAAA==.Moocifer:BAAALgAECgEJAQAAAA==.Moogrim:BAAALgADCgkJDgAAAA==.Moonsiand:BAACLgAFFH8QAAMTAAUJwgjsEQABAQATAAQJHgPsEQABAQARAAUJBwiaNADwAAAuAAQKfycABBEACAmqGM43AKwBABMACAleEysOAOYBABEABwnOFs43AKwBAAkAAQmqAV+ZABwAAAAA.Moosafur:BAABLgAECn8eAAMKAAkJ0iA4AgDdAgAKAAgJ9CQ4AgDdAgAdAAIJeQPHNQAuAAAAAA==.Mooshoe:BAAALgAECgEJAQAAAA==.Morphyr:BAAALgAECgYJBgAAAA==.Morrigån:BAAALgAECgIJAgAAAA==.Morvoult:BAAALgAECgEJAQAAAA==.Motgus:BAAALgAECgMJBQAAAA==.',
Ms='Mshottie:BAAALgAECgcJDQAAAA==.Msuysu:BAAALgAECgEJAQABLgAECgEJAgACAAAAAA==.',
Mt='Mtngrounds:BAAALgADCgIJAgAAAA==.',
Mu='Murkt:BAAALgAECgEJAQAAAA==.Mutuusami:BAAALgAECgEJAgAAAA==.',
Mx='Mx:BAAALgAECgUJBwAAAA==.',
My='Myraine:BAAALgAECgMJAwAAAA==.Myway:BAAALgADCggJCwAAAA==.',
Na='Naari:BAABLgAECn8ZAAMNAAcJ/xLzOwAGAQANAAYJwhHzOwAGAQAMAAEJLxl8SABDAAAAAA==.Naniwa:BAAALgAECgEJAQABLgAECggJFwALAN8UAA==.Naoya:BAAALgADCgIJAgAAAA==.Narexia:BAABLgAECn8jAAIkAAYJNxylDQBpAQAkAAYJNxylDQBpAQAAAA==.Natureboyy:BAAALgADCgcJDAAAAA==.',
Ne='Nekuma:BAAALgAFFAIJAgABLgAFFAUJFwAVAE0hAA==.Nellaa:BAAALgAECgcJEAAAAA==.',
Ni='Nightfury:BAAALgAECgcJDQAAAA==.Niklus:BAAALgAECgEJAQAAAA==.Nissanaltima:BAAALgADCgYJCQAAAA==.Nithilis:BAABLgAECn8sAAIHAAkJOBzuCwBIAgAHAAkJOBzuCwBIAgAAAA==.',
No='Noee:BAAALgADCgUJBQAAAA==.Nokkiewae:BAAALgADCgcJEgAAAA==.Nomadic:BAAALgADCgkJCQAAAA==.Nool:BAAALgADCgYJBQAAAA==.Nople:BAABLgAECn8fAAIBAAgJGBZ2VwCXAQABAAgJGBZ2VwCXAQAAAA==.',
Nu='Nutellaa:BAAALgAFFAIJAwAAAA==.',
Ny='Nymueline:BAAALgADCgUJBQAAAA==.',
Ob='Obie:BAAALgAECgUJBwAAAA==.Oborax:BAEBLgAECn8bAAIIAAcJqRbrVwB8AQAIAAcJqRbrVwB8AQAAAA==.',
Od='Od:BAAALgAECgYJBwAAAA==.',
Ok='Okiro:BAAALgAECgMJAwAAAA==.Okoru:BAAALgADCgIJAgAAAA==.',
Ol='Oluun:BAAALgADCgQJBAAAAA==.',
Ot='Otmetka:BAAALgADCgcJAQAAAA==.',
Pa='Palapal:BAAALgAECgYJDgAAAA==.Paldi:BAABLgAECn8WAAIIAAgJORnRKwB0AgAIAAgJORnRKwB0AgABLgAFFAMJBAACAAAAAA==.Papaozz:BAABLgAECn8WAAIeAAcJjwU9LADbAAAeAAcJjwU9LADbAAAAAA==.Pawcalypse:BAAALgAECgMJAwAAAA==.Paws:BAAALgAECgcJEgAAAA==.',
Pe='Perelia:BAABLgAECn8nAAIlAAgJswqMHgB+AQAlAAgJswqMHgB+AQAAAA==.Pewpewqt:BAAALgAECgUJBwABLgAECgcJKgAPACMZAA==.',
Pl='Plaguehammer:BAABLgAECn8WAAIUAAYJlwgdnwDjAAAUAAYJlwgdnwDjAAAAAA==.Playstationn:BAAALgADCgUJBQAAAA==.',
Pn='Pnwbambii:BAAALgADCgIJAgAAAA==.',
Po='Popcola:BAAALgADCgEJAQAAAA==.Popopopopopo:BAAALgAFFAQJBAAAAA==.Portholio:BAAALgAECgYJBgAAAA==.',
Pu='Pubbles:BAAALgAECggJEgAAAA==.Punizher:BAAALgAECgMJAwAAAA==.Purerage:BAAALgAECgYJDQAAAA==.',
Pv='Pvc:BAAALgAECgYJCQABLgAFFAUJCQAWAA8YAA==.',
Py='Pyrella:BAAALgADCgEJAQABLgAECgcJEAACAAAAAA==.Pyyrhadrood:BAAALgAECgMJAwAAAA==.Pyyrhanice:BAAALgAECgUJDgAAAA==.Pyyrhaspice:BAAALgADCgUJCQAAAA==.',
Qu='Quetzlcoatl:BAAALgADCgUJBQABLgAECgcJDQACAAAAAA==.',
Ra='Radiantharm:BAAALgAECgUJCwAAAA==.Raevalinaa:BAAALgAECgMJBgABLgAECggJJAABAD0QAA==.Raevelinaa:BAAALgAECgIJAwABLgAECggJJAABAD0QAA==.Randzmannz:BAAALgAECgMJAwAAAA==.Raph:BAAALgAECgIJAgAAAA==.Rarelootboss:BAAALgADCgcJDAAAAA==.',
Re='Reason:BAAALgAECgYJEgAAAA==.Redbaer:BAAALgADCgUJBQAAAA==.Renair:BAAALgADCgMJAwAAAA==.Renoitukax:BAABLgAECn8pAAMHAAkJGxeSDgAhAgAHAAkJGxeSDgAhAgAlAAUJEBm9HQCFAQAAAA==.Restorn:BAAALgADCgcJCgAAAA==.Retussy:BAAALgADCgEJAQAAAA==.Reynard:BAAALgAFFAEJAQAAAA==.Rezz:BAACLgAFFH8QAAIBAAUJxA0DQgA2AQABAAUJxA0DQgA2AQAuAAQKfyAAAgEACQmQHIgpAM0CAAEACQmQHIgpAM0CAAAA.',
Ri='Ridic:BAAALgADCgMJAwAAAA==.Rigour:BAAALgADCgMJAwAAAA==.',
Ro='Rocketpop:BAAALgADCgIJAgAAAA==.Rosiegirl:BAAALgADCgkJCgAAAA==.',
Ry='Ryzen:BAAALgAECgYJBwAAAA==.',
Sa='Salaelana:BAAALgADCgcJCQAAAA==.Saltzpyre:BAAALgADCgYJBAAAAA==.Saninar:BAAALgAECgEJAQAAAA==.',
Sc='Schezmu:BAAALgAECgIJAgAAAA==.Scruffknight:BAAALgAECgYJBgAAAA==.Scrufies:BAABLgAECn8WAAIeAAgJcxNTFwCKAQAeAAgJcxNTFwCKAQAAAA==.',
Se='Seisappho:BAAALgADCgMJAwAAAA==.Senorfiesta:BAAALgAECgQJBAAAAA==.Serenityboop:BAAALgADCgYJCQAAAA==.Sergnocchi:BAAALgAECgcJCAAAAA==.Sethour:BAAALgADCgQJBAAAAA==.',
Sh='Shaee:BAAALgADCgkJDwAAAA==.Shalthender:BAAALgADCgUJBQAAAA==.Shamans:BAABLgAECn8XAAIDAAcJeB62FQDpAQADAAcJeB62FQDpAQAAAA==.Shamncheese:BAAALgAECgYJDwAAAA==.Shamorcc:BAAALgADCgQJBAAAAA==.Shasta:BAACLgAFFH8SAAIKAAQJHiIiAgCbAQAKAAQJHiIiAgCbAQAuAAQKfygAAgoACAlaJW8BAEEDAAoACAlaJW8BAEEDAAAA.Shaulthariel:BAAALgAECgEJAQAAAA==.Shioz:BAAALgADCgQJBgAAAA==.Shisuiuchiha:BAAALgAECgYJDAAAAA==.Shootumup:BAAALgAECgEJAQAAAA==.Shootybithc:BAAALgADCgEJAQAAAA==.Shuhari:BAAALgAECgkJEAAAAQ==.Shyx:BAAALgADCgIJAgAAAA==.',
Si='Siilas:BAACLgAFFH8OAAQZAAQJqQjQVgDQAAAZAAQJzwTQVgDQAAAbAAEJhw/GEgBKAAAaAAIJ7QA/HQA6AAAuAAQKfyoAAxkACQljF+gbAEICABkACQljF+gbAEICABoABAlQBwFBALEAAAAA.Simplèjack:BAAALgADCgMJAwABLgAECgkJKwALACMRAA==.Sinamon:BAABLgAECn8pAAIIAAcJKiLTIgA1AgAIAAcJKiLTIgA1AgAAAA==.Sinani:BAABLgAECn8cAAIBAAgJtwOppgD3AAABAAgJtwOppgD3AAAAAA==.Sinista:BAAALgADCgkJCQAAAA==.Sinnamon:BAAALgAECgYJDAABLgAECgcJKQAIACoiAA==.',
Sj='Sjdh:BAABLgAECn8XAAIEAAcJnBK/SwBVAQAEAAcJnBK/SwBVAQAAAA==.Sjrogue:BAABLgAECn8nAAIeAAgJ6RNbGwAmAgAeAAgJ6RNbGwAmAgAAAA==.',
Sk='Skjolvarn:BAEALgAECgMJBwAAAA==.Skram:BAAALgAECgMJBAAAAA==.',
Sl='Slammydooker:BAABLgAECn8ZAAMeAAkJlhW7EADVAQAeAAkJlhW7EADVAQAfAAEJ1QcMIQAtAAAAAA==.Sleeptoken:BAAALgAECgMJCAAAAA==.Slyphz:BAAALgAECgYJBgAAAA==.',
Sm='Smightymouse:BAAALgADCgEJAQAAAA==.',
Sn='Snoipuh:BAAALgAECgUJBQAAAA==.',
So='Solas:BAAALgAECgQJBwAAAA==.Soletaken:BAAALgADCggJDwAAAA==.Solio:BAAALgADCgYJFQAAAA==.Solisha:BAAALgADCgkJCQAAAA==.Somberdh:BAAALgADCgcJBwAAAA==.Sonofsand:BAAALgAECgIJAgAAAA==.Soulja:BAAALgADCgEJAgAAAA==.Soulmoethus:BAAALgADCgYJCQAAAA==.',
Sp='Sprayandpray:BAAALgAECgQJCAAAAA==.Sprinklely:BAAALgADCgcJCgAAAA==.',
Sq='Squirtney:BAAALgADCgMJAwAAAA==.',
Ss='Ss:BAABLgAFFH8IAAIaAAMJ7ADUDACPAAAaAAMJ7ADUDACPAAAAAA==.Ssl:BAAALgADCgQJBAAAAA==.',
St='Starrwood:BAABLgAECn8jAAIRAAgJDArkTwBaAQARAAgJDArkTwBaAQAAAA==.Statik:BAAALgAECgEJAQAAAA==.Statík:BAAALgAECgEJAQABLgAECgEJAQACAAAAAA==.Stepmonk:BAAALgADCgEJAgAAAA==.Stevesharts:BAAALgADCgYJCwAAAA==.Stonedlock:BAAALgADCgcJCAAAAA==.Stonetusk:BAAALgADCgMJAwAAAA==.Stroya:BAAALgAECgUJBgAAAA==.',
Su='Sunpali:BAAALgAECgYJCQAAAA==.',
Sw='Swank:BAAALgADCgEJAQAAAA==.',
Sx='Sx:BAAALgADCgIJAgAAAA==.',
Sy='Syaa:BAAALgAECgYJBQAAAA==.Syberis:BAAALgADCgcJDgAAAA==.',
Ta='Tacholy:BAAALgADCgUJBQABLgAECggJLAAMAMgcAA==.Tacodaboss:BAAALgAECgcJEAAAAA==.Talelarissia:BAAALgADCgQJBAAAAA==.Talonflame:BAABLgAECn8fAAITAAkJBBy6BwB4AgATAAkJBBy6BwB4AgAAAA==.Tansu:BAAALgAECgYJEwAAAA==.Taupo:BAACLgAFFH8HAAIWAAMJIBweGgDzAAAWAAMJIBweGgDzAAAuAAQKfycAAhYACQlyH6kNAHoCABYACQlyH6kNAHoCAAAA.',
Tb='Tbanger:BAAALgAECgYJDgAAAA==.Tbh:BAAALgAFFAEJAQABLgAFFAUJCQAWAA8YAA==.',
Te='Techevo:BAAALgAECgQJBQAAAA==.Techfire:BAABLgAECn8pAAImAAkJ9hr7AAB5AgAmAAkJ9hr7AAB5AgAAAA==.Techsmexx:BAAALgAECgMJBQAAAA==.Tenebron:BAABLgAECn8dAAInAAYJQBIyHAAFAQAnAAYJQBIyHAAFAQAAAA==.Tenlucis:BAAALgAECgcJCgAAAA==.',
Th='Thaelyssa:BAAALgAECgEJAQAAAA==.Tharria:BAAALgADCgcJBwAAAA==.Thearia:BAABLgAECn8ZAAMPAAcJ/BSBUgBcAQAPAAcJ/BSBUgBcAQASAAUJmg4lPgDAAAAAAA==.Thecanmurk:BAAALgADCgkJEgAAAA==.Thedilf:BAAALgADCgEJAQAAAA==.Thicktotem:BAAALgAECgIJAgAAAA==.Thickumz:BAAALgAECgMJBgAAAA==.Thorenis:BAAALgADCgEJAQAAAA==.Thoryndruid:BAACLgAFFH8MAAIdAAUJ9hKfAQBWAQAdAAUJ9hKfAQBWAQAuAAQKfy0AAx0ACQmOIhEDAA4DAB0ACQlEIhEDAA4DAAoABwm8HtIHABMCAAAA.Thorïn:BAAALgADCgMJAwAAAA==.Thorýn:BAACLgAFFH8NAAIUAAQJ9hr4agCbAAAUAAQJ9hr4agCbAAAuAAQKfxoAAhQACAl7HoYaAGYCABQACAl7HoYaAGYCAAEuAAUUBQkMAB0A9hIA.Thórin:BAAALgAECgcJEQAAAA==.',
Ti='Timakk:BAAALgADCgEJAQAAAA==.Tipsy:BAABLgAECn8hAAMLAAkJMAxgLACvAQALAAkJMAxgLACvAQADAAIJigpPZgBWAAAAAA==.',
To='Tomfoolary:BAAALgAECgEJAgAAAA==.Toofy:BAAALgAECgEJAQAAAA==.Total:BAAALgADCgkJDAAAAA==.Totembear:BAAALgAECgEJAQAAAA==.',
Tr='Tralleth:BAABLgAECn8cAAMGAAgJ/hApJgBcAQAGAAgJ/hApJgBcAQAFAAEJGgioMAAuAAAAAA==.Trillbilly:BAAALgAECgEJAQAAAA==.Trinora:BAAALgADCgkJDgAAAA==.Trolltard:BAAALgAECgIJAgABLgAECgMJAwACAAAAAA==.Troxa:BAAALgAECgQJBQAAAA==.',
Tu='Tuskor:BAAALgADCggJCAAAAA==.',
Tw='Twinklord:BAAALgAECgcJDAAAAA==.',
Ty='Tylolight:BAAALgADCgMJAwAAAA==.Tylototem:BAAALgAFFAEJAgAAAA==.',
Ug='Uglyboi:BAAALgAECggJCQAAAA==.',
Uj='Ujcmonk:BAAALgAECgQJBAAAAA==.',
Ul='Ullbian:BAAALgADCgMJAwAAAA==.Ultramar:BAAALgADCgEJAQAAAA==.',
Un='Uncookedham:BAAALgAECgQJCwAAAA==.',
Ur='Urgh:BAABLgAECn8YAAIHAAgJdA/jJABOAQAHAAgJdA/jJABOAQAAAA==.Urk:BAAALgAECgYJBgAAAA==.Urzaa:BAAALgAECgEJAgAAAA==.',
Ut='Uthur:BAAALgAECgMJAwAAAA==.',
Va='Vaeelrundor:BAAALgADCgIJAgAAAA==.Valethales:BAAALgADCgcJBwAAAA==.Vanillaface:BAAALgAECggJEgAAAA==.Vape:BAAALgAECgUJDAAAAA==.',
Ve='Veinripp:BAAALgADCgUJBQAAAA==.Velarael:BAABLgAECn8aAAIZAAYJlAotkwDZAAAZAAYJlAotkwDZAAAAAA==.Velaryn:BAAALgADCgIJAgAAAA==.Veldar:BAAALgADCgIJAgAAAA==.Velekete:BAAALgADCgUJBQAAAA==.Velethei:BAAALgAFFAEJAQAAAA==.Velian:BAAALgADCgMJBAAAAA==.Verdesalsa:BAAALgAECgYJCQAAAA==.Verox:BAAALgADCgMJAwAAAA==.',
Vh='Vheckxus:BAABLgAECn8UAAIDAAYJ8Q96OQD5AAADAAYJ8Q96OQD5AAAAAA==.',
Vi='Vicv:BAABLgAECn8QAAIHAAgJlAwXNABIAQAHAAgJlAwXNABIAQAAAA==.',
Vo='Voidberg:BAAALgADCgYJBgAAAA==.',
['Vê']='Vêa:BAAALgADCgkJCQAAAA==.',
Wa='Wachonaso:BAACLgAFFH8LAAIZAAQJIQ9rQAAJAQAZAAQJIQ9rQAAJAQAuAAQKfy0AAxkABwlJHzUuAOMBABkABwkrHzUuAOMBABoABgl8HlgXAI8BAAAA.Wanbahl:BAAALgADCgMJAwAAAA==.',
Wh='Whatuphuz:BAAALgADCgQJBQAAAA==.Wheresmyjaw:BAACLgAFFH8QAAMZAAQJaRzXJABMAQAZAAQJaRzXJABMAQAbAAEJTAvZEgBKAAAuAAQKfyAAAxkACAmQIKQ5ACUCABkACAmQIKQ5ACUCABoAAgm6DiRSAHcAAAAA.',
Wi='Wildthree:BAABLgAECn8dAAMXAAgJtByMDAAvAgAXAAgJtByMDAAvAgAoAAMJ2RQvYgC5AAAAAA==.Willenda:BAAALgADCgYJBgAAAA==.Willowins:BAAALgAECgEJAQAAAA==.Winterstired:BAACLgAFFH8NAAIiAAQJ1SNvBQCeAQAiAAQJ1SNvBQCeAQAuAAQKf0AAAyIACQmtJDoBAIsDACIACQmtJDoBAIsDACUAAQleFwAAAAAAAAAA.',
Wo='Woen:BAAALgADCggJCQAAAA==.Wolf:BAAALgAECgQJBQAAAA==.Wollffie:BAAALgAECgQJBAAAAA==.',
Wu='Wuinn:BAAALgAFFAEJAQABLgAFFAQJDQAPAOYRAA==.Wut:BAAALgADCgcJBwAAAA==.',
Wy='Wynterswrath:BAAALgAECgQJBAAAAA==.',
['Wõ']='Wõnderful:BAAALgAFFAEJAQABLgAFFAMJCgAUAGkVAA==.',
Xc='Xclobber:BAAALgADCgIJAgAAAA==.',
Xe='Xemnass:BAAALgAECgUJBwAAAA==.',
Xi='Xillas:BAAALgADCgUJBQAAAA==.',
Xo='Xoverkll:BAAALgAECgYJDAAAAA==.',
Xy='Xylina:BAAALgADCgEJAQAAAA==.Xyrii:BAAALgADCgEJAQAAAA==.',
Ya='Yadder:BAAALgAECgIJAgAAAA==.Yahro:BAACLgAFFH8LAAIIAAQJhgtQLAAlAQAIAAQJhgtQLAAlAQAuAAQKfyQAAggACAmjG6MmAIsCAAgACAmjG6MmAIsCAAAA.',
Ye='Yeahiknow:BAAALgADCgkJDgAAAA==.Yeling:BAAALgAECgEJAQAAAA==.Yep:BAAALgAECgcJBwAAAA==.',
Yi='Yiska:BAAALgADCgcJBwAAAA==.',
Yo='Yoriale:BAAALgAECgYJDgAAAA==.Yotoymuerto:BAAALgAECgMJAwAAAA==.',
Za='Zafra:BAAALgADCgEJAQAAAA==.Zaimara:BAAALgAECgEJAwAAAA==.Zalind:BAAALgAECggJEgAAAA==.Zalvianna:BAAALgAECgYJDAAAAA==.Zarindlina:BAAALgADCgUJBQAAAA==.Zarshx:BAAALgAECgYJCwABLgAFFAMJBAACAAAAAA==.',
Ze='Zemonk:BAAALgAECgYJBgAAAA==.',
Zi='Zilong:BAAALgAFFAEJAQABLgAFFAUJDwAEAAEaAA==.Zilongmage:BAAALgAFFAIJAwABLgAFFAUJDwAEAAEaAA==.Zilongwar:BAAALgAFFAIJAgABLgAFFAUJDwAEAAEaAA==.Zinnia:BAAALgADCgEJAQAAAA==.',
Zo='Zonedk:BAAALgAECgYJEgAAAA==.Zonerg:BAAALgADCgEJAgABLgAECgYJEgACAAAAAA==.Zordak:BAAALgADCgcJCAAAAA==.Zosin:BAAALgAECgEJAQAAAA==.',
Zu='Zugzugzapzap:BAAALgADCgEJAQAAAA==.',
Zy='Zylphanae:BAAALgAECgQJBAAAAA==.',
['Ør']='Ørsted:BAAALgADCgEJAQABLgAFFAMJBwAWACAcAA==.',
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
