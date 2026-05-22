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

local lookup = {'Priest-Holy','Priest-Shadow','Priest-Discipline','Monk-Mistweaver','Druid-Restoration','Rogue-Assassination','Warlock-Destruction','Mage-Frost','Unknown-Unknown','DeathKnight-Unholy','DemonHunter-Havoc','DemonHunter-Devourer','Evoker-Augmentation','DeathKnight-Blood','Paladin-Holy','Paladin-Retribution','Paladin-Protection','Evoker-Preservation','Evoker-Devastation','Druid-Guardian','Warrior-Fury','Druid-Feral','Druid-Balance','Shaman-Restoration','Shaman-Elemental','Monk-Brewmaster','Shaman-Enhancement','Rogue-Subtlety','Hunter-BeastMastery','Mage-Arcane','Monk-Windwalker','DeathKnight-Frost','Warlock-Demonology','Hunter-Marksmanship','Warrior-Arms','Warrior-Protection','Mage-Fire','Warlock-Affliction','Hunter-Survival','Rogue-Outlaw',}
local provider = {region='US',realm='LaughingSkull',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Ablucia:BAAALgADCgUJCQAAAA==.',
Ac='Achannara:BAAALgADCgcJBwAAAA==.',
Ae='Aennisong:BAAALgAECgMJAwAAAA==.Aeoliana:BAAALgAECggJEgAAAA==.',
Aj='Ajier:BAABLgAECn8tAAIBAAkJKRajFgAnAgABAAkJKRajFgAnAgAAAA==.',
Al='Aleraz:BAACLgAFFH8NAAMBAAQJkBl8CgBCAQABAAQJkBl8CgBCAQACAAMJvxGVFgDyAAAuAAQKfzIABAIACQlLHI0HAJQCAAIACQlLHI0HAJQCAAEABwncIOEVAC0CAAMAAwkmB2ZEAHkAAAAA.Allcapwne:BAAALgAECgcJCwAAAA==.Allenduin:BAAALgAECgYJBwAAAA==.Alshau:BAABLgAECn8aAAIEAAcJ0BdfIwCYAQAEAAcJ0BdfIwCYAQAAAA==.Alucart:BAAALgADCgcJCgAAAA==.',
Am='Ambrosia:BAAALgAECgYJDwAAAA==.Amity:BAAALgADCgkJEAABLgAECgkJIAAFAPMdAA==.',
An='Anewrbyss:BAAALgAECgUJDwAAAA==.Angela:BAABLgAECn8jAAIDAAkJgRiECwBgAgADAAkJgRiECwBgAgAAAA==.Anna:BAAALgAECgQJBQAAAA==.Annalunà:BAAALgADCgIJAgAAAA==.Annälise:BAAALgADCgEJAQAAAA==.',
Ap='Apeople:BAABLgAECn8qAAIGAAkJ0CFaAQAhAwAGAAkJ0CFaAQAhAwAAAA==.Apocalýpsè:BAAALgAECgEJAQAAAA==.Applebottum:BAAALgAECgYJDAAAAA==.Appärition:BAABLgAECn8lAAIHAAgJ3htFAwAcAgAHAAgJ3htFAwAcAgAAAA==.',
Ar='Arleance:BAAALgAECgEJAQAAAA==.Arondael:BAABLgAECn8bAAIGAAgJ3xTyBQDFAQAGAAgJ3xTyBQDFAQAAAA==.Arsène:BAAALgADCgcJCwAAAA==.',
As='Aszun:BAAALgADCgUJBQAAAA==.',
Au='Aurialis:BAAALgAECgcJDQAAAA==.',
Av='Avanti:BAABLgAECn8nAAIIAAgJRRcyQQDWAQAIAAgJRRcyQQDWAQAAAA==.Avendeloria:BAAALgAECgYJDQAAAA==.',
Az='Azrahn:BAAALgADCgQJBQAAAA==.',
['Aü']='Aüra:BAAALgAECgEJAQABLgAECggJCQAJAAAAAA==.',
Ba='Backmoist:BAAALgAECgMJBAAAAA==.Bagmaster:BAACLgAFFH8IAAIBAAMJIyJtDAAnAQABAAMJIyJtDAAnAQAuAAQKfy8AAgEACQkAJpkCAD4DAAEACQkAJpkCAD4DAAAA.Baktolife:BAAALgAECgkJBAAAAA==.Bam:BAAALgAECgQJBQABLgAFFAIJBgAKAJshAA==.Bartholomoo:BAABLgAECn83AAIKAAgJOyOnEgCZAgAKAAgJOyOnEgCZAgAAAA==.Bayonetta:BAAALgAECgcJDAAAAA==.',
Be='Beeftornado:BAAALgAECgQJBAAAAA==.Belakor:BAAALgADCgIJAgAAAA==.Ber:BAAALgAECgEJAgAAAA==.',
Bi='Bigbusta:BAAALgADCgMJAwAAAA==.Bildros:BAAALgAECgEJAQAAAA==.Birgite:BAAALgAECgYJEAAAAA==.Bizniz:BAAALgAECgYJDAAAAA==.',
Bl='Blastin:BAAALgADCgcJBwAAAA==.Blazefury:BAAALgAECgQJEgAAAA==.Blazeknight:BAABLgAECn8mAAILAAgJbxqFFgAXAgALAAgJbxqFFgAXAgAAAA==.Blazemaker:BAABLgAECn8ZAAIIAAYJPBBjjQAiAQAIAAYJPBBjjQAiAQAAAA==.Blazemaster:BAAALgAECgQJCAAAAA==.Blinduru:BAACLgAFFH8KAAIMAAMJ+R88MQASAQAMAAMJ+R88MQASAQAuAAQKfy8AAgwACQmiJB8FAAoDAAwACQmiJB8FAAoDAAAA.Blitz:BAAALgAECgIJAgAAAA==.Blocktor:BAAALgAECgMJAwABLgAECgYJHAAMANkOAA==.Bluberriez:BAAALgAECgYJBgAAAA==.',
Bo='Bobbiepines:BAAALgAECgEJAQAAAA==.Book:BAAALgAECgcJBwAAAA==.Bookie:BAAALgADCgQJBAAAAA==.Booza:BAAALgAECgIJAgAAAA==.Borkenshwang:BAAALgADCgYJCwAAAA==.Boydik:BAAALgAECgQJBQAAAA==.',
Bp='Bpaìn:BAABLgAECn8WAAINAAYJORULKwA5AQANAAYJORULKwA5AQAAAA==.',
Br='Brewlïth:BAAALgAECgIJAgABLgAFFAUJCwAOAPAfAA==.Brink:BAAALgAECgUJDAAAAA==.Brojac:BAAALgAECgcJDgAAAA==.Brokil:BAAALgADCggJDAAAAA==.Bromaster:BAAALgAECgQJBQAAAA==.Brones:BAAALgAECggJAgAAAA==.Brossiere:BAABLgAECn8YAAQPAAgJiBphKgBtAQAPAAUJiRlhKgBtAQAQAAYJmBHNqAAwAQARAAUJYRZFGgDwAAAAAA==.Brotemic:BAAALgAECgEJAQAAAA==.Bru:BAABLgAECn8oAAIBAAkJdhzsDACGAgABAAkJdhzsDACGAgAAAA==.Brutalizèr:BAAALgADCgYJBgABLgAECgEJAQAJAAAAAA==.',
Bu='Bubblegal:BAAALgAECgEJAQAAAA==.Bullsmcgee:BAABLgAECn8tAAMKAAgJaSTMDADMAgAKAAgJaSTMDADMAgAOAAEJAAAXQwA9AAAAAA==.Burninghunt:BAAALgADCgcJDAAAAA==.Burningtree:BAAALgAECgYJEQAAAA==.Burny:BAAALgADCgEJAQAAAA==.Burrder:BAAALgADCggJCAAAAA==.Bustdown:BAAALgADCggJDwAAAA==.Buttslapper:BAAALgADCggJCAAAAA==.',
['Bö']='Börck:BAAALgADCgUJBQAAAA==.',
['Bø']='Bøb:BAAALgAECggJCwAAAA==.',
Ca='Camamoonmana:BAABLgAECn8aAAIFAAkJ3BMlKwC2AQAFAAkJ3BMlKwC2AQAAAA==.Captcorndog:BAABLgAECn8kAAQNAAgJIhKBIACDAQANAAgJIhKBIACDAQASAAUJ8wN5OACnAAATAAEJAAC0QAAvAAAAAA==.Catdog:BAABLgAECn8bAAIUAAYJ3BfSDwB8AQAUAAYJ3BfSDwB8AQAAAA==.Catechism:BAABLgAECn8WAAIPAAcJjh33FAAaAgAPAAcJjh33FAAaAgAAAA==.',
Ce='Cemeo:BAAALgAECgcJEwAAAA==.Cerberusalfa:BAACLgAFFH8IAAILAAMJ5iBYCQAnAQALAAMJ5iBYCQAnAQAuAAQKfzEAAgsACQnTJeEAAFEDAAsACQnTJeEAAFEDAAAA.',
Ch='Chaintazer:BAAALgADCgYJBgABLgAECgcJFwAVAO0cAA==.Chewbaca:BAAALgAECgEJAwAAAA==.Chickennuggi:BAABLgAECn8kAAIIAAYJRh9+RADMAQAIAAYJRh9+RADMAQAAAA==.Chiphoof:BAABLgAECn8WAAIWAAYJdBMPEgA0AQAWAAYJdBMPEgA0AQAAAA==.Chocofox:BAAALgAECgcJEQAAAA==.Chokemagic:BAAALgAECgEJAgAAAA==.Chopndot:BAAALgAECgEJBAAAAA==.Chozen:BAAALgADCgcJBwAAAA==.Chrill:BAAALgAECgUJDQAAAA==.',
Cl='Claraabun:BAAALgAECgUJBQABLgAFFAUJFAAPAN8TAA==.Clarabuns:BAACLgAFFH8UAAIPAAUJ3xM/DgB2AQAPAAUJ3xM/DgB2AQAuAAQKfxgAAw8ACQnGF2YlAPsBAA8ACQnGF2YlAPsBABAAAgmNDPDnAHcAAAAA.Clarasbuns:BAAALgADCgQJBAABLgAFFAUJFAAPAN8TAA==.Clawdragoon:BAECLgAFFH8PAAMXAAQJgQr0GQABAQAXAAQJgQr0GQABAQAFAAMJhAFJOACNAAAuAAQKfzAAAxcACAnVGW0UAG8CABcACAnVGW0UAG8CAAUABQlACN+bAJQAAAAA.',
Co='Coati:BAAALgADCgYJBgAAAA==.Colosie:BAAALgAECgYJEwAAAA==.Comegetpsalm:BAABLgAECn8zAAIPAAgJxxyUDgBjAgAPAAgJxxyUDgBjAgAAAA==.',
Cr='Creamsock:BAAALgAECgQJCQAAAA==.Creatlach:BAACLgAFFH8TAAIYAAUJDhwQDACXAQAYAAUJDhwQDACXAQAuAAQKfzcAAxgACAlPHScWAEUCABgACAlPHScWAEUCABkAAwlXE3BjALUAAAAA.Creech:BAAALgADCgIJAgAAAA==.Creeptoken:BAAALgAECgEJAQAAAA==.Crucifilth:BAAALgADCgYJDAAAAA==.Cryopathy:BAAALgAECgYJDgAAAA==.Crypty:BAABLgAECn8dAAMZAAkJggxSIgB8AQAZAAkJggxSIgB8AQAYAAUJrREiXQAWAQAAAA==.',
Cy='Cyaniidee:BAAALgADCgcJBwAAAA==.Cytherea:BAABLgAECn8aAAIQAAcJdQvnlwD5AAAQAAcJdQvnlwD5AAAAAA==.',
Da='Daddybod:BAABLgAECn8gAAIaAAkJjBKlFQDAAQAaAAkJjBKlFQDAAQAAAA==.Dalinek:BAAALgAECgUJBQAAAA==.Darktaynt:BAAALgAECgMJBQAAAA==.Darthfox:BAAALgAECgMJBQAAAA==.',
De='Deadsean:BAAALgAECgUJDAAAAA==.Deathtracker:BAAALgAECgcJDQAAAA==.Deathwarden:BAAALgAECgYJCwAAAA==.Deathñdk:BAAALgADCgEJAQAAAA==.Debuffed:BAAALgAECgEJAQAAAA==.Delathor:BAAALgAECgcJCwAAAA==.Demiloss:BAAALgADCgEJAQAAAA==.Demise:BAABLgAECn8fAAIIAAgJuR06MQCtAgAIAAgJuR06MQCtAgABLgAFFAMJBQANAFYJAA==.Demonclem:BAAALgAFFAIJAgAAAA==.Demonskinner:BAAALgADCgUJBQAAAA==.Denzo:BAAALgAECgMJAwAAAA==.Deoxyrybo:BAABLgAECn87AAMLAAkJ5RlZBwBqAgALAAkJ5RlZBwBqAgAMAAYJpwuViAAUAQAAAA==.Destructor:BAAALgAECgcJEwAAAA==.Devourera:BAAALgAECgYJEwAAAA==.',
Di='Died:BAAALgADCgMJAwAAAA==.Dilldobaggin:BAAALgADCgQJBAAAAA==.Dinopriest:BAABLgAECn8WAAICAAcJBxePGgCdAQACAAcJBxePGgCdAQAAAA==.Distia:BAAALgAECgYJBwAAAA==.Divinedragon:BAABLgAECn8jAAMCAAkJXhV6DwATAgACAAkJXhV6DwATAgADAAcJ5grnLgAoAQAAAA==.Dixoncider:BAAALgAECgQJBgAAAA==.',
Do='Doboy:BAAALgADCgIJAgAAAA==.Donmanuel:BAAALgADCgEJAQAAAA==.',
Dr='Drackaris:BAAALgADCgYJBgAAAA==.Drainbamage:BAAALgAECgMJAwAAAA==.Drakin:BAABLgAECn8jAAIQAAkJkxgRPAA0AgAQAAkJkxgRPAA0AgAAAA==.Dreya:BAABLgAECn8ZAAIbAAgJrB5yBwD2AQAbAAgJrB5yBwD2AQAAAA==.Dreyas:BAAALgADCgYJBgAAAA==.Drinkcoolaid:BAABLgAECn8VAAIYAAcJQBH7PABYAQAYAAcJQBH7PABYAQAAAA==.Dritzle:BAABLgAECn8aAAMcAAgJ/xTKIQDrAQAcAAgJ/xTKIQDrAQAGAAQJHgi5EwDEAAAAAA==.Droopapi:BAAALgAECgYJEQAAAA==.',
Du='Dutchman:BAACLgAFFH8UAAIdAAYJ3CN3AgD2AQAdAAYJ3CN3AgD2AQAuAAQKfxwAAh0ACAkNIWYIAAsDAB0ACAkNIWYIAAsDAAAA.',
Eh='Ehhmuh:BAAALgAECgYJCQAAAA==.Ehlumii:BAABLgAECn8UAAIEAAYJRSRvDgBvAgAEAAYJRSRvDgBvAgAAAA==.',
Ei='Eiffel:BAAALgADCgUJBQAAAA==.',
El='Eldrene:BAABLgAECn8uAAMIAAgJUx3AJABKAgAIAAgJUx3AJABKAgAeAAEJ7hOWHAA6AAAAAA==.Elethil:BAAALgADCgEJAQAAAA==.Elfstomper:BAAALgADCgcJCAAAAA==.Elitepaladin:BAABLgAECn8nAAIPAAkJGRbfIQAPAgAPAAkJGRbfIQAPAgAAAA==.Ellexi:BAAALgAECgYJDAAAAA==.Elyseia:BAABLgAECn8cAAIdAAgJ3wQYcgARAQAdAAgJ3wQYcgARAQAAAA==.',
Em='Empkin:BAAALgAECgcJEwAAAA==.',
En='Enof:BAAALgADCgIJAgAAAA==.Enpower:BAAALgADCgYJBgABLgAECggJJgAfAEMcAA==.',
Ep='Epicsause:BAAALgAECgEJAQAAAA==.',
Er='Erelor:BAAALgADCgMJAwAAAA==.',
Es='España:BAEBLgAECn8oAAQOAAkJTho9CgB2AgAOAAkJTho9CgB2AgAgAAQJUAssFAC3AAAKAAEJAACkOQEAAAAAAA==.Españamor:BAEALgAECgkJBgABLgAECgkJKAAOAE4aAA==.Essdeath:BAAALgADCgkJFwAAAA==.',
Fa='Farael:BAAALgAECgcJBAAAAA==.Farmerbrown:BAAALgAECgIJAwABLgAECggJIgAQAPMhAA==.Fatalmann:BAABLgAECn8WAAMTAAkJzA+ZFQCVAQATAAcJqA+ZFQCVAQASAAYJNg9NFQAqAQAAAA==.Fatalminn:BAAALgAECgUJCQAAAA==.Fathergob:BAAALgADCgEJAQAAAA==.Fatty:BAAALgADCgYJBgAAAA==.',
Fe='Fenty:BAAALgADCgEJAQAAAA==.Feralhorn:BAAALgAECgEJAQAAAA==.',
Fi='Fingerz:BAAALgADCgIJAgAAAA==.Fintan:BAAALgADCgEJAQAAAA==.',
Fl='Flarestrasz:BAAALgADCgUJCQAAAA==.Flexxar:BAAALgAECgEJAgAAAA==.Flèxion:BAACLgAFFH8JAAIKAAUJvh7PHgB7AQAKAAUJvh7PHgB7AQAuAAQKfygAAgoACAn/JP8RAJ4CAAoACAn/JP8RAJ4CAAAA.',
Fo='Foskin:BAAALgAECgEJAQABLgAECgcJFwAVAO0cAA==.',
Fr='Frassk:BAABLgAECn80AAMHAAgJuBVPDgANAQAHAAYJRxVPDgANAQAhAAQJZBEypQC0AAAAAA==.Freja:BAAALgADCgMJBgAAAA==.Froggystyle:BAAALgAECgUJDQAAAA==.Frostydru:BAABLgAECn8wAAIWAAgJfiFnBABnAgAWAAgJfiFnBABnAgAAAA==.Frozat:BAACLgAFFH8UAAISAAcJmRWXBQCdAQASAAcJmRWXBQCdAQAuAAQKfygAAxIACAkQI94CAO8CABIACAkQI94CAO8CAA0AAQmAEZ5eAEAAAAAA.Frösting:BAAALgADCgcJDgAAAA==.',
Fu='Furballieo:BAAALgADCgIJAgAAAA==.',
Ga='Galianem:BAAALgADCgMJAwAAAA==.Gamora:BAAALgAECgYJCQAAAA==.Gandon:BAAALgAECgQJBwAAAA==.Garbarn:BAABLgAECn8VAAIQAAkJ0g9kVACDAQAQAAkJ0g9kVACDAQAAAA==.Garonno:BAAALgADCgIJAgAAAA==.',
Ge='Gelystine:BAAALgADCgUJCgAAAA==.Geminirunes:BAAALgADCgYJBgABLgAECggJJgAfAEMcAA==.Germaine:BAAALgAECgQJBQAAAA==.',
Gh='Ghabi:BAAALgAECgYJBgAAAA==.Ghauri:BAAALgAECgMJBAAAAA==.',
Gi='Gia:BAABLgAECn8pAAIEAAgJwhmCDwBDAgAEAAgJwhmCDwBDAgAAAA==.',
Go='Gobx:BAAALgAECgUJBgAAAA==.Golgroth:BAAALgAECgYJEgAAAA==.Goodtimesm:BAAALgAECgYJBgAAAA==.Goodtymes:BAAALgAECgEJAQAAAA==.Gorearrow:BAABLgAECn8wAAMdAAkJVyLYCwDjAgAdAAkJVyLYCwDjAgAiAAIJVgdjegBZAAAAAA==.Goretaint:BAAALgAECgYJCgAAAA==.Gorgesh:BAAALgADCgQJBAAAAA==.Gothladriel:BAAALgAECgYJDAAAAA==.Gottamoo:BAAALgAECgkJEQAAAA==.',
Gr='Greenstank:BAAALgAECgEJAQABLgAECgUJDQAJAAAAAA==.Grimmtotem:BAAALgADCgQJBAAAAA==.Grrumpybear:BAABLgAECn83AAIUAAgJDB6lBQBTAgAUAAgJDB6lBQBTAgAAAA==.Grundal:BAAALgADCggJCAAAAA==.',
Gu='Gunafistya:BAAALgAFFAIJAgAAAA==.Guzzler:BAAALgAECgEJAQAAAA==.',
['Gú']='Gúildarts:BAAALgADCgEJAQAAAA==.',
Ha='Haannarr:BAAALgAECgIJAgAAAA==.Hairymoodini:BAAALgAECgEJAgAAAA==.Hajin:BAAALgAECgYJCgAAAA==.Hanky:BAAALgAECgQJBAAAAA==.Havòk:BAAALgAECggJBwAAAA==.Hawthorn:BAAALgAECgMJBQAAAA==.Hazyblades:BAAALgAECgEJAQAAAA==.',
He='Helacookie:BAAALgAECggJEwAAAA==.Heomors:BAAALgAECgEJAQAAAA==.Hexxan:BAAALgAECgUJEAAAAA==.',
Hi='Hifumi:BAAALgADCgQJBwAAAA==.Hisagu:BAAALgADCgIJAgABLgAECgYJDwAJAAAAAA==.Hiver:BAAALgAECgQJBQAAAA==.',
Ho='Holes:BAAALgADCgYJCAAAAA==.Holier:BAABLgAECn8wAAIQAAkJ6REbRACxAQAQAAkJ6REbRACxAQAAAA==.Hollows:BAAALgAECgQJBgAAAA==.Holyatrops:BAAALgAECgcJCAABLgAFFAYJGwAhAGcaAA==.Hopperstotem:BAAALgAECgIJAgAAAA==.Horuu:BAAALgAECgQJBgAAAA==.Hoyboii:BAAALgADCgYJBgAAAA==.',
Hu='Hulo:BAAALgAECgIJAgAAAA==.Humbled:BAAALgAECgQJBQAAAA==.Hunteress:BAAALgADCgYJBwAAAA==.Huntkoalas:BAAALgAECgMJAwABLgAFFAYJGQAXAB4ZAA==.Hurrdurr:BAAALgAECgEJAQAAAA==.',
['Hî']='Hîflax:BAAALgAECgEJAgAAAA==.',
['Hö']='Hölyców:BAAALgADCgQJBAAAAA==.',
Ic='Ichbinstark:BAAALgAECgEJBAAAAA==.',
Id='Idonttcare:BAAALgAECgMJAwAAAA==.',
Ig='Iggnignokt:BAAALgADCgYJBwAAAA==.',
Ih='Ihealnewbs:BAAALgADCgYJDwAAAA==.',
In='Infamus:BAAALgAECgQJCQAAAA==.Invysion:BAABLgAECn8uAAIDAAkJFxGwEQABAgADAAkJFxGwEQABAgAAAA==.',
Ir='Irri:BAAALgADCgUJBQAAAA==.',
Ja='Jaidess:BAAALgADCgcJFAAAAA==.',
Je='Jeanjean:BAAALgAECgcJCAAAAA==.Jeannjeann:BAAALgAECggJEgAAAA==.Jediknîght:BAAALgAECgYJBgAAAA==.Jeep:BAACLgAFFH8MAAIdAAQJnhtsGgBGAQAdAAQJnhtsGgBGAQAuAAQKfycAAh0ACAlAJVMEAEoDAB0ACAlAJVMEAEoDAAAA.Jellybea:BAABLgAECn8qAAMBAAkJbSExBAASAwABAAkJbSExBAASAwACAAIJCQx2UABmAAAAAA==.',
Ji='Jibalynne:BAAALgAECgQJBAAAAA==.Jida:BAAALgAECgEJAQAAAA==.Jiffypop:BAAALgAECgcJDAABLgAECgkJKgAVAJAaAA==.Jinwooaura:BAAALgADCgcJBwAAAA==.',
Jo='Johnnycakes:BAAALgADCgMJBQAAAA==.Jonsnowxd:BAAALgADCgYJBgAAAA==.',
Jr='Jrhnbr:BAAALgADCgMJAwAAAA==.',
Ju='Juggnut:BAAALgAECgcJEAAAAA==.Jump:BAAALgAECgQJCgAAAA==.Jurisdiction:BAABLgAECn8ZAAIQAAcJ2AvDewArAQAQAAcJ2AvDewArAQAAAA==.',
Jz='Jz:BAAALgAECgMJAwAAAA==.',
['Jì']='Jìnn:BAAALgAECgUJDwAAAA==.',
Ka='Kaan:BAABLgAECn8nAAIFAAcJhiFLEwCbAgAFAAcJhiFLEwCbAgAAAA==.Kadath:BAAALgADCgIJAwAAAA==.Kaeladín:BAAALgAECgUJCAAAAA==.Kagebouzu:BAAALgAECgYJDwAAAA==.Kahlan:BAAALgADCgcJCAABLgAECgYJCgAJAAAAAA==.Kamela:BAAALgAECgYJCAAAAA==.Karael:BAAALgAECgUJEQAAAA==.Karma:BAAALgAECgYJDgAAAA==.Kayliaa:BAAALgAECgkJAQAAAA==.Kazarke:BAAALgADCgcJGAAAAA==.',
Ke='Keho:BAABLgAECn8bAAMaAAcJlwkaMwD3AAAaAAcJcggaMwD3AAAfAAIJkg6maABqAAAAAA==.Kenalia:BAABLgAECn8mAAIEAAgJZRb6FgDuAQAEAAgJZRb6FgDuAQAAAA==.Keptalive:BAAALgADCgcJCgAAAA==.Kerzermern:BAAALgAFFAMJAwAAAA==.Kevic:BAAALgAECgcJBwAAAA==.',
Kh='Khamaelion:BAAALgADCgcJDgAAAA==.',
Ki='Kiara:BAABLgAECn8eAAIQAAgJMyBdIgCgAgAQAAgJMyBdIgCgAgAAAA==.Kiju:BAAALgADCgYJBgAAAA==.Killaban:BAACLgAFFH8FAAIVAAIJEhYNKgCcAAAVAAIJEhYNKgCcAAAuAAQKfzIAAxUACQklIFsMAF4CABUACQnhH1sMAF4CACMAAwkZGVMrAJoAAAAA.Killbydeath:BAAALgAECgEJAQAAAA==.Kimberlyhárt:BAABLgAECn8iAAMQAAgJ8yGgIQA7AgAQAAgJ8yGgIQA7AgAPAAEJpwMDfgAiAAAAAA==.Kissmydots:BAABLgAECn85AAIhAAgJ5x4QGgBNAgAhAAgJ5x4QGgBNAgAAAA==.Kitja:BAABLgAECn8oAAMBAAkJoxkKCgB8AgABAAgJaBwKCgB8AgADAAQJFw1PPgChAAAAAA==.Kitla:BAAALgADCgUJBQABLgAECgkJKAABAKMZAA==.',
Kl='Klukai:BAAALgADCgcJCwABLgAECgkJIAAFAPMdAA==.',
Kn='Kneed:BAAALgADCgYJBgAAAA==.',
Ko='Koala:BAAALgAECgQJBQABLgAFFAYJGQAXAB4ZAA==.Kohman:BAABLgAECn8aAAIhAAYJ5RTOfABiAQAhAAYJ5RTOfABiAQAAAA==.Konyani:BAAALgADCgUJAQAAAA==.',
Kp='Kpop:BAAALgAECgEJAQABLgAECgcJBwAJAAAAAA==.',
Kr='Kraeven:BAAALgADCgEJAQAAAA==.Kregerath:BAAALgADCgIJAgAAAA==.Krftpnk:BAACLgAFFH8SAAILAAQJhiWwAQCyAQALAAQJhiWwAQCyAQAuAAQKfyQAAwsACAmxIjcEADcDAAsACAmxIjcEADcDAAwAAQkAANj6AAAAAAAA.Krom:BAABLgAECn8qAAMVAAkJkBpnDQBRAgAVAAkJkBpnDQBRAgAjAAEJPQnEVAAqAAAAAA==.Kronas:BAABLgAECn8VAAIdAAgJ3RWHPgCRAQAdAAgJ3RWHPgCRAQAAAA==.Kronophyne:BAABLgAECn83AAIIAAkJ+B0gHwBnAgAIAAkJ+B0gHwBnAgAAAA==.Kronotality:BAABLgAECn87AAIOAAgJPyS7BACoAgAOAAgJPyS7BACoAgAAAA==.Kronotek:BAAALgAECgYJBgAAAA==.Kronotekken:BAAALgADCgYJBgAAAA==.',
Ku='Kurohitsugî:BAAALgAECgIJBAAAAA==.',
Ky='Kylorai:BAAALgAECgYJDwAAAA==.Kynbrochel:BAAALgAECgEJAQAAAA==.',
La='Laars:BAAALgAECgMJAwAAAA==.Laimaster:BAAALgAECgEJAQAAAA==.Lakiri:BAABLgAECn8qAAIbAAgJJxebCADUAQAbAAgJJxebCADUAQAAAA==.Landaeda:BAAALgAECgcJDgAAAA==.Lapsu:BAABLgAECn8fAAIfAAkJjRSqEgDaAQAfAAkJjRSqEgDaAQAAAA==.Lascivia:BAABLgAECn8kAAMVAAkJAB9QJgAnAgAVAAkJiBxQJgAnAgAkAAcJ+A8GIwDNAAAAAA==.Lawhanx:BAAALgADCgEJAQABLgAECggJJQAMALccAA==.Laylahh:BAAALgADCgMJBAAAAA==.Lazy:BAABLgAECn8WAAMhAAYJyRcpiQBHAQAhAAUJyRcpiQBHAQAHAAIJxQGEYQBLAAAAAA==.',
Le='Leademon:BAABLgAECn8xAAMMAAgJuB+sFwBHAgAMAAgJuB+sFwBHAgALAAIJTRrWWgB2AAAAAA==.Leadmin:BAAALgADCgMJBQABLgAECggJMQAMALgfAA==.Leadmln:BAAALgADCgcJBwABLgAECggJMQAMALgfAA==.Leftlane:BAABLgAECn8rAAIYAAgJ1iOXBAAnAwAYAAgJ1iOXBAAnAwAAAA==.Legato:BAAALgAECgcJCAABLgAFFAYJHQAYADggAA==.Lethalkrits:BAAALgAECgcJAgAAAA==.Leva:BAABLgAECn8gAAIFAAkJ8x3OEACHAgAFAAkJ8x3OEACHAgAAAA==.',
Li='Liberté:BAAALgADCgcJDQAAAA==.Lie:BAABLgAECn8qAAIcAAkJpRVVDAARAgAcAAkJpRVVDAARAgAAAA==.Lightsdown:BAAALgAECgYJBgAAAA==.Lilbeebs:BAAALgAECgkJEAAAAA==.Lileth:BAAALgAECgkJAgAAAA==.Lilflea:BAAALgAECggJEQAAAA==.Lilzuki:BAAALgAECgYJDgAAAA==.Lilïth:BAACLgAFFH8LAAIOAAUJ8B+/DQAmAQAOAAUJ8B+/DQAmAQAuAAQKfxsAAg4ABwmDJPIGAMICAA4ABwmDJPIGAMICAAAA.Linguine:BAAALgAECgEJAgABLgAFFAQJDQABAJAZAA==.Lisalisa:BAABLgAECn8mAAIYAAYJrxghOQBqAQAYAAYJrxghOQBqAQAAAA==.Livan:BAAALgAECgMJAwAAAA==.Livia:BAAALgAECgEJAQAAAA==.',
Lo='Lohzak:BAAALgAECgEJAQAAAA==.Lousier:BAAALgAECgEJAQAAAA==.',
Lu='Lularia:BAAALgADCgIJAgAAAA==.Lumii:BAAALgAECgYJBgABLgAECgYJFAAEAEUkAA==.Lunaa:BAAALgAECgYJBgAAAA==.Lurassa:BAAALgAECgYJDAAAAA==.',
Ly='Lyacon:BAAALgADCgQJBAABLgAECgkJFQAIAEEcAA==.',
['Lä']='Lä:BAEALgAECgcJBwAAAA==.',
Ma='Madrie:BAAALgAECgQJBAAAAA==.Maekar:BAABLgAECn8UAAITAAYJDAkZEQCxAAATAAYJDAkZEQCxAAAAAA==.Maellus:BAAALgAECgEJAQAAAA==.Maelstorm:BAAALgADCgIJAgAAAA==.Mageman:BAAALgADCgYJAgAAAA==.Magicmoo:BAAALgAECgEJAQABLgAECggJIgAQAPMhAA==.Maltis:BAAALgADCgcJCwAAAA==.Mananstuff:BAABLgAECn86AAIXAAkJrRBwFwC6AQAXAAkJrRBwFwC6AQAAAA==.Manaproblems:BAAALgADCgMJBAAAAA==.Marguerek:BAAALgADCgEJAQAAAA==.Marinara:BAAALgAECgYJCwABLgAECgYJDAAJAAAAAA==.Markamanimal:BAACLgAFFH8OAAIWAAQJiRU1AwBlAQAWAAQJiRU1AwBlAQAuAAQKfyUAAhYACAnfIYYDAPwCABYACAnfIYYDAPwCAAAA.Marnix:BAABLgAECn8VAAIZAAgJlhB1JABuAQAZAAgJlhB1JABuAQAAAA==.',
Md='Mdbeef:BAAALgAECgUJBQAAAA==.',
Me='Medikus:BAABLgAECn8hAAMYAAgJcBxqEwBdAgAYAAgJcBxqEwBdAgAZAAMJ3gmLWQB8AAAAAA==.Meesoomagi:BAAALgAECgYJBwAAAA==.Menil:BAABLgAECn8XAAMEAAgJwBtXFgAQAgAEAAcJJhpXFgAQAgAfAAQJcha0OQDKAAAAAA==.Merryl:BAAALgAECggJDgAAAA==.Meyounow:BAAALgAECgEJAgAAAA==.',
Mi='Midnye:BAAALgADCgYJBgAAAA==.Mike:BAEBLgAECn83AAMlAAkJZSQ1AAAvAwAlAAkJJiI1AAAvAwAIAAgJYyDtNwD3AQAAAA==.',
Mo='Mob:BAAALgADCgcJBwAAAA==.Mockra:BAABLgAECn82AAMIAAgJiSLhFwCRAgAIAAgJiSLhFwCRAgAeAAIJuBiqGgBCAAAAAA==.Monafae:BAAALgADCgUJBQAAAA==.Moohammered:BAAALgADCgUJCAAAAA==.Moolou:BAABLgAECn8hAAIRAAkJtR9IAwCYAgARAAkJtR9IAwCYAgAAAA==.Moosé:BAAALgAECgEJAQABLgAFFAgJIgAQAO8UAA==.Mootilator:BAAALgADCgYJBgAAAA==.Moraei:BAAALgADCgEJAQAAAA==.Mordew:BAAALgADCgUJBQABLgAECggJLQAKAGkkAA==.Morechie:BAABLgAECn8fAAImAAgJgxKLBwCLAQAmAAgJgxKLBwCLAQAAAA==.Morgatho:BAAALgADCgEJAgAAAA==.Mortiferon:BAABLgAECn8jAAIKAAkJ1xn6NwDZAQAKAAkJ1xn6NwDZAQAAAA==.',
Mu='Muhgunguh:BAAALgADCgYJBgAAAA==.Munnky:BAABLgAECn8fAAIEAAYJ+R9NGADgAQAEAAYJ+R9NGADgAQAAAA==.Murmaider:BAAALgADCgIJAgAAAA==.',
My='Mythrandere:BAAALgADCgcJCwAAAA==.',
['Má']='Mánflu:BAABLgAECn8rAAMjAAkJ5B4SAwDiAgAjAAkJ5B4SAwDiAgAVAAcJSRpSNADZAQAAAA==.',
['Mô']='Môrrigãn:BAAALgADCgMJAwAAAA==.',
['Mö']='Mörgänä:BAAALgADCgMJAwAAAA==.',
Na='Naissa:BAAALgAECgQJBgAAAA==.Nakanir:BAAALgAECgYJBgAAAA==.Nalfeign:BAAALgAECgQJBQAAAA==.Napa:BAAALgAECgQJBAABLgAFFAUJEgAYANoYAA==.Narn:BAABLgAECn83AAQTAAgJSB3RCQBCAgATAAcJrRjRCQBCAgANAAgJ8xeZFgDXAQASAAIJLQiEQQBgAAAAAA==.',
Ne='Nealite:BAAALgAECgkJBgAAAA==.Necrotion:BAAALgAECgYJEgAAAA==.Nei:BAAALgADCgEJAQAAAA==.Nerrisa:BAABLgAECn8iAAICAAkJERTfFADVAQACAAkJERTfFADVAQAAAA==.Nertt:BAAALgADCgYJBgABLgAECggJOQATAOYeAA==.Neublood:BAAALgAECgQJCAAAAA==.',
Ni='Nicodemus:BAAALgAECgYJBwAAAA==.',
No='Noblewarrior:BAACLgAFFH8ZAAIVAAYJox72BwB5AQAVAAYJox72BwB5AQAuAAQKfysAAhUACAmkJLEGALYCABUACAmkJLEGALYCAAAA.Noctilus:BAAALgAECgcJCQAAAA==.Nohkari:BAAALgADCgQJBAABLgAECgkJHgAhABwUAA==.Nooj:BAACLgAFFH8qAAMGAAgJkSIIAADrAgAGAAgJkSIIAADrAgAcAAYJiRQ8BwCLAQAuAAQKfx4AAwYACQl7ITsAAMMDAAYACQl7ITsAAMMDABwABgmFEpA6AEQBAAAA.Notakoala:BAACLgAFFH8ZAAIXAAYJHhlZBgCoAQAXAAYJHhlZBgCoAQAuAAQKfyIAAxcACAmuIlQNAMUCABcACAmuIlQNAMUCABQAAQk3EqE/ADUAAAAA.Nothnx:BAAALgAFFAEJAQAAAA==.Notoriouspat:BAABLgAECn8YAAIdAAUJyg+newDnAAAdAAUJyg+newDnAAAAAA==.Notsamadeath:BAAALgAFFAIJAgAAAA==.Novia:BAAALgAECgYJBgAAAA==.Noyber:BAAALgAECgMJAwAAAA==.Noydin:BAAALgAFFAEJAgAAAA==.',
['Nü']='Nüll:BAAALgAECggJDgAAAA==.',
Ob='Obern:BAABLgAECn8WAAInAAkJZhvUDAAVAgAnAAkJZhvUDAAVAgAAAA==.Oblïna:BAABLgAECn8WAAIEAAcJKQbRPwDRAAAEAAcJKQbRPwDRAAAAAA==.',
Od='Odiumaeterna:BAAALgADCgcJBwAAAA==.',
Of='Offensivé:BAAALgAECgMJBwAAAA==.',
On='Onetozerosix:BAABLgAECn8eAAIKAAkJ4he0QwCwAQAKAAkJ4he0QwCwAQAAAA==.Onsen:BAAALgADCgIJAgAAAA==.',
Oo='Oogak:BAAALgAECgUJBgAAAA==.Oomigig:BAAALgADCgUJBQAAAA==.',
Op='Opal:BAAALgAECgkJCQAAAA==.Opalily:BAAALgADCgYJBwAAAA==.Operation:BAAALgAECgQJCAAAAA==.',
Or='Orghrax:BAAALgADCgEJAQAAAA==.',
Os='Osteer:BAAALgAECgYJBgAAAA==.',
Ot='Otterjim:BAAALgADCgQJBAAAAA==.',
Pa='Pahaa:BAAALgAECgUJBQAAAA==.Pairadeez:BAAALgAECgYJCwAAAA==.Pajamabanana:BAAALgADCgIJAgAAAA==.Pandablaze:BAAALgAECgYJBwAAAA==.Panterarey:BAAALgADCgYJEAAAAA==.Papalego:BAABLgAECn8nAAIdAAgJeg1nQQCHAQAdAAgJeg1nQQCHAQAAAA==.Parakka:BAABLgAECn8kAAIYAAkJ8RE8IAD2AQAYAAkJ8RE8IAD2AQAAAA==.Patak:BAAALgADCgEJAQAAAA==.Pavle:BAAALgADCgcJCQAAAA==.Pawp:BAAALgAECgYJCQABLgAECggJHwABAMUSAA==.',
Pe='Pearagon:BAAALgAECgYJBwABLgAFFAUJEgAYANoYAA==.Pepsidew:BAAALgADCgcJCwAAAA==.Pepsisprite:BAABLgAECn8qAAIBAAgJWRiQEAAZAgABAAgJWRiQEAAZAgAAAA==.Pesky:BAABLgAECn8YAAIXAAYJ5Q+tLwAGAQAXAAYJ5Q+tLwAGAQAAAA==.',
Pf='Pfchanguz:BAAALgADCgcJDAAAAA==.',
Ph='Phdbeef:BAAALgAFFAIJBAABLgAFFAUJCwAOAPAfAA==.Phlemm:BAAALgAECgEJAQAAAA==.Phoivos:BAABLgAECn8VAAIIAAkJQRwKIQDvAgAIAAkJQRwKIQDvAgAAAA==.',
Pi='Picklez:BAABLgAECn8dAAIKAAcJsiHPJAAqAgAKAAcJsiHPJAAqAgAAAA==.Pissflizzle:BAABLgAECn8cAAIhAAcJeA+pcwAWAQAhAAcJeA+pcwAWAQAAAA==.',
Pl='Plaquenil:BAAALgADCgEJAQAAAA==.',
Po='Poison:BAAALgADCgEJAQAAAA==.Porkroaster:BAABLgAECn8aAAIIAAcJEQnFiwAlAQAIAAcJEQnFiwAlAQAAAA==.',
Pr='Praye:BAAALgAECgQJBAAAAA==.Priestop:BAAALgAECgEJAQAAAA==.',
Ps='Psyfarian:BAAALgADCgcJDQAAAA==.Psyop:BAAALgAECgEJAQABLgAECggJDQAJAAAAAA==.',
Qu='Quillswitch:BAAALgAECgEJAQAAAA==.',
Ra='Radduc:BAABLgAECn8ZAAMPAAYJKxifJwCAAQAPAAYJKxifJwCAAQAQAAEJlQY+RwEsAAAAAA==.Ragerade:BAAALgAECgQJBQAAAA==.Raidu:BAAALgAECgMJAwAAAA==.Ralpherion:BAAALgADCgIJAgAAAA==.Ranoa:BAAALgAECgQJCgAAAA==.Raphåel:BAAALgAFFAEJAQAAAA==.Ravioli:BAAALgAECgQJBgAAAA==.Razialum:BAAALgADCgYJBgAAAA==.Razorsteps:BAAALgAFFAcJBAAAAA==.Razzberry:BAAALgADCgYJDAAAAA==.',
Re='Rebrowth:BAAALgAECgUJDQAAAA==.Redren:BAAALgADCgIJAgAAAA==.Reegrets:BAAALgAECggJDQAAAA==.Reena:BAAALgADCgIJAwAAAA==.Regiplague:BAAALgAECgYJCwAAAA==.Regretty:BAAALgAECggJDQABLgAECggJDQAJAAAAAA==.Renthar:BAAALgADCgUJBQAAAA==.Renzdingo:BAAALgAECgkJDwAAAA==.Repete:BAAALgAECgUJDgAAAA==.Resyek:BAABLgAECn85AAIIAAgJOyQ0DwDOAgAIAAgJOyQ0DwDOAgAAAA==.Reverendgank:BAAALgAECgEJAQAAAA==.',
Rh='Rhaxanna:BAAALgADCgYJBgAAAA==.',
Ri='Rick:BAAALgAECgQJBAAAAA==.Riivan:BAABLgAECn8TAAIhAAcJiwuPawAoAQAhAAcJiwuPawAoAQAAAA==.Rini:BAAALgAECgUJBQABLgABCgYJCwAJAAAAAA==.Rishi:BAABLgAECn83AAIQAAgJBBUITACaAQAQAAgJBBUITACaAQAAAA==.Rivian:BAAALgADCgIJAgAAAA==.',
Ro='Robot:BAABLgAECn8eAAIEAAcJtQ8sLwBAAQAEAAcJtQ8sLwBAAQAAAA==.Rokmog:BAAALgADCgUJBQAAAA==.Rollinburn:BAAALgADCgYJCQAAAA==.Roxanol:BAAALgADCgEJAQABLgAECggJMwAPAMccAA==.',
Ru='Rumbrave:BAAALgAECgYJCwAAAA==.Rumtumtugger:BAAALgADCgkJCQAAAA==.',
['Rá']='Ráyune:BAAALgADCgcJBwAAAA==.',
Sa='Sackos:BAAALgAECgEJAQAAAA==.Sadpanda:BAAALgADCgUJCAAAAA==.Saffronspark:BAAALgADCgkJGQABLgAECgkJLgAfAMofAA==.Sainsei:BAAALgAECgUJCAAAAA==.Saith:BAAALgAECgEJBQAAAA==.Samasear:BAABLgAECn8UAAIVAAgJ0w8wMgDjAQAVAAgJ0w8wMgDjAQABLgAFFAUJGAAKAI0hAA==.Sandwitch:BAABLgAECn85AAMhAAgJtBmfKgDxAQAhAAgJtBmfKgDxAQAHAAIJmxB0UwB0AAAAAA==.Sargatana:BAABLgAECn8hAAIaAAkJIBZYEAD9AQAaAAkJIBZYEAD9AQAAAA==.Sars:BAABLgAECn8aAAMEAAcJ8CWoBQD3AgAEAAcJ8CWoBQD3AgAfAAMJGhNcQgCoAAAAAA==.Sauronxd:BAAALgAECgUJCAAAAA==.',
Sc='Scalion:BAABLgAECn8lAAMMAAgJtxzxHAAiAgAMAAgJtxzxHAAiAgALAAQJ+BG9SwDAAAAAAA==.Scarne:BAAALgADCggJCQAAAA==.Schrodinger:BAABLgAECn8XAAIRAAcJxQlxHQDSAAARAAcJxQlxHQDSAAAAAA==.',
Se='Selunee:BAAALgADCgEJAQAAAA==.Sepharad:BAAALgADCggJEgAAAA==.Septicflësh:BAAALgADCgEJAQAAAA==.Severum:BAABLgAECn8uAAIkAAgJaBugCQARAgAkAAgJaBugCQARAgAAAA==.',
Sh='Shadowtiger:BAABLgAECn8mAAIdAAgJOgsrRwBzAQAdAAgJOgsrRwBzAQAAAA==.Shadrad:BAABLgAECn8ZAAIQAAkJsiW8AwA5AwAQAAkJsiW8AwA5AwAAAA==.Shamanor:BAEALgAECgcJCAAAAA==.Shammoo:BAAALgAECgIJBAABLgAFFAgJIgAQAO8UAA==.Shantz:BAABLgAECn8iAAIOAAgJHhAGFgBiAQAOAAgJHhAGFgBiAQAAAA==.Shiban:BAAALgAECggJCAAAAA==.Shirtless:BAAALgAECggJEQAAAA==.Shockra:BAABLgAECn8dAAIZAAkJ4xdzFgDfAQAZAAkJ4xdzFgDfAQAAAA==.Shortbuss:BAAALgADCgYJEgAAAA==.',
Si='Sige:BAAALgADCgYJBgAAAA==.Sillygoose:BAAALgADCgkJDwAAAA==.Silverfox:BAAALgADCgMJAQABLgAECggJNgAIAIkiAA==.Silx:BAABLgAECn8VAAMDAAcJMBE8IQCJAQADAAcJMBE8IQCJAQACAAEJoBZEXQA/AAAAAA==.Simvastatin:BAAALgADCgQJBAAAAA==.Sinterdeath:BAAALgAECgIJAgAAAA==.',
Sk='Skik:BAAALgAECgUJBQAAAA==.Skulltide:BAAALgADCgcJCQAAAA==.',
Sl='Slaggz:BAAALgADCgQJBAAAAA==.Slamvoke:BAAALgAECgYJBgABLgAFFAUJDwAVAKwVAA==.Slaté:BAAALgAECgEJAQAAAA==.Slowrot:BAAALgAECgQJBAABLgAECggJIgAQAPMhAA==.Slâte:BAAALgAFFAEJAgAAAA==.',
Sm='Smiteasaurus:BAAALgAECgEJAQAAAA==.Smorthian:BAAALgAECgcJDQAAAA==.',
Sn='Snarll:BAAALgADCgEJAQAAAA==.Sniffinsteak:BAAALgAECgkJEwAAAA==.',
So='Somaliabiggs:BAAALgAECgYJCgAAAA==.Sorraba:BAAALgAECgQJBAAAAA==.Sorrabo:BAABLgAFFH8FAAIDAAMJmAPxKQB7AAADAAMJmAPxKQB7AAAAAA==.Soryan:BAAALgAFFAIJAgAAAA==.Sosalkin:BAAALgAECgcJEQAAAA==.Souls:BAACLgAFFH8NAAIhAAMJbCFPGQAnAQAhAAMJbCFPGQAnAQAuAAQKfxwABCEABwk8IyYXAMkCACEABwk8IyYXAMkCACYAAQkAAPIfAHIAAAcAAQm1GkhiAEoAAAAA.',
Sp='Spankenstine:BAABLgAECn8bAAMQAAkJJxYUMAD3AQAQAAkJJxYUMAD3AQAPAAUJowh+YwDuAAABLgABCgYJCwAJAAAAAA==.Spannky:BAAALgAECgUJBQABLgAECgYJHwAEAPkfAA==.',
Sq='Squishÿ:BAAALgAECgYJDwAAAA==.',
St='Starshriek:BAAALgADCgcJBwAAAA==.Stinkyfree:BAABLgAECn8cAAIaAAYJzBjoKAAuAQAaAAYJzBjoKAAuAQAAAA==.Stinkynatto:BAAALgADCgYJBgABLgAECgYJHAAaAMwYAA==.Stormcharred:BAABLgAECn8eAAIIAAgJ6SCgKADQAgAIAAgJ6SCgKADQAgAAAA==.Stormknight:BAAALgAECgQJBgAAAA==.Straka:BAABLgAECn8fAAIFAAkJERIZPgCrAQAFAAkJERIZPgCrAQAAAA==.',
Su='Suffers:BAAALgAECgEJAQAAAA==.Suneater:BAAALgAECgEJAgAAAA==.Sunmane:BAAALgADCgcJBwABLgAECgYJFgAWAHQTAA==.Supaheals:BAAALgAECgEJAQAAAA==.Superdruid:BAAALgADCgUJBQABLgAFFAYJEgAQAP0eAA==.Supermonks:BAAALgAECggJDAABLgAFFAYJEgAQAP0eAA==.Superpi:BAABLgAECn8ZAAIDAAcJFx4rDABWAgADAAcJFx4rDABWAgABLgAFFAYJEgAQAP0eAA==.Superret:BAACLgAFFH8SAAIQAAYJ/R7dEgBxAQAQAAYJ/R7dEgBxAQAuAAQKfyUAAxAACAkqI/gOABYDABAACAkqI/gOABYDAA8AAQn7FDlrAD4AAAAA.Superskeet:BAACLgAFFH8HAAIPAAMJtAtGIgDBAAAPAAMJtAtGIgDBAAAuAAQKfyUAAg8ACAl4F40XAP8BAA8ACAl4F40XAP8BAAAA.',
Sw='Swaggbag:BAAALgADCgEJAQAAAA==.Swiftia:BAABLgAECn8VAAMiAAYJlBZYOwBzAQAiAAYJjhRYOwBzAQAdAAUJAg2EiQDGAAAAAA==.Swiftybutt:BAAALgAECggJCgAAAA==.',
Sy='Sylphièl:BAACLgAFFH8KAAMGAAQJagJIBAAMAQAGAAQJagJIBAAMAQAoAAEJqQJiAgBEAAAuAAQKfygAAwYACAlHDvEHAIcBACgACAmbCq8EALkBAAYACAlwDfEHAIcBAAAA.Syncere:BAAALgAECgEJAQAAAA==.Synhunt:BAAALgADCgYJBwAAAA==.Syrene:BAAALgAECgMJBgAAAA==.',
Ta='Tandarì:BAACLgAFFH8PAAIQAAQJLRwCFQBpAQAQAAQJLRwCFQBpAQAuAAQKfyIAAhAACQmjHqoPABEDABAACQmjHqoPABEDAAAA.Tano:BAAALgAECgUJBwABLgAECggJNgAIAIkiAA==.Tanparo:BAAALgAECgMJAwAAAA==.Tarick:BAAALgAECgMJAwAAAA==.Tasty:BAAALgAECgQJCwAAAA==.Tawnii:BAAALgADCgcJEgAAAA==.Taírn:BAAALgAECgYJDwAAAA==.',
Te='Tehpredator:BAAALgAECgMJBQAAAA==.Teilin:BAACLgAFFH8dAAIYAAYJOCCxAwAZAgAYAAYJOCCxAwAZAgAuAAQKfyIAAhgACQmQI7MEACcDABgACQmQI7MEACcDAAAA.',
Th='Theaterthug:BAAALgADCgcJFQAAAA==.Thehulkster:BAAALgAECgMJAwAAAA==.Thetinman:BAAALgAECgEJAQAAAA==.Thevelo:BAAALgAECgIJAgABLgAECgYJDQAJAAAAAA==.Thewhole:BAAALgAFFAIJAQAAAA==.Theßigshot:BAABLgAECn8VAAIFAAYJICPAIgAyAgAFAAYJICPAIgAyAgAAAA==.Thoseheals:BAAALgADCgQJBAAAAA==.Thunderskeet:BAACLgAFFH8HAAIMAAMJrhi4NwD7AAAMAAMJrhi4NwD7AAAuAAQKfzUAAwwACQlCI84DACQDAAwACQlCI84DACQDAAsABwlYHRAUADICAAAA.Thundurus:BAACLgAFFH8IAAIZAAMJVROyHgDdAAAZAAMJVROyHgDdAAAuAAQKfyUAAhkACAm9FgUkAHEBABkACAm9FgUkAHEBAAAA.',
Ti='Timmayy:BAABLgAECn8kAAIhAAgJCBZ5OQAmAgAhAAgJCBZ5OQAmAgAAAA==.Tindrill:BAABLgAECn8aAAIjAAkJUSGUAwDKAgAjAAkJUSGUAwDKAgAAAA==.Tireiron:BAAALgADCgYJBgAAAA==.',
To='Tomraedisk:BAABLgAECn8XAAIVAAcJ7Rz+GQDPAQAVAAcJ7Rz+GQDPAQAAAA==.Totemagoat:BAACLgAFFH8VAAMZAAUJLQ8GFgAdAQAZAAUJLQ8GFgAdAQAYAAQJzxhEHQAZAQAuAAQKfzIAAxkACQkJHaQOADQCABkACAnQG6QOADQCABgACAlHFdgsANcBAAAA.Totemlyfine:BAABLgAECn8jAAMYAAcJ2yKKEAB6AgAYAAcJ2yKKEAB6AgAZAAEJ6hUacQA9AAAAAA==.Totesmugoats:BAAALgAECggJEgAAAA==.Toxicshock:BAAALgADCgEJAQAAAA==.',
Tr='Traprkeepr:BAAALgADCgcJDQAAAA==.Treechains:BAABLgAECn8WAAMYAAYJ8hfsNQB6AQAYAAYJ8hfsNQB6AQAZAAEJZQPtkQAlAAAAAA==.Treefist:BAAALgADCgYJBwAAAA==.Treeshield:BAAALgADCgYJBgAAAA==.Trickster:BAAALgAECgEJAQAAAA==.Truth:BAAALgADCgcJDQAAAA==.',
Tu='Turbobis:BAAALgAECgIJAgAAAA==.',
Tw='Twentyfour:BAABLgAECn8UAAIFAAcJhhDlXQA4AQAFAAcJhhDlXQA4AQAAAA==.Twigberry:BAAALgAECgUJCAAAAA==.',
Ty='Typeshxxt:BAAALgADCgEJAQAAAA==.Tytanea:BAAALgAECgMJBAAAAA==.',
['Tø']='Tøqa:BAAALgAFFAEJAQAAAA==.',
Uh='Uhnderstood:BAABLgAECn8mAAIEAAkJjh1qEABUAgAEAAkJjh1qEABUAgAAAA==.',
Un='Undeadmonks:BAABLgAECn82AAMaAAgJpBcdEgDmAQAaAAgJpBcdEgDmAQAfAAMJdgrEZQB2AAAAAA==.',
Va='Vahe:BAAALgAECgEJAQAAAA==.Vale:BAAALgAECgQJBAAAAA==.Valeshot:BAABLgAECn8jAAIdAAkJ/QluPwCxAQAdAAkJ/QluPwCxAQAAAA==.Valkillrie:BAAALgADCgcJBwAAAA==.Vall:BAAALgAECgYJCQAAAA==.Valssra:BAABLgAECn8XAAIIAAcJmAqQhgAvAQAIAAcJmAqQhgAvAQAAAA==.Vampiricvrus:BAAALgAECgQJBgAAAA==.',
Ve='Vedbow:BAACLgAFFH8QAAQnAAQJ0iFrAwCWAQAnAAQJ0iFrAwCWAQAdAAIJgw8AUQCTAAAiAAEJgA+6JwBNAAAuAAQKfxoABB0ACQnDIh4UAJUCAB0ACAmzIR4UAJUCACIABAnyHyc8AG4BACcAAwldIIsmABYBAAAA.Vedronas:BAAALgAECgcJEwAAAA==.Venlii:BAAALgADCgEJAQAAAA==.Verdict:BAAALgAECgUJBQAAAA==.Veritae:BAAALgADCgYJBgAAAA==.Vern:BAABLgAECn8YAAMDAAgJ+RefFwC9AQADAAgJ+RefFwC9AQACAAIJgwYoWQBWAAAAAA==.Vernaar:BAAALgAECgEJAQABLgAECggJGAADAPkXAA==.Vernah:BAABLgAECn8VAAIPAAgJ1RnNDgBgAgAPAAgJ1RnNDgBgAgABLgAECggJGAADAPkXAA==.Verybad:BAABLgAECn9EAAIIAAYJpRwgewDbAQAIAAYJpRwgewDbAQAAAA==.',
Vo='Voidify:BAAALgADCgEJAgAAAA==.Voodoodrood:BAAALgADCgIJAgAAAA==.',
['Vè']='Vèronique:BAAALgADCgYJBgAAAA==.',
Wa='Waamchifu:BAABLgAECn8rAAIaAAgJbCBsBwCLAgAaAAgJbCBsBwCLAgAAAA==.Wack:BAAALgADCgUJBgAAAA==.Waka:BAAALgADCgcJCwAAAA==.Waltersight:BAAALgAECgcJDAAAAA==.',
We='Wesker:BAAALgADCgYJBgAAAA==.Westavia:BAAALgADCgMJAwABLgAECggJIgAQAPMhAA==.Wewabear:BAAALgADCgQJBAAAAA==.',
Wh='Whateley:BAAALgAECgcJCgAAAA==.Whosthetänk:BAAALgAECgEJAQAAAA==.',
Wi='Wisebrownguy:BAABLgAECn8fAAIQAAgJGxvnKwAJAgAQAAgJGxvnKwAJAgABLgAECgcJFwAVAO0cAA==.',
Wo='Worgana:BAAALgAECgMJAwAAAA==.Wormchild:BAAALgADCgQJBAAAAA==.',
Wu='Wukòng:BAAALgADCgEJAQAAAA==.',
Xe='Xercuul:BAAALgAECgEJAQAAAA==.',
Xi='Xikar:BAAALgAECgQJCAAAAA==.',
Ye='Yeddy:BAAALgADCgcJBwAAAA==.Yel:BAAALgADCgYJCAAAAA==.',
Yo='Yoel:BAAALgADCgEJAQAAAA==.',
Yu='Yudah:BAACLgAFFH8HAAMnAAMJuRS5FADrAAAnAAMJDQ65FADrAAAdAAIJzxxuRACsAAAuAAQKfywABCcACAkSHb4OAPwBACcACAkZGb4OAPwBAB0ABwlgD9JkAB8BACIABQnjFaESAO4AAAAA.Yuta:BAAALgADCgcJBgAAAA==.',
Za='Zalrei:BAAALgADCgYJBgAAAA==.Zalupa:BAAALgAECgIJAgAAAA==.Zanghonghua:BAABLgAECn8uAAMfAAkJyh8oBQDEAgAfAAkJyh8oBQDEAgAEAAEJSRXWZAA+AAAAAA==.Zarinaria:BAABLgAECn8cAAIMAAYJ2Q7qfQAvAQAMAAYJ2Q7qfQAvAQAAAA==.',
Zh='Zhael:BAABLgAECn8bAAIMAAgJFRy2KQDaAQAMAAgJFRy2KQDaAQAAAA==.',
Zo='Zodstrike:BAABLgAECn8eAAMMAAgJwwQndwDeAAAMAAgJwwQndwDeAAALAAQJnwIXWACGAAAAAA==.Zomara:BAAALgAECgIJBwAAAA==.Zooboo:BAABLgAECn8WAAIVAAkJABe2GQDSAQAVAAkJABe2GQDSAQAAAA==.Zophie:BAAALgADCgEJAQAAAA==.',
['Är']='Ärcane:BAAALgAECgkJBgAAAA==.',
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
