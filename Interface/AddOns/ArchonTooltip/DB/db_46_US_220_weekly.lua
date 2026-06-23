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

local lookup = {'Mage-Frost','Priest-Holy','Priest-Discipline','Paladin-Retribution','Hunter-Marksmanship','Priest-Shadow','Monk-Brewmaster','Monk-Windwalker','Shaman-Restoration','Warrior-Fury','Druid-Balance','Druid-Restoration','Warlock-Affliction','Warrior-Protection','DemonHunter-Vengeance','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Frost','Hunter-BeastMastery','Unknown-Unknown','Monk-Mistweaver','Evoker-Preservation','DemonHunter-Havoc','DemonHunter-Devourer','Warlock-Destruction','Warlock-Demonology','Rogue-Subtlety','Druid-Feral','Warrior-Arms','Paladin-Holy','Druid-Guardian','Hunter-Survival','DeathKnight-Blood','Paladin-Protection','Shaman-Enhancement','Rogue-Assassination','Evoker-Devastation','Evoker-Augmentation','Rogue-Outlaw',}
local provider = {region='US',realm='Thunderhorn',name='US',type='weekly',zone=46,date='2026-06-21',data={Ab='Absynthe:BAAALgAECgYJDQAAAA==.Abysmal:BAAALgADCgYJBgABLgAECgkJIwABAEoOAA==.Abÿss:BAAALgAECgMJCAAAAA==.',
Ac='Achêrøn:BAAALgADCgcJBwAAAA==.Acoghai:BAAALgADCgcJDQAAAA==.',
Ad='Adoweld:BAAALgADCgcJBQAAAA==.Adøland:BAAALgADCgYJBgAAAA==.',
Ae='Aeliis:BAABLgAECn8lAAMCAAkJ5AySLABmAQACAAkJ5AySLABmAQADAAMJbQQlYgB0AAAAAA==.Aellart:BAAALgAECgEJAgAAAA==.Aeriona:BAABLgAECn84AAIEAAkJHxzWIwB2AgAEAAkJHxzWIwB2AgAAAA==.Aerosoul:BAAALgADCgEJAQAAAA==.',
Ag='Agamsi:BAABLgAECn8UAAIFAAgJcwujGADsAAAFAAgJcwujGADsAAAAAA==.',
Ai='Aine:BAABLgAECn8oAAMCAAgJuRnsFQAkAgACAAgJuRnsFQAkAgAGAAYJ6wA/WABcAAAAAA==.Ainek:BAAALgAECgUJCAAAAA==.Ainkor:BAAALgAFFAMJAwABLgAFFAMJCgAHADsNAA==.',
Aj='Ajani:BAABLgAECn8VAAMHAAgJ7xrgFQD9AQAHAAgJ7xrgFQD9AQAIAAQJXghnXgCeAAAAAA==.',
Ak='Akyospirit:BAABLgAECn9BAAIJAAkJShMTAgBfAQAJAAkJShMTAgBfAQAAAA==.Akyowindz:BAAALgAECgQJBAAAAA==.',
Al='Al:BAAALgAECgYJEAABLgAFFAUJBwAKAJ8SAA==.Alava:BAAALgADCgEJAQAAAA==.Algorimortis:BAAALgADCgIJAgAAAA==.Aliatra:BAABLgAECn9CAAMLAAkJxRLEHQDaAQALAAkJxRLEHQDaAQAMAAEJmgjY8gAfAAAAAA==.Alinth:BAAALgAECgMJBQAAAA==.Almosthuman:BAAALgAECgYJCgAAAA==.Alpha:BAABLgAECn87AAIBAAkJ7x1aGwC3AgABAAkJ7x1aGwC3AgAAAA==.Alroy:BAAALgAECgkJDgAAAA==.Aluina:BAAALgAFFAEJAQAAAA==.Alustryelle:BAAALgADCgkJEgABLgAECgkJOgAJAGgQAA==.Alykia:BAAALgADCgYJBgAAAA==.',
Am='Amamonk:BAABLgAECn9CAAMHAAkJkhl7FgD3AQAHAAkJDRV7FgD3AQAIAAYJUSDVGwDRAQAAAA==.Amandara:BAAALgADCgUJBQAAAA==.Ammert:BAABLgAECn84AAINAAkJ+BGaCADeAQANAAkJ+BGaCADeAQAAAA==.Amonet:BAAALgADCgYJEQAAAA==.',
An='Anathema:BAAALgAECgQJCAAAAA==.Anchovy:BAAALgAFFAMJBAABLgAFFAgJJQAOAJojAA==.Andou:BAAALgADCgcJBwAAAA==.Angeldracul:BAAALgADCgQJBwAAAA==.Angelove:BAAALgAECgQJDAAAAA==.Anglico:BAAALgAECgQJBQABLgAECgkJKgAPAMwgAA==.Angliko:BAAALgAECgUJCAABLgAECgkJKgAPAMwgAA==.Anglikoo:BAAALgADCggJCAABLgAECgkJKgAPAMwgAA==.Anomandaris:BAABLgAECn8gAAMQAAkJVBVQJwCyAQAQAAgJ4RZQJwCyAQAJAAEJTAYh3QArAAAAAA==.Anquan:BAABLgAECn8yAAIRAAgJThzQAQCkAQARAAgJThzQAQCkAQAAAA==.',
Ap='Apedemak:BAAALgAECgYJDwAAAA==.Aphobias:BAAALgAECgUJCwAAAA==.Aphradite:BAAALgADCgYJCwAAAA==.Apothica:BAABLgAECn8YAAIBAAgJIw6hfQB8AQABAAgJIw6hfQB8AQAAAA==.Apothicc:BAABLgAECn8kAAMRAAgJVhYYSADqAQARAAgJVhYYSADqAQASAAEJAADHRwAAAAAAAA==.Appalonio:BAAALgADCgcJBQAAAA==.Appaur:BAAALgADCgEJAQAAAA==.Appolymi:BAABLgAECn8xAAITAAkJjwVYcABgAQATAAkJjwVYcABgAQAAAA==.Apraxia:BAAALgADCgUJBQAAAA==.Aprionos:BAABLgAECn82AAIBAAgJ7AU1rwAiAQABAAgJ7AU1rwAiAQAAAA==.',
Ar='Arakek:BAAALgADCgcJCAAAAA==.Arataena:BAAALgADCgkJFgAAAA==.Arceus:BAAALgAECgMJBQAAAA==.Archibald:BAAALgAECgYJBgAAAA==.Aredhël:BAAALgADCgYJDgAAAA==.Argentavis:BAAALgAECggJEgABLgAECggJEwAUAAAAAA==.Argobow:BAAALgAFFAEJAgAAAA==.Argonaut:BAAALgAFFAMJBAAAAA==.Aristella:BAAALgADCgMJAwAAAA==.Arkken:BAABLgAECn8bAAIVAAcJ2iILDwCxAgAVAAcJ2iILDwCxAgABLgAECgkJRQADAJUjAA==.Artee:BAAALgAECgEJAQAAAA==.Artémis:BAABLgAECn8iAAITAAgJgRATawBsAQATAAgJgRATawBsAQAAAA==.',
As='Ascender:BAAALgAECgQJBAAAAA==.Ashadox:BAAALgAECgUJCgAAAA==.Asheritâ:BAAALgADCgcJBwAAAA==.Ashvalis:BAABLgAECn8cAAIWAAcJzSPFCQCaAgAWAAcJzSPFCQCaAgAAAA==.Asillyhunter:BAAALgADCgMJAwAAAA==.Asillypally:BAABLgAECn8kAAIEAAgJeBYaXgDJAQAEAAgJeBYaXgDJAQAAAA==.Askr:BAABLgAECn8qAAMTAAkJExHPPgDmAQATAAkJ6RDPPgDmAQAFAAYJnwoIIQCpAAAAAA==.Asphar:BAABLgAECn8yAAMTAAkJ2iV5AwBaAwATAAkJ2iV5AwBaAwAFAAMJChNoLQBhAAAAAA==.Asphel:BAAALgAECgEJAgAAAA==.Asteroth:BAAALgAECgEJAQAAAA==.',
Au='Aung:BAACLgAFFH8UAAIXAAQJACN3BwCPAQAXAAQJACN3BwCPAQAuAAQKf0sAAxcACQkkJm4BAGcDABcACQkkJm4BAGcDABgAAQmNBr0tASIAAAAA.Auri:BAAALgAECgQJBAAAAA==.',
Av='Avatan:BAAALgAECgMJAwABLgAECgkJLwAKAIcOAA==.Avralis:BAAALgADCgMJAwABLgAECggJHQAYAEocAA==.',
Ax='Axex:BAAALgAECgkJDQAAAA==.',
Az='Azamii:BAABLgAECn88AAMQAAkJOSKoBQADAwAQAAkJOSKoBQADAwAJAAYJQRgUOwCVAQAAAA==.Azarion:BAABLgAECn84AAMZAAgJch1xCwCKAQAZAAcJnRtxCwCKAQAaAAYJlBm1YAB+AQAAAA==.Azill:BAACLgAFFH8WAAIIAAYJIhpWBwChAQAIAAYJIhpWBwChAQAuAAQKfyYAAggACAleHjMKANUCAAgACAleHjMKANUCAAAA.Azzrael:BAABLgAECn8qAAIOAAkJzBDSFADAAQAOAAkJzBDSFADAAQAAAA==.',
Ba='Baalalmerat:BAAALgAECgIJAgAAAA==.Bandi:BAABLgAECn8ZAAIaAAYJiR4BAgBUAQAaAAYJiR4BAgBUAQAAAA==.Bartrak:BAACLgAFFH8JAAMGAAMJbAdVKQC0AAAGAAMJbAdVKQC0AAADAAIJNwqwQAB3AAAuAAQKfxsAAwYACQk/E3kkAKYBAAYACQk/E3kkAKYBAAMABQlsEZJbAJEAAAAA.',
Be='Bearfucius:BAABLgAECn8iAAIIAAkJcxJ1AADpAQAIAAkJcxJ1AADpAQAAAA==.Bearrific:BAACLgAFFH8HAAIbAAIJuRAJBwChAAAbAAIJuRAJBwChAAAuAAQKfyYAAhsACQnvGtwOAD0CABsACQnvGtwOAD0CAAAA.Beawulf:BAAALgAECgQJBAAAAA==.Behomadra:BAAALgAECgkJCQAAAA==.Belista:BAAALgAECgQJBAAAAA==.Bethel:BAAALgADCgYJCAAAAA==.Beyond:BAAALgAECgMJAwAAAA==.',
Bf='Bfresh:BAAALgADCgcJDgAAAA==.',
Bi='Bibidi:BAAALgAECgQJBAABLgAECgkJLAAcAAwfAA==.Billie:BAAALgADCgcJAgAAAA==.Billthekid:BAAALgAECgYJCwAAAA==.Billybobb:BAAALgAECgYJDgAAAA==.Biney:BAABLgAECn8gAAIOAAYJIRznFgCMAQAOAAYJIRznFgCMAQAAAA==.Binksy:BAACLgAFFH8VAAIKAAYJIhS4EQB5AQAKAAYJIhS4EQB5AQAuAAQKfyoAAgoACQkFHskNAOcCAAoACQkFHskNAOcCAAAA.Biscuit:BAACLgAFFH8lAAIOAAgJmiMFAQAJAgAOAAgJmiMFAQAJAgAuAAQKfyIAAg4ACQkfJe4AAJYDAA4ACQkfJe4AAJYDAAAA.Bitcoìn:BAAALgAECgEJAgAAAA==.',
Bl='Blaam:BAAALgAECgQJEgAAAA==.Blazin:BAACLgAFFH8tAAIBAAYJUxjyMgCdAQABAAYJUxjyMgCdAQAuAAQKfzYAAgEACQkPH3ISAOsCAAEACQkPH3ISAOsCAAAA.Blep:BAAALgAECgYJCgAAAA==.Blgunc:BAAALgAECgkJEQAAAA==.Blinkzy:BAAALgAECgUJCQAAAA==.Blitzoria:BAAALgADCgYJBgABLgAECggJGAAEAMwQAA==.Bloui:BAAALgAECgQJCwAAAA==.Bluesummers:BAAALgADCgkJCQAAAA==.',
Bo='Boba:BAAALgAECgYJBgABLgAFFAgJJQAOAJojAA==.Bongrips:BAAALgADCgcJCQAAAA==.Boomboom:BAAALgAECgUJCAAAAA==.Borlok:BAAALgAFFAQJBQAAAQ==.',
Br='Brannigan:BAABLgAECn88AAIOAAkJFiQlAgArAwAOAAkJFiQlAgArAwAAAA==.Braulioo:BAAALgAFFAMJAwAAAA==.Breebbs:BAAALgAECgUJBQAAAA==.Briantu:BAABLgAECn8qAAMJAAkJNQX+hADUAAAJAAgJ/QH+hADUAAAQAAEJEASVuQAjAAAAAA==.Brickitphil:BAABLgAECn8dAAISAAgJ8BmWBwAdAgASAAgJ8BmWBwAdAgAAAA==.Briiz:BAAALgADCgkJDAAAAA==.Brlolock:BAAALgAECgEJAQAAAA==.Brollo:BAAALgADCgEJAQAAAA==.Brud:BAAALgADCgYJAwAAAA==.Brönwyn:BAAALgAECgMJCAAAAA==.',
Bu='Bubblegumdrp:BAAALgAECgMJAwAAAA==.Bubblicious:BAAALgADCgUJCQAAAA==.Buckets:BAAALgAECgcJEgABLgAECggJCgAUAAAAAA==.Budi:BAAALgADCgcJCAAAAA==.Bulldan:BAABLgAECn8mAAINAAgJBx6bBQAtAgANAAgJBx6bBQAtAgAAAA==.Bullvi:BAAALgAECgYJBgAAAA==.',
['Bä']='Bärkler:BAABLgAECn8cAAMdAAkJaSIQBQC+AgAdAAkJaSIQBQC+AgAOAAEJHBiFTwA9AAAAAA==.',
['Bé']='Béckley:BAAALgAECggJEgAAAA==.Béckléy:BAAALgAECgUJDQABLgAECggJEgAUAAAAAA==.',
Ca='Caatha:BAAALgAECgQJBAAAAA==.Caleanone:BAAALgAFFAIJAgABLgAFFAUJBwAKAJ8SAA==.Calel:BAAALgAECgkJEAAAAA==.Callox:BAACLgAFFH8HAAIKAAUJnxLTHwAyAQAKAAUJnxLTHwAyAQAuAAQKfysABAoACAkFHAYpALUBAAoACAkhGwYpALUBAB0ABQknG+0RAIIBAA4ABgllDFsvAMQAAAAA.Cantelope:BAAALgADCgYJBgAAAA==.Capslock:BAAALgAECgQJAwAAAA==.Cara:BAAALgADCgIJAgAAAA==.Carahail:BAACLgAFFH8QAAMMAAQJwAbZPgC1AAAMAAQJwAbZPgC1AAALAAEJ6wFBVgApAAAuAAQKfzQAAwwACQmYFO4iADICAAwACQmYFO4iADICAAsABgkAD3lDAP8AAAAA.Carra:BAAALgAFFAIJAgAAAA==.Catriona:BAABLgAECn8iAAITAAkJgwqSYQCDAQATAAkJgwqSYQCDAQAAAA==.Cazmeer:BAABLgAECn8XAAILAAcJogfaSwDcAAALAAcJogfaSwDcAAAAAA==.',
Ce='Ceairra:BAAALgAECgUJBQAAAA==.Celés:BAAALgAECgUJBQAAAA==.',
Ch='Charcuterie:BAACLgAFFH8mAAIHAAgJPh3MBwASAgAHAAgJPh3MBwASAgAuAAQKfyAAAwcACQnYIVwJAPMCAAcACQnYIVwJAPMCAAgAAQlxHUmEAFAAAAAA.Chaír:BAAALgAECgEJBQAAAA==.Cheezeburg:BAAALgAECgcJCQABLgAECgkJIQAHAC4ZAA==.Cheezus:BAAALgAECgUJDQABLgAECgkJIQAHAC4ZAA==.Cherrbeår:BAAALgADCgcJBwAAAA==.Cherudim:BAACLgAFFH8GAAMZAAMJ4wsjDwCHAAAaAAMJ4wtGggDBAAAZAAIJrwIjDwCHAAAuAAQKfyYAAxkACAkiF44JACcCABkACAmBFY4JACcCABoACAl3FOtXAJUBAAAA.Chillainkor:BAACLgAFFH8KAAIHAAMJOw3LOwC3AAAHAAMJOw3LOwC3AAAuAAQKfykAAgcACQk7FpMYAOIBAAcACQk7FpMYAOIBAAAA.Chillidán:BAABLgAECn8oAAIYAAkJ+gatBwCFAAAYAAkJ+gatBwCFAAAAAA==.Chippmagi:BAABLgAECn8gAAIBAAgJ9RrxVQDbAQABAAgJ9RrxVQDbAQAAAA==.Chippndots:BAAALgAECgYJDAABLgAECggJIAABAPUaAA==.Chirp:BAAALgAECgEJAQAAAA==.Chives:BAAALgAECgQJBAAAAA==.Choggie:BAACLgAFFH8NAAIeAAQJRxFrIwAFAQAeAAQJRxFrIwAFAQAuAAQKfz4AAh4ACQl2IGAFADwDAB4ACQl2IGAFADwDAAAA.Chronocolter:BAAALgADCgMJAwAAAA==.Chronosaren:BAABLgAECn8UAAIBAAkJyxENWQDSAQABAAkJyxENWQDSAQAAAA==.Chåir:BAAALgAECgEJAgAAAA==.',
Ci='Cinterax:BAAALgAECgIJAgABLgAECgkJPAAOABYkAA==.',
Cj='Cjrej:BAABLgAECn8+AAIBAAkJOxHiAwAwAQABAAkJOxHiAwAwAQAAAA==.',
Cl='Claytonis:BAAALgAECgEJAQAAAA==.Cloudnine:BAAALgAECgQJBAAAAA==.',
Co='Colterr:BAAALgADCgEJAQAAAA==.Cons:BAABLgAECn8zAAQDAAkJGR5dBgAbAwADAAkJGR5dBgAbAwACAAMJKw3YZQCWAAAGAAEJ+xLvhQAzAAAAAA==.Corellon:BAABLgAECn8rAAITAAkJnRvkLQAlAgATAAkJnRvkLQAlAgAAAA==.Costcohotdog:BAABLgAFFH8KAAMHAAMJLR1IGACsAAAHAAMJLR1IGACsAAAVAAEJOQBpGgAYAAABLgAFFAgJJQAOAJojAA==.Cougarclaws:BAAALgAECgUJCQAAAA==.',
Cr='Craftsman:BAAALgADCgUJBQAAAA==.Craigchrist:BAAALgAECgYJBgAAAA==.Cranee:BAABLgAECn88AAIaAAkJ0xUzAgBCAQAaAAkJ0xUzAgBCAQAAAA==.Cranium:BAAALgAECgUJCAAAAA==.Crazytasty:BAABLgAECn8nAAITAAkJySICDgDhAgATAAkJySICDgDhAgAAAA==.Crumbo:BAAALgAECgYJBgAAAA==.Cryoburn:BAABLgAECn8fAAIBAAgJWB1rWAAwAgABAAgJWB1rWAAwAgABLgAFFAMJBwAQAMAWAA==.Cryoshock:BAABLgAFFH8HAAIQAAMJwBYENAC/AAAQAAMJwBYENAC/AAAAAA==.',
Cu='Cutty:BAAALgAECgUJBgAAAA==.',
['Cø']='Cøns:BAAALgAECgYJCgAAAA==.',
Da='Daario:BAABLgAECn8TAAIYAAcJsB+pNQAhAgAYAAcJsB+pNQAhAgAAAA==.Dabare:BAAALgADCgUJAQAAAA==.Dabora:BAAALgAECgEJAQABLgAECgkJLAAcAAwfAA==.Dabßod:BAAALgAECgQJBAAAAA==.Dabûra:BAABLgAECn8sAAQcAAkJDB8mCQA0AgAcAAgJTB0mCQA0AgALAAYJTR7FRAD5AAAfAAcJehCaMQDkAAAAAA==.Daenerys:BAAALgAECgIJBgAAAA==.Dahouse:BAAALgADCgQJAwAAAA==.Dahpeht:BAAALgADCgkJEwAAAA==.Damda:BAAALgADCgIJAgAAAA==.Dandypooh:BAAALgAECgYJBgABLgAECgcJDQAUAAAAAA==.Danksamdi:BAAALgAECgEJAQAAAA==.Dante:BAAALgAECgcJCwAAAA==.Darige:BAAALgAECgIJAgAAAA==.Darim:BAAALgAECgYJBgABLgAECgkJKQABAFwaAA==.Darrow:BAAALgAECggJCAAAAA==.Darthspawn:BAABLgAECn8oAAIRAAkJfgzBfgBmAQARAAkJfgzBfgBmAQAAAA==.Daryl:BAAALgAECgQJBAAAAA==.Daryn:BAAALgAECgYJDAAAAA==.Davidbowy:BAABLgAECn8ZAAMgAAgJsA3bLAA+AQAgAAcJ7wjbLAA+AQATAAcJYQ4IjQAlAQABLgAECgYJBwAUAAAAAA==.',
De='Deadchops:BAAALgAECgEJAwABLgAECgcJCAAUAAAAAA==.Deathnstuf:BAAALgAECgQJBgAAAA==.Deathollow:BAAALgAECgEJBAAAAA==.Delver:BAAALgADCgYJBgABLgAECgkJKQABAFwaAA==.Demai:BAAALgAECggJCQAAAA==.Demina:BAAALgAECgQJBgABLgAECggJHQAYAEocAA==.Demonainkor:BAAALgAFFAEJAQABLgAFFAMJCgAHADsNAA==.Demonicfury:BAAALgAECgYJBwAAAA==.Demonthrall:BAAALgAECgEJAQAAAA==.Dencity:BAABLgAECn88AAMDAAkJshekEgBOAgADAAkJUhakEgBOAgACAAYJbxcjOQAVAQAAAA==.Dendwran:BAAALgAECgkJCQAAAA==.Desden:BAABLgAECn9BAAIfAAkJPBRRFAC0AQAfAAkJPBRRFAC0AQAAAA==.Destined:BAAALgAECgYJBwAAAA==.Devianchi:BAABLgAECn8oAAMVAAgJ+B+FCQC5AgAVAAgJ+B+FCQC5AgAIAAcJIh+7GADsAQAAAA==.Devitodevour:BAABLgAECn8iAAMaAAgJ1hsHQQDZAQAaAAgJNBoHQQDZAQAZAAMJXBkENQDiAAAAAA==.',
Dg='Dgbugs:BAACLgAFFH8KAAIRAAMJoCL7lgDgAAARAAMJoCL7lgDgAAAuAAQKfzIAAhEACAk9IwIoAGICABEACAk9IwIoAGICAAAA.',
Dh='Dhbert:BAABLgAECn8sAAIhAAkJ5xGtFgCzAQAhAAkJ5xGtFgCzAQAAAA==.Dhomeli:BAAALgAECgQJBQABLgAECgYJIAAOACEcAA==.',
Di='Dirtchez:BAAALgAECgIJAwAAAA==.Disastrophy:BAAALgAECgYJEQABLgAECgcJCAAUAAAAAA==.Disturbed:BAABLgAECn8/AAQNAAkJ4yEEAQAIAwANAAkJsCEEAQAIAwAaAAgJNRsXJwBBAgAZAAEJAADbYgBJAAAAAA==.Disturbio:BAAALgAECgEJAQABLgAECgkJPwANAOMhAA==.Divinepsycho:BAAALgADCgcJBwAAAA==.Divitiacus:BAAALgAECgYJBgAAAA==.',
Dj='Djowio:BAAALgADCgYJBgABLgAECggJIwAaABoiAA==.',
Dk='Dknightresh:BAAALgAECgcJBwABLgAECgcJLAAKAIQTAA==.Dkson:BAAALgAFFAIJAgAAAA==.',
Dm='Dmz:BAAALgADCgUJBgAAAA==.',
Do='Docen:BAAALgADCgkJCwAAAA==.Domfromgears:BAAALgAECgQJCQAAAA==.Dominance:BAAALgAECgEJAQAAAA==.Doomgaze:BAAALgADCgMJAQAAAA==.Dorc:BAAALgAECgMJBQAAAA==.Dotyou:BAAALgAECgIJAgAAAA==.Doudouzz:BAAALgAECgQJDQAAAA==.',
Dr='Dracthor:BAAALgADCgQJBAAAAA==.Dracu:BAAALgAECgUJBQAAAA==.Draejin:BAAALgAECgkJDwAAAA==.Dragonfist:BAAALgADCgcJBwAAAA==.Dragonlore:BAAALgAFFAIJAwAAAA==.Dragthyr:BAAALgAECgUJCgAAAA==.Dramûl:BAABLgAECn8dAAITAAgJcRgMUQCvAQATAAgJcRgMUQCvAQAAAA==.Dreadedmonk:BAAALgAECgEJAgAAAA==.Dreadnought:BAAALgAECgEJAQAAAA==.Druiaier:BAAALgADCgYJCQAAAA==.Druidibrume:BAAALgAECgMJDAAAAA==.Druknatsu:BAAALgAECgcJDAAAAA==.Drunkdragon:BAABLgAECn8UAAIIAAgJRRLpGwD9AQAIAAgJRRLpGwD9AQAAAA==.Drwhodunnit:BAAALgAECgMJBgAAAA==.',
Du='Dubbzilla:BAAALgAECgEJAQAAAA==.Dudedruid:BAAALgADCgUJBQAAAA==.Duncán:BAABLgAFFH8JAAQEAAUJ+RtRNABGAQAEAAUJ+RtRNABGAQAiAAEJoBU+GAA5AAAeAAEJmwR8TwAsAAABLgAFFAYJDAAJAIYiAA==.Dustyknight:BAABLgAECn8tAAIhAAkJcw/nGACbAQAhAAkJcw/nGACbAQAAAA==.',
Dw='Dwell:BAAALgADCgkJJQAAAA==.',
Dy='Dyavola:BAAALgAECgUJBQAAAA==.',
Ea='Earthquack:BAAALgAECgUJBQABLgAECggJGwAiADMVAA==.',
Ed='Edge:BAABLgAECn8eAAIJAAgJShVjNgDXAQAJAAgJShVjNgDXAQAAAA==.',
Ee='Eelenna:BAABLgAECn8ZAAMjAAkJLhxgBgCSAgAjAAkJLhxgBgCSAgAQAAUJwRBnUwD4AAABLgAFFAUJEwASAIUUAA==.',
El='Elamlock:BAAALgADCgYJCwAAAA==.Eleathe:BAABLgAFFH8FAAIVAAQJwQx+PACzAAAVAAQJwQx+PACzAAABLgAECggJHQAYAEocAA==.Eleros:BAABLgAECn8wAAIYAAkJsB/XEAC7AgAYAAkJsB/XEAC7AgAAAA==.Elicio:BAAALgAECgYJEAAAAA==.Ellysial:BAAALgADCgUJBQAAAA==.Elphinia:BAABLgAECn8zAAMbAAkJqxlNEQAeAgAbAAkJqxlNEQAeAgAkAAEJ4BFlIAAxAAABLgAFFAQJDAAQAIoNAA==.Elreÿ:BAAALgADCgEJAQAAAA==.Elyas:BAAALgAECgIJBAAAAA==.',
Em='Emberwrath:BAAALgADCgMJAwAAAA==.Embr:BAAALgAECgMJAwAAAA==.Emosdnem:BAAALgAECgQJBQAAAA==.Emt:BAAALgAECgQJBAAAAA==.',
En='Endarial:BAAALgAECgUJCwAAAA==.Enoki:BAACLgAFFH8TAAIJAAUJlRdvHQCDAQAJAAUJlRdvHQCDAQAuAAQKfxUAAwkACQkuHAYbAEACAAkACQkuHAYbAEACABAAAgl8HHtvAJsAAAEuAAUUCAkgAAwAuxwA.',
Er='Eraduckated:BAAALgAECgYJCAABLgAECggJGwAiADMVAA==.Erah:BAAALgADCgUJDQAAAA==.Ereir:BAAALgAECgMJAwABLgAFFAUJBwAKAJ8SAA==.Erzascarlett:BAAALgAECgcJDAAAAA==.',
Es='Esco:BAAALgADCgMJAwAAAA==.Esile:BAAALgAECgQJBAABLgAECgkJPgALANkRAA==.',
Et='Eternalnow:BAAALgADCgEJAQAAAA==.',
Ev='Evelith:BAAALgADCgYJBgAAAA==.Everlife:BAABLgAECn8WAAIDAAcJ3RMrJgCfAQADAAcJ3RMrJgCfAQAAAA==.',
Ex='Exemptt:BAAALgAECgkJBQAAAA==.Exo:BAAALgADCgkJDwAAAA==.',
Fa='Falconpunch:BAAALgAECgYJCwAAAA==.Farnesë:BAAALgADCgUJBwABLgADCgcJBwAUAAAAAA==.Fauzzie:BAAALgAECgIJAgAAAA==.Fayrel:BAAALgAECgYJCQAAAA==.',
Fe='Fedders:BAACLgAFFH8GAAIEAAIJFB3ehACqAAAEAAIJFB3ehACqAAAuAAQKfykAAgQACQlGJoYHAFsDAAQACQlGJoYHAFsDAAAA.Felaids:BAACLgAFFH8VAAMaAAUJkBM0ZQD8AAAaAAUJ+A80ZQD8AAANAAEJSBCNJgBJAAAuAAQKfywAAxoACQmMGogsACcCABoACAmMGogsACcCABkAAwkSCLpEAKIAAAAA.Felidoria:BAAALgAECgEJAQABLgABCgQJBQAUAAAAAA==.Felimonk:BAAALgAECgQJBwABLgABCgQJBQAUAAAAAA==.Felpecs:BAAALgAECggJDgAAAA==.Fero:BAAALgAECgUJBQAAAA==.Feyda:BAABLgAECn8pAAIBAAkJ7wcUfQB+AQABAAkJ7wcUfQB+AQAAAA==.',
Fi='Fillon:BAACLgAFFH8MAAIEAAUJ3htgBgAEAQAEAAUJ3htgBgAEAQAuAAQKfzMAAgQACQmxJXANAPkCAAQACQmxJXANAPkCAAAA.Fionas:BAAALgADCgQJBAAAAA==.Firerybush:BAAALgAECgYJBwABLgAFFAMJBwAKALUVAA==.Firessar:BAAALgAECgcJDAAAAA==.Firexcracker:BAAALgAECgMJBAAAAA==.Fishfood:BAABLgAECn9BAAISAAkJzxeGAABXAQASAAkJzxeGAABXAQAAAA==.Fishlover:BAAALgADCgUJBQAAAA==.Fixer:BAABLgAECn8gAAIiAAYJ+CLyDQDlAQAiAAYJ+CLyDQDlAQAAAA==.',
Fk='Fk:BAAALgAFFAMJAwABLgAFFAYJDAAJAIYiAA==.',
Fo='Foe:BAEALgAECggJEwAAAA==.Folkvar:BAAALgADCgcJDAAAAA==.',
Fr='Frankngibbon:BAAALgADCgYJBgAAAA==.Frimm:BAAALgAECggJDgAAAA==.Frimthemage:BAACLgAFFH8LAAIBAAQJrgwvaQARAQABAAQJrgwvaQARAQAuAAQKfzEAAgEACQlDIGMoAHkCAAEACQlDIGMoAHkCAAAA.Frostmaster:BAABLgAECn8cAAIBAAcJrRwlXADKAQABAAcJrRwlXADKAQAAAA==.',
Fu='Funbunz:BAAALgAECgcJDAAAAA==.',
['Fí']='Fízban:BAAALgAECgUJDQAAAA==.',
['Fø']='Førd:BAACLgAFFH8NAAMlAAUJ1AvlBQABAQAlAAQJFQzlBQABAQAmAAMJ0QpZRgCvAAAuAAQKfy8ABCUACAmQHRoLACoCACUABwlLGhoLACoCACYABwlOGSUkAJwBABYAAwkIAs85ADwAAAAA.',
Ga='Gammon:BAABLgAECn87AAMQAAkJmR/ECADRAgAQAAkJmR/ECADRAgAJAAgJdxqmHABnAgAAAA==.Gangrene:BAABLgAECn8yAAMRAAkJnxMLVwDAAQARAAkJnxMLVwDAAQAhAAgJCQsPLQD0AAAAAA==.Gary:BAAALgAECgQJCgAAAA==.Garzhvog:BAAALgAECgIJAgAAAA==.Gash:BAAALgAECgMJAwAAAA==.Gaspasser:BAABLgAECn88AAMkAAkJnB8wAgDDAgAkAAkJnB8wAgDDAgAbAAEJphVcWQBCAAAAAA==.Gaviin:BAABLgAECn85AAIkAAkJGCF/AgCvAgAkAAkJGCF/AgCvAgAAAA==.',
Ge='Gearador:BAAALgADCgcJAQAAAA==.Geisten:BAAALgAECgYJEwAAAA==.Genovia:BAAALgADCgIJAgABLgAECggJEwAUAAAAAA==.Gerhart:BAABLgAECn8sAAQPAAkJSxnJCADlAQAPAAkJ6hTJCADlAQAYAAcJxBl5XwBrAQAXAAMJQxAvVABoAAAAAA==.Getcarried:BAAALgADCgMJAwABLgAFFAYJLQABAFMYAA==.Getty:BAAALgAECgcJEgAAAA==.',
Gf='Gfforgold:BAAALgADCgIJAgAAAA==.',
Gh='Ghosthunterx:BAAALgADCgEJAwAAAA==.Ghouldana:BAAALgADCgYJBgAAAA==.',
Gi='Gibbthok:BAAALgADCggJCAAAAA==.Gigachode:BAAALgAECgEJAwAAAA==.Gigarius:BAABLgAECn8iAAMiAAkJSSRiAgANAwAiAAkJSSRiAgANAwAEAAQJOBsO0QDxAAAAAA==.Gigglesworth:BAAALgAECgYJBgAAAA==.Gilamonster:BAAALgAECgYJCgAAAA==.',
Gl='Gladllimbo:BAAALgADCgEJAQAAAA==.Gleiten:BAAALgADCgMJAwAAAA==.Glonkins:BAABLgAECn8nAAQTAAkJWB+DDwDUAgATAAkJWB+DDwDUAgAgAAQJ9RRVMgAaAQAFAAEJAABNSQAAAAAAAA==.Glynden:BAAALgADCgEJAQAAAA==.',
Go='Goncor:BAACLgAFFH8TAAMSAAUJhRTyDgAiAQASAAUJwxPyDgAiAQARAAQJ1w6ulgDgAAAuAAQKfykAAxIACQnkIF4EAIcCABIACQmYIF4EAIcCACEABQk+I1UbAIIBAAAA.Gonnosuke:BAABLgAECn8UAAIEAAcJjgldvQAMAQAEAAcJjgldvQAMAQAAAA==.Gooseberry:BAAALgAECgEJAQAAAA==.Goosë:BAAALgADCgcJBwAAAA==.Gorrelord:BAAALgADCgEJAQABLgAFFAYJLQABAFMYAA==.Gortar:BAAALgADCgEJAQAAAA==.',
Gr='Granolah:BAAALgADCgcJCwABLgAECgkJLAAcAAwfAA==.Griffmonk:BAABLgAECn88AAIVAAkJCRtfFQBvAgAVAAkJCRtfFQBvAgAAAA==.Grumpydaemon:BAAALgAECgMJAwABLgAECgkJOAABAOsfAA==.Grumpymage:BAABLgAECn84AAIBAAkJ6x8SGwC4AgABAAkJ6x8SGwC4AgAAAA==.',
Gu='Gussy:BAAALgAECgQJBAABLgAECggJCgAUAAAAAA==.',
Ha='Hafsac:BAAALgAECgMJAwAAAA==.Halaranth:BAAALgAECgIJAgAAAA==.Hamasakura:BAAALgAECgYJBgAAAA==.Hammerheart:BAAALgAECgIJAgAAAA==.Hanya:BAAALgAECgIJAgAAAA==.Hara:BAABLgAECn8aAAIMAAYJPRrbQwCBAQAMAAYJPRrbQwCBAQAAAA==.Hardlyknower:BAAALgADCgIJAgAAAA==.Hardord:BAABLgAECn8vAAIbAAkJMhBGGADYAQAbAAkJMhBGGADYAQAAAA==.Harrydotter:BAAALgAECgIJAgAAAA==.Haryle:BAAALgAECgYJDwAAAA==.Hayanne:BAABLgAECn84AAIOAAkJXxxWCQBgAgAOAAkJXxxWCQBgAgAAAA==.',
He='Healchucky:BAAALgAECgYJDQAAAA==.Healfire:BAAALgADCgYJBwAAAA==.Healisha:BAAALgAECgYJEQAAAA==.Healzjoogewd:BAAALgAECgEJAQAAAA==.Heina:BAAALgAECgYJBgAAAA==.Hershall:BAAALgAECgUJBQABLgAFFAQJFAAXAAAjAA==.',
Hi='Hitnrun:BAAALgAECgMJAwAAAA==.',
Ho='Hochunk:BAACLgAFFH8JAAMDAAMJHgfyNwCqAAADAAMJHgfyNwCqAAACAAEJ3wEePQAmAAAuAAQKfysAAwMACQnfFDUUAD0CAAMACQn4EzUUAD0CAAIACQm6CR07AE4BAAAA.Hochunks:BAAALgAECgYJDQAAAA==.Holdenger:BAAALgADCgQJBAAAAA==.Holikow:BAABLgAECn8aAAIEAAkJGxFebwCPAQAEAAkJGxFebwCPAQAAAA==.Holyherpies:BAAALgAECgYJBgAAAA==.Holyllama:BAAALgADCgcJBwAAAA==.Holymousey:BAABLgAECn8fAAIeAAkJjRHQJwDMAQAeAAkJjRHQJwDMAQAAAA==.Holysnake:BAAALgAECgQJBAAAAA==.Holytady:BAAALgADCgcJDQAAAA==.Holytudd:BAABLgAECn8gAAIEAAgJixS0hgBiAQAEAAgJixS0hgBiAQAAAA==.Honeybun:BAAALgADCgQJAgAAAA==.Honorlife:BAABLgAECn8xAAIJAAgJDhtMIABOAgAJAAgJDhtMIABOAgAAAA==.Hopeudie:BAAALgAECgUJBgABLgAFFAYJDAAJAIYiAA==.Horata:BAAALgAECgMJAwAAAA==.Hormuz:BAAALgADCgcJCwAAAA==.Hotelcali:BAAALgADCgkJCQAAAA==.',
Hu='Huckcold:BAAALgAECgcJDwAAAA==.Hugehands:BAAALgAECgUJBwAAAA==.Hughass:BAAALgADCgEJAQAAAA==.Hurano:BAAALgAECgYJCAAAAA==.',
Hy='Hyperious:BAAALgAECggJCAAAAA==.',
['Hâ']='Hârley:BAABLgAECn87AAIMAAkJ+BsNGACGAgAMAAkJ+BsNGACGAgAAAA==.',
['Hí']='Híram:BAABLgAECn8mAAIEAAgJahRxeAB9AQAEAAgJahRxeAB9AQAAAA==.',
Id='Idyllwild:BAAALgAECgEJBAAAAA==.',
Ih='Ihsan:BAABLgAECn85AAMEAAkJExbmOgAYAgAEAAkJExbmOgAYAgAeAAIJvhc7AwChAAAAAA==.',
Il='Ilharess:BAACLgAFFH8NAAIBAAQJDg5XZQAYAQABAAQJDg5XZQAYAQAuAAQKfyoAAgEACQkXFDZxAJcBAAEACQkXFDZxAJcBAAAA.',
In='Inko:BAAALgADCgYJCQABLgAFFAYJHwAOALUkAA==.Inkpot:BAAALgAECgEJAQABLgAECggJNgAMABYlAA==.Inkstain:BAAALgAECgYJDAABLgAECggJNgAMABYlAA==.Inkwell:BAABLgAECn82AAIMAAgJFiX4CAAAAwAMAAgJFiX4CAAAAwAAAA==.',
Is='Iskasta:BAAALgADCgQJBAAAAA==.Isobell:BAAALgAECgcJDQAAAA==.',
Ja='Jaardrius:BAABLgAECn9EAAMVAAkJXiMZBgBFAwAVAAkJXiMZBgBFAwAIAAMJjgu3XgCVAAAAAA==.Jackransom:BAAALgADCgkJDgAAAA==.Jakobo:BAAALgAECgcJCwAAAA==.Jal:BAAALgADCgMJAwAAAA==.Jalapenoheat:BAAALgAECgQJAwAAAA==.Jandreyn:BAAALgADCgUJAQAAAA==.Jaskar:BAAALgAECgEJAQAAAA==.Javanna:BAAALgAECgYJCQAAAA==.',
Jd='Jdiddy:BAAALgAECgcJAQAAAA==.',
Je='Jelly:BAAALgADCgIJAgABLgAFFAgJIAAMALscAA==.',
Ji='Jimbostein:BAAALgADCgEJAQAAAA==.Jinnie:BAAALgADCgMJBgAAAA==.',
Jj='Jjb:BAAALgAECgcJCQAAAA==.',
Ju='Junebuge:BAAALgAECgQJBAAAAA==.Juniordh:BAAALgAFFAIJAgABLgAFFAYJFQAVAEceAA==.Junknthtrunk:BAAALgAECgQJBgAAAA==.',
Ka='Kaelana:BAAALgADCgEJAQAAAA==.Kalculated:BAAALgAFFAIJAwAAAA==.Kamahl:BAAALgAFFAEJAQAAAA==.Karl:BAAALgADCgUJBQAAAA==.Katôs:BAAALgADCgkJCQAAAA==.',
Kd='Kda:BAAALgAECgYJBgABLgAECgcJFQAbAIYjAA==.',
Ke='Keanew:BAABLgAECn8xAAQPAAkJNh6KCgC5AQAPAAgJ1hSKCgC5AQAXAAkJqRzdGgCoAQAYAAMJNgPK9gBWAAAAAA==.Kebap:BAAALgAECgYJBgAAAA==.Keigaa:BAABLgAECn8qAAMeAAcJTSCkIAAWAgAeAAYJcCGkIAAWAgAEAAYJNRRaqgAnAQAAAA==.Keilien:BAAALgAECgUJBwAAAA==.Kenry:BAABLgAECn8VAAINAAUJCw3LHQDRAAANAAUJCw3LHQDRAAAAAA==.Keonna:BAAALgAECgUJCwAAAA==.Keppra:BAABLgAECn8aAAIQAAYJcwYHBACQAAAQAAYJcwYHBACQAAAAAA==.Kerlin:BAACLgAFFH8SAAIMAAMJ4AHfVAByAAAMAAMJ4AHfVAByAAAuAAQKfxsAAwwACQk9DmRYAEkBAAwACAlSC2RYAEkBAAsAAQnkAnOIACcAAAAA.Keyaira:BAAALgADCgYJBwAAAA==.Keybash:BAABLgAECn8UAAMNAAYJmgVyHwB1AAAaAAYJewX1zQC3AAANAAMJagNyHwB1AAAAAA==.Keíga:BAAALgAECgMJBAAAAA==.',
Kh='Kharne:BAAALgAFFAEJAgABLgAFFAQJCwAhAM4iAA==.Khurst:BAAALgAECgcJDwAAAA==.',
Ki='Kilmithius:BAAALgAECgYJEgAAAA==.Kimchi:BAAALgAECgQJBAABLgAFFAgJIAAMALscAA==.Kimmex:BAAALgADCgcJAgAAAA==.Kinoxo:BAACLgAFFH8sAAMKAAcJdh0nDACnAQAKAAUJUiUnDACnAQAdAAYJUhO6FgAqAQAuAAQKfx0AAwoACAmRIeMaAHUCAAoACAnzHeMaAHUCAB0ABAm6HakgAOgAAAAA.Kinoxoxo:BAAALgAECgQJBwAAAA==.Kinozo:BAAALgAFFAIJAgAAAA==.Kirianis:BAABLgAECn8vAAIEAAkJDBh0NwAkAgAEAAkJDBh0NwAkAgAAAA==.Kishuko:BAAALgADCgEJAQAAAA==.',
Kl='Klesha:BAAALgADCgMJAwAAAA==.Klevens:BAAALgAECgkJBgAAAA==.',
Ko='Kongfuux:BAAALgAECgQJBAAAAA==.Kossuth:BAAALgAECgcJCAAAAA==.',
Kr='Kragge:BAAALgAECgcJCQAAAA==.Krampusnacht:BAAALgAECgYJCQAAAA==.Krissycat:BAAALgAECgUJBQAAAA==.Kryven:BAAALgADCgkJEQAAAA==.',
Ku='Kumma:BAAALgADCgEJAQAAAA==.Kushaladaora:BAAALgAECgQJCQAAAA==.',
Ky='Kybrine:BAAALgAECgYJCQAAAA==.Kynlas:BAAALgAECgQJDQAAAA==.Kyratinx:BAAALgAECgEJAwAAAA==.',
La='Lacachuda:BAAALgADCgIJAwAAAA==.Lacear:BAAALgADCgcJBwABLgAFFAYJDAAJAIYiAA==.Langris:BAAALgAECgcJCAAAAA==.Larious:BAABLgAECn9TAAIEAAkJ7x5SGQCrAgAEAAkJ7x5SGQCrAgAAAA==.',
Le='Led:BAAALgAECggJEAAAAA==.Ledikens:BAAALgAECggJDgAAAA==.Legless:BAAALgAECgYJBwABLgAECgkJEQAUAAAAAA==.Legnase:BAABLgAECn8wAAMDAAkJ6R41CADyAgADAAkJ1h41CADyAgACAAIJRRbTXQBjAAABLgAECgkJPAAQADkiAA==.Legolaslawl:BAAALgAECgQJBAABLgAFFAMJBwAKALUVAA==.Leht:BAABLgAECn8+AAMLAAkJ2RGhHADjAQALAAkJ2RGhHADjAQAMAAIJxgrXBwA9AAAAAA==.Lessgibbon:BAABLgAECn8XAAIKAAcJPh/WGgB1AgAKAAcJPh/WGgB1AgAAAA==.Lestare:BAAALgADCgYJBgAAAA==.Leviiathan:BAAALgAECgcJAwAAAA==.Lexishexis:BAAALgADCgYJBgAAAA==.',
Li='Libáh:BAAALgAECgEJAQABLgAECgkJIgAZAFkUAA==.Lighte:BAAALgADCgYJBgAAAA==.Lightspin:BAAALgAECgYJCgAAAA==.Lilgaspump:BAAALgADCgIJAQABLgAECgUJFAAHAJYQAA==.Lili:BAAALgADCgcJAgAAAA==.Lilnasty:BAABLgAECn8jAAIBAAkJSg6MaQCpAQABAAkJSg6MaQCpAQAAAA==.Lilnickel:BAAALgADCggJCAAAAA==.Lionroar:BAAALgAECgEJAQAAAA==.Livesey:BAAALgAECgYJDAAAAA==.',
Lo='Locknut:BAAALgADCgkJFwABLgAECggJFAAIAEUSAA==.Lockpie:BAAALgAECgUJBQAAAA==.Lockresh:BAAALgAECgMJAwABLgAECgcJLAAKAIQTAA==.Lokahn:BAABLgAECn8WAAIIAAYJ2RmGIwC6AQAIAAYJ2RmGIwC6AQAAAA==.Longhorndemn:BAAALgADCgQJBAABLgAFFAMJBwAKALUVAA==.Longhorndk:BAAALgAECgIJAQABLgAFFAMJBwAKALUVAA==.Longhornmage:BAAALgAECgMJAwABLgAFFAMJBwAKALUVAA==.Longhornpibe:BAACLgAFFH8HAAIKAAMJtRX3LgD1AAAKAAMJtRX3LgD1AAAuAAQKf0UAAwoACAnuGa0gAOsBAAoACAnuGa0gAOsBAB0AAwlMDg9RAJAAAAAA.Longhornroge:BAAALgAECgQJAwABLgAFFAMJBwAKALUVAA==.Longshañk:BAAALgAECgIJAwAAAA==.Loudog:BAABLgAECn81AAMRAAkJ3xOjWQC5AQARAAkJohKjWQC5AQAhAAYJ8hDwLgDoAAAAAA==.',
Lu='Lupardus:BAAALgAECgEJAQAAAA==.Luto:BAAALgAECgkJDgAAAA==.Luuko:BAAALgAECgQJBAAAAA==.',
Ly='Lynxie:BAABLgAECn8gAAIGAAgJWA8ZNABIAQAGAAgJWA8ZNABIAQAAAA==.',
['Lö']='Lökkïï:BAAALgADCgUJBQAAAA==.Lörelei:BAAALgAECgQJBAAAAA==.',
Ma='Mackenton:BAAALgAFFAEJAQABLgAFFAYJDAAJAIYiAA==.Mackerel:BAABLgAECn8YAAIHAAcJliBoEACXAgAHAAcJliBoEACXAgABLgAFFAgJJQAOAJojAA==.Madii:BAAALgAECgEJAQAAAA==.Mageresh:BAABLgAECn8VAAIBAAYJwQhY2ADmAAABAAYJwQhY2ADmAAABLgAECgcJLAAKAIQTAA==.Majinmu:BAAALgAECgYJDgAAAA==.Malinka:BAAALgAECgEJAQAAAA==.Malus:BAABLgAECn8ZAAIaAAgJLQ68YQClAQAaAAgJLQ68YQClAQAAAA==.Manders:BAAALgADCgcJAgAAAA==.Mangela:BAAALgAECgIJAwAAAA==.Mank:BAAALgAECgMJAwAAAA==.Maps:BAAALgAECgYJDQAAAA==.Masher:BAAALgAECgQJBAAAAA==.Mattydruid:BAAALgAFFAEJAQAAAA==.Maverage:BAAALgADCgMJBQAAAA==.Mavramune:BAACLgAFFH8KAAITAAUJ2Qg1XgDoAAATAAUJ2Qg1XgDoAAAuAAQKfyYAAxMACAlDF9tmAHYBABMABwniGdtmAHYBAAUACAmzDCchAKgAAAAA.Mayge:BAABLgAECn8rAAIBAAkJKxsXMwBMAgABAAkJKxsXMwBMAgAAAA==.Mañali:BAAALgADCgYJBgAAAA==.',
Mc='Mcfürry:BAABLgAECn8YAAIMAAcJyBtBMwDRAQAMAAcJyBtBMwDRAQAAAA==.',
Me='Mebedir:BAAALgAECgMJBQAAAA==.Meekal:BAAALgADCgEJAQAAAA==.Meggatron:BAAALgAECggJDgABLgAECgkJKQAjAPIeAA==.Melithia:BAAALgAECgcJEQAAAA==.Mels:BAAALgAECgQJBgAAAA==.Mendinna:BAABLgAECn89AAIXAAgJKxR7GwCiAQAXAAgJKxR7GwCiAQAAAA==.Mephidrossa:BAAALgAECggJCAABLgAFFAMJBQAIALQRAA==.Mercs:BAAALgADCgQJBQABLgAECgUJFAAHAJYQAA==.Methir:BAAALgAECgQJBQABLgAFFAQJBQAUAAAAAA==.',
Mi='Miffed:BAAALgAFFAIJAgABLgAFFAgJIAAiAM8NAA==.Mildew:BAAALgADCgYJBgAAAA==.Mincksie:BAABLgAECn8YAAMEAAgJpAujBwC8AAAEAAcJZAyjBwC8AAAiAAEJJgepUwApAAAAAA==.Mininetty:BAAALgADCgcJBwABLgAECgYJCAAUAAAAAA==.Mirage:BAABLgAECn8VAAIbAAcJhiMPFwBSAgAbAAcJhiMPFwBSAgAAAA==.Misfired:BAAALgADCgIJAgAAAA==.Mistbot:BAACLgAFFH8FAAMIAAMJtBGRMQB9AAAIAAIJ1haRMQB9AAAVAAIJxwnCTgBrAAAuAAQKfz0ABAgACQlkIVIGAOcCAAgACQlkIVIGAOcCAAcAAwnCH5U5ABYBABUAAQmyIoCaAGMAAAAA.',
Mo='Montebrew:BAAALgAECgYJBgAAAA==.Monysha:BAAALgAECgYJDQAAAA==.Mooferrigno:BAAALgAFFAMJBAABLgAFFAMJBwAQAMAWAA==.Mooky:BAABLgAECn8oAAILAAkJ9Q8wJACpAQALAAkJ9Q8wJACpAQAAAA==.Moovitz:BAAALgADCgYJDwAAAA==.Mopeia:BAABLgAECn8iAAMMAAYJghfkPwCSAQAMAAYJghfkPwCSAQAfAAUJOQ4ZPgCuAAABLgAECgYJEwAUAAAAAA==.Mord:BAAALgAECgUJDAAAAA==.Mork:BAAALgADCgMJAwABLgAECgcJLgARAD4iAA==.Mortemore:BAACLgAFFH8TAAIYAAYJwxVYNABTAQAYAAYJwxVYNABTAQAuAAQKfycAAhgACQkSIK8bAG4CABgACQkSIK8bAG4CAAAA.Mortlee:BAAALgAECgEJAQABLgAFFAYJEwAYAMMVAA==.Motet:BAAALgAECgYJCwAAAA==.Motoxman:BAAALgADCgEJAQAAAA==.',
Mu='Muikkie:BAAALgAECgEJAgAAAA==.Mulro:BAAALgADCgMJAwAAAA==.Muncher:BAAALgAECgkJEgAAAA==.',
My='Mymage:BAAALgADCgEJAQAAAA==.Mynoghra:BAAALgAECgYJEgAAAA==.Mynxx:BAAALgAECgcJCQAAAA==.Mystrax:BAAALgADCgIJAgAAAA==.',
Na='Nadoral:BAAALgADCgYJCwAAAA==.Nalka:BAAALgAECgMJAwAAAA==.Naproxen:BAABLgAECn9CAAIgAAkJySAOAwAMAwAgAAkJySAOAwAMAwAAAA==.Naraku:BAACLgAFFH8dAAQaAAYJQxmMKQCgAQAaAAYJghiMKQCgAQAZAAEJFhKxFABVAAANAAEJ6RS9IQBPAAAuAAQKfzUAAxoACAnhI5gVAKMCABoACAlcI5gVAKMCABkABglbHugNAOcBAAAA.Narberal:BAAALgADCgEJAQAAAA==.Nastager:BAAALgADCgcJBwAAAA==.Naxx:BAAALgADCgIJAgAAAA==.Nazgül:BAAALgADCgMJAgAAAA==.',
Ne='Necratog:BAAALgADCgEJAQAAAA==.Necroseeker:BAAALgAECgYJCwAAAA==.Negativity:BAAALgAFFAIJAgAAAA==.Nerkidz:BAAALgAECgEJAQAAAA==.Nes:BAAALgAECggJCwABLgAECgkJJQADAC0aAA==.Nettie:BAAALgAECgUJCAABLgAECgYJCAAUAAAAAA==.Netty:BAAALgAECgYJCAAAAA==.',
Ni='Nightshaulea:BAAALgAECgcJCwAAAA==.Niklaus:BAACLgAFFH8KAAIEAAQJcws+ZADmAAAEAAQJcws+ZADmAAAuAAQKfx4AAgQABwl2FlVoAK8BAAQABwl2FlVoAK8BAAAA.Nilisha:BAAALgADCgIJAgAAAA==.Nimi:BAAALgAECgEJAQAAAA==.Nirala:BAAALgADCgkJCQAAAA==.',
No='Nocticula:BAAALgADCgEJAQAAAA==.Nosferatmoo:BAAALgADCgkJCQABLgADCgkJEwAUAAAAAA==.',
Nu='Nusy:BAAALgAECgQJBAAAAA==.',
Ny='Nymeera:BAABLgAECn9BAAMfAAkJDghZLwDvAAAfAAkJDghZLwDvAAAcAAIJMgMbTABBAAAAAA==.Nymphetamine:BAABLgAECn9DAAMCAAkJLxq6DwBtAgACAAkJLxq6DwBtAgADAAQJ/AaKWQCZAAAAAA==.Nyxarya:BAAALgADCgcJBwAAAA==.',
Nz='Nzoth:BAABLgAECn8gAAIGAAkJGRAeKgCBAQAGAAkJGRAeKgCBAQAAAA==.',
Ob='Obnixilis:BAABLgAECn8WAAIRAAYJHxngbgCrAQARAAYJHxngbgCrAQABLgAECggJFQAHAO8aAA==.',
Od='Odessa:BAAALgAECgEJAQAAAA==.',
Ok='Okin:BAAALgAECgMJAwAAAA==.',
Om='Omadruid:BAAALgADCgYJBgAAAA==.Omapriest:BAAALgADCgUJBQAAAA==.Omashamwow:BAAALgAECgQJBQAAAA==.Omen:BAAALgAECgMJAwAAAA==.Omorc:BAABLgAECn82AAIFAAkJExgQBgA5AgAFAAkJExgQBgA5AgAAAA==.',
On='Oneyeli:BAAALgADCgYJBgAAAA==.Onikuma:BAAALgAECgQJBAAAAA==.Oniony:BAAALgADCgYJCwAAAA==.Onli:BAAALgAECgcJEgAAAA==.Onos:BAAALgAECgMJAwAAAA==.',
Or='Ordlok:BAAALgADCgcJCQAAAA==.Oresh:BAABLgAECn8sAAIKAAcJhBMrAgAJAQAKAAcJhBMrAgAJAQAAAA==.Orla:BAAALgAECgEJAQABLgAECggJHQAYAEocAA==.Orlaith:BAAALgAECgcJCgABLgAECggJHQAYAEocAA==.',
Ou='Ouinur:BAAALgAECgEJAQABLgAECgkJIQAHAC4ZAA==.',
Ow='Owenwilson:BAAALgAECgUJBwAAAA==.Owful:BAAALgAECgcJDQAAAA==.',
Pa='Pandaloca:BAAALgAECgUJBQAAAA==.Pandaloco:BAAALgADCgcJBwAAAA==.Pandalôc:BAAALgAECgIJAgAAAA==.Pandoe:BAABLgAECn8VAAQfAAgJbxfzEwC4AQAfAAYJaB/zEwC4AQALAAgJrA6nMACDAQAMAAEJngeR3AAmAAAAAA==.Papaya:BAACLgAFFH8gAAIMAAgJuxyaAQD+AQAMAAgJuxyaAQD+AQAuAAQKfyIAAwwACQnZIcMGAB8DAAwACQnZIcMGAB8DAAsABwliIZYjAOABAAAA.Paralasys:BAAALgADCgYJBgAAAA==.Pawpawpiddle:BAAALgAECgYJBgAAAA==.',
Pe='Penelopea:BAABLgAECn8pAAIBAAkJeRUxQQAZAgABAAkJeRUxQQAZAgAAAA==.Perlen:BAAALgADCgYJBgAAAA==.Perun:BAAALgAECgcJEAAAAA==.',
Ph='Phaith:BAAALgADCgUJCwABLgAECgcJCwAUAAAAAA==.Phaithfully:BAAALgAECgcJCwAAAA==.Phaithfulnes:BAAALgAECgUJCAABLgAECgcJCwAUAAAAAA==.Phenomenal:BAAALgAECgEJAQABLgAECgkJOwAQAJkfAA==.',
Pl='Plaguedealer:BAAALgADCgUJBQAAAA==.',
Pn='Pneumonya:BAAALgAECgcJBwAAAA==.',
Po='Porteagarder:BAABLgAECn86AAMJAAkJaBDLUgBoAQAJAAgJFQ7LUgBoAQAQAAIJSQNevgAfAAAAAA==.Potatodruid:BAAALgAECgQJDQAAAA==.Power:BAAALgADCgYJBgAAAA==.',
Pr='Preparedpie:BAABLgAECn8SAAIYAAgJcxlLNgDtAQAYAAgJcxlLNgDtAQAAAA==.Preront:BAACLgAFFH8/AAMjAAkJ8iUPAABtAwAjAAkJ8SUPAABtAwAQAAgJBxvKCgD/AQAuAAQKfyIABCMACQngJikAAOYDACMACQngJikAAOYDABAAAwksJq4+AFABAAkAAwkVG1J9AOgAAAAA.Priestbrume:BAAALgAECgYJDAAAAA==.Pringler:BAAALgAECgYJCAABLgAFFAgJJQAOAJojAA==.Producktive:BAABLgAECn8bAAIiAAgJMxXCEAC6AQAiAAgJMxXCEAC6AQAAAA==.Prometeus:BAAALgAECgUJBQAAAA==.Pros:BAABLgAECn8iAAIZAAkJWRRZDQDvAQAZAAkJWRRZDQDvAQAAAA==.Pruulia:BAAALgAECgMJAwABLgAECgkJPgALANkRAA==.Príestly:BAAALgAECgYJCwAAAA==.',
Ps='Psydúck:BAAALgADCgcJDQAAAA==.',
Pu='Puffdamagic:BAABLgAECn8aAAImAAgJ1hskGQANAgAmAAgJ1hskGQANAgABLgAFFAYJEwAYAMMVAA==.Puffthemagic:BAABLgAECn8WAAIlAAkJoQyTCQCOAQAlAAkJoQyTCQCOAQAAAA==.Purentity:BAAALgAECgYJCwAAAA==.',
Py='Pyatt:BAABLgAECn8vAAINAAkJbx1NBABcAgANAAkJbx1NBABcAgAAAA==.',
['Pú']='Púff:BAAALgAECgQJBwAAAA==.',
Qu='Quack:BAAALgAECggJEQAAAA==.Quackadin:BAAALgADCgYJCwABLgAECggJEQAUAAAAAA==.Quackula:BAAALgAECgcJBgAAAA==.Quilae:BAABLgAECn8dAAICAAgJQgm9NAAyAQACAAgJQgm9NAAyAQABLgAECgkJOgAJAGgQAA==.Quiny:BAAALgADCgMJAQAAAA==.',
Ra='Raerlynn:BAEALgADCgMJAwAAAA==.Ragnix:BAAALgAECgEJAQAAAA==.Randivh:BAAALgAECgIJAgAAAA==.Rassputin:BAABLgAECn8pAAIBAAkJnhfmOwAqAgABAAkJnhfmOwAqAgAAAA==.Raulioo:BAAALgAECgUJCgAAAA==.Ravnmoon:BAAALgAECgUJBQAAAA==.Raye:BAAALgADCgYJBgAAAA==.Razzleyi:BAAALgAECgUJBQAAAA==.',
Re='Realmack:BAAALgAECggJDAABLgAFFAYJDAAJAIYiAA==.Rebuke:BAAALgAECgYJBgAAAA==.Reclaimblade:BAAALgADCgUJBQAAAA==.Reclaimdrunk:BAAALgAECgIJAgAAAA==.Reclaimergun:BAAALgADCgEJAQAAAA==.Reclaimholy:BAAALgADCgUJBQAAAA==.Reclaimsage:BAAALgADCgYJBQAAAA==.Reffy:BAAALgAECgkJBgAAAA==.Reigwend:BAAALgADCggJDwAAAA==.Reisharra:BAAALgAECgUJCgAAAA==.Relimas:BAAALgADCgcJEAAAAA==.Remish:BAAALgAECgUJBQAAAA==.Rendezvous:BAAALgAECgEJBwAAAA==.Renkà:BAABLgAFFH8MAAMQAAQJig1EKgDsAAAQAAQJig1EKgDsAAAJAAQJ5QFQWQCbAAAAAA==.Requestor:BAAALgAECgUJCgABLgAECggJFQAHAO8aAA==.Resmondo:BAAALgADCgQJBAAAAA==.Ret:BAACLgAFFH8UAAIEAAUJlQxyVwABAQAEAAUJlQxyVwABAQAuAAQKfysAAgQACAkhG4suAGkCAAQACAkhG4suAGkCAAAA.Revaerlous:BAABLgAECn8uAAIRAAkJix0oLACIAgARAAkJix0oLACIAgAAAA==.',
Rh='Rheas:BAAALgADCgYJDQABLgAECggJEwAUAAAAAA==.Rhei:BAABLgAECn8RAAIYAAgJIBkbLgBEAgAYAAgJIBkbLgBEAgAAAA==.',
Ri='Ribeye:BAACLgAFFH8gAAIiAAgJzw1AAgCjAQAiAAgJzw1AAgCjAQAuAAQKfykAAiIACQlPFr4SAJwBACIACQlPFr4SAJwBAAAA.',
Ro='Roereker:BAABLgAECn9BAAIEAAkJcRrCJwBkAgAEAAkJcRrCJwBkAgAAAA==.Roguesamurai:BAAALgADCgEJAQAAAA==.Rohhenge:BAAALgAECgUJBAAAAA==.Roketraccoon:BAAALgAECgQJDwAAAA==.Romoxodus:BAAALgADCgUJCQAAAA==.Rongbip:BAABLgAECn8gAAIgAAkJ2hpjDgBDAgAgAAkJ2hpjDgBDAgAAAA==.Roshamandes:BAABLgAECn8qAAIPAAkJzCCFAgDUAgAPAAkJzCCFAgDUAgAAAA==.Rotigus:BAAALgADCgUJBQAAAA==.',
Ru='Rubadubdubz:BAAALgADCgMJAwAAAA==.Runep:BAABLgAECn8rAAIEAAkJbyADGACzAgAEAAkJbyADGACzAgAAAA==.',
Ry='Rysera:BAAALgAECgYJBgAAAA==.Ryusei:BAAALgAECgcJBwABLgAECgkJPAAQADkiAA==.Ryù:BAAALgADCgUJBQAAAA==.',
['Rè']='Rèi:BAAALgAECgIJCwABLgAECgkJJwATAMkiAA==.',
['Ré']='Réstofarian:BAACLgAFFH8UAAIMAAQJIB64IgBDAQAMAAQJIB64IgBDAQAuAAQKfy0AAwwACQm0I1sCAHYDAAwACQm0I1sCAHYDAAsAAgkoGexmAIYAAAAA.',
Sa='Sabbier:BAAALgADCgcJBwAAAA==.Sacredchikín:BAABLgAECn8eAAIaAAgJPxwAMAAYAgAaAAgJPxwAMAAYAgAAAA==.Saiki:BAAALgAECgUJDQAAAA==.Samuel:BAAALgAECgQJBwAAAA==.Sanataanna:BAAALgADCgUJCwABLgAECggJEwAUAAAAAA==.Sandvichus:BAABLgAECn8nAAILAAkJmyLJBQD8AgALAAkJmyLJBQD8AgAAAA==.Sanitarìum:BAAALgAECgQJCAAAAA==.Sardine:BAAALgAECgcJDgABLgAFFAgJIAAMALscAA==.Sasukie:BAAALgAECgEJBQAAAA==.Savagesmonk:BAAALgAECgUJBgAAAA==.Saxa:BAACLgAFFH8RAAIXAAQJ5SQVBgCpAQAXAAQJ5SQVBgCpAQAuAAQKfzEAAhcACQnnJIYFAOgCABcACQnnJIYFAOgCAAAA.',
Sc='Scratchnsnif:BAAALgADCgUJBQAAAA==.',
Se='Seers:BAAALgAECgMJAwABLgAFFAYJDAAJAIYiAA==.Sefik:BAAALgAECgYJEQAAAA==.Selaana:BAABLgAECn8YAAIQAAYJPh9nIgD8AQAQAAYJPh9nIgD8AQAAAA==.Serkis:BAAALgAECgcJBQAAAA==.Seyekobrew:BAAALgAECgMJAwAAAA==.Seyekosis:BAABLgAECn8bAAIYAAgJMhyCIwBCAgAYAAgJMhyCIwBCAgAAAA==.',
Sg='Sgathaich:BAEBLgAECn8rAAIeAAgJVBpIHAAhAgAeAAgJVBpIHAAhAgABLgAECgkJGwAMAGIZAA==.',
Sh='Shaan:BAAALgADCgMJAwAAAA==.Shadtae:BAAALgAECgYJCgABLgAECgkJLAAJAKgXAA==.Shaio:BAABLgAECn8VAAIIAAYJ3Q9hNgBGAQAIAAYJ3Q9hNgBGAQAAAA==.Shallistiah:BAAALgAECgYJBgABLgAECgkJRAAVAF4jAA==.Shamadin:BAAALgADCgkJCQAAAA==.Shambrume:BAAALgAECgYJDgAAAA==.Shambulence:BAACLgAFFH8QAAIJAAQJew6VQwDZAAAJAAQJew6VQwDZAAAuAAQKfxoAAwkACQm/FTgiAEICAAkACQm/FTgiAEICACMAAwnRESgoALUAAAAA.Shammlock:BAACLgAFFH8VAAQNAAYJgBCuCADuAAANAAUJRROuCADuAAAaAAMJYxHPfADKAAAZAAIJxwLVKQA/AAAuAAQKfygABA0ACQmCHuECAIMCAA0ACAkTH+ECAIMCABoACQnDGS0qAGcCABkABQl6EFskADgBAAAA.Shampriest:BAAALgAECggJCAAAAA==.Shamuel:BAACLgAFFH8JAAIgAAcJgRMHBADbAQAgAAcJgRMHBADbAQAuAAQKfxcAAiAACQlqE5oSABMCACAACQlqE5oSABMCAAAA.Shaylis:BAABLgAECn8UAAITAAcJxxmMRADUAQATAAcJxxmMRADUAQABLgAFFAQJDAAQAIoNAA==.Shazamm:BAAALgAECgEJAQAAAA==.Sheji:BAAALgADCgkJHAAAAA==.Shiggy:BAAALgAECgUJCgABLgAFFAUJBwAKAJ8SAA==.Shobadon:BAAALgAECggJEAAAAA==.Shobarella:BAAALgAECgkJCQAAAA==.Shole:BAABLgAECn81AAMQAAkJGh4gFABKAgAQAAkJGh4gFABKAgAJAAcJFBywKwALAgAAAA==.Shpoople:BAAALgAECgMJBAABLgAECgcJCQAUAAAAAA==.Shulanii:BAAALgAECgMJBQAAAA==.',
Si='Siatral:BAABLgAFFH8GAAMWAAQJ/wo0AgDjAAAWAAQJ/wo0AgDjAAAmAAIJKQWqWQBpAAABLgAFFAYJFQAVAEceAA==.Siggopotomus:BAAALgADCgUJBQABLgAECggJEwAUAAAAAA==.Sigvalden:BAAALgAECggJEwAAAA==.Sigvolden:BAAALgAECgcJAgABLgAECggJEwAUAAAAAA==.Silchar:BAAALgAECgMJBgAAAA==.Silicon:BAABLgAECn8hAAIBAAkJjhJPZgCxAQABAAkJjhJPZgCxAQAAAA==.Simp:BAAALgAECgEJAQABLgAECgcJAQAUAAAAAA==.Sinfulangel:BAABLgAECn85AAMRAAkJ/RxIKABgAgARAAkJ+BtIKABgAgAhAAkJbhS+EQDxAQAAAA==.Siona:BAABLgAECn9IAAITAAkJZg2nUACwAQATAAkJZg2nUACwAQAAAA==.',
Sk='Skadie:BAABLgAECn8qAAMTAAkJNBW0JgAfAgATAAkJNBW0JgAfAgAFAAEJ+QM/QwAkAAAAAA==.Skialin:BAAALgAECgQJBQAAAA==.Skiye:BAAALgAECgEJAQAAAA==.Skwii:BAAALgAFFAEJAQABLgAFFAYJDAAJAIYiAA==.Skwill:BAABLgAFFH8HAAIWAAUJZArtAQAFAQAWAAUJZArtAQAFAQABLgAFFAYJDAAJAIYiAA==.Skwip:BAABLgAFFH8MAAIJAAYJhiI7BwBTAgAJAAYJhiI7BwBTAgAAAA==.Skwop:BAAALgAECgEJAgABLgAFFAYJDAAJAIYiAA==.Skyelar:BAAALgAECgcJBgAAAA==.Skyler:BAABLgAECn8UAAInAAcJER39AgAzAgAnAAcJER39AgAzAgAAAA==.',
Sl='Slackness:BAAALgAECgMJCAAAAA==.Slavalous:BAAALgAECgcJDAAAAA==.',
Sn='Snakeshifter:BAAALgADCgUJBQAAAA==.Snakesoul:BAAALgAECgMJBAAAAA==.Snivels:BAABLgAECn8hAAIfAAkJbRGqKwACAQAfAAkJbRGqKwACAQAAAA==.Snnorri:BAAALgADCggJFgABLgAECgkJRAAVAF4jAA==.',
So='Sodtaoe:BAAALgADCgcJDQAAAA==.Soil:BAAALgAECgMJAwAAAA==.Solsilvesti:BAAALgADCgMJAwAAAA==.Souly:BAAALgAECgcJBwAAAA==.',
Sp='Sparrkle:BAABLgAECn8uAAIZAAkJ1w2SDQBjAQAZAAkJ1w2SDQBjAQAAAA==.Spin:BAAALgADCgMJAwAAAA==.Spinecrawler:BAABLgAFFH8FAAIaAAMJewxyfwDFAAAaAAMJewxyfwDFAAAAAA==.Spinjitzu:BAAALgAECgQJCwAAAA==.Spiritshift:BAAALgAECgEJAQAAAA==.Spyro:BAAALgAECgQJEQAAAA==.',
Sq='Squadw:BAACLgAFFH8hAAIXAAcJoxo2AwALAgAXAAcJoxo2AwALAgAuAAQKf0YAAhcACQkCJTkCAHMDABcACQkCJTkCAHMDAAAA.',
Ss='Sski:BAAALgADCgEJAQAAAA==.',
St='Starblast:BAAALgAECgYJEwABLgAECgYJBwAUAAAAAA==.Starrskrream:BAAALgAECgQJBgAAAA==.Staryknight:BAAALgAECgEJAQAAAA==.Steamworks:BAAALgADCgcJBwAAAA==.Steelrat:BAAALgADCgcJAgAAAA==.Stellanova:BAAALgADCgQJBAAAAA==.Stiick:BAABLgAECn82AAIiAAkJDBoYCgAqAgAiAAkJDBoYCgAqAgAAAA==.Stormhide:BAAALgADCgEJAgAAAA==.Streakycat:BAEALgAECgEJAQAAAA==.Stupidgnome:BAAALgAECgkJCgAAAA==.Stìmpak:BAAALgAECgMJBQABLgAECgcJCAAUAAAAAA==.',
Su='Subsizzle:BAAALgAECgMJAwABLgAECgcJEgAUAAAAAA==.Subzerow:BAAALgADCgYJBgAAAA==.Sudsy:BAAALgAECggJCgAAAA==.Sujin:BAAALgAECgMJAwAAAA==.Sunarra:BAABLgAECn8dAAIYAAgJShySMgD7AQAYAAgJShySMgD7AQAAAA==.Sunsmite:BAABLgAECn8dAAIEAAcJrha5bQCiAQAEAAcJrha5bQCiAQAAAA==.Supadupaman:BAAALgAECgkJBgAAAA==.Suramar:BAABLgAECn8YAAIOAAgJAhVkGQBxAQAOAAgJAhVkGQBxAQAAAA==.',
Sw='Sweetbippy:BAABLgAECn9BAAIBAAkJ5ASRCACvAAABAAkJ5ASRCACvAAAAAA==.Swifthealss:BAABLgAECn8lAAQfAAkJMQ/JHABnAQAfAAkJTA7JHABnAQAMAAgJjQYkaQD5AAALAAUJ3grmWwClAAAAAA==.Swirls:BAAALgAECgEJAgAAAA==.',
Sy='Sygvalden:BAAALgAECgYJDAABLgAECggJEwAUAAAAAA==.Sylunae:BAAALgAECgYJEAABLgAECgkJOgAJAGgQAA==.Syluné:BAABLgAECn8tAAIMAAkJvwwyQgCIAQAMAAkJvwwyQgCIAQABLgAECgkJOgAJAGgQAA==.Syläs:BAAALgAECgYJEwAAAA==.Syndrassil:BAABLgAECn88AAIBAAkJJBHvBAAMAQABAAkJJBHvBAAMAQAAAA==.',
['Sù']='Sùccubus:BAAALgADCgQJBAAAAA==.',
['Sý']='Sýd:BAAALgAECgMJAwAAAA==.',
Ta='Tacodog:BAAALgAECgUJCgABLgAFFAIJBgAEABQdAA==.Tacomonk:BAAALgAECggJCgAAAA==.Tacopally:BAAALgAECgcJCwABLgAECggJCgAUAAAAAA==.Tacozpriest:BAAALgAECgYJBgABLgAECggJCgAUAAAAAA==.Taelight:BAAALgADCggJDgABLgAECgkJLAAJAKgXAA==.Taelyx:BAABLgAECn8sAAMJAAkJqBdJOQDKAQAJAAkJqBdJOQDKAQAQAAIJ3gkQfgBOAAAAAA==.Taepain:BAAALgAECgIJAgABLgAECgkJLAAJAKgXAA==.Taicheeze:BAABLgAECn8hAAIHAAkJLhnjDwA/AgAHAAkJLhnjDwA/AgAAAA==.Tambot:BAAALgAECgQJDQAAAA==.Tanialeal:BAAALgAECgQJBAABLgAECggJMgARAE4cAA==.Taravangian:BAAALgAECgMJAwABLgAFFAMJBwAKALUVAA==.Tariced:BAAALgAECgUJCgAAAA==.Tarvaron:BAAALgADCgEJAQAAAA==.Taytra:BAAALgAECgQJBAABLgAECgkJQQABAOQEAA==.Tazmina:BAACLgAFFH8OAAIXAAMJ9R+wEQAWAQAXAAMJ9R+wEQAWAQAuAAQKfzkAAhcACQnqIooDAB0DABcACQnqIooDAB0DAAAA.',
Te='Teal:BAAALgADCgYJCgAAAA==.Teenieweenie:BAAALgAECgEJAQAAAA==.Tehssa:BAAALgAECgUJBgABLgAECgkJPAAQAEseAA==.Tenzen:BAAALgAECgYJCAAAAA==.Tessa:BAABLgAECn88AAIQAAkJSx7zCwCkAgAQAAkJSx7zCwCkAgAAAA==.Texasfight:BAAALgAECgEJAQABLgAFFAMJBwAKALUVAA==.Teyo:BAAALgAECgcJEQAAAA==.',
Th='Thedoctorwho:BAABLgAECn8WAAIEAAkJpw8eVwDGAQAEAAkJpw8eVwDGAQAAAA==.Theholytaz:BAABLgAECn8XAAIEAAgJDBZkQQAhAgAEAAgJDBZkQQAhAgAAAA==.Theirel:BAAALgAECgUJCgAAAA==.Thunderr:BAAALgAECgcJCAAAAA==.Thörn:BAABLgAECn8VAAMJAAgJ1A1NbQAUAQAJAAcJegtNbQAUAQAQAAIJGgUGmwBCAAABLgAFFAQJEAAMAMAGAA==.',
Ti='Tigs:BAAALgADCgMJAwAAAA==.Time:BAAALgAECgYJCQAAAA==.Tinyjapeto:BAAALgAECgQJBQAAAA==.Titanbow:BAAALgADCgYJBgABLgAECgkJMAAYALAfAA==.',
To='Tomcatt:BAABLgAECn9JAAITAAkJOCO1BwAgAwATAAkJOCO1BwAgAwAAAA==.Tonshaw:BAAALgAECgYJBgAAAA==.Toome:BAAALgADCgUJBQAAAA==.Toxin:BAAALgADCgEJAQAAAA==.',
Tr='Trailis:BAAALgAECgQJBwAAAA==.Travalden:BAAALgADCgMJAwAAAA==.Trekkie:BAAALgAECgUJBQABLgAFFAgJIAAiAM8NAA==.Treè:BAAALgAECgMJCgAAAA==.Trioxinn:BAAALgADCgEJAQAAAA==.',
Tu='Tuddlly:BAAALgAECgUJCgAAAA==.Turdfergison:BAAALgADCgUJDgABLgAECgkJKgAPAMwgAA==.Turin:BAABLgAECn8vAAIOAAkJHwinHgA+AQAOAAkJHwinHgA+AQAAAA==.Turnip:BAABLgAFFH8FAAIVAAIJWgztUwBbAAAVAAIJWgztUwBbAAABLgAFFAgJIAAMALscAA==.Tutonik:BAAALgADCgUJBQAAAA==.Tuubarkk:BAAALgADCgcJCAAAAA==.',
Tw='Twilghtdawn:BAABLgAECn8rAAIhAAgJ4Bf8FgCwAQAhAAgJ4Bf8FgCwAQAAAA==.Twos:BAAALgAECgEJAQAAAA==.Twotone:BAAALgADCgMJAwAAAA==.',
Ty='Tybo:BAABLgAECn83AAIjAAkJFSO6AQAWAwAjAAkJFSO6AQAWAwAAAA==.Tybs:BAAALgADCgEJAQAAAA==.',
['Tô']='Tôliah:BAAALgAECgEJAQAAAA==.',
Un='Uncás:BAABLgAECn8VAAITAAYJIgdZeAD+AAATAAYJIgdZeAD+AAAAAA==.Ungieblinks:BAAALgAECgQJCwAAAA==.Ungislayer:BAAALgADCgMJAwAAAA==.Unglifettv:BAACLgAFFH8MAAImAAQJBBuoJQA5AQAmAAQJBBuoJQA5AQAuAAQKfxUAAiYACAkxF/AfANkBACYACAkxF/AfANkBAAAA.Unstable:BAAALgAECgQJBgABLgAECgcJCgAUAAAAAA==.',
Up='Upchucky:BAAALgAECggJDQAAAA==.',
Ur='Urulóki:BAAALgAECgcJCgAAAA==.',
Va='Vaedeath:BAABLgAECn9DAAIhAAkJJiC3CQB3AgAhAAkJJiC3CQB3AgAAAA==.Vaina:BAAALgADCgMJAwAAAA==.Vainagos:BAABLgAECn8fAAQlAAYJ3h0TCACzAQAlAAYJ3h0TCACzAQAmAAQJ5RbARgAPAQAWAAUJTxCOHQAOAQAAAA==.Valaryon:BAAALgAECgcJEwAAAA==.Valkorin:BAAALgAECgYJBwAAAA==.Valoryan:BAABLgAECn9JAAIMAAkJYRbfHQBXAgAMAAkJYRbfHQBXAgAAAA==.Valyteilssra:BAAALgAECgQJCQAAAA==.Vanaakaa:BAAALgADCgQJBAAAAA==.Vandrius:BAAALgAECgkJBgABLgABCgQJBQAUAAAAAA==.Vanity:BAAALgAECgMJBgAAAA==.Varindra:BAAALgAECgMJBAABLgAFFAYJFQAVAEceAA==.Vasoline:BAAALgAFFAEJAgAAAA==.Vayluna:BAAALgAECgMJAwAAAA==.',
Ve='Vegà:BAABLgAECn8oAAIHAAkJ+BG/HAC/AQAHAAkJ+BG/HAC/AQAAAA==.Veina:BAAALgADCgQJCAAAAA==.Velyndris:BAAALgAECgYJCwAAAA==.Velysia:BAAALgADCgMJAwAAAA==.Vendettis:BAAALgAECgYJDwAAAA==.Verin:BAAALgAECgMJBgAAAA==.Vetraugr:BAAALgADCgMJAwABLgAECgYJDQAUAAAAAA==.Vextaerin:BAAALgAECgYJDQAAAA==.Vextarin:BAAALgADCgEJAQABLgAECgYJDQAUAAAAAA==.Veylyn:BAAALgADCgEJAQAAAA==.',
Vi='Virulent:BAAALgADCgYJCgAAAA==.Vivienreed:BAAALgAECgEJAgABLgAFFAUJDQAlANQLAA==.',
Vo='Voiddemon:BAAALgAECgEJAQAAAA==.Voidhax:BAAALgAECgUJBQAAAA==.Voidi:BAABLgAECn8XAAQbAAcJVyOsFQBiAgAbAAcJtCKsFQBiAgAkAAQJESEBDQBPAQAnAAEJtAOkDwAoAAAAAA==.Voidyo:BAACLgAFFH8SAAIYAAQJIxdAQwAeAQAYAAQJIxdAQwAeAQAuAAQKfxAAAhgACAmuHiQ9ANMBABgACAmuHiQ9ANMBAAAA.Voralyth:BAAALgADCggJCQAAAA==.Voranne:BAABLgAECn87AAIGAAkJjBByAQA4AQAGAAkJjBByAQA4AQAAAA==.Vortice:BAABLgAECn9PAAQQAAkJCxVFHQD3AQAQAAkJ8hRFHQD3AQAJAAkJOw4/SwCDAQAjAAQJyQmyAgBvAAAAAA==.Vowwel:BAAALgAECgEJAQAAAA==.',
Vy='Vyserlai:BAAALgADCgUJBQAAAA==.',
Wa='War:BAAALgAECgYJBwAAAA==.Ware:BAAALgADCgcJBwAAAA==.Warraxdead:BAAALgADCgEJAQABLgAFFAIJBwAXACANAA==.Warraxgos:BAAALgADCgkJHgABLgAFFAIJBwAXACANAA==.Warraxhunt:BAAALgAECgYJCAABLgAFFAIJBwAXACANAA==.Warraxmonk:BAAALgADCgYJBgABLgAFFAIJBwAXACANAA==.Warraxrage:BAAALgADCgYJBgABLgAFFAIJBwAXACANAA==.',
We='Weißenacht:BAAALgAECgMJAwAAAA==.',
Wh='Wheatstraw:BAAALgAECgMJBgAAAA==.Whiskeyjak:BAABLgAECn8nAAMOAAkJKR0HEQDaAQAOAAUJaiIHEQDaAQAKAAgJOg9bOABlAQAAAA==.',
Wi='Willowest:BAABLgAECn9BAAITAAkJqBtgGwCBAgATAAkJqBtgGwCBAgAAAA==.',
Wr='Wrathstorm:BAABLgAECn8pAAIjAAkJ8h51BQCLAgAjAAkJ8h51BQCLAgAAAA==.Wrekonhoof:BAAALgAECgEJAQAAAA==.',
Wt='Wtfpie:BAACLgAFFH8aAAMRAAYJFxQ4GABEAQARAAYJFxQ4GABEAQASAAEJyBo9JgBMAAAuAAQKfzoAAhEACQk3I9sOAPUCABEACQk3I9sOAPUCAAAA.',
Wu='Wurmoneonine:BAAALgADCgUJBQABLgAECgkJMAAMAIYXAA==.Wurmy:BAABLgAECn8wAAMMAAkJhhfyHgBOAgAMAAkJhhfyHgBOAgALAAYJSBNiQAANAQAAAA==.',
Wy='Wyndrunner:BAAALgADCgkJCQABLgAFFAMJDAATACsGAA==.',
['Wá']='Wárgbáte:BAAALgADCgcJBwAAAA==.',
Xa='Xalgas:BAABLgAECn8YAAIGAAYJaxaVKwB/AQAGAAYJaxaVKwB/AQAAAA==.Xanier:BAAALgAECgUJDAAAAA==.Xanivus:BAAALgAECgYJCQAAAA==.',
Xe='Xelagos:BAABLgAECn8gAAQWAAkJMRFoGABMAQAWAAgJKhBoGABMAQAlAAQJ6BbBGQCFAAAmAAMJ5BWvUwB4AAAAAA==.Xerxesjr:BAAALgADCgEJAQAAAA==.',
Xi='Xioamara:BAABLgAECn8UAAQVAAcJNQ2uUgAlAQAVAAcJNQ2uUgAlAQAHAAIJawN7fwBKAAAIAAEJ5Ai/sAAlAAAAAA==.',
Xo='Xorm:BAAALgAECgkJBgAAAA==.',
Xx='Xxd:BAAALgAECgEJAQAAAA==.',
Ya='Yanella:BAABLgAECn8wAAMCAAkJ3ByGCgC+AgACAAkJ3ByGCgC+AgADAAEJcwWmWgAtAAAAAA==.',
Yi='Yispally:BAAALgAECgQJCgAAAA==.Yisshaman:BAABLgAECn8eAAIQAAkJXhvZDADQAgAQAAkJXhvZDADQAgAAAA==.',
Yo='Yo:BAABLgAFFH8IAAMfAAQJaBz9CgBDAQAfAAQJaBz9CgBDAQAcAAEJWQYqIQA2AAABLgAFFAgJJQAOAJojAA==.Yogibearz:BAAALgAECgQJBwABLgAECgUJFAAHAJYQAA==.Yogimonk:BAABLgAECn8UAAIHAAUJlhAZUADBAAAHAAUJlhAZUADBAAAAAA==.',
Za='Zanax:BAAALgAECgcJCAAAAA==.Zandarbribbs:BAABLgAECn8hAAIEAAgJRRUdYgCsAQAEAAgJRRUdYgCsAQAAAA==.Zapzug:BAAALgADCgYJDQAAAA==.Zaratras:BAAALgAECgEJAQAAAA==.Zaydozer:BAAALgAECgcJCwAAAA==.',
Ze='Zenmetsu:BAAALgAECgUJBgAAAA==.Zennya:BAABLgAECn8tAAIMAAkJPBc9HwBMAgAMAAkJPBc9HwBMAgAAAA==.Zenthora:BAAALgAECgIJAgAAAA==.Zeon:BAAALgAECgYJEQAAAA==.Zezra:BAAALgADCgEJAQAAAA==.',
Zi='Zikoth:BAAALgADCgEJAQAAAA==.Zingers:BAAALgAECgMJAwAAAA==.',
Zm='Zmd:BAAALgAECgYJEQAAAA==.',
Zo='Zoeso:BAABLgAECn83AAMHAAkJfx/uBgDIAgAHAAkJfx/uBgDIAgAVAAUJyQ6/ZADpAAAAAA==.',
Zt='Ztropos:BAAALgAECgcJBwAAAA==.',
Zu='Zucchini:BAAALgAECgYJBgAAAA==.',
Zy='Zygal:BAAALgAECgMJCAAAAA==.',
['Zè']='Zèrà:BAAALgAECgEJAQAAAA==.',
['Ço']='Çonsecration:BAAALgAECgEJAgAAAA==.',
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
