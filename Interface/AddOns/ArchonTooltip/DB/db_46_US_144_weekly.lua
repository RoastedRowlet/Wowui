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

local lookup = {'Evoker-Preservation','Rogue-Assassination','Mage-Frost','DemonHunter-Devourer','Shaman-Restoration','Druid-Balance','Evoker-Augmentation','Druid-Guardian','Druid-Feral','Priest-Shadow','Priest-Discipline','Unknown-Unknown','Warlock-Demonology','DeathKnight-Blood','Hunter-Survival','Paladin-Retribution','Paladin-Holy','Warlock-Affliction','DemonHunter-Havoc','Priest-Holy','Hunter-BeastMastery','Hunter-Marksmanship','Monk-Mistweaver','Druid-Restoration','Rogue-Subtlety','Warrior-Protection','Monk-Windwalker','Mage-Arcane','Shaman-Elemental','DeathKnight-Frost','DeathKnight-Unholy','Monk-Brewmaster','Warrior-Fury','Warrior-Arms','Rogue-Outlaw','DemonHunter-Vengeance','Paladin-Protection','Warlock-Destruction','Evoker-Devastation','Mage-Fire','Shaman-Enhancement',}
local provider = {region='US',realm='Llane',name='US',type='weekly',zone=46,date='2026-07-05',data={Ab='Abdervoke:BAABLgAECn8fAAIBAAkJRyL4AQBkAwABAAkJRyL4AQBkAwAAAA==.Absent:BAAALgADCgEJAQAAAA==.',
Ac='Account:BAAALgADCgIJAgAAAA==.',
Ae='Aeila:BAAALgADCgYJBgAAAA==.',
Ah='Ahsoul:BAAALgAECgEJAgAAAA==.',
Ai='Ainur:BAAALgAECgEJAQABLgAECgkJWAACAI8aAA==.',
Al='Alesia:BAAALgADCgEJAQAAAA==.Alessaah:BAAALgADCgcJCgAAAA==.Aliadra:BAABLgAECn8zAAIDAAkJSSJvDwD/AgADAAkJSSJvDwD/AgAAAA==.Alistus:BAACLgAFFH8VAAIEAAQJPiWmDQB7AQAEAAQJPiWmDQB7AQAuAAQKfz8AAgQACQlZJccDAEoDAAQACQlZJccDAEoDAAAA.Alphá:BAAALgAECgUJCQABLgAFFAMJBQAFAAALAA==.Altholar:BAAALgADCgcJBwAAAA==.',
An='Anexxia:BAAALgAECgQJCQAAAA==.Angel:BAAALgAECgYJDwAAAA==.Angua:BAABLgAECn9cAAIGAAkJVh00AgC8AQAGAAkJVh00AgC8AQAAAA==.',
Ar='Arcanegarm:BAABLgAECn8bAAIDAAcJIAJZ/wCuAAADAAcJIAJZ/wCuAAAAAA==.Archeyois:BAABLgAECn8pAAMHAAkJVA9GKwCRAQAHAAkJVA9GKwCRAQABAAUJhQIRNwCzAAAAAA==.Armitage:BAABLgAECn8YAAMIAAkJ/w+0HABnAQAIAAkJXQ+0HABnAQAJAAcJQgvyHgARAQAAAA==.Arthonos:BAACLgAFFH8GAAIKAAIJVAUBNABzAAAKAAIJVAUBNABzAAAuAAQKfzUAAwoACQmaFQ8ZAP0BAAoACQmaFQ8ZAP0BAAsACAnjBWQnAFoBAAAA.Arugall:BAAALgAECgcJBwAAAA==.',
As='Ashmall:BAAALgAECgQJBAAAAA==.',
Av='Averille:BAAALgADCgYJCwAAAA==.',
Ay='Ayraa:BAAALgAECgYJBAAAAA==.',
Az='Azerphage:BAAALgAECgYJDwABLgAECgcJCwAMAAAAAA==.Azeura:BAAALgADCgQJBAAAAA==.Azhorra:BAABLgAECn8VAAINAAYJOwrVrgDmAAANAAYJOwrVrgDmAAAAAA==.Azzog:BAABLgAECn8bAAIOAAkJexfhAgBlAQAOAAkJexfhAgBlAQAAAA==.Azül:BAAALgAECgYJBgABLgAECgcJCwAMAAAAAA==.',
Ba='Bacchanalian:BAAALgAECgcJDAABLgAECgkJCwAMAAAAAA==.Baindyn:BAAALgAECgQJEwAAAA==.Barator:BAAALgAECgcJCwAAAA==.Barky:BAAALgADCgEJAQAAAA==.Bas:BAAALgAFFAEJAgAAAA==.',
Bi='Bickkbatwolf:BAAALgADCgYJDQAAAA==.Bigwhisky:BAAALgAECgcJEAAAAA==.',
Bl='Blackröse:BAACLgAFFH8GAAIPAAMJCRaVCADaAAAPAAMJCRaVCADaAAAuAAQKfyMAAg8ACAkzHYMQACoCAA8ACAkzHYMQACoCAAAA.Blackrøse:BAABLgAECn8pAAIFAAkJHxfKBAChAQAFAAkJHxfKBAChAQABLgAFFAMJBgAPAAkWAA==.Bladebane:BAABLgAECn8lAAIOAAkJGgFPPQCbAAAOAAkJGgFPPQCbAAAAAA==.Blandmonk:BAAALgAECgMJBAAAAA==.Blksunshine:BAAALgAECgcJCwAAAA==.',
Bo='Bolash:BAAALgAECgYJCwAAAA==.Boomnbloom:BAAALgAECgMJAwAAAA==.Bort:BAAALgAECgEJBAAAAA==.',
Br='Bradthomas:BAAALgAECgQJBQAAAA==.Breegorn:BAAALgAECgUJBgAAAA==.Breni:BAAALgAFFAEJAQAAAA==.Bruscha:BAAALgAECgUJDwAAAA==.',
Bu='Bulvhine:BAABLgAECn8xAAIQAAkJfyAqAgCOAgAQAAkJfyAqAgCOAgAAAA==.',
Ca='Camferd:BAAALgAECgEJAQAAAA==.Camford:BAABLgAECn8ZAAIDAAcJ8QhZvQBoAQADAAcJ8QhZvQBoAQAAAA==.Cantatrix:BAABLgAECn8bAAINAAYJ9gt4owD5AAANAAYJ9gt4owD5AAAAAA==.Capslok:BAAALgAFFAEJAQAAAA==.Captinmeat:BAAALgAECgUJCAAAAA==.Cargoan:BAAALgAECgIJAgAAAA==.Cashkin:BAAALgADCgYJBgAAAA==.Cassiela:BAAALgAECgYJBgABLgAECgkJCwAMAAAAAA==.',
Ce='Cecilx:BAABLgAECn8zAAIRAAkJWCRrAgCGAwARAAkJWCRrAgCGAwAAAA==.Cellybelleri:BAAALgAECgQJBAAAAA==.',
Ch='Chaac:BAAALgADCgEJAQAAAA==.Charmander:BAAALgADCgcJCAAAAA==.Chayton:BAAALgADCgUJBQAAAA==.Cherrypie:BAAALgAECgYJBgAAAA==.Chillana:BAAALgAECgQJBAAAAA==.Chimerax:BAACLgAFFH8aAAMSAAUJPyB4AgCDAQASAAUJPyB4AgCDAQANAAEJlxedwQBHAAAuAAQKfy0AAxIACQljHwACALACABIACAlCIgACALACAA0ACAlDEwt8AEEBAAAA.Chloede:BAAALgADCgUJBQAAAA==.Chlorpyrifos:BAAALgADCgEJAQAAAA==.Chrismikea:BAABLgAECn8cAAIQAAgJMAZQoQA9AQAQAAgJMAZQoQA9AQAAAA==.Chronic:BAAALgAECgQJBwAAAA==.Chully:BAACLgAFFH8PAAIEAAQJZRDlSAAOAQAEAAQJZRDlSAAOAQAuAAQKfywAAwQACQkIG2AqACACAAQACQkIG2AqACACABMAAwmIBM1ZAH0AAAAA.',
Cl='Clairíty:BAABLgAECn8fAAIUAAgJsh4DDgCGAgAUAAgJsh4DDgCGAgAAAA==.Clarky:BAAALgAECgYJEAAAAA==.Click:BAABLgAECn9EAAIVAAkJUxzvEwCzAgAVAAkJUxzvEwCzAgAAAA==.Cloutfarmer:BAACLgAFFH8QAAIVAAQJGyC5KQBhAQAVAAQJGyC5KQBhAQAuAAQKf0AABBUACQlKJf0EAEEDABUACQlKJf0EAEEDABYABgkZHFspAOABAA8AAglFHfpVAFUAAAAA.',
Co='Comadore:BAACLgAFFH8QAAIQAAUJDQyFWgD7AAAQAAUJDQyFWgD7AAAuAAQKfxwAAhAACAk4HNg4AEACABAACAk4HNg4AEACAAAA.Coronae:BAAALgAECgIJAwAAAA==.Corrose:BAAALgADCgEJAQAAAA==.',
Cr='Crankshanker:BAAALgAECgEJAQAAAA==.Cratora:BAAALgAECgYJBgAAAA==.Credan:BAEBLgAECn8VAAIXAAkJMyIQBgBFAwAXAAkJMyIQBgBFAwABLgADCgYJBgAMAAAAAA==.Critmypants:BAAALgAECgIJAgAAAA==.',
Cy='Cylithina:BAAALgAECgQJCgAAAA==.Cytochrome:BAAALgADCgQJBAAAAA==.',
Da='Dalair:BAAALgAECgQJBAAAAA==.Daphe:BAAALgAECgEJAwAAAA==.Dartheior:BAAALgAECgEJAQAAAA==.Dawggbiscuit:BAAALgAECgQJBQAAAA==.',
De='Deadiam:BAAALgAECgEJAgAAAA==.Deadseksi:BAAALgAECgcJEAAAAA==.Deathslead:BAABLgAECn9MAAMVAAkJSxeaAwAiAgAVAAkJSxeaAwAiAgAWAAUJ3AHpMQBSAAAAAA==.Decrepe:BAACLgAFFH8RAAIYAAQJ2BhjJwAhAQAYAAQJ2BhjJwAhAQAuAAQKfzsAAhgACQlIIIAKABUDABgACQlIIIAKABUDAAAA.Dedrepe:BAAALgAECggJCQAAAA==.Delph:BAAALgAFFAEJAQAAAA==.Deshal:BAAALgAECgQJDAAAAA==.Desomas:BAAALgAECgIJAgAAAA==.Dethklock:BAAALgAECgEJAQAAAA==.Dethwingchun:BAAALgAECgMJAwABLgAECgQJEwAMAAAAAA==.Detrath:BAAALgAECgEJAQAAAA==.',
Di='Dieurnal:BAAALgAECgQJAQAAAA==.Discostar:BAABLgAECn8pAAMYAAgJohlaLgDsAQAYAAcJghhaLgDsAQAGAAYJiBKXLwBhAQAAAA==.Distill:BAAALgAECgEJAQABLgAFFAkJIAAZAN4hAA==.',
Dn='Dni:BAAALgAECgMJBAABLgAECgkJLwAGAMAbAA==.',
Do='Dominicm:BAAALgAECgYJEgAAAA==.Dotdotdis:BAAALgAECgMJAwAAAA==.',
Dr='Dracanalian:BAAALgADCgkJCQAAAA==.Dragonpro:BAAALgADCgUJBQAAAA==.Drajhar:BAAALgAECgkJBQAAAA==.Drakyore:BAAALgADCgIJAwAAAA==.Draq:BAAALgAECgcJCwAAAA==.Druth:BAABLgAECn8tAAIaAAgJRx++CgBDAgAaAAgJRx++CgBDAgAAAA==.',
Eb='Ebonhorn:BAAALgAECgUJEQAAAA==.',
Ee='Eevillean:BAAALgAECgEJAQAAAA==.',
Ei='Einari:BAAALgAECggJCAAAAA==.Einark:BAABLgAECn9PAAMXAAkJASAIAQC0AgAXAAkJASAIAQC0AgAbAAgJzB4uDQByAgAAAA==.',
Ek='Ekiim:BAAALgAECgQJBAABLgAECgQJCQAMAAAAAA==.',
El='Eldrond:BAAALgAECgQJCAABLgAECgUJCQAMAAAAAA==.Elinis:BAAALgAFFAEJAQAAAA==.Elska:BAAALgADCgkJCQAAAA==.',
En='Ennauríon:BAAALgAECgUJCQAAAA==.Entropy:BAEALgAFFAIJAgABLgAFFAMJBwAcADUOAA==.',
Er='Eridor:BAAALgAECgcJEQAAAA==.Erissama:BAAALgADCgEJAQAAAA==.',
Ex='Exek:BAABLgAECn8yAAMUAAgJsBcvFwAVAgAUAAgJsBcvFwAVAgAKAAYJCA7mCQCzAAAAAA==.',
Ey='Eyeofnature:BAAALgAECgEJAQAAAA==.',
Ez='Ez:BAAALgAECgEJAQABLgAECgkJMAAdACgbAA==.',
Fa='Fabaztard:BAABLgAECn8kAAIGAAkJ1hIuIwCwAQAGAAkJ1hIuIwCwAQAAAA==.Faline:BAABLgAECn8zAAIYAAkJUwvJRQB5AQAYAAkJUwvJRQB5AQAAAA==.',
Fe='Felgetabouit:BAACLgAFFH8aAAIEAAUJUhNoSgAKAQAEAAUJUhNoSgAKAQAuAAQKfyMAAgQACQlUGs00ACUCAAQACQlUGs00ACUCAAAA.Felghoul:BAAALgAECgcJEgAAAA==.Felldozer:BAAALgAECgEJAQAAAA==.Fenrakar:BAAALgAECgQJBwAAAA==.Feywynn:BAAALgAECggJBwAAAA==.',
Fi='Fights:BAABLgAECn9BAAIRAAkJKR4HCgDrAgARAAkJKR4HCgDrAgAAAA==.',
Fl='Fleshworker:BAAALgADCgEJAQAAAA==.Floofi:BAAALgAECgcJCgAAAA==.',
Fo='Fordalliance:BAAALgADCgcJBwAAAA==.Forky:BAAALgAECgQJCAAAAA==.Foxknight:BAABLgAECn8UAAQeAAUJaxAdGgABAQAeAAUJaxAdGgABAQAfAAMJ7AsaFAGTAAAOAAQJ4QM2SwBiAAAAAA==.',
Fr='Franciss:BAAALgAECgYJDQAAAA==.Francys:BAAALgADCgIJAwAAAA==.Franksnbeans:BAAALgAECgEJAgABLgAECgYJEgAMAAAAAA==.Frostdrake:BAAALgAECgIJAgAAAA==.',
Ft='Ftx:BAABLgAECn8gAAMgAAgJuh+oDQC4AgAgAAgJlR+oDQC4AgAbAAQJ2hm/RgD6AAAAAA==.',
Fu='Fubbleskag:BAABLgAECn8xAAIQAAkJARwsOAAhAgAQAAkJARwsOAAhAgAAAA==.Fullmoonn:BAAALgAECgIJAwAAAA==.',
Ga='Gaern:BAAALgAECgEJAwABLgAFFAIJAgAMAAAAAA==.Gaidan:BAACLgAFFH8QAAIGAAUJzRDbCgALAQAGAAUJzRDbCgALAQAuAAQKfyEAAgYACQmlFogRAI8CAAYACQmlFogRAI8CAAEuAAUUBwkRAAQAtQoA.Gaidin:BAACLgAFFH8RAAIEAAcJtQpjLAB1AQAEAAcJtQpjLAB1AQAuAAQKfyAAAgQACQlGHgY9ANQBAAQACQlGHgY9ANQBAAAA.Gameslayer:BAABLgAECn8gAAMhAAkJcB2dKwCmAQAhAAYJcx+dKwCmAQAiAAQJzxdeMQACAQAAAA==.Gankzilla:BAACLgAFFH8aAAMZAAUJHRbUGQBGAQAZAAUJHRbUGQBGAQACAAEJbBG+EABOAAAuAAQKfycAAwIACQmeG2EJAKoBABkABgl3GNklAMoBAAIABwkfG2EJAKoBAAAA.Garothos:BAAALgAECgIJAgABLgAECgQJBwAMAAAAAA==.Gatanikaz:BAAALgAECgIJBAAAAA==.',
Ge='Genrealwee:BAAALgAECgEJAQAAAA==.Get:BAAALgADCgkJDAAAAA==.',
Gh='Ghalumvhar:BAABLgAECn8fAAIQAAcJBRtXTwDaAQAQAAcJBRtXTwDaAQAAAA==.Ghoulaid:BAAALgAECgcJBwAAAA==.Ghrìmm:BAABLgAECn8lAAQPAAkJ6w/EGgDIAQAPAAkJIA3EGgDIAQAVAAgJxA5OaQBwAQAWAAEJ+QZkRAAiAAAAAA==.',
Gi='Gila:BAAALgAECggJEAAAAA==.Gingasorrow:BAABLgAECn80AAIYAAkJnBkLFgCYAgAYAAkJnBkLFgCYAgAAAA==.Gizzle:BAACLgAFFH8SAAIQAAUJsxDQWAD+AAAQAAUJsxDQWAD+AAAuAAQKfyYAAhAACQmoFltVAMoBABAACQmoFltVAMoBAAAA.',
Gr='Greekfire:BAABLgAECn8YAAIRAAgJ3yE5GwA7AgARAAgJ3yE5GwA7AgAAAA==.Grimgrug:BAAALgADCgUJBQAAAA==.Grishna:BAAALgADCggJCAAAAA==.Grumrok:BAAALgAECgQJBgAAAA==.Grunbar:BAABLgAECn80AAIVAAgJqSKCGQCNAgAVAAgJqSKCGQCNAgAAAA==.Grændal:BAABLgAECn8aAAIKAAcJiBjRAgCPAQAKAAcJiBjRAgCPAQABLgAFFAcJEQAEALUKAA==.',
Ha='Hahatotem:BAAALgADCgMJAwAAAA==.Hanjha:BAABLgAECn9HAAMPAAkJkR/AAwD4AgAPAAgJkR/AAwD4AgAVAAEJAAA7zwA3AAAAAA==.Harunhwa:BAAALgAECgIJAgAAAA==.Haseo:BAAALgAECgEJAQABLgAECgkJWAACAI8aAA==.Hatz:BAAALgADCgcJBgAAAA==.',
He='Healshot:BAAALgADCgMJAwABLgAECgUJFQAQAGUmAA==.Helldozer:BAABLgAECn9JAAMdAAkJLxYOGAAjAgAdAAkJLxYOGAAjAgAFAAIJzxRcpwB9AAAAAA==.',
Ho='Hooj:BAAALgADCgYJBgAAAA==.Horde:BAAALgADCgEJAQAAAA==.',
Ht='Ht:BAAALgADCgMJCAAAAA==.',
Hu='Hugzy:BAABLgAECn8WAAIDAAYJDA2YEAD2AAADAAYJDA2YEAD2AAAAAA==.',
Hw='Hwore:BAAALgAECgQJBAAAAA==.',
Hy='Hydatos:BAAALgADCgMJAwABLgAECgYJCgAMAAAAAA==.Hypnocide:BAEBLgAECn9RAAIEAAkJLBm8AQA1AgAEAAkJLBm8AQA1AgAAAA==.',
['Hô']='Hôneynuts:BAAALgADCgIJAgAAAA==.',
Ib='Ibuki:BAAALgAFFAEJAQABLgAFFAUJGgARAFQGAA==.',
Ic='Icepick:BAAALgADCgIJAgAAAA==.',
Id='Idleorc:BAAALgADCgcJDQAAAA==.',
Ig='Iguanajon:BAAALgAECgEJAgAAAA==.',
Il='Illandren:BAACLgAFFH8RAAIPAAQJlggaGAARAQAPAAQJlggaGAARAQAuAAQKfxsAAw8ACQljC+0cALUBAA8ACQljC+0cALUBABYACAk6A9gfALEAAAAA.Illusiveeyes:BAAALgADCgYJDAAAAA==.',
Im='Impsane:BAABLgAECn8uAAINAAkJ1hDMAwC2AQANAAkJ1hDMAwC2AQAAAA==.',
In='Incøgnitø:BAAALgAECgEJAQABLgAECgkJHQAYADIcAA==.Infernis:BAAALgADCgYJCQAAAA==.Innphyy:BAABLgAECn8jAAIDAAcJsQj0wgAFAQADAAcJsQj0wgAFAQAAAA==.Innøminate:BAABLgAECn8iAAIVAAgJwhGmBwCIAQAVAAgJwhGmBwCIAQABLgAECgkJHQAYADIcAA==.Inti:BAAALgADCgEJAQAAAA==.',
Ir='Irv:BAABLgAECn8WAAQCAAgJlhqJBwDgAQACAAgJ5xmJBwDgAQAZAAUJoxxSMwBwAQAjAAQJjg9mCQDZAAAAAA==.',
Is='Isadavrah:BAAALgADCgcJDAAAAA==.Isekai:BAAALgAECgQJBwAAAA==.Issadin:BAAALgAECgUJBwABLgAECgYJDAAMAAAAAA==.Issadruiid:BAAALgADCgYJBgABLgAECgYJDAAMAAAAAA==.Issammonk:BAAALgAECgEJAQABLgAECgYJDAAMAAAAAA==.Issarage:BAAALgAECgQJCQABLgAECgYJDAAMAAAAAA==.Issashammy:BAAALgAECgYJDAAAAA==.',
Ja='Jaxxa:BAABLgAECn88AAIVAAkJ6xqCHwBqAgAVAAkJ6xqCHwBqAgAAAA==.',
Je='Jeddiah:BAABLgAECn8kAAMCAAcJIQ/TDQBKAQACAAcJIQ/TDQBKAQAZAAQJLgxhRwCdAAAAAA==.',
Jh='Jhals:BAAALgADCgYJBgAAAA==.',
Ji='Jiffarous:BAAALgAECgQJBwAAAA==.Jinkès:BAABLgAECn8wAAIWAAgJvBUQCwC6AQAWAAgJvBUQCwC6AQAAAA==.',
Jp='Jpank:BAAALgAFFAEJAwAAAA==.',
Ju='Jubei:BAABLgAFFH8GAAIQAAUJaQx7hACrAAAQAAUJaQx7hACrAAAAAA==.Judis:BAABLgAECn9TAAICAAkJRR+8AQDiAgACAAkJRR+8AQDiAgAAAA==.Judyth:BAAALgAECgIJBQAAAA==.Juicy:BAAALgADCgIJAgAAAA==.Justokevoker:BAABLgAFFH8LAAIHAAQJpxHcMgD2AAAHAAQJpxHcMgD2AAAAAA==.',
Ka='Kainel:BAAALgAECgkJCQAAAA==.Kairì:BAAALgADCgcJDQAAAA==.Kalifist:BAABLgAECn8cAAIbAAkJnR97CAC/AgAbAAkJnR97CAC/AgAAAA==.Kalinear:BAAALgADCgQJBQAAAA==.Kalipally:BAAALgAECgcJDgAAAA==.Kaliscales:BAAALgAECgUJBQAAAA==.Kamiportal:BAAALgAECgcJCgAAAA==.Kanajotoma:BAAALgAECgUJEgAAAA==.Karlai:BAABLgAECn8tAAMfAAgJWByVBwBaAQAeAAcJuhrlBAAAAgAfAAcJhRuVBwBaAQABLgAFFAcJEQAEALUKAA==.Kaslana:BAEALgADCgYJBgAAAA==.',
Ke='Keldrune:BAAALgAECgYJDgAAAA==.Keleena:BAEBLgAECn9iAAIRAAkJaSDfAAB/AgARAAkJaSDfAAB/AgAAAA==.Kelume:BAAALgADCgMJAwAAAA==.Kely:BAAALgADCgUJBgAAAA==.',
Kg='Kgor:BAAALgAECgcJBwAAAA==.',
Kh='Khaerne:BAAALgAECgEJAQABLgAFFAIJAgAMAAAAAA==.Khordelia:BAAALgAFFAIJAgAAAA==.',
Ki='Kinst:BAABLgAECn9GAAMVAAkJxB8zEgDAAgAVAAkJxB8zEgDAAgAWAAYJrxLaPwBbAQAAAA==.Kirigaya:BAAALgAECgMJCQAAAA==.Kisäi:BAABLgAECn8pAAMEAAkJ1RxbIACPAgAEAAkJ1RxbIACPAgAkAAIJHBGVKABiAAAAAA==.Kitanyia:BAABLgAECn8jAAIhAAkJfw9KKQC0AQAhAAkJfw9KKQC0AQAAAA==.Kittiy:BAABLgAECn82AAMGAAgJ1wlMQwD/AAAGAAgJ1wlMQwD/AAAYAAYJKgdRfADDAAAAAA==.',
Ko='Kordelia:BAABLgAECn8mAAIDAAkJJh8cHwCjAgADAAkJJh8cHwCjAgABLgAFFAIJAgAMAAAAAA==.Korvus:BAAALgAECgcJEQAAAA==.',
Kv='Kv:BAAALgADCggJCAAAAA==.',
Ky='Kyakuna:BAAALgAECgIJAgAAAA==.Kylnara:BAAALgAECgUJCQAAAA==.Kyloon:BAAALgAECgEJAQAAAA==.Kyrah:BAABLgAECn9DAAMNAAkJrhqKAgAXAgANAAkJABiKAgAXAgASAAYJ3xvLBgDrAQAAAA==.',
La='Lamanira:BAAALgAECgcJCwAAAA==.Lancier:BAAALgAECgcJCwAAAA==.',
Ld='Ldyaria:BAAALgAECgMJAwAAAA==.',
Le='Lecleme:BAACLgAFFH8GAAIfAAMJZBEEoADUAAAfAAMJZBEEoADUAAAuAAQKfyEAAh8ACAleGE5IAOkBAB8ACAleGE5IAOkBAAAA.Lejend:BAABLgAECn9KAAMiAAkJyCXiAABxAwAiAAkJyCXiAABxAwAhAAMJfRW8fwC+AAAAAA==.Lenthalis:BAAALgAECgUJEQAAAA==.Lezriel:BAAALgAECgMJBgAAAA==.',
Li='Lichin:BAAALgADCgEJAQAAAA==.Lilithh:BAAALgADCgUJCAAAAA==.',
Ll='Llanedh:BAAALgAECggJDAAAAA==.',
Lo='Loaganic:BAAALgAECgQJBAABLgAECggJFAAHAOsLAA==.Lockheéd:BAAALgAFFAEJAQAAAA==.Lonelyhearts:BAABLgAECn89AAIQAAkJrQsRcwCIAQAQAAkJrQsRcwCIAQAAAA==.Lonestar:BAAALgAECgYJDwAAAA==.Lonestarr:BAAALgAECgQJDAAAAA==.Loxricia:BAAALgADCgEJAQAAAA==.',
Lu='Lumiya:BAABLgAECn8yAAIUAAkJ7w52LwCFAQAUAAkJ7w52LwCFAQAAAA==.',
Ly='Lytol:BAABLgAECn8qAAMcAAkJtReFAgAoAgAcAAkJtReFAgAoAgADAAMJXgQ8IgF1AAAAAA==.',
Ma='Machu:BAAALgADCgIJAgABLgAFFAQJCwAHANkVAA==.Madderhorn:BAAALgAECgcJBQAAAA==.Maege:BAAALgADCggJCAAAAA==.Maenad:BAAALgAECgkJCwAAAA==.Maeple:BAABLgAECn8pAAMUAAkJ+SEhBABDAwAUAAkJ+SEhBABDAwALAAMJugpfXgCFAAAAAA==.Magikin:BAAALgAECgQJCAAAAA==.Magrat:BAAALgAECgQJBAAAAA==.Mamichula:BAAALgAECgEJAQAAAA==.',
Mb='Mbdtf:BAACLgAFFH8eAAMPAAcJeiOZAAAaAgAPAAcJeiOZAAAaAgAWAAEJjAS6JABVAAAuAAQKfxsAAw8ABwmMJXMEANQCAA8ABwkxJXMEANQCABYAAQksIwR3AGMAAAEuAAUUCAkwAAMAuyUA.',
Me='Mechagnome:BAACLgAFFH8GAAIbAAIJoBsILgCQAAAbAAIJoBsILgCQAAAuAAQKfzQAAxsACQnUIMsHAMsCABsACQnUIMsHAMsCABcACAkJBAU6AAABAAAA.Meeps:BAAALgADCgcJBwAAAA==.Megamedes:BAABLgAECn8aAAMQAAYJkhbKegCEAQAQAAYJEhbKegCEAQAlAAQJTQn+NgCEAAAAAA==.Meigna:BAABLgAECn8qAAIKAAgJuR2MEQBKAgAKAAgJuR2MEQBKAgAAAA==.Mekö:BAAALgAECgYJDQAAAA==.Meladyn:BAACLgAFFH8qAAMJAAYJ9iKSBAByAQAJAAUJeyOSBAByAQAIAAUJMh4aCQBhAQAuAAQKfygAAwkABwlnJlYDAAMDAAkABwlnJlYDAAMDAAgABQnrIwEXAJoBAAAA.Melritza:BAAALgAECgQJCAAAAA==.Mentock:BAABLgAECn8YAAIDAAYJ4hCEqwApAQADAAYJ4hCEqwApAQAAAA==.Merdock:BAAALgAECgQJBAAAAA==.Merelandra:BAAALgADCgkJKQAAAA==.Mermaid:BAAALgAECgUJCgAAAA==.',
Mi='Michelle:BAAALgADCgQJBAAAAA==.Miliara:BAAALgADCgEJAQAAAA==.Miradh:BAEALgAECgMJAwABLgAECgUJDgAMAAAAAA==.Missmaam:BAABLgAECn8ZAAMUAAkJjRpdFQAqAgAUAAgJ2hldFQAqAgAKAAUJuxKZBgD0AAAAAA==.Mistroot:BAAALgAECgkJDAAAAA==.Mistshealz:BAAALgAECgEJAQABLgAFFAQJDwAfAMQdAA==.Mithrandir:BAACLgAFFH8FAAMNAAIJxwARxABFAAANAAIJxwARxABFAAAmAAEJOQDVLQATAAAuAAQKfyQAAw0ABwmWEPhxAFYBAA0ABwmWEPhxAFYBACYABAnEDAgGAH8AAAAA.Mixcoati:BAAALgADCgQJBQAAAA==.Mizu:BAABLgAECn8cAAMaAAkJyxsdDwD4AQAaAAkJyxsdDwD4AQAhAAIJ6xAGlABvAAAAAA==.',
Mo='Moe:BAAALgAECgkJBAAAAA==.Monkfox:BAAALgAECgcJBwAAAA==.Morgianna:BAAALgADCgEJAQAAAA==.',
Mu='Mudanca:BAAALgAECgMJAwABLgAECgUJDwAMAAAAAA==.Mudflap:BAABLgAECn8VAAIVAAYJBg35GgCgAAAVAAYJBg35GgCgAAAAAA==.Mushuwoonter:BAAALgAECgEJAQABLgAFFAQJCwAHANkVAA==.Muztang:BAABLgAECn9CAAMiAAkJ1x5vBADUAgAiAAkJ1x5vBADUAgAhAAYJihOETgAOAQAAAA==.',
Mw='Mwmmwmm:BAAALgAECgYJCgAAAA==.',
My='Mythandwel:BAABLgAECn8vAAITAAgJZArjLQAUAQATAAgJZArjLQAUAQAAAA==.',
['Mä']='Mäddiey:BAAALgAECgQJCgAAAA==.',
['Mô']='Mônkii:BAACLgAFFH8TAAIgAAQJESXZDgCyAQAgAAQJESXZDgCyAQAuAAQKfz4AAyAACQnjJLICAC4DACAACQnjJLICAC4DABcAAQmvAhzfABEAAAAA.',
Na='Nace:BAABLgAECn8qAAIZAAkJ7BOvGQA2AgAZAAkJ7BOvGQA2AgAAAA==.Nadriede:BAAALgADCgYJBgAAAA==.Naenia:BAAALgAECgUJBQAAAA==.Naillimixam:BAAALgADCgMJAgAAAA==.Nariar:BAAALgAECgMJAwABLgAFFAUJGgARAFQGAA==.Nateldin:BAABLgAECn8YAAMQAAkJhwmIkABbAQAQAAkJ8AeIkABbAQAlAAIJ9Q61UgArAAAAAA==.',
Ne='Neoba:BAAALgAECgUJCAAAAA==.',
Ni='Nicksevokerc:BAAALgAECggJBwAAAA==.Niisha:BAAALgAECggJDQABLgAECgkJHwAUAKMHAA==.Nikiso:BAAALgADCgYJBwAAAA==.',
No='Nocainus:BAABLgAECn9NAAIOAAkJwCGJAwAFAwAOAAkJwCGJAwAFAwAAAA==.Nosehole:BAABLgAECn8iAAIFAAcJ0hTZPAC7AQAFAAcJ0hTZPAC7AQAAAA==.Novari:BAAALgADCgkJCQAAAA==.',
Nv='Nv:BAAALgADCgEJAQABLgAFFAUJBQAbAGgFAA==.',
['Nø']='Nøtsure:BAABLgAECn8dAAMYAAkJMhy4JQAgAgAYAAkJMhy4JQAgAgAGAAIJqwyJdABdAAAAAA==.',
Ob='Obesityy:BAABLgAECn8xAAIZAAkJph5yCACfAgAZAAkJph5yCACfAgAAAA==.Obsidia:BAABLgAECn8oAAINAAkJSQ8VSwC5AQANAAkJSQ8VSwC5AQAAAA==.',
Oc='Octopusprime:BAAALgAECgkJEQAAAA==.',
Ol='Oled:BAAALgADCgIJAgAAAA==.Ollix:BAAALgAECgEJBAABLgAECgkJTAAEAI4eAA==.',
Om='Omelette:BAABLgAECn8fAAIVAAkJiRz9GwB9AgAVAAkJiRz9GwB9AgAAAA==.',
On='Onik:BAAALgADCgcJDQABLgAECgUJCQAMAAAAAA==.',
Op='Ophj:BAACLgAFFH8IAAIDAAQJsBR2awAMAQADAAQJsBR2awAMAQAuAAQKfyAAAgMACQm2ImMHAJEDAAMACQm2ImMHAJEDAAAA.',
Or='Orangejulius:BAAALgAECgQJCQAAAA==.Orangutan:BAAALgAECgQJBQAAAA==.Oriclysmic:BAABLgAECn8iAAQBAAgJ5h3SBwB2AgABAAgJ5h3SBwB2AgAHAAQJhQSiTwCPAAAnAAEJAAAjPwAzAAAAAA==.Oriigami:BAAALgAECggJDAAAAA==.Orinoheal:BAAALgAECgYJBgAAAA==.',
Os='Oshtudead:BAAALgADCgQJBAAAAA==.',
Pe='Perilous:BAAALgAECgUJEgAAAA==.Pewpëw:BAAALgADCgkJDwAAAA==.',
Ph='Phalix:BAAALgAFFAIJAgABLgAFFAQJGgAWAAMhAA==.Phat:BAAALgAECgQJBgAAAA==.Phoelar:BAAALgAECgcJEQAAAA==.Phuumyn:BAABLgAECn9FAAIbAAkJTyVOAQBoAwAbAAkJTyVOAQBoAwAAAA==.',
Pi='Piccoblast:BAACLgAFFH8cAAIDAAcJyhQSDQCzAQADAAcJyhQSDQCzAQAuAAQKfy0AAgMACAnYIuEcAAIDAAMACAnYIuEcAAIDAAAA.Piccolocks:BAAALgAECgYJCwABLgAFFAcJHAADAMoUAA==.Piccopew:BAAALgAECgEJAQABLgAFFAcJHAADAMoUAA==.Pichus:BAAALgAECgEJAQABLgAFFAMJBQAFAAALAA==.Picklesoup:BAAALgAECgcJCQAAAA==.Pierrecurzi:BAAALgAFFAIJAwABLgAFFAQJGgAWAAMhAA==.Piickles:BAACLgAFFH8qAAMUAAgJ0RVTBgD1AQAUAAgJ0RVTBgD1AQALAAQJuxJMJgAYAQAuAAQKfx8AAhQABwndItoLAJMCABQABwndItoLAJMCAAAA.Pinkcanibus:BAABLgAECn8aAAIVAAgJvQSzbwAZAQAVAAgJvQSzbwAZAQAAAA==.Pippopper:BAAALgAECgEJAQABLgAFFAQJFQAEAD4lAA==.Pity:BAABLgAECn8XAAIEAAkJjg2UUQCRAQAEAAkJjg2UUQCRAQAAAA==.',
Pl='Plutø:BAABLgAECn9PAAQeAAkJ4xvBAAAxAgAOAAcJth4MDABRAgAeAAkJ/hXBAAAxAgAfAAkJghIMUQDQAQAAAA==.',
Po='Polylocks:BAABLgAECn8UAAINAAgJPBQdSgC8AQANAAgJPBQdSgC8AQAAAA==.Pompey:BAAALgAECgEJAQAAAA==.',
Pr='Praeastra:BAECLgAFFH8HAAIcAAMJNQ6GAgDLAAAcAAMJNQ6GAgDLAAAuAAQKfysAAhwACAmkGtEDANEBABwACAmkGtEDANEBAAAA.Praycation:BAAALgAECgYJBgAAAA==.Promethius:BAAALgAECgcJCQABLgAFFAMJBQANAMcAAA==.Protein:BAABLgAECn8gAAIhAAcJ0BURPQBSAQAhAAcJ0BURPQBSAQAAAA==.Prplxd:BAAALgADCgUJBQABLgAECgYJCgAMAAAAAA==.Prókill:BAAALgADCgcJBwAAAA==.',
Ps='Psychokitty:BAABLgAECn9JAAIYAAkJER0UDQD0AgAYAAkJER0UDQD0AgAAAA==.',
Py='Pyppi:BAAALgADCgEJAQABLgAECggJFAANADwUAA==.',
['Pô']='Pôwersm:BAAALgADCgMJAwAAAA==.',
Qu='Quiet:BAAALgAECgQJBAAAAA==.Quilian:BAACLgAFFH8ZAAIUAAUJdCS/BQAFAgAUAAUJdCS/BQAFAgAuAAQKfyYAAhQACQlAISkEABIDABQACQlAISkEABIDAAAA.',
Ra='Raelynn:BAABLgAECn9NAAIUAAkJvBk/DACiAgAUAAkJvBk/DACiAgAAAA==.Raevenhart:BAACLgAFFH8GAAIWAAMJlgivIACnAAAWAAMJlgivIACnAAAuAAQKfx0AAhYACAlZFWIkAAUCABYACAlZFWIkAAUCAAAA.Rainstorm:BAAALgADCgQJBAAAAA==.Rappa:BAAALgADCgEJAQAAAA==.Raptorx:BAAALgAECgMJAwAAAA==.Rashalisk:BAAALgAECgEJAQAAAA==.Raymond:BAAALgADCgcJBwAAAA==.Razerblade:BAAALgAECgEJAQAAAA==.',
Re='Rebarbative:BAABLgAECn8iAAMNAAkJoQ5dSwC4AQANAAkJoQ5dSwC4AQAmAAMJfAXZUQB5AAAAAA==.Redvex:BAACLgAFFH8OAAINAAQJXhjjRABAAQANAAQJXhjjRABAAQAuAAQKf0UABA0ACQnFJYsEAEcDAA0ACQmQJYsEAEcDACYABQkxII8SALcBABIAAglwI5UkAJ4AAAAA.Rei:BAAALgAECgEJAQAAAA==.Reinhard:BAABLgAECn89AAMQAAkJ5RFTDwD/AAAlAAcJfxOvAwAFAQAQAAkJ2A9TDwD/AAAAAA==.Restohexual:BAAALgAECgEJAQAAAA==.Revengè:BAAALgADCgQJBAAAAA==.Rewrew:BAABLgAECn8sAAIRAAkJhRoeEwB4AgARAAkJhRoeEwB4AgAAAA==.',
Rh='Rhedman:BAABLgAECn8aAAMeAAYJ7QqrHADpAAAeAAUJ7QqrHADpAAAfAAYJdAU87wDBAAAAAA==.',
Ri='Ricasti:BAAALgAECgUJCgAAAA==.Rinah:BAAALgAECgYJBgAAAA==.Rinahrune:BAAALgAECgMJBgAAAA==.Rinahvoid:BAAALgADCgcJBwAAAA==.',
Ro='Robat:BAAALgADCggJDQAAAA==.Ronwen:BAAALgAECgQJBAABLgAFFAUJGgARAFQGAA==.Rosanna:BAAALgAECggJCgAAAA==.Roselyn:BAABLgAECn8VAAIUAAcJaxHEKgByAQAUAAcJaxHEKgByAQAAAA==.Rotyr:BAABLgAECn9HAAILAAkJKRriAACdAgALAAkJKRriAACdAgAAAA==.',
Ru='Ruana:BAEALgAECgUJDgAAAA==.Rubyrazor:BAAALgAECgQJBgAAAA==.Rumpunch:BAAALgAECgEJAQAAAA==.',
Sa='Safetydance:BAAALgAECgIJAgAAAA==.Salil:BAAALgADCgMJAwAAAA==.Salothos:BAAALgADCgYJBgAAAA==.Samesh:BAAALgAECgQJCAAAAA==.Sandrace:BAAALgADCgIJAgAAAA==.Sanginie:BAAALgADCgEJAQAAAA==.Santhela:BAAALgAECgQJBQAAAA==.Satrana:BAAALgADCgMJAwAAAA==.Saturñ:BAAALgAECgYJEgAAAA==.Sauroman:BAAALgAECgUJDgAAAA==.',
Sc='Scoobey:BAABLgAECn8lAAIVAAgJtBp5MwAOAgAVAAgJtBp5MwAOAgAAAA==.Scots:BAAALgADCgQJCwAAAA==.Scubbs:BAACLgAFFH8VAAIFAAUJ4xIIJQBXAQAFAAUJ4xIIJQBXAQAuAAQKfyEAAgUACAkuFkkiABECAAUACAkuFkkiABECAAAA.Scubbsboo:BAACLgAFFH8GAAIXAAQJYxLvFADbAAAXAAQJYxLvFADbAAAuAAQKfxsAAhcABwmoG54cADMCABcABwmoG54cADMCAAEuAAUUBQkVAAUA4xIA.',
Se='Seras:BAAALgAECgUJBQAAAA==.Serka:BAAALgADCgYJBgAAAA==.Servantes:BAABLgAECn9KAAMYAAkJghCNOAC0AQAYAAkJghCNOAC0AQAGAAEJTwW7ngAjAAAAAA==.',
Sh='Shackleford:BAABLgAECn9HAAQLAAkJ4h4ZDQCbAgALAAkJ4h4ZDQCbAgAKAAgJpBZ2GwDpAQAUAAcJLBPDLABlAQAAAA==.Shamae:BAAALgAECgQJBAAAAA==.Shamrockk:BAAALgADCgIJAgAAAA==.Shamwõwz:BAAALgAFFAMJBAAAAA==.Shaolin:BAAALgAECgkJCQAAAA==.Sheck:BAAALgAECgEJAQAAAA==.Shessofine:BAAALgAECggJCgAAAA==.Shotya:BAABLgAECn9NAAIVAAkJlwvPTQC5AQAVAAkJlwvPTQC5AQAAAA==.Shyvàna:BAAALgAECgIJAgAAAA==.',
Si='Siath:BAABLgAECn8UAAMHAAgJ6wtnQQAkAQAHAAgJ6wtnQQAkAQAnAAIJ6gg7PQA5AAAAAA==.Silvino:BAAALgADCgEJAQABLgAECgkJLwAGAMAbAA==.Sixpacktnt:BAAALgADCgkJNQAAAA==.Sixthknight:BAABLgAECn8iAAIQAAYJBgoz3wDfAAAQAAYJBgoz3wDfAAAAAA==.',
Sl='Slarr:BAAALgADCgEJAgAAAA==.',
Sm='Smight:BAABLgAECn8eAAIRAAgJXyapBABNAwARAAgJXyapBABNAwAAAA==.',
Sn='Snacky:BAAALgAECgIJAgAAAA==.Snarkypony:BAABLgAECn8VAAIDAAcJcQ3+EADxAAADAAcJcQ3+EADxAAAAAA==.',
So='Solani:BAAALgADCgYJCQAAAA==.Solania:BAAALgAECgYJCgAAAA==.Soloqenjoyer:BAAALgAECgUJBQAAAA==.Sorocide:BAAALgADCgUJBQAAAA==.Sorsere:BAABLgAECn83AAINAAkJcR0VFACtAgANAAkJcR0VFACtAgAAAA==.',
Sp='Spcecialk:BAABLgAECn8dAAIaAAcJLQulKADvAAAaAAcJLQulKADvAAAAAA==.Specialk:BAACLgAFFH8IAAIdAAIJ0wsIRgBzAAAdAAIJ0wsIRgBzAAAuAAQKfz4AAx0ACAlJErwyAHIBAB0ACAlJErwyAHIBAAUAAwmsBr6xAGYAAAAA.',
Sq='Squallie:BAABLgAECn8ZAAIYAAYJqRNLTwBSAQAYAAYJqRNLTwBSAQAAAA==.',
St='Starcaller:BAAALgAECgYJBgAAAA==.Steamedhams:BAAALgAECgcJCwAAAA==.Stirredihime:BAAALgAFFAEJAQAAAA==.',
Su='Sundorei:BAAALgAECgQJBgAAAA==.',
Sw='Swipper:BAAALgAECgMJAwABLgAECgUJFAAeAGsQAA==.',
['Sû']='Sûlph:BAAALgAECgkJAwAAAA==.',
Ta='Taartt:BAAALgAFFAQJBAABLgAFFAcJJwABAJkTAA==.Tahoe:BAAALgADCgIJAgAAAA==.Talan:BAAALgAECgcJCgABLgAFFAcJEQAEALUKAA==.Talshekar:BAABLgAECn8lAAInAAgJsw3RCgBuAQAnAAgJsw3RCgBuAQAAAA==.Tarsis:BAABLgAECn8oAAIOAAkJeB97BQDRAgAOAAkJeB97BQDRAgAAAA==.',
Te='Teiana:BAABLgAECn8vAAIQAAkJ9x90BQC7AQAQAAkJ9x90BQC7AQAAAA==.Terizfolly:BAAALgAECgQJBAAAAA==.Tezlyn:BAAALgAECgEJAgAAAA==.',
Th='Thaevin:BAABLgAECn8kAAIQAAkJ0RP+TgDbAQAQAAkJ0RP+TgDbAQAAAA==.Therony:BAAALgAECgkJBQAAAA==.Thingwan:BAACLgAFFH8OAAIYAAUJvhXAHgBjAQAYAAUJvhXAHgBjAQAuAAQKfzYAAhgACQk4G9kQAMoCABgACQk4G9kQAMoCAAAA.Thordak:BAAALgADCggJDQABLgAECgkJHQAQANAUAA==.',
Ti='Tiamat:BAAALgAECgkJCQAAAA==.Timbuktoo:BAABLgAECn8VAAIJAAkJqxIhAQDMAQAJAAkJqxIhAQDMAQAAAA==.Tinietimm:BAAALgADCgQJBAAAAA==.Tinypoop:BAABLgAECn8WAAIDAAYJVBVnrwAiAQADAAYJVBVnrwAiAQAAAA==.Tinystain:BAAALgADCgcJDQAAAA==.Tinystink:BAABLgAECn8oAAINAAkJWB9JAQCzAgANAAkJWB9JAQCzAgAAAA==.Tiptugger:BAAALgAECgIJAgAAAA==.',
To='Toddstephens:BAABLgAECn8jAAIeAAYJUxlEAwDuAAAeAAYJUxlEAwDuAAAAAA==.Tors:BAACLgAFFH8QAAIGAAMJiw7VEACxAAAGAAMJiw7VEACxAAAuAAQKf1kAAwYACQndHjUJAMACAAYACQndHjUJAMACAAgAAgnYE55PAG8AAAAA.',
Tr='Trasky:BAAALgAECgMJAwAAAA==.Trogdore:BAAALgAECgYJDQAAAA==.Trollololo:BAABLgAECn9LAAMDAAkJuRqFJACKAgADAAkJuRqFJACKAgAoAAMJ+wfsCgCPAAAAAA==.Troy:BAABLgAECn8qAAIDAAkJXx7+IwCNAgADAAkJXx7+IwCNAgAAAA==.Truid:BAAALgADCgEJAQAAAA==.Trylly:BAAALgAECgYJCAABLgAECggJFAANADwUAA==.',
Tt='Ttaartt:BAACLgAFFH8nAAMBAAcJmRNbCgAFAgABAAcJmRNbCgAFAgAHAAQJyxDzQQC/AAAuAAQKfx0AAgEABwmqGfESABICAAEABwmqGfESABICAAAA.',
Tu='Tuckstaken:BAAALgAECgIJAgAAAA==.',
Ty='Typh:BAACLgAFFH8WAAICAAQJ2yAVAwBzAQACAAQJ2yAVAwBzAQAuAAQKf0QAAgIACQm5JXUAAF4DAAIACQm5JXUAAF4DAAAA.Tyr:BAAALgAECgkJBwAAAA==.Tyresta:BAAALgAECgEJAQAAAA==.Tyrone:BAABLgAECn8kAAMbAAkJcRqLDQBtAgAbAAkJcRqLDQBtAgAXAAQJABCydwC1AAAAAA==.Tyrslan:BAAALgAECgYJEQAAAA==.',
Uf='Uffish:BAAALgAECgkJCQAAAQ==.',
Ug='Uglymagi:BAAALgAECgMJBAAAAA==.Uglypriest:BAAALgADCgEJAQAAAA==.',
Un='Undeaddemon:BAABLgAECn8jAAQNAAkJJR3EOQDzAQANAAgJJR3EOQDzAQASAAMJEQ8THwB4AAAmAAEJkAbJeAAqAAAAAA==.Undeaddh:BAAALgAECgYJCAABLgAECgkJIwANACUdAA==.Undeadmaggot:BAAALgADCggJFAABLgAECgkJIwANACUdAA==.Undeadscaly:BAAALgAECgYJBwABLgAECgkJIwANACUdAA==.Undignified:BAABLgAECn9YAAICAAkJjxo9AABSAgACAAkJjxo9AABSAgAAAA==.Unholysixth:BAAALgADCgkJNAAAAA==.Unicornquen:BAAALgAECgUJCAAAAA==.',
Ur='Uriyah:BAAALgAECgEJAQAAAA==.',
Uz='Uzzìel:BAAALgADCgEJAQAAAA==.',
Va='Valkar:BAAALgAECgEJAgAAAA==.Vanidarr:BAAALgADCgEJAQAAAA==.',
Ve='Verasia:BAAALgAECgUJEQAAAA==.',
Vi='Vidikan:BAAALgAECgQJDwAAAA==.Vie:BAAALgAECgEJAQAAAA==.',
Vo='Voidwarranty:BAACLgAFFH8FAAIFAAMJAAtdWwCWAAAFAAMJAAtdWwCWAAAuAAQKfzQAAwUACQl0F+EiAD0CAAUACQl0F+EiAD0CAB0ABwmRFo4kAMMBAAAA.Vondi:BAEALgAECgUJBQABLgAFFAMJBwAcADUOAA==.Vontoot:BAAALgADCgEJAQAAAA==.',
Vv='Vvumpscut:BAABLgAECn8gAAIFAAkJaxobIABPAgAFAAkJaxobIABPAgAAAA==.',
Vy='Vysena:BAAALgAECgEJAwAAAA==.',
Wa='Waldón:BAABLgAECn9LAAIoAAkJPg3+BACRAQAoAAkJPg3+BACRAQAAAA==.',
We='Weatherley:BAAALgAECgEJAQAAAA==.Werrik:BAABLgAECn8aAAINAAkJXyX8IgCJAgANAAkJXyX8IgCJAgABLgAFFAIJAgAMAAAAAA==.',
Wh='Whiskeytap:BAAALgAECgIJAgAAAA==.',
Wi='Wildsoul:BAABLgAECn8jAAIFAAcJPxJcUgBqAQAFAAcJPxJcUgBqAQAAAA==.Winchester:BAAALgADCgMJAwAAAA==.',
Wo='Wolfguardiån:BAAALgADCgMJAwAAAA==.',
Wr='Wrenz:BAAALgAECgQJDAAAAA==.',
Wu='Wuha:BAAALgADCgEJAQAAAA==.',
['Wä']='Wärhämmer:BAAALgADCgcJCgAAAA==.',
Xa='Xaneva:BAAALgADCgEJAgABLgAFFAYJKgAJAPYiAA==.Xanxer:BAAALgADCgQJBQAAAA==.',
Xc='Xclaw:BAABLgAECn8aAAIPAAkJ+wowGgDNAQAPAAkJ+wowGgDNAQAAAA==.',
Xe='Xeroxgravîty:BAAALgAECgEJAQAAAA==.Xeroxpriest:BAAALgAECgcJCwAAAA==.',
Xi='Xilphira:BAAALgAECgUJCQAAAA==.',
Xl='Xlithz:BAABLgAECn80AAMhAAkJWRuaFgA6AgAhAAkJTxuaFgA6AgAiAAgJPhIiHQB0AQAAAA==.',
['Xí']='Xílo:BAABLgAECn9MAAMEAAkJjh4/FQCZAgAEAAkJcxw/FQCZAgATAAYJtx6SGAC+AQAAAA==.',
Yg='Yggdrasil:BAAALgAECgkJCgAAAA==.',
Yl='Ylene:BAABLgAECn82AAIYAAkJkBAKBQA1AQAYAAkJkBAKBQA1AQAAAA==.',
Yo='Yoink:BAACLgAFFH8TAAIfAAQJkxq7VQBGAQAfAAQJkxq7VQBGAQAuAAQKfzsAAh8ACQk7JGwIAC8DAB8ACQk7JGwIAC8DAAAA.',
Za='Zalasham:BAAALgADCgIJAgAAAA==.Zarinchaos:BAAALgAECgUJBwAAAA==.Zarinfur:BAABLgAECn82AAIJAAkJHBnGBwBYAgAJAAkJHBnGBwBYAgAAAA==.',
Ze='Zedrin:BAAALgAECgQJBAAAAA==.Zein:BAAALgAECgUJCQAAAA==.Zentacle:BAAALgAECgIJAgAAAA==.Zente:BAACLgAFFH8LAAIVAAQJqAdYLAC3AAAVAAQJqAdYLAC3AAAuAAQKfy0AAxUABwmsG0ZAAOEBABUABwmsG0ZAAOEBABYAAQn1AJGZABsAAAAA.Zequill:BAABLgAECn9QAAIaAAkJOCRgAgAjAwAaAAkJOCRgAgAjAwAAAA==.Zevsticles:BAABLgAECn8yAAIVAAkJmh/fBADfAQAVAAkJmh/fBADfAQAAAA==.',
Zh='Zhom:BAACLgAFFH8aAAIWAAQJAyGbDgB1AQAWAAQJAyGbDgB1AQAuAAQKf0AAAhYACQkcJIgBAAYDABYACQkcJIgBAAYDAAAA.',
Zo='Zohm:BAAALgADCgMJAwAAAA==.Zolec:BAAALgADCgcJDgAAAA==.Zooj:BAABLgAECn9MAAIpAAkJQBseBQCVAgApAAkJQBseBQCVAgAAAA==.Zorlak:BAAALgAECgUJDQAAAA==.',
Zu='Zuxa:BAAALgADCgYJBgAAAA==.',
Zy='Zylofeather:BAAALgAECgUJBQAAAA==.',
['ße']='ßeast:BAABLgAECn8jAAIbAAgJiwn3NwAiAQAbAAgJiwn3NwAiAQAAAA==.',
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
