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

local lookup = {'Evoker-Preservation','Mage-Frost','DemonHunter-Devourer','Shaman-Restoration','Druid-Balance','Evoker-Augmentation','Druid-Guardian','Druid-Feral','Priest-Shadow','Priest-Discipline','Unknown-Unknown','Warlock-Demonology','Hunter-Survival','DeathKnight-Blood','Paladin-Retribution','Paladin-Holy','Warlock-Affliction','DemonHunter-Havoc','Priest-Holy','Hunter-BeastMastery','Hunter-Marksmanship','Monk-Mistweaver','Druid-Restoration','Rogue-Subtlety','Warrior-Protection','Monk-Windwalker','Mage-Arcane','Shaman-Elemental','DeathKnight-Frost','DeathKnight-Unholy','Monk-Brewmaster','Warrior-Fury','Warrior-Arms','Rogue-Assassination','Rogue-Outlaw','DemonHunter-Vengeance','Paladin-Protection','Warlock-Destruction','Evoker-Devastation','Mage-Fire','Shaman-Enhancement',}
local provider = {region='US',realm='Llane',name='US',type='weekly',zone=46,date='2026-06-13',data={Ab='Abdervoke:BAABLgAECn8fAAIBAAkJRyLsAQBkAwABAAkJRyLsAQBkAwAAAA==.Absent:BAAALgADCgEJAQAAAA==.',
Ac='Account:BAAALgADCgIJAgAAAA==.',
Ae='Aeila:BAAALgADCgYJBgAAAA==.Aethos:BAAALgAECgkJBQAAAA==.',
Ah='Ahsoul:BAAALgAECgEJAgAAAA==.',
Al='Alesia:BAAALgADCgEJAQAAAA==.Alessaah:BAAALgADCgcJCgAAAA==.Aliadra:BAABLgAECn8zAAICAAkJSSL5DgAAAwACAAkJSSL5DgAAAwAAAA==.Alistus:BAACLgAFFH8NAAIDAAQJoSITJgCKAQADAAQJoSITJgCKAQAuAAQKfz4AAgMACQn/JJgDAEsDAAMACQn/JJgDAEsDAAAA.Alphá:BAAALgAECgUJCQABLgAFFAMJBQAEAAALAA==.Altholar:BAAALgADCgcJBwAAAA==.',
An='Anexxia:BAAALgAECgQJCQAAAA==.Angel:BAAALgAECgYJDwAAAA==.Angua:BAABLgAECn9LAAIFAAkJQRqyDgBvAgAFAAkJQRqyDgBvAgAAAA==.',
Ar='Arcanegarm:BAABLgAECn8bAAICAAcJIAIw/ACuAAACAAcJIAIw/ACuAAAAAA==.Archeyois:BAABLgAECn8pAAMGAAkJVA8nKgCVAQAGAAkJVA8nKgCVAQABAAUJhQIRNwCzAAAAAA==.Armitage:BAABLgAECn8YAAMHAAkJ/w8LHABnAQAHAAkJXQ8LHABnAQAIAAcJQgtSHgAQAQAAAA==.Arthonos:BAACLgAFFH8GAAIJAAIJVAV2MgBzAAAJAAIJVAV2MgBzAAAuAAQKfzUAAwkACQmaFTEYAAQCAAkACQmaFTEYAAQCAAoACAnjBWQnAFoBAAAA.Arugall:BAAALgAECgYJBgAAAA==.',
As='Ashmall:BAAALgAECgQJBAAAAA==.',
Av='Averille:BAAALgADCgYJCwAAAA==.',
Ay='Ayraa:BAAALgAECgYJBAAAAA==.',
Az='Azerphage:BAAALgAECgYJDwABLgAECgcJCwALAAAAAA==.Azeura:BAAALgADCgQJBAAAAA==.Azhorra:BAABLgAECn8VAAIMAAYJOwqOrADqAAAMAAYJOwqOrADqAAAAAA==.Azzog:BAAALgAECgcJEgAAAA==.Azül:BAAALgAECgQJBAABLgAECgcJCwALAAAAAA==.',
Ba='Bacchanalian:BAAALgAECgcJDAABLgAECgkJCwALAAAAAA==.Baindyn:BAAALgAECgQJEwAAAA==.Barator:BAAALgAECgYJCgAAAA==.Bas:BAAALgAECgUJCQAAAA==.',
Bi='Bickkbatwolf:BAAALgADCgYJDQAAAA==.Bigwhisky:BAAALgAECgcJEAAAAA==.',
Bl='Blackröse:BAABLgAECn8jAAINAAgJMx0rEAAuAgANAAgJMx0rEAAuAgAAAA==.Blackrøse:BAABLgAECn8cAAIEAAkJtQ5GOgDBAQAEAAkJtQ5GOgDBAQABLgAECggJIwANADMdAA==.Bladebane:BAABLgAECn8lAAIOAAkJGgEWPACeAAAOAAkJGgEWPACeAAAAAA==.Blandmonk:BAAALgAECgMJAwAAAA==.Blksunshine:BAAALgAECgYJCgAAAA==.',
Bo='Bolash:BAAALgAECgYJCwAAAA==.Bort:BAAALgAECgEJBAAAAA==.',
Br='Bradthomas:BAAALgAECgQJBQAAAA==.Breegorn:BAAALgAECgUJBgAAAA==.Breni:BAAALgAFFAEJAQAAAA==.Bruscha:BAAALgAECgUJDwAAAA==.',
Bu='Bulvhine:BAABLgAECn8oAAIPAAgJiiA8HgCOAgAPAAgJiiA8HgCOAgAAAA==.',
Ca='Camferd:BAAALgAECgEJAQAAAA==.Camford:BAABLgAECn8ZAAICAAcJ8QhZvQBoAQACAAcJ8QhZvQBoAQAAAA==.Cantatrix:BAABLgAECn8bAAIMAAYJ9gvDoAD9AAAMAAYJ9gvDoAD9AAAAAA==.Capslok:BAAALgAECgYJDQAAAA==.Captinmeat:BAAALgAECgIJBAAAAA==.Cashkin:BAAALgADCgYJBgAAAA==.Cassiela:BAAALgAECgYJBgABLgAECgkJCwALAAAAAA==.',
Ce='Cecilx:BAABLgAECn8yAAIQAAkJ7yNSAgCHAwAQAAkJ7yNSAgCHAwAAAA==.Cellybelleri:BAAALgADCgUJCAAAAA==.',
Ch='Chaac:BAAALgADCgEJAQAAAA==.Charmander:BAAALgADCgcJCAAAAA==.Chayton:BAAALgADCgUJBQAAAA==.Cherrypie:BAAALgAECgYJBgAAAA==.Chillana:BAAALgAECgQJBAAAAA==.Chimerax:BAACLgAFFH8XAAMRAAUJPyBRAgCFAQARAAUJPyBRAgCFAQAMAAEJlxd3vQBHAAAuAAQKfy0AAxEACQljHwACALACABEACAlCIgACALACAAwACAlDE515AEUBAAAA.Chloede:BAAALgADCgUJBQAAAA==.Chlorpyrifos:BAAALgADCgEJAQAAAA==.Chrismikea:BAABLgAECn8cAAIPAAgJMAZQoQA9AQAPAAgJMAZQoQA9AQAAAA==.Chronic:BAAALgAECgQJBwAAAA==.Chully:BAACLgAFFH8PAAIDAAQJZRBQRgAPAQADAAQJZRBQRgAPAQAuAAQKfywAAwMACQkIG8opAB8CAAMACQkIG8opAB8CABIAAwmIBM1ZAH0AAAAA.',
Cl='Clairíty:BAABLgAECn8eAAITAAgJoh67DQCHAgATAAgJoh67DQCHAgAAAA==.Clarky:BAAALgAECgYJEAAAAA==.Click:BAABLgAECn9EAAIUAAkJUxw8EwC0AgAUAAkJUxw8EwC0AgAAAA==.Cloutfarmer:BAACLgAFFH8QAAIUAAQJGyCpJgBjAQAUAAQJGyCpJgBjAQAuAAQKf0AABBQACQlKJb0EAEMDABQACQlKJb0EAEMDABUABgkZHFspAOABAA0AAglFHe5UAFUAAAAA.',
Co='Comadore:BAACLgAFFH8OAAIPAAUJhApvVwD7AAAPAAUJhApvVwD7AAAuAAQKfxwAAg8ACAk4HNg4AEACAA8ACAk4HNg4AEACAAAA.Coronae:BAAALgAECgEJAQAAAA==.',
Cr='Crankshanker:BAAALgAECgEJAQAAAA==.Cratora:BAAALgAECgYJBgAAAA==.Credan:BAEBLgAECn8VAAIWAAkJMyLrBQBFAwAWAAkJMyLrBQBFAwABLgADCgYJBgALAAAAAA==.Critmypants:BAAALgAECgIJAgAAAA==.',
Cy='Cylithina:BAAALgAECgQJBwAAAA==.Cytochrome:BAAALgADCgQJBAAAAA==.',
Da='Daphe:BAAALgAECgEJAwAAAA==.Dawggbiscuit:BAAALgAECgQJBQAAAA==.',
De='Deadiam:BAAALgAECgEJAQAAAA==.Deadseksi:BAAALgAECgcJDQAAAA==.Deathslead:BAABLgAECn8yAAMUAAgJkRRhQgDXAQAUAAgJkRRhQgDXAQAVAAUJ3AEsMQBSAAAAAA==.Decrepe:BAACLgAFFH8RAAIXAAQJ2Bg6JgAiAQAXAAQJ2Bg6JgAiAQAuAAQKfzsAAhcACQlIIEwKABUDABcACQlIIEwKABUDAAAA.Dedrepe:BAAALgAECggJCQAAAA==.Delph:BAAALgAECgkJEwAAAA==.Deshal:BAAALgAECgMJBAAAAA==.Desomas:BAAALgAECgIJAgAAAA==.Dethklock:BAAALgAECgEJAQAAAA==.',
Di='Dieurnal:BAAALgAECgQJAQAAAA==.Discostar:BAABLgAECn8oAAMXAAgJohkHLgDsAQAXAAcJghgHLgDsAQAFAAYJiBJILgBkAQAAAA==.Distill:BAAALgAECgEJAQABLgAFFAkJGgAYAGYgAA==.',
Dn='Dni:BAAALgAECgMJBAABLgAECgkJLwAFAMAbAA==.',
Do='Dominicm:BAAALgAECgYJEgAAAA==.Dotdotdis:BAAALgAECgMJAwAAAA==.',
Dr='Dracanalian:BAAALgADCgkJCQAAAA==.Drajhar:BAAALgAECgkJBQAAAA==.Drakyore:BAAALgADCgIJAwAAAA==.Draq:BAAALgAECgYJCgAAAA==.Druth:BAABLgAECn8tAAIZAAgJRx90CgBEAgAZAAgJRx90CgBEAgAAAA==.',
Eb='Ebonhorn:BAAALgAECgUJEQAAAA==.',
Ee='Eevillean:BAAALgAECgEJAQAAAA==.',
Ei='Einari:BAAALgAECggJCAAAAA==.Einark:BAABLgAECn88AAMWAAkJjR92CAARAwAWAAkJjR92CAARAwAaAAgJzB7xDABzAgAAAA==.',
Ek='Ekiim:BAAALgAECgQJBAABLgAECgQJCQALAAAAAA==.',
El='Eldrond:BAAALgAECgQJCAABLgAECgUJCQALAAAAAA==.Elinis:BAAALgAFFAEJAQAAAA==.Elska:BAAALgADCgkJCQAAAA==.',
En='Ennauríon:BAAALgAECgUJCQAAAA==.Entropy:BAEALgAFFAIJAgABLgAFFAMJBwAbADUOAA==.',
Er='Eridor:BAAALgAECgYJEAAAAA==.',
Ex='Exek:BAABLgAECn8tAAMTAAgJExfRFgAWAgATAAgJExfRFgAWAgAJAAUJWQs2UwDCAAAAAA==.',
Ez='Ez:BAAALgAECgEJAQABLgAECgkJLQAcABUbAA==.',
Fa='Fabaztard:BAABLgAECn8jAAIFAAgJdxTIIgCwAQAFAAgJdxTIIgCwAQAAAA==.Faline:BAABLgAECn8zAAIXAAkJUwvpRAB6AQAXAAkJUwvpRAB6AQAAAA==.',
Fe='Felgetabouit:BAACLgAFFH8XAAIDAAUJUhPxRwALAQADAAUJUhPxRwALAQAuAAQKfyMAAgMACQlUGs00ACUCAAMACQlUGs00ACUCAAAA.Felghoul:BAAALgAECgcJDQAAAA==.Felldozer:BAAALgAECgEJAQAAAA==.Fenrakar:BAAALgAECgQJBwAAAA==.Feywynn:BAAALgAECggJBwAAAA==.',
Fi='Fights:BAABLgAECn84AAIQAAkJKR7ZCQDsAgAQAAkJKR7ZCQDsAgAAAA==.',
Fl='Fleshworker:BAAALgADCgEJAQAAAA==.',
Fo='Fordalliance:BAAALgADCgcJBwAAAA==.Forky:BAAALgAECgQJCAAAAA==.Foxknight:BAABLgAECn8UAAQdAAUJaxB3GQADAQAdAAUJaxB3GQADAQAeAAMJ7AtvDgGVAAAOAAQJ4QPQSQBkAAAAAA==.',
Fr='Franciss:BAAALgAECgYJDQAAAA==.Francys:BAAALgADCgIJAwAAAA==.Franksnbeans:BAAALgAECgEJAgABLgAECgYJEgALAAAAAA==.',
Ft='Ftx:BAABLgAECn8gAAMfAAgJuh+oDQC4AgAfAAgJlR+oDQC4AgAaAAQJ2hm/RgD6AAAAAA==.',
Fu='Fubbleskag:BAABLgAECn8xAAIPAAkJARxENwAiAgAPAAkJARxENwAiAgAAAA==.Fullmoonn:BAAALgAECgIJAwAAAA==.',
Ga='Gaern:BAAALgAECgEJAwABLgAFFAEJAQALAAAAAA==.Gaidan:BAACLgAFFH8MAAIFAAUJ5wtgKADrAAAFAAUJ5wtgKADrAAAuAAQKfyEAAgUACQmlFogRAI8CAAUACQmlFogRAI8CAAEuAAUUBwkOAAMAiwkA.Gaidin:BAACLgAFFH8OAAIDAAcJiwkzKgB1AQADAAcJiwkzKgB1AQAuAAQKfx4AAgMACAkCGj08ANMBAAMACAkCGj08ANMBAAAA.Gameslayer:BAABLgAECn8gAAMgAAkJcB0gKwCoAQAgAAYJcx8gKwCoAQAhAAQJzxdYMAADAQAAAA==.Gankzilla:BAACLgAFFH8XAAMYAAUJHRbUGABGAQAYAAUJHRbUGABGAQAiAAEJbBGNEABOAAAuAAQKfycAAyIACQmeG2EJAKoBABgABgl3GNklAMoBACIABwkfG2EJAKoBAAAA.Garothos:BAAALgAECgIJAgABLgAECgQJBwALAAAAAA==.Gatanikaz:BAAALgAECgIJBAAAAA==.',
Ge='Genrealwee:BAAALgAECgEJAQAAAA==.Get:BAAALgADCgkJDAAAAA==.',
Gh='Ghalumvhar:BAABLgAECn8fAAIPAAcJBRsKTgDbAQAPAAcJBRsKTgDbAQAAAA==.Ghoulaid:BAAALgAECgcJBwAAAA==.Ghrìmm:BAABLgAECn8lAAQNAAkJ6w8tGgDNAQANAAkJIA0tGgDNAQAUAAgJxA5AZwBwAQAVAAEJ+QZVQwAiAAAAAA==.',
Gi='Gila:BAAALgAECggJDwAAAA==.Gingasorrow:BAABLgAECn8wAAIXAAkJcRgHGgByAgAXAAkJcRgHGgByAgAAAA==.Gizzle:BAACLgAFFH8QAAIPAAUJpg3MVQD+AAAPAAUJpg3MVQD+AAAuAAQKfyYAAg8ACQmoFjBUAMsBAA8ACQmoFjBUAMsBAAAA.',
Gr='Greekfire:BAABLgAECn8YAAIQAAgJ3yE5GwA7AgAQAAgJ3yE5GwA7AgAAAA==.Grishna:BAAALgADCggJCAAAAA==.Grumrok:BAAALgAECgQJBgAAAA==.Grunbar:BAABLgAECn8uAAIUAAcJYyLxLAAlAgAUAAcJYyLxLAAlAgAAAA==.Grændal:BAAALgAECgcJEAABLgAFFAcJDgADAIsJAA==.',
Ha='Hanjha:BAABLgAECn9HAAMNAAkJkR+hAwD7AgANAAgJkR+hAwD7AgAUAAEJAAA7zwA3AAAAAA==.Hatz:BAAALgADCgcJBgAAAA==.',
He='Healshot:BAAALgADCgMJAwABLgAECgUJFQAPAGUmAA==.Helldozer:BAABLgAECn9JAAMcAAkJLxaZFwAlAgAcAAkJLxaZFwAlAgAEAAIJzxR7pAB9AAAAAA==.',
Ho='Hooj:BAAALgADCgYJBgAAAA==.Horde:BAAALgADCgEJAQAAAA==.',
Ht='Ht:BAAALgADCgMJCAAAAA==.',
Hu='Hugzy:BAAALgAECgYJCwAAAA==.',
Hw='Hwore:BAAALgAECgQJBAAAAA==.',
Hy='Hydatos:BAAALgADCgMJAwABLgAECgYJCgALAAAAAA==.Hypnocide:BAEBLgAECn9AAAIDAAkJkRbHLQANAgADAAkJkRbHLQANAgAAAA==.',
['Hô']='Hôneynuts:BAAALgADCgIJAgAAAA==.',
Ib='Ibuki:BAAALgAECgYJEgABLgAFFAUJFwAQAFQGAA==.',
Ic='Icepick:BAAALgADCgIJAgAAAA==.',
Id='Idleorc:BAAALgADCgcJDQAAAA==.',
Ig='Iguanajon:BAAALgAECgEJAgAAAA==.',
Il='Illandren:BAACLgAFFH8RAAINAAQJlgiKFwARAQANAAQJlgiKFwARAQAuAAQKfxsAAw0ACQljC3kcALkBAA0ACQljC3kcALkBABUACAk6A1ofALEAAAAA.Illusiveeyes:BAAALgADCgYJDAAAAA==.',
Im='Impsane:BAABLgAECn8jAAIMAAkJBw6PTQCxAQAMAAkJBw6PTQCxAQAAAA==.',
In='Incøgnitø:BAAALgAECgEJAQABLgAECggJGwAXAK4cAA==.Infernis:BAAALgADCgYJCQAAAA==.Innphyy:BAABLgAECn8jAAICAAcJsQiuwAAFAQACAAcJsQiuwAAFAQAAAA==.Innøminate:BAABLgAECn8ZAAIUAAYJpA4UjQAgAQAUAAYJpA4UjQAgAQABLgAECggJGwAXAK4cAA==.Inti:BAAALgADCgEJAQAAAA==.',
Ir='Irv:BAABLgAECn8WAAQiAAgJlhpwBwDfAQAiAAgJ5xlwBwDfAQAYAAUJoxxSMwBwAQAjAAQJjg9mCQDZAAAAAA==.',
Is='Isadavrah:BAAALgADCgcJDAAAAA==.Isekai:BAAALgAECgQJBgAAAA==.Issadin:BAAALgAECgUJBwABLgAECgYJDAALAAAAAA==.Issadruiid:BAAALgADCgYJBgABLgAECgYJDAALAAAAAA==.Issammonk:BAAALgAECgEJAQABLgAECgYJDAALAAAAAA==.Issarage:BAAALgAECgQJCQABLgAECgYJDAALAAAAAA==.Issashammy:BAAALgAECgYJDAAAAA==.',
Ja='Jaxxa:BAABLgAECn88AAIUAAkJ6xqHHgBrAgAUAAkJ6xqHHgBrAgAAAA==.',
Je='Jeddiah:BAABLgAECn8jAAMiAAcJIQ+1DQBJAQAiAAcJIQ+1DQBJAQAYAAQJRgoWRgCdAAAAAA==.',
Jh='Jhals:BAAALgADCgYJBgAAAA==.',
Ji='Jiffarous:BAAALgAECgQJBwAAAA==.Jinkès:BAABLgAECn8nAAIVAAYJkRMbEwApAQAVAAYJkRMbEwApAQAAAA==.',
Jp='Jpank:BAAALgAFFAEJAwAAAA==.',
Ju='Jubei:BAABLgAFFH8HAAIPAAYJbgpQfAC1AAAPAAYJbgpQfAC1AAAAAA==.Judis:BAABLgAECn9TAAIiAAkJRR+yAQDiAgAiAAkJRR+yAQDiAgAAAA==.Judyth:BAAALgAECgIJBQAAAA==.Juicy:BAAALgADCgIJAgAAAA==.Justokevoker:BAABLgAFFH8LAAIGAAQJpxHJMAD8AAAGAAQJpxHJMAD8AAAAAA==.',
Ka='Kainel:BAAALgAECgkJCQAAAA==.Kairì:BAAALgADCgcJDQAAAA==.Kalifist:BAABLgAECn8cAAIaAAkJnR9NCADAAgAaAAkJnR9NCADAAgAAAA==.Kalinear:BAAALgADCgQJBQAAAA==.Kalipally:BAAALgAECgcJDgAAAA==.Kaliscales:BAAALgAECgUJBQAAAA==.Kamiportal:BAAALgAECgcJCgAAAA==.Kanajotoma:BAAALgAECgUJEgAAAA==.Karlai:BAABLgAECn8oAAMdAAgJZRrlBAAAAgAdAAcJuhrlBAAAAgAeAAUJGBKi3ADVAAABLgAFFAcJDgADAIsJAA==.Kaslana:BAEALgADCgYJBgAAAA==.',
Ke='Keldrune:BAAALgAECgYJDAAAAA==.Keleena:BAEBLgAECn9NAAIQAAkJbh/4CAD5AgAQAAkJbh/4CAD5AgAAAA==.Kelume:BAAALgADCgMJAwAAAA==.Kely:BAAALgADCgUJBgAAAA==.',
Kg='Kgor:BAAALgAECgcJBwAAAA==.',
Kh='Khaerne:BAAALgAECgEJAQABLgAFFAEJAQALAAAAAA==.Khordelia:BAAALgAFFAEJAQAAAA==.',
Ki='Kinst:BAABLgAECn89AAMUAAkJax6FEQDCAgAUAAkJax6FEQDCAgAVAAYJrxLaPwBbAQAAAA==.Kirigaya:BAAALgAECgMJCAAAAA==.Kisäi:BAABLgAECn8pAAMDAAkJ1RxbIACPAgADAAkJ1RxbIACPAgAkAAIJHBHtJwBiAAAAAA==.Kitanyia:BAABLgAECn8bAAIgAAkJlAqLTQAQAQAgAAkJlAqLTQAQAQAAAA==.Kittiy:BAABLgAECn8xAAMFAAgJJAbKRAD1AAAFAAgJJAbKRAD1AAAXAAYJKgddewDDAAAAAA==.',
Ko='Kordelia:BAABLgAECn8mAAICAAkJJh9sHgCkAgACAAkJJh9sHgCkAgABLgAFFAEJAQALAAAAAA==.Korvus:BAAALgAECgcJEQAAAA==.',
Kv='Kv:BAAALgADCggJCAAAAA==.',
Ky='Kyakuna:BAAALgAECgIJAgAAAA==.Kylnara:BAAALgAECgUJCQAAAA==.Kyloon:BAAALgAECgEJAQAAAA==.Kyrah:BAABLgAECn80AAMRAAkJHBnLBgDrAQAMAAkJIhUbMwALAgARAAYJ3xvLBgDrAQAAAA==.',
La='Lamanira:BAAALgAECgYJCgAAAA==.Lancier:BAAALgAECgYJCgAAAA==.',
Le='Lecleme:BAACLgAFFH8GAAIeAAMJZBH9mgDYAAAeAAMJZBH9mgDYAAAuAAQKfyEAAh4ACAleGB5HAOoBAB4ACAleGB5HAOoBAAAA.Lejend:BAABLgAECn9BAAMhAAkJyCXVAAByAwAhAAkJyCXVAAByAwAgAAMJfRW8fwC+AAAAAA==.Lenthalis:BAAALgAECgUJDAAAAA==.Lezriel:BAAALgAECgMJBgAAAA==.',
Li='Lichin:BAAALgADCgEJAQAAAA==.Lilithh:BAAALgADCgUJCAAAAA==.',
Ll='Llanedh:BAAALgAECggJDAAAAA==.',
Lo='Loaganic:BAAALgAECgQJBAABLgAECggJFAAGAOsLAA==.Lockheéd:BAAALgAFFAEJAQAAAA==.Lonelyhearts:BAABLgAECn89AAIPAAkJrQt0cACKAQAPAAkJrQt0cACKAQAAAA==.Lonestar:BAAALgAECgYJDwAAAA==.Lonestarr:BAAALgAECgQJDAAAAA==.Loxricia:BAAALgADCgEJAQAAAA==.',
Lu='Lumiya:BAABLgAECn8yAAITAAkJ7w52LwCFAQATAAkJ7w52LwCFAQAAAA==.',
Ly='Lytol:BAABLgAECn8qAAMbAAkJtRd1AgApAgAbAAkJtRd1AgApAgACAAMJXgRxHgF1AAAAAA==.',
Ma='Machu:BAAALgADCgIJAgABLgAFFAQJCwAGANkVAA==.Madderhorn:BAAALgAECgcJBQAAAA==.Maenad:BAAALgAECgkJCwAAAA==.Maeple:BAABLgAECn8pAAMTAAkJ+SEKBABEAwATAAkJ+SEKBABEAwAKAAMJugpgXACHAAAAAA==.Magikin:BAAALgAECgQJCAAAAA==.Mamichula:BAAALgAECgEJAQAAAA==.',
Mb='Mbdtf:BAACLgAFFH8WAAMNAAYJxR9rBQCxAQANAAUJlCZrBQCxAQAVAAEJjAS6JABVAAAuAAQKfxsAAw0ABwmMJXMEANQCAA0ABwkxJXMEANQCABUAAQksIwR3AGMAAAEuAAUUCAkoAAIA0CMA.',
Me='Mechagnome:BAACLgAFFH8GAAIaAAIJoBt8LACRAAAaAAIJoBt8LACRAAAuAAQKfzQAAxoACQnUIKIHAMwCABoACQnUIKIHAMwCABYACAkJBAU6AAABAAAA.Meeps:BAAALgADCgcJBwAAAA==.Megamedes:BAABLgAECn8aAAMPAAYJkhbKegCEAQAPAAYJEhbKegCEAQAlAAQJTQk5NgCEAAAAAA==.Meigna:BAABLgAECn8qAAIJAAgJuR1jEQBLAgAJAAgJuR1jEQBLAgAAAA==.Mekö:BAAALgAECgYJDQAAAA==.Meladyn:BAACLgAFFH8pAAMIAAYJ9iJHBABzAQAIAAUJeyNHBABzAQAHAAUJMh6VCABiAQAuAAQKfygAAwgABwlnJlYDAAMDAAgABwlnJlYDAAMDAAcABQnrI1gWAJsBAAAA.Melritza:BAAALgAECgQJCAAAAA==.Mentock:BAABLgAECn8YAAICAAYJ4hB1qQApAQACAAYJ4hB1qQApAQAAAA==.Merelandra:BAAALgADCggJFwAAAA==.Mermaid:BAAALgAECgUJCgAAAA==.',
Mi='Miliara:BAAALgADCgEJAQAAAA==.Missmaam:BAAALgAECgcJEQAAAA==.Mistroot:BAAALgAECgIJAwAAAA==.Mithrandir:BAACLgAFFH8FAAMMAAIJxwDWvwBFAAAMAAIJxwDWvwBFAAAmAAEJOQDNLAATAAAuAAQKfyAAAgwABwmWEMZvAFoBAAwABwmWEMZvAFoBAAAA.Mixcoati:BAAALgADCgQJBQAAAA==.Mizu:BAABLgAECn8cAAMZAAkJyxvQDgD5AQAZAAkJyxvQDgD5AQAgAAIJ6xAGlABvAAAAAA==.',
Mo='Moe:BAAALgAECgkJBAAAAA==.Monkfox:BAAALgAECgcJBwAAAA==.Morgianna:BAAALgADCgEJAQAAAA==.',
Mu='Mudflap:BAAALgAECgYJEQAAAA==.Mushuwoonter:BAAALgAECgEJAQABLgAFFAQJCwAGANkVAA==.Muztang:BAABLgAECn9CAAMhAAkJ1x5PBADVAgAhAAkJ1x5PBADVAgAgAAYJihN6TAAUAQAAAA==.',
Mw='Mwmmwmm:BAAALgAECgYJCQAAAA==.',
My='Mythandwel:BAABLgAECn8qAAISAAgJiAjOLAAWAQASAAgJiAjOLAAWAQAAAA==.',
['Mä']='Mäddiey:BAAALgAECgQJCgAAAA==.',
['Mô']='Mônkii:BAACLgAFFH8TAAIfAAQJESXTDQCzAQAfAAQJESXTDQCzAQAuAAQKfz4AAx8ACQnjJJ0CAC8DAB8ACQnjJJ0CAC8DABYAAQmvAtzXABEAAAAA.',
Na='Nace:BAABLgAECn8qAAIYAAkJ7BOvGQA2AgAYAAkJ7BOvGQA2AgAAAA==.Nadriede:BAAALgADCgYJBgAAAA==.Naenia:BAAALgAECgUJBQAAAA==.Naillimixam:BAAALgADCgMJAgAAAA==.Nariar:BAAALgAECgMJAwABLgAFFAUJFwAQAFQGAA==.Nateldin:BAABLgAECn8YAAMPAAkJhwmIkABbAQAPAAkJ8AeIkABbAQAlAAIJ9Q5vUQArAAAAAA==.',
Ne='Neoba:BAAALgAECgMJBQAAAA==.',
Ni='Nicksevokerc:BAAALgAECggJBwAAAA==.Niisha:BAAALgAECggJDQABLgAECgkJHwATAKMHAA==.Nikiso:BAAALgADCgYJBwAAAA==.',
No='Nocainus:BAABLgAECn9NAAIOAAkJwCFsAwAIAwAOAAkJwCFsAwAIAwAAAA==.Nosehole:BAABLgAECn8hAAIEAAcJ0hTGOwC7AQAEAAcJ0hTGOwC7AQAAAA==.Novari:BAAALgADCgkJCQAAAA==.',
Nv='Nv:BAAALgADCgEJAQABLgAFFAUJBQAaAGgFAA==.',
['Nø']='Nøtsure:BAABLgAECn8bAAMXAAgJrhxfJQAfAgAXAAgJrhxfJQAfAgAFAAIJqwyhcgBdAAAAAA==.',
Ob='Obesityy:BAABLgAECn8xAAIYAAkJph5ICACgAgAYAAkJph5ICACgAgAAAA==.Obsidia:BAABLgAECn8oAAIMAAkJSQ9nSQC9AQAMAAkJSQ9nSQC9AQAAAA==.',
Oc='Octopusprime:BAAALgAECgkJEQAAAA==.',
Ol='Ollix:BAEALgAECgEJBAABLgAECgkJTAADAI4eAA==.',
Om='Omelette:BAABLgAECn8fAAIUAAkJiRwNGwB+AgAUAAkJiRwNGwB+AgAAAA==.',
On='Onik:BAAALgADCgcJDQABLgAECgUJCQALAAAAAA==.',
Or='Orangejulius:BAAALgAECgQJCQAAAA==.Orangutan:BAAALgAECgQJBQAAAA==.Oriclysmic:BAABLgAECn8iAAQBAAgJ5h2tBwB2AgABAAgJ5h2tBwB2AgAGAAQJhQSiTwCPAAAnAAEJAAAjPwAzAAAAAA==.Oriigami:BAAALgAECgQJBwAAAA==.Orinoheal:BAAALgAECgYJBgAAAA==.',
Os='Oshtudead:BAAALgADCgQJBAAAAA==.',
Pe='Perilous:BAAALgAECgUJDwAAAA==.Pewpëw:BAAALgADCgkJDwAAAA==.',
Ph='Phalix:BAAALgAECgIJAwAAAA==.Phat:BAAALgAECgQJBQAAAA==.Phoelar:BAAALgAECgcJDgAAAA==.Phuumyn:BAABLgAECn9FAAIaAAkJTyU7AQBpAwAaAAkJTyU7AQBpAwAAAA==.',
Pi='Piccoblast:BAACLgAFFH8cAAICAAcJyhQSDQCzAQACAAcJyhQSDQCzAQAuAAQKfy0AAgIACAnYIuEcAAIDAAIACAnYIuEcAAIDAAAA.Piccolocks:BAAALgAECgYJCwABLgAFFAcJHAACAMoUAA==.Piccopew:BAAALgAECgEJAQABLgAFFAcJHAACAMoUAA==.Pichus:BAAALgAECgEJAQABLgAFFAMJBQAEAAALAA==.Picklesoup:BAAALgAECgcJCQAAAA==.Pierrecurzi:BAAALgAFFAEJAQABLgAFFAQJFQAVABcfAA==.Piickles:BAACLgAFFH8pAAMTAAcJ/Ba2BQD4AQATAAcJ/Ba2BQD4AQAKAAQJuxIVJQAZAQAuAAQKfx8AAhMABwndItoLAJMCABMABwndItoLAJMCAAAA.Pinkcanibus:BAABLgAECn8aAAIUAAgJvQSzbwAZAQAUAAgJvQSzbwAZAQAAAA==.Pippopper:BAAALgAECgEJAQABLgAFFAQJDQADAKEiAA==.Pity:BAABLgAECn8XAAIDAAkJjg1jUACRAQADAAkJjg1jUACRAQAAAA==.',
Pl='Plutø:BAABLgAECn9AAAMOAAkJdhoMDABRAgAOAAcJth4MDABRAgAeAAkJghIPTwDTAQAAAA==.',
Po='Polylocks:BAAALgAECggJEwAAAA==.Pompey:BAAALgAECgEJAQAAAA==.',
Pr='Praeastra:BAECLgAFFH8HAAIbAAMJNQ5sAgDLAAAbAAMJNQ5sAgDLAAAuAAQKfyoAAhsACAmMF8YDANABABsACAmMF8YDANABAAAA.Praycation:BAAALgAECgYJBgAAAA==.Promethius:BAAALgAECgcJCQABLgAFFAIJBQAMAMcAAA==.Protein:BAABLgAECn8gAAIgAAcJ0BWXOwBWAQAgAAcJ0BWXOwBWAQAAAA==.Prplxd:BAAALgADCgUJBQABLgAECgYJCgALAAAAAA==.Prókill:BAAALgADCgcJBwAAAA==.',
Ps='Psychokitty:BAABLgAECn9JAAIXAAkJER3iDAD0AgAXAAkJER3iDAD0AgAAAA==.',
Py='Pyppi:BAAALgADCgEJAQABLgAECggJEwALAAAAAA==.',
['Pô']='Pôwersm:BAAALgADCgMJAwAAAA==.',
Qu='Quiet:BAAALgAECgQJBAAAAA==.Quilian:BAACLgAFFH8WAAITAAUJdCQzBQAHAgATAAUJdCQzBQAHAgAuAAQKfyYAAhMACQlAISkEABIDABMACQlAISkEABIDAAAA.',
Ra='Raelynn:BAABLgAECn9NAAITAAkJvBkFDACjAgATAAkJvBkFDACjAgAAAA==.Raevenhart:BAACLgAFFH8GAAIVAAMJlghrHwCrAAAVAAMJlghrHwCrAAAuAAQKfx0AAhUACAlZFWIkAAUCABUACAlZFWIkAAUCAAAA.Rainstorm:BAAALgADCgQJBAAAAA==.Rappa:BAAALgADCgEJAQAAAA==.Raptorx:BAAALgADCggJCAAAAA==.Raymond:BAAALgADCgcJBwAAAA==.Razerblade:BAAALgAECgEJAQAAAA==.',
Re='Rebarbative:BAABLgAECn8iAAMMAAkJoQ7JSgC5AQAMAAkJoQ7JSgC5AQAmAAMJfAXZUQB5AAAAAA==.Redvex:BAACLgAFFH8OAAIMAAQJXhh0QgBBAQAMAAQJXhh0QgBBAQAuAAQKf0UABAwACQnFJVYEAEkDAAwACQmQJVYEAEkDACYABQkxII8SALcBABEAAglwI7EjAJ4AAAAA.Rei:BAAALgAECgEJAQAAAA==.Reinhard:BAABLgAECn8xAAMPAAkJ3w8kYQCsAQAPAAkJ8w4kYQCsAQAlAAYJvRLtHQAaAQAAAA==.Revengè:BAAALgADCgQJBAAAAA==.Rewrew:BAABLgAECn8sAAIQAAkJhRrSEgB4AgAQAAkJhRrSEgB4AgAAAA==.',
Rh='Rhedman:BAABLgAECn8aAAMdAAYJ7QrzGwDrAAAdAAUJ7QrzGwDrAAAeAAYJdAX76gDDAAAAAA==.',
Ri='Ricasti:BAAALgAECgUJCgAAAA==.Rinahrune:BAAALgAECgMJBgAAAA==.Rinahvoid:BAAALgADCgcJBwAAAA==.',
Ro='Robat:BAAALgADCggJDQAAAA==.Rosanna:BAAALgAECggJCgAAAA==.Roselyn:BAABLgAECn8VAAITAAcJaxEcKgByAQATAAcJaxEcKgByAQAAAA==.Rotyr:BAABLgAECn83AAIKAAkJYhjvDQCMAgAKAAkJYhjvDQCMAgAAAA==.',
Ru='Ruana:BAEALgAECgUJDgAAAA==.Rubyrazor:BAAALgAECgQJBgAAAA==.Rumpunch:BAAALgAECgEJAQAAAA==.',
Sa='Safetydance:BAAALgAECgIJAgAAAA==.Salil:BAAALgADCgMJAwAAAA==.Salothos:BAAALgADCgYJBgAAAA==.Samesh:BAAALgAECgQJCAAAAA==.Sandrace:BAAALgADCgIJAgAAAA==.Sanginie:BAAALgADCgEJAQAAAA==.Santhela:BAAALgAECgMJAwAAAA==.Satrana:BAAALgADCgMJAwAAAA==.Saturñ:BAAALgAECgYJEQAAAA==.Sauroman:BAAALgAECgUJDgAAAA==.',
Sc='Scoobey:BAABLgAECn8lAAIUAAgJtBogMgAPAgAUAAgJtBogMgAPAgAAAA==.Scubbs:BAACLgAFFH8VAAIEAAUJ4xJNIwBXAQAEAAUJ4xJNIwBXAQAuAAQKfyEAAgQACAkuFkkiABECAAQACAkuFkkiABECAAAA.Scubbsboo:BAABLgAECn8ZAAIWAAcJqBvnGwAzAgAWAAcJqBvnGwAzAgABLgAFFAUJFQAEAOMSAA==.',
Se='Seras:BAAALgAECgUJBQAAAA==.Servantes:BAABLgAECn9KAAMXAAkJghA7OACzAQAXAAkJghA7OACzAQAFAAEJTwXwmwAjAAAAAA==.',
Sh='Shackleford:BAABLgAECn9HAAQKAAkJ4h7UDACdAgAKAAkJ4h7UDACdAgAJAAgJpRYCGwDsAQATAAcJLBMLLABlAQAAAA==.Shamwõwz:BAAALgAFFAMJBAAAAA==.Sheck:BAAALgAECgEJAQAAAA==.Shessofine:BAAALgAECggJCgAAAA==.Shotya:BAABLgAECn9NAAIUAAkJlwspTAC5AQAUAAkJlwspTAC5AQAAAA==.Shyvàna:BAAALgAECgIJAgAAAA==.',
Si='Siath:BAABLgAECn8UAAMGAAgJ6wsjQAAlAQAGAAgJ6wsjQAAlAQAnAAIJ6gg7PQA5AAAAAA==.Silvino:BAAALgADCgEJAQABLgAECgkJLwAFAMAbAA==.Sixpacktnt:BAAALgADCgcJJwAAAA==.Sixthknight:BAABLgAECn8aAAIPAAYJ4gdS4ADaAAAPAAYJ4gdS4ADaAAAAAA==.',
Sl='Slarr:BAAALgADCgEJAgAAAA==.',
Sm='Smight:BAABLgAECn8eAAIQAAgJXyaGBABOAwAQAAgJXyaGBABOAwAAAA==.',
Sn='Snacky:BAAALgAECgIJAgAAAA==.Snarkypony:BAAALgAECgYJDwAAAA==.',
So='Solani:BAAALgADCgYJCQAAAA==.Solania:BAAALgAECgYJCgAAAA==.Soloqenjoyer:BAAALgAECgUJBQAAAA==.Sorocide:BAAALgADCgUJBQAAAA==.Sorsere:BAABLgAECn81AAIMAAkJcR2MEwCvAgAMAAkJcR2MEwCvAgAAAA==.',
Sp='Spcecialk:BAABLgAECn8dAAIZAAcJLQsMKADvAAAZAAcJLQsMKADvAAAAAA==.Specialk:BAABLgAECn8+AAMcAAgJSRLQMQByAQAcAAgJSRLQMQByAQAEAAMJrAaKrgBmAAAAAA==.',
Sq='Squallie:BAABLgAECn8VAAIXAAYJqRPCTgBRAQAXAAYJqRPCTgBRAQAAAA==.',
St='Steamedhams:BAAALgAECgcJCwAAAA==.Stirredihime:BAAALgAECgUJCgAAAA==.',
Su='Sundorei:BAAALgAECgQJBgAAAA==.',
['Sû']='Sûlph:BAAALgAECgkJAwAAAA==.',
Ta='Taartt:BAAALgAFFAQJBAABLgAFFAcJJwABAJkTAA==.Tahoe:BAAALgADCgIJAgAAAA==.Talan:BAAALgAECgcJCgABLgAFFAcJDgADAIsJAA==.Talshekar:BAABLgAECn8lAAInAAgJsw2wCgBuAQAnAAgJsw2wCgBuAQAAAA==.Tarsis:BAABLgAECn8oAAIOAAkJeB9UBQDUAgAOAAkJeB9UBQDUAgAAAA==.',
Te='Teiana:BAABLgAECn8pAAIPAAkJ9x8MIwB3AgAPAAkJ9x8MIwB3AgAAAA==.Tezlyn:BAAALgAECgEJAgAAAA==.',
Th='Thaevin:BAABLgAECn8hAAIPAAkJrhP+TADeAQAPAAkJrhP+TADeAQAAAA==.Therony:BAAALgAECgkJBQAAAA==.Thingwan:BAACLgAFFH8KAAIXAAUJJBWpHQBkAQAXAAUJJBWpHQBkAQAuAAQKfzYAAhcACQk4G38QAMsCABcACQk4G38QAMsCAAAA.Thordak:BAAALgADCggJDQABLgAECggJGwAPADsRAA==.',
Ti='Tiamat:BAAALgAECgkJCQAAAA==.Timbuktoo:BAAALgAECgUJCwAAAA==.Tinypoop:BAABLgAECn8WAAICAAYJVBVSrQAiAQACAAYJVBVSrQAiAQAAAA==.Tinystain:BAAALgADCgcJDQAAAA==.Tinystink:BAABLgAECn8fAAIMAAgJCB5iHgBsAgAMAAgJCB5iHgBsAgAAAA==.Tiptugger:BAAALgAECgIJAgAAAA==.',
To='Toddstephens:BAABLgAECn8gAAIdAAYJihciEQBhAQAdAAYJihciEQBhAQAAAA==.Tors:BAACLgAFFH8KAAIFAAMJxwyVMgCwAAAFAAMJxwyVMgCwAAAuAAQKf1YAAwUACQnbHeQIAMMCAAUACQnbHeQIAMMCAAcAAgnYE3pNAG8AAAAA.',
Tr='Trogdore:BAAALgAECgYJDQAAAA==.Trollololo:BAABLgAECn9LAAMCAAkJuRrXIwCLAgACAAkJuRrXIwCLAgAoAAMJ+wfsCgCPAAAAAA==.Troy:BAABLgAECn8pAAICAAkJXx5OIwCNAgACAAkJXx5OIwCNAgAAAA==.Truid:BAAALgADCgEJAQAAAA==.Trylly:BAAALgAECgYJCAABLgAECggJEwALAAAAAA==.',
Tt='Ttaartt:BAACLgAFFH8nAAMBAAcJmRPgCQAFAgABAAcJmRPgCQAFAgAGAAQJyxBkPwDFAAAuAAQKfx0AAgEABwmqGfESABICAAEABwmqGfESABICAAAA.',
Tu='Tuckstaken:BAAALgAECgIJAgAAAA==.',
Ty='Typh:BAACLgAFFH8WAAIiAAQJ2yD1AgB4AQAiAAQJ2yD1AgB4AQAuAAQKf0QAAiIACQm5JXIAAF8DACIACQm5JXIAAF8DAAAA.Tyr:BAAALgAECgkJBwAAAA==.Tyrone:BAABLgAECn8kAAMaAAkJcRpKDQBuAgAaAAkJcRpKDQBuAgAWAAQJABAddAC1AAAAAA==.Tyrslan:BAAALgAECgYJCwAAAA==.',
Uf='Uffish:BAAALgAECgkJCQAAAQ==.',
Ug='Uglymagi:BAAALgAECgMJBAAAAA==.',
Un='Undeaddemon:BAABLgAECn8jAAQMAAkJJR03OAD3AQAMAAgJJR03OAD3AQARAAMJEQ8THwB4AAAmAAEJkAbJeAAqAAAAAA==.Undeaddh:BAAALgAECgIJAgABLgAECgkJIwAMACUdAA==.Undeadmaggot:BAAALgADCggJFAABLgAECgkJIwAMACUdAA==.Undeadscaly:BAAALgAECgYJBwABLgAECgkJIwAMACUdAA==.Undignified:BAABLgAECn9FAAIiAAkJChkEBABcAgAiAAkJChkEBABcAgAAAA==.Unholysixth:BAAALgADCgkJNAAAAA==.Unicornquen:BAAALgAECgEJAQAAAA==.',
Ur='Uriyah:BAAALgAECgEJAQAAAA==.',
Uz='Uzzìel:BAAALgADCgEJAQAAAA==.',
Va='Valkar:BAAALgAECgEJAgAAAA==.Vanidarr:BAAALgADCgEJAQAAAA==.',
Ve='Verasia:BAAALgAECgUJEQAAAA==.',
Vi='Vidikan:BAAALgAECgQJDwAAAA==.Vie:BAAALgAECgEJAQAAAA==.',
Vo='Voidwarranty:BAACLgAFFH8FAAIEAAMJAAvLWACWAAAEAAMJAAvLWACWAAAuAAQKfzQAAwQACQl0FysiAD0CAAQACQl0FysiAD0CABwABwmRFuAjAMQBAAAA.Vontoot:BAAALgADCgEJAQAAAA==.',
Vv='Vvumpscut:BAABLgAECn8gAAIEAAkJaxp5HwBPAgAEAAkJaxp5HwBPAgAAAA==.',
Vy='Vysena:BAAALgAECgEJAwAAAA==.',
Wa='Waldón:BAABLgAECn9LAAIoAAkJPg3aBACRAQAoAAkJPg3aBACRAQAAAA==.',
We='Werrik:BAABLgAECn8aAAIMAAkJXyX8IgCJAgAMAAkJXyX8IgCJAgABLgAFFAIJAgALAAAAAA==.',
Wh='Whiskeytap:BAAALgAECgIJAgAAAA==.',
Wi='Wildsoul:BAABLgAECn8jAAIEAAcJPxIBUQBqAQAEAAcJPxIBUQBqAQAAAA==.Winchester:BAAALgADCgMJAwAAAA==.',
Wo='Wolfguardiån:BAAALgADCgMJAwAAAA==.',
Wr='Wrenz:BAAALgAECgQJDAAAAA==.',
Wu='Wuha:BAAALgADCgEJAQAAAA==.',
['Wä']='Wärhämmer:BAAALgADCgcJCgAAAA==.',
Xa='Xaneva:BAAALgADCgEJAgABLgAFFAYJKQAIAPYiAA==.Xanxer:BAAALgADCgQJBQAAAA==.',
Xc='Xclaw:BAABLgAECn8aAAINAAkJ+wqKGQDTAQANAAkJ+wqKGQDTAQAAAA==.',
Xe='Xeroxgravîty:BAAALgAECgEJAQAAAA==.Xeroxpriest:BAAALgAECgcJCwAAAA==.',
Xi='Xilphira:BAAALgAECgUJCQAAAA==.',
Xl='Xlithz:BAABLgAECn8wAAMgAAkJHxs3FgA8AgAgAAkJFhs3FgA8AgAhAAgJPhKYHAB0AQAAAA==.',
['Xí']='Xílo:BAEBLgAECn9MAAMDAAkJjh7mFACZAgADAAkJcxzmFACZAgASAAYJtx4JGAC/AQAAAA==.',
Yl='Ylene:BAABLgAECn8tAAIXAAkJRBCgMgDSAQAXAAkJRBCgMgDSAQAAAA==.',
Yo='Yoink:BAACLgAFFH8TAAIeAAQJkxoWUgBJAQAeAAQJkxoWUgBJAQAuAAQKfzsAAh4ACQk7JBUIADEDAB4ACQk7JBUIADEDAAAA.',
Za='Zalasham:BAAALgADCgIJAgAAAA==.Zarinchaos:BAAALgAECgUJBwAAAA==.Zarinfur:BAABLgAECn82AAIIAAkJHBmqBwBXAgAIAAkJHBmqBwBXAgAAAA==.',
Ze='Zedrin:BAAALgAECgQJBAAAAA==.Zein:BAAALgAECgQJCAAAAA==.Zentacle:BAAALgAECgIJAgAAAA==.Zente:BAACLgAFFH8IAAIUAAQJiAaaWgDoAAAUAAQJiAaaWgDoAAAuAAQKfycAAxQABwltGmpSAKcBABQABwltGmpSAKcBABUAAQn1AJGZABsAAAAA.Zequill:BAABLgAECn9HAAIZAAkJzyNNAgAkAwAZAAkJzyNNAgAkAwAAAA==.Zevsticles:BAABLgAECn8sAAIUAAkJUx8UFwCAAgAUAAkJUx8UFwCAAgAAAA==.',
Zh='Zhom:BAACLgAFFH8VAAIVAAQJFx+BDwBkAQAVAAQJFx+BDwBkAQAuAAQKfz8AAhUACQkcJHEBAAgDABUACQkcJHEBAAgDAAAA.',
Zo='Zohm:BAAALgADCgMJAwAAAA==.Zolec:BAAALgADCgcJDgAAAA==.Zooj:BAABLgAECn9MAAIpAAkJQBv1BACWAgApAAkJQBv1BACWAgAAAA==.Zorlak:BAAALgAECgUJDQAAAA==.',
Zu='Zuxa:BAAALgADCgYJBgAAAA==.',
Zy='Zylofeather:BAAALgAECgQJBAAAAA==.',
['ße']='ßeast:BAABLgAECn8jAAIaAAgJiwkRNwAjAQAaAAgJiwkRNwAjAQAAAA==.',
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
