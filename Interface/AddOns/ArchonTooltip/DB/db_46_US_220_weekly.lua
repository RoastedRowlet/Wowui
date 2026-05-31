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

local lookup = {'Mage-Frost','Priest-Holy','Priest-Discipline','Paladin-Retribution','Hunter-Marksmanship','Priest-Shadow','Monk-Brewmaster','Shaman-Restoration','Warrior-Fury','Druid-Balance','Druid-Restoration','Monk-Windwalker','Warlock-Affliction','Warrior-Protection','DemonHunter-Vengeance','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Frost','Hunter-BeastMastery','Unknown-Unknown','Monk-Mistweaver','Evoker-Preservation','DemonHunter-Havoc','DemonHunter-Devourer','Warlock-Destruction','Warlock-Demonology','Rogue-Subtlety','Warrior-Arms','Paladin-Holy','Druid-Feral','Druid-Guardian','Hunter-Survival','DeathKnight-Blood','Paladin-Protection','Shaman-Enhancement','Rogue-Assassination','Evoker-Devastation','Evoker-Augmentation','Rogue-Outlaw',}
local provider = {region='US',realm='Thunderhorn',name='US',type='weekly',zone=46,date='2026-05-31',data={Ab='Absynthe:BAAALgAECgYJCwAAAA==.Abysmal:BAAALgADCgYJBgABLgAECgkJIwABAEoOAA==.Abÿss:BAAALgAECgMJCAAAAA==.',
Ac='Achêrøn:BAAALgADCgcJBwAAAA==.Acoghai:BAAALgADCgcJDQAAAA==.',
Ad='Adoweld:BAAALgADCgcJBQAAAA==.Adøland:BAAALgADCgYJBgAAAA==.',
Ae='Aeliis:BAABLgAECn8lAAMCAAkJ5AyqJwB1AQACAAkJ5AyqJwB1AQADAAMJbQRmVQB5AAAAAA==.Aellart:BAAALgAECgEJAgAAAA==.Aeriona:BAABLgAECn8vAAIEAAkJehusIQBqAgAEAAkJehusIQBqAgAAAA==.Aerosoul:BAAALgADCgEJAQAAAA==.',
Ag='Agamsi:BAABLgAECn8UAAIFAAgJcwv4FQD0AAAFAAgJcwv4FQD0AAAAAA==.',
Ai='Aine:BAABLgAECn8kAAMCAAgJgBYCHADRAQACAAcJphkCHADRAQAGAAYJ6wA/WABcAAAAAA==.Ainek:BAAALgAECgUJBwAAAA==.Ainkor:BAAALgAECgYJCAABLgAFFAMJBwAHADsNAA==.',
Aj='Ajani:BAAALgAECggJEwAAAA==.',
Ak='Akyospirit:BAABLgAECn82AAIIAAkJwwxiPwCWAQAIAAkJwwxiPwCWAQAAAA==.Akyowindz:BAAALgAECgQJBAAAAA==.',
Al='Al:BAAALgAECgYJEAABLgAECgkJKgAJAAUcAA==.Alava:BAAALgADCgEJAQAAAA==.Aliatra:BAABLgAECn87AAMKAAkJ6hHEGwDTAQAKAAkJ6hHEGwDTAQALAAEJmgic5AAfAAAAAA==.Alinth:BAAALgAECgMJBQAAAA==.Almosthuman:BAAALgAECgYJCgAAAA==.Alpha:BAABLgAECn86AAIBAAkJoh0cGQCuAgABAAkJoh0cGQCuAgAAAA==.Alroy:BAAALgAECgkJCwAAAA==.Aluina:BAAALgAFFAEJAQAAAA==.Alustryelle:BAAALgADCgkJCQABLgAECggJJAAIAHcHAA==.Alykia:BAAALgADCgYJBgAAAA==.',
Am='Amamonk:BAABLgAECn89AAMHAAkJvRWJFAD7AQAHAAkJDRWJFAD7AQAMAAQJzBcCOAAMAQAAAA==.Amandara:BAAALgADCgUJBQAAAA==.Ammert:BAABLgAECn8uAAINAAkJ/w9fBwDcAQANAAkJ/w9fBwDcAQAAAA==.Amonet:BAAALgADCgYJEQAAAA==.',
An='Anchovy:BAAALgAFFAEJAQABLgAFFAgJJQAOAJojAA==.Andou:BAAALgADCgcJBwAAAA==.Angeldracul:BAAALgADCgQJBwAAAA==.Angelove:BAAALgAECgQJDAAAAA==.Anglico:BAAALgAECgQJBQABLgAECgkJJwAPAMwgAA==.Angliko:BAAALgAECgUJCAABLgAECgkJJwAPAMwgAA==.Anglikoo:BAAALgADCggJCAABLgAECgkJJwAPAMwgAA==.Anomandaris:BAABLgAECn8eAAMQAAkJVBUcIwC2AQAQAAgJ4RYcIwC2AQAIAAEJTAa1xgArAAAAAA==.Anquan:BAABLgAECn8hAAIRAAcJVRsXRADlAQARAAcJVRsXRADlAQAAAA==.',
Ap='Apedemak:BAAALgAECgYJDAAAAA==.Aphobias:BAAALgAECgUJCwAAAA==.Aphradite:BAAALgADCgYJCwAAAA==.Apothica:BAAALgAECgIJAgAAAA==.Apothicc:BAABLgAECn8kAAMRAAgJVhaUQADwAQARAAgJVhaUQADwAQASAAEJAABgPAAAAAAAAA==.Appalonio:BAAALgADCgcJBQAAAA==.Appaur:BAAALgADCgEJAQAAAA==.Appolymi:BAABLgAECn8tAAITAAkJaQVzZABmAQATAAkJaQVzZABmAQAAAA==.Apraxia:BAAALgADCgUJBQAAAA==.Aprionos:BAABLgAECn8wAAIBAAgJ3QUsqQATAQABAAgJ3QUsqQATAQAAAA==.',
Ar='Arakek:BAAALgADCgcJCAAAAA==.Arataena:BAAALgADCgkJFgAAAA==.Arceus:BAAALgAECgMJBQAAAA==.Aredhël:BAAALgADCgYJDgAAAA==.Argentavis:BAAALgAECggJEgABLgAECggJEwAUAAAAAA==.Argobow:BAAALgAECgQJBwAAAA==.Argonaut:BAAALgAFFAIJAgAAAA==.Arice:BAEALgAECgEJAQABLgAECgkJMgARAP0cAA==.Aristella:BAAALgADCgMJAwAAAA==.Arkken:BAABLgAECn8UAAIVAAYJiiSjEgBqAgAVAAYJiiSjEgBqAgABLgAECgkJRQADAJUjAA==.Artee:BAAALgAECgEJAQAAAA==.Artémis:BAABLgAECn8iAAITAAgJgRBbXQB3AQATAAgJgRBbXQB3AQAAAA==.',
As='Ascender:BAAALgAECgQJBAAAAA==.Ashadox:BAAALgAECgUJCQAAAA==.Asheritâ:BAAALgADCgcJBwAAAA==.Ashvalis:BAABLgAECn8cAAIWAAcJzSPFCQCaAgAWAAcJzSPFCQCaAgAAAA==.Asillyhunter:BAAALgADCgMJAwAAAA==.Asillypally:BAABLgAECn8kAAIEAAgJeBYaXgDJAQAEAAgJeBYaXgDJAQAAAA==.Askr:BAABLgAECn8qAAMTAAkJExEzNQD0AQATAAkJ6RAzNQD0AQAFAAYJnwq1HQCuAAAAAA==.Asphar:BAABLgAECn8vAAMTAAkJuiW2AgBdAwATAAkJuiW2AgBdAwAFAAMJChPqKABkAAAAAA==.Asteroth:BAAALgAECgEJAQAAAA==.',
Au='Aung:BAACLgAFFH8OAAIXAAQJ6SK3BACWAQAXAAQJ6SK3BACWAQAuAAQKf0sAAxcACQkkJtIAAHIDABcACQkkJtIAAHIDABgAAQmNBmUgARgAAAAA.Auri:BAAALgADCgkJIQAAAA==.',
Av='Avatan:BAAALgAECgMJAwABLgAECgkJLQAJAKgNAA==.Avralis:BAAALgADCgMJAwABLgAECggJHQAYAEocAA==.',
Ax='Axex:BAAALgAECgkJDQAAAA==.',
Az='Azamii:BAABLgAECn88AAMQAAkJOSKPBAALAwAQAAkJOSKPBAALAwAIAAYJQRgUOwCVAQAAAA==.Azarion:BAABLgAECn84AAMZAAgJch3aCQCOAQAZAAcJnRvaCQCOAQAaAAYJlBl/WgCEAQAAAA==.Azill:BAACLgAFFH8QAAIMAAUJcBpcBABQAQAMAAUJcBpcBABQAQAuAAQKfyYAAgwACAleHjMKANUCAAwACAleHjMKANUCAAAA.Azzrael:BAABLgAECn8qAAIOAAkJzBDSFADAAQAOAAkJzBDSFADAAQAAAA==.',
Ba='Baalalmerat:BAAALgAECgIJAgAAAA==.Bandi:BAAALgAECgYJDQAAAA==.Bartrak:BAACLgAFFH8HAAIGAAMJbAdLIgC9AAAGAAMJbAdLIgC9AAAuAAQKfxkAAwYACQk/E38gAKYBAAYACQk/E38gAKYBAAMAAwnSDidDAJwAAAAA.',
Be='Bearfucius:BAAALgAECggJCAAAAA==.Bearrific:BAABLgAECn8kAAIbAAkJahqgDQA3AgAbAAkJahqgDQA3AgAAAA==.Beawulf:BAAALgAECgQJBAAAAA==.Behomadra:BAAALgAECgkJCQAAAA==.Belista:BAAALgAECgQJBAAAAA==.Bethel:BAAALgADCgYJCAAAAA==.',
Bf='Bfresh:BAAALgADCgcJCAAAAA==.',
Bi='Billie:BAAALgADCgcJAgAAAA==.Billthekid:BAAALgAECgYJCwAAAA==.Billybobb:BAAALgAECgYJDgAAAA==.Biney:BAAALgAECgQJBAABLgAECgQJBQAUAAAAAA==.Binksy:BAACLgAFFH8RAAIJAAUJSxRzHwAhAQAJAAUJSxRzHwAhAQAuAAQKfykAAgkACQmLHMkNAOcCAAkACQmLHMkNAOcCAAAA.Biscuit:BAACLgAFFH8lAAIOAAgJmiNEAgBCAgAOAAgJmiNEAgBCAgAuAAQKfyIAAg4ACQkfJe4AAJYDAA4ACQkfJe4AAJYDAAAA.Bitcoìn:BAAALgAECgEJAgAAAA==.',
Bl='Blaam:BAAALgAECgQJDgAAAA==.Blazin:BAACLgAFFH8dAAIBAAUJIxg6SAA9AQABAAUJIxg6SAA9AQAuAAQKfywAAgEACQmLHqoRAN4CAAEACQmLHqoRAN4CAAAA.Blep:BAAALgAECgYJCgAAAA==.Blgunc:BAAALgAECgkJEAAAAA==.Blinkzy:BAAALgAECgUJCQAAAA==.Bloui:BAAALgAECgQJCAAAAA==.Bluesummers:BAAALgADCgkJCQAAAA==.',
Bo='Boba:BAAALgAECgYJBgABLgAFFAgJJQAOAJojAA==.Bongrips:BAAALgADCgcJCQAAAA==.Boomboom:BAAALgAECgUJCAAAAA==.Borlok:BAAALgAFFAQJBQAAAQ==.',
Br='Brannigan:BAABLgAECn82AAIOAAkJFiSrAQA1AwAOAAkJFiSrAQA1AwAAAA==.Braulioo:BAAALgAECgQJBwAAAA==.Breebbs:BAAALgAECgUJBQAAAA==.Briantu:BAABLgAECn8qAAMIAAkJNQWueADWAAAIAAgJ/QGueADWAAAQAAEJEARmpgAjAAAAAA==.Brickitphil:BAAALgAECgYJEQAAAA==.Briiz:BAAALgADCgkJDAAAAA==.Brlolock:BAAALgADCgkJJAAAAA==.Brollo:BAAALgADCgEJAQAAAA==.Brud:BAAALgADCgYJAwAAAA==.Brönwyn:BAAALgAECgMJCAAAAA==.',
Bu='Bubblegumdrp:BAAALgAECgMJAwAAAA==.Bubblicious:BAAALgADCgUJCQAAAA==.Buckets:BAAALgAECgcJEgABLgAECggJCgAUAAAAAA==.Budi:BAAALgADCgcJCAAAAA==.Bulldan:BAABLgAECn8mAAINAAgJBx5nBAA1AgANAAgJBx5nBAA1AgAAAA==.Bullvi:BAAALgAECgYJBgAAAA==.',
['Bä']='Bärkler:BAABLgAECn8cAAMcAAkJaSI4BADFAgAcAAkJaSI4BADFAgAOAAEJHBgKSABAAAAAAA==.',
['Bé']='Béckley:BAAALgAECggJEgAAAA==.Béckléy:BAAALgAECgUJDQABLgAECggJEgAUAAAAAA==.',
Ca='Caatha:BAAALgAECgQJBAAAAA==.Caleanone:BAAALgAECgcJCwABLgAECgkJKgAJAAUcAA==.Calel:BAAALgAECgkJEAAAAA==.Callox:BAABLgAECn8qAAQJAAgJBRy9JwCrAQAJAAgJZRm9JwCrAQAcAAUJJxvtEQCCAQAOAAYJZQz/KgDJAAAAAA==.Cantelope:BAAALgADCgYJBgAAAA==.Capslock:BAAALgAECgQJAwAAAA==.Cara:BAAALgADCgIJAgAAAA==.Carahail:BAACLgAFFH8IAAMLAAMJAwcMQQCiAAALAAMJAwcMQQCiAAAKAAEJ6wHqSAApAAAuAAQKfzIAAwsACQmYFCYgADQCAAsACQmYFCYgADQCAAoABQlvDZ1MAL8AAAAA.Catriona:BAABLgAECn8iAAITAAkJgwouVQCNAQATAAkJgwouVQCNAQAAAA==.Cazmeer:BAAALgAECgYJDAAAAA==.',
Ce='Celés:BAAALgAECgUJBQAAAA==.',
Ch='Charcuterie:BAACLgAFFH8mAAIHAAgJPh1eBAAhAgAHAAgJPh1eBAAhAgAuAAQKfyAAAwcACQnYIVwJAPMCAAcACQnYIVwJAPMCAAwAAQlxHcJ2AFEAAAAA.Chaír:BAAALgAECgEJBQAAAA==.Cheezeburg:BAAALgAECgEJAQABLgAECgkJHwAHAC4ZAA==.Cheezus:BAAALgAECgIJBAABLgAECgkJHwAHAC4ZAA==.Cherrbeår:BAAALgADCgcJBwAAAA==.Cherudim:BAACLgAFFH8FAAMZAAMJ4wsjDwCHAAAaAAMJ4wvscADGAAAZAAIJrwIjDwCHAAAuAAQKfyYAAxkACAkiF44JACcCABkACAmBFY4JACcCABoACAl3FJ9PAKIBAAAA.Chillainkor:BAACLgAFFH8HAAIHAAMJOw1mNQC6AAAHAAMJOw1mNQC6AAAuAAQKfykAAgcACQk7FrIWAOQBAAcACQk7FrIWAOQBAAAA.Chillidán:BAABLgAECn8XAAIYAAkJjgRMigDvAAAYAAkJjgRMigDvAAAAAA==.Chippmagi:BAABLgAECn8gAAIBAAgJ9RofTQDeAQABAAgJ9RofTQDeAQAAAA==.Chippndots:BAAALgAECgYJDAABLgAECggJIAABAPUaAA==.Chirp:BAAALgAECgEJAQAAAA==.Chives:BAAALgAECgQJBAAAAA==.Choggie:BAACLgAFFH8HAAIdAAIJ5BqrLwCiAAAdAAIJ5BqrLwCiAAAuAAQKfz4AAh0ACQl2IGYEAEMDAB0ACQl2IGYEAEMDAAAA.Chronocolter:BAAALgADCgMJAwAAAA==.Chronosaren:BAABLgAECn8UAAIBAAkJyxH8UQDPAQABAAkJyxH8UQDPAQAAAA==.Chåir:BAAALgAECgEJAgAAAA==.',
Ci='Cinterax:BAAALgAECgIJAgABLgAECgkJNgAOABYkAA==.',
Cj='Cjrej:BAABLgAECn8zAAIBAAkJ+Q6dTgDZAQABAAkJ+Q6dTgDZAQAAAA==.',
Cl='Claytonis:BAAALgAECgEJAQAAAA==.Cloudnine:BAAALgAECgQJBAAAAA==.',
Co='Colterr:BAAALgADCgEJAQAAAA==.Cons:BAABLgAECn8rAAQDAAkJ4RZcFAAdAgADAAkJlBVcFAAdAgACAAMJ8QrYZQCWAAAGAAEJ+xJOdAA3AAAAAA==.Corellon:BAABLgAECn8rAAITAAkJnRuiJgAxAgATAAkJnRuiJgAxAgAAAA==.Costcohotdog:BAABLgAFFH8KAAMHAAMJLR1IGACsAAAHAAMJLR1IGACsAAAVAAEJOQBpGgAYAAABLgAFFAgJJQAOAJojAA==.Cougarclaws:BAAALgAECgUJCQAAAA==.',
Cr='Craftsman:BAAALgADCgUJBQAAAA==.Craigchrist:BAAALgAECgYJBgAAAA==.Cranee:BAABLgAECn8xAAIaAAkJLRQELgAVAgAaAAkJLRQELgAVAgAAAA==.Cranium:BAAALgAECgUJCAAAAA==.Crazytasty:BAABLgAECn8mAAITAAgJXyKSGAB+AgATAAgJXyKSGAB+AgAAAA==.Crumbo:BAAALgAECgYJBgAAAA==.Cryoburn:BAABLgAECn8fAAIBAAgJWB1rWAAwAgABAAgJWB1rWAAwAgAAAA==.Cryoshock:BAABLgAFFH8HAAIQAAMJwBakKQDRAAAQAAMJwBakKQDRAAAAAA==.',
Cu='Cutty:BAAALgAECgUJBgAAAA==.',
['Cø']='Cøns:BAAALgAECgYJCgAAAA==.',
Da='Daario:BAABLgAECn8TAAIYAAcJsB+pNQAhAgAYAAcJsB+pNQAhAgAAAA==.Dabare:BAAALgADCgUJAQAAAA==.Dabora:BAAALgAECgEJAQABLgAECgkJLAAeAAwfAA==.Dabßod:BAAALgAECgQJBAAAAA==.Dabûra:BAABLgAECn8sAAQeAAkJDB/KBwA5AgAeAAgJTB3KBwA5AgAKAAYJTR51PgD7AAAfAAcJehCvKgDjAAAAAA==.Daenerys:BAAALgAECgIJBgAAAA==.Dahouse:BAAALgADCgQJAwAAAA==.Dahpeht:BAAALgADCgkJEwAAAA==.Damda:BAAALgADCgIJAgAAAA==.Dandypooh:BAAALgAECgYJBgABLgAECgcJDQAUAAAAAA==.Danksamdi:BAAALgAECgEJAQAAAA==.Dante:BAAALgAECgUJCAAAAA==.Darige:BAAALgAECgIJAgAAAA==.Darim:BAAALgAECgYJBgABLgAECgkJKQABAFwaAA==.Darrow:BAAALgAECggJCAAAAA==.Darthspawn:BAABLgAECn8gAAIRAAcJpAssjwA1AQARAAcJpAssjwA1AQAAAA==.Daryl:BAAALgAECgQJBAAAAA==.Daryn:BAAALgAECgQJBAAAAA==.Davidbowy:BAABLgAECn8ZAAMgAAgJsA06KQBIAQAgAAcJ7wg6KQBIAQATAAcJYQ6GfAAwAQABLgAECgYJBwAUAAAAAA==.',
De='Deathnstuf:BAAALgAECgQJBgAAAA==.Deathollow:BAAALgAECgEJBAAAAA==.Delver:BAAALgADCgYJBgABLgAECgkJKQABAFwaAA==.Demai:BAAALgAECgQJBAAAAA==.Demina:BAAALgAECgMJAwABLgAECggJHQAYAEocAA==.Demonainkor:BAAALgAECgYJBgABLgAFFAMJBwAHADsNAA==.Demonicfury:BAAALgAECgYJBwAAAA==.Demonthrall:BAAALgAECgEJAQAAAA==.Dencity:BAABLgAECn82AAMDAAkJVxbkFAAXAgADAAkJ5hPkFAAXAgACAAYJbxfKNAAcAQAAAA==.Dendwran:BAAALgAECgkJCQAAAA==.Desden:BAABLgAECn82AAIfAAkJqhI7EQC4AQAfAAkJqhI7EQC4AQAAAA==.Destined:BAAALgAECgYJBwAAAA==.Devianchi:BAABLgAECn8nAAMVAAgJ+B+FCQC5AgAVAAgJ+B+FCQC5AgAMAAcJIh/9FQDyAQABLgAECgkJFwAdAHcZAA==.Devitodevour:BAABLgAECn8hAAMaAAgJPRupOgDkAQAaAAgJmxmpOgDkAQAZAAMJXBkENQDiAAAAAA==.',
Dg='Dgbugs:BAACLgAFFH8KAAIRAAMJoCKMewDqAAARAAMJoCKMewDqAAAuAAQKfzIAAhEACAk9I4YiAGoCABEACAk9I4YiAGoCAAAA.',
Dh='Dhbert:BAABLgAECn8sAAIhAAkJ5xGfEwC+AQAhAAkJ5xGfEwC+AQAAAA==.Dhomeli:BAAALgAECgQJBQAAAA==.',
Di='Dirtchez:BAAALgAECgIJAwAAAA==.Disastrophy:BAAALgAECgYJEQABLgAECgcJCAAUAAAAAA==.Disturbed:BAABLgAECn8/AAQNAAkJ4yG9AAARAwANAAkJsCG9AAARAwAaAAgJNRuvIgBLAgAZAAEJAADbYgBJAAAAAA==.Disturbio:BAAALgAECgEJAQABLgAECgkJPwANAOMhAA==.Divinepsycho:BAAALgADCgcJBwAAAA==.Divitiacus:BAAALgAECgYJBgAAAA==.',
Dj='Djowio:BAAALgADCgYJBgABLgAECggJIwAaABoiAA==.',
Dk='Dknightresh:BAAALgAECgcJBwABLgAECgcJJwAJAH0SAA==.',
Dm='Dmz:BAAALgADCgUJBgAAAA==.',
Do='Domfromgears:BAAALgAECgQJCQAAAA==.Dominance:BAAALgAECgEJAQAAAA==.Doomgaze:BAAALgADCgMJAQAAAA==.Dorc:BAAALgAECgMJBQAAAA==.Dotyou:BAAALgAECgIJAgAAAA==.Doudouzz:BAAALgAECgQJDQAAAA==.',
Dr='Dracthor:BAAALgADCgQJBAAAAA==.Draejin:BAAALgAECgkJDwAAAA==.Dragonfist:BAAALgADCgcJBwAAAA==.Dragthyr:BAAALgAECgUJCgAAAA==.Dramûl:BAABLgAECn8dAAITAAgJcRhmRgC5AQATAAgJcRhmRgC5AQAAAA==.Dreadedmonk:BAAALgAECgEJAQAAAA==.Druiaier:BAAALgADCgYJCQAAAA==.Druidibrume:BAAALgAECgMJDAAAAA==.Druknatsu:BAAALgAECgcJDAAAAA==.Drunkdragon:BAABLgAECn8UAAIMAAgJRRLpGwD9AQAMAAgJRRLpGwD9AQAAAA==.Drwhodunnit:BAAALgAECgMJAwAAAA==.',
Du='Dubbzilla:BAAALgAECgEJAQAAAA==.Dudedruid:BAAALgADCgUJBQAAAA==.Duncán:BAABLgAFFH8IAAMEAAUJ+RuMJABWAQAEAAUJ+RuMJABWAQAiAAEJoBX/EwA9AAAAAA==.Dustyknight:BAABLgAECn8fAAIhAAkJigjiIwAbAQAhAAkJigjiIwAbAQAAAA==.',
Dw='Dwell:BAAALgADCgkJIQAAAA==.',
Dy='Dyavola:BAAALgAECgUJBQAAAA==.',
Ea='Earthquack:BAAALgAECgUJBQABLgAECggJGwAiADMVAA==.',
Ed='Edge:BAABLgAECn8eAAIIAAgJShW8MADZAQAIAAgJShW8MADZAQAAAA==.',
Ee='Eelenna:BAABLgAECn8ZAAMjAAkJLhxgBgCSAgAjAAkJLhxgBgCSAgAQAAUJwRBnUwD4AAABLgAFFAQJCQASAMMTAA==.',
El='Elamlock:BAAALgADCgYJCwAAAA==.Eleathe:BAAALgAFFAQJBAABLgAECggJHQAYAEocAA==.Eleros:BAABLgAECn8wAAIYAAkJsB9LDgC/AgAYAAkJsB9LDgC/AgAAAA==.Elicio:BAAALgAECgYJEAAAAA==.Ellysial:BAAALgADCgUJBQAAAA==.Elphinia:BAABLgAECn8xAAMbAAkJqxnqDgAmAgAbAAkJqxnqDgAmAgAkAAEJ4BFlIAAxAAABLgAFFAQJBAAUAAAAAA==.Elreÿ:BAAALgADCgEJAQAAAA==.Elyas:BAAALgAECgIJAgAAAA==.',
Em='Emberwrath:BAAALgADCgMJAwAAAA==.Emosdnem:BAAALgAECgQJBQAAAA==.Emt:BAAALgAECgQJBAAAAA==.',
En='Endarial:BAAALgAECgQJCAAAAA==.Enoki:BAABLgAFFH8LAAIIAAQJsxUTMgD6AAAIAAQJsxUTMgD6AAABLgAFFAgJIAALALscAA==.',
Er='Eraduckated:BAAALgAECgYJCAABLgAECggJGwAiADMVAA==.Erah:BAAALgADCgUJDQAAAA==.',
Es='Esco:BAAALgADCgMJAwAAAA==.Esile:BAAALgAECgQJBAABLgAECgkJNgAKAIURAA==.',
Et='Eternalnow:BAAALgADCgEJAQAAAA==.',
Ev='Evelith:BAAALgADCgYJBgAAAA==.Everlife:BAAALgAFFAEJAQAAAA==.',
Ex='Exemptt:BAAALgAECgkJBQAAAA==.Exo:BAAALgADCgkJDwAAAA==.',
Fa='Falconpunch:BAAALgAECgYJBwAAAA==.Farnesë:BAAALgADCgUJBwABLgADCgcJBwAUAAAAAA==.Fauzzie:BAAALgAECgIJAgAAAA==.Fayrel:BAAALgAECgEJAgAAAA==.',
Fe='Fedders:BAABLgAECn8pAAIEAAkJRiZECAAWAwAEAAkJRiZECAAWAwAAAA==.Felaids:BAACLgAFFH8UAAMaAAQJkBNWVQADAQAaAAQJ+A9WVQADAQANAAEJSBDPHgBKAAAuAAQKfywAAxoACQmMGownADICABoACAmMGownADICABkAAwkSCLpEAKIAAAAA.Felimonk:BAAALgAECgQJBAABLgABCgQJBQAUAAAAAA==.Felpecs:BAAALgAECggJDgAAAA==.Fero:BAAALgAECgUJBQAAAA==.Feyda:BAABLgAECn8nAAIBAAgJfgh9kgA6AQABAAgJfgh9kgA6AQAAAA==.',
Fi='Fillon:BAACLgAFFH8IAAIEAAQJPxueIABjAQAEAAQJPxueIABjAQAuAAQKfzMAAgQACQmxJcoKAP0CAAQACQmxJcoKAP0CAAAA.Fionas:BAAALgADCgQJBAAAAA==.Firerybush:BAAALgAECgYJBwABLgAECggJRAAJAPwYAA==.Firessar:BAAALgAECgcJDAAAAA==.Fishfood:BAABLgAECn82AAISAAkJBhWGBgASAgASAAkJBhWGBgASAgAAAA==.Fishlover:BAAALgADCgUJBQAAAA==.Fixer:BAAALgAECgUJCQAAAA==.',
Fk='Fk:BAAALgAFFAMJAwABLgAFFAUJCAAEAPkbAA==.',
Fo='Foe:BAEALgAECggJEwAAAA==.Folkvar:BAAALgADCgcJDAAAAA==.',
Fr='Frankngibbon:BAAALgADCgYJBgAAAA==.Frimm:BAAALgAECggJDgAAAA==.Frimthemage:BAACLgAFFH8HAAIBAAQJEgvOWwAaAQABAAQJEgvOWwAaAQAuAAQKfy8AAgEACQk5HxAkAHcCAAEACQk5HxAkAHcCAAAA.Frostmaster:BAABLgAECn8bAAIBAAcJOhwGUwDMAQABAAcJOhwGUwDMAQAAAA==.',
Fu='Funbunz:BAAALgAECgcJDAAAAA==.',
['Fí']='Fízban:BAAALgAECgIJBAAAAA==.',
['Fø']='Førd:BAACLgAFFH8LAAMlAAQJFQywBAAaAQAlAAQJFQywBAAaAQAmAAIJjQhVTQByAAAuAAQKfy8ABCUACAmQHRoLACoCACUABwlLGhoLACoCACYABwlOGSUkAJwBABYAAwkIAow1AD0AAAAA.',
Ga='Gammon:BAABLgAECn8nAAMQAAgJ0h3/EgA/AgAQAAgJ0h3/EgA/AgAIAAUJGxvuRACAAQAAAA==.Gangrene:BAABLgAECn8yAAMRAAkJnxPaTADLAQARAAkJnxPaTADLAQAhAAgJCQtNKAD8AAAAAA==.Gary:BAAALgAECgQJCgAAAA==.Gash:BAAALgAECgMJAwAAAA==.Gaspasser:BAABLgAECn8oAAIkAAgJYBk5BQAZAgAkAAgJYBk5BQAZAgAAAA==.Gaviin:BAABLgAECn84AAIkAAkJGCEbAgC1AgAkAAkJGCEbAgC1AgAAAA==.',
Ge='Gearador:BAAALgADCgcJAQAAAA==.Geisten:BAAALgAECgYJEwAAAA==.Genovia:BAAALgADCgIJAgABLgAECggJEwAUAAAAAA==.Gerhart:BAABLgAECn8sAAQPAAkJSxnJBwDqAQAPAAkJ6hTJBwDqAQAYAAcJxBlfWwBfAQAXAAMJQxD+SQBpAAAAAA==.Getcarried:BAAALgADCgMJAwABLgAFFAUJHQABACMYAA==.Getty:BAAALgAECgcJEgAAAA==.',
Gf='Gfforgold:BAAALgADCgIJAgAAAA==.',
Gh='Ghosthunterx:BAAALgADCgEJAwAAAA==.Ghouldana:BAAALgADCgYJBgAAAA==.',
Gi='Gibbthok:BAAALgADCggJCAAAAA==.Gigachode:BAAALgAECgEJAwAAAA==.Gigarius:BAABLgAECn8iAAMiAAkJSSTYAQAUAwAiAAkJSSTYAQAUAwAEAAQJOBuGvADxAAAAAA==.Gigglesworth:BAAALgAECgYJBgAAAA==.Gilamonster:BAAALgAECgYJCgAAAA==.',
Gl='Gladllimbo:BAAALgADCgEJAQAAAA==.Gleiten:BAAALgADCgMJAwAAAA==.Glonkins:BAABLgAECn8nAAQTAAkJWB8MDADhAgATAAkJWB8MDADhAgAgAAQJ9RRVLwAeAQAFAAEJAACHQgAAAAAAAA==.Glynden:BAAALgADCgEJAQAAAA==.',
Go='Goncor:BAACLgAFFH8JAAISAAQJwxMRCgAsAQASAAQJwxMRCgAsAQAuAAQKfycAAxIACQnxH+MDAHUCABIACQmlH+MDAHUCACEABQk+I2UYAIcBAAAA.Gonnosuke:BAABLgAECn8UAAIEAAcJjgmmrwAFAQAEAAcJjgmmrwAFAQAAAA==.Gooseberry:BAAALgAECgEJAQAAAA==.Goosë:BAAALgADCgcJBwAAAA==.Gorrelord:BAAALgADCgEJAQABLgAFFAUJHQABACMYAA==.Gortar:BAAALgADCgEJAQAAAA==.',
Gr='Granolah:BAAALgADCgcJCwABLgAECgkJLAAeAAwfAA==.Griffmonk:BAABLgAECn88AAIVAAkJCRuKEgBrAgAVAAkJCRuKEgBrAgAAAA==.Grumpymage:BAABLgAECn81AAIBAAkJ6x8OFwC7AgABAAkJ6x8OFwC7AgAAAA==.',
Gu='Gussy:BAAALgAECgQJBAABLgAECggJCgAUAAAAAA==.',
Ha='Hafsac:BAAALgAECgMJAwAAAA==.Halaranth:BAAALgAECgIJAgAAAA==.Hamasakura:BAAALgAECgYJBgAAAA==.Hanya:BAAALgAECgIJAgAAAA==.Hara:BAABLgAECn8aAAILAAYJPRoYQACAAQALAAYJPRoYQACAAQAAAA==.Hardlyknower:BAAALgADCgIJAgAAAA==.Hardord:BAABLgAECn8lAAIbAAgJuBA+HQCVAQAbAAgJuBA+HQCVAQAAAA==.Harrydotter:BAAALgAECgIJAgAAAA==.Haryle:BAAALgAECgUJCgAAAA==.Hayanne:BAABLgAECn84AAIOAAkJXxzLBwBvAgAOAAkJXxzLBwBvAgAAAA==.',
He='Healchucky:BAAALgAECgYJDQAAAA==.Healfire:BAAALgADCgYJBwAAAA==.Healisha:BAAALgAECgYJEAAAAA==.Heina:BAAALgAECgYJBgAAAA==.Hershall:BAAALgAECgUJBQABLgAFFAQJDgAXAOkiAA==.',
Hi='Hitnrun:BAAALgAECgMJAwAAAA==.',
Ho='Hochunk:BAABLgAECn8jAAMDAAkJMRA2GwDWAQADAAkJ7A02GwDWAQACAAkJugkdOwBOAQAAAA==.Hochunks:BAAALgAECgYJDQAAAA==.Holdenger:BAAALgADCgQJBAAAAA==.Holikow:BAABLgAECn8YAAIEAAkJnxDXYgCSAQAEAAkJnxDXYgCSAQAAAA==.Holyherpies:BAAALgAECgYJBgAAAA==.Holyllama:BAAALgADCgcJBwAAAA==.Holymousey:BAABLgAECn8fAAIdAAkJjREhJADRAQAdAAkJjREhJADRAQAAAA==.Holysnake:BAAALgAECgQJBAAAAA==.Holytady:BAAALgADCgcJDQAAAA==.Holytudd:BAABLgAECn8gAAIEAAgJixTFeABjAQAEAAgJixTFeABjAQAAAA==.Honeybun:BAAALgADCgQJAgAAAA==.Honorlife:BAABLgAECn8rAAIIAAgJDhtTHABRAgAIAAgJDhtTHABRAgAAAA==.Hopeudie:BAAALgAECgUJBgABLgAFFAUJCAAEAPkbAA==.Horata:BAAALgAECgMJAwAAAA==.Hormuz:BAAALgADCgcJCwAAAA==.Hotelcali:BAAALgADCgkJCQAAAA==.',
Hu='Huckcold:BAAALgAECgcJDwAAAA==.Hugehands:BAAALgAECgUJBwAAAA==.Hughass:BAAALgADCgEJAQAAAA==.Hurano:BAAALgAECgYJCAAAAA==.',
Hy='Hyperious:BAAALgAECggJCAAAAA==.',
['Hâ']='Hârley:BAABLgAECn85AAILAAkJ+BsAFgCHAgALAAkJ+BsAFgCHAgAAAA==.',
['Hí']='Híram:BAABLgAECn8mAAIEAAgJahTmbQB6AQAEAAgJahTmbQB6AQAAAA==.',
Id='Idyllwild:BAAALgAECgEJBAAAAA==.',
Ih='Ihsan:BAABLgAECn8wAAIEAAkJExZPMwAcAgAEAAkJExZPMwAcAgAAAA==.',
Il='Ilharess:BAACLgAFFH8NAAIBAAQJDg6FVAApAQABAAQJDg6FVAApAQAuAAQKfygAAgEACQmCExlrAI4BAAEACQmCExlrAI4BAAAA.',
In='Inko:BAAALgADCgYJCQABLgAFFAUJHQAOAG8kAA==.Inkpot:BAAALgAECgEJAQABLgAECggJNQALABYlAA==.Inkstain:BAAALgAECgEJAQABLgAECggJNQALABYlAA==.Inkwell:BAABLgAECn81AAILAAgJFiX4CAAAAwALAAgJFiX4CAAAAwAAAA==.',
Is='Iskasta:BAAALgADCgQJBAAAAA==.Isobell:BAAALgAECgcJDQAAAA==.',
Ja='Jaardrius:BAABLgAECn87AAMVAAkJUiI8BQA/AwAVAAkJUiI8BQA/AwAMAAMJjgu3XgCVAAAAAA==.Jackransom:BAAALgADCgkJDgAAAA==.Jakobo:BAAALgAECgcJCgAAAA==.Jal:BAAALgADCgMJAwAAAA==.Jalapenoheat:BAAALgAECgQJAwAAAA==.Jandreyn:BAAALgADCgUJAQAAAA==.Jaskar:BAAALgAECgEJAQAAAA==.Javanna:BAAALgAECgMJAwAAAA==.',
Jd='Jdiddy:BAAALgAECgcJAQAAAA==.',
Je='Jelly:BAAALgADCgIJAgABLgAFFAgJIAALALscAA==.',
Ji='Jimbostein:BAAALgADCgEJAQAAAA==.Jinnie:BAAALgADCgMJBgAAAA==.',
Jj='Jjb:BAAALgAECgcJCQAAAA==.',
Ju='Junebuge:BAAALgAECgQJBAAAAA==.Junknthtrunk:BAAALgAECgMJAwAAAA==.',
Ka='Kaelana:BAAALgADCgEJAQAAAA==.Kamahl:BAAALgAECgQJAwAAAA==.Karl:BAAALgADCgUJBQAAAA==.Katôs:BAAALgADCgkJCQAAAA==.',
Kd='Kda:BAAALgAECgYJBgABLgAECgcJFQAbAIYjAA==.',
Ke='Keanew:BAABLgAECn8wAAQPAAkJjB04CQDCAQAPAAgJ1hQ4CQDCAQAXAAkJ/xtOGQCYAQAYAAMJNgOG5QBOAAAAAA==.Kebap:BAAALgAECgYJBgAAAA==.Keigaa:BAABLgAECn8qAAMdAAcJTSCkIAAWAgAdAAYJcCGkIAAWAgAEAAYJNRQOmAAqAQAAAA==.Keilien:BAAALgAECgUJBgAAAA==.Kenry:BAAALgAECgQJCAAAAA==.Keonna:BAAALgAECgQJCAAAAA==.Keppra:BAAALgAECgYJEgAAAA==.Kerlin:BAACLgAFFH8OAAILAAMJ4AG0SACEAAALAAMJ4AG0SACEAAAuAAQKfxsAAwsACQk9DmRYAEkBAAsACAlSC2RYAEkBAAoAAQnkAnOIACcAAAAA.Keyaira:BAAALgADCgYJBwAAAA==.Keybash:BAABLgAECn8UAAMNAAYJmgVyHwB1AAAaAAYJewW8vwDAAAANAAMJagNyHwB1AAAAAA==.Keíga:BAAALgAECgMJBAAAAA==.',
Kh='Khurst:BAAALgAECgcJDwAAAA==.',
Ki='Kilmithius:BAAALgAECgYJEgAAAA==.Kimchi:BAAALgAECgQJBAABLgAFFAgJIAALALscAA==.Kimmex:BAAALgADCgcJAgAAAA==.Kinoxo:BAACLgAFFH8rAAMJAAcJdh0YBwC3AQAJAAUJUiUYBwC3AQAcAAYJUhPoDwA2AQAuAAQKfx0AAwkACAmRIeMaAHUCAAkACAnzHeMaAHUCABwABAm6HakgAOgAAAAA.Kinoxoxo:BAAALgAECgQJBwAAAA==.Kirianis:BAABLgAECn8vAAIEAAkJDBhHMAAoAgAEAAkJDBhHMAAoAgAAAA==.Kishuko:BAAALgADCgEJAQAAAA==.',
Kl='Klesha:BAAALgADCgMJAwAAAA==.',
Ko='Kongfuux:BAAALgAECgQJBAAAAA==.Kossuth:BAAALgAECgcJCAAAAA==.',
Kr='Kragge:BAAALgAECgcJBwAAAA==.Krampusnacht:BAAALgAECgYJCQAAAA==.Krissycat:BAAALgAECgUJBQAAAA==.Kryven:BAAALgADCgkJEQAAAA==.',
Ku='Kumma:BAAALgADCgEJAQAAAA==.Kushaladaora:BAAALgAECgQJCQAAAA==.',
Ky='Kybrine:BAAALgAECgEJAQAAAA==.Kynlas:BAAALgAECgEJAQAAAA==.Kyratinx:BAAALgAECgEJAwAAAA==.',
['Kì']='Kìtty:BAAALgAECgYJCwAAAA==.',
La='Lacachuda:BAAALgADCgIJAwAAAA==.Lacear:BAAALgADCgcJBwABLgAFFAUJCAAEAPkbAA==.Langris:BAAALgAECgcJCAAAAA==.Larious:BAABLgAECn9IAAIEAAkJ6R1BFgCoAgAEAAkJ6R1BFgCoAgAAAA==.',
Le='Led:BAAALgAECggJEAAAAA==.Ledikens:BAAALgAECgYJBgAAAA==.Legnase:BAABLgAECn8wAAMDAAkJ6R4ZBwDxAgADAAkJ1h4ZBwDxAgACAAIJRRbQVgBmAAABLgAECgkJPAAQADkiAA==.Legolaslawl:BAAALgAECgQJBAABLgAECggJRAAJAPwYAA==.Leht:BAABLgAECn82AAMKAAkJhRELGgDjAQAKAAkJhRELGgDjAQALAAEJawGQ7AAVAAAAAA==.Lessgibbon:BAABLgAECn8XAAIJAAcJPh/WGgB1AgAJAAcJPh/WGgB1AgAAAA==.Lestare:BAAALgADCgYJBgAAAA==.Leviiathan:BAAALgAECgcJAwAAAA==.Lexishexis:BAAALgADCgYJBgAAAA==.',
Li='Lichma:BAAALgAECgIJAgAAAA==.Lighte:BAAALgADCgYJBgAAAA==.Lightspin:BAAALgAECgYJBgAAAA==.Lilgaspump:BAAALgADCgIJAQABLgAECgUJFAAHAJYQAA==.Lili:BAAALgADCgcJAgAAAA==.Lilnasty:BAABLgAECn8jAAIBAAkJSg6JYwCfAQABAAkJSg6JYwCfAQAAAA==.Lilnickel:BAAALgADCggJCAAAAA==.Lionroar:BAAALgADCgIJAwAAAA==.Livesey:BAAALgAECgQJBgAAAA==.',
Lo='Locknut:BAAALgADCgkJFwABLgAECggJFAAMAEUSAA==.Lockpie:BAAALgAECgUJBQAAAA==.Lockresh:BAAALgADCgcJBwABLgAECgcJJwAJAH0SAA==.Lokahn:BAABLgAECn8WAAIMAAYJ2RmGIwC6AQAMAAYJ2RmGIwC6AQAAAA==.Longhorndk:BAAALgAECgIJAQABLgAECggJRAAJAPwYAA==.Longhornpibe:BAABLgAECn9EAAMJAAgJ/BiHIADaAQAJAAgJ/BiHIADaAQAcAAMJTA6fRgCWAAAAAA==.Loudog:BAABLgAECn8zAAMRAAkJ3xM/UADBAQARAAkJohI/UADBAQAhAAYJ8hBMKgDuAAAAAA==.',
Lu='Lupardus:BAAALgAECgEJAQAAAA==.Luto:BAAALgAECgkJDgAAAA==.Luuko:BAAALgAECgQJBAAAAA==.',
Ly='Lynxie:BAABLgAECn8gAAIGAAgJWA9iLgBIAQAGAAgJWA9iLgBIAQAAAA==.',
['Lö']='Lökkïï:BAAALgADCgUJBQAAAA==.Lörelei:BAAALgAECgQJBAAAAA==.',
Ma='Mackerel:BAABLgAECn8YAAIHAAcJliBoEACXAgAHAAcJliBoEACXAgABLgAFFAgJJQAOAJojAA==.Madii:BAAALgAECgEJAQAAAA==.Mageresh:BAABLgAECn8VAAIBAAYJwQh/zgDWAAABAAYJwQh/zgDWAAABLgAECgcJJwAJAH0SAA==.Malus:BAABLgAECn8ZAAIaAAgJLQ68YQClAQAaAAgJLQ68YQClAQAAAA==.Manders:BAAALgADCgcJAgAAAA==.Mangela:BAAALgAECgIJAwAAAA==.Mank:BAAALgAECgMJAwAAAA==.Maps:BAAALgAECgYJDQAAAA==.Masher:BAAALgAECgQJBAAAAA==.Mattydruid:BAAALgAFFAEJAQAAAA==.Maverage:BAAALgADCgMJBQAAAA==.Mavramune:BAACLgAFFH8KAAITAAUJ2QjCSQDvAAATAAUJ2QjCSQDvAAAuAAQKfyYAAxMACAlDF9lYAIQBABMABwniGdlYAIQBAAUACAmzDKAdAK8AAAAA.Mayge:BAABLgAECn8rAAIBAAkJKxtCLQBOAgABAAkJKxtCLQBOAgAAAA==.Mañali:BAAALgADCgYJBgAAAA==.',
Mc='Mcfürry:BAABLgAECn8YAAILAAcJyBvwLwDRAQALAAcJyBvwLwDRAQAAAA==.',
Me='Mebedir:BAAALgAECgMJBQAAAA==.Meekal:BAAALgADCgEJAQAAAA==.Meggatron:BAAALgAECggJDgABLgAECgkJKQAjAPIeAA==.Melithia:BAAALgAECgcJEQAAAA==.Mels:BAAALgAECgQJBgAAAA==.Mendinna:BAABLgAECn8zAAIXAAgJdBN0GAChAQAXAAgJdBN0GAChAQAAAA==.Mephidrossa:BAAALgAECggJCAABLgAECgkJNwAMAOMgAA==.Mercs:BAAALgADCgQJBQABLgAECgUJFAAHAJYQAA==.Methir:BAAALgAECgEJAQABLgAFFAQJBQAUAAAAAA==.',
Mi='Miffed:BAAALgAECggJEgABLgAFFAYJHQAiAPURAA==.Mildew:BAAALgADCgYJBgAAAA==.Mincksie:BAAALgAECggJEwAAAA==.Mininetty:BAAALgADCgcJBwABLgAECgYJCAAUAAAAAA==.Mirage:BAABLgAECn8VAAIbAAcJhiMPFwBSAgAbAAcJhiMPFwBSAgAAAA==.Misfired:BAAALgADCgIJAgAAAA==.Mistbot:BAABLgAECn83AAIMAAkJ4yBTBgDXAgAMAAkJ4yBTBgDXAgAAAA==.',
Mo='Montebrew:BAAALgAECgYJBgAAAA==.Monysha:BAAALgAECgYJBwAAAA==.Mooferrigno:BAAALgAFFAEJAQAAAA==.Mooky:BAABLgAECn8oAAIKAAkJ9Q8ZIACvAQAKAAkJ9Q8ZIACvAQAAAA==.Moovitz:BAAALgADCgYJBgAAAA==.Mopeia:BAABLgAECn8iAAMLAAYJghdDPACSAQALAAYJghdDPACSAQAfAAUJOQ4RNQCvAAABLgAECgYJEwAUAAAAAA==.Mord:BAAALgAECgUJDAAAAA==.Mork:BAAALgADCgMJAwABLgAECgcJLgARAD4iAA==.Mortemore:BAACLgAFFH8RAAIYAAUJ4hfjPAAXAQAYAAUJ4hfjPAAXAQAuAAQKfycAAhgACQkSIAMZAGwCABgACQkSIAMZAGwCAAAA.Mortlee:BAAALgAECgEJAQABLgAFFAUJEQAYAOIXAA==.Motet:BAAALgAECgYJCwAAAA==.Motoxman:BAAALgADCgEJAQAAAA==.',
Mu='Muikkie:BAAALgAECgEJAgAAAA==.Mulro:BAAALgADCgMJAwAAAA==.Muncher:BAAALgAECgkJEgAAAA==.',
My='Mymage:BAAALgADCgEJAQAAAA==.Mynoghra:BAAALgAECgYJEgAAAA==.Mynxx:BAAALgAECgcJCQAAAA==.Mystrax:BAAALgADCgIJAgAAAA==.',
Na='Nadoral:BAAALgADCgYJCwAAAA==.Nalka:BAAALgADCgUJBQAAAA==.Naproxen:BAABLgAECn9CAAIgAAkJySBuAgAWAwAgAAkJySBuAgAWAwAAAA==.Naraku:BAACLgAFFH8XAAQaAAUJqRn+NwBDAQAaAAUJuBj+NwBDAQAZAAEJFhKxFABVAAANAAEJ6RRRGgBQAAAuAAQKfzMAAxoACAnhI70SAKwCABoACAlcI70SAKwCABkABglbHugNAOcBAAAA.Narberal:BAAALgADCgEJAQAAAA==.Nastager:BAAALgADCgcJBwAAAA==.Naxx:BAAALgADCgIJAgAAAA==.Nazgül:BAAALgADCgMJAgAAAA==.',
Ne='Necroseeker:BAAALgAECgYJCwAAAA==.Negativity:BAAALgAECgYJBgAAAA==.Nes:BAAALgAECggJCwABLgAECgkJJQADAC0aAA==.Nettie:BAAALgAECgUJBQABLgAECgYJCAAUAAAAAA==.Netty:BAAALgAECgYJCAAAAA==.',
Ni='Nightshaulea:BAAALgAECgcJCgAAAA==.Niklaus:BAABLgAECn8eAAIEAAcJdhZVaACvAQAEAAcJdhZVaACvAQAAAA==.Nilisha:BAAALgADCgIJAgAAAA==.Nimi:BAAALgAECgEJAQAAAA==.Nirala:BAAALgADCgkJCQAAAA==.',
No='Nosferatmoo:BAAALgADCgkJCQABLgADCgkJEwAUAAAAAA==.',
Nu='Nusy:BAAALgAECgQJBAAAAA==.',
Ny='Nymeera:BAABLgAECn82AAMfAAkJ2AeXKADwAAAfAAkJ2AeXKADwAAAeAAIJMgOlPgBFAAAAAA==.Nymphetamine:BAABLgAECn9BAAMCAAkJxhicDwBZAgACAAkJxhicDwBZAgADAAQJ/AZKUQCOAAAAAA==.Nyxarya:BAAALgADCgcJBwAAAA==.',
Nz='Nzoth:BAABLgAECn8gAAIGAAkJGRDEJACHAQAGAAkJGRDEJACHAQAAAA==.',
Ob='Obnixilis:BAABLgAECn8VAAIRAAYJXRjgbgCrAQARAAYJXRjgbgCrAQABLgAECggJEwAUAAAAAA==.',
Od='Odessa:BAAALgAECgEJAQAAAA==.',
Ok='Okin:BAAALgAECgMJAwAAAA==.',
Om='Omadruid:BAAALgADCgYJBgAAAA==.Omapriest:BAAALgADCgUJBQAAAA==.Omashamwow:BAAALgAECgQJBQAAAA==.Omorc:BAABLgAECn82AAIFAAkJExg0BQBCAgAFAAkJExg0BQBCAgAAAA==.',
On='Oneyeli:BAAALgADCgYJBgAAAA==.Oniony:BAAALgADCgYJCwAAAA==.Onli:BAAALgAECgEJAgAAAA==.Onos:BAAALgAECgMJAwAAAA==.',
Or='Ordlok:BAAALgADCgcJCQAAAA==.Oresh:BAABLgAECn8nAAIJAAcJfRKXNABkAQAJAAcJfRKXNABkAQAAAA==.Orlaith:BAAALgAECgQJBAABLgAECggJHQAYAEocAA==.',
Ow='Owenwilson:BAAALgAECgIJAwAAAA==.Owful:BAAALgAECgcJDAAAAA==.',
Pa='Pandaloca:BAAALgAECgUJBQAAAA==.Pandaloco:BAAALgADCgcJBwAAAA==.Pandalôc:BAAALgAECgIJAgAAAA==.Pandoe:BAABLgAECn8VAAQfAAgJbxfxEAC8AQAfAAYJaB/xEAC8AQAKAAgJrA6nMACDAQALAAEJngeR3AAmAAAAAA==.Papaya:BAACLgAFFH8gAAILAAgJuxyaAQD+AQALAAgJuxyaAQD+AQAuAAQKfyIAAwsACQnZIcMGAB8DAAsACQnZIcMGAB8DAAoABwliIZYjAOABAAAA.Pawpawpiddle:BAAALgAECgYJBgAAAA==.',
Pe='Penelopea:BAABLgAECn8pAAIBAAkJeRXROAAfAgABAAkJeRXROAAfAgAAAA==.Perlen:BAAALgADCgYJBgAAAA==.Perun:BAAALgAECgYJDQAAAA==.',
Ph='Phaith:BAAALgADCgUJCwABLgAECgEJAQAUAAAAAA==.Phaithfully:BAAALgAECgEJAQAAAA==.Phenomenal:BAAALgAECgEJAQABLgAECggJJwAQANIdAA==.',
Pl='Plaguedealer:BAAALgADCgUJBQAAAA==.',
Pn='Pneumonya:BAAALgAECgcJBwAAAA==.',
Po='Porteagarder:BAABLgAECn8kAAIIAAgJdwenXgAkAQAIAAgJdwenXgAkAQAAAA==.Potatodruid:BAAALgAECgQJDQAAAA==.Power:BAAALgADCgYJBgAAAA==.',
Pr='Preparedpie:BAABLgAECn8SAAIYAAgJcxnGMQDqAQAYAAgJcxnGMQDqAQAAAA==.Preront:BAACLgAFFH84AAMjAAkJySUEAAB+AwAjAAkJryUEAAB+AwAQAAgJBxsGBgAeAgAuAAQKfyIABCMACQngJikAAOYDACMACQngJikAAOYDABAAAwksJq4+AFABAAgAAwkVGydyAOgAAAAA.Priestbrume:BAAALgAECgYJBgAAAA==.Pringler:BAAALgAECgQJBAABLgAFFAgJJQAOAJojAA==.Producktive:BAABLgAECn8bAAIiAAgJMxXCEAC6AQAiAAgJMxXCEAC6AQAAAA==.Prometeus:BAAALgAECgUJBQAAAA==.Pros:BAABLgAECn8iAAIZAAkJWRRZDQDvAQAZAAkJWRRZDQDvAQAAAA==.Pruulia:BAAALgADCgkJDAABLgAECgkJNgAKAIURAA==.Príestly:BAAALgAECgYJCwAAAA==.',
Ps='Psydúck:BAAALgADCgcJDQAAAA==.',
Pu='Puffdamagic:BAABLgAECn8aAAImAAgJ1htSFgAQAgAmAAgJ1htSFgAQAgABLgAFFAUJEQAYAOIXAA==.Puffthemagic:BAABLgAECn8WAAIlAAkJoQxiCACaAQAlAAkJoQxiCACaAQAAAA==.Purentity:BAAALgAECgYJCwAAAA==.',
Py='Pyatt:BAABLgAECn8uAAINAAkJbx1YAwBlAgANAAkJbx1YAwBlAgAAAA==.',
['Pú']='Púff:BAAALgAECgMJAwAAAA==.',
Qu='Quack:BAAALgAECggJEQAAAA==.Quackadin:BAAALgADCgYJCwABLgAECggJEQAUAAAAAA==.Quackula:BAAALgAECgcJBgAAAA==.Quilae:BAAALgAECgcJEAABLgAECggJJAAIAHcHAA==.Quiny:BAAALgADCgMJAQAAAA==.',
Ra='Raerlynn:BAEALgADCgMJAwAAAA==.Ragnix:BAAALgAECgEJAQAAAA==.Randivh:BAAALgAECgIJAgAAAA==.Rassputin:BAABLgAECn8pAAIBAAkJnhfLNQAqAgABAAkJnhfLNQAqAgAAAA==.Ravnmoon:BAAALgAECgUJBQAAAA==.Razzleyi:BAAALgAECgQJBAAAAA==.',
Re='Realmack:BAAALgAECggJDAABLgAFFAUJCAAEAPkbAA==.Rebuke:BAAALgAECgYJBgAAAA==.Reclaimblade:BAAALgADCgUJBQAAAA==.Reclaimdrunk:BAAALgAECgIJAgAAAA==.Reclaimergun:BAAALgADCgEJAQAAAA==.Reclaimholy:BAAALgADCgUJBQAAAA==.Reclaimsage:BAAALgADCgYJBQAAAA==.Reigwend:BAAALgADCggJDwAAAA==.Reisharra:BAAALgAECgUJCgAAAA==.Relimas:BAAALgADCgcJEAAAAA==.Remish:BAAALgAECgQJBAABLgAECgUJBQAUAAAAAA==.Rendezvous:BAAALgAECgEJBgAAAA==.Renkà:BAAALgAFFAQJBAAAAA==.Requestor:BAAALgAECgUJBgABLgAECggJEwAUAAAAAA==.Resmondo:BAAALgADCgQJBAAAAA==.Ret:BAACLgAFFH8RAAIEAAUJpguZRgAIAQAEAAUJpguZRgAIAQAuAAQKfysAAgQACAkhG4suAGkCAAQACAkhG4suAGkCAAAA.Revaerlous:BAABLgAECn8uAAIRAAkJix0oLACIAgARAAkJix0oLACIAgAAAA==.',
Rh='Rheas:BAAALgADCgYJDQABLgAECggJEwAUAAAAAA==.Rhei:BAABLgAECn8RAAIYAAgJIBkbLgBEAgAYAAgJIBkbLgBEAgAAAA==.',
Ri='Ribeye:BAACLgAFFH8dAAIiAAYJ9RHFAwBEAQAiAAYJ9RHFAwBEAQAuAAQKfykAAiIACQlPFpIQAKIBACIACQlPFpIQAKIBAAAA.',
Ro='Roereker:BAABLgAECn9AAAIEAAkJcBhOLAA4AgAEAAkJcBhOLAA4AgAAAA==.Roguesamurai:BAAALgADCgEJAQAAAA==.Rohhenge:BAAALgAECgQJBAAAAA==.Roketraccoon:BAAALgAECgQJCwAAAA==.Romoxodus:BAAALgADCgUJCQAAAA==.Rongbip:BAABLgAECn8gAAIgAAkJ2hrnEgAFAgAgAAkJ2hrnEgAFAgAAAA==.Roshamandes:BAABLgAECn8nAAIPAAkJzCANAgDdAgAPAAkJzCANAgDdAgAAAA==.Rotigus:BAAALgADCgUJBQAAAA==.',
Ru='Rubadubdubz:BAAALgADCgMJAwAAAA==.Runep:BAABLgAECn8rAAIEAAkJbyCbEwC5AgAEAAkJbyCbEwC5AgAAAA==.',
Ry='Ryusei:BAAALgAECgcJBwABLgAECgkJPAAQADkiAA==.',
['Rè']='Rèi:BAAALgAECgIJBgABLgAECggJJgATAF8iAA==.',
['Ré']='Réstofarian:BAACLgAFFH8UAAILAAQJIB6sHQBPAQALAAQJIB6sHQBPAQAuAAQKfy0AAwsACQm0I1sCAHYDAAsACQm0I1sCAHYDAAoAAgkoGexmAIYAAAAA.',
Sa='Sabbier:BAAALgADCgcJBwAAAA==.Sacredchikín:BAABLgAECn8dAAIaAAgJPxwqKwAhAgAaAAgJPxwqKwAhAgAAAA==.Saiki:BAAALgAECgQJBQAAAA==.Samuel:BAAALgAECgMJAwAAAA==.Sanataanna:BAAALgADCgUJCwABLgAECggJEwAUAAAAAA==.Sandvichus:BAABLgAECn8nAAIKAAkJmyLcBAAAAwAKAAkJmyLcBAAAAwAAAA==.Sanitarìum:BAAALgAECgQJCAAAAA==.Sardine:BAAALgAECgcJDgABLgAFFAgJIAALALscAA==.Sasukie:BAAALgAECgEJBQAAAA==.Savagesmonk:BAAALgAECgUJBgAAAA==.Saxa:BAACLgAFFH8IAAIXAAMJ6CR3CQBDAQAXAAMJ6CR3CQBDAQAuAAQKfy4AAhcACQnOJJgEAOgCABcACQnOJJgEAOgCAAAA.',
Sc='Scratchnsnif:BAAALgADCgUJBQAAAA==.',
Se='Seers:BAAALgAECgMJAwABLgAFFAUJCAAEAPkbAA==.Sefik:BAAALgAECgYJDgAAAA==.Selaana:BAABLgAECn8YAAIQAAYJPh9nIgD8AQAQAAYJPh9nIgD8AQAAAA==.Serkis:BAAALgAECgcJBQAAAA==.Seyekosis:BAABLgAECn8aAAIYAAgJMhw5IABBAgAYAAgJMhw5IABBAgAAAA==.',
Sg='Sgathaich:BAEBLgAECn8rAAIdAAgJVBp+GQAlAgAdAAgJVBp+GQAlAgAAAA==.',
Sh='Shaan:BAAALgADCgMJAwAAAA==.Shadtae:BAAALgAECgYJCgABLgAECgkJLAAIAKgXAA==.Shaio:BAABLgAECn8VAAIMAAYJ3Q9hNgBGAQAMAAYJ3Q9hNgBGAQAAAA==.Shallistiah:BAAALgAECgQJBAABLgAECgkJOwAVAFIiAA==.Shamadin:BAAALgADCgkJCQAAAA==.Shambrume:BAAALgAECgYJDgAAAA==.Shambulence:BAACLgAFFH8PAAIIAAQJew7DMwD0AAAIAAQJew7DMwD0AAAuAAQKfxoAAwgACQm/FRoeAEUCAAgACQm/FRoeAEUCACMAAwnREdMiALcAAAAA.Shammlock:BAACLgAFFH8TAAQNAAUJYBB+AQCvAAAaAAMJYxHWawDPAAANAAQJ+xB+AQCvAAAZAAIJxwI/JABBAAAuAAQKfygABA0ACQmCHuECAIMCAA0ACAkTH+ECAIMCABoACQnDGS0qAGcCABkABQl6EFskADgBAAAA.Shampriest:BAAALgAECggJCAAAAA==.Shamuel:BAACLgAFFH8IAAIgAAYJPBLQBQCWAQAgAAYJPBLQBQCWAQAuAAQKfxcAAiAACQlqE/UPACQCACAACQlqE/UPACQCAAAA.Shaylis:BAAALgAECgcJEgABLgAFFAQJBAAUAAAAAA==.Sheji:BAAALgADCgkJHAAAAA==.Shiggy:BAAALgAECgQJCQABLgAECgkJKgAJAAUcAA==.Shobadon:BAAALgAECggJEAAAAA==.Shole:BAABLgAECn81AAMQAAkJGh5zEQBQAgAQAAkJGh5zEQBQAgAIAAcJFBzkJgANAgAAAA==.Shulanii:BAAALgAECgMJBQAAAA==.',
Si='Siatral:BAAALgAECgEJAQABLgAFFAUJCQAVAGQYAA==.Siggopotomus:BAAALgADCgUJBQABLgAECggJEwAUAAAAAA==.Sigvalden:BAAALgAECggJEwAAAA==.Sigvolden:BAAALgAECgcJAgABLgAECggJEwAUAAAAAA==.Silchar:BAAALgAECgMJBgAAAA==.Silicon:BAABLgAECn8hAAIBAAkJjhL2WgC2AQABAAkJjhL2WgC2AQAAAA==.Sinfulangel:BAABLgAECn8yAAMRAAkJ/RyqIgBpAgARAAkJ+BuqIgBpAgAhAAYJPhTpIAA0AQAAAA==.Siona:BAABLgAECn9IAAITAAkJZg0ZRQC9AQATAAkJZg0ZRQC9AQAAAA==.',
Sk='Skadie:BAABLgAECn8qAAMTAAkJNBW0JgAfAgATAAkJNBW0JgAfAgAFAAEJ+QPKPAAnAAAAAA==.Skialin:BAAALgAECgEJAQAAAA==.Skiye:BAAALgADCggJDgAAAA==.Skwip:BAABLgAFFH8IAAIIAAQJSiOJEwCbAQAIAAQJSiOJEwCbAQABLgAFFAUJCAAEAPkbAA==.Skwop:BAAALgAECgEJAgABLgAFFAUJCAAEAPkbAA==.Skyelar:BAAALgAECgcJBgAAAA==.Skyler:BAABLgAECn8UAAInAAcJER39AgAzAgAnAAcJER39AgAzAgAAAA==.',
Sl='Slackness:BAAALgAECgMJCAAAAA==.Slavalous:BAAALgAECgcJDAAAAA==.',
Sn='Snakeshifter:BAAALgADCgUJBQAAAA==.Snakesoul:BAAALgAECgMJBAAAAA==.Snivels:BAABLgAECn8hAAIfAAkJbRGFJAALAQAfAAkJbRGFJAALAQAAAA==.Snnorri:BAAALgADCggJFgABLgAECgkJOwAVAFIiAA==.',
So='Sodtaoe:BAAALgADCgcJDQAAAA==.Solsilvesti:BAAALgADCgMJAwAAAA==.Souly:BAAALgAECgcJBwAAAA==.',
Sp='Sparrkle:BAABLgAECn8uAAIZAAkJ1w1oCwBvAQAZAAkJ1w1oCwBvAQAAAA==.Spin:BAAALgADCgMJAwAAAA==.Spinecrawler:BAAALgAECgIJAgAAAA==.Spinjitzu:BAAALgAECgQJCwAAAA==.Spiritshift:BAAALgAECgEJAQAAAA==.Spyro:BAAALgAECgQJEAAAAA==.',
Sq='Squadw:BAACLgAFFH8aAAIXAAYJAhy7AwCsAQAXAAYJAhy7AwCsAQAuAAQKf0YAAhcACQkCJTkCAHMDABcACQkCJTkCAHMDAAAA.',
Ss='Sski:BAAALgADCgEJAQAAAA==.',
St='Starblast:BAAALgAECgYJEwABLgAECgYJBwAUAAAAAA==.Starrskrream:BAAALgAECgQJBgAAAA==.Staryknight:BAAALgAECgEJAQAAAA==.Steamworks:BAAALgADCgcJBwAAAA==.Steelrat:BAAALgADCgcJAgAAAA==.Stellanova:BAAALgADCgQJBAAAAA==.Stiick:BAABLgAECn82AAIiAAkJDBrECAAwAgAiAAkJDBrECAAwAgAAAA==.Stormhide:BAAALgADCgEJAgAAAA==.Streakycat:BAEALgAECgEJAQAAAA==.Stupidgnome:BAAALgAECgkJCQAAAA==.Stìmpak:BAAALgAECgMJBQABLgAECgcJCAAUAAAAAA==.',
Su='Subsizzle:BAAALgAECgMJAwABLgAECgcJEgAUAAAAAA==.Subzerow:BAAALgADCgYJBgAAAA==.Sudsy:BAAALgAECggJCgAAAA==.Sujin:BAAALgAECgMJAwAAAA==.Sunarra:BAABLgAECn8dAAIYAAgJShxCLgD5AQAYAAgJShxCLgD5AQAAAA==.Sunsmite:BAABLgAECn8dAAIEAAcJrhaOgwBOAQAEAAcJrhaOgwBOAQAAAA==.Supadupaman:BAAALgAECgkJBgAAAA==.Suramar:BAABLgAECn8YAAIOAAgJAhWfFgB7AQAOAAgJAhWfFgB7AQAAAA==.',
Sw='Sweetbippy:BAABLgAECn82AAIBAAkJCwNQqwAPAQABAAkJCwNQqwAPAQAAAA==.Swifthealss:BAABLgAECn8YAAMLAAgJfAYCYgD/AAALAAgJfAYCYgD/AAAKAAUJ3gq6UwCmAAAAAA==.Swirls:BAAALgAECgEJAgAAAA==.',
Sy='Sygvalden:BAAALgAECgYJDAABLgAECggJEwAUAAAAAA==.Sylunae:BAAALgAECgYJCgABLgAECggJJAAIAHcHAA==.Syluné:BAABLgAECn8gAAILAAgJWAnzZwDsAAALAAgJWAnzZwDsAAABLgAECggJJAAIAHcHAA==.Syläs:BAAALgAECgYJEwAAAA==.Syndrassil:BAABLgAECn8oAAIBAAgJ+Av8eQBrAQABAAgJ+Av8eQBrAQAAAA==.',
['Sù']='Sùccubus:BAAALgADCgQJBAAAAA==.',
['Sý']='Sýd:BAAALgAECgIJAgAAAA==.',
Ta='Tacodog:BAAALgAECgUJCgABLgAECgkJKQAEAEYmAA==.Tacomonk:BAAALgAECggJCgAAAA==.Tacopally:BAAALgAECgQJBAABLgAECggJCgAUAAAAAA==.Tacozpriest:BAAALgAECgYJBgABLgAECggJCgAUAAAAAA==.Taelight:BAAALgADCggJDgABLgAECgkJLAAIAKgXAA==.Taelyx:BAABLgAECn8sAAMIAAkJqBcxMwDMAQAIAAkJqBcxMwDMAQAQAAIJ3gkQfgBOAAAAAA==.Taepain:BAAALgAECgIJAgABLgAECgkJLAAIAKgXAA==.Taicheeze:BAABLgAECn8fAAIHAAkJLhkrDgBEAgAHAAkJLhkrDgBEAgAAAA==.Tambot:BAAALgAECgQJDQAAAA==.Tariced:BAAALgAECgQJBAAAAA==.Tarvaron:BAAALgADCgEJAQAAAA==.Taytra:BAAALgAECgQJBAABLgAECgkJNgABAAsDAA==.Tazmina:BAACLgAFFH8LAAIXAAMJyR7IDgAOAQAXAAMJyR7IDgAOAQAuAAQKfzUAAhcACQlmIvsCABYDABcACQlmIvsCABYDAAAA.',
Te='Teal:BAAALgADCgYJCgAAAA==.Tehssa:BAAALgAECgUJBgABLgAECgkJPAAQAEseAA==.Tessa:BAABLgAECn88AAIQAAkJSx4iCgCqAgAQAAkJSx4iCgCqAgAAAA==.Texasfight:BAAALgAECgEJAQABLgAECggJRAAJAPwYAA==.Teyo:BAAALgAECgcJEQAAAA==.',
Th='Thedoctorwho:BAABLgAECn8WAAIEAAkJpw+rUAC/AQAEAAkJpw+rUAC/AQAAAA==.Theholytaz:BAABLgAECn8XAAIEAAgJDBZkQQAhAgAEAAgJDBZkQQAhAgAAAA==.Theirel:BAAALgADCgYJAQAAAA==.Thunderr:BAAALgAECgcJCAAAAA==.Thörn:BAABLgAECn8VAAMIAAgJ1A3dYgAXAQAIAAcJegvdYgAXAQAQAAIJGgVaigBDAAABLgAFFAMJCAALAAMHAA==.',
Ti='Tigs:BAAALgADCgMJAwAAAA==.Time:BAAALgAECgMJAwAAAA==.Tinyjapeto:BAAALgAECgQJBAAAAA==.Titanbow:BAAALgADCgYJBgABLgAECgkJMAAYALAfAA==.',
To='Tomcatt:BAABLgAECn9JAAITAAkJOCOEBQArAwATAAkJOCOEBQArAwAAAA==.Tonshaw:BAAALgAECgYJBgAAAA==.Toome:BAAALgADCgUJBQAAAA==.Toxin:BAAALgADCgEJAQAAAA==.',
Tr='Trailis:BAAALgAECgMJBAAAAA==.Travalden:BAAALgADCgMJAwAAAA==.Trekkie:BAAALgAECgUJBQABLgAFFAYJHQAiAPURAA==.Treè:BAAALgAECgMJCgAAAA==.Trioxinn:BAAALgADCgEJAQAAAA==.',
Tu='Tuddlly:BAAALgAECgUJCgAAAA==.Turin:BAABLgAECn8vAAIOAAkJHwg4GwBJAQAOAAkJHwg4GwBJAQAAAA==.Turnip:BAAALgAFFAIJBAABLgAFFAgJIAALALscAA==.Tutonik:BAAALgADCgUJBQAAAA==.Tuubarkk:BAAALgADCgcJCAAAAA==.',
Tw='Twilghtdawn:BAABLgAECn8rAAIhAAgJ4Bf2EwC6AQAhAAgJ4Bf2EwC6AQAAAA==.Twos:BAAALgAECgEJAQAAAA==.Twotone:BAAALgADCgMJAwAAAA==.',
Ty='Tybo:BAABLgAECn83AAIjAAkJFSNHAQAfAwAjAAkJFSNHAQAfAwAAAA==.Tybs:BAAALgADCgEJAQAAAA==.',
Un='Uncás:BAABLgAECn8VAAITAAYJIgdZeAD+AAATAAYJIgdZeAD+AAAAAA==.Ungieblinks:BAAALgAECgQJBwAAAA==.Ungislayer:BAAALgADCgMJAwAAAA==.Unglifettv:BAACLgAFFH8GAAImAAMJiBewMADoAAAmAAMJiBewMADoAAAuAAQKfxUAAiYACAkxF4ccANsBACYACAkxF4ccANsBAAAA.Unstable:BAAALgAECgQJBgABLgAECgcJCAAUAAAAAA==.',
Up='Upchucky:BAAALgAECgQJBAAAAA==.',
Ur='Urulóki:BAAALgAECgcJCAAAAA==.',
Va='Vaedeath:BAABLgAECn89AAIhAAkJJiAFCACFAgAhAAkJJiAFCACFAgAAAA==.Vaina:BAAALgADCgMJAwAAAA==.Vainagos:BAAALgAECgUJBgAAAA==.Valaryon:BAAALgAECgYJDAAAAA==.Valkorin:BAAALgAECgYJBwAAAA==.Valoryan:BAABLgAECn9JAAILAAkJYRaLGwBXAgALAAkJYRaLGwBXAgAAAA==.Valyteilssra:BAAALgAECgMJCAAAAA==.Vanity:BAAALgAECgMJBAAAAA==.Varindra:BAAALgAECgMJBAABLgAFFAUJCQAVAGQYAA==.Vasoline:BAAALgAECgkJDAAAAA==.',
Ve='Vegà:BAABLgAECn8oAAIHAAkJ+BGCGgDCAQAHAAkJ+BGCGgDCAQAAAA==.Veina:BAAALgADCgQJCAAAAA==.Velyndris:BAAALgAECgYJCwAAAA==.Velysia:BAAALgADCgMJAwAAAA==.Vendettis:BAAALgADCgYJBgAAAA==.Verin:BAAALgAECgMJBQAAAA==.Vetraugr:BAAALgADCgMJAwABLgAECgYJDQAUAAAAAA==.Vextaerin:BAAALgAECgYJDQAAAA==.Vextarin:BAAALgADCgEJAQABLgAECgYJDQAUAAAAAA==.Veylyn:BAAALgADCgEJAQAAAA==.',
Vi='Virulent:BAAALgADCgMJAwAAAA==.Vivienreed:BAAALgAECgEJAgABLgAFFAQJCwAlABUMAA==.',
Vo='Voidhax:BAAALgAECgUJBQAAAA==.Voidi:BAABLgAECn8XAAQbAAcJVyOsFQBiAgAbAAcJtCKsFQBiAgAkAAQJESEBDQBPAQAnAAEJtAOkDwAoAAAAAA==.Voidyo:BAACLgAFFH8PAAIYAAQJuxYGNgAoAQAYAAQJuxYGNgAoAQAuAAQKfxAAAhgACAmuHqc2ANcBABgACAmuHqc2ANcBAAAA.Voralyth:BAAALgADCggJCQAAAA==.Voranne:BAABLgAECn8uAAIGAAkJ0QoJJQCEAQAGAAkJ0QoJJQCEAQAAAA==.Vortice:BAABLgAECn9CAAQQAAkJTBGeJgCfAQAQAAkJTBGeJgCfAQAIAAgJKA50VQBDAQAjAAIJQAfbKABOAAAAAA==.Vowwel:BAAALgAECgEJAQAAAA==.',
Vy='Vyserlai:BAAALgADCgUJBQAAAA==.',
Wa='War:BAAALgAECgYJBwAAAA==.Ware:BAAALgADCgcJBwAAAA==.Warraxgos:BAAALgADCgkJHgABLgAECgkJKgAXAJUeAA==.Warraxhunt:BAAALgAECgIJAgABLgAECgkJKgAXAJUeAA==.Warraxmonk:BAAALgADCgYJBgABLgAECgkJKgAXAJUeAA==.',
We='Weißenacht:BAAALgAECgMJAwAAAA==.',
Wh='Wheatstraw:BAAALgADCgYJDQAAAA==.Whiskeyjak:BAABLgAECn8lAAMOAAkJJxxnEQC+AQAOAAUJzSBnEQC+AQAJAAgJOg+5MgBtAQAAAA==.',
Wi='Willowest:BAABLgAECn82AAITAAkJMxuBFwCFAgATAAkJMxuBFwCFAgAAAA==.',
Wr='Wrathstorm:BAABLgAECn8pAAIjAAkJ8h59BACVAgAjAAkJ8h59BACVAgAAAA==.Wrekonhoof:BAAALgAECgEJAQAAAA==.',
Wt='Wtfpie:BAACLgAFFH8WAAIRAAUJsxc4GABEAQARAAUJsxc4GABEAQAuAAQKfzoAAhEACQk3IzcMAPwCABEACQk3IzcMAPwCAAAA.',
Wu='Wurmoneonine:BAAALgADCgUJBQABLgAECgkJMAALAIYXAA==.Wurmy:BAABLgAECn8wAAMLAAkJhhecHABPAgALAAkJhhecHABPAgAKAAYJSBOVOgANAQAAAA==.',
Wy='Wyndrunner:BAAALgADCgkJCQABLgAFFAMJBwATAAsCAA==.',
['Wá']='Wárgbáte:BAAALgADCgcJBwAAAA==.',
Xa='Xalgas:BAABLgAECn8YAAIGAAYJaxaVKwB/AQAGAAYJaxaVKwB/AQAAAA==.Xanier:BAAALgAECgQJCAAAAA==.Xanivus:BAAALgADCgIJAgAAAA==.',
Xe='Xelagos:BAABLgAECn8gAAQWAAkJMRE4FwBLAQAWAAgJKhA4FwBLAQAlAAQJ6BbBJgDsAAAmAAMJ5BWvUwB4AAAAAA==.Xerxesjr:BAAALgADCgEJAQAAAA==.',
Xi='Xioamara:BAAALgAECgcJCgAAAA==.',
Xo='Xorm:BAAALgAECgkJBgAAAA==.',
Xx='Xxd:BAAALgAECgEJAQAAAA==.',
Ya='Yanella:BAABLgAECn8wAAMCAAkJ3BzoCADIAgACAAkJ3BzoCADIAgADAAEJcwWmWgAtAAAAAA==.',
Yi='Yispally:BAAALgAECgQJCgAAAA==.Yisshaman:BAABLgAECn8eAAIQAAkJXhvZDADQAgAQAAkJXhvZDADQAgAAAA==.',
Yo='Yo:BAAALgAFFAIJAwABLgAFFAgJJQAOAJojAA==.Yogibearz:BAAALgAECgQJBwABLgAECgUJFAAHAJYQAA==.Yogimonk:BAABLgAECn8UAAIHAAUJlhA6SwDCAAAHAAUJlhA6SwDCAAAAAA==.',
Za='Zanax:BAAALgAECgcJCAAAAA==.Zandarbribbs:BAABLgAECn8hAAIEAAgJRRW/VgCvAQAEAAgJRRW/VgCvAQAAAA==.Zapzug:BAAALgADCgYJDQAAAA==.Zaratras:BAAALgAECgEJAQAAAA==.Zaydozer:BAAALgAECgcJCwAAAA==.',
Ze='Zenmetsu:BAAALgAECgUJBgAAAA==.Zennya:BAABLgAECn8tAAILAAkJPBf6HABMAgALAAkJPBf6HABMAgAAAA==.Zeon:BAAALgAECgYJEQAAAA==.',
Zi='Zikoth:BAAALgADCgEJAQAAAA==.Zingers:BAAALgAECgMJAwAAAA==.',
Zm='Zmd:BAAALgAECgYJEQAAAA==.',
Zo='Zoeso:BAABLgAECn83AAMHAAkJfx/9BQDOAgAHAAkJfx/9BQDOAgAVAAUJyQ50VQDoAAAAAA==.',
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
