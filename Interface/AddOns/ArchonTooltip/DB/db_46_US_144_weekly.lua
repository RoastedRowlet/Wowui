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

local lookup = {'Evoker-Preservation','Mage-Frost','DemonHunter-Devourer','Shaman-Restoration','Druid-Balance','Evoker-Augmentation','Druid-Guardian','Druid-Feral','Priest-Shadow','Priest-Discipline','Unknown-Unknown','Hunter-Survival','DeathKnight-Blood','Paladin-Retribution','Warlock-Demonology','Paladin-Holy','Warlock-Affliction','DemonHunter-Havoc','Priest-Holy','Hunter-BeastMastery','Hunter-Marksmanship','Monk-Mistweaver','Druid-Restoration','Rogue-Subtlety','Warrior-Protection','Monk-Windwalker','Mage-Arcane','Shaman-Elemental','Monk-Brewmaster','Warrior-Fury','Warrior-Arms','Rogue-Assassination','Rogue-Outlaw','DeathKnight-Frost','DeathKnight-Unholy','DemonHunter-Vengeance','Paladin-Protection','Evoker-Devastation','Warlock-Destruction','Mage-Fire','Shaman-Enhancement',}
local provider = {region='US',realm='Llane',name='US',type='weekly',zone=46,date='2026-06-06',data={Ab='Abdervoke:BAABLgAECn8eAAIBAAgJ7CJCAwASAwABAAgJ7CJCAwASAwAAAA==.Absent:BAAALgADCgEJAQAAAA==.',
Ac='Account:BAAALgADCgIJAgAAAA==.',
Ae='Aeila:BAAALgADCgYJBgAAAA==.Aethos:BAAALgAECgkJBQAAAA==.',
Ah='Ahsoul:BAAALgAECgEJAgAAAA==.',
Al='Alesia:BAAALgADCgEJAQAAAA==.Alessaah:BAAALgADCgcJCgAAAA==.Aliadra:BAABLgAECn8zAAICAAkJSSLrDQAFAwACAAkJSSLrDQAFAwAAAA==.Alistus:BAACLgAFFH8JAAIDAAMJGyVoNAA8AQADAAMJGyVoNAA8AQAuAAQKfz4AAgMACQn/JEYDAEwDAAMACQn/JEYDAEwDAAAA.Alphá:BAAALgAECgUJCQABLgAFFAMJBQAEAAALAA==.Altholar:BAAALgADCgcJBwAAAA==.',
An='Anexxia:BAAALgAECgQJCQAAAA==.Angel:BAAALgAECgYJDwAAAA==.Angua:BAABLgAECn9DAAIFAAkJPRdDEgA6AgAFAAkJPRdDEgA6AgAAAA==.',
Ar='Arcanegarm:BAABLgAECn8aAAICAAcJIAKR9QCzAAACAAcJIAKR9QCzAAAAAA==.Archeyois:BAABLgAECn8pAAMGAAkJVA8qKACaAQAGAAkJVA8qKACaAQABAAUJhQIRNwCzAAAAAA==.Armitage:BAABLgAECn8YAAMHAAkJ/w9pGgBoAQAHAAkJXQ9pGgBoAQAIAAcJQguRHAASAQAAAA==.Arthonos:BAACLgAFFH8GAAIJAAIJVAVQLwBzAAAJAAIJVAVQLwBzAAAuAAQKfzUAAwkACQmaFfsWAAkCAAkACQmaFfsWAAkCAAoACAnjBWQnAFoBAAAA.Arugall:BAAALgAECgYJBgAAAA==.',
As='Ashmall:BAAALgAECgQJBAAAAA==.',
Av='Averille:BAAALgADCgYJCwAAAA==.',
Ay='Ayraa:BAAALgAECgYJBAAAAA==.',
Az='Azerphage:BAAALgAECgYJDwABLgAECgcJCwALAAAAAA==.Azeura:BAAALgADCgQJBAAAAA==.Azhorra:BAAALgAECgYJEwAAAA==.Azzog:BAAALgAECgcJEAAAAA==.Azül:BAAALgAECgMJAwABLgAECgcJCwALAAAAAA==.',
Ba='Bacchanalian:BAAALgAECgcJDAABLgAECgkJCwALAAAAAA==.Baindyn:BAAALgAECgQJEgAAAA==.Barator:BAAALgAECgYJCgAAAA==.Bas:BAAALgAECgUJCQAAAA==.',
Bi='Bickkbatwolf:BAAALgADCgYJDQAAAA==.Bigwhisky:BAAALgAECgcJEAAAAA==.',
Bl='Blackröse:BAABLgAECn8jAAIMAAgJMx08DwA1AgAMAAgJMx08DwA1AgAAAA==.Blackrøse:BAABLgAECn8YAAIEAAkJXg3cOwCxAQAEAAkJXg3cOwCxAQABLgAECggJIwAMADMdAA==.Bladebane:BAABLgAECn8lAAINAAkJGgGPOQCiAAANAAkJGgGPOQCiAAAAAA==.Blandmonk:BAAALgADCgkJDgAAAA==.Blksunshine:BAAALgAECgYJCgAAAA==.',
Bo='Bolash:BAAALgAECgYJCwAAAA==.Bort:BAAALgAECgEJBAAAAA==.',
Br='Bradthomas:BAAALgAECgQJBQAAAA==.Breegorn:BAAALgAECgUJBgAAAA==.Breni:BAAALgAFFAEJAQAAAA==.Bruscha:BAAALgAECgQJDQAAAA==.',
Bu='Bulvhine:BAABLgAECn8jAAIOAAgJuRwVLABGAgAOAAgJuRwVLABGAgAAAA==.',
Ca='Camferd:BAAALgAECgEJAQAAAA==.Camford:BAABLgAECn8ZAAICAAcJ8QhZvQBoAQACAAcJ8QhZvQBoAQAAAA==.Cantatrix:BAABLgAECn8bAAIPAAYJ9gtdnAAAAQAPAAYJ9gtdnAAAAQAAAA==.Capslok:BAAALgAECgYJDQAAAA==.Captinmeat:BAAALgAECgIJBAAAAA==.Cashkin:BAAALgADCgYJBgAAAA==.Cassiela:BAAALgAECgYJBgABLgAECgkJCwALAAAAAA==.',
Ce='Cecilx:BAABLgAECn8uAAIQAAgJ7yMRBwATAwAQAAgJ7yMRBwATAwAAAA==.Cellybelleri:BAAALgADCgUJCAAAAA==.',
Ch='Chaac:BAAALgADCgEJAQAAAA==.Charmander:BAAALgADCgcJCAAAAA==.Chayton:BAAALgADCgUJBQAAAA==.Cherrypie:BAAALgAECgYJBgAAAA==.Chillana:BAAALgAECgQJBAAAAA==.Chimerax:BAACLgAFFH8VAAMRAAQJPyDdAQCNAQARAAQJPyDdAQCNAQAPAAEJlxd3sgBLAAAuAAQKfy0AAxEACQljHwACALACABEACAlCIgACALACAA8ACAlDE0d3AEYBAAAA.Chloede:BAAALgADCgUJBQAAAA==.Chlorpyrifos:BAAALgADCgEJAQAAAA==.Chrismikea:BAABLgAECn8cAAIOAAgJMAZvygDtAAAOAAgJMAZvygDtAAAAAA==.Chronic:BAAALgAECgQJBwAAAA==.Chully:BAACLgAFFH8PAAIDAAQJZRAqQQAUAQADAAQJZRAqQQAUAQAuAAQKfywAAwMACQkIGz8oAB4CAAMACQkIGz8oAB4CABIAAwmIBM1ZAH0AAAAA.',
Cl='Clairíty:BAABLgAECn8eAAITAAgJoh7YDACKAgATAAgJoh7YDACKAgAAAA==.Clarky:BAAALgAECgYJEAAAAA==.Click:BAABLgAECn86AAIUAAgJ/RtQIQBVAgAUAAgJ/RtQIQBVAgAAAA==.Cloutfarmer:BAACLgAFFH8QAAIUAAQJGyDbHwBvAQAUAAQJGyDbHwBvAQAuAAQKf0AABBQACQlKJR8EAEgDABQACQlKJR8EAEgDABUABgkZHFspAOABAAwAAglFHWtSAFYAAAAA.',
Co='Comadore:BAACLgAFFH8NAAIOAAQJgwq2TwD/AAAOAAQJgwq2TwD/AAAuAAQKfxwAAg4ACAk4HNg4AEACAA4ACAk4HNg4AEACAAAA.',
Cr='Crankshanker:BAAALgAECgEJAQAAAA==.Cratora:BAAALgAECgYJBgAAAA==.Credan:BAEBLgAECn8VAAIWAAkJMyJ1BQBFAwAWAAkJMyJ1BQBFAwABLgADCgYJBgALAAAAAA==.',
Cy='Cylithina:BAAALgAECgQJBwAAAA==.Cytochrome:BAAALgADCgQJBAAAAA==.',
Da='Daphe:BAAALgAECgEJAwAAAA==.Dawggbiscuit:BAAALgAECgQJBQAAAA==.',
De='Deadiam:BAAALgAECgEJAQAAAA==.Deadseksi:BAAALgAECgcJDAAAAA==.Deathslead:BAABLgAECn8yAAMUAAgJkxTjPQDeAQAUAAgJkxTjPQDeAQAVAAUJ3AEbLwBUAAAAAA==.Decrepe:BAACLgAFFH8RAAIXAAQJ2BjbJAApAQAXAAQJ2BjbJAApAQAuAAQKfzsAAhcACQlIINIJABYDABcACQlIINIJABYDAAAA.Dedrepe:BAAALgAECggJCQAAAA==.Delph:BAAALgAECgcJEQAAAA==.Deshal:BAAALgAECgEJAQAAAA==.Desomas:BAAALgAECgIJAgAAAA==.',
Di='Dieurnal:BAAALgAECgQJAQAAAA==.Discostar:BAABLgAECn8lAAMXAAcJghjcLADrAQAXAAcJghjcLADrAQAFAAQJuhH+SADZAAAAAA==.Distill:BAAALgAECgEJAQABLgAFFAkJGAAYAAYdAA==.',
Dn='Dni:BAAALgAECgMJBAABLgAECgkJLAAFAMAbAA==.',
Do='Dominicm:BAAALgAECgYJEgAAAA==.Dotdotdis:BAAALgAECgMJAwAAAA==.',
Dr='Dracanalian:BAAALgADCgkJCQAAAA==.Drajhar:BAAALgAECgkJBQAAAA==.Drakyore:BAAALgADCgIJAwAAAA==.Draq:BAAALgAECgYJCgAAAA==.Druth:BAABLgAECn8tAAIZAAgJRx/aCQBJAgAZAAgJRx/aCQBJAgAAAA==.',
Eb='Ebonhorn:BAAALgAECgQJDwAAAA==.',
Ee='Eevillean:BAAALgAECgEJAQAAAA==.',
Ei='Einari:BAAALgAECggJCAAAAA==.Einark:BAABLgAECn87AAMWAAkJjR/dBwARAwAWAAkJjR/dBwARAwAaAAgJzB5IDAB1AgAAAA==.',
Ek='Ekiim:BAAALgAECgQJBAABLgAECgQJCQALAAAAAA==.',
El='Eldrond:BAAALgAECgQJCAAAAA==.Elinis:BAAALgAFFAEJAQAAAA==.Elska:BAAALgADCgkJCQAAAA==.',
En='Ennauríon:BAAALgAECgUJCQAAAA==.Entropy:BAEALgAFFAIJAgABLgAFFAIJBQAbAOQHAA==.',
Er='Eridor:BAAALgAECgYJEAAAAA==.',
Ex='Exek:BAABLgAECn8tAAMTAAgJExeTFQAYAgATAAgJExeTFQAYAgAJAAUJWQt8TwDIAAAAAA==.',
Ez='Ez:BAAALgAECgEJAQABLgAECgkJJwAcAAsbAA==.',
Fa='Fabaztard:BAABLgAECn8jAAIFAAgJdxRAIQCxAQAFAAgJdxRAIQCxAQAAAA==.Faline:BAABLgAECn8zAAIXAAkJUwvwQgB8AQAXAAkJUwvwQgB8AQAAAA==.',
Fe='Felgetabouit:BAACLgAFFH8VAAIDAAQJUhOuQgAQAQADAAQJUhOuQgAQAQAuAAQKfyMAAgMACQlUGs00ACUCAAMACQlUGs00ACUCAAAA.Felghoul:BAAALgAECgIJAgAAAA==.Felldozer:BAAALgAECgEJAQAAAA==.Fenrakar:BAAALgAECgQJBwAAAA==.Feywynn:BAAALgAECggJBwAAAA==.',
Fi='Fights:BAABLgAECn8vAAIQAAkJKR4sCQDuAgAQAAkJKR4sCQDuAgAAAA==.',
Fl='Fleshworker:BAAALgADCgEJAQAAAA==.',
Fo='Fordalliance:BAAALgADCgcJBwAAAA==.Forky:BAAALgAECgQJCAAAAA==.Foxknight:BAAALgAECgQJEgAAAA==.',
Fr='Franciss:BAAALgAECgYJDQAAAA==.Francys:BAAALgADCgIJAwAAAA==.Franksnbeans:BAAALgAECgEJAgABLgAECgYJEgALAAAAAA==.',
Ft='Ftx:BAABLgAECn8gAAMdAAgJuh+oDQC4AgAdAAgJlR+oDQC4AgAaAAQJ2hm/RgD6AAAAAA==.',
Fu='Fubbleskag:BAABLgAECn8xAAIOAAkJARxwNAAkAgAOAAkJARxwNAAkAgAAAA==.Fullmoonn:BAAALgAECgIJAwAAAA==.',
Ga='Gaern:BAAALgAECgEJAwABLgAECgkJJQACAI0eAA==.Gaidan:BAACLgAFFH8MAAIFAAUJ5wuyJQDsAAAFAAUJ5wuyJQDsAAAuAAQKfyEAAgUACQmlFogRAI8CAAUACQmlFogRAI8CAAEuAAUUBgkMAAMA0wgA.Gameslayer:BAABLgAECn8fAAMeAAgJ9RxzPQBHAQAeAAUJHB9zPQBHAQAfAAQJzxfpLgADAQAAAA==.Gankzilla:BAACLgAFFH8VAAMYAAQJtxQYFwBIAQAYAAQJtxQYFwBIAQAgAAEJbBH7DwBOAAAuAAQKfycAAyAACQmeG2EJAKoBABgABgl3GNklAMoBACAABwkfG2EJAKoBAAAA.Garothos:BAAALgAECgIJAgABLgAECgQJBwALAAAAAA==.Gatanikaz:BAAALgAECgIJBAAAAA==.',
Ge='Genrealwee:BAAALgAECgEJAQAAAA==.Get:BAAALgADCgkJDAAAAA==.',
Gh='Ghalumvhar:BAABLgAECn8fAAIOAAcJBRt8SgDdAQAOAAcJBRt8SgDdAQAAAA==.Ghoulaid:BAAALgAECgcJBwAAAA==.Ghrìmm:BAABLgAECn8lAAQMAAkJ6w/eGADUAQAMAAkJIA3eGADUAQAUAAgJxA56YQB2AQAVAAEJ+QbcQAAiAAAAAA==.',
Gi='Gila:BAAALgAECggJDgAAAA==.Gingasorrow:BAABLgAECn8sAAIXAAgJihfNJQAWAgAXAAgJihfNJQAWAgAAAA==.Gizzle:BAACLgAFFH8OAAIOAAQJpg0/TgACAQAOAAQJpg0/TgACAQAuAAQKfyYAAg4ACQmoFjBQAM0BAA4ACQmoFjBQAM0BAAAA.',
Gr='Greekfire:BAABLgAECn8YAAIQAAgJ3yE5GwA7AgAQAAgJ3yE5GwA7AgAAAA==.Grishna:BAAALgADCggJCAAAAA==.Grumrok:BAAALgAECgQJBgAAAA==.Grunbar:BAABLgAECn8uAAIUAAcJYyJwKgApAgAUAAcJYyJwKgApAgAAAA==.Grændal:BAAALgAECgQJBAABLgAFFAYJDAADANMIAA==.',
Ha='Hanjha:BAABLgAECn89AAMMAAgJxRsbDgBDAgAMAAcJxRsbDgBDAgAUAAEJAAA7zwA3AAAAAA==.Hatz:BAAALgADCgcJBgAAAA==.',
He='Healshot:BAAALgADCgMJAwABLgAECgUJFQAOAGUmAA==.Helldozer:BAABLgAECn9IAAMcAAgJtRecHADvAQAcAAgJtRecHADvAQAEAAIJzxRNngB9AAAAAA==.',
Ho='Hooj:BAAALgADCgYJBgAAAA==.Horde:BAAALgADCgEJAQAAAA==.',
Ht='Ht:BAAALgADCgMJCAAAAA==.',
Hu='Hugzy:BAAALgAECgEJBgAAAA==.',
Hw='Hwore:BAAALgAECgQJBAAAAA==.',
Hy='Hydatos:BAAALgADCgMJAwABLgAECgYJCgALAAAAAA==.Hypnocide:BAEBLgAECn85AAIDAAkJtRV1MAD5AQADAAkJtRV1MAD5AQAAAA==.',
['Hô']='Hôneynuts:BAAALgADCgIJAgAAAA==.',
Ib='Ibuki:BAAALgAECgYJEQABLgAFFAQJFQAQAEYGAA==.',
Ic='Icepick:BAAALgADCgIJAgAAAA==.',
Id='Idleorc:BAAALgADCgcJDQAAAA==.',
Ig='Iguanajon:BAAALgAECgEJAgAAAA==.',
Il='Illandren:BAACLgAFFH8RAAIMAAQJlgjTFQASAQAMAAQJlgjTFQASAQAuAAQKfxsAAwwACQljCzUbAL8BAAwACQljCzUbAL8BABUACAk6AwQeALIAAAAA.Illusiveeyes:BAAALgADCgYJDAAAAA==.',
Im='Impsane:BAABLgAECn8jAAIPAAkJBw4PSgC3AQAPAAkJBw4PSgC3AQAAAA==.',
In='Incøgnitø:BAAALgAECgEJAQABLgAECggJGQAXAAMcAA==.Infernis:BAAALgADCgYJCQAAAA==.Innphyy:BAABLgAECn8jAAICAAcJsQj7uQAOAQACAAcJsQj7uQAOAQAAAA==.Innøminate:BAAALgAECgYJEwABLgAECggJGQAXAAMcAA==.Inti:BAAALgADCgEJAQAAAA==.',
Ir='Irv:BAABLgAECn8WAAQgAAgJlhosBwDhAQAgAAgJ5xksBwDhAQAYAAUJoxxSMwBwAQAhAAQJjg9mCQDZAAAAAA==.',
Is='Isadavrah:BAAALgADCgcJDAAAAA==.Isekai:BAAALgAECgQJBQAAAA==.Issadin:BAAALgAECgUJBgABLgAECgUJBgALAAAAAA==.Issadruiid:BAAALgADCgYJBgABLgAECgUJBgALAAAAAA==.Issammonk:BAAALgAECgEJAQABLgAECgUJBgALAAAAAA==.Issarage:BAAALgAECgQJBgABLgAECgUJBgALAAAAAA==.Issashammy:BAAALgAECgUJBgAAAA==.',
Ja='Jaxxa:BAABLgAECn85AAIUAAkJdxpOHgBlAgAUAAkJdxpOHgBlAgAAAA==.',
Je='Jeddiah:BAABLgAECn8jAAMgAAcJIQ80DQBKAQAgAAcJIQ80DQBKAQAYAAQJRgpTQwCdAAAAAA==.',
Jh='Jhals:BAAALgADCgYJBgAAAA==.',
Ji='Jiffarous:BAAALgAECgQJBwAAAA==.Jinkès:BAABLgAECn8iAAIVAAYJ2g0mFwDvAAAVAAYJ2g0mFwDvAAAAAA==.',
Jp='Jpank:BAAALgAFFAEJAwAAAA==.',
Ju='Jubei:BAABLgAFFH8HAAIOAAYJbgodcgC5AAAOAAYJbgodcgC5AAAAAA==.Judis:BAABLgAECn9TAAIgAAkJRR+FAQDkAgAgAAkJRR+FAQDkAgAAAA==.Judyth:BAAALgAECgIJBQAAAA==.Juicy:BAAALgADCgIJAgAAAA==.Justokevoker:BAABLgAFFH8LAAIGAAQJpxG2KwAGAQAGAAQJpxG2KwAGAQAAAA==.',
Ka='Kainel:BAAALgAECgkJCQAAAA==.Kairì:BAAALgADCgcJDQAAAA==.Kalifist:BAABLgAECn8cAAIaAAkJnR+9BwDDAgAaAAkJnR+9BwDDAgAAAA==.Kalinear:BAAALgADCgQJBQAAAA==.Kalipally:BAAALgAECgcJDgAAAA==.Kaliscales:BAAALgAECgUJBQAAAA==.Kamiportal:BAAALgAECgcJCgAAAA==.Kanajotoma:BAAALgAECgQJEAAAAA==.Karlai:BAABLgAECn8oAAMiAAgJZRrlBAAAAgAiAAcJuhrlBAAAAgAjAAUJGBLT1QDWAAABLgAFFAYJDAADANMIAA==.Kaslana:BAEALgADCgYJBgAAAA==.',
Ke='Keldrune:BAAALgAECgYJCwAAAA==.Keleena:BAEBLgAECn9DAAIQAAkJbh8iCQDuAgAQAAkJbh8iCQDuAgAAAA==.Kelume:BAAALgADCgMJAwAAAA==.Kely:BAAALgADCgUJBgAAAA==.',
Kg='Kgor:BAAALgAECgcJBwAAAA==.',
Kh='Khaerne:BAAALgAECgEJAQABLgAECgkJJQACAI0eAA==.Khordelia:BAAALgAECgcJCAABLgAECgkJJQACAI0eAA==.',
Ki='Kinst:BAABLgAECn85AAMUAAkJ8h2lEQC5AgAUAAkJ8h2lEQC5AgAVAAYJrxLaPwBbAQAAAA==.Kirigaya:BAAALgAECgMJBwAAAA==.Kisäi:BAABLgAECn8pAAMDAAkJ1RxbIACPAgADAAkJ1RxbIACPAgAkAAIJHBEkJgBiAAAAAA==.Kitanyia:BAABLgAECn8ZAAIeAAkJlApRSQAXAQAeAAkJlApRSQAXAQAAAA==.Kittiy:BAABLgAECn8xAAMFAAgJJAZDQgD1AAAFAAgJJAZDQgD1AAAXAAYJKgfWeADDAAAAAA==.',
Ko='Kordelia:BAABLgAECn8lAAICAAkJjR7GHwCaAgACAAkJjR7GHwCaAgAAAA==.Korvus:BAAALgAECgcJEQAAAA==.',
Kv='Kv:BAAALgADCggJCAAAAA==.',
Ky='Kyakuna:BAAALgAECgIJAgAAAA==.Kylnara:BAAALgAECgQJCAABLgAECgQJCAALAAAAAA==.Kyloon:BAAALgAECgEJAQAAAA==.Kyrah:BAABLgAECn8xAAMRAAgJaxnLBgDrAQARAAYJ3xvLBgDrAQAPAAgJ3xSRRADIAQAAAA==.',
La='Lamanira:BAAALgAECgYJCgAAAA==.Lancier:BAAALgAECgYJCgAAAA==.',
Le='Lecleme:BAACLgAFFH8FAAIjAAMJhA4alQDWAAAjAAMJhA4alQDWAAAuAAQKfyEAAiMACAleGFFEAO4BACMACAleGFFEAO4BAAAA.Lejend:BAABLgAECn84AAMfAAkJmCPHAQA1AwAfAAkJmCPHAQA1AwAeAAMJfRW8fwC+AAAAAA==.Lenthalis:BAAALgAECgUJDAAAAA==.Lezriel:BAAALgAECgMJBgAAAA==.',
Li='Lichin:BAAALgADCgEJAQAAAA==.Lilithh:BAAALgADCgUJCAAAAA==.',
Ll='Llanedh:BAAALgAECggJDAAAAA==.',
Lo='Loaganic:BAAALgAECgQJBAABLgAECggJFAAGAOsLAA==.Lockheéd:BAAALgAFFAEJAQAAAA==.Lonelyhearts:BAABLgAECn80AAIOAAgJKAs3jQBLAQAOAAgJKAs3jQBLAQAAAA==.Lonestar:BAAALgAECgYJDwAAAA==.Lonestarr:BAAALgAECgQJDAAAAA==.Loxricia:BAAALgADCgEJAQAAAA==.',
Lu='Lumiya:BAABLgAECn8yAAITAAkJ7w52LwCFAQATAAkJ7w52LwCFAQAAAA==.',
Ly='Lytol:BAABLgAECn8hAAMbAAgJcRdfBACmAQAbAAcJcRpfBACmAQACAAMJXgS/FgF3AAAAAA==.',
Ma='Machu:BAAALgADCgIJAgABLgAFFAQJCgAGANkVAA==.Madderhorn:BAAALgAECgcJBQAAAA==.Maenad:BAAALgAECgkJCwAAAA==.Maeple:BAABLgAECn8pAAMTAAkJ+SG3AwBHAwATAAkJ+SG3AwBHAwAKAAMJugrkVwCJAAAAAA==.Magikin:BAAALgAECgQJCAAAAA==.Mamichula:BAAALgAECgEJAQAAAA==.',
Mb='Mbdtf:BAACLgAFFH8WAAMMAAYJxR9LBAC3AQAMAAUJlCZLBAC3AQAVAAEJjAS6JABVAAAuAAQKfxsAAwwABwmMJXMEANQCAAwABwkxJXMEANQCABUAAQksIwR3AGMAAAEuAAUUCAkoAAIA0CMA.',
Me='Mechagnome:BAACLgAFFH8GAAIaAAIJoBvmKACbAAAaAAIJoBvmKACbAAAuAAQKfzQAAxoACQnUICEHAM8CABoACQnUICEHAM8CABYACAkJBAU6AAABAAAA.Meeps:BAAALgADCgcJBwAAAA==.Megamedes:BAABLgAECn8aAAMOAAYJkhbKegCEAQAOAAYJEhbKegCEAQAlAAQJTQk0NACEAAAAAA==.Meigna:BAABLgAECn8qAAIJAAgJuR2LEABPAgAJAAgJuR2LEABPAgAAAA==.Mekö:BAAALgAECgYJDQAAAA==.Meladyn:BAACLgAFFH8pAAMIAAYJ9iKaAwB7AQAIAAUJeyOaAwB7AQAHAAUJMh5vBwBmAQAuAAQKfygAAwgABwlnJlYDAAMDAAgABwlnJlYDAAMDAAcABQnrI/cUAJsBAAAA.Melritza:BAAALgAECgQJCAAAAA==.Mentock:BAABLgAECn8YAAICAAYJ4hAMowAxAQACAAYJ4hAMowAxAQAAAA==.Merelandra:BAAALgADCggJFwAAAA==.Mermaid:BAAALgAECgUJCgAAAA==.',
Mi='Miliara:BAAALgADCgEJAQAAAA==.Missmaam:BAAALgAECgcJEAAAAA==.Mistroot:BAAALgAECgEJAQAAAA==.Mithrandir:BAABLgAECn8gAAIPAAcJlhAabQBcAQAPAAcJlhAabQBcAQAAAA==.Mixcoati:BAAALgADCgQJBQAAAA==.Mizu:BAABLgAECn8cAAMZAAkJyxv0DQD/AQAZAAkJyxv0DQD/AQAeAAIJ6xAGlABvAAAAAA==.',
Mo='Moe:BAAALgAECgkJBAAAAA==.Monkfox:BAAALgAECgcJBwAAAA==.Morgianna:BAAALgADCgEJAQAAAA==.',
Mu='Mudflap:BAAALgAECgYJDgAAAA==.Mushuwoonter:BAAALgAECgEJAQABLgAFFAQJCgAGANkVAA==.Muztang:BAABLgAECn84AAMfAAgJph5oBwB2AgAfAAgJph5oBwB2AgAeAAYJihPsSQAVAQAAAA==.',
Mw='Mwmmwmm:BAAALgAECgYJCQAAAA==.',
My='Mythandwel:BAABLgAECn8qAAISAAgJiAiNKgAXAQASAAgJiAiNKgAXAQAAAA==.',
['Mä']='Mäddiey:BAAALgAECgQJCgAAAA==.',
['Mô']='Mônkii:BAACLgAFFH8TAAIdAAQJESXNCwC3AQAdAAQJESXNCwC3AQAuAAQKfz4AAx0ACQnjJG4CADEDAB0ACQnjJG4CADEDABYAAQmvAgnJABEAAAAA.',
Na='Nace:BAABLgAECn8qAAIYAAkJ7BOvGQA2AgAYAAkJ7BOvGQA2AgAAAA==.Nadriede:BAAALgADCgYJBgAAAA==.Naenia:BAAALgAECgUJBQAAAA==.Naillimixam:BAAALgADCgMJAgAAAA==.Nariar:BAAALgAECgMJAwABLgAFFAQJFQAQAEYGAA==.Nateldin:BAABLgAECn8YAAMOAAkJhwmIkABbAQAOAAkJ8AeIkABbAQAlAAIJ9Q5YTgArAAAAAA==.',
Ne='Neoba:BAAALgAECgIJAwAAAA==.',
Ni='Nicksevokerc:BAAALgAECggJBwAAAA==.Niisha:BAAALgAECggJDQABLgAECgkJHwATAKMHAA==.Nikiso:BAAALgADCgYJBwAAAA==.',
No='Nocainus:BAABLgAECn9DAAINAAgJVyHUBwCTAgANAAgJVyHUBwCTAgAAAA==.Nosehole:BAABLgAECn8cAAIEAAcJBw/zUQBcAQAEAAcJBw/zUQBcAQAAAA==.Novari:BAAALgADCgkJCQAAAA==.',
Nv='Nv:BAAALgADCgEJAQABLgAFFAUJBQAaAGgFAA==.',
['Nø']='Nøtsure:BAABLgAECn8ZAAMXAAgJAxyDJgARAgAXAAgJAxyDJgARAgAFAAIJqwzDbgBdAAAAAA==.',
Ob='Obesityy:BAABLgAECn8xAAIYAAkJph6QBwCkAgAYAAkJph6QBwCkAgAAAA==.Obsidia:BAABLgAECn8eAAIPAAgJhQ3bZABwAQAPAAgJhQ3bZABwAQAAAA==.',
Oc='Octopusprime:BAAALgAECgkJEQAAAA==.',
Ol='Ollix:BAEALgAECgEJBAABLgAECggJQgADAFcfAA==.',
Om='Omelette:BAABLgAECn8fAAIUAAkJiRztGACEAgAUAAkJiRztGACEAgAAAA==.',
On='Onik:BAAALgADCgcJDQABLgAECgQJCAALAAAAAA==.',
Op='Ophj:BAABLgAECn8gAAICAAkJtiJjBwCRAwACAAkJtiJjBwCRAwAAAA==.',
Or='Orangejulius:BAAALgAECgQJCQAAAA==.Orangutan:BAAALgAECgQJBQAAAA==.Oriclysmic:BAABLgAECn8iAAQBAAgJ5h1zBwB5AgABAAgJ5h1zBwB5AgAGAAQJhQSiTwCPAAAmAAEJAAAjPwAzAAAAAA==.Oriigami:BAAALgAECgQJBwAAAA==.Orinoheal:BAAALgAECgYJBgAAAA==.',
Os='Oshtudead:BAAALgADCgQJBAAAAA==.',
Pe='Perilous:BAAALgAECgQJDQAAAA==.Pewpëw:BAAALgADCgkJDwAAAA==.',
Ph='Phalix:BAAALgAECgIJAwAAAA==.Phat:BAAALgAECgEJAQAAAA==.Phoelar:BAAALgAECgcJDgAAAA==.Phuumyn:BAABLgAECn87AAIaAAgJFCR1BgDcAgAaAAgJFCR1BgDcAgAAAA==.',
Pi='Piccoblast:BAACLgAFFH8cAAICAAcJyhQSDQCzAQACAAcJyhQSDQCzAQAuAAQKfy0AAgIACAnYIuEcAAIDAAIACAnYIuEcAAIDAAAA.Piccolocks:BAAALgAECgYJCwABLgAFFAcJHAACAMoUAA==.Piccopew:BAAALgAECgEJAQABLgAFFAcJHAACAMoUAA==.Pichus:BAAALgAECgEJAQABLgAFFAMJBQAEAAALAA==.Picklesoup:BAAALgAECgcJCQAAAA==.Pierrecurzi:BAAALgAFFAEJAQABLgAFFAQJEQAVAJ0cAA==.Piickles:BAACLgAFFH8nAAMTAAYJTRp1BwC+AQATAAYJTRp1BwC+AQAKAAQJuxLaIQAdAQAuAAQKfx8AAhMABwndItoLAJMCABMABwndItoLAJMCAAAA.Pinkcanibus:BAABLgAECn8aAAIUAAgJvQSzbwAZAQAUAAgJvQSzbwAZAQAAAA==.Pippopper:BAAALgAECgEJAQABLgAFFAMJCQADABslAA==.Pity:BAABLgAECn8WAAIDAAgJaQ0CZABTAQADAAgJaQ0CZABTAQAAAA==.',
Pl='Plutø:BAABLgAECn9AAAMNAAkJdhoMDABRAgANAAcJth4MDABRAgAjAAkJghKTSgDbAQAAAA==.',
Po='Polylocks:BAAALgAECggJDgAAAA==.Pompey:BAAALgAECgEJAQAAAA==.',
Pr='Praeastra:BAECLgAFFH8FAAIbAAIJ5AeYAwB+AAAbAAIJ5AeYAwB+AAAuAAQKfyoAAhsACAmMF6EDANIBABsACAmMF6EDANIBAAAA.Praycation:BAAALgAECgYJBgAAAA==.Promethius:BAAALgAECgcJCQABLgAECgkJIAAPAJYQAA==.Protein:BAABLgAECn8gAAIeAAcJ0BWlOABcAQAeAAcJ0BWlOABcAQAAAA==.Prplxd:BAAALgADCgUJBQABLgAECgYJCgALAAAAAA==.Prókill:BAAALgADCgcJBwAAAA==.',
Ps='Psychokitty:BAABLgAECn9HAAIXAAkJaBzYDQDiAgAXAAkJaBzYDQDiAgAAAA==.',
Py='Pyppi:BAAALgADCgEJAQABLgAECggJDgALAAAAAA==.',
['Pô']='Pôwersm:BAAALgADCgMJAwAAAA==.',
Qu='Quiet:BAAALgAECgQJBAAAAA==.Quilian:BAACLgAFFH8UAAITAAQJ3yVGCACuAQATAAQJ3yVGCACuAQAuAAQKfyYAAhMACQlAISkEABIDABMACQlAISkEABIDAAAA.',
Ra='Raelynn:BAABLgAECn9DAAITAAgJ5Bv2DQB6AgATAAgJ5Bv2DQB6AgAAAA==.Raevenhart:BAACLgAFFH8GAAIVAAMJlgh1HACwAAAVAAMJlgh1HACwAAAuAAQKfx0AAhUACAlZFWIkAAUCABUACAlZFWIkAAUCAAAA.Rainstorm:BAAALgADCgQJBAAAAA==.Rappa:BAAALgADCgEJAQAAAA==.Raptorx:BAAALgADCggJCAAAAA==.Raymond:BAAALgADCgcJBwAAAA==.Razerblade:BAAALgAECgEJAQAAAA==.',
Re='Rebarbative:BAABLgAECn8iAAMPAAkJoQ7WRwC+AQAPAAkJoQ7WRwC+AQAnAAMJfAXZUQB5AAAAAA==.Redvex:BAACLgAFFH8OAAIPAAQJXhh/PABFAQAPAAQJXhh/PABFAQAuAAQKf0UABA8ACQnFJesDAE4DAA8ACQmQJesDAE4DACcABQkxII8SALcBABEAAglwI6ohAJ8AAAAA.Rei:BAAALgAECgEJAQAAAA==.Reinhard:BAABLgAECn8xAAMOAAkJ3w9pXACuAQAOAAkJ8w5pXACuAQAlAAYJvRLtHQAaAQAAAA==.Revengè:BAAALgADCgQJBAAAAA==.Rewrew:BAABLgAECn8sAAIQAAkJhRryEQB6AgAQAAkJhRryEQB6AgAAAA==.',
Rh='Rhedman:BAABLgAECn8XAAMiAAYJQwqcGgDpAAAiAAUJQwqcGgDpAAAjAAYJdAVz4gDFAAAAAA==.',
Ri='Ricasti:BAAALgAECgUJCgAAAA==.Rinahrune:BAAALgAECgMJBgAAAA==.Rinahvoid:BAAALgADCgcJBwAAAA==.',
Ro='Robat:BAAALgADCggJDQAAAA==.Rosanna:BAAALgAECggJCgAAAA==.Roselyn:BAABLgAECn8VAAITAAcJaxGnKAB0AQATAAcJaxGnKAB0AQAAAA==.Rotyr:BAABLgAECn8uAAIKAAkJHxjeDQCEAgAKAAkJHxjeDQCEAgAAAA==.',
Ru='Ruana:BAEALgAECgQJDAAAAA==.Rubyrazor:BAAALgAECgQJBgAAAA==.Rumpunch:BAAALgAECgEJAQAAAA==.',
Sa='Safetydance:BAAALgAECgIJAgAAAA==.Salil:BAAALgADCgMJAwAAAA==.Salothos:BAAALgADCgYJBgAAAA==.Samesh:BAAALgAECgQJCAAAAA==.Sandrace:BAAALgADCgIJAgAAAA==.Sanginie:BAAALgADCgEJAQAAAA==.Santhela:BAAALgADCgYJBQAAAA==.Satrana:BAAALgADCgMJAwAAAA==.Saturñ:BAAALgAECgYJCgAAAA==.Sauroman:BAAALgAECgUJDgAAAA==.',
Sc='Scoobey:BAABLgAECn8fAAIUAAcJoRyARgDCAQAUAAcJoRyARgDCAQAAAA==.Scubbs:BAACLgAFFH8UAAIEAAQJrRTELQAUAQAEAAQJrRTELQAUAQAuAAQKfyEAAgQACAkuFkkiABECAAQACAkuFkkiABECAAAA.Scubbsboo:BAABLgAECn8ZAAIWAAcJqBsYGgAzAgAWAAcJqBsYGgAzAgABLgAFFAQJFAAEAK0UAA==.',
Se='Seras:BAAALgAECgUJBQAAAA==.Servantes:BAABLgAECn9AAAMXAAgJGREqQgB/AQAXAAgJGREqQgB/AQAFAAEJTwVllgAjAAAAAA==.',
Sh='Shackleford:BAABLgAECn89AAQKAAgJwR7lEQAmAgAKAAcJtR/lEQAmAgAJAAgJpRbTGQDvAQATAAcJLBNnKgBoAQAAAA==.Shamwõwz:BAAALgAFFAMJBAAAAA==.Sheck:BAAALgAECgEJAQAAAA==.Shessofine:BAAALgAECggJCgAAAA==.Shotya:BAABLgAECn9DAAIUAAgJPguYYAB5AQAUAAgJPguYYAB5AQAAAA==.Shyvàna:BAAALgAECgIJAgAAAA==.',
Si='Siath:BAABLgAECn8UAAMGAAgJ6wtCPQAqAQAGAAgJ6wtCPQAqAQAmAAIJ6gg7PQA5AAAAAA==.Silvino:BAAALgADCgEJAQABLgAECgkJLAAFAMAbAA==.Sixpacktnt:BAAALgADCgcJIAAAAA==.Sixthknight:BAABLgAECn8UAAIOAAYJIAcW4ADRAAAOAAYJIAcW4ADRAAAAAA==.',
Sl='Slarr:BAAALgADCgEJAgAAAA==.',
Sm='Smight:BAABLgAECn8eAAIQAAgJXyYuBABQAwAQAAgJXyYuBABQAwAAAA==.',
Sn='Snacky:BAAALgAECgEJAQAAAA==.Snarkypony:BAAALgAECgYJDgAAAA==.',
So='Solani:BAAALgADCgYJCQAAAA==.Solania:BAAALgAECgYJCgAAAA==.Soloqenjoyer:BAAALgAECgUJBQAAAA==.Sorocide:BAAALgADCgUJBQAAAA==.Sorsere:BAABLgAECn81AAIPAAkJcR16EgCzAgAPAAkJcR16EgCzAgAAAA==.',
Sp='Spcecialk:BAABLgAECn8dAAIZAAcJLQs0JgDzAAAZAAcJLQs0JgDzAAAAAA==.Specialk:BAABLgAECn8+AAMcAAgJSRKoLwBzAQAcAAgJSRKoLwBzAQAEAAMJrAbnpwBmAAAAAA==.',
Sq='Squallie:BAABLgAECn8VAAIXAAYJqRMdTQBQAQAXAAYJqRMdTQBQAQAAAA==.',
St='Steamedhams:BAAALgAECgcJCwAAAA==.Stirredihime:BAAALgAECgUJCgAAAA==.Stromm:BAACLgAFFH8MAAIDAAYJ0wiTNgA0AQADAAYJ0wiTNgA0AQAuAAQKfxsAAgMACAkeFu1QAIcBAAMACAkeFu1QAIcBAAAA.',
Su='Sundorei:BAAALgAECgQJBgAAAA==.',
['Sû']='Sûlph:BAAALgAECgkJAwAAAA==.',
Ta='Taartt:BAAALgAFFAQJBAABLgAFFAYJJgABABYWAA==.Tahoe:BAAALgADCgIJAgAAAA==.Talan:BAAALgAECgcJCgABLgAFFAYJDAADANMIAA==.Talshekar:BAABLgAECn8lAAImAAgJsw0YCgByAQAmAAgJsw0YCgByAQAAAA==.Tarsis:BAABLgAECn8eAAINAAgJ/BpGDgAaAgANAAgJ/BpGDgAaAgAAAA==.',
Te='Teiana:BAABLgAECn8pAAIOAAkJ9x+pIAB6AgAOAAkJ9x+pIAB6AgAAAA==.Tezlyn:BAAALgAECgEJAgAAAA==.',
Th='Thaevin:BAABLgAECn8fAAIOAAgJpBQrWwCxAQAOAAgJpBQrWwCxAQAAAA==.Therony:BAAALgAECgkJBQAAAA==.Thingwan:BAACLgAFFH8IAAIXAAQJKRjOIwAvAQAXAAQJKRjOIwAvAQAuAAQKfzUAAhcACQk4G7YPAM0CABcACQk4G7YPAM0CAAAA.Thordak:BAAALgADCggJDQABLgAECggJGwAOADsRAA==.',
Ti='Timbuktoo:BAAALgAECgQJBgAAAA==.Tinypoop:BAABLgAECn8WAAICAAYJVBVepwAqAQACAAYJVBVepwAqAQAAAA==.Tinystain:BAAALgADCgcJDQAAAA==.Tinystink:BAABLgAECn8XAAIPAAgJOx1FIABdAgAPAAgJOx1FIABdAgAAAA==.Tiptugger:BAAALgAECgIJAgAAAA==.',
To='Toddstephens:BAABLgAECn8eAAIiAAYJ2BbSEABWAQAiAAYJ2BbSEABWAQAAAA==.Tors:BAACLgAFFH8KAAIFAAMJxwxdLwCwAAAFAAMJxwxdLwCwAAAuAAQKf00AAwUACQkhHY8JALICAAUACQkhHY8JALICAAcAAgnYE8pIAG8AAAAA.',
Tr='Trogdore:BAAALgAECgYJDQAAAA==.Trollololo:BAABLgAECn9BAAMCAAgJUBqUOQAsAgACAAgJUBqUOQAsAgAoAAMJ+wfsCgCPAAAAAA==.Troy:BAABLgAECn8pAAICAAkJXx6uIQCRAgACAAkJXx6uIQCRAgAAAA==.Truid:BAAALgADCgEJAQAAAA==.Trylly:BAAALgAECgYJCAABLgAECggJDgALAAAAAA==.',
Tt='Ttaartt:BAACLgAFFH8mAAMBAAYJFharDAC9AQABAAYJFharDAC9AQAGAAQJyxC8OwDGAAAuAAQKfx0AAgEABwmqGfESABICAAEABwmqGfESABICAAAA.',
Tu='Tuckstaken:BAAALgAECgIJAgAAAA==.',
Ty='Typh:BAACLgAFFH8WAAIgAAQJ2yCeAgB+AQAgAAQJ2yCeAgB+AQAuAAQKf0QAAiAACQm5JWYAAGEDACAACQm5JWYAAGEDAAAA.Tyr:BAAALgAECgMJBQAAAA==.Tyrone:BAABLgAECn8kAAMaAAkJcRqnDABwAgAaAAkJcRqnDABwAgAWAAQJABCnbAC0AAAAAA==.Tyrslan:BAAALgAECgYJCwAAAA==.',
Uf='Uffish:BAAALgAECgkJCQAAAQ==.',
Ug='Uglymagi:BAAALgAECgMJBAAAAA==.',
Un='Undeaddemon:BAABLgAECn8jAAQPAAkJJR1iNgD6AQAPAAgJJR1iNgD6AQARAAMJEQ8THwB4AAAnAAEJkAbJeAAqAAAAAA==.Undeaddh:BAAALgAECgIJAgABLgAECgkJIwAPACUdAA==.Undeadmaggot:BAAALgADCggJFAABLgAECgkJIwAPACUdAA==.Undeadscaly:BAAALgAECgYJBwABLgAECgkJIwAPACUdAA==.Undignified:BAABLgAECn89AAIgAAkJURbfBAAuAgAgAAkJURbfBAAuAgAAAA==.Unholysixth:BAAALgADCgkJLQAAAA==.Unicornquen:BAAALgAECgEJAQAAAA==.',
Ur='Uriyah:BAAALgAECgEJAQAAAA==.',
Uz='Uzzìel:BAAALgADCgEJAQAAAA==.',
Va='Valkar:BAAALgAECgEJAQAAAA==.Vanidarr:BAAALgADCgEJAQAAAA==.',
Ve='Verasia:BAAALgAECgQJDwAAAA==.',
Vi='Vidikan:BAAALgAECgQJDwAAAA==.Vie:BAAALgAECgEJAQAAAA==.',
Vo='Voidwarranty:BAACLgAFFH8FAAIEAAMJAAskUgCaAAAEAAMJAAskUgCaAAAuAAQKfzQAAwQACQl0F6ggAD4CAAQACQl0F6ggAD4CABwABwmRFi8iAMUBAAAA.Vontoot:BAAALgADCgEJAQAAAA==.',
Vv='Vvumpscut:BAABLgAECn8eAAIEAAcJRRyaNgDIAQAEAAcJRRyaNgDIAQAAAA==.',
Vy='Vysena:BAAALgAECgEJAwAAAA==.',
Wa='Waldón:BAABLgAECn9JAAIoAAkJPg2SBACSAQAoAAkJPg2SBACSAQAAAA==.',
We='Werrik:BAABLgAECn8aAAIPAAkJXyX8IgCJAgAPAAkJXyX8IgCJAgABLgAFFAIJAgALAAAAAA==.',
Wh='Whiskeytap:BAAALgAECgIJAgAAAA==.',
Wi='Wildsoul:BAABLgAECn8jAAIEAAcJPxLrTQBqAQAEAAcJPxLrTQBqAQAAAA==.Winchester:BAAALgADCgMJAwAAAA==.',
Wo='Wolfguardiån:BAAALgADCgMJAwAAAA==.',
Wr='Wrenz:BAAALgAECgQJDAAAAA==.',
Wu='Wuha:BAAALgADCgEJAQAAAA==.',
['Wä']='Wärhämmer:BAAALgADCgcJCgAAAA==.',
Xa='Xaneva:BAAALgADCgEJAgABLgAFFAYJKQAIAPYiAA==.Xanxer:BAAALgADCgQJBQAAAA==.',
Xc='Xclaw:BAABLgAECn8aAAIMAAkJ+wpKGADaAQAMAAkJ+wpKGADaAQAAAA==.',
Xe='Xeroxgravîty:BAAALgAECgEJAQAAAA==.Xeroxpriest:BAAALgAECgcJCwAAAA==.',
Xi='Xilphira:BAAALgAECgQJBwAAAA==.',
Xl='Xlithz:BAABLgAECn8wAAMeAAkJHxsAFQBCAgAeAAkJFhsAFQBCAgAfAAgJPhI/GwB3AQAAAA==.',
['Xí']='Xílo:BAEBLgAECn9CAAMDAAgJVx8AMAD7AQADAAgJ1BkAMAD7AQASAAYJtx6tFgDBAQAAAA==.',
Yl='Ylene:BAABLgAECn8mAAIXAAgJqBFKOACsAQAXAAgJqBFKOACsAQAAAA==.',
Yo='Yoink:BAACLgAFFH8TAAIjAAQJkxqzRwBSAQAjAAQJkxqzRwBSAQAuAAQKfzsAAiMACQk7JDsHADUDACMACQk7JDsHADUDAAAA.',
Za='Zalasham:BAAALgADCgIJAgAAAA==.Zarinchaos:BAAALgAECgUJBwAAAA==.Zarinfur:BAABLgAECn82AAIIAAkJHBkqBwBZAgAIAAkJHBkqBwBZAgAAAA==.',
Ze='Zedrin:BAAALgAECgQJBAAAAA==.Zein:BAAALgAECgQJCAAAAA==.Zentacle:BAAALgAECgIJAgAAAA==.Zente:BAACLgAFFH8IAAIUAAQJiAa9UQDvAAAUAAQJiAa9UQDvAAAuAAQKfycAAxQABwltGjVNAK4BABQABwltGjVNAK4BABUAAQn1AJGZABsAAAAA.Zequill:BAABLgAECn8+AAIZAAkJ7iL1AgAGAwAZAAkJ7iL1AgAGAwAAAA==.Zevsticles:BAABLgAECn8sAAIUAAkJUx+tIABZAgAUAAkJUx+tIABZAgAAAA==.',
Zh='Zhom:BAACLgAFFH8RAAIVAAQJnRzfDwBNAQAVAAQJnRzfDwBNAQAuAAQKfz8AAhUACQkcJFIBAAsDABUACQkcJFIBAAsDAAAA.',
Zo='Zohm:BAAALgADCgMJAwAAAA==.Zolec:BAAALgADCgcJDgAAAA==.Zooj:BAABLgAECn9CAAIpAAgJABoZCQAhAgApAAgJABoZCQAhAgAAAA==.Zorlak:BAAALgAECgUJDQAAAA==.',
Zu='Zuxa:BAAALgADCgYJBgAAAA==.',
Zy='Zylofeather:BAAALgAECgQJBAAAAA==.',
['ße']='ßeast:BAABLgAECn8jAAIaAAgJiwk2NAAmAQAaAAgJiwk2NAAmAQAAAA==.',
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
