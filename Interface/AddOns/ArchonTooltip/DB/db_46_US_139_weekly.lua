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

local lookup = {'Priest-Holy','Priest-Shadow','Priest-Discipline','Monk-Mistweaver','Druid-Restoration','Rogue-Assassination','Warlock-Destruction','Mage-Frost','Unknown-Unknown','DeathKnight-Unholy','Hunter-BeastMastery','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-Survival','Evoker-Augmentation','Shaman-Restoration','DeathKnight-Blood','Paladin-Holy','Paladin-Retribution','Paladin-Protection','Evoker-Preservation','Evoker-Devastation','Warrior-Fury','Druid-Guardian','Druid-Feral','Shaman-Enhancement','Druid-Balance','Shaman-Elemental','Monk-Brewmaster','Rogue-Subtlety','Mage-Arcane','Monk-Windwalker','DeathKnight-Frost','Warlock-Demonology','Hunter-Marksmanship','Warrior-Arms','Warrior-Protection','Rogue-Outlaw','Mage-Fire','Warlock-Affliction',}
local provider = {region='US',realm='LaughingSkull',name='US',type='weekly',zone=46,date='2026-06-20',data={Ab='Abeblinken:BAAALgAECgIJAgAAAA==.Ablucia:BAAALgADCgUJCQAAAA==.Abomb:BAAALgAECgEJAgAAAA==.Abotharn:BAAALgADCgUJBQAAAA==.',
Ac='Acanaline:BAAALgAECgEJAQAAAA==.Achannara:BAAALgADCgcJBwAAAA==.',
Ae='Aennisong:BAAALgAECgUJCAAAAA==.Aeoliana:BAABLgAECn8VAAIBAAgJrQhXAgC2AAABAAgJrQhXAgC2AAAAAA==.',
Aj='Ajier:BAACLgAFFH8OAAIBAAUJxBhFDgBpAQABAAUJxBhFDgBpAQAuAAQKfy0AAgEACQkpFqMWACcCAAEACQkpFqMWACcCAAAA.',
Al='Aleraz:BAACLgAFFH8aAAMBAAYJqBZIDQB2AQABAAUJkRpIDQB2AQACAAUJWhQjGQAfAQAuAAQKfz8ABAIACQn7H4kGAOkCAAIACQn7H4kGAOkCAAEABwnbIOEVAC0CAAMAAwkmBxRjAHAAAAAA.Allcapwne:BAAALgAECgcJCwAAAA==.Allenduin:BAAALgAECgYJBwAAAA==.Alshau:BAABLgAECn8aAAIEAAcJ0BdfIwCYAQAEAAcJ0BdfIwCYAQAAAA==.Alucart:BAAALgAECgEJAQAAAA==.',
Am='Ambrosia:BAAALgAECgYJDwAAAA==.Amity:BAAALgADCgkJEAABLgAECgkJIQAFAPMdAA==.',
An='Anchoredowl:BAAALgAECgEJAgAAAA==.Anewrbyss:BAAALgAECgUJEQAAAA==.Angela:BAABLgAECn9KAAMDAAkJUx/GBgASAwADAAkJUx/GBgASAwACAAEJowwwiwAvAAAAAA==.Anna:BAAALgAECgQJBQAAAA==.Annalunà:BAAALgADCgIJBAAAAA==.Annälise:BAAALgADCgEJAQAAAA==.',
Ap='Apeople:BAACLgAFFH8MAAIGAAUJhhdsBABAAQAGAAUJhhdsBABAAQAuAAQKfzAAAgYACQmGIloBACEDAAYACQmGIloBACEDAAAA.Apocalýpsè:BAAALgAECgIJAgAAAA==.Applebottomj:BAAALgAECgMJAwAAAA==.Applebottum:BAAALgAECgkJEAAAAA==.Appärition:BAABLgAECn8zAAIHAAgJqCCbAgCKAgAHAAgJqCCbAgCKAgAAAA==.',
Ar='Arleance:BAAALgAECgUJCAAAAA==.Arondael:BAABLgAECn8iAAIGAAkJ8xjhBwDVAQAGAAkJ8xjhBwDVAQAAAA==.Arsène:BAAALgADCgcJCwAAAA==.',
As='Ashelaandrii:BAAALgAFFAEJAQAAAA==.Astroglyde:BAAALgAECgcJCQAAAA==.Aszun:BAAALgADCgUJBQAAAA==.',
Au='Aurialis:BAAALgAECgcJDQAAAA==.',
Av='Avanti:BAABLgAECn9AAAIIAAkJURuiLQBjAgAIAAkJURuiLQBjAgAAAA==.Avendeloria:BAABLgAECn8aAAIBAAcJFBbCHgDPAQABAAcJFBbCHgDPAQAAAA==.Averyn:BAAALgADCgEJAQAAAA==.',
Az='Azrahn:BAAALgADCgQJBQAAAA==.',
['Aü']='Aüra:BAAALgAECgEJAQABLgAECggJCQAJAAAAAA==.',
Ba='Babybear:BAAALgAECgIJAgAAAA==.Backmoist:BAAALgAECgQJBwAAAA==.Bagmaster:BAACLgAFFH8XAAIBAAUJDCC0CADDAQABAAUJDCC0CADDAQAuAAQKfzgAAgEACQkAJpkCAD4DAAEACQkAJpkCAD4DAAAA.Bahm:BAAALgADCgYJEwAAAA==.Baktolife:BAAALgAECgkJBAAAAA==.Bam:BAAALgAECgQJBQABLgAFFAIJBgAKAJshAA==.Bartholomoo:BAABLgAECn9BAAIKAAkJvyIOEADsAgAKAAkJvyIOEADsAgAAAA==.Bayonetta:BAAALgAECgcJDAAAAA==.',
Be='Beeftornado:BAAALgAECgYJBwAAAA==.Belakor:BAAALgADCgIJAgAAAA==.Ber:BAAALgAECgEJAwAAAA==.',
Bi='Bigbusta:BAAALgADCgMJAwAAAA==.Bigmanblasto:BAAALgADCgMJBAAAAA==.Bildros:BAAALgAECgEJAQAAAA==.Birgite:BAAALgAECgYJEQAAAA==.Bizniz:BAAALgAECgYJDAAAAA==.',
Bl='Blastin:BAAALgADCgcJBwAAAA==.Blazefury:BAABLgAECn8ZAAILAAYJcwwYqADyAAALAAYJcwwYqADyAAAAAA==.Blazeknight:BAACLgAFFH8IAAIMAAMJIw/EAgCLAAAMAAMJIw/EAgCLAAAuAAQKfy4AAwwACQn9GV4WANYBAAwACQn9GV4WANYBAA0AAQkAAHAQAAAAAAAA.Blazemaker:BAACLgAFFH8KAAIIAAQJhQTaDgCAAAAIAAQJhQTaDgCAAAAuAAQKfxoAAggABgk8EL3AAAgBAAgABgk8EL3AAAgBAAAA.Blazemaster:BAAALgAECgQJCQAAAA==.Blinduru:BAACLgAFFH8VAAINAAQJNyLdKACGAQANAAQJNyLdKACGAQAuAAQKfzkAAg0ACQltJcoCAFsDAA0ACQltJcoCAFsDAAAA.Blitz:BAAALgAECgIJAgAAAA==.Blocktor:BAAALgAECgMJAwABLgAECgYJHAANANkOAA==.Bloodsylf:BAAALgAECgkJBAABLgAECgcJFgAOAM4TAA==.Bluberriez:BAAALgAECgYJBgAAAA==.',
Bo='Bobbiepines:BAAALgAECgMJAwAAAA==.Bonez:BAAALgAECgMJAwAAAA==.Book:BAABLgAECn8UAAIDAAkJHBV6EQBdAgADAAkJHBV6EQBdAgAAAA==.Bookie:BAAALgAECgcJCAAAAA==.Books:BAAALgAECgIJAgAAAA==.Booza:BAAALgAECgIJAgAAAA==.Borkenshwang:BAAALgADCgYJCwAAAA==.Boydik:BAAALgAECgQJBgAAAA==.',
Bp='Bpain:BAAALgAECgMJAwABLgAECgkJMAAPAAEcAA==.Bpaìn:BAABLgAECn8wAAIPAAkJARxoDACVAgAPAAkJARxoDACVAgAAAA==.',
Br='Breandán:BAAALgADCgEJAQABLgAFFAcJIAAQAL0eAA==.Brewlïth:BAAALgAECgIJAgABLgAFFAYJEQARAMceAA==.Brewmaester:BAAALgAECgEJAgAAAA==.Brink:BAABLgAECn8YAAIIAAkJvA8FWwDNAQAIAAkJvA8FWwDNAQAAAA==.Brojac:BAAALgAECgcJDgAAAA==.Brokil:BAAALgADCggJDAAAAA==.Brolic:BAAALgAECgQJBQAAAA==.Bromaster:BAAALgAECgQJBQAAAA==.Brones:BAAALgAECgkJAwAAAA==.Brossiere:BAABLgAECn8hAAQSAAgJERuRNQB6AQASAAUJZRqRNQB6AQATAAYJoxdQjABYAQAUAAUJVRenIwD4AAAAAA==.Brotemic:BAAALgAECgYJDgAAAA==.Brovine:BAAALgAECgEJAQAAAA==.Bru:BAACLgAFFH8RAAIBAAUJXxoxDQB3AQABAAUJXxoxDQB3AQAuAAQKfyoAAgEACQl1HOwMAIYCAAEACQl1HOwMAIYCAAAA.Brutalizèr:BAAALgADCgYJBgABLgAECgEJAQAJAAAAAA==.',
Bt='Bt:BAAALgAECgUJCwAAAA==.',
Bu='Bubblegal:BAAALgAECgQJCQAAAA==.Bullsmcgee:BAABLgAECn88AAMKAAkJlyVqAwBpAwAKAAkJlyVqAwBpAwARAAEJAAAXQwA9AAAAAA==.Burningtree:BAABLgAECn8fAAIIAAkJDQ78ZgCvAQAIAAkJDQ78ZgCvAQAAAA==.Burny:BAAALgADCgEJAQAAAA==.Burrder:BAAALgADCggJCAAAAA==.Bustdown:BAAALgADCggJDwAAAA==.Buttslapper:BAAALgADCggJCAAAAA==.',
['Bö']='Börck:BAAALgADCgUJBQAAAA==.',
['Bø']='Bøb:BAAALgAECggJCwAAAA==.',
Ca='Camamoonmana:BAABLgAECn8aAAIFAAkJ3BN0OAC1AQAFAAkJ3BN0OAC1AQAAAA==.Captcorndog:BAACLgAFFH8GAAMPAAMJ2wqxSQClAAAPAAMJ2wqxSQClAAAVAAEJ2QJfBQAlAAAuAAQKfygABA8ACAlAFb8jAL4BAA8ACAlAFb8jAL4BABUABQnzA3k4AKcAABYAAQkAALRAAC8AAAAA.Caskket:BAAALgAECgkJEwAAAA==.Castreytid:BAAALgAECgcJDQABLgAFFAQJBQAXAHoHAA==.Catdog:BAABLgAECn8mAAIYAAYJFRizIwAzAQAYAAYJFRizIwAzAQAAAA==.Catechism:BAABLgAECn8uAAMSAAkJkB75BgAcAwASAAkJkB75BgAcAwATAAYJnwjZ3wDeAAAAAA==.',
Ce='Cemeo:BAABLgAECn8UAAIVAAcJiBcTFgDsAQAVAAcJiBcTFgDsAQAAAA==.Cerberusalfa:BAACLgAFFH8YAAIMAAUJ9iVYBQC6AQAMAAUJ9iVYBQC6AQAuAAQKfzgAAgwACQkTJkQBAGsDAAwACQkTJkQBAGsDAAAA.',
Ch='Chaintazer:BAAALgADCgYJBgABLgAFFAQJBQAXAHoHAA==.Chewbaca:BAAALgAECgEJAwAAAA==.Chickennuggi:BAACLgAFFH8LAAIIAAQJYREuYgAeAQAIAAQJYREuYgAeAQAuAAQKfyoAAggACAmsHVwrAGwCAAgACAmsHVwrAGwCAAAA.Chinchilla:BAAALgADCgcJBwAAAA==.Chiphoof:BAABLgAECn8nAAMZAAkJZBfsCAA6AgAZAAkJZBfsCAA6AgAYAAEJuQzABwAoAAAAAA==.Chocofox:BAABLgAECn8hAAMQAAkJmSFvBQBcAwAQAAkJmSFvBQBcAwAaAAEJ0AOERwAhAAAAAA==.Chokemagic:BAAALgAFFAIJBAAAAA==.Chopndot:BAAALgAECgEJBAAAAA==.Chozen:BAAALgADCgcJBwAAAA==.Chrill:BAABLgAECn8cAAINAAYJchfybABKAQANAAYJchfybABKAQAAAA==.',
Cl='Claraabun:BAAALgAECgUJBQABLgAFFAYJFgASAMYTAA==.Clarabuns:BAACLgAFFH8WAAISAAYJxhNZEQCsAQASAAYJxhNZEQCsAQAuAAQKfx8AAxIACQnGF2YlAPsBABIACQnGF2YlAPsBABMABQl1F/x+AHEBAAAA.Clarasbuns:BAAALgAECgMJAwABLgAFFAYJFgASAMYTAA==.Clawdragoon:BAECLgAFFH8dAAQbAAUJoQ67JgD5AAAbAAUJoQ67JgD5AAAFAAQJhAFOSwCPAAAYAAEJpwJmSAAaAAAuAAQKfzAAAxsACAnVGW0UAG8CABsACAnVGW0UAG8CAAUABQlACN+bAJQAAAAA.',
Co='Coati:BAAALgADCgYJBgAAAA==.Coldorc:BAAALgADCgEJAQAAAA==.Colforbin:BAAALgADCgUJBQAAAA==.Colosie:BAAALgAECgYJEwABLgAFFAEJAQAJAAAAAA==.Comegetpsalm:BAABLgAECn89AAISAAkJJRrqEQCEAgASAAkJJRrqEQCEAgAAAA==.Cornbreadmat:BAAALgADCgcJDQAAAA==.',
Cr='Creamsock:BAAALgAECgQJCQAAAA==.Creatlach:BAACLgAFFH8gAAIQAAcJvR6nBgBcAgAQAAcJvR6nBgBcAgAuAAQKfzoAAxAACQmKG0scAGoCABAACQmKG0scAGoCABwAAwlXE3BjALUAAAAA.Creatlachlol:BAAALgAECgkJCQABLgAFFAcJIAAQAL0eAA==.Creech:BAAALgADCgIJAgAAAA==.Creeptoken:BAAALgAECgEJAQAAAA==.Crucifilth:BAAALgADCgYJDAAAAA==.Cryopathy:BAAALgAECgYJDgAAAA==.Crypty:BAABLgAECn8dAAMcAAkJggwNNABrAQAcAAkJggwNNABrAQAQAAUJrREiXQAWAQAAAA==.',
Cy='Cyaniidee:BAAALgADCgcJBwAAAA==.Cyraxx:BAAALgADCgMJAwAAAA==.Cyrusdragon:BAAALgAECgYJBgAAAA==.Cyrussham:BAAALgAECgEJAQAAAA==.Cytherea:BAABLgAECn8rAAITAAgJ8w/XgwBoAQATAAgJ8w/XgwBoAQAAAA==.',
Da='Daddybod:BAABLgAECn8gAAIdAAkJjRJwHgCyAQAdAAkJjRJwHgCyAQAAAA==.Dainnan:BAAALgADCgEJAQAAAA==.Dalinek:BAAALgAECgUJBQAAAA==.Danicarkel:BAAALgAECggJDgAAAA==.Darkcallum:BAAALgAECgMJBAAAAA==.Darktaynt:BAAALgAECgMJBQAAAA==.Darthfox:BAAALgAECgMJBQAAAA==.',
De='Deadsean:BAAALgAECgUJDAAAAA==.Deathsyn:BAABLgAFFH8JAAIKAAQJzRlFVwBEAQAKAAQJzRlFVwBEAQAAAA==.Deathtracker:BAABLgAECn8bAAILAAgJmg55YgCBAQALAAgJmg55YgCBAQAAAA==.Deathwarden:BAAALgAECggJEwAAAA==.Deathñdk:BAAALgADCgEJAQAAAA==.Debuffed:BAAALgAECgEJAQAAAA==.Delathor:BAAALgAECgcJDgABLgAFFAEJAQAJAAAAAA==.Delimeatear:BAAALgAECgIJAgABLgAECgkJHQACABkcAA==.Demiloss:BAAALgAFFAEJAQABLgAFFAQJBQATAOIVAA==.Demise:BAACLgAFFH8HAAIIAAQJXBJFWQArAQAIAAQJXBJFWQArAQAuAAQKfy8AAggACAnmHjoxAK0CAAgACAnmHjoxAK0CAAAA.Demonclem:BAAALgAFFAIJAgAAAA==.Demonskinner:BAAALgADCgUJBQAAAA==.Denzo:BAAALgAECgMJAwAAAA==.Deoxyrybo:BAACLgAFFH8FAAIMAAMJPQo9HQC4AAAMAAMJPQo9HQC4AAAuAAQKfzsAAwwACQnkGZUNAEwCAAwACQnkGZUNAEwCAA0ABgmnC5WIABQBAAAA.Destructin:BAAALgAECgEJAQAAAA==.Destructor:BAAALgAECgcJEwAAAA==.Devourera:BAAALgAFFAMJAwABLgAFFAQJEAADAD8UAA==.',
Di='Died:BAAALgADCgMJAwAAAA==.Dilldobaggin:BAAALgADCgQJBAAAAA==.Dinoknight:BAAALgAECgcJBwAAAA==.Dinopriest:BAABLgAECn8XAAICAAcJLRcDJgCcAQACAAcJLRcDJgCcAQAAAA==.Distia:BAAALgAECgcJCgAAAA==.Divinedragon:BAABLgAECn8uAAMCAAkJGhiiEgA+AgACAAkJGhiiEgA+AgADAAcJ5AteAwBuAAAAAA==.Dixoncider:BAAALgAECgQJBgAAAA==.',
Do='Doboy:BAAALgADCgIJAgAAAA==.Donmanuel:BAAALgADCgEJAQAAAA==.',
Dr='Drackaris:BAAALgADCgYJBgAAAA==.Draggo:BAAALgAECgEJAwAAAA==.Drainbamage:BAAALgAECgMJAwAAAA==.Drakin:BAABLgAECn9HAAITAAkJ0CD+DAD9AgATAAkJ0CD+DAD9AgAAAA==.Dreya:BAABLgAECn8aAAIaAAkJDR3ZCQAfAgAaAAkJDR3ZCQAfAgAAAA==.Dreyas:BAAALgADCgYJBgAAAA==.Drinkcoolaid:BAACLgAFFH8HAAIQAAQJiQ4qBADjAAAQAAQJiQ4qBADjAAAuAAQKfx8AAhAACQmfFrIgAEsCABAACQmfFrIgAEsCAAAA.Dritzle:BAABLgAECn8aAAMeAAgJBhXKIQDrAQAeAAgJBhXKIQDrAQAGAAQJHgi5EwDEAAAAAA==.Droopapi:BAAALgAECgYJEQAAAA==.',
Du='Durrt:BAAALgADCgcJCAABLgAECgcJLAAFAGsiAA==.Dutchman:BAACLgAFFH8VAAILAAcJEyLvCwANAgALAAcJEyLvCwANAgAuAAQKfxwAAgsACAkNIWYIAAsDAAsACAkNIWYIAAsDAAAA.',
Eh='Ehhmuh:BAAALgAECgYJCgAAAA==.Ehlumii:BAABLgAECn8UAAIEAAYJRSRvDgBvAgAEAAYJRSRvDgBvAgAAAA==.',
Ei='Eiffel:BAAALgADCgUJBQAAAA==.',
El='Eldrene:BAABLgAECn82AAMIAAkJYh6nGgC6AgAIAAkJYh6nGgC6AgAfAAEJ7hOWHAA6AAAAAA==.Elethil:BAAALgADCgEJAgAAAA==.Elfstomper:BAAALgADCggJCwAAAA==.Elitepaladin:BAABLgAECn8nAAISAAkJGBbfIQAPAgASAAkJGBbfIQAPAgAAAA==.Ellexi:BAAALgAECgYJDAAAAA==.Elrai:BAAALgAECgIJAwAAAA==.Elyseia:BAABLgAECn8gAAILAAkJgwbuiQArAQALAAkJgwbuiQArAQAAAA==.',
Em='Empkin:BAAALgAECgcJEwAAAA==.',
En='Enof:BAAALgADCgIJAgAAAA==.Enpower:BAAALgADCgYJBgABLgAFFAQJEgAgAO8TAA==.',
Ep='Epicsause:BAAALgAFFAIJAgAAAA==.',
Er='Erelor:BAAALgADCgMJAwAAAA==.',
Es='España:BAECLgAFFH8NAAIRAAUJ+hbVGQAYAQARAAUJ+hbVGQAYAQAuAAQKfy0ABBEACQlOGj0KAHYCABEACQlOGj0KAHYCACEABQlGEXUcAOoAAAoAAQkAAMOuAQAAAAAA.Españaluna:BAEALgAECgcJBgABLgAFFAUJDQARAPoWAA==.Españamor:BAEALgAECgkJCAABLgAFFAUJDQARAPoWAA==.Essdeath:BAAALgAECgEJAQABLgAECgkJIAAdAI0SAA==.',
Ex='Excrucio:BAAALgADCgYJBgAAAA==.',
Ez='Ezpain:BAAALgAECgQJBQAAAA==.',
Fa='Farael:BAAALgAECgcJBAAAAA==.Farmerbrown:BAAALgAECgQJCAABLgAFFAMJBwATAFUaAA==.Fatalmann:BAACLgAFFH8LAAMVAAUJFAjNHgC4AAAVAAQJWwLNHgC4AAAWAAMJPwVjCwBpAAAuAAQKfxYAAxYACQnMD5kVAJUBABYABwmoD5kVAJUBABUABgk2DyMcAB0BAAAA.Fatalminn:BAAALgAECgUJCQAAAA==.Fathergob:BAAALgADCgEJAQAAAA==.Fatty:BAAALgADCgYJBgAAAA==.',
Fe='Fenty:BAAALgADCgEJAQAAAA==.Feralhorn:BAAALgAECgEJAQAAAA==.',
Fi='Fingerz:BAAALgADCgIJAgAAAA==.Fintan:BAAALgAFFAEJAQABLgAFFAcJIAAQAL0eAA==.',
Fl='Flarestrasz:BAAALgADCgUJCQAAAA==.Flexxar:BAAALgAECgEJAgAAAA==.Flinwazzart:BAAALgADCgcJBwAAAA==.Flutterby:BAAALgAECgEJAQABLgAECgkJOQACAJwJAA==.Flèxion:BAACLgAFFH8OAAIKAAUJ2R9jSgBeAQAKAAUJ2R9jSgBeAQAuAAQKfygAAgoACAkBJdAgAIUCAAoACAkBJdAgAIUCAAAA.',
Fo='Foskin:BAAALgAECgMJBAABLgAFFAQJBQAXAHoHAA==.',
Fr='Frassk:BAABLgAECn9DAAMHAAkJPBs7BgABAgAHAAcJSB07BgABAgAiAAQJ0hIS0QCyAAAAAA==.Freja:BAAALgADCgMJBgAAAA==.Frigid:BAAALgAECgkJBwAAAA==.Froggystyle:BAAALgAECgYJDgABLgAECggJDgAJAAAAAA==.Frostydru:BAABLgAECn8wAAIZAAgJfiH4BwBTAgAZAAgJfiH4BwBTAgAAAA==.Frozat:BAACLgAFFH8bAAIVAAgJGxhhBACZAgAVAAgJGxhhBACZAgAuAAQKfygAAxUACAkRI2oEAOYCABUACAkRI2oEAOYCAA8AAQmAEZ5eAEAAAAAA.Frösting:BAAALgADCgcJDgABLgAECgkJSAANAIkfAA==.',
Fu='Fullblooded:BAAALgAECgEJAQAAAA==.Fundeedo:BAAALgAFFAIJAwAAAA==.Furballieo:BAAALgADCgIJAgAAAA==.',
Ga='Galadriels:BAAALgAECgQJBAAAAA==.Galianem:BAAALgADCgMJAwAAAA==.Gamora:BAAALgAECgYJCQAAAA==.Gandon:BAAALgAECgQJCAAAAA==.Garbarn:BAABLgAECn8WAAITAAkJ0w90fgBxAQATAAkJ0w90fgBxAQAAAA==.Garonno:BAAALgADCgIJAgAAAA==.',
Ge='Gelystine:BAAALgADCgUJCgAAAA==.Geminiholy:BAAALgADCgcJBwABLgAFFAQJEgAgAO8TAA==.Geminirunes:BAAALgADCgYJBgABLgAFFAQJEgAgAO8TAA==.Germaine:BAAALgAECgQJBQAAAA==.',
Gh='Ghabi:BAAALgAECgYJBgAAAA==.Ghauri:BAAALgAECgMJBQAAAA==.',
Gi='Gia:BAABLgAECn8zAAIEAAgJpxt/FQBuAgAEAAgJpxt/FQBuAgAAAA==.',
Go='Gobx:BAAALgAECgUJBgAAAA==.Golgroth:BAABLgAECn8pAAIXAAkJeAfJOwBXAQAXAAkJeAfJOwBXAQAAAA==.Goodlocktime:BAAALgADCgIJAgABLgAECgYJCAAJAAAAAA==.Goodtimesm:BAAALgAECgYJCAAAAA==.Goodtymes:BAAALgAECgEJAQABLgAECgYJCAAJAAAAAA==.Gorearrow:BAACLgAFFH8OAAILAAUJOBSdNwA+AQALAAUJOBSdNwA+AQAuAAQKfzAAAwsACQlXItgLAOMCAAsACQlXItgLAOMCACMAAglWB2N6AFkAAAAA.Goretaint:BAAALgAECgYJDwAAAA==.Gorgesh:BAAALgADCgQJBAAAAA==.Gothladriel:BAAALgAECgYJDAAAAA==.Gotpwnedd:BAAALgAECgEJAQAAAA==.Gottamoo:BAABLgAECn8ZAAMYAAkJJwzAKQAOAQAYAAkJJwzAKQAOAQAbAAEJPQFWkAAaAAAAAA==.',
Gr='Greenstank:BAAALgAECggJDgAAAA==.Grrumpybear:BAABLgAECn9EAAIYAAkJ3xtTBwCBAgAYAAkJ3xtTBwCBAgAAAA==.Grundal:BAAALgADCggJCAAAAA==.',
Gu='Gumbuz:BAAALgAECgQJBgAAAA==.Gunafistya:BAABLgAFFH8JAAIEAAMJpBXjOQC+AAAEAAMJpBXjOQC+AAAAAA==.Gunnaroptiks:BAAALgAECgUJBQABLgAFFAQJGAAdAIsXAA==.Guzzler:BAAALgAECgkJDgAAAA==.',
['Gú']='Gúildarts:BAAALgADCgEJAQAAAA==.',
Ha='Haannarr:BAAALgAECgIJAgAAAA==.Hairymoodini:BAAALgAECgEJAgAAAA==.Hajin:BAAALgAECgYJDwAAAA==.Hankjr:BAAALgAECgEJAwAAAA==.Hanky:BAAALgAECgQJBAAAAA==.Havòk:BAAALgAECggJBwABLgAFFAEJAQAJAAAAAA==.Hawthorn:BAAALgAECgMJCAAAAA==.Hazyblades:BAAALgAECgMJAwAAAA==.',
He='Hektar:BAAALgADCgYJBgAAAA==.Helacookie:BAABLgAECn8ZAAITAAkJMBNVVADNAQATAAkJMBNVVADNAQAAAA==.Henso:BAAALgAFFAEJAQABLgAFFAQJEgAgAO8TAA==.Heomors:BAAALgAECgEJAQAAAA==.Hexxan:BAAALgAECgUJEAAAAA==.',
Hi='Hiawatha:BAAALgADCgEJAQABLgAECgcJBwAJAAAAAA==.Hifumi:BAAALgADCgQJBwAAAA==.Hisagu:BAAALgAECgEJAQABLgAECggJFAAKABYbAA==.Hitstabkill:BAAALgAECgEJAQAAAA==.Hiver:BAAALgAECgQJBgAAAA==.',
Ho='Hoagar:BAAALgAECgcJDAABLgAFFAMJCQAOALkeAA==.Holes:BAAALgAECgEJAgAAAA==.Holier:BAACLgAFFH8MAAITAAMJMxEECAC6AAATAAMJMxEECAC6AAAuAAQKfzkAAhMACQn+FXZGAPMBABMACQn+FXZGAPMBAAAA.Hollows:BAAALgAECgQJBgAAAA==.Holyatrops:BAAALgAECgkJEQABLgAFFAgJKQAiAJ4cAA==.Hoochurcooch:BAAALgAECgEJAQAAAA==.Hoppers:BAAALgAECgIJAgABLgAECgcJDwAJAAAAAA==.Hopperstotem:BAAALgAECgcJDwAAAA==.Horuu:BAAALgAECgQJBgAAAA==.Hoyboii:BAAALgADCgYJBgAAAA==.',
Hu='Hulo:BAAALgAECgcJDwAAAA==.Humbled:BAAALgAECgQJBQAAAA==.Hunteress:BAAALgADCgYJBwAAAA==.Huntkoalas:BAAALgAECgMJAwABLgAFFAgJIgAbACIVAA==.Hurrdurr:BAAALgAECgEJAQAAAA==.',
['Hî']='Hîflax:BAAALgAECgEJAgAAAA==.',
['Hö']='Hölyców:BAAALgADCgQJBAAAAA==.',
Ic='Ichbinstark:BAAALgAECgEJBAAAAA==.',
Id='Idonttcare:BAAALgAECgMJAwAAAA==.',
If='Ifirt:BAAALgAECgkJCwAAAA==.',
Ig='Iggnignokt:BAAALgADCgYJBwAAAA==.',
Ih='Ihealnewbs:BAAALgADCgYJDwAAAA==.',
In='Infamus:BAAALgAECgQJCgAAAA==.Invisabull:BAAALgAECgQJBgAAAA==.Invysion:BAACLgAFFH8QAAIDAAUJ/wipIwAxAQADAAUJ/wipIwAxAQAuAAQKfy4AAgMACQkXEf0dAN4BAAMACQkXEf0dAN4BAAAA.',
Ir='Ironballz:BAAALgAECgMJAwAAAA==.Irri:BAAALgADCgUJBQAAAA==.',
Is='Ishara:BAAALgAECggJCAABLgAECgkJNgAIAGIeAA==.',
Ja='Jacuzzi:BAAALgAECgUJCAAAAA==.Jaidess:BAAALgAECgEJAQAAAA==.',
Je='Jeangen:BAAALgAECgUJBAAAAA==.Jeanjean:BAAALgAECgcJCAAAAA==.Jeannjeann:BAAALgAECggJEgAAAA==.Jediknîght:BAAALgAECgYJBgAAAA==.Jeep:BAACLgAFFH8NAAILAAQJnhu1QgAoAQALAAQJnhu1QgAoAQAuAAQKfycAAgsACAlAJVMEAEoDAAsACAlAJVMEAEoDAAAA.Jellybea:BAACLgAFFH8RAAIBAAUJCRsnDACIAQABAAUJCRsnDACIAQAuAAQKfywAAwEACQltITEEABIDAAEACQltITEEABIDAAIAAgkJDAJxAGAAAAAA.',
Ji='Jibalynne:BAAALgAECgQJBAAAAA==.Jida:BAAALgAECgEJAQAAAA==.Jiffy:BAABLgAECn8tAAMXAAkJWx3rEQBlAgAXAAkJWx3rEQBlAgAkAAEJPQmnggAnAAAAAA==.Jiffypop:BAAALgAECgcJDQABLgAECgkJLQAXAFsdAA==.Jinwooaura:BAAALgADCgcJBwAAAA==.',
Jo='Johnnycakes:BAAALgADCgMJBQAAAA==.Jonsnowxd:BAAALgADCgYJBgAAAA==.',
Jr='Jrhnbr:BAAALgADCgMJAwAAAA==.',
Ju='Juggnut:BAAALgAECgcJEQAAAA==.Jump:BAAALgAECgcJEwAAAA==.Junglebrew:BAAALgADCgQJBAAAAA==.Jurisdiction:BAABLgAECn8uAAITAAkJWRLESQDpAQATAAkJWRLESQDpAQAAAA==.',
Jz='Jz:BAAALgAECgMJBAAAAA==.',
['Jì']='Jìnn:BAAALgAECgUJDwAAAA==.',
Ka='Kaan:BAABLgAECn8sAAIFAAcJayJLEwCbAgAFAAcJayJLEwCbAgAAAA==.Kabea:BAAALgAECgEJAgAAAA==.Kadath:BAAALgADCgIJAwAAAA==.Kaeladín:BAAALgAECgUJCAAAAA==.Kagebouzu:BAAALgAECgYJDwAAAA==.Kahlan:BAAALgADCgcJCAABLgAECgYJDwAJAAAAAA==.Kakutogi:BAAALgADCgEJAQAAAA==.Kalycia:BAAALgAECgEJAgAAAA==.Kamela:BAAALgAECgYJCAAAAA==.Karael:BAAALgAECgUJEQABLgAFFAIJAgAJAAAAAA==.Karma:BAABLgAECn8YAAIeAAYJqgO/QADCAAAeAAYJqgO/QADCAAAAAA==.Kayliaa:BAAALgAECgkJAQAAAA==.Kazarke:BAAALgADCgcJGAAAAA==.',
Ke='Keeia:BAAALgADCgQJBQAAAA==.Keho:BAABLgAECn81AAMdAAkJVAuZJQCBAQAdAAkJVAuZJQCBAQAgAAIJkg6maABqAAAAAA==.Keihoe:BAAALgAECgMJAwABLgAECgkJNQAdAFQLAA==.Kenalia:BAABLgAECn8qAAIEAAkJlRbTGgBCAgAEAAkJlRbTGgBCAgAAAA==.Kengo:BAAALgAECgEJAQAAAA==.Keptalive:BAAALgADCgcJCgAAAA==.Kerzermern:BAAALgAFFAMJAwAAAA==.Kevic:BAAALgAFFAIJAwABLgAFFAUJEwACABESAA==.',
Kh='Khamaelion:BAAALgADCgcJDgAAAA==.Khromn:BAAALgAECgkJAQABLgAFFAIJAgAJAAAAAA==.',
Ki='Kiara:BAABLgAECn8eAAITAAgJNiBdIgCgAgATAAgJNiBdIgCgAgAAAA==.Kiju:BAAALgADCgYJBgAAAA==.Killaban:BAACLgAFFH8KAAIXAAQJ9BcJHwA1AQAXAAQJ9BcJHwA1AQAuAAQKfzIAAxcACQklINwXAC8CABcACQngH9wXAC8CACQAAwkZGVMrAJoAAAAA.Killbydeath:BAAALgAECgEJAQAAAA==.Kimberlyhárt:BAACLgAFFH8HAAITAAMJVRpqWwD5AAATAAMJVRpqWwD5AAAuAAQKfzcAAxMACQnxJL0EAFMDABMACQnxJL0EAFMDABIABAn0CmVjAKgAAAAA.Kissmydots:BAABLgAECn9EAAIiAAkJKR58FwCXAgAiAAkJKR58FwCXAgAAAA==.Kitja:BAABLgAECn9QAAMDAAkJHCGxAwBmAwADAAkJHCGxAwBmAwABAAgJaBw3EQBZAgAAAA==.Kitla:BAAALgADCgUJBQABLgAECgkJUAADABwhAA==.',
Kl='Klipsch:BAAALgADCgUJBQAAAA==.Klukai:BAAALgADCgcJCwABLgAECgkJIQAFAPMdAA==.',
Kn='Kneed:BAAALgADCgYJBgAAAA==.',
Ko='Koala:BAAALgAECgQJBQABLgAFFAgJIgAbACIVAA==.Kohman:BAABLgAECn8bAAIiAAYJ3RXOfABiAQAiAAYJ3RXOfABiAQAAAA==.Konyani:BAAALgADCgUJAQAAAA==.',
Kp='Kpop:BAAALgAECgEJAQABLgAECgcJBwAJAAAAAA==.',
Kr='Kraeven:BAAALgADCgEJAQAAAA==.Kregerath:BAAALgADCgIJAgAAAA==.Krftpnk:BAACLgAFFH8XAAIMAAUJPCa6BQCwAQAMAAUJPCa6BQCwAQAuAAQKfyoAAwwACQnQJDcEADcDAAwACQnQJDcEADcDAA0AAQkAAOVIAQAAAAAA.Kronas:BAABLgAECn8VAAILAAgJ3RW5YgCAAQALAAgJ3RW5YgCAAQAAAA==.Kronophyne:BAACLgAFFH8JAAIIAAUJSRHnXgAjAQAIAAUJSRHnXgAjAQAuAAQKfzcAAggACQn5HSM0AEgCAAgACQn5HSM0AEgCAAAA.Kronotality:BAACLgAFFH8IAAMRAAMJ5xOfNwBWAAAKAAMJXQuorADHAAARAAEJJR+fNwBWAAAuAAQKf0oAAhEACQkZJWQCACoDABEACQkZJWQCACoDAAAA.Kronotek:BAAALgAECgcJDQAAAA==.Kronotekken:BAAALgADCgYJBgAAAA==.Kronotide:BAAALgAECgYJDAAAAA==.',
Ku='Kungfukittn:BAAALgAECgEJAgAAAA==.Kurohitsugî:BAAALgAECgIJBAAAAA==.',
Ky='Kylorai:BAAALgAECgYJEgAAAA==.Kynbrochel:BAAALgAECgYJEgAAAA==.',
La='Laars:BAAALgAECgUJDAABLgAECggJJQAiADsNAA==.Laimaster:BAAALgAECgEJAwAAAA==.Lakiri:BAABLgAECn9DAAIaAAkJiBsZBgB6AgAaAAkJiBsZBgB6AgAAAA==.Landaeda:BAAALgAECgcJDgAAAA==.Lanney:BAAALgAECgYJBgAAAA==.Lapsu:BAABLgAECn8fAAIgAAkJjRQBHQDGAQAgAAkJjRQBHQDGAQAAAA==.Lascivia:BAACLgAFFH8TAAMXAAUJYx/qFABlAQAXAAUJYx/qFABlAQAlAAQJQBLDFwDcAAAuAAQKfyYAAxcACQkAH1AmACcCABcACQmIHFAmACcCACUACAnlEJ8eAD8BAAAA.Lawhanx:BAAALgADCgEJAQABLgAFFAQJBQATAOIVAA==.Laylahh:BAAALgAECgMJAwAAAA==.Lazy:BAABLgAECn8WAAMiAAYJyRcpiQBHAQAiAAUJyRcpiQBHAQAHAAIJxQGEYQBLAAAAAA==.',
Le='Leademon:BAABLgAECn9BAAMNAAkJ6SBCEQC4AgANAAkJ6SBCEQC4AgAMAAIJTRrWWgB2AAAAAA==.Leadmin:BAAALgADCgMJBQABLgAECgkJQQANAOkgAA==.Leadmln:BAAALgADCgcJBwABLgAECgkJQQANAOkgAA==.Leftlane:BAABLgAECn8uAAMQAAkJsiE9BgBMAwAQAAkJsiE9BgBMAwAcAAEJgA2GqgAsAAAAAA==.Legato:BAAALgAECgkJCgABLgAFFAgJIAAQANgeAA==.Lehsham:BAAALgAECgkJAgAAAA==.Lekiri:BAAALgAECgYJCAAAAA==.Lep:BAAALgAFFAQJBAABLgAFFAgJGwAVABsYAA==.Lethalkrits:BAAALgAECgkJAgAAAA==.Leva:BAABLgAECn8hAAIFAAkJ8x3KGAB/AgAFAAkJ8x3KGAB/AgAAAA==.',
Li='Liberté:BAAALgAECgYJCwAAAA==.Liciano:BAABLgAECn8ZAAMmAAkJdRygAgCRAgAmAAkJSRugAgCRAgAeAAYJ5R0fHwCdAQABLgAFFAIJAgAJAAAAAA==.Licious:BAAALgAECgEJAQABLgAECgcJBwAJAAAAAA==.Lie:BAACLgAFFH8HAAIeAAIJTgvZNACOAAAeAAIJTgvZNACOAAAuAAQKfzsAAh4ACQkNGUINAFICAB4ACQkNGUINAFICAAAA.Lightsdown:BAAALgAECgYJBgAAAA==.Lilbeebs:BAAALgAECgkJEQAAAA==.Lileth:BAAALgAECgkJAgAAAA==.Lilflea:BAAALgAECggJEQAAAA==.Lilzuki:BAABLgAECn8bAAIHAAkJzwtNDgBXAQAHAAkJzwtNDgBXAQAAAA==.Lilïth:BAACLgAFFH8RAAIRAAYJxx7QEQBsAQARAAYJxx7QEQBsAQAuAAQKfyAAAhEABwmDJPIGAMICABEABwmDJPIGAMICAAAA.Linguine:BAAALgAECgEJBAABLgAFFAYJGgABAKgWAA==.Lisalisa:BAABLgAECn89AAIQAAkJwxfFIQBEAgAQAAkJwxfFIQBEAgAAAA==.Livan:BAAALgAECgMJAwAAAA==.Livia:BAAALgAECgEJAQAAAA==.',
Lo='Lohzak:BAAALgAECgEJAQAAAA==.Lousier:BAAALgAECgEJAQAAAA==.',
Lu='Lukethywalkr:BAAALgADCgYJBgAAAA==.Lularia:BAAALgADCgIJAgAAAA==.Lumii:BAAALgAECgYJBgABLgAECgYJFAAEAEUkAA==.Luminari:BAAALgADCgEJAQABLgAECgkJNgAIAGIeAA==.Lunaa:BAAALgAECgkJDAAAAA==.Lurassa:BAAALgAECgYJDAABLgAECgcJDgAJAAAAAA==.',
Ly='Lyacon:BAAALgADCgQJBAABLgAECgkJFQAIAEEcAA==.',
['Lä']='Lä:BAEALgAECgcJBwABLgAFFAMJBAAJAAAAAA==.',
Ma='Madrie:BAAALgAECgQJBAAAAA==.Maekar:BAABLgAECn8kAAIWAAYJwhA3DwAXAQAWAAYJwhA3DwAXAQAAAA==.Maellus:BAAALgAECgEJAQAAAA==.Maelstorm:BAAALgADCgIJAgAAAA==.Mageman:BAAALgADCgYJAgAAAA==.Magickdragon:BAAALgAECgYJBwABLgAECgkJLgACABoYAA==.Magicmoo:BAAALgAECgEJAQABLgAFFAMJBwATAFUaAA==.Maltis:BAAALgADCgcJCwAAAA==.Mananstuff:BAACLgAFFH8FAAIbAAMJqQRtOgCPAAAbAAMJqQRtOgCPAAAuAAQKf0QAAhsACQmIEYwfAMsBABsACQmIEYwfAMsBAAAA.Manaproblems:BAAALgADCgMJBAAAAA==.Mandemic:BAAALgAECgYJCQABLgAFFAUJFAAXABEbAA==.Marguerek:BAAALgADCgEJAQAAAA==.Marinara:BAAALgAECgcJDgAAAA==.Marisatomei:BAAALgAECgYJBgAAAA==.Markamanimal:BAACLgAFFH8PAAIZAAQJjBpbBgBIAQAZAAQJjBpbBgBIAQAuAAQKfyUAAhkACAnfIYYDAPwCABkACAnfIYYDAPwCAAAA.Marnix:BAABLgAECn8bAAIcAAgJmRItLwCEAQAcAAgJmRItLwCEAQAAAA==.Marshail:BAAALgAECgEJAQAAAA==.',
Md='Mdbeef:BAAALgAECgUJBQAAAA==.',
Me='Medikus:BAABLgAECn8kAAMQAAgJbxx5IABNAgAQAAgJbxx5IABNAgAcAAMJ2gwlegCAAAAAAA==.Meesoomagi:BAAALgAECgYJBwAAAA==.Megajoo:BAACLgAFFH8HAAMbAAIJuQzdPwB1AAAbAAIJuQzdPwB1AAAFAAIJuQE2aQBJAAAuAAQKfxUAAxsACAnYFQ4eANgBABsACAnYFQ4eANgBAAUABgnlBwZ7AMYAAAAA.Menil:BAABLgAECn8XAAMEAAgJwBtXFgAQAgAEAAcJJhpXFgAQAgAgAAQJchYdUQDDAAAAAA==.Merryl:BAAALgAECggJDgAAAA==.Meyounow:BAAALgAECgEJBQAAAA==.',
Mi='Midnye:BAAALgADCgYJBgAAAA==.Mike:BAECLgAFFH8GAAMnAAQJqhGfBACdAAAnAAIJzBmfBACdAAAIAAIJiAl0pQCGAAAuAAQKfzoAAycACQmDJK0AAP0CACcACQlAIq0AAP0CAAgACAlkIFhWANoBAAAA.Mips:BAAALgAFFAMJBAABLgAFFAQJBwAIAFwSAA==.',
Mk='Mk:BAEALgADCgcJBwABLgAECgkJTQAgAIoiAA==.',
Mo='Mob:BAAALgADCgcJBwAAAA==.Mockra:BAABLgAECn8+AAMIAAkJViIkFADhAgAIAAkJViIkFADhAgAfAAIJuBiqGgBCAAAAAA==.Monafae:BAAALgADCgUJBQAAAA==.Moohammered:BAABLgAECn8UAAITAAcJTRhKRAD5AQATAAcJTRhKRAD5AQAAAA==.Moolou:BAACLgAFFH8TAAIUAAUJ3RrrBAA+AQAUAAUJ3RrrBAA+AQAuAAQKfyMAAhQACQm1H1AGAIICABQACQm1H1AGAIICAAAA.Moonraka:BAAALgADCgUJBQAAAA==.Moosé:BAAALgAECgEJAQABLgAFFAgJKgATAPkXAA==.Mootilater:BAAALgADCgQJAQAAAA==.Mootilator:BAAALgADCgYJBgAAAA==.Moraei:BAAALgADCgEJAQAAAA==.Mordew:BAAALgADCgUJBQABLgAECgkJPAAKAJclAA==.Morechie:BAABLgAECn8iAAIoAAkJcBXSBwDwAQAoAAkJcBXSBwDwAQAAAA==.Morecowbell:BAAALgAECgEJAQAAAA==.Morgatho:BAAALgADCgEJAwAAAA==.Mortiferon:BAABLgAECn83AAIKAAkJCh8SFgDDAgAKAAkJCh8SFgDDAgAAAA==.',
Mu='Muhgunguh:BAAALgAECgEJAQAAAA==.Munnky:BAABLgAECn88AAIEAAgJliToBQBJAwAEAAgJliToBQBJAwAAAA==.Murmaider:BAAALgADCgIJAgAAAA==.',
My='Mythrandere:BAAALgAECgEJAQAAAA==.Mytu:BAAALgADCgUJBgAAAA==.',
['Má']='Mánflu:BAACLgAFFH8UAAIXAAUJERs2GABTAQAXAAUJERs2GABTAQAuAAQKfysAAyQACQniHhIDAOICACQACQniHhIDAOICABcABwlJGlI0ANkBAAAA.',
['Mô']='Môrrigãn:BAAALgADCgMJAwAAAA==.',
['Mö']='Mörgänä:BAAALgADCgMJAwAAAA==.',
Na='Naissa:BAAALgAECgQJCwAAAA==.Nakanir:BAAALgAECgYJBgAAAA==.Nalfeign:BAAALgAECgQJBQAAAA==.Napa:BAAALgAECgUJCgABLgAFFAYJFwAQAKMXAA==.Narn:BAABLgAECn9DAAQPAAkJOByaFAA3AgAWAAcJrRjRCQBCAgAPAAkJ5RiaFAA3AgAVAAIJLQiEQQBgAAAAAA==.',
Ne='Nealite:BAAALgAECgkJBgAAAA==.Necrophyllis:BAAALgAECgMJAwAAAA==.Necrotion:BAAALgAECgYJEgAAAA==.Nei:BAAALgAECgEJAQABLgAECgkJIAAdAI0SAA==.Nerrisa:BAABLgAECn8iAAICAAkJERQsIgC2AQACAAkJERQsIgC2AQAAAA==.Nertt:BAAALgADCgYJBgABLgAECgkJQwAVADEZAA==.Neublood:BAAALgAECgQJCAAAAA==.',
Ni='Nicodemus:BAAALgAECgcJEAAAAA==.Nimrods:BAAALgAECgQJBAAAAA==.',
No='Noblewarrior:BAACLgAFFH8hAAIXAAgJOhtDAwBVAgAXAAgJOhtDAwBVAgAuAAQKfysAAhcACAmuJHQNAJcCABcACAmuJHQNAJcCAAAA.Noctilus:BAAALgAECgcJCQAAAA==.Nohkari:BAAALgADCgkJHQABLgAECgkJJAAiANAUAA==.Nooj:BAACLgAFFH8wAAMGAAgJmSMmAADoAgAGAAgJmSMmAADoAgAeAAYJiRRJFABqAQAuAAQKfx4AAwYACQl7ITsAAMMDAAYACQl7ITsAAMMDAB4ABgmFEpA6AEQBAAAA.Notakoala:BAACLgAFFH8iAAIbAAgJIhUSDQDLAQAbAAgJIhUSDQDLAQAuAAQKfycAAxsACAlHJFQNAMUCABsACAlHJFQNAMUCABgAAQk3EjJzADQAAAAA.Nothnx:BAAALgAFFAEJAwAAAA==.Notoriouspat:BAABLgAECn8jAAILAAgJFA8DYQCFAQALAAgJFA8DYQCFAQAAAA==.Notsamadeath:BAABLgAFFH8LAAQhAAUJWRFcDwAeAQAhAAQJWRFcDwAeAQAKAAIJ3wi46wB+AAARAAEJAAB2TwAAAAAAAA==.Novia:BAAALgAECgYJBgAAAA==.Noyber:BAAALgAFFAIJAgAAAA==.Noydin:BAAALgAFFAIJAwAAAA==.',
['Ní']='Nínebreaker:BAAALgAECgUJDwAAAA==.',
['Nü']='Nüll:BAABLgAECn8UAAINAAgJ2AsCdwAzAQANAAgJ2AsCdwAzAQAAAA==.',
Ob='Obern:BAABLgAECn8WAAIOAAkJZhshFgDxAQAOAAkJZhshFgDxAQAAAA==.Obiron:BAAALgAECgEJAQAAAA==.Oblïna:BAABLgAECn8wAAIEAAkJbgqlSwA+AQAEAAkJbgqlSwA+AQAAAA==.',
Od='Odiumaeterna:BAAALgADCgcJBwAAAA==.',
Of='Offensivé:BAAALgAECgMJCAAAAA==.Oftheages:BAAALgAFFAEJAQABLgAFFAgJGwAVABsYAA==.',
On='Onetozerosix:BAABLgAECn8jAAIKAAkJHhyNPQAMAgAKAAkJHhyNPQAMAgAAAA==.Onos:BAAALgAECgEJAQAAAA==.Onsen:BAAALgAECgQJBgAAAA==.',
Oo='Oogak:BAAALgAECgUJBgAAAA==.Oomigig:BAAALgADCgUJBQAAAA==.',
Op='Opalily:BAAALgAECgEJAQAAAA==.Operation:BAAALgAECgQJCAAAAA==.',
Or='Oresties:BAAALgAECgYJCAAAAA==.Orestisies:BAAALgAECgcJCQAAAA==.Orghrax:BAAALgADCgEJAQAAAA==.Orisys:BAAALgAECgIJAwAAAA==.',
Os='Osteer:BAAALgAECgYJBgAAAA==.',
Ot='Otterjim:BAAALgADCgQJBAAAAA==.',
Pa='Padfoote:BAAALgAECgEJAQAAAA==.Pahaa:BAAALgAECgUJBQAAAA==.Pairadeez:BAAALgAECgYJDwAAAA==.Pajamabanana:BAAALgADCgIJAgAAAA==.Pandablaze:BAAALgAFFAEJAQAAAA==.Panterarey:BAAALgADCgYJEAAAAA==.Papalego:BAABLgAECn8yAAILAAkJlg43RwDMAQALAAkJlg43RwDMAQAAAA==.Parakka:BAABLgAECn82AAIQAAkJGhZ8IQBGAgAQAAkJGhZ8IQBGAgAAAA==.Patak:BAAALgAECgMJAwAAAA==.Pavle:BAAALgAECgMJAwAAAA==.Pawp:BAAALgAECgYJCgABLgAECggJJAABAOEXAA==.',
Pe='Pearagon:BAABLgAECn8VAAICAAgJwBEIJwCVAQACAAgJwBEIJwCVAQABLgAFFAYJFwAQAKMXAA==.Pepsidew:BAAALgADCgcJDAAAAA==.Pepsisprite:BAABLgAECn86AAIBAAkJdhqqDACcAgABAAkJdhqqDACcAgAAAA==.Pesky:BAABLgAECn8jAAIbAAYJJBauNQBAAQAbAAYJJBauNQBAAQABLgAFFAQJCwAIAGERAA==.',
Pf='Pfchanguz:BAAALgADCgcJDAAAAA==.',
Ph='Phdbeef:BAABLgAFFH8HAAIYAAIJ+xtiHwCgAAAYAAIJ+xtiHwCgAAABLgAFFAYJEQARAMceAA==.Phlemm:BAAALgAECgEJAQAAAA==.Phoivos:BAABLgAECn8VAAIIAAkJQRwKIQDvAgAIAAkJQRwKIQDvAgAAAA==.',
Pi='Picklez:BAABLgAECn82AAIKAAkJOiIYCgAeAwAKAAkJOiIYCgAeAwAAAA==.Pissflizzle:BAABLgAECn8dAAIiAAgJ9w0kagBoAQAiAAgJ9w0kagBoAQAAAA==.',
Pl='Plaquenil:BAAALgADCgEJAQAAAA==.',
Po='Poison:BAAALgADCgEJAQAAAA==.Porkroaster:BAABLgAECn8pAAIIAAgJuAwBhgBrAQAIAAgJuAwBhgBrAQAAAA==.Portwings:BAAALgADCgYJBgAAAA==.',
Pr='Praye:BAAALgAFFAMJAwAAAA==.Priestop:BAAALgAECgEJAQAAAA==.Professahoak:BAAALgAECgMJAwABLgAECgkJPgAIAFYiAA==.',
Ps='Psyfarian:BAAALgADCgcJDQAAAA==.Psyop:BAAALgAECgYJCAABLgAECggJIQABABkfAA==.',
Pu='Pushemover:BAAALgAECgMJBQAAAA==.',
Qu='Quelyndlina:BAAALgAECgEJAQAAAA==.Quillswitch:BAAALgAECgEJAQAAAA==.',
Ra='Radduc:BAABLgAECn8ZAAMSAAYJKxjaNgBzAQASAAYJKxjaNgBzAQATAAEJlQYzsgEpAAAAAA==.Ragerade:BAAALgAECgYJBwAAAA==.Raidu:BAAALgAECgMJAwAAAA==.Ralpherion:BAAALgADCgIJAgAAAA==.Ranoa:BAAALgAECgQJDQAAAA==.Raphåel:BAAALgAFFAEJAQAAAA==.Ravioli:BAAALgAECgQJBgAAAA==.Razialum:BAAALgADCgYJBgAAAA==.Razorsteps:BAAALgAFFAkJBAAAAA==.Razzberry:BAAALgADCgYJDAAAAA==.',
Re='Rebrowth:BAAALgAECgcJEgAAAA==.Redren:BAAALgADCgIJAgAAAA==.Reegrets:BAAALgAECggJDQAAAA==.Reena:BAAALgADCgIJAwAAAA==.Regeth:BAAALgAECgkJDgAAAA==.Regiplague:BAAALgAECgYJCwAAAA==.Regretty:BAAALgAECggJDQABLgAECggJDQAJAAAAAA==.Renthar:BAAALgADCgUJBQAAAA==.Renzdingo:BAAALgAECgkJDwAAAA==.Repete:BAAALgAECgUJDgAAAA==.Resyek:BAABLgAECn85AAIIAAgJOyQXHACzAgAIAAgJOyQXHACzAgAAAA==.Reverendgank:BAAALgAECgEJAQAAAA==.',
Rh='Rhaxanna:BAAALgADCgYJBgAAAA==.',
Ri='Rick:BAAALgAFFAMJAwAAAA==.Rickheaddk:BAAALgADCgEJAgAAAA==.Riivan:BAABLgAECn8sAAIiAAkJZRQ7NQAEAgAiAAkJZRQ7NQAEAgAAAA==.Rini:BAAALgAECgkJEQABLgABCgYJCwAJAAAAAA==.Rivian:BAAALgADCgIJAgABLgAECgEJAQAJAAAAAA==.',
Ro='Robot:BAABLgAECn8oAAIEAAgJUBGoPQB5AQAEAAgJUBGoPQB5AQAAAA==.Roguè:BAAALgAECgEJAQABLgAFFAEJAQAJAAAAAA==.Rokmog:BAAALgAECggJEAAAAA==.Rollinburn:BAAALgADCgYJCQAAAA==.Romanoff:BAAALgAECgEJAQABLgAECgkJIAAdAI0SAA==.Roxanol:BAAALgADCgEJAQABLgAECgkJPQASACUaAA==.',
Ru='Rumbrave:BAAALgAECgYJCwAAAA==.Rumtumtugger:BAAALgADCgkJCQAAAA==.',
Rx='Rxqüeen:BAAALgAECgEJAQAAAA==.',
['Rá']='Ráyune:BAAALgADCgcJBwAAAA==.',
Sa='Sackos:BAAALgAECgEJAgAAAA==.Sadpanda:BAAALgADCgUJCAAAAA==.Saffronspark:BAAALgADCgkJHwABLgAECgkJTgAgAMMiAA==.Sainsei:BAABLgAECn8fAAMdAAcJcgXVUQC7AAAdAAcJtwLVUQC7AAAgAAUJBAceZQCNAAAAAA==.Saith:BAAALgAECgEJBgAAAA==.Samasear:BAABLgAECn8UAAIXAAgJ0w8wMgDjAQAXAAgJ0w8wMgDjAQABLgAFFAgJIQAhANMeAA==.Sandwitch:BAABLgAECn9DAAMiAAkJLRjALwAZAgAiAAkJLRjALwAZAgAHAAIJmxB0UwB0AAAAAA==.Sanoa:BAABLgAFFH8JAAIaAAQJywT1DQDfAAAaAAQJywT1DQDfAAAAAA==.Sargatana:BAABLgAECn9CAAIdAAkJ7iB/BAD9AgAdAAkJ7iB/BAD9AgAAAA==.Sars:BAABLgAECn80AAMEAAgJKyU7BQBXAwAEAAgJKyU7BQBXAwAgAAMJGhO3XwCbAAAAAA==.Sauronxd:BAAALgAECgUJCAAAAA==.',
Sc='Scalion:BAABLgAECn8nAAMNAAgJOR7wJAA6AgANAAgJOR7wJAA6AgAMAAQJ+BG9SwDAAAABLgAFFAQJBQATAOIVAA==.Scarne:BAAALgAECgIJAgAAAA==.Schrodinger:BAABLgAECn8gAAIUAAgJuAp8IAAQAQAUAAgJuAp8IAAQAQAAAA==.Scravenhoof:BAAALgAECgYJBgAAAA==.',
Se='Seira:BAAALgAECgEJAgABLgAECgkJSgADAFMfAA==.Selunee:BAAALgADCgEJAQAAAA==.Sepharad:BAAALgADCggJEgAAAA==.Severum:BAABLgAECn8+AAIlAAkJYh0aBwCVAgAlAAkJYh0aBwCVAgAAAA==.',
Sh='Shabang:BAAALgAFFAEJAQAAAA==.Shadowtiger:BAABLgAECn8wAAILAAkJag3sTgC1AQALAAkJag3sTgC1AQAAAA==.Shadrad:BAACLgAFFH8LAAITAAUJhSFnIQCCAQATAAUJhSFnIQCCAQAuAAQKfxsAAhMACQnFJdsIACMDABMACQnFJdsIACMDAAAA.Shamanor:BAAALgAECgcJCAAAAA==.Shammoo:BAAALgAECgIJBAABLgAFFAgJKgATAPkXAA==.Shantz:BAABLgAECn8sAAIRAAgJVxRdHAB3AQARAAgJVxRdHAB3AQAAAA==.Shiban:BAABLgAECn8YAAIOAAkJIxClEwAJAgAOAAkJIxClEwAJAgAAAA==.Shirtless:BAAALgAECggJEQAAAA==.Shockra:BAABLgAECn8dAAIcAAkJ4xegIwDJAQAcAAkJ4xegIwDJAQAAAA==.Shokalypse:BAAALgADCgEJAQAAAA==.Shortbuss:BAAALgADCgYJEgAAAA==.',
Si='Sige:BAAALgADCgYJBgAAAA==.Sillygoose:BAAALgADCgkJDwAAAA==.Silverfox:BAAALgADCgMJAQABLgAECgkJPgAIAFYiAA==.Silx:BAABLgAECn8VAAMDAAcJMBE8IQCJAQADAAcJMBE8IQCJAQACAAEJoBZEXQA/AAAAAA==.Simvastatin:BAAALgADCgQJBAAAAA==.Sinterdeath:BAAALgAECgIJAgAAAA==.Sithiry:BAAALgAECgEJAQAAAA==.',
Sk='Skik:BAAALgAECgcJBwAAAA==.Skulltide:BAAALgADCgcJCQAAAA==.',
Sl='Slaggz:BAAALgADCgQJBAAAAA==.Slamvoke:BAAALgAECgYJBgAAAA==.Slaté:BAAALgAECgEJAgABLgAECgMJBQAJAAAAAA==.Slowrot:BAAALgAECgQJBQABLgAFFAMJBwATAFUaAA==.Slushpuppy:BAAALgAFFAEJAQAAAA==.Slâte:BAAALgAFFAEJAgAAAA==.',
Sm='Smiteasaurus:BAAALgAECgEJAQAAAA==.Smokkie:BAABLgAFFH8FAAITAAQJ4hVJPwAsAQATAAQJ4hVJPwAsAQAAAA==.Smorthian:BAAALgAECgcJDQAAAA==.',
Sn='Snarll:BAAALgADCgEJAQAAAA==.Sniffinsteak:BAABLgAECn8bAAMgAAkJGiG9BgDeAgAgAAkJGiG9BgDeAgAEAAEJtws2xgAlAAAAAA==.',
So='Solas:BAAALgADCgYJBgAAAA==.Somaliabiggs:BAAALgAECgYJCgAAAA==.Sonar:BAAALgADCgYJBgABLgAECgkJPAAKAJclAA==.Sonuvabitxh:BAAALgADCgQJBAAAAA==.Sorraba:BAABLgAFFH8JAAIIAAQJMwKwjgC7AAAIAAQJMwKwjgC7AAABLgAFFAQJEAADAD8UAA==.Sorrabo:BAACLgAFFH8QAAIDAAQJPxTdJQAdAQADAAQJPxTdJQAdAQAuAAQKfyIABAMACQn3Gd4LALECAAMACQn3Gd4LALECAAEAAwm7A79lAEsAAAIAAQkpA2WYACEAAAAA.Sorraug:BAAALgAFFAIJAgABLgAFFAQJEAADAD8UAA==.Soryan:BAACLgAFFH8IAAITAAQJWALvegDAAAATAAQJWALvegDAAAAuAAQKfxoAAhMACAk4B9OVAFEBABMACAk4B9OVAFEBAAAA.Sosalkin:BAAALgAECgcJEQAAAA==.Souls:BAACLgAFFH8VAAIiAAUJ8B3fOwBdAQAiAAUJ8B3fOwBdAQAuAAQKfx4ABCIABwnhIyYXAMkCACIABwnhIyYXAMkCACgAAQkAAPIfAHIAAAcAAQm1GkhiAEoAAAAA.',
Sp='Spankenstine:BAABLgAECn8kAAMTAAkJHRcMRgD0AQATAAkJHRcMRgD0AQASAAUJowh+YwDuAAABLgABCgYJCwAJAAAAAA==.Spannky:BAAALgAECgcJEgABLgAECggJPAAEAJYkAA==.',
Sq='Squeaks:BAAALgAECgkJAQAAAA==.Squishÿ:BAAALgAECgYJDwAAAA==.',
St='Starshriek:BAAALgADCgcJBwAAAA==.Stinkydeathy:BAAALgAECgIJAwABLgAECgYJHQAdAMwYAA==.Stinkyfree:BAABLgAECn8dAAMdAAYJzBjSLgCcAQAdAAYJzBjSLgCcAQAgAAEJQROtBQA7AAAAAA==.Stinkynatto:BAAALgADCgYJBgABLgAECgYJHQAdAMwYAA==.Stormcharred:BAABLgAECn8eAAIIAAgJ6SCgKADQAgAIAAgJ6SCgKADQAgAAAA==.Stormknight:BAAALgAECgUJEAAAAA==.Stormpoo:BAAALgAECgEJAQAAAA==.Straka:BAABLgAECn8fAAIFAAkJERIZPgCrAQAFAAkJERIZPgCrAQAAAA==.',
Su='Suffers:BAAALgAECgEJAQAAAA==.Sultanae:BAAALgAECgQJBAAAAA==.Sunbearr:BAAALgAECgEJAQAAAA==.Suneater:BAAALgAECgEJAgAAAA==.Sunmane:BAAALgAECgEJAgABLgAECgkJJwAZAGQXAA==.Supaheals:BAAALgAECgEJAQAAAA==.Superdk:BAABLgAFFH8IAAIhAAQJkhb+CwA7AQAhAAQJkhb+CwA7AQABLgAFFAgJFQATAOIaAA==.Superdruid:BAAALgADCgUJBQABLgAFFAgJFQATAOIaAA==.Supermonks:BAAALgAECggJDAABLgAFFAgJFQATAOIaAA==.Superpi:BAABLgAECn8aAAIDAAcJFx5tEwBFAgADAAcJFx5tEwBFAgABLgAFFAgJFQATAOIaAA==.Superret:BAACLgAFFH8VAAITAAgJ4hr9EADnAQATAAgJ4hr9EADnAQAuAAQKfycAAxMACQkGI/gOABYDABMACQkGI/gOABYDABIAAQn7FAmIADsAAAAA.Superskeet:BAACLgAFFH8HAAISAAMJtAsRNgCWAAASAAMJtAsRNgCWAAAuAAQKfyUAAhIACAl3F54iAPABABIACAl3F54iAPABAAAA.Superwar:BAAALgAECgkJCQABLgAFFAgJFQATAOIaAA==.',
Sv='Svetllama:BAAALgADCggJCAAAAA==.',
Sw='Swaggbag:BAAALgADCgEJAQAAAA==.Swiftia:BAABLgAECn8VAAMjAAYJlBZYOwBzAQAjAAYJjhRYOwBzAQALAAUJAg0HxQC9AAAAAA==.Swiftybutt:BAAALgAECggJCgAAAA==.',
Sy='Sylphièl:BAACLgAFFH8UAAMGAAUJDgdfBgALAQAGAAUJDgdfBgALAQAmAAEJqQKTEwAsAAAuAAQKfygAAwYACAkwDoULAHgBACYACAmbCq8EALkBAAYACAlDDYULAHgBAAAA.Syncere:BAAALgAFFAIJAgAAAA==.Synhunt:BAAALgAFFAEJAgAAAA==.Syrene:BAAALgAECgMJBgAAAA==.',
Ta='Tandarì:BAACLgAFFH8ZAAITAAUJWB/rMABQAQATAAUJWB/rMABQAQAuAAQKfyIAAhMACQmjHqoPABEDABMACQmjHqoPABEDAAAA.Tano:BAAALgAECgUJCQABLgAECgkJPgAIAFYiAA==.Tanparo:BAAALgAECgMJAwAAAA==.Tarick:BAAALgAECgYJCAAAAA==.Tasty:BAAALgAECgQJCwAAAA==.Tawnii:BAAALgADCgcJEgAAAA==.Tazath:BAAALgAECgEJAwAAAA==.Taírn:BAABLgAECn8UAAQWAAYJzwqCGQCIAAAPAAUJrQusRADMAAAWAAYJpAaCGQCIAAAVAAEJpwRwQwAgAAAAAA==.',
Te='Tehpredator:BAAALgAFFAMJAwABLgAFFAQJEAADAD8UAA==.Teilin:BAACLgAFFH8gAAIQAAgJ2B4vAwCqAgAQAAgJ2B4vAwCqAgAuAAQKfyIAAhAACQmQI7MEACcDABAACQmQI7MEACcDAAAA.Tenderloin:BAAALgAECggJDAAAAA==.Teralynn:BAAALgAECgEJAgAAAA==.Terryisgreat:BAAALgAECgEJAQABLgAECgcJFgASAPETAA==.',
Th='Thalendor:BAAALgAECgIJAgAAAA==.Theaterthug:BAAALgAECgIJAgAAAA==.Thehulkster:BAAALgAECgMJAwAAAA==.Thetinman:BAAALgAECgEJAQAAAA==.Thevelo:BAAALgAECgIJAgABLgAECgcJFgAOAM4TAA==.Thewhole:BAAALgAFFAMJAQAAAA==.Theßigshot:BAABLgAECn8VAAIFAAYJICPAIgAyAgAFAAYJICPAIgAyAgAAAA==.Thoseheals:BAAALgADCgQJBAAAAA==.Thunderskeet:BAACLgAFFH8KAAINAAMJARmCXQDXAAANAAMJARmCXQDXAAAuAAQKfzwAAw0ACQkFJfQDAEcDAA0ACQkFJfQDAEcDAAwABwlYHRAUADICAAAA.Thundurus:BAACLgAFFH8QAAIcAAYJpxA/JwD5AAAcAAYJpxA/JwD5AAAuAAQKfyUAAhwACAm9FmY3AFsBABwACAm9FmY3AFsBAAAA.',
Ti='Timmayy:BAABLgAECn8kAAIiAAgJCBZ5OQAmAgAiAAgJCBZ5OQAmAgAAAA==.Tindrill:BAABLgAECn8yAAIkAAkJfSXYAAByAwAkAAkJfSXYAAByAwAAAA==.Tireiron:BAAALgADCgYJBgAAAA==.',
To='Tomraedisk:BAACLgAFFH8FAAIXAAQJegfnKwAEAQAXAAQJegfnKwAEAQAuAAQKfxkAAhcACQmJG8MWADgCABcACQmJG8MWADgCAAAA.Totemagoat:BAACLgAFFH8iAAMQAAcJdBYdAgBTAQAQAAcJdBYdAgBTAQAcAAUJ+hCJJwD3AAAuAAQKfzQAAxwACQkJHdYYABwCABwACAnQG9YYABwCABAACQmqFNgsANcBAAAA.Totemlyfine:BAABLgAECn80AAMQAAgJlSIpEADQAgAQAAgJlSIpEADQAgAcAAQJMBUgYQDCAAAAAA==.Totesmugoats:BAAALgAECggJEgAAAA==.Toxicshock:BAAALgADCgEJAQAAAA==.',
Tr='Traprkeepr:BAAALgADCgcJEgAAAA==.Treechains:BAABLgAECn8WAAMQAAYJ8hcBUAByAQAQAAYJ8hcBUAByAQAcAAEJZQPtkQAlAAAAAA==.Treefist:BAAALgAFFAEJAgAAAA==.Treeshield:BAAALgADCgYJBgAAAA==.Trickster:BAAALgAECgEJAgAAAA==.Triplex:BAAALgAECgQJBAAAAA==.Truth:BAAALgADCgcJDQAAAA==.',
Ts='Tsumuji:BAAALgAECgEJAQAAAA==.',
Tu='Turbobis:BAAALgAECgIJAgAAAA==.',
Tw='Twentyfour:BAACLgAFFH8MAAIFAAMJJgV1TgCGAAAFAAMJJgV1TgCGAAAuAAQKfxUAAgUABwmGEOVdADgBAAUABwmGEOVdADgBAAAA.Twigberry:BAAALgAECgUJCAAAAA==.',
Ty='Tygra:BAAALgAECgcJDgAAAA==.Typeshxxt:BAAALgADCgEJAQAAAA==.Tytanea:BAAALgAECgMJBAAAAA==.',
['Tø']='Tøqa:BAAALgAFFAEJAQAAAA==.',
Uh='Uhnderstood:BAABLgAECn8mAAIEAAkJjh1qEABUAgAEAAkJjh1qEABUAgAAAA==.',
Un='Undeadmonks:BAACLgAFFH8OAAIdAAMJSBcpNADXAAAdAAMJSBcpNADXAAAuAAQKf0kAAx0ACQliHqkHALsCAB0ACQliHqkHALsCACAAAwl2CsRlAHYAAAAA.',
Uv='Uvaweez:BAAALgAECgMJAwAAAA==.',
Va='Vahe:BAAALgAECgEJAQAAAA==.Vale:BAAALgAECgUJBgAAAA==.Valeshot:BAACLgAFFH8FAAILAAMJwAH0fQCcAAALAAMJwAH0fQCcAAAuAAQKfyYAAgsACQn9CW4/ALEBAAsACQn9CW4/ALEBAAAA.Valkillrie:BAAALgADCgcJBwAAAA==.Valkyrié:BAAALgAECgIJAwAAAA==.Vall:BAAALgAECggJDAAAAA==.Valssra:BAABLgAECn8XAAIIAAcJmAoNsAAhAQAIAAcJmAoNsAAhAQAAAA==.Vampiricvrus:BAAALgAECgQJBgAAAA==.Vashi:BAABLgAECn86AAITAAkJQxb7UgDQAQATAAkJQxb7UgDQAQAAAA==.',
Ve='Vedbow:BAACLgAFFH8UAAQOAAQJmiNcDQBaAQAOAAQJ0iFcDQBaAQALAAMJMBUdZgDZAAAjAAEJgA+6JwBNAAAuAAQKfxwABAsACQnIIh4UAJUCAAsACAm5IR4UAJUCACMABAnyHyc8AG4BAA4AAwldIPY1AAUBAAAA.Vedronas:BAABLgAECn8XAAITAAcJaiOcHgC0AgATAAcJaiOcHgC0AgAAAA==.Velillys:BAAALgAECgEJAQAAAA==.Venlii:BAAALgADCgEJAQAAAA==.Veos:BAAALgAECgEJAQAAAA==.Verdict:BAABLgAECn8WAAIQAAgJYxECPQC6AQAQAAgJYxECPQC6AQAAAA==.Veritae:BAAALgAECgcJCQAAAA==.Vern:BAABLgAECn8YAAMDAAgJ+BdiJQCkAQADAAgJ+BdiJQCkAQACAAIJgwYoWQBWAAAAAA==.Vernaar:BAAALgAECgMJAwABLgAECggJGAADAPgXAA==.Vernah:BAABLgAECn8VAAISAAgJ1Rk8GABGAgASAAgJ1Rk8GABGAgABLgAECggJGAADAPgXAA==.Verybad:BAABLgAECn9EAAIIAAYJpRwgewDbAQAIAAYJpRwgewDbAQAAAA==.',
Vo='Voidify:BAAALgADCgEJAgAAAA==.Voodoodrood:BAAALgADCgIJAgAAAA==.',
['Vè']='Vèronique:BAAALgAECgYJBgAAAA==.',
Wa='Waambler:BAAALgAECgIJAgAAAA==.Waamchifu:BAABLgAECn85AAIdAAkJhyN4AgA2AwAdAAkJhyN4AgA2AwAAAA==.Wack:BAAALgADCgUJBgAAAA==.Waka:BAAALgADCgcJCwAAAA==.Waltersight:BAACLgAFFH8JAAILAAQJNg7vBgDiAAALAAQJNg7vBgDiAAAuAAQKfxcAAgsACQlvFz8pADkCAAsACQlvFz8pADkCAAAA.Warsheep:BAAALgADCgQJAQAAAA==.',
We='Wednesdayy:BAAALgAECgEJAQAAAA==.Wesker:BAAALgADCgYJBgAAAA==.Westavia:BAAALgAECgEJAQABLgAFFAMJBwATAFUaAA==.Wewabear:BAAALgADCgQJBAAAAA==.',
Wh='Whateley:BAAALgAECgcJCgAAAA==.Whosthetänk:BAAALgAECgEJAQAAAA==.',
Wi='Wisebrownguy:BAABLgAECn8tAAITAAkJHR9rFQDCAgATAAkJHR9rFQDCAgABLgAFFAQJBQAXAHoHAA==.Wisperia:BAAALgADCgYJBgAAAA==.',
Wo='Worgana:BAAALgAECgMJAwAAAA==.Wormchild:BAAALgADCgQJBAAAAA==.',
Wu='Wukòng:BAAALgADCgEJAQAAAA==.',
Xe='Xercuul:BAAALgAECgcJEQAAAA==.',
Xi='Xikar:BAAALgAECgQJCAAAAA==.',
Xp='Xplosiv:BAABLgAECn8WAAILAAgJHSJSAQDVAQALAAgJHSJSAQDVAQABLgAFFAcJIAAQAL0eAA==.',
Xy='Xylophonejoe:BAAALgAECgYJCQAAAA==.',
Ye='Yeddy:BAAALgADCgcJBwAAAA==.Yel:BAAALgADCgYJCAAAAA==.',
Yo='Yoel:BAAALgADCgEJAQAAAA==.Yourdad:BAAALgAECgYJEAABLgAFFAEJAQAJAAAAAA==.',
Yu='Yudah:BAACLgAFFH8JAAQOAAMJuRQOIgDJAAAOAAMJDQ4OIgDJAAALAAIJzxwWgACYAAAjAAEJ3AAhPQAnAAAuAAQKfy0ABA4ACAmgHUIYAN8BAA4ACAkZGUIYAN8BACMABglUFtYTACQBAAsABwlgD1KWABMBAAAA.Yuta:BAAALgADCgcJBgAAAA==.',
Za='Zalrei:BAAALgAECgEJAQAAAA==.Zalupa:BAAALgAECgIJAgAAAA==.Zanghonghua:BAABLgAECn9OAAMgAAkJwyK7AwAkAwAgAAkJwyK7AwAkAwAEAAEJSRXWZAA+AAAAAA==.Zarinaria:BAABLgAECn8cAAINAAYJ2Q7qfQAvAQANAAYJ2Q7qfQAvAQAAAA==.',
Ze='Zetsumei:BAAALgADCgMJAwAAAA==.',
Zh='Zhael:BAABLgAECn8hAAINAAkJCRo3JwAvAgANAAkJCRo3JwAvAgAAAA==.',
Zi='Zitizen:BAAALgADCgYJBwAAAA==.',
Zo='Zodstrike:BAABLgAECn8xAAMNAAkJbwUiiwAKAQANAAkJbwUiiwAKAQAMAAQJnwIXWACGAAAAAA==.Zomara:BAAALgAECgMJCgAAAA==.Zooboo:BAABLgAECn8XAAIXAAkJURcjJgDHAQAXAAkJURcjJgDHAQAAAA==.Zophie:BAAALgADCgEJAQAAAA==.',
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
