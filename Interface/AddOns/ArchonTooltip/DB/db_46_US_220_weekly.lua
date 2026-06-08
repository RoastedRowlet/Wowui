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

local lookup = {'Mage-Frost','Priest-Holy','Priest-Discipline','Paladin-Retribution','Hunter-Marksmanship','Priest-Shadow','Monk-Brewmaster','Monk-Windwalker','Shaman-Restoration','Warrior-Fury','Druid-Balance','Druid-Restoration','Warlock-Affliction','Warrior-Protection','DemonHunter-Vengeance','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Frost','Hunter-BeastMastery','Unknown-Unknown','Monk-Mistweaver','Evoker-Preservation','DemonHunter-Havoc','DemonHunter-Devourer','Warlock-Destruction','Warlock-Demonology','Rogue-Subtlety','Warrior-Arms','Paladin-Holy','Druid-Feral','Druid-Guardian','Hunter-Survival','DeathKnight-Blood','Paladin-Protection','Shaman-Enhancement','Rogue-Assassination','Evoker-Devastation','Evoker-Augmentation','Rogue-Outlaw',}
local provider = {region='US',realm='Thunderhorn',name='US',type='weekly',zone=46,date='2026-06-07',data={Ab='Absynthe:BAAALgAECgYJDAAAAA==.Abysmal:BAAALgADCgYJBgABLgAECgkJIwABAEoOAA==.Abÿss:BAAALgAECgMJCAAAAA==.',
Ac='Achêrøn:BAAALgADCgcJBwAAAA==.Acoghai:BAAALgADCgcJDQAAAA==.',
Ad='Adoweld:BAAALgADCgcJBQAAAA==.Adøland:BAAALgADCgYJBgAAAA==.',
Ae='Aeliis:BAABLgAECn8lAAMCAAkJ5AyTKgBoAQACAAkJ5AyTKgBoAQADAAMJbQSdXAB1AAAAAA==.Aellart:BAAALgAECgEJAgAAAA==.Aeriona:BAABLgAECn81AAIEAAkJHxwaIQB5AgAEAAkJHxwaIQB5AgAAAA==.Aerosoul:BAAALgADCgEJAQAAAA==.',
Ag='Agamsi:BAABLgAECn8UAAIFAAgJcwtZFwDsAAAFAAgJcwtZFwDsAAAAAA==.',
Ai='Aine:BAABLgAECn8lAAMCAAgJhBfqGAD5AQACAAgJhBfqGAD5AQAGAAYJ6wA/WABcAAAAAA==.Ainek:BAAALgAECgUJBwAAAA==.Ainkor:BAAALgAECgYJCAABLgAFFAMJCgAHADsNAA==.',
Aj='Ajani:BAABLgAECn8VAAMHAAgJ7xrlFAAAAgAHAAgJ7xrlFAAAAgAIAAQJXghiWQCgAAAAAA==.',
Ak='Akyospirit:BAABLgAECn88AAIJAAkJGA0sQgCZAQAJAAkJGA0sQgCZAQAAAA==.Akyowindz:BAAALgAECgQJBAAAAA==.',
Al='Al:BAAALgAECgYJEAABLgAFFAMJBQAKAMoWAA==.Alava:BAAALgADCgEJAQAAAA==.Aliatra:BAABLgAECn9CAAMLAAkJxRLxGwDeAQALAAkJxRLxGwDeAQAMAAEJmgit6wAfAAAAAA==.Alinth:BAAALgAECgMJBQAAAA==.Almosthuman:BAAALgAECgYJCgAAAA==.Alpha:BAABLgAECn86AAIBAAkJoh12GwCvAgABAAkJoh12GwCvAgAAAA==.Alroy:BAAALgAECgkJDgAAAA==.Aluina:BAAALgAFFAEJAQAAAA==.Alustryelle:BAAALgADCgkJCQABLgAECgkJIwAMABQJAA==.Alykia:BAAALgADCgYJBgAAAA==.',
Am='Amamonk:BAABLgAECn9BAAMHAAkJnhiJFQD5AQAHAAkJDRWJFQD5AQAIAAUJviAwJgB5AQAAAA==.Amandara:BAAALgADCgUJBQAAAA==.Ammert:BAABLgAECn80AAINAAkJkhDgBwDfAQANAAkJkhDgBwDfAQAAAA==.Amonet:BAAALgADCgYJEQAAAA==.',
An='Anchovy:BAAALgAFFAMJBAABLgAFFAgJJQAOAJojAA==.Andou:BAAALgADCgcJBwAAAA==.Angeldracul:BAAALgADCgQJBwAAAA==.Angelove:BAAALgAECgQJDAAAAA==.Anglico:BAAALgAECgQJBQABLgAECgkJJwAPAMwgAA==.Angliko:BAAALgAECgUJCAABLgAECgkJJwAPAMwgAA==.Anglikoo:BAAALgADCggJCAABLgAECgkJJwAPAMwgAA==.Anomandaris:BAABLgAECn8eAAMQAAkJVBUdJQCzAQAQAAgJ4RYdJQCzAQAJAAEJTAZt0QArAAAAAA==.Anquan:BAABLgAECn8lAAIRAAcJVRtCSADjAQARAAcJVRtCSADjAQAAAA==.',
Ap='Apedemak:BAAALgAECgYJDAAAAA==.Aphobias:BAAALgAECgUJCwAAAA==.Aphradite:BAAALgADCgYJCwAAAA==.Apothica:BAAALgAECgcJCgAAAA==.Apothicc:BAABLgAECn8kAAMRAAgJVhamRADuAQARAAgJVhamRADuAQASAAEJAADuQQAAAAAAAA==.Appalonio:BAAALgADCgcJBQAAAA==.Appaur:BAAALgADCgEJAQAAAA==.Appolymi:BAABLgAECn8xAAITAAkJjwVUaQBlAQATAAkJjwVUaQBlAQAAAA==.Apraxia:BAAALgADCgUJBQAAAA==.Aprionos:BAABLgAECn82AAIBAAgJ7AWFpwArAQABAAgJ7AWFpwArAQAAAA==.',
Ar='Arakek:BAAALgADCgcJCAAAAA==.Arataena:BAAALgADCgkJFgAAAA==.Arceus:BAAALgAECgMJBQAAAA==.Archibald:BAAALgAECgIJAgAAAA==.Aredhël:BAAALgADCgYJDgAAAA==.Argentavis:BAAALgAECggJEgABLgAECggJEwAUAAAAAA==.Argobow:BAAALgAFFAEJAQAAAA==.Argonaut:BAAALgAFFAIJAwAAAA==.Arice:BAEALgAECgEJAQABLgAECgkJOQARAP0cAA==.Aristella:BAAALgADCgMJAwAAAA==.Arkken:BAABLgAECn8bAAIVAAcJ2iLqDQCxAgAVAAcJ2iLqDQCxAgABLgAECgkJRQADAJUjAA==.Artee:BAAALgAECgEJAQAAAA==.Artémis:BAABLgAECn8iAAITAAgJgRC6YwByAQATAAgJgRC6YwByAQAAAA==.',
As='Ascender:BAAALgAECgQJBAAAAA==.Ashadox:BAAALgAECgUJCgAAAA==.Asheritâ:BAAALgADCgcJBwAAAA==.Ashvalis:BAABLgAECn8cAAIWAAcJzSPFCQCaAgAWAAcJzSPFCQCaAgAAAA==.Asillyhunter:BAAALgADCgMJAwAAAA==.Asillypally:BAABLgAECn8kAAIEAAgJeBYaXgDJAQAEAAgJeBYaXgDJAQAAAA==.Askr:BAABLgAECn8qAAMTAAkJExHWOQDuAQATAAkJ6RDWOQDuAQAFAAYJnwpjHwCpAAAAAA==.Asphar:BAABLgAECn8vAAMTAAkJuiU+AwBYAwATAAkJuiU+AwBYAwAFAAMJChNUKwBhAAAAAA==.Asteroth:BAAALgAECgEJAQAAAA==.',
Au='Aung:BAACLgAFFH8PAAIXAAQJ6SIsBgCQAQAXAAQJ6SIsBgCQAQAuAAQKf0sAAxcACQkkJhwBAGwDABcACQkkJhwBAGwDABgAAQmNBnIfASIAAAAA.Auri:BAAALgADCgkJIQAAAA==.',
Av='Avatan:BAAALgAECgMJAwABLgAECgkJLgAKAKgNAA==.Avralis:BAAALgADCgMJAwABLgAECggJHQAYAEocAA==.',
Ax='Axex:BAAALgAECgkJDQAAAA==.',
Az='Azamii:BAABLgAECn88AAMQAAkJOSIMBQAGAwAQAAkJOSIMBQAGAwAJAAYJQRgUOwCVAQAAAA==.Azarion:BAABLgAECn84AAMZAAgJch2NCgCNAQAZAAcJnRuNCgCNAQAaAAYJlBm3XQCBAQAAAA==.Azill:BAACLgAFFH8UAAIIAAUJqhxXDABXAQAIAAUJqhxXDABXAQAuAAQKfyYAAggACAleHjMKANUCAAgACAleHjMKANUCAAAA.Azzrael:BAABLgAECn8qAAIOAAkJzBDSFADAAQAOAAkJzBDSFADAAQAAAA==.',
Ba='Baalalmerat:BAAALgAECgIJAgAAAA==.Bandi:BAAALgAECgYJDgAAAA==.Bartrak:BAACLgAFFH8JAAMGAAMJbAe+JQC2AAAGAAMJbAe+JQC2AAADAAIJNwrkOgB4AAAuAAQKfxsAAwYACQk/Ez4hALUBAAYACQk/Ez4hALUBAAMABQlsEaJWAJMAAAAA.',
Be='Bearfucius:BAAALgAECgkJEQAAAA==.Bearrific:BAABLgAECn8kAAIbAAkJahrODgAyAgAbAAkJahrODgAyAgAAAA==.Beawulf:BAAALgAECgQJBAAAAA==.Behomadra:BAAALgAECgkJCQAAAA==.Belista:BAAALgAECgQJBAAAAA==.Bethel:BAAALgADCgYJCAAAAA==.',
Bf='Bfresh:BAAALgADCgcJDgAAAA==.',
Bi='Bibidi:BAAALgAECgQJBAAAAA==.Billie:BAAALgADCgcJAgAAAA==.Billthekid:BAAALgAECgYJCwAAAA==.Billybobb:BAAALgAECgYJDgAAAA==.Biney:BAAALgAECgQJBAABLgAECgQJBQAUAAAAAA==.Binksy:BAACLgAFFH8TAAIKAAYJihNrEAByAQAKAAYJihNrEAByAQAuAAQKfykAAgoACQmLHMkNAOcCAAoACQmLHMkNAOcCAAAA.Biscuit:BAACLgAFFH8lAAIOAAgJmiMFAQAJAgAOAAgJmiMFAQAJAgAuAAQKfyIAAg4ACQkfJe4AAJYDAA4ACQkfJe4AAJYDAAAA.Bitcoìn:BAAALgAECgEJAgAAAA==.',
Bl='Blaam:BAAALgAECgQJEgAAAA==.Blazin:BAACLgAFFH8jAAIBAAYJ6BWTMQCSAQABAAYJ6BWTMQCSAQAuAAQKfzIAAgEACQmLHsgSAOQCAAEACQmLHsgSAOQCAAAA.Blep:BAAALgAECgYJCgAAAA==.Blgunc:BAAALgAECgkJEQAAAA==.Blinkzy:BAAALgAECgUJCQAAAA==.Blitzshot:BAAALgADCgEJAQABLgAECggJGAAEAMwQAA==.Bloui:BAAALgAECgQJCAAAAA==.Bluesummers:BAAALgADCgkJCQAAAA==.',
Bo='Boba:BAAALgAECgYJBgABLgAFFAgJJQAOAJojAA==.Bongrips:BAAALgADCgcJCQAAAA==.Boomboom:BAAALgAECgUJCAAAAA==.Borlok:BAAALgAFFAQJBQAAAQ==.',
Br='Brannigan:BAABLgAECn88AAIOAAkJFiTgAQAxAwAOAAkJFiTgAQAxAwAAAA==.Braulioo:BAAALgAFFAIJAgAAAA==.Breebbs:BAAALgAECgUJBQAAAA==.Briantu:BAABLgAECn8qAAMJAAkJNQWOfgDVAAAJAAgJ/QGOfgDVAAAQAAEJEATtrgAjAAAAAA==.Brickitphil:BAABLgAECn8VAAISAAcJShYKDACpAQASAAcJShYKDACpAQAAAA==.Briiz:BAAALgADCgkJDAAAAA==.Brlolock:BAAALgADCgkJJAAAAA==.Brollo:BAAALgADCgEJAQAAAA==.Brud:BAAALgADCgYJAwAAAA==.Brönwyn:BAAALgAECgMJCAAAAA==.',
Bu='Bubblegumdrp:BAAALgAECgMJAwAAAA==.Bubblicious:BAAALgADCgUJCQAAAA==.Buckets:BAAALgAECgcJEgABLgAECggJCgAUAAAAAA==.Budi:BAAALgADCgcJCAAAAA==.Bulldan:BAABLgAECn8mAAINAAgJBx4OBQAxAgANAAgJBx4OBQAxAgAAAA==.Bullvi:BAAALgAECgYJBgAAAA==.',
['Bä']='Bärkler:BAABLgAECn8cAAMcAAkJaSKiBADCAgAcAAkJaSKiBADCAgAOAAEJHBiRSwA+AAAAAA==.',
['Bé']='Béckley:BAAALgAECggJEgAAAA==.Béckléy:BAAALgAECgUJDQABLgAECggJEgAUAAAAAA==.',
Ca='Caatha:BAAALgAECgQJBAAAAA==.Caleanone:BAAALgAECgcJDwABLgAFFAMJBQAKAMoWAA==.Calel:BAAALgAECgkJEAAAAA==.Callox:BAACLgAFFH8FAAIKAAMJyhbqKwDvAAAKAAMJyhbqKwDvAAAuAAQKfysABAoACAkFHJ4nALgBAAoACAkhG54nALgBABwABQknG+0RAIIBAA4ABgllDPMsAMcAAAAA.Cantelope:BAAALgADCgYJBgAAAA==.Capslock:BAAALgAECgQJAwAAAA==.Cara:BAAALgADCgIJAgAAAA==.Carahail:BAACLgAFFH8OAAMMAAMJTAgYRQCdAAAMAAMJTAgYRQCdAAALAAEJ6wFFTwApAAAuAAQKfzIAAwwACQmYFIIhADQCAAwACQmYFIIhADQCAAsABQlvDTtQAL8AAAAA.Catriona:BAABLgAECn8iAAITAAkJgwoLWwCJAQATAAkJgwoLWwCJAQAAAA==.Cazmeer:BAAALgAECgYJEAAAAA==.',
Ce='Celés:BAAALgAECgUJBQAAAA==.',
Ch='Charcuterie:BAACLgAFFH8mAAIHAAgJPh3qBQAYAgAHAAgJPh3qBQAYAgAuAAQKfyAAAwcACQnYIVwJAPMCAAcACQnYIVwJAPMCAAgAAQlxHeB8AFAAAAAA.Chaír:BAAALgAECgEJBQAAAA==.Cheezeburg:BAAALgAECgcJBwABLgAECgkJHwAHAC4ZAA==.Cheezus:BAAALgAECgIJBAABLgAECgkJHwAHAC4ZAA==.Cherrbeår:BAAALgADCgcJBwAAAA==.Cherudim:BAACLgAFFH8FAAMZAAMJ4wsjDwCHAAAaAAMJ4wumeQDDAAAZAAIJrwIjDwCHAAAuAAQKfyYAAxkACAkiF44JACcCABkACAmBFY4JACcCABoACAl3FBlVAJcBAAAA.Chillainkor:BAACLgAFFH8KAAIHAAMJOw18OAC6AAAHAAMJOw18OAC6AAAuAAQKfykAAgcACQk7Fq4XAOMBAAcACQk7Fq4XAOMBAAAA.Chillidán:BAABLgAECn8eAAIYAAkJLAV1igD/AAAYAAkJLAV1igD/AAAAAA==.Chippmagi:BAABLgAECn8gAAIBAAgJ9Ro8UQDjAQABAAgJ9Ro8UQDjAQAAAA==.Chippndots:BAAALgAECgYJDAABLgAECggJIAABAPUaAA==.Chirp:BAAALgAECgEJAQAAAA==.Chives:BAAALgAECgQJBAAAAA==.Choggie:BAACLgAFFH8KAAIdAAMJExRMKADaAAAdAAMJExRMKADaAAAuAAQKfz4AAh0ACQl2INwEAEADAB0ACQl2INwEAEADAAAA.Chronocolter:BAAALgADCgMJAwAAAA==.Chronosaren:BAABLgAECn8UAAIBAAkJyxErVADaAQABAAkJyxErVADaAQAAAA==.Chåir:BAAALgAECgEJAgAAAA==.',
Ci='Cinterax:BAAALgAECgIJAgABLgAECgkJPAAOABYkAA==.',
Cj='Cjrej:BAABLgAECn85AAIBAAkJKhBoTwDoAQABAAkJKhBoTwDoAQAAAA==.',
Cl='Claytonis:BAAALgAECgEJAQAAAA==.Cloudnine:BAAALgAECgQJBAAAAA==.',
Co='Colterr:BAAALgADCgEJAQAAAA==.Cons:BAABLgAECn8rAAQDAAkJ4RbiFQAfAgADAAkJlBXiFQAfAgACAAMJ8QrYZQCWAAAGAAEJ+xLsfgAzAAAAAA==.Corellon:BAABLgAECn8rAAITAAkJnRv0KQAsAgATAAkJnRv0KQAsAgAAAA==.Costcohotdog:BAABLgAFFH8KAAMHAAMJLR1IGACsAAAHAAMJLR1IGACsAAAVAAEJOQBpGgAYAAABLgAFFAgJJQAOAJojAA==.Cougarclaws:BAAALgAECgUJCQAAAA==.',
Cr='Craftsman:BAAALgADCgUJBQAAAA==.Craigchrist:BAAALgAECgYJBgAAAA==.Cranee:BAABLgAECn83AAIaAAkJZhTOMAAPAgAaAAkJZhTOMAAPAgAAAA==.Cranium:BAAALgAECgUJCAAAAA==.Crazytasty:BAABLgAECn8mAAITAAgJXyIUGwB4AgATAAgJXyIUGwB4AgAAAA==.Crumbo:BAAALgAECgYJBgAAAA==.Cryoburn:BAABLgAECn8fAAIBAAgJWB1rWAAwAgABAAgJWB1rWAAwAgAAAA==.Cryoshock:BAABLgAFFH8HAAIQAAMJwBYtLgDMAAAQAAMJwBYtLgDMAAAAAA==.',
Cu='Cutty:BAAALgAECgUJBgAAAA==.',
['Cø']='Cøns:BAAALgAECgYJCgAAAA==.',
Da='Daario:BAABLgAECn8TAAIYAAcJsB+pNQAhAgAYAAcJsB+pNQAhAgAAAA==.Dabare:BAAALgADCgUJAQAAAA==.Dabora:BAAALgAECgEJAQABLgAECgkJLAAeAAwfAA==.Dabßod:BAAALgAECgQJBAAAAA==.Dabûra:BAABLgAECn8sAAQeAAkJDB+GCAA2AgAeAAgJTB2GCAA2AgALAAYJTR6YQQD6AAAfAAcJehAuLgDjAAAAAA==.Daenerys:BAAALgAECgIJBgAAAA==.Dahouse:BAAALgADCgQJAwAAAA==.Dahpeht:BAAALgADCgkJEwAAAA==.Damda:BAAALgADCgIJAgAAAA==.Dandypooh:BAAALgAECgYJBgABLgAECgcJDQAUAAAAAA==.Danksamdi:BAAALgAECgEJAQAAAA==.Dante:BAAALgAECgcJCwAAAA==.Darige:BAAALgAECgIJAgAAAA==.Darim:BAAALgAECgYJBgABLgAECgkJKQABAFwaAA==.Darrow:BAAALgAECggJCAAAAA==.Darthspawn:BAABLgAECn8iAAIRAAcJcwzUlQA1AQARAAcJcwzUlQA1AQAAAA==.Daryl:BAAALgAECgQJBAAAAA==.Daryn:BAAALgAECgQJBAAAAA==.Davidbowy:BAABLgAECn8ZAAMgAAgJsA3hKgBHAQAgAAcJ7wjhKgBHAQATAAcJYQ4zhAArAQABLgAECgYJBwAUAAAAAA==.',
De='Deathnstuf:BAAALgAECgQJBgAAAA==.Deathollow:BAAALgAECgEJBAAAAA==.Delver:BAAALgADCgYJBgABLgAECgkJKQABAFwaAA==.Demai:BAAALgAECggJCQAAAA==.Demina:BAAALgAECgQJBgABLgAECggJHQAYAEocAA==.Demonainkor:BAAALgAECgYJBgABLgAFFAMJCgAHADsNAA==.Demonicfury:BAAALgAECgYJBwAAAA==.Demonthrall:BAAALgAECgEJAQAAAA==.Dencity:BAABLgAECn88AAMDAAkJshdnEQBSAgADAAkJUhZnEQBSAgACAAYJbxeQNgAYAQAAAA==.Dendwran:BAAALgAECgkJCQAAAA==.Desden:BAABLgAECn88AAIfAAkJ5BLMEgC0AQAfAAkJ5BLMEgC0AQAAAA==.Destined:BAAALgAECgYJBwAAAA==.Devianchi:BAABLgAECn8nAAMVAAgJ+B+FCQC5AgAVAAgJ+B+FCQC5AgAIAAcJIh9rFwDtAQABLgAECgkJFwAdAHcZAA==.Devitodevour:BAABLgAECn8hAAMaAAgJPRszPgDdAQAaAAgJmxkzPgDdAQAZAAMJXBkENQDiAAAAAA==.',
Dg='Dgbugs:BAACLgAFFH8KAAIRAAMJoCIYiADoAAARAAMJoCIYiADoAAAuAAQKfzIAAhEACAk9I1slAGgCABEACAk9I1slAGgCAAAA.',
Dh='Dhbert:BAABLgAECn8sAAIhAAkJ5xEwFQC5AQAhAAkJ5xEwFQC5AQAAAA==.Dhomeli:BAAALgAECgQJBQAAAA==.',
Di='Dirtchez:BAAALgAECgIJAwAAAA==.Disastrophy:BAAALgAECgYJEQABLgAECgcJCAAUAAAAAA==.Disturbed:BAABLgAECn8/AAQNAAkJ4yHdAAANAwANAAkJsCHdAAANAwAaAAgJNRskJQBEAgAZAAEJAADbYgBJAAAAAA==.Disturbio:BAAALgAECgEJAQABLgAECgkJPwANAOMhAA==.Divinepsycho:BAAALgADCgcJBwAAAA==.Divitiacus:BAAALgAECgYJBgAAAA==.',
Dj='Djowio:BAAALgADCgYJBgABLgAECggJIwAaABoiAA==.',
Dk='Dknightresh:BAAALgAECgcJBwABLgAECgcJJwAKAH0SAA==.',
Dm='Dmz:BAAALgADCgUJBgAAAA==.',
Do='Docen:BAAALgADCgkJCQAAAA==.Domfromgears:BAAALgAECgQJCQAAAA==.Dominance:BAAALgAECgEJAQAAAA==.Doomgaze:BAAALgADCgMJAQAAAA==.Dorc:BAAALgAECgMJBQAAAA==.Dotyou:BAAALgAECgIJAgAAAA==.Doudouzz:BAAALgAECgQJDQAAAA==.',
Dr='Dracthor:BAAALgADCgQJBAAAAA==.Draejin:BAAALgAECgkJDwAAAA==.Dragonfist:BAAALgADCgcJBwAAAA==.Dragonlore:BAAALgAFFAEJAQAAAA==.Dragthyr:BAAALgAECgUJCgAAAA==.Dramûl:BAABLgAECn8dAAITAAgJcRizSwC0AQATAAgJcRizSwC0AQAAAA==.Dreadedmonk:BAAALgAECgEJAgAAAA==.Druiaier:BAAALgADCgYJCQAAAA==.Druidibrume:BAAALgAECgMJDAAAAA==.Druknatsu:BAAALgAECgcJDAAAAA==.Drunkdragon:BAABLgAECn8UAAIIAAgJRRLpGwD9AQAIAAgJRRLpGwD9AQAAAA==.Drwhodunnit:BAAALgAECgMJAwAAAA==.',
Du='Dubbzilla:BAAALgAECgEJAQAAAA==.Dudedruid:BAAALgADCgUJBQAAAA==.Duncán:BAABLgAFFH8IAAMEAAUJ+Rs7LABMAQAEAAUJ+Rs7LABMAQAiAAEJoBUEFgA7AAABLgAFFAUJCgAJAHUjAA==.Dustyknight:BAABLgAECn8mAAIhAAkJeAyjHABpAQAhAAkJeAyjHABpAQAAAA==.',
Dw='Dwell:BAAALgADCgkJJAAAAA==.',
Dy='Dyavola:BAAALgAECgUJBQAAAA==.',
Ea='Earthquack:BAAALgAECgUJBQABLgAECggJGwAiADMVAA==.',
Ed='Edge:BAABLgAECn8eAAIJAAgJShWSMwDYAQAJAAgJShWSMwDYAQAAAA==.',
Ee='Eelenna:BAABLgAECn8ZAAMjAAkJLhxgBgCSAgAjAAkJLhxgBgCSAgAQAAUJwRBnUwD4AAABLgAFFAQJDQASAMMTAA==.',
El='Elamlock:BAAALgADCgYJCwAAAA==.Eleathe:BAAALgAFFAQJBAABLgAECggJHQAYAEocAA==.Eleros:BAABLgAECn8wAAIYAAkJsB/NDwC8AgAYAAkJsB/NDwC8AgAAAA==.Elicio:BAAALgAECgYJEAAAAA==.Ellysial:BAAALgADCgUJBQAAAA==.Elphinia:BAABLgAECn8zAAMbAAkJqxkvEAAhAgAbAAkJqxkvEAAhAgAkAAEJ4BFlIAAxAAABLgAFFAQJBwAQAIYMAA==.Elreÿ:BAAALgADCgEJAQAAAA==.Elyas:BAAALgAECgIJAgAAAA==.',
Em='Emberwrath:BAAALgADCgMJAwAAAA==.Emosdnem:BAAALgAECgQJBQAAAA==.Emt:BAAALgAECgQJBAAAAA==.',
En='Endarial:BAAALgAECgUJCQAAAA==.Enoki:BAACLgAFFH8QAAIJAAUJlRfsGACHAQAJAAUJlRfsGACHAQAuAAQKfxUAAwkACQkuHAYbAEACAAkACQkuHAYbAEACABAAAgl8HMhpAJwAAAEuAAUUCAkgAAwAuxwA.',
Er='Eraduckated:BAAALgAECgYJCAABLgAECggJGwAiADMVAA==.Erah:BAAALgADCgUJDQAAAA==.',
Es='Esco:BAAALgADCgMJAwAAAA==.Esile:BAAALgAECgQJBAABLgAECgkJPAALANkRAA==.',
Et='Eternalnow:BAAALgADCgEJAQAAAA==.',
Ev='Evelith:BAAALgADCgYJBgAAAA==.Everlife:BAABLgAECn8UAAIDAAcJRRPbIwCjAQADAAcJRRPbIwCjAQAAAA==.',
Ex='Exemptt:BAAALgAECgkJBQAAAA==.Exo:BAAALgADCgkJDwAAAA==.',
Fa='Falconpunch:BAAALgAECgYJCwAAAA==.Farnesë:BAAALgADCgUJBwABLgADCgcJBwAUAAAAAA==.Fauzzie:BAAALgAECgIJAgAAAA==.Fayrel:BAAALgAECgYJBwAAAA==.',
Fe='Fedders:BAACLgAFFH8GAAIEAAIJFB0eeACsAAAEAAIJFB0eeACsAAAuAAQKfykAAgQACQlGJoYHAFsDAAQACQlGJoYHAFsDAAAA.Felaids:BAACLgAFFH8VAAMaAAUJkBN0XQD/AAAaAAUJ+A90XQD/AAANAAEJSBAsIwBKAAAuAAQKfywAAxoACQmMGlsqACoCABoACAmMGlsqACoCABkAAwkSCLpEAKIAAAAA.Felimonk:BAAALgAECgQJBAABLgABCgQJBQAUAAAAAA==.Felpecs:BAAALgAECggJDgAAAA==.Fero:BAAALgAECgUJBQAAAA==.Feyda:BAABLgAECn8pAAIBAAkJ7wdOdgCHAQABAAkJ7wdOdgCHAQAAAA==.',
Fi='Fillon:BAACLgAFFH8IAAIEAAQJPxtQJwBbAQAEAAQJPxtQJwBbAQAuAAQKfzMAAgQACQmxJRkMAP0CAAQACQmxJRkMAP0CAAAA.Fionas:BAAALgADCgQJBAAAAA==.Firerybush:BAAALgAECgYJBwABLgAFFAMJBQAKAFoUAA==.Firessar:BAAALgAECgcJDAAAAA==.Firexcracker:BAAALgAECgMJAwAAAA==.Fishfood:BAABLgAECn88AAISAAkJIxVTBwAUAgASAAkJIxVTBwAUAgAAAA==.Fishlover:BAAALgADCgUJBQAAAA==.Fixer:BAAALgAECgUJCQAAAA==.',
Fk='Fk:BAAALgAFFAMJAwABLgAFFAUJCgAJAHUjAA==.',
Fo='Foe:BAEALgAECggJEwAAAA==.Folkvar:BAAALgADCgcJDAAAAA==.',
Fr='Frankngibbon:BAAALgADCgYJBgAAAA==.Frimm:BAAALgAECggJDgAAAA==.Frimthemage:BAACLgAFFH8LAAIBAAQJrgwMYQAgAQABAAQJrgwMYQAgAQAuAAQKfzEAAgEACQlDIBMlAIECAAEACQlDIBMlAIECAAAA.Frostmaster:BAABLgAECn8bAAIBAAcJOhyPVwDRAQABAAcJOhyPVwDRAQAAAA==.',
Fu='Funbunz:BAAALgAECgcJDAAAAA==.',
['Fí']='Fízban:BAAALgAECgIJBAAAAA==.',
['Fø']='Førd:BAACLgAFFH8MAAMlAAUJggpABQAKAQAlAAQJFQxABQAKAQAmAAMJGwf8QgCvAAAuAAQKfy8ABCUACAmQHRoLACoCACUABwlLGhoLACoCACYABwlOGSUkAJwBABYAAwkIAok3AD0AAAAA.',
Ga='Gammon:BAABLgAECn8wAAMQAAkJaB1kDACUAgAQAAkJaB1kDACUAgAJAAcJCRyzIgAyAgAAAA==.Gangrene:BAABLgAECn8yAAMRAAkJnxPCUADLAQARAAkJnxPCUADLAQAhAAgJCQvxKgD4AAAAAA==.Gary:BAAALgAECgQJCgAAAA==.Garzhvog:BAAALgAECgIJAgAAAA==.Gash:BAAALgAECgMJAwAAAA==.Gaspasser:BAABLgAECn8xAAMkAAkJrhyEAgClAgAkAAkJQhyEAgClAgAbAAEJphWKVABCAAAAAA==.Gaviin:BAABLgAECn84AAIkAAkJGCFPAgCwAgAkAAkJGCFPAgCwAgAAAA==.',
Ge='Gearador:BAAALgADCgcJAQAAAA==.Geisten:BAAALgAECgYJEwAAAA==.Genovia:BAAALgADCgIJAgABLgAECggJEwAUAAAAAA==.Gerhart:BAABLgAECn8sAAQPAAkJSxlICADlAQAPAAkJ6hRICADlAQAYAAcJxBm/WwBqAQAXAAMJQxC5TgBpAAAAAA==.Getcarried:BAAALgADCgMJAwABLgAFFAYJIwABAOgVAA==.Getty:BAAALgAECgcJEgAAAA==.',
Gf='Gfforgold:BAAALgADCgIJAgAAAA==.',
Gh='Ghosthunterx:BAAALgADCgEJAwAAAA==.Ghouldana:BAAALgADCgYJBgAAAA==.',
Gi='Gibbthok:BAAALgADCggJCAAAAA==.Gigachode:BAAALgAECgEJAwAAAA==.Gigarius:BAABLgAECn8iAAMiAAkJSSQZAgAQAwAiAAkJSSQZAgAQAwAEAAQJOBvxxwDyAAAAAA==.Gigglesworth:BAAALgAECgYJBgAAAA==.Gilamonster:BAAALgAECgYJCgAAAA==.',
Gl='Gladllimbo:BAAALgADCgEJAQAAAA==.Gleiten:BAAALgADCgMJAwAAAA==.Glonkins:BAABLgAECn8nAAQTAAkJWB+2DQDbAgATAAkJWB+2DQDbAgAgAAQJ9RRAMQAdAQAFAAEJAACvRQAAAAAAAA==.Glynden:BAAALgADCgEJAQAAAA==.',
Go='Goncor:BAACLgAFFH8NAAISAAQJwxNiDAAiAQASAAQJwxNiDAAiAQAuAAQKfykAAxIACQnkIPMDAI0CABIACQmYIPMDAI0CACEABQk+I/0ZAIUBAAAA.Gonnosuke:BAABLgAECn8UAAIEAAcJjgmjswAPAQAEAAcJjgmjswAPAQAAAA==.Gooseberry:BAAALgAECgEJAQAAAA==.Goosë:BAAALgADCgcJBwAAAA==.Gorrelord:BAAALgADCgEJAQABLgAFFAYJIwABAOgVAA==.Gortar:BAAALgADCgEJAQAAAA==.',
Gr='Granolah:BAAALgADCgcJCwABLgAECgkJLAAeAAwfAA==.Griffmonk:BAABLgAECn88AAIVAAkJCRvnEwBsAgAVAAkJCRvnEwBsAgAAAA==.Grumpydaemon:BAAALgAECgMJAwABLgAECgkJNwABAOsfAA==.Grumpymage:BAABLgAECn83AAIBAAkJ6x8FGQC9AgABAAkJ6x8FGQC9AgAAAA==.',
Gu='Gussy:BAAALgAECgQJBAABLgAECggJCgAUAAAAAA==.',
Ha='Hafsac:BAAALgAECgMJAwAAAA==.Halaranth:BAAALgAECgIJAgAAAA==.Hamasakura:BAAALgAECgYJBgAAAA==.Hanya:BAAALgAECgIJAgAAAA==.Hara:BAABLgAECn8aAAIMAAYJPRooQgCAAQAMAAYJPRooQgCAAQAAAA==.Hardlyknower:BAAALgADCgIJAgAAAA==.Hardord:BAABLgAECn8nAAIbAAgJuBAbHwCQAQAbAAgJuBAbHwCQAQAAAA==.Harrydotter:BAAALgAECgIJAgAAAA==.Haryle:BAAALgAECgUJCgAAAA==.Hayanne:BAABLgAECn84AAIOAAkJXxyQCABmAgAOAAkJXxyQCABmAgAAAA==.',
He='Healchucky:BAAALgAECgYJDQAAAA==.Healfire:BAAALgADCgYJBwAAAA==.Healisha:BAAALgAECgYJEAAAAA==.Healzjoogewd:BAAALgAECgEJAQAAAA==.Heina:BAAALgAECgYJBgAAAA==.Hershall:BAAALgAECgUJBQABLgAFFAQJDwAXAOkiAA==.',
Hi='Hitnrun:BAAALgAECgMJAwAAAA==.',
Ho='Hochunk:BAACLgAFFH8GAAMDAAIJ1AgYPABzAAADAAIJ1AgYPABzAAACAAEJ3wHQOAAmAAAuAAQKfysAAwMACQnfFOASAEECAAMACQn4E+ASAEECAAIACQm6CR07AE4BAAAA.Hochunks:BAAALgAECgYJDQAAAA==.Holdenger:BAAALgADCgQJBAAAAA==.Holikow:BAABLgAECn8YAAIEAAkJnxDgaACTAQAEAAkJnxDgaACTAQAAAA==.Holyherpies:BAAALgAECgYJBgAAAA==.Holyllama:BAAALgADCgcJBwAAAA==.Holymousey:BAABLgAECn8fAAIdAAkJjRHnJQDQAQAdAAkJjRHnJQDQAQAAAA==.Holysnake:BAAALgAECgQJBAAAAA==.Holytady:BAAALgADCgcJDQAAAA==.Holytudd:BAABLgAECn8gAAIEAAgJixSYgABjAQAEAAgJixSYgABjAQAAAA==.Honeybun:BAAALgADCgQJAgAAAA==.Honorlife:BAABLgAECn8xAAIJAAgJDhtuHgBPAgAJAAgJDhtuHgBPAgAAAA==.Hopeudie:BAAALgAECgUJBgABLgAFFAUJCgAJAHUjAA==.Horata:BAAALgAECgMJAwAAAA==.Hormuz:BAAALgADCgcJCwAAAA==.Hotelcali:BAAALgADCgkJCQAAAA==.',
Hu='Huckcold:BAAALgAECgcJDwAAAA==.Hugehands:BAAALgAECgUJBwAAAA==.Hughass:BAAALgADCgEJAQAAAA==.Hurano:BAAALgAECgYJCAAAAA==.',
Hy='Hyperious:BAAALgAECggJCAAAAA==.',
['Hâ']='Hârley:BAABLgAECn87AAIMAAkJ+BsUFwCGAgAMAAkJ+BsUFwCGAgAAAA==.',
['Hí']='Híram:BAABLgAECn8mAAIEAAgJahSFcgB/AQAEAAgJahSFcgB/AQAAAA==.',
Id='Idyllwild:BAAALgAECgEJBAAAAA==.',
Ih='Ihsan:BAABLgAECn82AAIEAAkJExaDNwAZAgAEAAkJExaDNwAZAgAAAA==.',
Il='Ilharess:BAACLgAFFH8NAAIBAAQJDg7hXAAoAQABAAQJDg7hXAAoAQAuAAQKfyoAAgEACQkXFHFtAJoBAAEACQkXFHFtAJoBAAAA.',
In='Inko:BAAALgADCgYJCQABLgAFFAYJHwAOALUkAA==.Inkpot:BAAALgAECgEJAQABLgAECggJNgAMABYlAA==.Inkstain:BAAALgAECgYJBwABLgAECggJNgAMABYlAA==.Inkwell:BAABLgAECn82AAIMAAgJFiX4CAAAAwAMAAgJFiX4CAAAAwAAAA==.',
Is='Iskasta:BAAALgADCgQJBAAAAA==.Isobell:BAAALgAECgcJDQAAAA==.',
Ja='Jaardrius:BAABLgAECn9BAAMVAAkJVyKGBQBGAwAVAAkJVyKGBQBGAwAIAAMJjgu3XgCVAAAAAA==.Jackransom:BAAALgADCgkJDgAAAA==.Jakobo:BAAALgAECgcJCgAAAA==.Jal:BAAALgADCgMJAwAAAA==.Jalapenoheat:BAAALgAECgQJAwAAAA==.Jandreyn:BAAALgADCgUJAQAAAA==.Jaskar:BAAALgAECgEJAQAAAA==.Javanna:BAAALgAECgUJCAAAAA==.',
Jd='Jdiddy:BAAALgAECgcJAQAAAA==.',
Je='Jelly:BAAALgADCgIJAgABLgAFFAgJIAAMALscAA==.',
Ji='Jimbostein:BAAALgADCgEJAQAAAA==.Jinnie:BAAALgADCgMJBgAAAA==.',
Jj='Jjb:BAAALgAECgcJCQAAAA==.',
Ju='Junebuge:BAAALgAECgQJBAAAAA==.Juniordh:BAAALgAFFAIJAgABLgAFFAUJDgAVALgdAA==.Junknthtrunk:BAAALgAECgMJAwAAAA==.',
Ka='Kaelana:BAAALgADCgEJAQAAAA==.Kamahl:BAAALgAFFAEJAQAAAA==.Karl:BAAALgADCgUJBQAAAA==.Katôs:BAAALgADCgkJCQAAAA==.',
Kd='Kda:BAAALgAECgYJBgABLgAECgcJFQAbAIYjAA==.',
Ke='Keanew:BAABLgAECn8wAAQPAAkJjB3vCQC5AQAPAAgJ1hTvCQC5AQAXAAkJ/xtuGwCUAQAYAAMJNgNO6wBWAAAAAA==.Kebap:BAAALgAECgYJBgAAAA==.Keigaa:BAABLgAECn8qAAMdAAcJTSCkIAAWAgAdAAYJcCGkIAAWAgAEAAYJNRR5ogApAQAAAA==.Keilien:BAAALgAECgUJBwAAAA==.Kenry:BAAALgAECgQJCAAAAA==.Keonna:BAAALgAECgUJCQAAAA==.Keppra:BAAALgAECgYJEwAAAA==.Kerlin:BAACLgAFFH8PAAIMAAMJ4AEoTgB9AAAMAAMJ4AEoTgB9AAAuAAQKfxsAAwwACQk9DmRYAEkBAAwACAlSC2RYAEkBAAsAAQnkAnOIACcAAAAA.Keyaira:BAAALgADCgYJBwAAAA==.Keybash:BAABLgAECn8UAAMNAAYJmgVyHwB1AAAaAAYJewWdxgC8AAANAAMJagNyHwB1AAAAAA==.Keíga:BAAALgAECgMJBAAAAA==.',
Kh='Kharne:BAAALgAFFAEJAgABLgAFFAQJBgAhABYiAA==.Khurst:BAAALgAECgcJDwAAAA==.',
Ki='Kilmithius:BAAALgAECgYJEgAAAA==.Kimchi:BAAALgAECgQJBAABLgAFFAgJIAAMALscAA==.Kimmex:BAAALgADCgcJAgAAAA==.Kinoxo:BAACLgAFFH8rAAMKAAcJdh1kCQCvAQAKAAUJUiVkCQCvAQAcAAYJUhMNEwAwAQAuAAQKfx0AAwoACAmRIeMaAHUCAAoACAnzHeMaAHUCABwABAm6HakgAOgAAAAA.Kinoxoxo:BAAALgAECgQJBwAAAA==.Kirianis:BAABLgAECn8vAAIEAAkJDBgiNAAmAgAEAAkJDBgiNAAmAgAAAA==.Kishuko:BAAALgADCgEJAQAAAA==.',
Kl='Klesha:BAAALgADCgMJAwAAAA==.',
Ko='Kongfuux:BAAALgAECgQJBAAAAA==.Kossuth:BAAALgAECgcJCAAAAA==.',
Kr='Kragge:BAAALgAECgcJCQAAAA==.Krampusnacht:BAAALgAECgYJCQAAAA==.Krissycat:BAAALgAECgUJBQAAAA==.Kryven:BAAALgADCgkJEQAAAA==.',
Ku='Kumma:BAAALgADCgEJAQAAAA==.Kushaladaora:BAAALgAECgQJCQAAAA==.',
Ky='Kybrine:BAAALgAECgEJAQAAAA==.Kynlas:BAAALgAECgEJAQAAAA==.Kyratinx:BAAALgAECgEJAwAAAA==.',
['Kì']='Kìtty:BAAALgAECgYJCwAAAA==.',
La='Lacachuda:BAAALgADCgIJAwAAAA==.Lacear:BAAALgADCgcJBwABLgAFFAUJCgAJAHUjAA==.Langris:BAAALgAECgcJCAAAAA==.Larious:BAABLgAECn9OAAIEAAkJSx4gFwCvAgAEAAkJSx4gFwCvAgAAAA==.',
Le='Led:BAAALgAECggJEAAAAA==.Ledikens:BAAALgAECggJDgAAAA==.Legnase:BAABLgAECn8wAAMDAAkJ6R6iBwD1AgADAAkJ1h6iBwD1AgACAAIJRRbvWQBkAAABLgAECgkJPAAQADkiAA==.Legolaslawl:BAAALgAECgQJBAABLgAFFAMJBQAKAFoUAA==.Leht:BAABLgAECn88AAMLAAkJ2REAGwDnAQALAAkJ2REAGwDnAQAMAAEJawGQ7AAVAAAAAA==.Lessgibbon:BAABLgAECn8XAAIKAAcJPh/WGgB1AgAKAAcJPh/WGgB1AgAAAA==.Lestare:BAAALgADCgYJBgAAAA==.Leviiathan:BAAALgAECgcJAwAAAA==.Lexishexis:BAAALgADCgYJBgAAAA==.',
Li='Lichma:BAAALgAECgIJAgAAAA==.Lighte:BAAALgADCgYJBgAAAA==.Lightspin:BAAALgAECgYJCgAAAA==.Lilgaspump:BAAALgADCgIJAQABLgAECgUJFAAHAJYQAA==.Lili:BAAALgADCgcJAgAAAA==.Lilnasty:BAABLgAECn8jAAIBAAkJSg6wYwCxAQABAAkJSg6wYwCxAQAAAA==.Lilnickel:BAAALgADCggJCAAAAA==.Lionroar:BAAALgAECgEJAQAAAA==.Livesey:BAAALgAECgQJBgAAAA==.',
Lo='Locknut:BAAALgADCgkJFwABLgAECggJFAAIAEUSAA==.Lockpie:BAAALgAECgUJBQAAAA==.Lockresh:BAAALgADCgcJCAABLgAECgcJJwAKAH0SAA==.Lokahn:BAABLgAECn8WAAIIAAYJ2RmGIwC6AQAIAAYJ2RmGIwC6AQAAAA==.Longhorndemn:BAAALgADCgQJBAABLgAFFAMJBQAKAFoUAA==.Longhorndk:BAAALgAECgIJAQABLgAFFAMJBQAKAFoUAA==.Longhornmage:BAAALgAECgMJAwABLgAFFAMJBQAKAFoUAA==.Longhornpibe:BAACLgAFFH8FAAIKAAMJWhTENQDHAAAKAAMJWhTENQDHAAAuAAQKf0QAAwoACAn8GLciANcBAAoACAn8GLciANcBABwAAwlMDmFLAJUAAAAA.Loudog:BAABLgAECn8zAAMRAAkJ3xNFVADBAQARAAkJohJFVADBAQAhAAYJ8hC1LADrAAAAAA==.',
Lu='Lupardus:BAAALgAECgEJAQAAAA==.Luto:BAAALgAECgkJDgAAAA==.Luuko:BAAALgAECgQJBAAAAA==.',
Ly='Lynxie:BAABLgAECn8gAAIGAAgJWA9wMABVAQAGAAgJWA9wMABVAQAAAA==.',
['Lö']='Lökkïï:BAAALgADCgUJBQAAAA==.Lörelei:BAAALgAECgQJBAAAAA==.',
Ma='Mackerel:BAABLgAECn8YAAIHAAcJliBoEACXAgAHAAcJliBoEACXAgABLgAFFAgJJQAOAJojAA==.Madii:BAAALgAECgEJAQAAAA==.Mageresh:BAABLgAECn8VAAIBAAYJwQg8zwDuAAABAAYJwQg8zwDuAAABLgAECgcJJwAKAH0SAA==.Majinmu:BAAALgADCgUJBQAAAA==.Malus:BAABLgAECn8ZAAIaAAgJLQ68YQClAQAaAAgJLQ68YQClAQAAAA==.Manders:BAAALgADCgcJAgAAAA==.Mangela:BAAALgAECgIJAwAAAA==.Mank:BAAALgAECgMJAwAAAA==.Maps:BAAALgAECgYJDQAAAA==.Masher:BAAALgAECgQJBAAAAA==.Mattydruid:BAAALgAFFAEJAQAAAA==.Maverage:BAAALgADCgMJBQAAAA==.Mavramune:BAACLgAFFH8KAAITAAUJ2Qj2UgDrAAATAAUJ2Qj2UgDrAAAuAAQKfyYAAxMACAlDFwBgAHwBABMABwniGQBgAHwBAAUACAmzDG0fAKgAAAAA.Mayge:BAABLgAECn8rAAIBAAkJKxuUMABQAgABAAkJKxuUMABQAgAAAA==.Mañali:BAAALgADCgYJBgAAAA==.',
Mc='Mcfürry:BAABLgAECn8YAAIMAAcJyBuzMQDRAQAMAAcJyBuzMQDRAQAAAA==.',
Me='Mebedir:BAAALgAECgMJBQAAAA==.Meekal:BAAALgADCgEJAQAAAA==.Meggatron:BAAALgAECggJDgABLgAECgkJKQAjAPIeAA==.Melithia:BAAALgAECgcJEQAAAA==.Mels:BAAALgAECgQJBgAAAA==.Mendinna:BAABLgAECn80AAIXAAgJdBNvGgCdAQAXAAgJdBNvGgCdAQAAAA==.Mephidrossa:BAAALgAECggJCAABLgAECgkJOQAIAGQhAA==.Mercs:BAAALgADCgQJBQABLgAECgUJFAAHAJYQAA==.Methir:BAAALgAECgEJAQABLgAFFAQJBQAUAAAAAA==.',
Mi='Miffed:BAAALgAFFAIJAgABLgAFFAcJHwAiAAoQAA==.Mildew:BAAALgADCgYJBgAAAA==.Mincksie:BAAALgAECggJEwAAAA==.Mininetty:BAAALgADCgcJBwABLgAECgYJCAAUAAAAAA==.Mirage:BAABLgAECn8VAAIbAAcJhiMPFwBSAgAbAAcJhiMPFwBSAgAAAA==.Misfired:BAAALgADCgIJAgAAAA==.Mistbot:BAABLgAECn85AAIIAAkJZCHYBQDpAgAIAAkJZCHYBQDpAgAAAA==.',
Mo='Montebrew:BAAALgAECgYJBgAAAA==.Monysha:BAAALgAECgYJDQAAAA==.Mooferrigno:BAAALgAFFAMJBAAAAA==.Mooky:BAABLgAECn8oAAILAAkJ9Q8jIgCsAQALAAkJ9Q8jIgCsAQAAAA==.Moovitz:BAAALgADCgYJDAAAAA==.Mopeia:BAABLgAECn8iAAMMAAYJghdDPgCRAQAMAAYJghdDPgCRAQAfAAUJOQ55OQCuAAABLgAECgYJEwAUAAAAAA==.Mord:BAAALgAECgUJDAAAAA==.Mork:BAAALgADCgMJAwABLgAECgcJLgARAD4iAA==.Mortemore:BAACLgAFFH8TAAIYAAYJwxW7KwBiAQAYAAYJwxW7KwBiAQAuAAQKfycAAhgACQkSIEMaAG0CABgACQkSIEMaAG0CAAAA.Mortlee:BAAALgAECgEJAQABLgAFFAYJEwAYAMMVAA==.Motet:BAAALgAECgYJCwAAAA==.Motoxman:BAAALgADCgEJAQAAAA==.',
Mu='Muikkie:BAAALgAECgEJAgAAAA==.Mulro:BAAALgADCgMJAwAAAA==.Muncher:BAAALgAECgkJEgAAAA==.',
My='Mymage:BAAALgADCgEJAQAAAA==.Mynoghra:BAAALgAECgYJEgAAAA==.Mynxx:BAAALgAECgcJCQAAAA==.Mystrax:BAAALgADCgIJAgAAAA==.',
Na='Nadoral:BAAALgADCgYJCwAAAA==.Nalka:BAAALgADCgUJBQAAAA==.Naproxen:BAABLgAECn9CAAIgAAkJySC6AgASAwAgAAkJySC6AgASAwAAAA==.Naraku:BAACLgAFFH8aAAQaAAUJBByFOgBNAQAaAAUJExuFOgBNAQAZAAEJFhKxFABVAAANAAEJ6RR+HgBQAAAuAAQKfzMAAxoACAnhIzcUAKcCABoACAlcIzcUAKcCABkABglbHugNAOcBAAAA.Narberal:BAAALgADCgEJAQAAAA==.Nastager:BAAALgADCgcJBwAAAA==.Naxx:BAAALgADCgIJAgAAAA==.Nazgül:BAAALgADCgMJAgAAAA==.',
Ne='Necroseeker:BAAALgAECgYJCwAAAA==.Negativity:BAAALgAFFAIJAgAAAA==.Nes:BAAALgAECggJCwABLgAECgkJJQADAC0aAA==.Nettie:BAAALgAECgUJBQABLgAECgYJCAAUAAAAAA==.Netty:BAAALgAECgYJCAAAAA==.',
Ni='Nightshaulea:BAAALgAECgcJCwAAAA==.Niklaus:BAACLgAFFH8IAAIEAAMJtg6IcADAAAAEAAMJtg6IcADAAAAuAAQKfx4AAgQABwl2FlVoAK8BAAQABwl2FlVoAK8BAAAA.Nilisha:BAAALgADCgIJAgAAAA==.Nimi:BAAALgAECgEJAQAAAA==.Nirala:BAAALgADCgkJCQAAAA==.',
No='Nosferatmoo:BAAALgADCgkJCQABLgADCgkJEwAUAAAAAA==.',
Nu='Nusy:BAAALgAECgQJBAAAAA==.',
Ny='Nymeera:BAABLgAECn88AAMfAAkJDgjTKwDwAAAfAAkJDgjTKwDwAAAeAAIJMgMpRABFAAAAAA==.Nymphetamine:BAABLgAECn9DAAMCAAkJLxqhDgBxAgACAAkJLxqhDgBxAgADAAQJ/AazUwCgAAAAAA==.Nyxarya:BAAALgADCgcJBwAAAA==.',
Nz='Nzoth:BAABLgAECn8gAAIGAAkJGRA8JwCMAQAGAAkJGRA8JwCMAQAAAA==.',
Ob='Obnixilis:BAABLgAECn8WAAIRAAYJHxngbgCrAQARAAYJHxngbgCrAQABLgAECggJFQAHAO8aAA==.',
Od='Odessa:BAAALgAECgEJAQAAAA==.',
Ok='Okin:BAAALgAECgMJAwAAAA==.',
Om='Omadruid:BAAALgADCgYJBgAAAA==.Omapriest:BAAALgADCgUJBQAAAA==.Omashamwow:BAAALgAECgQJBQAAAA==.Omen:BAAALgAECgMJAwAAAA==.Omorc:BAABLgAECn82AAIFAAkJExiRBQA9AgAFAAkJExiRBQA9AgAAAA==.',
On='Oneyeli:BAAALgADCgYJBgAAAA==.Oniony:BAAALgADCgYJCwAAAA==.Onli:BAAALgAECgIJAwAAAA==.Onos:BAAALgAECgMJAwAAAA==.',
Or='Ordlok:BAAALgADCgcJCQAAAA==.Oresh:BAABLgAECn8nAAIKAAcJfRI9NwBkAQAKAAcJfRI9NwBkAQAAAA==.Orlaith:BAAALgAECgcJCgABLgAECggJHQAYAEocAA==.',
Ou='Ouinur:BAAALgAECgEJAQABLgAECgkJHwAHAC4ZAA==.',
Ow='Owenwilson:BAAALgAECgUJBwAAAA==.Owful:BAAALgAECgcJDAAAAA==.',
Pa='Pandaloca:BAAALgAECgUJBQAAAA==.Pandaloco:BAAALgADCgcJBwAAAA==.Pandalôc:BAAALgAECgIJAgAAAA==.Pandoe:BAABLgAECn8VAAQfAAgJbxdnEgC5AQAfAAYJaB9nEgC5AQALAAgJrA6nMACDAQAMAAEJngeR3AAmAAAAAA==.Papaya:BAACLgAFFH8gAAIMAAgJuxyaAQD+AQAMAAgJuxyaAQD+AQAuAAQKfyIAAwwACQnZIcMGAB8DAAwACQnZIcMGAB8DAAsABwliIZYjAOABAAAA.Pawpawpiddle:BAAALgAECgYJBgAAAA==.',
Pe='Penelopea:BAABLgAECn8pAAIBAAkJeRXWPAAhAgABAAkJeRXWPAAhAgAAAA==.Perlen:BAAALgADCgYJBgAAAA==.Perun:BAAALgAECgcJEAAAAA==.',
Ph='Phaith:BAAALgADCgUJCwABLgAECgEJAQAUAAAAAA==.Phaithfully:BAAALgAECgEJAQAAAA==.Phenomenal:BAAALgAECgEJAQABLgAECgkJMAAQAGgdAA==.',
Pl='Plaguedealer:BAAALgADCgUJBQAAAA==.',
Pn='Pneumonya:BAAALgAECgcJBwAAAA==.',
Po='Porteagarder:BAABLgAECn8pAAIJAAgJugdwYgAmAQAJAAgJugdwYgAmAQABLgAECgkJIwAMABQJAA==.Potatodruid:BAAALgAECgQJDQAAAA==.Power:BAAALgADCgYJBgAAAA==.',
Pr='Preparedpie:BAABLgAECn8SAAIYAAgJcxnuMwDsAQAYAAgJcxnuMwDsAQAAAA==.Preront:BAACLgAFFH84AAMjAAkJySUIAABuAwAjAAkJryUIAABuAwAQAAgJBxsvCAAPAgAuAAQKfyIABCMACQngJikAAOYDACMACQngJikAAOYDABAAAwksJq4+AFABAAkAAwkVG8p3AOgAAAAA.Priestbrume:BAAALgAECgYJDAAAAA==.Pringler:BAAALgAECgQJBAABLgAFFAgJJQAOAJojAA==.Producktive:BAABLgAECn8bAAIiAAgJMxXCEAC6AQAiAAgJMxXCEAC6AQAAAA==.Prometeus:BAAALgAECgUJBQAAAA==.Pros:BAABLgAECn8iAAIZAAkJWRRZDQDvAQAZAAkJWRRZDQDvAQAAAA==.Pruulia:BAAALgADCgkJDAABLgAECgkJPAALANkRAA==.Príestly:BAAALgAECgYJCwAAAA==.',
Ps='Psydúck:BAAALgADCgcJDQAAAA==.',
Pu='Puffdamagic:BAABLgAECn8aAAImAAgJ1hu4FwASAgAmAAgJ1hu4FwASAgABLgAFFAYJEwAYAMMVAA==.Puffthemagic:BAABLgAECn8WAAIlAAkJoQz4CACTAQAlAAkJoQz4CACTAQAAAA==.Purentity:BAAALgAECgYJCwAAAA==.',
Py='Pyatt:BAABLgAECn8uAAINAAkJbx3jAwBgAgANAAkJbx3jAwBgAgAAAA==.',
['Pú']='Púff:BAAALgAECgQJBwAAAA==.',
Qu='Quack:BAAALgAECggJEQAAAA==.Quackadin:BAAALgADCgYJCwABLgAECggJEQAUAAAAAA==.Quackula:BAAALgAECgcJBgAAAA==.Quilae:BAABLgAECn8VAAICAAcJUwpqNQAgAQACAAcJUwpqNQAgAQABLgAECgkJIwAMABQJAA==.Quiny:BAAALgADCgMJAQAAAA==.',
Ra='Raerlynn:BAEALgADCgMJAwAAAA==.Ragnix:BAAALgAECgEJAQAAAA==.Randivh:BAAALgAECgIJAgAAAA==.Rassputin:BAABLgAECn8pAAIBAAkJnhcbOQAuAgABAAkJnhcbOQAuAgAAAA==.Raulioo:BAAALgAECgUJBQAAAA==.Ravnmoon:BAAALgAECgUJBQAAAA==.Raye:BAAALgADCgYJBgAAAA==.Razzleyi:BAAALgAECgQJBAAAAA==.',
Re='Realmack:BAAALgAECggJDAABLgAFFAUJCgAJAHUjAA==.Rebuke:BAAALgAECgYJBgAAAA==.Reclaimblade:BAAALgADCgUJBQAAAA==.Reclaimdrunk:BAAALgAECgIJAgAAAA==.Reclaimergun:BAAALgADCgEJAQAAAA==.Reclaimholy:BAAALgADCgUJBQAAAA==.Reclaimsage:BAAALgADCgYJBQAAAA==.Reigwend:BAAALgADCggJDwAAAA==.Reisharra:BAAALgAECgUJCgAAAA==.Relimas:BAAALgADCgcJEAAAAA==.Remish:BAAALgAECgUJBQAAAA==.Rendezvous:BAAALgAECgEJBwAAAA==.Renkà:BAABLgAFFH8HAAMQAAQJhgylMgC4AAAQAAMJ+Q2lMgC4AAAJAAQJ5QHFUQCeAAAAAA==.Requestor:BAAALgAECgUJCgABLgAECggJFQAHAO8aAA==.Resmondo:BAAALgADCgQJBAAAAA==.Ret:BAACLgAFFH8UAAIEAAUJlQxFTgAEAQAEAAUJlQxFTgAEAQAuAAQKfysAAgQACAkhG4suAGkCAAQACAkhG4suAGkCAAAA.Revaerlous:BAABLgAECn8uAAIRAAkJix0oLACIAgARAAkJix0oLACIAgAAAA==.',
Rh='Rheas:BAAALgADCgYJDQABLgAECggJEwAUAAAAAA==.Rhei:BAABLgAECn8RAAIYAAgJIBkbLgBEAgAYAAgJIBkbLgBEAgAAAA==.',
Ri='Ribeye:BAACLgAFFH8fAAIiAAcJChD0AgB1AQAiAAcJChD0AgB1AQAuAAQKfykAAiIACQlPFpwRAKABACIACQlPFpwRAKABAAAA.',
Ro='Roereker:BAABLgAECn9BAAIEAAkJcRr7JABnAgAEAAkJcRr7JABnAgAAAA==.Roguesamurai:BAAALgADCgEJAQAAAA==.Rohhenge:BAAALgAECgQJBAAAAA==.Roketraccoon:BAAALgAECgQJDwAAAA==.Romoxodus:BAAALgADCgUJCQAAAA==.Rongbip:BAABLgAECn8gAAIgAAkJ2hooDQBQAgAgAAkJ2hooDQBQAgAAAA==.Roshamandes:BAABLgAECn8nAAIPAAkJzCBLAgDWAgAPAAkJzCBLAgDWAgAAAA==.Rotigus:BAAALgADCgUJBQAAAA==.',
Ru='Rubadubdubz:BAAALgADCgMJAwAAAA==.Runep:BAABLgAECn8rAAIEAAkJbyDBFQC3AgAEAAkJbyDBFQC3AgAAAA==.',
Ry='Rysera:BAAALgAECgYJBgAAAA==.Ryusei:BAAALgAECgcJBwABLgAECgkJPAAQADkiAA==.',
['Rè']='Rèi:BAAALgAECgIJCAABLgAECggJJgATAF8iAA==.',
['Ré']='Réstofarian:BAACLgAFFH8UAAIMAAQJIB5fIABLAQAMAAQJIB5fIABLAQAuAAQKfy0AAwwACQm0I1sCAHYDAAwACQm0I1sCAHYDAAsAAgkoGexmAIYAAAAA.',
Sa='Sabbier:BAAALgADCgcJBwAAAA==.Sacredchikín:BAABLgAECn8eAAIaAAgJPxzMLQAbAgAaAAgJPxzMLQAbAgAAAA==.Saiki:BAAALgAECgQJBQAAAA==.Samuel:BAAALgAECgQJBwAAAA==.Sanataanna:BAAALgADCgUJCwABLgAECggJEwAUAAAAAA==.Sandvichus:BAABLgAECn8nAAILAAkJmyJVBQD+AgALAAkJmyJVBQD+AgAAAA==.Sanitarìum:BAAALgAECgQJCAAAAA==.Sardine:BAAALgAECgcJDgABLgAFFAgJIAAMALscAA==.Sasukie:BAAALgAECgEJBQAAAA==.Savagesmonk:BAAALgAECgUJBgAAAA==.Saxa:BAACLgAFFH8MAAIXAAQJyySkBACvAQAXAAQJyySkBACvAQAuAAQKfy4AAhcACQnOJE4FAOICABcACQnOJE4FAOICAAAA.',
Sc='Scratchnsnif:BAAALgADCgUJBQAAAA==.',
Se='Seers:BAAALgAECgMJAwABLgAFFAUJCgAJAHUjAA==.Sefik:BAAALgAECgYJEQAAAA==.Selaana:BAABLgAECn8YAAIQAAYJPh9nIgD8AQAQAAYJPh9nIgD8AQAAAA==.Serkis:BAAALgAECgcJBQAAAA==.Seyekosis:BAABLgAECn8bAAIYAAgJMhy9IQBCAgAYAAgJMhy9IQBCAgAAAA==.',
Sg='Sgathaich:BAEBLgAECn8rAAIdAAgJVBr4GgAjAgAdAAgJVBr4GgAjAgAAAA==.',
Sh='Shaan:BAAALgADCgMJAwAAAA==.Shadtae:BAAALgAECgYJCgABLgAECgkJLAAJAKgXAA==.Shaio:BAABLgAECn8VAAIIAAYJ3Q9hNgBGAQAIAAYJ3Q9hNgBGAQAAAA==.Shallistiah:BAAALgAECgQJBAABLgAECgkJQQAVAFciAA==.Shamadin:BAAALgADCgkJCQAAAA==.Shambrume:BAAALgAECgYJDgAAAA==.Shambulence:BAACLgAFFH8QAAIJAAQJew6UPADfAAAJAAQJew6UPADfAAAuAAQKfxoAAwkACQm/FS0gAEMCAAkACQm/FS0gAEMCACMAAwnREZYlALYAAAAA.Shammlock:BAACLgAFFH8VAAQNAAYJgBBjBwD7AAANAAUJRRNjBwD7AAAaAAMJYxE9dADNAAAZAAIJxwIpJwBBAAAuAAQKfygABA0ACQmCHuECAIMCAA0ACAkTH+ECAIMCABoACQnDGS0qAGcCABkABQl6EFskADgBAAAA.Shampriest:BAAALgAECggJCAAAAA==.Shamuel:BAACLgAFFH8IAAIgAAYJPBKyBwCDAQAgAAYJPBKyBwCDAQAuAAQKfxcAAiAACQlqEw4RACECACAACQlqEw4RACECAAAA.Shaylis:BAABLgAECn8UAAITAAcJxxm7PwDZAQATAAcJxxm7PwDZAQABLgAFFAQJBwAQAIYMAA==.Shazamm:BAAALgADCgEJAQAAAA==.Sheji:BAAALgADCgkJHAAAAA==.Shiggy:BAAALgAECgUJCgABLgAFFAMJBQAKAMoWAA==.Shobadon:BAAALgAECggJEAAAAA==.Shobarella:BAAALgAECgkJCQAAAA==.Shole:BAABLgAECn81AAMQAAkJGh7XEgBMAgAQAAkJGh7XEgBMAgAJAAcJFBxKKQALAgAAAA==.Shpoople:BAAALgAECgEJAQABLgAECgcJCQAUAAAAAA==.Shulanii:BAAALgAECgMJBQAAAA==.',
Si='Siatral:BAAALgAECgEJAQABLgAFFAUJDgAVALgdAA==.Siggopotomus:BAAALgADCgUJBQABLgAECggJEwAUAAAAAA==.Sigvalden:BAAALgAECggJEwAAAA==.Sigvolden:BAAALgAECgcJAgABLgAECggJEwAUAAAAAA==.Silchar:BAAALgAECgMJBgAAAA==.Silicon:BAABLgAECn8hAAIBAAkJjhI8YAC6AQABAAkJjhI8YAC6AQAAAA==.Simp:BAAALgAECgEJAQABLgAECgcJAQAUAAAAAA==.Sinfulangel:BAABLgAECn85AAMRAAkJ/RyjJQBmAgARAAkJ+BujJQBmAgAhAAkJbhReEAD5AQAAAA==.Siona:BAABLgAECn9IAAITAAkJZg1zSgC4AQATAAkJZg1zSgC4AQAAAA==.',
Sk='Skadie:BAABLgAECn8qAAMTAAkJNBW0JgAfAgATAAkJNBW0JgAfAgAFAAEJ+QMJQAAkAAAAAA==.Skialin:BAAALgAECgEJAQAAAA==.Skiye:BAAALgADCggJDgAAAA==.Skwii:BAAALgAFFAEJAQABLgAFFAUJCgAJAHUjAA==.Skwip:BAABLgAFFH8KAAIJAAUJdSMICwD/AQAJAAUJdSMICwD/AQAAAA==.Skwop:BAAALgAECgEJAgABLgAFFAUJCgAJAHUjAA==.Skyelar:BAAALgAECgcJBgAAAA==.Skyler:BAABLgAECn8UAAInAAcJER39AgAzAgAnAAcJER39AgAzAgAAAA==.',
Sl='Slackness:BAAALgAECgMJCAAAAA==.Slavalous:BAAALgAECgcJDAAAAA==.',
Sn='Snakeshifter:BAAALgADCgUJBQAAAA==.Snakesoul:BAAALgAECgMJBAAAAA==.Snivels:BAABLgAECn8hAAIfAAkJbRGhKAACAQAfAAkJbRGhKAACAQAAAA==.Snnorri:BAAALgADCggJFgABLgAECgkJQQAVAFciAA==.',
So='Sodtaoe:BAAALgADCgcJDQAAAA==.Solsilvesti:BAAALgADCgMJAwAAAA==.Souly:BAAALgAECgcJBwAAAA==.',
Sp='Sparrkle:BAABLgAECn8uAAIZAAkJ1w2NDABnAQAZAAkJ1w2NDABnAQAAAA==.Spin:BAAALgADCgMJAwAAAA==.Spinecrawler:BAAALgAFFAEJAQAAAA==.Spinjitzu:BAAALgAECgQJCwAAAA==.Spiritshift:BAAALgAECgEJAQAAAA==.Spyro:BAAALgAECgQJEQAAAA==.',
Sq='Squadw:BAACLgAFFH8fAAIXAAYJbRymBACvAQAXAAYJbRymBACvAQAuAAQKf0YAAhcACQkCJTkCAHMDABcACQkCJTkCAHMDAAAA.',
Ss='Sski:BAAALgADCgEJAQAAAA==.',
St='Starblast:BAAALgAECgYJEwABLgAECgYJBwAUAAAAAA==.Starrskrream:BAAALgAECgQJBgAAAA==.Staryknight:BAAALgAECgEJAQAAAA==.Steamworks:BAAALgADCgcJBwAAAA==.Steelrat:BAAALgADCgcJAgAAAA==.Stellanova:BAAALgADCgQJBAAAAA==.Stiick:BAABLgAECn82AAIiAAkJDBp7CQAsAgAiAAkJDBp7CQAsAgAAAA==.Stormhide:BAAALgADCgEJAgAAAA==.Streakycat:BAEALgAECgEJAQAAAA==.Stupidgnome:BAAALgAECgkJCgAAAA==.Stìmpak:BAAALgAECgMJBQABLgAECgcJCAAUAAAAAA==.',
Su='Subsizzle:BAAALgAECgMJAwABLgAECgcJEgAUAAAAAA==.Subzerow:BAAALgADCgYJBgAAAA==.Sudsy:BAAALgAECggJCgAAAA==.Sujin:BAAALgAECgMJAwAAAA==.Sunarra:BAABLgAECn8dAAIYAAgJShxFMAD7AQAYAAgJShxFMAD7AQAAAA==.Sunsmite:BAABLgAECn8dAAIEAAcJrha5bQCiAQAEAAcJrha5bQCiAQAAAA==.Supadupaman:BAAALgAECgkJBgAAAA==.Suramar:BAABLgAECn8YAAIOAAgJAhX6FwB2AQAOAAgJAhX6FwB2AQAAAA==.',
Sw='Sweetbippy:BAABLgAECn88AAIBAAkJjAPtpQAuAQABAAkJjAPtpQAuAQAAAA==.Swifthealss:BAABLgAECn8aAAMMAAgJjQa1ZQD7AAAMAAgJjQa1ZQD7AAALAAUJ3gqHVwCmAAAAAA==.Swirls:BAAALgAECgEJAgAAAA==.',
Sy='Sygvalden:BAAALgAECgYJDAABLgAECggJEwAUAAAAAA==.Sylunae:BAAALgAECgYJCgABLgAECgkJIwAMABQJAA==.Syluné:BAABLgAECn8jAAIMAAkJFAmzXQAVAQAMAAkJFAmzXQAVAQAAAA==.Syläs:BAAALgAECgYJEwAAAA==.Syndrassil:BAABLgAECn8xAAIBAAkJgw1JWwDHAQABAAkJgw1JWwDHAQAAAA==.',
['Sù']='Sùccubus:BAAALgADCgQJBAAAAA==.',
['Sý']='Sýd:BAAALgAECgMJAwAAAA==.',
Ta='Tacodog:BAAALgAECgUJCgABLgAFFAIJBgAEABQdAA==.Tacomonk:BAAALgAECggJCgAAAA==.Tacopally:BAAALgAECgcJCwABLgAECggJCgAUAAAAAA==.Tacozpriest:BAAALgAECgYJBgABLgAECggJCgAUAAAAAA==.Taelight:BAAALgADCggJDgABLgAECgkJLAAJAKgXAA==.Taelyx:BAABLgAECn8sAAMJAAkJqBc3NgDLAQAJAAkJqBc3NgDLAQAQAAIJ3gkQfgBOAAAAAA==.Taepain:BAAALgAECgIJAgABLgAECgkJLAAJAKgXAA==.Taicheeze:BAABLgAECn8fAAIHAAkJLhkCDwBCAgAHAAkJLhkCDwBCAgAAAA==.Tambot:BAAALgAECgQJDQAAAA==.Tariced:BAAALgAECgUJBgAAAA==.Tarvaron:BAAALgADCgEJAQAAAA==.Taytra:BAAALgAECgQJBAABLgAECgkJPAABAIwDAA==.Tazmina:BAACLgAFFH8NAAIXAAMJzB94DwAYAQAXAAMJzB94DwAYAQAuAAQKfzYAAhcACQnUIh0DAB8DABcACQnUIh0DAB8DAAAA.',
Te='Teal:BAAALgADCgYJCgAAAA==.Tehssa:BAAALgAECgUJBgABLgAECgkJPAAQAEseAA==.Tessa:BAABLgAECn88AAIQAAkJSx4YCwCmAgAQAAkJSx4YCwCmAgAAAA==.Texasfight:BAAALgAECgEJAQABLgAFFAMJBQAKAFoUAA==.Teyo:BAAALgAECgcJEQAAAA==.',
Th='Thedoctorwho:BAABLgAECn8WAAIEAAkJpw+JUgDIAQAEAAkJpw+JUgDIAQAAAA==.Theholytaz:BAABLgAECn8XAAIEAAgJDBZkQQAhAgAEAAgJDBZkQQAhAgAAAA==.Theirel:BAAALgAECgMJBAAAAA==.Thunderr:BAAALgAECgcJCAAAAA==.Thörn:BAABLgAECn8VAAMJAAgJ1A3MZwAWAQAJAAcJegvMZwAWAQAQAAIJGgV0kgBCAAABLgAFFAMJDgAMAEwIAA==.',
Ti='Tigs:BAAALgADCgMJAwAAAA==.Time:BAAALgAECgUJCAAAAA==.Tinyjapeto:BAAALgAECgQJBAAAAA==.Titanbow:BAAALgADCgYJBgABLgAECgkJMAAYALAfAA==.',
To='Tomcatt:BAABLgAECn9JAAITAAkJOCOWBgAmAwATAAkJOCOWBgAmAwAAAA==.Tonshaw:BAAALgAECgYJBgAAAA==.Toome:BAAALgADCgUJBQAAAA==.Toxin:BAAALgADCgEJAQAAAA==.',
Tr='Trailis:BAAALgAECgQJBQAAAA==.Travalden:BAAALgADCgMJAwAAAA==.Trekkie:BAAALgAECgUJBQABLgAFFAcJHwAiAAoQAA==.Treè:BAAALgAECgMJCgAAAA==.Trioxinn:BAAALgADCgEJAQAAAA==.',
Tu='Tuddlly:BAAALgAECgUJCgAAAA==.Turdfergison:BAAALgADCgUJDgABLgAECgkJJwAPAMwgAA==.Turin:BAABLgAECn8vAAIOAAkJHwgfHQBBAQAOAAkJHwgfHQBBAQAAAA==.Turnip:BAABLgAFFH8FAAIVAAIJWgwGSQBhAAAVAAIJWgwGSQBhAAABLgAFFAgJIAAMALscAA==.Tutonik:BAAALgADCgUJBQAAAA==.Tuubarkk:BAAALgADCgcJCAAAAA==.',
Tw='Twilghtdawn:BAABLgAECn8rAAIhAAgJ4BelFQC0AQAhAAgJ4BelFQC0AQAAAA==.Twos:BAAALgAECgEJAQAAAA==.Twotone:BAAALgADCgMJAwAAAA==.',
Ty='Tybo:BAABLgAECn83AAIjAAkJFSN9AQAbAwAjAAkJFSN9AQAbAwAAAA==.Tybs:BAAALgADCgEJAQAAAA==.',
['Tô']='Tôliah:BAAALgAECgEJAQAAAA==.',
Un='Uncás:BAABLgAECn8VAAITAAYJIgdZeAD+AAATAAYJIgdZeAD+AAAAAA==.Ungieblinks:BAAALgAECgQJCwAAAA==.Ungislayer:BAAALgADCgMJAwAAAA==.Unglifettv:BAACLgAFFH8KAAImAAQJzBoCIgA7AQAmAAQJzBoCIgA7AQAuAAQKfxUAAiYACAkxF0UeAN4BACYACAkxF0UeAN4BAAAA.Unstable:BAAALgAECgQJBgABLgAECgcJCAAUAAAAAA==.',
Up='Upchucky:BAAALgAECgcJCQAAAA==.',
Ur='Urulóki:BAAALgAECgcJCAAAAA==.',
Va='Vaedeath:BAABLgAECn9DAAIhAAkJJiDiCAB+AgAhAAkJJiDiCAB+AgAAAA==.Vaina:BAAALgADCgMJAwAAAA==.Vainagos:BAAALgAECgUJBgAAAA==.Valaryon:BAAALgAECgcJEwAAAA==.Valkorin:BAAALgAECgYJBwAAAA==.Valoryan:BAABLgAECn9JAAIMAAkJYRbGHABXAgAMAAkJYRbGHABXAgAAAA==.Valyteilssra:BAAALgAECgQJCQAAAA==.Vanity:BAAALgAECgMJBQAAAA==.Varindra:BAAALgAECgMJBAABLgAFFAUJDgAVALgdAA==.Vasoline:BAAALgAECgkJDAAAAA==.',
Ve='Vegà:BAABLgAECn8oAAIHAAkJ+BG1GwDAAQAHAAkJ+BG1GwDAAQAAAA==.Veina:BAAALgADCgQJCAAAAA==.Velyndris:BAAALgAECgYJCwAAAA==.Velysia:BAAALgADCgMJAwAAAA==.Vendettis:BAAALgADCgYJBgAAAA==.Verin:BAAALgAECgMJBQAAAA==.Vetraugr:BAAALgADCgMJAwABLgAECgYJDQAUAAAAAA==.Vextaerin:BAAALgAECgYJDQAAAA==.Vextarin:BAAALgADCgEJAQABLgAECgYJDQAUAAAAAA==.Veylyn:BAAALgADCgEJAQAAAA==.',
Vi='Virulent:BAAALgADCgMJAwAAAA==.Vivienreed:BAAALgAECgEJAgABLgAFFAUJDAAlAIIKAA==.',
Vo='Voidhax:BAAALgAECgUJBQAAAA==.Voidi:BAABLgAECn8XAAQbAAcJVyOsFQBiAgAbAAcJtCKsFQBiAgAkAAQJESEBDQBPAQAnAAEJtAOkDwAoAAAAAA==.Voidyo:BAACLgAFFH8PAAIYAAQJuxbLPAAiAQAYAAQJuxbLPAAiAQAuAAQKfxAAAhgACAmuHjc6ANMBABgACAmuHjc6ANMBAAAA.Voralyth:BAAALgADCggJCQAAAA==.Voranne:BAABLgAECn80AAIGAAkJ0gsWJQCaAQAGAAkJ0gsWJQCaAQAAAA==.Vortice:BAABLgAECn9IAAQQAAkJ8hStGwD4AQAQAAkJ8hStGwD4AQAJAAkJZg0bTQBwAQAjAAIJQAfbKABOAAAAAA==.Vowwel:BAAALgAECgEJAQAAAA==.',
Vy='Vyserlai:BAAALgADCgUJBQAAAA==.',
Wa='War:BAAALgAECgYJBwAAAA==.Ware:BAAALgADCgcJBwAAAA==.Warraxgos:BAAALgADCgkJHgABLgAECgkJKgAXAJUeAA==.Warraxhunt:BAAALgAECgYJCAABLgAECgkJKgAXAJUeAA==.Warraxmonk:BAAALgADCgYJBgABLgAECgkJKgAXAJUeAA==.',
We='Weißenacht:BAAALgAECgMJAwAAAA==.',
Wh='Wheatstraw:BAAALgADCgYJDQAAAA==.Whiskeyjak:BAABLgAECn8nAAMOAAkJKR39DwDfAQAOAAUJaiL9DwDfAQAKAAgJOg9INQBtAQAAAA==.',
Wi='Willowest:BAABLgAECn88AAITAAkJqBuDGACJAgATAAkJqBuDGACJAgAAAA==.',
Wr='Wrathstorm:BAABLgAECn8pAAIjAAkJ8h71BACRAgAjAAkJ8h71BACRAgAAAA==.Wrekonhoof:BAAALgAECgEJAQAAAA==.',
Wt='Wtfpie:BAACLgAFFH8YAAMRAAYJFxQ4GABEAQARAAYJFxQ4GABEAQASAAEJyBphIABQAAAuAAQKfzoAAhEACQk3I4UNAPoCABEACQk3I4UNAPoCAAAA.',
Wu='Wurmoneonine:BAAALgADCgUJBQABLgAECgkJMAAMAIYXAA==.Wurmy:BAABLgAECn8wAAMMAAkJhhfXHQBOAgAMAAkJhhfXHQBOAgALAAYJSBOdPQAMAQAAAA==.',
Wy='Wyndrunner:BAAALgADCgkJCQABLgAFFAMJCgATACgCAA==.',
['Wá']='Wárgbáte:BAAALgADCgcJBwAAAA==.',
Xa='Xalgas:BAABLgAECn8YAAIGAAYJaxaVKwB/AQAGAAYJaxaVKwB/AQAAAA==.Xanier:BAAALgAECgUJCQAAAA==.Xanivus:BAAALgADCgIJAgAAAA==.',
Xe='Xelagos:BAABLgAECn8gAAQWAAkJMRHgFwBMAQAWAAgJKhDgFwBMAQAlAAQJ6BanGACGAAAmAAMJ5BWvUwB4AAAAAA==.Xerxesjr:BAAALgADCgEJAQAAAA==.',
Xi='Xioamara:BAAALgAECgcJDAAAAA==.',
Xo='Xorm:BAAALgAECgkJBgAAAA==.',
Xx='Xxd:BAAALgAECgEJAQAAAA==.',
Ya='Yanella:BAABLgAECn8wAAMCAAkJ3BynCQDBAgACAAkJ3BynCQDBAgADAAEJcwWmWgAtAAAAAA==.',
Yi='Yispally:BAAALgAECgQJCgAAAA==.Yisshaman:BAABLgAECn8eAAIQAAkJXhvZDADQAgAQAAkJXhvZDADQAgAAAA==.',
Yo='Yo:BAABLgAFFH8GAAMfAAQJaBwlCQBJAQAfAAQJaBwlCQBJAQAeAAEJWQYrHAA6AAABLgAFFAgJJQAOAJojAA==.Yogibearz:BAAALgAECgQJBwABLgAECgUJFAAHAJYQAA==.Yogimonk:BAABLgAECn8UAAIHAAUJlhDrTQDCAAAHAAUJlhDrTQDCAAAAAA==.',
Za='Zanax:BAAALgAECgcJCAAAAA==.Zandarbribbs:BAABLgAECn8hAAIEAAgJRRU+XQCtAQAEAAgJRRU+XQCtAQAAAA==.Zapzug:BAAALgADCgYJDQAAAA==.Zaratras:BAAALgAECgEJAQAAAA==.Zaydozer:BAAALgAECgcJCwAAAA==.',
Ze='Zenmetsu:BAAALgAECgUJBgAAAA==.Zennya:BAABLgAECn8tAAIMAAkJPBcjHgBMAgAMAAkJPBcjHgBMAgAAAA==.Zeon:BAAALgAECgYJEQAAAA==.Zezra:BAAALgADCgEJAQAAAA==.',
Zi='Zikoth:BAAALgADCgEJAQAAAA==.Zingers:BAAALgAECgMJAwAAAA==.',
Zm='Zmd:BAAALgAECgYJEQAAAA==.',
Zo='Zoeso:BAABLgAECn83AAMHAAkJfx9yBgDMAgAHAAkJfx9yBgDMAgAVAAUJyQ7TXADoAAAAAA==.',
Zt='Ztropos:BAAALgAECgcJBwAAAA==.',
Zy='Zygal:BAAALgAECgMJCAAAAA==.',
['Zè']='Zèrà:BAAALgAECgEJAQAAAA==.',
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
