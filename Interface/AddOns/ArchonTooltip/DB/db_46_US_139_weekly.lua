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

local lookup = {'Priest-Holy','Priest-Shadow','Priest-Discipline','Monk-Mistweaver','Druid-Restoration','Rogue-Assassination','Warlock-Destruction','Mage-Frost','Unknown-Unknown','DeathKnight-Unholy','Hunter-BeastMastery','DemonHunter-Havoc','DemonHunter-Devourer','Evoker-Augmentation','DeathKnight-Blood','Paladin-Retribution','Paladin-Holy','Paladin-Protection','Evoker-Preservation','Evoker-Devastation','Druid-Guardian','Warrior-Fury','Druid-Feral','Shaman-Restoration','Druid-Balance','Shaman-Elemental','Monk-Brewmaster','Shaman-Enhancement','Rogue-Subtlety','Mage-Arcane','DeathKnight-Frost','Warlock-Demonology','Hunter-Marksmanship','Monk-Windwalker','Warrior-Arms','Warrior-Protection','Mage-Fire','Warlock-Affliction','Hunter-Survival','Rogue-Outlaw',}
local provider = {region='US',realm='LaughingSkull',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Ablucia:BAAALgADCgUJCQAAAA==.Abomb:BAAALgADCgcJBwAAAA==.',
Ac='Achannara:BAAALgADCgcJBwAAAA==.',
Ae='Aennisong:BAAALgAECgUJCAAAAA==.Aeoliana:BAAALgAECggJEgAAAA==.',
Aj='Ajier:BAACLgAFFH8FAAIBAAQJiRF+EQAPAQABAAQJiRF+EQAPAQAuAAQKfy0AAgEACQkpFqMWACcCAAEACQkpFqMWACcCAAAA.',
Al='Aleraz:BAACLgAFFH8NAAMBAAQJkBnDDQA5AQABAAQJkBnDDQA5AQACAAMJvxE9GwDoAAAuAAQKfzkABAIACQkCHqAGAMsCAAIACQkCHqAGAMsCAAEABwnbIOEVAC0CAAMAAwkmB2JPAHkAAAAA.Allcapwne:BAAALgAECgcJCwAAAA==.Allenduin:BAAALgAECgYJBwAAAA==.Alshau:BAABLgAECn8aAAIEAAcJ0BdfIwCYAQAEAAcJ0BdfIwCYAQAAAA==.Alucart:BAAALgADCgcJCgAAAA==.',
Am='Ambrosia:BAAALgAECgYJDwAAAA==.Amity:BAAALgADCgkJEAABLgAECgkJIAAFAPMdAA==.',
An='Anewrbyss:BAAALgAECgUJDwAAAA==.Angela:BAABLgAECn8yAAIDAAkJHxxoCQCzAgADAAkJHxxoCQCzAgAAAA==.Anna:BAAALgAECgQJBQAAAA==.Annalunà:BAAALgADCgIJAgAAAA==.Annälise:BAAALgADCgEJAQAAAA==.',
Ap='Apeople:BAACLgAFFH8FAAIGAAMJExk7BQAKAQAGAAMJExk7BQAKAQAuAAQKfy4AAgYACQlJIloBACEDAAYACQlJIloBACEDAAAA.Apocalýpsè:BAAALgAECgIJAgAAAA==.Applebottum:BAAALgAECgYJDAAAAA==.Appärition:BAABLgAECn8tAAIHAAgJNSD5AQCLAgAHAAgJNSD5AQCLAgAAAA==.',
Ar='Arleance:BAAALgAECgQJBAAAAA==.Arondael:BAABLgAECn8fAAIGAAgJuhX/BgDLAQAGAAgJuhX/BgDLAQAAAA==.Arsène:BAAALgADCgcJCwAAAA==.',
As='Astroglyde:BAAALgAECgYJBgAAAA==.Aszun:BAAALgADCgUJBQAAAA==.',
Au='Aurialis:BAAALgAECgcJDQAAAA==.',
Av='Avanti:BAABLgAECn8xAAIIAAkJHxl1KwBOAgAIAAkJHxl1KwBOAgAAAA==.Avendeloria:BAAALgAECgYJDgAAAA==.',
Az='Azrahn:BAAALgADCgQJBQAAAA==.',
['Aü']='Aüra:BAAALgAECgEJAQABLgAECggJCQAJAAAAAA==.',
Ba='Backmoist:BAAALgAECgMJBAAAAA==.Bagmaster:BAACLgAFFH8MAAIBAAQJ6yHSCACDAQABAAQJ6yHSCACDAQAuAAQKfzUAAgEACQkAJpkCAD4DAAEACQkAJpkCAD4DAAAA.Bahm:BAAALgADCgQJBAAAAA==.Baktolife:BAAALgAECgkJBAAAAA==.Bam:BAAALgAECgQJBQABLgAFFAIJBgAKAJshAA==.Bartholomoo:BAABLgAECn8/AAIKAAgJPCPzFgCbAgAKAAgJPCPzFgCbAgAAAA==.Bayonetta:BAAALgAECgcJDAAAAA==.',
Be='Beeftornado:BAAALgAECgYJBwAAAA==.Belakor:BAAALgADCgIJAgAAAA==.Ber:BAAALgAECgEJAgAAAA==.',
Bi='Bigbusta:BAAALgADCgMJAwAAAA==.Bildros:BAAALgAECgEJAQAAAA==.Birgite:BAAALgAECgYJEAAAAA==.Bizniz:BAAALgAECgYJDAAAAA==.',
Bl='Blastin:BAAALgADCgcJBwAAAA==.Blazefury:BAABLgAECn8YAAILAAYJcwzBiQD6AAALAAYJcwzBiQD6AAAAAA==.Blazeknight:BAABLgAECn8pAAIMAAkJfhmFFgAXAgAMAAkJfhmFFgAXAgAAAA==.Blazemaker:BAABLgAECn8aAAIIAAYJPBAPpQAYAQAIAAYJPBAPpQAYAQAAAA==.Blazemaster:BAAALgAECgQJCQAAAA==.Blinduru:BAACLgAFFH8OAAINAAQJixxDIgBeAQANAAQJixxDIgBeAQAuAAQKfzYAAg0ACQltJdUBAGQDAA0ACQltJdUBAGQDAAAA.Blitz:BAAALgAECgIJAgAAAA==.Blocktor:BAAALgAECgMJAwABLgAECgYJHAANANkOAA==.Bluberriez:BAAALgAECgYJBgAAAA==.',
Bo='Bobbiepines:BAAALgAECgEJAQAAAA==.Bonez:BAAALgAECgIJAgAAAA==.Book:BAAALgAECggJEAAAAA==.Bookie:BAAALgADCgQJBAAAAA==.Booza:BAAALgAECgIJAgAAAA==.Borkenshwang:BAAALgADCgYJCwAAAA==.Boydik:BAAALgAECgQJBgAAAA==.',
Bp='Bpaìn:BAABLgAECn8XAAIOAAYJghXONAA1AQAOAAYJghXONAA1AQAAAA==.',
Br='Brewlïth:BAAALgAECgIJAgABLgAFFAUJDgAPAPAfAA==.Brewmaester:BAAALgAECgEJAQAAAA==.Brink:BAAALgAECgYJDQAAAA==.Brojac:BAAALgAECgcJDgAAAA==.Brokil:BAAALgADCggJDAAAAA==.Brolic:BAAALgAECgEJAQAAAA==.Bromaster:BAAALgAECgQJBQAAAA==.Brones:BAAALgAECggJAgAAAA==.Brossiere:BAABLgAECn8fAAQQAAgJ7hWAcABtAQAQAAYJoxeAcABtAQARAAUJiBn6MQBlAQASAAUJVRdPHQD8AAAAAA==.Brotemic:BAAALgAECgYJCAAAAA==.Bru:BAACLgAFFH8FAAIBAAMJ+hgPFgDiAAABAAMJ+hgPFgDiAAAuAAQKfygAAgEACQl1HOwMAIYCAAEACQl1HOwMAIYCAAAA.Brutalizèr:BAAALgADCgYJBgABLgAECgEJAQAJAAAAAA==.',
Bu='Bubblegal:BAAALgAECgQJBwAAAA==.Bullsmcgee:BAABLgAECn80AAMKAAgJRiU+CwD1AgAKAAgJRiU+CwD1AgAPAAEJAAAXQwA9AAAAAA==.Burninghunt:BAAALgADCgkJEgAAAA==.Burningtree:BAAALgAECgYJEgAAAA==.Burny:BAAALgADCgEJAQAAAA==.Burrder:BAAALgADCggJCAAAAA==.Bustdown:BAAALgADCggJDwAAAA==.Buttslapper:BAAALgADCggJCAAAAA==.',
['Bö']='Börck:BAAALgADCgUJBQAAAA==.',
['Bø']='Bøb:BAAALgAECggJCwAAAA==.',
Ca='Camamoonmana:BAABLgAECn8aAAIFAAkJ3BOwMQC1AQAFAAkJ3BOwMQC1AQAAAA==.Captcorndog:BAACLgAFFH8FAAIOAAMJ2woUNQC/AAAOAAMJ2woUNQC/AAAuAAQKfyQABA4ACAkAErQlAJABAA4ACAkAErQlAJABABMABQnzA3k4AKcAABQAAQkAALRAAC8AAAAA.Caskket:BAAALgADCgkJCQAAAA==.Catdog:BAABLgAECn8bAAIVAAYJ3BfSDwB8AQAVAAYJ3BfSDwB8AQAAAA==.Catechism:BAABLgAECn8WAAIRAAcJjh3KGQAQAgARAAcJjh3KGQAQAgAAAA==.',
Ce='Cemeo:BAAALgAECgcJEwAAAA==.Cerberusalfa:BAACLgAFFH8KAAIMAAQJoCO7AwCWAQAMAAQJoCO7AwCWAQAuAAQKfzEAAgwACQnTJYEBAEIDAAwACQnTJYEBAEIDAAAA.',
Ch='Chaintazer:BAAALgADCgYJBgABLgAECgkJGQAWAIkbAA==.Chewbaca:BAAALgAECgEJAwAAAA==.Chickennuggi:BAACLgAFFH8GAAIIAAMJWxGgZADsAAAIAAMJWxGgZADsAAAuAAQKfygAAggABwmlHdg5ABYCAAgABwmlHdg5ABYCAAAA.Chinchilla:BAAALgADCgYJBgAAAA==.Chiphoof:BAABLgAECn8WAAIXAAYJdBP6FQAvAQAXAAYJdBP6FQAvAQAAAA==.Chocofox:BAABLgAECn8VAAIYAAcJqSRDEACkAgAYAAcJqSRDEACkAgAAAA==.Chokemagic:BAAALgAECgUJBwAAAA==.Chopndot:BAAALgAECgEJBAAAAA==.Chozen:BAAALgADCgcJBwAAAA==.Chrill:BAABLgAECn8ZAAINAAYJFhf4YQA/AQANAAYJFhf4YQA/AQAAAA==.',
Cl='Claraabun:BAAALgAECgUJBQABLgAFFAUJFAARAN8TAA==.Clarabuns:BAACLgAFFH8UAAIRAAUJ3xMKEwBeAQARAAUJ3xMKEwBeAQAuAAQKfxwAAxEACQnGF2YlAPsBABEACQnGF2YlAPsBABAABAnsE12hABQBAAAA.Clarasbuns:BAAALgAECgMJAwABLgAFFAUJFAARAN8TAA==.Clawdragoon:BAECLgAFFH8QAAMZAAQJgQqaHwD7AAAZAAQJgQqaHwD7AAAFAAQJhAFqOACxAAAuAAQKfzAAAxkACAnVGW0UAG8CABkACAnVGW0UAG8CAAUABQlACN+bAJQAAAAA.',
Co='Coati:BAAALgADCgYJBgAAAA==.Colosie:BAAALgAECgYJEwAAAA==.Comegetpsalm:BAABLgAECn87AAIRAAgJ5RzcEQBhAgARAAgJ5RzcEQBhAgAAAA==.',
Cr='Creamsock:BAAALgAECgQJCQAAAA==.Creatlach:BAACLgAFFH8YAAIYAAUJUBycEACXAQAYAAUJUBycEACXAQAuAAQKfzgAAxgACAlPHTYcADwCABgACAlPHTYcADwCABoAAwlXE3BjALUAAAAA.Creatlachlol:BAAALgAECgkJCQABLgAFFAUJGAAYAFAcAA==.Creech:BAAALgADCgIJAgAAAA==.Creeptoken:BAAALgAECgEJAQAAAA==.Crucifilth:BAAALgADCgYJDAAAAA==.Cryopathy:BAAALgAECgYJDgAAAA==.Crypty:BAABLgAECn8dAAMaAAkJggy+KQB2AQAaAAkJggy+KQB2AQAYAAUJrREiXQAWAQAAAA==.',
Cy='Cyaniidee:BAAALgADCgcJBwAAAA==.Cytherea:BAABLgAECn8gAAIQAAcJdQsCrQABAQAQAAcJdQsCrQABAQAAAA==.',
Da='Daddybod:BAABLgAECn8gAAIbAAkJjRK8GQC5AQAbAAkJjRK8GQC5AQAAAA==.Dainnan:BAAALgADCgEJAQAAAA==.Dalinek:BAAALgAECgUJBQAAAA==.Danicarkel:BAAALgAECgYJBgAAAA==.Darktaynt:BAAALgAECgMJBQAAAA==.Darthfox:BAAALgAECgMJBQAAAA==.',
De='Deadsean:BAAALgAECgUJDAAAAA==.Deathsyn:BAABLgAFFH8FAAIKAAIJEBggkQCqAAAKAAIJEBggkQCqAAAAAA==.Deathtracker:BAABLgAECn8VAAILAAgJ6AnMZgBIAQALAAgJ6AnMZgBIAQAAAA==.Deathwarden:BAAALgAECggJEwAAAA==.Deathñdk:BAAALgADCgEJAQAAAA==.Debuffed:BAAALgAECgEJAQAAAA==.Delathor:BAAALgAECgcJCwAAAA==.Demiloss:BAAALgAFFAEJAQABLgAECggJJQANALccAA==.Demise:BAABLgAECn8fAAIIAAgJuR06MQCtAgAIAAgJuR06MQCtAgABLgAFFAMJCAAOAC0NAA==.Demonclem:BAAALgAFFAIJAgAAAA==.Demonskinner:BAAALgADCgUJBQAAAA==.Denzo:BAAALgAECgMJAwAAAA==.Deoxyrybo:BAABLgAECn87AAMMAAkJ5Bn1CQBaAgAMAAkJ5Bn1CQBaAgANAAYJpwuViAAUAQAAAA==.Destructor:BAAALgAECgcJEwAAAA==.Devourera:BAAALgAFFAMJAwAAAA==.',
Di='Died:BAAALgADCgMJAwAAAA==.Dilldobaggin:BAAALgADCgQJBAAAAA==.Dinopriest:BAABLgAECn8XAAICAAcJLRcRHwClAQACAAcJLRcRHwClAQAAAA==.Distia:BAAALgAECgYJCAAAAA==.Divinedragon:BAABLgAECn8sAAMCAAkJGhheDgBNAgACAAkJGhheDgBNAgADAAcJ5grnLgAoAQAAAA==.Dixoncider:BAAALgAECgQJBgAAAA==.',
Do='Doboy:BAAALgADCgIJAgAAAA==.Donmanuel:BAAALgADCgEJAQAAAA==.',
Dr='Drackaris:BAAALgADCgYJBgAAAA==.Drainbamage:BAAALgAECgMJAwAAAA==.Drakin:BAABLgAECn8yAAIQAAkJgxwWFwCaAgAQAAkJgxwWFwCaAgAAAA==.Dreya:BAABLgAECn8aAAIcAAkJDR1JBwAqAgAcAAkJDR1JBwAqAgAAAA==.Dreyas:BAAALgADCgYJBgAAAA==.Drinkcoolaid:BAABLgAECn8WAAIYAAcJZBEHSQBXAQAYAAcJZBEHSQBXAQAAAA==.Dritzle:BAABLgAECn8aAAMdAAgJBhXKIQDrAQAdAAgJBhXKIQDrAQAGAAQJHgi5EwDEAAAAAA==.Droopapi:BAAALgAECgYJEQAAAA==.',
Du='Dutchman:BAACLgAFFH8UAAILAAYJ3CNIBgDSAQALAAYJ3CNIBgDSAQAuAAQKfxwAAgsACAkNIWYIAAsDAAsACAkNIWYIAAsDAAAA.',
Eh='Ehhmuh:BAAALgAECgYJCQAAAA==.Ehlumii:BAABLgAECn8UAAIEAAYJRSRvDgBvAgAEAAYJRSRvDgBvAgAAAA==.',
Ei='Eiffel:BAAALgADCgUJBQAAAA==.',
El='Eldrene:BAABLgAECn8uAAMIAAgJUR17LwA9AgAIAAgJUR17LwA9AgAeAAEJ7hOWHAA6AAAAAA==.Elethil:BAAALgADCgEJAgAAAA==.Elfstomper:BAAALgADCggJCwAAAA==.Elitepaladin:BAABLgAECn8nAAIRAAkJGBbfIQAPAgARAAkJGBbfIQAPAgAAAA==.Ellexi:BAAALgAECgYJDAAAAA==.Elyseia:BAABLgAECn8eAAILAAkJgwZtbwAzAQALAAkJgwZtbwAzAQAAAA==.',
Em='Empkin:BAAALgAECgcJEwAAAA==.',
En='Enof:BAAALgADCgIJAgAAAA==.Enpower:BAAALgADCgYJBgABLgAECgYJBgAJAAAAAA==.',
Ep='Epicsause:BAAALgAECgEJAQAAAA==.',
Er='Erelor:BAAALgADCgMJAwAAAA==.',
Es='España:BAECLgAFFH8FAAIPAAMJ2A3oHgCvAAAPAAMJ2A3oHgCvAAAuAAQKfy0ABA8ACQlOGj0KAHYCAA8ACQlOGj0KAHYCAB8ABQlGEY4UAPAAAAoAAQkAAOJiAQAAAAAA.Españaluna:BAEALgAECgcJBgABLgAFFAMJBQAPANgNAA==.Españamor:BAEALgAECgkJBgABLgAFFAMJBQAPANgNAA==.Essdeath:BAAALgAECgEJAQAAAA==.',
Fa='Farael:BAAALgAECgcJBAAAAA==.Farmerbrown:BAAALgAECgIJAwABLgAECgkJLgAQALYjAA==.Fatalmann:BAACLgAFFH8FAAMUAAMJdAWZCABtAAAUAAIJsgKZCABtAAATAAIJsQH6IABmAAAuAAQKfxYAAxQACQnMD5kVAJUBABQABwmoD5kVAJUBABMABgk2D4sYACUBAAAA.Fatalminn:BAAALgAECgUJCQAAAA==.Fathergob:BAAALgADCgEJAQAAAA==.Fatty:BAAALgADCgYJBgAAAA==.',
Fe='Fenty:BAAALgADCgEJAQAAAA==.Feralhorn:BAAALgAECgEJAQAAAA==.',
Fi='Fingerz:BAAALgADCgIJAgAAAA==.Fintan:BAAALgAECgYJBgAAAA==.',
Fl='Flarestrasz:BAAALgADCgUJCQAAAA==.Flexxar:BAAALgAECgEJAgAAAA==.Flutterby:BAAALgADCgEJAQABLgAECgkJKgACAEYFAA==.Flèxion:BAACLgAFFH8JAAIKAAUJvh4TLwBnAQAKAAUJvh4TLwBnAQAuAAQKfygAAgoACAkBJbwYAJACAAoACAkBJbwYAJACAAAA.',
Fo='Foskin:BAAALgAECgEJAQABLgAECgkJGQAWAIkbAA==.',
Fr='Frassk:BAABLgAECn8+AAMHAAgJQxcYDgAwAQAHAAYJSxYYDgAwAQAgAAQJ0hJouAC8AAAAAA==.Freja:BAAALgADCgMJBgAAAA==.Froggystyle:BAAALgAECgUJDQABLgAECggJCQAJAAAAAA==.Frostydru:BAABLgAECn8wAAIXAAgJfiHUBQBgAgAXAAgJfiHUBQBgAgAAAA==.Frozat:BAACLgAFFH8WAAITAAgJCxSXBQCdAQATAAgJCxSXBQCdAQAuAAQKfygAAxMACAkRI5MDAOoCABMACAkRI5MDAOoCAA4AAQmAEZ5eAEAAAAAA.Frösting:BAAALgADCgcJDgABLgAECgcJLQANAMgaAA==.',
Fu='Fundeedo:BAAALgAFFAIJAwAAAA==.Furballieo:BAAALgADCgIJAgAAAA==.',
Ga='Galadriels:BAAALgAECgQJBAAAAA==.Galianem:BAAALgADCgMJAwAAAA==.Gamora:BAAALgAECgYJCQAAAA==.Gandon:BAAALgAECgQJCAAAAA==.Garbarn:BAABLgAECn8VAAIQAAkJ0w/WYwCJAQAQAAkJ0w/WYwCJAQAAAA==.Garonno:BAAALgADCgIJAgAAAA==.',
Ge='Gelystine:BAAALgADCgUJCgAAAA==.Geminirunes:BAAALgADCgYJBgABLgAECgYJBgAJAAAAAA==.Germaine:BAAALgAECgQJBQAAAA==.',
Gh='Ghabi:BAAALgAECgYJBgAAAA==.Ghauri:BAAALgAECgMJBAAAAA==.',
Gi='Gia:BAABLgAECn8tAAIEAAgJyBnLEwBEAgAEAAgJyBnLEwBEAgAAAA==.',
Go='Gobx:BAAALgAECgUJBgAAAA==.Golgroth:BAABLgAECn8aAAIWAAgJXwO5TgDjAAAWAAgJXwO5TgDjAAAAAA==.Goodlocktime:BAAALgADCgIJAgAAAA==.Goodtimesm:BAAALgAECgYJBwAAAA==.Goodtymes:BAAALgAECgEJAQAAAA==.Gorearrow:BAABLgAECn8wAAMLAAkJVyLYCwDjAgALAAkJVyLYCwDjAgAhAAIJVgdjegBZAAAAAA==.Goretaint:BAAALgAECgYJDwAAAA==.Gorgesh:BAAALgADCgQJBAAAAA==.Gothladriel:BAAALgAECgYJDAAAAA==.Gottamoo:BAABLgAECn8YAAMVAAkJJwzPHgATAQAVAAkJJwzPHgATAQAZAAEJPQFWkAAaAAAAAA==.',
Gr='Greenstank:BAAALgAECggJCQAAAA==.Grimmtotem:BAAALgADCgQJBAAAAA==.Grrumpybear:BAABLgAECn8/AAIVAAgJDR4YBwBSAgAVAAgJDR4YBwBSAgAAAA==.Grundal:BAAALgADCggJCAAAAA==.',
Gu='Gunafistya:BAAALgAFFAIJBAAAAA==.Guzzler:BAAALgAECgcJCQAAAA==.',
['Gú']='Gúildarts:BAAALgADCgEJAQAAAA==.',
Ha='Haannarr:BAAALgAECgIJAgAAAA==.Hairymoodini:BAAALgAECgEJAgAAAA==.Hajin:BAAALgAECgYJDwAAAA==.Hanky:BAAALgAECgQJBAAAAA==.Havòk:BAAALgAECggJBwAAAA==.Hawthorn:BAAALgAECgMJBgAAAA==.Hazyblades:BAAALgAECgEJAQAAAA==.',
He='Helacookie:BAAALgAECggJEwAAAA==.Henso:BAAALgAECgYJBgAAAA==.Heomors:BAAALgAECgEJAQAAAA==.Hexxan:BAAALgAECgUJEAAAAA==.',
Hi='Hifumi:BAAALgADCgQJBwAAAA==.Hisagu:BAAALgADCgIJAgABLgAECgYJDwAJAAAAAA==.Hiver:BAAALgAECgQJBQAAAA==.',
Ho='Hoagar:BAAALgAECgQJBAABLgAECgUJCAAJAAAAAA==.Holes:BAAALgAECgEJAQAAAA==.Holier:BAABLgAECn8yAAIQAAkJ6xNqRADaAQAQAAkJ6xNqRADaAQAAAA==.Hollows:BAAALgAECgQJBgAAAA==.Holyatrops:BAAALgAECgkJEQABLgAFFAYJHAAgAGcaAA==.Hoppers:BAAALgAECgIJAgABLgAECgMJBgAJAAAAAA==.Hopperstotem:BAAALgAECgMJBgAAAA==.Horuu:BAAALgAECgQJBgAAAA==.Hoyboii:BAAALgADCgYJBgAAAA==.',
Hu='Hulo:BAAALgAECgIJAgAAAA==.Humbled:BAAALgAECgQJBQAAAA==.Hunteress:BAAALgADCgYJBwAAAA==.Huntkoalas:BAAALgAECgMJAwABLgAFFAYJGgAZAH0ZAA==.Hurrdurr:BAAALgAECgEJAQAAAA==.',
['Hî']='Hîflax:BAAALgAECgEJAgAAAA==.',
['Hö']='Hölyców:BAAALgADCgQJBAAAAA==.',
Ic='Ichbinstark:BAAALgAECgEJBAAAAA==.',
Id='Idonttcare:BAAALgAECgMJAwAAAA==.',
Ig='Iggnignokt:BAAALgADCgYJBwAAAA==.',
Ih='Ihealnewbs:BAAALgADCgYJDwAAAA==.',
In='Infamus:BAAALgAECgQJCQAAAA==.Invisabull:BAAALgAECgIJAgAAAA==.Invysion:BAACLgAFFH8HAAIDAAQJAweOHwALAQADAAQJAweOHwALAQAuAAQKfy4AAgMACQkXER8WAPgBAAMACQkXER8WAPgBAAAA.',
Ir='Irri:BAAALgADCgUJBQAAAA==.',
Is='Ishara:BAAALgAECggJCAABLgAECggJLgAIAFEdAA==.',
Ja='Jaidess:BAAALgADCgcJFAAAAA==.',
Je='Jeanjean:BAAALgAECgcJCAAAAA==.Jeannjeann:BAAALgAECggJEgAAAA==.Jediknîght:BAAALgAECgYJBgAAAA==.Jeep:BAACLgAFFH8NAAILAAQJnhuOJgA3AQALAAQJnhuOJgA3AQAuAAQKfycAAgsACAlAJVMEAEoDAAsACAlAJVMEAEoDAAAA.Jellybea:BAACLgAFFH8FAAIBAAMJGhvHFADwAAABAAMJGhvHFADwAAAuAAQKfyoAAwEACQltITEEABIDAAEACQltITEEABIDAAIAAgkJDMVcAGUAAAAA.',
Ji='Jibalynne:BAAALgAECgQJBAAAAA==.Jida:BAAALgAECgEJAQAAAA==.Jiffypop:BAAALgAECgcJDQABLgAECgkJLQAWAFsdAA==.Jinwooaura:BAAALgADCgcJBwAAAA==.',
Jo='Johnnycakes:BAAALgADCgMJBQAAAA==.Jonsnowxd:BAAALgADCgYJBgAAAA==.',
Jr='Jrhnbr:BAAALgADCgMJAwAAAA==.',
Ju='Juggnut:BAAALgAECgcJEQAAAA==.Jump:BAAALgAECgUJDgAAAA==.Jurisdiction:BAABLgAECn8aAAIQAAcJdA1ViAA+AQAQAAcJdA1ViAA+AQAAAA==.',
Jz='Jz:BAAALgAECgMJAwAAAA==.',
['Jì']='Jìnn:BAAALgAECgUJDwAAAA==.',
Ka='Kaan:BAABLgAECn8nAAIFAAcJhiFLEwCbAgAFAAcJhiFLEwCbAgAAAA==.Kadath:BAAALgADCgIJAwAAAA==.Kaeladín:BAAALgAECgUJCAAAAA==.Kagebouzu:BAAALgAECgYJDwAAAA==.Kahlan:BAAALgADCgcJCAABLgAECgYJDwAJAAAAAA==.Kamela:BAAALgAECgYJCAAAAA==.Karael:BAAALgAECgUJEQAAAA==.Karma:BAAALgAECgYJDwAAAA==.Kayliaa:BAAALgAECgkJAQAAAA==.Kazarke:BAAALgADCgcJGAAAAA==.',
Ke='Keho:BAABLgAECn8cAAMbAAcJWQrDNwAAAQAbAAcJNAnDNwAAAQAiAAIJkg6maABqAAAAAA==.Kenalia:BAABLgAECn8oAAIEAAgJZRajHADyAQAEAAgJZRajHADyAQAAAA==.Kengo:BAAALgAECgEJAQAAAA==.Keptalive:BAAALgADCgcJCgAAAA==.Kerzermern:BAAALgAFFAMJAwAAAA==.Kevic:BAAALgAECgcJBwABLgAFFAQJCAACADsNAA==.',
Kh='Khamaelion:BAAALgADCgcJDgAAAA==.',
Ki='Kiara:BAABLgAECn8eAAIQAAgJNiBdIgCgAgAQAAgJNiBdIgCgAgAAAA==.Kiju:BAAALgADCgYJBgAAAA==.Killaban:BAACLgAFFH8GAAIWAAMJMhXYJgDgAAAWAAMJMhXYJgDgAAAuAAQKfzIAAxYACQklIK4RAEUCABYACQngH64RAEUCACMAAwkZGVMrAJoAAAAA.Killbydeath:BAAALgAECgEJAQAAAA==.Kimberlyhárt:BAABLgAECn8uAAMQAAkJtiN/BgAkAwAQAAkJtiN/BgAkAwARAAQJ9AqPVwCpAAAAAA==.Kissmydots:BAABLgAECn9BAAIgAAgJ6B5pHgBVAgAgAAgJ6B5pHgBVAgAAAA==.Kitja:BAABLgAECn8vAAMBAAkJ7Rn+DABtAgABAAgJaBz+DABtAgADAAgJXxILFwDvAQAAAA==.Kitla:BAAALgADCgUJBQABLgAECgkJLwABAO0ZAA==.',
Kl='Klukai:BAAALgADCgcJCwABLgAECgkJIAAFAPMdAA==.',
Kn='Kneed:BAAALgADCgYJBgAAAA==.',
Ko='Koala:BAAALgAECgQJBQABLgAFFAYJGgAZAH0ZAA==.Kohman:BAABLgAECn8aAAIgAAYJ5RTOfABiAQAgAAYJ5RTOfABiAQAAAA==.Konyani:BAAALgADCgUJAQAAAA==.',
Kp='Kpop:BAAALgAECgEJAQABLgAECgcJBwAJAAAAAA==.',
Kr='Kraeven:BAAALgADCgEJAQAAAA==.Kregerath:BAAALgADCgIJAgAAAA==.Krftpnk:BAACLgAFFH8SAAIMAAQJhiVQAwCfAQAMAAQJhiVQAwCfAQAuAAQKfyQAAwwACAmxIjcEADcDAAwACAmxIjcEADcDAA0AAQkAAJgWAQAAAAAA.Krom:BAABLgAECn8tAAMWAAkJWx3UDAB7AgAWAAkJWx3UDAB7AgAjAAEJPQm+ZQAqAAAAAA==.Kronas:BAABLgAECn8VAAILAAgJ3RVjTQCMAQALAAgJ3RVjTQCMAQAAAA==.Kronophyne:BAABLgAECn83AAIIAAkJ+R1PKQBYAgAIAAkJ+R1PKQBYAgAAAA==.Kronotality:BAABLgAECn9FAAIPAAgJqCTcBADAAgAPAAgJqCTcBADAAgAAAA==.Kronotek:BAAALgAECgcJDQAAAA==.Kronotekken:BAAALgADCgYJBgAAAA==.',
Ku='Kurohitsugî:BAAALgAECgIJBAAAAA==.',
Ky='Kylorai:BAAALgAECgYJDwAAAA==.Kynbrochel:BAAALgAECgEJAQAAAA==.',
La='Laars:BAAALgAECgMJAwABLgAECggJHwAgAB4JAA==.Laimaster:BAAALgAECgEJAQAAAA==.Lakiri:BAABLgAECn80AAIcAAkJMhi9BgA4AgAcAAkJMhi9BgA4AgAAAA==.Landaeda:BAAALgAECgcJDgAAAA==.Lapsu:BAABLgAECn8fAAIiAAkJjRStFgDYAQAiAAkJjRStFgDYAQAAAA==.Lascivia:BAACLgAFFH8FAAIWAAMJrCACHgATAQAWAAMJrCACHgATAQAuAAQKfyQAAxYACQkAH1AmACcCABYACQmIHFAmACcCACQABwn4DxwoAMoAAAAA.Lawhanx:BAAALgADCgEJAQABLgAECggJJQANALccAA==.Laylahh:BAAALgADCgMJBAAAAA==.Lazy:BAABLgAECn8WAAMgAAYJyRcpiQBHAQAgAAUJyRcpiQBHAQAHAAIJxQGEYQBLAAAAAA==.',
Le='Leademon:BAABLgAECn87AAMNAAgJuB8NHgBDAgANAAgJuB8NHgBDAgAMAAIJTRrWWgB2AAAAAA==.Leadmin:BAAALgADCgMJBQABLgAECggJOwANALgfAA==.Leadmln:BAAALgADCgcJBwABLgAECggJOwANALgfAA==.Leftlane:BAABLgAECn8uAAMYAAkJsiH1AwBWAwAYAAkJsiH1AwBWAwAaAAEJgA0XiAAxAAAAAA==.Legato:BAAALgAECgcJCAABLgAFFAYJHQAYADggAA==.Lekiri:BAAALgAECgMJAwAAAA==.Lep:BAAALgAFFAEJAQABLgAFFAgJFgATAAsUAA==.Lethalkrits:BAAALgAECgcJAgAAAA==.Leva:BAABLgAECn8gAAIFAAkJ8x1aFACFAgAFAAkJ8x1aFACFAgAAAA==.',
Li='Liberté:BAAALgAECgIJAgAAAA==.Liciano:BAAALgADCgYJBgABLgAECgUJEQAJAAAAAA==.Lie:BAACLgAFFH8FAAIdAAIJTgukJwCWAAAdAAIJTgukJwCWAAAuAAQKfzMAAh0ACQliF+kMADICAB0ACQliF+kMADICAAAA.Lightsdown:BAAALgAECgYJBgAAAA==.Lilbeebs:BAAALgAECgkJEAAAAA==.Lileth:BAAALgAECgkJAgAAAA==.Lilflea:BAAALgAECggJEQAAAA==.Lilzuki:BAAALgAECggJEgAAAA==.Lilïth:BAACLgAFFH8OAAIPAAUJ8B+7EAAoAQAPAAUJ8B+7EAAoAQAuAAQKfyAAAg8ABwmDJPIGAMICAA8ABwmDJPIGAMICAAAA.Linguine:BAAALgAECgEJAgABLgAFFAQJDQABAJAZAA==.Lisalisa:BAABLgAECn8tAAIYAAcJwhYfPACLAQAYAAcJwhYfPACLAQAAAA==.Livan:BAAALgAECgMJAwAAAA==.Livia:BAAALgAECgEJAQAAAA==.',
Lo='Lohzak:BAAALgAECgEJAQAAAA==.Lousier:BAAALgAECgEJAQAAAA==.',
Lu='Lularia:BAAALgADCgIJAgAAAA==.Lumii:BAAALgAECgYJBgABLgAECgYJFAAEAEUkAA==.Luminari:BAAALgADCgEJAQABLgAECggJLgAIAFEdAA==.Lunaa:BAAALgAECggJCgAAAA==.Lurassa:BAAALgAECgYJDAAAAA==.',
Ly='Lyacon:BAAALgADCgQJBAABLgAECgkJFQAIAEEcAA==.',
['Lä']='Lä:BAEALgAECgcJBwABLgAFFAIJAgAJAAAAAA==.',
Ma='Madrie:BAAALgAECgQJBAAAAA==.Maekar:BAABLgAECn8aAAIUAAYJOg6rDQAUAQAUAAYJOg6rDQAUAQAAAA==.Maellus:BAAALgAECgEJAQAAAA==.Maelstorm:BAAALgADCgIJAgAAAA==.Mageman:BAAALgADCgYJAgAAAA==.Magicmoo:BAAALgAECgEJAQABLgAECgkJLgAQALYjAA==.Maltis:BAAALgADCgcJCwAAAA==.Mananstuff:BAABLgAECn9DAAIZAAkJbhFNGQDUAQAZAAkJbhFNGQDUAQAAAA==.Manaproblems:BAAALgADCgMJBAAAAA==.Marguerek:BAAALgADCgEJAQAAAA==.Marinara:BAAALgAECgYJCwABLgAECgYJDAAJAAAAAA==.Markamanimal:BAACLgAFFH8PAAIXAAQJjBpeAwBlAQAXAAQJjBpeAwBlAQAuAAQKfyUAAhcACAnfIYYDAPwCABcACAnfIYYDAPwCAAAA.Marnix:BAABLgAECn8XAAIaAAgJcRJOJwCFAQAaAAgJcRJOJwCFAQAAAA==.Marshail:BAAALgAECgEJAQAAAA==.',
Md='Mdbeef:BAAALgAECgUJBQAAAA==.',
Me='Medikus:BAABLgAECn8iAAMYAAgJbxwQGQBVAgAYAAgJbxwQGQBVAgAaAAMJ2gxgZQCBAAAAAA==.Meesoomagi:BAAALgAECgYJBwAAAA==.Menil:BAABLgAECn8XAAMEAAgJwBtXFgAQAgAEAAcJJhpXFgAQAgAiAAQJchbWQgDIAAAAAA==.Merryl:BAAALgAECggJDgAAAA==.Meyounow:BAAALgAECgEJAwAAAA==.',
Mi='Midnye:BAAALgADCgYJBgAAAA==.Mike:BAECLgAFFH8FAAMlAAQJmBEcAgCxAAAlAAIJzBkcAgCxAAAIAAIJZQkIiQCTAAAuAAQKfzoAAyUACQmDJE8AACoDACUACQlAIk8AACoDAAgACAlkIExGAO0BAAAA.Mips:BAAALgADCgMJAwABLgAFFAMJCAAOAC0NAA==.',
Mo='Mob:BAAALgADCgcJBwAAAA==.Mockra:BAABLgAECn89AAMIAAgJiCIuHgCNAgAIAAgJiCIuHgCNAgAeAAIJuBiqGgBCAAAAAA==.Monafae:BAAALgADCgUJBQAAAA==.Moohammered:BAAALgAECgIJAgAAAA==.Moolou:BAACLgAFFH8FAAISAAMJZRRDCADFAAASAAMJZRRDCADFAAAuAAQKfyEAAhIACQm1H4cEAI4CABIACQm1H4cEAI4CAAAA.Moonraka:BAAALgADCgUJBQAAAA==.Moosé:BAAALgAECgEJAQABLgAFFAgJIgAQAO8UAA==.Mootilator:BAAALgADCgYJBgAAAA==.Moraei:BAAALgADCgEJAQAAAA==.Mordew:BAAALgADCgUJBQABLgAECggJNAAKAEYlAA==.Morechie:BAABLgAECn8fAAImAAgJgxJgCgCEAQAmAAgJgxJgCgCEAQAAAA==.Morgatho:BAAALgADCgEJAwAAAA==.Mortiferon:BAABLgAECn8xAAIKAAkJJh1mFQCmAgAKAAkJJh1mFQCmAgAAAA==.',
Mu='Muhgunguh:BAAALgAECgEJAQAAAA==.Munnky:BAABLgAECn8mAAIEAAYJlyGAFgApAgAEAAYJlyGAFgApAgAAAA==.Murmaider:BAAALgADCgIJAgAAAA==.',
My='Mythrandere:BAAALgADCgcJCwAAAA==.',
['Má']='Mánflu:BAACLgAFFH8HAAIWAAQJ1RYlEwBCAQAWAAQJ1RYlEwBCAQAuAAQKfysAAyMACQniHhIDAOICACMACQniHhIDAOICABYABwlJGlI0ANkBAAAA.',
['Mô']='Môrrigãn:BAAALgADCgMJAwAAAA==.',
['Mö']='Mörgänä:BAAALgADCgMJAwAAAA==.',
Na='Naissa:BAAALgAECgQJCwAAAA==.Nakanir:BAAALgAECgYJBgAAAA==.Nalfeign:BAAALgAECgQJBQAAAA==.Napa:BAAALgAECgQJBAABLgAFFAYJEwAYAKMXAA==.Narn:BAABLgAECn9BAAQUAAgJSh3RCQBCAgAUAAcJrRjRCQBCAgAOAAgJEhlIGQDsAQATAAIJLQiEQQBgAAAAAA==.',
Ne='Nealite:BAAALgAECgkJBgAAAA==.Necrotion:BAAALgAECgYJEgAAAA==.Nei:BAAALgAECgEJAQAAAA==.Nerrisa:BAABLgAECn8iAAICAAkJERQvGgDPAQACAAkJERQvGgDPAQAAAA==.Nertt:BAAALgADCgYJBgABLgAECggJQQAUAOceAA==.Neublood:BAAALgAECgQJCAAAAA==.',
Ni='Nicodemus:BAAALgAECgYJCQAAAA==.',
No='Noblewarrior:BAACLgAFFH8fAAIWAAYJsR+xAwDVAQAWAAYJsR+xAwDVAQAuAAQKfysAAhYACAmuJLAJAKcCABYACAmuJLAJAKcCAAAA.Noctilus:BAAALgAECgcJCQAAAA==.Nohkari:BAAALgADCggJCwABLgAECgkJHwAgANAUAA==.Nooj:BAACLgAFFH8qAAMGAAgJkSIUAADaAgAGAAgJkSIUAADaAgAdAAYJiRRfCwB/AQAuAAQKfx4AAwYACQl7ITsAAMMDAAYACQl7ITsAAMMDAB0ABgmFEpA6AEQBAAAA.Notakoala:BAACLgAFFH8aAAIZAAYJfRkdCgCdAQAZAAYJfRkdCgCdAQAuAAQKfycAAxkACAlHJFQNAMUCABkACAlHJFQNAMUCABUAAQk3En5SADQAAAAA.Nothnx:BAAALgAFFAEJAwAAAA==.Notoriouspat:BAABLgAECn8bAAILAAcJag9QYABYAQALAAcJag9QYABYAQAAAA==.Notsamadeath:BAAALgAFFAMJAwAAAA==.Novia:BAAALgAECgYJBgAAAA==.Noyber:BAAALgAECgMJBAAAAA==.Noydin:BAAALgAFFAEJAgAAAA==.',
Ny='Nysselle:BAAALgADCgMJAwAAAA==.',
['Ní']='Nínebreaker:BAAALgADCgQJAwAAAA==.',
['Nü']='Nüll:BAAALgAECggJEQAAAA==.',
Ob='Obern:BAABLgAECn8WAAInAAkJZhuHEQAFAgAnAAkJZhuHEQAFAgAAAA==.Oblïna:BAABLgAECn8XAAIEAAcJMAYlUADPAAAEAAcJMAYlUADPAAAAAA==.',
Od='Odiumaeterna:BAAALgADCgcJBwAAAA==.',
Of='Offensivé:BAAALgAECgMJBwAAAA==.',
On='Onetozerosix:BAABLgAECn8gAAIKAAkJ/xs3MgATAgAKAAkJ/xs3MgATAgAAAA==.Onos:BAAALgAECgEJAQAAAA==.Onsen:BAAALgAECgIJAgAAAA==.',
Oo='Oogak:BAAALgAECgUJBgAAAA==.Oomigig:BAAALgADCgUJBQAAAA==.',
Op='Opalily:BAAALgADCgYJCAAAAA==.Operation:BAAALgAECgQJCAAAAA==.',
Or='Orghrax:BAAALgADCgEJAQAAAA==.Orisys:BAAALgAECgIJAgAAAA==.',
Os='Osteer:BAAALgAECgYJBgAAAA==.',
Ot='Otterjim:BAAALgADCgQJBAAAAA==.',
Pa='Pahaa:BAAALgAECgUJBQAAAA==.Pairadeez:BAAALgAECgYJCwAAAA==.Pajamabanana:BAAALgADCgIJAgAAAA==.Pandablaze:BAAALgAECgYJDAAAAA==.Panterarey:BAAALgADCgYJEAAAAA==.Papalego:BAABLgAECn8vAAILAAgJZA60SwCSAQALAAgJZA60SwCSAQAAAA==.Parakka:BAABLgAECn8tAAIYAAkJFRS6IgAQAgAYAAkJFRS6IgAQAgAAAA==.Patak:BAAALgADCgkJCgAAAA==.Pavle:BAAALgADCgcJCQAAAA==.Pawp:BAAALgAECgYJCQABLgAECggJHwABAMUSAA==.',
Pe='Pearagon:BAAALgAECggJEgABLgAFFAYJEwAYAKMXAA==.Pepsidew:BAAALgADCgcJDAAAAA==.Pepsisprite:BAABLgAECn8yAAIBAAgJSxufDABzAgABAAgJSxufDABzAgAAAA==.Pesky:BAABLgAECn8eAAIZAAYJShU+LwAzAQAZAAYJShU+LwAzAQABLgAFFAMJBgAIAFsRAA==.',
Pf='Pfchanguz:BAAALgADCgcJDAAAAA==.',
Ph='Phdbeef:BAABLgAFFH8GAAIVAAIJ+xvqEQCrAAAVAAIJ+xvqEQCrAAABLgAFFAUJDgAPAPAfAA==.Phlemm:BAAALgAECgEJAQAAAA==.Phoivos:BAABLgAECn8VAAIIAAkJQRwKIQDvAgAIAAkJQRwKIQDvAgAAAA==.',
Pi='Picklez:BAABLgAECn8jAAIKAAcJlCI7JgBHAgAKAAcJlCI7JgBHAgAAAA==.Pissflizzle:BAABLgAECn8dAAIgAAgJ9w0vWQB8AQAgAAgJ9w0vWQB8AQAAAA==.',
Pl='Plaquenil:BAAALgADCgEJAQAAAA==.',
Po='Poison:BAAALgADCgEJAQAAAA==.Porkroaster:BAABLgAECn8aAAIIAAcJEAnQmwAnAQAIAAcJEAnQmwAnAQAAAA==.',
Pr='Praye:BAAALgAFFAIJAgAAAA==.Priestop:BAAALgAECgEJAQAAAA==.',
Ps='Psyfarian:BAAALgADCgcJDQAAAA==.Psyop:BAAALgAECgEJAQABLgAECggJEwAJAAAAAA==.',
Qu='Quillswitch:BAAALgAECgEJAQAAAA==.',
Ra='Radduc:BAABLgAECn8ZAAMRAAYJKxibLgB6AQARAAYJKxibLgB6AQAQAAEJlQZ0cQErAAAAAA==.Ragerade:BAAALgAECgQJBQAAAA==.Raidu:BAAALgAECgMJAwAAAA==.Ralpherion:BAAALgADCgIJAgAAAA==.Ranoa:BAAALgAECgQJCgAAAA==.Raphåel:BAAALgAFFAEJAQAAAA==.Ravioli:BAAALgAECgQJBgAAAA==.Razialum:BAAALgADCgYJBgAAAA==.Razorsteps:BAAALgAFFAcJBAAAAA==.Razzberry:BAAALgADCgYJDAAAAA==.',
Re='Rebrowth:BAAALgAECgcJEgAAAA==.Redren:BAAALgADCgIJAgAAAA==.Reegrets:BAAALgAECggJDQAAAA==.Reena:BAAALgADCgIJAwAAAA==.Regiplague:BAAALgAECgYJCwAAAA==.Regretty:BAAALgAECggJDQABLgAECggJDQAJAAAAAA==.Renthar:BAAALgADCgUJBQAAAA==.Renzdingo:BAAALgAECgkJDwAAAA==.Repete:BAAALgAECgUJDgAAAA==.Resyek:BAABLgAECn85AAIIAAgJOyTKFADCAgAIAAgJOyTKFADCAgAAAA==.Reverendgank:BAAALgAECgEJAQAAAA==.',
Rh='Rhaxanna:BAAALgADCgYJBgAAAA==.',
Ri='Rick:BAAALgAECgQJBAAAAA==.Rickheaddk:BAAALgADCgEJAgAAAA==.Riivan:BAABLgAECn8UAAIgAAcJjAtVegAvAQAgAAcJjAtVegAvAQAAAA==.Rini:BAAALgAECgUJCgABLgABCgYJCwAJAAAAAA==.Rishi:BAABLgAECn83AAIQAAgJBBXQXgCUAQAQAAgJBBXQXgCUAQAAAA==.Rivian:BAAALgADCgIJAgAAAA==.',
Ro='Robot:BAABLgAECn8eAAIEAAcJtQ8sLwBAAQAEAAcJtQ8sLwBAAQAAAA==.Rokmog:BAAALgAECgIJAgAAAA==.Rollinburn:BAAALgADCgYJCQAAAA==.Roxanol:BAAALgADCgEJAQABLgAECggJOwARAOUcAA==.',
Ru='Rumbrave:BAAALgAECgYJCwAAAA==.Rumtumtugger:BAAALgADCgkJCQAAAA==.',
['Rá']='Ráyune:BAAALgADCgcJBwAAAA==.',
Sa='Sackos:BAAALgAECgEJAQAAAA==.Sadpanda:BAAALgADCgUJCAAAAA==.Saffronspark:BAAALgADCgkJHwABLgAECgkJOAAiAPUfAA==.Sainsei:BAAALgAECgYJEgAAAA==.Saith:BAAALgAECgEJBgAAAA==.Samasear:BAABLgAECn8UAAIWAAgJ0w8wMgDjAQAWAAgJ0w8wMgDjAQABLgAFFAYJGgAKAN0gAA==.Sandwitch:BAABLgAECn9BAAMgAAgJtRkcNwDkAQAgAAgJtRkcNwDkAQAHAAIJmxB0UwB0AAAAAA==.Sargatana:BAABLgAECn8qAAIbAAkJgh0UBgC+AgAbAAkJgh0UBgC+AgAAAA==.Sars:BAABLgAECn8fAAMEAAcJ7yWEBwD1AgAEAAcJ7yWEBwD1AgAiAAMJGhNBTwCdAAAAAA==.Sauronxd:BAAALgAECgUJCAAAAA==.',
Sc='Scalion:BAABLgAECn8lAAMNAAgJtxztJAAcAgANAAgJtxztJAAcAgAMAAQJ+BG9SwDAAAAAAA==.Scarne:BAAALgAECgIJAgAAAA==.Schrodinger:BAABLgAECn8YAAISAAcJWAofIQDaAAASAAcJWAofIQDaAAAAAA==.',
Se='Selunee:BAAALgADCgEJAQAAAA==.Sepharad:BAAALgADCggJEgAAAA==.Septicflësh:BAAALgADCgEJAQAAAA==.Severum:BAABLgAECn82AAIkAAgJkB35BwBbAgAkAAgJkB35BwBbAgAAAA==.',
Sh='Shadowtiger:BAABLgAECn8uAAILAAkJUQyyPADCAQALAAkJUQyyPADCAQAAAA==.Shadrad:BAABLgAECn8aAAIQAAkJsiXJBQAvAwAQAAkJsiXJBQAvAwAAAA==.Shamanor:BAAALgAECgcJCAAAAA==.Shammoo:BAAALgAECgIJBAABLgAFFAgJIgAQAO8UAA==.Shantz:BAABLgAECn8mAAIPAAgJORM+FwB7AQAPAAgJORM+FwB7AQAAAA==.Shiban:BAAALgAECggJEAAAAA==.Shirtless:BAAALgAECggJEQAAAA==.Shockra:BAABLgAECn8dAAIaAAkJ4xceHADUAQAaAAkJ4xceHADUAQAAAA==.Shokalypse:BAAALgADCgEJAQAAAA==.Shortbuss:BAAALgADCgYJEgAAAA==.',
Si='Sige:BAAALgADCgYJBgAAAA==.Sillygoose:BAAALgADCgkJDwAAAA==.Silverfox:BAAALgADCgMJAQABLgAECggJPQAIAIgiAA==.Silx:BAABLgAECn8VAAMDAAcJMBE8IQCJAQADAAcJMBE8IQCJAQACAAEJoBZEXQA/AAAAAA==.Simvastatin:BAAALgADCgQJBAAAAA==.Sinterdeath:BAAALgAECgIJAgAAAA==.',
Sk='Skik:BAAALgAECgUJBQAAAA==.Skulltide:BAAALgADCgcJCQAAAA==.',
Sl='Slaggz:BAAALgADCgQJBAAAAA==.Slamvoke:BAAALgAECgYJBgABLgAFFAUJDwAWAKwVAA==.Slaté:BAAALgAECgEJAgAAAA==.Slowrot:BAAALgAECgQJBAABLgAECgkJLgAQALYjAA==.Slâte:BAAALgAFFAEJAgAAAA==.',
Sm='Smiteasaurus:BAAALgAECgEJAQAAAA==.Smorthian:BAAALgAECgcJDQAAAA==.',
Sn='Snarll:BAAALgADCgEJAQAAAA==.Sniffinsteak:BAABLgAECn8bAAMiAAkJGiGNBADuAgAiAAkJGiGNBADuAgAEAAEJtwuFkQAjAAAAAA==.',
So='Somaliabiggs:BAAALgAECgYJCgAAAA==.Sonar:BAAALgADCgYJBgABLgAECggJNAAKAEYlAA==.Sorraba:BAAALgAFFAIJAgAAAA==.Sorrabo:BAACLgAFFH8IAAIDAAMJ8weaJgDLAAADAAMJ8weaJgDLAAAuAAQKfxkABAMACQn6EeURACsCAAMACQn6EeURACsCAAEAAwm6Az5WAFUAAAIAAQkpA7B7ACIAAAAA.Soryan:BAABLgAECn8VAAIQAAgJfwbTlQBRAQAQAAgJfwbTlQBRAQAAAA==.Sosalkin:BAAALgAECgcJEQAAAA==.Souls:BAACLgAFFH8OAAIgAAMJLCNPGQAnAQAgAAMJLCNPGQAnAQAuAAQKfx4ABCAABwnhIyYXAMkCACAABwnhIyYXAMkCACYAAQkAAPIfAHIAAAcAAQm1GkhiAEoAAAAA.',
Sp='Spankenstine:BAABLgAECn8gAAMQAAkJYxZQOQD9AQAQAAkJYxZQOQD9AQARAAUJowh+YwDuAAABLgABCgYJCwAJAAAAAA==.Spannky:BAAALgAECgUJBQABLgAECgYJJgAEAJchAA==.',
Sq='Squishÿ:BAAALgAECgYJDwAAAA==.',
St='Starshriek:BAAALgADCgcJBwAAAA==.Stinkyfree:BAABLgAECn8cAAIbAAYJzBjSLgCcAQAbAAYJzBjSLgCcAQAAAA==.Stinkynatto:BAAALgADCgYJBgABLgAECgYJHAAbAMwYAA==.Stormcharred:BAABLgAECn8eAAIIAAgJ6SCgKADQAgAIAAgJ6SCgKADQAgAAAA==.Stormknight:BAAALgAECgUJDwAAAA==.Straka:BAABLgAECn8fAAIFAAkJERIZPgCrAQAFAAkJERIZPgCrAQAAAA==.',
Su='Suffers:BAAALgAECgEJAQAAAA==.Suneater:BAAALgAECgEJAgAAAA==.Sunmane:BAAALgADCgcJCAABLgAECgYJFgAXAHQTAA==.Supaheals:BAAALgAECgEJAQAAAA==.Superdruid:BAAALgADCgUJBQABLgAFFAcJFAAQADodAA==.Supermonks:BAAALgAECggJDAABLgAFFAcJFAAQADodAA==.Superpi:BAABLgAECn8ZAAIDAAcJFx5MDwBOAgADAAcJFx5MDwBOAgABLgAFFAcJFAAQADodAA==.Superret:BAACLgAFFH8UAAIQAAcJOh3GCgC+AQAQAAcJOh3GCgC+AQAuAAQKfycAAxAACQkGI/gOABYDABAACQkGI/gOABYDABEAAQn7FFt3ADwAAAAA.Superskeet:BAACLgAFFH8HAAIRAAMJtAvkKACzAAARAAMJtAvkKACzAAAuAAQKfyUAAhEACAl3F8scAPYBABEACAl3F8scAPYBAAAA.',
Sw='Swaggbag:BAAALgADCgEJAQAAAA==.Swiftia:BAABLgAECn8VAAMhAAYJlBZYOwBzAQAhAAYJjhRYOwBzAQALAAUJAg3FoQDFAAAAAA==.Swiftybutt:BAAALgAECggJCgAAAA==.',
Sy='Sylphièl:BAACLgAFFH8LAAMGAAQJagIyBQALAQAGAAQJagIyBQALAQAoAAEJqQJiAgBEAAAuAAQKfygAAwYACAkwDlUJAIcBACgACAmbCq8EALkBAAYACAlDDVUJAIcBAAAA.Syncere:BAAALgAECgEJAQAAAA==.Synhunt:BAAALgAFFAEJAgAAAA==.Syrene:BAAALgAECgMJBgAAAA==.',
Ta='Tandarì:BAACLgAFFH8QAAIQAAUJLRxxHwBXAQAQAAUJLRxxHwBXAQAuAAQKfyIAAhAACQmjHqoPABEDABAACQmjHqoPABEDAAAA.Tano:BAAALgAECgUJCAABLgAECggJPQAIAIgiAA==.Tanparo:BAAALgAECgMJAwAAAA==.Tarick:BAAALgAECgYJCAAAAA==.Tasty:BAAALgAECgQJCwAAAA==.Tawnii:BAAALgADCgcJEgAAAA==.Tazath:BAAALgAECgEJAgAAAA==.Taírn:BAAALgAECgYJDwAAAA==.',
Te='Tehpredator:BAAALgAFFAMJAwAAAA==.Teilin:BAACLgAFFH8dAAIYAAYJOCBIBgAPAgAYAAYJOCBIBgAPAgAuAAQKfyIAAhgACQmQI7MEACcDABgACQmQI7MEACcDAAAA.',
Th='Theaterthug:BAAALgADCgcJFQAAAA==.Thehulkster:BAAALgAECgMJAwAAAA==.Thetinman:BAAALgAECgEJAQAAAA==.Thevelo:BAAALgAECgIJAgABLgAECgYJDgAJAAAAAA==.Thewhole:BAAALgAFFAIJAQAAAA==.Theßigshot:BAABLgAECn8VAAIFAAYJICPAIgAyAgAFAAYJICPAIgAyAgAAAA==.Thoseheals:BAAALgADCgQJBAAAAA==.Thunderskeet:BAACLgAFFH8KAAINAAMJARngQQD3AAANAAMJARngQQD3AAAuAAQKfzwAAw0ACQkFJZMCAFMDAA0ACQkFJZMCAFMDAAwABwlYHRAUADICAAAA.Thundurus:BAACLgAFFH8MAAIaAAQJYRHyGgAWAQAaAAQJYRHyGgAWAQAuAAQKfyUAAhoACAm9FlYsAGcBABoACAm9FlYsAGcBAAAA.',
Ti='Timmayy:BAABLgAECn8kAAIgAAgJCBZ5OQAmAgAgAAgJCBZ5OQAmAgAAAA==.Tindrill:BAABLgAECn8iAAIjAAkJJyQjAQBIAwAjAAkJJyQjAQBIAwAAAA==.Tireiron:BAAALgADCgYJBgAAAA==.',
To='Tomraedisk:BAABLgAECn8ZAAIWAAkJiRtYEABTAgAWAAkJiRtYEABTAgAAAA==.Totemagoat:BAACLgAFFH8ZAAMaAAUJ+hAuGgAaAQAaAAUJ+hAuGgAaAQAYAAQJzxjUJgAOAQAuAAQKfzIAAxoACQkJHWkTACUCABoACAnQG2kTACUCABgACAlIFdgsANcBAAAA.Totemlyfine:BAABLgAECn8rAAMYAAgJlSJdCwDaAgAYAAgJlSJdCwDaAgAaAAEJ0CA6cQBeAAAAAA==.Totesmugoats:BAAALgAECggJEgAAAA==.Toxicshock:BAAALgADCgEJAQAAAA==.',
Tr='Traprkeepr:BAAALgADCgcJDQAAAA==.Treechains:BAABLgAECn8WAAMYAAYJ8hc8QQB2AQAYAAYJ8hc8QQB2AQAaAAEJZQPtkQAlAAAAAA==.Treefist:BAAALgAECgIJAgAAAA==.Treeshield:BAAALgADCgYJBgAAAA==.Trickster:BAAALgAECgEJAQAAAA==.Truth:BAAALgADCgcJDQAAAA==.',
Tu='Turbobis:BAAALgAECgIJAgAAAA==.',
Tw='Twentyfour:BAACLgAFFH8FAAIFAAIJ4ARxTABuAAAFAAIJ4ARxTABuAAAuAAQKfxUAAgUABwmGEOVdADgBAAUABwmGEOVdADgBAAAA.Twigberry:BAAALgAECgUJCAAAAA==.',
Ty='Typeshxxt:BAAALgADCgEJAQAAAA==.Tytanea:BAAALgAECgMJBAAAAA==.',
['Tø']='Tøqa:BAAALgAFFAEJAQAAAA==.',
Uh='Uhnderstood:BAABLgAECn8mAAIEAAkJjh1qEABUAgAEAAkJjh1qEABUAgAAAA==.',
Un='Undeadmonks:BAABLgAECn8/AAMbAAkJjBkDDABWAgAbAAkJjBkDDABWAgAiAAMJdgrEZQB2AAAAAA==.',
Va='Vahe:BAAALgAECgEJAQAAAA==.Vale:BAAALgAECgUJBQAAAA==.Valeshot:BAABLgAECn8kAAILAAkJ/QluPwCxAQALAAkJ/QluPwCxAQAAAA==.Valkillrie:BAAALgADCgcJBwAAAA==.Vall:BAAALgAECgYJCgAAAA==.Valssra:BAABLgAECn8XAAIIAAcJmAojlgAxAQAIAAcJmAojlgAxAQAAAA==.Vampiricvrus:BAAALgAECgQJBgAAAA==.',
Ve='Vedbow:BAACLgAFFH8UAAQnAAQJmiPYBQCDAQAnAAQJ0iHYBQCDAQALAAMJMBWAPwDtAAAhAAEJgA+6JwBNAAAuAAQKfxwABAsACQnIIh4UAJUCAAsACAm5IR4UAJUCACEABAnyHyc8AG4BACcAAwldIHIuAA8BAAAA.Vedronas:BAABLgAECn8VAAIQAAcJOSOcHgC0AgAQAAcJOSOcHgC0AgAAAA==.Venlii:BAAALgADCgEJAQAAAA==.Verdict:BAAALgAECgYJBgAAAA==.Veritae:BAAALgADCgYJBgAAAA==.Vern:BAABLgAECn8YAAMDAAgJ+BchHQC2AQADAAgJ+BchHQC2AQACAAIJgwYoWQBWAAAAAA==.Vernaar:BAAALgAECgEJAQABLgAECggJGAADAPgXAA==.Vernah:BAABLgAECn8VAAIRAAgJ1RlQEwBRAgARAAgJ1RlQEwBRAgABLgAECggJGAADAPgXAA==.Verybad:BAABLgAECn9EAAIIAAYJpRwgewDbAQAIAAYJpRwgewDbAQAAAA==.',
Vo='Voidify:BAAALgADCgEJAgAAAA==.Voodoodrood:BAAALgADCgIJAgAAAA==.',
['Vè']='Vèronique:BAAALgADCgYJBgAAAA==.',
Wa='Waambler:BAAALgADCgEJAQAAAA==.Waamchifu:BAABLgAECn8zAAIbAAgJeSM1BQDSAgAbAAgJeSM1BQDSAgAAAA==.Wack:BAAALgADCgUJBgAAAA==.Waka:BAAALgADCgcJCwAAAA==.Waltersight:BAAALgAECgcJDgAAAA==.',
We='Wesker:BAAALgADCgYJBgAAAA==.Westavia:BAAALgAECgEJAQABLgAECgkJLgAQALYjAA==.Wewabear:BAAALgADCgQJBAAAAA==.',
Wh='Whateley:BAAALgAECgcJCgAAAA==.Whosthetänk:BAAALgAECgEJAQAAAA==.',
Wi='Wisebrownguy:BAABLgAECn8nAAIQAAgJqB3VIwBVAgAQAAgJqB3VIwBVAgABLgAECgkJGQAWAIkbAA==.',
Wo='Worgana:BAAALgAECgMJAwAAAA==.Wormchild:BAAALgADCgQJBAAAAA==.',
Wu='Wukòng:BAAALgADCgEJAQAAAA==.',
Xe='Xercuul:BAAALgAECgQJBwAAAA==.',
Xi='Xikar:BAAALgAECgQJCAAAAA==.',
Xp='Xplosiv:BAAALgADCgcJBwABLgAFFAUJGAAYAFAcAA==.',
Ye='Yeddy:BAAALgADCgcJBwAAAA==.Yel:BAAALgADCgYJCAAAAA==.',
Yo='Yoel:BAAALgADCgEJAQAAAA==.',
Yu='Yudah:BAACLgAFFH8JAAQnAAMJuRQdGQDgAAAnAAMJDQ4dGQDgAAALAAIJzxw0VgCjAAAhAAEJ3AA9LAAsAAAuAAQKfy0ABCcACAmgHWITAPEBACcACAkZGWITAPEBACEABglUFl8QAC8BAAsABwlgD3J7ABkBAAAA.Yuta:BAAALgADCgcJBgAAAA==.',
Za='Zalrei:BAAALgADCgYJBgAAAA==.Zalupa:BAAALgAECgIJAgAAAA==.Zanghonghua:BAABLgAECn84AAMiAAkJ9R+QBQDWAgAiAAkJ9R+QBQDWAgAEAAEJSRXWZAA+AAAAAA==.Zarinaria:BAABLgAECn8cAAINAAYJ2Q7qfQAvAQANAAYJ2Q7qfQAvAQAAAA==.',
Ze='Zetsumei:BAAALgADCgMJAwAAAA==.',
Zh='Zhael:BAABLgAECn8bAAINAAgJFhzFMwDXAQANAAgJFhzFMwDXAQAAAA==.',
Zi='Zitizen:BAAALgADCgYJBwAAAA==.',
Zo='Zodstrike:BAABLgAECn8oAAMNAAkJAQVJdQAQAQANAAkJAQVJdQAQAQAMAAQJnwIXWACGAAAAAA==.Zomara:BAAALgAECgIJBwAAAA==.Zooboo:BAABLgAECn8XAAIWAAkJURfGHQDcAQAWAAkJURfGHQDcAQAAAA==.Zophie:BAAALgADCgEJAQAAAA==.',
['Är']='Ärcane:BAAALgAECgkJCgAAAA==.',
['Ät']='Ätticus:BAAALgAECgMJAQAAAA==.',
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
