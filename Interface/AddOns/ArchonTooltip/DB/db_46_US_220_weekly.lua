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
local provider = {region='US',realm='Thunderhorn',name='US',type='weekly',zone=46,date='2026-06-14',data={Ab='Absynthe:BAAALgAECgYJDQAAAA==.Abysmal:BAAALgADCgYJBgABLgAECgkJIwABAEoOAA==.Abÿss:BAAALgAECgMJCAAAAA==.',
Ac='Achêrøn:BAAALgADCgcJBwAAAA==.Acoghai:BAAALgADCgcJDQAAAA==.',
Ad='Adoweld:BAAALgADCgcJBQAAAA==.Adøland:BAAALgADCgYJBgAAAA==.',
Ae='Aeliis:BAABLgAECn8lAAMCAAkJ5AwgLABmAQACAAkJ5AwgLABmAQADAAMJbQQLYQB0AAAAAA==.Aellart:BAAALgAECgEJAgAAAA==.Aeriona:BAABLgAECn81AAIEAAkJHxxiIwB3AgAEAAkJHxxiIwB3AgAAAA==.Aerosoul:BAAALgADCgEJAQAAAA==.',
Ag='Agamsi:BAABLgAECn8UAAIFAAgJcwthGADsAAAFAAgJcwthGADsAAAAAA==.',
Ai='Aine:BAABLgAECn8nAAMCAAgJuRm1FQAkAgACAAgJuRm1FQAkAgAGAAYJ6wA/WABcAAAAAA==.Ainek:BAAALgAECgUJBwAAAA==.Ainkor:BAAALgAFFAMJAwABLgAFFAMJCgAHADsNAA==.',
Aj='Ajani:BAABLgAECn8VAAMHAAgJ7xqqFQD+AQAHAAgJ7xqqFQD+AQAIAAQJXgjtXACgAAAAAA==.',
Ak='Akyospirit:BAABLgAECn88AAIJAAkJGA2PRACZAQAJAAkJGA2PRACZAQAAAA==.Akyowindz:BAAALgAECgQJBAAAAA==.',
Al='Al:BAAALgAECgYJEAABLgAFFAQJBgAKAMoWAA==.Alava:BAAALgADCgEJAQAAAA==.Aliatra:BAABLgAECn9CAAMLAAkJxRJvHQDaAQALAAkJxRJvHQDaAQAMAAEJmggX8QAfAAAAAA==.Alinth:BAAALgAECgMJBQAAAA==.Almosthuman:BAAALgAECgYJCgAAAA==.Alpha:BAABLgAECn87AAIBAAkJ7x3cGgC3AgABAAkJ7x3cGgC3AgAAAA==.Alroy:BAAALgAECgkJDgAAAA==.Aluina:BAAALgAFFAEJAQAAAA==.Alustryelle:BAAALgADCgkJEgABLgAECgkJMgAJABsOAA==.Alykia:BAAALgADCgYJBgAAAA==.',
Am='Amamonk:BAABLgAECn9CAAMHAAkJkhlHFgD3AQAHAAkJDRVHFgD3AQAIAAYJUSBiGwDSAQAAAA==.Amandara:BAAALgADCgUJBQAAAA==.Ammert:BAABLgAECn80AAINAAkJkhBuCADfAQANAAkJkhBuCADfAQAAAA==.Amonet:BAAALgADCgYJEQAAAA==.',
An='Anathema:BAAALgAECgQJBwAAAA==.Anchovy:BAAALgAFFAMJBAABLgAFFAgJJQAOAJojAA==.Andou:BAAALgADCgcJBwAAAA==.Angeldracul:BAAALgADCgQJBwAAAA==.Angelove:BAAALgAECgQJDAAAAA==.Anglico:BAAALgAECgQJBQABLgAECgkJJwAPAMwgAA==.Angliko:BAAALgAECgUJCAABLgAECgkJJwAPAMwgAA==.Anglikoo:BAAALgADCggJCAABLgAECgkJJwAPAMwgAA==.Anomandaris:BAABLgAECn8eAAMQAAkJVBXnJgCyAQAQAAgJ4RbnJgCyAQAJAAEJTAY12gArAAAAAA==.Anquan:BAABLgAECn8oAAIRAAgJGxv8MwAtAgARAAgJGxv8MwAtAgAAAA==.',
Ap='Apedemak:BAAALgAECgYJDwAAAA==.Aphobias:BAAALgAECgUJCwAAAA==.Aphradite:BAAALgADCgYJCwAAAA==.Apothica:BAABLgAECn8XAAIBAAgJ4Ay8hwBlAQABAAgJ4Ay8hwBlAQAAAA==.Apothicc:BAABLgAECn8kAAMRAAgJVhZzRwDqAQARAAgJVhZzRwDqAQASAAEJAABGRgAAAAAAAA==.Appalonio:BAAALgADCgcJBQAAAA==.Appaur:BAAALgADCgEJAQAAAA==.Appolymi:BAABLgAECn8xAAITAAkJjwX1bgBgAQATAAkJjwX1bgBgAQAAAA==.Apraxia:BAAALgADCgUJBQAAAA==.Aprionos:BAABLgAECn82AAIBAAgJ7AW/rQAiAQABAAgJ7AW/rQAiAQAAAA==.',
Ar='Arakek:BAAALgADCgcJCAAAAA==.Arataena:BAAALgADCgkJFgAAAA==.Arceus:BAAALgAECgMJBQAAAA==.Archibald:BAAALgAECgYJBgAAAA==.Aredhël:BAAALgADCgYJDgAAAA==.Argentavis:BAAALgAECggJEgABLgAECggJEwAUAAAAAA==.Argobow:BAAALgAFFAEJAQAAAA==.Argonaut:BAAALgAFFAMJBAAAAA==.Arice:BAEALgAECgEJAQABLgAECgkJOQARAP0cAA==.Aristella:BAAALgADCgMJAwAAAA==.Arkken:BAABLgAECn8bAAIVAAcJ2iLSDgCxAgAVAAcJ2iLSDgCxAgABLgAECgkJRQADAJUjAA==.Artee:BAAALgAECgEJAQAAAA==.Artémis:BAABLgAECn8iAAITAAgJgRDFaQBsAQATAAgJgRDFaQBsAQAAAA==.',
As='Ascender:BAAALgAECgQJBAAAAA==.Ashadox:BAAALgAECgUJCgAAAA==.Asheritâ:BAAALgADCgcJBwAAAA==.Ashvalis:BAABLgAECn8cAAIWAAcJzSPFCQCaAgAWAAcJzSPFCQCaAgAAAA==.Asillyhunter:BAAALgADCgMJAwAAAA==.Asillypally:BAABLgAECn8kAAIEAAgJeBYaXgDJAQAEAAgJeBYaXgDJAQAAAA==.Askr:BAABLgAECn8qAAMTAAkJExHrPQDmAQATAAkJ6RDrPQDmAQAFAAYJnwqrIACpAAAAAA==.Asphar:BAABLgAECn8wAAMTAAkJ2iWEAwBXAwATAAkJ2iWEAwBXAwAFAAMJChP8LABhAAAAAA==.Asphel:BAAALgAECgEJAQAAAA==.Asteroth:BAAALgAECgEJAQAAAA==.',
Au='Aung:BAACLgAFFH8UAAIXAAQJACPtBgCTAQAXAAQJACPtBgCTAQAuAAQKf0sAAxcACQkkJlcBAGgDABcACQkkJlcBAGgDABgAAQmNBikqASIAAAAA.Auri:BAAALgADCgkJIQAAAA==.',
Av='Avatan:BAAALgAECgMJAwABLgAECgkJLgAKAKgNAA==.Avralis:BAAALgADCgMJAwABLgAECggJHQAYAEocAA==.',
Ax='Axex:BAAALgAECgkJDQAAAA==.',
Az='Azamii:BAABLgAECn88AAMQAAkJOSJ/BQAEAwAQAAkJOSJ/BQAEAwAJAAYJQRgUOwCVAQAAAA==.Azarion:BAABLgAECn84AAMZAAgJch1BCwCKAQAZAAcJnRtBCwCKAQAaAAYJlBlSYAB/AQAAAA==.Azill:BAACLgAFFH8WAAIIAAYJIhr0BgCiAQAIAAYJIhr0BgCiAQAuAAQKfyYAAggACAleHjMKANUCAAgACAleHjMKANUCAAAA.Azzrael:BAABLgAECn8qAAIOAAkJzBDSFADAAQAOAAkJzBDSFADAAQAAAA==.',
Ba='Baalalmerat:BAAALgAECgIJAgAAAA==.Bandi:BAAALgAECgYJEwAAAA==.Bartrak:BAACLgAFFH8JAAMGAAMJbAdqKAC0AAAGAAMJbAdqKAC0AAADAAIJNwoRPwB3AAAuAAQKfxsAAwYACQk/E1AjAK4BAAYACQk/E1AjAK4BAAMABQlsEbhaAJIAAAAA.',
Be='Bearfucius:BAABLgAECn8ZAAIIAAkJmQfHMwAyAQAIAAkJmQfHMwAyAQAAAA==.Bearrific:BAACLgAFFH8FAAIbAAIJoBAfMACfAAAbAAIJoBAfMACfAAAuAAQKfyYAAhsACQnvGoUOAD8CABsACQnvGoUOAD8CAAAA.Beawulf:BAAALgAECgQJBAAAAA==.Behomadra:BAAALgAECgkJCQAAAA==.Belista:BAAALgAECgQJBAAAAA==.Bethel:BAAALgADCgYJCAAAAA==.Beyond:BAAALgAECgMJAwAAAA==.',
Bf='Bfresh:BAAALgADCgcJDgAAAA==.',
Bi='Bibidi:BAAALgAECgQJBAAAAA==.Billie:BAAALgADCgcJAgAAAA==.Billthekid:BAAALgAECgYJCwAAAA==.Billybobb:BAAALgAECgYJDgAAAA==.Biney:BAABLgAECn8eAAIOAAYJ+RufFgCNAQAOAAYJ+RufFgCNAQAAAA==.Binksy:BAACLgAFFH8UAAIKAAYJIhQbEQB5AQAKAAYJIhQbEQB5AQAuAAQKfyoAAgoACQkFHskNAOcCAAoACQkFHskNAOcCAAAA.Biscuit:BAACLgAFFH8lAAIOAAgJmiMFAQAJAgAOAAgJmiMFAQAJAgAuAAQKfyIAAg4ACQkfJe4AAJYDAA4ACQkfJe4AAJYDAAAA.Bitcoìn:BAAALgAECgEJAgAAAA==.',
Bl='Blaam:BAAALgAECgQJEgAAAA==.Blazin:BAACLgAFFH8oAAIBAAYJUxhEMACqAQABAAYJUxhEMACqAQAuAAQKfzQAAgEACQkGHxkSAOwCAAEACQkGHxkSAOwCAAAA.Blep:BAAALgAECgYJCgAAAA==.Blgunc:BAAALgAECgkJEQAAAA==.Blinkzy:BAAALgAECgUJCQAAAA==.Blitzongosh:BAAALgADCgEJAQAAAA==.Bloui:BAAALgAECgQJCwAAAA==.Bluesummers:BAAALgADCgkJCQAAAA==.',
Bo='Boba:BAAALgAECgYJBgABLgAFFAgJJQAOAJojAA==.Bongrips:BAAALgADCgcJCQAAAA==.Boomboom:BAAALgAECgUJCAAAAA==.Borlok:BAAALgAFFAQJBQAAAQ==.',
Br='Brannigan:BAABLgAECn88AAIOAAkJFiQUAgAsAwAOAAkJFiQUAgAsAwAAAA==.Braulioo:BAAALgAFFAMJAwAAAA==.Breebbs:BAAALgAECgUJBQAAAA==.Briantu:BAABLgAECn8qAAMJAAkJNQV4gwDUAAAJAAgJ/QF4gwDUAAAQAAEJEATvtgAjAAAAAA==.Brickitphil:BAABLgAECn8dAAISAAgJ8BmFBwAdAgASAAgJ8BmFBwAdAgAAAA==.Briiz:BAAALgADCgkJDAAAAA==.Brlolock:BAAALgAECgEJAQAAAA==.Brollo:BAAALgADCgEJAQAAAA==.Brud:BAAALgADCgYJAwAAAA==.Brönwyn:BAAALgAECgMJCAAAAA==.',
Bu='Bubblegumdrp:BAAALgAECgMJAwAAAA==.Bubblicious:BAAALgADCgUJCQAAAA==.Buckets:BAAALgAECgcJEgABLgAECggJCgAUAAAAAA==.Budi:BAAALgADCgcJCAAAAA==.Bulldan:BAABLgAECn8mAAINAAgJBx6JBQAuAgANAAgJBx6JBQAuAgAAAA==.Bullvi:BAAALgAECgYJBgAAAA==.',
['Bä']='Bärkler:BAABLgAECn8cAAMcAAkJaSL5BAC+AgAcAAkJaSL5BAC+AgAOAAEJHBiMTgA9AAAAAA==.',
['Bé']='Béckley:BAAALgAECggJEgAAAA==.Béckléy:BAAALgAECgUJDQABLgAECggJEgAUAAAAAA==.',
Ca='Caatha:BAAALgAECgQJBAAAAA==.Caleanone:BAAALgAFFAIJAgABLgAFFAQJBgAKAMoWAA==.Calel:BAAALgAECgkJEAAAAA==.Callox:BAACLgAFFH8GAAIKAAQJyhbCLwDsAAAKAAQJyhbCLwDsAAAuAAQKfysABAoACAkFHNEoALYBAAoACAkhG9EoALYBABwABQknG+0RAIIBAA4ABgllDOAuAMQAAAAA.Cantelope:BAAALgADCgYJBgAAAA==.Capslock:BAAALgAECgQJAwAAAA==.Cara:BAAALgADCgIJAgAAAA==.Carahail:BAACLgAFFH8QAAMMAAQJwAbWPQC1AAAMAAQJwAbWPQC1AAALAAEJ6wFKVAApAAAuAAQKfzQAAwwACQmYFKAiADICAAwACQmYFKAiADICAAsABgkAD8RCAP4AAAAA.Catriona:BAABLgAECn8iAAITAAkJgwpdYACDAQATAAkJgwpdYACDAQAAAA==.Cazmeer:BAAALgAECgYJEAAAAA==.',
Ce='Celés:BAAALgAECgUJBQAAAA==.',
Ch='Charcuterie:BAACLgAFFH8mAAIHAAgJPh1ABwATAgAHAAgJPh1ABwATAgAuAAQKfyAAAwcACQnYIVwJAPMCAAcACQnYIVwJAPMCAAgAAQlxHc6CAFAAAAAA.Chaír:BAAALgAECgEJBQAAAA==.Cheezeburg:BAAALgAECgcJCAABLgAECgkJHwAHAC4ZAA==.Cheezus:BAAALgAECgUJCAABLgAECgkJHwAHAC4ZAA==.Cherrbeår:BAAALgADCgcJBwAAAA==.Cherudim:BAACLgAFFH8FAAMZAAMJ4wsjDwCHAAAaAAMJ4wtRgADBAAAZAAIJrwIjDwCHAAAuAAQKfyYAAxkACAkiF44JACcCABkACAmBFY4JACcCABoACAl3FCxXAJcBAAAA.Chillainkor:BAACLgAFFH8KAAIHAAMJOw3/OgC3AAAHAAMJOw3/OgC3AAAuAAQKfykAAgcACQk7FmcYAOIBAAcACQk7FmcYAOIBAAAA.Chillidán:BAABLgAECn8kAAIYAAkJgwZbhAAUAQAYAAkJgwZbhAAUAQAAAA==.Chippmagi:BAABLgAECn8gAAIBAAgJ9RoLVQDbAQABAAgJ9RoLVQDbAQAAAA==.Chippndots:BAAALgAECgYJDAABLgAECggJIAABAPUaAA==.Chirp:BAAALgAECgEJAQAAAA==.Chives:BAAALgAECgQJBAAAAA==.Choggie:BAACLgAFFH8NAAIdAAQJRxGqIgAFAQAdAAQJRxGqIgAFAQAuAAQKfz4AAh0ACQl2IEUFAD4DAB0ACQl2IEUFAD4DAAAA.Chronocolter:BAAALgADCgMJAwAAAA==.Chronosaren:BAABLgAECn8UAAIBAAkJyxEfWADSAQABAAkJyxEfWADSAQAAAA==.Chåir:BAAALgAECgEJAgAAAA==.',
Ci='Cinterax:BAAALgAECgIJAgABLgAECgkJPAAOABYkAA==.',
Cj='Cjrej:BAABLgAECn85AAIBAAkJKhAVUwDgAQABAAkJKhAVUwDgAQAAAA==.',
Cl='Claytonis:BAAALgAECgEJAQAAAA==.Cloudnine:BAAALgAECgQJBAAAAA==.',
Co='Colterr:BAAALgADCgEJAQAAAA==.Cons:BAABLgAECn8zAAQDAAkJGR46BgAdAwADAAkJGR46BgAdAwACAAMJKw3YZQCWAAAGAAEJ+xJkhAAzAAAAAA==.Corellon:BAABLgAECn8rAAITAAkJnRsgLQAmAgATAAkJnRsgLQAmAgAAAA==.Costcohotdog:BAABLgAFFH8KAAMHAAMJLR1IGACsAAAHAAMJLR1IGACsAAAVAAEJOQBpGgAYAAABLgAFFAgJJQAOAJojAA==.Cougarclaws:BAAALgAECgUJCQAAAA==.',
Cr='Craftsman:BAAALgADCgUJBQAAAA==.Craigchrist:BAAALgAECgYJBgAAAA==.Cranee:BAABLgAECn83AAIaAAkJZhTaMgAMAgAaAAkJZhTaMgAMAgAAAA==.Cranium:BAAALgAECgUJCAAAAA==.Crazytasty:BAABLgAECn8mAAITAAgJXyKQHQBxAgATAAgJXyKQHQBxAgAAAA==.Crumbo:BAAALgAECgYJBgAAAA==.Cryoburn:BAABLgAECn8fAAIBAAgJWB1rWAAwAgABAAgJWB1rWAAwAgAAAA==.Cryoshock:BAABLgAFFH8HAAIQAAMJwBayMgC/AAAQAAMJwBayMgC/AAAAAA==.',
Cu='Cutty:BAAALgAECgUJBgAAAA==.',
['Cø']='Cøns:BAAALgAECgYJCgAAAA==.',
Da='Daario:BAABLgAECn8TAAIYAAcJsB+pNQAhAgAYAAcJsB+pNQAhAgAAAA==.Dabare:BAAALgADCgUJAQAAAA==.Dabora:BAAALgAECgEJAQABLgAECgkJLAAeAAwfAA==.Dabßod:BAAALgAECgQJBAAAAA==.Dabûra:BAABLgAECn8sAAQeAAkJDB8JCQAzAgAeAAgJTB0JCQAzAgALAAYJTR4JRAD5AAAfAAcJehDKMADjAAAAAA==.Daenerys:BAAALgAECgIJBgAAAA==.Dahouse:BAAALgADCgQJAwAAAA==.Dahpeht:BAAALgADCgkJEwAAAA==.Damda:BAAALgADCgIJAgAAAA==.Dandypooh:BAAALgAECgYJBgABLgAECgcJDQAUAAAAAA==.Danksamdi:BAAALgAECgEJAQAAAA==.Dante:BAAALgAECgcJCwAAAA==.Darige:BAAALgAECgIJAgAAAA==.Darim:BAAALgAECgYJBgABLgAECgkJKQABAFwaAA==.Darrow:BAAALgAECggJCAAAAA==.Darthspawn:BAABLgAECn8mAAIRAAgJJgzifABoAQARAAgJJgzifABoAQAAAA==.Daryl:BAAALgAECgQJBAAAAA==.Daryn:BAAALgAECgYJDAAAAA==.Davidbowy:BAABLgAECn8ZAAMgAAgJsA1fLABCAQAgAAcJ7whfLABCAQATAAcJYQ5EiwAlAQABLgAECgYJBwAUAAAAAA==.',
De='Deadchops:BAAALgAECgEJAgABLgAECgcJCAAUAAAAAA==.Deathnstuf:BAAALgAECgQJBgAAAA==.Deathollow:BAAALgAECgEJBAAAAA==.Delver:BAAALgADCgYJBgABLgAECgkJKQABAFwaAA==.Demai:BAAALgAECggJCQAAAA==.Demina:BAAALgAECgQJBgABLgAECggJHQAYAEocAA==.Demonainkor:BAAALgAECgYJBgABLgAFFAMJCgAHADsNAA==.Demonicfury:BAAALgAECgYJBwAAAA==.Demonthrall:BAAALgAECgEJAQAAAA==.Dencity:BAABLgAECn88AAMDAAkJshdfEgBQAgADAAkJUhZfEgBQAgACAAYJbxeGOAAVAQAAAA==.Dendwran:BAAALgAECgkJCQAAAA==.Desden:BAABLgAECn88AAIfAAkJ5BL6EwC0AQAfAAkJ5BL6EwC0AQAAAA==.Destined:BAAALgAECgYJBwAAAA==.Devianchi:BAABLgAECn8nAAMVAAgJ+B+FCQC5AgAVAAgJ+B+FCQC5AgAIAAcJIh9kGADtAQABLgAECgkJFwAdAHcZAA==.Devitodevour:BAABLgAECn8hAAMaAAgJPRsxQADcAQAaAAgJmxkxQADcAQAZAAMJXBkENQDiAAAAAA==.',
Dg='Dgbugs:BAACLgAFFH8KAAIRAAMJoCLskwDgAAARAAMJoCLskwDgAAAuAAQKfzIAAhEACAk9I4knAGICABEACAk9I4knAGICAAAA.',
Dh='Dhbert:BAABLgAECn8sAAIhAAkJ5xFfFgC1AQAhAAkJ5xFfFgC1AQAAAA==.Dhomeli:BAAALgAECgQJBQABLgAECgYJHgAOAPkbAA==.',
Di='Dirtchez:BAAALgAECgIJAwAAAA==.Disastrophy:BAAALgAECgYJEQABLgAECgcJCAAUAAAAAA==.Disturbed:BAABLgAECn8/AAQNAAkJ4yH9AAAJAwANAAkJsCH9AAAJAwAaAAgJNRuvJgBCAgAZAAEJAADbYgBJAAAAAA==.Disturbio:BAAALgAECgEJAQABLgAECgkJPwANAOMhAA==.Divinepsycho:BAAALgADCgcJBwAAAA==.Divitiacus:BAAALgAECgYJBgAAAA==.',
Dj='Djowio:BAAALgADCgYJBgABLgAECggJIwAaABoiAA==.',
Dk='Dknightresh:BAAALgAECgcJBwABLgAECgcJJwAKAH0SAA==.',
Dm='Dmz:BAAALgADCgUJBgAAAA==.',
Do='Docen:BAAALgADCgkJCwAAAA==.Domfromgears:BAAALgAECgQJCQAAAA==.Dominance:BAAALgAECgEJAQAAAA==.Doomgaze:BAAALgADCgMJAQAAAA==.Dorc:BAAALgAECgMJBQAAAA==.Dotyou:BAAALgAECgIJAgAAAA==.Doudouzz:BAAALgAECgQJDQAAAA==.',
Dr='Dracthor:BAAALgADCgQJBAAAAA==.Draejin:BAAALgAECgkJDwAAAA==.Dragonfist:BAAALgADCgcJBwAAAA==.Dragonlore:BAAALgAFFAEJAgAAAA==.Dragthyr:BAAALgAECgUJCgAAAA==.Dramûl:BAABLgAECn8dAAITAAgJcRi0TwCwAQATAAgJcRi0TwCwAQAAAA==.Dreadedmonk:BAAALgAECgEJAgAAAA==.Druiaier:BAAALgADCgYJCQAAAA==.Druidibrume:BAAALgAECgMJDAAAAA==.Druknatsu:BAAALgAECgcJDAAAAA==.Drunkdragon:BAABLgAECn8UAAIIAAgJRRLpGwD9AQAIAAgJRRLpGwD9AQAAAA==.Drwhodunnit:BAAALgAECgMJBgAAAA==.',
Du='Dubbzilla:BAAALgAECgEJAQAAAA==.Dudedruid:BAAALgADCgUJBQAAAA==.Duncán:BAABLgAFFH8JAAQEAAUJ+RsSMgBHAQAEAAUJ+RsSMgBHAQAiAAEJoBWuFwA5AAAdAAEJmwRATgAsAAABLgAFFAYJCwAJAIYiAA==.Dustyknight:BAABLgAECn8tAAIhAAkJcw9lGACeAQAhAAkJcw9lGACeAQAAAA==.',
Dw='Dwell:BAAALgADCgkJJQAAAA==.',
Dy='Dyavola:BAAALgAECgUJBQAAAA==.',
Ea='Earthquack:BAAALgAECgUJBQABLgAECggJGwAiADMVAA==.',
Ed='Edge:BAABLgAECn8eAAIJAAgJShXHNQDXAQAJAAgJShXHNQDXAQAAAA==.',
Ee='Eelenna:BAABLgAECn8ZAAMjAAkJLhxgBgCSAgAjAAkJLhxgBgCSAgAQAAUJwRBnUwD4AAABLgAFFAUJDwASAMMTAA==.',
El='Elamlock:BAAALgADCgYJCwAAAA==.Eleathe:BAAALgAFFAQJBAABLgAECggJHQAYAEocAA==.Eleros:BAABLgAECn8wAAIYAAkJsB+iEAC7AgAYAAkJsB+iEAC7AgAAAA==.Elicio:BAAALgAECgYJEAAAAA==.Ellysial:BAAALgADCgUJBQAAAA==.Elphinia:BAABLgAECn8zAAMbAAkJqxnqEAAgAgAbAAkJqxnqEAAgAgAkAAEJ4BFlIAAxAAABLgAFFAQJCwAQAMgMAA==.Elreÿ:BAAALgADCgEJAQAAAA==.Elyas:BAAALgAECgIJBAAAAA==.',
Em='Emberwrath:BAAALgADCgMJAwAAAA==.Embr:BAAALgAECgMJAwAAAA==.Emosdnem:BAAALgAECgQJBQAAAA==.Emt:BAAALgAECgQJBAAAAA==.',
En='Endarial:BAAALgAECgUJCwAAAA==.Enoki:BAACLgAFFH8RAAIJAAUJlRc0HACDAQAJAAUJlRc0HACDAQAuAAQKfxUAAwkACQkuHAYbAEACAAkACQkuHAYbAEACABAAAgl8HENuAJwAAAEuAAUUCAkgAAwAuxwA.',
Er='Eraduckated:BAAALgAECgYJCAABLgAECggJGwAiADMVAA==.Erah:BAAALgADCgUJDQAAAA==.Ereir:BAAALgAECgMJAwABLgAFFAQJBgAKAMoWAA==.Erzascarlett:BAAALgAECgcJBwAAAA==.',
Es='Esco:BAAALgADCgMJAwAAAA==.Esile:BAAALgAECgQJBAABLgAECgkJPAALANkRAA==.',
Et='Eternalnow:BAAALgADCgEJAQAAAA==.',
Ev='Evelith:BAAALgADCgYJBgAAAA==.Everlife:BAABLgAECn8VAAIDAAcJRROnJQCiAQADAAcJRROnJQCiAQAAAA==.',
Ex='Exemptt:BAAALgAECgkJBQAAAA==.Exo:BAAALgADCgkJDwAAAA==.',
Fa='Falconpunch:BAAALgAECgYJCwAAAA==.Farnesë:BAAALgADCgUJBwABLgADCgcJBwAUAAAAAA==.Fauzzie:BAAALgAECgIJAgAAAA==.Fayrel:BAAALgAECgYJCQAAAA==.',
Fe='Fedders:BAACLgAFFH8GAAIEAAIJFB2lgQCrAAAEAAIJFB2lgQCrAAAuAAQKfykAAgQACQlGJoYHAFsDAAQACQlGJoYHAFsDAAAA.Felaids:BAACLgAFFH8VAAMaAAUJkBM0YwD8AAAaAAUJ+A80YwD8AAANAAEJSBDJJQBJAAAuAAQKfywAAxoACQmMGhcsACgCABoACAmMGhcsACgCABkAAwkSCLpEAKIAAAAA.Felimonk:BAAALgAECgQJBAABLgABCgQJBQAUAAAAAA==.Felpecs:BAAALgAECggJDgAAAA==.Fero:BAAALgAECgUJBQAAAA==.Feyda:BAABLgAECn8pAAIBAAkJ7wf1ewB+AQABAAkJ7wf1ewB+AQAAAA==.',
Fi='Fillon:BAACLgAFFH8IAAIEAAQJPxtILQBVAQAEAAQJPxtILQBVAQAuAAQKfzMAAgQACQmxJSYNAPsCAAQACQmxJSYNAPsCAAAA.Fionas:BAAALgADCgQJBAAAAA==.Firerybush:BAAALgAECgYJBwABLgAFFAMJBgAKAFoUAA==.Firessar:BAAALgAECgcJDAAAAA==.Firexcracker:BAAALgAECgMJBAAAAA==.Fishfood:BAABLgAECn88AAISAAkJIxUECAAQAgASAAkJIxUECAAQAgAAAA==.Fishlover:BAAALgADCgUJBQAAAA==.Fixer:BAABLgAECn8eAAIiAAYJRSLBDQDmAQAiAAYJRSLBDQDmAQAAAA==.',
Fk='Fk:BAAALgAFFAMJAwABLgAFFAYJCwAJAIYiAA==.',
Fo='Foe:BAEALgAECggJEwAAAA==.Folkvar:BAAALgADCgcJDAAAAA==.',
Fr='Frankngibbon:BAAALgADCgYJBgAAAA==.Frimm:BAAALgAECggJDgAAAA==.Frimthemage:BAACLgAFFH8LAAIBAAQJrgxgZwAbAQABAAQJrgxgZwAbAQAuAAQKfzEAAgEACQlDIOUnAHkCAAEACQlDIOUnAHkCAAAA.Frostmaster:BAABLgAECn8bAAIBAAcJOhwoWwDKAQABAAcJOhwoWwDKAQAAAA==.',
Fu='Funbunz:BAAALgAECgcJDAAAAA==.',
['Fí']='Fízban:BAAALgAECgQJCAAAAA==.',
['Fø']='Førd:BAACLgAFFH8NAAMlAAUJ1AvLBQABAQAlAAQJFQzLBQABAQAmAAMJ0QrrRACvAAAuAAQKfy8ABCUACAmQHRoLACoCACUABwlLGhoLACoCACYABwlOGSUkAJwBABYAAwkIAjw5ADwAAAAA.',
Ga='Gammon:BAABLgAECn82AAMQAAkJlh+WCADSAgAQAAkJlh+WCADSAgAJAAgJdxpEHABnAgAAAA==.Gangrene:BAABLgAECn8yAAMRAAkJnxOfVQDCAQARAAkJnxOfVQDCAQAhAAgJCQuWLAD1AAAAAA==.Gary:BAAALgAECgQJCgAAAA==.Garzhvog:BAAALgAECgIJAgAAAA==.Gash:BAAALgAECgMJAwAAAA==.Gaspasser:BAABLgAECn83AAMkAAkJux0qAgDDAgAkAAkJux0qAgDDAgAbAAEJphUaWABCAAAAAA==.Gaviin:BAABLgAECn84AAIkAAkJGCF5AgCvAgAkAAkJGCF5AgCvAgAAAA==.',
Ge='Gearador:BAAALgADCgcJAQAAAA==.Geisten:BAAALgAECgYJEwAAAA==.Genovia:BAAALgADCgIJAgABLgAECggJEwAUAAAAAA==.Gerhart:BAABLgAECn8sAAQPAAkJSxmtCADlAQAPAAkJ6hStCADlAQAYAAcJxBmQXgBqAQAXAAMJQxDfUgBoAAAAAA==.Getcarried:BAAALgADCgMJAwABLgAFFAYJKAABAFMYAA==.Getty:BAAALgAECgcJEgAAAA==.',
Gf='Gfforgold:BAAALgADCgIJAgAAAA==.',
Gh='Ghosthunterx:BAAALgADCgEJAwAAAA==.Ghouldana:BAAALgADCgYJBgAAAA==.',
Gi='Gibbthok:BAAALgADCggJCAAAAA==.Gigachode:BAAALgAECgEJAwAAAA==.Gigarius:BAABLgAECn8iAAMiAAkJSSRQAgAOAwAiAAkJSSRQAgAOAwAEAAQJOBuqzwDyAAAAAA==.Gigglesworth:BAAALgAECgYJBgAAAA==.Gilamonster:BAAALgAECgYJCgAAAA==.',
Gl='Gladllimbo:BAAALgADCgEJAQAAAA==.Gleiten:BAAALgADCgMJAwAAAA==.Glonkins:BAABLgAECn8nAAQTAAkJWB8aDwDVAgATAAkJWB8aDwDVAgAgAAQJ9RRnMgAaAQAFAAEJAABuSAAAAAAAAA==.Glynden:BAAALgADCgEJAQAAAA==.',
Go='Goncor:BAACLgAFFH8PAAISAAUJwxNkDgAiAQASAAUJwxNkDgAiAQAuAAQKfykAAxIACQnkIEUEAIgCABIACQmYIEUEAIgCACEABQk+IxobAIIBAAAA.Gonnosuke:BAABLgAECn8UAAIEAAcJjgkwugAPAQAEAAcJjgkwugAPAQAAAA==.Gooseberry:BAAALgAECgEJAQAAAA==.Goosë:BAAALgADCgcJBwAAAA==.Gorrelord:BAAALgADCgEJAQABLgAFFAYJKAABAFMYAA==.Gortar:BAAALgADCgEJAQAAAA==.',
Gr='Granolah:BAAALgADCgcJCwABLgAECgkJLAAeAAwfAA==.Griffmonk:BAABLgAECn88AAIVAAkJCRv/FABuAgAVAAkJCRv/FABuAgAAAA==.Grumpydaemon:BAAALgAECgMJAwABLgAECgkJOAABAOsfAA==.Grumpymage:BAABLgAECn84AAIBAAkJ6x+GGgC5AgABAAkJ6x+GGgC5AgAAAA==.',
Gu='Gussy:BAAALgAECgQJBAABLgAECggJCgAUAAAAAA==.',
Ha='Hafsac:BAAALgAECgMJAwAAAA==.Halaranth:BAAALgAECgIJAgAAAA==.Hamasakura:BAAALgAECgYJBgAAAA==.Hanya:BAAALgAECgIJAgAAAA==.Hara:BAABLgAECn8aAAIMAAYJPRprQwCBAQAMAAYJPRprQwCBAQAAAA==.Hardlyknower:BAAALgADCgIJAgAAAA==.Hardord:BAABLgAECn8tAAIbAAkJUQ/mFwDZAQAbAAkJUQ/mFwDZAQAAAA==.Harrydotter:BAAALgAECgIJAgAAAA==.Haryle:BAAALgAECgUJCgAAAA==.Hayanne:BAABLgAECn84AAIOAAkJXxwtCQBhAgAOAAkJXxwtCQBhAgAAAA==.',
He='Healchucky:BAAALgAECgYJDQAAAA==.Healfire:BAAALgADCgYJBwAAAA==.Healisha:BAAALgAECgYJEAAAAA==.Healzjoogewd:BAAALgAECgEJAQAAAA==.Heina:BAAALgAECgYJBgAAAA==.Hershall:BAAALgAECgUJBQABLgAFFAQJFAAXAAAjAA==.',
Hi='Hitnrun:BAAALgAECgMJAwAAAA==.',
Ho='Hochunk:BAACLgAFFH8JAAMDAAMJHgeoNgCqAAADAAMJHgeoNgCqAAACAAEJ3wEKPAAmAAAuAAQKfysAAwMACQnfFPoTAD4CAAMACQn4E/oTAD4CAAIACQm6CR07AE4BAAAA.Hochunks:BAAALgAECgYJDQAAAA==.Holdenger:BAAALgADCgQJBAAAAA==.Holikow:BAABLgAECn8YAAIEAAkJnxAdbQCTAQAEAAkJnxAdbQCTAQAAAA==.Holyherpies:BAAALgAECgYJBgAAAA==.Holyllama:BAAALgADCgcJBwAAAA==.Holymousey:BAABLgAECn8fAAIdAAkJjREtJwDPAQAdAAkJjREtJwDPAQAAAA==.Holysnake:BAAALgAECgQJBAAAAA==.Holytady:BAAALgADCgcJDQAAAA==.Holytudd:BAABLgAECn8gAAIEAAgJixSIhQBjAQAEAAgJixSIhQBjAQAAAA==.Honeybun:BAAALgADCgQJAgAAAA==.Honorlife:BAABLgAECn8xAAIJAAgJDhvhHwBOAgAJAAgJDhvhHwBOAgAAAA==.Hopeudie:BAAALgAECgUJBgABLgAFFAYJCwAJAIYiAA==.Horata:BAAALgAECgMJAwAAAA==.Hormuz:BAAALgADCgcJCwAAAA==.Hotelcali:BAAALgADCgkJCQAAAA==.',
Hu='Huckcold:BAAALgAECgcJDwAAAA==.Hugehands:BAAALgAECgUJBwAAAA==.Hughass:BAAALgADCgEJAQAAAA==.Hurano:BAAALgAECgYJCAAAAA==.',
Hy='Hyperious:BAAALgAECggJCAAAAA==.',
['Hâ']='Hârley:BAABLgAECn87AAIMAAkJ+BvPFwCGAgAMAAkJ+BvPFwCGAgAAAA==.',
['Hí']='Híram:BAABLgAECn8mAAIEAAgJahRddwB+AQAEAAgJahRddwB+AQAAAA==.',
Id='Idyllwild:BAAALgAECgEJBAAAAA==.',
Ih='Ihsan:BAABLgAECn82AAIEAAkJExZKOgAYAgAEAAkJExZKOgAYAgAAAA==.',
Il='Ilharess:BAACLgAFFH8NAAIBAAQJDg5CYwAjAQABAAQJDg5CYwAjAQAuAAQKfyoAAgEACQkXFAlwAJcBAAEACQkXFAlwAJcBAAAA.',
In='Inko:BAAALgADCgYJCQABLgAFFAYJHwAOALUkAA==.Inkpot:BAAALgAECgEJAQABLgAECggJNgAMABYlAA==.Inkstain:BAAALgAECgYJDAABLgAECggJNgAMABYlAA==.Inkwell:BAABLgAECn82AAIMAAgJFiX4CAAAAwAMAAgJFiX4CAAAAwAAAA==.',
Is='Iskasta:BAAALgADCgQJBAAAAA==.Isobell:BAAALgAECgcJDQAAAA==.',
Ja='Jaardrius:BAABLgAECn9BAAMVAAkJVyIOBgBFAwAVAAkJVyIOBgBFAwAIAAMJjgu3XgCVAAAAAA==.Jackransom:BAAALgADCgkJDgAAAA==.Jakobo:BAAALgAECgcJCwAAAA==.Jal:BAAALgADCgMJAwAAAA==.Jalapenoheat:BAAALgAECgQJAwAAAA==.Jandreyn:BAAALgADCgUJAQAAAA==.Jaskar:BAAALgAECgEJAQAAAA==.Javanna:BAAALgAECgUJCAAAAA==.',
Jd='Jdiddy:BAAALgAECgcJAQAAAA==.',
Je='Jelly:BAAALgADCgIJAgABLgAFFAgJIAAMALscAA==.',
Ji='Jimbostein:BAAALgADCgEJAQAAAA==.Jinnie:BAAALgADCgMJBgAAAA==.',
Jj='Jjb:BAAALgAECgcJCQAAAA==.',
Ju='Junebuge:BAAALgAECgQJBAAAAA==.Juniordh:BAAALgAFFAIJAgABLgAFFAUJEwAVAMogAA==.Junknthtrunk:BAAALgAECgMJAwAAAA==.',
Ka='Kaelana:BAAALgADCgEJAQAAAA==.Kalculated:BAAALgAECgEJAQAAAA==.Kamahl:BAAALgAFFAEJAQAAAA==.Karl:BAAALgADCgUJBQAAAA==.Katôs:BAAALgADCgkJCQAAAA==.',
Kd='Kda:BAAALgAECgYJBgABLgAECgcJFQAbAIYjAA==.',
Ke='Keanew:BAABLgAECn8xAAQPAAkJNh5rCgC5AQAPAAgJ1hRrCgC5AQAXAAkJqRxzGgCoAQAYAAMJNgP28wBWAAAAAA==.Kebap:BAAALgAECgYJBgAAAA==.Keigaa:BAABLgAECn8qAAMdAAcJTSCkIAAWAgAdAAYJcCGkIAAWAgAEAAYJNRRDqQAoAQAAAA==.Keilien:BAAALgAECgUJBwAAAA==.Kenry:BAAALgAECgUJEwAAAA==.Keonna:BAAALgAECgUJCwAAAA==.Keppra:BAABLgAECn8WAAIQAAYJfgVnaACrAAAQAAYJfgVnaACrAAAAAA==.Kerlin:BAACLgAFFH8PAAIMAAMJ4AF7UwByAAAMAAMJ4AF7UwByAAAuAAQKfxsAAwwACQk9DmRYAEkBAAwACAlSC2RYAEkBAAsAAQnkAnOIACcAAAAA.Keyaira:BAAALgADCgYJBwAAAA==.Keybash:BAABLgAECn8UAAMNAAYJmgVyHwB1AAAaAAYJewVWzAC5AAANAAMJagNyHwB1AAAAAA==.Keíga:BAAALgAECgMJBAAAAA==.',
Kh='Kharne:BAAALgAFFAEJAgABLgAFFAQJCgAhAM4iAA==.Khurst:BAAALgAECgcJDwAAAA==.',
Ki='Kilmithius:BAAALgAECgYJEgAAAA==.Kimchi:BAAALgAECgQJBAABLgAFFAgJIAAMALscAA==.Kimmex:BAAALgADCgcJAgAAAA==.Kinoxo:BAACLgAFFH8rAAMKAAcJdh1uCwCpAQAKAAUJUiVuCwCpAQAcAAYJUhP4FQAqAQAuAAQKfx0AAwoACAmRIeMaAHUCAAoACAnzHeMaAHUCABwABAm6HakgAOgAAAAA.Kinoxoxo:BAAALgAECgQJBwAAAA==.Kinozo:BAAALgAFFAIJAgAAAA==.Kirianis:BAABLgAECn8vAAIEAAkJDBjWNgAkAgAEAAkJDBjWNgAkAgAAAA==.Kishuko:BAAALgADCgEJAQAAAA==.',
Kl='Klesha:BAAALgADCgMJAwAAAA==.Klevens:BAAALgAECgkJBgAAAA==.',
Ko='Kongfuux:BAAALgAECgQJBAAAAA==.Kossuth:BAAALgAECgcJCAAAAA==.',
Kr='Kragge:BAAALgAECgcJCQAAAA==.Krampusnacht:BAAALgAECgYJCQAAAA==.Krissycat:BAAALgAECgUJBQAAAA==.Kryven:BAAALgADCgkJEQAAAA==.',
Ku='Kumma:BAAALgADCgEJAQAAAA==.Kushaladaora:BAAALgAECgQJCQAAAA==.',
Ky='Kybrine:BAAALgAECgYJBwAAAA==.Kynlas:BAAALgAECgQJDQAAAA==.Kyratinx:BAAALgAECgEJAwAAAA==.',
['Kì']='Kìtty:BAAALgAFFAIJAgAAAA==.',
La='Lacachuda:BAAALgADCgIJAwAAAA==.Lacear:BAAALgADCgcJBwABLgAFFAYJCwAJAIYiAA==.Langris:BAAALgAECgcJCAAAAA==.Larious:BAABLgAECn9OAAIEAAkJSx7nGACsAgAEAAkJSx7nGACsAgAAAA==.',
Le='Led:BAAALgAECggJEAAAAA==.Ledikens:BAAALgAECggJDgAAAA==.Legless:BAAALgAECgEJAQABLgAECgkJEQAUAAAAAA==.Legnase:BAABLgAECn8wAAMDAAkJ6R4OCAD0AgADAAkJ1h4OCAD0AgACAAIJRRbiXABjAAABLgAECgkJPAAQADkiAA==.Legolaslawl:BAAALgAECgQJBAABLgAFFAMJBgAKAFoUAA==.Leht:BAABLgAECn88AAMLAAkJ2RFJHADjAQALAAkJ2RFJHADjAQAMAAEJawGQ7AAVAAAAAA==.Lessgibbon:BAABLgAECn8XAAIKAAcJPh/WGgB1AgAKAAcJPh/WGgB1AgAAAA==.Lestare:BAAALgADCgYJBgAAAA==.Leviiathan:BAAALgAECgcJAwAAAA==.Lexishexis:BAAALgADCgYJBgAAAA==.',
Li='Libáh:BAAALgAECgEJAQABLgAECgkJIgAZAFkUAA==.Lichma:BAAALgAECgIJAgAAAA==.Lighte:BAAALgADCgYJBgAAAA==.Lightspin:BAAALgAECgYJCgAAAA==.Lilgaspump:BAAALgADCgIJAQABLgAECgUJFAAHAJYQAA==.Lili:BAAALgADCgcJAgAAAA==.Lilnasty:BAABLgAECn8jAAIBAAkJSg6IaACpAQABAAkJSg6IaACpAQAAAA==.Lilnickel:BAAALgADCggJCAAAAA==.Lionroar:BAAALgAECgEJAQAAAA==.Livesey:BAAALgAECgQJBgAAAA==.',
Lo='Locknut:BAAALgADCgkJFwABLgAECggJFAAIAEUSAA==.Lockpie:BAAALgAECgUJBQAAAA==.Lockresh:BAAALgADCgcJCAABLgAECgcJJwAKAH0SAA==.Lokahn:BAABLgAECn8WAAIIAAYJ2RmGIwC6AQAIAAYJ2RmGIwC6AQAAAA==.Longhorndemn:BAAALgADCgQJBAABLgAFFAMJBgAKAFoUAA==.Longhorndk:BAAALgAECgIJAQABLgAFFAMJBgAKAFoUAA==.Longhornmage:BAAALgAECgMJAwABLgAFFAMJBgAKAFoUAA==.Longhornpibe:BAACLgAFFH8GAAIKAAMJWhTuOQDFAAAKAAMJWhTuOQDFAAAuAAQKf0UAAwoACAnuGWkgAOwBAAoACAnuGWkgAOwBABwAAwlMDqBPAJAAAAAA.Longshañk:BAAALgAECgIJAgAAAA==.Loudog:BAABLgAECn8zAAMRAAkJ3xNdWQC4AQARAAkJohJdWQC4AQAhAAYJ8hB2LgDpAAAAAA==.',
Lu='Lupardus:BAAALgAECgEJAQAAAA==.Luto:BAAALgAECgkJDgAAAA==.Luuko:BAAALgAECgQJBAAAAA==.',
Ly='Lynxie:BAABLgAECn8gAAIGAAgJWA8gMwBNAQAGAAgJWA8gMwBNAQAAAA==.',
['Lö']='Lökkïï:BAAALgADCgUJBQAAAA==.Lörelei:BAAALgAECgQJBAAAAA==.',
Ma='Mackerel:BAABLgAECn8YAAIHAAcJliBoEACXAgAHAAcJliBoEACXAgABLgAFFAgJJQAOAJojAA==.Madii:BAAALgAECgEJAQAAAA==.Mageresh:BAABLgAECn8VAAIBAAYJwQiS1gDmAAABAAYJwQiS1gDmAAABLgAECgcJJwAKAH0SAA==.Majinmu:BAAALgAECgUJCwAAAA==.Malus:BAABLgAECn8ZAAIaAAgJLQ68YQClAQAaAAgJLQ68YQClAQAAAA==.Manders:BAAALgADCgcJAgAAAA==.Mangela:BAAALgAECgIJAwAAAA==.Mank:BAAALgAECgMJAwAAAA==.Maps:BAAALgAECgYJDQAAAA==.Masher:BAAALgAECgQJBAAAAA==.Mattydruid:BAAALgAFFAEJAQAAAA==.Maverage:BAAALgADCgMJBQAAAA==.Mavramune:BAACLgAFFH8KAAITAAUJ2QhVWwDoAAATAAUJ2QhVWwDoAAAuAAQKfyYAAxMACAlDF2ZlAHYBABMABwniGWZlAHYBAAUACAmzDMcgAKgAAAAA.Mayge:BAABLgAECn8rAAIBAAkJKxuHMgBNAgABAAkJKxuHMgBNAgAAAA==.Mañali:BAAALgADCgYJBgAAAA==.',
Mc='Mcfürry:BAABLgAECn8YAAIMAAcJyBvsMgDQAQAMAAcJyBvsMgDQAQAAAA==.',
Me='Mebedir:BAAALgAECgMJBQAAAA==.Meekal:BAAALgADCgEJAQAAAA==.Meggatron:BAAALgAECggJDgABLgAECgkJKQAjAPIeAA==.Melithia:BAAALgAECgcJEQAAAA==.Mels:BAAALgAECgQJBgAAAA==.Mendinna:BAABLgAECn82AAIXAAgJdBPZGwCbAQAXAAgJdBPZGwCbAQAAAA==.Mephidrossa:BAAALgAECggJCAABLgAFFAMJBQAIALQRAA==.Mercs:BAAALgADCgQJBQABLgAECgUJFAAHAJYQAA==.Methir:BAAALgAECgQJBAABLgAFFAQJBQAUAAAAAA==.',
Mi='Miffed:BAAALgAFFAIJAgABLgAFFAcJHwAiAAoQAA==.Mildew:BAAALgADCgYJBgAAAA==.Mincksie:BAAALgAECggJEwAAAA==.Mininetty:BAAALgADCgcJBwABLgAECgYJCAAUAAAAAA==.Mirage:BAABLgAECn8VAAIbAAcJhiMPFwBSAgAbAAcJhiMPFwBSAgAAAA==.Misfired:BAAALgADCgIJAgAAAA==.Mistbot:BAACLgAFFH8FAAMIAAMJtBFmMAB9AAAIAAIJ1hZmMAB9AAAVAAIJxwn8SwBsAAAuAAQKfz0ABAgACQlkITgGAOcCAAgACQlkITgGAOcCAAcAAwnCHyg5ABYBABUAAQmyIgaXAGMAAAAA.',
Mo='Montebrew:BAAALgAECgYJBgAAAA==.Monysha:BAAALgAECgYJDQAAAA==.Mooferrigno:BAAALgAFFAMJBAAAAA==.Mooky:BAABLgAECn8oAAILAAkJ9Q/DIwCpAQALAAkJ9Q/DIwCpAQAAAA==.Moovitz:BAAALgADCgYJDwAAAA==.Mopeia:BAABLgAECn8iAAMMAAYJghdyPwCSAQAMAAYJghdyPwCSAQAfAAUJOQ4OPQCuAAABLgAECgYJEwAUAAAAAA==.Mord:BAAALgAECgUJDAAAAA==.Mork:BAAALgADCgMJAwABLgAECgcJLgARAD4iAA==.Mortemore:BAACLgAFFH8TAAIYAAYJwxXJMgBTAQAYAAYJwxXJMgBTAQAuAAQKfycAAhgACQkSIGIbAG4CABgACQkSIGIbAG4CAAAA.Mortlee:BAAALgAECgEJAQABLgAFFAYJEwAYAMMVAA==.Motet:BAAALgAECgYJCwAAAA==.Motoxman:BAAALgADCgEJAQAAAA==.',
Mu='Muikkie:BAAALgAECgEJAgAAAA==.Mulro:BAAALgADCgMJAwAAAA==.Muncher:BAAALgAECgkJEgAAAA==.',
My='Mymage:BAAALgADCgEJAQAAAA==.Mynoghra:BAAALgAECgYJEgAAAA==.Mynxx:BAAALgAECgcJCQAAAA==.Mystrax:BAAALgADCgIJAgAAAA==.',
Na='Nadoral:BAAALgADCgYJCwAAAA==.Nalka:BAAALgAECgMJAwAAAA==.Naproxen:BAABLgAECn9CAAIgAAkJySD8AgAOAwAgAAkJySD8AgAOAwAAAA==.Naraku:BAACLgAFFH8cAAQaAAYJQxlNJwChAQAaAAYJghhNJwChAQAZAAEJFhKxFABVAAANAAEJ6RT3IABPAAAuAAQKfzMAAxoACAnhIzgVAKUCABoACAlcIzgVAKUCABkABglbHugNAOcBAAAA.Narberal:BAAALgADCgEJAQAAAA==.Nastager:BAAALgADCgcJBwAAAA==.Naxx:BAAALgADCgIJAgAAAA==.Nazgül:BAAALgADCgMJAgAAAA==.',
Ne='Necratog:BAAALgADCgEJAQAAAA==.Necroseeker:BAAALgAECgYJCwAAAA==.Negativity:BAAALgAFFAIJAgAAAA==.Nerkidz:BAAALgAECgEJAQAAAA==.Nes:BAAALgAECggJCwABLgAECgkJJQADAC0aAA==.Nettie:BAAALgAECgUJBQABLgAECgYJCAAUAAAAAA==.Netty:BAAALgAECgYJCAAAAA==.',
Ni='Nightshaulea:BAAALgAECgcJCwAAAA==.Niklaus:BAACLgAFFH8KAAIEAAQJcwvAYQDmAAAEAAQJcwvAYQDmAAAuAAQKfx4AAgQABwl2FlVoAK8BAAQABwl2FlVoAK8BAAAA.Nilisha:BAAALgADCgIJAgAAAA==.Nimi:BAAALgAECgEJAQAAAA==.Nirala:BAAALgADCgkJCQAAAA==.',
No='Nocticula:BAAALgADCgEJAQAAAA==.Nosferatmoo:BAAALgADCgkJCQABLgADCgkJEwAUAAAAAA==.',
Nu='Nusy:BAAALgAECgQJBAAAAA==.',
Ny='Nymeera:BAABLgAECn9BAAMfAAkJDgiHLgDvAAAfAAkJDgiHLgDvAAAeAAIJMgOtSgBAAAAAAA==.Nymphetamine:BAABLgAECn9DAAMCAAkJLxqKDwBtAgACAAkJLxqKDwBtAgADAAQJ/AaeVwCfAAAAAA==.Nyxarya:BAAALgADCgcJBwAAAA==.',
Nz='Nzoth:BAABLgAECn8gAAIGAAkJGRAMKQCHAQAGAAkJGRAMKQCHAQAAAA==.',
Ob='Obnixilis:BAABLgAECn8WAAIRAAYJHxngbgCrAQARAAYJHxngbgCrAQABLgAECggJFQAHAO8aAA==.',
Od='Odessa:BAAALgAECgEJAQAAAA==.',
Ok='Okin:BAAALgAECgMJAwAAAA==.',
Om='Omadruid:BAAALgADCgYJBgAAAA==.Omapriest:BAAALgADCgUJBQAAAA==.Omashamwow:BAAALgAECgQJBQAAAA==.Omen:BAAALgAECgMJAwAAAA==.Omorc:BAABLgAECn82AAIFAAkJExj1BQA5AgAFAAkJExj1BQA5AgAAAA==.',
On='Oneyeli:BAAALgADCgYJBgAAAA==.Onikuma:BAAALgAECgQJBAAAAA==.Oniony:BAAALgADCgYJCwAAAA==.Onli:BAAALgAECgUJCAAAAA==.Onos:BAAALgAECgMJAwAAAA==.',
Or='Ordlok:BAAALgADCgcJCQAAAA==.Oresh:BAABLgAECn8nAAIKAAcJfRLiOQBfAQAKAAcJfRLiOQBfAQAAAA==.Orla:BAAALgAECgEJAQABLgAECggJHQAYAEocAA==.Orlaith:BAAALgAECgcJCgABLgAECggJHQAYAEocAA==.',
Ou='Ouinur:BAAALgAECgEJAQABLgAECgkJHwAHAC4ZAA==.',
Ow='Owenwilson:BAAALgAECgUJBwAAAA==.Owful:BAAALgAECgcJDQAAAA==.',
Pa='Pandaloca:BAAALgAECgUJBQAAAA==.Pandaloco:BAAALgADCgcJBwAAAA==.Pandalôc:BAAALgAECgIJAgAAAA==.Pandoe:BAABLgAECn8VAAQfAAgJbxeZEwC4AQAfAAYJaB+ZEwC4AQALAAgJrA6nMACDAQAMAAEJngeR3AAmAAAAAA==.Papaya:BAACLgAFFH8gAAIMAAgJuxyaAQD+AQAMAAgJuxyaAQD+AQAuAAQKfyIAAwwACQnZIcMGAB8DAAwACQnZIcMGAB8DAAsABwliIZYjAOABAAAA.Pawpawpiddle:BAAALgAECgYJBgAAAA==.',
Pe='Penelopea:BAABLgAECn8pAAIBAAkJeRWDQAAZAgABAAkJeRWDQAAZAgAAAA==.Perlen:BAAALgADCgYJBgAAAA==.Perun:BAAALgAECgcJEAAAAA==.',
Ph='Phaith:BAAALgADCgUJCwABLgAECgUJBQAUAAAAAA==.Phaithfully:BAAALgAECgUJBQAAAA==.Phaithfulnes:BAAALgAECgUJBQABLgAECgUJBQAUAAAAAA==.Phenomenal:BAAALgAECgEJAQABLgAECgkJNgAQAJYfAA==.',
Pl='Plaguedealer:BAAALgADCgUJBQAAAA==.',
Pn='Pneumonya:BAAALgAECgcJBwAAAA==.',
Po='Porteagarder:BAABLgAECn8yAAMJAAkJGw6gUwBiAQAJAAgJfgugUwBiAQAQAAIJSQOquwAfAAAAAA==.Potatodruid:BAAALgAECgQJDQAAAA==.Power:BAAALgADCgYJBgAAAA==.',
Pr='Preparedpie:BAABLgAECn8SAAIYAAgJcxneNQDsAQAYAAgJcxneNQDsAQAAAA==.Preront:BAACLgAFFH8+AAMjAAkJzCUNAABwAwAjAAkJyyUNAABwAwAQAAgJBxv1CQABAgAuAAQKfyIABCMACQngJikAAOYDACMACQngJikAAOYDABAAAwksJq4+AFABAAkAAwkVG9R7AOgAAAAA.Priestbrume:BAAALgAECgYJDAAAAA==.Pringler:BAAALgAECgYJCAABLgAFFAgJJQAOAJojAA==.Producktive:BAABLgAECn8bAAIiAAgJMxXCEAC6AQAiAAgJMxXCEAC6AQAAAA==.Prometeus:BAAALgAECgUJBQAAAA==.Pros:BAABLgAECn8iAAIZAAkJWRRZDQDvAQAZAAkJWRRZDQDvAQAAAA==.Pruulia:BAAALgADCgkJDAABLgAECgkJPAALANkRAA==.Príestly:BAAALgAECgYJCwAAAA==.',
Ps='Psydúck:BAAALgADCgcJDQAAAA==.',
Pu='Puffdamagic:BAABLgAECn8aAAImAAgJ1husGAARAgAmAAgJ1husGAARAgABLgAFFAYJEwAYAMMVAA==.Puffthemagic:BAABLgAECn8WAAIlAAkJoQx2CQCOAQAlAAkJoQx2CQCOAQAAAA==.Purentity:BAAALgAECgYJCwAAAA==.',
Py='Pyatt:BAABLgAECn8uAAINAAkJbx07BABdAgANAAkJbx07BABdAgAAAA==.',
['Pú']='Púff:BAAALgAECgQJBwAAAA==.',
Qu='Quack:BAAALgAECggJEQAAAA==.Quackadin:BAAALgADCgYJCwABLgAECggJEQAUAAAAAA==.Quackula:BAAALgAECgcJBgAAAA==.Quilae:BAABLgAECn8VAAICAAcJVApKNwAeAQACAAcJVApKNwAeAQABLgAECgkJMgAJABsOAA==.Quiny:BAAALgADCgMJAQAAAA==.',
Ra='Raerlynn:BAEALgADCgMJAwAAAA==.Ragnix:BAAALgAECgEJAQAAAA==.Randivh:BAAALgAECgIJAgAAAA==.Rassputin:BAABLgAECn8pAAIBAAkJnhdJOwAqAgABAAkJnhdJOwAqAgAAAA==.Raulioo:BAAALgAECgUJCQAAAA==.Ravnmoon:BAAALgAECgUJBQAAAA==.Raye:BAAALgADCgYJBgAAAA==.Razzleyi:BAAALgAECgQJBAAAAA==.',
Re='Realmack:BAAALgAECggJDAABLgAFFAYJCwAJAIYiAA==.Rebuke:BAAALgAECgYJBgAAAA==.Reclaimblade:BAAALgADCgUJBQAAAA==.Reclaimdrunk:BAAALgAECgIJAgAAAA==.Reclaimergun:BAAALgADCgEJAQAAAA==.Reclaimholy:BAAALgADCgUJBQAAAA==.Reclaimsage:BAAALgADCgYJBQAAAA==.Reigwend:BAAALgADCggJDwAAAA==.Reisharra:BAAALgAECgUJCgAAAA==.Relimas:BAAALgADCgcJEAAAAA==.Remish:BAAALgAECgUJBQAAAA==.Rendezvous:BAAALgAECgEJBwAAAA==.Renkà:BAABLgAFFH8LAAMQAAQJyAyBKgDnAAAQAAQJyAyBKgDnAAAJAAQJ5QGMVwCbAAAAAA==.Requestor:BAAALgAECgUJCgABLgAECggJFQAHAO8aAA==.Resmondo:BAAALgADCgQJBAAAAA==.Ret:BAACLgAFFH8UAAIEAAUJlQwsVQABAQAEAAUJlQwsVQABAQAuAAQKfysAAgQACAkhG4suAGkCAAQACAkhG4suAGkCAAAA.Revaerlous:BAABLgAECn8uAAIRAAkJix0oLACIAgARAAkJix0oLACIAgAAAA==.',
Rh='Rheas:BAAALgADCgYJDQABLgAECggJEwAUAAAAAA==.Rhei:BAABLgAECn8RAAIYAAgJIBkbLgBEAgAYAAgJIBkbLgBEAgAAAA==.',
Ri='Ribeye:BAACLgAFFH8fAAIiAAcJChBbAwBxAQAiAAcJChBbAwBxAQAuAAQKfykAAiIACQlPFogSAJ0BACIACQlPFogSAJ0BAAAA.',
Ro='Roereker:BAABLgAECn9BAAIEAAkJcRpLJwBlAgAEAAkJcRpLJwBlAgAAAA==.Roguesamurai:BAAALgADCgEJAQAAAA==.Rohhenge:BAAALgAECgQJBAAAAA==.Roketraccoon:BAAALgAECgQJDwAAAA==.Romoxodus:BAAALgADCgUJCQAAAA==.Rongbip:BAABLgAECn8gAAIgAAkJ2hoCDgBJAgAgAAkJ2hoCDgBJAgAAAA==.Roshamandes:BAABLgAECn8nAAIPAAkJzCB5AgDUAgAPAAkJzCB5AgDUAgAAAA==.Rotigus:BAAALgADCgUJBQAAAA==.',
Ru='Rubadubdubz:BAAALgADCgMJAwAAAA==.Runep:BAABLgAECn8rAAIEAAkJbyCXFwC0AgAEAAkJbyCXFwC0AgAAAA==.',
Ry='Rysera:BAAALgAECgYJBgAAAA==.Ryusei:BAAALgAECgcJBwABLgAECgkJPAAQADkiAA==.Ryù:BAAALgADCgUJBQAAAA==.',
['Rè']='Rèi:BAAALgAECgIJCgABLgAECggJJgATAF8iAA==.',
['Ré']='Réstofarian:BAACLgAFFH8UAAIMAAQJIB7aIQBEAQAMAAQJIB7aIQBEAQAuAAQKfy0AAwwACQm0I1sCAHYDAAwACQm0I1sCAHYDAAsAAgkoGexmAIYAAAAA.',
Sa='Sabbier:BAAALgADCgcJBwAAAA==.Sacredchikín:BAABLgAECn8eAAIaAAgJPxx9LwAaAgAaAAgJPxx9LwAaAgAAAA==.Saiki:BAAALgAECgUJDQAAAA==.Samuel:BAAALgAECgQJBwAAAA==.Sanataanna:BAAALgADCgUJCwABLgAECggJEwAUAAAAAA==.Sandvichus:BAABLgAECn8nAAILAAkJmyKtBQD8AgALAAkJmyKtBQD8AgAAAA==.Sanitarìum:BAAALgAECgQJCAAAAA==.Sardine:BAAALgAECgcJDgABLgAFFAgJIAAMALscAA==.Sasukie:BAAALgAECgEJBQAAAA==.Savagesmonk:BAAALgAECgUJBgAAAA==.Saxa:BAACLgAFFH8QAAIXAAQJ5SSlBQCsAQAXAAQJ5SSlBQCsAQAuAAQKfzEAAhcACQnnJGcFAOkCABcACQnnJGcFAOkCAAAA.',
Sc='Scratchnsnif:BAAALgADCgUJBQAAAA==.',
Se='Seers:BAAALgAECgMJAwABLgAFFAYJCwAJAIYiAA==.Sefik:BAAALgAECgYJEQAAAA==.Selaana:BAABLgAECn8YAAIQAAYJPh9nIgD8AQAQAAYJPh9nIgD8AQAAAA==.Serkis:BAAALgAECgcJBQAAAA==.Seyekobrew:BAAALgADCgIJAgAAAA==.Seyekosis:BAABLgAECn8bAAIYAAgJMhwkIwBCAgAYAAgJMhwkIwBCAgAAAA==.',
Sg='Sgathaich:BAEBLgAECn8rAAIdAAgJVBoGHAAiAgAdAAgJVBoGHAAiAgABLgAECgkJGwAMAGIZAA==.',
Sh='Shaan:BAAALgADCgMJAwAAAA==.Shadtae:BAAALgAECgYJCgABLgAECgkJLAAJAKgXAA==.Shaio:BAABLgAECn8VAAIIAAYJ3Q9hNgBGAQAIAAYJ3Q9hNgBGAQAAAA==.Shallistiah:BAAALgAECgQJBAABLgAECgkJQQAVAFciAA==.Shamadin:BAAALgADCgkJCQAAAA==.Shambrume:BAAALgAECgYJDgAAAA==.Shambulence:BAACLgAFFH8QAAIJAAQJew4lQgDZAAAJAAQJew4lQgDZAAAuAAQKfxoAAwkACQm/FcMhAEICAAkACQm/FcMhAEICACMAAwnREXsnALYAAAAA.Shammlock:BAACLgAFFH8VAAQNAAYJgBBhCADwAAANAAUJRRNhCADwAAAaAAMJYxH3egDKAAAZAAIJxwJPKQA/AAAuAAQKfygABA0ACQmCHuECAIMCAA0ACAkTH+ECAIMCABoACQnDGS0qAGcCABkABQl6EFskADgBAAAA.Shampriest:BAAALgAECggJCAAAAA==.Shamuel:BAACLgAFFH8IAAIgAAYJPBLbCACCAQAgAAYJPBLbCACCAQAuAAQKfxcAAiAACQlqEzwSABgCACAACQlqEzwSABgCAAAA.Shaylis:BAABLgAECn8UAAITAAcJxxlaQwDVAQATAAcJxxlaQwDVAQABLgAFFAQJCwAQAMgMAA==.Shazamm:BAAALgADCgEJAQAAAA==.Sheji:BAAALgADCgkJHAAAAA==.Shiggy:BAAALgAECgUJCgABLgAFFAQJBgAKAMoWAA==.Shobadon:BAAALgAECggJEAAAAA==.Shobarella:BAAALgAECgkJCQAAAA==.Shole:BAABLgAECn81AAMQAAkJGh7eEwBLAgAQAAkJGh7eEwBLAgAJAAcJFBwmKwALAgAAAA==.Shpoople:BAAALgAECgMJBAABLgAECgcJCQAUAAAAAA==.Shulanii:BAAALgAECgMJBQAAAA==.',
Si='Siatral:BAAALgAFFAIJAgABLgAFFAUJEwAVAMogAA==.Siggopotomus:BAAALgADCgUJBQABLgAECggJEwAUAAAAAA==.Sigvalden:BAAALgAECggJEwAAAA==.Sigvolden:BAAALgAECgcJAgABLgAECggJEwAUAAAAAA==.Silchar:BAAALgAECgMJBgAAAA==.Silicon:BAABLgAECn8hAAIBAAkJjhJKZQCxAQABAAkJjhJKZQCxAQAAAA==.Simp:BAAALgAECgEJAQABLgAECgcJAQAUAAAAAA==.Sinfulangel:BAABLgAECn85AAMRAAkJ/RzUJwBhAgARAAkJ+BvUJwBhAgAhAAkJbhRbEQD0AQAAAA==.Siona:BAABLgAECn9IAAITAAkJZg2NTwCwAQATAAkJZg2NTwCwAQAAAA==.',
Sk='Skadie:BAABLgAECn8qAAMTAAkJNBW0JgAfAgATAAkJNBW0JgAfAgAFAAEJ+QOPQgAkAAAAAA==.Skialin:BAAALgAECgEJAQAAAA==.Skiye:BAAALgADCggJDgAAAA==.Skwii:BAAALgAFFAEJAQABLgAFFAYJCwAJAIYiAA==.Skwill:BAAALgAECgEJAQABLgAFFAYJCwAJAIYiAA==.Skwip:BAABLgAFFH8LAAIJAAYJhiJ4BgBVAgAJAAYJhiJ4BgBVAgAAAA==.Skwop:BAAALgAECgEJAgABLgAFFAYJCwAJAIYiAA==.Skyelar:BAAALgAECgcJBgAAAA==.Skyler:BAABLgAECn8UAAInAAcJER39AgAzAgAnAAcJER39AgAzAgAAAA==.',
Sl='Slackness:BAAALgAECgMJCAAAAA==.Slavalous:BAAALgAECgcJDAAAAA==.',
Sn='Snakeshifter:BAAALgADCgUJBQAAAA==.Snakesoul:BAAALgAECgMJBAAAAA==.Snivels:BAABLgAECn8hAAIfAAkJbREEKwACAQAfAAkJbREEKwACAQAAAA==.Snnorri:BAAALgADCggJFgABLgAECgkJQQAVAFciAA==.',
So='Sodtaoe:BAAALgADCgcJDQAAAA==.Solsilvesti:BAAALgADCgMJAwAAAA==.Souly:BAAALgAECgcJBwAAAA==.',
Sp='Sparrkle:BAABLgAECn8uAAIZAAkJ1w1lDQBkAQAZAAkJ1w1lDQBkAQAAAA==.Spin:BAAALgADCgMJAwAAAA==.Spinecrawler:BAAALgAFFAMJBAAAAA==.Spinjitzu:BAAALgAECgQJCwAAAA==.Spiritshift:BAAALgAECgEJAQAAAA==.Spyro:BAAALgAECgQJEQAAAA==.',
Sq='Squadw:BAACLgAFFH8hAAIXAAcJoxrvAgAOAgAXAAcJoxrvAgAOAgAuAAQKf0YAAhcACQkCJTkCAHMDABcACQkCJTkCAHMDAAAA.',
Ss='Sski:BAAALgADCgEJAQAAAA==.',
St='Starblast:BAAALgAECgYJEwABLgAECgYJBwAUAAAAAA==.Starrskrream:BAAALgAECgQJBgAAAA==.Staryknight:BAAALgAECgEJAQAAAA==.Steamworks:BAAALgADCgcJBwAAAA==.Steelrat:BAAALgADCgcJAgAAAA==.Stellanova:BAAALgADCgQJBAAAAA==.Stiick:BAABLgAECn82AAIiAAkJDBr6CQAqAgAiAAkJDBr6CQAqAgAAAA==.Stormhide:BAAALgADCgEJAgAAAA==.Streakycat:BAEALgAECgEJAQAAAA==.Stupidgnome:BAAALgAECgkJCgAAAA==.Stìmpak:BAAALgAECgMJBQABLgAECgcJCAAUAAAAAA==.',
Su='Subsizzle:BAAALgAECgMJAwABLgAECgcJEgAUAAAAAA==.Subzerow:BAAALgADCgYJBgAAAA==.Sudsy:BAAALgAECggJCgAAAA==.Sujin:BAAALgAECgMJAwAAAA==.Sunarra:BAABLgAECn8dAAIYAAgJShwTMgD7AQAYAAgJShwTMgD7AQAAAA==.Sunsmite:BAABLgAECn8dAAIEAAcJrha5bQCiAQAEAAcJrha5bQCiAQAAAA==.Supadupaman:BAAALgAECgkJBgAAAA==.Suramar:BAABLgAECn8YAAIOAAgJAhUfGQBxAQAOAAgJAhUfGQBxAQAAAA==.',
Sw='Sweetbippy:BAABLgAECn88AAIBAAkJjANSqwAnAQABAAkJjANSqwAnAQAAAA==.Swifthealss:BAABLgAECn8fAAQMAAkJiweDaAD5AAAMAAgJjQaDaAD5AAAfAAUJ+QsUOADCAAALAAUJ3grXWgClAAAAAA==.Swirls:BAAALgAECgEJAgAAAA==.',
Sy='Sygvalden:BAAALgAECgYJDAABLgAECggJEwAUAAAAAA==.Sylunae:BAAALgAECgYJEAABLgAECgkJMgAJABsOAA==.Syluné:BAABLgAECn8sAAIMAAkJvwzKQQCIAQAMAAkJvwzKQQCIAQABLgAECgkJMgAJABsOAA==.Syläs:BAAALgAECgYJEwAAAA==.Syndrassil:BAABLgAECn83AAIBAAkJ7w4VWgDNAQABAAkJ7w4VWgDNAQAAAA==.',
['Sù']='Sùccubus:BAAALgADCgQJBAAAAA==.',
['Sý']='Sýd:BAAALgAECgMJAwAAAA==.',
Ta='Tacodog:BAAALgAECgUJCgABLgAFFAIJBgAEABQdAA==.Tacomonk:BAAALgAECggJCgAAAA==.Tacopally:BAAALgAECgcJCwABLgAECggJCgAUAAAAAA==.Tacozpriest:BAAALgAECgYJBgABLgAECggJCgAUAAAAAA==.Taelight:BAAALgADCggJDgABLgAECgkJLAAJAKgXAA==.Taelyx:BAABLgAECn8sAAMJAAkJqBeXOADKAQAJAAkJqBeXOADKAQAQAAIJ3gkQfgBOAAAAAA==.Taepain:BAAALgAECgIJAgABLgAECgkJLAAJAKgXAA==.Taicheeze:BAABLgAECn8fAAIHAAkJLhm8DwA/AgAHAAkJLhm8DwA/AgAAAA==.Tambot:BAAALgAECgQJDQAAAA==.Tanialeal:BAAALgAECgQJBAABLgAECggJKAARABsbAA==.Tariced:BAAALgAECgUJCQAAAA==.Tarvaron:BAAALgADCgEJAQAAAA==.Taytra:BAAALgAECgQJBAABLgAECgkJPAABAIwDAA==.Tazmina:BAACLgAFFH8OAAIXAAMJ9R9bEQAXAQAXAAMJ9R9bEQAXAQAuAAQKfzkAAhcACQnqIl4DAB8DABcACQnqIl4DAB8DAAAA.',
Te='Teal:BAAALgADCgYJCgAAAA==.Teenieweenie:BAAALgAECgEJAQAAAA==.Tehssa:BAAALgAECgUJBgABLgAECgkJPAAQAEseAA==.Tenzen:BAAALgAECgYJBgAAAA==.Tessa:BAABLgAECn88AAIQAAkJSx7JCwClAgAQAAkJSx7JCwClAgAAAA==.Texasfight:BAAALgAECgEJAQABLgAFFAMJBgAKAFoUAA==.Teyo:BAAALgAECgcJEQAAAA==.',
Th='Thedoctorwho:BAABLgAECn8WAAIEAAkJpw9GVgDHAQAEAAkJpw9GVgDHAQAAAA==.Theholytaz:BAABLgAECn8XAAIEAAgJDBZkQQAhAgAEAAgJDBZkQQAhAgAAAA==.Theirel:BAAALgAECgUJCQAAAA==.Thunderr:BAAALgAECgcJCAAAAA==.Thörn:BAABLgAECn8VAAMJAAgJ1A0TbAAUAQAJAAcJegsTbAAUAQAQAAIJGgXrmABCAAABLgAFFAQJEAAMAMAGAA==.',
Ti='Tigs:BAAALgADCgMJAwAAAA==.Time:BAAALgAECgUJCAAAAA==.Tinyjapeto:BAAALgAECgQJBAAAAA==.Titanbow:BAAALgADCgYJBgABLgAECgkJMAAYALAfAA==.',
To='Tomcatt:BAABLgAECn9JAAITAAkJOCNxBwAhAwATAAkJOCNxBwAhAwAAAA==.Tonshaw:BAAALgAECgYJBgAAAA==.Toome:BAAALgADCgUJBQAAAA==.Toxin:BAAALgADCgEJAQAAAA==.',
Tr='Trailis:BAAALgAECgQJBwAAAA==.Travalden:BAAALgADCgMJAwAAAA==.Trekkie:BAAALgAECgUJBQABLgAFFAcJHwAiAAoQAA==.Treè:BAAALgAECgMJCgAAAA==.Trioxinn:BAAALgADCgEJAQAAAA==.',
Tu='Tuddlly:BAAALgAECgUJCgAAAA==.Turdfergison:BAAALgADCgUJDgABLgAECgkJJwAPAMwgAA==.Turin:BAABLgAECn8vAAIOAAkJHwheHgA+AQAOAAkJHwheHgA+AQAAAA==.Turnip:BAABLgAFFH8FAAIVAAIJWgztUABcAAAVAAIJWgztUABcAAABLgAFFAgJIAAMALscAA==.Tutonik:BAAALgADCgUJBQAAAA==.Tuubarkk:BAAALgADCgcJCAAAAA==.',
Tw='Twilghtdawn:BAABLgAECn8rAAIhAAgJ4Be4FgCxAQAhAAgJ4Be4FgCxAQAAAA==.Twos:BAAALgAECgEJAQAAAA==.Twotone:BAAALgADCgMJAwAAAA==.',
Ty='Tybo:BAABLgAECn83AAIjAAkJFSOvAQAXAwAjAAkJFSOvAQAXAwAAAA==.Tybs:BAAALgADCgEJAQAAAA==.',
['Tô']='Tôliah:BAAALgAECgEJAQAAAA==.',
Un='Uncás:BAABLgAECn8VAAITAAYJIgdZeAD+AAATAAYJIgdZeAD+AAAAAA==.Ungieblinks:BAAALgAECgQJCwAAAA==.Ungislayer:BAAALgADCgMJAwAAAA==.Unglifettv:BAACLgAFFH8MAAImAAQJBBseJAA9AQAmAAQJBBseJAA9AQAuAAQKfxUAAiYACAkxF1ofAN0BACYACAkxF1ofAN0BAAAA.Unstable:BAAALgAECgQJBgABLgAECgcJCAAUAAAAAA==.',
Up='Upchucky:BAAALgAECggJDQAAAA==.',
Ur='Urulóki:BAAALgAECgcJCAAAAA==.',
Va='Vaedeath:BAABLgAECn9DAAIhAAkJJiCKCQB5AgAhAAkJJiCKCQB5AgAAAA==.Vaina:BAAALgADCgMJAwAAAA==.Vainagos:BAABLgAECn8dAAQlAAYJpB33BwCzAQAlAAYJpB33BwCzAQAmAAQJ5RYzRgAPAQAWAAUJTxBSHQAOAQAAAA==.Valaryon:BAAALgAECgcJEwAAAA==.Valkorin:BAAALgAECgYJBwAAAA==.Valoryan:BAABLgAECn9JAAIMAAkJYRaaHQBXAgAMAAkJYRaaHQBXAgAAAA==.Valyteilssra:BAAALgAECgQJCQAAAA==.Vanaakaa:BAAALgADCgQJBAAAAA==.Vanity:BAAALgAECgMJBQAAAA==.Varindra:BAAALgAECgMJBAABLgAFFAUJEwAVAMogAA==.Vasoline:BAAALgAFFAEJAQAAAA==.Vayluna:BAAALgAECgMJAwAAAA==.',
Ve='Vegà:BAABLgAECn8oAAIHAAkJ+BGOHAC/AQAHAAkJ+BGOHAC/AQAAAA==.Veina:BAAALgADCgQJCAAAAA==.Velyndris:BAAALgAECgYJCwAAAA==.Velysia:BAAALgADCgMJAwAAAA==.Vendettis:BAAALgAECgYJDQAAAA==.Verin:BAAALgAECgMJBgAAAA==.Vetraugr:BAAALgADCgMJAwABLgAECgYJDQAUAAAAAA==.Vextaerin:BAAALgAECgYJDQAAAA==.Vextarin:BAAALgADCgEJAQABLgAECgYJDQAUAAAAAA==.Veylyn:BAAALgADCgEJAQAAAA==.',
Vi='Virulent:BAAALgADCgYJCgAAAA==.Vivienreed:BAAALgAECgEJAgABLgAFFAUJDQAlANQLAA==.',
Vo='Voiddemon:BAAALgAECgEJAQAAAA==.Voidhax:BAAALgAECgUJBQAAAA==.Voidi:BAABLgAECn8XAAQbAAcJVyOsFQBiAgAbAAcJtCKsFQBiAgAkAAQJESEBDQBPAQAnAAEJtAOkDwAoAAAAAA==.Voidyo:BAACLgAFFH8SAAIYAAQJIxdcQQAeAQAYAAQJIxdcQQAeAQAuAAQKfxAAAhgACAmuHnY8ANMBABgACAmuHnY8ANMBAAAA.Voralyth:BAAALgADCggJCQAAAA==.Voranne:BAABLgAECn82AAIGAAkJdgwvJgCaAQAGAAkJdgwvJgCaAQAAAA==.Vortice:BAABLgAECn9MAAQQAAkJ9hT4HAD4AQAQAAkJ8hT4HAD4AQAJAAkJOw58SgCDAQAjAAMJtgfbKABOAAAAAA==.Vowwel:BAAALgAECgEJAQAAAA==.',
Vy='Vyserlai:BAAALgADCgUJBQAAAA==.',
Wa='War:BAAALgAECgYJBwAAAA==.Ware:BAAALgADCgcJBwAAAA==.Warraxgos:BAAALgADCgkJHgABLgAFFAIJBQAXACANAA==.Warraxhunt:BAAALgAECgYJCAABLgAFFAIJBQAXACANAA==.Warraxmonk:BAAALgADCgYJBgABLgAFFAIJBQAXACANAA==.',
We='Weißenacht:BAAALgAECgMJAwAAAA==.',
Wh='Wheatstraw:BAAALgAECgMJBgAAAA==.Whiskeyjak:BAABLgAECn8nAAMOAAkJKR3NEADbAQAOAAUJaiLNEADbAQAKAAgJOg+vNwBpAQAAAA==.',
Wi='Willowest:BAABLgAECn88AAITAAkJqBu5GgCCAgATAAkJqBu5GgCCAgAAAA==.',
Wr='Wrathstorm:BAABLgAECn8pAAIjAAkJ8h5XBQCNAgAjAAkJ8h5XBQCNAgAAAA==.Wrekonhoof:BAAALgAECgEJAQAAAA==.',
Wt='Wtfpie:BAACLgAFFH8YAAMRAAYJFxQ4GABEAQARAAYJFxQ4GABEAQASAAEJyBrJJABNAAAuAAQKfzoAAhEACQk3I5MOAPYCABEACQk3I5MOAPYCAAAA.',
Wu='Wurmoneonine:BAAALgADCgUJBQABLgAECgkJMAAMAIYXAA==.Wurmy:BAABLgAECn8wAAMMAAkJhhesHgBOAgAMAAkJhhesHgBOAgALAAYJSBO3PwAMAQAAAA==.',
Wy='Wyndrunner:BAAALgADCgkJCQABLgAFFAMJCwATACsGAA==.',
['Wá']='Wárgbáte:BAAALgADCgcJBwAAAA==.',
Xa='Xalgas:BAABLgAECn8YAAIGAAYJaxaVKwB/AQAGAAYJaxaVKwB/AQAAAA==.Xanier:BAAALgAECgUJDAAAAA==.Xanivus:BAAALgAECgQJBAAAAA==.',
Xe='Xelagos:BAABLgAECn8gAAQWAAkJMRE3GABMAQAWAAgJKhA3GABMAQAlAAQJ6BZxGQCFAAAmAAMJ5BWvUwB4AAAAAA==.Xerxesjr:BAAALgADCgEJAQAAAA==.',
Xi='Xioamara:BAAALgAECgcJEwAAAA==.',
Xo='Xorm:BAAALgAECgkJBgAAAA==.',
Xx='Xxd:BAAALgAECgEJAQAAAA==.',
Ya='Yanella:BAABLgAECn8wAAMCAAkJ3BxfCgC+AgACAAkJ3BxfCgC+AgADAAEJcwWmWgAtAAAAAA==.',
Yi='Yispally:BAAALgAECgQJCgAAAA==.Yisshaman:BAABLgAECn8eAAIQAAkJXhvZDADQAgAQAAkJXhvZDADQAgAAAA==.',
Yo='Yo:BAABLgAFFH8GAAMfAAQJaBx1CgBFAQAfAAQJaBx1CgBFAQAeAAEJWQaKIQAqAAABLgAFFAgJJQAOAJojAA==.Yogibearz:BAAALgAECgQJBwABLgAECgUJFAAHAJYQAA==.Yogimonk:BAABLgAECn8UAAIHAAUJlhCETwDBAAAHAAUJlhCETwDBAAAAAA==.',
Za='Zanax:BAAALgAECgcJCAAAAA==.Zandarbribbs:BAABLgAECn8hAAIEAAgJRRVaYQCsAQAEAAgJRRVaYQCsAQAAAA==.Zapzug:BAAALgADCgYJDQAAAA==.Zaratras:BAAALgAECgEJAQAAAA==.Zaydozer:BAAALgAECgcJCwAAAA==.',
Ze='Zenmetsu:BAAALgAECgUJBgAAAA==.Zennya:BAABLgAECn8tAAIMAAkJPBfxHgBMAgAMAAkJPBfxHgBMAgAAAA==.Zeon:BAAALgAECgYJEQAAAA==.Zezra:BAAALgADCgEJAQAAAA==.',
Zi='Zikoth:BAAALgADCgEJAQAAAA==.Zingers:BAAALgAECgMJAwAAAA==.',
Zm='Zmd:BAAALgAECgYJEQAAAA==.',
Zo='Zoeso:BAABLgAECn83AAMHAAkJfx/UBgDJAgAHAAkJfx/UBgDJAgAVAAUJyQ7lYgDpAAAAAA==.',
Zt='Ztropos:BAAALgAECgcJBwAAAA==.',
Zu='Zucchini:BAAALgAECgUJBQAAAA==.',
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
