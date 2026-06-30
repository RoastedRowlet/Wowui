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

local lookup = {'Priest-Holy','Priest-Shadow','Priest-Discipline','Monk-Mistweaver','Druid-Restoration','Rogue-Assassination','Warlock-Destruction','Mage-Frost','Unknown-Unknown','DeathKnight-Unholy','Hunter-BeastMastery','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-Survival','Evoker-Augmentation','Shaman-Restoration','DeathKnight-Blood','Paladin-Holy','Paladin-Retribution','Paladin-Protection','Evoker-Preservation','Evoker-Devastation','Warrior-Fury','Druid-Guardian','Druid-Feral','Shaman-Enhancement','Warlock-Demonology','Druid-Balance','Shaman-Elemental','Monk-Brewmaster','Rogue-Subtlety','Mage-Arcane','Monk-Windwalker','DeathKnight-Frost','Hunter-Marksmanship','Warrior-Arms','Warrior-Protection','Rogue-Outlaw','Mage-Fire','Warlock-Affliction',}
local provider = {region='US',realm='LaughingSkull',name='US',type='weekly',zone=46,date='2026-06-27',data={Ab='Abeblinken:BAAALgAECgIJAgAAAA==.Ablucia:BAAALgADCgUJCQAAAA==.Abomb:BAAALgAECgEJAgAAAA==.Abotharn:BAAALgADCgUJBQAAAA==.',
Ac='Acanaline:BAAALgAECgEJAgAAAA==.Achannara:BAAALgADCgcJBwAAAA==.',
Ae='Aennisong:BAAALgAECgUJCAAAAA==.Aeoliana:BAABLgAECn8VAAIBAAgJrQjrBQCzAAABAAgJrQjrBQCzAAAAAA==.',
Aj='Ajier:BAACLgAFFH8RAAIBAAUJxBhEDgBpAQABAAUJxBhEDgBpAQAuAAQKfy0AAgEACQkpFqMWACcCAAEACQkpFqMWACcCAAAA.',
Al='Aleraz:BAACLgAFFH8aAAMBAAYJqBZIDQB2AQABAAUJkRpIDQB2AQACAAUJWhQiGQAfAQAuAAQKfz8ABAIACQn7H4kGAOkCAAIACQn7H4kGAOkCAAEABwnbIOEVAC0CAAMAAwkmBxZjAHAAAAAA.Allcapwne:BAAALgAECgcJCwAAAA==.Allenduin:BAAALgAECgYJBwAAAA==.Alshau:BAABLgAECn8aAAIEAAcJ0BdfIwCYAQAEAAcJ0BdfIwCYAQAAAA==.Alucart:BAAALgAECgEJAQAAAA==.',
Am='Ambrosia:BAAALgAECgYJDwAAAA==.Amity:BAAALgADCgkJEAABLgAECgkJIQAFAPMdAA==.',
An='Anchoredowl:BAAALgAECgEJAgAAAA==.Anewrbyss:BAAALgAECgUJEQAAAA==.Angela:BAABLgAECn9KAAMDAAkJUx/GBgASAwADAAkJUx/GBgASAwACAAEJoww3iwAvAAAAAA==.Anna:BAAALgAECgQJBQAAAA==.Annalunà:BAAALgADCgIJBAAAAA==.Annälise:BAAALgADCgEJAQAAAA==.',
Ap='Apeople:BAACLgAFFH8PAAIGAAUJhhdsBABAAQAGAAUJhhdsBABAAQAuAAQKfzAAAgYACQmGIloBACEDAAYACQmGIloBACEDAAAA.Apocalýpsè:BAAALgAECgIJAgAAAA==.Applebottomj:BAAALgAECgMJAwAAAA==.Applebottum:BAAALgAECgkJEAAAAA==.Appärition:BAABLgAECn8zAAIHAAgJqCCbAgCKAgAHAAgJqCCbAgCKAgAAAA==.',
Ar='Arleance:BAAALgAECgUJCAAAAA==.Arondael:BAABLgAECn8iAAIGAAkJ8xjhBwDVAQAGAAkJ8xjhBwDVAQAAAA==.Arsène:BAAALgADCgcJCwAAAA==.',
As='Ashelaandrii:BAAALgAFFAEJAgAAAA==.Astroglyde:BAAALgAECgcJCQAAAA==.Aszun:BAAALgADCgUJBQAAAA==.',
Au='Aurialis:BAAALgAECgcJDQAAAA==.',
Av='Avanti:BAABLgAECn9AAAIIAAkJURufLQBjAgAIAAkJURufLQBjAgAAAA==.Avendeloria:BAABLgAECn8dAAIBAAkJiRTEHgDPAQABAAkJiRTEHgDPAQAAAA==.Averyn:BAAALgADCgEJAQAAAA==.',
Az='Azrahn:BAAALgADCgQJBQAAAA==.',
['Aü']='Aüra:BAAALgAECgEJAQABLgAECggJCQAJAAAAAA==.',
Ba='Babybear:BAAALgAECgIJAgAAAA==.Backmoist:BAAALgAECgQJBwAAAA==.Bagmaster:BAACLgAFFH8aAAIBAAUJDCCzCADEAQABAAUJDCCzCADEAQAuAAQKfzgAAgEACQkAJpkCAD4DAAEACQkAJpkCAD4DAAAA.Bahm:BAAALgADCgYJEwAAAA==.Baktolife:BAAALgAECgkJBAAAAA==.Bam:BAAALgAECgQJBQABLgAFFAIJBgAKAJshAA==.Bartholomoo:BAABLgAECn9BAAIKAAkJvyIQEADsAgAKAAkJvyIQEADsAgAAAA==.Bayonetta:BAAALgAECgcJDQAAAA==.',
Be='Beeftornado:BAAALgAECgYJBwAAAA==.Belakor:BAAALgADCgIJAgAAAA==.Ber:BAAALgAECgEJAwAAAA==.',
Bi='Bichstewy:BAAALgAECgEJAQAAAA==.Bigbusta:BAAALgADCgMJAwAAAA==.Bigmanblasto:BAAALgADCgMJBAAAAA==.Bildros:BAAALgAECgEJAQAAAA==.Birgite:BAAALgAECgYJEQAAAA==.Bizniz:BAAALgAECgYJDAAAAA==.',
Bl='Blackdracula:BAAALgAECgEJAQAAAA==.Blastin:BAAALgADCgcJBwAAAA==.Blazefury:BAABLgAECn8ZAAILAAYJcwwdqADyAAALAAYJcwwdqADyAAAAAA==.Blazeknight:BAACLgAFFH8IAAIMAAMJIw97CQCHAAAMAAMJIw97CQCHAAAuAAQKfy4AAwwACQn9GV0WANYBAAwACQn9GV0WANYBAA0AAQkAAIIkAAAAAAAA.Blazemaker:BAACLgAFFH8LAAIIAAQJhQRQfADeAAAIAAQJhQRQfADeAAAuAAQKfxoAAggABgk8EMTAAAgBAAgABgk8EMTAAAgBAAAA.Blazemaster:BAAALgAECgQJCQAAAA==.Blinduru:BAACLgAFFH8VAAINAAQJNyLLKACHAQANAAQJNyLLKACHAQAuAAQKfzkAAg0ACQltJcoCAFsDAA0ACQltJcoCAFsDAAAA.Blitz:BAAALgAECgIJAgAAAA==.Blocktor:BAAALgAECgMJAwABLgAECgYJHAANANkOAA==.Bloodsylf:BAAALgAECgkJBAABLgAECgcJFgAOAM4TAA==.Bluberriez:BAAALgAECgYJBgAAAA==.',
Bo='Bobbiepines:BAAALgAECgMJAwAAAA==.Bonez:BAAALgAECgMJAwAAAA==.Boocakey:BAAALgADCgkJCgAAAA==.Book:BAABLgAECn8UAAIDAAkJHBV7EQBdAgADAAkJHBV7EQBdAgAAAA==.Bookie:BAAALgAECgcJCAAAAA==.Books:BAAALgAECgcJBwAAAA==.Booza:BAAALgAECgIJAgAAAA==.Borkenshwang:BAAALgADCgYJCwAAAA==.Boydik:BAAALgAECgQJBwAAAA==.',
Bp='Bpain:BAAALgAECgMJAwABLgAECgkJMwAPAAYcAA==.Bpaìn:BAABLgAECn8zAAIPAAkJBhxoDACVAgAPAAkJBhxoDACVAgAAAA==.',
Br='Braski:BAAALgAECgEJAQAAAA==.Breandán:BAAALgADCgEJAQABLgAFFAgJIgAQAOUcAA==.Brewlïth:BAAALgAECgIJAgABLgAFFAYJEQARAMceAA==.Brewmaester:BAAALgAECgEJAgAAAA==.Brink:BAABLgAECn8aAAIIAAkJ5A8EWwDNAQAIAAkJ5A8EWwDNAQAAAA==.Brojac:BAAALgAECgcJDgAAAA==.Brokil:BAAALgADCggJDAAAAA==.Brolic:BAAALgAECgQJBQAAAA==.Brolymorph:BAAALgAECgQJBAAAAA==.Bromaster:BAAALgAECgQJBQAAAA==.Brones:BAAALgAECgkJAwAAAA==.Brossiere:BAABLgAECn8hAAQSAAgJERuSNQB6AQASAAUJZRqSNQB6AQATAAYJoxdQjABYAQAUAAUJVRenIwD4AAAAAA==.Brotemic:BAAALgAECgYJDgAAAA==.Brovine:BAAALgAECgEJAQAAAA==.Bru:BAACLgAFFH8RAAIBAAUJXxoxDQB3AQABAAUJXxoxDQB3AQAuAAQKfyoAAgEACQl1HOwMAIYCAAEACQl1HOwMAIYCAAAA.Brutalizèr:BAAALgADCgYJBgABLgAECgEJAQAJAAAAAA==.',
Bt='Bt:BAAALgAECgUJDAAAAA==.',
Bu='Bubblegal:BAAALgAECgQJCQAAAA==.Bullsmcgee:BAABLgAECn88AAMKAAkJlyVqAwBpAwAKAAkJlyVqAwBpAwARAAEJAAAXQwA9AAAAAA==.Burningtree:BAABLgAECn8iAAIIAAkJyA79ZgCvAQAIAAkJyA79ZgCvAQAAAA==.Burny:BAAALgADCgEJAQAAAA==.Burrder:BAAALgADCggJCAAAAA==.Bustdown:BAAALgADCggJDwAAAA==.Buttslapper:BAAALgADCggJCAAAAA==.',
['Bö']='Börck:BAAALgADCgUJBQAAAA==.',
['Bø']='Bøb:BAAALgAECggJCwAAAA==.',
Ca='Camamoonmana:BAABLgAECn8aAAIFAAkJ3BNxOAC1AQAFAAkJ3BNxOAC1AQAAAA==.Captcorndog:BAACLgAFFH8GAAMPAAMJ2wq3SQClAAAPAAMJ2wq3SQClAAAVAAEJ2QJ5DwAlAAAuAAQKfygABA8ACAlAFcAjAL4BAA8ACAlAFcAjAL4BABUABQnzA3k4AKcAABYAAQkAALRAAC8AAAAA.Caskket:BAABLgAECn8WAAIRAAkJbBslCgBwAgARAAkJbBslCgBwAgAAAA==.Castreytid:BAAALgAECgcJDQABLgAFFAQJBQAXAHoHAA==.Catdog:BAABLgAECn8mAAIYAAYJFRiyIwAzAQAYAAYJFRiyIwAzAQAAAA==.Catechism:BAABLgAECn8xAAMSAAkJ3B/6BgAcAwASAAkJ3B/6BgAcAwATAAYJnwjc3wDeAAAAAA==.',
Ce='Cemeo:BAABLgAECn8UAAIVAAcJiBcTFgDsAQAVAAcJiBcTFgDsAQAAAA==.Cerberusalfa:BAACLgAFFH8YAAIMAAUJ9iVYBQC6AQAMAAUJ9iVYBQC6AQAuAAQKfzgAAgwACQkTJkQBAGsDAAwACQkTJkQBAGsDAAAA.',
Ch='Chaintazer:BAAALgADCgYJBgABLgAFFAQJBQAXAHoHAA==.Chewbaca:BAAALgAECgEJAwAAAA==.Chickennuggi:BAACLgAFFH8PAAIIAAQJYRH8HgDdAAAIAAQJYRH8HgDdAAAuAAQKfyoAAggACAmsHVkrAGwCAAgACAmsHVkrAGwCAAAA.Chinchilla:BAAALgAECgEJAQAAAA==.Chiphoof:BAABLgAECn8qAAMZAAkJcxftCAA6AgAZAAkJcxftCAA6AgAYAAEJuQzVEQAoAAAAAA==.Chocofox:BAABLgAECn8hAAMQAAkJmSFuBQBcAwAQAAkJmSFuBQBcAwAaAAEJ0AOFRwAhAAAAAA==.Chokemagic:BAABLgAFFH8GAAIbAAIJbA6BnwCLAAAbAAIJbA6BnwCLAAAAAA==.Chopndot:BAAALgAECgEJBAAAAA==.Chozen:BAAALgADCgcJBwAAAA==.Chrill:BAABLgAECn8cAAINAAYJchfxbABKAQANAAYJchfxbABKAQAAAA==.',
Cl='Claraabun:BAAALgAECgUJBQABLgAFFAYJFgASAMYTAA==.Clarabuns:BAACLgAFFH8WAAISAAYJxhNKEQCsAQASAAYJxhNKEQCsAQAuAAQKfx8AAxIACQnGF2YlAPsBABIACQnGF2YlAPsBABMABQl1F/l+AHEBAAAA.Clarasbuns:BAAALgAECgMJAwABLgAFFAYJFgASAMYTAA==.Clawdragoon:BAACLgAFFH8fAAQcAAYJnA+3JgD5AAAcAAYJnA+3JgD5AAAFAAQJhAFISwCPAAAYAAEJpwJlSAAaAAAuAAQKfzAAAxwACAnVGW0UAG8CABwACAnVGW0UAG8CAAUABQlACN+bAJQAAAAA.',
Co='Coati:BAAALgADCgYJBgAAAA==.Coldorc:BAAALgADCgEJAQAAAA==.Colforbin:BAAALgADCgUJBQAAAA==.Colosie:BAAALgAECgYJEwABLgAFFAEJAQAJAAAAAA==.Comegetpsalm:BAABLgAECn89AAISAAkJJRrpEQCEAgASAAkJJRrpEQCEAgAAAA==.Cornbreadmat:BAAALgADCgcJDQAAAA==.',
Cr='Creamsock:BAAALgAECgQJCQAAAA==.Creatlach:BAACLgAFFH8iAAIQAAgJ5RymBgBcAgAQAAgJ5RymBgBcAgAuAAQKfzoAAxAACQmKG00cAGoCABAACQmKG00cAGoCAB0AAwlXE3BjALUAAAAA.Creatlachlol:BAAALgAECgkJCQABLgAFFAgJIgAQAOUcAA==.Creech:BAAALgADCgIJAgAAAA==.Creeptoken:BAAALgAECgEJAQAAAA==.Crucifilth:BAAALgADCgYJDAAAAA==.Cryopathy:BAAALgAECgYJDgAAAA==.Crypty:BAABLgAECn8dAAMdAAkJggwPNABrAQAdAAkJggwPNABrAQAQAAUJrREiXQAWAQAAAA==.',
Cy='Cyaniidee:BAAALgADCgcJBwAAAA==.Cyraxx:BAAALgADCgMJAwAAAA==.Cyrusdragon:BAAALgAECgYJBgAAAA==.Cyrussham:BAAALgAECgEJAQAAAA==.Cytherea:BAACLgAFFH8HAAITAAMJ+gMuJwB5AAATAAMJ+gMuJwB5AAAuAAQKfysAAhMACAnzD9iDAGgBABMACAnzD9iDAGgBAAAA.',
Da='Daddybod:BAABLgAECn8gAAIeAAkJjRJzHgCyAQAeAAkJjRJzHgCyAQAAAA==.Dainnan:BAAALgADCgEJAQAAAA==.Dalinek:BAAALgAECgUJBQAAAA==.Danicarkel:BAAALgAECgkJEAAAAA==.Darkcallum:BAAALgAECgUJDAAAAA==.Darktaynt:BAAALgAECgMJBQAAAA==.Darthfox:BAAALgAECgMJBQAAAA==.',
De='Deadsean:BAAALgAECgUJDAAAAA==.Deathsyn:BAABLgAFFH8JAAIKAAQJzRk+VwBEAQAKAAQJzRk+VwBEAQAAAA==.Deathtracker:BAABLgAECn8bAAILAAgJmg50YgCBAQALAAgJmg50YgCBAQAAAA==.Deathwarden:BAAALgAECggJEwAAAA==.Deathñdk:BAAALgADCgEJAQAAAA==.Debuffed:BAAALgAECgEJAQAAAA==.Delathor:BAAALgAECgcJDgABLgAFFAEJAQAJAAAAAA==.Delimeatear:BAAALgAECgIJAgABLgAECgkJHQACABkcAA==.Demiloss:BAAALgAFFAEJAQABLgAFFAQJCAATAJ0WAA==.Demise:BAACLgAFFH8HAAIIAAQJXBIsWQArAQAIAAQJXBIsWQArAQAuAAQKfy8AAggACAnmHjoxAK0CAAgACAnmHjoxAK0CAAAA.Demonclem:BAAALgAFFAIJAgAAAA==.Demonskinner:BAAALgADCgUJBQAAAA==.Denzo:BAAALgAECgMJAwAAAA==.Deoxyrybo:BAACLgAFFH8FAAIMAAMJPQpBHQC4AAAMAAMJPQpBHQC4AAAuAAQKfzsAAwwACQnkGZQNAEwCAAwACQnkGZQNAEwCAA0ABgmnC5WIABQBAAAA.Destructin:BAAALgAECgEJAQAAAA==.Destructor:BAAALgAECgcJEwAAAA==.Devourera:BAAALgAFFAMJAwABLgAFFAUJEgADAOgQAA==.',
Di='Died:BAAALgADCgMJAwAAAA==.Dilldobaggin:BAAALgADCgQJBAAAAA==.Dinoknight:BAAALgAECgcJBwAAAA==.Dinopriest:BAABLgAECn8XAAICAAcJLRcFJgCcAQACAAcJLRcFJgCcAQAAAA==.Distia:BAAALgAECgcJCgAAAA==.Divinedragon:BAABLgAECn8uAAMCAAkJGhihEgA+AgACAAkJGhihEgA+AgADAAcJ5QvnLgAoAQAAAA==.Dixoncider:BAAALgAECgQJBgAAAA==.',
Do='Doboy:BAAALgAECgEJAQAAAA==.Donmanuel:BAAALgADCgEJAQAAAA==.',
Dr='Drackaris:BAAALgADCgYJBgAAAA==.Draggo:BAAALgAECgEJAwAAAA==.Drainbamage:BAAALgAECgMJAwAAAA==.Drakin:BAABLgAECn9HAAITAAkJ0CAADQD9AgATAAkJ0CAADQD9AgAAAA==.Dreya:BAABLgAECn8aAAIaAAkJDR3ZCQAfAgAaAAkJDR3ZCQAfAgAAAA==.Dreyas:BAAALgADCgYJBgAAAA==.Drinkcoolaid:BAACLgAFFH8KAAIQAAQJvBEODQDvAAAQAAQJvBEODQDvAAAuAAQKfx8AAhAACQmfFrMgAEsCABAACQmfFrMgAEsCAAAA.Dritzle:BAABLgAECn8aAAMfAAgJBhXKIQDrAQAfAAgJBhXKIQDrAQAGAAQJHgi5EwDEAAAAAA==.Droopapi:BAAALgAECgYJEQAAAA==.',
Du='Durrt:BAAALgADCgcJCAABLgAECgcJLAAFAGsiAA==.Dutchman:BAACLgAFFH8WAAILAAcJEyLrCwANAgALAAcJEyLrCwANAgAuAAQKfxwAAgsACAkNIWYIAAsDAAsACAkNIWYIAAsDAAAA.',
['Dë']='Dëçäÿ:BAAALgADCgUJBQABLgAECgcJIQAFAMobAA==.',
Eh='Ehhmuh:BAAALgAECgYJCgAAAA==.Ehlumii:BAABLgAECn8UAAIEAAYJRSRvDgBvAgAEAAYJRSRvDgBvAgAAAA==.',
Ei='Eiffel:BAAALgADCgUJBQAAAA==.',
El='Eldrene:BAABLgAECn82AAMIAAkJYh6lGgC6AgAIAAkJYh6lGgC6AgAgAAEJ7hOWHAA6AAAAAA==.Elethil:BAAALgADCgEJAgAAAA==.Elfstomper:BAAALgADCggJCwAAAA==.Elitepaladin:BAABLgAECn8nAAISAAkJGBbfIQAPAgASAAkJGBbfIQAPAgAAAA==.Ellexi:BAAALgAECgYJDAAAAA==.Elrai:BAAALgAECgIJAwAAAA==.Elyseia:BAABLgAECn8gAAILAAkJgwbtiQArAQALAAkJgwbtiQArAQAAAA==.',
Em='Emeritus:BAAALgAECgkJBwAAAA==.Empkin:BAAALgAECgcJEwAAAA==.',
En='Enof:BAAALgADCgIJAgAAAA==.Enpower:BAAALgAECgMJAwABLgAFFAQJFQAhAO8TAA==.',
Ep='Epicsause:BAABLgAFFH8HAAIYAAMJxggSCwCAAAAYAAMJxggSCwCAAAAAAA==.',
Er='Erelor:BAAALgADCgMJAwAAAA==.',
Es='España:BAECLgAFFH8NAAIRAAUJ+hbMGQAYAQARAAUJ+hbMGQAYAQAuAAQKfy4ABBEACQlOGj0KAHYCABEACQlOGj0KAHYCACIABgncEHUcAOoAAAoAAQkAAMiuAQAAAAAA.Españaluna:BAEALgAECgcJBgABLgAFFAUJDQARAPoWAA==.Españamor:BAEALgAECgkJCAABLgAFFAUJDQARAPoWAA==.Essdeath:BAAALgAECgEJAQABLgAECgkJIAAeAI0SAA==.',
Ex='Excrucio:BAAALgADCgYJBgAAAA==.',
Ez='Ezpain:BAAALgAECgQJBQAAAA==.',
Fa='Farael:BAAALgAECgcJBAAAAA==.Farmerbrown:BAAALgAECgQJCAABLgAFFAQJCwATAF4aAA==.Fatalmann:BAACLgAFFH8LAAMVAAUJFAjLHgC4AAAVAAQJWwLLHgC4AAAWAAMJPwVhCwBpAAAuAAQKfxYAAxYACQnMD5kVAJUBABYABwmoD5kVAJUBABUABgk2DyQcAB0BAAAA.Fatalminn:BAAALgAECgUJCQAAAA==.Fathergob:BAAALgADCgEJAQAAAA==.Fatty:BAAALgADCgYJBgAAAA==.',
Fe='Fenty:BAAALgADCgEJAQAAAA==.Feralhorn:BAAALgAECgEJAQAAAA==.',
Fi='Fingerz:BAAALgADCgIJAgAAAA==.Fintan:BAAALgAFFAEJAQABLgAFFAgJIgAQAOUcAA==.Fizzlespin:BAAALgAECgMJAwAAAA==.',
Fl='Flarestrasz:BAAALgADCgUJCQAAAA==.Flexxar:BAAALgAECgEJAgAAAA==.Flinwazzart:BAAALgADCgcJBwAAAA==.Flutterby:BAAALgAECgIJAwABLgAECgkJOgACAKEJAA==.Flèxion:BAACLgAFFH8OAAIKAAUJ2R9dSgBeAQAKAAUJ2R9dSgBeAQAuAAQKfygAAgoACAkBJc8gAIUCAAoACAkBJc8gAIUCAAAA.',
Fo='Foskin:BAAALgAECgMJBAABLgAFFAQJBQAXAHoHAA==.',
Fr='Frassk:BAABLgAECn9DAAMHAAkJPBs6BgABAgAHAAcJSB06BgABAgAbAAQJ0hIV0QCyAAAAAA==.Freja:BAAALgADCgMJBgAAAA==.Frigid:BAAALgAECgkJBwAAAA==.Froggystyle:BAAALgAECgYJDgABLgAECggJDgAJAAAAAA==.Frostydru:BAABLgAECn8wAAIZAAgJfiH5BwBTAgAZAAgJfiH5BwBTAgAAAA==.Frozat:BAACLgAFFH8bAAIVAAgJGxhfBACZAgAVAAgJGxhfBACZAgAuAAQKfygAAxUACAkRI2oEAOYCABUACAkRI2oEAOYCAA8AAQmAEZ5eAEAAAAAA.Frösting:BAAALgADCgcJDgABLgAECgkJSwANAIkfAA==.',
Fu='Fullblooded:BAAALgAECgEJAQAAAA==.Fundeedo:BAAALgAFFAIJAwAAAA==.Furballieo:BAAALgADCgIJAgAAAA==.',
Ga='Galadriels:BAAALgAECgQJBAAAAA==.Galianem:BAAALgADCgMJAwAAAA==.Galled:BAAALgAECgEJAQAAAA==.Gamora:BAAALgAECgYJCQAAAA==.Gandon:BAAALgAECgQJCAAAAA==.Garbarn:BAABLgAECn8WAAITAAkJ0w9yfgBxAQATAAkJ0w9yfgBxAQAAAA==.Garonno:BAAALgADCgIJAgAAAA==.',
Ge='Gelystine:BAAALgADCgUJCgAAAA==.Geminiholy:BAAALgADCgcJBwABLgAFFAQJFQAhAO8TAA==.Geminirunes:BAAALgADCgYJBgABLgAFFAQJFQAhAO8TAA==.Germaine:BAAALgAECgQJBQAAAA==.',
Gh='Ghabi:BAAALgAECgYJBgAAAA==.Ghauri:BAAALgAECgMJBQAAAA==.',
Gi='Gia:BAABLgAECn8zAAIEAAgJpxt9FQBuAgAEAAgJpxt9FQBuAgAAAA==.',
Go='Gobx:BAAALgAECgUJBgAAAA==.Golgroth:BAABLgAECn8sAAIXAAkJLgjJOwBXAQAXAAkJLgjJOwBXAQAAAA==.Goodlocktime:BAAALgADCgIJAgABLgAECgYJCAAJAAAAAA==.Goodtimesm:BAAALgAECgYJCAAAAA==.Goodtymes:BAAALgAECgEJAQABLgAECgYJCAAJAAAAAA==.Gorearrow:BAACLgAFFH8OAAILAAUJOBSXNwA+AQALAAUJOBSXNwA+AQAuAAQKfzAAAwsACQlXItgLAOMCAAsACQlXItgLAOMCACMAAglWB2N6AFkAAAAA.Goretaint:BAAALgAECgYJDwAAAA==.Gorgesh:BAAALgADCgQJBAAAAA==.Gothladriel:BAAALgAECgYJDAAAAA==.Gotpwnedd:BAAALgAECgEJAQAAAA==.Gottamoo:BAABLgAECn8ZAAMYAAkJJwzAKQAOAQAYAAkJJwzAKQAOAQAcAAEJPQFWkAAaAAAAAA==.',
Gr='Greenstank:BAAALgAECggJDgAAAA==.Grrumpybear:BAABLgAECn9FAAIYAAkJLBxTBwCBAgAYAAkJLBxTBwCBAgAAAA==.Grundal:BAAALgADCggJCAAAAA==.',
Gu='Gumbuz:BAAALgAECgQJBgAAAA==.Gunafistya:BAABLgAFFH8LAAIEAAMJYhboOQC+AAAEAAMJYhboOQC+AAAAAA==.Gunnaroptiks:BAAALgAECgUJBQABLgAFFAUJGQAeAIsXAA==.Guzzler:BAAALgAECgkJDgAAAA==.',
['Gú']='Gúildarts:BAAALgADCgEJAQAAAA==.',
Ha='Haannarr:BAAALgAECgIJAgAAAA==.Hairymoodini:BAAALgAECgEJAgAAAA==.Hajin:BAAALgAECgYJDwAAAA==.Hankjr:BAAALgAECgEJAwAAAA==.Hanky:BAAALgAECgQJBAAAAA==.Havòk:BAAALgAECggJBwABLgAFFAEJAQAJAAAAAA==.Hawthorn:BAAALgAECgMJCAAAAA==.Hazyblades:BAAALgAECgMJAwAAAA==.',
He='Hektar:BAAALgADCgYJBgAAAA==.Helacookie:BAABLgAECn8ZAAITAAkJMBNSVADNAQATAAkJMBNSVADNAQAAAA==.Henso:BAAALgAFFAEJAQABLgAFFAQJFQAhAO8TAA==.Heomors:BAAALgAECgEJAQAAAA==.Hexxan:BAAALgAECgUJEAAAAA==.',
Hi='Hiawatha:BAAALgADCgEJAQABLgAECgcJBwAJAAAAAA==.Hifumi:BAAALgADCgQJBwAAAA==.Hisagu:BAAALgAECgEJAQABLgAECggJFQAKABYbAA==.Hitstabkill:BAAALgAECgEJAQAAAA==.Hiver:BAAALgAECgQJBgAAAA==.',
Ho='Hoegar:BAAALgAFFAIJAQABLgAFFAMJCQAOALkeAA==.Holes:BAAALgAECgEJAwAAAA==.Holier:BAACLgAFFH8PAAITAAQJYQ5IEgD0AAATAAQJYQ5IEgD0AAAuAAQKfzkAAhMACQn+FXRGAPMBABMACQn+FXRGAPMBAAAA.Hollows:BAAALgAECgQJBgAAAA==.Holyatrops:BAAALgAECgkJEQABLgAFFAgJLAAbALYcAA==.Hoochurcooch:BAAALgAECgEJAQAAAA==.Hoppers:BAAALgAECgIJAgABLgAECgcJDwAJAAAAAA==.Hopperstotem:BAAALgAECgcJDwAAAA==.Horuu:BAAALgAECgQJBgAAAA==.Hoyboii:BAAALgADCgYJBgAAAA==.',
Hu='Hulo:BAAALgAECgcJDwAAAA==.Humbled:BAAALgAECgQJBQAAAA==.Hunteress:BAAALgADCgYJBwAAAA==.Huntkoalas:BAAALgAECgMJAwABLgAFFAgJIwAcACIVAA==.Hurrdurr:BAAALgAECgEJAQAAAA==.Hush:BAABLgAECn8tAAMXAAkJWx3rEQBlAgAXAAkJWx3rEQBlAgAkAAEJPQmlggAnAAAAAA==.',
['Hî']='Hîflax:BAAALgAECgEJAgAAAA==.',
['Hö']='Hölyców:BAAALgADCgQJBAAAAA==.',
Ic='Ichbinstark:BAAALgAECgEJBAAAAA==.',
Id='Idonttcare:BAAALgAECgMJAwAAAA==.',
If='Ifirt:BAAALgAECgkJDgAAAA==.',
Ig='Iggnignokt:BAAALgADCgYJBwAAAA==.',
Ih='Ihealnewbs:BAAALgADCgYJDwAAAA==.',
In='Infamus:BAAALgAECgQJCgAAAA==.Invisabull:BAAALgAECgQJBgAAAA==.Invysion:BAACLgAFFH8UAAIDAAUJ/wj5CwDRAAADAAUJ/wj5CwDRAAAuAAQKfy4AAgMACQkXEf8dAN4BAAMACQkXEf8dAN4BAAAA.',
Ir='Ironballz:BAAALgAECgMJAwAAAA==.Irri:BAAALgADCgUJBQAAAA==.',
Is='Ishara:BAAALgAECggJCAABLgAECgkJNgAIAGIeAA==.',
Ja='Jacuzzi:BAAALgAECgUJCAAAAA==.Jaidess:BAAALgAECgEJAQAAAA==.',
Je='Jeangen:BAAALgAECgUJBAAAAA==.Jeanjean:BAAALgAECgcJCAAAAA==.Jeannjeann:BAAALgAECggJEgAAAA==.Jediknîght:BAAALgAECgYJBgAAAA==.Jeep:BAACLgAFFH8NAAILAAQJnhuwQgAoAQALAAQJnhuwQgAoAQAuAAQKfycAAgsACAlAJVMEAEoDAAsACAlAJVMEAEoDAAAA.Jellybea:BAACLgAFFH8RAAIBAAUJCRsoDACIAQABAAUJCRsoDACIAQAuAAQKfywAAwEACQltITEEABIDAAEACQltITEEABIDAAIAAgkJDA1xAGAAAAAA.Jesstter:BAAALgAECgEJAQAAAA==.',
Ji='Jibalynne:BAAALgAECgQJBAAAAA==.Jida:BAAALgAECgEJAQAAAA==.Jiffypop:BAAALgAECgcJDQABLgAECgkJLQAXAFsdAA==.Jinwooaura:BAAALgADCgcJBwAAAA==.',
Jo='Johnnycakes:BAAALgADCgMJBQAAAA==.Jonsnowxd:BAAALgADCgYJBgAAAA==.',
Jr='Jrhnbr:BAAALgADCgMJAwAAAA==.',
Ju='Juggnut:BAAALgAECgcJEQAAAA==.Jump:BAAALgAECgcJEwAAAA==.Junglebrew:BAAALgADCgQJBAAAAA==.Jurisdiction:BAABLgAECn8uAAITAAkJWRLESQDpAQATAAkJWRLESQDpAQAAAA==.',
Jz='Jz:BAAALgAECgMJBAAAAA==.',
['Jì']='Jìnn:BAAALgAECgUJDwAAAA==.',
Ka='Kaan:BAABLgAECn8sAAIFAAcJayJLEwCbAgAFAAcJayJLEwCbAgAAAA==.Kabea:BAAALgAECgEJAgAAAA==.Kadath:BAAALgADCgIJAwAAAA==.Kaeladín:BAAALgAECgUJCAAAAA==.Kagebouzu:BAAALgAECgYJDwAAAA==.Kahanie:BAAALgADCgcJBwAAAA==.Kahlan:BAAALgADCgcJCAABLgAECgYJDwAJAAAAAA==.Kakutogi:BAAALgADCgEJAQAAAA==.Kalycia:BAAALgAECgEJAgAAAA==.Kamela:BAAALgAECgYJCAAAAA==.Karael:BAAALgAECgUJEQABLgAFFAMJBQAQAKkWAA==.Karma:BAABLgAECn8aAAIfAAcJWQPBQADCAAAfAAcJWQPBQADCAAAAAA==.Kayliaa:BAAALgAECgkJAQAAAA==.Kazarke:BAAALgADCgcJGAAAAA==.',
Ke='Keeia:BAAALgADCgQJBQAAAA==.Keho:BAABLgAECn84AAMeAAkJdgubJQCBAQAeAAkJdgubJQCBAQAhAAIJkg6maABqAAAAAA==.Keihoe:BAAALgAECgMJAwABLgAECgkJOAAeAHYLAA==.Kenalia:BAABLgAECn8qAAIEAAkJlRbSGgBCAgAEAAkJlRbSGgBCAgAAAA==.Kengo:BAAALgAECgEJAQAAAA==.Keptalive:BAAALgADCgcJCgAAAA==.Kerzermern:BAAALgAFFAMJAwAAAA==.Kevic:BAAALgAFFAIJAwABLgAFFAUJEwACABESAA==.',
Kh='Khamaelion:BAAALgADCgcJDgAAAA==.Khromn:BAAALgAECgkJAgABLgAFFAIJAgAJAAAAAA==.',
Ki='Kiara:BAABLgAECn8eAAITAAgJNiBdIgCgAgATAAgJNiBdIgCgAgAAAA==.Kiju:BAAALgADCgYJBgAAAA==.Killaban:BAACLgAFFH8KAAIXAAQJ9BcEHwA1AQAXAAQJ9BcEHwA1AQAuAAQKfzIAAxcACQklINwXAC8CABcACQngH9wXAC8CACQAAwkZGVMrAJoAAAAA.Killbydeath:BAAALgAECgEJAQAAAA==.Kimberlyhárt:BAACLgAFFH8LAAITAAQJXhruCQA+AQATAAQJXhruCQA+AQAuAAQKfzcAAxMACQnxJL4EAFMDABMACQnxJL4EAFMDABIABAn0CmVjAKgAAAAA.Kissmydots:BAABLgAECn9EAAIbAAkJKR5+FwCXAgAbAAkJKR5+FwCXAgAAAA==.Kitja:BAABLgAECn9ZAAMDAAkJ+yFfAAAMAwADAAkJ+yFfAAAMAwABAAgJaBw3EQBZAgAAAA==.Kitla:BAAALgADCgUJBQABLgAECgkJWQADAPshAA==.',
Kl='Klipsch:BAAALgAECgEJAQAAAA==.Klukai:BAAALgADCgcJCwABLgAECgkJIQAFAPMdAA==.',
Kn='Kneed:BAAALgADCgYJBgAAAA==.',
Ko='Koala:BAAALgAECgQJBQABLgAFFAgJIwAcACIVAA==.Kohman:BAABLgAECn8bAAIbAAYJ3RXOfABiAQAbAAYJ3RXOfABiAQAAAA==.Konyani:BAAALgADCgUJAQAAAA==.',
Kp='Kpop:BAAALgAECgEJAQABLgAECgcJBwAJAAAAAA==.',
Kr='Kraeven:BAAALgADCgEJAQAAAA==.Kregerath:BAAALgADCgIJAgAAAA==.Krftpnk:BAACLgAFFH8aAAIMAAUJPSa6BQCwAQAMAAUJPSa6BQCwAQAuAAQKfyoAAwwACQnQJDcEADcDAAwACQnQJDcEADcDAA0AAQkAAOpIAQAAAAAA.Kronas:BAABLgAECn8VAAILAAgJ3RWyYgCAAQALAAgJ3RWyYgCAAQAAAA==.Kronophyne:BAACLgAFFH8MAAIIAAUJSREJHwDdAAAIAAUJSREJHwDdAAAuAAQKfzcAAggACQn5HSA0AEgCAAgACQn5HSA0AEgCAAAA.Kronotality:BAACLgAFFH8KAAMRAAMJQxgDDQCNAAAKAAMJXQuirADHAAARAAMJQhgDDQCNAAAuAAQKf0oAAhEACQkZJWMCACoDABEACQkZJWMCACoDAAAA.Kronotek:BAAALgAECgcJDQAAAA==.Kronotekken:BAAALgADCgYJBgAAAA==.Kronotide:BAAALgAECgYJDAAAAA==.',
Ku='Kungfoosauce:BAAALgAFFAEJAQAAAA==.Kungfukittn:BAAALgAECgEJAgAAAA==.Kurohitsugî:BAAALgAECgIJBAAAAA==.',
Ky='Kylorai:BAAALgAECgYJEgAAAA==.Kynbrochel:BAAALgAECgYJEgAAAA==.',
La='Laars:BAAALgAECgUJDAABLgAECggJJQAbADsNAA==.Laimaster:BAAALgAECgEJAwAAAA==.Laizie:BAAALgAECgEJAQAAAA==.Lakiri:BAABLgAECn9EAAIaAAkJiBsZBgB6AgAaAAkJiBsZBgB6AgAAAA==.Landaeda:BAAALgAECgcJDgAAAA==.Lanney:BAAALgAECgYJBgAAAA==.Lapsu:BAABLgAECn8fAAIhAAkJjRQBHQDGAQAhAAkJjRQBHQDGAQAAAA==.Lascivia:BAACLgAFFH8TAAMXAAUJYx/eFABlAQAXAAUJYx/eFABlAQAlAAQJQBLIFwDcAAAuAAQKfyYAAxcACQkAH1AmACcCABcACQmIHFAmACcCACUACAnlEJ4eAD8BAAAA.Lawhanx:BAAALgADCgEJAQABLgAFFAQJCAATAJ0WAA==.Laylahh:BAAALgAECgMJAwAAAA==.Lazy:BAABLgAECn8WAAMbAAYJyRcpiQBHAQAbAAUJyRcpiQBHAQAHAAIJxQGEYQBLAAAAAA==.',
Le='Leademon:BAABLgAECn9BAAMNAAkJ6SBAEQC4AgANAAkJ6SBAEQC4AgAMAAIJTRrWWgB2AAAAAA==.Leadmin:BAAALgADCgMJBQABLgAECgkJQQANAOkgAA==.Leadmln:BAAALgADCgcJBwABLgAECgkJQQANAOkgAA==.Leftlane:BAABLgAECn8uAAMQAAkJsiE7BgBMAwAQAAkJsiE7BgBMAwAdAAEJgA2LqgAsAAAAAA==.Legato:BAAALgAECgkJCgABLgAFFAgJIAAQANgeAA==.Lehsham:BAAALgAECgkJAgAAAA==.Lekiri:BAAALgAECgYJCgAAAA==.Lep:BAAALgAFFAQJBAABLgAFFAgJGwAVABsYAA==.Lethalkrits:BAAALgAECgkJAgAAAA==.Leva:BAABLgAECn8hAAIFAAkJ8x3JGAB/AgAFAAkJ8x3JGAB/AgAAAA==.',
Li='Liberté:BAAALgAECgYJDAAAAA==.Liciano:BAABLgAECn8aAAMmAAkJdRygAgCRAgAmAAkJSRugAgCRAgAfAAcJPBxrGwC8AQABLgAFFAMJBQAQAKkWAA==.Licious:BAAALgAECgEJAQABLgAECgcJBwAJAAAAAA==.Lie:BAACLgAFFH8HAAIfAAIJTgvYNACOAAAfAAIJTgvYNACOAAAuAAQKfzsAAh8ACQkNGUQNAFICAB8ACQkNGUQNAFICAAAA.Lief:BAAALgAECgEJAQAAAA==.Lightsdown:BAAALgAECgYJBgAAAA==.Lilbeebs:BAAALgAECgkJEQAAAA==.Lileth:BAAALgAECgkJAgAAAA==.Lilflea:BAAALgAECggJEQAAAA==.Lilzuki:BAABLgAECn8cAAIHAAkJEgxNDgBXAQAHAAkJEgxNDgBXAQAAAA==.Lilïth:BAACLgAFFH8RAAIRAAYJxx7GEQBtAQARAAYJxx7GEQBtAQAuAAQKfyAAAhEABwmDJPIGAMICABEABwmDJPIGAMICAAAA.Linguine:BAAALgAECgEJBAABLgAFFAYJGgABAKgWAA==.Lisalisa:BAABLgAECn89AAIQAAkJwxfGIQBEAgAQAAkJwxfGIQBEAgAAAA==.Livan:BAAALgAECgMJAwAAAA==.Livia:BAAALgAECgEJAQAAAA==.',
Lo='Lohzak:BAAALgAECgEJAQAAAA==.Lotioned:BAAALgADCgEJAQAAAA==.Lousier:BAAALgAECgEJAQAAAA==.',
Lu='Lukethywalkr:BAAALgADCgYJBgAAAA==.Lularia:BAAALgADCgIJAgAAAA==.Lumii:BAAALgAECgYJBgABLgAECgYJFAAEAEUkAA==.Luminari:BAAALgADCgEJAQABLgAECgkJNgAIAGIeAA==.Lunaa:BAAALgAECgkJDAAAAA==.Lurassa:BAAALgAECgYJDAABLgAECggJDwAJAAAAAA==.',
Ly='Lyacon:BAAALgADCgQJBAABLgAECgkJFQAIAEEcAA==.',
['Lä']='Lä:BAEALgAECgcJBwABLgAFFAIJAwAJAAAAAA==.',
Ma='Madrie:BAAALgAECgQJBAAAAA==.Maekar:BAABLgAECn8kAAIWAAYJwhA3DwAXAQAWAAYJwhA3DwAXAQAAAA==.Maellus:BAAALgAECgEJAQAAAA==.Maelstorm:BAAALgADCgIJAgAAAA==.Mageman:BAAALgADCgYJAgAAAA==.Magickdragon:BAAALgAECgYJBwABLgAECgkJLgACABoYAA==.Magicmoo:BAAALgAECgEJAQABLgAFFAQJCwATAF4aAA==.Maltis:BAAALgADCgcJCwAAAA==.Mananstuff:BAACLgAFFH8FAAIcAAMJqQRnOgCPAAAcAAMJqQRnOgCPAAAuAAQKf0QAAhwACQmIEZEfAMsBABwACQmIEZEfAMsBAAAA.Manaproblems:BAAALgADCgMJBAAAAA==.Mandemic:BAAALgAECgYJCQABLgAFFAUJFwAXABEbAA==.Marguerek:BAAALgADCgEJAQAAAA==.Marinara:BAAALgAECggJDwAAAA==.Marisatomei:BAAALgAECgYJCQAAAA==.Markamanimal:BAACLgAFFH8PAAIZAAQJjBpbBgBIAQAZAAQJjBpbBgBIAQAuAAQKfyUAAhkACAnfIYYDAPwCABkACAnfIYYDAPwCAAAA.Marnix:BAABLgAECn8bAAIdAAgJmRIwLwCEAQAdAAgJmRIwLwCEAQAAAA==.Marshail:BAAALgAECgEJAQAAAA==.',
Md='Mdbeef:BAAALgAECgUJBQAAAA==.',
Me='Medikus:BAABLgAECn8pAAMQAAgJYR6ZAgDNAQAQAAgJYR6ZAgDNAQAdAAMJ2gwoegCAAAAAAA==.Meesoomagi:BAAALgAECgYJBwAAAA==.Megajoo:BAACLgAFFH8IAAMcAAIJuQzZPwB1AAAcAAIJuQzZPwB1AAAFAAIJSwQ1aQBJAAAuAAQKfxUAAxwACAnYFRIeANgBABwACAnYFRIeANgBAAUABgnlBwh7AMYAAAAA.Menil:BAABLgAECn8XAAMEAAgJwBtXFgAQAgAEAAcJJhpXFgAQAgAhAAQJchYeUQDDAAAAAA==.Merryl:BAAALgAECggJDgAAAA==.Meyounow:BAAALgAECgEJBQAAAA==.',
Mi='Midnye:BAAALgADCgYJBgAAAA==.Mike:BAECLgAFFH8GAAMnAAQJqhGfBACdAAAnAAIJzBmfBACdAAAIAAIJiAllpQCGAAAuAAQKfzoAAycACQmDJK0AAP0CACcACQlAIq0AAP0CAAgACAlkIFdWANoBAAAA.Mips:BAAALgAFFAMJBAABLgAFFAQJBwAIAFwSAA==.',
Mk='Mk:BAEALgADCgcJBwABLgAECgkJTQAhAIoiAA==.',
Mo='Mob:BAAALgADCgcJBwAAAA==.Mockra:BAABLgAECn8+AAMIAAkJViIgFADhAgAIAAkJViIgFADhAgAgAAIJuBiqGgBCAAAAAA==.Monafae:BAAALgADCgUJBQAAAA==.Moohammered:BAABLgAECn8bAAITAAkJZhlbAgAaAgATAAkJZhlbAgAaAgAAAA==.Moolou:BAACLgAFFH8TAAIUAAUJ3RrrBAA+AQAUAAUJ3RrrBAA+AQAuAAQKfyMAAhQACQm1H1AGAIICABQACQm1H1AGAIICAAAA.Moonraka:BAAALgADCgUJBQAAAA==.Moosé:BAAALgAECgEJAQABLgAFFAgJLgATAPkXAA==.Mootilater:BAAALgADCgQJAQAAAA==.Mootilator:BAAALgADCgYJBgAAAA==.Moraei:BAAALgADCgEJAQAAAA==.Mordew:BAAALgADCgUJBQABLgAECgkJPAAKAJclAA==.Morechie:BAABLgAECn8nAAIoAAkJ/BfTBwDwAQAoAAkJ/BfTBwDwAQAAAA==.Morecowbell:BAAALgAECgEJAQAAAA==.Morgatho:BAAALgADCgEJAwAAAA==.Mortiferon:BAABLgAECn83AAIKAAkJCh8TFgDDAgAKAAkJCh8TFgDDAgAAAA==.',
Mu='Muhgunguh:BAAALgAECgEJAQAAAA==.Munnky:BAABLgAECn8+AAIEAAgJoyS0AACxAgAEAAgJoyS0AACxAgAAAA==.Murmaider:BAAALgADCgIJAgAAAA==.',
My='Mythrandere:BAAALgAECgEJAQAAAA==.Mytu:BAAALgADCgUJBgAAAA==.',
['Má']='Mánflu:BAACLgAFFH8XAAIXAAUJERspGABTAQAXAAUJERspGABTAQAuAAQKfysAAyQACQniHhIDAOICACQACQniHhIDAOICABcABwlJGlI0ANkBAAAA.',
['Mô']='Môrrigãn:BAAALgADCgMJAwAAAA==.',
['Mö']='Mörgänä:BAAALgADCgMJAwAAAA==.',
Na='Naissa:BAAALgAECgQJCwAAAA==.Nakanir:BAAALgAECgYJBgAAAA==.Nalfeign:BAAALgAECgQJBQAAAA==.Napa:BAAALgAECgUJCgABLgAFFAYJFwAQAKMXAA==.Narn:BAABLgAECn9DAAQPAAkJOBybFAA3AgAWAAcJrRjRCQBCAgAPAAkJ5RibFAA3AgAVAAIJLQiEQQBgAAAAAA==.',
Ne='Nealite:BAAALgAECgkJBgAAAA==.Necrophyllis:BAAALgAECgMJAwAAAA==.Necrotion:BAAALgAECgYJEgAAAA==.Nei:BAAALgAECgEJAQABLgAECgkJIAAeAI0SAA==.Nerrisa:BAABLgAECn8iAAICAAkJERQtIgC2AQACAAkJERQtIgC2AQAAAA==.Nertmage:BAAALgADCgUJBQABLgAECgkJQwAVADEZAA==.Nertt:BAAALgADCgYJBgABLgAECgkJQwAVADEZAA==.Neublood:BAAALgAECgQJCAAAAA==.',
Ni='Nicodemus:BAAALgAECgcJEQAAAA==.Nimrods:BAAALgAECgQJBAAAAA==.',
No='Noblewarrior:BAACLgAFFH8iAAIXAAgJOhtDAwBVAgAXAAgJOhtDAwBVAgAuAAQKfysAAhcACAmuJHYNAJcCABcACAmuJHYNAJcCAAAA.Noctilus:BAAALgAECgcJCQAAAA==.Nohkari:BAAALgADCgkJHQABLgAECgkJKgAbAPAXAA==.Nooj:BAACLgAFFH84AAMGAAgJmSMmAADoAgAGAAgJmSMmAADoAgAfAAYJiRRDFABqAQAuAAQKfx4AAwYACQl7ITsAAMMDAAYACQl7ITsAAMMDAB8ABgmFEpA6AEQBAAAA.Notakoala:BAACLgAFFH8jAAIcAAgJIhUGDQDMAQAcAAgJIhUGDQDMAQAuAAQKfycAAxwACAlHJFQNAMUCABwACAlHJFQNAMUCABgAAQk3EjJzADQAAAAA.Nothnx:BAAALgAFFAEJAwAAAA==.Notoriouspat:BAABLgAECn8jAAILAAgJFA/+YACFAQALAAgJFA/+YACFAQAAAA==.Notsamadeath:BAABLgAFFH8LAAQiAAUJWRFdDwAeAQAiAAQJWRFdDwAeAQAKAAIJ3wi26wB+AAARAAEJAAB0TwAAAAAAAA==.Notsifra:BAAALgAECgYJDQABLgAFFAQJDAAEAJglAA==.Novia:BAAALgAECgYJBgAAAA==.Noyber:BAAALgAFFAIJAgAAAA==.Noydin:BAAALgAFFAIJAwAAAA==.Noythrax:BAAALgAFFAMJAwAAAA==.',
['Ní']='Nínebreaker:BAAALgAECgkJEAAAAA==.',
['Nü']='Nüll:BAABLgAECn8UAAINAAgJ2AsBdwAzAQANAAgJ2AsBdwAzAQAAAA==.',
Ob='Obern:BAABLgAECn8WAAIOAAkJZhsgFgDxAQAOAAkJZhsgFgDxAQAAAA==.Obiron:BAAALgAECgEJAQAAAA==.Oblïna:BAABLgAECn8zAAIEAAkJlwqmSwA+AQAEAAkJlwqmSwA+AQAAAA==.',
Od='Odiumaeterna:BAAALgADCgcJBwAAAA==.',
Of='Offensivé:BAAALgAECgMJCAAAAA==.Oftheages:BAAALgAFFAEJAQABLgAFFAgJGwAVABsYAA==.',
On='Onetozerosix:BAABLgAECn8jAAIKAAkJHhyQPQAMAgAKAAkJHhyQPQAMAgAAAA==.Onos:BAAALgAECgEJAQAAAA==.Onsen:BAAALgAECgQJBgAAAA==.',
Oo='Oogak:BAAALgAECgUJBgAAAA==.Oomigig:BAAALgADCgUJBQAAAA==.',
Op='Opalily:BAAALgAECgEJAQAAAA==.Operation:BAAALgAECgQJCAAAAA==.Oprahwndfury:BAAALgADCgIJAgAAAA==.',
Or='Oresties:BAAALgAECgYJCAAAAA==.Orestisies:BAAALgAECgcJCQAAAA==.Orghrax:BAAALgADCgEJAQAAAA==.Orisys:BAAALgAECgIJAwAAAA==.',
Os='Osteer:BAAALgAECgYJBgAAAA==.',
Ot='Otterjim:BAAALgADCgQJBAAAAA==.',
Pa='Padfoote:BAAALgAECgEJAQAAAA==.Pahaa:BAAALgAECgUJBQAAAA==.Pairadeez:BAAALgAECgYJDwAAAA==.Pajamabanana:BAAALgADCgIJAgAAAA==.Pandablaze:BAAALgAFFAEJAgAAAA==.Panterarey:BAAALgADCgYJEAAAAA==.Papalego:BAABLgAECn8yAAILAAkJlg43RwDMAQALAAkJlg43RwDMAQAAAA==.Parakka:BAABLgAECn82AAIQAAkJGhZ8IQBGAgAQAAkJGhZ8IQBGAgAAAA==.Patak:BAAALgAECgMJAwAAAA==.Pavle:BAAALgAECgMJAwAAAA==.Pawp:BAAALgAECgYJCgABLgAFFAQJBgABAHoHAA==.',
Pe='Pearagon:BAABLgAECn8VAAICAAgJwBEJJwCVAQACAAgJwBEJJwCVAQABLgAFFAYJFwAQAKMXAA==.Pepsidew:BAAALgADCgcJDAAAAA==.Pepsisprite:BAABLgAECn86AAIBAAkJdhqqDACcAgABAAkJdhqqDACcAgAAAA==.Pesky:BAABLgAECn8jAAIcAAYJJBazNQBAAQAcAAYJJBazNQBAAQABLgAFFAQJDwAIAGERAA==.',
Pf='Pfchanguz:BAAALgADCgcJDAAAAA==.',
Ph='Phdbeef:BAABLgAFFH8HAAIYAAIJ+xtkHwCgAAAYAAIJ+xtkHwCgAAABLgAFFAYJEQARAMceAA==.Phlemm:BAAALgAECgEJAQAAAA==.Phoivos:BAABLgAECn8VAAIIAAkJQRwKIQDvAgAIAAkJQRwKIQDvAgAAAA==.',
Pi='Picklez:BAABLgAECn87AAIKAAkJuyIYCgAeAwAKAAkJuyIYCgAeAwAAAA==.Pissflizzle:BAABLgAECn8dAAIbAAgJ9w0kagBoAQAbAAgJ9w0kagBoAQAAAA==.',
Pl='Plaquenil:BAAALgADCgEJAQAAAA==.',
Po='Poison:BAAALgADCgEJAQAAAA==.Porkroaster:BAABLgAECn8pAAIIAAgJuAwChgBrAQAIAAgJuAwChgBrAQAAAA==.Portwings:BAAALgADCgYJBgAAAA==.',
Pr='Praye:BAAALgAFFAMJAwAAAA==.Priestop:BAAALgAECgEJAQAAAA==.Professahoak:BAAALgAECgUJBQABLgAECgkJPgAIAFYiAA==.',
Ps='Psyfarian:BAAALgADCgcJDQAAAA==.Psyop:BAAALgAECgYJCAABLgAECggJIQABABkfAA==.Psyrax:BAAALgADCgUJCAAAAA==.',
Pu='Pushemover:BAAALgAECgMJBgAAAA==.',
Qu='Quelyndlina:BAAALgAECgEJAQAAAA==.Quillswitch:BAAALgAECgEJAQAAAA==.',
Ra='Radduc:BAABLgAECn8ZAAMSAAYJKxjcNgBzAQASAAYJKxjcNgBzAQATAAEJlQY0sgEpAAAAAA==.Ragerade:BAAALgAECgYJBwAAAA==.Raidu:BAAALgAECgMJAwAAAA==.Ralpherion:BAAALgADCgIJAgAAAA==.Ranoa:BAAALgAECgQJDQAAAA==.Raphåel:BAAALgAFFAEJAQAAAA==.Ravioli:BAAALgAECgQJBgAAAA==.Razialum:BAAALgADCgYJBgAAAA==.Razorsteps:BAABLgAFFH8FAAMHAAQJWAGhFwByAAAHAAQJoAChFwByAAAoAAEJDAOyDABBAAAAAA==.Razzberry:BAAALgADCgYJDAAAAA==.',
Re='Rebrowth:BAAALgAECgcJEgAAAA==.Redren:BAAALgADCgIJAgAAAA==.Reegrets:BAAALgAECggJDQAAAA==.Reena:BAAALgADCgIJAwAAAA==.Regeth:BAAALgAECgkJDgAAAA==.Regiplague:BAAALgAECgYJCwAAAA==.Regretty:BAAALgAECggJDQABLgAECggJDQAJAAAAAA==.Renthar:BAAALgADCgUJBQAAAA==.Renzdingo:BAAALgAECgkJDwAAAA==.Repete:BAAALgAECgUJDgAAAA==.Resyek:BAABLgAECn85AAIIAAgJOyQVHACzAgAIAAgJOyQVHACzAgAAAA==.Reverendgank:BAAALgAECgEJAQAAAA==.',
Rh='Rhaxanna:BAAALgADCgYJBgAAAA==.',
Ri='Rick:BAAALgAFFAMJAwAAAA==.Rickheaddk:BAAALgADCgEJAgAAAA==.Riivan:BAABLgAECn8uAAIbAAkJZRQ8NQAEAgAbAAkJZRQ8NQAEAgAAAA==.Rini:BAAALgAECgkJEQABLgABCgYJCwAJAAAAAA==.Rivian:BAAALgADCgIJAgABLgAECgEJAgAJAAAAAA==.',
Ro='Robot:BAABLgAECn8oAAIEAAgJUBGqPQB5AQAEAAgJUBGqPQB5AQAAAA==.Roguè:BAAALgAECgEJAQABLgAFFAEJAQAJAAAAAA==.Rokmog:BAAALgAECggJEQAAAA==.Rollinburn:BAAALgADCgYJCQAAAA==.Romanoff:BAAALgAECgEJAQABLgAECgkJIAAeAI0SAA==.Roxanol:BAAALgADCgEJAQABLgAECgkJPQASACUaAA==.',
Ru='Rumbrave:BAAALgAECgYJCwAAAA==.Rumtumtugger:BAAALgADCgkJCQAAAA==.',
Rx='Rxqüeen:BAAALgAECgEJAQAAAA==.',
['Rá']='Ráyune:BAAALgADCgcJBwAAAA==.',
Sa='Sackos:BAAALgAECgEJAgAAAA==.Sadpanda:BAAALgADCgUJCAAAAA==.Saffronspark:BAAALgADCgkJHwABLgAECgkJTgAhAMMiAA==.Sainsei:BAABLgAECn8gAAMeAAcJqgXVUQC7AAAeAAcJFQPVUQC7AAAhAAUJBAcdZQCNAAAAAA==.Saith:BAAALgAECgEJBgAAAA==.Samasear:BAABLgAECn8UAAIXAAgJ0w8wMgDjAQAXAAgJ0w8wMgDjAQABLgAFFAgJIQAiANMeAA==.Sandwitch:BAABLgAECn9DAAMbAAkJLRjBLwAZAgAbAAkJLRjBLwAZAgAHAAIJmxB0UwB0AAAAAA==.Sanoa:BAABLgAFFH8JAAIaAAQJywTzDQDfAAAaAAQJywTzDQDfAAAAAA==.Sargatana:BAABLgAECn9CAAIeAAkJ7iB/BAD9AgAeAAkJ7iB/BAD9AgAAAA==.Sars:BAABLgAECn82AAMEAAkJlSQ6BQBXAwAEAAkJlSQ6BQBXAwAhAAMJGhO3XwCbAAAAAA==.Sauronxd:BAAALgAECgUJCAAAAA==.',
Sc='Scalion:BAABLgAECn8nAAMNAAgJOR7tJAA6AgANAAgJOR7tJAA6AgAMAAQJ+BG9SwDAAAABLgAFFAQJCAATAJ0WAA==.Scarne:BAAALgAECgIJAgAAAA==.Schrodinger:BAABLgAECn8gAAIUAAgJuAp9IAAQAQAUAAgJuAp9IAAQAQAAAA==.Scravenhoof:BAAALgAECgYJBgAAAA==.',
Se='Seira:BAAALgAECgEJAwABLgAECgkJSgADAFMfAA==.Selunee:BAAALgADCgEJAQAAAA==.Sepharad:BAAALgADCggJEgAAAA==.Septicflësh:BAAALgAECgkJAQAAAA==.Severum:BAABLgAECn8+AAIlAAkJYh0YBwCVAgAlAAkJYh0YBwCVAgAAAA==.Seyrah:BAAALgAECgkJAgAAAA==.',
Sh='Shabang:BAAALgAFFAEJAQAAAA==.Shadowtiger:BAABLgAECn8wAAILAAkJag3tTgC1AQALAAkJag3tTgC1AQAAAA==.Shadrad:BAACLgAFFH8MAAITAAUJsSFNIQCCAQATAAUJsSFNIQCCAQAuAAQKfxsAAhMACQnFJd0IACMDABMACQnFJd0IACMDAAAA.Shamanor:BAAALgAECgcJCAAAAA==.Shammoo:BAAALgAECgIJBAABLgAFFAgJLgATAPkXAA==.Shantz:BAABLgAECn8sAAIRAAgJVxRfHAB3AQARAAgJVxRfHAB3AQAAAA==.Shiban:BAABLgAECn8YAAIOAAkJIxCjEwAJAgAOAAkJIxCjEwAJAgAAAA==.Shirtless:BAAALgAECggJEQAAAA==.Shockra:BAABLgAECn8dAAIdAAkJ4xedIwDJAQAdAAkJ4xedIwDJAQAAAA==.Shokalypse:BAAALgADCgEJAQAAAA==.Shortbuss:BAAALgADCgYJEgAAAA==.',
Si='Sige:BAAALgADCgYJBgAAAA==.Sillygoose:BAAALgADCgkJDwAAAA==.Silverfox:BAAALgADCgMJAQABLgAECgkJPgAIAFYiAA==.Silx:BAABLgAECn8VAAMDAAcJMBE8IQCJAQADAAcJMBE8IQCJAQACAAEJoBZEXQA/AAAAAA==.Simvastatin:BAAALgADCgQJBAAAAA==.Sinterdeath:BAAALgAECgIJAgAAAA==.Sithiry:BAAALgAECgEJAQAAAA==.',
Sk='Skik:BAAALgAECgcJBwAAAA==.Skulltide:BAAALgADCgcJCQAAAA==.',
Sl='Slaggz:BAAALgADCgQJBAAAAA==.Slamvoke:BAAALgAECgYJBgABLgAFFAUJFAAXAD8WAA==.Slaté:BAAALgAECgEJAgABLgAECgMJBQAJAAAAAA==.Slowrot:BAAALgAECgQJBQABLgAFFAQJCwATAF4aAA==.Slushpuppy:BAAALgAFFAEJAQAAAA==.Slâte:BAAALgAFFAEJAgAAAA==.',
Sm='Smiteasaurus:BAAALgAECgEJAQAAAA==.Smokkie:BAABLgAFFH8IAAITAAQJnRY9PwAsAQATAAQJnRY9PwAsAQAAAA==.Smorthian:BAAALgAECgcJDQAAAA==.',
Sn='Snarll:BAAALgADCgEJAQAAAA==.Sniffinsteak:BAABLgAECn8bAAMhAAkJGiG9BgDeAgAhAAkJGiG9BgDeAgAEAAEJtws1xgAlAAAAAA==.',
So='Solas:BAAALgADCgYJBgAAAA==.Somaliabiggs:BAAALgAECgYJCgAAAA==.Sonar:BAAALgADCgYJBgABLgAECgkJPAAKAJclAA==.Sonuvabitxh:BAAALgADCgQJBAAAAA==.Sorraba:BAABLgAFFH8KAAIIAAQJUgKVjgC7AAAIAAQJUgKVjgC7AAABLgAFFAUJEgADAOgQAA==.Sorrabo:BAACLgAFFH8SAAIDAAUJ6BDTJQAdAQADAAUJ6BDTJQAdAQAuAAQKfyIABAMACQn3Gd4LALECAAMACQn3Gd4LALECAAEAAwm7A8JlAEsAAAIAAQkpA2yYACEAAAAA.Sorraug:BAAALgAFFAMJAwABLgAFFAUJEgADAOgQAA==.Soryan:BAACLgAFFH8IAAITAAQJWALmegDAAAATAAQJWALmegDAAAAuAAQKfxoAAhMACAk4B9OVAFEBABMACAk4B9OVAFEBAAAA.Sosalkin:BAAALgAECgcJEQAAAA==.Souls:BAACLgAFFH8VAAIbAAUJ8B2/OwBdAQAbAAUJ8B2/OwBdAQAuAAQKfx4ABBsABwnhIyYXAMkCABsABwnhIyYXAMkCACgAAQkAAPIfAHIAAAcAAQm1GkhiAEoAAAAA.',
Sp='Spankenstine:BAABLgAECn8lAAMTAAkJTRgKRgD0AQATAAkJTRgKRgD0AQASAAUJowh+YwDuAAABLgABCgYJCwAJAAAAAA==.Spannky:BAAALgAECgcJEgABLgAECggJPgAEAKMkAA==.',
Sq='Squeaks:BAAALgAECgkJAQAAAA==.Squishÿ:BAAALgAECgYJDwAAAA==.',
St='Starshriek:BAAALgADCgcJBwAAAA==.Stinkydeathy:BAAALgAECgMJBAABLgAECgYJHQAeAMwYAA==.Stinkyfree:BAABLgAECn8dAAMeAAYJzBjSLgCcAQAeAAYJzBjSLgCcAQAhAAEJQRObDQA9AAAAAA==.Stinkynatto:BAAALgADCgYJBgABLgAECgYJHQAeAMwYAA==.Stormcharred:BAABLgAECn8eAAIIAAgJ6SCgKADQAgAIAAgJ6SCgKADQAgAAAA==.Stormknight:BAAALgAECgUJEAAAAA==.Stormpoo:BAAALgAECgEJAQAAAA==.Straka:BAABLgAECn8fAAIFAAkJERIZPgCrAQAFAAkJERIZPgCrAQAAAA==.',
Su='Suffers:BAAALgAECgEJAQAAAA==.Sultanae:BAAALgAECgQJBAAAAA==.Sunbearr:BAAALgAECgEJAgAAAA==.Suneater:BAAALgAECgEJAgAAAA==.Sunmane:BAAALgAECgEJAwABLgAECgkJKgAZAHMXAA==.Supaheals:BAAALgAECgEJAQAAAA==.Superdk:BAABLgAFFH8IAAIiAAQJkhb8CwA7AQAiAAQJkhb8CwA7AQABLgAFFAgJFQATAOIaAA==.Superdruid:BAAALgADCgUJBQABLgAFFAgJFQATAOIaAA==.Supermonks:BAAALgAECggJDAABLgAFFAgJFQATAOIaAA==.Superpi:BAABLgAECn8aAAIDAAcJFx5uEwBFAgADAAcJFx5uEwBFAgABLgAFFAgJFQATAOIaAA==.Superret:BAACLgAFFH8VAAITAAgJ4hrtEADnAQATAAgJ4hrtEADnAQAuAAQKfycAAxMACQkGI/gOABYDABMACQkGI/gOABYDABIAAQn7FAWIADsAAAAA.Superskeet:BAACLgAFFH8HAAISAAMJtAsSNgCWAAASAAMJtAsSNgCWAAAuAAQKfyUAAhIACAl3F54iAPABABIACAl3F54iAPABAAAA.Superwar:BAAALgAECgkJCQABLgAFFAgJFQATAOIaAA==.',
Sv='Svetllama:BAAALgADCggJCAAAAA==.',
Sw='Swaggbag:BAAALgADCgEJAQAAAA==.Swiftia:BAABLgAECn8VAAMjAAYJlBZYOwBzAQAjAAYJjhRYOwBzAQALAAUJAg0MxQC9AAAAAA==.Swiftybutt:BAAALgAECggJCgAAAA==.',
Sy='Sylphièl:BAACLgAFFH8VAAMGAAUJDgdfBgALAQAGAAUJDgdfBgALAQAmAAEJqQKSEwAsAAAuAAQKfygAAwYACAkwDoQLAHgBACYACAmbCq8EALkBAAYACAlDDYQLAHgBAAAA.Syncere:BAAALgAFFAIJAgAAAA==.Synhunt:BAAALgAFFAEJAgAAAA==.Syrene:BAAALgAECgMJBgAAAA==.',
Ta='Tandarì:BAACLgAFFH8ZAAITAAUJWB/aMABQAQATAAUJWB/aMABQAQAuAAQKfyIAAhMACQmjHqoPABEDABMACQmjHqoPABEDAAAA.Tano:BAAALgAECgUJCQABLgAECgkJPgAIAFYiAA==.Tanparo:BAAALgAECgMJAwAAAA==.Tarick:BAAALgAECgYJCAAAAA==.Tasty:BAAALgAECgQJCwAAAA==.Tawnii:BAAALgADCgcJEgAAAA==.Tazath:BAAALgAECgEJAwAAAA==.Taírn:BAABLgAECn8XAAQPAAYJAwz/BgCHAAAWAAYJpAaCGQCIAAAPAAUJLg3/BgCHAAAVAAEJpwRvQwAgAAAAAA==.',
Te='Tehpredator:BAAALgAFFAMJAwABLgAFFAUJEgADAOgQAA==.Teilin:BAACLgAFFH8gAAIQAAgJ2B4uAwCrAgAQAAgJ2B4uAwCrAgAuAAQKfyIAAhAACQmQI7MEACcDABAACQmQI7MEACcDAAAA.Tenderloin:BAAALgAECgkJDwAAAA==.Teralynn:BAAALgAECgEJAgAAAA==.Terryisgreat:BAAALgAECgEJAQABLgAECgcJFgASAPETAA==.',
Th='Thalendor:BAAALgAECgIJAgAAAA==.Theaterthug:BAAALgAECgIJAgAAAA==.Thehulkster:BAAALgAECgMJAwAAAA==.Thetinman:BAAALgAECgEJAQAAAA==.Thevelo:BAAALgAECgIJAgABLgAECgcJFgAOAM4TAA==.Thewhole:BAAALgAFFAMJAQAAAA==.Theßigshot:BAABLgAECn8VAAIFAAYJICPAIgAyAgAFAAYJICPAIgAyAgABLgAFFAEJAQAJAAAAAA==.Thoseheals:BAAALgADCgQJBAAAAA==.Thunderskeet:BAACLgAFFH8KAAINAAMJARlyXQDXAAANAAMJARlyXQDXAAAuAAQKfzwAAw0ACQkFJfQDAEcDAA0ACQkFJfQDAEcDAAwABwlYHRAUADICAAAA.Thundurus:BAACLgAFFH8QAAIdAAYJpxBBJwD5AAAdAAYJpxBBJwD5AAAuAAQKfyUAAh0ACAm9Fmc3AFsBAB0ACAm9Fmc3AFsBAAAA.',
Ti='Timmayy:BAABLgAECn8kAAIbAAgJCBZ5OQAmAgAbAAgJCBZ5OQAmAgAAAA==.Tindrill:BAABLgAECn8yAAIkAAkJfSXYAABzAwAkAAkJfSXYAABzAwAAAA==.Tireiron:BAAALgADCgYJBgAAAA==.',
To='Tomraedisk:BAACLgAFFH8FAAIXAAQJegfjKwAEAQAXAAQJegfjKwAEAQAuAAQKfxkAAhcACQmJG8MWADgCABcACQmJG8MWADgCAAAA.Totemagoat:BAACLgAFFH8jAAMQAAgJyBXrBACMAQAQAAgJyBXrBACMAQAdAAUJ+hCKJwD3AAAuAAQKfzQAAx0ACQkJHdUYABwCAB0ACAnQG9UYABwCABAACQmqFNgsANcBAAAA.Totemlyfine:BAABLgAECn82AAMQAAkJUCEpEADQAgAQAAkJUCEpEADQAgAdAAQJMBUkYQDCAAAAAA==.Totesmugoats:BAAALgAECggJEgAAAA==.Toxicshock:BAAALgADCgEJAQAAAA==.',
Tr='Traprkeepr:BAAALgADCgcJEgAAAA==.Treechains:BAABLgAECn8WAAMQAAYJ8hcGUAByAQAQAAYJ8hcGUAByAQAdAAEJZQPtkQAlAAAAAA==.Treefist:BAAALgAFFAEJAgAAAA==.Treeshield:BAAALgADCgYJBgAAAA==.Trickster:BAAALgAECgEJAgAAAA==.Triplex:BAAALgAECgQJBAAAAA==.Truth:BAAALgADCgcJDQAAAA==.',
Ts='Tsumuji:BAAALgAECgEJAQAAAA==.',
Tu='Turbobis:BAAALgAECgIJAgAAAA==.',
Tw='Twentyfour:BAACLgAFFH8MAAIFAAMJJgVvTgCGAAAFAAMJJgVvTgCGAAAuAAQKfxUAAgUABwmGEOVdADgBAAUABwmGEOVdADgBAAAA.Twigberry:BAAALgAECgUJCAAAAA==.',
Ty='Tygra:BAAALgAECgcJDgAAAA==.Typeshxxt:BAAALgADCgEJAQAAAA==.Tytanea:BAAALgAECgMJBAAAAA==.',
['Tø']='Tøga:BAAALgADCgMJAQAAAA==.Tøqa:BAAALgAFFAEJAQAAAA==.',
Uh='Uhnderstood:BAABLgAECn8mAAIEAAkJjh1qEABUAgAEAAkJjh1qEABUAgAAAA==.',
Un='Undeadmonks:BAACLgAFFH8OAAIeAAMJSBcdNADXAAAeAAMJSBcdNADXAAAuAAQKf0kAAx4ACQliHqgHALsCAB4ACQliHqgHALsCACEAAwl2CsRlAHYAAAAA.',
Uv='Uvaweez:BAAALgAECgMJAwAAAA==.',
Va='Vahe:BAAALgAECgEJAQAAAA==.Vale:BAAALgAECgUJBgAAAA==.Valeshot:BAACLgAFFH8FAAILAAMJwAHzfQCcAAALAAMJwAHzfQCcAAAuAAQKfycAAgsACQnUCm4/ALEBAAsACQnUCm4/ALEBAAAA.Valkillrie:BAAALgADCgcJBwAAAA==.Valkyrié:BAAALgAECgIJAwAAAA==.Vall:BAAALgAECggJDAAAAA==.Valssra:BAABLgAECn8XAAIIAAcJmAoRsAAhAQAIAAcJmAoRsAAhAQAAAA==.Vampiricvrus:BAAALgAECgQJBgAAAA==.Vashi:BAABLgAECn86AAITAAkJQxb6UgDQAQATAAkJQxb6UgDQAQAAAA==.',
Ve='Vedbow:BAACLgAFFH8UAAQOAAQJmiNdDQBaAQAOAAQJ0iFdDQBaAQALAAMJMBUeZgDZAAAjAAEJgA+6JwBNAAAuAAQKfxwABAsACQnIIh4UAJUCAAsACAm5IR4UAJUCACMABAnyHyc8AG4BAA4AAwldIPo1AAUBAAAA.Vedronas:BAABLgAECn8XAAITAAcJaiOcHgC0AgATAAcJaiOcHgC0AgAAAA==.Velara:BAAALgADCgUJBQAAAA==.Velillys:BAAALgAECgEJAQAAAA==.Venlii:BAAALgADCgEJAQAAAA==.Veos:BAAALgAECgEJAQAAAA==.Verdict:BAABLgAECn8WAAIQAAgJYxEEPQC6AQAQAAgJYxEEPQC6AQAAAA==.Veritae:BAAALgAECgcJCQAAAA==.Vern:BAABLgAECn8YAAMDAAgJ+BdlJQCkAQADAAgJ+BdlJQCkAQACAAIJgwYoWQBWAAAAAA==.Vernaar:BAAALgAECgMJAwABLgAECggJGAADAPgXAA==.Vernah:BAABLgAECn8VAAISAAgJ1Rk4GABGAgASAAgJ1Rk4GABGAgABLgAECggJGAADAPgXAA==.Verybad:BAABLgAECn9EAAIIAAYJpRwgewDbAQAIAAYJpRwgewDbAQAAAA==.',
Vo='Voidify:BAAALgADCgEJAgAAAA==.Voodoodrood:BAAALgADCgIJAgAAAA==.',
['Vè']='Vèronique:BAAALgAECgYJBgAAAA==.',
Wa='Waambler:BAAALgAECgIJAgAAAA==.Waamchifu:BAABLgAECn85AAIeAAkJhyN4AgA2AwAeAAkJhyN4AgA2AwAAAA==.Wack:BAAALgADCgUJBgAAAA==.Waka:BAAALgADCgcJCwAAAA==.Waltersight:BAACLgAFFH8MAAILAAQJ1w/MFwDkAAALAAQJ1w/MFwDkAAAuAAQKfxcAAgsACQlvFz0pADkCAAsACQlvFz0pADkCAAAA.Warsheep:BAAALgADCgQJAQAAAA==.',
We='Wednesdayy:BAAALgAECgEJAQAAAA==.Wesker:BAAALgADCgYJBgAAAA==.Westavia:BAAALgAECgEJAQABLgAFFAQJCwATAF4aAA==.Wewabear:BAAALgADCgQJBAAAAA==.',
Wh='Whateley:BAAALgAECgcJCgAAAA==.Whoforted:BAAALgAECgQJBAAAAA==.Whosthetänk:BAAALgAECgEJAQAAAA==.',
Wi='Wisebrownguy:BAABLgAECn8tAAITAAkJHR9rFQDCAgATAAkJHR9rFQDCAgABLgAFFAQJBQAXAHoHAA==.Wisperia:BAAALgADCgYJBgAAAA==.',
Wo='Worgana:BAAALgAECgMJAwAAAA==.Wormchild:BAAALgADCgQJBAAAAA==.',
Wu='Wukòng:BAAALgADCgEJAQAAAA==.',
Xe='Xercuul:BAAALgAECgcJEQAAAA==.',
Xi='Xikar:BAAALgAECgQJCAAAAA==.',
Xp='Xplosiv:BAABLgAECn8WAAILAAgJHSLWAwDGAQALAAgJHSLWAwDGAQABLgAFFAgJIgAQAOUcAA==.',
Xy='Xylophonejoe:BAAALgAECgYJCQAAAA==.',
Ye='Yeddy:BAAALgADCgcJBwAAAA==.Yel:BAAALgADCgYJCAAAAA==.',
Yo='Yoel:BAAALgADCgEJAQAAAA==.Yourdad:BAAALgAECgYJEAABLgAFFAEJAQAJAAAAAA==.',
Yu='Yudah:BAACLgAFFH8JAAQOAAMJuRQPIgDJAAAOAAMJDQ4PIgDJAAALAAIJzxwWgACYAAAjAAEJ3AAaPQAnAAAuAAQKfy0ABA4ACAmgHT8YAN8BAA4ACAkZGT8YAN8BACMABglUFtYTACQBAAsABwlgD1KWABMBAAAA.Yuta:BAAALgADCgcJBgAAAA==.',
Za='Zalrei:BAAALgAECgEJAQAAAA==.Zalupa:BAAALgAECgIJAgAAAA==.Zanghonghua:BAABLgAECn9OAAMhAAkJwyK7AwAkAwAhAAkJwyK7AwAkAwAEAAEJSRXWZAA+AAAAAA==.Zarinaria:BAABLgAECn8cAAINAAYJ2Q7qfQAvAQANAAYJ2Q7qfQAvAQAAAA==.',
Ze='Zetsumei:BAAALgADCgMJAwAAAA==.',
Zh='Zhael:BAABLgAECn8hAAINAAkJCRo0JwAvAgANAAkJCRo0JwAvAgAAAA==.',
Zi='Zitizen:BAAALgADCgYJBwAAAA==.',
Zo='Zodstrike:BAABLgAECn8xAAMNAAkJbwUjiwAKAQANAAkJbwUjiwAKAQAMAAQJnwIXWACGAAAAAA==.Zomara:BAAALgAECgMJCgAAAA==.Zooboo:BAABLgAECn8XAAIXAAkJURcjJgDHAQAXAAkJURcjJgDHAQAAAA==.Zophie:BAAALgADCgEJAQAAAA==.',
['Är']='Ärcane:BAAALgAECgkJCwABLgAFFAEJAQAJAAAAAA==.',
['Ät']='Ätticus:BAAALgAECgYJBgABLgAFFAEJAQAJAAAAAA==.',
['Äú']='Äúra:BAAALgAECggJCQAAAA==.',
['Åi']='Åir:BAAALgADCgIJAgAAAA==.',
['Ðô']='Ðôôm:BAAALgAECgEJAQAAAA==.',
['Öv']='Överpöwered:BAAALgADCgIJAgABLgAFFAEJAQAJAAAAAA==.',
['Öð']='Öðïn:BAAALgADCgQJBAAAAA==.',
['ßl']='ßlisster:BAAALgADCgYJBgAAAA==.',
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
