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

local lookup = {'Priest-Holy','Priest-Shadow','Priest-Discipline','Monk-Mistweaver','Druid-Restoration','Rogue-Assassination','Warlock-Destruction','Mage-Frost','Unknown-Unknown','DeathKnight-Unholy','Hunter-BeastMastery','DemonHunter-Havoc','DemonHunter-Devourer','Evoker-Augmentation','DeathKnight-Blood','Paladin-Holy','Paladin-Retribution','Paladin-Protection','Evoker-Preservation','Evoker-Devastation','Druid-Guardian','Warrior-Fury','Druid-Feral','Shaman-Restoration','Druid-Balance','Shaman-Elemental','Monk-Brewmaster','Shaman-Enhancement','Rogue-Subtlety','Mage-Arcane','DeathKnight-Frost','Warlock-Demonology','Hunter-Marksmanship','Monk-Windwalker','Warrior-Arms','Warrior-Protection','Mage-Fire','Warlock-Affliction','Hunter-Survival','Rogue-Outlaw',}
local provider = {region='US',realm='LaughingSkull',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Ablucia:BAAALgADCgUJCQAAAA==.Abomb:BAAALgAECgEJAQAAAA==.',
Ac='Acanaline:BAAALgAECgEJAQAAAA==.Achannara:BAAALgADCgcJBwAAAA==.',
Ae='Aennisong:BAAALgAECgUJCAAAAA==.Aeoliana:BAAALgAECggJEgAAAA==.',
Aj='Ajier:BAACLgAFFH8FAAIBAAQJiRGLFAD7AAABAAQJiRGLFAD7AAAuAAQKfy0AAgEACQkpFqMWACcCAAEACQkpFqMWACcCAAAA.',
Al='Aleraz:BAACLgAFFH8QAAMBAAQJkBnpDwAuAQABAAQJkBnpDwAuAQACAAQJDhORFAArAQAuAAQKfz4ABAIACQn5HmgGANICAAIACQn5HmgGANICAAEABwnbIOEVAC0CAAMAAwkmB3xVAHMAAAAA.Allcapwne:BAAALgAECgcJCwAAAA==.Allenduin:BAAALgAECgYJBwAAAA==.Alshau:BAABLgAECn8aAAIEAAcJ0BdfIwCYAQAEAAcJ0BdfIwCYAQAAAA==.Alucart:BAAALgADCgcJCgAAAA==.',
Am='Ambrosia:BAAALgAECgYJDwAAAA==.Amity:BAAALgADCgkJEAABLgAECgkJIAAFAPMdAA==.',
An='Anewrbyss:BAAALgAECgUJDwAAAA==.Angela:BAABLgAECn83AAIDAAkJwx28CQC6AgADAAkJwx28CQC6AgAAAA==.Anna:BAAALgAECgQJBQAAAA==.Annalunà:BAAALgADCgIJAgAAAA==.Annälise:BAAALgADCgEJAQAAAA==.',
Ap='Apeople:BAACLgAFFH8FAAIGAAMJExkWBgD3AAAGAAMJExkWBgD3AAAuAAQKfy8AAgYACQlJIloBACEDAAYACQlJIloBACEDAAAA.Apocalýpsè:BAAALgAECgIJAgAAAA==.Applebottum:BAAALgAECgcJDQAAAA==.Appärition:BAABLgAECn8vAAIHAAgJNSBNAgCEAgAHAAgJNSBNAgCEAgAAAA==.',
Ar='Arleance:BAAALgAECgUJCAAAAA==.Arondael:BAABLgAECn8hAAIGAAgJeRfsBgDeAQAGAAgJeRfsBgDeAQAAAA==.Arsène:BAAALgADCgcJCwAAAA==.',
As='Astroglyde:BAAALgAECgcJCAAAAA==.Aszun:BAAALgADCgUJBQAAAA==.',
Au='Aurialis:BAAALgAECgcJDQAAAA==.',
Av='Avanti:BAABLgAECn80AAIIAAkJMxoeLgBKAgAIAAkJMxoeLgBKAgAAAA==.Avendeloria:BAAALgAECgYJDgAAAA==.',
Az='Azrahn:BAAALgADCgQJBQAAAA==.',
['Aü']='Aüra:BAAALgAECgEJAQABLgAECggJCQAJAAAAAA==.',
Ba='Backmoist:BAAALgAECgMJBAAAAA==.Bagmaster:BAACLgAFFH8QAAIBAAQJ6yGdCgB3AQABAAQJ6yGdCgB3AQAuAAQKfzgAAgEACQkAJpkCAD4DAAEACQkAJpkCAD4DAAAA.Bahm:BAAALgADCgQJBAAAAA==.Baktolife:BAAALgAECgkJBAAAAA==.Bam:BAAALgAECgQJBQABLgAFFAIJBgAKAJshAA==.Bartholomoo:BAABLgAECn9BAAIKAAkJvyLADAD1AgAKAAkJvyLADAD1AgAAAA==.Bayonetta:BAAALgAECgcJDAAAAA==.',
Be='Beeftornado:BAAALgAECgYJBwAAAA==.Belakor:BAAALgADCgIJAgAAAA==.Ber:BAAALgAECgEJAwAAAA==.',
Bi='Bigbusta:BAAALgADCgMJAwAAAA==.Bildros:BAAALgAECgEJAQAAAA==.Birgite:BAAALgAECgYJEAAAAA==.Bizniz:BAAALgAECgYJDAAAAA==.',
Bl='Blastin:BAAALgADCgcJBwAAAA==.Blazefury:BAABLgAECn8YAAILAAYJcwwFlAD8AAALAAYJcwwFlAD8AAAAAA==.Blazeknight:BAABLgAECn8sAAIMAAkJBBoVEwDeAQAMAAkJBBoVEwDeAQAAAA==.Blazemaker:BAABLgAECn8aAAIIAAYJPBDNrgAIAQAIAAYJPBDNrgAIAQAAAA==.Blazemaster:BAAALgAECgQJCQAAAA==.Blinduru:BAACLgAFFH8RAAINAAQJJSJ/HQCQAQANAAQJJSJ/HQCQAQAuAAQKfzYAAg0ACQltJTACAFwDAA0ACQltJTACAFwDAAAA.Blitz:BAAALgAECgIJAgAAAA==.Blocktor:BAAALgAECgMJAwABLgAECgYJHAANANkOAA==.Bluberriez:BAAALgAECgYJBgAAAA==.',
Bo='Bobbiepines:BAAALgAECgMJAgAAAA==.Bonez:BAAALgAECgMJAwAAAA==.Book:BAAALgAECggJEQAAAA==.Bookie:BAAALgAECgEJAQAAAA==.Booza:BAAALgAECgIJAgAAAA==.Borkenshwang:BAAALgADCgYJCwAAAA==.Boydik:BAAALgAECgQJBgAAAA==.',
Bp='Bpaìn:BAABLgAECn8eAAIOAAgJMhfyGwDeAQAOAAgJMhfyGwDeAQAAAA==.',
Br='Brewlïth:BAAALgAECgIJAgABLgAFFAUJDgAPAPAfAA==.Brewmaester:BAAALgAECgEJAgAAAA==.Brink:BAABLgAECn8UAAIIAAgJNg2rfgBgAQAIAAgJNg2rfgBgAQAAAA==.Brojac:BAAALgAECgcJDgAAAA==.Brokil:BAAALgADCggJDAAAAA==.Brolic:BAAALgAECgQJBAAAAA==.Bromaster:BAAALgAECgQJBQAAAA==.Brones:BAAALgAECgkJAgAAAA==.Brossiere:BAABLgAECn8hAAQQAAgJERsQMQB+AQAQAAUJZRoQMQB+AQARAAYJoxcJewBdAQASAAUJVRf4HwD6AAAAAA==.Brotemic:BAAALgAECgYJDQAAAA==.Bru:BAACLgAFFH8JAAIBAAQJghj1DwAtAQABAAQJghj1DwAtAQAuAAQKfygAAgEACQl1HOwMAIYCAAEACQl1HOwMAIYCAAAA.Brutalizèr:BAAALgADCgYJBgABLgAECgEJAQAJAAAAAA==.',
Bu='Bubblegal:BAAALgAECgQJCAAAAA==.Bullsmcgee:BAABLgAECn80AAMKAAgJRiUxDQDyAgAKAAgJRiUxDQDyAgAPAAEJAAAXQwA9AAAAAA==.Burninghunt:BAAALgAECgEJAQAAAA==.Burningtree:BAABLgAECn8UAAIIAAcJIAlKsAAFAQAIAAcJIAlKsAAFAQAAAA==.Burny:BAAALgADCgEJAQAAAA==.Burrder:BAAALgADCggJCAAAAA==.Bustdown:BAAALgADCggJDwAAAA==.Buttslapper:BAAALgADCggJCAAAAA==.',
['Bö']='Börck:BAAALgADCgUJBQAAAA==.',
['Bø']='Bøb:BAAALgAECggJCwAAAA==.',
Ca='Camamoonmana:BAABLgAECn8aAAIFAAkJ3BPqNAC0AQAFAAkJ3BPqNAC0AQAAAA==.Captcorndog:BAACLgAFFH8FAAIOAAMJ2wpmPAC0AAAOAAMJ2wpmPAC0AAAuAAQKfygABA4ACAlAFQEgAL4BAA4ACAlAFQEgAL4BABMABQnzA3k4AKcAABQAAQkAALRAAC8AAAAA.Caskket:BAAALgAECgIJAgAAAA==.Catdog:BAABLgAECn8hAAIVAAYJ6RfJHgAxAQAVAAYJ6RfJHgAxAQAAAA==.Catechism:BAABLgAECn8dAAIQAAgJhyDzDQCfAgAQAAgJhyDzDQCfAgAAAA==.',
Ce='Cemeo:BAAALgAECgcJEwAAAA==.Cerberusalfa:BAACLgAFFH8OAAIMAAQJriMyBACeAQAMAAQJriMyBACeAQAuAAQKfzEAAgwACQnTJfsBADkDAAwACQnTJfsBADkDAAAA.',
Ch='Chaintazer:BAAALgADCgYJBgABLgAECgkJGQAWAIkbAA==.Chewbaca:BAAALgAECgEJAwAAAA==.Chickennuggi:BAACLgAFFH8IAAIIAAMJuRHQbwDiAAAIAAMJuRHQbwDiAAAuAAQKfygAAggABwmlHf0+AAkCAAgABwmlHf0+AAkCAAAA.Chinchilla:BAAALgADCgYJBgAAAA==.Chiphoof:BAABLgAECn8YAAIXAAcJuxJTEwBkAQAXAAcJuxJTEwBkAQAAAA==.Chocofox:BAABLgAECn8XAAIYAAgJUCL7DADZAgAYAAgJUCL7DADZAgAAAA==.Chokemagic:BAAALgAECgUJBwAAAA==.Chopndot:BAAALgAECgEJBAAAAA==.Chozen:BAAALgADCgcJBwAAAA==.Chrill:BAABLgAECn8cAAINAAYJchdxYwBHAQANAAYJchdxYwBHAQAAAA==.',
Cl='Claraabun:BAAALgAECgUJBQABLgAFFAYJFQAQAH8SAA==.Clarabuns:BAACLgAFFH8VAAIQAAYJfxLpDgCqAQAQAAYJfxLpDgCqAQAuAAQKfx8AAxAACQnGF2YlAPsBABAACQnGF2YlAPsBABEABQl1F+1vAHQBAAAA.Clarasbuns:BAAALgAECgMJAwABLgAFFAYJFQAQAH8SAA==.Clawdragoon:BAACLgAFFH8RAAQZAAQJgQqIJADeAAAZAAQJgQqIJADeAAAFAAQJhAE7PgCpAAAVAAEJpwL3MwAkAAAuAAQKfzAAAxkACAnVGW0UAG8CABkACAnVGW0UAG8CAAUABQlACN+bAJQAAAAA.',
Co='Coati:BAAALgADCgYJBgAAAA==.Colosie:BAAALgAECgYJEwAAAA==.Comegetpsalm:BAABLgAECn89AAIQAAkJJRqPDwCKAgAQAAkJJRqPDwCKAgAAAA==.Cornbreadmat:BAAALgADCgcJCgAAAA==.',
Cr='Creamsock:BAAALgAECgQJCQAAAA==.Creatlach:BAACLgAFFH8cAAIYAAUJixzHFACPAQAYAAUJixzHFACPAQAuAAQKfzgAAxgACAlPHYcfADkCABgACAlPHYcfADkCABoAAwlXE3BjALUAAAEuAAUUBgkQAAQAQRYA.Creatlachlol:BAAALgAECgkJCQABLgAFFAYJEAAEAEEWAA==.Creech:BAAALgADCgIJAgAAAA==.Creeptoken:BAAALgAECgEJAQAAAA==.Crucifilth:BAAALgADCgYJDAAAAA==.Cryopathy:BAAALgAECgYJDgAAAA==.Crypty:BAABLgAECn8dAAMaAAkJggxzLQB0AQAaAAkJggxzLQB0AQAYAAUJrREiXQAWAQAAAA==.',
Cy='Cyaniidee:BAAALgADCgcJBwAAAA==.Cytherea:BAABLgAECn8lAAIRAAcJDBAGlAAwAQARAAcJDBAGlAAwAQAAAA==.',
Da='Daddybod:BAABLgAECn8gAAIbAAkJjRL4GwC0AQAbAAkJjRL4GwC0AQAAAA==.Dainnan:BAAALgADCgEJAQAAAA==.Dalinek:BAAALgAECgUJBQAAAA==.Danicarkel:BAAALgAECggJCwAAAA==.Darkcallum:BAAALgADCgEJAQAAAA==.Darktaynt:BAAALgAECgMJBQAAAA==.Darthfox:BAAALgAECgMJBQAAAA==.',
De='Deadsean:BAAALgAECgUJDAAAAA==.Deathsyn:BAABLgAFFH8JAAIKAAQJzRm8PABYAQAKAAQJzRm8PABYAQAAAA==.Deathtracker:BAABLgAECn8aAAILAAgJXw4HVgCJAQALAAgJXw4HVgCJAQAAAA==.Deathwarden:BAAALgAECggJEwAAAA==.Deathñdk:BAAALgADCgEJAQAAAA==.Debuffed:BAAALgAECgEJAQAAAA==.Delathor:BAAALgAECgcJDgAAAA==.Delimeatear:BAAALgADCgEJAQAAAA==.Demiloss:BAAALgAFFAEJAQAAAA==.Demise:BAABLgAECn8lAAIIAAgJ5x06MQCtAgAIAAgJ5x06MQCtAgABLgAFFAMJCQAOAEoUAA==.Demonclem:BAAALgAFFAIJAgAAAA==.Demonskinner:BAAALgADCgUJBQAAAA==.Denzo:BAAALgAECgMJAwAAAA==.Deoxyrybo:BAACLgAFFH8FAAIMAAMJPQr4FQDAAAAMAAMJPQr4FQDAAAAuAAQKfzsAAwwACQnkGVcLAFQCAAwACQnkGVcLAFQCAA0ABgmnC5WIABQBAAAA.Destructin:BAAALgAECgEJAQAAAA==.Destructor:BAAALgAECgcJEwAAAA==.Devourera:BAAALgAFFAMJAwAAAA==.',
Di='Died:BAAALgADCgMJAwAAAA==.Dilldobaggin:BAAALgADCgQJBAAAAA==.Dinopriest:BAABLgAECn8XAAICAAcJLRfsIQCYAQACAAcJLRfsIQCYAQAAAA==.Distia:BAAALgAECgcJCgAAAA==.Divinedragon:BAABLgAECn8sAAMCAAkJGhgMEABAAgACAAkJGhgMEABAAgADAAcJ5grnLgAoAQAAAA==.Dixoncider:BAAALgAECgQJBgAAAA==.',
Do='Doboy:BAAALgADCgIJAgAAAA==.Donmanuel:BAAALgADCgEJAQAAAA==.',
Dr='Drackaris:BAAALgADCgYJBgAAAA==.Drainbamage:BAAALgAECgMJAwAAAA==.Drakin:BAABLgAECn83AAIRAAkJZR6sFQCrAgARAAkJZR6sFQCrAgAAAA==.Dreya:BAABLgAECn8aAAIcAAkJDR1MCAAnAgAcAAkJDR1MCAAnAgAAAA==.Dreyas:BAAALgADCgYJBgAAAA==.Drinkcoolaid:BAABLgAECn8cAAIYAAgJAxSMLwDcAQAYAAgJAxSMLwDcAQAAAA==.Dritzle:BAABLgAECn8aAAMdAAgJBhXKIQDrAQAdAAgJBhXKIQDrAQAGAAQJHgi5EwDEAAAAAA==.Droopapi:BAAALgAECgYJEQAAAA==.',
Du='Durrt:BAAALgADCgcJCAABLgAECgcJKgAFAIYhAA==.Dutchman:BAACLgAFFH8UAAILAAYJ3CO/CgDEAQALAAYJ3CO/CgDEAQAuAAQKfxwAAgsACAkNIWYIAAsDAAsACAkNIWYIAAsDAAAA.',
Eh='Ehhmuh:BAAALgAECgYJCgAAAA==.Ehlumii:BAABLgAECn8UAAIEAAYJRSRvDgBvAgAEAAYJRSRvDgBvAgAAAA==.',
Ei='Eiffel:BAAALgADCgUJBQAAAA==.',
El='Eldrene:BAABLgAECn8uAAMIAAgJUR3TMwAxAgAIAAgJUR3TMwAxAgAeAAEJ7hOWHAA6AAAAAA==.Elethil:BAAALgADCgEJAgAAAA==.Elfstomper:BAAALgADCggJCwAAAA==.Elitepaladin:BAABLgAECn8nAAIQAAkJGBbfIQAPAgAQAAkJGBbfIQAPAgAAAA==.Ellexi:BAAALgAECgYJDAAAAA==.Elyseia:BAABLgAECn8eAAILAAkJgwY3egAxAQALAAkJgwY3egAxAQAAAA==.',
Em='Empkin:BAAALgAECgcJEwAAAA==.',
En='Enof:BAAALgADCgIJAgAAAA==.Enpower:BAAALgADCgYJBgABLgAECgcJBwAJAAAAAA==.',
Ep='Epicsause:BAAALgAECgkJCgAAAA==.',
Er='Erelor:BAAALgADCgMJAwAAAA==.',
Es='España:BAECLgAFFH8HAAIPAAQJbxEyFwADAQAPAAQJbxEyFwADAQAuAAQKfy0ABA8ACQlOGj0KAHYCAA8ACQlOGj0KAHYCAB8ABQlGEaEYANwAAAoAAQkAALd+AQAAAAAA.Españaluna:BAEALgAECgcJBgABLgAFFAQJBwAPAG8RAA==.Españamor:BAEALgAECgkJCAABLgAFFAQJBwAPAG8RAA==.Essdeath:BAAALgAECgEJAQAAAA==.',
Fa='Farael:BAAALgAECgcJBAAAAA==.Farmerbrown:BAAALgAECgIJAwABLgAECgkJNwARAPEkAA==.Fatalmann:BAACLgAFFH8FAAMUAAMJdAWFCQBsAAAUAAIJsgKFCQBsAAATAAIJsQFWIwBmAAAuAAQKfxYAAxQACQnMD5kVAJUBABQABwmoD5kVAJUBABMABgk2D20aAB4BAAAA.Fatalminn:BAAALgAECgUJCQAAAA==.Fathergob:BAAALgADCgEJAQAAAA==.Fatty:BAAALgADCgYJBgAAAA==.',
Fe='Fenty:BAAALgADCgEJAQAAAA==.Feralhorn:BAAALgAECgEJAQAAAA==.',
Fi='Fingerz:BAAALgADCgIJAgAAAA==.Fintan:BAAALgAECgYJBgAAAA==.',
Fl='Flarestrasz:BAAALgADCgUJCQAAAA==.Flexxar:BAAALgAECgEJAgAAAA==.Flutterby:BAAALgADCgcJDAABLgAECgkJMQACAMgHAA==.Flèxion:BAACLgAFFH8OAAIKAAUJ2R+fMQBzAQAKAAUJ2R+fMQBzAQAuAAQKfygAAgoACAkBJekbAIwCAAoACAkBJekbAIwCAAAA.',
Fo='Foskin:BAAALgAECgMJBAABLgAECgkJGQAWAIkbAA==.',
Fr='Frassk:BAABLgAECn9AAAMHAAkJVRjICQCMAQAHAAcJ4hfICQCMAQAgAAQJ0hL6wgC5AAAAAA==.Freja:BAAALgADCgMJBgAAAA==.Froggystyle:BAAALgAECgUJDQABLgAECggJCQAJAAAAAA==.Frostydru:BAABLgAECn8wAAIXAAgJfiGWBgBaAgAXAAgJfiGWBgBaAgAAAA==.Frozat:BAACLgAFFH8WAAITAAgJCxSXBQCdAQATAAgJCxSXBQCdAQAuAAQKfygAAxMACAkRI+kDAOkCABMACAkRI+kDAOkCAA4AAQmAEZ5eAEAAAAAA.Frösting:BAAALgADCgcJDgABLgAECggJNAANAEQbAA==.',
Fu='Fundeedo:BAAALgAFFAIJAwAAAA==.Furballieo:BAAALgADCgIJAgAAAA==.',
Ga='Galadriels:BAAALgAECgQJBAAAAA==.Galianem:BAAALgADCgMJAwAAAA==.Gamora:BAAALgAECgYJCQAAAA==.Gandon:BAAALgAECgQJCAAAAA==.Garbarn:BAABLgAECn8WAAIRAAkJ0w8FcwBuAQARAAkJ0w8FcwBuAQAAAA==.Garonno:BAAALgADCgIJAgAAAA==.',
Ge='Gelystine:BAAALgADCgUJCgAAAA==.Geminirunes:BAAALgADCgYJBgABLgAECgcJBwAJAAAAAA==.Germaine:BAAALgAECgQJBQAAAA==.',
Gh='Ghabi:BAAALgAECgYJBgAAAA==.Ghauri:BAAALgAECgMJBAAAAA==.',
Gi='Gia:BAABLgAECn8vAAIEAAgJ+xquEwBeAgAEAAgJ+xquEwBeAgAAAA==.',
Go='Gobx:BAAALgAECgUJBgAAAA==.Golgroth:BAABLgAECn8dAAIWAAkJPwRhRgAUAQAWAAkJPwRhRgAUAQAAAA==.Goodlocktime:BAAALgADCgIJAgAAAA==.Goodtimesm:BAAALgAECgYJBwAAAA==.Goodtymes:BAAALgAECgEJAQAAAA==.Gorearrow:BAACLgAFFH8IAAILAAQJMRLULQA6AQALAAQJMRLULQA6AQAuAAQKfzAAAwsACQlXItgLAOMCAAsACQlXItgLAOMCACEAAglWB2N6AFkAAAAA.Goretaint:BAAALgAECgYJDwAAAA==.Gorgesh:BAAALgADCgQJBAAAAA==.Gothladriel:BAAALgAECgYJDAAAAA==.Gottamoo:BAABLgAECn8ZAAMVAAkJJwwwIwARAQAVAAkJJwwwIwARAQAZAAEJPQFWkAAaAAAAAA==.',
Gr='Greenstank:BAAALgAECggJCQAAAA==.Grimmtotem:BAAALgADCgQJBAAAAA==.Grrumpybear:BAABLgAECn9BAAIVAAkJvRs3BgCAAgAVAAkJvRs3BgCAAgAAAA==.Grundal:BAAALgADCggJCAAAAA==.',
Gu='Gunafistya:BAAALgAFFAIJBAAAAA==.Gunnaroptiks:BAAALgAECgUJBQABLgAFFAQJEQAbAIcUAA==.Guzzler:BAAALgAECggJCwAAAA==.',
['Gú']='Gúildarts:BAAALgADCgEJAQAAAA==.',
Ha='Haannarr:BAAALgAECgIJAgAAAA==.Hairymoodini:BAAALgAECgEJAgAAAA==.Hajin:BAAALgAECgYJDwAAAA==.Hankjr:BAAALgAECgEJAQAAAA==.Hanky:BAAALgAECgQJBAAAAA==.Havòk:BAAALgAECggJBwAAAA==.Hawthorn:BAAALgAECgMJCAAAAA==.Hazyblades:BAAALgAECgMJAwAAAA==.',
He='Helacookie:BAABLgAECn8ZAAIRAAkJMBMzSQDTAQARAAkJMBMzSQDTAQAAAA==.Henso:BAAALgAECgcJBwAAAA==.Heomors:BAAALgAECgEJAQAAAA==.Hexxan:BAAALgAECgUJEAAAAA==.',
Hi='Hifumi:BAAALgADCgQJBwAAAA==.Hisagu:BAAALgAECgEJAQABLgAECgYJDwAJAAAAAA==.Hiver:BAAALgAECgQJBgAAAA==.',
Ho='Hoagar:BAAALgAECgcJCwAAAA==.Holes:BAAALgAECgEJAQAAAA==.Holier:BAABLgAECn84AAIRAAkJ/hUmPQD4AQARAAkJ/hUmPQD4AQAAAA==.Hollows:BAAALgAECgQJBgAAAA==.Holyatrops:BAAALgAECgkJEQABLgAFFAcJHgAgAD4YAA==.Hoppers:BAAALgAECgIJAgABLgAECgcJDwAJAAAAAA==.Hopperstotem:BAAALgAECgcJDwAAAA==.Horuu:BAAALgAECgQJBgAAAA==.Hoyboii:BAAALgADCgYJBgAAAA==.',
Hu='Hulo:BAAALgAECgIJAgAAAA==.Humbled:BAAALgAECgQJBQAAAA==.Hunteress:BAAALgADCgYJBwAAAA==.Huntkoalas:BAAALgAECgMJAwABLgAFFAcJHAAZAMsWAA==.Hurrdurr:BAAALgAECgEJAQAAAA==.',
['Hî']='Hîflax:BAAALgAECgEJAgAAAA==.',
['Hö']='Hölyców:BAAALgADCgQJBAAAAA==.',
Ic='Ichbinstark:BAAALgAECgEJBAAAAA==.',
Id='Idonttcare:BAAALgAECgMJAwAAAA==.',
Ig='Iggnignokt:BAAALgADCgYJBwAAAA==.',
Ih='Ihealnewbs:BAAALgADCgYJDwAAAA==.',
In='Infamus:BAAALgAECgQJCQAAAA==.Invisabull:BAAALgAECgIJAgAAAA==.Invysion:BAACLgAFFH8HAAIDAAQJAwcTJAD5AAADAAQJAwcTJAD5AAAuAAQKfy4AAgMACQkXEeEYAOkBAAMACQkXEeEYAOkBAAAA.',
Ir='Irri:BAAALgADCgUJBQAAAA==.',
Is='Ishara:BAAALgAECggJCAABLgAECggJLgAIAFEdAA==.',
Ja='Jacuzzi:BAAALgADCgYJBgAAAA==.Jaidess:BAAALgADCgcJFAAAAA==.',
Je='Jeanjean:BAAALgAECgcJCAAAAA==.Jeannjeann:BAAALgAECggJEgAAAA==.Jediknîght:BAAALgAECgYJBgAAAA==.Jeep:BAACLgAFFH8NAAILAAQJnhvhLwA2AQALAAQJnhvhLwA2AQAuAAQKfycAAgsACAlAJVMEAEoDAAsACAlAJVMEAEoDAAAA.Jellybea:BAACLgAFFH8JAAIBAAQJBxkKEAAsAQABAAQJBxkKEAAsAQAuAAQKfyoAAwEACQltITEEABIDAAEACQltITEEABIDAAIAAgkJDDBiAGMAAAAA.',
Ji='Jibalynne:BAAALgAECgQJBAAAAA==.Jida:BAAALgAECgEJAQAAAA==.Jiffypop:BAAALgAECgcJDQABLgAECgkJLQAWAFsdAA==.Jinwooaura:BAAALgADCgcJBwAAAA==.',
Jo='Johnnycakes:BAAALgADCgMJBQAAAA==.Jonsnowxd:BAAALgADCgYJBgAAAA==.',
Jr='Jrhnbr:BAAALgADCgMJAwAAAA==.',
Ju='Juggnut:BAAALgAECgcJEQAAAA==.Jump:BAAALgAECgUJDgAAAA==.Jurisdiction:BAABLgAECn8jAAIRAAgJbxE6YgCSAQARAAgJbxE6YgCSAQAAAA==.',
Jz='Jz:BAAALgAECgMJAwAAAA==.',
['Jì']='Jìnn:BAAALgAECgUJDwAAAA==.',
Ka='Kaan:BAABLgAECn8qAAIFAAcJhiFLEwCbAgAFAAcJhiFLEwCbAgAAAA==.Kabea:BAAALgAECgEJAQAAAA==.Kadath:BAAALgADCgIJAwAAAA==.Kaeladín:BAAALgAECgUJCAAAAA==.Kagebouzu:BAAALgAECgYJDwAAAA==.Kahlan:BAAALgADCgcJCAABLgAECgYJDwAJAAAAAA==.Kalycia:BAAALgAECgEJAQAAAA==.Kamela:BAAALgAECgYJCAAAAA==.Karael:BAAALgAECgUJEQABLgAECggJCgAJAAAAAA==.Karma:BAAALgAECgYJEgAAAA==.Kayliaa:BAAALgAECgkJAQAAAA==.Kazarke:BAAALgADCgcJGAAAAA==.',
Ke='Keeia:BAAALgADCgQJBQAAAA==.Keho:BAABLgAECn8jAAMbAAgJIQrkLgA3AQAbAAgJswnkLgA3AQAiAAIJkg6maABqAAAAAA==.Kenalia:BAABLgAECn8oAAIEAAgJZRbJHwD0AQAEAAgJZRbJHwD0AQAAAA==.Kengo:BAAALgAECgEJAQAAAA==.Keptalive:BAAALgADCgcJCgAAAA==.Kerzermern:BAAALgAFFAMJAwAAAA==.Kevic:BAAALgAFFAIJAwABLgAFFAQJCgACADsNAA==.',
Kh='Khamaelion:BAAALgADCgcJDgAAAA==.',
Ki='Kiara:BAABLgAECn8eAAIRAAgJNiBdIgCgAgARAAgJNiBdIgCgAgAAAA==.Kiju:BAAALgADCgYJBgAAAA==.Killaban:BAACLgAFFH8KAAIWAAQJ9BeSFwA+AQAWAAQJ9BeSFwA+AQAuAAQKfzIAAxYACQklIG0UADoCABYACQngH20UADoCACMAAwkZGVMrAJoAAAAA.Killbydeath:BAAALgAECgEJAQAAAA==.Kimberlyhárt:BAABLgAECn83AAMRAAkJ8SRBAwBZAwARAAkJ8SRBAwBZAwAQAAQJ9ApJXACpAAAAAA==.Kissmydots:BAABLgAECn9DAAIgAAkJKR4xFACgAgAgAAkJKR4xFACgAgAAAA==.Kitja:BAABLgAECn84AAMDAAkJgBwUCQDHAgADAAkJghkUCQDHAgABAAgJaByaDgBlAgAAAA==.Kitla:BAAALgADCgUJBQABLgAECgkJOAADAIAcAA==.',
Kl='Klukai:BAAALgADCgcJCwABLgAECgkJIAAFAPMdAA==.',
Kn='Kneed:BAAALgADCgYJBgAAAA==.',
Ko='Koala:BAAALgAECgQJBQABLgAFFAcJHAAZAMsWAA==.Kohman:BAABLgAECn8bAAIgAAYJ3RXOfABiAQAgAAYJ3RXOfABiAQAAAA==.Konyani:BAAALgADCgUJAQAAAA==.',
Kp='Kpop:BAAALgAECgEJAQABLgAECgcJBwAJAAAAAA==.',
Kr='Kraeven:BAAALgADCgEJAQAAAA==.Kregerath:BAAALgADCgIJAgAAAA==.Krftpnk:BAACLgAFFH8WAAIMAAQJPCbTAgDDAQAMAAQJPCbTAgDDAQAuAAQKfyYAAwwACQm1JDcEADcDAAwACQm1JDcEADcDAA0AAQkAAKAoAQAAAAAA.Krom:BAABLgAECn8tAAMWAAkJWx36DgBxAgAWAAkJWx36DgBxAgAjAAEJPQllcAAqAAAAAA==.Kronas:BAABLgAECn8VAAILAAgJ3RWpVACNAQALAAgJ3RWpVACNAQAAAA==.Kronophyne:BAABLgAECn83AAIIAAkJ+R1ZLgBJAgAIAAkJ+R1ZLgBJAgAAAA==.Kronotality:BAABLgAECn9HAAIPAAkJ0iQCAgArAwAPAAkJ0iQCAgArAwAAAA==.Kronotek:BAAALgAECgcJDQAAAA==.Kronotekken:BAAALgADCgYJBgAAAA==.Kronotide:BAAALgAECgYJBgAAAA==.',
Ku='Kurohitsugî:BAAALgAECgIJBAAAAA==.',
Ky='Kylorai:BAAALgAECgYJDwAAAA==.Kynbrochel:BAAALgAECgYJCAAAAA==.',
La='Laars:BAAALgAECgQJBwABLgAECggJHwAgAB4JAA==.Laimaster:BAAALgAECgEJAQAAAA==.Lakiri:BAABLgAECn81AAIcAAkJihlfBwA+AgAcAAkJihlfBwA+AgAAAA==.Landaeda:BAAALgAECgcJDgAAAA==.Lapsu:BAABLgAECn8fAAIiAAkJjRQlGQDRAQAiAAkJjRQlGQDRAQAAAA==.Lascivia:BAACLgAFFH8JAAMWAAQJ5B1VEQBdAQAWAAQJ5B1VEQBdAQAkAAIJMgyvHwBzAAAuAAQKfyQAAxYACQkAH1AmACcCABYACQmIHFAmACcCACQABwn4D0MrAMQAAAAA.Lawhanx:BAAALgADCgEJAQABLgAFFAEJAQAJAAAAAA==.Laylahh:BAAALgADCgMJBAAAAA==.Lazy:BAABLgAECn8WAAMgAAYJyRcpiQBHAQAgAAUJyRcpiQBHAQAHAAIJxQGEYQBLAAAAAA==.',
Le='Leademon:BAABLgAECn89AAMNAAkJiR8IEwCXAgANAAkJiR8IEwCXAgAMAAIJTRrWWgB2AAAAAA==.Leadmin:BAAALgADCgMJBQABLgAECgkJPQANAIkfAA==.Leadmln:BAAALgADCgcJBwABLgAECgkJPQANAIkfAA==.Leftlane:BAABLgAECn8uAAMYAAkJsiHcBABSAwAYAAkJsiHcBABSAwAaAAEJgA2VkwAxAAAAAA==.Legato:BAAALgAECgcJCAABLgAFFAcJHwAYAPYgAA==.Lekiri:BAAALgAECgMJBAAAAA==.Lep:BAAALgAFFAQJBAABLgAFFAgJFgATAAsUAA==.Lethalkrits:BAAALgAECgcJAgAAAA==.Leva:BAABLgAECn8gAAIFAAkJ8x1BFgCDAgAFAAkJ8x1BFgCDAgAAAA==.',
Li='Liberté:BAAALgAECgIJAgAAAA==.Liciano:BAAALgAECggJCgAAAA==.Lie:BAACLgAFFH8FAAIdAAIJTgtRLACTAAAdAAIJTgtRLACTAAAuAAQKfzsAAh0ACQkNGQsLAFwCAB0ACQkNGQsLAFwCAAAA.Lightsdown:BAAALgAECgYJBgAAAA==.Lilbeebs:BAAALgAECgkJEQAAAA==.Lileth:BAAALgAECgkJAgAAAA==.Lilflea:BAAALgAECggJEQAAAA==.Lilzuki:BAAALgAECgkJEwAAAA==.Lilïth:BAACLgAFFH8OAAIPAAUJ8B98FAAbAQAPAAUJ8B98FAAbAQAuAAQKfyAAAg8ABwmDJPIGAMICAA8ABwmDJPIGAMICAAAA.Linguine:BAAALgAECgEJAwABLgAFFAQJEAABAJAZAA==.Lisalisa:BAABLgAECn81AAIYAAgJ6RjNJQASAgAYAAgJ6RjNJQASAgAAAA==.Livan:BAAALgAECgMJAwAAAA==.Livia:BAAALgAECgEJAQAAAA==.',
Lo='Lohzak:BAAALgAECgEJAQAAAA==.Lousier:BAAALgAECgEJAQAAAA==.',
Lu='Lularia:BAAALgADCgIJAgAAAA==.Lumii:BAAALgAECgYJBgABLgAECgYJFAAEAEUkAA==.Luminari:BAAALgADCgEJAQABLgAECggJLgAIAFEdAA==.Lunaa:BAAALgAECggJCwAAAA==.Lurassa:BAAALgAECgYJDAAAAA==.',
Ly='Lyacon:BAAALgADCgQJBAABLgAECgkJFQAIAEEcAA==.',
['Lä']='Lä:BAEALgAECgcJBwABLgAFFAIJAgAJAAAAAA==.',
Ma='Madrie:BAAALgAECgQJBAAAAA==.Maekar:BAABLgAECn8aAAIUAAYJOg6tDgAQAQAUAAYJOg6tDgAQAQAAAA==.Maellus:BAAALgAECgEJAQAAAA==.Maelstorm:BAAALgADCgIJAgAAAA==.Mageman:BAAALgADCgYJAgAAAA==.Magickdragon:BAAALgAECgUJBQABLgAECgkJLAACABoYAA==.Magicmoo:BAAALgAECgEJAQABLgAECgkJNwARAPEkAA==.Maltis:BAAALgADCgcJCwAAAA==.Mananstuff:BAACLgAFFH8FAAIZAAMJqQSgMACPAAAZAAMJqQSgMACPAAAuAAQKf0MAAhkACQluEd4bANEBABkACQluEd4bANEBAAAA.Manaproblems:BAAALgADCgMJBAAAAA==.Marguerek:BAAALgADCgEJAQAAAA==.Marinara:BAAALgAECgYJCwABLgAECgYJDAAJAAAAAA==.Markamanimal:BAACLgAFFH8PAAIXAAQJjBpTBABUAQAXAAQJjBpTBABUAQAuAAQKfyUAAhcACAnfIYYDAPwCABcACAnfIYYDAPwCAAAA.Marnix:BAABLgAECn8bAAIaAAgJmRIDKgCHAQAaAAgJmRIDKgCHAQAAAA==.Marshail:BAAALgAECgEJAQAAAA==.',
Md='Mdbeef:BAAALgAECgUJBQAAAA==.',
Me='Medikus:BAABLgAECn8iAAMYAAgJbxwTHABRAgAYAAgJbxwTHABRAgAaAAMJ2gwQbQCBAAAAAA==.Meesoomagi:BAAALgAECgYJBwAAAA==.Megajoo:BAAALgAFFAEJAQAAAA==.Menil:BAABLgAECn8XAAMEAAgJwBtXFgAQAgAEAAcJJhpXFgAQAgAiAAQJchazSADHAAAAAA==.Merryl:BAAALgAECggJDgAAAA==.Meyounow:BAAALgAECgEJAwAAAA==.',
Mi='Midnye:BAAALgADCgYJBgAAAA==.Mike:BAECLgAFFH8GAAMlAAQJqhHEAgClAAAlAAIJzBnEAgClAAAIAAIJiAlhlACMAAAuAAQKfzoAAyUACQmDJHMAABYDACUACQlAInMAABYDAAgACAlkIOhNANoBAAAA.Mips:BAAALgAFFAIJAgABLgAFFAMJCQAOAEoUAA==.',
Mo='Mob:BAAALgADCgcJBwAAAA==.Mockra:BAABLgAECn8+AAMIAAkJViK/EADjAgAIAAkJViK/EADjAgAeAAIJuBiqGgBCAAAAAA==.Monafae:BAAALgADCgUJBQAAAA==.Moohammered:BAAALgAECgMJBAAAAA==.Moolou:BAACLgAFFH8JAAISAAQJSRZ5BQAZAQASAAQJSRZ5BQAZAQAuAAQKfyEAAhIACQm1HzYFAIkCABIACQm1HzYFAIkCAAAA.Moonraka:BAAALgADCgUJBQAAAA==.Moosé:BAAALgAECgEJAQABLgAFFAgJJQARAO8UAA==.Mootilater:BAAALgADCgQJAQAAAA==.Mootilator:BAAALgADCgYJBgAAAA==.Moraei:BAAALgADCgEJAQAAAA==.Mordew:BAAALgADCgUJBQABLgAECggJNAAKAEYlAA==.Morechie:BAABLgAECn8fAAImAAgJgxIWDAB3AQAmAAgJgxIWDAB3AQAAAA==.Morecowbell:BAAALgAECgEJAQAAAA==.Morgatho:BAAALgADCgEJAwAAAA==.Mortiferon:BAABLgAECn8zAAIKAAkJcR1ZFwCnAgAKAAkJcR1ZFwCnAgAAAA==.',
Mu='Muhgunguh:BAAALgAECgEJAQAAAA==.Munnky:BAABLgAECn8nAAIEAAYJlyFzGQAmAgAEAAYJlyFzGQAmAgAAAA==.Murmaider:BAAALgADCgIJAgAAAA==.',
My='Mythrandere:BAAALgADCgcJCwAAAA==.Mytu:BAAALgADCgUJBgAAAA==.',
['Má']='Mánflu:BAACLgAFFH8LAAIWAAQJRxm8FABKAQAWAAQJRxm8FABKAQAuAAQKfysAAyMACQniHhIDAOICACMACQniHhIDAOICABYABwlJGlI0ANkBAAAA.',
['Mô']='Môrrigãn:BAAALgADCgMJAwAAAA==.',
['Mö']='Mörgänä:BAAALgADCgMJAwAAAA==.',
Na='Naissa:BAAALgAECgQJCwAAAA==.Nakanir:BAAALgAECgYJBgAAAA==.Nalfeign:BAAALgAECgQJBQAAAA==.Napa:BAAALgAECgQJBAABLgAFFAYJEwAYAKMXAA==.Narn:BAABLgAECn9DAAQOAAkJOBw9EgA2AgAUAAcJrRjRCQBCAgAOAAkJ5Rg9EgA2AgATAAIJLQiEQQBgAAAAAA==.',
Ne='Nealite:BAAALgAECgkJBgAAAA==.Necrotion:BAAALgAECgYJEgAAAA==.Nei:BAAALgAECgEJAQAAAA==.Nerrisa:BAABLgAECn8iAAICAAkJERSEHgCyAQACAAkJERSEHgCyAQAAAA==.Nertt:BAAALgADCgYJBgABLgAECgkJQwATADEZAA==.Neublood:BAAALgAECgQJCAAAAA==.',
Ni='Nicodemus:BAAALgAECgcJDAAAAA==.',
No='Noblewarrior:BAACLgAFFH8gAAIWAAcJBx/hAgAbAgAWAAcJBx/hAgAbAgAuAAQKfysAAhYACAmuJB4LAKACABYACAmuJB4LAKACAAAA.Noctilus:BAAALgAECgcJCQAAAA==.Nohkari:BAAALgADCgkJFAABLgAECgkJHwAgANAUAA==.Nooj:BAACLgAFFH8qAAMGAAgJkSInAAC+AgAGAAgJkSInAAC+AgAdAAYJiRRcDgB1AQAuAAQKfx4AAwYACQl7ITsAAMMDAAYACQl7ITsAAMMDAB0ABgmFEpA6AEQBAAAA.Notakoala:BAACLgAFFH8cAAIZAAcJyxYJCADWAQAZAAcJyxYJCADWAQAuAAQKfycAAxkACAlHJFQNAMUCABkACAlHJFQNAMUCABUAAQk3EoNfADMAAAAA.Nothnx:BAAALgAFFAEJAwAAAA==.Notoriouspat:BAABLgAECn8dAAILAAgJ7w1uWQB/AQALAAgJ7w1uWQB/AQAAAA==.Notsamadeath:BAABLgAFFH8HAAMfAAQJPBBsCgAmAQAfAAQJPBBsCgAmAQAKAAIJ3wgeygCBAAAAAA==.Novia:BAAALgAECgYJBgAAAA==.Noyber:BAAALgAECgcJCgAAAA==.Noydin:BAAALgAFFAIJAwAAAA==.',
['Ní']='Nínebreaker:BAAALgADCggJBwAAAA==.',
['Nü']='Nüll:BAAALgAECggJEgAAAA==.',
Ob='Obern:BAABLgAECn8WAAInAAkJZhuBEwD+AQAnAAkJZhuBEwD+AQAAAA==.Oblïna:BAABLgAECn8eAAIEAAgJWAhXTwD6AAAEAAgJWAhXTwD6AAAAAA==.',
Od='Odiumaeterna:BAAALgADCgcJBwAAAA==.',
Of='Offensivé:BAAALgAECgMJBwAAAA==.',
On='Onetozerosix:BAABLgAECn8hAAIKAAkJ/xt+NwAOAgAKAAkJ/xt+NwAOAgAAAA==.Onos:BAAALgAECgEJAQAAAA==.Onsen:BAAALgAECgQJBgAAAA==.',
Oo='Oogak:BAAALgAECgUJBgAAAA==.Oomigig:BAAALgADCgUJBQAAAA==.',
Op='Opalily:BAAALgADCgYJCAAAAA==.Operation:BAAALgAECgQJCAAAAA==.',
Or='Oresties:BAAALgAECgYJBgAAAA==.Orghrax:BAAALgADCgEJAQAAAA==.Orisys:BAAALgAECgIJAgAAAA==.',
Os='Osteer:BAAALgAECgYJBgAAAA==.',
Ot='Otterjim:BAAALgADCgQJBAAAAA==.',
Pa='Pahaa:BAAALgAECgUJBQAAAA==.Pairadeez:BAAALgAECgYJCwAAAA==.Pajamabanana:BAAALgADCgIJAgAAAA==.Pandablaze:BAAALgAECgYJDQAAAA==.Panterarey:BAAALgADCgYJEAAAAA==.Papalego:BAABLgAECn8vAAILAAgJZA52UwCQAQALAAgJZA52UwCQAQAAAA==.Parakka:BAABLgAECn82AAIYAAkJGhYvHQBJAgAYAAkJGhYvHQBJAgAAAA==.Patak:BAAALgADCgkJCgAAAA==.Pavle:BAAALgAECgMJAwAAAA==.Pawp:BAAALgAECgYJCQABLgAECggJHwABAMUSAA==.',
Pe='Pearagon:BAAALgAECggJEgABLgAFFAYJEwAYAKMXAA==.Pepsidew:BAAALgADCgcJDAAAAA==.Pepsisprite:BAABLgAECn8yAAIBAAgJSxtEDgBqAgABAAgJSxtEDgBqAgAAAA==.Pesky:BAABLgAECn8eAAIZAAYJShUpMwAyAQAZAAYJShUpMwAyAQABLgAFFAMJCAAIALkRAA==.',
Pf='Pfchanguz:BAAALgADCgcJDAAAAA==.',
Ph='Phdbeef:BAABLgAFFH8HAAIVAAIJ+xvZFgCpAAAVAAIJ+xvZFgCpAAABLgAFFAUJDgAPAPAfAA==.Phlemm:BAAALgAECgEJAQAAAA==.Phoivos:BAABLgAECn8VAAIIAAkJQRwKIQDvAgAIAAkJQRwKIQDvAgAAAA==.',
Pi='Picklez:BAABLgAECn8rAAIKAAgJkiFUFgCuAgAKAAgJkiFUFgCuAgAAAA==.Pissflizzle:BAABLgAECn8dAAIgAAgJ9w2UXwB2AQAgAAgJ9w2UXwB2AQAAAA==.',
Pl='Plaquenil:BAAALgADCgEJAQAAAA==.',
Po='Poison:BAAALgADCgEJAQAAAA==.Porkroaster:BAABLgAECn8fAAIIAAcJlgn/pgAVAQAIAAcJlgn/pgAVAQAAAA==.',
Pr='Praye:BAAALgAFFAMJAwAAAA==.Priestop:BAAALgAECgEJAQAAAA==.',
Ps='Psyfarian:BAAALgADCgcJDQAAAA==.Psyop:BAAALgAECgYJBwABLgAECggJFwABAAUcAA==.',
Qu='Quillswitch:BAAALgAECgEJAQAAAA==.',
Ra='Radduc:BAABLgAECn8ZAAMQAAYJKxgdMgB3AQAQAAYJKxgdMgB3AQARAAEJlQY9iwEpAAAAAA==.Ragerade:BAAALgAECgQJBQAAAA==.Raidu:BAAALgAECgMJAwAAAA==.Ralpherion:BAAALgADCgIJAgAAAA==.Ranoa:BAAALgAECgQJCgAAAA==.Raphåel:BAAALgAFFAEJAQAAAA==.Ravioli:BAAALgAECgQJBgAAAA==.Razialum:BAAALgADCgYJBgAAAA==.Razorsteps:BAAALgAFFAcJBAAAAA==.Razzberry:BAAALgADCgYJDAAAAA==.',
Re='Rebrowth:BAAALgAECgcJEgAAAA==.Redren:BAAALgADCgIJAgAAAA==.Reegrets:BAAALgAECggJDQAAAA==.Reena:BAAALgADCgIJAwAAAA==.Regiplague:BAAALgAECgYJCwAAAA==.Regretty:BAAALgAECggJDQABLgAECggJDQAJAAAAAA==.Renthar:BAAALgADCgUJBQAAAA==.Renzdingo:BAAALgAECgkJDwAAAA==.Repete:BAAALgAECgUJDgAAAA==.Resyek:BAABLgAECn85AAIIAAgJOyTlFwC0AgAIAAgJOyTlFwC0AgAAAA==.Reverendgank:BAAALgAECgEJAQAAAA==.',
Rh='Rhaxanna:BAAALgADCgYJBgAAAA==.',
Ri='Rick:BAAALgAFFAMJAwAAAA==.Rickheaddk:BAAALgADCgEJAgAAAA==.Riivan:BAABLgAECn8bAAIgAAgJhA1UXQB8AQAgAAgJhA1UXQB8AQAAAA==.Rini:BAAALgAECgkJEQABLgABCgYJCwAJAAAAAA==.Rishi:BAABLgAECn83AAIRAAgJBBXYagB/AQARAAgJBBXYagB/AQAAAA==.Rivian:BAAALgADCgIJAgAAAA==.',
Ro='Robot:BAABLgAECn8eAAIEAAcJtQ8sLwBAAQAEAAcJtQ8sLwBAAQAAAA==.Rokmog:BAAALgAECgUJBwAAAA==.Rollinburn:BAAALgADCgYJCQAAAA==.Roxanol:BAAALgADCgEJAQABLgAECgkJPQAQACUaAA==.',
Ru='Rumbrave:BAAALgAECgYJCwAAAA==.Rumtumtugger:BAAALgADCgkJCQAAAA==.',
['Rá']='Ráyune:BAAALgADCgcJBwAAAA==.',
Sa='Sackos:BAAALgAECgEJAgAAAA==.Sadpanda:BAAALgADCgUJCAAAAA==.Saffronspark:BAAALgADCgkJHwABLgAECgkJQQAiAHohAA==.Sainsei:BAABLgAECn8YAAMiAAYJGAY0WQCUAAAbAAYJvwIHVgCeAAAiAAUJBAc0WQCUAAAAAA==.Saith:BAAALgAECgEJBgAAAA==.Samasear:BAABLgAECn8UAAIWAAgJ0w8wMgDjAQAWAAgJ0w8wMgDjAQABLgAFFAYJGgAKAN0gAA==.Sandwitch:BAABLgAECn9DAAMgAAkJLRgAKwAgAgAgAAkJLRgAKwAgAgAHAAIJmxB0UwB0AAAAAA==.Sanoa:BAAALgAECgQJBwAAAA==.Sargatana:BAABLgAECn8vAAIbAAkJrx6/BQDTAgAbAAkJrx6/BQDTAgAAAA==.Sars:BAABLgAECn8kAAMEAAcJ7yWiCADyAgAEAAcJ7yWiCADyAgAiAAMJGhMOVgCdAAAAAA==.Sauronxd:BAAALgAECgUJCAAAAA==.',
Sc='Scalion:BAABLgAECn8nAAMNAAgJOR43IQA6AgANAAgJOR43IQA6AgAMAAQJ+BG9SwDAAAABLgAFFAEJAQAJAAAAAA==.Scarne:BAAALgAECgIJAgAAAA==.Schrodinger:BAABLgAECn8dAAISAAgJuAosHQASAQASAAgJuAosHQASAQAAAA==.Scravenhoof:BAAALgAECgYJBgAAAA==.',
Se='Selunee:BAAALgADCgEJAQAAAA==.Sepharad:BAAALgADCggJEgAAAA==.Septicflësh:BAAALgADCgEJAQAAAA==.Severum:BAABLgAECn82AAIkAAgJkB0WCQBQAgAkAAgJkB0WCQBQAgAAAA==.',
Sh='Shadowtiger:BAABLgAECn8uAAILAAkJUQz7QgDBAQALAAkJUQz7QgDBAQAAAA==.Shadrad:BAACLgAFFH8HAAIRAAQJdx2yHABvAQARAAQJdx2yHABvAQAuAAQKfxoAAhEACQmyJUUHACADABEACQmyJUUHACADAAAA.Shamanor:BAAALgAECgcJCAAAAA==.Shammoo:BAAALgAECgIJBAABLgAFFAgJJQARAO8UAA==.Shantz:BAABLgAECn8oAAIPAAgJcRODGQB4AQAPAAgJcRODGQB4AQAAAA==.Shiban:BAAALgAECggJEAAAAA==.Shirtless:BAAALgAECggJEQAAAA==.Shockra:BAABLgAECn8dAAIaAAkJ4xcWHwDQAQAaAAkJ4xcWHwDQAQAAAA==.Shokalypse:BAAALgADCgEJAQAAAA==.Shortbuss:BAAALgADCgYJEgAAAA==.',
Si='Sige:BAAALgADCgYJBgAAAA==.Sillygoose:BAAALgADCgkJDwAAAA==.Silverfox:BAAALgADCgMJAQABLgAECgkJPgAIAFYiAA==.Silx:BAABLgAECn8VAAMDAAcJMBE8IQCJAQADAAcJMBE8IQCJAQACAAEJoBZEXQA/AAAAAA==.Simvastatin:BAAALgADCgQJBAAAAA==.Sinterdeath:BAAALgAECgIJAgAAAA==.Sithiry:BAAALgAECgEJAQAAAA==.',
Sk='Skik:BAAALgAECgUJBQAAAA==.Skulltide:BAAALgADCgcJCQAAAA==.',
Sl='Slaggz:BAAALgADCgQJBAAAAA==.Slamvoke:BAAALgAECgYJBgABLgAFFAUJDwAWAKwVAA==.Slaté:BAAALgAECgEJAgAAAA==.Slowrot:BAAALgAECgQJBAABLgAECgkJNwARAPEkAA==.Slâte:BAAALgAFFAEJAgAAAA==.',
Sm='Smiteasaurus:BAAALgAECgEJAQAAAA==.Smorthian:BAAALgAECgcJDQAAAA==.',
Sn='Snarll:BAAALgADCgEJAQAAAA==.Sniffinsteak:BAABLgAECn8bAAMiAAkJGiFoBQDoAgAiAAkJGiFoBQDoAgAEAAEJtwttpQAkAAAAAA==.',
So='Somaliabiggs:BAAALgAECgYJCgAAAA==.Sonar:BAAALgADCgYJBgABLgAECggJNAAKAEYlAA==.Sorraba:BAABLgAFFH8HAAIIAAQJhQEffwC9AAAIAAQJhQEffwC9AAAAAA==.Sorrabo:BAACLgAFFH8MAAIDAAQJ7gcqJQDvAAADAAQJ7gcqJQDvAAAuAAQKfx0ABAMACQmbE00SADMCAAMACQmbE00SADMCAAEAAwm7A9dbAFEAAAIAAQkpA12FACIAAAAA.Soryan:BAABLgAECn8aAAIRAAgJOAfTlQBRAQARAAgJOAfTlQBRAQAAAA==.Sosalkin:BAAALgAECgcJEQAAAA==.Souls:BAACLgAFFH8QAAIgAAMJeiNPGQAnAQAgAAMJeiNPGQAnAQAuAAQKfx4ABCAABwnhIyYXAMkCACAABwnhIyYXAMkCACYAAQkAAPIfAHIAAAcAAQm1GkhiAEoAAAAA.',
Sp='Spankenstine:BAABLgAECn8kAAMRAAkJHRdgPAD6AQARAAkJHRdgPAD6AQAQAAUJowh+YwDuAAABLgABCgYJCwAJAAAAAA==.Spannky:BAAALgAECgYJCwABLgAECgYJJwAEAJchAA==.',
Sq='Squishÿ:BAAALgAECgYJDwAAAA==.',
St='Starshriek:BAAALgADCgcJBwAAAA==.Stinkyfree:BAABLgAECn8cAAIbAAYJzBjSLgCcAQAbAAYJzBjSLgCcAQAAAA==.Stinkynatto:BAAALgADCgYJBgABLgAECgYJHAAbAMwYAA==.Stormcharred:BAABLgAECn8eAAIIAAgJ6SCgKADQAgAIAAgJ6SCgKADQAgAAAA==.Stormknight:BAAALgAECgUJEAAAAA==.Straka:BAABLgAECn8fAAIFAAkJERIZPgCrAQAFAAkJERIZPgCrAQAAAA==.',
Su='Suffers:BAAALgAECgEJAQAAAA==.Suneater:BAAALgAECgEJAgAAAA==.Sunmane:BAAALgADCgcJCAABLgAECgcJGAAXALsSAA==.Supaheals:BAAALgAECgEJAQAAAA==.Superdk:BAAALgAFFAQJBAABLgAFFAgJFQARAOIaAA==.Superdruid:BAAALgADCgUJBQABLgAFFAgJFQARAOIaAA==.Supermonks:BAAALgAECggJDAABLgAFFAgJFQARAOIaAA==.Superpi:BAABLgAECn8aAAIDAAcJFx72EABEAgADAAcJFx72EABEAgABLgAFFAgJFQARAOIaAA==.Superret:BAACLgAFFH8VAAIRAAgJ4hpXCAACAgARAAgJ4hpXCAACAgAuAAQKfycAAxEACQkGI/gOABYDABEACQkGI/gOABYDABAAAQn7FAl+ADsAAAAA.Superskeet:BAACLgAFFH8HAAIQAAMJtAueLQCsAAAQAAMJtAueLQCsAAAuAAQKfyUAAhAACAl3FzwfAPMBABAACAl3FzwfAPMBAAAA.',
Sw='Swaggbag:BAAALgADCgEJAQAAAA==.Swiftia:BAABLgAECn8VAAMhAAYJlBZYOwBzAQAhAAYJjhRYOwBzAQALAAUJAg2lrgDFAAAAAA==.Swiftybutt:BAAALgAECggJCgAAAA==.',
Sy='Sylphièl:BAACLgAFFH8MAAMGAAQJagIMBgD4AAAGAAQJagIMBgD4AAAoAAEJqQJiAgBEAAAuAAQKfygAAwYACAkwDkcKAIABACgACAmbCq8EALkBAAYACAlDDUcKAIABAAAA.Syncere:BAAALgAFFAIJAgAAAA==.Synhunt:BAAALgAFFAEJAgAAAA==.Syrene:BAAALgAECgMJBgAAAA==.',
Ta='Tandarì:BAACLgAFFH8UAAIRAAUJWB9sIABhAQARAAUJWB9sIABhAQAuAAQKfyIAAhEACQmjHqoPABEDABEACQmjHqoPABEDAAAA.Tano:BAAALgAECgUJCQABLgAECgkJPgAIAFYiAA==.Tanparo:BAAALgAECgMJAwAAAA==.Tarick:BAAALgAECgYJCAAAAA==.Tasty:BAAALgAECgQJCwAAAA==.Tawnii:BAAALgADCgcJEgAAAA==.Tazath:BAAALgAECgEJAwAAAA==.Taírn:BAAALgAECgYJEQAAAA==.',
Te='Tehpredator:BAAALgAFFAMJAwAAAA==.Teilin:BAACLgAFFH8fAAIYAAcJ9iDhAgB0AgAYAAcJ9iDhAgB0AgAuAAQKfyIAAhgACQmQI7MEACcDABgACQmQI7MEACcDAAAA.Teralynn:BAAALgAECgEJAQAAAA==.',
Th='Thalendor:BAAALgAECgIJAgAAAA==.Theaterthug:BAAALgAECgIJAgAAAA==.Thehulkster:BAAALgAECgMJAwAAAA==.Thetinman:BAAALgAECgEJAQAAAA==.Thevelo:BAAALgAECgIJAgABLgAECgcJEwAJAAAAAA==.Thewhole:BAAALgAFFAIJAQAAAA==.Theßigshot:BAABLgAECn8VAAIFAAYJICPAIgAyAgAFAAYJICPAIgAyAgAAAA==.Thoseheals:BAAALgADCgQJBAAAAA==.Thunderskeet:BAACLgAFFH8KAAINAAMJARmdSwDpAAANAAMJARmdSwDpAAAuAAQKfzwAAw0ACQkFJQQDAEoDAA0ACQkFJQQDAEoDAAwABwlYHRAUADICAAAA.Thundurus:BAACLgAFFH8PAAIaAAUJihM1HgAMAQAaAAUJihM1HgAMAQAuAAQKfyUAAhoACAm9Fo8wAGMBABoACAm9Fo8wAGMBAAAA.',
Ti='Timmayy:BAABLgAECn8kAAIgAAgJCBZ5OQAmAgAgAAgJCBZ5OQAmAgAAAA==.Tindrill:BAABLgAECn8lAAIjAAkJJyRCAQBKAwAjAAkJJyRCAQBKAwAAAA==.Tireiron:BAAALgADCgYJBgAAAA==.',
To='Tomraedisk:BAABLgAECn8ZAAIWAAkJiRsQEwBHAgAWAAkJiRsQEwBHAgAAAA==.Totemagoat:BAACLgAFFH8bAAMYAAYJUhn4HABZAQAYAAUJmBb4HABZAQAaAAUJ+hAhHwAIAQAuAAQKfzIAAxoACQkJHYcVACICABoACAnQG4cVACICABgACAlIFdgsANcBAAAA.Totemlyfine:BAABLgAECn8wAAMYAAgJlSJCDQDWAgAYAAgJlSJCDQDWAgAaAAQJMBVCVwDDAAAAAA==.Totesmugoats:BAAALgAECggJEgAAAA==.Toxicshock:BAAALgADCgEJAQAAAA==.',
Tr='Traprkeepr:BAAALgADCgcJDQAAAA==.Treechains:BAABLgAECn8WAAMYAAYJ8hd0RwB0AQAYAAYJ8hd0RwB0AQAaAAEJZQPtkQAlAAAAAA==.Treefist:BAAALgAECgUJAgAAAA==.Treeshield:BAAALgADCgYJBgAAAA==.Trickster:BAAALgAECgEJAQAAAA==.Truth:BAAALgADCgcJDQAAAA==.',
Ts='Tsumuji:BAAALgAECgEJAQAAAA==.',
Tu='Turbobis:BAAALgAECgIJAgAAAA==.',
Tw='Twentyfour:BAACLgAFFH8IAAIFAAMJJgUEQgCbAAAFAAMJJgUEQgCbAAAuAAQKfxUAAgUABwmGEOVdADgBAAUABwmGEOVdADgBAAAA.Twigberry:BAAALgAECgUJCAAAAA==.',
Ty='Tygra:BAAALgAECgcJCAAAAA==.Typeshxxt:BAAALgADCgEJAQAAAA==.Tytanea:BAAALgAECgMJBAAAAA==.',
['Tø']='Tøqa:BAAALgAFFAEJAQAAAA==.',
Uh='Uhnderstood:BAABLgAECn8mAAIEAAkJjh1qEABUAgAEAAkJjh1qEABUAgAAAA==.',
Un='Undeadmonks:BAACLgAFFH8IAAIbAAMJYhX6LQDbAAAbAAMJYhX6LQDbAAAuAAQKf0gAAxsACQliHn4GAMICABsACQliHn4GAMICACIAAwl2CsRlAHYAAAAA.',
Va='Vahe:BAAALgAECgEJAQAAAA==.Vale:BAAALgAECgUJBQAAAA==.Valeshot:BAACLgAFFH8FAAILAAMJwAE/YwCjAAALAAMJwAE/YwCjAAAuAAQKfyQAAgsACQn9CW4/ALEBAAsACQn9CW4/ALEBAAAA.Valkillrie:BAAALgADCgcJBwAAAA==.Vall:BAAALgAECgYJCgAAAA==.Valssra:BAABLgAECn8XAAIIAAcJmArHpAAYAQAIAAcJmArHpAAYAQAAAA==.Vampiricvrus:BAAALgAECgQJBgAAAA==.',
Ve='Vedbow:BAACLgAFFH8UAAQnAAQJmiNVCAB3AQAnAAQJ0iFVCAB3AQALAAMJMBXdTADoAAAhAAEJgA+6JwBNAAAuAAQKfxwABAsACQnIIh4UAJUCAAsACAm5IR4UAJUCACEABAnyHyc8AG4BACcAAwldILkxAA0BAAAA.Vedronas:BAABLgAECn8VAAIRAAcJOSOcHgC0AgARAAcJOSOcHgC0AgAAAA==.Venlii:BAAALgADCgEJAQAAAA==.Verdict:BAABLgAECn8UAAIYAAcJSRHEQgCGAQAYAAcJSRHEQgCGAQAAAA==.Veritae:BAAALgAECgMJAwAAAA==.Vern:BAABLgAECn8YAAMDAAgJ+BdrIQCeAQADAAgJ+BdrIQCeAQACAAIJgwYoWQBWAAAAAA==.Vernaar:BAAALgAECgEJAQABLgAECggJGAADAPgXAA==.Vernah:BAABLgAECn8VAAIQAAgJ1RlOFQBMAgAQAAgJ1RlOFQBMAgABLgAECggJGAADAPgXAA==.Verybad:BAABLgAECn9EAAIIAAYJpRwgewDbAQAIAAYJpRwgewDbAQAAAA==.',
Vo='Voidify:BAAALgADCgEJAgAAAA==.Voodoodrood:BAAALgADCgIJAgAAAA==.',
['Vè']='Vèronique:BAAALgAECgUJBQAAAA==.',
Wa='Waambler:BAAALgADCgEJAQAAAA==.Waamchifu:BAABLgAECn8zAAIbAAgJeSPlBQDPAgAbAAgJeSPlBQDPAgAAAA==.Wack:BAAALgADCgUJBgAAAA==.Waka:BAAALgADCgcJCwAAAA==.Waltersight:BAABLgAECn8UAAILAAgJHRhsMQD/AQALAAgJHRhsMQD/AQAAAA==.Warsheep:BAAALgADCgQJAQAAAA==.',
We='Wesker:BAAALgADCgYJBgAAAA==.Westavia:BAAALgAECgEJAQABLgAECgkJNwARAPEkAA==.Wewabear:BAAALgADCgQJBAAAAA==.',
Wh='Whateley:BAAALgAECgcJCgAAAA==.Whosthetänk:BAAALgAECgEJAQAAAA==.',
Wi='Wisebrownguy:BAABLgAECn8oAAIRAAkJjBwdGgCPAgARAAkJjBwdGgCPAgABLgAECgkJGQAWAIkbAA==.',
Wo='Worgana:BAAALgAECgMJAwAAAA==.Wormchild:BAAALgADCgQJBAAAAA==.',
Wu='Wukòng:BAAALgADCgEJAQAAAA==.',
Xe='Xercuul:BAAALgAECgQJBwAAAA==.',
Xi='Xikar:BAAALgAECgQJCAAAAA==.',
Xp='Xplosiv:BAAALgAECgUJBQABLgAFFAYJEAAEAEEWAA==.',
Ye='Yeddy:BAAALgADCgcJBwAAAA==.Yel:BAAALgADCgYJCAAAAA==.',
Yo='Yoel:BAAALgADCgEJAQAAAA==.Yourdad:BAAALgAECgYJCwAAAA==.',
Yu='Yudah:BAACLgAFFH8JAAQnAAMJuRRPHADcAAAnAAMJDQ5PHADcAAALAAIJzxwCZACiAAAhAAEJ3ACuMQArAAAuAAQKfy0ABCcACAmgHVQVAO0BACcACAkZGVQVAO0BACEABglUFpURACsBAAsABwlgD5yGABgBAAAA.Yuta:BAAALgADCgcJBgAAAA==.',
Za='Zalrei:BAAALgADCgYJBwAAAA==.Zalupa:BAAALgAECgIJAgAAAA==.Zanghonghua:BAABLgAECn9BAAMiAAkJeiEVBAAKAwAiAAkJeiEVBAAKAwAEAAEJSRXWZAA+AAAAAA==.Zarinaria:BAABLgAECn8cAAINAAYJ2Q7qfQAvAQANAAYJ2Q7qfQAvAQAAAA==.',
Ze='Zetsumei:BAAALgADCgMJAwAAAA==.',
Zh='Zhael:BAABLgAECn8bAAINAAgJFhzoNwDQAQANAAgJFhzoNwDQAQAAAA==.',
Zi='Zitizen:BAAALgADCgYJBwAAAA==.',
Zo='Zodstrike:BAABLgAECn8rAAMNAAkJNgUGgAAEAQANAAkJNgUGgAAEAQAMAAQJnwIXWACGAAAAAA==.Zomara:BAAALgAECgMJCgAAAA==.Zooboo:BAABLgAECn8XAAIWAAkJURdQIQDTAQAWAAkJURdQIQDTAQAAAA==.Zophie:BAAALgADCgEJAQAAAA==.',
['Är']='Ärcane:BAAALgAECgkJCwAAAA==.',
['Ät']='Ätticus:BAAALgAECgMJAgAAAA==.',
['Äú']='Äúra:BAAALgAECggJCQAAAA==.',
['Åi']='Åir:BAAALgADCgIJAgAAAA==.',
['Ðô']='Ðôôm:BAAALgAECgEJAQAAAA==.',
['Öv']='Överpöwered:BAAALgADCgIJAgAAAA==.',
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
