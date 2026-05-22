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

local lookup = {'Mage-Frost','Priest-Holy','Paladin-Retribution','Hunter-Marksmanship','Priest-Shadow','Monk-Brewmaster','Shaman-Restoration','Warrior-Fury','Druid-Balance','Druid-Restoration','Monk-Windwalker','Warlock-Affliction','DemonHunter-Vengeance','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Frost','Hunter-BeastMastery','Unknown-Unknown','Priest-Discipline','Evoker-Preservation','DemonHunter-Havoc','DemonHunter-Devourer','Warlock-Destruction','Warlock-Demonology','Warrior-Protection','Rogue-Subtlety','Warrior-Arms','Paladin-Holy','Monk-Mistweaver','Druid-Feral','Druid-Guardian','Hunter-Survival','DeathKnight-Blood','Paladin-Protection','Shaman-Enhancement','Rogue-Assassination','Evoker-Devastation','Evoker-Augmentation','Rogue-Outlaw',}
local provider = {region='US',realm='Thunderhorn',name='US',type='weekly',zone=46,date='2026-05-17',data={Ab='Absynthe:BAAALgAECgYJBgAAAA==.Abysmal:BAAALgADCgYJBgABLgAECggJHQABAGUNAA==.Abÿss:BAAALgAECgMJCAAAAA==.',
Ac='Achêrøn:BAAALgADCgcJBwAAAA==.Acoghai:BAAALgADCgcJDQAAAA==.',
Ad='Adoweld:BAAALgADCgcJBQAAAA==.Adøland:BAAALgADCgYJBgAAAA==.',
Ae='Aeliis:BAABLgAECn8iAAICAAkJ5AzQHwCIAQACAAkJ5AzQHwCIAQAAAA==.Aellart:BAAALgAECgEJAgAAAA==.Aeriona:BAABLgAECn8dAAIDAAgJGxmdPQDSAQADAAgJGxmdPQDSAQAAAA==.Aerosoul:BAAALgADCgEJAQAAAA==.',
Ag='Agamsi:BAABLgAECn8UAAIEAAgJcQvCEgDzAAAEAAgJcQvCEgDzAAAAAA==.',
Ai='Aine:BAABLgAECn8WAAMCAAcJJBbrHgCQAQACAAYJwRnrHgCQAQAFAAYJ6wA/WABcAAAAAA==.Ainek:BAAALgAECgUJBwAAAA==.Ainkor:BAAALgAECgYJBwABLgAECgkJKQAGADsWAA==.',
Aj='Ajani:BAAALgAECggJEgAAAA==.',
Ak='Akyospirit:BAABLgAECn8kAAIHAAgJAgyaPwBdAQAHAAgJAgyaPwBdAQAAAA==.Akyowindz:BAAALgADCgkJCQAAAA==.',
Al='Al:BAAALgAECgYJEAABLgAECgkJIwAIAAUcAA==.Alava:BAAALgADCgEJAQAAAA==.Aliatra:BAABLgAECn8mAAMJAAkJqQ/oHACVAQAJAAkJqQ/oHACVAQAKAAEJmggdywAfAAAAAA==.Alinth:BAAALgAECgMJBQAAAA==.Almosthuman:BAAALgAECgYJBgAAAA==.Alpha:BAABLgAECn8xAAIBAAkJHx38FQCkAgABAAkJHx38FQCkAgAAAA==.Alroy:BAAALgAECgkJCwAAAA==.Aluina:BAAALgAECgQJBAAAAA==.Alykia:BAAALgADCgYJBgAAAA==.',
Am='Amamonk:BAABLgAECn81AAMGAAkJ8hRIEQD6AQAGAAkJQhRIEQD6AQALAAQJzBdELQAVAQAAAA==.Amandara:BAAALgADCgUJBQAAAA==.Ammert:BAABLgAECn8kAAIMAAgJmg2LCQBuAQAMAAgJmg2LCQBuAQAAAA==.Amonet:BAAALgADCgYJEQAAAA==.',
An='Andou:BAAALgADCgcJBwAAAA==.Angeldracul:BAAALgADCgQJBwAAAA==.Angelove:BAAALgAECgQJCwAAAA==.Anglico:BAAALgAECgQJBQABLgAECggJHgANALIfAA==.Angliko:BAAALgAECgUJBQABLgAECggJHgANALIfAA==.Anglikoo:BAAALgADCggJCAABLgAECggJHgANALIfAA==.Anomandaris:BAABLgAECn8ZAAIOAAgJsRKkIwCCAQAOAAgJsRKkIwCCAQAAAA==.Anquan:BAABLgAECn8aAAIPAAcJQBhRVACPAQAPAAcJQBhRVACPAQAAAA==.',
Ap='Apedemak:BAAALgAECgYJBgAAAA==.Aphobias:BAAALgAECgMJAwAAAA==.Aphradite:BAAALgADCgYJCwAAAA==.Apothicc:BAABLgAECn8aAAMPAAcJARInXwBzAQAPAAcJARInXwBzAQAQAAEJAACMKwAAAAAAAA==.Appalonio:BAAALgADCgcJBQAAAA==.Appaur:BAAALgADCgEJAQAAAA==.Appolymi:BAABLgAECn8kAAIRAAgJPwR9cAAUAQARAAgJPwR9cAAUAQAAAA==.Apraxia:BAAALgADCgUJBQAAAA==.Aprionos:BAABLgAECn8pAAIBAAgJxQVejQArAQABAAgJxQVejQArAQAAAA==.',
Ar='Arakek:BAAALgADCgcJCAAAAA==.Arataena:BAAALgADCgkJFgAAAA==.Arceus:BAAALgAECgMJBQAAAA==.Aredhël:BAAALgADCgYJDgAAAA==.Argentavis:BAAALgAECggJEgABLgAECggJEwASAAAAAA==.Argobow:BAAALgAECgQJBgAAAA==.Argonaut:BAAALgAECgYJCgAAAA==.Aristella:BAAALgADCgMJAwAAAA==.Arkken:BAAALgAECgQJCAABLgAECgkJMQATAOoeAA==.Artee:BAAALgAECgEJAQAAAA==.Artémis:BAABLgAECn8iAAIRAAgJgRCCSgB5AQARAAgJgRCCSgB5AQAAAA==.',
As='Ascender:BAAALgADCgMJBgAAAA==.Ashadox:BAAALgAECgQJBAAAAA==.Asheritâ:BAAALgADCgcJBwAAAA==.Ashvalis:BAABLgAECn8cAAIUAAcJzCPFCQCaAgAUAAcJzCPFCQCaAgAAAA==.Asillyhunter:BAAALgADCgMJAwAAAA==.Asillypally:BAABLgAECn8kAAIDAAgJeBYaXgDJAQADAAgJeBYaXgDJAQAAAA==.Askr:BAABLgAECn8dAAMRAAgJ1g9JQwCRAQARAAgJpg9JQwCRAQAEAAYJnwopGQCwAAAAAA==.Asphar:BAABLgAECn8tAAMRAAkJkiWVAQBiAwARAAkJkiWVAQBiAwAEAAMJChNJIgBoAAAAAA==.Asteroth:BAAALgAECgEJAQAAAA==.',
Au='Aung:BAACLgAFFH8GAAIVAAMJliVTBgBKAQAVAAMJliVTBgBKAQAuAAQKf0EAAxUACAkiJg8CAHgDABUACAkiJg8CAHgDABYAAQmNBsn0AB4AAAAA.Auri:BAAALgADCgkJIQAAAA==.',
Av='Avatan:BAAALgAECgMJAwABLgAECggJJQAIAC0KAA==.Avralis:BAAALgADCgMJAwABLgAECggJHQAWAEkcAA==.',
Ax='Axex:BAAALgAECgcJCAAAAA==.',
Az='Azamii:BAABLgAECn81AAMOAAkJmCBOBQDcAgAOAAkJmCBOBQDcAgAHAAYJQRgUOwCVAQAAAA==.Azarion:BAABLgAECn8zAAMXAAgJch1hBwCXAQAXAAcJnRthBwCXAQAYAAYJMBZIYwBIAQAAAA==.Azill:BAACLgAFFH8QAAILAAUJcBpcBABQAQALAAUJcBpcBABQAQAuAAQKfyYAAgsACAleHjMKANUCAAsACAleHjMKANUCAAAA.Azzrael:BAABLgAECn8mAAIZAAkJaRDSFADAAQAZAAkJaRDSFADAAQAAAA==.',
Ba='Baalalmerat:BAAALgAECgIJAgAAAA==.Bandi:BAAALgAECgUJBgAAAA==.Bartrak:BAABLgAECn8YAAMFAAkJQBNgGAC/AQAFAAkJQBNgGAC/AQATAAMJ0g4nQwCcAAAAAA==.',
Be='Bearrific:BAABLgAECn8gAAIaAAkJahkcDQASAgAaAAkJahkcDQASAgAAAA==.Beawulf:BAAALgADCgkJKwAAAA==.Belista:BAAALgADCgkJKwAAAA==.Bethel:BAAALgADCgYJCAAAAA==.',
Bf='Bfresh:BAAALgADCgYJBgAAAA==.',
Bi='Billie:BAAALgADCgcJAgAAAA==.Billthekid:BAAALgAECgYJBwAAAA==.Billybobb:BAAALgAECgYJDgAAAA==.Biney:BAAALgAECgQJBAABLgAECgQJBQASAAAAAA==.Binksy:BAACLgAFFH8QAAIIAAUJSxSWFQAtAQAIAAUJSxSWFQAtAQAuAAQKfykAAggACQmLHMkNAOcCAAgACQmLHMkNAOcCAAAA.Biscuit:BAACLgAFFH8eAAIZAAcJcyNGAQAzAgAZAAcJcyNGAQAzAgAuAAQKfyIAAhkACQkfJe4AAJYDABkACQkfJe4AAJYDAAAA.Bitcoìn:BAAALgAECgEJAgAAAA==.',
Bl='Blaam:BAAALgAECgMJCgAAAA==.Blazin:BAACLgAFFH8SAAIBAAQJvRZmSACeAAABAAQJvRZmSACeAAAuAAQKfyQAAgEACAmtIIcWAKACAAEACAmtIIcWAKACAAAA.Blep:BAAALgAECgYJCgAAAA==.Blgunc:BAAALgAECggJDwAAAA==.Blinkzy:BAAALgAECgUJCQAAAA==.Bloui:BAAALgAECgQJCAAAAA==.',
Bo='Boba:BAAALgAECgYJBgABLgAFFAcJHgAZAHMjAA==.Bongrips:BAAALgADCgIJAgAAAA==.Boomboom:BAAALgAECgIJAwAAAA==.Borlok:BAAALgAFFAEJAQAAAQ==.',
Br='Brannigan:BAABLgAECn8kAAIZAAgJbyMKBAC1AgAZAAgJbyMKBAC1AgAAAA==.Braulioo:BAAALgAECgEJAgAAAA==.Breebbs:BAAALgAECgUJBQAAAA==.Briantu:BAABLgAECn8aAAIHAAgJ1wGmZADSAAAHAAgJ1wGmZADSAAAAAA==.Brickitphil:BAAALgAECgYJBwAAAA==.Briiz:BAAALgADCgkJDAAAAA==.Brlolock:BAAALgADCgkJJAAAAA==.Brollo:BAAALgADCgEJAQAAAA==.Brud:BAAALgADCgYJAwAAAA==.Brönwyn:BAAALgAECgMJBQAAAA==.',
Bu='Bubblegumdrp:BAAALgAECgMJAwAAAA==.Bubblicious:BAAALgADCgUJCQAAAA==.Buckets:BAAALgAECgcJEQAAAA==.Budi:BAAALgADCgcJCAAAAA==.Bulldan:BAABLgAECn8fAAIMAAcJkiE1BAAGAgAMAAcJkiE1BAAGAgAAAA==.Bullvi:BAAALgAECgYJBgAAAA==.',
['Bä']='Bärkler:BAABLgAECn8aAAMbAAgJGCLrBQBhAgAbAAgJGCLrBQBhAgAZAAEJHBjePABFAAAAAA==.',
['Bé']='Béckley:BAAALgAECggJEgAAAA==.Béckléy:BAAALgAECgUJDQABLgAECggJEgASAAAAAA==.',
Ca='Caatha:BAAALgADCgkJIgAAAA==.Caleanone:BAAALgAECgcJCAABLgAECgkJIwAIAAUcAA==.Calel:BAAALgAECgkJCAAAAA==.Callox:BAABLgAECn8jAAMIAAgJBRxYHgC7AQAIAAgJZBlYHgC7AQAbAAUJJxvtEQCCAQAAAA==.Cantelope:BAAALgADCgYJBgAAAA==.Capslock:BAAALgAECgQJAwAAAA==.Cara:BAAALgADCgIJAgAAAA==.Carahail:BAABLgAECn8nAAMKAAgJ5xS5JADsAQAKAAgJ5xS5JADsAQAJAAQJNwsDTgCLAAAAAA==.Catriona:BAABLgAECn8ZAAIRAAgJuAoFXABHAQARAAgJuAoFXABHAQAAAA==.Cazmeer:BAAALgAECgMJAwAAAA==.',
Ce='Celés:BAAALgAECgUJBQAAAA==.',
Ch='Charcuterie:BAACLgAFFH8fAAIGAAcJThkXBADfAQAGAAcJThkXBADfAQAuAAQKfyAAAwYACQnXIVwJAPMCAAYACQnXIVwJAPMCAAsAAQlxHbZgAFUAAAAA.Chaír:BAAALgAECgEJBQAAAA==.Cheezeburg:BAAALgADCgEJAQABLgAECggJGgAGAGYWAA==.Cheezus:BAAALgAECgIJAwABLgAECggJGgAGAGYWAA==.Cherrbeår:BAAALgADCgcJBwAAAA==.Cherudim:BAACLgAFFH8FAAMXAAMJ4wsjDwCHAAAYAAMJ4wtgWADSAAAXAAIJrwIjDwCHAAAuAAQKfyYAAxcACAkiF44JACcCABcACAmBFY4JACcCABgACAl1FGNCAKIBAAAA.Chillainkor:BAABLgAECn8pAAIGAAkJOxYwEgDvAQAGAAkJOxYwEgDvAQAAAA==.Chillidán:BAABLgAECn8OAAIWAAgJ9wLtlQCsAAAWAAgJ9wLtlQCsAAAAAA==.Chippmagi:BAABLgAECn8gAAIBAAgJ9BrLOwDzAQABAAgJ9BrLOwDzAQAAAA==.Chippndots:BAAALgAECgUJCwABLgAECggJIAABAPQaAA==.Chirp:BAAALgAECgEJAQAAAA==.Chives:BAAALgAECgQJBAAAAA==.Choggie:BAABLgAECn8uAAIcAAkJrxypBQD/AgAcAAkJrxypBQD/AgAAAA==.Chronocolter:BAAALgADCgMJAwAAAA==.Chronosaren:BAAALgAECggJEgAAAA==.Chåir:BAAALgAECgEJAgAAAA==.',
Ci='Cinterax:BAAALgAECgIJAgABLgAECggJJAAZAG8jAA==.',
Cj='Cjrej:BAABLgAECn8hAAIBAAgJug3HaABzAQABAAgJug3HaABzAQAAAA==.',
Cl='Claytonis:BAAALgAECgEJAQAAAA==.Cloudnine:BAAALgAECgQJBAAAAA==.',
Co='Colterr:BAAALgADCgEJAQAAAA==.Cons:BAABLgAECn8jAAQTAAkJIxaEEAAhAgATAAkJ1hSEEAAhAgACAAMJ8QrYZQCWAAAFAAEJ+xIlYgA3AAAAAA==.Corellon:BAABLgAECn8qAAIRAAgJ1xzSJwD8AQARAAgJ1xzSJwD8AQAAAA==.Costcohotdog:BAABLgAFFH8KAAMGAAMJLR1IGACsAAAGAAMJLR1IGACsAAAdAAEJOQBpGgAYAAABLgAFFAcJHgAZAHMjAA==.Cougarclaws:BAAALgAECgUJCQAAAA==.',
Cr='Craftsman:BAAALgADCgYJBgAAAA==.Craigchrist:BAAALgAECgYJBgAAAA==.Cranee:BAABLgAECn8fAAIYAAgJyxCBSwCHAQAYAAgJyxCBSwCHAQAAAA==.Cranium:BAAALgAECgUJCAAAAA==.Crazytasty:BAABLgAECn8mAAIRAAgJXyICEACQAgARAAgJXyICEACQAgAAAA==.Crumbo:BAAALgAECgYJBgAAAA==.Cryoburn:BAABLgAECn8fAAIBAAgJWB0URADWAQABAAgJWB0URADWAQAAAA==.Cryoshock:BAABLgAFFH8FAAIOAAMJwBZFHgDnAAAOAAMJwBZFHgDnAAAAAA==.',
Cu='Cutty:BAAALgAECgUJBgAAAA==.',
Da='Daario:BAABLgAECn8TAAIWAAcJsB+pNQAhAgAWAAcJsB+pNQAhAgAAAA==.Dabare:BAAALgADCgUJAQAAAA==.Dabora:BAAALgAECgEJAQABLgAECggJJwAeAEsfAA==.Dabßod:BAAALgAECgQJBAAAAA==.Dabûra:BAABLgAECn8nAAQeAAgJSx9qDACeAQAeAAcJTh1qDACeAQAfAAcJehACHwDmAAAJAAYJ+xzEOADlAAAAAA==.Daenerys:BAAALgAECgIJBgAAAA==.Dahouse:BAAALgADCgQJAwAAAA==.Dahpeht:BAAALgADCgkJEwAAAA==.Damda:BAAALgADCgIJAgAAAA==.Dandypooh:BAAALgAECgYJBgABLgAECgcJDQASAAAAAA==.Danksamdi:BAAALgAECgEJAQAAAA==.Darige:BAAALgAECgIJAgAAAA==.Darim:BAAALgAECgEJAQABLgAECggJIgABAJcYAA==.Darrow:BAAALgAECggJCAAAAA==.Darthspawn:BAABLgAECn8UAAIPAAYJewt7lAAEAQAPAAYJewt7lAAEAQAAAA==.Daryl:BAAALgAECgQJBAAAAA==.Daryn:BAAALgAECgQJBAAAAA==.Davidbowy:BAABLgAECn8ZAAMgAAgJsA1oIQBUAQAgAAcJ7whoIQBUAQARAAcJYQ6sZQAuAQABLgAECgYJBwASAAAAAA==.',
De='Deathnstuf:BAAALgAECgQJBgAAAA==.Deathollow:BAAALgAECgEJAwAAAA==.Delver:BAAALgADCgYJBgABLgAECggJIgABAJcYAA==.Demina:BAAALgADCgUJBQABLgAECggJHQAWAEkcAA==.Demonainkor:BAAALgAECgYJBgABLgAECgkJKQAGADsWAA==.Demonicfury:BAAALgAECgYJBwAAAA==.Demonthrall:BAAALgAECgEJAQAAAA==.Dencity:BAABLgAECn8kAAMTAAgJQhYvIAB+AQATAAcJ1REvIAB+AQACAAYJbxcpLQAmAQAAAA==.Desden:BAABLgAECn8kAAIfAAgJmxMREACHAQAfAAgJmxMREACHAQAAAA==.Destined:BAAALgAECgIJAgAAAA==.Devianchi:BAABLgAECn8nAAMdAAgJ+B+FCQC5AgAdAAgJ+B+FCQC5AgALAAcJIh+QEAAAAgAAAA==.Devitodevour:BAABLgAECn8eAAMYAAgJPRu2LwDmAQAYAAcJmxm2LwDmAQAXAAMJXBkENQDiAAAAAA==.',
Dg='Dgbugs:BAACLgAFFH8KAAIPAAMJoCKhVQAOAQAPAAMJoCKhVQAOAQAuAAQKfzIAAg8ACAk9I+4ZAHMCAA8ACAk9I+4ZAHMCAAAA.',
Dh='Dhbert:BAABLgAECn8jAAIhAAkJww/IFQBxAQAhAAkJww/IFQBxAQAAAA==.Dhomeli:BAAALgAECgQJBQAAAA==.',
Di='Dirtchez:BAAALgAECgEJAQAAAA==.Disastrophy:BAAALgAECgYJEQABLgAECgcJCAASAAAAAA==.Disturbed:BAABLgAECn8uAAQYAAkJXxzXGQBYAgAYAAgJMxvXGQBYAgAMAAMJpR8fGACcAAAXAAEJAADbYgBJAAAAAA==.Disturbio:BAAALgAECgEJAQABLgAECgkJLgAYAF8cAA==.Divinepsycho:BAAALgADCgcJBwAAAA==.Divitiacus:BAAALgADCgMJAwAAAA==.',
Dj='Djowio:BAAALgADCgYJBgABLgAECggJIwAYABoiAA==.',
Dm='Dmz:BAAALgADCgUJBgAAAA==.',
Do='Domfromgears:BAAALgAECgQJCQAAAA==.Dominance:BAAALgAECgEJAQAAAA==.Doomgaze:BAAALgADCgMJAQAAAA==.Dooridash:BAAALgADCgcJCwAAAA==.Dorc:BAAALgAECgMJBQAAAA==.Dotyou:BAAALgAECgIJAgAAAA==.Doudouzz:BAAALgAECgQJDQAAAA==.',
Dr='Dracthor:BAAALgADCgQJBAAAAA==.Draejin:BAAALgAECgkJDwAAAA==.Dragonfist:BAAALgADCgcJBwAAAA==.Dragthyr:BAAALgAECgQJBQAAAA==.Dramûl:BAABLgAECn8dAAIRAAgJcRjTMQDQAQARAAgJcRjTMQDQAQAAAA==.Druiaier:BAAALgADCgYJCQAAAA==.Druidibrume:BAAALgAECgMJDAAAAA==.Druknatsu:BAAALgAECgUJBQAAAA==.Drunkdragon:BAABLgAECn8UAAILAAgJRRLpGwD9AQALAAgJRRLpGwD9AQAAAA==.',
Du='Dubbzilla:BAAALgAECgEJAQAAAA==.Dudedruid:BAAALgADCgUJBQAAAA==.Duncán:BAAALgAFFAEJAQABLgAFFAMJAwASAAAAAA==.Dustyknight:BAABLgAECn8eAAIhAAgJzQiPIgDzAAAhAAgJzQiPIgDzAAAAAA==.',
Dw='Dwell:BAAALgADCgkJHwAAAA==.',
Dy='Dyavola:BAAALgAECgUJBQAAAA==.',
Ea='Earthquack:BAAALgADCgMJAwABLgAECggJGwAiADMVAA==.',
Ed='Edge:BAABLgAECn8bAAIHAAgJyxQIMgCdAQAHAAgJyxQIMgCdAQAAAA==.',
Ee='Eelenna:BAABLgAECn8YAAMjAAkJ5xtgBgCSAgAjAAkJ5xtgBgCSAgAOAAUJwRBnUwD4AAABLgAECggJHwAQAHofAA==.',
El='Elamlock:BAAALgADCgYJCwAAAA==.Eleathe:BAAALgAECgcJEAABLgAECggJHQAWAEkcAA==.Eleros:BAABLgAECn8wAAIWAAkJrx8XCgDJAgAWAAkJrx8XCgDJAgAAAA==.Elicio:BAAALgAECgYJEAAAAA==.Ellysial:BAAALgADCgUJBQAAAA==.Elphinia:BAABLgAECn8pAAMaAAgJ1hhDEgDMAQAaAAgJ1hhDEgDMAQAkAAEJ4BFlIAAxAAAAAA==.Elreÿ:BAAALgADCgEJAQAAAA==.',
Em='Emberwrath:BAAALgADCgMJAwAAAA==.Emosdnem:BAAALgAECgEJAQAAAA==.Emt:BAAALgADCgkJGAAAAA==.',
En='Endarial:BAAALgAECgQJCAAAAA==.Enoki:BAABLgAFFH8IAAIHAAMJ3hmNEADkAAAHAAMJ3hmNEADkAAABLgAFFAcJHQAKAE8gAA==.',
Er='Eraduckated:BAAALgAECgYJBgABLgAECggJGwAiADMVAA==.Erah:BAAALgADCgUJDQAAAA==.',
Es='Esco:BAAALgADCgMJAwAAAA==.Esile:BAAALgADCgkJHwABLgAECggJJAAJAHoNAA==.',
Et='Eternalnow:BAAALgADCgEJAQAAAA==.',
Ev='Evelith:BAAALgADCgYJBgAAAA==.Everlife:BAAALgAECgcJDwAAAA==.',
Ex='Exemptt:BAAALgAECgkJBQAAAA==.Exo:BAAALgADCgkJDwAAAA==.',
Fa='Falconpunch:BAAALgAECgEJAQAAAA==.Farnesë:BAAALgADCgUJBwABLgADCgcJBwASAAAAAA==.Fauzzie:BAAALgAECgIJAgAAAA==.Fayrel:BAAALgAECgEJAgAAAA==.',
Fe='Fedders:BAABLgAECn8pAAIDAAkJPibABAArAwADAAkJPibABAArAwAAAA==.Felaids:BAACLgAFFH8OAAMYAAQJdRAqSgDxAAAYAAQJ3QwqSgDxAAAMAAEJSBDBEwBKAAAuAAQKfyoAAxgACAlDHAkrAPsBABgABwlDHAkrAPsBABcAAwkSCLpEAKIAAAAA.Felimonk:BAAALgAECgQJBAABLgABCgQJBQASAAAAAA==.Felpecs:BAAALgAECggJDgAAAA==.Feyda:BAABLgAECn8bAAIBAAgJjQd3fgBFAQABAAgJjQd3fgBFAQAAAA==.',
Fi='Fillon:BAABLgAECn8yAAIDAAgJrSXLEgCfAgADAAgJrSXLEgCfAgAAAA==.Fionas:BAAALgADCgQJBAAAAA==.Firerybush:BAAALgAECgYJBgABLgAECggJPQAIAPwYAA==.Firessar:BAAALgAECgcJCwAAAA==.Fishfood:BAABLgAECn8kAAIQAAgJSxPACACUAQAQAAgJSxPACACUAQAAAA==.Fishlover:BAAALgADCgUJBQAAAA==.Fixer:BAAALgAECgUJCQAAAA==.',
Fk='Fk:BAAALgAFFAMJAwAAAA==.',
Fo='Foe:BAEALgAECggJEwAAAA==.Folkvar:BAAALgADCgcJDAAAAA==.',
Fr='Frankngibbon:BAAALgADCgYJBgAAAA==.Frimm:BAAALgAECgUJBQAAAA==.Frimthemage:BAABLgAECn8tAAIBAAkJOB/3GQCLAgABAAkJOB/3GQCLAgAAAA==.Frostmaster:BAABLgAECn8bAAIBAAcJOhx0QwDYAQABAAcJOhx0QwDYAQAAAA==.',
Fu='Funbunz:BAAALgAECgYJBgAAAA==.',
['Fí']='Fízban:BAAALgAECgIJAwAAAA==.',
['Fø']='Førd:BAACLgAFFH8LAAMlAAQJFQxqAwAlAQAlAAQJFQxqAwAlAQAmAAIJjQgiPACCAAAuAAQKfy8ABCUACAmQHRoLACoCACUABwlLGhoLACoCACYABwlOGSUkAJwBABQAAwkIApguAD8AAAAA.',
Ga='Gammon:BAABLgAECn8gAAMOAAgJ7httEwAKAgAOAAgJ7httEwAKAgAHAAUJGxuxNgCGAQAAAA==.Gangrene:BAABLgAECn8yAAMPAAkJnxOgPQDTAQAPAAkJnxOgPQDTAQAhAAgJCQvMHwALAQAAAA==.Gary:BAAALgAECgQJBgAAAA==.Gash:BAAALgAECgMJAwAAAA==.Gaspasser:BAABLgAECn8hAAIkAAgJwBcSBQDzAQAkAAgJwBcSBQDzAQAAAA==.Gaviin:BAABLgAECn8vAAIkAAgJtiFvAgB2AgAkAAgJtiFvAgB2AgAAAA==.',
Ge='Gearador:BAAALgADCgcJAQAAAA==.Geisten:BAAALgAECgYJEwAAAA==.Genovia:BAAALgADCgIJAgABLgAECggJEwASAAAAAA==.Gerhart:BAABLgAECn8jAAQNAAgJIBliCgB1AQANAAcJrBViCgB1AQAWAAcJYxlZdwBAAQAVAAMJRhBtPABqAAAAAA==.Getcarried:BAAALgADCgMJAwABLgAFFAQJEgABAL0WAA==.Getty:BAAALgAECgcJEQAAAA==.',
Gf='Gfforgold:BAAALgADCgIJAgAAAA==.',
Gh='Ghosthunterx:BAAALgADCgEJAwAAAA==.Ghouldana:BAAALgADCgYJBgAAAA==.',
Gi='Gibbthok:BAAALgADCggJCAAAAA==.Gigachode:BAAALgAECgEJAgAAAA==.Gigarius:BAABLgAECn8ZAAIiAAgJVyQbAwCoAgAiAAgJVyQbAwCoAgAAAA==.Gigglesworth:BAAALgAECgYJBgAAAA==.Gilamonster:BAAALgAECgYJCgAAAA==.',
Gl='Gleiten:BAAALgADCgMJAwAAAA==.Glonkins:BAAALgAECggJEQAAAA==.Glynden:BAAALgADCgEJAQAAAA==.',
Go='Goncor:BAABLgAECn8fAAMQAAgJeh/rBAAQAgAQAAgJMB/rBAAQAgAhAAUJ+CIjFQB5AQAAAA==.Gonnosuke:BAAALgAECgYJCQAAAA==.Gooseberry:BAAALgAECgEJAQAAAA==.Goosë:BAAALgADCgcJBwAAAA==.Gorrelord:BAAALgADCgEJAQABLgAFFAQJEgABAL0WAA==.Gortar:BAAALgADCgEJAQAAAA==.',
Gr='Granolah:BAAALgADCgcJCwABLgAECggJJwAeAEsfAA==.Griffmonk:BAABLgAECn8wAAIdAAkJCRv1DQBmAgAdAAkJCRv1DQBmAgAAAA==.Grumpymage:BAABLgAECn8xAAIBAAkJpx9cEADLAgABAAkJpx9cEADLAgAAAA==.',
Gu='Gussy:BAAALgADCgUJAgABLgAECgcJEQASAAAAAA==.',
Ha='Hafsac:BAAALgAECgMJAwAAAA==.Halaranth:BAAALgAECgIJAgAAAA==.Hamasakura:BAAALgADCgkJJgAAAA==.Hara:BAABLgAECn8aAAIKAAYJPRpkNwB/AQAKAAYJPRpkNwB/AQAAAA==.Hardlyknower:BAAALgADCgIJAgAAAA==.Hardord:BAABLgAECn8aAAIaAAcJEQ3tIQA1AQAaAAcJEQ3tIQA1AQAAAA==.Harrydotter:BAAALgAECgIJAgAAAA==.Haryle:BAAALgAECgUJCgAAAA==.Hayanne:BAABLgAECn81AAIZAAkJHBtGBwBUAgAZAAkJHBtGBwBUAgAAAA==.',
He='Healchucky:BAAALgAECgYJDQAAAA==.Healfire:BAAALgADCgYJBwAAAA==.Healisha:BAAALgAECgYJDwAAAA==.Heina:BAAALgAECgYJBgAAAA==.Hershall:BAAALgAECgUJBQABLgAFFAMJBgAVAJYlAA==.',
Hi='Hitnrun:BAAALgAECgMJAwAAAA==.',
Ho='Hochunk:BAABLgAECn8YAAMTAAkJ/A6WGQC4AQATAAkJxQqWGQC4AQACAAkJugkdOwBOAQAAAA==.Hochunks:BAAALgAECgYJDQAAAA==.Holdenger:BAAALgADCgQJBAAAAA==.Holikow:BAAALgAECggJEwAAAA==.Holyherpies:BAAALgAECgYJBgAAAA==.Holyllama:BAAALgADCgcJBwAAAA==.Holymousey:BAABLgAECn8ZAAIcAAkJ0Q95IgCyAQAcAAkJ0Q95IgCyAQAAAA==.Holysnake:BAAALgAECgQJBAAAAA==.Holytady:BAAALgADCgcJDQAAAA==.Holytudd:BAABLgAECn8gAAIDAAgJixTaYAByAQADAAgJixTaYAByAQAAAA==.Honeybun:BAAALgADCgQJAgAAAA==.Honorlife:BAABLgAECn8kAAIHAAgJDhuAFwBGAgAHAAgJDhuAFwBGAgAAAA==.Hopeudie:BAAALgAECgUJBgABLgAFFAMJAwASAAAAAA==.Hotelcali:BAAALgADCgkJCQAAAA==.',
Hu='Huckcold:BAAALgAECgcJDwAAAA==.Hugehands:BAAALgAECgUJBwAAAA==.Hughass:BAAALgADCgEJAQAAAA==.Hurano:BAAALgAECgYJBQAAAA==.',
['Hâ']='Hârley:BAABLgAECn8pAAIKAAkJxhpFFABtAgAKAAkJxhpFFABtAgAAAA==.',
['Hí']='Híram:BAABLgAECn8mAAIDAAgJahS1VACPAQADAAgJahS1VACPAQAAAA==.',
Id='Idyllwild:BAAALgAECgEJBAAAAA==.',
Ih='Ihsan:BAABLgAECn8eAAIDAAgJ2BQpQwDAAQADAAgJ2BQpQwDAAQAAAA==.',
Il='Ilharess:BAACLgAFFH8HAAIBAAMJKQekYwDeAAABAAMJKQekYwDeAAAuAAQKfyYAAgEACQkdE8ZbAJMBAAEACQkdE8ZbAJMBAAAA.',
In='Inko:BAAALgADCgYJCQABLgAFFAUJEwAZAEwkAA==.Inkpot:BAAALgAECgEJAQABLgAECggJLgAKABYlAA==.Inkwell:BAABLgAECn8uAAIKAAgJFiX4CAAAAwAKAAgJFiX4CAAAAwAAAA==.',
Is='Iskasta:BAAALgADCgQJBAAAAA==.Isobell:BAAALgAECgUJBwAAAA==.',
Ja='Jaardrius:BAABLgAECn8pAAMdAAgJkCImBwDeAgAdAAgJkCImBwDeAgALAAMJjgu3XgCVAAAAAA==.Jackransom:BAAALgADCgkJDgAAAA==.Jakobo:BAAALgAECgcJCgAAAA==.Jal:BAAALgADCgMJAwAAAA==.Jalapenoheat:BAAALgAECgQJAwAAAA==.Jandreyn:BAAALgADCgUJAQAAAA==.Jaskar:BAAALgAECgEJAQAAAA==.Javanna:BAAALgAECgMJAwAAAA==.',
Jd='Jdiddy:BAAALgAECgcJAQAAAA==.',
Je='Jelly:BAAALgADCgIJAgABLgAFFAcJHQAKAE8gAA==.',
Ji='Jimbostein:BAAALgADCgEJAQAAAA==.Jinnie:BAAALgADCgMJBgAAAA==.',
Jj='Jjb:BAAALgAECgYJBwAAAA==.',
Ju='Junebuge:BAAALgADCgkJHQAAAA==.Junknthtrunk:BAAALgAECgMJAwAAAA==.',
Ka='Kaelana:BAAALgADCgEJAQAAAA==.Karl:BAAALgADCgUJBQAAAA==.Katôs:BAAALgADCgkJCQAAAA==.',
Kd='Kda:BAAALgAECgYJBgABLgAECgcJFQAaAIYjAA==.',
Ke='Keanew:BAABLgAECn8sAAQNAAgJPR4QCQCTAQANAAcJHRcQCQCTAQAVAAgJdxy7GQBXAQAWAAMJNgPtwgBUAAAAAA==.Kebap:BAAALgAECgYJBgAAAA==.Keigaa:BAABLgAECn8lAAMcAAYJcCGkIAAWAgAcAAYJcCGkIAAWAgADAAQJBA94ygC3AAAAAA==.Keilien:BAAALgAECgEJAQAAAA==.Kenry:BAAALgAECgQJCAAAAA==.Keonna:BAAALgAECgQJCAAAAA==.Keppra:BAAALgAECgYJDgAAAA==.Kerlin:BAACLgAFFH8IAAIKAAMJGwE3PgCBAAAKAAMJGwE3PgCBAAAuAAQKfxoAAwoACAkND2RYAEkBAAoABwnVC2RYAEkBAAkAAQnkAnOIACcAAAAA.Keyaira:BAAALgADCgYJBwAAAA==.Keybash:BAABLgAECn8UAAMMAAYJmgVyHwB1AAAYAAYJewWJpQDEAAAMAAMJagNyHwB1AAAAAA==.Keíga:BAAALgAECgMJBAAAAA==.',
Kh='Khurst:BAAALgAECgcJCgAAAA==.',
Ki='Kilmithius:BAAALgAECgYJEgAAAA==.Kimchi:BAAALgAECgQJBAABLgAFFAcJHQAKAE8gAA==.Kimmex:BAAALgADCgcJAgAAAA==.Kinoxo:BAACLgAFFH8fAAMIAAYJzhw1CgBVAQAIAAQJZx01CgBVAQAbAAUJ1RWcEAD2AAAuAAQKfx0AAwgACAmSIeMaAHUCAAgACAnzHeMaAHUCABsABAm8HakgAOgAAAAA.Kinoxoxo:BAAALgAECgQJBwAAAA==.Kirianis:BAABLgAECn8nAAIDAAgJXRaeRQC5AQADAAgJXRaeRQC5AQAAAA==.Kishuko:BAAALgADCgEJAQAAAA==.',
Kl='Klesha:BAAALgADCgMJAwAAAA==.',
Ko='Kongfuux:BAAALgAECgQJBAAAAA==.Kossuth:BAAALgAECgYJBgAAAA==.',
Kr='Kragge:BAAALgADCgcJBwAAAA==.Krampusnacht:BAAALgAECgYJCQAAAA==.Kryven:BAAALgADCgkJEQAAAA==.',
Ku='Kumma:BAAALgADCgEJAQAAAA==.Kushaladaora:BAAALgAECgQJCQAAAA==.',
Ky='Kybrine:BAAALgAECgEJAQAAAA==.Kynlas:BAAALgAECgEJAQAAAA==.Kyratinx:BAAALgAECgEJAwAAAA==.',
['Kì']='Kìtty:BAAALgAECgYJBgAAAA==.',
La='Lacachuda:BAAALgADCgIJAwAAAA==.Lacear:BAAALgADCgcJBwABLgAFFAMJAwASAAAAAA==.Langris:BAAALgAECgcJCAAAAA==.Larious:BAABLgAECn80AAIDAAgJiRyKJwAnAgADAAgJiRyKJwAnAgAAAA==.',
Le='Ledikens:BAAALgADCgkJEQAAAA==.Legnase:BAABLgAECn8wAAMTAAkJ6h79BAADAwATAAkJ1x79BAADAwACAAIJRRZQSwBsAAABLgAECgkJNQAOAJggAA==.Leht:BAABLgAECn8kAAMJAAgJeg2jJQBRAQAJAAgJeg2jJQBRAQAKAAEJawGQ7AAVAAAAAA==.Lessgibbon:BAABLgAECn8XAAIIAAcJPh/WGgB1AgAIAAcJPh/WGgB1AgAAAA==.Lestare:BAAALgADCgYJBgAAAA==.Leviiathan:BAAALgAECgcJAwAAAA==.Lexishexis:BAAALgADCgYJBgAAAA==.',
Li='Lichma:BAAALgAECgIJAgAAAA==.Lighte:BAAALgADCgYJBgAAAA==.Lilgaspump:BAAALgADCgIJAQABLgAECgUJFAAGAJYQAA==.Lili:BAAALgADCgcJAgAAAA==.Lilnasty:BAABLgAECn8dAAIBAAgJZQ3SbwBkAQABAAgJZQ3SbwBkAQAAAA==.Lilnickel:BAAALgADCggJCAAAAA==.Lionroar:BAAALgADCgEJAQAAAA==.Livesey:BAAALgAECgQJBQAAAA==.',
Lo='Locknut:BAAALgADCgkJFwABLgAECggJFAALAEUSAA==.Lockpie:BAAALgAECgUJBQAAAA==.Lockresh:BAAALgADCgUJBQABLgAECgcJHQAIAE8RAA==.Lokahn:BAABLgAECn8WAAILAAYJ2RmGIwC6AQALAAYJ2RmGIwC6AQAAAA==.Longhornpibe:BAABLgAECn89AAMIAAgJ/BhoGgDZAQAIAAgJ/BhoGgDZAQAbAAMJTA4QNgCaAAAAAA==.Loudog:BAABLgAECn8wAAMPAAgJZhQqWwB9AQAPAAgJ/BIqWwB9AQAhAAYJ8RAeIgD3AAAAAA==.',
Lu='Lupardus:BAAALgAECgEJAQAAAA==.Luto:BAAALgAECgkJDgAAAA==.',
Ly='Lynxie:BAABLgAECn8gAAIFAAgJWQ8mJQBYAQAFAAgJWQ8mJQBYAQAAAA==.',
['Lö']='Lökkïï:BAAALgADCgUJBQAAAA==.Lörelei:BAAALgADCgkJKAAAAA==.',
Ma='Mackerel:BAABLgAECn8YAAIGAAcJliBoEACXAgAGAAcJliBoEACXAgABLgAFFAcJHgAZAHMjAA==.Madii:BAAALgAECgEJAQAAAA==.Mageresh:BAAALgAECgYJDAABLgAECgcJHQAIAE8RAA==.Malus:BAABLgAECn8ZAAIYAAgJLQ68YQClAQAYAAgJLQ68YQClAQAAAA==.Manders:BAAALgADCgcJAgAAAA==.Mangela:BAAALgAECgIJAwAAAA==.Mank:BAAALgAECgMJAwAAAA==.Maps:BAAALgAECgYJDQAAAA==.Masher:BAAALgADCgkJKwAAAA==.Mattydruid:BAAALgAFFAEJAQAAAA==.Maverage:BAAALgADCgMJBQAAAA==.Mavramune:BAABLgAECn8mAAMRAAgJNhf/QQCVAQARAAcJ4hn/QQCVAQAEAAgJpQx3GQCuAAAAAA==.Mayge:BAABLgAECn8pAAIBAAkJKxuLIwBYAgABAAkJKxuLIwBYAgAAAA==.Mañali:BAAALgADCgYJBgAAAA==.',
Mc='Mcfürry:BAABLgAECn8VAAIKAAcJyBu5KADSAQAKAAcJyBu5KADSAQAAAA==.',
Me='Mebedir:BAAALgAECgMJBQAAAA==.Meekal:BAAALgADCgEJAQAAAA==.Melithia:BAAALgAECgcJBwAAAA==.Mels:BAAALgAECgQJBgAAAA==.Mendinna:BAABLgAECn8rAAIVAAgJeRCGFwBwAQAVAAgJeRCGFwBwAQAAAA==.Mercs:BAAALgADCgQJBQABLgAECgUJFAAGAJYQAA==.Methir:BAAALgADCgYJCQAAAA==.',
Mi='Miffed:BAAALgAECggJEgABLgAFFAUJGwAiAJUVAA==.Mildew:BAAALgADCgYJBgAAAA==.Mincksie:BAAALgAECggJEQAAAA==.Mininetty:BAAALgADCgcJBwABLgAECgUJBQASAAAAAA==.Mirage:BAABLgAECn8VAAIaAAcJhiMPFwBSAgAaAAcJhiMPFwBSAgAAAA==.Misfired:BAAALgADCgIJAgAAAA==.Mistbot:BAABLgAECn8wAAILAAkJMyDTBQC7AgALAAkJMyDTBQC7AgAAAA==.',
Mo='Montebrew:BAAALgAECgYJBgAAAA==.Mooky:BAABLgAECn8oAAIJAAkJ9Q9EGgCtAQAJAAkJ9Q9EGgCtAQAAAA==.Moovitz:BAAALgADCgYJBgAAAA==.Mopeia:BAABLgAECn8dAAIKAAYJghfcMwCRAQAKAAYJghfcMwCRAQABLgAECgYJEwASAAAAAA==.Mord:BAAALgAECgUJDAAAAA==.Mork:BAAALgADCgMJAwABLgAECgYJIQAPALcjAA==.Mortemore:BAACLgAFFH8RAAIWAAUJ4hfLKgAqAQAWAAUJ4hfLKgAqAQAuAAQKfyQAAhYACQkSINAYAEgCABYACQkSINAYAEgCAAAA.Mortlee:BAAALgAECgEJAQABLgAFFAUJEQAWAOIXAA==.Motet:BAAALgAECgYJCwAAAA==.',
Mu='Muikkie:BAAALgAECgEJAgAAAA==.Mulro:BAAALgADCgMJAwAAAA==.Muncher:BAAALgAECgkJEgAAAA==.',
My='Mymage:BAAALgADCgEJAQAAAA==.Mynoghra:BAAALgAECgYJEgAAAA==.Mynxx:BAAALgAECgcJCQAAAA==.Mystrax:BAAALgADCgIJAgAAAA==.',
Na='Nadoral:BAAALgADCgYJCwAAAA==.Naproxen:BAABLgAECn8uAAIgAAkJABxeBgCNAgAgAAkJABxeBgCNAgAAAA==.Naraku:BAACLgAFFH8RAAMYAAUJBRbcKABEAQAYAAUJyRXcKABEAQAXAAEJFhKxFABVAAAuAAQKfy4AAxgACAlsIT0eAKECABgACAnnID0eAKECABcABglbHugNAOcBAAAA.Narberal:BAAALgADCgEJAQAAAA==.Nastager:BAAALgADCgcJBwAAAA==.Naxx:BAAALgADCgIJAgAAAA==.Nazgül:BAAALgADCgMJAgAAAA==.',
Ne='Necroseeker:BAAALgAECgYJCwAAAA==.Negativity:BAAALgAECgYJBgAAAA==.Nettie:BAAALgAECgUJBQAAAA==.Netty:BAAALgAECgIJAgABLgAECgUJBQASAAAAAA==.',
Ni='Nightshaulea:BAAALgAECgUJBgAAAA==.Niklaus:BAABLgAECn8dAAIDAAcJdhZVaACvAQADAAcJdhZVaACvAQAAAA==.Nilisha:BAAALgADCgIJAgAAAA==.Nimi:BAAALgAECgEJAQAAAA==.Nirala:BAAALgADCgkJCQAAAA==.',
No='Nosferatmoo:BAAALgADCgkJCQABLgADCgkJEwASAAAAAA==.',
Nu='Nusy:BAAALgADCgYJBgAAAA==.',
Ny='Nymeera:BAABLgAECn8nAAMfAAkJlwZMIADcAAAfAAkJWQZMIADcAAAeAAIJPANiLwBKAAAAAA==.Nymphetamine:BAABLgAECn8wAAMCAAkJxxjqCwBnAgACAAkJxxjqCwBnAgATAAQJ4AROQgCcAAAAAA==.Nyxarya:BAAALgADCgcJBwAAAA==.',
Nz='Nzoth:BAABLgAECn8gAAIFAAkJGRC3HACXAQAFAAkJGRC3HACXAQAAAA==.',
Ob='Obnixilis:BAABLgAECn8VAAIPAAYJXRjgbgCrAQAPAAYJXRjgbgCrAQABLgAECggJEgASAAAAAA==.',
Od='Odessa:BAAALgAECgEJAQAAAA==.',
Ok='Okin:BAAALgAECgMJAwAAAA==.',
Om='Omadruid:BAAALgADCgYJBgAAAA==.Omapriest:BAAALgADCgUJBQAAAA==.Omashamwow:BAAALgAECgQJBQAAAA==.Omorc:BAABLgAECn8kAAIEAAgJ1BBTCwBtAQAEAAgJ1BBTCwBtAQAAAA==.',
On='Oneyeli:BAAALgADCgYJBgAAAA==.Oniony:BAAALgADCgYJCwAAAA==.Onos:BAAALgAECgMJAwAAAA==.',
Or='Ordlok:BAAALgADCgcJCQAAAA==.Orlaith:BAAALgADCgUJBQABLgAECggJHQAWAEkcAA==.',
Ow='Owenwilson:BAAALgAECgEJAgAAAA==.Owful:BAAALgAECgQJBQAAAA==.',
Pa='Pandaloca:BAAALgAECgUJBQAAAA==.Pandaloco:BAAALgADCgcJBwAAAA==.Pandalôc:BAAALgAECgIJAgAAAA==.Pandoe:BAABLgAECn8UAAQfAAgJbxdTDAC/AQAfAAYJaB9TDAC/AQAJAAgJrA6nMACDAQAKAAEJngeR3AAmAAAAAA==.Papaya:BAACLgAFFH8dAAIKAAcJTyCaAQD+AQAKAAcJTyCaAQD+AQAuAAQKfyIAAwoACQnZIcMGAB8DAAoACQnZIcMGAB8DAAkABwliIZYjAOABAAAA.Pawpawpiddle:BAAALgAECgYJBgAAAA==.',
Pe='Penelopea:BAABLgAECn8kAAIBAAgJ4xV9RwDLAQABAAgJ4xV9RwDLAQAAAA==.Perlen:BAAALgADCgYJBgAAAA==.Perun:BAAALgAECgYJDQAAAA==.',
Ph='Phaith:BAAALgADCgUJCwAAAA==.Phenomenal:BAAALgAECgEJAQABLgAECggJIAAOAO4bAA==.',
Pl='Plaguedealer:BAAALgADCgUJBQAAAA==.',
Po='Porteagarder:BAABLgAECn8VAAIHAAYJmgY8ZgDNAAAHAAYJmgY8ZgDNAAABLgAECgcJHAAKAJ8JAA==.Potatodruid:BAAALgAECgQJDQAAAA==.Power:BAAALgADCgYJBgAAAA==.',
Pr='Preparedpie:BAAALgAECgkJDQAAAA==.Preront:BAACLgAFFH8rAAMjAAkJJyAMAADGAgAjAAkJcR0MAADGAgAOAAgJBxs2AgBLAgAuAAQKfyIABCMACQngJikAAOYDACMACQngJikAAOYDAA4AAwksJq4+AFABAAcAAwkVG1tdAOwAAAAA.Priestbrume:BAAALgADCgUJBQAAAA==.Pringler:BAAALgAECgQJBAABLgAFFAcJHgAZAHMjAA==.Producktive:BAABLgAECn8bAAIiAAgJMxXCEAC6AQAiAAgJMxXCEAC6AQAAAA==.Prometeus:BAAALgADCggJCAAAAA==.Pros:BAABLgAECn8iAAIXAAkJWRRZDQDvAQAXAAkJWRRZDQDvAQAAAA==.Pruulia:BAAALgADCgkJDAABLgAECggJJAAJAHoNAA==.Príestly:BAAALgAECgUJBgAAAA==.',
Ps='Psydúck:BAAALgADCgcJDQAAAA==.',
Pu='Puffdamagic:BAABLgAECn8aAAImAAgJ1BsuEgARAgAmAAgJ1BsuEgARAgABLgAFFAUJEQAWAOIXAA==.Puffthemagic:BAAALgAECggJDQAAAA==.Purentity:BAAALgAECgYJCwAAAA==.',
Py='Pyatt:BAABLgAECn8rAAIMAAgJNh2aAwAgAgAMAAgJNh2aAwAgAgAAAA==.',
['Pú']='Púff:BAAALgADCgEJAQAAAA==.',
Qu='Quack:BAAALgAECggJEQAAAA==.Quackadin:BAAALgADCgYJCwABLgAECggJEQASAAAAAA==.Quackula:BAAALgAECgcJBgAAAA==.Quilae:BAAALgAECgUJCQABLgAECgcJHAAKAJ8JAA==.Quiny:BAAALgADCgMJAQAAAA==.',
Ra='Raerlynn:BAEALgADCgMJAwAAAA==.Ragnix:BAAALgAECgEJAQAAAA==.Randivh:BAAALgAECgIJAgAAAA==.Rassputin:BAABLgAECn8mAAIBAAkJ5xaGLwAgAgABAAkJ5xaGLwAgAgAAAA==.Ravnmoon:BAAALgAECgUJBQAAAA==.Razzleyi:BAAALgADCgkJKwAAAA==.',
Re='Realmack:BAAALgAECggJDAABLgAFFAMJAwASAAAAAA==.Rebuke:BAAALgAECgYJBgAAAA==.Reclaimblade:BAAALgADCgUJBQAAAA==.Reclaimdrunk:BAAALgAECgIJAgAAAA==.Reclaimergun:BAAALgADCgEJAQAAAA==.Reclaimholy:BAAALgADCgUJBQAAAA==.Reclaimsage:BAAALgADCgYJBQAAAA==.Reigwend:BAAALgADCggJDwAAAA==.Reisharra:BAAALgAECgUJCgAAAA==.Relimas:BAAALgADCgcJEAAAAA==.Remish:BAAALgAECgQJBAAAAA==.Rendezvous:BAAALgAECgEJBAAAAA==.Renkà:BAAALgAECgQJBAABLgAECggJKQAaANYYAA==.Requestor:BAAALgAECgUJBQABLgAECggJEgASAAAAAA==.Resmondo:BAAALgADCgQJBAAAAA==.Ret:BAACLgAFFH8LAAIDAAQJ+gqTMAAbAQADAAQJ+gqTMAAbAQAuAAQKfyoAAgMACAkhG4suAGkCAAMACAkhG4suAGkCAAAA.Revaerlous:BAABLgAECn8uAAIPAAkJiR2VKwAXAgAPAAkJiR2VKwAXAgAAAA==.',
Rh='Rheas:BAAALgADCgYJDQABLgAECggJEwASAAAAAA==.Rhei:BAABLgAECn8RAAIWAAgJIBkbLgBEAgAWAAgJIBkbLgBEAgAAAA==.',
Ri='Ribeye:BAACLgAFFH8bAAIiAAUJlRXkAwAVAQAiAAUJlRXkAwAVAQAuAAQKfykAAiIACQlPFroMAK0BACIACQlPFroMAK0BAAAA.',
Ro='Roereker:BAABLgAECn8wAAIDAAkJ+BeVJAA1AgADAAkJ+BeVJAA1AgAAAA==.Roguesamurai:BAAALgADCgEJAQAAAA==.Rohhenge:BAAALgADCgkJDwAAAA==.Roketraccoon:BAAALgAECgMJBwAAAA==.Romoxodus:BAAALgADCgUJCQAAAA==.Rongbip:BAABLgAECn8bAAIgAAkJXhokDgASAgAgAAkJXhokDgASAgAAAA==.Roshamandes:BAABLgAECn8eAAINAAgJsh8hAwBxAgANAAgJsh8hAwBxAgAAAA==.Rotigus:BAAALgADCgUJBQAAAA==.',
Ru='Rubadubdubz:BAAALgADCgMJAwAAAA==.Runep:BAABLgAECn8rAAIDAAkJbyAeDADWAgADAAkJbyAeDADWAgAAAA==.',
['Rè']='Rèi:BAAALgAECgIJAgABLgAECggJJgARAF8iAA==.',
['Ré']='Réstofarian:BAACLgAFFH8UAAIKAAQJIB6WFQBXAQAKAAQJIB6WFQBXAQAuAAQKfy0AAwoACQm0I1sCAHYDAAoACQm0I1sCAHYDAAkAAgkoGexmAIYAAAAA.',
Sa='Sabbier:BAAALgADCgcJBwAAAA==.Sacredchikín:BAABLgAECn8ZAAIYAAgJvRtVJQAXAgAYAAgJvRtVJQAXAgAAAA==.Saiki:BAAALgAECgQJBQAAAA==.Sanataanna:BAAALgADCgUJCwABLgAECggJEwASAAAAAA==.Sandvichus:BAABLgAECn8eAAIJAAkJDSFIBwClAgAJAAkJDSFIBwClAgAAAA==.Sanitarìum:BAAALgAECgQJCAAAAA==.Sardine:BAAALgAECgcJDgABLgAFFAcJHQAKAE8gAA==.Sasukie:BAAALgAECgEJBQAAAA==.Savagesmonk:BAAALgAECgUJBgAAAA==.Saxa:BAABLgAECn8lAAIVAAkJ1SIKBQCxAgAVAAkJ1SIKBQCxAgAAAA==.',
Sc='Scratchnsnif:BAAALgADCgUJBQAAAA==.',
Se='Sefik:BAAALgAECgYJDQAAAA==.Selaana:BAABLgAECn8YAAIOAAYJPh9nIgD8AQAOAAYJPh9nIgD8AQAAAA==.Serkis:BAAALgAECgcJBQAAAA==.Seyekosis:BAAALgAECgcJDwAAAA==.',
Sg='Sgathaich:BAEBLgAECn8lAAIcAAgJdhnaGwDkAQAcAAgJdhnaGwDkAQAAAA==.',
Sh='Shaan:BAAALgADCgMJAwAAAA==.Shadtae:BAAALgAECgYJCgABLgAECgkJLAAHAKgXAA==.Shaio:BAABLgAECn8VAAILAAYJ3Q9hNgBGAQALAAYJ3Q9hNgBGAQAAAA==.Shallistiah:BAAALgADCgkJGgABLgAECggJKQAdAJAiAA==.Shamadin:BAAALgADCgkJCQAAAA==.Shambrume:BAAALgAECgYJDgAAAA==.Shambulence:BAACLgAFFH8LAAIHAAQJggztJAD/AAAHAAQJggztJAD/AAAuAAQKfxQAAwcACQlGFBYaADECAAcACQlGFBYaADECACMAAgnQF0UeAJAAAAAA.Shammlock:BAACLgAFFH8TAAQMAAUJYBB+AQCvAAAYAAMJYxFOUwDcAAAMAAQJ+xB+AQCvAAAXAAIJxwJvHABCAAAuAAQKfygABAwACQmCHuECAIMCAAwACAkTH+ECAIMCABgACQnDGS0qAGcCABcABQl6EFskADgBAAAA.Shampriest:BAAALgAECggJCAAAAA==.Shamuel:BAABLgAECn8XAAIgAAkJaRNgCwA3AgAgAAkJaRNgCwA3AgAAAA==.Shaylis:BAAALgAECgcJCQABLgAECggJKQAaANYYAA==.Sheji:BAAALgADCgkJHAAAAA==.Shiggy:BAAALgAECgQJBQABLgAECgkJIwAIAAUcAA==.Shobadon:BAAALgAECggJCAAAAA==.Shole:BAABLgAECn81AAMOAAkJGB6VDABeAgAOAAkJGB6VDABeAgAHAAcJFBzHHQAVAgAAAA==.Shulanii:BAAALgAECgMJBQAAAA==.',
Si='Siatral:BAAALgAECgEJAQABLgAECgkJKgATAFwjAA==.Siggopotomus:BAAALgADCgUJBQABLgAECggJEwASAAAAAA==.Sigvalden:BAAALgAECggJEwAAAA==.Sigvolden:BAAALgAECgcJAgABLgAECggJEwASAAAAAA==.Silchar:BAAALgADCgUJAQAAAA==.Silicon:BAABLgAECn8hAAIBAAkJjhIpSwDAAQABAAkJjhIpSwDAAQAAAA==.Sinfulangel:BAABLgAECn8qAAIPAAgJpRt2KgAcAgAPAAgJpRt2KgAcAgAAAA==.Siona:BAABLgAECn80AAIRAAkJigv7QACYAQARAAkJigv7QACYAQAAAA==.',
Sk='Skadie:BAABLgAECn8kAAMRAAkJMBVULADnAQARAAkJMBVULADnAQAEAAEJ6wPSNQAkAAAAAA==.Skialin:BAAALgAECgEJAQAAAA==.Skiye:BAAALgADCggJDgAAAA==.Skwop:BAAALgAECgEJAgABLgAFFAMJAwASAAAAAA==.Skyler:BAABLgAECn8UAAInAAcJER39AgAzAgAnAAcJER39AgAzAgAAAA==.',
Sl='Slackness:BAAALgAECgMJBgAAAA==.Slavalous:BAAALgAECgUJCgAAAA==.',
Sn='Snakeshifter:BAAALgADCgUJBQAAAA==.Snakesoul:BAAALgAECgMJBAAAAA==.Snivels:BAABLgAECn8fAAIfAAgJsRDIEgBFAQAfAAgJsRDIEgBFAQAAAA==.Snnorri:BAAALgADCggJFgABLgAECggJKQAdAJAiAA==.',
So='Sodtaoe:BAAALgADCgcJDQAAAA==.Solsilvesti:BAAALgADCgMJAwAAAA==.',
Sp='Sparrkle:BAABLgAECn8lAAIXAAgJFAvkDQAcAQAXAAgJFAvkDQAcAQAAAA==.Spin:BAAALgADCgMJAwAAAA==.Spinecrawler:BAAALgAECgIJAgAAAA==.Spinjitzu:BAAALgAECgMJCgAAAA==.Spiritshift:BAAALgAECgEJAQAAAA==.Spyro:BAAALgAECgMJCgAAAA==.',
Sq='Squadw:BAACLgAFFH8WAAIVAAUJPyDXAwB2AQAVAAUJPyDXAwB2AQAuAAQKf0AAAhUACQkBJVEBAD0DABUACQkBJVEBAD0DAAAA.',
Ss='Sski:BAAALgADCgEJAQAAAA==.',
St='Starblast:BAAALgAECgYJEwABLgAECgYJBwASAAAAAA==.Starrskrream:BAAALgAECgQJBgAAAA==.Steamworks:BAAALgADCgcJBwAAAA==.Steelrat:BAAALgADCgcJAgAAAA==.Stellanova:BAAALgADCgQJBAAAAA==.Stiick:BAABLgAECn8tAAIiAAkJoRbZCQDjAQAiAAkJoRbZCQDjAQAAAA==.Stormhide:BAAALgADCgEJAgAAAA==.Streakycat:BAEALgAECgEJAQAAAA==.Stupidgnome:BAAALgADCgcJCgAAAA==.',
Su='Subsizzle:BAAALgAECgMJAwABLgAECgcJEgASAAAAAA==.Subzerow:BAAALgADCgYJBgAAAA==.Sudsy:BAAALgAECgIJAgABLgAECgcJEQASAAAAAA==.Sujin:BAAALgAECgMJAwAAAA==.Sunarra:BAABLgAECn8dAAIWAAgJSRx7MgC+AQAWAAgJSRx7MgC+AQAAAA==.Sunsmite:BAABLgAECn8dAAIDAAcJrha9ZgBlAQADAAcJrha9ZgBlAQAAAA==.Suramar:BAABLgAECn8XAAIZAAgJABWgEQCNAQAZAAgJABWgEQCNAQAAAA==.',
Sw='Sweetbippy:BAABLgAECn8kAAIBAAgJrwEe0AC5AAABAAgJrwEe0AC5AAAAAA==.Swifthealss:BAABLgAECn8YAAMKAAgJewZhVgD/AAAKAAgJewZhVgD/AAAJAAUJ3goFRQCvAAAAAA==.Swirls:BAAALgAECgEJAgAAAA==.',
Sy='Sygvalden:BAAALgAECgYJDAABLgAECggJEwASAAAAAA==.Sylunae:BAAALgAECgIJAgABLgAECgcJHAAKAJ8JAA==.Syluné:BAABLgAECn8cAAIKAAcJnwn+ZADOAAAKAAcJnwn+ZADOAAAAAA==.Syläs:BAAALgAECgYJEwAAAA==.Syndrassil:BAABLgAECn8hAAIBAAgJoQoGcQBhAQABAAgJoQoGcQBhAQAAAA==.',
['Sù']='Sùccubus:BAAALgADCgQJBAAAAA==.',
Ta='Tacodog:BAAALgAECgUJCgABLgAECgkJKQADAD4mAA==.Tacomonk:BAAALgAECggJCgAAAA==.Tacozpriest:BAAALgAECgYJBgABLgAECggJCgASAAAAAA==.Taelight:BAAALgADCggJDgABLgAECgkJLAAHAKgXAA==.Taelyx:BAABLgAECn8sAAMHAAkJqBc8KADSAQAHAAkJqBc8KADSAQAOAAIJ3gkQfgBOAAAAAA==.Taicheeze:BAABLgAECn8aAAIGAAgJZhaEFADVAQAGAAgJZhaEFADVAQAAAA==.Tambot:BAAALgAECgQJDQAAAA==.Tariced:BAAALgAECgQJBAAAAA==.Tarvaron:BAAALgADCgEJAQAAAA==.Taytra:BAAALgADCgkJJQABLgAECggJJAABAK8BAA==.Tazmina:BAACLgAFFH8HAAIVAAMJQhdxDAD8AAAVAAMJQhdxDAD8AAAuAAQKfysAAhUACQnLH/MHAOQCABUACQnLH/MHAOQCAAAA.',
Te='Teal:BAAALgADCgYJCgAAAA==.Tehssa:BAAALgAECgEJAQABLgAECgkJLQAOAHsaAA==.Tessa:BAABLgAECn8tAAIOAAkJexpEDABiAgAOAAkJexpEDABiAgAAAA==.Texasfight:BAAALgADCgIJAgABLgAECggJPQAIAPwYAA==.Teyo:BAAALgAECgQJDgAAAA==.',
Th='Thedoctorwho:BAAALgAFFAEJAQAAAA==.Theholytaz:BAABLgAECn8XAAIDAAgJDBZkQQAhAgADAAgJDBZkQQAhAgAAAA==.Thunderr:BAAALgAECgcJCAAAAA==.Thörn:BAAALgAECgcJEwABLgAECggJJwAKAOcUAA==.',
Ti='Time:BAAALgAECgMJAwAAAA==.Tinyjapeto:BAAALgAECgMJAwAAAA==.Titanbow:BAAALgADCgYJBgABLgAECgkJMAAWAK8fAA==.',
To='Tomcatt:BAABLgAECn81AAIRAAkJZCCZCwC8AgARAAkJZCCZCwC8AgAAAA==.Tonshaw:BAAALgAECgYJBgAAAA==.Toome:BAAALgADCgUJBQAAAA==.',
Tr='Trailis:BAAALgAECgMJBAAAAA==.Travalden:BAAALgADCgMJAwAAAA==.Trekkie:BAAALgAECgUJBQABLgAFFAUJGwAiAJUVAA==.Treè:BAAALgAECgMJCgAAAA==.Trioxinn:BAAALgADCgEJAQAAAA==.',
Tu='Tuddlly:BAAALgAECgUJCgAAAA==.Turin:BAABLgAECn8dAAIZAAgJQASJJgDAAAAZAAgJQASJJgDAAAAAAA==.Tutonik:BAAALgADCgUJBQAAAA==.Tuubarkk:BAAALgADCgcJCAAAAA==.',
Tw='Twilghtdawn:BAABLgAECn8kAAIhAAgJKReLEAC3AQAhAAgJKReLEAC3AQAAAA==.Twos:BAAALgAECgEJAQAAAA==.Twotone:BAAALgADCgMJAwAAAA==.',
Ty='Tybo:BAABLgAECn8kAAIjAAkJPyGfAQDrAgAjAAkJPyGfAQDrAgAAAA==.Tybs:BAAALgADCgEJAQAAAA==.',
Un='Uncás:BAABLgAECn8VAAIRAAYJIgdZeAD+AAARAAYJIgdZeAD+AAAAAA==.Ungieblinks:BAAALgAECgQJBAAAAA==.Ungislayer:BAAALgADCgMJAwAAAA==.Unglifettv:BAABLgAECn8UAAImAAgJMReOFwDbAQAmAAgJMReOFwDbAQAAAA==.Unstable:BAAALgAECgQJBgABLgAECgcJBwASAAAAAA==.',
Up='Upchucky:BAAALgADCgYJBwAAAA==.',
Ur='Urulóki:BAAALgAECgcJBwAAAA==.',
Va='Vaedeath:BAABLgAECn8tAAIhAAkJ7h84BgCGAgAhAAkJ7h84BgCGAgAAAA==.Vaina:BAAALgADCgMJAwAAAA==.Vainagos:BAAALgAECgUJBgAAAA==.Valaryon:BAAALgADCgkJHgAAAA==.Valkorin:BAAALgAECgYJBwAAAA==.Valoryan:BAABLgAECn81AAIKAAkJghWVGQA8AgAKAAkJghWVGQA8AgAAAA==.Valyteilssra:BAAALgAECgMJCAAAAA==.Vanity:BAAALgAECgEJAQAAAA==.Varindra:BAAALgAECgMJBAABLgAECgkJKgATAFwjAA==.',
Ve='Vegà:BAABLgAECn8fAAIGAAgJLRHuIABtAQAGAAgJLRHuIABtAQAAAA==.Veina:BAAALgADCgQJCAAAAA==.Velyndris:BAAALgAECgYJCwAAAA==.Velysia:BAAALgADCgMJAwAAAA==.Vendettis:BAAALgADCgYJBgAAAA==.Verin:BAAALgAECgMJBQAAAA==.Vetraugr:BAAALgADCgMJAwABLgAECgYJDQASAAAAAA==.Vextaerin:BAAALgAECgYJDQAAAA==.Vextarin:BAAALgADCgEJAQABLgAECgYJDQASAAAAAA==.Veylyn:BAAALgADCgEJAQAAAA==.',
Vi='Virulent:BAAALgADCgMJAwAAAA==.Vivienreed:BAAALgAECgEJAgABLgAFFAQJCwAlABUMAA==.',
Vo='Voidhax:BAAALgAECgUJBQAAAA==.Voidi:BAABLgAECn8XAAQaAAcJVyOsFQBiAgAaAAcJtCKsFQBiAgAkAAQJESEBDQBPAQAnAAEJtAOkDwAoAAAAAA==.Voidyo:BAABLgAFFH8JAAIWAAMJ0xxKNwAEAQAWAAMJ0xxKNwAEAQAAAA==.Voralyth:BAAALgADCggJCQAAAA==.Voranne:BAABLgAECn8gAAIFAAgJwQm/KABBAQAFAAgJwQm/KABBAQAAAA==.Vortice:BAABLgAECn8/AAQOAAkJrxKdJgBuAQAOAAgJIhGdJgBuAQAHAAgJ8w0VRgBCAQAjAAIJQAfbKABOAAAAAA==.Vowwel:BAAALgAECgEJAQAAAA==.',
Vy='Vyserlai:BAAALgADCgUJBQAAAA==.',
Wa='War:BAAALgADCgUJAwAAAA==.Ware:BAAALgADCgcJBwAAAA==.Warraxgos:BAAALgADCgkJHgABLgAECgkJIAAVAHMdAA==.Warraxhunt:BAAALgAECgEJAQABLgAECgkJIAAVAHMdAA==.Warraxmonk:BAAALgADCgYJBgABLgAECgkJIAAVAHMdAA==.',
We='Weißenacht:BAAALgAECgMJAwAAAA==.',
Wh='Wheatstraw:BAAALgADCgUJBwAAAA==.Whiskeyjak:BAABLgAECn8bAAMIAAgJQho0KQBzAQAIAAgJDw80KQBzAQAZAAMJoh+tHgD7AAAAAA==.',
Wi='Willowest:BAABLgAECn8kAAIRAAgJuBopIwASAgARAAgJuBopIwASAgAAAA==.',
Wr='Wrathstorm:BAABLgAECn8mAAIjAAgJTx1iBgAkAgAjAAgJTx1iBgAkAgAAAA==.Wrekonhoof:BAAALgAECgEJAQAAAA==.',
Wt='Wtfpie:BAACLgAFFH8VAAIPAAUJSxc4GABEAQAPAAUJSxc4GABEAQAuAAQKfzQAAg8ACQkpI2cNAM8CAA8ACQkpI2cNAM8CAAAA.',
Wu='Wurmoneonine:BAAALgADCgUJBQABLgAECgkJMAAKAIYXAA==.Wurmy:BAABLgAECn8wAAMKAAkJhhcYFwBRAgAKAAkJhhcYFwBRAgAJAAYJSBO7LwATAQAAAA==.',
Wy='Wyndrunner:BAAALgADCgkJCQABLgAECgkJLQARAHUMAA==.',
['Wá']='Wárgbáte:BAAALgADCgcJBwAAAA==.',
Xa='Xalgas:BAABLgAECn8YAAIFAAYJaxaVKwB/AQAFAAYJaxaVKwB/AQAAAA==.Xanier:BAAALgAECgQJCAAAAA==.',
Xe='Xelagos:BAABLgAECn8eAAQUAAgJchIjFwAeAQAUAAcJdBEjFwAeAQAlAAMJCBzBJgDsAAAmAAMJ5BWvUwB4AAAAAA==.Xerxesjr:BAAALgADCgEJAQAAAA==.',
Ya='Yanella:BAABLgAECn8eAAMCAAgJ/hMlHACoAQACAAgJ/hMlHACoAQATAAEJcwWmWgAtAAAAAA==.',
Yi='Yispally:BAAALgAECgQJCQAAAA==.Yisshaman:BAABLgAECn8eAAIOAAkJXhvZDADQAgAOAAkJXhvZDADQAgAAAA==.',
Yo='Yogibearz:BAAALgAECgQJBwABLgAECgUJFAAGAJYQAA==.Yogimonk:BAABLgAECn8UAAIGAAUJlhBCQQDGAAAGAAUJlhBCQQDGAAAAAA==.',
Za='Zanax:BAAALgAECgQJBAAAAA==.Zandarbribbs:BAABLgAECn8WAAIDAAYJixaBegA8AQADAAYJixaBegA8AQAAAA==.Zapzug:BAAALgADCgYJDQAAAA==.Zaratras:BAAALgAECgEJAQAAAA==.Zaydozer:BAAALgADCgkJFAAAAA==.',
Ze='Zenmetsu:BAAALgAECgUJBgAAAA==.Zennya:BAABLgAECn8hAAIKAAgJMRgoIQADAgAKAAgJMRgoIQADAgAAAA==.Zeon:BAAALgAECgYJEQAAAA==.',
Zi='Zikoth:BAAALgADCgEJAQAAAA==.Zingers:BAAALgAECgMJAwAAAA==.',
Zm='Zmd:BAAALgAECgYJEQAAAA==.',
Zo='Zoeso:BAABLgAECn81AAMGAAkJ9x7IBADLAgAGAAkJ9x7IBADLAgAdAAUJyQ6+PwDmAAAAAA==.',
Zt='Ztropos:BAAALgAECgcJBwAAAA==.',
Zy='Zygal:BAAALgAECgMJBwAAAA==.',
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
