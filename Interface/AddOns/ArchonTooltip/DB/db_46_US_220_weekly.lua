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

local lookup = {'Mage-Frost','Priest-Holy','Priest-Discipline','Paladin-Retribution','Hunter-Marksmanship','Priest-Shadow','Monk-Brewmaster','Shaman-Restoration','Warrior-Fury','Druid-Balance','Druid-Restoration','Monk-Windwalker','Warlock-Affliction','DemonHunter-Vengeance','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Frost','Hunter-BeastMastery','Unknown-Unknown','Evoker-Preservation','DemonHunter-Havoc','DemonHunter-Devourer','Warlock-Destruction','Warlock-Demonology','Warrior-Protection','Rogue-Subtlety','Warrior-Arms','Paladin-Holy','Monk-Mistweaver','Druid-Feral','Druid-Guardian','Hunter-Survival','DeathKnight-Blood','Paladin-Protection','Shaman-Enhancement','Rogue-Assassination','Evoker-Devastation','Evoker-Augmentation','Rogue-Outlaw',}
local provider = {region='US',realm='Thunderhorn',name='US',type='weekly',zone=46,date='2026-05-24',data={Ab='Absynthe:BAAALgAECgYJBgAAAA==.Abysmal:BAAALgADCgYJBgABLgAECggJIAABAIoPAA==.Abÿss:BAAALgAECgMJCAAAAA==.',
Ac='Achêrøn:BAAALgADCgcJBwAAAA==.Acoghai:BAAALgADCgcJDQAAAA==.',
Ad='Adoweld:BAAALgADCgcJBQAAAA==.Adøland:BAAALgADCgYJBgAAAA==.',
Ae='Aeliis:BAABLgAECn8lAAMCAAkJ5AxVJACAAQACAAkJ5AxVJACAAQADAAMJbQSDUAB5AAAAAA==.Aellart:BAAALgAECgEJAgAAAA==.Aeriona:BAABLgAECn8mAAIEAAkJXRrTIwBXAgAEAAkJXRrTIwBXAgAAAA==.Aerosoul:BAAALgADCgEJAQAAAA==.',
Ag='Agamsi:BAABLgAECn8UAAIFAAgJcwuIFAD2AAAFAAgJcwuIFAD2AAAAAA==.',
Ai='Aine:BAABLgAECn8cAAMCAAcJ3BgUHQC6AQACAAYJ7RwUHQC6AQAGAAYJ6wA/WABcAAAAAA==.Ainek:BAAALgAECgUJBwAAAA==.Ainkor:BAAALgAECgYJBwABLgAECgkJKQAHADsWAA==.',
Aj='Ajani:BAAALgAECggJEgAAAA==.',
Ak='Akyospirit:BAABLgAECn8tAAIIAAkJZwsWPgCIAQAIAAkJZwsWPgCIAQAAAA==.Akyowindz:BAAALgADCgkJEgAAAA==.',
Al='Al:BAAALgAECgYJEAABLgAECgkJKgAJAAUcAA==.Alava:BAAALgADCgEJAQAAAA==.Aliatra:BAABLgAECn81AAMKAAkJ6hHPGQDSAQAKAAkJ6hHPGQDSAQALAAEJmgi22gAfAAAAAA==.Alinth:BAAALgAECgMJBQAAAA==.Almosthuman:BAAALgAECgYJCgAAAA==.Alpha:BAABLgAECn83AAIBAAkJoh0xFgC7AgABAAkJoh0xFgC7AgAAAA==.Alroy:BAAALgAECgkJCwAAAA==.Aluina:BAAALgAECgUJCQAAAA==.Alykia:BAAALgADCgYJBgAAAA==.',
Am='Amamonk:BAABLgAECn88AAMHAAkJ8RRjFADuAQAHAAkJQRRjFADuAQAMAAQJzBflMwANAQAAAA==.Amandara:BAAALgADCgUJBQAAAA==.Ammert:BAABLgAECn8lAAINAAkJDQ25CACpAQANAAkJDQ25CACpAQAAAA==.Amonet:BAAALgADCgYJEQAAAA==.',
An='Andou:BAAALgADCgcJBwAAAA==.Angeldracul:BAAALgADCgQJBwAAAA==.Angelove:BAAALgAECgQJDAAAAA==.Anglico:BAAALgAECgQJBQABLgAECgkJJwAOAMwgAA==.Angliko:BAAALgAECgUJBQABLgAECgkJJwAOAMwgAA==.Anglikoo:BAAALgADCggJCAABLgAECgkJJwAOAMwgAA==.Anomandaris:BAABLgAECn8cAAMPAAkJqxErKQB9AQAPAAgJshIrKQB9AQAIAAEJTAb4twArAAAAAA==.Anquan:BAABLgAECn8eAAIQAAcJQRjbXQCOAQAQAAcJQRjbXQCOAQAAAA==.',
Ap='Apedemak:BAAALgAECgYJBgAAAA==.Aphobias:BAAALgAECgUJCwAAAA==.Aphradite:BAAALgADCgYJCwAAAA==.Apothica:BAAALgADCgUJBwAAAA==.Apothicc:BAABLgAECn8aAAMQAAcJARJvbABrAQAQAAcJARJvbABrAQARAAEJAAC5NAAAAAAAAA==.Appalonio:BAAALgADCgcJBQAAAA==.Appaur:BAAALgADCgEJAQAAAA==.Appolymi:BAABLgAECn8kAAISAAgJPwT1gAARAQASAAgJPwT1gAARAQAAAA==.Apraxia:BAAALgADCgUJBQAAAA==.Aprionos:BAABLgAECn8wAAIBAAgJ3QVClwAyAQABAAgJ3QVClwAyAQAAAA==.',
Ar='Arakek:BAAALgADCgcJCAAAAA==.Arataena:BAAALgADCgkJFgAAAA==.Arceus:BAAALgAECgMJBQAAAA==.Aredhël:BAAALgADCgYJDgAAAA==.Argentavis:BAAALgAECggJEgABLgAECggJEwATAAAAAA==.Argobow:BAAALgAECgQJBgAAAA==.Argonaut:BAAALgAECgYJCgAAAA==.Aristella:BAAALgADCgMJAwAAAA==.Arkken:BAAALgAECgYJDgABLgAECgkJPAADAAMiAA==.Artee:BAAALgAECgEJAQAAAA==.Artémis:BAABLgAECn8iAAISAAgJgRCIVgB0AQASAAgJgRCIVgB0AQAAAA==.',
As='Ascender:BAAALgAECgQJBAAAAA==.Ashadox:BAAALgAECgUJBwAAAA==.Asheritâ:BAAALgADCgcJBwAAAA==.Ashvalis:BAABLgAECn8cAAIUAAcJzSPFCQCaAgAUAAcJzSPFCQCaAgAAAA==.Asillyhunter:BAAALgADCgMJAwAAAA==.Asillypally:BAABLgAECn8kAAIEAAgJeBYaXgDJAQAEAAgJeBYaXgDJAQAAAA==.Askr:BAABLgAECn8kAAMSAAgJxxATSgCYAQASAAgJlxATSgCYAQAFAAYJnwrSGwCwAAAAAA==.Asphar:BAABLgAECn8uAAMSAAkJkyWEAgBVAwASAAkJkyWEAgBVAwAFAAMJChPsJQBnAAAAAA==.Asteroth:BAAALgAECgEJAQAAAA==.',
Au='Aung:BAACLgAFFH8IAAIVAAMJjiV3CABIAQAVAAMJjiV3CABIAQAuAAQKf0kAAxUACQnfJecAAGcDABUACQnfJecAAGcDABYAAQmNBp8DASIAAAAA.Auri:BAAALgADCgkJIQAAAA==.',
Av='Avatan:BAAALgAECgMJAwABLgAECgkJLAAJANAMAA==.Avralis:BAAALgADCgMJAwABLgAECggJHQAWAEocAA==.',
Ax='Axex:BAAALgAECggJCgAAAA==.',
Az='Azamii:BAABLgAECn86AAMPAAkJqSHCBAD8AgAPAAkJqSHCBAD8AgAIAAYJQRgUOwCVAQAAAA==.Azarion:BAABLgAECn84AAMXAAgJch3LCACTAQAXAAcJnRvLCACTAQAYAAYJlBn2VACJAQAAAA==.Azill:BAACLgAFFH8QAAIMAAUJcBpcBABQAQAMAAUJcBpcBABQAQAuAAQKfyYAAgwACAleHjMKANUCAAwACAleHjMKANUCAAAA.Azzrael:BAABLgAECn8qAAIZAAkJzBDSFADAAQAZAAkJzBDSFADAAQAAAA==.',
Ba='Baalalmerat:BAAALgAECgIJAgAAAA==.Bandi:BAAALgAECgYJDQAAAA==.Bartrak:BAABLgAECn8YAAMGAAkJPxNLHAC+AQAGAAkJPxNLHAC+AQADAAMJ0g4nQwCcAAAAAA==.',
Be='Bearrific:BAABLgAECn8iAAIaAAkJ/hlQDQAuAgAaAAkJ/hlQDQAuAgAAAA==.Beawulf:BAAALgADCgkJLAAAAA==.Belista:BAAALgADCgkJNAAAAA==.Bethel:BAAALgADCgYJCAAAAA==.',
Bf='Bfresh:BAAALgADCgcJBwAAAA==.',
Bi='Billie:BAAALgADCgcJAgAAAA==.Billthekid:BAAALgAECgYJCwAAAA==.Billybobb:BAAALgAECgYJDgAAAA==.Biney:BAAALgAECgQJBAABLgAECgQJBQATAAAAAA==.Binksy:BAACLgAFFH8RAAIJAAUJSxQ1GwAkAQAJAAUJSxQ1GwAkAQAuAAQKfykAAgkACQmLHMkNAOcCAAkACQmLHMkNAOcCAAAA.Biscuit:BAACLgAFFH8lAAIZAAgJmiN3AADJAgAZAAgJmiN3AADJAgAuAAQKfyIAAhkACQkfJe4AAJYDABkACQkfJe4AAJYDAAAA.Bitcoìn:BAAALgAECgEJAgAAAA==.',
Bl='Blaam:BAAALgAECgQJCwAAAA==.Blazin:BAACLgAFFH8XAAIBAAUJvRYQQQBFAQABAAUJvRYQQQBFAQAuAAQKfywAAgEACQmLHvAOAO0CAAEACQmLHvAOAO0CAAAA.Blep:BAAALgAECgYJCgAAAA==.Blgunc:BAAALgAECggJDwAAAA==.Blinkzy:BAAALgAECgUJCQAAAA==.Bloui:BAAALgAECgQJCAAAAA==.Bluesummers:BAAALgADCgkJCQAAAA==.',
Bo='Boba:BAAALgAECgYJBgABLgAFFAgJJQAZAJojAA==.Bongrips:BAAALgADCgIJAgAAAA==.Boomboom:BAAALgAECgIJAwAAAA==.Borlok:BAAALgAFFAQJBQAAAQ==.',
Br='Brannigan:BAABLgAECn8tAAIZAAkJ+iG2AgD+AgAZAAkJ+iG2AgD+AgAAAA==.Braulioo:BAAALgAECgEJAgAAAA==.Breebbs:BAAALgAECgUJBQAAAA==.Briantu:BAABLgAECn8hAAIIAAgJ9gEJcADWAAAIAAgJ9gEJcADWAAAAAA==.Brickitphil:BAAALgAECgYJDgAAAA==.Briiz:BAAALgADCgkJDAAAAA==.Brlolock:BAAALgADCgkJJAAAAA==.Brollo:BAAALgADCgEJAQAAAA==.Brud:BAAALgADCgYJAwAAAA==.Brönwyn:BAAALgAECgMJCAAAAA==.',
Bu='Bubblegumdrp:BAAALgAECgMJAwAAAA==.Bubblicious:BAAALgADCgUJCQAAAA==.Buckets:BAAALgAECgcJEgABLgAECggJCgATAAAAAA==.Budi:BAAALgADCgcJCAAAAA==.Bulldan:BAABLgAECn8hAAINAAgJBx4hBAAwAgANAAgJBx4hBAAwAgAAAA==.Bullvi:BAAALgAECgYJBgAAAA==.',
['Bä']='Bärkler:BAABLgAECn8cAAMbAAkJaSKPAwDPAgAbAAkJaSKPAwDPAgAZAAEJHBgAQwBCAAAAAA==.',
['Bé']='Béckley:BAAALgAECggJEgAAAA==.Béckléy:BAAALgAECgUJDQABLgAECggJEgATAAAAAA==.',
Ca='Caatha:BAAALgADCgkJKwAAAA==.Caleanone:BAAALgAECgcJCwABLgAECgkJKgAJAAUcAA==.Calel:BAAALgAECgkJEAAAAA==.Callox:BAABLgAECn8qAAQJAAgJBRxYJACwAQAJAAgJZRlYJACwAQAbAAUJJxvtEQCCAQAZAAYJZQyNJwDQAAAAAA==.Cantelope:BAAALgADCgYJBgAAAA==.Capslock:BAAALgAECgQJAwAAAA==.Cara:BAAALgADCgIJAgAAAA==.Carahail:BAACLgAFFH8GAAMLAAMJCw9rUABkAAALAAIJhAVrUABkAAAKAAEJ6wG/QQAuAAAuAAQKfycAAwsACAnnFPooAOwBAAsACAnnFPooAOwBAAoABAk3CxJYAIMAAAAA.Catriona:BAABLgAECn8bAAISAAgJEAsKaABIAQASAAgJEAsKaABIAQAAAA==.Cazmeer:BAAALgAECgYJCQAAAA==.',
Ce='Celés:BAAALgAECgUJBQAAAA==.',
Ch='Charcuterie:BAACLgAFFH8mAAIHAAgJPh0RAQCNAgAHAAgJPh0RAQCNAgAuAAQKfyAAAwcACQnYIVwJAPMCAAcACQnYIVwJAPMCAAwAAQlxHchsAFIAAAAA.Chaír:BAAALgAECgEJBQAAAA==.Cheezeburg:BAAALgADCgEJAQABLgAECgkJHQAHAIMXAA==.Cheezus:BAAALgAECgIJAwABLgAECgkJHQAHAIMXAA==.Cherrbeår:BAAALgADCgcJBwAAAA==.Cherudim:BAACLgAFFH8FAAMXAAMJ4wsjDwCHAAAYAAMJ4wtnZgDOAAAXAAIJrwIjDwCHAAAuAAQKfyYAAxcACAkiF44JACcCABcACAmBFY4JACcCABgACAl3FFNJAKoBAAAA.Chillainkor:BAABLgAECn8pAAIHAAkJOxbXFADqAQAHAAkJOxbXFADqAQAAAA==.Chillidán:BAABLgAECn8QAAIWAAgJ+ALqoAC4AAAWAAgJ+ALqoAC4AAAAAA==.Chippmagi:BAABLgAECn8gAAIBAAgJ9RocRwDsAQABAAgJ9RocRwDsAQAAAA==.Chippndots:BAAALgAECgYJDAABLgAECggJIAABAPUaAA==.Chirp:BAAALgAECgEJAQAAAA==.Chives:BAAALgAECgQJBAAAAA==.Choggie:BAACLgAFFH8FAAIcAAIJxRoJLACjAAAcAAIJxRoJLACjAAAuAAQKfzcAAhwACQkuHwgFACYDABwACQkuHwgFACYDAAAA.Chronocolter:BAAALgADCgMJAwAAAA==.Chronosaren:BAAALgAECgkJEwAAAA==.Chåir:BAAALgAECgEJAgAAAA==.',
Ci='Cinterax:BAAALgAECgIJAgABLgAECgkJLQAZAPohAA==.',
Cj='Cjrej:BAABLgAECn8qAAIBAAkJ6QwhVwC9AQABAAkJ6QwhVwC9AQAAAA==.',
Cl='Claytonis:BAAALgAECgEJAQAAAA==.Cloudnine:BAAALgAECgQJBAAAAA==.',
Co='Colterr:BAAALgADCgEJAQAAAA==.Cons:BAABLgAECn8rAAQDAAkJ4RaUEgAmAgADAAkJlBWUEgAmAgACAAMJ8QrYZQCWAAAGAAEJ+xLfbAA3AAAAAA==.Corellon:BAABLgAECn8qAAISAAgJ1xz1MgDnAQASAAgJ1xz1MgDnAQAAAA==.Costcohotdog:BAABLgAFFH8KAAMHAAMJLR1IGACsAAAHAAMJLR1IGACsAAAdAAEJOQBpGgAYAAABLgAFFAgJJQAZAJojAA==.Cougarclaws:BAAALgAECgUJCQAAAA==.',
Cr='Craftsman:BAAALgADCgYJBgAAAA==.Craigchrist:BAAALgAECgYJBgAAAA==.Cranee:BAABLgAECn8oAAIYAAkJtxDCPADSAQAYAAkJtxDCPADSAQAAAA==.Cranium:BAAALgAECgUJCAAAAA==.Crazytasty:BAABLgAECn8mAAISAAgJXyImFQCBAgASAAgJXyImFQCBAgAAAA==.Crumbo:BAAALgAECgYJBgAAAA==.Cryoburn:BAABLgAECn8fAAIBAAgJWB1rWAAwAgABAAgJWB1rWAAwAgAAAA==.Cryoshock:BAABLgAFFH8HAAIPAAMJwBbhJADcAAAPAAMJwBbhJADcAAAAAA==.',
Cu='Cutty:BAAALgAECgUJBgAAAA==.',
['Cø']='Cøns:BAAALgAECgUJBQAAAA==.',
Da='Daario:BAABLgAECn8TAAIWAAcJsB+pNQAhAgAWAAcJsB+pNQAhAgAAAA==.Dabare:BAAALgADCgUJAQAAAA==.Dabora:BAAALgAECgEJAQABLgAECgkJKgAeAAwfAA==.Dabßod:BAAALgAECgQJBAAAAA==.Dabûra:BAABLgAECn8qAAQeAAkJDB/3CQDzAQAeAAgJTB33CQDzAQAKAAYJTR70OQD8AAAfAAcJehDGJQDkAAAAAA==.Daenerys:BAAALgAECgIJBgAAAA==.Dahouse:BAAALgADCgQJAwAAAA==.Dahpeht:BAAALgADCgkJEwAAAA==.Damda:BAAALgADCgIJAgAAAA==.Dandypooh:BAAALgAECgYJBgABLgAECgcJDQATAAAAAA==.Danksamdi:BAAALgAECgEJAQAAAA==.Dante:BAAALgAECgUJCAAAAA==.Darige:BAAALgAECgIJAgAAAA==.Darim:BAAALgAECgEJAQABLgAECgkJJQABADQZAA==.Darrow:BAAALgAECggJCAAAAA==.Darthspawn:BAABLgAECn8aAAIQAAYJ4gtjpQD/AAAQAAYJ4gtjpQD/AAAAAA==.Daryl:BAAALgAECgQJBAAAAA==.Daryn:BAAALgAECgQJBAAAAA==.Davidbowy:BAABLgAECn8ZAAMgAAgJsA1VJgBLAQAgAAcJ7whVJgBLAQASAAcJYQ4mdAAsAQABLgAECgYJBwATAAAAAA==.',
De='Deathnstuf:BAAALgAECgQJBgAAAA==.Deathollow:BAAALgAECgEJBAAAAA==.Delver:BAAALgADCgYJBgABLgAECgkJJQABADQZAA==.Demina:BAAALgAECgMJAwABLgAECggJHQAWAEocAA==.Demonainkor:BAAALgAECgYJBgABLgAECgkJKQAHADsWAA==.Demonicfury:BAAALgAECgYJBwAAAA==.Demonthrall:BAAALgAECgEJAQAAAA==.Dencity:BAABLgAECn8tAAMDAAkJEBarFQABAgADAAkJ8BGrFQABAgACAAYJbxfWMQAgAQAAAA==.Desden:BAABLgAECn8tAAIfAAkJqhJ4DwC2AQAfAAkJqhJ4DwC2AQAAAA==.Destined:BAAALgAECgYJBwAAAA==.Devianchi:BAABLgAECn8nAAMdAAgJ+B+FCQC5AgAdAAgJ+B+FCQC5AgAMAAcJIh8IFAD1AQABLgAECgkJFwAcAHcZAA==.Devitodevour:BAABLgAECn8eAAMYAAgJPRs5NgDqAQAYAAcJmxk5NgDqAQAXAAMJXBkENQDiAAAAAA==.',
Dg='Dgbugs:BAACLgAFFH8KAAIQAAMJoCLLaQD7AAAQAAMJoCLLaQD7AAAuAAQKfzIAAhAACAk9Ix8fAG4CABAACAk9Ix8fAG4CAAAA.',
Dh='Dhbert:BAABLgAECn8sAAIhAAkJ5xHcEQDDAQAhAAkJ5xHcEQDDAQAAAA==.Dhomeli:BAAALgAECgQJBQAAAA==.',
Di='Dirtchez:BAAALgAECgIJAwAAAA==.Disastrophy:BAAALgAECgYJEQABLgAECgcJCAATAAAAAA==.Disturbed:BAABLgAECn83AAQNAAkJGSD4AADtAgANAAkJ5h/4AADtAgAYAAgJNRtEHwBSAgAXAAEJAADbYgBJAAAAAA==.Disturbio:BAAALgAECgEJAQABLgAECgkJNwANABkgAA==.Divinepsycho:BAAALgADCgcJBwAAAA==.Divitiacus:BAAALgAECgYJBgAAAA==.',
Dj='Djowio:BAAALgADCgYJBgABLgAECggJIwAYABoiAA==.',
Dk='Dknightresh:BAAALgAECgYJBgABLgAECgcJIwAJANwRAA==.',
Dm='Dmz:BAAALgADCgUJBgAAAA==.',
Do='Domfromgears:BAAALgAECgQJCQAAAA==.Dominance:BAAALgAECgEJAQAAAA==.Doomgaze:BAAALgADCgMJAQAAAA==.Dooridash:BAAALgADCgcJCwAAAA==.Dorc:BAAALgAECgMJBQAAAA==.Dotyou:BAAALgAECgIJAgAAAA==.Doudouzz:BAAALgAECgQJDQAAAA==.',
Dr='Dracthor:BAAALgADCgQJBAAAAA==.Draejin:BAAALgAECgkJDwAAAA==.Dragonfist:BAAALgADCgcJBwAAAA==.Dragthyr:BAAALgAECgQJBQAAAA==.Dramûl:BAABLgAECn8dAAISAAgJcRgOPgC/AQASAAgJcRgOPgC/AQAAAA==.Druiaier:BAAALgADCgYJCQAAAA==.Druidibrume:BAAALgAECgMJDAAAAA==.Druknatsu:BAAALgAECgUJBQAAAA==.Drunkdragon:BAABLgAECn8UAAIMAAgJRRLpGwD9AQAMAAgJRRLpGwD9AQAAAA==.',
Du='Dubbzilla:BAAALgAECgEJAQAAAA==.Dudedruid:BAAALgADCgUJBQAAAA==.Duncán:BAABLgAFFH8HAAMEAAUJ+RtdHABkAQAEAAUJ+RtdHABkAQAiAAEJoBWdEQA+AAAAAA==.Dustyknight:BAABLgAECn8eAAIhAAgJzQgzKADoAAAhAAgJzQgzKADoAAAAAA==.',
Dw='Dwell:BAAALgADCgkJIQAAAA==.',
Dy='Dyavola:BAAALgAECgUJBQAAAA==.',
Ea='Earthquack:BAAALgADCgMJAwABLgAECggJGwAiADMVAA==.',
Ed='Edge:BAABLgAECn8bAAIIAAgJyxTtOQCaAQAIAAgJyxTtOQCaAQAAAA==.',
Ee='Eelenna:BAABLgAECn8ZAAMjAAkJLhxgBgCSAgAjAAkJLhxgBgCSAgAPAAUJwRBnUwD4AAABLgAFFAMJBQARAKgTAA==.',
El='Elamlock:BAAALgADCgYJCwAAAA==.Eleathe:BAAALgAFFAQJBAABLgAECggJHQAWAEocAA==.Eleros:BAABLgAECn8wAAIWAAkJsB+gDADIAgAWAAkJsB+gDADIAgAAAA==.Elicio:BAAALgAECgYJEAAAAA==.Ellysial:BAAALgADCgUJBQAAAA==.Elphinia:BAABLgAECn8uAAMaAAkJNhiRDgAdAgAaAAkJNhiRDgAdAgAkAAEJ4BFlIAAxAAABLgAFFAMJAwATAAAAAA==.Elreÿ:BAAALgADCgEJAQAAAA==.',
Em='Emberwrath:BAAALgADCgMJAwAAAA==.Emosdnem:BAAALgAECgQJBQAAAA==.Emt:BAAALgAECgQJBAAAAA==.',
En='Endarial:BAAALgAECgQJCAAAAA==.Enoki:BAABLgAFFH8KAAIIAAQJsxWcKgADAQAIAAQJsxWcKgADAQABLgAFFAgJIAALALscAA==.',
Er='Eraduckated:BAAALgAECgYJCAABLgAECggJGwAiADMVAA==.Erah:BAAALgADCgUJDQAAAA==.',
Es='Esco:BAAALgADCgMJAwAAAA==.Esile:BAAALgADCgkJKAABLgAECgkJLQAKAC4PAA==.',
Et='Eternalnow:BAAALgADCgEJAQAAAA==.',
Ev='Evelith:BAAALgADCgYJBgAAAA==.Everlife:BAAALgAFFAEJAQAAAA==.',
Ex='Exemptt:BAAALgAECgkJBQAAAA==.Exo:BAAALgADCgkJDwAAAA==.',
Fa='Falconpunch:BAAALgAECgYJBwAAAA==.Farnesë:BAAALgADCgUJBwABLgADCgcJBwATAAAAAA==.Fauzzie:BAAALgAECgIJAgAAAA==.Fayrel:BAAALgAECgEJAgAAAA==.',
Fe='Fedders:BAABLgAECn8pAAIEAAkJRiahBgAkAwAEAAkJRiahBgAkAwAAAA==.Felaids:BAACLgAFFH8QAAMYAAQJhRJzTQAJAQAYAAQJ7A5zTQAJAQANAAEJSBCRGQBMAAAuAAQKfyoAAxgACAlHHCMzAPYBABgABwlHHCMzAPYBABcAAwkSCLpEAKIAAAAA.Felimonk:BAAALgAECgQJBAABLgABCgQJBQATAAAAAA==.Felpecs:BAAALgAECggJDgAAAA==.Fero:BAAALgAECgQJBAAAAA==.Feyda:BAABLgAECn8bAAIBAAgJjQf8iQBKAQABAAgJjQf8iQBKAQAAAA==.',
Fi='Fillon:BAACLgAFFH8IAAIEAAQJPxvEGQBuAQAEAAQJPxvEGQBuAQAuAAQKfzMAAgQACQmxJRAJAAkDAAQACQmxJRAJAAkDAAAA.Fionas:BAAALgADCgQJBAAAAA==.Firerybush:BAAALgAECgYJBwABLgAECggJRAAJAPwYAA==.Firessar:BAAALgAECgcJCwAAAA==.Fishfood:BAABLgAECn8tAAIRAAkJ/xIaBwDtAQARAAkJ/xIaBwDtAQAAAA==.Fishlover:BAAALgADCgUJBQAAAA==.Fixer:BAAALgAECgUJCQAAAA==.',
Fk='Fk:BAAALgAFFAMJAwABLgAFFAUJBwAEAPkbAA==.',
Fo='Foe:BAEALgAECggJEwAAAA==.Folkvar:BAAALgADCgcJDAAAAA==.',
Fr='Frankngibbon:BAAALgADCgYJBgAAAA==.Frimm:BAAALgAECgYJBwAAAA==.Frimthemage:BAABLgAECn8tAAIBAAkJOR+YIACDAgABAAkJOR+YIACDAgAAAA==.Frostmaster:BAABLgAECn8bAAIBAAcJOhxITgDWAQABAAcJOhxITgDWAQAAAA==.',
Fu='Funbunz:BAAALgAECgYJBgAAAA==.',
['Fí']='Fízban:BAAALgAECgIJAwAAAA==.',
['Fø']='Førd:BAACLgAFFH8LAAMlAAQJFQwnBAAcAQAlAAQJFQwnBAAcAQAmAAIJjQioRQB4AAAuAAQKfy8ABCUACAmQHRoLACoCACUABwlLGhoLACoCACYABwlOGSUkAJwBABQAAwkIAtsyAD0AAAAA.',
Ga='Gammon:BAABLgAECn8hAAMPAAgJ7huCFwAAAgAPAAgJ7huCFwAAAgAIAAUJGxtMPwCCAQAAAA==.Gangrene:BAABLgAECn8yAAMQAAkJnxPZRgDOAQAQAAkJnxPZRgDOAQAhAAgJCQtWJQD+AAAAAA==.Gary:BAAALgAECgQJBwAAAA==.Gash:BAAALgAECgMJAwAAAA==.Gaspasser:BAABLgAECn8iAAIkAAgJvBfxBQD0AQAkAAgJvBfxBQD0AQAAAA==.Gaviin:BAABLgAECn84AAIkAAkJGCHAAQC/AgAkAAkJGCHAAQC/AgAAAA==.',
Ge='Gearador:BAAALgADCgcJAQAAAA==.Geisten:BAAALgAECgYJEwAAAA==.Genovia:BAAALgADCgIJAgABLgAECggJEwATAAAAAA==.Gerhart:BAABLgAECn8sAAQOAAkJSxkSBwDvAQAOAAkJ6hQSBwDvAQAWAAcJxBmzUQBwAQAVAAMJQxCCQwBrAAAAAA==.Getcarried:BAAALgADCgMJAwABLgAFFAUJFwABAL0WAA==.Getty:BAAALgAECgcJEgAAAA==.',
Gf='Gfforgold:BAAALgADCgIJAgAAAA==.',
Gh='Ghosthunterx:BAAALgADCgEJAwAAAA==.Ghouldana:BAAALgADCgYJBgAAAA==.',
Gi='Gibbthok:BAAALgADCggJCAAAAA==.Gigachode:BAAALgAECgEJAgAAAA==.Gigarius:BAABLgAECn8bAAIiAAgJWCTXAwCmAgAiAAgJWCTXAwCmAgAAAA==.Gigglesworth:BAAALgAECgYJBgAAAA==.Gilamonster:BAAALgAECgYJCgAAAA==.',
Gl='Gleiten:BAAALgADCgMJAwAAAA==.Glonkins:BAABLgAECn8hAAQSAAkJjR7nDADHAgASAAkJQx7nDADHAgAgAAQJ6RSXLQAXAQAFAAEJAACtPgAAAAAAAA==.Glynden:BAAALgADCgEJAQAAAA==.',
Go='Goncor:BAACLgAFFH8FAAIRAAMJqBOjDADpAAARAAMJqBOjDADpAAAuAAQKfyAAAxEACAkyIPgFABECABEACAnoH/gFABECACEABQn4InIYAHIBAAAA.Gonnosuke:BAAALgAECgYJDgAAAA==.Gooseberry:BAAALgAECgEJAQAAAA==.Goosë:BAAALgADCgcJBwAAAA==.Gorrelord:BAAALgADCgEJAQABLgAFFAUJFwABAL0WAA==.Gortar:BAAALgADCgEJAQAAAA==.',
Gr='Granolah:BAAALgADCgcJCwABLgAECgkJKgAeAAwfAA==.Griffmonk:BAABLgAECn8zAAIdAAkJCRvEEABqAgAdAAkJCRvEEABqAgAAAA==.Grumpymage:BAABLgAECn81AAIBAAkJ6x8eFADJAgABAAkJ6x8eFADJAgAAAA==.',
Gu='Gussy:BAAALgAECgQJBAABLgAECggJCgATAAAAAA==.',
Ha='Hafsac:BAAALgAECgMJAwAAAA==.Halaranth:BAAALgAECgIJAgAAAA==.Hamasakura:BAAALgAECgYJBgAAAA==.Hara:BAABLgAECn8aAAILAAYJPRoGPQB/AQALAAYJPRoGPQB/AQAAAA==.Hardlyknower:BAAALgADCgIJAgAAAA==.Hardord:BAABLgAECn8hAAIaAAcJMQ/LIgBTAQAaAAcJMQ/LIgBTAQAAAA==.Harrydotter:BAAALgAECgIJAgAAAA==.Haryle:BAAALgAECgUJCgAAAA==.Hayanne:BAABLgAECn84AAIZAAkJXxzGBgB7AgAZAAkJXxzGBgB7AgAAAA==.',
He='Healchucky:BAAALgAECgYJDQAAAA==.Healfire:BAAALgADCgYJBwAAAA==.Healisha:BAAALgAECgYJEAAAAA==.Heina:BAAALgAECgYJBgAAAA==.Hershall:BAAALgAECgUJBQABLgAFFAMJCAAVAI4lAA==.',
Hi='Hitnrun:BAAALgAECgMJAwAAAA==.',
Ho='Hochunk:BAABLgAECn8dAAMDAAkJ+w7rHQCyAQADAAkJxArrHQCyAQACAAkJugkdOwBOAQAAAA==.Hochunks:BAAALgAECgYJDQAAAA==.Holdenger:BAAALgADCgQJBAAAAA==.Holikow:BAABLgAECn8WAAIEAAkJwA2gagB7AQAEAAkJwA2gagB7AQAAAA==.Holyherpies:BAAALgAECgYJBgAAAA==.Holyllama:BAAALgADCgcJBwAAAA==.Holymousey:BAABLgAECn8fAAIcAAkJjRG3IQDTAQAcAAkJjRG3IQDTAQAAAA==.Holysnake:BAAALgAECgQJBAAAAA==.Holytady:BAAALgADCgcJDQAAAA==.Holytudd:BAABLgAECn8gAAIEAAgJixTOagB7AQAEAAgJixTOagB7AQAAAA==.Honeybun:BAAALgADCgQJAgAAAA==.Honorlife:BAABLgAECn8rAAIIAAgJDhtFGQBVAgAIAAgJDhtFGQBVAgAAAA==.Hopeudie:BAAALgAECgUJBgABLgAFFAUJBwAEAPkbAA==.Horata:BAAALgAECgMJAwAAAA==.Hotelcali:BAAALgADCgkJCQAAAA==.',
Hu='Huckcold:BAAALgAECgcJDwAAAA==.Hugehands:BAAALgAECgUJBwAAAA==.Hughass:BAAALgADCgEJAQAAAA==.Hurano:BAAALgAECgYJBQAAAA==.',
['Hâ']='Hârley:BAABLgAECn8xAAILAAkJehueFQB7AgALAAkJehueFQB7AgAAAA==.',
['Hí']='Híram:BAABLgAECn8mAAIEAAgJahSWYACSAQAEAAgJahSWYACSAQAAAA==.',
Id='Idyllwild:BAAALgAECgEJBAAAAA==.',
Ih='Ihsan:BAABLgAECn8nAAIEAAkJDBQnOAADAgAEAAkJDBQnOAADAgAAAA==.',
Il='Ilharess:BAACLgAFFH8JAAIBAAMJIgsibQDfAAABAAMJIgsibQDfAAAuAAQKfyYAAgEACQkdEx5rAIsBAAEACQkdEx5rAIsBAAAA.',
In='Inko:BAAALgADCgYJCQABLgAFFAUJGAAZAEwkAA==.Inkpot:BAAALgAECgEJAQABLgAECggJNQALABYlAA==.Inkwell:BAABLgAECn81AAILAAgJFiX4CAAAAwALAAgJFiX4CAAAAwAAAA==.',
Is='Iskasta:BAAALgADCgQJBAAAAA==.Isobell:BAAALgAECgUJBwAAAA==.',
Ja='Jaardrius:BAABLgAECn8yAAMdAAkJeyGLBQAmAwAdAAkJeyGLBQAmAwAMAAMJjgu3XgCVAAAAAA==.Jackransom:BAAALgADCgkJDgAAAA==.Jakobo:BAAALgAECgcJCgAAAA==.Jal:BAAALgADCgMJAwAAAA==.Jalapenoheat:BAAALgAECgQJAwAAAA==.Jandreyn:BAAALgADCgUJAQAAAA==.Jaskar:BAAALgAECgEJAQAAAA==.Javanna:BAAALgAECgMJAwAAAA==.',
Jd='Jdiddy:BAAALgAECgcJAQAAAA==.',
Je='Jelly:BAAALgADCgIJAgABLgAFFAgJIAALALscAA==.',
Ji='Jimbostein:BAAALgADCgEJAQAAAA==.Jinnie:BAAALgADCgMJBgAAAA==.',
Jj='Jjb:BAAALgAECgcJCQAAAA==.',
Ju='Junebuge:BAAALgADCgkJJgAAAA==.Junknthtrunk:BAAALgAECgMJAwAAAA==.',
Ka='Kaelana:BAAALgADCgEJAQAAAA==.Karl:BAAALgADCgUJBQAAAA==.Katôs:BAAALgADCgkJCQAAAA==.',
Kd='Kda:BAAALgAECgYJBgABLgAECgcJFQAaAIYjAA==.',
Ke='Keanew:BAABLgAECn8uAAQOAAkJjB2KCgCOAQAVAAkJ/xvTFgCdAQAOAAcJHReKCgCOAQAWAAMJNgPo1ABWAAAAAA==.Kebap:BAAALgAECgYJBgAAAA==.Keigaa:BAABLgAECn8pAAMcAAYJcCGkIAAWAgAcAAYJcCGkIAAWAgAEAAUJSBZJrQADAQAAAA==.Keilien:BAAALgAECgUJBgAAAA==.Kenry:BAAALgAECgQJCAAAAA==.Keonna:BAAALgAECgQJCAAAAA==.Keppra:BAAALgAECgYJEgAAAA==.Kerlin:BAACLgAFFH8MAAILAAMJ4AHyQQCNAAALAAMJ4AHyQQCNAAAuAAQKfxsAAwsACQk9DmRYAEkBAAsACAlSC2RYAEkBAAoAAQnkAnOIACcAAAAA.Keyaira:BAAALgADCgYJBwAAAA==.Keybash:BAABLgAECn8UAAMNAAYJmgVyHwB1AAAYAAYJewVEtgDDAAANAAMJagNyHwB1AAAAAA==.Keíga:BAAALgAECgMJBAAAAA==.',
Kh='Khurst:BAAALgAECgcJCgAAAA==.',
Ki='Kilmithius:BAAALgAECgYJEgAAAA==.Kimchi:BAAALgAECgQJBAABLgAFFAgJIAALALscAA==.Kimmex:BAAALgADCgcJAgAAAA==.Kinoxo:BAACLgAFFH8lAAMJAAYJbB+cCACOAQAJAAUJuSKcCACOAQAbAAUJ1RV1FgDsAAAuAAQKfx0AAwkACAmRIeMaAHUCAAkACAnzHeMaAHUCABsABAm6HakgAOgAAAAA.Kinoxoxo:BAAALgAECgQJBwAAAA==.Kirianis:BAABLgAECn8tAAIEAAkJ5BflKgA2AgAEAAkJ5BflKgA2AgAAAA==.Kishuko:BAAALgADCgEJAQAAAA==.',
Kl='Klesha:BAAALgADCgMJAwAAAA==.',
Ko='Kongfuux:BAAALgAECgQJBAAAAA==.Kossuth:BAAALgAECgcJCAAAAA==.',
Kr='Kragge:BAAALgADCgkJDwAAAA==.Krampusnacht:BAAALgAECgYJCQAAAA==.Kryven:BAAALgADCgkJEQAAAA==.',
Ku='Kumma:BAAALgADCgEJAQAAAA==.Kushaladaora:BAAALgAECgQJCQAAAA==.',
Ky='Kybrine:BAAALgAECgEJAQAAAA==.Kynlas:BAAALgAECgEJAQAAAA==.Kyratinx:BAAALgAECgEJAwAAAA==.',
['Kì']='Kìtty:BAAALgAECgYJCwAAAA==.',
La='Lacachuda:BAAALgADCgIJAwAAAA==.Lacear:BAAALgADCgcJBwABLgAFFAUJBwAEAPkbAA==.Langris:BAAALgAECgcJCAAAAA==.Larious:BAABLgAECn9AAAIEAAkJLB22FwCYAgAEAAkJLB22FwCYAgAAAA==.',
Le='Led:BAAALgAECgcJBwAAAA==.Ledikens:BAAALgADCgkJEQAAAA==.Legnase:BAABLgAECn8wAAMDAAkJ6R5ABgD8AgADAAkJ1h5ABgD8AgACAAIJRRYZUgBoAAABLgAECgkJOgAPAKkhAA==.Leht:BAABLgAECn8tAAMKAAkJLg9zHQCyAQAKAAkJLg9zHQCyAQALAAEJawGQ7AAVAAAAAA==.Lessgibbon:BAABLgAECn8XAAIJAAcJPh/WGgB1AgAJAAcJPh/WGgB1AgAAAA==.Lestare:BAAALgADCgYJBgAAAA==.Leviiathan:BAAALgAECgcJAwAAAA==.Lexishexis:BAAALgADCgYJBgAAAA==.',
Li='Lichma:BAAALgAECgIJAgAAAA==.Lighte:BAAALgADCgYJBgAAAA==.Lilgaspump:BAAALgADCgIJAQABLgAECgUJFAAHAJYQAA==.Lili:BAAALgADCgcJAgAAAA==.Lilnasty:BAABLgAECn8gAAIBAAgJig/obwCAAQABAAgJig/obwCAAQAAAA==.Lilnickel:BAAALgADCggJCAAAAA==.Lionroar:BAAALgADCgIJAwAAAA==.Livesey:BAAALgAECgQJBgAAAA==.',
Lo='Locknut:BAAALgADCgkJFwABLgAECggJFAAMAEUSAA==.Lockpie:BAAALgAECgUJBQAAAA==.Lockresh:BAAALgADCgUJBQABLgAECgcJIwAJANwRAA==.Lokahn:BAABLgAECn8WAAIMAAYJ2RmGIwC6AQAMAAYJ2RmGIwC6AQAAAA==.Longhornpibe:BAABLgAECn9EAAMJAAgJ/BhcHQDhAQAJAAgJ/BhcHQDhAQAbAAMJTA75PwCXAAAAAA==.Loudog:BAABLgAECn8xAAMQAAgJZxSwZgB4AQAQAAgJ/RKwZgB4AQAhAAYJ8hD4JgDxAAAAAA==.',
Lu='Lupardus:BAAALgAECgEJAQAAAA==.Luto:BAAALgAECgkJDgAAAA==.',
Ly='Lynxie:BAABLgAECn8gAAIGAAgJWA/AKQBdAQAGAAgJWA/AKQBdAQAAAA==.',
['Lö']='Lökkïï:BAAALgADCgUJBQAAAA==.Lörelei:BAAALgADCgkJMQAAAA==.',
Ma='Mackerel:BAABLgAECn8YAAIHAAcJliBoEACXAgAHAAcJliBoEACXAgABLgAFFAgJJQAZAJojAA==.Madii:BAAALgAECgEJAQAAAA==.Mageresh:BAAALgAECgYJEAABLgAECgcJIwAJANwRAA==.Malus:BAABLgAECn8ZAAIYAAgJLQ68YQClAQAYAAgJLQ68YQClAQAAAA==.Manders:BAAALgADCgcJAgAAAA==.Mangela:BAAALgAECgIJAwAAAA==.Mank:BAAALgAECgMJAwAAAA==.Maps:BAAALgAECgYJDQAAAA==.Masher:BAAALgADCgkJNAAAAA==.Mattydruid:BAAALgAFFAEJAQAAAA==.Maverage:BAAALgADCgMJBQAAAA==.Mavramune:BAACLgAFFH8IAAISAAQJ2QgNPwDzAAASAAQJ2QgNPwDzAAAuAAQKfyYAAxIACAlDF6pPAIcBABIABwniGapPAIcBAAUACAmzDLcbALEAAAAA.Mayge:BAABLgAECn8rAAIBAAkJKxtSKQBaAgABAAkJKxtSKQBaAgAAAA==.Mañali:BAAALgADCgYJBgAAAA==.',
Mc='Mcfürry:BAABLgAECn8VAAILAAcJyBtXLQDRAQALAAcJyBtXLQDRAQAAAA==.',
Me='Mebedir:BAAALgAECgMJBQAAAA==.Meekal:BAAALgADCgEJAQAAAA==.Meggatron:BAAALgAECgYJBgABLgAECggJKAAjAFofAA==.Melithia:BAAALgAECgcJEQAAAA==.Mels:BAAALgAECgQJBgAAAA==.Mendinna:BAABLgAECn8zAAIVAAgJdBP7FQCmAQAVAAgJdBP7FQCmAQAAAA==.Mephidrossa:BAAALgAECggJCAABLgAECgkJNgAMAOMgAA==.Mercs:BAAALgADCgQJBQABLgAECgUJFAAHAJYQAA==.Methir:BAAALgAECgEJAQABLgAFFAQJBQATAAAAAA==.',
Mi='Miffed:BAAALgAECggJEgABLgAFFAYJHQAiAPURAA==.Mildew:BAAALgADCgYJBgAAAA==.Mincksie:BAAALgAECggJEwAAAA==.Mininetty:BAAALgADCgcJBwABLgAECgUJBQATAAAAAA==.Mirage:BAABLgAECn8VAAIaAAcJhiMPFwBSAgAaAAcJhiMPFwBSAgAAAA==.Misfired:BAAALgADCgIJAgAAAA==.Mistbot:BAABLgAECn82AAIMAAkJ4yBPBQDcAgAMAAkJ4yBPBQDcAgAAAA==.',
Mo='Montebrew:BAAALgAECgYJBgAAAA==.Mooky:BAABLgAECn8oAAIKAAkJ9Q9HHQC0AQAKAAkJ9Q9HHQC0AQAAAA==.Moovitz:BAAALgADCgYJBgAAAA==.Mopeia:BAABLgAECn8iAAMLAAYJghcrOQCRAQALAAYJghcrOQCRAQAfAAUJOQ6HLgCxAAABLgAECgYJEwATAAAAAA==.Mord:BAAALgAECgUJDAAAAA==.Mork:BAAALgADCgMJAwABLgAECgcJJwAQAD4iAA==.Mortemore:BAACLgAFFH8RAAIWAAUJ4hd4NAAhAQAWAAUJ4hd4NAAhAQAuAAQKfyQAAhYACQkSIKMdAEgCABYACQkSIKMdAEgCAAAA.Mortlee:BAAALgAECgEJAQABLgAFFAUJEQAWAOIXAA==.Motet:BAAALgAECgYJCwAAAA==.',
Mu='Muikkie:BAAALgAECgEJAgAAAA==.Mulro:BAAALgADCgMJAwAAAA==.Muncher:BAAALgAECgkJEgAAAA==.',
My='Mymage:BAAALgADCgEJAQAAAA==.Mynoghra:BAAALgAECgYJEgAAAA==.Mynxx:BAAALgAECgcJCQAAAA==.Mystrax:BAAALgADCgIJAgAAAA==.',
Na='Nadoral:BAAALgADCgYJCwAAAA==.Naproxen:BAABLgAECn85AAIgAAkJgRwvBQC+AgAgAAkJgRwvBQC+AgAAAA==.Naraku:BAACLgAFFH8WAAQYAAUJqRnmMABKAQAYAAUJuBjmMABKAQAXAAEJFhKxFABVAAANAAEJ6RTTFABTAAAuAAQKfzIAAxgACAnhI88QALECABgACAlcI88QALECABcABglbHugNAOcBAAAA.Narberal:BAAALgADCgEJAQAAAA==.Nastager:BAAALgADCgcJBwAAAA==.Naxx:BAAALgADCgIJAgAAAA==.Nazgül:BAAALgADCgMJAgAAAA==.',
Ne='Necroseeker:BAAALgAECgYJCwAAAA==.Negativity:BAAALgAECgYJBgAAAA==.Nes:BAAALgAECggJCAABLgAECgkJJAADAC4aAA==.Nettie:BAAALgAECgUJBQAAAA==.Netty:BAAALgAECgIJAgABLgAECgUJBQATAAAAAA==.',
Ni='Nightshaulea:BAAALgAECgUJBgAAAA==.Niklaus:BAABLgAECn8eAAIEAAcJdhZVaACvAQAEAAcJdhZVaACvAQAAAA==.Nilisha:BAAALgADCgIJAgAAAA==.Nimi:BAAALgAECgEJAQAAAA==.Nirala:BAAALgADCgkJCQAAAA==.',
No='Nosferatmoo:BAAALgADCgkJCQABLgADCgkJEwATAAAAAA==.',
Nu='Nusy:BAAALgAECgQJBAAAAA==.',
Ny='Nymeera:BAABLgAECn8tAAMfAAkJBgcYJgDiAAAfAAkJygYYJgDiAAAeAAIJMgMcNwBJAAAAAA==.Nymphetamine:BAABLgAECn85AAMCAAkJxhh4DgBbAgACAAkJxhh4DgBbAgADAAQJ4AQ7SwCYAAAAAA==.Nyxarya:BAAALgADCgcJBwAAAA==.',
Nz='Nzoth:BAABLgAECn8gAAIGAAkJGRCOIQCUAQAGAAkJGRCOIQCUAQAAAA==.',
Ob='Obnixilis:BAABLgAECn8VAAIQAAYJXRjgbgCrAQAQAAYJXRjgbgCrAQABLgAECggJEgATAAAAAA==.',
Od='Odessa:BAAALgAECgEJAQAAAA==.',
Ok='Okin:BAAALgAECgMJAwAAAA==.',
Om='Omadruid:BAAALgADCgYJBgAAAA==.Omapriest:BAAALgADCgUJBQAAAA==.Omashamwow:BAAALgAECgQJBQAAAA==.Omorc:BAABLgAECn8tAAIFAAkJLhdhBQAuAgAFAAkJLhdhBQAuAgAAAA==.',
On='Oneyeli:BAAALgADCgYJBgAAAA==.Oniony:BAAALgADCgYJCwAAAA==.Onli:BAAALgAECgEJAQAAAA==.Onos:BAAALgAECgMJAwAAAA==.',
Or='Ordlok:BAAALgADCgcJCQAAAA==.Orlaith:BAAALgADCgUJBQABLgAECggJHQAWAEocAA==.',
Ow='Owenwilson:BAAALgAECgIJAwAAAA==.Owful:BAAALgAECgcJDAAAAA==.',
Pa='Pandaloca:BAAALgAECgUJBQAAAA==.Pandaloco:BAAALgADCgcJBwAAAA==.Pandalôc:BAAALgAECgIJAgAAAA==.Pandoe:BAABLgAECn8VAAQfAAgJbxfaDgC+AQAfAAYJaB/aDgC+AQAKAAgJrA6nMACDAQALAAEJngeR3AAmAAAAAA==.Papaya:BAACLgAFFH8gAAILAAgJuxx/AwCQAgALAAgJuxx/AwCQAgAuAAQKfyIAAwsACQnZIcMGAB8DAAsACQnZIcMGAB8DAAoABwliIZYjAOABAAAA.Pawpawpiddle:BAAALgAECgYJBgAAAA==.',
Pe='Penelopea:BAABLgAECn8pAAIBAAkJeRVbNAArAgABAAkJeRVbNAArAgAAAA==.Perlen:BAAALgADCgYJBgAAAA==.Perun:BAAALgAECgYJDQAAAA==.',
Ph='Phaith:BAAALgADCgUJCwAAAA==.Phenomenal:BAAALgAECgEJAQABLgAECggJIQAPAO4bAA==.',
Pl='Plaguedealer:BAAALgADCgUJBQAAAA==.',
Pn='Pneumonya:BAAALgAECgcJBwAAAA==.',
Po='Porteagarder:BAABLgAECn8bAAIIAAYJoAa0cgDPAAAIAAYJoAa0cgDPAAABLgAECggJHgALAKsIAA==.Potatodruid:BAAALgAECgQJDQAAAA==.Power:BAAALgADCgYJBgAAAA==.',
Pr='Preparedpie:BAABLgAECn8SAAIWAAgJcxm2LQDzAQAWAAgJcxm2LQDzAQAAAA==.Preront:BAACLgAFFH8vAAMjAAkJJSIQAADjAgAjAAkJViEQAADjAgAPAAgJBxvlAwA2AgAuAAQKfyIABCMACQngJikAAOYDACMACQngJikAAOYDAA8AAwksJq4+AFABAAgAAwkVG+dpAOoAAAAA.Priestbrume:BAAALgAECgEJAQAAAA==.Pringler:BAAALgAECgQJBAABLgAFFAgJJQAZAJojAA==.Producktive:BAABLgAECn8bAAIiAAgJMxXCEAC6AQAiAAgJMxXCEAC6AQAAAA==.Prometeus:BAAALgADCggJCAAAAA==.Pros:BAABLgAECn8iAAIXAAkJWRRZDQDvAQAXAAkJWRRZDQDvAQAAAA==.Pruulia:BAAALgADCgkJDAABLgAECgkJLQAKAC4PAA==.Príestly:BAAALgAECgYJCwAAAA==.',
Ps='Psydúck:BAAALgADCgcJDQAAAA==.',
Pu='Puffdamagic:BAABLgAECn8aAAImAAgJ1huSFAAZAgAmAAgJ1huSFAAZAgABLgAFFAUJEQAWAOIXAA==.Puffthemagic:BAAALgAECggJDQAAAA==.Purentity:BAAALgAECgYJCwAAAA==.',
Py='Pyatt:BAABLgAECn8uAAINAAkJbx3JAgBxAgANAAkJbx3JAgBxAgAAAA==.',
['Pú']='Púff:BAAALgADCgEJAQAAAA==.',
Qu='Quack:BAAALgAECggJEQAAAA==.Quackadin:BAAALgADCgYJCwABLgAECggJEQATAAAAAA==.Quackula:BAAALgAECgcJBgAAAA==.Quilae:BAAALgAECgYJDwABLgAECggJHgALAKsIAA==.Quiny:BAAALgADCgMJAQAAAA==.',
Ra='Raerlynn:BAEALgADCgMJAwAAAA==.Ragnix:BAAALgAECgEJAQAAAA==.Randivh:BAAALgAECgIJAgAAAA==.Rassputin:BAABLgAECn8pAAIBAAkJnhc4MAA7AgABAAkJnhc4MAA7AgAAAA==.Ravnmoon:BAAALgAECgUJBQAAAA==.Razzleyi:BAAALgADCgkJNAAAAA==.',
Re='Realmack:BAAALgAECggJDAABLgAFFAUJBwAEAPkbAA==.Rebuke:BAAALgAECgYJBgAAAA==.Reclaimblade:BAAALgADCgUJBQAAAA==.Reclaimdrunk:BAAALgAECgIJAgAAAA==.Reclaimergun:BAAALgADCgEJAQAAAA==.Reclaimholy:BAAALgADCgUJBQAAAA==.Reclaimsage:BAAALgADCgYJBQAAAA==.Reigwend:BAAALgADCggJDwAAAA==.Reisharra:BAAALgAECgUJCgAAAA==.Relimas:BAAALgADCgcJEAAAAA==.Remish:BAAALgAECgQJBAABLgAECgUJBQATAAAAAA==.Rendezvous:BAAALgAECgEJBAAAAA==.Renkà:BAAALgAFFAMJAwAAAA==.Requestor:BAAALgAECgUJBgABLgAECggJEgATAAAAAA==.Resmondo:BAAALgADCgQJBAAAAA==.Ret:BAACLgAFFH8PAAIEAAQJpguOOwAWAQAEAAQJpguOOwAWAQAuAAQKfyoAAgQACAkhG4suAGkCAAQACAkhG4suAGkCAAAA.Revaerlous:BAABLgAECn8uAAIQAAkJix0oLACIAgAQAAkJix0oLACIAgAAAA==.',
Rh='Rheas:BAAALgADCgYJDQABLgAECggJEwATAAAAAA==.Rhei:BAABLgAECn8RAAIWAAgJIBkbLgBEAgAWAAgJIBkbLgBEAgAAAA==.',
Ri='Ribeye:BAACLgAFFH8dAAIiAAYJ9RH5AgBSAQAiAAYJ9RH5AgBSAQAuAAQKfykAAiIACQlPFigPAKYBACIACQlPFigPAKYBAAAA.',
Ro='Roereker:BAABLgAECn85AAIEAAkJcBi8KAA/AgAEAAkJcBi8KAA/AgAAAA==.Roguesamurai:BAAALgADCgEJAQAAAA==.Rohhenge:BAAALgADCgkJDwAAAA==.Roketraccoon:BAAALgAECgQJCAAAAA==.Romoxodus:BAAALgADCgUJCQAAAA==.Rongbip:BAABLgAECn8bAAIgAAkJXhodEQALAgAgAAkJXhodEQALAgAAAA==.Roshamandes:BAABLgAECn8nAAIOAAkJzCC4AQDkAgAOAAkJzCC4AQDkAgAAAA==.Rotigus:BAAALgADCgUJBQAAAA==.',
Ru='Rubadubdubz:BAAALgADCgMJAwAAAA==.Runep:BAABLgAECn8rAAIEAAkJbyDEEADIAgAEAAkJbyDEEADIAgAAAA==.',
['Rè']='Rèi:BAAALgAECgIJBAABLgAECggJJgASAF8iAA==.',
['Ré']='Réstofarian:BAACLgAFFH8UAAILAAQJIB4hGgBUAQALAAQJIB4hGgBUAQAuAAQKfy0AAwsACQm0I1sCAHYDAAsACQm0I1sCAHYDAAoAAgkoGexmAIYAAAAA.',
Sa='Sabbier:BAAALgADCgcJBwAAAA==.Sacredchikín:BAABLgAECn8dAAIYAAgJPxxHJwAoAgAYAAgJPxxHJwAoAgAAAA==.Saiki:BAAALgAECgQJBQAAAA==.Sanataanna:BAAALgADCgUJCwABLgAECggJEwATAAAAAA==.Sandvichus:BAABLgAECn8nAAIKAAkJmyIxBAAEAwAKAAkJmyIxBAAEAwAAAA==.Sanitarìum:BAAALgAECgQJCAAAAA==.Sardine:BAAALgAECgcJDgABLgAFFAgJIAALALscAA==.Sasukie:BAAALgAECgEJBQAAAA==.Savagesmonk:BAAALgAECgUJBgAAAA==.Saxa:BAACLgAFFH8FAAIVAAMJ/xpEDgAKAQAVAAMJ/xpEDgAKAQAuAAQKfywAAhUACQnWIusFALUCABUACQnWIusFALUCAAAA.',
Sc='Scratchnsnif:BAAALgADCgUJBQAAAA==.',
Se='Sefik:BAAALgAECgYJDgAAAA==.Selaana:BAABLgAECn8YAAIPAAYJPh9nIgD8AQAPAAYJPh9nIgD8AQAAAA==.Serkis:BAAALgAECgcJBQAAAA==.Seyekosis:BAAALgAECgcJEQAAAA==.',
Sg='Sgathaich:BAEBLgAECn8rAAIcAAgJVBpgFwAqAgAcAAgJVBpgFwAqAgAAAA==.',
Sh='Shaan:BAAALgADCgMJAwAAAA==.Shadtae:BAAALgAECgYJCgABLgAECgkJLAAIAKgXAA==.Shaio:BAABLgAECn8VAAIMAAYJ3Q9hNgBGAQAMAAYJ3Q9hNgBGAQAAAA==.Shallistiah:BAAALgADCgkJIwABLgAECgkJMgAdAHshAA==.Shamadin:BAAALgADCgkJCQAAAA==.Shambrume:BAAALgAECgYJDgAAAA==.Shambulence:BAACLgAFFH8PAAIIAAQJew4LLAD+AAAIAAQJew4LLAD+AAAuAAQKfxoAAwgACQm/FRwbAEgCAAgACQm/FRwbAEgCACMAAwnRETUfALgAAAAA.Shammlock:BAACLgAFFH8TAAQNAAUJYBB+AQCvAAAYAAMJYxFhYQDYAAANAAQJ+xB+AQCvAAAXAAIJxwK5IABCAAAuAAQKfygABA0ACQmCHuECAIMCAA0ACAkTH+ECAIMCABgACQnDGS0qAGcCABcABQl6EFskADgBAAAA.Shampriest:BAAALgAECggJCAAAAA==.Shamuel:BAACLgAFFH8IAAIgAAYJPBJSBACbAQAgAAYJPBJSBACbAQAuAAQKfxcAAiAACQlqE10OACkCACAACQlqE10OACkCAAAA.Shaylis:BAAALgAECgcJDgABLgAFFAMJAwATAAAAAA==.Sheji:BAAALgADCgkJHAAAAA==.Shiggy:BAAALgAECgQJBQABLgAECgkJKgAJAAUcAA==.Shobadon:BAAALgAECggJEAAAAA==.Shole:BAABLgAECn81AAMPAAkJGh7BDwBUAgAPAAkJGh7BDwBUAgAIAAcJFBxQIwAQAgAAAA==.Shulanii:BAAALgAECgMJBQAAAA==.',
Si='Siatral:BAAALgAECgEJAQABLgAECgkJGgAdAOAaAA==.Siggopotomus:BAAALgADCgUJBQABLgAECggJEwATAAAAAA==.Sigvalden:BAAALgAECggJEwAAAA==.Sigvolden:BAAALgAECgcJAgABLgAECggJEwATAAAAAA==.Silchar:BAAALgADCgUJAQAAAA==.Silicon:BAABLgAECn8hAAIBAAkJjhJwVADFAQABAAkJjhJwVADFAQAAAA==.Sinfulangel:BAABLgAECn8sAAIQAAkJ+BvhHgBvAgAQAAkJ+BvhHgBvAgAAAA==.Siona:BAABLgAECn8/AAISAAkJyAzgRgCiAQASAAkJyAzgRgCiAQAAAA==.',
Sk='Skadie:BAABLgAECn8qAAMSAAkJNBW0JgAfAgASAAkJNBW0JgAfAgAFAAEJ+QOmOQAnAAAAAA==.Skialin:BAAALgAECgEJAQAAAA==.Skiye:BAAALgADCggJDgAAAA==.Skwip:BAAALgAFFAQJBAABLgAFFAUJBwAEAPkbAA==.Skwop:BAAALgAECgEJAgABLgAFFAUJBwAEAPkbAA==.Skyelar:BAAALgAECgcJBgAAAA==.Skyler:BAABLgAECn8UAAInAAcJER39AgAzAgAnAAcJER39AgAzAgAAAA==.',
Sl='Slackness:BAAALgAECgMJCAAAAA==.Slavalous:BAAALgAECgUJCgAAAA==.',
Sn='Snakeshifter:BAAALgADCgUJBQAAAA==.Snakesoul:BAAALgAECgMJBAAAAA==.Snivels:BAABLgAECn8fAAIfAAgJsRDIEgBFAQAfAAgJsRDIEgBFAQAAAA==.Snnorri:BAAALgADCggJFgABLgAECgkJMgAdAHshAA==.',
So='Sodtaoe:BAAALgADCgcJDQAAAA==.Solsilvesti:BAAALgADCgMJAwAAAA==.',
Sp='Sparrkle:BAABLgAECn8uAAIXAAkJ1w0QCgB3AQAXAAkJ1w0QCgB3AQAAAA==.Spin:BAAALgADCgMJAwAAAA==.Spinecrawler:BAAALgAECgIJAgAAAA==.Spinjitzu:BAAALgAECgQJCwAAAA==.Spiritshift:BAAALgAECgEJAQAAAA==.Spyro:BAAALgAECgQJDgAAAA==.',
Sq='Squadw:BAACLgAFFH8aAAIVAAYJAhw2AgDFAQAVAAYJAhw2AgDFAQAuAAQKf0QAAhUACQkCJTkCAHMDABUACQkCJTkCAHMDAAAA.',
Ss='Sski:BAAALgADCgEJAQAAAA==.',
St='Starblast:BAAALgAECgYJEwABLgAECgYJBwATAAAAAA==.Starrskrream:BAAALgAECgQJBgAAAA==.Staryknight:BAAALgAECgEJAQAAAA==.Steamworks:BAAALgADCgcJBwAAAA==.Steelrat:BAAALgADCgcJAgAAAA==.Stellanova:BAAALgADCgQJBAAAAA==.Stiick:BAABLgAECn80AAIiAAkJ9RnGBwAzAgAiAAkJ9RnGBwAzAgAAAA==.Stormhide:BAAALgADCgEJAgAAAA==.Streakycat:BAEALgAECgEJAQAAAA==.Stupidgnome:BAAALgAECgkJCQAAAA==.Stìmpak:BAAALgAECgIJAgABLgAECgcJCAATAAAAAA==.',
Su='Subsizzle:BAAALgAECgMJAwABLgAECgcJEgATAAAAAA==.Subzerow:BAAALgADCgYJBgAAAA==.Sudsy:BAAALgAECggJCgAAAA==.Sujin:BAAALgAECgMJAwAAAA==.Sunarra:BAABLgAECn8dAAIWAAgJShwPKwD/AQAWAAgJShwPKwD/AQAAAA==.Sunsmite:BAABLgAECn8dAAIEAAcJrhbueABeAQAEAAcJrhbueABeAQAAAA==.Supadupaman:BAAALgAECgkJBgAAAA==.Suramar:BAABLgAECn8YAAIZAAgJAhVOFACGAQAZAAgJAhVOFACGAQAAAA==.',
Sw='Sweetbippy:BAABLgAECn8tAAIBAAkJdQKsrgALAQABAAkJdQKsrgALAQAAAA==.Swifthealss:BAABLgAECn8YAAMLAAgJfAbZXQD/AAALAAgJfAbZXQD/AAAKAAUJ3gpYTgCmAAAAAA==.Swirls:BAAALgAECgEJAgAAAA==.',
Sy='Sygvalden:BAAALgAECgYJDAABLgAECggJEwATAAAAAA==.Sylunae:BAAALgAECgIJBAABLgAECggJHgALAKsIAA==.Syluné:BAABLgAECn8eAAILAAgJqwjAaADcAAALAAgJqwjAaADcAAAAAA==.Syläs:BAAALgAECgYJEwAAAA==.Syndrassil:BAABLgAECn8iAAIBAAgJBwtpeABtAQABAAgJBwtpeABtAQAAAA==.',
['Sù']='Sùccubus:BAAALgADCgQJBAAAAA==.',
Ta='Tacodog:BAAALgAECgUJCgABLgAECgkJKQAEAEYmAA==.Tacomonk:BAAALgAECggJCgAAAA==.Tacozpriest:BAAALgAECgYJBgABLgAECggJCgATAAAAAA==.Taelight:BAAALgADCggJDgABLgAECgkJLAAIAKgXAA==.Taelyx:BAABLgAECn8sAAMIAAkJqBfkLgDPAQAIAAkJqBfkLgDPAQAPAAIJ3gkQfgBOAAAAAA==.Taicheeze:BAABLgAECn8dAAIHAAkJgxfPDgAwAgAHAAkJgxfPDgAwAgAAAA==.Tambot:BAAALgAECgQJDQAAAA==.Tariced:BAAALgAECgQJBAAAAA==.Tarvaron:BAAALgADCgEJAQAAAA==.Taytra:BAAALgADCgkJLgABLgAECgkJLQABAHUCAA==.Tazmina:BAACLgAFFH8HAAIVAAMJQhenDwD2AAAVAAMJQhenDwD2AAAuAAQKfysAAhUACQnLH/MHAOQCABUACQnLH/MHAOQCAAAA.',
Te='Teal:BAAALgADCgYJCgAAAA==.Tehssa:BAAALgAECgUJBgABLgAECgkJMwAPAJgcAA==.Tessa:BAABLgAECn8zAAIPAAkJmBzbCwCDAgAPAAkJmBzbCwCDAgAAAA==.Texasfight:BAAALgAECgEJAQABLgAECggJRAAJAPwYAA==.Teyo:BAAALgAECgQJDgAAAA==.',
Th='Thedoctorwho:BAABLgAECn8WAAIEAAkJpw+7QwDeAQAEAAkJpw+7QwDeAQAAAA==.Theholytaz:BAABLgAECn8XAAIEAAgJDBZkQQAhAgAEAAgJDBZkQQAhAgAAAA==.Thunderr:BAAALgAECgcJCAAAAA==.Thörn:BAABLgAECn8VAAMIAAgJ1A3jWwAXAQAIAAcJegvjWwAXAQAPAAIJGgVDgABDAAABLgAFFAMJBgALAAsPAA==.',
Ti='Tigs:BAAALgADCgMJAwAAAA==.Time:BAAALgAECgMJAwAAAA==.Tinyjapeto:BAAALgAECgMJAwAAAA==.Titanbow:BAAALgADCgYJBgABLgAECgkJMAAWALAfAA==.',
To='Tomcatt:BAABLgAECn9AAAISAAkJwiGbBwD/AgASAAkJwiGbBwD/AgAAAA==.Tonshaw:BAAALgAECgYJBgAAAA==.Toome:BAAALgADCgUJBQAAAA==.',
Tr='Trailis:BAAALgAECgMJBAAAAA==.Travalden:BAAALgADCgMJAwAAAA==.Trekkie:BAAALgAECgUJBQABLgAFFAYJHQAiAPURAA==.Treè:BAAALgAECgMJCgAAAA==.Trioxinn:BAAALgADCgEJAQAAAA==.',
Tu='Tuddlly:BAAALgAECgUJCgAAAA==.Turin:BAABLgAECn8mAAIZAAkJCwZZHQAjAQAZAAkJCwZZHQAjAQAAAA==.Turnip:BAAALgAECgUJBQABLgAFFAgJIAALALscAA==.Tutonik:BAAALgADCgUJBQAAAA==.Tuubarkk:BAAALgADCgcJCAAAAA==.',
Tw='Twilghtdawn:BAABLgAECn8rAAIhAAgJ4BcWEgDAAQAhAAgJ4BcWEgDAAQAAAA==.Twos:BAAALgAECgEJAQAAAA==.Twotone:BAAALgADCgMJAwAAAA==.',
Ty='Tybo:BAABLgAECn8vAAIjAAkJBCKLAQAFAwAjAAkJBCKLAQAFAwAAAA==.Tybs:BAAALgADCgEJAQAAAA==.',
Un='Uncás:BAABLgAECn8VAAISAAYJIgdZeAD+AAASAAYJIgdZeAD+AAAAAA==.Ungieblinks:BAAALgAECgQJBgAAAA==.Ungislayer:BAAALgADCgMJAwAAAA==.Unglifettv:BAABLgAECn8UAAImAAgJMReTGgDkAQAmAAgJMReTGgDkAQAAAA==.Unstable:BAAALgAECgQJBgABLgAECgcJBwATAAAAAA==.',
Up='Upchucky:BAAALgAECgMJAwAAAA==.',
Ur='Urulóki:BAAALgAECgcJBwAAAA==.',
Va='Vaedeath:BAABLgAECn81AAIhAAkJJiBwBwCCAgAhAAkJJiBwBwCCAgAAAA==.Vaina:BAAALgADCgMJAwAAAA==.Vainagos:BAAALgAECgUJBgAAAA==.Valaryon:BAAALgAECgYJBgAAAA==.Valkorin:BAAALgAECgYJBwAAAA==.Valoryan:BAABLgAECn9AAAILAAkJ6BUeGwBLAgALAAkJ6BUeGwBLAgAAAA==.Valyteilssra:BAAALgAECgMJCAAAAA==.Vanity:BAAALgAECgMJBAAAAA==.Varindra:BAAALgAECgMJBAABLgAECgkJGgAdAOAaAA==.Vasoline:BAAALgAECgkJCQAAAA==.',
Ve='Vegà:BAABLgAECn8hAAIHAAgJLRHNJABpAQAHAAgJLRHNJABpAQAAAA==.Veina:BAAALgADCgQJCAAAAA==.Velyndris:BAAALgAECgYJCwAAAA==.Velysia:BAAALgADCgMJAwAAAA==.Vendettis:BAAALgADCgYJBgAAAA==.Verin:BAAALgAECgMJBQAAAA==.Vetraugr:BAAALgADCgMJAwABLgAECgYJDQATAAAAAA==.Vextaerin:BAAALgAECgYJDQAAAA==.Vextarin:BAAALgADCgEJAQABLgAECgYJDQATAAAAAA==.Veylyn:BAAALgADCgEJAQAAAA==.',
Vi='Virulent:BAAALgADCgMJAwAAAA==.Vivienreed:BAAALgAECgEJAgABLgAFFAQJCwAlABUMAA==.',
Vo='Voidhax:BAAALgAECgUJBQAAAA==.Voidi:BAABLgAECn8XAAQaAAcJVyOsFQBiAgAaAAcJtCKsFQBiAgAkAAQJESEBDQBPAQAnAAEJtAOkDwAoAAAAAA==.Voidyo:BAACLgAFFH8MAAIWAAMJCh22QAD9AAAWAAMJCh22QAD9AAAuAAQKfxAAAhYACAmuHoczANoBABYACAmuHoczANoBAAAA.Voralyth:BAAALgADCggJCQAAAA==.Voranne:BAABLgAECn8pAAIGAAkJPApsIgCOAQAGAAkJPApsIgCOAQAAAA==.Vortice:BAABLgAECn9BAAQPAAkJTBF8IwChAQAPAAkJTBF8IwChAQAIAAgJKA7lTgBEAQAjAAIJQAfbKABOAAAAAA==.Vowwel:BAAALgAECgEJAQAAAA==.',
Vy='Vyserlai:BAAALgADCgUJBQAAAA==.',
Wa='War:BAAALgAECgYJBgAAAA==.Ware:BAAALgADCgcJBwAAAA==.Warraxgos:BAAALgADCgkJHgABLgAECgkJIgAVAHIdAA==.Warraxhunt:BAAALgAECgEJAQABLgAECgkJIgAVAHIdAA==.Warraxmonk:BAAALgADCgYJBgABLgAECgkJIgAVAHIdAA==.',
We='Weißenacht:BAAALgAECgMJAwAAAA==.',
Wh='Wheatstraw:BAAALgADCgYJDQAAAA==.Whiskeyjak:BAABLgAECn8gAAMZAAkJGxsiEgCjAQAZAAUJdR4iEgCjAQAJAAgJOg+WLgByAQAAAA==.',
Wi='Willowest:BAABLgAECn8tAAISAAkJVRrSFwBvAgASAAkJVRrSFwBvAgAAAA==.',
Wr='Wrathstorm:BAABLgAECn8oAAIjAAgJWh94BgBEAgAjAAgJWh94BgBEAgAAAA==.Wrekonhoof:BAAALgAECgEJAQAAAA==.',
Wt='Wtfpie:BAACLgAFFH8WAAIQAAUJsxc4GABEAQAQAAUJsxc4GABEAQAuAAQKfzQAAhAACQkqIzkRAMYCABAACQkqIzkRAMYCAAAA.',
Wu='Wurmoneonine:BAAALgADCgUJBQABLgAECgkJMAALAIYXAA==.Wurmy:BAABLgAECn8wAAMLAAkJhheWGgBPAgALAAkJhheWGgBPAgAKAAYJSBOFNgAOAQAAAA==.',
Wy='Wyndrunner:BAAALgADCgkJCQABLgAECgkJLQASAHQMAA==.',
['Wá']='Wárgbáte:BAAALgADCgcJBwAAAA==.',
Xa='Xalgas:BAABLgAECn8YAAIGAAYJaxaVKwB/AQAGAAYJaxaVKwB/AQAAAA==.Xanier:BAAALgAECgQJCAAAAA==.',
Xe='Xelagos:BAABLgAECn8fAAQUAAkJMRGrFQBQAQAUAAgJKhCrFQBQAQAlAAMJCBzBJgDsAAAmAAMJ5BWvUwB4AAAAAA==.Xerxesjr:BAAALgADCgEJAQAAAA==.',
Xi='Xioamara:BAAALgAECgQJAwAAAA==.',
Ya='Yanella:BAABLgAECn8nAAMCAAkJ3By6BwDQAgACAAkJ3By6BwDQAgADAAEJcwWmWgAtAAAAAA==.',
Yi='Yispally:BAAALgAECgQJCgAAAA==.Yisshaman:BAABLgAECn8eAAIPAAkJXhvZDADQAgAPAAkJXhvZDADQAgAAAA==.',
Yo='Yo:BAAALgAFFAEJAQABLgAFFAgJJQAZAJojAA==.Yogibearz:BAAALgAECgQJBwABLgAECgUJFAAHAJYQAA==.Yogimonk:BAABLgAECn8UAAIHAAUJlhB8RwDEAAAHAAUJlhB8RwDEAAAAAA==.',
Za='Zanax:BAAALgAECgcJCAAAAA==.Zandarbribbs:BAABLgAECn8dAAIEAAcJjBWmaQB+AQAEAAcJjBWmaQB+AQAAAA==.Zapzug:BAAALgADCgYJDQAAAA==.Zaratras:BAAALgAECgEJAQAAAA==.Zaydozer:BAAALgAECgQJBAAAAA==.',
Ze='Zenmetsu:BAAALgAECgUJBgAAAA==.Zennya:BAABLgAECn8kAAILAAgJMhgkJQADAgALAAgJMhgkJQADAgAAAA==.Zeon:BAAALgAECgYJEQAAAA==.',
Zi='Zikoth:BAAALgADCgEJAQAAAA==.Zingers:BAAALgAECgMJAwAAAA==.',
Zm='Zmd:BAAALgAECgYJEQAAAA==.',
Zo='Zoeso:BAABLgAECn83AAMHAAkJfx89BQDTAgAHAAkJfx89BQDTAgAdAAUJyQ65SwDpAAAAAA==.',
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
