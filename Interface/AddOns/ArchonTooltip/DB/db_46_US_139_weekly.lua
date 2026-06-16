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

local lookup = {'Priest-Holy','Priest-Shadow','Priest-Discipline','Monk-Mistweaver','Druid-Restoration','Rogue-Assassination','Warlock-Destruction','Mage-Frost','Unknown-Unknown','DeathKnight-Unholy','Hunter-BeastMastery','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-Survival','Evoker-Augmentation','DeathKnight-Blood','Paladin-Holy','Paladin-Retribution','Paladin-Protection','Evoker-Preservation','Evoker-Devastation','Warrior-Fury','Druid-Guardian','Druid-Feral','Shaman-Restoration','Shaman-Enhancement','Druid-Balance','Shaman-Elemental','Monk-Brewmaster','Rogue-Subtlety','Mage-Arcane','DeathKnight-Frost','Warlock-Demonology','Hunter-Marksmanship','Rogue-Outlaw','Monk-Windwalker','Warrior-Arms','Warrior-Protection','Mage-Fire','Warlock-Affliction',}
local provider = {region='US',realm='LaughingSkull',name='US',type='weekly',zone=46,date='2026-06-13',data={Ab='Abeblinken:BAAALgAECgIJAgAAAA==.Ablucia:BAAALgADCgUJCQAAAA==.Abomb:BAAALgAECgEJAQAAAA==.Abotharn:BAAALgADCgUJBQAAAA==.',
Ac='Acanaline:BAAALgAECgEJAQAAAA==.Achannara:BAAALgADCgcJBwAAAA==.',
Ae='Aennisong:BAAALgAECgUJCAAAAA==.Aeoliana:BAAALgAECggJEgAAAA==.',
Aj='Ajier:BAACLgAFFH8NAAIBAAQJ6xb4FQAKAQABAAQJ6xb4FQAKAQAuAAQKfy0AAgEACQkpFqMWACcCAAEACQkpFqMWACcCAAAA.',
Al='Aleraz:BAACLgAFFH8YAAMBAAYJqBaPDAB6AQABAAUJkRqPDAB6AQACAAUJhBPTGAAbAQAuAAQKfz8ABAIACQn7Hy4GAO8CAAIACQn7Hy4GAO8CAAEABwnbIOEVAC0CAAMAAwkmBzRhAHAAAAAA.Allcapwne:BAAALgAECgcJCwAAAA==.Allenduin:BAAALgAECgYJBwAAAA==.Alshau:BAABLgAECn8aAAIEAAcJ0BdfIwCYAQAEAAcJ0BdfIwCYAQAAAA==.Alucart:BAAALgAECgEJAQAAAA==.',
Am='Ambrosia:BAAALgAECgYJDwAAAA==.Amity:BAAALgADCgkJEAABLgAECgkJIQAFAPMdAA==.',
An='Anchoredowl:BAAALgAECgEJAgAAAA==.Anewrbyss:BAAALgAECgUJEAAAAA==.Angela:BAABLgAECn9IAAMDAAkJUx+PBgAUAwADAAkJUx+PBgAUAwACAAEJowy4iAAvAAAAAA==.Anna:BAAALgAECgQJBQAAAA==.Annalunà:BAAALgADCgIJBAAAAA==.Annälise:BAAALgADCgEJAQAAAA==.',
Ap='Apeople:BAACLgAFFH8KAAIGAAQJnhvrBgD4AAAGAAQJnhvrBgD4AAAuAAQKfzAAAgYACQmGIloBACEDAAYACQmGIloBACEDAAAA.Apocalýpsè:BAAALgAECgIJAgAAAA==.Applebottomj:BAAALgAECgMJAwAAAA==.Applebottum:BAAALgAECggJDgAAAA==.Appärition:BAABLgAECn8zAAIHAAgJqCCBAgCMAgAHAAgJqCCBAgCMAgAAAA==.',
Ar='Arleance:BAAALgAECgUJCAAAAA==.Arondael:BAABLgAECn8hAAIGAAgJeRfHBwDUAQAGAAgJeRfHBwDUAQAAAA==.Arsène:BAAALgADCgcJCwAAAA==.',
As='Astroglyde:BAAALgAECgcJCQAAAA==.Aszun:BAAALgADCgUJBQAAAA==.',
Au='Aurialis:BAAALgAECgcJDQAAAA==.',
Av='Avanti:BAABLgAECn9AAAIIAAkJURv1LABjAgAIAAkJURv1LABjAgAAAA==.Avendeloria:BAABLgAECn8aAAIBAAcJFBYtHgDPAQABAAcJFBYtHgDPAQAAAA==.Averyn:BAAALgADCgEJAQAAAA==.',
Az='Azrahn:BAAALgADCgQJBQAAAA==.',
['Aü']='Aüra:BAAALgAECgEJAQABLgAECggJCQAJAAAAAA==.',
Ba='Babybear:BAAALgAECgIJAgAAAA==.Backmoist:BAAALgAECgQJBwAAAA==.Bagmaster:BAACLgAFFH8UAAIBAAUJDCA5CADEAQABAAUJDCA5CADEAQAuAAQKfzgAAgEACQkAJpkCAD4DAAEACQkAJpkCAD4DAAAA.Bahm:BAAALgADCgYJEwAAAA==.Baktolife:BAAALgAECgkJBAAAAA==.Bam:BAAALgAECgQJBQABLgAFFAIJBgAKAJshAA==.Bartholomoo:BAABLgAECn9BAAIKAAkJvyKrDwDtAgAKAAkJvyKrDwDtAgAAAA==.Bayonetta:BAAALgAECgcJDAAAAA==.',
Be='Beeftornado:BAAALgAECgYJBwAAAA==.Belakor:BAAALgADCgIJAgAAAA==.Ber:BAAALgAECgEJAwAAAA==.',
Bi='Bigbusta:BAAALgADCgMJAwAAAA==.Bigmanblasto:BAAALgADCgMJBAAAAA==.Bildros:BAAALgAECgEJAQAAAA==.Birgite:BAAALgAECgYJEAAAAA==.Bizniz:BAAALgAECgYJDAAAAA==.',
Bl='Blastin:BAAALgADCgcJBwAAAA==.Blazefury:BAABLgAECn8YAAILAAYJcwzgpADyAAALAAYJcwzgpADyAAAAAA==.Blazeknight:BAACLgAFFH8FAAIMAAMJIw+uGgDFAAAMAAMJIw+uGgDFAAAuAAQKfy0AAgwACQn9GekVANcBAAwACQn9GekVANcBAAAA.Blazemaker:BAACLgAFFH8IAAIIAAQJ1gLzeQDqAAAIAAQJ1gLzeQDqAAAuAAQKfxoAAggABgk8EIO+AAgBAAgABgk8EIO+AAgBAAAA.Blazemaster:BAAALgAECgQJCQAAAA==.Blinduru:BAACLgAFFH8SAAINAAQJNyI2JgCJAQANAAQJNyI2JgCJAQAuAAQKfzkAAg0ACQltJa4CAFwDAA0ACQltJa4CAFwDAAAA.Blitz:BAAALgAECgIJAgAAAA==.Blocktor:BAAALgAECgMJAwABLgAECgYJHAANANkOAA==.Bloodsylf:BAAALgAECgkJAgABLgAECgcJFgAOAM4TAA==.Bluberriez:BAAALgAECgYJBgAAAA==.',
Bo='Bobbiepines:BAAALgAECgMJAwAAAA==.Bonez:BAAALgAECgMJAwAAAA==.Book:BAAALgAECgkJEwAAAA==.Bookie:BAAALgAECgcJCAAAAA==.Booza:BAAALgAECgIJAgAAAA==.Borkenshwang:BAAALgADCgYJCwAAAA==.Boydik:BAAALgAECgQJBgAAAA==.',
Bp='Bpain:BAAALgAECgMJAwAAAA==.Bpaìn:BAABLgAECn8tAAIPAAkJxxuHDACRAgAPAAkJxxuHDACRAgAAAA==.',
Br='Breandán:BAAALgADCgEJAQAAAA==.Brewlïth:BAAALgAECgIJAgABLgAFFAYJEAAQAMceAA==.Brewmaester:BAAALgAECgEJAgAAAA==.Brink:BAABLgAECn8YAAIIAAkJvA+NWQDNAQAIAAkJvA+NWQDNAQAAAA==.Brojac:BAAALgAECgcJDgAAAA==.Brokil:BAAALgADCggJDAAAAA==.Brolic:BAAALgAECgQJBAAAAA==.Bromaster:BAAALgAECgQJBQAAAA==.Brones:BAAALgAECgkJAwAAAA==.Brossiere:BAABLgAECn8hAAQRAAgJERvxNAB7AQARAAUJZRrxNAB7AQASAAYJoxeFigBZAQATAAUJVRcjIwD4AAAAAA==.Brotemic:BAAALgAECgYJDgAAAA==.Brovine:BAAALgAECgEJAQAAAA==.Bru:BAACLgAFFH8NAAIBAAUJ2BicDQBrAQABAAUJ2BicDQBrAQAuAAQKfyoAAgEACQl1HOwMAIYCAAEACQl1HOwMAIYCAAAA.Brutalizèr:BAAALgADCgYJBgABLgAECgEJAQAJAAAAAA==.',
Bt='Bt:BAAALgAECgUJCgAAAA==.',
Bu='Bubblegal:BAAALgAECgQJCQAAAA==.Bullsmcgee:BAABLgAECn86AAMKAAkJlyWKAwBmAwAKAAkJlyWKAwBmAwAQAAEJAAAXQwA9AAAAAA==.Burningtree:BAABLgAECn8eAAIIAAkJ6QtkZQCwAQAIAAkJ6QtkZQCwAQAAAA==.Burny:BAAALgADCgEJAQAAAA==.Burrder:BAAALgADCggJCAAAAA==.Bustdown:BAAALgADCggJDwAAAA==.Buttslapper:BAAALgADCggJCAAAAA==.',
['Bö']='Börck:BAAALgADCgUJBQAAAA==.',
['Bø']='Bøb:BAAALgAECggJCwAAAA==.',
Ca='Camamoonmana:BAABLgAECn8aAAIFAAkJ3BMaOAC0AQAFAAkJ3BMaOAC0AQAAAA==.Captcorndog:BAACLgAFFH8FAAIPAAMJ2wpHRwCpAAAPAAMJ2wpHRwCpAAAuAAQKfygABA8ACAlAFfEiAMEBAA8ACAlAFfEiAMEBABQABQnzA3k4AKcAABUAAQkAALRAAC8AAAAA.Caskket:BAAALgAECgkJEQAAAA==.Castreytid:BAAALgAECgcJDQABLgAFFAQJBQAWAHoHAA==.Catdog:BAABLgAECn8iAAIXAAYJFRjyIgAyAQAXAAYJFRjyIgAyAQAAAA==.Catechism:BAABLgAECn8rAAMRAAkJkR7QBgAdAwARAAkJkR7QBgAdAwASAAQJaghuIwGKAAAAAA==.',
Ce='Cemeo:BAABLgAECn8UAAIUAAcJiBcTFgDsAQAUAAcJiBcTFgDsAQAAAA==.Cerberusalfa:BAACLgAFFH8WAAIMAAUJZSU7BQCzAQAMAAUJZSU7BQCzAQAuAAQKfzcAAgwACQkTJk4BAGkDAAwACQkTJk4BAGkDAAAA.',
Ch='Chaintazer:BAAALgADCgYJBgABLgAFFAQJBQAWAHoHAA==.Chewbaca:BAAALgAECgEJAwAAAA==.Chickennuggi:BAACLgAFFH8LAAIIAAQJYRE8XwAtAQAIAAQJYRE8XwAtAQAuAAQKfyoAAggACAmsHZoqAG0CAAgACAmsHZoqAG0CAAAA.Chinchilla:BAAALgADCgcJBwAAAA==.Chiphoof:BAABLgAECn8mAAIYAAkJZBfFCAA5AgAYAAkJZBfFCAA5AgAAAA==.Chocofox:BAABLgAECn8hAAMZAAkJmSFBBQBcAwAZAAkJmSFBBQBcAwAaAAEJ0ANrRQAhAAAAAA==.Chokemagic:BAAALgAFFAIJAgAAAA==.Chopndot:BAAALgAECgEJBAAAAA==.Chozen:BAAALgADCgcJBwAAAA==.Chrill:BAABLgAECn8cAAINAAYJchdjawBJAQANAAYJchdjawBJAQAAAA==.',
Cl='Claraabun:BAAALgAECgUJBQABLgAFFAYJFgARAMYTAA==.Clarabuns:BAACLgAFFH8WAAIRAAYJxhOKEACsAQARAAYJxhOKEACsAQAuAAQKfx8AAxEACQnGF2YlAPsBABEACQnGF2YlAPsBABIABQl1F3p9AHEBAAAA.Clarasbuns:BAAALgAECgMJAwABLgAFFAYJFgARAMYTAA==.Clawdragoon:BAECLgAFFH8cAAQbAAUJoQ6aJQD5AAAbAAUJoQ6aJQD5AAAFAAQJhAGKSQCPAAAXAAEJpwJpRAAeAAAuAAQKfzAAAxsACAnVGW0UAG8CABsACAnVGW0UAG8CAAUABQlACN+bAJQAAAAA.',
Co='Coati:BAAALgADCgYJBgAAAA==.Colforbin:BAAALgADCgUJBQAAAA==.Colosie:BAAALgAECgYJEwAAAA==.Comegetpsalm:BAABLgAECn89AAIRAAkJJRqlEQCFAgARAAkJJRqlEQCFAgAAAA==.Cornbreadmat:BAAALgADCgcJDQAAAA==.',
Cr='Creamsock:BAAALgAECgQJCQAAAA==.Creatlach:BAACLgAFFH8fAAIZAAcJvR5iBgBUAgAZAAcJvR5iBgBUAgAuAAQKfzoAAxkACQmKG8UbAGoCABkACQmKG8UbAGoCABwAAwlXE3BjALUAAAAA.Creatlachlol:BAAALgAECgkJCQABLgAFFAcJHwAZAL0eAA==.Creech:BAAALgADCgIJAgAAAA==.Creeptoken:BAAALgAECgEJAQAAAA==.Crucifilth:BAAALgADCgYJDAAAAA==.Cryopathy:BAAALgAECgYJDgAAAA==.Crypty:BAABLgAECn8dAAMcAAkJggwLMwBtAQAcAAkJggwLMwBtAQAZAAUJrREiXQAWAQAAAA==.',
Cy='Cyaniidee:BAAALgADCgcJBwAAAA==.Cyraxx:BAAALgADCgMJAwAAAA==.Cyrusdragon:BAAALgAECgYJBgAAAA==.Cyrussham:BAAALgAECgEJAQAAAA==.Cytherea:BAABLgAECn8pAAISAAgJig/fhgBfAQASAAgJig/fhgBfAQAAAA==.',
Da='Daddybod:BAABLgAECn8gAAIdAAkJjRImHgCyAQAdAAkJjRImHgCyAQAAAA==.Dainnan:BAAALgADCgEJAQAAAA==.Dalinek:BAAALgAECgUJBQAAAA==.Danicarkel:BAAALgAECggJDQAAAA==.Darkcallum:BAAALgAECgMJBAAAAA==.Darktaynt:BAAALgAECgMJBQAAAA==.Darthfox:BAAALgAECgMJBQAAAA==.',
De='Deadsean:BAAALgAECgUJDAAAAA==.Deathsyn:BAABLgAFFH8JAAIKAAQJzRnPUwBGAQAKAAQJzRnPUwBGAQAAAA==.Deathtracker:BAABLgAECn8aAAILAAgJXw5oYQB/AQALAAgJXw5oYQB/AQAAAA==.Deathwarden:BAAALgAECggJEwAAAA==.Deathñdk:BAAALgADCgEJAQAAAA==.Debuffed:BAAALgAECgEJAQAAAA==.Delathor:BAAALgAECgcJDgABLgAFFAEJAQAJAAAAAA==.Delimeatear:BAAALgAECgIJAgABLgAECgkJHQACABkcAA==.Demiloss:BAAALgAFFAEJAQABLgAFFAMJBAAJAAAAAA==.Demise:BAACLgAFFH8GAAIIAAQJXBIVWAA4AQAIAAQJXBIVWAA4AQAuAAQKfysAAggACAnWHjoxAK0CAAgACAnWHjoxAK0CAAAA.Demonclem:BAAALgAFFAIJAgAAAA==.Demonskinner:BAAALgADCgUJBQAAAA==.Denzo:BAAALgAECgMJAwAAAA==.Deoxyrybo:BAACLgAFFH8FAAIMAAMJPQocHAC4AAAMAAMJPQocHAC4AAAuAAQKfzsAAwwACQnkGVANAE0CAAwACQnkGVANAE0CAA0ABgmnC5WIABQBAAAA.Destructin:BAAALgAECgEJAQAAAA==.Destructor:BAAALgAECgcJEwAAAA==.Devourera:BAAALgAFFAMJAwABLgAFFAQJEAADAD8UAA==.',
Di='Died:BAAALgADCgMJAwAAAA==.Dilldobaggin:BAAALgADCgQJBAAAAA==.Dinoknight:BAAALgAECgcJBwAAAA==.Dinopriest:BAABLgAECn8XAAICAAcJLRdWJQCeAQACAAcJLRdWJQCeAQAAAA==.Distia:BAAALgAECgcJCgAAAA==.Divinedragon:BAABLgAECn8sAAMCAAkJGhgkEgBDAgACAAkJGhgkEgBDAgADAAcJ5grnLgAoAQAAAA==.Dixoncider:BAAALgAECgQJBgAAAA==.',
Do='Doboy:BAAALgADCgIJAgAAAA==.Donmanuel:BAAALgADCgEJAQAAAA==.',
Dr='Drackaris:BAAALgADCgYJBgAAAA==.Draggo:BAAALgAECgEJAwAAAA==.Drainbamage:BAAALgAECgMJAwAAAA==.Drakin:BAABLgAECn9FAAISAAkJ0CCcDAD+AgASAAkJ0CCcDAD+AgAAAA==.Dreya:BAABLgAECn8aAAIaAAkJDR2UCQAgAgAaAAkJDR2UCQAgAgAAAA==.Dreyas:BAAALgADCgYJBgAAAA==.Drinkcoolaid:BAABLgAECn8fAAIZAAkJnxYZIABLAgAZAAkJnxYZIABLAgAAAA==.Dritzle:BAABLgAECn8aAAMeAAgJBhXKIQDrAQAeAAgJBhXKIQDrAQAGAAQJHgi5EwDEAAAAAA==.Droopapi:BAAALgAECgYJEQAAAA==.',
Du='Durrt:BAAALgADCgcJCAABLgAECgcJLAAFAGsiAA==.Dutchman:BAACLgAFFH8VAAILAAcJEyJRCgAPAgALAAcJEyJRCgAPAgAuAAQKfxwAAgsACAkNIWYIAAsDAAsACAkNIWYIAAsDAAAA.',
Eh='Ehhmuh:BAAALgAECgYJCgAAAA==.Ehlumii:BAABLgAECn8UAAIEAAYJRSRvDgBvAgAEAAYJRSRvDgBvAgAAAA==.',
Ei='Eiffel:BAAALgADCgUJBQAAAA==.',
El='Eldrene:BAABLgAECn80AAMIAAkJXh5mGgC5AgAIAAkJXh5mGgC5AgAfAAEJ7hOWHAA6AAAAAA==.Elethil:BAAALgADCgEJAgAAAA==.Elfstomper:BAAALgADCggJCwAAAA==.Elitepaladin:BAABLgAECn8nAAIRAAkJGBbfIQAPAgARAAkJGBbfIQAPAgAAAA==.Ellexi:BAAALgAECgYJDAAAAA==.Elrai:BAAALgAECgIJAwAAAA==.Elyseia:BAABLgAECn8gAAILAAkJgwZMhwArAQALAAkJgwZMhwArAQAAAA==.',
Em='Empkin:BAAALgAECgcJEwAAAA==.',
En='Enof:BAAALgADCgIJAgAAAA==.Enpower:BAAALgADCgYJBgABLgAFFAEJAQAJAAAAAA==.',
Ep='Epicsause:BAAALgAECgkJCgAAAA==.',
Er='Erelor:BAAALgADCgMJAwAAAA==.',
Es='España:BAECLgAFFH8JAAIQAAUJbxFdHQD2AAAQAAUJbxFdHQD2AAAuAAQKfy0ABBAACQlOGj0KAHYCABAACQlOGj0KAHYCACAABQlGEcAbAO0AAAoAAQkAAMClAQAAAAAA.Españaluna:BAEALgAECgcJBgABLgAFFAUJCQAQAG8RAA==.Españamor:BAEALgAECgkJCAABLgAFFAUJCQAQAG8RAA==.Essdeath:BAAALgAECgEJAQAAAA==.',
Ex='Excrucio:BAAALgADCgYJBgAAAA==.',
Ez='Ezpain:BAAALgAECgQJBQAAAA==.',
Fa='Farael:BAAALgAECgcJBAAAAA==.Farmerbrown:BAAALgAECgMJBQABLgAFFAMJBwASAFUaAA==.Fatalmann:BAACLgAFFH8IAAMUAAQJKQlLIwB+AAAUAAMJ4wFLIwB+AAAVAAIJrAUXCwBpAAAuAAQKfxYAAxUACQnMD5kVAJUBABUABwmoD5kVAJUBABQABgk2D9EbAB0BAAAA.Fatalminn:BAAALgAECgUJCQAAAA==.Fathergob:BAAALgADCgEJAQAAAA==.Fatty:BAAALgADCgYJBgAAAA==.',
Fe='Fenty:BAAALgADCgEJAQAAAA==.Feralhorn:BAAALgAECgEJAQAAAA==.',
Fi='Fingerz:BAAALgADCgIJAgAAAA==.Fintan:BAAALgAECgcJDAABLgAFFAcJHwAZAL0eAA==.',
Fl='Flarestrasz:BAAALgADCgUJCQAAAA==.Flexxar:BAAALgAECgEJAgAAAA==.Flinwazzart:BAAALgADCgcJBwAAAA==.Flutterby:BAAALgADCgcJDQABLgAECgkJOQACAJwJAA==.Flèxion:BAACLgAFFH8OAAIKAAUJ2R9hRgBhAQAKAAUJ2R9hRgBhAQAuAAQKfygAAgoACAkBJTcgAIYCAAoACAkBJTcgAIYCAAAA.',
Fo='Foskin:BAAALgAECgMJBAABLgAFFAQJBQAWAHoHAA==.',
Fr='Frassk:BAABLgAECn9DAAMHAAkJPBsJBgACAgAHAAcJSB0JBgACAgAhAAQJ0hJRzQC2AAAAAA==.Freja:BAAALgADCgMJBgAAAA==.Frigid:BAAALgAECgkJBwAAAA==.Froggystyle:BAAALgAECgYJDgABLgAECggJDgAJAAAAAA==.Frostydru:BAABLgAECn8wAAIYAAgJfiHLBwBUAgAYAAgJfiHLBwBUAgAAAA==.Frozat:BAACLgAFFH8ZAAIUAAgJGxgDBACaAgAUAAgJGxgDBACaAgAuAAQKfygAAxQACAkRI1YEAOYCABQACAkRI1YEAOYCAA8AAQmAEZ5eAEAAAAAA.Frösting:BAAALgADCgcJDgABLgAECgkJRQANAIkfAA==.',
Fu='Fundeedo:BAAALgAFFAIJAwAAAA==.Furballieo:BAAALgADCgIJAgAAAA==.',
Ga='Galadriels:BAAALgAECgQJBAAAAA==.Galianem:BAAALgADCgMJAwAAAA==.Gamora:BAAALgAECgYJCQAAAA==.Gandon:BAAALgAECgQJCAAAAA==.Garbarn:BAABLgAECn8WAAISAAkJ0w+JewB1AQASAAkJ0w+JewB1AQAAAA==.Garonno:BAAALgADCgIJAgAAAA==.',
Ge='Gelystine:BAAALgADCgUJCgAAAA==.Geminirunes:BAAALgADCgYJBgABLgAFFAEJAQAJAAAAAA==.Germaine:BAAALgAECgQJBQAAAA==.',
Gh='Ghabi:BAAALgAECgYJBgAAAA==.Ghauri:BAAALgAECgMJBAAAAA==.',
Gi='Gia:BAABLgAECn8zAAIEAAgJpxvrFABtAgAEAAgJpxvrFABtAgAAAA==.',
Go='Gobx:BAAALgAECgUJBgAAAA==.Golgroth:BAABLgAECn8mAAIWAAkJXgcvOgBcAQAWAAkJXgcvOgBcAQAAAA==.Goodlocktime:BAAALgADCgIJAgABLgAECgYJCAAJAAAAAA==.Goodtimesm:BAAALgAECgYJCAAAAA==.Goodtymes:BAAALgAECgEJAQABLgAECgYJCAAJAAAAAA==.Gorearrow:BAACLgAFFH8MAAILAAUJMRLXPQArAQALAAUJMRLXPQArAQAuAAQKfzAAAwsACQlXItgLAOMCAAsACQlXItgLAOMCACIAAglWB2N6AFkAAAAA.Goretaint:BAAALgAECgYJDwAAAA==.Gorgesh:BAAALgADCgQJBAAAAA==.Gothladriel:BAAALgAECgYJDAAAAA==.Gotpwnedd:BAAALgAECgEJAQAAAA==.Gottamoo:BAABLgAECn8ZAAMXAAkJJwzKKAANAQAXAAkJJwzKKAANAQAbAAEJPQFWkAAaAAAAAA==.',
Gr='Greenstank:BAAALgAECggJDgAAAA==.Grrumpybear:BAABLgAECn9DAAIXAAkJ3xsjBwCCAgAXAAkJ3xsjBwCCAgAAAA==.Grundal:BAAALgADCggJCAAAAA==.',
Gu='Gumbuz:BAAALgAECgQJBgAAAA==.Gunafistya:BAABLgAFFH8HAAIEAAMJZhWZNwC9AAAEAAMJZhWZNwC9AAAAAA==.Gunnaroptiks:BAAALgAECgUJBQABLgAFFAQJGAAdAIsXAA==.Guzzler:BAAALgAECgkJDgAAAA==.',
['Gú']='Gúildarts:BAAALgADCgEJAQAAAA==.',
Ha='Haannarr:BAAALgAECgIJAgAAAA==.Hairymoodini:BAAALgAECgEJAgAAAA==.Hajin:BAAALgAECgYJDwAAAA==.Hankjr:BAAALgAECgEJAwAAAA==.Hanky:BAAALgAECgQJBAAAAA==.Havòk:BAAALgAECggJBwABLgAFFAEJAQAJAAAAAA==.Hawthorn:BAAALgAECgMJCAAAAA==.Hazyblades:BAAALgAECgMJAwAAAA==.',
He='Hektar:BAAALgADCgYJBgAAAA==.Helacookie:BAABLgAECn8ZAAISAAkJMBMdUgDQAQASAAkJMBMdUgDQAQAAAA==.Henso:BAAALgAFFAEJAQAAAA==.Heomors:BAAALgAECgEJAQAAAA==.Hexxan:BAAALgAECgUJEAAAAA==.',
Hi='Hifumi:BAAALgADCgQJBwAAAA==.Hisagu:BAAALgAECgEJAQABLgAECggJFAAKABYbAA==.Hiver:BAAALgAECgQJBgAAAA==.',
Ho='Hoagar:BAAALgAECgcJDAABLgAFFAMJBQAiALkeAA==.Holes:BAAALgAECgEJAgAAAA==.Holier:BAACLgAFFH8JAAISAAMJMxHTagDUAAASAAMJMxHTagDUAAAuAAQKfzkAAhIACQn+FV9FAPQBABIACQn+FV9FAPQBAAAA.Hollows:BAAALgAECgQJBgAAAA==.Holyatrops:BAAALgAECgkJEQABLgAFFAgJJQAhAPoaAA==.Hoochurcooch:BAAALgAECgEJAQAAAA==.Hoppers:BAAALgAECgIJAgABLgAECgcJDwAJAAAAAA==.Hopperstotem:BAAALgAECgcJDwAAAA==.Horuu:BAAALgAECgQJBgAAAA==.Hoyboii:BAAALgADCgYJBgAAAA==.',
Hu='Hulo:BAAALgAECgcJDwAAAA==.Humbled:BAAALgAECgQJBQAAAA==.Hunteress:BAAALgADCgYJBwAAAA==.Huntkoalas:BAAALgAECgMJAwABLgAFFAcJIQAbAHwXAA==.Hurrdurr:BAAALgAECgEJAQAAAA==.',
['Hî']='Hîflax:BAAALgAECgEJAgAAAA==.',
['Hö']='Hölyców:BAAALgADCgQJBAAAAA==.',
Ic='Ichbinstark:BAAALgAECgEJBAAAAA==.',
Id='Idonttcare:BAAALgAECgMJAwAAAA==.',
If='Ifirt:BAAALgAECggJCAAAAA==.',
Ig='Iggnignokt:BAAALgADCgYJBwAAAA==.',
Ih='Ihealnewbs:BAAALgADCgYJDwAAAA==.',
In='Infamus:BAAALgAECgQJCgAAAA==.Invisabull:BAAALgAECgQJBgAAAA==.Invysion:BAACLgAFFH8PAAIDAAQJsgqgKQD6AAADAAQJsgqgKQD6AAAuAAQKfy4AAgMACQkXEeIcAOQBAAMACQkXEeIcAOQBAAAA.',
Ir='Irri:BAAALgADCgUJBQAAAA==.',
Is='Ishara:BAAALgAECggJCAABLgAECgkJNAAIAF4eAA==.',
Ja='Jacuzzi:BAAALgAECgUJCAAAAA==.Jaidess:BAAALgAECgEJAQAAAA==.',
Je='Jeangen:BAAALgAECgUJAwAAAA==.Jeanjean:BAAALgAECgcJCAAAAA==.Jeannjeann:BAAALgAECggJEgAAAA==.Jediknîght:BAAALgAECgYJBgAAAA==.Jeep:BAACLgAFFH8NAAILAAQJnhuhPwAoAQALAAQJnhuhPwAoAQAuAAQKfycAAgsACAlAJVMEAEoDAAsACAlAJVMEAEoDAAAA.Jellybea:BAACLgAFFH8NAAIBAAUJ/xqQCwCJAQABAAUJ/xqQCwCJAQAuAAQKfywAAwEACQltITEEABIDAAEACQltITEEABIDAAIAAgkJDKpuAGIAAAAA.',
Ji='Jibalynne:BAAALgAECgQJBAAAAA==.Jida:BAAALgAECgEJAQAAAA==.Jiffypop:BAAALgAECgcJDQABLgAECgkJLQAWAFsdAA==.Jinwooaura:BAAALgADCgcJBwAAAA==.',
Jo='Johnnycakes:BAAALgADCgMJBQAAAA==.Jonsnowxd:BAAALgADCgYJBgAAAA==.',
Jr='Jrhnbr:BAAALgADCgMJAwAAAA==.',
Ju='Juggnut:BAAALgAECgcJEQAAAA==.Jump:BAAALgAECgcJEwAAAA==.Junglebrew:BAAALgADCgQJBAAAAA==.Jurisdiction:BAABLgAECn8uAAISAAkJWRK2RwDsAQASAAkJWRK2RwDsAQAAAA==.',
Jz='Jz:BAAALgAECgMJBAAAAA==.',
['Jì']='Jìnn:BAAALgAECgUJDwAAAA==.',
Ka='Kaan:BAABLgAECn8sAAIFAAcJayJLEwCbAgAFAAcJayJLEwCbAgAAAA==.Kabea:BAAALgAECgEJAQAAAA==.Kadath:BAAALgADCgIJAwAAAA==.Kaeladín:BAAALgAECgUJCAAAAA==.Kagebouzu:BAAALgAECgYJDwAAAA==.Kahlan:BAAALgADCgcJCAABLgAECgYJDwAJAAAAAA==.Kakutogi:BAAALgADCgEJAQAAAA==.Kalycia:BAAALgAECgEJAgAAAA==.Kamela:BAAALgAECgYJCAAAAA==.Karael:BAAALgAECgUJEQABLgAECgkJGAAjAGQbAA==.Karma:BAABLgAECn8YAAIeAAYJqgOlPwDCAAAeAAYJqgOlPwDCAAAAAA==.Kayliaa:BAAALgAECgkJAQAAAA==.Kazarke:BAAALgADCgcJGAAAAA==.',
Ke='Keeia:BAAALgADCgQJBQAAAA==.Keho:BAABLgAECn8yAAMdAAkJTwtBJQCBAQAdAAkJTwtBJQCBAQAkAAIJkg6maABqAAAAAA==.Keihoe:BAAALgAECgMJAwABLgAECgkJMgAdAE8LAA==.Kenalia:BAABLgAECn8qAAIEAAkJlRZPGgBAAgAEAAkJlRZPGgBAAgAAAA==.Kengo:BAAALgAECgEJAQAAAA==.Keptalive:BAAALgADCgcJCgAAAA==.Kerzermern:BAAALgAFFAMJAwAAAA==.Kevic:BAAALgAFFAIJAwABLgAFFAQJEQACAJIQAA==.',
Kh='Khamaelion:BAAALgADCgcJDgAAAA==.',
Ki='Kiara:BAABLgAECn8eAAISAAgJNiBdIgCgAgASAAgJNiBdIgCgAgAAAA==.Kiju:BAAALgADCgYJBgAAAA==.Killaban:BAACLgAFFH8KAAIWAAQJ9BfjHQA1AQAWAAQJ9BfjHQA1AQAuAAQKfzIAAxYACQklIIYXADACABYACQngH4YXADACACUAAwkZGVMrAJoAAAAA.Killbydeath:BAAALgAECgEJAQAAAA==.Kimberlyhárt:BAACLgAFFH8HAAISAAMJVRrcVwD6AAASAAMJVRrcVwD6AAAuAAQKfzcAAxIACQnxJIIEAFUDABIACQnxJIIEAFUDABEABAn0CnNiAKgAAAAA.Kissmydots:BAABLgAECn9EAAIhAAkJKR70FgCZAgAhAAkJKR70FgCZAgAAAA==.Kitja:BAABLgAECn9JAAMDAAkJHCGUAwBoAwADAAkJHCGUAwBoAwABAAgJaBznEABaAgAAAA==.Kitla:BAAALgADCgUJBQABLgAECgkJSQADABwhAA==.',
Kl='Klipsch:BAAALgADCgUJBQAAAA==.Klukai:BAAALgADCgcJCwABLgAECgkJIQAFAPMdAA==.',
Kn='Kneed:BAAALgADCgYJBgAAAA==.',
Ko='Koala:BAAALgAECgQJBQABLgAFFAcJIQAbAHwXAA==.Kohman:BAABLgAECn8bAAIhAAYJ3RXOfABiAQAhAAYJ3RXOfABiAQAAAA==.Konyani:BAAALgADCgUJAQAAAA==.',
Kp='Kpop:BAAALgAECgEJAQABLgAECgcJBwAJAAAAAA==.',
Kr='Kraeven:BAAALgADCgEJAQAAAA==.Kregerath:BAAALgADCgIJAgAAAA==.Krftpnk:BAACLgAFFH8WAAIMAAQJPCYrBQC0AQAMAAQJPCYrBQC0AQAuAAQKfyoAAwwACQnQJDcEADcDAAwACQnQJDcEADcDAA0AAQkAAA9DAQAAAAAA.Krom:BAABLgAECn8tAAMWAAkJWx2WEQBmAgAWAAkJWx2WEQBmAgAlAAEJPQm4fwAnAAAAAA==.Kronas:BAABLgAECn8VAAILAAgJ3RXJYACAAQALAAgJ3RXJYACAAQAAAA==.Kronophyne:BAACLgAFFH8HAAIIAAUJChHOXAAxAQAIAAUJChHOXAAxAQAuAAQKfzcAAggACQn5HWYzAEkCAAgACQn5HWYzAEkCAAAA.Kronotality:BAACLgAFFH8HAAMQAAMJ5xOhNgBXAAAKAAMJXQv6pwDKAAAQAAEJJR+hNgBXAAAuAAQKf0oAAhAACQkZJUwCAC0DABAACQkZJUwCAC0DAAAA.Kronotek:BAAALgAECgcJDQAAAA==.Kronotekken:BAAALgADCgYJBgAAAA==.Kronotide:BAAALgAECgYJDAAAAA==.',
Ku='Kurohitsugî:BAAALgAECgIJBAAAAA==.',
Ky='Kylorai:BAAALgAECgYJEgAAAA==.Kynbrochel:BAAALgAECgYJDAAAAA==.',
La='Laars:BAAALgAECgUJDAABLgAECggJJQAhADsNAA==.Laimaster:BAAALgAECgEJAwAAAA==.Lakiri:BAABLgAECn9AAAIaAAkJiBvyBQB7AgAaAAkJiBvyBQB7AgAAAA==.Landaeda:BAAALgAECgcJDgAAAA==.Lanney:BAAALgAECgYJBgAAAA==.Lapsu:BAABLgAECn8fAAIkAAkJjRRJHADIAQAkAAkJjRRJHADIAQAAAA==.Lascivia:BAACLgAFFH8PAAMWAAUJ5B0yFwBTAQAWAAUJ5B0yFwBTAQAmAAQJQBL6FgDdAAAuAAQKfyYAAxYACQkAH1AmACcCABYACQmIHFAmACcCACYACAnlECQeAD8BAAAA.Lawhanx:BAAALgADCgEJAQABLgAFFAMJBAAJAAAAAA==.Laylahh:BAAALgADCgQJBQAAAA==.Lazy:BAABLgAECn8WAAMhAAYJyRcpiQBHAQAhAAUJyRcpiQBHAQAHAAIJxQGEYQBLAAAAAA==.',
Le='Leademon:BAABLgAECn9BAAMNAAkJ6SD/EAC4AgANAAkJ6SD/EAC4AgAMAAIJTRrWWgB2AAAAAA==.Leadmin:BAAALgADCgMJBQABLgAECgkJQQANAOkgAA==.Leadmln:BAAALgADCgcJBwABLgAECgkJQQANAOkgAA==.Leftlane:BAABLgAECn8uAAMZAAkJsiENBgBNAwAZAAkJsiENBgBNAwAcAAEJgA0WpwAsAAAAAA==.Legato:BAAALgAECgcJCAABLgAFFAgJIAAZANgeAA==.Lehsham:BAAALgAECgkJAgAAAA==.Lekiri:BAAALgAECgYJCAAAAA==.Lep:BAAALgAFFAQJBAABLgAFFAgJGQAUABsYAA==.Lethalkrits:BAAALgAECgkJAgAAAA==.Leva:BAABLgAECn8hAAIFAAkJ8x1vGACAAgAFAAkJ8x1vGACAAgAAAA==.',
Li='Liberté:BAAALgAECgQJBgAAAA==.Liciano:BAABLgAECn8YAAMjAAkJZBubAgCRAgAjAAkJSRubAgCRAgAeAAYJsRubHgCeAQAAAA==.Lie:BAACLgAFFH8HAAIeAAIJTgtQMwCOAAAeAAIJTgtQMwCOAAAuAAQKfzsAAh4ACQkNGe0MAFQCAB4ACQkNGe0MAFQCAAAA.Lightsdown:BAAALgAECgYJBgAAAA==.Lilbeebs:BAAALgAECgkJEQAAAA==.Lileth:BAAALgAECgkJAgAAAA==.Lilflea:BAAALgAECggJEQAAAA==.Lilzuki:BAABLgAECn8XAAIHAAkJdAgCEgAjAQAHAAkJdAgCEgAjAQAAAA==.Lilïth:BAACLgAFFH8QAAIQAAYJxx7bEABwAQAQAAYJxx7bEABwAQAuAAQKfyAAAhAABwmDJPIGAMICABAABwmDJPIGAMICAAAA.Linguine:BAAALgAECgEJAwABLgAFFAYJGAABAKgWAA==.Lisalisa:BAABLgAECn89AAIZAAkJwxcjIQBEAgAZAAkJwxcjIQBEAgAAAA==.Livan:BAAALgAECgMJAwAAAA==.Livia:BAAALgAECgEJAQAAAA==.',
Lo='Lohzak:BAAALgAECgEJAQAAAA==.Lousier:BAAALgAECgEJAQAAAA==.',
Lu='Lularia:BAAALgADCgIJAgAAAA==.Lumii:BAAALgAECgYJBgABLgAECgYJFAAEAEUkAA==.Luminari:BAAALgADCgEJAQABLgAECgkJNAAIAF4eAA==.Lunaa:BAAALgAECgkJDAAAAA==.Lurassa:BAAALgAECgYJDAABLgAECgcJDgAJAAAAAA==.',
Ly='Lyacon:BAAALgADCgQJBAABLgAECgkJFQAIAEEcAA==.',
['Lä']='Lä:BAEALgAECgcJBwABLgAFFAMJBAAJAAAAAA==.',
Ma='Madrie:BAAALgAECgQJBAAAAA==.Maekar:BAABLgAECn8jAAIVAAYJwhD8DgAXAQAVAAYJwhD8DgAXAQAAAA==.Maellus:BAAALgAECgEJAQAAAA==.Maelstorm:BAAALgADCgIJAgAAAA==.Mageman:BAAALgADCgYJAgAAAA==.Magickdragon:BAAALgAECgYJBwABLgAECgkJLAACABoYAA==.Magicmoo:BAAALgAECgEJAQABLgAFFAMJBwASAFUaAA==.Maltis:BAAALgADCgcJCwAAAA==.Mananstuff:BAACLgAFFH8FAAIbAAMJqQTBOACPAAAbAAMJqQTBOACPAAAuAAQKf0QAAhsACQmIEdIeAM4BABsACQmIEdIeAM4BAAAA.Manaproblems:BAAALgADCgMJBAAAAA==.Mandemic:BAAALgAECgYJCQABLgAFFAQJEgAWABEbAA==.Marguerek:BAAALgADCgEJAQAAAA==.Marinara:BAAALgAECgcJDgAAAA==.Marisatomei:BAAALgAECgYJBgAAAA==.Markamanimal:BAACLgAFFH8PAAIYAAQJjBoIBgBJAQAYAAQJjBoIBgBJAQAuAAQKfyUAAhgACAnfIYYDAPwCABgACAnfIYYDAPwCAAAA.Marnix:BAABLgAECn8bAAIcAAgJmRJ0LgCEAQAcAAgJmRJ0LgCEAQAAAA==.Marshail:BAAALgAECgEJAQAAAA==.',
Md='Mdbeef:BAAALgAECgUJBQAAAA==.',
Me='Medikus:BAABLgAECn8jAAMZAAgJbxzLHwBNAgAZAAgJbxzLHwBNAgAcAAMJ2gzDdwCBAAAAAA==.Meesoomagi:BAAALgAECgYJBwAAAA==.Megajoo:BAACLgAFFH8GAAMbAAIJuQzvPQB1AAAbAAIJuQzvPQB1AAAFAAIJuQFDZwBJAAAuAAQKfxUAAxsACAnYFa8dANgBABsACAnYFa8dANgBAAUABgnlB6F5AMcAAAAA.Menil:BAABLgAECn8XAAMEAAgJwBtXFgAQAgAEAAcJJhpXFgAQAgAkAAQJchb+TwDDAAAAAA==.Merryl:BAAALgAECggJDgAAAA==.Meyounow:BAAALgAECgEJBQAAAA==.',
Mi='Midnye:BAAALgADCgYJBgAAAA==.Mike:BAECLgAFFH8GAAMnAAQJqhFEBACeAAAnAAIJzBlEBACeAAAIAAIJiAkrpgCIAAAuAAQKfzoAAycACQmDJKMAAP4CACcACQlAIqMAAP4CAAgACAlkIB5VANoBAAAA.Mips:BAAALgAFFAMJBAABLgAFFAQJBgAIAFwSAA==.',
Mk='Mk:BAEALgADCgcJBwABLgAECgkJQQAkAIAgAA==.',
Mo='Mob:BAAALgADCgcJBwAAAA==.Mockra:BAABLgAECn8+AAMIAAkJViKcEwDiAgAIAAkJViKcEwDiAgAfAAIJuBiqGgBCAAAAAA==.Monafae:BAAALgADCgUJBQAAAA==.Moohammered:BAAALgAECggJDQAAAA==.Moolou:BAACLgAFFH8PAAITAAUJWRcPBgAeAQATAAUJWRcPBgAeAQAuAAQKfyMAAhMACQm1HyYGAIMCABMACQm1HyYGAIMCAAAA.Moonraka:BAAALgADCgUJBQAAAA==.Moosé:BAAALgAECgEJAQABLgAFFAgJJgASAO8UAA==.Mootilater:BAAALgADCgQJAQAAAA==.Mootilator:BAAALgADCgYJBgAAAA==.Moraei:BAAALgADCgEJAQAAAA==.Mordew:BAAALgADCgUJBQABLgAECgkJOgAKAJclAA==.Morechie:BAABLgAECn8hAAIoAAkJcBWSBwDyAQAoAAkJcBWSBwDyAQAAAA==.Morecowbell:BAAALgAECgEJAQAAAA==.Morgatho:BAAALgADCgEJAwAAAA==.Mortiferon:BAABLgAECn82AAIKAAkJCh+NFQDEAgAKAAkJCh+NFQDEAgAAAA==.',
Mu='Muhgunguh:BAAALgAECgEJAQAAAA==.Munnky:BAABLgAECn8wAAIEAAgJQSKHCQD9AgAEAAgJQSKHCQD9AgAAAA==.Murmaider:BAAALgADCgIJAgAAAA==.',
My='Mythrandere:BAAALgADCgcJCwAAAA==.Mytu:BAAALgADCgUJBgAAAA==.',
['Má']='Mánflu:BAACLgAFFH8SAAIWAAQJERvgFgBUAQAWAAQJERvgFgBUAQAuAAQKfysAAyUACQniHhIDAOICACUACQniHhIDAOICABYABwlJGlI0ANkBAAAA.',
['Mô']='Môrrigãn:BAAALgADCgMJAwAAAA==.',
['Mö']='Mörgänä:BAAALgADCgMJAwAAAA==.',
Na='Naissa:BAAALgAECgQJCwAAAA==.Nakanir:BAAALgAECgYJBgAAAA==.Nalfeign:BAAALgAECgQJBQAAAA==.Napa:BAAALgAECgUJCgABLgAFFAYJFwAZAKMXAA==.Narn:BAABLgAECn9DAAQPAAkJOBwhFAA6AgAVAAcJrRjRCQBCAgAPAAkJ5RghFAA6AgAUAAIJLQiEQQBgAAAAAA==.',
Ne='Nealite:BAAALgAECgkJBgAAAA==.Necrophyllis:BAAALgAECgMJAwAAAA==.Necrotion:BAAALgAECgYJEgAAAA==.Nei:BAAALgAECgEJAQABLgAECgEJAQAJAAAAAA==.Nerrisa:BAABLgAECn8iAAICAAkJERTiIAC9AQACAAkJERTiIAC9AQAAAA==.Nertt:BAAALgADCgYJBgABLgAECgkJQwAUADEZAA==.Neublood:BAAALgAECgQJCAAAAA==.',
Ni='Nicodemus:BAAALgAECgcJDwAAAA==.',
No='Noblewarrior:BAACLgAFFH8hAAIWAAgJOhvkAgBWAgAWAAgJOhvkAgBWAgAuAAQKfysAAhYACAmuJCoNAJgCABYACAmuJCoNAJgCAAAA.Noctilus:BAAALgAECgcJCQAAAA==.Nohkari:BAAALgADCgkJHQABLgAECgkJJAAhANAUAA==.Nooj:BAACLgAFFH8wAAMGAAgJmSMiAADqAgAGAAgJmSMiAADqAgAeAAYJiRQ8EwBrAQAuAAQKfx4AAwYACQl7ITsAAMMDAAYACQl7ITsAAMMDAB4ABgmFEpA6AEQBAAAA.Notakoala:BAACLgAFFH8hAAIbAAcJfBfxCwDPAQAbAAcJfBfxCwDPAQAuAAQKfycAAxsACAlHJFQNAMUCABsACAlHJFQNAMUCABcAAQk3Es1vADMAAAAA.Nothnx:BAAALgAFFAEJAwAAAA==.Notoriouspat:BAABLgAECn8hAAILAAgJrg4aXwCFAQALAAgJrg4aXwCFAQAAAA==.Notsamadeath:BAABLgAFFH8LAAQgAAUJWRGMDgAeAQAgAAQJWRGMDgAeAQAKAAIJ3wht5ACBAAAQAAEJAACjTAAAAAAAAA==.Novia:BAAALgAECgYJBgAAAA==.Noyber:BAAALgAFFAIJAgAAAA==.Noydin:BAAALgAFFAIJAwAAAA==.',
['Ní']='Nínebreaker:BAAALgAECgQJBQAAAA==.',
['Nü']='Nüll:BAAALgAECggJEwAAAA==.',
Ob='Obern:BAABLgAECn8WAAIOAAkJZhvqFQD0AQAOAAkJZhvqFQD0AQAAAA==.Oblïna:BAABLgAECn8tAAIEAAkJTwnLTQAuAQAEAAkJTwnLTQAuAQAAAA==.',
Od='Odiumaeterna:BAAALgADCgcJBwAAAA==.',
Of='Offensivé:BAAALgAECgMJCAAAAA==.Oftheages:BAAALgAFFAEJAQABLgAFFAgJGQAUABsYAA==.',
On='Onetozerosix:BAABLgAECn8jAAIKAAkJHhytPAAMAgAKAAkJHhytPAAMAgAAAA==.Onos:BAAALgAECgEJAQAAAA==.Onsen:BAAALgAECgQJBgAAAA==.',
Oo='Oogak:BAAALgAECgUJBgAAAA==.Oomigig:BAAALgADCgUJBQAAAA==.',
Op='Opalily:BAAALgAECgEJAQAAAA==.Operation:BAAALgAECgQJCAAAAA==.',
Or='Oresties:BAAALgAECgYJCAAAAA==.Orestisies:BAAALgAECgcJCAAAAA==.Orghrax:BAAALgADCgEJAQAAAA==.Orisys:BAAALgAECgIJAwAAAA==.',
Os='Osteer:BAAALgAECgYJBgAAAA==.',
Ot='Otterjim:BAAALgADCgQJBAAAAA==.',
Pa='Padfoote:BAAALgADCgIJAwAAAA==.Pahaa:BAAALgAECgUJBQAAAA==.Pairadeez:BAAALgAECgYJDwAAAA==.Pajamabanana:BAAALgADCgIJAgAAAA==.Pandablaze:BAAALgAECgYJDwAAAA==.Panterarey:BAAALgADCgYJEAAAAA==.Papalego:BAABLgAECn8wAAILAAkJfg0dSwC8AQALAAkJfg0dSwC8AQAAAA==.Parakka:BAABLgAECn82AAIZAAkJGhbaIABGAgAZAAkJGhbaIABGAgAAAA==.Patak:BAAALgAECgMJAwAAAA==.Pavle:BAAALgAECgMJAwAAAA==.Pawp:BAAALgAECgYJCgABLgAECggJJAABAOEXAA==.',
Pe='Pearagon:BAABLgAECn8VAAICAAgJwBE2JgCZAQACAAgJwBE2JgCZAQABLgAFFAYJFwAZAKMXAA==.Pepsidew:BAAALgADCgcJDAAAAA==.Pepsisprite:BAABLgAECn84AAIBAAkJsRkRDQCSAgABAAkJsRkRDQCSAgAAAA==.Pesky:BAABLgAECn8jAAIbAAYJJBbtNAA/AQAbAAYJJBbtNAA/AQABLgAFFAQJCwAIAGERAA==.',
Pf='Pfchanguz:BAAALgADCgcJDAAAAA==.',
Ph='Phdbeef:BAABLgAFFH8HAAIXAAIJ+xszHgCiAAAXAAIJ+xszHgCiAAABLgAFFAYJEAAQAMceAA==.Phlemm:BAAALgAECgEJAQAAAA==.Phoivos:BAABLgAECn8VAAIIAAkJQRwKIQDvAgAIAAkJQRwKIQDvAgAAAA==.',
Pi='Picklez:BAABLgAECn82AAIKAAkJOiK/CQAgAwAKAAkJOiK/CQAgAwAAAA==.Pissflizzle:BAABLgAECn8dAAIhAAgJ9w3sZwBsAQAhAAgJ9w3sZwBsAQAAAA==.',
Pl='Plaquenil:BAAALgADCgEJAQAAAA==.',
Po='Poison:BAAALgADCgEJAQAAAA==.Porkroaster:BAABLgAECn8nAAIIAAgJhAwAhABsAQAIAAgJhAwAhABsAQAAAA==.',
Pr='Praye:BAAALgAFFAMJAwAAAA==.Priestop:BAAALgAECgEJAQAAAA==.',
Ps='Psyfarian:BAAALgADCgcJDQAAAA==.Psyop:BAAALgAECgYJCAABLgAECggJIQABABkfAA==.',
Pu='Pushemover:BAAALgAECgMJBQAAAA==.',
Qu='Quillswitch:BAAALgAECgEJAQAAAA==.',
Ra='Radduc:BAABLgAECn8ZAAMRAAYJKxgaNgB0AQARAAYJKxgaNgB0AQASAAEJlQZFqwEpAAAAAA==.Ragerade:BAAALgAECgYJBwAAAA==.Raidu:BAAALgAECgMJAwAAAA==.Ralpherion:BAAALgADCgIJAgAAAA==.Ranoa:BAAALgAECgQJCgAAAA==.Raphåel:BAAALgAFFAEJAQAAAA==.Ravioli:BAAALgAECgQJBgAAAA==.Razialum:BAAALgADCgYJBgAAAA==.Razorsteps:BAAALgAFFAkJBAAAAA==.Razzberry:BAAALgADCgYJDAAAAA==.',
Re='Rebrowth:BAAALgAECgcJEgAAAA==.Redren:BAAALgADCgIJAgAAAA==.Reegrets:BAAALgAECggJDQAAAA==.Reena:BAAALgADCgIJAwAAAA==.Regeth:BAAALgAECgkJDgAAAA==.Regiplague:BAAALgAECgYJCwAAAA==.Regretty:BAAALgAECggJDQABLgAECggJDQAJAAAAAA==.Renthar:BAAALgADCgUJBQAAAA==.Renzdingo:BAAALgAECgkJDwAAAA==.Repete:BAAALgAECgUJDgAAAA==.Resyek:BAABLgAECn85AAIIAAgJOyRiGwC0AgAIAAgJOyRiGwC0AgAAAA==.Reverendgank:BAAALgAECgEJAQAAAA==.',
Rh='Rhaxanna:BAAALgADCgYJBgAAAA==.',
Ri='Rick:BAAALgAFFAMJAwAAAA==.Rickheaddk:BAAALgADCgEJAgAAAA==.Riivan:BAABLgAECn8pAAIhAAkJDBOZNQABAgAhAAkJDBOZNQABAgAAAA==.Rini:BAAALgAECgkJEQABLgABCgYJCwAJAAAAAA==.Rishi:BAABLgAECn86AAISAAkJQxYzUQDTAQASAAkJQxYzUQDTAQAAAA==.Rivian:BAAALgADCgIJAgABLgAECgEJAQAJAAAAAA==.',
Ro='Robot:BAABLgAECn8oAAIEAAgJUBE0PAB3AQAEAAgJUBE0PAB3AQAAAA==.Roguè:BAAALgADCgYJBgABLgAFFAEJAQAJAAAAAA==.Rokmog:BAAALgAECgcJDgAAAA==.Rollinburn:BAAALgADCgYJCQAAAA==.Romanoff:BAAALgAECgEJAQAAAA==.Roxanol:BAAALgADCgEJAQABLgAECgkJPQARACUaAA==.',
Ru='Rumbrave:BAAALgAECgYJCwAAAA==.Rumtumtugger:BAAALgADCgkJCQAAAA==.',
['Rá']='Ráyune:BAAALgADCgcJBwAAAA==.',
Sa='Sackos:BAAALgAECgEJAgAAAA==.Sadpanda:BAAALgADCgUJCAAAAA==.Saffronspark:BAAALgADCgkJHwABLgAECgkJTgAkAMMiAA==.Sainsei:BAABLgAECn8fAAMdAAcJcgUHUQC7AAAdAAcJtwIHUQC7AAAkAAUJBAfMYgCPAAAAAA==.Saith:BAAALgAECgEJBgAAAA==.Samasear:BAABLgAECn8UAAIWAAgJ0w8wMgDjAQAWAAgJ0w8wMgDjAQABLgAFFAcJHAAKAHIeAA==.Sandwitch:BAABLgAECn9DAAMhAAkJLRguLwAaAgAhAAkJLRguLwAaAgAHAAIJmxB0UwB0AAAAAA==.Sanoa:BAABLgAFFH8JAAIaAAQJywRdDQDkAAAaAAQJywRdDQDkAAAAAA==.Sargatana:BAABLgAECn9AAAIdAAkJ7iBeBAD+AgAdAAkJ7iBeBAD+AgAAAA==.Sars:BAABLgAECn8yAAMEAAgJKyUVBQBXAwAEAAgJKyUVBQBXAwAkAAMJGhMrXgCbAAAAAA==.Sauronxd:BAAALgAECgUJCAAAAA==.',
Sc='Scalion:BAABLgAECn8nAAMNAAgJOR5YJAA7AgANAAgJOR5YJAA7AgAMAAQJ+BG9SwDAAAABLgAFFAMJBAAJAAAAAA==.Scarne:BAAALgAECgIJAgAAAA==.Schrodinger:BAABLgAECn8gAAITAAgJuAoOIAAQAQATAAgJuAoOIAAQAQAAAA==.Scravenhoof:BAAALgAECgYJBgAAAA==.',
Se='Selunee:BAAALgADCgEJAQAAAA==.Sepharad:BAAALgADCggJEgAAAA==.Septicflësh:BAAALgADCgEJAQAAAA==.Severum:BAABLgAECn88AAImAAkJYh3rBgCWAgAmAAkJYh3rBgCWAgAAAA==.',
Sh='Shabang:BAAALgAECgEJAQABLgAECgYJEwAJAAAAAA==.Shadowtiger:BAABLgAECn8vAAILAAkJUQxVTQC1AQALAAkJUQxVTQC1AQAAAA==.Shadrad:BAACLgAFFH8HAAISAAQJdx0sKgBdAQASAAQJdx0sKgBdAQAuAAQKfxsAAhIACQnFJYoIACQDABIACQnFJYoIACQDAAAA.Shamanor:BAAALgAECgcJCAAAAA==.Shammoo:BAAALgAECgIJBAABLgAFFAgJJgASAO8UAA==.Shantz:BAABLgAECn8sAAIQAAgJVxS9GwB7AQAQAAgJVxS9GwB7AQAAAA==.Shiban:BAABLgAECn8WAAIOAAkJEw6oFQD3AQAOAAkJEw6oFQD3AQAAAA==.Shirtless:BAAALgAECggJEQAAAA==.Shockra:BAABLgAECn8dAAIcAAkJ4xf4IgDKAQAcAAkJ4xf4IgDKAQAAAA==.Shokalypse:BAAALgADCgEJAQAAAA==.Shortbuss:BAAALgADCgYJEgAAAA==.',
Si='Sige:BAAALgADCgYJBgAAAA==.Sillygoose:BAAALgADCgkJDwAAAA==.Silverfox:BAAALgADCgMJAQABLgAECgkJPgAIAFYiAA==.Silx:BAABLgAECn8VAAMDAAcJMBE8IQCJAQADAAcJMBE8IQCJAQACAAEJoBZEXQA/AAAAAA==.Simvastatin:BAAALgADCgQJBAAAAA==.Sinterdeath:BAAALgAECgIJAgAAAA==.Sithiry:BAAALgAECgEJAQAAAA==.',
Sk='Skik:BAAALgAECgcJBwAAAA==.Skulltide:BAAALgADCgcJCQAAAA==.',
Sl='Slaggz:BAAALgADCgQJBAAAAA==.Slamvoke:BAAALgAECgYJBgABLgAFFAUJDwAWAKwVAA==.Slaté:BAAALgAECgEJAgABLgAECgMJBQAJAAAAAA==.Slowrot:BAAALgAECgQJBQABLgAFFAMJBwASAFUaAA==.Slushpuppy:BAAALgAFFAEJAQAAAA==.Slâte:BAAALgAFFAEJAgAAAA==.',
Sm='Smiteasaurus:BAAALgAECgEJAQAAAA==.Smokkie:BAAALgAFFAMJBAAAAA==.Smorthian:BAAALgAECgcJDQAAAA==.',
Sn='Snarll:BAAALgADCgEJAQAAAA==.Sniffinsteak:BAABLgAECn8bAAMkAAkJGiGYBgDfAgAkAAkJGiGYBgDfAgAEAAEJtwv8vwAlAAAAAA==.',
So='Solas:BAAALgADCgYJBgAAAA==.Somaliabiggs:BAAALgAECgYJCgAAAA==.Sonar:BAAALgADCgYJBgABLgAECgkJOgAKAJclAA==.Sonuvabitxh:BAAALgADCgQJBAAAAA==.Sorraba:BAABLgAFFH8JAAIIAAQJMwI+jADEAAAIAAQJMwI+jADEAAABLgAFFAQJEAADAD8UAA==.Sorrabo:BAACLgAFFH8QAAIDAAQJPxR6JAAeAQADAAQJPxR6JAAeAQAuAAQKfyAABAMACQmwFeoRAFQCAAMACQmwFeoRAFQCAAEAAwm7A0BkAEsAAAIAAQkpA3WVACEAAAAA.Sorraug:BAAALgAFFAIJAgABLgAFFAQJEAADAD8UAA==.Soryan:BAACLgAFFH8FAAISAAMJSwG7mgB/AAASAAMJSwG7mgB/AAAuAAQKfxoAAhIACAk4B9OVAFEBABIACAk4B9OVAFEBAAAA.Sosalkin:BAAALgAECgcJEQAAAA==.Souls:BAACLgAFFH8VAAIhAAUJ8B0MOQBfAQAhAAUJ8B0MOQBfAQAuAAQKfx4ABCEABwnhIyYXAMkCACEABwnhIyYXAMkCACgAAQkAAPIfAHIAAAcAAQm1GkhiAEoAAAAA.',
Sp='Spankenstine:BAABLgAECn8kAAMSAAkJHRf4RAD1AQASAAkJHRf4RAD1AQARAAUJowh+YwDuAAABLgABCgYJCwAJAAAAAA==.Spannky:BAAALgAECgcJEgABLgAECggJMAAEAEEiAA==.',
Sq='Squishÿ:BAAALgAECgYJDwAAAA==.',
St='Starshriek:BAAALgADCgcJBwAAAA==.Stinkydeathy:BAAALgAECgIJAwABLgAECgYJHAAdAMwYAA==.Stinkyfree:BAABLgAECn8cAAIdAAYJzBjSLgCcAQAdAAYJzBjSLgCcAQAAAA==.Stinkynatto:BAAALgADCgYJBgABLgAECgYJHAAdAMwYAA==.Stormcharred:BAABLgAECn8eAAIIAAgJ6SCgKADQAgAIAAgJ6SCgKADQAgAAAA==.Stormknight:BAAALgAECgUJEAAAAA==.Stormpoo:BAAALgAECgEJAQAAAA==.Straka:BAABLgAECn8fAAIFAAkJERIZPgCrAQAFAAkJERIZPgCrAQAAAA==.',
Su='Suffers:BAAALgAECgEJAQAAAA==.Sunbearr:BAAALgAECgEJAQAAAA==.Suneater:BAAALgAECgEJAgAAAA==.Sunmane:BAAALgAECgEJAQABLgAECgkJJgAYAGQXAA==.Supaheals:BAAALgAECgEJAQAAAA==.Superdk:BAABLgAFFH8IAAIgAAQJkhYqCwA8AQAgAAQJkhYqCwA8AQABLgAFFAgJFQASAOIaAA==.Superdruid:BAAALgADCgUJBQABLgAFFAgJFQASAOIaAA==.Supermonks:BAAALgAECggJDAABLgAFFAgJFQASAOIaAA==.Superpi:BAABLgAECn8aAAIDAAcJFx72EgBHAgADAAcJFx72EgBHAgABLgAFFAgJFQASAOIaAA==.Superret:BAACLgAFFH8VAAISAAgJ4hpPDwDoAQASAAgJ4hpPDwDoAQAuAAQKfycAAxIACQkGI/gOABYDABIACQkGI/gOABYDABEAAQn7FHOGADsAAAAA.Superskeet:BAACLgAFFH8HAAIRAAMJtAvhNACWAAARAAMJtAvhNACWAAAuAAQKfyUAAhEACAl3FyAiAPEBABEACAl3FyAiAPEBAAAA.Superwar:BAAALgAECgkJCQABLgAFFAgJFQASAOIaAA==.',
Sv='Svetllama:BAAALgADCggJCAAAAA==.',
Sw='Swaggbag:BAAALgADCgEJAQAAAA==.Swiftia:BAABLgAECn8VAAMiAAYJlBZYOwBzAQAiAAYJjhRYOwBzAQALAAUJAg07wQC9AAAAAA==.Swiftybutt:BAAALgAECggJCgAAAA==.',
Sy='Sylphièl:BAACLgAFFH8UAAMGAAUJDgc4BgAQAQAGAAUJDgc4BgAQAQAjAAEJqQLqEgAsAAAuAAQKfygAAwYACAkwDmELAHgBACMACAmbCq8EALkBAAYACAlDDWELAHgBAAAA.Syncere:BAAALgAFFAIJAgAAAA==.Synhunt:BAAALgAFFAEJAgAAAA==.Syrene:BAAALgAECgMJBgAAAA==.',
Ta='Tandarì:BAACLgAFFH8ZAAISAAUJWB/zLQBRAQASAAUJWB/zLQBRAQAuAAQKfyIAAhIACQmjHqoPABEDABIACQmjHqoPABEDAAAA.Tano:BAAALgAECgUJCQABLgAECgkJPgAIAFYiAA==.Tanparo:BAAALgAECgMJAwAAAA==.Tarick:BAAALgAECgYJCAAAAA==.Tasty:BAAALgAECgQJCwAAAA==.Tawnii:BAAALgADCgcJEgAAAA==.Tazath:BAAALgAECgEJAwAAAA==.Taírn:BAAALgAECgYJEQAAAA==.',
Te='Tehpredator:BAAALgAFFAMJAwABLgAFFAQJEAADAD8UAA==.Teilin:BAACLgAFFH8gAAIZAAgJ2B69AgCsAgAZAAgJ2B69AgCsAgAuAAQKfyIAAhkACQmQI7MEACcDABkACQmQI7MEACcDAAAA.Tenderloin:BAAALgAECgcJCwAAAA==.Teralynn:BAAALgAECgEJAgAAAA==.Terryisgreat:BAAALgAECgEJAQABLgAECgcJFgARAPETAA==.',
Th='Thalendor:BAAALgAECgIJAgAAAA==.Theaterthug:BAAALgAECgIJAgAAAA==.Thehulkster:BAAALgAECgMJAwAAAA==.Thetinman:BAAALgAECgEJAQAAAA==.Thevelo:BAAALgAECgIJAgABLgAECgcJFgAOAM4TAA==.Thewhole:BAAALgAFFAMJAQAAAA==.Theßigshot:BAABLgAECn8VAAIFAAYJICPAIgAyAgAFAAYJICPAIgAyAgAAAA==.Thoseheals:BAAALgADCgQJBAAAAA==.Thunderskeet:BAACLgAFFH8KAAINAAMJARleWgDZAAANAAMJARleWgDZAAAuAAQKfzwAAw0ACQkFJcUDAEgDAA0ACQkFJcUDAEgDAAwABwlYHRAUADICAAAA.Thundurus:BAACLgAFFH8PAAIcAAUJihPFJQD6AAAcAAUJihPFJQD6AAAuAAQKfyUAAhwACAm9Fj02AF0BABwACAm9Fj02AF0BAAAA.',
Ti='Timmayy:BAABLgAECn8kAAIhAAgJCBZ5OQAmAgAhAAgJCBZ5OQAmAgAAAA==.Tindrill:BAABLgAECn8wAAIlAAkJfSXNAABzAwAlAAkJfSXNAABzAwAAAA==.Tireiron:BAAALgADCgYJBgAAAA==.',
To='Tomraedisk:BAACLgAFFH8FAAIWAAQJegd9KgAEAQAWAAQJegd9KgAEAQAuAAQKfxkAAhYACQmJGzAWADwCABYACQmJGzAWADwCAAAA.Totemagoat:BAACLgAFFH8dAAMZAAcJJhhPGACZAQAZAAYJrxVPGACZAQAcAAUJ+hAKJgD4AAAuAAQKfzQAAxwACQkJHXUYAB0CABwACAnQG3UYAB0CABkACQmqFNgsANcBAAAA.Totemlyfine:BAABLgAECn80AAMZAAgJlSK3DwDQAgAZAAgJlSK3DwDQAgAcAAQJMBWsXwDCAAAAAA==.Totesmugoats:BAAALgAECggJEgAAAA==.Toxicshock:BAAALgADCgEJAQAAAA==.',
Tr='Traprkeepr:BAAALgADCgcJEgAAAA==.Treechains:BAABLgAECn8WAAMZAAYJ8he/TgByAQAZAAYJ8he/TgByAQAcAAEJZQPtkQAlAAAAAA==.Treefist:BAAALgAFFAEJAgAAAA==.Treeshield:BAAALgADCgYJBgAAAA==.Trickster:BAAALgAECgEJAgAAAA==.Triplex:BAAALgAECgQJBAAAAA==.Truth:BAAALgADCgcJDQAAAA==.',
Ts='Tsumuji:BAAALgAECgEJAQAAAA==.',
Tu='Turbobis:BAAALgAECgIJAgAAAA==.',
Tw='Twentyfour:BAACLgAFFH8MAAIFAAMJJgWqTACGAAAFAAMJJgWqTACGAAAuAAQKfxUAAgUABwmGEOVdADgBAAUABwmGEOVdADgBAAAA.Twigberry:BAAALgAECgUJCAAAAA==.',
Ty='Tygra:BAAALgAECgcJDQAAAA==.Typeshxxt:BAAALgADCgEJAQAAAA==.Tytanea:BAAALgAECgMJBAAAAA==.',
['Tø']='Tøqa:BAAALgAFFAEJAQAAAA==.',
Uh='Uhnderstood:BAABLgAECn8mAAIEAAkJjh1qEABUAgAEAAkJjh1qEABUAgAAAA==.',
Un='Undeadmonks:BAACLgAFFH8NAAIdAAMJSBcoMwDXAAAdAAMJSBcoMwDXAAAuAAQKf0kAAx0ACQliHoMHALwCAB0ACQliHoMHALwCACQAAwl2CsRlAHYAAAAA.',
Uv='Uvaweez:BAAALgAECgMJAwAAAA==.',
Va='Vahe:BAAALgAECgEJAQAAAA==.Vale:BAAALgAECgUJBgAAAA==.Valeshot:BAACLgAFFH8FAAILAAMJwAHleACcAAALAAMJwAHleACcAAAuAAQKfyYAAgsACQn9CW4/ALEBAAsACQn9CW4/ALEBAAAA.Valkillrie:BAAALgADCgcJBwAAAA==.Vall:BAAALgAECggJDAAAAA==.Valssra:BAABLgAECn8XAAIIAAcJmAqfrQAiAQAIAAcJmAqfrQAiAQAAAA==.Vampiricvrus:BAAALgAECgQJBgAAAA==.',
Ve='Vedbow:BAACLgAFFH8UAAQOAAQJmiPQDABbAQAOAAQJ0iHQDABbAQALAAMJMBX2YQDZAAAiAAEJgA+6JwBNAAAuAAQKfxwABAsACQnIIh4UAJUCAAsACAm5IR4UAJUCACIABAnyHyc8AG4BAA4AAwldIMA1AAYBAAAA.Vedronas:BAABLgAECn8XAAISAAcJaiOcHgC0AgASAAcJaiOcHgC0AgAAAA==.Velillys:BAAALgAECgEJAQAAAA==.Venlii:BAAALgADCgEJAQAAAA==.Veos:BAAALgAECgEJAQAAAA==.Verdict:BAABLgAECn8WAAIZAAgJYxEIPAC6AQAZAAgJYxEIPAC6AQAAAA==.Veritae:BAAALgAECgUJBwAAAA==.Vern:BAABLgAECn8YAAMDAAgJ+BcqJACrAQADAAgJ+BcqJACrAQACAAIJgwYoWQBWAAAAAA==.Vernaar:BAAALgAECgEJAQABLgAECggJGAADAPgXAA==.Vernah:BAABLgAECn8VAAIRAAgJ1RnhFwBHAgARAAgJ1RnhFwBHAgABLgAECggJGAADAPgXAA==.Verybad:BAABLgAECn9EAAIIAAYJpRwgewDbAQAIAAYJpRwgewDbAQAAAA==.',
Vo='Voidify:BAAALgADCgEJAgAAAA==.Voodoodrood:BAAALgADCgIJAgAAAA==.',
['Vè']='Vèronique:BAAALgAECgYJBgAAAA==.',
Wa='Waambler:BAAALgAECgIJAgAAAA==.Waamchifu:BAABLgAECn83AAIdAAkJhyNlAgA2AwAdAAkJhyNlAgA2AwAAAA==.Wack:BAAALgADCgUJBgAAAA==.Waka:BAAALgADCgcJCwAAAA==.Waltersight:BAACLgAFFH8GAAILAAMJgw3UZQDQAAALAAMJgw3UZQDQAAAuAAQKfxcAAgsACQlvFzEoADoCAAsACQlvFzEoADoCAAAA.Warsheep:BAAALgADCgQJAQAAAA==.',
We='Wesker:BAAALgADCgYJBgAAAA==.Westavia:BAAALgAECgEJAQABLgAFFAMJBwASAFUaAA==.Wewabear:BAAALgADCgQJBAAAAA==.',
Wh='Whateley:BAAALgAECgcJCgAAAA==.Whosthetänk:BAAALgAECgEJAQAAAA==.',
Wi='Wisebrownguy:BAABLgAECn8tAAISAAkJHR/bFADDAgASAAkJHR/bFADDAgABLgAFFAQJBQAWAHoHAA==.',
Wo='Worgana:BAAALgAECgMJAwAAAA==.Wormchild:BAAALgADCgQJBAAAAA==.',
Wu='Wukòng:BAAALgADCgEJAQAAAA==.',
Xe='Xercuul:BAAALgAECgUJCgAAAA==.',
Xi='Xikar:BAAALgAECgQJCAAAAA==.',
Xp='Xplosiv:BAAALgAECgcJDQABLgAFFAcJHwAZAL0eAA==.',
Xy='Xylophonejoe:BAAALgAECgQJBwAAAA==.',
Ye='Yeddy:BAAALgADCgcJBwAAAA==.Yel:BAAALgADCgYJCAAAAA==.',
Yo='Yoel:BAAALgADCgEJAQAAAA==.Yourdad:BAAALgAECgYJEAABLgAFFAEJAQAJAAAAAA==.',
Yu='Yudah:BAACLgAFFH8JAAQOAAMJuRRDIQDJAAAOAAMJDQ5DIQDJAAALAAIJzxzqegCYAAAiAAEJ3ABJOwAnAAAuAAQKfy0ABA4ACAmgHaQXAOUBAA4ACAkZGaQXAOUBACIABglUFnkTACQBAAsABwlgD2GTABQBAAAA.Yuta:BAAALgADCgcJBgAAAA==.',
Za='Zalrei:BAAALgAECgEJAQAAAA==.Zalupa:BAAALgAECgIJAgAAAA==.Zanghonghua:BAABLgAECn9OAAMkAAkJwyKbAwAlAwAkAAkJwyKbAwAlAwAEAAEJSRXWZAA+AAAAAA==.Zarinaria:BAABLgAECn8cAAINAAYJ2Q7qfQAvAQANAAYJ2Q7qfQAvAQAAAA==.',
Ze='Zetsumei:BAAALgADCgMJAwAAAA==.',
Zh='Zhael:BAABLgAECn8hAAINAAkJCRqoJgAuAgANAAkJCRqoJgAuAgAAAA==.',
Zi='Zitizen:BAAALgADCgYJBwAAAA==.',
Zo='Zodstrike:BAABLgAECn8sAAMNAAkJbwUXiQAKAQANAAkJbwUXiQAKAQAMAAQJnwIXWACGAAAAAA==.Zomara:BAAALgAECgMJCgAAAA==.Zooboo:BAABLgAECn8XAAIWAAkJURdrJQDKAQAWAAkJURdrJQDKAQAAAA==.Zophie:BAAALgADCgEJAQAAAA==.',
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
