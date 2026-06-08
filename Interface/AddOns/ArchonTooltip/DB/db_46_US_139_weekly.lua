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

local lookup = {'Priest-Holy','Priest-Shadow','Priest-Discipline','Monk-Mistweaver','Druid-Restoration','Rogue-Assassination','Warlock-Destruction','Mage-Frost','Unknown-Unknown','DeathKnight-Unholy','Hunter-BeastMastery','DemonHunter-Havoc','DemonHunter-Devourer','Evoker-Augmentation','DeathKnight-Blood','Paladin-Holy','Paladin-Retribution','Paladin-Protection','Evoker-Preservation','Evoker-Devastation','Warrior-Fury','Druid-Guardian','Druid-Feral','Shaman-Restoration','Druid-Balance','Shaman-Elemental','Monk-Brewmaster','Shaman-Enhancement','Rogue-Subtlety','Mage-Arcane','Monk-Windwalker','DeathKnight-Frost','Warlock-Demonology','Hunter-Marksmanship','Warrior-Arms','Warrior-Protection','Mage-Fire','Warlock-Affliction','Hunter-Survival','Rogue-Outlaw',}
local provider = {region='US',realm='LaughingSkull',name='US',type='weekly',zone=46,date='2026-06-06',data={Ab='Abeblinken:BAAALgAECgIJAgAAAA==.Ablucia:BAAALgADCgUJCQAAAA==.Abomb:BAAALgAECgEJAQAAAA==.Abotharn:BAAALgADCgUJBQAAAA==.',
Ac='Acanaline:BAAALgAECgEJAQAAAA==.Achannara:BAAALgADCgcJBwAAAA==.',
Ae='Aennisong:BAAALgAECgUJCAAAAA==.Aeoliana:BAAALgAECggJEgAAAA==.',
Aj='Ajier:BAACLgAFFH8JAAIBAAQJ8hRpFQABAQABAAQJ8hRpFQABAQAuAAQKfy0AAgEACQkpFqMWACcCAAEACQkpFqMWACcCAAAA.',
Al='Aleraz:BAACLgAFFH8TAAMBAAUJEhVKEgAjAQABAAQJkBlKEgAjAQACAAUJDhNIFwAaAQAuAAQKfz4ABAIACQn5HiQHANkCAAIACQn5HiQHANkCAAEABwnbIOEVAC0CAAMAAwkmB4FcAHEAAAAA.Allcapwne:BAAALgAECgcJCwAAAA==.Allenduin:BAAALgAECgYJBwAAAA==.Alshau:BAABLgAECn8aAAIEAAcJ0BdfIwCYAQAEAAcJ0BdfIwCYAQAAAA==.Alucart:BAAALgADCgcJCgAAAA==.',
Am='Ambrosia:BAAALgAECgYJDwAAAA==.Amity:BAAALgADCgkJEAABLgAECgkJIAAFAPMdAA==.',
An='Anchoredowl:BAAALgAECgEJAQAAAA==.Anewrbyss:BAAALgAECgUJEAAAAA==.Angela:BAABLgAECn8/AAMDAAkJAR+aBgANAwADAAkJAR+aBgANAwACAAEJowwIfwAzAAAAAA==.Anna:BAAALgAECgQJBQAAAA==.Annalunà:BAAALgADCgIJBAAAAA==.Annälise:BAAALgADCgEJAQAAAA==.',
Ap='Apeople:BAACLgAFFH8GAAIGAAMJExnCBgD1AAAGAAMJExnCBgD1AAAuAAQKfzAAAgYACQmGIloBACEDAAYACQmGIloBACEDAAAA.Apocalýpsè:BAAALgAECgIJAgAAAA==.Applebottum:BAAALgAECgcJDQAAAA==.Appärition:BAABLgAECn8xAAIHAAgJqCBTAgCQAgAHAAgJqCBTAgCQAgAAAA==.',
Ar='Arleance:BAAALgAECgUJCAAAAA==.Arondael:BAABLgAECn8hAAIGAAgJeRd6BwDXAQAGAAgJeRd6BwDXAQAAAA==.Arsène:BAAALgADCgcJCwAAAA==.',
As='Astroglyde:BAAALgAECgcJCAAAAA==.Aszun:BAAALgADCgUJBQAAAA==.',
Au='Aurialis:BAAALgAECgcJDQAAAA==.',
Av='Avanti:BAABLgAECn89AAIIAAkJURu1KgBoAgAIAAkJURu1KgBoAgAAAA==.Avendeloria:BAAALgAECgYJEAAAAA==.',
Az='Azrahn:BAAALgADCgQJBQAAAA==.',
['Aü']='Aüra:BAAALgAECgEJAQABLgAECggJCQAJAAAAAA==.',
Ba='Backmoist:BAAALgAECgMJBAAAAA==.Bagmaster:BAACLgAFFH8QAAIBAAQJ6yE4DABuAQABAAQJ6yE4DABuAQAuAAQKfzgAAgEACQkAJpkCAD4DAAEACQkAJpkCAD4DAAAA.Bahm:BAAALgADCgYJEwAAAA==.Baktolife:BAAALgAECgkJBAAAAA==.Bam:BAAALgAECgQJBQABLgAFFAIJBgAKAJshAA==.Bartholomoo:BAABLgAECn9BAAIKAAkJvyJEDgDyAgAKAAkJvyJEDgDyAgAAAA==.Bayonetta:BAAALgAECgcJDAAAAA==.',
Be='Beeftornado:BAAALgAECgYJBwAAAA==.Belakor:BAAALgADCgIJAgAAAA==.Ber:BAAALgAECgEJAwAAAA==.',
Bi='Bigbusta:BAAALgADCgMJAwAAAA==.Bildros:BAAALgAECgEJAQAAAA==.Birgite:BAAALgAECgYJEAAAAA==.Bizniz:BAAALgAECgYJDAAAAA==.',
Bl='Blastin:BAAALgADCgcJBwAAAA==.Blazefury:BAABLgAECn8YAAILAAYJcwwUnQD4AAALAAYJcwwUnQD4AAAAAA==.Blazeknight:BAABLgAECn8tAAIMAAkJ/RmpFADZAQAMAAkJ/RmpFADZAQAAAA==.Blazemaker:BAABLgAECn8aAAIIAAYJPBB2twARAQAIAAYJPBB2twARAQAAAA==.Blazemaster:BAAALgAECgQJCQAAAA==.Blinduru:BAACLgAFFH8RAAINAAQJJSIpIwCHAQANAAQJJSIpIwCHAQAuAAQKfzYAAg0ACQltJWsCAF0DAA0ACQltJWsCAF0DAAAA.Blitz:BAAALgAECgIJAgAAAA==.Blocktor:BAAALgAECgMJAwABLgAECgYJHAANANkOAA==.Bluberriez:BAAALgAECgYJBgAAAA==.',
Bo='Bobbiepines:BAAALgAECgMJAwAAAA==.Bonez:BAAALgAECgMJAwAAAA==.Book:BAAALgAECgkJEwAAAA==.Bookie:BAAALgAECgcJCAAAAA==.Booza:BAAALgAECgIJAgAAAA==.Borkenshwang:BAAALgADCgYJCwAAAA==.Boydik:BAAALgAECgQJBgAAAA==.',
Bp='Bpaìn:BAABLgAECn8lAAIOAAgJwRihGgD5AQAOAAgJwRihGgD5AQAAAA==.',
Br='Brewlïth:BAAALgAECgIJAgABLgAFFAUJDgAPAPAfAA==.Brewmaester:BAAALgAECgEJAgAAAA==.Brink:BAABLgAECn8UAAIIAAgJNg3sfQB1AQAIAAgJNg3sfQB1AQAAAA==.Brojac:BAAALgAECgcJDgAAAA==.Brokil:BAAALgADCggJDAAAAA==.Brolic:BAAALgAECgQJBAAAAA==.Bromaster:BAAALgAECgQJBQAAAA==.Brones:BAAALgAECgkJAgAAAA==.Brossiere:BAABLgAECn8hAAQQAAgJERtLMwB8AQAQAAUJZRpLMwB8AQARAAYJoxejgwBcAQASAAUJVRfUIQD5AAAAAA==.Brotemic:BAAALgAECgYJDQAAAA==.Bru:BAACLgAFFH8LAAIBAAQJMBkaEgAlAQABAAQJMBkaEgAlAQAuAAQKfyoAAgEACQl1HOwMAIYCAAEACQl1HOwMAIYCAAAA.Brutalizèr:BAAALgADCgYJBgABLgAECgEJAQAJAAAAAA==.',
Bt='Bt:BAAALgAECgEJAgAAAA==.',
Bu='Bubblegal:BAAALgAECgQJCQAAAA==.Bullsmcgee:BAABLgAECn86AAMKAAkJlyUoAwBqAwAKAAkJlyUoAwBqAwAPAAEJAAAXQwA9AAAAAA==.Burningtree:BAABLgAECn8bAAIIAAgJ6Aq6ggBrAQAIAAgJ6Aq6ggBrAQAAAA==.Burny:BAAALgADCgEJAQAAAA==.Burrder:BAAALgADCggJCAAAAA==.Bustdown:BAAALgADCggJDwAAAA==.Buttslapper:BAAALgADCggJCAAAAA==.',
['Bö']='Börck:BAAALgADCgUJBQAAAA==.',
['Bø']='Bøb:BAAALgAECggJCwAAAA==.',
Ca='Camamoonmana:BAABLgAECn8aAAIFAAkJ3BPDNgC0AQAFAAkJ3BPDNgC0AQAAAA==.Captcorndog:BAACLgAFFH8FAAIOAAMJ2wo2QgCwAAAOAAMJ2wo2QgCwAAAuAAQKfygABA4ACAlAFdAhAMMBAA4ACAlAFdAhAMMBABMABQnzA3k4AKcAABQAAQkAALRAAC8AAAAA.Caskket:BAAALgAECggJCQAAAA==.Castreytid:BAAALgAECgYJBgABLgAECgkJGQAVAIkbAA==.Catdog:BAABLgAECn8hAAIWAAYJ6RedIQAuAQAWAAYJ6RedIQAuAQAAAA==.Catechism:BAABLgAECn8kAAIQAAgJdiEpCQDuAgAQAAgJdiEpCQDuAgAAAA==.',
Ce='Cemeo:BAABLgAECn8UAAITAAcJiBcTFgDsAQATAAcJiBcTFgDsAQAAAA==.Cerberusalfa:BAACLgAFFH8SAAIMAAQJISVEBAC0AQAMAAQJISVEBAC0AQAuAAQKfzcAAgwACQkTJhUBAGwDAAwACQkTJhUBAGwDAAAA.',
Ch='Chaintazer:BAAALgADCgYJBgABLgAECgkJGQAVAIkbAA==.Chewbaca:BAAALgAECgEJAwAAAA==.Chickennuggi:BAACLgAFFH8KAAIIAAQJYRHHWAAtAQAIAAQJYRHHWAAtAQAuAAQKfygAAggABwmlHbFCAA0CAAgABwmlHbFCAA0CAAAA.Chinchilla:BAAALgADCgcJBwAAAA==.Chiphoof:BAABLgAECn8fAAIXAAgJ0xRnDgC9AQAXAAgJ0xRnDgC9AQAAAA==.Chocofox:BAABLgAECn8fAAIYAAkJmSHLBABeAwAYAAkJmSHLBABeAwAAAA==.Chokemagic:BAAALgAECgUJBwAAAA==.Chopndot:BAAALgAECgEJBAAAAA==.Chozen:BAAALgADCgcJBwAAAA==.Chrill:BAABLgAECn8cAAINAAYJchfTZwBJAQANAAYJchfTZwBJAQAAAA==.',
Cl='Claraabun:BAAALgAECgUJBQABLgAFFAYJFgAQAMYTAA==.Clarabuns:BAACLgAFFH8WAAIQAAYJxhOZDgC/AQAQAAYJxhOZDgC/AQAuAAQKfx8AAxAACQnGF2YlAPsBABAACQnGF2YlAPsBABEABQl1Fyd3AHQBAAAA.Clarasbuns:BAAALgAECgMJAwABLgAFFAYJFgAQAMYTAA==.Clawdragoon:BAECLgAFFH8VAAQZAAQJEQvHJwDfAAAZAAQJEQvHJwDfAAAFAAQJhAG9QwCfAAAWAAEJpwK9PAAfAAAuAAQKfzAAAxkACAnVGW0UAG8CABkACAnVGW0UAG8CAAUABQlACN+bAJQAAAAA.',
Co='Coati:BAAALgADCgYJBgAAAA==.Colosie:BAAALgAECgYJEwAAAA==.Comegetpsalm:BAABLgAECn89AAIQAAkJJRrQEACGAgAQAAkJJRrQEACGAgAAAA==.Cornbreadmat:BAAALgADCgcJDQAAAA==.',
Cr='Creamsock:BAAALgAECgQJCQAAAA==.Creatlach:BAACLgAFFH8eAAIYAAYJoR13DADrAQAYAAYJoR13DADrAQAuAAQKfzgAAxgACAlPHcAhADcCABgACAlPHcAhADcCABoAAwlXE3BjALUAAAAA.Creatlachlol:BAAALgAECgkJCQABLgAFFAYJHgAYAKEdAA==.Creech:BAAALgADCgIJAgAAAA==.Creeptoken:BAAALgAECgEJAQAAAA==.Crucifilth:BAAALgADCgYJDAAAAA==.Cryopathy:BAAALgAECgYJDgAAAA==.Crypty:BAABLgAECn8dAAMaAAkJggzmMABtAQAaAAkJggzmMABtAQAYAAUJrREiXQAWAQAAAA==.',
Cy='Cyaniidee:BAAALgADCgcJBwAAAA==.Cyraxx:BAAALgADCgMJAwAAAA==.Cyrusdragon:BAAALgAECgEJAQAAAA==.Cytherea:BAABLgAECn8nAAIRAAcJDBCpnAAxAQARAAcJDBCpnAAxAQAAAA==.',
Da='Daddybod:BAABLgAECn8gAAIbAAkJjRI8HQCzAQAbAAkJjRI8HQCzAQAAAA==.Dainnan:BAAALgADCgEJAQAAAA==.Dalinek:BAAALgAECgUJBQAAAA==.Danicarkel:BAAALgAECggJDQAAAA==.Darkcallum:BAAALgAECgEJAQAAAA==.Darktaynt:BAAALgAECgMJBQAAAA==.Darthfox:BAAALgAECgMJBQAAAA==.',
De='Deadsean:BAAALgAECgUJDAAAAA==.Deathsyn:BAABLgAFFH8JAAIKAAQJzRmWSABQAQAKAAQJzRmWSABQAQAAAA==.Deathtracker:BAABLgAECn8aAAILAAgJXw4gXACEAQALAAgJXw4gXACEAQAAAA==.Deathwarden:BAAALgAECggJEwAAAA==.Deathñdk:BAAALgADCgEJAQAAAA==.Debuffed:BAAALgAECgEJAQAAAA==.Delathor:BAAALgAECgcJDgABLgAFFAEJAQAJAAAAAA==.Delimeatear:BAAALgAECgIJAgABLgAECgkJHQACABkcAA==.Demiloss:BAAALgAFFAEJAQAAAA==.Demise:BAABLgAECn8qAAIIAAgJ1h46MQCtAgAIAAgJ1h46MQCtAgABLgAFFAMJBAAJAAAAAA==.Demonclem:BAAALgAFFAIJAgAAAA==.Demonskinner:BAAALgADCgUJBQAAAA==.Denzo:BAAALgAECgMJAwAAAA==.Deoxyrybo:BAACLgAFFH8FAAIMAAMJPQpyGQC4AAAMAAMJPQpyGQC4AAAuAAQKfzsAAwwACQnkGXEMAE4CAAwACQnkGXEMAE4CAA0ABgmnC5WIABQBAAAA.Destructin:BAAALgAECgEJAQAAAA==.Destructor:BAAALgAECgcJEwAAAA==.Devourera:BAAALgAFFAMJAwAAAA==.',
Di='Died:BAAALgADCgMJAwAAAA==.Dilldobaggin:BAAALgADCgQJBAAAAA==.Dinoknight:BAAALgAECgcJBwAAAA==.Dinopriest:BAABLgAECn8XAAICAAcJLRcDJAChAQACAAcJLRcDJAChAQAAAA==.Distia:BAAALgAECgcJCgAAAA==.Divinedragon:BAABLgAECn8sAAMCAAkJGhhMEQBGAgACAAkJGhhMEQBGAgADAAcJ5grnLgAoAQAAAA==.Dixoncider:BAAALgAECgQJBgAAAA==.',
Do='Doboy:BAAALgADCgIJAgAAAA==.Donmanuel:BAAALgADCgEJAQAAAA==.',
Dr='Drackaris:BAAALgADCgYJBgAAAA==.Drainbamage:BAAALgAECgMJAwAAAA==.Drakin:BAABLgAECn8/AAIRAAkJ0CCFCwABAwARAAkJ0CCFCwABAwAAAA==.Dreya:BAABLgAECn8aAAIcAAkJDR0PCQAiAgAcAAkJDR0PCQAiAgAAAA==.Dreyas:BAAALgADCgYJBgAAAA==.Drinkcoolaid:BAABLgAECn8fAAIYAAkJnxbOHgBLAgAYAAkJnxbOHgBLAgAAAA==.Dritzle:BAABLgAECn8aAAMdAAgJBhXKIQDrAQAdAAgJBhXKIQDrAQAGAAQJHgi5EwDEAAAAAA==.Droopapi:BAAALgAECgYJEQAAAA==.',
Du='Durrt:BAAALgADCgcJCAABLgAECgcJLAAFAGsiAA==.Dutchman:BAACLgAFFH8VAAILAAcJEyL2BgAdAgALAAcJEyL2BgAdAgAuAAQKfxwAAgsACAkNIWYIAAsDAAsACAkNIWYIAAsDAAAA.',
Eh='Ehhmuh:BAAALgAECgYJCgAAAA==.Ehlumii:BAABLgAECn8UAAIEAAYJRSRvDgBvAgAEAAYJRSRvDgBvAgAAAA==.',
Ei='Eiffel:BAAALgADCgUJBQAAAA==.',
El='Eldrene:BAABLgAECn80AAMIAAkJXh7QGAC+AgAIAAkJXh7QGAC+AgAeAAEJ7hOWHAA6AAAAAA==.Elethil:BAAALgADCgEJAgAAAA==.Elfstomper:BAAALgADCggJCwAAAA==.Elitepaladin:BAABLgAECn8nAAIQAAkJGBbfIQAPAgAQAAkJGBbfIQAPAgAAAA==.Ellexi:BAAALgAECgYJDAAAAA==.Elrai:BAAALgAECgEJAQAAAA==.Elyseia:BAABLgAECn8gAAILAAkJgwaFgQAvAQALAAkJgwaFgQAvAQAAAA==.',
Em='Empkin:BAAALgAECgcJEwAAAA==.',
En='Enof:BAAALgADCgIJAgAAAA==.Enpower:BAAALgADCgYJBgABLgAFFAMJDgAfAI0WAA==.',
Ep='Epicsause:BAAALgAECgkJCgAAAA==.',
Er='Erelor:BAAALgADCgMJAwAAAA==.',
Es='España:BAECLgAFFH8HAAIPAAQJbxF2GgD+AAAPAAQJbxF2GgD+AAAuAAQKfy0ABA8ACQlOGj0KAHYCAA8ACQlOGj0KAHYCACAABQlGERoaAO8AAAoAAQkAAHSTAQAAAAAA.Españaluna:BAEALgAECgcJBgABLgAFFAQJBwAPAG8RAA==.Españamor:BAEALgAECgkJCAABLgAFFAQJBwAPAG8RAA==.Essdeath:BAAALgAECgEJAQAAAA==.',
Ez='Ezpain:BAAALgAECgEJAQAAAA==.',
Fa='Farael:BAAALgAECgcJBAAAAA==.Farmerbrown:BAAALgAECgMJBQABLgAFFAMJBgARAFUaAA==.Fatalmann:BAACLgAFFH8FAAMUAAMJdAV9CgBkAAAUAAIJsgJ9CgBkAAATAAIJsQFtJABfAAAuAAQKfxYAAxQACQnMD5kVAJUBABQABwmoD5kVAJUBABMABgk2Dz0bAB4BAAAA.Fatalminn:BAAALgAECgUJCQAAAA==.Fathergob:BAAALgADCgEJAQAAAA==.Fatty:BAAALgADCgYJBgAAAA==.',
Fe='Fenty:BAAALgADCgEJAQAAAA==.Feralhorn:BAAALgAECgEJAQAAAA==.',
Fi='Fingerz:BAAALgADCgIJAgAAAA==.Fintan:BAAALgAECgcJCwABLgAFFAYJHgAYAKEdAA==.',
Fl='Flarestrasz:BAAALgADCgUJCQAAAA==.Flexxar:BAAALgAECgEJAgAAAA==.Flutterby:BAAALgADCgcJDAABLgAECgkJOQACAJwJAA==.Flèxion:BAACLgAFFH8OAAIKAAUJ2R8EPQBqAQAKAAUJ2R8EPQBqAQAuAAQKfygAAgoACAkBJWEeAIoCAAoACAkBJWEeAIoCAAAA.',
Fo='Foskin:BAAALgAECgMJBAABLgAECgkJGQAVAIkbAA==.',
Fr='Frassk:BAABLgAECn9DAAMHAAkJPBuOBQAGAgAHAAcJSB2OBQAGAgAhAAQJ0hJqyQC2AAAAAA==.Freja:BAAALgADCgMJBgAAAA==.Froggystyle:BAAALgAECgYJDgABLgAECggJDgAJAAAAAA==.Frostydru:BAABLgAECn8wAAIXAAgJfiE5BwBXAgAXAAgJfiE5BwBXAgAAAA==.Frozat:BAACLgAFFH8ZAAITAAgJGxgsAwCfAgATAAgJGxgsAwCfAgAuAAQKfygAAxMACAkRIyEEAOgCABMACAkRIyEEAOgCAA4AAQmAEZ5eAEAAAAAA.Frösting:BAAALgADCgcJDgABLgAECggJQQANALkfAA==.',
Fu='Fundeedo:BAAALgAFFAIJAwAAAA==.Furballieo:BAAALgADCgIJAgAAAA==.',
Ga='Galadriels:BAAALgAECgQJBAAAAA==.Galianem:BAAALgADCgMJAwAAAA==.Gamora:BAAALgAECgYJCQAAAA==.Gandon:BAAALgAECgQJCAAAAA==.Garbarn:BAABLgAECn8WAAIRAAkJ0w+ydgB1AQARAAkJ0w+ydgB1AQAAAA==.Garonno:BAAALgADCgIJAgAAAA==.',
Ge='Gelystine:BAAALgADCgUJCgAAAA==.Geminirunes:BAAALgADCgYJBgABLgAFFAMJDgAfAI0WAA==.Germaine:BAAALgAECgQJBQAAAA==.',
Gh='Ghabi:BAAALgAECgYJBgAAAA==.Ghauri:BAAALgAECgMJBAAAAA==.',
Gi='Gia:BAABLgAECn8xAAIEAAgJpxuvEwBtAgAEAAgJpxuvEwBtAgAAAA==.',
Go='Gobx:BAAALgAECgUJBgAAAA==.Golgroth:BAABLgAECn8mAAIVAAkJXgdsNwBhAQAVAAkJXgdsNwBhAQAAAA==.Goodlocktime:BAAALgADCgIJAgAAAA==.Goodtimesm:BAAALgAECgYJCAAAAA==.Goodtymes:BAAALgAECgEJAQAAAA==.Gorearrow:BAACLgAFFH8IAAILAAQJMRL5NQA2AQALAAQJMRL5NQA2AQAuAAQKfzAAAwsACQlXItgLAOMCAAsACQlXItgLAOMCACIAAglWB2N6AFkAAAAA.Goretaint:BAAALgAECgYJDwAAAA==.Gorgesh:BAAALgADCgQJBAAAAA==.Gothladriel:BAAALgAECgYJDAAAAA==.Gottamoo:BAABLgAECn8ZAAMWAAkJJwx7JgAOAQAWAAkJJwx7JgAOAQAZAAEJPQFWkAAaAAAAAA==.',
Gr='Greenstank:BAAALgAECggJDgAAAA==.Grimmtotem:BAAALgADCgQJBAAAAA==.Grrumpybear:BAABLgAECn9CAAIWAAkJ3xuqBgCDAgAWAAkJ3xuqBgCDAgAAAA==.Grundal:BAAALgADCggJCAAAAA==.',
Gu='Gunafistya:BAAALgAFFAIJBAAAAA==.Gunnaroptiks:BAAALgAECgUJBQABLgAFFAQJFAAbAHoWAA==.Guzzler:BAAALgAECgkJDgAAAA==.',
['Gú']='Gúildarts:BAAALgADCgEJAQAAAA==.',
Ha='Haannarr:BAAALgAECgIJAgAAAA==.Hairymoodini:BAAALgAECgEJAgAAAA==.Hajin:BAAALgAECgYJDwAAAA==.Hankjr:BAAALgAECgEJAgAAAA==.Hanky:BAAALgAECgQJBAAAAA==.Havòk:BAAALgAECggJBwABLgAFFAEJAQAJAAAAAA==.Hawthorn:BAAALgAECgMJCAAAAA==.Hazyblades:BAAALgAECgMJAwAAAA==.',
He='Helacookie:BAABLgAECn8ZAAIRAAkJMBPpTQDTAQARAAkJMBPpTQDTAQAAAA==.Henso:BAAALgAECgcJBwABLgAFFAMJDgAfAI0WAA==.Heomors:BAAALgAECgEJAQAAAA==.Hexxan:BAAALgAECgUJEAAAAA==.',
Hi='Hifumi:BAAALgADCgQJBwAAAA==.Hisagu:BAAALgAECgEJAQABLgAECggJEQAJAAAAAA==.Hiver:BAAALgAECgQJBgAAAA==.',
Ho='Hoagar:BAAALgAECgcJDAABLgAFFAIJAgAJAAAAAA==.Hoegar:BAAALgAECgcJBwABLgAFFAIJAgAJAAAAAA==.Holes:BAAALgAECgEJAgAAAA==.Holier:BAACLgAFFH8HAAIRAAMJMxETYgDXAAARAAMJMxETYgDXAAAuAAQKfzkAAhEACQn+FeVBAPYBABEACQn+FeVBAPYBAAAA.Hollows:BAAALgAECgQJBgAAAA==.Holyatrops:BAAALgAECgkJEQABLgAFFAcJIQAhAMwZAA==.Hoppers:BAAALgAECgIJAgABLgAECgcJDwAJAAAAAA==.Hopperstotem:BAAALgAECgcJDwAAAA==.Horuu:BAAALgAECgQJBgAAAA==.Hoyboii:BAAALgADCgYJBgAAAA==.',
Hu='Hulo:BAAALgAECgcJCQAAAA==.Humbled:BAAALgAECgQJBQAAAA==.Hunteress:BAAALgADCgYJBwAAAA==.Huntkoalas:BAAALgAECgMJAwABLgAFFAcJIQAZAHwXAA==.Hurrdurr:BAAALgAECgEJAQAAAA==.',
['Hî']='Hîflax:BAAALgAECgEJAgAAAA==.',
['Hö']='Hölyców:BAAALgADCgQJBAAAAA==.',
Ic='Ichbinstark:BAAALgAECgEJBAAAAA==.',
Id='Idonttcare:BAAALgAECgMJAwAAAA==.',
Ig='Iggnignokt:BAAALgADCgYJBwAAAA==.',
Ih='Ihealnewbs:BAAALgADCgYJDwAAAA==.',
In='Infamus:BAAALgAECgQJCgAAAA==.Invisabull:BAAALgAECgQJBgAAAA==.Invysion:BAACLgAFFH8LAAIDAAQJsgpBJgD8AAADAAQJsgpBJgD8AAAuAAQKfy4AAgMACQkXETEbAOcBAAMACQkXETEbAOcBAAAA.',
Ir='Irri:BAAALgADCgUJBQAAAA==.',
Is='Ishara:BAAALgAECggJCAABLgAECgkJNAAIAF4eAA==.',
Ja='Jacuzzi:BAAALgAECgUJBwAAAA==.Jaidess:BAAALgAECgEJAQAAAA==.',
Je='Jeangen:BAAALgAECgUJAwAAAA==.Jeanjean:BAAALgAECgcJCAAAAA==.Jeannjeann:BAAALgAECggJEgAAAA==.Jediknîght:BAAALgAECgYJBgAAAA==.Jeep:BAACLgAFFH8NAAILAAQJnhsMOAAyAQALAAQJnhsMOAAyAQAuAAQKfycAAgsACAlAJVMEAEoDAAsACAlAJVMEAEoDAAAA.Jellybea:BAACLgAFFH8MAAIBAAQJghurDwBBAQABAAQJghurDwBBAQAuAAQKfywAAwEACQltITEEABIDAAEACQltITEEABIDAAIAAgkJDKFqAGIAAAAA.',
Ji='Jibalynne:BAAALgAECgQJBAAAAA==.Jida:BAAALgAECgEJAQAAAA==.Jiffypop:BAAALgAECgcJDQABLgAECgkJLQAVAFsdAA==.Jinwooaura:BAAALgADCgcJBwAAAA==.',
Jo='Johnnycakes:BAAALgADCgMJBQAAAA==.Jonsnowxd:BAAALgADCgYJBgAAAA==.',
Jr='Jrhnbr:BAAALgADCgMJAwAAAA==.',
Ju='Juggnut:BAAALgAECgcJEQAAAA==.Jump:BAAALgAECgcJEwAAAA==.Junglebrew:BAAALgADCgQJBAAAAA==.Jurisdiction:BAABLgAECn8qAAIRAAgJVRLMYQCiAQARAAgJVRLMYQCiAQAAAA==.',
Jz='Jz:BAAALgAECgMJAwAAAA==.',
['Jì']='Jìnn:BAAALgAECgUJDwAAAA==.',
Ka='Kaan:BAABLgAECn8sAAIFAAcJayJLEwCbAgAFAAcJayJLEwCbAgAAAA==.Kabea:BAAALgAECgEJAQAAAA==.Kadath:BAAALgADCgIJAwAAAA==.Kaeladín:BAAALgAECgUJCAAAAA==.Kagebouzu:BAAALgAECgYJDwAAAA==.Kahlan:BAAALgADCgcJCAABLgAECgYJDwAJAAAAAA==.Kakutogi:BAAALgADCgEJAQAAAA==.Kalycia:BAAALgAECgEJAQAAAA==.Kamela:BAAALgAECgYJCAAAAA==.Karael:BAAALgAECgUJEQABLgAECgkJDQAJAAAAAA==.Karma:BAAALgAECgYJEgAAAA==.Kayliaa:BAAALgAECgkJAQAAAA==.Kazarke:BAAALgADCgcJGAAAAA==.',
Ke='Keeia:BAAALgADCgQJBQAAAA==.Keho:BAABLgAECn8qAAMbAAgJlgwQLABQAQAbAAgJJwwQLABQAQAfAAIJkg6maABqAAAAAA==.Kenalia:BAABLgAECn8qAAIEAAkJlRYAGQA9AgAEAAkJlRYAGQA9AgAAAA==.Kengo:BAAALgAECgEJAQAAAA==.Keptalive:BAAALgADCgcJCgAAAA==.Kerzermern:BAAALgAFFAMJAwAAAA==.Kevic:BAAALgAFFAIJAwABLgAFFAQJDgACABAOAA==.',
Kh='Khamaelion:BAAALgADCgcJDgAAAA==.',
Ki='Kiara:BAABLgAECn8eAAIRAAgJNiBdIgCgAgARAAgJNiBdIgCgAgAAAA==.Kiju:BAAALgADCgYJBgAAAA==.Killaban:BAACLgAFFH8KAAIVAAQJ9BdZGwA2AQAVAAQJ9BdZGwA2AQAuAAQKfzIAAxUACQklIG4WADUCABUACQngH24WADUCACMAAwkZGVMrAJoAAAAA.Killbydeath:BAAALgAECgEJAQAAAA==.Kimberlyhárt:BAACLgAFFH8GAAIRAAMJVRpwUAD9AAARAAMJVRpwUAD9AAAuAAQKfzcAAxEACQnxJPcDAFgDABEACQnxJPcDAFgDABAABAn0CuNfAKgAAAAA.Kissmydots:BAABLgAECn9EAAIhAAkJKR7fFQCcAgAhAAkJKR7fFQCcAgAAAA==.Kitja:BAABLgAECn9AAAMDAAkJsR8CBABSAwADAAkJsR8CBABSAwABAAgJaBzfDwBdAgAAAA==.Kitla:BAAALgADCgUJBQABLgAECgkJQAADALEfAA==.',
Kl='Klipsch:BAAALgADCgUJBQAAAA==.Klukai:BAAALgADCgcJCwABLgAECgkJIAAFAPMdAA==.',
Kn='Kneed:BAAALgADCgYJBgAAAA==.',
Ko='Koala:BAAALgAECgQJBQABLgAFFAcJIQAZAHwXAA==.Kohman:BAABLgAECn8bAAIhAAYJ3RXOfABiAQAhAAYJ3RXOfABiAQAAAA==.Konyani:BAAALgADCgUJAQAAAA==.',
Kp='Kpop:BAAALgAECgEJAQABLgAECgcJBwAJAAAAAA==.',
Kr='Kraeven:BAAALgADCgEJAQAAAA==.Kregerath:BAAALgADCgIJAgAAAA==.Krftpnk:BAACLgAFFH8WAAIMAAQJPCYUBAC6AQAMAAQJPCYUBAC6AQAuAAQKfyYAAwwACQm1JDcEADcDAAwACQm1JDcEADcDAA0AAQkAAH42AQAAAAAA.Krom:BAABLgAECn8tAAMVAAkJWx2dEABrAgAVAAkJWx2dEABrAgAjAAEJPQl9eQAnAAAAAA==.Kronas:BAABLgAECn8VAAILAAgJ3RXhWgCIAQALAAgJ3RXhWgCIAQAAAA==.Kronophyne:BAACLgAFFH8GAAIIAAQJChFLVgAxAQAIAAQJChFLVgAxAQAuAAQKfzcAAggACQn5HVgxAE0CAAgACQn5HVgxAE0CAAAA.Kronotality:BAACLgAFFH8HAAMPAAMJ5xOMMgBZAAAKAAMJXQvgmwDOAAAPAAEJJR+MMgBZAAAuAAQKf0oAAg8ACQkZJRYCADIDAA8ACQkZJRYCADIDAAAA.Kronotek:BAAALgAECgcJDQAAAA==.Kronotekken:BAAALgADCgYJBgAAAA==.Kronotide:BAAALgAECgYJDAAAAA==.',
Ku='Kurohitsugî:BAAALgAECgIJBAAAAA==.',
Ky='Kylorai:BAAALgAECgYJEgAAAA==.Kynbrochel:BAAALgAECgYJCgAAAA==.',
La='Laars:BAAALgAECgUJDAABLgAECggJJQAhADsNAA==.Laimaster:BAAALgAECgEJAgAAAA==.Lakiri:BAABLgAECn84AAIcAAkJtBr6BgBWAgAcAAkJtBr6BgBWAgAAAA==.Landaeda:BAAALgAECgcJDgAAAA==.Lanney:BAAALgAECgYJBgAAAA==.Lapsu:BAABLgAECn8fAAIfAAkJjRTcGgDNAQAfAAkJjRTcGgDNAQAAAA==.Lascivia:BAACLgAFFH8NAAMVAAQJ5B2YFABVAQAVAAQJ5B2YFABVAQAkAAQJQBKIFADrAAAuAAQKfyYAAxUACQkAH1AmACcCABUACQmIHFAmACcCACQACAnlENUcAEIBAAAA.Lawhanx:BAAALgADCgEJAQABLgAFFAEJAQAJAAAAAA==.Laylahh:BAAALgADCgMJBAAAAA==.Lazy:BAABLgAECn8WAAMhAAYJyRcpiQBHAQAhAAUJyRcpiQBHAQAHAAIJxQGEYQBLAAAAAA==.',
Le='Leademon:BAABLgAECn9AAAMNAAkJ6SAzEAC4AgANAAkJ6SAzEAC4AgAMAAIJTRrWWgB2AAAAAA==.Leadmin:BAAALgADCgMJBQABLgAECgkJQAANAOkgAA==.Leadmln:BAAALgADCgcJBwABLgAECgkJQAANAOkgAA==.Leftlane:BAABLgAECn8uAAMYAAkJsiGFBQBQAwAYAAkJsiGFBQBQAwAaAAEJgA1SnwAsAAAAAA==.Legato:BAAALgAECgcJCAABLgAFFAcJHwAYAPUgAA==.Lehsham:BAAALgAECgkJAgAAAA==.Lekiri:BAAALgAECgYJCAAAAA==.Lep:BAAALgAFFAQJBAABLgAFFAgJGQATABsYAA==.Lethalkrits:BAAALgAECgcJAgAAAA==.Leva:BAABLgAECn8gAAIFAAkJ8x19FwCCAgAFAAkJ8x19FwCCAgAAAA==.',
Li='Liberté:BAAALgAECgIJAgAAAA==.Liciano:BAAALgAECgkJDQAAAA==.Lie:BAACLgAFFH8HAAIdAAIJTgteMACQAAAdAAIJTgteMACQAAAuAAQKfzsAAh0ACQkNGSQMAFYCAB0ACQkNGSQMAFYCAAAA.Lightsdown:BAAALgAECgYJBgAAAA==.Lilbeebs:BAAALgAECgkJEQAAAA==.Lileth:BAAALgAECgkJAgAAAA==.Lilflea:BAAALgAECggJEQAAAA==.Lilzuki:BAAALgAECgkJEwAAAA==.Lilïth:BAACLgAFFH8OAAIPAAUJ8B//FwATAQAPAAUJ8B//FwATAQAuAAQKfyAAAg8ABwmDJPIGAMICAA8ABwmDJPIGAMICAAAA.Linguine:BAAALgAECgEJAwABLgAFFAUJEwABABIVAA==.Lisalisa:BAABLgAECn88AAIYAAgJ6Rg0KAAQAgAYAAgJ6Rg0KAAQAgAAAA==.Livan:BAAALgAECgMJAwAAAA==.Livia:BAAALgAECgEJAQAAAA==.',
Lo='Lohzak:BAAALgAECgEJAQAAAA==.Lousier:BAAALgAECgEJAQAAAA==.',
Lu='Lularia:BAAALgADCgIJAgAAAA==.Lumii:BAAALgAECgYJBgABLgAECgYJFAAEAEUkAA==.Luminari:BAAALgADCgEJAQABLgAECgkJNAAIAF4eAA==.Lunaa:BAAALgAECgkJDAAAAA==.Lurassa:BAAALgAECgYJDAAAAA==.',
Ly='Lyacon:BAAALgADCgQJBAABLgAECgkJFQAIAEEcAA==.',
['Lä']='Lä:BAEALgAECgcJBwABLgAFFAMJBAAJAAAAAA==.',
Ma='Madrie:BAAALgAECgQJBAAAAA==.Maekar:BAABLgAECn8aAAIUAAYJOg6ZDwAGAQAUAAYJOg6ZDwAGAQAAAA==.Maellus:BAAALgAECgEJAQAAAA==.Maelstorm:BAAALgADCgIJAgAAAA==.Mageman:BAAALgADCgYJAgAAAA==.Magickdragon:BAAALgAECgUJBQABLgAECgkJLAACABoYAA==.Magicmoo:BAAALgAECgEJAQABLgAFFAMJBgARAFUaAA==.Maltis:BAAALgADCgcJCwAAAA==.Mananstuff:BAACLgAFFH8FAAIZAAMJqQQ2NQCPAAAZAAMJqQQ2NQCPAAAuAAQKf0QAAhkACQmIEYodAM8BABkACQmIEYodAM8BAAAA.Manaproblems:BAAALgADCgMJBAAAAA==.Mandemic:BAAALgAECgYJBgABLgAFFAQJDwAVAEcZAA==.Marguerek:BAAALgADCgEJAQAAAA==.Marinara:BAAALgAECgYJDAABLgAECgYJDAAJAAAAAA==.Markamanimal:BAACLgAFFH8PAAIXAAQJjBpOBQBPAQAXAAQJjBpOBQBPAQAuAAQKfyUAAhcACAnfIYYDAPwCABcACAnfIYYDAPwCAAAA.Marnix:BAABLgAECn8bAAIaAAgJmRJnLACFAQAaAAgJmRJnLACFAQAAAA==.Marshail:BAAALgAECgEJAQAAAA==.',
Md='Mdbeef:BAAALgAECgUJBQAAAA==.',
Me='Medikus:BAABLgAECn8jAAMYAAgJbxxeHgBOAgAYAAgJbxxeHgBOAgAaAAMJ2gzRcgCBAAAAAA==.Meesoomagi:BAAALgAECgYJBwAAAA==.Megajoo:BAAALgAFFAIJBAAAAA==.Menil:BAABLgAECn8XAAMEAAgJwBtXFgAQAgAEAAcJJhpXFgAQAgAfAAQJchaMTADEAAAAAA==.Merryl:BAAALgAECggJDgAAAA==.Meyounow:BAAALgAECgEJBAAAAA==.',
Mi='Midnye:BAAALgADCgYJBgAAAA==.Mike:BAECLgAFFH8GAAMlAAQJqhF/AwChAAAlAAIJzBl/AwChAAAIAAIJiAnwngCIAAAuAAQKfzoAAyUACQmDJI0AAAQDACUACQlAIo0AAAQDAAgACAlkIN1RAOABAAAA.Mips:BAAALgAFFAMJBAAAAA==.',
Mk='Mk:BAEALgADCgcJBwABLgAECgkJQQAfAIAgAA==.',
Mo='Mob:BAAALgADCgcJBwAAAA==.Mockra:BAABLgAECn8+AAMIAAkJViJoEgDnAgAIAAkJViJoEgDnAgAeAAIJuBiqGgBCAAAAAA==.Monafae:BAAALgADCgUJBQAAAA==.Moohammered:BAAALgAECgMJBAAAAA==.Moolou:BAACLgAFFH8NAAISAAQJyxb2BQAXAQASAAQJyxb2BQAXAQAuAAQKfyMAAhIACQm1H7cFAIYCABIACQm1H7cFAIYCAAAA.Moonraka:BAAALgADCgUJBQAAAA==.Moosé:BAAALgAECgEJAQABLgAFFAgJJgARAO8UAA==.Mootilater:BAAALgADCgQJAQAAAA==.Mootilator:BAAALgADCgYJBgAAAA==.Moraei:BAAALgADCgEJAQAAAA==.Mordew:BAAALgADCgUJBQABLgAECgkJOgAKAJclAA==.Morechie:BAABLgAECn8hAAImAAkJcBX9BgD1AQAmAAkJcBX9BgD1AQAAAA==.Morecowbell:BAAALgAECgEJAQAAAA==.Morgatho:BAAALgADCgEJAwAAAA==.Mortiferon:BAABLgAECn82AAIKAAkJCh/8EwDIAgAKAAkJCh/8EwDIAgAAAA==.',
Mu='Muhgunguh:BAAALgAECgEJAQAAAA==.Munnky:BAABLgAECn8tAAIEAAcJ1iH1DwCTAgAEAAcJ1iH1DwCTAgAAAA==.Murmaider:BAAALgADCgIJAgAAAA==.',
My='Mythrandere:BAAALgADCgcJCwAAAA==.Mytu:BAAALgADCgUJBgAAAA==.',
['Má']='Mánflu:BAACLgAFFH8PAAIVAAQJRxlTGABDAQAVAAQJRxlTGABDAQAuAAQKfysAAyMACQniHhIDAOICACMACQniHhIDAOICABUABwlJGlI0ANkBAAAA.',
['Mô']='Môrrigãn:BAAALgADCgMJAwAAAA==.',
['Mö']='Mörgänä:BAAALgADCgMJAwAAAA==.',
Na='Naissa:BAAALgAECgQJCwAAAA==.Nakanir:BAAALgAECgYJBgAAAA==.Nalfeign:BAAALgAECgQJBQAAAA==.Napa:BAAALgAECgUJCAABLgAFFAYJFwAYAKMXAA==.Narn:BAABLgAECn9DAAQOAAkJOByNEwA6AgAUAAcJrRjRCQBCAgAOAAkJ5RiNEwA6AgATAAIJLQiEQQBgAAAAAA==.',
Ne='Nealite:BAAALgAECgkJBgAAAA==.Necrotion:BAAALgAECgYJEgAAAA==.Nei:BAAALgAECgEJAQAAAA==.Nerrisa:BAABLgAECn8iAAICAAkJERS+HgDHAQACAAkJERS+HgDHAQAAAA==.Nertt:BAAALgADCgYJBgABLgAECgkJQwATADEZAA==.Neublood:BAAALgAECgQJCAAAAA==.',
Ni='Nicodemus:BAAALgAECgcJDAAAAA==.',
No='Noblewarrior:BAACLgAFFH8hAAIVAAgJOhsVAgBYAgAVAAgJOhsVAgBYAgAuAAQKfysAAhUACAmuJGsMAJwCABUACAmuJGsMAJwCAAAA.Noctilus:BAAALgAECgcJCQAAAA==.Nohkari:BAAALgADCgkJHQABLgAECgkJJAAhANAUAA==.Nooj:BAACLgAFFH8wAAMGAAgJmSMbAAD3AgAGAAgJmSMbAAD3AgAdAAYJiRT8EABwAQAuAAQKfx4AAwYACQl7ITsAAMMDAAYACQl7ITsAAMMDAB0ABgmFEpA6AEQBAAAA.Notakoala:BAACLgAFFH8hAAIZAAcJfBfkCQDZAQAZAAcJfBfkCQDZAQAuAAQKfycAAxkACAlHJFQNAMUCABkACAlHJFQNAMUCABYAAQk3Ek1oADMAAAAA.Nothnx:BAAALgAFFAEJAwAAAA==.Notoriouspat:BAABLgAECn8fAAILAAgJrg5GWQCMAQALAAgJrg5GWQCMAQAAAA==.Notsamadeath:BAABLgAFFH8KAAMgAAQJWRGEDAAeAQAgAAQJWRGEDAAeAQAKAAIJ3wim2gCBAAAAAA==.Novia:BAAALgAECgYJBgAAAA==.Noyber:BAAALgAFFAIJAgAAAA==.Noydin:BAAALgAFFAIJAwAAAA==.',
['Ní']='Nínebreaker:BAAALgAECgMJAwAAAA==.',
['Nü']='Nüll:BAAALgAECggJEwAAAA==.',
Ob='Obern:BAABLgAECn8WAAInAAkJZhv0FAD5AQAnAAkJZhv0FAD5AQAAAA==.Oblïna:BAABLgAECn8lAAIEAAgJsAkLTwAWAQAEAAgJsAkLTwAWAQAAAA==.',
Od='Odiumaeterna:BAAALgADCgcJBwAAAA==.',
Of='Offensivé:BAAALgAECgMJCAAAAA==.Oftheages:BAAALgAECgIJAgABLgAFFAgJGQATABsYAA==.',
On='Onetozerosix:BAABLgAECn8iAAIKAAkJ/xv4OgANAgAKAAkJ/xv4OgANAgAAAA==.Onos:BAAALgAECgEJAQAAAA==.Onsen:BAAALgAECgQJBgAAAA==.',
Oo='Oogak:BAAALgAECgUJBgAAAA==.Oomigig:BAAALgADCgUJBQAAAA==.',
Op='Opalily:BAAALgAECgEJAQAAAA==.Operation:BAAALgAECgQJCAAAAA==.',
Or='Oresties:BAAALgAECgYJBgAAAA==.Orestisies:BAAALgAECgYJBgAAAA==.Orghrax:BAAALgADCgEJAQAAAA==.Orisys:BAAALgAECgIJAwAAAA==.',
Os='Osteer:BAAALgAECgYJBgAAAA==.',
Ot='Otterjim:BAAALgADCgQJBAAAAA==.',
Pa='Padfoote:BAAALgADCgEJAgAAAA==.Pahaa:BAAALgAECgUJBQAAAA==.Pairadeez:BAAALgAECgYJDwAAAA==.Pajamabanana:BAAALgADCgIJAgAAAA==.Pandablaze:BAAALgAECgYJDgAAAA==.Panterarey:BAAALgADCgYJEAAAAA==.Papalego:BAABLgAECn8wAAILAAkJfg00RgDDAQALAAkJfg00RgDDAQAAAA==.Parakka:BAABLgAECn82AAIYAAkJGhZdHwBHAgAYAAkJGhZdHwBHAgAAAA==.Patak:BAAALgAECgMJAwAAAA==.Pavle:BAAALgAECgMJAwAAAA==.Pawp:BAAALgAECgYJCgABLgAECggJHwABAMUSAA==.',
Pe='Pearagon:BAABLgAECn8VAAICAAgJwBGVIwCkAQACAAgJwBGVIwCkAQABLgAFFAYJFwAYAKMXAA==.Pepsidew:BAAALgADCgcJDAAAAA==.Pepsisprite:BAABLgAECn84AAIBAAkJsRk1DACVAgABAAkJsRk1DACVAgAAAA==.Pesky:BAABLgAECn8hAAIZAAYJJBbYMgBAAQAZAAYJJBbYMgBAAQABLgAFFAQJCgAIAGERAA==.',
Pf='Pfchanguz:BAAALgADCgcJDAAAAA==.',
Ph='Phdbeef:BAABLgAFFH8HAAIWAAIJ+xtZGgClAAAWAAIJ+xtZGgClAAABLgAFFAUJDgAPAPAfAA==.Phlemm:BAAALgAECgEJAQAAAA==.Phoivos:BAABLgAECn8VAAIIAAkJQRwKIQDvAgAIAAkJQRwKIQDvAgAAAA==.',
Pi='Picklez:BAABLgAECn8uAAIKAAgJ9SFGFwCzAgAKAAgJ9SFGFwCzAgAAAA==.Pissflizzle:BAABLgAECn8dAAIhAAgJ9w2OZABxAQAhAAgJ9w2OZABxAQAAAA==.',
Pl='Plaquenil:BAAALgADCgEJAQAAAA==.',
Po='Poison:BAAALgADCgEJAQAAAA==.Porkroaster:BAABLgAECn8nAAIIAAgJhAz5fQB1AQAIAAgJhAz5fQB1AQAAAA==.',
Pr='Praye:BAAALgAFFAMJAwAAAA==.Priestop:BAAALgAECgEJAQAAAA==.',
Ps='Psyfarian:BAAALgADCgcJDQAAAA==.Psyop:BAAALgAECgYJBwABLgAECggJGgABAAUcAA==.',
Pu='Pushemover:BAAALgAECgMJBQAAAA==.',
Qu='Quillswitch:BAAALgAECgEJAQAAAA==.',
Ra='Radduc:BAABLgAECn8ZAAMQAAYJKxhlNAB2AQAQAAYJKxhlNAB2AQARAAEJlQZanAEpAAAAAA==.Ragerade:BAAALgAECgYJBwAAAA==.Raidu:BAAALgAECgMJAwAAAA==.Ralpherion:BAAALgADCgIJAgAAAA==.Ranoa:BAAALgAECgQJCgAAAA==.Raphåel:BAAALgAFFAEJAQAAAA==.Ravioli:BAAALgAECgQJBgAAAA==.Razialum:BAAALgADCgYJBgAAAA==.Razorsteps:BAAALgAFFAcJBAAAAA==.Razzberry:BAAALgADCgYJDAAAAA==.',
Re='Rebrowth:BAAALgAECgcJEgAAAA==.Redren:BAAALgADCgIJAgAAAA==.Reegrets:BAAALgAECggJDQAAAA==.Reena:BAAALgADCgIJAwAAAA==.Regiplague:BAAALgAECgYJCwAAAA==.Regretty:BAAALgAECggJDQABLgAECggJDQAJAAAAAA==.Renthar:BAAALgADCgUJBQAAAA==.Renzdingo:BAAALgAECgkJDwAAAA==.Repete:BAAALgAECgUJDgAAAA==.Resyek:BAABLgAECn85AAIIAAgJOyTMGQC5AgAIAAgJOyTMGQC5AgAAAA==.Reverendgank:BAAALgAECgEJAQAAAA==.',
Rh='Rhaxanna:BAAALgADCgYJBgAAAA==.',
Ri='Rick:BAAALgAFFAMJAwAAAA==.Rickheaddk:BAAALgADCgEJAgAAAA==.Riivan:BAABLgAECn8iAAIhAAgJihB1VgCUAQAhAAgJihB1VgCUAQAAAA==.Rini:BAAALgAECgkJEQABLgABCgYJCwAJAAAAAA==.Rishi:BAABLgAECn86AAIRAAkJQxaLTQDUAQARAAkJQxaLTQDUAQAAAA==.Rivian:BAAALgADCgIJAgAAAA==.',
Ro='Robot:BAABLgAECn8kAAIEAAgJ7g8vPwBXAQAEAAgJ7g8vPwBXAQAAAA==.Rokmog:BAAALgAECgcJDgAAAA==.Rollinburn:BAAALgADCgYJCQAAAA==.Roxanol:BAAALgADCgEJAQABLgAECgkJPQAQACUaAA==.',
Ru='Rumbrave:BAAALgAECgYJCwAAAA==.Rumtumtugger:BAAALgADCgkJCQAAAA==.',
['Rá']='Ráyune:BAAALgADCgcJBwAAAA==.',
Sa='Sackos:BAAALgAECgEJAgAAAA==.Sadpanda:BAAALgADCgUJCAAAAA==.Saffronspark:BAAALgADCgkJHwABLgAECgkJRQAfAI4iAA==.Sainsei:BAABLgAECn8ZAAMbAAcJcgUpTwC8AAAbAAcJqAIpTwC8AAAfAAUJBAfiXgCPAAAAAA==.Saith:BAAALgAECgEJBgAAAA==.Samasear:BAABLgAECn8UAAIVAAgJ0w8wMgDjAQAVAAgJ0w8wMgDjAQABLgAFFAcJHAAKAHIeAA==.Sandwitch:BAABLgAECn9DAAMhAAkJLRiXLQAcAgAhAAkJLRiXLQAcAgAHAAIJmxB0UwB0AAAAAA==.Sanoa:BAABLgAFFH8GAAIcAAMJcgPJDwCkAAAcAAMJcgPJDwCkAAAAAA==.Sargatana:BAABLgAECn83AAIbAAkJbR90BQDiAgAbAAkJbR90BQDiAgAAAA==.Sars:BAABLgAECn8sAAMEAAgJHSW+BABWAwAEAAgJHSW+BABWAwAfAAMJGhOOWgCbAAAAAA==.Sauronxd:BAAALgAECgUJCAAAAA==.',
Sc='Scalion:BAABLgAECn8nAAMNAAgJOR7CIgA7AgANAAgJOR7CIgA7AgAMAAQJ+BG9SwDAAAABLgAFFAEJAQAJAAAAAA==.Scarne:BAAALgAECgIJAgAAAA==.Schrodinger:BAABLgAECn8dAAISAAgJuAoDHwAPAQASAAgJuAoDHwAPAQAAAA==.Scravenhoof:BAAALgAECgYJBgAAAA==.',
Se='Selunee:BAAALgADCgEJAQAAAA==.Sepharad:BAAALgADCggJEgAAAA==.Septicflësh:BAAALgADCgEJAQAAAA==.Severum:BAABLgAECn88AAIkAAkJYh1nBgCcAgAkAAkJYh1nBgCcAgAAAA==.',
Sh='Shabang:BAAALgAECgEJAQABLgAECgYJEwAJAAAAAA==.Shadowtiger:BAABLgAECn8uAAILAAkJUQxcSAC8AQALAAkJUQxcSAC8AQAAAA==.Shadrad:BAACLgAFFH8HAAIRAAQJdx0OJABjAQARAAQJdx0OJABjAQAuAAQKfxsAAhEACQnFJacHACgDABEACQnFJacHACgDAAAA.Shamanor:BAAALgAECgcJCAAAAA==.Shammoo:BAAALgAECgIJBAABLgAFFAgJJgARAO8UAA==.Shantz:BAABLgAECn8qAAIPAAgJFhRiGgB/AQAPAAgJFhRiGgB/AQAAAA==.Shiban:BAABLgAECn8WAAInAAkJEw6QFAD9AQAnAAkJEw6QFAD9AQAAAA==.Shirtless:BAAALgAECggJEQAAAA==.Shockra:BAABLgAECn8dAAIaAAkJ4xdQIQDLAQAaAAkJ4xdQIQDLAQAAAA==.Shokalypse:BAAALgADCgEJAQAAAA==.Shortbuss:BAAALgADCgYJEgAAAA==.',
Si='Sige:BAAALgADCgYJBgAAAA==.Sillygoose:BAAALgADCgkJDwAAAA==.Silverfox:BAAALgADCgMJAQABLgAECgkJPgAIAFYiAA==.Silx:BAABLgAECn8VAAMDAAcJMBE8IQCJAQADAAcJMBE8IQCJAQACAAEJoBZEXQA/AAAAAA==.Simvastatin:BAAALgADCgQJBAAAAA==.Sinterdeath:BAAALgAECgIJAgAAAA==.Sithiry:BAAALgAECgEJAQAAAA==.',
Sk='Skik:BAAALgAECgUJBQAAAA==.Skulltide:BAAALgADCgcJCQAAAA==.',
Sl='Slaggz:BAAALgADCgQJBAAAAA==.Slamvoke:BAAALgAECgYJBgABLgAFFAUJDwAVAKwVAA==.Slaté:BAAALgAECgEJAgABLgAECgMJBQAJAAAAAA==.Slowrot:BAAALgAECgQJBAABLgAFFAMJBgARAFUaAA==.Slâte:BAAALgAFFAEJAgAAAA==.',
Sm='Smiteasaurus:BAAALgAECgEJAQAAAA==.Smokkie:BAAALgAECgIJAgAAAA==.Smorthian:BAAALgAECgcJDQAAAA==.',
Sn='Snarll:BAAALgADCgEJAQAAAA==.Sniffinsteak:BAABLgAECn8bAAMfAAkJGiEbBgDjAgAfAAkJGiEbBgDjAgAEAAEJtwvqswAkAAAAAA==.',
So='Solas:BAAALgADCgYJBgAAAA==.Somaliabiggs:BAAALgAECgYJCgAAAA==.Sonar:BAAALgADCgYJBgABLgAECgkJOgAKAJclAA==.Sorraba:BAABLgAFFH8JAAIIAAQJMwIFhQDFAAAIAAQJMwIFhQDFAAAAAA==.Sorrabo:BAACLgAFFH8NAAIDAAQJ7gd5KQDlAAADAAQJ7gd5KQDlAAAuAAQKfx4ABAMACQlnFJ4TADUCAAMACQlnFJ4TADUCAAEAAwm7Ay9hAEsAAAIAAQkpA9eOACEAAAAA.Sorraug:BAAALgAECgQJBAAAAA==.Soryan:BAABLgAECn8aAAIRAAgJOAfTlQBRAQARAAgJOAfTlQBRAQAAAA==.Sosalkin:BAAALgAECgcJEQAAAA==.Souls:BAACLgAFFH8VAAIhAAUJ8B2FMgBkAQAhAAUJ8B2FMgBkAQAuAAQKfx4ABCEABwnhIyYXAMkCACEABwnhIyYXAMkCACYAAQkAAPIfAHIAAAcAAQm1GkhiAEoAAAAA.',
Sp='Spankenstine:BAABLgAECn8kAAMRAAkJHRemQQD3AQARAAkJHRemQQD3AQAQAAUJowh+YwDuAAABLgABCgYJCwAJAAAAAA==.Spannky:BAAALgAECgYJDAABLgAECgcJLQAEANYhAA==.',
Sq='Squishÿ:BAAALgAECgYJDwAAAA==.',
St='Starshriek:BAAALgADCgcJBwAAAA==.Stinkydeathy:BAAALgAECgEJAQABLgAECgYJHAAbAMwYAA==.Stinkyfree:BAABLgAECn8cAAIbAAYJzBjSLgCcAQAbAAYJzBjSLgCcAQAAAA==.Stinkynatto:BAAALgADCgYJBgABLgAECgYJHAAbAMwYAA==.Stormcharred:BAABLgAECn8eAAIIAAgJ6SCgKADQAgAIAAgJ6SCgKADQAgAAAA==.Stormknight:BAAALgAECgUJEAAAAA==.Straka:BAABLgAECn8fAAIFAAkJERIZPgCrAQAFAAkJERIZPgCrAQAAAA==.',
Su='Suffers:BAAALgAECgEJAQAAAA==.Suneater:BAAALgAECgEJAgAAAA==.Sunmane:BAAALgAECgEJAQABLgAECggJHwAXANMUAA==.Supaheals:BAAALgAECgEJAQAAAA==.Superdk:BAAALgAFFAQJBAABLgAFFAgJFQARAOIaAA==.Superdruid:BAAALgADCgUJBQABLgAFFAgJFQARAOIaAA==.Supermonks:BAAALgAECggJDAABLgAFFAgJFQARAOIaAA==.Superpi:BAABLgAECn8aAAIDAAcJFx4jEgBHAgADAAcJFx4jEgBHAgABLgAFFAgJFQARAOIaAA==.Superret:BAACLgAFFH8VAAIRAAgJ4hoRDADvAQARAAgJ4hoRDADvAQAuAAQKfycAAxEACQkGI/gOABYDABEACQkGI/gOABYDABAAAQn7FKyCADsAAAAA.Superskeet:BAACLgAFFH8HAAIQAAMJtAsqMQCjAAAQAAMJtAsqMQCjAAAuAAQKfyUAAhAACAl3F9ogAPEBABAACAl3F9ogAPEBAAAA.',
Sw='Swaggbag:BAAALgADCgEJAQAAAA==.Swiftia:BAABLgAECn8VAAMiAAYJlBZYOwBzAQAiAAYJjhRYOwBzAQALAAUJAg37uADBAAAAAA==.Swiftybutt:BAAALgAECggJCgAAAA==.',
Sy='Sylphièl:BAACLgAFFH8PAAMGAAUJqAJ+BgD7AAAGAAUJqAJ+BgD7AAAoAAEJqQJiAgBEAAAuAAQKfygAAwYACAkwDvwKAHoBACgACAmbCq8EALkBAAYACAlDDfwKAHoBAAAA.Syncere:BAAALgAFFAIJAgAAAA==.Synhunt:BAAALgAFFAEJAgAAAA==.Syrene:BAAALgAECgMJBgAAAA==.',
Ta='Tandarì:BAACLgAFFH8ZAAIRAAUJWB+IJwBYAQARAAUJWB+IJwBYAQAuAAQKfyIAAhEACQmjHqoPABEDABEACQmjHqoPABEDAAAA.Tano:BAAALgAECgUJCQABLgAECgkJPgAIAFYiAA==.Tanparo:BAAALgAECgMJAwAAAA==.Tarick:BAAALgAECgYJCAAAAA==.Tasty:BAAALgAECgQJCwAAAA==.Tawnii:BAAALgADCgcJEgAAAA==.Tazath:BAAALgAECgEJAwAAAA==.Taírn:BAAALgAECgYJEQAAAA==.',
Te='Tehpredator:BAAALgAFFAMJAwAAAA==.Teilin:BAACLgAFFH8fAAIYAAcJ9SBVBABmAgAYAAcJ9SBVBABmAgAuAAQKfyIAAhgACQmQI7MEACcDABgACQmQI7MEACcDAAAA.Tenderloin:BAAALgAECgYJBgAAAA==.Teralynn:BAAALgAECgEJAQAAAA==.',
Th='Thalendor:BAAALgAECgIJAgAAAA==.Theaterthug:BAAALgAECgIJAgAAAA==.Thehulkster:BAAALgAECgMJAwAAAA==.Thetinman:BAAALgAECgEJAQAAAA==.Thevelo:BAAALgAECgIJAgABLgAECgcJFQAnAM4TAA==.Thewhole:BAAALgAFFAIJAQAAAA==.Theßigshot:BAABLgAECn8VAAIFAAYJICPAIgAyAgAFAAYJICPAIgAyAgAAAA==.Thoseheals:BAAALgADCgQJBAAAAA==.Thunderskeet:BAACLgAFFH8KAAINAAMJARmeVADdAAANAAMJARmeVADdAAAuAAQKfzwAAw0ACQkFJXADAEkDAA0ACQkFJXADAEkDAAwABwlYHRAUADICAAAA.Thundurus:BAACLgAFFH8PAAIaAAUJihMYIgAIAQAaAAUJihMYIgAIAQAuAAQKfyUAAhoACAm9FsEzAF4BABoACAm9FsEzAF4BAAAA.',
Ti='Timmayy:BAABLgAECn8kAAIhAAgJCBZ5OQAmAgAhAAgJCBZ5OQAmAgAAAA==.Tindrill:BAABLgAECn8tAAIjAAkJeiWvAAB2AwAjAAkJeiWvAAB2AwAAAA==.Tireiron:BAAALgADCgYJBgAAAA==.',
To='Tomraedisk:BAABLgAECn8ZAAIVAAkJiRvFFABDAgAVAAkJiRvFFABDAgAAAA==.Totemagoat:BAACLgAFFH8bAAMYAAYJUhmvIgBHAQAYAAUJmBavIgBHAQAaAAUJ+hBXIwACAQAuAAQKfzIAAxoACQkJHR8XAB4CABoACAnQGx8XAB4CABgACAlIFdgsANcBAAAA.Totemlyfine:BAABLgAECn8yAAMYAAgJlSKxDgDSAgAYAAgJlSKxDgDSAgAaAAQJMBVwWwDCAAAAAA==.Totesmugoats:BAAALgAECggJEgAAAA==.Toxicshock:BAAALgADCgEJAQAAAA==.',
Tr='Traprkeepr:BAAALgADCgcJEgAAAA==.Treechains:BAABLgAECn8WAAMYAAYJ8hfKSwBzAQAYAAYJ8hfKSwBzAQAaAAEJZQPtkQAlAAAAAA==.Treefist:BAAALgAFFAEJAgAAAA==.Treeshield:BAAALgADCgYJBgAAAA==.Trickster:BAAALgAECgEJAQAAAA==.Truth:BAAALgADCgcJDQAAAA==.',
Ts='Tsumuji:BAAALgAECgEJAQAAAA==.',
Tu='Turbobis:BAAALgAECgIJAgAAAA==.',
Tw='Twentyfour:BAACLgAFFH8JAAIFAAMJJgVaRwCUAAAFAAMJJgVaRwCUAAAuAAQKfxUAAgUABwmGEOVdADgBAAUABwmGEOVdADgBAAAA.Twigberry:BAAALgAECgUJCAAAAA==.',
Ty='Tygra:BAAALgAECgcJCwAAAA==.Typeshxxt:BAAALgADCgEJAQAAAA==.Tytanea:BAAALgAECgMJBAAAAA==.',
['Tø']='Tøqa:BAAALgAFFAEJAQAAAA==.',
Uh='Uhnderstood:BAABLgAECn8mAAIEAAkJjh1qEABUAgAEAAkJjh1qEABUAgAAAA==.',
Un='Undeadmonks:BAACLgAFFH8KAAIbAAMJYhUGMgDTAAAbAAMJYhUGMgDTAAAuAAQKf0kAAxsACQliHg0HAL8CABsACQliHg0HAL8CAB8AAwl2CsRlAHYAAAAA.',
Va='Vahe:BAAALgAECgEJAQAAAA==.Vale:BAAALgAECgUJBgAAAA==.Valeshot:BAACLgAFFH8FAAILAAMJwAEybwCgAAALAAMJwAEybwCgAAAuAAQKfyYAAgsACQn9CW4/ALEBAAsACQn9CW4/ALEBAAAA.Valkillrie:BAAALgADCgcJBwAAAA==.Vall:BAAALgAECggJDAAAAA==.Valssra:BAABLgAECn8XAAIIAAcJmAr9pgArAQAIAAcJmAr9pgArAQAAAA==.Vampiricvrus:BAAALgAECgQJBgAAAA==.',
Ve='Vedbow:BAACLgAFFH8UAAQnAAQJmiMPCwBfAQAnAAQJ0iEPCwBfAQALAAMJMBWSWADgAAAiAAEJgA+6JwBNAAAuAAQKfxwABAsACQnIIh4UAJUCAAsACAm5IR4UAJUCACIABAnyHyc8AG4BACcAAwldIAI0AAsBAAAA.Vedronas:BAABLgAECn8XAAIRAAcJaiOcHgC0AgARAAcJaiOcHgC0AgAAAA==.Velillys:BAAALgAECgEJAQAAAA==.Venlii:BAAALgADCgEJAQAAAA==.Veos:BAAALgAECgEJAQAAAA==.Verdict:BAABLgAECn8VAAIYAAgJYxGwOQC6AQAYAAgJYxGwOQC6AQAAAA==.Veritae:BAAALgAECgMJAwAAAA==.Vern:BAABLgAECn8YAAMDAAgJ+Bd4IgCrAQADAAgJ+Bd4IgCrAQACAAIJgwYoWQBWAAAAAA==.Vernaar:BAAALgAECgEJAQABLgAECggJGAADAPgXAA==.Vernah:BAABLgAECn8VAAIQAAgJ1Rm+FgBJAgAQAAgJ1Rm+FgBJAgABLgAECggJGAADAPgXAA==.Verybad:BAABLgAECn9EAAIIAAYJpRwgewDbAQAIAAYJpRwgewDbAQAAAA==.',
Vo='Voidify:BAAALgADCgEJAgAAAA==.Voodoodrood:BAAALgADCgIJAgAAAA==.',
['Vè']='Vèronique:BAAALgAECgYJBgAAAA==.',
Wa='Waambler:BAAALgAECgIJAgAAAA==.Waamchifu:BAABLgAECn83AAIbAAkJhyM2AgA5AwAbAAkJhyM2AgA5AwAAAA==.Wack:BAAALgADCgUJBgAAAA==.Waka:BAAALgADCgcJCwAAAA==.Waltersight:BAABLgAECn8XAAILAAkJbxcfJQBCAgALAAkJbxcfJQBCAgAAAA==.Warsheep:BAAALgADCgQJAQAAAA==.',
We='Wesker:BAAALgADCgYJBgAAAA==.Westavia:BAAALgAECgEJAQABLgAFFAMJBgARAFUaAA==.Wewabear:BAAALgADCgQJBAAAAA==.',
Wh='Whateley:BAAALgAECgcJCgAAAA==.Whosthetänk:BAAALgAECgEJAQAAAA==.',
Wi='Wisebrownguy:BAABLgAECn8rAAIRAAkJ/R7WEwDDAgARAAkJ/R7WEwDDAgABLgAECgkJGQAVAIkbAA==.',
Wo='Worgana:BAAALgAECgMJAwAAAA==.Wormchild:BAAALgADCgQJBAAAAA==.',
Wu='Wukòng:BAAALgADCgEJAQAAAA==.',
Xe='Xercuul:BAAALgAECgUJCgAAAA==.',
Xi='Xikar:BAAALgAECgQJCAAAAA==.',
Xp='Xplosiv:BAAALgAECgUJBQABLgAFFAYJHgAYAKEdAA==.',
Ye='Yeddy:BAAALgADCgcJBwAAAA==.Yel:BAAALgADCgYJCAAAAA==.',
Yo='Yoel:BAAALgADCgEJAQAAAA==.Yourdad:BAAALgAECgYJEAABLgAFFAEJAQAJAAAAAA==.',
Yu='Yudah:BAACLgAFFH8JAAQnAAMJuRQ1HwDKAAAnAAMJDQ41HwDKAAALAAIJzxyMcACdAAAiAAEJ3ADiNgAqAAAuAAQKfy0ABCcACAmgHa0WAOoBACcACAkZGa0WAOoBACIABglUFoASACgBAAsABwlgD2WNABcBAAAA.Yuta:BAAALgADCgcJBgAAAA==.',
Za='Zalrei:BAAALgAECgEJAQAAAA==.Zalupa:BAAALgAECgIJAgAAAA==.Zanghonghua:BAABLgAECn9FAAMfAAkJjiKOAwAfAwAfAAkJjiKOAwAfAwAEAAEJSRXWZAA+AAAAAA==.Zarinaria:BAABLgAECn8cAAINAAYJ2Q7qfQAvAQANAAYJ2Q7qfQAvAQAAAA==.',
Ze='Zetsumei:BAAALgADCgMJAwAAAA==.',
Zh='Zhael:BAABLgAECn8hAAINAAkJCRoWJQAuAgANAAkJCRoWJQAuAgAAAA==.',
Zi='Zitizen:BAAALgADCgYJBwAAAA==.',
Zo='Zodstrike:BAABLgAECn8rAAMNAAkJNgWzhQAHAQANAAkJNgWzhQAHAQAMAAQJnwIXWACGAAAAAA==.Zomara:BAAALgAECgMJCgAAAA==.Zooboo:BAABLgAECn8XAAIVAAkJURdYIwDSAQAVAAkJURdYIwDSAQAAAA==.Zophie:BAAALgADCgEJAQAAAA==.',
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
