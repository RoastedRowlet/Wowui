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

local lookup = {'Evoker-Preservation','Mage-Frost','DemonHunter-Devourer','Shaman-Restoration','Druid-Balance','Evoker-Augmentation','Druid-Guardian','Druid-Feral','Priest-Shadow','Priest-Discipline','Unknown-Unknown','Warlock-Demonology','DeathKnight-Blood','Hunter-Survival','Paladin-Retribution','Paladin-Holy','Warlock-Affliction','DemonHunter-Havoc','Priest-Holy','Hunter-BeastMastery','Hunter-Marksmanship','Monk-Mistweaver','Druid-Restoration','Rogue-Subtlety','Warrior-Protection','Monk-Windwalker','Mage-Arcane','Shaman-Elemental','DeathKnight-Frost','DeathKnight-Unholy','Monk-Brewmaster','Warrior-Fury','Warrior-Arms','Rogue-Assassination','Rogue-Outlaw','DemonHunter-Vengeance','Paladin-Protection','Warlock-Destruction','Evoker-Devastation','Mage-Fire','Shaman-Enhancement',}
local provider = {region='US',realm='Llane',name='US',type='weekly',zone=46,date='2026-06-20',data={Ab='Abdervoke:BAABLgAECn8fAAIBAAkJRyL4AQBkAwABAAkJRyL4AQBkAwAAAA==.Absent:BAAALgADCgEJAQAAAA==.',
Ac='Account:BAAALgADCgIJAgAAAA==.',
Ae='Aeila:BAAALgADCgYJBgAAAA==.',
Ah='Ahsoul:BAAALgAECgEJAgAAAA==.',
Al='Alesia:BAAALgADCgEJAQAAAA==.Alessaah:BAAALgADCgcJCgAAAA==.Aliadra:BAABLgAECn8zAAICAAkJSSJzDwD/AgACAAkJSSJzDwD/AgAAAA==.Alistus:BAACLgAFFH8PAAIDAAQJoSKsKACIAQADAAQJoSKsKACIAQAuAAQKfz4AAgMACQn/JMcDAEoDAAMACQn/JMcDAEoDAAAA.Alphá:BAAALgAECgUJCQABLgAFFAMJBQAEAAALAA==.Altholar:BAAALgADCgcJBwAAAA==.',
An='Anexxia:BAAALgAECgQJCQAAAA==.Angel:BAAALgAECgYJDwAAAA==.Angua:BAABLgAECn9QAAIFAAkJ4hugAACjAQAFAAkJ4hugAACjAQAAAA==.',
Ar='Arcanegarm:BAABLgAECn8bAAICAAcJIAJU/wCuAAACAAcJIAJU/wCuAAAAAA==.Archeyois:BAABLgAECn8pAAMGAAkJVA9FKwCRAQAGAAkJVA9FKwCRAQABAAUJhQIRNwCzAAAAAA==.Armitage:BAABLgAECn8YAAMHAAkJ/w+0HABnAQAHAAkJXQ+0HABnAQAIAAcJQgvxHgARAQAAAA==.Arthonos:BAACLgAFFH8GAAIJAAIJVAX/MwBzAAAJAAIJVAX/MwBzAAAuAAQKfzUAAwkACQmaFQ8ZAP0BAAkACQmaFQ8ZAP0BAAoACAnjBWQnAFoBAAAA.Arugall:BAAALgAECgYJBgAAAA==.',
As='Ashmall:BAAALgAECgQJBAAAAA==.',
Av='Averille:BAAALgADCgYJCwAAAA==.',
Ay='Ayraa:BAAALgAECgYJBAAAAA==.',
Az='Azerphage:BAAALgAECgYJDwABLgAECgcJCwALAAAAAA==.Azeura:BAAALgADCgQJBAAAAA==.Azhorra:BAABLgAECn8VAAIMAAYJOwrVrgDmAAAMAAYJOwrVrgDmAAAAAA==.Azzog:BAABLgAECn8YAAINAAgJFBa1GACdAQANAAgJFBa1GACdAQAAAA==.Azül:BAAALgAECgQJBAABLgAECgcJCwALAAAAAA==.',
Ba='Bacchanalian:BAAALgAECgcJDAABLgAECgkJCwALAAAAAA==.Baindyn:BAAALgAECgQJEwAAAA==.Barator:BAAALgAECgYJCgAAAA==.Bas:BAAALgAECgUJCQAAAA==.',
Bi='Bickkbatwolf:BAAALgADCgYJDQAAAA==.Bigwhisky:BAAALgAECgcJEAAAAA==.',
Bl='Blackröse:BAABLgAECn8jAAIOAAgJMx2FEAAqAgAOAAgJMx2FEAAqAgAAAA==.Blackrøse:BAABLgAECn8cAAIEAAkJtQ5NOwDBAQAEAAkJtQ5NOwDBAQABLgAECggJIwAOADMdAA==.Bladebane:BAABLgAECn8lAAINAAkJGgFNPQCbAAANAAkJGgFNPQCbAAAAAA==.Blandmonk:BAAALgAECgMJAwAAAA==.Blksunshine:BAAALgAECgYJCgAAAA==.',
Bo='Bolash:BAAALgAECgYJCwAAAA==.Bort:BAAALgAECgEJBAAAAA==.',
Br='Bradthomas:BAAALgAECgQJBQAAAA==.Breegorn:BAAALgAECgUJBgAAAA==.Breni:BAAALgAFFAEJAQAAAA==.Bruscha:BAAALgAECgUJDwAAAA==.',
Bu='Bulvhine:BAABLgAECn8xAAIPAAkJfCCJAACgAgAPAAkJfCCJAACgAgAAAA==.',
Ca='Camferd:BAAALgAECgEJAQAAAA==.Camford:BAABLgAECn8ZAAICAAcJ8QhZvQBoAQACAAcJ8QhZvQBoAQAAAA==.Cantatrix:BAABLgAECn8bAAIMAAYJ9gt3owD5AAAMAAYJ9gt3owD5AAAAAA==.Capslok:BAAALgAECgYJDQAAAA==.Captinmeat:BAAALgAECgIJBAAAAA==.Cashkin:BAAALgADCgYJBgAAAA==.Cassiela:BAAALgAECgYJBgABLgAECgkJCwALAAAAAA==.',
Ce='Cecilx:BAABLgAECn8zAAIQAAkJWCRsAgCGAwAQAAkJWCRsAgCGAwAAAA==.Cellybelleri:BAAALgADCgUJCAAAAA==.',
Ch='Chaac:BAAALgADCgEJAQAAAA==.Charmander:BAAALgADCgcJCAAAAA==.Chayton:BAAALgADCgUJBQAAAA==.Cherrypie:BAAALgAECgYJBgAAAA==.Chillana:BAAALgAECgQJBAAAAA==.Chimerax:BAACLgAFFH8XAAMRAAUJPyB4AgCDAQARAAUJPyB4AgCDAQAMAAEJlxenwQBHAAAuAAQKfy0AAxEACQljHwACALACABEACAlCIgACALACAAwACAlDEwh8AEEBAAAA.Chloede:BAAALgADCgUJBQAAAA==.Chlorpyrifos:BAAALgADCgEJAQAAAA==.Chrismikea:BAABLgAECn8cAAIPAAgJMAZQoQA9AQAPAAgJMAZQoQA9AQAAAA==.Chronic:BAAALgAECgQJBwAAAA==.Chully:BAACLgAFFH8PAAIDAAQJZRD1SAAOAQADAAQJZRD1SAAOAQAuAAQKfywAAwMACQkIG2IqACACAAMACQkIG2IqACACABIAAwmIBM1ZAH0AAAAA.',
Cl='Clairíty:BAABLgAECn8eAAITAAgJoh4DDgCGAgATAAgJoh4DDgCGAgAAAA==.Clarky:BAAALgAECgYJEAAAAA==.Click:BAABLgAECn9EAAIUAAkJUxzxEwCzAgAUAAkJUxzxEwCzAgAAAA==.Cloutfarmer:BAACLgAFFH8QAAIUAAQJGyC6KQBhAQAUAAQJGyC6KQBhAQAuAAQKf0AABBQACQlKJf8EAEEDABQACQlKJf8EAEEDABUABgkZHFspAOABAA4AAglFHfhVAFUAAAAA.',
Co='Comadore:BAACLgAFFH8OAAIPAAUJhAqQWgD7AAAPAAUJhAqQWgD7AAAuAAQKfxwAAg8ACAk4HNg4AEACAA8ACAk4HNg4AEACAAAA.Coronae:BAAALgAECgEJAQAAAA==.',
Cr='Crankshanker:BAAALgAECgEJAQAAAA==.Cratora:BAAALgAECgYJBgAAAA==.Credan:BAEBLgAECn8VAAIWAAkJMyISBgBFAwAWAAkJMyISBgBFAwABLgADCgYJBgALAAAAAA==.Critmypants:BAAALgAECgIJAgAAAA==.',
Cy='Cylithina:BAAALgAECgQJBwAAAA==.Cytochrome:BAAALgADCgQJBAAAAA==.',
Da='Daphe:BAAALgAECgEJAwAAAA==.Dawggbiscuit:BAAALgAECgQJBQAAAA==.',
De='Deadiam:BAAALgAECgEJAQAAAA==.Deadseksi:BAAALgAECgcJDQAAAA==.Deathslead:BAABLgAECn9AAAMUAAgJaRZEAwArAQAUAAgJaRZEAwArAQAVAAUJ3AHqMQBSAAAAAA==.Decrepe:BAACLgAFFH8RAAIXAAQJ2BhsJwAhAQAXAAQJ2BhsJwAhAQAuAAQKfzsAAhcACQlIIIAKABUDABcACQlIIIAKABUDAAAA.Dedrepe:BAAALgAECggJCQAAAA==.Delph:BAAALgAFFAEJAQAAAA==.Deshal:BAAALgAECgQJCAAAAA==.Desomas:BAAALgAECgIJAgAAAA==.Dethklock:BAAALgAECgEJAQAAAA==.',
Di='Dieurnal:BAAALgAECgQJAQAAAA==.Discostar:BAABLgAECn8pAAMXAAgJohlbLgDsAQAXAAcJghhbLgDsAQAFAAYJiBKSLwBhAQAAAA==.Distill:BAAALgAECgEJAQABLgAFFAkJHAAYAB4hAA==.',
Dn='Dni:BAAALgAECgMJBAABLgAECgkJLwAFAMAbAA==.',
Do='Dominicm:BAAALgAECgYJEgAAAA==.Dotdotdis:BAAALgAECgMJAwAAAA==.',
Dr='Dracanalian:BAAALgADCgkJCQAAAA==.Drajhar:BAAALgAECgkJBQAAAA==.Drakyore:BAAALgADCgIJAwAAAA==.Draq:BAAALgAECgYJCgAAAA==.Druth:BAABLgAECn8tAAIZAAgJRx++CgBDAgAZAAgJRx++CgBDAgAAAA==.',
Eb='Ebonhorn:BAAALgAECgUJEQAAAA==.',
Ee='Eevillean:BAAALgAECgEJAQAAAA==.',
Ei='Einari:BAAALgAECggJCAAAAA==.Einark:BAABLgAECn9FAAMWAAkJ+x9KAAClAgAWAAkJ+x9KAAClAgAaAAgJzB4uDQByAgAAAA==.',
Ek='Ekiim:BAAALgAECgQJBAABLgAECgQJCQALAAAAAA==.',
El='Eldrond:BAAALgAECgQJCAABLgAECgUJCQALAAAAAA==.Elinis:BAAALgAFFAEJAQAAAA==.Elska:BAAALgADCgkJCQAAAA==.',
En='Ennauríon:BAAALgAECgUJCQAAAA==.Entropy:BAEALgAFFAIJAgABLgAFFAMJBwAbADUOAA==.',
Er='Eridor:BAAALgAECgYJEAAAAA==.',
Ex='Exek:BAABLgAECn8tAAMTAAgJExctFwAVAgATAAgJExctFwAVAgAJAAUJWQu9VADAAAAAAA==.',
Ez='Ez:BAAALgAECgEJAQABLgAECgkJLQAcABUbAA==.',
Fa='Fabaztard:BAABLgAECn8kAAIFAAkJ1xIoIwCwAQAFAAkJ1xIoIwCwAQAAAA==.Faline:BAABLgAECn8zAAIXAAkJUwvLRQB5AQAXAAkJUwvLRQB5AQAAAA==.',
Fe='Felgetabouit:BAACLgAFFH8XAAIDAAUJUhN4SgAKAQADAAUJUhN4SgAKAQAuAAQKfyMAAgMACQlUGs00ACUCAAMACQlUGs00ACUCAAAA.Felghoul:BAAALgAECgcJEgAAAA==.Felldozer:BAAALgAECgEJAQAAAA==.Fenrakar:BAAALgAECgQJBwAAAA==.Feywynn:BAAALgAECggJBwAAAA==.',
Fi='Fights:BAABLgAECn9BAAIQAAkJKR4HCgDrAgAQAAkJKR4HCgDrAgAAAA==.',
Fl='Fleshworker:BAAALgADCgEJAQAAAA==.',
Fo='Fordalliance:BAAALgADCgcJBwAAAA==.Forky:BAAALgAECgQJCAAAAA==.Foxknight:BAABLgAECn8UAAQdAAUJaxAdGgABAQAdAAUJaxAdGgABAQAeAAMJ7AsOFAGTAAANAAQJ4QM1SwBiAAAAAA==.',
Fr='Franciss:BAAALgAECgYJDQAAAA==.Francys:BAAALgADCgIJAwAAAA==.Franksnbeans:BAAALgAECgEJAgABLgAECgYJEgALAAAAAA==.',
Ft='Ftx:BAABLgAECn8gAAMfAAgJuh+oDQC4AgAfAAgJlR+oDQC4AgAaAAQJ2hm/RgD6AAAAAA==.',
Fu='Fubbleskag:BAABLgAECn8xAAIPAAkJARwwOAAhAgAPAAkJARwwOAAhAgAAAA==.Fullmoonn:BAAALgAECgIJAwAAAA==.',
Ga='Gaern:BAAALgAECgEJAwABLgAFFAEJAQALAAAAAA==.Gaidan:BAACLgAFFH8MAAIFAAUJ5wukKQDqAAAFAAUJ5wukKQDqAAAuAAQKfyEAAgUACQmlFogRAI8CAAUACQmlFogRAI8CAAEuAAUUBwkQAAMAtQoA.Gaidin:BAACLgAFFH8QAAIDAAcJtQp1LAB1AQADAAcJtQp1LAB1AQAuAAQKfyAAAgMACQlJHgU9ANQBAAMACQlJHgU9ANQBAAAA.Gameslayer:BAABLgAECn8gAAMgAAkJcB2cKwCmAQAgAAYJcx+cKwCmAQAhAAQJzxdcMQACAQAAAA==.Gankzilla:BAACLgAFFH8XAAMYAAUJHRbZGQBGAQAYAAUJHRbZGQBGAQAiAAEJbBG+EABOAAAuAAQKfycAAyIACQmeG2EJAKoBABgABgl3GNklAMoBACIABwkfG2EJAKoBAAAA.Garothos:BAAALgAECgIJAgABLgAECgQJBwALAAAAAA==.Gatanikaz:BAAALgAECgIJBAAAAA==.',
Ge='Genrealwee:BAAALgAECgEJAQAAAA==.Get:BAAALgADCgkJDAAAAA==.',
Gh='Ghalumvhar:BAABLgAECn8fAAIPAAcJBRtbTwDaAQAPAAcJBRtbTwDaAQAAAA==.Ghoulaid:BAAALgAECgcJBwAAAA==.Ghrìmm:BAABLgAECn8lAAQOAAkJ6w/FGgDIAQAOAAkJIA3FGgDIAQAUAAgJxA5RaQBwAQAVAAEJ+QZmRAAiAAAAAA==.',
Gi='Gila:BAAALgAECggJDwAAAA==.Gingasorrow:BAABLgAECn80AAIXAAkJoBkLFgCYAgAXAAkJoBkLFgCYAgAAAA==.Gizzle:BAACLgAFFH8QAAIPAAUJpg3cWAD+AAAPAAUJpg3cWAD+AAAuAAQKfyYAAg8ACQmoFlxVAMoBAA8ACQmoFlxVAMoBAAAA.',
Gr='Greekfire:BAABLgAECn8YAAIQAAgJ3yE5GwA7AgAQAAgJ3yE5GwA7AgAAAA==.Grishna:BAAALgADCggJCAAAAA==.Grumrok:BAAALgAECgQJBgAAAA==.Grunbar:BAABLgAECn80AAIUAAgJqSKDGQCNAgAUAAgJqSKDGQCNAgAAAA==.Grændal:BAABLgAECn8UAAIJAAcJ8Ba3AQDwAAAJAAcJ8Ba3AQDwAAABLgAFFAcJEAADALUKAA==.',
Ha='Hanjha:BAABLgAECn9HAAMOAAkJkR/BAwD4AgAOAAgJkR/BAwD4AgAUAAEJAAA7zwA3AAAAAA==.Hatz:BAAALgADCgcJBgAAAA==.',
He='Healshot:BAAALgADCgMJAwABLgAECgUJFQAPAGUmAA==.Helldozer:BAABLgAECn9JAAMcAAkJLxYQGAAjAgAcAAkJLxYQGAAjAgAEAAIJzxRWpwB9AAAAAA==.',
Ho='Hooj:BAAALgADCgYJBgAAAA==.Horde:BAAALgADCgEJAQAAAA==.',
Ht='Ht:BAAALgADCgMJCAAAAA==.',
Hu='Hugzy:BAAALgAECgYJCwAAAA==.',
Hw='Hwore:BAAALgAECgQJBAAAAA==.',
Hy='Hydatos:BAAALgADCgMJAwABLgAECgYJCgALAAAAAA==.Hypnocide:BAEBLgAECn9JAAIDAAkJ8RiFAAALAgADAAkJ8RiFAAALAgAAAA==.',
['Hô']='Hôneynuts:BAAALgADCgIJAgAAAA==.',
Ib='Ibuki:BAAALgAECgYJEgABLgAFFAUJFwAQAFQGAA==.',
Ic='Icepick:BAAALgADCgIJAgAAAA==.',
Id='Idleorc:BAAALgADCgcJDQAAAA==.',
Ig='Iguanajon:BAAALgAECgEJAgAAAA==.',
Il='Illandren:BAACLgAFFH8RAAIOAAQJlggbGAARAQAOAAQJlggbGAARAQAuAAQKfxsAAw4ACQljC+4cALUBAA4ACQljC+4cALUBABUACAk6A9cfALEAAAAA.Illusiveeyes:BAAALgADCgYJDAAAAA==.',
Im='Impsane:BAABLgAECn8jAAIMAAkJBw6ATgCvAQAMAAkJBw6ATgCvAQAAAA==.',
In='Incøgnitø:BAAALgAECgEJAQABLgAECgkJHAAXAAkcAA==.Infernis:BAAALgADCgYJCQAAAA==.Innphyy:BAABLgAECn8jAAICAAcJsQjtwgAFAQACAAcJsQjtwgAFAQAAAA==.Innøminate:BAABLgAECn8hAAIUAAgJuhGiAQCrAQAUAAgJuhGiAQCrAQABLgAECgkJHAAXAAkcAA==.Inti:BAAALgADCgEJAQAAAA==.',
Ir='Irv:BAABLgAECn8WAAQiAAgJlhqJBwDgAQAiAAgJ5xmJBwDgAQAYAAUJoxxSMwBwAQAjAAQJjg9mCQDZAAAAAA==.',
Is='Isadavrah:BAAALgADCgcJDAAAAA==.Isekai:BAAALgAECgQJBgAAAA==.Issadin:BAAALgAECgUJBwABLgAECgYJDAALAAAAAA==.Issadruiid:BAAALgADCgYJBgABLgAECgYJDAALAAAAAA==.Issammonk:BAAALgAECgEJAQABLgAECgYJDAALAAAAAA==.Issarage:BAAALgAECgQJCQABLgAECgYJDAALAAAAAA==.Issashammy:BAAALgAECgYJDAAAAA==.',
Ja='Jaxxa:BAABLgAECn88AAIUAAkJ6xqCHwBqAgAUAAkJ6xqCHwBqAgAAAA==.',
Je='Jeddiah:BAABLgAECn8jAAMiAAcJIQ/UDQBKAQAiAAcJIQ/UDQBKAQAYAAQJRgpfRwCdAAAAAA==.',
Jh='Jhals:BAAALgADCgYJBgAAAA==.',
Ji='Jiffarous:BAAALgAECgQJBwAAAA==.Jinkès:BAABLgAECn8tAAIVAAgJfxUQCwC6AQAVAAgJfxUQCwC6AQAAAA==.',
Jp='Jpank:BAAALgAFFAEJAwAAAA==.',
Ju='Jubei:BAABLgAFFH8HAAIPAAYJbgpygAC1AAAPAAYJbgpygAC1AAAAAA==.Judis:BAABLgAECn9TAAIiAAkJRR+8AQDiAgAiAAkJRR+8AQDiAgAAAA==.Judyth:BAAALgAECgIJBQAAAA==.Juicy:BAAALgADCgIJAgAAAA==.Justokevoker:BAABLgAFFH8LAAIGAAQJpxHkMgD2AAAGAAQJpxHkMgD2AAAAAA==.',
Ka='Kainel:BAAALgAECgkJCQAAAA==.Kairì:BAAALgADCgcJDQAAAA==.Kalifist:BAABLgAECn8cAAIaAAkJnR97CAC/AgAaAAkJnR97CAC/AgAAAA==.Kalinear:BAAALgADCgQJBQAAAA==.Kalipally:BAAALgAECgcJDgAAAA==.Kaliscales:BAAALgAECgUJBQAAAA==.Kamiportal:BAAALgAECgcJCgAAAA==.Kanajotoma:BAAALgAECgUJEgAAAA==.Karlai:BAABLgAECn8oAAMdAAgJZRrlBAAAAgAdAAcJuhrlBAAAAgAeAAUJGBIY3wDVAAABLgAFFAcJEAADALUKAA==.Kaslana:BAEALgADCgYJBgAAAA==.',
Ke='Keldrune:BAAALgAECgYJDAAAAA==.Keleena:BAEBLgAECn9WAAIQAAkJvh8pAACPAgAQAAkJvh8pAACPAgAAAA==.Kelume:BAAALgADCgMJAwAAAA==.Kely:BAAALgADCgUJBgAAAA==.',
Kg='Kgor:BAAALgAECgcJBwAAAA==.',
Kh='Khaerne:BAAALgAECgEJAQABLgAFFAEJAQALAAAAAA==.Khordelia:BAAALgAFFAEJAQAAAA==.',
Ki='Kinst:BAABLgAECn9DAAMUAAkJvB82EgDAAgAUAAkJvB82EgDAAgAVAAYJrxLaPwBbAQAAAA==.Kirigaya:BAAALgAECgMJCAAAAA==.Kisäi:BAABLgAECn8pAAMDAAkJ1RxbIACPAgADAAkJ1RxbIACPAgAkAAIJHBGTKABiAAAAAA==.Kitanyia:BAABLgAECn8hAAIgAAkJDg9LKQC0AQAgAAkJDg9LKQC0AQAAAA==.Kittiy:BAABLgAECn81AAMFAAgJfAdIQwD/AAAFAAgJfAdIQwD/AAAXAAYJKgdPfADDAAAAAA==.',
Ko='Kordelia:BAABLgAECn8mAAICAAkJJh8dHwCjAgACAAkJJh8dHwCjAgABLgAFFAEJAQALAAAAAA==.Korvus:BAAALgAECgcJEQAAAA==.',
Kv='Kv:BAAALgADCggJCAAAAA==.',
Ky='Kyakuna:BAAALgAECgIJAgAAAA==.Kylnara:BAAALgAECgUJCQAAAA==.Kyloon:BAAALgAECgEJAQAAAA==.Kyrah:BAABLgAECn89AAMMAAkJrhqvAAAHAgAMAAkJmBevAAAHAgARAAYJ3xvLBgDrAQAAAA==.',
La='Lamanira:BAAALgAECgYJCgAAAA==.Lancier:BAAALgAECgYJCgAAAA==.',
Le='Lecleme:BAACLgAFFH8GAAIeAAMJZBEJoADUAAAeAAMJZBEJoADUAAAuAAQKfyEAAh4ACAleGEhIAOkBAB4ACAleGEhIAOkBAAAA.Lejend:BAABLgAECn9KAAMhAAkJyCXiAABxAwAhAAkJyCXiAABxAwAgAAMJfRW8fwC+AAAAAA==.Lenthalis:BAAALgAECgUJDwAAAA==.Lezriel:BAAALgAECgMJBgAAAA==.',
Li='Lichin:BAAALgADCgEJAQAAAA==.Lilithh:BAAALgADCgUJCAAAAA==.',
Ll='Llanedh:BAAALgAECggJDAAAAA==.',
Lo='Loaganic:BAAALgAECgQJBAABLgAECggJFAAGAOsLAA==.Lockheéd:BAAALgAFFAEJAQAAAA==.Lonelyhearts:BAABLgAECn89AAIPAAkJrQsUcwCIAQAPAAkJrQsUcwCIAQAAAA==.Lonestar:BAAALgAECgYJDwAAAA==.Lonestarr:BAAALgAECgQJDAAAAA==.Loxricia:BAAALgADCgEJAQAAAA==.',
Lu='Lumiya:BAABLgAECn8yAAITAAkJ7w52LwCFAQATAAkJ7w52LwCFAQAAAA==.',
Ly='Lytol:BAABLgAECn8qAAMbAAkJtReFAgAoAgAbAAkJtReFAgAoAgACAAMJXgQ4IgF1AAAAAA==.',
Ma='Machu:BAAALgADCgIJAgABLgAFFAQJCwAGANkVAA==.Madderhorn:BAAALgAECgcJBQAAAA==.Maenad:BAAALgAECgkJCwAAAA==.Maeple:BAABLgAECn8pAAMTAAkJ+SEiBABDAwATAAkJ+SEiBABDAwAKAAMJugpeXgCFAAAAAA==.Magikin:BAAALgAECgQJCAAAAA==.Magrat:BAAALgAECgQJBAAAAA==.Mamichula:BAAALgAECgEJAQAAAA==.',
Mb='Mbdtf:BAACLgAFFH8XAAMOAAcJ6hy5AgANAgAOAAYJySG5AgANAgAVAAEJjAS6JABVAAAuAAQKfxsAAw4ABwmMJXMEANQCAA4ABwkxJXMEANQCABUAAQksIwR3AGMAAAEuAAUUCAkoAAIA0CMA.',
Me='Mechagnome:BAACLgAFFH8GAAIaAAIJoBsKLgCQAAAaAAIJoBsKLgCQAAAuAAQKfzQAAxoACQnUIMsHAMsCABoACQnUIMsHAMsCABYACAkJBAU6AAABAAAA.Meeps:BAAALgADCgcJBwAAAA==.Megamedes:BAABLgAECn8aAAMPAAYJkhbKegCEAQAPAAYJEhbKegCEAQAlAAQJTQn8NgCEAAAAAA==.Meigna:BAABLgAECn8qAAIJAAgJuR2MEQBKAgAJAAgJuR2MEQBKAgAAAA==.Mekö:BAAALgAECgYJDQAAAA==.Meladyn:BAACLgAFFH8pAAMIAAYJ9iKQBAByAQAIAAUJeyOQBAByAQAHAAUJMh4aCQBhAQAuAAQKfygAAwgABwlnJlYDAAMDAAgABwlnJlYDAAMDAAcABQnrIwEXAJoBAAAA.Melritza:BAAALgAECgQJCAAAAA==.Mentock:BAABLgAECn8YAAICAAYJ4hB/qwApAQACAAYJ4hB/qwApAQAAAA==.Merelandra:BAAALgADCgkJIAAAAA==.Mermaid:BAAALgAECgUJCgAAAA==.',
Mi='Miliara:BAAALgADCgEJAQAAAA==.Missmaam:BAABLgAECn8XAAMTAAgJ2hldFQAqAgATAAgJ2hldFQAqAgAJAAQJ4RCgAgCtAAAAAA==.Mistroot:BAAALgAECggJCQAAAA==.Mistshealz:BAAALgAECgEJAQABLgAFFAQJDgAeAMQdAA==.Mithrandir:BAACLgAFFH8FAAMMAAIJxwAaxABFAAAMAAIJxwAaxABFAAAmAAEJOQDWLQATAAAuAAQKfyAAAgwABwmWEPZxAFYBAAwABwmWEPZxAFYBAAAA.Mixcoati:BAAALgADCgQJBQAAAA==.Mizu:BAABLgAECn8cAAMZAAkJyxseDwD4AQAZAAkJyxseDwD4AQAgAAIJ6xAGlABvAAAAAA==.',
Mo='Moe:BAAALgAECgkJBAAAAA==.Monkfox:BAAALgAECgcJBwAAAA==.Morgianna:BAAALgADCgEJAQAAAA==.',
Mu='Mudflap:BAAALgAECgYJEQAAAA==.Mushuwoonter:BAAALgAECgEJAQABLgAFFAQJCwAGANkVAA==.Muztang:BAABLgAECn9CAAMhAAkJ1x5vBADUAgAhAAkJ1x5vBADUAgAgAAYJihOBTgAOAQAAAA==.',
Mw='Mwmmwmm:BAAALgAECgYJCgAAAA==.',
My='Mythandwel:BAABLgAECn8uAAISAAgJsQjeLQAUAQASAAgJsQjeLQAUAQAAAA==.',
['Mä']='Mäddiey:BAAALgAECgQJCgAAAA==.',
['Mô']='Mônkii:BAACLgAFFH8TAAIfAAQJESXoDgCyAQAfAAQJESXoDgCyAQAuAAQKfz4AAx8ACQnjJLICAC4DAB8ACQnjJLICAC4DABYAAQmvAhvfABEAAAAA.',
Na='Nace:BAABLgAECn8qAAIYAAkJ7BOvGQA2AgAYAAkJ7BOvGQA2AgAAAA==.Nadriede:BAAALgADCgYJBgAAAA==.Naenia:BAAALgAECgUJBQAAAA==.Naillimixam:BAAALgADCgMJAgAAAA==.Nariar:BAAALgAECgMJAwABLgAFFAUJFwAQAFQGAA==.Nateldin:BAABLgAECn8YAAMPAAkJhwmIkABbAQAPAAkJ8AeIkABbAQAlAAIJ9Q61UgArAAAAAA==.',
Ne='Neoba:BAAALgAECgMJBQAAAA==.',
Ni='Nicksevokerc:BAAALgAECggJBwAAAA==.Niisha:BAAALgAECggJDQABLgAECgkJHwATAKMHAA==.Nikiso:BAAALgADCgYJBwAAAA==.',
No='Nocainus:BAABLgAECn9NAAINAAkJwCGLAwAFAwANAAkJwCGLAwAFAwAAAA==.Nosehole:BAABLgAECn8iAAIEAAcJ0hTXPAC7AQAEAAcJ0hTXPAC7AQAAAA==.Novari:BAAALgADCgkJCQAAAA==.',
Nv='Nv:BAAALgADCgEJAQABLgAFFAUJBQAaAGgFAA==.',
['Nø']='Nøtsure:BAABLgAECn8cAAMXAAkJCRy6JQAgAgAXAAkJCRy6JQAgAgAFAAIJqwyHdABdAAAAAA==.',
Ob='Obesityy:BAABLgAECn8xAAIYAAkJph5vCACfAgAYAAkJph5vCACfAgAAAA==.Obsidia:BAABLgAECn8oAAIMAAkJSQ8WSwC5AQAMAAkJSQ8WSwC5AQAAAA==.',
Oc='Octopusprime:BAAALgAECgkJEQAAAA==.',
Ol='Ollix:BAEALgAECgEJBAABLgAECgkJTAADAI4eAA==.',
Om='Omelette:BAABLgAECn8fAAIUAAkJiRz+GwB9AgAUAAkJiRz+GwB9AgAAAA==.',
On='Onik:BAAALgADCgcJDQABLgAECgUJCQALAAAAAA==.',
Or='Orangejulius:BAAALgAECgQJCQAAAA==.Orangutan:BAAALgAECgQJBQAAAA==.Oriclysmic:BAABLgAECn8iAAQBAAgJ5h3TBwB2AgABAAgJ5h3TBwB2AgAGAAQJhQSiTwCPAAAnAAEJAAAjPwAzAAAAAA==.Oriigami:BAAALgAECgUJCAAAAA==.Orinoheal:BAAALgAECgYJBgAAAA==.',
Os='Oshtudead:BAAALgADCgQJBAAAAA==.',
Pe='Perilous:BAAALgAECgUJDwAAAA==.Pewpëw:BAAALgADCgkJDwAAAA==.',
Ph='Phalix:BAAALgAFFAIJAgABLgAFFAQJFwAVAAMhAA==.Phat:BAAALgAECgQJBQAAAA==.Phoelar:BAAALgAECgcJDgAAAA==.Phuumyn:BAABLgAECn9FAAIaAAkJTyVOAQBoAwAaAAkJTyVOAQBoAwAAAA==.',
Pi='Piccoblast:BAACLgAFFH8cAAICAAcJyhQSDQCzAQACAAcJyhQSDQCzAQAuAAQKfy0AAgIACAnYIuEcAAIDAAIACAnYIuEcAAIDAAAA.Piccolocks:BAAALgAECgYJCwABLgAFFAcJHAACAMoUAA==.Piccopew:BAAALgAECgEJAQABLgAFFAcJHAACAMoUAA==.Pichus:BAAALgAECgEJAQABLgAFFAMJBQAEAAALAA==.Picklesoup:BAAALgAECgcJCQAAAA==.Pierrecurzi:BAAALgAFFAIJAwABLgAFFAQJFwAVAAMhAA==.Piickles:BAACLgAFFH8qAAMTAAgJ0RVVBgD1AQATAAgJ0RVVBgD1AQAKAAQJuxJTJgAYAQAuAAQKfx8AAhMABwndItoLAJMCABMABwndItoLAJMCAAAA.Pinkcanibus:BAABLgAECn8aAAIUAAgJvQSzbwAZAQAUAAgJvQSzbwAZAQAAAA==.Pippopper:BAAALgAECgEJAQABLgAFFAQJDwADAKEiAA==.Pity:BAABLgAECn8XAAIDAAkJjg2XUQCRAQADAAkJjg2XUQCRAQAAAA==.',
Pl='Plutø:BAABLgAECn9GAAQdAAkJdhpvAABFAQANAAcJth4MDABRAgAeAAkJghIHUQDQAQAdAAYJDxVvAABFAQAAAA==.',
Po='Polylocks:BAABLgAECn8UAAIMAAgJPBQbSgC8AQAMAAgJPBQbSgC8AQAAAA==.Pompey:BAAALgAECgEJAQAAAA==.',
Pr='Praeastra:BAECLgAFFH8HAAIbAAMJNQ6GAgDLAAAbAAMJNQ6GAgDLAAAuAAQKfysAAhsACAmkGtEDANEBABsACAmkGtEDANEBAAAA.Praycation:BAAALgAECgYJBgAAAA==.Promethius:BAAALgAECgcJCQABLgAFFAMJBQAMAMcAAA==.Protein:BAABLgAECn8gAAIgAAcJ0BUQPQBSAQAgAAcJ0BUQPQBSAQAAAA==.Prplxd:BAAALgADCgUJBQABLgAECgYJCgALAAAAAA==.Prókill:BAAALgADCgcJBwAAAA==.',
Ps='Psychokitty:BAABLgAECn9JAAIXAAkJER0UDQD0AgAXAAkJER0UDQD0AgAAAA==.',
Py='Pyppi:BAAALgADCgEJAQABLgAECggJFAAMADwUAA==.',
['Pô']='Pôwersm:BAAALgADCgMJAwAAAA==.',
Qu='Quiet:BAAALgAECgQJBAAAAA==.Quilian:BAACLgAFFH8WAAITAAUJdCTBBQAEAgATAAUJdCTBBQAEAgAuAAQKfyYAAhMACQlAISkEABIDABMACQlAISkEABIDAAAA.',
Ra='Raelynn:BAABLgAECn9NAAITAAkJvBk/DACiAgATAAkJvBk/DACiAgAAAA==.Raevenhart:BAACLgAFFH8GAAIVAAMJlgi7IACnAAAVAAMJlgi7IACnAAAuAAQKfx0AAhUACAlZFWIkAAUCABUACAlZFWIkAAUCAAAA.Rainstorm:BAAALgADCgQJBAAAAA==.Rappa:BAAALgADCgEJAQAAAA==.Raptorx:BAAALgADCggJCAAAAA==.Raymond:BAAALgADCgcJBwAAAA==.Razerblade:BAAALgAECgEJAQAAAA==.',
Re='Rebarbative:BAABLgAECn8iAAMMAAkJoQ5cSwC4AQAMAAkJoQ5cSwC4AQAmAAMJfAXZUQB5AAAAAA==.Redvex:BAACLgAFFH8OAAIMAAQJXhj+RABAAQAMAAQJXhj+RABAAQAuAAQKf0UABAwACQnFJYsEAEcDAAwACQmQJYsEAEcDACYABQkxII8SALcBABEAAglwI5ckAJ4AAAAA.Rei:BAAALgAECgEJAQAAAA==.Reinhard:BAABLgAECn83AAMPAAkJtxBnAwAQAQAlAAYJvRLtHQAaAQAPAAkJ2A9nAwAQAQAAAA==.Revengè:BAAALgADCgQJBAAAAA==.Rewrew:BAABLgAECn8sAAIQAAkJhRofEwB4AgAQAAkJhRofEwB4AgAAAA==.',
Rh='Rhedman:BAABLgAECn8aAAMdAAYJ7QqrHADpAAAdAAUJ7QqrHADpAAAeAAYJdAUy7wDBAAAAAA==.',
Ri='Ricasti:BAAALgAECgUJCgAAAA==.Rinahrune:BAAALgAECgMJBgAAAA==.Rinahvoid:BAAALgADCgcJBwAAAA==.',
Ro='Robat:BAAALgADCggJDQAAAA==.Ronwen:BAAALgAECgQJBAABLgAFFAUJFwAQAFQGAA==.Rosanna:BAAALgAECggJCgAAAA==.Roselyn:BAABLgAECn8VAAITAAcJaxG+KgByAQATAAcJaxG+KgByAQAAAA==.Rotyr:BAABLgAECn9AAAIKAAkJLhlYAABGAgAKAAkJLhlYAABGAgAAAA==.',
Ru='Ruana:BAEALgAECgUJDgAAAA==.Rubyrazor:BAAALgAECgQJBgAAAA==.Rumpunch:BAAALgAECgEJAQAAAA==.',
Sa='Safetydance:BAAALgAECgIJAgAAAA==.Salil:BAAALgADCgMJAwAAAA==.Salothos:BAAALgADCgYJBgAAAA==.Samesh:BAAALgAECgQJCAAAAA==.Sandrace:BAAALgADCgIJAgAAAA==.Sanginie:BAAALgADCgEJAQAAAA==.Santhela:BAAALgAECgQJBAAAAA==.Satrana:BAAALgADCgMJAwAAAA==.Saturñ:BAAALgAECgYJEgAAAA==.Sauroman:BAAALgAECgUJDgAAAA==.',
Sc='Scoobey:BAABLgAECn8lAAIUAAgJtBp5MwAOAgAUAAgJtBp5MwAOAgAAAA==.Scots:BAAALgADCgMJAwAAAA==.Scubbs:BAACLgAFFH8VAAIEAAUJ4xIeJQBXAQAEAAUJ4xIeJQBXAQAuAAQKfyEAAgQACAkuFkkiABECAAQACAkuFkkiABECAAAA.Scubbsboo:BAABLgAECn8bAAIWAAcJqBufHAAzAgAWAAcJqBufHAAzAgABLgAFFAUJFQAEAOMSAA==.',
Se='Seras:BAAALgAECgUJBQAAAA==.Serka:BAAALgADCgYJBgAAAA==.Servantes:BAABLgAECn9KAAMXAAkJghCQOAC0AQAXAAkJghCQOAC0AQAFAAEJTwW1ngAjAAAAAA==.',
Sh='Shackleford:BAABLgAECn9HAAQKAAkJ4h4ZDQCbAgAKAAkJ4h4ZDQCbAgAJAAgJpRZ3GwDpAQATAAcJLBO/LABlAQAAAA==.Shamrockk:BAAALgADCgIJAgAAAA==.Shamwõwz:BAAALgAFFAMJBAAAAA==.Sheck:BAAALgAECgEJAQAAAA==.Shessofine:BAAALgAECggJCgAAAA==.Shotya:BAABLgAECn9NAAIUAAkJlwvOTQC5AQAUAAkJlwvOTQC5AQAAAA==.Shyvàna:BAAALgAECgIJAgAAAA==.',
Si='Siath:BAABLgAECn8UAAMGAAgJ6wtkQQAkAQAGAAgJ6wtkQQAkAQAnAAIJ6gg7PQA5AAAAAA==.Silvino:BAAALgADCgEJAQABLgAECgkJLwAFAMAbAA==.Sixpacktnt:BAAALgADCgkJMAAAAA==.Sixthknight:BAABLgAECn8gAAIPAAYJzggw3wDfAAAPAAYJzggw3wDfAAAAAA==.',
Sl='Slarr:BAAALgADCgEJAgAAAA==.',
Sm='Smight:BAABLgAECn8eAAIQAAgJXyaqBABNAwAQAAgJXyaqBABNAwAAAA==.',
Sn='Snacky:BAAALgAECgIJAgAAAA==.Snarkypony:BAAALgAECgYJDwAAAA==.',
So='Solani:BAAALgADCgYJCQAAAA==.Solania:BAAALgAECgYJCgAAAA==.Soloqenjoyer:BAAALgAECgUJBQAAAA==.Sorocide:BAAALgADCgUJBQAAAA==.Sorsere:BAABLgAECn81AAIMAAkJcR0VFACtAgAMAAkJcR0VFACtAgAAAA==.',
Sp='Spcecialk:BAABLgAECn8dAAIZAAcJLQumKADvAAAZAAcJLQumKADvAAAAAA==.Specialk:BAACLgAFFH8IAAIcAAIJ0wsMRgBzAAAcAAIJ0wsMRgBzAAAuAAQKfz4AAxwACAlJEroyAHIBABwACAlJEroyAHIBAAQAAwmsBrmxAGYAAAAA.',
Sq='Squallie:BAABLgAECn8ZAAIXAAYJqRNNTwBSAQAXAAYJqRNNTwBSAQAAAA==.',
St='Starcaller:BAAALgAECgYJBgAAAA==.Steamedhams:BAAALgAECgcJCwAAAA==.Stirredihime:BAAALgAECgUJCgAAAA==.',
Su='Sundorei:BAAALgAECgQJBgAAAA==.',
['Sû']='Sûlph:BAAALgAECgkJAwAAAA==.',
Ta='Taartt:BAAALgAFFAQJBAABLgAFFAcJJwABAJkTAA==.Tahoe:BAAALgADCgIJAgAAAA==.Talan:BAAALgAECgcJCgABLgAFFAcJEAADALUKAA==.Talshekar:BAABLgAECn8lAAInAAgJsw3RCgBuAQAnAAgJsw3RCgBuAQAAAA==.Tarsis:BAABLgAECn8oAAINAAkJeB9+BQDRAgANAAkJeB9+BQDRAgAAAA==.',
Te='Teiana:BAABLgAECn8pAAIPAAkJ9x8fJAB0AgAPAAkJ9x8fJAB0AgAAAA==.Tezlyn:BAAALgAECgEJAgAAAA==.',
Th='Thaevin:BAABLgAECn8hAAIPAAkJrhMBTwDbAQAPAAkJrhMBTwDbAQAAAA==.Therony:BAAALgAECgkJBQAAAA==.Thingwan:BAACLgAFFH8KAAIXAAUJJBXEHgBjAQAXAAUJJBXEHgBjAQAuAAQKfzYAAhcACQk4G9kQAMoCABcACQk4G9kQAMoCAAAA.Thordak:BAAALgADCggJDQABLgAECggJGwAPADsRAA==.',
Ti='Tiamat:BAAALgAECgkJCQAAAA==.Timbuktoo:BAAALgAECgUJDgAAAA==.Tinypoop:BAABLgAECn8WAAICAAYJVBVjrwAiAQACAAYJVBVjrwAiAQAAAA==.Tinystain:BAAALgADCgcJDQAAAA==.Tinystink:BAABLgAECn8oAAIMAAkJVx9FAADAAgAMAAkJVx9FAADAAgAAAA==.Tiptugger:BAAALgAECgIJAgAAAA==.',
To='Toddstephens:BAABLgAECn8gAAIdAAYJihdxEQBhAQAdAAYJihdxEQBhAQAAAA==.Tors:BAACLgAFFH8MAAIFAAMJxwwMBQB4AAAFAAMJxwwMBQB4AAAuAAQKf1cAAwUACQnbHTUJAMACAAUACQnbHTUJAMACAAcAAgnYE5pPAG8AAAAA.',
Tr='Trasky:BAAALgAECgEJAQAAAA==.Trogdore:BAAALgAECgYJDQAAAA==.Trollololo:BAABLgAECn9LAAMCAAkJuRqIJACKAgACAAkJuRqIJACKAgAoAAMJ+wfsCgCPAAAAAA==.Troy:BAABLgAECn8qAAICAAkJXx4BJACNAgACAAkJXx4BJACNAgAAAA==.Truid:BAAALgADCgEJAQAAAA==.Trylly:BAAALgAECgYJCAABLgAECggJFAAMADwUAA==.',
Tt='Ttaartt:BAACLgAFFH8nAAMBAAcJmRNmCgAFAgABAAcJmRNmCgAFAgAGAAQJyxDtQQC/AAAuAAQKfx0AAgEABwmqGfESABICAAEABwmqGfESABICAAAA.',
Tu='Tuckstaken:BAAALgAECgIJAgAAAA==.',
Ty='Typh:BAACLgAFFH8WAAIiAAQJ2yAVAwBzAQAiAAQJ2yAVAwBzAQAuAAQKf0QAAiIACQm5JXUAAF4DACIACQm5JXUAAF4DAAAA.Tyr:BAAALgAECgkJBwAAAA==.Tyrone:BAABLgAECn8kAAMaAAkJcRqLDQBtAgAaAAkJcRqLDQBtAgAWAAQJABCtdwC1AAAAAA==.Tyrslan:BAAALgAECgYJCwAAAA==.',
Uf='Uffish:BAAALgAECgkJCQAAAQ==.',
Ug='Uglymagi:BAAALgAECgMJBAAAAA==.',
Un='Undeaddemon:BAABLgAECn8jAAQMAAkJJR3BOQDzAQAMAAgJJR3BOQDzAQARAAMJEQ8THwB4AAAmAAEJkAbJeAAqAAAAAA==.Undeaddh:BAAALgAECgIJAgABLgAECgkJIwAMACUdAA==.Undeadmaggot:BAAALgADCggJFAABLgAECgkJIwAMACUdAA==.Undeadscaly:BAAALgAECgYJBwABLgAECgkJIwAMACUdAA==.Undignified:BAABLgAECn9OAAIiAAkJChkaAAAVAgAiAAkJChkaAAAVAgAAAA==.Unholysixth:BAAALgADCgkJNAAAAA==.Unicornquen:BAAALgAECgEJAQAAAA==.',
Ur='Uriyah:BAAALgAECgEJAQAAAA==.',
Uz='Uzzìel:BAAALgADCgEJAQAAAA==.',
Va='Valkar:BAAALgAECgEJAgAAAA==.Vanidarr:BAAALgADCgEJAQAAAA==.',
Ve='Verasia:BAAALgAECgUJEQAAAA==.',
Vi='Vidikan:BAAALgAECgQJDwAAAA==.Vie:BAAALgAECgEJAQAAAA==.',
Vo='Voidwarranty:BAACLgAFFH8FAAIEAAMJAAtZWwCWAAAEAAMJAAtZWwCWAAAuAAQKfzQAAwQACQl0F+AiAD0CAAQACQl0F+AiAD0CABwABwmRFpAkAMMBAAAA.Vontoot:BAAALgADCgEJAQAAAA==.',
Vv='Vvumpscut:BAABLgAECn8gAAIEAAkJaxodIABPAgAEAAkJaxodIABPAgAAAA==.',
Vy='Vysena:BAAALgAECgEJAwAAAA==.',
Wa='Waldón:BAABLgAECn9LAAIoAAkJPg3+BACRAQAoAAkJPg3+BACRAQAAAA==.',
We='Weatherley:BAAALgAECgEJAQAAAA==.Werrik:BAABLgAECn8aAAIMAAkJXyX8IgCJAgAMAAkJXyX8IgCJAgABLgAFFAIJAgALAAAAAA==.',
Wh='Whiskeytap:BAAALgAECgIJAgAAAA==.',
Wi='Wildsoul:BAABLgAECn8jAAIEAAcJPxJXUgBqAQAEAAcJPxJXUgBqAQAAAA==.Winchester:BAAALgADCgMJAwAAAA==.',
Wo='Wolfguardiån:BAAALgADCgMJAwAAAA==.',
Wr='Wrenz:BAAALgAECgQJDAAAAA==.',
Wu='Wuha:BAAALgADCgEJAQAAAA==.',
['Wä']='Wärhämmer:BAAALgADCgcJCgAAAA==.',
Xa='Xaneva:BAAALgADCgEJAgABLgAFFAYJKQAIAPYiAA==.Xanxer:BAAALgADCgQJBQAAAA==.',
Xc='Xclaw:BAABLgAECn8aAAIOAAkJ+woyGgDNAQAOAAkJ+woyGgDNAQAAAA==.',
Xe='Xeroxgravîty:BAAALgAECgEJAQAAAA==.Xeroxpriest:BAAALgAECgcJCwAAAA==.',
Xi='Xilphira:BAAALgAECgUJCQAAAA==.',
Xl='Xlithz:BAABLgAECn8wAAMgAAkJHxuZFgA6AgAgAAkJFhuZFgA6AgAhAAgJPhIhHQB0AQAAAA==.',
['Xí']='Xílo:BAEBLgAECn9MAAMDAAkJjh5BFQCZAgADAAkJcxxBFQCZAgASAAYJtx6SGAC+AQAAAA==.',
Yl='Ylene:BAABLgAECn82AAIXAAkJkBAkAQBPAQAXAAkJkBAkAQBPAQAAAA==.',
Yo='Yoink:BAACLgAFFH8TAAIeAAQJkxrAVQBGAQAeAAQJkxrAVQBGAQAuAAQKfzsAAh4ACQk7JGwIAC8DAB4ACQk7JGwIAC8DAAAA.',
Za='Zalasham:BAAALgADCgIJAgAAAA==.Zarinchaos:BAAALgAECgUJBwAAAA==.Zarinfur:BAABLgAECn82AAIIAAkJHBnFBwBYAgAIAAkJHBnFBwBYAgAAAA==.',
Ze='Zedrin:BAAALgAECgQJBAAAAA==.Zein:BAAALgAECgQJCAAAAA==.Zentacle:BAAALgAECgIJAgAAAA==.Zente:BAACLgAFFH8IAAIUAAQJiAaNXgDoAAAUAAQJiAaNXgDoAAAuAAQKfy0AAxQABwmsG0pAAOEBABQABwmsG0pAAOEBABUAAQn1AJGZABsAAAAA.Zequill:BAABLgAECn9QAAIZAAkJOCRgAgAjAwAZAAkJOCRgAgAjAwAAAA==.Zevsticles:BAABLgAECn8sAAIUAAkJUx8UFwCAAgAUAAkJUx8UFwCAAgAAAA==.',
Zh='Zhom:BAACLgAFFH8XAAIVAAQJAyGuDgB1AQAVAAQJAyGuDgB1AQAuAAQKf0AAAhUACQkcJIgBAAYDABUACQkcJIgBAAYDAAAA.',
Zo='Zohm:BAAALgADCgMJAwAAAA==.Zolec:BAAALgADCgcJDgAAAA==.Zooj:BAABLgAECn9MAAIpAAkJQBseBQCVAgApAAkJQBseBQCVAgAAAA==.Zorlak:BAAALgAECgUJDQAAAA==.',
Zu='Zuxa:BAAALgADCgYJBgAAAA==.',
Zy='Zylofeather:BAAALgAECgUJBQAAAA==.',
['ße']='ßeast:BAABLgAECn8jAAIaAAgJiwn0NwAiAQAaAAgJiwn0NwAiAQAAAA==.',
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
